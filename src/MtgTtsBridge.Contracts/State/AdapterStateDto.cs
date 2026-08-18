using MtgTtsBridge.Contracts.Events;

namespace MtgTtsBridge.Contracts.State;

public sealed record AdapterStateDto(
    string SessionId,
    string State,
    DecisionDto? CurrentDecision,
    CommittedEventDto? LastCommittedEvent);