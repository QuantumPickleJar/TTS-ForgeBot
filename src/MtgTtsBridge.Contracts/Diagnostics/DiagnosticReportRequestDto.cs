using System.Text.Json;
using System.Text.Json.Serialization;

namespace MtgTtsBridge.Contracts.Diagnostics;

/// <summary>Presentation-side context supplied by TTS when a tester captures a report.</summary>
public sealed record DiagnosticReportRequestDto(
    string? Summary = null,
    string? Category = null,
    string? SessionId = null,
    string? DecisionId = null,
    string? ClientRuntimeId = null,
    string? ClientRevision = null,
    string? ClientGeneratedGlobalLuaSha256 = null,
    string? ExpectedGeneratedGlobalLuaSha256 = null,
    string? RuntimeCompatibilityState = null,
    long? LastAppliedEventSequence = null,
    int? Turn = null,
    string? Phase = null,
    string? ActivePlayer = null,
    string? PriorityPlayer = null,
    IReadOnlyList<string>? MappedCardInstanceIds = null,
    IReadOnlyList<DiagnosticPhysicalMappingDto>? PhysicalMappings = null,
    string? Status = null,
    DiagnosticPresentedResultDto? PresentedResult = null,
    DiagnosticPerformanceSummaryDto? PerformanceSummary = null,
    IReadOnlyList<TtsPerformanceTraceRecordDto>? RecentTtsTrace = null,
    IReadOnlyList<DiagnosticCaptureLifecycleRecordDto>? DiagnosticCaptureLifecycle = null,
    DiagnosticEventDrainDiagnosticsDto? EventDrainDiagnostics = null);

public sealed record DiagnosticPresentedResultDto(
    bool Presented = false,
    string? SourceEventId = null,
    long? SourceEventCursor = null,
    string? SourceSessionId = null,
    string? Outcome = null,
    string? Reason = null,
    int? PresentationGeneration = null,
    bool TerminalRecoveryError = false);

/// <summary>Live TTS evidence for one authoritative physical mapping.</summary>
public sealed record DiagnosticPhysicalMappingDto(
    string CardInstanceId,
    string Guid,
    string? Zone = null,
    bool IsLive = false,
    string? AdvertisedCardInstanceId = null);

/// <summary>Bounded scheduler state captured when the TTS event head cannot start.</summary>
public sealed record DiagnosticEventDrainDiagnosticsDto(
    long? HeadSequence = null,
    string? HeadKind = null,
    string? HeadSourceZone = null,
    string? HeadDestinationZone = null,
    int QueueLength = 0,
    long? LastReceived = null,
    long? LastApplied = null,
    string? BlockReason = null,
    bool AnimationRunning = false,
    bool PhysicalLibraryQueuesIdle = true,
    bool EventPolling = false,
    bool EventRequestInFlight = false,
    bool EventPollScheduled = false,
    bool SnapshotReconcilePending = false,
    bool SnapshotReconcileInFlight = false,
    bool DesyncLatched = false,
    bool ResyncInFlight = false,
    bool Bootstrapping = false,
    bool TerminalRecoveryError = false,
    IReadOnlyDictionary<string, DiagnosticPhysicalQueueStateDto>? PhysicalQueues = null,
    JsonElement? PhysicalMutationProgress = null,
    JsonElement? PhysicalMutationJournal = null,
    JsonElement? LastTtsRuntimeError = null,
    JsonElement? OwnedMutation = null,
    int? EmbodimentEpoch = null,
    int? EmbodimentTransactionToken = null,
    bool EmbodimentActive = false,
    string? EmbodimentReason = null,
    string? EmbodimentSessionId = null,
    long? EmbodimentTargetCursor = null,
    string? EmbodimentPhase = null,
    int? EmbodimentOperationIndex = null,
    int? EmbodimentReplanCount = null,
    long? EmbodimentLastProgressUpdateTick = null,
    string? EmbodimentLastBlockingPredicate = null,
    IReadOnlyList<DiagnosticEmbodimentJournalRecordDto>? EmbodimentJournal = null,
    string? BootstrapStage = null,
    double? BootstrapStageChangedAt = null,
    double? BootstrapLastProgressAt = null,
    string? LastSnapshotReconcileFailureStage = null,
    string? LastSnapshotReconcileFailureReason = null,
    IReadOnlyList<DiagnosticBootstrapStageRecordDto>? BootstrapStageTrace = null,
    DiagnosticPhysicalZoneOwnershipDto? SnapshotPhysicalZoneOwnership = null,
    IReadOnlyDictionary<string, DiagnosticLibraryMappingDto>? BootstrapLibraryMappings = null,
    int ExpectedLibraryMappings = 0,
    int VerifiedLibraryMappings = 0,
    int MissingLibraryMappings = 0,
    int DuplicateLibraryMappings = 0,
    int UnsettledGuidCount = 0,
    int DuplicateRealGuidCount = 0,
    string? FirstBlockingObservation = null,
    string? FirstActualFailure = null,
    string? CurrentObservedBlocker = null);

public sealed record DiagnosticLibraryMappingDto(
    int ExpectedLibraryMappings = 0,
    int VerifiedLibraryMappings = 0,
    int MissingLibraryMappings = 0,
    int DuplicateLibraryMappings = 0,
    int UnsettledGuidCount = 0,
    int DuplicateRealGuidCount = 0,
    string? Status = null,
    string? LastError = null);

public sealed record DiagnosticEmbodimentJournalRecordDto(
    int? RuntimeEpoch = null,
    int? EmbodimentEpoch = null,
    int? Token = null,
    string? Reason = null,
    string? SessionId = null,
    long? TargetCursor = null,
    string? Phase = null,
    int? OperationIndex = null,
    string? OperationType = null,
    string? OperationToken = null,
    string? Precondition = null,
    string? NativeAction = null,
    string? Postcondition = null,
    string? Detail = null,
    long? UpdateTick = null,
    long? LastProgressUpdateTick = null,
    int? ReplanCount = null,
    string? LastBlockingPredicate = null);

public sealed record DiagnosticBootstrapStageRecordDto(
    string? Stage = null,
    string? State = null,
    string? Detail = null,
    double? At = null,
    long? UpdateTick = null);

[JsonConverter(typeof(DiagnosticPhysicalZoneOwnershipDtoConverter))]
public sealed record DiagnosticPhysicalZoneOwnershipDto(
    int ExpectedHandCount = 0,
    int PhysicallyVerifiedHandCount = 0,
    int InternallyMappedHandCount = 0,
    int RepairedHandCount = 0,
    int NilZoneCount = 0,
    int WrongSeatCount = 0);

/// <summary>
/// TTS serializes an empty Lua table as an array. Accept that legacy empty
/// diagnostic shape so a report request cannot fail merely because no hand
/// ownership audit has run yet.
/// </summary>
public sealed class DiagnosticPhysicalZoneOwnershipDtoConverter : JsonConverter<DiagnosticPhysicalZoneOwnershipDto>
{
    public override DiagnosticPhysicalZoneOwnershipDto? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType == JsonTokenType.Null)
            return null;

        if (reader.TokenType == JsonTokenType.StartArray)
        {
            reader.Skip();
            return new DiagnosticPhysicalZoneOwnershipDto();
        }

        if (reader.TokenType != JsonTokenType.StartObject)
            throw new JsonException("Expected an object or an empty array for snapshot physical zone ownership.");

        using var document = JsonDocument.ParseValue(ref reader);
        var root = document.RootElement;
        return new DiagnosticPhysicalZoneOwnershipDto(
            ExpectedHandCount: ReadInt(root, "expectedHandCount"),
            PhysicallyVerifiedHandCount: ReadInt(root, "physicallyVerifiedHandCount"),
            InternallyMappedHandCount: ReadInt(root, "internallyMappedHandCount"),
            RepairedHandCount: ReadInt(root, "repairedHandCount"),
            NilZoneCount: ReadInt(root, "nilZoneCount"),
            WrongSeatCount: ReadInt(root, "wrongSeatCount"));
    }

    public override void Write(Utf8JsonWriter writer, DiagnosticPhysicalZoneOwnershipDto value, JsonSerializerOptions options)
    {
        writer.WriteStartObject();
        writer.WriteNumber("expectedHandCount", value.ExpectedHandCount);
        writer.WriteNumber("physicallyVerifiedHandCount", value.PhysicallyVerifiedHandCount);
        writer.WriteNumber("internallyMappedHandCount", value.InternallyMappedHandCount);
        writer.WriteNumber("repairedHandCount", value.RepairedHandCount);
        writer.WriteNumber("nilZoneCount", value.NilZoneCount);
        writer.WriteNumber("wrongSeatCount", value.WrongSeatCount);
        writer.WriteEndObject();
    }

    private static int ReadInt(JsonElement root, string propertyName)
        => root.TryGetProperty(propertyName, out var property) && property.TryGetInt32(out var value) ? value : 0;
}

public sealed record DiagnosticPhysicalQueueStateDto(
    bool LibraryExtractionActive = false,
    int LibraryExtractionLength = 0,
    bool MulliganInsertionActive = false,
    int MulliganInsertionLength = 0,
    int? Generation = null);

/// <summary>Bounded TTS-side liveness evidence around a diagnostic capture.</summary>
public sealed record DiagnosticCaptureLifecycleRecordDto(
    double Timestamp,
    string Stage,
    int? Token = null,
    string? Reason = null,
    string? SessionId = null,
    string? DecisionId = null,
    string? DecisionKind = null,
    long? DecisionEventCursor = null,
    long? LastReceivedEventSequence = null,
    long? LastAppliedEventSequence = null,
    int EventQueueLength = 0,
    bool EventPolling = false,
    bool EventRequestInFlight = false,
    bool EventPollScheduled = false,
    int EventPollGeneration = 0,
    int EventSessionGeneration = 0,
    bool DecisionPollInFlight = false,
    bool DecisionPollScheduled = false,
    int DecisionPollGeneration = 0,
    bool DecisionRefreshInFlight = false,
    bool Submitting = false,
    bool ChoiceProtocolPaused = false,
    bool AnimationRunning = false,
    int? YieldPolicyTurnNumber = null,
    string? YieldPolicyActiveSeatId = null,
    string? YieldPolicySessionId = null,
    bool YieldPolicyOwnTurn = false,
    int PresentationGeneration = 0,
    int PhysicalPresentationGeneration = 0,
    int PhysicalTransactionGeneration = 0,
    string? EventDrainBlockReason = null,
    bool ResyncInFlight = false,
    string? ResyncOrigin = null,
    double? ResyncStartedAt = null,
    string? ResyncDeferredReason = null,
    bool ReportCaptureInFlight = false);

/// <summary>Compact, client-side performance counters supplied only at capture time.</summary>
public sealed record DiagnosticPerformanceSummaryDto(
    int SlowRenderCount = 0,
    double WorstRenderDurationMs = 0,
    double WorstClearHighlightsDurationMs = 0,
    double WorstPreparedPresentationDurationMs = 0,
    double WorstCandidateCollectionDurationMs = 0,
    double WorstActionMatchingDurationMs = 0,
    double WorstUiFlushDurationMs = 0,
    double WorstSnapshotReconcileDurationMs = 0,
    int DecisionRenderAttempts = 0,
    int DecisionRenderExecuted = 0,
    int DecisionRenderSkippedIdentical = 0,
    int UiAttributeAttempts = 0,
    int UiAttributeWrites = 0,
    int UiAttributeSkippedIdentical = 0,
    int EncoderRebuildCount = 0,
    int KeywordPropWriteCount = 0,
    int DecalWriteCount = 0,
    int FullSnapshotReconcileCount = 0,
    DiagnosticLandActionCanaryDto? LandActionCanary = null,
    string? ClockKind = null,
    string? WallClockKind = null);

/// <summary>Compact correlation data for the generic land-action canary.</summary>
public sealed record DiagnosticLandActionCanaryDto(
    int? TurnNumber = null,
    string? Phase = null,
    string? ActiveSeatId = null,
    string? PrioritySeatId = null,
    int ForgeLegalLandCount = 0,
    int ForgeLegalInstantFlashCount = 0,
    string? DecisionId = null,
    string? DecisionKind = null,
    int DecisionPlayLandCount = 0,
    int DecisionCastSpellCount = 0,
    bool DecisionPassPriorityPresent = false,
    int TtsRepresentedPlayLandCount = 0,
    int TtsRepresentedCastSpellCount = 0,
    long? EventCursor = null,
    long? LastTtsAppliedEventSequence = null);

/// <summary>A deliberately small Lua trace record; it contains no card names.</summary>
public sealed record TtsPerformanceTraceRecordDto(
    double Timestamp,
    string Marker,
    string? DecisionId = null,
    string? DecisionKind = null,
    long? EventSequence = null,
    double? DurationMs = null,
    int? Detail1 = null,
    int? Detail2 = null,
    double? CpuDurationMs = null,
    double? WallDurationMs = null,
    string? WallClockKind = null);

public sealed record DiagnosticReportResponseDto(
    bool Success,
    string ReportId,
    string ReportPath,
    string Message);

public sealed record DiagnosticReportFailureDto(
    string ErrorCode,
    string Message,
    string? ReportId = null);
