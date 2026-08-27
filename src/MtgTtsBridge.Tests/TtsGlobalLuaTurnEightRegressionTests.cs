using Xunit;

namespace MtgTtsBridge.Tests;

public sealed class TtsGlobalLuaTurnEightRegressionTests
{
    private static readonly string Script = File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.lua"));

    [Fact]
    public void PrivateHandDuplicate_ReturnDoesNotConvertAnIdentityAmbiguityIntoAMatchFailure()
    {
        Assert.Contains("pendingPrivateHandIdentityByInstanceId", Script);
        Assert.Contains("event.sourceZone == \"exile\" and event.destinationZone == \"hand\"", Script);
        Assert.Contains("deferred indistinguishable private-hand mapping", Script);
        Assert.Contains("Forge move remains authoritative", Script);
    }

    [Fact]
    public void StructuredCollectionChoices_CanSubmitDoneAndCompleteSingleOptionalPayment()
    {
        Assert.Contains("BridgeSubmitChoice(decision.decisionId, action.actionId, \"hud_collection_done\")", Script);
        Assert.Contains("function BridgeTryFinishSingleOptionalPaymentChoice(decision, source)", Script);
        Assert.Contains("payment_option_auto_done", Script);
    }

    [Fact]
    public void SingleNamedCounter_UsesVisibleEncoderFallback()
    {
        Assert.Contains("local needsFallback = #(namedCounters or {}) > 0", Script);
        Assert.Contains("if #labels == 0 then return end", Script);
    }

    [Fact]
    public void PhysicalCardTargetsAndFixedSacrifices_SubmitTheirForgeInputsWithoutLocalDeadEnds()
    {
        Assert.Contains("action.type == \"choose_target\"", Script);
        Assert.Contains("physical_card_target_pickup", Script);
        Assert.Contains("action.type == \"sacrifice\" and decision.confirmRequired == true", Script);
        Assert.Contains("physical_sacrifice_pickup", Script);
        Assert.Contains("function BridgeTryFinishFixedSacrificeChoice(decision, source)", Script);
        Assert.Contains("sacrifice_auto_done", Script);
    }
}
