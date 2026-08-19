namespace MtgTtsBridge.Forge;

public sealed class ForgeTuiOptions
{
    public string WorkingDirectory { get; init; } = string.Empty;

    public string Executable { get; init; } = string.Empty;

    public string Arguments { get; init; } = string.Empty;

    public int StartupTimeoutSeconds { get; init; } = 180;

    public int DecisionTimeoutSeconds { get; init; } = 60;

    public string HumanSeatId { get; init; } = "forge-player-1";

    public Dictionary<string, string> PlayerSeats { get; init; } = new(StringComparer.OrdinalIgnoreCase)
    {
        ["Player 1"] = "forge-player-1",
        ["AI-monored"] = "forge-player-2",
    };
}
