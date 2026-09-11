using System.Text.Json;
using Microsoft.Extensions.Logging.Abstractions;
using MtgTtsBridge.TtsEditor;

namespace MtgTtsBridge.Tests;

public sealed class TtsExternalEditorCallbackTrackerTests
{
    [Fact]
    public async Task WaitForSequenceAdvance_IgnoresStaleAndNonScriptCallbacks()
    {
        var logger = NullLogger.Instance;
        var tracker = new TtsExternalEditorCallbackTracker();

        tracker.TryProcessIncomingMessage(Parse("""
            {"messageID":1,"scriptStates":[{"name":"Global","guid":"-1","script":"BRIDGE_GENERATED_GLOBAL_LUA_SOURCE_SHA256 = \"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"","ui":""}]}
            """), logger);

        var baseline = tracker.Snapshot().LatestCallbackSequence;
        var waitTask = tracker.WaitForGlobalScriptStateAfterSequenceAsync(baseline, TimeSpan.FromSeconds(2), CancellationToken.None);

        tracker.TryProcessIncomingMessage(Parse("{" + "\"messageID\":3,\"error\":\"async\"}"), logger);
        Assert.Equal(3, tracker.Snapshot().LatestRuntimeError?.MessageId);
        Assert.Equal("async", tracker.Snapshot().LatestRuntimeError?.Error);
        tracker.TryProcessIncomingMessage(Parse("{" + "\"messageID\":1,\"scriptStates\":[{\"name\":\"Deck\",\"guid\":\"123\",\"script\":\"x\"}]}"), logger);

        await Task.Delay(100);
        Assert.False(waitTask.IsCompleted);

        tracker.TryProcessIncomingMessage(Parse("""
            {"messageID":1,"scriptStates":[{"name":"Global","guid":"-1","script":"BRIDGE_GENERATED_GLOBAL_LUA_SOURCE_SHA256 = \"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"","ui":""}]}
            """), logger);

        var observed = await waitTask;
        Assert.True(observed.Sequence > baseline);
        Assert.Equal("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", observed.GeneratedGlobalLuaSha256);
    }

    private static JsonElement Parse(string json)
    {
        using var document = JsonDocument.Parse(json);
        return document.RootElement.Clone();
    }
}
