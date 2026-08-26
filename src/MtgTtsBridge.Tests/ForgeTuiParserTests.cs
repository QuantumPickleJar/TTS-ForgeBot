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
    public void DuplicateNamedCards_RetainSeparateForgeInstanceActions()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append("""
            What would you like to do?
              0. Pass priority (do nothing)
              1. Play land: Mountain [id=42]
              2. Play land: Mountain [id=43]
            Enter choice (0-2):
            """);

        var mountains = result.ParsedDecision!.Decision.Actions.Where(action => action.Type == "play_land").ToArray();
        Assert.Equal(2, mountains.Length);
        Assert.Equal(new[] { "forge-object:42", "forge-object:43" }, mountains.Select(action => action.CardInstanceId));
        Assert.NotEqual(mountains[0].ActionId, mountains[1].ActionId);
        Assert.Equal("1", result.ParsedDecision.Inputs[mountains[0].ActionId]);
        Assert.Equal("2", result.ParsedDecision.Inputs[mountains[1].ActionId]);
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
        Assert.Equal("pass_priority", decision.Decision.Actions[0].Type);
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
    public void AlternateTargetHeader_ParsesCardAndPlayerTargets()
    {
        var seats = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["Player 1"] = "forge-player-1",
            ["AI-monored"] = "forge-player-2",
        };
        var parser = new ForgeTuiParser(seats);
        var result = parser.Append("Choose a target for Burst Lightning:\n  0) Player 1 (Life: 20)\n  1) AI-monored (Life: 20)\n  2) Hired Claw (1/2) [AI-monored]\nEnter choice (0-2): ");

        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision);
        Assert.Equal("target_selection", decision.Decision.Kind);
        Assert.Equal("forge-player-1", decision.Decision.Actions[0].TargetSeatId);
        Assert.Equal("forge-player-2", decision.Decision.Actions[1].TargetSeatId);
        Assert.Equal("card", decision.Decision.Actions[2].TargetKind);
        Assert.Equal("Hired Claw", decision.Decision.Actions[2].CardIdentity);
    }

    [Fact]
    public void TargetHeaderWithoutNumericPrompt_DoesNotFailParser()
    {
        var parser = new ForgeTuiParser();
        var partial = parser.Append("=== Choose Target for Burst Lightning ===\nSelect a target:\n");
        Assert.Null(partial.ParsedDecision);
        Assert.Null(partial.ErrorCode);
        Assert.Null(partial.UnsupportedPrompt);

        var completed = parser.Append("  0. Player 1 (Life: 20)\n  1. AI-monored (Life: 20)\nEnter choice (0-1): ");
        var decision = Assert.IsType<ForgeTuiDecision>(completed.ParsedDecision);
        Assert.Equal("target_selection", decision.Decision.Kind);
        Assert.Equal(2, decision.Decision.Actions.Count);
    }

    [Fact]
    public void GenericChooseOneHeaderStreamedBeforeOptions_WaitsForFollowupChunk()
    {
        var parser = new ForgeTuiParser();
        var first = parser.Append("Choose one:\n");
        Assert.Null(first.ParsedDecision);
        Assert.Null(first.ErrorCode);
        Assert.Null(first.UnsupportedPrompt);

        var second = parser.Append("  0) Emberheart Challenger — Prowess trigger\n  1) Hired Claw — Prowess trigger\nSelect an option: ");
        var decision = Assert.IsType<ForgeTuiDecision>(second.ParsedDecision);
        Assert.Equal("generic_numeric_selection", decision.Decision.Kind);
        Assert.Equal(2, decision.Decision.Actions.Count);
        Assert.Equal("0", decision.Inputs[decision.Decision.Actions[0].ActionId]);
        Assert.Equal("1", decision.Inputs[decision.Decision.Actions[1].ActionId]);
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
        Assert.Equal("0", decision.Inputs[decision.Decision.Actions[0].ActionId]);
        Assert.Equal("choose_blocker", decision.Decision.Actions[1].Type);
        Assert.Equal("Hired Claw", decision.Decision.Actions[1].CardIdentity);
        Assert.Equal("1", decision.Inputs[decision.Decision.Actions[1].ActionId]);
        Assert.Equal(0, decision.Decision.MinSelections);
        Assert.Equal(1, decision.Decision.MaxSelections);
    }

    [Fact]
    public void BlockAssignmentPrompt_ParsesDoneActionWhenNoMenuOptionsExist()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append("""
            Declare blockers (or enter 'done' when finished):
            Format: <blocker_num> blocks <attacker_num>
            Example: 0 blocks 1
            Enter block assignment (or 'done'):
            """);

        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision);
        var action = Assert.Single(decision.Decision.Actions);
        Assert.Equal("finish_blocking", action.Type);
        Assert.Equal("done", decision.Inputs[action.ActionId]);
        Assert.Equal("blocker_selection", decision.Decision.Kind);
    }

    [Fact]
    public void ManaAbility_IsTypedAndKeepsExactSourceIdentity()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append("What would you like to do?\n  0. Pass priority (do nothing)\n  1. Rockface Village [id=77]: {T}: Add {R}.\nEnter choice (0-1): ");

        var action = Assert.Single(result.ParsedDecision!.Decision.Actions, item => item.Type == "activate_mana");
        Assert.Equal("Rockface Village", action.CardIdentity);
        Assert.Equal("forge-object:77", action.CardInstanceId);
        Assert.Equal("1", result.ParsedDecision.Inputs[action.ActionId]);
    }

    [Fact]
    public void AttackerMenu_UsesExplicitFinishAndExactCardInstance()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append("Declare attackers:\n  0. No further attackers\n  1. Hired Claw [id=91] (1/2)\n  2. Emberheart Challenger [id=92] (2/2)\nEnter choice (0-2): ");

        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision;
        Assert.Equal("attacker_selection", decision.Kind);
        Assert.Equal("finish_attacking", decision.Actions[0].Type);
        Assert.Equal("choose_attacker", decision.Actions[1].Type);
        Assert.Equal("forge-object:91", decision.Actions[1].CardInstanceId);
        Assert.Equal(0, decision.MinSelections);
        Assert.True(decision.AllowsCancel);
    }

    [Fact]
    public void UppercaseAttackerHeader_IsClassifiedAsAttackerSelection()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append("=== DECLARE ATTACKERS ===\n  0. No further attackers\n  1. Hired Claw [id=91] (1/2)\n  2. Emberheart Challenger [id=92] (2/2)\nEnter choice (0-2): ");

        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision;
        Assert.Equal("attacker_selection", decision.Kind);
        Assert.Contains(decision.Actions, action => action.Type == "finish_attacking");
        Assert.Contains(decision.Actions, action => action.Type == "choose_attacker" && action.CardIdentity == "Hired Claw");
        Assert.Contains(decision.Actions, action => action.Type == "choose_attacker" && action.CardIdentity == "Emberheart Challenger");
    }

    [Fact]
    public void GenericChooseOnePrompt_StillParsesNumericMenu()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append("Choose one:\n  0. Pass\n  1. Razorkin Needlehead [id=17] (1/1)\n  2. Hired Claw [id=18] (1/2)\nSelect an option: ");

        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision;
        Assert.Equal("generic_numeric_selection", decision.Kind);
        Assert.Equal("Razorkin Needlehead", decision.Actions[1].CardIdentity);
        Assert.Equal("1", result.ParsedDecision.Inputs[decision.Actions[1].ActionId]);
    }

    [Fact]
    public void UppercaseDefenderHeader_IsClassifiedAsTargetableDefenderSelection()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append("=== CHOOSE DEFENDER FOR EMBERHEART CHALLENGER ===\n  0. Player 1 (Life: 20)\nEnter choice (0-0): ");

        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision;
        Assert.Equal("defender_selection", decision.Kind);
        var action = Assert.Single(decision.Actions);
        Assert.Equal("choose_target", action.Type);
        Assert.Equal("Player 1 (Life: 20)", action.DisplayName);
        Assert.Equal(1, decision.MinSelections);
    }

    [Fact]
    public void DefenderSelection_MapsPlayerTargetsWhenSeatLookupIsProvided()
    {
        var parser = new ForgeTuiParser(new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["Player 1"] = "forge-player-1"
        });
        var result = parser.Append("Choose defender for Emberheart Challenger:\n  0. Player 1 (Life: 20)\nEnter choice (0-0): ");

        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision;
        var action = Assert.Single(decision.Actions);
        Assert.Equal("choose_target", action.Type);
        Assert.Equal("player", action.TargetKind);
        Assert.Equal("forge-player-1", action.TargetSeatId);
    }

    [Fact]
    public void AlternateAttackerHeader_IsClassifiedAsAttackerSelection()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append("=== SELECT ATTACKERS ===\n  0. No further attackers\n  1. Hired Claw [id=91] (1/2)\nEnter choice (0-1): ");

        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision;
        Assert.Equal("attacker_selection", decision.Kind);
        Assert.Contains(decision.Actions, action => action.Type == "finish_attacking");
        Assert.Contains(decision.Actions, action => action.Type == "choose_attacker" && action.CardIdentity == "Hired Claw");
    }

    [Fact]
    public void ChainedCombatMenu_ReportsAlreadyDeclaredAttackerAsSelected()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append("=== SELECT ATTACKERS ===\n  0. No further attackers\n  1. Hired Claw [id=91] (1/2) [ATTACKING]\n  2. Emberheart Challenger [id=92] (2/2)\nEnter choice (0-2): ");

        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision;
        var selected = Assert.Single(decision.Actions, action => action.CardIdentity == "Hired Claw");
        Assert.True(selected.IsSelected);
        Assert.Equal(1, decision.SelectedCount);
        Assert.False(Assert.Single(decision.Actions, action => action.CardIdentity == "Emberheart Challenger").IsSelected);
    }

    [Fact]
    public void GenericSacrificeChoice_PreservesCardinalityZeroDoneAndExactDuplicateIds()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append("=== FORGE CHOICE ===\nChoose permanents to sacrifice\n[kind=sacrifice min=0 max=2 selected=1 ordered=false]\n  0. Done\n  1. Mountain [id=41] [SELECTED]\n  2. Mountain [id=72]\nEnter choice (0-2): ");

        var parsed = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision);
        var decision = parsed.Decision;
        Assert.Equal("sacrifice", decision.Kind);
        Assert.Equal(0, decision.MinSelections);
        Assert.Equal(2, decision.MaxSelections);
        Assert.True(decision.CanChooseZero);
        Assert.True(decision.ConfirmRequired);
        Assert.Equal(1, decision.SelectedCount);
        Assert.False(decision.RequiresConfirmation);
        Assert.Equal("0", parsed.Inputs[Assert.Single(decision.Actions, action => action.Type == "choose_none").ActionId]);
        var mountains = decision.Actions.Where(action => action.Type == "sacrifice").ToArray();
        Assert.Equal(["forge-object:41", "forge-object:72"], mountains.Select(action => action.CardInstanceId));
        Assert.True(mountains[0].IsSelected);
        Assert.False(mountains[1].IsSelected);
    }

    [Theory]
    [InlineData("mode_selection", "choose_mode")]
    [InlineData("numeric_selection", "choose_number")]
    [InlineData("yes_no", "choose_option")]
    public void GenericTextDecisions_ProduceTypedOptionActions(string kind, string expectedType)
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append($"=== FORGE CHOICE ===\nA Forge prompt\n[kind={kind} min=1 max=1 selected=0 ordered=false]\n  0. First option\n  1. Second option\nEnter choice (0-1): ");

        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision;
        Assert.Equal(kind, decision.Kind);
        Assert.All(decision.Actions, action => Assert.Equal(expectedType, action.Type));
    }

    [Fact]
    public void GenericPlayerSelection_MapsSeatWithoutTreatingTtsColorAsRulesIdentity()
    {
        var parser = new ForgeTuiParser(new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["Player 1"] = "forge-player-1",
            ["AI-monored"] = "forge-player-2",
        });
        var result = parser.Append("=== FORGE CHOICE ===\nChoose a player\n[kind=player_selection min=1 max=1 selected=0 ordered=false]\n  0. Player 1 (Life: 20)\n  1. AI-monored (Life: 18)\nEnter choice (0-1): ");

        var actions = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision.Actions;
        Assert.Equal(["forge-player-1", "forge-player-2"], actions.Select(action => action.TargetSeatId));
        Assert.All(actions, action =>
        {
            Assert.Equal("choose_target", action.Type);
            Assert.Equal("player", action.TargetKind);
        });
    }

    [Fact]
    public void GenericPlayerSelection_MapsDeckNamedAiWithoutADeckSpecificConfigurationEntry()
    {
        var parser = new ForgeTuiParser(new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["Player 1"] = "forge-player-1",
        });
        var result = parser.Append("=== FORGE CHOICE ===\nChoose a player\n[kind=player_selection min=1 max=1 selected=0 ordered=false]\n  0. Player 1 (Life: 20)\n  1. AI-Legacy-Burn (Life: 20)\nEnter choice (0-1): ");

        var actions = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision.Actions;
        Assert.Equal(["forge-player-1", "forge-player-2"], actions.Select(action => action.TargetSeatId));
    }

    [Fact]
    public void OneAtATimeAttackerPrompt_ParsesDoneWithoutMenuOptions()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append("Choose attackers one at a time (or enter 'done' when finished):\nEnter attacker number (or 'done'): ");

        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision;
        Assert.Equal("attacker_selection", decision.Kind);
        var action = Assert.Single(decision.Actions);
        Assert.Equal("finish_attacking", action.Type);
        Assert.Equal("done", result.ParsedDecision!.Inputs[action.ActionId]);
        Assert.Equal(0, decision.MinSelections);
        Assert.Equal(1, decision.MaxSelections);
    }

    [Fact]
    public void OneAtATimeBlockerPrompt_ParsesDoneWithoutMenuOptions()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append("Choose blockers one at a time (or enter 'done' when finished):\nEnter blocker number (or 'done'): ");

        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision;
        Assert.Equal("blocker_selection", decision.Kind);
        var action = Assert.Single(decision.Actions);
        Assert.Equal("finish_blocking", action.Type);
        Assert.Equal("done", result.ParsedDecision!.Inputs[action.ActionId]);
        Assert.Equal(0, decision.MinSelections);
        Assert.Equal(1, decision.MaxSelections);
    }

    [Fact]
    public void NumericCombatMenus_UseForgePresentedIndicesRatherThanCardIds()
    {
        var parser = new ForgeTuiParser();
        var attackers = parser.Append("Declare attackers:\n  0. No further attackers\n  1. Hired Claw [id=91] (1/2)\nEnter choice (0-1): ");
        var attackerDecision = Assert.IsType<ForgeTuiDecision>(attackers.ParsedDecision);
        var attacker = Assert.Single(attackerDecision.Decision.Actions, action => action.Type == "choose_attacker");
        Assert.Equal("1", attackerDecision.Inputs[attacker.ActionId]);
        Assert.NotEqual("91", attackerDecision.Inputs[attacker.ActionId]);

        var blockers = parser.Append("Who should block this attacker?\n  0. No further blockers\n  1. Hired Claw [id=91] (1/2)\nEnter choice (0-1): ");
        var blockerDecision = Assert.IsType<ForgeTuiDecision>(blockers.ParsedDecision);
        var blocker = Assert.Single(blockerDecision.Decision.Actions, action => action.Type == "choose_blocker");
        Assert.Equal("1", blockerDecision.Inputs[blocker.ActionId]);
        Assert.NotEqual("91", blockerDecision.Inputs[blocker.ActionId]);

        var finish = Assert.Single(blockerDecision.Decision.Actions, action => action.Type == "finish_blocking");
        Assert.Equal("0", blockerDecision.Inputs[finish.ActionId]);
    }

    [Fact]
    public void NumericCombatChoice_DoesNotIncludeItsBridgeActionIdInForgeInput()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append("Declare attackers:\n  0. No further attackers\n  1. Hired Claw [id=91] (1/2)\nEnter choice (0-1): ");
        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision);
        var action = Assert.Single(decision.Decision.Actions, item => item.Type == "choose_attacker");

        Assert.Equal("1", decision.Inputs[action.ActionId]);
        Assert.DoesNotContain("forge-tui", decision.Inputs[action.ActionId], StringComparison.Ordinal);
    }

    [Fact]
    public void DuplicateMountains_KeepDistinctInstanceIds()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append("What would you like to do?\n  0. Pass priority (do nothing)\n  1. Play land: Mountain [id=41]\n  2. Play land: Mountain [id=72]\nEnter choice (0-2): ");

        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision;
        var mountains = decision.Actions.Where(action => action.Type == "play_land" && action.CardIdentity == "Mountain").ToArray();
        Assert.Equal(2, mountains.Length);
        Assert.Equal("forge-object:41", mountains[0].CardInstanceId);
        Assert.Equal("forge-object:72", mountains[1].CardInstanceId);
        Assert.NotEqual(mountains[0].CardInstanceId, mountains[1].CardInstanceId);
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
