using MoonSharp.Interpreter;

namespace MtgTtsBridge.Tests;

public sealed class AtomicMultiCardPhysicalMaterializationTests
{
    private static readonly string Script = File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.lua"));

    [Fact]
    public void ContainedGraveyardProxyCannotOverwriteExactContainedIdentityAsLooseBattlefieldCard()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            bridgeTest.graveyardContainer = bridgeTest.graveyardDeck
            bridgeTest.graveyardDeck.entries = {{guid='contained-27', instanceId=':27', name='Grave Researcher'}}
            BridgeState.physicalContainerByInstanceId[':27'] = {
                deckGuid='grave-deck', cardGuid='contained-27', locatorType='GUID_LOCATOR',
                seatId='forge-player-1', zoneName='graveyard', cardName='Grave Researcher'
            }
            BridgeState.physicalContainedInstanceIdByGuid['contained-27'] = ':27'
            BridgeState.physicalSeatByGuid['contained-27'] = 'forge-player-1'
            BridgeState.physicalZoneByGuid['contained-27'] = 'graveyard'
            local retainedProxy = BridgeTestCreateCard(':27', 'Grave Researcher', 'contained-27')
            retainedProxy._inDeck = true
            proxyAccepted = BridgeRecordLooseCardIdentity(':27', 'contained-27', 'forge-player-1', 'battlefield')
            containerStillPresent = BridgeState.physicalContainerByInstanceId[':27'] ~= nil
            containedOwner = BridgeState.physicalContainedInstanceIdByGuid['contained-27']
            containedZone = BridgeState.physicalZoneByGuid['contained-27']
            looseGuid = BridgeState.physicalByInstanceId[':27']
        ");

        Assert.False(lua.Globals.Get("proxyAccepted").Boolean);
        Assert.True(lua.Globals.Get("containerStillPresent").Boolean);
        Assert.Equal(":27", lua.Globals.Get("containedOwner").String);
        Assert.Equal("graveyard", lua.Globals.Get("containedZone").String);
        Assert.True(lua.Globals.Get("looseGuid").IsNil());
    }

    [Fact]
    public void ExistingGraveyardMergeReplacesLooseBattlefieldMappingWithContainedIdentity()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            BridgeState.cardNameByInstanceId[':33'] = 'Harmonized Trio'
            BridgeState.cardNameByInstanceId[':27'] = 'Grave Researcher'
            BridgeTestSeedExistingDeck({instanceId=':33', cardName='Harmonized Trio'})
            local researcher = BridgeTestCreateCard(':27', 'Grave Researcher', 'e7460b')
            researcher._inLibrary = false
            BridgeRecordLooseCardIdentity(':27', 'e7460b', 'forge-player-1', 'battlefield')
            mergeCompleted = false
            mergeOk, mergeError = BridgeMoveToGraveyard({
                sequence=243, seatId='forge-player-1', sourceZone='battlefield',
                destinationZone='graveyard', cardInstanceId=':27'
            }, researcher, function(ok, err) mergeCompleted = ok == true; mergeCompletionError = err end)
            contained = BridgeState.physicalContainerByInstanceId[':27']
            looseGuid = BridgeState.physicalByInstanceId[':27']
            containedOwner = contained and BridgeState.physicalContainedInstanceIdByGuid[contained.cardGuid] or nil
            containedZone = contained and BridgeState.physicalZoneByGuid[contained.cardGuid] or nil
            containedSeat = contained and BridgeState.physicalSeatByGuid[contained.cardGuid] or nil
            nativeCount = BridgeTestGraveyardInstanceCount(':27')
        ");

        Assert.True(lua.Globals.Get("mergeOk").Boolean, lua.Globals.Get("mergeError").ToPrintString());
        Assert.True(lua.Globals.Get("mergeCompleted").Boolean, lua.Globals.Get("mergeCompletionError").ToPrintString());
        Assert.Equal(1, lua.Globals.Get("nativeCount").Number);
        Assert.True(lua.Globals.Get("contained").IsNotNil());
        Assert.True(lua.Globals.Get("looseGuid").IsNil());
        Assert.Equal(":27", lua.Globals.Get("containedOwner").String);
        Assert.Equal("graveyard", lua.Globals.Get("containedZone").String);
        Assert.Equal("forge-player-1", lua.Globals.Get("containedSeat").String);
    }

    [Fact]
    public void ExactCostCandidateNeverFallsBackToSameNameBattlefieldCard()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            local battlefield = BridgeTestCreateCard(':32', 'Harmonized Trio', 'battlefield-32')
            battlefield._inLibrary = false
            BridgeRecordLooseCardIdentity(':32', 'battlefield-32', 'forge-player-1', 'battlefield')
            local decision = {decisionId='delve-1', seatId='forge-player-1'}
            local action = {actionId='delve-31', cardInstanceId=':31', cardIdentity='Harmonized Trio', sourceZone='graveyard'}
            resolved, resolveError = BridgeResolveExactActionPhysical(decision, action)
            battlefieldInstance = BridgeState.physicalInstanceIdByGuid['battlefield-32']
            battlefieldZone = BridgeState.physicalZoneByGuid['battlefield-32']
            attemptedRepair = BridgeState.physicalByInstanceId[':31']
            resolutionKind = BridgeState.lastActionPhysicalResolution and BridgeState.lastActionPhysicalResolution.resolutionKind or nil
        ");

        Assert.True(lua.Globals.Get("resolved").IsNil());
        Assert.Contains("contained", lua.Globals.Get("resolveError").String);
        Assert.Equal(":32", lua.Globals.Get("battlefieldInstance").String);
        Assert.Equal("battlefield", lua.Globals.Get("battlefieldZone").String);
        Assert.True(lua.Globals.Get("attemptedRepair").IsNil());
        Assert.Equal("unresolved", lua.Globals.Get("resolutionKind").String);
    }

    [Fact]
    public void DelveGraveyardCandidateResolvesContainedExactInstanceWithoutTouchingSameNamePermanent()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            local battlefield = BridgeTestCreateCard(':32', 'Harmonized Trio', 'battlefield-32')
            battlefield._inLibrary = false
            BridgeRecordLooseCardIdentity(':32', 'battlefield-32', 'forge-player-1', 'battlefield')
            bridgeTest.graveyardDeck.entries = {{instanceId=':31', name='Harmonized Trio', guid='contained-31'}}
            bridgeTest.graveyardContainer = bridgeTest.graveyardDeck
            BridgeState.physicalContainerByInstanceId[':31'] = {
                deckGuid='grave-deck', cardGuid='contained-31', locatorType='GUID_LOCATOR',
                seatId='forge-player-1', zoneName='graveyard', cardName='Harmonized Trio'
            }
            BridgeState.physicalContainedInstanceIdByGuid['contained-31'] = ':31'
            BridgeState.physicalSeatByGuid['contained-31'] = 'forge-player-1'
            BridgeState.physicalZoneByGuid['contained-31'] = 'graveyard'
            local decision = {decisionId='delve-1', seatId='forge-player-1'}
            local action = {actionId='delve-31', cardInstanceId=':31', cardIdentity='Harmonized Trio', sourceZone='graveyard'}
            resolved, resolveError = BridgeResolveExactActionPhysical(decision, action)
            resolutionKind = resolved and resolved.kind or nil
            resolvedDeckGuid = resolved and resolved.deckGuid or nil
            battlefieldInstance = BridgeState.physicalInstanceIdByGuid['battlefield-32']
            battlefieldZone = BridgeState.physicalZoneByGuid['battlefield-32']
        ");

        Assert.Equal("exact-contained", lua.Globals.Get("resolutionKind").String);
        Assert.Equal("grave-deck", lua.Globals.Get("resolvedDeckGuid").String);
        Assert.Equal(":32", lua.Globals.Get("battlefieldInstance").String);
        Assert.Equal("battlefield", lua.Globals.Get("battlefieldZone").String);
    }

    [Fact]
    public void ExactActionSourceZoneMustMatchPhysicalZone()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            local battlefield = BridgeTestCreateCard(':31', 'Harmonized Trio', 'battlefield-31')
            battlefield._inLibrary = false
            BridgeRecordLooseCardIdentity(':31', 'battlefield-31', 'forge-player-1', 'battlefield')
            local decision = {decisionId='delve-1', seatId='forge-player-1'}
            local action = {actionId='delve-31', cardInstanceId=':31', cardIdentity='Harmonized Trio', sourceZone='graveyard'}
            resolved, resolveError = BridgeResolveExactActionPhysical(decision, action)
            physicalZone = BridgeState.physicalZoneByGuid['battlefield-31']
            resolutionKind = BridgeState.lastActionPhysicalResolution and BridgeState.lastActionPhysicalResolution.resolutionKind or nil
        ");

        Assert.True(lua.Globals.Get("resolved").IsNil());
        Assert.Contains("wrong seat or source zone", lua.Globals.Get("resolveError").String);
        Assert.Equal("battlefield", lua.Globals.Get("physicalZone").String);
        Assert.Equal("unresolved", lua.Globals.Get("resolutionKind").String);
    }

    [Fact]
    public void StaleDecisionActionCannotSubmitAfterDecisionReplacement()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            BridgeState.eventSessionId = 'session'
            BridgeState.eventSessionGeneration = 1
            BridgeState.lastDecision = {
                decisionId = 'decision-new', kind = 'main_priority', seatId = 'forge-player-1',
                actions = {{actionId = 'pass-new', type = 'pass_priority'}}
            }
            BridgeState.choiceTransactions = {}
            BridgeState.choiceProtocolPaused = false
            BridgeState.desyncLatched = false
            BridgeState.submitting = false
            posted = 0
            BridgeHttp.requestJson = function(...) posted = posted + 1 end
            BridgeSubmitChoice('decision-new', 'cast-old-trio', 'stale-test')
            stalePosted = posted
            staleTransaction = BridgeState.choiceTransactions['decision-new']
        ");

        Assert.Equal(0d, lua.Globals.Get("stalePosted").Number);
        Assert.True(lua.Globals.Get("staleTransaction").IsNil());
    }

    [Fact]
    public void SemanticSpellResolvedDoesNotPreemptStructuredThoughtScourMove()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            BridgeState.eventSessionId = 'session'
            BridgeState.eventSessionGeneration = 3
            BridgeState.lastAppliedEventSequence = 27
            BridgeState.cardNameByInstanceId[':33'] = 'Harmonized Trio'
            BridgeState.cardNameByInstanceId[':36'] = 'Baleful Strix'
            BridgeState.cardNameByInstanceId[':35'] = 'Thought Scour'
            BridgeState.cardNameByInstanceId[':3'] = 'Armored Skaab'
            local millA = BridgeTestCreateCard(':33', 'Harmonized Trio', 'mill-a')
            local millB = BridgeTestCreateCard(':36', 'Baleful Strix', 'mill-b')
            local scour = BridgeTestCreateCard(':35', 'Thought Scour', 'scour-guid')
            local draw = BridgeTestCreateCard(':3', 'Armored Skaab', 'draw-guid')
            scour._inLibrary = false
            scour._inHand = false
            scour._lastPosition = {x=0, y=2, z=0}
            BridgeRecordLooseCardIdentity(':35', 'scour-guid', 'forge-player-1', 'stack')
            BridgeState.pendingCastBySeatId['forge-player-1'] = {
                cardInstanceId=':35', guid='scour-guid', seatId='forge-player-1'
            }
            snapshotSchedules = 0
            BridgeScheduleSnapshotReconcile = function(reason) snapshotSchedules = snapshotSchedules + 1 end

            semanticApplied, semanticDelay = BridgeApplyAuthoritativeEvent({
                sequence=27, kind='spell_resolved', seatId='forge-player-1',
                sourceZone='stack', destinationZone='graveyard',
                cardInstanceId=':35', cardName='Thought Scour', forgeSequence=12
            })
            zoneAfterSemantic = BridgeState.physicalZoneByGuid['scour-guid']
            pendingAfterSemantic = BridgeState.pendingCastBySeatId['forge-player-1'] ~= nil
            semanticResolutionAfterSemantic = BridgeState.pendingSemanticResolutionByInstanceId[':35'] ~= nil
            graveyardBeforeStructured = bridgeTest.graveyardContainer

            BridgeTestQueueExtractionCards({millA, millB, draw})
            BridgeTestSetEventQueue(
                {sequence=28, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':33', cardName='Harmonized Trio', forgeSequence=13},
                {sequence=29, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':36', cardName='Baleful Strix', forgeSequence=13},
                {sequence=30, kind='card_moved', seatId='forge-player-1', sourceZone='stack', destinationZone='graveyard', cardInstanceId=':35', cardName='Thought Scour', forgeSequence=13},
                {sequence=31, kind='draw', seatId='forge-player-1', sourceZone='library', destinationZone='hand', cardInstanceId=':3', cardName='Armored Skaab', forgeSequence=13}
            )
            BridgeProcessEventQueue()
            finalApplied = BridgeState.lastAppliedEventSequence
            finalDeckCount = BridgeTestArrayLength(bridgeTest.graveyardDeck.entries)
            scourContainer = BridgeState.physicalContainerByInstanceId[':35']
            scourContained = scourContainer and scourContainer.zoneName == 'graveyard'
            pendingAfterStructured = BridgeState.pendingCastBySeatId['forge-player-1'] ~= nil
            pendingInstanceAfterStructured = pendingAfterStructured
                and BridgeState.pendingCastBySeatId['forge-player-1'].cardInstanceId or nil
            semanticResolutionAfterStructured = BridgeState.pendingSemanticResolutionByInstanceId[':35'] ~= nil
            drawZone = BridgeState.physicalZoneByGuid[BridgeState.physicalByInstanceId[':3']]
            commits = BridgeTestCountLogToken('MUTATION_COMMIT')
            aborts = BridgeTestCountLogToken('MUTATION_ABORT')
            deferredPhysicalDispatches = BridgeTestCountLogToken('DEFERRED_GRAVEYARD_PHYSICAL_DISPATCHED')
            desyncState = tostring(desyncReason)
        ");

        Assert.True(lua.Globals.Get("semanticApplied").Boolean);
        Assert.Equal("stack", lua.Globals.Get("zoneAfterSemantic").String);
        Assert.True(lua.Globals.Get("pendingAfterSemantic").Boolean);
        Assert.True(lua.Globals.Get("semanticResolutionAfterSemantic").Boolean);
        Assert.True(lua.Globals.Get("graveyardBeforeStructured").IsNil());
        Assert.Equal(31, lua.Globals.Get("finalApplied").Number);
        Assert.Equal(3, lua.Globals.Get("finalDeckCount").Number);
        Assert.True(lua.Globals.Get("scourContained").Boolean);
        Assert.False(lua.Globals.Get("pendingAfterStructured").Boolean,
            $"pending={lua.Globals.Get("pendingInstanceAfterStructured").ToPrintString()} logs={CapturedLogsTail(lua)}");
        Assert.False(lua.Globals.Get("semanticResolutionAfterStructured").Boolean);
        Assert.Equal("hand", lua.Globals.Get("drawZone").String);
        Assert.Equal(1, lua.Globals.Get("commits").Number);
        Assert.Equal(0, lua.Globals.Get("aborts").Number);
        Assert.Equal(1, lua.Globals.Get("deferredPhysicalDispatches").Number);
        Assert.Equal("nil", lua.Globals.Get("desyncState").String);
    }

    [Fact]
    public void SemanticPermanentResolutionDoesNotPreemptStructuredBattlefieldMove()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            local creature = BridgeTestCreateCard(':permanent', 'Armored Skaab', 'permanent-guid')
            creature._inLibrary = false
            creature._inHand = false
            creature._lastPosition = {x=0, y=2, z=0}
            BridgeRecordLooseCardIdentity(':permanent', 'permanent-guid', 'forge-player-1', 'stack')
            BridgeState.pendingCastBySeatId['forge-player-1'] = {
                cardInstanceId=':permanent', guid='permanent-guid', seatId='forge-player-1'
            }
            BridgeScheduleSnapshotReconcile = function(reason) end
            applied = BridgeApplyAuthoritativeEvent({
                sequence=10, kind='spell_resolved', seatId='forge-player-1',
                sourceZone='stack', destinationZone='battlefield',
                cardInstanceId=':permanent', cardName='Armored Skaab'
            })
            zoneAfterSemantic = BridgeState.physicalZoneByGuid['permanent-guid']
            pendingAfterSemantic = BridgeState.pendingCastBySeatId['forge-player-1'] ~= nil
            semanticResolutionAfterSemantic = BridgeState.pendingSemanticResolutionByInstanceId[':permanent'] ~= nil
            moved, moveError = BridgeApplyStructuredCardMove({
                sequence=11, kind='card_moved', seatId='forge-player-1',
                sourceZone='stack', destinationZone='battlefield',
                cardInstanceId=':permanent', cardName='Armored Skaab'
            })
            zoneAfterStructured = BridgeState.physicalZoneByGuid['permanent-guid']
            pendingAfterStructured = BridgeState.pendingCastBySeatId['forge-player-1'] ~= nil
            pendingInstanceAfterStructured = pendingAfterStructured
                and BridgeState.pendingCastBySeatId['forge-player-1'].cardInstanceId or nil
            semanticResolutionAfterStructured = BridgeState.pendingSemanticResolutionByInstanceId[':permanent'] ~= nil
        ");

        Assert.True(lua.Globals.Get("applied").Boolean);
        Assert.Equal("stack", lua.Globals.Get("zoneAfterSemantic").String);
        Assert.True(lua.Globals.Get("pendingAfterSemantic").Boolean);
        Assert.True(lua.Globals.Get("semanticResolutionAfterSemantic").Boolean);
        Assert.True(lua.Globals.Get("moved").Boolean,
            lua.Globals.Get("moveError").ToPrintString());
        Assert.Equal("battlefield", lua.Globals.Get("zoneAfterStructured").String);
        Assert.False(lua.Globals.Get("pendingAfterStructured").Boolean,
            $"pending={lua.Globals.Get("pendingInstanceAfterStructured").ToPrintString()} logs={CapturedLogsTail(lua)}");
        Assert.False(lua.Globals.Get("semanticResolutionAfterStructured").Boolean);
    }

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
            groupRequestCount = bridgeTest.groupCalls or 0
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
        Assert.Equal(1, lua.Globals.Get("groupRequestCount").Number);
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
    public void NativeGroupArrayResultIsAcquiredWithoutWaitingForResync()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            bridgeTest.groupReturnsArray = true
            BridgeState.lastAppliedEventSequence = 900
            BridgeState.cardNameByInstanceId[':g1'] = 'Group A'
            BridgeState.cardNameByInstanceId[':g2'] = 'Group B'
            local a = BridgeTestCreateCard(':g1', 'Group A', 'loose-g1')
            local b = BridgeTestCreateCard(':g2', 'Group B', 'loose-g2')
            BridgeTestQueueExtractionCards({a, b})
            BridgeTestSetEventQueue(
                {sequence=901, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':g1', cardName='Group A', forgeSequence=922},
                {sequence=902, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':g2', cardName='Group B', forgeSequence=922}
            )
            BridgeProcessEventQueue()
            finalApplied = BridgeState.lastAppliedEventSequence
            mutationCommitCount = BridgeTestCountLogToken('MUTATION_COMMIT')
            mutationAbortCount = BridgeTestCountLogToken('MUTATION_ABORT')
            topologyLogCount = BridgeTestCountLogToken('MUTATION_GRAVEYARD_TOPOLOGY')
            groupResultLogCount = BridgeTestCountLogToken('MUTATION_GRAVEYARD_GROUP_RESULT')
            desyncState = tostring(desyncReason)
        ");

        Assert.Equal(902, lua.Globals.Get("finalApplied").Number);
        Assert.Equal(1, lua.Globals.Get("mutationCommitCount").Number);
        Assert.Equal(0, lua.Globals.Get("mutationAbortCount").Number);
        Assert.True(lua.Globals.Get("topologyLogCount").Number >= 3);
        Assert.Equal(1, lua.Globals.Get("groupResultLogCount").Number);
        Assert.Equal("nil", lua.Globals.Get("desyncState").String);
    }

    [Fact]
    public void NativeGroupArrayDeckThatReceivesItsGuidOnALaterFrameIsRetained()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            bridgeTest.groupReturnsArray = true
            bridgeTest.groupDeckUnreadyGuidReads = 2
            bridgeTest.groupDeckGuidReads = 0
            BridgeState.lastAppliedEventSequence = 900
            BridgeState.cardNameByInstanceId[':g1'] = 'Group A'
            BridgeState.cardNameByInstanceId[':g2'] = 'Group B'
            local a = BridgeTestCreateCard(':g1', 'Group A', 'loose-g1')
            local b = BridgeTestCreateCard(':g2', 'Group B', 'loose-g2')
            BridgeTestQueueExtractionCards({a, b})
            BridgeTestSetEventQueue(
                {sequence=901, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':g1', cardName='Group A', forgeSequence=922},
                {sequence=902, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':g2', cardName='Group B', forgeSequence=922}
            )
            BridgeProcessEventQueue()
            finalApplied = BridgeState.lastAppliedEventSequence
            mutationCommitCount = BridgeTestCountLogToken('MUTATION_COMMIT')
            mutationAbortCount = BridgeTestCountLogToken('MUTATION_ABORT')
            desyncState = tostring(desyncReason)
        ");

        Assert.Equal(902, lua.Globals.Get("finalApplied").Number);
        Assert.Equal(1, lua.Globals.Get("mutationCommitCount").Number);
        Assert.Equal(0, lua.Globals.Get("mutationAbortCount").Number);
        Assert.Equal("nil", lua.Globals.Get("desyncState").String);
    }

    [Fact]
    public void WidelySeparatedStagedCardsRequireOwnedNativeDestinationFormation()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            bridgeTest.useProductionGraveyardShape = true
            bridgeTest.preserveContainedSourceGuid = true
            bridgeTest.keepContainedLooseAliases = true
            bridgeTest.reassignContainedEveryPut = false
            BridgeState.lastAppliedEventSequence = 173
            BridgeState.cardNameByInstanceId[':3'] = 'Armored Skaab'
            BridgeState.cardNameByInstanceId[':9'] = 'Stitcher\'s Supplier'
            BridgeState.cardNameByInstanceId[':29'] = 'Mental Note'
            BridgeState.cardNameByInstanceId[':8'] = 'Stitcher\'s Supplier'
            local skaab = BridgeTestCreateCard(':3', 'Armored Skaab', 'skaab-guid')
            local milledSupplier = BridgeTestCreateCard(':9', 'Stitcher\'s Supplier', 'milled-supplier-guid')
            local note = BridgeTestCreateCard(':29', 'Mental Note', 'note-guid')
            local drawnSupplier = BridgeTestCreateCard(':8', 'Stitcher\'s Supplier', 'drawn-supplier-guid')
            note._inLibrary = false
            note._inHand = false
            note._lastPosition = {x=2, y=1, z=0}
            BridgeRecordLooseCardIdentity(':29', 'note-guid', 'forge-player-1', 'stack')
            BridgeTestQueueExtractionCards({skaab, milledSupplier, drawnSupplier})
            BridgeTestSetEventQueue(
                {sequence=174, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':3', cardName='Armored Skaab', forgeSequence=32},
                {sequence=175, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':9', cardName='Stitcher\'s Supplier', forgeSequence=32},
                {sequence=176, kind='card_moved', seatId='forge-player-1', sourceZone='stack', destinationZone='graveyard', cardInstanceId=':29', cardName='Mental Note', forgeSequence=32},
                {sequence=177, kind='draw', seatId='forge-player-1', sourceZone='library', destinationZone='hand', cardInstanceId=':8', cardName='Stitcher\'s Supplier', forgeSequence=32}
            )
            BridgeProcessEventQueue()
            local function distance(left, right)
                local dx = left.x - right.x
                local dz = left.z - right.z
                return math.sqrt(dx * dx + dz * dz)
            end
            finalApplied = BridgeState.lastAppliedEventSequence
            stagingDistance = distance(skaab._lastPosition, milledSupplier._lastPosition)
            finalDeckCount = BridgeTestArrayLength(bridgeTest.graveyardDeck.entries)
            finalLooseCount = BridgeTestLooseGraveyardCardCount()
            drawGuid = BridgeState.physicalByInstanceId[':8']
            drawZone = drawGuid and BridgeState.physicalZoneByGuid[drawGuid] or nil
            transitionAliases = 0
            for _, record in ipairs(BridgeState.physicalMutationJournal or {}) do
                if record.classification == 'transitional_alias' then
                    transitionAliases = transitionAliases + 1
                end
            end
            commits = BridgeTestCountLogToken('MUTATION_COMMIT')
            aborts = BridgeTestCountLogToken('MUTATION_ABORT')
            desyncState = tostring(desyncReason)
        ");

        Assert.True(lua.Globals.Get("finalApplied").Number == 177,
            $"applied={lua.Globals.Get("finalApplied").ToPrintString()} stageDistance={lua.Globals.Get("stagingDistance").ToPrintString()} deck={lua.Globals.Get("finalDeckCount").ToPrintString()} loose={lua.Globals.Get("finalLooseCount").ToPrintString()} aliases={lua.Globals.Get("transitionAliases").ToPrintString()} draw={lua.Globals.Get("drawZone").ToPrintString()} commits={lua.Globals.Get("commits").ToPrintString()} aborts={lua.Globals.Get("aborts").ToPrintString()} desync={lua.Globals.Get("desyncState").ToPrintString()} logs={CapturedLogsTail(lua)}");
        Assert.True(lua.Globals.Get("stagingDistance").Number > 3.25);
        Assert.Equal(3, lua.Globals.Get("finalDeckCount").Number);
        // Real TTS may retain pre-group Card userdata in getAllObjects for a
        // few frames. The production shape validator must classify only the
        // positively owned aliases, rather than weakening the final topology.
        Assert.True(lua.Globals.Get("finalLooseCount").Number >= 2);
        Assert.True(lua.Globals.Get("transitionAliases").Number >= 2);
        Assert.Equal("hand", lua.Globals.Get("drawZone").String);
        Assert.Equal(1, lua.Globals.Get("commits").Number);
        Assert.Equal(0, lua.Globals.Get("aborts").Number);
        Assert.Equal("nil", lua.Globals.Get("desyncState").String);
    }

    [Fact]
    public void NativeGroupMayReturnBeforeSingleDeckExists()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            bridgeTest.groupDeckDiscoveryDelay = 3
            BridgeState.lastAppliedEventSequence = 40
            BridgeState.cardNameByInstanceId[':a'] = 'Island'
            BridgeState.cardNameByInstanceId[':b'] = 'Swamp'
            local a = BridgeTestCreateCard(':a', 'Island', 'a-guid')
            local b = BridgeTestCreateCard(':b', 'Swamp', 'b-guid')
            BridgeTestQueueExtractionCards({a, b})
            BridgeTestSetEventQueue(
                {sequence=41, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':a', cardName='Island', forgeSequence=41},
                {sequence=42, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':b', cardName='Swamp', forgeSequence=41}
            )
            BridgeProcessEventQueue()
            finalApplied = BridgeState.lastAppliedEventSequence
            discoveryChecks = bridgeTest.groupDiscoveryChecks or 0
            deckCount = BridgeTestArrayLength(bridgeTest.graveyardDeck.entries)
            commits = BridgeTestCountLogToken('MUTATION_COMMIT')
            aborts = BridgeTestCountLogToken('MUTATION_ABORT')
            desyncState = tostring(desyncReason)
        ");

        Assert.True(lua.Globals.Get("finalApplied").Number == 42,
            $"applied={lua.Globals.Get("finalApplied").ToPrintString()} checks={lua.Globals.Get("discoveryChecks").ToPrintString()} deck={lua.Globals.Get("deckCount").ToPrintString()} commits={lua.Globals.Get("commits").ToPrintString()} aborts={lua.Globals.Get("aborts").ToPrintString()} desync={lua.Globals.Get("desyncState").ToPrintString()} logs={CapturedLogsTail(lua)}");
        Assert.True(lua.Globals.Get("discoveryChecks").Number >= 3);
        Assert.Equal(2, lua.Globals.Get("deckCount").Number);
        Assert.Equal(1, lua.Globals.Get("commits").Number);
        Assert.Equal(0, lua.Globals.Get("aborts").Number);
    }

    [Fact]
    public void GenuineDestinationFormationFailureRemainsRecoverable()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            bridgeTest.groupNeverFormsDeck = true
            bridgeTest.useProductionGraveyardShape = true
            BridgeState.lastAppliedEventSequence = 50
            BridgeState.cardNameByInstanceId[':a'] = 'Island'
            BridgeState.cardNameByInstanceId[':b'] = 'Swamp'
            local a = BridgeTestCreateCard(':a', 'Island', 'a-guid')
            local b = BridgeTestCreateCard(':b', 'Swamp', 'b-guid')
            BridgeTestQueueExtractionCards({a, b})
            BridgeTestSetEventQueue(
                {sequence=51, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':a', cardName='Island', forgeSequence=51},
                {sequence=52, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':b', cardName='Swamp', forgeSequence=51}
            )
            BridgeProcessEventQueue()
            finalApplied = BridgeState.lastAppliedEventSequence
            desyncLatched = BridgeState.desyncLatched == true
            txRetired = BridgeState.eventDrainTransaction == nil
            aStillPresent = bridgeTest.cardsByGuid['a-guid'] ~= nil
                and bridgeTest.cardsByGuid['a-guid']._inLibrary ~= true
            bStillPresent = bridgeTest.cardsByGuid['b-guid'] ~= nil
                and bridgeTest.cardsByGuid['b-guid']._inLibrary ~= true
            commits = BridgeTestCountLogToken('MUTATION_COMMIT')
            aborts = BridgeTestCountLogToken('MUTATION_ABORT')
            desyncState = tostring(desyncReason)
        ");

        Assert.True(lua.Globals.Get("finalApplied").Number == 50,
            $"applied={lua.Globals.Get("finalApplied").ToPrintString()} desync={lua.Globals.Get("desyncState").ToPrintString()} txRetired={lua.Globals.Get("txRetired").ToPrintString()} aPresent={lua.Globals.Get("aStillPresent").ToPrintString()} bPresent={lua.Globals.Get("bStillPresent").ToPrintString()} commits={lua.Globals.Get("commits").ToPrintString()} aborts={lua.Globals.Get("aborts").ToPrintString()} logs={CapturedLogsTail(lua)}");
        Assert.True(lua.Globals.Get("desyncLatched").Boolean);
        Assert.True(lua.Globals.Get("txRetired").Boolean);
        Assert.True(lua.Globals.Get("aStillPresent").Boolean);
        Assert.True(lua.Globals.Get("bStillPresent").Boolean);
        Assert.Equal(0, lua.Globals.Get("commits").Number);
        Assert.True(lua.Globals.Get("aborts").Number >= 1);
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
    public void SupplierThreeCardMillDoesNotDuplicatePhysicalEntriesDuringNativeGrouping()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            bridgeTest.autoStackOverlappingStagedCards = true
            BridgeState.lastAppliedEventSequence = 116
            BridgeState.lastReceivedEventSequence = 119
            BridgeState.cardNameByInstanceId[':37'] = 'Baleful Strix'
            BridgeState.cardNameByInstanceId[':2'] = 'Treasure Cruise'
            BridgeState.cardNameByInstanceId[':31'] = 'Harmonized Trio'
            local c1 = BridgeTestCreateCard(':37', 'Baleful Strix', 'loose-37')
            local c2 = BridgeTestCreateCard(':2', 'Treasure Cruise', 'loose-2')
            local c3 = BridgeTestCreateCard(':31', 'Harmonized Trio', 'loose-31')
            BridgeTestQueueExtractionCards({c1, c2, c3})
            BridgeTestSetEventQueue(
                {sequence=117, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':37', cardName='Baleful Strix', forgeSequence=24},
                {sequence=118, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':2', cardName='Treasure Cruise', forgeSequence=24},
                {sequence=119, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':31', cardName='Harmonized Trio', forgeSequence=24}
            )
            local committedLedgerBefore = BridgeZoneLedger('forge-player-1', 'graveyard')
            ledgerBeforeCount = BridgeTestArrayLength(committedLedgerBefore or {})
            BridgeProcessEventQueue()
            local committedLedgerAfter = BridgeZoneLedger('forge-player-1', 'graveyard')
            finalApplied = BridgeState.lastAppliedEventSequence
            finalLedgerCount = BridgeTestArrayLength(committedLedgerAfter or {})
            nativeEntryCount = BridgeTestArrayLength(bridgeTest.graveyardDeck.getObjects() or {})
            nativeDeckCount = bridgeTest.graveyardContainer == bridgeTest.graveyardDeck and 1 or 0
            looseCount = BridgeTestLooseGraveyardCardCount()
            duplicateRepresentationCount = BridgeTestDuplicateGraveyardInstanceCount()
            treasureRepresentationCount = BridgeTestGraveyardInstanceCount(':2')
            trioRepresentationCount = BridgeTestGraveyardInstanceCount(':31')
            mutationCommitCount = BridgeTestCountLogToken('MUTATION_COMMIT')
            mutationAbortCount = BridgeTestCountLogToken('MUTATION_ABORT')
            autoStackCount = bridgeTest.autoStackCount or 0
            debugDesync = tostring(desyncReason)
        ");

        Assert.Equal(0, lua.Globals.Get("ledgerBeforeCount").Number);
        Assert.True(lua.Globals.Get("autoStackCount").Number == 0,
            $"pre-group native autoStackCount={lua.Globals.Get("autoStackCount").Number}; desync={lua.Globals.Get("debugDesync").String}; logs={CapturedLogsTail(lua)}");
        Assert.Equal(119, lua.Globals.Get("finalApplied").Number);
        Assert.Equal(3, lua.Globals.Get("finalLedgerCount").Number);
        Assert.Equal(1, lua.Globals.Get("nativeDeckCount").Number);
        Assert.Equal(3, lua.Globals.Get("nativeEntryCount").Number);
        Assert.Equal(0, lua.Globals.Get("looseCount").Number);
        Assert.Equal(0, lua.Globals.Get("duplicateRepresentationCount").Number);
        Assert.Equal(1, lua.Globals.Get("treasureRepresentationCount").Number);
        Assert.Equal(1, lua.Globals.Get("trioRepresentationCount").Number);
        Assert.Equal(1, lua.Globals.Get("mutationCommitCount").Number);
        Assert.Equal(0, lua.Globals.Get("mutationAbortCount").Number);
    }

    [Fact]
    public void MentalNoteThreeCardMillRebindsZeroBasedNativeDeckEntriesWithoutShiftingIdentity()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            BridgeState.eventSessionId = 'mental-note-session'
            local deck = bridgeTest.graveyardDeck
            local inventoryPhase = 'before-put'
            deck.getObjects = function()
                if inventoryPhase == 'before-put' then
                    return {
                        {guid='old-island', nickname='Island', index=0},
                        {guid='old-supplier', nickname='Stitcher\'s Supplier', index=1}
                    }
                end
                return {
                    {guid='contained-note', nickname='Mental Note', index=0},
                    {guid='contained-island', nickname='Island', index=1},
                    {guid='contained-supplier', nickname='Stitcher\'s Supplier', index=2}
                }
            end
            BridgeRecordContainedCardIdentity(':13', 'grave-deck', 'old-island', 'forge-player-1', 'graveyard', 'Island')
            BridgeRecordContainedCardIdentity(':9', 'grave-deck', 'old-supplier', 'forge-player-1', 'graveyard', 'Stitcher\'s Supplier')
            BridgeRecordLooseCardIdentity(':29', 'contained-note', 'forge-player-1', 'stack')
            local expected = BridgeCollectGraveyardExpectedInstances('forge-player-1', deck, ':29', true)
            expected1 = expected[1] and expected[1].instanceId or nil
            expected2 = expected[2] and expected[2].instanceId or nil
            expected3 = expected[3] and expected[3].instanceId or nil
            inventoryPhase = 'after-put'
            rebindOk = BridgeRecordGraveyardContainerEntries('forge-player-1', deck, expected)
            island = BridgeState.physicalContainerByInstanceId[':13']
            supplier = BridgeState.physicalContainerByInstanceId[':9']
            note = BridgeState.physicalContainerByInstanceId[':29']
            rebindFailure = BridgeState.lastGraveyardRebindFailure
        ");

        Assert.True(lua.Globals.Get("rebindOk").Boolean,
            $"rebind={lua.Globals.Get("rebindFailure").ToPrintString()}; logs={CapturedLogsTail(lua)}");
        Assert.Equal(":29", lua.Globals.Get("expected1").String);
        Assert.Equal(":13", lua.Globals.Get("expected2").String);
        Assert.Equal(":9", lua.Globals.Get("expected3").String);
        Assert.Equal("contained-island", lua.Globals.Get("island").Table.Get("cardGuid").String);
        Assert.Equal("contained-supplier", lua.Globals.Get("supplier").Table.Get("cardGuid").String);
        Assert.Equal("contained-note", lua.Globals.Get("note").Table.Get("cardGuid").String);
    }

    [Fact]
    public void GraveyardRebindPermutationDoesNotClobberCurrentGuidMetadata()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            BridgeState.eventSessionId = 'rebind-permutation-session'
            local deck = bridgeTest.graveyardDeck
            deck.getObjects = function()
                return {
                    {guid='guid-a', nickname='Card A', index=0},
                    {guid='guid-b', nickname='Card B', index=1}
                }
            end
            BridgeRecordContainedCardIdentity(':a', 'grave-deck', 'guid-a', 'forge-player-1', 'graveyard', 'Card A')
            BridgeRecordContainedCardIdentity(':b', 'grave-deck', 'guid-b', 'forge-player-1', 'graveyard', 'Card B')
            local expectedRebind = BridgeCollectGraveyardExpectedInstances('forge-player-1', deck, nil, false)
            deck.getObjects = function()
                return {
                    {guid='guid-b', nickname='Card A', index=0},
                    {guid='guid-a', nickname='Card B', index=1}
                }
            end
            local ok = BridgeRecordGraveyardContainerEntries('forge-player-1', deck, expectedRebind)
            rebindOk = ok
            rebindFailure = BridgeState.lastGraveyardRebindFailure
            a = BridgeState.physicalContainerByInstanceId[':a']
            b = BridgeState.physicalContainerByInstanceId[':b']
            inverseA = BridgeState.physicalContainedInstanceIdByGuid['guid-b']
            inverseB = BridgeState.physicalContainedInstanceIdByGuid['guid-a']
            seatA = BridgeState.physicalSeatByGuid['guid-b']
            zoneA = BridgeState.physicalZoneByGuid['guid-b']
            seatB = BridgeState.physicalSeatByGuid['guid-a']
            zoneB = BridgeState.physicalZoneByGuid['guid-a']
        ");

        Assert.True(lua.Globals.Get("rebindOk").Boolean,
            $"rebindFailure={lua.Globals.Get("rebindFailure").ToPrintString()}; logs={CapturedLogsTail(lua)}");
        Assert.Equal("guid-b", lua.Globals.Get("a").Table.Get("cardGuid").String);
        Assert.Equal("guid-a", lua.Globals.Get("b").Table.Get("cardGuid").String);
        Assert.Equal(":a", lua.Globals.Get("inverseA").String);
        Assert.Equal(":b", lua.Globals.Get("inverseB").String);
        Assert.Equal("forge-player-1", lua.Globals.Get("seatA").String);
        Assert.Equal("graveyard", lua.Globals.Get("zoneA").String);
        Assert.Equal("forge-player-1", lua.Globals.Get("seatB").String);
        Assert.Equal("graveyard", lua.Globals.Get("zoneB").String);
    }

    [Fact]
    public void RecoveryMergesLooseMillCardIntoExistingDeckWithoutDroppingCommittedEntries()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            BridgeState.eventSessionId = 'recovery-session'
            BridgeState.cardNameByInstanceId[':old-a'] = 'Island'
            BridgeState.cardNameByInstanceId[':old-b'] = 'Swamp'
            BridgeState.cardNameByInstanceId[':recovered'] = 'Thought Scour'
            BridgeTestSeedExistingDeck(
                {instanceId=':old-a', cardName='Island'},
                {instanceId=':old-b', cardName='Swamp'}
            )
            local recovered = BridgeTestCreateCard(':recovered', 'Thought Scour', 'loose-recovered')
            recovered._inLibrary = false
            recovered._lastPosition = {x=0, y=1, z=0}
            BridgeRecordLooseCardIdentity(':recovered', 'loose-recovered', 'forge-player-1', 'graveyard')
            local deck = bridgeTest.graveyardDeck
            local rawPut = deck.putObject
            deck.putObject = function(object, position)
                local result = rawPut(object, position)
                local entries = deck.entries
                local length = BridgeTestArrayLength(entries)
                local incoming = entries[length]
                for index = length, 2, -1 do entries[index] = entries[index - 1] end
                entries[1] = incoming
                return result
            end
            recoveryOk, recoveryError = BridgeEnsureNativeGraveyardContainer('forge-player-1')
            oldA = BridgeState.physicalContainerByInstanceId[':old-a']
            oldB = BridgeState.physicalContainerByInstanceId[':old-b']
            incoming = BridgeState.physicalContainerByInstanceId[':recovered']
            entryCount = BridgeTestArrayLength(deck.getObjects() or {})
        ");

        Assert.True(lua.Globals.Get("recoveryOk").Boolean,
            $"recovery={lua.Globals.Get("recoveryError").ToPrintString()}; logs={CapturedLogsTail(lua)}");
        Assert.Equal(3, lua.Globals.Get("entryCount").Number);
        Assert.Equal("grave-deck", lua.Globals.Get("oldA").Table.Get("deckGuid").String);
        Assert.Equal("grave-deck", lua.Globals.Get("oldB").Table.Get("deckGuid").String);
        Assert.Equal("grave-deck", lua.Globals.Get("incoming").Table.Get("deckGuid").String);
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
            bridgeTest.autoStackOverlappingStagedCards = true
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
            nativeEntryCount = BridgeTestArrayLength(bridgeTest.graveyardDeck.getObjects() or {})
            duplicateRepresentationCount = BridgeTestDuplicateGraveyardInstanceCount()
            autoStackCount = bridgeTest.autoStackCount or 0
            mutationCommitCount = BridgeTestCountLogToken('MUTATION_COMMIT')
            mutationAbortCount = BridgeTestCountLogToken('MUTATION_ABORT')
        ");

        Assert.Equal(202, lua.Globals.Get("finalApplied").Number);
        Assert.Equal(4, lua.Globals.Get("finalCount").Number);
        Assert.Equal(":old1", lua.Globals.Get("final1").String);
        Assert.Equal(":old2", lua.Globals.Get("final2").String);
        Assert.Equal(":new1", lua.Globals.Get("final3").String);
        Assert.Equal(":new2", lua.Globals.Get("final4").String);
        Assert.Equal("Deck", lua.Globals.Get("containerTag").String);
        Assert.Equal(4, lua.Globals.Get("nativeEntryCount").Number);
        Assert.Equal(0, lua.Globals.Get("duplicateRepresentationCount").Number);
        Assert.Equal(0, lua.Globals.Get("autoStackCount").Number);
        Assert.Equal(1, lua.Globals.Get("mutationCommitCount").Number);
        Assert.Equal(0, lua.Globals.Get("mutationAbortCount").Number);
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

    [Fact]
    public void ThoughtScourDeferredGraveyardSettlementRetainsItsTransactionCompletion()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            local queue = {}
            local tx = {
                token='session:1:1:135', sessionId='session', eventSessionGeneration=1,
                physicalTransactionGeneration=1, forgeSequence=37, firstEventSequence=135,
                lastEventSequence=138, state='APPLYING', queue=queue, pendingPhysicalEvents={}
            }
            BridgeState.eventQueue = queue
            BridgeState.eventDrainTransaction = tx
            local event = {sequence=137, kind='card_moved', seatId='forge-player-1',
                sourceZone='stack', destinationZone='graveyard', cardInstanceId='forge:session:35',
                cardName='Thought Scour', forgeSequence=37}
            tx.pendingPhysicalEvents[137] = true
            completionCount = 0
            event._bridgePhysicalCompletion = function(ok, reason)
                completionCount = completionCount + 1
                if ok then tx.pendingPhysicalEvents[137] = nil end
            end
            local deferredEvents = {}
            deferredEvents[1] = event
            local batch = {seatId='forge-player-1', requiredCount=2,
                deferredEvents=deferredEvents, deferredPendingCount=0}
            local rawApply = BridgeApplyStructuredCardMove
            BridgeApplyStructuredCardMove = function(candidate)
                delayedDeferredEvent = candidate
                return true, nil
            end
            deferredInputCount = BridgeTableSize(batch.deferredEvents)
            BridgeStartDeferredGraveyardEvents(tx, batch)
            callbackRetainedAfterDispatch = delayedDeferredEvent ~= nil
                and delayedDeferredEvent._bridgePhysicalCompletion ~= nil
            pendingBeforeCallback = batch.deferredPendingCount
            local delayedCompletion = delayedDeferredEvent and delayedDeferredEvent._bridgePhysicalCompletion or nil
            if delayedCompletion ~= nil then delayedCompletion(true, nil) end
            pendingAfterCallback = batch.deferredPendingCount
            transactionPendingAfterCallback = tx.pendingPhysicalEvents[137] ~= nil
            if delayedCompletion ~= nil then delayedCompletion(true, nil) end
            BridgeApplyStructuredCardMove = rawApply
        ");

        Assert.True(lua.Globals.Get("callbackRetainedAfterDispatch").Boolean,
            $"input={lua.Globals.Get("deferredInputCount").ToPrintString()} pending={lua.Globals.Get("pendingBeforeCallback").ToPrintString()} logs={CapturedLogsTail(lua)}");
        Assert.Equal(1, lua.Globals.Get("pendingBeforeCallback").Number);
        Assert.Equal(0, lua.Globals.Get("pendingAfterCallback").Number);
        Assert.False(lua.Globals.Get("transactionPendingAfterCallback").Boolean);
        Assert.Equal(1, lua.Globals.Get("completionCount").Number);
    }

    [Fact]
    public void MentalNoteCompoundLibraryBatchDefersStackArrivalUntilOwnedGraveyardIsReady()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            BridgeState.lastAppliedEventSequence = 95
            BridgeState.cardNameByInstanceId[':island'] = 'Island'
            BridgeState.cardNameByInstanceId[':ashiok'] = 'Ashiok'
            BridgeState.cardNameByInstanceId[':note'] = 'Mental Note'
            BridgeState.cardNameByInstanceId[':swamp'] = 'Swamp'
            local island = BridgeTestCreateCard(':island', 'Island', 'loose-island')
            local ashiok = BridgeTestCreateCard(':ashiok', 'Ashiok', 'loose-ashiok')
            local swamp = BridgeTestCreateCard(':swamp', 'Swamp', 'loose-swamp')
            local note = BridgeTestCreateCard(':note', 'Mental Note', 'loose-note')
            note._inLibrary = false
            note._inHand = false
            note._lastPosition = {x=2, y=1, z=0}
            BridgeRecordLooseCardIdentity(':note', 'loose-note', 'forge-player-1', 'stack')
            BridgeTestQueueExtractionCards({island, ashiok, swamp})
            local rawApply = BridgeApplyStructuredCardMove
            BridgeApplyStructuredCardMove = function(event)
                if event ~= nil and event.sequence == 98 then
                    stackApplyCount = (stackApplyCount or 0) + 1
                end
                return rawApply(event)
            end
            local rawStartDeferred = BridgeStartDeferredGraveyardEvents
            BridgeStartDeferredGraveyardEvents = function(tx, batch)
                deferredStartCount = (deferredStartCount or 0) + 1
                deferredEventCount = BridgeTestArrayLength(batch and batch.deferredEvents or {})
                return rawStartDeferred(tx, batch)
            end
            BridgeTestSetEventQueue(
                {sequence=96, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':island', cardName='Island', forgeSequence=19},
                {sequence=97, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':ashiok', cardName='Ashiok', forgeSequence=19},
                {sequence=98, kind='card_moved', seatId='forge-player-1', sourceZone='stack', destinationZone='graveyard', cardInstanceId=':note', cardName='Mental Note', forgeSequence=19},
                {sequence=99, kind='draw', seatId='forge-player-1', sourceZone='library', destinationZone='hand', cardInstanceId=':swamp', cardName='Swamp', forgeSequence=19}
            )
            BridgeProcessEventQueue()
            local ledger = BridgeZoneLedger('forge-player-1', 'graveyard')
            finalApplied = BridgeState.lastAppliedEventSequence
            graveyardCount = BridgeTestArrayLength(ledger or {})
            graveyard1 = ledger[1]
            graveyard2 = ledger[2]
            graveyardDeckCount = BridgeTestArrayLength(bridgeTest.graveyardDeck.entries or {})
            deckEntry1 = bridgeTest.graveyardDeck.entries[1] and bridgeTest.graveyardDeck.entries[1].instanceId or 'nil'
            deckEntry2 = bridgeTest.graveyardDeck.entries[2] and bridgeTest.graveyardDeck.entries[2].instanceId or 'nil'
            deckEntry3 = bridgeTest.graveyardDeck.entries[3] and bridgeTest.graveyardDeck.entries[3].instanceId or 'nil'
            swampGuid = BridgeState.physicalByInstanceId[':swamp']
            swampZone = swampGuid and BridgeState.physicalZoneByGuid[swampGuid] or nil
            mutationAbortCount = BridgeTestCountLogToken('MUTATION_ABORT')
            stackApplyCount = stackApplyCount or 0
            deferredStartCount = deferredStartCount or 0
            deferredEventCount = deferredEventCount or 0
            desyncState = tostring(desyncReason)
        ");

        Assert.True(lua.Globals.Get("finalApplied").Number == 99,
            $"finalApplied={lua.Globals.Get("finalApplied").ToPrintString()} graveyard={lua.Globals.Get("graveyardCount").ToPrintString()} deck={lua.Globals.Get("graveyardDeckCount").ToPrintString()} entries={lua.Globals.Get("deckEntry1").ToPrintString()},{lua.Globals.Get("deckEntry2").ToPrintString()},{lua.Globals.Get("deckEntry3").ToPrintString()} stackApply={lua.Globals.Get("stackApplyCount").ToPrintString()} deferredStart={lua.Globals.Get("deferredStartCount").ToPrintString()} deferredEvents={lua.Globals.Get("deferredEventCount").ToPrintString()} swamp={lua.Globals.Get("swampZone").ToPrintString()} aborts={lua.Globals.Get("mutationAbortCount").ToPrintString()} desync={lua.Globals.Get("desyncState").ToPrintString()}");
        Assert.Equal(3, lua.Globals.Get("graveyardCount").Number);
        Assert.True(lua.Globals.Get("graveyardDeckCount").Number == 3,
            $"deck={lua.Globals.Get("graveyardDeckCount").ToPrintString()} entries={lua.Globals.Get("deckEntry1").ToPrintString()},{lua.Globals.Get("deckEntry2").ToPrintString()},{lua.Globals.Get("deckEntry3").ToPrintString()} stackApply={lua.Globals.Get("stackApplyCount").ToPrintString()} deferredStart={lua.Globals.Get("deferredStartCount").ToPrintString()} deferredEvents={lua.Globals.Get("deferredEventCount").ToPrintString()} desync={lua.Globals.Get("desyncState").ToPrintString()}");
        Assert.Equal(":island", lua.Globals.Get("graveyard1").String);
        Assert.Equal(":ashiok", lua.Globals.Get("graveyard2").String);
        Assert.Equal("hand", lua.Globals.Get("swampZone").String);
        Assert.Equal(0, lua.Globals.Get("mutationAbortCount").Number);
        // One call enrolls the resolving spell in the transaction; the second
        // is the single physical dispatch after the native graveyard Deck is
        // ready. The exact graveyard ledger above proves that dispatch did not
        // create a second physical Thought Scour representation.
        Assert.Equal(2, lua.Globals.Get("stackApplyCount").Number);
    }

    [Fact]
    public void MentalNoteBatchTracksBaseAndFinalExpectedGraveyardCounts()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            BridgeState.cardNameByInstanceId[':g1'] = 'Swamp'
            BridgeState.cardNameByInstanceId[':g2'] = 'Forest'
            BridgeState.cardNameByInstanceId[':g3'] = 'Island'
            BridgeState.cardNameByInstanceId[':mill-a'] = 'Mental Note'
            BridgeState.cardNameByInstanceId[':mill-b'] = 'Harmonized Trio'
            BridgeState.cardNameByInstanceId[':note'] = 'Mental Note'
            local tx = {
                token='session:1:1:300', sessionId='session', eventSessionGeneration=1,
                physicalTransactionGeneration=1, forgeSequence=17, firstEventSequence=300,
                lastEventSequence=303, state='APPLYING', events={},
                eventCount=3,
                pendingPhysicalEvents={}
            }
            tx.events[1] = {sequence=301, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':mill-a', cardName='Mental Note', forgeSequence=17}
            tx.events[2] = {sequence=302, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':mill-b', cardName='Harmonized Trio', forgeSequence=17}
            tx.events[3] = {sequence=303, kind='card_moved', seatId='forge-player-1', sourceZone='stack', destinationZone='graveyard', cardInstanceId=':note', cardName='Mental Note', forgeSequence=17}
            local existingGraveyard = {':g1', ':g2', ':g3'}
            BridgeZoneLedger = function(seatId, zone)
                if seatId == 'forge-player-1' and zone == 'graveyard' then
                    return existingGraveyard
                end
                return {}
            end
            BridgeLogAtomicGraveyardTopology = function(seatId, batch, phase)
                return {graveyardEntries={}}
            end
            BridgeBuildAtomicLibraryToGraveyardBatches(tx)
            local batch = tx.graveyardMutationBatchesBySeatId['forge-player-1']
            baseCount = BridgeTableSize(batch and batch.baseExpectedInstances or {})
            finalCount = BridgeTableSize(batch and batch.finalExpectedInstances or {})
        ");

        Assert.Equal(5, lua.Globals.Get("baseCount").Number);
        Assert.Equal(6, lua.Globals.Get("finalCount").Number);
    }

    [Fact]
    public void ThoughtScourStagingAvoidsPlayerOneLandRowAndPositionsFinalDeckAtGraveyard()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            local graveyardAnchor = {x=1.7714, y=2.0, z=-12.2921}
            local landAnchor = {x=6.5, y=2.0, z=-11.5}
            BridgeGraveyardPosition = function(seatId) return graveyardAnchor end
            BridgeState.lastAppliedEventSequence = 67
            BridgeState.cardNameByInstanceId[':mill-a'] = 'Island'
            BridgeState.cardNameByInstanceId[':mill-b'] = 'Mental Note'
            BridgeState.cardNameByInstanceId[':scour'] = 'Thought Scour'
            BridgeState.cardNameByInstanceId[':draw'] = 'Harmonized Trio'
            BridgeState.cardNameByInstanceId[':land'] = 'Island'
            local millA = BridgeTestCreateCard(':mill-a', 'Island', 'mill-a')
            local millB = BridgeTestCreateCard(':mill-b', 'Mental Note', 'mill-b')
            local draw = BridgeTestCreateCard(':draw', 'Harmonized Trio', 'draw')
            local scour = BridgeTestCreateCard(':scour', 'Thought Scour', 'scour')
            scour._inLibrary = false
            scour._inHand = false
            scour._lastPosition = {x=2, y=1, z=0}
            BridgeRecordLooseCardIdentity(':scour', 'scour', 'forge-player-1', 'stack')
            local land = BridgeTestCreateCard(':land', 'Island', 'battlefield-land')
            land._inLibrary = false
            land._inHand = false
            land._lastPosition = landAnchor
            BridgeRecordLooseCardIdentity(':land', 'battlefield-land', 'forge-player-1', 'battlefield')
            BridgeTestQueueExtractionCards({millA, millB, draw})
            BridgeTestSetEventQueue(
                {sequence=68, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':mill-a', cardName='Island', forgeSequence=71},
                {sequence=69, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':mill-b', cardName='Mental Note', forgeSequence=71},
                {sequence=70, kind='card_moved', seatId='forge-player-1', sourceZone='stack', destinationZone='graveyard', cardInstanceId=':scour', cardName='Thought Scour', forgeSequence=71},
                {sequence=71, kind='draw', seatId='forge-player-1', sourceZone='library', destinationZone='hand', cardInstanceId=':draw', cardName='Harmonized Trio', forgeSequence=71}
            )
            BridgeProcessEventQueue()
            local function distance(left, right)
                local dx = left.x - right.x
                local dz = left.z - right.z
                return math.sqrt(dx * dx + dz * dz)
            end
            stageAFromLand = distance(millA._lastPosition, landAnchor)
            stageBFromLand = distance(millB._lastPosition, landAnchor)
            stageSeparation = distance(millA._lastPosition, millB._lastPosition)
            finalDeckDistance = distance(bridgeTest.graveyardDeck._lastPosition, graveyardAnchor)
            finalApplied = BridgeState.lastAppliedEventSequence
            deckCount = BridgeTestArrayLength(bridgeTest.graveyardDeck.entries)
            landStillLoose = land._inDeck ~= true
            landMapping = BridgeState.physicalByInstanceId[':land']
            landZone = landMapping and BridgeState.physicalZoneByGuid[landMapping] or nil
            drawGuid = BridgeState.physicalByInstanceId[':draw']
            drawZone = drawGuid and BridgeState.physicalZoneByGuid[drawGuid] or nil
            aborts = BridgeTestCountLogToken('MUTATION_ABORT')
        ");

        Assert.Equal(71, lua.Globals.Get("finalApplied").Number);
        Assert.True(lua.Globals.Get("stageAFromLand").Number > 3.25);
        Assert.True(lua.Globals.Get("stageBFromLand").Number > 3.25);
        Assert.True(lua.Globals.Get("stageSeparation").Number > 3.25);
        Assert.True(lua.Globals.Get("finalDeckDistance").Number <= 0.001);
        Assert.Equal(3, lua.Globals.Get("deckCount").Number);
        Assert.True(lua.Globals.Get("landStillLoose").Boolean);
        Assert.Equal("battlefield-land", lua.Globals.Get("landMapping").String);
        Assert.Equal("battlefield", lua.Globals.Get("landZone").String);
        Assert.Equal("hand", lua.Globals.Get("drawZone").String);
        Assert.Equal(0, lua.Globals.Get("aborts").Number);
    }

    [Fact]
    public void AtomicGraveyardDestinationRejectsBattlefieldDeckAndUnexpectedTrackedCard()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            local graveyardAnchor = {x=1.7714, y=2.0, z=-12.2921}
            local landAnchor = {x=6.5, y=2.0, z=-11.5}
            BridgeGraveyardPosition = function(seatId) return graveyardAnchor end
            BridgeState.cardNameByInstanceId[':a'] = 'Island'
            BridgeState.cardNameByInstanceId[':b'] = 'Mental Note'
            BridgeState.cardNameByInstanceId[':land'] = 'Island'
            local batch = {seatId='forge-player-1', expectedInstances={{instanceId=':a'}, {instanceId=':b'}}}
            local foreignDeck
            foreignDeck = {
                tag='Deck', _position=landAnchor,
                getGUID=function() return 'foreign-deck' end,
                getPosition=function() return foreignDeck._position end,
                getObjects=function() return {{guid='expected-a'}, {guid='contained-foreign'}} end
            }
            BridgeState.physicalContainedInstanceIdByGuid['expected-a'] = ':a'
            BridgeState.physicalContainedInstanceIdByGuid['contained-foreign'] = ':land'
            wrongLocationOk, wrongLocationReason = BridgeValidateAtomicGraveyardDestination(batch, foreignDeck)
            foreignDeck._position = graveyardAnchor
            foreignOk, foreignReason = BridgeValidateAtomicGraveyardDestination(batch, foreignDeck)
        ");

        Assert.False(lua.Globals.Get("wrongLocationOk").Boolean);
        Assert.Contains("outside its seat anchor radius", lua.Globals.Get("wrongLocationReason").String);
        Assert.True(!lua.Globals.Get("foreignOk").Boolean,
            $"foreignOk={lua.Globals.Get("foreignOk").ToPrintString()} reason={lua.Globals.Get("foreignReason").ToPrintString()}");
        Assert.Contains("unexpected", lua.Globals.Get("foreignReason").String);
    }

    [Fact]
    public void AtomicGraveyardStagingUsesTheSafeSideForPlayerTwoGeometry()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            local graveyardAnchor = {x=1.7476, y=2.0, z=12.3162}
            local landAnchor = {x=6.5, y=2.0, z=19.0}
            BridgeGraveyardPosition = function(seatId) return graveyardAnchor end
            local first = BridgeAtomicGraveyardStagingPosition('forge-player-2', 1, {stagedPhysicalMoves={}})
            local second = BridgeAtomicGraveyardStagingPosition('forge-player-2', 2, {stagedPhysicalMoves={}})
            local function distance(left, right)
                local dx = left.x - right.x
                local dz = left.z - right.z
                return math.sqrt(dx * dx + dz * dz)
            end
            firstLandDistance = distance(first, landAnchor)
            secondLandDistance = distance(second, landAnchor)
            stageDistance = distance(first, second)
            firstOnSafeSide = first.x < graveyardAnchor.x
            secondOnSafeSide = second.x < first.x
        ");

        Assert.True(lua.Globals.Get("firstLandDistance").Number > 3.25);
        Assert.True(lua.Globals.Get("secondLandDistance").Number > 3.25);
        Assert.True(lua.Globals.Get("stageDistance").Number > 3.25);
        Assert.True(lua.Globals.Get("firstOnSafeSide").Boolean);
        Assert.True(lua.Globals.Get("secondOnSafeSide").Boolean);
    }

    [Fact]
    public void ThoughtScourTwoCardMillAndDrawPreservesPhysicalAtomicity()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            BRIDGE_SEATS['forge-player-2'] = BRIDGE_SEATS['forge-player-2'] or {}
            BRIDGE_SEATS['forge-player-2'].libraryZoneGuid = 'lib-zone'
            BRIDGE_SEATS['forge-player-2'].graveyardAnchor = {x=-2, y=0, z=0}
            BRIDGE_SEATS['forge-player-2'].handTransform = {position={x=-8, y=2, z=0}, rotation={x=0, y=0, z=0}}
            BRIDGE_SEATS['forge-player-2'].tableSideZ = 1
            BridgeState.lastAppliedEventSequence = 800
            BridgeState.cardNameByInstanceId[':opp86'] = 'Baleful Strix'
            BridgeState.cardNameByInstanceId[':opp98'] = 'Recruiter of the Guard'
            BridgeState.cardNameByInstanceId[':draw15'] = 'Stitcher\'s Supplier'
            local mill1 = BridgeTestCreateCard(':opp86', 'Baleful Strix', 'loose-opp86')
            local mill2 = BridgeTestCreateCard(':opp98', 'Recruiter of the Guard', 'loose-opp98')
            local draw1 = BridgeTestCreateCard(':draw15', 'Stitcher\'s Supplier', 'loose-draw15')
            BridgeTestQueueExtractionCards({mill1, mill2, draw1})
            drawSeenInHand = false
            local rawTryGetSeatHandObjects = BridgeTryGetSeatHandObjects
            BridgeTryGetSeatHandObjects = function(seatId)
                local handObjects, handError = rawTryGetSeatHandObjects(seatId)
                if handObjects ~= nil then
                    for _, handObject in ipairs(handObjects) do
                        local handGuid = handObject and BridgeSafeObjectGuid(handObject) or nil
                        if handObject ~= nil and (handObject._instanceId == ':draw15' or tostring(handGuid or '') == 'loose-draw15') then
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
                return rawCommit(tx)
            end
            BridgeTestSetEventQueue(
                {sequence=801, kind='card_moved', seatId='forge-player-2', sourceZone='library', destinationZone='graveyard', cardInstanceId=':opp86', cardName='Baleful Strix', forgeSequence=820},
                {sequence=802, kind='card_moved', seatId='forge-player-2', sourceZone='library', destinationZone='graveyard', cardInstanceId=':opp98', cardName='Recruiter of the Guard', forgeSequence=820},
                {sequence=803, kind='draw', seatId='forge-player-1', sourceZone='library', destinationZone='hand', cardInstanceId=':draw15', cardName='Stitcher\'s Supplier', forgeSequence=820}
            )
            BridgeProcessEventQueue()
            local oppLedger = BridgeZoneLedger('forge-player-2', 'graveyard')
            oppLedgerCount = BridgeTestArrayLength(oppLedger or {})
            oppLedger1 = oppLedger[1]
            oppLedger2 = oppLedger[2]
            drawGuid = BridgeState.physicalByInstanceId[':draw15']
            drawZone = drawGuid and BridgeState.physicalZoneByGuid[drawGuid] or nil
            drawSeat = drawGuid and BridgeState.physicalSeatByGuid[drawGuid] or nil
            finalApplied = BridgeState.lastAppliedEventSequence
            commitEnterCount = commitEnterCount or 0
            mutationCommitCount = BridgeTestCountLogToken('MUTATION_COMMIT')
            mutationAbortCount = BridgeTestCountLogToken('MUTATION_ABORT')
            stageBeginCount = BridgeTestCountLogToken('MUTATION_STAGE_BEGIN')
            extractedCount = BridgeTestCountLogToken('MUTATION_STAGE_EXTRACTED')
            destinationVerifiedCount = BridgeTestCountLogToken('MUTATION_DESTINATION_VERIFIED')
            desyncState = tostring(desyncReason)
        ");

        Assert.True(lua.Globals.Get("commitSawDrawInHand").Boolean,
            $"commitSawDrawInHand={lua.Globals.Get("commitSawDrawInHand").Boolean} finalApplied={lua.Globals.Get("finalApplied").Number} drawGuid={lua.Globals.Get("drawGuid").ToPrintString()} drawZone={lua.Globals.Get("drawZone").ToPrintString()} drawSeat={lua.Globals.Get("drawSeat").ToPrintString()} oppLedgerCount={lua.Globals.Get("oppLedgerCount").Number} stageBegin={lua.Globals.Get("stageBeginCount").Number} extracted={lua.Globals.Get("extractedCount").Number} destVerified={lua.Globals.Get("destinationVerifiedCount").Number} mutationCommit={lua.Globals.Get("mutationCommitCount").Number} mutationAbort={lua.Globals.Get("mutationAbortCount").Number} desync={lua.Globals.Get("desyncState").String} logs={CapturedLogsTail(lua)}");
        Assert.Equal(803, lua.Globals.Get("finalApplied").Number);
        Assert.Equal(2, lua.Globals.Get("oppLedgerCount").Number);
        Assert.Equal(":opp86", lua.Globals.Get("oppLedger1").String);
        Assert.Equal(":opp98", lua.Globals.Get("oppLedger2").String);
        Assert.Equal("loose-draw15", lua.Globals.Get("drawGuid").String);
        Assert.Equal("hand", lua.Globals.Get("drawZone").String);
        Assert.Equal("forge-player-1", lua.Globals.Get("drawSeat").String);
        Assert.Equal(1, lua.Globals.Get("commitEnterCount").Number);
        Assert.Equal(1, lua.Globals.Get("stageBeginCount").Number);
        Assert.Equal(2, lua.Globals.Get("extractedCount").Number);
        Assert.Equal(1, lua.Globals.Get("destinationVerifiedCount").Number);
        Assert.Equal(1, lua.Globals.Get("mutationCommitCount").Number);
        Assert.Equal(0, lua.Globals.Get("mutationAbortCount").Number);
    }

    [Fact]
    public void CompoundMutationNativeSettlementExceptionAbortsOwnedTransactionWithoutOrphaningAnimation()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            BridgeState.lastAppliedEventSequence = 93
            BridgeState.cardNameByInstanceId[':scour'] = 'Thought Scour'
            BridgeState.cardNameByInstanceId[':swamp'] = 'Swamp'
            BridgeState.cardNameByInstanceId[':note'] = 'Mental Note'
            BridgeState.cardNameByInstanceId[':supplier'] = 'Stitcher\'s Supplier'
            local scour = BridgeTestCreateCard(':scour', 'Thought Scour', 'late-scour')
            local swamp = BridgeTestCreateCard(':swamp', 'Swamp', 'late-swamp')
            local note = BridgeTestCreateCard(':note', 'Mental Note', 'late-note')
            local supplier = BridgeTestCreateCard(':supplier', 'Stitcher\'s Supplier', 'late-supplier')
            BridgeTestQueueExtractionCards({scour, swamp, supplier})
            local rawRecord = BridgeRecordGraveyardContainerEntries
            BridgeRecordGraveyardContainerEntries = function(seatId, deck, expected)
                error('simulated native null object after Deck promotion')
            end
            BridgeTestSetEventQueue(
                {sequence=94, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':scour', cardName='Thought Scour', forgeSequence=931},
                {sequence=95, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':swamp', cardName='Swamp', forgeSequence=931},
                {sequence=96, kind='card_moved', seatId='forge-player-1', sourceZone='stack', destinationZone='graveyard', cardInstanceId=':note', cardName='Mental Note', forgeSequence=931},
                {sequence=97, kind='draw', seatId='forge-player-1', sourceZone='library', destinationZone='hand', cardInstanceId=':supplier', cardName='Stitcher\'s Supplier', forgeSequence=931}
            )
            callbackOk, callbackError = pcall(BridgeProcessEventQueue)
            finalApplied = BridgeState.lastAppliedEventSequence
            animationRunning = BridgeState.animationRunning == true
            desyncLatched = BridgeState.desyncLatched == true
            activeTransaction = BridgeState.eventDrainTransaction
            runtimeStage = BridgeState.lastTtsRuntimeError and BridgeState.lastTtsRuntimeError.stage or nil
            runtimeDetail = BridgeState.lastTtsRuntimeError and BridgeState.lastTtsRuntimeError.detail or nil
            callbackExceptionCount = 0
            for _, record in ipairs(BridgeState.physicalMutationJournal or {}) do
                if record.stage == 'NATIVE_CALLBACK_EXCEPTION' then
                    callbackExceptionCount = callbackExceptionCount + 1
                end
            end
            mutationAbortCount = BridgeTestCountLogToken('MUTATION_ABORT')
            supplierGuid = BridgeState.physicalByInstanceId[':supplier']
            BridgeRecordGraveyardContainerEntries = rawRecord
        ");

        Assert.True(lua.Globals.Get("callbackOk").Boolean,
            lua.Globals.Get("callbackError").ToPrintString());
        Assert.Equal(93, lua.Globals.Get("finalApplied").Number);
        Assert.False(lua.Globals.Get("animationRunning").Boolean);
        Assert.True(lua.Globals.Get("desyncLatched").Boolean);
        Assert.True(lua.Globals.Get("activeTransaction").IsNil());
        Assert.Equal("graveyard-settlement", lua.Globals.Get("runtimeStage").String);
        Assert.Contains("simulated native null object", lua.Globals.Get("runtimeDetail").String);
        Assert.Equal(1, lua.Globals.Get("callbackExceptionCount").Number);
        Assert.True(lua.Globals.Get("mutationAbortCount").Number >= 1);
        Assert.Equal("late-supplier", lua.Globals.Get("supplierGuid").String);
    }

    [Fact]
    public void ExistingLooseGraveyardCardPlusAtomicMillBatchPromotesToDeckAndCommits()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            BridgeState.lastAppliedEventSequence = 210
            BridgeState.lastReceivedEventSequence = 215
            BridgeState.cardNameByInstanceId[':31'] = 'Harmonized Trio'
            BridgeState.cardNameByInstanceId[':16'] = 'Island'
            BridgeState.cardNameByInstanceId[':33'] = 'Mountain'
            BridgeState.cardNameByInstanceId[':38'] = 'Forest'
            BridgeState.cardNameByInstanceId[':9'] = 'Swamp'
            local looseExisting = BridgeTestCreateCard(':31', 'Harmonized Trio', 'loose-existing')
            BridgeRecordLooseCardIdentity(':31', 'loose-existing', 'forge-player-1', 'graveyard')
            local c16 = BridgeTestCreateCard(':16', 'Island', 'loose-16')
            local c33 = BridgeTestCreateCard(':33', 'Mountain', 'loose-33')
            local c38 = BridgeTestCreateCard(':38', 'Forest', 'loose-38')
            local c9 = BridgeTestCreateCard(':9', 'Swamp', 'loose-9')
            BridgeTestQueueExtractionCards({c16, c33, c38, c9})
            BridgeState.zoneLedgerBySeatAndZone['forge-player-1'] = BridgeState.zoneLedgerBySeatAndZone['forge-player-1'] or {}
            BridgeState.zoneLedgerBySeatAndZone['forge-player-1']['graveyard'] = {}
            BridgeState.zoneLedgerBySeatAndZone['forge-player-1']['graveyard'][1] = ':31'
            BridgeTestSetEventQueue(
                {sequence=211, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':16', cardName='Island', forgeSequence=215},
                {sequence=212, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':33', cardName='Mountain', forgeSequence=215},
                {sequence=213, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':38', cardName='Forest', forgeSequence=215},
                {sequence=214, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':9', cardName='Swamp', forgeSequence=215}
            )
            BridgeProcessEventQueue()
            local ledger = BridgeZoneLedger('forge-player-1', 'graveyard')
            finalApplied = BridgeState.lastAppliedEventSequence
            ledgerCount = BridgeTestArrayLength(ledger or {})
            firstLedger = ledger[1]
            lastLedger = ledger[ledgerCount]
            containerTag = bridgeTest.graveyardContainer and bridgeTest.graveyardContainer.tag or 'nil'
            looseCount = BridgeTestLooseGraveyardCardCount()
            groupCalls = bridgeTest.groupCalls or 0
            mutationCommitCount = BridgeTestCountLogToken('MUTATION_COMMIT')
            mutationAbortCount = BridgeTestCountLogToken('MUTATION_ABORT')
            desyncState = tostring(desyncReason)
        ");

        Assert.True(lua.Globals.Get("finalApplied").Number == 214,
            $"finalApplied={lua.Globals.Get("finalApplied").Number} ledgerCount={lua.Globals.Get("ledgerCount").Number} first={lua.Globals.Get("firstLedger").ToPrintString()} last={lua.Globals.Get("lastLedger").ToPrintString()} container={lua.Globals.Get("containerTag").String} looseCount={lua.Globals.Get("looseCount").Number} groupCalls={lua.Globals.Get("groupCalls").Number} mutationCommit={lua.Globals.Get("mutationCommitCount").Number} mutationAbort={lua.Globals.Get("mutationAbortCount").Number} desync={lua.Globals.Get("desyncState").String} logs={CapturedLogsTail(lua)}");
        Assert.Equal(5, lua.Globals.Get("ledgerCount").Number);
        Assert.Equal(":31", lua.Globals.Get("firstLedger").String);
        Assert.Equal(":9", lua.Globals.Get("lastLedger").String);
        Assert.Equal("Deck", lua.Globals.Get("containerTag").String);
        Assert.Equal(0, lua.Globals.Get("looseCount").Number);
        Assert.True(lua.Globals.Get("groupCalls").Number >= 1);
        Assert.Equal(1, lua.Globals.Get("mutationCommitCount").Number);
        Assert.Equal(0, lua.Globals.Get("mutationAbortCount").Number);
        Assert.Equal("nil", lua.Globals.Get("desyncState").String);
    }

    [Fact]
    public void NewMatchCleanupReturnsLiveHandCardsWhenHandApiLagsAfterMove()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            BridgeState.libraryInsertionHandReleaseByGuid = {}
            local seatId = 'forge-player-1'
            local cardA = BridgeTestCreateCard(':handA', 'Hand A', 'live-A')
            local cardB = BridgeTestCreateCard(':handB', 'Hand B', 'live-B')
            cardA._inHand = true
            cardB._inHand = true
            cardA.use_hands = false
            cardB.use_hands = false
            cardA.setPosition = function(position)
                cardA._lastPosition = position
                cardA._inHand = false
            end
            cardB.setPosition = function(position)
                cardB._lastPosition = position
                cardB._inHand = false
            end
            local rawHandObjects = BridgeTryGetSeatHandObjects
            BridgeTryGetSeatHandObjects = function()
                return {cardA, cardB}, nil
            end
            local inserted = {}
            local function finishA(ok, err)
                inserted[1] = ok
                insertErrorA = tostring(err or 'nil')
                BridgeInsertPhysicalCardIntoLibrary(seatId, cardB, 'NORMAL', function(okB, errB)
                    inserted[2] = okB
                    insertErrorB = tostring(errB or 'nil')
                end, ':handB')
            end
            BridgeInsertPhysicalCardIntoLibrary(seatId, cardA, 'NORMAL', finishA, ':handA')
            finalSuccess = inserted[1] == true and inserted[2] == true
            finalFirstError = tostring(insertErrorA or 'nil')
            finalSecondError = tostring(insertErrorB or 'nil')
        ");

        Assert.True(lua.Globals.Get("finalSuccess").Boolean,
            $"first={lua.Globals.Get("finalFirstError").String} second={lua.Globals.Get("finalSecondError").String} logs={CapturedLogsTail(lua)}");
    }

    [Fact]
    public void NilForgeSequenceEventsRemainSingletonTransactions()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            BridgeState.lastAppliedEventSequence = 40
            BridgeState.cardNameByInstanceId[':n1'] = 'Card N1'
            BridgeState.cardNameByInstanceId[':n2'] = 'Card N2'
            local n1 = BridgeTestCreateCard(':n1', 'Card N1', 'loose-n1')
            local n2 = BridgeTestCreateCard(':n2', 'Card N2', 'loose-n2')
            BridgeTestQueueExtractionCards({n1, n2})
            commitRanges = {}
            local rawCommit = BridgeCommitEventMutationTransaction
            BridgeCommitEventMutationTransaction = function(tx)
                commitRanges[BridgeTestArrayLength(commitRanges) + 1] = {
                    first = tx and tx.firstEventSequence or nil,
                    last = tx and tx.lastEventSequence or nil,
                    count = tx and tx.eventCount or nil
                }
                return rawCommit(tx)
            end
            function BridgeWaitTime(callback, delay) end
            BridgeTestSetEventQueue(
                {sequence=41, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':n1', cardName='Card N1'},
                {sequence=42, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':n2', cardName='Card N2'}
            )
            BridgeProcessEventQueue()
            local ledger = BridgeZoneLedger('forge-player-1', 'graveyard')
            ledgerCount = BridgeTestArrayLength(ledger or {})
            ledger1 = ledger[1]
            commitCount = BridgeTestArrayLength(commitRanges or {})
            firstCommitCount = commitRanges[1] and commitRanges[1].count or nil
            queueLenAfter = #(BridgeState.eventQueue or {})
            queueHeadAfter = BridgeState.eventQueue[1] and BridgeState.eventQueue[1].sequence or nil
            finalApplied = BridgeState.lastAppliedEventSequence
            desyncState = tostring(desyncReason)
        ");

        Assert.Equal(41, lua.Globals.Get("finalApplied").Number);
        Assert.Equal(1, lua.Globals.Get("commitCount").Number);
        Assert.Equal(1, lua.Globals.Get("firstCommitCount").Number);
        Assert.Equal(1, lua.Globals.Get("ledgerCount").Number);
        Assert.Equal(":n1", lua.Globals.Get("ledger1").String);
        Assert.Equal(1, lua.Globals.Get("queueLenAfter").Number);
        Assert.Equal(42, lua.Globals.Get("queueHeadAfter").Number);
        Assert.Equal("nil", lua.Globals.Get("desyncState").String);
    }

    [Fact]
    public void DifferentPositiveForgeSequencesAreNotBatchedTogether()
    {
        var lua = NewProbe();
        ExecuteProbe(lua, @"
            BridgeTestInitAtomicHarness()
            BridgeState.lastAppliedEventSequence = 50
            BridgeState.cardNameByInstanceId[':p1'] = 'Card P1'
            BridgeState.cardNameByInstanceId[':p2'] = 'Card P2'
            local p1 = BridgeTestCreateCard(':p1', 'Card P1', 'loose-p1')
            local p2 = BridgeTestCreateCard(':p2', 'Card P2', 'loose-p2')
            BridgeTestQueueExtractionCards({p1, p2})
            commitRanges = {}
            local rawCommit = BridgeCommitEventMutationTransaction
            BridgeCommitEventMutationTransaction = function(tx)
                commitRanges[BridgeTestArrayLength(commitRanges) + 1] = {
                    first = tx and tx.firstEventSequence or nil,
                    last = tx and tx.lastEventSequence or nil,
                    count = tx and tx.eventCount or nil,
                    forgeSequence = tx and tx.forgeSequence or nil
                }
                return rawCommit(tx)
            end
            function BridgeWaitTime(callback, delay) end
            BridgeTestSetEventQueue(
                {sequence=51, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':p1', cardName='Card P1', forgeSequence=901},
                {sequence=52, kind='card_moved', seatId='forge-player-1', sourceZone='library', destinationZone='graveyard', cardInstanceId=':p2', cardName='Card P2', forgeSequence=902}
            )
            BridgeProcessEventQueue()
            local ledger = BridgeZoneLedger('forge-player-1', 'graveyard')
            ledgerCount = BridgeTestArrayLength(ledger or {})
            ledger1 = ledger[1]
            commitCount = BridgeTestArrayLength(commitRanges or {})
            firstCommitCount = commitRanges[1] and commitRanges[1].count or nil
            firstCommitForgeSequence = commitRanges[1] and commitRanges[1].forgeSequence or nil
            queueLenAfter = #(BridgeState.eventQueue or {})
            queueHeadAfter = BridgeState.eventQueue[1] and BridgeState.eventQueue[1].sequence or nil
            finalApplied = BridgeState.lastAppliedEventSequence
            desyncState = tostring(desyncReason)
        ");

        Assert.Equal(51, lua.Globals.Get("finalApplied").Number);
        Assert.Equal(1, lua.Globals.Get("commitCount").Number);
        Assert.Equal(1, lua.Globals.Get("firstCommitCount").Number);
        Assert.Equal(901, lua.Globals.Get("firstCommitForgeSequence").Number);
        Assert.Equal(1, lua.Globals.Get("ledgerCount").Number);
        Assert.Equal(":p1", lua.Globals.Get("ledger1").String);
        Assert.Equal(1, lua.Globals.Get("queueLenAfter").Number);
        Assert.Equal(52, lua.Globals.Get("queueHeadAfter").Number);
        Assert.Equal("nil", lua.Globals.Get("desyncState").String);
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
                        batch.baseExpectedInstances = {}
                        for _, instanceId in pairs(stagedLedger) do
                            table.insert(batch.baseExpectedInstances, {
                                instanceId = instanceId,
                                cardName = BridgeState.cardNameByInstanceId[instanceId]
                            })
                        end
                        batch.expectedInstances = batch.baseExpectedInstances
                        batch.finalExpectedInstances = nil
                        for index = 1, (tonumber(tx.eventCount) or 0) do
                            local event = tx.events[index]
                            if event ~= nil and tostring(event.kind or '') == 'card_moved'
                                and tostring(event.destinationZone or '') == 'graveyard'
                                and tostring(event.sourceZone or '') ~= 'library'
                                and tostring(event.seatId or '') == tostring(seatId) then
                                local finalExpected = {}
                                for _, entry in pairs(BridgeTestNormalizeSequence(batch.baseExpectedInstances or {})) do
                                    table.insert(finalExpected, {
                                        instanceId = entry and entry.instanceId or nil,
                                        cardName = entry and entry.cardName or nil
                                    })
                                end
                                if event.cardInstanceId ~= nil then
                                    table.insert(finalExpected, {
                                        instanceId = event.cardInstanceId,
                                        cardName = BridgeState.cardNameByInstanceId[event.cardInstanceId]
                                    })
                                end
                                batch.finalExpectedInstances = finalExpected
                            end
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
                local productionAssertGraveyardObjectShape = BridgeAssertGraveyardObjectShape
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
                    groupCalls = 0,
                    promotePutCount = 0,
                    containedReassignCount = 0,
                    forceMissingDeckAfterPromotion = false,
                    forceUnstableSettlement = false,
                    reassignContainedEveryPut = true,
                    nativeDeckZeroBasedIndices = true,
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
                    entries = {},
                    getObjects = function()
                        local out = {}
                        bridgeTest.forEachArrayEntry(bridgeTest.libraryDeck.entries, function(entry)
                            out[BridgeTestArrayLength(out) + 1] = {
                                guid = entry and entry.guid or nil,
                                nickname = entry and entry.nickname or nil,
                                index = BridgeTestArrayLength(out) + 1
                            }
                        end)
                        return out
                    end,
                    putObject = function(object, position)
                        if object ~= nil then
                            object._inLibrary = true
                            object._inDeck = true
                            object._inHand = false
                        end
                        bridgeTest.libraryDeck.entries[BridgeTestArrayLength(bridgeTest.libraryDeck.entries) + 1] = {
                            guid = object and object.getGUID and object.getGUID() or nil,
                            nickname = object and object.name or nil,
                            index = BridgeTestArrayLength(bridgeTest.libraryDeck.entries) + 1
                        }
                        return bridgeTest.libraryDeck
                    end
                }
                bridgeTest.graveyardDeck = {
                    tag = 'Deck',
                    _lastPosition = {x=0, y=0, z=0},
                    getGUID = function()
                        bridgeTest.groupDeckGuidReads = (bridgeTest.groupDeckGuidReads or 0) + 1
                        if bridgeTest.groupDeckUnreadyGuidReads ~= nil
                            and bridgeTest.groupDeckGuidReads <= bridgeTest.groupDeckUnreadyGuidReads then
                            return nil
                        end
                        return 'grave-deck'
                    end,
                    entries = {}
                }
                bridgeTest.graveyardDeck.getPosition = function() return bridgeTest.graveyardDeck._lastPosition end
                bridgeTest.graveyardDeck.setPosition = function(position) bridgeTest.graveyardDeck._lastPosition = position end
                bridgeTest.graveyardDeck.setPositionSmooth = function(position, smooth, collide)
                    bridgeTest.graveyardDeck._lastPosition = position
                end
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
                            -- TTS exposes native Deck positions separately
                            -- from its Lua result array; production positions
                            -- begin at zero.
                            index = bridgeTest.nativeDeckZeroBasedIndices and (outIndex - 1) or outIndex
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
                    local containedGuid = bridgeTest.preserveContainedSourceGuid == true
                        and object and object.getGUID and object.getGUID()
                        or bridgeTest.nextContainedGuid(instanceId)
                    local entry = {
                        instanceId = instanceId,
                        name = cardName,
                        guid = containedGuid
                    }
                    local entryCount = BridgeTestArrayLength(bridgeTest.graveyardDeck.entries)
                    if tonumber(position) == 0 and bridgeTest.insideNativeGroup ~= true then
                        for entryIndex = entryCount, 1, -1 do
                            bridgeTest.graveyardDeck.entries[entryIndex + 1] = bridgeTest.graveyardDeck.entries[entryIndex]
                        end
                        bridgeTest.graveyardDeck.entries[1] = entry
                    else
                        bridgeTest.graveyardDeck.entries[entryCount + 1] = entry
                    end
                    if object ~= nil then
                        object._inDeck = bridgeTest.keepContainedLooseAliases ~= true
                        object._inLibrary = false
                        object._inHand = false
                    end
                    if bridgeTest.reassignContainedEveryPut then bridgeTest.reassignContainedGuids() end
                    bridgeTest.graveyardContainer = bridgeTest.graveyardDeck
                    return bridgeTest.graveyardDeck
                end

                function group(objects)
                    bridgeTest.groupCalls = bridgeTest.groupCalls + 1
                    if bridgeTest.groupNeverFormsDeck == true then return objects end
                    if bridgeTest.groupDeckDiscoveryDelay ~= nil then
                        bridgeTest.pendingGroupObjects = objects
                        bridgeTest.graveyardContainer = nil
                        return {}
                    end
                    bridgeTest.graveyardContainer = bridgeTest.graveyardDeck
                    bridgeTest.insideNativeGroup = true
                    for _, object in ipairs(objects or {}) do
                        if object ~= nil and object._nativeAutoStack ~= nil then
                            bridgeTest.forEachArrayEntry(object._nativeAutoStack, function(member)
                                bridgeTest.graveyardDeck.putObject(member, 0)
                            end)
                        else
                            bridgeTest.graveyardDeck.putObject(object, 0)
                        end
                    end
                    bridgeTest.insideNativeGroup = false
                    if bridgeTest.groupReturnsArray then return {bridgeTest.graveyardDeck} end
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
                    card.getPosition = function() return card._lastPosition or {x=0, y=0, z=0} end
                    local function setCardPosition(position)
                        card._lastPosition = position
                        bridgeTest.stagedPositionCount = (bridgeTest.stagedPositionCount or 0) + 1
                        if bridgeTest.autoStackOverlappingStagedCards == true
                            and bridgeTest.stagedPositionCount >= 3
                            and bridgeTest.autoStackCount == nil then
                            local nearest = nil
                            local nearestDistance = nil
                            bridgeTest.forEachArrayEntry(bridgeTest.allCards, function(other)
                                if bridgeTest.autoStackCount == nil and other ~= card
                                    and other._lastPosition ~= nil and other._inDeck ~= true
                                    and other._inLibrary ~= true then
                                    local dx = (tonumber(position.x) or 0) - (tonumber(other._lastPosition.x) or 0)
                                    local dz = (tonumber(position.z) or 0) - (tonumber(other._lastPosition.z) or 0)
                                    local distance = math.sqrt((dx * dx) + (dz * dz))
                                    if distance < 2.6 and (nearestDistance == nil or distance < nearestDistance) then
                                        nearest = other
                                        nearestDistance = distance
                                    end
                                end
                            end)
                            if nearest ~= nil then
                                local nativeStack = {nearest, card}
                                nearest._nativeAutoStack = nativeStack
                                card._nativeAutoStack = nativeStack
                                bridgeTest.autoStackCount = 1
                                bridgeTest.autoStackFirstInstanceId = nearest._instanceId
                                bridgeTest.autoStackSecondInstanceId = card._instanceId
                            end
                        end
                    end
                    card.setPositionSmooth = function(position, smooth, collide) setCardPosition(position) end
                    card.setPosition = function(position) setCardPosition(position) end
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

                function BridgeTestDuplicateGraveyardInstanceCount()
                    local seen = {}
                    local duplicates = 0
                    bridgeTest.forEachArrayEntry(bridgeTest.graveyardDeck.entries or {}, function(entry)
                        local instanceId = tostring(entry and entry.instanceId or '')
                        if seen[instanceId] == true then
                            duplicates = duplicates + 1
                        else
                            seen[instanceId] = true
                        end
                    end)
                    return duplicates
                end

                function BridgeTestGraveyardInstanceCount(expectedInstanceId)
                    local count = 0
                    bridgeTest.forEachArrayEntry(bridgeTest.graveyardDeck.entries or {}, function(entry)
                        if entry ~= nil and entry.instanceId == expectedInstanceId then count = count + 1 end
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
                    if bridgeTest.pendingGroupObjects ~= nil then
                        bridgeTest.groupDiscoveryChecks = (bridgeTest.groupDiscoveryChecks or 0) + 1
                        if bridgeTest.groupDiscoveryChecks >= bridgeTest.groupDeckDiscoveryDelay then
                            local pending = bridgeTest.pendingGroupObjects
                            bridgeTest.pendingGroupObjects = nil
                            bridgeTest.graveyardContainer = bridgeTest.graveyardDeck
                            bridgeTest.forEachArrayEntry(pending, function(object)
                                bridgeTest.graveyardDeck.putObject(object, 0)
                            end)
                        end
                    end
                    local container = bridgeTest.graveyardContainer
                    if container ~= nil then
                        local guid = container.getGUID and container.getGUID() or nil
                        if excludeGuid == nil or guid ~= excludeGuid then return container end
                    end
                    for _, card in ipairs(bridgeTest.allCards or {}) do
                        if card ~= nil and card.tag == 'Card' and card._inDeck ~= true then
                            local guid = card.getGUID and card.getGUID() or nil
                            if guid ~= nil and guid ~= excludeGuid
                                and BridgeState.physicalSeatByGuid[guid] == seatId
                                and BridgeState.physicalZoneByGuid[guid] == 'graveyard' then
                                return card
                            end
                        end
                    end
                    return nil
                end

                function BridgeAssertGraveyardObjectShape(seatId, context, containmentOwner)
                    if bridgeTest.useProductionGraveyardShape == true then
                        return productionAssertGraveyardObjectShape(seatId, context,
                            containmentOwner or bridgeTest.activeContainmentOwner)
                    end
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

                local function bridgeHarnessTakeFromLibrary(cardInstanceId, expectedName, position, faceDown, callback)
                    bridgeTest.extractionIndex = bridgeTest.extractionIndex + 1
                    local index = bridgeTest.extractionIndex
                    local card = nil
                    -- A physical retry must not advance the simulated library
                    -- merely because TTS re-entered the extraction callback.
                    -- Resolve the exact authoritative instance first, then
                    -- fall back to name matching for legacy tests.
                    bridgeTest.forEachArrayEntry(bridgeTest.extractionCards, function(candidate)
                        if card == nil and candidate ~= nil and candidate._extracted ~= true
                            and (cardInstanceId == nil
                                or tostring(candidate._instanceId or '') == tostring(cardInstanceId))
                            and (expectedName == nil or expectedName == ''
                                or BridgeCardNameMatches(candidate.name, expectedName)
                                or tostring(candidate._instanceId or '') == tostring(cardInstanceId or '')) then
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

                function BridgeTakeContainedLibraryCardByIdentity(cardInstanceId, position, smooth, callback)
                    local expectedName = BridgeState.cardNameByInstanceId[cardInstanceId] or nil
                    bridgeHarnessTakeFromLibrary(cardInstanceId, expectedName, position, smooth, callback)
                end

                function BridgeTakeTopCardFromLibrary(deck, expectedName, position, faceDown, callback)
                    bridgeHarnessTakeFromLibrary(nil, expectedName, position, faceDown, callback)
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
