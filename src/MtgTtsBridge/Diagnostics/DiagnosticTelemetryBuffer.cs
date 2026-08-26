using System.Collections.ObjectModel;
using MtgTtsBridge.Contracts.Actions;
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
    IReadOnlyList<DiagnosticTelemetryRecord> Choices);

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

    private readonly DiagnosticRollingBuffer<DiagnosticTelemetryRecord> _bridgeLogs = new(BridgeLogCapacity);
    private readonly DiagnosticRollingBuffer<DiagnosticTelemetryRecord> _forgeOutput = new(ForgeOutputCapacity);
    private readonly DiagnosticRollingBuffer<DiagnosticTelemetryRecord> _protocol = new(ProtocolCapacity);
    private readonly DiagnosticRollingBuffer<DiagnosticTelemetryRecord> _forgeEvents = new(ForgeEventCapacity);
    private readonly DiagnosticRollingBuffer<DiagnosticTelemetryRecord> _choices = new(ChoiceCapacity);

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
        _choices.Snapshot());

    private static string Truncate(string value) => value.Length <= 16_384 ? value : value[..16_384] + "…";
}
