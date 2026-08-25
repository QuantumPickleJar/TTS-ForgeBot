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
    bool IsSelected = false);
