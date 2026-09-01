using System.IO.Compression;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Logging.Abstractions;
using MtgTtsBridge.Contracts.Diagnostics;
using MtgTtsBridge.Diagnostics;
using MtgTtsBridge.Forge;

namespace MtgTtsBridge.Tests;

public sealed class DiagnosticsTests
{
    [Fact]
    public void RollingBuffer_IsBoundedAndOrdered()
    {
        var buffer = new DiagnosticRollingBuffer<int>(3);
        buffer.Add(1);
        buffer.Add(2);
        buffer.Add(3);
        buffer.Add(4);

        Assert.Equal(new[] { 2, 3, 4 }, buffer.Snapshot());
    }

    [Fact]
    public void RollingBuffer_ConcurrentWritesRemainBoundedAndReadable()
    {
        var buffer = new DiagnosticRollingBuffer<int>(100);
        Parallel.For(0, 2_000, buffer.Add);

        var snapshot = buffer.Snapshot();
        Assert.True(snapshot.Count <= 100);
        Assert.All(snapshot, value => Assert.InRange(value, 0, 1_999));
    }

    [Fact]
    public async Task Collector_CreatesValidBundleWithMetadataAndMissingOptionalFiles()
    {
        var root = CreateTempDirectory();
        try
        {
            var telemetry = new DiagnosticTelemetryBuffer();
            telemetry.RecordBridgeLog("Information", "test", "activity before capture");
            var adapter = new MockForgeAdapter();
            var state = await adapter.StartSessionAsync(CancellationToken.None);
            telemetry.RecordChoice(new(
                state.CurrentDecision!.DecisionId, "pass_priority")
            {
                SessionId = state.SessionId,
                RequestId = "request-1",
                ClientRuntimeId = "runtime-1",
                ClientRevision = "test-revision",
                Source = "test"
            }, "rejected", "test_rejection", "captured test outcome");
            var identity = new BridgeProcessIdentity();
            var collector = new DiagnosticReportCollector(
                adapter, telemetry, new DiagnosticSelfTestRunner(), new DiagnosticBundleWriter(),
                new DiagnosticOptions { ReportDirectory = root }, identity,
                NullLogger<DiagnosticReportCollector>.Instance);

            var result = await collector.CaptureAsync(new DiagnosticReportRequestDto(
                Summary: "../../unsafe text that must stay content",
                Category: "Crash/error",
                SessionId: state.SessionId,
                DecisionId: state.CurrentDecision.DecisionId,
                ClientRuntimeId: "runtime-1",
                ClientRevision: "tts-test",
                LastAppliedEventSequence: 0,
                Turn: 6,
                Phase: "Combat"), CancellationToken.None);

            Assert.True(result.Success, result.Message);
            Assert.StartsWith(Path.GetFullPath(root), result.ReportPath!, StringComparison.OrdinalIgnoreCase);
            Assert.True(File.Exists(result.ReportPath));
            using var zip = ZipFile.OpenRead(result.ReportPath!);
            var names = zip.Entries.Select(entry => entry.FullName).ToHashSet(StringComparer.Ordinal);
            Assert.Contains("report.json", names);
            Assert.Contains("report.txt", names);
            Assert.Contains("state/bridge-health.json", names);
            Assert.Contains("state/forge-state.json", names);
            Assert.Contains("state/tts-state.json", names);
            Assert.Contains("self-test/results.json", names);
            Assert.Contains("self-test/results.txt", names);
            Assert.DoesNotContain("state/forge-snapshot.json", names);
            Assert.DoesNotContain("../../unsafe text that must stay content", Directory.EnumerateFiles(Directory.GetParent(root)!.FullName, "*", SearchOption.TopDirectoryOnly).Select(Path.GetFileName));

            var manifestEntry = zip.GetEntry("report.json");
            Assert.NotNull(manifestEntry);
            using var manifestStream = manifestEntry!.Open();
            using var manifest = JsonDocument.Parse(manifestStream);
            Assert.Equal(result.ReportId, manifest.RootElement.GetProperty("reportId").GetString());
            Assert.Equal(BridgeProcessIdentity.Revision, manifest.RootElement.GetProperty("bridgeRevision").GetString());
            Assert.True(manifest.RootElement.GetProperty("includedFiles").GetArrayLength() >= 5);
            Assert.Contains("report.json", manifest.RootElement.GetProperty("includedFiles").EnumerateArray().Select(item => item.GetString()));
            Assert.Contains("report.txt", manifest.RootElement.GetProperty("includedFiles").EnumerateArray().Select(item => item.GetString()));
            Assert.True(manifest.RootElement.GetProperty("missingFiles").TryGetProperty("state/forge-snapshot.json", out _));
        }
        finally { TryDelete(root); }
    }

    [Fact]
    public async Task Collector_GivesDistinctPathsForRapidCaptures()
    {
        var root = CreateTempDirectory();
        try
        {
            var adapter = new MockForgeAdapter();
            await adapter.StartSessionAsync(CancellationToken.None);
            var collector = new DiagnosticReportCollector(
                adapter, new DiagnosticTelemetryBuffer(), new DiagnosticSelfTestRunner(), new DiagnosticBundleWriter(),
                new DiagnosticOptions { ReportDirectory = root }, new BridgeProcessIdentity(),
                NullLogger<DiagnosticReportCollector>.Instance);
            var first = await collector.CaptureAsync(new DiagnosticReportRequestDto(), CancellationToken.None);
            var second = await collector.CaptureAsync(new DiagnosticReportRequestDto(), CancellationToken.None);

            Assert.True(first.Success, first.Message);
            Assert.True(second.Success, second.Message);
            Assert.NotEqual(first.ReportId, second.ReportId);
            Assert.NotEqual(first.ReportPath, second.ReportPath);
        }
        finally { TryDelete(root); }
    }

    [Fact]
    public void SelfTests_SerializeStructuredChecks()
    {
        var result = new DiagnosticSelfTestRunner().Run(
            null, null, null, new DiagnosticReportRequestDto(SessionId: "tts-session"), new BridgeProcessIdentity());
        var json = JsonSerializer.Serialize(result, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase });

        Assert.Contains("\"checks\"", json);
        Assert.Contains("active_session_exists", json);
        Assert.Contains("unavailable", json);
    }

    [Fact]
    public async Task DiagnosticEndpoint_ReturnsIdentityAndPath()
    {
        using var factory = new TestWebApplicationFactory();
        using var client = factory.CreateClient();
        var start = await client.PostAsync("/api/v1/session/start", null);
        var session = await start.Content.ReadFromJsonAsync<MtgTtsBridge.Contracts.State.SessionStartResponseDto>();

        var response = await client.PostAsJsonAsync("/api/v1/diagnostics/report", new DiagnosticReportRequestDto(
            Summary: "Blocker remained in battlefield row",
            Category: "Combat",
            SessionId: session!.SessionId,
            DecisionId: session.CurrentDecision?.DecisionId,
            ClientRuntimeId: "test-runtime",
            ClientRevision: "test-revision",
            LastAppliedEventSequence: 0,
            Turn: 6,
            Phase: "Combat"));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<DiagnosticReportResponseDto>();
        Assert.NotNull(body);
        Assert.True(body!.Success);
        Assert.False(string.IsNullOrWhiteSpace(body.ReportId));
        Assert.True(File.Exists(body.ReportPath));
    }

    [Fact]
    public async Task DiagnosticCapture_DoesNotBlockDecisionEventOrChoiceRequests()
    {
        using var factory = new TestWebApplicationFactory();
        using var client = factory.CreateClient();
        var sessionId = await StartSessionForDiagnosticsAsync(client);

        var reportTask = client.PostAsJsonAsync("/api/v1/diagnostics/report",
            new DiagnosticReportRequestDto(SessionId: sessionId, Category: "Gameplay sync"));
        var eventsTask = client.GetAsync("/api/v1/events?after=0");
        var decisionTask = client.GetAsync("/api/v1/decision");
        var choiceTask = client.PostAsJsonAsync("/api/v1/choice",
            ChoiceForDiagnostics(sessionId, "decision-1-main", "pass_priority"));

        var responses = await Task.WhenAll(reportTask, eventsTask, decisionTask, choiceTask)
            .WaitAsync(TimeSpan.FromSeconds(10));

        Assert.Equal(HttpStatusCode.OK, responses[0].StatusCode);
        Assert.Equal(HttpStatusCode.OK, responses[1].StatusCode);
        Assert.InRange((int)responses[2].StatusCode, 200, 499);
        Assert.InRange((int)responses[3].StatusCode, 200, 499);
    }

    [Fact]
    public async Task DiagnosticEndpoint_ReturnsUsefulFailureWhenOutputCannotBeCreated()
    {
        var blockingFile = Path.Combine(Path.GetTempPath(), $"MtgTtsBridge-report-block-{Guid.NewGuid():N}");
        await File.WriteAllTextAsync(blockingFile, "not a directory");
        try
        {
            using var factory = new TestWebApplicationFactory(blockingFile);
            using var client = factory.CreateClient();
            var response = await client.PostAsJsonAsync("/api/v1/diagnostics/report", new DiagnosticReportRequestDto(Summary: "capture failure"));

            Assert.Equal(HttpStatusCode.InternalServerError, response.StatusCode);
            var body = await response.Content.ReadFromJsonAsync<DiagnosticReportFailureDto>();
            Assert.Equal("diagnostic_capture_failed", body?.ErrorCode);
            Assert.Contains("failed", body?.Message, StringComparison.OrdinalIgnoreCase);
        }
        finally { TryDelete(blockingFile); }
    }

    [Fact]
    public async Task PerformanceCapture_WritesBoundedCompactDirectZipAndNoStagingDirectory()
    {
        var root = CreateTempDirectory();
        try
        {
            var adapter = new MockForgeAdapter();
            var state = await adapter.StartSessionAsync(CancellationToken.None);
            var sampler = new ProcessSampler(4);
            sampler.SampleOnce();
            var collector = new DiagnosticReportCollector(
                adapter, new DiagnosticTelemetryBuffer(), new DiagnosticSelfTestRunner(), new DiagnosticBundleWriter(),
                new DiagnosticOptions { ReportDirectory = root, PerformanceReportMaxBytes = 32 * 1024 },
                new BridgeProcessIdentity(), NullLogger<DiagnosticReportCollector>.Instance, sampler);

            var result = await collector.CaptureAsync(new DiagnosticReportRequestDto(
                Category: "Performance / Freeze",
                SessionId: state.SessionId,
                PerformanceSummary: new DiagnosticPerformanceSummaryDto(DecisionRenderAttempts: 3, WallClockKind: "Time.time-game"),
                RecentTtsTrace: [new TtsPerformanceTraceRecordDto(
                    1.25, "decision_render_end", DurationMs: 321.5, CpuDurationMs: 321.5,
                    WallDurationMs: 500.25, WallClockKind: "Time.time-game")],
                DiagnosticCaptureLifecycle: [new DiagnosticCaptureLifecycleRecordDto(
                    1.25, "DIAG_CAPTURE_POSTCHECK", Token: 7, SessionId: state.SessionId,
                    DecisionId: "decision-1", EventPolling: true, EventPollScheduled: true)]),
                CancellationToken.None);

            Assert.True(result.Success, result.Message);
            Assert.NotNull(result.ReportPath);
            Assert.True(new FileInfo(result.ReportPath!).Length <= 32 * 1024);
            Assert.DoesNotContain(Directory.EnumerateDirectories(root), path => Path.GetFileName(path).StartsWith(".capture-", StringComparison.Ordinal));
            using var zip = ZipFile.OpenRead(result.ReportPath!);
            foreach (var required in new[]
            {
                "report.json", "report.txt", "perf/summary.json", "perf/tts-trace.jsonl", "perf/process-samples.jsonl",
                "diagnostics/capture-lifecycle.jsonl",
                "state/bridge-health.json", "state/current-decision.json", "protocol/recent-events.jsonl",
                "protocol/recent-choices.jsonl", "protocol/recent-requests.jsonl", "logs/recent-bridge.log",
                "logs/recent-forge-stdout.log", "logs/recent-forge-stderr.log"
            }) Assert.NotNull(zip.GetEntry(required));
            var summary = zip.GetEntry("perf/summary.json")!;
            using var summaryReader = new StreamReader(summary.Open());
            var compact = await summaryReader.ReadToEndAsync();
            Assert.DoesNotContain("\n", compact);
            Assert.Contains("decisionRenderAttempts", compact);
            Assert.Contains("wallClockKind", compact);
            var trace = zip.GetEntry("perf/tts-trace.jsonl")!;
            using var traceReader = new StreamReader(trace.Open());
            var traceText = await traceReader.ReadToEndAsync();
            Assert.Contains("cpuDurationMs", traceText);
            Assert.Contains("wallDurationMs", traceText);
            var captureLifecycle = zip.GetEntry("diagnostics/capture-lifecycle.jsonl")!;
            using var captureLifecycleReader = new StreamReader(captureLifecycle.Open());
            var captureLifecycleText = await captureLifecycleReader.ReadToEndAsync();
            Assert.Contains("DIAG_CAPTURE_POSTCHECK", captureLifecycleText);
            var manifest = zip.GetEntry("report.json")!;
            using var manifestDocument = await JsonDocument.ParseAsync(manifest.Open());
            Assert.True(manifestDocument.RootElement.GetProperty("includedFiles").GetArrayLength() >= 13);
        }
        finally { TryDelete(root); }
    }

    [Fact]
    public async Task PerformanceRetention_DeletesOnlyStrictCollectorOwnedReports()
    {
        var root = CreateTempDirectory();
        try
        {
            var old = Path.Combine(root, "ForgeBot-Performance-20200101-010101-abcd.zip");
            var newer = Path.Combine(root, "ForgeBot-Performance-20200102-010101-abce.zip");
            await File.WriteAllTextAsync(old, "old");
            await File.WriteAllTextAsync(newer, "newer");
            File.SetLastWriteTimeUtc(old, DateTime.UtcNow.AddMinutes(-2));
            File.SetLastWriteTimeUtc(newer, DateTime.UtcNow.AddMinutes(-1));
            var unrelated = Path.Combine(root, "ForgeBot-Performance-user-export.zip");
            await File.WriteAllTextAsync(unrelated, "keep");

            var adapter = new MockForgeAdapter();
            await adapter.StartSessionAsync(CancellationToken.None);
            var collector = new DiagnosticReportCollector(
                adapter, new DiagnosticTelemetryBuffer(), new DiagnosticSelfTestRunner(), new DiagnosticBundleWriter(),
                new DiagnosticOptions { ReportDirectory = root, PerformanceReportRetentionCount = 2 },
                new BridgeProcessIdentity(), NullLogger<DiagnosticReportCollector>.Instance);
            var result = await collector.CaptureAsync(new DiagnosticReportRequestDto(Category: "Performance"), CancellationToken.None);

            Assert.True(result.Success, result.Message);
            Assert.False(File.Exists(old));
            Assert.True(File.Exists(newer));
            Assert.True(File.Exists(unrelated));
        }
        finally { TryDelete(root); }
    }

    [Fact]
    public void ProcessSampler_RemainsUsableWhenExternalProcessesAreAbsent()
    {
        using var sampler = new ProcessSampler(3);
        sampler.SampleOnce();
        sampler.SampleOnce();
        Assert.True(sampler.Snapshot().Count <= 3);
        Assert.Contains(sampler.Snapshot(), sample => sample.Role == "bridge");
    }

    private static string CreateTempDirectory()
    {
        var path = Path.Combine(Path.GetTempPath(), $"MtgTtsBridge-diagnostics-{Guid.NewGuid():N}");
        Directory.CreateDirectory(path);
        return path;
    }

    private static async Task<string> StartSessionForDiagnosticsAsync(HttpClient client)
    {
        var response = await client.PostAsync("/api/v1/session/start", null);
        response.EnsureSuccessStatusCode();
        var body = await response.Content.ReadFromJsonAsync<MtgTtsBridge.Contracts.State.SessionStartResponseDto>();
        return body!.SessionId;
    }

    private static MtgTtsBridge.Contracts.Actions.ChoiceRequestDto ChoiceForDiagnostics(
        string sessionId, string decisionId, string actionId) =>
        new(decisionId, actionId)
        {
            SessionId = sessionId,
            RequestId = $"diagnostic-concurrency-{Guid.NewGuid():N}",
            ClientRuntimeId = "diagnostic-test-runtime",
            ClientRevision = "diagnostic-test",
            Source = "diagnostic-concurrency-test"
        };

    private static void TryDelete(string path)
    {
        try
        {
            if (Directory.Exists(path)) Directory.Delete(path, true);
            else if (File.Exists(path)) File.Delete(path);
        }
        catch { }
    }
}
