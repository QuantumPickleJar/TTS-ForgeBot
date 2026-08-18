using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using MtgTtsBridge.Contracts.Actions;
using MtgTtsBridge.Forge;

namespace MtgTtsBridge.Tests;

public sealed class ForgeTuiAdapterTests
{
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
}
