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
            BridgeState.eventSessionId = 'session'
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

    [Fact]
    public void PartialOpeningHandZoneMetadataIsRepairedOnlyFromExactHandMembership()
    {
        var lua = new Script();
        lua.DoString(@"
            function log(message) end
            function broadcastToAll(message, color) end
            function printToAll(message, color) end
            local objects = {}
            local function object(guid, instanceId)
                local value = {tag='Card', bridgeId=instanceId, bridgeSession='session'}
                value.getGUID = function() return guid end
                value.getVar = function(key)
                    if key == 'bridgeCardInstanceId' then return value.bridgeId end
                    if key == 'bridgeSessionId' then return value.bridgeSession end
                    return nil
                end
                value.setVar = function(key, id)
                    if key == 'bridgeCardInstanceId' then value.bridgeId = id end
                    if key == 'bridgeSessionId' then value.bridgeSession = id end
                end
                return value
            end
            for i = 1, 7 do objects['human-' .. i] = object('human-' .. i, 'human:' .. i) end
            for i = 1, 7 do objects['ai-' .. i] = object('ai-' .. i, 'ai:' .. i) end
            function getObjectFromGUID(guid) return objects[guid] end
            JSON = {encode = function(value) return '{}' end, decode = function(value) return {} end}
            os = {time = function() return 1 end, clock = function() return 0 end}
            math.random = function(minimum, maximum) return 123456 end
            math.randomseed(1)
            table.concat = function(values, separator)
                local result = ''
                for index, value in ipairs(values) do
                    if index > 1 then result = result .. separator end
                    result = result .. tostring(value)
                end
                return result
            end
        ");
        lua.DoString(Script);
        lua.DoString(@"
            BridgeState.eventSessionId = 'session'
            BridgeState.physicalByInstanceId = {['human:1']='human-1', ['human:2']='human-2'}
            BridgeState.physicalInstanceIdByGuid = {['human-1']='human:1', ['human-2']='human:2'}
            BridgeState.physicalSeatByGuid = {['human-1']='forge-player-1', ['human-2']='forge-player-1'}
            BridgeState.physicalZoneByGuid = {['human-1']='hand', ['human-2']='hand'}
            function BridgeTryGetSeatHandObjects(seatId)
                local result = {}
                local prefix = seatId == 'forge-player-1' and 'human-' or 'ai-'
                for i = 1, 7 do table.insert(result, getObjectFromGUID(prefix .. i)) end
                return result, nil
            end
            local snapshot = {sessionId='session', seats={
                {seatId='forge-player-1', zones={{name='hand', cards={
                    {cardInstanceId='human:1'}, {cardInstanceId='human:2'}, {cardInstanceId='human:3'},
                    {cardInstanceId='human:4'}, {cardInstanceId='human:5'}, {cardInstanceId='human:6'}, {cardInstanceId='human:7'}}}}},
                {seatId='forge-player-2', zones={{name='hand', cards={
                    {cardInstanceId='ai:1'}, {cardInstanceId='ai:2'}, {cardInstanceId='ai:3'},
                    {cardInstanceId='ai:4'}, {cardInstanceId='ai:5'}, {cardInstanceId='ai:6'}, {cardInstanceId='ai:7'}}}}}
            }}
            ownershipOk, ownershipError, expectedCount, physicalCount, repairedCount = BridgeReconcileSnapshotHandOwnership(snapshot)
            ready, readyCount, expectedHuman = (function()
                BridgeRecordExpectedHandIdentities(snapshot, 'forge-player-1')
                return BridgeCheckOpeningHandReadiness('forge-player-1')
            end)()
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        Assert.True(lua.Globals.Get("ownershipOk").Boolean, lua.Globals.Get("ownershipError").ToPrintString());
        Assert.Equal(14, lua.Globals.Get("expectedCount").Number);
        Assert.Equal(14, lua.Globals.Get("physicalCount").Number);
        Assert.Equal(0, lua.Globals.Get("repairedCount").Number);
        Assert.True(lua.Globals.Get("ready").Boolean);
        Assert.Equal(7, lua.Globals.Get("readyCount").Number);
        Assert.Equal(7, lua.Globals.Get("expectedHuman").Number);
        Assert.Equal("hand", state.Get("physicalZoneByGuid").Table.Get("ai-1").String);
        Assert.Equal("forge-player-2", state.Get("physicalSeatByGuid").Table.Get("ai-7").String);
    }

    [Fact]
    public void NewSessionFencesOldPhysicalMappingsAndCallbacks()
    {
        var lua = new Script();
        lua.DoString(@"
            function log(message) end
            function broadcastToAll(message, color) end
            function printToAll(message, color) end
            local objects = {}
            local function object(guid, instanceId)
                local value = {tag='Card', bridgeId=instanceId, bridgeSession='old'}
                value.getGUID = function() return guid end
                value.getVar = function(key)
                    if key == 'bridgeCardInstanceId' then return value.bridgeId end
                    if key == 'bridgeSessionId' then return value.bridgeSession end
                    return nil
                end
                value.setVar = function(key, id)
                    if key == 'bridgeCardInstanceId' then value.bridgeId = id end
                    if key == 'bridgeSessionId' then value.bridgeSession = id end
                end
                return value
            end
            objects['old-guid'] = object('old-guid', 'forge:old:1')
            objects['new-guid'] = object('new-guid', 'forge:new:1')
            objects['new-guid'].bridgeSession = 'new'
            function getObjectFromGUID(guid) return objects[guid] end
            function getAllObjects() return {} end
            JSON = {encode = function(value) return '{}' end, decode = function(value) return {} end}
            os = {time = function() return 1 end, clock = function() return 0 end}
            math.random = function(minimum, maximum) return 123456 end
            math.randomseed(1)
            table.concat = function(values, separator)
                local result = ''
                for index, value in ipairs(values or {}) do
                    if value ~= nil then
                        if result ~= '' then result = result .. (separator or '') end
                        result = result .. tostring(value)
                    end
                end
                return result
            end
        ");
        lua.DoString(Script);
        lua.DoString(@"
            BridgeState.eventSessionId = 'old'
            BridgeState.physicalOwnershipSessionId = 'old'
            BridgeState.physicalByInstanceId = {['forge:old:1']='old-guid'}
            BridgeState.physicalInstanceIdByGuid = {['old-guid']='forge:old:1'}
            BridgeState.physicalSeatByGuid = {['old-guid']='forge-player-1'}
            BridgeState.physicalZoneByGuid = {['old-guid']='hand'}
            BridgeState.physicalContainerByInstanceId = {}
            BridgeState.physicalContainedInstanceIdByGuid = {}
            oldBeforeReplace = BridgeState.physicalByInstanceId['forge:old:1']
            BridgePrepareEventSession('new', true, false)
            oldCallbackAccepted = BridgeRecordLooseCardIdentity('forge:old:1', 'old-guid', 'forge-player-1', 'hand')
            newCallbackAccepted = BridgeRecordLooseCardIdentity('forge:new:1', 'new-guid', 'forge-player-1', 'hand')
            oldAfterReplace = BridgeState.physicalByInstanceId['forge:old:1']
            newAfterReplace = BridgeState.physicalByInstanceId['forge:new:1']
        ");

        Assert.Equal("old-guid", lua.Globals.Get("oldBeforeReplace").String);
        Assert.False(lua.Globals.Get("oldCallbackAccepted").Boolean);
        Assert.True(lua.Globals.Get("newCallbackAccepted").Boolean);
        Assert.True(lua.Globals.Get("oldAfterReplace").IsNil());
        Assert.Equal("new-guid", lua.Globals.Get("newAfterReplace").String);
    }

}
