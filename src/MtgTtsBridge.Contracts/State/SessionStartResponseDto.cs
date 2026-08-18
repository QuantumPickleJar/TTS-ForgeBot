namespace MtgTtsBridge.Contracts.State;

public sealed record SessionStartResponseDto(
    string SessionId,
    DecisionDto CurrentDecision);