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

    [Fact]
    public void SuccessfulSameSessionReconcileRecertifiesMulliganAndKeepsChoicesVisible()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeState.eventSessionId = 'mulligan-session'
            BridgeState.eventSessionGeneration = 12
            BridgeState.physicalTransactionGeneration = 4
            BridgeState.lastAppliedEventSequence = 54
            BridgeState.lastStateProjectedEventSequence = 54
            BridgeState.snapshotReconcileLastAppliedCursor = 54
            BridgeState.setupStage = 'READY'
            BridgeState.bootstrapStage = 'READY'
            BridgeState.resyncStage = 'Idle'
            BridgeState.desyncLatched = false
            BridgeState.resyncInFlight = false
            BridgeState.setupBusy = false
            BridgeState.bootstrapping = false
            BridgeState.snapshotReconcileInFlight = false
            BridgeState.physicalStateCertificate = {
                sessionId='mulligan-session', sessionGeneration=12,
                physicalTransactionGeneration=4, authoritativeCursor=54
            }
            BridgeState.lastDecision = {
                decisionId='forge-tui-1', sessionId='mulligan-session', kind='mulligan',
                mulliganStage='keep_or_mulligan', eventCursor=54, seatId='forge-player-1',
                actions={{actionId='forge-tui-1-choice-0', type='keep_hand', displayName='Keep', shortLabel='Keep'},
                    {actionId='forge-tui-1-choice-1', type='mulligan', displayName='Mulligan', shortLabel='Mulligan'}}
            }
            BridgeState.humanActionReadiness = {
                certified=true, globalCertified=true, decisionAccepted=true,
                sessionId='mulligan-session', decisionId='forge-tui-1',
                sessionGeneration=12, physicalTransactionGeneration=4,
                authoritativeCursor=54
            }
            BridgeState.ui = {mounted=true, dirty=true, actionRows={}, selectedActionIds={},
                gameLogVisible=false, fastPlaytest=false, manaMode='AUTO', autoPassEmpty=false,
                graveyardActionRows={}, playerStateBySeatId={}, contextInstanceId=nil}
            BridgeState.playerStateBySeatId = {['forge-player-1']={}, ['forge-player-2']={}}
            BridgeState.retiredChoiceDecisionIds = {}
            BridgeState.highlightedGuids = {}
            BridgeState.pendingIntent = nil
            BridgeState.gameEnded = nil
            BridgeState.currentTurnSeatId = nil
            BridgeState.prioritySeatId = nil
            BridgeState.currentPhase = nil
            BridgeState.stackSummary = {}
            uiAttributes = {}
            submissions = {}
            UI = {setAttribute=function(id, attribute, value)
                uiAttributes[id .. '.' .. attribute] = tostring(value)
            end, getAttribute=function(id, attribute) return uiAttributes[id .. '.' .. attribute] end}
            BridgePhysicalMutationOperationsIdle = function() return true end
            BridgeDecisionPhysicalMappingsReady = function() return true end
            BridgeCheckOpeningHandReadiness = function() return true, 7, 7, '' end
            BridgeUiMarkDirty = function(reason) BridgeState.ui.dirty = true end
            BridgeSetStatus = function() end
            BridgeShowError = function() end
            BridgeRecordInteractionProducer = function() end
            BridgeClaimHumanTtsColor = function() end
            BridgeCurrentAuthoritativeResult = function() return nil end
            BridgeCurrentTerminalRecoveryError = function() return nil end
            BridgeYieldControllerMode = function() return 'normal' end
            BridgeTurnLabel = function() return 'TURN 0' end
            BridgeHudPhaseColor = function() return '#ffffff' end
            BridgeActionPresentationAuthorized = function() return true end
            BridgeCreatureTypePrepare = function() end
            BridgeGraveyardPrepareDecision = function(_, actions) return actions end
            BridgeIsDiscardChoice = function() return false end
            BridgeDecisionNeedsConfirmation = function() return false end
            BridgeSelectionCount = function() return 0 end
            BridgeIsStructuredForgeToggleChoice = function() return false end
            BridgeSubmitChoice = function(decisionId, actionId, source)
                table.insert(submissions, {decisionId=decisionId, actionId=actionId, source=source})
            end

            -- A legitimate physical generation change blocks the decision
            -- until the successful verified snapshot is finalized.
            BridgeState.physicalTransactionGeneration = 5
            BridgeState.snapshotReconcileInFlight = true
            blocked = BridgeHumanActionReadiness(BridgeState.lastDecision, nil, 'hud')
            BridgeState.ui.dirty = true
            BridgeUiFlush()
            blockedActive = uiAttributes['BridgeHudAction1.active']
            blockedInteractable = uiAttributes['BridgeHudAction1.interactable']
            blockedPrompt = uiAttributes['BridgeHudPrompt.text']
            BridgeState.snapshotReconcileInFlight = false
            recertified, recertifyReason = BridgeFinalizeSuccessfulSnapshotReconcileReadiness(
                {sessionId='mulligan-session', eventCursor=54}, 'safe-snapshot-verified')
            BridgeState.humanActionReadiness = {
                certified=false, globalCertified=false, decisionAccepted=false,
                sessionId='mulligan-session', reason='temporary reconcile'
            }
            BridgeState.ui.dirty = true
            BridgeUiFlush()
            temporarilyBlockedActive = uiAttributes['BridgeHudAction1.active']
            temporarilyBlockedInteractable = uiAttributes['BridgeHudAction1.interactable']
            BridgeFinalizeSuccessfulSnapshotReconcileReadiness(
                {sessionId='mulligan-session', eventCursor=54}, 'second-verified')
            BridgeState.ui.dirty = true
            BridgeUiFlush()
            readyActive = uiAttributes['BridgeHudAction1.active']
            readyInteractable = uiAttributes['BridgeHudAction1.interactable']
            readyPrompt = uiAttributes['BridgeHudPrompt.text']
            readyStatus = uiAttributes['BridgeHudStatus.text']
            actionRowCount = #BridgeState.ui.actionRows
            actionRow1Id = BridgeState.ui.actionRows[1] and BridgeState.ui.actionRows[1].actionId or 'nil'
            actionRow2Id = BridgeState.ui.actionRows[2] and BridgeState.ui.actionRows[2].actionId or 'nil'
            actionButton1Text = uiAttributes['BridgeHudAction1.text']
            actionButton2Text = uiAttributes['BridgeHudAction2.text']
        ");

        Assert.False(lua.Globals.Get("blocked").Table.Get("ready").Boolean);
        Assert.Equal("RECONCILE", lua.Globals.Get("blocked").Table.Get("classification").String);
        Assert.True(lua.Globals.Get("recertified").Boolean, lua.Globals.Get("recertifyReason").String);
        Assert.Equal("true", lua.Globals.Get("blockedActive").String);
        Assert.Equal("false", lua.Globals.Get("blockedInteractable").String);
        Assert.True(lua.Globals.Get("blockedPrompt").String.Contains("OPENING HAND"), lua.Globals.Get("blockedPrompt").String);
        Assert.Equal("true", lua.Globals.Get("temporarilyBlockedActive").String);
        Assert.Equal("false", lua.Globals.Get("temporarilyBlockedInteractable").String);
        Assert.Equal("true", lua.Globals.Get("readyActive").String);
        Assert.Equal("true", lua.Globals.Get("readyInteractable").String);
        Assert.Contains("OPENING HAND - KEEP OR MULLIGAN", lua.Globals.Get("readyPrompt").String);
        Assert.Contains("OPENING HAND", lua.Globals.Get("readyStatus").String);
        Assert.Equal(2, lua.Globals.Get("actionRowCount").Number);
        Assert.NotEqual(lua.Globals.Get("actionRow1Id").String, lua.Globals.Get("actionRow2Id").String);
    }

    [Fact]
    public void FailedSameSessionReconcileDoesNotRecertifyDecision()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeState.eventSessionId = 'failed-session'
            BridgeState.eventSessionGeneration = 2
            BridgeState.physicalTransactionGeneration = 8
            BridgeState.lastAppliedEventSequence = 54
            BridgeState.setupStage = 'READY'
            BridgeState.resyncStage = 'Idle'
            BridgeState.snapshotReconcileInFlight = false
            BridgeState.desyncLatched = false
            BridgeState.resyncInFlight = false
            BridgeState.lastDecision = {decisionId='forge-tui-1', sessionId='failed-session',
                kind='mulligan', mulliganStage='keep_or_mulligan', eventCursor=54,
                actions={{actionId='keep', type='keep_hand'}, {actionId='mulligan', type='mulligan'}}}
            BridgeState.humanActionReadiness = {certified=false, globalCertified=false,
                decisionAccepted=false, sessionId='failed-session', reason='reconcile failed'}
            BridgeDecisionPhysicalMappingsReady = function() return false, 'missing exact hand mapping' end
            result, reason = BridgeFinalizeSuccessfulSnapshotReconcileReadiness(
                {sessionId='failed-session', eventCursor=54}, 'failed-verification')
        ");

        Assert.False(lua.Globals.Get("result").Boolean);
        Assert.Contains("missing exact hand mapping", lua.Globals.Get("reason").String);
        Assert.False(lua.Globals.Get("BridgeState").Table.Get("humanActionReadiness").Table.Get("certified").Boolean);
    }

    [Fact]
    public void ReadinessDiagnosticProbeReportsPredicateWithoutMutatingCertificate()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeState.eventSessionId = 'diagnostic-session'
            BridgeState.eventSessionGeneration = 3
            BridgeState.physicalTransactionGeneration = 9
            BridgeState.snapshotReconcileInFlight = true
            BridgeState.lastDecision = {decisionId='forge-tui-1', sessionId='diagnostic-session',
                kind='mulligan', eventCursor=54, actions={}}
            BridgeState.humanActionReadiness = {
                certified=true, globalCertified=true, decisionAccepted=true,
                sessionId='diagnostic-session', decisionId='forge-tui-1',
                sessionGeneration=3, physicalTransactionGeneration=8,
                authoritativeCursor=54, reason='certified-before-reconcile'
            }
            diagnostic = BridgeHumanActionReadinessDiagnosticPayload()
        ");

        var diagnostic = lua.Globals.Get("diagnostic").Table;
        Assert.True(diagnostic.Get("certified").Boolean);
        Assert.Equal("diagnostic-session", diagnostic.Get("sessionId").String);
        Assert.Equal("forge-tui-1", diagnostic.Get("decisionId").String);
        Assert.Equal(8, diagnostic.Get("physicalTransactionGeneration").Number);
        Assert.Equal(9, diagnostic.Get("currentPhysicalTransactionGeneration").Number);
        Assert.False(diagnostic.Get("probe").Table.Get("ready").Boolean);
        Assert.Equal("RECONCILE", diagnostic.Get("probe").Table.Get("classification").String);
        Assert.True(lua.Globals.Get("BridgeState").Table.Get("humanActionReadiness").Table.Get("certified").Boolean);
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
