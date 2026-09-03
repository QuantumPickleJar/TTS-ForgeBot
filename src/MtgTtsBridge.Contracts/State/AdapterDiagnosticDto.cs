namespace MtgTtsBridge.Contracts.State;

public sealed record AdapterDiagnosticDto(
    string? Code,
    string? Message,
    string? Context,
    IReadOnlyList<StartupMilestoneDto> StartupMilestones,
    IReadOnlyDictionary<string, int>? InheritedHumanDecisionKinds = null,
    IReadOnlyList<string>? RecentControllerDiagnostics = null,
    long? LatestObservedEventCursor = null,
    long? LatestCommittedMutationCursor = null,
    long? LatestDecisionEligibleCursor = null,
    long? LatestCommittedMutationForgeSequence = null,
    string? PendingDecisionId = null,
    bool PendingDecisionAwaitingWatermark = false);

public sealed record StartupMilestoneDto(
    string Name,
    long ElapsedMilliseconds);
