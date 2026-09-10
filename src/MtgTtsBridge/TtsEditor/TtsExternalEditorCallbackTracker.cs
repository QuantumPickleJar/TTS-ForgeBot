using System.Text.Json;

namespace MtgTtsBridge.TtsEditor;

public sealed record TtsExternalEditorGlobalScriptState(
    long Sequence,
    DateTimeOffset ReceivedUtc,
    string Name,
    string Guid,
    string Script,
    string Ui,
    string? GeneratedGlobalLuaSha256,
    string CanonicalContentSha256,
    int CanonicalLength);

public sealed record TtsExternalEditorTrackerSnapshot(
    long LatestCallbackSequence,
    DateTimeOffset? LatestCallbackUtc,
    TtsExternalEditorGlobalScriptState? LatestGlobalScriptState);

public sealed class TtsExternalEditorCallbackTracker
{
    private readonly object _sync = new();
    private readonly object _waitSync = new();
    private TaskCompletionSource<long> _nextGlobalCallback = NewWaiter();
    private long _latestCallbackSequence;
    private DateTimeOffset? _latestCallbackUtc;
    private TtsExternalEditorGlobalScriptState? _latestGlobal;

    public TtsExternalEditorTrackerSnapshot Snapshot()
    {
        lock (_sync)
        {
            return new TtsExternalEditorTrackerSnapshot(_latestCallbackSequence, _latestCallbackUtc, _latestGlobal);
        }
    }

    public bool TryProcessIncomingMessage(JsonElement root, ILogger logger)
    {
        if (!TryGetMessageId(root, out var messageId))
        {
            logger.LogWarning("Ignoring TTS external-editor callback without numeric messageID.");
            return false;
        }

        if (messageId != 1)
        {
            if (messageId == 3 && root.TryGetProperty("error", out var errorElement) && errorElement.ValueKind == JsonValueKind.String)
            {
                logger.LogWarning("TTS external-editor callback messageID=3 error={Error}", errorElement.GetString());
            }
            else
            {
                logger.LogDebug("Ignoring asynchronous TTS external-editor callback messageID={MessageId}", messageId);
            }

            return false;
        }

        if (!TryParseGlobalScriptState(root, out var parsedState, out var parseError))
        {
            logger.LogWarning("Ignoring TTS script-state callback without usable Global script state: {Reason}", parseError);
            return false;
        }

        var receivedUtc = DateTimeOffset.UtcNow;
        var sequence = Interlocked.Increment(ref _latestCallbackSequence);
        var canonical = TtsGlobalScriptComparer.CanonicalizeForTransportComparison(parsedState.Script);
        var state = new TtsExternalEditorGlobalScriptState(
            Sequence: sequence,
            ReceivedUtc: receivedUtc,
            Name: parsedState.Name,
            Guid: parsedState.Guid,
            Script: parsedState.Script,
            Ui: parsedState.Ui,
            GeneratedGlobalLuaSha256: TtsGlobalScriptComparer.ExtractEmbeddedGeneratedSha256(parsedState.Script),
            CanonicalContentSha256: TtsGlobalScriptComparer.CanonicalSha256(canonical),
            CanonicalLength: canonical.Length);

        lock (_sync)
        {
            _latestCallbackUtc = receivedUtc;
            _latestGlobal = state;
        }

        SignalGlobalCallback(sequence);
        logger.LogDebug("Accepted TTS script-state callback sequence={Sequence}", sequence);
        return true;
    }

    public async Task<TtsExternalEditorGlobalScriptState> WaitForGlobalScriptStateAfterSequenceAsync(
        long baselineSequence,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        using var timeoutCts = new CancellationTokenSource(timeout);
        using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(timeoutCts.Token, cancellationToken);

        while (true)
        {
            var snapshot = Snapshot();
            if (snapshot.LatestGlobalScriptState is not null && snapshot.LatestGlobalScriptState.Sequence > baselineSequence)
            {
                return snapshot.LatestGlobalScriptState;
            }

            Task waitTask;
            lock (_waitSync)
            {
                waitTask = _nextGlobalCallback.Task;
            }

            try
            {
                await waitTask.WaitAsync(linkedCts.Token).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (timeoutCts.IsCancellationRequested && !cancellationToken.IsCancellationRequested)
            {
                throw new TimeoutException($"Timed out waiting for TTS script-state callback sequence > {baselineSequence}.");
            }
        }
    }

    private static TaskCompletionSource<long> NewWaiter() => new(TaskCreationOptions.RunContinuationsAsynchronously);

    private void SignalGlobalCallback(long sequence)
    {
        TaskCompletionSource<long> waiter;
        lock (_waitSync)
        {
            waiter = _nextGlobalCallback;
            _nextGlobalCallback = NewWaiter();
        }

        waiter.TrySetResult(sequence);
    }

    private static bool TryGetMessageId(JsonElement root, out int messageId)
    {
        messageId = default;
        if (!root.TryGetProperty("messageID", out var messageIdElement)) return false;
        if (messageIdElement.ValueKind == JsonValueKind.Number) return messageIdElement.TryGetInt32(out messageId);
        if (messageIdElement.ValueKind != JsonValueKind.String) return false;
        return int.TryParse(messageIdElement.GetString(), out messageId);
    }

    private static bool TryParseGlobalScriptState(JsonElement root, out (string Name, string Guid, string Script, string Ui) state, out string reason)
    {
        state = default;
        reason = string.Empty;

        if (!root.TryGetProperty("scriptStates", out var scriptStates) || scriptStates.ValueKind != JsonValueKind.Array)
        {
            reason = "scriptStates was missing or not an array";
            return false;
        }

        JsonElement? globalByGuid = null;
        JsonElement? globalByName = null;
        foreach (var candidate in scriptStates.EnumerateArray())
        {
            if (candidate.ValueKind != JsonValueKind.Object) continue;
            var guid = candidate.TryGetProperty("guid", out var guidValue) && guidValue.ValueKind == JsonValueKind.String
                ? guidValue.GetString() : null;
            var name = candidate.TryGetProperty("name", out var nameValue) && nameValue.ValueKind == JsonValueKind.String
                ? nameValue.GetString() : null;
            if (string.Equals(guid, "-1", StringComparison.Ordinal)) globalByGuid = candidate;
            else if (string.Equals(name, "Global", StringComparison.Ordinal)) globalByName = candidate;
        }

        var selected = globalByGuid ?? globalByName;
        if (selected is null)
        {
            reason = "no scriptStates entry matched guid=-1 or name=Global";
            return false;
        }

        var script = selected.Value.TryGetProperty("script", out var scriptValue) && scriptValue.ValueKind == JsonValueKind.String
            ? scriptValue.GetString() ?? string.Empty
            : string.Empty;
        var nameResult = selected.Value.TryGetProperty("name", out var nameResultValue) && nameResultValue.ValueKind == JsonValueKind.String
            ? nameResultValue.GetString() ?? "Global"
            : "Global";
        var guidResult = selected.Value.TryGetProperty("guid", out var guidResultValue) && guidResultValue.ValueKind == JsonValueKind.String
            ? guidResultValue.GetString() ?? "-1"
            : "-1";
        var ui = selected.Value.TryGetProperty("ui", out var uiValue) && uiValue.ValueKind == JsonValueKind.String
            ? uiValue.GetString() ?? string.Empty
            : string.Empty;

        state = (nameResult, guidResult, script, ui);
        return true;
    }
}
