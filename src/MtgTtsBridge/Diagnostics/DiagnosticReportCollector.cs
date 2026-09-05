using System.IO.Compression;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
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
    DiagnosticSelfTestSummary SelfTests,
    bool Truncated = false,
    long RecordsDropped = 0);

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
    private readonly ProcessSampler _processSampler;

    public DiagnosticReportCollector(
        IForgeAdapter adapter,
        DiagnosticTelemetryBuffer telemetry,
        DiagnosticSelfTestRunner selfTests,
        DiagnosticBundleWriter writer,
        DiagnosticOptions options,
        BridgeProcessIdentity identity,
        ILogger<DiagnosticReportCollector> logger,
        ProcessSampler? processSampler = null)
    {
        _adapter = adapter;
        _telemetry = telemetry;
        _selfTests = selfTests;
        _writer = writer;
        _options = options;
        _identity = identity;
        _logger = logger;
        _processSampler = processSampler ?? new ProcessSampler();
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
            if (!IsPerformanceCapture(request.Category))
                snapshot = await ReadSnapshotAsync(missing, cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException) { throw; }

        var telemetry = _telemetry.Capture();
        var selfTest = _selfTests.Run(state, events, snapshot, request, _identity);
        if (IsPerformanceCapture(request.Category))
            return await CapturePerformanceAsync(request, capturedAt, reportId, state, events, telemetry, selfTest, missing, cancellationToken).ConfigureAwait(false);

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
            WriteOptionalJsonLines(staging, "diagnostics/capture-lifecycle.jsonl",
                request.DiagnosticCaptureLifecycle ?? [], included, missing,
                "No TTS diagnostic capture lifecycle was supplied.");

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

    private Task<DiagnosticCaptureResult> CapturePerformanceAsync(
        DiagnosticReportRequestDto request,
        DateTimeOffset capturedAt,
        string reportId,
        AdapterStateDto? state,
        EventBatchDto? events,
        DiagnosticTelemetrySnapshot telemetry,
        DiagnosticSelfTestResult selfTest,
        Dictionary<string, string> missing,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var root = Path.GetFullPath(_options.ReportDirectory);
        var finalZip = Path.Combine(root, $"ForgeBot-Performance-{reportId}.zip");
        var included = PerformanceFiles.ToList();
        var canary = BuildLandCanary(request, state);
        var summary = request.PerformanceSummary ?? new DiagnosticPerformanceSummaryDto(LandActionCanary: canary);
        if (summary.LandActionCanary is null) summary = summary with { LandActionCanary = canary };
        var processSamples = _processSampler.Snapshot();
        var dropped = 0L;
        var entryBudget = Math.Max(2 * 1024L, _options.PerformanceReportMaxBytes / 16);
        var trace = FitJsonLines(request.RecentTtsTrace ?? [], entryBudget, ref dropped);
        var captureLifecycle = FitJsonLines(request.DiagnosticCaptureLifecycle ?? [], entryBudget, ref dropped);
        var samples = FitJsonLines(processSamples, entryBudget, ref dropped);
        var recentEvents = FitJsonLines(events?.Events ?? [], entryBudget, ref dropped);
        var choices = FitJsonLines(telemetry.Choices, entryBudget, ref dropped);
        var requests = FitJsonLines(telemetry.Protocol, entryBudget, ref dropped);
        var breadcrumbs = FitJsonLines(telemetry.TtsBreadcrumbs, entryBudget, ref dropped);
        var bridgeLog = FitText(FormatBridgeLogs(telemetry.BridgeLogs), entryBudget, ref dropped);
        var forgeStdout = FitText(FormatForgeOutput(telemetry.ForgeOutput, "forge_stdout") ?? string.Empty, entryBudget, ref dropped);
        var forgeStderr = FitText(FormatForgeOutput(telemetry.ForgeOutput, "forge_stderr") ?? string.Empty, entryBudget, ref dropped);
        var truncated = dropped > 0;
        var manifest = new DiagnosticReportManifest(
            reportId, capturedAt, CleanText(request.Summary), CleanText(request.Category),
            BridgeProcessIdentity.Revision, _identity.ProcessInstanceId, _identity.ProcessId, _identity.ProcessStartUtc,
            CleanText(request.ClientRuntimeId), CleanText(request.ClientRevision),
            CleanText(request.SessionId) ?? state?.SessionId,
            state?.CurrentDecision?.DecisionId ?? CleanText(request.DecisionId), state?.CurrentDecision?.Kind,
            request.Turn ?? state?.CurrentDecision?.TurnNumber,
            CleanText(request.Phase) ?? state?.CurrentDecision?.PhaseName,
            CleanText(request.ActivePlayer) ?? state?.CurrentDecision?.ActiveSeatId,
            CleanText(request.PriorityPlayer) ?? state?.CurrentDecision?.PrioritySeatId,
            events?.LatestSequence, request.LastAppliedEventSequence, _adapter.Name, state?.State,
            included, missing,
            new DiagnosticSelfTestSummary(selfTest.PassCount, selfTest.WarningCount, selfTest.FailCount, selfTest.UnavailableCount),
            truncated, dropped);
        var reportText = FormatPerformanceReportText(manifest, summary, processSamples, canary);
        var health = new
        {
            status = state is null ? "unavailable" : state.State == "failed" ? "failed" : "ok",
            adapter = _adapter.Name, adapterState = state?.State, sessionId = state?.SessionId,
            bridgeRevision = BridgeProcessIdentity.Revision, bridgeProcessInstanceId = _identity.ProcessInstanceId,
            processId = _identity.ProcessId, capturedAtUtc = capturedAt, truncated, recordsDropped = dropped
        };
        var currentDecision = state?.CurrentDecision;
        try
        {
            Directory.CreateDirectory(root);
            _writer.WriteZipAtomically(finalZip, archive =>
            {
                DiagnosticBundleWriter.WriteJsonEntry(archive, "report.json", manifest);
                DiagnosticBundleWriter.WriteTextEntry(archive, "report.txt", reportText);
                DiagnosticBundleWriter.WriteJsonEntry(archive, "perf/summary.json", new { summary, processSamples, truncated, recordsDropped = dropped });
                WriteJsonLinesBytes(archive, "perf/tts-trace.jsonl", trace);
                WriteJsonLinesBytes(archive, "diagnostics/capture-lifecycle.jsonl", captureLifecycle);
                WriteJsonLinesBytes(archive, "perf/process-samples.jsonl", samples);
                DiagnosticBundleWriter.WriteJsonEntry(archive, "state/bridge-health.json", health);
                DiagnosticBundleWriter.WriteJsonEntry(archive, "state/current-decision.json", currentDecision);
                WriteJsonLinesBytes(archive, "protocol/recent-events.jsonl", recentEvents);
                WriteJsonLinesBytes(archive, "protocol/recent-choices.jsonl", choices);
                WriteJsonLinesBytes(archive, "protocol/recent-requests.jsonl", requests);
                WriteJsonLinesBytes(archive, "diagnostics/tts-execution-breadcrumbs.jsonl", breadcrumbs);
                DiagnosticBundleWriter.WriteJsonEntry(archive, "state/tts-execution-watchdog.json", telemetry.Watchdog);
                DiagnosticBundleWriter.WriteTextEntry(archive, "logs/recent-bridge.log", bridgeLog);
                DiagnosticBundleWriter.WriteTextEntry(archive, "logs/recent-forge-stdout.log", forgeStdout);
                DiagnosticBundleWriter.WriteTextEntry(archive, "logs/recent-forge-stderr.log", forgeStderr);
            });
            PrunePerformanceReports(root);
            _logger.LogInformation("Performance diagnostic report captured reportId={ReportId} path={ReportPath}", reportId, finalZip);
            return Task.FromResult(new DiagnosticCaptureResult(true, reportId, finalZip, "Performance diagnostic report captured."));
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception exception)
        {
            _logger.LogError(exception, "Performance diagnostic report capture failed reportId={ReportId}", reportId);
            return Task.FromResult(new DiagnosticCaptureResult(false, reportId, null, $"Diagnostic report capture failed: {exception.Message}"));
        }
    }

    private static readonly string[] PerformanceFiles =
    [
        "report.json", "report.txt", "perf/summary.json", "perf/tts-trace.jsonl", "diagnostics/capture-lifecycle.jsonl", "perf/process-samples.jsonl",
        "state/bridge-health.json", "state/current-decision.json", "protocol/recent-events.jsonl",
        "protocol/recent-choices.jsonl", "protocol/recent-requests.jsonl", "logs/recent-bridge.log",
        "logs/recent-forge-stdout.log", "logs/recent-forge-stderr.log",
        "diagnostics/tts-execution-breadcrumbs.jsonl", "state/tts-execution-watchdog.json"
    ];

    private static bool IsPerformanceCapture(string? category) =>
        category?.Contains("performance", StringComparison.OrdinalIgnoreCase) == true
        || category?.Contains("freeze", StringComparison.OrdinalIgnoreCase) == true;

    private static List<byte[]> FitJsonLines<T>(IReadOnlyList<T> values, long budget, ref long dropped)
    {
        var lines = values.Select(value => JsonSerializer.SerializeToUtf8Bytes(value, DiagnosticBundleWriter.CompactJsonOptions)).ToList();
        var kept = new List<byte[]>();
        var size = 0L;
        for (var index = lines.Count - 1; index >= 0; index--)
        {
            var lineSize = lines[index].LongLength + 1;
            if (kept.Count > 0 && size + lineSize > budget) { dropped += index + 1; break; }
            kept.Add(lines[index]);
            size += lineSize;
        }
        kept.Reverse();
        return kept;
    }

    private static string FitText(string text, long budget, ref long dropped)
    {
        var bytes = Encoding.UTF8.GetBytes(text ?? string.Empty);
        if (bytes.LongLength <= budget) return text ?? string.Empty;
        dropped++;
        var start = checked((int)Math.Max(0, bytes.LongLength - budget));
        return Encoding.UTF8.GetString(bytes, start, bytes.Length - start);
    }

    private static void WriteJsonLinesBytes(ZipArchive archive, string path, IReadOnlyList<byte[]> lines)
    {
        using var stream = DiagnosticBundleWriter.CreateSafeEntry(archive, path).Open();
        foreach (var line in lines) { stream.Write(line); stream.WriteByte((byte)'\n'); }
    }

    private void PrunePerformanceReports(string root)
    {
        var keep = Math.Max(1, _options.PerformanceReportRetentionCount);
        var files = Directory.EnumerateFiles(root, "ForgeBot-Performance-*.zip", SearchOption.TopDirectoryOnly)
            .Where(path => Regex.IsMatch(Path.GetFileName(path), @"^ForgeBot-Performance-\d{8}-\d{6}-[0-9a-f]{4}\.zip$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant))
            .OrderByDescending(File.GetLastWriteTimeUtc).ToList();
        foreach (var path in files.Skip(keep))
        {
            try { File.Delete(path); } catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }

    private static DiagnosticLandActionCanaryDto BuildLandCanary(DiagnosticReportRequestDto request, AdapterStateDto? state)
    {
        var decision = state?.CurrentDecision;
        var diagnostic = state?.Diagnostic?.RecentControllerDiagnostics?.Reverse()
            .Select(ParsePriorityDiagnostic).FirstOrDefault(item => item is not null);
        var actions = decision?.Actions ?? [];
        return new DiagnosticLandActionCanaryDto(
            request.Turn ?? decision?.TurnNumber ?? diagnostic?.Turn,
            CleanText(request.Phase) ?? decision?.PhaseName ?? diagnostic?.Phase,
            CleanText(request.ActivePlayer) ?? decision?.ActiveSeatId ?? diagnostic?.ActiveSeatId,
            CleanText(request.PriorityPlayer) ?? decision?.PrioritySeatId ?? diagnostic?.PrioritySeatId,
            diagnostic?.LandCount ?? 0, diagnostic?.InstantCount ?? 0,
            decision?.DecisionId ?? CleanText(request.DecisionId), decision?.Kind,
            actions.Count(action => action.Type == "play_land"),
            actions.Count(action => action.Type == "cast_spell"),
            actions.Any(action => action.Type == "pass_priority"),
            request.PerformanceSummary?.LandActionCanary?.TtsRepresentedPlayLandCount ?? 0,
            request.PerformanceSummary?.LandActionCanary?.TtsRepresentedCastSpellCount ?? 0,
            decision?.EventCursor, request.LastAppliedEventSequence);
    }

    private sealed record ParsedPriorityDiagnostic(int Turn, string Phase, string? ActiveSeatId, string? PrioritySeatId, int LandCount, int InstantCount);

    private static readonly Regex PriorityDiagnosticHeader = new(
        @"^\[TUI-DIAG priority\]\s+turn=(?<turn>\d+)\s+phase=(?<phase>.+?)\s+active=(?<active>.+?)\s+priority=(?<priority>.+?)\s+isActivePlayersTurn=(?:true|false)\s+hasPriority=(?:true|false)(?<tail>.*)$",
        RegexOptions.CultureInvariant);

    private static ParsedPriorityDiagnostic? ParsePriorityDiagnostic(string line)
    {
        if (!line.StartsWith("[TUI-DIAG priority]", StringComparison.Ordinal)) return null;
        var match = PriorityDiagnosticHeader.Match(line);
        if (!match.Success || !int.TryParse(match.Groups["turn"].Value, out var turn)) return null;
        var tail = match.Groups["tail"].Value;
        return new ParsedPriorityDiagnostic(turn, match.Groups["phase"].Value.Trim(), match.Groups["active"].Value.Trim(), match.Groups["priority"].Value.Trim(),
            CountForgeActions(ReadDiagnosticField(tail, "lands")), CountForgeActions(ReadDiagnosticField(tail, "instants")));
    }

    private static string? ReadDiagnosticField(string tail, string field)
    {
        var match = Regex.Match(tail, $@"\s{Regex.Escape(field)}=(?<value>.*?)(?=\s+\w+=|$)", RegexOptions.CultureInvariant);
        return match.Success ? match.Groups["value"].Value.Trim() : null;
    }

    private static int CountForgeActions(string? value) => string.IsNullOrWhiteSpace(value) || value == "-" ? 0 : Regex.Matches(value, @"#\d+").Count;

    private static string FormatPerformanceReportText(
        DiagnosticReportManifest manifest,
        DiagnosticPerformanceSummaryDto summary,
        IReadOnlyList<ProcessSample> processSamples,
        DiagnosticLandActionCanaryDto canary)
    {
        var worst = new (string Marker, double DurationMs)[]
        {
            ("decision_render", summary.WorstRenderDurationMs),
            ("clear_highlights", summary.WorstClearHighlightsDurationMs),
            ("prepared_presentation", summary.WorstPreparedPresentationDurationMs),
            ("candidate_collection", summary.WorstCandidateCollectionDurationMs),
            ("action_matching", summary.WorstActionMatchingDurationMs),
            ("ui_flush", summary.WorstUiFlushDurationMs),
            ("snapshot_reconcile", summary.WorstSnapshotReconcileDurationMs)
        }.OrderByDescending(item => item.DurationMs).First();
        var builder = new StringBuilder();
        builder.AppendLine("Freeze/performance capture");
        builder.AppendLine();
        builder.AppendLine("Current:");
        builder.AppendLine($"  turn {manifest.Turn?.ToString() ?? "?"}");
        builder.AppendLine($"  phase {manifest.Phase ?? "?"}");
        builder.AppendLine($"  DecisionId {manifest.CurrentDecisionId ?? "?"}");
        builder.AppendLine($"  decision kind {manifest.CurrentDecisionKind ?? "?"}");
        builder.AppendLine($"  Forge/TTS event cursors {manifest.LastForgeEventSequence?.ToString() ?? "?"}/{manifest.LastTtsAppliedEventSequence?.ToString() ?? "?"}");
        builder.AppendLine($"Worst recent TTS operation: {worst.Marker} {worst.DurationMs:0.###} ms");
        builder.AppendLine();
        builder.AppendLine($"Decision rendering: attempts={summary.DecisionRenderAttempts} executed={summary.DecisionRenderExecuted} identical skipped={summary.DecisionRenderSkippedIdentical}");
        builder.AppendLine($"UI: attempts={summary.UiAttributeAttempts} writes={summary.UiAttributeWrites} skipped={summary.UiAttributeSkippedIdentical}");
        builder.AppendLine($"Process peaks: TTS working set={Peak(processSamples, "tts", s => s.WorkingSetBytes)} CPU delta={Peak(processSamples, "tts", s => s.CpuDeltaMilliseconds)}; Bridge working set={Peak(processSamples, "bridge", s => s.WorkingSetBytes)}; Forge working set={Peak(processSamples, "forge-java", s => s.WorkingSetBytes)}");
        builder.AppendLine();
        builder.AppendLine("Land-action canary:");
        builder.AppendLine($"  most recent Turn-1 Main-1 priority: turn={canary.TurnNumber?.ToString() ?? "?"} phase={canary.Phase ?? "?"}");
        builder.AppendLine($"  Forge lands={canary.ForgeLegalLandCount} instants/flash={canary.ForgeLegalInstantFlashCount}");
        builder.AppendLine($"  Decision play_land={canary.DecisionPlayLandCount} cast_spell={canary.DecisionCastSpellCount} pass_priority={canary.DecisionPassPriorityPresent}");
        builder.AppendLine($"  TTS represented play_land={canary.TtsRepresentedPlayLandCount} cast_spell={canary.TtsRepresentedCastSpellCount}");
        builder.AppendLine($"  truncated={manifest.Truncated} recordsDropped={manifest.RecordsDropped}");
        return builder.ToString();
    }

    private static string Peak(IReadOnlyList<ProcessSample> samples, string role, Func<ProcessSample, object?> selector)
    {
        var values = samples.Where(sample => sample.Role == role).Select(selector).Where(value => value is not null).ToArray();
        return values.Length == 0 ? "?" : values.Max(value => Convert.ToDouble(value, System.Globalization.CultureInfo.InvariantCulture)).ToString("0.###", System.Globalization.CultureInfo.InvariantCulture);
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
