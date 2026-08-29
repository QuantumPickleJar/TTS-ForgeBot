namespace MtgTtsBridge.Contracts.State;

/// <summary>
/// Forge-authoritative current characteristics for a game object.
/// All values come from Forge's current game object state, never calculated
/// from printed card data or derived in the bridge.
/// </summary>
public sealed record CurrentCharacteristicsDto(
    string CurrentCardName,
    string? CurrentManaCost = null,
    int? CurrentManaValue = null,
    IReadOnlyList<string>? CurrentColors = null,
    IReadOnlyList<string>? CurrentSupertypes = null,
    IReadOnlyList<string>? CurrentCardTypes = null,
    IReadOnlyList<string>? CurrentSubtypes = null,
    string? CurrentPower = null,
    string? CurrentToughness = null,
    string? CurrentLoyalty = null,
    string? CurrentDefense = null,
    IReadOnlyList<string>? CurrentKeywords = null);
