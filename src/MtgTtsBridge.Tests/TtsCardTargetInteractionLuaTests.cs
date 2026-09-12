using MoonSharp.Interpreter;

namespace MtgTtsBridge.Tests;

public sealed class TtsCardTargetInteractionLuaTests
{
    private static readonly string GlobalScript = File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.lua"));

    [Fact]
    public void FollowUpCardTargetDecisionRendersExactClickableTargetsAndRejectsStaleCallbacks()
    {
        var lua = NewProbe();
        lua.DoString(@"
            local cardsByGuid = {}
            testArrayMeta = {__len=function(values)
                local length = 0
                while values[length + 1] ~= nil do length = length + 1 end
                return length
            end}
            local function makeCard(guid)
                local card = {tag='Card', guid=guid, buttons={}, highlightCount=0, moveCount=0}
                function card.getGUID() return card.guid end
                function card.getName() return 'Raging Goblin' end
                function card.getButtons() return card.buttons end
                function card.createButton(button) table.insert(card.buttons, button) end
                function card.removeButton(index) table.remove(card.buttons, index + 1) end
                function card.highlightOn(color) card.highlightCount=card.highlightCount+1 end
                function card.highlightOff() end
                function card.getPosition() return {x=0,y=0,z=0} end
                function card.getRotation() return {x=0,y=0,z=0} end
                function card.setPositionSmooth() card.moveCount=card.moveCount+1 end
                function card.setRotationSmooth() card.moveCount=card.moveCount+1 end
                cardsByGuid[guid] = card
                return card
            end
            cards = {g79=makeCard('g79'), g80=makeCard('g80'), g78=makeCard('g78')}
            function getObjectFromGUID(guid) return cardsByGuid[guid] end
            Player = {White={}}
            BridgeState.eventSessionId = 'target-session'
            BridgeState.eventSessionGeneration = 1
            BridgeState.physicalTransactionGeneration = 1
            BridgeState.decisionPresentationGeneration = 7
            BridgeState.currentPhysicalPresentationGeneration = 1
            BridgeState.renderedDecisionPresentationKey = nil
            BridgeState.renderedDecisionPhysicalGeneration = nil
            BridgeState.submitting = false
            BridgeState.choiceProtocolPaused = false
            BridgeState.desyncLatched = false
            BridgeState.gameEnded = nil
            BridgeState.actionByGuid = {}
            BridgeState.highlightedGuids = {}
            BridgeState.targetButtonIndexByGuid = {}
            BridgeState.playerTargetControlGuids = {}
            BridgeState.physicalByInstanceId = {
                ['card:79']='g79', ['card:80']='g80', ['card:78']='g78'
            }
            BridgeState.physicalInstanceIdByGuid = {
                g79='card:79', g80='card:80', g78='card:78'
            }
            BridgeState.physicalSeatByGuid = {g79='forge-player-2', g80='forge-player-2', g78='forge-player-2'}
            BridgeState.physicalZoneByGuid = {g79='battlefield', g80='battlefield', g78='battlefield'}
            BridgeState.physicalContainerByInstanceId = {}
            BridgeState.authoritativeObjectByInstanceId = {
                ['card:79']={isVirtual=false}, ['card:80']={isVirtual=false}, ['card:78']={isVirtual=false}
            }
            BridgeState.ui = {mounted=true, actionRows={}, gameLogVisible=false, fastForwardActive=false,
                autoAdvanceMode='NORMAL', autoPassEmpty=false}
            function BridgeClearHighlights()
                BridgeState.actionByGuid = {}
                BridgeState.highlightedGuids = {}
                BridgeState.targetButtonIndexByGuid = {}
            end
            function BridgeRenderPreparedSpellPresentations() end
            function BridgeEnsureSelectionControls() end
            function BridgeEnsureContextualCompletionControl() end
            function BridgeHideMainPriorityControls() end
            function BridgeEnsureDecisionOptionControls() end
            function BridgeApplyDiscardPresentation() end
            function BridgeUiMarkDirty() end
            function BridgeScheduleSnapshotReconcile() end
            function BridgeRecordDecisionLifecycle() end
            function BridgeRecordDecisionPresentationRendered(key)
                BridgeState.renderedDecisionPresentationKey = key
                BridgeState.renderedDecisionPhysicalGeneration = BridgeState.currentPhysicalPresentationGeneration
            end
            function BridgeYieldControllerMode() return 'normal' end
            function BridgeClaimHumanTtsColor() end
            function BridgeShowError(message) lastError=message end
            function BridgePresentationMetric() end
            function BridgeSubmitChoice(decisionId, actionId, source)
                submitted = (submitted or 0) + 1
                lastSubmission = {decisionId=decisionId, actionId=actionId, source=source}
            end

            local mainDecision = {decisionId='forge-tui-9', kind='main_priority', seatId='forge-player-1',
                phaseName='Main phase, precombat', actions={
                    [1]={actionId='choice-3', type='cast_spell', cardInstanceId='spell:cut'}
                }}
            setmetatable(mainDecision.actions, testArrayMeta)
            targetDecision = {decisionId='forge-tui-10', kind='target_selection', seatId='forge-player-1',
                actions={
                    [1]={actionId='choice-0', type='choose_target', targetKind='card', cardIdentity='Raging Goblin', cardInstanceId='card:79'},
                    [2]={actionId='choice-1', type='choose_target', targetKind='card', cardIdentity='Raging Goblin', cardInstanceId='card:80'},
                    [3]={actionId='choice-2', type='choose_target', targetKind='card', cardIdentity='Raging Goblin', cardInstanceId='card:78'},
                    [4]={actionId='choice-3', type='cancel_casting', displayName='Cancel casting'}
                }}
            setmetatable(targetDecision.actions, testArrayMeta)
            BridgeState.lastDecision = mainDecision
            BridgeState.ui.actionRows = mainDecision.actions
            hudIndex = tonumber(string.match('BridgeHudAction1', '(%d+)$'))
            hudActionPresent = BridgeState.ui.actionRows[hudIndex] ~= nil
            hudHasAction = BridgeDecisionHasAction(mainDecision, mainDecision.actions[1].actionId)
            hudRetired = BridgeState.retiredChoiceDecisionIds[mainDecision.decisionId] == true
            hudGameEnded = tostring(BridgeState.gameEnded)
            BridgeHudAction('White', '', 'BridgeHudAction1')
            castSubmission = lastSubmission
            castAttempted = submitted or 0
            BridgeState.lastDecision = targetDecision
            BridgeState.ui.actionRows = targetDecision.actions
            mappingReady, mappingError = BridgeDecisionPhysicalMappingsReady(targetDecision)
            BridgeRenderDecision(targetDecision, true)
            targetDiagnostics = BridgeTargetInteractionDiagnosticPayload()
            targetButtons = {
                g79=cards.g79.buttons[1], g80=cards.g80.buttons[1], g78=cards.g78.buttons[1]
            }
            targetMappings = {
                g79=BridgeState.actionByGuid.g79,
                g80=BridgeState.actionByGuid.g80,
                g78=BridgeState.actionByGuid.g78
            }
            submitted = 0
            BridgeState.actionByGuid.g80 = targetMappings.g80
            onObjectPickUp('White', cards.g80)
            pickupSubmission = lastSubmission
            pickupSubmitCount = submitted or 0
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        Assert.True(lua.Globals.Get("hudActionPresent").Boolean);
        Assert.True(lua.Globals.Get("hudHasAction").Boolean);
        Assert.False(lua.Globals.Get("hudRetired").Boolean);
        Assert.Equal("nil", lua.Globals.Get("hudGameEnded").String);
        Assert.Equal(1, lua.Globals.Get("castAttempted").Number);
        Assert.Equal("forge-tui-9", lua.Globals.Get("castSubmission").Table.Get("decisionId").String);
        Assert.Equal("choice-3", lua.Globals.Get("castSubmission").Table.Get("actionId").String);
        Assert.True(lua.Globals.Get("mappingReady").Boolean, lua.Globals.Get("mappingError").String);
        var targetDiagnostics = lua.Globals.Get("targetDiagnostics").Table;
        Assert.Equal(3, targetDiagnostics.Get("actionByGuidCount").Number);
        Assert.Equal(3, targetDiagnostics.Get("targetControlCount").Number);
        Assert.Equal(3, targetDiagnostics.Get("highlightedGuidCount").Number);
        Assert.Equal("forge-tui-10", targetDiagnostics.Get("decisionId").String);

        foreach (var guid in new[] { "g79", "g80", "g78" })
        {
            var buttonValue = lua.Globals.Get("targetButtons").Table.Get(guid);
            Assert.False(buttonValue.IsNil(), $"no card target button for {guid}");
            var button = buttonValue.Table;
            var clickFunction = button.Get("click_function");
            Assert.False(clickFunction.IsNil(), $"target button has no callback for {guid}");
            Assert.Equal("BridgeSelectCardTarget", clickFunction.String);
            var mappedAction = lua.Globals.Get("targetMappings").Table.Get(guid).Table;
            Assert.Equal("choose_target", mappedAction.Get("type").String);
            Assert.Equal("choice-" + (guid == "g79" ? "0" : guid == "g80" ? "1" : "2"), mappedAction.Get("actionId").String);
        }

        lua.DoString(@"
            submitted = 0
            BridgeState.actionByGuid.g79 = targetMappings.g79
            BridgeState.actionByGuid.g80 = targetMappings.g80
            BridgeState.actionByGuid.g78 = targetMappings.g78
            BridgeSelectCardTarget(cards.g79, 'White', false)
            selectedSubmission = lastSubmission
            selectedMoveCount = cards.g79.moveCount + cards.g80.moveCount + cards.g78.moveCount
            -- A HUD action row is a second explicit producer for the same exact action.
            BridgeState.lastDecision = targetDecision
            BridgeState.ui.actionRows = targetDecision.actions
            BridgeState.actionByGuid.g79 = targetMappings.g79
            BridgeState.actionByGuid.g80 = targetMappings.g80
            BridgeState.actionByGuid.g78 = targetMappings.g78
            BridgeHudAction('White', '', 'BridgeHudAction1')
            hudSubmission = lastSubmission
            -- Replaying the old card callback after a decision replacement is inert.
            BridgeState.lastDecision = {decisionId='forge-tui-11', kind='main_priority', seatId='forge-player-1', actions={}}
            BridgeState.actionByGuid.g79 = targetMappings.g79
            BridgeSelectCardTarget(cards.g79, 'White', false)
            staleSubmissionCount = submitted
        ");

        Assert.Equal(2, lua.Globals.Get("submitted").Number);
        Assert.Equal("forge-tui-10", lua.Globals.Get("selectedSubmission").Table.Get("decisionId").String);
        Assert.Equal("choice-0", lua.Globals.Get("selectedSubmission").Table.Get("actionId").String);
        Assert.Equal("card_target_control", lua.Globals.Get("selectedSubmission").Table.Get("source").String);
        Assert.Equal(0, lua.Globals.Get("selectedMoveCount").Number);
        Assert.Equal(1, lua.Globals.Get("pickupSubmitCount").Number);
        Assert.Equal("choice-1", lua.Globals.Get("pickupSubmission").Table.Get("actionId").String);
        Assert.Equal("physical_card_target_pickup", lua.Globals.Get("pickupSubmission").Table.Get("source").String);
        Assert.Equal("choice-0", lua.Globals.Get("hudSubmission").Table.Get("actionId").String);
        Assert.Equal(2, lua.Globals.Get("staleSubmissionCount").Number);
        Assert.Equal("choice-3", state.Get("ui").Table.Get("actionRows").Table.Get(4).Table.Get("actionId").String);
    }

    private static Script NewProbe()
    {
        var lua = new Script();
        lua.DoString(@"
            function log(message) end
            function broadcastToAll(message, color) end
            function printToAll(message, color) end
            function getObjectFromGUID(guid) return nil end
            function getAllObjects() return {} end
            function Wait(frames) end
            Time = {waitForSeconds=function(seconds, callback) callback() end}
            JSON = {encode=function(value) return '{}' end, decode=function(value) return {} end}
            os = {time=function() return 1 end, clock=function() return 0 end}
            table.insert = function(values, value)
                setmetatable(values, testArrayMeta)
                local index = 1
                while values[index] ~= nil do index = index + 1 end
                values[index] = value
            end
            table.remove = function(values, index)
                local removed = values[index]
                while values[index + 1] ~= nil do
                    values[index] = values[index + 1]
                    index = index + 1
                end
                values[index] = nil
                return removed
            end
            local rawIpairs = ipairs
            ipairs = function(values)
                local index = 0
                return function(state, last)
                    index = index + 1
                    local value = state[index]
                    if value ~= nil then return index, value end
                    return nil
                end, values, 0
            end
            table.concat = function(values, separator)
                local result = ''
                for index, value in ipairs(values) do
                    if index > 1 then result = result .. separator end
                    result = result .. tostring(value or '')
                end
                return result
            end
        ");
        lua.DoString(GlobalScript);
        return lua;
    }
}
