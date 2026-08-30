namespace MtgTtsBridge.Contracts.Actions;

/// <summary>
/// Generic cost component representing one Forge-derived cost requirement.
/// Provides enough identity and context for presentation and routing without
/// implementing Magic cost validation in the bridge.
/// </summary>
public sealed record CostComponentDto(
    string CostComponentId,
    string Kind,
    string? DisplayLabel = null,
    string? RequiredValue = null,
    string? SelectedValue = null,
    string? SourceZone = null,
    string? SelectionKind = null,
    int? MinSelections = null,
    int? MaxSelections = null,
    string? RequirementKind = null);
