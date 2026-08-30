namespace MtgTtsBridge.Contracts.Actions;

/// <summary>
/// Generic payment context for a cast/activation requiring follow-up choices.
/// All follow-up Forge decisions belonging to this payment correlate via PaymentContextId.
/// </summary>
public sealed record PaymentContextDto(
    string OriginActionId,
    string PaymentContextId,
    string? SourceCardInstanceId = null,
    string? SourceZone = null,
    string? ActionKind = null,
    string? CastMode = null,
    IReadOnlyList<CostComponentDto>? CostComponents = null);
