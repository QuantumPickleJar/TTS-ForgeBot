using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Options;
using MtgTtsBridge;
using MtgTtsBridge.Contracts.Actions;
using MtgTtsBridge.Contracts.Events;
using MtgTtsBridge.Contracts.State;
using MtgTtsBridge.Diagnostics;

namespace MtgTtsBridge.Forge;

internal sealed class ForgeGameEndedException : Exception;

/// <summary>Supervises a locally configured Forge TUI process. Forge remains authoritative for every game decision.</summary>
public sealed class ForgeTuiAdapter : IForgeAdapter, IAsyncDisposable
{
    private readonly object _sync = new();
    private readonly ForgeTuiOptions _options;
    private readonly ILogger<ForgeTuiAdapter> _logger;
    private readonly ForgeTuiParser _parser;
    private readonly ForgeTuiEventParser _eventParser;
    private readonly ForgeStructuredOutputParser _structuredParser;
    private readonly ForgeStructuredStateReconciler _structuredState;
    private readonly ForgeStartupTracker _startupTracker;
    private readonly DiagnosticTelemetryBuffer? _telemetry;
    private readonly SemaphoreSlim _sessionStartGate = new(1, 1);
    // A TUI decision is a one-shot transaction. Keep the winning action after
    // it is consumed so duplicate HTTP delivery can be acknowledged without a
    // second stdin write, while a conflicting action remains a hard reject.
    private readonly Dictionary<string, ResolvedChoice> _resolvedChoices = new(StringComparer.Ordinal);
    private readonly Dictionary<string, SeenDecision> _seenDecisions = new(StringComparer.Ordinal);
    private readonly Queue<string> _seenDecisionOrder = new();
    private Process? _process;
    private CancellationTokenSource? _processCancellation;
    // A cancelled reader can still return a buffered chunk after NEW MATCH.
    // Only the reader generation that created the current process may mutate
    // parser/reconciler/session state.
    private long _processGeneration;
    private Task? _stdoutReaderTask;
    private TaskCompletionSource<ForgeTuiDecision>? _nextDecision;
    private DecisionDto? _currentDecision;
    private IReadOnlyDictionary<string, string>? _currentInputs;
    private string _sessionId = "session-not-started";
    private string _state = "not_started";
    private string? _diagnosticCode;
    private string? _diagnosticMessage;
    private string? _diagnosticContext;
    private readonly List<AuthoritativeEventDto> _events = [];
    private readonly HashSet<string> _landCardInstanceIds = new(StringComparer.Ordinal);
    private readonly Dictionary<string, int> _inheritedHumanDecisionKinds = new(StringComparer.Ordinal);
    private readonly Queue<string> _recentControllerDiagnostics = new();
    private readonly string? _opponentSeatId;
    private string? _humanDeckPath;
    private string? _aiDeckPath;
    private long _latestEventSequence;
    private string _lastObservedTuiText = string.Empty;
    private int? _latestObservedTurnNumber;
    private string? _latestObservedPhaseName;
    private string? _latestObservedPrioritySeatId;
    private string? _latestObservedActiveSeatId;
    private long? _latestObservedForgeSequence;

    private const int EventHistoryLimit = 512;
    private const int DecisionHistoryLimit = 128;

    public ForgeTuiAdapter(IOptions<ForgeTuiOptions> options, ILogger<ForgeTuiAdapter> logger, DiagnosticTelemetryBuffer? telemetry = null)
    {
        _options = options.Value;
        _logger = logger;
        _telemetry = telemetry;
        _startupTracker = new ForgeStartupTracker(logger);
        _opponentSeatId = _options.PlayerSeats.Values.FirstOrDefault(seatId => !string.Equals(seatId, _options.HumanSeatId, StringComparison.Ordinal));
        _parser = new ForgeTuiParser(_options.PlayerSeats, _opponentSeatId ?? "forge-player-2");
        _eventParser = new ForgeTuiEventParser(_options.PlayerSeats, _opponentSeatId ?? "forge-player-2");
        _structuredParser = new ForgeStructuredOutputParser();
        _structuredState = new ForgeStructuredStateReconciler();
    }

    public string Name => "ForgeTuiAdapter";

    public async Task ConfigureDecksAsync(DeckLoadRequestDto request, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var human = request.Seats.SingleOrDefault(seat => seat.SeatId == _options.HumanSeatId)
            ?? throw new InvalidOperationException($"Deck inventory has no {_options.HumanSeatId} seat.");
        var aiSeatId = _opponentSeatId ?? "forge-player-2";
        var ai = request.Seats.SingleOrDefault(seat => seat.SeatId == aiSeatId)
            ?? throw new InvalidOperationException($"Deck inventory has no {aiSeatId} seat.");

        var directory = Path.Combine(Path.GetTempPath(), "MtgTtsBridge", "decks");
        Directory.CreateDirectory(directory);
        var humanPath = Path.Combine(directory, "tts-human.dck");
        var aiPath = Path.Combine(directory, "tts-ai.dck");
        await WriteDeckAsync(humanPath, human.Cards, cancellationToken).ConfigureAwait(false);
        await WriteDeckAsync(aiPath, ai.Cards, cancellationToken).ConfigureAwait(false);
        lock (_sync)
        {
            _humanDeckPath = humanPath;
            _aiDeckPath = aiPath;
        }
        _logger.LogInformation("Accepted TTS library deck inventories: humanCards={HumanCards} aiCards={AiCards}",
            human.Cards.Sum(card => card.Count), ai.Cards.Sum(card => card.Count));
    }

    public Task<AdapterStateDto> GetStateAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_sync) return Task.FromResult(CreateState());
    }

    public Task<EventBatchDto> GetEventsAsync(long afterSequence, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_sync)
        {
            var oldest = _events.Count == 0 ? _latestEventSequence + 1 : _events[0].Sequence;
            var hasGap = _events.Count > 0 && afterSequence < oldest - 1;
            var events = hasGap
                ? []
                : _events.Where(item => item.Sequence > afterSequence).ToArray();
            return Task.FromResult(new EventBatchDto(afterSequence, oldest, _latestEventSequence, hasGap, events));
        }
    }

    public Task<GameSnapshotDto?> GetSnapshotAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_sync)
        {
            var snapshot = _structuredState.Current;
            if (snapshot is null) return Task.FromResult<GameSnapshotDto?>(null);
            GameCardSnapshotDto Annotate(GameCardSnapshotDto card) => card with
            {
                // Preserve structured currentTypes for cards already known to
                // be on the battlefield. The event-derived land set is only a
                // compatibility fallback for older producer frames.
                BattlefieldKind = card.BattlefieldKind
                    ?? (_landCardInstanceIds.Contains(card.CardInstanceId) ? "land" : null)
            };
            return Task.FromResult<GameSnapshotDto?>(snapshot with
            {
                EventCursor = _latestEventSequence,
                Seats = snapshot.Seats.Select(seat => seat with
                {
                    Zones = seat.Zones.Select(zone => zone with
                    {
                        Cards = zone.Cards.Select(Annotate).ToArray()
                    }).ToArray()
                }).ToArray(),
                Stack = snapshot.Stack.Select(Annotate).ToArray()
            });
        }
    }

    public async Task<AdapterStateDto> StartSessionAsync(CancellationToken cancellationToken)
    {
        ValidateConfiguration();
        await _sessionStartGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            lock (_sync)
            {
                if (_state == "starting" && _process is not null)
                {
                    _logger.LogInformation("Forge startup is already in progress for session {SessionId}; returning the current state without restarting.", _sessionId);
                    return CreateState();
                }

                if (HasHealthyProcess())
                {
                    _logger.LogInformation("Attaching session start request to active Forge session {SessionId}", _sessionId);
                    return CreateState();
                }
            }

            await StopProcessAsync().ConfigureAwait(false);
            return await StartNewSessionAsync(cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            _sessionStartGate.Release();
        }
    }

    public async Task<AdapterStateDto> ResetSessionAsync(CancellationToken cancellationToken)
    {
        ValidateConfiguration();
        await _sessionStartGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            _logger.LogInformation("Explicitly replacing active Forge session {SessionId}", _sessionId);
            await StopProcessAsync().ConfigureAwait(false);
            return await StartNewSessionAsync(cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            _sessionStartGate.Release();
        }
    }

    private async Task<AdapterStateDto> StartNewSessionAsync(CancellationToken cancellationToken)
    {

        var startInfo = new ProcessStartInfo
        {
            FileName = _options.Executable,
            Arguments = RenderArguments(),
            WorkingDirectory = _options.WorkingDirectory,
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = !_options.ShowConsoleWindow,
        };

        var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
        var cancellation = new CancellationTokenSource();
        TaskCompletionSource<ForgeTuiDecision> initialDecision;
        long processGeneration;

        lock (_sync)
        {
            _startupTracker.Reset();
            _parser.Reset();
            _eventParser.Reset();
            _structuredParser.Reset();
            _structuredState.Reset();
            _events.Clear();
            _landCardInstanceIds.Clear();
            _inheritedHumanDecisionKinds.Clear();
            _recentControllerDiagnostics.Clear();
            _latestEventSequence = 0;
            _latestObservedTurnNumber = null;
            _latestObservedPhaseName = null;
            _latestObservedPrioritySeatId = null;
            _latestObservedActiveSeatId = null;
            _latestObservedForgeSequence = null;
            _resolvedChoices.Clear();
            _seenDecisions.Clear();
            _seenDecisionOrder.Clear();
            _sessionId = Guid.NewGuid().ToString("N");
            _state = "starting";
            _currentDecision = null;
            _currentInputs = null;
            _diagnosticCode = null;
            _diagnosticMessage = null;
            _diagnosticContext = null;
            _process = process;
            _processCancellation = cancellation;
            processGeneration = ++_processGeneration;
            initialDecision = NewDecisionWaiter();
        }

        process.Exited += (_, _) => _ = HandleProcessExitAsync(process, processGeneration, process.ExitCode);
        if (!process.Start())
        {
            throw new InvalidOperationException("Forge TUI process could not be started.");
        }

        lock (_sync) _startupTracker.MarkProcessLaunched();

        _logger.LogInformation("Started Forge TUI process {ProcessId}: {Executable} (TTS library decks, Legacy assumption)", process.Id, _options.Executable);
        lock (_sync) _stdoutReaderTask = ReadOutputAsync(process, processGeneration, process.StandardOutput, isError: false, cancellation.Token);
        _ = ReadOutputAsync(process, processGeneration, process.StandardError, isError: true, cancellation.Token);

        try
        {
            var decision = await WaitForDecisionAsync(initialDecision, _options.StartupTimeoutSeconds, cancellationToken, "startup").ConfigureAwait(false);
            SetDecision(decision);
            return CreateState();
        }
        catch (ForgeUnsupportedPromptException)
        {
            return CreateState();
        }
        catch
        {
            await StopProcessAsync().ConfigureAwait(false);
            throw;
        }
    }

    public async Task<ForgeChoiceResult> SubmitChoiceAsync(ChoiceRequestDto request, CancellationToken cancellationToken)
    {
        TaskCompletionSource<ForgeTuiDecision> waiter;
        string forgeInput = string.Empty;
        Process? process;
        DecisionDto? decisionForRequest;
        LegalActionDto? currentActionForRequest;
        lock (_sync)
        {
            decisionForRequest = _currentDecision;
            var currentDecisionId = _currentDecision?.DecisionId;
            var currentAction = _currentDecision?.Actions.FirstOrDefault(action =>
                string.Equals(action.ActionId, request.ActionId, StringComparison.Ordinal));
            currentActionForRequest = currentAction;
            var isCollectionToggle = IsCollectionDecision(_currentDecision)
                && currentAction is not null
                && !string.Equals(currentAction.Type, "choose_none", StringComparison.Ordinal);
            ResolvedChoice? resolvedChoice = null;
            var resolvedAlready = !isCollectionToggle
                && _resolvedChoices.TryGetValue(request.DecisionId, out resolvedChoice);
            _logger.LogInformation(
                "CHOICE_REQUEST requestId={RequestId} clientRuntimeId={ClientRuntimeId} clientRevision={ClientRevision} source={Source} requestSessionId={RequestSessionId} serverSessionId={ServerSessionId} decision={DecisionId} action={ActionId} currentDecision={CurrentDecisionId} state={State} resolvedAlready={ResolvedAlready} previouslyAcceptedAction={PreviouslyAcceptedAction}",
                request.RequestId ?? "(missing)",
                request.ClientRuntimeId ?? "(missing)",
                request.ClientRevision ?? "(missing)",
                request.Source ?? "(missing)",
                request.SessionId ?? "(missing)",
                _sessionId ?? "(none)",
                request.DecisionId,
                request.ActionId,
                currentDecisionId ?? "(none)",
                _state,
                resolvedAlready,
                resolvedChoice?.ActionId ?? "(none)");

            if (!string.Equals(request.SessionId, _sessionId, StringComparison.Ordinal))
            {
                LogChoiceRejection(request, "WRONG_SESSION", currentDecisionId);
                return Reject(
                    "stale_session",
                    "The provided choice belongs to a different Forge session.",
                    expectedSessionId: _sessionId,
                    receivedSessionId: request.SessionId);
            }

            // This check deliberately precedes the no-pending-decision check.
            // The first request clears _currentDecision before waiting for
            // Forge, so a second delivery must resolve against this ledger.
            if (resolvedAlready)
            {
                if (string.Equals(request.ActionId, resolvedChoice!.ActionId, StringComparison.Ordinal))
                {
                    _logger.LogInformation(
                        "Forge choice duplicate accepted idempotently decision={DecisionId} action={ActionId} transactionState={TransactionState}",
                        request.DecisionId,
                        request.ActionId,
                        resolvedChoice.State);
                    return new ForgeChoiceResult(true, CreateState(), null, null);
                }

                LogChoiceRejection(request, "RESOLVED_THIS_SESSION", currentDecisionId);
                return Reject(
                    "decision_already_resolved",
                    "The provided decisionId was already resolved with a different action.");
            }

            if (_currentDecision is null || _currentInputs is null)
            {
                LogChoiceRejection(request, ClassifyDecision(request.DecisionId), currentDecisionId);
                return Reject("no_pending_decision", "No Forge TUI decision is currently active.");
            }
            if (!string.Equals(request.DecisionId, _currentDecision.DecisionId, StringComparison.Ordinal))
            {
                LogChoiceRejection(request, ClassifyDecision(request.DecisionId), currentDecisionId);
                return Reject("unknown_decision_id", "The provided decisionId is unknown for the current session state.");
            }
            if (!_currentInputs.TryGetValue(request.ActionId, out var mappedInput) || mappedInput is null)
            {
                LogChoiceRejection(request, "CURRENT", currentDecisionId);
                return Reject("unknown_action_id", "The provided actionId is not legal for this Forge TUI decision.");
            }
            forgeInput = mappedInput;
            process = _process;
            if (process is null || process.HasExited)
            {
                return Reject("forge_process_exited", "The Forge TUI process exited before the choice could be submitted.");
            }
            if (!isCollectionToggle)
            {
                _resolvedChoices.Add(_currentDecision.DecisionId, new ResolvedChoice(request.ActionId, "awaiting_forge"));
                MarkDecisionResolved(_currentDecision.DecisionId, request.ActionId);
            }
            else
            {
                _logger.LogDebug("Forge collection toggle remains in the same logical decision decision={DecisionId} action={ActionId}",
                    request.DecisionId, request.ActionId);
            }
            _currentDecision = null;
            _currentInputs = null;
            _state = "awaiting_forge";
            waiter = NewDecisionWaiter();
        }

        _logger.LogInformation("Forge TUI stdin action={ActionId} input={ForgeInput}", request.ActionId, forgeInput);
        if (currentActionForRequest is not null && string.Equals(currentActionForRequest.Type, "choose_none", StringComparison.Ordinal)
            && IsCollectionDecision(decisionForRequest))
        {
            _parser.CompleteCollectionDecision();
        }
        try
        {
            await process.StandardInput.WriteLineAsync(forgeInput).ConfigureAwait(false);
            await process.StandardInput.FlushAsync().ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is IOException or InvalidOperationException)
        {
            lock (_sync)
            {
                if (_resolvedChoices.TryGetValue(request.DecisionId, out var choice))
                {
                    _resolvedChoices[request.DecisionId] = choice with { State = "write_failed" };
                }
            }
            return Reject("forge_process_exited", $"Forge TUI stdin write failed: {ex.Message}");
        }

        try
        {
            var decision = await WaitForDecisionAsync(waiter, _options.DecisionTimeoutSeconds, cancellationToken, "decision").ConfigureAwait(false);
            SetDecision(decision);
            lock (_sync)
            {
                if (_resolvedChoices.TryGetValue(request.DecisionId, out var choice))
                {
                    _resolvedChoices[request.DecisionId] = choice with { State = "accepted" };
                }
            }
            return new ForgeChoiceResult(true, CreateState(), null, null);
        }
        catch (ForgeGameEndedException)
        {
            return new ForgeChoiceResult(true, CreateState(), null, null);
        }
        catch (ForgeUnsupportedPromptException ex)
        {
            return Reject("unsupported_decision", ex.Message);
        }
        catch (TimeoutException ex)
        {
            Fail("decision_timeout", ex.Message);
            await StopProcessAsync().ConfigureAwait(false);
            return Reject("decision_timeout", ex.Message);
        }
        catch (InvalidOperationException ex)
        {
            return Reject("forge_process_exited", ex.Message);
        }
    }

    private sealed record ResolvedChoice(string ActionId, string State);
    private sealed record SeenDecision(DateTimeOffset FirstPresentedAtUtc, string? ResolvedActionId, DateTimeOffset? ResolvedAtUtc);

    private bool IsCurrentProcessGeneration(Process process, long processGeneration)
    {
        lock (_sync) return ReferenceEquals(_process, process) && _processGeneration == processGeneration;
    }

    private async Task ReadOutputAsync(Process process, long processGeneration, StreamReader reader, bool isError, CancellationToken cancellationToken)
    {
        var buffer = new char[1024];
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                var count = await reader.ReadAsync(buffer.AsMemory(0, buffer.Length), cancellationToken).ConfigureAwait(false);
                if (count == 0) return;
                var chunk = new string(buffer, 0, count);
                if (!IsCurrentProcessGeneration(process, processGeneration))
                {
                    _logger.LogDebug("Discarded Forge output from retired process generation {Generation}", processGeneration);
                    return;
                }
                if (isError)
                {
                    foreach (var line in chunk.Split('\n'))
                    {
                        var normalized = line.TrimEnd('\r');
                        if (normalized.Length > 0) _telemetry?.RecordForgeOutput("stderr", normalized, _sessionId);
                    }
                    _logger.LogDebug("Forge TUI stderr: {ForgeOutput}", chunk);
                    continue;
                }
                foreach (var line in chunk.Split('\n'))
                {
                    var normalized = line.TrimEnd('\r');
                    if (normalized.Length > 0) _telemetry?.RecordForgeOutput("stdout", normalized, _sessionId);
                }
                ForgeTuiParserResult result;
                lock (_sync)
                {
                    if (!ReferenceEquals(_process, process) || _processGeneration != processGeneration) return;
                    var output = _structuredParser.Append(chunk);
                    foreach (var snapshot in output.Snapshots)
                    {
                        _latestObservedForgeSequence = snapshot.Sequence;
                        foreach (var rawEvent in _structuredState.Apply(_sessionId, snapshot)) EnqueueEvent(rawEvent);
                        if (_structuredState.Current?.Result is not null) MarkGameEnded(_structuredState.Current.Result);
                        _logger.LogTrace(
                            "Forge structured snapshot {ForgeSequence} ({Reason}); hidden payload redacted",
                            snapshot.Sequence,
                            snapshot.Reason);
                    }

                    var tuiText = output.TuiText;
                    if (tuiText.Length > 0)
                    {
                        _lastObservedTuiText = tuiText.Length > 8192 ? tuiText[^8192..] : tuiText;
                        foreach (var diagnosticEvent in ObserveControllerDiagnostics(tuiText)) EnqueueEvent(diagnosticEvent);
                        _logger.LogTrace("Forge TUI stdout: {ForgeOutput}", tuiText);
                        _startupTracker.Observe(tuiText);
                        foreach (var rawEvent in _eventParser.Append(tuiText))
                        {
                            // A TUI display name is not a seat identity.  A
                            // no-seat text event cannot safely move a TTS
                            // object, and structured snapshots carry the
                            // authoritative exact card/controller mapping.
                            if (rawEvent.SeatId is null)
                            {
                                _logger.LogWarning(
                                    "Dropped unscoped Forge TUI event {Kind}; waiting for structured state. Summary={Summary}",
                                    rawEvent.Kind,
                                    rawEvent.Summary);
                                continue;
                            }
                            // Structured snapshots currently do not carry
                            // turn/phase/priority state. Keep the continuous
                            // Forge TUI authority for those transitions until
                            // an equivalent structured contract exists.
                            if (_structuredState.Current is not null
                                && rawEvent.Kind is "player_state" or "card_moved") continue;
                            EnqueueEvent(rawEvent);
                        }
                    }
                    result = _parser.Append(tuiText);
                }
                var stopForParserFailure = false;
                lock (_sync)
                {
                    if (!ReferenceEquals(_process, process) || _processGeneration != processGeneration) return;
                    if (result.ParsedDecision is not null)
                    {
                        var parsed = result.ParsedDecision;
                        _logger.LogInformation(
                            "Forge TUI parsed decision {DecisionId} kind={Kind} prompt={Prompt} actions={ActionCount}",
                            parsed.Decision.DecisionId,
                            parsed.Decision.Kind,
                            parsed.Decision.Prompt ?? "(none)",
                            parsed.Decision.Actions.Count);
                        _nextDecision?.TrySetResult(parsed);
                    }
                    if (result.UnsupportedPrompt is not null)
                    {
                        _logger.LogWarning(
                            "Forge TUI unsupported prompt {Code}; context={Context}",
                            result.UnsupportedPrompt.Code,
                            result.UnsupportedPrompt.Context);
                        SetUnsupportedPrompt(result.UnsupportedPrompt);
                    }
                    if (result.ErrorCode is not null)
                    {
                        _logger.LogError(
                            "Forge TUI parser error {Code}: {Message}",
                            result.ErrorCode,
                            result.ErrorMessage);
                        Fail(result.ErrorCode, result.ErrorMessage!);
                        stopForParserFailure = true;
                    }
                }
                if (stopForParserFailure) _ = StopProcessAsync(processGeneration);
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { }
        catch (ForgeStructuredDuplicateCardInstanceException ex)
        {
            if (IsCurrentProcessGeneration(process, processGeneration)) Fail("duplicate_structured_card_instance_id", ex.Message);
        }
        catch (Exception ex)
        {
            if (IsCurrentProcessGeneration(process, processGeneration)) Fail("forge_output_failure", ex.Message);
        }
    }

    private TaskCompletionSource<ForgeTuiDecision> NewDecisionWaiter()
    {
        _nextDecision = new(TaskCreationOptions.RunContinuationsAsynchronously);
        return _nextDecision;
    }

    private async Task<ForgeTuiDecision> WaitForDecisionAsync(TaskCompletionSource<ForgeTuiDecision> waiter, int seconds, CancellationToken cancellationToken, string operation)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(Math.Max(1, seconds)));
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeout.Token);
        try { return await waiter.Task.WaitAsync(linked.Token).ConfigureAwait(false); }
        catch (OperationCanceledException) when (timeout.IsCancellationRequested)
        {
            throw new TimeoutException($"Forge TUI did not present a supported {operation} decision within {seconds} seconds.");
        }
    }

    private void SetDecision(ForgeTuiDecision decision)
    {
        lock (_sync)
        {
            if (_currentDecision is null && _state == "starting") _startupTracker.MarkFirstDecision();
            string? NormalizeInstanceId(string? value) =>
                value is not null && value.StartsWith("forge-object:", StringComparison.Ordinal)
                    ? $"forge:{_sessionId}:{value["forge-object:".Length..]}"
                    : value;
            var actions = decision.Decision.Actions.Select(action => action with
            {
                CardInstanceId = NormalizeInstanceId(action.CardInstanceId),
                SourceCardInstanceId = NormalizeInstanceId(action.SourceCardInstanceId),
                PreparedSourceCardInstanceId = NormalizeInstanceId(action.PreparedSourceCardInstanceId)
            }).ToArray();

            var inputs = decision.Inputs.ToDictionary(kvp => kvp.Key, kvp => kvp.Value, StringComparer.Ordinal);

            _currentDecision = decision.Decision with { SeatId = _options.HumanSeatId, Actions = actions };
            _currentDecision = _currentDecision with
            {
                SourceCardInstanceId = NormalizeInstanceId(_currentDecision.SourceCardInstanceId),
                ContextCardInstanceId = NormalizeInstanceId(_currentDecision.ContextCardInstanceId),
                SessionId = _sessionId,
                EventCursor = _latestEventSequence,
                ForgeSequence = _latestObservedForgeSequence ?? _structuredState.Current?.ForgeSequence,
                TurnNumber = _latestObservedTurnNumber,
                ActiveSeatId = _latestObservedActiveSeatId,
                PrioritySeatId = _latestObservedPrioritySeatId,
                PhaseName = _latestObservedPhaseName,
            };
            _currentInputs = inputs;
            _state = "awaiting_human_decision";
            RecordDecisionPresented(_currentDecision.DecisionId);
            _logger.LogInformation(
                "DECISION_PRESENTED session={SessionId} decision={DecisionId} state={State}",
                _sessionId,
                _currentDecision.DecisionId,
                _state);
        }
    }

    private void RecordDecisionPresented(string decisionId)
    {
        if (_seenDecisions.ContainsKey(decisionId)) return;

        _seenDecisions.Add(decisionId, new SeenDecision(DateTimeOffset.UtcNow, null, null));
        _seenDecisionOrder.Enqueue(decisionId);
        while (_seenDecisionOrder.Count > DecisionHistoryLimit)
        {
            _seenDecisions.Remove(_seenDecisionOrder.Dequeue());
        }
    }

    private void MarkDecisionResolved(string decisionId, string actionId)
    {
        if (_seenDecisions.TryGetValue(decisionId, out var seen))
        {
            _seenDecisions[decisionId] = seen with
            {
                ResolvedActionId = actionId,
                ResolvedAtUtc = DateTimeOffset.UtcNow
            };
        }
    }

    private string ClassifyDecision(string decisionId)
    {
        if (string.Equals(_currentDecision?.DecisionId, decisionId, StringComparison.Ordinal)) return "CURRENT";
        if (_resolvedChoices.ContainsKey(decisionId)) return "RESOLVED_THIS_SESSION";
        return _seenDecisions.ContainsKey(decisionId) ? "SEEN_BUT_NOT_CURRENT" : "NEVER_SEEN_THIS_SESSION";
    }

    private void LogChoiceRejection(ChoiceRequestDto request, string classification, string? currentDecisionId)
    {
        _logger.LogWarning(
            "CHOICE_REJECTED requestId={RequestId} clientRuntimeId={ClientRuntimeId} requestSessionId={RequestSessionId} serverSessionId={ServerSessionId} decision={DecisionId} classification={Classification} currentDecision={CurrentDecisionId} adapterState={AdapterState} processInstance={ProcessInstance}",
            request.RequestId ?? "(missing)",
            request.ClientRuntimeId ?? "(missing)",
            request.SessionId ?? "(missing)",
            _sessionId,
            request.DecisionId,
            classification,
            currentDecisionId ?? "(none)",
            _state,
            BridgeProcessIdentity.InstanceId);
    }

    private void SetUnsupportedPrompt(ForgeTuiUnsupportedPrompt prompt)
    {
        lock (_sync)
        {
            _logger.LogWarning("Forge TUI paused on unsupported prompt {Code}: {Context}", prompt.Code, prompt.Context);
            _state = "unsupported_decision";
            _currentDecision = null;
            _currentInputs = null;
            _diagnosticCode = prompt.Code;
            _diagnosticMessage = prompt.Message;
            _diagnosticContext = prompt.Context;
            _nextDecision?.TrySetException(new ForgeUnsupportedPromptException(prompt.Message));
        }
    }

    private void EnqueueEvent(ForgeTuiRawEvent rawEvent)
    {
        if (IsDuplicateTransition(rawEvent)) return;
        _latestEventSequence++;
        var cardInstanceId = rawEvent.ForgeObjectId is null
            ? null
            : $"forge:{_sessionId}:{rawEvent.ForgeObjectId.Value}";
        var authoritativeEvent = new AuthoritativeEventDto(
            Sequence: _latestEventSequence,
            EventId: $"forge-event-{_sessionId}-{_latestEventSequence}",
            Kind: rawEvent.Kind,
            SeatId: rawEvent.SeatId,
            CardName: rawEvent.CardName,
            ForgeObjectId: rawEvent.ForgeObjectId,
            CardInstanceId: cardInstanceId,
            SourceZone: rawEvent.SourceZone,
            DestinationZone: rawEvent.DestinationZone,
            Summary: rawEvent.Summary,
            OccurredAtUtc: DateTimeOffset.UtcNow,
            LifeTotal: rawEvent.LifeTotal,
            PoisonCounters: rawEvent.PoisonCounters,
            CounterType: rawEvent.CounterType,
            CounterValue: rawEvent.CounterValue,
            Keyword: rawEvent.Keyword,
            Tapped: rawEvent.Tapped,
            ContainsHiddenIdentity: rawEvent.ContainsHiddenIdentity,
            ManaPool: rawEvent.ManaPool,
            Phase: rawEvent.Phase,
            TurnNumber: rawEvent.TurnNumber,
            ForgeSequence: rawEvent.ForgeSequence,
            ActiveSeatId: rawEvent.ActiveSeatId,
            PrioritySeatId: rawEvent.PrioritySeatId,
            NetPower: rawEvent.NetPower,
            NetToughness: rawEvent.NetToughness,
            CurrentPower: rawEvent.CurrentPower,
            CurrentToughness: rawEvent.CurrentToughness,
            CurrentTypes: rawEvent.CurrentTypes,
            CurrentCardName: rawEvent.CurrentCardName,
            OwnerSeatId: rawEvent.OwnerSeatId,
            ControllerSeatId: rawEvent.ControllerSeatId,
            FaceDown: rawEvent.FaceDown,
            PhasedOut: rawEvent.PhasedOut,
            Speed: rawEvent.Speed,
            Designations: rawEvent.Designations,
            MonarchSeatId: rawEvent.MonarchSeatId,
            WinnerSeatIds: rawEvent.WinnerSeatIds,
            LoserSeatIds: rawEvent.LoserSeatIds,
            GameEndReason: rawEvent.GameEndReason,
            Counters: rawEvent.Counters,
            BattlefieldKind: rawEvent.BattlefieldKind)
        {
            Characteristics = rawEvent.Characteristics
        };
        if (authoritativeEvent.Kind == "turn_changed")
        {
            _latestObservedTurnNumber = authoritativeEvent.TurnNumber ?? _latestObservedTurnNumber;
            _latestObservedActiveSeatId = authoritativeEvent.SeatId ?? authoritativeEvent.ActiveSeatId ?? _latestObservedActiveSeatId;
        }
        if (authoritativeEvent.Kind == "phase_changed" && authoritativeEvent.Phase is not null)
        {
            _latestObservedPhaseName = authoritativeEvent.Phase;
        }
        if (authoritativeEvent.Kind == "priority_changed")
        {
            _latestObservedPrioritySeatId = authoritativeEvent.PrioritySeatId ?? authoritativeEvent.SeatId ?? _latestObservedPrioritySeatId;
        }
        if (authoritativeEvent.Kind == "land_played" && cardInstanceId is not null)
        {
            _landCardInstanceIds.Add(cardInstanceId);
        }
        _events.Add(authoritativeEvent);
        if (_events.Count > EventHistoryLimit) _events.RemoveAt(0);
        _telemetry?.RecordForgeEvent(authoritativeEvent, _sessionId);
        if (authoritativeEvent.ContainsHiddenIdentity)
        {
            _logger.LogTrace(
                "Forge private event {Sequence} {Kind} seat={SeatId}; card identity redacted",
                authoritativeEvent.Sequence,
                authoritativeEvent.Kind,
                authoritativeEvent.SeatId);
        }
        else
        {
            _logger.LogDebug(
                "Forge event {Sequence} {Kind} seat={SeatId} card={CardName} instance={CardInstanceId}",
                authoritativeEvent.Sequence,
                authoritativeEvent.Kind,
                authoritativeEvent.SeatId,
                authoritativeEvent.CardName,
                authoritativeEvent.CardInstanceId);
        }
    }

    private bool IsDuplicateTransition(ForgeTuiRawEvent rawEvent)
    {
        if (rawEvent.Kind is not ("turn_changed" or "phase_changed" or "priority_changed")) return false;
        var previous = _events.LastOrDefault(item => item.Kind == rawEvent.Kind);
        if (previous is null) return false;

        var activeSeat = rawEvent.ActiveSeatId ?? rawEvent.SeatId;
        var previousActiveSeat = previous.ActiveSeatId ?? previous.SeatId;
        if (activeSeat is null || !string.Equals(activeSeat, previousActiveSeat, StringComparison.Ordinal)) return false;

        return rawEvent.Kind switch
        {
            "turn_changed" => rawEvent.TurnNumber == previous.TurnNumber,
            // A phase repeats on every turn (Main 1 is the important case),
            // so the phase alone is not a transition identity. Raw legacy
            // phase lines do not carry a turn number and must remain visible
            // rather than being guessed to be duplicates.
            "phase_changed" => rawEvent.TurnNumber is not null
                && previous.TurnNumber is not null
                && rawEvent.TurnNumber == previous.TurnNumber
                && string.Equals(rawEvent.Phase, previous.Phase, StringComparison.Ordinal),
            "priority_changed" => rawEvent.TurnNumber is not null
                && previous.TurnNumber is not null
                && rawEvent.TurnNumber == previous.TurnNumber
                && string.Equals(rawEvent.Phase, previous.Phase, StringComparison.Ordinal)
                && string.Equals(rawEvent.PrioritySeatId, previous.PrioritySeatId, StringComparison.Ordinal),
            _ => false,
        };
    }

    private IReadOnlyList<ForgeTuiRawEvent> ObserveControllerDiagnostics(string text)
    {
        var events = new List<ForgeTuiRawEvent>();
        foreach (var line in text.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            if (line.StartsWith("[TUI-INHERITED] kind=", StringComparison.Ordinal))
            {
                var remainder = line["[TUI-INHERITED] kind=".Length..];
                var end = remainder.IndexOf(' ');
                var kind = end < 0 ? remainder : remainder[..end];
                _inheritedHumanDecisionKinds[kind] = _inheritedHumanDecisionKinds.GetValueOrDefault(kind) + 1;
                AddRecentControllerDiagnostic(line);
            }
            else if (line.StartsWith("[TUI-DIAG priority]", StringComparison.Ordinal))
            {
                AddRecentControllerDiagnostic(line);
                var match = PriorityDiagnosticRegex.Match(line);
                if (match.Success)
                {
                    var turn = int.Parse(match.Groups["turn"].Value, System.Globalization.CultureInfo.InvariantCulture);
                    var phase = match.Groups["phase"].Value.Trim();
                    var priorityName = match.Groups["priority"].Value.Trim();
                    var activeName = match.Groups["active"].Value.Trim();
                    var isActivePlayersTurn = bool.Parse(match.Groups["isActivePlayersTurn"].Value);
                    var hasPriority = bool.Parse(match.Groups["hasPriority"].Value);
                    var prioritySeat = ResolveDiagnosticSeat(priorityName);
                    var activeSeat = ResolveDiagnosticSeat(activeName) ?? _latestObservedActiveSeatId;

                    if (_latestObservedTurnNumber != turn || !string.Equals(_latestObservedActiveSeatId, activeSeat, StringComparison.Ordinal))
                    {
                        _latestObservedTurnNumber = turn;
                        _latestObservedActiveSeatId = activeSeat;
                        events.Add(new ForgeTuiRawEvent(
                            "turn_changed",
                            activeSeat,
                            null,
                            null,
                            null,
                            null,
                            $"Authoritative turn is now {turn}.",
                            TurnNumber: turn,
                            ActiveSeatId: activeSeat,
                            PrioritySeatId: prioritySeat,
                            ForgeSequence: _latestObservedForgeSequence));
                    }

                    if (!string.Equals(_latestObservedPhaseName, phase, StringComparison.Ordinal))
                    {
                        _latestObservedPhaseName = phase;
                        events.Add(new ForgeTuiRawEvent(
                            "phase_changed",
                            activeSeat,
                            null,
                            null,
                            null,
                            null,
                            $"Authoritative phase is now {phase}.",
                            Phase: phase,
                            TurnNumber: turn,
                            ActiveSeatId: activeSeat,
                            PrioritySeatId: prioritySeat,
                            ForgeSequence: _latestObservedForgeSequence));
                    }

                    if (!string.Equals(_latestObservedPrioritySeatId, prioritySeat, StringComparison.Ordinal))
                    {
                        events.Add(new ForgeTuiRawEvent(
                            "priority_changed",
                            prioritySeat,
                            null,
                            null,
                            null,
                            null,
                            $"Authoritative priority is now {priorityName}; humanHasPriority={hasPriority}.",
                            TurnNumber: turn,
                            ActiveSeatId: activeSeat,
                            PrioritySeatId: prioritySeat,
                            Phase: phase,
                            ForgeSequence: _latestObservedForgeSequence));
                    }

                    _latestObservedPrioritySeatId = prioritySeat;
                }
            }
        }
        return events;
    }

    private void AddRecentControllerDiagnostic(string line)
    {
        const int limit = 24;
        _recentControllerDiagnostics.Enqueue(line.Length <= 1024 ? line : line[..1024]);
        while (_recentControllerDiagnostics.Count > limit) _recentControllerDiagnostics.Dequeue();
    }

    private string? ResolveDiagnosticSeat(string playerName)
    {
        if (string.Equals(playerName, "none", StringComparison.OrdinalIgnoreCase)) return null;
        if (_options.PlayerSeats.TryGetValue(playerName, out var seatId)) return seatId;
        return playerName.StartsWith("AI-", StringComparison.OrdinalIgnoreCase) ? _opponentSeatId : null;
    }

    private static bool IsCollectionDecision(DecisionDto? decision) =>
        decision is not null && decision.ConfirmRequired &&
        (decision.Kind is "discard" or "sacrifice" or "payment_option" or "search_selection"
            or "entity_selection" or "cost_selection"
            || decision.Kind == "mulligan"
                && string.Equals(decision.MulliganStage, "bottom_selection", StringComparison.Ordinal));

    private void MarkGameEnded(GameResultDto result)
    {
        if (string.Equals(_state, "game_ended", StringComparison.Ordinal)) return;
        _logger.LogInformation("Forge game ended winners={Winners} losers={Losers} reason={Reason}",
            string.Join(',', result.WinnerSeatIds), string.Join(',', result.LoserSeatIds), result.Reason ?? "(unspecified)");
        _state = "game_ended";
        _currentDecision = null;
        _currentInputs = null;
        _nextDecision?.TrySetException(new ForgeGameEndedException());
    }

    private static readonly Regex PriorityDiagnosticRegex = new(
        @"^\[TUI-DIAG priority\]\s+turn=(?<turn>\d+)\s+phase=(?<phase>.+?)\s+active=(?<active>.+?)\s+priority=(?<priority>.+?)\s+isActivePlayersTurn=(?<isActivePlayersTurn>true|false)\s+hasPriority=(?<hasPriority>true|false)\b",
        RegexOptions.CultureInvariant);

    private async Task HandleProcessExitAsync(Process process, long processGeneration, int exitCode)
    {
        Task? stdoutReader;
        lock (_sync)
        {
            if (!ReferenceEquals(_process, process) || _processGeneration != processGeneration) return;
            stdoutReader = _stdoutReaderTask;
        }

        if (stdoutReader is not null)
            await Task.WhenAny(stdoutReader, Task.Delay(TimeSpan.FromSeconds(1))).ConfigureAwait(false);

        lock (_sync)
        {
            if (!ReferenceEquals(_process, process) || _processGeneration != processGeneration) return;
            if (string.Equals(_state, "game_ended", StringComparison.Ordinal)) return;
        }
        Fail("forge_process_exited", $"Forge TUI process exited with code {exitCode}.");
    }

    private void Fail(string code, string message)
    {
        lock (_sync)
        {
            if (!string.IsNullOrWhiteSpace(_lastObservedTuiText))
            {
                _logger.LogWarning("Forge TUI output tail before failure: {Tail}", _lastObservedTuiText);
            }
            _logger.LogError("Forge TUI failure ({Code}): {Message}", code, message);
            _state = "failed";
            _diagnosticCode = code;
            _diagnosticMessage = message;
            _currentDecision = null;
            _currentInputs = null;
            _nextDecision?.TrySetException(new InvalidOperationException(message));
        }
    }

    private ForgeChoiceResult Reject(string code, string message, string? expectedSessionId = null, string? receivedSessionId = null) =>
        new(false, CreateState(), code, message, expectedSessionId, receivedSessionId);

    private AdapterStateDto CreateState()
    {
        lock (_sync)
        {
            var diagnostic = new AdapterDiagnosticDto(
                _diagnosticCode,
                _diagnosticMessage,
                _diagnosticContext,
                _startupTracker.Snapshot(),
                new Dictionary<string, int>(_inheritedHumanDecisionKinds, StringComparer.Ordinal),
                _recentControllerDiagnostics.ToArray());
            return new AdapterStateDto(_sessionId, _state, _currentDecision, null, diagnostic, _structuredState.Current?.Result);
        }
    }

    private bool HasHealthyProcess()
    {
        if (_process is null || string.Equals(_state, "failed", StringComparison.Ordinal)) return false;
        try { return !_process.HasExited; }
        catch (InvalidOperationException) { return false; }
    }

    private void ValidateConfiguration()
    {
        if (string.IsNullOrWhiteSpace(_options.Executable) || string.IsNullOrWhiteSpace(_options.WorkingDirectory))
            throw new InvalidOperationException("Forge:Executable and Forge:WorkingDirectory must be configured when Bridge:Adapter is ForgeTui.");
        if (string.IsNullOrWhiteSpace(_options.Arguments))
            throw new InvalidOperationException("Forge:Arguments must be configured.");
        var usesTtsDeckTemplate = _options.Arguments.Contains("{humanDeck}", StringComparison.Ordinal)
            || _options.Arguments.Contains("{aiDeck}", StringComparison.Ordinal);
        if (usesTtsDeckTemplate && (!_options.Arguments.Contains("{humanDeck}", StringComparison.Ordinal) || !_options.Arguments.Contains("{aiDeck}", StringComparison.Ordinal)))
            throw new InvalidOperationException("Forge:Arguments must contain both {humanDeck} and {aiDeck} placeholders.");
        if (usesTtsDeckTemplate) lock (_sync)
        {
            if (string.IsNullOrWhiteSpace(_humanDeckPath) || string.IsNullOrWhiteSpace(_aiDeckPath))
                throw new InvalidOperationException("TTS library decks have not been loaded. Import both decks on the table before NEW MATCH.");
        }
        if (!CanResolveExecutable(_options.Executable))
            throw new FileNotFoundException("Configured Forge executable was not found.", _options.Executable);
        if (!Directory.Exists(_options.WorkingDirectory))
            throw new DirectoryNotFoundException($"Configured Forge working directory was not found: {_options.WorkingDirectory}");
    }

    private string RenderArguments()
    {
        var arguments = _options.Arguments;
        if (arguments.Contains("{seed}", StringComparison.Ordinal))
        {
            var seed = RandomNumberGenerator.GetInt32(1, int.MaxValue);
            arguments = arguments.Replace("{seed}", seed.ToString(System.Globalization.CultureInfo.InvariantCulture), StringComparison.Ordinal);
            _logger.LogInformation("Starting Forge session with generated random seed {Seed}", seed);
        }
        if (!arguments.Contains("{humanDeck}", StringComparison.Ordinal)) return arguments;
        lock (_sync)
        {
            return arguments
                .Replace("{humanDeck}", _humanDeckPath!, StringComparison.Ordinal)
                .Replace("{aiDeck}", _aiDeckPath!, StringComparison.Ordinal);
        }
    }

    private static async Task WriteDeckAsync(string path, IReadOnlyList<DeckCardLoadDto> cards, CancellationToken cancellationToken)
    {
        var mainCards = cards
            .Select(card => new { CardName = ImportedCardName(card.CardName), card.Count })
            .Where(card => !string.IsNullOrWhiteSpace(card.CardName))
            .GroupBy(card => card.CardName, StringComparer.OrdinalIgnoreCase)
            .OrderBy(group => group.Key, StringComparer.OrdinalIgnoreCase)
            .Select(group => $"{group.Sum(card => card.Count)} {group.First().CardName}")
            .ToArray();
        if (mainCards.Length == 0) throw new InvalidOperationException("TTS library did not contain any importable card names.");
        var lines = new[] { "[metadata]", $"Name={Path.GetFileNameWithoutExtension(path)}", "[Main]" }
            .Concat(mainCards);
        var temporary = path + ".tmp";
        await File.WriteAllLinesAsync(temporary, lines, cancellationToken).ConfigureAwait(false);
        File.Move(temporary, path, overwrite: true);
    }

    private static string ImportedCardName(string name)
    {
        var imported = (name ?? string.Empty).Replace("\r", "\n", StringComparison.Ordinal);
        var lineBreak = imported.IndexOf('\n');
        if (lineBreak >= 0) imported = imported[..lineBreak];
        var splitFace = imported.IndexOf(" // ", StringComparison.Ordinal);
        if (splitFace >= 0) imported = imported[..splitFace];
        return imported.Trim();
    }

    private static bool CanResolveExecutable(string executable)
    {
        if (string.IsNullOrWhiteSpace(executable)) return false;
        if (File.Exists(executable)) return true;

        if (Path.IsPathRooted(executable) || executable.Contains('/') || executable.Contains('\\'))
            return false;

        var pathEntries = (Environment.GetEnvironmentVariable("PATH") ?? string.Empty)
            .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        foreach (var pathEntry in pathEntries)
        {
            if (string.IsNullOrWhiteSpace(pathEntry)) continue;

            var candidates = new[]
            {
                Path.Combine(pathEntry, executable),
                Path.Combine(pathEntry, executable + ".exe"),
                Path.Combine(pathEntry, executable + ".cmd"),
                Path.Combine(pathEntry, executable + ".bat"),
                Path.Combine(pathEntry, executable + ".com"),
            };

            foreach (var candidate in candidates)
            {
                if (File.Exists(candidate)) return true;
            }
        }

        return false;
    }

    private async Task StopProcessAsync(long? expectedGeneration = null)
    {
        Process? process;
        CancellationTokenSource? cancellation;
        lock (_sync)
        {
            if (expectedGeneration is not null && _processGeneration != expectedGeneration.Value) return;
            process = _process;
            cancellation = _processCancellation;
            _process = null;
            _processCancellation = null;
            // Invalidate buffered output before cancelling/killing the old
            // process. A subsequent session gets a distinct generation.
            _processGeneration++;
        }
        if (cancellation is not null) await cancellation.CancelAsync().ConfigureAwait(false);
        if (process is not null)
        {
            try { if (!process.HasExited) process.Kill(entireProcessTree: true); }
            catch (InvalidOperationException) { }
            process.Dispose();
        }
        cancellation?.Dispose();
    }

    public async ValueTask DisposeAsync()
    {
        await StopProcessAsync().ConfigureAwait(false);
        _sessionStartGate.Dispose();
    }
}

internal sealed class ForgeUnsupportedPromptException(string message) : InvalidOperationException(message);
