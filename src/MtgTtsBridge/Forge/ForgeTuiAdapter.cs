using System.Diagnostics;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Options;
using MtgTtsBridge.Contracts.Actions;
using MtgTtsBridge.Contracts.Events;
using MtgTtsBridge.Contracts.State;

namespace MtgTtsBridge.Forge;

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
    private readonly SemaphoreSlim _sessionStartGate = new(1, 1);
    private readonly HashSet<string> _resolvedDecisionIds = new(StringComparer.Ordinal);
    private Process? _process;
    private CancellationTokenSource? _processCancellation;
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
    private long _latestEventSequence;
    private string _lastObservedTuiText = string.Empty;
    private int? _latestObservedTurnNumber;
    private string? _latestObservedPhaseName;
    private string? _latestObservedPrioritySeatId;
    private string? _latestObservedActiveSeatId;
    private long? _latestObservedForgeSequence;

    private const int EventHistoryLimit = 512;

    public ForgeTuiAdapter(IOptions<ForgeTuiOptions> options, ILogger<ForgeTuiAdapter> logger)
    {
        _options = options.Value;
        _logger = logger;
        _startupTracker = new ForgeStartupTracker(logger);
        _parser = new ForgeTuiParser(_options.PlayerSeats);
        _eventParser = new ForgeTuiEventParser(_options.PlayerSeats);
        _structuredParser = new ForgeStructuredOutputParser();
        _structuredState = new ForgeStructuredStateReconciler();
        _opponentSeatId = _options.PlayerSeats.Values.FirstOrDefault(seatId => !string.Equals(seatId, _options.HumanSeatId, StringComparison.Ordinal));
    }

    public string Name => "ForgeTuiAdapter";

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
                BattlefieldKind = _landCardInstanceIds.Contains(card.CardInstanceId) ? "land" : null
            };
            return Task.FromResult<GameSnapshotDto?>(snapshot with
            {
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
            Arguments = _options.Arguments,
            WorkingDirectory = _options.WorkingDirectory,
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
        };

        var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
        var cancellation = new CancellationTokenSource();
        TaskCompletionSource<ForgeTuiDecision> initialDecision;

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
            _resolvedDecisionIds.Clear();
            _sessionId = Guid.NewGuid().ToString("N");
            _state = "starting";
            _currentDecision = null;
            _currentInputs = null;
            _diagnosticCode = null;
            _diagnosticMessage = null;
            _diagnosticContext = null;
            _process = process;
            _processCancellation = cancellation;
            initialDecision = NewDecisionWaiter();
        }

        process.Exited += (_, _) => HandleProcessExit(process, process.ExitCode);
        if (!process.Start())
        {
            throw new InvalidOperationException("Forge TUI process could not be started.");
        }

        lock (_sync) _startupTracker.MarkProcessLaunched();

        _logger.LogInformation("Started Forge TUI process {ProcessId}: {Executable} {Arguments}", process.Id, _options.Executable, _options.Arguments);
        _ = ReadOutputAsync(process.StandardOutput, isError: false, cancellation.Token);
        _ = ReadOutputAsync(process.StandardError, isError: true, cancellation.Token);

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
        lock (_sync)
        {
            if (_currentDecision is null || _currentInputs is null)
            {
                return Reject("no_pending_decision", "No Forge TUI decision is currently active.");
            }
            if (!string.Equals(request.DecisionId, _currentDecision.DecisionId, StringComparison.Ordinal))
            {
                return _resolvedDecisionIds.Contains(request.DecisionId)
                    ? Reject("stale_decision_id", "The provided decisionId is stale and no longer active.")
                    : Reject("unknown_decision_id", "The provided decisionId is unknown for the current session state.");
            }
            if (!_currentInputs.TryGetValue(request.ActionId, out var mappedInput) || mappedInput is null)
            {
                return Reject("unknown_action_id", "The provided actionId is not legal for this Forge TUI decision.");
            }
            forgeInput = mappedInput;
            process = _process;
            if (process is null || process.HasExited)
            {
                return Reject("forge_process_exited", "The Forge TUI process exited before the choice could be submitted.");
            }
            _resolvedDecisionIds.Add(_currentDecision.DecisionId);
            _currentDecision = null;
            _currentInputs = null;
            _state = "awaiting_forge";
            waiter = NewDecisionWaiter();
        }

        _logger.LogDebug("Forge TUI stdin: {ForgeInput}", forgeInput);
        await process.StandardInput.WriteLineAsync(forgeInput).ConfigureAwait(false);
        await process.StandardInput.FlushAsync().ConfigureAwait(false);

        try
        {
            var decision = await WaitForDecisionAsync(waiter, _options.DecisionTimeoutSeconds, cancellationToken, "decision").ConfigureAwait(false);
            SetDecision(decision);
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

    private async Task ReadOutputAsync(StreamReader reader, bool isError, CancellationToken cancellationToken)
    {
        var buffer = new char[1024];
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                var count = await reader.ReadAsync(buffer.AsMemory(0, buffer.Length), cancellationToken).ConfigureAwait(false);
                if (count == 0) return;
                var chunk = new string(buffer, 0, count);
                if (isError)
                {
                    _logger.LogDebug("Forge TUI stderr: {ForgeOutput}", chunk);
                    continue;
                }
                ForgeTuiParserResult result;
                lock (_sync)
                {
                    var output = _structuredParser.Append(chunk);
                    foreach (var snapshot in output.Snapshots)
                    {
                        _latestObservedForgeSequence = snapshot.Sequence;
                        foreach (var rawEvent in _structuredState.Apply(_sessionId, snapshot)) EnqueueEvent(rawEvent);
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
                            if (_structuredState.Current is not null
                                && rawEvent.Kind is "player_state" or "card_moved" or "turn_changed" or "phase_changed") continue;
                            EnqueueEvent(rawEvent);
                        }
                    }
                    result = _parser.Append(tuiText);
                }
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
                    _ = StopProcessAsync();
                }
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { }
        catch (Exception ex) { Fail("forge_output_failure", ex.Message); }
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
            var actions = decision.Decision.Actions.Select(action =>
                action.CardInstanceId is not null && action.CardInstanceId.StartsWith("forge-object:", StringComparison.Ordinal)
                    ? action with { CardInstanceId = $"forge:{_sessionId}:{action.CardInstanceId["forge-object:".Length..]}" }
                    : action).ToArray();
            _currentDecision = decision.Decision with { SeatId = _options.HumanSeatId, Actions = actions };
            _currentDecision = _currentDecision with
            {
                EventCursor = _latestEventSequence,
                ForgeSequence = _latestObservedForgeSequence ?? _structuredState.Current?.ForgeSequence,
                TurnNumber = _latestObservedTurnNumber,
                ActiveSeatId = _latestObservedActiveSeatId,
                PrioritySeatId = _latestObservedPrioritySeatId,
                PhaseName = _latestObservedPhaseName,
            };
            _currentInputs = decision.Inputs;
            _state = "awaiting_human_decision";
        }
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
            PrioritySeatId: rawEvent.PrioritySeatId);
        if (authoritativeEvent.Kind == "turn_changed")
        {
            _latestObservedTurnNumber = authoritativeEvent.TurnNumber ?? _latestObservedTurnNumber;
            _latestObservedActiveSeatId = authoritativeEvent.SeatId ?? authoritativeEvent.ActiveSeatId ?? _latestObservedActiveSeatId;
        }
        if (authoritativeEvent.Kind == "phase_changed" && authoritativeEvent.Phase is not null)
        {
            _latestObservedPhaseName = authoritativeEvent.Phase;
        }
        if (authoritativeEvent.Kind == "land_played" && cardInstanceId is not null)
        {
            _landCardInstanceIds.Add(cardInstanceId);
        }
        _events.Add(authoritativeEvent);
        if (_events.Count > EventHistoryLimit) _events.RemoveAt(0);
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
                    var isMyTurn = bool.Parse(match.Groups["isMyTurn"].Value);
                    var prioritySeat = _options.PlayerSeats.TryGetValue(priorityName, out var mappedPrioritySeat)
                        ? mappedPrioritySeat
                        : _latestObservedPrioritySeatId;
                    var activeSeat = isMyTurn ? _options.HumanSeatId : _opponentSeatId;

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

    private static readonly Regex PriorityDiagnosticRegex = new(
        @"^\[TUI-DIAG priority\]\s+turn=(?<turn>\d+)\s+phase=(?<phase>.+?)\s+priority=(?<priority>.+?)\s+isMyTurn=(?<isMyTurn>true|false)\b",
        RegexOptions.CultureInvariant);

    private void HandleProcessExit(Process process, int exitCode)
    {
        lock (_sync)
        {
            if (!ReferenceEquals(_process, process)) return;
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

    private ForgeChoiceResult Reject(string code, string message) => new(false, CreateState(), code, message);

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
            return new AdapterStateDto(_sessionId, _state, _currentDecision, null, diagnostic);
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
        if (!File.Exists(_options.Executable)) throw new FileNotFoundException("Configured Forge executable was not found.", _options.Executable);
        if (!Directory.Exists(_options.WorkingDirectory)) throw new DirectoryNotFoundException($"Configured Forge working directory was not found: {_options.WorkingDirectory}");
    }

    private async Task StopProcessAsync()
    {
        Process? process;
        CancellationTokenSource? cancellation;
        lock (_sync) { process = _process; cancellation = _processCancellation; _process = null; _processCancellation = null; }
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
