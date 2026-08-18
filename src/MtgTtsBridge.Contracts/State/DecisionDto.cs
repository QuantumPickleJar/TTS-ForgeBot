using MtgTtsBridge.Contracts.Actions;

namespace MtgTtsBridge.Contracts.State;

public sealed record DecisionDto(
    string DecisionId,
    string Kind,
    IReadOnlyList<LegalActionDto> Actions,
    string? SeatId = null);
