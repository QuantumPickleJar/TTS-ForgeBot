using System.Collections.ObjectModel;
using MtgTtsBridge.Contracts.Actions;
using MtgTtsBridge.Contracts.Diagnostics;
using MtgTtsBridge.Contracts.Events;

namespace MtgTtsBridge.Diagnostics;

/// <summary>A small locked ring buffer. Snapshot returns a stable copy for report generation.</summary>
public sealed class DiagnosticRollingBuffer<T>
{
    private readonly object _sync = new();
    private readonly Queue<T> _items = new();
    private readonly int _capacity;

    public DiagnosticRollingBuffer(int capacity)
    {
        if (capacity <= 0) throw new ArgumentOutOfRangeException(nameof(capacity));
        _capacity = capacity;
    }

    public int Count { get { lock (_sync) return _items.Count; } }

    public void Add(T item)
    {
        lock (_sync)
        {
            _items.Enqueue(item);
            while (_items.Count > _capacity) _items.Dequeue();
        }
    }

    public IReadOnlyList<T> Snapshot()
    {
        lock (_sync) return _items.ToArray();
    }
}

public sealed record DiagnosticTelemetryRecord(
    DateTimeOffset TimestampUtc,
    string Kind,
    string? Message = null,
    string? SessionId = null,
    string? DecisionId = null,
    long? EventSequence = null,
    string? RequestId = null,
    string? BridgeProcessInstanceId = null,
    string? ClientRuntimeId = null,
    string? ClientRevision = null,
    IReadOnlyDictionary<string, object?>? Details = null);

public sealed record DiagnosticTelemetrySnapshot(
    IReadOnlyList<DiagnosticTelemetryRecord> BridgeLogs,
    IReadOnlyList<DiagnosticTelemetryRecord> ForgeOutput,
    IReadOnlyList<DiagnosticTelemetryRecord> Protocol,
    IReadOnlyList<DiagnosticTelemetryRecord> ForgeEvents,
    IReadOnlyList<DiagnosticTelemetryRecord> Choices,
    IReadOnlyList<TtsExecutionBreadcrumb> TtsBreadcrumbs,
    TtsExecutionWatchdogState Watchdog);

public sealed record TtsExecutionBreadcrumb(
    string ClientRuntimeId,
    string? SessionId,
    long? EventSessionGeneration,
    long? PresentationGeneration,
    long? EventSequence,
    string? EventKind,
    string Stage,
    string Operation,
    string? OperationId,
    string? CardInstanceId,
    string? SourceZone,
    string? DestinationZone,
    double? LuaTimestamp,
    DateTimeOffset ReceivedAtUtc);

public sealed record TtsExecutionBreadcrumbRequest(
    string ClientRuntimeId,
    string? SessionId,
    long? EventSessionGeneration,
    long? PresentationGeneration,
    long? EventSequence,
    string? EventKind,
    string Stage,
    string Operation,
    string? OperationId = null,
    string? CardInstanceId = null,
    string? SourceZone = null,
    string? DestinationZone = null,
    double? LuaTimestamp = null);

public sealed record TtsExecutionWatchdogState(
    string? ActiveClientRuntimeId,
    string? SessionId,
    long? OpenEventSequence,
    string? OpenEventKind,
    string? OpenOperation,
    string? OpenOperationId,
    DateTimeOffset? EnteredUtc,
    double? AgeSeconds,
    long? LastCompletedEventSequence,
    string? LastCompletedOperation,
    string? TriggerReason,
    bool CaptureTriggered);

public sealed class TtsExecutionWatchdog
{
    private readonly object _sync = new();
    private readonly TimeSpan _stallThreshold;
    private TtsExecutionBreadcrumb? _open;
    private string? _activeRuntime;
    private string? _activeSession;
    private string? _capturedKey;
    private string? _lastCompletedOperation;
    private long? _lastCompletedEvent;
    private string? _triggerReason;

    public TtsExecutionWatchdog(TimeSpan? stallThreshold = null) => _stallThreshold = stallThreshold ?? TimeSpan.FromSeconds(3);

    public TtsExecutionWatchdogState Snapshot(DateTimeOffset now)
    {
        lock (_sync) return State(now, false);
    }

    public bool Record(TtsExecutionBreadcrumb breadcrumb, DateTimeOffset now, out TtsExecutionWatchdogState state)
    {
        lock (_sync)
        {
            var isEnter = string.Equals(breadcrumb.Stage, "ENTER", StringComparison.OrdinalIgnoreCase)
                || breadcrumb.Stage.EndsWith("_ENTER", StringComparison.OrdinalIgnoreCase);
            var isExit = string.Equals(breadcrumb.Stage, "EXIT", StringComparison.OrdinalIgnoreCase)
                || breadcrumb.Stage.EndsWith("_RETURNED", StringComparison.OrdinalIgnoreCase)
                || breadcrumb.Stage.EndsWith("_EXIT", StringComparison.OrdinalIgnoreCase);
            if (isEnter)
            {
                if (_activeRuntime is not null && breadcrumb.ClientRuntimeId != _activeRuntime
                    && _open is not null && breadcrumb.SessionId != _activeSession)
                {
                    state = State(now, false);
                    return false;
                }
                if (_activeRuntime != breadcrumb.ClientRuntimeId || _activeSession != breadcrumb.SessionId)
                    _capturedKey = null;
                _activeRuntime = breadcrumb.ClientRuntimeId;
                _activeSession = breadcrumb.SessionId;
                _open = breadcrumb;
                _triggerReason = null;
            }
            else if (isExit && _open is not null && Owns(_open, breadcrumb))
            {
                _lastCompletedEvent = breadcrumb.EventSequence;
                _lastCompletedOperation = breadcrumb.Operation;
                _open = null;
            }
            state = State(now, false);
            return false;
        }
    }

    public bool Evaluate(DateTimeOffset now, out TtsExecutionWatchdogState state)
    {
        lock (_sync)
        {
            if (_open is null || now - _open.ReceivedAtUtc < _stallThreshold)
            {
                state = State(now, false);
                return false;
            }
            var key = Key(_open);
            if (_capturedKey == key)
            {
                state = State(now, true);
                return false;
            }
            _capturedKey = key;
            _triggerReason = "unmatched-enter-stalled";
            state = State(now, true);
            return true;
        }
    }

    private TtsExecutionWatchdogState State(DateTimeOffset now, bool triggered) => new(
        _open?.ClientRuntimeId, _open?.SessionId, _open?.EventSequence, _open?.EventKind,
        _open?.Operation, _open?.OperationId, _open?.ReceivedAtUtc,
        _open is null ? null : Math.Max(0, (now - _open.ReceivedAtUtc).TotalSeconds),
        _lastCompletedEvent, _lastCompletedOperation, _triggerReason, triggered || _capturedKey is not null);

    private static bool Owns(TtsExecutionBreadcrumb left, TtsExecutionBreadcrumb right) =>
        left.ClientRuntimeId == right.ClientRuntimeId && left.SessionId == right.SessionId
        && left.EventSessionGeneration == right.EventSessionGeneration
        && left.PresentationGeneration == right.PresentationGeneration
        && left.EventSequence == right.EventSequence && left.OperationId == right.OperationId
        && left.Operation == right.Operation;

    private static string Key(TtsExecutionBreadcrumb b) => string.Join("|", b.ClientRuntimeId, b.SessionId,
        b.EventSessionGeneration, b.PresentationGeneration, b.EventSequence, b.Operation, b.OperationId);
}

public sealed class TtsExecutionWatchdogService : BackgroundService
{
    private readonly DiagnosticTelemetryBuffer _telemetry;
    private readonly DiagnosticReportCollector _collector;
    private readonly ILogger<TtsExecutionWatchdogService> _logger;

    public TtsExecutionWatchdogService(DiagnosticTelemetryBuffer telemetry, DiagnosticReportCollector collector,
        ILogger<TtsExecutionWatchdogService> logger) => (_telemetry, _collector, _logger) = (telemetry, collector, logger);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromMilliseconds(500));
        while (await timer.WaitForNextTickAsync(stoppingToken).ConfigureAwait(false))
        {
            if (!_telemetry.TtsWatchdog.Evaluate(DateTimeOffset.UtcNow, out var state)) continue;
            try
            {
                await _collector.CaptureAsync(new DiagnosticReportRequestDto(
                    Summary: $"Automatic TTS freeze watchdog: {state.OpenOperation} event={state.OpenEventSequence}",
                    Category: "TTS freeze / emergency",
                    ClientRuntimeId: state.ActiveClientRuntimeId,
                    SessionId: state.SessionId,
                    LastAppliedEventSequence: state.LastCompletedEventSequence), stoppingToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { return; }
            catch (Exception exception) { _logger.LogError(exception, "TTS execution watchdog capture failed"); }
        }
    }
}

/// <summary>
/// In-memory, bounded diagnostic history. It is observational and intentionally
/// independent of the authoritative Forge state model.
/// </summary>
public sealed class DiagnosticTelemetryBuffer
{
    public const int BridgeLogCapacity = 1000;
    public const int ForgeOutputCapacity = 1000;
    public const int ProtocolCapacity = 250;
    public const int ForgeEventCapacity = 250;
    public const int ChoiceCapacity = 250;
    public const int TtsBreadcrumbCapacity = 384;

    private readonly DiagnosticRollingBuffer<DiagnosticTelemetryRecord> _bridgeLogs = new(BridgeLogCapacity);
    private readonly DiagnosticRollingBuffer<DiagnosticTelemetryRecord> _forgeOutput = new(ForgeOutputCapacity);
    private readonly DiagnosticRollingBuffer<DiagnosticTelemetryRecord> _protocol = new(ProtocolCapacity);
    private readonly DiagnosticRollingBuffer<DiagnosticTelemetryRecord> _forgeEvents = new(ForgeEventCapacity);
    private readonly DiagnosticRollingBuffer<DiagnosticTelemetryRecord> _choices = new(ChoiceCapacity);
    private readonly DiagnosticRollingBuffer<TtsExecutionBreadcrumb> _ttsBreadcrumbs = new(TtsBreadcrumbCapacity);
    public TtsExecutionWatchdog TtsWatchdog { get; } = new();

    public void RecordTtsBreadcrumb(TtsExecutionBreadcrumb breadcrumb)
    {
        _ttsBreadcrumbs.Add(breadcrumb);
        TtsWatchdog.Record(breadcrumb, breadcrumb.ReceivedAtUtc, out _);
    }

    public void RecordBridgeLog(string level, string category, string message, Exception? exception = null)
    {
        _bridgeLogs.Add(new DiagnosticTelemetryRecord(
            DateTimeOffset.UtcNow,
            "bridge_log",
            Truncate(message),
            BridgeProcessIdentity.InstanceId,
            Details: new ReadOnlyDictionary<string, object?>(new Dictionary<string, object?>
            {
                ["level"] = level,
                ["category"] = category,
                ["exception"] = exception?.ToString()
            })));
    }

    public void RecordForgeOutput(string stream, string line, string? sessionId = null)
    {
        _forgeOutput.Add(new DiagnosticTelemetryRecord(
            DateTimeOffset.UtcNow,
            stream == "stderr" ? "forge_stderr" : "forge_stdout",
            Truncate(line),
            sessionId,
            BridgeProcessInstanceId: BridgeProcessIdentity.InstanceId,
            Details: new ReadOnlyDictionary<string, object?>(new Dictionary<string, object?>
            {
                ["stream"] = stream
            })));
    }

    public void RecordProtocol(
        string direction,
        string path,
        int? statusCode = null,
        string? sessionId = null,
        string? decisionId = null,
        string? requestId = null,
        string? clientRuntimeId = null,
        string? clientRevision = null,
        object? payload = null)
    {
        _protocol.Add(new DiagnosticTelemetryRecord(
            DateTimeOffset.UtcNow,
            "protocol",
            $"{direction} {path}",
            sessionId,
            decisionId,
            RequestId: requestId,
            BridgeProcessInstanceId: BridgeProcessIdentity.InstanceId,
            ClientRuntimeId: clientRuntimeId,
            ClientRevision: clientRevision,
            Details: new ReadOnlyDictionary<string, object?>(new Dictionary<string, object?>
            {
                ["direction"] = direction,
                ["path"] = path,
                ["statusCode"] = statusCode,
                ["payload"] = payload
            })));
    }

    public void RecordChoice(ChoiceRequestDto request, string outcome, string? errorCode = null, string? message = null)
    {
        _choices.Add(new DiagnosticTelemetryRecord(
            DateTimeOffset.UtcNow,
            "choice",
            message ?? outcome,
            request.SessionId,
            request.DecisionId,
            RequestId: request.RequestId,
            BridgeProcessInstanceId: BridgeProcessIdentity.InstanceId,
            ClientRuntimeId: request.ClientRuntimeId,
            ClientRevision: request.ClientRevision,
            Details: new ReadOnlyDictionary<string, object?>(new Dictionary<string, object?>
            {
                ["actionId"] = request.ActionId,
                ["source"] = request.Source,
                ["outcome"] = outcome,
                ["errorCode"] = errorCode
            })));
    }

    public void RecordForgeEvent(AuthoritativeEventDto forgeEvent, string? sessionId = null)
    {
        _forgeEvents.Add(new DiagnosticTelemetryRecord(
            forgeEvent.OccurredAtUtc,
            "forge_event",
            forgeEvent.Summary,
            sessionId,
            EventSequence: forgeEvent.Sequence,
            BridgeProcessInstanceId: BridgeProcessIdentity.InstanceId,
            Details: new ReadOnlyDictionary<string, object?>(new Dictionary<string, object?>
            {
                ["event"] = forgeEvent
            })));
    }

    public DiagnosticTelemetrySnapshot Capture() => new(
        _bridgeLogs.Snapshot(),
        _forgeOutput.Snapshot(),
        _protocol.Snapshot(),
        _forgeEvents.Snapshot(),
        _choices.Snapshot(),
        _ttsBreadcrumbs.Snapshot(),
        TtsWatchdog.Snapshot(DateTimeOffset.UtcNow));

    private static string Truncate(string value) => value.Length <= 16_384 ? value : value[..16_384] + "…";
}
