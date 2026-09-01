using MoonSharp.Interpreter;

namespace MtgTtsBridge.Tests;

public sealed class TtsIdentityHardeningLuaTests
{
    private static readonly string Script = File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.lua"));

    [Fact]
    public void LiveIdentityCannotBeReassignedToAnotherGuidOrCardInstance()
    {
        var lua = new Script();
        lua.DoString(@"
            function log(message) lastLog = message end
            function broadcastToAll(message, color) end
            function printToAll(message, color) end
            local objects = {}
            local function object(guid)
                local value = {tag='Card', bridgeId=nil}
                value.getGUID = function() return guid end
                value.getVar = function(key) return value.bridgeId end
                value.setVar = function(key, id) value.bridgeId = id end
                return value
            end
            objects['guid-a'] = object('guid-a')
            objects['guid-b'] = object('guid-b')
            function getObjectFromGUID(guid) return objects[guid] end
            JSON = {encode = function(value) return '{}' end, decode = function(value) return {} end}
            os = {time = function() return 1 end, clock = function() return 0 end}
            math.random = function(minimum, maximum) return 123456 end
            table.concat = function(values, separator) return 'probe-runtime' end
            math.randomseed(1)
        ");
        lua.DoString(Script);
        lua.DoString(@"
            BridgeState.physicalByInstanceId = {}
            BridgeState.physicalInstanceIdByGuid = {}
            BridgeState.physicalSeatByGuid = {}
            BridgeState.physicalZoneByGuid = {}
            BridgeState.canonicalCardNameByGuid = {}
            first = BridgeRecordLooseCardIdentity('forge:session:4', 'guid-a', 'forge-player-1', 'battlefield')
            stolenGuid = BridgeRecordLooseCardIdentity('forge:session:4', 'guid-b', 'forge-player-1', 'battlefield')
            stolenCard = BridgeRecordLooseCardIdentity('forge:session:126', 'guid-a', 'forge-player-1', 'battlefield')
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        Assert.True(lua.Globals.Get("first").Boolean);
        Assert.False(lua.Globals.Get("stolenGuid").Boolean);
        Assert.False(lua.Globals.Get("stolenCard").Boolean);
        Assert.Equal("guid-a", state.Get("physicalByInstanceId").Table.Get("forge:session:4").String);
        Assert.Equal("forge:session:4", state.Get("physicalInstanceIdByGuid").Table.Get("guid-a").String);
        Assert.Null(state.Get("physicalByInstanceId").Table.Get("forge:session:126").ToObject());
    }

}
