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
    IReadOnlyList<TtsPerformanceTraceRecordDto>? RecentTtsTrace = null);

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
