using System.Diagnostics;
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
    private long _latestEventSequence;

    private const int EventHistoryLimit = 512;

    public ForgeTuiAdapter(IOptions<ForgeTuiOptions> options, ILogger<ForgeTuiAdapter> logger)
    {
        _options = options.Value;
        _logger = logger;
        _startupTracker = new ForgeStartupTracker(logger);
        _parser = new ForgeTuiParser(_options.PlayerSeats);
        _eventParser = new ForgeTuiEventParser(_options.PlayerSeats);
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
            _events.Clear();
            _latestEventSequence = 0;
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
                _logger.LogTrace("Forge TUI stdout: {ForgeOutput}", chunk);
                ForgeTuiParserResult result;
                lock (_sync)
                {
                    _startupTracker.Observe(chunk);
                    foreach (var rawEvent in _eventParser.Append(chunk)) EnqueueEvent(rawEvent);
                    result = _parser.Append(chunk);
                }
                if (result.ParsedDecision is not null) _nextDecision?.TrySetResult(result.ParsedDecision);
                if (result.UnsupportedPrompt is not null) SetUnsupportedPrompt(result.UnsupportedPrompt);
                if (result.ErrorCode is not null)
                {
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
            _currentDecision = decision.Decision with { SeatId = _options.HumanSeatId };
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
            Keyword: rawEvent.Keyword);
        _events.Add(authoritativeEvent);
        if (_events.Count > EventHistoryLimit) _events.RemoveAt(0);
        _logger.LogDebug(
            "Forge event {Sequence} {Kind} seat={SeatId} card={CardName} instance={CardInstanceId}",
            authoritativeEvent.Sequence,
            authoritativeEvent.Kind,
            authoritativeEvent.SeatId,
            authoritativeEvent.CardName,
            authoritativeEvent.CardInstanceId);
    }

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
                _startupTracker.Snapshot());
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
