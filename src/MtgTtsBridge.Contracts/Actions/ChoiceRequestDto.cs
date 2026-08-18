namespace MtgTtsBridge.Contracts.Actions;

public sealed record ChoiceRequestDto(
    string DecisionId,
    string ActionId);