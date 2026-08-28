namespace MtgTtsBridge.Contracts.Actions;

public sealed record LegalActionDto(
    string ActionId,
    string Type,
    string DisplayName,
    bool RequiresFollowup,
    string? CardIdentity,
    string? ObjectIdentity,
    string? TargetKind = null,
    string? TargetSeatId = null,
    string? CardInstanceId = null,
    bool IsSelected = false,
    // Presentation-only metadata. ActionId remains the sole legal identity.
    string? ActionKind = null,
    string? SourceCardInstanceId = null,
    string? SourceCardName = null,
    string? ShortLabel = null,
    bool RequiresSelection = false,
    int? MinSelections = null,
    int? MaxSelections = null,
    // Forge-derived provenance. These are presentation/routing metadata only;
    // ActionId remains the canonical legality identity.
    string? SourceZone = null,
    string? AbilityKind = null,
    string? CastMode = null,
    string? CostKind = null,
    // Exact source permanent for a Forge-created virtual PreparedSpell copy.
    // This is presentation context only; ActionId remains authoritative.
    string? PreparedSourceCardInstanceId = null,
    string? PrototypePower = null,
    string? PrototypeToughness = null,
    string? DisplayManaCost = null,
    // Entity-selection provenance. Cards use CardInstanceId; players use
    // EntitySeatId. These fields never replace ActionId as legal identity.
    string? EntityKind = null,
    string? EntitySeatId = null)
{
    /// <summary>
    /// Generic structured action provenance. When present, provides richer context
    /// about the action's origin, mode, and payment requirements. Flat fields above
    /// are preserved for backward compatibility. ActionId remains canonical.
    /// </summary>
    public ActionProvenanceDto? Provenance { get; init; }
};
