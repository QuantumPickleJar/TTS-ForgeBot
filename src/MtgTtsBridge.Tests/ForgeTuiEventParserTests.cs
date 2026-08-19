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
            ["turn_changed", "phase_changed", "land_played", "mana_ability_used", "spell_cast", "spell_resolved", "land_played", "spell_cast", "spell_resolved", "attack_declared", "attack_declared"],
            events.Select(item => item.Kind));
        Assert.Equal("forge-player-2", events[6].SeatId);
        Assert.Equal(128, events[6].ForgeObjectId);
        Assert.Equal("forge-player-2", events[8].SeatId);
        Assert.Equal("Emberheart Challenger", events[9].CardName);
        Assert.Equal(92, events[9].ForgeObjectId);
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
}
