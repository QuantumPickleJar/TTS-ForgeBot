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
                    new Dictionary<string, int>(expectedSeat.Value, StringComparer.OrdinalIgnoreCase),
                    new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase),
                    "Forge did not emit the configured seat in its authoritative snapshot.");
            }

            var actual = seat.Zones
                .SelectMany(zone => zone.Cards)
                .Where(card => !card.IsToken && !card.IsVirtual && !card.IsCopy)
                .GroupBy(card => NormalizeCardName(card.CardName), StringComparer.OrdinalIgnoreCase)
                .ToDictionary(group => group.Key, group => group.Count(), StringComparer.OrdinalIgnoreCase);
            var expectedCount = expectedSeat.Value.Values.Sum();
            var actualCount = actual.Values.Sum();
            var missingByCard = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            foreach (var pair in expectedSeat.Value)
            {
                var observed = actual.TryGetValue(pair.Key, out var value) ? value : 0;
                if (observed < pair.Value) missingByCard[pair.Key] = pair.Value - observed;
            }

            var excessByCard = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            foreach (var pair in actual)
            {
                var expected = expectedSeat.Value.TryGetValue(pair.Key, out var value) ? value : 0;
                if (pair.Value > expected) excessByCard[pair.Key] = pair.Value - expected;
            }

            if (missingByCard.Count == 0 && excessByCard.Count == 0) continue;

            return Invalid(expectedSeat.Key, expectedCount, actualCount,
                missingByCard, excessByCard,
                "Forge authoritative card inventory differs from the TTS deck inventory.");
        }

        return new ForgeDeckInventoryValidationResult(true, null, null, null, null);
    }

    private static ForgeDeckInventoryValidationResult Invalid(
        string seatId,
        int expected,
        int actual,
        IReadOnlyDictionary<string, int> missingByCard,
        IReadOnlyDictionary<string, int> excessByCard,
        string reason)
    {
        static string FormatDelta(IReadOnlyDictionary<string, int> delta)
        {
            if (delta.Count == 0) return "none";
            return string.Join(", ",
                delta.OrderBy(pair => pair.Key, StringComparer.OrdinalIgnoreCase)
                    .Select(pair => $"{pair.Key} x{pair.Value}"));
        }

        return new ForgeDeckInventoryValidationResult(
            IsValid: false,
            SeatId: seatId,
            ExpectedCount: expected,
            ActualCount: actual,
            ErrorMessage: $"{reason} seat={seatId} ttsCards={expected} forgeCards={actual} missing=[{FormatDelta(missingByCard)}] excess=[{FormatDelta(excessByCard)}].",
            MissingByCard: new Dictionary<string, int>(missingByCard, StringComparer.OrdinalIgnoreCase),
            ExcessByCard: new Dictionary<string, int>(excessByCard, StringComparer.OrdinalIgnoreCase));
    }

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
    string? ErrorMessage,
    IReadOnlyDictionary<string, int>? MissingByCard = null,
    IReadOnlyDictionary<string, int>? ExcessByCard = null);
