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
    int? MaxSelections = null);
