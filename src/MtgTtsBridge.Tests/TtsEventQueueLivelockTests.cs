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
        ExecuteProbe(lua, "SuccessfulEventCommitsOnceWhenPollingGenerationChangesDuringApply.probe.lua", @"
            queueProbe = { checks = {}, commits = {} }
            local _rawIsCurrent = BridgeEventMutationIsCurrent
            BridgeEventMutationIsCurrent = function(tx)
                local isCurrent = _rawIsCurrent(tx)
                local seq = {}
                for i, queued in ipairs(BridgeState.eventQueue or {}) do seq[i] = queued.sequence end
                table.insert(queueProbe.checks, {
                    token = tx and tx.token or nil,
                    state = tx and tx.state or nil,
                    isCurrent = isCurrent,
                    txIsDrain = (BridgeState.eventDrainTransaction == tx),
                    txSessionId = tx and tx.sessionId or nil,
                    stateSessionId = BridgeState.eventSessionId,
                    txSessionGeneration = tx and tx.eventSessionGeneration or nil,
                    stateSessionGeneration = BridgeState.eventSessionGeneration,
                    txPhysicalGeneration = tx and tx.physicalTransactionGeneration or nil,
                    statePhysicalGeneration = BridgeState.physicalTransactionGeneration,
                    queueIdentityMatch = (BridgeState.eventQueue == (tx and tx.queue or nil)),
                    queueSeq = seq
                })
                return isCurrent
            end
            local _rawCommit = BridgeCommitEventMutationTransaction
            BridgeCommitEventMutationTransaction = function(tx)
                local seq = {}
                for i, queued in ipairs(BridgeState.eventQueue or {}) do seq[i] = queued.sequence end
                local currentBefore = BridgeEventMutationIsCurrent(tx)
                local queueHead = tx and tx.queue and tx.queue[1] or nil
                local firstEvent = tx and tx.events and tx.events[1] or nil
                local ok, resultOrErr = pcall(function() return _rawCommit(tx) end)
                table.insert(queueProbe.commits, {
                    token = tx and tx.token or nil,
                    stateBefore = tx and tx.state or nil,
                    txLastEventSequence = tx and tx.lastEventSequence or nil,
                    queueHeadBeforeSequence = queueHead and queueHead.sequence or nil,
                    firstEventSequence = firstEvent and firstEvent.sequence or nil,
                    queueHeadMatchesFirstEventByIdentity = (queueHead == firstEvent),
                    currentBefore = currentBefore,
                    ok = ok,
                    commitReturned = ok and resultOrErr or false,
                    commitError = ok and nil or tostring(resultOrErr),
                    stateAfter = tx and tx.state or nil,
                    txIsDrainAfter = (BridgeState.eventDrainTransaction == tx),
                    stateSessionId = BridgeState.eventSessionId,
                    stateSessionGeneration = BridgeState.eventSessionGeneration,
                    statePhysicalGeneration = BridgeState.physicalTransactionGeneration,
                    queueIdentityMatchAfter = (BridgeState.eventQueue == (tx and tx.queue or nil)),
                    queueSeqBefore = seq,
                    queueIdleProbe = BridgePhysicalLibraryQueuesIdle(),
                    lastApplied = BridgeState.lastAppliedEventSequence,
                    desyncReason = desyncReason
                })
                return ok and resultOrErr or false
            end
            BridgeState.eventQueue = {}
            table.insert(BridgeState.eventQueue, {sequence=9, kind='card_moved', seatId='forge-player-2', destinationZone='library', cardInstanceId='forge-object:9'})
            table.insert(BridgeState.eventQueue, {sequence=8, kind='card_moved', seatId='forge-player-2', sourceZone=nil, destinationZone='library', containsHiddenIdentity=true, cardInstanceId='forge-object:8'})
            preQueueLength = #(BridgeState.eventQueue or {})
            preHeadSequence = BridgeState.eventQueue[1] and BridgeState.eventQueue[1].sequence or nil
            preExpectedSequence = (tonumber(BridgeState.lastAppliedEventSequence or 0) or 0) + 1
            preBlockReason = BridgeEventDrainBlockReason()
            applyCount = 0
            function BridgeApplyAuthoritativeEvent(event)
                applyCount = applyCount + 1
                if event.sequence == 8 then BridgeState.eventPollGeneration = BridgeState.eventPollGeneration + 1 end
                return true, 0
            end
            BridgeProcessEventQueue()
            postQueueLength = #(BridgeState.eventQueue or {})
            postDrainState = BridgeState.eventDrainTransaction and BridgeState.eventDrainTransaction.state or 'nil'
            postDesyncReason = desyncReason
            local commitCount = #(queueProbe.commits or {})
            local checkCount = #(queueProbe.checks or {})
            firstCommit = queueProbe.commits[commitCount] or queueProbe.commits[1] or queueProbe.commits[0]
            firstCheck = queueProbe.checks[checkCount] or queueProbe.checks[1] or queueProbe.checks[0]
        ");

        var probe = lua.Globals.Get("queueProbe").Table;
        Assert.True(probe.Get("commits").Table.Length >= 1,
            $"preQueueLen={lua.Globals.Get("preQueueLength").ToPrintString()} preHead={lua.Globals.Get("preHeadSequence").ToPrintString()} preExpected={lua.Globals.Get("preExpectedSequence").ToPrintString()} preBlock={lua.Globals.Get("preBlockReason").ToPrintString()} postQueueLen={lua.Globals.Get("postQueueLength").ToPrintString()} postDrain={lua.Globals.Get("postDrainState").ToPrintString()} desync={lua.Globals.Get("postDesyncReason").ToPrintString()}");
        Assert.True(probe.Get("checks").Table.Length >= 1);
        var firstCommit = lua.Globals.Get("firstCommit").Table;
        var firstCheck = lua.Globals.Get("firstCheck").Table;
        Assert.NotNull(firstCommit);
        Assert.NotNull(firstCheck);
        Assert.Equal(1, lua.Globals.Get("applyCount").Number);
        Assert.True(firstCommit.Get("txLastEventSequence").Number == 8,
            $"txLastEventSequence={firstCommit.Get("txLastEventSequence").ToPrintString()} token={firstCommit.Get("token").ToPrintString()} stateBefore={firstCommit.Get("stateBefore").ToPrintString()} stateAfter={firstCommit.Get("stateAfter").ToPrintString()} currentBefore={firstCommit.Get("currentBefore").ToPrintString()} commitReturned={firstCommit.Get("commitReturned").ToPrintString()}");
        Assert.True(firstCommit.Get("lastApplied").Number == 8,
            $"commitLastApplied={firstCommit.Get("lastApplied").ToPrintString()} token={firstCommit.Get("token").ToPrintString()} stateAfter={firstCommit.Get("stateAfter").ToPrintString()} commitReturned={firstCommit.Get("commitReturned").ToPrintString()} queueIdentityMatchAfter={firstCommit.Get("queueIdentityMatchAfter").ToPrintString()} headSeq={firstCommit.Get("queueHeadBeforeSequence").ToPrintString()} firstEventSeq={firstCommit.Get("firstEventSequence").ToPrintString()} headEqEvent={firstCommit.Get("queueHeadMatchesFirstEventByIdentity").ToPrintString()} desync={firstCommit.Get("desyncReason").ToPrintString()}");
        var finalApplied = lua.Globals.Get("BridgeState").Table.Get("lastAppliedEventSequence").Number;
        Assert.True(finalApplied == 8,
            $"finalApplied={finalApplied} commitReturned={firstCommit.Get("commitReturned").ToPrintString()} commitState={firstCommit.Get("stateAfter").ToPrintString()} commitLastApplied={firstCommit.Get("lastApplied").ToPrintString()} postQueueLen={lua.Globals.Get("postQueueLength").ToPrintString()} postDrain={lua.Globals.Get("postDrainState").ToPrintString()} desync={lua.Globals.Get("postDesyncReason").ToPrintString()}");
        Assert.True(firstCommit.Get("currentBefore").Boolean);
        Assert.True(firstCommit.Get("commitReturned").Boolean);
        Assert.Equal("COMMITTED", firstCommit.Get("stateAfter").String);
    }

    [Fact]
    public void SessionReplacementAbandonsTheOldQueueWithoutCommittingItsEvent()
    {
        var lua = NewQueueProbe();
        ExecuteProbe(lua, "SessionReplacementAbandonsTheOldQueueWithoutCommittingItsEvent.probe.lua", @"
            queueProbe = { checks = {}, commits = {} }
            local _rawIsCurrent = BridgeEventMutationIsCurrent
            BridgeEventMutationIsCurrent = function(tx)
                local isCurrent = _rawIsCurrent(tx)
                local seq = {}
                for i, queued in ipairs(BridgeState.eventQueue or {}) do seq[i] = queued.sequence end
                table.insert(queueProbe.checks, {
                    token = tx and tx.token or nil,
                    state = tx and tx.state or nil,
                    isCurrent = isCurrent,
                    txIsDrain = (BridgeState.eventDrainTransaction == tx),
                    txSessionId = tx and tx.sessionId or nil,
                    stateSessionId = BridgeState.eventSessionId,
                    txSessionGeneration = tx and tx.eventSessionGeneration or nil,
                    stateSessionGeneration = BridgeState.eventSessionGeneration,
                    txPhysicalGeneration = tx and tx.physicalTransactionGeneration or nil,
                    statePhysicalGeneration = BridgeState.physicalTransactionGeneration,
                    queueIdentityMatch = (BridgeState.eventQueue == (tx and tx.queue or nil)),
                    queueSeq = seq,
                    desyncReason = desyncReason
                })
                return isCurrent
            end
            local _rawCommit = BridgeCommitEventMutationTransaction
            BridgeCommitEventMutationTransaction = function(tx)
                local ok, resultOrErr = pcall(function() return _rawCommit(tx) end)
                table.insert(queueProbe.commits, {
                    token = tx and tx.token or nil,
                    ok = ok,
                    txLastEventSequence = tx and tx.lastEventSequence or nil,
                    queueHeadBeforeSequence = (tx and tx.queue and tx.queue[1] and tx.queue[1].sequence) or nil,
                    firstEventSequence = (tx and tx.events and tx.events[1] and tx.events[1].sequence) or nil,
                    queueHeadMatchesFirstEventByIdentity = ((tx and tx.queue and tx.events and tx.queue[1] == tx.events[1]) or false),
                    commitReturned = ok and resultOrErr or false,
                    commitError = ok and nil or tostring(resultOrErr),
                    stateAfter = tx and tx.state or nil,
                    txIsDrainAfter = (BridgeState.eventDrainTransaction == tx),
                    stateSessionId = BridgeState.eventSessionId,
                    stateSessionGeneration = BridgeState.eventSessionGeneration,
                    statePhysicalGeneration = BridgeState.physicalTransactionGeneration,
                    queueIdentityMatchAfter = (BridgeState.eventQueue == (tx and tx.queue or nil)),
                    lastApplied = BridgeState.lastAppliedEventSequence,
                    desyncReason = desyncReason
                })
                return ok and resultOrErr or false
            end
            BridgeState.eventQueue = {}
            table.insert(BridgeState.eventQueue, {sequence=9, kind='phase_changed', seatId='forge-player-1'})
            table.insert(BridgeState.eventQueue, {sequence=8, kind='card_moved', seatId='forge-player-2', destinationZone='library', cardInstanceId='forge-object:8'})
            preQueueLength = #(BridgeState.eventQueue or {})
            preHeadSequence = BridgeState.eventQueue[1] and BridgeState.eventQueue[1].sequence or nil
            preExpectedSequence = (tonumber(BridgeState.lastAppliedEventSequence or 0) or 0) + 1
            preBlockReason = BridgeEventDrainBlockReason()
            applyCount = 0
            startedSequence = nil
            function BridgeApplyAuthoritativeEvent(event)
                applyCount = applyCount + 1
                startedSequence = event.sequence
                BridgeState.eventSessionId = 'replacement'
                BridgeState.eventSessionGeneration = (BridgeState.eventSessionGeneration or 0) + 1
                BridgeState.eventQueue = {}
                table.insert(BridgeState.eventQueue, {sequence=2, kind='phase_changed', seatId='forge-player-1'})
                table.insert(BridgeState.eventQueue, {sequence=1, kind='phase_changed', seatId='forge-player-1'})
                return true, 0
            end
            BridgeProcessEventQueue()
            postQueueLength = #(BridgeState.eventQueue or {})
            postDrainState = BridgeState.eventDrainTransaction and BridgeState.eventDrainTransaction.state or 'nil'
            postDesyncReason = desyncReason
            local commitCount = #(queueProbe.commits or {})
            local checkCount = #(queueProbe.checks or {})
            firstCommit = queueProbe.commits[commitCount] or queueProbe.commits[1] or queueProbe.commits[0]
            firstCheck = queueProbe.checks[checkCount] or queueProbe.checks[1] or queueProbe.checks[0]
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        var probe = lua.Globals.Get("queueProbe").Table;
        Assert.Equal(1, lua.Globals.Get("applyCount").Number);
        Assert.Equal(8, lua.Globals.Get("startedSequence").Number);
        Assert.Equal(7, state.Get("lastAppliedEventSequence").Number);
        Assert.Equal("replacement", state.Get("eventSessionId").String);
        Assert.Equal(1, state.Get("eventQueue").Table.Get(1).Table.Get("sequence").Number);
        Assert.Equal(0, probe.Get("commits").Table.Length);
        Assert.True(probe.Get("checks").Table.Length >= 1,
            $"applyCount={lua.Globals.Get("applyCount").ToPrintString()} preQueueLen={lua.Globals.Get("preQueueLength").ToPrintString()} preHead={lua.Globals.Get("preHeadSequence").ToPrintString()} preExpected={lua.Globals.Get("preExpectedSequence").ToPrintString()} preBlock={lua.Globals.Get("preBlockReason").ToPrintString()} postQueueLen={lua.Globals.Get("postQueueLength").ToPrintString()} postDrain={lua.Globals.Get("postDrainState").ToPrintString()} desync={lua.Globals.Get("postDesyncReason").ToPrintString()}");
        var firstCheck = lua.Globals.Get("firstCheck").Table;
        Assert.NotNull(firstCheck);
        Assert.False(firstCheck.Get("isCurrent").Boolean);
        Assert.Equal("replacement", firstCheck.Get("stateSessionId").String);
    }

    [Fact]
    public void SuccessfulEventCommitsWhenPollingStopsWithinTheSameSession()
    {
        var lua = NewQueueProbe();
        ExecuteProbe(lua, "SuccessfulEventCommitsWhenPollingStopsWithinTheSameSession.probe.lua", @"
            queueProbe = { checks = {}, commits = {} }
            local _rawIsCurrent = BridgeEventMutationIsCurrent
            BridgeEventMutationIsCurrent = function(tx)
                local isCurrent = _rawIsCurrent(tx)
                local seq = {}
                for i, queued in ipairs(BridgeState.eventQueue or {}) do seq[i] = queued.sequence end
                table.insert(queueProbe.checks, {
                    token = tx and tx.token or nil,
                    state = tx and tx.state or nil,
                    isCurrent = isCurrent,
                    txIsDrain = (BridgeState.eventDrainTransaction == tx),
                    txSessionId = tx and tx.sessionId or nil,
                    stateSessionId = BridgeState.eventSessionId,
                    txSessionGeneration = tx and tx.eventSessionGeneration or nil,
                    stateSessionGeneration = BridgeState.eventSessionGeneration,
                    txPhysicalGeneration = tx and tx.physicalTransactionGeneration or nil,
                    statePhysicalGeneration = BridgeState.physicalTransactionGeneration,
                    queueIdentityMatch = (BridgeState.eventQueue == (tx and tx.queue or nil)),
                    queueSeq = seq,
                    queueIdleProbe = BridgePhysicalLibraryQueuesIdle()
                })
                return isCurrent
            end
            local _rawCommit = BridgeCommitEventMutationTransaction
            BridgeCommitEventMutationTransaction = function(tx)
                local ok, resultOrErr = pcall(function() return _rawCommit(tx) end)
                table.insert(queueProbe.commits, {
                    token = tx and tx.token or nil,
                    ok = ok,
                    txLastEventSequence = tx and tx.lastEventSequence or nil,
                    commitReturned = ok and resultOrErr or false,
                    commitError = ok and nil or tostring(resultOrErr),
                    stateAfter = tx and tx.state or nil,
                    txIsDrainAfter = (BridgeState.eventDrainTransaction == tx),
                    stateSessionId = BridgeState.eventSessionId,
                    stateSessionGeneration = BridgeState.eventSessionGeneration,
                    statePhysicalGeneration = BridgeState.physicalTransactionGeneration,
                    queueIdentityMatchAfter = (BridgeState.eventQueue == (tx and tx.queue or nil)),
                    lastApplied = BridgeState.lastAppliedEventSequence,
                    desyncReason = desyncReason
                })
                return ok and resultOrErr or false
            end
            BridgeState.eventQueue = {}
            table.insert(BridgeState.eventQueue, {sequence=9, kind='phase_changed', seatId='forge-player-1'})
            table.insert(BridgeState.eventQueue, {sequence=8, kind='card_moved', seatId='forge-player-2', destinationZone='library', cardInstanceId='forge-object:8'})
            preQueueLength = #(BridgeState.eventQueue or {})
            preHeadSequence = BridgeState.eventQueue[1] and BridgeState.eventQueue[1].sequence or nil
            preExpectedSequence = (tonumber(BridgeState.lastAppliedEventSequence or 0) or 0) + 1
            preBlockReason = BridgeEventDrainBlockReason()
            applyCount = 0
            function BridgeApplyAuthoritativeEvent(event)
                applyCount = applyCount + 1
                BridgeState.eventPolling = false
                return true, 0
            end
            BridgeProcessEventQueue()
            postQueueLength = #(BridgeState.eventQueue or {})
            postDrainState = BridgeState.eventDrainTransaction and BridgeState.eventDrainTransaction.state or 'nil'
            postDesyncReason = desyncReason
            local commitCount = #(queueProbe.commits or {})
            local checkCount = #(queueProbe.checks or {})
            firstCommit = queueProbe.commits[commitCount] or queueProbe.commits[1] or queueProbe.commits[0]
            firstCheck = queueProbe.checks[checkCount] or queueProbe.checks[1] or queueProbe.checks[0]
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        var probe = lua.Globals.Get("queueProbe").Table;
        var firstCommit = lua.Globals.Get("firstCommit").Table;
        Assert.NotNull(firstCommit);
        Assert.True(lua.Globals.Get("applyCount").Number == 1,
            $"preQueueLen={lua.Globals.Get("preQueueLength").ToPrintString()} preHead={lua.Globals.Get("preHeadSequence").ToPrintString()} preExpected={lua.Globals.Get("preExpectedSequence").ToPrintString()} preBlock={lua.Globals.Get("preBlockReason").ToPrintString()} postQueueLen={lua.Globals.Get("postQueueLength").ToPrintString()} postDrain={lua.Globals.Get("postDrainState").ToPrintString()} desync={lua.Globals.Get("postDesyncReason").ToPrintString()}");
        Assert.True(firstCommit.Get("txLastEventSequence").Number == 8,
            $"txLastEventSequence={firstCommit.Get("txLastEventSequence").ToPrintString()} token={firstCommit.Get("token").ToPrintString()} stateAfter={firstCommit.Get("stateAfter").ToPrintString()} commitReturned={firstCommit.Get("commitReturned").ToPrintString()}");
        Assert.True(firstCommit.Get("lastApplied").Number == 8,
            $"commitLastApplied={firstCommit.Get("lastApplied").ToPrintString()} token={firstCommit.Get("token").ToPrintString()} stateAfter={firstCommit.Get("stateAfter").ToPrintString()} commitReturned={firstCommit.Get("commitReturned").ToPrintString()} queueIdentityMatchAfter={firstCommit.Get("queueIdentityMatchAfter").ToPrintString()} headSeq={firstCommit.Get("queueHeadBeforeSequence").ToPrintString()} firstEventSeq={firstCommit.Get("firstEventSequence").ToPrintString()} headEqEvent={firstCommit.Get("queueHeadMatchesFirstEventByIdentity").ToPrintString()} desync={firstCommit.Get("desyncReason").ToPrintString()}");
        var finalApplied = state.Get("lastAppliedEventSequence").Number;
        Assert.True(finalApplied == 8,
            $"finalApplied={finalApplied} commitReturned={firstCommit.Get("commitReturned").ToPrintString()} commitState={firstCommit.Get("stateAfter").ToPrintString()} commitLastApplied={firstCommit.Get("lastApplied").ToPrintString()} postQueueLen={lua.Globals.Get("postQueueLength").ToPrintString()} postDrain={lua.Globals.Get("postDrainState").ToPrintString()} desync={lua.Globals.Get("postDesyncReason").ToPrintString()}");
        Assert.True(firstCommit.Get("commitReturned").Boolean);
        Assert.Equal("COMMITTED", firstCommit.Get("stateAfter").String);
    }

    [Fact]
    public void QueueOrderContract_MoonSharpTableInsertBuildsAscendingForThisProbeLayout()
    {
        var lua = NewQueueProbe();
        ExecuteProbe(lua, "QueueOrderContract_MoonSharpTableInsertBuildsAscendingForThisProbeLayout.probe.lua", @"
            BridgeState.eventQueue = {}
            table.insert(BridgeState.eventQueue, {sequence=9, kind='phase_changed', seatId='forge-player-1'})
            table.insert(BridgeState.eventQueue, {sequence=8, kind='card_moved', seatId='forge-player-2'})
            legacyHeadSequence = BridgeState.eventQueue[1] and BridgeState.eventQueue[1].sequence or nil
            legacyApplyCount = 0
            function BridgeApplyAuthoritativeEvent(event)
                legacyApplyCount = legacyApplyCount + 1
                return true, 0
            end
            desyncReason = nil
            BridgeProcessEventQueueLegacy()
            legacyReason = desyncReason

            BridgeState.desyncLatched = false
            BridgeState.lastAppliedEventSequence = 7
            BridgeState.eventDrainTransaction = nil
            BridgeState.animationRunning = false
            BridgeState.eventQueue = {}
            table.insert(BridgeState.eventQueue, {sequence=9, kind='phase_changed', seatId='forge-player-1'})
            table.insert(BridgeState.eventQueue, {sequence=8, kind='card_moved', seatId='forge-player-2'})
            currentHeadSequence = BridgeState.eventQueue[1] and BridgeState.eventQueue[1].sequence or nil
            currentApplyCount = 0
            BridgeApplyAuthoritativeEvent = function(event)
                currentApplyCount = currentApplyCount + 1
                return true, 0
            end
            desyncReason = nil
            BridgeProcessEventQueue()
            currentReason = desyncReason
        ");

        Assert.Equal(8, lua.Globals.Get("legacyHeadSequence").Number);
        Assert.Equal(8, lua.Globals.Get("currentHeadSequence").Number);
        Assert.Equal(1, lua.Globals.Get("legacyApplyCount").Number);
        Assert.Equal(1, lua.Globals.Get("currentApplyCount").Number);
    }

    [Fact]
    public void PhysicalReadinessProbeFailureDoesNotCommitMutation()
    {
        var lua = NewQueueProbe();
        ExecuteProbe(lua, "PhysicalReadinessProbeFailureDoesNotCommitMutation.probe.lua", @"
            queueProbe = { commits = {}, checks = {} }
            local _rawIsCurrent = BridgeEventMutationIsCurrent
            BridgeEventMutationIsCurrent = function(tx)
                local isCurrent = _rawIsCurrent(tx)
                table.insert(queueProbe.checks, {
                    token = tx and tx.token or nil,
                    isCurrent = isCurrent,
                    state = tx and tx.state or nil,
                    txIsDrain = (BridgeState.eventDrainTransaction == tx),
                    txSessionId = tx and tx.sessionId or nil,
                    stateSessionId = BridgeState.eventSessionId,
                    txSessionGeneration = tx and tx.eventSessionGeneration or nil,
                    stateSessionGeneration = BridgeState.eventSessionGeneration,
                    txPhysicalGeneration = tx and tx.physicalTransactionGeneration or nil,
                    statePhysicalGeneration = BridgeState.physicalTransactionGeneration,
                    queueIdentityMatch = (BridgeState.eventQueue == (tx and tx.queue or nil))
                })
                return isCurrent
            end
            local _rawCommit = BridgeCommitEventMutationTransaction
            BridgeCommitEventMutationTransaction = function(tx)
                local ok, resultOrErr = pcall(function() return _rawCommit(tx) end)
                table.insert(queueProbe.commits, {
                    ok = ok,
                    commitReturned = ok and resultOrErr or false,
                    commitError = ok and nil or tostring(resultOrErr),
                    stateAfter = tx and tx.state or nil,
                    txIsDrainAfter = (BridgeState.eventDrainTransaction == tx),
                    lastApplied = BridgeState.lastAppliedEventSequence,
                    desyncReason = desyncReason
                })
                return ok and resultOrErr or false
            end
            BridgeState.eventQueue = {}
            table.insert(BridgeState.eventQueue, {sequence=9, kind='phase_changed', seatId='forge-player-1'})
            table.insert(BridgeState.eventQueue, {sequence=8, kind='card_moved', seatId='forge-player-2', destinationZone='library', cardInstanceId='forge-object:8'})
            preQueueLength = #(BridgeState.eventQueue or {})
            preHeadSequence = BridgeState.eventQueue[1] and BridgeState.eventQueue[1].sequence or nil
            preExpectedSequence = (tonumber(BridgeState.lastAppliedEventSequence or 0) or 0) + 1
            preBlockReason = BridgeEventDrainBlockReason()
            applyCount = 0
            function BridgeApplyAuthoritativeEvent(event)
                applyCount = applyCount + 1
                return true, 0
            end
            BridgePhysicalLibraryQueuesIdle = function() error('readiness probe exploded') end
            BridgeProcessEventQueue()
            postQueueLength = #(BridgeState.eventQueue or {})
            postDrainState = BridgeState.eventDrainTransaction and BridgeState.eventDrainTransaction.state or 'nil'
            postDesyncReason = desyncReason
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        var probe = lua.Globals.Get("queueProbe").Table;
        Assert.True(lua.Globals.Get("applyCount").Number == 1,
            $"preQueueLen={lua.Globals.Get("preQueueLength").ToPrintString()} preHead={lua.Globals.Get("preHeadSequence").ToPrintString()} preExpected={lua.Globals.Get("preExpectedSequence").ToPrintString()} preBlock={lua.Globals.Get("preBlockReason").ToPrintString()} postQueueLen={lua.Globals.Get("postQueueLength").ToPrintString()} postDrain={lua.Globals.Get("postDrainState").ToPrintString()} desync={lua.Globals.Get("postDesyncReason").ToPrintString()}");
        Assert.Equal(7, state.Get("lastAppliedEventSequence").Number);
        Assert.Equal(2, state.Get("eventQueue").Table.Length);
        Assert.True(probe.Get("commits").Table.Length == 0);
        Assert.Contains("physical-readiness-probe-failed", lua.Globals.Get("desyncReason").String);
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
            BridgeState.eventDrainTransaction = {
                token = 'probe-tx',
                state = 'PREPARING',
                sessionId = BridgeState.eventSessionId,
                eventSessionGeneration = BridgeState.eventSessionGeneration,
                physicalTransactionGeneration = BridgeState.physicalTransactionGeneration,
                queue = BridgeState.eventQueue
            }
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
    public void StaleAnimationFenceWithoutTransactionClearsAndUnblocksQueueDrain()
    {
        var lua = NewQueueProbe();
        ExecuteProbe(lua, "StaleAnimationFenceWithoutTransactionSelfHealsAndCommitsTheHeadEvent.probe.lua", @"
            BridgeState.eventQueue = {}
            table.insert(BridgeState.eventQueue, {sequence=8, kind='card_moved', seatId='forge-player-2', sourceZone='hand', destinationZone='library', containsHiddenIdentity=true, cardInstanceId='forge-object:8'})
            BridgeState.animationRunning = true
            BridgeState.eventDrainTransaction = nil
            blockReason = BridgeEventDrainBlockReason()
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        Assert.Equal("none", lua.Globals.Get("blockReason").String);
        Assert.False(state.Get("animationRunning").Boolean);
        Assert.Equal(1, state.Get("eventQueue").Table.Length);
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
    public void StaleLibraryExtractionCallbackCleansUpQueueOwnershipWhenTheGenerationChanges()
    {
        var lua = NewQueueProbe();
        
        // Capture logs
        lua.DoString(@"
            _captured_logs = {}
            function log(message)
                table.insert(_captured_logs, message)
            end
        ");
        
        lua.DoString(@"
            BridgeState.eventSessionId = 'session'
            BridgeState.physicalTransactionGeneration = 7
            BridgeState.libraryExtractionQueueBySeatId['forge-player-1'] = {}
            BridgeState.libraryExtractionActiveBySeatId['forge-player-1'] = nil
            BridgeState.libraryExtractionTransactionBySeatId['forge-player-1'] = nil
        ");
        
        // Create the queue item in Lua with a callback function
        lua.DoString(@"
            local queue = BridgeState.libraryExtractionQueueBySeatId['forge-player-1']
            queue.run = function(complete)
                local tx = BridgeState.libraryExtractionTransactionBySeatId['forge-player-1']
                BridgeState.physicalTransactionGeneration = 8
                if tx ~= nil then
                    tx.generation = 8
                end
                complete('stale-callback')
            end
            queue.cardInstanceId = 'forge-object:17'
            queue.expectedCardName = 'Island'
            
            -- Manually add to queue using key=1 instead of table.insert
            BridgeState.libraryExtractionQueueBySeatId['forge-player-1'][1] = {
                cardInstanceId = 'forge-object:17',
                expectedCardName = 'Island',
                run = function(complete)
                    local tx = BridgeState.libraryExtractionTransactionBySeatId['forge-player-1']
                    BridgeState.physicalTransactionGeneration = 8
                    if tx ~= nil then
                        tx.generation = 8
                    end
                    complete('stale-callback')
                end
            }
            
            BridgeProcessLibraryExtractionQueue('forge-player-1')
        ");

        // Extract captured logs
        var capturedLogs = lua.Globals.Get("_captured_logs").Table;
        var logLines = new System.Collections.Generic.List<string>();
        if (capturedLogs != null)
        {
            foreach (var kvp in capturedLogs.Pairs)
            {
                if (kvp.Value.Type == DataType.String)
                {
                    logLines.Add(kvp.Value.String);
                }
            }
        }

        var state = lua.Globals.Get("BridgeState").Table;
        var queue = state.Get("libraryExtractionQueueBySeatId").Table.Get("forge-player-1");
        var active = state.Get("libraryExtractionActiveBySeatId").Table.Get("forge-player-1");
        Assert.NotNull(queue);
        
        // If queue is not empty, include logs in the error
        if (queue.Table.Length != 0)
        {
            var logText = string.Join("\n", logLines);
            Assert.Fail($"Queue should be empty. Queue length: {queue.Table.Length}. Captured {logLines.Count} logs.\n\nCAPTURED LOGS:\n{logText}");
        }
        
        Assert.True(active == null || active.IsNil());
    }

    [Fact]
    public void CurrentLibraryExtractionCompletionRemovesItsItemBeforeReleasingTheWorker()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.physicalTransactionGeneration = 7
            BridgeState.libraryExtractionQueueBySeatId['forge-player-1'] = {}
            BridgeState.libraryExtractionActiveBySeatId['forge-player-1'] = nil
            BridgeState.libraryExtractionTransactionBySeatId['forge-player-1'] = nil
            BridgeWakePhysicalReadinessDependency = function() end
            BridgeFindLibraryDeckForSeat = function() return nil end
            BridgeLogLibraryExtraction = function() end
            local item = {cardInstanceId='forge-object:18', expectedCardName='Island',
                run=function(complete) complete('success') end}
            BridgeState.libraryExtractionQueueBySeatId['forge-player-1'][1] = item
            BridgeProcessLibraryExtractionQueue('forge-player-1')
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        Assert.Equal(0, state.Get("libraryExtractionQueueBySeatId").Table
            .Get("forge-player-1").Table.Length);
        Assert.True(state.Get("libraryExtractionActiveBySeatId").Table
            .Get("forge-player-1").IsNil());
        Assert.True(state.Get("libraryExtractionTransactionBySeatId").Table
            .Get("forge-player-1").IsNil());
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
        ExecuteProbe(lua, "AutomaticResyncBehindPhysicalQueueUsesOneBoundedRetry.probe.lua", @"
            BridgeState.eventSessionId = 'session'
            BridgeState.libraryBatchBySeatId = BridgeState.libraryBatchBySeatId or {}
            BridgeState.libraryExtractionQueueBySeatId = BridgeState.libraryExtractionQueueBySeatId or {}
            BridgeState.libraryExtractionActiveBySeatId = BridgeState.libraryExtractionActiveBySeatId or {}
            BridgeState.graveyardExtractionActiveBySeatId = BridgeState.graveyardExtractionActiveBySeatId or {}
            BridgeState.mulliganBottomQueueBySeatId = BridgeState.mulliganBottomQueueBySeatId or {}
            BridgeState.mulliganBottomInsertionActiveBySeatId = BridgeState.mulliganBottomInsertionActiveBySeatId or {}
            BridgeState.libraryExtractionActiveBySeatId['forge-player-1'] = true
            BridgePhysicalLibraryQueuesIdle = function() return false end
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
    public void DecisionIsNotDeferredWhenItsCursorIsAlreadyObservedEvenIfOneEventIsStillUnapplied()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.lastAppliedEventSequence = 86
            BridgeState.lastReceivedEventSequence = 87
            BridgeState.eventQueue = {}
            defer, cursor, applied, reason = BridgeShouldDeferDecision({
                decisionId='forge-tui-87',
                kind='main_priority',
                seatId='forge-player-1',
                eventCursor=87,
                forgeSequence=14,
                actions={{actionId='land-87', type='play_land', isPresentationAuthorized=true}}
            })
        ");

        Assert.False(lua.Globals.Get("defer").Boolean);
        Assert.Equal(87, lua.Globals.Get("cursor").Number);
        Assert.Equal(86, lua.Globals.Get("applied").Number);
        Assert.True(lua.Globals.Get("reason").IsNil() || string.IsNullOrWhiteSpace(lua.Globals.Get("reason").String));
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
    public void G2F_CurrentSessionIgnoresPriorSessionTerminalRecovery()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'session-b'
            BridgeState.terminalRecoveryError = {
                sessionId='session-a',
                kind='decision_provenance_lag',
                detail='stale decision from old session'
            }
            currentRecovery = BridgeCurrentTerminalRecoveryError()
            presented = BridgeDiagnosticPresentedResult()
        ");

        Assert.True(lua.Globals.Get("currentRecovery").IsNil());
        Assert.False(lua.Globals.Get("presented").Table.Get("terminalRecoveryError").Boolean);
    }

    [Fact]
    public void D4628_SessionReplacementDoesNotWriteTerminalRecoveryForAnOldGenerationFault()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'session-b'
            BridgeState.eventSessionGeneration = 2
            BridgeState.eventPolling = true
            fault = {
                sessionId = 'session-a',
                sessionGeneration = 1,
                decisionId = 'forge-tui-old',
                key = 'stale-old-generation',
                eventCursor = 9,
                appliedEventCursor = 10,
                payloadHash = 'old'
            }
            BridgeStopOnDecisionProvenanceLag('old generation after replacement', fault)
            recovery = BridgeCurrentTerminalRecoveryError()
            polling = BridgeState.eventPolling
        ");

        Assert.True(lua.Globals.Get("recovery").IsNil());
        Assert.True(lua.Globals.Get("polling").Boolean);
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

    [Fact]
    public void ContainedGraveyardIdentitiesRemainExactWhenPrintedNamesDuplicate()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'session'
            BridgeRecordContainedCardIdentity('forge-object:1', 'grave-deck', 'contained-1', 'forge-player-1', 'graveyard', 'Plains')
            BridgeRecordContainedCardIdentity('forge-object:2', 'grave-deck', 'contained-2', 'forge-player-1', 'graveyard', 'Plains')
            first = BridgeState.physicalContainerByInstanceId['forge-object:1']
            second = BridgeState.physicalContainerByInstanceId['forge-object:2']
        ");

        var first = lua.Globals.Get("first").Table;
        var second = lua.Globals.Get("second").Table;
        Assert.Equal("grave-deck", first.Get("deckGuid").String);
        Assert.Equal("contained-1", first.Get("cardGuid").String);
        Assert.Equal("contained-2", second.Get("cardGuid").String);
        Assert.Equal("forge-object:1", lua.Globals.Get("BridgeState").Table
            .Get("physicalContainedInstanceIdByGuid").Table.Get("contained-1").String);
        Assert.Equal("forge-object:2", lua.Globals.Get("BridgeState").Table
            .Get("physicalContainedInstanceIdByGuid").Table.Get("contained-2").String);
    }

    [Fact]
    public void GraveyardDeckCollapseRebindsOnlyTheExactContainedIdentityToLooseCard()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'session'
            BridgeRecordContainedCardIdentity('forge-object:1', 'grave-deck', 'contained-1', 'forge-player-1', 'graveyard', 'Plains')
            BridgeRecordContainedCardIdentity('forge-object:2', 'grave-deck', 'contained-2', 'forge-player-1', 'graveyard', 'Plains')
            BridgeRecordLooseCardIdentity('forge-object:2', 'physical-2', 'forge-player-1', 'graveyard')
            retained = BridgeState.physicalContainerByInstanceId['forge-object:1']
            collapsed = BridgeState.physicalByInstanceId['forge-object:2']
            collapsedContainer = BridgeState.physicalContainerByInstanceId['forge-object:2']
        ");

        Assert.Equal("contained-1", lua.Globals.Get("retained").Table.Get("cardGuid").String);
        Assert.Equal("physical-2", lua.Globals.Get("collapsed").String);
        Assert.True(lua.Globals.Get("collapsedContainer").IsNil());
    }

    [Fact]
    public void FinalPhysicalRepresentationAcceptsExactContainedDeckIdentity()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            local deck = {tag='Deck', getGUID=function() return 'grave-deck' end,
                getObjects=function() return {{guid='contained-1', index=1}} end}
            local card = {tag='Card', getGUID=function() return 'contained-1' end}
            function getObjectFromGUID(guid)
                if guid == 'grave-deck' then return deck end
                if guid == 'contained-1' then return card end
                return nil
            end
            BridgeState.eventSessionId = 'session'
            BridgeRecordContainedCardIdentity('forge-object:1', 'grave-deck', 'contained-1', 'forge-player-1', 'graveyard', 'Plains')
            verified, verifyError = BridgeVerifyFinalPhysicalRepresentation('forge-object:1', 'forge-player-1', 'graveyard')
        ");

        Assert.True(lua.Globals.Get("verified").Boolean, lua.Globals.Get("verifyError").ToPrintString());
    }

    [Fact]
    public void FinalPhysicalRepresentationRejectsStaleContainedDeckMapping()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            local deck = {tag='Deck', getGUID=function() return 'grave-deck' end,
                getObjects=function() return {{guid='different-card', index=1}} end}
            function getObjectFromGUID(guid) if guid == 'grave-deck' then return deck end return nil end
            BridgeState.eventSessionId = 'session'
            BridgeRecordContainedCardIdentity('forge-object:1', 'grave-deck', 'contained-1', 'forge-player-1', 'graveyard', 'Plains')
            verified, verifyError = BridgeVerifyFinalPhysicalRepresentation('forge-object:1', 'forge-player-1', 'graveyard')
        ");

        Assert.False(lua.Globals.Get("verified").Boolean);
        Assert.Contains("contained card GUID is absent", lua.Globals.Get("verifyError").String);
    }

    [Fact]
    public void FinalPhysicalRepresentationRequiresExactLooseCardZoneAndSeat()
    {
        var lua = NewQueueProbe();
        lua.DoString(@"
            local card = {tag='Card', getGUID=function() return 'physical-1' end}
            function getObjectFromGUID(guid) if guid == 'physical-1' then return card end return nil end
            BridgeState.eventSessionId = 'session'
            BridgeRecordLooseCardIdentity('forge-object:1', 'physical-1', 'forge-player-1', 'hand')
            verified, verifyError = BridgeVerifyFinalPhysicalRepresentation('forge-object:1', 'forge-player-1', 'graveyard')
        ");

        Assert.False(lua.Globals.Get("verified").Boolean);
        Assert.Contains("missing final physical representation", lua.Globals.Get("verifyError").String);
    }

    private static Script NewQueueProbe()
    {
        var lua = new Script();
        ExecuteProbe(lua, "NewQueueProbe.bootstrap.lua", @"
            function log(message) end
            function broadcastToAll(message, color) end
            function printToAll(message, color) end
            function getObjectFromGUID(guid) return nil end
            function Wait(frames) end
            Time = { waitForSeconds = function(seconds, callback) callback() end }
            JSON = { encode = function(value) return '{}' end, decode = function(value) return {} end }
            os = { time = function() return 1 end, clock = function() return 0 end }
            math.randomseed(1)
            table.concat = function(values, separator)
                local result = ''
                for index, value in ipairs(values) do
                    if index > 1 then result = result .. separator end
                    result = result .. tostring(value)
                end
                return result
            end
        ");
        ExecuteProbe(lua, "Global.lua", Script);
        ExecuteProbe(lua, "NewQueueProbe.setup.lua", @"
            function BridgeTryApplyDeferredSnapshotReconcile(reason) end
            function BridgeTryStartPendingSnapshotReconcile(reason) end
            function BridgeTryPresentPendingDecision(reason) end
            function BridgeRefreshDecisionAfterStateTransition(reason) end
            function BridgeShouldReconcileAfterEvent(event) return false end
            function BridgeScheduleSnapshotReconcile(reason, category) end
            function BridgeStopOnDesync(reason) desyncReason = reason end
            function BridgeWaitTime(callback, delay) end
            -- This fixture tests cursor/scheduler semantics, not the native
            -- TTS extraction workers.  Model their required readiness result
            -- explicitly instead of relying on the unrelated table harness.
            function BridgePhysicalLibraryQueuesIdle() return true end
            BridgeState.eventPolling = true
            BridgeState.eventPollGeneration = 4
            BridgeState.eventSessionId = 'session'
            BridgeState.eventSessionGeneration = 1
            BridgeState.lastAppliedEventSequence = 7
            BridgeState.lastReceivedEventSequence = 9
            BridgeState.eventQueue = {}
            BridgeState.animationRunning = false
            BridgeState.bootstrapping = false
            BridgeState.desyncLatched = false
            BridgeState.resyncInFlight = false
            BridgeState.schedulerOwner = 'NORMAL'
            BridgeState.eventDrainTransaction = nil
            BridgeState.eventCommitWatchdog = nil
            BridgeState.eventDrainWatchdog = {}
            BridgeState.ui = BridgeState.ui or {}
            BridgeState.libraryBatchBySeatId = {}
            BridgeState.libraryExtractionQueueBySeatId = {}
            BridgeState.libraryExtractionActiveBySeatId = {}
            BridgeState.libraryExtractionTransactionBySeatId = {}
            BridgeState.graveyardExtractionActiveBySeatId = {}
            BridgeState.mulliganBottomQueueBySeatId = {}
            BridgeState.mulliganBottomInsertionActiveBySeatId = {}
        ");
        return lua;
    }

    private static void ExecuteProbe(Script lua, string sourceName, string source)
    {
        try
        {
            lua.DoString(source, null, sourceName);
        }
        catch (ScriptRuntimeException exception)
        {
            var marker = lua.Globals.Get("queueProbeMarker");
            throw new Xunit.Sdk.XunitException($"Lua failure in {sourceName}; marker={marker.ToPrintString()}:{Environment.NewLine}{exception.DecoratedMessage}");
        }
    }
}
