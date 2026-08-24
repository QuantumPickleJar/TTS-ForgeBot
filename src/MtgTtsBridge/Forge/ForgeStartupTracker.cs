using System.Diagnostics;
using System.Linq;
using System.Text;
using MtgTtsBridge.Contracts.State;

namespace MtgTtsBridge.Forge;

internal sealed class ForgeStartupTracker
{
    private const int ScanBufferLimit = 8192;

    private static readonly (string Name, string Marker)[] OutputMilestones =
    [
        ("forge_tui_banner", "=== Forge Text UI Mode ==="),
        ("forge_initializing", "Initializing Forge"),
        ("language_loaded", "loaded successfully."),
        ("first_card_loading_output", "Read cards:"),
        ("card_database_loaded", "Card database loaded successfully."),
        ("starting_game", "Starting game:"),
        ("game_starting", "Game starting..."),
    ];

    private readonly ILogger _logger;
    private readonly List<StartupMilestoneDto> _milestones = [];
    private readonly HashSet<string> _seen = new(StringComparer.Ordinal);
    private readonly HashSet<string> _seenProfileLines = new(StringComparer.Ordinal);
    private readonly StringBuilder _scanBuffer = new();
    private string _profileLineRemainder = string.Empty;
    private long _startedTimestamp;

    public ForgeStartupTracker(ILogger logger) => _logger = logger;

    public void Reset()
    {
        _milestones.Clear();
        _seen.Clear();
        _seenProfileLines.Clear();
        _scanBuffer.Clear();
        _profileLineRemainder = string.Empty;
        _startedTimestamp = Stopwatch.GetTimestamp();
        Mark("session_start_received");
    }

    public void MarkProcessLaunched() => Mark("java_process_launched");

    public void MarkFirstDecision() => Mark("first_human_decision");

    public void Observe(string output)
    {
        var lineBuffer = (_profileLineRemainder + output).Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n');
        var lineParts = lineBuffer.Split('\n');
        var completeCount = lineBuffer.EndsWith('\n') ? lineParts.Length : Math.Max(0, lineParts.Length - 1);
        _profileLineRemainder = lineBuffer.EndsWith('\n') ? string.Empty : lineParts[^1];

        for (var i = 0; i < completeCount; i++)
        {
            var line = lineParts[i].Trim();
            if (!line.StartsWith("[Forge profile]", StringComparison.Ordinal)) continue;
            if (!_seenProfileLines.Add(line)) continue;
            Console.WriteLine(line);
            _logger.LogInformation("{ForgeProfileLine}", line);
        }

        _scanBuffer.Append(output);
        if (_scanBuffer.Length > ScanBufferLimit)
        {
            _scanBuffer.Remove(0, _scanBuffer.Length - ScanBufferLimit);
        }

        var text = _scanBuffer.ToString();
        foreach (var (name, marker) in OutputMilestones)
        {
            if (text.Contains(marker, StringComparison.Ordinal)) Mark(name);
        }
    }

    public IReadOnlyList<StartupMilestoneDto> Snapshot() => _milestones.ToArray();

    private void Mark(string name)
    {
        if (!_seen.Add(name)) return;

        var elapsed = _startedTimestamp == 0
            ? 0
            : (long)Stopwatch.GetElapsedTime(_startedTimestamp).TotalMilliseconds;
        _milestones.Add(new StartupMilestoneDto(name, elapsed));
        var message = $"[Forge startup] {name} at +{elapsed} ms";
        Console.WriteLine(message);
        _logger.LogInformation("Forge startup milestone {Milestone} at +{ElapsedMilliseconds} ms", name, elapsed);
        if (string.Equals(name, "first_human_decision", StringComparison.Ordinal))
        {
            LogSummary();
        }
    }

    private void LogSummary()
    {
        var byName = _milestones.ToDictionary(m => m.Name, m => m.ElapsedMilliseconds, StringComparer.Ordinal);

        static long Delta(IReadOnlyDictionary<string, long> milestones, string from, string to)
            => milestones.TryGetValue(to, out var end) && milestones.TryGetValue(from, out var start) ? Math.Max(0, end - start) : 0;

        var jvmMs = Delta(byName, "session_start_received", "java_process_launched");
        var languageMs = Delta(byName, "java_process_launched", "language_loaded");
        var cardDbMs = Delta(byName, "language_loaded", "card_database_loaded");
        var gameCreateMs = Delta(byName, "card_database_loaded", "game_starting");
        var firstDecisionMs = Delta(byName, "game_starting", "first_human_decision");
        var totalMs = byName.TryGetValue("first_human_decision", out var total) ? total : 0;
        var summary = $"[Forge startup summary] JVM={jvmMs}ms language={languageMs}ms cardDb={cardDbMs}ms gameCreate={gameCreateMs}ms firstDecision={firstDecisionMs}ms total={totalMs}ms";
        Console.WriteLine(summary);
        _logger.LogInformation(
            "Forge startup summary JVM={JvmMs}ms language={LanguageMs}ms cardDb={CardDbMs}ms gameCreate={GameCreateMs}ms firstDecision={FirstDecisionMs}ms total={TotalMs}ms",
            jvmMs, languageMs, cardDbMs, gameCreateMs, firstDecisionMs, totalMs);
    }
}
