using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Options;
using MtgTtsBridge.Contracts.State;

namespace MtgTtsBridge.TtsEditor;

public sealed class TtsExternalEditorService : IHostedService, ITtsExternalEditorService, IDisposable
{
    private readonly ILogger<TtsExternalEditorService> _logger;
    private readonly TtsExternalEditorOptions _options;
    private readonly TtsExternalEditorCallbackTracker _tracker = new();
    private readonly SemaphoreSlim _operationGate = new(1, 1);
    private readonly JsonSerializerOptions _jsonOptions = new(JsonSerializerDefaults.Web);
    private readonly object _listenerSync = new();

    private TcpListener? _listener;
    private CancellationTokenSource? _listenerCts;
    private Task? _listenerTask;
    private volatile bool _listenerActive;

    public TtsExternalEditorService(IOptions<TtsExternalEditorOptions> options, ILogger<TtsExternalEditorService> logger)
    {
        _logger = logger;
        _options = options.Value;
    }

    public TtsEditorStatusResponseDto GetStatus()
    {
        var snapshot = _tracker.Snapshot();
        var global = snapshot.LatestGlobalScriptState;
        return new TtsEditorStatusResponseDto(
            Enabled: _options.Enabled,
            ListenerActive: _listenerActive,
            ListenHost: _options.ListenHost,
            ListenPort: _options.ListenPort,
            TtsHost: _options.TtsHost,
            TtsPort: _options.TtsPort,
            LatestCallbackSequence: snapshot.LatestCallbackSequence,
            LatestCallbackUtc: snapshot.LatestCallbackUtc,
            HasGlobalScriptState: global is not null,
            LatestGeneratedGlobalLuaSha256: global?.GeneratedGlobalLuaSha256,
            LatestCanonicalContentSha256: global?.CanonicalContentSha256,
            LatestCanonicalLength: global?.CanonicalLength);
    }

    public async Task<TtsEditorRefreshResponseDto> RefreshAsync(CancellationToken cancellationToken)
    {
        EnsureOperationsAvailable();

        await _operationGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            EnsureOperationsAvailable();
            var baseline = _tracker.Snapshot().LatestCallbackSequence;
            await SendCommandAsync(new ExternalEditorEnvelope(MessageId: 0), cancellationToken).ConfigureAwait(false);
            var observed = await WaitForNextGlobalCallbackAsync(baseline, cancellationToken, "refresh_timeout", "Timed out waiting for TTS refresh callback.")
                .ConfigureAwait(false);
            return new TtsEditorRefreshResponseDto(
                BaselineCallbackSequence: baseline,
                ObservedCallbackSequence: observed.Sequence,
                GeneratedGlobalLuaSha256: observed.GeneratedGlobalLuaSha256 ?? string.Empty,
                CanonicalContentSha256: observed.CanonicalContentSha256,
                CanonicalLength: observed.CanonicalLength,
                ObservedCallbackUtc: observed.ReceivedUtc);
        }
        finally
        {
            _operationGate.Release();
        }
    }

    public async Task<TtsEditorPushGlobalResponseDto> PushGlobalAsync(TtsEditorPushGlobalRequestDto request, CancellationToken cancellationToken)
    {
        EnsureOperationsAvailable();

        if (string.IsNullOrWhiteSpace(request.GlobalLua))
            throw new TtsEditorOperationException("invalid_request", "GlobalLua must be supplied.", StatusCodes.Status400BadRequest);
        if (string.IsNullOrWhiteSpace(request.ExpectedGeneratedGlobalLuaSha256))
            throw new TtsEditorOperationException("invalid_request", "ExpectedGeneratedGlobalLuaSha256 must be supplied.", StatusCodes.Status400BadRequest);

        var expectedGeneratedSha = request.ExpectedGeneratedGlobalLuaSha256.Trim().ToLowerInvariant();
        var embeddedSha = TtsGlobalScriptComparer.ExtractEmbeddedGeneratedSha256(request.GlobalLua);
        if (!string.Equals(expectedGeneratedSha, embeddedSha, StringComparison.OrdinalIgnoreCase))
        {
            throw new TtsEditorOperationException(
                "generated_sha_mismatch",
                "Provided Global.lua does not contain the expected embedded generated SHA.")
            {
                Details = new TtsEditorErrorResponseDto(
                    ErrorCode: "generated_sha_mismatch",
                    Message: "Provided Global.lua does not contain the expected embedded generated SHA.",
                    ExpectedGeneratedGlobalLuaSha256: expectedGeneratedSha,
                    ActualGeneratedGlobalLuaSha256: embeddedSha)
            };
        }

        await _operationGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            EnsureOperationsAvailable();
            var current = await EnsureCurrentGlobalStateAsync(cancellationToken).ConfigureAwait(false);
            var replacement = new ExternalEditorScriptState(
                Name: string.IsNullOrWhiteSpace(current.Name) ? "Global" : current.Name,
                Guid: "-1",
                Script: request.GlobalLua,
                Ui: current.Ui);

            var baseline = _tracker.Snapshot().LatestCallbackSequence;
            await SendCommandAsync(new ExternalEditorEnvelope(1, [replacement]), cancellationToken).ConfigureAwait(false);
            var observed = await WaitForNextGlobalCallbackAsync(baseline, cancellationToken, "reload_timeout", "Timed out waiting for TTS Save & Play reload callback.")
                .ConfigureAwait(false);

            if (!string.Equals(expectedGeneratedSha, observed.GeneratedGlobalLuaSha256, StringComparison.OrdinalIgnoreCase))
            {
                throw new TtsEditorOperationException(
                    "generated_sha_mismatch",
                    "TTS reloaded Global.lua but the embedded generated SHA did not match.")
                {
                    Details = new TtsEditorErrorResponseDto(
                        ErrorCode: "generated_sha_mismatch",
                        Message: "TTS reloaded Global.lua but the embedded generated SHA did not match.",
                        ExpectedGeneratedGlobalLuaSha256: expectedGeneratedSha,
                        ActualGeneratedGlobalLuaSha256: observed.GeneratedGlobalLuaSha256)
                };
            }

            var canonicalComparison = TtsGlobalScriptComparer.CompareCanonicalContent(request.GlobalLua, observed.Script);
            if (!canonicalComparison.IsMatch)
            {
                throw new TtsEditorOperationException(
                    "content_mismatch",
                    "TTS reloaded Global.lua with matching generated identity, but canonicalized content differed.")
                {
                    Details = new TtsEditorErrorResponseDto(
                        ErrorCode: "content_mismatch",
                        Message: "TTS reloaded Global.lua with matching generated identity, but canonicalized content differed.",
                        ExpectedGeneratedGlobalLuaSha256: expectedGeneratedSha,
                        ActualGeneratedGlobalLuaSha256: observed.GeneratedGlobalLuaSha256,
                        ExpectedCanonicalContentSha256: canonicalComparison.ExpectedCanonicalContentSha256,
                        ActualCanonicalContentSha256: canonicalComparison.ActualCanonicalContentSha256,
                        ExpectedCanonicalLength: canonicalComparison.ExpectedCanonicalLength,
                        ActualCanonicalLength: canonicalComparison.ActualCanonicalLength,
                        FirstDiffIndex: canonicalComparison.FirstDiffIndex)
                };
            }

            return new TtsEditorPushGlobalResponseDto(
                BaselineCallbackSequence: baseline,
                ObservedCallbackSequence: observed.Sequence,
                ExpectedGeneratedGlobalLuaSha256: expectedGeneratedSha,
                VerifiedGeneratedGlobalLuaSha256: observed.GeneratedGlobalLuaSha256 ?? string.Empty,
                CanonicalContentSha256: canonicalComparison.ActualCanonicalContentSha256,
                CanonicalLength: canonicalComparison.ActualCanonicalLength,
                ObservedCallbackUtc: observed.ReceivedUtc);
        }
        finally
        {
            _operationGate.Release();
        }
    }

    public Task StartAsync(CancellationToken cancellationToken)
    {
        if (!_options.Enabled)
        {
            _logger.LogInformation("TTS external-editor service disabled by configuration.");
            return Task.CompletedTask;
        }

        var listenAddress = ParseLoopbackAddress(_options.ListenHost);
        var listener = new TcpListener(listenAddress, _options.ListenPort);

        try
        {
            listener.Start();
        }
        catch (Exception exception)
        {
            throw new InvalidOperationException(
                $"TTS external-editor listener cannot start on {_options.ListenHost}:{_options.ListenPort}. " +
                "Stop or inspect the existing owner; the bridge will not terminate other processes automatically. " +
                exception.Message,
                exception);
        }

        lock (_listenerSync)
        {
            _listener = listener;
            _listenerCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            _listenerTask = Task.Run(() => RunListenerLoopAsync(listener, _listenerCts.Token));
            _listenerActive = true;
        }

        _logger.LogInformation("TTS external-editor listener: {Host}:{Port}", _options.ListenHost, _options.ListenPort);
        Console.WriteLine($"TTS external-editor listener: {_options.ListenHost}:{_options.ListenPort}");
        return Task.CompletedTask;
    }

    public async Task StopAsync(CancellationToken cancellationToken)
    {
        Task? listenerTask;
        CancellationTokenSource? listenerCts;
        TcpListener? listener;

        lock (_listenerSync)
        {
            listenerTask = _listenerTask;
            listenerCts = _listenerCts;
            listener = _listener;
            _listenerTask = null;
            _listenerCts = null;
            _listener = null;
            _listenerActive = false;
        }

        listenerCts?.Cancel();
        try { listener?.Stop(); } catch { }

        if (listenerTask is not null)
        {
            try
            {
                await listenerTask.WaitAsync(cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { }
            catch (Exception exception)
            {
                _logger.LogDebug(exception, "TTS external-editor listener stop observed non-fatal exception.");
            }
        }

        listenerCts?.Dispose();
    }

    public void Dispose()
    {
        _listenerCts?.Cancel();
        _listenerCts?.Dispose();
        _listenerCts = null;
        try { _listener?.Stop(); } catch { }
        _listener = null;
        _operationGate.Dispose();
    }

    private void EnsureOperationsAvailable()
    {
        if (!_options.Enabled)
            throw new TtsEditorOperationException("listener_unavailable", "TTS external-editor service is disabled.", StatusCodes.Status503ServiceUnavailable);
        if (!_listenerActive)
            throw new TtsEditorOperationException("listener_unavailable", "TTS external-editor listener is not active.", StatusCodes.Status503ServiceUnavailable);
    }

    private async Task RunListenerLoopAsync(TcpListener listener, CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            TcpClient? client = null;
            try
            {
                client = await listener.AcceptTcpClientAsync(cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                break;
            }
            catch (ObjectDisposedException) when (cancellationToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception exception)
            {
                _logger.LogError(exception, "TTS external-editor listener failed accepting callback client.");
                continue;
            }

            _ = HandleClientAsync(client, cancellationToken);
        }
    }

    private async Task HandleClientAsync(TcpClient client, CancellationToken cancellationToken)
    {
        using (client)
        {
            await using var stream = client.GetStream();
            using var bufferStream = new MemoryStream();
            var buffer = new byte[64 * 1024];

            while (true)
            {
                int read;
                try
                {
                    read = await stream.ReadAsync(buffer, cancellationToken).ConfigureAwait(false);
                }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
                {
                    return;
                }
                catch (Exception exception)
                {
                    _logger.LogWarning(exception, "TTS external-editor callback read failed.");
                    return;
                }

                if (read == 0) break;
                bufferStream.Write(buffer, 0, read);
            }

            if (bufferStream.Length == 0) return;

            try
            {
                using var document = JsonDocument.Parse(bufferStream.ToArray());
                _tracker.TryProcessIncomingMessage(document.RootElement, _logger);
            }
            catch (JsonException exception)
            {
                _logger.LogWarning(exception, "Ignoring malformed JSON callback from TTS external-editor.");
            }
        }
    }

    private async Task<TtsExternalEditorGlobalScriptState> EnsureCurrentGlobalStateAsync(CancellationToken cancellationToken)
    {
        var snapshot = _tracker.Snapshot();
        if (snapshot.LatestGlobalScriptState is not null) return snapshot.LatestGlobalScriptState;

        var baseline = snapshot.LatestCallbackSequence;
        await SendCommandAsync(new ExternalEditorEnvelope(0), cancellationToken).ConfigureAwait(false);
        return await WaitForNextGlobalCallbackAsync(
            baseline,
            cancellationToken,
            "refresh_timeout",
            "Timed out waiting for current TTS Global script state before Save & Play.").ConfigureAwait(false);
    }

    private async Task<TtsExternalEditorGlobalScriptState> WaitForNextGlobalCallbackAsync(
        long baseline,
        CancellationToken cancellationToken,
        string timeoutErrorCode,
        string timeoutMessage)
    {
        try
        {
            return await _tracker.WaitForGlobalScriptStateAfterSequenceAsync(
                baseline,
                TimeSpan.FromSeconds(Math.Max(1, _options.OperationTimeoutSeconds)),
                cancellationToken).ConfigureAwait(false);
        }
        catch (TimeoutException exception)
        {
            throw new TtsEditorOperationException(timeoutErrorCode, timeoutMessage, StatusCodes.Status504GatewayTimeout)
            {
                Details = new TtsEditorErrorResponseDto(timeoutErrorCode, timeoutMessage)
            };
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw new TtsEditorOperationException("operation_cancelled", "TTS external-editor operation was cancelled by shutdown or caller.", StatusCodes.Status409Conflict)
            {
                Details = new TtsEditorErrorResponseDto("operation_cancelled", "TTS external-editor operation was cancelled by shutdown or caller.")
            };
        }
    }

    private async Task SendCommandAsync(ExternalEditorEnvelope command, CancellationToken cancellationToken)
    {
        var payload = JsonSerializer.Serialize(command, _jsonOptions);
        var bytes = Encoding.UTF8.GetBytes(payload);
        using var client = new TcpClient();

        try
        {
            await client.ConnectAsync(_options.TtsHost, _options.TtsPort, cancellationToken).ConfigureAwait(false);
            await using var stream = client.GetStream();
            await stream.WriteAsync(bytes, cancellationToken).ConfigureAwait(false);
            await stream.FlushAsync(cancellationToken).ConfigureAwait(false);
            try { client.Client.Shutdown(SocketShutdown.Send); } catch { }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            throw new TtsEditorOperationException(
                "tts_command_connect_failed",
                $"Could not send TTS external-editor command to {_options.TtsHost}:{_options.TtsPort}. {exception.Message}",
                StatusCodes.Status503ServiceUnavailable)
            {
                Details = new TtsEditorErrorResponseDto(
                    "tts_command_connect_failed",
                    $"Could not send TTS external-editor command to {_options.TtsHost}:{_options.TtsPort}. {exception.Message}")
            };
        }
    }

    private static IPAddress ParseLoopbackAddress(string host)
    {
        if (IPAddress.TryParse(host, out var parsed) && IPAddress.IsLoopback(parsed)) return parsed;
        throw new InvalidOperationException($"TtsEditor:ListenHost must be a loopback address. Current value: '{host}'.");
    }

    private sealed record ExternalEditorEnvelope(
        [property: JsonPropertyName("messageID")] int MessageId,
        [property: JsonPropertyName("scriptStates")] IReadOnlyList<ExternalEditorScriptState>? ScriptStates = null);

    private sealed record ExternalEditorScriptState(
        [property: JsonPropertyName("name")] string Name,
        [property: JsonPropertyName("guid")] string Guid,
        [property: JsonPropertyName("script")] string Script,
        [property: JsonPropertyName("ui")] string Ui);
}
