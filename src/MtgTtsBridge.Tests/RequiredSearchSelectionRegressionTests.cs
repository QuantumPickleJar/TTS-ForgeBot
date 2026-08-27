using Xunit;

namespace MtgTtsBridge.Tests;

public sealed class RequiredSearchSelectionRegressionTests
{
    private static readonly string Script = File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.lua"));

    [Fact]
    public void StructuredSearch_UsesForgeToggleThenCompletesFixedRequiredSelection()
    {
        Assert.Contains("function BridgeIsStructuredForgeToggleChoice(decision)", Script);
        Assert.Contains("kind == \"search_selection\"", Script);
        Assert.Contains("BridgeSubmitChoice(decision.decisionId, action.actionId, \"hud_structured_toggle\")", Script);
        Assert.Contains("function BridgeTryFinishFixedRequiredSelection(decision, source)", Script);
        Assert.Contains("fixed_selection_auto_done", Script);
    }

    [Fact]
    public void StructuredDone_RejectsZeroWhenForgeRequiresASelection()
    {
        Assert.Contains("function BridgeCanSubmitStructuredDone(decision, source)", Script);
        Assert.Contains("selected < minimum or selected > maximum", Script);
        Assert.Contains("Forge requires %d to %d selections before Done", Script);
        Assert.Contains("blocked invalid structured Done", Script);
        Assert.Contains("physical_option_done", Script);
    }
}
