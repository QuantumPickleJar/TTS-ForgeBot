using MoonSharp.Interpreter;

namespace MtgTtsBridge.Tests;

public sealed class PrepareLuaMappingTests
{
    private static readonly string GlobalScript = File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.lua"));

    [Fact]
    public void PreparedSpellUsesPreparedSourcePhysicalZoneAndRemainsClickable()
    {
        var lua = NewProbe();
        lua.DoString(@"
            local source = {tag='Card', guid='g31', moveCount=0}
            function source.getGUID() return source.guid end
            function source.getName() return 'Harmonized Trio' end
            function source.getButtons() return {} end
            function source.highlightOn() end
            function source.highlightOff() end
            function getObjectFromGUID(guid) if guid == 'g31' then return source end return nil end

            BridgeState.eventSessionId = 'prepare-session'
            BridgeState.eventSessionGeneration = 1
            BridgeState.physicalTransactionGeneration = 1
            BridgeState.submitting = false
            BridgeState.retiredChoiceDecisionIds = {}
            BridgeState.physicalByInstanceId = { ['forge:prepare-session:31'] = 'g31' }
            BridgeState.physicalInstanceIdByGuid = { ['g31'] = 'forge:prepare-session:31' }
            BridgeState.physicalSeatByGuid = { ['g31'] = 'forge-player-1' }
            BridgeState.physicalZoneByGuid = { ['g31'] = 'battlefield' }
            BridgeState.physicalContainerByInstanceId = {}
            BridgeState.authoritativeObjectByInstanceId = {
                ['forge:prepare-session:31'] = {
                    zone='battlefield', seatId='forge-player-1', isVirtual=false,
                    materializationPolicy='physical', cardDesignations={'prepared'}
                }
            }
            BridgeFindContainedCardEntry = function() return nil, nil, nil end
            BridgeState.actionByGuid = {}
            BridgeState.highlightedGuids = {}
            BridgeState.selectedActionIds = {}
            BridgeState.combatSelectedByGuid = {}
            BridgeState.targetButtonIndexByGuid = {}
            BridgeState.playerTargetControlGuids = {}
            BridgeState.ui = {mounted=true, actionRows={}, gameLogVisible=false, fastForwardActive=false,
                autoAdvanceMode='NORMAL', autoPassEmpty=false}
            BridgeState.selectionDecisionId = nil
            BridgeState.renderedDecisionPresentationKey = nil
            BridgeState.renderedDecisionPhysicalGeneration = nil
            BridgeState.currentPhysicalPresentationGeneration = 1
            BridgeState.decisionPresentationGeneration = 1
            BridgeState.pendingIntent = nil
            BridgeState.choiceProtocolPaused = false
            BridgeState.desyncLatched = false
            BridgeState.gameEnded = nil

            local preparedAction = {
                actionId='cast-brainstorm', type='cast_spell',
                cardInstanceId='forge:prepare-session:81',
                sourceCardInstanceId='forge:prepare-session:81',
                sourceZone='exile', castMode='prepare', costKind='prepare',
                preparedSourceCardInstanceId='forge:prepare-session:31',
                displayName='PREPARED SPELL: Cast instant: Brainstorm - {U}'
            }
            local decision = {
                decisionId='forge-tui-30', kind='main_priority', seatId='forge-player-1',
                actions={preparedAction}
            }

            ready, readyError = BridgeDecisionPhysicalMappingsReady(decision)
            assert(ready, tostring(readyError))
            resolved, resolveError = BridgeResolveExactActionPhysical(decision, preparedAction)
            assert(resolved ~= nil, tostring(resolveError))
            assert(resolved.guid == 'g31')
            assert(BridgeActionExactPhysicalInstanceId(preparedAction) == 'forge:prepare-session:31')
            assert(BridgeActionExpectedSourceZone(preparedAction) == 'exile')
            assert(BridgeActionExpectedPhysicalSourceZone(preparedAction) == 'battlefield')

            BridgeState.physicalByInstanceId['forge:prepare-session:31'] = nil
            missingReady = BridgeDecisionPhysicalMappingsReady(decision)
            assert(not missingReady)
            assert(BridgeState.lastActionPhysicalResolution.logicalCardInstanceId == 'forge:prepare-session:81')
            assert(BridgeState.lastActionPhysicalResolution.logicalSourceCardInstanceId == 'forge:prepare-session:81')
            assert(BridgeState.lastActionPhysicalResolution.logicalSourceZone == 'exile')
            assert(BridgeState.lastActionPhysicalResolution.preparedSourceCardInstanceId == 'forge:prepare-session:31')
            assert(BridgeState.lastActionPhysicalResolution.expectedPhysicalZone == 'battlefield')
            assert(BridgeState.lastActionPhysicalResolution.physicalInstanceId == 'forge:prepare-session:31')
            BridgeState.physicalByInstanceId['forge:prepare-session:31'] = 'g31'
            BridgeState.physicalInstanceIdByGuid['g31'] = 'wrong-instance'
            inverseReady = BridgeDecisionPhysicalMappingsReady(decision)
            assert(not inverseReady)
            BridgeState.physicalInstanceIdByGuid['g31'] = 'forge:prepare-session:31'
            BridgeState.physicalSeatByGuid['g31'] = 'forge-player-2'
            wrongSeatReady = BridgeDecisionPhysicalMappingsReady(decision)
            assert(not wrongSeatReady)
            BridgeState.physicalSeatByGuid['g31'] = 'forge-player-1'

            BridgeState.physicalZoneByGuid['g31'] = 'exile'
            wrongZoneReady = BridgeDecisionPhysicalMappingsReady(decision)
            assert(not wrongZoneReady)
            assert(BridgeState.lastActionPhysicalResolution.physicalGuid == 'g31')
            assert(BridgeState.lastActionPhysicalResolution.observedZone == 'exile')
            assert(BridgeState.lastActionPhysicalResolution.expectedPhysicalZone == 'battlefield')
            BridgeState.physicalZoneByGuid['g31'] = 'battlefield'

            BridgeState.authoritativeObjectByInstanceId['forge:prepare-session:31'].cardDesignations = {}
            designationReady = BridgeDecisionPhysicalMappingsReady(decision)
            assert(not designationReady)
            BridgeState.authoritativeObjectByInstanceId['forge:prepare-session:31'].cardDesignations = {'prepared'}

            BridgeState.authoritativeObjectByInstanceId['forge:prepare-session:91'] = {
                zone='exile', seatId='forge-player-1', isVirtual=false, materializationPolicy='physical'
            }
            BridgeState.physicalByInstanceId['forge:prepare-session:91'] = 'g91'
            BridgeState.physicalInstanceIdByGuid['g91'] = 'forge:prepare-session:91'
            BridgeState.physicalSeatByGuid['g91'] = 'forge-player-1'
            BridgeState.physicalZoneByGuid['g91'] = 'battlefield'
            ordinaryExileAction = {
                actionId='ordinary-exile', type='cast_spell',
                cardInstanceId='forge:prepare-session:91', sourceCardInstanceId='forge:prepare-session:91',
                sourceZone='exile', castMode='normal'
            }
            ordinaryReady = BridgeDecisionPhysicalMappingsReady({actions={ordinaryExileAction}, seatId='forge-player-1'})
            assert(not ordinaryReady)

            preparedRendered = false
            function BridgeRenderPreparedSpellPresentations(renderedDecision)
                preparedRendered = renderedDecision ~= nil
            end
            function BridgeResolveRevealForDecision() end
            function BridgePresentationMetric() end
            function BridgeRecordDecisionLifecycle() end
            function BridgeClearHighlights() end
            function BridgeResetSelectionState() end
            function BridgeEnsureSelectionControls() end
            function BridgeEnsureContextualCompletionControl() end
            function BridgeHideMainPriorityControls() end
            function BridgeEnsureDecisionOptionControls() end
            function BridgeApplyDiscardPresentation() end
            function BridgeCurrentAuthoritativeResult() return nil end
            function BridgeCurrentTerminalRecoveryError() return nil end
            function BridgeYieldControllerMode() return 'normal' end
            function BridgeActionPresentationAuthorized() return true end
            function BridgeUiMarkDirty() end
            function BridgeClaimHumanTtsColor() end
            BridgeSubmitChoice = function(decisionId, actionId, source)
                submitted = {decisionId=decisionId, actionId=actionId, source=source}
            end
            BridgeState.lastDecision = decision
            BridgeRenderDecision(decision, true)
            assert(preparedRendered)

            local tile = {vars={bridgeDecisionId='forge-tui-30', bridgeActionId='cast-brainstorm'}}
            function tile.getVar(name) return tile.vars[name] end
            BridgeCastPreparedSpellTile(tile, 'White', false)
            assert(submitted.actionId == 'cast-brainstorm')
            assert(submitted.source == 'prepared_spell_tile')
            assert(source.moveCount == 0)
        ");
    }

    private static Script NewProbe()
    {
        var lua = new Script();
        lua.DoString(@"
            function log() end
            function broadcastToAll() end
            function printToAll() end
            function getObjectFromGUID() return nil end
            function getAllObjects() return {} end
            function Wait() end
            Time = {waitForSeconds=function(_, callback) if callback then callback() end end}
            JSON = {encode=function() return '{}' end, decode=function() return {} end}
            os = {time=function() return 1 end, clock=function() return 0 end}
            local rawConcat = table.concat
            table.concat = function(values, separator)
                local normalized = {}
                local maximum = 0
                for index, _ in pairs(values or {}) do
                    if type(index) == 'number' and index > maximum then maximum = index end
                end
                for index = 1, maximum do normalized[index] = tostring(values[index] or '') end
                return rawConcat(normalized, separator or '')
            end
        ");
        lua.DoString(GlobalScript);
        return lua;
    }
}
