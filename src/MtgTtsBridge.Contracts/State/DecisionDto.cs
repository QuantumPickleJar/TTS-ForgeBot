using MtgTtsBridge.Contracts.Actions;

namespace MtgTtsBridge.Contracts.State;

public sealed record DecisionDto(
    string DecisionId,
    string Kind,
    IReadOnlyList<LegalActionDto> Actions,
    string? SeatId = null,
    string? Prompt = null,
    int MinSelections = 1,
    int MaxSelections = 1,
    bool RequiresConfirmation = false,
    bool AllowsCancel = false,
    bool IsOrdered = false)
{
    public long? EventCursor { get; init; }
    public long? ForgeSequence { get; init; }
    public int? TurnNumber { get; init; }
    public string? ActiveSeatId { get; init; }
    public string? PrioritySeatId { get; init; }
    public string? PhaseName { get; init; }
    public bool CanChooseZero => MinSelections == 0;
    public int SelectedCount { get; init; }
    public bool ConfirmRequired { get; init; }
}
