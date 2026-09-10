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
    public void BootstrapWaitingForLibrarySettlementIsNotMisclassifiedAsLostCallback()
    {
        var lua = NewProbe();
        lua.DoString(@"
            callbackLost = 0
            function BridgeLegacyBootstrapCurrentSnapshot(sessionId, callback, resume, origin, tx)
                local snapshot = {sessionId=sessionId, eventCursor=14, forgeSequence=4, seats={}}
                BridgeEmbodimentSetSnapshot(tx, snapshot)
                callback(true, nil, snapshot, {status='WAITING_FOR_PHYSICAL_SETTLEMENT', reason='blank contained identity'})
            end
            local rawJournal = BridgeEmbodimentJournal
            BridgeEmbodimentJournal = function(tx, phase, operation, detail)
                if operation == 'CALLBACK_LOST_REPLAN' then callbackLost = callbackLost + 1 end
                return rawJournal(tx, phase, operation, detail)
            end
            BridgeBootstrapCurrentSnapshot('settlement', function(ok, err) finalOk, finalErr = ok, err end, false, 'initial-bootstrap')
            tx = BridgeState.embodimentTransaction
            initialReplans = tx and tx.replanCount or -1
            for i = 1, 20 do
                BridgeState.updateTick = BridgeState.updateTick + 1
                BridgePumpEmbodimentTransaction()
            end
            finalTx = BridgeState.embodimentTransaction
        ");

        Assert.True(lua.Globals.Get("finalOk").IsNil());
        Assert.Equal(0, lua.Globals.Get("initialReplans").Number);
        Assert.Equal(0, lua.Globals.Get("callbackLost").Number);
        Assert.False(lua.Globals.Get("finalTx").IsNil());
    }

    [Fact]
    public void LegacyBootstrapPreservesAuthoritativeSnapshotAcrossSeatOutcome()
    {
        var lua = NewProbe();
        lua.DoString(@"
            BridgeGetEmbodimentSnapshot = function(callback)
                callback(true, {sessionId='session', eventCursor=11, forgeSequence=4, seats={}}, nil)
            end
            function BridgeStageSeatCardsForBootstrap(snapshot, callback) callback(true, nil, {}) end
            function BridgeVerifyLibraryIdentityStability(callback) callback(true, nil) end
            function BridgeAnnotateSnapshotBattlefieldKinds(snapshot, callback) callback(true, nil) end
            function BridgeValidateAuthoritativeSnapshotPhysicalState(_) return false, 'seat outcome not physically verified' end
            function BridgeBootstrapSeats(snapshot, seatIndex, callback)
                callback(BridgeMakeEmbodimentResult('FAILED', snapshot, 'seat outcome failed', {status='FAILED'}))
            end
            BridgeBootstrapCurrentSnapshot('session', function(ok, err) finalOk, finalErr = ok, err end,
                false, 'initial-bootstrap')
            finalTx = BridgeState.embodimentTransaction or BridgeState.lastEmbodimentTransaction
        ");

        Assert.False(lua.Globals.Get("finalOk").Boolean);
        Assert.Equal(11, lua.Globals.Get("finalTx").Table.Get("targetCursor").Number);
        Assert.DoesNotContain("cursor0", lua.Globals.Get("finalErr").IsNil() ? "" : lua.Globals.Get("finalErr").String);
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
    public void LibraryUnsettledStateUsesSeatLibraryReplanNotWholeSnapshot()
    {
        var lua = NewProbe();
        lua.DoString(@"
            desired = {cardsByInstanceId={
                a={cardInstanceId='a', seatId='forge-player-1', zone='library'},
                b={cardInstanceId='b', seatId='forge-player-1', zone='library'}
            }}
            observed = {byInstanceId={}, duplicateInstanceIds={}, unsettledContainedEntries={
                {deckGuid='library-1', seatId='forge-player-1', zone='library'}
            }}
            plan = BridgePlanEmbodimentReconciliation(desired, observed)
            operationCount = #plan.operations
            _, firstOperation = next(plan.operations)
            operationScope = firstOperation and firstOperation.scope or nil
            operationSeat = firstOperation and firstOperation.seatId or nil
        ");

        var plan = lua.Globals.Get("plan").Table;
        Assert.Equal(1, lua.Globals.Get("operationCount").Number);
        Assert.Equal(0, plan.Get("missing").Table.Length);
        Assert.Equal("SEAT_LIBRARY", lua.Globals.Get("operationScope").String);
        Assert.Equal("forge-player-1", lua.Globals.Get("operationSeat").String);
        Assert.Equal("PRESENT_BUT_UNSETTLED", plan.Get("unsettledZones").Table.Get("forge-player-1:library").String);
    }

    [Fact]
    public void ZoneObservationRequiresSeatAndZone()
    {
        var lua = NewProbe();
        lua.DoString(@"
            observed = {byInstanceId={
                human={instanceId='human', seatId='forge-player-1', zone='hand'},
                ai={instanceId='ai', seatId='forge-player-2', zone='hand'}
            }}
            zone = BridgeObserveZoneState({seatId='forge-player-2', zone='hand'}, observed)
        ");

        var zone = lua.Globals.Get("zone").Table;
        Assert.True(zone.Get("instanceIds").Table.Get("ai").Boolean);
        Assert.True(zone.Get("instanceIds").Table.Get("human").IsNil());
        Assert.Equal(1, zone.Get("count").Number);
    }

    [Fact]
    public void HiddenAiHandCardAbsentFromGetAllObjectsStillObserved()
    {
        var lua = NewProbe();
        lua.DoString(@"
            BRIDGE_SEATS = {['forge-player-1'] = true, ['forge-player-2'] = true}
            aiCard = {tag='Card', getGUID=function() return 'ai-hand-guid' end}
            function BridgeTryGetSeatHandObjects(seatId)
                return seatId == 'forge-player-2' and {aiCard} or {}
            end
            function getAllObjects() return {} end
            function BridgeReadPhysicalIdentity(object) return object == aiCard and 'forge:session:71' or nil end
            observed = BridgeObservePhysicalState(nil)
        ");

        var observed = lua.Globals.Get("observed").Table;
        var card = observed.Get("byInstanceId").Table.Get("forge:session:71").Table;
        Assert.Equal("forge-player-2", card.Get("seatId").String);
        Assert.Equal("hand", card.Get("zone").String);
        Assert.False(observed.Get("duplicateInstanceIds").Table.Get("forge:session:71").Boolean);
    }

    [Fact]
    public void UnmappedExistingAiHandCanBindWithoutRedeal()
    {
        var lua = NewProbe();
        lua.DoString(@"
            aiCard = {tag='Card', getGUID=function() return 'ai-hand-guid' end,
                getName=function() return 'Goblin Piker' end}
            function BridgeTryGetSeatHandObjects(_) return {aiCard} end
            BridgeState.eventSessionId = 'session'
            BridgeBindHandMappingsForSnapshot({seatId='forge-player-2', zones={{name='hand', cards={{
                cardInstanceId='forge:session:67', cardName='Goblin Piker', zonePosition=0
            }}}}}, function(ok, err, outcome) bindOk, bindErr, bindOutcome = ok, err, outcome end)
            mapping = BridgeState.physicalByInstanceId['forge:session:67']
        ");

        Assert.True(lua.Globals.Get("bindOk").Boolean, lua.Globals.Get("bindErr").ToPrintString());
        Assert.Equal("ai-hand-guid", lua.Globals.Get("mapping").String);
        Assert.Equal("SUCCESS", lua.Globals.Get("bindOutcome").Table.Get("status").String);
    }

    [Fact]
    public void HandBindingIsAtomicWhenThePhysicalMultisetDoesNotMatch()
    {
        var lua = NewProbe();
        lua.DoString(@"
            first = {tag='Card', getGUID=function() return 'hand-1' end,
                getName=function() return 'Goblin Piker' end}
            second = {tag='Card', getGUID=function() return 'hand-2' end,
                getName=function() return 'Wrong Card' end}
            function BridgeTryGetSeatHandObjects(_) return {first, second} end
            BridgeState.eventSessionId = 'session'
            BridgeBindHandMappingsForSnapshot({seatId='forge-player-2', zones={{name='hand', cards={
                {cardInstanceId='forge:session:67', cardName='Goblin Piker', zonePosition=0},
                {cardInstanceId='forge:session:68', cardName='Swamp', zonePosition=1}
            }}}}, function(ok, err, outcome) bindOk, bindErr, bindOutcome = ok, err, outcome end)
            published = 0
            for _ in pairs(BridgeState.physicalByInstanceId) do published = published + 1 end
        ");

        Assert.False(lua.Globals.Get("bindOk").Boolean);
        Assert.Equal(0, lua.Globals.Get("published").Number);
        Assert.Equal("FAILED", lua.Globals.Get("bindOutcome").Table.Get("status").String);
    }

    [Fact]
    public void OldMatchToNewMatchConvergesAcrossTransientContainedGuidsAndHiddenAiHand()
    {
        var lua = NewProbe();
        lua.DoString(@"
            local humanDeck = {tag='Deck', getGUID=function() return 'human-library' end,
                getObjects=function() return {{guid=' ', nickname='Swamp', index=0}, {guid=' ', nickname='Mental Note', index=1}} end}
            local aiDeck = {tag='Deck', getGUID=function() return 'ai-library' end,
                getObjects=function() return {{guid=' ', nickname='Swamp', index=0}, {guid=' ', nickname='Mental Note', index=1}} end}
            local function handCard(guid)
                local card = {tag='Card', bridgeId=nil, bridgeSession=nil,
                    getGUID=function() return guid end, getName=function() return 'Goblin Piker' end}
                card.getVar=function(key) return key == 'bridgeCardInstanceId' and card.bridgeId or (key == 'bridgeSessionId' and card.bridgeSession or nil) end
                card.setVar=function(key, value) if key == 'bridgeCardInstanceId' then card.bridgeId=value elseif key == 'bridgeSessionId' then card.bridgeSession=value end end
                return card
            end
            local humanHand = handCard('human-hand')
            local aiHand = handCard('ai-hand')
            function BridgeResolveSeatLibraryDeck(seatId)
                return seatId == 'forge-player-1' and humanDeck or aiDeck, {}, nil
            end
            function BridgeTryGetSeatHandObjects(seatId)
                return seatId == 'forge-player-1' and {humanHand} or {aiHand}, nil
            end
            function getObjectFromGUID(guid)
                if guid == 'human-library' then return humanDeck end
                if guid == 'ai-library' then return aiDeck end
                if guid == 'human-hand' then return humanHand end
                if guid == 'ai-hand' then return aiHand end
                return nil
            end
            BridgeState.eventSessionId = 'new-session'
            local humanSnapshot = {seatId='forge-player-1', zones={
                {name='library', cards={{cardInstanceId='new-session:h1', cardName='Swamp', zonePosition=0}, {cardInstanceId='new-session:h2', cardName='Mental Note', zonePosition=1}}},
                {name='hand', cards={{cardInstanceId='new-session:hh', cardName='Goblin Piker', zonePosition=0}}}}}
            local aiSnapshot = {seatId='forge-player-2', zones={
                {name='library', cards={{cardInstanceId='new-session:a1', cardName='Swamp', zonePosition=0}, {cardInstanceId='new-session:a2', cardName='Mental Note', zonePosition=1}}},
                {name='hand', cards={{cardInstanceId='new-session:ah', cardName='Goblin Piker', zonePosition=0}}}}}
            local snapshot = {sessionId='new-session', eventCursor=14, seats={humanSnapshot, aiSnapshot}}
            BridgeBindLibraryMappingsForSnapshot(humanSnapshot, function(ok, err, outcome) humanLibraryOk, humanLibraryErr, humanLibraryOutcome = ok, err, outcome end)
            BridgeBindLibraryMappingsForSnapshot(aiSnapshot, function(ok, err, outcome) aiLibraryOk, aiLibraryErr, aiLibraryOutcome = ok, err, outcome end)
            BridgeBindHandMappingsForSnapshot(humanSnapshot, function(ok, err, outcome) humanHandOk, humanHandErr, humanHandOutcome = ok, err, outcome end)
            BridgeBindHandMappingsForSnapshot(aiSnapshot, function(ok, err, outcome) aiHandOk, aiHandErr, aiHandOutcome = ok, err, outcome end)
            BridgeState.lastAppliedEventSequence = 0
            function BridgeCommitSnapshotCheckpoint(candidate) BridgeState.lastAppliedEventSequence = candidate.eventCursor; return true, nil end
            committed = BridgeCommitSnapshotCheckpoint(snapshot)
            function getAllObjects() return {humanDeck, aiDeck} end
            observed = BridgeObservePhysicalState(BridgeBuildDesiredPhysicalState(snapshot))
        ");

        Assert.True(lua.Globals.Get("humanLibraryOk").Boolean);
        Assert.True(lua.Globals.Get("aiLibraryOk").Boolean, lua.Globals.Get("aiLibraryErr").ToPrintString());
        Assert.True(lua.Globals.Get("humanHandOk").Boolean);
        Assert.True(lua.Globals.Get("aiHandOk").Boolean);
        Assert.Equal("SLOT_LOCATOR", lua.Globals.Get("BridgeState").Table.Get("physicalContainerByInstanceId").Table.Get("new-session:a1").Table.Get("locatorType").String);
        Assert.Equal("ai-hand", lua.Globals.Get("BridgeState").Table.Get("physicalByInstanceId").Table.Get("new-session:ah").String);
        Assert.Equal(14, lua.Globals.Get("BridgeState").Table.Get("lastAppliedEventSequence").Number);
        Assert.False(lua.Globals.Get("observed").Table.Get("byInstanceId").Table.Get("new-session:ah").IsNil());
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
    public void NewMatchCleanupCannotCommitWhilePreviousGameHandIsNonEmpty()
    {
        var lua = NewProbe();
        lua.DoString(@"
            local oldHand = {tag='Card', getGUID=function() return 'old-hand' end}
            BRIDGE_SEATS = {['forge-player-1'] = {}}
            function BridgeTryGetSeatHandObjects(_) return {oldHand} end
            function BridgeReturnPreviousGameCardsToLibraries(callback) callback(true, nil) end
            BridgeAdvanceEmbodimentEpoch('cleanup-hand-regression')
            BridgeBeginNewMatchCleanupTransaction(function(ok, err) cleanupOk, cleanupErr = ok, err end)
            BridgePumpEmbodimentTransaction()
            BridgeState.updateTick = BridgeState.updateTick + 1
            BridgePumpEmbodimentTransaction()
        ");

        Assert.False(lua.Globals.Get("cleanupOk").Boolean);
        Assert.Contains("hand", lua.Globals.Get("BridgeState").Table.Get("embodimentTransaction").Table.Get("lastBlockingPredicate").String);
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

    [Fact]
    public void AuthoritativeSnapshotValidationAcceptsValidSlotBoundLibraryCard()
    {
        var lua = NewProbe();
        lua.DoString(@"
            local deck = {tag='Deck', getGUID=function() return 'library' end,
                getObjects=function() return {{index=4, nickname='Mental Note', guid=' '}} end}
            function getObjectFromGUID(guid) if guid == 'library' then return deck end end
            BridgeState.libraryBindingGenerationBySeatId = {['forge-player-1']=7}
            BridgeState.physicalContainerByInstanceId = {['X']={locatorType='SLOT_LOCATOR', deckGuid='library', slotIndex=4, bindingGeneration=7, seatId='forge-player-1', zoneName='library', cardName='Mental Note'}}
            BridgeState.physicalContainedInstanceIdByGuid = {}
            BridgeState.physicalByInstanceId = {}; BridgeState.physicalInstanceIdByGuid = {}
            valid, validationError = BridgeValidateAuthoritativeSnapshotPhysicalState({sessionId='session', eventCursor=14, seats={{seatId='forge-player-1', zones={{name='library', cards={{cardInstanceId='X', cardName='Mental Note'}}}}}}})
        ");

        Assert.True(lua.Globals.Get("valid").Boolean, lua.Globals.Get("validationError").ToPrintString());
    }

    [Fact]
    public void AuthoritativeSnapshotValidationSupportsMixedGuidAndSlotLibraryLocators()
    {
        var lua = NewProbe();
        lua.DoString(@"
            local deck = {tag='Deck', getGUID=function() return 'library' end, getObjects=function() return {
                {index=1, nickname='Swamp', guid='guid-swamp'}, {index=4, nickname='Mental Note', guid=' '}} end}
            function getObjectFromGUID(guid) if guid == 'library' then return deck end end
            BridgeState.libraryBindingGenerationBySeatId = {['forge-player-1']=7}
            BridgeState.physicalContainerByInstanceId = {
                ['G']={locatorType='GUID_LOCATOR', deckGuid='library', cardGuid='guid-swamp', seatId='forge-player-1', zoneName='library'},
                ['S']={locatorType='SLOT_LOCATOR', deckGuid='library', slotIndex=4, bindingGeneration=7, seatId='forge-player-1', zoneName='library', cardName='Mental Note'}}
            BridgeState.physicalContainedInstanceIdByGuid = {['guid-swamp']='G'}
            BridgeState.physicalSeatByGuid = {['guid-swamp']='forge-player-1'}
            BridgeState.physicalZoneByGuid = {['guid-swamp']='library'}
            BridgeState.physicalByInstanceId = {}; BridgeState.physicalInstanceIdByGuid = {}
            valid, validationError = BridgeValidateAuthoritativeSnapshotPhysicalState({sessionId='session', eventCursor=14, seats={{seatId='forge-player-1', zones={{name='library', cards={{cardInstanceId='G', cardName='Swamp'}, {cardInstanceId='S', cardName='Mental Note'}}}}}}})
        ");

        Assert.True(lua.Globals.Get("valid").Boolean, lua.Globals.Get("validationError").ToPrintString());
    }

    [Fact]
    public void AuthoritativeSnapshotValidationRejectsStaleSlotLocator()
    {
        var lua = NewProbe();
        lua.DoString(@"
            local deck = {tag='Deck', getGUID=function() return 'library' end,
                getObjects=function() return {{index=4, nickname='Mental Note', guid=' '}} end}
            function getObjectFromGUID(guid) if guid == 'library' then return deck end end
            BridgeState.libraryBindingGenerationBySeatId = {['forge-player-1']=8}
            BridgeState.physicalContainerByInstanceId = {['X']={locatorType='SLOT_LOCATOR', deckGuid='library', slotIndex=4, bindingGeneration=7, seatId='forge-player-1', zoneName='library', cardName='Mental Note'}}
            BridgeState.physicalContainedInstanceIdByGuid = {}; BridgeState.physicalByInstanceId = {}; BridgeState.physicalInstanceIdByGuid = {}
            valid, validationError = BridgeValidateAuthoritativeSnapshotPhysicalState({sessionId='session', eventCursor=14, seats={{seatId='forge-player-1', zones={{name='library', cards={{cardInstanceId='X', cardName='Mental Note'}}}}}}})
        ");

        Assert.False(lua.Globals.Get("valid").Boolean);
        Assert.Contains("generation is stale", lua.Globals.Get("validationError").String);
    }

    [Fact]
    public void SeatLocalReplanStopsAfterBoundedNoProgressFingerprint()
    {
        var lua = NewProbe();
        lua.DoString(@"
            local deck = {tag='Deck', getGUID=function() return 'library' end,
                getObjects=function() return {{index=4, nickname='Mental Note', guid=' '}} end}
            function BridgeResolveSeatLibraryDeck(_) return deck end
            BridgeState.libraryBindingGenerationBySeatId = {['forge-player-1']=7}
            BridgeState.physicalContainerByInstanceId = {['X']={locatorType='SLOT_LOCATOR', deckGuid='library', slotIndex=4, bindingGeneration=7, seatId='forge-player-1', zoneName='library', cardName='Mental Note'}}
            local tx = {targetCursor=14, lastBlockingPredicate='validator rejects representation'}
            local operation = {scope='SEAT_LIBRARY', seatId='forge-player-1', zone='library'}
            first = BridgeLocalReplanProgressFingerprint(tx, operation)
            -- A successful identity rebind can advance this bookkeeping
            -- generation without changing the physical Deck at all.  That
            -- must not masquerade as progress for a permanently rejected
            -- representation.
            BridgeState.libraryBindingGenerationBySeatId['forge-player-1'] = 8
            second = BridgeLocalReplanProgressFingerprint(tx, operation)
        ");

        Assert.Equal(lua.Globals.Get("first").String, lua.Globals.Get("second").String);
    }

    [Fact]
    public void LondonMulliganSourceAssignmentRequiresCanonicalIdentityMetadata()
    {
        var lua = NewProbe();
        lua.DoString(@"
            local deck = {tag='Deck', getGUID=function() return 'ai-library' end,
                getObjects=function() return {{index=1, nickname='Mountain', guid='mountain-guid'}} end}
            function BridgeResolveSeatLibraryDeck(seatId) return deck end
            local seat = {seatId='forge-player-2', zones={
                {name='library', cards={}},
                {name='hand', cards={{cardInstanceId='forge:ai:62'}}}}}
            sourcePlan, sourceError = BridgeBuildSeatSourceAssignment(seat, {})
        ");

        Assert.True(lua.Globals.Get("sourcePlan").IsNil());
        Assert.Contains("canonical card name", lua.Globals.Get("sourceError").String);
        Assert.DoesNotContain("physical card nil", lua.Globals.Get("sourceError").String);
    }

    [Fact]
    public void LondonMulliganSourceAssignmentPreservesDuplicateNamesByExactInstance()
    {
        var lua = NewProbe();
        lua.DoString(@"
            local deck = {tag='Deck', getGUID=function() return 'ai-library' end,
                getObjects=function() return {
                    {index=1, nickname='Mountain', guid='mountain-a'},
                    {index=2, nickname='Mountain', guid='mountain-b'}} end}
            function BridgeResolveSeatLibraryDeck(seatId) return deck end
            local seat = {seatId='forge-player-2', zones={
                {name='library', cards={}},
                {name='hand', cards={
                    {cardInstanceId='forge:ai:62', cardName='Mountain', zonePosition=1},
                    {cardInstanceId='forge:ai:63', cardName='Mountain', zonePosition=2}}}}}
            sourcePlan, sourceError = BridgeBuildSeatSourceAssignment(seat, {})
        ");

        Assert.False(lua.Globals.Get("sourcePlan").IsNil(), lua.Globals.Get("sourceError").ToPrintString());
        var assignments = lua.Globals.Get("sourcePlan").Table.Get("assignments").Table;
        var first = assignments.Get("forge:ai:62").Table.Get("source").Table;
        var second = assignments.Get("forge:ai:63").Table.Get("source").Table;
        Assert.NotEqual(first.Get("guid").String, second.Get("guid").String);
    }

    [Fact]
    public void NewMatchRetiresOldSessionIdentityBeforeBootstrap()
    {
        var lua = NewProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'old-session'
            BridgeState.physicalOwnershipSessionId = 'old-session'
            BridgeState.physicalByInstanceId = {['forge:old-session:4']='old-guid'}
            BridgeState.physicalInstanceIdByGuid = {['old-guid']='forge:old-session:4'}
            BridgeState.physicalContainerByInstanceId = {['forge:old-session:5']={deckGuid='old-library', cardGuid='old-contained', seatId='forge-player-1', zoneName='library'}}
            BridgeState.physicalContainedInstanceIdByGuid = {['old-contained']='forge:old-session:5'}
            BridgeState.physicalSlotByInstanceId = {['forge:old-session:6']={deckGuid='old-library', slotIndex=2}}
            BridgeState.libraryBindingGenerationBySeatId = {['forge-player-1']=9}
            function BridgeStopEventPolling(reason) end
            function BridgeAdvanceEventSessionGeneration(reason) BridgeState.eventSessionGeneration=(BridgeState.eventSessionGeneration or 0)+1 end
            function BridgeStopDecisionPolling() end
            function BridgeReturnAttackPresentation(value) end
            function BridgeRetireResourceRowObjects() end
            function BridgeHydratePresentationObjectIndexes() end
            function BridgeClearPreparedPresentationObjects() end
            function BridgeAdvancePhysicalPresentationGeneration(reason) end
            function BridgeAdvancePhysicalTransactionGeneration(reason) BridgeState.physicalTransactionGeneration=(BridgeState.physicalTransactionGeneration or 0)+1 end
            function BridgeCreatureTypeClearDraft(reason) end
            function BridgeGraveyardClear(reason) end
            function BridgeGetLiveObjectByGuid(guid) return nil end
            BridgePrepareEventSession('new-session', true, true)
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        Assert.True(state.Get("physicalByInstanceId").Table.Get("forge:old-session:4").IsNil());
        Assert.True(state.Get("physicalContainerByInstanceId").Table.Get("forge:old-session:5").IsNil());
        Assert.True(state.Get("physicalSlotByInstanceId").Table.Get("forge:old-session:6").IsNil());
        Assert.Equal(0, state.Get("libraryBindingGenerationBySeatId").Table.Length);
        Assert.Equal("new-session", state.Get("physicalOwnershipSessionId").String);
    }

    [Fact]
    public void NewMatchRetiresOldPhysicalCardAdvertisementBeforeNewBootstrap()
    {
        var lua = NewProbe();
        lua.DoString(@"
            local oldCard = {tag='Card', guid='thought-scour-card', vars={
                bridgeCardInstanceId='forge:old-session:35', bridgeSessionId='old-session'}}
            oldCard.getGUID = function() return oldCard.guid end
            oldCard.getVar = function(key) return oldCard.vars[key] end
            oldCard.setVar = function(key, value) oldCard.vars[key] = value end
            BridgeObjectIsUsable = function(object) return object ~= nil end
            BridgeSafeObjectGuid = function(object) return object and object.getGUID and object.getGUID() or nil end
            BridgeIsPresentationOnlyObject = function(object) return false end
            function getAllObjects() return {oldCard} end
            BridgeState.eventSessionId = 'old-session'
            BridgeState.physicalOwnershipSessionId = 'old-session'
            BridgeState.physicalByInstanceId = {['forge:old-session:35']='thought-scour-card'}
            BridgeState.physicalInstanceIdByGuid = {['thought-scour-card']='forge:old-session:35'}
            function BridgeStopEventPolling(reason) end
            function BridgeAdvanceEventSessionGeneration(reason) BridgeState.eventSessionGeneration=(BridgeState.eventSessionGeneration or 0)+1 end
            function BridgeStopDecisionPolling() end
            function BridgeReturnAttackPresentation(value) end
            function BridgeRetireResourceRowObjects() end
            function BridgeHydratePresentationObjectIndexes() end
            function BridgeClearPreparedPresentationObjects() end
            function BridgeAdvancePhysicalPresentationGeneration(reason) end
            function BridgeAdvancePhysicalTransactionGeneration(reason) BridgeState.physicalTransactionGeneration=(BridgeState.physicalTransactionGeneration or 0)+1 end
            function BridgeCreatureTypeClearDraft(reason) end
            function BridgeGraveyardClear(reason) end
            function BridgeGetLiveObjectByGuid(guid) if guid == 'thought-scour-card' then return oldCard end end
            BridgePrepareEventSession('new-session', true, false)
            retiredInstance = oldCard.vars.bridgeCardInstanceId
            retiredSession = oldCard.vars.bridgeSessionId
            function staleOldCallback()
                if BridgeState.eventSessionId ~= 'old-session' then return end
                BridgeWritePhysicalIdentity(oldCard, 'forge:old-session:35')
            end
            staleOldCallback()
            instanceAfterStaleCallback = oldCard.vars.bridgeCardInstanceId
        ");

        Assert.True(lua.Globals.Get("retiredInstance").IsNil());
        Assert.True(lua.Globals.Get("retiredSession").IsNil());
        Assert.True(lua.Globals.Get("instanceAfterStaleCallback").IsNil());
    }

    [Fact]
    public void SlotLocatorRefreshAfterLibraryMutationUsesCurrentDeckTopology()
    {
        var lua = NewProbe();
        lua.DoString(@"
            local deck = {tag='Deck', getGUID=function() return 'library' end,
                getObjects=function() return {
                    {index=3, nickname='Armored Skaab', guid=' '},
                    {index=8, nickname='Armored Skaab', guid=' '}}
                end}
            function getObjectFromGUID(guid) if guid == 'library' then return deck end end
            BridgeState.libraryBindingGenerationBySeatId = {['forge-player-1']=4}
            BridgeState.physicalContainerByInstanceId = {
                ['forge:session:4']={locatorType='SLOT_LOCATOR', deckGuid='library', slotIndex=1,
                    bindingGeneration=3, seatId='forge-player-1', zoneName='library', cardName='Armored Skaab'},
                ['forge:session:9']={locatorType='SLOT_LOCATOR', deckGuid='library', slotIndex=2,
                    bindingGeneration=3, seatId='forge-player-1', zoneName='library', cardName='Armored Skaab'}}
            BridgeState.physicalSlotByInstanceId = {}
            refreshed, refreshError = BridgeRefreshLibrarySlotBindings('library')
            resolvedDeck, resolvedEntry, resolveError = BridgeFindContainedCardEntry('forge:session:9', 'library')
        ");

        Assert.True(lua.Globals.Get("refreshed").Boolean, lua.Globals.Get("refreshError").ToPrintString());
        Assert.True(lua.Globals.Get("resolvedDeck").Table is not null, lua.Globals.Get("resolveError").ToPrintString());
        Assert.Equal(8, lua.Globals.Get("resolvedEntry").Table.Get("index").Number);
        var mappings = lua.Globals.Get("BridgeState").Table.Get("physicalContainerByInstanceId").Table;
        Assert.Equal(mappings.Get("forge:session:9").Table.Get("bindingGeneration").Number,
            lua.Globals.Get("BridgeState").Table.Get("libraryBindingGenerationBySeatId").Table.Get("forge-player-1").Number);
    }

    [Fact]
    public void StaleSlotLocatorIsNeverUsedDirectlyWhenRefreshCannotProveIdentity()
    {
        var lua = NewProbe();
        lua.DoString(@"
            local deck = {tag='Deck', getGUID=function() return 'library' end,
                getObjects=function() return {{index=9, nickname='Mountain', guid=' '}} end}
            function getObjectFromGUID(guid) if guid == 'library' then return deck end end
            BridgeState.libraryBindingGenerationBySeatId = {['forge-player-1']=5}
            BridgeState.physicalContainerByInstanceId = {['forge:session:4']={locatorType='SLOT_LOCATOR', deckGuid='library',
                slotIndex=1, bindingGeneration=4, seatId='forge-player-1', zoneName='library', cardName='Armored Skaab'}}
            BridgeState.physicalSlotByInstanceId = {}
            refreshed, refreshError = BridgeRefreshLibrarySlotBindings('library')
            resolvedDeck, resolvedEntry, resolveError = BridgeFindContainedCardEntry('forge:session:4', 'library')
        ");

        Assert.False(lua.Globals.Get("refreshed").Boolean);
        Assert.True(lua.Globals.Get("resolvedDeck").IsNil());
        Assert.Contains("generation is stale", lua.Globals.Get("resolveError").String);
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
