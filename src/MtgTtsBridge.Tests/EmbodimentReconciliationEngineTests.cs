using MoonSharp.Interpreter;

namespace MtgTtsBridge.Tests;

public sealed class EmbodimentReconciliationEngineTests
{
    private static readonly string GlobalScript = File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.lua"));

    [Fact]
    public void Capture1604LostBootstrapCallbackReobservesPhysicalHandsAndCommitsCursor14()
    {
        var lua = NewProbe();
        lua.DoString(@"
            BridgeState.lastAppliedEventSequence = 0
            BridgeState.lastReceivedEventSequence = 0
            physicalReady = false
            commitCount = 0
            callbackCount = 0
            BridgeConfigureEmbodimentFaultInjection({dropCallback='snapshot-reconcile'})
            function BridgeLegacyBootstrapCurrentSnapshot(sessionId, callback, resume, origin, tx)
                local snapshot = {sessionId='session-1604', eventCursor=14, forgeSequence=3, seats={}}
                BridgeEmbodimentSetSnapshot(tx, snapshot)
                physicalReady = true -- native hands moved before Wait callback disappeared
                BridgeState.physicalByInstanceId['human:1'] = 'new-guid-after-deal'
                BridgeState.physicalInstanceIdByGuid['new-guid-after-deal'] = 'human:1'
                BridgeState.physicalSeatByGuid['new-guid-after-deal'] = 'forge-player-1'
                BridgeState.physicalZoneByGuid['new-guid-after-deal'] = 'hand'
                BridgeDeliverEmbodimentOperationCallback(tx, tx.operationAttempt, true, nil, snapshot, 'snapshot-reconcile')
            end
            function BridgeReconcileSnapshotHandOwnership(snapshot) return physicalReady, physicalReady and nil or 'hand API lag' end
            function BridgeValidateAuthoritativeSnapshotPhysicalState(snapshot) return physicalReady, physicalReady and nil or 'hands incomplete' end
            function BridgeCommitSnapshotCheckpoint(snapshot, reason)
                commitCount = commitCount + 1
                BridgeState.lastAppliedEventSequence = snapshot.eventCursor
                BridgeState.lastReceivedEventSequence = snapshot.eventCursor
                return true, nil
            end
            BridgeBootstrapCurrentSnapshot('session-1604', function(ok, err)
                callbackCount = callbackCount + 1; finalOk = ok; finalError = err
            end, false, 'initial-bootstrap')
            for i = 1, 8 do
                BridgeState.updateTick = BridgeState.updateTick + 1
                BridgePumpEmbodimentTransaction()
            end
        ");

        Assert.True(lua.Globals.Get("finalOk").Boolean, lua.Globals.Get("finalError").ToPrintString());
        Assert.Equal(14, lua.Globals.Get("BridgeState").Table.Get("lastAppliedEventSequence").Number);
        Assert.Equal(1, lua.Globals.Get("commitCount").Number);
        Assert.Equal(1, lua.Globals.Get("callbackCount").Number);
        var ledger = lua.Globals.Get("BridgeState").Table.Get("committedPhysicalLedger").Table;
        Assert.Equal("new-guid-after-deal", ledger.Get("physicalByInstanceId").Table.Get("human:1").String);
    }

    [Fact]
    public void Capture87f3AlreadyMatchingHandsCommitCursor54WithoutASecondPhysicalDeal()
    {
        var lua = NewProbe();
        lua.DoString(@"
            BridgeState.lastAppliedEventSequence = 0
            BridgeState.lastReceivedEventSequence = 0
            nativeMutationCount = 0
            commitCount = 0
            function BridgeLegacyBootstrapCurrentSnapshot(sessionId, callback, resume, origin, tx)
                local snapshot = {sessionId='session-87f3', eventCursor=54, forgeSequence=4, seats={}}
                BridgeEmbodimentSetSnapshot(tx, snapshot)
                -- Snapshot transport/annotation completes, but observation says
                -- all fourteen hands already match, so no native move is issued.
                BridgeDeliverEmbodimentOperationCallback(tx, tx.operationAttempt, true, nil, snapshot, 'snapshot-reconcile')
            end
            function BridgeReconcileSnapshotHandOwnership(snapshot) return true, nil end
            function BridgeValidateAuthoritativeSnapshotPhysicalState(snapshot) return true, nil end
            function BridgeCommitSnapshotCheckpoint(snapshot, reason)
                commitCount = commitCount + 1
                BridgeState.lastAppliedEventSequence = snapshot.eventCursor
                BridgeState.lastReceivedEventSequence = snapshot.eventCursor
                return true, nil
            end
            BridgeConfigureEmbodimentFaultInjection({duplicateCallback='snapshot-reconcile'})
            BridgeBootstrapCurrentSnapshot('session-87f3', function(ok, err) finalOk=ok; finalError=err end,
                true, 'automatic')
        ");

        Assert.True(lua.Globals.Get("finalOk").Boolean, lua.Globals.Get("finalError").ToPrintString());
        Assert.Equal(54, lua.Globals.Get("BridgeState").Table.Get("lastAppliedEventSequence").Number);
        Assert.Equal(1, lua.Globals.Get("commitCount").Number);
        Assert.Equal(0, lua.Globals.Get("nativeMutationCount").Number);
    }

    [Fact]
    public void CaptureDeb9ManualOwnershipReplacesAutomaticPlanAndFencesItsLateCallback()
    {
        var lua = NewProbe();
        lua.DoString(@"
            BridgeState.lastAppliedEventSequence = 0
            automaticCallbackCount = 0
            manualCallbackCount = 0
            commitCount = 0
            physicalReady = false
            oldTx = BridgeBeginEmbodimentTransaction('session-deb9', 'automatic', true, function(ok, err)
                automaticCallbackCount = automaticCallbackCount + 1
            end)
            BridgeConfigureEmbodimentFaultInjection({delayCallback='snapshot-reconcile'})
            function BridgeLegacyBootstrapCurrentSnapshot(sessionId, callback, resume, origin, tx)
                local snapshot = {sessionId='session-deb9', eventCursor=54, forgeSequence=4, seats={}}
                BridgeEmbodimentSetSnapshot(tx, snapshot)
                BridgeDeliverEmbodimentOperationCallback(tx, tx.operationAttempt, true, nil, snapshot, 'snapshot-reconcile')
            end
            function BridgeReconcileSnapshotHandOwnership(snapshot) return physicalReady, 'not ready' end
            function BridgeValidateAuthoritativeSnapshotPhysicalState(snapshot) return physicalReady, 'not ready' end
            function BridgeCommitSnapshotCheckpoint(snapshot, reason)
                commitCount = commitCount + 1
                BridgeState.lastAppliedEventSequence = snapshot.eventCursor
                return true, nil
            end
            for i = 1, 3 do BridgePumpEmbodimentTransaction() end
            oldEpoch = oldTx.epoch
            BridgeAdvanceEmbodimentEpoch('hud-replaces-automatic')
            BridgeConfigureEmbodimentFaultInjection({})
            physicalReady = true
            manualTx = BridgeBeginEmbodimentTransaction('session-deb9', 'hud', true, function(ok, err)
                manualCallbackCount = manualCallbackCount + 1; manualOk = ok
            end)
            for i = 1, 10 do BridgePumpEmbodimentTransaction() end
            BridgeReleaseEmbodimentDelayedCallbacks()
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        Assert.Equal(54, state.Get("lastAppliedEventSequence").Number);
        Assert.Equal(1, lua.Globals.Get("commitCount").Number);
        Assert.Equal(0, lua.Globals.Get("automaticCallbackCount").Number);
        Assert.Equal(1, lua.Globals.Get("manualCallbackCount").Number);
        Assert.True(lua.Globals.Get("manualOk").Boolean);
        Assert.True(state.Get("embodimentEpoch").Number > lua.Globals.Get("oldEpoch").Number);
    }

    [Fact]
    public void HandApiLagIsASettlePredicateRatherThanAClockFailure()
    {
        var lua = NewProbe();
        lua.DoString(@"
            handProbe = 0
            commitCount = 0
            BridgeConfigureEmbodimentFaultInjection({dropCallback='snapshot-reconcile'})
            function BridgeLegacyBootstrapCurrentSnapshot(sessionId, callback, resume, origin, tx)
                local snapshot = {sessionId='hand-lag', eventCursor=54, forgeSequence=4, seats={}}
                BridgeEmbodimentSetSnapshot(tx, snapshot)
                BridgeDeliverEmbodimentOperationCallback(tx, tx.operationAttempt, true, nil, snapshot, 'snapshot-reconcile')
            end
            function BridgeReconcileSnapshotHandOwnership(snapshot)
                handProbe = handProbe + 1
                return handProbe >= 4, 'hand API lag'
            end
            function BridgeValidateAuthoritativeSnapshotPhysicalState(snapshot) return handProbe >= 4, 'hand API lag' end
            function BridgeCommitSnapshotCheckpoint(snapshot, reason) commitCount=commitCount+1; return true, nil end
            BridgeBootstrapCurrentSnapshot('hand-lag', function(ok, err) finalOk=ok end, true, 'resume')
            for i = 1, 10 do
                BridgeState.updateTick = BridgeState.updateTick + 1
                BridgePumpEmbodimentTransaction()
            end
        ");

        Assert.True(lua.Globals.Get("finalOk").Boolean);
        Assert.Equal(1, lua.Globals.Get("commitCount").Number);
        Assert.True(lua.Globals.Get("handProbe").Number >= 4);
    }

    [Fact]
    public void DesiredZoneStateExposesTheMillMigrationTopologyContract()
    {
        var lua = NewProbe();
        lua.DoString(@"
            function desiredWith(cards)
                return {sessionId='s', eventCursor=1, seats={{seatId='forge-player-1', zones={{
                    name='graveyard', cards=cards
                }}}}}
            end
            empty = BridgeBuildDesiredZoneState(desiredWith({}), 'forge-player-1', 'graveyard')
            loose = BridgeBuildDesiredZoneState(desiredWith({{cardInstanceId='a'}}), 'forge-player-1', 'graveyard')
            deck = BridgeBuildDesiredZoneState(desiredWith({{cardInstanceId='a'},{cardInstanceId='b'}}), 'forge-player-1', 'graveyard')
        ");

        Assert.Equal("EMPTY", lua.Globals.Get("empty").Table.Get("topology").String);
        Assert.Equal("CARD", lua.Globals.Get("loose").Table.Get("topology").String);
        Assert.Equal("DECK", lua.Globals.Get("deck").Table.Get("topology").String);
    }

    [Fact]
    public void NewMatchCleanupCompletesFromObservationWhenItsNativeCallbackIsLost()
    {
        var lua = NewProbe();
        lua.DoString(@"
            cleanupCalls = 0
            completionCount = 0
            function BridgeReturnPreviousGameCardsToLibraries(callback)
                cleanupCalls = cleanupCalls + 1
                -- The native move completed, but its Wait callback disappeared.
            end
            BridgeAdvanceEmbodimentEpoch('new-match-1')
            BridgeBeginNewMatchCleanupTransaction(function(ok, err)
                if ok then completionCount = completionCount + 1 end
            end)
            BridgePumpEmbodimentTransaction()
            BridgePumpEmbodimentTransaction()

            BridgeAdvanceEmbodimentEpoch('new-match-2')
            BridgeBeginNewMatchCleanupTransaction(function(ok, err)
                if ok then completionCount = completionCount + 1 end
            end)
            BridgePumpEmbodimentTransaction()
            BridgePumpEmbodimentTransaction()
        ");

        Assert.Equal(2, lua.Globals.Get("cleanupCalls").Number);
        Assert.Equal(2, lua.Globals.Get("completionCount").Number);
        Assert.True(lua.Globals.Get("BridgeState").Table.Get("embodimentTransaction").IsNil());
    }

    [Fact]
    public void ObservationUsesLiveHandMembershipAndAdvertisedIdentityInsteadOfCommittedMappings()
    {
        var lua = NewProbe();
        lua.DoString(@"
            card = {tag='Card', guid='live-hand-guid', instance='forge-card:16', session='observed-session'}
            duplicate = {tag='Card', guid='duplicate-guid', instance='forge-card:16', session='observed-session'}
            function BridgeSafeObjectGuid(object) return object.guid end
            function BridgeReadPhysicalIdentity(object) return object.instance end
            function BridgeReadPhysicalSessionIdentity(object) return object.session end
            function BridgeTryGetSeatHandObjects(seatId)
                if seatId == 'forge-player-1' then return {card}, nil end
                return {}, nil
            end
            function getAllObjects() return {card} end
            desired = BridgeBuildDesiredPhysicalState({sessionId='observed-session', eventCursor=54, seats={{
                seatId='forge-player-1', zones={{name='hand', cards={{cardInstanceId='forge-card:16'}}}}
            }}})
            observed = BridgeObservePhysicalState(desired)
            observedCard = observed.byInstanceId['forge-card:16']
            committedMappingCount = 0
            for _ in pairs(BridgeState.physicalByInstanceId) do committedMappingCount = committedMappingCount + 1 end
            function getAllObjects() return {card, duplicate} end
            ambiguousPlan = BridgePlanEmbodimentReconciliation(desired, BridgeObservePhysicalState(desired))
        ");

        Assert.Equal(0, lua.Globals.Get("committedMappingCount").Number);
        var observedCard = lua.Globals.Get("observedCard").Table;
        Assert.Equal("hand", observedCard.Get("zone").String);
        Assert.Equal("forge-player-1", observedCard.Get("seatId").String);
        Assert.Equal("duplicate exact physical identity",
            lua.Globals.Get("ambiguousPlan").Table.Get("blockingPredicate").String);
    }

    private static Script NewProbe()
    {
        var lua = new Script();
        lua.DoString(@"
            function log(message) end
            function broadcastToAll(message, color) end
            function printToAll(message, color) end
            function getObjectFromGUID(guid) return nil end
            function getAllObjects() return {} end
            function Wait(frames) end
            Time = {waitForSeconds=function(seconds, callback) callback() end}
            JSON = {encode=function(value) return '{}' end, decode=function(value) return {} end}
            os = {time=function() return 1 end, clock=function() return 0 end}
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
        lua.DoString(GlobalScript);
        lua.DoString(@"
            BridgeState.eventSessionId = 'session'
            BridgeState.eventQueue = {}
            BridgeState.updateTick = 0
            BridgeState.bootstrapping = false
            BridgeState.resyncInFlight = false
            BridgeState.ui = BridgeState.ui or {}
            function BridgeUiMarkDirty(reason) end
            function BridgeStopOnDesync(reason) end
        ");
        return lua;
    }
}
