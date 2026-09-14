using MoonSharp.Interpreter;

namespace MtgTtsBridge.Tests;

public sealed class TtsHumanActionReadinessLuaTests
{
    private static readonly string GlobalScript = File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.lua"));

    [Fact]
    public void OnePhysicalPermanentKeepsBothAbilitiesAndPickupIsNonCommittal()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            local card = {
                tag='Card', guid='ash-guid', buttons={}, highlights=0,
                position={x=0,y=0,z=0}, rotation={x=0,y=0,z=0}, use_hands=true
            }
            function card.getGUID() return card.guid end
            function card.getName() return 'Ashiok, Nightmare Weaver' end
            function card.getButtons() return card.buttons end
            function card.createButton(button)
                button.index = #card.buttons
                table.insert(card.buttons, button)
            end
            function card.removeButton(index) table.remove(card.buttons, index + 1) end
            function card.highlightOn() card.highlights = card.highlights + 1 end
            function card.highlightOff() end
            function card.getPosition() return card.position end
            function card.getRotation() return card.rotation end
            function card.setPositionSmooth(position) card.position = position end
            function card.setRotationSmooth(rotation) card.rotation = rotation end
            function card.getVar() return nil end
            objects = {card}
            function getObjectFromGUID(guid) if guid == 'ash-guid' then return card end end
            Player = {White={}}
            Global = {}
            BRIDGE_SEATS['forge-player-1'] = {ttsColor='White', tableSideZ=-1, animateAuthoritativeEvents=false}
            BridgeState.eventSessionId = 'ash-session'
            BridgeState.eventSessionGeneration = 4
            BridgeState.humanActionGeneration = 8
            BridgeState.physicalTransactionGeneration = 3
            BridgeState.lastAppliedEventSequence = 0
            BridgeState.lastStateProjectedEventSequence = 0
            BridgeState.snapshotReconcileLastAppliedCursor = 0
            BridgeState.setupStage = 'READY'
            BridgeState.resyncStage = 'Idle'
            BridgeState.desyncLatched = false
            BridgeState.resyncInFlight = false
            BridgeState.setupBusy = false
            BridgeState.bootstrapping = false
            BridgeState.snapshotReconcileInFlight = false
            BridgeState.humanActionReadiness = {
                certified=true, globalCertified=true, decisionAccepted=true,
                sessionId='ash-session', decisionId='forge-tui-16',
                sessionGeneration=4, physicalTransactionGeneration=3,
                authoritativeCursor=0
            }
            BridgeState.physicalByInstanceId = {['forge:e8aa:25']='ash-guid'}
            BridgeState.physicalInstanceIdByGuid = {['ash-guid']='forge:e8aa:25'}
            BridgeState.physicalSeatByGuid = {['ash-guid']='forge-player-1'}
            BridgeState.physicalZoneByGuid = {['ash-guid']='battlefield'}
            BridgeState.authoritativeObjectByInstanceId = {
                ['forge:e8aa:25']={isVirtual=false, zone='battlefield', seatId='forge-player-1'}
            }
            BridgeState.actionsByGuid = {}
            BridgeState.actionByGuid = {}
            BridgeState.gestureActionAmbiguousByGuid = {}
            BridgeState.highlightedGuids = {}
            BridgeState.contextualActionMenuByGuid = {}
            BridgeState.contextualActionButtonIndexesByGuid = {}
            local ashPlus = {actionId='forge-tui-16-choice-1', type='activate_ability',
                sourceCardInstanceId='forge:e8aa:25', sourceZone='battlefield',
                displayName='Ashiok, Nightmare Weaver: +2: Exile the top three cards of target opponent library.'}
            local ashMinusX = {actionId='forge-tui-16-choice-2', type='activate_ability',
                sourceCardInstanceId='forge:e8aa:25', sourceZone='battlefield',
                displayName='Ashiok, Nightmare Weaver: -X: Put a creature card onto the battlefield.'}
            BridgeState.lastDecision = {
                decisionId='forge-tui-16', sessionId='ash-session', kind='main_priority',
                seatId='forge-player-1', eventCursor=0, actions={
                    {actionId='forge-tui-16-choice-0', type='pass_priority', displayName='Pass priority'},
                    ashPlus,
                    ashMinusX
                }
            }
            submissions = {}
            submissionCount = 0
            function BridgeSubmitChoice(decisionId, actionId, source)
                submissionCount = submissionCount + 1
                submissions[submissionCount] = {decisionId=decisionId, actionId=actionId, source=source}
            end

            BridgeHighlightPhysicalObjectOnce(card, 'ash-guid', {0.53, 0.81, 0.98})
            BridgeRegisterPhysicalAction('ash-guid', ashPlus, BridgeState.lastDecision)
            BridgeRegisterPhysicalAction('ash-guid', ashMinusX, BridgeState.lastDecision)
            BridgeInstallContextualActionMenu(card, BridgeState.lastDecision, BridgeState.actionsByGuid['ash-guid'])
            highlightCount = card.highlights
            actionCount = BridgeOrderedCollectionCount(BridgeState.actionsByGuid['ash-guid'])
            mappedShortcut = BridgeState.actionByGuid['ash-guid']
            collapsedButtonCount = #card.buttons

            onObjectPickUp('White', card)
            onObjectDrop('White', card)
            pickupSubmitCount = submissionCount
            BridgeToggleContextualActionMenu(card, 'White', false)
            openButtonCount = #card.buttons
            menuHasPlus = false
            menuHasMinusX = false
            for _, button in ipairs(card.buttons) do
                if button.label == '+2' then menuHasPlus = true end
                if button.label == '-X' then menuHasMinusX = true end
            end
            menuAction1Id = BridgeState.contextualActionMenuByGuid['ash-guid'].actions[1]
                and BridgeState.contextualActionMenuByGuid['ash-guid'].actions[1].actionId or 'nil'
            BridgeChooseContextualAction(card, 'White', false, 'ash-guid', 1)
            plusActionId = submissions[1] and submissions[1].actionId or 'nil'
            plusSource = submissions[1] and submissions[1].source or 'nil'

            BridgeHighlightPhysicalObjectOnce(card, 'ash-guid', {0.53, 0.81, 0.98})
            BridgeRegisterPhysicalAction('ash-guid', ashPlus, BridgeState.lastDecision)
            BridgeRegisterPhysicalAction('ash-guid', ashMinusX, BridgeState.lastDecision)
            BridgeInstallContextualActionMenu(card, BridgeState.lastDecision, BridgeState.actionsByGuid['ash-guid'])
            BridgeToggleContextualActionMenu(card, 'White', false)
            BridgeChooseContextualAction(card, 'White', false, 'ash-guid', 2)
            minusActionId = submissions[2] and submissions[2].actionId or 'nil'
            minusSource = submissions[2] and submissions[2].source or 'nil'
        ");

        Assert.Equal(1, lua.Globals.Get("highlightCount").Number);
        Assert.Equal(2, lua.Globals.Get("actionCount").Number);
        Assert.True(lua.Globals.Get("mappedShortcut").IsNil());
        Assert.Equal(1, lua.Globals.Get("collapsedButtonCount").Number);
        Assert.Equal(0, lua.Globals.Get("pickupSubmitCount").Number);
        Assert.Equal(3, lua.Globals.Get("openButtonCount").Number);
        Assert.True(lua.Globals.Get("menuHasPlus").Boolean);
        Assert.True(lua.Globals.Get("menuHasMinusX").Boolean);
        Assert.Equal("forge-tui-16-choice-1", lua.Globals.Get("menuAction1Id").String);
        Assert.Equal(2, lua.Globals.Get("submissionCount").Number);
        Assert.Equal("forge-tui-16-choice-1", lua.Globals.Get("plusActionId").String);
        Assert.Equal("contextual_action_button", lua.Globals.Get("plusSource").String);
        Assert.Equal("forge-tui-16-choice-2", lua.Globals.Get("minusActionId").String);
        Assert.Equal("contextual_action_button", lua.Globals.Get("minusSource").String);
    }

    [Fact]
    public void NewMatchRetiresOldPassBeforeCleanupAndNeverPostsIt()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeState.eventSessionId = 'old-session'
            BridgeState.eventSessionGeneration = 2
            BridgeState.humanActionGeneration = 5
            BridgeState.lastDecision = {decisionId='forge-tui-17', sessionId='old-session', kind='main_priority',
                actions={{actionId='old-pass', type='pass_priority'}}}
            BridgeState.actionsByGuid = {['old-guid']={{actionId='old-ability'}}}
            BridgeState.actionByGuid = {['old-guid']={actionId='old-ability'}}
            BridgeState.humanActionReadiness = {certified=true, globalCertified=true,
                decisionAccepted=true, sessionId='old-session', decisionId='forge-tui-17',
                sessionGeneration=2, physicalTransactionGeneration=1, authoritativeCursor=9}
            BridgeState.ui = {mounted=false, actionRows={}, contextInstanceId=nil}
            postCount = 0
            BridgeHttp.requestJson = function() postCount = postCount + 1 end
            BridgeRetireHumanActionState('new-match-begun')
            retiredDecision = BridgeState.lastDecision
            retiredActions = BridgeState.actionsByGuid
            BridgeSubmitChoice('forge-tui-17', 'old-pass', 'hud_pass')
        ");

        Assert.True(lua.Globals.Get("retiredDecision").IsNil());
        Assert.Equal(0, lua.Globals.Get("postCount").Number);
        Assert.Equal(0, lua.Globals.Get("retiredActions").Table.Length);
    }

    [Fact]
    public void MulliganBeforePhysicalCertificationIsBlockedThenUnlocksAfterReconciliation()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeState.eventSessionId = 'new-session'
            BridgeState.eventSessionGeneration = 9
            BridgeState.physicalTransactionGeneration = 7
            BridgeState.lastAppliedEventSequence = 0
            BridgeState.lastStateProjectedEventSequence = 0
            BridgeState.snapshotReconcileLastAppliedCursor = 0
            BridgeState.setupBusy = false
            BridgeState.bootstrapping = false
            BridgeState.resyncInFlight = false
            BridgeState.resyncStage = 'Failed'
            BridgeState.desyncLatched = true
            BridgeState.lastDecision = {decisionId='forge-tui-1', sessionId='new-session', kind='mulligan', eventCursor=47,
                actions={{actionId='keep', type='keep_hand'}, {actionId='mulligan', type='mulligan'}}}
            BridgeState.humanActionReadiness = {certified=false, globalCertified=false, decisionAccepted=false,
                sessionId='new-session', sessionGeneration=9, physicalTransactionGeneration=7,
                reason='bootstrap failed'}
            blocked = BridgeHumanActionReadiness(BridgeState.lastDecision, BridgeState.lastDecision.actions[1], 'mulligan')
            BridgeState.resyncStage = 'Completed'
            BridgeState.desyncLatched = false
            BridgeState.lastAppliedEventSequence = 47
            BridgeState.physicalStateCertificate = {sessionId='new-session', sessionGeneration=9,
                physicalTransactionGeneration=7, authoritativeCursor=47}
            BridgeState.humanActionReadiness = {certified=true, globalCertified=true, decisionAccepted=true,
                sessionId='new-session', decisionId='forge-tui-1', sessionGeneration=9,
                physicalTransactionGeneration=7, authoritativeCursor=47}
            unlocked = BridgeHumanActionReadiness(BridgeState.lastDecision, BridgeState.lastDecision.actions[1], 'mulligan')
        ");

        Assert.False(lua.Globals.Get("blocked").Table.Get("ready").Boolean);
        Assert.Equal("RESYNC", lua.Globals.Get("blocked").Table.Get("classification").String);
        Assert.True(lua.Globals.Get("unlocked").Table.Get("ready").Boolean);
    }

    private static Script NewProbe()
    {
        var lua = new Script(CoreModules.Preset_Complete);
        lua.DoString(@"
            function log(message) end
            function broadcastToAll(message, color) end
            function printToAll(message, color) end
            local probeObjects = {}
            function getAllObjects() return probeObjects end
            function getObjectFromGUID(guid) return nil end
            Wait = {frames=function(callback, frames) end, time=function(callback, delay) end}
            Time = {time=0}
            JSON = {encode=function(value) return '{}' end, decode=function(value) return {} end}
            os = {time=function() return 1 end, clock=function() return 0 end}
            Global = {}
        ");
        ExecuteProbe(lua, GlobalScript);
        return lua;
    }

    private static void ExecuteProbe(Script lua, string source)
    {
        try
        {
            lua.DoString(source);
        }
        catch (ScriptRuntimeException exception)
        {
            throw new Xunit.Sdk.XunitException(exception.DecoratedMessage);
        }
    }
}
