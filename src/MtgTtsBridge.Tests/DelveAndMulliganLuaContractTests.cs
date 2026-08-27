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
}
