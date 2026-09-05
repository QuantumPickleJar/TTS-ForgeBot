using System.Diagnostics;

namespace MtgTtsBridge;

public sealed class BridgeProcessIdentity
{
    // Keep the process diagnostic in lockstep with the Global.lua protocol
    // revision so a live table cannot silently report an older bridge build.
    public static readonly string Revision = ReadGit("rev-parse HEAD") ?? "git-unavailable";
    private static readonly string? GitStatus = ReadGit("status --porcelain");
    public static readonly bool? IsDirty = GitStatus is null ? null : GitStatus.Length > 0;
    public static readonly string BuildIdentity = typeof(BridgeProcessIdentity).Assembly.GetName().Version?.ToString()
        + ":" + File.GetLastWriteTimeUtc(typeof(BridgeProcessIdentity).Assembly.Location).ToString("O");

    public BridgeProcessIdentity()
    {
        using var process = Process.GetCurrentProcess();
        ProcessId = process.Id;
        ProcessStartUtc = process.StartTime.ToUniversalTime();
        InstanceId = _instanceId;
    }

    public static string InstanceId { get; private set; } = "process-not-initialized";
    public string ProcessInstanceId => _instanceId;

    private readonly string _instanceId = Guid.NewGuid().ToString("N");
    public int ProcessId { get; }
    public DateTimeOffset ProcessStartUtc { get; }

    private static string? ReadGit(string arguments)
    {
        try
        {
            var directory = new DirectoryInfo(AppContext.BaseDirectory);
            while (directory is not null && !File.Exists(Path.Combine(directory.FullName, "AGENTS.md"))) directory = directory.Parent;
            if (directory is null) return null;
            using var process = Process.Start(new ProcessStartInfo("git", arguments)
            {
                WorkingDirectory = directory.FullName,
                RedirectStandardOutput = true,
                UseShellExecute = false,
                CreateNoWindow = true
            });
            if (process is null || !process.WaitForExit(1000) || process.ExitCode != 0) return null;
            return process.StandardOutput.ReadToEnd().Trim();
        }
        catch { return null; }
    }
}
