namespace MtgTtsBridge.Tests;

public sealed class TtsGlobalLuaContractTests
{
    private static readonly string Script = File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.lua"));

    [Fact]
    public void EventPolling_IsSingleFlightAndRetriesTransientFailures()
    {
        Assert.Contains("eventPollGeneration", Script);
        Assert.Contains("eventRequestInFlight", Script);
        Assert.Contains("eventPollScheduled", Script);
        Assert.Contains("math.min(2 ^ (BridgeState.eventRetryCount - 1), 5)", Script);
        Assert.Contains("BridgeState.eventRetryCount = 0", Script);
        Assert.DoesNotContain("event poll failed: \" .. tostring(err)", Script);
    }

    [Fact]
    public void EventApplication_TracksReceivedAndAppliedCursorsSeparately()
    {
        Assert.Contains("lastReceivedEventSequence", Script);
        Assert.Contains("lastAppliedEventSequence", Script);
        Assert.DoesNotContain("lastEventSequence", Script);

        var failedApplication = Script.IndexOf("if not applied then", StringComparison.Ordinal);
        var appliedAdvance = Script.IndexOf("BridgeState.lastAppliedEventSequence = event.sequence", StringComparison.Ordinal);
        Assert.True(failedApplication >= 0);
        Assert.True(appliedAdvance > failedApplication);
    }

    [Fact]
    public void EventHistoryAndSequenceGaps_StopSynchronization()
    {
        Assert.Contains("body.errorCode == \"event_history_gap\"", Script);
        Assert.Contains("event sequence gap: expected", Script);
        Assert.Contains("event application gap: expected", Script);
        Assert.Contains("BridgeStopOnDesync", Script);
    }

    [Fact]
    public void BattlefieldMovement_ReleasesHandsAndUsesMeasuredBlueAnchors()
    {
        Assert.Contains("land = {x = 6.5, y = 2.0, z = 11.5}", Script);
        Assert.Contains("creature = {x = 7.0, y = 2.0, z = 3.5}", Script);

        var releaseHand = Script.IndexOf("object.use_hands = false", StringComparison.Ordinal);
        var directMove = Script.IndexOf("object.setPosition(destination)", StringComparison.Ordinal);
        Assert.True(releaseHand >= 0);
        Assert.True(directMove > releaseHand);
    }
}
