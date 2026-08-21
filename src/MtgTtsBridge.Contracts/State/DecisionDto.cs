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
    bool IsOrdered = false);
