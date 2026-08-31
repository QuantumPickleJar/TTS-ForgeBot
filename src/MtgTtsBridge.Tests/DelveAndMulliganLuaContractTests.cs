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
    public void StructuredDone_RemainsForgeValidatedForOptionalAndRequiredSelections()
    {
        Assert.Contains("BridgeCanSubmitStructuredDone", Script);
        Assert.Contains("selected < minimum or selected > maximum", Script);
        Assert.Contains("hud_collection_done", Script);
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

        Assert.Contains("local ignoredGuids = attempt < 30 and expectedGuids or nil", stability);
        Assert.Contains("BridgeAuditDuplicateLibraryGuids(ignoredGuids)", stability);
        Assert.Contains("attempt >= 30", stability);
        Assert.Contains("BridgeWaitFrames(function()", stability);
        Assert.Contains("waiting for TTS library containment to settle", stability);
        Assert.Contains("BridgeVerifyLibraryIdentityStability(function(stable, stabilityError)", insertion);
        Assert.DoesNotContain("local duplicateGuidCount = BridgeAuditDuplicateLibraryGuids()", insertion);
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
        Assert.Contains("BridgeStopOnDesync(string.format(", Script);
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
        Assert.Contains("openingHandReadinessSnapshotPending = false", capture);
    }
}
