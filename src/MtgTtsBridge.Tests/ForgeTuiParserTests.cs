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
        Assert.Equal("play_land", action.ActionKind);
        Assert.Equal("forge-object:42", action.SourceCardInstanceId);
        Assert.Equal("Mountain", action.SourceCardName);
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
        Assert.NotEqual(mountains[0].SourceCardInstanceId, mountains[1].SourceCardInstanceId);
    }

    [Fact]
    public void ProliferateMixedEntities_UsesExactCardInstancesAndPlayerSeats()
    {
        var parser = new ForgeTuiParser(new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["Player 1"] = "forge-player-1",
            ["AI"] = "forge-player-2",
        });
        var result = parser.Append("""
            === FORGE CHOICE ===
            Choose proliferate targets
            [kind=entity_selection selectionKind=proliferate min=0 max=3 selected=0 ordered=false]
              0. Done
              1. Player 1 (Life: 20) [bridge entityKind=player seatId=forge-player-1]
              2. Walking Ballista [id=42] [bridge entityKind=permanent cardInstanceId=42 sourceZone=battlefield]
              3. AI (Life: 20) [bridge entityKind=player seatId=forge-player-2]
            Enter choice (0-3):
            """);

        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision);
        Assert.Equal("entity_selection", decision.Decision.Kind);
        Assert.Equal("proliferate", decision.Decision.SelectionKind);
        Assert.True(decision.Decision.ConfirmRequired);
        var player = decision.Decision.Actions.Single(action => action.EntitySeatId == "forge-player-1");
        Assert.Equal("player", player.EntityKind);
        Assert.Equal("player", player.TargetKind);
        Assert.Equal("forge-player-1", player.TargetSeatId);
        Assert.Null(player.CardInstanceId);
        var permanent = decision.Decision.Actions.Single(action => action.EntityKind == "permanent");
        Assert.Equal("forge-object:42", permanent.CardInstanceId);
        Assert.Equal("battlefield", permanent.SourceZone);
        Assert.Equal("choose_entity", permanent.Type);
    }

    [Fact]
    public void PrototypeCastProvenance_IsTypedAndDistinctFromNormalCast()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append("""
            What would you like to do?
              0. Pass priority (do nothing)
              1. Cast creature: Blitz Automaton (3/3) - {1}{B}{B} [id=7] [bridge sourceZone=hand actionKind=cast_spell abilityKind=spell castMode=prototype costKind=alternative displayManaCost={1}{B}{B} prototypePower=3 prototypeToughness=3]
              2. Cast creature: Blitz Automaton (6/6) - {7} [id=7] [bridge sourceZone=hand actionKind=cast_spell abilityKind=spell castMode=normal costKind=printed]
            Enter choice (0-2):
            """);

        var actions = result.ParsedDecision!.Decision.Actions.Where(action => action.CardIdentity == "Blitz Automaton").ToArray();
        Assert.Equal(2, actions.Length);
        Assert.Equal("prototype", actions[0].CastMode);
        Assert.Equal("normal", actions[1].CastMode);
        Assert.Equal("{1}{B}{B}", actions[0].DisplayManaCost);
        Assert.NotEqual(actions[0].ActionId, actions[1].ActionId);
        Assert.Equal("forge-object:7", actions[0].CardInstanceId);
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
    public void EnchantmentCastAction_PreservesExactCardIdentity()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append("""
            What would you like to do?
              0. Pass priority (do nothing)
              1. Cast enchantment: Caretaker's Talent - {2}{W} [id=61]
            Enter choice (0-1):
            """);

        var action = Assert.Single(result.ParsedDecision!.Decision.Actions, item => item.Type == "cast_spell");
        Assert.Equal("Caretaker's Talent", action.CardIdentity);
        Assert.Equal("forge-object:61", action.CardInstanceId);
    }

    [Fact]
    public void InstantCastAction_FromMainPriorityMenuIsPhysicalAndUiAddressable()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append(
            "What would you like to do?\n" +
            "  0. Pass priority (do nothing)\n" +
            "  1. Cast instant: Lightning Bolt [id=73] - {R} [bridge sourceZone=hand actionKind=cast_spell abilityKind=spell castMode=normal costKind=printed]\n" +
            "Enter choice (0-1): ");

        var action = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision.Actions[1];
        Assert.Equal("cast_spell", action.Type);
        Assert.Equal("cast_spell", action.ActionKind);
        Assert.Equal("hand", action.SourceZone);
        Assert.Equal("forge-object:73", action.CardInstanceId);
        Assert.Equal("Lightning Bolt", action.CardIdentity);
        Assert.Equal("1", Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Inputs[action.ActionId]);
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
    public void TargetMenu_OptionsPrintedAfterPrompt_AreBufferedAndParsed()
    {
        var parser = new ForgeTuiParser(new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["Player 1"] = "forge-player-1",
            ["AI-tts-ai"] = "forge-player-2",
        });

        var first = parser.Append(
            "=== Choose Target for Swords to Plowshares ===\n" +
            "Select a target:\n" +
            "Enter target (0-0, or q to cancel):\n");
        Assert.Null(first.ParsedDecision);
        Assert.Null(first.ErrorCode);

        var second = parser.Append("  0. Glissa Sunslayer [id=76] (3/3) [AI-tts-ai]\n");
        var decision = Assert.IsType<ForgeTuiDecision>(second.ParsedDecision);
        var target = Assert.Single(decision.Decision.Actions, action => action.Type == "choose_target");
        Assert.Equal("Glissa Sunslayer", target.CardIdentity);
        Assert.Equal("forge-object:76", target.CardInstanceId);
        Assert.Equal("0", decision.Inputs[target.ActionId]);
        var cancel = Assert.Single(decision.Decision.Actions, action => action.Type == "cancel_cast");
        Assert.Equal("q", decision.Inputs[cancel.ActionId]);
    }

    [Fact]
    public void PlayerTarget_WithForgeDisplayAnnotation_RemainsTypedTarget()
    {
        var parser = new ForgeTuiParser(new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["Player 1"] = "forge-player-1",
            ["AI-blue"] = "forge-player-2",
        });

        var result = parser.Append("Choose target for Thought Scour:\n"
            + "  0. Player 1 (Life: 20) [id=1]\n"
            + "  1. AI-blue (Life: 20) [controller=AI]\n"
            + "Enter choice (0-1): ");

        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision;
        var target = Assert.Single(decision.Actions,
            action => action.TargetKind == "player" && action.TargetSeatId == "forge-player-2");
        Assert.Equal("choose_target", target.Type);
    }

    [Fact]
    public void TargetMenu_OptionSplitAcrossChunks_WaitsForCompleteLine()
    {
        var parser = new ForgeTuiParser();
        var first = parser.Append(
            "Choose target for Swords to Plowshares:\n" +
            "Enter target (0-0, or q to cancel):\n" +
            "  0. Glissa Sunslayer [id=76]");
        Assert.Null(first.ParsedDecision);
        Assert.Null(first.ErrorCode);

        var second = parser.Append(" (3/3)\n");
        var decision = Assert.IsType<ForgeTuiDecision>(second.ParsedDecision);
        Assert.Contains(decision.Decision.Actions, action => action.CardIdentity == "Glissa Sunslayer");
    }

    [Fact]
    public void TargetMenu_TrailingNumericTerminator_DoesNotLeakIntoNextDecision()
    {
        var parser = new ForgeTuiParser();
        var first = parser.Append(
            "Choose target for Murderous Cut:\n" +
            "  0. Player 1 (Life: 20)\n" +
            "Enter choice (0-0): 0");
        var decision = Assert.IsType<ForgeTuiDecision>(first.ParsedDecision);
        Assert.Equal("target_selection", decision.Decision.Kind);
        Assert.Equal("0", decision.Inputs[decision.Decision.Actions[0].ActionId]);

        var second = parser.Append(
            "What would you like to do?\n" +
            "  0. Pass priority (do nothing)\n" +
            "Enter choice (0-0): ");
        var nextDecision = Assert.IsType<ForgeTuiDecision>(second.ParsedDecision);
        Assert.Equal("main_priority", nextDecision.Decision.Kind);
        Assert.Equal("0", nextDecision.Inputs[nextDecision.Decision.Actions[0].ActionId]);
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
        Assert.Equal(3, decision.Decision.Actions.Count);
        var cancel = Assert.Single(decision.Decision.Actions, action => action.Type == "cancel_cast");
        Assert.Equal("q", decision.Inputs[cancel.ActionId]);
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
        var action = Assert.Single(decision.Actions, candidate => candidate.Type == "choose_target");
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
        var action = Assert.Single(decision.Actions, candidate => candidate.Type == "choose_target");
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

    [Fact]
    public void LegacyDiscardPromptRequiresExplicitConfirmation()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append(
            " to discard:\n  0. Cloudspire Captain\n  1. Great Gilded Boat\nEnter choice (0-1): ");

        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision;
        Assert.Equal("card_selection", decision.Kind);
        Assert.True(decision.RequiresConfirmation);
        Assert.True(decision.ConfirmRequired);
        Assert.True(decision.AllowsCancel);
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
    public void ModeSelectionIsAForgeOwnedCollectionWithStableSelectionAndDone()
    {
        var parser = new ForgeTuiParser();
        var first = parser.Append(
            "=== FORGE CHOICE ===\nChoose mode for See Double\n" +
            "[kind=mode_selection min=2 max=2 selected=0 ordered=true]\n" +
            "  0. Done\n  1. Copy spell\n  2. Copy permanent\n" +
            "Enter choice (0-2): ");
        var firstDecision = Assert.IsType<ForgeTuiDecision>(first.ParsedDecision).Decision;
        Assert.True(firstDecision.ConfirmRequired);
        Assert.Equal("choose_none", firstDecision.Actions[0].Type);

        var second = parser.Append(
            "=== FORGE CHOICE ===\nChoose mode for See Double\n" +
            "[kind=mode_selection min=2 max=2 selected=1 ordered=true]\n" +
            "  0. Done\n  1. Copy spell [SELECTED]\n  2. Copy permanent\n" +
            "Enter choice (0-2): ");
        var secondDecision = Assert.IsType<ForgeTuiDecision>(second.ParsedDecision).Decision;
        Assert.Equal(firstDecision.DecisionId, secondDecision.DecisionId);
        Assert.Equal(1, secondDecision.SelectedCount);
        Assert.True(secondDecision.Actions.Single(action => action.Type == "choose_mode" && action.IsSelected).IsSelected);
        Assert.Contains(secondDecision.Actions, action => action.Type == "choose_none");
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
        var targets = actions.Where(action => action.Type == "choose_target").ToArray();
        Assert.Equal(["forge-player-1", "forge-player-2"], targets.Select(action => action.TargetSeatId));
        Assert.All(targets, action =>
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
        Assert.Equal(["forge-player-1", "forge-player-2"], actions
            .Where(action => action.Type == "choose_target")
            .Select(action => action.TargetSeatId));
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

    [Fact]
    public void CreatureTypePrompt_UsesEnumeratedForgeActionsWithoutRestrictingTheChoices()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append(
            "=== FORGE CHOICE ===\n" +
            "Choose creature\n" +
            "[kind=creature_type_selection min=1 max=1 selected=0 ordered=false]\n" +
            "  0. Elf\n" +
            "  1. Rat\n" +
            "  2. Completely New Creature Type\n" +
            "Enter choice (0-2): ");

        var parsed = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision);
        Assert.Equal("creature_type_selection", parsed.Decision.Kind);
        Assert.Equal(3, parsed.Decision.Actions.Count);
        Assert.Equal("Elf", parsed.Decision.Actions[0].DisplayName);
        Assert.Equal("choose_creature_type", parsed.Decision.Actions[0].Type);
        Assert.Equal("Rat", parsed.Decision.Actions[1].DisplayName);
        Assert.Equal("Completely New Creature Type", parsed.Decision.Actions[2].DisplayName);
        Assert.Equal("2", parsed.Inputs[parsed.Decision.Actions[2].ActionId]);
    }

    [Fact]
    public void TypedProvenance_ProvidesSourceZoneWithoutParsingDisplayText()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append(
            "=== YOUR TURN ===\n" +
            "What would you like to do?\n" +
            "  0. Pass priority (do nothing)\n" +
            "  1. Faithless Looting — cast this from somewhere [id=91] [bridge sourceZone=graveyard actionKind=cast_spell abilityKind=spell castMode=flashback costKind=alternative]\n" +
            "Enter choice (0-1): ");

        var action = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision.Actions[1];
        Assert.Equal("graveyard", action.SourceZone);
        Assert.Equal("cast_spell", action.ActionKind);
        Assert.Equal("spell", action.AbilityKind);
        Assert.Equal("flashback", action.CastMode);
        Assert.Equal("alternative", action.CostKind);
        Assert.DoesNotContain("sourceZone=", action.DisplayName);
    }

    [Fact]
    public void DiscardDecision_UsesStructuredCauseAndExactSourceIdentity()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append(
            "=== FORGE CHOICE ===\n" +
            "Choose cards to discard\n" +
            "[bridge decisionCause=spell_or_ability decisionReason=spell_or_ability sourceCardId=81 sourceCardName=Liliana of the Veil]\n" +
            "[kind=discard min=1 max=1 selected=0 ordered=false]\n" +
            "  0. Done\n  1. Island [id=41]\nEnter choice (0-1): ");

        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision;
        Assert.Equal("discard", decision.Kind);
        Assert.Equal("spell_or_ability", decision.DecisionCauseKind);
        Assert.Equal("forge-object:81", decision.SourceCardInstanceId);
        Assert.Equal("Liliana of the Veil", decision.SourceCardName);
        Assert.Equal("discard_card", Assert.Single(decision.Actions, action => action.CardInstanceId == "forge-object:41").Type);
    }

    [Fact]
    public void CleanupDiscardDecision_HasNoInventedSourceCard()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append(
            "=== FORGE CHOICE ===\n" +
            "Discard to maximum hand size\n" +
            "[bridge decisionCause=cleanup_hand_size decisionReason=cleanup_hand_size]\n" +
            "[kind=discard min=2 max=2 selected=0 ordered=false]\n" +
            "  0. Done\n  1. Island [id=41]\n  2. Mountain [id=42]\nEnter choice (0-2): ");

        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision;
        Assert.Equal("cleanup_hand_size", decision.DecisionCauseKind);
        Assert.Null(decision.SourceCardInstanceId);
        Assert.Null(decision.SourceCardName);
        Assert.Equal(2, decision.MinSelections);
    }

    [Fact]
    public void DelveDecision_UsesTypedCostMetadataAndExactGraveyardCards()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append(
            "=== FORGE CHOICE ===\n" +
            "Choose graveyard cards to exile for Delve\n" +
            "[kind=cost_selection costKind=delve sourceZone=graveyard min=0 max=4 selected=0 ordered=false]\n" +
            "  0. Done\n  1. Consider [id=41]\n  2. Consider [id=42]\nEnter choice (0-2): ");

        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision;
        Assert.Equal("cost_selection", decision.Kind);
        Assert.Equal("delve", decision.CostKind);
        Assert.Equal("graveyard", decision.CandidateSourceZone);
        Assert.Equal(0, decision.MinSelections);
        Assert.Equal(4, decision.MaxSelections);
        Assert.Equal("forge-object:41", decision.Actions[1].CardInstanceId);
        Assert.Equal("forge-object:42", decision.Actions[2].CardInstanceId);
    }

    [Fact]
    public void CrewDecision_UsesTypedCostMetadataAndExactBattlefieldCandidates()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append(
            "=== FORGE CHOICE ===\n" +
            "Tap any number of creatures you control with total power 3 or greater\n" +
            "[kind=cost_selection costKind=crew sourceZone=battlefield requiredTotalPower=3 selectedTotalPower=2 min=0 max=3 selected=1 ordered=false]\n" +
            "  0. Done\n" +
            "  1. Grizzly Bears [id=41] [bridge entityKind=permanent cardInstanceId=41 sourceZone=battlefield]\n" +
            "  2. Grizzly Bears [id=42] [bridge entityKind=permanent cardInstanceId=42 sourceZone=battlefield]\n" +
            "Enter choice (0-2): ");

        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision;
        Assert.Equal("cost_selection", decision.Kind);
        Assert.Equal("crew", decision.CostKind);
        Assert.Equal("battlefield", decision.CandidateSourceZone);
        Assert.Equal(0, decision.MinSelections);
        Assert.Equal(3, decision.MaxSelections);
        Assert.Equal(3, decision.RequiredTotalPower);
        Assert.Equal(2, decision.SelectedTotalPower);
        Assert.Equal("choose_option", decision.Actions[1].Type);
        Assert.Equal("forge-object:41", decision.Actions[1].CardInstanceId);
        Assert.Equal("battlefield", decision.Actions[1].SourceZone);
        Assert.Equal("forge-object:42", decision.Actions[2].CardInstanceId);
        Assert.Equal("Grizzly Bears", decision.Actions[1].CardIdentity);
        Assert.Equal("Grizzly Bears", decision.Actions[2].CardIdentity);
    }

    [Fact]
    public void EntityProvenance_DoesNotChangeDiscardActionContract()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append(
            "=== FORGE CHOICE ===\nChoose cards to discard\n" +
            "[kind=discard min=1 max=1 selected=0 ordered=false]\n" +
            "  0. Done\n  1. Island [id=41] [bridge entityKind=card cardInstanceId=41 sourceZone=hand]\n" +
            "Enter choice (0-1): ");

        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision;
        var action = Assert.Single(decision.Actions, candidate => candidate.CardInstanceId == "forge-object:41");
        Assert.Equal("discard_card", action.Type);
        Assert.Equal("hand", action.SourceZone);
    }

    [Fact]
    public void EntityProvenance_MapsOnlyGenericEntitySelectionToChooseEntity()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append(
            "=== FORGE CHOICE ===\nProliferate\n" +
            "[kind=entity_selection selectionKind=proliferate min=0 max=2 selected=0 ordered=false]\n" +
            "  0. Done\n  1. Ballista [id=41] [bridge entityKind=permanent cardInstanceId=41 sourceZone=battlefield]\n" +
            "  2. You [bridge entityKind=player seatId=forge-player-1 sourceZone=command]\n" +
            "Enter choice (0-2): ");

        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision;
        Assert.All(decision.Actions.Where(candidate => candidate.CardInstanceId != null || candidate.EntitySeatId != null),
            action => Assert.Equal("choose_entity", action.Type));
        Assert.Equal("forge-player-1", decision.Actions[2].EntitySeatId);
    }

    [Fact]
    public void CollectionRedraws_RetainOneLogicalDecisionIdentity()
    {
        var parser = new ForgeTuiParser();
        var first = parser.Append(
            "=== FORGE CHOICE ===\nChoose cards to discard\n" +
            "[kind=discard min=1 max=2 selected=0 ordered=false]\n" +
            "  0. Done\n  1. Island [id=41]\n  2. Mountain [id=42]\nEnter choice (0-2): ");
        var second = parser.Append(
            "=== FORGE CHOICE ===\nChoose cards to discard\n" +
            "[kind=discard min=1 max=2 selected=1 ordered=false]\n" +
            "  0. Done\n  1. Island [id=41] [SELECTED]\n  2. Mountain [id=42]\nEnter choice (0-2): ");

        var firstDecision = Assert.IsType<ForgeTuiDecision>(first.ParsedDecision).Decision;
        var secondDecision = Assert.IsType<ForgeTuiDecision>(second.ParsedDecision).Decision;
        Assert.Equal(firstDecision.DecisionId, secondDecision.DecisionId);
        Assert.Equal(firstDecision.Actions[1].ActionId, secondDecision.Actions[1].ActionId);
        Assert.Equal(1, secondDecision.SelectedCount);
        parser.CompleteCollectionDecision();
        var next = parser.Append(
            "=== FORGE CHOICE ===\nChoose cards to discard\n" +
            "[kind=discard min=1 max=1 selected=0 ordered=false]\n" +
            "  0. Done\n  1. Plains [id=43]\nEnter choice (0-1): ");
        Assert.NotEqual(firstDecision.DecisionId, Assert.IsType<ForgeTuiDecision>(next.ParsedDecision).Decision.DecisionId);
    }

    [Fact]
    public void MulliganKeepActions_AreTypedWithoutDisplayParsingInTheBridge()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append(
            "=== FORGE CHOICE ===\nOpening hand\n" +
            "[kind=mulligan mulliganStage=keep_or_mulligan min=1 max=1 selected=0 ordered=false]\n" +
            "  0. Keep\n  1. Mulligan\nEnter choice (0-1): ");
        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision;
        Assert.Equal("keep_hand", decision.Actions[0].Type);
        Assert.Equal("mulligan", decision.Actions[1].Type);
    }

    [Fact]
    public void MulliganDecisions_KeepNativeStagesAndExactBottomCardIdentity()
    {
        var parser = new ForgeTuiParser();
        var keep = parser.Append(
            "=== FORGE CHOICE ===\nOpening hand\n" +
            "[kind=mulligan mulliganStage=keep_or_mulligan min=1 max=1 selected=0 ordered=false]\n" +
            "  0. Keep\n  1. Mulligan\nEnter choice (0-1): ");

        var keepDecision = Assert.IsType<ForgeTuiDecision>(keep.ParsedDecision).Decision;
        Assert.Equal("mulligan", keepDecision.Kind);
        Assert.Equal("keep_or_mulligan", keepDecision.MulliganStage);
        Assert.False(keepDecision.ConfirmRequired);
        var keepParsed = Assert.IsType<ForgeTuiDecision>(keep.ParsedDecision);
        Assert.Equal("0", keepParsed.Inputs[keepDecision.Actions[0].ActionId]);
        Assert.Equal("1", keepParsed.Inputs[keepDecision.Actions[1].ActionId]);

        var bottom = parser.Append(
            "=== FORGE CHOICE ===\nChoose cards to put on the bottom of your library\n" +
            "[kind=mulligan mulliganStage=bottom_selection sourceZone=hand min=1 max=1 selected=0 ordered=false]\n" +
            "  0. Done\n  1. Island [id=51]\n  2. Island [id=52]\nEnter choice (0-2): ");

        var bottomDecision = Assert.IsType<ForgeTuiDecision>(bottom.ParsedDecision).Decision;
        Assert.Equal("bottom_selection", bottomDecision.MulliganStage);
        Assert.True(bottomDecision.ConfirmRequired);
        Assert.Equal("hand", bottomDecision.CandidateSourceZone);
        Assert.Equal("forge-object:51", bottomDecision.Actions[1].CardInstanceId);
        Assert.Equal("forge-object:52", bottomDecision.Actions[2].CardInstanceId);
    }

    [Fact]
    public void PreparedSpell_UsesExactVirtualSourceProvenanceWithoutNameMatching()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append(
            "What would you like to do?\n" +
            "  0. Pass priority (do nothing)\n" +
            "  1. Cast creature: Craft with Pride [id=91] (2/2) - {R} [bridge sourceZone=exile actionKind=cast_spell abilityKind=spell castMode=prepare costKind=prepare preparedSourceCardId=41]\n" +
            "Enter choice (0-1): ");

        var action = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision.Actions[1];
        Assert.Equal("prepare", action.CastMode);
        Assert.Equal("prepare", action.CostKind);
        Assert.Equal("forge-object:41", action.PreparedSourceCardInstanceId);
        Assert.StartsWith("PREPARED SPELL:", action.DisplayName, StringComparison.Ordinal);
    }

    [Fact]
    public void BlockerDecision_UsesProducerSuppliedExactAttackerContext()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append(
            "[bridge blockerForCardId=91 blockerForName=Ragavan, Nimble Pilferer]\n" +
            "Who should block this attacker?\n  0. No further blockers\n  1. Pilot [id=44] (1/1)\nEnter choice (0-1): ");

        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision;
        Assert.Equal("forge-object:91", decision.ContextCardInstanceId);
        Assert.Equal("Ragavan, Nimble Pilferer", decision.ContextCardName);
        Assert.Equal("forge-object:44", Assert.Single(decision.Actions, action => action.Type == "choose_blocker").CardInstanceId);
    }

    [Fact]
    public void UnearthProvenance_RemainsAtypedGraveyardActivatedAbility()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append(
            "=== YOUR TURN ===\n" +
            "What would you like to do?\n" +
            "  0. Pass priority (do nothing)\n" +
            "  1. Stitcher's Supplier — return this card [id=77] [bridge sourceZone=graveyard actionKind=activate_ability abilityKind=unearth castMode=normal costKind=printed]\n" +
            "Enter choice (0-1): ");

        var action = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision.Actions[1];
        Assert.Equal("activate_ability", action.ActionKind);
        Assert.Equal("unearth", action.AbilityKind);
        Assert.Equal("graveyard", action.SourceZone);
        Assert.Equal("forge-object:77", action.SourceCardInstanceId);
        Assert.DoesNotContain("Unearth", action.DisplayName, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void PaymentContextAndCostComponents_AreParsedFromBridgeRecords()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append(
            "=== FORGE CHOICE ===\n" +
            "Choose optional costs for Spell\n" +
            "[bridge paymentContextId=pctx-7 originActionId=forge-tui-4-choice-1 sourceCardId=42 sourceZone=graveyard actionKind=cast_spell castMode=flashback paymentStage=optional_cost]\n" +
            "[bridge costComponent paymentContextId=pctx-7 componentId=pctx-7-c0 kind=mana displayLabel=%7B2%7D%7BU%7D requiredValue=%7B2%7D%7BU%7D]\n" +
            "[bridge costComponent paymentContextId=pctx-7 componentId=pctx-7-c1 kind=exile displayLabel=Exile+cards+from+graveyard sourceZone=graveyard selectionKind=cards minSelections=0 maxSelections=3]\n" +
            "[kind=payment_option min=0 max=2 selected=0 ordered=false]\n" +
            "  0. Done\n  1. Kicker\nEnter choice (0-1): ");

        var decision = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision;
        var payment = Assert.IsType<MtgTtsBridge.Contracts.Actions.PaymentContextDto>(decision.PaymentContext);
        Assert.Equal("pctx-7", payment.PaymentContextId);
        Assert.Equal("forge-tui-4-choice-1", payment.OriginActionId);
        Assert.Equal("forge-object:42", payment.SourceCardInstanceId);
        Assert.Equal("graveyard", payment.SourceZone);
        Assert.Equal("cast_spell", payment.ActionKind);
        Assert.Equal("flashback", payment.CastMode);
        Assert.Equal(2, payment.CostComponents!.Count);
        Assert.Equal(["pctx-7-c0", "pctx-7-c1"], payment.CostComponents.Select(component => component.CostComponentId));
        Assert.Equal("{2}{U}", payment.CostComponents[0].DisplayLabel);
        Assert.Equal("Exile cards from graveyard", payment.CostComponents[1].DisplayLabel);
    }

    [Fact]
    public void ActionProvenance_PreservesPaymentContextFromBridgeSuffix()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append(
            "What would you like to do?\n" +
            "  0. Pass priority (do nothing)\n" +
            "  1. Cast instant: Think Twice [id=71] - {2}{U} [bridge sourceZone=graveyard actionKind=cast_spell abilityKind=spell castMode=flashback costKind=alternative displayManaCost={2}{U} paymentContextId=pctx-13]\n" +
            "Enter choice (0-1): ");

        var action = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision.Actions[1];
        Assert.Equal("pctx-13", action.Provenance?.PaymentContextId);
        Assert.Equal("flashback", action.Provenance?.CastMode);
    }

    [Fact]
    public void PaymentContext_SurvivesRedrawForSameCollectionTransaction()
    {
        var parser = new ForgeTuiParser();
        var first = parser.Append(
            "=== FORGE CHOICE ===\n" +
            "[bridge paymentContextId=pctx-9 originActionId=forge-tui-8-choice-1 sourceCardId=99 sourceZone=graveyard actionKind=cast_spell castMode=flashback paymentStage=nonmana_payment]\n" +
            "[bridge costComponent paymentContextId=pctx-9 componentId=pctx-9-c0 kind=exile displayLabel=Exile+for+Delve sourceZone=graveyard selectionKind=cards minSelections=0 maxSelections=2]\n" +
            "[kind=cost_selection costKind=delve sourceZone=graveyard min=0 max=2 selected=1 ordered=false]\n" +
            "  0. Done\n  1. Card A [id=1] [SELECTED]\n  2. Card B [id=2]\nEnter choice (0-2): ");

        var second = parser.Append(
            "=== FORGE CHOICE ===\n" +
            "[bridge paymentContextId=pctx-9 originActionId=forge-tui-8-choice-1 sourceCardId=99 sourceZone=graveyard actionKind=cast_spell castMode=flashback paymentStage=nonmana_payment]\n" +
            "[bridge costComponent paymentContextId=pctx-9 componentId=pctx-9-c0 kind=exile displayLabel=Exile+for+Delve sourceZone=graveyard selectionKind=cards minSelections=0 maxSelections=2]\n" +
            "[kind=cost_selection costKind=delve sourceZone=graveyard min=0 max=2 selected=2 ordered=false]\n" +
            "  0. Done\n  1. Card A [id=1] [SELECTED]\n  2. Card B [id=2] [SELECTED]\nEnter choice (0-2): ");

        var firstDecision = Assert.IsType<ForgeTuiDecision>(first.ParsedDecision).Decision;
        var secondDecision = Assert.IsType<ForgeTuiDecision>(second.ParsedDecision).Decision;
        Assert.Equal(firstDecision.DecisionId, secondDecision.DecisionId);
        Assert.Equal("pctx-9", firstDecision.PaymentContext?.PaymentContextId);
        Assert.Equal("pctx-9", secondDecision.PaymentContext?.PaymentContextId);
        Assert.Equal(["pctx-9-c0"], secondDecision.PaymentContext?.CostComponents?.Select(component => component.CostComponentId));
    }

    [Fact]
    public void IndependentPaymentTransactions_UseDistinctContextIds()
    {
        var parser = new ForgeTuiParser();
        var first = parser.Append(
            "=== FORGE CHOICE ===\n" +
            "[bridge paymentContextId=pctx-21 originActionId=forge-tui-11-choice-1 sourceCardId=11 sourceZone=hand actionKind=cast_spell castMode=normal paymentStage=optional_cost]\n" +
            "[kind=payment_option min=0 max=1 selected=0 ordered=false]\n" +
            "  0. Done\n  1. Kicker\nEnter choice (0-1): ");
        parser.CompleteCollectionDecision();
        var second = parser.Append(
            "=== FORGE CHOICE ===\n" +
            "[bridge paymentContextId=pctx-22 originActionId=forge-tui-12-choice-1 sourceCardId=12 sourceZone=hand actionKind=cast_spell castMode=normal paymentStage=optional_cost]\n" +
            "[kind=payment_option min=0 max=1 selected=0 ordered=false]\n" +
            "  0. Done\n  1. Kicker\nEnter choice (0-1): ");

        Assert.Equal("pctx-21", Assert.IsType<ForgeTuiDecision>(first.ParsedDecision).Decision.PaymentContext?.PaymentContextId);
        Assert.Equal("pctx-22", Assert.IsType<ForgeTuiDecision>(second.ParsedDecision).Decision.PaymentContext?.PaymentContextId);
    }

    [Fact]
    public void LibrarySourceCastAction_PreservesExactForgeProvenance()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append(
            "What would you like to do?\n" +
            "  0. Pass priority (do nothing)\n" +
            "  1. Cast creature: Youthful Valkyrie [id=321] - {1}{W} [bridge sourceZone=library actionKind=cast_spell abilityKind=spell castMode=normal costKind=printed paymentContextId=pctx-31]\n" +
            "Enter choice (0-1): ");

        var action = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision.Actions[1];
        Assert.Equal("cast_spell", action.ActionKind);
        Assert.Equal("library", action.SourceZone);
        Assert.Equal("forge-object:321", action.SourceCardInstanceId);
        Assert.Equal("pctx-31", action.Provenance?.PaymentContextId);
        Assert.False(action.IsPresentationAuthorized);
        Assert.False(action.Provenance?.IsPresentationAuthorized);
    }

    [Fact]
    public void ForgeAuthorizedTopLibraryCast_IsSafeToPresentWithoutPhysicalExtraction()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append(
            "What would you like to do?\n" +
            "  0. Pass priority (do nothing)\n" +
            "  1. Cast creature: Youthful Valkyrie [id=321] - {1}{W} [bridge sourceZone=library visibility=authorized actionKind=cast_spell abilityKind=spell castMode=normal costKind=printed]\n" +
            "Enter choice (0-1): ");

        var action = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision.Actions[1];
        Assert.True(action.IsPresentationAuthorized);
        Assert.True(action.Provenance?.IsPresentationAuthorized);
        Assert.Equal("forge-object:321", action.CardInstanceId);
    }

    [Fact]
    public void NonCastableTopLibraryCard_DoesNotEmitLibraryCastAction()
    {
        var parser = new ForgeTuiParser();
        var result = parser.Append(
            "What would you like to do?\n" +
            "  0. Pass priority (do nothing)\n" +
            "  1. Play land: Plains [id=51]\n" +
            "Enter choice (0-1): ");

        var actions = Assert.IsType<ForgeTuiDecision>(result.ParsedDecision).Decision.Actions;
        Assert.DoesNotContain(actions, action => action.ActionKind == "cast_spell" && action.SourceZone == "library");
    }
}
