namespace MtgTtsBridge.Contracts.State;

public sealed record ErrorResponseDto(
    string ErrorCode,
    string Message,
    string? DecisionId);