namespace MtgTtsBridge.Forge;

public sealed class ForgeTuiOptions
{
    public string WorkingDirectory { get; init; } = string.Empty;

    public string Executable { get; init; } = string.Empty;

    public string Arguments { get; init; } = string.Empty;

    public int StartupTimeoutSeconds { get; init; } = 180;

    public int DecisionTimeoutSeconds { get; init; } = 60;

    public string HumanSeatId { get; init; } = "forge-player-1";
}
