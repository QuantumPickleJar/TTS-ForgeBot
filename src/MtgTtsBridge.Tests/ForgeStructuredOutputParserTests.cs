using MtgTtsBridge.Forge;

namespace MtgTtsBridge.Tests;

public sealed class ForgeStructuredOutputParserTests
{
    [Fact]
    public void FramedSnapshot_IsRemovedFromTuiTextAndPreservesLibraryOrderAndDuplicateIds()
    {
        var parser = new ForgeStructuredOutputParser();
        var frame = Frame(1, Player(
            library: [Card(12, "Mountain", "library", 0), Card(7, "Mountain", "library", 1)],
            hand: [Card(19, "Hired Claw", "hand", 0)]));

        var first = parser.Append("What would you like to do?\n" + frame[..40]);
        var second = parser.Append(frame[40..] + "\n  0. Pass priority (do nothing)\n");

        Assert.Equal("What would you like to do?\n", first.TuiText);
        var snapshot = Assert.Single(second.Snapshots);
        Assert.DoesNotContain(ForgeStructuredOutputParser.Sentinel, second.TuiText);
        var library = Assert.Single(snapshot.Players).Zones.Single(zone => zone.Name == "library").Cards;
        Assert.Equal([12, 7], library.Select(card => card.ForgeCardId));
        Assert.Equal(["Mountain", "Mountain"], library.Select(card => card.CardName));
    }

    [Fact]
    public void Reconciliation_EmitsExactDrawZoneTapCounterAndKeywordFinalState()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        var initial = Parse(parser, Frame(1, Player(
            library: [Card(12, "Mountain", "library", 0), Card(7, "Mountain", "library", 1)],
            hand: [Card(19, "Hired Claw", "hand", 0)])));
        Assert.Empty(reconciler.Apply("session-a", initial));

        var changed = Parse(parser, Frame(2, Player(
            library: [Card(7, "Mountain", "library", 0)],
            hand: [Card(12, "Mountain", "hand", 0)],
            battlefield: [Card(19, "Hired Claw", "battlefield", 0, tapped: true, counters: "{\"+1/+1\":2}", keywords: "[\"Haste\"]")])));
        var events = reconciler.Apply("session-a", changed);

        var draw = Assert.Single(events, item => item.Kind == "draw");
        Assert.Equal(12, draw.ForgeObjectId);
        Assert.True(draw.ContainsHiddenIdentity);
        var move = Assert.Single(events, item => item.Kind == "card_moved" && item.ForgeObjectId == 19);
        Assert.Equal("hand", move.SourceZone);
        Assert.Equal("battlefield", move.DestinationZone);
        Assert.True(Assert.Single(events, item => item.Kind == "tap_changed").Tapped);
        var counter = Assert.Single(events, item => item.Kind == "counter_changed");
        Assert.Equal("+1/+1", counter.CounterType);
        Assert.Equal(2, counter.CounterValue);
        Assert.Equal("Haste", Assert.Single(events, item => item.Kind == "keyword_added").Keyword);

        var current = Assert.IsType<MtgTtsBridge.Contracts.State.GameSnapshotDto>(reconciler.Current);
        Assert.Equal("forge:session-a:12", current.Seats[0].Zones.Single(zone => zone.Name == "hand").Cards[0].CardInstanceId);
    }

    [Fact]
    public void SnapshotReplacement_ReconcilesAuthoritativeAbsoluteRemovalState()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        reconciler.Apply("session-a", Parse(parser, Frame(1, Player(
            battlefield: [Card(19, "Hired Claw", "battlefield", 0, tapped: true, counters: "{\"+1/+1\":2}", keywords: "[\"Haste\"]")]))));

        var events = reconciler.Apply("session-a", Parse(parser, Frame(2, Player(
            battlefield: [Card(19, "Hired Claw", "battlefield", 0)]))));

        Assert.False(Assert.Single(events, item => item.Kind == "tap_changed").Tapped);
        Assert.Equal(0, Assert.Single(events, item => item.Kind == "counter_changed").CounterValue);
        Assert.Equal("Haste", Assert.Single(events, item => item.Kind == "keyword_removed").Keyword);
    }

    [Fact]
    public void ManaPoolChanges_AreAbsoluteAndIncludeAllDisplayColors()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        reconciler.Apply("session-a", Parse(parser, Frame(1, Player(manaPool: "{\"W\":0,\"U\":0,\"B\":0,\"R\":0,\"G\":0,\"C\":0}"))));

        var events = reconciler.Apply("session-a", Parse(parser, Frame(2, Player(manaPool: "{\"W\":0,\"U\":0,\"B\":0,\"R\":1,\"G\":0,\"C\":0}"))));

        var mana = Assert.Single(events, item => item.Kind == "mana_pool_changed");
        Assert.Equal(1, mana.ManaPool!["R"]);
        Assert.Equal(0, mana.ManaPool["C"]);
        Assert.Equal(1, reconciler.Current!.Seats[0].ManaPool!["R"]);
    }

    [Fact]
    public void MalformedFrame_FailsVisibly()
    {
        var parser = new ForgeStructuredOutputParser();
        Assert.Throws<ForgeStructuredFrameException>(() =>
            parser.Append(ForgeStructuredOutputParser.Sentinel + "{not-json}\n"));
    }

    [Fact]
    public void Reset_DropsPartialFrameAndPreviousSnapshotState()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        parser.Append(ForgeStructuredOutputParser.Sentinel + "{\"version\":1");
        reconciler.Apply("session-a", Parse(new ForgeStructuredOutputParser(), Frame(1, Player())));

        parser.Reset();
        reconciler.Reset();

        var output = parser.Append("What would you like to do?");
        Assert.Equal("What would you like to do?", output.TuiText);
        Assert.Null(reconciler.Current);
    }

    private static ForgeStructuredSnapshot Parse(ForgeStructuredOutputParser parser, string frame) =>
        Assert.Single(parser.Append(frame + "\n").Snapshots);

    private static string Frame(long sequence, string player) =>
        ForgeStructuredOutputParser.Sentinel
        + $$"""{"version":1,"type":"snapshot","sequence":{{sequence}},"reason":"test","players":[{{player}}],"stack":[]}""";

    private static string Player(
        IReadOnlyList<string>? library = null,
        IReadOnlyList<string>? hand = null,
        IReadOnlyList<string>? battlefield = null,
        string manaPool = "{\"W\":0,\"U\":0,\"B\":0,\"R\":0,\"G\":0,\"C\":0}") =>
        $$"""{"seatId":"forge-player-1","forgePlayerId":1,"displayName":"Player 1","life":20,"poison":0,"counters":{},"manaPool":{{manaPool}},"zones":[{"name":"library","cards":[{{string.Join(',', library ?? [])}}]},{"name":"hand","cards":[{{string.Join(',', hand ?? [])}}]},{"name":"battlefield","cards":[{{string.Join(',', battlefield ?? [])}}]},{"name":"graveyard","cards":[]},{"name":"exile","cards":[]}]}""";

    private static string Card(
        int id,
        string name,
        string zone,
        int position,
        bool tapped = false,
        string counters = "{}",
        string keywords = "[]") =>
        $$"""{"forgeCardId":{{id}},"cardName":"{{name}}","currentCardName":"{{name}}","zone":"{{zone}}","zonePosition":{{position}},"ownerSeatId":"forge-player-1","controllerSeatId":"forge-player-1","tapped":{{tapped.ToString().ToLowerInvariant()}},"faceDown":false,"phasedOut":false,"counters":{{counters}},"keywords":{{keywords}}}""";
}
