using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.Channels;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Options;
using MtgTtsBridge;
using MtgTtsBridge.Contracts.Actions;
using MtgTtsBridge.Contracts.Events;
using MtgTtsBridge.Contracts.State;
using MtgTtsBridge.Forge;

namespace MtgTtsBridge.Diagnostics;

public sealed class FlightRecorderOptions
{
    public bool Enabled { get; set; } = true;
    public string Directory { get; set; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MtgTtsBridge", "Recordings");
    public int QueueCapacity { get; set; } = 4096;
    public long MaxQueueBytes { get; set; } = 32 * 1024 * 1024;
    public int MaxRecordPayloadBytes { get; set; } = 4 * 1024 * 1024;
    public int MaxEventPayloadBytes { get; set; } = 64 * 1024;
    public long MaxSegmentBytes { get; set; } = 8 * 1024 * 1024;
    public long MaxDiskBytes { get; set; } = 512 * 1024 * 1024;
    public int RetentionMatchCount { get; set; } = 20;
    public int FlushIntervalSeconds { get; set; } = 2;
    public int CheckpointIntervalSeconds { get; set; } = 30;
}

public sealed record FlightRecorderStatus(
    bool Enabled,
    bool Recording,
    string? SessionId,
    string Directory,
    long RecordsWritten,
    long RecordsDropped,
    long StaleRuntimeRecords,
    bool StorageFaulted,
    string? StorageError,
    long QueueDepth,
    int SchemaVersion,
    long QueuedPayloadBytes = 0);

public sealed record FlightRecorderEnvelope(
    int SchemaVersion,
    long Sequence,
    DateTimeOffset TimestampUtc,
    string Type,
    string? SessionId,
    string? DecisionId,
    long? ForgeSequence,
    long? EventCursor,
    string? ClientRuntimeId,
    JsonElement Payload,
    string ChecksumSha256,
    string? BridgeProcessInstanceId = null,
    string? BridgeBuildIdentity = null,
    bool PrivacyRedacted = false);

public sealed record FlightRecorderSegmentMetadata(
    int SchemaVersion,
    string SessionId,
    string FileName,
    long FirstRecordSequence,
    long LastRecordSequence,
    int RecordCount,
    long ByteLength,
    string Sha256,
    bool RecoveredAfterInterruption,
    DateTimeOffset ClosedAtUtc);

public sealed record FlightRecorderCaptureExcerpt(
    int SchemaVersion,
    string? SessionId,
    bool Truncated,
    bool Missing,
    string? MissingReason,
    long RecordsDropped,
    IReadOnlyList<string> RecentRecords,
    IReadOnlyList<string> CheckpointRecords,
    FlightRecorderStatus Status);

public sealed record FlightRecorderTtsEventRequest(
    string SessionId,
    string ClientRuntimeId,
    string Type,
    string? DecisionId,
    JsonElement Payload,
    long? EventCursor = null);

/// <summary>
/// Local append-only flight journal. Producer paths only serialize records into
/// bounded immutable queue items; they never touch disk and return immediately.
/// </summary>
public sealed class FlightRecorderService : BackgroundService
{
    public const int CurrentSchemaVersion = 1;
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.Never,
        WriteIndented = false
    };

    private readonly FlightRecorderOptions _options;
    private readonly ILogger<FlightRecorderService> _logger;
    private readonly string _bridgeProcessInstanceId;
    private readonly string _bridgeBuildIdentity;
    private readonly Channel<WorkItem> _queue;
    private readonly object _stateSync = new();
    private readonly ConcurrentDictionary<string, long> _sequences = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, long> _pendingDroppedBySession = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, long> _droppedBySession = new(StringComparer.Ordinal);
    private readonly HashSet<string> _recordedDecisionGenerations = new(StringComparer.Ordinal);
    private readonly Queue<string> _recordedDecisionGenerationOrder = new();
    private readonly HashSet<string> _completedSessions = new(StringComparer.Ordinal);
    private readonly HashSet<string> _finalizedSessions = new(StringComparer.Ordinal);
    private readonly HashSet<string> _interruptedSessions = new(StringComparer.Ordinal);
    private readonly Dictionary<string, DeliveryObservation> _deliveryObservations = new(StringComparer.Ordinal);
    private string? _sessionId;
    private string? _clientRuntimeId;
    private string? _activeTtsRuntimeId;
    private bool _recording;
    private bool _storageFaulted;
    private string? _storageError;
    private long _recordsWritten;
    private long _recordsDropped;
    private long _pendingDropped;
    private long _queuedPayloadBytes;
    private long _staleRuntimeRecords;
    private long _lastCheckpointTicks;
    private string? _lastCheckpointSessionId;
    private StreamWriter? _writer;
    private FileStream? _stream;
    private string? _activeDirectory;
    private string? _activeSegmentPath;
    private string? _activeSegmentSessionId;
    private int _segmentNumber;
    private long _segmentFirstSequence;
    private long _segmentLastSequence;
    private int _segmentRecordCount;
    private long _segmentBytes;

    public FlightRecorderService(IOptions<FlightRecorderOptions> options, ILogger<FlightRecorderService> logger,
        BridgeProcessIdentity? identity = null)
    {
        _options = options.Value;
        _logger = logger;
        _bridgeProcessInstanceId = identity?.ProcessInstanceId ?? BridgeProcessIdentity.InstanceId;
        _bridgeBuildIdentity = BridgeProcessIdentity.BuildIdentity;
        var capacity = Math.Max(1, _options.QueueCapacity);
        _queue = Channel.CreateBounded<WorkItem>(new BoundedChannelOptions(capacity)
        {
            FullMode = BoundedChannelFullMode.Wait,
            SingleReader = true,
            SingleWriter = false,
            AllowSynchronousContinuations = false
        });
        _recording = _options.Enabled;
    }

    public FlightRecorderStatus GetStatus()
    {
        lock (_stateSync)
        {
            return new FlightRecorderStatus(_options.Enabled, _recording, _sessionId, GetRootDirectory(),
                Interlocked.Read(ref _recordsWritten), Interlocked.Read(ref _recordsDropped),
                Interlocked.Read(ref _staleRuntimeRecords), _storageFaulted, _storageError,
                Math.Max(0, _queue.Reader.Count), CurrentSchemaVersion,
                Math.Max(0, Interlocked.Read(ref _queuedPayloadBytes)));
        }
    }

    public bool StartRecording(string? sessionId = null, string? clientRuntimeId = null)
    {
        if (!_options.Enabled) return false;
        lock (_stateSync)
        {
            if (_storageFaulted) return false;
            _recording = true;
            if (_sessionId is not null) _finalizedSessions.Remove(_sessionId);
        }
        if (!string.IsNullOrWhiteSpace(sessionId)) BeginMatch(sessionId, clientRuntimeId);
        if (!string.IsNullOrWhiteSpace(sessionId))
            EnqueueRecord("recording_started", new { atUtc = DateTimeOffset.UtcNow }, sessionId,
                clientRuntimeId: clientRuntimeId ?? _activeTtsRuntimeId);
        return true;
    }

    public void RegisterClientRuntime(string? clientRuntimeId)
    {
        if (string.IsNullOrWhiteSpace(clientRuntimeId)) return;
        lock (_stateSync)
        {
            if (_activeTtsRuntimeId == clientRuntimeId) return;
            _activeTtsRuntimeId = clientRuntimeId;
            _clientRuntimeId = clientRuntimeId;
            if (_recording && !_storageFaulted && _sessionId is not null)
                EnqueueRecord("tts_runtime_changed", new { clientRuntimeId }, _sessionId, clientRuntimeId: clientRuntimeId);
        }
    }

    public async Task StopRecordingAsync(CancellationToken cancellationToken = default)
    {
        lock (_stateSync)
        {
            FlushDeliveryObservationLocked(_sessionId);
            if (_recording && _sessionId is not null)
                EnqueueRecord("recording_stopped", new { atUtc = DateTimeOffset.UtcNow }, _sessionId,
                    clientRuntimeId: _activeTtsRuntimeId);
            if (_sessionId is not null) _finalizedSessions.Add(_sessionId);
            _recording = false;
        }
        await FlushAsync(cancellationToken).ConfigureAwait(false);
        EnqueueControl(WorkKind.CloseSegment, cancellationToken);
        await FlushAsync(cancellationToken).ConfigureAwait(false);
    }

    public bool BeginMatch(string sessionId, string? clientRuntimeId = null)
    {
        if (string.IsNullOrWhiteSpace(sessionId) || sessionId == "session-not-started") return false;
        lock (_stateSync)
        {
            if (!_recording || _storageFaulted) return false;
            if (_sessionId == sessionId) return true;
            FlushDeliveryObservationLocked(_sessionId);
            if (_sessionId is not null)
            {
                var previous = _sessionId;
                EnqueueRecord("match_replaced", new { replacementSessionId = sessionId }, previous);
                _finalizedSessions.Add(previous);
            }
            _sessionId = sessionId;
            _clientRuntimeId = clientRuntimeId ?? _activeTtsRuntimeId;
            return EnqueueRecord("match_started", new { sessionId, clientRuntimeId = _clientRuntimeId,
                schemaVersion = CurrentSchemaVersion }, sessionId, clientRuntimeId: _clientRuntimeId);
        }
    }

    public bool RecordDecisionOffered(DecisionDto decision, string? clientRuntimeId = null)
    {
        if (decision is null || string.IsNullOrWhiteSpace(decision.SessionId)) return false;
        BeginMatch(decision.SessionId, clientRuntimeId);
        var generationKey = string.Join("|", decision.SessionId, decision.DecisionId,
            decision.ForgeSequence?.ToString() ?? "?", decision.EventCursor?.ToString() ?? "?");
        lock (_stateSync)
        {
            if (!_recording || _storageFaulted || !TryRememberDecisionGenerationLocked(generationKey)) return false;
        }
        var accepted = EnqueueRecord("decision_offered", decision, decision.SessionId, decision.DecisionId,
            decision.ForgeSequence, decision.EventCursor, clientRuntimeId ?? _activeTtsRuntimeId);
        if (!accepted)
        {
            lock (_stateSync) ForgetDecisionGenerationLocked(generationKey);
        }
        return accepted;
    }

    public void ObserveDecisionDelivery(DecisionDto decision, string? clientRuntimeId = null)
    {
        if (decision is null || string.IsNullOrWhiteSpace(decision.SessionId)) return;
        BeginMatch(decision.SessionId, clientRuntimeId);
        var key = string.Join("|", decision.SessionId, decision.DecisionId,
            decision.ForgeSequence?.ToString() ?? "?", decision.EventCursor?.ToString() ?? "?");
        lock (_stateSync)
        {
            if (!_recording || _storageFaulted) return;
            if (_deliveryObservations.TryGetValue(decision.SessionId, out var current) && current.GenerationKey == key)
            {
                _deliveryObservations[decision.SessionId] = current with { Count = current.Count + 1, LastAtUtc = DateTimeOffset.UtcNow };
                return;
            }
            FlushDeliveryObservationLocked(decision.SessionId);
            _deliveryObservations[decision.SessionId] = new DeliveryObservation(key, decision.DecisionId,
                decision.ForgeSequence, decision.EventCursor, 1, DateTimeOffset.UtcNow, DateTimeOffset.UtcNow);
        }
        RecordDecisionOffered(decision, clientRuntimeId);
    }

    public bool RecordChoiceRequested(ChoiceRequestDto request)
    {
        if (request.SessionId is not null && _sessionId is null) BeginMatch(request.SessionId, request.ClientRuntimeId);
        if (!AcceptTtsRuntime(request.ClientRuntimeId)) return false;
        return EnqueueRecord("choice_requested", request, request.SessionId, request.DecisionId,
            clientRuntimeId: request.ClientRuntimeId);
    }

    public bool RecordChoiceResult(ChoiceRequestDto request, string outcome, object? result = null)
    {
        if (!AcceptTtsRuntime(request.ClientRuntimeId)) return false;
        return EnqueueRecord("choice_result", new { request, outcome, result }, request.SessionId,
            request.DecisionId, clientRuntimeId: request.ClientRuntimeId);
    }

    public bool RecordForgeEvent(AuthoritativeEventDto forgeEvent, string? sessionId)
    {
        if (forgeEvent is null) return false;
        if (!string.IsNullOrWhiteSpace(sessionId) && _sessionId is null) BeginMatch(sessionId, _clientRuntimeId);
        var accepted = EnqueueRecord("forge_event", forgeEvent, sessionId, eventCursor: forgeEvent.Sequence,
            forgeSequence: forgeEvent.ForgeSequence, clientRuntimeId: _activeTtsRuntimeId);
        var matchEnded = forgeEvent.WinnerSeatIds is not null || !string.IsNullOrWhiteSpace(forgeEvent.GameEndReason);
        var firstEnd = false;
        if (matchEnded && sessionId is not null)
        {
            lock (_stateSync) firstEnd = _completedSessions.Add(sessionId);
        }
        if (accepted && firstEnd)
            EnqueueRecord("match_completed", new { forgeEvent.WinnerSeatIds, forgeEvent.LoserSeatIds, forgeEvent.GameEndReason },
                sessionId, eventCursor: forgeEvent.Sequence, forgeSequence: forgeEvent.ForgeSequence,
                clientRuntimeId: _activeTtsRuntimeId);
        return accepted;
    }

    public bool RecordTtsBreadcrumb(TtsExecutionBreadcrumb breadcrumb)
    {
        if (breadcrumb is null) return false;
        if (!string.IsNullOrWhiteSpace(breadcrumb.SessionId) && _sessionId is null)
            BeginMatch(breadcrumb.SessionId, breadcrumb.ClientRuntimeId);
        if (!AcceptTtsRuntime(breadcrumb.ClientRuntimeId)) return false;
        return EnqueueRecord("tts_observation", breadcrumb, breadcrumb.SessionId,
            eventCursor: breadcrumb.EventSequence, clientRuntimeId: breadcrumb.ClientRuntimeId);
    }

    public bool RecordSnapshot(GameSnapshotDto snapshot, string reason = "periodic")
    {
        if (snapshot is null) return false;
        if (_sessionId is null) BeginMatch(snapshot.SessionId, _clientRuntimeId);
        var previous = Interlocked.Read(ref _lastCheckpointTicks);
        var now = DateTime.UtcNow.Ticks;
        if (reason == "periodic" && _lastCheckpointSessionId == snapshot.SessionId
            && now - previous < TimeSpan.FromSeconds(Math.Max(1, _options.CheckpointIntervalSeconds)).Ticks)
            return false;
        _lastCheckpointSessionId = snapshot.SessionId;
        Interlocked.Exchange(ref _lastCheckpointTicks, now);
        return EnqueueRecord("authoritative_checkpoint", new { reason, snapshot }, snapshot.SessionId,
            forgeSequence: snapshot.ForgeSequence, eventCursor: snapshot.EventCursor);
    }

    public bool RecordTtsEvent(string sessionId, string clientRuntimeId, string type,
        string? decisionId, object payload, long? eventCursor = null)
    {
        if (string.IsNullOrWhiteSpace(sessionId) || string.IsNullOrWhiteSpace(type)) return false;
        if (_sessionId is null) BeginMatch(sessionId, clientRuntimeId);
        if (!AcceptTtsRuntime(clientRuntimeId)) return false;
        if (!CanAcceptRecord("tts_" + type, sessionId, clientRuntimeId)) return false;
        if (QueueIsAlreadyFull())
        {
            RecordDroppedEvent(sessionId);
            return false;
        }
        byte[] payloadJson;
        try
        {
            payloadJson = payload is JsonElement jsonPayload
                ? Encoding.UTF8.GetBytes(jsonPayload.GetRawText())
                : JsonSerializer.SerializeToUtf8Bytes(payload, JsonOptions);
        }
        catch (Exception exception)
        {
            _logger.LogWarning(exception, "Flight recorder could not serialize TTS event {EventType}", type);
            RecordDroppedEvent(sessionId);
            return false;
        }
        if (payloadJson.Length > Math.Max(1024, _options.MaxEventPayloadBytes))
        {
            RecordDroppedEvent(sessionId);
            return false;
        }
        return EnqueueSerializedRecord("tts_" + type, payloadJson, sessionId, decisionId,
            eventCursor: eventCursor, clientRuntimeId: clientRuntimeId);
    }

    public async Task FlushAsync(CancellationToken cancellationToken = default)
    {
        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        if (!_queue.Writer.TryWrite(new WorkItem(WorkKind.Flush, null, completion)))
            await _queue.Writer.WriteAsync(new WorkItem(WorkKind.Flush, null, completion), cancellationToken).ConfigureAwait(false);
        await completion.Task.WaitAsync(cancellationToken).ConfigureAwait(false);
    }

    public FlightRecorderCaptureExcerpt CaptureExcerpt(string? sessionId, int maxRecords = 500, int maxBytes = 1024 * 1024)
    {
        var status = GetStatus();
        var targetSession = sessionId ?? status.SessionId;
        if (string.IsNullOrWhiteSpace(targetSession))
            return new FlightRecorderCaptureExcerpt(CurrentSchemaVersion, null, false, true,
                "No recording session is available.", status.RecordsDropped, [], [], status);
        var targetDropped = _droppedBySession.GetValueOrDefault(targetSession);
        var directory = Path.Combine(GetRootDirectory(), SafeSegment(targetSession));
        if (!Directory.Exists(directory))
            return new FlightRecorderCaptureExcerpt(CurrentSchemaVersion, targetSession, false, true,
                "Recording directory does not exist.", targetDropped, [], [], status);
        var lines = new List<string>();
        var checkpoints = new List<string>();
        var bytes = 0;
        var truncated = false;
        foreach (var path in Directory.EnumerateFiles(directory, "segment-*.jsonl*")
                     .OrderByDescending(path => path, StringComparer.OrdinalIgnoreCase))
        {
            try
            {
                using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                using var reader = new StreamReader(stream, Encoding.UTF8);
                var segmentLines = new List<string>();
                while (reader.ReadLine() is { } line) segmentLines.Add(line);
                for (var index = segmentLines.Count - 1; index >= 0; index--)
                {
                    var line = segmentLines[index];
                    if (bytes + Encoding.UTF8.GetByteCount(line) > Math.Max(2048, maxBytes) || lines.Count >= Math.Max(1, maxRecords))
                    {
                        truncated = true;
                        break;
                    }
                    bytes += Encoding.UTF8.GetByteCount(line);
                    lines.Add(line);
                    if (line.Contains("\"type\":\"authoritative_checkpoint\"", StringComparison.Ordinal)) checkpoints.Add(line);
                }
                if (truncated) break;
            }
            catch (IOException) { truncated = true; }
        }
        lines.Reverse();
        checkpoints.Reverse();
        return new FlightRecorderCaptureExcerpt(CurrentSchemaVersion, targetSession, truncated, false, null,
            targetDropped, lines, checkpoints, status);
    }

    public static FlightRecorderEnvelope RedactForExternalExport(FlightRecorderEnvelope envelope)
    {
        var payloadNode = JsonNode.Parse(envelope.Payload.GetRawText());
        RedactNode(payloadNode, envelope.Type);
        if (payloadNode is JsonObject result) result["externalExportPrivacy"] = "redacted";
        var payload = JsonSerializer.SerializeToElement(payloadNode, JsonOptions);
        var decisionId = RedactIdentifier(envelope.DecisionId);
        var unsigned = new UnsignedEnvelope(envelope.SchemaVersion, envelope.Sequence, envelope.TimestampUtc,
            envelope.Type, RedactIdentifier(envelope.SessionId), decisionId, envelope.ForgeSequence, envelope.EventCursor,
            RedactIdentifier(envelope.ClientRuntimeId), RedactIdentifier(envelope.BridgeProcessInstanceId), envelope.BridgeBuildIdentity, payload);
        var checksum = Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(unsigned, JsonOptions))).ToLowerInvariant();
        return envelope with
        {
            SessionId = RedactIdentifier(envelope.SessionId),
            DecisionId = decisionId,
            ClientRuntimeId = RedactIdentifier(envelope.ClientRuntimeId),
            BridgeProcessInstanceId = RedactIdentifier(envelope.BridgeProcessInstanceId),
            Payload = payload,
            ChecksumSha256 = checksum,
            PrivacyRedacted = true
        };
    }

    public static string? RedactExternalIdentifier(string? value) => RedactIdentifier(value);

    public static bool VerifyEnvelope(FlightRecorderEnvelope envelope)
    {
        var unsigned = new UnsignedEnvelope(envelope.SchemaVersion, envelope.Sequence, envelope.TimestampUtc,
            envelope.Type, envelope.SessionId, envelope.DecisionId, envelope.ForgeSequence, envelope.EventCursor,
            envelope.ClientRuntimeId, envelope.BridgeProcessInstanceId, envelope.BridgeBuildIdentity, envelope.Payload);
        var expected = Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(unsigned, JsonOptions))).ToLowerInvariant();
        return CryptographicOperations.FixedTimeEquals(Encoding.ASCII.GetBytes(expected),
            Encoding.ASCII.GetBytes(envelope.ChecksumSha256 ?? string.Empty));
    }

    private static void RedactNode(JsonNode? node, string recordType)
    {
        if (node is JsonArray array)
        {
            foreach (var child in array) RedactNode(child, recordType);
            return;
        }
        if (node is not JsonObject obj) return;

        var zoneName = obj["name"]?.ToString() ?? obj["zone"]?.ToString() ?? "";
        var privateZone = zoneName.Contains("hand", StringComparison.OrdinalIgnoreCase)
            || zoneName.Contains("library", StringComparison.OrdinalIgnoreCase)
            || zoneName.Contains("deck", StringComparison.OrdinalIgnoreCase);
        if (privateZone && obj["cards"] is JsonArray privateCards)
        {
            obj["redactedCardCount"] = privateCards.Count;
            obj["cards"] = new JsonArray();
            obj["privateContentsRedacted"] = true;
        }
        if (obj.ContainsKey("decisionId") && obj["actions"] is JsonArray actions)
        {
            obj["offeredActionCount"] = actions.Count;
            obj.Remove("actions");
            obj["actionDetailsRedacted"] = true;
        }
        if (obj["targets"] is JsonArray targets)
        {
            obj["redactedTargetCount"] = targets.Count;
            obj.Remove("targets");
        }
        if (obj["summary"] is not null)
            obj["summary"] = recordType == "forge_event" ? "Forge authoritative event." : null;

        foreach (var key in obj.Select(pair => pair.Key).ToArray())
        {
            if (key is "decisionId" or "sessionId" or "clientRuntimeId" or "bridgeProcessInstanceId"
                && obj[key]?.GetValueKind() == JsonValueKind.String)
            {
                obj[key] = RedactIdentifier(obj[key]!.GetValue<string>());
                continue;
            }
            if (IsPrivateIdentityField(key) || key is "prompt" or "displayName" or "sourceName"
                or "abilityName" or "abilityText" or "rulesText" or "cardText" or "text")
            {
                obj[key] = null;
                continue;
            }
            RedactNode(obj[key], recordType);
        }
    }

    private static bool IsPrivateIdentityField(string key)
    {
        var normalized = key.ToLowerInvariant();
        return normalized is
        "cardname" or "currentcardname" or "sourcecardname" or "contextcardname" or "cardidentity"
        or "cardinstanceid" or "sourcecardinstanceid" or "entitycardinstanceid" or "preparedsourcecardinstanceid"
        or "targetcardinstanceid" or "forgeobjectid" or "authoritativeobjectid" or "originobjectid"
        or "copysourceobjectid" or "tokensourceobjectid" or "objectidentity" or "actionid"
        or "ttsguid" or "guid" or "sourceguid" or "targetguid"
        || normalized.Contains("cardname", StringComparison.Ordinal)
        || normalized.Contains("cardidentity", StringComparison.Ordinal)
        || normalized.Contains("cardinstanceid", StringComparison.Ordinal)
        || normalized.EndsWith("objectid", StringComparison.Ordinal);
    }

    private static string? RedactIdentifier(string? value) => string.IsNullOrWhiteSpace(value)
        ? value
        : "redacted-" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)))[..16].ToLowerInvariant();

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        Task? readerTask = null;
        try
        {
            RecoverInterruptedSegments();
            LoadExistingSequenceState();
            await RefreshInterruptedManifestsAsync(stoppingToken).ConfigureAwait(false);
            using var timer = new PeriodicTimer(TimeSpan.FromSeconds(Math.Clamp(_options.FlushIntervalSeconds, 1, 60)));
            readerTask = ReadQueueAsync(stoppingToken);
            while (!stoppingToken.IsCancellationRequested)
            {
                var tick = timer.WaitForNextTickAsync(stoppingToken).AsTask();
                var completed = await Task.WhenAny(readerTask, tick).ConfigureAwait(false);
                if (completed == readerTask) { await readerTask.ConfigureAwait(false); return; }
                await tick.ConfigureAwait(false);
                await FlushWriterAsync(stoppingToken).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { }
        catch (Exception exception) { SetStorageFault(exception); }
        finally
        {
            try
            {
                if (readerTask is not null)
                {
                    try { await readerTask.ConfigureAwait(false); }
                    catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { }
                }
                _queue.Writer.TryComplete();
                while (_queue.Reader.TryRead(out var queued))
                    await ProcessWorkItemAsync(queued, CancellationToken.None).ConfigureAwait(false);
                await WritePendingLossAsync(CancellationToken.None).ConfigureAwait(false);
                await FlushWriterAsync(CancellationToken.None).ConfigureAwait(false);
                if (_sessionId is not null)
                {
                    lock (_stateSync) _finalizedSessions.Add(_sessionId);
                }
                await CloseSegmentAsync(recovered: false, CancellationToken.None).ConfigureAwait(false);
            }
            catch (Exception exception) { SetStorageFault(exception); }
        }
    }

    private async Task ReadQueueAsync(CancellationToken cancellationToken)
    {
        await foreach (var item in _queue.Reader.ReadAllAsync(cancellationToken).ConfigureAwait(false))
            await ProcessWorkItemAsync(item, cancellationToken).ConfigureAwait(false);
    }

    private async Task ProcessWorkItemAsync(WorkItem item, CancellationToken cancellationToken)
    {
        try
        {
            if (item.Kind == WorkKind.Flush)
            {
                await WritePendingLossAsync(cancellationToken).ConfigureAwait(false);
                await FlushWriterAsync(cancellationToken).ConfigureAwait(false);
                item.Completion?.TrySetResult();
                return;
            }
            if (item.Kind == WorkKind.CloseSegment)
            {
                await WritePendingLossAsync(cancellationToken).ConfigureAwait(false);
                await CloseSegmentAsync(recovered: false, cancellationToken).ConfigureAwait(false);
                return;
            }
            if (item.Record is null) return;
            try { await WriteRecordAsync(item.Record, cancellationToken).ConfigureAwait(false); }
            catch (Exception exception) { SetStorageFault(exception); }
        }
        catch (Exception exception)
        {
            item.Completion?.TrySetException(exception);
            throw;
        }
        finally
        {
            if (item.ReservedBytes > 0) Interlocked.Add(ref _queuedPayloadBytes, -item.ReservedBytes);
        }
    }

    private bool EnqueueRecord(string type, object payload, string? sessionId = null, string? decisionId = null,
        long? forgeSequence = null, long? eventCursor = null, string? clientRuntimeId = null)
    {
        if (!CanAcceptRecord(type, sessionId, clientRuntimeId)) return false;
        if (QueueIsAlreadyFull())
        {
            if (!string.IsNullOrWhiteSpace(sessionId)) RecordDroppedEvent(sessionId);
            return false;
        }
        byte[] payloadJson;
        try { payloadJson = JsonSerializer.SerializeToUtf8Bytes(payload, JsonOptions); }
        catch (Exception exception)
        {
            _logger.LogWarning(exception, "Flight recorder could not serialize event {EventType}", type);
            if (!string.IsNullOrWhiteSpace(sessionId)) RecordDroppedEvent(sessionId);
            return false;
        }
        return EnqueueSerializedRecord(type, payloadJson, sessionId, decisionId, forgeSequence, eventCursor, clientRuntimeId);
    }

    private bool EnqueueSerializedRecord(string type, byte[] payloadJson, string? sessionId,
        string? decisionId, long? forgeSequence = null, long? eventCursor = null, string? clientRuntimeId = null)
    {
        lock (_stateSync)
        {
            if (!CanAcceptRecordLocked(type, sessionId, clientRuntimeId)) return false;
            var maxRecordBytes = Math.Max(1024, _options.MaxRecordPayloadBytes);
            if (payloadJson.Length > maxRecordBytes)
            {
                RecordDroppedEvent(sessionId!);
                return false;
            }
            var queuedBytes = Interlocked.Add(ref _queuedPayloadBytes, payloadJson.Length);
            if (queuedBytes > Math.Max(1024, _options.MaxQueueBytes))
            {
                Interlocked.Add(ref _queuedPayloadBytes, -payloadJson.Length);
                RecordDroppedEvent(sessionId!);
                return false;
            }
            var item = new RecorderRecord(DateTimeOffset.UtcNow, type, sessionId, decisionId,
                forgeSequence, eventCursor, clientRuntimeId, payloadJson);
            if (_queue.Writer.TryWrite(new WorkItem(WorkKind.Record, item, null, payloadJson.Length))) return true;
            Interlocked.Add(ref _queuedPayloadBytes, -payloadJson.Length);
            Interlocked.Increment(ref _recordsDropped);
            AddDroppedEventLocked(sessionId!);
            return false;
        }
    }

    private bool CanAcceptRecord(string type, string? sessionId, string? clientRuntimeId)
    {
        lock (_stateSync) return CanAcceptRecordLocked(type, sessionId, clientRuntimeId);
    }

    private bool CanAcceptRecordLocked(string type, string? sessionId, string? clientRuntimeId)
    {
        if (!_recording || _storageFaulted || string.IsNullOrWhiteSpace(sessionId)) return false;
        if (_sessionId is null) _sessionId = sessionId;
        if (!string.Equals(sessionId, _sessionId, StringComparison.Ordinal))
        {
            Interlocked.Increment(ref _staleRuntimeRecords);
            return false;
        }
        var isTtsRequest = type.StartsWith("tts_", StringComparison.Ordinal)
            || type is "choice_requested" or "choice_result";
        if (isTtsRequest && !string.IsNullOrWhiteSpace(clientRuntimeId)
            && _activeTtsRuntimeId is not null && _activeTtsRuntimeId != clientRuntimeId)
        {
            Interlocked.Increment(ref _staleRuntimeRecords);
            return false;
        }
        return true;
    }

    private bool QueueIsAlreadyFull()
    {
        lock (_stateSync)
            return _queue.Reader.Count >= Math.Max(1, _options.QueueCapacity)
                || Interlocked.Read(ref _queuedPayloadBytes) >= Math.Max(1024, _options.MaxQueueBytes);
    }

    private void RecordDroppedEvent(string sessionId)
    {
        lock (_stateSync)
        {
            if (!_recording || _storageFaulted || _sessionId != sessionId) return;
            Interlocked.Increment(ref _recordsDropped);
            AddDroppedEventLocked(sessionId);
        }
    }

    private void AddDroppedEventLocked(string sessionId)
    {
        Interlocked.Increment(ref _pendingDropped);
        _pendingDroppedBySession.AddOrUpdate(sessionId, 1, static (_, previous) => previous + 1);
        _droppedBySession.AddOrUpdate(sessionId, 1, static (_, previous) => previous + 1);
    }

    private bool AcceptTtsRuntime(string? runtimeId)
    {
        if (string.IsNullOrWhiteSpace(runtimeId)) return true;
        lock (_stateSync)
        {
            if (_activeTtsRuntimeId is null)
            {
                _activeTtsRuntimeId = runtimeId;
                return true;
            }
            if (_activeTtsRuntimeId == runtimeId) return true;
            Interlocked.Increment(ref _staleRuntimeRecords);
            return false;
        }
    }

    private void FlushDeliveryObservationLocked(string? sessionId)
    {
        if (sessionId is null || !_deliveryObservations.Remove(sessionId, out var observation) || observation.Count <= 0) return;
        // Queue directly while holding the state lock; TryWrite is nonblocking and disk-free.
        var payload = new
        {
            observation.DecisionId,
            observation.ForgeSequence,
            observation.EventCursor,
            observationCount = observation.Count,
            observation.FirstAtUtc,
            observation.LastAtUtc
        };
        EnqueueRecord("decision_delivery_summary", payload, sessionId, observation.DecisionId,
            observation.ForgeSequence, observation.EventCursor, _clientRuntimeId);
    }

    private bool TryRememberDecisionGenerationLocked(string generation)
    {
        if (!_recordedDecisionGenerations.Add(generation)) return false;
        _recordedDecisionGenerationOrder.Enqueue(generation);
        while (_recordedDecisionGenerationOrder.Count > 4096)
            _recordedDecisionGenerations.Remove(_recordedDecisionGenerationOrder.Dequeue());
        return true;
    }

    private void ForgetDecisionGenerationLocked(string generation)
    {
        if (!_recordedDecisionGenerations.Remove(generation)) return;
        var retained = _recordedDecisionGenerationOrder
            .Where(key => !string.Equals(key, generation, StringComparison.Ordinal)).ToArray();
        _recordedDecisionGenerationOrder.Clear();
        foreach (var key in retained) _recordedDecisionGenerationOrder.Enqueue(key);
    }

    private async Task WriteRecordAsync(RecorderRecord record, CancellationToken cancellationToken)
    {
        if (_activeSegmentSessionId != record.SessionId)
        {
            await CloseSegmentAsync(recovered: false, cancellationToken).ConfigureAwait(false);
            OpenSegment(record.SessionId!);
        }
        using var payloadDocument = JsonDocument.Parse(record.PayloadJson);
        var payload = payloadDocument.RootElement;
        var sequence = _sequences.AddOrUpdate(record.SessionId!, 1, static (_, previous) => previous + 1);
        var unsigned = new UnsignedEnvelope(CurrentSchemaVersion, sequence, record.TimestampUtc, record.Type,
            record.SessionId, record.DecisionId, record.ForgeSequence, record.EventCursor, record.ClientRuntimeId,
            _bridgeProcessInstanceId, _bridgeBuildIdentity, payload);
        var checksum = Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(unsigned, JsonOptions))).ToLowerInvariant();
        var envelope = new FlightRecorderEnvelope(CurrentSchemaVersion, sequence, record.TimestampUtc,
            record.Type, record.SessionId, record.DecisionId, record.ForgeSequence, record.EventCursor,
            record.ClientRuntimeId, payload, checksum, _bridgeProcessInstanceId, _bridgeBuildIdentity);
        var line = JsonSerializer.Serialize(envelope, JsonOptions);
        var bytes = Encoding.UTF8.GetByteCount(line) + 1;
        if (_segmentRecordCount > 0 && _segmentBytes + bytes > Math.Max(1024, _options.MaxSegmentBytes))
        {
            await CloseSegmentAsync(recovered: false, cancellationToken).ConfigureAwait(false);
            OpenSegment(record.SessionId!);
        }
        await _writer!.WriteLineAsync(line.AsMemory(), cancellationToken).ConfigureAwait(false);
        _segmentBytes += bytes;
        if (_segmentRecordCount == 0) _segmentFirstSequence = sequence;
        _segmentLastSequence = sequence;
        _segmentRecordCount++;
        Interlocked.Increment(ref _recordsWritten);
    }

    private async Task WritePendingLossAsync(CancellationToken cancellationToken)
    {
        foreach (var entry in _pendingDroppedBySession.ToArray())
        {
            if (!_pendingDroppedBySession.TryRemove(entry.Key, out var dropped) || dropped <= 0) continue;
            Interlocked.Add(ref _pendingDropped, -dropped);
            await WriteRecordAsync(new RecorderRecord(DateTimeOffset.UtcNow, "recorder_loss", entry.Key,
                null, null, null, _clientRuntimeId,
                JsonSerializer.SerializeToUtf8Bytes(new { droppedRecords = dropped, reason = "bounded_queue_full" }, JsonOptions)), cancellationToken)
                .ConfigureAwait(false);
        }
    }

    private void OpenSegment(string sessionId)
    {
        Directory.CreateDirectory(GetRootDirectory());
        _activeDirectory = Path.Combine(GetRootDirectory(), SafeSegment(sessionId));
        Directory.CreateDirectory(_activeDirectory);
        _activeSegmentSessionId = sessionId;
        _segmentNumber = Directory.EnumerateFiles(_activeDirectory, "segment-*.jsonl*")
            .Select(path => ParseSegmentNumber(Path.GetFileName(path)))
            .DefaultIfEmpty(0).Max() + 1;
        _activeSegmentPath = Path.Combine(_activeDirectory, $"segment-{_segmentNumber:D6}.jsonl.open");
        _stream = new FileStream(_activeSegmentPath, FileMode.CreateNew, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete,
            64 * 1024, FileOptions.Asynchronous | FileOptions.SequentialScan);
        _writer = new StreamWriter(_stream, new UTF8Encoding(false), 64 * 1024, leaveOpen: true);
        _segmentFirstSequence = 0;
        _segmentLastSequence = 0;
        _segmentRecordCount = 0;
        _segmentBytes = 0;
    }

    private async Task FlushWriterAsync(CancellationToken cancellationToken)
    {
        if (_writer is null) return;
        await _writer.FlushAsync(cancellationToken).ConfigureAwait(false);
        if (_stream is not null) await _stream.FlushAsync(cancellationToken).ConfigureAwait(false);
    }

    private async Task CloseSegmentAsync(bool recovered, CancellationToken cancellationToken)
    {
        if (_writer is null || _activeSegmentPath is null || _activeDirectory is null || _activeSegmentSessionId is null) return;
        await _writer.FlushAsync(cancellationToken).ConfigureAwait(false);
        if (_stream is not null) await _stream.FlushAsync(cancellationToken).ConfigureAwait(false);
        await _writer.DisposeAsync().ConfigureAwait(false);
        if (_stream is not null) await _stream.DisposeAsync().ConfigureAwait(false);
        _writer = null;
        _stream = null;
        var closedPath = _activeSegmentPath.EndsWith(".open", StringComparison.OrdinalIgnoreCase)
            ? _activeSegmentPath[..^5] : _activeSegmentPath;
        if (_segmentRecordCount > 0 && !string.Equals(_activeSegmentPath, closedPath, StringComparison.OrdinalIgnoreCase))
        {
            File.Move(_activeSegmentPath, closedPath, overwrite: true);
            var bytes = new FileInfo(closedPath).Length;
            var hash = Convert.ToHexString(SHA256.HashData(await File.ReadAllBytesAsync(closedPath, cancellationToken).ConfigureAwait(false))).ToLowerInvariant();
            var metadata = new FlightRecorderSegmentMetadata(CurrentSchemaVersion, _activeSegmentSessionId,
                Path.GetFileName(closedPath), _segmentFirstSequence, _segmentLastSequence, _segmentRecordCount,
                bytes, hash, recovered, DateTimeOffset.UtcNow);
            await WriteAtomicJsonAsync(Path.ChangeExtension(closedPath, ".meta.json"), metadata, cancellationToken).ConfigureAwait(false);
            var dropped = _droppedBySession.GetValueOrDefault(_activeSegmentSessionId);
            var matchCompleted = _completedSessions.Contains(_activeSegmentSessionId);
            var recordingFinalized = _finalizedSessions.Contains(_activeSegmentSessionId);
            var missingData = dropped > 0 || _storageFaulted || _interruptedSessions.Contains(_activeSegmentSessionId);
            await WriteManifestAsync(_activeDirectory, _activeSegmentSessionId,
                complete: matchCompleted && recordingFinalized && !missingData,
                matchCompleted: matchCompleted,
                recordingFinalized: recordingFinalized,
                missingData: missingData,
                cancellationToken: cancellationToken).ConfigureAwait(false);
            EnforceRetention();
        }
        else if (File.Exists(_activeSegmentPath)) File.Delete(_activeSegmentPath);
        _activeSegmentPath = null;
        _activeDirectory = null;
        _activeSegmentSessionId = null;
        _segmentNumber = 0;
        _segmentFirstSequence = 0;
        _segmentLastSequence = 0;
        _segmentRecordCount = 0;
        _segmentBytes = 0;
        EnforceRetention();
    }

    private void RecoverInterruptedSegments()
    {
        var root = GetRootDirectory();
        if (!Directory.Exists(root)) return;
        foreach (var path in Directory.EnumerateFiles(root, "segment-*.jsonl.open", SearchOption.AllDirectories))
        {
            try
            {
                var validLines = new List<string>();
                var bytes = File.ReadAllBytes(path);
                var start = 0;
                var validEnd = 0;
                for (var index = 0; index < bytes.Length; index++)
                {
                    if (bytes[index] != (byte)'\n') continue;
                    var length = index - start;
                    if (length > 0 && bytes[index - 1] == (byte)'\r') length--;
                    var line = Encoding.UTF8.GetString(bytes, start, length);
                    if (!VerifyLine(line)) break;
                    validLines.Add(line);
                    validEnd = index + 1;
                    start = index + 1;
                }
                if (validEnd < bytes.Length) File.WriteAllBytes(path, bytes[..validEnd]);
                if (validLines.Count == 0) { File.Delete(path); continue; }
                var sessionId = Path.GetFileName(Path.GetDirectoryName(path));
                var closedPath = path[..^5];
                File.Move(path, closedPath, overwrite: true);
                var records = validLines.Select(ParseSequence).ToArray();
                var metadata = new FlightRecorderSegmentMetadata(CurrentSchemaVersion, sessionId!,
                    Path.GetFileName(closedPath), records.Min(), records.Max(), records.Length,
                    new FileInfo(closedPath).Length,
                    Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(closedPath))).ToLowerInvariant(), true, DateTimeOffset.UtcNow);
                WriteAtomicJsonAsync(Path.ChangeExtension(closedPath, ".meta.json"), metadata, CancellationToken.None).GetAwaiter().GetResult();
                lock (_stateSync)
                {
                    _interruptedSessions.Add(sessionId!);
                    _finalizedSessions.Remove(sessionId!);
                }
                _logger.LogWarning("Recovered interrupted flight recorder segment {Path} records={RecordCount}", closedPath, validLines.Count);
            }
            catch (Exception exception) { _logger.LogError(exception, "Flight recorder segment recovery failed for {Path}", path); }
        }
    }

    private void LoadExistingSequenceState()
    {
        var root = GetRootDirectory();
        if (!Directory.Exists(root)) return;
        foreach (var manifestPath in Directory.EnumerateFiles(root, "manifest.json", SearchOption.AllDirectories))
        {
            try
            {
                using var manifest = JsonDocument.Parse(File.ReadAllText(manifestPath));
                var sessionId = GetString(manifest.RootElement, "sessionId");
                if (sessionId is null) continue;
                if (manifest.RootElement.TryGetProperty("recordingFinalized", out var finalized)
                    && finalized.ValueKind == JsonValueKind.True)
                    lock (_stateSync)
                    {
                        if (!_interruptedSessions.Contains(sessionId)) _finalizedSessions.Add(sessionId);
                    }
                if (manifest.RootElement.TryGetProperty("matchCompleted", out var completed)
                    && completed.ValueKind == JsonValueKind.True)
                    lock (_stateSync) _completedSessions.Add(sessionId);
            }
            catch (Exception exception) { _logger.LogWarning(exception, "Could not read flight recorder manifest {Path}", manifestPath); }
        }
        foreach (var metadataPath in Directory.EnumerateFiles(root, "segment-*.meta.json", SearchOption.AllDirectories))
        {
            try
            {
                var metadata = JsonSerializer.Deserialize<FlightRecorderSegmentMetadata>(File.ReadAllText(metadataPath), JsonOptions);
                if (metadata?.RecoveredAfterInterruption == true)
                    lock (_stateSync) _interruptedSessions.Add(metadata.SessionId);
            }
            catch (Exception exception) { _logger.LogWarning(exception, "Could not read flight recorder segment metadata {Path}", metadataPath); }
        }
        foreach (var path in Directory.EnumerateFiles(root, "segment-*.jsonl", SearchOption.AllDirectories))
        {
            try
            {
                foreach (var line in File.ReadLines(path))
                {
                    if (!VerifyLine(line)) continue;
                    using var document = JsonDocument.Parse(line);
                    var row = document.RootElement;
                    var sessionId = GetString(row, "sessionId");
                    if (sessionId is null) continue;
                    var sequence = row.GetProperty("sequence").GetInt64();
                    _sequences.AddOrUpdate(sessionId, sequence, (_, current) => Math.Max(current, sequence));
                    if (GetString(row, "type") == "decision_offered")
                    {
                        var decisionId = GetString(row, "decisionId") ?? "";
                        var generation = string.Join("|", sessionId, decisionId,
                            GetLong(row, "forgeSequence")?.ToString() ?? "?", GetLong(row, "eventCursor")?.ToString() ?? "?");
                        lock (_stateSync) TryRememberDecisionGenerationLocked(generation);
                    }
                    else if (GetString(row, "type") == "match_completed")
                    {
                        lock (_stateSync) _completedSessions.Add(sessionId);
                    }
                    else if (GetString(row, "type") == "recorder_loss"
                        && row.TryGetProperty("payload", out var payload)
                        && payload.TryGetProperty("droppedRecords", out var droppedNode)
                        && droppedNode.TryGetInt64(out var dropped))
                    {
                        _droppedBySession.AddOrUpdate(sessionId, dropped, (_, current) => current + dropped);
                        Interlocked.Add(ref _recordsDropped, dropped);
                    }
                }
            }
            catch (Exception exception) { _logger.LogWarning(exception, "Could not read existing flight recorder segment {Path}", path); }
        }
    }

    private async Task RefreshInterruptedManifestsAsync(CancellationToken cancellationToken)
    {
        foreach (var sessionId in _interruptedSessions)
        {
            var directory = Path.Combine(GetRootDirectory(), SafeSegment(sessionId));
            if (!Directory.Exists(directory)) continue;
            await WriteManifestAsync(directory, sessionId, complete: false,
                matchCompleted: _completedSessions.Contains(sessionId), recordingFinalized: false,
                missingData: true, cancellationToken: cancellationToken).ConfigureAwait(false);
        }
    }

    private bool VerifyLine(string line)
    {
        try
        {
            using var document = JsonDocument.Parse(line);
            var root = document.RootElement;
            if (root.GetProperty("schemaVersion").GetInt32() != CurrentSchemaVersion) return false;
            var unsigned = new UnsignedEnvelope(
                root.GetProperty("schemaVersion").GetInt32(), root.GetProperty("sequence").GetInt64(),
                root.GetProperty("timestampUtc").GetDateTimeOffset(), root.GetProperty("type").GetString()!,
                GetString(root, "sessionId"), GetString(root, "decisionId"), GetLong(root, "forgeSequence"),
                GetLong(root, "eventCursor"), GetString(root, "clientRuntimeId"),
                GetString(root, "bridgeProcessInstanceId"), GetString(root, "bridgeBuildIdentity"),
                root.GetProperty("payload").Clone());
            var expected = Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(unsigned, JsonOptions))).ToLowerInvariant();
            return CryptographicOperations.FixedTimeEquals(Encoding.ASCII.GetBytes(expected), Encoding.ASCII.GetBytes(root.GetProperty("checksumSha256").GetString() ?? string.Empty));
        }
        catch { return false; }
    }

    private void EnforceRetention()
    {
        try
        {
            var root = GetRootDirectory();
            if (!Directory.Exists(root)) return;
            var matchDirectories = new DirectoryInfo(root).EnumerateDirectories()
                .OrderBy(directory => directory.LastWriteTimeUtc).ToList();
            var activePath = _sessionId is null ? _activeDirectory : Path.Combine(root, SafeSegment(_sessionId));
            if (activePath is not null) activePath = Path.GetFullPath(activePath);
            long totalBytes = matchDirectories.Sum(DirectoryBytes);
            foreach (var directory in matchDirectories.ToArray())
            {
                var isActive = activePath is not null && string.Equals(Path.GetFullPath(directory.FullName), activePath, StringComparison.OrdinalIgnoreCase);
                var overCount = matchDirectories.Count > Math.Max(1, _options.RetentionMatchCount);
                var overSize = totalBytes > Math.Max(1, _options.MaxDiskBytes);
                if ((!overCount && !overSize) || isActive) continue;
                var size = DirectoryBytes(directory);
                ForgetRetainedMatch(directory);
                directory.Delete(recursive: true);
                totalBytes -= size;
                matchDirectories.Remove(directory);
            }
            if (totalBytes > Math.Max(1, _options.MaxDiskBytes))
            {
                lock (_stateSync)
                {
                    _storageFaulted = true;
                    _storageError = "Maximum recorder disk usage reached; no inactive match can be removed.";
                }
            }
        }
        catch (Exception exception) { SetStorageFault(exception); }
    }

    private static long DirectoryBytes(DirectoryInfo directory) => directory.EnumerateFiles("*", SearchOption.AllDirectories).Sum(file => file.Length);

    private void ForgetRetainedMatch(DirectoryInfo directory)
    {
        var sessionId = directory.Name;
        var manifestPath = Path.Combine(directory.FullName, "manifest.json");
        if (File.Exists(manifestPath))
        {
            try
            {
                using var manifest = JsonDocument.Parse(File.ReadAllText(manifestPath));
                sessionId = GetString(manifest.RootElement, "sessionId") ?? sessionId;
            }
            catch { }
        }
        _sequences.TryRemove(sessionId, out _);
        _droppedBySession.TryRemove(sessionId, out _);
        _pendingDroppedBySession.TryRemove(sessionId, out _);
        lock (_stateSync)
        {
            _completedSessions.Remove(sessionId);
            _finalizedSessions.Remove(sessionId);
            _interruptedSessions.Remove(sessionId);
            _deliveryObservations.Remove(sessionId);
            var prefix = sessionId + "|";
            var retained = _recordedDecisionGenerationOrder
                .Where(key => !key.StartsWith(prefix, StringComparison.Ordinal)).ToArray();
            _recordedDecisionGenerationOrder.Clear();
            _recordedDecisionGenerations.Clear();
            foreach (var key in retained)
            {
                _recordedDecisionGenerationOrder.Enqueue(key);
                _recordedDecisionGenerations.Add(key);
            }
        }
    }

    private async Task WriteManifestAsync(string directory, string sessionId, bool complete,
        bool matchCompleted, bool recordingFinalized, bool missingData, CancellationToken cancellationToken)
    {
        var files = Directory.EnumerateFiles(directory, "segment-*.jsonl").OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
            .Select(path => new FileInfo(path)).Select(file => new { file.Name, file.Length }).ToArray();
        var manifest = new
        {
            schemaVersion = CurrentSchemaVersion,
            sessionId,
            updatedAtUtc = DateTimeOffset.UtcNow,
            complete,
            matchCompleted,
            recordingFinalized,
            missingData,
            enabled = _options.Enabled,
            segments = files,
            recordsDropped = _droppedBySession.GetValueOrDefault(sessionId),
            storageFaulted = _storageFaulted,
            storageError = _storageError,
            recording = _recording && _sessionId == sessionId && !_finalizedSessions.Contains(sessionId)
        };
        await WriteAtomicJsonAsync(Path.Combine(directory, "manifest.json"), manifest, cancellationToken).ConfigureAwait(false);
    }

    private static async Task WriteAtomicJsonAsync<T>(string path, T value, CancellationToken cancellationToken)
    {
        var temporary = path + ".tmp";
        await File.WriteAllTextAsync(temporary, JsonSerializer.Serialize(value, JsonOptions), new UTF8Encoding(false), cancellationToken).ConfigureAwait(false);
        File.Move(temporary, path, overwrite: true);
    }

    private void EnqueueControl(WorkKind kind, CancellationToken cancellationToken)
    {
        var item = new WorkItem(kind, null, null);
        if (!_queue.Writer.TryWrite(item)) _queue.Writer.WriteAsync(item, cancellationToken).AsTask().GetAwaiter().GetResult();
    }

    private string GetRootDirectory() => Path.GetFullPath(string.IsNullOrWhiteSpace(_options.Directory)
        ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MtgTtsBridge", "Recordings")
        : _options.Directory);

    private static string SafeSegment(string value)
    {
        var chars = value.Select(character => char.IsAsciiLetterOrDigit(character) || character is '-' or '_' ? character : '_').ToArray();
        return new string(chars);
    }

    private static int ParseSegmentNumber(string name)
    {
        var digits = new string(name.SkipWhile(character => character != '-').Skip(1).TakeWhile(char.IsDigit).ToArray());
        return int.TryParse(digits, out var number) ? number : 0;
    }

    private static long ParseSequence(string line) => JsonDocument.Parse(line).RootElement.GetProperty("sequence").GetInt64();
    private static string? GetString(JsonElement element, string property) => element.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
    private static long? GetLong(JsonElement element, string property) => element.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.Number ? value.GetInt64() : null;

    private void SetStorageFault(Exception exception)
    {
        lock (_stateSync)
        {
            _storageFaulted = true;
            _storageError = exception.Message;
        }
        _logger.LogError(exception, "Flight recorder storage failed; gameplay continues without recording");
    }

    private sealed record RecorderRecord(DateTimeOffset TimestampUtc, string Type, string? SessionId,
        string? DecisionId, long? ForgeSequence, long? EventCursor, string? ClientRuntimeId, byte[] PayloadJson);
    private sealed record WorkItem(WorkKind Kind, RecorderRecord? Record, TaskCompletionSource? Completion,
        long ReservedBytes = 0);
    private sealed record UnsignedEnvelope(int SchemaVersion, long Sequence, DateTimeOffset TimestampUtc, string Type,
        string? SessionId, string? DecisionId, long? ForgeSequence, long? EventCursor, string? ClientRuntimeId,
        string? BridgeProcessInstanceId, string? BridgeBuildIdentity, JsonElement Payload);
    private sealed record DeliveryObservation(string GenerationKey, string DecisionId, long? ForgeSequence,
        long? EventCursor, int Count, DateTimeOffset FirstAtUtc, DateTimeOffset LastAtUtc);
    private enum WorkKind { Record, Flush, CloseSegment }
}

public sealed class FlightRecorderCheckpointService : BackgroundService
{
    private readonly IForgeAdapter _adapter;
    private readonly FlightRecorderService _recorder;
    private readonly ILogger<FlightRecorderCheckpointService> _logger;

    public FlightRecorderCheckpointService(IForgeAdapter adapter, FlightRecorderService recorder,
        ILogger<FlightRecorderCheckpointService> logger) => (_adapter, _recorder, _logger) = (adapter, recorder, logger);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(5));
        while (await timer.WaitForNextTickAsync(stoppingToken).ConfigureAwait(false))
        {
            var status = _recorder.GetStatus();
            if (!status.Recording || status.StorageFaulted) continue;
            try
            {
                var state = await _adapter.GetStateAsync(stoppingToken).ConfigureAwait(false);
                if (state.SessionId == "session-not-started" || string.IsNullOrWhiteSpace(state.SessionId)) continue;
                _recorder.BeginMatch(state.SessionId);
                var snapshot = await _adapter.GetSnapshotAsync(stoppingToken).ConfigureAwait(false);
                if (snapshot is not null) _recorder.RecordSnapshot(snapshot);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { return; }
            catch (Exception exception) { _logger.LogWarning(exception, "Flight recorder checkpoint poll failed; gameplay remains authoritative in Forge"); }
        }
    }
}
