using System.Diagnostics;

namespace MtgTtsBridge;

public sealed class BridgeProcessIdentity
{
    public const string Revision = "2026-08-25-forensic-v9";

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
}
