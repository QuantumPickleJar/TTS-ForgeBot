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
            echo [TUI-DIAG priority] turn=2 phase=Main priority=Player 1 isMyTurn=true totalActions=1 uniqueActions=1
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
        await File.WriteAllTextAsync(script, """
            @echo off
            echo === FORGE CHOICE ===
            echo Choose cards to discard
            echo [kind=discard min=1 max=1 selected=0 ordered=false]
            echo   0. Done
            echo   1. Island [id=41]
            <nul set /p "=Enter choice (0-1): "
            set /p choice=
            echo === FORGE CHOICE ===
            echo Choose cards to discard
            echo [kind=discard min=1 max=1 selected=1 ordered=false]
            echo   0. Done
            echo   1. Island [id=41] [SELECTED]
            <nul set /p "=Enter choice (0-1): "
            set /p choice=
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
            var firstDecision = Assert.IsType<MtgTtsBridge.Contracts.State.DecisionDto>(initial.CurrentDecision);
            var card = Assert.Single(firstDecision.Actions, action => action.Type == "discard_card");
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
