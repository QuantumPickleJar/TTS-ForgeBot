BRIDGE_BASE_URL = "http://127.0.0.1:43110"
BRIDGE_STACK_POSITION = {x = -5.5, y = 1.6, z = 0}
BRIDGE_MANA_COUNTER_SOURCES = {
    W = "cd8bb6", U = "4783af", B = "1c4a59",
    R = "220d2f", G = "cdbccc", C = "aeeb11"
}
BRIDGE_PLAYER_TRACKER_SOURCES = {
    poison = "81ae86", experience = "1ea882", energy = "328fa7", speed = "2c18ff"
}
BRIDGE_MANA_COLORS = {"W", "U", "B", "R", "G", "C"}
-- One presentation row is shared by mana and player resources.  The values
-- come from Forge snapshots/events; this table is only presentation metadata.
BRIDGE_RESOURCE_ORDER = {"W", "U", "B", "R", "G", "C", "energy", "experience", "poison", "speed"}
BRIDGE_RESOURCE_ROW_SPACING = 1.05
BRIDGE_EVENT_POLL_INTERVAL_IDLE = 1.0
-- Slightly slower active polling reduces frequent full decision/highlight churn
-- in TTS without materially affecting interactive responsiveness.
BRIDGE_EVENT_POLL_INTERVAL_ACTIVE = 0.20
BRIDGE_DECISION_DEFER_STALL_SECONDS = 0.6
BRIDGE_OPENING_HAND_READINESS_TIMEOUT_SECONDS = 8.0
BRIDGE_OPENING_HAND_READINESS_RETRY_FRAMES = 2
-- A hand can be authoritative in Forge before TTS finishes returning/redealing
-- physical cards (especially after a mulligan).  Readiness failures are
-- recoverable embodiment races, so allow a bounded refresh before latching a
-- synchronization failure.
BRIDGE_HAND_READINESS_RECOVERY_ATTEMPTS = 2
BRIDGE_PERFORMANCE_TRACE_CAPACITY = 384
BRIDGE_EVENT_QUEUE_MAX = 128
BRIDGE_PERFORMANCE_SLOW_OPERATION_SECONDS = 0.25
-- Diagnostic capture is deliberately best-effort. A lost WebRequest callback
-- must not leave report controls latched forever after a freeze capture.
BRIDGE_REPORT_CAPTURE_TIMEOUT_SECONDS = 30.0
BRIDGE_DIAGNOSTIC_CAPTURE_LIFECYCLE_CAPACITY = 96
BRIDGE_DIAGNOSTIC_CAPTURE_FOLLOWUP_SECONDS = 5.0
BRIDGE_DIAGNOSTIC_CAPTURE_FOLLOWUP_INTERVAL_SECONDS = 0.5
-- Library extraction is serialized separately. Keep the event cursor moving
-- promptly after a draw so a burst (for example, a draw per creature) cannot
-- hold later authoritative phase/priority events behind animation delays.
BRIDGE_DRAW_EVENT_PRESENTATION_DELAY = 0.25
BRIDGE_STALE_DECISION_CONVERGENCE_ATTEMPTS = 8
BRIDGE_STALE_DECISION_CONVERGENCE_SECONDS = 12.0
-- A queue head that cannot start for this long is a scheduler fault worth
-- recording.  It is intentionally diagnostic-only; authoritative events are
-- never dropped or cursor-advanced by the watchdog.
BRIDGE_EVENT_DRAIN_STALL_SECONDS = 2.0
-- A committed event owns one serialized continuation until its timer callback
-- is observed.  The frame deadline is a bounded fallback for a TTS Wait.time
-- callback that disappears; it is not a second per-frame event pump.
BRIDGE_EVENT_DRAIN_CONTINUATION_STALL_FRAMES = 120
BRIDGE_RESYNC_PHYSICAL_QUEUE_GRACE_SECONDS = 1.0
BRIDGE_RESYNC_STALL_SECONDS = 30.0
-- The physical rebuild can finish before its final bookkeeping callback. Keep
-- a separate, shorter owner so onUpdate can resume that exact finalization
-- without rolling a proven table back to the pre-resync cursor.
BRIDGE_RESYNC_COMPLETION_STALL_FRAMES = 180
BRIDGE_EMBODIMENT_REOBSERVE_FRAMES = 240
BRIDGE_EMBODIMENT_MAX_REPLANS = 6
BRIDGE_EMBODIMENT_JOURNAL_CAPACITY = 64
-- A recovery request may wait briefly for an already-running physical library
-- transaction, but it must not create an unbounded retry stream.  The frame
-- watchdog is a fallback for hosts where a time callback is delayed while the
-- TTS runtime is busy.
BRIDGE_RESYNC_AUTOMATIC_QUEUE_GRACE_SECONDS = 10.0
BRIDGE_RESYNC_STALL_FRAMES = 1800
BRIDGE_GRAVEYARD_ACTION_GROUP_THRESHOLD = 6
BRIDGE_DEFAULT_MATCH_FORMAT = "limited"
BRIDGE_ALLOW_DECK_MINIMUM_OVERRIDE = false
-- Configuration, not rules: FREEFORM permits a player to arrange their own
-- lands after they enter. STRICT re-applies the persistent land row only on
-- authoritative layout events or an explicit organize request.
BRIDGE_LAND_PLACEMENT_MODE = BRIDGE_LAND_PLACEMENT_MODE or "FREEFORM"
BRIDGE_SCRIPT_REVISION = "2026-09-07-h0-supplier-recovery-watchdog"

-- TTS can leave callbacks scheduled by the previous Global.lua alive during a
-- Save & Play reload.  Generations inside BridgeState start from zero again,
-- so they cannot distinguish that retired runtime from the freshly loaded
-- one.  This epoch intentionally lives outside BridgeState and is captured by
-- every bridge timer/request; a callback from an older script is then inert.
BRIDGE_RUNTIME_EPOCH = (tonumber(BRIDGE_RUNTIME_EPOCH) or 0) + 1
local BRIDGE_RUNTIME_EPOCH_LOCAL = BRIDGE_RUNTIME_EPOCH
local BRIDGE_CLIENT_RUNTIME_ID = table.concat({
    tostring(os.time()),
    tostring(math.floor(os.clock() * 1000000)),
    tostring(math.random(100000, 999999))
}, "-")

function BridgeRuntimeIsCurrent(epoch)
    return epoch == BRIDGE_RUNTIME_EPOCH
end

-- TTS print() writes to game chat. Keep protocol and diagnostic traffic in
-- the scripting console; explicit broadcastToAll calls remain user-facing.
function BridgeLog(message)
    log(tostring(message))
end

local BRIDGE_DECISION_LIFECYCLE_CAPACITY = 128

function BridgeRecordDecisionLifecycle(decision, origin, disposition, reason, actionId, actionType, automationPolicy, result)
    if decision == nil then return end
    local actionTypes = {}
    local nonPassActionCount = 0
    local hasPassPriority = false
    for _, action in ipairs(decision.actions or {}) do
        local kind = tostring(action.type or action.actionType or "unknown")
        table.insert(actionTypes, kind)
        if kind == "pass_priority" then
            hasPassPriority = true
        else
            nonPassActionCount = nonPassActionCount + 1
        end
    end
    local record = {
        timestamp = os.clock(),
        sessionId = BridgeState.eventSessionId,
        decisionId = decision.decisionId,
        origin = origin,
        kind = decision.kind,
        seatId = decision.seatId,
        activeSeatId = decision.activeSeatId,
        prioritySeatId = decision.prioritySeatId,
        turnNumber = decision.turnNumber,
        phaseName = decision.phaseName,
        eventCursor = decision.eventCursor,
        lastReceivedEventSequence = BridgeState.lastReceivedEventSequence,
        lastAppliedEventSequence = BridgeState.lastAppliedEventSequence,
        actionCount = #actionTypes,
        actionTypes = actionTypes,
        hasPassPriority = hasPassPriority,
        nonPassActionCount = nonPassActionCount,
        disposition = disposition,
        reason = reason,
        actionId = actionId,
        actionType = actionType,
        automationPolicy = automationPolicy,
        result = result
    }
    table.insert(BridgeState.decisionLifecycle, record)
    while #BridgeState.decisionLifecycle > BRIDGE_DECISION_LIFECYCLE_CAPACITY do
        table.remove(BridgeState.decisionLifecycle, 1)
    end
    BridgeLog(string.format(
        "[Bridge] DECISION_LIFECYCLE timestamp=%s session=%s decision=%s origin=%s kind=%s seat=%s active=%s priority=%s turn=%s phase=%s cursor=%s received=%s applied=%s actionCount=%s actionTypes=%s pass=%s nonPass=%s disposition=%s reason=%s actionId=%s actionType=%s automationPolicy=%s result=%s",
        tostring(record.timestamp), tostring(record.sessionId), tostring(record.decisionId), tostring(origin),
        tostring(record.kind), tostring(record.seatId), tostring(record.activeSeatId), tostring(record.prioritySeatId),
        tostring(record.turnNumber), tostring(record.phaseName), tostring(record.eventCursor),
        tostring(record.lastReceivedEventSequence), tostring(record.lastAppliedEventSequence),
        tostring(record.actionCount), #actionTypes > 0 and table.concat(actionTypes, ",") or "none",
        tostring(record.hasPassPriority), tostring(record.nonPassActionCount), tostring(disposition),
        tostring(reason), tostring(actionId), tostring(actionType), tostring(automationPolicy), tostring(result)))
    if decision.kind == "main_priority" and decision.seatId == "forge-player-1"
        and string.find(string.lower(tostring(decision.phaseName or "")), "main", 1, true) ~= nil then
        BridgeLog(string.format(
            "[Bridge] MAIN1_TX decision=%s cursor=%s received=%s applied=%s pass=%s nonPass=%s origin=%s disposition=%s reason=%s",
            tostring(decision.decisionId), tostring(decision.eventCursor),
            tostring(record.lastReceivedEventSequence), tostring(record.lastAppliedEventSequence),
            tostring(record.hasPassPriority), tostring(record.nonPassActionCount), tostring(origin),
            tostring(disposition), tostring(reason)))
    end
    return record
end

function BridgeCheckProjectionCoherence(decision, reason)
    if decision == nil then return true end
    local mismatches = {}
    local function same(left, right)
        return left == nil or right == nil or tostring(left) == tostring(right)
    end
    if not same(decision.turnNumber, BridgeState.tableTurnCount) then table.insert(mismatches, "turn") end
    if not same(decision.activeSeatId, BridgeState.currentTurnSeatId) then table.insert(mismatches, "active-seat") end
    if not same(decision.prioritySeatId, BridgeState.prioritySeatId) then table.insert(mismatches, "priority-seat") end
    if decision.phaseName ~= nil and BridgeState.currentPhase ~= nil
        and BridgePriorityPhaseFamily ~= nil
        and BridgePriorityPhaseFamily(decision.phaseName) ~= BridgePriorityPhaseFamily(BridgeState.currentPhase) then
        table.insert(mismatches, "phase")
    end
    local decisionCursor = tonumber(decision.eventCursor or 0) or 0
    local projected = math.max(
        tonumber(BridgeState.lastAppliedEventSequence or 0) or 0,
        tonumber(BridgeState.lastStateProjectedEventSequence or 0) or 0)
    if decisionCursor > projected then table.insert(mismatches, "cursor-coverage") end
    if #mismatches == 0 then return true end
    BridgeState.projectionCoherenceMismatchCount = (BridgeState.projectionCoherenceMismatchCount or 0) + 1
    BridgeState.lastProjectionCoherenceMismatch = {
        reason = reason, decisionId = decision.decisionId, mismatches = mismatches,
        decisionTurn = decision.turnNumber, projectedTurn = BridgeState.tableTurnCount,
        decisionPhase = decision.phaseName, projectedPhase = BridgeState.currentPhase,
        decisionCursor = decisionCursor, projectedCursor = projected
    }
    BridgeLog(string.format("[Bridge] PROJECTION_COHERENCE_MISMATCH decision=%s reason=%s fields=%s decisionCursor=%s projectedCursor=%s",
        tostring(decision.decisionId), tostring(reason), table.concat(mismatches, ","),
        tostring(decisionCursor), tostring(projected)))
    return false
end

-- Capture is an observer, but its callback is also the best place to prove
-- that the presentation pumps survived it. Keep this ring intentionally
-- small and free of card identities so the next report can explain a
-- post-capture failure without retaining a large snapshot payload.
function BridgeRecordDiagnosticCaptureLifecycle(stage, token, reason)
    local decision = BridgeState.lastDecision
    local ui = BridgeState.ui or {}
    local record = {
        timestamp = os.clock(),
        stage = tostring(stage or "unknown"),
        token = token,
        reason = reason,
        sessionId = BridgeState.eventSessionId,
        decisionId = decision and decision.decisionId or nil,
        decisionKind = decision and decision.kind or nil,
        decisionEventCursor = decision and decision.eventCursor or nil,
        lastReceivedEventSequence = BridgeState.lastReceivedEventSequence,
        lastAppliedEventSequence = BridgeState.lastAppliedEventSequence,
        eventQueueLength = #(BridgeState.eventQueue or {}),
        eventPolling = BridgeState.eventPolling == true,
        eventRequestInFlight = BridgeState.eventRequestInFlight == true,
        eventRequestGeneration = BridgeState.eventRequestGeneration,
        eventPollScheduled = BridgeState.eventPollScheduled == true,
        eventPollGeneration = BridgeState.eventPollGeneration,
        eventSessionGeneration = BridgeState.eventSessionGeneration,
        decisionPollInFlight = BridgeState.decisionPollInFlight == true,
        decisionPollScheduled = BridgeState.decisionPollScheduled == true,
        decisionPollScheduledAt = BridgeState.decisionPollScheduledAt,
        decisionPollDueAt = BridgeState.decisionPollDueAt,
        decisionPollScheduledUpdateTick = BridgeState.decisionPollScheduledUpdateTick,
        decisionPollDueUpdateTick = BridgeState.decisionPollDueUpdateTick,
        decisionPollTimerToken = BridgeState.decisionPollTimerToken,
        lastDecisionPollStartedAt = BridgeState.lastDecisionPollStartedAt,
        lastDecisionPollCompletedAt = BridgeState.lastDecisionPollCompletedAt,
        lastDecisionPollOutcome = BridgeState.lastDecisionPollOutcome,
        decisionAuthoritativeWatermark = BridgeState.decisionAuthoritativeWatermark,
        decisionPollGeneration = BridgeState.decisionPollGeneration,
        decisionRefreshInFlight = BridgeState.decisionRefreshInFlight == true,
        submitting = BridgeState.submitting == true,
        choiceProtocolPaused = BridgeState.choiceProtocolPaused == true,
        animationRunning = BridgeState.animationRunning == true,
        yieldPolicyTurnNumber = BridgeState.yieldPolicyTurnNumber,
        yieldPolicyActiveSeatId = BridgeState.yieldPolicyActiveSeatId,
        yieldPolicySessionId = BridgeState.yieldPolicySessionId,
        yieldPolicyOwnTurn = BridgeState.yieldPolicyOwnTurn == true,
        yieldMode = BridgeYieldControllerMode ~= nil and BridgeYieldControllerMode() or "normal",
        autoPassEmpty = ui.autoPassEmpty == true,
        fastForwardActive = ui.fastForwardActive == true,
        fastForwardStopScope = ui.fastForwardStopScope,
        fastForwardStops = ui.fastForwardStops,
        presentationGeneration = BridgeState.decisionPresentationGeneration,
        physicalPresentationGeneration = BridgeState.currentPhysicalPresentationGeneration,
        lastConsumedEventSequence = BridgeState.lastConsumedEventSequence,
        lastStateProjectedEventSequence = BridgeState.lastStateProjectedEventSequence,
        lastPhysicalPresentationEventSequence = BridgeState.lastPhysicalPresentationEventSequence,
        phaseSourceEventSequence = BridgeState.phaseSourceEventSequence,
        turnSourceEventSequence = BridgeState.turnSourceEventSequence,
        activePlayerSourceEventSequence = BridgeState.activePlayerSourceEventSequence,
        prioritySourceEventSequence = BridgeState.prioritySourceEventSequence,
        projectionCoherenceMismatchCount = BridgeState.projectionCoherenceMismatchCount,
        lastProjectionCoherenceMismatch = BridgeState.lastProjectionCoherenceMismatch,
        physicalTransactionGeneration = BridgeState.physicalTransactionGeneration,
        eventDrainBlockReason = BridgeEventDrainBlockReason(),
        resyncInFlight = BridgeState.resyncInFlight == true,
        coreResyncInFlight = BridgeState.resyncInFlight == true,
        uiResyncInFlight = ui.resyncInFlight == true,
        resyncScheduled = BridgeState.resyncScheduled == true,
        resyncToken = BridgeState.resyncToken,
        resyncOrigin = BridgeState.resyncOrigin,
        resyncStartedAt = BridgeState.resyncStartedAt,
        resyncUpdateTick = BridgeState.resyncUpdateTick,
        resyncStartedUpdateTick = BridgeState.resyncStartedUpdateTick,
        resyncStartedCpuAt = BridgeState.resyncStartedCpuAt,
        resyncLastStartedAt = BridgeState.resyncLastStartedAt,
        resyncLastStartedCpuAt = BridgeState.resyncLastStartedCpuAt,
        resyncLastStartedUpdateTick = BridgeState.resyncLastStartedUpdateTick,
        resyncStage = BridgeState.resyncStage,
        resyncStageChangedAt = BridgeState.resyncStageChangedAt,
        resyncLastProgressAt = BridgeState.resyncLastProgressAt,
        resyncLastCallbackStage = BridgeState.resyncLastCallbackStage,
        resyncLastCallbackAt = BridgeState.resyncLastCallbackAt,
        resyncLastCallbackReason = BridgeState.resyncLastCallbackReason,
        resyncExpectedCallbackStage = BridgeState.resyncExpectedCallbackStage,
        resyncExpectedCallbackAt = BridgeState.resyncExpectedCallbackAt,
        resyncExpectedCallbackReason = BridgeState.resyncExpectedCallbackReason,
        resyncLastUnobservedCallbackStage = BridgeState.resyncLastUnobservedCallbackStage,
        resyncLastUnobservedCallbackAt = BridgeState.resyncLastUnobservedCallbackAt,
        resyncLastUnobservedCallbackReason = BridgeState.resyncLastUnobservedCallbackReason,
        resyncCompletionScheduled = BridgeState.resyncCompletionContinuation ~= nil,
        resyncCompletionToken = BridgeState.resyncCompletionContinuation and BridgeState.resyncCompletionContinuation.token or nil,
        resyncCompletionStage = BridgeState.resyncCompletionContinuation and BridgeState.resyncCompletionContinuation.stage or nil,
        resyncCompletionScheduledAt = BridgeState.resyncCompletionContinuation and BridgeState.resyncCompletionContinuation.scheduledAt or nil,
        resyncCompletionDueUpdateTick = BridgeState.resyncCompletionContinuation and BridgeState.resyncCompletionContinuation.dueUpdateTick or nil,
        resyncPhysicalRebuildReady = BridgeState.resyncPhysicalRebuildReady == true,
        resyncPhysicalValidationPassed = BridgeState.resyncPhysicalValidationPassed == true,
        resyncCandidateSnapshotCursor = BridgeState.resyncCandidateSnapshot and BridgeState.resyncCandidateSnapshot.eventCursor or nil,
        resyncMappingTransactionStatus = BridgeState.resyncMappingTransactionStatus,
        resyncMappingTransactionStartedAt = BridgeState.resyncMappingTransactionStartedAt,
        resyncMappingTransactionCompletedAt = BridgeState.resyncMappingTransactionCompletedAt,
        resyncLastFailureReason = BridgeState.resyncLastFailureReason,
        resyncLastBlockingPredicate = BridgeState.resyncLastBlockingPredicate,
        resyncDeferredReason = BridgeState.resyncDeferredReason,
        resyncDeferredSince = BridgeState.resyncDeferredSince,
        resyncDeferredRetryScheduled = BridgeState.resyncDeferredRetryScheduled == true,
        resyncWatchdogToken = BridgeState.resyncWatchdogToken,
        resyncLifecycle = BridgeState.resyncLifecycle or {},
        resyncBootstrapGeneration = BridgeState.resyncBootstrapGeneration,
        resyncReconcileStarted = BridgeState.resyncReconcileStarted == true,
        reportCaptureInFlight = ui.reportCaptureInFlight == true
    }
    local lifecycle = BridgeState.diagnosticCaptureLifecycle
    if lifecycle == nil then
        lifecycle = {}
        BridgeState.diagnosticCaptureLifecycle = lifecycle
    end
    table.insert(lifecycle, record)
    while #lifecycle > BRIDGE_DIAGNOSTIC_CAPTURE_LIFECYCLE_CAPACITY do
        table.remove(lifecycle, 1)
    end
    BridgeLog(string.format(
        "[Bridge] %s token=%s reason=%s session=%s decision=%s event=%s/%s queue=%s eventPoll=%s request=%s scheduled=%s decisionPoll=%s/%s refresh=%s submitting=%s yield=%s",
        tostring(record.stage), tostring(record.token), tostring(record.reason), tostring(record.sessionId),
        tostring(record.decisionId), tostring(record.lastAppliedEventSequence), tostring(record.lastReceivedEventSequence),
        tostring(record.eventQueueLength), tostring(record.eventPolling), tostring(record.eventRequestInFlight),
        tostring(record.eventPollScheduled), tostring(record.decisionPollInFlight),
        tostring(record.decisionPollScheduled), tostring(record.decisionRefreshInFlight),
        tostring(record.submitting), tostring(record.yieldPolicyTurnNumber)))
    return record
end

function BridgeCurrentAuthoritativeResult()
    local result = BridgeState.gameEnded
    if result == nil then return nil end
    if result.authoritative ~= true then return nil end
    if result.sourceEventId == nil or result.sourceEventCursor == nil then return nil end
    if result.sourceSessionId == nil or result.sourceSessionId ~= BridgeState.eventSessionId then return nil end
    return result
end

function BridgeCurrentTerminalRecoveryError()
    local error = BridgeState.terminalRecoveryError
    if error == nil then return nil end
    if BridgeState.eventSessionId ~= nil then
        local expectedSessionId = error.sessionId or error.sourceSessionId
        if expectedSessionId ~= nil and expectedSessionId ~= BridgeState.eventSessionId then
            return nil
        end
    end
    if error.sessionGeneration ~= nil and BridgeState.eventSessionGeneration ~= nil
        and error.sessionGeneration ~= BridgeState.eventSessionGeneration then
        return nil
    end
    return error
end

function BridgeDiagnosticPresentedResult()
    local result = BridgeCurrentAuthoritativeResult()
    local terminal = BridgeCurrentTerminalRecoveryError()
    return {
        presented = result ~= nil,
        sourceEventId = result and result.sourceEventId or nil,
        sourceEventCursor = result and result.sourceEventCursor or nil,
        sourceSessionId = result and result.sourceSessionId or nil,
        outcome = result and result.outcome or nil,
        reason = result and result.reason or nil,
        presentationGeneration = result and result.presentationGeneration or nil,
        terminalRecoveryError = terminal ~= nil
    }
end

-- Keep repeated stale automatic-resync responses visible without changing
-- recovery behavior. A same-cursor response is not progress merely because
-- the request succeeded; this bounded streak makes a readiness loop
-- diagnosable in the next report.
function BridgeRecordResyncSnapshotProgress(origin, snapshot)
    if snapshot == nil then return end
    local sessionId = BridgeState.eventSessionId
    local forgeSequence = snapshot.forgeSequence
    local eventCursor = snapshot.eventCursor
    local progress = BridgeState.resyncNoProgress
    if progress == nil then
        progress = {sessionId = nil, forgeSequence = nil, eventCursor = nil, count = 0, lastLoggedCount = 0}
        BridgeState.resyncNoProgress = progress
    end
    local same = progress.sessionId == sessionId
        and tostring(progress.forgeSequence) == tostring(forgeSequence)
        and tostring(progress.eventCursor) == tostring(eventCursor)
    local previousForgeSequence = progress.forgeSequence
    local previousEventCursor = progress.eventCursor
    if same then progress.count = (progress.count or 0) + 1
    else
        progress.count = 1
        progress.lastLoggedCount = 0
    end
    progress.sessionId = sessionId
    progress.forgeSequence = forgeSequence
    progress.eventCursor = eventCursor
    BridgeLog(string.format(
        "[Bridge] RESYNC_PROGRESS origin=%s session=%s forgeSequence=%s eventCursor=%s previousForgeSequence=%s previousEventCursor=%s count=%s lastReceived=%s lastApplied=%s pendingDecision=%s pendingDecisionCursor=%s",
        tostring(origin), tostring(sessionId), tostring(forgeSequence), tostring(eventCursor),
        tostring(previousForgeSequence), tostring(previousEventCursor), tostring(progress.count),
        tostring(BridgeState.lastReceivedEventSequence), tostring(BridgeState.lastAppliedEventSequence),
        tostring(BridgeState.pendingDecision and BridgeState.pendingDecision.decisionId or nil),
        tostring(BridgeState.pendingDecision and BridgeState.pendingDecision.eventCursor or nil)))
    if not same or progress.count == 1 then
        BridgeState.resyncLastProgressAt = BridgeResyncClockNow ~= nil and BridgeResyncClockNow() or os.clock()
    end
    if same and progress.count >= 3 and progress.lastLoggedCount < 3 then
        progress.lastLoggedCount = progress.count
        BridgeState.resyncNoProgressAttempts = (BridgeState.resyncNoProgressAttempts or 0) + 1
        BridgeState.resyncLastFailureReason = "identical snapshot without recovery progress"
        BridgeState.resyncCircuitOpen = true
        BridgeState.snapshotRecoveryOwner = {
            sessionId = sessionId, targetCursor = eventCursor,
            embodimentEpoch = BridgeState.embodimentEpoch,
            recoveryGeneration = BridgeState.resyncAttempt or 0,
            circuitOpen = true
        }
        BridgeLog(string.format(
            "[Bridge] RESYNC_NO_PROGRESS origin=%s session=%s forgeSequence=%s eventCursor=%s previousForgeSequence=%s previousEventCursor=%s count=%s lastReceived=%s lastApplied=%s pendingDecision=%s pendingDecisionCursor=%s",
            tostring(origin), tostring(sessionId), tostring(forgeSequence), tostring(eventCursor),
            tostring(previousForgeSequence), tostring(previousEventCursor), tostring(progress.count),
            tostring(BridgeState.lastReceivedEventSequence), tostring(BridgeState.lastAppliedEventSequence),
            tostring(BridgeState.pendingDecision and BridgeState.pendingDecision.decisionId or nil),
            tostring(BridgeState.pendingDecision and BridgeState.pendingDecision.eventCursor or nil)))
        if BridgeState.resyncInFlight == true and BridgeReleaseStalledResync ~= nil then
            BridgeReleaseStalledResync(BridgeState.eventSessionId, BridgeState.resyncToken,
                "identical-snapshot-circuit-breaker")
        end
    end
end

function BridgeRecordResyncLifecycle(stage, origin, generation, snapshot, reason, expectedInstanceId, beforeReceived, beforeApplied)
    local lifecycle = BridgeState.resyncLifecycle
    if lifecycle == nil then lifecycle = {}; BridgeState.resyncLifecycle = lifecycle end
    local now = os.clock()
    if BridgeResyncClockNow ~= nil then
        local ok, value = pcall(BridgeResyncClockNow)
        if ok and value ~= nil then now = value end
    end
    local record = {
        timestamp = now, stage = stage, sessionId = BridgeState.eventSessionId,
        generation = generation, token = BridgeState.resyncToken, origin = origin,
        resyncStage = BridgeState.resyncStage, stageChangedAt = BridgeState.resyncStageChangedAt,
        lastProgressAt = BridgeState.resyncLastProgressAt,
        expectedCallbackStage = BridgeState.resyncExpectedCallbackStage,
        expectedCallbackAt = BridgeState.resyncExpectedCallbackAt,
        lastCallbackStage = BridgeState.resyncLastCallbackStage,
        lastCallbackAt = BridgeState.resyncLastCallbackAt,
        lastUnobservedCallbackStage = BridgeState.resyncLastUnobservedCallbackStage,
        lastUnobservedCallbackAt = BridgeState.resyncLastUnobservedCallbackAt,
        snapshotCursor = snapshot ~= nil and snapshot.eventCursor or nil,
        receivedBefore = beforeReceived, appliedBefore = beforeApplied,
        receivedAfter = BridgeState.lastReceivedEventSequence,
        appliedAfter = BridgeState.lastAppliedEventSequence,
        expectedCardInstanceId = expectedInstanceId, blockingPredicate = reason,
        elapsed = BridgeState.resyncStartedAt ~= nil and now - BridgeState.resyncStartedAt or nil
    }
    table.insert(lifecycle, record)
    while #lifecycle > 64 do table.remove(lifecycle, 1) end
    BridgeLog(string.format("[Bridge] RESYNC_%s generation=%s origin=%s cursor=%s received=%s/%s applied=%s/%s reason=%s",
        tostring(stage), tostring(generation), tostring(origin), tostring(record.snapshotCursor),
        tostring(beforeReceived), tostring(record.receivedAfter), tostring(beforeApplied),
        tostring(record.appliedAfter), tostring(reason)))
    return record
end

function BridgeSetResyncStage(stage, reason, snapshot)
    local prior = BridgeState.resyncStage or "Idle"
    BridgeState.resyncStage = stage
    BridgeState.resyncStageChangedAt = BridgeResyncClockNow ~= nil and BridgeResyncClockNow() or os.clock()
    BridgeState.resyncLastProgressAt = BridgeState.resyncStageChangedAt
    BridgeLog(string.format("[Bridge] RESYNC_STAGE %s -> %s session=%s generation=%s token=%s cursor=%s reason=%s",
        tostring(prior), tostring(stage), tostring(BridgeState.eventSessionId),
        tostring(BridgeState.eventSessionGeneration), tostring(BridgeState.resyncToken),
        tostring(snapshot and snapshot.eventCursor or nil), tostring(reason)))
end

function BridgeSetSchedulerOwner(owner, reason)
    local prior = BridgeState.schedulerOwner or "NORMAL"
    if prior == owner then return end
    BridgeState.schedulerOwner = owner
    BridgeLog(string.format("[Bridge] SCHEDULER_OWNER %s -> %s reason=%s",
        tostring(prior), tostring(owner), tostring(reason or "unspecified")))
end

function BridgePresentationMetric(name)
    BridgeState.presentationMetrics[name] = (BridgeState.presentationMetrics[name] or 0) + 1
end

function BridgeStartupPerfNowSeconds()
    local wall = BridgePerformanceWallNow()
    if wall ~= nil then return wall end
    return BridgePerformanceNow()
end

function BridgeStartupPerfEnsure()
    local startup = BridgeState.startupPerf
    if startup ~= nil then return startup end
    startup = {
        active = false,
        origin = nil,
        baseWallSeconds = nil,
        baseCpuSeconds = nil,
        baseUpdateTick = 0,
        stageTokens = {},
        stageRecords = {},
        counters = {}
    }
    BridgeState.startupPerf = startup
    return startup
end

function BridgeStartupPerfReset(origin)
    local startup = BridgeStartupPerfEnsure()
    startup.active = true
    startup.origin = tostring(origin or "unknown")
    startup.baseWallSeconds = BridgeStartupPerfNowSeconds()
    startup.baseCpuSeconds = BridgePerformanceNow()
    startup.baseUpdateTick = tonumber(BridgeState.updateTick or 0) or 0
    startup.stageTokens = {}
    startup.stageRecords = {}
    startup.counters = {}
    BridgeLog(string.format(
        "[Bridge] STARTUP_PERF stage=startup-reset origin=%s elapsedMs=0 totalMs=0 ticks=0",
        startup.origin))
end

function BridgeStartupPerfCounter(name, delta)
    local startup = BridgeState.startupPerf
    if startup == nil or startup.active ~= true then return end
    local key = tostring(name or "unknown")
    startup.counters[key] = (tonumber(startup.counters[key] or 0) or 0) + (tonumber(delta or 1) or 1)
end

function BridgeStartupPerfStageBegin(stage, detail)
    local startup = BridgeState.startupPerf
    if startup == nil or startup.active ~= true then return end
    local key = tostring(stage or "unknown")
    startup.stageTokens[key] = {
        wallStartedAt = BridgeStartupPerfNowSeconds(),
        cpuStartedAt = BridgePerformanceNow(),
        updateTick = tonumber(BridgeState.updateTick or 0) or 0,
        detail = detail
    }
end

function BridgeStartupPerfStageEnd(stage, detail)
    local startup = BridgeState.startupPerf
    if startup == nil or startup.active ~= true then return end
    local key = tostring(stage or "unknown")
    local token = startup.stageTokens[key]
    if token == nil then
        token = {
            wallStartedAt = BridgeStartupPerfNowSeconds(),
            cpuStartedAt = BridgePerformanceNow(),
            updateTick = tonumber(BridgeState.updateTick or 0) or 0
        }
    end
    startup.stageTokens[key] = nil
    local endedWall = BridgeStartupPerfNowSeconds()
    local elapsedMs = math.max(0, (endedWall - (token.wallStartedAt or endedWall)) * 1000)
    local totalMs = startup.baseWallSeconds ~= nil and math.max(0, (endedWall - startup.baseWallSeconds) * 1000) or elapsedMs
    local updateTick = tonumber(BridgeState.updateTick or 0) or 0
    local tickDelta = math.max(0, updateTick - (token.updateTick or updateTick))
    startup.stageRecords[key] = {
        stage = key,
        elapsedMs = elapsedMs,
        totalMs = totalMs,
        ticks = tickDelta,
        detail = detail or token.detail
    }
    BridgeLog(string.format(
        "[Bridge] STARTUP_PERF stage=%s elapsedMs=%.0f totalMs=%.0f ticks=%d detail=%s",
        key,
        elapsedMs,
        totalMs,
        tickDelta,
        tostring(detail or token.detail or "")))
end

function BridgeStartupPerfEvent(stage, detail)
    local startup = BridgeState.startupPerf
    if startup == nil or startup.active ~= true then return end
    local nowWall = BridgeStartupPerfNowSeconds()
    local totalMs = startup.baseWallSeconds ~= nil and math.max(0, (nowWall - startup.baseWallSeconds) * 1000) or 0
    local ticks = math.max(0, (tonumber(BridgeState.updateTick or 0) or 0) - (startup.baseUpdateTick or 0))
    BridgeLog(string.format(
        "[Bridge] STARTUP_PERF stage=%s elapsedMs=0 totalMs=%.0f ticks=%d detail=%s",
        tostring(stage or "event"),
        totalMs,
        ticks,
        tostring(detail or "")))
end

-- Automated pass/yield is presentation convenience, so it must not let Forge
-- outrun a TTS event backlog created by local rendering work. Manual choices
-- remain unaffected and the next authoritative decision resumes automation.
function BridgeAutomaticPassBackpressured()
    local received = tonumber(BridgeState.lastReceivedEventSequence or 0) or 0
    local applied = tonumber(BridgeState.lastAppliedEventSequence or 0) or 0
    local backlog = math.max(#(BridgeState.eventQueue or {}), math.max(0, received - applied))
    if backlog <= 0 and not BridgeState.animationRunning
        and not BridgeState.snapshotReconcileInFlight then return false end
    BridgePresentationMetric("yieldBackpressurePauseCount")
    BridgeLog("[Bridge] automated pass held behind presentation backlog=" .. tostring(backlog))
    return true
end

function BridgeRetireInvalidEventDrainOwnership(origin)
    local tx = BridgeState.eventDrainTransaction
    local continuation = BridgeState.eventDrainContinuation
    local continuationQueue = continuation ~= nil and continuation.transaction ~= nil
        and continuation.transaction.queue or nil
    if continuation ~= nil and continuationQueue ~= nil and continuationQueue ~= BridgeState.eventQueue then
        BridgeClearEventDrainContinuation(continuation, "queue-replaced")
    end
    if tx == nil then
        if BridgeState.animationRunning == true then
            BridgeState.animationRunning = false
            BridgeLog(string.format("[Bridge] EVENT_DRAIN_HEAL cleared orphan animation fence origin=%s",
                tostring(origin)))
            return true
        end
        return false
    end
    if BridgeEventMutationIsCurrent == nil then
        return false
    end
    local ok, current = pcall(BridgeEventMutationIsCurrent, tx)
    if ok and current == true then
        return false
    end
    BridgeState.eventDrainTransaction = nil
    BridgeState.animationRunning = false
    BridgeLog(string.format(
        "[Bridge] EVENT_DRAIN_HEAL cleared stale transaction ownership origin=%s token=%s session=%s sessionGeneration=%s physicalGeneration=%s state=%s current=%s",
        tostring(origin), tostring(tx.token), tostring(tx.sessionId), tostring(tx.eventSessionGeneration),
        tostring(tx.physicalTransactionGeneration), tostring(tx.state), tostring((ok and current) or "probe-failed")))
    return true
end

function BridgeResyncCallbackNow()
    return BridgeResyncClockNow ~= nil and BridgeResyncClockNow() or os.clock()
end

function BridgeResyncCallbackExpected(stage, reason)
    BridgeState.resyncExpectedCallbackStage = stage
    BridgeState.resyncExpectedCallbackAt = BridgeResyncCallbackNow()
    BridgeState.resyncExpectedCallbackReason = reason
    BridgeState.resyncLastProgressAt = BridgeState.resyncExpectedCallbackAt
    BridgeLog(string.format("[Bridge] RESYNC_CALLBACK_EXPECTED stage=%s reason=%s token=%s generation=%s",
        tostring(stage), tostring(reason), tostring(BridgeState.resyncToken),
        tostring(BridgeState.resyncBootstrapGeneration)))
end

function BridgeResyncCallbackObserved(stage, reason)
    local now = BridgeResyncCallbackNow()
    BridgeState.resyncLastCallbackStage = stage
    BridgeState.resyncLastCallbackAt = now
    BridgeState.resyncLastCallbackReason = reason
    BridgeState.resyncExpectedCallbackStage = nil
    BridgeState.resyncExpectedCallbackAt = nil
    BridgeState.resyncExpectedCallbackReason = nil
    BridgeState.resyncLastProgressAt = now
    BridgeLog(string.format("[Bridge] RESYNC_CALLBACK_OBSERVED stage=%s reason=%s token=%s generation=%s",
        tostring(stage), tostring(reason), tostring(BridgeState.resyncToken),
        tostring(BridgeState.resyncBootstrapGeneration)))
end

function BridgeEventDrainContinuationNow()
    return os.clock()
end

function BridgeClearEventDrainContinuation(owner, reason)
    if owner ~= nil and BridgeState.eventDrainContinuation ~= owner then return false end
    local current = BridgeState.eventDrainContinuation
    if current == nil then return false end
    BridgeState.eventDrainContinuation = nil
    if current.transaction ~= nil then
        current.transaction.continuationScheduled = false
    end
    if reason ~= nil then
        BridgeState.eventDrainLastContinuation = {
            token = current.token,
            transactionToken = current.transactionToken,
            eventSequence = current.eventSequence,
            reason = reason,
            at = BridgeEventDrainContinuationNow()
        }
    end
    return true
end

-- Install exactly one continuation owner for a committed transaction.  TTS
-- does not provide a reliable timer handle, so identity is fenced by object
-- identity plus session/physical generations.  A stale callback can therefore
-- neither clear a newer owner nor enter the queue pump.
function BridgeScheduleEventDrainContinuation(transaction, delay)
    if transaction == nil then return false end
    local existing = BridgeState.eventDrainContinuation
    if existing ~= nil then
        if existing.transaction == transaction then return false end
        BridgeLog(string.format(
            "[Bridge] EVENT_DRAIN_CONTINUATION_REPLACED oldToken=%s newTransaction=%s",
            tostring(existing.token), tostring(transaction.token)))
        BridgeClearEventDrainContinuation(existing, "replaced")
    end
    local nextDelay = tonumber(delay or 0) or 0
    if nextDelay < 0 then nextDelay = 0 end
    BridgeState.eventDrainContinuationToken = (BridgeState.eventDrainContinuationToken or 0) + 1
    local token = BridgeState.eventDrainContinuationToken
    local now = BridgeEventDrainContinuationNow()
    local updateTick = tonumber(BridgeState.updateTick or 0) or 0
    local owner = {
        token = token,
        transaction = transaction,
        transactionToken = transaction.token,
        sessionId = BridgeState.eventSessionId,
        sessionGeneration = BridgeState.eventSessionGeneration or 0,
        physicalTransactionGeneration = BridgeState.physicalTransactionGeneration or 0,
        eventSequence = transaction.lastEventSequence or transaction.eventSequence,
        scheduledAt = now,
        dueAt = now + math.max(nextDelay, BRIDGE_EVENT_DRAIN_STALL_SECONDS),
        scheduledUpdateTick = updateTick,
        dueUpdateTick = updateTick + math.max(BRIDGE_EVENT_DRAIN_CONTINUATION_STALL_FRAMES,
            math.ceil(nextDelay * 60)),
        callbackObserved = false
    }
    BridgeState.eventDrainContinuation = owner
    transaction.continuationScheduled = true
    transaction.continuationToken = token
    BridgeState.eventDrainLastContinuation = nil
    BridgeWaitTime(function()
        -- Equality is the ownership fence.  In particular, an old callback A
        -- must not clear or execute a newer callback B.
        if BridgeState.eventDrainContinuation ~= owner then return end
        owner.callbackObserved = true
        BridgeClearEventDrainContinuation(owner, "callback")
        if owner.sessionId ~= BridgeState.eventSessionId
            or owner.sessionGeneration ~= (BridgeState.eventSessionGeneration or 0)
            or owner.physicalTransactionGeneration ~= (BridgeState.physicalTransactionGeneration or 0) then
            return
        end
        local ok, err = pcall(BridgeProcessEventQueue)
        if not ok then
            BridgeLog("[Bridge] EVENT_DRAIN_CONTINUATION_FAILED error=" .. tostring(err))
            BridgeStopOnDesync("event drain continuation failed: " .. tostring(err))
        end
    end, nextDelay)
    return true
end

-- Reclaim only a continuation whose bounded deadline has elapsed.  Healthy
-- timers remain the normal path; this function is called from onUpdate solely
-- to repair a native callback which TTS silently dropped.
function BridgeCheckEventDrainContinuationLiveness(reason)
    local owner = BridgeState.eventDrainContinuation
    if owner == nil then return false end
    if owner.sessionId ~= BridgeState.eventSessionId
        or owner.sessionGeneration ~= (BridgeState.eventSessionGeneration or 0)
        or owner.physicalTransactionGeneration ~= (BridgeState.physicalTransactionGeneration or 0) then
        BridgeClearEventDrainContinuation(owner, "stale-generation")
        return false
    end
    local now = BridgeEventDrainContinuationNow()
    local updateTick = tonumber(BridgeState.updateTick or 0) or 0
    local dueByClock = owner.dueAt ~= nil and now >= tonumber(owner.dueAt)
    local dueByFrames = owner.dueUpdateTick ~= nil and updateTick >= tonumber(owner.dueUpdateTick)
    if not dueByClock and not dueByFrames then return false end

    -- Retire exactly this owner before arming its replacement.  A stale A
    -- callback that later arrives sees owner B and is a no-op.
    BridgeClearEventDrainContinuation(owner, "lost:" .. tostring(reason or "onUpdate"))
    BridgeLog(string.format(
        "[Bridge] EVENT_DRAIN_CONTINUATION_LOST token=%s transaction=%s event=%s reason=%s",
        tostring(owner.token), tostring(owner.transactionToken), tostring(owner.eventSequence),
        tostring(reason or "onUpdate")))
    local replacement = owner.transaction
    if replacement == nil then return true end
    BridgeScheduleEventDrainContinuation(replacement, 0)
    return true
end

-- The final recovery callback is a separate ownership domain from the event
-- queue.  Physical reconstruction can be complete even when TTS drops the
-- last Wait.frames callback; retain a tokenized owner so onUpdate can resume
-- only that finalizer and never restart the whole snapshot request.
function BridgeClearResyncCompletionContinuation(owner, reason)
    if owner ~= nil and BridgeState.resyncCompletionContinuation ~= owner then return false end
    local current = BridgeState.resyncCompletionContinuation
    if current == nil then return false end
    BridgeState.resyncCompletionContinuation = nil
    if reason ~= nil then
        BridgeState.resyncLastCallbackReason = tostring(reason)
    end
    return true
end

function BridgeScheduleResyncCompletionContinuation(snapshot, callback, frames, stage)
    if snapshot == nil or callback == nil then return false end
    local existing = BridgeState.resyncCompletionContinuation
    if existing ~= nil then
        if existing.snapshot == snapshot then return false end
        BridgeClearResyncCompletionContinuation(existing, "replaced")
    end
    BridgeState.resyncCompletionContinuationToken = (BridgeState.resyncCompletionContinuationToken or 0) + 1
    local token = BridgeState.resyncCompletionContinuationToken
    local now = BridgeResyncCallbackNow ~= nil and BridgeResyncCallbackNow() or os.clock()
    local updateTick = tonumber(BridgeState.updateTick or 0) or 0
    local waitFrames = math.max(1, tonumber(frames or 1) or 1)
    local owner = {
        token = token,
        snapshot = snapshot,
        callback = callback,
        stage = stage or "physical-rebuild-finalize",
        sessionId = BridgeState.eventSessionId,
        sessionGeneration = BridgeState.eventSessionGeneration or 0,
        physicalTransactionGeneration = BridgeState.physicalTransactionGeneration or 0,
        resyncToken = BridgeState.resyncToken,
        bootstrapGeneration = BridgeState.resyncBootstrapGeneration,
        scheduledAt = now,
        scheduledUpdateTick = updateTick,
        dueAt = now + BRIDGE_RESYNC_STALL_SECONDS,
        dueUpdateTick = updateTick + math.max(BRIDGE_RESYNC_COMPLETION_STALL_FRAMES, waitFrames),
        callbackObserved = false
    }
    BridgeState.resyncCompletionContinuation = owner
    BridgeResyncCallbackExpected(owner.stage, "native-wait-frames")
    BridgeWaitFrames(function()
        if BridgeState.resyncCompletionContinuation ~= owner then return end
        owner.callbackObserved = true
        BridgeClearResyncCompletionContinuation(owner, "native-callback")
        if owner.sessionId ~= BridgeState.eventSessionId
            or owner.sessionGeneration ~= (BridgeState.eventSessionGeneration or 0)
            or owner.physicalTransactionGeneration ~= (BridgeState.physicalTransactionGeneration or 0)
            or owner.resyncToken ~= BridgeState.resyncToken
            or owner.bootstrapGeneration ~= BridgeState.resyncBootstrapGeneration then
            return
        end
        BridgeResyncCallbackObserved(owner.stage, "native-callback")
        callback("native-callback")
    end, waitFrames)
    return true
end

function BridgeCheckResyncCompletionLiveness(reason)
    local owner = BridgeState.resyncCompletionContinuation
    if owner == nil then return false end
    if owner.sessionId ~= BridgeState.eventSessionId
        or owner.sessionGeneration ~= (BridgeState.eventSessionGeneration or 0)
        or owner.physicalTransactionGeneration ~= (BridgeState.physicalTransactionGeneration or 0)
        or owner.resyncToken ~= BridgeState.resyncToken
        or owner.bootstrapGeneration ~= BridgeState.resyncBootstrapGeneration then
        BridgeClearResyncCompletionContinuation(owner, "stale-generation")
        return false
    end
    local now = BridgeResyncCallbackNow ~= nil and BridgeResyncCallbackNow() or os.clock()
    local updateTick = tonumber(BridgeState.updateTick or 0) or 0
    local dueByClock = owner.dueAt ~= nil and now >= tonumber(owner.dueAt)
    local dueByFrames = owner.dueUpdateTick ~= nil and updateTick >= tonumber(owner.dueUpdateTick)
    if not dueByClock and not dueByFrames then return false end
    BridgeClearResyncCompletionContinuation(owner, "lost:" .. tostring(reason or "onUpdate"))
    BridgeState.resyncLastUnobservedCallbackStage = owner.stage
    BridgeState.resyncLastUnobservedCallbackAt = now
    BridgeState.resyncLastUnobservedCallbackReason = tostring(reason or "onUpdate")
    BridgeLog(string.format("[Bridge] RESYNC_CALLBACK_LOST token=%s stage=%s reason=%s snapshotCursor=%s",
        tostring(owner.token), tostring(owner.stage), tostring(reason or "onUpdate"),
        tostring(owner.snapshot and owner.snapshot.eventCursor or nil)))
    BridgeResyncCallbackObserved(owner.stage, "onUpdate-liveness")
    owner.callback("onUpdate-liveness")
    return true
end

-- Return the actual fence preventing the queue head from starting.  This is
-- deliberately kept separate from the event cursor: a non-empty queue with a
-- stagnant cursor is only useful diagnostically when the scheduler says why
-- it is not being entered.
function BridgeEventDrainBlockReason()
    local queue = BridgeState.eventQueue or {}
    if #queue == 0 then return "queue_empty" end
    BridgeRetireInvalidEventDrainOwnership("block-reason")
    if BridgeState.animationRunning == true then return "animationRunning" end
    if BridgeState.eventPolling ~= true then return "eventPolling_disabled" end
    if BridgeState.desyncLatched == true then return "desyncLatched" end
    if BridgeState.resyncInFlight == true then return "resyncInFlight" end
    if BridgeState.bootstrapping == true then return "bootstrapping" end

    -- Physical library queues are reported by BridgeEventDrainQueueState, but
    -- are not an implicit event-drain fence.  Exact authoritative events and
    -- their serialized physical work are separate lifetimes; making the
    -- event pump wait here would turn a local queue delay into a second
    -- circular recovery failure.
    return "none"
end

function BridgeEventDrainQueueState()
    local queue = BridgeState.eventQueue or {}
    local head = queue[1]
    local physical = {}
    local physicalIdle = true
    for seatId, _ in pairs(BRIDGE_SEATS or {}) do
        local extractionActive = BridgeState.libraryExtractionActiveBySeatId[seatId] == true
        local extractionLength = #(BridgeState.libraryExtractionQueueBySeatId[seatId] or {})
        local mulliganActive = BridgeState.mulliganBottomInsertionActiveBySeatId[seatId] == true
        local mulliganLength = #(BridgeState.mulliganBottomQueueBySeatId[seatId] or {})
        if extractionActive or extractionLength > 0 or mulliganActive or mulliganLength > 0 then
            physicalIdle = false
        end
        physical[seatId] = {
            libraryExtractionActive = extractionActive,
            libraryExtractionLength = extractionLength,
            mulliganInsertionActive = mulliganActive,
            mulliganInsertionLength = mulliganLength,
            generation = BridgeState.physicalTransactionGeneration
        }
    end
    -- TTS JSON encodes an empty Lua table as [], but this diagnostic value is
    -- contractually an object. Keep the shape stable before the first hand
    -- ownership audit has populated it.
    local zoneOwnership = BridgeState.snapshotPhysicalZoneOwnership
    if type(zoneOwnership) ~= "table" or next(zoneOwnership) == nil then
        zoneOwnership = {
            expectedHandCount = 0,
            physicallyVerifiedHandCount = 0,
            internallyMappedHandCount = 0,
            repairedHandCount = 0,
            nilZoneCount = 0,
            wrongSeatCount = 0
        }
    end
    local libraryMapping = {}
    local aggregateExpected = 0
    local aggregateVerified = 0
    local aggregateMissing = 0
    local aggregateDuplicate = 0
    for seatId, _ in pairs(BRIDGE_SEATS or {}) do
        local entry = (BridgeState.bootstrapLibraryMappingBySeatId or {})[seatId] or {}
        local expected = tonumber(entry.expectedLibraryMappings or 0) or 0
        local verified = tonumber(entry.verifiedLibraryMappings or 0) or 0
        local missing = tonumber(entry.missingLibraryMappings or math.max(expected - verified, 0)) or 0
        local duplicate = tonumber(entry.duplicateLibraryMappings or 0) or 0
        local unsettled = tonumber(entry.unsettledGuidCount or 0) or 0
        local duplicateReal = tonumber(entry.duplicateRealGuidCount or duplicate) or 0
        aggregateExpected = aggregateExpected + expected
        aggregateVerified = aggregateVerified + verified
        aggregateMissing = aggregateMissing + missing
        aggregateDuplicate = aggregateDuplicate + duplicate
        aggregateUnsettled = (aggregateUnsettled or 0) + unsettled
        aggregateDuplicateReal = (aggregateDuplicateReal or 0) + duplicateReal
        libraryMapping[seatId] = {
            expectedLibraryMappings = expected,
            verifiedLibraryMappings = verified,
            missingLibraryMappings = missing,
            duplicateLibraryMappings = duplicate,
            duplicateRealGuidCount = duplicateReal,
            unsettledGuidCount = unsettled,
            status = entry.status,
            lastError = entry.lastError
        }
    end
    return {
        headSequence = head and head.sequence or nil,
        headKind = head and head.kind or nil,
        headSourceZone = head and head.sourceZone or nil,
        headDestinationZone = head and head.destinationZone or nil,
        queueLength = #queue,
        lastReceived = BridgeState.lastReceivedEventSequence,
        lastApplied = BridgeState.lastAppliedEventSequence,
        blockReason = BridgeEventDrainBlockReason(),
        animationRunning = BridgeState.animationRunning == true,
        continuationScheduled = BridgeState.eventDrainContinuation ~= nil,
        continuationToken = BridgeState.eventDrainContinuation and BridgeState.eventDrainContinuation.token or nil,
        continuationTransactionToken = BridgeState.eventDrainContinuation and BridgeState.eventDrainContinuation.transactionToken or nil,
        continuationEventSequence = BridgeState.eventDrainContinuation and BridgeState.eventDrainContinuation.eventSequence or nil,
        continuationSessionId = BridgeState.eventDrainContinuation and BridgeState.eventDrainContinuation.sessionId or nil,
        continuationSessionGeneration = BridgeState.eventDrainContinuation and BridgeState.eventDrainContinuation.sessionGeneration or nil,
        continuationPhysicalTransactionGeneration = BridgeState.eventDrainContinuation and BridgeState.eventDrainContinuation.physicalTransactionGeneration or nil,
        continuationCallbackObserved = BridgeState.eventDrainContinuation and BridgeState.eventDrainContinuation.callbackObserved or nil,
        continuationScheduledAt = BridgeState.eventDrainContinuation and BridgeState.eventDrainContinuation.scheduledAt or nil,
        continuationDueAt = BridgeState.eventDrainContinuation and BridgeState.eventDrainContinuation.dueAt or nil,
        continuationScheduledUpdateTick = BridgeState.eventDrainContinuation and BridgeState.eventDrainContinuation.scheduledUpdateTick or nil,
        continuationDueUpdateTick = BridgeState.eventDrainContinuation and BridgeState.eventDrainContinuation.dueUpdateTick or nil,
        continuationLastResult = BridgeState.eventDrainLastContinuation,
        physicalLibraryQueuesIdle = physicalIdle,
        physicalQueues = physical,
        snapshotReconcilePending = BridgeState.snapshotReconcilePending == true,
        snapshotReconcileInFlight = BridgeState.snapshotReconcileInFlight == true,
        eventPolling = BridgeState.eventPolling == true,
        eventRequestInFlight = BridgeState.eventRequestInFlight == true,
        eventPollScheduled = BridgeState.eventPollScheduled == true,
        desyncLatched = BridgeState.desyncLatched == true,
        resyncInFlight = BridgeState.resyncInFlight == true,
        bootstrapping = BridgeState.bootstrapping == true,
        terminalRecoveryError = BridgeCurrentTerminalRecoveryError() ~= nil,
        resyncToken = BridgeState.resyncToken,
        resyncOrigin = BridgeState.resyncOrigin,
        resyncRootCause = BridgeState.resyncRootCause,
        resyncLastFailureReason = BridgeState.resyncLastFailureReason,
        resyncCircuitOpen = BridgeState.resyncCircuitOpen == true,
        snapshotRecoveryOwner = BridgeDiagnosticSnapshot(BridgeState.snapshotRecoveryOwner or {}),
        snapshotRecoverySuppressedCount = BridgeState.snapshotRecoverySuppressedCount or 0,
        runtimeCompatibilityState = BridgeState.runtimeCompatibilityState,
        runtimeCompatibility = BridgeDiagnosticSnapshot(BridgeState.runtimeCompatibility or {}),
        schedulerOwner = BridgeState.schedulerOwner,
        lastSnapshotSupersededRange = BridgeState.lastSnapshotSupersededRange,
        resyncStartedAt = BridgeState.resyncStartedAt,
        resyncLastStartedAt = BridgeState.resyncLastStartedAt,
        resyncLastStartedCpuAt = BridgeState.resyncLastStartedCpuAt,
        resyncLastStartedUpdateTick = BridgeState.resyncLastStartedUpdateTick,
        resyncStage = BridgeState.resyncStage,
        resyncStageChangedAt = BridgeState.resyncStageChangedAt,
        resyncLastProgressAt = BridgeState.resyncLastProgressAt,
        resyncReconcileStarted = BridgeState.resyncReconcileStarted == true,
        resyncLastCallbackStage = BridgeState.resyncLastCallbackStage,
        resyncLastCallbackAt = BridgeState.resyncLastCallbackAt,
        resyncLastCallbackReason = BridgeState.resyncLastCallbackReason,
        resyncExpectedCallbackStage = BridgeState.resyncExpectedCallbackStage,
        resyncExpectedCallbackAt = BridgeState.resyncExpectedCallbackAt,
        resyncExpectedCallbackReason = BridgeState.resyncExpectedCallbackReason,
        resyncLastUnobservedCallbackStage = BridgeState.resyncLastUnobservedCallbackStage,
        resyncLastUnobservedCallbackAt = BridgeState.resyncLastUnobservedCallbackAt,
        resyncLastUnobservedCallbackReason = BridgeState.resyncLastUnobservedCallbackReason,
        resyncPhysicalRebuildReady = BridgeState.resyncPhysicalRebuildReady == true,
        resyncPhysicalValidationPassed = BridgeState.resyncPhysicalValidationPassed == true,
        resyncCandidateSnapshotCursor = BridgeState.resyncCandidateSnapshot and BridgeState.resyncCandidateSnapshot.eventCursor or nil,
        resyncMappingTransactionStatus = BridgeState.resyncMappingTransactionStatus,
        resyncMappingTransactionStartedAt = BridgeState.resyncMappingTransactionStartedAt,
        resyncMappingTransactionCompletedAt = BridgeState.resyncMappingTransactionCompletedAt,
        resyncCompletionScheduled = BridgeState.resyncCompletionContinuation ~= nil,
        resyncCompletionToken = BridgeState.resyncCompletionContinuation and BridgeState.resyncCompletionContinuation.token or nil,
        resyncCompletionStage = BridgeState.resyncCompletionContinuation and BridgeState.resyncCompletionContinuation.stage or nil,
        resyncCompletionScheduledAt = BridgeState.resyncCompletionContinuation and BridgeState.resyncCompletionContinuation.scheduledAt or nil,
        resyncCompletionDueUpdateTick = BridgeState.resyncCompletionContinuation and BridgeState.resyncCompletionContinuation.dueUpdateTick or nil,
        resyncUpdateTick = BridgeState.resyncUpdateTick,
        resyncStartedUpdateTick = BridgeState.resyncStartedUpdateTick,
        resyncDeferredReason = BridgeState.resyncDeferredReason,
        resyncDeferredSince = BridgeState.resyncDeferredSince,
        resyncDeferredRetryScheduled = BridgeState.resyncDeferredRetryScheduled == true,
        resyncWatchdogToken = BridgeState.resyncWatchdogToken,
        resyncBootstrapGeneration = BridgeState.resyncBootstrapGeneration,
        embodimentEpoch = BridgeState.embodimentEpoch,
        embodimentTransactionToken = BridgeState.embodimentTransactionToken,
        embodimentActive = BridgeState.embodimentTransaction ~= nil,
        embodimentReason = BridgeState.embodimentTransaction and BridgeState.embodimentTransaction.reason or nil,
        embodimentSessionId = BridgeState.embodimentTransaction and BridgeState.embodimentTransaction.targetSessionId or nil,
        embodimentTargetCursor = BridgeState.embodimentTransaction and BridgeState.embodimentTransaction.targetCursor or nil,
        embodimentPhase = BridgeState.embodimentTransaction and BridgeState.embodimentTransaction.phase or nil,
        embodimentOperationIndex = BridgeState.embodimentTransaction and BridgeState.embodimentTransaction.operationIndex or nil,
        embodimentReplanCount = BridgeState.embodimentTransaction and BridgeState.embodimentTransaction.replanCount or nil,
        embodimentLastProgressUpdateTick = BridgeState.embodimentTransaction and BridgeState.embodimentTransaction.lastProgressUpdateTick or nil,
        embodimentLastBlockingPredicate = BridgeState.embodimentTransaction and BridgeState.embodimentTransaction.lastBlockingPredicate or nil,
        embodimentJournal = BridgeDiagnosticSnapshot(BridgeState.embodimentJournal or {}),
        bootstrapStage = BridgeState.bootstrapStage,
        bootstrapStageChangedAt = BridgeState.bootstrapStageChangedAt,
        bootstrapLastProgressAt = BridgeState.bootstrapLastProgressAt,
        bootstrapStageTrace = BridgeDiagnosticSnapshot(BridgeState.bootstrapStageTrace or {}),
        lastSnapshotReconcileFailureStage = BridgeState.lastSnapshotReconcileFailureStage,
        lastSnapshotReconcileFailureReason = BridgeState.lastSnapshotReconcileFailureReason,
        snapshotPhysicalZoneOwnership = BridgeDiagnosticSnapshot(zoneOwnership),
        bootstrapLibraryMappings = BridgeDiagnosticSnapshot(libraryMapping),
        expectedLibraryMappings = aggregateExpected,
        verifiedLibraryMappings = aggregateVerified,
        missingLibraryMappings = aggregateMissing,
        duplicateLibraryMappings = aggregateDuplicate,
        unsettledGuidCount = aggregateUnsettled or 0,
        duplicateRealGuidCount = aggregateDuplicateReal or 0,
        firstBlockingObservation = BridgeState.firstBlockingObservation,
        firstActualFailure = BridgeState.firstActualFailure,
        currentObservedBlocker = BridgeState.currentObservedBlocker,
        lastSnapshotRepresentationFailure = BridgeDiagnosticSnapshot(BridgeState.lastSnapshotRepresentationFailure)
    }
end

function BridgeRecordEventDrainStall(state)
    local queueState = state or BridgeEventDrainQueueState()
    local watchdog = BridgeState.eventDrainWatchdog or {}
    watchdog.lastBlockReason = queueState.blockReason
    BridgeState.eventDrainWatchdog = watchdog
    if watchdog.logged then return end
    watchdog.logged = true
    BridgeLog(string.format(
        "[Bridge] EVENT_DRAIN_STALLED head=%s kind=%s source=%s destination=%s received=%s applied=%s queueLength=%s blockReason=%s animationRunning=%s physicalLibraryQueuesIdle=%s eventPolling=%s eventRequestInFlight=%s eventPollScheduled=%s snapshotPending=%s snapshotInFlight=%s desyncLatched=%s resyncInFlight=%s bootstrapping=%s physicalQueues=%s",
        tostring(queueState.headSequence), tostring(queueState.headKind),
        tostring(queueState.headSourceZone), tostring(queueState.headDestinationZone),
        tostring(queueState.lastReceived), tostring(queueState.lastApplied),
        tostring(queueState.queueLength), tostring(queueState.blockReason),
        tostring(queueState.animationRunning), tostring(queueState.physicalLibraryQueuesIdle),
        tostring(queueState.eventPolling), tostring(queueState.eventRequestInFlight),
        tostring(queueState.eventPollScheduled), tostring(queueState.snapshotReconcilePending),
        tostring(queueState.snapshotReconcileInFlight), tostring(queueState.desyncLatched),
        tostring(queueState.resyncInFlight), tostring(queueState.bootstrapping),
        JSON.encode(queueState.physicalQueues or {})))
end

function BridgeObserveEventDrainBlocked(reason)
    local queue = BridgeState.eventQueue or {}
    local head = queue[1]
    if head == nil then return end
    local now = os.clock()
    local watchdog = BridgeState.eventDrainWatchdog or {}
    local sameHead = watchdog.sessionId == BridgeState.eventSessionId
        and watchdog.sessionGeneration == BridgeState.eventSessionGeneration
        and watchdog.eventSequence == head.sequence
        and watchdog.lastAppliedEventSequence == BridgeState.lastAppliedEventSequence
    if not sameHead then
        watchdog = {
            sessionId = BridgeState.eventSessionId,
            sessionGeneration = BridgeState.eventSessionGeneration,
            eventSequence = head.sequence,
            lastAppliedEventSequence = BridgeState.lastAppliedEventSequence,
            blockedSince = now,
            lastBlockReason = reason,
            logged = false,
            scheduled = false
        }
        BridgeState.eventDrainWatchdog = watchdog
    else
        watchdog.lastBlockReason = reason
    end
    if not watchdog.scheduled then
        watchdog.scheduled = true
        local sessionId = watchdog.sessionId
        local sessionGeneration = watchdog.sessionGeneration
        local sequence = watchdog.eventSequence
        BridgeWaitTime(function()
            local current = BridgeState.eventDrainWatchdog
            if current == nil or current.eventSequence ~= sequence
                or current.sessionId ~= sessionId
                or current.sessionGeneration ~= sessionGeneration then return end
            current.scheduled = false
            local currentHead = (BridgeState.eventQueue or {})[1]
            local currentReason = BridgeEventDrainBlockReason()
            if currentHead ~= nil and currentHead.sequence == sequence
                and current.lastAppliedEventSequence == BridgeState.lastAppliedEventSequence
                and currentReason ~= "queue_empty" then
                if currentReason == "animationRunning" then
                    local tx = BridgeState.eventDrainTransaction
                    if tx ~= nil and BridgeEventMutationIsCurrent ~= nil
                        and BridgeCommitEventMutationTransaction ~= nil then
                        local txCurrentOk, txIsCurrent = pcall(BridgeEventMutationIsCurrent, tx)
                        local queueProbeOk, queuesIdle = pcall(function()
                            if BridgePhysicalMutationOperationsIdle ~= nil then
                                return BridgePhysicalMutationOperationsIdle()
                            end
                            return BridgePhysicalLibraryQueuesIdle()
                        end)
                        local mutationReadyOk, mutationReady = true, true
                        if BridgeMutationPhysicalBatchesReady ~= nil then
                            mutationReadyOk, mutationReady = pcall(function()
                                local ready = BridgeMutationPhysicalBatchesReady(tx)
                                return ready
                            end)
                        end
                        if txCurrentOk and txIsCurrent and queueProbeOk and queuesIdle
                            and mutationReadyOk and mutationReady then
                            local commitOk, commitResult = pcall(BridgeCommitEventMutationTransaction, tx)
                            if commitOk and commitResult then
                                BridgeLog(string.format(
                                    "[Bridge] EVENT_DRAIN_WATCHDOG_RECOVERY committed token=%s head=%s",
                                    tostring(tx.token), tostring(sequence)))
                                return
                            end
                            if not commitOk then
                                BridgeLog("[Bridge] EVENT_DRAIN_WATCHDOG_RECOVERY commit failed: "
                                    .. tostring(commitResult))
                            end
                        end
                    end
                end
                local observed = BridgeEventDrainQueueState()
                if currentReason == "none" then
                    -- The fence may have cleared between the blocked pump and
                    -- this watchdog frame. Preserve the fence that actually
                    -- caused the wait in the diagnostic record.
                    observed.blockReason = current.lastBlockReason or "cleared-before-watchdog"
                end
                BridgeRecordEventDrainStall(observed)
                if currentReason == "none" and not BridgeState.animationRunning then
                    -- The fence cleared without another caller entering the
                    -- pump. One state-aware retry repairs a lost scheduler
                    -- callback; it never skips or drops the queue head.
                    BridgeProcessEventQueue()
                end
            end
        end, BRIDGE_EVENT_DRAIN_STALL_SECONDS)
    end
end

-- Freeze-flight telemetry is deliberately local to this Lua runtime.  TTS's
-- documented Time.time member is the game-runtime clock; probe it because
-- MoonSharp-based test hosts and older/non-TTS runtimes may not expose Time.
-- Keep os.clock as the deterministic CPU-time fallback and label both clocks.
local BRIDGE_PERFORMANCE_CLOCK_KIND = "os.clock-cpu"
local BRIDGE_PERFORMANCE_WALL_CLOCK_KIND = "Time.time-game"
local BRIDGE_PERFORMANCE_WALL_CLOCK_FALLBACK_KIND = "os.clock-cpu-fallback"
local BRIDGE_PERFORMANCE_CLOCK_OK = pcall(function() return os.clock() end)

function BridgePerformanceNow()
    if BRIDGE_PERFORMANCE_CLOCK_OK then return os.clock() end
    return 0
end

function BridgePerformanceWallNow()
    local ok, value = pcall(function()
        if Time == nil then return nil end
        return Time.time
    end)
    if ok and type(value) == "number" then return value end
    return nil
end

function BridgePerformanceTrace(marker, durationMs, detail1, detail2, wallDurationMs, wallClockKind)
    local trace = BridgeState.performanceTrace
    if trace == nil then return end
    local decision = BridgeState.lastDecision
    local cpuDurationMs = durationMs ~= nil and tonumber(durationMs) or nil
    local record = {
        timestamp = BridgePerformanceNow(), marker = tostring(marker),
        decisionId = decision and decision.decisionId or nil,
        decisionKind = decision and decision.kind or nil,
        eventSequence = tonumber(BridgeState.lastAppliedEventSequence or 0) or 0,
        -- durationMs remains the CPU-time compatibility field for existing
        -- diagnostic consumers; the explicit fields remove that ambiguity.
        durationMs = cpuDurationMs,
        cpuDurationMs = cpuDurationMs,
        wallDurationMs = wallDurationMs ~= nil and tonumber(wallDurationMs) or nil,
        wallClockKind = wallClockKind or BRIDGE_PERFORMANCE_WALL_CLOCK_KIND,
        detail1 = detail1 ~= nil and tonumber(detail1) or nil,
        detail2 = detail2 ~= nil and tonumber(detail2) or nil
    }
    trace.head = (trace.head % trace.capacity) + 1
    trace.records[trace.head] = record
    trace.count = math.min(trace.count + 1, trace.capacity)
end

function BridgePerformanceBegin(marker, detail1, detail2)
    BridgePerformanceTrace(marker, nil, detail1, detail2)
    return {
        marker = tostring(marker),
        startedAt = BridgePerformanceNow(),
        wallStartedAt = BridgePerformanceWallNow(),
        wallClockKind = BRIDGE_PERFORMANCE_WALL_CLOCK_KIND
    }
end

function BridgePerformanceEnd(token, marker, summaryKey, detail1, detail2)
    if token == nil then return end
    local cpuDurationMs = math.max(0, (BridgePerformanceNow() - (token.startedAt or 0)) * 1000)
    local wallDurationMs = nil
    local wallClockKind = token.wallClockKind or BRIDGE_PERFORMANCE_WALL_CLOCK_KIND
    if token.wallStartedAt ~= nil then
        local wallNow = BridgePerformanceWallNow()
        if wallNow ~= nil and wallNow >= token.wallStartedAt then
            wallDurationMs = (wallNow - token.wallStartedAt) * 1000
        end
    end
    if wallDurationMs == nil then
        wallDurationMs = cpuDurationMs
        wallClockKind = BRIDGE_PERFORMANCE_WALL_CLOCK_FALLBACK_KIND
    end
    token.cpuDurationMs = cpuDurationMs
    token.wallDurationMs = wallDurationMs
    token.wallClockKind = wallClockKind
    BridgePerformanceTrace(marker, cpuDurationMs, detail1, detail2, wallDurationMs, wallClockKind)
    local summary = BridgeState.performanceSummary
    if summary == nil then return end
    if summaryKey ~= nil then
        local worstKey = "worst" .. string.upper(string.sub(summaryKey, 1, 1)) .. string.sub(summaryKey, 2) .. "DurationMs"
        if cpuDurationMs > tonumber(summary[worstKey] or 0) then summary[worstKey] = cpuDurationMs end
    end
    if summaryKey ~= nil and cpuDurationMs >= BRIDGE_PERFORMANCE_SLOW_OPERATION_SECONDS * 1000 then
        summary.slowRenderCount = (summary.slowRenderCount or 0) + 1
    end
    return cpuDurationMs
end

function BridgeStartupStageBegin(marker)
    return BridgePerformanceBegin(marker)
end

function BridgeStartupStageEnd(token, marker, summaryField)
    local durationMs = BridgePerformanceEnd(token, marker)
    local startup = BridgeState.startupTrace
    if startup ~= nil and summaryField ~= nil and durationMs ~= nil then
        startup[summaryField] = durationMs
    end
    return durationMs
end

function BridgeLogStartupSummary()
    local startup = BridgeState.startupTrace
    if startup == nil or startup.summaryLogged == true then return end
    startup.summaryLogged = true
    BridgeLog(string.format(
        "[Bridge perf] startup observable=%.0fms cleanup=%.0fms ui=%.0fms discovery=%.0fms dispatch=%.0fms",
        tonumber(startup.observableDurationMs or 0),
        tonumber(startup.transientCleanupDurationMs or 0),
        tonumber(startup.uiDurationMs or 0),
        tonumber(startup.objectDiscoveryDurationMs or 0),
        tonumber(startup.healthDispatchDurationMs or 0)))
end

function BridgePerformanceTraceSnapshot()
    local trace = BridgeState.performanceTrace or {capacity = BRIDGE_PERFORMANCE_TRACE_CAPACITY, head = 0, count = 0, records = {}}
    local result = {}
    local first = trace.count == trace.capacity and (trace.head % trace.capacity) + 1 or 1
    for offset = 0, trace.count - 1 do
        local index = ((first + offset - 1) % trace.capacity) + 1
        if trace.records[index] ~= nil then table.insert(result, trace.records[index]) end
    end
    return result
end

-- P10: Recovery state invariants check
-- Detect impossible states: recovery needed but no owner, or recovery orphaned
function BridgeComputeRecoveryStateInvariants()
    local result = {
        status = "PASS",
        violations = {},
        desyncLatched = BridgeState.desyncLatched,
        resyncInFlight = BridgeState.sessionRecoveryInFlight,
        eventPolling = BridgeState.eventPolling,
        eventQueueLength = BridgeState.eventQueue and #(BridgeState.eventQueue) or 0,
        eventCursor = BridgeState.lastAppliedEventSequence,
        handReadinessRecoveryAttempts = BridgeState.handReadinessRecoveryAttempts or 0
    }
    
    -- P10: ORPHANED_PHYSICAL_RECOVERY
    -- Recovery is needed (desyncLatched=true) but no active recovery (resyncInFlight=false)
    -- AND there is pending event work (eventQueueLength > 0)
    if result.desyncLatched and not result.resyncInFlight and result.eventQueueLength > 0 then
        table.insert(result.violations, "ORPHANED_PHYSICAL_RECOVERY: desyncLatched=true but no recovery owner, with " .. result.eventQueueLength .. " events queued")
        result.status = "CRITICAL"
    end
    
    -- P10: STRANDED_EVENT_BACKLOG
    -- Events are queued but neither applied nor being processed
    if result.eventQueueLength > 0 and not result.eventPolling and not result.resyncInFlight then
        table.insert(result.violations, "STRANDED_EVENT_BACKLOG: " .. result.eventQueueLength .. " events queued but no consumer")
        result.status = "CRITICAL"
    end
    
    -- P10: RECOVERY_DEFERRED_WITHOUT_OWNER
    -- Recovery was attempted but exited early without taking ownership
    if BridgeState.resyncDeferredRetryScheduled and not result.resyncInFlight then
        table.insert(result.violations, "RECOVERY_DEFERRED_WITHOUT_OWNER: recovery scheduled but no active owner")
        result.status = "CRITICAL"
    end
    
    return result
end

function BridgeDiagnosticSnapshot(value, active)
    if type(value) ~= "table" then return value end
    active = active or {}
    if active[value] then return "<diagnostic-cycle>" end
    active[value] = true
    local copy = {}
    for key, item in pairs(value) do
        local copiedKey = type(key) == "table" and tostring(key) or key
        copy[copiedKey] = BridgeDiagnosticSnapshot(item, active)
    end
    active[value] = nil
    return copy
end

-- ============================================================
-- H0 EMBODIMENT RECONCILIATION OWNERSHIP
--
-- One update-driven transaction owns correctness-critical snapshot physics.
-- Native callbacks are hints; the pump advances only from observed physical
-- postconditions.  Legacy materializers remain operation adapters until event
-- mutations migrate onto the same desired-zone interface.
-- ============================================================

function BridgeEmbodimentJournal(tx, phase, operationType, detail)
    if tx == nil then return end
    if operationType ~= nil and string.find(tostring(operationType), "REPLAN", 1, true) ~= nil then
        BridgeStartupPerfCounter("embodimentReplanCount", 1)
    end
    local record = {
        runtimeEpoch = tx.runtimeEpoch,
        embodimentEpoch = tx.epoch,
        token = tx.token,
        reason = tx.reason,
        sessionId = tx.targetSessionId,
        targetCursor = tx.targetCursor,
        phase = phase or tx.phase,
        operationIndex = tx.operationIndex or 0,
        operationType = operationType,
        operationToken = tx.currentOperation and tx.currentOperation.token or nil,
        precondition = tx.currentOperation and tx.currentOperation.precondition or nil,
        nativeAction = tx.currentOperation and tx.currentOperation.nativeAction or nil,
        postcondition = tx.currentOperation and tx.currentOperation.postcondition or nil,
        detail = detail ~= nil and tostring(detail) or nil,
        updateTick = tonumber(BridgeState.updateTick or 0) or 0,
        lastProgressUpdateTick = tx.lastProgressUpdateTick,
        replanCount = tx.replanCount or 0,
        lastBlockingPredicate = tx.lastBlockingPredicate,
        firstBlockingObservation = tx.firstBlockingObservation,
        firstActualFailure = tx.firstActualFailure,
        currentObservedBlocker = tx.currentObservedBlocker
    }
    BridgeState.embodimentJournal = BridgeState.embodimentJournal or {}
    table.insert(BridgeState.embodimentJournal, record)
    while #BridgeState.embodimentJournal > BRIDGE_EMBODIMENT_JOURNAL_CAPACITY do
        table.remove(BridgeState.embodimentJournal, 1)
    end
end

function BridgeEmbodimentRecordBlockingObservation(tx, detail)
    local value = detail ~= nil and tostring(detail) or nil
    if value == nil or value == "" then return end
    if tx ~= nil then
        tx.firstBlockingObservation = tx.firstBlockingObservation or value
        tx.currentObservedBlocker = value
    end
    BridgeState.firstBlockingObservation = BridgeState.firstBlockingObservation or value
    BridgeState.currentObservedBlocker = value
end

function BridgeEmbodimentRecordActualFailure(tx, detail)
    local value = detail ~= nil and tostring(detail) or nil
    if value == nil or value == "" then return end
    if tx ~= nil then tx.firstActualFailure = tx.firstActualFailure or value end
    BridgeState.firstActualFailure = BridgeState.firstActualFailure or value
end

function BridgeEmbodimentTransactionIsCurrent(tx)
    return tx ~= nil and BridgeState.embodimentTransaction == tx
        and tx.runtimeEpoch == BRIDGE_RUNTIME_EPOCH_LOCAL
        and tx.epoch == BridgeState.embodimentEpoch
        and tx.token == BridgeState.embodimentTransactionToken
end

function BridgeCapturePhysicalLedger()
    return {
        physicalByInstanceId = BridgeDiagnosticSnapshot(BridgeState.physicalByInstanceId or {}),
        physicalInstanceIdByGuid = BridgeDiagnosticSnapshot(BridgeState.physicalInstanceIdByGuid or {}),
        physicalSeatByGuid = BridgeDiagnosticSnapshot(BridgeState.physicalSeatByGuid or {}),
        physicalZoneByGuid = BridgeDiagnosticSnapshot(BridgeState.physicalZoneByGuid or {}),
        physicalContainerByInstanceId = BridgeDiagnosticSnapshot(BridgeState.physicalContainerByInstanceId or {}),
        physicalContainedInstanceIdByGuid = BridgeDiagnosticSnapshot(BridgeState.physicalContainedInstanceIdByGuid or {}),
        physicalSlotByInstanceId = BridgeDiagnosticSnapshot(BridgeState.physicalSlotByInstanceId or {})
    }
end

function BridgeActivatePhysicalLedger(ledger)
    if ledger == nil then return false end
    BridgeState.physicalByInstanceId = ledger.physicalByInstanceId
    BridgeState.physicalInstanceIdByGuid = ledger.physicalInstanceIdByGuid
    BridgeState.physicalSeatByGuid = ledger.physicalSeatByGuid
    BridgeState.physicalZoneByGuid = ledger.physicalZoneByGuid
    BridgeState.physicalContainerByInstanceId = ledger.physicalContainerByInstanceId
    BridgeState.physicalContainedInstanceIdByGuid = ledger.physicalContainedInstanceIdByGuid
    BridgeState.physicalSlotByInstanceId = ledger.physicalSlotByInstanceId or {}
    return true
end

function BridgeAdvanceEmbodimentEpoch(reason)
    local prior = BridgeState.embodimentTransaction
    if prior ~= nil and prior.committedPhysicalLedger ~= nil then
        BridgeActivatePhysicalLedger(prior.committedPhysicalLedger)
    end
    BridgeState.embodimentEpoch = (BridgeState.embodimentEpoch or 0) + 1
    BridgeState.embodimentTransactionToken = (BridgeState.embodimentTransactionToken or 0) + 1
    BridgeState.embodimentTransaction = nil
    if prior ~= nil then BridgeEmbodimentJournal(prior, "ABORT", "EPOCH_REPLACED", reason) end
    BridgeLog("[Bridge] EMBODIMENT_EPOCH_ADVANCED epoch=" .. tostring(BridgeState.embodimentEpoch)
        .. " reason=" .. tostring(reason or "unspecified"))
    return BridgeState.embodimentEpoch
end

function BridgeObserveObjectPhysicalZone(object, handSeatId)
    if handSeatId ~= nil then return handSeatId, "hand" end
    if BridgeObjectNearSeatZone == nil then return nil, nil end
    for seatId, _ in pairs(BRIDGE_SEATS or {}) do
        for _, zoneName in ipairs({"library", "graveyard", "exile", "battlefield", "stack"}) do
            local ok, near = pcall(function() return BridgeObjectNearSeatZone(object, seatId, zoneName) end)
            if ok and near == true then return seatId, zoneName end
        end
    end
    return nil, nil
end

function BridgeBuildDesiredPhysicalState(snapshot)
    if snapshot == nil then return nil end
    local desired = {
        sessionId = snapshot.sessionId,
        cursor = tonumber(snapshot.eventCursor or 0) or 0,
        forgeSequence = snapshot.forgeSequence,
        cardsByInstanceId = {}, zonesBySeat = {}
    }
    for _, seatSnapshot in ipairs(snapshot.seats or {}) do
        local seatId = seatSnapshot.seatId
        desired.zonesBySeat[seatId] = desired.zonesBySeat[seatId] or {}
        for _, zone in ipairs(seatSnapshot.zones or {}) do
            local zoneName = string.lower(tostring(zone.name or ""))
            local zoneState = {seatId = seatId, zone = zoneName, instanceIds = {}, count = 0}
            for _, card in ipairs(zone.cards or {}) do
                local instanceId = card.cardInstanceId and tostring(card.cardInstanceId) or nil
                if instanceId ~= nil and card.isVirtual ~= true
                    and tostring(card.materializationPolicy or "") ~= "virtual"
                    and tostring(card.materializationPolicy or "") ~= "virtual-stack" then
                    zoneState.count = zoneState.count + 1
                    zoneState.instanceIds[instanceId] = true
                    desired.cardsByInstanceId[instanceId] = {
                        cardInstanceId = instanceId,
                        seatId = seatId,
                        zone = zoneName,
                        private = zoneName == "hand" or zoneName == "library",
                        tapped = card.tapped == true,
                        faceDown = card.faceDown == true,
                        controllerSeatId = card.controllerSeatId or seatId
                    }
                end
            end
            zoneState.topology = zoneState.count == 0 and "EMPTY"
                or (zoneState.count == 1 and "CARD" or "DECK")
            desired.zonesBySeat[seatId][zoneName] = zoneState
        end
    end
    return desired
end

function BridgeObservePhysicalState(desired)
    local observed = {
        objects = {}, byInstanceId = {}, byGuid = {}, duplicateInstanceIds = {},
        unsettledContainedEntries = {}, handsBySeat = {}, zones = {}
    }
    local handSeatByGuid = {}
    local function addObserved(entry)
        if entry == nil or entry.guid == nil then return end
        local existingByGuid = observed.byGuid[entry.guid]
        if existingByGuid ~= nil then
            -- A hand object can also be present in getAllObjects. Merge the
            -- enumeration evidence by physical GUID instead of creating a
            -- duplicate physical observation.
            existingByGuid.handSeatId = existingByGuid.handSeatId or entry.handSeatId
            existingByGuid.seatId = existingByGuid.seatId or entry.seatId
            existingByGuid.zone = existingByGuid.zone or entry.zone
            if existingByGuid.instanceId == nil then existingByGuid.instanceId = entry.instanceId end
            if existingByGuid.sessionId == nil then existingByGuid.sessionId = entry.sessionId end
            if entry.contained ~= nil then
                for _, contained in ipairs(entry.contained) do table.insert(existingByGuid.contained, contained) end
            end
            return existingByGuid
        end
        observed.byGuid[entry.guid] = entry
        table.insert(observed.objects, entry)
        if entry.instanceId ~= nil and (entry.sessionId == nil
            or desired == nil or tostring(entry.sessionId) == tostring(desired.sessionId)) then
            if observed.byInstanceId[entry.instanceId] ~= nil
                and observed.byInstanceId[entry.instanceId].guid ~= entry.guid then
                observed.duplicateInstanceIds[entry.instanceId] = true
            else
                observed.byInstanceId[entry.instanceId] = entry
            end
        end
        return entry
    end
    for seatId, _ in pairs(BRIDGE_SEATS or {}) do
        local hands = BridgeTryGetSeatHandObjects ~= nil and BridgeTryGetSeatHandObjects(seatId) or {}
        observed.handsBySeat[seatId] = {}
        for _, object in ipairs(hands or {}) do
            local guid = BridgeSafeObjectGuid ~= nil and BridgeSafeObjectGuid(object) or nil
            if guid ~= nil then
                observed.handsBySeat[seatId][guid] = true
                handSeatByGuid[guid] = seatId
                if object.tag == "Card" then
                    local entry = {
                        guid = guid, tag = "Card", handSeatId = seatId,
                        seatId = seatId, zone = "hand", contained = {},
                        instanceId = BridgeReadPhysicalIdentity ~= nil and BridgeReadPhysicalIdentity(object) or nil,
                        sessionId = BridgeReadPhysicalSessionIdentity ~= nil and BridgeReadPhysicalSessionIdentity(object) or nil
                    }
                    addObserved(entry)
                end
            end
        end
    end
    local objects = type(getAllObjects) == "function" and (getAllObjects() or {}) or {}
    for _, object in ipairs(objects) do
        if object ~= nil and (object.tag == "Card" or object.tag == "Deck") then
            local guid = BridgeSafeObjectGuid ~= nil and BridgeSafeObjectGuid(object) or nil
            if guid ~= nil then
                local entry = {guid = guid, tag = object.tag, handSeatId = handSeatByGuid[guid], contained = {}}
                entry.seatId, entry.zone = BridgeObserveObjectPhysicalZone(object, entry.handSeatId)
                if object.tag == "Card" then
                    entry.instanceId = BridgeReadPhysicalIdentity ~= nil and BridgeReadPhysicalIdentity(object) or nil
                    entry.sessionId = BridgeReadPhysicalSessionIdentity ~= nil and BridgeReadPhysicalSessionIdentity(object) or nil
                else
                    local ok, contained = pcall(function() return object.getObjects() or {} end)
                    if ok then
                        for _, native in ipairs(contained) do
                            local containedGuid = native.guid or native.GUID
                            local instanceId = containedGuid and BridgeState.physicalContainedInstanceIdByGuid[containedGuid] or nil
                            local containedEntry = {guid = containedGuid, deckGuid = guid, instanceId = instanceId,
                                seatId = entry.seatId, zone = entry.zone}
                            if containedGuid == nil or string.match(tostring(containedGuid), "%S") == nil then
                                table.insert(observed.unsettledContainedEntries, {
                                    deckGuid = guid, index = native.index, seatId = entry.seatId, zone = entry.zone
                                })
                            end
                            table.insert(entry.contained, containedEntry)
                            if instanceId ~= nil and observed.byInstanceId[instanceId] == nil then
                                observed.byInstanceId[instanceId] = containedEntry
                            elseif instanceId ~= nil then
                                observed.duplicateInstanceIds[instanceId] = true
                            end
                        end
                    end
                end
                addObserved(entry)
            end
        end
    end
    return observed
end

function BridgePlanEmbodimentReconciliation(desired, observed)
    local plan = {operations = {}, affectedZones = {}, missing = {}, misplaced = {}, ambiguous = {}, unsettledZones = {}}
    if desired == nil then
        table.insert(plan.operations, {type = "FETCH_AND_RECONCILE_SNAPSHOT",
            precondition = "one current embodiment owner",
            nativeAction = "BridgeLegacyBootstrapCurrentSnapshot",
            postcondition = "authoritative snapshot fully verified"})
        return plan
    end
    for instanceId, _ in pairs(observed.duplicateInstanceIds or {}) do table.insert(plan.ambiguous, instanceId) end
    local unsettledByZone = {}
    for _, entry in ipairs(observed.unsettledContainedEntries or {}) do
        local key = tostring(entry.seatId or "") .. ":" .. tostring(entry.zone or "library")
        unsettledByZone[key] = true
        plan.unsettledZones[key] = "PRESENT_BUT_UNSETTLED"
        plan.affectedZones[key] = true
    end
    for instanceId, card in pairs(desired.cardsByInstanceId or {}) do
        local physical = (observed.byInstanceId or {})[instanceId]
        if physical == nil then
            local key = tostring(card.seatId or "") .. ":" .. tostring(card.zone or "")
            plan.affectedZones[key] = true
            if not (card.zone == "library" and unsettledByZone[key]) then
                table.insert(plan.missing, instanceId)
            end
        elseif tostring(physical.zone or "") ~= tostring(card.zone)
            or tostring(physical.seatId or "") ~= tostring(card.seatId) then
            table.insert(plan.misplaced, instanceId)
            plan.affectedZones[card.seatId .. ":" .. card.zone] = true
        end
    end
    if #plan.ambiguous > 0 then
        plan.blockingPredicate = "duplicate exact physical identity"
    elseif #plan.missing > 0 or #plan.misplaced > 0 or next(plan.unsettledZones) ~= nil then
        local localZones = {}
        local zoneSource = next(unsettledByZone) ~= nil and unsettledByZone or plan.affectedZones
        for key in pairs(zoneSource) do
            local separator = string.find(key, ":", 1, true)
            local seatId = separator and string.sub(key, 1, separator - 1) or key
            local zone = separator and string.sub(key, separator + 1) or ""
            if zone == "library" or zone == "hand" then
                table.insert(localZones, {seatId = seatId, zone = zone})
            end
        end
        table.sort(localZones, function(left, right)
            return tostring(left.seatId) .. tostring(left.zone) < tostring(right.seatId) .. tostring(right.zone)
        end)
        for _, localZone in ipairs(localZones) do
            table.insert(plan.operations, {
                type = localZone.zone == "library" and "REOBSERVE_SEAT_LIBRARY" or "REOBSERVE_SEAT_HAND",
                scope = localZone.zone == "library" and "SEAT_LIBRARY" or "SEAT_HAND",
                seatId = localZone.seatId, zone = localZone.zone,
                precondition = "unambiguous seat-local physical evidence",
                nativeAction = localZone.zone == "library" and "BridgeBindLibraryMappingsForSnapshot" or "BridgeObserveSeatHand",
                postcondition = "selected seat zone exact state verified"})
        end
        if #localZones == 0 then
            table.insert(plan.operations, {type = "RECONCILE_SNAPSHOT_ZONES", scope = "GLOBAL_SNAPSHOT",
                precondition = "unambiguous desired and observed exact identities",
                nativeAction = "BridgeLegacyBootstrapCurrentSnapshot",
                postcondition = "desired exact identity/zone state verified"})
        end
    end
    return plan
end

function BridgeAssignEmbodimentOperationTokens(tx)
    for index, operation in ipairs(tx.plan and tx.plan.operations or {}) do
        operation.index = index
        operation.token = table.concat({tostring(tx.epoch), tostring(tx.token), tostring(tx.replanCount or 0), tostring(index)}, ":")
        operation.runtimeEpoch = tx.runtimeEpoch
        operation.embodimentEpoch = tx.epoch
        operation.transactionToken = tx.token
        operation.scope = operation.scope or "GLOBAL_SNAPSHOT"
        operation.seatId = operation.seatId or nil
        operation.zone = operation.zone or nil
    end
end

-- Generic affected-zone seam for the next gameplay/mill migration. A same-
-- forgeSequence mutation can supply multiple desired zones and receive one
-- plan/verify boundary without creating card-specific synchronization code.
function BridgeBuildDesiredZoneState(snapshot, seatId, zoneName)
    local desired = BridgeBuildDesiredPhysicalState(snapshot)
    return desired and desired.zonesBySeat[seatId]
        and desired.zonesBySeat[seatId][string.lower(tostring(zoneName or ""))] or nil
end

function BridgeObserveZoneState(desiredZone, observed)
    observed = observed or BridgeObservePhysicalState(nil)
    local result = {seatId = desiredZone and desiredZone.seatId or nil,
        zone = desiredZone and desiredZone.zone or nil, instanceIds = {}, count = 0}
    for instanceId, entry in pairs(observed.byInstanceId or {}) do
        if desiredZone ~= nil
            and tostring(entry.seatId or "") == tostring(desiredZone.seatId or "")
            and tostring(entry.zone or "") == tostring(desiredZone.zone or "") then
            result.instanceIds[instanceId] = true
            result.count = result.count + 1
        end
    end
    result.topology = result.count == 0 and "EMPTY" or (result.count == 1 and "CARD" or "DECK")
    return result
end

function BridgePlanZoneReconciliation(desiredZone, observedZone)
    local plan = {operations = {}, exact = true}
    for instanceId in pairs(desiredZone and desiredZone.instanceIds or {}) do
        if observedZone == nil or observedZone.instanceIds[instanceId] ~= true then
            plan.exact = false
            table.insert(plan.operations, {type = "MATERIALIZE_EXACT_INSTANCE", cardInstanceId = instanceId,
                destinationSeatId = desiredZone.seatId, destinationZone = desiredZone.zone,
                precondition = "exact instance has one physical source",
                nativeAction = "materialize-or-move-exact-instance",
                postcondition = "exact instance observed in desired zone"})
        end
    end
    if observedZone ~= nil and observedZone.count ~= (desiredZone and desiredZone.count or 0) then
        plan.exact = false
        table.insert(plan.operations, {type = "NORMALIZE_ZONE_TOPOLOGY",
            destinationSeatId = desiredZone and desiredZone.seatId or nil,
            destinationZone = desiredZone and desiredZone.zone or nil,
            expectedTopology = desiredZone and desiredZone.topology or "EMPTY",
            precondition = "zone exact identities are unambiguous",
            nativeAction = "normalize-native-card-deck-topology",
            postcondition = "native topology and exact count match desired zone"})
    end
    return plan
end

function BridgeEmbodimentSetSnapshot(tx, snapshot)
    if not BridgeEmbodimentTransactionIsCurrent(tx) then return false end
    tx.snapshot = snapshot
    tx.targetSessionId = snapshot and snapshot.sessionId or tx.targetSessionId
    tx.targetCursor = snapshot and tonumber(snapshot.eventCursor or 0) or tx.targetCursor
    tx.targetForgeSequence = snapshot and snapshot.forgeSequence or tx.targetForgeSequence
    tx.desiredState = BridgeBuildDesiredPhysicalState(snapshot)
    tx.lastProgressUpdateTick = tonumber(BridgeState.updateTick or 0) or 0
    BridgeEmbodimentJournal(tx, tx.phase, "SNAPSHOT_OBSERVED", "cursor=" .. tostring(tx.targetCursor))
    return true
end

function BridgeFinishEmbodimentTransaction(tx, ok, errorMessage)
    if not BridgeEmbodimentTransactionIsCurrent(tx) then return false end
    tx.phase = ok and "COMMITTED" or "ABORTED"
    tx.commitResult = ok == true
    tx.lastBlockingPredicate = errorMessage or tx.lastBlockingPredicate
    BridgeEmbodimentJournal(tx, tx.phase, ok and "COMMIT" or "ABORT", errorMessage)
    if ok then
        tx.candidatePhysicalLedger = BridgeCapturePhysicalLedger()
        BridgeState.committedPhysicalLedger = tx.candidatePhysicalLedger
    elseif tx.committedPhysicalLedger ~= nil then
        -- This restores only the last committed logical publication. It does
        -- not claim physics rolled back: tx.observedState remains the durable
        -- account of current TTS reality and the next plan reobserves the table.
        BridgeActivatePhysicalLedger(tx.committedPhysicalLedger)
    end
    BridgeState.lastEmbodimentTransaction = BridgeDiagnosticSnapshot(tx)
    BridgeState.embodimentTransaction = nil
    -- Retire every callback belonging to the operation adapter. Physics is
    -- already observed; only callback ownership is discarded.
    BridgeState.resyncBootstrapGeneration = (BridgeState.resyncBootstrapGeneration or 0) + 1
    BridgeState.bootstrapping = false
    local callback = tx.callback
    if callback ~= nil then callback(ok, errorMessage) end
    return true
end

function BridgeBeginEmbodimentTransaction(sessionId, reason, resumeFromSnapshotCursor, callback)
    local current = BridgeState.embodimentTransaction
    if current ~= nil and BridgeEmbodimentTransactionIsCurrent(current) then
        if current.reason == reason and current.targetSessionId == sessionId then return current, false end
        return nil, false
    end
    BridgeState.embodimentTransactionToken = (BridgeState.embodimentTransactionToken or 0) + 1
    local tx = {
        runtimeEpoch = BRIDGE_RUNTIME_EPOCH_LOCAL,
        epoch = BridgeState.embodimentEpoch or 1,
        token = BridgeState.embodimentTransactionToken,
        reason = reason or "snapshot-bootstrap",
        targetSessionId = sessionId,
        targetCursor = nil,
        targetForgeSequence = nil,
        phase = "OBSERVE",
        operationIndex = 0,
        operationAttempt = 0,
        operationStarted = false,
        lastProgressUpdateTick = tonumber(BridgeState.updateTick or 0) or 0,
        replanCount = 0,
        firstBlockingObservation = nil,
        firstActualFailure = nil,
        currentObservedBlocker = nil,
        resumeFromSnapshotCursor = resumeFromSnapshotCursor == true,
        callback = callback
    }
    tx.committedPhysicalLedger = BridgeState.committedPhysicalLedger ~= nil
        and BridgeDiagnosticSnapshot(BridgeState.committedPhysicalLedger) or BridgeCapturePhysicalLedger()
    tx.candidatePhysicalLedger = BridgeDiagnosticSnapshot(tx.committedPhysicalLedger)
    BridgeActivatePhysicalLedger(tx.candidatePhysicalLedger)
    BridgeState.embodimentTransaction = tx
    BridgeStartupPerfEvent("embodiment-transaction-begin",
        "reason=" .. tostring(tx.reason) .. " session=" .. tostring(sessionId))
    BridgeEmbodimentJournal(tx, "OBSERVE", "BEGIN", nil)
    return tx, true
end

function BridgeBeginNewMatchCleanupTransaction(callback)
    local tx, started = BridgeBeginEmbodimentTransaction(
        BridgeState.eventSessionId, "new-match-cleanup", false, callback)
    if tx ~= nil and started then
        tx.kind = "NEW_MATCH_CLEANUP"
        tx.phase = "APPLY"
        tx.operationStarted = false
        tx.cleanupAttempted = false
        BridgeEmbodimentJournal(tx, "APPLY", "CONVERGE_OLD_CARDS_TO_LIBRARIES", nil)
    end
    return tx, started
end

function BridgeNewMatchCleanupPhysicalReady()
    local libraryGuids = {}
    for seatId, _ in pairs(BRIDGE_SEATS or {}) do
        local library = BridgeResolveSeatLibraryDeck ~= nil and BridgeResolveSeatLibraryDeck(seatId) or nil
        local libraryGuid = BridgeSafeObjectGuid ~= nil and BridgeSafeObjectGuid(library) or nil
        if libraryGuid ~= nil then libraryGuids[libraryGuid] = true end
    end
    local objects = type(getAllObjects) == "function" and (getAllObjects() or {}) or {}
    for _, object in ipairs(objects) do
        if object ~= nil and object.tag == "Card" and not BridgeIsPresentationOnlyObject(object) then
            local guid = BridgeSafeObjectGuid(object)
            local advertised = BridgeReadPhysicalIdentity(object)
            local trackedZone = guid and BridgeState.physicalZoneByGuid[guid] or nil
            if libraryGuids[guid] ~= true
                and (advertised ~= nil or (trackedZone ~= nil and trackedZone ~= "library")) then
                return false, "previous-game loose Card remains outside a native library"
            end
        end
    end
    for seatId, _ in pairs(BRIDGE_SEATS or {}) do
        local hands = BridgeTryGetSeatHandObjects(seatId)
        if hands ~= nil and #hands > 0 then return false, "previous-game hand is not empty" end
    end
    return true, nil
end

function BridgePumpNewMatchCleanupTransaction(tx, updateTick)
    local ready, readyError = false, "cleanup operation has not observed the old table yet"
    if tx.cleanupAttempted then
        ready, readyError = BridgeNewMatchCleanupPhysicalReady()
        if ready then return BridgeFinishEmbodimentTransaction(tx, true, nil) end
    end
    tx.lastBlockingPredicate = readyError
    if not tx.operationStarted then
        tx.operationStarted = true
        tx.operationAttempt = (tx.operationAttempt or 0) + 1
        tx.lastProgressUpdateTick = updateTick
        local attempt = tx.operationAttempt
        -- From the next update onward, physical observation—not callback
        -- delivery—may prove cleanup complete.
        tx.cleanupAttempted = true
        BridgeEmbodimentJournal(tx, "APPLY", "RETURN_PREVIOUS_GAME_CARDS", "attempt=" .. tostring(attempt))
        BridgeReturnPreviousGameCardsToLibraries(function(ok, err)
            if not BridgeEmbodimentTransactionIsCurrent(tx) or tx.operationAttempt ~= attempt then return end
            tx.operationStarted = false
            tx.cleanupAttempted = true
            if ok then
                tx.lastProgressUpdateTick = tonumber(BridgeState.updateTick or 0) or 0
                BridgeEmbodimentJournal(tx, "SETTLE", "CLEANUP_CALLBACK", nil)
            else
                tx.replanCount = (tx.replanCount or 0) + 1
                tx.lastBlockingPredicate = tostring(err or "cleanup operation failed")
                BridgeEmbodimentJournal(tx, "OBSERVE", "CLEANUP_REPLAN", tx.lastBlockingPredicate)
            end
        end)
    elseif updateTick - (tx.lastProgressUpdateTick or updateTick) >= BRIDGE_EMBODIMENT_REOBSERVE_FRAMES then
        tx.operationStarted = false
        tx.operationAttempt = tx.operationAttempt + 1
        -- The callback is only a notification. Reobserve before deciding
        -- whether the already-issued native actions need another plan.
        tx.cleanupAttempted = true
        tx.replanCount = (tx.replanCount or 0) + 1
        tx.lastProgressUpdateTick = updateTick
        BridgeEmbodimentJournal(tx, "OBSERVE", "CLEANUP_CALLBACK_LOST_REPLAN", readyError)
    end
    if (tx.replanCount or 0) > BRIDGE_EMBODIMENT_MAX_REPLANS then
        return BridgeFinishEmbodimentTransaction(tx, false,
            "NEW MATCH physical cleanup could not converge: " .. tostring(tx.lastBlockingPredicate))
    end
    return true
end

function BridgeEmbodimentOperationCallback(tx, attempt, ok, errorMessage, snapshot, outcome)
    if not BridgeEmbodimentTransactionIsCurrent(tx) or tx.operationAttempt ~= attempt then return false end
    if snapshot ~= nil then BridgeEmbodimentSetSnapshot(tx, snapshot) end
    tx.operationStarted = false
    tx.lastProgressUpdateTick = tonumber(BridgeState.updateTick or 0) or 0
    if outcome ~= nil and outcome.status == "WAITING_FOR_PHYSICAL_SETTLEMENT" then
        tx.waitingForPhysicalSettlement = true
        tx.phase = "OBSERVE"
        BridgeEmbodimentRecordBlockingObservation(tx, outcome.reason or "physical settlement pending")
        BridgeEmbodimentJournal(tx, "OBSERVE", "WAITING_FOR_PHYSICAL_SETTLEMENT", nil)
        return true
    end
    if ok then
        tx.phase = "SETTLE"
        BridgeEmbodimentJournal(tx, "SETTLE", "LEGACY_ADAPTER_RETURNED", nil)
    else
        tx.lastBlockingPredicate = tostring(errorMessage or "physical operation failed")
        BridgeEmbodimentRecordActualFailure(tx, tx.lastBlockingPredicate)
        if tx.snapshot == nil then
            -- No authoritative target was obtained, so there is nothing safe
            -- to replan toward. Transport/session failure is immediately
            -- actionable rather than a physical convergence retry.
            return BridgeFinishEmbodimentTransaction(tx, false, tx.lastBlockingPredicate)
        end
        tx.replanCount = (tx.replanCount or 0) + 1
        tx.phase = "OBSERVE"
        BridgeEmbodimentJournal(tx, "OBSERVE", "OPERATION_FAILED_REOBSERVE", tx.lastBlockingPredicate)
    end
    return true
end

-- Deterministic fault injection is inert unless a test explicitly configures
-- it. It exercises ownership/correlation, while TTS object fakes model GUID
-- churn, async Deck promotion, hand lag, and auto-stacking at the native edge.
function BridgeConfigureEmbodimentFaultInjection(faults)
    BridgeState.embodimentFaultInjection = faults or {}
    BridgeState.embodimentDelayedCallbacks = {}
end

function BridgeDeliverEmbodimentOperationCallback(tx, attempt, ok, errorMessage, snapshot, callbackKind, outcome)
    local faults = BridgeState.embodimentFaultInjection or {}
    local kind = callbackKind or "operation"
    if faults.dropCallback == kind or faults.dropNextCallback == true then
        faults.dropNextCallback = false
        return false
    end
    local deliver = function() BridgeEmbodimentOperationCallback(tx, attempt, ok, errorMessage, snapshot, outcome) end
    if faults.delayCallback == kind then
        table.insert(BridgeState.embodimentDelayedCallbacks, deliver)
        return false
    end
    deliver()
    if faults.duplicateCallback == kind then deliver() end
    return true
end

function BridgeReleaseEmbodimentDelayedCallbacks()
    local delayed = BridgeState.embodimentDelayedCallbacks or {}
    BridgeState.embodimentDelayedCallbacks = {}
    for _, callback in ipairs(delayed) do callback() end
end

function BridgePumpEmbodimentTransaction()
    local tx = BridgeState.embodimentTransaction
    if not BridgeEmbodimentTransactionIsCurrent(tx) then return false end
    local updateTick = tonumber(BridgeState.updateTick or 0) or 0
    if tx.kind == "NEW_MATCH_CLEANUP" then
        return BridgePumpNewMatchCleanupTransaction(tx, updateTick)
    end

    -- Callback-independent completion: once current TTS reality fully proves
    -- the target snapshot, proceed even if the native completion callback was
    -- dropped.  Verification, never elapsed time, authorizes the commit.
    if tx.snapshot ~= nil and tx.phase ~= "COMMIT" then
        local handsOk, handsError = BridgeReconcileSnapshotHandOwnership(tx.snapshot)
        local valid, validationError = false, handsError
        if handsOk then valid, validationError = BridgeValidateAuthoritativeSnapshotPhysicalState(tx.snapshot) end
        if valid then
            tx.verificationResult = true
            tx.lastBlockingPredicate = nil
            tx.phase = "VERIFY"
            tx.lastProgressUpdateTick = updateTick
            BridgeEmbodimentJournal(tx, "VERIFY", "POSTCONDITION_SATISFIED", nil)
        else
            tx.verificationResult = false
            tx.lastBlockingPredicate = tostring(validationError or "physical snapshot not yet verified")
        end
    end

    if tx.phase == "OBSERVE" then
        tx.observedState = BridgeObservePhysicalState(tx.desiredState)
        tx.phase = "PLAN"
        tx.lastProgressUpdateTick = updateTick
        BridgeEmbodimentJournal(tx, "OBSERVE", "PHYSICAL_STATE_CAPTURED", nil)
    elseif tx.phase == "PLAN" then
        tx.plan = BridgePlanEmbodimentReconciliation(tx.desiredState, tx.observedState or {})
        if tx.plan.blockingPredicate ~= nil then
            return BridgeFinishEmbodimentTransaction(tx, false, tx.plan.blockingPredicate)
        end
        BridgeAssignEmbodimentOperationTokens(tx)
        tx.phase = "APPLY"
        tx.operationStarted = false
        tx.lastProgressUpdateTick = updateTick
        BridgeEmbodimentJournal(tx, "PLAN", "PLAN_CREATED", "operations=" .. tostring(#(tx.plan.operations or {})))
    elseif tx.phase == "APPLY" then
        if not tx.operationStarted then
            tx.operationStarted = true
            tx.operationIndex = 1
            tx.operationAttempt = (tx.operationAttempt or 0) + 1
            tx.lastProgressUpdateTick = updateTick
            local attempt = tx.operationAttempt
            tx.currentOperation = tx.plan and tx.plan.operations and tx.plan.operations[1] or {
                index = 1,
                token = table.concat({tostring(tx.epoch), tostring(tx.token), tostring(tx.replanCount or 0), "1"}, ":"),
                type = "VERIFY_OR_RECONCILE_EXISTING_SNAPSHOT",
                precondition = "authoritative snapshot acquired",
                nativeAction = "BridgeLegacyBootstrapCurrentSnapshot",
                postcondition = "authoritative snapshot fully verified"
            }
            BridgeEmbodimentJournal(tx, "APPLY", tx.currentOperation.type,
                "operationToken=" .. tostring(tx.currentOperation.token) .. " attempt=" .. tostring(attempt))
            local operation = tx.currentOperation
            if operation.scope == "SEAT_LIBRARY" then
                local seatSnapshot = nil
                for _, candidateSeat in ipairs(tx.snapshot and tx.snapshot.seats or {}) do
                    if tostring(candidateSeat.seatId) == tostring(operation.seatId) then seatSnapshot = candidateSeat; break end
                end
                BridgeBindLibraryMappingsForSnapshot(seatSnapshot, function(ok, err, stats)
                    local status = stats and stats.status or (ok and "SUCCESS" or "FAILED")
                    if status == "WAITING_FOR_PHYSICAL_SETTLEMENT" then
                        tx.waitingForPhysicalSettlement = true
                        tx.lastProgressUpdateTick = updateTick
                        BridgeEmbodimentRecordBlockingObservation(tx, err or "library physical settlement pending")
                        BridgeEmbodimentJournal(tx, "APPLY", "WAITING_FOR_PHYSICAL_SETTLEMENT", "scope=SEAT_LIBRARY")
                        return
                    end
                    if status == "SUCCESS" then
                        tx.operationStarted = false
                        tx.phase = "OBSERVE"
                        tx.lastProgressUpdateTick = tonumber(BridgeState.updateTick or 0) or 0
                        BridgeEmbodimentJournal(tx, "OBSERVE", "SEAT_LIBRARY_REBOUND", nil)
                    else
                        BridgeEmbodimentOperationCallback(tx, attempt, false, err, nil)
                    end
                end)
            elseif operation.scope == "SEAT_HAND" then
                local observed = BridgeObservePhysicalState(tx.desiredState)
                local exact = true
                for instanceId, card in pairs(tx.desiredState and tx.desiredState.cardsByInstanceId or {}) do
                    if card.seatId == operation.seatId and card.zone == "hand"
                        and observed.byInstanceId[instanceId] == nil then exact = false; break end
                end
                if exact then
                    tx.operationStarted = false; tx.phase = "OBSERVE"
                    BridgeEmbodimentJournal(tx, "OBSERVE", "SEAT_HAND_REOBSERVED", nil)
                else
                    BridgeEmbodimentRecordBlockingObservation(tx, "hand ownership missing exact instance seat=" .. tostring(operation.seatId))
                    BridgeEmbodimentOperationCallback(tx, attempt, false, "seat hand exact ownership not observed", nil)
                end
            else
                BridgeLegacyBootstrapCurrentSnapshot(tx.targetSessionId, function(ok, err, snapshot, outcome)
                    BridgeDeliverEmbodimentOperationCallback(tx, attempt, ok, err, snapshot, "snapshot-reconcile", outcome)
                end, tx.resumeFromSnapshotCursor, tx.reason, tx)
            end
        elseif updateTick - (tx.lastProgressUpdateTick or updateTick) >= BRIDGE_EMBODIMENT_REOBSERVE_FRAMES then
            if tx.waitingForPhysicalSettlement == true and tx.currentOperation ~= nil
                and tx.currentOperation.scope == "SEAT_LIBRARY" then
                tx.waitingForPhysicalSettlement = false
                tx.operationStarted = false
                tx.phase = "OBSERVE"
                tx.lastProgressUpdateTick = updateTick
                BridgeEmbodimentJournal(tx, "OBSERVE", "SEAT_LIBRARY_SETTLEMENT_REOBSERVE", nil)
                return true
            end
            tx.replanCount = (tx.replanCount or 0) + 1
            tx.operationAttempt = tx.operationAttempt + 1
            tx.operationStarted = false
            tx.phase = "OBSERVE"
            tx.lastBlockingPredicate = "operation callback absent; reobserving current physical state"
            -- Fence the abandoned callback graph. Already-executed physics is
            -- intentionally retained and will be observed on the next pump.
            BridgeState.resyncBootstrapGeneration = (BridgeState.resyncBootstrapGeneration or 0) + 1
            BridgeState.bootstrapping = false
            BridgeEmbodimentJournal(tx, "OBSERVE", "CALLBACK_LOST_REPLAN", tx.lastBlockingPredicate)
        end
    elseif tx.phase == "SETTLE" then
        if updateTick - (tx.lastProgressUpdateTick or updateTick) >= BRIDGE_EMBODIMENT_REOBSERVE_FRAMES then
            tx.replanCount = (tx.replanCount or 0) + 1
            tx.phase = "OBSERVE"
            BridgeEmbodimentJournal(tx, "OBSERVE", "SETTLE_REOBSERVE", tx.lastBlockingPredicate)
        end
    elseif tx.phase == "VERIFY" then
        local handsOk, handsError = BridgeReconcileSnapshotHandOwnership(tx.snapshot)
        local valid, validationError = false, handsError
        if handsOk then valid, validationError = BridgeValidateAuthoritativeSnapshotPhysicalState(tx.snapshot) end
        if valid then
            tx.phase = "COMMIT"
            BridgeEmbodimentJournal(tx, "VERIFY", "VERIFIED", nil)
        else
            tx.replanCount = (tx.replanCount or 0) + 1
            tx.lastBlockingPredicate = tostring(validationError or "verification failed")
            tx.phase = "OBSERVE"
            BridgeEmbodimentJournal(tx, "OBSERVE", "VERIFY_FAILED_REPLAN", tx.lastBlockingPredicate)
        end
    elseif tx.phase == "COMMIT" then
        local committed, commitError = BridgeCommitSnapshotCheckpoint(tx.snapshot, "embodiment-transaction")
        if not committed then return BridgeFinishEmbodimentTransaction(tx, false, commitError) end
        BridgeState.committedPhysicalLedger = {
            physicalByInstanceId = BridgeDiagnosticSnapshot(BridgeState.physicalByInstanceId or {}),
            physicalInstanceIdByGuid = BridgeDiagnosticSnapshot(BridgeState.physicalInstanceIdByGuid or {}),
            physicalSeatByGuid = BridgeDiagnosticSnapshot(BridgeState.physicalSeatByGuid or {}),
            physicalZoneByGuid = BridgeDiagnosticSnapshot(BridgeState.physicalZoneByGuid or {}),
            physicalContainerByInstanceId = BridgeDiagnosticSnapshot(BridgeState.physicalContainerByInstanceId or {}),
            physicalContainedInstanceIdByGuid = BridgeDiagnosticSnapshot(BridgeState.physicalContainedInstanceIdByGuid or {}),
            physicalSlotByInstanceId = BridgeDiagnosticSnapshot(BridgeState.physicalSlotByInstanceId or {})
        }
        return BridgeFinishEmbodimentTransaction(tx, true, nil)
    end

    if (tx.replanCount or 0) > BRIDGE_EMBODIMENT_MAX_REPLANS then
        return BridgeFinishEmbodimentTransaction(tx, false,
            "embodiment reconciliation could not verify target after bounded replans: "
                .. tostring(tx.lastBlockingPredicate or "unknown physical predicate"))
    end
    return true
end

function BridgePerformanceDiagnosticPayload()
    -- Work exclusively on detached diagnostic data. Capturing a report must
    -- not write back into the live synchronization or presentation state while
    -- the HTTP request is outstanding.
    local summary = BridgeDiagnosticSnapshot(BridgeState.performanceSummary or {})
    local metrics = BridgeState.presentationMetrics or {}
    local ui = BridgeState.ui or {}
    local startup = BridgeState.startupTrace or {}
    local canary = {decisionPlayLandCount = 0, decisionCastSpellCount = 0, ttsRepresentedPlayLandCount = 0, ttsRepresentedCastSpellCount = 0}
    local decision = BridgeState.lastDecision
    for _, action in ipairs(decision and decision.actions or {}) do
        if action.type == "play_land" then canary.decisionPlayLandCount = canary.decisionPlayLandCount + 1 end
        if action.type == "cast_spell" then canary.decisionCastSpellCount = canary.decisionCastSpellCount + 1 end
    end
    canary.ttsRepresentedPlayLandCount = tonumber(summary.ttsRepresentedPlayLandCount or 0) or 0
    canary.ttsRepresentedCastSpellCount = tonumber(summary.ttsRepresentedCastSpellCount or 0) or 0
    summary.decisionRenderAttempts = tonumber(metrics.decisionRenderAttempts or 0) or 0
    summary.decisionRenderExecuted = tonumber(metrics.decisionRenderExecuted or 0) or 0
    summary.decisionRenderSkippedIdentical = tonumber(metrics.decisionRenderSkippedIdentical or 0) or 0
    summary.uiAttributeAttempts = tonumber(ui.uiAttributeAttemptCount or 0) or 0
    summary.uiAttributeWrites = tonumber(ui.uiAttributeWriteCount or 0) or 0
    summary.uiAttributeSkippedIdentical = tonumber(ui.uiAttributeSkippedCount or 0) or 0
    summary.encoderRebuildCount = tonumber(metrics.encoderRebuildCount or 0) or 0
    summary.keywordPropWriteCount = tonumber(metrics.keywordPropWriteCount or 0) or 0
    summary.decalWriteCount = tonumber(metrics.decalWriteCount or 0) or 0
    summary.fullSnapshotReconcileCount = tonumber(metrics.fullSnapshotReconcileCount or 0) or 0
    summary.resourceRowRefreshCount = tonumber(metrics.resourceRowRefreshCount or 0) or 0
    summary.resourceWorldScanCount = tonumber(metrics.resourceWorldScanCount or 0) or 0
    summary.worldScanCount = tonumber(metrics.worldScanCount or 0) or 0
    summary.yieldBackpressurePauseCount = tonumber(metrics.yieldBackpressurePauseCount or 0) or 0
    summary.snapshotVisualCounters = tonumber(metrics.snapshotVisualCounters or 0) or 0
    summary.snapshotVisualKeywords = tonumber(metrics.snapshotVisualKeywords or 0) or 0
    summary.snapshotVisualCharacteristics = tonumber(metrics.snapshotVisualCharacteristics or 0) or 0
    summary.snapshotVisualDesignations = tonumber(metrics.snapshotVisualDesignations or 0) or 0
    summary.snapshotReconcileLastAppliedCursor = BridgeState.snapshotReconcileLastAppliedCursor
    summary.snapshotReconcileLastAppliedGeneration = BridgeState.snapshotReconcileLastAppliedGeneration
    canary.turnNumber = tonumber(BridgeState.tableTurnCount or 0) or nil
    canary.phase = BridgeState.currentPhase
    canary.activeSeatId = BridgeState.currentTurnSeatId
    canary.prioritySeatId = BridgeState.prioritySeatId
    canary.decisionId = decision and decision.decisionId or nil
    canary.decisionKind = decision and decision.kind or nil
    canary.decisionPassPriorityPresent = false
    for _, action in ipairs(decision and decision.actions or {}) do
        if action.type == "pass_priority" then canary.decisionPassPriorityPresent = true end
    end
    canary.eventCursor = decision and decision.eventCursor or nil
    canary.lastTtsAppliedEventSequence = BridgeState.lastAppliedEventSequence
    summary.landActionCanary = canary
    summary.clockKind = BRIDGE_PERFORMANCE_CLOCK_KIND
    summary.wallClockKind = BRIDGE_PERFORMANCE_WALL_CLOCK_KIND
    summary.startupObservableDurationMs = startup.observableDurationMs
    summary.startupTransientCleanupDurationMs = startup.transientCleanupDurationMs
    summary.startupUiDurationMs = startup.uiDurationMs
    summary.startupObjectDiscoveryDurationMs = startup.objectDiscoveryDurationMs
    summary.startupHealthDispatchDurationMs = startup.healthDispatchDurationMs
    local startupPerf = BridgeState.startupPerf or {}
    local startupCounters = startupPerf.counters or {}
    summary.startupGetAllObjectsCalls = tonumber(startupCounters.getAllObjectsCalls or 0) or 0
    summary.startupResolveSeatLibraryDeckCalls = tonumber(startupCounters.resolveSeatLibraryDeckCalls or 0) or 0
    summary.startupDeckGetObjectsCalls = tonumber(startupCounters.deckGetObjectsCalls or 0) or 0
    summary.startupDeckTakeObjectCalls = tonumber(startupCounters.deckTakeObjectCalls or 0) or 0
    summary.startupDeckPutObjectCalls = tonumber(startupCounters.deckPutObjectCalls or 0) or 0
    summary.startupWaitFramesCalls = tonumber(startupCounters.waitFramesCalls or 0) or 0
    summary.startupWaitTimeCalls = tonumber(startupCounters.waitTimeCalls or 0) or 0
    summary.startupEmbodimentReplanCount = tonumber(startupCounters.embodimentReplanCount or 0) or 0
    return {
        performanceSummary = summary,
        recentTtsTrace = BridgeDiagnosticSnapshot(BridgePerformanceTraceSnapshot()),
        diagnosticCaptureLifecycle = BridgeDiagnosticSnapshot(BridgeState.diagnosticCaptureLifecycle or {}),
        authoritativeForge = {
            turn = decision and decision.turnNumber or nil,
            phase = decision and decision.phaseName or nil,
            decisionId = decision and decision.decisionId or nil,
            decisionKind = decision and decision.kind or nil,
            eventCursor = decision and decision.eventCursor or nil
        },
        ttsPresentation = {
            turn = BridgeState.tableTurnCount,
            phase = BridgeState.currentPhase,
            renderedDecisionId = BridgeState.lastDecision and BridgeState.lastDecision.decisionId or nil,
            receivedCursor = BridgeState.lastReceivedEventSequence,
            appliedCursor = BridgeState.lastAppliedEventSequence,
            status = BridgeState.statusText
        },
        resyncLifecycle = BridgeDiagnosticSnapshot(BridgeState.resyncLifecycle or {}),
        eventDrainDiagnostics = BridgeEventDrainQueueState(),
        startupPerf = BridgeDiagnosticSnapshot(BridgeState.startupPerf or {}),
        recoveryStateInvariants = BridgeComputeRecoveryStateInvariants()
    }
end

function BridgePerformanceRecordTtsActionRepresentation()
    local summary = BridgeState.performanceSummary
    if summary == nil then return end
    local seen = {}
    local lands, spells = 0, 0
    for _, action in pairs(BridgeState.actionByGuid or {}) do
        if action ~= nil and action.actionId ~= nil and not seen[action.actionId] then
            seen[action.actionId] = true
            if action.type == "play_land" then lands = lands + 1 end
            if action.type == "cast_spell" then spells = spells + 1 end
        end
    end
    summary.ttsRepresentedPlayLandCount = lands
    summary.ttsRepresentedCastSpellCount = spells
end

function BridgeLogPresentationMetrics(label)
    local metrics = BridgeState.presentationMetrics or {}
    BridgeLog(string.format(
        "[Bridge] presentation-metrics label=%s decisionAttempts=%d decisionExecuted=%d decisionSkippedIdentical=%d uiAttempts=%d uiWrites=%d uiSkippedIdentical=%d encoderRebuilds=%d keywordWrites=%d decalWrites=%d snapshotReconciles=%d resourceRows=%d resourceScans=%d worldScans=%d yieldPaused=%d snapshotCounters=%d snapshotKeywords=%d snapshotCharacteristics=%d snapshotDesignations=%d",
        tostring(label or "manual"), tonumber(metrics.decisionRenderAttempts or 0),
        tonumber(metrics.decisionRenderExecuted or 0),
        tonumber(metrics.decisionRenderSkippedIdentical or 0),
        tonumber(BridgeState.ui and BridgeState.ui.uiAttributeAttemptCount or 0),
        tonumber(BridgeState.ui and BridgeState.ui.uiAttributeWriteCount or 0),
        tonumber(BridgeState.ui and BridgeState.ui.uiAttributeSkippedCount or 0),
        tonumber(metrics.encoderRebuildCount or 0), tonumber(metrics.keywordPropWriteCount or 0),
        tonumber(metrics.decalWriteCount or 0), tonumber(metrics.fullSnapshotReconcileCount or 0),
        tonumber(metrics.resourceRowRefreshCount or 0), tonumber(metrics.resourceWorldScanCount or 0),
        tonumber(metrics.worldScanCount or 0), tonumber(metrics.yieldBackpressurePauseCount or 0),
        tonumber(metrics.snapshotVisualCounters or 0), tonumber(metrics.snapshotVisualKeywords or 0),
        tonumber(metrics.snapshotVisualCharacteristics or 0), tonumber(metrics.snapshotVisualDesignations or 0)))
end

function BridgeWaitTime(callback, delay)
    local epoch = BRIDGE_RUNTIME_EPOCH_LOCAL
    BridgeStartupPerfCounter("waitTimeCalls", 1)
    Wait.time(function()
        if not BridgeRuntimeIsCurrent(epoch) then return end
        callback()
    end, delay)
end

function BridgeWaitFrames(callback, frames)
    local epoch = BRIDGE_RUNTIME_EPOCH_LOCAL
    BridgeStartupPerfCounter("waitFramesCalls", 1)
    Wait.frames(function()
        if not BridgeRuntimeIsCurrent(epoch) then return end
        callback()
    end, frames)
end

-- Seat identity remains independent of controller type and TTS color.
BRIDGE_SEATS = {
    ["forge-player-1"] = {
        ttsColor = "White",
        animateAuthoritativeEvents = false,
        assetMaxAbsX = 40,
        libraryAssetRadius = 4,
        targetSurfaceGuid = "2a7098",
        lifeCounterGuid = "2a7098",
        libraryZoneGuid = "ddf5c3",
        tableSideZ = -1,
        attackLaneZ = -0.9,
        blockerLaneZ = -2.2,
        manaBankOffset = {x = 2.5, y = 0.45, z = -0.60},  -- Positioned right of life counter, nudged toward battlefield
        resourceRotation = {x = 0, y = 90, z = 0},
        trackerOffsets = {
            poison = {x = -2.8, y = 0.45, z = -0.55}, experience = {x = -4.0, y = 0.45, z = -0.55},
            energy = {x = -5.2, y = 0.45, z = -0.55}, speed = {x = -6.4, y = 0.45, z = -0.55}
        },
        faceUpRotation = {x = 0, y = 180, z = 0},
        graveyardZoneGuid = nil,
        exileZoneGuid = nil,
        -- Extracted native table geometry; y is a deliberate card drop height.
        libraryAnchor = {x = 1.7772, y = 2.0, z = -8.7126},
        graveyardAnchor = {x = 1.7714, y = 2.0, z = -12.2921},
        exileAnchor = {x = 1.7575, y = 2.0, z = -15.9598},
        commandAnchor = {x = 37.3817, y = 2.0, z = -3.1542},
        monarchAnchor = {x = 37.3817, y = 2.35, z = -3.1542},
        monarchRotation = {x = 0, y = 180, z = 0},
        includeCardGuids = {},
        excludeCardGuids = {},
        battlefieldAnchors = {
            land = {x = 6.5, y = 2.0, z = -11.5},
            creature = {x = 7.0, y = 2.0, z = -3.5}
        }
    },
    ["forge-player-2"] = {
        ttsColor = "Blue",
        animateAuthoritativeEvents = true,
        assetMaxAbsX = 40,
        libraryAssetRadius = 4,
        targetSurfaceGuid = "3ef92a",
        lifeCounterGuid = "3ef92a",
        libraryZoneGuid = "548812",
        tableSideZ = 1,
        attackLaneZ = 0.9,
        blockerLaneZ = 2.2,
        manaBankOffset = {x = 2.5, y = 0.45, z = 0.60},  -- Positioned right of life counter, nudged toward battlefield
        resourceRotation = {x = 0, y = 270, z = 0},
        trackerOffsets = {
            poison = {x = -2.8, y = 0.45, z = 0.55}, experience = {x = -4.0, y = 0.45, z = 0.55},
            energy = {x = -5.2, y = 0.45, z = 0.55}, speed = {x = -6.4, y = 0.45, z = 0.55}
        },
        faceUpRotation = {x = 0, y = 0, z = 0},
        graveyardZoneGuid = nil,
        exileZoneGuid = nil,
        -- Extracted native table geometry; y is a deliberate card drop height.
        libraryAnchor = {x = 1.7983, y = 2.0, z = 8.7004},
        graveyardAnchor = {x = 1.7476, y = 2.0, z = 12.3162},
        exileAnchor = {x = 1.7837, y = 2.0, z = 15.9528},
        commandAnchor = {x = 37.3622, y = 2.0, z = 3.1347},
        monarchAnchor = {x = 37.3622, y = 2.35, z = 3.1347},
        monarchRotation = {x = 0, y = 0, z = 0},
        includeCardGuids = {},
        excludeCardGuids = {},
        battlefieldAnchors = {
            land = {x = 6.5, y = 2.0, z = 19.0},
            creature = {x = 7.0, y = 2.0, z = 3.5}
        }
    }
}

local _obj = getObjectFromGUID
local _rawAllObjects = getAllObjects
local function BridgeAllObjectsSnapshot()
    if BridgeStartupPerfCounter ~= nil then
        BridgeStartupPerfCounter("getAllObjectsCalls", 1)
    end
    if type(_rawAllObjects) ~= "function" then
        return {}
    end
    return _rawAllObjects()
end
getAllObjects = BridgeAllObjectsSnapshot
local _all = BridgeAllObjectsSnapshot
local _spawn = spawnObject
local _ip = ipairs
local _pairs = pairs

BridgeState = {
    -- The Bridge process and the Forge session are independent lifetimes.
    -- A process restart invalidates every callback from the old match; a
    -- no-session response is setup state, never an active-session resync.
    lifecycleState = "DISCONNECTED",
    bridgeProcessInstanceId = nil,
    connectionEpoch = 0,
    -- Runtime reload and embodiment ownership are intentionally separate.
    -- Save & Play changes BRIDGE_RUNTIME_EPOCH_LOCAL; this epoch fences
    -- destructive lifecycle/recovery plans within one loaded Global script.
    embodimentEpoch = 1,
    embodimentTransactionToken = 0,
    embodimentTransaction = nil,
    embodimentJournal = {},
    committedPhysicalLedger = nil,
    sessionCleanupApplied = false,
    selectedFormat = BRIDGE_DEFAULT_MATCH_FORMAT,
    selectedFormatProvenance = "tts-default-limited",
    allowDeckMinimumOverride = BRIDGE_ALLOW_DECK_MINIMUM_OVERRIDE,
    lastDecision = nil,
    actionByGuid = {},
    highlightedGuids = {},
    targetButtonIndexByGuid = {},
    playerTargetControlGuids = {},
    endTurnObjectGuidBySeatId = {},
    passObjectGuidBySeatId = {},
    setupObjectGuidByKind = {},
    -- Reuse named presentation objects between refreshes; each lookup still
    -- validates the GUID through BridgeGetLiveObjectByGuid before use.
    namedObjectGuidByName = {},
    statusObjectGuid = nil,
    statusHeadline = "CLIENT LOADED",
    statusDetail = "Checking companion...",
    turnCounterObjectGuidByKind = {},
    turnCountsBySeatId = {},
    tableTurnCount = 0,
    turnCounterSessionId = nil,
    resetConfirmationArmed = false,
    resetConfirmationGuid = nil,
    selectedActionIds = {},
    selectedGuidByActionId = {},
    selectionDecisionId = nil,
    selectionControlGuids = {},
    selectionControlDecisionId = nil,
    selectionControlActionId = nil,
    optionControlGuids = {},
    optionControlDecisionId = nil,
    attackOriginByGuid = {},
    attackLaneGuidBySeatId = {},
    combatSelectedByGuid = {},
    manaCounterGuidBySeatId = {},
    playerTrackerGuidBySeatId = {},
    -- Canonical physical presentation map for the compact resource row.
    -- Legacy mana/tracker maps remain as compatibility aliases for callers.
    resourceCounterGuidBySeatId = {},
    resourceCounterSpawnInFlightBySeatId = {},
    monarchHelperGuid = nil,
    monarchSeatId = nil,
    monarchSpawnInFlight = false,
    submitting = false,
    choiceAttemptSequence = 0,
    choiceRequestSequence = 0,
    choiceTransactions = {},
    retiredChoiceDecisionIds = {},
    retiredChoiceDecisionOrder = {},
    pendingIntent = nil,
    unboundPickupIntent = nil,
    pendingIntentControlGuids = {},
    pendingDecision = nil,
    decisionAwaitingCausallyCurrent = false,
    staleDecisionRetryKey = nil,
    staleDecisionRetryCount = 0,
    staleDecisionRetryStartedAt = nil,
    staleDecisionRetryDeadlineAt = nil,
    pendingDecisionDeferredAt = nil,
    pendingDecisionDeferredCursor = 0,
    pendingDecisionDeferredApplied = 0,
    expectedHandInstanceIdsBySeatId = {},
    openingHandReadinessDecisionId = nil,
    openingHandReadinessSnapshotPending = false,
    openingHandReadinessSnapshotRequested = false,
    openingHandReadinessRetryScheduled = false,
    handActionReadinessSnapshotDecisionId = nil,
    handActionReadinessSnapshotSessionId = nil,
    handReadinessRecoveryDecisionId = nil,
    handReadinessRecoverySessionId = nil,
    handReadinessRecoveryAttempts = 0,
    bootstrapStage = "BOOTSTRAP_IDLE",
    bootstrapCompletionInFlight = false,
    eventSessionId = nil,
    eventSessionGeneration = 0,
    lastReceivedEventSequence = 0,
    lastAppliedEventSequence = 0,
    lastConsumedEventSequence = 0,
    lastStateProjectedEventSequence = 0,
    lastPhysicalPresentationEventSequence = 0,
    lastAppliedForgeSequence = 0,
    phaseSourceEventSequence = 0,
    turnSourceEventSequence = 0,
    activePlayerSourceEventSequence = 0,
    prioritySourceEventSequence = 0,
    eventPolling = false,
    eventPollGeneration = 0,
    eventRequestInFlight = false,
    eventPollScheduled = false,
    eventRequestGeneration = nil,
    updateTick = 0,
    decisionPollGeneration = 0,
    decisionPresentationGeneration = 0,
    decisionPollInFlight = false,
    decisionPollScheduled = false,
    decisionPollScheduledAt = nil,
    decisionPollDueAt = nil,
    decisionPollScheduledUpdateTick = nil,
    decisionPollDueUpdateTick = nil,
    decisionPollTimerToken = nil,
    lastDecisionPollStartedAt = nil,
    lastDecisionPollCompletedAt = nil,
    lastDecisionPollOutcome = nil,
    decisionAuthoritativeWatermark = nil,
    decisionRefreshInFlight = false,
    eventRetryCount = 0,
    skipExistingEventsOnAttach = false,
    eventQueue = {},
    animationRunning = false,
    -- H0 single owner for presentation/recovery.  Compatibility flags remain
    -- below, but no mutation transaction is allowed to exist outside this.
    presentationState = "RUNNING",
    eventCommitWatchdog = {
        eventSequence = nil,
        successfulApplyAttemptsWithoutCommit = 0,
        firstAttemptTimestamp = nil,
        lastAbortReason = nil
    },
    eventDrainTransaction = nil,
    eventDrainContinuation = nil,
    eventDrainContinuationToken = 0,
    eventDrainLastContinuation = nil,
    eventDrainWatchdog = {
        sessionId = nil,
        sessionGeneration = nil,
        eventSequence = nil,
        lastAppliedEventSequence = nil,
        blockedSince = nil,
        lastBlockReason = nil,
        logged = false,
        scheduled = false
    },
    currentPhysicalPresentationGeneration = 0,
    physicalTransactionGeneration = 0,
    physicalReadinessDependency = nil,
    renderedDecisionPresentationKey = nil,
    renderedDecisionPhysicalGeneration = nil,
    physicalByInstanceId = {},
    physicalInstanceIdByGuid = {},
    -- A card inside a native TTS Deck is not a live top-level object. Keep
    -- its exact physical card GUID together with the containing Deck GUID so
    -- duplicate printed names never become an identity source.
    physicalContainerByInstanceId = {},
    physicalContainedInstanceIdByGuid = {},
    physicalSlotByInstanceId = {},
    libraryBindingGenerationBySeatId = {},
    -- Native Deck contained GUIDs are ephemeral TTS implementation details.
    -- Forge instance identity in a deck-like zone is this ordered ledger.
    zoneLedgerBySeatAndZone = {},
    bootstrapLibraryMappingBySeatId = {},
    cardNameByInstanceId = {},
    canonicalCardNameByGuid = {},
    encoderIdentityLoggedGuids = {},
    presentedStatsByGuid = {},
    presentedOwnerControllerByGuid = {},
    presentedPhasedByGuid = {},
    presentedCounterSignatureByGuid = {},
    presentedCounterFallbackSignatureByGuid = {},
    presentedKeywordSignatureByGuid = {},
    presentedIconLayoutByGuid = {},
    preparedDescriptionByGuid = {},
    prototypeDescriptionByGuid = {},
    preparedBadgeGuidByInstanceId = {},
    preparedPresentationGuidByInstanceId = {},
    preparedDesignationStateByInstanceId = {},
    preparedSpellControlGuids = {},
    unsupportedKeywordLogged = {},
    presentationMetrics = {
        encoderRebuildCount = 0,
        keywordPropWriteCount = 0,
        decalWriteCount = 0,
        fullSnapshotReconcileCount = 0,
        resourceRowRefreshCount = 0,
        resourceWorldScanCount = 0,
        worldScanCount = 0,
        yieldBackpressurePauseCount = 0,
        decisionRenderAttempts = 0,
        decisionRenderExecuted = 0,
        decisionRenderSkippedIdentical = 0
    },
    performanceTrace = {capacity = BRIDGE_PERFORMANCE_TRACE_CAPACITY, head = 0, count = 0, records = {}},
    performanceSummary = {
        slowRenderCount = 0,
        worstRenderDurationMs = 0,
        worstClearHighlightsDurationMs = 0,
        worstPreparedPresentationDurationMs = 0,
        worstCandidateCollectionDurationMs = 0,
        worstActionMatchingDurationMs = 0,
        worstUiFlushDurationMs = 0,
        worstSnapshotReconcileDurationMs = 0,
        startupGetAllObjectsCalls = 0,
        startupResolveSeatLibraryDeckCalls = 0,
        startupDeckGetObjectsCalls = 0,
        startupDeckTakeObjectCalls = 0,
        startupDeckPutObjectCalls = 0,
        startupWaitFramesCalls = 0,
        startupWaitTimeCalls = 0,
        startupEmbodimentReplanCount = 0,
        ttsRepresentedPlayLandCount = 0,
        ttsRepresentedCastSpellCount = 0
    },
    startupTrace = {
        healthDispatchRecorded = false,
        objectDiscoveryRecorded = false,
        summaryLogged = false,
        observableDurationMs = nil,
        transientCleanupDurationMs = nil,
        uiDurationMs = nil,
        objectDiscoveryDurationMs = nil,
        healthDispatchDurationMs = nil
    },
    startupPerf = {
        active = false,
        origin = nil,
        baseWallSeconds = nil,
        baseCpuSeconds = nil,
        baseUpdateTick = 0,
        stageTokens = {},
        stageRecords = {},
        counters = {}
    },
    physicalSeatByGuid = {},
    physicalZoneByGuid = {},
    -- Table helpers are never candidates for Forge CardInstanceId mapping.
    presentationOnlyGuids = { ["946716"] = {kind = "utility_cards_deck"} },
    -- Token embodiments are real game objects during a session, but are not
    -- library cards.  Destructive NEW MATCH removes them instead of shuffling
    -- them into a player's imported deck.
    tokenPhysicalGuids = {},
    -- Token imports are asynchronous. A Forge identity is allowed one and
    -- only one in-flight embodiment, independent of token name.
    tokenMaterializationByInstanceId = {},
    -- Authoritative Forge-object metadata is independent of physical GUIDs.
    -- Virtual/copy objects can exist without an original deck card.
    authoritativeObjectByInstanceId = {},
    canonicalCardScaleByGuid = {},
    landPlacementMode = BRIDGE_LAND_PLACEMENT_MODE,
    landInsertionOrderByInstanceId = {},
    nextLandInsertionOrder = 0,
    discardPresentation = nil,
    mulliganBottomInstanceIds = {},
    mulliganReturningInstanceIds = {},
    mulliganBottomQueueBySeatId = {},
    mulliganBottomInsertionActiveBySeatId = {},
    libraryExtractionQueueBySeatId = {},
    libraryExtractionActiveBySeatId = {},
    libraryExtractionTransactionBySeatId = {},
    libraryInsertionHandReleaseByGuid = {},
    newMatchCleanupOwner = nil,
    lastNewMatchCleanupFailure = nil,
    graveyardExtractionActiveBySeatId = {},
    -- Consecutive library transitions emitted by one Forge mutation are one
    -- physical transaction.  The queue still serializes Deck operations, but
    -- this owner prevents verification/recovery from observing its middle.
    libraryBatchBySeatId = {},
    battlefieldCounts = {},
    graveyardCounts = {},
    currentTurnSeatId = nil,
    prioritySeatId = nil,
    stackSummary = {},
    stackObjects = {},
    -- HUD YIELD can be armed while the AI is acting and no human decision is
    -- currently visible.  Keep that policy scoped to the authoritative turn
    -- and active seat so it cannot leak into a later turn.
    yieldPolicyTurnNumber = nil,
    yieldPolicyActiveSeatId = nil,
    yieldPolicySessionId = nil,
    yieldPolicyOwnTurn = false,
    decisionLifecycle = {},
    staleDecisionFault = nil,
    staleDecisionFaultsByKey = {},
    terminalRecoveryError = nil,
    diagnosticCaptureLifecycle = {},
    revealedPresentationsByKey = {},
    revealedPresentationOrder = {},
    dismissedRevealKeys = {},
    activeRevealPresentationKey = nil,
    revealSurfaceOffset = 1,
    diagnosticCaptureFollowupToken = nil,
    diagnosticCaptureFollowupUntil = 0,
    resyncNoProgress = {
        sessionId = nil,
        forgeSequence = nil,
        eventCursor = nil,
        count = 0,
        lastLoggedCount = 0
    },
    resyncLifecycle = {},
    resyncCheckpoint = nil,
    resyncScheduled = false,
    resyncDeferredRetryScheduled = false,
    resyncDeferredSince = nil,
    resyncWatchdogToken = nil,
    resyncUpdateTick = 0,
    resyncStartedUpdateTick = nil,
    resyncStartedCpuAt = nil,
    resyncLastStartedAt = nil,
    resyncLastStartedCpuAt = nil,
    resyncLastStartedUpdateTick = nil,
    resyncBootstrapGeneration = 0,
    lastChoiceAttempt = nil,
    counterStateByInstanceId = {},
    keywordStateByInstanceId = {},
    cardDesignationsByInstanceId = {},
    untappedRotationByGuid = {},
    -- Tap state is Forge-owned.  Keep it separately from the current face
    -- orientation so a face-up/face-down update cannot accidentally restore
    -- an otherwise tapped permanent to its untapped rotation.
    physicalTappedByGuid = {},
    pendingCastBySeatId = {},
    snapshotForgeSequence = 0,
    snapshotReconcileInFlight = false,
    snapshotReconcilePending = false,
    snapshotReconcilePendingRequest = nil,
    snapshotReconcileRequestGeneration = 0,
    snapshotReconcileLastAppliedCursor = 0,
    snapshotReconcileLastAppliedGeneration = 0,
    snapshotReconcileLastAppliedCategory = nil,
    deferredSnapshotReconcile = nil,
    lastTurnEventSignature = nil,
    lastPhaseEventSignature = nil,
    lastPriorityEventSignature = nil,
    -- A textual semantic event (such as land_played) can immediately follow
    -- the same exact structured card_moved event.  Keep the exact transition
    -- identity so the second renderer never treats a temporarily unresolved
    -- first renderer as a name-based physical desync.
    pendingStructuredZoneTransitionByInstanceId = {},
    -- A card returning from a public zone to a hand can be visually
    -- indistinguishable from another copy already in that hand. Keep the
    -- authoritative Forge identity pending until it next becomes public.
    pendingPrivateHandIdentityByInstanceId = {},
    -- A semantic land_played line can precede the coalesced structured zone
    -- transition. Preserve only its presentation row; the later exact
    -- CardInstanceId event still owns physical identity and movement.
    battlefieldKindByInstanceId = {},
    presentedCombatSignature = nil,
    zoneAnchorGuidBySeatAndZone = {},
    resourceCounterIndexHydrated = false,
    monarchHelperIndexHydrated = false,
    bootstrapping = false,
    setupBusy = false,
    setupStage = "IDLE",
    setupLastError = nil,
    setupTrace = {},
    doctorInitializedUi = false,
    doctorRetryAttempt = 0,
    transitionExpectedUntil = 0,
    latencyProbe = nil,
    sessionRecoveryInFlight = false,
    resyncToken = 0,
    resyncStartedAt = nil,
    resyncStartedUpdateTick = nil,
    resyncStartedCpuAt = nil,
    resyncStage = "Idle",
    resyncStageChangedAt = nil,
    resyncLastCallbackStage = nil,
    resyncLastCallbackAt = nil,
    resyncLastCallbackReason = nil,
    resyncExpectedCallbackStage = nil,
    resyncExpectedCallbackAt = nil,
    resyncExpectedCallbackReason = nil,
    resyncLastUnobservedCallbackStage = nil,
    resyncLastUnobservedCallbackAt = nil,
    resyncLastUnobservedCallbackReason = nil,
    resyncCompletionContinuation = nil,
    resyncCompletionCallback = nil,
    resyncCompletionContinuationToken = 0,
    resyncPhysicalRebuildReady = false,
    resyncPhysicalValidationPassed = false,
    resyncCandidateSnapshot = nil,
    resyncAttempt = 0,
    resyncRootCause = nil,
    resyncLastFailureReason = nil,
    resyncLastProgressAt = nil,
    resyncNoProgressAttempts = 0,
    resyncCircuitOpen = false,
    snapshotRecoveryOwner = nil,
    snapshotRecoverySuppressedCount = 0,
    lastSnapshotSupersededRange = nil,
    resyncSnapshotFingerprint = nil,
    resyncSnapshotRepeatCount = 0,
    resyncMappingTransaction = nil,
    resyncMappingTransactionStatus = nil,
    resyncMappingTransactionStartedAt = nil,
    resyncMappingTransactionCompletedAt = nil,
    resyncReconcileStarted = false,
    resyncLastBlockingPredicate = nil,
    resyncOrigin = nil,
    schedulerOwner = "NORMAL",
    runtimeCompatibility = nil,
    runtimeCompatibilityState = "UNKNOWN",
    fastForwardSuspendedByResync = false,
    resyncDeferredReason = nil,
    manualResyncGraceUntil = 0,
    -- A physical-sync failure is terminal for the current presentation
    -- generation.  Async movement/snapshot callbacks may still finish after
    -- the stop (and while an explicit resync is rebuilding the table); keep
    -- those callbacks diagnostic-only instead of surfacing a second failure.
    desyncLatched = false,
    desyncFailureCount = 0,
    desyncLastMessage = nil,
    choiceProtocolPaused = false,
    choiceProtocolFailureTimes = {},
    gameEnded = nil,
    resultSourceEventId = nil,
    resultEventCursor = nil,
    resultSessionId = nil,
    resultOutcome = nil,
    resultReason = nil,
    resultPresentationGeneration = 0,
    playerStateBySeatId = {},
    playerCountersBySeatId = {},
    ui = {mounted = false, dirty = false, flushScheduled = false, actionRows = {}, contextInstanceId = nil,
        graveyardActionRows = {}, graveyardFolderDecisionId = nil, graveyardFolderOpen = false,
        graveyardFolderPage = 1,
        manaMode = "AUTO", autoAdvanceMode = "NORMAL", autoPassEmpty = false,
        fastForwardActive = false, fastForwardSessionId = nil, fastForwardTurnNumber = nil,
        fastForwardActiveSeatId = nil, fastForwardStops = {own_turn = {}, other_turn = {}},
        fastForwardStopScope = "own_turn", fastPlaytest = false, gameLogVisible = true,
        gameLog = {},
        diagnosticsVisible = false, reportPanelVisible = false, reportCategoryIndex = 1,
        creatureTypeDecisionId = nil, creatureTypeDraftActionId = nil, creatureTypeOptions = {},
        reportStatus = "", reportCaptureInFlight = false, reportCaptureToken = 0, resyncInFlight = false, uiFullRebuildCount = 0, uiAttributeUpdateCount = 0,
        uiAttributeCache = {}, uiAttributeAttemptCount = 0, uiAttributeWriteCount = 0,
        uiAttributeSkippedCount = 0,
        actionPanelRenderCount = 0, candidatePanelRenderCount = 0, ephemeralPhysicalControlSpawnCount = 0},
}

BridgeHttp = {}

local BRIDGE_SETUP_TRACE_CAPACITY = 64
function BridgeSetupTrace(marker, detail)
    local record = {timestamp = os.clock(), marker = marker, detail = detail,
        stage = BridgeState.setupStage, lifecycle = BridgeState.lifecycleState}
    BridgeState.setupTrace = BridgeState.setupTrace or {}
    table.insert(BridgeState.setupTrace, record)
    while #BridgeState.setupTrace > BRIDGE_SETUP_TRACE_CAPACITY do table.remove(BridgeState.setupTrace, 1) end
    BridgeLog("[Bridge] " .. tostring(marker) .. (detail and (" " .. tostring(detail)) or ""))
    return record
end

function BridgeSetupStage(stage, detail)
    local priorStage = BridgeState.setupStage
    if priorStage ~= nil and priorStage ~= stage then
        BridgeStartupPerfStageEnd("setup-" .. tostring(priorStage), "next=" .. tostring(stage))
    end
    BridgeState.setupStage = stage
    BridgeSetupTrace(stage, detail)
    local labels = {
        READING_DECKS = "Reading decks…",
        CONTACTING_BRIDGE = "Contacting Bridge…",
        VALIDATING_DECKS = "Validating decks…",
        STARTING_FORGE = "Starting Forge…",
        WAITING_FOR_FORGE = "Waiting for Forge…",
        RECONCILING_HUMAN_SNAPSHOT = "Reconciling human snapshot…",
        RECONCILING_HUMAN_LIBRARY = "Reconciling human library…",
        RECONCILING_AI_SNAPSHOT = "Reconciling AI snapshot…",
        RECONCILING_AI_LIBRARY = "Reconciling AI library…",
        VERIFYING_PHYSICAL_SNAPSHOT = "Verifying physical snapshot…",
        READY = "Ready",
        SETUP_STATE_VALIDATED = "Validating setup…"
    }
    if BridgeSetStatus ~= nil and labels[stage] ~= nil then BridgeSetStatus(labels[stage], detail or "") end
    BridgeStartupPerfStageBegin("setup-" .. tostring(stage), detail)
    if stage == "READY" then BridgeStartupPerfEvent("decision-presentation-ready", tostring(detail or "")) end
    BridgeUiMarkDirty("setup-stage-" .. tostring(stage))
end

function BridgeSetupFailure(stage, errorMessage)
    local detail = tostring(errorMessage or "unknown error")
    BridgeState.setupLastError = detail
    BridgeSetupStage("FAILED", "stage=" .. tostring(stage) .. " error=" .. detail)
    BridgeSetStatus("FAILED: " .. tostring(stage), detail)
    BridgeShowError("NEW MATCH failed at " .. tostring(stage) .. ": " .. detail)
end

function BridgeRunSetupProtected(stage, action)
    local ok, err = xpcall(action, debug and debug.traceback or function(value) return tostring(value) end)
    if ok then return true end
    BridgeSetupFailure(stage, err)
    return false
end

BRIDGE_LIFECYCLE_DISCONNECTED = "DISCONNECTED"
BRIDGE_LIFECYCLE_READY_NO_SESSION = "BRIDGE_READY_NO_SESSION"
BRIDGE_LIFECYCLE_STARTING = "STARTING_SESSION"
BRIDGE_LIFECYCLE_ACTIVE = "SESSION_ACTIVE"
BRIDGE_LIFECYCLE_ENDING = "ENDING_SESSION"
BRIDGE_LIFECYCLE_RECOVERING = "RECOVERING_ACTIVE_SESSION"
BRIDGE_LIFECYCLE_START_FAILED = "START_FAILED"

local BRIDGE_LIFECYCLE_COMMAND_RULES = {
    START_MATCH = {
        [BRIDGE_LIFECYCLE_READY_NO_SESSION] = true,
        [BRIDGE_LIFECYCLE_START_FAILED] = true
    },
    RESUME_MATCH = {
        [BRIDGE_LIFECYCLE_ACTIVE] = true,
        [BRIDGE_LIFECYCLE_RECOVERING] = true,
        [BRIDGE_LIFECYCLE_READY_NO_SESSION] = true,
        [BRIDGE_LIFECYCLE_START_FAILED] = true
    },
    NEW_MATCH = {
        [BRIDGE_LIFECYCLE_DISCONNECTED] = true,
        [BRIDGE_LIFECYCLE_READY_NO_SESSION] = true,
        [BRIDGE_LIFECYCLE_STARTING] = true,
        [BRIDGE_LIFECYCLE_ACTIVE] = true,
        [BRIDGE_LIFECYCLE_RECOVERING] = true,
        [BRIDGE_LIFECYCLE_START_FAILED] = true
    },
    CONFIRM_NEW_MATCH = {
        [BRIDGE_LIFECYCLE_DISCONNECTED] = true,
        [BRIDGE_LIFECYCLE_READY_NO_SESSION] = true,
        [BRIDGE_LIFECYCLE_STARTING] = true,
        [BRIDGE_LIFECYCLE_ACTIVE] = true,
        [BRIDGE_LIFECYCLE_RECOVERING] = true,
        [BRIDGE_LIFECYCLE_START_FAILED] = true
    }
}

function BridgeLifecycleCommandAllowed(command)
    local state = BridgeState.lifecycleState or BRIDGE_LIFECYCLE_DISCONNECTED
    local allowedStates = BRIDGE_LIFECYCLE_COMMAND_RULES[tostring(command or "")]
    if allowedStates == nil then
        return true, state
    end
    return allowedStates[state] == true, state
end

function BridgeGuardLifecycleCommand(command)
    local allowed, state = BridgeLifecycleCommandAllowed(command)
    if allowed then return true end
    local label = string.gsub(tostring(command or "COMMAND"), "_", " ")
    local message = string.format("%s unavailable while lifecycle state is %s", label, tostring(state))
    BridgeLog("[Bridge] COMMAND_BLOCKED command=" .. tostring(command)
        .. " lifecycle=" .. tostring(state)
        .. " session=" .. tostring(BridgeState.eventSessionId))
    if BridgeSetStatus ~= nil then BridgeSetStatus("COMMAND BLOCKED", message) end
    if BridgeShowError ~= nil then BridgeShowError(message) end
    return false
end

function BridgeSetLifecycleState(state, reason)
    local previous = BridgeState.lifecycleState
    BridgeState.lifecycleState = state
    if previous ~= state then
        BridgeLog(string.format("[Bridge] LIFECYCLE %s -> %s reason=%s connectionEpoch=%s session=%s",
            tostring(previous), tostring(state), tostring(reason), tostring(BridgeState.connectionEpoch),
            tostring(BridgeState.eventSessionId)))
    end
    if BridgeUiMarkDirty ~= nil then BridgeUiMarkDirty("lifecycle-" .. tostring(state)) end
end

-- One idempotent local transaction for crossing into setup.  It never calls
-- Forge and deliberately does not attempt snapshot recovery.  The cleanup
-- marker prevents repeated health/404 responses from churning generations.
function BridgeCleanupLocalSession(reason, lifecycleState)
    if BridgeState.sessionCleanupApplied == true
        and BridgeState.eventSessionId == nil
        and BridgeState.lastDecision == nil then
        BridgeSetLifecycleState(lifecycleState or BRIDGE_LIFECYCLE_READY_NO_SESSION, reason)
        BridgeState.newMatchCleanupOwner = nil
        BridgeState.lastNewMatchCleanupFailure = nil
        if BridgeEnsureSetupControls ~= nil then BridgeEnsureSetupControls() end
        return false
    end

    BridgeState.sessionCleanupApplied = true
    BridgeState.newMatchCleanupOwner = nil
    BridgeState.lastNewMatchCleanupFailure = nil
    if BridgeStopEventPolling ~= nil then BridgeStopEventPolling("session-boundary:" .. tostring(reason)) end
    if BridgeStopDecisionPolling ~= nil then BridgeStopDecisionPolling() end
    BridgeState.eventSessionGeneration = (BridgeState.eventSessionGeneration or 0) + 1
    BridgeState.decisionPresentationGeneration = (BridgeState.decisionPresentationGeneration or 0) + 1
    BridgeState.resyncBootstrapGeneration = (BridgeState.resyncBootstrapGeneration or 0) + 1
    BridgeState.resyncToken = (BridgeState.resyncToken or 0) + 1
    if BridgeAdvancePhysicalPresentationGeneration ~= nil then BridgeAdvancePhysicalPresentationGeneration("session-boundary") end
    if BridgeAdvancePhysicalTransactionGeneration ~= nil then BridgeAdvancePhysicalTransactionGeneration("session-boundary") end

    if BridgeClearHighlights ~= nil then pcall(BridgeClearHighlights) end
    if BridgeResetSelectionState ~= nil then pcall(BridgeResetSelectionState) end
    if BridgeReturnAttackPresentation ~= nil then pcall(BridgeReturnAttackPresentation, nil) end
    if BridgeClearPreparedPresentationObjects ~= nil then pcall(BridgeClearPreparedPresentationObjects) end
    if BridgeHideMainPriorityControls ~= nil then pcall(BridgeHideMainPriorityControls) end
    if BridgeDestroyTransientControls ~= nil then pcall(BridgeDestroyTransientControls) end

    BridgeState.eventSessionId = nil
    BridgeState.lastDecision = nil
    BridgeState.pendingDecision = nil
    BridgeState.pendingIntent = nil
    BridgeState.unboundPickupIntent = nil
    BridgeState.choiceTransactions = {}
    BridgeState.retiredChoiceDecisionIds = {}
    BridgeState.retiredChoiceDecisionOrder = {}
    BridgeState.lastChoiceAttempt = nil
    BridgeState.eventQueue = {}
    BridgeState.lastReceivedEventSequence = 0
    BridgeState.lastAppliedEventSequence = 0
    BridgeState.lastConsumedEventSequence = 0
    BridgeState.lastStateProjectedEventSequence = 0
    BridgeState.lastPhysicalPresentationEventSequence = 0
    BridgeState.lastAppliedForgeSequence = 0
    BridgeState.currentTurnSeatId = nil
    BridgeState.prioritySeatId = nil
    BridgeState.tableTurnCount = 0
    BridgeState.turnCountsBySeatId = {}
    BridgeState.currentPhase = nil
    BridgeState.phaseSourceEventSequence = 0
    BridgeState.turnSourceEventSequence = 0
    BridgeState.activePlayerSourceEventSequence = 0
    BridgeState.prioritySourceEventSequence = 0
    BridgeState.desyncLatched = false
    BridgeState.desyncLastMessage = nil
    BridgeState.desyncFailureCount = 0
    BridgeState.terminalRecoveryError = nil
    BridgeState.staleDecisionFault = nil
    BridgeState.staleDecisionFaultsByKey = {}
    BridgeState.staleDecisionRetryKey = nil
    BridgeState.staleDecisionRetryCount = 0
    BridgeState.staleDecisionRetryStartedAt = nil
    BridgeState.staleDecisionRetryDeadlineAt = nil
    BridgeState.bootstrapping = false
    BridgeState.resyncInFlight = false
    BridgeState.resyncScheduled = false
    BridgeState.resyncDeferredRetryScheduled = false
    BridgeState.snapshotReconcileInFlight = false
    BridgeState.snapshotReconcilePending = false
    BridgeState.resyncCheckpoint = nil
    BridgeState.resyncMappingTransaction = nil
    BridgeState.resyncMappingTransactionStatus = nil
    BridgeState.resyncMappingTransactionStartedAt = nil
    BridgeState.resyncMappingTransactionCompletedAt = nil
    BridgeState.resyncReconcileStarted = false
    BridgeState.resyncLastBlockingPredicate = nil
    BridgeState.resyncStage = "Idle"
    BridgeState.resyncLastCallbackStage = nil
    BridgeState.resyncLastCallbackAt = nil
    BridgeState.resyncLastCallbackReason = nil
    BridgeState.resyncExpectedCallbackStage = nil
    BridgeState.resyncExpectedCallbackAt = nil
    BridgeState.resyncExpectedCallbackReason = nil
    BridgeState.resyncLastUnobservedCallbackStage = nil
    BridgeState.resyncLastUnobservedCallbackAt = nil
    BridgeState.resyncLastUnobservedCallbackReason = nil
    BridgeState.resyncCompletionContinuation = nil
    BridgeState.resyncCompletionCallback = nil
    BridgeState.resyncCompletionContinuationToken = (BridgeState.resyncCompletionContinuationToken or 0) + 1
    BridgeState.resyncPhysicalRebuildReady = false
    BridgeState.resyncPhysicalValidationPassed = false
    BridgeState.resyncCandidateSnapshot = nil
    BridgeState.resyncStartedAt = nil
    BridgeState.resyncStartedUpdateTick = nil
    BridgeState.resyncStartedCpuAt = nil
    BridgeState.resyncLastStartedAt = nil
    BridgeState.resyncLastStartedCpuAt = nil
    BridgeState.resyncLastStartedUpdateTick = nil
    BridgeState.resyncOrigin = nil
    BridgeState.resyncLastFailureReason = nil
    BridgeState.resyncNoProgressAttempts = 0
    BridgeState.resyncCircuitOpen = false
    BridgeState.schedulerOwner = "NORMAL"
    BridgeState.fastForwardSuspendedByResync = false
    BridgeState.animationRunning = false
    BridgeState.eventDrainTransaction = nil
    BridgeState.eventDrainContinuation = nil
    BridgeState.eventDrainContinuationToken = (BridgeState.eventDrainContinuationToken or 0) + 1
    BridgeState.eventDrainLastContinuation = nil
    BridgeState.yieldPolicyTurnNumber = nil
    BridgeState.yieldPolicyActiveSeatId = nil
    BridgeState.yieldPolicySessionId = nil
    BridgeState.yieldPolicyOwnTurn = false
    BridgeState.pendingCastBySeatId = {}
    BridgeState.libraryExtractionQueueBySeatId = {}
    BridgeState.libraryExtractionActiveBySeatId = {}
    BridgeState.libraryExtractionTransactionBySeatId = {}
    BridgeState.graveyardExtractionActiveBySeatId = {}
    BridgeState.libraryBatchBySeatId = {}
    BridgeState.mulliganBottomQueueBySeatId = {}
    BridgeState.mulliganBottomInsertionActiveBySeatId = {}
    BridgeState.mulliganReturningInstanceIds = {}
    BridgeState.mulliganBottomInstanceIds = {}
    BridgeState.physicalByInstanceId = {}
    BridgeState.physicalInstanceIdByGuid = {}
    BridgeState.physicalContainerByInstanceId = {}
    BridgeState.physicalContainedInstanceIdByGuid = {}
    BridgeState.bootstrapLibraryMappingBySeatId = {}
    BridgeState.physicalSeatByGuid = {}
    BridgeState.physicalZoneByGuid = {}
    BridgeState.cardNameByInstanceId = {}
    BridgeState.authoritativeObjectByInstanceId = {}
    BridgeState.revealedPresentationsByKey = {}
    BridgeState.revealedPresentationOrder = {}
    BridgeState.dismissedRevealKeys = {}
    BridgeState.activeRevealPresentationKey = nil
    BridgeState.stackSummary = {}
    BridgeState.stackObjects = {}
    BridgeState.combatSelectedByGuid = {}
    BridgeState.attackOriginByGuid = {}
    BridgeState.pendingCastBySeatId = {}
    BridgeState.gameEnded = nil
    BridgeState.resultSourceEventId = nil
    BridgeState.resultEventCursor = nil
    BridgeState.resultSessionId = nil
    BridgeState.resultOutcome = nil
    BridgeState.resultReason = nil
    BridgeState.resultPresentationGeneration = 0
    BridgeState.eventPolling = false
    BridgeState.eventRequestInFlight = false
    BridgeState.eventPollScheduled = false
    BridgeState.decisionPollInFlight = false
    BridgeState.decisionPollScheduled = false
    BridgeState.decisionRefreshInFlight = false
    BridgeState.submitting = false
    BridgeState.setupBusy = false
    BridgeState.resetConfirmationArmed = false
    BridgeState.resetConfirmationGuid = nil
    BridgeSetLifecycleState(lifecycleState or BRIDGE_LIFECYCLE_READY_NO_SESSION, reason)
    if BridgeSetStatus ~= nil then BridgeSetStatus("COMPANION READY", "READY TO START A NEW MATCH") end
    if BridgeEnsureSetupControls ~= nil then BridgeEnsureSetupControls() end
    return true
end

function BridgeObserveBridgeHealth(body)
    if body == nil then return end
    local processId = body.bridgeProcessInstanceId
    if processId ~= nil and processId ~= "" then
        if BridgeState.bridgeProcessInstanceId ~= nil
            and BridgeState.bridgeProcessInstanceId ~= processId then
            BridgeState.connectionEpoch = (BridgeState.connectionEpoch or 0) + 1
            BridgeLog(string.format("[Bridge] BRIDGE_PROCESS_EPOCH_CHANGED old=%s new=%s epoch=%s",
                tostring(BridgeState.bridgeProcessInstanceId), tostring(processId), tostring(BridgeState.connectionEpoch)))
            BridgeCleanupLocalSession("bridge-process-changed", BRIDGE_LIFECYCLE_READY_NO_SESSION)
        end
        BridgeState.bridgeProcessInstanceId = processId
    end
    local noSession = body.adapterState == "not_started"
        or body.sessionId == nil or body.sessionId == "session-not-started"
    if noSession then
        BridgeCleanupLocalSession("bridge-reports-no-session", BRIDGE_LIFECYCLE_READY_NO_SESSION)
    elseif body.adapterState == "starting" then
        BridgeState.sessionCleanupApplied = false
        BridgeSetLifecycleState(BRIDGE_LIFECYCLE_STARTING, "bridge-starting")
    elseif body.sessionId ~= nil then
        BridgeState.sessionCleanupApplied = false
        if BridgeState.lifecycleState ~= BRIDGE_LIFECYCLE_RECOVERING then
            BridgeSetLifecycleState(BRIDGE_LIFECYCLE_ACTIVE, "bridge-session-present")
        end
    end
end

function BridgeObjectIsUsable(object)
    if object == nil then return false end
    local ok, valid = pcall(function()
        return object.getGUID() ~= nil
    end)
    return ok and valid == true
end

function BridgeSafeObjectGuid(object)
    if not BridgeObjectIsUsable(object) then return nil end
    local ok, guid = pcall(function() return object.getGUID() end)
    if not ok then return nil end
    return guid
end

function BridgeRegisterPresentationObject(objectOrGuid, kind)
    local guid = type(objectOrGuid) == "string" and objectOrGuid or BridgeSafeObjectGuid(objectOrGuid)
    if guid == nil then return false end
    BridgeState.presentationOnlyGuids[guid] = {kind = kind or "presentation"}
    return true
end

function BridgeUnregisterPresentationObject(objectOrGuid)
    local guid = type(objectOrGuid) == "string" and objectOrGuid or BridgeSafeObjectGuid(objectOrGuid)
    if guid == nil then return false end
    BridgeState.presentationOnlyGuids[guid] = nil
    return true
end

function BridgeIsPresentationOnlyObject(objectOrGuid)
    local guid = type(objectOrGuid) == "string" and objectOrGuid or BridgeSafeObjectGuid(objectOrGuid)
    return guid ~= nil and BridgeState.presentationOnlyGuids[guid] ~= nil
end

function BridgeSafeObjectName(object)
    if not BridgeObjectIsUsable(object) then return nil end
    local ok, name = pcall(function() return object.getName() end)
    if not ok then return nil end
    return tostring(name or "")
end

-- A card's visible name is presentation and may change when an Encoder module
-- displays a transformed face.  Bootstrap identity is the imported/card-data
-- name, captured once per physical object.  Forge's cardName is likewise the
-- stable identity; currentCardName is only for post-mapping presentation.
function BridgePhysicalCanonicalCardName(object)
    local guid = BridgeSafeObjectGuid(object)
    if guid ~= nil and BridgeState.canonicalCardNameByGuid[guid] ~= nil then
        return BridgeState.canonicalCardNameByGuid[guid]
    end
    local canonical = nil
    local ok, data = pcall(function() return object.getData() end)
    if ok and data ~= nil then
        canonical = data.Nickname or data.nickname
    end
    if canonical == nil or tostring(canonical) == "" then canonical = BridgeSafeObjectName(object) end
    canonical = tostring(canonical or "")
    if guid ~= nil and canonical ~= "" then BridgeState.canonicalCardNameByGuid[guid] = canonical end
    return canonical
end

function BridgeSafeObjectCall(object, action)
    if not BridgeObjectIsUsable(object) or action == nil then return false end
    local ok = pcall(action, object)
    return ok
end

local BRIDGE_PHYSICAL_ID_KEY = "bridgeCardInstanceId"
local BRIDGE_PHYSICAL_SESSION_KEY = "bridgeSessionId"

function BridgeReadPhysicalIdentity(object)
    if not BridgeObjectIsUsable(object) or type(object.getVar) ~= "function" then return nil end
    local ok, value = pcall(function() return object.getVar(BRIDGE_PHYSICAL_ID_KEY) end)
    if not ok or value == nil or tostring(value) == "" then return nil end
    return tostring(value)
end

function BridgeWritePhysicalIdentity(object, cardInstanceId)
    if not BridgeObjectIsUsable(object) or cardInstanceId == nil or type(object.setVar) ~= "function" then return end
    pcall(function() object.setVar(BRIDGE_PHYSICAL_ID_KEY, tostring(cardInstanceId)) end)
end

function BridgeReadPhysicalSessionIdentity(object)
    if not BridgeObjectIsUsable(object) or type(object.getVar) ~= "function" then return nil end
    local ok, value = pcall(function() return object.getVar(BRIDGE_PHYSICAL_SESSION_KEY) end)
    if not ok or value == nil or tostring(value) == "" then return nil end
    return tostring(value)
end

function BridgeWritePhysicalSessionIdentity(object, sessionId)
    if not BridgeObjectIsUsable(object) or sessionId == nil or type(object.setVar) ~= "function" then return end
    pcall(function() object.setVar(BRIDGE_PHYSICAL_SESSION_KEY, tostring(sessionId)) end)
end

function BridgeAdvancePhysicalPresentationGeneration(reason)
    BridgeState.currentPhysicalPresentationGeneration =
        (BridgeState.currentPhysicalPresentationGeneration or 0) + 1
    if reason ~= nil then
        BridgeState.lastPhysicalPresentationInvalidationReason = tostring(reason)
    end
end

function BridgePhysicalPresentationIsCurrent(sessionId, generation)
    return sessionId == BridgeState.eventSessionId
        and generation == (BridgeState.physicalTransactionGeneration or 0)
end

function BridgeAdvancePhysicalTransactionGeneration(reason)
    BridgeState.physicalTransactionGeneration = (BridgeState.physicalTransactionGeneration or 0) + 1
    if reason ~= nil then
        BridgeState.lastPhysicalTransactionInvalidationReason = tostring(reason)
    end
    return BridgeState.physicalTransactionGeneration
end

-- A deferred hand decision is owned by the physical transaction that is
-- preventing readiness.  The transaction's terminal callback is the only
-- normal wake-up; timers are diagnostics, not a continuation mechanism.
function BridgeRegisterPhysicalReadinessDependency(decision, reason, detail, seatId)
    if decision == nil then return false end
    local transaction = seatId and BridgeState.libraryExtractionTransactionBySeatId
        and BridgeState.libraryExtractionTransactionBySeatId[seatId] or nil
    local generation = transaction and transaction.generation
        or (BridgeState.physicalTransactionGeneration or 0)
    local existing = BridgeState.physicalReadinessDependency
    if existing ~= nil and not existing.awakened
        and existing.sessionId == BridgeState.eventSessionId
        and existing.sessionGeneration == BridgeState.eventSessionGeneration
        and existing.physicalTransactionGeneration == generation
        and existing.decisionId == decision.decisionId then
        return true
    end
    BridgeState.physicalReadinessDependency = {
        sessionId = BridgeState.eventSessionId,
        sessionGeneration = BridgeState.eventSessionGeneration,
        physicalTransactionGeneration = generation,
        readinessToken = tostring(decision.decisionId) .. ":" .. tostring(generation),
        decisionId = decision.decisionId,
        seatId = seatId,
        reason = reason,
        detail = detail,
        awakened = false
    }
    return true
end

function BridgeWakePhysicalReadinessDependency(generation, reason)
    local dependency = BridgeState.physicalReadinessDependency
    if dependency == nil or dependency.awakened then return false end
    if dependency.sessionId ~= BridgeState.eventSessionId
        or dependency.sessionGeneration ~= BridgeState.eventSessionGeneration
        or dependency.physicalTransactionGeneration ~= generation then
        return false
    end
    dependency.awakened = true
    BridgeState.physicalReadinessDependency = nil
    BridgeLog(string.format("[Bridge] PHYSICAL_READINESS_WAKE token=%s reason=%s",
        tostring(dependency.readinessToken), tostring(reason)))
    if BridgeTryPresentPendingDecision ~= nil and BridgeState.pendingDecision ~= nil then
        BridgeTryPresentPendingDecision("physical-transaction-terminal")
    end
    return true
end

function BridgeRecordLooseCardIdentity(cardInstanceId, guid, seatId, zoneName)
    if cardInstanceId == nil or guid == nil or tostring(guid) == "" then
        BridgeLog("[Bridge] refusing incomplete Forge mapping")
        return false
    end
    local activeSessionId = BridgeState.eventSessionId
    if activeSessionId == nil or activeSessionId == "session-not-started" then
        BridgeLog("[Bridge] refusing Forge mapping without an active session")
        return false
    end
    if BridgeIsPresentationOnlyObject(guid) then
        BridgeLog("[Bridge] refusing Forge mapping for presentation object " .. tostring(guid))
        return false
    end
    local object = BridgeGetLiveObjectByGuid ~= nil and BridgeGetLiveObjectByGuid(guid) or nil
    local advertisedSession = BridgeReadPhysicalSessionIdentity(object)
    if advertisedSession ~= nil and advertisedSession ~= tostring(activeSessionId) then
        BridgeLog("[Bridge] refusing mapping owned by another session guid=" .. tostring(guid)
            .. " objectSession=" .. tostring(advertisedSession)
            .. " activeSession=" .. tostring(activeSessionId))
        return false
    end
    local advertised = BridgeReadPhysicalIdentity(object)
    if advertised ~= nil and advertised ~= tostring(cardInstanceId) then
        BridgeLog("[Bridge] refusing mapping whose physical object advertises another card instance guid="
            .. tostring(guid) .. " advertised=" .. advertised .. " requested=" .. tostring(cardInstanceId))
        return false
    end
    local previousGuid = BridgeState.physicalByInstanceId[cardInstanceId]
    local previousContainer = BridgeState.physicalContainerByInstanceId[cardInstanceId]
    if previousContainer ~= nil then
        if previousContainer.cardGuid ~= nil
            and BridgeState.physicalContainedInstanceIdByGuid[previousContainer.cardGuid] == cardInstanceId then
            BridgeState.physicalContainedInstanceIdByGuid[previousContainer.cardGuid] = nil
            BridgeState.physicalSeatByGuid[previousContainer.cardGuid] = nil
            BridgeState.physicalZoneByGuid[previousContainer.cardGuid] = nil
        end
        BridgeState.physicalContainerByInstanceId[cardInstanceId] = nil
    end
    if BridgeState.physicalSlotByInstanceId ~= nil then
        BridgeState.physicalSlotByInstanceId[cardInstanceId] = nil
    end
    if previousGuid ~= nil and previousGuid ~= guid then
        local previousObject = BridgeGetLiveObjectByGuid ~= nil and BridgeGetLiveObjectByGuid(previousGuid) or nil
        if previousObject ~= nil then
            BridgeLog("[Bridge] refusing to reassign live card instance " .. tostring(cardInstanceId)
                .. " from guid=" .. tostring(previousGuid) .. " to guid=" .. tostring(guid))
            return false
        end
        BridgeState.physicalInstanceIdByGuid[previousGuid] = nil
        BridgeState.physicalSeatByGuid[previousGuid] = nil
        BridgeState.physicalZoneByGuid[previousGuid] = nil
    end
    local previousInstanceId = BridgeState.physicalInstanceIdByGuid[guid]
    if previousInstanceId ~= nil and previousInstanceId ~= cardInstanceId then
        -- A live GUID already owned by another authoritative identity can
        -- never be silently stolen by a same-name token/copy.
        if object ~= nil then
            BridgeLog("[Bridge] refusing to reassign live guid=" .. tostring(guid)
                .. " from card instance=" .. tostring(previousInstanceId)
                .. " to " .. tostring(cardInstanceId))
            return false
        end
        BridgeState.physicalByInstanceId[previousInstanceId] = nil
    end
    local changed = BridgeState.physicalByInstanceId[cardInstanceId] ~= guid
        or BridgeState.physicalInstanceIdByGuid[guid] ~= cardInstanceId
    changed = changed
        or BridgeState.physicalSeatByGuid[guid] ~= seatId
        or BridgeState.physicalZoneByGuid[guid] ~= zoneName
    BridgeState.physicalByInstanceId[cardInstanceId] = guid
    BridgeState.physicalInstanceIdByGuid[guid] = cardInstanceId
    BridgeState.physicalSeatByGuid[guid] = seatId
    BridgeState.physicalZoneByGuid[guid] = zoneName
    BridgeWritePhysicalIdentity(object, cardInstanceId)
    BridgeWritePhysicalSessionIdentity(object, activeSessionId)
    if changed then BridgeAdvancePhysicalPresentationGeneration("card-mapping") end
    if BridgeCaptureCanonicalCardScale ~= nil then BridgeCaptureCanonicalCardScale(object) end
    return true
end

-- Record the exact identity of a card that is currently contained by a
-- native TTS Deck. The contained card GUID is stable even though
-- getObjectFromGUID(cardGuid) returns nil until the card is extracted.
function BridgeRecordContainedCardIdentity(cardInstanceId, containingDeckGuid, containedCardGuid, seatId, zoneName, cardName)
    if cardInstanceId == nil or containingDeckGuid == nil or containedCardGuid == nil
        or tostring(containingDeckGuid) == "" or tostring(containedCardGuid) == "" then
        BridgeLog("[Bridge] refusing incomplete contained Forge mapping")
        return false
    end
    local activeSessionId = BridgeState.eventSessionId
    if activeSessionId == nil or activeSessionId == "session-not-started" then
        BridgeLog("[Bridge] refusing contained Forge mapping without an active session")
        return false
    end
    local existingInstanceId = BridgeState.physicalContainedInstanceIdByGuid[containedCardGuid]
    if existingInstanceId ~= nil and existingInstanceId ~= cardInstanceId then
        BridgeLog("[Bridge] refusing contained GUID reassignment guid=" .. tostring(containedCardGuid)
            .. " existingInstance=" .. tostring(existingInstanceId)
            .. " requestedInstance=" .. tostring(cardInstanceId))
        return false
    end
    local previousGuid = BridgeState.physicalByInstanceId[cardInstanceId]
    if previousGuid ~= nil then
        BridgeState.physicalInstanceIdByGuid[previousGuid] = nil
        BridgeState.physicalSeatByGuid[previousGuid] = nil
        BridgeState.physicalZoneByGuid[previousGuid] = nil
        BridgeState.physicalByInstanceId[cardInstanceId] = nil
    end
    local previousContainer = BridgeState.physicalContainerByInstanceId[cardInstanceId]
    if previousContainer ~= nil and previousContainer.cardGuid ~= containedCardGuid
        and BridgeState.physicalContainedInstanceIdByGuid[previousContainer.cardGuid] == cardInstanceId then
        BridgeState.physicalContainedInstanceIdByGuid[previousContainer.cardGuid] = nil
    end
    local changed = previousContainer == nil
        or previousContainer.deckGuid ~= containingDeckGuid
        or previousContainer.cardGuid ~= containedCardGuid
        or previousContainer.seatId ~= seatId
        or previousContainer.zoneName ~= zoneName
    BridgeState.physicalContainerByInstanceId[cardInstanceId] = {
        deckGuid = containingDeckGuid,
        cardGuid = containedCardGuid,
        seatId = seatId,
        zoneName = zoneName
    }
    if BridgeState.physicalSlotByInstanceId ~= nil then
        BridgeState.physicalSlotByInstanceId[cardInstanceId] = nil
    end
    BridgeState.physicalContainedInstanceIdByGuid[containedCardGuid] = cardInstanceId
    BridgeState.physicalSeatByGuid[containedCardGuid] = seatId
    BridgeState.physicalZoneByGuid[containedCardGuid] = zoneName
    if cardName ~= nil and cardName ~= "" then
        BridgeState.cardNameByInstanceId[cardInstanceId] = cardName
    end
    if changed then BridgeAdvancePhysicalPresentationGeneration("card-contained") end
    return true
end

function BridgeFindContainedCardEntry(cardInstanceId, expectedZone)
    local mapping = BridgeState.physicalContainerByInstanceId[cardInstanceId]
    if mapping == nil then return nil, nil, "no contained mapping for card instance" end
    if expectedZone ~= nil and mapping.zoneName ~= nil and mapping.zoneName ~= expectedZone then
        return nil, nil, "contained mapping is in " .. tostring(mapping.zoneName)
    end
    local deck = BridgeGetLiveObjectByGuid(mapping.deckGuid)
    if deck == nil or deck.tag ~= "Deck" then
        return nil, nil, "containing Deck is unavailable"
    end
    local entries = {}
    local ok = pcall(function() entries = deck.getObjects() or {} end)
    if not ok then return nil, nil, "containing Deck inventory is unavailable" end
    if mapping.locatorType == "SLOT_LOCATOR" then
        local targetIndex = tonumber(mapping.slotIndex)
        local targetName = BridgeNormalizeCardName(mapping.cardName or BridgeState.cardNameByInstanceId[cardInstanceId])
        local match = nil
        for _, entry in ipairs(entries) do
            local entryIndex = tonumber(entry and entry.index or -1)
            local entryName = BridgeNormalizeCardName(entry and (entry.nickname or entry.name or entry.Name))
            if entryIndex == targetIndex and entryName == targetName then
                if match ~= nil then return nil, nil, "slot locator is ambiguous" end
                match = entry
            end
        end
        if match == nil then return nil, nil, "slot locator no longer matches Deck" end
        mapping.index = targetIndex
        return deck, match, nil
    end
    for _, entry in ipairs(entries) do
        local guid = entry and (entry.guid or entry.GUID) or nil
        if tostring(guid or "") == tostring(mapping.cardGuid) then
            mapping.index = entry.index
            return deck, entry, nil
        end
    end
    return nil, nil, "contained card GUID is absent from its Deck"
end

function BridgeRecordSlotLibraryIdentity(cardInstanceId, deckGuid, slotIndex, seatId, zoneName, cardName, bindingGeneration)
    if cardInstanceId == nil or deckGuid == nil or tonumber(slotIndex) == nil then return false end
    BridgeState.physicalContainerByInstanceId = BridgeState.physicalContainerByInstanceId or {}
    BridgeState.physicalSlotByInstanceId = BridgeState.physicalSlotByInstanceId or {}
    local previous = BridgeState.physicalContainerByInstanceId[cardInstanceId]
    BridgeState.physicalContainerByInstanceId[cardInstanceId] = {
        deckGuid = deckGuid, cardGuid = nil, slotIndex = tonumber(slotIndex),
        locatorType = "SLOT_LOCATOR", seatId = seatId, zoneName = zoneName,
        cardName = cardName, bindingGeneration = bindingGeneration
    }
    BridgeState.physicalSlotByInstanceId[cardInstanceId] = BridgeState.physicalContainerByInstanceId[cardInstanceId]
    BridgeState.cardNameByInstanceId[cardInstanceId] = cardName
    if previous == nil or previous.slotIndex ~= tonumber(slotIndex) or previous.bindingGeneration ~= bindingGeneration then
        BridgeAdvancePhysicalPresentationGeneration("card-slot-contained")
    end
    return true
end

-- Native Deck indices are only meaningful for the observation that produced
-- them.  After a Deck mutation, refresh all remaining SLOT locators from one
-- current inventory observation before allowing another extraction.  Matching
-- is deliberately by canonical card name and deterministic instance/GUID
-- ordering; Forge CardInstanceId remains the authoritative identity.
function BridgeRefreshLibrarySlotBindings(deckGuid)
    if deckGuid == nil then return false, "library Deck has no GUID" end
    local deck = BridgeGetLiveObjectByGuid(deckGuid)
    if deck == nil or deck.tag ~= "Deck" then return false, "library Deck is unavailable" end
    local entries = {}
    local ok = pcall(function() entries = deck.getObjects() or {} end)
    if not ok then return false, "library Deck inventory is unavailable" end
    local byName = {}
    for _, entry in ipairs(entries) do
        local name = BridgeNormalizeCardName(entry and (entry.nickname or entry.name or entry.Name))
        byName[name] = byName[name] or {}
        table.insert(byName[name], entry)
    end
    local mappings = {}
    for instanceId, mapping in pairs(BridgeState.physicalSlotByInstanceId or {}) do
        if mapping.deckGuid == deckGuid then
            local name = BridgeNormalizeCardName(mapping.cardName or BridgeState.cardNameByInstanceId[instanceId])
            mappings[name] = mappings[name] or {}
            table.insert(mappings[name], {instanceId = instanceId, mapping = mapping})
        end
    end
    for name, items in pairs(mappings) do
        local available = byName[name] or {}
        table.sort(items, function(a, b) return tostring(a.instanceId) < tostring(b.instanceId) end)
        table.sort(available, function(a, b)
            return (tonumber(a and a.index or -1) or -1) < (tonumber(b and b.index or -1) or -1)
        end)
        if #items > #available then return false, "slot locator cannot be rebound uniquely" end
        for index, item in ipairs(items) do
            local entry = available[index]
            local slot = tonumber(entry and entry.index or -1) or -1
            if slot < 0 then return false, "library entry has no usable native index" end
            item.mapping.slotIndex = slot
            item.mapping.index = slot
            item.mapping.bindingGeneration = (item.mapping.bindingGeneration or 0) + 1
        end
    end
    return true, nil
end

function BridgeRefreshContainedMappingsAfterDeckMutation(deckGuid)
    if deckGuid == nil then return end
    BridgeState.libraryBindingGenerationBySeatId = BridgeState.libraryBindingGenerationBySeatId or {}
    for instanceId, mapping in pairs(BridgeState.physicalSlotByInstanceId or {}) do
        if mapping.deckGuid == deckGuid then
            BridgeState.libraryBindingGenerationBySeatId[mapping.seatId] =
                (BridgeState.libraryBindingGenerationBySeatId[mapping.seatId] or 0) + 1
        end
    end
    -- Keep the logical slot bindings, but mark their native indices stale and
    -- refresh them from the post-mutation Deck inventory when it is still
    -- addressable.  Extraction also refreshes defensively immediately before
    -- taking a SLOT locator.
    BridgeRefreshLibrarySlotBindings(deckGuid)
    local recovered = {}
    for instanceId, mapping in pairs(BridgeState.physicalContainerByInstanceId or {}) do
        if mapping.deckGuid == deckGuid and mapping.cardGuid ~= nil then
            local object = BridgeGetLiveObjectByGuid(mapping.cardGuid)
            if object ~= nil and object.tag == "Card" then
                table.insert(recovered, {
                    instanceId = instanceId,
                    guid = mapping.cardGuid,
                    seatId = mapping.seatId,
                    zoneName = mapping.zoneName,
                    cardName = BridgeState.cardNameByInstanceId[instanceId]
                })
            end
        end
    end
    for _, item in ipairs(recovered) do
        BridgeRecordLooseCardIdentity(item.instanceId, item.guid, item.seatId, item.zoneName)
        BridgeLog(string.format("[Bridge] contained card became loose after Deck mutation instance=%s guid=%s deckGuid=%s",
            tostring(item.instanceId), tostring(item.guid), tostring(deckGuid)))
    end
end

function BridgeBeginTokenMaterialization(cardInstanceId)
    if cardInstanceId == nil then return false, "token has no Forge CardInstanceId" end
    local current = BridgeState.tokenMaterializationByInstanceId[cardInstanceId]
    if current ~= nil and (current.state == "SPAWNING" or current.state == "BOUND") then
        return false, current.state
    end
    BridgeState.tokenMaterializationByInstanceId[cardInstanceId] = {
        state = "SPAWNING", sessionId = BridgeState.eventSessionId, epoch = BRIDGE_RUNTIME_EPOCH_LOCAL
    }
    return true, "SPAWNING"
end

function BridgeTokenMaterializationIsCurrent(cardInstanceId, sessionId, epoch)
    local current = BridgeState.tokenMaterializationByInstanceId[cardInstanceId]
    return current ~= nil and current.state == "SPAWNING"
        and current.sessionId == sessionId and current.epoch == epoch
        and BridgeState.eventSessionId == sessionId and BridgeRuntimeIsCurrent(epoch)
end

function BridgeBindTokenMaterialization(event, object, row, sessionId, epoch)
    if not BridgeTokenMaterializationIsCurrent(event.cardInstanceId, sessionId, epoch) then
        return false, "stale token import callback"
    end
    local guid = BridgeSafeObjectGuid(object)
    if guid == nil then return false, "token import returned no live TTS GUID" end
    local existingInstanceId = BridgeState.physicalInstanceIdByGuid[guid]
    if existingInstanceId ~= nil and existingInstanceId ~= event.cardInstanceId then
        -- Never steal a live physical object from another Forge card. Importer
        -- callbacks can race a prior token import and return its object; that
        -- is a presentation failure for this token, not a game-state desync.
        BridgeState.tokenMaterializationByInstanceId[event.cardInstanceId].state = "FAILED"
        BridgeLog("[Bridge] token import rejected duplicate GUID=" .. tostring(guid)
            .. " requested=" .. tostring(event.cardInstanceId)
            .. " alreadyBound=" .. tostring(existingInstanceId))
        BridgeScheduleSnapshotReconcile("duplicate token importer GUID")
        return false, "duplicate token importer GUID"
    end
    -- Bind the exact Forge identity before moving the object. Snapshot and
    -- event reconciliation now see BOUND instead of creating a second token.
    local recorded, recordError = BridgeRecordLooseCardIdentity(event.cardInstanceId, guid, event.seatId, "battlefield")
    if not recorded then
        BridgeState.tokenMaterializationByInstanceId[event.cardInstanceId].state = "FAILED"
        return false, recordError or "token identity registration failed"
    end
    BridgeState.tokenMaterializationByInstanceId[event.cardInstanceId].state = "BOUND"
    local moved, moveError = BridgeMoveToBattlefield(event, object, row)
    if not moved then
        -- Binding is provisional until the art-bearing object reaches the
        -- authoritative battlefield position.  A failed placement must not
        -- leave the lifecycle stuck in BOUND or make a later snapshot create
        -- a second physical token for the same Forge instance.
        BridgeState.tokenMaterializationByInstanceId[event.cardInstanceId].state = "FAILED"
        if BridgeState.physicalByInstanceId[event.cardInstanceId] == guid then
            BridgeState.physicalByInstanceId[event.cardInstanceId] = nil
        end
        if BridgeState.physicalInstanceIdByGuid[guid] == event.cardInstanceId then
            BridgeState.physicalInstanceIdByGuid[guid] = nil
        end
        BridgeState.physicalSeatByGuid[guid] = nil
        BridgeState.physicalZoneByGuid[guid] = nil
        BridgeAdvancePhysicalPresentationGeneration("token-mapping-removed")
        BridgeSafeObjectCall(object, function(card) card.destruct() end)
        return false, moveError
    end
    return true, nil
end

function BridgeRecordLibraryContainedState(cardInstanceId, seatId, cardName, containingDeck, containedCardGuid)
    if cardInstanceId == nil then return false end
    if containingDeck ~= nil and containedCardGuid ~= nil then
        local deckGuid = BridgeSafeObjectGuid(containingDeck)
        if deckGuid ~= nil then
            return BridgeRecordContainedCardIdentity(
                cardInstanceId, deckGuid, containedCardGuid, seatId, "library", cardName)
        end
    end
    local existingGuid = BridgeState.physicalByInstanceId[cardInstanceId]
    if existingGuid ~= nil then
        BridgeState.physicalInstanceIdByGuid[existingGuid] = nil
        BridgeState.physicalSeatByGuid[existingGuid] = nil
        BridgeState.physicalZoneByGuid[existingGuid] = nil
        BridgeState.physicalTappedByGuid[existingGuid] = nil
        BridgeAdvancePhysicalPresentationGeneration("card-contained")
    end
    local existingContainer = BridgeState.physicalContainerByInstanceId[cardInstanceId]
    if existingContainer ~= nil then
        if BridgeState.physicalContainedInstanceIdByGuid[existingContainer.cardGuid] == cardInstanceId then
            BridgeState.physicalContainedInstanceIdByGuid[existingContainer.cardGuid] = nil
        end
        BridgeState.physicalContainerByInstanceId[cardInstanceId] = nil
        BridgeState.physicalSeatByGuid[existingContainer.cardGuid] = nil
        BridgeState.physicalZoneByGuid[existingContainer.cardGuid] = nil
        BridgeAdvancePhysicalPresentationGeneration("card-contained-library")
    end
    BridgeState.physicalByInstanceId[cardInstanceId] = nil
    if BridgeState.physicalSlotByInstanceId ~= nil then
        BridgeState.physicalSlotByInstanceId[cardInstanceId] = nil
    end
    if cardName ~= nil and cardName ~= "" then
        BridgeState.cardNameByInstanceId[cardInstanceId] = cardName
    end
    return true
end

function BridgeTraceStart(marker, detail)
    local message = nil
    if detail ~= nil and tostring(detail) ~= "" then
        message = "[Bridge] " .. tostring(marker) .. " " .. tostring(detail)
    else
        message = "[Bridge] " .. tostring(marker)
    end
    BridgeLog(message)
end

function BridgeRunTraced(marker, action)
    if action == nil then return false end
    local handler = function(err) return tostring(err) end
    if debug ~= nil and debug.traceback ~= nil then
        handler = debug.traceback
    end
    local ok, err = xpcall(action, handler)
    if ok then return true end
    BridgeTraceStart(tostring(marker) .. " ERROR", tostring(err))
    BridgeShowError(tostring(marker) .. " failed; inspect Lua log")
    return false
end

function BridgeGetLiveObjectByGuid(guid)
    if guid == nil then return nil end
    local ok, object = pcall(function() return getObjectFromGUID(guid) end)
    if not ok or object == nil then return nil end
    if not BridgeObjectIsUsable(object) then return nil end
    return object
end

function BridgeTryGetSeatPlayer(seatId)
    local seat = BRIDGE_SEATS[seatId]
