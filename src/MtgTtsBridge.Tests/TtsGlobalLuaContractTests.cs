using System.Text;

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
        Assert.Contains("yieldTurnNumber = tonumber(decision.turnNumber or BridgeState.tableTurnCount or 0)", Script);
        Assert.Contains("cleared end-turn yield at authoritative turn transition", Script);
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
    public void YieldAutoPass_ExpiresFromAuthoritativeTurnMirrorBeforeDecisionAutoPass()
    {
        var start = Script.IndexOf("if BridgeState.yieldSeatId ~= nil then", StringComparison.Ordinal);
        var end = Script.IndexOf("-- Keep passive auto-pass off", start, StringComparison.Ordinal);
        var yield = Script[start..end];

        Assert.Contains("authoritativeTurn = tonumber(BridgeState.tableTurnCount or 0)", yield);
        Assert.Contains("authoritativeActiveSeat = BridgeState.currentTurnSeatId", yield);
        Assert.Contains("authoritativeTurn ~= yieldTurn", yield);
        Assert.Contains("authoritativeActiveSeat ~= BridgeState.yieldSeatId", yield);
        Assert.Contains("BridgeState.yieldSeatId = nil", yield);
    }

    [Fact]
    public void SyntheticHudCallbackColor_CannotRebindTheConfiguredHumanSeat()
    {
        var claim = Script.IndexOf("function BridgeClaimHumanTtsColor", StringComparison.Ordinal);
        Assert.True(claim >= 0);
        var nextFunction = Script.IndexOf("function BridgeSelectPlayerTarget", claim, StringComparison.Ordinal);
        var body = Script[claim..nextFunction];

        Assert.Contains("if playerColor == \"LuaPlayer\" then", body);
        Assert.Contains("ignoring synthetic UI callback color", body);
        Assert.Contains("if BridgeState.eventSessionId ~= nil and seat.ttsColor ~= playerColor then", body);
        Assert.Contains("ignoring attempted active-match seat-color rebind", body);
    }

    [Fact]
    public void ConfirmedSelection_StagesExactActionsWithoutPreemptiveZoneMutation()
    {
        Assert.Contains("selectedActionIds", Script);
        Assert.Contains("decision.minSelections or 1", Script);
        Assert.Contains("decision.maxSelections or 1", Script);
        Assert.Contains("DONE /\\nCONFIRM", Script);
        Assert.Contains("CANCEL /\\nUNDO", Script);
        Assert.Contains("BridgeDecisionNeedsConfirmation(decision)", Script);
        Assert.Contains("action.requiresSelection == true", Script);
        Assert.Contains("function BridgeToggleSingleSelection(decision, actionId, guid)", Script);
        Assert.Contains("choose one card, confirm it, then Forge will request any remaining cards", Script);
        Assert.Contains("staged Forge selection decision=", Script);
        Assert.Contains("function BridgeTryFinishDiscardChoice(decision, source)", Script);
        Assert.Contains("physical_discard_graveyard", Script);
        Assert.Contains("awaiting explicit Done", Script);
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
        Assert.Contains("Combat declarations have an explicit Forge finish action", Script);
        Assert.Contains("or decision.kind == \"blocker_selection\" or decision.kind == \"blocker_assignment\")", Script);
        Assert.Contains("DONE ATTACKING", Script);
        Assert.Contains("DONE BLOCKING", Script);
        Assert.Contains("finish_attacking", Script);
        Assert.Contains("finish_blocking", Script);
        Assert.Contains("selectionControlDecisionId", Script);
        Assert.Contains("selectionControlActionId", Script);
        Assert.Contains("combat completion action is stale; waiting for Forge redraw", Script);
        Assert.Contains("BridgeSubmitChoice(decisionId, currentAction.actionId, \"contextual_done\")", Script);
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
    public void FreshCombatDecisionPhaseMetadataCannotBeSuppressedByLatePhaseEvent()
    {
        var staleGate = Script.IndexOf("function BridgeShouldIgnoreStaleDecision", StringComparison.Ordinal);
        var nextFunction = Script.IndexOf("function BridgeShouldDeferDecision", staleGate, StringComparison.Ordinal);
        Assert.True(staleGate >= 0);
        Assert.True(nextFunction > staleGate);
        var body = Script[staleGate..nextFunction];

        Assert.Contains("local decisionPhase = string.upper(tostring(decision.phaseName or \"\"))", body);
        Assert.Contains("local phase = decisionPhase ~= \"\" and decisionPhase", body);
        Assert.Contains("decisionPhase=", body);
        Assert.Contains("cachedPhase=", body);
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
        Assert.Contains("must not suppress that action", Script);
        Assert.DoesNotContain("local staleLandWindow", Script);
    }

    [Fact]
    public void SameTurnStalePriorityMenuCannotCarryUpkeepPassIntoMainOne()
    {
        var start = Script.IndexOf("function BridgeShouldIgnoreStaleDecision", StringComparison.Ordinal);
        var end = Script.IndexOf("function BridgeShouldDeferDecision", start, StringComparison.Ordinal);
        Assert.True(start >= 0 && end > start);
        var body = Script[start..end];

        Assert.Contains("eventCursor > 0 and eventCursor < applied", body);
        Assert.Contains("local function phaseFamily(value)", body);
        Assert.Contains("decisionFamily ~= authoritativeFamily", body);
        Assert.Contains("ignoring stale main-priority decision phase=", body);
    }

    [Fact]
    public void CombatActionsWithExactIdentityNeverFallBackToSpentSameNameCards()
    {
        var start = Script.IndexOf("local fallbackMatches = {}", StringComparison.Ordinal);
        var end = Script.IndexOf("if action.cardInstanceId == nil then", start, StringComparison.Ordinal);
        Assert.True(start >= 0 && end > start);
        var body = Script[start..end];
        Assert.Contains("combatSelection and action.cardInstanceId ~= nil", body);
        Assert.Contains("suppressing combat action without exact physical mapping", body);
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
    public void DeferredDecision_DoesNotExposeUnembodiedHandActionsThroughTheHud()
    {
        var acceptStart = Script.IndexOf("function BridgeAcceptDecision(decision, origin, expectedSessionId, presentationGeneration)", StringComparison.Ordinal);
        var acceptEnd = Script.IndexOf("function BridgeRenderDecision(decision, force)", acceptStart, StringComparison.Ordinal);
        Assert.True(acceptStart >= 0 && acceptEnd > acceptStart);
        var accept = Script[acceptStart..acceptEnd];
        var deferStart = accept.IndexOf("if deferDecision then", StringComparison.Ordinal);
        var deferEnd = accept.IndexOf("BridgeState.pendingDecision = nil", deferStart, StringComparison.Ordinal);
        Assert.True(deferStart >= 0 && deferEnd > deferStart);
        var deferred = accept[deferStart..deferEnd];

        Assert.Contains("BridgeState.pendingDecision = decision", deferred);
        Assert.Contains("BridgeState.lastDecision = nil", deferred);
        Assert.Contains("BridgeUiMarkDirty(\"decision-deferred\")", deferred);
    }

    [Fact]
    public void HandActions_AreHeldUntilTheirExactInstancesAreInTheLiveTtsHand()
    {
        var deferStart = Script.IndexOf("function BridgeShouldDeferDecision", StringComparison.Ordinal);
        var retryStart = Script.IndexOf("function BridgeScheduleOpeningHandReadinessRetry", deferStart, StringComparison.Ordinal);
        Assert.True(deferStart >= 0 && retryStart > deferStart);
        var defer = Script[deferStart..retryStart];

        Assert.Contains("BridgeBuildSeatHandGuidSet(decision.seatId)", defer);
        Assert.Contains("action.preparedSourceCardInstanceId", defer);
        Assert.Contains("BridgeState.physicalByInstanceId[instanceId]", defer);
        Assert.Contains("BridgeState.physicalInstanceIdByGuid[guid] ~= instanceId", defer);
        Assert.Contains("handGuids[guid] ~= true", defer);
        Assert.Contains("\"hand_action_readiness\"", defer);
        Assert.Contains("function BridgeScheduleHandActionReadinessRetry", Script);
        Assert.Contains("holding decision %s until exact hand action is embodied", Script);
        Assert.Contains("hand action readiness timeout", Script);
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
        Assert.Contains("counter.setValue(amount)", Script);
        Assert.Contains("event.kind == \"mana_pool_changed\"", Script);
        Assert.Contains("seatSnapshot.manaPool", Script);
        Assert.Contains("lifeCounter.getPosition()", Script);
        Assert.Contains("seat.manaBankOffset", Script);
    }

    [Fact]
    public void ManaTrackerUpdates_UseCounterApiWithoutCallingMissingFunctions()
    {
        var start = Script.IndexOf("function BridgeSetNativeTrackerValue", StringComparison.Ordinal);
        var end = Script.IndexOf("function BridgeTrackerPosition", start, StringComparison.Ordinal);
        var body = Script[start..end];

        Assert.Contains("local nativeOk = pcall(function() counter.setValue(amount) end)", body);
        Assert.Contains("local setVarOk, setVarError = pcall(function() counter.setVar(\"val\", amount) end)", body);
        Assert.DoesNotContain("counter.call(\"updateVal\")", body);
        Assert.DoesNotContain("counter.call(\"updateSave\")", body);
        Assert.DoesNotContain("counter.call(functionName)", body);
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
    public void StartupTrace_RecordsBoundedMarkersAtExistingStartupBoundaries()
    {
        var requiredMarkers = new[]
        {
            "onLoad_enter",
            "BridgeOnLoad_enter",
            "startup_transient_cleanup_begin",
            "startup_transient_cleanup_end",
            "startup_ui_begin",
            "startup_ui_end",
            "startup_object/bootstrap_discovery_begin",
            "startup_object/bootstrap_discovery_end",
            "startup_bridge_health_begin",
            "startup_bridge_health_dispatched",
            "BridgeOnLoad_return"
        };

        foreach (var marker in requiredMarkers)
        {
            Assert.Contains($"\"{marker}\"", Script);
        }

        Assert.Contains("BridgeState.startupTrace.observableDurationMs", Script);
        Assert.Contains("function BridgePerformanceTraceSnapshot()", Script);
        Assert.Contains("TTS file read and Lua compilation happen before this function executes", Script);
        Assert.DoesNotContain("File.Write", Script);
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
        Assert.Contains("if phased == true then", Script);
        Assert.Contains("APIobjDisableProp", Script);
        Assert.Contains("data.mtg_phased = false", Script);
        Assert.Contains("function BridgeSetFaceState(object, forgeState, seatId)", Script);
        Assert.Contains("Do not infer Morph/Manifest or", Script);
        Assert.Contains("function BridgeSetCardCounters(object, absoluteCounters)", Script);
        Assert.Contains("function BridgeCopyCounterMap(counters)", Script);
        Assert.Contains("if #named == 1 then", Script);
        Assert.Contains("local BRIDGE_COUNTER_FALLBACK_PROPERTY = \"ForgeBotState\"", Script);
        Assert.Contains("function BridgeSetForgeBotCounterFallback(object, namedCounters)", Script);
        Assert.Contains("local BRIDGE_KEYWORDS_PROPERTY = \"πKeywords\"", Script);
        Assert.Contains("function BridgeSetCardKeywords(object, absoluteKeywords)", Script);
        Assert.Contains("data.activeIcons = {}", Script);
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
        Assert.Contains("BridgeRecordLooseCardIdentity(mapping.card.cardInstanceId, guid", Script);
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
        var prepare = Script.IndexOf("BridgePrepareEventSession(sessionId, true, resumeFromSnapshotCursor == true)", bootstrap, StringComparison.Ordinal);
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
        Assert.Contains("dx * dx + dz * dz < 3.0", Script);
        Assert.Contains("card.battlefieldKind == \"land\"", Script);
        Assert.Contains("function BridgeAnnotateSnapshotBattlefieldKinds", Script);
        Assert.Contains("event.kind == \"land_played\"", Script);
        Assert.Contains("landByInstanceId[card.cardInstanceId]", Script);
        Assert.Contains("local snapshotRow = zoneName == \"battlefield\"", Script);
        Assert.Contains("ROW_PLACEMENT seat=", Script);
        Assert.Contains("event.battlefieldKind", Script);
    }

    [Fact]
    public void DirectHandToBattlefieldMove_WaitsForSemanticLandPlacement()
    {
        Assert.Contains("event.destinationZone == \"battlefield\"", Script);
        Assert.Contains("object = tryResolveFromZone(\"stack\")", Script);
        Assert.Contains("BridgeMoveToBattlefield(event, object, \"land\")", Script);
    }

    [Fact]
    public void StructuredBattlefieldMove_IsNotRepeatedByInstanceLessSemanticResolution()
    {
        Assert.Contains("event.kind == \"spell_resolved\"", Script);
        Assert.Contains("presented exact pending cast on semantic resolution", Script);
        Assert.Contains("resolvedEvent.cardInstanceId = pendingCast.cardInstanceId", Script);
        Assert.Contains("if event.cardInstanceId == nil then", Script);
        Assert.Contains("BridgeResolvePhysicalCard(event, \"stack\")", Script);
    }

    [Fact]
    public void SemanticBattlefieldResolution_PreservesAuthoritativeCardRow()
    {
        Assert.Contains("function BridgeBattlefieldRowForEvent(event, defaultRow)", Script);
        Assert.Contains("event.battlefieldKind == \"land\"", Script);
        Assert.Contains("event.currentTypes or {}", Script);
        Assert.Contains("BridgeBattlefieldRowForEvent(resolvedEvent, \"creature\")", Script);
        Assert.Contains("BridgeBattlefieldRowForEvent(event, \"creature\")", Script);
    }

    [Fact]
    public void BattlefieldCardMovesAreNotHeldBehindLongPresentationDelay()
    {
        Assert.Contains("local presentationDelay = (event.destinationZone == \"battlefield\"", Script);
        Assert.Contains("or event.destinationZone == \"stack\") and 0.1 or 1.0", Script);
        Assert.Contains("return applied, presentationDelay, moveError", Script);
    }

    [Fact]
    public void CastSpellIntent_TracksStackIdentityAndResolvedGraveyardBinding()
    {
        Assert.Contains("pendingCastBySeatId", Script);
        Assert.Contains("BridgeState.physicalZoneByGuid[intent.guid] = \"stack\"", Script);
        Assert.Contains("BridgeState.pendingCastBySeatId[intent.seatId]", Script);
        Assert.Contains("cardInstanceId = intent.action.cardInstanceId", Script);
        Assert.Contains("BridgeResolveResolvedSpellObject", Script);
        Assert.Contains("BridgeRecordLooseCardIdentity(event.cardInstanceId, pendingCast.guid, event.seatId, \"stack\")", Script);
        Assert.Contains("BridgeRetirePendingCastForInstance", Script);
        Assert.Contains("pendingCast ~= nil and pendingCast.guid ~= nil", Script);
        Assert.Contains("if pendingObject ~= nil and pendingName ~= nil and BridgeCardNameMatches(pendingName, event.cardName) then", Script);
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
        var publishMapping = Script.IndexOf("BridgeRecordLooseCardIdentity(mapping.card.cardInstanceId, guid", reconcile, StringComparison.Ordinal);
        Assert.True(collectMapping > reconcile);
        Assert.True(publishMapping > collectMapping);
    }

    [Fact]
    public void SnapshotReconcile_DoesNotGuessLibraryForUnmappedPublicCards()
    {
        var reconcile = Script.IndexOf("function BridgeApplySafeSnapshotReconcile", StringComparison.Ordinal);
        var next = Script.IndexOf("function BridgeTryApplyDeferredSnapshotReconcile", reconcile, StringComparison.Ordinal);
        var body = Script[reconcile..next];

        Assert.Contains("local snapshotSourceZone = mappedObject ~= nil", body);
        Assert.Contains("and mappedObject.tag == \"Card\" and mappedZone or nil", body);
        Assert.Contains("BridgeFindAuthoritativeSnapshotTransitionSourceZone(", body);
        Assert.Contains("snapshot candidate deferred", body);
        Assert.DoesNotContain("snapshotSourceZone = \"library\"", body);
        Assert.Contains("sourceZone = snapshotSourceZone", body);
        Assert.Contains("event.sourceZone == \"library\" and event.destinationZone == \"graveyard\"", Script);
    }

    [Fact]
    public void SnapshotReconcile_UsesOnlyExactQueuedTransitionAsSyntheticSource()
    {
        var helper = Script.IndexOf("function BridgeFindAuthoritativeSnapshotTransitionSourceZone", StringComparison.Ordinal);
        var end = Script.IndexOf("function BridgeQueuedEventRange", helper, StringComparison.Ordinal);
        var body = Script[helper..end];

        Assert.Contains("pendingStructuredZoneTransitionByInstanceId", body);
        Assert.Contains("eventQueue", body);
        Assert.Contains("queued.cardInstanceId == cardInstanceId", body);
        Assert.Contains("queued.sourceZone ~= nil", body);
        Assert.DoesNotContain("cardName", body);
    }

    [Fact]
    public void SnapshotReconcile_WaitsForOrderedLibraryQueues()
    {
        Assert.Contains("function BridgePhysicalLibraryQueuesIdle()", Script);
        Assert.Contains("BridgeState.libraryExtractionActiveBySeatId[seatId] == true", Script);
        Assert.Contains("mulliganBottomInsertionActiveBySeatId[seatId] == true", Script);
        Assert.Contains("BridgeSnapshotMayMutatePublicZones(snapshot) and BridgePhysicalLibraryQueuesIdle()", Script);
        Assert.Contains("local queueState = BridgePhysicalLibraryQueuesIdle() and \"event-cursor\" or \"physical-library-queue\"", Script);
        Assert.Contains("library-extraction-complete", Script);
    }

    [Fact]
    public void SameSessionResync_PreservesExactPublicMappingsBeforeBootstrap()
    {
        Assert.Contains("BridgePrepareEventSession(sessionId, true, resumeFromSnapshotCursor == true)", Script);
        Assert.Contains("preservedLiveMappings", Script);
        Assert.Contains("BridgeState.physicalByInstanceId[instanceId] = mapping.guid", Script);
        Assert.Contains("mapping.zoneName", Script);
        Assert.Contains("authoritative resync deferred until physical library queues are idle", Script);
    }

    [Fact]
    public void SnapshotBootstrap_PrefersExactGuidAndRefusesResyncNameExtraction()
    {
        Assert.Contains("local preservedGuid = BridgeState.physicalByInstanceId[card.cardInstanceId]", Script);
        Assert.Contains("assetByGuid[tostring(preservedGuid)]", Script);
        Assert.Contains("local preserveTrackedPublicCard = trackedInstanceId ~= nil", Script);
        Assert.Contains("and not preserveTrackedPublicCard", Script);
        Assert.Contains("resync materialization using contained-library fallback for unmapped public card", Script);
    }

    [Fact]
    public void SnapshotBootstrap_StagesLooseCardsNearLibrariesBeforeRemapping()
    {
        Assert.Contains("BridgeStageSeatCardsForBootstrap(snapshot, function(stagedOk, stagedError, stagedGuids)", Script);
        Assert.Contains("function BridgeStageSeatCardsForBootstrap(snapshot, callback)", Script);
        Assert.Contains("IsGameCardCandidate(object, seatId, context)", Script);
        Assert.Contains("BridgeTryGetSeatHandObjects(seatId)", Script);
        Assert.Contains("BridgeNearestSeatIdForPosition", Script);
        Assert.Contains("function BridgeLibraryStagingPosition", Script);
        Assert.Contains("BridgeInsertPhysicalCardIntoLibrary(seatId, object, \"NORMAL\"", Script);
    }

    [Fact]
    public void SnapshotBootstrap_PreservesLiveHandsWhileRebuildingThePublicEmbodiment()
    {
        var start = Script.IndexOf("function BridgeStageSeatCardsForBootstrap", StringComparison.Ordinal);
        var end = Script.IndexOf("-- A destructive New Match", start, StringComparison.Ordinal);
        var staging = Script[start..end];

        Assert.Contains("context.handGuidsBySeat[seatId] = handGuids", staging);
        Assert.Contains("local isInHand = handSeatId ~= nil", staging);
        Assert.Contains("and not isInHand", staging);
        Assert.Contains("local function addAsset(object)", Script);
        Assert.Contains("BridgeTryGetSeatHandObjects(seatId)", Script);
        Assert.Contains("TTS hand objects are not guaranteed to be present in getAllObjects()", Script);
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
        Assert.Contains("physicalTappedByGuid = {}", Script);
        Assert.Contains("BridgeState.physicalTappedByGuid[guid] = tapped == true", Script);
        Assert.Contains("BridgeState.physicalTappedByGuid[guid] == true and 90 or 0", Script);
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
        Assert.Contains("forgeExpectedTotal=%d containedPhysicalTotal=%d loosePhysicalTotal=%d physicalTotal=%d deficit=%d", Script);
        Assert.Contains("function BridgeLogLibraryMismatchInventory(seatSnapshot, failedName, displayName)", Script);
        Assert.Contains("LIBRARY MISMATCH INVENTORY", Script);
        Assert.Contains("containedAssigned=%d looseAssigned=%d containedRemaining=%d looseRemaining=%d", Script);
        Assert.Contains("BridgeLog(\"[Bridge] \" .. detail)", Script);
    }

    [Fact]
    public void SnapshotBootstrap_SerializesVerifiedLooseCardInsertionBeforeReadingTheLibraryLedger()
    {
        Assert.Contains("function BridgeStagePhysicalCardForBootstrap(object, seatId, callback)", Script);
        Assert.Contains("refused to stage a library card into itself", Script);
        Assert.Contains("BridgeInsertPhysicalCardIntoLibrary(seatId, object, \"NORMAL\"", Script);
        Assert.Contains("function BridgeStageSeatCardsForBootstrap(snapshot, callback)", Script);
        Assert.Contains("BridgeStagePhysicalCardForBootstrap(item.object, item.seatId, function(ok, err)", Script);
        Assert.Contains("BridgeVerifyLibraryContainment(seatId, guid", Script);
        Assert.Contains("BridgeAuditDuplicateLibraryGuids", Script);
        Assert.Contains("START-13 loose-card-staging", Script);
    }

    [Fact]
    public void NewMatch_ReturnsTrackedPreviousGameCardsBeforeReadingDeckInventory()
    {
        Assert.Contains("function BridgeReturnPreviousGameCardsToLibraries", Script);
        Assert.Contains("BridgeState.physicalSeatByGuid[guid]", Script);
        Assert.Contains("BridgeState.physicalZoneByGuid[guid]", Script);
        Assert.Contains("BridgeInsertPhysicalCardIntoLibrary(candidate.seatId, candidate.object, \"NORMAL\"", Script);
        Assert.Contains("TTS Deck-on-Deck operations", Script);
        Assert.Contains("if not BridgeObjectIsUsable(object) or object.tag ~= \"Card\" then", Script);
        Assert.Contains("if not BridgeObjectIsUsable(object) or object.tag ~= \"Card\" then return end", Script);
        var reset = Script.Substring(Script.IndexOf("function BridgeResetSession()", StringComparison.Ordinal));
        Assert.Contains("BridgeReturnPreviousGameCardsToLibraries(function", reset);
        Assert.True(reset.IndexOf("BridgeReturnPreviousGameCardsToLibraries", StringComparison.Ordinal)
            < reset.IndexOf("BridgeConfigureDecks", StringComparison.Ordinal));
    }

    [Fact]
    public void F2cHud_IsMountedOnceAndRoutesChoicesThroughHardenedChoiceSubmission()
    {
        Assert.Contains("function BridgeUiMount()", Script);
        Assert.DoesNotContain("UI.setXml(", Script);
        var xml = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.xml"));
        Assert.Contains("BridgeHudRoot", xml);
        Assert.Contains("BridgeHudAction24", xml);
        Assert.Contains("function BridgeUiFlush()", Script);
        Assert.Contains("UI.setAttribute", Script);
        Assert.Contains("BridgeSubmitChoice(decision.decisionId, action.actionId, \"hud_action\")", Script);
        Assert.Contains("BridgeState.retiredChoiceDecisionIds[decision.decisionId] == true", Script);
        Assert.Contains("BridgeDecisionHasAction(decision, action.actionId)", Script);
    }

    [Fact]
    public void HudLayout_DoesNotLetNestedLayoutExpandGlobalHudToTheScreen()
    {
        var xml = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.xml"));

        Assert.Contains("width=\"700\"", xml);
        Assert.Contains("height=\"630\"", xml);
        Assert.DoesNotContain("<VerticalLayout width=\"100%\" height=\"100%\"", xml);
    }

    [Fact]
    public void F2cHud_UsesBoundedRowsAndSuppressesNormalPathPhysicalOptionSpawns()
    {
        Assert.Contains("for i = 1, 24 do", Script);
        Assert.Contains("BridgeState.ui.uiFullRebuildCount", Script);
        Assert.Contains("if BridgeState.ui ~= nil and BridgeState.ui.mounted then", Script);
        Assert.Contains("function BridgeOpenCardContext(cardInstanceId)", Script);
        Assert.Contains("action.sourceCardInstanceId or action.cardInstanceId", Script);
    }

    [Fact]
    public void CreatureTypeDecision_UsesDecisionScopedDropdownAndExplicitConfirm()
    {
        var xml = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.xml"));
        Assert.Contains("BridgeHudCreatureTypePanel", xml);
        Assert.Contains("id=\"BridgeHudCreatureTypePanel\" active=\"false\"", xml);
        Assert.Contains("Dropdown id=\"BridgeHudCreatureTypeDropdown\"", xml);
        Assert.Contains("options=\"Choose\" value=\"Choose\"", xml);
        Assert.Contains("onValueChanged=\"BridgeHudCreatureTypeChanged\"", xml);
        Assert.Contains("BridgeHudCreatureTypeConfirm", xml);
        Assert.Contains("BridgeHudCreatureTypeCancel", xml);
        Assert.Contains("function BridgeCreatureTypePrepare", Script);
        Assert.Contains("function BridgeHudCreatureTypeChanged", Script);
        Assert.Contains("function BridgeHudCreatureTypeConfirm", Script);
        Assert.Contains("BridgeSubmitChoice(decision.decisionId, actionId, \"creature_type_confirm\")", Script);
        Assert.Contains("if decision ~= nil and decision.kind == \"creature_type_selection\" then actions = {} end", Script);
        Assert.Contains("not requiresConfirm and not creatureTypeDecision", Script);
        var changedStart = Script.IndexOf("function BridgeHudCreatureTypeChanged", StringComparison.Ordinal);
        var confirmStart = Script.IndexOf("function BridgeHudCreatureTypeConfirm", StringComparison.Ordinal);
        Assert.True(changedStart >= 0 && confirmStart > changedStart);
        Assert.DoesNotContain("BridgeSubmitChoice(", Script[changedStart..confirmStart]);
        Assert.Contains("BridgeCreatureTypeClearDraft(\"decision-replaced\")", Script);
        Assert.Contains("BridgeCreatureTypeClearDraft(\"decision-retired\")", Script);
        Assert.Contains("BridgeCreatureTypeClearDraft(\"session-replaced\")", Script);
        Assert.Contains("TTS Dropdown cannot safely hold an empty option list", Script);
    }

    [Fact]
    public void GraveyardActions_UseDecisionScopedFolderWithoutChangingForgeActions()
    {
        var xml = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.xml"));
        Assert.Contains("BridgeHudGraveyardPanel", xml);
        Assert.Contains("BridgeHudGraveyardAction24", xml);
        Assert.Contains("BridgeHudGraveyardPage", xml);
        Assert.Contains("BRIDGE_GRAVEYARD_ACTION_GROUP_THRESHOLD = 6", Script);
        Assert.Contains("BridgeGraveyardPrepareDecision(decision, actions)", Script);
        Assert.Contains("action.isGraveyardFolder == true", Script);
        Assert.Contains("BridgeDecisionHasAction(decision, action.actionId)", Script);
        Assert.Contains("ui.graveyardFolderDecisionId ~= decision.decisionId", Script);
        Assert.Contains("BridgeGraveyardClear(\"decision-replaced\")", Script);
        Assert.Contains("BridgeGraveyardClear(\"session-replaced\")", Script);
        Assert.Contains("BridgeGraveyardClear(\"decision-retired\")", Script);
        Assert.Contains("#graveyard <= BRIDGE_GRAVEYARD_ACTION_GROUP_THRESHOLD", Script);
        Assert.Contains("graveyardFolderPage", Script);
        Assert.Contains("BridgeHudGraveyardPrev", xml);
        Assert.Contains("sourceZone or \"\"", Script);
        Assert.Contains("GRAVEYARD ACTIONS (\" .. tostring(#graveyard) .. \")", Script);
    }

    [Fact]
    public void KeywordLayout_UsesNativeEncoderValueAndCachesAbovePreference()
    {
        Assert.Contains("function BridgeEnsureKeywordIconLayout(object, encoder)", Script);
        Assert.Contains("valueID = \"iconLayout\"", Script);
        Assert.Contains("data = {iconLayout = \"above\"}", Script);
        Assert.Contains("BridgeState.presentedIconLayoutByGuid", Script);
    }

    [Fact]
    public void Launcher_CanStartForgeWithAuthoritativeManualManaChoices()
    {
        var launcher = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "tools", "Start-ForgeBot.ps1"));
        Assert.Contains("[switch]$ManualMana", launcher);
        Assert.Contains("--askmana", launcher);
    }

    [Fact]
    public void TerminalGameEvent_StopsGameplayPollingAndKeepsNewMatchPathAvailable()
    {
        Assert.Contains("if event.kind == \"game_ended\" then", Script);
        Assert.Contains("BridgeStopDecisionPolling()", Script);
        Assert.Contains("BridgeStopEventPolling()", Script);
        Assert.Contains("BridgeScheduleSnapshotReconcile(\"game_ended final state\")", Script);
        Assert.Contains("BridgeState.gameEnded", Script);
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
    public void FastPlaytest_OnlyAcceleratesExpectedTransitionsNotIdleForgeBackoff()
    {
        var scheduleStart = Script.IndexOf("function BridgeScheduleDecisionPoll", StringComparison.Ordinal);
        var pollStart = Script.IndexOf("function BridgePollForNextDecision", scheduleStart, StringComparison.Ordinal);
        Assert.True(scheduleStart >= 0 && pollStart > scheduleStart);
        var schedule = Script[scheduleStart..pollStart];

        Assert.Contains("BridgeState.ui.fastPlaytest and BridgeTransitionExpected()", schedule);
        Assert.DoesNotContain("BridgeState.ui.fastPlaytest then nextDelay", schedule);
        Assert.Contains("local retryDelay = BridgeTransitionExpected() and 0.1 or 0.5", Script);
    }

    [Fact]
    public void ChoiceSubmission_UsesDecisionScopedTransactionsAndBoundedRetirement()
    {
        Assert.Contains("BRIDGE_SCRIPT_REVISION = \"2026-08-30-u2-gameplay-repair\"", Script);
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
        Assert.Contains("local deficit = expectedCount - physicalCount", Script);
        Assert.Contains("return false, BridgeLibraryMismatchMessage", Script);
        Assert.Contains("BridgeSetStatus(\"LIBRARY MISMATCH\", diagnostic)", Script);
    }

    [Fact]
    public void PhysicalGraveyardDiscard_SubmitsForgeSelectionThenRendersReturnedDoneStep()
    {
        Assert.Contains("if object.tag == \"Card\" and action.type == \"discard_card\" and BridgeIsDiscardChoice(decision) then", Script);
        Assert.Contains("if BridgeObjectNearSeatZone(object, intent.seatId, \"graveyard\") then", Script);
        Assert.Contains("BridgeSubmitChoice(decisionId, actionId, \"physical_discard_graveyard\")", Script);
        Assert.Contains("BridgeTryFinishDiscardChoice(body.currentDecision, activeTransaction.source)", Script);
        Assert.Contains("awaiting explicit Done", Script);
        Assert.DoesNotContain("discard_auto_done", Script);
    }

    [Fact]
    public void LegacyDiscardSelection_SubmitsExactActionForClickHudAndGraveyardDrop()
    {
        Assert.Contains("decision.kind == \"card_selection\" and BridgeDecisionContainsDiscardAction(decision)", Script);
        Assert.Contains("BridgeSubmitChoice(decision.decisionId, action.actionId, \"hud_discard_card\")", Script);
        Assert.Contains("BridgeState.pendingIntent = {", Script);
        Assert.Contains("BridgeSubmitChoice(decisionId, actionId, \"physical_discard_click\")", Script);
        Assert.Contains("Forge remains the sole authority for the actual zone move", Script);
    }

    [Fact]
    public void CrewCostSelection_UsesExactForgeCandidatesAndSharedStructuredControls()
    {
        Assert.Contains("tostring(decision.costKind or \"\") == \"crew\"", Script);
        Assert.Contains("kind == \"cost_selection\"", Script);
        Assert.Contains("physical_structured_toggle", Script);
        Assert.Contains("hud_structured_toggle", Script);
    }

    [Fact]
    public void BootstrapInventory_AccountsForHandsAndCommandZoneWithoutCrossSeatNameClaims()
    {
        var candidateStart = Script.IndexOf("function IsGameCardCandidate", StringComparison.Ordinal);
        var candidateEnd = Script.IndexOf("function BridgeDeckContainsCardName", candidateStart, StringComparison.Ordinal);
        var candidate = Script[candidateStart..candidateEnd];

        Assert.Contains("A card in a TTS hand", candidate);
        Assert.Contains("if seatHandGuids ~= nil and seatHandGuids[guid] == true then return true end", candidate);
        Assert.True(candidate.IndexOf("if seatHandGuids", StringComparison.Ordinal)
            < candidate.IndexOf("if not BridgeObjectIsOnSeatSide", StringComparison.Ordinal));
        Assert.Contains("if not BridgeObjectIsOnSeatSide(object, seat) then return false end", candidate);
        Assert.DoesNotContain("and BridgeObjectIsOnSeatSide(object, seat)", Script[Script.IndexOf("function BridgeCollectSeatAssets", StringComparison.Ordinal)..Script.IndexOf("function BridgeBuildSeatLibraryLedger", StringComparison.Ordinal)]);
        Assert.Contains("elseif zone.name == \"command\" then", Script);
        Assert.Contains("BridgeResolveSeatZoneAnchor(seatSnapshot.seatId, \"command\")", Script);
    }

    [Fact]
    public void BootstrapIdentity_UsesCanonicalImportedNameRatherThanMutableFacePresentation()
    {
        Assert.Contains("function BridgePhysicalCanonicalCardName(object)", Script);
        Assert.Contains("canonical = data.Nickname or data.nickname", Script);
        Assert.Contains("BridgeState.canonicalCardNameByGuid", Script);
        Assert.Contains("local cardName = BridgePhysicalCanonicalCardName(object)", Script);
        Assert.Contains("Forge's cardName is likewise the", Script);
        Assert.Contains("stable identity; currentCardName is only for post-mapping presentation", Script);
    }

    [Fact]
    public void BootstrapInventory_ExcludesOnlyPresentationObjectsAndKeepsHardSafetyBoundary()
    {
        Assert.Contains("presentationOnlyGuids = { [\"946716\"]", Script);
        Assert.Contains("if BridgeIsPresentationOnlyObject(object) then return false end", Script);
        Assert.Contains("presentation_only:", Script);
        Assert.Contains("mappedForgeInstance=%s trackedZone=%s handSeat=%s containedCount=%d reason=%s", Script);
        Assert.Contains("if physicalCount < expectedCount then", Script);
    }

    [Fact]
    public void ForgePresentation_UsesStablePrintedStatsAndRendersKeywordsInAlternateLayout()
    {
        Assert.Contains("function BridgeUnifiedPrintedFace(unified)", Script);
        Assert.Contains("faces[1] or faces[0] or faces.front", Script);
        Assert.Contains("BridgeState.presentedStatsByGuid", Script);
        Assert.Contains("if event.kind == \"stats_changed\" then", Script);
        Assert.Contains("function BridgeRenderKeywordDecals(object, enabled, encoder)", Script);
        Assert.Contains("layout == \"above\"", Script);
        Assert.Contains("BridgeRenderKeywordDecals(object, enabled, encoder)", Script);
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
        Assert.Contains("or (event.kind == \"card_moved\"", Script);
        Assert.Contains("pendingStructuredZoneTransitionByInstanceId[event.cardInstanceId]", Script);
        Assert.Contains(".applied ~= true", Script);
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
    public void ResolvedSpellWithoutExactInstance_DefersToStructuredSnapshotInsteadOfGuessing()
    {
        var start = Script.IndexOf("if event.kind == \"spell_resolved\" and event.destinationZone == \"graveyard\" then", StringComparison.Ordinal);
        var end = Script.IndexOf("if event.kind == \"spell_resolved\" and event.destinationZone == \"battlefield\" then", start, StringComparison.Ordinal);
        var handler = Script[start..end];
        Assert.Contains("if event.cardInstanceId == nil then", handler);
        Assert.Contains("pendingCastBySeatId[event.seatId]", handler);
        Assert.Contains("BridgeScheduleSnapshotReconcile(\"semantic spell resolution without exact instance\")", handler);
        Assert.Contains("BridgeScheduleSnapshotReconcile(\"unmapped resolved spell \"", handler);
        Assert.Contains("resolved spell presentation deferred event=", handler);
        Assert.Contains("return true, 0.1", handler);
    }

    [Fact]
    public void SemanticSpellResolution_CannotMoveCrewedVehicleFromBattlefield()
    {
        var start = Script.IndexOf("if event.kind == \"spell_resolved\" and event.destinationZone == \"graveyard\" then", StringComparison.Ordinal);
        var end = Script.IndexOf("if event.kind == \"tap_changed\" then", start, StringComparison.Ordinal);
        var handler = Script[start..end];

        // TUI resolution text is not an identity-bearing zone transition.
        // Only a physically tracked stack object may use the semantic fallback;
        // a Vehicle/ability source already on the battlefield must remain there.
        Assert.Contains("pendingZone ~= \"stack\"", handler);
        Assert.Contains("mappedZone ~= \"stack\"", handler);
        Assert.Contains("semantic ability resolution for non-stack object", handler);
        Assert.Contains("semantic ability resolution for non-stack mapped object", handler);
        Assert.Contains("BridgeScheduleSnapshotReconcile", handler);

        var resolverStart = Script.IndexOf("function BridgeResolveResolvedSpellObject(event)", StringComparison.Ordinal);
        var resolverEnd = Script.IndexOf("-- Table-native presentation adapter", resolverStart, StringComparison.Ordinal);
        var resolver = Script[resolverStart..resolverEnd];
        Assert.Contains("BridgeResolvePhysicalCard(event, \"stack\")", resolver);
        Assert.DoesNotContain("{\"stack\", \"battlefield\", \"hand\"}", resolver);
    }

    [Fact]
    public void MainPriorityActions_BindExactActivatedAbilitySourceOutsideHand()
    {
        var start = Script.IndexOf("local presentationInstanceId = action.preparedSourceCardInstanceId", StringComparison.Ordinal);
        var end = Script.IndexOf("if mappedSeatMatches and mappedZoneMatches then", start, StringComparison.Ordinal);
        var binding = Script[start..end];

        Assert.Contains("action.preparedSourceCardInstanceId or action.cardInstanceId", binding);
        Assert.Contains("action.sourceZone", binding);
        Assert.Contains("mappedPhysicalZone == actionSourceZone", binding);
        Assert.Contains("action.type == \"activate_ability\"", binding);
        Assert.Contains("mappedPhysicalZone == \"battlefield\"", binding);
        Assert.Contains("mappedPhysicalZone == \"graveyard\"", binding);
        Assert.Contains("mappedSourceZoneMatches", binding);
        Assert.Contains("exactMappingContradictsActionSource", binding);
        Assert.Contains("suppressing stale exact action", binding);
    }

    [Fact]
    public void SnapshotBattlefieldRepair_PreservesForgeRowKindAndTapDoesNotReflow()
    {
        Assert.Contains("battlefieldKind = card.battlefieldKind", Script);
        Assert.Contains("function BridgeBattlefieldRowForEvent(event, defaultRow)", Script);
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
        Assert.Contains("graveyardAnchor = {x = 1.7714, y = 2.0, z = -12.2921}", Script);
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
    public void CastPreview_IsReachableFromTheHudAndRemainsReversible()
    {
        Assert.Contains("CAST PREVIEW — press CAST / CONFIRM or CANCEL / RETURN", Script);
        Assert.Contains("BridgeHudConfirm", Script);
        Assert.Contains("BridgeConfirmCastPreview(nil, player, false)", Script);
        Assert.Contains("BridgeCancelCastPreview(nil, player, false)", Script);
        Assert.Contains("castPreviewPending", Script);
    }

    [Fact]
    public void CombatCandidates_AreOrangeFollowupChoices()
    {
        Assert.Contains("if decision.kind ~= \"main_priority\" and not BridgeIsStructuredForgeToggleChoice(decision) then", Script);
        Assert.Contains("highlightColor = {1.0, 0.55, 0.0}", Script);
    }

    [Fact]
    public void StructuredCollections_KeepBlueLegalChoiceHighlights()
    {
        var renderStart = Script.IndexOf("function BridgeRenderDecision(decision, force)", StringComparison.Ordinal);
        var candidateStart = Script.IndexOf("local representedActionIds", renderStart, StringComparison.Ordinal);
        Assert.True(renderStart >= 0 && candidateStart > renderStart);
        var highlight = Script[renderStart..candidateStart];

        Assert.Contains("not BridgeIsStructuredForgeToggleChoice(decision)", highlight);
        Assert.Contains("local highlightColor = {0.53, 0.81, 0.98}", highlight);
    }

    [Fact]
    public void ResourceCounters_UseSeatSpecificPresentationRotation()
    {
        var showStart = Script.IndexOf("function BridgeShowResourceCounter", StringComparison.Ordinal);
        var findStart = Script.IndexOf("function BridgeFindResourceCounter", showStart, StringComparison.Ordinal);
        Assert.True(showStart >= 0 && findStart > showStart);
        var show = Script[showStart..findStart];

        Assert.Contains("seat.resourceRotation", show);
        Assert.Contains("counter.setRotation(seat.resourceRotation)", show);
        Assert.Contains("BridgeShowResourceCounter(counter, position, seat)", Script);
        Assert.Contains("resourceRotation = {x = 0, y = 90, z = 0}", Script);
        Assert.Contains("resourceRotation = {x = 0, y = 270, z = 0}", Script);
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
        Assert.Contains("presentationInstanceId and BridgeState.physicalByInstanceId[presentationInstanceId]", Script);
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
    public void ExtractedTableGeometryAndPresentationRegistryProtectGameCardIdentity()
    {
        Assert.Contains("graveyardAnchor = {x = 1.7714, y = 2.0, z = -12.2921}", Script);
        Assert.Contains("exileAnchor = {x = 1.7575, y = 2.0, z = -15.9598}", Script);
        Assert.Contains("graveyardAnchor = {x = 1.7476, y = 2.0, z = 12.3162}", Script);
        Assert.Contains("exileAnchor = {x = 1.7837, y = 2.0, z = 15.9528}", Script);
        Assert.Contains("presentationOnlyGuids = { [\"946716\"]", Script);
        Assert.Contains("function BridgeRegisterPresentationObject(objectOrGuid, kind)", Script);
        Assert.Contains("if BridgeIsPresentationOnlyObject(object) then return false end", Script);
        Assert.Contains("refusing Forge mapping for presentation object", Script);
    }

    [Fact]
    public void PlayerTrackersAndMonarchUseNativeTableAssets()
    {
        Assert.Contains("BRIDGE_PLAYER_TRACKER_SOURCES", Script);
        Assert.Contains("poison = \"81ae86\", experience = \"1ea882\", energy = \"328fa7\", speed = \"2c18ff\"", Script);
        Assert.Contains("function BridgeSetSeatTracker(seatId, kind, value)", Script);
        Assert.Contains("BridgeRegisterPresentationObject(taken, \"player_tracker_\" .. kind)", Script);
        Assert.Contains("function BridgeSetMonarchSeat(seatId)", Script);
        Assert.Contains("utility deck 946716", Script);
        Assert.Contains("BridgeRegisterPresentationObject(helper, \"monarch_helper\")", Script);
        Assert.Contains("BridgeSetMonarchSeat(snapshot and snapshot.monarchSeatId or nil)", Script);
    }

    [Fact]
    public void ResourceRowMaterializesOnlyPositiveAuthoritativeValuesAndRepacks()
    {
        Assert.Contains("BRIDGE_RESOURCE_ORDER = {\"W\", \"U\", \"B\", \"R\", \"G\", \"C\", \"energy\", \"experience\", \"poison\", \"speed\"}", Script);
        Assert.Contains("function BridgeRefreshResourceRow(seatId)", Script);
        Assert.Contains("if value > 0 then", Script);
        Assert.Contains("slot = slot + 1", Script);
        Assert.Contains("BridgeHideResourceCounter(counter)", Script);
        Assert.Contains("BridgeResourceRowPosition(seatId, slot)", Script);
        Assert.Contains("BridgeState.playerStateBySeatId[seatId].mana", Script);
        Assert.Contains("BridgeState.playerCountersBySeatId[seatId][kind] = amount", Script);
    }

    [Fact]
    public void ResourceRowNeverDestroysNativeTemplatesAndIsResetSafe()
    {
        Assert.Contains("source.clone({position = position})", Script);
        Assert.Contains("source.takeObject({position = position", Script);
        Assert.Contains("if BridgeIsPresentationOnlyObject(object) then", Script);
        Assert.Contains("function BridgeRetireResourceRowObjects()", Script);
        Assert.Contains("BridgeState.resourceCounterGuidBySeatId = {}", Script);
        Assert.Contains("sessionId ~= BridgeState.eventSessionId", Script);
    }

    [Fact]
    public void TurnHudSeparatesActiveTurnOwnerFromPriorityAndRetiresStalePriority()
    {
        Assert.Contains("local owner = BridgeState.currentTurnSeatId == \"forge-player-1\" and \"YOUR TURN\"", Script);
        Assert.Contains("or (BridgeState.currentTurnSeatId and \"OPPONENT TURN\"", Script);
        Assert.Contains("or \"NO PRIORITY\"", Script);
        Assert.Contains("if event.prioritySeatId ~= nil then BridgeState.prioritySeatId = event.prioritySeatId end", Script);
        Assert.Contains("if event.kind == \"priority_changed\" then", Script);
        Assert.Contains("BridgeUiMarkDirty(\"priority\")", Script);
        Assert.Contains("BridgeState.currentPhase = nil", Script);
    }

    [Fact]
    public void DuplicateTurnPhasePriorityEvents_AreDeduplicatedBeforeUiResetWork()
    {
        Assert.Contains("lastTurnEventSignature", Script);
        Assert.Contains("lastPhaseEventSignature", Script);
        Assert.Contains("lastPriorityEventSignature", Script);
        Assert.Contains("if BridgeState.lastPhaseEventSignature == phaseSignature then", Script);
        Assert.Contains("if BridgeState.lastPriorityEventSignature == prioritySignature then", Script);
        Assert.Contains("if BridgeState.lastTurnEventSignature == turnSignature then", Script);
    }

    [Fact]
    public void TurnHudUsesAuthoritativePhaseAndOwnerTextInAdditionToRibbonColor()
    {
        Assert.Contains("BridgeTurnLabel() .. \" — \" .. owner .. \" — \"", Script);
        Assert.Contains("BridgeUiSet(\"BridgeHudTop\", \"text\", turn", Script);
        Assert.Contains("BridgeHudRefreshPhaseRibbon()", Script);
        Assert.Contains("BridgeUiMarkDirty(\"turn\")", Script);
        Assert.Contains("BridgeUiMarkDirty(\"phase\")", Script);
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
    public void BattlefieldMovementRestoresCanonicalScaleAfterDeferredTtsPresentation()
    {
        Assert.Contains("TTS hand/Encoder presentation can apply a scale change", Script);
        Assert.Contains("BridgeWaitFrames(function()", Script);
        Assert.Contains("BridgeRestoreCanonicalCardScale(object)", Script);
    }

    [Fact]
    public void DrawAndImmediateLandPlay_WaitsForExactStructuredLibraryTransition()
    {
        Assert.Contains("battlefieldKindByInstanceId", Script);
        Assert.Contains("awaiting exact structured transition", Script);
        Assert.Contains("function moveFromLibraryDeckToBattlefield(deck)", Script);
        Assert.Contains("event.sourceZone == \"library\" and event.destinationZone == \"battlefield\"", Script);
        Assert.Contains("BridgeQueueLibraryExtraction(event.seatId", Script);
        Assert.Contains("BridgeTakeTopCardFromLibrary(liveDeck, expectedName", Script);
    }

    [Fact]
    public void LibraryMill_UsesSerializedExactExtractionBeforeLaterDraws()
    {
        var moveStart = Script.IndexOf("function BridgeApplyStructuredCardMove(event)", StringComparison.Ordinal);
        var moveEnd = Script.IndexOf("function BridgeMoveToGraveyard", moveStart, StringComparison.Ordinal);
        var moveBody = Script[moveStart..moveEnd];

        Assert.Contains("function moveFromLibraryDeckToGraveyard(deck)", moveBody);
        Assert.Contains("BridgeQueueLibraryExtraction(event.seatId", moveBody);
        Assert.Contains("BridgeTakeTopCardFromLibrary(liveDeck, expectedName", moveBody);
        Assert.Contains("BridgeMoveToGraveyard(event, taken)", moveBody);
        Assert.Contains("BridgeWaitTime(complete, BRIDGE_DRAW_EVENT_PRESENTATION_DELAY)", moveBody);
        Assert.Contains("event.sourceZone == \"library\" and event.destinationZone == \"graveyard\"", moveBody);
        Assert.DoesNotContain("resolved object is a deck for non-library->hand move", moveBody);
        Assert.Contains("BridgeRecoverFromLibraryOrderMismatch(takeError)", moveBody);
    }

    [Fact]
    public void AuthoritativeLibraryTransitions_ExtractTheTopCardRatherThanSelectingByName()
    {
        var topStart = Script.IndexOf("function BridgeTakeTopCardFromLibrary", StringComparison.Ordinal);
        var topEnd = Script.IndexOf("function BridgeTakeNamedCardFromDeck", topStart, StringComparison.Ordinal);
        var topBody = Script[topStart..topEnd];

        Assert.Contains("local top = containedCards[1]", topBody);
        Assert.Contains("index = top.index", topBody);
        Assert.Contains("top order mismatched authoritative transition", topBody);
        Assert.DoesNotContain("for _, contained in ipairs(containedCards) do", topBody);
    }

    [Fact]
    public void LibraryOrderMismatch_RequestsAuthoritativeRecoveryInsteadOfStoppingTheMatch()
    {
        var start = Script.IndexOf("function BridgeRecoverFromLibraryOrderMismatch", StringComparison.Ordinal);
        var end = Script.IndexOf("function BridgeApplyStructuredCardMove", start, StringComparison.Ordinal);
        var recovery = Script[start..end];

        Assert.Contains("library top order mismatched", recovery);
        Assert.Contains("BridgeResyncFromAuthoritativeSnapshot(\"library order mismatch\")", recovery);
        Assert.Contains("consecutive mill transitions", recovery);
    }

    [Fact]
    public void BootstrapAlignsThePhysicalLibraryToForgeSnapshotOrderBeforeLiveDraws()
    {
        var alignmentStart = Script.IndexOf("function BridgeAlignLibraryOrderForSnapshot", StringComparison.Ordinal);
        var alignmentEnd = Script.IndexOf("function BridgeTryBootstrapSeatSnapshot", alignmentStart, StringComparison.Ordinal);
        var alignment = Script[alignmentStart..alignmentEnd];

        Assert.Contains("table.sort(libraryCards", alignment);
        Assert.Contains("local nextIndex = #libraryCards", alignment);
        Assert.Contains("BridgeTakeCardFromDeckByIdentity", alignment);
        Assert.Contains("current.putObject(taken, 0)", alignment);
        var bootstrapStart = Script.IndexOf("function BridgeTryBootstrapSeatSnapshot", StringComparison.Ordinal);
        var bootstrapEnd = Script.IndexOf("function BridgeCollectSeatAssets", bootstrapStart, StringComparison.Ordinal);
        var bootstrap = Script[bootstrapStart..bootstrapEnd];
        Assert.Contains("BridgeMaterializeSeatSnapshot", bootstrap);
        Assert.Contains("BridgeAlignLibraryOrderForSnapshot(seatSnapshot", bootstrap);
    }

    [Fact]
    public void PassiveAutoPass_IsDisabledForHumanSeatToPreventPhaseSkipping()
    {
        Assert.Contains("function BridgeDecisionHasNonPassAction", Script);
        Assert.Contains("empty_priority_auto_pass", Script);
        Assert.Contains("decision.seatId ~= \"forge-player-1\"", Script);
        Assert.Contains("not BridgeDecisionHasNonPassAction(decision)", Script);
        Assert.Contains("Keep passive auto-pass off for the human seat", Script);
        Assert.Contains("Priority/active-seat fields are descriptive state, not ordering keys", Script);
        Assert.DoesNotContain("if stalePrioritySeat or activeMismatch then", Script);
    }

    [Fact]
    public void QueuedStateEvents_CannotEraseANewerAcceptedDecision()
    {
        var applyStart = Script.IndexOf("function BridgeApplyAuthoritativeEvent(event)", StringComparison.Ordinal);
        var applyEnd = Script.IndexOf("function BridgeMoveToBattlefield", applyStart, StringComparison.Ordinal);
        var applyBody = Script[applyStart..applyEnd];

        Assert.Contains("function BridgeCurrentDecisionOutrunsEvent(event)", Script);
        Assert.Contains("function BridgePhaseEventMatchesCurrentDecision(event)", Script);
        Assert.Contains("retaining newer decision", applyBody);
        Assert.Contains("local retainCurrentDecision = BridgePhaseEventMatchesCurrentDecision(event)", applyBody);
        Assert.Contains("if not retainCurrentDecision then", applyBody);
        Assert.Contains("BridgeRenderDecision(BridgeState.lastDecision, true)", applyBody);
    }

    [Fact]
    public void AuthoritativeDrawAndPhaseTransitionsRefreshTheCurrentDecision()
    {
        Assert.Contains("if event.kind == \"draw\" or event.kind == \"turn_changed\" or event.kind == \"phase_changed\" then", Script);
        Assert.Contains("BridgeStartDecisionPolling()", Script);
        Assert.Contains("newly available hand actions", Script);
    }

    [Fact]
    public void CardContext_CannotHidePassYieldOrTheNextDecisionActions()
    {
        var uiStart = Script.IndexOf("function BridgeUiFlush", StringComparison.Ordinal);
        var uiEnd = Script.IndexOf("function BridgeUiMount", uiStart, StringComparison.Ordinal);
        var uiBody = Script[uiStart..uiEnd];
        var acceptStart = Script.IndexOf("function BridgeAcceptDecision", StringComparison.Ordinal);
        var acceptEnd = Script.IndexOf("function BridgeNormalizeCardName", acceptStart, StringComparison.Ordinal);
        var acceptBody = Script[acceptStart..acceptEnd];

        Assert.Contains("for _, action in ipairs(decision and decision.actions or {}) do", uiBody);
        Assert.Contains("Pass/Yield are properties of the full", uiBody);
        Assert.Contains("BridgeState.ui.contextInstanceId = nil", acceptBody);
        Assert.Contains("Retaining it after Forge changes decisions", acceptBody);
    }

    [Fact]
    public void HiddenLibraryIdentityCanary_FailsClosedUnlessForgeExplicitlyAuthorizesPresentation()
    {
        Assert.Contains("function BridgeActionPresentationAuthorized(action)", Script);
        Assert.Contains("sourceZone == \"library\"", Script);
        Assert.Contains("action.isPresentationAuthorized == true", Script);
        Assert.Contains("BridgeDecisionHasUnauthorizedPresentationAction(decision)", Script);
        Assert.Contains("Forge supplied an unapproved hidden-zone action", Script);
        Assert.Contains("suppressed unauthorized hidden-zone option control", Script);
    }

    [Fact]
    public void OrdinaryPriorityActions_AreNotRenderedAsMultiSelectCheckboxes()
    {
        var uiStart = Script.IndexOf("function BridgeUiFlush", StringComparison.Ordinal);
        var uiEnd = Script.IndexOf("function BridgeUiMount", uiStart, StringComparison.Ordinal);
        var uiBody = Script[uiStart..uiEnd];

        Assert.Contains("Ordinary priority actions are immediate exact Forge inputs", uiBody);
        Assert.Contains("local selectionPresentation = BridgeDecisionNeedsConfirmation(decision)", uiBody);
        Assert.Contains("or decision.kind == \"attacker_selection\"", uiBody);
        Assert.Contains("local prefix = \"\"", uiBody);
    }

    [Fact]
    public void UnboundHandDrags_AreRolledBackUnlessBackInHandZone()
    {
        Assert.Contains("function BridgeCaptureUnboundPickupIntent", Script);
        Assert.Contains("function BridgeRejectUnboundDropIfIllegal", Script);
        Assert.Contains("if intent.zone ~= \"hand\" then return end", Script);
        Assert.Contains("if BridgeObjectNearSeatZone(object, intent.seatId, \"hand\") then return end", Script);
        Assert.Contains("illegal physical move rejected; use a highlighted Forge action", Script);
    }

    [Fact]
    public void CombatPickups_BypassSingleSelectionDraftLimit()
    {
        Assert.Contains("action.type ~= \"choose_attacker\"", Script);
        Assert.Contains("action.type ~= \"choose_blocker\"", Script);
    }

    [Fact]
    public void TwoPlayerDefenderSelection_SuppressesIllegalSelfTargetSurface()
    {
        Assert.Contains("suppressing illegal self-defender target in two-player match", Script);
        Assert.Contains("decision.kind == \"defender_selection\"", Script);
    }

    [Fact]
    public void PriorityStatusUsesDecisionSeatInsteadOfHardcodedHumanHeadline()
    {
        Assert.Contains("local priorityHeadline = decision.seatId == \"forge-player-1\" and \"YOUR PRIORITY\" or \"OPPONENT PRIORITY\"", Script);
        Assert.DoesNotContain("BridgeSetStatus(\"YOUR PRIORITY\", BridgeTurnLabel()", Script);
    }

    [Fact]
    public void HudPhaseColorIsDerivedFromAuthoritativePhaseWithoutAdvancingTurn()
    {
        Assert.Contains("function BridgeHudPhaseColor(phase)", Script);
        Assert.Contains("BridgeHudStatus\", \"color\", terminal and \"#F8FAFC\" or BridgeHudPhaseColor(BridgeState.currentPhase)", Script);
        Assert.Contains("BridgeHudRefreshPhaseRibbon()", Script);
    }

    [Fact]
    public void CombatDecisionsCannotRenderBeforeAuthoritativeCombatPhase()
    {
        Assert.Contains("ignoring combat decision before phase transition", Script);
        Assert.Contains("decision.kind == \"attacker_selection\"", Script);
        Assert.Contains("string.find(phase, \"COMBAT\", 1, true)", Script);
    }

    [Fact]
    public void DecisionPhaseMetadataCannotRegressAuthoritativeEventPhase()
    {
        Assert.Contains("retaining event phase=%s over stale decision phase=%s", Script);
        Assert.Contains("decisionCursor <= 0 or decisionCursor >= appliedCursor", Script);
        Assert.Contains("BridgeState.currentPhase = decisionPhase", Script);
    }

    [Fact]
    public void OpeningHandLibraryExtractions_AreSerializedAndSingleCardLibrariesRemainDrawable()
    {
        Assert.Contains("function BridgeQueueLibraryExtraction", Script);
        Assert.Contains("function BridgeProcessLibraryExtractionQueue", Script);
        Assert.Contains("deck.tag == \"Card\"", Script);
        Assert.Contains("physical single-card library mismatched authoritative identity", Script);
        Assert.Contains("opening-hand draws", Script);
        Assert.Contains("library-extraction-complete", Script);
    }

    [Fact]
    public void MulliganBottomUsesExplicitDeckIndex_NotRotationHeuristic()
    {
        Assert.Contains("function BridgeInsertPhysicalCardIntoLibrary", Script);
        Assert.Contains("local entries = BridgeLibraryEntries(library)", Script);
        Assert.Contains("library.putObject(object, #entries)", Script);
        Assert.Contains("BridgeVerifyLibraryContainment", Script);
        Assert.Contains("attempt >= 30", Script);
        Assert.Contains("return (tonumber(left.zonePosition or 0) or 0) < (tonumber(right.zonePosition or 0) or 0)\n    end)", Script.ReplaceLineEndings("\n"));
        Assert.DoesNotContain("local inverted = {rotation.x, rotation.y, rotation.z + 180}", Script);
    }

    [Fact]
    public void LifelinkUsesTheTableNativeKeywordTileAsset()
    {
        Assert.Contains("lifelink = {name=\"Lifelink\"", Script);
        Assert.Contains("https://steamusercontent-a.akamaihd.net/ugc/1647720820459778541", Script);
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
    public void LandsNeverUseLegacyZeroNetStatsAndAttackPresentationCanRepairLateMapping()
    {
        var statsStart = Script.IndexOf("if event.kind == \"stats_changed\" then", StringComparison.Ordinal);
        var statsEnd = Script.IndexOf("if event.kind == \"controller_changed\" then", statsStart, StringComparison.Ordinal);
        var statsHandler = Script[statsStart..statsEnd];
        Assert.Contains("local power = event.currentPower", statsHandler);
        Assert.Contains("local toughness = event.currentToughness", statsHandler);
        Assert.DoesNotContain("event.netPower", statsHandler);
        Assert.DoesNotContain("event.netToughness", statsHandler);

        var attackStart = Script.IndexOf("if event.kind == \"attack_declared\" then", StringComparison.Ordinal);
        var attackEnd = Script.IndexOf("if event.kind == \"block_declared\" then", attackStart, StringComparison.Ordinal);
        var attackHandler = Script[attackStart..attackEnd];
        Assert.Contains("allowUntrackedByName = true", attackHandler);
        Assert.Contains("attack presentation deferred", attackHandler);
        Assert.Contains("BridgeScheduleSnapshotReconcile", attackHandler);
        Assert.Contains("repaired untracked attack presentation mapping", Script);
    }

    [Fact]
    public void UnscopedCombatPresentationWaitsForStructuredSnapshotRatherThanStoppingTheMatch()
    {
        var applyStart = Script.IndexOf("function BridgeApplyAuthoritativeEvent(event)", StringComparison.Ordinal);
        var turnStart = Script.IndexOf("if event.kind == \"turn_changed\" then", applyStart, StringComparison.Ordinal);
        var applyPrelude = Script[applyStart..turnStart];

        Assert.Contains("ignored unscoped combat presentation event=", applyPrelude);
        Assert.Contains("BridgeScheduleSnapshotReconcile(\"unscoped combat event \"", applyPrelude);
        Assert.Contains("event.kind == \"attack_declared\" or event.kind == \"block_declared\"", applyPrelude);
    }

    [Fact]
    public void RedundantLandEventWithAlreadyMovedMapping_DefersInsteadOfStopping()
    {
        var start = Script.IndexOf("if event.kind == \"land_played\" then", StringComparison.Ordinal);
        var end = Script.IndexOf("if event.kind == \"spell_resolved\" and event.destinationZone == \"battlefield\" then", start, StringComparison.Ordinal);
        var handler = Script[start..end];

        Assert.Contains("semantic land source already changed", handler);
        Assert.Contains("BridgeScheduleSnapshotReconcile(\"semantic land source already changed \"", handler);
        Assert.Contains("return true, 0.1", handler);
        Assert.DoesNotContain("return false, 0, resolveError", handler);
    }

    [Fact]
    public void LandMapping_RepairsStaleHandZoneFromExactMappedGuid()
    {
        var resolver = Script.IndexOf("function BridgeResolvePhysicalCard", StringComparison.Ordinal);
        var body = Script[resolver..];
        Assert.Contains("expectedZone == \"hand\" and mappedZone ~= \"hand\"", body);
        Assert.Contains("BridgeTryGetSeatHandObjects(event.seatId)", body);
        Assert.Contains("BridgeSafeObjectGuid(handObject) == existingGuid", body);
        Assert.Contains("BridgeRecordLooseCardIdentity(event.cardInstanceId, existingGuid, event.seatId, \"hand\")", body);
    }

    [Fact]
    public void NonAnimatedLandPresentation_UsesAuthoritativeSourceAndDefersMappingGaps()
    {
        var start = Script.IndexOf("if not seat.animateAuthoritativeEvents then", StringComparison.Ordinal);
        var end = Script.IndexOf("if event.kind == \"card_moved\"", start, StringComparison.Ordinal);
        var handler = Script[start..end];
        Assert.Contains("local sourceZone = event.sourceZone or \"hand\"", handler);
        Assert.Contains("BridgeResolvePhysicalCard(event, sourceZone)", handler);
        Assert.Contains("BridgeScheduleSnapshotReconcile(\"unmapped non-animated land \"", handler);
        Assert.Contains("return true, 0.1", handler);
    }

    [Fact]
    public void TokenMaterialization_UsesExactVisualImportBeforeDegradedProxy()
    {
        Assert.Contains("A generic Encoder button is not a token producer", Script);
        Assert.Contains("string.find(text, \"spawn token\", 1, true)", Script);
        Assert.DoesNotContain("string.find(label, \"encode\", 1, true) ~= nil then score", Script);
        Assert.Contains("function BridgeSpawnGenericTokenProxy(expectedName, seatId, callback)", Script);
        Assert.Contains("DEGRADED token presentation: exact art-bearing import unavailable", Script);
        Assert.Contains("function BridgeImportExactTokenVisual(expectedName, seatId, callback)", Script);
        Assert.Contains("function BridgeIsArtBearingCard(object)", Script);
        Assert.Contains("CustomDeck", Script);
        Assert.Contains("FaceURL", Script);
        Assert.Contains("tokenPhysicalGuids", Script);
        Assert.Contains("BridgeMarkTokenPhysicalObject(taken)", Script);
        Assert.Contains("object.destruct()", Script);

        var fetchStart = Script.IndexOf("function BridgeTakeCardFromTokenFetcher", StringComparison.Ordinal);
        var fetchEnd = Script.IndexOf("function BridgeSetPhysicalFaceDown", fetchStart, StringComparison.Ordinal);
        var fetcher = Script[fetchStart..fetchEnd];
        Assert.True(fetcher.IndexOf("BridgeImportExactTokenVisual", StringComparison.Ordinal)
            < fetcher.IndexOf("BridgeSpawnGenericTokenProxy", StringComparison.Ordinal));
        Assert.Contains("exact token visual import requested", fetcher);
        Assert.Contains("Source-card buttons such as EmblemsAndTokens", fetcher);
        Assert.DoesNotContain("BridgeTrySpawnTokenViaEncodeButton(expectedName, seatId", fetcher);
        Assert.Contains("DEGRADED token presentation: exact art importer failed", fetcher);
        Assert.Contains("local finished = false", fetcher);
        Assert.Contains("ignored duplicate token visual callback", fetcher);
    }

    [Fact]
    public void TokenMaterialization_InvokesBuiltInButtonWithTtsPositionalCallbackSignature()
    {
        var start = Script.IndexOf("function BridgeInvokeButtonClick", StringComparison.Ordinal);
        var end = Script.IndexOf("function BridgeTrySpawnTokenViaEncodeButton", start, StringComparison.Ordinal);
        var invoker = Script[start..end];
        Assert.Contains("globalHandler(source, seatColor, false)", invoker);
        Assert.Contains("invoked built-in card button positionally", invoker);
        Assert.True(invoker.IndexOf("globalHandler(source, seatColor, false)", StringComparison.Ordinal)
            < invoker.IndexOf("owner.call(clickFunction, payload)", StringComparison.Ordinal));
    }

    [Fact]
    public void DisabledLegacyTokenButtonPath_DoesNotLeaveStatementsAfterLuaReturn()
    {
        var start = Script.IndexOf("function BridgeTrySpawnTokenViaEncodeButton", StringComparison.Ordinal);
        var end = Script.IndexOf("function BridgeSpawnGenericTokenProxy", start, StringComparison.Ordinal);
        var disabledPath = Script[start..end];

        Assert.Contains("legacy source-card token button path disabled", disabledPath);
        Assert.DoesNotContain("\n    return\n", disabledPath);
    }

    [Fact]
    public void TokenMaterialization_ArtBearingContractRejectsBareCardAndUsesSingleShotCallbacks()
    {
        var importerStart = Script.IndexOf("function BridgeImportExactTokenVisual", StringComparison.Ordinal);
        var importerEnd = Script.IndexOf("function BridgeFindDeckWithContainedCardName", importerStart, StringComparison.Ordinal);
        var importer = Script[importerStart..importerEnd];
        Assert.Contains("local completed = false", importer);
        Assert.Contains("if completed then return end", importer);
        Assert.Contains("not BridgeIsArtBearingCard(object)", importer);
        Assert.Contains("spawnObjectJSON({", importer);
        Assert.Contains("json = JSON.encode(cardJson)", importer);
        Assert.Contains("function BridgeParseExactTokenImportJson(text, expectedName)", Script);
        Assert.Contains("exact token importer returned a non-art-bearing card JSON", Script);
        Assert.Contains("BRIDGE_TOKEN_IMPORT_PRIMARY_URL", Script);
        Assert.Contains("BRIDGE_TOKEN_IMPORT_FALLBACK_URL", Script);
    }

    [Fact]
    public void TokenMaterialization_IsExactlyOncePerForgeInstanceAcrossAsyncSnapshotRaces()
    {
        Assert.Contains("tokenMaterializationByInstanceId", Script);
        Assert.Contains("function BridgeBeginTokenMaterialization(cardInstanceId)", Script);
        Assert.Contains("current.state == \"SPAWNING\" or current.state == \"BOUND\"", Script);
        Assert.Contains("function BridgeBindTokenMaterialization(event, object, row, sessionId, epoch)", Script);
        Assert.Contains("BridgeRecordLooseCardIdentity(event.cardInstanceId, guid, event.seatId, \"battlefield\")", Script);
        Assert.Contains("token materialization suppressed instance=", Script);
        Assert.Contains("stale token import callback", Script);
        Assert.Contains("BridgeState.tokenMaterializationByInstanceId[event.cardInstanceId].state = \"BOUND\"", Script);
        Assert.Contains("local finished = false", Script);
        Assert.Contains("local function finish(object, err)", Script);
        Assert.Contains("ignored duplicate token visual callback", Script);
        Assert.DoesNotContain("tokenMaterializationByName", Script);
    }

    [Fact]
    public void TokenMaterialization_UsesRequestedNameForRikrassenVisualLookupWithoutSourcePermanentInference()
    {
        var importerStart = Script.IndexOf("function BridgeImportExactTokenVisual", StringComparison.Ordinal);
        var importerEnd = Script.IndexOf("function BridgeFindDeckWithContainedCardName", importerStart, StringComparison.Ordinal);
        var importer = Script[importerStart..importerEnd];
        Assert.Contains("data = \"1 \" .. tostring(expectedName)", Script);
        Assert.Contains("importer.rikrassen.xyz/build", Script);
        Assert.Contains("BridgeNormalizeCardName(cardJson.Nickname or \"\")", Script);
        Assert.Contains("#candidates ~= 1", Script);
        Assert.DoesNotContain("sourceCard", importer);
    }

    [Fact]
    public void TokenReuse_RequiresExactNormalizedTokenIdentity()
    {
        var keyStart = Script.IndexOf("function BridgeTokenNameKey", StringComparison.Ordinal);
        var keyEnd = Script.IndexOf("function BridgeMarkTokenPhysicalObject", keyStart, StringComparison.Ordinal);
        var key = Script[keyStart..keyEnd];
        Assert.Contains("function BridgeTokenNameKey(name)", key);
        Assert.Contains("string.gsub(normalized, \"%f[%a]token%f[%A]\", \" \")", key);
        Assert.Contains("return left == right", key);
        Assert.DoesNotContain("string.find(left, right, 1, true)", key);

        var lookupStart = Script.IndexOf("function BridgeFindDeckWithContainedCardName", StringComparison.Ordinal);
        var lookupEnd = Script.IndexOf("function BridgeTakeCardFromTokenFetcher", lookupStart, StringComparison.Ordinal);
        var lookup = Script[lookupStart..lookupEnd];
        Assert.Contains("local expectedTokenKey = BridgeTokenNameKey(expectedName)", lookup);
        Assert.Contains("BridgeTokenNameKey(containedName) == expectedTokenKey", lookup);
        Assert.DoesNotContain("BridgeCardNameMatches(containedName, expectedName)", lookup);
    }

    [Fact]
    public void Presentation_PreservesCanonicalCardScaleAndSeparatesLandPlacementModes()
    {
        Assert.Contains("canonicalCardScaleByGuid", Script);
        Assert.Contains("function BridgeCaptureCanonicalCardScale(object)", Script);
        Assert.Contains("function BridgeRestoreCanonicalCardScale(object)", Script);
        Assert.Contains("BridgeRestoreCanonicalCardScale(object)", Script);
        Assert.Contains("BRIDGE_LAND_PLACEMENT_MODE = BRIDGE_LAND_PLACEMENT_MODE or \"FREEFORM\"", Script);
        Assert.Contains("function BridgeSetLandPlacementMode(mode)", Script);
        Assert.Contains("function BridgeRelayoutStrictLandRow(seatId)", Script);
        Assert.Contains("if row == \"land\" and BridgeLandPlacementMode() == \"STRICT\"", Script);
        Assert.Contains("landInsertionOrderByInstanceId", Script);
    }

    [Fact]
    public void EveryGameCardEncoderMutationUsesOneCanonicalScaleSafeBoundary()
    {
        Assert.Contains("function BridgeEncoderMutation(object, operation, label)", Script);
        Assert.Contains("local canonical = BridgeCaptureCanonicalCardScale(object)", Script);
        Assert.Contains("BridgeRestoreCardScaleIfChanged(object, canonical)", Script);
        Assert.Contains("BridgeWaitFrames(function()", Script);
        Assert.Contains("end, 2)", Script);
        Assert.Contains("end, \"APIencodeObject\")", Script);
        Assert.Contains("end, \"APIobjEnableProp\")", Script);
        Assert.Contains("end, \"APIobjSetPropData+APIrebuildButtons\")", Script);
        Assert.Contains("end, \"keywords+APIrebuildButtons\")", Script);
        Assert.Contains("end, \"counter-fallback+APIrebuildButtons\")", Script);
        Assert.Contains("if object == nil or object.tag ~= \"Card\" then", Script);
    }

    [Fact]
    public void CrewDecisionUsesForgePowerProgressInTheHumanChoiceHud()
    {
        Assert.Contains("decision.kind == \"cost_selection\" and decision.costKind == \"crew\"", Script);
        Assert.Contains("CREW — SELECT CREATURES", Script);
        Assert.Contains("decision.selectedTotalPower or 0", Script);
        Assert.Contains("decision.requiredTotalPower", Script);
    }

    [Fact]
    public void CurrentDecisionRebuildsPhysicalActionsWithoutPriorityGatingTurnBasedCombat()
    {
        var staleStart = Script.IndexOf("function BridgeShouldIgnoreStaleDecision", StringComparison.Ordinal);
        var staleEnd = Script.IndexOf("function BridgeShouldDeferDecision", staleStart, StringComparison.Ordinal);
        var stalePolicy = Script[staleStart..staleEnd];
        Assert.Contains("if decision.kind ~= \"main_priority\" then", stalePolicy);
        Assert.Contains("return false, eventCursor, applied", stalePolicy);
        Assert.Contains("BLOCKING: ", Script);
        Assert.Contains("decision.contextCardName", Script);

        var renderStart = Script.IndexOf("function BridgeRenderDecision(decision, force)", StringComparison.Ordinal);
        var renderEnd = Script.IndexOf("function BridgeShowError", renderStart, StringComparison.Ordinal);
        var renderer = Script[renderStart..renderEnd];
        Assert.Contains("BridgeClearHighlights()", renderer);
        Assert.Contains("presentationInstanceId and BridgeState.physicalByInstanceId[presentationInstanceId]", renderer);
        Assert.Contains("BridgeState.actionByGuid[guid] = action", renderer);
        Assert.Contains("action.sourceZone", renderer);
        Assert.DoesNotContain("currentTypes contains Creature", renderer);
    }

    [Fact]
    public void DiscardPresentation_UsesStructuredProvenanceAndRetiresWithDecisionHighlights()
    {
        Assert.Contains("function BridgeApplyDiscardPresentation(decision)", Script);
        Assert.Contains("decision.decisionCauseKind", Script);
        Assert.Contains("decision.sourceCardInstanceId", Script);
        Assert.Contains("DISCARD TO MAXIMUM HAND SIZE", Script);
        Assert.Contains("Caused by:", Script);
        Assert.Contains("BridgeState.discardPresentation = nil", Script);
    }

    [Fact]
    public void DestructiveReset_DrainsGraveyardDeckPilesCardByCardBeforeLooseCleanup()
    {
        Assert.Contains("function BridgeReturnGraveyardPilesToLibraries(callback)", Script);
        Assert.Contains("function BridgeDeckContainsTrackedCardForSeat(deck, seatId)", Script);
        Assert.Contains("BridgeObjectNearSeatZone(object, seatId, \"graveyard\")", Script);
        Assert.Contains("Re-read the live contents before every extraction", Script);
        Assert.Contains("When a TTS Deck reaches one card it is replaced by a loose", Script);
        Assert.Contains("BridgeWaitFrames(function() done(true, nil) end, 2)", Script);
        Assert.Contains("local entry = entries[1]", Script);
        Assert.Contains("pile.takeObject(options)", Script);
        Assert.Contains("BridgeInsertPhysicalCardIntoLibrary(job.seatId, card, \"NORMAL\"", Script);
        Assert.Contains("BridgeReturnGraveyardPilesToLibraries(continueWithLooseCards)", Script);
        Assert.Contains("whole Deck-on-Deck merges are deliberately avoided", Script);
    }

    [Fact]
    public void ResolvedSpellObject_DoesNotReferenceChoiceInteractionLocals()
    {
        var start = Script.IndexOf("function BridgeResolveResolvedSpellObject(event)", StringComparison.Ordinal);
        var end = Script.IndexOf("function BridgeSetPreparedDesignationPresentation", start, StringComparison.Ordinal);
        Assert.True(start >= 0 && end > start);
        var resolver = Script[start..end];
        Assert.DoesNotContain("intent.action", resolver);
        Assert.DoesNotContain("BridgeToggleSingleSelection", resolver);
    }

    [Fact]
    public void DefaultForgeLaunchUsesNumericCombatChoicesAndNeverSynthesizesCardIdCombatInputs()
    {
        var launcher = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "tools", "Start-ForgeBot.ps1"));
        var settings = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "MtgTtsBridge", "appsettings.json"));
        var adapter = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "MtgTtsBridge", "Forge", "ForgeTuiAdapter.cs"));

        Assert.Contains("--numeric-choices", launcher);
        Assert.Contains("{humanDeck}", launcher);
        Assert.DoesNotContain("SynthesizeCombatActions", adapter);
        Assert.DoesNotContain("SynthesizeBlockerAssignments", adapter);
    }

    [Fact]
    public void StructuredCharacteristicEvents_DoNotRequestASecondFullSnapshot()
    {
        var start = Script.IndexOf("function BridgeShouldReconcileAfterEvent", StringComparison.Ordinal);
        var finish = Script.IndexOf("function BridgeResumeChoiceProtocol", start, StringComparison.Ordinal);
        var policy = Script[start..finish];
        Assert.DoesNotContain("stats_changed", policy);
        Assert.DoesNotContain("characteristic_changed", policy);
        Assert.DoesNotContain("keyword_added", policy);
        Assert.DoesNotContain("keyword_removed", policy);
    }

    [Fact]
    public void PresentationCaches_MakeAnIdenticalSnapshotAPhysicalNoOp()
    {
        Assert.Contains("presentedKeywordSignatureByGuid", Script);
        Assert.Contains("presentedCounterSignatureByGuid", Script);
        Assert.Contains("presentedOwnerControllerByGuid", Script);
        Assert.Contains("BridgeState.presentedKeywordSignatureByGuid[guid] == signature", Script);
        Assert.Contains("local unifiedAlreadyPresented = guid ~= nil and BridgeState.presentedCounterSignatureByGuid[guid] == signature", Script);
        Assert.Contains("local fallbackAlreadyPresented = guid ~= nil", Script);
        Assert.Contains("BridgeState.presentedCounterFallbackSignatureByGuid[guid] == fallbackSignature", Script);
        Assert.Contains("Do not cache failure", Script);
        Assert.Contains("presentationMetrics = {", Script);
        Assert.Contains("decisionRenderSkippedIdentical", Script);
        Assert.Contains("BridgePresentationMetric(\"encoderRebuildCount\")", Script);
    }

    [Fact]
    public void ForgeLauncher_LoadsTtsLibraryDecksInsteadOfUsingTheMonoredFixture()
    {
        var launcher = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "tools", "Start-ForgeBot.ps1"));
        var settings = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "MtgTtsBridge", "appsettings.json"));
        var adapter = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "MtgTtsBridge", "Forge", "ForgeTuiAdapter.cs"));

        Assert.Contains("{humanDeck}", launcher);
        Assert.Contains("{aiDeck}", launcher);
        Assert.DoesNotContain("test_decks\\monored.dck", launcher);
        Assert.DoesNotContain("test_decks\\monored.dck", settings);
        Assert.Contains("TTS library decks have not been loaded", adapter);
        Assert.Contains("[metadata]", adapter);
        Assert.Contains("[Main]", adapter);
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

    [Fact]
    public void DevHud_ReportBugControlsSendPresentationContextAndKeepCaptureOutOfLua()
    {
        var xml = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.xml"));
        Assert.Contains("BridgeHudReportOpen", xml);
        Assert.Contains("BridgeHudReportSummary", xml);
        Assert.Contains("BridgeHudReportCapture", xml);
        Assert.Contains("BridgeHudReportCancel", xml);
        Assert.Contains("BridgeHudReportCategoryDropdown", xml);
        Assert.Contains("id=\"BridgeHudDevRoot\" active=\"false\" visibility=\"Host|Admin\" minHeight=\"230\" preferredHeight=\"230\"", xml);
        Assert.Contains("id=\"BridgeHudReportCategoryDropdown\" options=\"Gameplay sync|Combat|Card movement|Presentation/UI|Decision/prompt|Mana/payment|Performance / Freeze|Crash/error|Other\"", xml);
        Assert.Contains("minWidth=\"650\" preferredWidth=\"650\"", xml);
        Assert.Contains("BridgeHudRollingCapture", xml);
        Assert.Contains("BridgeHudResyncFromForge", xml);
        var gamePanelStart = xml.IndexOf("id=\"BridgeHudGamePanel\"", StringComparison.Ordinal);
        var choiceTrayStart = xml.IndexOf("id=\"BridgeHudChoiceTray\"", StringComparison.Ordinal);
        Assert.True(gamePanelStart >= 0 && choiceTrayStart > gamePanelStart);
        var gamePanel = xml[gamePanelStart..choiceTrayStart];
        Assert.Contains("id=\"BridgeHudRollingCapture\"", gamePanel);
        Assert.Contains("visibility=\"Host|Admin\"", gamePanel);
        Assert.Contains("function BridgeHudReportCategoryChanged", Script);
        Assert.Contains("function BridgeHudRollingCapture", Script);
        var rollingStart = Script.IndexOf("function BridgeHudRollingCapture", StringComparison.Ordinal);
        var rollingEnd = Script.IndexOf("function BridgeHudResyncFromForge", rollingStart, StringComparison.Ordinal);
        Assert.Contains("diagnosticsVisible = true", Script[rollingStart..rollingEnd]);
        Assert.Contains("function BridgeHudResyncFromForge", Script);
        Assert.Contains("Rolling freeze capture", Script);
        Assert.Contains("function BridgeHudReportCapture", Script);
        Assert.Contains("/api/v1/diagnostics/report", Script);
        Assert.Contains("mappedCardInstanceIds", Script);
        Assert.Contains("lastAppliedEventSequence", Script);
        Assert.DoesNotContain("ZipFile", Script);
        Assert.DoesNotContain("screenshot.png", Script);
    }

    [Fact]
    public void ReportCategory_UsesReliableButtonCallbacksInsteadOfTheTtsDropdown()
    {
        Assert.Contains("function BridgeHudReportCategoryPrevious", Script);
        Assert.Contains("function BridgeHudReportCategory(player, value, id)", Script);
        Assert.Contains("BridgeUiMarkDirty(\"report-category-previous\")", Script);
        Assert.Contains("BridgeUiMarkDirty(\"report-category-next\")", Script);
        Assert.Contains("BridgeUiSet(\"BridgeHudReportCategoryDropdown\", \"active\", \"false\")", Script);
        Assert.Contains("BridgeUiSet(\"BridgeHudReportCategoryPrevious\", \"active\", categoryControlsActive", Script);
        Assert.Contains("BridgeUiSet(\"BridgeHudReportCategory\", \"text\", BRIDGE_REPORT_CATEGORIES[reportCategoryIndex]", Script);
    }

    [Fact]
    public void ResyncControl_RemainsAvailableWhenSessionIsStopped()
    {
        Assert.Contains("BridgeStopOnDesync", Script);
        Assert.Contains("BridgeUiSet(\"BridgeHudResyncFromForge\", \"active\", devEnabled and not ui.resyncInFlight", Script);
        Assert.Contains("if sessionId == nil then", Script);
        Assert.Contains("cannot resync before Forge has started a session", Script);
    }

    [Fact]
    public void AuthoritativeResync_RebuildsFromSnapshotAndResumesAtItsEventCursor()
    {
        var start = Script.IndexOf("function BridgeResyncFromAuthoritativeSnapshot", StringComparison.Ordinal);
        var end = Script.IndexOf("function BridgeAlignLibraryOrderForSnapshot", start, StringComparison.Ordinal);
        var resync = Script[start..end];

        Assert.Contains("BridgeBootstrapCurrentSnapshot(sessionId", resync);
        Assert.Contains("end, true)", resync);
        Assert.Contains("BridgeStartEventPolling(sessionId, false)", resync);
        Assert.Contains("BridgeStartDecisionPolling()", resync);
        Assert.Contains("lastAppliedEventSequence = cursor", Script);
        Assert.Contains("lastReceivedEventSequence = cursor", Script);
        Assert.Contains("authoritative resync snapshot is missing a valid event cursor", Script);
        Assert.Contains("BridgeState.submitting = false", resync);
        Assert.Contains("BridgeResumeChoiceProtocol(\"authoritative_resync\")", resync);
        Assert.Contains("resyncPresentationState", Script);
    }

    [Fact]
    public void DesyncRecovery_SuppressesDuplicateAsyncFailuresDuringResync()
    {
        Assert.Contains("desyncLatched = false", Script);
        Assert.Contains("desyncFailureCount = 0", Script);
        Assert.Contains("suppressed desync during authoritative resync", Script);
        Assert.Contains("duplicate synchronization failure suppressed", Script);
        var resyncStart = Script.IndexOf("function BridgeResyncFromAuthoritativeSnapshot", StringComparison.Ordinal);
        var resyncEnd = Script.IndexOf("function BridgeAlignLibraryOrderForSnapshot", resyncStart, StringComparison.Ordinal);
        Assert.Contains("BridgeState.desyncLatched = false", Script[resyncStart..resyncEnd]);
        Assert.Contains("BridgeState.desyncFailureCount = 0", Script[resyncStart..resyncEnd]);
    }

    [Fact]
    public void CombatCandidates_RequireCurrentBattlefieldMapping()
    {
        var start = Script.IndexOf("local mappedPhysicalZone =", StringComparison.Ordinal);
        var end = Script.IndexOf("BridgeEnsureDecisionOptionControls", start, StringComparison.Ordinal);
        Assert.True(start >= 0 && end > start);
        var body = Script[start..end];
        Assert.Contains("local combatActionKind = action.type or action.actionKind", body);
        Assert.Contains("local combatSelection = combatActionKind == \"choose_attacker\" or combatActionKind == \"choose_blocker\"", body);
        Assert.Contains("if combatSelection and mappedPhysicalZone ~= \"battlefield\" then", body);
        Assert.Contains("not combatSelection or objectZone == \"battlefield\"", body);
    }

    [Fact]
    public void YieldTurn_IsVisibleWithoutHumanDecisionAndRemainsTurnScoped()
    {
        Assert.Contains("local yieldPolicyAvailable = BridgeState.gameEnded == nil", Script);
        Assert.Contains("(hasYield or yieldPolicyAvailable)", Script);
        Assert.Contains("yieldPolicyTurnNumber = tonumber(BridgeState.tableTurnCount or 0)", Script);
        Assert.Contains("yieldPolicyActiveSeatId = BridgeState.currentTurnSeatId", Script);
        Assert.Contains("yield_policy_auto_pass", Script);
        Assert.Contains("cleared HUD yield policy at authoritative turn transition", Script);
    }

    [Fact]
    public void YieldTurn_ArmsDuringOpponentTurnWithoutSubmittingHumanResponse()
    {
        Assert.Contains("local activeSeat = BridgeState.currentTurnSeatId", Script);
        Assert.Contains("if activeSeat ~= nil and activeSeat ~= \"forge-player-1\" then", Script);
        Assert.Contains("yieldPolicyActiveSeatId = activeSeat", Script);
        Assert.Contains("local policyTurnMatches = policyTurn == 0", Script);
    }

    [Fact]
    public void TurnBoundary_RetiresStaleDecisionBeforeRefreshingYieldControls()
    {
        var start = Script.IndexOf("if event.kind == \"turn_changed\" then", StringComparison.Ordinal);
        var end = Script.IndexOf("if event.kind == \"phase_changed\" then", start, StringComparison.Ordinal);
        Assert.True(start >= 0 && end > start);
        var turnBody = Script[start..end];
        Assert.Contains("BridgeState.lastDecision = nil", turnBody);
        Assert.Contains("BridgeState.pendingDecision = nil", turnBody);
        Assert.Contains("BridgeResetSelectionState()", turnBody);
        Assert.Contains("BridgeClearHighlights()", turnBody);
    }

    [Fact]
    public void CheckedInGlobalLua_MatchesDeterministicAuthoringBundle()
    {
        var repositoryRoot = FindRepositoryRoot();
        var sourceDirectory = Path.Combine(repositoryRoot, "tts", "src");
        var expected = new StringBuilder();
        foreach (var path in Directory.GetFiles(sourceDirectory, "*.lua")
                     .OrderBy(Path.GetFileName, StringComparer.Ordinal))
        {
            var name = Path.GetFileName(path);
            expected.Append("-- BEGIN GENERATED SOURCE: ").Append(name).AppendLine();
            expected.Append(File.ReadAllText(path));
            if (expected.Length == 0 || expected[^1] != '\n') expected.AppendLine();
            expected.Append("-- END GENERATED SOURCE: ").Append(name).AppendLine();
        }

        Assert.Equal(expected.ToString(), File.ReadAllText(Path.Combine(repositoryRoot, "tts", "Global.lua")));
    }

    private static string FindRepositoryRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null && !File.Exists(Path.Combine(directory.FullName, "AGENTS.md")))
            directory = directory.Parent;
        return directory?.FullName ?? throw new DirectoryNotFoundException("Repository root not found.");
    }

    [Fact]
    public void DevHud_HasOneRollingCaptureControlSoItCannotShadowChoiceButtons()
    {
        var xml = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.xml"));
        var occurrences = System.Text.RegularExpressions.Regex.Matches(
            xml, @"id=""BridgeHudRollingCapture""", System.Text.RegularExpressions.RegexOptions.CultureInvariant);
        Assert.Single(occurrences);
    }

    [Fact]
    public void DevHud_ReportResultIsVisibleAndUsesStableCallbacks()
    {
        Assert.Contains("CAPTURED • ", Script);
        Assert.Contains("diagnostic report failed", Script);
        Assert.Contains("BridgeState.ui.reportStatus", Script);
        Assert.Contains("BridgeHudReportStatus", File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.xml")));
    }

    [Fact]
    public void FreezeFlightRecorder_IsBoundedCaptureOnlyAndUsesCompactScalarRecords()
    {
        Assert.Contains("BRIDGE_PERFORMANCE_TRACE_CAPACITY = 384", Script);
        Assert.Contains("performanceTrace = {capacity = BRIDGE_PERFORMANCE_TRACE_CAPACITY", Script);
        Assert.Contains("function BridgePerformanceTraceSnapshot()", Script);
        Assert.Contains("BRIDGE_PERFORMANCE_CLOCK_KIND = \"os.clock-cpu\"", Script);
        Assert.Contains("BRIDGE_PERFORMANCE_WALL_CLOCK_KIND = \"Time.time-game\"", Script);
        Assert.Contains("cpuDurationMs = cpuDurationMs", Script);
        Assert.Contains("wallDurationMs = wallDurationMs", Script);
        Assert.Contains("wallClockKind = wallClockKind", Script);
        Assert.Contains("performanceSummary = performance.performanceSummary", Script);
        Assert.Contains("recentTtsTrace = performance.recentTtsTrace", Script);
        Assert.DoesNotContain("BridgeHttp.requestJson", Script[Script.IndexOf("function BridgePerformanceTrace", StringComparison.Ordinal)..Script.IndexOf("function BridgePerformanceDiagnosticPayload", StringComparison.Ordinal)]);
        foreach (var marker in new[]
        {
            "decision_accept_begin", "decision_accept_end", "decision_render_begin", "decision_render_skipped", "decision_render_end",
            "clear_highlights_begin", "clear_highlights_end", "prepared_presentation_begin", "prepared_presentation_end",
            "candidate_collection_begin", "candidate_collection_end", "action_matching_begin", "action_matching_end",
            "ui_flush_begin", "ui_flush_end", "authoritative_event_begin", "authoritative_event_end",
            "physical_move_begin", "physical_move_end", "snapshot_reconcile_begin", "snapshot_reconcile_end"
        }) Assert.Contains(marker, Script);
    }

    [Fact]
    public void FreezeFlightRecorder_UsesTtsWallClockAndFallsBackWithoutIt()
    {
        var start = Script.IndexOf("function BridgePerformanceWallNow", StringComparison.Ordinal);
        var end = Script.IndexOf("function BridgePerformanceTraceSnapshot", start, StringComparison.Ordinal);
        var implementation = Script[start..end];

        Assert.Contains("pcall(function()", implementation);
        Assert.Contains("if Time == nil then return nil end", implementation);
        Assert.Contains("return Time.time", implementation);
        Assert.Contains("if wallDurationMs == nil", implementation);
        Assert.Contains("wallDurationMs = cpuDurationMs", implementation);
        Assert.Contains("BRIDGE_PERFORMANCE_WALL_CLOCK_FALLBACK_KIND = \"os.clock-cpu-fallback\"", Script);
        Assert.DoesNotContain("os.time()", implementation);
    }

    [Fact]
    public void FreezeCapture_ExcludesCardNamesFromPerformancePayloadAndExposesLandCanaryCounts()
    {
        var start = Script.IndexOf("function BridgePerformanceDiagnosticPayload", StringComparison.Ordinal);
        var end = Script.IndexOf("function BridgeWaitTime", start, StringComparison.Ordinal);
        var payload = Script[start..end];
        Assert.Contains("decisionPlayLandCount", payload);
        Assert.Contains("ttsRepresentedPlayLandCount", payload);
        Assert.Contains("eventCursor", payload);
        Assert.DoesNotContain("cardName", payload);
        Assert.Contains("Performance / Freeze", Script);
    }
    [Fact]
    public void LibraryInsertion_RetiresIdentityOnlyAfterVerifiedContainment()
    {
        var start = Script.IndexOf("function BridgeInsertPhysicalCardIntoLibrary", StringComparison.Ordinal);
        var end = Script.IndexOf("function BridgeProcessMulliganBottomQueue", start, StringComparison.Ordinal);
        var insertion = Script[start..end];

        Assert.Contains("object.setLock(false)", insertion);
        Assert.Contains("library.putObject(object)", insertion);
        Assert.Contains("resultingLibrary = library.putObject(object)", insertion);
        Assert.Contains("library.tag == \"Card\"", insertion);
        Assert.Contains("BridgeVerifyLibraryContainment(seatId, guid", insertion);
        Assert.Contains("resultingLibrary)", insertion);
        Assert.Contains("TTS did not verify library containment", Script);
        Assert.DoesNotContain("setPositionSmooth(libraryZone.getPosition()", insertion);
    }

    [Fact]
    public void LibraryCorruptionCanary_DetectsLooseAndContainedGuidCollisionsWithPhysicalDetails()
    {
        Assert.Contains("function BridgeAuditDuplicateLibraryGuids", Script);
        Assert.Contains("DUPLICATE_PHYSICAL_GUID", Script);
        Assert.Contains("looseCardID", Script);
        Assert.Contains("containingDeck", Script);
        Assert.Contains("containedIndex", Script);
        Assert.Contains("BridgeAuditDuplicateLibraryGuids()", Script);
    }

    [Fact]
    public void LibraryInsertion_AllowsOnlyExactStagedGuidsDuringTtsSourceSettle()
    {
        var auditStart = Script.IndexOf("function BridgeLibraryAuditIgnoresGuid", StringComparison.Ordinal);
        var auditEnd = Script.IndexOf("function BridgeLibraryCardIdentity", auditStart, StringComparison.Ordinal);
        var audit = Script[auditStart..auditEnd];
        var stabilityStart = Script.IndexOf("function BridgeVerifyLibraryIdentityStability", StringComparison.Ordinal);
        var stabilityEnd = Script.IndexOf("function BridgeInsertPhysicalCardIntoLibrary", stabilityStart, StringComparison.Ordinal);
        var stability = Script[stabilityStart..stabilityEnd];

        Assert.Contains("function BridgeLibraryAuditIgnoresGuid(ignoredGuids, guid)", audit);
        Assert.Contains("ignoredGuids[tostring(guid)] == true", audit);
        Assert.Contains("not BridgeLibraryAuditIgnoresGuid(ignoredGuids, guid)", audit);
        Assert.Contains("local strictDuplicateCount = BridgeAuditDuplicateLibraryGuids()", stability);
        Assert.Contains("local ignoredGuids = expectedGuids", stability);
        Assert.Contains("BridgeAuditDuplicateLibraryGuids(ignoredGuids)", stability);
        Assert.Contains("unexpected loose/contained duplicate GUID(s)", stability);
        Assert.Contains("BridgeVerifyLibraryIdentityStability(callback, attempt + 1, expectedGuids)", stability);
    }

    [Fact]
    public void AuthoritativeResync_WaitsForEveryExactBootstrapStagingGuidThenRunsStrictAudit()
    {
        var start = Script.IndexOf("function BridgeStageSeatCardsForBootstrap", StringComparison.Ordinal);
        var end = Script.IndexOf("function BridgeObjectNearSeatZone", start, StringComparison.Ordinal);
        var staging = Script[start..end];
        var bootstrapStart = Script.IndexOf("function BridgeBootstrapCurrentSnapshot", StringComparison.Ordinal);
        var bootstrapEnd = Script.IndexOf("function BridgeAnnotateSnapshotBattlefieldKinds", bootstrapStart, StringComparison.Ordinal);
        var bootstrap = Script[bootstrapStart..bootstrapEnd];

        Assert.Contains("local stagedGuids = {}", staging);
        Assert.Contains("local function stageNext(index)", staging);
        Assert.Contains("BridgeStagePhysicalCardForBootstrap(item.object, item.seatId, function(ok, err)", staging);
        Assert.Contains("stagedGuids[tostring(item.guid)] = true", staging);
        Assert.Contains("callback(true, nil, stagedGuids)", staging);
        Assert.Contains("BridgeStageSeatCardsForBootstrap(snapshot, function(stagedOk, stagedError, stagedGuids)", bootstrap);
        Assert.Contains("BridgeVerifyLibraryIdentityStability(function(stable, stabilityError)", bootstrap);
        Assert.Contains("end, 1, stagedGuids)", bootstrap);
        Assert.DoesNotContain("local postStageDuplicateCount = BridgeAuditDuplicateLibraryGuids()", bootstrap);
    }

    [Fact]
    public void GraveyardCleanup_WaitsForTakeObjectSourcePileToSettleBeforeReinsertion()
    {
        var start = Script.IndexOf("function BridgeReturnGraveyardPilesToLibraries", StringComparison.Ordinal);
        var end = Script.IndexOf("function BridgeReturnPreviousGameCardsToLibraries", start, StringComparison.Ordinal);
        var cleanup = Script[start..end];

        Assert.Contains("takeObject invokes its callback before TTS has", cleanup);
        Assert.Contains("BridgeWaitFrames(function()", cleanup);
        Assert.Contains("BridgeInsertPhysicalCardIntoLibrary(job.seatId, card, \"NORMAL\"", cleanup);
    }

    [Fact]
    public void EventQueue_DoesNotRemoveAnEventAfterSessionReplacementOrQueueMutation()
    {
        var start = Script.IndexOf("function BridgeProcessEventQueue", StringComparison.Ordinal);
        var end = Script.IndexOf("-- Decisions are fetched from Forge independently", start, StringComparison.Ordinal);
        var processor = Script[start..end];

        Assert.Contains("not BridgeState.eventPolling", processor);
        Assert.Contains("local processingGeneration = BridgeState.eventPollGeneration", processor);
        Assert.Contains("processingGeneration ~= BridgeState.eventPollGeneration", processor);
        Assert.Contains("BridgeState.eventQueue[1] ~= event", processor);
        Assert.Contains("event queue changed while applying event", processor);
    }

    [Fact]
    public void NormalDeckCards_CannotFallThroughToTokenMaterialization()
    {
        var patch = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "tools", "forge", "bridge-headless.patch"));
        Assert.Contains("property(json, \"isToken\", card.isToken() || card.isTokenCard())", patch);
        Assert.Contains("if card.isToken ~= true then", Script);
        Assert.Contains("ordinary deck card was not found in its authoritative physical zone", Script);
        Assert.Contains("CARD_ART_INTEGRITY_FAILURE", Script);
    }

    [Fact]
    public void LibraryInsertion_UsesSamePrimitiveForMulliganGraveyardAndNewMatchPaths()
    {
        Assert.Contains("BridgeInsertPhysicalCardIntoLibrary(seatId, item.object, \"BOTTOM\"", Script);
        Assert.Contains("BridgeInsertPhysicalCardIntoLibrary(job.seatId, card, \"NORMAL\"", Script);
        Assert.Contains("BridgeInsertPhysicalCardIntoLibrary(candidate.seatId, candidate.object, \"NORMAL\"", Script);
    }

    [Fact]
    public void DecisionPresentation_UsesCompleteFingerprintAndPhysicalGenerationGuard()
    {
        var keyStart = Script.IndexOf("function BridgeDecisionPresentationKey", StringComparison.Ordinal);
        var keyEnd = Script.IndexOf("function BridgeRecordDecisionPresentationRendered", keyStart, StringComparison.Ordinal);
        var renderStart = Script.IndexOf("function BridgeRenderDecision", keyEnd, StringComparison.Ordinal);
        var clear = Script.IndexOf("BridgeClearHighlights()", renderStart, StringComparison.Ordinal);
        var guard = Script.IndexOf("key == BridgeState.renderedDecisionPresentationKey", renderStart, StringComparison.Ordinal);

        Assert.True(keyStart >= 0 && keyEnd > keyStart && renderStart > keyEnd);
        Assert.True(guard >= 0 && clear > guard);
        Assert.Contains("selectedCount", Script[keyStart..keyEnd]);
        Assert.Contains("selectedTotalPower", Script[keyStart..keyEnd]);
        Assert.Contains("action.isSelected", Script[keyStart..keyEnd]);
        Assert.Contains("currentPhysicalPresentationGeneration", Script);
        Assert.Contains("decisionRenderSkippedIdentical", Script);
    }

    [Fact]
    public void DecisionPresentation_SameIdStagedSelectionsRemainDistinct()
    {
        var keyStart = Script.IndexOf("function BridgeDecisionPresentationKey", StringComparison.Ordinal);
        var keyEnd = Script.IndexOf("function BridgeRecordDecisionPresentationRendered", keyStart, StringComparison.Ordinal);
        var key = Script[keyStart..keyEnd];

        Assert.Contains("decisionId", key);
        Assert.Contains("selectedCount", key);
        Assert.Contains("selectedTotalPower", key);
        Assert.Contains("action.isSelected", key);
        Assert.Contains("action.actionId", key);
        Assert.Contains("action.targetSeatId", key);
    }

    [Fact]
    public void UiAttributeCache_CountsAttemptsWritesAndSkippedNoOps()
    {
        var start = Script.IndexOf("function BridgeUiSet", StringComparison.Ordinal);
        var end = Script.IndexOf("function BridgeUiMarkDirty", start, StringComparison.Ordinal);
        var setter = Script[start..end];

        Assert.Contains("uiAttributeAttemptCount", setter);
        Assert.Contains("uiAttributeWriteCount", setter);
        Assert.Contains("uiAttributeSkippedCount", setter);
        Assert.Contains("attributeCache[attribute] == nextValue", setter);
        Assert.Contains("UI.setAttribute(id, attribute, nextValue)", setter);
        Assert.Contains("uiAttributeUpdateCount = ui.uiAttributeWriteCount", setter);
        Assert.True(setter.IndexOf("attributeCache[attribute] == nextValue", StringComparison.Ordinal)
            < setter.IndexOf("UI.setAttribute(id, attribute, nextValue)", StringComparison.Ordinal));
    }

    [Fact]
    public void PresentationCaches_AreClearedForMountAndSessionReplacement()
    {
        Assert.Contains("BridgeState.ui.uiAttributeCache = {}", Script);
        Assert.Contains("BridgeState.renderedDecisionPresentationKey = nil", Script);
        Assert.Contains("BridgeState.renderedDecisionPhysicalGeneration = nil", Script);
        Assert.Contains("BridgeAdvancePhysicalPresentationGeneration(\"session-replaced\")", Script);
    }

    [Fact]
    public void SequentialCombatRedraws_ReleaseSameDecisionTransaction()
    {
        Assert.Contains("body.currentDecision.decisionId == decisionId", Script);
        Assert.Contains("body.currentDecision.kind == \"attacker_selection\"", Script);
        Assert.Contains("body.currentDecision.kind == \"blocker_selection\"", Script);
        Assert.Contains("body.currentDecision.kind == \"blocker_assignment\"", Script);
        Assert.Contains("BridgeState.choiceTransactions[decisionId] = nil", Script);
    }

    [Fact]
    public void BattlefieldSnapshot_CorrectsUnknownOrChangedPermanentRow()
    {
        Assert.Contains("snapshotRow ~= nil and priorRow ~= snapshotRow", Script);
        Assert.Contains("local expectedRow = BridgeBattlefieldRowForEvent(event, \"creature\")", Script);
        var normalizedScript = Script.Replace("\r\n", "\n", StringComparison.Ordinal);
        Assert.Contains("BridgeMoveToBattlefield(\n                        event, object, expectedRow, false)", normalizedScript);
        Assert.Contains("if countAsNewPlacement ~= false then", Script);
    }

    [Fact]
    public void BattlefieldMoves_DeriveFallbackRowFromForgeCurrentTypes()
    {
        var moveStart = Script.IndexOf("function BridgeApplyStructuredCardMove", StringComparison.Ordinal);
        var moveEnd = Script.IndexOf("function BridgeMoveToGraveyard", moveStart, StringComparison.Ordinal);
        var move = Script[moveStart..moveEnd];

        Assert.Contains("local row = BridgeBattlefieldRowForEvent(event, \"creature\")", move);
        Assert.DoesNotContain("local row = event.battlefieldKind\n            or BridgeState.battlefieldKindByInstanceId[event.cardInstanceId]", move);
        Assert.Contains("for _, cardType in ipairs(event.currentTypes or {}) do", Script);
        Assert.Contains("local normalizedType = string.lower(tostring(cardType))", Script);
        Assert.Contains("if normalizedType == \"land\" then return \"land\" end", Script);
    }

    [Fact]
    public void ResolvedPermanent_RepairsExactCardStrandedAtPhysicalStackAnchor()
    {
        Assert.Contains("function BridgePhysicalObjectAtStackAnchor(object)", Script);
        Assert.Contains("or strandedAtStack", Script);
        Assert.Contains("STRUCTURED_MOVE stack->battlefield", Script);
        Assert.Contains("SPELL_RESOLVED", Script);
        Assert.Contains("PHYSICAL_MOVE_TO_BATTLEFIELD", Script);
        Assert.Contains("deferred stack-anchor correction", Script);
        Assert.Contains("exact battlefield card remained at the physical stack anchor", Script);
    }

    [Fact]
    public void ResolvedPermanent_RetiresPendingCastOnlyAfterExactBattlefieldMove()
    {
        var move = Script.IndexOf("function BridgeMoveToBattlefield", StringComparison.Ordinal);
        var retire = Script.IndexOf("function BridgeRetirePendingCastForInstance", StringComparison.Ordinal);
        Assert.True(move >= 0);
        Assert.True(retire >= 0);
        Assert.Contains("BridgeRetirePendingCastForInstance(", Script);

        var structured = Script.IndexOf("if event.kind == \"card_moved\"", StringComparison.Ordinal);
        var structuredBattlefield = Script.IndexOf("sourcePhysicalZone == \"stack\"", structured, StringComparison.Ordinal);
        Assert.True(structuredBattlefield > structured);
        Assert.Contains("structured stack-to-battlefield", Script);
        Assert.Contains("semantic stack-to-battlefield", Script);
    }

    [Fact]
    public void ResolvedInstantOrSorcery_DoesNotUsePermanentBattlefieldRepair()
    {
        var graveyard = Script.IndexOf(
            "if event.kind == \"spell_resolved\" and event.destinationZone == \"graveyard\" then",
            StringComparison.Ordinal);
        var graveyardEnd = Script.IndexOf(
            "if event.kind == \"tap_changed\" then", graveyard, StringComparison.Ordinal);
        Assert.True(graveyard >= 0);
        Assert.True(graveyardEnd > graveyard);
        var graveyardHandler = Script[graveyard..graveyardEnd];
        Assert.DoesNotContain("BridgeMoveToBattlefield", graveyardHandler);
        Assert.Contains("BridgeMoveToGraveyard", graveyardHandler);
    }

    [Fact]
    public void GraveyardMove_RetiresOnlyTheExactPendingCast()
    {
        var start = Script.IndexOf("function BridgeMoveToGraveyard", StringComparison.Ordinal);
        var end = Script.IndexOf("function BridgeFindSeatLibraryDeckWithCard", start, StringComparison.Ordinal);
        var move = Script[start..end];

        Assert.Contains("BridgeRetirePendingCastForInstance(", move);
        Assert.Contains("event.cardInstanceId, guid, \"graveyard-move\"", move);
        Assert.DoesNotContain("BridgeState.pendingCastBySeatId[event.seatId] = nil", move);
    }

    [Fact]
    public void PublicZoneReturn_UnlocksExactGraveyardCardBeforeReuse()
    {
        var prepareStart = Script.IndexOf("function BridgePreparePhysicalCardForPublicZoneMove", StringComparison.Ordinal);
        var prepareEnd = Script.IndexOf("function BridgeApplyStructuredCardMove", prepareStart, StringComparison.Ordinal);
        Assert.True(prepareStart >= 0);
        Assert.True(prepareEnd > prepareStart);
        var prepare = Script[prepareStart..prepareEnd];
        Assert.Contains("object.setLock(false)", prepare);
        Assert.Contains("destinationZone == \"graveyard\" or destinationZone == \"library\"", prepare);

        var moveStart = Script.IndexOf("function BridgeMoveToBattlefield", StringComparison.Ordinal);
        var moveEnd = Script.IndexOf("function BridgeBattlefieldPosition", moveStart, StringComparison.Ordinal);
        Assert.True(moveStart >= 0);
        Assert.True(moveEnd > moveStart);
        Assert.Contains("BridgePreparePhysicalCardForPublicZoneMove(object, \"battlefield\")", Script[moveStart..moveEnd]);
    }

    [Fact]
    public void DrawBurst_UsesSerializedExtractionWithoutBlockingPhaseCursor()
    {
        Assert.Contains("BRIDGE_DRAW_EVENT_PRESENTATION_DELAY = 0.25", Script);
        Assert.Contains("return applied, BRIDGE_DRAW_EVENT_PRESENTATION_DELAY, drawError", Script);
        Assert.Contains("BridgeRenderDecision(BridgeState.lastDecision)", Script);
    }

    [Fact]
    public void DrawDecisionWaitsForPhysicalExtractionBeforePresentingNewHandActions()
    {
        var deferStart = Script.IndexOf("function BridgeShouldDeferDecision", StringComparison.Ordinal);
        var deferEnd = Script.IndexOf("function BridgeTryPresentPendingDecision", deferStart, StringComparison.Ordinal);
        Assert.True(deferStart >= 0);
        Assert.True(deferEnd > deferStart);
        var deferBody = Script[deferStart..deferEnd];
        Assert.Contains("libraryExtractionActiveBySeatId", deferBody);
        Assert.Contains("libraryExtractionQueueBySeatId", deferBody);
        Assert.Contains("BridgeTryPresentPendingDecision(\"library-extraction-complete\")", Script);
        Assert.Contains("BridgeRenderDecision(BridgeState.lastDecision)", Script);
    }

    [Fact]
    public void ResourceClone_RetriesAuthoritativeValueAfterTtsRegistration()
    {
        var start = Script.IndexOf("function BridgeCreateResourceCounter", StringComparison.Ordinal);
        var end = Script.IndexOf("function BridgeRefreshResourceRow", start, StringComparison.Ordinal);
        var body = Script[start..end];

        Assert.Equal(2, body.Split("BridgeRefreshResourceRow(seatId)", StringSplitOptions.None).Length - 1);
        Assert.Contains("BridgeSetNativeTrackerValue(counter, BridgeResourceValue(seatId, kind))", body);
        Assert.Contains("BridgeSetNativeTrackerValue(taken, BridgeResourceValue(seatId, kind))", body);
    }
}
