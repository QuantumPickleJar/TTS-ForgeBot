using MtgTtsBridge.Contracts.State;
using MtgTtsBridge.Forge;

namespace MtgTtsBridge.Tests;

public sealed class ForgeDeckInventoryValidatorTests
{
    [Fact]
    public void DetectsCardsOmittedByForgeBeforeTtsLibraryReconciliation()
    {
        var expected = new Dictionary<string, IReadOnlyDictionary<string, int>>(StringComparer.Ordinal)
        {
            ["forge-player-1"] = ForgeDeckInventoryValidator.BuildInventory([
                new("Island", 38), new("Unsupported Card", 2)]),
            ["forge-player-2"] = ForgeDeckInventoryValidator.BuildInventory([
                new("Swamp", 40)]),
        };
        var snapshot = Snapshot(
            Seat("forge-player-1", Cards("Island", 38)),
            Seat("forge-player-2", Cards("Swamp", 40)));

        var result = ForgeDeckInventoryValidator.Validate(expected, snapshot);

        Assert.False(result.IsValid);
        Assert.Equal("forge-player-1", result.SeatId);
        Assert.Equal(40, result.ExpectedCount);
        Assert.Equal(38, result.ActualCount);
        Assert.Contains("unsupported cards", result.ErrorMessage, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void AcceptsExactInventoryAndIgnoresForgeCreatedTokens()
    {
        var expected = new Dictionary<string, IReadOnlyDictionary<string, int>>(StringComparer.Ordinal)
        {
            ["forge-player-1"] = ForgeDeckInventoryValidator.BuildInventory([new("Island", 2)]),
        };
        var seat = Seat("forge-player-1", Cards("Island", 2), Token("Soldier"));

        var result = ForgeDeckInventoryValidator.Validate(expected, Snapshot(seat));

        Assert.True(result.IsValid, result.ErrorMessage);
    }

    [Fact]
    public void WaitsForGameStartedInsteadOfValidatingTheFirstPlayerShuffle()
    {
        var playerOneShuffle = Snapshot(Seat("forge-player-1", Cards("Island", 40))) with
        {
            Reason = "GameEventShuffle"
        };
        var gameStarted = playerOneShuffle with { Reason = "GameEventGameStarted" };

        Assert.False(ForgeDeckInventoryValidator.IsInitialDeckInventorySnapshot(playerOneShuffle));
        Assert.True(ForgeDeckInventoryValidator.IsInitialDeckInventorySnapshot(gameStarted));
    }

    private static GameSnapshotDto Snapshot(params GameSeatSnapshotDto[] seats) =>
        new("session", 1, "initial", seats, []);

    private static GameSeatSnapshotDto Seat(string id, params GameZoneSnapshotDto[] zones) =>
        new(id, id.EndsWith("1", StringComparison.Ordinal) ? 1 : 2, id, 20, 0,
            new Dictionary<string, int>(), zones);

    private static GameZoneSnapshotDto Cards(string name, int count) =>
        new("library", Enumerable.Range(0, count).Select(index => Card(name, index)).ToArray());

    private static GameZoneSnapshotDto Token(string name) =>
        new("battlefield", [Card(name, 0) with { IsToken = true, ObjectKind = "forge-token" }]);

    private static GameCardSnapshotDto Card(string name, int index) =>
        new($"forge:card:{name}:{index}", index, name, name, "library", index, null, null,
            false, false, false, new Dictionary<string, int>(), []);
}
