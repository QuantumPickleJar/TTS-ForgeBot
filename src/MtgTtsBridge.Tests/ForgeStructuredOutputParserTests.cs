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
    public void Reconciliation_DoesNotPromoteLegacyZeroStatsToNonCreatureCharacteristics()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        reconciler.Apply("session-a", Parse(parser, Frame(1, Player(
            battlefield: [Card(12, "Mountain", "battlefield", 0, currentTypes: "[\"land\"]")]))));

        var mountain = Assert.Single(reconciler.Current!.Seats[0].Zones
            .Single(zone => zone.Name == "battlefield").Cards);

        Assert.Null(mountain.CurrentPower);
        Assert.Null(mountain.CurrentToughness);
    }

    [Fact]
    public void Reconciliation_DiffsLiveGameEventReasonsWithoutRequiringGameStartedReason()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();

        var baseline = Parse(parser, Frame(
            sequence: 1,
            player: Player(battlefield: [Card(86, "Hired Claw", "battlefield", 0)]),
            reason: "GameEventSpellResolved"));
        Assert.Empty(reconciler.Apply("session-a", baseline));

        var changed = Parse(parser, Frame(
            sequence: 2,
            player: Player(graveyard: [Card(86, "Hired Claw", "graveyard", 0)]),
            reason: "GameEventCardTapped"));
        var events = reconciler.Apply("session-a", changed);

        var moved = Assert.Single(events, item => item.Kind == "card_moved" && item.ForgeObjectId == 86);
        Assert.Equal("battlefield", moved.SourceZone);
        Assert.Equal("graveyard", moved.DestinationZone);
    }

    [Fact]
    public void Reconciliation_OrdersSoulstoneZoneTransitionBeforeItsTapPresentation()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        reconciler.Apply("session-a", Parse(parser, Frame(1, Player(
            hand: [Card(88, "Soulstone Sanctuary", "hand", 0)]))));

        var events = reconciler.Apply("session-a", Parse(parser, Frame(2, Player(
            battlefield: [Card(88, "Soulstone Sanctuary", "battlefield", 0, tapped: true)]))));

        var movementIndex = events
            .Select((item, index) => (item, index))
            .Single(pair => pair.item.Kind == "card_moved" && pair.item.ForgeObjectId == 88).index;
        var tapIndex = events
            .Select((item, index) => (item, index))
            .Single(pair => pair.item.Kind == "tap_changed" && pair.item.ForgeObjectId == 88).index;

        Assert.True(movementIndex < tapIndex);
        Assert.Equal("hand", events[movementIndex].SourceZone);
        Assert.Equal("battlefield", events[movementIndex].DestinationZone);
        Assert.True(events[tapIndex].Tapped);
        Assert.All(events, item => Assert.Equal(2, item.ForgeSequence));
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
    public void KeywordNormalization_StripsReminderSuffixesForCanonicalCapabilityKeys()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        reconciler.Apply("session-a", Parse(parser, Frame(1, Player(
            battlefield: [Card(19, "Emberheart Challenger", "battlefield", 0)]))));

        var events = reconciler.Apply("session-a", Parse(parser, Frame(2, Player(
            battlefield: [Card(19, "Emberheart Challenger", "battlefield", 0, keywords: "[\"Prowess (Whenever you cast a noncreature spell, this creature gets +1/+1 until end of turn.)\"]")]))));

        Assert.Equal("Prowess", Assert.Single(events, item => item.Kind == "keyword_added").Keyword);
    }

    [Fact]
    public void ProwessStats_AreObservedFromForgeAndReturnAtEndOfDuration()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        reconciler.Apply("session-a", Parse(parser, Frame(1, Player(
            battlefield: [Card(19, "Emberheart Challenger", "battlefield", 0, netPower: 2, netToughness: 2)]))));

        var triggered = reconciler.Apply("session-a", Parse(parser, Frame(2, Player(
            battlefield: [Card(19, "Emberheart Challenger", "battlefield", 0, netPower: 3, netToughness: 3)]))));
        var gain = Assert.Single(triggered, item => item.Kind == "stats_changed");
        Assert.Equal(3, gain.NetPower);
        Assert.Equal(3, gain.NetToughness);

        var expired = reconciler.Apply("session-a", Parse(parser, Frame(3, Player(
            battlefield: [Card(19, "Emberheart Challenger", "battlefield", 0, netPower: 2, netToughness: 2)]))));
        var reset = Assert.Single(expired, item => item.Kind == "stats_changed");
        Assert.Equal(2, reset.NetPower);
        Assert.Equal(2, reset.NetToughness);
    }

    [Fact]
    public void Reconciliation_EmitsTerminalEventFromForgeOutcome_NotFromLifeInference()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        reconciler.Apply("session-a", Parse(parser, Frame(1, Player())));

        var terminal = ForgeStructuredOutputParser.Sentinel
            + "{\"version\":1,\"type\":\"snapshot\",\"sequence\":2,\"reason\":\"game_ended\",\"players\":["
            + Player() + "],\"stack\":[],\"gameEnded\":{\"winnerSeatIds\":[\"forge-player-2\"],\"loserSeatIds\":[\"forge-player-1\"],\"reason\":\"AllOpposingTeamsLost\"}}";
        var events = reconciler.Apply("session-a", Parse(parser, terminal));

        var ended = Assert.Single(events, item => item.Kind == "game_ended");
        Assert.Equal(["forge-player-2"], ended.WinnerSeatIds);
        Assert.Equal(["forge-player-1"], ended.LoserSeatIds);
        Assert.Equal("AllOpposingTeamsLost", ended.GameEndReason);
        Assert.NotNull(reconciler.Current!.Result);
    }

    [Fact]
    public void StartupSnapshot_WithNoCombatObject_IsAnAuthoritativeEmptyCombatState()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        var frame = ForgeStructuredOutputParser.Sentinel
            + "{\"version\":1,\"type\":\"snapshot\",\"sequence\":1,\"reason\":\"GameEventGameStarted\",\"players\":["
            + Player()
            + "],\"stack\":[],\"combat\":{\"attacks\":[]}}";

        var snapshot = Parse(parser, frame);
        Assert.NotNull(snapshot.Combat);
        Assert.Empty(snapshot.Combat!.Attacks);
        Assert.Empty(reconciler.Apply("session-a", snapshot));
        Assert.NotNull(reconciler.Current);
        Assert.NotNull(reconciler.Current!.Combat);
        Assert.Empty(reconciler.Current.Combat!.Attacks);
    }

    [Fact]
    public void CombatSnapshot_PreservesExactBlockerToAttackerRelationshipsIncludingSharedBlockers()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        var frame = ForgeStructuredOutputParser.Sentinel
            + "{\"version\":1,\"type\":\"snapshot\",\"sequence\":1,\"reason\":\"combat\",\"players\":["
            + Player(battlefield: [
                Card(11, "Attacker A", "battlefield", 0), Card(12, "Attacker B", "battlefield", 1),
                Card(21, "Blocker", "battlefield", 2)])
            + "],\"stack\":[],\"combat\":{\"attacks\":["
            + "{\"attackerForgeObjectId\":11,\"defenderSeatId\":\"forge-player-1\",\"defenderForgeObjectId\":null,\"blockerForgeObjectIds\":[21]},"
            + "{\"attackerForgeObjectId\":12,\"defenderSeatId\":\"forge-player-1\",\"defenderForgeObjectId\":null,\"blockerForgeObjectIds\":[21]}]}}";

        Assert.Empty(reconciler.Apply("session-a", Parse(parser, frame)));
        var attacks = reconciler.Current!.Combat!.Attacks;
        Assert.Equal(2, attacks.Count);
        Assert.All(attacks, attack => Assert.Equal(["forge:session-a:21"], attack.BlockerCardInstanceIds));
        Assert.Equal(["forge:session-a:11", "forge:session-a:12"], attacks.Select(attack => attack.AttackerCardInstanceId));
    }

    [Fact]
    public void ContinuousCharacteristicSnapshot_UpdatesEveryAffectedPermanentAndRevertsWithoutCombat()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        reconciler.Apply("session-a", Parse(parser, Frame(1, Player(
            battlefield: [Card(1, "Baseline Creature", "battlefield", 0,
                netPower: 1, netToughness: 1, currentTypes: "[\"creature\"]")]))));

        var lordEntered = reconciler.Apply("session-a", Parse(parser, Frame(2, Player(
            battlefield: [
                Card(1, "Baseline Creature", "battlefield", 0,
                    netPower: 2, netToughness: 2, currentTypes: "[\"creature\"]"),
                Card(2, "Continuous Effect Source", "battlefield", 1,
                    netPower: 2, netToughness: 2, currentTypes: "[\"creature\"]")
            ]))));

        var buff = Assert.Single(lordEntered, item => item.Kind == "stats_changed" && item.ForgeObjectId == 1);
        Assert.Equal(2, buff.CurrentPower);
        Assert.Equal(2, buff.CurrentToughness);

        var lordLeft = reconciler.Apply("session-a", Parse(parser, Frame(3, Player(
            battlefield: [Card(1, "Baseline Creature", "battlefield", 0,
                netPower: 1, netToughness: 1, currentTypes: "[\"creature\"]")],
            graveyard: [Card(2, "Continuous Effect Source", "graveyard", 0,
                netPower: 0, netToughness: 0, currentTypes: "[\"creature\"]")]))));

        var revert = Assert.Single(lordLeft, item => item.Kind == "stats_changed" && item.ForgeObjectId == 1);
        Assert.Equal(1, revert.CurrentPower);
        Assert.Equal(1, revert.CurrentToughness);
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
    public void Reconciliation_TransportsForgeCharacteristicsControllerFacePhaseAndDesignations()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        reconciler.Apply("session-a", Parse(parser, Frame(1, Player(
            battlefield: [Card(19, "Prototype Vehicle", "battlefield", 0,
                netPower: 0, netToughness: 0, currentTypes: "[\"artifact\",\"vehicle\"]")]))));

        var changed = reconciler.Apply("session-a", Parse(parser, Frame(2, Player(
            battlefield: [Card(19, "Prototype Vehicle", "battlefield", 0,
                controllerSeatId: "forge-player-2", faceDown: true, phasedOut: true,
                netPower: 3, netToughness: 3,
                currentTypes: "[\"artifact\",\"creature\",\"vehicle\"]")],
            speed: 2, designations: "[\"monarch\",\"citys_blessing\"]"), monarchSeatId: "forge-player-1")));

        var controller = Assert.Single(changed, item => item.Kind == "controller_changed");
        Assert.Equal("forge-player-1", controller.OwnerSeatId);
        Assert.Equal("forge-player-2", controller.ControllerSeatId);
        var characteristic = Assert.Single(changed, item => item.Kind == "characteristic_changed");
        Assert.Contains("creature", characteristic.CurrentTypes!);
        Assert.Equal(3, characteristic.CurrentPower);
        Assert.True(Assert.Single(changed, item => item.Kind == "face_changed").FaceDown);
        Assert.True(Assert.Single(changed, item => item.Kind == "phasing_changed").PhasedOut);
        var designation = Assert.Single(changed, item => item.Kind == "designation_changed");
        Assert.Equal(2, designation.Speed);
        Assert.Equal("forge-player-1", designation.MonarchSeatId);

        var snapshot = reconciler.Current!;
        Assert.Equal("forge-player-1", snapshot.MonarchSeatId);
        Assert.Equal(2, snapshot.Seats[0].Speed);
        Assert.Contains("citys_blessing", snapshot.Seats[0].Designations!);
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

    private static string Frame(long sequence, string player, string reason = "test", string? monarchSeatId = null) =>
        ForgeStructuredOutputParser.Sentinel
        + $$"""{"version":1,"type":"snapshot","sequence":{{sequence}},"reason":"{{reason}}","monarchSeatId":{{(monarchSeatId is null ? "null" : "\"" + monarchSeatId + "\"")}},"players":[{{player}}],"stack":[]}""";

    private static string Player(
        IReadOnlyList<string>? library = null,
        IReadOnlyList<string>? hand = null,
        IReadOnlyList<string>? battlefield = null,
        IReadOnlyList<string>? graveyard = null,
        string manaPool = "{\"W\":0,\"U\":0,\"B\":0,\"R\":0,\"G\":0,\"C\":0}",
        int speed = 0,
        string designations = "[]") =>
        $$"""{"seatId":"forge-player-1","forgePlayerId":1,"displayName":"Player 1","life":20,"poison":0,"counters":{},"manaPool":{{manaPool}},"speed":{{speed}},"designations":{{designations}},"zones":[{"name":"library","cards":[{{string.Join(',', library ?? [])}}]},{"name":"hand","cards":[{{string.Join(',', hand ?? [])}}]},{"name":"battlefield","cards":[{{string.Join(',', battlefield ?? [])}}]},{"name":"graveyard","cards":[{{string.Join(',', graveyard ?? [])}}]},{"name":"exile","cards":[]}]}""";

    private static string Card(
        int id,
        string name,
        string zone,
        int position,
        bool tapped = false,
        string counters = "{}",
        string keywords = "[]",
        int? netPower = null,
        int? netToughness = null,
        string controllerSeatId = "forge-player-1",
        bool faceDown = false,
        bool phasedOut = false,
        string currentTypes = "[]") =>
        $$"""{"forgeCardId":{{id}},"cardName":"{{name}}","currentCardName":"{{name}}","zone":"{{zone}}","zonePosition":{{position}},"ownerSeatId":"forge-player-1","controllerSeatId":"{{controllerSeatId}}","tapped":{{tapped.ToString().ToLowerInvariant()}},"faceDown":{{faceDown.ToString().ToLowerInvariant()}},"phasedOut":{{phasedOut.ToString().ToLowerInvariant()}},"netPower":{{(netPower?.ToString() ?? "null")}},"netToughness":{{(netToughness?.ToString() ?? "null")}},"currentPower":{{(netPower?.ToString() ?? "null")}},"currentToughness":{{(netToughness?.ToString() ?? "null")}},"currentTypes":{{currentTypes}},"counters":{{counters}},"keywords":{{keywords}}}""";
}
