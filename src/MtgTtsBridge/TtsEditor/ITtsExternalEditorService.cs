using MtgTtsBridge.Contracts.State;

namespace MtgTtsBridge.TtsEditor;

public interface ITtsExternalEditorService
{
    TtsEditorStatusResponseDto GetStatus();
    Task<TtsEditorRefreshResponseDto> RefreshAsync(CancellationToken cancellationToken);
    Task<TtsEditorPushGlobalResponseDto> PushGlobalAsync(TtsEditorPushGlobalRequestDto request, CancellationToken cancellationToken);
}

public sealed class TtsEditorOperationException : Exception
{
    public TtsEditorOperationException(string errorCode, string message, int statusCode = StatusCodes.Status409Conflict)
        : base(message)
    {
        ErrorCode = errorCode;
        StatusCode = statusCode;
    }

    public string ErrorCode { get; }

    public int StatusCode { get; }

    public TtsEditorErrorResponseDto? Details { get; init; }
}
