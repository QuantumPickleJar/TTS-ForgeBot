using MoonSharp.Interpreter;

namespace MtgTtsBridge.Tests;

public sealed class TtsPhasePresentationLuaTests
{
    private static readonly string Source = File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.lua"));

    [Theory]
    [InlineData("Main phase, precombat", "BridgePhaseMain1")]
    [InlineData("Main phase, postcombat", "BridgePhaseMain2")]
    [InlineData("Main 1", "BridgePhaseMain1")]
    [InlineData("Main 2", "BridgePhaseMain2")]
    [InlineData("Beginning of Combat Step", "BridgePhaseCombat")]
    [InlineData("Declare Attackers Step", "BridgePhaseCombat")]
    [InlineData("Declare Blockers Step", "BridgePhaseCombat")]
    [InlineData("Combat Damage Step", "BridgePhaseCombat")]
    [InlineData("End of Combat Step", "BridgePhaseCombat")]
    public void ForgePhaseNamesMapToUnambiguousRibbonElements(string phase, string expected)
    {
        var lua = NewProbe();
        var actual = lua.Globals.Get("BridgeHudPhaseElementId").Function.Call(phase);

        Assert.Equal(expected, actual.String);
        if (phase.Contains("precombat", StringComparison.OrdinalIgnoreCase))
            Assert.NotEqual("BridgePhaseCombat", actual.String);
        if (phase.Contains("postcombat", StringComparison.OrdinalIgnoreCase))
            Assert.NotEqual("BridgePhaseCombat", actual.String);
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
