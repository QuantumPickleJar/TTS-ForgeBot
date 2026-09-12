using MoonSharp.Interpreter;

namespace MtgTtsBridge.Tests;

public sealed class DelveAndMulliganLuaContractTests
{
    private static readonly string Script = File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.lua"));

    [Fact]
    public void PhysicalDelveAndBottomSelection_UseTheNativeToggleTransaction()
    {
        Assert.Contains("kind == \"cost_selection\"", Script);
        Assert.Contains("kind == \"mulligan\" and tostring(decision.mulliganStage or \"\") == \"bottom_selection\"", Script);
        Assert.Contains("physical_structured_toggle", Script);
        Assert.Contains("No local zone move is made", Script);
    }

    [Fact]
    public void DelveDecision_UsesForgeRedrawSelectionAndBlocksPrematureDone()
    {
        var lua = new Script(CoreModules.Preset_Complete);
        lua.DoString(@"
            local rawTableConcat = table.concat
            table.concat = function(values, separator)
                local normalized = {}
                local maximum = 0
                for index, _ in pairs(values or {}) do
                    if type(index) == 'number' and index > maximum then maximum = index end
                end
                for index = 1, maximum do normalized[index] = tostring(values[index] or '') end
                return rawTableConcat(normalized, separator or '')
            end
            function log() end
            function broadcastToAll() end
            function printToAll() end
            function getObjectFromGUID() return nil end
            function getAllObjects() return {} end
            function Wait() end
            Time = { waitForSeconds = function(_, callback) if callback then callback() end end }
            JSON = { encode = function() return '{}' end, decode = function() return {} end }
        ");
        lua.DoString(Script);
        lua.DoString(@"
            BridgeState.ui = { mounted = true, dirty = true, autoPassEmpty = false,
                fastPlaytest = false, gameLogVisible = false, manaMode = 'AUTO',
                actionRows = {}, contextInstanceId = nil, selectedActionIds = {},
                gameLog = {}, graveyardActionRows = {}, graveyardFolderDecisionId = nil,
                candidatePanelRenderCount = 0, actionPanelRenderCount = 0 }
            BridgeState.lastDecision = nil
            BridgeState.retiredChoiceDecisionIds = {}
            BridgeState.choiceTransactions = {}
            BridgeState.selectedActionIds = {}
            BridgeState.choiceAttemptSequence = 0
            BridgeState.lastChoiceAttempt = nil
            BridgeState.playerStateBySeatId = { ['forge-player-1'] = {}, ['forge-player-2'] = {} }
            BridgeState.highlightedGuids = {}
            BridgeState.pendingIntent = nil
            BridgeState.gameEnded = nil
            BridgeState.desyncLatched = false
            BridgeState.resyncInFlight = false
            BridgeState.resyncScheduled = false
            BridgeState.currentTurnSeatId = 'forge-player-1'
            BridgeState.prioritySeatId = 'forge-player-1'
            BridgeState.currentPhase = 'Main phase, precombat'
            BridgeState.currentAuthoritativeResult = nil
            BridgeState.terminalRecoveryError = nil
            local attributes = {}
            local submissions = {}
            local errors = {}
            BridgeUiSet = function(id, attribute, value) attributes[id .. '.' .. attribute] = tostring(value) end
            BridgeUiMarkDirty = function() end
            BridgeSetStatus = function() end
            BridgeRenderDecision = function() end
            BridgeRenderRevealSurface = function() end
            BridgeClaimHumanTtsColor = function() end
            BridgeRecordInteractionProducer = function() end
            BridgeShowError = function(message) table.insert(errors, tostring(message)) end
            BridgeSubmitChoice = function(decisionId, actionId, source)
                table.insert(submissions, { decisionId = decisionId, actionId = actionId, source = source })
            end
            BridgeCurrentAuthoritativeResult = function() return nil end
            BridgeCurrentTerminalRecoveryError = function() return nil end
            BridgeYieldControllerMode = function() return 'normal' end
            BridgeTurnLabel = function() return 'TURN 1' end
            BridgeHudPhaseColor = function() return '#ffffff' end
            BridgeActionPresentationAuthorized = function() return true end
            BridgeCreatureTypePrepare = function() end
            BridgeGraveyardPrepareDecision = function(_, actions) return actions end
            BridgeState._attributes = attributes
            BridgeState._submissions = submissions
            BridgeState._errors = errors

            function MakeDelve(selected, selectedId)
                return {
                    decisionId = 'forge-tui-delve', kind = 'cost_selection', costKind = 'delve',
                    candidateSourceZone = 'graveyard', minSelections = 3, maxSelections = 5,
                    selectedCount = selected, confirmRequired = true, requiresConfirmation = true,
                    allowsCancel = true, seatId = 'forge-player-1',
                    actions = {
                        { actionId = 'done', type = 'choose_none', displayName = 'Done' },
                        { actionId = 'card-31', type = 'choose_option', displayName = 'Harmonized Trio', cardInstanceId = 'forge-object:31', sourceZone = 'graveyard', isSelected = selectedId == '31' },
                        { actionId = 'card-25', type = 'choose_option', displayName = 'Ashiok', cardInstanceId = 'forge-object:25', sourceZone = 'graveyard', isSelected = selectedId == '25' },
                        { actionId = 'card-2', type = 'choose_option', displayName = 'Treasure Cruise', cardInstanceId = 'forge-object:2', sourceZone = 'graveyard', isSelected = selectedId == '2' },
                        { actionId = 'card-10', type = 'choose_option', displayName = 'Island', cardInstanceId = 'forge-object:10', sourceZone = 'graveyard', isSelected = selectedId == '10' },
                        { actionId = 'card-9', type = 'choose_option', displayName = ""Stitcher's Supplier"", cardInstanceId = 'forge-object:9', sourceZone = 'graveyard', isSelected = selectedId == '9' }
                    }
                }
            end

            local decision = MakeDelve(1, '2')
            assert(BridgeIsStructuredForgeToggleChoice(decision), 'delve was not structured')
            assert(decision.candidateSourceZone == 'graveyard', 'wrong delve source zone')
            assert(decision.minSelections == 3 and decision.maxSelections == 5, 'wrong delve limits')
            assert(BridgeCanSubmitStructuredDone(decision, 'test') == false, 'premature Done was accepted')
            decision = MakeDelve(3, '9')
            assert(BridgeCanSubmitStructuredDone(decision, 'test') == true, 'valid Done was blocked')
        ");
    }

    [Fact]
    public void StructuredDone_RemainsForgeValidatedForOptionalAndRequiredSelections()
    {
        Assert.Contains("BridgeCanSubmitStructuredDone", Script);
        Assert.Contains("selected < minimum or selected > maximum", Script);
        Assert.Contains("hud_collection_done", Script);
    }

    [Fact]
    public void DelveHudExplainsAuthoritativeGraveyardExileAndDynamicLimits()
    {
        Assert.Contains("DELVE - SELECT ", Script);
        Assert.Contains("CARDS FROM YOUR GRAVEYARD TO EXILE, THEN CONFIRM", Script);
        Assert.Contains("Each exiled card pays {1} of this spell's generic mana cost.", Script);
        Assert.Contains("DELVE: ", Script);
        Assert.Contains("need at least ", Script);
    }

    [Fact]
    public void StructuredConfirm_UsesCurrentForgeDoneInsteadOfLegacyLocalSelection()
    {
        var start = Script.IndexOf("function BridgeConfirmSelection", StringComparison.Ordinal);
        var end = Script.IndexOf("function BridgeCancelSelection", start, StringComparison.Ordinal);
        var confirm = Script[start..end];
        var structuredStart = confirm.IndexOf("if BridgeIsStructuredForgeToggleChoice(decision)", StringComparison.Ordinal);
        var legacyStart = confirm.IndexOf("if decision == nil", structuredStart, StringComparison.Ordinal);
        var structured = confirm[structuredStart..legacyStart];

        Assert.Contains("BridgeIsStructuredForgeToggleChoice(decision)", structured);
        Assert.Contains("action.type == \"choose_none\"", structured);
        Assert.Contains("BridgeCanSubmitStructuredDone(decision, \"physical_structured_done\")", structured);
        Assert.Contains("BridgeSubmitChoice(decision.decisionId, doneAction.actionId, \"physical_structured_done\")", structured);
        Assert.DoesNotContain("BridgeSelectionCount()", structured);
        Assert.DoesNotContain("BridgeState.selectedActionIds", structured);
    }

    [Fact]
    public void StructuredCancel_DoesNotClearForgeOwnedSelectionLocally()
    {
        var start = Script.IndexOf("function BridgeCancelSelection", StringComparison.Ordinal);
        var end = Script.IndexOf("function BridgeRenderDecision", start, StringComparison.Ordinal);
        var cancel = Script[start..end];
        var structuredStart = cancel.IndexOf("if BridgeIsStructuredForgeToggleChoice(decision)", StringComparison.Ordinal);
        var legacyStart = cancel.IndexOf("BridgeResetSelectionState()", structuredStart, StringComparison.Ordinal);
        var structured = cancel[structuredStart..legacyStart];

        Assert.Contains("BridgeIsStructuredForgeToggleChoice(decision)", structured);
        Assert.Contains("STRUCTURED_CANCEL_BLOCKED", structured);
        Assert.DoesNotContain("BridgeResetSelectionState()", structured);
    }

    [Fact]
    public void MulliganBottomSelection_UsesForgeSelectedCountAndBottomInsertionOnlyAfterDone()
    {
        Assert.Contains("BridgeIsStructuredForgeToggleChoice(decision)", Script);
        Assert.Contains("selected = tonumber(decision.selectedCount or 0) or 0", Script);
        Assert.Contains("or action.isSelected == true", Script);
        Assert.Contains("action.type == \"choose_none\"", Script);
        Assert.Contains("candidate.isSelected == true", Script);
        Assert.Contains("mulliganBottomInstanceIds", Script);
        Assert.Contains("function BridgeQueueMulliganBottomInsertion", Script);
        Assert.Contains("function BridgeProcessMulliganBottomQueue", Script);
        Assert.Contains("function BridgeInsertPhysicalCardIntoLibrary", Script);
        Assert.Contains("library.putObject(object, #entries)", Script);
        Assert.Contains("BridgeVerifyLibraryContainment", Script);
        Assert.DoesNotContain("rotation.z + 180", Script);
    }

    [Fact]
    public void StructuredPhysicalDiscard_ReRendersForgeSelectedStateBeforeAcceptingAnotherToggle()
    {
        Assert.Contains("physical_structured_toggle", Script);
        Assert.Contains("body.currentDecision.decisionId == decisionId", Script);
        Assert.Contains("BridgeIsStructuredForgeToggleChoice(body.currentDecision)", Script);
        Assert.Contains("BridgeState.choiceTransactions[decisionId] = nil", Script);
        Assert.Contains("including selectedCount and", Script);
    }

    [Fact]
    public void KeepOrMulligan_IsAnImmediateForgeActionRatherThanALocalStagedSelection()
    {
        Assert.Contains("if BridgeDecisionNeedsConfirmation(decision) then", Script);
        Assert.Contains("BridgeSubmitChoice(decision.decisionId, action.actionId, \"hud_action\")", Script);
        Assert.Contains("mulliganStage or \"\") == \"bottom_selection\"", Script);
    }

    [Fact]
    public void RejectedOpeningHand_IsQueuedAtBottomBeforeReplacementDraw()
    {
        Assert.Contains("mulliganReturningInstanceIds", Script);
        Assert.Contains("selectedAction.type == \"mulligan\"", Script);
        Assert.Contains("zone == \"hand\" and seatId == activeDecision.seatId", Script);
        Assert.Contains("local returningMarker = BridgeState.mulliganReturningInstanceIds[event.cardInstanceId]", Script);
        Assert.Contains("returningMarker.sessionId == BridgeState.eventSessionId", Script);
        Assert.Contains("BridgeQueueMulliganBottomInsertion(event.seatId, object)", Script);
    }

    [Fact]
    public void MulliganLibraryInsertion_AllowsTtsContainmentToSettleBeforeFailingDuplicateAudit()
    {
        var start = Script.IndexOf("function BridgeVerifyLibraryIdentityStability", StringComparison.Ordinal);
        var end = Script.IndexOf("function BridgeInsertPhysicalCardIntoLibrary", start, StringComparison.Ordinal);
        var stability = Script[start..end];
        var insertionStart = end;
        var insertionEnd = Script.IndexOf("function BridgeProcessMulliganBottomQueue", insertionStart, StringComparison.Ordinal);
        var insertion = Script[insertionStart..insertionEnd];

        Assert.Contains("local strictDuplicateCount = BridgeAuditDuplicateLibraryGuids(ignoredGuids)", stability);
        Assert.Contains("local ignoredGuids = BridgeOwnedContainmentGuids(expectedGuids, owner)", stability);
        Assert.Contains("BridgeAuditDuplicateLibraryGuids(ignoredGuids)", stability);
        Assert.Contains("attempt >= 30", stability);
        Assert.Contains("BridgeWaitFrames(function()", stability);
        Assert.Contains("waiting for TTS library containment to settle", stability);
        Assert.Contains("BridgeVerifyLibraryIdentityStability(function(stable, stabilityError)", insertion);
        Assert.DoesNotContain("local duplicateGuidCount = BridgeAuditDuplicateLibraryGuids()", insertion);
    }

    [Fact]
    public void MulliganLibraryInsertion_WaitsForHandCardToLeaveTtsHandBeforePutObject()
    {
        Assert.Contains("function BridgeSeatHandContainsGuid(seatId, guid)", Script);
        Assert.Contains("card remained in player hand before library insertion", Script);
        Assert.Contains("releaseMarkers[guid] = true", Script);
        Assert.Contains("BridgeWaitFrames(function() waitForHandRelease(attempt + 1) end, 2)", Script);
        Assert.Contains("Stage the card over", Script);
        Assert.Contains("object.setPosition({libraryPosition.x, libraryPosition.y + 3.0, libraryPosition.z})", Script);
        Assert.Contains("BridgeInsertPhysicalCardIntoLibrary(seatId, object, placementMode, callback, cardInstanceId, owner)", Script);
    }

    [Fact]
    public void MulliganBottomFailure_DoesNotContinueMutatingTheRemainingQueue()
    {
        var start = Script.IndexOf("function BridgeProcessMulliganBottomQueue", StringComparison.Ordinal);
        var end = Script.IndexOf("function BridgeQueueMulliganBottomInsertion", start, StringComparison.Ordinal);
        var processor = Script[start..end];
        var failure = processor.IndexOf("if not ok then", StringComparison.Ordinal);
        var success = processor.IndexOf("if instanceId ~= nil then", failure, StringComparison.Ordinal);

        Assert.True(failure >= 0 && success > failure);
        Assert.Contains("BridgeStopOnDesync", processor[failure..success]);
        Assert.Contains("mulliganBottomQueueBySeatId[seatId] = nil", processor[failure..success]);
        Assert.DoesNotContain("complete()", processor[failure..success]);
    }

    [Fact]
    public void DecisionRendering_IncludesLiveDecisionSeatHandAfterMulligan()
    {
        var start = Script.IndexOf("function BridgeRenderDecision(decision, force)", StringComparison.Ordinal);
        var end = Script.IndexOf("function BridgeShowError", start, StringComparison.Ordinal);
        var renderer = Script[start..end];

        Assert.Contains("local function addDecisionCandidate(object)", renderer);
        Assert.Contains("TTS does not guarantee that cards held in a hand are returned by", renderer);
        Assert.Contains("BridgeTryGetSeatHandObjects(decision.seatId)", renderer);
        Assert.Contains("for _, object in ipairs(handObjects or {}) do", renderer);
    }

    [Fact]
    public void OpeningKeepOrMulligan_IsGatedByExactSnapshotHandReadiness()
    {
        var deferStart = Script.IndexOf("function BridgeShouldDeferDecision", StringComparison.Ordinal);
        var retryStart = Script.IndexOf("function BridgeScheduleOpeningHandReadinessRetry", deferStart, StringComparison.Ordinal);
        var renderStart = Script.IndexOf("function BridgeTryPresentPendingDecision", retryStart, StringComparison.Ordinal);
        var defer = Script[deferStart..retryStart];
        var retry = Script[retryStart..renderStart];

        Assert.Contains("decision.kind == \"mulligan\"", defer);
        Assert.Contains("mulliganStage or \"\") == \"keep_or_mulligan\"", defer);
        Assert.Contains("expectedHandInstanceIdsBySeatId", Script);
        Assert.Contains("BridgeCheckOpeningHandReadiness(decision.seatId)", defer);
        Assert.Contains("physicalInstanceIdByGuid[guid] ~= instanceId", Script);
        Assert.Contains("physicalSeatByGuid[guid] ~= seatId", Script);
        Assert.Contains("physicalZoneByGuid[guid] ~= \"hand\"", Script);
        Assert.Contains("handGuids[guid] ~= true", Script);
        Assert.Contains("readyCount == expectedCount", Script);
        Assert.DoesNotContain("== 7", defer);
        Assert.Contains("BridgeWaitFrames", retry);
        Assert.Contains("BRIDGE_OPENING_HAND_READINESS_TIMEOUT_SECONDS", Script);
        Assert.Contains("BridgeScheduleSnapshotReconcile(\"opening-hand-readiness\")", Script);
        Assert.Contains("BridgeRecoverFromHandReadinessTimeout", Script);
        Assert.Contains("BridgeScheduleSnapshotReconcile(\"hand-readiness-timeout\")", Script);
        Assert.Contains("opening hand readiness timeout", Script);
    }

    [Fact]
    public void OpeningHandReadiness_UsesSnapshotIdsAndNeverDiagnosticCardNames()
    {
        var start = Script.IndexOf("function BridgeRecordExpectedHandIdentities", StringComparison.Ordinal);
        var end = Script.IndexOf("function BridgeCheckOpeningHandReadiness", start, StringComparison.Ordinal);
        var capture = Script[start..end];

        Assert.Contains("zone.name or \"\")", capture);
        Assert.Contains("== \"hand\"", capture);
        Assert.Contains("card.cardInstanceId", capture);
        Assert.DoesNotContain("card.cardName", capture);
        Assert.Contains("openingHandReadinessSnapshotPending = not complete", capture);
    }

    [Fact]
    public void BootstrapMatching_ReservesTtsHandMembersBeforeMatchingDuplicateNamesInOtherZones()
    {
        var start = Script.IndexOf("function BridgeReconcileSeatSnapshot", StringComparison.Ordinal);
        var end = Script.IndexOf("function BridgeMaterializeSeatSnapshot", start, StringComparison.Ordinal);
        var reconcile = Script[start..end];

        Assert.Contains("local handByName = {}", reconcile);
        Assert.Contains("local nonHandByName = {}", reconcile);
        Assert.Contains("BridgeBuildSeatHandGuidSet(seatSnapshot.seatId)", reconcile);
        Assert.Contains("handGuids[assetGuid] == true and handByName or nonHandByName", reconcile);
        Assert.Contains("zoneName == \"hand\"", reconcile);
        Assert.Contains("handByName[normalized]", reconcile);
        Assert.Contains("nonHandByName[normalized]", reconcile);
    }

    [Fact]
    public void OpeningHandReadinessTimeout_RechecksReadyHandBeforeStoppingSynchronization()
    {
        var start = Script.IndexOf("if elapsed >= BRIDGE_OPENING_HAND_READINESS_TIMEOUT_SECONDS then", StringComparison.Ordinal);
        var stop = Script.IndexOf("BridgeStopOnDesync", start, StringComparison.Ordinal);
        var timeout = Script[start..stop];

        Assert.Contains("local ready, readyCount, expectedCount, readinessDetail", timeout);
        Assert.Contains("if ready then", timeout);
        Assert.Contains("BridgeTryPresentPendingDecision(reason .. \"-readiness-recovered\")", timeout);
        Assert.True(Script.IndexOf("BridgeTryPresentPendingDecision(reason .. \"-readiness-recovered\")", start, StringComparison.Ordinal)
            < stop);
    }

    [Fact]
    public void HandReadinessTimeout_UsesBoundedAuthoritativeRecoveryBeforeDesyncLatch()
    {
        var start = Script.IndexOf("function BridgeRecoverFromHandReadinessTimeout", StringComparison.Ordinal);
        var end = Script.IndexOf("function BridgeTryPresentPendingDecision", start, StringComparison.Ordinal);
        Assert.True(start >= 0 && end > start);
        var recovery = Script[start..end];

        Assert.Contains("handReadinessRecoveryDecisionId", recovery);
        Assert.Contains("handReadinessRecoverySessionId", recovery);
        Assert.Contains("BRIDGE_HAND_READINESS_RECOVERY_ATTEMPTS", recovery);
        Assert.Contains("BridgeScheduleSnapshotReconcile(\"hand-readiness-timeout\")", recovery);
        Assert.Contains("BridgeResyncFromAuthoritativeSnapshot(\"hand-readiness-timeout\")", recovery);
        Assert.DoesNotContain("cardName", recovery);
    }
}
