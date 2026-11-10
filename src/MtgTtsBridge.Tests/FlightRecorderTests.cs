using System.IO.Compression;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.Extensions.Options;
using MtgTtsBridge.Contracts.Actions;
using MtgTtsBridge.Contracts.Diagnostics;
using MtgTtsBridge.Contracts.Events;
using MtgTtsBridge.Contracts.State;
using MtgTtsBridge.Diagnostics;
using MtgTtsBridge.Forge;
using Microsoft.Extensions.Logging.Abstractions;

namespace MtgTtsBridge.Tests;

public sealed class FlightRecorderTests
{
    private static readonly JsonSerializerOptions WebJson = new(JsonSerializerDefaults.Web);

    [Fact]
    public async Task OfferedDecisionKeepsCompleteForgeActionSetAndChoiceResultCorrelation()
    {
        var root = CreateTempDirectory();
        var recorder = await StartRecorder(root);
        try
        {
            const string sessionId = "session-offers";
            recorder.RegisterClientRuntime("tts-runtime-1");
            recorder.BeginMatch(sessionId, "bridge-instance-1");
            var decision = CreateDecision(sessionId, "decision-7", 19, 27);
            Assert.True(recorder.RecordDecisionOffered(decision, "bridge-instance-1"));
            var request = new ChoiceRequestDto(decision.DecisionId, "cast:source-81")
            {
                SessionId = sessionId,
                RequestId = "request-3",
                ClientRuntimeId = "tts-runtime-1",
                Source = "physical-card"
            };
            Assert.True(recorder.RecordChoiceRequested(request));
            Assert.True(recorder.RecordChoiceResult(request, "accepted", new
            {
                authoritative = true,
                committedEvent = new { eventCursor = 28, forgeSequence = 28 },
                currentDecision = new { decisionId = "decision-followup", kind = "target_selection" }
            }));
            await recorder.FlushAsync();
            await recorder.StopRecordingAsync();

            var records = ReadRecords(root, sessionId);
            var offered = Assert.Single(records.Where(record => record.Type == "decision_offered"));
            var actions = offered.Payload.GetProperty("actions").EnumerateArray().ToArray();
            Assert.Equal(new[] { "cast:source-81", "pass:19" }, actions.Select(action => action.GetProperty("actionId").GetString()));
            Assert.Equal("forge:session-offers:81", actions[0].GetProperty("sourceCardInstanceId").GetString());
            Assert.Equal("{X}{R}", actions[0].GetProperty("displayManaCost").GetString());
            Assert.Equal("forge-object:81", actions[0].GetProperty("objectIdentity").GetString());
            Assert.Equal("cast", actions[0].GetProperty("provenance").GetProperty("actionKind").GetString());
            Assert.Equal(27L, offered.ForgeSequence);
            Assert.Equal(19L, offered.EventCursor);
            Assert.True(offered.Payload.GetProperty("allowsCancel").GetBoolean());
            Assert.Equal("payment:81", offered.Payload.GetProperty("paymentContext").GetProperty("paymentContextId").GetString());
            Assert.Equal("sacrifice", offered.Payload.GetProperty("paymentContext").GetProperty("costComponents")[0].GetProperty("kind").GetString());
            Assert.False(string.IsNullOrWhiteSpace(offered.BridgeProcessInstanceId));
            Assert.False(string.IsNullOrWhiteSpace(offered.BridgeBuildIdentity));

            var requested = Assert.Single(records.Where(record => record.Type == "choice_requested"));
            Assert.Equal(offered.DecisionId, requested.DecisionId);
            Assert.Equal("cast:source-81", requested.Payload.GetProperty("actionId").GetString());
            Assert.Equal("physical-card", requested.Payload.GetProperty("source").GetString());
            var result = Assert.Single(records.Where(record => record.Type == "choice_result"));
            Assert.Equal(requested.DecisionId, result.DecisionId);
            Assert.Equal("accepted", result.Payload.GetProperty("outcome").GetString());
            Assert.Equal(28, result.Payload.GetProperty("result").GetProperty("committedEvent").GetProperty("eventCursor").GetInt32());
            Assert.Equal("decision-followup", result.Payload.GetProperty("result").GetProperty("currentDecision").GetProperty("decisionId").GetString());
        }
        finally { await DisposeRecorder(recorder); DeleteTempDirectory(root); }
    }

    [Fact]
    public async Task DuplicateDecisionPollingIsSummarizedWithoutDuplicateGenerations()
    {
        var root = CreateTempDirectory();
        var recorder = await StartRecorder(root);
        try
        {
            var decision = CreateDecision("session-polls", "decision-repeat", 4, 8);
            recorder.ObserveDecisionDelivery(decision, "bridge-instance");
            recorder.ObserveDecisionDelivery(decision, "bridge-instance");
            recorder.ObserveDecisionDelivery(decision, "bridge-instance");
            await recorder.StopRecordingAsync();

            var records = ReadRecords(root, "session-polls");
            Assert.Single(records.Where(record => record.Type == "decision_offered"));
            var summary = Assert.Single(records.Where(record => record.Type == "decision_delivery_summary"));
            Assert.Equal(3, summary.Payload.GetProperty("observationCount").GetInt32());
            Assert.Equal("decision-repeat", summary.DecisionId);
        }
        finally { await DisposeRecorder(recorder); DeleteTempDirectory(root); }
    }

    [Fact]
    public async Task DecisionGenerationCanBeRetriedAfterAQueuePayloadDrop()
    {
        var root = CreateTempDirectory();
        var recorder = await StartRecorder(root, maxRecordPayloadBytes: 4096);
        try
        {
            var decision = CreateDecision("session-decision-retry", "decision-retry", 4, 8);
            var tooLarge = decision with
            {
                Actions = [new LegalActionDto("cast:large", "cast_spell", new string('x', 10_000), true, null, null)]
            };
            Assert.False(recorder.RecordDecisionOffered(tooLarge));
            Assert.True(recorder.RecordDecisionOffered(decision));
            await recorder.StopRecordingAsync();

            var records = ReadRecords(root, "session-decision-retry");
            var offered = Assert.Single(records.Where(record => record.Type == "decision_offered"));
            Assert.Equal(2, offered.Payload.GetProperty("actions").GetArrayLength());
            Assert.Contains(records, record => record.Type == "recorder_loss"
                && record.Payload.GetProperty("droppedRecords").GetInt64() == 1);
        }
        finally { await DisposeRecorder(recorder); DeleteTempDirectory(root); }
    }

    [Fact]
    public async Task AuthoritativeEventsPhysicalObservationsAndChoicesKeepCausalityOrder()
    {
        var root = CreateTempDirectory();
        var recorder = await StartRecorder(root);
        try
        {
            const string sessionId = "session-causality";
            recorder.RegisterClientRuntime("tts-runtime");
            recorder.BeginMatch(sessionId, "bridge-instance");
            recorder.RecordDecisionOffered(CreateDecision(sessionId, "decision-cause", 11, 33), "bridge-instance");
            recorder.RecordForgeEvent(CreateEvent(1, "phase_changed", sessionId, forgeSequence: 33), sessionId);
            recorder.RecordTtsBreadcrumb(new TtsExecutionBreadcrumb("tts-runtime", sessionId, 4, 12, 1,
                "phase_changed", "EVENT_ENTER", "authoritative_event", "event:1", "forge:session-causality:2",
                "library", "battlefield", 1.2, DateTimeOffset.UtcNow, "abcd12", [1, 2, 3], [0, 180, 0]));
            var request = new ChoiceRequestDto("decision-cause", "pass:11")
            {
                SessionId = sessionId, RequestId = "request-cause", ClientRuntimeId = "tts-runtime", Source = "automation"
            };
            recorder.RecordChoiceRequested(request);
            recorder.RecordForgeEvent(CreateEvent(2, "turn_changed", sessionId, forgeSequence: 34), sessionId);
            await recorder.StopRecordingAsync();

            var records = ReadRecords(root, sessionId);
            Assert.Equal(records.Select(record => record.Sequence).Order().ToArray(), records.Select(record => record.Sequence).ToArray());
            var timeline = records.Select(record => record.Type).ToArray();
            Assert.True(Array.IndexOf(timeline, "decision_offered") < Array.IndexOf(timeline, "forge_event"));
            Assert.True(Array.IndexOf(timeline, "forge_event") < Array.IndexOf(timeline, "tts_observation"));
            Assert.True(Array.IndexOf(timeline, "tts_observation") < Array.IndexOf(timeline, "choice_requested"));
            Assert.True(Array.LastIndexOf(timeline, "forge_event") > Array.IndexOf(timeline, "choice_requested"));
            var physical = Assert.Single(records.Where(record => record.Type == "tts_observation"));
            Assert.Equal("abcd12", physical.Payload.GetProperty("ttsGuid").GetString());
            Assert.Equal(180, physical.Payload.GetProperty("rotation")[1].GetDouble());
            Assert.Equal("automation", records.Single(record => record.Type == "choice_requested")
                .Payload.GetProperty("source").GetString());
        }
        finally { await DisposeRecorder(recorder); DeleteTempDirectory(root); }
    }

    [Fact]
    public async Task CheckpointsRetainEnoughAuthoritativeStateToAnchorTimeline()
    {
        var root = CreateTempDirectory();
        var recorder = await StartRecorder(root);
        try
        {
            const string sessionId = "session-checkpoint";
            var snapshot = new GameSnapshotDto(sessionId, 40, "test-checkpoint", [], [], EventCursor: 17,
                TurnNumber: 5, ActiveSeatId: "forge-player-2", PrioritySeatId: "forge-player-1", Phase: "Main 1");
            recorder.BeginMatch(sessionId, "bridge-instance");
            Assert.True(recorder.RecordSnapshot(snapshot, "initial"));
            recorder.RecordForgeEvent(CreateEvent(18, "phase_changed", sessionId, forgeSequence: 41), sessionId);
            await recorder.StopRecordingAsync();

            var excerpt = recorder.CaptureExcerpt(sessionId);
            Assert.False(excerpt.Missing);
            var checkpoint = Assert.Single(excerpt.CheckpointRecords);
            using var parsed = JsonDocument.Parse(checkpoint);
            var stored = parsed.RootElement.GetProperty("payload").GetProperty("snapshot");
            Assert.Equal(5, stored.GetProperty("turnNumber").GetInt32());
            Assert.Equal("Main 1", stored.GetProperty("phase").GetString());
            Assert.Equal(17, parsed.RootElement.GetProperty("eventCursor").GetInt64());
            Assert.Equal(4, excerpt.RecentRecords.Count);
        }
        finally { await DisposeRecorder(recorder); DeleteTempDirectory(root); }
    }

    [Fact]
    public async Task InterruptedSegmentRecoveryKeepsEarlierBytesAndDropsCorruptTail()
    {
        var root = CreateTempDirectory();
        var recorder = await StartRecorder(root);
        try
        {
            const string sessionId = "session-crash";
            recorder.BeginMatch(sessionId, "bridge-instance");
            recorder.RecordForgeEvent(CreateEvent(1, "phase_changed", sessionId, forgeSequence: 1), sessionId);
            recorder.RecordForgeEvent(CreateEvent(2, "priority_changed", sessionId, forgeSequence: 2), sessionId);
            await recorder.StopRecordingAsync();
            var sessionDirectory = Path.Combine(root, sessionId);
            var firstSegment = Directory.GetFiles(sessionDirectory, "segment-*.jsonl").Single();
            var beforeHash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(firstSegment)));
            var interrupted = Path.Combine(sessionDirectory, "segment-000002.jsonl.open");
            File.Copy(firstSegment, interrupted);
            await File.AppendAllTextAsync(interrupted, "{\"schemaVersion\":1,broken-tail");

            var recoveredRecorder = await StartRecorder(root);
            try
            {
                await recoveredRecorder.FlushAsync();
                var recoveredPath = Path.Combine(sessionDirectory, "segment-000002.jsonl");
                Assert.True(File.Exists(recoveredPath));
                Assert.Equal(beforeHash, Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(firstSegment))));
                using var metadata = JsonDocument.Parse(await File.ReadAllTextAsync(Path.ChangeExtension(recoveredPath, ".meta.json")));
                Assert.True(metadata.RootElement.GetProperty("recoveredAfterInterruption").GetBoolean());
                Assert.Equal(4, File.ReadLines(recoveredPath).Count());
                using var recoveryManifest = JsonDocument.Parse(await File.ReadAllTextAsync(Path.Combine(sessionDirectory, "manifest.json")));
                Assert.True(recoveryManifest.RootElement.GetProperty("missingData").GetBoolean());
                Assert.False(recoveryManifest.RootElement.GetProperty("complete").GetBoolean());
            }
            finally { await DisposeRecorder(recoveredRecorder); }
        }
        finally { await DisposeRecorder(recorder); DeleteTempDirectory(root); }
    }

    [Fact]
    public async Task DiskLimitAndRetentionRemoveOldMatchesWithoutDeletingCurrentMatch()
    {
        var root = CreateTempDirectory();
        var oldMatch = Path.Combine(root, "old-match");
        Directory.CreateDirectory(oldMatch);
        await File.WriteAllBytesAsync(Path.Combine(oldMatch, "old.bin"), new byte[96 * 1024]);
        var recorder = await StartRecorder(root, maxDiskBytes: 64 * 1024, retentionMatchCount: 1);
        try
        {
            recorder.BeginMatch("current-match", "bridge-instance");
            recorder.RecordForgeEvent(CreateEvent(1, "phase_changed", "current-match", 1), "current-match");
            await recorder.StopRecordingAsync();

            Assert.False(Directory.Exists(oldMatch));
            Assert.True(Directory.Exists(Path.Combine(root, "current-match")));
            Assert.False(recorder.GetStatus().StorageFaulted);
        }
        finally { await DisposeRecorder(recorder); DeleteTempDirectory(root); }
    }

    [Fact]
    public async Task BoundedQueueBackpressureIsObservableAndLossIsRecorded()
    {
        var root = CreateTempDirectory();
        var recorder = await StartRecorder(root, queueCapacity: 32);
        try
        {
            recorder.BeginMatch("session-pressure", "bridge-instance");
            var payload = new { block = new string('x', 32 * 1024) };
            for (var index = 0; index < 20_000; index++)
                recorder.RecordTtsEvent("session-pressure", "runtime", "physical_probe", null, payload, index);
            Assert.InRange(recorder.GetStatus().QueueDepth, 0, 32);
            Assert.InRange(recorder.GetStatus().QueuedPayloadBytes, 0, 32 * 1024 * 1024);
            Assert.True(recorder.GetStatus().RecordsDropped > 0);
            await recorder.StopRecordingAsync();
            var records = ReadRecords(root, "session-pressure");
            Assert.Contains(records, record => record.Type == "recorder_loss"
                && record.Payload.GetProperty("droppedRecords").GetInt64() > 0);
            using var manifest = JsonDocument.Parse(await File.ReadAllTextAsync(Path.Combine(root, "session-pressure", "manifest.json")));
            Assert.True(manifest.RootElement.GetProperty("missingData").GetBoolean());
            Assert.False(manifest.RootElement.GetProperty("complete").GetBoolean());
        }
        finally { await DisposeRecorder(recorder); DeleteTempDirectory(root); }
    }

    [Fact]
    public async Task OversizedTtsObservationIsDroppedWithoutEnteringTheBoundedQueue()
    {
        var root = CreateTempDirectory();
        var recorder = await StartRecorder(root);
        try
        {
            recorder.BeginMatch("session-oversize", "bridge-instance");
            var payload = JsonSerializer.SerializeToElement(new { data = new string('x', 70 * 1024) }, WebJson);
            Assert.False(recorder.RecordTtsEvent("session-oversize", "runtime", "large_observation", null, payload));
            Assert.InRange(recorder.GetStatus().QueueDepth, 0, 256);
            Assert.Equal(1, recorder.GetStatus().RecordsDropped);
            await recorder.StopRecordingAsync();
            Assert.Contains(ReadRecords(root, "session-oversize"), record => record.Type == "recorder_loss"
                && record.Payload.GetProperty("droppedRecords").GetInt64() == 1);
        }
        finally { await DisposeRecorder(recorder); DeleteTempDirectory(root); }
    }

    [Fact]
    public void ExternalExportRedactsDecisionIdentityAndHiddenZonesButPreservesRecordIntegrity()
    {
        var decisionPayload = JsonSerializer.SerializeToElement(new
        {
            decisionId = "decision-secret",
            prompt = "Choose Secret Hero",
            actions = new[] { new { actionId = "cast:secret", displayName = "Secret Hero", cardInstanceId = "card-secret" } }
        }, WebJson);
        var decision = CreateEnvelope("decision_offered", decisionPayload, "decision-secret");
        var redactedDecision = FlightRecorderService.RedactForExternalExport(decision);
        Assert.True(redactedDecision.PrivacyRedacted);
        Assert.True(FlightRecorderService.VerifyEnvelope(redactedDecision));
        Assert.NotEqual(decision.DecisionId, redactedDecision.DecisionId);
        Assert.Equal(1, redactedDecision.Payload.GetProperty("offeredActionCount").GetInt32());
        Assert.False(redactedDecision.Payload.TryGetProperty("actions", out _));
        Assert.False(redactedDecision.Payload.GetProperty("prompt").ValueKind == JsonValueKind.String);
        Assert.DoesNotContain("Secret Hero", redactedDecision.Payload.GetRawText(), StringComparison.Ordinal);
        Assert.DoesNotContain("card-secret", redactedDecision.Payload.GetRawText(), StringComparison.Ordinal);

        var checkpointPayload = JsonSerializer.SerializeToElement(new
        {
            snapshot = new
            {
                seats = new[] { new { zones = new[]
                {
                    new { name = "hand", cards = new[] { new { cardName = "Hidden Hand Card", cardInstanceId = "hidden-1" } } },
                    new { name = "library", cards = new[] { new { cardName = "Deck Top", cardInstanceId = "hidden-2" } } },
                    new { name = "battlefield", cards = new[] { new { cardName = "Visible Permanent", cardInstanceId = "visible-1" } } }
                } } },
                stackObjects = new[] { new { sourceName = "Hidden Stack Card", abilityText = "Private ability text", ttsGuid = "guid-secret" } }
            }
        }, WebJson);
        var checkpoint = FlightRecorderService.RedactForExternalExport(CreateEnvelope("authoritative_checkpoint", checkpointPayload));
        var serialized = checkpoint.Payload.GetRawText();
        Assert.DoesNotContain("Hidden Hand Card", serialized, StringComparison.Ordinal);
        Assert.DoesNotContain("Deck Top", serialized, StringComparison.Ordinal);
        Assert.DoesNotContain("Visible Permanent", serialized, StringComparison.Ordinal);
        Assert.DoesNotContain("hidden-1", serialized, StringComparison.Ordinal);
        Assert.DoesNotContain("Hidden Stack Card", serialized, StringComparison.Ordinal);
        Assert.DoesNotContain("Private ability text", serialized, StringComparison.Ordinal);
        Assert.DoesNotContain("guid-secret", serialized, StringComparison.Ordinal);
        Assert.Contains("redactedCardCount", serialized, StringComparison.Ordinal);
        Assert.NotEqual("privacy-session", checkpoint.SessionId);
        Assert.NotEqual("runtime", checkpoint.ClientRuntimeId);
        Assert.True(FlightRecorderService.VerifyEnvelope(checkpoint));

        var choiceResultPayload = JsonSerializer.SerializeToElement(new
        {
            outcome = "accepted",
            result = new
            {
                currentDecision = new
                {
                    decisionId = "followup-secret",
                    kind = "target_selection",
                    prompt = "Choose Hidden Creature",
                    actions = new[] { new { actionId = "target:hidden", displayName = "Hidden Creature", cardInstanceId = "hidden-target" } }
                }
            }
        }, WebJson);
        var choiceResult = FlightRecorderService.RedactForExternalExport(CreateEnvelope("choice_result", choiceResultPayload, "decision-secret"));
        var resultText = choiceResult.Payload.GetRawText();
        Assert.DoesNotContain("Hidden Creature", resultText, StringComparison.Ordinal);
        Assert.DoesNotContain("hidden-target", resultText, StringComparison.Ordinal);
        Assert.DoesNotContain("target:hidden", resultText, StringComparison.Ordinal);
        Assert.DoesNotContain("\"actions\"", resultText, StringComparison.Ordinal);
        Assert.True(FlightRecorderService.VerifyEnvelope(choiceResult));
    }

    [Fact]
    public async Task DisabledRecorderDoesNotCreateFilesOrQueueRecords()
    {
        var root = CreateTempDirectory();
        var recorder = await StartRecorder(root, enabled: false);
        try
        {
            Assert.False(recorder.BeginMatch("session-disabled", "bridge-instance"));
            Assert.False(recorder.RecordTtsEvent("session-disabled", "runtime", "physical_probe", null, new { value = 1 }));
            await recorder.FlushAsync();
            Assert.False(recorder.GetStatus().Recording);
            Assert.Equal(0, recorder.GetStatus().QueueDepth);
            Assert.Equal(0, recorder.GetStatus().QueuedPayloadBytes);
            Assert.Equal(0, recorder.GetStatus().RecordsWritten);
            var sideEffect = new SideEffectPayload();
            Assert.False(recorder.RecordTtsEvent("session-disabled", "runtime", "probe", null, sideEffect));
            Assert.Equal(0, sideEffect.ReadCount);
            Assert.Empty(Directory.GetFileSystemEntries(root));
        }
        finally { await DisposeRecorder(recorder); DeleteTempDirectory(root); }
    }

    [Fact]
    public async Task OldRuntimeAndOldSessionEventsCannotContaminateReplacementMatch()
    {
        var root = CreateTempDirectory();
        var recorder = await StartRecorder(root);
        try
        {
            recorder.RegisterClientRuntime("runtime-current");
            recorder.BeginMatch("session-current");
            Assert.False(recorder.RecordTtsEvent("session-current", "runtime-retired", "physical_drop",
                "decision-old", new { cardInstanceId = "old-card" }));
            recorder.BeginMatch("session-replacement");
            Assert.False(recorder.RecordTtsEvent("session-current", "runtime-current", "physical_drop",
                "decision-old", new { cardInstanceId = "old-card" }));
            Assert.True(recorder.RecordTtsEvent("session-replacement", "runtime-current", "physical_drop",
                "decision-new", new { cardInstanceId = "new-card" }));
            await recorder.StopRecordingAsync();

            Assert.True(recorder.GetStatus().StaleRuntimeRecords >= 2);
            var records = ReadRecords(root, "session-replacement");
            Assert.Contains(records, record => record.Type == "tts_physical_drop");
            Assert.DoesNotContain(records, record => record.DecisionId == "decision-old");
        }
        finally { await DisposeRecorder(recorder); DeleteTempDirectory(root); }
    }

    [Fact]
    public async Task NormalAuthoritativeGameEndIsRecordedSeparatelyFromRecordingFinalization()
    {
        var root = CreateTempDirectory();
        var recorder = await StartRecorder(root);
        try
        {
            const string sessionId = "session-completed";
            recorder.BeginMatch(sessionId);
            var gameEnd = CreateEvent(7, "game_ended", sessionId, 45) with
            {
                WinnerSeatIds = ["forge-player-1"],
                LoserSeatIds = ["forge-player-2"],
                GameEndReason = "life_total"
            };
            Assert.True(recorder.RecordForgeEvent(gameEnd, sessionId));
            recorder.BeginMatch("session-after-completion");
            recorder.RecordForgeEvent(CreateEvent(1, "turn_changed", "session-after-completion", 1),
                "session-after-completion");
            await recorder.StopRecordingAsync();

            var records = ReadRecords(root, sessionId);
            Assert.Single(records.Where(record => record.Type == "match_completed"));
            using var manifest = JsonDocument.Parse(await File.ReadAllTextAsync(Path.Combine(root, sessionId, "manifest.json")));
            Assert.True(manifest.RootElement.GetProperty("matchCompleted").GetBoolean());
            Assert.True(manifest.RootElement.GetProperty("recordingFinalized").GetBoolean());
            Assert.True(manifest.RootElement.GetProperty("complete").GetBoolean());
            using var nextManifest = JsonDocument.Parse(await File.ReadAllTextAsync(
                Path.Combine(root, "session-after-completion", "manifest.json")));
            Assert.False(nextManifest.RootElement.GetProperty("matchCompleted").GetBoolean());
            Assert.True(nextManifest.RootElement.GetProperty("recordingFinalized").GetBoolean());
        }
        finally { await DisposeRecorder(recorder); DeleteTempDirectory(root); }
    }

    [Fact]
    public async Task DiagnosticZipCanIncludeOptionalRecorderExcerptWithoutChangingDefaultCapture()
    {
        var root = CreateTempDirectory();
        var recorder = await StartRecorder(Path.Combine(root, "recordings"));
        try
        {
            var adapter = new MockForgeAdapter();
            var state = await adapter.StartSessionAsync(CancellationToken.None);
            var beforeCapture = await adapter.GetStateAsync(CancellationToken.None);
            recorder.BeginMatch(state.SessionId, "bridge-instance");
            recorder.RecordDecisionOffered(state.CurrentDecision!, "bridge-instance");
            await recorder.StopRecordingAsync();
            var telemetry = new DiagnosticTelemetryBuffer();
            var collector = new DiagnosticReportCollector(adapter, telemetry, new DiagnosticSelfTestRunner(),
                new DiagnosticBundleWriter(), new DiagnosticOptions
                {
                    ReportDirectory = Path.Combine(root, "reports"),
                    IncludeFlightRecorderInCaptures = true
                }, new BridgeProcessIdentity(), NullLogger<DiagnosticReportCollector>.Instance,
                flightRecorder: recorder);
            var result = await collector.CaptureAsync(new DiagnosticReportRequestDto(
                Summary: "flight recorder capture integration", Category: "test", SessionId: state.SessionId), CancellationToken.None);
            Assert.True(result.Success, result.Message);
            using var archive = ZipFile.OpenRead(result.ReportPath!);
            Assert.Contains(archive.Entries, entry => entry.FullName == "recorder/manifest.json");
            Assert.Contains(archive.Entries, entry => entry.FullName == "recorder/recent.jsonl");
            var afterCapture = await adapter.GetStateAsync(CancellationToken.None);
            Assert.Equal(beforeCapture.SessionId, afterCapture.SessionId);
            Assert.Equal(beforeCapture.State, afterCapture.State);
            Assert.Equal(beforeCapture.CurrentDecision?.DecisionId, afterCapture.CurrentDecision?.DecisionId);

            var performance = await collector.CaptureAsync(new DiagnosticReportRequestDto(
                Summary: "flight recorder performance capture integration", Category: "performance", SessionId: state.SessionId), CancellationToken.None);
            Assert.True(performance.Success, performance.Message);
            using var performanceArchive = ZipFile.OpenRead(performance.ReportPath!);
            Assert.Contains(performanceArchive.Entries, entry => entry.FullName == "recorder/manifest.json");
            Assert.Contains(performanceArchive.Entries, entry => entry.FullName == "recorder/recent.jsonl");
        }
        finally { await DisposeRecorder(recorder); DeleteTempDirectory(root); }
    }

    private static DecisionDto CreateDecision(string sessionId, string decisionId, long cursor, long forgeSequence) =>
        new(decisionId, "main_priority",
        [
            new LegalActionDto("cast:source-81", "cast_spell", "Cast a spell", true, null, "forge-object:81",
                CardInstanceId: "forge:" + sessionId + ":81", SourceCardInstanceId: "forge:" + sessionId + ":81",
                DisplayManaCost: "{X}{R}", CostKind: "mana", TargetKind: "creature")
            {
                Provenance = new ActionProvenanceDto("cast", "forge:" + sessionId + ":81", "hand",
                    "forge-player-1", CastMode: "normal", DisplayCost: "{X}{R}")
            },
            new LegalActionDto("pass:" + cursor, "pass_priority", "Pass", false, null, null)
        ], SeatId: "forge-player-1")
        {
            SessionId = sessionId, EventCursor = cursor, ForgeSequence = forgeSequence, TurnNumber = 4,
            ActiveSeatId = "forge-player-1", PrioritySeatId = "forge-player-1", PhaseName = "Main 1",
            AllowsCancel = true,
            PaymentContext = new PaymentContextDto("cast:source-81", "payment:81", "forge:" + sessionId + ":81",
                "hand", "cast", "normal", [new CostComponentDto("cost:81", "sacrifice", "Sacrifice a creature", "1")])
        };

    private static AuthoritativeEventDto CreateEvent(long sequence, string kind, string sessionId, long forgeSequence) =>
        new(sequence, $"forge-event-{sessionId}-{sequence}", kind, "forge-player-1", null, null, null,
            null, null, kind, DateTimeOffset.UtcNow, ForgeSequence: forgeSequence,
            TurnNumber: 4, Phase: "Main 1", ActiveSeatId: "forge-player-1", PrioritySeatId: "forge-player-1");

    private static FlightRecorderEnvelope CreateEnvelope(string type, JsonElement payload, string? decisionId = null)
    {
        var timestamp = DateTimeOffset.UtcNow;
        var unsigned = new
        {
            schemaVersion = FlightRecorderService.CurrentSchemaVersion,
            sequence = 1L,
            timestampUtc = timestamp,
            type,
            sessionId = "privacy-session",
            decisionId,
            forgeSequence = (long?)null,
            eventCursor = (long?)null,
            clientRuntimeId = "runtime",
            bridgeProcessInstanceId = "bridge-instance",
            bridgeBuildIdentity = "test-build",
            payload
        };
        var checksum = Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(unsigned, WebJson))).ToLowerInvariant();
        return new FlightRecorderEnvelope(FlightRecorderService.CurrentSchemaVersion, 1, timestamp,
            type, "privacy-session", decisionId, null, null, "runtime", payload, checksum,
            "bridge-instance", "test-build");
    }

    private static async Task<FlightRecorderService> StartRecorder(string root, bool enabled = true,
        int queueCapacity = 256, long maxDiskBytes = 64 * 1024 * 1024, int retentionMatchCount = 20,
        int maxRecordPayloadBytes = 4 * 1024 * 1024, long maxQueueBytes = 32 * 1024 * 1024)
    {
        var recorder = new FlightRecorderService(Options.Create(new FlightRecorderOptions
        {
            Enabled = enabled,
            Directory = root,
            QueueCapacity = queueCapacity,
            MaxQueueBytes = maxQueueBytes,
            MaxRecordPayloadBytes = maxRecordPayloadBytes,
            MaxDiskBytes = maxDiskBytes,
            RetentionMatchCount = retentionMatchCount,
            MaxSegmentBytes = 64 * 1024,
            FlushIntervalSeconds = 1,
            CheckpointIntervalSeconds = 30
        }), NullLogger<FlightRecorderService>.Instance);
        await recorder.StartAsync(CancellationToken.None);
        return recorder;
    }

    private static IReadOnlyList<FlightRecorderEnvelope> ReadRecords(string root, string sessionId) =>
        Directory.GetFiles(Path.Combine(root, sessionId), "segment-*.jsonl")
            .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
            .SelectMany(File.ReadLines)
            .Select(line => JsonSerializer.Deserialize<FlightRecorderEnvelope>(line, WebJson)!)
            .ToArray();

    private static async Task DisposeRecorder(FlightRecorderService recorder)
    {
        try
        {
            if (recorder.GetStatus().Recording) await recorder.StopRecordingAsync();
            await recorder.StopAsync(CancellationToken.None);
        }
        catch { }
        recorder.Dispose();
    }

    private static string CreateTempDirectory()
    {
        var path = Path.Combine(Path.GetTempPath(), $"MtgTtsBridge-recorder-tests-{Guid.NewGuid():N}");
        Directory.CreateDirectory(path);
        return path;
    }

    private static void DeleteTempDirectory(string path)
    {
        try { if (Directory.Exists(path)) Directory.Delete(path, recursive: true); } catch { }
    }

    private sealed class SideEffectPayload
    {
        public int ReadCount { get; private set; }
        public string Value { get { ReadCount++; return "should not serialize"; } }
    }
}
