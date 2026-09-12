using MtgTtsBridge.Contracts.State;

namespace MtgTtsBridge.Contracts.Events;

/// <summary>Forge-authoritative, visibility-aware projection of a reveal.</summary>
public sealed record RevealPresentationDto(
    string PresentationId,
    long OriginatingEventSequence,
    string? SourceObjectId,
    string? SourceName,
    string? RevealingSeatId,
    IReadOnlyList<string> EntitledViewerSeatIds,
    string Visibility,
    IReadOnlyList<RevealedCardDto> Cards,
    string? Reason,
    bool AcknowledgmentRequired,
    string? AssociatedDecisionId,
    string Lifecycle = "opened",
    // Structured producer semantics. These fields deliberately describe the
    // rules operation; TTS must not infer a physical interaction from card
    // names, source labels, or Oracle text.
    string? InteractionKind = null,
    bool PhysicalInteractionSupported = false,
    string? SourceZone = null,
    IReadOnlyList<string>? AllowedPhysicalDestinations = null);

public sealed record RevealedCardDto(
    string AuthoritativeObjectId,
    string CardName,
    string? CardFaceIdentity = null,
    string? ImageUrl = null,
    string? OriginatingZone = null,
    CurrentCharacteristicsDto? Characteristics = null);
