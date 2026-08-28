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
        Assert.Contains("deck.setRotation({rotation.x, rotation.y + 180, rotation.z})", Script);
        Assert.Contains("deck.putObject(object)", Script);
        Assert.Contains("deck.setRotation(rotation)", Script);
    }

    [Fact]
    public void KeepOrMulligan_IsAnImmediateForgeActionRatherThanALocalStagedSelection()
    {
        Assert.Contains("if BridgeDecisionNeedsConfirmation(decision) then", Script);
        Assert.Contains("BridgeSubmitChoice(decision.decisionId, action.actionId, \"hud_action\")", Script);
        Assert.Contains("mulliganStage or \"\") == \"bottom_selection\"", Script);
    }
}
