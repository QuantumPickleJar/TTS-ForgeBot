namespace MtgTtsBridge.Contracts.State;

public sealed record AdapterDiagnosticDto(
    string? Code,
    string? Message,
    string? Context,
    IReadOnlyList<StartupMilestoneDto> StartupMilestones,
    IReadOnlyDictionary<string, int>? InheritedHumanDecisionKinds = null,
    IReadOnlyList<string>? RecentControllerDiagnostics = null);

public sealed record StartupMilestoneDto(
    string Name,
    long ElapsedMilliseconds);
