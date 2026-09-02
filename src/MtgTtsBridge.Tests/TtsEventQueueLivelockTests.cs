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

    [Fact]
    public void QueueHeadStallReportsTheActualSchedulerFenceWithoutApplyingTheEvent()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.animationRunning = true
            BridgeState.eventQueue = {{sequence=78, kind='card_moved', seatId='forge-player-2', sourceZone='hand', destinationZone='library', containsHiddenIdentity=true}}
            applyCount = 0
            function BridgeApplyAuthoritativeEvent(event) applyCount = applyCount + 1; return true, 0 end
            log = function(message) lastLog = message end
            function BridgeWaitTime(callback, delay) end
            directBlockReason = tostring(BridgeEventDrainBlockReason())
            BridgeProcessEventQueue()
            BridgeRecordEventDrainStall(BridgeEventDrainQueueState())
        ");

        Assert.Equal("animationRunning", lua.Globals.Get("directBlockReason").String);
        Assert.Equal(0, lua.Globals.Get("applyCount").Number);
        Assert.Equal(7, lua.Globals.Get("BridgeState").Table.Get("lastAppliedEventSequence").Number);
        Assert.Equal("animationRunning", lua.Globals.Get("BridgeState").Table.Get("eventDrainWatchdog").Table.Get("lastBlockReason").ToPrintString());
        Assert.Contains("EVENT_DRAIN_STALLED", lua.Globals.Get("lastLog").String);
    }

    [Fact]
    public void ManualResyncRetiresWedgeAndSupersedesTheOldEventQueue()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            probeClock = 0
            os.clock = function() return probeClock end
            BridgeState.eventSessionId = 'session'
            BridgeState.eventQueue = {{sequence=78, kind='card_moved'}}
            BridgeState.lastAppliedEventSequence = 77
            BridgeState.lastReceivedEventSequence = 96
            BridgeState.libraryExtractionActiveBySeatId['forge-player-1'] = true
            BridgeState.libraryExtractionQueueBySeatId['forge-player-1'] = {{}}
            BridgeState.ui = {resyncInFlight=false}
            function BridgeWaitFrames(callback, frames) probeClock = probeClock + 1; callback() end
            function BridgeWaitTime(callback, delay) end
            function BridgeStopEventPolling(reason) end
            function BridgeStopDecisionPolling() end
            function BridgeResumeChoiceProtocol(reason) end
            function BridgeClearHighlights() end
            function BridgeResetSelectionState() end
            function BridgeHideMainPriorityControls() end
            function BridgeSetStatus(headline, detail) end
            function BridgeUiMarkDirty(reason) end
            function BridgeStartEventPolling(sessionId, skipExisting) end
            function BridgeStartDecisionPolling() end
            function BridgeBootstrapCurrentSnapshot(sessionId, callback, resume, origin)
                BridgeState.lastReceivedEventSequence = 96
                BridgeState.lastAppliedEventSequence = 96
                BridgeState.eventQueue = {}
                callback(true, nil)
            end
            BridgeResyncFromAuthoritativeSnapshot('hud')
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        Assert.Equal(96, state.Get("lastAppliedEventSequence").Number);
        Assert.Equal(0, state.Get("eventQueue").Table.Length);
        Assert.False(state.Get("resyncInFlight").Boolean);
        Assert.Equal(0, state.Get("ui").Table.Get("resyncInFlight").Boolean ? 1 : 0);
    }

    [Fact]
    public void SameSessionResyncFailureRestoresTheCommittedCheckpoint()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'session'
            BridgeState.eventQueue = {{sequence=78, kind='card_moved'}}
            BridgeState.lastAppliedEventSequence = 77
            BridgeState.lastReceivedEventSequence = 96
            BridgeState.ui = {resyncInFlight=false}
            function BridgeWaitFrames(callback, frames) end
            function BridgeWaitTime(callback, delay) end
            function BridgeStopEventPolling(reason) end
            function BridgeStopDecisionPolling() end
            function BridgeResumeChoiceProtocol(reason) end
            function BridgeClearHighlights() end
            function BridgeResetSelectionState() end
            function BridgeHideMainPriorityControls() end
            function BridgeSetStatus(headline, detail) end
            function BridgeUiMarkDirty(reason) end
            function BridgeStartEventPolling(sessionId, skipExisting) end
            function BridgeStartDecisionPolling() end
            function BridgeBootstrapCurrentSnapshot(sessionId, callback, resume, origin)
                BridgeState.lastReceivedEventSequence = 0
                BridgeState.lastAppliedEventSequence = 0
                BridgeState.eventQueue = {}
                callback(false, 'snapshot stage failed')
            end
            BridgeResyncFromAuthoritativeSnapshot('hud')
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        Assert.Equal(96, state.Get("lastReceivedEventSequence").Number);
        Assert.Equal(77, state.Get("lastAppliedEventSequence").Number);
        Assert.True(state.Get("desyncLatched").Boolean);
    }

    [Fact]
    public void DesyncLatchAlwaysSchedulesRecovery()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'session'
            BridgeState.desyncLatched = true
            BridgeState.resyncInFlight = false
            BridgeState.resyncScheduled = false
            function BridgeWaitFrames(callback, frames) recoveryScheduled = true end
            BridgeEnsureDesyncRecovery('test')
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        Assert.True(lua.Globals.Get("recoveryScheduled").Boolean);
        Assert.True(state.Get("resyncScheduled").Boolean);
    }

    [Fact]
    public void RetiredLibraryCallbackCannotMutateThePostResyncQueues()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'session'
            capturedGeneration = BridgeState.physicalTransactionGeneration
            staleCallbackWouldMutate = false
            function staleCallback()
                if BridgePhysicalPresentationIsCurrent('session', capturedGeneration) then
                    staleCallbackWouldMutate = true
                end
            end
            BridgeRetireLocalPhysicalTransactions('manual-resync-force')
            staleCallback()
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        Assert.False(lua.Globals.Get("staleCallbackWouldMutate").Boolean);
        Assert.Equal(1, state.Get("physicalTransactionGeneration").Number);
    }

    [Fact]
    public void StalledAutomaticResyncReleasesItsLocalLatchAndInvalidatesBootstrap()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'session'
            BridgeState.resyncToken = 4
            BridgeState.resyncInFlight = true
            BridgeState.bootstrapping = true
            BridgeState.resyncStartedAt = 0
            BridgeState.ui = {resyncInFlight=true}
            BridgeSetStatus = function(headline, detail) end
            BridgeUiMarkDirty = function(reason) end
            Time.time = 31
            released = BridgeCheckResyncWatchdog('test-clock')
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        Assert.True(lua.Globals.Get("released").Boolean);
        Assert.False(state.Get("resyncInFlight").Boolean);
        Assert.False(state.Get("bootstrapping").Boolean);
        Assert.False(state.Get("ui").Table.Get("resyncInFlight").Boolean);
        Assert.Equal(5, state.Get("resyncToken").Number);
        Assert.Equal(1, state.Get("resyncBootstrapGeneration").Number);
    }

    [Fact]
    public void AutomaticResyncBehindPhysicalQueueUsesOneBoundedRetry()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'session'
            BridgeState.libraryExtractionActiveBySeatId['forge-player-1'] = true
            BridgeState.resyncDeferredRetryScheduled = false
            BridgeState.resyncDeferredSince = nil
            Time.time = 1
            retrySchedules = 0
            function BridgeWaitFrames(callback, frames) retrySchedules = retrySchedules + 1 end
            BridgeResyncFromAuthoritativeSnapshot('library order mismatch')
            BridgeResyncFromAuthoritativeSnapshot('library order mismatch')
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        Assert.Equal(1, lua.Globals.Get("retrySchedules").Number);
        Assert.True(state.Get("resyncDeferredRetryScheduled").Boolean);
        Assert.Equal("physical-library-queue", state.Get("resyncDeferredReason").String);
    }

    [Fact]
    public void ValidMulliganSnapshotSupersedesQueuedIntermediateEvents()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.eventQueue = {}
            for sequence = 76, 88 do
                table.insert(BridgeState.eventQueue, {sequence=sequence, kind='card_moved', sourceZone='hand', destinationZone='library'})
            end
            table.insert(BridgeState.eventQueue, {sequence=89, kind='draw', sourceZone='library', destinationZone='hand'})
            BridgeState.lastReceivedEventSequence = 88
            BridgeState.lastAppliedEventSequence = 75
            BridgeSupersedeEventsThroughSnapshot(88, 'mulligan-checkpoint')
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        Assert.Equal(88, state.Get("lastReceivedEventSequence").Number);
        Assert.Equal(1, state.Get("eventQueue").Table.Length);
    }

    [Fact]
    public void SnapshotCheckpointCommitsCursorAndSupersedesFetchlandTailAtomically()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.eventQueue = {}
            for sequence = 216, 230 do
                table.insert(BridgeState.eventQueue, {sequence=sequence, kind='phase_changed'})
            end
            BridgeState.lastReceivedEventSequence = 230
            BridgeState.lastAppliedEventSequence = 215
            BridgeState.resyncOrigin = 'library order mismatch'
            BridgeState.resyncBootstrapGeneration = 4
            local snapshot = {sessionId='session', eventCursor=230, forgeSequence=31}
            local ok, err = BridgeCommitSnapshotCheckpoint(snapshot, 'fetchland-recovery')
            checkpointOk, checkpointError = ok, err
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        Assert.True(lua.Globals.Get("checkpointOk").Boolean);
        Assert.Equal(230, state.Get("lastAppliedEventSequence").Number);
        Assert.Equal(230, state.Get("lastConsumedEventSequence").Number);
        Assert.Equal(230, state.Get("lastStateProjectedEventSequence").Number);
        Assert.Equal(0, state.Get("eventQueue").Table.Length);
    }

    [Fact]
    public void SameSessionResyncStagesMappingsAndRollsThemBackWithoutLosingTheCommittedRegistry()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'session'
            BridgeState.physicalByInstanceId = { ['old-card'] = 'old-guid' }
            BridgeState.physicalInstanceIdByGuid = { ['old-guid'] = 'old-card' }
            BridgeState.physicalSeatByGuid = { ['old-guid'] = 'forge-player-1' }
            BridgeState.physicalZoneByGuid = { ['old-guid'] = 'battlefield' }
            BridgeState.eventQueue = {{sequence=89, kind='card_moved'}}
            BridgeState.lastReceivedEventSequence = 88
            BridgeState.lastAppliedEventSequence = 88
            BridgeBeginResyncMappingTransaction()
            BridgeState.physicalByInstanceId = { ['new-card'] = 'new-guid' }
            BridgeState.physicalInstanceIdByGuid = { ['new-guid'] = 'new-card' }
            BridgeRestoreResyncMappingTransaction('staged-reconcile-failed')
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        Assert.Equal("old-guid", state.Get("physicalByInstanceId").Table.Get("old-card").String);
        Assert.Equal("old-card", state.Get("physicalInstanceIdByGuid").Table.Get("old-guid").String);
        Assert.Equal(88, state.Get("lastAppliedEventSequence").Number);
        Assert.Equal(1, state.Get("eventQueue").Table.Length);
    }

    [Fact]
    public void ValidSnapshotCheckpointReattachesTheCurrentDecisionExactlyOnce()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'session'
            BridgeState.eventQueue = {{sequence=89, kind='card_moved'}}
            BridgeState.lastReceivedEventSequence = 88
            BridgeState.lastAppliedEventSequence = 88
            BridgeState.ui = {resyncInFlight=false}
            function BridgeWaitFrames(callback, frames) end
            function BridgeWaitTime(callback, delay) end
            function BridgeStopEventPolling(reason) end
            function BridgeStopDecisionPolling() end
            function BridgeResumeChoiceProtocol(reason) end
            function BridgeClearHighlights() end
            function BridgeResetSelectionState() end
            function BridgeHideMainPriorityControls() end
            function BridgeSetStatus(headline, detail) end
            function BridgeUiMarkDirty(reason) end
            function BridgeStartEventPolling(sessionId, skipExisting) end
            function BridgeGetDecision(callback)
                callback(true, {
                    decisionId='forge-tui-13', sessionId='session', eventCursor=95,
                    kind='main_priority', seatId='forge-player-1',
                    actions={{actionId='pass-13', type='pass_priority'}}
                }, nil)
            end
            reattached = 0
            function BridgeAcceptDecision(decision, origin, sessionId, presentationGeneration)
                reattached = reattached + 1
                BridgeState.lastDecision = decision
            end
            function BridgeBootstrapCurrentSnapshot(sessionId, callback, resume, origin)
                BridgeState.lastReceivedEventSequence = 95
                BridgeState.lastAppliedEventSequence = 95
                BridgeState.eventQueue = {}
                callback(true, nil)
            end
            BridgeResyncFromAuthoritativeSnapshot('manual')
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        Assert.Equal(95, state.Get("lastAppliedEventSequence").Number);
        Assert.Equal(0, state.Get("eventQueue").Table.Length);
        Assert.Equal("forge-tui-13", state.Get("lastDecision").Table.Get("decisionId").String);
        Assert.Equal(1, lua.Globals.Get("reattached").Number);
        Assert.False(state.Get("resyncInFlight").Boolean);
    }

    [Fact]
    public void RecoveryOwnsSchedulersAndSuspendsFastForward()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.ui = {fastForwardActive=true, autoAdvanceMode='FAST-FORWARD'}
            BridgeState.schedulerOwner = 'NORMAL'
            BridgeState.eventSessionId = 'session'
            BridgeState.resyncToken = 0
            BridgeState.resyncInFlight = false
            BridgeState.resyncCircuitOpen = false
            BridgeState.libraryExtractionActiveBySeatId = {}
            BridgeState.libraryExtractionQueueBySeatId = {}
            function BridgeGetEmbodimentSnapshot(callback) end
            function BridgeStopEventPolling(reason) end
            function BridgeStopDecisionPolling() end
            function BridgeResumeChoiceProtocol(reason) end
            function BridgeClearHighlights() end
            function BridgeResetSelectionState() end
            function BridgeHideMainPriorityControls() end
            function BridgeSetStatus(headline, detail) end
            function BridgeUiMarkDirty(reason) end
            function BridgeWaitTime(callback, delay) end
            function BridgeWaitFrames(callback, frames) end
            BridgeResyncFromAuthoritativeSnapshot('library order mismatch')
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        Assert.Equal("RESYNC", state.Get("schedulerOwner").String);
        Assert.False(state.Get("ui").Table.Get("fastForwardActive").Boolean);
        Assert.True(state.Get("fastForwardSuspendedByResync").Boolean);
    }

    [Fact]
    public void RepeatedIdenticalRecoverySnapshotsOpenCircuitInsteadOfChurning()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'session'
            BridgeState.resyncInFlight = false
            BridgeState.resyncNoProgress = nil
            BridgeRecordResyncSnapshotProgress('library order mismatch', {eventCursor=230, forgeSequence=31})
            BridgeRecordResyncSnapshotProgress('library order mismatch', {eventCursor=230, forgeSequence=31})
            BridgeRecordResyncSnapshotProgress('library order mismatch', {eventCursor=230, forgeSequence=31})
        ");

        Assert.True(lua.Globals.Get("BridgeState").Table.Get("resyncCircuitOpen").Boolean);
        Assert.Equal(1, lua.Globals.Get("BridgeState").Table.Get("resyncNoProgressAttempts").Number);
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
            BridgeState.eventDrainWatchdog = {}
            BridgeState.libraryExtractionQueueBySeatId = {}
            BridgeState.libraryExtractionActiveBySeatId = {}
            BridgeState.mulliganBottomQueueBySeatId = {}
            BridgeState.mulliganBottomInsertionActiveBySeatId = {}
        ");
        return lua;
    }
}
