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
    public void SameSessionResyncSupersedesStaleBootstrapOwnershipAndFetchesSnapshot()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'session'
            BridgeState.resyncInFlight = true
            BridgeState.bootstrapping = true
            BridgeState.resyncBootstrapGeneration = 4
            snapshotRequests = 0
            function BridgeGetEmbodimentSnapshot(callback)
                snapshotRequests = snapshotRequests + 1
                callback(false, nil, 'probe snapshot failure')
            end
            callbackOk = nil
            callbackError = nil
            BridgeBootstrapCurrentSnapshot('session', function(ok, err)
                callbackOk, callbackError = ok, err
            end, true, 'manual')
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        Assert.Equal(1, lua.Globals.Get("snapshotRequests").Number);
        Assert.False(lua.Globals.Get("callbackOk").Boolean);
        Assert.Equal("authoritative snapshot unavailable: probe snapshot failure",
            lua.Globals.Get("callbackError").String);
        Assert.False(state.Get("bootstrapping").Boolean);
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

    [Fact]
    public void ResumeOnActiveCoherentSessionDoesNotAttachOrResetCheckpoint()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'active-session'
            BridgeState.lifecycleState = 'SESSION_ACTIVE'
            BridgeState.lastReceivedEventSequence = 213
            BridgeState.lastAppliedEventSequence = 213
            BridgeState.lastDecision = {
                decisionId='forge-tui-10', sessionId='active-session', eventCursor=213,
                kind='main_priority', seatId='forge-player-1',
                actions={{actionId='pass-10', type='pass_priority'}}
            }
            BridgeState.desyncLatched = false
            BridgeState.setupBusy = false
            BridgeState.ui = {fastForwardActive=false}
            BridgeDecisionPhysicalMappingsReady = function(decision) return true, nil end
            attached = false
            rendered = false
            eventStarted = false
            function BridgeAttachToActiveSession(done) attached = true end
            function BridgeRenderDecision(decision, force) rendered = true end
            function BridgeStartEventPolling(sessionId, skipExisting) eventStarted = true end
            function BridgeStartDecisionPolling(allowCurrent) end
            function BridgeResumeChoiceProtocol(reason) end
            function BridgeSetSetupBusy(value, detail) BridgeState.setupBusy = value end
            function BridgeSetStatus(headline, detail) end
            function BridgeUiMarkDirty(reason) end
            BridgeWaitFrames = function(callback, frames) callback() end
            BridgeDoPressResume(nil, false)
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        Assert.False(lua.Globals.Get("attached").Boolean);
        Assert.True(lua.Globals.Get("rendered").Boolean);
        Assert.True(lua.Globals.Get("eventStarted").Boolean);
        Assert.Equal("active-session", state.Get("eventSessionId").String);
        Assert.Equal(213, state.Get("lastAppliedEventSequence").Number);
        Assert.Equal("forge-tui-10", state.Get("lastDecision").Table.Get("decisionId").String);
    }

    [Fact]
    public void ResumeWithCurrentCursorMappingDefectRequestsScopedRepairWithoutAttach()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'active-session'
            BridgeState.lifecycleState = 'SESSION_ACTIVE'
            BridgeState.lastReceivedEventSequence = 213
            BridgeState.lastAppliedEventSequence = 213
            BridgeState.lastDecision = {decisionId='forge-tui-10', sessionId='active-session', eventCursor=213, actions={}}
            BridgeState.desyncLatched = true
            BridgeState.desyncLastMessage = 'missing live mapping'
            BridgeState.setupBusy = false
            BridgeState.ui = {fastForwardActive=false}
            BridgeDecisionPhysicalMappingsReady = function(decision) return false, 'mountain-51' end
            attached = false
            repairRequested = false
            function BridgeAttachToActiveSession(done) attached = true end
            function BridgeScheduleSnapshotReconcile(reason, category) repairRequested = reason == 'resume-targeted-mapping-repair' end
            function BridgeSetStatus(headline, detail) end
            function BridgeUiMarkDirty(reason) end
            BridgeDoPressResume(nil, false)
        ");

        Assert.False(lua.Globals.Get("attached").Boolean);
        Assert.True(lua.Globals.Get("repairRequested").Boolean);
        var state = lua.Globals.Get("BridgeState").Table;
        Assert.Equal(213, state.Get("lastAppliedEventSequence").Number);
        Assert.True(state.Get("desyncLatched").Boolean);
    }

    [Fact]
    public void ForgeMutationGroupComparisonUsesSharedPositiveForgeSequenceOnly()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            sameA, seqA = BridgeEventsShareForgeMutationGroup(
                {sequence=8, forgeSequence=44},
                {sequence=9, forgeSequence=44})
            sameB, seqB = BridgeEventsShareForgeMutationGroup(
                {sequence=8, forgeSequence=44},
                {sequence=9, forgeSequence=45})
            sameC, seqC = BridgeEventsShareForgeMutationGroup(
                {sequence=8, forgeSequence=0},
                {sequence=9, forgeSequence=0})
        ");

        Assert.True(lua.Globals.Get("sameA").Boolean);
        Assert.Equal(44, lua.Globals.Get("seqA").Number);
        Assert.False(lua.Globals.Get("sameB").Boolean);
        Assert.True(lua.Globals.Get("seqB").Number > 0);
        Assert.False(lua.Globals.Get("sameC").Boolean);
        Assert.Equal(0, lua.Globals.Get("seqC").Number);
    }

    [Fact]
    public void DecisionIsDeferredWhenQueuedEventsShareItsForgeMutationSequence()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.lastAppliedEventSequence = 20
            BridgeState.eventQueue = {{sequence=21, kind='card_moved', forgeSequence=77, seatId='forge-player-1'}}
            defer, cursor, applied, reason, detail = BridgeShouldDeferDecision({
                decisionId='forge-tui-21',
                kind='main_priority',
                seatId='forge-player-1',
                eventCursor=20,
                forgeSequence=77,
                actions={{actionId='pass-21', type='pass_priority'}}
            })
        ");

        Assert.True(lua.Globals.Get("defer").Boolean);
        Assert.Equal("causal_dependency_pending", lua.Globals.Get("reason").String);
        Assert.Contains("forgeSequence=77", lua.Globals.Get("detail").String);
        Assert.Equal(20, lua.Globals.Get("cursor").Number);
        Assert.Equal(20, lua.Globals.Get("applied").Number);
    }

    [Fact]
    public void G2B_MentalNoteQueueEntryDoesNotBlockDecisionProgression()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.lastAppliedEventSequence = 20
            BridgeState.eventQueue = {{sequence=21, kind='mental_note', forgeSequence=0, summary='waiting for next authoritative mutation'}}
            defer, cursor, applied, reason = BridgeShouldDeferDecision({
                decisionId='forge-tui-21',
                kind='main_priority',
                seatId='forge-player-1',
                eventCursor=20,
                forgeSequence=77,
                actions={{actionId='pass-21', type='pass_priority'}}
            })
        ");

        Assert.False(lua.Globals.Get("defer").Boolean);
        Assert.Equal(20, lua.Globals.Get("cursor").Number);
        Assert.Equal(20, lua.Globals.Get("applied").Number);
        Assert.True(lua.Globals.Get("reason").IsNil() || string.IsNullOrWhiteSpace(lua.Globals.Get("reason").String));
    }

    [Fact]
    public void StaleDecisionAcceptanceDoesNotCrashAndRearmsDecisionPolling()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'session'
            BridgeState.decisionPresentationGeneration = 1
            BridgeState.lastAppliedEventSequence = 48
            BridgeState.lastReceivedEventSequence = 48
            BridgeState.lastAppliedForgeSequence = 9
            BridgeState.currentPhase = 'Main phase, precombat'
            BridgeState.choiceTransactions = {}
            BridgeState.retiredChoiceDecisionIds = {}
            BridgeState.lastDecision = nil
            BridgeState.pendingDecision = nil
            function BridgeClearHighlights() end
            function BridgeHideMainPriorityControls() end
            local staleProbe = {
                decisionId='forge-tui-5',
                sessionId='session',
                kind='main_priority',
                seatId='forge-player-1',
                eventCursor=44,
                forgeSequence=8,
                phaseName='Draw step',
                actions={{actionId='pass-5', type='pass_priority'}}
            }
            directIgnore = BridgeShouldIgnoreStaleDecision(staleProbe)
            BridgeRecordStaleDecisionConvergence(staleProbe, 44, 48)
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        Assert.True(state.Get("lastDecision").IsNil());
        Assert.True(state.Get("pendingDecision").IsNil());
        Assert.True(lua.Globals.Get("directIgnore").Boolean);
        Assert.True(state.Get("staleDecisionRetryCount").Number >= 1,
            $"retryCount={state.Get("staleDecisionRetryCount").ToPrintString()} lastDecision={state.Get("lastDecision").ToPrintString()}");
    }

    [Fact]
    public void G6_ThoughtScourMutationCompletionInstallsCursorCurrentDecisionWithoutResync()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'session'
            BridgeState.lifecycleState = 'SESSION_ACTIVE'
            BridgeState.decisionPresentationGeneration = 2
            BridgeState.lastAppliedEventSequence = 107
            BridgeState.lastReceivedEventSequence = 107
            BridgeState.lastAppliedForgeSequence = 12
            BridgeState.currentPhase = 'Main phase, precombat'
            BridgeState.currentTurnSeatId = 'forge-player-1'
            BridgeState.prioritySeatId = 'forge-player-1'
            BridgeState.physicalPresentationGeneration = 177
            BridgeState.currentPhysicalPresentationGeneration = 177
            BridgeState.physicalTransactionGeneration = 2
            BridgeState.bootstrapping = false
            BridgeState.choiceTransactions = {}
            BridgeState.retiredChoiceDecisionIds = {}
            BridgeState.lastDecision = nil
            snapshotRequests = 0
            resyncStarts = 0
            renderCount = 0
            function BridgeScheduleSnapshotReconcile(reason, category) snapshotRequests = snapshotRequests + 1 end
            function BridgeResyncFromAuthoritativeSnapshot(origin) resyncStarts = resyncStarts + 1; return false end
            function BridgeRenderDecision(decision, force) renderCount = renderCount + 1; BridgeState.renderedDecisionPresentationKey = decision.decisionId end
            function BridgeDecisionPhysicalMappingsReady(decision) return true, nil end
            local decision = {
                decisionId='forge-tui-10', sessionId='session', kind='main_priority',
                seatId='forge-player-1', activeSeatId='forge-player-1', prioritySeatId='forge-player-1',
                eventCursor=107, forgeSequence=12, turnNumber=3, phaseName='Main phase, precombat',
                actions={{actionId='forge-tui-10-choice-0', type='pass_priority'}}
            }
            accepted = BridgeAcceptDecision(decision, 'thought-scour-followup', 'session', 2)
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        Assert.True(lua.Globals.Get("accepted").Boolean);
        Assert.Equal("forge-tui-10", state.Get("lastDecision").Table.Get("decisionId").String);
        Assert.Equal(1, lua.Globals.Get("renderCount").Number);
        Assert.Equal(0, lua.Globals.Get("snapshotRequests").Number);
        Assert.Equal(0, lua.Globals.Get("resyncStarts").Number);
        Assert.False(state.Get("bootstrapping").Boolean);
        Assert.Equal(177, state.Get("physicalPresentationGeneration").Number);
        Assert.Equal(2, state.Get("physicalTransactionGeneration").Number);
    }

    [Fact]
    public void G7_ManualResyncAndResumeCannotResetStaleDecisionBudget()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'session'
            BridgeState.lifecycleState = 'SESSION_ACTIVE'
            BridgeState.decisionPresentationGeneration = 2
            BridgeState.lastAppliedEventSequence = 107
            BridgeState.lastReceivedEventSequence = 107
            BridgeState.lastAppliedForgeSequence = 12
            BridgeState.currentPhase = 'Main phase, precombat'
            BridgeState.currentTurnSeatId = 'forge-player-1'
            BridgeState.prioritySeatId = 'forge-player-1'
            BridgeState.physicalPresentationGeneration = 177
            BridgeState.currentPhysicalPresentationGeneration = 177
            BridgeState.physicalTransactionGeneration = 2
            BridgeState.bootstrapping = false
            BridgeState.choiceTransactions = {}
            BridgeState.retiredChoiceDecisionIds = {}
            BridgeState.ui = {resyncInFlight=false, fastForwardActive=false, autoPassEmpty=false}
            stopEventCount = 0
            stopDecisionCount = 0
            pollsScheduled = 0
            function BridgeStopEventPolling(reason) stopEventCount = stopEventCount + 1; BridgeState.eventPolling = false end
            function BridgeStopDecisionPolling() stopDecisionCount = stopDecisionCount + 1; BridgeState.decisionPollGeneration = BridgeState.decisionPollGeneration + 1; BridgeState.decisionPollScheduled = false end
            function BridgeScheduleDecisionPoll(delay, generation, attempt, allowCurrentDecision) pollsScheduled = pollsScheduled + 1 end
            function BridgeRenderDecision(decision, force) rendered = true end
            function BridgeDecisionPhysicalMappingsReady(decision) return true, nil end
            function BridgeStartEventPolling(sessionId, skipExisting) eventStarted = true end
            function BridgeResumeChoiceProtocol(reason) end
            function BridgeSetSetupBusy(value, detail) BridgeState.setupBusy = value end
            local stale = {
                decisionId='forge-tui-9', sessionId='session', kind='main_priority',
                seatId='forge-player-1', activeSeatId='forge-player-1', prioritySeatId='forge-player-1',
                eventCursor=103, forgeSequence=11, turnNumber=3, phaseName='Main phase, precombat',
                actions={{actionId='forge-tui-9-choice-0', type='pass_priority'}}
            }
            for i = 1, BRIDGE_STALE_DECISION_CONVERGENCE_ATTEMPTS + 1 do
                BridgeRecordStaleDecisionConvergence(stale, 103, 107)
            end
            keyAfterFailure = BridgeState.staleDecisionRetryKey
            retriesAfterFailure = BridgeState.staleDecisionRetryCount
            terminalAfterFailure = BridgeState.terminalRecoveryError ~= nil
            resyncBlocked = BridgeResyncFromAuthoritativeSnapshot('hud')
            BridgeDoPressResume(nil, false)
            keyAfterResume = BridgeState.staleDecisionRetryKey
            retriesAfterResume = BridgeState.staleDecisionRetryCount
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        Assert.True(lua.Globals.Get("terminalAfterFailure").Boolean);
        Assert.True(lua.Globals.Get("resyncBlocked").IsNil() || !lua.Globals.Get("resyncBlocked").Boolean);
        Assert.Equal(lua.Globals.Get("keyAfterFailure").String, lua.Globals.Get("keyAfterResume").String);
        Assert.Equal(lua.Globals.Get("retriesAfterFailure").Number, lua.Globals.Get("retriesAfterResume").Number);
        Assert.False(state.Get("resyncInFlight").Boolean);
        Assert.False(state.Get("ui").Table.Get("resyncInFlight").Boolean);
        Assert.Equal("decision_provenance_lag", state.Get("terminalRecoveryError").Table.Get("kind").String);
        Assert.Equal(177, state.Get("physicalPresentationGeneration").Number);
        Assert.Equal(2, state.Get("physicalTransactionGeneration").Number);
    }

    [Fact]
    public void G2C_NullResultIsNotPresentedAsDrawDuringTerminalRecovery()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'session'
            BridgeState.terminalRecoveryError = {kind='decision_provenance_lag', detail='stale decision'}
            BridgeState.gameEnded = {winnerSeatIds={}, loserSeatIds={}, reason=nil}
            presented = BridgeDiagnosticPresentedResult()
            authoritative = BridgeCurrentAuthoritativeResult()
        ");

        Assert.True(lua.Globals.Get("authoritative").IsNil());
        var presented = lua.Globals.Get("presented").Table;
        Assert.False(presented.Get("presented").Boolean);
        Assert.True(presented.Get("terminalRecoveryError").Boolean);
    }

    [Fact]
    public void G2D_ExplicitAuthoritativeDrawIncludesSourceEventMetadata()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'session'
            function BridgeScheduleSnapshotReconcile(reason) end
            function BridgeSetStatus(headline, detail) end
            function BridgeStopDecisionPolling() end
            function BridgeStopEventPolling(reason) end
            function BridgeClearHighlights() end
            function BridgeRollbackPendingIntent() end
            function BridgeResetSelectionState() end
            function BridgeHideMainPriorityControls() end
            function BridgeCancelFastForward(reason) end
            applied = BridgeApplyAuthoritativeEvent({
                kind='game_ended',
                eventId='forge-event-session-200',
                sequence=200,
                winnerSeatIds={},
                loserSeatIds={'forge-player-1','forge-player-2'},
                gameEndReason='draw'
            })
            presented = BridgeDiagnosticPresentedResult()
            authoritative = BridgeCurrentAuthoritativeResult()
        ");

        Assert.True(lua.Globals.Get("applied").Boolean);
        var authoritative = lua.Globals.Get("authoritative").Table;
        Assert.Equal("draw", authoritative.Get("outcome").String);
        Assert.Equal("forge-event-session-200", authoritative.Get("sourceEventId").String);
        Assert.Equal(200, authoritative.Get("sourceEventCursor").Number);
        var presented = lua.Globals.Get("presented").Table;
        Assert.True(presented.Get("presented").Boolean);
    }

    [Fact]
    public void G2E_NewSessionClearsStalePriorSessionResultState()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'new-session'
            BridgeState.gameEnded = {
                authoritative=true,
                sourceEventId='forge-event-old-9',
                sourceEventCursor=9,
                sourceSessionId='old-session',
                outcome='draw',
                reason='draw',
                presentationGeneration=1,
                winnerSeatIds={},
                loserSeatIds={}
            }
            BridgeState.resultSourceEventId = 'forge-event-old-9'
            BridgeState.resultEventCursor = 9
            BridgeState.resultSessionId = 'old-session'
            BridgeState.resultOutcome = 'draw'
            BridgeState.resultReason = 'draw'
            BridgeState.resultPresentationGeneration = 1
            presented = BridgeDiagnosticPresentedResult()
            authoritative = BridgeCurrentAuthoritativeResult()
        ");

        Assert.True(lua.Globals.Get("authoritative").IsNil());
        Assert.False(lua.Globals.Get("presented").Table.Get("presented").Boolean);
    }

    [Fact]
    public void LifecycleGuardBlocksStartMatchOutsideReadyOrFailedStates()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.lifecycleState = 'SESSION_ACTIVE'
            blockedMessage = nil
            function BridgeShowError(message)
                blockedMessage = message
            end
            allowed = BridgeGuardLifecycleCommand('START_MATCH')
        ");

        Assert.False(lua.Globals.Get("allowed").Boolean);
        Assert.Contains("START MATCH unavailable", lua.Globals.Get("blockedMessage").String);
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
