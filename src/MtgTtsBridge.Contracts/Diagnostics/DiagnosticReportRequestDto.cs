namespace MtgTtsBridge.Contracts.Diagnostics;

/// <summary>Presentation-side context supplied by TTS when a tester captures a report.</summary>
public sealed record DiagnosticReportRequestDto(
    string? Summary = null,
    string? Category = null,
    string? SessionId = null,
    string? DecisionId = null,
    string? ClientRuntimeId = null,
    string? ClientRevision = null,
    long? LastAppliedEventSequence = null,
    int? Turn = null,
    string? Phase = null,
    string? ActivePlayer = null,
    string? PriorityPlayer = null,
    IReadOnlyList<string>? MappedCardInstanceIds = null,
    string? Status = null,
    DiagnosticPerformanceSummaryDto? PerformanceSummary = null,
    IReadOnlyList<TtsPerformanceTraceRecordDto>? RecentTtsTrace = null,
    IReadOnlyList<DiagnosticCaptureLifecycleRecordDto>? DiagnosticCaptureLifecycle = null,
    DiagnosticEventDrainDiagnosticsDto? EventDrainDiagnostics = null);

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
    IReadOnlyDictionary<string, DiagnosticPhysicalQueueStateDto>? PhysicalQueues = null);

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
