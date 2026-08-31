namespace MtgTtsBridge.Contracts.Actions;

/// <summary>
/// Generic structured action provenance. Explains what action Forge is offering,
/// where it originates, and which mode/variant is being used.
/// ActionId remains the canonical legal identity; provenance is presentation context.
/// </summary>
public sealed record ActionProvenanceDto(
    string ActionKind,
    string? SourceCardInstanceId = null,
    string? SourceZone = null,
    string? SourceSeatId = null,
    string? AbilityKind = null,
    string? CastMode = null,
    string? CastFace = null,
    string? DisplayLabel = null,
    string? DisplayCost = null,
    string? PaymentContextId = null,
    bool? IsPresentationAuthorized = null);
