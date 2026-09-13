using MoonSharp.Interpreter;

namespace MtgTtsBridge.Tests;

public sealed class TtsOpponentSpellPresentationLuaTests
{
    private static readonly string Script = File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.lua"));

    [Fact]
    public void SharedTimingUsesExplicitInheritanceAndDoesNotChangeRevealTimer()
    {
        var lua = NewProbe();
        Assert.Equal(DataType.Function, lua.Globals.Get("BridgeHudOpponentSpellHoldCycle").Type);
        Assert.Equal(DataType.Function, lua.Globals.Get("BridgeUiMarkDirty").Type);
        Run(lua, @"
            BridgeState.presentationTiming.defaultReadableHoldSeconds = 2.5
            BridgeState.presentationTiming.overrides.opponent_spell = nil
            inherited = BridgePresentationHoldSeconds('opponent_spell')
            BridgeHudPresentationHoldCycle()
            changedGlobal = BridgePresentationHoldSeconds('opponent_spell')
            BridgeState.presentationTiming.overrides.opponent_spell = 1
            explicit = BridgePresentationHoldSeconds('opponent_spell')
            explicitOverride = BridgeState.presentationTiming.overrides.opponent_spell
            BridgeState.presentationTiming.overrides.opponent_spell = nil
            reset = BridgePresentationHoldSeconds('opponent_spell')
            randomSettleSeconds = BRIDGE_RANDOM_RESULT_PRESENTATION_SETTINGS.settleSeconds
        ");

        Assert.Equal(2.5, lua.Globals.Get("inherited").Number);
        Assert.Equal(3, lua.Globals.Get("changedGlobal").Number);
        Assert.True(Math.Abs(lua.Globals.Get("explicit").Number - 1) < 0.001,
            "override=" + lua.Globals.Get("explicitOverride"));
        Assert.Equal(3, lua.Globals.Get("reset").Number);
        Assert.Equal(0.25, lua.Globals.Get("randomSettleSeconds").Number);
    }

    [Fact]
    public void OpponentSpellUsesExactRealCardAndProxyAfterImmediateDeparture()
    {
        var lua = NewProbe();
        Assert.Equal(DataType.Function, lua.Globals.Get("BridgeOpponentSpellObserveCast").Type);
        Assert.Equal(DataType.Function, lua.Globals.Get("BridgeOpponentSpellObserveStackEntry").Type);
        Run(lua, @"
            local real = NewCard('real-card')
            objects = {real}
            BridgeGetLiveObjectByGuid = function(guid)
                for _, object in ipairs(objects) do if object.getGUID() == guid then return object end end
                return nil
            end
            local instance = 'forge:session:spell-1'
            BridgeState.physicalByInstanceId[instance] = 'real-card'
            BridgeState.physicalInstanceIdByGuid['real-card'] = instance
            BridgeState.physicalSeatByGuid['real-card'] = 'forge-player-2'
            BridgeState.physicalZoneByGuid['real-card'] = 'stack'
            BridgeState.authoritativeObjectByInstanceId[instance] = {zone='stack', seatId='forge-player-2'}
            BridgeOpponentSpellObserveCast({seatId='forge-player-2', sequence=10})
            BridgeOpponentSpellObserveStackEntry({seatId='forge-player-2', sequence=11,
                cardInstanceId=instance, sourceZone='hand', destinationZone='stack'}, real)
            activeBeforeDeparture = BridgeOpponentSpellPresentationDiagnostics().activeCount
            now = 0.5
            presentation = BridgeOpponentSpellPrepareDeparture({seatId='forge-player-2', sequence=12,
                cardInstanceId=instance, sourceZone='stack', destinationZone='graveyard'}, real)
            BridgeOpponentSpellCommitDeparture(presentation, nil, true)
            stageAfterCommit = presentation.stage
            proxy = presentation.proxyObject
            proxyInstance = proxy.getVar('bridgeCardInstanceId')
            proxySession = proxy.getVar('bridgeSessionId')
            proxyMarker = proxy.getVar('bridgePresentationProxy')
            proxyRegistered = BridgeIsPresentationProxyObject(proxy)
            proxyScannerRejected = not BridgeRecordLooseCardIdentity(instance, proxy.getGUID(),
                'forge-player-2', 'stack', false)
            resolved, resolveError = BridgeResolveExactActionPhysical(
                {decisionId='d', seatId='forge-player-2'},
                {actionId='a', type='cast_spell', cardInstanceId=instance, sourceZone='stack'})
            BridgeState.physicalByInstanceId[instance] = proxy.getGUID()
            BridgeState.physicalInstanceIdByGuid[proxy.getGUID()] = instance
            BridgeState.physicalSeatByGuid[proxy.getGUID()] = 'forge-player-2'
            BridgeState.physicalZoneByGuid[proxy.getGUID()] = 'stack'
            proxyResolved = BridgeResolveExactActionPhysical(
                {decisionId='d', seatId='forge-player-2'},
                {actionId='proxy-action', type='cast_spell', cardInstanceId=instance, sourceZone='stack'})
            cursorBefore = BridgeState.lastAppliedEventSequence
            BridgeState.lastAppliedEventSequence = 12
            cursorAfter = BridgeState.lastAppliedEventSequence
            scheduledDelay = pendingDelay
            now = 2.5
            scheduledCallback()
            activeAfterHold = BridgeOpponentSpellPresentationDiagnostics().activeCount
        ");

        Assert.Equal(1, lua.Globals.Get("activeBeforeDeparture").Number);
        Assert.Equal("PROXY_VISIBLE", lua.Globals.Get("stageAfterCommit").String);
        Assert.Equal(DataType.Nil, lua.Globals.Get("proxyInstance").Type);
        Assert.Equal(DataType.Nil, lua.Globals.Get("proxySession").Type);
        Assert.Equal("opponent-spell", lua.Globals.Get("proxyMarker").String);
        Assert.True(lua.Globals.Get("proxyRegistered").Boolean);
        Assert.True(lua.Globals.Get("proxyScannerRejected").Boolean);
        Assert.Equal("real-card", lua.Globals.Get("resolved").Table.Get("guid").String);
        Assert.Equal(DataType.Nil, lua.Globals.Get("proxyResolved").Type);
        Assert.Equal(12, lua.Globals.Get("cursorAfter").Number);
        Assert.Equal(2, lua.Globals.Get("scheduledDelay").Number);
        Assert.Equal(0, lua.Globals.Get("activeAfterHold").Number);
    }

    [Fact]
    public void SemanticOpponentCastCreatesOnlyAHintAndDoesNotFenceEventDrain()
    {
        var lua = NewProbe();
        Run(lua, @"
            BRIDGE_SEATS['forge-player-2'].animateAuthoritativeEvents = true
            local event = {kind='spell_cast', sequence=40, seatId='forge-player-2',
                cardName='Rapid Spell'}
            directObserved = BridgeOpponentSpellObserveCast(event)
            applied, delay = BridgeApplyAuthoritativeEvent(event)
            hintCount = #BridgeState.opponentSpellCastHintsBySeatId['forge-player-2']
            physicalBarrier = event._bridgePhysicalCompletionPending == true
            BridgeState.lastAppliedEventSequence = 40
            cursorAdvanced = BridgeState.lastAppliedEventSequence == 40
        ");

        Assert.True(lua.Globals.Get("applied").Boolean);
        Assert.Equal(0, lua.Globals.Get("delay").Number);
        Assert.True(lua.Globals.Get("directObserved").Boolean);
        Assert.Equal(2, lua.Globals.Get("hintCount").Number);
        Assert.False(lua.Globals.Get("physicalBarrier").Boolean);
        Assert.True(lua.Globals.Get("cursorAdvanced").Boolean);
    }

    [Fact]
    public void OwnSpellsPermanentDestinationsAndRapidSpellsRemainDistinctAndBounded()
    {
        var lua = NewProbe();
        Run(lua, @"
            function StartSpell(instance, seat, guid, destination)
                local card = NewCard(guid)
                BridgeOpponentSpellObserveCast({seatId=seat, sequence=instance})
                BridgeOpponentSpellObserveStackEntry({seatId=seat, sequence=instance,
                    cardInstanceId=instance, sourceZone='hand', destinationZone='stack'}, card)
                local presentation = BridgeOpponentSpellPrepareDeparture({seatId=seat, sequence=instance,
                    cardInstanceId=instance, sourceZone='stack', destinationZone=destination}, card)
                if presentation ~= nil and destination ~= 'battlefield' then
                    BridgeOpponentSpellCommitDeparture(presentation, nil, true)
                end
                return presentation
            end
            own = StartSpell('forge:session:own', 'forge-player-1', 'own', 'graveyard')
            permanent = StartSpell('forge:session:permanent', 'forge-player-2', 'permanent', 'battlefield')
            first = StartSpell('forge:session:first', 'forge-player-2', 'first', 'graveyard')
            second = StartSpell('forge:session:second', 'forge-player-2', 'second', 'graveyard')
            distinct = first.presentationId ~= second.presentationId
            twoActive = BridgeOpponentSpellPresentationDiagnostics().activeCount
            for index = 1, 8 do StartSpell('forge:session:rapid-' .. tostring(index), 'forge-player-2', 'rapid-' .. tostring(index), 'graveyard') end
            bounded = BridgeOpponentSpellPresentationDiagnostics().activeCount <= 6
            ownAbsent = own == nil
            permanentAbsent = permanent.finished == true and permanent.proxyObject == nil
        ");

        Assert.True(lua.Globals.Get("ownAbsent").Boolean);
        Assert.True(lua.Globals.Get("permanentAbsent").Boolean);
        Assert.True(lua.Globals.Get("distinct").Boolean);
        Assert.Equal(2, lua.Globals.Get("twoActive").Number);
        Assert.True(lua.Globals.Get("bounded").Boolean);
    }

    [Fact]
    public void SessionFenceMakesOldExpiryInertForNewPresentation()
    {
        var lua = NewProbe();
        Run(lua, @"
            old = NewCard('old')
            BridgeOpponentSpellObserveStackEntry({seatId='forge-player-2', sequence=1,
                cardInstanceId='forge:session:old', sourceZone='hand', destinationZone='stack'}, old)
            oldPresentation = BridgeOpponentSpellPrepareDeparture({seatId='forge-player-2', sequence=1,
                cardInstanceId='forge:session:old', sourceZone='stack', destinationZone='graveyard'}, old)
            BridgeOpponentSpellCommitDeparture(oldPresentation, nil, true)
            oldCallback = pendingCallback
            BridgeRetireOpponentSpellPresentations('new-match')
            BridgeState.eventSessionId = 'new-session'
            seatPresentation = BRIDGE_SEATS['forge-player-2'].animateAuthoritativeEvents
            fresh = NewCard('fresh')
            freshPresentation = nil
            BridgeOpponentSpellObserveCast({seatId='forge-player-2', sequence=2,
                cardInstanceId='forge:new-session:fresh'})
            castCount = #BridgeState.opponentSpellPresentationOrder
            BridgeOpponentSpellObserveStackEntry({seatId='forge-player-2', sequence=2,
                cardInstanceId='forge:new-session:fresh', sourceZone='hand', destinationZone='stack'}, fresh)
            freshPresentation = BridgeState.opponentSpellPresentationsById['new-session:forge:new-session:fresh:2']
            freshExists = freshPresentation ~= nil
            oldCallback()
            oldExpiryDidNotRemoveFresh = freshExists
                and BridgeState.opponentSpellPresentationsById[freshPresentation.presentationId] ~= nil
        ");

        Assert.True(lua.Globals.Get("freshExists").Boolean,
            "castCount=" + lua.Globals.Get("castCount") + " seat=" + lua.Globals.Get("seatPresentation"));
        Assert.True(lua.Globals.Get("oldExpiryDidNotRemoveFresh").Boolean);
    }

    private static Script NewProbe()
    {
        var lua = new Script();
        lua.DoString(@"
            function log(message) end
            function broadcastToAll(message, color) end
            function printToAll(message, color) end
            function getObjectFromGUID(guid) return nil end
            function getAllObjects() return objects or {} end
            Wait = {time = function(callback, delay) end, frames = function(callback, frames) end}
            Time = {time = 0}
            JSON = {encode = function(value) return '{}' end, decode = function(value) return {} end}
            os = {time = function() return 1 end, clock = function() return 0 end}
            table.concat = function(values, separator)
                local result = ''
                for index, value in ipairs(values) do
                    if index > 1 then result = result .. (separator or '') end
                    result = result .. tostring(value)
                end
                return result
            end
        ");
        lua.DoString(Script);
        lua.DoString(@"
            now = 0
            BRIDGE_RUNTIME_EPOCH_LOCAL = 1
            BRIDGE_RUNTIME_EPOCH = 1
            BridgeRuntimeIsCurrent = function(epoch) return epoch == BRIDGE_RUNTIME_EPOCH end
            BridgeResyncClockNow = function() return now end
            BridgeLog = function(message) lastLog = message end
            BridgeWaitTime = function(callback, delay) pendingCallback = callback; pendingDelay = delay; scheduledCallback = callback end
            BridgeUiMarkDirty = function(reason) dirtyReason = reason end
            BridgeShowError = function(message) lastError = message end
            function NewCard(guid)
                local card = {guid=guid, tag='Card', vars={}, live=true}
                function card.getGUID() return card.guid end
                function card.getName() return 'Rapid Spell' end
                function card.getDescription() return '' end
                function card.getVar(key) return card.vars[key] end
                function card.setVar(key, value) card.vars[key] = value end
                function card.clone(options)
                    local clone = NewCard(card.guid .. '-proxy')
                    objects = objects or {}
                    table.insert(objects, clone)
                    return clone
                end
                function card.clearButtons() end
                function card.setLock(value) card.locked = value end
                function card.setPosition(value) card.position = value end
                function card.setRotation(value) card.rotation = value end
                function card.destruct() card.live = false end
                return card
            end
            objects = {}
            BridgeState.eventSessionId = 'session'
            BridgeState.eventSessionGeneration = 1
            BridgeState.presentationTiming.defaultReadableHoldSeconds = 2.5
            BridgeState.presentationTiming.overrides.opponent_spell = nil
            BridgeState.opponentSpellPresentationGeneration = 0
            BridgeState.opponentSpellPresentationsById = {}
            BridgeState.opponentSpellPresentationOrder = {}
            BridgeState.opponentSpellPresentationDiagnostics = {}
            BridgeState.opponentSpellCastHintsBySeatId = {}
            BridgeState.presentationProxyGuids = {}
            BridgeState.physicalByInstanceId = {}
            BridgeState.physicalInstanceIdByGuid = {}
            BridgeState.physicalSeatByGuid = {}
            BridgeState.physicalZoneByGuid = {}
            BridgeState.authoritativeObjectByInstanceId = {}
        ");
        return lua;
    }

    private static void Run(Script lua, string code)
    {
        lua.DoString("ok, luaError = pcall(function()\n" + code + "\nend)");
        Assert.True(lua.Globals.Get("ok").Boolean, lua.Globals.Get("luaError").CastToString());
    }
}
