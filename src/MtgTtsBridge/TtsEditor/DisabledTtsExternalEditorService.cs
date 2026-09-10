using MtgTtsBridge.Contracts.State;

namespace MtgTtsBridge.TtsEditor;

public sealed class DisabledTtsExternalEditorService : ITtsExternalEditorService
{
    private readonly TtsExternalEditorOptions _options;

    public DisabledTtsExternalEditorService(Microsoft.Extensions.Options.IOptions<TtsExternalEditorOptions> options)
    {
        _options = options.Value;
    }

    public TtsEditorStatusResponseDto GetStatus() => new(
        Enabled: false,
        ListenerActive: false,
        ListenHost: _options.ListenHost,
        ListenPort: _options.ListenPort,
        TtsHost: _options.TtsHost,
        TtsPort: _options.TtsPort,
        LatestCallbackSequence: 0,
        LatestCallbackUtc: null,
        HasGlobalScriptState: false,
        LatestGeneratedGlobalLuaSha256: null,
        LatestCanonicalContentSha256: null,
        LatestCanonicalLength: null);

    public Task<TtsEditorRefreshResponseDto> RefreshAsync(CancellationToken cancellationToken) =>
        Task.FromException<TtsEditorRefreshResponseDto>(
            new TtsEditorOperationException("listener_unavailable", "TTS external-editor service is disabled in this environment.", StatusCodes.Status503ServiceUnavailable)
            {
                Details = new TtsEditorErrorResponseDto("listener_unavailable", "TTS external-editor service is disabled in this environment.")
            });

    public Task<TtsEditorPushGlobalResponseDto> PushGlobalAsync(TtsEditorPushGlobalRequestDto request, CancellationToken cancellationToken) =>
        Task.FromException<TtsEditorPushGlobalResponseDto>(
            new TtsEditorOperationException("listener_unavailable", "TTS external-editor service is disabled in this environment.", StatusCodes.Status503ServiceUnavailable)
            {
                Details = new TtsEditorErrorResponseDto("listener_unavailable", "TTS external-editor service is disabled in this environment.")
            });
}
