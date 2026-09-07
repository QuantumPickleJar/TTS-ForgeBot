using MtgTtsBridge.Contracts.Actions;
using MtgTtsBridge.Contracts.State;

namespace MtgTtsBridge.Forge;

/// <summary>
/// Verifies that Forge retained the physical deck inventory supplied by TTS.
/// Forge can omit an unsupported card while still starting a match; allowing
/// that state to reach Lua makes library reconciliation fail later with a
/// misleading physical-count error.
/// </summary>
public static class ForgeDeckInventoryValidator
{
    /// <summary>
    /// Forge emits a shuffle snapshot for each player while preparing zones.
    /// The first of those can contain player one's complete library while
    /// player two has not been populated yet. GameStarted is the first
    /// snapshot after both submitted decks have been installed.
    /// </summary>
    public static bool IsInitialDeckInventorySnapshot(GameSnapshotDto snapshot) =>
        string.Equals(snapshot.Reason, "GameEventGameStarted", StringComparison.Ordinal);

    public static IReadOnlyDictionary<string, int> BuildInventory(IEnumerable<DeckCardLoadDto> cards)
    {
        var inventory = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        foreach (var card in cards)
        {
            var name = NormalizeCardName(card.CardName);
            if (name.Length == 0 || card.Count <= 0) continue;
            inventory[name] = inventory.TryGetValue(name, out var count) ? count + card.Count : card.Count;
        }
        return inventory;
    }

    public static ForgeDeckInventoryValidationResult Validate(
        IReadOnlyDictionary<string, IReadOnlyDictionary<string, int>> expectedBySeat,
        GameSnapshotDto snapshot)
    {
        foreach (var expectedSeat in expectedBySeat)
        {
            var seat = snapshot.Seats.FirstOrDefault(item =>
                string.Equals(item.SeatId, expectedSeat.Key, StringComparison.Ordinal));
            if (seat is null)
            {
                return Invalid(expectedSeat.Key, expectedSeat.Value.Values.Sum(), 0,
                    "Forge did not emit the configured seat in its authoritative snapshot.");
            }

            var actual = seat.Zones
                .SelectMany(zone => zone.Cards)
                .Where(card => !card.IsToken && !card.IsVirtual && !card.IsCopy)
                .GroupBy(card => NormalizeCardName(card.CardName), StringComparer.OrdinalIgnoreCase)
                .ToDictionary(group => group.Key, group => group.Count(), StringComparer.OrdinalIgnoreCase);
            var expectedCount = expectedSeat.Value.Values.Sum();
            var actualCount = actual.Values.Sum();
            if (expectedCount == actualCount && expectedSeat.Value.All(pair =>
                    actual.TryGetValue(pair.Key, out var count) && count == pair.Value)) continue;

            return Invalid(expectedSeat.Key, expectedCount, actualCount,
                "Forge's authoritative card inventory differs from the TTS deck inventory; Forge may have omitted unsupported cards.");
        }

        return new ForgeDeckInventoryValidationResult(true, null, null, null, null);
    }

    private static ForgeDeckInventoryValidationResult Invalid(string seatId, int expected, int actual, string reason) =>
        new(false, seatId, expected, actual, $"{reason} seat={seatId} ttsCards={expected} forgeCards={actual}.");

    public static string NormalizeCardName(string? name)
    {
        var imported = (name ?? string.Empty).Replace("\r", "\n", StringComparison.Ordinal);
        var lineBreak = imported.IndexOf('\n');
        if (lineBreak >= 0) imported = imported[..lineBreak];
        var splitFace = imported.IndexOf(" // ", StringComparison.Ordinal);
        if (splitFace >= 0) imported = imported[..splitFace];
        return imported.Trim();
    }
}

public sealed record ForgeDeckInventoryValidationResult(
    bool IsValid,
    string? SeatId,
    int? ExpectedCount,
    int? ActualCount,
    string? ErrorMessage);
