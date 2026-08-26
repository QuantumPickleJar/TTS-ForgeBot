using System.Text;
using MtgTtsBridge.Contracts.Diagnostics;
using MtgTtsBridge.Contracts.Events;
using MtgTtsBridge.Contracts.State;
using MtgTtsBridge.Forge;

namespace MtgTtsBridge.Diagnostics;

public sealed record DiagnosticCaptureResult(
    bool Success,
    string ReportId,
    string? ReportPath,
    string Message);

public sealed record DiagnosticReportManifest(
    string ReportId,
    DateTimeOffset CapturedAtUtc,
    string? Summary,
    string? Category,
    string BridgeRevision,
    string BridgeProcessInstanceId,
    int BridgeProcessId,
    DateTimeOffset BridgeProcessStartUtc,
    string? ClientRuntimeId,
    string? ClientRevision,
    string? SessionId,
    string? CurrentDecisionId,
    string? CurrentDecisionKind,
    int? Turn,
    string? Phase,
    string? ActivePlayer,
    string? PriorityPlayer,
    long? LastForgeEventSequence,
    long? LastTtsAppliedEventSequence,
    string AdapterName,
    string? AdapterState,
    IReadOnlyList<string> IncludedFiles,
    IReadOnlyDictionary<string, string> MissingFiles,
    DiagnosticSelfTestSummary SelfTests);

public sealed record DiagnosticSelfTestSummary(
    int Pass,
    int Warning,
    int Fail,
    int Unavailable);

/// <summary>Captures current state and pre-capture history without advancing Forge.</summary>
public sealed class DiagnosticReportCollector
{
    private readonly IForgeAdapter _adapter;
    private readonly DiagnosticTelemetryBuffer _telemetry;
    private readonly DiagnosticSelfTestRunner _selfTests;
    private readonly DiagnosticBundleWriter _writer;
    private readonly DiagnosticOptions _options;
    private readonly BridgeProcessIdentity _identity;
    private readonly ILogger<DiagnosticReportCollector> _logger;

    public DiagnosticReportCollector(
        IForgeAdapter adapter,
        DiagnosticTelemetryBuffer telemetry,
        DiagnosticSelfTestRunner selfTests,
        DiagnosticBundleWriter writer,
        DiagnosticOptions options,
        BridgeProcessIdentity identity,
        ILogger<DiagnosticReportCollector> logger)
    {
        _adapter = adapter;
        _telemetry = telemetry;
        _selfTests = selfTests;
        _writer = writer;
        _options = options;
        _identity = identity;
        _logger = logger;
    }

    public async Task<DiagnosticCaptureResult> CaptureAsync(DiagnosticReportRequestDto request, CancellationToken cancellationToken)
    {
        var capturedAt = DateTimeOffset.UtcNow;
        var reportId = $"{capturedAt:yyyyMMdd-HHmmss}-{Guid.NewGuid():N}"[..20];
        AdapterStateDto? state = null;
        EventBatchDto? events = null;
        GameSnapshotDto? snapshot = null;
        var missing = new Dictionary<string, string>(StringComparer.Ordinal);

        try
        {
            state = await ReadStateAsync(missing, cancellationToken).ConfigureAwait(false);
            events = await ReadEventsAsync(missing, cancellationToken).ConfigureAwait(false);
            snapshot = await ReadSnapshotAsync(missing, cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException) { throw; }

        var telemetry = _telemetry.Capture();
        var selfTest = _selfTests.Run(state, events, snapshot, request, _identity);
        var included = new List<string>();
        var root = Path.GetFullPath(_options.ReportDirectory);
        var staging = Path.Combine(root, $".capture-{reportId}-{Guid.NewGuid():N}");
        var finalZip = Path.Combine(root, $"ForgeBot-Bug-{reportId}.zip");
        var temporaryZip = finalZip + ".tmp";

        try
        {
            Directory.CreateDirectory(root);
            Directory.CreateDirectory(staging);

            WriteRequiredJson(staging, "state/bridge-health.json", new
            {
                status = state is null ? "unavailable" : state.State == "failed" ? "failed" : "ok",
                adapter = _adapter.Name,
                adapterState = state?.State,
                sessionId = state?.SessionId,
                diagnostic = state?.Diagnostic,
                bridgeRevision = BridgeProcessIdentity.Revision,
                bridgeProcessInstanceId = _identity.ProcessInstanceId,
                processId = _identity.ProcessId,
                processStartUtc = _identity.ProcessStartUtc,
                capturedAtUtc = capturedAt
            }, included, "state/bridge-health.json");

            WriteOptionalJson(staging, "state/forge-state.json", state, included, missing, "Adapter state was unavailable.");
            WriteOptionalJson(staging, "state/forge-snapshot.json", snapshot, included, missing, "Authoritative embodiment snapshot was unavailable.");
            WriteOptionalJson(staging, "state/current-decision.json", state?.CurrentDecision, included, missing, "No current authoritative decision was available.");
            WriteOptionalJson(staging, "state/tts-state.json", request, included, missing, "TTS context was not supplied.");

            if (events is not null)
                WriteRequiredJsonLines(staging, "protocol/recent-events.jsonl", events.Events, included);
            else
                missing["protocol/recent-events.jsonl"] = "Event history was unavailable.";

            WriteOptionalJsonLines(staging, "protocol/recent-choices.jsonl", telemetry.Choices, included, missing, "No choice telemetry was captured.");
            WriteOptionalJsonLines(staging, "protocol/recent-requests.jsonl", telemetry.Protocol, included, missing, "No protocol telemetry was captured.");
            WriteOptionalText(staging, "logs/bridge.log", FormatBridgeLogs(telemetry.BridgeLogs), included, missing, "No bridge log entries were captured.");
            WriteOptionalText(staging, "logs/forge-stdout.log", FormatForgeOutput(telemetry.ForgeOutput, "forge_stdout"), included, missing, "No Forge stdout was captured.");
            WriteOptionalText(staging, "logs/forge-stderr.log", FormatForgeOutput(telemetry.ForgeOutput, "forge_stderr"), included, missing, "No Forge stderr was captured.");

            WriteRequiredJson(staging, "self-test/results.json", selfTest, included, "self-test/results.json");
            WriteRequiredText(staging, "self-test/results.txt", FormatSelfTests(selfTest), included, "self-test/results.txt");
            // The manifest indexes itself and the human summary even though
            // those two files are serialized immediately after this point.
            included.Add("report.json");
            included.Add("report.txt");

            var manifest = new DiagnosticReportManifest(
                reportId,
                capturedAt,
                CleanText(request.Summary),
                CleanText(request.Category),
                BridgeProcessIdentity.Revision,
                _identity.ProcessInstanceId,
                _identity.ProcessId,
                _identity.ProcessStartUtc,
                CleanText(request.ClientRuntimeId),
                CleanText(request.ClientRevision),
                CleanText(request.SessionId) ?? state?.SessionId,
                state?.CurrentDecision?.DecisionId ?? CleanText(request.DecisionId),
                state?.CurrentDecision?.Kind,
                request.Turn ?? state?.CurrentDecision?.TurnNumber,
                CleanText(request.Phase) ?? state?.CurrentDecision?.PhaseName,
                CleanText(request.ActivePlayer) ?? state?.CurrentDecision?.ActiveSeatId,
                CleanText(request.PriorityPlayer) ?? state?.CurrentDecision?.PrioritySeatId,
                events?.LatestSequence,
                request.LastAppliedEventSequence,
                _adapter.Name,
                state?.State,
                included,
                missing,
                new DiagnosticSelfTestSummary(selfTest.PassCount, selfTest.WarningCount, selfTest.FailCount, selfTest.UnavailableCount));

            WriteRequiredJson(staging, "report.json", manifest, included, "report.json");
            WriteRequiredText(staging, "report.txt", FormatReportText(manifest, selfTest), included, "report.txt");

            _writer.CreateZip(staging, temporaryZip);
            File.Move(temporaryZip, finalZip);
            _logger.LogInformation("Diagnostic report captured reportId={ReportId} path={ReportPath}", reportId, finalZip);
            return new DiagnosticCaptureResult(true, reportId, finalZip, "Diagnostic report captured.");
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception exception)
        {
            try { if (File.Exists(temporaryZip)) File.Delete(temporaryZip); } catch { }
            _logger.LogError(exception, "Diagnostic report capture failed reportId={ReportId}", reportId);
            return new DiagnosticCaptureResult(false, reportId, null, $"Diagnostic report capture failed: {exception.Message}");
        }
        finally
        {
            try { if (Directory.Exists(staging)) Directory.Delete(staging, recursive: true); } catch { }
        }
    }

    private async Task<AdapterStateDto?> ReadStateAsync(Dictionary<string, string> missing, CancellationToken cancellationToken)
    {
        try { return await _adapter.GetStateAsync(cancellationToken).ConfigureAwait(false); }
        catch (Exception exception) when (exception is not OperationCanceledException)
        { missing["state/forge-state.json"] = $"Adapter state read failed: {exception.Message}"; return null; }
    }

    private async Task<EventBatchDto?> ReadEventsAsync(Dictionary<string, string> missing, CancellationToken cancellationToken)
    {
        try { return await _adapter.GetEventsAsync(0, cancellationToken).ConfigureAwait(false); }
        catch (Exception exception) when (exception is not OperationCanceledException)
        { missing["protocol/recent-events.jsonl"] = $"Event history read failed: {exception.Message}"; return null; }
    }

    private async Task<GameSnapshotDto?> ReadSnapshotAsync(Dictionary<string, string> missing, CancellationToken cancellationToken)
    {
        try { return await _adapter.GetSnapshotAsync(cancellationToken).ConfigureAwait(false); }
        catch (Exception exception) when (exception is not OperationCanceledException)
        { missing["state/forge-snapshot.json"] = $"Snapshot read failed: {exception.Message}"; return null; }
    }

    private void WriteRequiredJson(string root, string path, object value, List<string> included, string includedPath)
    {
        _writer.WriteJson(root, path, value);
        if (!included.Contains(includedPath, StringComparer.Ordinal)) included.Add(includedPath);
    }

    private void WriteRequiredJsonLines<T>(string root, string path, IEnumerable<T> values, List<string> included)
    {
        _writer.WriteJsonLines(root, path, values);
        included.Add(path);
    }

    private void WriteRequiredText(string root, string path, string value, List<string> included, string includedPath)
    {
        _writer.WriteText(root, path, value);
        if (!included.Contains(includedPath, StringComparer.Ordinal)) included.Add(includedPath);
    }

    private void WriteOptionalJson(string root, string path, object? value, List<string> included, Dictionary<string, string> missing, string reason)
    {
        if (value is null) { missing[path] = reason; return; }
        try { _writer.WriteJson(root, path, value); included.Add(path); }
        catch (Exception exception) { missing[path] = exception.Message; }
    }

    private void WriteOptionalJsonLines<T>(string root, string path, IReadOnlyList<T> values, List<string> included, Dictionary<string, string> missing, string reason)
    {
        if (values.Count == 0) { missing[path] = reason; return; }
        try { _writer.WriteJsonLines(root, path, values); included.Add(path); }
        catch (Exception exception) { missing[path] = exception.Message; }
    }

    private void WriteOptionalText(string root, string path, string? value, List<string> included, Dictionary<string, string> missing, string reason)
    {
        if (string.IsNullOrEmpty(value)) { missing[path] = reason; return; }
        try { _writer.WriteText(root, path, value); included.Add(path); }
        catch (Exception exception) { missing[path] = exception.Message; }
    }

    private static string FormatBridgeLogs(IReadOnlyList<DiagnosticTelemetryRecord> records) =>
        string.Join(Environment.NewLine, records.Select(item => $"{item.TimestampUtc:O} [{item.Details?["level"]}] {item.Details?["category"]}: {item.Message}")) + (records.Count > 0 ? Environment.NewLine : "");

    private static string? FormatForgeOutput(IReadOnlyList<DiagnosticTelemetryRecord> records, string kind)
    {
        var selected = records.Where(item => item.Kind == kind).ToArray();
        return selected.Length == 0 ? null : string.Join(Environment.NewLine, selected.Select(item => $"{item.TimestampUtc:O} {item.Message}")) + Environment.NewLine;
    }

    private static string FormatSelfTests(DiagnosticSelfTestResult result) =>
        string.Join(Environment.NewLine, result.Checks.Select(item => $"{item.Status.ToUpperInvariant(),-12} {item.Id}: {item.Message}")) + Environment.NewLine;

    private static string FormatReportText(DiagnosticReportManifest manifest, DiagnosticSelfTestResult tests)
    {
        var builder = new StringBuilder();
        builder.AppendLine($"ForgeBot diagnostic report {manifest.ReportId}");
        builder.AppendLine($"Captured: {manifest.CapturedAtUtc:O}");
        builder.AppendLine($"Summary: {manifest.Summary ?? "(none supplied)"}");
        builder.AppendLine($"Category: {manifest.Category ?? "(none supplied)"}");
        builder.AppendLine($"Adapter: {manifest.AdapterName} / {manifest.AdapterState ?? "unavailable"}");
        builder.AppendLine($"Session: {manifest.SessionId ?? "(unavailable)"}");
        builder.AppendLine($"Decision: {manifest.CurrentDecisionId ?? "(none)"} ({manifest.CurrentDecisionKind ?? "n/a"})");
        builder.AppendLine($"Turn/phase: {manifest.Turn?.ToString() ?? "?"} / {manifest.Phase ?? "?"}");
        builder.AppendLine($"Events Forge/TTS: {manifest.LastForgeEventSequence?.ToString() ?? "?"} / {manifest.LastTtsAppliedEventSequence?.ToString() ?? "?"}");
        builder.AppendLine($"Self-tests: {tests.PassCount} pass, {tests.WarningCount} warning, {tests.FailCount} fail, {tests.UnavailableCount} unavailable");
        builder.AppendLine($"Included files: {manifest.IncludedFiles.Count}; missing: {manifest.MissingFiles.Count}");
        return builder.ToString();
    }

    private static string? CleanText(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        var trimmed = value.Trim();
        return trimmed.Length <= 4096 ? trimmed : trimmed[..4096];
    }
}
