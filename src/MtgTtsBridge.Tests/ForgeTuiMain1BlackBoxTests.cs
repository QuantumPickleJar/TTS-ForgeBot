using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using MtgTtsBridge.Contracts.Actions;
using MtgTtsBridge.Contracts.State;
using MtgTtsBridge.Forge;
using Xunit.Abstractions;

namespace MtgTtsBridge.Tests;

/// <summary>
/// Opt-in black-box probe for the real stamped Forge process and the real
/// ForgeTuiAdapter. It deliberately stops at the first human precombat Main 1
/// decision and never submits that decision.
/// </summary>
public sealed class ForgeTuiMain1BlackBoxTests
{
    private readonly ITestOutputHelper _output;

    public ForgeTuiMain1BlackBoxTests(ITestOutputHelper output) => _output = output;

    [Fact]
    [Trait("Category", "RealForgeProbe")]
    public async Task StampedForgeAndAdapterHoldHumanMain1UntilExplicitInput()
    {
        if (!string.Equals(Environment.GetEnvironmentVariable("FORGEBOT_RUN_REAL_FORGE_PROBE"), "1", StringComparison.Ordinal)) return;

        var repositoryRoot = FindRepositoryRoot();
        var forgeRoot = Path.Combine(repositoryRoot, ".deps", "forge");
        var jar = Environment.GetEnvironmentVariable("FORGEBOT_FORGE_JAR")
            ?? Path.Combine(forgeRoot, "forge-headless", "target", "forge-headless-2.0.15-SNAPSHOT-jar-with-dependencies.jar");
        var java = FindJava17();
        if (!File.Exists(jar)) throw new FileNotFoundException("Stamped Forge JAR was not found. Set FORGEBOT_FORGE_JAR to override the path.", jar);
        if (java is null) throw new FileNotFoundException("A Java 17+ executable was not found. Set FORGEBOT_JAVA to override the path.");

        var options = new ForgeTuiOptions
        {
            Executable = java,
            WorkingDirectory = forgeRoot,
            Arguments = $"-jar \"{jar}\" tui \"{{humanDeck}}\" \"{{aiDeck}}\" --p1 tui --p2 ai --numeric-choices --seed 8675309",
            StartupTimeoutSeconds = 120,
            DecisionTimeoutSeconds = 30,
            ShowConsoleWindow = false,
        };

        var timeline = new List<string>();
        await using var adapter = new ForgeTuiAdapter(
            Options.Create(options),
            new ProbeLogger(_output, timeline));

        var landDeck = new[] { new DeckCardLoadDto("Mountain", 60) };
        await adapter.ConfigureDecksAsync(
            new DeckLoadRequestDto(
            [
                new DeckSeatLoadDto("forge-player-1", landDeck),
                new DeckSeatLoadDto("forge-player-2", landDeck),
            ]),
            CancellationToken.None);

        var state = await adapter.StartSessionAsync(CancellationToken.None);
        var deadline = DateTime.UtcNow.AddSeconds(90);
        var submissions = 0;

        try
        {
            while (DateTime.UtcNow < deadline)
            {
                var decision = state.CurrentDecision;
                if (decision is null)
                {
                    await Task.Delay(100, CancellationToken.None);
                    state = await adapter.GetStateAsync(CancellationToken.None);
                    continue;
                }

                var snapshot = await adapter.GetSnapshotAsync(CancellationToken.None);
                var phase = snapshot?.Phase ?? decision.PhaseName ?? "(unknown)";
                timeline.Add($"decision={decision.DecisionId} kind={decision.Kind} phase={phase} active={snapshot?.ActiveSeatId ?? decision.ActiveSeatId ?? "(unknown)"} stack={snapshot?.Stack.Count ?? -1} actions={string.Join(',', decision.Actions.Select(action => action.Type))}");

                if (decision.Kind == "main_priority"
                    && string.Equals(phase, "Main phase, precombat", StringComparison.OrdinalIgnoreCase)
                    && string.Equals(snapshot?.ActiveSeatId ?? decision.ActiveSeatId, "forge-player-1", StringComparison.Ordinal))
                {
                    Assert.NotNull(snapshot);
                    Assert.Equal("forge-player-1", snapshot!.ActiveSeatId ?? decision.ActiveSeatId);
                    Assert.Equal("Main phase, precombat", phase, ignoreCase: true);
                    Assert.Empty(snapshot.Stack);

                    var human = Assert.Single(snapshot.Seats, seat => seat.SeatId == "forge-player-1");
                    var hand = Assert.Single(human.Zones, zone => zone.Name == "hand");
                    var handLands = hand.Cards
                        .Where(card => card.CurrentTypes?.Contains("land", StringComparer.OrdinalIgnoreCase) == true)
                        .ToArray();
                    Assert.NotEmpty(handLands);

                    var landActions = decision.Actions.Where(action => action.Type == "play_land").ToArray();
                    Assert.NotEmpty(landActions);
                    Assert.All(landActions, action => Assert.False(string.IsNullOrWhiteSpace(action.CardInstanceId)));
                    Assert.Contains(landActions, action => handLands.Any(card =>
                        action.CardInstanceId!.EndsWith($":{card.ForgeCardId}", StringComparison.Ordinal)
                        || action.CardInstanceId.EndsWith($"/{card.ForgeCardId}", StringComparison.Ordinal)));

                    timeline.Add($"MAIN1_STOP decision={decision.DecisionId} handLands={handLands.Length} playLandActions={landActions.Length} noInputWindow=1000ms");
                    await Task.Delay(1000, CancellationToken.None);
                    var waiting = await adapter.GetStateAsync(CancellationToken.None);
                    Assert.Equal("awaiting_human_decision", waiting.State);
                    Assert.Equal(decision.DecisionId, waiting.CurrentDecision?.DecisionId);
                    Assert.Equal("main_priority", waiting.CurrentDecision?.Kind);
                    return;
                }

                LegalActionDto actionToSubmit;
                if (decision.Kind == "mulligan")
                {
                    actionToSubmit = Assert.Single(decision.Actions, action => action.Type == "keep_hand");
                }
                else if (decision.Kind == "main_priority")
                {
                    actionToSubmit = Assert.Single(decision.Actions, action => action.Type == "pass_priority");
                }
                else
                {
                    throw new Xunit.Sdk.XunitException($"Unexpected human decision before Main 1: {decision.Kind} ({decision.DecisionId}).");
                }

                submissions++;
                timeline.Add($"choice decision={decision.DecisionId} action={actionToSubmit.ActionId} type={actionToSubmit.Type} source=black-box-probe expectedForgeInput={ForgeInputFor(actionToSubmit)}");
                var result = await adapter.SubmitChoiceAsync(
                    new ChoiceRequestDto(decision.DecisionId, actionToSubmit.ActionId)
                    {
                        SessionId = state.SessionId,
                        Source = "black-box-probe",
                        RequestId = $"black-box-{submissions}",
                    },
                    CancellationToken.None);
                Assert.True(result.Accepted, result.ErrorMessage);
                state = result.State;
            }

            throw new Xunit.Sdk.XunitException("The real Forge/adapter probe did not reach a human precombat Main 1 decision within 90 seconds.");
        }
        finally
        {
            foreach (var line in timeline) _output.WriteLine(line);
        }
    }

    private static string ForgeInputFor(LegalActionDto action)
    {
        var marker = "-choice-";
        var index = action.ActionId.LastIndexOf(marker, StringComparison.Ordinal);
        return index >= 0 ? action.ActionId[(index + marker.Length)..] : "(adapter-mapped)";
    }

    private static string FindRepositoryRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            if (Directory.Exists(Path.Combine(directory.FullName, ".git"))
                && Directory.Exists(Path.Combine(directory.FullName, ".deps"))) return directory.FullName;
            directory = directory.Parent;
        }
        throw new DirectoryNotFoundException("Could not locate the repository root from the test output directory.");
    }

    private static string? FindJava17()
    {
        var configured = Environment.GetEnvironmentVariable("FORGEBOT_JAVA");
        if (!string.IsNullOrWhiteSpace(configured) && File.Exists(configured)) return configured;

        var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        var candidates = new[]
        {
            Path.Combine(programFiles, "Microsoft", "jdk-17.0.20.101-hotspot", "bin", "java.exe"),
            Path.Combine(programFiles, "Java", "jdk-17", "bin", "java.exe"),
        };
        return candidates.FirstOrDefault(File.Exists);
    }

    private sealed class ProbeLogger(ITestOutputHelper output, List<string> timeline) : ILogger<ForgeTuiAdapter>
    {
        private readonly object _gate = new();

        public IDisposable BeginScope<TState>(TState state) where TState : notnull => NullScope.Instance;
        public bool IsEnabled(LogLevel logLevel) => logLevel >= LogLevel.Information;

        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter)
        {
            var line = formatter(state, exception);
            if (!line.Contains("CHOICE_REQUEST", StringComparison.Ordinal)
                && !line.Contains("Forge TUI stdin", StringComparison.Ordinal)
                && !line.Contains("DECISION_PRESENTED", StringComparison.Ordinal)) return;
            lock (_gate)
            {
                timeline.Add($"adapter-log {line}");
                output.WriteLine($"adapter-log {line}");
            }
        }

        private sealed class NullScope : IDisposable
        {
            public static NullScope Instance { get; } = new();
            public void Dispose() { }
        }
    }
}
