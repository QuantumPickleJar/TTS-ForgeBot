namespace MtgTtsBridge.Tests;

public sealed class PushTtsGlobalScriptTests
{
    [Fact]
    public void PushScript_IsThinHttpClientWithoutDirectTcpListenerOwnership()
    {
        var repositoryRoot = FindRepositoryRoot();
        var scriptPath = Path.Combine(repositoryRoot, "tools", "Push-TtsGlobal.ps1");
        var script = File.ReadAllText(scriptPath);

        Assert.Contains("/api/v1/tts-editor/status", script, StringComparison.Ordinal);
        Assert.Contains("/api/v1/tts-editor/push-global", script, StringComparison.Ordinal);
        Assert.DoesNotContain("TcpListener", script, StringComparison.Ordinal);
        Assert.DoesNotContain("localhost:39998", script, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Receive-TtsJsonMessage", script, StringComparison.Ordinal);
        Assert.DoesNotContain("Send-TtsMessage", script, StringComparison.Ordinal);
    }

    private static string FindRepositoryRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null && !File.Exists(Path.Combine(directory.FullName, "AGENTS.md")))
            directory = directory.Parent;
        return directory?.FullName ?? throw new DirectoryNotFoundException("Repository root not found.");
    }
}
