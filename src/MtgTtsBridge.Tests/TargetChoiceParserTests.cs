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

        var target = Assert.Single(Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision.Actions);
        Assert.Equal("choose_target", target.Type);
        Assert.False(target.RequiresSelection);
    }
}
