namespace MtgTtsBridge.Diagnostics;

public sealed class DiagnosticOptions
{
    public string ReportDirectory { get; set; } = Path.Combine(Environment.CurrentDirectory, "BugReports");
}
