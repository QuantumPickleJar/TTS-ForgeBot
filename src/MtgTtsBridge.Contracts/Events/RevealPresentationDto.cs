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
    string Lifecycle = "opened");

public sealed record RevealedCardDto(
    string AuthoritativeObjectId,
    string CardName,
    string? CardFaceIdentity = null,
    string? ImageUrl = null,
    string? OriginatingZone = null,
    CurrentCharacteristicsDto? Characteristics = null);
