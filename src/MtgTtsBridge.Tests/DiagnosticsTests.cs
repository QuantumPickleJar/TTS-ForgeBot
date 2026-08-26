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

    private static string CreateTempDirectory()
    {
        var path = Path.Combine(Path.GetTempPath(), $"MtgTtsBridge-diagnostics-{Guid.NewGuid():N}");
        Directory.CreateDirectory(path);
        return path;
    }

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
