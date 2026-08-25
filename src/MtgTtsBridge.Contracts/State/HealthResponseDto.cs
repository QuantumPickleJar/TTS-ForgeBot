using MtgTtsBridge.Contracts.Events;

namespace MtgTtsBridge.Contracts.State;

public sealed record HealthResponseDto(
    string Status,
    string Adapter,
    string AdapterState,
    string SessionId,
    bool HasActiveDecision,
    string? CurrentDecisionId,
    CommittedEventDto? LastCommittedEvent,
    AdapterDiagnosticDto? Diagnostic = null,
    string? BridgeRevision = null,
    string? BridgeProcessInstanceId = null,
    int? ProcessId = null,
    DateTimeOffset? ProcessStartUtc = null);
