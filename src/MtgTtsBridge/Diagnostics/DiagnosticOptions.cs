namespace MtgTtsBridge.Diagnostics;

public sealed class DiagnosticOptions
{
    public string ReportDirectory { get; set; } = Path.Combine(Environment.CurrentDirectory, "BugReports");
    public long PerformanceReportMaxBytes { get; set; } = 2 * 1024 * 1024;
    public int PerformanceReportRetentionCount { get; set; } = 3;
}
