using System.Diagnostics;

namespace MtgTtsBridge.Diagnostics;

public sealed record ProcessSample(
    DateTimeOffset TimestampUtc,
    string Role,
    int ProcessId,
    double? TotalCpuMilliseconds,
    double? CpuDeltaMilliseconds,
    long? WorkingSetBytes,
    long? PrivateBytes,
    int? ThreadCount,
    int? HandleCount);

/// <summary>
/// Cheap, in-memory process observations for freeze reports. It intentionally
/// does not inspect modules, WMI, stacks, or any other expensive process data.
/// </summary>
public sealed class ProcessSampler : IDisposable
{
    public const int DefaultCapacity = 256;
    public const int DefaultIntervalMilliseconds = 500;

    private readonly DiagnosticRollingBuffer<ProcessSample> _samples;
    private readonly object _sync = new();
    private readonly Dictionary<(string Role, int Pid), double> _previousCpu = [];
    private System.Threading.Timer? _timer;
    private bool _disposed;

    public ProcessSampler(int capacity = DefaultCapacity)
    {
        _samples = new DiagnosticRollingBuffer<ProcessSample>(capacity);
    }

    public IReadOnlyList<ProcessSample> Snapshot() => _samples.Snapshot();

    public void Start()
    {
        lock (_sync)
        {
            if (_disposed || _timer is not null) return;
            _timer = new System.Threading.Timer(static state => ((ProcessSampler)state!).SampleOnce(), this,
                TimeSpan.Zero, TimeSpan.FromMilliseconds(DefaultIntervalMilliseconds));
        }
    }

    public void SampleOnce()
    {
        if (_disposed) return;

        foreach (var process in FindProcesses("Tabletop Simulator", "TabletopSimulator", "Tabletop Simulator_x64"))
            AddProcess("tts", process);
        foreach (var process in FindProcesses("java", "javaw"))
            AddProcess("forge-java", process);

        // Keep the bridge sample in a bounded buffer even when several
        // external processes are present.  It identifies the recorder's own
        // health and is more useful than letting discovery order evict it.
        AddProcess("bridge", Process.GetCurrentProcess());
    }

    private void AddProcess(string role, Process process)
    {
        try
        {
            process.Refresh();
            var key = (role, process.Id);
            var totalCpu = process.TotalProcessorTime.TotalMilliseconds;
            double? delta = null;
            lock (_sync)
            {
                if (_previousCpu.TryGetValue(key, out var previous)) delta = Math.Max(0, totalCpu - previous);
                _previousCpu[key] = totalCpu;
            }

            _samples.Add(new ProcessSample(
                DateTimeOffset.UtcNow,
                role,
                process.Id,
                totalCpu,
                delta,
                process.WorkingSet64,
                TryGetPrivateBytes(process),
                TryGetInt(() => process.Threads.Count),
                TryGetInt(() => process.HandleCount)));
        }
        catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception or NotSupportedException)
        {
            // Processes can exit between discovery and Refresh. Missing samples
            // are preferable to blocking or making capture fail.
        }
        finally
        {
            if (process.Id != Environment.ProcessId) process.Dispose();
        }
    }

    private static IEnumerable<Process> FindProcesses(params string[] names)
    {
        foreach (var name in names.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            Process[] processes;
            try { processes = Process.GetProcessesByName(name); }
            catch (Exception exception) when (exception is System.ComponentModel.Win32Exception or InvalidOperationException) { continue; }
            foreach (var process in processes) yield return process;
        }
    }

    private static long? TryGetPrivateBytes(Process process)
    {
        try { return process.PrivateMemorySize64; }
        catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception or NotSupportedException) { return null; }
    }

    private static int? TryGetInt(Func<int> read)
    {
        try { return read(); }
        catch (Exception exception) when (exception is InvalidOperationException or System.ComponentModel.Win32Exception or NotSupportedException) { return null; }
    }

    public void Dispose()
    {
        lock (_sync)
        {
            if (_disposed) return;
            _disposed = true;
            _timer?.Dispose();
            _timer = null;
        }
    }
}
