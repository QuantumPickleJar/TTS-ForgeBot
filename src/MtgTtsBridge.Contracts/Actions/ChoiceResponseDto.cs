using MtgTtsBridge.Contracts.Events;
using MtgTtsBridge.Contracts.State;

namespace MtgTtsBridge.Contracts.Actions;

public sealed record ChoiceResponseDto(
    bool Accepted,
    string? ErrorCode,
    string? ErrorMessage,
    DecisionDto? CurrentDecision,
    CommittedEventDto? CommittedEvent);