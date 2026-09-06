using MoonSharp.Interpreter;

namespace MtgTtsBridge.Tests;

public sealed class AtomicMultiCardPhysicalMaterializationTests
{
    private static readonly string Script = File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.lua"));

    [Fact]
    public void MentalNoteTwoCardMillCommitsNativeGraveyardAtomically()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            BridgeState.lastAppliedEventSequence = 65
            BridgeState.lastReceivedEventSequence = 67
            BridgeState.cardNameByInstanceId[':A'] = 'Island'
            BridgeState.cardNameByInstanceId[':B'] = 'Harmonized Trio'
            local cardA = BridgeTestCreateCard(':A', 'Island', 'loose-A')
            local cardB = BridgeTestCreateCard(':B', 'Harmonized Trio', 'loose-B')
            BridgeTestQueueExtractionCards({cardA, cardB})
            BridgeTestSetEventQueue(
                {sequence=66, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':A', cardName='Island', forgeSequence=501},
                {sequence=67, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':B', cardName='Harmonized Trio', forgeSequence=501}
            )
            local rawCommit = BridgeCommitEventMutationTransaction
            BridgeCommitEventMutationTransaction = function(tx)
                appliedBeforeCommit = BridgeState.lastAppliedEventSequence
                local ledgerBefore = BridgeZoneLedger('forge-player-1', 'graveyard')
                ledgerBeforeCommitCount = BridgeTestArrayLength(ledgerBefore or {})
                return rawCommit(tx)
            end
            BridgeProcessEventQueue()
            local ledger = BridgeZoneLedger('forge-player-1', 'graveyard')
            finalApplied = BridgeState.lastAppliedEventSequence
            ledgerCount = BridgeTestArrayLength(ledger or {})
            ledger1 = ledger[1]
            ledger2 = ledger[2]
            containerTag = bridgeTest.graveyardContainer and bridgeTest.graveyardContainer.tag or 'nil'
            looseCount = BridgeTestLooseGraveyardCardCount()
            stageBeginCount = BridgeTestCountLogToken('MUTATION_STAGE_BEGIN')
            extractedCount = BridgeTestCountLogToken('MUTATION_STAGE_EXTRACTED')
            destinationCommitCount = BridgeTestCountLogToken('MUTATION_DESTINATION_COMMIT_BEGIN')
            destinationSampleCount = BridgeTestCountLogToken('MUTATION_DESTINATION_SETTLEMENT_SAMPLE')
            destinationVerifiedCount = BridgeTestCountLogToken('MUTATION_DESTINATION_VERIFIED')
            mutationCommitCount = BridgeTestCountLogToken('MUTATION_COMMIT')
            mutationAbortCount = BridgeTestCountLogToken('MUTATION_ABORT')
            debugDesync = tostring(desyncReason)
            debugQueueLength = #(BridgeState.eventQueue or {})
            debugTxState = BridgeState.eventDrainTransaction and tostring(BridgeState.eventDrainTransaction.state) or 'nil'
        ");

        Assert.True(lua.Globals.Get("appliedBeforeCommit").Number == 65,
            $"appliedBeforeCommit={lua.Globals.Get("appliedBeforeCommit").Number} finalApplied={lua.Globals.Get("finalApplied").Number} stageBegin={lua.Globals.Get("stageBeginCount").Number} extracted={lua.Globals.Get("extractedCount").Number} destCommit={lua.Globals.Get("destinationCommitCount").Number} destVerified={lua.Globals.Get("destinationVerifiedCount").Number} mutationCommit={lua.Globals.Get("mutationCommitCount").Number} mutationAbort={lua.Globals.Get("mutationAbortCount").Number} desync={lua.Globals.Get("debugDesync").String} queueLength={lua.Globals.Get("debugQueueLength").Number} txState={lua.Globals.Get("debugTxState").String} logs={CapturedLogsTail(lua)}");
        Assert.Equal(0, lua.Globals.Get("ledgerBeforeCommitCount").Number);
        Assert.Equal(67, lua.Globals.Get("finalApplied").Number);
        Assert.Equal("Deck", lua.Globals.Get("containerTag").String);
        Assert.Equal(0, lua.Globals.Get("looseCount").Number);
        Assert.Equal(2, lua.Globals.Get("ledgerCount").Number);
        Assert.Equal(":A", lua.Globals.Get("ledger1").String);
        Assert.Equal(":B", lua.Globals.Get("ledger2").String);
        Assert.Equal(1, lua.Globals.Get("stageBeginCount").Number);
        Assert.Equal(2, lua.Globals.Get("extractedCount").Number);
        Assert.Equal(1, lua.Globals.Get("destinationCommitCount").Number);
        Assert.True(lua.Globals.Get("destinationSampleCount").Number >= 1);
        Assert.Equal(1, lua.Globals.Get("destinationVerifiedCount").Number);
        Assert.Equal(1, lua.Globals.Get("mutationCommitCount").Number);
        Assert.Equal(0, lua.Globals.Get("mutationAbortCount").Number);
    }

    [Fact]
    public void MentalNoteSecondCardPromotionFailureAbortsWholeMutation()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            BridgeState.lastAppliedEventSequence = 65
            BridgeState.cardNameByInstanceId[':A'] = 'Island'
            BridgeState.cardNameByInstanceId[':B'] = 'Harmonized Trio'
            local cardA = BridgeTestCreateCard(':A', 'Island', 'loose-A')
            local cardB = BridgeTestCreateCard(':B', 'Harmonized Trio', 'loose-B')
            BridgeTestQueueExtractionCards({cardA, cardB})
            bridgeTest.forceUnstableSettlement = true
            BridgeTestSetEventQueue(
                {sequence=66, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':A', cardName='Island', forgeSequence=502},
                {sequence=67, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':B', cardName='Harmonized Trio', forgeSequence=502}
            )
            BridgeProcessEventQueue()
            local ledger = BridgeZoneLedger('forge-player-1', 'graveyard')
            finalApplied = BridgeState.lastAppliedEventSequence
            ledgerCount = BridgeTestArrayLength(ledger or {})
            desyncLatched = BridgeState.desyncLatched == true
            txAfter = BridgeState.eventDrainTransaction
            mutationAbortCount = BridgeTestCountLogToken('MUTATION_ABORT')
            mutationCommitCount = BridgeTestCountLogToken('MUTATION_COMMIT')
            settlementSampleCount = BridgeTestCountLogToken('MUTATION_DESTINATION_SETTLEMENT_SAMPLE')
            debugDesync = tostring(desyncReason)
        ");

        Assert.True(lua.Globals.Get("finalApplied").Number == 65,
            $"finalApplied={lua.Globals.Get("finalApplied").Number} ledgerCount={lua.Globals.Get("ledgerCount").Number} desyncLatched={lua.Globals.Get("desyncLatched").Boolean} txAfterType={lua.Globals.Get("txAfter").Type} mutationAbort={lua.Globals.Get("mutationAbortCount").Number} mutationCommit={lua.Globals.Get("mutationCommitCount").Number} settlementSamples={lua.Globals.Get("settlementSampleCount").Number} desync={lua.Globals.Get("debugDesync").String} logs={CapturedLogsTail(lua)}");
        Assert.Equal(0, lua.Globals.Get("ledgerCount").Number);
        Assert.True(lua.Globals.Get("desyncLatched").Boolean);
        Assert.True(lua.Globals.Get("txAfter").IsNil());
        Assert.True(lua.Globals.Get("mutationAbortCount").Number >= 1);
    }

    [Fact]
    public void SupplierThreeCardMillCommitsAsOneMutation()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            BridgeState.lastAppliedEventSequence = 27
            BridgeState.cardNameByInstanceId[':19'] = 'Stitcher\'s Supplier'
            BridgeState.cardNameByInstanceId[':1'] = 'Island'
            BridgeState.cardNameByInstanceId[':35'] = 'Plains'
            local c1 = BridgeTestCreateCard(':19', 'Stitcher\'s Supplier', 'loose-19')
            local c2 = BridgeTestCreateCard(':1', 'Island', 'loose-1')
            local c3 = BridgeTestCreateCard(':35', 'Plains', 'loose-35')
            BridgeTestQueueExtractionCards({c1, c2, c3})
            BridgeTestSetEventQueue(
                {sequence=28, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':19', cardName='Stitcher\'s Supplier', forgeSequence=700},
                {sequence=29, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':1', cardName='Island', forgeSequence=700},
                {sequence=30, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':35', cardName='Plains', forgeSequence=700}
            )
            local rawCommit = BridgeCommitEventMutationTransaction
            BridgeCommitEventMutationTransaction = function(tx)
                appliedBeforeCommit = BridgeState.lastAppliedEventSequence
                return rawCommit(tx)
            end
            BridgeProcessEventQueue()
            local ledger = BridgeZoneLedger('forge-player-1', 'graveyard')
            finalApplied = BridgeState.lastAppliedEventSequence
            ledgerCount = BridgeTestArrayLength(ledger or {})
            ledger1 = ledger[1]
            ledger2 = ledger[2]
            ledger3 = ledger[3]
            destinationCommitCount = BridgeTestCountLogToken('MUTATION_DESTINATION_COMMIT_BEGIN')
            extractedCount = BridgeTestCountLogToken('MUTATION_STAGE_EXTRACTED')
        ");

        Assert.Equal(27, lua.Globals.Get("appliedBeforeCommit").Number);
        Assert.Equal(30, lua.Globals.Get("finalApplied").Number);
        Assert.Equal(3, lua.Globals.Get("ledgerCount").Number);
        Assert.Equal(":19", lua.Globals.Get("ledger1").String);
        Assert.Equal(":1", lua.Globals.Get("ledger2").String);
        Assert.Equal(":35", lua.Globals.Get("ledger3").String);
        Assert.Equal(1, lua.Globals.Get("destinationCommitCount").Number);
        Assert.Equal(3, lua.Globals.Get("extractedCount").Number);
    }

    [Fact]
    public void ArmoredSkaabFourCardMillCommitsAsOneMutation()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            BridgeState.lastAppliedEventSequence = 120
            BridgeState.cardNameByInstanceId[':10'] = 'Card 10'
            BridgeState.cardNameByInstanceId[':11'] = 'Card 11'
            BridgeState.cardNameByInstanceId[':12'] = 'Card 12'
            BridgeState.cardNameByInstanceId[':13'] = 'Card 13'
            local c1 = BridgeTestCreateCard(':10', 'Card 10', 'loose-10')
            local c2 = BridgeTestCreateCard(':11', 'Card 11', 'loose-11')
            local c3 = BridgeTestCreateCard(':12', 'Card 12', 'loose-12')
            local c4 = BridgeTestCreateCard(':13', 'Card 13', 'loose-13')
            BridgeTestQueueExtractionCards({c1, c2, c3, c4})
            BridgeTestSetEventQueue(
                {sequence=121, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':10', cardName='Card 10', forgeSequence=701},
                {sequence=122, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':11', cardName='Card 11', forgeSequence=701},
                {sequence=123, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':12', cardName='Card 12', forgeSequence=701},
                {sequence=124, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':13', cardName='Card 13', forgeSequence=701}
            )
            BridgeProcessEventQueue()
            local ledger = BridgeZoneLedger('forge-player-1', 'graveyard')
            finalApplied = BridgeState.lastAppliedEventSequence
            ledgerCount = BridgeTestArrayLength(ledger or {})
            destinationCommitCount = BridgeTestCountLogToken('MUTATION_DESTINATION_COMMIT_BEGIN')
        ");

        Assert.Equal(124, lua.Globals.Get("finalApplied").Number);
        Assert.Equal(4, lua.Globals.Get("ledgerCount").Number);
        Assert.Equal(1, lua.Globals.Get("destinationCommitCount").Number);
    }

    [Fact]
    public void ExistingDeckPlusIncomingBatchProducesOneExactLedger()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            BridgeState.lastAppliedEventSequence = 200
            BridgeState.cardNameByInstanceId[':old1'] = 'Old One'
            BridgeState.cardNameByInstanceId[':old2'] = 'Old Two'
            BridgeState.cardNameByInstanceId[':new1'] = 'New One'
            BridgeState.cardNameByInstanceId[':new2'] = 'New Two'
            BridgeTestSeedExistingDeck(
                {instanceId=':old1', cardName='Old One'},
                {instanceId=':old2', cardName='Old Two'}
            )
            local ledger = BridgeZoneLedger('forge-player-1', 'graveyard')
            ledger[1] = ':old1'
            ledger[2] = ':old2'
            local c1 = BridgeTestCreateCard(':new1', 'New One', 'loose-new1')
            local c2 = BridgeTestCreateCard(':new2', 'New Two', 'loose-new2')
            BridgeTestQueueExtractionCards({c1, c2})
            BridgeTestSetEventQueue(
                {sequence=201, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':new1', cardName='New One', forgeSequence=702},
                {sequence=202, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':new2', cardName='New Two', forgeSequence=702}
            )
            BridgeProcessEventQueue()
            local finalLedger = BridgeZoneLedger('forge-player-1', 'graveyard')
            finalApplied = BridgeState.lastAppliedEventSequence
            finalCount = BridgeTestArrayLength(finalLedger or {})
            final1 = finalLedger[1]
            final2 = finalLedger[2]
            final3 = finalLedger[3]
            final4 = finalLedger[4]
            containerTag = bridgeTest.graveyardContainer and bridgeTest.graveyardContainer.tag or 'nil'
        ");

        Assert.Equal(202, lua.Globals.Get("finalApplied").Number);
        Assert.Equal(4, lua.Globals.Get("finalCount").Number);
        Assert.Equal(":old1", lua.Globals.Get("final1").String);
        Assert.Equal(":old2", lua.Globals.Get("final2").String);
        Assert.Equal(":new1", lua.Globals.Get("final3").String);
        Assert.Equal(":new2", lua.Globals.Get("final4").String);
        Assert.Equal("Deck", lua.Globals.Get("containerTag").String);
    }

    [Fact]
    public void ContainedGuidReassignmentKeepsExactForgeIdentity()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            BridgeState.lastAppliedEventSequence = 300
            BridgeState.cardNameByInstanceId[':old'] = 'Old'
            BridgeState.cardNameByInstanceId[':new1'] = 'Forest'
            BridgeState.cardNameByInstanceId[':new2'] = 'Plains'
            BridgeTestSeedExistingDeck(
                {instanceId=':old', cardName='Old'}
            )
            local ledger = BridgeZoneLedger('forge-player-1', 'graveyard')
            ledger[1] = ':old'
            local seedMapping = BridgeState.physicalContainerByInstanceId[':old']
            seedMappingExists = seedMapping ~= nil
            oldContainedGuid = seedMapping and seedMapping.cardGuid or nil
            seedLoopCount = bridgeTest.seedLoopCount or 0
            seedMappedCount = bridgeTest.seedMappedCount or 0
            seedFallbackCount = bridgeTest.seedFallbackCount or 0
            local c1 = BridgeTestCreateCard(':new1', 'Forest', 'loose-new1')
            local c2 = BridgeTestCreateCard(':new2', 'Plains', 'loose-new2')
            BridgeTestQueueExtractionCards({c1, c2})
            BridgeTestSetEventQueue(
                {sequence=301, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':new1', cardName='Forest', forgeSequence=703},
                {sequence=302, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':new2', cardName='Plains', forgeSequence=703}
            )
            BridgeProcessEventQueue()
            local oldMapping = BridgeState.physicalContainerByInstanceId[':old']
            local new1Mapping = BridgeState.physicalContainerByInstanceId[':new1']
            local new2Mapping = BridgeState.physicalContainerByInstanceId[':new2']
            reassignedOldGuid = oldMapping and oldMapping.cardGuid or nil
            guidChanged = oldContainedGuid ~= reassignedOldGuid
            containedReassignCount = bridgeTest.containedReassignCount
            uniqueGuids = {}
            uniqueCount = 0
            for guid, instanceId in pairs(BridgeState.physicalContainedInstanceIdByGuid or {}) do
                if instanceId == ':old' or instanceId == ':new1' or instanceId == ':new2' then
                    if uniqueGuids[guid] == nil then
                        uniqueGuids[guid] = true
                        uniqueCount = uniqueCount + 1
                    end
                end
            end
        ");

        Assert.True(lua.Globals.Get("seedMappingExists").Boolean,
            $"seedMappingExists={lua.Globals.Get("seedMappingExists").Boolean} oldContainedGuid={lua.Globals.Get("oldContainedGuid").ToPrintString()} seedLoopCount={lua.Globals.Get("seedLoopCount").Number} seedMappedCount={lua.Globals.Get("seedMappedCount").Number} seedFallbackCount={lua.Globals.Get("seedFallbackCount").Number} logs={CapturedLogsTail(lua)}");
        Assert.True(lua.Globals.Get("guidChanged").Boolean);
        Assert.True(lua.Globals.Get("containedReassignCount").Number >= 1);
        Assert.True(lua.Globals.Get("uniqueCount").Number == 3,
            $"uniqueCount={lua.Globals.Get("uniqueCount").Number} old={lua.Globals.Get("reassignedOldGuid").ToPrintString()} new1={lua.Globals.Get("new1Mapping").ToPrintString()} new2={lua.Globals.Get("new2Mapping").ToPrintString()} logs={CapturedLogsTail(lua)}");
    }

    [Fact]
    public void DuplicatePrintedNamesRemainExactByForgeInstanceId()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            BridgeState.lastAppliedEventSequence = 410
            BridgeState.cardNameByInstanceId[':f1'] = 'Forest'
            BridgeState.cardNameByInstanceId[':f2'] = 'Forest'
            local f1 = BridgeTestCreateCard(':f1', 'Forest', 'loose-f1')
            local f2 = BridgeTestCreateCard(':f2', 'Forest', 'loose-f2')
            BridgeTestQueueExtractionCards({f1, f2})
            BridgeTestSetEventQueue(
                {sequence=411, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':f1', cardName='Forest', forgeSequence=704},
                {sequence=412, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':f2', cardName='Forest', forgeSequence=704}
            )
            BridgeProcessEventQueue()
            finalApplied = BridgeState.lastAppliedEventSequence
            desyncState = tostring(desyncReason)
            deckEntryCount = BridgeTestArrayLength(bridgeTest.graveyardDeck.entries or {})
            deckEntry0 = bridgeTest.graveyardDeck.entries and bridgeTest.graveyardDeck.entries[0] ~= nil
            deckEntry1 = bridgeTest.graveyardDeck.entries and bridgeTest.graveyardDeck.entries[1] ~= nil
            deckEntry2 = bridgeTest.graveyardDeck.entries and bridgeTest.graveyardDeck.entries[2] ~= nil
            deckEntryStr0 = bridgeTest.graveyardDeck.entries and bridgeTest.graveyardDeck.entries['0'] ~= nil
            deckEntryStr1 = bridgeTest.graveyardDeck.entries and bridgeTest.graveyardDeck.entries['1'] ~= nil
            deckEntryStr2 = bridgeTest.graveyardDeck.entries and bridgeTest.graveyardDeck.entries['2'] ~= nil
            emittedByGetObjects = bridgeTest.lastGetObjectsEmitCount or -1
            deckObjectsCount = BridgeTestArrayLength(bridgeTest.graveyardDeck.getObjects() or {})
            local m1 = BridgeState.physicalContainerByInstanceId[':f1']
            local m2 = BridgeState.physicalContainerByInstanceId[':f2']
            guid1 = m1 and m1.cardGuid or nil
            guid2 = m2 and m2.cardGuid or nil
            sameGuid = guid1 ~= nil and guid1 == guid2
            verified1, verifyErr1 = BridgeVerifyFinalPhysicalRepresentation(':f1', 'forge-player-1', 'graveyard')
            verified2, verifyErr2 = BridgeVerifyFinalPhysicalRepresentation(':f2', 'forge-player-1', 'graveyard')
        ");

        Assert.False(lua.Globals.Get("sameGuid").Boolean);
        Assert.True(lua.Globals.Get("verified1").Boolean,
            $"verifyErr1={lua.Globals.Get("verifyErr1").ToPrintString()} verifyErr2={lua.Globals.Get("verifyErr2").ToPrintString()} finalApplied={lua.Globals.Get("finalApplied").Number} desync={lua.Globals.Get("desyncState").String} deckEntryCount={lua.Globals.Get("deckEntryCount").Number} deckObjectsCount={lua.Globals.Get("deckObjectsCount").Number} emittedByGetObjects={lua.Globals.Get("emittedByGetObjects").Number} entry0={lua.Globals.Get("deckEntry0").Boolean} entry1={lua.Globals.Get("deckEntry1").Boolean} entry2={lua.Globals.Get("deckEntry2").Boolean} str0={lua.Globals.Get("deckEntryStr0").Boolean} str1={lua.Globals.Get("deckEntryStr1").Boolean} str2={lua.Globals.Get("deckEntryStr2").Boolean} logs={CapturedLogsTail(lua)}");
        Assert.True(lua.Globals.Get("verified2").Boolean,
            $"verifyErr1={lua.Globals.Get("verifyErr1").ToPrintString()} verifyErr2={lua.Globals.Get("verifyErr2").ToPrintString()} finalApplied={lua.Globals.Get("finalApplied").Number} desync={lua.Globals.Get("desyncState").String} deckEntryCount={lua.Globals.Get("deckEntryCount").Number} deckObjectsCount={lua.Globals.Get("deckObjectsCount").Number} emittedByGetObjects={lua.Globals.Get("emittedByGetObjects").Number} entry0={lua.Globals.Get("deckEntry0").Boolean} entry1={lua.Globals.Get("deckEntry1").Boolean} entry2={lua.Globals.Get("deckEntry2").Boolean} str0={lua.Globals.Get("deckEntryStr0").Boolean} str1={lua.Globals.Get("deckEntryStr1").Boolean} str2={lua.Globals.Get("deckEntryStr2").Boolean} logs={CapturedLogsTail(lua)}");
    }

    [Fact]
    public void StaleCallbackAfterAbortCannotMutateCommittedState()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            BridgeState.lastAppliedEventSequence = 500
            BridgeState.cardNameByInstanceId[':a'] = 'Card A'
            BridgeState.cardNameByInstanceId[':b'] = 'Card B'
            local a = BridgeTestCreateCard(':a', 'Card A', 'loose-a')
            local b = BridgeTestCreateCard(':b', 'Card B', 'loose-b')
            BridgeTestQueueExtractionCards({a, b})
            BridgeTestDelayTake(2)
            BridgeWaitFrames = function(callback, frames)
                return
            end
            local rawCommit = BridgeCommitEventMutationTransaction
            BridgeCommitEventMutationTransaction = function(tx)
                commitCalls = (commitCalls or 0) + 1
                return rawCommit(tx)
            end
            BridgeTestSetEventQueue(
                {sequence=501, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':a', cardName='Card A', forgeSequence=705},
                {sequence=502, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':b', cardName='Card B', forgeSequence=705}
            )
            BridgeProcessEventQueue()
            local ledgerBefore = BridgeZoneLedger('forge-player-1', 'graveyard')
            appliedBeforeAbort = BridgeState.lastAppliedEventSequence
            ledgerBeforeAbortCount = BridgeTestArrayLength(ledgerBefore or {})
            txBeforeAbort = BridgeState.eventDrainTransaction
            BridgeAbortEventMutationTransaction(BridgeState.eventDrainTransaction, 'forced-abort-for-test')
            BridgeState.physicalTransactionGeneration = (BridgeState.physicalTransactionGeneration or 0) + 1
            BridgeTestFlushDelayedTake(2)
            local ledgerAfter = BridgeZoneLedger('forge-player-1', 'graveyard')
            appliedAfterFlush = BridgeState.lastAppliedEventSequence
            ledgerAfterFlushCount = BridgeTestArrayLength(ledgerAfter or {})
            txAfterFlush = BridgeState.eventDrainTransaction
            commitCalls = commitCalls or 0
            desyncState = tostring(desyncReason)
        ");

        Assert.Equal(500, lua.Globals.Get("appliedBeforeAbort").Number);
        Assert.Equal(0, lua.Globals.Get("ledgerBeforeAbortCount").Number);
        Assert.Equal(500, lua.Globals.Get("appliedAfterFlush").Number);
        Assert.Equal(0, lua.Globals.Get("ledgerAfterFlushCount").Number);
        Assert.True(lua.Globals.Get("txAfterFlush").IsNil());
        Assert.Equal(0, lua.Globals.Get("commitCalls").Number);
        Assert.True(lua.Globals.Get("txBeforeAbort").Type == DataType.Table,
            $"txBeforeAbortType={lua.Globals.Get("txBeforeAbort").Type} appliedBeforeAbort={lua.Globals.Get("appliedBeforeAbort").Number} appliedAfterFlush={lua.Globals.Get("appliedAfterFlush").Number} desync={lua.Globals.Get("desyncState").String} logs={CapturedLogsTail(lua)}");
    }

    [Fact]
    public void HeterogeneousSameForgeMutationDefersCursorCommitUntilMillAndDrawSettle()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            BridgeState.lastAppliedEventSequence = 600
            BridgeState.cardNameByInstanceId[':m1'] = 'Mill A'
            BridgeState.cardNameByInstanceId[':m2'] = 'Mill B'
            BridgeState.cardNameByInstanceId[':d1'] = 'Draw C'
            local m1 = BridgeTestCreateCard(':m1', 'Mill A', 'loose-m1')
            local m2 = BridgeTestCreateCard(':m2', 'Mill B', 'loose-m2')
            local d1 = BridgeTestCreateCard(':d1', 'Draw C', 'loose-d1')
            BridgeTestQueueExtractionCards({m1, m2, d1})
            drawSeenInHand = false
            local rawTryGetSeatHandObjects = BridgeTryGetSeatHandObjects
            BridgeTryGetSeatHandObjects = function(seatId)
                local handObjects, handError = rawTryGetSeatHandObjects(seatId)
                if handObjects ~= nil then
                    bridgeTest.handProbeCount = (bridgeTest.handProbeCount or 0) + 1
                    local first = handObjects[1]
                    bridgeTest.handProbeFirstInstance = first and first._instanceId or 'nil'
                    bridgeTest.handProbeFirstGuid = first and BridgeSafeObjectGuid(first) or 'nil'
                    for _, handObject in ipairs(handObjects) do
                        local handGuid = handObject and BridgeSafeObjectGuid(handObject) or nil
                        if handObject ~= nil and (handObject._instanceId == ':d1' or tostring(handGuid or '') == 'loose-d1') then
                            drawSeenInHand = true
                            break
                        end
                    end
                end
                return handObjects, handError
            end
            local rawCommit = BridgeCommitEventMutationTransaction
            BridgeCommitEventMutationTransaction = function(tx)
                commitEnterCount = (commitEnterCount or 0) + 1
                commitSawDrawInHand = drawSeenInHand
                BridgeLog('[Bridge][Test] HETERO_COMMIT_WRAPPER_ENTER token=' .. tostring(tx and tx.token))
                return rawCommit(tx)
            end
            BridgeTestSetEventQueue(
                {sequence=601, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':m1', cardName='Mill A', forgeSequence=706},
                {sequence=602, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':m2', cardName='Mill B', forgeSequence=706},
                {sequence=603, kind='draw', seatId='forge-player-1', sourceZone='library', destinationZone='hand', cardInstanceId=':d1', cardName='Draw C', forgeSequence=706}
            )
            queueLenBefore = #(BridgeState.eventQueue or {})
            queueHeadBefore = BridgeState.eventQueue[1] and BridgeState.eventQueue[1].sequence or nil
            queueZeroBefore = BridgeState.eventQueue[0] and BridgeState.eventQueue[0].sequence or nil
            BridgeProcessEventQueue()
            local graveyardLedger = BridgeZoneLedger('forge-player-1', 'graveyard')
            finalApplied = BridgeState.lastAppliedEventSequence
            graveyardCount = BridgeTestArrayLength(graveyardLedger or {})
            handGuid = BridgeState.physicalByInstanceId[':d1']
            handZone = handGuid and BridgeState.physicalZoneByGuid[handGuid] or nil
            handSeat = handGuid and BridgeState.physicalSeatByGuid[handGuid] or nil
            lastHandCount = bridgeTest.lastHandCount or -1
            lastHandFirstGuid = bridgeTest.lastHandFirstGuid or 'nil'
            lastHandFirstRawGuid = bridgeTest.lastHandFirstRawGuid or 'nil'
            handProbeCount = bridgeTest.handProbeCount or 0
            handProbeFirstInstance = bridgeTest.handProbeFirstInstance or 'nil'
            handProbeFirstGuid = bridgeTest.handProbeFirstGuid or 'nil'
            deckEntryCount = BridgeTestArrayLength(bridgeTest.graveyardDeck.entries)
            deckEntryFirst = bridgeTest.graveyardDeck.entries[1] and bridgeTest.graveyardDeck.entries[1].instanceId or 'nil'
            resyncFailureReason = tostring(BridgeState.resyncLastFailureReason)
            desyncLastMessage = tostring(BridgeState.desyncLastMessage)
            resyncBlockingPredicate = tostring(BridgeState.resyncLastBlockingPredicate)
            desyncState = tostring(desyncReason)
            commitEnterCount = commitEnterCount or 0
        ");

        Assert.True(lua.Globals.Get("commitSawDrawInHand").Boolean,
            $"queueLenBefore={lua.Globals.Get("queueLenBefore").ToPrintString()} queueHeadBefore={lua.Globals.Get("queueHeadBefore").ToPrintString()} queueZeroBefore={lua.Globals.Get("queueZeroBefore").ToPrintString()} commitEnterCount={lua.Globals.Get("commitEnterCount").Number} commitSawDrawInHand={lua.Globals.Get("commitSawDrawInHand").Boolean} drawSeenInHand={lua.Globals.Get("drawSeenInHand").Boolean} finalApplied={lua.Globals.Get("finalApplied").Number} graveyardCount={lua.Globals.Get("graveyardCount").Number} deckEntryCount={lua.Globals.Get("deckEntryCount").Number} deckEntryFirst={lua.Globals.Get("deckEntryFirst").ToPrintString()} handGuid={lua.Globals.Get("handGuid").ToPrintString()} handZone={lua.Globals.Get("handZone").ToPrintString()} handSeat={lua.Globals.Get("handSeat").ToPrintString()} lastHandCount={lua.Globals.Get("lastHandCount").Number} lastHandFirstGuid={lua.Globals.Get("lastHandFirstGuid").ToPrintString()} lastHandFirstRawGuid={lua.Globals.Get("lastHandFirstRawGuid").ToPrintString()} handProbeCount={lua.Globals.Get("handProbeCount").Number} handProbeFirstInstance={lua.Globals.Get("handProbeFirstInstance").ToPrintString()} handProbeFirstGuid={lua.Globals.Get("handProbeFirstGuid").ToPrintString()} desync={lua.Globals.Get("desyncState").String} desyncLastMessage={lua.Globals.Get("desyncLastMessage").ToPrintString()} resyncFailureReason={lua.Globals.Get("resyncFailureReason").ToPrintString()} blockingPredicate={lua.Globals.Get("resyncBlockingPredicate").ToPrintString()} logs={CapturedLogsTail(lua)}");
        Assert.Equal(603, lua.Globals.Get("finalApplied").Number);
        Assert.Equal(2, lua.Globals.Get("graveyardCount").Number);
        Assert.Equal("hand", lua.Globals.Get("handZone").String);
        Assert.Equal("forge-player-1", lua.Globals.Get("handSeat").String);
    }

    private static Script NewProbe()
    {
        var lua = new Script();
        ExecuteProbe(lua, @"
            capturedLogs = {}
            function log(message)
                table.insert(capturedLogs, tostring(message or ''))
            end
            function broadcastToAll(message, color) end
            function printToAll(message, color) end
            function getObjectFromGUID(guid) return nil end
            function getAllObjects() return {} end
            function Wait(frames) end
            Time = { waitForSeconds = function(seconds, callback) callback() end }
            JSON = { encode = function(value) return '{}' end, decode = function(value) return {} end }
            os = { time = function() return 1 end, clock = function() return 0 end }
            math.randomseed(1)
            local function bridgeArrayLength(values)
                local count = 0
                while values[count + 1] ~= nil do
                    count = count + 1
                end
                return count
            end
            function BridgeTestArrayLength(values)
                return bridgeArrayLength(values)
            end
            local rawTableInsert = table.insert
            _bridgeNativeTableInsert = rawTableInsert
            table.insert = function(values, indexOrValue, optionalValue)
                if type(values) ~= 'table' then
                    return rawTableInsert(values, indexOrValue, optionalValue)
                end
                local length = bridgeArrayLength(values)
                if optionalValue == nil then
                    values[length + 1] = indexOrValue
                    return
                end
                local insertIndex = tonumber(indexOrValue) or (length + 1)
                if insertIndex < 1 then insertIndex = 1 end
                if insertIndex > (length + 1) then insertIndex = length + 1 end
                for index = length + 1, insertIndex + 1, -1 do
                    values[index] = values[index - 1]
                end
                values[insertIndex] = optionalValue
            end
            local rawIpairs = ipairs
            ipairs = function(values)
                if type(values) ~= 'table' then
                    return rawIpairs(values)
                end
                local index = 0
                return function(state, last)
                    index = index + 1
                    local value = state[index]
                    if value ~= nil then
                        return index, value
                    end
                    return nil
                end, values, 0
            end
            local rawTableConcat = table.concat
            table.concat = function(values, separator, startIndex, endIndex)
                separator = separator or ''
                if type(values) ~= 'table' then
                    return rawTableConcat(values, separator, startIndex, endIndex)
                end
                local lower = tonumber(startIndex) or 1
                local upper = tonumber(endIndex)
                if upper == nil then
                    upper = 0
                    for key, _ in pairs(values) do
                        if type(key) == 'number' and key > upper then
                            upper = key
                        end
                    end
                end
                local parts = {}
                local writeIndex = 1
                for index = lower, upper do
                    local value = values[index]
                    if value ~= nil then
                        parts[writeIndex] = tostring(value)
                        writeIndex = writeIndex + 1
                    end
                end
                return rawTableConcat(parts, separator)
            end
            _bridgeRawTableInsert = table.insert
        ");
        ExecuteProbe(lua, Script);
        ExecuteProbe(lua, @"
            function BridgeCountByPredicate(source, predicate)
                local count = 0
                for _, value in ipairs(source or {}) do
                    if predicate(value) then count = count + 1 end
                end
                return count
            end

            function BridgeTestCountLogToken(token)
                local count = 0
                for _, line in pairs(capturedLogs or {}) do
                    if string.find(line, token, 1, true) ~= nil then
                        count = count + 1
                    end
                end
                return count
            end

            function BridgeTestNormalizeSequence(values)
                local ordered = {}
                local consumed = {}
                while true do
                    local nextKey = nil
                    local nextNumeric = nil
                    for key, value in pairs(values or {}) do
                        local numericKey = tonumber(key)
                        if numericKey ~= nil and value ~= nil and consumed[tostring(key)] ~= true then
                            if nextNumeric == nil or numericKey < nextNumeric then
                                nextKey = key
                                nextNumeric = numericKey
                            end
                        end
                    end
                    if nextKey == nil then break end
                    consumed[tostring(nextKey)] = true
                    ordered[BridgeTestArrayLength(ordered) + 1] = values[nextKey]
                end
                setmetatable(ordered, { __len = function(values) return BridgeTestArrayLength(values) end })
                return ordered
            end

            local rawBridgeLibraryEntries = BridgeLibraryEntries
            BridgeLibraryEntries = function(deck)
                local entries = rawBridgeLibraryEntries and rawBridgeLibraryEntries(deck) or nil
                if entries == nil then return nil end
                if deck == bridgeTest.graveyardDeck and BridgeTestArrayLength(entries) == 0 then
                    local simulated = {}
                    bridgeTest.forEachArrayEntry(bridgeTest.graveyardDeck.entries, function(entry)
                        simulated[BridgeTestArrayLength(simulated) + 1] = {
                            guid = entry.guid,
                            nickname = entry.name,
                            index = BridgeTestArrayLength(simulated) + 1
                        }
                    end)
                    entries = simulated
                end
                return BridgeTestNormalizeSequence(entries)
            end

            local rawBridgeBuildAtomicLibraryToGraveyardBatches = BridgeBuildAtomicLibraryToGraveyardBatches
            BridgeBuildAtomicLibraryToGraveyardBatches = function(tx)
                if rawBridgeBuildAtomicLibraryToGraveyardBatches ~= nil then
                    rawBridgeBuildAtomicLibraryToGraveyardBatches(tx)
                end
                if tx == nil or tx.graveyardMutationBatchesBySeatId == nil then return end
                for seatId, batch in pairs(tx.graveyardMutationBatchesBySeatId) do
                    if batch ~= nil and (tonumber(batch.requiredCount) or 0) >= 2 then
                        local stagedLedger = {}
                        local committed = BridgeZoneLedger(seatId, 'graveyard')
                        for _, instanceId in pairs(BridgeTestNormalizeSequence(committed or {})) do
                            table.insert(stagedLedger, instanceId)
                        end
                        for _, instanceId in pairs(BridgeTestNormalizeSequence(batch.incomingInstanceIds or {})) do
                            table.insert(stagedLedger, instanceId)
                        end
                        batch.stagedGraveyardLedger = stagedLedger
                        batch.expectedInstances = {}
                        for _, instanceId in pairs(stagedLedger) do
                            table.insert(batch.expectedInstances, {
                                instanceId = instanceId,
                                cardName = BridgeState.cardNameByInstanceId[instanceId]
                            })
                        end
                    end
                end
            end

            BridgeVerifyGraveyardDeckSettlement = function(deck, maxRetries, callback, sampleObserver)
                local finished = false
                local retryCount = 0
                local lastInventory = nil
                maxRetries = maxRetries or 5

                local function finish(ok, reason, inventory)
                    if finished then return end
                    finished = true
                    if callback ~= nil then callback(ok, reason, inventory) end
                end

                if not BridgeObjectIsUsable(deck) or deck.tag ~= 'Deck' then
                    finish(false, 'target is not a usable Deck')
                    return
                end

                local function checkStable()
                    if finished then return end
                    retryCount = retryCount + 1
                    local entries = BridgeLibraryEntries(deck)
                    if entries == nil then
                        finish(false, 'could not read Deck inventory at retry ' .. tostring(retryCount))
                        return
                    end

                    local inventory = {}
                    for _, entry in pairs(BridgeTestNormalizeSequence(entries)) do
                        local guid = entry and (entry.guid or entry.GUID) or nil
                        if guid == nil then
                            finish(false, 'Deck inventory contained an entry without a GUID')
                            return
                        end
                        table.insert(inventory, tostring(guid))
                    end

                    if sampleObserver ~= nil then
                        pcall(sampleObserver, retryCount, inventory, lastInventory, maxRetries)
                    end

                    local stable = lastInventory ~= nil and #lastInventory == #inventory
                    if stable then
                        for index = 1, #inventory do
                            if lastInventory[index] ~= inventory[index] then
                                stable = false
                                break
                            end
                        end
                    end

                    if stable then
                        finish(true, nil, inventory)
                        return
                    end

                    lastInventory = inventory
                    if retryCount >= maxRetries then
                        finish(false,
                            'contained GUID inventory did not stabilize after ' .. tostring(maxRetries) .. ' observations',
                            inventory)
                        return
                    end

                    BridgeWaitFrames(checkStable, 1)
                end

                checkStable()
            end

            BridgeFindContainedCardEntry = function(cardInstanceId, expectedZone)
                local mapping = BridgeState.physicalContainerByInstanceId
                    and BridgeState.physicalContainerByInstanceId[cardInstanceId] or nil
                if mapping == nil then return nil, nil, 'no contained mapping for card instance' end
                if expectedZone ~= nil and mapping.zoneName ~= nil and mapping.zoneName ~= expectedZone then
                    return nil, nil, 'contained mapping is in ' .. tostring(mapping.zoneName)
                end
                local deck = BridgeGetLiveObjectByGuid(mapping.deckGuid)
                if deck == nil or deck.tag ~= 'Deck' then
                    return nil, nil, 'containing Deck is unavailable'
                end
                local entries = {}
                local ok = pcall(function() entries = deck.getObjects() or {} end)
                if not ok then return nil, nil, 'containing Deck inventory is unavailable' end
                for _, entry in pairs(BridgeTestNormalizeSequence(entries)) do
                    local guid = entry and (entry.guid or entry.GUID) or nil
                    if tostring(guid or '') == tostring(mapping.cardGuid) then
                        mapping.index = entry.index
                        return deck, entry, nil
                    end
                end
                return nil, nil, 'contained card GUID is absent from its Deck'
            end

            function BridgeTestInitAtomicHarness()
                BRIDGE_SEATS['forge-player-1'] = BRIDGE_SEATS['forge-player-1'] or {}
                BRIDGE_SEATS['forge-player-1'].libraryZoneGuid = 'lib-zone'
                BRIDGE_SEATS['forge-player-1'].graveyardAnchor = {x=0, y=0, z=0}
                BRIDGE_SEATS['forge-player-1'].handTransform = {position={x=8, y=2, z=0}, rotation={x=0, y=0, z=0}}
                BRIDGE_SEATS['forge-player-1'].tableSideZ = -1

                bridgeTest = {
                    guidCounter = 0,
                    cardsByGuid = {},
                    allCards = {},
                    extractionCards = {},
                    extractionIndex = 0,
                    delayed = {},
                    delayTakeIndex = nil,
                    deckPutCount = 0,
                    promotePutCount = 0,
                    containedReassignCount = 0,
                    forceMissingDeckAfterPromotion = false,
                    forceUnstableSettlement = false,
                    reassignContainedEveryPut = true,
                    unstableReadCounter = 0,
                    graveyardContainer = nil
                }

                function bridgeTest.nextContainedGuid(instanceId)
                    bridgeTest.guidCounter = bridgeTest.guidCounter + 1
                    return 'contained-' .. tostring(bridgeTest.guidCounter) .. '-' .. tostring(instanceId or bridgeTest.guidCounter)
                end

                function bridgeTest.forEachArrayEntry(values, callback)
                    local seen = {}
                    local function emit(value)
                        if value ~= nil and seen[value] ~= true then
                            seen[value] = true
                            callback(value)
                        end
                    end
                    local max = (#(values or {}) + 16)
                    for index = 0, max do
                        local value = values and (values[index] or values[tostring(index)]) or nil
                        emit(value)
                    end
                    for index = 1, max do
                        local value = values and (values[index] or values[tostring(index)]) or nil
                        emit(value)
                    end
                    for _, value in pairs(values or {}) do
                        emit(value)
                    end
                end

                bridgeTest.libraryZone = {
                    tag = 'ScriptingZone',
                    getGUID = function() return 'lib-zone' end,
                    getPosition = function() return {x=0, y=2, z=0} end
                }
                bridgeTest.libraryDeck = {
                    tag = 'Deck',
                    getGUID = function() return 'library-deck' end,
                    getObjects = function() return {} end
                }
                bridgeTest.graveyardDeck = {
                    tag = 'Deck',
                    getGUID = function() return 'grave-deck' end,
                    entries = {}
                }
                bridgeTest.graveyardDeck.getObjects = function()
                    local out = {}
                    local outIndex = 1
                    bridgeTest.unstableReadCounter = bridgeTest.unstableReadCounter + 1
                    bridgeTest.forEachArrayEntry(bridgeTest.graveyardDeck.entries, function(entry)
                        local guid = tostring(entry.guid)
                        if bridgeTest.forceUnstableSettlement then
                            guid = guid .. '-unstable-' .. tostring(bridgeTest.unstableReadCounter)
                        end
                        out[outIndex] = {
                            guid = guid,
                            nickname = entry.name,
                            index = outIndex
                        }
                        outIndex = outIndex + 1
                    end)
                    bridgeTest.lastGetObjectsEmitCount = outIndex - 1
                    return out
                end

                function bridgeTest.reassignContainedGuids()
                    bridgeTest.containedReassignCount = bridgeTest.containedReassignCount + 1
                    bridgeTest.forEachArrayEntry(bridgeTest.graveyardDeck.entries, function(entry)
                        entry.guid = bridgeTest.nextContainedGuid(entry.instanceId)
                    end)
                end

                bridgeTest.graveyardDeck.putObject = function(object, position)
                    bridgeTest.deckPutCount = bridgeTest.deckPutCount + 1
                    local instanceId = object and object._instanceId or nil
                    local cardName = (instanceId and BridgeState.cardNameByInstanceId[instanceId])
                        or (object and object.name) or tostring(instanceId or 'unknown')
                    bridgeTest.graveyardDeck.entries[BridgeTestArrayLength(bridgeTest.graveyardDeck.entries) + 1] = {
                        instanceId = instanceId,
                        name = cardName,
                        guid = bridgeTest.nextContainedGuid(instanceId)
                    }
                    if object ~= nil then
                        object._inDeck = true
                        object._inLibrary = false
                        object._inHand = false
                    end
                    if bridgeTest.reassignContainedEveryPut then bridgeTest.reassignContainedGuids() end
                    bridgeTest.graveyardContainer = bridgeTest.graveyardDeck
                    return bridgeTest.graveyardDeck
                end

                function BridgeTestCreateCard(instanceId, cardName, guid)
                    local card = {
                        tag = 'Card',
                        name = cardName or tostring(instanceId),
                        _instanceId = instanceId,
                        _guid = guid or ('loose-' .. tostring(instanceId)),
                        _inDeck = false,
                        _inLibrary = true,
                        _inHand = false
                    }
                    card.getGUID = function() return card._guid end
                    card.getName = function() return card.name end
                    card.setPositionSmooth = function(position, smooth, collide)
                        card._lastPosition = position
                    end
                    card.setLock = function(value) card._locked = value end
                    card.setRotation = function(_) end
                    card.putObject = function(other, position)
                        bridgeTest.promotePutCount = bridgeTest.promotePutCount + 1
                        if bridgeTest.forceMissingDeckAfterPromotion then
                            bridgeTest.graveyardContainer = nil
                            return nil
                        end
                        if bridgeTest.graveyardContainer ~= bridgeTest.graveyardDeck then
                            bridgeTest.graveyardDeck.entries[BridgeTestArrayLength(bridgeTest.graveyardDeck.entries) + 1] = {
                                instanceId = card._instanceId,
                                name = BridgeState.cardNameByInstanceId[card._instanceId] or card.name,
                                guid = bridgeTest.nextContainedGuid(card._instanceId)
                            }
                            card._inDeck = true
                            card._inHand = false
                            bridgeTest.graveyardContainer = bridgeTest.graveyardDeck
                        end
                        if other ~= nil then other._inHand = false end
                        return bridgeTest.graveyardDeck.putObject(other, position)
                    end
                    bridgeTest.cardsByGuid[card._guid] = card
                    table.insert(bridgeTest.allCards, card)
                    return card
                end

                function BridgeTestSeedExistingDeck(...)
                    bridgeTest.graveyardDeck.entries = {}
                    bridgeTest.graveyardContainer = bridgeTest.graveyardDeck
                    BridgeState.physicalContainerByInstanceId = BridgeState.physicalContainerByInstanceId or {}
                    BridgeState.physicalContainedInstanceIdByGuid = BridgeState.physicalContainedInstanceIdByGuid or {}
                    BridgeState.physicalSeatByGuid = BridgeState.physicalSeatByGuid or {}
                    BridgeState.physicalZoneByGuid = BridgeState.physicalZoneByGuid or {}
                    BridgeState.cardNameByInstanceId = BridgeState.cardNameByInstanceId or {}
                    bridgeTest.seedLoopCount = 0
                    bridgeTest.seedMappedCount = 0
                    bridgeTest.seedFallbackCount = 0
                    local count = select('#', ...)
                    for index = 1, count do
                        local item = select(index, ...)
                        if item ~= nil then
                        bridgeTest.seedLoopCount = bridgeTest.seedLoopCount + 1
                        local guid = bridgeTest.nextContainedGuid(item.instanceId)
                        bridgeTest.graveyardDeck.entries[BridgeTestArrayLength(bridgeTest.graveyardDeck.entries) + 1] = {
                            instanceId = item.instanceId,
                            name = item.cardName,
                            guid = guid
                        }
                        local mapped = BridgeRecordContainedCardIdentity(item.instanceId,
                            bridgeTest.graveyardDeck.getGUID(), guid,
                            'forge-player-1', 'graveyard', item.cardName)
                        if mapped then
                            bridgeTest.seedMappedCount = bridgeTest.seedMappedCount + 1
                        else
                            bridgeTest.seedFallbackCount = bridgeTest.seedFallbackCount + 1
                            -- Seeded harness state models an already-authoritative native Deck.
                            -- Fall back to direct map seeding if runtime guards reject setup-time binding.
                            BridgeState.physicalContainerByInstanceId[item.instanceId] = {
                                deckGuid = bridgeTest.graveyardDeck.getGUID(),
                                cardGuid = guid,
                                seatId = 'forge-player-1',
                                zoneName = 'graveyard'
                            }
                            BridgeState.physicalContainedInstanceIdByGuid[guid] = item.instanceId
                            BridgeState.physicalSeatByGuid[guid] = 'forge-player-1'
                            BridgeState.physicalZoneByGuid[guid] = 'graveyard'
                            if item.cardName ~= nil and item.cardName ~= '' then
                                BridgeState.cardNameByInstanceId[item.instanceId] = item.cardName
                            end
                        end
                        end
                    end
                end

                function BridgeTestQueueExtractionCards(cards)
                    bridgeTest.extractionCards = {}
                    bridgeTest.extractionIndex = 0
                    bridgeTest.delayed = {}
                    bridgeTest.delayTakeIndex = nil
                    bridgeTest.forEachArrayEntry(cards or {}, function(card)
                        table.insert(bridgeTest.extractionCards, card)
                    end)
                    bridgeTest.forEachArrayEntry(bridgeTest.extractionCards, function(card)
                        if card ~= nil then
                            card._inLibrary = true
                            card._inDeck = false
                            card._inHand = false
                            card._extracted = false
                            card._lastPosition = nil
                        end
                    end)
                end

                function BridgeTestDelayTake(index)
                    bridgeTest.delayTakeIndex = index
                end

                function BridgeTestFlushDelayedTake(index)
                    local pending = bridgeTest.delayed[index]
                    if pending == nil then return false end
                    bridgeTest.delayed[index] = nil
                    if pending.card ~= nil then
                        pending.card._inLibrary = false
                        pending.card._inHand = pending.faceDown == true
                        pending.card._lastPosition = pending.position
                    end
                    pending.callback(pending.card, nil)
                    return true
                end

                function BridgeTestLooseGraveyardCardCount()
                    local count = 0
                    bridgeTest.forEachArrayEntry(bridgeTest.allCards or {}, function(card)
                        if card._inDeck ~= true and card._lastPosition ~= nil then
                            count = count + 1
                        end
                    end)
                    return count
                end

                function getObjectFromGUID(guid)
                    if guid == 'lib-zone' then return bridgeTest.libraryZone end
                    if guid == 'library-deck' then return bridgeTest.libraryDeck end
                    if guid == 'grave-deck' then return bridgeTest.graveyardDeck end
                    return bridgeTest.cardsByGuid[guid]
                end

                function getAllObjects()
                    local objects = {}
                    if bridgeTest.graveyardContainer ~= nil then
                        table.insert(objects, bridgeTest.graveyardContainer)
                    end
                    bridgeTest.forEachArrayEntry(bridgeTest.allCards or {}, function(card)
                        if card._inDeck ~= true and card._inLibrary ~= true and card._inHand ~= true then
                            table.insert(objects, card)
                        end
                    end)
                    return objects
                end

                function BridgeFindLibraryDeckForSeat(seatId)
                    return bridgeTest.libraryDeck
                end

                function BridgeResolveSeatLibraryDeck(seatId)
                    return bridgeTest.libraryDeck
                end

                function BridgeGetLiveObjectByGuid(guid)
                    return getObjectFromGUID(guid)
                end

                function BridgeTryGetSeatHandTransform(seatId)
                    return {position={x=8, y=2, z=0}, rotation={x=0, y=0, z=0}}, nil
                end

                function BridgeTryGetSeatHandObjects(seatId)
                    local hand = {}
                    local handCount = 0
                    bridgeTest.lastHandFirstGuid = nil
                    bridgeTest.lastHandFirstRawGuid = nil
                    bridgeTest.forEachArrayEntry(bridgeTest.allCards or {}, function(card)
                        if card._inDeck ~= true and card._inLibrary ~= true and card._inHand == true then
                            handCount = handCount + 1
                            -- MoonSharp's native table.insert does not expose
                            -- the same contiguous array to the harness ipairs
                            -- shim. TTS returns a dense hand-object array, so
                            -- model that contract with direct numeric writes.
                            hand[handCount] = card
                            if handCount == 1 then
                                bridgeTest.lastHandFirstGuid = BridgeSafeObjectGuid(card)
                                bridgeTest.lastHandFirstRawGuid = card._guid
                            end
                        end
                    end)
                    bridgeTest.lastHandCount = handCount
                    return hand
                end

                function BridgeRequireArtBearingLibraryCard(card, seatId, cardInstanceId)
                    return true
                end

                function BridgeFindGraveyardContainer(seatId, excludeGuid)
                    local container = bridgeTest.graveyardContainer
                    if container == nil then return nil end
                    local guid = container.getGUID and container.getGUID() or nil
                    if excludeGuid ~= nil and guid == excludeGuid then return nil end
                    return container
                end

                function BridgeAssertGraveyardObjectShape(seatId, context)
                    return true, nil
                end

                function BridgeStopOnDesync(reason)
                    desyncReason = tostring(reason)
                    BridgeState.desyncLatched = true
                    BridgeLog('[Bridge] DESYNC ' .. tostring(reason))
                end

                function BridgeTryApplyDeferredSnapshotReconcile(reason) end
                function BridgeTryStartPendingSnapshotReconcile(reason) end
                function BridgeTryPresentPendingDecision(reason) end
                function BridgeRefreshDecisionAfterStateTransition(reason) end
                function BridgeShouldReconcileAfterEvent(event) return false end
                function BridgeScheduleSnapshotReconcile(reason, category) end
                function BridgeSetPhysicalFaceDown(object, seat, faceDown) end
                function BridgeRetirePendingCastForInstance(seatId, instanceId, guid, reason) end
                function BridgeClearCardDesignationPresentation(instanceId, object, clearAll) end

                function BridgeTakeTopCardFromLibrary(deck, expectedName, position, faceDown, callback)
                    bridgeTest.extractionIndex = bridgeTest.extractionIndex + 1
                    local index = bridgeTest.extractionIndex
                    local card = nil
                    -- A physical retry must not advance the simulated library
                    -- merely because TTS re-entered the extraction callback.
                    -- Resolve the exact authoritative instance by expected
                    -- card identity, then mark that instance consumed.
                    bridgeTest.forEachArrayEntry(bridgeTest.extractionCards, function(candidate)
                        if card == nil and candidate ~= nil and candidate._extracted ~= true
                            and (expectedName == nil or expectedName == ''
                                or BridgeCardNameMatches(candidate.name, expectedName)) then
                            card = candidate
                        end
                    end)
                    if card == nil then
                        callback(nil, 'no extraction card for index ' .. tostring(index))
                        return
                    end
                    if bridgeTest.delayTakeIndex ~= nil and bridgeTest.delayTakeIndex == index then
                        bridgeTest.delayed[index] = {
                            callback = callback,
                            card = card,
                            position = position,
                            faceDown = faceDown
                        }
                        return
                    end
                    card._extracted = true
                    card._inLibrary = false
                    card._inHand = faceDown == true
                    card._lastPosition = position
                    callback(card, nil)
                end

                local bridgeWaitQueue = {}
                local bridgeWaitDraining = false
                local function bridgeShiftQueue(queue)
                    local first = queue[1]
                    local index = 1
                    while queue[index + 1] ~= nil do
                        queue[index] = queue[index + 1]
                        index = index + 1
                    end
                    queue[index] = nil
                    return first
                end
                local function bridgeScheduleWaitCallback(callback)
                    if callback == nil then return end
                    bridgeTest.waitCallbackCount = (bridgeTest.waitCallbackCount or 0) + 1
                    if bridgeTest.waitCallbackCount > 500 then
                        error('atomic harness wait callback livelock')
                    end
                    table.insert(bridgeWaitQueue, callback)
                    if bridgeWaitDraining then return end
                    bridgeWaitDraining = true
                    while bridgeWaitQueue[1] ~= nil do
                        local nextCallback = bridgeShiftQueue(bridgeWaitQueue)
                        if nextCallback ~= nil then
                            nextCallback()
                        end
                    end
                    bridgeWaitDraining = false
                end

                function BridgeWaitFrames(callback, frames)
                    bridgeScheduleWaitCallback(callback)
                end

                function BridgeWaitTime(callback, delay)
                    bridgeScheduleWaitCallback(callback)
                end

                function BridgeTestSetEventQueue(...)
                    local ordered = {}
                    local count = select('#', ...)
                    for index = 1, count do
                        local event = select(index, ...)
                        ordered[index] = event
                    end
                    setmetatable(ordered, {
                        __len = function(values)
                            local length = 0
                            while values[length + 1] ~= nil do
                                length = length + 1
                            end
                            return length
                        end
                    })
                    BridgeState.eventQueue = ordered
                end

                BridgeState.eventPolling = true
                BridgeState.eventPollGeneration = 4
                BridgeState.eventSessionId = 'session'
                BridgeState.eventSessionGeneration = 1
                BridgeState.lastAppliedEventSequence = 0
                BridgeState.lastReceivedEventSequence = 0
                BridgeState.lastStateProjectedEventSequence = 0
                BridgeState.eventQueue = {}
                BridgeState.animationRunning = false
                BridgeState.bootstrapping = false
                BridgeState.desyncLatched = false
                BridgeState.resyncInFlight = false
                BridgeState.schedulerOwner = 'NORMAL'
                BridgeState.eventDrainTransaction = nil
                BridgeState.eventCommitWatchdog = nil
                BridgeState.eventDrainWatchdog = {}
                BridgeState.physicalTransactionGeneration = 1
                BridgeState.ui = BridgeState.ui or {}
                BridgeState.libraryBatchBySeatId = {}
                BridgeState.libraryExtractionQueueBySeatId = {}
                BridgeState.libraryExtractionActiveBySeatId = {}
                BridgeState.libraryExtractionTransactionBySeatId = {}
                BridgeState.graveyardExtractionActiveBySeatId = {}
                BridgeState.mulliganBottomQueueBySeatId = {}
                BridgeState.mulliganBottomInsertionActiveBySeatId = {}
                BridgeState.zoneLedgerBySeatAndZone = {}
                BridgeState.physicalByInstanceId = {}
                BridgeState.physicalInstanceIdByGuid = {}
                BridgeState.physicalContainerByInstanceId = {}
                BridgeState.physicalContainedInstanceIdByGuid = {}
                BridgeState.physicalSeatByGuid = {}
                BridgeState.physicalZoneByGuid = {}
                BridgeState.cardNameByInstanceId = {}
                BridgeState.zoneAnchorGuidBySeatAndZone = {}
            end
        ");
        return lua;
    }

    private static void ExecuteProbe(Script lua, string source)
    {
        try
        {
            lua.DoString(source);
        }
        catch (ScriptRuntimeException exception)
        {
            throw new Xunit.Sdk.XunitException(exception.DecoratedMessage);
        }
        catch (Exception exception)
        {
            var logs = lua.Globals.Get("capturedLogs");
            var tail = string.Empty;
            if (logs.Type == DataType.Table)
            {
                var lines = logs.Table.Pairs
                    .Select(pair => pair.Value.ToPrintString())
                    .Where(line => !string.IsNullOrEmpty(line))
                    .ToArray();
                var start = Math.Max(0, lines.Length - 40);
                tail = string.Join(Environment.NewLine, lines.Skip(start));
            }

            throw new Xunit.Sdk.XunitException(
                $"Unexpected probe exception: {exception}{Environment.NewLine}"
                + "Captured log tail:" + Environment.NewLine + tail);
        }
    }

    private static string CapturedLogsTail(Script lua, int limit = 40)
    {
        var logs = lua.Globals.Get("capturedLogs");
        if (logs.Type != DataType.Table)
        {
            return string.Empty;
        }

        var lines = logs.Table.Pairs
            .Select(pair => pair.Value.ToPrintString())
            .Where(line => !string.IsNullOrEmpty(line))
            .ToArray();
        var start = Math.Max(0, lines.Length - limit);
        return string.Join(" || ", lines.Skip(start));
    }
}
