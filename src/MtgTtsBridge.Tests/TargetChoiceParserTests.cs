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

    [Fact]
    public void PlayerTarget_UsingForgeEnterTargetPrompt_IsParsedAndSubmitsExactInput()
    {
        var parser = new ForgeTuiParser(new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["Player 1"] = "forge-player-1",
            ["AI-blue"] = "forge-player-2",
        });
        var result = parser.Append("""
            === Choose Target for Thought Scour ===
            Select a target:
              0. Player 1 (Life: 20)
              1. AI-blue (Life: 20)
            Enter target (0-1, or q to cancel):
            """);

        var parsed = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision);
        var target = Assert.Single(parsed.Decision.Actions,
            action => action.TargetKind == "player" && action.TargetSeatId == "forge-player-2");

        Assert.Equal("target_selection", parsed.Decision.Kind);
        Assert.Equal("choose_target", target.Type);
        Assert.False(parsed.Decision.RequiresConfirmation);
        Assert.Equal("1", parsed.Inputs[target.ActionId]);
    }
}
