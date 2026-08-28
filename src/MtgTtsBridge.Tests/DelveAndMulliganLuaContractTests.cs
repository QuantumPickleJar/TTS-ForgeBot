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
        Assert.Contains("return deck.putObject(object, #entries)", Script);
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
        Assert.Contains("mulliganReturningInstanceIds[event.cardInstanceId] == true", Script);
        Assert.Contains("BridgeQueueMulliganBottomInsertion(event.seatId, object)", Script);
    }
}
