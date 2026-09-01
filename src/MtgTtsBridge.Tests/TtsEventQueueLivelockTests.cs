using MoonSharp.Interpreter;

namespace MtgTtsBridge.Tests;

public sealed class TtsEventQueueLivelockTests
{
    private static readonly string Script = File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.lua"));

    [Fact]
    public void SuccessfulEventCommitsOnceWhenPollingGenerationChangesDuringApply()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.eventQueue = {}
            table.insert(BridgeState.eventQueue, {sequence=9, kind='card_moved', seatId='forge-player-2', destinationZone='library', cardInstanceId='forge-object:9'})
            table.insert(BridgeState.eventQueue, {sequence=8, kind='card_moved', seatId='forge-player-2', sourceZone=nil, destinationZone='library', containsHiddenIdentity=true, cardInstanceId='forge-object:8'})
            applyCount = 0
            function BridgeApplyAuthoritativeEvent(event)
                applyCount = applyCount + 1
                if event.sequence == 8 then BridgeState.eventPollGeneration = BridgeState.eventPollGeneration + 1 end
                return true, 0
            end
            BridgeProcessEventQueue()
        ");

        Assert.Equal(1, lua.Globals.Get("applyCount").Number);
        Assert.Equal(8, lua.Globals.Get("BridgeState").Table.Get("lastAppliedEventSequence").Number);
    }

    [Fact]
    public void SessionReplacementAbandonsTheOldQueueWithoutCommittingItsEvent()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.eventQueue = {}
            table.insert(BridgeState.eventQueue, {sequence=9, kind='phase_changed', seatId='forge-player-1'})
            table.insert(BridgeState.eventQueue, {sequence=8, kind='card_moved', seatId='forge-player-2', destinationZone='library', cardInstanceId='forge-object:8'})
            function BridgeApplyAuthoritativeEvent(event)
                BridgeState.eventSessionId = 'replacement'
                BridgeState.eventSessionGeneration = (BridgeState.eventSessionGeneration or 0) + 1
                BridgeState.eventQueue = {}
                table.insert(BridgeState.eventQueue, {sequence=2, kind='phase_changed', seatId='forge-player-1'})
                table.insert(BridgeState.eventQueue, {sequence=1, kind='phase_changed', seatId='forge-player-1'})
                return true, 0
            end
            BridgeProcessEventQueue()
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        Assert.Equal(7, state.Get("lastAppliedEventSequence").Number);
        Assert.Equal("replacement", state.Get("eventSessionId").String);
        Assert.Equal(1, state.Get("eventQueue").Table.Get(1).Table.Get("sequence").Number);
    }

    [Fact]
    public void SuccessfulEventCommitsWhenPollingStopsWithinTheSameSession()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.eventQueue = {}
            table.insert(BridgeState.eventQueue, {sequence=9, kind='phase_changed', seatId='forge-player-1'})
            table.insert(BridgeState.eventQueue, {sequence=8, kind='card_moved', seatId='forge-player-2', destinationZone='library', cardInstanceId='forge-object:8'})
            function BridgeApplyAuthoritativeEvent(event)
                BridgeState.eventPolling = false
                return true, 0
            end
            BridgeProcessEventQueue()
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        Assert.Equal(8, state.Get("lastAppliedEventSequence").Number);
    }

    [Fact]
    public void RepeatedSuccessfulApplyAbortIsReportedAsCommitLivelock()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            local event = {sequence=8, kind='card_moved'}
            for i = 1, 3 do
                BridgeRecordEventCommitAbort(event, 'queue_head_changed', 'session', 1)
            end
        ");

        Assert.Contains("EVENT_COMMIT_LIVELOCK", lua.Globals.Get("desyncReason").String);
    }

    private static Script NewQueueProbe()
    {
        var lua = new Script();
        lua.DoString(@"
            function log(message) end
            function broadcastToAll(message, color) end
            function printToAll(message, color) end
            function getObjectFromGUID(guid) return nil end
            function Wait(frames) end
            Time = { waitForSeconds = function(seconds, callback) callback() end }
            JSON = { encode = function(value) return '{}' end, decode = function(value) return {} end }
            os = { time = function() return 1 end, clock = function() return 0 end }
            math.randomseed(1)
            table.concat = function(values, separator) return 'probe-runtime' end
        ");
        lua.DoString(Script);
        lua.DoString(@"
            function BridgeTryApplyDeferredSnapshotReconcile(reason) end
            function BridgeTryStartPendingSnapshotReconcile(reason) end
            function BridgeTryPresentPendingDecision(reason) end
            function BridgeRefreshDecisionAfterStateTransition(reason) end
            function BridgeShouldReconcileAfterEvent(event) return false end
            function BridgeScheduleSnapshotReconcile(reason, category) end
            function BridgeStopOnDesync(reason) desyncReason = reason end
            function BridgeWaitTime(callback, delay) end
            BridgeState.eventPolling = true
            BridgeState.eventPollGeneration = 4
            BridgeState.eventSessionId = 'session'
            BridgeState.eventSessionGeneration = 1
            BridgeState.lastAppliedEventSequence = 7
            BridgeState.lastReceivedEventSequence = 9
            BridgeState.eventQueue = {}
            BridgeState.animationRunning = false
            BridgeState.eventCommitWatchdog = nil
        ");
        return lua;
    }
}
