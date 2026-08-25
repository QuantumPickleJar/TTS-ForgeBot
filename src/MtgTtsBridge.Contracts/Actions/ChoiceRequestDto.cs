namespace MtgTtsBridge.Contracts.Actions;

public sealed record ChoiceRequestDto(
    string DecisionId,
    string ActionId)
{
    // SessionId is protocol identity, not a UI hint: a decision can only be
    // consumed by the Forge session that presented it.
    public string? SessionId { get; init; }
    public string? RequestId { get; init; }
    public string? ClientRuntimeId { get; init; }
    public string? ClientRevision { get; init; }
    public string? Source { get; init; }
}
