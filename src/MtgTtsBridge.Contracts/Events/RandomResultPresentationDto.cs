namespace MtgTtsBridge.Contracts.Events;

/// <summary>
/// Forge-authoritative random results intended for a physical presentation.
/// This is deliberately generic so a future coin renderer can share the
/// presentation barrier without exposing a second rules transport.
/// </summary>
public sealed record RandomResultPresentationDto(
    string RollGroupId,
    string SeatId,
    int Sides,
    IReadOnlyList<int> NaturalResults,
    IReadOnlyList<int>? FinalResults = null,
    bool IsReroll = false,
    string Purpose = "rules/gameplay",
    string? SourceObjectId = null,
    string? SourceName = null,
    long? ForgeSequence = null)
{
    public int RollCount => NaturalResults.Count;
}
