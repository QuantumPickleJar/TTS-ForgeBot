namespace MtgTtsBridge.Tests;

public sealed class PrepareLuaContractTests
{
    private static readonly string Script = File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.lua"));

    [Fact]
    public void PreparedSpell_UsesVirtualActionAndNeverMovesTheSourcePermanent()
    {
        Assert.Contains("preparedSourceCardInstanceId", Script);
        Assert.Contains("physical_prepared_spell", Script);
        Assert.Contains("moved as though it were the spell being cast", Script);
        Assert.Contains("cardDesignationsByInstanceId", Script);
    }

    [Fact]
    public void PreparedDesignation_HasAuthoritativeInspectionIndicatorAndRestoresOnRemoval()
    {
        Assert.Contains("function BridgeSetPreparedDesignationPresentation", Script);
        Assert.Contains("PREPARED", Script);
        Assert.Contains("preparedDescriptionByGuid", Script);
        Assert.Contains("designations[\"prepared\"] == true", Script);
        Assert.Contains("BridgeSetPreparedDesignationPresentation(object, false)", Script);
        Assert.Contains("BridgeState.physicalSeatByGuid[guid]", Script);
    }

    [Fact]
    public void PreparedDesignation_HasPersistentPhysicalBadgeAndTransitionPulse()
    {
        Assert.Contains("function BridgeEnsurePreparedBadge", Script);
        Assert.Contains("label = \"PREPARED\"", Script);
        Assert.Contains("function BridgePulsePreparedDesignation", Script);
        Assert.Contains("object.highlightOn({0.62, 0.18, 0.86}, 1.5)", Script);
        var pulseStart = Script.IndexOf("function BridgePulsePreparedDesignation", StringComparison.Ordinal);
        var pulseEnd = Script.IndexOf("function BridgePreparedSpellPosition", pulseStart, StringComparison.Ordinal);
        Assert.DoesNotContain("table.insert(BridgeState.highlightedGuids", Script[pulseStart..pulseEnd]);
        Assert.Contains("preparedBadgeGuidByInstanceId", Script);
        Assert.Contains("hadPreparedBaseline", Script);
        Assert.Contains("isPrepared and hadPreparedBaseline and not wasPrepared", Script);
    }

    [Fact]
    public void PreparedSpell_HasPresentationOnlyWorldspaceCastAffordanceBackedByExactAction()
    {
        Assert.Contains("function BridgeRenderPreparedSpellPresentations", Script);
        Assert.Contains("function BridgeCastPreparedSpellTile", Script);
        Assert.Contains("tostring(action.castMode or \"\") == \"prepare\"", Script);
        Assert.Contains("BridgeSubmitChoice(decision.decisionId, action.actionId, \"prepared_spell_tile\")", Script);
        Assert.Contains("preparedSpellControlGuids", Script);
        Assert.Contains("Prepared Spell", Script);
        Assert.Contains("BridgeClearPreparedSpellControls", Script);
        Assert.Contains("local renderedActionId = action.actionId", Script);
        Assert.Contains("control.setVar(\"bridgeActionId\", renderedActionId)", Script);
    }

    [Fact]
    public void PreparedDesignation_RemainsSeparateFromKeywordState()
    {
        var designationStart = Script.IndexOf("function BridgeSetPreparedDesignationPresentation", StringComparison.Ordinal);
        var designationEnd = Script.IndexOf("function BridgeSetPrototypeDesignationPresentation", designationStart, StringComparison.Ordinal);
        var designation = Script[designationStart..designationEnd];
        Assert.DoesNotContain("BridgeSetCardKeyword", designation);
        Assert.Contains("cardDesignationsByInstanceId", Script);
        Assert.Contains("preparedDesignationStateByInstanceId", Script);
    }
}
