namespace MtgTtsBridge.Contracts.State;

public sealed record AdapterDiagnosticDto(
    string? Code,
    string? Message,
    string? Context,
    IReadOnlyList<StartupMilestoneDto> StartupMilestones);

public sealed record StartupMilestoneDto(
    string Name,
    long ElapsedMilliseconds);
