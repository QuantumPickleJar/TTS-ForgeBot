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
    public void BattlefieldMovement_ReleasesHandsAndUsesAdjustedBlueLandAnchor()
    {
        Assert.Contains("land = {x = 6.5, y = 2.0, z = 19.0}", Script);
        Assert.Contains("creature = {x = 7.0, y = 2.0, z = 3.5}", Script);

        var releaseHand = Script.IndexOf("object.use_hands = false", StringComparison.Ordinal);
        var directMove = Script.IndexOf("object.setPosition(destination)", StringComparison.Ordinal);
        Assert.True(releaseHand >= 0);
        Assert.True(directMove > releaseHand);
    }

    [Fact]
    public void HumanIntent_IsStagedUntilDropAndRollbackRestoresPhysicalState()
    {
        var pickup = Script.IndexOf("function onObjectPickUp", StringComparison.Ordinal);
        var drop = Script.IndexOf("function onObjectDrop", StringComparison.Ordinal);
        var submit = Script.IndexOf("BridgeSubmitChoice(intent.decisionId, intent.action.actionId, submissionSource)", drop, StringComparison.Ordinal);

        Assert.True(pickup >= 0);
        Assert.True(drop > pickup);
        Assert.True(submit > drop);
        Assert.Contains("useHands = object.use_hands", Script);
        Assert.Contains("object.use_hands = intent.useHands", Script);
        Assert.Contains("if decision ~= nil then BridgeRenderDecision(decision) end", Script);
    }

    [Fact]
    public void TurnYield_UsesForgePassAndTurnEventsDriveTtsPresentation()
    {
        Assert.DoesNotContain("function onPlayerTurnEnd", Script);
        Assert.Contains("function BridgePressEndTurn", Script);
        Assert.Contains("click_function = \"BridgePressEndTurn\"", Script);
        Assert.Contains("type = \"BlockSquare\"", Script);
        Assert.Contains("object.setRotation({0, seat.tableSideZ < 0 and 180 or 0, 0})", Script);
        Assert.Contains("BridgeState.yieldSeatId = decision.seatId", Script);
        Assert.Contains("if action.type == \"pass_priority\"", Script);
        Assert.Contains("BridgeState.currentTurnSeatId = event.activeSeatId", Script);
        Assert.Contains("BridgeRecordAuthoritativeTurn(BridgeState.currentTurnSeatId, tonumber(event.turnNumber or 0))", Script);
        Assert.Contains("function BridgeRecordAuthoritativeTurn", Script);
        Assert.Contains("TURN\\n", Script);
        Assert.Contains("WHITE TURN", Script);
        Assert.Contains("BLUE TURN", Script);
        Assert.DoesNotContain("Turns.turn_color", Script);
    }

    [Fact]
    public void PassAndYield_HaveDistinctPhysicalSemantics()
    {
        Assert.Contains("function BridgePressPass", Script);
        Assert.Contains("Pass exactly this Forge priority decision", Script);
        Assert.Contains("BridgeState.yieldSeatId = nil", Script);
        Assert.Contains("function BridgePressEndTurn", Script);
        Assert.Contains("BridgeState.yieldSeatId = decision.seatId", Script);
        Assert.Contains("action.type == \"pass_priority\"", Script);
    }

    [Fact]
    public void ConfirmedSelection_StagesExactActionsWithoutPreemptiveZoneMutation()
    {
        Assert.Contains("selectedActionIds", Script);
        Assert.Contains("decision.minSelections or 1", Script);
        Assert.Contains("decision.maxSelections or 1", Script);
        Assert.Contains("DONE /\\nCONFIRM", Script);
        Assert.Contains("CANCEL /\\nUNDO", Script);
        Assert.Contains("this Forge TUI transport cannot atomically submit multiple selections yet", Script);
        Assert.DoesNotContain("BridgeState.physicalZoneByGuid[intent.guid] = \"graveyard\"", Script);
    }

    [Fact]
    public void AttackAndBlockLanesPreserveLateralSpacingAndMappings()
    {
        Assert.Contains("attackLaneZ", Script);
        Assert.Contains("blockerLaneZ", Script);
        Assert.Contains("x = position.x", Script);
        Assert.Contains("BridgeState.attackOriginByGuid[guid]", Script);
        Assert.Contains("function BridgeReturnAttackPresentation", Script);
        var attackLane = Script.IndexOf("function BridgeMoveToAttackLane", StringComparison.Ordinal);
        var blockerLane = Script.IndexOf("function BridgeMoveToBlockerLane", attackLane, StringComparison.Ordinal);
        var attackLaneBody = Script[attackLane..blockerLane];
        Assert.DoesNotContain("towardCenter.x * 2", attackLaneBody);
    }

    [Fact]
    public void CombatSelections_UsePhysicalDropPreviewAndExplicitForgeFinishActions()
    {
        Assert.Contains("function BridgeEnsureContextualCompletionControl", Script);
        Assert.Contains("DONE ATTACKING", Script);
        Assert.Contains("DONE BLOCKING", Script);
        Assert.Contains("finish_attacking", Script);
        Assert.Contains("finish_blocking", Script);
        Assert.Contains("BridgeMoveToAttackLane(intent.seatId, object)", Script);
        Assert.Contains("BridgeMoveToBlockerLane(intent.seatId, object)", Script);
        Assert.DoesNotContain("BridgeSubmitChoice(decision.decisionId, action.actionId)\n        return\n    end\n\n    if object.tag == \"Card\" and decision.requiresConfirmation", Script);
    }

    [Fact]
    public void CombatDrop_AcceptsExplicitLanePlacementOrStandardPickupDropSelection()
    {
        Assert.Contains("local droppedInLane", Script);
        Assert.Contains("math.abs(current.z - laneZ) <= 1.35", Script);
        Assert.Contains("combat selection accepted in place", Script);
        Assert.Contains("combat drop accepted", Script);
    }

    [Fact]
    public void StaleDecision_IsIgnoredWhenAuthoritativeEventsAlreadyAdvanced()
    {
        Assert.Contains("function BridgeShouldIgnoreStaleDecision", Script);
        Assert.Contains("if decision.kind ~= \"main_priority\" then", Script);
        Assert.Contains("ignoring stale main-priority decision", Script);
        Assert.Contains("decision.eventCursor", Script);
        Assert.Contains("BridgeState.lastAppliedEventSequence", Script);
        Assert.Contains("decision.prioritySeatId", Script);
        Assert.Contains("BridgeDecisionOffersActionType(decision, \"play_land\")", Script);
    }

    [Fact]
    public void NonMainPriorityDecisions_HidePassAndYieldControls()
    {
        Assert.Contains("function BridgeHideMainPriorityControls", Script);
        Assert.Contains("BridgeState.endTurnObjectGuidBySeatId", Script);
        Assert.Contains("BridgeState.passObjectGuidBySeatId", Script);
        Assert.Contains("BridgeHideMainPriorityControls()", Script);
    }

    [Fact]
    public void DeferredDecisions_WaitForEventCursorBeforeRenderingHighlights()
    {
        Assert.Contains("function BridgeShouldDeferDecision", Script);
        Assert.Contains("function BridgeTryPresentPendingDecision", Script);
        Assert.Contains("BridgeState.pendingDecision", Script);
        Assert.Contains("gating decision", Script);
        Assert.Contains("BridgeTryPresentPendingDecision(\"event-applied\")", Script);
    }

    [Fact]
    public void GenericNumericDecisions_ExposePhysicalOptionButtons()
    {
        Assert.Contains("function BridgeEnsureDecisionOptionControls", Script);
        Assert.Contains("function BridgeChooseDecisionOption", Script);
        Assert.Contains("CHOOSE OPTION", Script);
        Assert.Contains("BridgeState.optionControlGuids", Script);
    }

    [Fact]
    public void AttackerAndBlockerStatus_CopyUsesPhysicalInstructions()
    {
        Assert.Contains("DECLARE ATTACKERS", Script);
        Assert.Contains("Drag/select highlighted creatures into attack row", Script);
        Assert.Contains("DECLARE BLOCKERS", Script);
        Assert.Contains("Drag/select highlighted creatures into block row", Script);
    }

    [Fact]
    public void ManaBanksReuseTableCountersAndDisplayForgeAbsolutePool()
    {
        Assert.Contains("BRIDGE_MANA_COUNTER_SOURCES", Script);
        Assert.Contains("source.clone", Script);
        Assert.Contains("counter.setVar(\"val\", amount)", Script);
        Assert.Contains("event.kind == \"mana_pool_changed\"", Script);
        Assert.Contains("seatSnapshot.manaPool", Script);
        Assert.Contains("lifeCounter.getPosition()", Script);
        Assert.Contains("seat.manaBankOffset", Script);
    }

    [Fact]
    public void StatusPanelAndPhaseEventsClearStalePhysicalChoices()
    {
        Assert.Contains("function BridgeEnsureStatusPanel", Script);
        Assert.Contains("CURRENT TURN:", Script);
        Assert.Contains("PHASE:", Script);
        Assert.Contains("FORGE INITIALIZING", Script);
        Assert.Contains("BridgeClearHighlights()", Script);
        Assert.Contains("BridgeState.lastDecision = nil", Script);
    }

    [Fact]
    public void LoadEntersPreparationAndStartResumeResetAreExplicit()
    {
        var onLoad = Script.IndexOf("function BridgeOnLoad", StringComparison.Ordinal);
        var next = Script.IndexOf("function BridgeShowPreparationReadiness", onLoad, StringComparison.Ordinal);
        var onLoadBody = Script[onLoad..next];
        Assert.Contains("BridgeDoctor(function(report)", onLoadBody);
        Assert.Contains("BridgeInitializeInteractiveUi()", onLoadBody);
        Assert.Contains("BridgeScheduleCompanionRetry(1)", onLoadBody);
        Assert.DoesNotContain("BridgeAttachToActiveSession", onLoadBody);
        Assert.Contains("function BridgePressStartMatch", Script);
        Assert.Contains("function BridgePressResume", Script);
        Assert.Contains("function BridgePressNewMatch", Script);
        Assert.Contains("Click it again within 10 seconds", Script);
    }

    [Fact]
    public void SetupCallbacks_DeferLifecycleWorkToInternalHandlers()
    {
        var newMatchStart = Script.IndexOf("function BridgePressNewMatch", StringComparison.Ordinal);
        var newMatchEnd = Script.IndexOf("function BridgeDoPressNewMatch", newMatchStart, StringComparison.Ordinal);
        var newMatchClickBody = Script[newMatchStart..newMatchEnd];
        Assert.Contains("setup-click:new-match", newMatchClickBody);
        Assert.Contains("BridgeWaitFrames(function()", newMatchClickBody);
        Assert.Contains("BridgeDoPressNewMatch", newMatchClickBody);
        Assert.DoesNotContain("BridgeSpawnResetConfirmationControl()", newMatchClickBody);
        Assert.DoesNotContain("BridgeClearResetConfirmationControl()", newMatchClickBody);

        var confirmStart = Script.IndexOf("function BridgePressConfirmNewMatch", StringComparison.Ordinal);
        var confirmEnd = Script.IndexOf("function BridgeDoPressConfirmNewMatch", confirmStart, StringComparison.Ordinal);
        var confirmClickBody = Script[confirmStart..confirmEnd];
        Assert.Contains("setup-click:confirm", confirmClickBody);
        Assert.Contains("BridgeWaitFrames(function()", confirmClickBody);
        Assert.Contains("BridgeDoPressConfirmNewMatch", confirmClickBody);
        Assert.DoesNotContain("BridgeResetSession()", confirmClickBody);

        Assert.Contains("setup-deferred:new-match", Script);
        Assert.Contains("setup-confirm-spawned", Script);
        Assert.Contains("setup-deferred:confirm", Script);
        Assert.Contains("function BridgeDoPressStartMatch", Script);
        Assert.Contains("function BridgeDoPressResume", Script);
    }

    [Fact]
    public void StartPath_EmitsOrderedMarkersAndUsesSeatPlayerGuards()
    {
        Assert.Contains("START-01 click", Script);
        Assert.Contains("START-02 deferred-handler", Script);
        Assert.Contains("START-03 health-request", Script);
        Assert.Contains("START-04 health-response", Script);
        Assert.Contains("START-05 deck-check-begin", Script);
        Assert.Contains("START-06 deck-check-complete", Script);
        Assert.Contains("START-07 session-start-request", Script);
        Assert.Contains("START-08 session-start-response", Script);
        Assert.Contains("START-09 event-session-prepare", Script);
        Assert.Contains("START-10 snapshot-request", Script);
        Assert.Contains("START-11 snapshot-response", Script);
        Assert.Contains("START-12 physical-bootstrap-begin", Script);
        Assert.Contains("START-13 loose-card-staging", Script);
        Assert.Contains("START-14 library-indexing", Script);
        Assert.Contains("START-15 hand-reconstruction", Script);
        Assert.Contains("START-16 battlefield-reconstruction", Script);
        Assert.Contains("START-17 mapping-complete", Script);
        Assert.Contains("START-18 event-poll-start", Script);
        Assert.Contains("START-19 decision-poll-start", Script);
        Assert.Contains("START-20 ready", Script);
        Assert.Contains("body.adapterState == \"starting\"", Script);
        Assert.Contains("function BridgeTryGetSeatHandObjects", Script);
        Assert.Contains("function BridgeTryGetSeatHandTransform", Script);

        var stageStart = Script.IndexOf("function BridgeStageSeatCardsForBootstrap", StringComparison.Ordinal);
        var stageEnd = Script.IndexOf("function BridgeHttp.handleResponse", stageStart, StringComparison.Ordinal);
        var stageBody = Script[stageStart..stageEnd];
        Assert.DoesNotContain("Player[seat.ttsColor].getHandObjects()", stageBody);
    }

    [Fact]
    public void StartupBootstrap_UsesLiveLibraryObjectsForStagingAndDeckTakeSafety()
    {
        var materializeStart = Script.IndexOf("function BridgeMaterializeSeatSnapshot", StringComparison.Ordinal);
        var materializeEnd = Script.IndexOf("function BridgePlaceSnapshotCard", materializeStart, StringComparison.Ordinal);
        var materializeBody = Script[materializeStart..materializeEnd];
        Assert.Contains("BridgeGetLiveObjectByGuid(guid)", materializeBody);
        Assert.Contains("BridgeGetLiveObjectByGuid(seat.libraryZoneGuid)", materializeBody);
        Assert.DoesNotContain("local libraryZone = getObjectFromGUID(seat.libraryZoneGuid)", materializeBody);

        var takeStart = Script.IndexOf("function BridgeTakeCardFromDeckByIdentity", StringComparison.Ordinal);
        var takeEnd = Script.IndexOf("function BridgeTakeNamedCardFromDeck", takeStart, StringComparison.Ordinal);
        var takeBody = Script[takeStart..takeEnd];
        Assert.Contains("BridgeObjectIsUsable(deck)", takeBody);
        Assert.Contains("local deckGuid = BridgeSafeObjectGuid(deck)", takeBody);
        Assert.Contains("BridgeGetLiveObjectByGuid(deckGuid)", takeBody);
    }

    [Fact]
    public void SnapshotVisualState_UsesLiveGuidReacquisitionForCountersAndLife()
    {
        var visualStart = Script.IndexOf("function BridgeApplySeatSnapshotVisualState", StringComparison.Ordinal);
        var visualEnd = Script.IndexOf("function BridgeEnsureManaBank", visualStart, StringComparison.Ordinal);
        var visualBody = Script[visualStart..visualEnd];
        Assert.Contains("BridgeGetLiveObjectByGuid(seat.lifeCounterGuid)", visualBody);
        Assert.Contains("guid and BridgeGetLiveObjectByGuid(guid) or nil", visualBody);

        var manaStart = Script.IndexOf("function BridgeEnsureManaBank", StringComparison.Ordinal);
        var manaEnd = Script.IndexOf("function BridgeSetManaBank", manaStart, StringComparison.Ordinal);
        var manaBody = Script[manaStart..manaEnd];
        Assert.Contains("BridgeGetLiveObjectByGuid(seat.lifeCounterGuid)", manaBody);
        Assert.Contains("BridgeGetLiveObjectByGuid(BRIDGE_MANA_COUNTER_SOURCES[color])", manaBody);
        Assert.Contains("BridgeObjectIsUsable(object) and BridgeSafeObjectName(object) == expectedName", manaBody);
    }

    [Fact]
    public void PlayerTargets_AreMachineTypedAndUseConfiguredSeatSurface()
    {
        Assert.Contains("action.targetKind == \"player\"", Script);
        Assert.Contains("action.targetSeatId", Script);
        Assert.Contains("targetSurfaceGuid", Script);
        Assert.Contains("click_function = \"BridgeSelectPlayerTarget\"", Script);
        Assert.Contains("function BridgeSpawnPlayerTargetControl", Script);
        Assert.Contains("click_function = \"BridgeSelectPlayerTargetControl\"", Script);
        Assert.DoesNotContain("action.displayName == \"Player", Script);
    }

    [Fact]
    public void ExistingCardModules_AreUpdatedByAbsoluteAuthoritativeState()
    {
        Assert.Contains("APIobjGetPropData", Script);
        Assert.Contains("local BRIDGE_UNIFIED_PROPERTY = \"_MTG_Simplified_UNIFIED\"", Script);
        Assert.Contains("function BridgeEnsureTableEncoded(object)", Script);
        Assert.Contains("APIobjectExists", Script);
        Assert.Contains("APIobjIsPropEnabled", Script);
        Assert.Contains("function BridgeSetDerivedStats(object, power, toughness)", Script);
        Assert.Contains("unified.displayPowTou = true", Script);
        Assert.Contains("function BridgeSetOwnerController(object, ownerSeatId, controllerSeatId)", Script);
        Assert.Contains("unified.displayOwnership", Script);
        Assert.Contains("function BridgeSetPhasedState(object, phased)", Script);
        Assert.Contains("data.mtg_phased = phased == true", Script);
        Assert.Contains("local BRIDGE_KEYWORDS_PROPERTY = \"πKeywords\"", Script);
        Assert.Contains("data[property] = enabled and 1 or 0", Script);
        Assert.Contains("APIobjSetPropData", Script);
        Assert.Contains("APIrebuildButtons", Script);
    }

    [Fact]
    public void ManualDrawCannotMutateForgeAuthoritativeLibrary()
    {
        var drawStart = Script.IndexOf("function drawSwap", StringComparison.Ordinal);
        var drawEnd = Script.IndexOf("function BridgeGetHealth", drawStart, StringComparison.Ordinal);
        var drawFunction = Script[drawStart..drawEnd];

        Assert.Contains("manual Draw is disabled", drawFunction);
        Assert.DoesNotContain(".deal(", drawFunction);
    }

    [Fact]
    public void DeveloperSyncDumpIncludesMappingsZonesAndCursors()
    {
        Assert.Contains("function BridgeDumpSyncState", Script);
        Assert.Contains("physicalByInstanceId", Script);
        Assert.Contains("physicalZoneByGuid", Script);
        Assert.Contains("lastReceivedEventSequence", Script);
        Assert.Contains("lastAppliedEventSequence", Script);
    }

    [Fact]
    public void SnapshotBootstrap_MapsUniqueInstancesAndPreservesForgeLibraryPosition()
    {
        Assert.Contains("/api/v1/embodiment/snapshot", Script);
        Assert.Contains("BridgeState.physicalByInstanceId[mapping.card.cardInstanceId] = guid", Script);
        Assert.Contains("count - card.zonePosition", Script);
        Assert.Contains("BridgeNormalizeCardName(card.cardName)", Script);
        Assert.Contains("hidden identities redacted", Script);
    }

    [Fact]
    public void SnapshotBootstrap_ExcludesExistingTableUtilityStacksFromPlayerAssets()
    {
        Assert.Contains("assetMaxAbsX = 40", Script);
        Assert.Contains("math.abs(position.x) > seat.assetMaxAbsX", Script);
        Assert.Contains("libraryAssetRadius = 4", Script);
        Assert.Contains("if object.tag == \"Deck\" then", Script);
        Assert.Contains("dx * dx + dz * dz <= radius * radius", Script);
    }

    [Fact]
    public void SnapshotBootstrap_EstablishesEventSessionBeforeBuildingInstanceMappings()
    {
        var bootstrap = Script.IndexOf("function BridgeBootstrapCurrentSnapshot", StringComparison.Ordinal);
        var prepare = Script.IndexOf("BridgePrepareEventSession(sessionId, true)", bootstrap, StringComparison.Ordinal);
        var requestSnapshot = Script.IndexOf("BridgeGetEmbodimentSnapshot", bootstrap, StringComparison.Ordinal);

        Assert.True(bootstrap >= 0);
        Assert.True(prepare > bootstrap);
        Assert.True(requestSnapshot > prepare);
        Assert.Contains("BridgePrepareEventSession(sessionId, false)", Script);
    }

    [Fact]
    public void ActiveSessionAttach_RendersDecisionOnlyAfterSnapshotMappingCompletes()
    {
        var attach = Script.IndexOf("function BridgeAttachToActiveSession", StringComparison.Ordinal);
        var initializationWait = Script.IndexOf("BridgeWaitForForgeInitialization(1, done)", attach, StringComparison.Ordinal);
        var bootstrap = Script.IndexOf("BridgeBootstrapWhenAvailable(body.sessionId, 1", attach, StringComparison.Ordinal);
        var decision = Script.IndexOf("BridgeFetchDecisionAfterAttach()", bootstrap, StringComparison.Ordinal);
        var callbackEnd = Script.IndexOf("end)", bootstrap, StringComparison.Ordinal);

        Assert.True(attach >= 0);
        Assert.True(initializationWait > attach);
        Assert.True(bootstrap > attach);
        Assert.True(decision > bootstrap);
        Assert.True(decision < callbackEnd);
    }

    [Fact]
    public void AuthoritativeDraw_TakesVerifiedNamedCardFromPhysicalDeckWithoutChatLeak()
    {
        Assert.Contains("if event.kind == \"draw\"", Script);
        Assert.Contains("BridgeFindSeatLibraryDeckWithCard(seat, expectedName)", Script);
        Assert.Contains("deck.takeObject({", Script);
        Assert.Contains("index = matched.index", Script);
        Assert.Contains("BridgeCardNameMatches(taken.getName(), expectedName)", Script);
        Assert.Contains("card identity redacted", Script);
    }

    [Fact]
    public void ImporterDeckExtraction_UsesCurrentNameMatchedIndexAndVerifiesReturnedCard()
    {
        Assert.Contains("function BridgeTakeNamedCardFromDeck", Script);
        Assert.Contains("BridgeCardNameMatches(contained.nickname or contained.name, expectedName)", Script);
        Assert.Contains("index = matched.index", Script);
        Assert.Contains("physical library extraction mismatched authoritative identity", Script);
        Assert.Contains("BridgeSetPhysicalFaceDown(object, seat, card.faceDown == true)", Script);
        Assert.Contains("BridgeSetPhysicalFaceDown(object, seat, event.faceDown == true)", Script);
    }

    [Fact]
    public void CardOrientation_IsAbsoluteAndDoesNotUseAnimatedFlip()
    {
        Assert.Contains("faceUpRotation = {x = 0, y = 180, z = 0}", Script);
        Assert.Contains("faceUpRotation = {x = 0, y = 0, z = 0}", Script);
        Assert.Contains("o.setRotation(rotation)", Script);
        Assert.DoesNotContain("object.flip()", Script);
    }

    [Fact]
    public void MainPriority_MappedCardMustBelongToDecisionSeatHand()
    {
        Assert.Contains("function BridgeBuildSeatHandGuidSet", Script);
        Assert.Contains("local observedInDecisionHand", Script);
        Assert.Contains("BridgeState.physicalSeatByGuid[mappedGuid] == decision.seatId", Script);
        Assert.Contains("candidateGuid[mappedGuid] == true", Script);
        Assert.Contains("BridgeState.physicalZoneByGuid[guid] == \"hand\"", Script);
        Assert.Contains("BridgeObjectIsOnSeatSide(object, decisionSeat)", Script);
    }

    [Fact]
    public void CardDrop_UsesDeliberatePhysicalDisplacementInsteadOfTtsHandClassification()
    {
        Assert.Contains("local dx = current.x - intent.position.x", Script);
        Assert.Contains("if dx * dx + dz * dz < 1.0 then", Script);
        Assert.DoesNotContain("function BridgeObjectIsInHand", Script);
    }

    [Fact]
    public void CancelledPhysicalIntent_PreservesItsAuthoritativeInstanceMapping()
    {
        Assert.Contains("physicalSeatId = BridgeState.physicalSeatByGuid[object.getGUID()]", Script);
        Assert.Contains("physicalZone = BridgeState.physicalZoneByGuid[object.getGUID()]", Script);
        Assert.Contains("BridgeState.physicalSeatByGuid[intent.guid] = intent.physicalSeatId", Script);
        Assert.Contains("BridgeState.physicalZoneByGuid[intent.guid] = intent.physicalZone", Script);
        var rollbackStart = Script.IndexOf("function BridgeRollbackPendingIntent", StringComparison.Ordinal);
        var rollbackEnd = Script.IndexOf("function BridgeBootstrapCurrentSnapshot", rollbackStart, StringComparison.Ordinal);
        var rollback = Script[rollbackStart..rollbackEnd];
        Assert.DoesNotContain("BridgeState.physicalSeatByGuid[intent.guid] = nil", rollback);
        Assert.DoesNotContain("BridgeState.physicalZoneByGuid[intent.guid] = nil", rollback);
    }

    [Fact]
    public void MissingTableDecoration_DoesNotStopAuthoritativeSynchronization()
    {
        Assert.Contains("optional physical counter decoration skipped", Script);
        Assert.Contains("optional physical keyword decoration skipped", Script);
        Assert.Contains("return true, 0.1, nil", Script);
    }

    [Fact]
    public void BattlefieldPlacement_ProbesForAFreePhysicalSlot()
    {
        Assert.Contains("function BridgeBattlefieldPositionOccupied", Script);
        Assert.Contains("if not BridgeBattlefieldPositionOccupied(candidate) then", Script);
        Assert.Contains("dx * dx + dz * dz < 1.5", Script);
        Assert.Contains("card.battlefieldKind == \"land\"", Script);
        Assert.Contains("function BridgeAnnotateSnapshotBattlefieldKinds", Script);
        Assert.Contains("event.kind == \"land_played\"", Script);
        Assert.Contains("landByInstanceId[card.cardInstanceId]", Script);
    }

    [Fact]
    public void DirectHandToBattlefieldMove_WaitsForSemanticLandPlacement()
    {
        Assert.Contains("if event.sourceZone ~= \"hand\" then", Script);
        Assert.Contains("BridgeMoveToBattlefield(event, object, \"land\")", Script);
    }

    [Fact]
    public void StructuredBattlefieldMove_IsNotRepeatedByInstanceLessSemanticResolution()
    {
        Assert.Contains("event.kind == \"spell_resolved\"", Script);
        Assert.Contains("if event.cardInstanceId == nil then return true, 0.1 end", Script);
        Assert.Contains("BridgeResolvePhysicalCard(event, \"stack\")", Script);
    }

    [Fact]
    public void CastSpellIntent_TracksStackIdentityAndResolvedGraveyardBinding()
    {
        Assert.Contains("pendingCastBySeatId", Script);
        Assert.Contains("BridgeState.physicalZoneByGuid[intent.guid] = \"stack\"", Script);
        Assert.Contains("BridgeState.pendingCastBySeatId[intent.seatId]", Script);
        Assert.Contains("BridgeResolveResolvedSpellObject", Script);
        Assert.Contains("BridgeRecordLooseCardIdentity(event.cardInstanceId, pendingCast.guid, event.seatId, \"stack\")", Script);
        Assert.Contains("BridgeState.pendingCastBySeatId[event.seatId] = nil", Script);
        Assert.Contains("local pendingObject = pendingCast ~= nil and getObjectFromGUID(pendingCast.guid) or nil", Script);
        Assert.Contains("if pendingObject ~= nil and BridgeCardNameMatches(pendingObject.getName(), event.cardName) then", Script);
    }

    [Fact]
    public void PhysicalStack_UsesDedicatedStableTablePosition()
    {
        Assert.Contains("BRIDGE_STACK_POSITION = {x = -5.5, y = 1.6, z = 0}", Script);
        Assert.Contains("object.setPosition(BRIDGE_STACK_POSITION)", Script);
    }

    [Fact]
    public void AuthoritativePlayerState_UpdatesConfiguredSeatLifeCounter()
    {
        Assert.Contains("if event.kind == \"player_state\" and event.lifeTotal ~= nil then", Script);
        Assert.Contains("lifeCounter.setValue(event.lifeTotal)", Script);
    }

    [Fact]
    public void SnapshotBootstrap_IndexesLibrariesWithoutUnpackingThem()
    {
        Assert.Contains("deck.getObjects() or {}", Script);
        Assert.Contains("for _, contained in ipairs(containedCards)", Script);
        Assert.Contains("if zone.name == \"library\" or cardIndex > #cards then", Script);
        Assert.DoesNotContain("BridgeExtractOneDeck", Script);
        Assert.DoesNotContain("physical deck remainder disappeared", Script);
    }

    [Fact]
    public void SnapshotBootstrap_RetriesIncompleteRuntimeInventoryWithoutPublishingPartialMappings()
    {
        Assert.Contains("function BridgeTryBootstrapSeatSnapshot", Script);
        Assert.Contains("if attempt < 4 then", Script);
        Assert.Contains("BridgeTryBootstrapSeatSnapshot(seatSnapshot, attempt + 1, callback)", Script);

        var reconcile = Script.IndexOf("function BridgeReconcileSeatSnapshot", StringComparison.Ordinal);
        var collectMapping = Script.IndexOf("table.insert(mappings", reconcile, StringComparison.Ordinal);
        var publishMapping = Script.IndexOf("BridgeState.physicalByInstanceId[mapping.card.cardInstanceId]", reconcile, StringComparison.Ordinal);
        Assert.True(collectMapping > reconcile);
        Assert.True(publishMapping > collectMapping);
    }

    [Fact]
    public void SnapshotBootstrap_StagesLooseCardsNearLibrariesBeforeRemapping()
    {
        Assert.Contains("BridgeStageSeatCardsForBootstrap(snapshot)", Script);
        Assert.Contains("function BridgeStageSeatCardsForBootstrap(snapshot)", Script);
        Assert.Contains("IsGameCardCandidate(object, seatId, context)", Script);
        Assert.Contains("BridgeTryGetSeatHandObjects(seatId)", Script);
        Assert.Contains("BridgeNearestSeatIdForPosition", Script);
        Assert.Contains("function BridgeLibraryStagingPosition", Script);
        Assert.Contains("o.setPosition(staging)", Script);
    }

    [Fact]
    public void GameCardEligibility_UsesReusableCandidateFilterWithoutNameSpecialCases()
    {
        Assert.Contains("function IsGameCardCandidate(object, seatId, context)", Script);
        Assert.Contains("function BridgeBuildGameCardContext(snapshot)", Script);
        Assert.Contains("BridgeCollectSeatAssets(seatSnapshot.seatId, seatSnapshot", Script);
        Assert.Contains("BridgeCardFootprintLooksLikeMtg", Script);
        Assert.Contains("BridgeCardMetadataLooksLikeMtg", Script);
        Assert.DoesNotContain("How to Play", Script);
    }

    [Fact]
    public void GraveyardAndExileMoves_PreferSeatZoneAnchorsOverBattlefieldFallback()
    {
        Assert.Contains("BridgeGraveyardPosition(event.seatId)", Script);
        Assert.Contains("BridgeResolveSeatZoneAnchor(seatId, \"graveyard\")", Script);
        Assert.Contains("BridgeResolveSeatZoneAnchor(event.seatId, \"exile\")", Script);
        Assert.Contains("BridgeResolveSeatZoneAnchor(seatSnapshot.seatId, \"graveyard\")", Script);
        Assert.Contains("BridgeResolveSeatZoneAnchor(seatSnapshot.seatId, \"exile\")", Script);
        Assert.Contains("BridgeFindNamedZoneObjectForSeat", Script);
        Assert.Contains("no graveyard anchor configured for seat", Script);
        Assert.Contains("no exile anchor configured for seat", Script);
    }

    [Fact]
    public void CardNameNormalization_UsesImporterPrimaryNameLineOnly()
    {
        Assert.Contains("string.find(normalized, \"\\n\", 1, true)", Script);
        Assert.Contains("string.find(normalized, \"\\r\", 1, true)", Script);
        Assert.Contains("string.sub(normalized, 1, lineBreak - 1)", Script);
    }

    [Fact]
    public void StructuredZoneAndTapChanges_UseInstanceMappingAndAbsoluteState()
    {
        Assert.Contains("if event.kind == \"card_moved\"", Script);
        Assert.Contains("if event.kind == \"tap_changed\"", Script);
        Assert.Contains("BridgeSetPhysicalTapped(object, event.tapped == true)", Script);
        Assert.Contains("local targetY = base.y + (tapped and 90 or 0)", Script);
        Assert.Contains("o.setRotationSmooth({base.x, targetY, base.z}", Script);
    }

    [Fact]
    public void StructuredCardMove_UsesAuthoritativeRecoveryOrderWithoutCrossZoneGuessing()
    {
        Assert.Contains("local attemptedZones = {}", Script);
        Assert.Contains("object = tryResolveFromZone(event.sourceZone)", Script);
        Assert.Contains("local idempotent = tryResolveFromZone(event.destinationZone)", Script);
        Assert.Contains("authoritativeSource=", Script);
        Assert.Contains("authoritativeDestination=", Script);
        Assert.DoesNotContain("for _, zoneName in ipairs({\"hand\", \"battlefield\", \"graveyard\", \"stack\", \"exile\", \"library\"})", Script);
        Assert.DoesNotContain("table.insert(fallbackZones", Script);
    }

    [Fact]
    public void StructuredCardMove_RecoversDeadGuidsAndPerformsFreshLibraryInventorySelection()
    {
        Assert.Contains("BridgeState.physicalByInstanceId[event.cardInstanceId] = nil", Script);
        Assert.Contains("BridgeTakeCardFromDeckByIdentity", Script);
        Assert.Contains("physical library inventory has no card matching authoritative identity", Script);
        Assert.DoesNotContain("mapped deck-contained identity does not match the authoritative card name", Script);
        Assert.DoesNotContain("authoritative draw identity does not match physical top-of-library card", Script);
    }

    [Fact]
    public void SnapshotBootstrap_TracksContainedLibraryAsNameMultiplicityNotContainedGuidIdentity()
    {
        Assert.DoesNotContain("libraryContainedGuidByInstanceId", Script);
        Assert.DoesNotContain("libraryContainerGuidByInstanceId", Script);
        Assert.DoesNotContain("BridgeAssignContainedLibraryIdentity", Script);
        Assert.DoesNotContain("BridgeClearContainedLibraryIdentity", Script);
        Assert.Contains("function BridgeBuildSeatLibraryLedger(seatSnapshot)", Script);
        Assert.Contains("countByName[normalizedName] = (countByName[normalizedName] or 0) + 1", Script);
    }

    [Fact]
    public void SnapshotBootstrap_DuplicateContainedCardsUseDeterministicSelectionWithoutGuidUniquenessAssumption()
    {
        Assert.Contains("table.sort(containedCards, function(left, right)", Script);
        Assert.Contains("local authoritativeCountByName = {}", Script);
        Assert.Contains("local assignedContainedByName = {}", Script);
        Assert.Contains("local containedCandidates = ledger.byName[normalized] or {}", Script);
        Assert.Contains("table.remove(containedCandidates, 1)", Script);
    }

    [Fact]
    public void SnapshotBootstrap_MultiplicityMismatchIncludesSeatAndCountDiagnostics()
    {
        Assert.Contains("library reconciliation failed: seat=%s card=%s forgeExpected=%d physicalContained=%d physicalLoose=%d unmappedForgeInstances=%d unassignedContained=%d", Script);
        Assert.Contains("BridgeLog(\"[Bridge] \" .. detail)", Script);
    }

    [Fact]
    public void SnapshotBootstrap_InsertsLooseCardsIntoTheResolvedDeckBeforeReadingTheLibraryLedger()
    {
        Assert.Contains("local deck = BridgeResolveSeatLibraryDeck(seatId)", Script);
        Assert.Contains("deck.putObject(o)", Script);
        Assert.Contains("START-13 library-settle", Script);
        Assert.Contains("Wait.frames(function()", Script);
    }

    [Fact]
    public void ChoiceRejection_UsesStructuredErrorCodesRatherThanTreatingEvery409AsStale()
    {
        Assert.Contains("function BridgeIsStaleChoiceRejection", Script);
        Assert.Contains("errorCode == \"unknown_decision_id\"", Script);
        Assert.Contains("errorCode == \"decision_already_resolved\"", Script);
        Assert.Contains("errorCode == \"no_pending_decision\"", Script);
        Assert.DoesNotContain("responseCode == 409", Script);
        Assert.Contains("BridgeState.yieldSeatId = nil", Script);
        Assert.Contains("BridgeStartDecisionPolling()", Script);
    }

    [Fact]
    public void ChoiceSubmission_UsesDecisionScopedTransactionsAndBoundedRetirement()
    {
        Assert.Contains("BRIDGE_SCRIPT_REVISION = \"2026-08-25-forensic-v9\"", Script);
        Assert.Contains("choiceTransactions = {}", Script);
        Assert.Contains("retiredChoiceDecisionIds = {}", Script);
        Assert.Contains("function BridgeLogChoiceAttempt", Script);
        Assert.Contains("choice-attempt=%s source=%s", Script);
        Assert.Contains("BridgeState.choiceTransactions[decisionId] = transaction", Script);
        Assert.Contains("while #BridgeState.retiredChoiceDecisionOrder > 32 do", Script);
        Assert.Contains("BridgeState.retiredChoiceDecisionIds = {}", Script);
    }

    [Fact]
    public void SaveAndPlayReload_RetiresTimersAndHttpCallbacksFromThePreviousLuaRuntime()
    {
        Assert.Contains("BRIDGE_RUNTIME_EPOCH = (tonumber(BRIDGE_RUNTIME_EPOCH) or 0) + 1", Script);
        Assert.Contains("function BridgeRuntimeIsCurrent(epoch)", Script);
        Assert.Contains("function BridgeWaitTime(callback, delay)", Script);
        Assert.Contains("function BridgeWaitFrames(callback, frames)", Script);
        Assert.Contains("local epoch = BRIDGE_RUNTIME_EPOCH_LOCAL", Script);
        Assert.Contains("ignored HTTP callback from retired Global.lua runtime", Script);
        Assert.Contains("BridgeWaitTime(function()", Script);
        Assert.Contains("BridgeWaitFrames(function()", Script);
    }

    [Fact]
    public void Diagnostics_UseTheScriptingConsoleWhileErrorsBroadcastOnlyOnce()
    {
        Assert.Contains("function BridgeLog(message)", Script);
        Assert.Contains("log(tostring(message))", Script);
        Assert.DoesNotMatch(@"(?m)^\s*print\(", Script);

        var start = Script.IndexOf("function BridgeShowError", StringComparison.Ordinal);
        var end = Script.IndexOf("function onObjectPickUp", start, StringComparison.Ordinal);
        var body = Script[start..end];
        Assert.Contains("BridgeLog(text)", body);
        Assert.Contains("broadcastToAll(text", body);
    }

    [Fact]
    public void DecisionFetch_LeavesStateMutationToTheGenerationValidatedCaller()
    {
        var start = Script.IndexOf("function BridgeGetDecision", StringComparison.Ordinal);
        var end = Script.IndexOf("function BridgeStopDecisionPolling", start, StringComparison.Ordinal);
        var body = Script[start..end];

        Assert.Contains("BridgeHttp.requestJson(\"GET\", \"/api/v1/decision\", nil, callback)", body);
        Assert.DoesNotContain("BridgeState.lastDecision =", body);
        Assert.DoesNotContain("BridgeClearHighlights()", body);
    }

    [Fact]
    public void ChoiceSubmission_PostsAtTheIdempotentServerBoundaryWithoutGetPreflight()
    {
        Assert.Contains("BridgeHttp.requestJson(\"POST\", \"/api/v1/choice\"", Script);
        Assert.Contains("CHOICE_POST_BLOCKED reason=retired_runtime", Script);
        Assert.Contains("CHOICE_POST_BLOCKED reason=missing_source", Script);
        Assert.Contains("CHOICE_NOT_SENT reason=missing_protocol_identity", Script);
        Assert.Contains("[Bridge] CHOICE_WIRE_BODY", Script);
        Assert.Contains("if transaction.actionId == actionId then", Script);
        Assert.Contains("conflicting action ignored for an already-submitting Forge decision", Script);
        Assert.DoesNotContain("function BridgePostValidatedChoice", Script);
        var submitStart = Script.IndexOf("function BridgeSubmitChoice", StringComparison.Ordinal);
        var submitEnd = Script.IndexOf("function BridgeChoose", submitStart, StringComparison.Ordinal);
        Assert.True(submitStart >= 0 && submitEnd > submitStart);
        Assert.DoesNotContain("BridgeHttp.requestJson(\"GET\", \"/api/v1/decision\"", Script[submitStart..submitEnd]);
        Assert.Contains("sessionId = requestSessionId", Script[submitStart..submitEnd]);
        Assert.Contains("clientRuntimeId = BRIDGE_CLIENT_RUNTIME_ID", Script[submitStart..submitEnd]);
        Assert.Contains("[Bridge] CHOICE_POST requestId=", Script);
    }

    [Fact]
    public void DecisionAcceptance_IsCentralizedAndSessionProvenanced()
    {
        Assert.Contains("function BridgeAcceptDecision(decision, origin, expectedSessionId, presentationGeneration)", Script);
        Assert.Contains("[Bridge] DECISION_ACCEPT origin=", Script);
        Assert.Contains("reason=wrong_session", Script);
        Assert.DoesNotContain("function printDecision", Script);
    }

    [Fact]
    public void ChoiceProtocolFailures_PauseAutomationOnceForForensics()
    {
        Assert.Contains("function BridgeRecordChoiceProtocolFailure", Script);
        Assert.Contains("now - failures[1] > 2", Script);
        Assert.Contains("BridgeState.choiceProtocolPaused = true", Script);
        Assert.Contains("FORGEBOT PROTOCOL PAUSED", Script);
        Assert.Contains("choice submission blocked: protocol is paused", Script);
    }

    [Fact]
    public void DelayedDecisionResponses_CannotRenderControlsFromAReplacedSession()
    {
        Assert.Contains("decisionPresentationGeneration = 0", Script);
        Assert.Contains("BridgeState.decisionPresentationGeneration = BridgeState.decisionPresentationGeneration + 1", Script);
        Assert.Contains("function BridgeAcceptDecision(decision, origin, expectedSessionId, presentationGeneration)", Script);
        Assert.Contains("reason=replaced_generation", Script);
        Assert.Contains("ignored delayed decision fetch from a replaced Forge session", Script);
        Assert.Contains("ignored delayed decision refresh from a replaced Forge session", Script);
    }

    [Fact]
    public void CardSelection_IsPresentedAsAnOrangeRequiredChoiceRatherThanABlueCastAction()
    {
        Assert.Contains("elseif decision.kind == \"card_selection\"", Script);
        Assert.Contains("Required Forge selection (for example, discard)", Script);
        Assert.Contains("if decision.kind ~= \"main_priority\" then", Script);
    }

    [Fact]
    public void PhysicalPickup_RejectsAnActionThatDoesNotBelongToTheCurrentDecision()
    {
        Assert.Contains("if not BridgeDecisionHasAction(decision, action.actionId) then", Script);
        Assert.Contains("card action is stale; waiting for the current Forge decision", Script);
    }

    [Fact]
    public void LibraryExtraction_UsesFreshDeckObjectsAndAssignsLooseGuidAfterTakeObject()
    {
        Assert.Contains("BridgeTakeCardFromDeckByIdentity(", Script);
        Assert.Contains("containedCards = deck.getObjects() or {}", Script);
        Assert.Contains("index = matched.index", Script);
        Assert.Contains("BridgeRecordLooseCardIdentity(event.cardInstanceId, drawnGuid, event.seatId, event.destinationZone)", Script);
    }

    [Fact]
    public void LibraryIdentityRegressionA_DuplicateCopiesCanShareContainedGuidsAndStillReconcileByCounts()
    {
        Assert.Contains("local physicalCount = looseCount + containedCount", Script);
        Assert.Contains("if physicalCount < expectedCount then", Script);
        Assert.Contains("local containedCandidates = ledger.byName[normalized] or {}", Script);
    }

    [Fact]
    public void LibraryIdentityRegressionB_DistinctForgeInstancesDoNotRequireDistinctContainedGuids()
    {
        Assert.Contains("BridgeTakeCardFromDeckByIdentity(", Script);
        Assert.DoesNotContain("preferredContainedGuid", Script);
    }

    [Fact]
    public void LibraryIdentityRegressionC_DrawRescansDeckAndUsesCurrentIndexEachTime()
    {
        Assert.Contains("moveFromLibraryDeckToHand", Script);
        Assert.Contains("table.sort(containedCards, function(left, right)", Script);
        Assert.Contains("index = matched.index", Script);
    }

    [Fact]
    public void LibraryIdentityRegressionD_MultiplicityMismatchHardFailsWithExpectedDiagnostics()
    {
        Assert.Contains("if physicalCount < expectedCount then", Script);
        Assert.Contains("library reconciliation failed: seat=%s card=%s forgeExpected=%d physicalContained=%d physicalLoose=%d unmappedForgeInstances=%d unassignedContained=%d", Script);
        Assert.Contains("see host log for multiplicity diagnostics", Script);
    }

    [Fact]
    public void LibraryIdentityRegressionE_MixedDuplicatesNeverRequireContainedGuidUniqueness()
    {
        Assert.Contains("table.remove(containedCandidates, 1)", Script);
        Assert.Contains("assignedContainedByName[normalized] = (assignedContainedByName[normalized] or 0) + 1", Script);
        Assert.DoesNotContain("mapped deck-contained identity does not match the authoritative card name", Script);
    }

    [Fact]
    public void LibraryIdentityRegressionF_ResumeCanReconstructWithoutPersistedContainedMappings()
    {
        Assert.Contains("BridgeState.physicalByInstanceId = {}", Script);
        Assert.Contains("BridgeState.cardNameByInstanceId = {}", Script);
        Assert.Contains("BridgeBuildSeatLibraryLedger(seatSnapshot)", Script);
    }

    [Fact]
    public void LibraryIdentityRegressionG_LibraryReentryClearsLooseGuidAssociation()
    {
        Assert.Contains("function BridgeRecordLooseCardIdentity", Script);
        Assert.Contains("function BridgeRecordLibraryContainedState", Script);
        Assert.Contains("BridgeState.physicalByInstanceId[cardInstanceId] = nil", Script);
    }

    [Fact]
    public void LibraryIdentityRegressionH_ForgeDrawDoesNotDependOnPhysicalTopCardIdentity()
    {
        Assert.DoesNotContain("if matched == nil and drawFromTop then", Script);
        Assert.DoesNotContain("authoritative draw identity does not match physical top-of-library card", Script);
        Assert.Contains("for _, contained in ipairs(containedCards) do", Script);
    }

    [Fact]
    public void SnapshotReconcile_RepairsPublicZoneDriftWhenStructuredMoveEventsAreSparse()
    {
        Assert.Contains("function BridgeScheduleSnapshotReconcile", Script);
        Assert.Contains("BridgeShouldReconcileAfterEvent(event)", Script);
        Assert.Contains("or event.kind == \"card_moved\"", Script);
        Assert.Contains("BridgeZoneIsPublicForReconcile(zoneName)", Script);
        Assert.Contains("mappedNeedsFix", Script);
        Assert.Contains("BridgeApplyStructuredCardMove(evt)", Script);
        Assert.Contains("existing.tag == \"Card\"", Script);
        Assert.Contains("BridgeState.physicalByInstanceId[event.cardInstanceId] = nil", Script);
    }

    [Fact]
    public void ExactResolvedSpellAlreadyInGraveyard_IsIdempotent()
    {
        Assert.Contains("idempotent spell resolution event=", Script);
        Assert.Contains("after structured graveyard move=", Script);
        Assert.Contains("structuredMove.destinationZone == \"graveyard\"", Script);
        Assert.Contains("mappedZone == \"graveyard\"", Script);
        Assert.Contains("inverseInstanceId ~= event.cardInstanceId", Script);
        Assert.Contains("BridgeState.pendingCastBySeatId[event.seatId] = nil", Script);
    }

    [Fact]
    public void SnapshotBattlefieldRepair_PreservesForgeRowKindAndTapDoesNotReflow()
    {
        Assert.Contains("battlefieldKind = card.battlefieldKind", Script);
        Assert.Contains("local row = event.battlefieldKind == \"land\" and \"land\" or \"creature\"", Script);
        var tapStart = Script.IndexOf("if event.kind == \"tap_changed\" then", StringComparison.Ordinal);
        var tapEnd = Script.IndexOf("if event.kind == \"counter_changed\" then", tapStart, StringComparison.Ordinal);
        var tapBlock = Script[tapStart..tapEnd];
        Assert.Contains("BridgeSetPhysicalTapped", tapBlock);
        Assert.DoesNotContain("BridgeMoveToBattlefield", tapBlock);
    }

    [Fact]
    public void AcceptedCombatChoice_RemainsDistinctUntilCombatPresentationClears()
    {
        Assert.Contains("combatSelectedByGuid", Script);
        Assert.Contains("or action.isSelected == true", Script);
        Assert.Contains("object.highlightOn(selected and selectedCombatColor or highlightColor)", Script);
        Assert.Contains("BridgeState.combatSelectedByGuid[intent.guid] = true", Script);
        Assert.Contains("BridgeState.combatSelectedByGuid[guid] = nil", Script);
    }

    [Fact]
    public void SelectedCombatCandidate_RemainsSelectableToUndoItsForgeStaging()
    {
        Assert.Contains("BridgeState.actionByGuid[guid] = action", Script);
        Assert.Contains("if intent.action.isSelected == true then", Script);
        Assert.Contains("BridgeReturnCombatPreviewCard(intent.seatId, object)", Script);
        Assert.Contains("function BridgeReturnCombatPreviewCard", Script);
    }

    [Fact]
    public void GraveyardCards_RemainIndividuallyMappedAndCenteredOnThePrintedZone()
    {
        Assert.Contains("graveyardAnchor = {x = 1.75, y = 2.0", Script);
        Assert.Contains("function BridgeGraveyardPosition", Script);
        Assert.Contains("BridgeState.graveyardCounts[seatId]", Script);
        Assert.Contains("local graveyardPosition = BridgeGraveyardPosition(event.seatId)", Script);
        Assert.Contains("x = anchor.x", Script);
        Assert.Contains("y = anchor.y + 0.08 + count * 0.12", Script);
        Assert.Contains("object.setLock(true)", Script);
    }

    [Fact]
    public void CastSpellIntent_IsReversibleBeforeForgeReceivesIt()
    {
        Assert.Contains("function BridgeEnsureCastPreviewControls", Script);
        Assert.Contains("CAST /\\nCONFIRM", Script);
        Assert.Contains("CANCEL /\\nRETURN", Script);
        Assert.Contains("function BridgeConfirmCastPreview", Script);
        Assert.Contains("function BridgeCancelCastPreview", Script);
        Assert.Contains("BridgeEnsureCastPreviewControls(intent)", Script);
        Assert.Contains("BridgeRollbackPendingIntent()", Script);
    }

    [Fact]
    public void CombatCandidates_AreOrangeFollowupChoices()
    {
        Assert.Contains("if decision.kind ~= \"main_priority\" then", Script);
        Assert.Contains("highlightColor = {1.0, 0.55, 0.0}", Script);
    }

    [Fact]
    public void AiLandRow_IsMovedFartherTowardItsTableSide()
    {
        Assert.Contains("land = {x = 6.5, y = 2.0, z = 19.0}", Script);
    }

    [Fact]
    public void SnapshotReconcile_DefersPublicMovementUntilItsBridgeEventCursorIsApplied()
    {
        Assert.Contains("EventCursor = _latestEventSequence", File.ReadAllText(
            Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "MtgTtsBridge", "Forge", "ForgeTuiAdapter.cs")));
        Assert.Contains("function BridgeSnapshotMayMutatePublicZones", Script);
        Assert.Contains("snapshotCursor <= tonumber(BridgeState.lastAppliedEventSequence", Script);
        Assert.Contains("BridgeState.deferredSnapshotReconcile = {snapshot = snapshot, reason = reason}", Script);
        Assert.Contains("BridgeTryApplyDeferredSnapshotReconcile(\"event \" .. tostring(event.sequence))", Script);
        Assert.Contains("forgeSequence=%s eventCursor=%s received=%s applied=%s queued=%s..%s", Script);
    }

    [Fact]
    public void TapAndExactDestinationSafety_DoNotTurnAHandCardOrSuppressWrongMappings()
    {
        Assert.Contains("if trackedZone ~= \"battlefield\" then", Script);
        Assert.Contains("tap presentation deferred event=%s instance=%s trackedZone=%s", Script);
        Assert.Contains("physicalInstanceIdByGuid", Script);
        Assert.Contains("mapped destination GUID belongs to a different Forge instance", Script);
        Assert.Contains("exact mapped destination belongs to a different seat", Script);
        Assert.Contains("idempotent move event=%s instance=%s already at %s", Script);
        Assert.Contains("idempotent move event=%s instance=%s already at battlefield", Script);
    }

    [Fact]
    public void RealDecisionIdentity_WinsOverDuplicateNameFallback()
    {
        Assert.Contains("action.cardInstanceId and BridgeState.physicalByInstanceId[action.cardInstanceId]", Script);
        Assert.Contains("if mappedSeatMatches and mappedZoneMatches then", Script);
        Assert.Contains("if mappedGuid == nil and #matches > 1 then", Script);
        Assert.Contains("repaired instance mapping", Script);
        Assert.Contains("instance mapping ambiguous", Script);
    }

    [Fact]
    public void ProwessUsesForgeCurrentPowerToughness_NotANonexistentTableIcon()
    {
        Assert.DoesNotContain("mtg_prowesscounter", Script);
        Assert.Contains("BridgeSetDerivedStats(object, power, toughness)", Script);
        Assert.Contains("function BridgeNormalizeKeywordName", Script);
        Assert.Contains("string.find(normalized, \" (\", 1, true)", Script);
    }

    [Fact]
    public void DoctorPreflight_ReportsCompanionAndTableCapabilityWithoutMutatingCards()
    {
        Assert.Contains("function BridgeDoctor(done)", Script);
        Assert.Contains("[BridgeDoctor] PASS=", Script);
        Assert.Contains("companion.health", Script);
        Assert.Contains("seat.deck.", Script);
        Assert.Contains("table.piKeywords", Script);
        Assert.Contains("COMPANION OFFLINE", Script);
    }

    [Fact]
    public void LibraryDeckResolution_UsesLibraryAnchorProximityWhenMultipleDeckCandidatesExist()
    {
        Assert.Contains("function BridgeSelectNearestDeckCandidate(seat, candidates)", Script);
        Assert.Contains("BridgeSelectNearestDeckCandidate(seat, candidates)", Script);
        Assert.Contains("local nearest = BridgeSelectNearestDeckCandidate(seat, matches)", Script);
        Assert.Contains("ambiguous library deck match for", Script);
    }

    [Fact]
    public void StructuredMappingMisses_DeferToSnapshotInsteadOfImmediateDesync()
    {
        Assert.Contains("function BridgeCanDeferStructuredMoveToSnapshot", Script);
        Assert.Contains("structured move deferred to snapshot reconcile", Script);
        Assert.Contains("tap update deferred to snapshot reconcile", Script);
        Assert.Contains("counter update deferred to snapshot reconcile", Script);
        Assert.Contains("keyword update deferred to snapshot reconcile", Script);
    }

    [Fact]
    public void DuplicateSemanticLandPresentation_DefersWhenItsExactStructuredMoveIsPending()
    {
        Assert.Contains("pendingStructuredZoneTransitionByInstanceId", Script);
        Assert.Contains("pendingTransition.destinationZone == \"battlefield\"", Script);
        Assert.Contains("semantic land presentation deferred event=%s instance=%s after structured move=%s", Script);
        Assert.Contains("This does not suppress unrelated or wrong-instance moves", Script);
    }

    [Fact]
    public void ManaPresentation_UsesOnlyTheExactMappedBattlefieldInstance()
    {
        var manaStart = Script.IndexOf("if event.kind == \"mana_ability_used\" then", StringComparison.Ordinal);
        var manaEnd = Script.IndexOf("if event.kind == \"attack_declared\" then", manaStart, StringComparison.Ordinal);
        var manaHandler = Script[manaStart..manaEnd];

        Assert.Contains("BridgeResolveMappedInstance(event)", manaHandler);
        Assert.DoesNotContain("BridgeResolvePhysicalCard(event, \"battlefield\")", manaHandler);
        Assert.Contains("mana presentation deferred event=%s instance=%s reason=%s", manaHandler);
        Assert.Contains("mana presentation deferred event=%s instance=%s trackedZone=%s", manaHandler);
        Assert.Contains("BridgeScheduleSnapshotReconcile(\"mana event \" .. tostring(event.sequence))", manaHandler);
    }

    [Fact]
    public void DefaultForgeLaunchUsesNumericCombatChoicesAndNeverSynthesizesCardIdCombatInputs()
    {
        var launcher = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "tools", "Start-ForgeBot.ps1"));
        var settings = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "MtgTtsBridge", "appsettings.json"));
        var adapter = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "MtgTtsBridge", "Forge", "ForgeTuiAdapter.cs"));

        Assert.Contains("--numeric-choices", launcher);
        Assert.Contains("--numeric-choices", settings);
        Assert.DoesNotContain("SynthesizeCombatActions", adapter);
        Assert.DoesNotContain("SynthesizeBlockerAssignments", adapter);
    }

    [Fact]
    public void CombatCardsCanBeSelectedWithAStandardPickupAndDropWithoutLanePrecision()
    {
        Assert.Contains("combat selection accepted in place for %s (guid=%s)", Script);
        Assert.DoesNotContain("combat drop ignored for %s", Script);
        Assert.Contains("BridgeMoveToAttackLane(intent.seatId, object)", Script);
    }

    [Fact]
    public void TransitionPolling_UsesFastPathAndLatencyTelemetryAfterChoiceAcceptance()
    {
        Assert.Contains("transitionExpectedUntil", Script);
        Assert.Contains("function BridgeCurrentEventPollDelay", Script);
        Assert.Contains("BridgeScheduleEventPoll(0.05, BridgeState.eventPollGeneration)", Script);
        Assert.Contains("BridgeState.latencyProbe = {", Script);
        Assert.Contains("BridgeRecordLatencyProbeDecisionReady", Script);
        Assert.Contains("[Bridge latency] action=", Script);
    }
}
