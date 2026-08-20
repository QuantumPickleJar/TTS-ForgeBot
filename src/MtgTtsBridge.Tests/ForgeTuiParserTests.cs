using MtgTtsBridge.Forge;

namespace MtgTtsBridge.Tests;

public sealed class ForgeTuiParserTests
{
    [Fact]
    public void StructuredCardIdInHeadlessMenu_BindsActionToSessionReplaceableIdentity()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append("""
            What would you like to do?
              0. Pass priority (do nothing)
              1. Play land: Mountain [id=42]
            Enter choice (0-1):
            """);

        var action = Assert.Single(result.ParsedDecision!.Decision.Actions, item => item.Type == "play_land");
        Assert.Equal("Mountain", action.CardIdentity);
        Assert.Equal("forge-object:42", action.CardInstanceId);
        Assert.DoesNotContain("[id=", action.DisplayName);
    }

    [Fact]
    public void InitialDecision_ParsesIncrementalTuiOutputAndMapsInputs()
    {
        var transcript = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "forge-tui-initial-menu.txt"));
        var parser = new ForgeTuiParser();

        var firstChunk = parser.Append(transcript[..80]);
        var result = parser.Append(transcript[80..]);

        Assert.Null(firstChunk.ParsedDecision);
        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision);
        Assert.Equal("main_priority", decision.Decision.Kind);
        Assert.Equal(new[] { "Pass priority (do nothing)", "Play land: Mountain", "Play land: Rockface Village" }, decision.Decision.Actions.Select(action => action.DisplayName));
        Assert.Equal("pass_yield", decision.Decision.Actions[0].Type);
        Assert.Equal("Rockface Village", decision.Decision.Actions[2].CardIdentity);
        Assert.Equal("2", decision.Inputs[decision.Decision.Actions[2].ActionId]);
    }

    [Fact]
    public void SubsequentRealDecision_ParsesCastActionAndCardIdentity()
    {
        var transcript = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "forge-tui-subsequent-menu.txt"));
        var parser = new ForgeTuiParser();

        var result = parser.Append(transcript);

        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision);
        Assert.Equal("Cast creature: Hired Claw (1/2) - {R}", decision.Decision.Actions[1].DisplayName);
        Assert.Equal("Hired Claw", decision.Decision.Actions[1].CardIdentity);
        Assert.Equal("1", decision.Inputs[decision.Decision.Actions[1].ActionId]);
    }

    [Fact]
    public void TargetMenu_BecomesSeparateDecision()
    {
        var seats = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["Player 1"] = "forge-player-1",
            ["AI-monored"] = "forge-player-2",
        };
        var parser = new ForgeTuiParser(seats);
        var result = parser.Append("=== Choose Target for Burst Lightning ===\nSelect a target:\n  0. Player 1 (Life: 20)\n  1. AI-monored (Life: 20)\n  2. Hired Claw (1/2) [AI-monored]\nEnter choice (0-2, or ?): ");

        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision);
        Assert.Equal("target_selection", decision.Decision.Kind);
        Assert.Equal("player", decision.Decision.Actions[0].TargetKind);
        Assert.Equal("forge-player-1", decision.Decision.Actions[0].TargetSeatId);
        Assert.Null(decision.Decision.Actions[0].CardIdentity);
        Assert.Equal("forge-player-2", decision.Decision.Actions[1].TargetSeatId);
        Assert.Equal("card", decision.Decision.Actions[2].TargetKind);
        Assert.Equal("Hired Claw", decision.Decision.Actions[2].CardIdentity);
        Assert.Equal("2", decision.Inputs[decision.Decision.Actions[2].ActionId]);
    }

    [Fact]
    public void RealBlockerMenu_BecomesTypedDecisionWithCardIdentity()
    {
        var transcript = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "forge-tui-blocker-menu.txt"));
        var parser = new ForgeTuiParser();

        var result = parser.Append(transcript);

        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision);
        Assert.Equal("blocker_selection", decision.Decision.Kind);
        Assert.Equal("finish_blocking", decision.Decision.Actions[0].Type);
        Assert.Equal("choose_blocker", decision.Decision.Actions[1].Type);
        Assert.Equal("Hired Claw", decision.Decision.Actions[1].CardIdentity);
        Assert.Equal("1", decision.Inputs[decision.Decision.Actions[1].ActionId]);
    }

    [Fact]
    public void SequentialMenus_HaveStableIncreasingDecisionIds()
    {
        var parser = new ForgeTuiParser();
        var first = parser.Append("What would you like to do?\n  0. Pass priority (do nothing)\nEnter choice (0-0): ");
        var second = parser.Append(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "forge-tui-blocker-menu.txt")));

        Assert.Equal("forge-tui-1", first.ParsedDecision!.Decision.DecisionId);
        Assert.Equal("forge-tui-2", second.ParsedDecision!.Decision.DecisionId);
        Assert.Equal("forge-tui-2-choice-1", second.ParsedDecision.Decision.Actions[1].ActionId);
    }

    [Fact]
    public void UnknownNumericPrompt_IsPreservedAsUnsupported()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append("Unexpected controller output\nEnter choice (0-1, or ?): ");

        Assert.Equal("unsupported_numeric_prompt", result.UnsupportedPrompt?.Code);
        Assert.Contains("Unexpected controller output", result.UnsupportedPrompt?.Context);
    }

    [Fact]
    public void Reset_RestartsDecisionIdentitySequence()
    {
        var parser = new ForgeTuiParser();
        var first = parser.Append("What would you like to do?\n  0. Pass priority (do nothing)\nEnter choice (0-0, or ?): ");
        parser.Reset();
        var second = parser.Append("What would you like to do?\n  0. Pass priority (do nothing)\nEnter choice (0-0, or ?): ");

        Assert.Equal("forge-tui-1", first.ParsedDecision!.Decision.DecisionId);
        Assert.Equal("forge-tui-1", second.ParsedDecision!.Decision.DecisionId);
    }
}
