using MoonSharp.Interpreter;

namespace MtgTtsBridge.Tests;

public sealed class HareApparentPresentationLuaTests
{
    private static readonly string Script = File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.lua"));

    private static Script NewLua()
    {
        var lua = new Script(CoreModules.Preset_Complete);
        lua.DoString(@"
            function log() end
            function broadcastToAll() end
            function printToAll() end
            function getObjectFromGUID() return nil end
            function getAllObjects() return {} end
            function Wait() end
            Time = { waitForSeconds = function(_, callback) if callback then callback() end end }
            WebRequest = {}
            JSON = { encode = function() return '{}' end, decode = function() return {} end }
        ");
        lua.DoString(Script);
        // The reduced MoonSharp host has no native TTS JSON userdata after the
        // bundle is loaded. Reinstall only the small contract stub used by
        // parser tests; live TTS supplies its real JSON implementation.
        lua.DoString(@"
            JSON = JSON or {}
            JSON.encode = function() return '{}' end
            JSON.decode = function() return {} end
        ");
        return lua;
    }

    [Fact]
    public void TokenVisualKeySeparatesTokenVisualNamingFromOrdinaryCardNaming()
    {
        var lua = NewLua();
        lua.DoString(@"
            ordinaryExpected = BridgeNormalizeCardName('Rabbit Token')
            ordinaryImported = BridgeNormalizeCardName('Rabbit\nToken Creature — Rabbit 0CMC')
            expectedKey = BridgeTokenNameKey('Rabbit Token')
            importedKey = BridgeTokenNameKey('Rabbit\nToken Creature — Rabbit 0CMC')
            assert(ordinaryExpected == 'rabbit token', ordinaryExpected)
            assert(ordinaryImported == 'rabbit', ordinaryImported)
            assert(ordinaryExpected ~= ordinaryImported, 'legacy ordinary comparison must reject this visual')
            assert(expectedKey == 'rabbit', expectedKey)
            assert(importedKey == 'rabbit', importedKey)
            assert(BridgeTokenVisualNameMatches('Rabbit\nToken Creature — Rabbit 0CMC', 'Rabbit Token'))
        ");

        Assert.Equal("rabbit token", lua.Globals.Get("ordinaryExpected").String);
        Assert.Equal("rabbit", lua.Globals.Get("ordinaryImported").String);
        Assert.Equal("rabbit", lua.Globals.Get("expectedKey").String);
        Assert.Equal("rabbit", lua.Globals.Get("importedKey").String);
    }

    [Fact]
    public void ExactRabbitImporterAcceptsKnownGoodMultilineVisualAndRejectsWrongOrBareCards()
    {
        var lua = NewLua();
        lua.DoString(@"
            BridgeRecordTokenMaterializationDiagnostic = function(_) end
            importCandidate = {
                Name = 'Card', CardID = 366100,
                Nickname = 'Rabbit\nToken Creature — Rabbit 0CMC',
                CustomDeck = { ['3661'] = { FaceURL = 'https://example.invalid/rabbit.png' } }
            }
            local accepted, acceptedError = BridgeValidateExactTokenImportCandidate(importCandidate, 'Rabbit Token')
            assert(accepted ~= nil, acceptedError or 'known-good Rabbit visual was rejected')

            importCandidate.Nickname = 'Goblin\nToken Creature — Goblin'
            local wrong, wrongError = BridgeValidateExactTokenImportCandidate(importCandidate, 'Rabbit Token')
            assert(wrong == nil and wrongError ~= nil, 'wrong token visual was accepted')

            importCandidate.Nickname = 'Rabbit\nToken Creature — Rabbit 0CMC'
            importCandidate.CustomDeck = nil
            local bare, bareError = BridgeValidateExactTokenImportCandidate(importCandidate, 'Rabbit Token')
            assert(bare == nil and bareError ~= nil, 'bare token card was accepted')
        ");
    }

    [Fact]
    public void TokenBindingPublishesEachExactForgeIdentityWithoutNameCoalescing()
    {
        var lua = NewLua();
        lua.DoString(@"
            BridgeState.eventSessionId = 'session-rabbit'
            BridgeState.tokenMaterializationByInstanceId = {}
            BridgeState.physicalByInstanceId = {}
            BridgeState.physicalInstanceIdByGuid = {}
            BridgeState.physicalSeatByGuid = {}
            BridgeState.physicalZoneByGuid = {}
            BridgeMoveToBattlefield = function() return true end
            BridgeRecordLooseCardIdentity = function(instanceId, guid, seatId, zone)
                BridgeState.physicalByInstanceId[instanceId] = guid
                BridgeState.physicalInstanceIdByGuid[guid] = instanceId
                BridgeState.physicalSeatByGuid[guid] = seatId
                BridgeState.physicalZoneByGuid[guid] = zone
                return true
            end
            local function card(guid) return {
                tag = 'Card', getGUID = function() return guid end
            } end
            local e1 = { cardInstanceId = 'forge:session-rabbit:84', seatId = 'forge-player-1', sequence = 1 }
            local e2 = { cardInstanceId = 'forge:session-rabbit:85', seatId = 'forge-player-1', sequence = 2 }
            assert(BridgeBeginTokenMaterialization(e1.cardInstanceId))
            assert(BridgeBeginTokenMaterialization(e2.cardInstanceId))
            assert(BridgeBindTokenMaterialization(e1, card('rabbit-guid-a'), nil, 'session-rabbit', BRIDGE_RUNTIME_EPOCH))
            assert(BridgeBindTokenMaterialization(e2, card('rabbit-guid-b'), nil, 'session-rabbit', BRIDGE_RUNTIME_EPOCH))
            assert(BridgeState.physicalByInstanceId[e1.cardInstanceId] == 'rabbit-guid-a')
            assert(BridgeState.physicalByInstanceId[e2.cardInstanceId] == 'rabbit-guid-b')
            assert(BridgeState.physicalInstanceIdByGuid['rabbit-guid-a'] == e1.cardInstanceId)
            assert(BridgeState.physicalInstanceIdByGuid['rabbit-guid-b'] == e2.cardInstanceId)
        ");
    }

    [Fact]
    public void AuthoritativeStackProjectionRetiresResolvedTriggerAndRejectsOlderCallback()
    {
        var lua = NewLua();
        lua.DoString(@"
            BridgeState.eventSessionId = 'session-hare'
            BridgeState.eventSessionGeneration = 7
            BridgeState.stackPresentationEventCursor = 0
            BridgeState.stackSummary = {}
            BridgeState.stackObjects = {}
            dirty = 0
            attributes = {}
            BridgeUiMarkDirty = function() dirty = dirty + 1 end
            BridgeUiSet = function(id, attribute, value) attributes[id .. '.' .. attribute] = tostring(value) end
            BridgeRevealCardArt = function(_) return nil end
            BridgeState.stackObjects = { [1] = { stackObjectId = 'trigger-b', sourceName = 'Hare Apparent' } }
            BridgeState.stackSummary = { [1] = 'Hare Apparent — triggered ability: Create Rabbit tokens' }
            BridgeRenderStackHud()
            assert(BridgeApplyAuthoritativeStackProjection({
                sessionId = 'session-hare', eventCursor = 11, stackObjects = {}, stack = {}
            }, 'hare-resolved', 'session-hare', 7))
            BridgeRenderStackHud()
            assert(next(BridgeState.stackObjects) == nil and #BridgeState.stackSummary == 0, 'resolved stack counts')
            assert(attributes['BridgeHudStack.text'] == '', 'resolved HUD=' .. tostring(attributes['BridgeHudStack.text']))
            assert(attributes['BridgeHudStackDetails.text'] == '', 'resolved details=' .. tostring(attributes['BridgeHudStackDetails.text']))
            assert(attributes['BridgeHudStackFallback.text'] == '', 'resolved fallback=' .. tostring(attributes['BridgeHudStackFallback.text']))
            local stale = BridgeApplyAuthoritativeStackProjection({
                sessionId = 'session-hare', eventCursor = 10, stackObjects = { one = { stackObjectId = 'trigger-b' } }, stack = {}
            }, 'delayed-old-callback', 'session-hare', 7)
            assert(stale == false)
            assert(#BridgeState.stackObjects == 0 and #BridgeState.stackSummary == 0)
            assert(dirty == 1)
        ");
    }

    [Fact]
    public void SpellLifecycleRefreshUsesStackOnlyAuthoritativeEndpoint()
    {
        var lua = NewLua();
        lua.DoString(@"
            BridgeState.eventSessionId = 'session-hare-refresh'
            BridgeState.eventSessionGeneration = 4
            BridgeState.stackPresentationEventCursor = 3
            BridgeState.stackSummary = { [1] = 'retired trigger' }
            BridgeState.stackObjects = { [1] = { stackObjectId = 'trigger' } }
            requestedPath = nil
            BridgeUiMarkDirty = function() end
            BridgeHttp = { requestJson = function(method, path, payload, callback)
                requestedPath = path
                callback(true, {
                    sessionId = 'session-hare-refresh', eventCursor = 4,
                    forgeSequence = 8, stack = {}, stackObjects = {}
                }, nil)
            end }
            WebRequest = {}
            BridgeRefreshAuthoritativeStackProjection(4, 'spell_resolved')
            assert(requestedPath == '/api/v1/embodiment/stack')
            assert(BridgeState.stackPresentationEventCursor == 4)
            assert(next(BridgeState.stackObjects) == nil)
            assert(#BridgeState.stackSummary == 0)
        ");
    }
}
