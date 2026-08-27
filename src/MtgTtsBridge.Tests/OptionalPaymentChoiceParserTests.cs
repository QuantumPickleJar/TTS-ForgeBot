using MtgTtsBridge.Forge;
using Xunit;

namespace MtgTtsBridge.Tests;

public sealed class OptionalPaymentChoiceParserTests
{
    [Fact]
    public void StructuredOptionalPayment_IsPresentedAsAForgeToggleMenuWithDone()
    {
        var parser = new ForgeTuiParser();

        var result = parser.Append("""
            Choose optional costs for Rockfall Vale
            [kind=payment_option min=0 max=1 selected=0 ordered=false]
              0. Done
              1. Pay {2} life so Rockfall Vale enters untapped
            Enter choice (0-1):
            """);

        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision;
        Assert.Equal("payment_option", decision.Kind);
        Assert.True(decision.ConfirmRequired);
        Assert.Equal(0, decision.MinSelections);
        Assert.Equal(1, decision.MaxSelections);
        Assert.Contains(decision.Actions, action => action.Type == "choose_none");
        Assert.Contains(decision.Actions, action => action.Type == "choose_option"
            && action.DisplayName.StartsWith("Pay {2} life", StringComparison.Ordinal));
    }
}
