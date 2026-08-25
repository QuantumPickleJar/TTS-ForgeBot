using System.Diagnostics;
using System.Net;
using System.Net.NetworkInformation;

namespace MtgTtsBridge;

public static class BridgePortOwnershipGuard
{
    public static void ThrowIfAlreadyListening(string listenUrl)
    {
        if (!Uri.TryCreate(listenUrl, UriKind.Absolute, out var uri)) return;
        var endpoint = new IPEndPoint(IPAddress.Loopback, uri.Port);
        var occupied = IPGlobalProperties.GetIPGlobalProperties().GetActiveTcpListeners()
            .Any(item => item.Port == endpoint.Port && (IPAddress.IsLoopback(item.Address) || item.Address.Equals(IPAddress.Any)));
        if (!occupied) return;

        var details = FindOwnerDetails(endpoint.Port);
        throw new InvalidOperationException($"Bridge cannot start because TCP port {endpoint.Port} is already listening. Existing owner: {details}. Stop or inspect that process; the bridge will not terminate it automatically.");
    }

    private static string FindOwnerDetails(int port)
    {
        if (!OperatingSystem.IsWindows()) return "PID unavailable on this platform";
        try
        {
            using var process = Process.Start(new ProcessStartInfo("netstat", "-ano -p tcp")
            {
                UseShellExecute = false,
                RedirectStandardOutput = true,
                CreateNoWindow = true
            });
            var output = process?.StandardOutput.ReadToEnd() ?? string.Empty;
            process?.WaitForExit(2000);
            var line = output.Split(Environment.NewLine).FirstOrDefault(value => value.Contains($":{port}") && value.Contains("LISTENING", StringComparison.OrdinalIgnoreCase));
            if (line is null) return "PID unavailable";
            var pidText = line.Split(' ', StringSplitOptions.RemoveEmptyEntries).LastOrDefault();
            if (!int.TryParse(pidText, out var pid)) return "PID unavailable";
            using var owner = Process.GetProcessById(pid);
            return $"PID {pid} ({owner.ProcessName})";
        }
        catch
        {
            return "PID unavailable";
        }
    }
}
