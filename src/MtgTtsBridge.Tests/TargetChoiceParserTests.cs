using MtgTtsBridge.Forge;
using Xunit;

namespace MtgTtsBridge.Tests;

public sealed class TargetChoiceParserTests
{
    [Fact]
    public void CardTarget_IsAnImmediateForgeChoiceRatherThanACollectionConfirmation()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append("""
            Choose a target for Lightning Strike:
              0. Grizzly Bears [id=42]
            Enter choice (0-0):
            """);

        var target = Assert.Single(Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision.Actions,
            action => action.Type == "choose_target");
        Assert.Equal("choose_target", target.Type);
        Assert.False(target.RequiresSelection);
        var cancel = Assert.Single(Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision.Actions,
            action => action.Type == "cancel_cast");
        Assert.Equal("q", result.ParsedDecision.Inputs[cancel.ActionId]);
    }
}
