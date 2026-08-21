using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using MtgTtsBridge.Contracts.Actions;
using MtgTtsBridge.Forge;

namespace MtgTtsBridge.Tests;

public sealed class ForgeTuiAdapterTests
{
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
    public async Task Choice_UsesMappedNumericInputAndRejectsResolvedDecisionAsStale()
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
                new ChoiceRequestDto(decision.DecisionId, mountain.ActionId), CancellationToken.None);
            Assert.True(accepted.Accepted);
            Assert.Equal("forge-tui-2", accepted.State.CurrentDecision?.DecisionId);

            var stale = await adapter.SubmitChoiceAsync(
                new ChoiceRequestDto(decision.DecisionId, mountain.ActionId), CancellationToken.None);
            Assert.False(stale.Accepted);
            Assert.Equal("stale_decision_id", stale.ErrorCode);
        }
        finally
        {
            File.Delete(script);
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
