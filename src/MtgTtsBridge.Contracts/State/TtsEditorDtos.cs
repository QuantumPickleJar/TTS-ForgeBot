namespace MtgTtsBridge.Contracts.State;

public sealed record TtsEditorStatusResponseDto(
    bool Enabled,
    bool ListenerActive,
    string ListenHost,
    int ListenPort,
    string TtsHost,
    int TtsPort,
    long LatestCallbackSequence,
    DateTimeOffset? LatestCallbackUtc,
    bool HasGlobalScriptState,
    string? LatestGeneratedGlobalLuaSha256,
    string? LatestCanonicalContentSha256,
    int? LatestCanonicalLength,
    TtsExternalEditorRuntimeErrorDto? LatestRuntimeError = null);

public sealed record TtsExternalEditorRuntimeErrorDto(
    int MessageId,
    string Error,
    DateTimeOffset ReceivedUtc);

public sealed record TtsEditorRefreshResponseDto(
    long BaselineCallbackSequence,
    long ObservedCallbackSequence,
    string GeneratedGlobalLuaSha256,
    string CanonicalContentSha256,
    int CanonicalLength,
    DateTimeOffset ObservedCallbackUtc);

public sealed record TtsEditorPushGlobalRequestDto(
    string GlobalLua,
    string ExpectedGeneratedGlobalLuaSha256);

public sealed record TtsEditorPushGlobalResponseDto(
    long BaselineCallbackSequence,
    long ObservedCallbackSequence,
    string ExpectedGeneratedGlobalLuaSha256,
    string VerifiedGeneratedGlobalLuaSha256,
    string CanonicalContentSha256,
    int CanonicalLength,
    DateTimeOffset ObservedCallbackUtc);

public sealed record TtsEditorErrorResponseDto(
    string ErrorCode,
    string Message,
    string? ExpectedGeneratedGlobalLuaSha256 = null,
    string? ActualGeneratedGlobalLuaSha256 = null,
    string? ExpectedCanonicalContentSha256 = null,
    string? ActualCanonicalContentSha256 = null,
    int? ExpectedCanonicalLength = null,
    int? ActualCanonicalLength = null,
    int? FirstDiffIndex = null);
