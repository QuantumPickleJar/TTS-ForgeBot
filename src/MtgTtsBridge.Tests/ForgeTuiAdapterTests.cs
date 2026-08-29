using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using System.Reflection;
using MtgTtsBridge.Contracts.Actions;
using MtgTtsBridge.Contracts.State;
using MtgTtsBridge.Forge;

namespace MtgTtsBridge.Tests;

public sealed class ForgeTuiAdapterTests
{
    [Fact]
    public async Task SeedTemplate_IsRenderedAsANewConcreteSeedForEachForgeSession()
    {
        await using var adapter = new ForgeTuiAdapter(
            Options.Create(new ForgeTuiOptions
            {
                Executable = "unused",
                Arguments = "tui --seed {seed}",
                WorkingDirectory = Environment.CurrentDirectory,
            }),
            NullLogger<ForgeTuiAdapter>.Instance);
        var render = typeof(ForgeTuiAdapter).GetMethod("RenderArguments", BindingFlags.Instance | BindingFlags.NonPublic);
        Assert.NotNull(render);

        var first = Assert.IsType<string>(render.Invoke(adapter, null));
        var second = Assert.IsType<string>(render.Invoke(adapter, null));

        Assert.Matches(@"^tui --seed [1-9]\d*$", first);
        Assert.Matches(@"^tui --seed [1-9]\d*$", second);
        Assert.NotEqual(first, second);
    }

    [Fact]
    public async Task HumanControllerDiagnostics_AreBoundedAndCountInheritedKinds()
    {
        var command = Path.Combine(Environment.SystemDirectory, "cmd.exe");
        if (!File.Exists(command)) return;
        var script = Path.Combine(Path.GetTempPath(), $"forge-tui-diagnostics-{Guid.NewGuid():N}.cmd");
        await File.WriteAllTextAsync(script, """
            @echo off
            echo [TUI-INHERITED] kind=choose_color turn=2 phase=Main
            echo [TUI-DIAG priority] turn=2 phase=Main active=Player 1 priority=Player 1 isActivePlayersTurn=true hasPriority=true totalActions=1 uniqueActions=1
            echo What would you like to do?
            echo   0. Pass priority (do nothing)
            <nul set /p "=Enter choice (0-0): "
            set /p choice=
            """);

        try
        {
            await using var adapter = new ForgeTuiAdapter(
                Options.Create(new ForgeTuiOptions
                {
                    Executable = command,
                    Arguments = $"/d /q /c \"{script}\"",
                    WorkingDirectory = Path.GetDirectoryName(script)!,
                    StartupTimeoutSeconds = 5,
                }),
                NullLogger<ForgeTuiAdapter>.Instance);

            var state = await adapter.StartSessionAsync(CancellationToken.None);
            Assert.Equal(1, state.Diagnostic!.InheritedHumanDecisionKinds!["choose_color"]);
            Assert.Contains(state.Diagnostic.RecentControllerDiagnostics!, line => line.StartsWith("[TUI-DIAG priority]"));

            var decision = state.CurrentDecision;
            Assert.NotNull(decision);
            Assert.Equal(2, decision.TurnNumber);
            Assert.Equal("Main", decision.PhaseName);
            Assert.Equal("forge-player-1", decision.ActiveSeatId);

            var events = await adapter.GetEventsAsync(0, CancellationToken.None);
            Assert.Contains(events.Events, item => item.Kind == "turn_changed" && item.TurnNumber == 2);
            Assert.Contains(events.Events, item => item.Kind == "phase_changed" && item.Phase == "Main");
            Assert.Contains(events.Events, item => item.Kind == "priority_changed" && item.PrioritySeatId == "forge-player-1");
        }
        finally
        {
            File.Delete(script);
        }
    }

    [Fact]
    public async Task ActiveTurnAndPriorityRemainIndependentWhenTheyDiffer()
    {
        var command = Path.Combine(Environment.SystemDirectory, "cmd.exe");
        if (!File.Exists(command)) return;
        var script = Path.Combine(Path.GetTempPath(), $"forge-tui-priority-semantics-{Guid.NewGuid():N}.cmd");
        await File.WriteAllTextAsync(script, """
            @echo off
            echo [TUI-DIAG priority] turn=4 phase=Main 1 active=AI-monored priority=Player 1 isActivePlayersTurn=false hasPriority=true totalActions=1 uniqueActions=1
            echo What would you like to do?
            echo   0. Pass priority (do nothing)
            <nul set /p "=Enter choice (0-0): "
            set /p choice=
            """);

        try
        {
            await using var adapter = new ForgeTuiAdapter(
                Options.Create(new ForgeTuiOptions
                {
                    Executable = command,
                    Arguments = $"/d /q /c \"{script}\"",
                    WorkingDirectory = Path.GetDirectoryName(script)!,
                    StartupTimeoutSeconds = 5,
                }),
                NullLogger<ForgeTuiAdapter>.Instance);

            var state = await adapter.StartSessionAsync(CancellationToken.None);
            Assert.Equal("forge-player-2", state.CurrentDecision!.ActiveSeatId);
            Assert.Equal("forge-player-1", state.CurrentDecision.PrioritySeatId);
            Assert.Equal(4, state.CurrentDecision.TurnNumber);
            Assert.Equal("Main 1", state.CurrentDecision.PhaseName);

            var events = await adapter.GetEventsAsync(0, CancellationToken.None);
            Assert.Contains(events.Events, item => item.Kind == "turn_changed" && item.ActiveSeatId == "forge-player-2");
            Assert.Contains(events.Events, item => item.Kind == "phase_changed" && item.ActiveSeatId == "forge-player-2");
            Assert.Contains(events.Events, item => item.Kind == "priority_changed"
                && item.PrioritySeatId == "forge-player-1"
                && item.ActiveSeatId == "forge-player-2");
        }
        finally
        {
            File.Delete(script);
        }
    }

    [Fact]
    public async Task StructuredStateDoesNotSuppressUnreplacedTurnAndPhaseEvents()
    {
        var command = Path.Combine(Environment.SystemDirectory, "cmd.exe");
        if (!File.Exists(command)) return;
        var script = Path.Combine(Path.GetTempPath(), $"forge-tui-raw-phase-events-{Guid.NewGuid():N}.cmd");
        await File.WriteAllTextAsync(script, """
            @echo off
            echo @@FORGE_BRIDGE_STATE@@{"version":1,"type":"snapshot","sequence":1,"reason":"baseline","players":[],"stack":[]}
            echo +++ Turn: Turn 3 (Player 1)
            echo +++ Phase: Player 1's Main phase, precombat
            echo What would you like to do?
            echo   0. Pass priority (do nothing)
            <nul set /p "=Enter choice (0-0): "
            set /p choice=
            """);

        try
        {
            await using var adapter = new ForgeTuiAdapter(
                Options.Create(new ForgeTuiOptions
                {
                    Executable = command,
                    Arguments = $"/d /q /c \"{script}\"",
                    WorkingDirectory = Path.GetDirectoryName(script)!,
                    StartupTimeoutSeconds = 5,
                }),
                NullLogger<ForgeTuiAdapter>.Instance);

            await adapter.StartSessionAsync(CancellationToken.None);
            var events = await adapter.GetEventsAsync(0, CancellationToken.None);
            Assert.Contains(events.Events, item => item.Kind == "turn_changed" && item.TurnNumber == 3);
            Assert.Contains(events.Events, item => item.Kind == "phase_changed" && item.Phase == "Main phase, precombat");
        }
        finally
        {
            File.Delete(script);
        }
    }

    [Fact]
    public async Task ExecutableNameOnPath_IsAcceptedForForgeLaunch()
    {
        var script = Path.Combine(Path.GetTempPath(), $"forge-tui-path-{Guid.NewGuid():N}.cmd");
        await File.WriteAllTextAsync(script, """
            @echo off
            echo What would you like to do?
            echo   0. Pass priority (do nothing)
            <nul set /p "=Enter choice (0-0): "
            set /p choice=
            """);

        try
        {
            await using var adapter = new ForgeTuiAdapter(
                Options.Create(new ForgeTuiOptions
                {
                    Executable = "cmd.exe",
                    Arguments = $"/d /q /c \"{script}\"",
                    WorkingDirectory = Path.GetDirectoryName(script)!,
                    StartupTimeoutSeconds = 5,
                }),
                NullLogger<ForgeTuiAdapter>.Instance);

            var state = await adapter.StartSessionAsync(CancellationToken.None);
            Assert.Equal("awaiting_human_decision", state.State);
            Assert.NotNull(state.CurrentDecision);
        }
        finally
        {
            File.Delete(script);
        }
    }

    [Fact]
    public async Task OptionalTrigger_IsExposedAsStructuredYesNoDecision()
    {
        var command = Path.Combine(Environment.SystemDirectory, "cmd.exe");
        if (!File.Exists(command)) return;
        var script = Path.Combine(Path.GetTempPath(), $"forge-tui-optional-trigger-{Guid.NewGuid():N}.cmd");
        await File.WriteAllTextAsync(script, """
            @echo off
            echo === FORGE CHOICE ===
            echo Use optional trigger from Soul Warden?
            echo Ability: You gain 1 life.
            echo [kind=yes_no min=1 max=1 selected=0 ordered=false]
            echo   0. No
            echo   1. Yes
            <nul set /p "=Enter choice (0-1): "
            set /p choice=
            if not "%choice%"=="1" exit /b 31
            echo What would you like to do?
            echo   0. Pass priority (do nothing)
            <nul set /p "=Enter choice (0-0): "
            set /p choice=
            """);

        try
        {
            await using var adapter = new ForgeTuiAdapter(
                Options.Create(new ForgeTuiOptions
                {
                    Executable = command,
                    Arguments = $"/d /q /c \"{script}\"",
                    WorkingDirectory = Path.GetDirectoryName(script)!,
                    StartupTimeoutSeconds = 5,
                    DecisionTimeoutSeconds = 5,
                }), NullLogger<ForgeTuiAdapter>.Instance);

            var initial = await adapter.StartSessionAsync(CancellationToken.None);
            var decision = Assert.IsType<DecisionDto>(initial.CurrentDecision);
            Assert.Equal("yes_no", decision.Kind);
            Assert.Contains(decision.Actions, action => action.DisplayName == "Yes");

            var yes = Assert.Single(decision.Actions, action => action.DisplayName == "Yes");
            var response = await adapter.SubmitChoiceAsync(
                new ChoiceRequestDto(decision.DecisionId, yes.ActionId) { SessionId = initial.SessionId },
                CancellationToken.None);
            Assert.True(response.Accepted);
        }
        finally
        {
            File.Delete(script);
        }
    }

    [Fact]
    public async Task ProcessExitDuringStartup_MarksAdapterAsFailed()
    {
        var command = Path.Combine(Environment.SystemDirectory, "cmd.exe");
        if (!File.Exists(command)) return;

        await using var adapter = new ForgeTuiAdapter(
            Options.Create(new ForgeTuiOptions
            {
                Executable = command,
                Arguments = "/c exit 7",
                WorkingDirectory = Environment.CurrentDirectory,
                StartupTimeoutSeconds = 5,
            }),
            NullLogger<ForgeTuiAdapter>.Instance);

        await Assert.ThrowsAsync<InvalidOperationException>(() => adapter.StartSessionAsync(CancellationToken.None));

        var state = await adapter.GetStateAsync(CancellationToken.None);
        Assert.Equal("failed", state.State);
        Assert.Null(state.CurrentDecision);
    }

    [Fact]
    public async Task Choice_UsesMappedNumericInputAndTreatsSameResolvedChoiceAsIdempotent()
    {
        var command = Path.Combine(Environment.SystemDirectory, "cmd.exe");
        if (!File.Exists(command)) return;

        var script = Path.Combine(Path.GetTempPath(), $"forge-tui-adapter-{Guid.NewGuid():N}.cmd");
        await File.WriteAllTextAsync(script, """
            @echo off
            echo What would you like to do?
            echo   0. Pass priority (do nothing)
            echo   2. Play land: Mountain
            <nul set /p "=Enter choice (0-2): "
            set /p choice=
            if not "%choice%"=="2" exit /b 9
            echo What would you like to do?
            echo   0. Pass priority (do nothing)
            <nul set /p "=Enter choice (0-0): "
            set /p choice=
            """);

        try
        {
            await using var adapter = new ForgeTuiAdapter(
                Options.Create(new ForgeTuiOptions
                {
                    Executable = command,
                    Arguments = $"/d /q /c \"{script}\"",
                    WorkingDirectory = Path.GetDirectoryName(script)!,
                    StartupTimeoutSeconds = 5,
                    DecisionTimeoutSeconds = 5,
                }),
                NullLogger<ForgeTuiAdapter>.Instance);

            var initial = await adapter.StartSessionAsync(CancellationToken.None);
            var decision = Assert.IsType<MtgTtsBridge.Contracts.State.DecisionDto>(initial.CurrentDecision);
            var mountain = Assert.Single(decision.Actions, action => action.CardIdentity == "Mountain");

            var accepted = await adapter.SubmitChoiceAsync(
                new ChoiceRequestDto(decision.DecisionId, mountain.ActionId) { SessionId = initial.SessionId }, CancellationToken.None);
            Assert.True(accepted.Accepted);
            Assert.Equal("forge-tui-2", accepted.State.CurrentDecision?.DecisionId);

            var duplicate = await adapter.SubmitChoiceAsync(
                new ChoiceRequestDto(decision.DecisionId, mountain.ActionId) { SessionId = initial.SessionId }, CancellationToken.None);
            Assert.True(duplicate.Accepted);

            var conflicting = await adapter.SubmitChoiceAsync(
                new ChoiceRequestDto(decision.DecisionId, "forge-tui-1-choice-0") { SessionId = initial.SessionId }, CancellationToken.None);
            Assert.False(conflicting.Accepted);
            Assert.Equal("decision_already_resolved", conflicting.ErrorCode);
        }
        finally
        {
            File.Delete(script);
        }
    }

    [Fact]
    public async Task CollectionChoice_RedrawnMenuAcceptsCardThenDoneUnderOneDecision()
    {
        var command = Path.Combine(Environment.SystemDirectory, "cmd.exe");
        if (!File.Exists(command)) return;

        var script = Path.Combine(Path.GetTempPath(), $"forge-tui-collection-{Guid.NewGuid():N}.cmd");
        var inputLog = Path.Combine(Path.GetTempPath(), $"forge-tui-collection-{Guid.NewGuid():N}.log");
        await File.WriteAllTextAsync(script, """
            @echo off
            echo === FORGE CHOICE ===
            echo Choose cards to discard
            echo [bridge decisionCause=cleanup_hand_size decisionReason=cleanup_hand_size]
            echo [kind=discard min=1 max=1 selected=0 ordered=false]
            echo   0. Done
            echo   4. Island [id=41]
            <nul set /p "=Enter choice (0-4): "
            set /p choice=
            >>"__INPUT_LOG__" echo(%choice%
            if not "%choice%"=="4" exit /b 41
            echo === FORGE CHOICE ===
            echo Choose cards to discard
            echo [kind=discard min=1 max=1 selected=1 ordered=false]
            echo   0. Done
            echo   4. Island [id=41] [SELECTED]
            <nul set /p "=Enter choice (0-4): "
            set /p choice=
            >>"__INPUT_LOG__" echo(%choice%
            if not "%choice%"=="0" exit /b 42
            echo What would you like to do?
            echo   0. Pass priority (do nothing)
            <nul set /p "=Enter choice (0-0): "
            set /p choice=
            """.Replace("__INPUT_LOG__", inputLog));

        try
        {
            await using var adapter = new ForgeTuiAdapter(
                Options.Create(new ForgeTuiOptions
                {
                    Executable = command,
                    Arguments = $"/d /q /c \"{script}\"",
                    WorkingDirectory = Path.GetDirectoryName(script)!,
                    StartupTimeoutSeconds = 5,
                    DecisionTimeoutSeconds = 5,
                }), NullLogger<ForgeTuiAdapter>.Instance);

            var initial = await adapter.StartSessionAsync(CancellationToken.None);
            var firstDecision = Assert.IsType<MtgTtsBridge.Contracts.State.DecisionDto>(initial.CurrentDecision);
            Assert.Equal("cleanup_hand_size", firstDecision.DecisionCauseKind);
            var card = Assert.Single(firstDecision.Actions, action => action.Type == "discard_card");
            Assert.Equal("forge-tui-1-choice-4", card.ActionId);
            var toggled = await adapter.SubmitChoiceAsync(
                new ChoiceRequestDto(firstDecision.DecisionId, card.ActionId) { SessionId = initial.SessionId }, CancellationToken.None);
            Assert.True(toggled.Accepted);
            var redraw = Assert.IsType<MtgTtsBridge.Contracts.State.DecisionDto>(toggled.State.CurrentDecision);
            Assert.Equal(firstDecision.DecisionId, redraw.DecisionId);
            var done = Assert.Single(redraw.Actions, action => action.Type == "choose_none");
            var completed = await adapter.SubmitChoiceAsync(
                new ChoiceRequestDto(redraw.DecisionId, done.ActionId) { SessionId = initial.SessionId }, CancellationToken.None);
            Assert.True(completed.Accepted);
            Assert.Equal("forge-tui-2", completed.State.CurrentDecision?.DecisionId);
            Assert.Equal(["4", "0"], (await File.ReadAllLinesAsync(inputLog)).Select(line => line.Trim()).ToArray());
        }
        finally
        {
            File.Delete(script);
            File.Delete(inputLog);
        }
    }

    [Fact]
    public async Task MultiCardDiscardWaitsForAllForgeRedrawsBeforeDone()
    {
        var command = Path.Combine(Environment.SystemDirectory, "cmd.exe");
        if (!File.Exists(command)) return;

        var script = Path.Combine(Path.GetTempPath(), $"forge-tui-discard-two-{Guid.NewGuid():N}.cmd");
        var inputLog = Path.Combine(Path.GetTempPath(), $"forge-tui-discard-two-{Guid.NewGuid():N}.log");
        await File.WriteAllTextAsync(script, """
            @echo off
            echo === FORGE CHOICE ===
            echo Choose cards to discard
            echo [bridge decisionCause=spell_or_ability decisionReason=spell_or_ability sourceCardId=81 sourceCardName=Mind Rot]
            echo [kind=discard min=2 max=2 selected=0 ordered=false]
            echo   0. Done
            echo   4. Island [id=41]
            echo   5. Mountain [id=42]
            <nul set /p "=Enter choice (0-5): "
            set /p choice=
            >>"__INPUT_LOG__" echo(%choice%
            if not "%choice%"=="4" exit /b 41
            echo === FORGE CHOICE ===
            echo Choose cards to discard
            echo [kind=discard min=2 max=2 selected=1 ordered=false]
            echo   0. Done
            echo   4. Island [id=41] [SELECTED]
            echo   5. Mountain [id=42]
            <nul set /p "=Enter choice (0-5): "
            set /p choice=
            >>"__INPUT_LOG__" echo(%choice%
            if not "%choice%"=="5" exit /b 42
            echo === FORGE CHOICE ===
            echo Choose cards to discard
            echo [kind=discard min=2 max=2 selected=2 ordered=false]
            echo   0. Done
            echo   4. Island [id=41] [SELECTED]
            echo   5. Mountain [id=42] [SELECTED]
            <nul set /p "=Enter choice (0-5): "
            set /p choice=
            >>"__INPUT_LOG__" echo(%choice%
            if not "%choice%"=="0" exit /b 43
            echo What would you like to do?
            echo   0. Pass priority (do nothing)
            <nul set /p "=Enter choice (0-0): "
            set /p choice=
            """.Replace("__INPUT_LOG__", inputLog));

        try
        {
            await using var adapter = new ForgeTuiAdapter(
                Options.Create(new ForgeTuiOptions
                {
                    Executable = command,
                    Arguments = $"/d /q /c \"{script}\"",
                    WorkingDirectory = Path.GetDirectoryName(script)!,
                    StartupTimeoutSeconds = 5,
                    DecisionTimeoutSeconds = 5,
                }), NullLogger<ForgeTuiAdapter>.Instance);

            var initial = await adapter.StartSessionAsync(CancellationToken.None);
            var firstDecision = Assert.IsType<DecisionDto>(initial.CurrentDecision);
            Assert.Equal("spell_or_ability", firstDecision.DecisionCauseKind);
            Assert.Equal(2, firstDecision.MinSelections);
            var first = Assert.Single(firstDecision.Actions, action => action.CardInstanceId?.EndsWith(":41", StringComparison.Ordinal) == true);
            var second = Assert.Single(firstDecision.Actions, action => action.CardInstanceId?.EndsWith(":42", StringComparison.Ordinal) == true);

            var firstResponse = await adapter.SubmitChoiceAsync(
                new ChoiceRequestDto(firstDecision.DecisionId, first.ActionId) { SessionId = initial.SessionId },
                CancellationToken.None);
            var oneSelected = Assert.IsType<DecisionDto>(firstResponse.State.CurrentDecision);
            Assert.Equal(firstDecision.DecisionId, oneSelected.DecisionId);
            Assert.Equal(1, oneSelected.SelectedCount);
            Assert.True(oneSelected.Actions.Single(action => action.CardInstanceId?.EndsWith(":41", StringComparison.Ordinal) == true).IsSelected);

            var secondResponse = await adapter.SubmitChoiceAsync(
                new ChoiceRequestDto(oneSelected.DecisionId, second.ActionId) { SessionId = initial.SessionId },
                CancellationToken.None);
            var twoSelected = Assert.IsType<DecisionDto>(secondResponse.State.CurrentDecision);
            Assert.Equal(2, twoSelected.SelectedCount);
            Assert.True(twoSelected.Actions.Single(action => action.CardInstanceId?.EndsWith(":41", StringComparison.Ordinal) == true).IsSelected);
            Assert.True(twoSelected.Actions.Single(action => action.CardInstanceId?.EndsWith(":42", StringComparison.Ordinal) == true).IsSelected);

            var done = Assert.Single(twoSelected.Actions, action => action.Type == "choose_none");
            var completed = await adapter.SubmitChoiceAsync(
                new ChoiceRequestDto(twoSelected.DecisionId, done.ActionId) { SessionId = initial.SessionId },
                CancellationToken.None);
            Assert.True(completed.Accepted);
            Assert.Equal("forge-tui-2", completed.State.CurrentDecision?.DecisionId);
            Assert.Equal(["4", "5", "0"], (await File.ReadAllLinesAsync(inputLog)).Select(line => line.Trim()).ToArray());
        }
        finally
        {
            File.Delete(script);
            File.Delete(inputLog);
        }
    }

    [Fact]
    public async Task MulliganBottomCollectionChoiceRoundTripsForgeSelectionThenCurrentDone()
    {
        var command = Path.Combine(Environment.SystemDirectory, "cmd.exe");
        if (!File.Exists(command)) return;

        var script = Path.Combine(Path.GetTempPath(), $"forge-tui-mulligan-bottom-{Guid.NewGuid():N}.cmd");
        var inputLog = Path.Combine(Path.GetTempPath(), $"forge-tui-mulligan-bottom-{Guid.NewGuid():N}.log");
        await File.WriteAllTextAsync(script, """
            @echo off
            echo === FORGE CHOICE ===
            echo Choose cards to put on the bottom of your library
            echo [kind=mulligan mulliganStage=bottom_selection sourceZone=hand min=1 max=1 selected=0 ordered=false]
            echo   0. Done
            echo   1. Island [id=41] [bridge entityKind=card cardInstanceId=41 sourceZone=hand]
            echo   2. Mountain [id=42] [bridge entityKind=card cardInstanceId=42 sourceZone=hand]
            <nul set /p "=Enter choice (0-2): "
            set /p choice=
            >>"__INPUT_LOG__" echo(%choice%
            if not "%choice%"=="2" exit /b 41
            echo === FORGE CHOICE ===
            echo Choose cards to put on the bottom of your library
            echo [kind=mulligan mulliganStage=bottom_selection sourceZone=hand min=1 max=1 selected=1 ordered=false]
            echo   0. Done
            echo   1. Island [id=41] [bridge entityKind=card cardInstanceId=41 sourceZone=hand]
            echo   2. Mountain [id=42] [SELECTED] [bridge entityKind=card cardInstanceId=42 sourceZone=hand]
            <nul set /p "=Enter choice (0-2): "
            set /p choice=
            >>"__INPUT_LOG__" echo(%choice%
            if not "%choice%"=="0" exit /b 42
            echo What would you like to do?
            echo   0. Pass priority (do nothing)
            <nul set /p "=Enter choice (0-0): "
            set /p choice=
            """.Replace("__INPUT_LOG__", inputLog));

        try
        {
            await using var adapter = new ForgeTuiAdapter(
                Options.Create(new ForgeTuiOptions
                {
                    Executable = command,
                    Arguments = $"/d /q /c \"{script}\"",
                    WorkingDirectory = Path.GetDirectoryName(script)!,
                    StartupTimeoutSeconds = 5,
                    DecisionTimeoutSeconds = 5,
                }), NullLogger<ForgeTuiAdapter>.Instance);

            var initial = await adapter.StartSessionAsync(CancellationToken.None);
            var firstDecision = Assert.IsType<DecisionDto>(initial.CurrentDecision);
            Assert.Equal("mulligan", firstDecision.Kind);
            Assert.Equal("bottom_selection", firstDecision.MulliganStage);
            var mountain = Assert.Single(firstDecision.Actions, action => action.CardIdentity == "Mountain");
            Assert.Equal("forge-tui-1-choice-2", mountain.ActionId);

            var toggled = await adapter.SubmitChoiceAsync(
                new ChoiceRequestDto(firstDecision.DecisionId, mountain.ActionId) { SessionId = initial.SessionId },
                CancellationToken.None);
            var redraw = Assert.IsType<DecisionDto>(toggled.State.CurrentDecision);
            Assert.Equal(firstDecision.DecisionId, redraw.DecisionId);
            Assert.Equal(1, redraw.SelectedCount);
            Assert.True(Assert.Single(redraw.Actions, action => action.CardIdentity == "Mountain").IsSelected);

            var done = Assert.Single(redraw.Actions, action => action.Type == "choose_none");
            var completed = await adapter.SubmitChoiceAsync(
                new ChoiceRequestDto(redraw.DecisionId, done.ActionId) { SessionId = initial.SessionId },
                CancellationToken.None);
            Assert.True(completed.Accepted);
            Assert.Equal("forge-tui-2", completed.State.CurrentDecision?.DecisionId);
            Assert.Equal(["2", "0"], (await File.ReadAllLinesAsync(inputLog)).Select(line => line.Trim()).ToArray());
        }
        finally
        {
            File.Delete(script);
            File.Delete(inputLog);
        }
    }

    [Fact]
    public async Task CrewCollectionChoiceKeepsDuplicateNamesDistinctAcrossMultipleSelections()
    {
        var command = Path.Combine(Environment.SystemDirectory, "cmd.exe");
        if (!File.Exists(command)) return;
        var script = Path.Combine(Path.GetTempPath(), $"forge-tui-crew-selection-{Guid.NewGuid():N}.cmd");
        await File.WriteAllTextAsync(script, """
            @echo off
            :initial
            echo === FORGE CHOICE ===
            echo CREW - SELECT CREATURES
            echo [kind=cost_selection costKind=crew sourceZone=battlefield requiredTotalPower=3 selectedTotalPower=0 min=0 max=3 selected=0 ordered=false]
            echo   0. Done
            echo   1. Grizzly Bears [id=41] [bridge entityKind=permanent cardInstanceId=41 sourceZone=battlefield]
            echo   2. Grizzly Bears [id=42] [bridge entityKind=permanent cardInstanceId=42 sourceZone=battlefield]
            echo   3. Llanowar Elves [id=43] [bridge entityKind=permanent cardInstanceId=43 sourceZone=battlefield]
            <nul set /p "=Enter choice (0-3): "
            set /p choice=
            if "%choice%"=="1" goto first
            exit /b 41
            :first
            echo === FORGE CHOICE ===
            echo CREW - SELECT CREATURES
            echo [kind=cost_selection costKind=crew sourceZone=battlefield requiredTotalPower=3 selectedTotalPower=2 min=0 max=3 selected=1 ordered=false]
            echo   0. Done
            echo   1. Grizzly Bears [id=41] [SELECTED] [bridge entityKind=permanent cardInstanceId=41 sourceZone=battlefield]
            echo   2. Grizzly Bears [id=42] [bridge entityKind=permanent cardInstanceId=42 sourceZone=battlefield]
            echo   3. Llanowar Elves [id=43] [bridge entityKind=permanent cardInstanceId=43 sourceZone=battlefield]
            <nul set /p "=Enter choice (0-3): "
            set /p choice=
            if "%choice%"=="2" goto second
            exit /b 42
            :second
            echo === FORGE CHOICE ===
            echo CREW - SELECT CREATURES
            echo [kind=cost_selection costKind=crew sourceZone=battlefield requiredTotalPower=3 selectedTotalPower=4 min=0 max=3 selected=2 ordered=false]
            echo   0. Done
            echo   1. Grizzly Bears [id=41] [SELECTED] [bridge entityKind=permanent cardInstanceId=41 sourceZone=battlefield]
            echo   2. Grizzly Bears [id=42] [SELECTED] [bridge entityKind=permanent cardInstanceId=42 sourceZone=battlefield]
            echo   3. Llanowar Elves [id=43] [bridge entityKind=permanent cardInstanceId=43 sourceZone=battlefield]
            <nul set /p "=Enter choice (0-3): "
            set /p choice=
            if not "%choice%"=="0" exit /b 43
            echo What would you like to do?
            echo   0. Pass priority (do nothing)
            <nul set /p "=Enter choice (0-0): "
            set /p choice=
            """);

        try
        {
            await using var adapter = new ForgeTuiAdapter(
                Options.Create(new ForgeTuiOptions
                {
                    Executable = command,
                    Arguments = $"/d /q /c \"{script}\"",
                    WorkingDirectory = Path.GetDirectoryName(script)!,
                    StartupTimeoutSeconds = 5,
                    DecisionTimeoutSeconds = 5,
                }), NullLogger<ForgeTuiAdapter>.Instance);

            var initial = await adapter.StartSessionAsync(CancellationToken.None);
            var firstDecision = Assert.IsType<DecisionDto>(initial.CurrentDecision);
            Assert.Equal("crew", firstDecision.CostKind);
            Assert.StartsWith("forge:", firstDecision.Actions[1].CardInstanceId, StringComparison.Ordinal);
            Assert.EndsWith(":41", firstDecision.Actions[1].CardInstanceId, StringComparison.Ordinal);
            Assert.EndsWith(":42", firstDecision.Actions[2].CardInstanceId, StringComparison.Ordinal);
            Assert.EndsWith(":43", firstDecision.Actions[3].CardInstanceId, StringComparison.Ordinal);
            Assert.Equal(3, firstDecision.RequiredTotalPower);

            var firstSelection = await adapter.SubmitChoiceAsync(
                new ChoiceRequestDto(firstDecision.DecisionId, firstDecision.Actions[1].ActionId) { SessionId = initial.SessionId },
                CancellationToken.None);
            var secondDecision = Assert.IsType<DecisionDto>(firstSelection.State.CurrentDecision);
            Assert.Equal(firstDecision.DecisionId, secondDecision.DecisionId);
            Assert.Equal(2, secondDecision.SelectedTotalPower);
            Assert.True(secondDecision.Actions[1].IsSelected);
            Assert.False(secondDecision.Actions[2].IsSelected);

            var secondSelection = await adapter.SubmitChoiceAsync(
                new ChoiceRequestDto(secondDecision.DecisionId, secondDecision.Actions[2].ActionId) { SessionId = initial.SessionId },
                CancellationToken.None);
            var completedSelection = Assert.IsType<DecisionDto>(secondSelection.State.CurrentDecision);
            Assert.Equal(4, completedSelection.SelectedTotalPower);
            Assert.True(completedSelection.Actions[1].IsSelected);
            Assert.True(completedSelection.Actions[2].IsSelected);

            var done = Assert.Single(completedSelection.Actions, action => action.Type == "choose_none");
            var completed = await adapter.SubmitChoiceAsync(
                new ChoiceRequestDto(completedSelection.DecisionId, done.ActionId) { SessionId = initial.SessionId },
                CancellationToken.None);
            Assert.True(completed.Accepted);
            Assert.Equal("forge-tui-2", completed.State.CurrentDecision?.DecisionId);
        }
        finally
        {
            File.Delete(script);
        }
    }

    [Fact]
    public async Task ConcurrentDuplicateChoice_ConsumesForgeDecisionAndWritesStdinOnlyOnce()
    {
        var command = Path.Combine(Environment.SystemDirectory, "cmd.exe");
        if (!File.Exists(command)) return;

        var script = Path.Combine(Path.GetTempPath(), $"forge-tui-idempotent-{Guid.NewGuid():N}.cmd");
        var inputLog = Path.Combine(Path.GetTempPath(), $"forge-tui-idempotent-{Guid.NewGuid():N}.log");
        await File.WriteAllTextAsync(script, """
            @echo off
            echo What would you like to do?
            echo   0. Pass priority (do nothing)
            <nul set /p "=Enter choice (0-0): "
            set /p choice=
            echo %choice% > "__INPUT_LOG__"
            if not "%choice%"=="0" exit /b 9
            ping 127.0.0.1 -n 2 >nul
            echo What would you like to do?
            echo   0. Pass priority (do nothing)
            <nul set /p "=Enter choice (0-0): "
            set /p choice2=
            echo %choice2% >> "__INPUT_LOG__"
            """.Replace("__INPUT_LOG__", inputLog));

        try
        {
            await using var adapter = new ForgeTuiAdapter(
                Options.Create(new ForgeTuiOptions
                {
                    Executable = command,
                    Arguments = $"/d /q /c \"{script}\"",
                    WorkingDirectory = Path.GetDirectoryName(script)!,
                    StartupTimeoutSeconds = 5,
                    DecisionTimeoutSeconds = 5,
                }),
                NullLogger<ForgeTuiAdapter>.Instance);

            var initial = await adapter.StartSessionAsync(CancellationToken.None);
            var decision = Assert.IsType<MtgTtsBridge.Contracts.State.DecisionDto>(initial.CurrentDecision);
            var pass = Assert.Single(decision.Actions, action => action.Type == "pass_priority");

            var first = adapter.SubmitChoiceAsync(new ChoiceRequestDto(decision.DecisionId, pass.ActionId) { SessionId = initial.SessionId }, CancellationToken.None);
            for (var attempt = 0; attempt < 50; attempt++)
            {
                if ((await adapter.GetStateAsync(CancellationToken.None)).State == "awaiting_forge") break;
                await Task.Delay(20);
            }
            Assert.Equal("awaiting_forge", (await adapter.GetStateAsync(CancellationToken.None)).State);

            var duplicate = await adapter.SubmitChoiceAsync(new ChoiceRequestDto(decision.DecisionId, pass.ActionId) { SessionId = initial.SessionId }, CancellationToken.None);
            var unknown = await adapter.SubmitChoiceAsync(new ChoiceRequestDto("not-a-forge-decision", pass.ActionId) { SessionId = initial.SessionId }, CancellationToken.None);
            var original = await first;

            Assert.True(duplicate.Accepted);
            Assert.False(unknown.Accepted);
            Assert.Equal("no_pending_decision", unknown.ErrorCode);
            Assert.True(original.Accepted);
            Assert.Equal("forge-tui-2", original.State.CurrentDecision?.DecisionId);
            var inputs = (await File.ReadAllLinesAsync(inputLog)).Select(input => input.Trim()).ToArray();
            Assert.Equal(new[] { "0" }, inputs);
        }
        finally
        {
            File.Delete(script);
            File.Delete(inputLog);
        }
    }

    [Fact]
    public async Task PreviousSessionChoice_IsRejectedBeforeAnyForgeStdinWrite()
    {
        var command = Path.Combine(Environment.SystemDirectory, "cmd.exe");
        if (!File.Exists(command)) return;

        var script = Path.Combine(Path.GetTempPath(), $"forge-tui-stale-session-{Guid.NewGuid():N}.cmd");
        var inputLog = Path.Combine(Path.GetTempPath(), $"forge-tui-stale-session-{Guid.NewGuid():N}.log");
        await File.WriteAllTextAsync(script, """
            @echo off
            echo What would you like to do?
            echo   0. Pass priority (do nothing)
            <nul set /p "=Enter choice (0-0): "
            set /p choice=
            echo %choice% > "__INPUT_LOG__"
            """.Replace("__INPUT_LOG__", inputLog));

        try
        {
            await using var adapter = new ForgeTuiAdapter(
                Options.Create(new ForgeTuiOptions
                {
                    Executable = command,
                    Arguments = $"/d /q /c \"{script}\"",
                    WorkingDirectory = Path.GetDirectoryName(script)!,
                    StartupTimeoutSeconds = 5,
                    DecisionTimeoutSeconds = 5,
                }),
                NullLogger<ForgeTuiAdapter>.Instance);

            var state = await adapter.StartSessionAsync(CancellationToken.None);
            var decision = Assert.IsType<DecisionDto>(state.CurrentDecision);
            var pass = Assert.Single(decision.Actions, action => action.Type == "pass_priority");

            var rejection = await adapter.SubmitChoiceAsync(
                new ChoiceRequestDto(decision.DecisionId, pass.ActionId) { SessionId = "previous-session" },
                CancellationToken.None);

            Assert.False(rejection.Accepted);
            Assert.Equal("stale_session", rejection.ErrorCode);
            Assert.Equal(state.SessionId, rejection.ExpectedSessionId);
            Assert.Equal("previous-session", rejection.ReceivedSessionId);
            Assert.Equal("awaiting_human_decision", (await adapter.GetStateAsync(CancellationToken.None)).State);
            Assert.False(File.Exists(inputLog));
        }
        finally
        {
            File.Delete(script);
            File.Delete(inputLog);
        }
    }

    [Fact]
    public async Task ConcurrentStartsAndAttach_ReuseOneHealthySession()
    {
        var command = Path.Combine(Environment.SystemDirectory, "cmd.exe");
        if (!File.Exists(command)) return;

        var script = Path.Combine(Path.GetTempPath(), $"forge-tui-start-{Guid.NewGuid():N}.cmd");
        await File.WriteAllTextAsync(script, """
            @echo off
            echo === Forge Text UI Mode ===
            echo Initializing Forge
            echo Language 'en-US' loaded successfully.
            echo Read cards: test
            echo Card database loaded successfully.
            echo Starting game: test
            echo Game starting...
            echo What would you like to do?
            echo   0. Pass priority (do nothing)
            <nul set /p "=Enter choice (0-0): "
            set /p choice=
            """);

        try
        {
            await using var adapter = new ForgeTuiAdapter(
                Options.Create(new ForgeTuiOptions
                {
                    Executable = command,
                    Arguments = $"/d /q /c \"{script}\"",
                    WorkingDirectory = Path.GetDirectoryName(script)!,
                    StartupTimeoutSeconds = 5,
                }),
                NullLogger<ForgeTuiAdapter>.Instance);

            var starts = await Task.WhenAll(
                adapter.StartSessionAsync(CancellationToken.None),
                adapter.StartSessionAsync(CancellationToken.None));
            var attached = await adapter.StartSessionAsync(CancellationToken.None);
            var healthRead = await adapter.GetStateAsync(CancellationToken.None);

            Assert.Equal(starts[0].SessionId, starts[1].SessionId);
            Assert.Equal(starts[0].SessionId, attached.SessionId);
            Assert.Equal(starts[0].SessionId, healthRead.SessionId);
            Assert.Equal("awaiting_human_decision", healthRead.State);
            Assert.Contains(healthRead.Diagnostic!.StartupMilestones, item => item.Name == "first_human_decision");
        }
        finally
        {
            File.Delete(script);
        }
    }

    [Fact]
    public async Task ExplicitReset_ReplacesHealthyProcessAndSession()
    {
        var command = Path.Combine(Environment.SystemDirectory, "cmd.exe");
        if (!File.Exists(command)) return;

        var script = Path.Combine(Path.GetTempPath(), $"forge-tui-reset-{Guid.NewGuid():N}.cmd");
        await File.WriteAllTextAsync(script, """
            @echo off
            echo What would you like to do?
            echo   0. Pass priority (do nothing)
            <nul set /p "=Enter choice (0-0): "
            set /p choice=
            """);

        try
        {
            await using var adapter = new ForgeTuiAdapter(
                Options.Create(new ForgeTuiOptions
                {
                    Executable = command,
                    Arguments = $"/d /q /c \"{script}\"",
                    WorkingDirectory = Path.GetDirectoryName(script)!,
                    StartupTimeoutSeconds = 5,
                }),
                NullLogger<ForgeTuiAdapter>.Instance);

            var first = await adapter.StartSessionAsync(CancellationToken.None);
            var attached = await adapter.StartSessionAsync(CancellationToken.None);
            var reset = await adapter.ResetSessionAsync(CancellationToken.None);

            Assert.Equal(first.SessionId, attached.SessionId);
            Assert.NotEqual(first.SessionId, reset.SessionId);
            Assert.Equal("awaiting_human_decision", reset.State);
            Assert.NotNull(reset.CurrentDecision);
        }
        finally
        {
            File.Delete(script);
        }
    }

    [Fact]
    public async Task UnknownNumericPrompt_PreservesProcessAndDiagnosticState()
    {
        var command = Path.Combine(Environment.SystemDirectory, "cmd.exe");
        if (!File.Exists(command)) return;

        var script = Path.Combine(Path.GetTempPath(), $"forge-tui-unsupported-{Guid.NewGuid():N}.cmd");
        await File.WriteAllTextAsync(script, """
            @echo off
            echo An unfamiliar blocking controller prompt
            <nul set /p "=Enter choice (0-1): "
            set /p choice=
            """);

        try
        {
            await using var adapter = new ForgeTuiAdapter(
                Options.Create(new ForgeTuiOptions
                {
                    Executable = command,
                    Arguments = $"/d /q /c \"{script}\"",
                    WorkingDirectory = Path.GetDirectoryName(script)!,
                    StartupTimeoutSeconds = 5,
                }),
                NullLogger<ForgeTuiAdapter>.Instance);

            var unsupported = await adapter.StartSessionAsync(CancellationToken.None);
            var attached = await adapter.StartSessionAsync(CancellationToken.None);

            Assert.Equal("unsupported_decision", unsupported.State);
            Assert.Equal("unsupported_numeric_prompt", unsupported.Diagnostic?.Code);
            Assert.Contains("unfamiliar blocking", unsupported.Diagnostic?.Context);
            Assert.Equal(unsupported.SessionId, attached.SessionId);
            Assert.Equal("unsupported_decision", attached.State);
        }
        finally
        {
            File.Delete(script);
        }
    }

    [Fact]
    public async Task AuthoritativeEvents_AreOrderedAndNotReplayedAfterSequence()
    {
        var command = Path.Combine(Environment.SystemDirectory, "cmd.exe");
        if (!File.Exists(command)) return;

        var script = Path.Combine(Path.GetTempPath(), $"forge-tui-events-{Guid.NewGuid():N}.cmd");
        await File.WriteAllTextAsync(script, """
            @echo off
            echo +++ Land: AI-monored played Mountain (128)
            echo +++ Mana: Mountain (128) - {T}: Add {R}.
            echo What would you like to do?
            echo   0. Pass priority (do nothing)
            <nul set /p "=Enter choice (0-0): "
            set /p choice=
            """);

        try
        {
            await using var adapter = new ForgeTuiAdapter(
                Options.Create(new ForgeTuiOptions
                {
                    Executable = command,
                    Arguments = $"/d /q /c \"{script}\"",
                    WorkingDirectory = Path.GetDirectoryName(script)!,
                    StartupTimeoutSeconds = 5,
                }),
                NullLogger<ForgeTuiAdapter>.Instance);

            var session = await adapter.StartSessionAsync(CancellationToken.None);
            var firstBatch = await adapter.GetEventsAsync(0, CancellationToken.None);
            var acknowledged = await adapter.GetEventsAsync(firstBatch.LatestSequence, CancellationToken.None);

            Assert.False(firstBatch.HasGap);
            Assert.Equal([1L, 2L], firstBatch.Events.Select(item => item.Sequence));
            Assert.Equal(["land_played", "mana_ability_used"], firstBatch.Events.Select(item => item.Kind));
            Assert.All(firstBatch.Events, item => Assert.Equal("forge-player-2", item.SeatId));
            Assert.Equal($"forge:{session.SessionId}:128", firstBatch.Events[0].CardInstanceId);
            Assert.Equal(firstBatch.Events[0].CardInstanceId, firstBatch.Events[1].CardInstanceId);
            Assert.Empty(acknowledged.Events);
            Assert.Equal(firstBatch.LatestSequence, acknowledged.LatestSequence);
        }
        finally
        {
            File.Delete(script);
        }
    }

    [Fact]
    public async Task EventHistoryOverflow_ReportsAnActualSequenceGap()
    {
        var command = Path.Combine(Environment.SystemDirectory, "cmd.exe");
        if (!File.Exists(command)) return;

        var script = Path.Combine(Path.GetTempPath(), $"forge-tui-event-gap-{Guid.NewGuid():N}.cmd");
        var lines = Enumerable.Range(1, 513)
            .Select(index => $"echo +++ Land: AI-monored played Mountain ({index})")
            .Prepend("@echo off")
            .Concat([
                "echo What would you like to do?",
                "echo   0. Pass priority (do nothing)",
                "<nul set /p \"=Enter choice (0-0): \"",
                "set /p choice=",
            ]);
        await File.WriteAllLinesAsync(script, lines);

        try
        {
            await using var adapter = new ForgeTuiAdapter(
                Options.Create(new ForgeTuiOptions
                {
                    Executable = command,
                    Arguments = $"/d /q /c \"{script}\"",
                    WorkingDirectory = Path.GetDirectoryName(script)!,
                    StartupTimeoutSeconds = 15,
                }),
                NullLogger<ForgeTuiAdapter>.Instance);

            await adapter.StartSessionAsync(CancellationToken.None);
            var batch = await adapter.GetEventsAsync(0, CancellationToken.None);

            Assert.True(batch.HasGap);
            Assert.Equal(2, batch.OldestAvailableSequence);
            Assert.Equal(513, batch.LatestSequence);
            Assert.Empty(batch.Events);
        }
        finally
        {
            File.Delete(script);
        }
    }
}
