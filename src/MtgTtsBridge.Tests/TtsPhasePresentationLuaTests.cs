using MoonSharp.Interpreter;

namespace MtgTtsBridge.Tests;

public sealed class TtsPhasePresentationLuaTests
{
    private static readonly string Source = File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.lua"));

    [Theory]
    [InlineData("Main phase, precombat", "BridgeHudPhaseMain1")]
    [InlineData("Main phase, postcombat", "BridgeHudPhaseMain2")]
    [InlineData("Main 1", "BridgeHudPhaseMain1")]
    [InlineData("Main 2", "BridgeHudPhaseMain2")]
    [InlineData("Beginning of Combat Step", "BridgeHudPhaseBeginningCombat")]
    [InlineData("Declare Attackers Step", "BridgeHudPhaseAttackers")]
    [InlineData("Declare Blockers Step", "BridgeHudPhaseBlockers")]
    [InlineData("Combat Damage Step", "BridgeHudPhaseDamage")]
    [InlineData("End of Combat Step", "BridgeHudPhaseEndCombat")]
    public void ForgePhaseNamesMapToUnambiguousRibbonElements(string phase, string expected)
    {
        var lua = NewProbe();
        var actual = lua.Globals.Get("BridgeHudPhaseElementId").Function.Call(phase);

        Assert.Equal(expected, actual.String);
        if (phase.Contains("precombat", StringComparison.OrdinalIgnoreCase))
            Assert.NotEqual("BridgeHudPhaseBeginningCombat", actual.String);
        if (phase.Contains("postcombat", StringComparison.OrdinalIgnoreCase))
            Assert.NotEqual("BridgeHudPhaseEndCombat", actual.String);
    }

    [Fact]
    public void SingleRibbonButtonsEditOnlyTheSelectedSharedStopScope()
    {
        var lua = NewProbe();
        lua.DoString(@"
            BridgeState.ui.fastForwardStops = {own_turn = {}, other_turn = {}}
            BridgeState.ui.fastForwardStopScope = 'own_turn'
            BridgeHudYieldPhaseStop(nil, nil, 'BridgeHudPhaseMain1')
            ownEnabled = BridgeState.ui.fastForwardStops.own_turn.main_precombat == true
            otherEnabledBefore = BridgeState.ui.fastForwardStops.other_turn.main_precombat == true
            BridgeHudYieldStopScope()
            BridgeHudYieldPhaseStop(nil, nil, 'BridgeHudPhaseMain1')
            otherEnabled = BridgeState.ui.fastForwardStops.other_turn.main_precombat == true
            scopeAfter = BridgeState.ui.fastForwardStopScope
            phaseAfter = BridgeState.currentPhase
        ");

        Assert.True(lua.Globals.Get("ownEnabled").Boolean);
        Assert.False(lua.Globals.Get("otherEnabledBefore").Boolean);
        Assert.True(lua.Globals.Get("otherEnabled").Boolean);
        Assert.Equal("other_turn", lua.Globals.Get("scopeAfter").String);
        Assert.True(lua.Globals.Get("phaseAfter").IsNil());
    }

    [Fact]
    public void UntapIsAnIndicatorAndCannotCreateAStop()
    {
        var lua = NewProbe();
        lua.DoString(@"
            BridgeState.ui.fastForwardStops = {own_turn = {}, other_turn = {}}
            result = BridgeHudPhaseUntap()
        ");

        Assert.False(lua.Globals.Get("result").Boolean);
        Assert.True(lua.Globals.Get("BridgeState").Table.Get("ui").Table.Get("fastForwardStops").Table.Get("own_turn").Table.Get("upkeep").IsNil());
    }

    private static Script NewProbe()
    {
        var lua = new Script();
        lua.DoString(@"
            function log(message) end
            function broadcastToAll(message, color) end
            function printToAll(message, color) end
            function getAllObjects() return {} end
            function getObjectFromGUID(guid) return nil end
            function getObjectsWithTag(tag) return {} end
            Wait = {time = function(callback, delay) end, frames = function(callback, frames) end}
            Time = {time = 0}
            JSON = {encode = function(value) return '{}'; end, decode = function(value) return {}; end}
            os = {time = function() return 1 end, clock = function() return 0 end}
            math.random = function(minimum, maximum) return 123456 end
            table.concat = function(values, separator) return 'probe-runtime' end
        ");
        lua.DoString(Source);
        return lua;
    }
}
