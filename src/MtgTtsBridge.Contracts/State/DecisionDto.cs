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
    public string? SessionId { get; init; }
    public long? EventCursor { get; init; }
    public long? ForgeSequence { get; init; }
    public int? TurnNumber { get; init; }
    public string? ActiveSeatId { get; init; }
    public string? PrioritySeatId { get; init; }
    public string? PhaseName { get; init; }
    public bool CanChooseZero => MinSelections == 0;
    public int SelectedCount { get; init; }
    public bool ConfirmRequired { get; init; }
    // Forge-producer metadata used solely for presentation. It is never a
    // substitute for the legal ActionIds that Forge supplied.
    public string? DecisionCauseKind { get; init; }
    public string? DecisionReason { get; init; }
    public string? SourceCardInstanceId { get; init; }
    public string? SourceCardName { get; init; }
    // Exact Forge context for a sequential relationship decision (for example,
    // the attacker currently being offered legal blockers).
    public string? ContextCardInstanceId { get; init; }
    public string? ContextCardName { get; init; }
    // Typed native-choice provenance. These are presentation hints emitted by
    // Forge at the controller boundary; legal ActionIds remain authoritative.
    public string? CostKind { get; init; }
    public string? SelectionKind { get; init; }
    public string? MulliganStage { get; init; }
    public string? CandidateSourceZone { get; init; }
    // Forge-computed aggregate payment progress. These are display metadata;
    // Forge still validates the selected cards before accepting the payment.
    public int? RequiredTotalPower { get; init; }
    public int? SelectedTotalPower { get; init; }
}
