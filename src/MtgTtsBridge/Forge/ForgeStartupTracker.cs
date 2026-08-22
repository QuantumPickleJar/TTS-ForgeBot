using System.Diagnostics;
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
    private readonly StringBuilder _scanBuffer = new();
    private long _startedTimestamp;

    public ForgeStartupTracker(ILogger logger) => _logger = logger;

    public void Reset()
    {
        _milestones.Clear();
        _seen.Clear();
        _scanBuffer.Clear();
        _startedTimestamp = Stopwatch.GetTimestamp();
        Mark("session_start_received");
    }

    public void MarkProcessLaunched() => Mark("java_process_launched");

    public void MarkFirstDecision() => Mark("first_human_decision");

    public void Observe(string output)
    {
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
    }
}
