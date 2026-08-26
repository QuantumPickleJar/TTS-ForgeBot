using MtgTtsBridge.Forge;

namespace MtgTtsBridge.Tests;

public sealed class ForgeTuiEventParserTests
{
    private static readonly Dictionary<string, string> Seats = new(StringComparer.OrdinalIgnoreCase)
    {
        ["Player 1"] = "forge-player-1",
        ["AI-monored"] = "forge-player-2",
    };

    [Fact]
    public void RealAuthoritativeLines_ParseInOrderWithSeatAndInstanceIdentity()
    {
        var transcript = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "forge-tui-authoritative-events.txt"));
        var parser = new ForgeTuiEventParser(Seats);

        var first = parser.Append(transcript[..100]);
        var second = parser.Append(transcript[100..]);
        var events = first.Concat(second).ToArray();

        Assert.Equal(
            ["turn_changed", "phase_changed", "land_played", "mana_ability_used", "spell_cast", "spell_resolved", "land_played", "spell_cast", "spell_resolved", "attack_declared", "attack_declared", "card_moved", "player_state"],
            events.Select(item => item.Kind));
        Assert.Equal("forge-player-2", events[6].SeatId);
        Assert.Equal(128, events[6].ForgeObjectId);
        Assert.Equal("forge-player-2", events[8].SeatId);
        Assert.Equal("Emberheart Challenger", events[9].CardName);
        Assert.Equal(92, events[9].ForgeObjectId);
        Assert.Equal("graveyard", events[11].DestinationZone);
        Assert.Equal(47, events[11].ForgeObjectId);
        Assert.Equal(19, events[12].LifeTotal);
    }

    [Fact]
    public void Reset_ClearsCrossSessionCardAndStackCorrelation()
    {
        var parser = new ForgeTuiEventParser(Seats);
        parser.Append("+++ Land: AI-monored played Mountain (128)\n+++ Add To Stack: AI-monored cast Hired Claw\n");
        parser.Reset();

        var events = parser.Append("+++ Mana: Mountain (128) - {T}: Add {R}.\n+++ Resolve Stack: Hired Claw - Creature 1 / 2\n");

        Assert.All(events, item => Assert.Null(item.SeatId));
    }

    [Fact]
    public void RealPlayerSnapshots_EmitInitialAndChangedLifeOnly()
    {
        var parser = new ForgeTuiEventParser(Seats);
        var transcript = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "forge-tui-player-state.txt"));
        var events = parser.Append(transcript).Concat(parser.Append("    AI-monored\n      Life: 17\n")).ToArray();

        Assert.Equal(3, events.Length);
        Assert.Equal(["forge-player-1", "forge-player-2", "forge-player-2"], events.Select(item => item.SeatId));
        Assert.Equal([20, 20, 17], events.Select(item => item.LifeTotal));
    }

    [Fact]
    public void Reset_ClearsLifeSnapshotDeduplication()
    {
        var parser = new ForgeTuiEventParser(Seats);
        parser.Append(">>> [YOU] Player 1\n>>> [YOU]   Life: 20\n");
        parser.Reset();

        var events = parser.Append(">>> [YOU] Player 1\n>>> [YOU]   Life: 20\n");

        Assert.Single(events);
    }

    [Fact]
    public void RealInstantResolution_UsesForgeIdAndMovesStackToGraveyard()
    {
        var parser = new ForgeTuiEventParser(Seats);
        var events = parser.Append(
            "+++ Add To Stack: Player 1 cast Burst Lightning targeting [AI-monored]\n" +
            "+++ Resolve Stack: Burst Lightning (6) - Burst Lightning (6) deals 2 damage to AI-monored.\n");

        Assert.Equal(2, events.Count);
        Assert.Equal("spell_resolved", events[1].Kind);
        Assert.Equal(6, events[1].ForgeObjectId);
        Assert.Equal("graveyard", events[1].DestinationZone);
        Assert.Equal("forge-player-1", events[1].SeatId);
    }

    [Fact]
    public void TriggerResolution_DoesNotInventCardZoneTransition()
    {
        var parser = new ForgeTuiEventParser(Seats);
        var events = parser.Append(
            "+++ Add To Stack: AI-monored triggered Hired Claw targeting [Player 1]\n" +
            "+++ Resolve Stack: Whenever you attack, Hired Claw deals 1 damage.\n");

        Assert.Empty(events);
    }

    [Fact]
    public void ExplicitBlockerDeclaration_UsesKnownExactInstance()
    {
        var parser = new ForgeTuiEventParser(Seats);
        parser.Append("+++ Land: AI-monored played Mountain (128)\n");
        parser.Append("+++ Add To Stack: AI-monored cast Hired Claw\n+++ Resolve Stack: Hired Claw (92) - Creature 1 / 2\n");

        var events = parser.Append(">> Hired Claw blocks Llanowar Elves\n");

        var blocker = Assert.Single(events);
        Assert.Equal("block_declared", blocker.Kind);
        Assert.Equal("forge-player-2", blocker.SeatId);
        Assert.Equal(92, blocker.ForgeObjectId);
        Assert.Equal("Hired Claw", blocker.CardName);
    }

    [Fact]
    public void AmbiguousBlockerName_IsNotMappedByName()
    {
        var parser = new ForgeTuiEventParser(Seats);
        parser.Append("+++ Add To Stack: AI-monored cast Bear Cub\n+++ Resolve Stack: Bear Cub (1) - Creature 2 / 2\n");
        parser.Append("+++ Add To Stack: AI-monored cast Bear Cub\n+++ Resolve Stack: Bear Cub (2) - Creature 2 / 2\n");

        Assert.Empty(parser.Append(">> Bear Cub blocks Llanowar Elves\n"));
    }

    [Fact]
    public void ForgeAiBlockerDeclaration_UsesPublicExactForgeIdentity()
    {
        var parser = new ForgeTuiEventParser(Seats);

        var blocker = Assert.Single(parser.Append("+++ Block: AI-monored Hired Claw (92)\n"));

        Assert.Equal("block_declared", blocker.Kind);
        Assert.Equal("forge-player-2", blocker.SeatId);
        Assert.Equal("Hired Claw", blocker.CardName);
        Assert.Equal(92, blocker.ForgeObjectId);
        Assert.Equal("battlefield", blocker.SourceZone);
    }

    [Fact]
    public void CombatLineWithAnUnmappedDisplayName_IsNotDeliveredWithoutASafeSeat()
    {
        var parser = new ForgeTuiEventParser(Seats);

        var events = parser.Append("+++ Combat: Forge temporary display name assigned Baleful Strix (74) to attack Player 1.\n");

        Assert.Empty(events);
    }
}
