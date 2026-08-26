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
    string? Status = null);

public sealed record DiagnosticReportResponseDto(
    bool Success,
    string ReportId,
    string ReportPath,
    string Message);

public sealed record DiagnosticReportFailureDto(
    string ErrorCode,
    string Message,
    string? ReportId = null);
