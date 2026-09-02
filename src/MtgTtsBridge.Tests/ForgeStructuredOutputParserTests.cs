using MtgTtsBridge.Forge;
using MtgTtsBridge.Contracts.State;

namespace MtgTtsBridge.Tests;

public sealed class ForgeStructuredOutputParserTests
{
    [Fact]
    public void EmbeddedStructuredFrame_PreservesTuiPrefixAndRemovesFrame()
    {
        var parser = new ForgeStructuredOutputParser();
        var output = parser.Append("Enter choice (0-1): " + Frame(1, Player()) + "\n");

        Assert.Equal("Enter choice (0-1): ", output.TuiText);
        Assert.Equal(1, Assert.Single(output.Snapshots).Sequence);
        Assert.DoesNotContain(ForgeStructuredOutputParser.Sentinel, output.TuiText);
        Assert.DoesNotContain("\"players\"", output.TuiText);
    }

    [Fact]
    public void EmbeddedSentinel_SplitAcrossChunks_PreservesPrefixAndParsesOnce()
    {
        var parser = new ForgeStructuredOutputParser();
        var embedded = "Enter choice (0-1): " + ForgeStructuredOutputParser.Sentinel;

        var first = parser.Append(embedded[..^5]);
        var second = parser.Append(embedded[^5..] + Frame(1, Player())[
            ForgeStructuredOutputParser.Sentinel.Length..] + "\n");

        Assert.Equal("Enter choice (0-1): ", first.TuiText);
        Assert.Empty(first.Snapshots);
        Assert.Empty(second.TuiText);
        Assert.Equal(1, Assert.Single(second.Snapshots).Sequence);
    }

    [Fact]
    public void StructuredTriggeredAbility_IsPreservedAsIndependentStackObject()
    {
        var parser = new ForgeStructuredOutputParser();
        var frame = Frame(18, Player()).Replace(
            ",\"stack\":[]",
            ",\"stack\":[],\"stackObjects\":[{\"stackObjectId\":\"forge-stack:44\",\"stackKind\":\"triggered-ability\",\"sourceCardInstanceId\":\"forge-object:8\",\"sourceName\":\"Stitcher’s Supplier\",\"controllerSeatId\":\"forge-player-1\",\"abilityName\":\"ETB\",\"abilityText\":\"Mill three cards.\",\"creationSequence\":18,\"stackIndex\":1,\"provenance\":\"trigger\",\"targets\":[]}] ");
        var reconciler = new ForgeStructuredStateReconciler();
        _ = reconciler.Apply("session-stack", Parse(parser, frame));

        var stackObject = Assert.Single(reconciler.Current!.StackObjects!);
        Assert.Equal("forge-stack:44", stackObject.StackObjectId);
        Assert.Equal("triggered-ability", stackObject.StackKind);
        Assert.Equal("forge:session-stack:8", stackObject.SourceCardInstanceId);
        Assert.Equal("Mill three cards.", stackObject.AbilityText);
    }

    [Fact]
    public void StructuredJson_SplitAcrossManyChunks_ParsesOnceWithoutJsonLeakage()
    {
        var parser = new ForgeStructuredOutputParser();
        var frame = Frame(1, Player());
        var outputs = new List<ForgeStructuredOutputResult>();
        for (var offset = 0; offset < frame.Length; offset += 17)
        {
            var length = Math.Min(17, frame.Length - offset);
            outputs.Add(parser.Append(frame.Substring(offset, length)));
        }
        outputs.Add(parser.Append("\n"));

        Assert.Empty(outputs.SelectMany(output => output.TuiText));
        var snapshot = Assert.Single(outputs.SelectMany(output => output.Snapshots));
        Assert.Equal(1, snapshot.Sequence);
    }

    [Fact]
    public void OrdinaryTuiTextOnly_IsPreserved()
    {
        var parser = new ForgeStructuredOutputParser();

        var output = parser.Append("Enter choice (0-1): ");

        Assert.Equal("Enter choice (0-1): ", output.TuiText);
        Assert.Empty(output.Snapshots);
    }

    [Fact]
    public void MultipleStructuredFrames_AreParsedInOrder()
    {
        var parser = new ForgeStructuredOutputParser();

        var output = parser.Append(Frame(1, Player()) + "\n" + Frame(2, Player()) + "\n");

        Assert.Equal([1, 2], output.Snapshots.Select(snapshot => snapshot.Sequence));
        Assert.Empty(output.TuiText);
    }

    [Fact]
    public void TuiTextBeforeAndAfterStructuredFrames_IsPreservedInOrder()
    {
        var parser = new ForgeStructuredOutputParser();

        var output = parser.Append("before\n" + Frame(1, Player()) + "\nafter\n");

        Assert.Equal("before\nafter\n", output.TuiText);
        Assert.Single(output.Snapshots);
    }

    [Fact]
    public void CapturedStartupSequence_ParsesEmbeddedOpeningHandSnapshotAsCurrent()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        var humanLibrary = Enumerable.Range(1, 61).Select(id => Card(id, "Island", "library", id - 1)).ToArray();
        var opponentLibrary = Enumerable.Range(100, 60).Select(id => Card(id, "Forest", "library", id - 100,
            ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2")).ToArray();
        var humanHand = Enumerable.Range(1, 7).Select(id => Card(id, "Island", "hand", id - 1)).ToArray();
        var opponentHand = Enumerable.Range(100, 7).Select(id => Card(id, "Forest", "hand", id - 100,
            ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2")).ToArray();
        var humanLibraryAfterDeal = Enumerable.Range(8, 54).Select(id => Card(id, "Island", "library", id - 8)).ToArray();
        var opponentLibraryAfterDeal = Enumerable.Range(107, 53).Select(id => Card(id, "Forest", "library", id - 107,
            ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2")).ToArray();

        var snapshot1 = Frame(1, Players(
            Player(library: humanLibrary),
            Player(library: [], seatId: "forge-player-2", forgePlayerId: 2)));
        var snapshot2 = Frame(2, Players(
            Player(library: humanLibrary),
            Player(library: opponentLibrary, seatId: "forge-player-2", forgePlayerId: 2)));
        var snapshot3 = Frame(3, Players(
            Player(library: humanLibraryAfterDeal, hand: humanHand),
            Player(library: opponentLibraryAfterDeal, hand: opponentHand,
                seatId: "forge-player-2", forgePlayerId: 2)));

        Assert.Empty(reconciler.Apply("session-a", Parse(parser, snapshot1)));
        _ = reconciler.Apply("session-a", Parse(parser, snapshot2));

        var output = parser.Append("Enter choice (0-1): " + snapshot3 + "\n");
        Assert.Equal("Enter choice (0-1): ", output.TuiText);
        var currentEvents = reconciler.Apply("session-a", Assert.Single(output.Snapshots));

        Assert.NotEmpty(currentEvents);
        Assert.Equal(3, reconciler.Current!.ForgeSequence);
        Assert.Equal(7, reconciler.Current.Seats.Single(seat => seat.SeatId == "forge-player-1")
            .Zones.Single(zone => zone.Name == "hand").Cards.Count);
        Assert.Equal(7, reconciler.Current.Seats.Single(seat => seat.SeatId == "forge-player-2")
            .Zones.Single(zone => zone.Name == "hand").Cards.Count);
    }

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
    public void ThoughtScour_ReconciliationEmitsTwoTargetMillMovesAndTheControllerDraw()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();

        var initial = Frame(1, Players(
            Player(
                library: [Card(1, "Island", "library", 0), Card(15, "Stitcher's Supplier", "library", 1)],
                hand: [Card(50, "Thought Scour", "hand", 0)]),
            Player(
                library:
                [
                    Card(86, "Baleful Strix", "library", 0, ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2"),
                    Card(98, "Recruiter of the Guard", "library", 1, ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2"),
                    Card(100, "Forest", "library", 2, ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2")
                ],
                seatId: "forge-player-2",
                forgePlayerId: 2)));
        Assert.Empty(reconciler.Apply("session-a", Parse(parser, initial)));

        var changed = Frame(2, Players(
            Player(
                library: [Card(1, "Island", "library", 0)],
                hand:
                [
                    Card(50, "Thought Scour", "hand", 0),
                    Card(15, "Stitcher's Supplier", "hand", 1)
                ]),
            Player(
                library: [Card(100, "Forest", "library", 0, ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2")],
                graveyard:
                [
                    Card(86, "Baleful Strix", "graveyard", 0, ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2"),
                    Card(98, "Recruiter of the Guard", "graveyard", 1, ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2")
                ],
                seatId: "forge-player-2",
                forgePlayerId: 2)));
        var events = reconciler.Apply("session-a", Parse(parser, changed));

        var draw = Assert.Single(events, item => item.Kind == "draw");
        Assert.Equal("forge-player-1", draw.SeatId);
        Assert.Equal(15, draw.ForgeObjectId);

        var milled = events
            .Where(item => item.Kind == "card_moved"
                && item.SeatId == "forge-player-2"
                && item.SourceZone == "library"
                && item.DestinationZone == "graveyard")
            .ToArray();
        Assert.Equal([86, 98], milled.Select(item => item.ForgeObjectId));
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
    public void Reconciliation_PreservesAuthoritativeBattlefieldRowForLandAndCreature()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        var initial = Parse(parser, Frame(1, Player(
            battlefield: [
                Card(12, "Forest", "battlefield", 0, currentTypes: "[\"basic\",\"land\"]"),
                Card(19, "Hired Claw", "battlefield", 1, currentTypes: "[\"creature\"]")])));

        Assert.Empty(reconciler.Apply("session-a", initial));

        var battlefield = reconciler.Current!.Seats[0].Zones
            .Single(zone => zone.Name == "battlefield").Cards;
        Assert.Equal("land", battlefield.Single(card => card.ForgeCardId == 12).BattlefieldKind);
        Assert.Equal("creature", battlefield.Single(card => card.ForgeCardId == 19).BattlefieldKind);
    }

    [Fact]
    public void Reconciliation_CarriesBattlefieldRowOnZoneMoveEvents()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        reconciler.Apply("session-a", Parse(parser, Frame(1, Player(
            hand: [Card(12, "Forest", "hand", 0)]))));

        var events = reconciler.Apply("session-a", Parse(parser, Frame(2, Player(
            battlefield: [Card(12, "Forest", "battlefield", 0, currentTypes: "[\"land\"]")]))) );

        var moved = Assert.Single(events, item => item.Kind == "card_moved");
        Assert.Equal("land", moved.BattlefieldKind);
    }

    [Fact]
    public void Reconciliation_CarriesForgeTokenProvenanceOnAnExactBattlefieldMove()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        Assert.Empty(reconciler.Apply("session-a", Parse(parser, Frame(1, Player()))));

        var events = reconciler.Apply("session-a", Parse(parser, Frame(2, Player(
            battlefield: [Card(123, "Elemental Token", "battlefield", 0,
                currentTypes: "[\"creature\",\"elemental\"]", isToken: true)]))));

        var moved = Assert.Single(events, item => item.Kind == "card_moved");
        Assert.Equal(123, moved.ForgeObjectId);
        Assert.True(moved.IsToken);
        var snapshotCard = Assert.Single(reconciler.Current!.Seats[0].Zones
            .Single(zone => zone.Name == "battlefield").Cards);
        Assert.True(snapshotCard.IsToken);
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
    public void Reconciliation_EmitsExactGraveyardToBattlefieldReturnForTargetedSorcery()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();

        reconciler.Apply("session-a", Parse(parser, Frame(1, Player(
            graveyard: [Card(417, "Tune Up", "graveyard", 0), Card(88, "Cargo Ship", "graveyard", 1)]))));

        var events = reconciler.Apply("session-a", Parse(parser, Frame(2, Player(
            graveyard: [Card(417, "Tune Up", "graveyard", 0)],
            battlefield: [Card(88, "Cargo Ship", "battlefield", 0, currentTypes: "[\"artifact\",\"vehicle\"]")]))) );

        var moved = Assert.Single(events, item => item.Kind == "card_moved" && item.ForgeObjectId == 88);
        Assert.Equal("graveyard", moved.SourceZone);
        Assert.Equal("battlefield", moved.DestinationZone);
        Assert.Equal("creature", moved.BattlefieldKind);
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
    public void Reconciliation_RejectsDuplicateStructuredIdentityWithBothAuthoritativeLocations()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        var card = Card(91, "Worldly Tutor", "hand", 0);
        var frame = ForgeStructuredOutputParser.Sentinel
            + $$"""{"version":1,"type":"snapshot","sequence":9,"reason":"duplicate-canary","monarchSeatId":null,"players":[{{Player(hand: [card])}}],"stack":[{{card}}]}""";

        var exception = Assert.Throws<ForgeStructuredDuplicateCardInstanceException>(
            () => reconciler.Apply("new-session", Parse(parser, frame)));

        Assert.Equal("forge:new-session:91", exception.CardInstanceId);
        Assert.Equal(9, exception.ForgeSequence);
        Assert.Equal(2, exception.Locations.Count);
        Assert.Contains(exception.Locations, location => location.Contains("zone=hand", StringComparison.Ordinal));
        Assert.Contains(exception.Locations, location => location.StartsWith("stack ", StringComparison.Ordinal));
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
    public void FloatingManaSequence_RemainsAbsoluteAcrossSpendAndNewManaSource()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        reconciler.Apply("session-a", Parse(parser, Frame(1, Player(manaPool: "{\"W\":0,\"U\":0,\"B\":0,\"R\":0,\"G\":0,\"C\":0}"))));

        var ritual = reconciler.Apply("session-a", Parse(parser, Frame(2, Player(manaPool: "{\"W\":0,\"U\":0,\"B\":3,\"R\":0,\"G\":0,\"C\":0}"))));
        Assert.Equal(3, Assert.Single(ritual, item => item.Kind == "mana_pool_changed").ManaPool!["B"]);

        var spent = reconciler.Apply("session-a", Parse(parser, Frame(3, Player(manaPool: "{\"W\":0,\"U\":0,\"B\":1,\"R\":0,\"G\":0,\"C\":0}"))));
        Assert.Equal(1, Assert.Single(spent, item => item.Kind == "mana_pool_changed").ManaPool!["B"]);

        var replenished = reconciler.Apply("session-a", Parse(parser, Frame(4, Player(manaPool: "{\"W\":0,\"U\":0,\"B\":4,\"R\":0,\"G\":0,\"C\":0}"))));
        Assert.Equal(4, Assert.Single(replenished, item => item.Kind == "mana_pool_changed").ManaPool!["B"]);
        Assert.Equal(4, reconciler.Current!.Seats[0].ManaPool!["B"]);
    }

    [Fact]
    public void PlayerCounterChanges_AreCarriedOnAuthoritativePlayerStateEvents()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        reconciler.Apply("session-a", Parse(parser, Frame(1, Player())));

        var events = reconciler.Apply("session-a", Parse(parser, Frame(2,
            Player(counters: "{\"energy\":2,\"experience\":1}"))));

        var playerState = Assert.Single(events, item => item.Kind == "player_state");
        Assert.Equal(2, playerState.Counters!["energy"]);
        Assert.Equal(1, playerState.Counters["experience"]);
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
    public void MalformedFrame_IncludesSafeJsonExceptionMetadata()
    {
        var parser = new ForgeStructuredOutputParser();
        var frame = ForgeStructuredOutputParser.Sentinel
            + """{"version":1,"type":"snapshot","sequence":1,"reason":"test","players":[{"seatId":"forge-player-1","forgePlayerId":1,"displayName":"Player 1","life":20,"poison":0,"counters":{},"manaPool":{"W":0},"speed":0,"designations":[],"zones":[{"name":"battlefield","cards":[{"forgeCardId":10,"cardName":"Jace","currentCardName":"Jace","zone":"battlefield","zonePosition":0,"ownerSeatId":"forge-player-1","controllerSeatId":"forge-player-1","tapped":false,"faceDown":false,"phasedOut":false,"counters":{},"keywords":[],"characteristics":{"currentCardName":"Jace","currentManaCost":"{2}{U}{U}","currentManaValue":"oops","currentColors":["blue"],"currentSupertypes":["legendary"],"currentCardTypes":["planeswalker"],"currentSubtypes":["jace"],"currentPower":null,"currentToughness":null,"currentLoyalty":"4","currentDefense":null,"currentKeywords":[]}}]},{"name":"library","cards":[]},{"name":"hand","cards":[]},{"name":"graveyard","cards":[]},{"name":"exile","cards":[]}]}],"stack":[]}""" + "\n";

        var exception = Assert.Throws<ForgeStructuredFrameException>(() => parser.Append(frame));
        Assert.Contains("Forge emitted malformed structured state JSON", exception.Message, StringComparison.Ordinal);
        Assert.Contains("path=", exception.Message, StringComparison.Ordinal);
        Assert.Contains("line=", exception.Message, StringComparison.Ordinal);
        Assert.Contains("byte=", exception.Message, StringComparison.Ordinal);
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

    [Fact]
    public void StructuredTurnStateDrivesMainOneWithoutWaitingForLegacyTuiText()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        Assert.Empty(reconciler.Apply("session-a", Parse(parser, Frame(
            1, Player(), turnNumber: 1, activeSeatId: "forge-player-1",
            prioritySeatId: "forge-player-1", phase: "Draw Step"))));

        var events = reconciler.Apply("session-a", Parse(parser, Frame(
            2, Player(), turnNumber: 1, activeSeatId: "forge-player-1",
            prioritySeatId: "forge-player-1", phase: "Main phase, precombat")));

        Assert.Contains(events, item => item.Kind == "phase_changed"
            && item.Phase == "Main phase, precombat"
            && item.TurnNumber == 1
            && item.ActiveSeatId == "forge-player-1"
            && item.PrioritySeatId == "forge-player-1");
        Assert.Equal("Main phase, precombat", reconciler.Current!.Phase);
        Assert.Equal("forge-player-1", reconciler.Current.PrioritySeatId);
    }

    private static ForgeStructuredSnapshot Parse(ForgeStructuredOutputParser parser, string frame) =>
        Assert.Single(parser.Append(frame + "\n").Snapshots);

    private static string Frame(
        long sequence,
        string player,
        string reason = "test",
        string? monarchSeatId = null,
        int? turnNumber = null,
        string? activeSeatId = null,
        string? prioritySeatId = null,
        string? phase = null) =>
        ForgeStructuredOutputParser.Sentinel
        + $$"""{"version":1,"type":"snapshot","sequence":{{sequence}},"reason":"{{reason}}","monarchSeatId":{{(monarchSeatId is null ? "null" : "\"" + monarchSeatId + "\"")}},"turnNumber":{{(turnNumber is null ? "null" : turnNumber.Value.ToString())}},"activeSeatId":{{(activeSeatId is null ? "null" : "\"" + activeSeatId + "\"")}},"prioritySeatId":{{(prioritySeatId is null ? "null" : "\"" + prioritySeatId + "\"")}},"phase":{{(phase is null ? "null" : "\"" + phase + "\"")}},"players":[{{player}}],"stack":[]}""";

    private static string Players(params string[] players) => string.Join(',', players);

    private static string Player(
        IReadOnlyList<string>? library = null,
        IReadOnlyList<string>? hand = null,
        IReadOnlyList<string>? battlefield = null,
        IReadOnlyList<string>? graveyard = null,
        string manaPool = "{\"W\":0,\"U\":0,\"B\":0,\"R\":0,\"G\":0,\"C\":0}",
        string counters = "{}",
        int speed = 0,
        string designations = "[]",
        string seatId = "forge-player-1",
        int forgePlayerId = 1) =>
        $$"""{"seatId":"{{seatId}}","forgePlayerId":{{forgePlayerId}},"displayName":"Player {{forgePlayerId}}","life":20,"poison":0,"counters":{{counters}},"manaPool":{{manaPool}},"speed":{{speed}},"designations":{{designations}},"zones":[{"name":"library","cards":[{{string.Join(',', library ?? [])}}]},{"name":"hand","cards":[{{string.Join(',', hand ?? [])}}]},{"name":"battlefield","cards":[{{string.Join(',', battlefield ?? [])}}]},{"name":"graveyard","cards":[{{string.Join(',', graveyard ?? [])}}]},{"name":"exile","cards":[]}]}""";

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
        string currentTypes = "[]",
        string ownerSeatId = "forge-player-1",
        bool isToken = false) =>
        $$"""{"forgeCardId":{{id}},"cardName":"{{name}}","currentCardName":"{{name}}","zone":"{{zone}}","zonePosition":{{position}},"ownerSeatId":"{{ownerSeatId}}","controllerSeatId":"{{controllerSeatId}}","tapped":{{tapped.ToString().ToLowerInvariant()}},"faceDown":{{faceDown.ToString().ToLowerInvariant()}},"phasedOut":{{phasedOut.ToString().ToLowerInvariant()}},"isToken":{{isToken.ToString().ToLowerInvariant()}},"netPower":{{(netPower?.ToString() ?? "null")}},"netToughness":{{(netToughness?.ToString() ?? "null")}},"currentPower":{{(netPower?.ToString() ?? "null")}},"currentToughness":{{(netToughness?.ToString() ?? "null")}},"currentTypes":{{currentTypes}},"counters":{{counters}},"keywords":{{keywords}}}""";

    [Fact]
    public void SnapshotReconstruction_UsesForgeStructuredCharacteristicsPayload()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        var frame = Frame(1, Player(
            battlefield:
            [
                """{"forgeCardId":10,"cardName":"Prototype Vehicle","currentCardName":"Prototype Vehicle","zone":"battlefield","zonePosition":0,"ownerSeatId":"forge-player-1","controllerSeatId":"forge-player-1","tapped":false,"faceDown":false,"phasedOut":false,"netPower":3,"netToughness":3,"currentPower":3,"currentToughness":3,"currentTypes":["artifact","creature","vehicle"],"counters":{"loyalty":2},"keywords":["Flying"],"characteristics":{"currentCardName":"Prototype Vehicle","currentManaCost":"{1}{U}","currentManaValue":2,"currentColors":["blue"],"currentSupertypes":["legendary"],"currentCardTypes":["artifact","creature"],"currentSubtypes":["vehicle"],"currentPower":"3","currentToughness":"3","currentLoyalty":"4","currentDefense":null,"currentKeywords":["Flying"]}}"""
            ]));

        _ = reconciler.Apply("session-a", Parse(parser, frame));
        var card = Assert.Single(reconciler.Current!.Seats[0].Zones.Single(zone => zone.Name == "battlefield").Cards);
        var characteristics = Assert.IsType<CurrentCharacteristicsDto>(card.Characteristics);
        Assert.Equal("{1}{U}", characteristics.CurrentManaCost);
        Assert.Equal(2, characteristics.CurrentManaValue);
        Assert.Equal(["blue"], characteristics.CurrentColors);
        Assert.Equal(["legendary"], characteristics.CurrentSupertypes);
        Assert.Equal(["artifact", "creature"], characteristics.CurrentCardTypes);
        Assert.Equal(["vehicle"], characteristics.CurrentSubtypes);
        Assert.Equal("3", characteristics.CurrentPower);
        Assert.Equal("3", characteristics.CurrentToughness);
        Assert.Equal("4", characteristics.CurrentLoyalty);
        Assert.Contains("Flying", characteristics.CurrentKeywords!);
    }

    [Fact]
    public void SnapshotReconstruction_PreservesGenericCopyVirtualIdentity()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        var frame = Frame(7, Player(
            hand: ["{\"forgeCardId\":41,\"cardName\":\"Original\",\"currentCardName\":\"Original\",\"zone\":\"hand\",\"zonePosition\":0,\"ownerSeatId\":\"forge-player-1\",\"controllerSeatId\":\"forge-player-1\",\"tapped\":false,\"faceDown\":false,\"phasedOut\":false,\"counters\":{},\"keywords\":[],\"authoritativeObjectId\":\"card-41\",\"objectKind\":\"physical-original\"}"],
            seatId: "forge-player-1",
            forgePlayerId: 1));
        // Replace the empty stack in the compact fixture with a distinct
        // authoritative virtual copy, keeping the test focused on transport.
        frame = frame.Replace(",\"stack\":[]", ",\"stack\":[{\"forgeCardId\":99,\"cardName\":\"Original\",\"currentCardName\":\"Copied Original\",\"zone\":\"stack\",\"zonePosition\":0,\"ownerSeatId\":\"forge-player-1\",\"controllerSeatId\":\"forge-player-1\",\"tapped\":false,\"faceDown\":false,\"phasedOut\":false,\"counters\":{},\"keywords\":[],\"authoritativeObjectId\":\"copy-99\",\"originObjectId\":\"card-41\",\"copySourceObjectId\":\"card-41\",\"objectKind\":\"copy-spell\",\"isCopy\":true,\"isVirtual\":true,\"materializationPolicy\":\"virtual-stack\"}]");

        _ = reconciler.Apply("session-u3", Parse(parser, frame));
        var copy = Assert.Single(reconciler.Current!.Stack);
        Assert.Equal("forge:session-u3:copy-99", copy.CardInstanceId);
        Assert.Equal("copy-spell", copy.ObjectKind);
        Assert.True(copy.IsCopy);
        Assert.True(copy.IsVirtual);
        Assert.Equal("forge:session-u3:card-41", copy.CopySourceObjectId);
        Assert.Equal("virtual-stack", copy.MaterializationPolicy);
    }

    [Fact]
    public void NewlyAppearedCopyPermanentEvent_PreservesCreatorAndCopiedObjectSeparately()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        var original = """{"forgeCardId":4,"cardName":"Young Pyromancer","currentCardName":"Young Pyromancer","zone":"battlefield","zonePosition":0,"ownerSeatId":"forge-player-1","controllerSeatId":"forge-player-1","tapped":false,"faceDown":false,"phasedOut":false,"counters":{},"keywords":[],"currentTypes":["creature"],"authoritativeObjectId":"forge-object:4","objectKind":"physical-original"}""";
        var copy = """{"forgeCardId":126,"cardName":"Young Pyromancer","currentCardName":"Young Pyromancer","zone":"battlefield","zonePosition":1,"ownerSeatId":"forge-player-1","controllerSeatId":"forge-player-1","tapped":false,"faceDown":false,"phasedOut":false,"counters":{},"keywords":["Haste"],"currentTypes":["creature"],"isToken":true,"authoritativeObjectId":"forge-object:126","originObjectId":"forge-object:30","copySourceObjectId":"forge-object:4","objectKind":"copy-permanent","isCopy":true,"materializationPolicy":"physical"}""";

        _ = reconciler.Apply("session-copy", Parse(parser, Frame(1, Player(battlefield: [original]))));
        var events = reconciler.Apply("session-copy", Parse(parser, Frame(2, Player(battlefield: [original, copy]))));

        var moved = Assert.Single(events, item => item.Kind == "card_moved" && item.ForgeObjectId == 126);
        Assert.True(moved.IsToken);
        Assert.True(moved.IsCopy);
        Assert.Equal("forge:session-copy:126", moved.AuthoritativeObjectId);
        Assert.Equal("forge:session-copy:30", moved.OriginObjectId);
        Assert.Equal("forge:session-copy:4", moved.CopySourceObjectId);
        Assert.Equal("copy-permanent", moved.ObjectKind);
        Assert.Equal("physical", moved.MaterializationPolicy);
    }

    [Fact]
    public void CharacteristicChangedEvent_CarriesStructuredCharacteristics()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        _ = reconciler.Apply("session-a", Parse(parser, Frame(1, Player(
            battlefield:
            [
                """{"forgeCardId":11,"cardName":"Adaptive Form","currentCardName":"Adaptive Form","zone":"battlefield","zonePosition":0,"ownerSeatId":"forge-player-1","controllerSeatId":"forge-player-1","tapped":false,"faceDown":false,"phasedOut":false,"netPower":2,"netToughness":2,"currentPower":2,"currentToughness":2,"currentTypes":["creature"],"counters":{},"keywords":[],"characteristics":{"currentCardName":"Adaptive Form","currentManaCost":"{1}{G}","currentManaValue":2,"currentColors":["green"],"currentSupertypes":[],"currentCardTypes":["creature"],"currentSubtypes":["shapeshifter"],"currentPower":"2","currentToughness":"2","currentLoyalty":null,"currentDefense":null,"currentKeywords":[]}}"""
            ]))));

        var events = reconciler.Apply("session-a", Parse(parser, Frame(2, Player(
            battlefield:
            [
                """{"forgeCardId":11,"cardName":"Adaptive Form","currentCardName":"Adaptive Form","zone":"battlefield","zonePosition":0,"ownerSeatId":"forge-player-1","controllerSeatId":"forge-player-1","tapped":false,"faceDown":false,"phasedOut":false,"netPower":4,"netToughness":4,"currentPower":4,"currentToughness":4,"currentTypes":["creature"],"counters":{},"keywords":["Trample"],"characteristics":{"currentCardName":"Adaptive Form","currentManaCost":"{1}{G}","currentManaValue":2,"currentColors":["green","red"],"currentSupertypes":[],"currentCardTypes":["creature"],"currentSubtypes":["shapeshifter"],"currentPower":"4","currentToughness":"4","currentLoyalty":null,"currentDefense":null,"currentKeywords":["Trample"]}}"""
            ]))));

        var characteristic = Assert.Single(events, item => item.Kind == "characteristic_changed");
        var payload = Assert.IsType<CurrentCharacteristicsDto>(characteristic.Characteristics);
        Assert.Equal(["green", "red"], payload.CurrentColors);
        Assert.Equal("4", payload.CurrentPower);
        Assert.Contains("Trample", payload.CurrentKeywords!);
    }

    [Fact]
    public void CharacteristicsLoyaltyAndDefense_UseForgeStringShapeAcrossCardKinds()
    {
        var parser = new ForgeStructuredOutputParser();
        var snapshot = Parse(parser, Frame(1, Player(
            battlefield:
            [
                """{"forgeCardId":21,"cardName":"Grizzly Bears","currentCardName":"Grizzly Bears","zone":"battlefield","zonePosition":0,"ownerSeatId":"forge-player-1","controllerSeatId":"forge-player-1","tapped":false,"faceDown":false,"phasedOut":false,"netPower":2,"netToughness":2,"currentPower":2,"currentToughness":2,"currentTypes":["creature"],"counters":{},"keywords":[],"characteristics":{"currentCardName":"Grizzly Bears","currentManaCost":"{1}{G}","currentManaValue":2,"currentColors":["green"],"currentSupertypes":[],"currentCardTypes":["creature"],"currentSubtypes":["bear"],"currentPower":"2","currentToughness":"2","currentLoyalty":null,"currentDefense":null,"currentKeywords":[]}}""",
                """{"forgeCardId":22,"cardName":"Jace","currentCardName":"Jace","zone":"battlefield","zonePosition":1,"ownerSeatId":"forge-player-1","controllerSeatId":"forge-player-1","tapped":false,"faceDown":false,"phasedOut":false,"netPower":null,"netToughness":null,"currentPower":null,"currentToughness":null,"currentTypes":["planeswalker"],"counters":{"loyalty":2},"keywords":[],"characteristics":{"currentCardName":"Jace","currentManaCost":"{2}{U}{U}","currentManaValue":4,"currentColors":["blue"],"currentSupertypes":["legendary"],"currentCardTypes":["planeswalker"],"currentSubtypes":["jace"],"currentPower":null,"currentToughness":null,"currentLoyalty":"4","currentDefense":null,"currentKeywords":[]}}""",
                """{"forgeCardId":23,"cardName":"Invasion of Zendikar","currentCardName":"Invasion of Zendikar","zone":"battlefield","zonePosition":2,"ownerSeatId":"forge-player-1","controllerSeatId":"forge-player-1","tapped":false,"faceDown":false,"phasedOut":false,"netPower":null,"netToughness":null,"currentPower":null,"currentToughness":null,"currentTypes":["battle"],"counters":{"defense":3},"keywords":[],"characteristics":{"currentCardName":"Invasion of Zendikar","currentManaCost":"{3}{G}","currentManaValue":4,"currentColors":["green"],"currentSupertypes":[],"currentCardTypes":["battle"],"currentSubtypes":["siege"],"currentPower":null,"currentToughness":null,"currentLoyalty":null,"currentDefense":"5","currentKeywords":[]}}"""
            ])));

        var cards = snapshot.Players[0].Zones.Single(zone => zone.Name == "battlefield").Cards;
        Assert.Null(cards.Single(card => card.ForgeCardId == 21).Characteristics?.CurrentLoyalty);
        Assert.Null(cards.Single(card => card.ForgeCardId == 21).Characteristics?.CurrentDefense);
        Assert.Equal("4", cards.Single(card => card.ForgeCardId == 22).Characteristics?.CurrentLoyalty);
        Assert.Equal("5", cards.Single(card => card.ForgeCardId == 23).Characteristics?.CurrentDefense);
    }
}
