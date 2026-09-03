using MtgTtsBridge.Contracts.State;
using MtgTtsBridge.Forge;

namespace MtgTtsBridge.Tests;

/// <summary>
/// U4 Phase 0 Combat Relationship Characterization Tests
///
/// Purpose: Establish deterministic regression coverage that characterizes how combat information
/// flows through Forge → ForgeStructuredStateReconciler → GameSnapshotDto → TTS without making
/// any U4 implementation changes.
///
/// These tests answer:
/// 1. What combat information does Forge emit?
/// 2. What information survives parsing into bridge structured state?
/// 3. What information survives reconciliation into GameSnapshotDto?
/// 4. What information TTS currently consumes or ignores?
/// 5. Where current representation is insufficient for U4?
///
/// KNOWN ASYMMETRY (intentional until U4):
/// - Attacker and blocker card IDs are normalized to stable CardInstanceId
/// - Defender remains as raw DefenderForgeObjectId (NOT normalized yet)
/// - This is part of U4's contract improvement
/// </summary>
public sealed class CombatRelationshipCharacterizationTests
{
    private static readonly string RepositoryRoot = Path.GetFullPath(
        Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", ".."));

    // TEST SCENARIO 1: Multiple attackers attacking the same player
    [Fact]
    public void MultipleAttackers_AttackingSamePlayer_PreservesAllAttackerIdentities()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        var sessionId = "combat-test-1";

        // Setup: two creatures on battlefield, both will attack
        reconciler.Apply(sessionId, Parse(parser, FrameWithCombat(1, Player(
            battlefield: [
                Card(10, "Grizzly Bears", "battlefield", 0, currentTypes: "[\"creature\"]"),
                Card(11, "Llanowar Elves", "battlefield", 1, currentTypes: "[\"creature\"]")
            ]))));

        // Combat: both creatures attack player 2
        var snapshot2 = Parse(parser, FrameWithCombat(2, Player(
            battlefield: [
                Card(10, "Grizzly Bears", "battlefield", 0, currentTypes: "[\"creature\"]"),
                Card(11, "Llanowar Elves", "battlefield", 1, currentTypes: "[\"creature\"]")
            ]),
            combat: """{"attacks":[{"attackerForgeObjectId":10,"defenderSeatId":"forge-player-2","defenderForgeObjectId":null,"blockerForgeObjectIds":[]},{"attackerForgeObjectId":11,"defenderSeatId":"forge-player-2","defenderForgeObjectId":null,"blockerForgeObjectIds":[]}]}"""));

        var events = reconciler.Apply(sessionId, snapshot2);
        var currentCombat = reconciler.Current!.Combat;
        
        Assert.NotNull(currentCombat);
        Assert.Equal(2, currentCombat.Attacks.Count);
        Assert.Equal($"forge:{sessionId}:10", currentCombat.Attacks[0].AttackerCardInstanceId);
        Assert.Equal($"forge:{sessionId}:11", currentCombat.Attacks[1].AttackerCardInstanceId);
        Assert.Equal("forge-player-2", currentCombat.Attacks[0].DefenderSeatId);
        Assert.Equal("forge-player-2", currentCombat.Attacks[1].DefenderSeatId);
    }

    // TEST SCENARIO 2: Multiple attackers with different defenders (player vs permanent)
    [Fact]
    public void MultipleAttackers_DifferentDefenders_PreservesEachDefenderIdentity()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        var sessionId = "combat-test-2";

        // Setup: player 1 has two creatures, player 2 has a creature on battlefield
        reconciler.Apply(sessionId, Parse(parser, FrameWithCombat(1, Players(
            Player(
                battlefield: [
                    Card(10, "Grizzly Bears", "battlefield", 0, currentTypes: "[\"creature\"]"),
                    Card(11, "Llanowar Elves", "battlefield", 1, currentTypes: "[\"creature\"]")
                ]),
            Player(
                battlefield: [
                    Card(20, "Wall of Frost", "battlefield", 0, 
                        currentTypes: "[\"creature\"]",
                        ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2")
                ],
                seatId: "forge-player-2", forgePlayerId: 2)))));

        // Combat: creature 10 attacks player 2 directly, creature 11 attacks the wall
        var snapshot2 = Parse(parser, FrameWithCombat(2, Players(
            Player(
                battlefield: [
                    Card(10, "Grizzly Bears", "battlefield", 0, currentTypes: "[\"creature\"]"),
                    Card(11, "Llanowar Elves", "battlefield", 1, currentTypes: "[\"creature\"]")
                ]),
            Player(
                battlefield: [
                    Card(20, "Wall of Frost", "battlefield", 0, 
                        currentTypes: "[\"creature\"]",
                        ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2")
                ],
                seatId: "forge-player-2", forgePlayerId: 2)),
            combat: """{"attacks":[{"attackerForgeObjectId":10,"defenderSeatId":"forge-player-2","defenderForgeObjectId":null,"blockerForgeObjectIds":[]},{"attackerForgeObjectId":11,"defenderSeatId":null,"defenderForgeObjectId":20,"blockerForgeObjectIds":[]}]}"""
        ));

        var events = reconciler.Apply(sessionId, snapshot2);
        var currentCombat = reconciler.Current!.Combat;
        
        Assert.NotNull(currentCombat);
        Assert.Equal(2, currentCombat.Attacks.Count);
        
        // First attack is against a player
        Assert.Equal($"forge:{sessionId}:10", currentCombat.Attacks[0].AttackerCardInstanceId);
        Assert.Equal("forge-player-2", currentCombat.Attacks[0].DefenderSeatId);
        Assert.Null(currentCombat.Attacks[0].DefenderForgeObjectId);
        
        // Second attack is against a permanent
        Assert.Equal($"forge:{sessionId}:11", currentCombat.Attacks[1].AttackerCardInstanceId);
        Assert.Null(currentCombat.Attacks[1].DefenderSeatId);
        Assert.Equal(20, currentCombat.Attacks[1].DefenderForgeObjectId);
    }

    // TEST SCENARIO 3: Player defender identity is preserved
    [Fact]
    public void PlayerDefender_IsPreservedInSnapshot()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        var sessionId = "combat-test-3";

        reconciler.Apply(sessionId, Parse(parser, FrameWithCombat(1, Player(
            battlefield: [Card(10, "Goblin Token", "battlefield", 0, currentTypes: "[\"creature\"]")] ))));

        var snapshot2 = Parse(parser, FrameWithCombat(2, Player(
            battlefield: [Card(10, "Goblin Token", "battlefield", 0, currentTypes: "[\"creature\"]")] ),
            combat: """{"attacks":[{"attackerForgeObjectId":10,"defenderSeatId":"forge-player-2","defenderForgeObjectId":null,"blockerForgeObjectIds":[]}]}"""
        ));

        var events = reconciler.Apply(sessionId, snapshot2);
        var attack = Assert.Single(reconciler.Current!.Combat!.Attacks);
        
        Assert.Equal("forge-player-2", attack.DefenderSeatId);
        Assert.Null(attack.DefenderForgeObjectId);
    }

    // TEST SCENARIO 4: Permanent defender Forge object identity is preserved
    [Fact]
    public void PermanentDefender_ForgeObjectIdIsPreserved()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        var sessionId = "combat-test-4";

        reconciler.Apply(sessionId, Parse(parser, FrameWithCombat(1, Players(
            Player(battlefield: [Card(10, "Wolf", "battlefield", 0, currentTypes: "[\"creature\"]")]),  
            Player(
                battlefield: [Card(50, "Planeswalker", "battlefield", 0, 
                    currentTypes: "[\"planeswalker\"]",
                    ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2")],
                seatId: "forge-player-2", forgePlayerId: 2)))));

        var snapshot2 = Parse(parser, FrameWithCombat(2, Players(
            Player(battlefield: [Card(10, "Wolf", "battlefield", 0, currentTypes: "[\"creature\"]")]),
            Player(
                battlefield: [Card(50, "Planeswalker", "battlefield", 0, 
                    currentTypes: "[\"planeswalker\"]",
                    ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2")],
                seatId: "forge-player-2", forgePlayerId: 2)),
            combat: """{"attacks":[{"attackerForgeObjectId":10,"defenderSeatId":null,"defenderForgeObjectId":50,"blockerForgeObjectIds":[]}]}"""
        ));

        var events = reconciler.Apply(sessionId, snapshot2);
        var attack = Assert.Single(reconciler.Current!.Combat!.Attacks);
        
        Assert.Null(attack.DefenderSeatId);
        Assert.Equal(50, attack.DefenderForgeObjectId);
    }

    // TEST SCENARIO 5: Multiple blockers assigned to one attacker survive parsing
    [Fact]
    public void MultipleBlockers_AssignedToOneAttacker_AreAllPreserved()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        var sessionId = "combat-test-5";

        reconciler.Apply(sessionId, Parse(parser, FrameWithCombat(1, Players(
            Player(battlefield: [Card(10, "Attacker", "battlefield", 0, currentTypes: "[\"creature\"]")]),
            Player(
                battlefield: [
                    Card(20, "Blocker 1", "battlefield", 0, currentTypes: "[\"creature\"]",
                        ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2"),
                    Card(21, "Blocker 2", "battlefield", 1, currentTypes: "[\"creature\"]",
                        ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2")
                ],
                seatId: "forge-player-2", forgePlayerId: 2)))));

        var snapshot2 = Parse(parser, FrameWithCombat(2, Players(
            Player(battlefield: [Card(10, "Attacker", "battlefield", 0, currentTypes: "[\"creature\"]")]),
            Player(
                battlefield: [
                    Card(20, "Blocker 1", "battlefield", 0, currentTypes: "[\"creature\"]",
                        ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2"),
                    Card(21, "Blocker 2", "battlefield", 1, currentTypes: "[\"creature\"]",
                        ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2")
                ],
                seatId: "forge-player-2", forgePlayerId: 2)),
            combat: """{"attacks":[{"attackerForgeObjectId":10,"defenderSeatId":"forge-player-2","defenderForgeObjectId":null,"blockerForgeObjectIds":[20,21]}]}"""
        ));

        var events = reconciler.Apply(sessionId, snapshot2);
        var attack = Assert.Single(reconciler.Current!.Combat!.Attacks);
        
        Assert.Equal(2, attack.BlockerCardInstanceIds.Count);
        Assert.Contains($"forge:{sessionId}:20", attack.BlockerCardInstanceIds);
        Assert.Contains($"forge:{sessionId}:21", attack.BlockerCardInstanceIds);
    }

    // TEST SCENARIO 6: Multiple attackers each preserve their own independent blocker lists
    [Fact]
    public void MultipleAttackers_WithIndependentBlockers_PreserveAllRelationships()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        var sessionId = "combat-test-6";

        reconciler.Apply(sessionId, Parse(parser, FrameWithCombat(1, Players(
            Player(battlefield: [
                Card(10, "Attacker 1", "battlefield", 0, currentTypes: "[\"creature\"]"),
                Card(11, "Attacker 2", "battlefield", 1, currentTypes: "[\"creature\"]")
            ]),
            Player(
                battlefield: [
                    Card(20, "Blocker A", "battlefield", 0, currentTypes: "[\"creature\"]",
                        ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2"),
                    Card(21, "Blocker B", "battlefield", 1, currentTypes: "[\"creature\"]",
                        ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2"),
                    Card(22, "Blocker C", "battlefield", 2, currentTypes: "[\"creature\"]",
                        ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2")
                ],
                seatId: "forge-player-2", forgePlayerId: 2)))));

        var snapshot2 = Parse(parser, FrameWithCombat(2, Players(
            Player(battlefield: [
                Card(10, "Attacker 1", "battlefield", 0, currentTypes: "[\"creature\"]"),
                Card(11, "Attacker 2", "battlefield", 1, currentTypes: "[\"creature\"]")
            ]),
            Player(
                battlefield: [
                    Card(20, "Blocker A", "battlefield", 0, currentTypes: "[\"creature\"]",
                        ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2"),
                    Card(21, "Blocker B", "battlefield", 1, currentTypes: "[\"creature\"]",
                        ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2"),
                    Card(22, "Blocker C", "battlefield", 2, currentTypes: "[\"creature\"]",
                        ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2")
                ],
                seatId: "forge-player-2", forgePlayerId: 2)),
            combat: """{"attacks":[{"attackerForgeObjectId":10,"defenderSeatId":"forge-player-2","defenderForgeObjectId":null,"blockerForgeObjectIds":[20,21]},{"attackerForgeObjectId":11,"defenderSeatId":"forge-player-2","defenderForgeObjectId":null,"blockerForgeObjectIds":[22]}]}"""
        ));

        var events = reconciler.Apply(sessionId, snapshot2);
        var attacks = reconciler.Current!.Combat!.Attacks;
        
        Assert.Equal(2, attacks.Count);
        Assert.Equal(2, attacks[0].BlockerCardInstanceIds.Count);
        Assert.Contains($"forge:{sessionId}:20", attacks[0].BlockerCardInstanceIds);
        Assert.Contains($"forge:{sessionId}:21", attacks[0].BlockerCardInstanceIds);
        Assert.Single(attacks[1].BlockerCardInstanceIds);
        Assert.Contains($"forge:{sessionId}:22", attacks[1].BlockerCardInstanceIds);
    }

    // TEST SCENARIO 7: Creature token can appear as an attacker
    [Fact]
    public void CreatureToken_AsAttacker_IsPreserved()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        var sessionId = "combat-test-7";

        reconciler.Apply(sessionId, Parse(parser, FrameWithCombat(1, Player(
            battlefield: [Card(10, "Goblin Token", "battlefield", 0, 
                currentTypes: "[\"creature\"]", isToken: true)] ))));

        var snapshot2 = Parse(parser, FrameWithCombat(2, Player(
            battlefield: [Card(10, "Goblin Token", "battlefield", 0, 
                currentTypes: "[\"creature\"]", isToken: true)] ),
            combat: """{"attacks":[{"attackerForgeObjectId":10,"defenderSeatId":"forge-player-2","defenderForgeObjectId":null,"blockerForgeObjectIds":[]}]}"""
        ));

        var events = reconciler.Apply(sessionId, snapshot2);
        var attack = Assert.Single(reconciler.Current!.Combat!.Attacks);
        
        Assert.Equal($"forge:{sessionId}:10", attack.AttackerCardInstanceId);
        // Verify the token is marked as such in the card snapshot
        var attacker = reconciler.Current.Seats[0].Zones
            .Single(z => z.Name == "battlefield")
            .Cards.Single(c => c.CardInstanceId == attack.AttackerCardInstanceId);
        Assert.True(attacker.IsToken);
    }

    // TEST SCENARIO 8: Creature token can appear as a blocker
    [Fact]
    public void CreatureToken_AsBlocker_IsPreserved()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        var sessionId = "combat-test-8";

        reconciler.Apply(sessionId, Parse(parser, FrameWithCombat(1, Players(
            Player(battlefield: [Card(10, "Attacker", "battlefield", 0, currentTypes: "[\"creature\"]")]),
            Player(
                battlefield: [Card(20, "Goblin Token", "battlefield", 0, 
                    currentTypes: "[\"creature\"]", isToken: true,
                    ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2")],
                seatId: "forge-player-2", forgePlayerId: 2)))));

        var snapshot2 = Parse(parser, FrameWithCombat(2, Players(
            Player(battlefield: [Card(10, "Attacker", "battlefield", 0, currentTypes: "[\"creature\"]")]),
            Player(
                battlefield: [Card(20, "Goblin Token", "battlefield", 0, 
                    currentTypes: "[\"creature\"]", isToken: true,
                    ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2")],
                seatId: "forge-player-2", forgePlayerId: 2)),
            combat: """{"attacks":[{"attackerForgeObjectId":10,"defenderSeatId":"forge-player-2","defenderForgeObjectId":null,"blockerForgeObjectIds":[20]}]}"""
        ));

        var events = reconciler.Apply(sessionId, snapshot2);
        var attack = Assert.Single(reconciler.Current!.Combat!.Attacks);
        
        Assert.Single(attack.BlockerCardInstanceIds);
        Assert.Contains($"forge:{sessionId}:20", attack.BlockerCardInstanceIds);
        // Verify the token is marked as such in the card snapshot
        var blocker = reconciler.Current.Seats[1].Zones
            .Single(z => z.Name == "battlefield")
            .Cards.Single(c => c.CardInstanceId == attack.BlockerCardInstanceIds[0]);
        Assert.True(blocker.IsToken);
    }

    // TEST SCENARIO 9: Combat snapshot with zero attacks is valid and total
    [Fact]
    public void EmptyCombat_WithZeroAttacks_IsValidAndTotal()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        var sessionId = "combat-test-9";

        reconciler.Apply(sessionId, Parse(parser, FrameWithCombat(1, Player(
            battlefield: [Card(10, "Creature", "battlefield", 0, currentTypes: "[\"creature\"]")] ))));

        var snapshot2 = Parse(parser, FrameWithCombat(2, Player(
            battlefield: [Card(10, "Creature", "battlefield", 0, currentTypes: "[\"creature\"]")] ),
            combat: """{"attacks":[]}"""
        ));

        var events = reconciler.Apply(sessionId, snapshot2);
        var currentCombat = reconciler.Current!.Combat;
        
        Assert.NotNull(currentCombat);
        Assert.Empty(currentCombat.Attacks);
    }

    // TEST SCENARIO 10-13: Snapshot equality detects changes in attacker, defender seat, defender object, and blockers
    [Fact]
    public void SnapshotEquality_ChangedAttacker_IsDetected()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        var sessionId = "combat-test-10";

        var snapshot1 = Parse(parser, FrameWithCombat(1, Players(
            Player(battlefield: [
                Card(10, "Attacker 1", "battlefield", 0, currentTypes: "[\"creature\"]"),
                Card(11, "Attacker 2", "battlefield", 1, currentTypes: "[\"creature\"]")
            ]),
            Player(seatId: "forge-player-2", forgePlayerId: 2)),
            combat: """{"attacks":[{"attackerForgeObjectId":10,"defenderSeatId":"forge-player-2","defenderForgeObjectId":null,"blockerForgeObjectIds":[]}]}"""
        ));
        reconciler.Apply(sessionId, snapshot1);
        var first = reconciler.Current!.Combat;

        var snapshot2 = Parse(parser, FrameWithCombat(2, Players(
            Player(battlefield: [
                Card(10, "Attacker 1", "battlefield", 0, currentTypes: "[\"creature\"]"),
                Card(11, "Attacker 2", "battlefield", 1, currentTypes: "[\"creature\"]")
            ]),
            Player(seatId: "forge-player-2", forgePlayerId: 2)),
            combat: """{"attacks":[{"attackerForgeObjectId":11,"defenderSeatId":"forge-player-2","defenderForgeObjectId":null,"blockerForgeObjectIds":[]}]}"""
        ));
        reconciler.Apply(sessionId, snapshot2);
        var second = reconciler.Current!.Combat;

        Assert.NotEqual(first, second);
    }

    [Fact]
    public void SnapshotEquality_ChangedDefenderSeatId_IsDetected()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        var sessionId = "combat-test-11";

        var snapshot1 = Parse(parser, FrameWithCombat(1, Players(
            Player(battlefield: [Card(10, "Attacker", "battlefield", 0, currentTypes: "[\"creature\"]")]),
            Player(seatId: "forge-player-2", forgePlayerId: 2),
            Player(seatId: "forge-player-3", forgePlayerId: 3)),
            combat: """{"attacks":[{"attackerForgeObjectId":10,"defenderSeatId":"forge-player-2","defenderForgeObjectId":null,"blockerForgeObjectIds":[]}]}"""
        ));
        reconciler.Apply(sessionId, snapshot1);
        var first = reconciler.Current!.Combat;

        var snapshot2 = Parse(parser, FrameWithCombat(2, Players(
            Player(battlefield: [Card(10, "Attacker", "battlefield", 0, currentTypes: "[\"creature\"]")]),
            Player(seatId: "forge-player-2", forgePlayerId: 2),
            Player(seatId: "forge-player-3", forgePlayerId: 3)),
            combat: """{"attacks":[{"attackerForgeObjectId":10,"defenderSeatId":"forge-player-3","defenderForgeObjectId":null,"blockerForgeObjectIds":[]}]}"""
        ));
        reconciler.Apply(sessionId, snapshot2);
        var second = reconciler.Current!.Combat;

        Assert.NotEqual(first, second);
    }

    [Fact]
    public void SnapshotEquality_ChangedDefenderForgeObjectId_IsDetected()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        var sessionId = "combat-test-12";

        var snapshot1 = Parse(parser, FrameWithCombat(1, Players(
            Player(battlefield: [Card(10, "Attacker", "battlefield", 0, currentTypes: "[\"creature\"]")]),
            Player(
                battlefield: [
                    Card(20, "Permanent A", "battlefield", 0, currentTypes: "[\"creature\"]",
                        ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2"),
                    Card(21, "Permanent B", "battlefield", 1, currentTypes: "[\"creature\"]",
                        ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2")
                ],
                seatId: "forge-player-2", forgePlayerId: 2)),
            combat: """{"attacks":[{"attackerForgeObjectId":10,"defenderSeatId":null,"defenderForgeObjectId":20,"blockerForgeObjectIds":[]}]}"""
        ));
        reconciler.Apply(sessionId, snapshot1);
        var first = reconciler.Current!.Combat;

        var snapshot2 = Parse(parser, FrameWithCombat(2, Players(
            Player(battlefield: [Card(10, "Attacker", "battlefield", 0, currentTypes: "[\"creature\"]")]),
            Player(
                battlefield: [
                    Card(20, "Permanent A", "battlefield", 0, currentTypes: "[\"creature\"]",
                        ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2"),
                    Card(21, "Permanent B", "battlefield", 1, currentTypes: "[\"creature\"]",
                        ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2")
                ],
                seatId: "forge-player-2", forgePlayerId: 2)),
            combat: """{"attacks":[{"attackerForgeObjectId":10,"defenderSeatId":null,"defenderForgeObjectId":21,"blockerForgeObjectIds":[]}]}"""
        ));
        reconciler.Apply(sessionId, snapshot2);
        var second = reconciler.Current!.Combat;

        Assert.NotEqual(first, second);
    }

    [Fact]
    public void SnapshotEquality_ChangedBlockers_IsDetected()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        var sessionId = "combat-test-13";

        var snapshot1 = Parse(parser, FrameWithCombat(1, Players(
            Player(battlefield: [Card(10, "Attacker", "battlefield", 0, currentTypes: "[\"creature\"]")]),
            Player(
                battlefield: [
                    Card(20, "Blocker 1", "battlefield", 0, currentTypes: "[\"creature\"]",
                        ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2"),
                    Card(21, "Blocker 2", "battlefield", 1, currentTypes: "[\"creature\"]",
                        ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2")
                ],
                seatId: "forge-player-2", forgePlayerId: 2)),
            combat: """{"attacks":[{"attackerForgeObjectId":10,"defenderSeatId":"forge-player-2","defenderForgeObjectId":null,"blockerForgeObjectIds":[20]}]}"""
        ));
        reconciler.Apply(sessionId, snapshot1);
        var first = reconciler.Current!.Combat;

        var snapshot2 = Parse(parser, FrameWithCombat(2, Players(
            Player(battlefield: [Card(10, "Attacker", "battlefield", 0, currentTypes: "[\"creature\"]")]),
            Player(
                battlefield: [
                    Card(20, "Blocker 1", "battlefield", 0, currentTypes: "[\"creature\"]",
                        ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2"),
                    Card(21, "Blocker 2", "battlefield", 1, currentTypes: "[\"creature\"]",
                        ownerSeatId: "forge-player-2", controllerSeatId: "forge-player-2")
                ],
                seatId: "forge-player-2", forgePlayerId: 2)),
            combat: """{"attacks":[{"attackerForgeObjectId":10,"defenderSeatId":"forge-player-2","defenderForgeObjectId":null,"blockerForgeObjectIds":[20,21]}]}"""
        ));
        reconciler.Apply(sessionId, snapshot2);
        var second = reconciler.Current!.Combat;

        Assert.NotEqual(first, second);
    }

    // TEST SCENARIO 14: TTS presentation signature ignores defender identity (KNOWN U4 DEFICIENCY)
    // This test characterizes the CURRENT behavior and serves as documentation that U4
    // implementation must change BridgeApplyCombatSnapshot to include defender in signature.
    [Fact]
    public void TtsPresentationSignature_IgnoresDefender_CharacterizesU4Deficiency()
    {
        // This test verifies the known deficiency: two combat snapshots that differ only
        // in which permanent/player an attacker is attacking will have identical presentation
        // signatures in the current TTS code.
        
        var sessionId = "tts-sig-test";
        var signature1 = ComputePresentationSignature(new GameCombatSnapshotDto(new[]
        {
            new GameCombatAttackSnapshotDto(
                AttackerCardInstanceId: $"forge:{sessionId}:10",
                DefenderSeatId: "forge-player-2",
                DefenderForgeObjectId: null,
                BlockerCardInstanceIds: new[] { $"forge:{sessionId}:20" })
        }));

        var signature2 = ComputePresentationSignature(new GameCombatSnapshotDto(new[]
        {
            new GameCombatAttackSnapshotDto(
                AttackerCardInstanceId: $"forge:{sessionId}:10",
                DefenderSeatId: null,
                DefenderForgeObjectId: 30,
                BlockerCardInstanceIds: new[] { $"forge:{sessionId}:20" })
        }));

        // DEFICIENCY: These are different authoritative combat states but have identical
        // presentation signatures because BridgeApplyCombatSnapshot only includes
        // (attackerCardInstanceId + blockerCardInstanceIds) in its signature.
        Assert.Equal(signature1, signature2);
        // This test documents that U4 must change the signature to include defender identity.
    }

    // HELPER: Compute TTS presentation signature (mirroring BridgeApplyCombatSnapshot logic)
    private static string ComputePresentationSignature(GameCombatSnapshotDto combat)
    {
        var parts = new List<string>();
        foreach (var attack in combat.Attacks)
        {
            var part = $"{attack.AttackerCardInstanceId}|{string.Join(",", attack.BlockerCardInstanceIds)}";
            parts.Add(part);
        }
        parts.Sort();
        return string.Join(";", parts);
    }

    // HELPER METHODS

    private static ForgeStructuredSnapshot Parse(ForgeStructuredOutputParser parser, string frame) =>
        Assert.Single(parser.Append(frame + "\n").Snapshots);

    private static string FrameWithCombat(
        long sequence,
        string player,
        string combat = """{"attacks":[]}""",
        string reason = "test") =>
        ForgeStructuredOutputParser.Sentinel
        + $$"""{"version":1,"type":"snapshot","sequence":{{sequence}},"reason":"{{reason}}","monarchSeatId":null,"players":[{{player}}],"stack":[],"combat":{{combat}}}""";

    private static string Players(params string[] players) => string.Join(',', players);

    private static string Player(
        IReadOnlyList<string>? battlefield = null,
        string seatId = "forge-player-1",
        int forgePlayerId = 1) =>
        $$"""{"seatId":"{{seatId}}","forgePlayerId":{{forgePlayerId}},"displayName":"Player {{forgePlayerId}}","life":20,"poison":0,"counters":{},"manaPool":{"W":0,"U":0,"B":0,"R":0,"G":0,"C":0},"speed":0,"designations":[],"zones":[{"name":"library","cards":[]},{"name":"hand","cards":[]},{"name":"battlefield","cards":[{{string.Join(',', battlefield ?? [])}}]},{"name":"graveyard","cards":[]},{"name":"exile","cards":[]}]}""";

    private static string Card(
        int id,
        string name,
        string zone,
        int position,
        string currentTypes = "[]",
        string ownerSeatId = "forge-player-1",
        string controllerSeatId = "forge-player-1",
        bool isToken = false) =>
        $$"""{"forgeCardId":{{id}},"cardName":"{{name}}","currentCardName":"{{name}}","zone":"{{zone}}","zonePosition":{{position}},"ownerSeatId":"{{ownerSeatId}}","controllerSeatId":"{{controllerSeatId}}","tapped":false,"faceDown":false,"phasedOut":false,"isToken":{{isToken.ToString().ToLowerInvariant()}},"netPower":null,"netToughness":null,"currentPower":null,"currentToughness":null,"currentTypes":{{currentTypes}},"counters":{},"keywords":[]}""";
}
