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
        Assert.Contains("function BridgeInsertCardAtLibraryBottom(deck, object, seat)", Script);
        Assert.Contains("return deck.putObject(object, #entries + 1)", Script);
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
}
