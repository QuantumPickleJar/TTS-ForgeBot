-- BEGIN GENERATED SOURCE: 00-config.lua
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
-- A queue head that cannot start for this long is a scheduler fault worth
-- recording.  It is intentionally diagnostic-only; authoritative events are
-- never dropped or cursor-advanced by the watchdog.
BRIDGE_EVENT_DRAIN_STALL_SECONDS = 2.0
BRIDGE_RESYNC_PHYSICAL_QUEUE_GRACE_SECONDS = 1.0
BRIDGE_RESYNC_STALL_SECONDS = 30.0
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
BRIDGE_SCRIPT_REVISION = "2026-08-30-u2-gameplay-repair"

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
        resyncScheduled = BridgeState.resyncScheduled == true,
        resyncOrigin = BridgeState.resyncOrigin,
        resyncStartedAt = BridgeState.resyncStartedAt,
        resyncDeferredReason = BridgeState.resyncDeferredReason,
        resyncDeferredSince = BridgeState.resyncDeferredSince,
        resyncDeferredRetryScheduled = BridgeState.resyncDeferredRetryScheduled == true,
        resyncWatchdogToken = BridgeState.resyncWatchdogToken,
        resyncLifecycle = BridgeState.resyncLifecycle or {},
        resyncBootstrapGeneration = BridgeState.resyncBootstrapGeneration,
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
        generation = generation, origin = origin,
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

-- Return the actual fence preventing the queue head from starting.  This is
-- deliberately kept separate from the event cursor: a non-empty queue with a
-- stagnant cursor is only useful diagnostically when the scheduler says why
-- it is not being entered.
function BridgeEventDrainBlockReason()
    local queue = BridgeState.eventQueue or {}
    if #queue == 0 then return "queue_empty" end
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
    resyncOrigin = BridgeState.resyncOrigin,
        resyncRootCause = BridgeState.resyncRootCause,
        resyncLastFailureReason = BridgeState.resyncLastFailureReason,
        resyncCircuitOpen = BridgeState.resyncCircuitOpen == true,
        schedulerOwner = BridgeState.schedulerOwner,
        lastSnapshotSupersededRange = BridgeState.lastSnapshotSupersededRange,
        resyncStartedAt = BridgeState.resyncStartedAt,
        resyncDeferredReason = BridgeState.resyncDeferredReason,
        resyncDeferredSince = BridgeState.resyncDeferredSince,
        resyncDeferredRetryScheduled = BridgeState.resyncDeferredRetryScheduled == true,
        resyncWatchdogToken = BridgeState.resyncWatchdogToken,
        resyncBootstrapGeneration = BridgeState.resyncBootstrapGeneration
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

function BridgePerformanceDiagnosticPayload()
    local summary = BridgeState.performanceSummary or {}
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
    return {
        performanceSummary = summary,
        recentTtsTrace = BridgePerformanceTraceSnapshot(),
        diagnosticCaptureLifecycle = BridgeState.diagnosticCaptureLifecycle or {},
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
        resyncLifecycle = BridgeState.resyncLifecycle or {},
        eventDrainDiagnostics = BridgeEventDrainQueueState()
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
    Wait.time(function()
        if not BridgeRuntimeIsCurrent(epoch) then return end
        callback()
    end, delay)
end

function BridgeWaitFrames(callback, frames)
    local epoch = BRIDGE_RUNTIME_EPOCH_LOCAL
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
local _all = getAllObjects
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
    decisionPollGeneration = 0,
    decisionPresentationGeneration = 0,
    decisionPollInFlight = false,
    decisionPollScheduled = false,
    decisionPollScheduledAt = nil,
    decisionPollDueAt = nil,
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
    eventCommitWatchdog = {
        eventSequence = nil,
        successfulApplyAttemptsWithoutCommit = 0,
        firstAttemptTimestamp = nil,
        lastAbortReason = nil
    },
    eventDrainTransaction = nil,
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
    renderedDecisionPresentationKey = nil,
    renderedDecisionPhysicalGeneration = nil,
    physicalByInstanceId = {},
    physicalInstanceIdByGuid = {},
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
    resyncStage = "Idle",
    resyncStageChangedAt = nil,
    resyncAttempt = 0,
    resyncRootCause = nil,
    resyncLastFailureReason = nil,
    resyncLastProgressAt = nil,
    resyncNoProgressAttempts = 0,
    resyncCircuitOpen = false,
    lastSnapshotSupersededRange = nil,
    resyncSnapshotFingerprint = nil,
    resyncSnapshotRepeatCount = 0,
    resyncMappingTransaction = nil,
    resyncReconcileStarted = false,
    resyncLastBlockingPredicate = nil,
    resyncOrigin = nil,
    schedulerOwner = "NORMAL",
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
    BridgeState.setupStage = stage
    BridgeSetupTrace(stage, detail)
    local labels = {
        READING_DECKS = "Reading decks…",
        CONTACTING_BRIDGE = "Contacting Bridge…",
        VALIDATING_DECKS = "Validating decks…",
        STARTING_FORGE = "Starting Forge…",
        SETUP_STATE_VALIDATED = "Validating setup…"
    }
    if BridgeSetStatus ~= nil and labels[stage] ~= nil then BridgeSetStatus(labels[stage], detail or "") end
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
        [BRIDGE_LIFECYCLE_ACTIVE] = true,
        [BRIDGE_LIFECYCLE_RECOVERING] = true,
        [BRIDGE_LIFECYCLE_START_FAILED] = true
    },
    CONFIRM_NEW_MATCH = {
        [BRIDGE_LIFECYCLE_DISCONNECTED] = true,
        [BRIDGE_LIFECYCLE_READY_NO_SESSION] = true,
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
        if BridgeEnsureSetupControls ~= nil then BridgeEnsureSetupControls() end
        return false
    end

    BridgeState.sessionCleanupApplied = true
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
    BridgeState.bootstrapping = false
    BridgeState.resyncInFlight = false
    BridgeState.resyncScheduled = false
    BridgeState.resyncDeferredRetryScheduled = false
    BridgeState.snapshotReconcileInFlight = false
    BridgeState.snapshotReconcilePending = false
    BridgeState.resyncCheckpoint = nil
    BridgeState.resyncMappingTransaction = nil
    BridgeState.resyncReconcileStarted = false
    BridgeState.resyncLastBlockingPredicate = nil
    BridgeState.resyncStage = "Idle"
    BridgeState.resyncStartedAt = nil
    BridgeState.resyncOrigin = nil
    BridgeState.resyncLastFailureReason = nil
    BridgeState.resyncNoProgressAttempts = 0
    BridgeState.resyncCircuitOpen = false
    BridgeState.schedulerOwner = "NORMAL"
    BridgeState.fastForwardSuspendedByResync = false
    BridgeState.animationRunning = false
    BridgeState.eventDrainTransaction = nil
    BridgeState.yieldPolicyTurnNumber = nil
    BridgeState.yieldPolicyActiveSeatId = nil
    BridgeState.yieldPolicySessionId = nil
    BridgeState.yieldPolicyOwnTurn = false
    BridgeState.pendingCastBySeatId = {}
    BridgeState.libraryExtractionQueueBySeatId = {}
    BridgeState.libraryExtractionActiveBySeatId = {}
    BridgeState.libraryBatchBySeatId = {}
    BridgeState.mulliganBottomQueueBySeatId = {}
    BridgeState.mulliganBottomInsertionActiveBySeatId = {}
    BridgeState.mulliganReturningInstanceIds = {}
    BridgeState.mulliganBottomInstanceIds = {}
    BridgeState.physicalByInstanceId = {}
    BridgeState.physicalInstanceIdByGuid = {}
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

function BridgeRecordLibraryContainedState(cardInstanceId, seatId, cardName)
    if cardInstanceId == nil then return end
    local existingGuid = BridgeState.physicalByInstanceId[cardInstanceId]
    if existingGuid ~= nil then
        BridgeState.physicalInstanceIdByGuid[existingGuid] = nil
        BridgeState.physicalSeatByGuid[existingGuid] = nil
        BridgeState.physicalZoneByGuid[existingGuid] = nil
        BridgeState.physicalTappedByGuid[existingGuid] = nil
        BridgeAdvancePhysicalPresentationGeneration("card-contained")
    end
    BridgeState.physicalByInstanceId[cardInstanceId] = nil
    if cardName ~= nil and cardName ~= "" then
        BridgeState.cardNameByInstanceId[cardInstanceId] = cardName
    end
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
-- END GENERATED SOURCE: 00-config.lua
-- BEGIN GENERATED SOURCE: 10-state-diagnostics.lua
    if seat == nil then
        return nil, "unknown configured seat " .. tostring(seatId)
    end
    local color = seat.ttsColor
    if color == nil or color == "" then
        return nil, "seat " .. tostring(seatId) .. " has no configured TTS color"
    end
    -- Player[color] is TTS userdata, and its index operation can throw while
    -- the seat is being reassigned/disconnected.  This is a presentation
    -- lookup, so never let a transient TTS seat invalidate Forge's decision.
    local playerOk, playerOrError = pcall(function() return Player[color] end)
    if not playerOk then
        return nil, "cannot access TTS player color " .. tostring(color) .. " for seat " .. tostring(seatId)
    end
    local player = playerOrError
    if player == nil then
        return nil, "TTS player color " .. tostring(color) .. " is unavailable for seat " .. tostring(seatId)
    end
    return player, nil
end

function BridgeTryGetSeatHandObjects(seatId)
    local player, playerError = BridgeTryGetSeatPlayer(seatId)
    if player == nil then return nil, playerError end
    local ok, handObjects = pcall(function() return player.getHandObjects() end)
    if not ok then
        return nil, "cannot access hand objects for seat " .. tostring(seatId)
    end
    return handObjects or {}, nil
end

function BridgeBuildSeatHandGuidSet(seatId)
    local handObjects, handError = BridgeTryGetSeatHandObjects(seatId)
    if handObjects == nil then
        return {}, handError
    end
    local handGuids = {}
    for _, handObject in ipairs(handObjects) do
        local guid = BridgeSafeObjectGuid(handObject)
        if guid ~= nil then
            handGuids[guid] = true
        end
    end
    return handGuids, nil
end

function BridgeTryGetSeatHandTransform(seatId)
    local player, playerError = BridgeTryGetSeatPlayer(seatId)
    if player == nil then return nil, playerError end
    local ok, hand = pcall(function() return player.getHandTransform(1) end)
    if not ok or hand == nil or hand.position == nil then
        return nil, "cannot access hand transform for seat " .. tostring(seatId)
    end
    return hand, nil
end

function BridgeSeatIdForSeatConfig(targetSeat)
    for seatId, seat in pairs(BRIDGE_SEATS) do
        if seat == targetSeat then return seatId end
    end
    return nil
end

function BridgeExpectedCardNamesForSeatSnapshot(seatSnapshot)
    local expected = {}
    for _, zone in ipairs(seatSnapshot and seatSnapshot.zones or {}) do
        for _, card in ipairs(zone.cards or {}) do
            local normalized = BridgeNormalizeCardName(card.cardName)
            if normalized ~= "" then expected[normalized] = true end
        end
    end
    return expected
end

function BridgeBuildGameCardContext(snapshot)
    local context = {
        expectedCardNamesBySeat = {},
        handGuidsBySeat = {}
    }
    for _, seatSnapshot in ipairs(snapshot and snapshot.seats or {}) do
        context.expectedCardNamesBySeat[seatSnapshot.seatId] = BridgeExpectedCardNamesForSeatSnapshot(seatSnapshot)
    end
    return context
end

function BridgeCardFootprintLooksLikeMtg(object)
    local ok, bounds = pcall(function() return object.getBoundsNormalized() end)
    if not ok or bounds == nil or bounds.size == nil then
        return true
    end
    local size = bounds.size
    local x = math.abs(tonumber(size.x) or 0)
    local z = math.abs(tonumber(size.z) or 0)
    local width = math.min(x, z)
    local length = math.max(x, z)
    if width <= 0 or length <= 0 then
        return true
    end
    return width >= 0.85 and width <= 1.45 and length >= 1.2 and length <= 2.2
end

function BridgeCardMetadataLooksLikeMtg(object)
    local ok, data = pcall(function() return object.getData() end)
    if not ok or data == nil then return false end
    local customDeck = data.CustomDeck
    if customDeck == nil then return false end
    return next(customDeck) ~= nil
end

function IsGameCardCandidate(object, seatId, context)
    if not BridgeObjectIsUsable(object) then return false end
    if BridgeIsPresentationOnlyObject(object) then return false end
    if object.tag ~= "Card" and object.tag ~= "Deck" then return false end

    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then return false end

    local guid = BridgeSafeObjectGuid(object)
    if guid == nil then return false end

    if seat.excludeCardGuids ~= nil and seat.excludeCardGuids[guid] == true then
        return false
    end
    if seat.includeCardGuids ~= nil and seat.includeCardGuids[guid] == true then
        return true
    end

    if object.tag == "Deck" then
        return BridgeObjectIsOnSeatSide(object, seat)
    end

    if BridgeState.physicalSeatByGuid[guid] == seatId then
        return true
    end

    -- A card in a TTS hand does not reliably have a position on its owner's
    -- half of the table.  Establish hand ownership before spatial filtering.
    local handGuidsBySeat = context and context.handGuidsBySeat or nil
    local seatHandGuids = handGuidsBySeat and handGuidsBySeat[seatId] or nil
    if seatHandGuids == nil then
        seatHandGuids = BridgeBuildSeatHandGuidSet(seatId)
        if handGuidsBySeat ~= nil then handGuidsBySeat[seatId] = seatHandGuids end
    end
    if seatHandGuids ~= nil and seatHandGuids[guid] == true then return true end

    -- Never use a matching name alone to claim a card from the other seat.
    -- This check follows hand membership so hand objects remain discoverable.
    if not BridgeObjectIsOnSeatSide(object, seat) then return false end

    local expectedBySeat = context and context.expectedCardNamesBySeat or nil
    local expectedNames = expectedBySeat and expectedBySeat[seatId] or nil
    if expectedNames ~= nil and next(expectedNames) ~= nil then
        local normalized = BridgeNormalizeCardName(BridgePhysicalCanonicalCardName(object))
        return expectedNames[normalized] == true
    end
    if BridgeCardMetadataLooksLikeMtg(object) then
        return true
    end
    return BridgeCardFootprintLooksLikeMtg(object)
end

function BridgeDeckContainsCardName(deck, expectedName)
    if not BridgeObjectIsUsable(deck) then return false end
    local containedCards = {}
    local containedOk = pcall(function() containedCards = deck.getObjects() or {} end)
    if not containedOk then return false end
    for _, contained in ipairs(containedCards) do
        if BridgeCardNameMatches(contained.nickname or contained.name, expectedName) then
            return true
        end
    end
    return false
end

function BridgeFindLibraryDeckCandidatesForSeat(seatId, objectSnapshot)
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then return {} end
    local candidates = {}
    for _, object in ipairs(objectSnapshot or _all()) do
        if BridgeObjectIsUsable(object) and object.tag == "Deck" and BridgeObjectIsOnSeatSide(object, seat) then
            table.insert(candidates, object)
        end
    end
    return candidates
end

function BridgeFindSingleCardLibraryCandidateForSeat(seatId, objectSnapshot)
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then return nil end
    local anchor = BridgeGetLiveObjectByGuid(seat.libraryZoneGuid)
    if anchor == nil then return nil end
    local okAnchor, anchorPosition = pcall(function() return anchor.getPosition() end)
    if not okAnchor or anchorPosition == nil then return nil end
    local nearest = nil
    local nearestDistance = nil
    local radius = (seat.libraryAssetRadius or 4) + 0.75
    for _, object in ipairs(objectSnapshot or _all()) do
        if BridgeObjectIsUsable(object) and object.tag == "Card"
            and not BridgeIsPresentationOnlyObject(object) then
            local guid = BridgeSafeObjectGuid(object)
            local mappedZone = guid and BridgeState.physicalZoneByGuid[guid] or nil
            if guid ~= nil and (mappedZone == nil or mappedZone == "library") then
                local okPosition, position = pcall(function() return object.getPosition() end)
                if okPosition and position ~= nil then
                    local dx = position.x - anchorPosition.x
                    local dz = position.z - anchorPosition.z
                    local distance = dx * dx + dz * dz
                    if distance <= radius * radius
                        and (nearestDistance == nil or distance < nearestDistance) then
                        nearest = object
                        nearestDistance = distance
                    end
                end
            end
        end
    end
    return nearest
end

function BridgeSelectNearestDeckCandidate(seat, candidates)
    if seat == nil or candidates == nil or #candidates == 0 then return nil end
    local libraryAnchor = BridgeGetLiveObjectByGuid(seat.libraryZoneGuid)
    if libraryAnchor == nil then return nil end
    local okAnchor, anchorPosition = pcall(function() return libraryAnchor.getPosition() end)
    if not okAnchor or anchorPosition == nil then return nil end

    local nearest = nil
    local nearestDistance = nil
    local secondDistance = nil
    for _, candidate in ipairs(candidates) do
        if BridgeObjectIsUsable(candidate) then
            local okPosition, position = pcall(function() return candidate.getPosition() end)
            if okPosition and position ~= nil then
                local dx = position.x - anchorPosition.x
                local dz = position.z - anchorPosition.z
                local squaredDistance = dx * dx + dz * dz
                if nearestDistance == nil or squaredDistance < nearestDistance then
                    secondDistance = nearestDistance
                    nearestDistance = squaredDistance
                    nearest = candidate
                elseif secondDistance == nil or squaredDistance < secondDistance then
                    secondDistance = squaredDistance
                end
            end
        end
    end

    if nearest == nil or nearestDistance == nil then return nil end
    local maxRadius = (seat.libraryAssetRadius or 4) + 2
    local nearAnchor = nearestDistance <= (maxRadius * maxRadius)
    local clearlyNearest = secondDistance == nil or (secondDistance - nearestDistance) > 0.25
    if nearAnchor or clearlyNearest then
        return nearest
    end
    return nil
end

function BridgeResolveSeatLibraryDeck(seatId, objectSnapshot)
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then return nil, {}, "unknown seat" end
    local candidates = BridgeFindLibraryDeckCandidatesForSeat(seatId, objectSnapshot)

    local configured = BridgeGetLiveObjectByGuid(seat.libraryZoneGuid)
    if configured ~= nil and configured.tag == "Deck" and BridgeObjectIsOnSeatSide(configured, seat) then
        return configured, candidates, nil
    end

    if #candidates == 1 then
        return candidates[1], candidates, nil
    end
    if #candidates > 1 then
        local nearest = BridgeSelectNearestDeckCandidate(seat, candidates)
        if nearest ~= nil then
            return nearest, candidates, nil
        end
    end
    if #candidates == 0 then
        -- TTS collapses a one-card Deck into a loose Card.  That Card is still
        -- the physical library, but it must only be promoted back to a Deck by
        -- a verified insertion; proximity alone is never enough to clear a
        -- Forge identity mapping.
        local singleCard = BridgeFindSingleCardLibraryCandidateForSeat(seatId, objectSnapshot)
        if singleCard ~= nil then return singleCard, candidates, nil end
        return nil, candidates, "no deck or single-card library candidate found near library anchor"
    end
    return nil, candidates, "ambiguous deck candidates near library anchor"
end

function BridgeTryStartupStep(stepName, action)
    local ok, err = pcall(action)
    if ok then return true end
    BridgeShowError("startup " .. tostring(stepName) .. " failed: " .. tostring(err))
    BridgeSetStatus("ERROR", tostring(stepName))
    return false
end

function BridgeHideMainPriorityControls()
    for seatId, guid in pairs(BridgeState.endTurnObjectGuidBySeatId or {}) do
        local object = BridgeGetLiveObjectByGuid(guid)
        if object ~= nil then BridgeSafeObjectCall(object, function(o) o.destruct() end) end
        BridgeState.endTurnObjectGuidBySeatId[seatId] = nil
    end
    for seatId, guid in pairs(BridgeState.passObjectGuidBySeatId or {}) do
        local object = BridgeGetLiveObjectByGuid(guid)
        if object ~= nil then BridgeSafeObjectCall(object, function(o) o.destruct() end) end
        BridgeState.passObjectGuidBySeatId[seatId] = nil
    end
end

local BRIDGE_TRANSIENT_CONTROL_NAMES = {
    ["Forge End Turn"] = true,
    ["Forge Pass Priority"] = true,
    ["Forge Confirm Selection"] = true,
    ["Forge Cancel Selection"] = true,
    ["Forge Setup Start"] = true,
    ["Forge Setup Resume"] = true,
    ["Forge Setup Reset"] = true,
    ["Forge Setup V2 Start"] = true,
    ["Forge Setup V2 Resume"] = true,
    ["Forge Setup V2 Reset"] = true,
    ["Forge Confirm New Match"] = true,
}

local BRIDGE_SETUP_CONTROL_PREFIX = "Forge Setup V2 "

function BridgeDestroyTransientControls()
    for _, object in _ip(_all()) do
        if not BridgeObjectIsUsable(object) then
            -- Skip dead object handles left behind by hot reloads or stale save state.
        else
            local name = BridgeSafeObjectName(object)
            if BRIDGE_TRANSIENT_CONTROL_NAMES[name] == true
                or string.sub(name or "", 1, 22) == "Forge Decision Option "
                or string.sub(name or "", 1, 24) == "Forge Combat Completion " then
                pcall(function() object.destruct() end)
            end
        end
    end
    BridgeState.endTurnObjectGuidBySeatId = {}
    BridgeState.passObjectGuidBySeatId = {}
    BridgeState.selectionControlGuids = {}
    BridgeState.selectionControlDecisionId = nil
    BridgeState.selectionControlActionId = nil
    BridgeState.optionControlGuids = {}
    BridgeState.optionControlDecisionId = nil
    BridgeState.setupObjectGuidByKind = {}
    BridgeState.namedObjectGuidByName = {}
    BridgeState.resetConfirmationArmed = false
    BridgeState.resetConfirmationGuid = nil
end

function BridgeFindNamedObject(name)
    local cachedGuid = BridgeState.namedObjectGuidByName[name]
    if cachedGuid ~= nil then
        local cached = BridgeGetLiveObjectByGuid(cachedGuid)
        if cached ~= nil and BridgeSafeObjectName(cached) == name then return cached end
        BridgeState.namedObjectGuidByName[name] = nil
    end
    for _, object in _ip(_all()) do
        if BridgeObjectIsUsable(object) then
            if BridgeSafeObjectName(object) == name then
                local guid = BridgeSafeObjectGuid(object)
                if guid ~= nil then BridgeState.namedObjectGuidByName[name] = guid end
                return object
            end
        end
    end
    return nil
end

function BridgeHttp.requestJson(method, path, payload, callback)
    local url = BRIDGE_BASE_URL .. path
    local epoch = BRIDGE_RUNTIME_EPOCH_LOCAL
    local connectionEpoch = BridgeState.connectionEpoch or 0

    local function handleIfCurrent(request)
        if not BridgeRuntimeIsCurrent(epoch) then
            BridgeLog("[Bridge] ignored HTTP callback from retired Global.lua runtime")
            return
        end
        if connectionEpoch ~= (BridgeState.connectionEpoch or 0) then
            BridgeLog(string.format("[Bridge] ignored HTTP callback from retired Bridge connection epoch path=%s expected=%s current=%s",
                tostring(path), tostring(connectionEpoch), tostring(BridgeState.connectionEpoch)))
            return
        end
        BridgeHttp.handleResponse(request, callback)
    end

    if method == "GET" then
        WebRequest.get(url, function(request)
            handleIfCurrent(request)
        end)
        return
    end

    local body = payload and JSON.encode(payload) or ""
    local headers = {
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/json"
    }

    if path == "/api/v1/choice" then
        -- A choice body contains protocol identifiers only, never card or
        -- hidden-information data. Record the exact serialized wire shape so
        -- a Lua/TTS transport issue can be distinguished from a legacy caller.
        BridgeLog("[Bridge] CHOICE_WIRE_BODY " .. tostring(body))
    end

    WebRequest.custom(url, method, true, body, headers, function(request)
        handleIfCurrent(request)
    end)
end

function BridgeSeatIdForObjectSide(object)
    for seatId, seat in pairs(BRIDGE_SEATS) do
        if BridgeObjectIsOnSeatSide(object, seat) then
            return seatId
        end
    end
    return nil
end

function BridgeNearestSeatIdForPosition(position, seatIds)
    local nearestSeatId = nil
    local nearestDistance = nil
    for _, seatId in ipairs(seatIds or {}) do
        local seat = BRIDGE_SEATS[seatId]
        local library = seat and BridgeGetLiveObjectByGuid(seat.libraryZoneGuid) or nil
        if library ~= nil then
            local ok, anchor = pcall(function() return library.getPosition() end)
            if ok and anchor ~= nil then
                local dx = position.x - anchor.x
                local dz = position.z - anchor.z
                local distance = dx * dx + dz * dz
                if nearestDistance == nil or distance < nearestDistance then
                    nearestDistance = distance
                    nearestSeatId = seatId
                end
            end
        end
    end
    return nearestSeatId
end

function BridgeLibraryStagingPosition(seat, stagedBySeat, seatId)
    local library = seat and BridgeGetLiveObjectByGuid(seat.libraryZoneGuid) or nil
    if library == nil then return nil end
    local offset = stagedBySeat[seatId] or 0
    stagedBySeat[seatId] = offset + 1
    local ok, position = pcall(function() return library.getPosition() end)
    if not ok or position == nil then return nil end
    return {
        x = position.x + ((offset % 8) - 3.5) * 0.2,
        y = position.y + 1.5 + math.floor(offset / 8) * 0.03,
        z = position.z
    }
end

function BridgeStagePhysicalCardForBootstrap(object, seatId, callback)
    callback = callback or function() end
    if not BridgeObjectIsUsable(object) then callback(false, "staged object is unavailable"); return end
    -- This helper is intentionally Card-only. TTS Deck-on-Deck operations
    -- are not a safe reset primitive and can corrupt the physical pile.
    if object.tag ~= "Card" then callback(false, "staged object is not a Card"); return end
    local seat = seatId and BRIDGE_SEATS[seatId] or nil
    if seat == nil then callback(false, "staged object has no configured seat"); return end

    -- Do not merely drop cards above the scripting-zone marker and hope that
    -- physics merges them before the library ledger is inspected. On this
    -- table the marker is several units above the actual Deck, which left a
    -- transient (and occasionally permanent) under-count during bootstrap.
    -- Inserting into the resolved physical Deck is deterministic and does not
    -- assign any Forge identity; the later ledger remains authoritative.
    local objectGuid = BridgeSafeObjectGuid(object)
    local deck = BridgeResolveSeatLibraryDeck(seatId)
    local deckGuid = BridgeSafeObjectGuid(deck)
    if objectGuid ~= nil and objectGuid == deckGuid then
        local detail = "refused to stage a library card into itself guid=" .. tostring(objectGuid)
            .. " seat=" .. tostring(seatId)
        BridgeLog("[Bridge] " .. detail)
        callback(false, detail)
        return
    end
    -- Serialize staging through the same verified insertion primitive used by
    -- mulligan and ordinary library returns. Repeated synchronous putObject
    -- calls leave several loose Card userdatas beside one Deck long enough to
    -- defeat the strict resync audit.
    BridgeInsertPhysicalCardIntoLibrary(seatId, object, "NORMAL", function(ok, err)
        if not ok then
            BridgeLog("[Bridge] bootstrap library staging failed seat=" .. tostring(seatId)
                .. " guid=" .. tostring(objectGuid) .. " reason=" .. tostring(err))
        end
        callback(ok, err)
    end, nil)
end

function BridgeZoneAnchorCacheKey(seatId, zoneName)
    return tostring(seatId) .. ":" .. tostring(zoneName)
end

function BridgeFindNamedZoneObjectForSeat(seatId, zoneName)
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then return nil end

    local keyword = nil
    if zoneName == "graveyard" then keyword = "graveyard" end
    if zoneName == "exile" then keyword = "exile" end
    if zoneName == "command" then keyword = "command" end
    if keyword == nil then return nil end

    local library = BridgeGetLiveObjectByGuid(seat.libraryZoneGuid)
    local nearest = nil
    local nearestDistance = nil
    for _, object in ipairs(getAllObjects()) do
        if BridgeObjectIsUsable(object) then
            local name = string.lower(tostring(BridgeSafeObjectName(object) or ""))
            if string.find(name, keyword, 1, true) ~= nil and BridgeObjectIsOnSeatSide(object, seat) then
            if library == nil then
                return object
            end
                local okObjPos, objectPos = pcall(function() return object.getPosition() end)
                local okLibraryPos, libraryPos = pcall(function() return library.getPosition() end)
                if okObjPos and objectPos ~= nil and okLibraryPos and libraryPos ~= nil then
                    local dx = objectPos.x - libraryPos.x
                    local dz = objectPos.z - libraryPos.z
                    local distance = dx * dx + dz * dz
                    if nearestDistance == nil or distance < nearestDistance then
                        nearestDistance = distance
                        nearest = object
                    end
                end
            end
        end
    end
    return nearest
end

function BridgeResolveSeatZoneAnchor(seatId, zoneName)
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then return nil end

    local cacheKey = BridgeZoneAnchorCacheKey(seatId, zoneName)
    local cachedGuid = BridgeState.zoneAnchorGuidBySeatAndZone[cacheKey]
    if cachedGuid ~= nil then
        local cached = BridgeGetLiveObjectByGuid(cachedGuid)
        if cached ~= nil then
            local ok, cachedPos = pcall(function() return cached.getPosition() end)
            if ok and cachedPos ~= nil then return cachedPos end
        end
        BridgeState.zoneAnchorGuidBySeatAndZone[cacheKey] = nil
    end

    local configuredGuid = seat[zoneName .. "ZoneGuid"]
    if configuredGuid ~= nil then
        local configured = BridgeGetLiveObjectByGuid(configuredGuid)
        if configured ~= nil then
            BridgeState.zoneAnchorGuidBySeatAndZone[cacheKey] = configuredGuid
            local ok, configuredPos = pcall(function() return configured.getPosition() end)
            if ok and configuredPos ~= nil then return configuredPos end
        end
    end

    local named = BridgeFindNamedZoneObjectForSeat(seatId, zoneName)
    if named ~= nil then
        local namedGuid = BridgeSafeObjectGuid(named)
        if namedGuid ~= nil then
            BridgeState.zoneAnchorGuidBySeatAndZone[cacheKey] = namedGuid
        end
        local ok, namedPos = pcall(function() return named.getPosition() end)
        if ok and namedPos ~= nil then return namedPos end
    end

    local configuredAnchor = seat[zoneName .. "Anchor"]
    if configuredAnchor ~= nil then
        return {
            x = configuredAnchor.x,
            y = configuredAnchor.y,
            z = configuredAnchor.z
        }
    end

    return nil
end

function BridgeStageSeatCardsForBootstrap(snapshot, callback)
    callback = callback or function() end
    BridgeTraceStart("START-13 loose-card-staging")
    local knownSeatIds = {}
    local knownSeatIdSet = {}
    local context = BridgeBuildGameCardContext(snapshot)
    for _, seatSnapshot in ipairs(snapshot.seats or {}) do
        table.insert(knownSeatIds, seatSnapshot.seatId)
        knownSeatIdSet[seatSnapshot.seatId] = true
    end

    -- Keep cards in the live TTS hands during a resync.  Moving both hands into
    -- the library before the authoritative rebuild made a slow or failed
    -- bootstrap look like a hand loss, and left the player without a visible
    -- recovery point.  Hand objects are explicitly collected below because TTS
    -- does not consistently return them from getAllObjects().
    for seatId, _ in pairs(BRIDGE_SEATS) do
        local handObjects, handError = BridgeTryGetSeatHandObjects(seatId)
        if handObjects == nil then callback(false, handError); return end
        local handGuids = {}
        for _, handObject in ipairs(handObjects) do
            local guid = BridgeSafeObjectGuid(handObject)
            if guid ~= nil then handGuids[guid] = true end
        end
        context.handGuidsBySeat[seatId] = handGuids
    end

    local stagedGuids = {}
    local staged = {}
    for _, object in ipairs(getAllObjects()) do
        if BridgeObjectIsUsable(object) and object.tag == "Card" then
            local guid = BridgeSafeObjectGuid(object)
            local handSeatId = nil
            for candidateSeatId, handGuids in pairs(context.handGuidsBySeat or {}) do
                if guid ~= nil and handGuids[guid] == true then
                    handSeatId = candidateSeatId
                    break
                end
            end
            local seatId = handSeatId or BridgeSeatIdForObjectSide(object)
            if seatId == nil or not knownSeatIdSet[seatId] then
                local ok, position = pcall(function() return object.getPosition() end)
                if ok and position ~= nil then
                    seatId = BridgeNearestSeatIdForPosition(position, knownSeatIds)
                end
            end
            local isInHand = handSeatId ~= nil
            local trackedInstanceId = guid and BridgeState.physicalInstanceIdByGuid[guid] or nil
            local trackedZone = guid and BridgeState.physicalZoneByGuid[guid] or nil
            -- During a same-session resync, retain live public cards in place.
            -- Moving them into the library would erase their exact identity
            -- before snapshot reconciliation and force a duplicate-name deck
            -- extraction (the Thought Scour failure mode). Unknown loose
            -- objects are still staged so a real new-match/bootstrap rebuild
            -- remains strict and deterministic.
            local preserveTrackedPublicCard = trackedInstanceId ~= nil
                and trackedZone ~= nil and trackedZone ~= "library"
            if seatId ~= nil
                and not isInHand
                and not preserveTrackedPublicCard
                and IsGameCardCandidate(object, seatId, context) then
                table.insert(staged, {object = object, seatId = seatId, guid = guid})
            end
        end
    end

    local stagedCount = 0
    local function stageNext(index)
        local item = staged[index]
        if item == nil then
            if stagedCount > 0 then
                BridgeLog("[Bridge] staged " .. tostring(stagedCount)
                    .. " loose card(s) through verified library containment before authoritative bootstrap")
            end
            callback(true, nil, stagedGuids)
            return
        end
        BridgeStagePhysicalCardForBootstrap(item.object, item.seatId, function(ok, err)
            if not ok then
                callback(false, "bootstrap staging failed for guid=" .. tostring(item.guid) .. ": " .. tostring(err))
                return
            end
            stagedCount = stagedCount + 1
            if item.guid ~= nil then stagedGuids[tostring(item.guid)] = true end
            stageNext(index + 1)
        end)
    end
    stageNext(1)
end

-- A destructive New Match must not leave the previous game's embodied cards
-- on the battlefield (or in hand/graveyard/exile/command).  Mappings are the
-- identity-safe source of truth here: only cards already associated with a
-- Forge seat are returned, so presentation helpers and unrelated table
-- objects are never swept into a player's library. Graveyard Deck piles are
-- drained card-by-card; whole Deck-on-Deck merges are deliberately avoided.
-- Do this before reading
-- the imported deck inventory; otherwise the physical deck is under-counted
-- and the old cards remain visible after reset.
function BridgeObjectNearSeatZone(object, seatId, zoneName)
    local anchor = BridgeResolveSeatZoneAnchor(seatId, zoneName)
    if anchor == nil or not BridgeObjectIsUsable(object) then return false end
    local ok, position = pcall(function() return object.getPosition() end)
    if not ok or position == nil then return false end
    local dx = position.x - anchor.x
    local dz = position.z - anchor.z
    return dx * dx + dz * dz <= 16.0
end

-- Once cards are stacked, TTS no longer exposes their positions.  Preserve an
-- identity-based way to recognize a graveyard pile even when the pile was
-- nudged outside the nominal graveyard anchor radius.
function BridgeDeckContainsTrackedCardForSeat(deck, seatId)
    if not BridgeObjectIsUsable(deck) or deck.tag ~= "Deck" then return false end
    local entries = {}
    local ok = pcall(function() entries = deck.getObjects() or {} end)
    if not ok then return false end
    for _, entry in ipairs(entries) do
        local guid = entry and entry.guid or nil
        local mappedSeat = guid and BridgeState.physicalSeatByGuid[guid] or nil
        if mappedSeat == seatId then return true end
    end
    return false
end

function BridgeLibraryEntries(deck)
    if not BridgeObjectIsUsable(deck) or deck.tag ~= "Deck" then return nil end
    local entries = {}
    local ok = pcall(function() entries = deck.getObjects() or {} end)
    if not ok then return nil end
    return entries
end

function BridgeLibraryContainsGuid(deck, guid)
    if guid == nil then return false end
    for _, entry in ipairs(BridgeLibraryEntries(deck) or {}) do
        if tostring(entry.guid or entry.GUID or "") == tostring(guid) then return true end
    end
    return false
end

function BridgeLibraryAuditIgnoresGuid(ignoredGuids, guid)
    if ignoredGuids == nil or guid == nil then return false end
    if type(ignoredGuids) == "table" then
        return ignoredGuids[tostring(guid)] == true
    end
    return tostring(guid) == tostring(ignoredGuids)
end

function BridgeAuditDuplicateLibraryGuids(ignoredGuids)
    local looseByGuid = {}
    for _, object in ipairs(getAllObjects()) do
        if BridgeObjectIsUsable(object) and object.tag == "Card" then
            local guid = BridgeSafeObjectGuid(object)
            -- During a Deck.putObject/takeObject transaction TTS can retain
            -- the exact moved Card in its old loose/source view while also
            -- publishing it in the destination Deck ledger.  The insertion
            -- caller supplies the exact just-inserted GUID(s); all other collisions
            -- remain strict corruption canaries.
            if guid ~= nil and not BridgeLibraryAuditIgnoresGuid(ignoredGuids, guid) then
                looseByGuid[guid] = object
            end
        end
    end

    local duplicates = 0
    for _, deck in ipairs(getAllObjects()) do
        if BridgeObjectIsUsable(deck) and deck.tag == "Deck" then
            local deckGuid = BridgeSafeObjectGuid(deck)
            for index, entry in ipairs(BridgeLibraryEntries(deck) or {}) do
                local guid = entry and (entry.guid or entry.GUID) or nil
                local loose = guid and looseByGuid[guid] or nil
                if loose ~= nil then
                    duplicates = duplicates + 1
                    local identity = BridgeLibraryCardIdentity(loose) or {}
                    BridgeLog(string.format(
                        "[Bridge] DUPLICATE_PHYSICAL_GUID seat=%s guid=%s card=%s looseTag=%s looseCardID=%s containingDeck=%s containedIndex=%s forgeCardInstanceId=%s",
                        tostring(BridgeSeatIdForObjectSide(loose)), tostring(guid), tostring(BridgeSafeObjectName(loose)),
                        tostring(loose.tag), tostring(identity.cardId or -1), tostring(deckGuid), tostring(index),
                        tostring(BridgeState.physicalInstanceIdByGuid[guid])))
                end
            end
        end
    end
    return duplicates
end

function BridgeLibraryCardIdentity(object)
    if not BridgeObjectIsUsable(object) or object.tag ~= "Card" then return nil end
    local ok, data = pcall(function() return object.getData() end)
    if not ok or type(data) ~= "table" then return nil end
    local customDeck = data.CustomDeck
    local hasFaceUrl = false
    if type(customDeck) == "table" then
        for _, deck in pairs(customDeck) do
            if type(deck) == "table" and tostring(deck.FaceURL or "") ~= "" then
                hasFaceUrl = true
                break
            end
        end
    end
    return {
        cardId = tonumber(data.CardID or data.cardID),
        hasCustomDeck = type(customDeck) == "table" and next(customDeck) ~= nil,
        hasFaceUrl = hasFaceUrl
    }
end

function BridgeRequireArtBearingLibraryCard(object, seatId, cardInstanceId)
    local identity = BridgeLibraryCardIdentity(object)
    if identity ~= nil and identity.cardId ~= nil and identity.cardId >= 0
        and identity.hasCustomDeck == true and identity.hasFaceUrl == true then
        return true
    end
    local guid = BridgeSafeObjectGuid(object)
    BridgeLog(string.format(
        "[Bridge] CARD_ART_INTEGRITY_FAILURE seat=%s instance=%s guid=%s card=%s CardID=%s CustomDeck=%s FaceURL=%s",
        tostring(seatId), tostring(cardInstanceId), tostring(guid), tostring(BridgeSafeObjectName(object)),
        tostring(identity and identity.cardId or -1), tostring(identity and identity.hasCustomDeck or false),
        tostring(identity and identity.hasFaceUrl or false)))
    return false
end

function BridgeFindLibraryDeckContainingGuid(seatId, guid)
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil or guid == nil then return nil end
    for _, deck in ipairs(BridgeFindLibraryDeckCandidatesForSeat(seatId)) do
        if BridgeLibraryContainsGuid(deck, guid) then return deck end
    end
    return nil
end

function BridgeVerifyLibraryContainment(seatId, guid, callback, attempt, preferredLibrary)
    attempt = attempt or 1
    local library = preferredLibrary
    if library == nil or not BridgeObjectIsUsable(library) or library.tag ~= "Deck" then
        library = BridgeResolveSeatLibraryDeck(seatId)
    end
    if library ~= nil and library.tag == "Deck" and BridgeLibraryContainsGuid(library, guid) then
        callback(true, library, nil)
        return
    end
    local containingDeck = BridgeFindLibraryDeckContainingGuid(seatId, guid)
    if containingDeck ~= nil then
        callback(true, containingDeck, nil)
        return
    end
    if attempt >= 30 then
        callback(false, nil, "TTS did not verify library containment for GUID " .. tostring(guid))
        return
    end
    BridgeWaitFrames(function()
        -- A putObject operation may replace the physical Deck while TTS is
        -- settling. Re-resolve the live container on every retry instead of
        -- retaining a stale Deck reference from the previous frame.
        BridgeVerifyLibraryContainment(seatId, guid, callback, attempt + 1)
    end, 2)
end

-- TTS can report a newly returned card in Deck.getObjects() for a short period
-- while getAllObjects() still exposes the pre-put Card userdata.  Treat that
-- as a container-settle window, not as physical corruption.  Keep retrying
-- the real duplicate audit, and still fail loudly if the loose/contained
-- collision survives the bounded window.
function BridgeVerifyLibraryIdentityStability(callback, attempt, expectedGuids)
    attempt = attempt or 1
    -- TTS can retain source Card userdata for a few frames after it has added
    -- a card to a Deck. Suppress only the exact GUIDs just staged during that
    -- bounded window; the terminal check is strict so a persistent duplicate
    -- can never be accepted as a successful insertion/bootstrap.
    local strictDuplicateCount = BridgeAuditDuplicateLibraryGuids()
    if strictDuplicateCount == 0 then
        callback(true, nil)
        return
    end
    if attempt >= 30 then
        callback(false, "library insertion produced " .. tostring(strictDuplicateCount)
            .. " loose/contained duplicate GUID(s)")
        return
    end
    local ignoredGuids = expectedGuids
    local unexpectedDuplicateCount = BridgeAuditDuplicateLibraryGuids(ignoredGuids)
    if unexpectedDuplicateCount > 0 then
        callback(false, "library insertion produced " .. tostring(unexpectedDuplicateCount)
            .. " unexpected loose/contained duplicate GUID(s)")
        return
    end
    if attempt == 1 then
        BridgeLog("[Bridge] waiting for TTS library containment to settle before duplicate audit")
    end
    BridgeWaitFrames(function()
        BridgeVerifyLibraryIdentityStability(callback, attempt + 1, expectedGuids)
    end, 2)
end

-- Every authoritative library insertion crosses this boundary.  The caller
-- keeps its exact loose mapping until the callback proves that TTS has put the
-- card into the physical library container.
function BridgeInsertPhysicalCardIntoLibrary(seatId, object, placementMode, callback, cardInstanceId)
    callback = callback or function() end
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then callback(false, "unknown seat"); return end
    if not BridgeObjectIsUsable(object) or object.tag ~= "Card" then
        callback(false, "library insertion requires a live Card object")
        return
    end
    local guid = BridgeSafeObjectGuid(object)
    if guid == nil then callback(false, "library insertion card has no GUID"); return end
    if not BridgeRequireArtBearingLibraryCard(object, seatId, cardInstanceId) then
        callback(false, "library insertion rejected an artless normal game card")
        return
    end

    local library = BridgeResolveSeatLibraryDeck(seatId)
    if library == nil then
        callback(false, "no physical library container is available")
        return
    end
    local mode = string.upper(tostring(placementMode or "NORMAL"))
    local inserted = false
    local insertError = nil
    local resultingLibrary = nil
    local ok = pcall(function()
        object.setLock(false)
        object.use_hands = false
        BridgeSetPhysicalFaceDown(object, seat, true)
        if library.tag == "Deck" then
            local entries = BridgeLibraryEntries(library)
            if entries == nil then error("could not inspect physical library before insertion") end
            -- getObjects is one-based and putObject's final slot is the
            -- explicit bottom. NORMAL intentionally leaves Forge's existing
            -- physical order untouched; Forge remains authoritative for order.
            if mode == "BOTTOM" then
                -- TTS deck entries use zero-based indices. The current card
                -- count is therefore the explicit bottom insertion index.
                resultingLibrary = library.putObject(object, #entries)
            else
                resultingLibrary = library.putObject(object)
            end
            inserted = true
        elseif library.tag == "Card" then
            -- TTS represents a one-card Deck as a loose Card.  Use the same
            -- container insertion primitive as the normal path so TTS forms
            -- the resulting Deck deterministically.  Merely positioning two
            -- cards together is not containment and can leave both cards
            -- loose after a reset or mulligan.
            local libraryPosition = library.getPosition()
            library.setLock(false)
            library.use_hands = false
            BridgeSetPhysicalFaceDown(library, seat, true)
            local yOffset = mode == "BOTTOM" and -0.06 or 0.06
            object.setPosition({libraryPosition.x, libraryPosition.y + yOffset, libraryPosition.z})
            library.setPosition(libraryPosition)
            resultingLibrary = library.putObject(object)
            inserted = true
        else
            insertError = "library target is neither a Deck nor a one-card Card"
        end
    end)
    if not ok then
        callback(false, tostring(insertError or inserted))
        return
    end
    if not inserted then callback(false, insertError or "physical library insertion failed"); return end

    BridgeVerifyLibraryContainment(seatId, guid, function(verified, deck, verifyError)
        if not verified then
            BridgeLog(string.format("[Bridge] LIBRARY_CONTAINMENT_FAILURE seat=%s guid=%s reason=%s",
                tostring(seatId), tostring(guid), tostring(verifyError)))
            callback(false, verifyError)
            return
        end
        BridgeVerifyLibraryIdentityStability(function(stable, stabilityError)
            if not stable then
                BridgeLog("[Bridge] " .. tostring(stabilityError))
                callback(false, stabilityError)
                return
            end
            callback(true, nil, deck)
        end, 1, guid)
    end, 1, resultingLibrary)
end

function BridgeProcessMulliganBottomQueue(seatId)
    if BridgeState.mulliganBottomInsertionActiveBySeatId[seatId] == true then return end
    local queue = BridgeState.mulliganBottomQueueBySeatId[seatId]
    local item = queue and queue[1] or nil
    if item == nil then return end
    BridgeState.mulliganBottomInsertionActiveBySeatId[seatId] = true

    local transactionSessionId = BridgeState.eventSessionId
    local transactionGeneration = BridgeState.physicalTransactionGeneration or 0
    local function current()
        return transactionSessionId == BridgeState.eventSessionId
            and transactionGeneration == (BridgeState.physicalTransactionGeneration or 0)
    end
    local function complete()
        if not current() then
            BridgeLog("[Bridge] ignored stale mulligan library callback seat=" .. tostring(seatId)
                .. " generation=" .. tostring(transactionGeneration))
            return
        end
        local current = BridgeState.mulliganBottomQueueBySeatId[seatId]
        if current ~= nil then table.remove(current, 1) end
        BridgeState.mulliganBottomInsertionActiveBySeatId[seatId] = nil
        BridgeProcessMulliganBottomQueue(seatId)
        -- A replacement opening-hand draw must not overtake a preceding
        -- authoritative hand->library insertion.
        BridgeProcessLibraryExtractionQueue(seatId)
        BridgeTryApplyDeferredSnapshotReconcile("library-bottom-insertion-complete")
    end

    local guid = BridgeSafeObjectGuid(item.object)
    local instanceId = guid and BridgeState.physicalInstanceIdByGuid[guid] or nil
    BridgeInsertPhysicalCardIntoLibrary(seatId, item.object, "BOTTOM", function(ok, err)
        if not current() then return end
        if not ok then
            BridgeStopOnDesync("mulligan bottom library insertion failed: " .. tostring(err))
            -- Do not drain the remaining rejected-hand queue after a physical
            -- failure.  Continuing here was the source of one desync report per
            -- mulligan card and could issue more TTS mutations after the bridge
            -- had already declared synchronization unsafe.  Resync/reset owns
            -- recovery and recreates these queues.
            BridgeState.mulliganBottomQueueBySeatId[seatId] = nil
            BridgeState.mulliganBottomInsertionActiveBySeatId[seatId] = nil
            return
        end
        if instanceId ~= nil then
            BridgeRecordLibraryContainedState(instanceId, seatId, BridgeState.cardNameByInstanceId[instanceId])
        end
        complete()
    end, instanceId)
end

function BridgeQueueMulliganBottomInsertion(seatId, object)
    if BridgeState.mulliganBottomQueueBySeatId[seatId] == nil then
        BridgeState.mulliganBottomQueueBySeatId[seatId] = {}
    end
    table.insert(BridgeState.mulliganBottomQueueBySeatId[seatId], {object = object})
    BridgeProcessMulliganBottomQueue(seatId)
end

-- Library-to-public-zone events can arrive as a burst while TTS is still
-- resolving the prior Deck.takeObject callback (notably the opening seven).
-- Serialize those physical extractions per seat so deck indices never race.
function BridgeProcessLibraryExtractionQueue(seatId)
    if BridgeState.libraryExtractionActiveBySeatId[seatId] == true then return end
    if BridgeState.mulliganBottomInsertionActiveBySeatId[seatId] == true
        or #(BridgeState.mulliganBottomQueueBySeatId[seatId] or {}) > 0 then
        return
    end
    local queue = BridgeState.libraryExtractionQueueBySeatId[seatId]
    local job = queue and queue[1] or nil
    if job == nil then return end
    BridgeState.libraryExtractionActiveBySeatId[seatId] = true
    local transactionSessionId = BridgeState.eventSessionId
    local transactionGeneration = BridgeState.physicalTransactionGeneration or 0
    local finished = false
    local function current()
        return transactionSessionId == BridgeState.eventSessionId
            and transactionGeneration == (BridgeState.physicalTransactionGeneration or 0)
    end
    local function complete()
        if finished then return end
        finished = true
        if not current() then
            BridgeLog("[Bridge] ignored stale library extraction callback seat=" .. tostring(seatId)
                .. " generation=" .. tostring(transactionGeneration))
            return
        end
        local current = BridgeState.libraryExtractionQueueBySeatId[seatId]
        if current ~= nil then table.remove(current, 1) end
    BridgeState.libraryExtractionActiveBySeatId[seatId] = nil
        local batch = BridgeState.libraryBatchBySeatId[seatId]
        local nextEvent = BridgeState.eventQueue and BridgeState.eventQueue[1] or nil
        if batch ~= nil and (nextEvent == nil or tostring(nextEvent.forgeSequence or "") ~= tostring(batch.forgeSequence or "")) then
            batch.completedAt = BridgeResyncClockNow ~= nil and BridgeResyncClockNow() or os.clock()
            batch.active = false
            BridgeState.libraryBatchBySeatId[seatId] = nil
            BridgeLog(string.format("[Bridge] LIBRARY_BATCH_COMMITTED seat=%s forgeSequence=%s count=%s",
                tostring(seatId), tostring(batch.forgeSequence), tostring(#(batch.cardInstanceIds or {}))))
        end
        BridgeProcessLibraryExtractionQueue(seatId)
        BridgeTryPresentPendingDecision("library-extraction-complete")
        if BridgeState.lastDecision ~= nil and not BridgeState.submitting then
            BridgeRenderDecision(BridgeState.lastDecision)
        end
        BridgeTryApplyDeferredSnapshotReconcile("library-extraction-complete")
    end
    local started, startError = pcall(function() job(function(...)
        if not current() then
            BridgeLog("[Bridge] ignored stale library extraction completion seat=" .. tostring(seatId)
                .. " generation=" .. tostring(transactionGeneration))
            return
        end
        complete(...)
    end) end)
    if not started then
        complete()
        BridgeStopOnDesync("library extraction transaction failed to start: " .. tostring(startError))
    end
end

function BridgeQueueLibraryExtraction(seatId, job)
    if BridgeState.libraryExtractionQueueBySeatId[seatId] == nil then
        BridgeState.libraryExtractionQueueBySeatId[seatId] = {}
    end
    table.insert(BridgeState.libraryExtractionQueueBySeatId[seatId], job)
    BridgeProcessMulliganBottomQueue(seatId)
    BridgeProcessLibraryExtractionQueue(seatId)
end

function BridgeReturnGraveyardPilesToLibraries(callback)
    local jobs = {}
    local seen = {}
    for seatId, seat in pairs(BRIDGE_SEATS) do
        local library = BridgeResolveSeatLibraryDeck(seatId)
        local libraryGuid = library and BridgeSafeObjectGuid(library) or nil
        if library ~= nil then
            for _, object in ipairs(getAllObjects()) do
                local guid = BridgeSafeObjectGuid(object)
                if BridgeObjectIsUsable(object) and object.tag == "Deck"
                    and guid ~= nil and guid ~= libraryGuid and not seen[guid]
                    and not BridgeIsPresentationOnlyObject(object)
                    and (BridgeObjectNearSeatZone(object, seatId, "graveyard")
                        or BridgeDeckContainsTrackedCardForSeat(object, seatId)) then
                    seen[guid] = true
                    table.insert(jobs, {pile = object, library = library, seatId = seatId, guid = guid})
                end
            end
        end
    end

    local function drain(job, done)
        local pile = job.pile
        local library = job.library
        local drained = 0
        local function nextCard()
            if not BridgeObjectIsUsable(pile) then
                -- When a TTS Deck reaches one card it is replaced by a loose
                -- Card object.  Give that replacement a couple of frames to
                -- appear before the caller sweeps loose graveyard cards;
                -- otherwise the final card is invisible to getAllObjects and
                -- remains stranded outside the new library.
                BridgeWaitFrames(function() done(true, nil) end, 2)
                return
            end
            -- Re-read the live contents before every extraction.  A TTS Deck's
            -- contained-object indices are re-numbered after takeObject; using
            -- one snapshot of indices can therefore skip cards and leave them
            -- stranded in the old graveyard pile.
            local entries = {}
            local inspected = pcall(function() entries = pile.getObjects() or {} end)
            if not inspected then done(false, "could not inspect graveyard pile " .. tostring(job.guid)); return end
            local entry = entries[1]
            if entry == nil then
                BridgeLog(string.format("[Bridge] drained graveyard pile guid=%s seat=%s cards=%d",
                    tostring(job.guid), tostring(job.seatId), drained))
                done(true, nil)
                return
            end
            local taken = false
            local options = {
                position = library.getPosition(),
                smooth = false,
                callback_function = function(card)
                    if taken then return end
                    taken = true
                    if not BridgeObjectIsUsable(card) then
                        done(false, "graveyard pile returned an unusable card " .. tostring(entry.guid))
                        return
                    end
                    local cardGuid = BridgeSafeObjectGuid(card) or entry.guid
                    if cardGuid ~= nil and BridgeState.tokenPhysicalGuids[cardGuid] == true then
                        pcall(function() card.destruct() end)
                        BridgeState.tokenPhysicalGuids[cardGuid] = nil
                        drained = drained + 1
                        BridgeWaitFrames(nextCard, 1)
                    else
                        -- takeObject invokes its callback before TTS has
                        -- necessarily removed the entry from the source pile.
                        -- Let that source-side ledger settle before putting the
                        -- same physical GUID into the destination library.
                        BridgeWaitFrames(function()
                            BridgeInsertPhysicalCardIntoLibrary(job.seatId, card, "NORMAL", function(inserted, insertError)
                                if not inserted then
                                    done(false, "could not return graveyard card " .. tostring(cardGuid) .. " to library: " .. tostring(insertError))
                                    return
                                end
                                drained = drained + 1
                                BridgeWaitFrames(nextCard, 1)
                            end, BridgeState.physicalInstanceIdByGuid[cardGuid])
                        end, 2)
                        return
                    end
                end
            }
            if entry.guid ~= nil then options.guid = entry.guid else options.index = entry.index end
            local takeOk, takeError = pcall(function() pile.takeObject(options) end)
            if not takeOk then
                done(false, "could not take card from graveyard pile " .. tostring(job.guid) .. ": " .. tostring(takeError))
            end
        end
        nextCard()
    end

    local function nextJob(index)
        if index > #jobs then
            if callback then callback(true, nil) end
            return
        end
        drain(jobs[index], function(ok, err)
            if not ok then
                if callback then callback(false, err) end
                return
            end
            nextJob(index + 1)
        end)
    end
    nextJob(1)
end

function BridgeReturnPreviousGameCardsToLibraries(callback)
    local candidates = {}
    local seen = {}
    local function addCandidate(object)
        if not BridgeObjectIsUsable(object) or object.tag ~= "Card" then return end
        if BridgeIsPresentationOnlyObject(object) then return end
        local guid = BridgeSafeObjectGuid(object)
        if guid == nil or seen[guid] then return end
        if BridgeState.tokenPhysicalGuids[guid] == true then
            pcall(function() object.destruct() end)
            BridgeState.tokenPhysicalGuids[guid] = nil
            seen[guid] = true
            return
        end
        local seatId = BridgeState.physicalSeatByGuid[guid]
        local zoneName = BridgeState.physicalZoneByGuid[guid]
        if zoneName == "library" then return end
        -- Older event paths can leave a legitimate battlefield card without
        -- a mapping (for example after a tolerated move error). During the
        -- destructive reset, recover such cards by their physical seat side;
        -- presentation-only objects remain excluded by the candidate check.
        if seatId == nil then
            for candidateSeatId, seat in pairs(BRIDGE_SEATS) do
                if BridgeObjectIsOnSeatSide(object, seat) then
                    seatId = candidateSeatId
                    zoneName = "battlefield"
                    break
                end
            end
        end
        if seatId == nil or BRIDGE_SEATS[seatId] == nil then return end
        seen[guid] = true
        table.insert(candidates, {object = object, seatId = seatId, guid = guid, zone = zoneName})
    end

    local continueWithLooseCards = function(pileOk, pileError)
        if not pileOk then
            if callback then callback(false, pileError) end
            return
        end
        -- getAllObjects includes most loose cards, but hand APIs are retained as
        -- an explicit fallback because TTS can omit hand contents from that list.
        for seatId, _ in pairs(BRIDGE_SEATS) do
            local handObjects = BridgeTryGetSeatHandObjects(seatId)
            for _, object in ipairs(handObjects or {}) do addCandidate(object) end
        end
        for _, object in ipairs(getAllObjects()) do addCandidate(object) end

        local function insertCandidate(index)
            if index > #candidates then
                if #candidates > 0 then
                    BridgeLog("[Bridge] returned " .. tostring(#candidates) .. " previous-game card(s) to libraries before reset")
                end
                if callback then callback(true, nil) end
                return
            end
            local candidate = candidates[index]
            BridgeInsertPhysicalCardIntoLibrary(candidate.seatId, candidate.object, "NORMAL", function(inserted, insertError)
                if not inserted then
                    BridgeLog("[Bridge] previous-game card return failed guid=" .. tostring(candidate.guid)
                        .. " seat=" .. tostring(candidate.seatId) .. " zone=" .. tostring(candidate.zone)
                        .. " reason=" .. tostring(insertError))
                    if callback then callback(false, "could not return previous-game card " .. tostring(candidate.guid) .. " to library") end
                    return
                end
                insertCandidate(index + 1)
            end, BridgeState.physicalInstanceIdByGuid[candidate.guid])
        end
        insertCandidate(1)
    end
    BridgeReturnGraveyardPilesToLibraries(continueWithLooseCards)
end

function BridgeHttp.handleResponse(request, callback)
    if request.is_error then
        callback(false, nil, "Request failed: " .. tostring(request.error), request)
        return
    end

    local body = nil
    if request.text ~= nil and request.text ~= "" then
        local ok, decoded = pcall(function()
            return JSON.decode(request.text)
        end)

        if ok then
            body = decoded
        end
    end

    local isOk = request.response_code >= 200 and request.response_code < 300
    if isOk then
        callback(true, body, nil, request)
    else
        callback(false, body, "HTTP " .. tostring(request.response_code), request)
    end
end

function onLoad()
    -- TTS file read and Lua compilation happen before this function executes;
    -- this first marker deliberately measures only observable runtime startup.
    local startupToken = BridgeStartupStageBegin("onLoad_enter")
    BridgeOnLoad()
    BridgeState.startupTrace.observableDurationMs = BridgeStartupStageEnd(
        startupToken, "BridgeOnLoad_return")
end

function onUpdate()
    if BridgeEnforceDesyncRecovery ~= nil then BridgeEnforceDesyncRecovery("onUpdate") end
    if BridgeCheckRecoveryConvergence ~= nil then BridgeCheckRecoveryConvergence("onUpdate") end
    if BridgeCheckDecisionPollingLiveness ~= nil then BridgeCheckDecisionPollingLiveness("onUpdate") end
    -- Wait.time is normally sufficient, but a bootstrap can be waiting on a
    -- TTS callback while the time scheduler is delayed.  Keep the resync
    -- watchdog reactive from the frame loop as well.
    if BridgeCheckResyncWatchdog ~= nil then BridgeCheckResyncWatchdog("onUpdate") end
end

function BridgeBeginLibraryBatch(event)
    if event == nil or event.seatId == nil or event.sourceZone ~= "library"
        or event.destinationZone == nil or event.destinationZone == "library" then return end
    local sequence = event.forgeSequence
    if sequence == nil then return end
    local batch = BridgeState.libraryBatchBySeatId[event.seatId]
    if batch == nil or tostring(batch.forgeSequence) ~= tostring(sequence) then
        batch = {forgeSequence = sequence, active = true, cardInstanceIds = {}, startedAt = os.clock()}
        BridgeState.libraryBatchBySeatId[event.seatId] = batch
        BridgeLog(string.format("[Bridge] LIBRARY_BATCH_BEGIN seat=%s forgeSequence=%s", tostring(event.seatId), tostring(sequence)))
    end
    for _, instanceId in ipairs(batch.cardInstanceIds) do
        if instanceId == event.cardInstanceId then return end
    end
    table.insert(batch.cardInstanceIds, event.cardInstanceId)
end

-- The stable static tree lives in Global.xml. Dynamic decision content is
-- routed through its fixed IDs, never through a second Forge choice transport.

function BridgeUiSet(id, attribute, value)
    local ui = BridgeState.ui
    if ui == nil or ui.mounted ~= true then return end
    local nextValue = tostring(value or "")
    ui.uiAttributeAttemptCount = (ui.uiAttributeAttemptCount or 0) + 1
    ui.uiAttributeCache = ui.uiAttributeCache or {}
    local attributeCache = ui.uiAttributeCache[id]
    if attributeCache == nil then
        attributeCache = {}
        ui.uiAttributeCache[id] = attributeCache
    end
    if attributeCache[attribute] == nextValue then
        ui.uiAttributeSkippedCount = (ui.uiAttributeSkippedCount or 0) + 1
        return
    end
    local written = pcall(function() UI.setAttribute(id, attribute, nextValue) end)
    if written then
        attributeCache[attribute] = nextValue
        ui.uiAttributeWriteCount = (ui.uiAttributeWriteCount or 0) + 1
        ui.uiAttributeUpdateCount = ui.uiAttributeWriteCount
    end
end

-- Keep only exact Forge instance IDs here. Card names are intentionally not
-- retained for the readiness diagnostic because an opening hand may be hidden
-- information from the other player.
function BridgeRecordExpectedHandIdentities(snapshot, requiredSeatId)
    BridgeState.expectedHandInstanceIdsBySeatId = {}
    local identityCount = 0
    for _, seatSnapshot in ipairs(snapshot and snapshot.seats or {}) do
        local expected = {}
        for _, zone in ipairs(seatSnapshot.zones or {}) do
            if string.lower(tostring(zone.name or "")) == "hand" then
                for _, card in ipairs(zone.cards or {}) do
                    if card.cardInstanceId ~= nil and tostring(card.cardInstanceId) ~= "" then
                        expected[card.cardInstanceId] = true
                        identityCount = identityCount + 1
                    end
                end
            end
        end
        BridgeState.expectedHandInstanceIdsBySeatId[seatSnapshot.seatId] = expected
    end
    -- A transient/partial snapshot must not release the opening decision.  If
    -- no exact hand IDs were returned, the next readiness retry requests a
    -- fresh snapshot instead of waiting forever on an empty expected set.
    local requiredExpected = requiredSeatId ~= nil
        and BridgeState.expectedHandInstanceIdsBySeatId[requiredSeatId] or nil
    local complete = requiredSeatId ~= nil
        and requiredExpected ~= nil and next(requiredExpected) ~= nil
        or (requiredSeatId == nil and identityCount > 0)
    BridgeState.openingHandReadinessSnapshotPending = not complete
    return complete
end

function BridgeCheckOpeningHandReadiness(seatId)
    local expected = BridgeState.expectedHandInstanceIdsBySeatId[seatId]
    local handGuids, handError = BridgeBuildSeatHandGuidSet(seatId)
    local expectedCount = 0
    local readyCount = 0
    local missing = {}
    for instanceId in pairs(expected or {}) do
        expectedCount = expectedCount + 1
        local guid = BridgeState.physicalByInstanceId[instanceId]
        local reason = nil
        if guid == nil then
            reason = "missing-guid"
        elseif BridgeState.physicalInstanceIdByGuid[guid] ~= instanceId then
            reason = "inverse-mapping-mismatch"
        elseif BridgeState.physicalSeatByGuid[guid] ~= seatId then
            reason = "physical-seat-mismatch"
        elseif BridgeState.physicalZoneByGuid[guid] ~= "hand" then
            reason = "physical-zone-mismatch"
        else
            local object = BridgeGetLiveObjectByGuid(guid)
            if object == nil or object.tag ~= "Card" then
                reason = "physical-card-unavailable"
            elseif handGuids[guid] ~= true then
                reason = "tts-hand-membership-pending"
            end
        end
        if reason == nil then
            readyCount = readyCount + 1
        else
            table.insert(missing, tostring(instanceId) .. "->" .. tostring(guid) .. ":" .. reason)
        end
    end

    if expectedCount == 0 then
        local reason = handError and ("authoritative-hand-snapshot-missing; " .. tostring(handError))
            or "authoritative-hand-snapshot-missing"
        return false, readyCount, expectedCount, reason
    end
    return readyCount == expectedCount, readyCount, expectedCount, table.concat(missing, ",")
end

-- A resolved permanent can have two independent pieces of state in flight:
-- Forge's public zone mapping and TTS's last physical transform.  Keep the
-- diagnostic exact-id based so a stale semantic resolution can never make us
-- move a same-name permanent.  Card names are deliberately omitted here;
-- this trace is also emitted while a snapshot may contain private objects.
function BridgeTracePermanentTransition(marker, event, object, sourceZone, detail)
    local guid = object ~= nil and BridgeSafeObjectGuid(object) or nil
    local trackedZone = guid ~= nil and BridgeState.physicalZoneByGuid[guid] or nil
    local pending = event ~= nil and event.seatId ~= nil
        and BridgeState.pendingCastBySeatId[event.seatId] or nil
    local pendingForInstance = pending ~= nil and event ~= nil
        and pending.cardInstanceId == event.cardInstanceId
    local suffix = detail ~= nil and (" detail=" .. tostring(detail)) or ""
    BridgeLog(string.format(
        "[Bridge] %s instance=%s guid=%s sourceZone=%s destinationZone=%s trackedZone=%s pendingCast=%s eventSequence=%s snapshotSequence=%s%s",
        tostring(marker), tostring(event and event.cardInstanceId), tostring(guid),
        tostring(sourceZone or (event and event.sourceZone)),
        tostring(event and event.destinationZone), tostring(trackedZone),
        tostring(pendingForInstance == true), tostring(event and event.sequence),
        tostring(BridgeState.snapshotForgeSequence), suffix))
end

function BridgePhysicalObjectAtStackAnchor(object)
    if object == nil or type(object.getPosition) ~= "function" then return false end
    local ok, position = pcall(function() return object.getPosition() end)
    if not ok or position == nil then return false end
    local x = tonumber(position.x or position[1])
    local z = tonumber(position.z or position[3])
    if x == nil or z == nil then return false end
    local dx = x - BRIDGE_STACK_POSITION.x
    local dz = z - BRIDGE_STACK_POSITION.z
    return dx * dx + dz * dz < 0.75
end

function BridgeRetirePendingCastForInstance(seatId, cardInstanceId, guid, reason)
    if seatId == nil or cardInstanceId == nil then return false end
    local pending = BridgeState.pendingCastBySeatId[seatId]
    if pending == nil or pending.cardInstanceId ~= cardInstanceId then return false end
    if guid ~= nil and pending.guid ~= guid then return false end
    BridgeState.pendingCastBySeatId[seatId] = nil
    BridgeLog(string.format("[Bridge] retired exact pending cast instance=%s guid=%s reason=%s",
        tostring(cardInstanceId), tostring(guid), tostring(reason)))
    return true
end

function BridgeUiMarkDirty(reason)
    local ui = BridgeState.ui
    if ui == nil or not ui.mounted then return end
    ui.dirty = true
    ui.dirtyReason = reason
    if ui.flushScheduled then return end
    ui.flushScheduled = true
    BridgeWaitFrames(function()
        if BridgeState.ui == nil then return end
        BridgeState.ui.flushScheduled = false
        BridgeUiFlush()
    end, 1)
end

-- Opt-in coexistence diagnostic. Card Importer/Encoder code is external to
-- this repository, so capture the live Global UI tree before and after it
-- opens instead of replacing the tree or guessing its layout contract.
function BridgeDumpGlobalUiOwnership(label)
    local ok, xml = pcall(function() return UI.getXml() end)
    if not ok or xml == nil then
        BridgeLog("[Bridge] global UI ownership snapshot failed label=" .. tostring(label))
        return false
    end
    local ids = {}
    for id in string.gmatch(tostring(xml), 'id="([^"]+)"') do
        ids[#ids + 1] = id
    end
    BridgeLog("[Bridge] global UI ownership snapshot label=" .. tostring(label)
        .. " bytes=" .. tostring(#xml)
        .. " ids=" .. table.concat(ids, ","))
    return true
end
-- END GENERATED SOURCE: 10-state-diagnostics.lua
-- BEGIN GENERATED SOURCE: 20-ui-decisions.lua

function BridgeUiRecordEvent(event)
    local ui = BridgeState.ui
    if ui == nil or event == nil or event.containsHiddenIdentity == true or event.summary == nil then return end
    table.insert(ui.gameLog, tostring(event.summary))
    while #ui.gameLog > 4 do table.remove(ui.gameLog, 1) end
    BridgeUiMarkDirty("game-log")
end

function BridgeUiActionLabel(action)
    local label = action.shortLabel or action.displayName or action.actionKind or action.type or "Choose"
    if #tostring(label) > 96 then label = string.sub(tostring(label), 1, 93) .. "..." end
    return tostring(label)
end

function BridgeCreatureTypeClearDraft(reason)
    local ui = BridgeState.ui
    if ui == nil then return end
    ui.creatureTypeDecisionId = nil
    ui.creatureTypeDraftActionId = nil
    ui.creatureTypeOptions = {}
    BridgeLog("[Bridge] creature-type draft cleared reason=" .. tostring(reason or "unspecified"))
    BridgeUiMarkDirty("creature-type-clear")
end

function BridgeCreatureTypePrepare(decision)
    local ui = BridgeState.ui
    if ui == nil then return end
    if decision == nil or decision.kind ~= "creature_type_selection" then
        if ui.creatureTypeDecisionId ~= nil then BridgeCreatureTypeClearDraft("decision-kind-changed") end
        return
    end
    if ui.creatureTypeDecisionId ~= decision.decisionId then
        ui.creatureTypeDecisionId = decision.decisionId
        ui.creatureTypeDraftActionId = nil
        ui.creatureTypeOptions = {}
        for _, action in ipairs(decision.actions or {}) do
            table.insert(ui.creatureTypeOptions, {
                label = tostring(action.displayName or action.shortLabel or action.actionId),
                actionId = action.actionId
            })
        end
    end
end

function BridgeHudCreatureTypeChanged(player, value, id)
    local decision = BridgeState.lastDecision
    local ui = BridgeState.ui
    if decision == nil or decision.kind ~= "creature_type_selection"
        or ui == nil or ui.creatureTypeDecisionId ~= decision.decisionId
        or BridgeState.retiredChoiceDecisionIds[decision.decisionId] == true then
        return
    end
    local selected = tostring(value or "")
    for _, option in ipairs(ui.creatureTypeOptions or {}) do
        if option.label == selected then
            ui.creatureTypeDraftActionId = option.actionId
            BridgeLog("[Bridge] creature-type draft selected decision=" .. tostring(decision.decisionId)
                .. " action=" .. tostring(option.actionId))
            BridgeUiMarkDirty("creature-type-draft")
            return
        end
    end
    BridgeLog("[Bridge] ignored creature-type dropdown value not in Forge actions: " .. selected)
end

function BridgeHudCreatureTypeConfirm(player, value, id)
    local decision = BridgeState.lastDecision
    local ui = BridgeState.ui
    if decision == nil or decision.kind ~= "creature_type_selection"
        or ui == nil or ui.creatureTypeDecisionId ~= decision.decisionId
        or ui.creatureTypeDraftActionId == nil
        or not BridgeDecisionHasAction(decision, ui.creatureTypeDraftActionId) then
        BridgeShowError("creature type selection is stale or incomplete")
        return
    end
    BridgeClaimHumanTtsColor(decision.seatId, player)
    local actionId = ui.creatureTypeDraftActionId
    BridgeCreatureTypeClearDraft("confirmed")
    BridgeSubmitChoice(decision.decisionId, actionId, "creature_type_confirm")
end

function BridgeHudCreatureTypeCancel(player, value, id)
    local decision = BridgeState.lastDecision
    local ui = BridgeState.ui
    if decision == nil or decision.kind ~= "creature_type_selection"
        or ui == nil or ui.creatureTypeDecisionId ~= decision.decisionId then return end
    BridgeCreatureTypeClearDraft("cancelled")
end

function BridgeGraveyardClear(reason)
    local ui = BridgeState.ui
    if ui == nil then return end
    ui.graveyardActionRows = {}
    ui.graveyardFolderDecisionId = nil
    ui.graveyardFolderOpen = false
    ui.graveyardFolderPage = 1
    if reason ~= nil then BridgeLog("[Bridge] graveyard folder cleared reason=" .. tostring(reason)) end
end

function BridgeGraveyardPrepareDecision(decision, actions)
    local ui = BridgeState.ui
    if ui == nil then return actions or {} end
    if decision == nil or decision.sessionId ~= BridgeState.eventSessionId then
        if ui.graveyardFolderDecisionId ~= nil then BridgeGraveyardClear("decision-missing-or-session") end
        return actions or {}
    end

    local graveyard = {}
    for _, action in ipairs(actions or {}) do
        if string.lower(tostring(action.sourceZone or "")) == "graveyard" then
            table.insert(graveyard, action)
        end
    end
    if #graveyard <= BRIDGE_GRAVEYARD_ACTION_GROUP_THRESHOLD then
        if ui.graveyardFolderDecisionId ~= nil then BridgeGraveyardClear("folder-not-needed") end
        return actions or {}
    end

    if ui.graveyardFolderDecisionId ~= decision.decisionId then
        ui.graveyardFolderDecisionId = decision.decisionId
        ui.graveyardFolderOpen = false
        ui.graveyardFolderPage = 1
    end
    ui.graveyardActionRows = graveyard
    local pageCount = math.max(math.ceil(#graveyard / 24), 1)
    ui.graveyardFolderPage = math.min(math.max(tonumber(ui.graveyardFolderPage or 1) or 1, 1), pageCount)

    local root = {}
    local inserted = false
    for _, action in ipairs(actions or {}) do
        if string.lower(tostring(action.sourceZone or "")) == "graveyard" then
            if not inserted then
                table.insert(root, {
                    isGraveyardFolder = true,
                    displayName = "GRAVEYARD ACTIONS (" .. tostring(#graveyard) .. ")",
                    graveyardActionCount = #graveyard,
                    actionId = "graveyard-folder-" .. tostring(decision.decisionId)
                })
                inserted = true
            end
        else
            table.insert(root, action)
        end
    end
    return root
end

function BridgeUiTerminalLabel(terminal)
    if terminal == nil then return "" end
    if #(terminal.winnerSeatIds or {}) == 0 then return "DRAW" end
    for _, seatId in ipairs(terminal.winnerSeatIds or {}) do
        if seatId == "forge-player-1" then return "VICTORY" end
    end
    return "DEFEAT"
end

function BridgeUiFlush()
    local ui = BridgeState.ui
    if ui == nil or not ui.mounted or not ui.dirty then return end
    ui.dirty = false
    local decision = BridgeState.lastDecision
    local terminal = BridgeState.gameEnded
    local owner = BridgeState.currentTurnSeatId == "forge-player-1" and "YOUR TURN"
        or (BridgeState.currentTurnSeatId and "OPPONENT TURN" or "TURN OWNER UNKNOWN")
    local turn = BridgeTurnLabel() .. " — " .. owner .. " — " .. tostring(BridgeState.currentPhase or "WAITING")
    local human = BridgeState.playerStateBySeatId["forge-player-1"] or {}
    local opponent = BridgeState.playerStateBySeatId["forge-player-2"] or {}
    local mana = human.mana or {}
    BridgeUiSet("BridgeHudTop", "text", turn .. "   YOU " .. tostring(human.life or "?")
        .. "   OPP " .. tostring(opponent.life or "?") .. "   MANA "
        .. "W" .. tostring(mana.W or 0) .. " U" .. tostring(mana.U or 0) .. " B" .. tostring(mana.B or 0)
        .. " R" .. tostring(mana.R or 0) .. " G" .. tostring(mana.G or 0) .. " C" .. tostring(mana.C or 0))
    local priority = BridgeState.prioritySeatId == "forge-player-1" and "YOUR PRIORITY"
        or (BridgeState.prioritySeatId and "OPPONENT PRIORITY" or "NO PRIORITY")
    -- Keep phase and priority visibly distinct while presenting them together
    -- in the large status lane.  The phase ribbon is supplemental; this text
    -- remains readable when color updates are unavailable in a TTS client.
    local phaseStatus = tostring(BridgeState.currentPhase or "WAITING")
    BridgeUiSet("BridgeHudStatus", "text", terminal and "GAME OVER" or (priority .. " • " .. phaseStatus))
    BridgeUiSet("BridgeHudStatus", "color", terminal and "#F8FAFC" or BridgeHudPhaseColor(BridgeState.currentPhase))
    local castPreviewPending = BridgeState.pendingIntent ~= nil
        and BridgeState.pendingIntent.action ~= nil
        and BridgeState.pendingIntent.action.type == "cast_spell"
    local prompt = decision and (decision.prompt or decision.kind or "Choose an action") or "AI THINKING..."
    if castPreviewPending then
        prompt = "CAST PREVIEW — press CAST / CONFIRM or CANCEL / RETURN"
    end
    if decision ~= nil and decision.kind == "cost_selection" and decision.costKind == "crew" then
        prompt = "CREW — SELECT CREATURES"
    end
    if decision ~= nil and BridgeIsDiscardChoice(decision) then
        -- Keep post-mulligan discard explicit even when Forge's prompt is
        -- generic. Exact candidate/action identities remain Forge-owned.
        prompt = "DISCARD A CARD - SELECT IN ORANGE, THEN CONFIRM"
    elseif decision ~= nil and decision.kind == "mulligan"
        and tostring(decision.mulliganStage or "") == "bottom_selection" then
        prompt = "MULLIGAN - PUT CARD ON BOTTOM, THEN CONFIRM"
    end
    BridgeUiSet("BridgeHudPrompt", "text", terminal and BridgeUiTerminalLabel(terminal) or prompt)
    BridgeUiSet("BridgeHudMana", "text", "MANA: " .. tostring(ui.manaMode or "AUTO"))
    local yieldMode = BridgeYieldControllerMode ~= nil and BridgeYieldControllerMode() or "normal"
    BridgeUiSet("BridgeHudMode", "text", ui.autoPassEmpty and "AUTO-PASS: ON" or "AUTO-PASS: OFF")
    BridgeUiSet("BridgeHudFast", "text", ui.fastPlaytest and "FAST: ON" or "FAST: OFF")
    BridgeUiSet("BridgeHudLog", "text", ui.gameLogVisible and "LOG: ON" or "LOG: OFF")
    local help = yieldMode == "fast_forward" and "FAST-FORWARD: " .. (ui.fastForwardStopScope or "own_turn")
        or (yieldMode == "auto_pass_empty" and "AUTO-PASS: EMPTY PRIORITY"
            or "NORMAL: every human Forge decision requires input.")
    BridgeUiSet("BridgeHudHelp", "text", help)
    local actions = {}
    for _, action in ipairs(terminal and {} or (decision and decision.actions or {})) do
        if BridgeActionPresentationAuthorized(action) then
            table.insert(actions, action)
        end
    end
    BridgeCreatureTypePrepare(decision)
    if decision ~= nil and decision.kind == "creature_type_selection" then actions = {} end
    actions = BridgeGraveyardPrepareDecision(decision, actions)
    if ui.contextInstanceId ~= nil and decision ~= nil then
        local contextual = {}
        for _, action in ipairs(actions) do
            local source = action.preparedSourceCardInstanceId or action.sourceCardInstanceId or action.cardInstanceId
            if source == ui.contextInstanceId then table.insert(contextual, action) end
        end
        if #contextual > 0 then actions = contextual else ui.contextInstanceId = nil end
    end
    ui.actionRows = actions
    ui.actionPanelRenderCount = (ui.actionPanelRenderCount or 0) + 1
    ui.candidatePanelRenderCount = (ui.candidatePanelRenderCount or 0) + 1
    -- Forge's structured menus (including London-mulligan bottom selection)
    -- own their staged set. Do not mask its authoritative selectedCount with
    -- the legacy one-card local draft used by non-structured prompts.
    local selected = 0
    if decision ~= nil then
        if BridgeIsStructuredForgeToggleChoice(decision) then
            selected = tonumber(decision.selectedCount or 0) or 0
        elseif BridgeDecisionNeedsConfirmation(decision) then
            selected = BridgeSelectionCount()
        else
            selected = tonumber(decision.selectedCount or 0) or 0
        end
    end
    local min = tonumber(decision and decision.minSelections or 0) or 0
    local max = tonumber(decision and decision.maxSelections or 0) or 0
    local selectionText = decision and ("Selected: " .. tostring(selected) .. " / " .. tostring(max) .. " (min " .. tostring(min) .. ")") or ""
    if decision ~= nil and decision.kind == "cost_selection" and decision.costKind == "crew"
        and decision.requiredTotalPower ~= nil then
        selectionText = "TOTAL POWER " .. tostring(decision.selectedTotalPower or 0)
            .. " / " .. tostring(decision.requiredTotalPower)
    end
    BridgeUiSet("BridgeHudSelection", "text", selectionText)
    for i = 1, 24 do
        local action = actions[i]
        BridgeUiSet("BridgeHudAction" .. tostring(i), "active", action ~= nil and "true" or "false")
        if action ~= nil then
            if action.isGraveyardFolder == true then
                BridgeUiSet("BridgeHudAction" .. tostring(i), "text", action.displayName)
                BridgeUiSet("BridgeHudAction" .. tostring(i), "tooltip", "Open the exact Forge actions originating in your graveyard.")
            else
                -- Structured Forge choices retain selection on the Forge side;
                -- local draft state is only used by legacy single-card flows.
                -- Ordinary priority actions are immediate exact Forge inputs,
                -- not local checkbox selections. Reserve selection marks for
                -- Forge collections and combat redraws so a draw/main menu
                -- cannot misleadingly advertise multi-select behavior.
                local selectionPresentation = BridgeDecisionNeedsConfirmation(decision)
                    or decision.kind == "attacker_selection"
                    or decision.kind == "blocker_selection"
                    or decision.kind == "blocker_assignment"
                local prefix = ""
                if selectionPresentation then
                    prefix = (BridgeState.selectedActionIds[action.actionId] == true or action.isSelected == true)
                        and "[x] " or "[ ] "
                end
                BridgeUiSet("BridgeHudAction" .. tostring(i), "text", prefix .. BridgeUiActionLabel(action))
                BridgeUiSet("BridgeHudAction" .. tostring(i), "tooltip", "Forge action: " .. BridgeUiActionLabel(action)
                    .. "\nKind: " .. tostring(action.actionKind or action.type or "choice")
                    .. (action.sourceCardName and ("\nSource: " .. tostring(action.sourceCardName)) or ""))
            end
        end
    end
    -- Card context may intentionally narrow the action rows, but it must not
    -- hide Forge's priority controls. Pass/Yield are properties of the full
    -- authoritative decision, not of a contextual HUD subset.
    local hasPass = false
    local hasYield = false
    for _, action in ipairs(decision and decision.actions or {}) do
        if action.type == "pass_priority" then hasPass = true; hasYield = true end
    end
    local targetCanCancel = decision ~= nil and decision.allowsCancel == true
        and (decision.kind == "target_selection" or decision.kind == "defender_selection"
            or decision.kind == "player_selection")
    local yieldPolicyAvailable = BridgeState.gameEnded == nil
        and not BridgeDecisionNeedsConfirmation(decision)
        and BridgeState.pendingIntent == nil
    BridgeUiSet("BridgeHudPass", "active", hasPass and "true" or "false")
    -- Keep YIELD visible during an AI/opponent turn even when Forge is not
    -- currently waiting on a human decision; clicking it arms the policy and
    -- does not fabricate a pass. When a human pass decision exists, it uses
    -- the exact Forge action as before.
    BridgeUiSet("BridgeHudYield", "active", (hasYield or yieldPolicyAvailable) and "true" or "false")
    BridgeUiSet("BridgeHudConfirm", "active", (decision and BridgeDecisionNeedsConfirmation(decision))
        or castPreviewPending and "true" or "false")
    BridgeUiSet("BridgeHudConfirm", "text", castPreviewPending and "CAST / CONFIRM" or "CONFIRM")
    BridgeUiSet("BridgeHudConfirm", "tooltip", castPreviewPending
        and "Submit this Forge-approved spell after reviewing the cast preview."
        or "Submit the staged Forge selection when its required count is satisfied.")
    BridgeUiSet("BridgeHudCancel", "active", (castPreviewPending or (decision and
        ((BridgeDecisionNeedsConfirmation(decision) and not BridgeIsStructuredForgeToggleChoice(decision))
            or targetCanCancel))) and "true" or "false")
    BridgeUiSet("BridgeHudCancel", "text", castPreviewPending and "CANCEL / RETURN" or "CANCEL")
    BridgeUiSet("BridgeHudNewMatch", "active", terminal and "true" or "false")
    BridgeUiSet("BridgeHudNewMatch", "text", BridgeState.resetConfirmationArmed and "CONFIRM NEW MATCH" or "NEW MATCH")
    local footer = terminal and "NEW MATCH is available on the table."
        or (ui.contextInstanceId and "CARD CONTEXT — choose a Forge-provided action" or "Forge decides legality. Screen actions submit exact Forge choices.")
    if not terminal and #(BridgeState.stackSummary or {}) > 0 then footer = "STACK: " .. table.concat(BridgeState.stackSummary, " > ") end
    if not terminal and ui.gameLogVisible and #(ui.gameLog or {}) > 0 then footer = ui.gameLog[#ui.gameLog] end
    BridgeUiSet("BridgeHudFooter", "text", footer)
    if BridgeRenderRevealSurface ~= nil then BridgeRenderRevealSurface() end
end

function BridgeUiMount()
    local ui = BridgeState.ui
    if ui ~= nil and ui.mounted then return end
    pcall(function() UI.setAttribute("BridgeHudRoot", "active", "true") end)
    BridgeState.ui.mounted = true
    BridgeState.ui.uiAttributeCache = {}
    BridgeState.ui.uiFullRebuildCount = (BridgeState.ui.uiFullRebuildCount or 0) + 1
    BridgeUiMarkDirty("mount")
end

function BridgeHudAction(player, value, id)
    local index = tonumber(string.match(tostring(id or ""), "(%d+)$"))
    local ui, decision = BridgeState.ui, BridgeState.lastDecision
    local action = index and ui and ui.actionRows[index] or nil
    if action ~= nil and action.isGraveyardFolder == true then
        if decision ~= nil and ui.graveyardFolderDecisionId == decision.decisionId
            and BridgeState.retiredChoiceDecisionIds[decision.decisionId] ~= true then
            ui.graveyardFolderOpen = not ui.graveyardFolderOpen
            BridgeUiMarkDirty("graveyard-folder-toggle")
        end
        return
    end
    if BridgeState.gameEnded ~= nil or decision == nil or action == nil
        or decision.decisionId ~= BridgeState.lastDecision.decisionId
        or BridgeState.retiredChoiceDecisionIds[decision.decisionId] == true
        or not BridgeDecisionHasAction(decision, action.actionId) then return end
    BridgeClaimHumanTtsColor(decision.seatId, player)
    if BridgeDecisionNeedsConfirmation(decision) then
        -- A legacy discard menu may arrive as `card_selection`.  Discarding
        -- is a Forge action, not a local hand-selection draft: submit the
        -- exact card action immediately so Forge can move it to its graveyard.
        if action.type == "discard_card" and BridgeIsDiscardChoice(decision) then
            BridgeSubmitChoice(decision.decisionId, action.actionId, "hud_discard_card")
            return
        end
        -- Structured Forge collection menus use a real `Done` action after
        -- toggling choices. It is a commit, not another local selection.
        if action.type == "choose_none" then
            if BridgeIsStructuredForgeToggleChoice(decision) then
                BridgeConfirmSelection(nil, player, false)
                return
            end
            if not BridgeCanSubmitStructuredDone(decision, "hud_collection_done") then return end
            BridgeResetSelectionState()
            BridgeSubmitChoice(decision.decisionId, action.actionId, "hud_collection_done")
            return
        end
        if BridgeIsStructuredForgeToggleChoice(decision) then
            -- Forge has already modeled the selected set. Send the exact
            -- toggle now so searches and other non-physical option rows do
            -- not wait for a local confirmation that Forge cannot observe.
            BridgeSubmitChoice(decision.decisionId, action.actionId, "hud_structured_toggle")
            return
        end
        BridgeToggleSingleSelection(decision, action.actionId, nil)
        BridgeUiMarkDirty("selection-toggle")
        return
    end
    BridgeSubmitChoice(decision.decisionId, action.actionId, "hud_action")
end

function BridgeHudGraveyardAction(player, value, id)
    local ui, decision = BridgeState.ui, BridgeState.lastDecision
    local index = tonumber(string.match(tostring(id or ""), "(%d+)$"))
    local offset = ui and ((tonumber(ui.graveyardFolderPage or 1) - 1) * 24) or 0
    local action = index and ui and ui.graveyardActionRows[offset + index] or nil
    if BridgeState.gameEnded ~= nil or decision == nil or action == nil
        or ui.graveyardFolderDecisionId ~= decision.decisionId
        or not ui.graveyardFolderOpen
        or BridgeState.retiredChoiceDecisionIds[decision.decisionId] == true
        or not BridgeDecisionHasAction(decision, action.actionId) then return end
    BridgeClaimHumanTtsColor(decision.seatId, player)
    BridgeSubmitChoice(decision.decisionId, action.actionId, "hud_graveyard_action")
end

function BridgeHudGraveyardPage(player, value, id)
    local ui, decision = BridgeState.ui, BridgeState.lastDecision
    if ui == nil or decision == nil or ui.graveyardFolderDecisionId ~= decision.decisionId
        or not ui.graveyardFolderOpen then return end
    local pageCount = math.max(math.ceil(#(ui.graveyardActionRows or {}) / 24), 1)
    local page = tonumber(ui.graveyardFolderPage or 1) or 1
    if tostring(id or "") == "BridgeHudGraveyardPrev" then page = page - 1 else page = page + 1 end
    ui.graveyardFolderPage = math.min(math.max(page, 1), pageCount)
    BridgeUiMarkDirty("graveyard-folder-page")
end

function BridgeHudGraveyardClose(player, value, id)
    local ui, decision = BridgeState.ui, BridgeState.lastDecision
    if ui == nil or decision == nil or ui.graveyardFolderDecisionId ~= decision.decisionId then return end
    ui.graveyardFolderOpen = false
    BridgeUiMarkDirty("graveyard-folder-close")
end

function BridgeHudConfirm(player, value, id)
    if BridgeState.pendingIntent ~= nil and BridgeState.pendingIntent.action ~= nil
        and BridgeState.pendingIntent.action.type == "cast_spell" then
        BridgeConfirmCastPreview(nil, player, false)
        return
    end
    if BridgeState.lastDecision == nil or not BridgeDecisionNeedsConfirmation(BridgeState.lastDecision) then return end
    BridgeConfirmSelection(nil, player, false)
end

function BridgeHudCancel(player, value, id)
    if BridgeState.pendingIntent ~= nil and BridgeState.pendingIntent.action ~= nil
        and BridgeState.pendingIntent.action.type == "cast_spell" then
        BridgeCancelCastPreview(nil, player, false)
        return
    end
    BridgeCancelSelection(nil, player, false)
end

function BridgeHudNewMatch(player, value, id)
    if BridgeState.gameEnded == nil then return end
    if BridgeState.resetConfirmationArmed then
        BridgeDoPressConfirmNewMatch(player, false)
    else
        BridgeDoPressNewMatch(player, false)
        BridgeUiMarkDirty("new-match-confirm")
    end
end

function BridgeHudPass(player, value, id)
    local decision = BridgeState.lastDecision
    if decision == nil then return end
    for _, action in ipairs(decision.actions or {}) do
        if action.type == "pass_priority" then BridgeSubmitChoice(decision.decisionId, action.actionId, "hud_pass"); return end
    end
end

function BridgeArmYieldPolicy(activeSeat, reason)
    -- Compatibility entry point for the physical END TURN/YIELD control.
    -- It uses the same transient controller as FAST-FORWARD.
    BridgeState.yieldPolicyTurnNumber = tonumber(BridgeState.tableTurnCount or 0) or 0
    BridgeState.yieldPolicyActiveSeatId = activeSeat
    BridgeState.yieldPolicySessionId = BridgeState.eventSessionId
    BridgeState.yieldPolicyOwnTurn = activeSeat == "forge-player-1"
    if BridgeState.yieldPolicyOwnTurn then
        BridgeSetStatus("YIELDING REST OF TURN", "Forge will pass optional priority and finish your attack step using exact Forge actions.")
    else
        BridgeSetStatus("YIELD ARMED — STOPPING ON INTERACTION", "Forge will pass only empty opponent-turn priority windows.")
    end
    if BridgeState.eventSessionId ~= nil and BridgeState.gameEnded == nil then
        if not BridgeState.eventPolling then
            BridgeStartEventPolling(BridgeState.eventSessionId, false)
        end
        if BridgeState.lastDecision == nil and not BridgeState.submitting then
            BridgeStartDecisionPolling()
        end
    end
    BridgeStartFastForward(reason or "yield")
    -- Keep the established physical-control label while routing behavior
    -- through the shared fast-forward controller.
    if BridgeState.ui ~= nil then BridgeState.ui.autoAdvanceMode = "YIELD" end
    BridgeLog("[Bridge] yield policy armed activeSeat=" .. tostring(activeSeat)
        .. " ownTurn=" .. tostring(BridgeState.yieldPolicyOwnTurn)
        .. " reason=" .. tostring(reason or "user"))
end

function BridgeHudYield(player, value, id)
    local decision = BridgeState.lastDecision
    local activeSeat = BridgeState.currentTurnSeatId
    -- Yield is a turn-scoped policy. During the opponent's turn it must arm
    -- the policy even when Forge is between AI priority windows; if a real
    -- human response is already required, leave that decision untouched so
    -- the policy stops at the intervention boundary.
    BridgeArmYieldPolicy(activeSeat, decision == nil and "no-human-decision" or "hud-yield")
    if decision ~= nil then BridgeRenderDecision(decision, true) end
end

function BridgeDisarmYieldPolicy(reason)
    if BridgeState.ui ~= nil and BridgeState.ui.fastForwardActive == true then
        BridgeState.ui.fastForwardActive = false
        BridgeState.ui.fastForwardSessionId = nil
        BridgeState.ui.fastForwardTurnNumber = nil
        BridgeState.ui.fastForwardActiveSeatId = nil
    end
    if BridgeState.yieldPolicyTurnNumber ~= nil then
        BridgeState.yieldPolicyTurnNumber = nil
        BridgeState.yieldPolicyActiveSeatId = nil
        BridgeState.yieldPolicySessionId = nil
        BridgeState.yieldPolicyOwnTurn = false
        if BridgeState.ui ~= nil then
            BridgeState.ui.autoAdvanceMode = BridgeState.ui.autoPassEmpty and "AUTO-PASS EMPTY" or "NORMAL"
            BridgeUiMarkDirty("yield-policy-stopped")
        end
        BridgeLog("[Bridge] yield policy stopped reason=" .. tostring(reason))
    end
end

function BridgeAutomaticDecisionBlocked(decision)
    if decision == nil or decision.decisionId == nil or decision.decisionId == "" then return "no-current-decision" end
    if BridgeState.desyncLatched == true then return "desync-latched" end
    if BridgeState.resyncInFlight == true or BridgeState.resyncScheduled == true then return "resync-active" end
    local ui = BridgeState.ui or {}
    if ui.reportCaptureInFlight == true then return "diagnostic-capture" end
    local received = tonumber(BridgeState.lastReceivedEventSequence or 0) or 0
    local applied = tonumber(BridgeState.lastAppliedEventSequence or 0) or 0
    if received ~= applied or #(BridgeState.eventQueue or {}) > 0 then return "event-backpressure" end
    local cursor = tonumber(decision.eventCursor or 0) or 0
    local projected = math.max(applied, tonumber(BridgeState.lastStateProjectedEventSequence or 0) or 0)
    if cursor > 0 and cursor > projected then return "decision-cursor-mismatch" end
    return nil
end

function BridgeConsiderYieldAutomaticAction(decision, action, policy)
    if decision == nil or action == nil then return false end
    local blockedReason = BridgeAutomaticDecisionBlocked(decision)
    if blockedReason ~= nil then
        BridgeRecordDecisionLifecycle(decision, "yield", "AUTO_ACTION_BLOCKED", blockedReason,
            action.actionId, action.type or action.actionType, policy, "blocked")
        return false
    end
    local actionType = tostring(action.type or action.actionType or "unknown")
    local result = "submitted"
    if BridgeAutomaticPassBackpressured() then
        result = "blocked_backpressure"
        BridgeRecordDecisionLifecycle(decision, "yield", "AUTO_ACTION_BLOCKED", "event-backpressure",
            action.actionId, actionType, policy, result)
        return false
    end
    BridgeRecordDecisionLifecycle(decision, "yield", "AUTO_ACTION_CONSIDERED", "yield-policy",
        action.actionId, actionType, policy, result)
    local submitSource = policy == "FAST_FORWARD"
        and "fast_forward"
        or policy == "AUTO_PASS_EMPTY"
        and "auto_pass_empty"
        or policy == "OWN_TURN_YIELD"
        and ((actionType == "finish_attacking" or actionType == "choose_none")
            and "own_turn_yield_auto_finish_attacking" or "own_turn_yield_auto_pass")
        or "yield_policy_auto_pass"
    BridgeSubmitChoice(decision.decisionId, action.actionId, submitSource)
    return true
end

function BridgeHudMode(player, value, id)
    BridgeSetAutoPassEmpty(not (BridgeState.ui and BridgeState.ui.autoPassEmpty == true), "hud")
end

function BridgeHudFast(player, value, id)
    BridgeState.ui.fastPlaytest = not BridgeState.ui.fastPlaytest
    BridgeUiMarkDirty("fast-playtest")
end

function BridgeHudMana(player, value, id)
    BridgeState.ui.manaMode = BridgeState.ui.manaMode == "AUTO" and "MANUAL SOURCES" or "AUTO"
    BridgeUiMarkDirty("mana-mode")
end

function BridgeHudLog(player, value, id)
    BridgeState.ui.gameLogVisible = not BridgeState.ui.gameLogVisible
    BridgeUiMarkDirty("game-log-toggle")
end

function BridgeOpenCardContext(cardInstanceId)
    if cardInstanceId == nil or BridgeState.lastDecision == nil then return end
    BridgeState.ui.contextInstanceId = cardInstanceId
    BridgeUiMarkDirty("card-context")
end

-- Forge owns draws. The legacy button remains present, but cannot mutate the
-- physical library independently of an authoritative Forge transition.
function drawSwap(me, clickerColor)
    BridgeShowError("manual Draw is disabled while Forge is authoritative; wait for Forge's draw event")
end

function BridgeGetHealth(callback)
    BridgeHttp.requestJson("GET", "/health", nil, function(ok, body, err, request)
        if ok and body ~= nil and BridgeObserveBridgeHealth ~= nil then
            BridgeObserveBridgeHealth(body)
        end
        if callback ~= nil then callback(ok, body, err, request) end
    end)
end

function BridgeStartSession(callback)
    BridgeSetupTrace("SESSION_START_REQUEST_SENT", "POST /api/v1/session/start")
    BridgeHttp.requestJson("POST", "/api/v1/session/start", nil, callback)
end

function BridgeResetSessionRequest(callback)
    BridgeHttp.requestJson("POST", "/api/v1/session/reset", nil, callback)
end

function BridgeNormalizedDeckFormat()
    local value = string.lower(tostring(BridgeState.selectedFormat or BRIDGE_DEFAULT_MATCH_FORMAT or "limited"))
    if value == "standard" or value == "legacy" then return "constructed" end
    if value == "constructed" or value == "limited" then return value end
    return value
end

function BridgeDeckMinimumForFormat(format)
    local normalized = string.lower(tostring(format or ""))
    if normalized == "limited" then return 40 end
    if normalized == "constructed" then return 60 end
    return nil
end

function BridgeDeckCardCount(deck)
    if deck == nil or not BridgeObjectIsUsable(deck) then return 0 end
    if deck.tag == "Deck" then return #(deck.getObjects() or {}) end
    if deck.tag == "Card" then return 1 end
    return 0
end

function BridgeBuildDeckGuidManifest(deck)
    local manifest = {}
    if deck == nil or not BridgeObjectIsUsable(deck) then return manifest end
    if deck.tag == "Deck" then
        for _, entry in ipairs(deck.getObjects() or {}) do
            if entry ~= nil and tostring(entry.guid or "") ~= "" then
                manifest[tostring(entry.guid)] = true
            end
        end
    elseif deck.tag == "Card" then
        local guid = BridgeSafeObjectGuid(deck)
        if guid ~= nil then manifest[tostring(guid)] = true end
    end
    return manifest
end

function BridgeCollectManagedCardPreflightIssues(humanDeck, aiDeck)
    local allowed = BridgeBuildDeckGuidManifest(humanDeck)
    local aiAllowed = BridgeBuildDeckGuidManifest(aiDeck)
    for guid, _ in pairs(aiAllowed) do allowed[guid] = true end

    local stale = {}
    local byInstanceId = {}
    for _, object in ipairs(getAllObjects() or {}) do
        if BridgeObjectIsUsable(object) and object.tag == "Card" then
            local guid = BridgeSafeObjectGuid(object)
            local instanceId = BridgeReadPhysicalIdentity(object)
            local sessionId = BridgeReadPhysicalSessionIdentity(object)
            if guid ~= nil and (instanceId ~= nil or sessionId ~= nil) then
                if allowed[tostring(guid)] ~= true then
                    table.insert(stale, string.format("%s(instance=%s,session=%s)", tostring(guid), tostring(instanceId), tostring(sessionId)))
                end
                if instanceId ~= nil then
                    byInstanceId[instanceId] = byInstanceId[instanceId] or {}
                    table.insert(byInstanceId[instanceId], guid)
                end
            end
        end
    end

    local duplicates = {}
    for instanceId, guids in pairs(byInstanceId) do
        if #guids > 1 then
            table.sort(guids)
            table.insert(duplicates, string.format("%s=>%s", tostring(instanceId), table.concat(guids, ",")))
        end
    end
    table.sort(stale)
    table.sort(duplicates)
    return stale, duplicates
end

function BridgeStartMatchPreflight(humanDeck, aiDeck)
    if BridgeState.eventSessionId ~= nil and BridgeState.eventSessionId ~= "session-not-started" then
        return false, "an active TTS session already exists; use NEW MATCH for cleanup"
    end
    if BridgeState.eventPolling == true or BridgeState.decisionPollInFlight == true
        or BridgeState.resyncInFlight == true or BridgeState.bootstrapping == true then
        return false, "bridge is not in clean setup state; use NEW MATCH to clean existing match state"
    end

    local stale, duplicates = BridgeCollectManagedCardPreflightIssues(humanDeck, aiDeck)
    if #stale > 0 then
        return false, "managed cards from a previous session are still live outside deck piles: " .. table.concat(stale, "; ")
    end
    if #duplicates > 0 then
        return false, "duplicate cardInstanceId identities detected: " .. table.concat(duplicates, "; ")
    end

    local format = BridgeNormalizedDeckFormat()
    local provenance = tostring(BridgeState.selectedFormatProvenance or "")
    if provenance == "" then
        return false, "format provenance missing; configure explicit format provenance before START MATCH"
    end
    local minimum = BridgeDeckMinimumForFormat(format)
    if minimum == nil then
        return false, "unsupported selected format '" .. tostring(format) .. "'"
    end
    local humanCards = BridgeDeckCardCount(humanDeck)
    local aiCards = BridgeDeckCardCount(aiDeck)
    local override = BridgeState.allowDeckMinimumOverride == true
    if not override and (humanCards < minimum or aiCards < minimum) then
        return false, string.format(
            "deck count below minimum for %s (min=%d): humanCards=%d aiCards=%d",
            tostring(format), minimum, humanCards, aiCards)
    end
    if override then
        BridgeLog(string.format(
            "[Bridge] DECK_VALIDATION_OVERRIDE enabled=true format=%s min=%d provenance=%s humanCards=%d aiCards=%d",
            tostring(format), minimum, tostring(provenance), humanCards, aiCards))
    end
    BridgeSetupTrace("START_PREFLIGHT_OK", string.format(
        "format=%s provenance=%s min=%s override=%s humanCards=%s aiCards=%s",
        tostring(format), tostring(provenance), tostring(minimum), tostring(override), tostring(humanCards), tostring(aiCards)))
    return true, nil
end

-- TTS's imported library piles are the deck chooser.  We send printed
-- identities and explicit format provenance so Bridge-side validation never
-- falls back to an implicit format assumption.
function BridgeConfigureDecks(callback)
    local seats = {}
    for _, seatId in ipairs({"forge-player-1", "forge-player-2"}) do
        BridgeSetupTrace("DECK_PILE_SCAN_BEGIN", "seat=" .. tostring(seatId))
        local deck, _, deckError = BridgeResolveSeatLibraryDeck(seatId)
        if deck == nil then
            BridgeSetupTrace("DECK_PILE_SCAN_RESULT", "seat=" .. tostring(seatId) .. " pileGuid=nil objectType=nil cardCount=0 detectedFormat=unknown error=" .. tostring(deckError))
            callback(false, nil, "cannot load TTS library for " .. tostring(seatId) .. ": " .. tostring(deckError)); return
        end
        local counts = {}
        local containedCards = deck.getObjects() or {}
        for _, contained in ipairs(containedCards) do
            local name = BridgeImportedCardName(contained.nickname or contained.name or "")
            if BridgeNormalizeCardName(name) ~= "" then counts[name] = (counts[name] or 0) + 1 end
        end
        local cards = {}
        for name, count in pairs(counts) do table.insert(cards, {cardName = name, count = count}) end
        BridgeSetupTrace("DECK_PILE_SCAN_RESULT", string.format(
            "seat=%s pileGuid=%s objectType=%s cardCount=%s detectedFormat=%s uniqueNames=%s",
            tostring(seatId), tostring(BridgeSafeObjectGuid(deck)), tostring(deck.tag), tostring(#containedCards),
            tostring(BridgeState.selectedFormat or "unknown"), tostring(#cards)))
        if #cards == 0 then callback(false, nil, "TTS library is empty for " .. tostring(seatId)); return end
        BridgeLog(string.format("[Bridge] TTS deck inventory seat=%s uniqueNames=%d totalCards=%d revision=%s",
            tostring(seatId), #cards, #(deck.getObjects() or {}), tostring(BRIDGE_SCRIPT_REVISION)))
        table.insert(seats, {seatId = seatId, cards = cards})
    end
    local selectedFormat = BridgeNormalizedDeckFormat()
    local formatProvenance = tostring(BridgeState.selectedFormatProvenance or "")
    local allowMinimumOverride = BridgeState.allowDeckMinimumOverride == true
    BridgeSetupStage("VALIDATING_DECKS", "posting TTS deck inventory")
    BridgeLog("[Bridge] posting TTS deck inventory to /api/v1/decks")
    BridgeHttp.requestJson("POST", "/api/v1/decks", {
        seats = seats,
        format = selectedFormat,
        formatProvenance = formatProvenance,
        allowDeckMinimumOverride = allowMinimumOverride
    }, function(ok, body, err, request)
        BridgeSetupTrace("DECK_VALIDATION_RESULT", "ok=" .. tostring(ok) .. " error=" .. tostring(err or "none"))
        if ok then BridgeLog("[Bridge] TTS deck inventory accepted by bridge")
        else BridgeLog("[Bridge] TTS deck inventory rejected: " .. tostring(err) .. " body=" .. tostring(body and JSON.encode(body) or "(empty)")) end
        callback(ok, body, err, request)
    end)
end

function BridgeHttpFailureDetail(body, fallback)
    if body ~= nil and body.message ~= nil and tostring(body.message) ~= "" then
        return tostring(body.message)
    end
    return tostring(fallback or "request failed")
end

function BridgeGetDecision(callback)
    -- The caller owns state changes after it validates the response's session
    -- and presentation generation.  Mutating BridgeState here would let a
    -- delayed response clear or replace a newer decision before that check.
    BridgeHttp.requestJson("GET", "/api/v1/decision", nil, callback)
end

function BridgeStopDecisionPolling()
    BridgeState.decisionPollGeneration = BridgeState.decisionPollGeneration + 1
    BridgeState.decisionPollInFlight = false
    BridgeState.decisionPollScheduled = false
    BridgeState.decisionPollScheduledAt = nil
    BridgeState.decisionPollDueAt = nil
    BridgeState.decisionPollTimerToken = nil
end

function BridgeDecisionPollNow()
    return os.clock()
end

-- A scheduled flag is only a claim made by the scheduler.  The timer token
-- and deadline make that claim auditable and let the frame watchdog recover a
-- callback which TTS silently drops.
function BridgeCheckDecisionPollingLiveness(reason)
    if BridgeState.gameEnded ~= nil or BridgeState.eventSessionId == nil
        or BridgeState.submitting or BridgeState.choiceProtocolPaused then return false end

    local now = BridgeDecisionPollNow()
    if BridgeState.decisionPollScheduled == true
        and BridgeState.decisionPollDueAt ~= nil
        and now >= tonumber(BridgeState.decisionPollDueAt) then
        BridgeLog(string.format("[Bridge] DECISION_POLL_TIMER_LOST reason=%s token=%s due=%s now=%s",
            tostring(reason), tostring(BridgeState.decisionPollTimerToken),
            tostring(BridgeState.decisionPollDueAt), tostring(now)))
        BridgeState.decisionPollScheduled = false
        BridgeState.decisionPollScheduledAt = nil
        BridgeState.decisionPollDueAt = nil
        BridgeState.decisionPollTimerToken = nil
        BridgeState.lastDecisionPollOutcome = "timer_lost"
    end

    -- A current decision is presentation state, not proof that a poller is
    -- alive.  The normal caller may explicitly allow a same-decision refresh.
    if BridgeState.lastDecision == nil
        and not BridgeState.decisionPollInFlight
        and not BridgeState.decisionPollScheduled then
        BridgeLog("[Bridge] DECISION_POLL_LIVENESS_REARM reason=" .. tostring(reason))
        BridgeStartDecisionPolling()
        return true
    end
    return false
end

function BridgeMarkTransitionExpected(seconds)
    local duration = tonumber(seconds or 0) or 0
    if duration <= 0 then
        BridgeState.transitionExpectedUntil = 0
        return
    end
    BridgeState.transitionExpectedUntil = os.clock() + duration
end

function BridgeTransitionExpected()
    local untilTs = tonumber(BridgeState.transitionExpectedUntil or 0) or 0
    return untilTs > 0 and os.clock() <= untilTs
end

function BridgeCurrentEventPollDelay()
    if BridgeTransitionExpected()
        or BridgeState.submitting
        or BridgeState.pendingDecision ~= nil
        or #BridgeState.eventQueue > 0 then
        return BRIDGE_EVENT_POLL_INTERVAL_ACTIVE
    end
    return BRIDGE_EVENT_POLL_INTERVAL_IDLE
end

function BridgeRecordLatencyProbeDecisionReady(decision)
    local probe = BridgeState.latencyProbe
    if probe == nil or probe.nextDecisionAt ~= nil then return end
    probe.nextDecisionAt = os.clock()
    local submitMs = math.floor((probe.acceptedAt - probe.submittedAt) * 1000)
    local eventMs = probe.firstEventReceivedAt ~= nil and math.floor((probe.firstEventReceivedAt - probe.acceptedAt) * 1000) or -1
    local turnMs = probe.turnChangedAppliedAt ~= nil and math.floor((probe.turnChangedAppliedAt - probe.acceptedAt) * 1000) or -1
    local decisionMs = math.floor((probe.nextDecisionAt - probe.acceptedAt) * 1000)
    BridgeLog(string.format(
        "[Bridge latency] action=%s submit=%dms firstEvent=%sms turnChanged=%sms nextDecision=%dms total=%dms decision=%s",
        tostring(probe.actionId),
        submitMs,
        eventMs >= 0 and tostring(eventMs) or "n/a",
        turnMs >= 0 and tostring(turnMs) or "n/a",
        decisionMs,
        math.floor((probe.nextDecisionAt - probe.submittedAt) * 1000),
        tostring(decision and decision.decisionId)))
    BridgeState.latencyProbe = nil
end

function BridgeScheduleDecisionPoll(delay, generation, attempt, allowCurrentDecision)
    if BridgeState.gameEnded ~= nil then return end
    if generation ~= BridgeState.decisionPollGeneration then return end
    if (BridgeState.lastDecision ~= nil and allowCurrentDecision ~= true) or BridgeState.submitting then return end
    if BridgeState.decisionPollInFlight or BridgeState.decisionPollScheduled then return end

    local nextDelay = delay or 0.1
    -- FAST is for a known short authoritative transition, not a blanket
    -- override of Forge's normal no-decision backoff. Polling an idle Forge at
    -- 20 Hz can race a just-drawn card's physical embodiment and repeatedly
    -- retry the same presentation work before the 0.5 s authoritative wait.
    if BridgeState.ui ~= nil and BridgeState.ui.fastPlaytest and BridgeTransitionExpected() then
        nextDelay = math.min(nextDelay, 0.05)
    end
    BridgeState.decisionPollScheduled = true
    BridgeState.decisionPollScheduledAt = BridgeDecisionPollNow()
    BridgeState.decisionPollDueAt = BridgeState.decisionPollScheduledAt + nextDelay
    BridgeState.decisionPollTimerToken = (BridgeState.decisionPollTimerToken or 0) + 1
    local timerToken = BridgeState.decisionPollTimerToken
    BridgeWaitTime(function()
        if generation ~= BridgeState.decisionPollGeneration then return end
        if BridgeState.decisionPollTimerToken ~= timerToken then return end
        BridgeState.decisionPollScheduled = false
        BridgeState.decisionPollScheduledAt = nil
        BridgeState.decisionPollDueAt = nil
        BridgeState.decisionPollTimerToken = nil
        BridgeState.lastDecisionPollStartedAt = BridgeDecisionPollNow()
        BridgeState.lastDecisionPollOutcome = "started"
        BridgePollForNextDecision(generation, attempt, allowCurrentDecision)
    end, nextDelay)
end

function BridgeYieldControllerMode()
    local ui = BridgeState.ui or {}
    if ui.fastForwardActive == true then return "fast_forward" end
    if ui.autoPassEmpty == true then return "auto_pass_empty" end
    return "normal"
end

function BridgeYieldPhaseKey(value)
    local phase = string.upper(tostring(value or ""))
    if string.find(phase, "UPKEEP", 1, true) then return "upkeep" end
    if string.find(phase, "DRAW", 1, true) then return "draw" end
    if string.find(phase, "MAIN", 1, true) then
        if string.find(phase, "POST", 1, true) or string.find(phase, "MAIN 2", 1, true) then return "main_postcombat" end
        return "main_precombat"
    end
    if string.find(phase, "BEGINNING", 1, true) and string.find(phase, "COMBAT", 1, true) then return "beginning_combat" end
    if string.find(phase, "ATTACK", 1, true) then return "declare_attackers" end
    if string.find(phase, "BLOCK", 1, true) then return "declare_blockers" end
    if string.find(phase, "DAMAGE", 1, true) then return "combat_damage" end
    if string.find(phase, "END OF COMBAT", 1, true) then return "end_combat" end
    if string.find(phase, "END", 1, true) then return "end_step" end
    return nil
end

function BridgeYieldScopeForDecision(decision)
    local active = decision and (decision.activeSeatId or decision.seatId) or BridgeState.currentTurnSeatId
    return active == "forge-player-1" and "own_turn" or "other_turn"
end

function BridgeYieldRecord(decision, disposition, reason, policy, action)
    if decision == nil or BridgeRecordDecisionLifecycle == nil then return end
    BridgeRecordDecisionLifecycle(decision, "yield-controller", disposition, reason,
        action and action.actionId or nil, action and action.type or nil, policy, reason)
end

function BridgeSetAutoPassEmpty(enabled, reason)
    local ui = BridgeState.ui
    if ui == nil then return end
    ui.autoPassEmpty = enabled == true
    if not ui.fastForwardActive then ui.autoAdvanceMode = ui.autoPassEmpty and "AUTO-PASS EMPTY" or "NORMAL" end
    BridgeSetStatus(ui.autoPassEmpty and "AUTO-PASS: EMPTY PRIORITY" or "NORMAL MODE",
        ui.autoPassEmpty and "Only pass-only human priority decisions will be submitted automatically." or "Every human Forge decision is presented normally.")
    BridgeUiMarkDirty("auto-pass-empty-" .. tostring(reason or "user"))
end

function BridgeToggleYieldPhaseStop(scope, phaseKey)
    local ui = BridgeState.ui
    if ui == nil or (scope ~= "own_turn" and scope ~= "other_turn") or phaseKey == nil then return end
    ui.fastForwardStops = ui.fastForwardStops or {own_turn = {}, other_turn = {}}
    local stops = ui.fastForwardStops[scope] or {}
    stops[phaseKey] = not (stops[phaseKey] == true)
    ui.fastForwardStops[scope] = stops
    BridgeUiMarkDirty("phase-stop-" .. scope .. "-" .. phaseKey)
end

function BridgeClearYieldPhaseStops()
    local ui = BridgeState.ui
    if ui == nil then return end
    ui.fastForwardStops = {own_turn = {}, other_turn = {}}
    BridgeUiMarkDirty("phase-stops-cleared")
end

function BridgeStartFastForward(reason)
    local ui = BridgeState.ui
    if ui == nil or BridgeState.gameEnded ~= nil then return end
    if BridgeState.schedulerOwner == "RESYNC" or BridgeState.resyncInFlight == true
        or BridgeState.bootstrapping == true then
        BridgeState.fastForwardSuspendedByResync = true
        BridgeLog("[Bridge] FAST_FORWARD_SUSPENDED reason=resync-active")
        return
    end
    ui.fastForwardActive = true
    ui.fastForwardSessionId = BridgeState.eventSessionId
    ui.fastForwardTurnNumber = tonumber(BridgeState.tableTurnCount or 0) or 0
    ui.fastForwardActiveSeatId = BridgeState.currentTurnSeatId
    ui.autoAdvanceMode = "FAST-FORWARD"
    BridgeSetStatus("FAST-FORWARD ACTIVE", "Stops at configured phase gates or any required human choice.")
    BridgeUiMarkDirty("fast-forward-started")
    BridgeLog("[Bridge] fast_forward_started reason=" .. tostring(reason or "user"))
    if BridgeState.eventSessionId ~= nil then
        if not BridgeState.eventPolling then BridgeStartEventPolling(BridgeState.eventSessionId, false) end
        if BridgeState.lastDecision == nil and not BridgeState.submitting then BridgeStartDecisionPolling() end
    end
    if BridgeState.lastDecision ~= nil then BridgeRenderDecision(BridgeState.lastDecision, true) end
end

function BridgeCancelFastForward(reason)
    local ui = BridgeState.ui
    if ui == nil or ui.fastForwardActive ~= true then return end
    ui.fastForwardActive = false
    ui.fastForwardSessionId = nil
    ui.fastForwardTurnNumber = nil
    ui.fastForwardActiveSeatId = nil
    ui.autoAdvanceMode = ui.autoPassEmpty and "AUTO-PASS EMPTY" or "NORMAL"
    BridgeSetStatus("FAST-FORWARD CANCELLED", tostring(reason or "user"))
    BridgeUiMarkDirty("fast-forward-cancelled")
    BridgeLog("[Bridge] fast_forward_cancelled reason=" .. tostring(reason or "user"))
end

function BridgeHudFastForward(player, value, id)
    if BridgeState.ui and BridgeState.ui.fastForwardActive then BridgeCancelFastForward("manual")
    else BridgeStartFastForward("manual") end
end

function BridgeHudYieldPhaseStop(player, value, id)
    local names = {
        Upkeep = "upkeep", Draw = "draw", MainPre = "main_precombat",
        BeginningCombat = "beginning_combat", Attackers = "declare_attackers",
        Blockers = "declare_blockers", Damage = "combat_damage",
        EndCombat = "end_combat", MainPost = "main_postcombat", EndStep = "end_step"
    }
    local raw = string.match(tostring(id or ""), "BridgeHudStop[^_]*_(.+)$")
    local scope = string.find(tostring(id or ""), "BridgeHudStopOwn_", 1, true) == 1 and "own_turn" or "other_turn"
    local phaseKey = names[raw]
    if phaseKey ~= nil then BridgeToggleYieldPhaseStop(scope, phaseKey) end
end

function BridgeHudClearYieldStops(player, value, id)
    BridgeClearYieldPhaseStops()
end

function BridgePollForNextDecision(generation, attempt, allowCurrentDecision)
    if BridgeState.gameEnded ~= nil then return end
    if BridgeState.schedulerOwner == "RESYNC" then return end
    if generation ~= BridgeState.decisionPollGeneration then return end
    if (BridgeState.lastDecision ~= nil and allowCurrentDecision ~= true) or BridgeState.submitting then return end
    if BridgeState.decisionPollInFlight then return end

    local expectedSessionId = BridgeState.eventSessionId
    local presentationGeneration = BridgeState.decisionPresentationGeneration
    BridgeState.decisionPollInFlight = true
    BridgeState.lastDecisionPollStartedAt = BridgeDecisionPollNow()
    BridgeHttp.requestJson("GET", "/api/v1/decision", nil, function(ok, body, err, request)
        if generation ~= BridgeState.decisionPollGeneration then return end
        if not ok and body ~= nil and body.errorCode == "session_not_started" then
            BridgeCleanupLocalSession("decision-no-session", BRIDGE_LIFECYCLE_READY_NO_SESSION)
            return
        end
        if expectedSessionId ~= BridgeState.eventSessionId
            or presentationGeneration ~= BridgeState.decisionPresentationGeneration then return end

        BridgeState.decisionPollInFlight = false
        BridgeState.lastDecisionPollCompletedAt = BridgeDecisionPollNow()
        if ok and body ~= nil then
            BridgeState.lastDecisionPollOutcome = "decision"
            BridgeState.decisionAuthoritativeWatermark = body.eventCursor
            BridgeMarkTransitionExpected(0)
            BridgeRecordLatencyProbeDecisionReady(body)
            BridgeAcceptDecision(body, "decision_poll", expectedSessionId, presentationGeneration)
            return
        end

        local responseCode = request and tonumber(request.response_code) or nil
        local noPendingDecision = (body ~= nil and body.errorCode == "no_pending_decision") or responseCode == 404
        if noPendingDecision then
            BridgeState.lastDecisionPollOutcome = "no_pending_decision"
            if attempt == 1 or attempt % 10 == 0 then
                BridgeLog("[Bridge] waiting for Forge's next decision...")
            end
            if attempt >= 180 then
                BridgeShowError("Forge did not expose a follow-up decision within 90 seconds")
                return
            end
            local retryDelay = BridgeTransitionExpected() and 0.1 or 0.5
            if BridgeTransitionExpected() and attempt > 40 then
                BridgeMarkTransitionExpected(0)
                retryDelay = 0.5
            end
            BridgeScheduleDecisionPoll(retryDelay, generation, attempt + 1, allowCurrentDecision)
            return
        end

        BridgeShowError("decision poll failed: " .. tostring(err))
        BridgeState.lastDecisionPollOutcome = "failed"
        BridgeScheduleDecisionPoll(1.0, generation, attempt + 1, allowCurrentDecision)
    end)
end

function BridgeStartDecisionPolling(allowCurrentDecision)
    if BridgeState.gameEnded ~= nil then return end
    if BridgeState.schedulerOwner == "RESYNC" then return end
    BridgeStopDecisionPolling()
    BridgeScheduleDecisionPoll(BridgeTransitionExpected() and 0.1 or 0.25,
        BridgeState.decisionPollGeneration, 1, allowCurrentDecision == true)
end

-- State-changing events can invalidate the currently rendered decision even
-- while it is still non-nil. Fetch exactly one authoritative replacement and
-- feed it through the normal decision acceptance/readiness path.
function BridgeRefreshDecisionAfterStateTransition(reason)
    if BridgeState.eventSessionId == nil or BridgeState.gameEnded ~= nil
        or BridgeState.desyncLatched or BridgeState.decisionRefreshInFlight then
        return
    end

    local expectedSessionId = BridgeState.eventSessionId
    local presentationGeneration = BridgeState.decisionPresentationGeneration
    BridgeState.decisionRefreshInFlight = true
    BridgeLog("[Bridge] requesting authoritative decision refresh reason=" .. tostring(reason))
    BridgeGetDecision(function(ok, body, err)
        if expectedSessionId ~= BridgeState.eventSessionId
            or presentationGeneration ~= BridgeState.decisionPresentationGeneration then
            BridgeState.decisionRefreshInFlight = false
            BridgeLog("[Bridge] ignored delayed transition decision refresh")
            return
        end

        BridgeState.decisionRefreshInFlight = false
        if ok and body ~= nil then
            BridgeAcceptDecision(body, "state_transition_refresh", expectedSessionId, presentationGeneration)
        else
            BridgeLog("[Bridge] state transition decision refresh failed: " .. tostring(err))
        end
    end)
end

function BridgeDecisionHasAction(decision, actionId)
    if decision == nil or actionId == nil then return false end
    for _, action in ipairs(decision.actions or {}) do
        if action.actionId == actionId then return true end
    end
    return false
end

function BridgeDecisionNeedsConfirmation(decision)
    if decision == nil then return false end
    return decision.requiresConfirmation == true or decision.confirmRequired == true
end

function BridgeIsStructuredForgeToggleChoice(decision)
    if decision == nil or decision.confirmRequired ~= true then return false end
    local kind = tostring(decision.kind or "")
    return kind == "discard" or kind == "sacrifice" or kind == "payment_option"
        or kind == "search_selection" or kind == "entity_selection" or kind == "cost_selection"
        or kind == "mode_selection"
        or (kind == "mulligan" and tostring(decision.mulliganStage or "") == "bottom_selection")
end

-- Older Forge/TUI builds identify a discard menu as `card_selection` rather
-- than the typed `discard` kind.  The action type is still authoritative and
-- lets the bridge route the physical/UI gesture to the exact Forge action
-- instead of treating a discard as an uncommitted local card move.
function BridgeDecisionContainsDiscardAction(decision)
    if decision == nil then return false end
    for _, action in ipairs(decision.actions or {}) do
        if action.type == "discard_card" then return true end
    end
    return false
end

function BridgeIsDiscardChoice(decision)
    if decision == nil or decision.confirmRequired ~= true then return false end
    return decision.kind == "discard" or
        (decision.kind == "card_selection" and BridgeDecisionContainsDiscardAction(decision))
end

function BridgeIsMulliganBottomSelection(decision)
    return decision ~= nil and decision.kind == "mulligan"
        and tostring(decision.mulliganStage or "") == "bottom_selection"
        and decision.confirmRequired == true
end

function BridgeCanSubmitStructuredDone(decision, source)
    if decision == nil or decision.confirmRequired ~= true then return true end
    local selected = tonumber(decision.selectedCount or 0) or 0
    local minimum = tonumber(decision.minSelections or 0) or 0
    local maximum = tonumber(decision.maxSelections or minimum) or minimum
    if selected < minimum or selected > maximum then
        BridgeShowError(string.format(
            "Forge requires %d to %d selections before Done; currently selected %d",
            minimum, maximum, selected))
        BridgeLog("[Bridge] blocked invalid structured Done source=" .. tostring(source)
            .. " decision=" .. tostring(decision.decisionId))
        return false
    end
    return true
end

function BridgeLogStructuredSelectionRedraw(decision, source)
    if not BridgeIsStructuredForgeToggleChoice(decision) then return end
    local selectedIds = {}
    local doneActionId = "none"
    for _, action in ipairs(decision.actions or {}) do
        if action.type == "choose_none" then
            doneActionId = tostring(action.actionId or "none")
        elseif action.isSelected == true and action.cardInstanceId ~= nil then
            table.insert(selectedIds, tostring(action.cardInstanceId))
        end
    end
    table.sort(selectedIds)
    BridgeLog(string.format(
        "[Bridge] STRUCTURED_SELECTION_REDRAW decision=%s kind=%s source=%s selected=%s min=%s max=%s selectedIds=%s doneAction=%s",
        tostring(decision.decisionId), tostring(decision.kind), tostring(source),
        tostring(decision.selectedCount or 0), tostring(decision.minSelections or 0),
        tostring(decision.maxSelections or 0),
        #selectedIds > 0 and table.concat(selectedIds, ",") or "none", doneActionId))
end

-- The controlled Forge TUI exposes collection choices as a toggle menu: a
-- card choice updates Forge's selected set, then a separate `Done` choice
-- commits it.  A local confirmation must not pretend the first input is the
-- final commit.
function BridgeIsStructuredDiscardChoice(decision)
    return decision ~= nil and decision.kind == "discard" and decision.confirmRequired == true
end

function BridgeTryFinishDiscardChoice(decision, source)
    -- A redraw-based Forge collection is one logical transaction, but every
    -- redraw supplies the authoritative selected set and its exact Done
    -- ActionId. Do not race that menu with a local auto-complete: render the
    -- returned state and let explicit CONFIRM submit the returned Done.
    if BridgeIsDiscardChoice(decision) then
        BridgeLog("[Bridge] discard redraw decision=" .. tostring(decision.decisionId)
            .. " selected=" .. tostring(decision.selectedCount or 0)
            .. " source=" .. tostring(source) .. " awaiting explicit Done")
    end
end

function BridgeTryFinishSingleOptionalPaymentChoice(decision, source)
    if decision == nil or decision.kind ~= "payment_option" or decision.confirmRequired ~= true then return end
    local selected = tonumber(decision.selectedCount or 0) or 0
    local maximum = tonumber(decision.maxSelections or 1) or 1
    -- Optional enter-untapped style choices are one-of-one. Once Forge accepts
    -- the selected cost, submit its explicit Done action.
    if selected ~= 1 or maximum ~= 1 then return end
    for _, action in ipairs(decision.actions or {}) do
        if action.type == "choose_none" then
            BridgeLog("[Bridge] completing single optional payment with Done decision="
                .. tostring(decision.decisionId) .. " source=" .. tostring(source))
            BridgeSubmitChoice(decision.decisionId, action.actionId, "payment_option_auto_done")
            return
        end
    end
end

function BridgeTryFinishFixedSacrificeChoice(decision, source)
    if decision == nil or decision.kind ~= "sacrifice" or decision.confirmRequired ~= true then return end
    local selected = tonumber(decision.selectedCount or 0) or 0
    local minimum = tonumber(decision.minSelections or 1) or 1
    local maximum = tonumber(decision.maxSelections or minimum) or minimum
    -- Sacrifice costs such as Windswept Heath's are fixed-count Forge toggle
    -- menus. A selected legal cost must be followed by its explicit Done input;
    -- do that transport step instead of waiting for an unrelated next decision.
    if minimum ~= maximum or selected ~= minimum then return end
    for _, action in ipairs(decision.actions or {}) do
        if action.type == "choose_none" then
            BridgeLog("[Bridge] completing fixed sacrifice with Done decision="
                .. tostring(decision.decisionId) .. " source=" .. tostring(source))
            BridgeSubmitChoice(decision.decisionId, action.actionId, "sacrifice_auto_done")
            return
        end
    end
end

function BridgeTryFinishFixedRequiredSelection(decision, source)
    if not BridgeIsStructuredForgeToggleChoice(decision) then return end
    local kind = tostring(decision.kind or "")
    if kind ~= "search_selection" and kind ~= "entity_selection" and kind ~= "cost_selection" then return end
    local selected = tonumber(decision.selectedCount or 0) or 0
    local minimum = tonumber(decision.minSelections or 0) or 0
    local maximum = tonumber(decision.maxSelections or minimum) or minimum
    if minimum <= 0 or minimum ~= maximum or selected ~= minimum then return end
    for _, action in ipairs(decision.actions or {}) do
        if action.type == "choose_none" and BridgeCanSubmitStructuredDone(decision, "fixed_selection_auto_done") then
            BridgeLog("[Bridge] completing fixed required " .. kind .. " with Done decision="
                .. tostring(decision.decisionId) .. " source=" .. tostring(source))
            BridgeSubmitChoice(decision.decisionId, action.actionId, "fixed_selection_auto_done")
            return
        end
    end
end

function BridgeIsStaleChoiceRejection(body)
    local errorCode = body and body.errorCode or nil
    return errorCode == "stale_decision_id"
        or errorCode == "unknown_decision_id"
        or errorCode == "decision_already_resolved"
        or errorCode == "no_pending_decision"
end

function BridgeLogChoiceAttempt(source, decisionId, actionId, transactionState)
    BridgeState.choiceAttemptSequence = (BridgeState.choiceAttemptSequence or 0) + 1
    local attempt = BridgeState.choiceAttemptSequence
    BridgeState.lastChoiceAttempt = {
        timestamp = os.clock(),
        decisionId = decisionId,
        actionId = actionId,
        source = source,
        transactionState = transactionState
    }
    BridgeLog(string.format(
        "[Bridge] choice-attempt=%s source=%s session=%s decision=%s action=%s submitting=%s transactionState=%s yieldSeat=%s",
        tostring(attempt), tostring(source or "unknown"), tostring(BridgeState.eventSessionId or "nil"),
        tostring(decisionId), tostring(actionId), tostring(BridgeState.submitting == true),
        tostring(transactionState or "none"), tostring(BridgeState.yieldPolicyActiveSeatId or "nil")))
    local decision = BridgeState.lastDecision
    if decision ~= nil and decision.decisionId == decisionId then
        local actionType = "unknown"
        for _, action in ipairs(decision.actions or {}) do
            if action.actionId == actionId then actionType = action.type or action.actionType or "unknown"; break end
        end
        local policy = string.find(tostring(source or ""), "own_turn_yield_auto_", 1, true) == 1 and "OWN_TURN_YIELD"
            or (source == "yield_policy_auto_pass" and "OPPONENT_YIELD"
                or (source == "auto_pass_empty" and "AUTO_PASS_EMPTY"
                    or (source == "fast_forward" and "FAST_FORWARD" or nil)))
        BridgeRecordDecisionLifecycle(decision, source, "CHOICE_ATTEMPT", "choice-submit",
            actionId, actionType, policy, "submitted")
    end
    return attempt
end

function BridgeRetireChoiceTransactionsForDecision(decisionId)
    for existingDecisionId, _ in pairs(BridgeState.choiceTransactions or {}) do
        if existingDecisionId ~= decisionId then
            BridgeState.choiceTransactions[existingDecisionId] = nil
            if BridgeState.retiredChoiceDecisionIds[existingDecisionId] ~= true then
                BridgeState.retiredChoiceDecisionIds[existingDecisionId] = true
                table.insert(BridgeState.retiredChoiceDecisionOrder, existingDecisionId)
            end
        end
    end

    -- Delayed HTTP callbacks are allowed to arrive after polling has moved on.
    -- Keep only a small session-local tombstone window so they cannot re-arm a
    -- consumed decision, without accumulating an unbounded rejected-ID table.
    while #BridgeState.retiredChoiceDecisionOrder > 32 do
        local retiredId = table.remove(BridgeState.retiredChoiceDecisionOrder, 1)
        BridgeState.retiredChoiceDecisionIds[retiredId] = nil
    end
end

function BridgeSubmitChoice(decisionId, actionId, source)
    -- This guard sits at the actual choice producer, not just around timer and
    -- HTTP callbacks. A callback closure from a previous v9-or-newer runtime
    -- can retain this function and attempt to submit after Save & Play; it must
    -- become inert before it can construct an outbound request.
    if not BridgeRuntimeIsCurrent(BRIDGE_RUNTIME_EPOCH_LOCAL) then
        BridgeLog("[Bridge] CHOICE_POST_BLOCKED reason=retired_runtime runtime="
            .. tostring(BRIDGE_CLIENT_RUNTIME_ID) .. " epoch=" .. tostring(BRIDGE_RUNTIME_EPOCH_LOCAL))
        return
    end
    if BridgeState.choiceProtocolPaused then
        BridgeLog("[Bridge] choice submission blocked: protocol is paused; source=" .. tostring(source))
        return
    end
    if source == nil or source == "" then
        BridgeLog("[Bridge] CHOICE_POST_BLOCKED reason=missing_source")
        return
    end
    if decisionId == nil or decisionId == "" then
        decisionId = BridgeState.lastDecision and BridgeState.lastDecision.decisionId or nil
    end
    local transaction = decisionId and BridgeState.choiceTransactions[decisionId] or nil
    BridgeLogChoiceAttempt(source, decisionId, actionId, transaction and transaction.state or "none")

    if decisionId == nil or actionId == nil or actionId == "" then
        return
    end
    local activeDecision = BridgeState.lastDecision
    if activeDecision == nil or activeDecision.decisionId ~= decisionId then
        return
    end
    if activeDecision ~= nil and activeDecision.decisionId == decisionId
        and activeDecision.kind == "main_priority"
        and activeDecision.seatId == "forge-player-1"
        and string.find(string.lower(tostring(activeDecision.phaseName or "")), "main", 1, true) ~= nil
        and actionId ~= nil
        and BridgeDecisionOffersActionType(activeDecision, "pass_priority")
        and (source == "empty_priority_auto_pass" or source == "yield_policy_auto_pass"
            or source == "auto_pass_empty" or source == "fast_forward"
            or string.find(tostring(source or ""), "auto_", 1, true) ~= nil)
        and source ~= "own_turn_yield_auto_pass" then
        BridgeRecordDecisionLifecycle(activeDecision, source, "AUTO_ACTION_BLOCKED",
            "HUMAN_MAIN1_AUTOPASS_BLOCKED", actionId, "pass_priority", "UNAUTHORIZED", "wrong-policy")
        BridgeLog("[Bridge] HUMAN_MAIN1_AUTOPASS_BLOCKED decision=" .. tostring(decisionId)
            .. " source=" .. tostring(source) .. " action=" .. tostring(actionId))
        return
    end
    local ownTurnYieldSource = string.find(tostring(source or ""), "own_turn_yield_auto_", 1, true) == 1
    if ownTurnYieldSource
        and (BridgeState.yieldPolicyOwnTurn ~= true
            or BridgeState.yieldPolicySessionId ~= BridgeState.eventSessionId
            or BridgeState.yieldPolicyActiveSeatId ~= BridgeState.currentTurnSeatId
            or (tonumber(BridgeState.yieldPolicyTurnNumber or 0) or 0) ~= (tonumber(BridgeState.tableTurnCount or 0) or 0)) then
        BridgeRecordDecisionLifecycle(activeDecision, source, "AUTO_ACTION_BLOCKED",
            "own-turn-yield-policy-no-longer-authorized", actionId, "unknown", "OWN_TURN_YIELD", "stale-policy")
        BridgeLog("[Bridge] own-turn yield action blocked: policy is no longer authoritative")
        return
    end
    local activeActionType = "unknown"
    for _, action in ipairs(activeDecision.actions or {}) do
        if action.actionId == actionId then activeActionType = action.type or action.actionType or "unknown"; break end
    end
    if activeDecision ~= nil and activeDecision.decisionId == decisionId
        and activeDecision.kind == "mulligan"
        and tostring(activeDecision.mulliganStage or "") == "bottom_selection" then
        -- Toggle actions merely stage Forge's native selection. Mark cards for
        -- the presentation-only bottom insertion only when its Forge-provided
        -- Done action commits the currently selected exact identities.
        for _, action in ipairs(activeDecision.actions or {}) do
            if action.actionId == actionId and action.type == "choose_none" then
                for _, candidate in ipairs(activeDecision.actions or {}) do
                    if candidate.cardInstanceId ~= nil and candidate.isSelected == true then
                        BridgeState.mulliganBottomInstanceIds[candidate.cardInstanceId] = true
                    end
                end
                break
            end
        end
    end
    -- A MULLIGAN action returns the rejected opening hand to the library
    -- before Forge deals the replacement hand.  Mark those exact physical
    -- instances before the first authoritative hand->library event arrives;
    -- the event handler can then insert them at the physical bottom instead
    -- of briefly putting them face-up on top of the deck.
    if activeDecision ~= nil and activeDecision.decisionId == decisionId
        and activeDecision.kind == "mulligan"
        and tostring(activeDecision.mulliganStage or "") == "keep_or_mulligan" then
        local selectedAction = nil
        for _, candidateAction in ipairs(activeDecision.actions or {}) do
            if candidateAction.actionId == actionId then
                selectedAction = candidateAction
                break
            end
        end
        if selectedAction ~= nil and selectedAction.type == "mulligan" then
            for instanceId, guid in pairs(BridgeState.physicalByInstanceId or {}) do
                local zone = BridgeState.physicalZoneByGuid[guid]
                local seatId = BridgeState.physicalSeatByGuid[guid]
                if zone == "hand" and seatId == activeDecision.seatId then
                    BridgeState.mulliganReturningInstanceIds[instanceId] = {
                        sessionId = BridgeState.eventSessionId,
                        decisionId = decisionId,
                        actionId = actionId,
                        seatId = activeDecision.seatId
                    }
                end
            end
            BridgeLog("[Bridge] marked rejected opening hand for physical library bottom seat="
                .. tostring(activeDecision.seatId))
        end
    end
    if transaction ~= nil then
        if transaction.actionId == actionId then
            -- Same logical choice is already in flight or complete. Do not
            -- issue another POST; the adapter independently accepts it too.
            return
        end
        if transaction.conflictReported ~= true then
            transaction.conflictReported = true
            BridgeShowError("conflicting action ignored for an already-submitting Forge decision")
        end
        return
    end
    if BridgeState.submitting then return end
    if BridgeState.lastDecision == nil
        or BridgeState.lastDecision.decisionId ~= decisionId
        or not BridgeDecisionHasAction(BridgeState.lastDecision, actionId) then
        return
    end

    -- The decision-scoped transaction is installed before any asynchronous
    -- network work. Atomicity ultimately lives in the adapter; this prevents
    -- duplicate physical callbacks from needlessly reaching that boundary.
    transaction = {
        actionId = actionId,
        actionType = activeActionType,
        state = "posting",
        source = source,
        sessionId = BridgeState.eventSessionId,
        presentationGeneration = BridgeState.decisionPresentationGeneration
    }
    BridgeState.choiceTransactions[decisionId] = transaction
    BridgeState.pendingDecision = nil
    BridgeState.pendingDecisionDeferredAt = nil
    BridgeState.pendingDecisionDeferredCursor = 0
    BridgeState.pendingDecisionDeferredApplied = 0
    BridgeState.submitting = true
    BridgeRecordDecisionLifecycle(activeDecision, source, "CHOICE_POST", "choice-post",
        actionId, transaction.actionType, string.find(tostring(transaction.source or ""), "own_turn_yield_auto_", 1, true) == 1 and "OWN_TURN_YIELD"
            or (transaction.source == "yield_policy_auto_pass" and "OPPONENT_YIELD"
                or (transaction.source == "auto_pass_empty" and "AUTO_PASS_EMPTY"
                    or (transaction.source == "fast_forward" and "FAST_FORWARD" or nil))), "posted")
    local submittedAt = os.clock()
    BridgeState.latencyProbe = {
        actionId = actionId,
        decisionId = decisionId,
        submittedAt = submittedAt,
        acceptedAt = nil,
        firstEventReceivedAt = nil,
        turnChangedAppliedAt = nil,
        nextDecisionAt = nil
    }

    BridgeState.choiceRequestSequence = (BridgeState.choiceRequestSequence or 0) + 1
    local requestId = tostring(BRIDGE_CLIENT_RUNTIME_ID) .. "-choice-" .. tostring(BridgeState.choiceRequestSequence)
    local requestSessionId = BridgeState.eventSessionId
    local missingProtocolFields = {}
    if requestSessionId == nil or requestSessionId == "" then table.insert(missingProtocolFields, "sessionId") end
    if requestId == nil or requestId == "" then table.insert(missingProtocolFields, "requestId") end
    if BRIDGE_CLIENT_RUNTIME_ID == nil or BRIDGE_CLIENT_RUNTIME_ID == "" then table.insert(missingProtocolFields, "clientRuntimeId") end
    if BRIDGE_SCRIPT_REVISION == nil or BRIDGE_SCRIPT_REVISION == "" then table.insert(missingProtocolFields, "clientRevision") end
    if source == nil or source == "" then table.insert(missingProtocolFields, "source") end
    if #missingProtocolFields > 0 then
        BridgeState.submitting = false
        transaction.state = "not_sent"
        BridgeLog("[Bridge] CHOICE_NOT_SENT reason=missing_protocol_identity missingFields="
            .. table.concat(missingProtocolFields, ",") .. " decision=" .. tostring(decisionId)
            .. " action=" .. tostring(actionId))
        BridgePauseChoiceProtocol("protocol identity missing; inspect diagnostics")
        return
    end
    BridgeLog(string.format(
        "[Bridge] CHOICE_POST requestId=%s runtime=%s revision=%s epoch=%s session=%s decision=%s action=%s source=%s transactionState=%s lastDecision=%s eventCursor=%s appliedCursor=%s",
        tostring(requestId), tostring(BRIDGE_CLIENT_RUNTIME_ID), tostring(BRIDGE_SCRIPT_REVISION),
        tostring(BRIDGE_RUNTIME_EPOCH_LOCAL), tostring(requestSessionId), tostring(decisionId),
        tostring(actionId), tostring(source), tostring(transaction.state),
        tostring(BridgeState.lastDecision and BridgeState.lastDecision.decisionId or "nil"),
        tostring(BridgeState.lastDecision and BridgeState.lastDecision.eventCursor or "nil"),
        tostring(BridgeState.lastAppliedEventSequence or 0)))

    BridgeHttp.requestJson("POST", "/api/v1/choice", {
        sessionId = requestSessionId,
        decisionId = decisionId,
        actionId = actionId,
        requestId = requestId,
        clientRuntimeId = BRIDGE_CLIENT_RUNTIME_ID,
        clientRevision = BRIDGE_SCRIPT_REVISION,
        source = source
    }, function(ok, body, err, request)
        BridgeState.submitting = false
        local activeTransaction = BridgeState.choiceTransactions[decisionId]
        if activeTransaction == nil or activeTransaction.actionId ~= actionId then return end
        if activeTransaction.sessionId ~= BridgeState.eventSessionId
            or activeTransaction.presentationGeneration ~= BridgeState.decisionPresentationGeneration then
            return
        end
        if not ok then
            activeTransaction.state = "rejected"
            local rejectedDecision = BridgeState.lastDecision
            if rejectedDecision ~= nil and rejectedDecision.decisionId == decisionId then
                BridgeRecordDecisionLifecycle(rejectedDecision, activeTransaction.source, "CHOICE_REJECTED",
                    tostring(body and body.errorCode or err or "request-failed"), actionId,
                    activeTransaction.actionType, nil, "rejected")
            end
            -- No authoritative mulligan transition follows a rejected
            -- MULLIGAN action. Retire the pre-marked hand identities so a
            -- later unrelated library move cannot be misrouted to bottom.
            if activeTransaction.source == "hud_action"
                or activeTransaction.source == "physical_mulligan"
                or activeTransaction.source == "physical_card_drop" then
                for instanceId, marker in pairs(BridgeState.mulliganReturningInstanceIds or {}) do
                    if marker ~= nil and marker.sessionId == activeTransaction.sessionId
                        and marker.decisionId == decisionId and marker.actionId == actionId then
                        BridgeState.mulliganReturningInstanceIds[instanceId] = nil
                    end
                end
            end
            BridgeState.latencyProbe = nil
            BridgeMarkTransitionExpected(0)
            BridgeClearHighlights()
            BridgeRollbackPendingIntent()
            BridgeResetSelectionState()
            BridgeRecordChoiceProtocolFailure(body, err, requestId)
            if body ~= nil and body.errorCode == "stale_session" then
                BridgeRecoverFromStaleSession(body, requestId)
                return
            end
            if BridgeIsStaleChoiceRejection(body) then
                BridgeState.lastDecision = nil
                BridgeLog("[Bridge] rejected Forge transaction retired decision=" .. tostring(decisionId)
                    .. " action=" .. tostring(actionId) .. " code=" .. tostring(body and body.errorCode or "unknown"))
                BridgeStartDecisionPolling()
                return
            end
            -- Choice protocol failures are forensic data. Keep the first and
            -- subsequent details in the scripting/Bridge logs; the circuit
            -- breaker provides the single player-facing notification if the
            -- failures become a burst.
            BridgeLog("[Bridge] choice rejected: " .. tostring(err))
            if body ~= nil and body.errorCode ~= nil then
                BridgeLog("[Bridge] errorCode=" .. tostring(body.errorCode) .. " message=" .. tostring(body.message))
            end
            return
        end

        activeTransaction.state = "accepted"
        local acceptedDecision = BridgeState.lastDecision
        if acceptedDecision ~= nil and acceptedDecision.decisionId == decisionId then
            BridgeRecordDecisionLifecycle(acceptedDecision, activeTransaction.source, "CHOICE_ACCEPTED",
                "forge-accepted", actionId, activeTransaction.actionType, nil, "accepted")
        end
        BridgeLog("[Bridge] choice accepted.")
        local probe = BridgeState.latencyProbe
        if probe ~= nil then
            probe.acceptedAt = os.clock()
            local submitMs = math.floor((probe.acceptedAt - probe.submittedAt) * 1000)
            BridgeLog(string.format("[Bridge latency] choice POST accepted in %dms (action=%s)", submitMs, tostring(actionId)))
        end
        BridgeMarkTransitionExpected(2.5)
        BridgeScheduleEventPoll(0.05, BridgeState.eventPollGeneration)
        if body ~= nil and body.committedEvent ~= nil then
            BridgeLog("[Bridge] committed: " .. tostring(body.committedEvent.summary))
        end
        BridgeCommitPendingIntent()
        if body ~= nil and body.currentDecision ~= nil then
            BridgeStopDecisionPolling()
            BridgeMarkTransitionExpected(0)
            BridgeRecordLatencyProbeDecisionReady(body.currentDecision)
            -- Forge collection choices deliberately keep the same DecisionId
            -- while each exact candidate is toggled.  This response is the
            -- authoritative staged state (including selectedCount and
            -- [SELECTED] rows), not a stale replay of a consumed decision.
            -- Release the completed request transaction before rendering it so
            -- a physical discard click and its HUD use the same model and the
            -- next exact toggle can be submitted.
            if body.currentDecision.decisionId == decisionId
                and (BridgeIsStructuredForgeToggleChoice(body.currentDecision)
                    or BridgeIsDiscardChoice(body.currentDecision)
                    or body.currentDecision.kind == "attacker_selection"
                    or body.currentDecision.kind == "blocker_selection"
                    or body.currentDecision.kind == "blocker_assignment") then
                BridgeState.choiceTransactions[decisionId] = nil
            end
            if body.currentDecision.decisionId == decisionId
                and BridgeIsStructuredForgeToggleChoice(body.currentDecision) then
                BridgeLogStructuredSelectionRedraw(body.currentDecision, activeTransaction.source)
            end
            BridgeAcceptDecision(body.currentDecision, "choice_response", activeTransaction.sessionId, activeTransaction.presentationGeneration)
            BridgeTryFinishDiscardChoice(body.currentDecision, activeTransaction.source)
            BridgeTryFinishSingleOptionalPaymentChoice(body.currentDecision, activeTransaction.source)
            BridgeTryFinishFixedSacrificeChoice(body.currentDecision, activeTransaction.source)
            BridgeTryFinishFixedRequiredSelection(body.currentDecision, activeTransaction.source)
        else
            BridgeState.lastDecision = nil
            BridgeClearHighlights()
            BridgeHideMainPriorityControls()
            BridgeLog("[Bridge] no pending decision.")
            BridgeStartDecisionPolling()
        end
    end)
end

function BridgeRecordChoiceProtocolFailure(body, err, requestId)
    local now = os.clock()
    local failures = BridgeState.choiceProtocolFailureTimes or {}
    table.insert(failures, now)
    while #failures > 0 and now - failures[1] > 2 do
        table.remove(failures, 1)
    end
    BridgeState.choiceProtocolFailureTimes = failures
    if #failures < 3 or BridgeState.choiceProtocolPaused then return end

    BridgePauseChoiceProtocol("three choice protocol failures in two seconds; inspect diagnostics")
    BridgeLog("[Bridge] CHOICE_PROTOCOL_FAILURE_SUMMARY runtime=" .. tostring(BRIDGE_CLIENT_RUNTIME_ID)
        .. " session=" .. tostring(BridgeState.eventSessionId)
        .. " failures=" .. tostring(#failures)
        .. " requestId=" .. tostring(requestId)
        .. " lastCode=" .. tostring(body and body.errorCode)
        .. " lastError=" .. tostring(err))
end

function BridgePauseChoiceProtocol(reason)
    if BridgeState.choiceProtocolPaused then return end
    BridgeState.choiceProtocolPaused = true
    BridgeClearHighlights()
    BridgeRollbackPendingIntent()
    BridgeResetSelectionState()
    BridgeHideMainPriorityControls()
    BridgeLog("[Bridge] CHOICE_PROTOCOL_PAUSED runtime=" .. tostring(BRIDGE_CLIENT_RUNTIME_ID)
        .. " session=" .. tostring(BridgeState.eventSessionId)
        .. " reason=" .. tostring(reason))
    BridgeSetStatus("FORGEBOT PROTOCOL PAUSED", tostring(reason))
    broadcastToAll("[Bridge] FORGEBOT PROTOCOL PAUSED — " .. tostring(reason), {1.0, 0.2, 0.2})
end

function BridgeRecoverFromStaleSession(body, requestId)
    if BridgeState.sessionRecoveryInFlight then
        BridgeLog("[Bridge] stale_session recovery already in progress; requestId=" .. tostring(requestId))
        return
    end

    BridgeState.sessionRecoveryInFlight = true
    BridgeState.choiceProtocolPaused = false
    BridgeState.choiceProtocolFailureTimes = {}
    BridgeState.lastDecision = nil
    BridgeState.pendingDecision = nil
    BridgeClearHighlights()
    BridgeRollbackPendingIntent()
    BridgeResetSelectionState()
    BridgeHideMainPriorityControls()
    BridgeStopDecisionPolling()
    BridgeStopEventPolling("stale-session-recovery")
    BridgeLog("[Bridge] STALE_SESSION requestId=" .. tostring(requestId)
        .. " expectedSession=" .. tostring(body.expectedSessionId)
        .. " receivedSession=" .. tostring(body.receivedSessionId)
        .. " — reattaching without replaying the rejected choice")
    BridgeStartSessionIfNone(function()
        BridgeState.sessionRecoveryInFlight = false
    end)
end

function BridgeChoose(actionId)
    BridgeSubmitChoice(nil, actionId, "developer_choose")
end

function BridgeChooseTargetOpponent()
    BridgeChoose("target_opponent")
end

function BridgeChooseTargetTestCreature()
    BridgeChoose("target_test_creature")
end

function BridgeGetEmbodimentSnapshot(callback)
    BridgeHttp.requestJson("GET", "/api/v1/embodiment/snapshot", nil, callback)
end

function BridgeDecisionOffersActionType(decision, actionType)
    for _, action in ipairs(decision.actions or {}) do
        if action.type == actionType then return true end
    end
    return false
end

function BridgeActionPresentationAuthorized(action)
    if action == nil then return false end
    if action.isPresentationAuthorized == false then return false end
    local provenance = action.provenance or {}
    if provenance.isPresentationAuthorized == false then return false end
    -- Older producers did not carry authorization metadata. Library identity
    -- is hidden by default, so never render it without an explicit grant.
    local sourceZone = string.lower(tostring(action.sourceZone or provenance.sourceZone or ""))
    if sourceZone == "library" then
        return action.isPresentationAuthorized == true
            or provenance.isPresentationAuthorized == true
    end
    return true
end

function BridgeDecisionHasUnauthorizedPresentationAction(decision)
    for _, action in ipairs((decision and decision.actions) or {}) do
        if not BridgeActionPresentationAuthorized(action) then return true end
    end
    return false
end

function BridgeDecisionHasNonPassAction(decision)
    for _, action in ipairs((decision and decision.actions) or {}) do
        if action.type ~= "pass_priority" and BridgeActionPresentationAuthorized(action) then return true end
    end
    return false
end

-- Keep phase-family normalization shared by stale-decision checks and
-- diagnostics. It is descriptive only; Forge remains legality authority.
function BridgePriorityPhaseFamily(value)
    local phase = string.upper(tostring(value or ""))
    if phase == "" then return "" end
    if string.find(phase, "UPKEEP", 1, true) then return "UPKEEP" end
    if string.find(phase, "DRAW", 1, true) then return "DRAW" end
    if string.find(phase, "MAIN", 1, true) then return "MAIN" end
    if string.find(phase, "ATTACK", 1, true)
        or string.find(phase, "BLOCK", 1, true)
        or string.find(phase, "DAMAGE", 1, true)
        or string.find(phase, "COMBAT", 1, true) then return "COMBAT" end
    if string.find(phase, "CLEANUP", 1, true) then return "CLEANUP" end
    if string.find(phase, "END", 1, true) then return "END" end
    return phase
end

function BridgeShouldIgnoreStaleDecision(decision)
    local eventCursor = tonumber(decision and decision.eventCursor or 0) or 0
    local applied = tonumber(BridgeState.lastAppliedEventSequence or 0) or 0
    local decisionForgeSequence = tonumber(decision and decision.forgeSequence or 0) or 0
    local appliedForgeSequence = tonumber(BridgeState.lastAppliedForgeSequence or 0) or 0
    if decisionForgeSequence > 0 and appliedForgeSequence > 0
        and decisionForgeSequence < appliedForgeSequence then
        BridgeLog(string.format(
            "[Bridge] ignoring stale decision %s due to forgeSequence ordering decision=%s applied=%s",
            tostring(decision and decision.decisionId), tostring(decisionForgeSequence), tostring(appliedForgeSequence)))
        return true, eventCursor, applied
    end
    if eventCursor < 1 or eventCursor >= applied then
        if decision ~= nil and (decision.kind == "attacker_selection"
            or decision.kind == "blocker_selection" or decision.kind == "blocker_assignment") then
            -- A valid combat decision can arrive in the same transport window
            -- as its phase event. Prefer Forge's phase carried by this exact
            -- decision so a late phase poll cannot suppress the decision before
            -- BridgeRenderDecision has a chance to install its highlights.
            local decisionPhase = string.upper(tostring(decision.phaseName or ""))
            local phase = decisionPhase ~= "" and decisionPhase
                or string.upper(tostring(BridgeState.currentPhase or ""))
            local combatPhase = string.find(phase, "COMBAT", 1, true) ~= nil
                or string.find(phase, "ATTACK", 1, true) ~= nil
                or string.find(phase, "BLOCK", 1, true) ~= nil
                or string.find(phase, "DAMAGE", 1, true) ~= nil
            if not combatPhase then
                BridgeLog("[Bridge] ignoring combat decision before phase transition decisionPhase="
                    .. tostring(decision.phaseName) .. " cachedPhase=" .. tostring(BridgeState.currentPhase))
                return true, eventCursor, applied
            end
        end
        return false, eventCursor, applied
    end

    if decision.kind ~= "main_priority" then
        -- A combat decision cannot be presented while the authoritative phase
        -- is still draw/main. This is a stale poll result, not a valid combat
        -- choice; presenting it alongside the draw step desynchronizes the UI.
        if decision.kind == "attacker_selection" or decision.kind == "blocker_selection"
            or decision.kind == "blocker_assignment" then
            local phase = string.upper(tostring(BridgeState.currentPhase or ""))
            local combatPhase = string.find(phase, "COMBAT", 1, true) ~= nil
                or string.find(phase, "ATTACK", 1, true) ~= nil
                or string.find(phase, "BLOCK", 1, true) ~= nil
                or string.find(phase, "DAMAGE", 1, true) ~= nil
            if not combatPhase then
                BridgeLog("[Bridge] ignoring stale combat decision while phase=" .. tostring(BridgeState.currentPhase))
                return true, eventCursor, applied
            end
        end
        -- Other non-priority decisions can legitimately arrive after
        -- additional phase events; retain them unless the phase contradicts
        -- their decision kind as above.
        return false, eventCursor, applied
    end

    local decisionTurn = tonumber(decision.turnNumber or 0) or 0
    local tableTurn = tonumber(BridgeState.tableTurnCount or 0) or 0
    if decisionTurn > 0 and tableTurn > 0 and decisionTurn < tableTurn then
        return true, eventCursor, applied
    end

    -- A same-turn priority menu can still be returned by a delayed poll after
    -- the authoritative phase event has already been applied. Keeping that
    -- menu would make an Upkeep pass look current and can carry the game
    -- straight past Main 1. Decision phase metadata never advances or
    -- regresses BridgeState.currentPhase; when its cursor is stale it is only
    -- used as a contradiction check. Coarse families keep Forge labels such
    -- as "Main phase, precombat" and "Main 1" equivalent.
    -- A pass-only menu from an older phase is never actionable, even when
    -- the decision and phase event happen to share the same cursor.  That
    -- race was allowing an Upkeep/DRAW pass to be submitted after Main 1 had
    -- already become authoritative, effectively consuming the Main 1 window.
    -- A menu carrying a real Forge action remains eligible to bridge the
    -- short event-publication gap; legality is still Forge-owned.
    -- Keep the phase-family normalization local to this stale-decision
    -- comparison so the guard remains self-contained and easy to audit.
    local function phaseFamily(value)
        return BridgePriorityPhaseFamily(value)
    end
    local decisionFamily = BridgePriorityPhaseFamily(decision.phaseName)
    local authoritativeFamily = BridgePriorityPhaseFamily(BridgeState.currentPhase)
    local contradictoryPassOnly = decisionFamily ~= "" and authoritativeFamily ~= ""
        and decisionFamily ~= authoritativeFamily
        and not BridgeDecisionHasNonPassAction(decision)
    if (eventCursor > 0 and eventCursor < applied) or contradictoryPassOnly then
        if decisionFamily ~= "" and authoritativeFamily ~= ""
            and decisionFamily ~= authoritativeFamily then
            -- Forge can publish the first Main 1 menu (including a legal land
            -- or sorcery action) with the prior draw/upkeep event cursor while
            -- its event stream catches up.  Discarding that menu makes the
            -- bridge look as if upkeep jumped straight to combat.  A stale
            -- pass-only menu is still unsafe and is retired; a menu carrying
            -- an exact meaningful Forge action is authoritative enough to
            -- present and submit.  Legality remains entirely Forge-owned.
            if not BridgeDecisionHasNonPassAction(decision) then
                -- Legacy diagnostic wording retained for contract readers:
                -- "ignoring stale pass-only priority menu".
                BridgeLog(string.format(
                    "[Bridge] ignoring stale main-priority pass-only decision phase=%s authoritativePhase=%s cursor=%s applied=%s",
                    tostring(decision.phaseName), tostring(BridgeState.currentPhase),
                    tostring(eventCursor), tostring(applied)))
                return true, eventCursor, applied
            end
            BridgeLog(string.format(
                -- Legacy diagnostic wording: "retaining regenerated Forge action menu".
                "[Bridge] retaining stale main-priority decision with Forge action phase=%s authoritativePhase=%s cursor=%s applied=%s",
                tostring(decision.phaseName), tostring(BridgeState.currentPhase),
                tostring(eventCursor), tostring(applied)))
        end
    end

    -- Priority/active-seat fields are descriptive state, not ordering keys.
    -- During a phase transition the event feed can legitimately update one
    -- before the decision poll (and a decision's chooser can differ from the
    -- current priority seat). Treating either mismatch as stale discarded the
    -- authoritative Main 1 land/spell menu and could skip the turn; it must not suppress that action.
    -- Only the
    -- comparable Forge turn number above can establish staleness here.
    if decision.prioritySeatId ~= nil or decision.activeSeatId ~= nil then
        BridgeLog(string.format("[Bridge] retaining decision despite state mirror (priority=%s active=%s current=%s)",
            tostring(decision.prioritySeatId), tostring(decision.activeSeatId), tostring(BridgeState.currentTurnSeatId)))
    end

    return false, eventCursor, applied
end

-- Empty cursor handling remains explicit in the stale-decision policy:
-- if eventCursor <= 0, no cross-domain ordering comparison is possible.
function BridgeShouldDeferDecision(decision)
    local openingMulligan = decision ~= nil and decision.kind == "mulligan"
        and tostring(decision.mulliganStage or "") == "keep_or_mulligan"
    local function globalPhysicalQueueBusy()
        for seatId, _ in pairs(BRIDGE_SEATS or {}) do
            if BridgeState.libraryExtractionActiveBySeatId[seatId] == true
                or #(BridgeState.libraryExtractionQueueBySeatId[seatId] or {}) > 0
                or BridgeState.mulliganBottomInsertionActiveBySeatId[seatId] == true
                or #(BridgeState.mulliganBottomQueueBySeatId[seatId] or {}) > 0 then
                return true, seatId
            end
        end
        return false, nil
    end
    local busy, busySeatId = globalPhysicalQueueBusy()
    if busy then
        return true, tonumber(decision and decision.eventCursor or 0) or 0,
            tonumber(BridgeState.lastAppliedEventSequence or 0) or 0,
            "physical_transition_pending_global",
            "seat=" .. tostring(busySeatId)
    end
    -- A decision can arrive before the tail of its own Forge mutation group is
    -- physically committed. Keep that decision non-actionable until every
    -- queued event in the same forgeSequence is embodied.
    if decision ~= nil then
        local decisionForgeSequence = tonumber(decision.forgeSequence or 0) or 0
        if decisionForgeSequence > 0 then
            for _, queued in ipairs(BridgeState.eventQueue or {}) do
                local queuedForgeSequence = tonumber(queued and queued.forgeSequence or 0) or 0
                if queuedForgeSequence == decisionForgeSequence then
                    return true, tonumber(decision.eventCursor or 0) or 0,
                        tonumber(BridgeState.lastAppliedEventSequence or 0) or 0,
                        "causal_dependency_pending",
                        "forgeSequence=" .. tostring(decisionForgeSequence)
                            .. " queuedEvent=" .. tostring(queued.sequence)
                end
            end
        end
    end
    -- Forge can produce the next priority menu before the bridge event poll
    -- has received the matching draw. Do not reveal or make actionable a
    -- hand-source action until its exact instance has an exact physical card
    -- in the chooser's live TTS hand. This is stronger than event-cursor
    -- ordering: the menu itself can legitimately carry an older cursor while
    -- already reflecting Forge's newly drawn hand.
    if not openingMulligan and decision ~= nil and decision.seatId ~= nil then
        local handGuids, handError = BridgeBuildSeatHandGuidSet(decision.seatId)
        for _, action in ipairs(decision.actions or {}) do
            if string.lower(tostring(action.sourceZone or "")) == "hand" then
                local instanceId = action.preparedSourceCardInstanceId
                    or action.sourceCardInstanceId or action.cardInstanceId
                local guid = instanceId and BridgeState.physicalByInstanceId[instanceId] or nil
                if instanceId == nil or guid == nil
                    or BridgeState.physicalInstanceIdByGuid[guid] ~= instanceId
                    or handGuids[guid] ~= true then
                    return true, tonumber(decision.eventCursor or 0) or 0,
                        tonumber(BridgeState.lastAppliedEventSequence or 0) or 0,
                        "hand_action_readiness",
                        string.format("instance=%s guid=%s hand=%s error=%s",
                            tostring(instanceId), tostring(guid), tostring(handGuids[guid] == true), tostring(handError))
                end
            end
        end
    end
    -- A draw is authoritative before its physical Deck extraction callback
    -- completes. Do not expose a priority menu whose new hand card cannot yet
    -- be embodied; otherwise the player can pass a stale menu and only then
    -- see the card/action refresh. The extraction completion path releases
    -- and rerenders the same Forge decision after the exact card is in hand.
    if not openingMulligan and decision ~= nil and decision.seatId ~= nil then
        local extractionQueue = BridgeState.libraryExtractionQueueBySeatId[decision.seatId]
        if BridgeState.libraryExtractionActiveBySeatId[decision.seatId] == true
            or (extractionQueue ~= nil and #extractionQueue > 0) then
            return true, tonumber(decision.eventCursor or 0) or 0,
                tonumber(BridgeState.lastAppliedEventSequence or 0) or 0
        end
    end

    -- Do not show KEEP/MULLIGAN until the exact opening-hand draws from Forge's
    -- authoritative snapshot is physically settled in the human's TTS hand.
    -- This deliberately uses the snapshot identities, not a hard-coded hand
    -- size or the transient extraction queue length.
    if openingMulligan then
        if BridgeState.openingHandReadinessDecisionId ~= decision.decisionId then
            BridgeState.openingHandReadinessDecisionId = decision.decisionId
            BridgeState.openingHandReadinessSnapshotPending = true
            BridgeState.openingHandReadinessSnapshotRequested = false
        end
        if BridgeState.openingHandReadinessSnapshotPending then
            return true, tonumber(decision.eventCursor or 0) or 0,
                tonumber(BridgeState.lastAppliedEventSequence or 0) or 0,
                "opening_hand_readiness", "waiting for authoritative opening-hand snapshot"
        end
        local ready, readyCount, expectedCount, readinessDetail =
            BridgeCheckOpeningHandReadiness(decision.seatId)
        if not ready then
            return true, tonumber(decision.eventCursor or 0) or 0,
                tonumber(BridgeState.lastAppliedEventSequence or 0) or 0,
                "opening_hand_readiness",
                string.format("ready=%d expected=%d missing=%s", readyCount, expectedCount, readinessDetail)
        end
    end
    local eventCursor = tonumber(decision and decision.eventCursor or 0) or 0
    local applied = math.max(
        tonumber(BridgeState.lastAppliedEventSequence or 0) or 0,
        tonumber(BridgeState.lastStateProjectedEventSequence or 0) or 0)
    if eventCursor <= 0 then return false, eventCursor, applied end
    return eventCursor > applied, eventCursor, applied
end

function BridgeScheduleOpeningHandReadinessRetry()
    if BridgeState.openingHandReadinessRetryScheduled then return end
    BridgeState.openingHandReadinessRetryScheduled = true
    BridgeWaitFrames(function()
        BridgeState.openingHandReadinessRetryScheduled = false
        if BridgeState.pendingDecision ~= nil and not BridgeState.submitting then
            BridgeTryPresentPendingDecision("opening-hand-readiness-retry")
        end
    end, BRIDGE_OPENING_HAND_READINESS_RETRY_FRAMES)
end

function BridgeScheduleHandActionReadinessRetry()
    if BridgeState.handActionReadinessRetryScheduled then return end
    BridgeState.handActionReadinessRetryScheduled = true
    BridgeWaitFrames(function()
        BridgeState.handActionReadinessRetryScheduled = false
        if BridgeState.pendingDecision ~= nil and not BridgeState.submitting then
            BridgeTryPresentPendingDecision("hand-action-readiness-retry")
        end
    end, BRIDGE_OPENING_HAND_READINESS_RETRY_FRAMES)
end

-- A readiness timeout is not, by itself, evidence that Forge and TTS disagree.
-- Mulligan replacement cards can be present in the authoritative snapshot while
-- TTS is still finishing Deck/Card callbacks.  Recover from that transient
-- state with an exact-session snapshot refresh, then (once) a full
-- authoritative rebuild.  The decision is never fabricated and the bounded
-- attempt ledger prevents an endless retry loop.
function BridgeRecoverFromHandReadinessTimeout(decision, deferReason, detail)
    local decisionId = decision and decision.decisionId or nil
    local sessionId = BridgeState.eventSessionId
    if decisionId == nil or sessionId == nil then return false end
    if BridgeState.handReadinessRecoveryDecisionId ~= decisionId
        or BridgeState.handReadinessRecoverySessionId ~= sessionId then
        BridgeState.handReadinessRecoveryDecisionId = decisionId
        BridgeState.handReadinessRecoverySessionId = sessionId
        BridgeState.handReadinessRecoveryAttempts = 0
    end
    local attempts = (BridgeState.handReadinessRecoveryAttempts or 0) + 1
    BridgeState.handReadinessRecoveryAttempts = attempts
    BridgeState.pendingDecisionDeferredAt = os.clock()
    BridgeState.pendingDecisionDeferredCursor = tonumber(decision.eventCursor or 0) or 0
    BridgeState.pendingDecisionDeferredApplied = tonumber(BridgeState.lastAppliedEventSequence or 0) or 0
    BridgeLog(string.format(
        "[Bridge] hand readiness timeout is recoverable decision=%s reason=%s attempt=%d/%d session=%s detail=%s",
        tostring(decisionId), tostring(deferReason), attempts,
        BRIDGE_HAND_READINESS_RECOVERY_ATTEMPTS, tostring(sessionId), tostring(detail)))

    if attempts < BRIDGE_HAND_READINESS_RECOVERY_ATTEMPTS then
        -- Keep the exact Forge decision pending while refreshing the snapshot;
        -- no local selection or physical move is performed.
        BridgeState.openingHandReadinessSnapshotRequested = false
        BridgeState.openingHandReadinessSnapshotPending = true
        BridgeScheduleSnapshotReconcile("hand-readiness-timeout")
        if deferReason == "opening_hand_readiness" then
            BridgeScheduleOpeningHandReadinessRetry()
        else
            BridgeScheduleHandActionReadinessRetry()
        end
        return true
    end

    -- A second timeout means the ordinary snapshot refresh did not settle the
    -- physical hand. Rebuild from Forge's current snapshot and resume polling;
    -- this is still recoverable and is intentionally not a guessed card bind.
    if BridgeState.resyncInFlight ~= true then
        BridgeResyncFromAuthoritativeSnapshot("hand-readiness-timeout")
        return true
    end
    return true
end

function BridgeTryPresentPendingDecision(reason)
    if BridgeState.pendingDecision == nil or BridgeState.submitting then return end
    local pending = BridgeState.pendingDecision
    local defer, eventCursor, applied, deferReason, deferDetail = BridgeShouldDeferDecision(pending)
    if defer then
        local deferredAt = tonumber(BridgeState.pendingDecisionDeferredAt or 0) or 0
        if deferredAt <= 0 then deferredAt = os.clock() end
        local elapsed = os.clock() - deferredAt
        if deferReason == "opening_hand_readiness" then
            BridgeState.pendingDecisionDeferredAt = deferredAt
            BridgeState.pendingDecisionDeferredCursor = eventCursor
            BridgeState.pendingDecisionDeferredApplied = applied
            if not BridgeState.openingHandReadinessSnapshotRequested then
                BridgeState.openingHandReadinessSnapshotRequested = true
                BridgeState.openingHandReadinessSnapshotPending = true
                BridgeScheduleSnapshotReconcile("opening-hand-readiness")
            end
            if elapsed >= BRIDGE_OPENING_HAND_READINESS_TIMEOUT_SECONDS then
                local ready, readyCount, expectedCount, readinessDetail =
                    BridgeCheckOpeningHandReadiness(pending.seatId)
                if ready then
                    -- The readiness reason was captured before TTS published
                    -- all hand membership callbacks.  Re-evaluate the full
                    -- decision now that the exact hand is ready; otherwise a
                    -- stale defer reason can stop a valid seven-card opening
                    -- hand with ready=expected in the diagnostic.
                    BridgeState.openingHandReadinessSnapshotPending = false
                    BridgeLog(string.format(
                        "[Bridge] opening hand readiness recovered: ready=%d expected=%d; re-evaluating decision",
                        readyCount, expectedCount))
                    BridgeTryPresentPendingDecision(reason .. "-readiness-recovered")
                    return
                end
                if BridgeRecoverFromHandReadinessTimeout(pending, deferReason, string.format(
                    "ready=%d expected=%d missing=%d mappings=%s",
                    readyCount, expectedCount, math.max(expectedCount - readyCount, 0), readinessDetail)) then
                    return
                end
                BridgeStopOnDesync(string.format(
                    "opening hand readiness timeout: ready=%d expected=%d missing=%d mappings=%s",
                    readyCount, expectedCount, math.max(expectedCount - readyCount, 0), readinessDetail))
                return
            end
            BridgeLog(string.format(
                "[Bridge] holding opening mulligan decision %s: %s",
                tostring(pending.decisionId), tostring(deferDetail)))
            BridgeScheduleOpeningHandReadinessRetry()
            return
        end
        if deferReason == "hand_action_readiness" then
            BridgeState.pendingDecisionDeferredAt = deferredAt
            BridgeState.pendingDecisionDeferredCursor = eventCursor
            BridgeState.pendingDecisionDeferredApplied = applied
            -- Keep a discard/bottoming transaction visible through the HUD
            -- while exact hand GUIDs finish converging.  The HUD submits only
            -- the exact Forge ActionId; physical cards remain inert until
            -- their identity mapping is verified.  Without this fallback a
            -- post-mulligan hand race looked like "no discard prompt" and
            -- could never be recovered by the player.
            if BridgeIsDiscardChoice(pending) or BridgeIsMulliganBottomSelection(pending) then
                BridgeState.lastDecision = pending
                BridgeUiMarkDirty("hand-action-readiness-fallback")
                BridgeRenderDecision(pending, true)
            end
            -- Mulligan replacement cards can leave the next hand-based
            -- discard/cast menu one polling cycle ahead of its physical TTS
            -- mappings. Request one exact-session snapshot immediately so
            -- readiness converges without waiting for the long timeout.
            if BridgeState.handActionReadinessSnapshotDecisionId ~= pending.decisionId
                or BridgeState.handActionReadinessSnapshotSessionId ~= BridgeState.eventSessionId then
                BridgeState.handActionReadinessSnapshotDecisionId = pending.decisionId
                BridgeState.handActionReadinessSnapshotSessionId = BridgeState.eventSessionId
                BridgeScheduleSnapshotReconcile("hand-action-readiness")
            end
            if elapsed >= BRIDGE_OPENING_HAND_READINESS_TIMEOUT_SECONDS then
                if BridgeRecoverFromHandReadinessTimeout(pending, deferReason, deferDetail) then
                    return
                end
                BridgeStopOnDesync("hand action readiness timeout: " .. tostring(deferDetail))
                return
            end
            BridgeLog(string.format(
                "[Bridge] holding decision %s until exact hand action is embodied: %s",
                tostring(pending.decisionId), tostring(deferDetail)))
            BridgeScheduleHandActionReadinessRetry()
            return
        end
        local stalledProgress = BridgeState.pendingDecisionDeferredCursor == eventCursor
            and BridgeState.pendingDecisionDeferredApplied == applied
        if elapsed < BRIDGE_DECISION_DEFER_STALL_SECONDS or not stalledProgress then
            BridgeState.pendingDecisionDeferredAt = deferredAt
            BridgeState.pendingDecisionDeferredCursor = eventCursor
            BridgeState.pendingDecisionDeferredApplied = applied
            return
        end
        local ignoreStale = BridgeShouldIgnoreStaleDecision(pending)
        if ignoreStale then
            BridgeLog(string.format(
                "[Bridge] dropping stale deferred decision %s after %.1fs wait (cursor=%s applied=%s)",
                tostring(pending.decisionId), elapsed, tostring(eventCursor), tostring(applied)))
            BridgeState.pendingDecision = nil
            BridgeState.pendingDecisionDeferredAt = nil
            BridgeState.pendingDecisionDeferredCursor = 0
            BridgeState.pendingDecisionDeferredApplied = 0
            -- Retiring a stale deferred menu must not strand the protocol.
            -- Poll again for the exact current Forge decision after the
            -- event/physical-mapping fence has been observed.
            BridgeStartDecisionPolling()
            return
        end
        BridgeLog(string.format(
            "[Bridge] forcing deferred decision %s after %.1fs with unchanged cursor/applied (%s/%s)",
            tostring(pending.decisionId), elapsed, tostring(eventCursor), tostring(applied)))
    end
    local decision = BridgeState.pendingDecision
    BridgeState.pendingDecision = nil
    BridgeState.pendingDecisionDeferredAt = nil
    BridgeState.pendingDecisionDeferredCursor = 0
    BridgeState.pendingDecisionDeferredApplied = 0
    BridgeLog(string.format(
        "[Bridge] releasing gated decision %s (%s) cursor=%s applied=%s",
        tostring(decision.decisionId), tostring(reason or "event"),
        tostring(eventCursor), tostring(applied)))
    BridgeAcceptDecision(decision, "pending_decision_release", BridgeState.eventSessionId, BridgeState.decisionPresentationGeneration)
end

function BridgeZoneIsPublicForReconcile(zoneName)
    return zoneName == "battlefield"
        or zoneName == "graveyard"
        or zoneName == "stack"
        or zoneName == "exile"
        or zoneName == "command"
end

function BridgeShouldReconcileAfterEvent(event)
    -- Exact land/spell/card events are already the authoritative physical
    -- delta. Full snapshots are recovery authority only; routine verification
    -- here used to repaint the whole table after every ordinary mutation.
    local transition = event ~= nil and event.kind == "card_moved"
        and BridgeState.pendingStructuredZoneTransitionByInstanceId[event.cardInstanceId] or nil
    return transition ~= nil and transition.applied ~= true
end

function BridgeResumeChoiceProtocol(reason)
    if not BridgeState.choiceProtocolPaused then return end
    BridgeState.choiceProtocolPaused = false
    BridgeState.choiceProtocolFailureTimes = {}
    BridgeLog("[Bridge] CHOICE_PROTOCOL_RESUMED reason=" .. tostring(reason))
end

function BridgeCanDeferStructuredMoveToSnapshot(event)
    local destinationZone = string.lower(tostring(event.destinationZone or ""))
    return event.kind == "card_moved" and BridgeZoneIsPublicForReconcile(destinationZone)
end

-- A snapshot is authoritative for the resulting public zone, but it does not
-- carry the physical source of a card that was already public. In particular,
-- a missing graveyard/battlefield mapping must not be guessed as a library
-- extraction: during a burst such as Thought Scour (mill, mill, draw), that
-- would take the current library top by name and can pull a land or a card
-- which was already milled back out of the deck. Only an exact transition
-- which is still pending/in-flight may supply a source zone for a synthetic
-- snapshot repair.
function BridgeFindAuthoritativeSnapshotTransitionSourceZone(cardInstanceId, destinationZone)
    if cardInstanceId == nil or destinationZone == nil then return nil end
    local pending = BridgeState.pendingStructuredZoneTransitionByInstanceId[cardInstanceId]
    if pending ~= nil and tostring(pending.destinationZone or "") == tostring(destinationZone)
        and pending.sourceZone ~= nil and tostring(pending.sourceZone) ~= "" then
        return pending.sourceZone
    end
    for _, queued in ipairs(BridgeState.eventQueue or {}) do
        if queued ~= nil
            and queued.cardInstanceId == cardInstanceId
            and tostring(queued.destinationZone or "") == tostring(destinationZone)
            and queued.sourceZone ~= nil and tostring(queued.sourceZone) ~= "" then
            return queued.sourceZone
        end
    end
    return nil
end

function BridgeQueuedEventRange()
    local minimum, maximum = nil, nil
    for _, queued in ipairs(BridgeState.eventQueue or {}) do
        local sequence = tonumber(queued.sequence or 0) or 0
        if sequence > 0 then
            minimum = minimum == nil and sequence or math.min(minimum, sequence)
            maximum = maximum == nil and sequence or math.max(maximum, sequence)
        end
    end
    return minimum or 0, maximum or 0
end

function BridgeLogSnapshotOrdering(marker, snapshot, reason)
    local minQueued, maxQueued = BridgeQueuedEventRange()
    BridgeLog(string.format(
        "[Bridge] snapshot %s reason=%s forgeSequence=%s eventCursor=%s received=%s applied=%s queued=%s..%s",
        tostring(marker), tostring(reason), tostring(snapshot and snapshot.forgeSequence),
        tostring(snapshot and snapshot.eventCursor), tostring(BridgeState.lastReceivedEventSequence),
        tostring(BridgeState.lastAppliedEventSequence), tostring(minQueued), tostring(maxQueued)))
end

function BridgeSnapshotMayMutatePublicZones(snapshot)
    local snapshotCursor = tonumber(snapshot and snapshot.eventCursor or 0) or 0
    -- ForgeSequence is local to the child process and is not comparable to the
    -- bridge event stream. EventCursor is captured atomically with the HTTP
    -- snapshot and is the ordering invariant for public embodiment.
    return snapshotCursor <= tonumber(BridgeState.lastAppliedEventSequence or 0)
end

-- A snapshot can be authoritative while its physical library transitions are
-- still being embodied.  Applying it during a Thought Scour-style burst lets
-- bootstrap/reconcile extract a same-name card from the current Deck top,
-- racing the exact queued mill/draw operations.  Keep snapshot mutation
-- deferred until every seat's ordered library queue is idle.
function BridgePhysicalLibraryQueuesIdle()
    for seatId, _ in pairs(BRIDGE_SEATS or {}) do
        if BridgeState.libraryBatchBySeatId[seatId] ~= nil
            and BridgeState.libraryBatchBySeatId[seatId].active == true then
            return false
        end
        if BridgeState.libraryExtractionActiveBySeatId[seatId] == true
            or #(BridgeState.libraryExtractionQueueBySeatId[seatId] or {}) > 0
            or BridgeState.mulliganBottomInsertionActiveBySeatId[seatId] == true
            or #(BridgeState.mulliganBottomQueueBySeatId[seatId] or {}) > 0 then
            return false
        end
    end
    return true
end

function BridgeSnapshotRequestCategory(reason, category)
    if category ~= nil then return string.upper(tostring(category)) end
    local text = string.lower(tostring(reason or ""))
    if string.find(text, "final", 1, true) or string.find(text, "game_ended", 1, true) then return "FINAL" end
    if string.sub(text, 1, 6) == "event " then return "ROUTINE_VERIFY" end
    return "RECOVERY"
end

function BridgeEventBacklogCount()
    local received = tonumber(BridgeState.lastReceivedEventSequence or 0) or 0
    local applied = tonumber(BridgeState.lastAppliedEventSequence or 0) or 0
    return math.max(#(BridgeState.eventQueue or {}), math.max(0, received - applied))
end

function BridgeRoutineSnapshotBlocked()
    return BridgeEventBacklogCount() > 0 or BridgeState.animationRunning == true
end

function BridgeSnapshotRequestPriority(category)
    if category == "FINAL" then return 3 end
    if category == "RECOVERY" then return 2 end
    return 1
end

function BridgeRememberSnapshotRequest(reason, category)
    BridgeState.snapshotReconcileRequestGeneration = (BridgeState.snapshotReconcileRequestGeneration or 0) + 1
    local request = {
        reason = reason,
        category = category,
        generation = BridgeState.snapshotReconcileRequestGeneration
    }
    local prior = BridgeState.snapshotReconcilePendingRequest
    if prior == nil or BridgeSnapshotRequestPriority(category) >= BridgeSnapshotRequestPriority(prior.category) then
        -- Routine requests are latest-wins. Recovery/final requests retain
        -- priority over a routine request arriving in the same burst.
        BridgeState.snapshotReconcilePendingRequest = request
    end
    BridgeState.snapshotReconcilePending = true
end

function BridgeTryStartPendingSnapshotReconcile(reason)
    local request = BridgeState.snapshotReconcilePendingRequest
    if request == nil or BridgeState.snapshotReconcileInFlight then return false end
    if request.category == "ROUTINE_VERIFY" and BridgeRoutineSnapshotBlocked() then return false end
    BridgeState.snapshotReconcilePendingRequest = nil
    BridgeState.snapshotReconcilePending = false
    BridgeScheduleSnapshotReconcile(request.reason or reason or "pending", request.category)
    return true
end

function BridgeApplyCombatSnapshot(combat)
    local parts = {}
    for _, attack in ipairs((combat and combat.attacks) or {}) do table.insert(parts, tostring(attack.attackerCardInstanceId) .. "|" .. table.concat(attack.blockerCardInstanceIds or {}, ",")) end
    table.sort(parts)
    local signature = table.concat(parts, ";")
    if BridgeState.presentedCombatSignature == signature then return end
    BridgeState.presentedCombatSignature = signature
    BridgeReturnAttackPresentation(nil)
    for _, attack in ipairs((combat and combat.attacks) or {}) do
        local attackerGuid = BridgeState.physicalByInstanceId[attack.attackerCardInstanceId]
        local attacker = attackerGuid and BridgeGetLiveObjectByGuid(attackerGuid) or nil
        if attacker ~= nil then BridgeMoveToAttackLane(BridgeState.physicalSeatByGuid[attackerGuid], attacker) end
        for _, blockerId in ipairs(attack.blockerCardInstanceIds or {}) do
            local blockerGuid = BridgeState.physicalByInstanceId[blockerId]
            local blocker = blockerGuid and BridgeGetLiveObjectByGuid(blockerGuid) or nil
            if blocker ~= nil then BridgeMoveToBlockerLane(BridgeState.physicalSeatByGuid[blockerGuid], blocker) end
        end
    end
end

function BridgeApplySafeSnapshotReconcile(snapshot, reason)
    local movedCount = 0
    local queueBefore = #(BridgeState.eventQueue or {})
    local receivedBefore = tonumber(BridgeState.lastReceivedEventSequence or 0) or 0
    local appliedBefore = tonumber(BridgeState.lastAppliedEventSequence or 0) or 0
    local scansBefore = tonumber(BridgeState.presentationMetrics and BridgeState.presentationMetrics.worldScanCount or 0) or 0
    BridgePerformanceTrace("snapshot_reconcile.queue_lag_before", nil,
        math.max(0, receivedBefore - appliedBefore), queueBefore)
    BridgePresentationMetric("fullSnapshotReconcileCount")
    local pending = BridgeState.pendingDecision
    local requiredSeatId = pending ~= nil and pending.kind == "mulligan"
        and tostring(pending.mulliganStage or "") == "keep_or_mulligan"
        and pending.seatId or nil
    local handToken = BridgePerformanceBegin("snapshot_reconcile.hand_identity")
    BridgeRecordExpectedHandIdentities(snapshot, requiredSeatId)
    BridgePerformanceEnd(handToken, "snapshot_reconcile.hand_identity.end", "snapshotReconcileHandIdentity")
    local monarchToken = BridgePerformanceBegin("snapshot_reconcile.monarch")
    BridgeSetMonarchSeat(snapshot and snapshot.monarchSeatId or nil)
    BridgePerformanceEnd(monarchToken, "snapshot_reconcile.monarch.end", "snapshotReconcileMonarch")
    local stackToken = BridgePerformanceBegin("snapshot_reconcile.stack")
    BridgeState.stackSummary = {}
    BridgeState.stackObjects = snapshot and snapshot.stackObjects or {}
    for _, stackObject in ipairs(snapshot and snapshot.stackObjects or {}) do
        local source = tostring(stackObject.sourceName or "Forge source")
        local kind = tostring(stackObject.stackKind or "stack object")
        local text = tostring(stackObject.abilityText or stackObject.abilityName or "")
        table.insert(BridgeState.stackSummary, source .. " — " .. kind .. (text ~= "" and (": " .. text) or ""))
    end
    for _, card in ipairs(snapshot and snapshot.stack or {}) do
        if #(snapshot and snapshot.stackObjects or {}) == 0 then
            table.insert(BridgeState.stackSummary, tostring(card.currentCardName or card.cardName or "Forge stack object"))
        end
        BridgeState.authoritativeObjectByInstanceId[card.cardInstanceId] = {
            objectId = card.authoritativeObjectId or card.cardInstanceId,
            originObjectId = card.originObjectId,
            copySourceObjectId = card.copySourceObjectId,
            objectKind = card.objectKind,
            isCopy = card.isCopy == true,
            isVirtual = card.isVirtual == true,
            materializationPolicy = card.materializationPolicy
        }
    end
    BridgeUiMarkDirty("stack")
    BridgePerformanceEnd(stackToken, "snapshot_reconcile.stack.end", "snapshotReconcileStack")
    local publicZoneToken = BridgePerformanceBegin("snapshot_reconcile.public_zone_diff")
    for _, seatSnapshot in ipairs(snapshot.seats or {}) do
        for _, zone in ipairs(seatSnapshot.zones or {}) do
            local zoneName = string.lower(tostring(zone.name or ""))
            if BridgeZoneIsPublicForReconcile(zoneName) then
                for _, card in ipairs(zone.cards or {}) do
                    local mappedGuid = BridgeState.physicalByInstanceId[card.cardInstanceId]
                    local mappedObject = mappedGuid and getObjectFromGUID(mappedGuid) or nil
                    local mappedZone = mappedGuid and BridgeState.physicalZoneByGuid[mappedGuid] or nil
                    local snapshotRow = zoneName == "battlefield"
                        and (card.battlefieldKind == "land" and "land" or "creature") or nil
                    local priorRow = BridgeState.battlefieldKindByInstanceId[card.cardInstanceId]
                    local strandedAtStack = zoneName == "battlefield"
                        and mappedObject ~= nil and mappedObject.tag == "Card"
                        and BridgePhysicalObjectAtStackAnchor(mappedObject)
                    local mappedNeedsFix = mappedObject == nil or mappedObject.tag ~= "Card" or mappedZone ~= zoneName
                        or (snapshotRow ~= nil and priorRow ~= snapshotRow)
                        or strandedAtStack
                    if strandedAtStack then
                        BridgeTracePermanentTransition(
                            "SNAPSHOT_ZONE battlefield", {
                                cardInstanceId = card.cardInstanceId,
                                seatId = seatSnapshot.seatId,
                                sourceZone = mappedZone,
                                destinationZone = zoneName,
                                sequence = snapshot.forgeSequence
                            }, mappedObject, mappedZone, "physical object remains at stack anchor")
                    end
                    if mappedNeedsFix then
                        -- The log intentionally omits cardName: a snapshot can
                        -- contain identities that should not be public chat.
                        -- A public card absent from the reverse mapping has no
                        -- trustworthy physical source in a snapshot alone.
                        -- Never assume library here: a Thought Scour-style
                        -- mill/draw burst can otherwise extract the wrong top
                        -- card (including a land or an already-milled card).
                        -- The exact queued transition, when present, is the
                        -- only safe source for a synthetic repair.
                        local snapshotSourceZone = mappedObject ~= nil
                            and mappedObject.tag == "Card" and mappedZone or nil
                        if snapshotSourceZone == nil then
                            snapshotSourceZone = BridgeFindAuthoritativeSnapshotTransitionSourceZone(
                                card.cardInstanceId, zoneName)
                        end
                        BridgeLog(string.format(
                            "[Bridge] snapshot candidate instance=%s oldZone=%s destinationZone=%s",
                            tostring(card.cardInstanceId), tostring(mappedZone), tostring(zoneName)))
                        if snapshotSourceZone == nil then
                            BridgeLog(string.format(
                                "[Bridge] snapshot candidate deferred instance=%s destinationZone=%s: no exact source transition",
                                tostring(card.cardInstanceId), tostring(zoneName)))
                        else
                            local evt = {
                                seatId = seatSnapshot.seatId,
                                cardInstanceId = card.cardInstanceId,
                                cardName = card.cardName,
                                sourceZone = snapshotSourceZone,
                                destinationZone = zoneName,
                                faceDown = card.faceDown,
                                battlefieldKind = card.battlefieldKind
                            }
                            local moved, moveError = BridgeApplyStructuredCardMove(evt)
                            if moved then
                                movedCount = movedCount + 1
                            else
                                BridgeLog("[Bridge] snapshot reconcile skipped a move: " .. tostring(moveError))
                            end
                        end
                    end

                    if snapshotRow ~= nil then
                        BridgeState.battlefieldKindByInstanceId[card.cardInstanceId] = snapshotRow
                    end

                    local guid = BridgeState.physicalByInstanceId[card.cardInstanceId]
                    local object = guid and getObjectFromGUID(guid) or nil
                    if object ~= nil and object.tag == "Card" and zoneName == "battlefield" then
                        BridgeSetPhysicalTapped(object, card.tapped == true)
                    end
                end
            end
        end
        -- A newly materialized battlefield card may not have had a physical
        -- GUID when the first visual pass ran. Reapply the same authoritative
        -- snapshot after zone reconciliation so persistent designations and
        -- their badges appear without waiting for another Forge mutation.
        local seatVisualToken = BridgePerformanceBegin("snapshot_reconcile.seat_visual")
        BridgeApplySeatSnapshotVisualState(seatSnapshot)
        BridgePerformanceEnd(seatVisualToken, "snapshot_reconcile.seat_visual.end", "snapshotReconcileSeatVisual")
    end
    BridgePerformanceEnd(publicZoneToken, "snapshot_reconcile.public_zone_diff.end", "snapshotReconcilePublicZoneDiff", movedCount)
    local combatToken = BridgePerformanceBegin("snapshot_reconcile.combat")
    BridgeApplyCombatSnapshot(snapshot.combat)
    BridgePerformanceEnd(combatToken, "snapshot_reconcile.combat.end", "snapshotReconcileCombat")
    -- Snapshot reconciliation is also recovery authority for the turn
    -- pipeline. These values come directly from Forge; they never advance a
    -- phase or infer legality in Lua.
    local turnStateToken = BridgePerformanceBegin("snapshot_reconcile.turn_state")
    local snapshotCursor = tonumber(snapshot and snapshot.eventCursor or 0) or 0
    local projectedCursor = tonumber(BridgeState.lastStateProjectedEventSequence
        or BridgeState.lastAppliedEventSequence or 0) or 0
    local mayProjectTurnState = snapshotCursor >= projectedCursor
    if mayProjectTurnState then
        if snapshot.turnNumber ~= nil then BridgeState.tableTurnCount = snapshot.turnNumber end
        if snapshot.activeSeatId ~= nil then BridgeState.currentTurnSeatId = snapshot.activeSeatId end
        if snapshot.prioritySeatId ~= nil then BridgeState.prioritySeatId = snapshot.prioritySeatId end
        if snapshot.phase ~= nil and tostring(snapshot.phase) ~= "" then
            BridgeState.currentPhase = snapshot.phase
        end
    else
        BridgeLog(string.format("[Bridge] retaining newer event projection over older snapshot cursor=%s projected=%s",
            tostring(snapshotCursor), tostring(projectedCursor)))
    end
    BridgeUiMarkDirty("authoritative-snapshot-turn-state")
    BridgeState.snapshotForgeSequence = snapshot.forgeSequence or BridgeState.snapshotForgeSequence
    if BridgeRestoreAuthoritativeReveals ~= nil then BridgeRestoreAuthoritativeReveals(snapshot) end
    BridgeState.snapshotReconcileLastAppliedCursor = snapshotCursor
    BridgeState.snapshotReconcileLastAppliedGeneration = BridgeState.snapshotReconcileRequestGeneration or 0
    BridgeState.snapshotReconcileLastAppliedCategory = BridgeSnapshotRequestCategory(reason)
    BridgePerformanceEnd(turnStateToken, "snapshot_reconcile.turn_state.end", "snapshotReconcileTurnState")
    local receivedAfter = tonumber(BridgeState.lastReceivedEventSequence or 0) or 0
    local appliedAfter = tonumber(BridgeState.lastAppliedEventSequence or 0) or 0
    local queueAfter = #(BridgeState.eventQueue or {})
    local scansAfter = tonumber(BridgeState.presentationMetrics and BridgeState.presentationMetrics.worldScanCount or 0) or 0
    BridgePerformanceTrace("snapshot_reconcile.queue_lag_after", nil,
        math.max(0, receivedAfter - appliedAfter), queueAfter)
    BridgeLogSnapshotOrdering("applied", snapshot, reason)
    BridgeLog(string.format(
        "[Bridge] snapshot reconcile metrics cursor=%s received=%s applied=%s queueBefore=%s queueAfter=%s reason=%s corrected=%s physicalCorrection=%s worldScans=%s",
        tostring(snapshot.eventCursor), tostring(receivedAfter), tostring(appliedAfter), tostring(queueBefore),
        tostring(queueAfter), tostring(reason), tostring(movedCount), tostring(movedCount > 0), tostring(scansAfter - scansBefore)))
    if movedCount > 0 then
        BridgeLog(string.format("[Bridge] snapshot reconcile (%s): corrected %d public card location(s)", tostring(reason), movedCount))
    end
end

function BridgeTryApplyDeferredSnapshotReconcile(reason)
    local pending = BridgeState.deferredSnapshotReconcile
    if pending == nil or not BridgeSnapshotMayMutatePublicZones(pending.snapshot)
        or not BridgePhysicalLibraryQueuesIdle() then return false end
    if pending.category == "ROUTINE_VERIFY" and BridgeRoutineSnapshotBlocked() then
        return false
    end
    local snapshotCursor = tonumber(pending.snapshot and pending.snapshot.eventCursor or 0) or 0
    if pending.category == "ROUTINE_VERIFY"
        and snapshotCursor <= tonumber(BridgeState.snapshotReconcileLastAppliedCursor or 0) then
        BridgeState.deferredSnapshotReconcile = nil
        BridgeLogSnapshotOrdering("skipped-superseded", pending.snapshot, pending.reason or reason)
        return false
    end
    BridgeState.deferredSnapshotReconcile = nil
    BridgeState.pendingStructuredZoneTransitionByInstanceId = {}
    BridgeApplySafeSnapshotReconcile(pending.snapshot, pending.reason or reason or "deferred")
    return true
end

function BridgeScheduleSnapshotReconcile(reason, category)
    if BridgeState.eventSessionId == nil then return end
    category = BridgeSnapshotRequestCategory(reason, category)
    if category == "ROUTINE_VERIFY" and BridgeRoutineSnapshotBlocked() then
        BridgeRememberSnapshotRequest(reason, category)
        BridgeLog("[Bridge] routine snapshot held behind event drain reason=" .. tostring(reason)
            .. " backlog=" .. tostring(BridgeEventBacklogCount()))
        return
    end
    if BridgeState.snapshotReconcileInFlight then
        BridgeRememberSnapshotRequest(reason, category)
        return
    end
    BridgeState.snapshotReconcileInFlight = true
    local requestGeneration = (BridgeState.snapshotReconcileRequestGeneration or 0) + 1
    BridgeState.snapshotReconcileRequestGeneration = requestGeneration
    BridgeGetEmbodimentSnapshot(function(ok, snapshot, err)
        BridgeState.snapshotReconcileInFlight = false
        if ok and snapshot ~= nil and snapshot.sessionId == BridgeState.eventSessionId then
            local pending = BridgeState.pendingDecision
            local requiredSeatId = pending ~= nil and pending.kind == "mulligan"
                and tostring(pending.mulliganStage or "") == "keep_or_mulligan"
                and pending.seatId or nil
            local hasHandIdentities = BridgeRecordExpectedHandIdentities(snapshot, requiredSeatId)
            if not hasHandIdentities then
                BridgeState.openingHandReadinessSnapshotRequested = false
                BridgeLog("[Bridge] opening-hand-readiness snapshot contained no exact hand identities; retrying")
            end
            local snapshotCursor = tonumber(snapshot.eventCursor or 0) or 0
            local alreadyCovered = category == "ROUTINE_VERIFY"
                and snapshotCursor <= tonumber(BridgeState.snapshotReconcileLastAppliedCursor or 0)
            local canApply = not alreadyCovered
                and BridgeSnapshotMayMutatePublicZones(snapshot)
                and BridgePhysicalLibraryQueuesIdle()
                and (category ~= "ROUTINE_VERIFY" or not BridgeRoutineSnapshotBlocked())
            if canApply then
                BridgeApplySafeSnapshotReconcile(snapshot, reason)
            elseif alreadyCovered then
                BridgeLogSnapshotOrdering("skipped-superseded", snapshot, reason)
            else
                local prior = BridgeState.deferredSnapshotReconcile
                if prior == nil or BridgeSnapshotRequestPriority(category) >= BridgeSnapshotRequestPriority(prior.category) then
                    -- Keep one latest useful payload. Never let an older routine
                    -- response replace an explicit recovery snapshot.
                    BridgeState.deferredSnapshotReconcile = {
                        snapshot = snapshot,
                        reason = reason,
                        category = category,
                        generation = requestGeneration
                    }
                end
                local queueState = BridgePhysicalLibraryQueuesIdle() and "event-cursor" or "physical-library-queue"
                BridgeLogSnapshotOrdering("deferred-" .. queueState, snapshot, reason)
            end
        elseif not ok then
            BridgeLog("[Bridge] snapshot reconcile failed: " .. tostring(err))
        elseif snapshot ~= nil then
            BridgeLog("[Bridge] snapshot reconcile skipped due to session mismatch")
        end

        if BridgeState.pendingDecision ~= nil then
            BridgeTryPresentPendingDecision("snapshot-reconcile")
        end

        BridgeTryStartPendingSnapshotReconcile("pending")
    end)
end

function BridgeDoctorAddCheck(report, name, status, detail)
    local entry = {
        name = tostring(name or "unknown"),
        status = tostring(status or "WARN"),
        detail = tostring(detail or "")
    }
    table.insert(report.checks, entry)
    if entry.status == "PASS" then
        report.pass = report.pass + 1
    elseif entry.status == "FAIL" then
        report.fail = report.fail + 1
    else
        report.warn = report.warn + 1
    end
end

function BridgeDoctorPrintReport(report)
    BridgeLog(string.format(
        "[BridgeDoctor] PASS=%d WARN=%d FAIL=%d",
        tonumber(report.pass or 0), tonumber(report.warn or 0), tonumber(report.fail or 0)))
    for _, check in ipairs(report.checks or {}) do
        BridgeLog(string.format("[BridgeDoctor] %-4s %s :: %s", check.status, check.name, check.detail))
    end
end

function BridgeDoctorCheckTable(report, health)
    for seatId, seat in pairs(BRIDGE_SEATS) do
        local player, playerError = BridgeTryGetSeatPlayer(seatId)
        if player ~= nil then
            BridgeDoctorAddCheck(report, "seat.player." .. seatId, "PASS", "TTS color " .. tostring(seat.ttsColor))
        else
            BridgeDoctorAddCheck(report, "seat.player." .. seatId, "WARN", tostring(playerError))
        end

        local life = BridgeGetLiveObjectByGuid(seat.lifeCounterGuid)
        if life ~= nil then
            BridgeDoctorAddCheck(report, "seat.life." .. seatId, "PASS", "guid=" .. tostring(seat.lifeCounterGuid))
        else
            BridgeDoctorAddCheck(report, "seat.life." .. seatId, "FAIL", "life counter GUID is missing/unusable")
        end

        local library = BridgeGetLiveObjectByGuid(seat.libraryZoneGuid)
        if library ~= nil and library.tag == "Deck" then
            BridgeDoctorAddCheck(report, "seat.library." .. seatId, "PASS", "guid=" .. tostring(seat.libraryZoneGuid))
        elseif library ~= nil then
            BridgeDoctorAddCheck(report, "seat.library." .. seatId, "FAIL", "library GUID resolved to " .. tostring(library.tag))
        else
            BridgeDoctorAddCheck(report, "seat.library." .. seatId, "FAIL", "library GUID is missing/unusable")
        end

        local graveyardAnchor = BridgeResolveSeatZoneAnchor(seatId, "graveyard")
        if graveyardAnchor ~= nil then
            BridgeDoctorAddCheck(report, "seat.graveyard." .. seatId, "PASS", string.format(
                "anchor=(%.2f, %.2f, %.2f)", graveyardAnchor.x, graveyardAnchor.y, graveyardAnchor.z))
        else
            BridgeDoctorAddCheck(report, "seat.graveyard." .. seatId, "FAIL", "no graveyard anchor resolved")
        end

        local exileAnchor = BridgeResolveSeatZoneAnchor(seatId, "exile")
        if exileAnchor ~= nil then
            BridgeDoctorAddCheck(report, "seat.exile." .. seatId, "PASS", string.format(
                "anchor=(%.2f, %.2f, %.2f)", exileAnchor.x, exileAnchor.y, exileAnchor.z))
        else
            BridgeDoctorAddCheck(report, "seat.exile." .. seatId, "FAIL", "no exile anchor resolved")
        end

        local deck, candidates, reason = BridgeResolveSeatLibraryDeck(seatId)
        if #candidates > 1 then
            BridgeDoctorAddCheck(report, "seat.deck." .. seatId, "FAIL",
                "ambiguous deck candidates near library (" .. tostring(#candidates) .. ")")
        elseif deck == nil then
            BridgeDoctorAddCheck(report, "seat.deck." .. seatId, "FAIL", tostring(reason or "deck not identifiable"))
        else
            local deckGuid = BridgeSafeObjectGuid(deck)
            BridgeDoctorAddCheck(report, "seat.deck." .. seatId, "PASS",
                "deck=" .. tostring(deckGuid) .. " candidates=" .. tostring(#candidates))
        end
    end

    local encoder = Global.getVar("Encoder")
    if encoder == nil then
        BridgeDoctorAddCheck(report, "table.encoder", "WARN", "Easy Modules Encoder unavailable")
        return
    end
    BridgeDoctorAddCheck(report, "table.encoder", "PASS", "Easy Modules Encoder resolved")

    local keywordCardsTested = 0
    for seatId, _ in pairs(BRIDGE_SEATS) do
        local testedForSeat = 0
        for _, object in ipairs(getAllObjects()) do
            if object.tag == "Card" and IsGameCardCandidate(object, seatId, nil) then
                local ok, data = pcall(function()
                    return encoder.call("APIobjGetPropData", {obj = object, propID = "πKeywords"})
                end)
                keywordCardsTested = keywordCardsTested + 1
                testedForSeat = testedForSeat + 1
                if ok and data ~= nil then
                    BridgeDoctorAddCheck(report, "table.piKeywords." .. seatId, "PASS",
                        "guid=" .. tostring(BridgeSafeObjectGuid(object)))
                else
                    BridgeDoctorAddCheck(report, "table.piKeywords." .. seatId, "WARN",
                        "card lacks πKeywords metadata or read failed")
                end
                if testedForSeat >= 2 then break end
            end
        end
    end
    if keywordCardsTested == 0 then
        BridgeDoctorAddCheck(report, "table.piKeywords", "WARN", "no visible game cards available for capability probe")
    end
end

function BridgeDoctor(done)
    local report = {
        checks = {},
        pass = 0,
        warn = 0,
        fail = 0,
        companionOk = false
    }

    local startup = BridgeState.startupTrace
    local healthDispatchToken = nil
    if startup ~= nil and not startup.healthDispatchRecorded then
        startup.healthDispatchRecorded = true
        healthDispatchToken = BridgeStartupStageBegin("startup_bridge_health_begin")
    end
    BridgeGetHealth(function(ok, body, err)
        if ok and body ~= nil then
            report.companionOk = true
            BridgeDoctorAddCheck(report, "companion.health", "PASS", "GET /health")
            BridgeDoctorAddCheck(report, "companion.adapter", "PASS",
                tostring(body.adapter) .. " state=" .. tostring(body.adapterState))
            local sessionState = nil
            if body.sessionId == nil or body.sessionId == "session-not-started" then
                sessionState = "no-active-session"
            else
                sessionState = "session=" .. tostring(body.sessionId)
            end
            BridgeDoctorAddCheck(report, "companion.session", "PASS", sessionState)
        else
            BridgeDoctorAddCheck(report, "companion.health", "FAIL", tostring(err or "request failed"))
            BridgeDoctorAddCheck(report, "companion.adapter", "WARN", "companion offline")
            BridgeDoctorAddCheck(report, "companion.session", "WARN", "unknown while offline")
        end

        local discoveryToken = nil
        if startup ~= nil and not startup.objectDiscoveryRecorded then
            startup.objectDiscoveryRecorded = true
            discoveryToken = BridgeStartupStageBegin("startup_object/bootstrap_discovery_begin")
        end
        BridgeDoctorCheckTable(report, body)
        BridgeStartupStageEnd(discoveryToken, "startup_object/bootstrap_discovery_end",
            "objectDiscoveryDurationMs")
        BridgeDoctorPrintReport(report)
        if done ~= nil then done(report) end
    end)
    BridgeStartupStageEnd(healthDispatchToken, "startup_bridge_health_dispatched",
        "healthDispatchDurationMs")
end

function BridgeInitializeInteractiveUi()
    if BridgeState.doctorInitializedUi then return end
    BridgeState.doctorInitializedUi = true
    local startupUiToken = BridgeStartupStageBegin("startup_ui_begin")
    BridgeWaitFrames(function()
        local cleanupToken = BridgeStartupStageBegin("startup_transient_cleanup_begin")
        BridgeTryStartupStep("destroy_transient_controls", BridgeDestroyTransientControls)
        BridgeStartupStageEnd(cleanupToken, "startup_transient_cleanup_end",
            "transientCleanupDurationMs")
        BridgeTryStartupStep("ensure_setup_controls", BridgeEnsureSetupControls)
        BridgeTryStartupStep("ensure_turn_counters", BridgeEnsureTurnCounters)
        BridgeTryStartupStep("ensure_status_panel", BridgeEnsureStatusPanel)
        BridgeTryStartupStep("show_preparation_readiness", BridgeShowPreparationReadiness)
        BridgeStartupStageEnd(startupUiToken, "startup_ui_end", "uiDurationMs")
        BridgeLogStartupSummary()
    end, 30)
end

function BridgeScheduleCompanionRetry(attempt)
    if BridgeState.doctorInitializedUi then return end
    local currentAttempt = tonumber(attempt or 1) or 1
    BridgeState.doctorRetryAttempt = currentAttempt
    BridgeWaitTime(function()
        if BridgeState.doctorInitializedUi then return end
        BridgeGetHealth(function(ok, body, err)
            if ok and body ~= nil then
                BridgeLog("[Bridge] companion became reachable; initializing controls.")
                BridgeInitializeInteractiveUi()
                return
            end
            if currentAttempt == 1 or currentAttempt % 6 == 0 then
                BridgeLog("[Bridge] companion still offline; retrying health in 5s (" .. tostring(currentAttempt) .. ")")
            end
            BridgeSetStatus("COMPANION OFFLINE", "Bridge unreachable at 127.0.0.1:43110")
            if currentAttempt == 1 then
                broadcastToAll("[Bridge] COMPANION OFFLINE: bridge unreachable at 127.0.0.1:43110", {1.0, 0.55, 0.1})
            end
            BridgeScheduleCompanionRetry(currentAttempt + 1)
        end)
    end, 5)
end

function BridgeRetryCompanion()
    BridgeDoctor(function(report)
        if report.companionOk then
            BridgeInitializeInteractiveUi()
        else
            BridgeSetStatus("COMPANION OFFLINE", "Bridge unreachable at 127.0.0.1:43110")
            BridgeScheduleCompanionRetry(1)
        end
    end)
end

function BridgeOnLoad()
    BridgePerformanceTrace("BridgeOnLoad_enter")
    BridgeUiMount()
    BridgeLog("[Bridge] ForgeBot integration loaded. revision=" .. tostring(BRIDGE_SCRIPT_REVISION)
        .. " runtimeId=" .. tostring(BRIDGE_CLIENT_RUNTIME_ID)
        .. " runtimeEpoch=" .. tostring(BRIDGE_RUNTIME_EPOCH_LOCAL))
    BridgeSetStatus("CLIENT LOADED", "Running ForgeBot preflight...")
    BridgeDoctor(function(report)
        if report.companionOk then
            BridgeInitializeInteractiveUi()
        else
            BridgeSetStatus("COMPANION OFFLINE", "Bridge unreachable at 127.0.0.1:43110")
            BridgeLog("[Bridge] companion unavailable on load; skipping bootstrap and waiting for retry.")
            broadcastToAll("[Bridge] COMPANION OFFLINE: bridge unreachable at 127.0.0.1:43110", {1.0, 0.55, 0.1})
            BridgeScheduleCompanionRetry(1)
        end
    end)
end

function BridgeEnsureObjectButton(object, config)
    if object == nil or config == nil or not BridgeObjectIsUsable(object) then return end
    local buttons = object.getButtons and object.getButtons() or {}
    if #buttons > 0 then
        -- Avoid editButton here; stale embedded objects can throw Unity-side
        -- object-reference errors during startup hydration.
        return
    end
    pcall(function()
        if object.createButton ~= nil then object.createButton(config) end
    end)
end

function BridgeEnsureStatusPanel()
    local existing = BridgeGetLiveObjectByGuid(BridgeState.statusObjectGuid)
    if existing ~= nil then
        local buttons = existing.getButtons and existing.getButtons() or {}
        if #buttons == 0 then
            BridgeEnsureObjectButton(existing, {
                click_function = "BridgeIgnoreStatusClick",
                function_owner = Global,
                label = tostring(BridgeState.statusHeadline or "FORGE STATUS") .. "\n" .. tostring(BridgeState.statusDetail or ""),
                position = {0, 0.55, 0},
                width = 1750,
                height = 420,
                font_size = 115,
                color = {0.12, 0.12, 0.16, 1},
                font_color = {1, 1, 1, 1},
                tooltip = "Forge-authoritative game status"
            })
        end
        BridgeRefreshStatusPanel()
        return
    end
    for _, object in ipairs(getAllObjects()) do
        if BridgeObjectIsUsable(object) and BridgeSafeObjectName(object) == "Forge Status" then
            BridgeState.statusObjectGuid = BridgeSafeObjectGuid(object)
            BridgeRefreshStatusPanel()
            return
        end
    end
    spawnObject({
        type = "BlockSquare",
        position = {-1.0, 1.6, 0},
        rotation = {0, 180, 0},  -- Rotated to face blue seat (forge-player-1)
        scale = {4.8, 0.3, 1.25},
        callback_function = function(object)
            if not BridgeObjectIsUsable(object) then return end
            object.setName("Forge Status")
            object.setLock(true)
            object.setColorTint({0.12, 0.12, 0.16})
            BridgeEnsureObjectButton(object, {
                click_function = "BridgeIgnoreStatusClick",
                function_owner = Global,
                label = tostring(BridgeState.statusHeadline or "FORGE STATUS") .. "\n" .. tostring(BridgeState.statusDetail or ""),
                position = {0, 0.55, 0},
                width = 1750,
                height = 420,
                font_size = 115,
                color = {0.12, 0.12, 0.16, 1},
                font_color = {1, 1, 1, 1},
                tooltip = "Forge-authoritative game status"
            })
            BridgeState.statusObjectGuid = object.getGUID()
            BridgeRefreshStatusPanel()
        end
    })
end

function BridgeIgnoreStatusClick(object, playerColor, altClick)
end

function BridgeSetStatus(headline, detail)
    BridgeState.statusHeadline = headline or BridgeState.statusHeadline
    BridgeState.statusDetail = detail or ""
    BridgeRefreshStatusPanel()
    BridgeUiMarkDirty("status")
end

function BridgeTurnLabel()
    return "TURN " .. tostring(BridgeState.tableTurnCount or 0)
end

function BridgeCurrentSeatLabel(seatId)
    local seat = BRIDGE_SEATS[seatId]
    return tostring((seat and seat.ttsColor) or seatId or "Unknown")
end
function BridgeRefreshStatusPanel()
    local object = BridgeGetLiveObjectByGuid(BridgeState.statusObjectGuid)
    if object ~= nil then
        BridgeSafeObjectCall(object, function(o)
            if o.clearButtons ~= nil then o.clearButtons() end
            if o.createButton ~= nil then
                o.createButton({
                    click_function = "BridgeIgnoreStatusClick",
                    function_owner = Global,
                    label = tostring(BridgeState.statusHeadline) .. "\n" .. tostring(BridgeState.statusDetail),
                    position = {0, 0.55, 0},
                    width = 1750,
                    height = 420,
                    font_size = 115,
                    color = {0.12, 0.12, 0.16, 1},
                    font_color = {1, 1, 1, 1},
                    tooltip = "Forge-authoritative game status"
                })
            end
        end)
    end
end

function BridgeShowPreparationReadiness()
    BridgeGetHealth(function(ok, body, err)
        if not ok then
            BridgeSetStatus("COMPANION OFFLINE", "Bridge unreachable at 127.0.0.1:43110")
            BridgeLog("[Bridge] preparation: companion unavailable: " .. tostring(err))
            return
        end
        local humanDeck, humanCandidates = BridgeResolveSeatLibraryDeck("forge-player-1")
        local aiDeck, aiCandidates = BridgeResolveSeatLibraryDeck("forge-player-2")
        local humanDeckOk = humanDeck ~= nil and #humanCandidates <= 1
        local aiDeckOk = aiDeck ~= nil and #aiCandidates <= 1
        BridgeLog(string.format(
            "[Bridge] preparation: Companion=READY Human deck=%s AI deck=%s active=%s",
            humanDeckOk and "FOUND" or "MISSING/AMBIG", aiDeckOk and "FOUND" or "MISSING/AMBIG",
            tostring(body.sessionId ~= nil and body.sessionId ~= "session-not-started" and body.adapterState ~= "not_started" and body.adapterState ~= "failed")))
        if body.adapterState == "starting" then
            BridgeSetStatus("FORGE INITIALIZING", "Loading Forge card database")
        elseif body.adapterState == "failed" then
            BridgeSetStatus("ERROR", "Forge process failed")
        elseif body.sessionId == nil or body.sessionId == "session-not-started" then
            BridgeSetStatus("COMPANION READY", "READY TO START")
        elseif body.adapterState == "awaiting_human_decision" then
            BridgeSetStatus("MATCH ACTIVE", "YOUR PRIORITY")
        else
            BridgeSetStatus("MATCH ACTIVE", "AI THINKING")
        end
    end)
end

function BridgeFindLibraryDeckForSeat(seatId)
    local deck = BridgeResolveSeatLibraryDeck(seatId)
    return deck
end

function BridgeEnsureSetupControl(kind, label, x, color, clickFunction, tooltip)
    local existingGuid = BridgeState.setupObjectGuidByKind[kind]
    local existing = BridgeGetLiveObjectByGuid(existingGuid)
    if existing ~= nil then
        local buttons = existing.getButtons and existing.getButtons() or {}
        if #buttons == 0 then
            BridgeEnsureObjectButton(existing, {
                click_function = clickFunction,
                function_owner = Global,
                label = label,
                position = {0, 0.6, 0},
                width = 900,
                height = 420,
                font_size = 145,
                color = color,
                font_color = {1, 1, 1, 1},
                tooltip = tooltip
            })
        end
        return
    end
    for _, object in ipairs(getAllObjects()) do
        if BridgeObjectIsUsable(object) and BridgeSafeObjectName(object) == BRIDGE_SETUP_CONTROL_PREFIX .. kind then
            BridgeState.setupObjectGuidByKind[kind] = BridgeSafeObjectGuid(object)
            local buttons = object.getButtons and object.getButtons() or {}
            if #buttons == 0 then
                BridgeEnsureObjectButton(object, {
                    click_function = clickFunction,
                    function_owner = Global,
                    label = label,
                    position = {0, 0.6, 0},
                    width = 900,
                    height = 420,
                    font_size = 145,
                    color = color,
                    font_color = {1, 1, 1, 1},
                    tooltip = tooltip
                })
            end
            return
        end
    end
    spawnObject({
        type = "BlockSquare",
        position = {x, 1.6, -17.0},
        scale = {2.5, 0.35, 1.25},
        callback_function = function(object)
            if not BridgeObjectIsUsable(object) then return end
            object.setName(BRIDGE_SETUP_CONTROL_PREFIX .. kind)
            object.setLock(true)
            object.setColorTint(color)
            object.setRotation({0, 180, 0})
            BridgeEnsureObjectButton(object, {
                click_function = clickFunction,
                function_owner = Global,
                label = label,
                position = {0, 0.6, 0},
                width = 900,
                height = 420,
                font_size = 145,
                color = color,
                font_color = {1, 1, 1, 1},
                tooltip = tooltip
            })
            BridgeState.setupObjectGuidByKind[kind] = object.getGUID()
        end
    })
end

-- Forge startup can take a minute while its card database loads.  Keep the
-- setup controls visibly busy and reject duplicate clicks until the request
-- has produced a usable session (or failed).
function BridgeSetSetupBusy(busy, message)
    BridgeState.setupBusy = busy
    -- Avoid mutating setup button state while TTS is processing click callbacks.
    -- Some table states surface a Unity-side object-reference fault during editButton.
    if busy and message ~= nil then broadcastToAll("[Bridge] " .. message, {1.0, 0.8, 0.2}) end
    if busy then BridgeSetStatus("FORGE INITIALIZING", message or "Please wait") end
end

function BridgeEnsureSetupControls()
    BridgeEnsureSetupControl("Start", "START\nMATCH", -7.0, {0.12, 0.48, 0.25}, "BridgePressStartMatch", "Start only when no Forge match exists")
    BridgeEnsureSetupControl("Resume", "RESUME", -1.0, {0.15, 0.35, 0.65}, "BridgePressResume", "Attach to the active Forge match without resetting it")
    BridgeEnsureSetupControl("Reset", "NEW MATCH\n(2 CLICKS)", 5.0, {0.65, 0.18, 0.12}, "BridgePressNewMatch", "Explicitly replace the active Forge match; click twice")
end

-- These are presentation-only counters. Forge's turn events remain the sole
-- authority; TTS never infers a turn from a card movement or timer.
function BridgeEnsureTurnCounter(kind, label, position, color)
    local existingGuid = BridgeState.turnCounterObjectGuidByKind[kind]
    local existing = BridgeGetLiveObjectByGuid(existingGuid)
    if existing ~= nil then
        local buttons = existing.getButtons and existing.getButtons() or {}
        if #buttons == 0 then
            BridgeEnsureObjectButton(existing, {
                click_function = "BridgeIgnoreTurnCounterClick",
                function_owner = Global,
                label = label .. "\n0",
                position = {0, 0.55, 0},
                width = 760,
                height = 340,
                font_size = 110,
                color = color,
                font_color = {1, 1, 1, 1},
                tooltip = "Forge-authoritative turn counter"
            })
        end
        BridgeRefreshTurnCounterLabels()
        return
    end
    local objectName = "Forge Turn Counter " .. kind
    for _, object in ipairs(getAllObjects()) do
        if BridgeObjectIsUsable(object) and BridgeSafeObjectName(object) == objectName then
            BridgeState.turnCounterObjectGuidByKind[kind] = BridgeSafeObjectGuid(object)
            local buttons = object.getButtons and object.getButtons() or {}
            if #buttons == 0 then
                BridgeEnsureObjectButton(object, {
                    click_function = "BridgeIgnoreTurnCounterClick",
                    function_owner = Global,
                    label = label .. "\n0",
                    position = {0, 0.55, 0},
                    width = 760,
                    height = 340,
                    font_size = 110,
                    color = color,
                    font_color = {1, 1, 1, 1},
                    tooltip = "Forge-authoritative turn counter"
                })
            end
            BridgeRefreshTurnCounterLabels()
            return
        end
    end
    spawnObject({
        type = "BlockSquare",
        position = position,
        scale = {1.7, 0.28, 0.9},
        callback_function = function(object)
            if not BridgeObjectIsUsable(object) then return end
            object.setName(objectName)
            object.setLock(true)
            object.setColorTint(color)
            object.setRotation({0, 180, 0})
            BridgeEnsureObjectButton(object, {
                click_function = "BridgeIgnoreTurnCounterClick",
                function_owner = Global,
                label = label .. "\n0",
                position = {0, 0.55, 0},
                width = 760,
                height = 340,
                font_size = 110,
                color = color,
                font_color = {1, 1, 1, 1},
                tooltip = "Forge-authoritative turn counter"
            })
            BridgeState.turnCounterObjectGuidByKind[kind] = object.getGUID()
            BridgeRefreshTurnCounterLabels()
        end
    })
end

function BridgeIgnoreTurnCounterClick(object, playerColor, altClick)
    -- Deliberately noninteractive: only an authoritative Forge turn event updates it.
end

function BridgeEnsureTurnCounters()
    BridgeEnsureTurnCounter("Table", "TABLE TURN", {x = -7.0, y = 1.6, z = -18.0}, {0.35, 0.35, 0.35})
    BridgeEnsureTurnCounter("White", "WHITE TURN", {x = -1.0, y = 1.6, z = -18.0}, {0.88, 0.88, 0.88})
    BridgeEnsureTurnCounter("Blue", "BLUE TURN", {x = 5.0, y = 1.6, z = -18.0}, {0.12, 0.35, 0.7})
end

function BridgeRefreshTurnCounterLabels()
    local labels = {
        Table = "TURN\n" .. tostring(BridgeState.tableTurnCount or 0),
        White = "WHITE TURN\n" .. tostring(BridgeState.turnCountsBySeatId["forge-player-1"] or 0),
        Blue = "BLUE TURN\n" .. tostring(BridgeState.turnCountsBySeatId["forge-player-2"] or 0)
    }
    local colors = {
        Table = {0.35, 0.35, 0.35, 1},
        White = {0.88, 0.88, 0.88, 1},
        Blue = {0.12, 0.35, 0.7, 1}
    }
    for kind, label in pairs(labels) do
        local guid = BridgeState.turnCounterObjectGuidByKind[kind]
        local object = BridgeGetLiveObjectByGuid(guid)
        if object ~= nil then
            BridgeSafeObjectCall(object, function(o)
                if o.clearButtons ~= nil then o.clearButtons() end
                if o.createButton ~= nil then
                    o.createButton({
                        click_function = "BridgeIgnoreTurnCounterClick",
                        function_owner = Global,
                        label = label,
                        position = {0, 0.55, 0},
                        width = 760,
                        height = 340,
                        font_size = 110,
                        color = colors[kind] or {0.35, 0.35, 0.35, 1},
                        font_color = {1, 1, 1, 1},
                        tooltip = "Forge-authoritative turn counter"
                    })
                end
            end)
        end
    end
end

function BridgeRecordAuthoritativeTurn(seatId, turnNumber)
    if turnNumber ~= nil and turnNumber > 0 then
        BridgeState.tableTurnCount = turnNumber
    else
        BridgeState.tableTurnCount = (BridgeState.tableTurnCount or 0) + 1
    end
    BridgeState.turnCountsBySeatId[seatId] = (BridgeState.turnCountsBySeatId[seatId] or 0) + 1
    BridgeRefreshTurnCounterLabels()
end
function BridgePressStartMatch(object, playerColor, altClick)
    local color = playerColor
    local alt = altClick == true
    BridgeTraceStart("START-01 click", tostring(color or "unknown"))
    BridgeWaitFrames(function()
        BridgeRunTraced("START-02 deferred-handler", function()
            BridgeDoPressStartMatch(color, alt)
        end)
    end, 1)
end

function BridgeDoPressStartMatch(playerColor, altClick)
    BridgeTraceStart("START-02 deferred-handler")
    if BridgeState.setupBusy then
        BridgeShowError("Forge is still initializing; wait for the loading controls to finish")
        return
    end
    if not BridgeGuardLifecycleCommand("START_MATCH") then return end
    BridgeSetSetupBusy(true, "Forge match is loading; START and RESUME are temporarily disabled.")
    BridgeSetupStage("CONTACTING_BRIDGE", "checking bridge health")
    BridgeTraceStart("START-03 health-request")
    BridgeGetHealth(function(ok, body, err)
        BridgeRunTraced("START-04 health-response", function()
            BridgeTraceStart("START-04 health-response", ok and "ok" or tostring(err))
            if not ok then
                BridgeSetSetupBusy(false)
                BridgeSetupFailure("bridge-health", err)
                BridgeShowError("cannot start: companion unavailable: " .. tostring(err))
                return
            end
            if body.adapterState == "starting" then
                BridgeSetSetupBusy(true, "Forge is still initializing; wait for startup to finish before starting a new match.")
                BridgeSetStatus("FORGE INITIALIZING", "Loading Forge card database")
                return
            end
            local active = body.sessionId ~= nil and body.sessionId ~= "session-not-started"
                and body.adapterState ~= "not_started" and body.adapterState ~= "failed"
            if active then BridgeSetSetupBusy(false); BridgeShowError("a Forge match already exists; use RESUME or explicitly choose NEW MATCH"); return end
            BridgeSetupStage("READING_DECKS", "scanning both configured piles")
            BridgeTraceStart("START-05 deck-check-begin")
            local humanDeck, humanCandidates = BridgeResolveSeatLibraryDeck("forge-player-1")
            local aiDeck, aiCandidates = BridgeResolveSeatLibraryDeck("forge-player-2")
            if humanDeck == nil or aiDeck == nil or #humanCandidates > 1 or #aiCandidates > 1 then
                BridgeSetSetupBusy(false)
                BridgeSetupFailure("deck-reading", "both physical library decks must be uniquely identifiable before START")
                BridgeShowError("both physical library decks must be uniquely identifiable before START")
                return
            end
            local preflightOk, preflightError = BridgeStartMatchPreflight(humanDeck, aiDeck)
            if not preflightOk then
                BridgeSetSetupBusy(false)
                BridgeSetupFailure("start-preflight", preflightError)
                BridgeShowError("START MATCH refused: " .. tostring(preflightError) .. ". Use NEW MATCH to clean existing session objects.")
                return
            end
            BridgeSetupTrace("SETUP_STATE_VALIDATED", "deck piles uniquely identified")
            BridgeTraceStart("START-06 deck-check-complete")
            BridgeStartSessionIfNone(function() BridgeSetSetupBusy(false) end)
        end)
    end)
end

function BridgePressResume(object, playerColor, altClick)
    local color = playerColor
    local alt = altClick == true
    BridgeWaitFrames(function()
        BridgeDoPressResume(color, alt)
    end, 1)
end

function BridgeDoPressResume(playerColor, altClick)
    if BridgeState.setupBusy then
        BridgeShowError("Forge is still initializing; wait for the loading controls to finish")
        return
    end
    if not BridgeGuardLifecycleCommand("RESUME_MATCH") then return end
    -- RESUME is a continuation operation, not an attach/bootstrap operation.
    -- An active session already owns its event cursor and physical mappings;
    -- routing it through BridgeAttachToActiveSession used the fresh-attach
    -- bootstrap path (BridgePrepareEventSession(..., true)), which reset a
    -- healthy cursor and rebuilt unrelated cards.  Classify the local state
    -- before considering authoritative recovery.
    if BridgeState.eventSessionId ~= nil
        and BridgeState.eventSessionId ~= "session-not-started"
        and BridgeState.lifecycleState ~= BRIDGE_LIFECYCLE_READY_NO_SESSION
        and BridgeState.lifecycleState ~= BRIDGE_LIFECYCLE_START_FAILED then
        BridgeResumeActiveSession("resume")
        return
    end
    BridgeShowError("RESUME requires an already-paused local session. Use START MATCH from clean setup or NEW MATCH for explicit teardown.")
end

function BridgeClassifyResumeState()
    if BridgeState.eventSessionId == nil or BridgeState.eventSessionId == "session-not-started" then
        return "SESSION_MISMATCH"
    end
    if BridgeState.lifecycleState == BRIDGE_LIFECYCLE_ENDING then return "MATCH_TEARDOWN_ACTIVE" end
    if BridgeState.resyncInFlight == true or BridgeState.bootstrapping == true then return "RECOVERY_ACTIVE" end
    local received = tonumber(BridgeState.lastReceivedEventSequence or 0) or 0
    local applied = tonumber(BridgeState.lastAppliedEventSequence or 0) or 0
    if received ~= applied or #(BridgeState.eventQueue or {}) > 0 then return "CURSOR_BEHIND" end
    if BridgeState.lastDecision ~= nil and BridgeDecisionPhysicalMappingsReady ~= nil then
        local ready, missing = BridgeDecisionPhysicalMappingsReady(BridgeState.lastDecision)
        if not ready then
            return "CURSOR_CURRENT_MAPPING_DEFECT", missing
        end
    end
    if BridgeState.desyncLatched == true then
        return "CURSOR_CURRENT_MAPPING_DEFECT", BridgeState.desyncLastMessage
    end
    if BridgeState.lastDecision ~= nil then return "PROTOCOL_PAUSED_AND_COHERENT" end
    return "PROTOCOL_PAUSED_AND_COHERENT"
end

function BridgeResumeActiveSession(reason)
    local classification, detail = BridgeClassifyResumeState()
    BridgeLog("[Bridge] RESUME_CLASSIFIED state=" .. tostring(classification)
        .. " detail=" .. tostring(detail) .. " session=" .. tostring(BridgeState.eventSessionId)
        .. " received=" .. tostring(BridgeState.lastReceivedEventSequence)
        .. " applied=" .. tostring(BridgeState.lastAppliedEventSequence))

    if classification == "MATCH_TEARDOWN_ACTIVE" or classification == "SESSION_MISMATCH" then
        BridgeShowError("RESUME is unavailable because no continuous active Forge session can be proven")
        return false
    end
    if classification == "RECOVERY_ACTIVE" then
        BridgeShowError("authoritative recovery is already in progress; use RESUME after it completes")
        return false
    end
    if classification == "CURSOR_BEHIND" then
        BridgeSetStatus("SYNCHRONIZING", "RESUME is waiting for the authoritative event checkpoint")
        if BridgeState.desyncLatched == true then
            BridgeEnsureDesyncRecovery("resume-cursor-behind")
        else
            -- A paused poller with queued authoritative work is not a new
            -- session. Resume its existing event session and let the normal
            -- ordered consumer catch up; only a latched desync escalates to
            -- snapshot recovery.
            BridgeStartEventPolling(BridgeState.eventSessionId, false)
            BridgeStartDecisionPolling(false)
        end
        return false
    end
    if classification == "CURSOR_CURRENT_MAPPING_DEFECT" then
        -- Never use the fresh-session bootstrap here.  The recovery scheduler
        -- owns any authoritative identity repair and its transaction preserves
        -- the committed cursor/mapping registry until a replacement is valid.
        BridgeLog("[Bridge] TARGETED_MAPPING_REPAIR_REQUESTED instance=" .. tostring(detail))
        BridgeSetStatus("MAPPING REPAIR", "Repairing only the missing authoritative physical identity")
        BridgeScheduleSnapshotReconcile("resume-targeted-mapping-repair", "RECOVERY")
        return false
    end

    BridgeResumeChoiceProtocol(reason or "resume-active-session")
    if BridgeStartEventPolling ~= nil then BridgeStartEventPolling(BridgeState.eventSessionId, false) end
    if BridgeState.lastDecision ~= nil then
        BridgeRenderDecision(BridgeState.lastDecision, true)
    else
        BridgeStartDecisionPolling(true)
    end
    BridgeSetSetupBusy(false)
    BridgeSetStatus("MATCH ACTIVE", "Resumed the existing Forge match without resetting its checkpoint")
    BridgeUiMarkDirty("resume-active-session")
    return true
end

function BridgePressNewMatch(object, playerColor, altClick)
    local color = playerColor
    local alt = altClick == true
    BridgeSetupTrace("TTS_NEW_MATCH_CLICKED", "player=" .. tostring(color or "unknown") .. " confirmed=" .. tostring(alt))
    BridgeSetStatus("NEW MATCH", alt and "Preparing match..." or "Click again to confirm")
    BridgeLog("setup-click:new-match")
    BridgeWaitFrames(function()
        BridgeRunSetupProtected("new-match-click", function() BridgeDoPressNewMatch(color, alt) end)
    end, 1)
end

function BridgeDoPressNewMatch(playerColor, altClick)
    BridgeLog("setup-deferred:new-match")
    if BridgeState.setupBusy then
        BridgeShowError("Forge is still initializing; wait for the loading controls to finish")
        return
    end
    if not BridgeGuardLifecycleCommand("NEW_MATCH") then return end
    BridgeSetupStage("SETUP_STATE_VALIDATED", "new-match confirmation path ready")
    BridgeState.resetConfirmationArmed = true
    BridgeClearResetConfirmationControl()
    BridgeSpawnResetConfirmationControl()
    broadcastToAll("[Bridge] NEW MATCH is destructive. Click it again within 10 seconds to confirm.", {1.0, 0.55, 0.1})
    BridgeWaitTime(function()
        if BridgeState.resetConfirmationArmed then
            BridgeState.resetConfirmationArmed = false
            BridgeClearResetConfirmationControl()
        end
    end, 10)
end

function BridgeClearResetConfirmationControl()
    local guid = BridgeState.resetConfirmationGuid
    local object = BridgeGetLiveObjectByGuid(guid)
    if object ~= nil then
        BridgeSafeObjectCall(object, function(o) o.destruct() end)
    end
    BridgeState.resetConfirmationGuid = nil
    for _, candidate in _ip(_all()) do
        if BridgeObjectIsUsable(candidate) and BridgeSafeObjectName(candidate) == "Forge Confirm New Match" then
            BridgeSafeObjectCall(candidate, function(o) o.destruct() end)
        end
    end
end

function BridgeSpawnResetConfirmationControl()
    BridgeClearResetConfirmationControl()
    spawnObject({
        type = "BlockSquare",
        position = {10.8, 1.6, -15.0},
        scale = {2.7, 0.35, 1.25},
        callback_function = function(control)
            if not BridgeObjectIsUsable(control) then return end
            local guid = BridgeSafeObjectGuid(control)
            if guid == nil then return end
            BridgeState.resetConfirmationGuid = guid
            BridgeWaitFrames(function()
                local live = BridgeGetLiveObjectByGuid(guid)
                if live == nil then return end
                BridgeSafeObjectCall(live, function(o)
                    o.setName("Forge Confirm New Match")
                    o.setLock(true)
                    o.setColorTint({0.72, 0.12, 0.12})
                    o.setRotation({0, 180, 0})
                    o.createButton({
                        click_function = "BridgePressConfirmNewMatch",
                        function_owner = Global,
                        label = "CONFIRM\nNEW MATCH",
                        position = {0, 0.6, 0},
                        width = 950,
                        height = 420,
                        font_size = 120,
                        color = {0.72, 0.12, 0.12, 1.0},
                        font_color = {1, 1, 1, 1},
                        tooltip = "Confirm replacing the active Forge match"
                    })
                end)
                BridgeLog("setup-confirm-spawned")
            end, 1)
        end
    })
end

function BridgePressConfirmNewMatch(object, playerColor, altClick)
    local color = playerColor
    local alt = altClick == true
    BridgeLog("setup-click:confirm")
    BridgeWaitFrames(function()
        BridgeRunSetupProtected("new-match-confirm", function() BridgeDoPressConfirmNewMatch(color, alt) end)
    end, 1)
end

function BridgeDoPressConfirmNewMatch(playerColor, altClick)
    BridgeLog("setup-deferred:confirm")
    if BridgeState.setupBusy then
        BridgeShowError("Forge is still initializing; wait for the loading controls to finish")
        return
    end
    if not BridgeGuardLifecycleCommand("CONFIRM_NEW_MATCH") then return end
    if not BridgeState.resetConfirmationArmed then
        BridgeShowError("NEW MATCH confirmation expired; click NEW MATCH again")
        BridgeClearResetConfirmationControl()
        return
    end
    BridgeState.resetConfirmationArmed = false
    BridgeClearResetConfirmationControl()
    BridgeSetupStage("SETUP_STATE_VALIDATED", "confirmed new-match request")
    BridgeSetSetupBusy(true, "Replacing the Forge match; setup controls are temporarily disabled.")
    BridgeResetSession()
end

function BridgeAttachToActiveSession(done)
    BridgeGetHealth(function(ok, body, err)
        if not ok then
            BridgeClearHighlights()
            if done then done() end
            BridgeShowError("health failed: " .. tostring(err))
            return
        end

        BridgeLog("[Bridge] health ok. adapter=" .. tostring(body.adapter) .. " state=" .. tostring(body.adapterState))
        if body.adapterState == "starting" then
            BridgeWaitForForgeInitialization(1, done)
            return
        end
        if body.sessionId ~= nil and body.sessionId ~= "session-not-started"
            and body.adapterState ~= "failed" and body.adapterState ~= "not_started" then
            BridgeBootstrapWhenAvailable(body.sessionId, 1, function(bootstrapOk, bootstrapError)
                if bootstrapOk then
                    BridgeStartEventPolling(body.sessionId, true)
                    BridgeFetchDecisionAfterAttach()
                else
                    BridgeStopOnDesync(bootstrapError)
                end
                if done then done() end
            end)
            return
        end

        if body.adapterState == "not_started" or body.sessionId == nil
            or body.sessionId == "session-not-started" then
            BridgeCleanupLocalSession("attach-no-session", BRIDGE_LIFECYCLE_READY_NO_SESSION)
        else
            BridgeFetchDecisionAfterAttach()
        end
        if done then done() end
    end)
end

-- A Forge launch intentionally exposes state=starting before the first
-- structured snapshot is available.  This is normal (and can take 90s), not
-- a physical desynchronization.  Keep the setup controls busy and poll.
function BridgeWaitForForgeInitialization(attempt, done)
    if attempt > 75 then
        if done then done() end
        BridgeShowError("Forge initialization exceeded 150 seconds; inspect bridge logs")
        return
    end
    BridgeGetHealth(function(ok, body, err)
        if not ok then
            if done then done() end
            BridgeShowError("health failed while waiting for Forge: " .. tostring(err))
            return
        end
        if body.adapterState == "starting" then
            BridgeSetStatus("FORGE INITIALIZING", "Loading Forge card database (" .. tostring(attempt * 2) .. "s)")
            if attempt == 1 or attempt % 10 == 0 then
                BridgeLog("[Bridge] Forge is initializing... (" .. tostring(attempt * 2) .. "s)")
            end
            BridgeWaitTime(function() BridgeWaitForForgeInitialization(attempt + 1, done) end, 2)
            return
        end
        if body.adapterState == "failed" then
            BridgeSetStatus("ERROR", "Forge initialization failed")
            if done then done() end
            BridgeShowError("Forge failed during initialization; inspect bridge logs")
            return
        end
        BridgeAttachToActiveSession(done)
    end)
end

function BridgeFetchDecisionAfterAttach()
    local expectedSessionId = BridgeState.eventSessionId
    local presentationGeneration = BridgeState.decisionPresentationGeneration
    BridgeGetDecision(function(decisionOk, decisionBody, decisionErr)
        if expectedSessionId ~= BridgeState.eventSessionId
            or presentationGeneration ~= BridgeState.decisionPresentationGeneration then
            BridgeLog("[Bridge] ignored delayed decision fetch from a replaced Forge session")
            return
        end
        if decisionOk and decisionBody ~= nil then
            BridgeAcceptDecision(decisionBody, "attach_response", expectedSessionId, presentationGeneration)
            return
        end

        BridgeHideMainPriorityControls()
        BridgeLog("[Bridge] no active decision available (" .. tostring(decisionErr) .. "). This script will not restart Forge automatically.")
        BridgeLog("[Bridge] When Forge reaches a decision, run BridgeRefreshDecision().")
    end)
end

function BridgeRefreshDecision()
    BridgeResumeChoiceProtocol("manual_refresh")
    local expectedSessionId = BridgeState.eventSessionId
    local presentationGeneration = BridgeState.decisionPresentationGeneration
    BridgeGetDecision(function(ok, body, err)
        if expectedSessionId ~= BridgeState.eventSessionId
            or presentationGeneration ~= BridgeState.decisionPresentationGeneration then
            BridgeLog("[Bridge] ignored delayed decision refresh from a replaced Forge session")
            return
        end
        if ok and body ~= nil then
            BridgeAcceptDecision(body, "decision_refresh", expectedSessionId, presentationGeneration)
        else
            BridgeShowError("decision fetch failed: " .. tostring(err))
        end
    end)
end

function BridgeStartSessionIfNone(done)
    BridgeClearHighlights()
    BridgeState.lastDecision = nil

    BridgeSetupStage("READING_DECKS", "building Bridge deck inventory")
    BridgeTraceStart("START-07 TTS-library-deck-load")
    BridgeConfigureDecks(function(deckOk, _, deckError)
        if not deckOk then
            if done then done() end
            BridgeSetupFailure("deck-reading", BridgeHttpFailureDetail(_, deckError))
            BridgeShowError("TTS library load failed: " .. BridgeHttpFailureDetail(_, deckError))
            return
        end
        BridgeSetupTrace("SESSION_START_REQUEST_BEGIN", "POST /api/v1/session/start")
        BridgeSetupStage("STARTING_FORGE", "requesting Forge session")
        BridgeTraceStart("START-07 session-start-request")
        BridgeStartSession(function(ok, body, err)
        BridgeRunTraced("START-08 session-start-response", function()
            BridgeTraceStart("START-08 session-start-response", ok and tostring(body and body.sessionId or "ok") or tostring(err))
            if not ok then
                if done then done() end
                BridgeSetLifecycleState(BRIDGE_LIFECYCLE_START_FAILED, "session-start-failed")
                BridgeSetupFailure("session-start", BridgeHttpFailureDetail(body, err))
                BridgeShowError("session start failed: " .. BridgeHttpFailureDetail(body, err))
                return
            end

            BridgeLog("[Bridge] started or attached session: " .. tostring(body and body.sessionId))
            BridgeState.sessionCleanupApplied = false
            BridgeSetLifecycleState(BRIDGE_LIFECYCLE_ACTIVE, "session-started")
            -- The start route may attach to a match that already exists. Do not replay
            -- its historical physical events; an explicit reset is the new-match path.
            BridgeBootstrapWhenAvailable(body.sessionId, 1, function(bootstrapOk, bootstrapError)
                BridgeRunTraced("START bootstrap-callback", function()
                    if not bootstrapOk then if done then done() end; BridgeStopOnDesync(bootstrapError); return end
                    BridgeTraceStart("START-18 event-poll-start")
                    BridgeStartEventPolling(body.sessionId, true)
                    BridgeTraceStart("START-19 decision-poll-start")
                    if body ~= nil and body.currentDecision ~= nil then
                        BridgeAcceptDecision(body.currentDecision, "session_start_response", body.sessionId, BridgeState.decisionPresentationGeneration)
                    else
                        BridgeRefreshDecision()
                    end
                    BridgeTraceStart("START-20 ready")
                    if done then done() end
                end)
            end)
        end)
        end)
    end)
end

function BridgeResetSession()
    BridgeStopEventPolling("session-reset")
    BridgeClearHighlights()
    BridgeState.lastDecision = nil

    BridgeReturnPreviousGameCardsToLibraries(function(returnOk, returnError)
        if not returnOk then
            BridgeSetSetupBusy(false)
            BridgeShowError("previous game cleanup failed: " .. tostring(returnError))
            return
        end
        BridgeConfigureDecks(function(deckOk, _, deckError)
            if not deckOk then
                BridgeSetSetupBusy(false)
                BridgeShowError("TTS library load failed: " .. BridgeHttpFailureDetail(_, deckError))
                return
            end
            BridgeResetSessionRequest(function(ok, body, err)
        if not ok then
            BridgeSetSetupBusy(false)
            BridgeShowError("explicit session reset failed: " .. BridgeHttpFailureDetail(body, err))
            return
        end

        BridgeLog("[Bridge] active match explicitly replaced: " .. tostring(body and body.sessionId))
            BridgeState.sessionCleanupApplied = false
            BridgeSetLifecycleState(BRIDGE_LIFECYCLE_ACTIVE, "session-reset")
        BridgeBootstrapWhenAvailable(body.sessionId, 1, function(bootstrapOk, bootstrapError)
            if not bootstrapOk then BridgeSetSetupBusy(false); BridgeStopOnDesync(bootstrapError); return end
            -- The snapshot is authoritative through this point, so opening
            -- mutation records are acknowledged instead of replayed.
            BridgeStartEventPolling(body.sessionId, true)
            if body ~= nil and body.currentDecision ~= nil then
                BridgeAcceptDecision(body.currentDecision, "session_reset_response", body.sessionId, BridgeState.decisionPresentationGeneration)
            else
                BridgeRefreshDecision()
            end
            BridgeSetSetupBusy(false)
            end)
        end)
    end)
    end)
end

function BridgeSmokeTest()
    BridgeAttachToActiveSession()
end

function BridgeAcceptDecision(decision, origin, expectedSessionId, presentationGeneration)
    if decision == nil then
        BridgeLog("[Bridge] DECISION_REJECT origin=" .. tostring(origin) .. " reason=missing_payload")
        return
    end

    BridgeRecordDecisionLifecycle(decision, origin, "OBSERVED", "decision-payload")

    if expectedSessionId ~= nil and (expectedSessionId ~= BridgeState.eventSessionId
        or presentationGeneration ~= BridgeState.decisionPresentationGeneration) then
        BridgeRecordDecisionLifecycle(decision, origin, "REJECTED_STALE", "replaced-generation")
        BridgeLog("[Bridge] DECISION_REJECT origin=" .. tostring(origin) .. " reason=replaced_generation decision=" .. tostring(decision.decisionId))
        return
    end

    if decision.sessionId == nil or decision.sessionId ~= BridgeState.eventSessionId then
        BridgeRecordDecisionLifecycle(decision, origin, "REJECTED_STALE", "wrong-session")
        BridgeLog("[Bridge] DECISION_REJECT origin=" .. tostring(origin) .. " reason=wrong_session decision="
            .. tostring(decision.decisionId) .. " decisionSession=" .. tostring(decision.sessionId)
            .. " activeSession=" .. tostring(BridgeState.eventSessionId))
        return
    end

    if BridgeState.retiredChoiceDecisionIds[decision.decisionId] == true
        or BridgeState.choiceTransactions[decision.decisionId] ~= nil then
        BridgeRecordDecisionLifecycle(decision, origin, "REJECTED_STALE", "decision-retired-or-submitting")
        -- A delayed GET/render callback must never make a consumed decision
        -- actionable again. The next distinct Forge decision will retire the
        -- old transaction and render normally.
        if BridgeState.ui ~= nil and BridgeState.ui.creatureTypeDecisionId == decision.decisionId then
            BridgeCreatureTypeClearDraft("decision-retired")
        end
        if BridgeState.ui ~= nil and BridgeState.ui.graveyardFolderDecisionId == decision.decisionId then
            BridgeGraveyardClear("decision-retired")
        end
        if BridgeState.lastDecision == nil or BridgeState.lastDecision.decisionId == decision.decisionId then
            BridgeState.lastDecision = nil
            BridgeClearHighlights()
            BridgeHideMainPriorityControls()
        end
        return
    end

    if BridgeState.lastDecision == nil or BridgeState.lastDecision.decisionId ~= decision.decisionId then
        local previousDecision = BridgeState.lastDecision
        if previousDecision ~= nil and previousDecision.decisionId ~= decision.decisionId
            and previousDecision.kind == "main_priority"
            and previousDecision.seatId == "forge-player-1"
            and string.find(string.lower(tostring(previousDecision.phaseName or "")), "main", 1, true) ~= nil
            and decision.kind == "attacker_selection"
            and BridgeState.choiceTransactions[previousDecision.decisionId] == nil
            and BridgeState.retiredChoiceDecisionIds[previousDecision.decisionId] ~= true then
            BridgeRecordDecisionLifecycle(previousDecision, "main1", "RETIRED",
                "advanced-to-attacker-without-choice")
            BridgeLog(string.format(
                "[Bridge] MAIN1_ADVANCED_WITHOUT_BRIDGE_CHOICE previousDecision=%s newDecision=%s previousCursor=%s newCursor=%s eventCursorDelta=%s lastChoiceDecision=%s lastChoiceAction=%s lastChoiceSource=%s",
                tostring(previousDecision.decisionId), tostring(decision.decisionId),
                tostring(previousDecision.eventCursor), tostring(decision.eventCursor),
                tostring((tonumber(decision.eventCursor or 0) or 0) - (tonumber(previousDecision.eventCursor or 0) or 0)),
                tostring(BridgeState.lastChoiceAttempt and BridgeState.lastChoiceAttempt.decisionId or nil),
                tostring(BridgeState.lastChoiceAttempt and BridgeState.lastChoiceAttempt.actionId or nil),
                tostring(BridgeState.lastChoiceAttempt and BridgeState.lastChoiceAttempt.source or nil)))
        end
        BridgeCreatureTypeClearDraft("decision-replaced")
        BridgeGraveyardClear("decision-replaced")
        -- A card context is only a convenience filter for the decision in
        -- which it was opened. Retaining it after Forge changes decisions can
        -- hide newly drawn legal cards and the next Main 1 action list.
        if BridgeState.ui ~= nil then BridgeState.ui.contextInstanceId = nil end
    end

    BridgeRetireChoiceTransactionsForDecision(decision.decisionId)

    local ignoreStale, eventCursor, applied = BridgeShouldIgnoreStaleDecision(decision)
    if ignoreStale then
        BridgeRecordDecisionLifecycle(decision, origin, "REJECTED_STALE", "stale-event-cursor")
        BridgeLog(string.format(
            "[Bridge] ignoring stale decision %s kind=%s (cursor=%s, applied=%s)",
            tostring(decision.decisionId), tostring(decision.kind), tostring(eventCursor), tostring(applied)))
        -- A stale poll response is not a terminal state.  The GET that
        -- delivered it has already completed, so simply returning would
        -- leave the bridge with no current decision and Forge would continue
        -- advancing its priority windows.  Start a fresh poll against the
        -- current event/session generation; only that newer Forge decision
        -- may replace the stale one.
        -- If this was the menu currently rendered, retire it before polling;
        -- otherwise a newer menu is already authoritative and must remain.
        if BridgeState.lastDecision == nil
            or BridgeState.lastDecision.decisionId == decision.decisionId then
            BridgeState.lastDecision = nil
            BridgeClearHighlights()
            BridgeHideMainPriorityControls()
            BridgeStartDecisionPolling()
        end
        return
    end

    -- The producer must never turn Forge's private library inspection into a
    -- human-visible option. Fail safely before action rows, tooltips, or
    -- physical controls can expose an unapproved identity.
    if BridgeDecisionHasUnauthorizedPresentationAction(decision) then
        BridgeLog("[Bridge] stopped: Forge supplied an unapproved hidden-zone action")
        BridgeStopOnDesync("Forge supplied an unapproved hidden-zone action; presentation paused safely")
        return
    end

    local deferDecision, deferCursor, deferApplied, deferReason = BridgeShouldDeferDecision(decision)
    if deferDecision then
        BridgeRecordDecisionLifecycle(decision, origin,
            deferReason == "opening_hand_readiness" and "DEFERRED_HAND_READINESS" or "DEFERRED_CURSOR",
            deferReason)
        BridgeState.pendingDecision = decision
        -- A pending decision is not yet presentation-safe.  In particular, a
        -- post-draw menu can describe a card whose extraction from the
        -- library has not completed. Keeping it as lastDecision lets the HUD
        -- render those action rows even though physical interaction is gated.
        -- Keep the decision only in the private pending slot until the exact
        -- embodiment/event cursor gate releases it.
        BridgeState.lastDecision = nil
        BridgeState.pendingDecisionDeferredAt = os.clock()
        BridgeState.pendingDecisionDeferredCursor = deferCursor
        BridgeState.pendingDecisionDeferredApplied = deferApplied
        BridgeClearHighlights()
        BridgeResetSelectionState()
        BridgeHideMainPriorityControls()
        BridgeUiMarkDirty("decision-deferred")
        BridgeLog(string.format(
            "[Bridge] gating decision %s until events catch up (cursor=%s, applied=%s)",
            tostring(decision.decisionId), tostring(deferCursor), tostring(deferApplied)))
        if deferReason == "opening_hand_readiness" then
            BridgeScheduleOpeningHandReadinessRetry()
        end
        return
    end

    BridgeState.pendingDecision = nil
    BridgeState.pendingDecisionDeferredAt = nil
    BridgeState.pendingDecisionDeferredCursor = 0
    BridgeState.pendingDecisionDeferredApplied = 0

    if decision.turnNumber ~= nil and tonumber(decision.turnNumber) ~= nil and tonumber(decision.turnNumber) > 0 then
        BridgeState.tableTurnCount = tonumber(decision.turnNumber)
        BridgeRefreshTurnCounterLabels()
    end
    if decision.activeSeatId ~= nil then
        BridgeState.currentTurnSeatId = decision.activeSeatId
    end
    -- Phase transitions are authoritative events. Decision metadata is only a
    -- corroborating hint and must not overwrite the phase event stream. The
    -- initial decision may seed an otherwise-uninitialized display, but once
    -- any authoritative phase is known, a poll response can never move it.
    local decisionPhase = tostring(decision.phaseName or "")
    local decisionCursor = tonumber(decision.eventCursor or 0) or 0
    local appliedCursor = tonumber(BridgeState.lastAppliedEventSequence or 0) or 0
    if decisionPhase ~= "" and BridgeState.currentPhase == nil
        and (decisionCursor <= 0 or decisionCursor >= appliedCursor) then
        BridgeState.currentPhase = decisionPhase
    elseif decisionPhase ~= "" then
        BridgeLog(string.format("[Bridge] retaining event phase=%s over stale decision phase=%s cursor=%s applied=%s",
            tostring(BridgeState.currentPhase), decisionPhase, tostring(decisionCursor), tostring(appliedCursor)))
    end
    if decision.prioritySeatId ~= nil then
        BridgeState.prioritySeatId = decision.prioritySeatId
    end

    BridgeState.lastDecision = decision
    BridgeRecordDecisionLifecycle(decision, origin, "ACCEPTED", "authoritative-current")
    if BridgeCheckProjectionCoherence ~= nil then
        BridgeCheckProjectionCoherence(decision, "decision-accepted")
    end
    BridgeLog(string.format(
        "[Bridge] DECISION_ACCEPT origin=%s runtime=%s revision=%s epoch=%s session=%s decision=%s eventCursor=%s forgeSequence=%s presentationGeneration=%s",
        tostring(origin), tostring(BRIDGE_CLIENT_RUNTIME_ID), tostring(BRIDGE_SCRIPT_REVISION),
        tostring(BRIDGE_RUNTIME_EPOCH_LOCAL), tostring(BridgeState.eventSessionId), tostring(decision.decisionId),
        tostring(decision.eventCursor), tostring(decision.forgeSequence), tostring(BridgeState.decisionPresentationGeneration)))
    local seat = BRIDGE_SEATS[decision.seatId]
    local actor = seat and seat.ttsColor or decision.seatId
    if decision.kind == "attacker_selection" then
        BridgeSetStatus("DECLARE ATTACKERS", "Drag/select highlighted creatures into attack row\nDONE ATTACKING")
    elseif decision.kind == "blocker_selection" then
        local attackerLabel = decision.contextCardName and ("BLOCKING: " .. tostring(decision.contextCardName)) or "DECLARE BLOCKERS"
        BridgeSetStatus(attackerLabel, "Drag/select highlighted creatures into block row for this exact attacker\nDONE BLOCKING")
    elseif decision.kind == "blocker_assignment" then
        BridgeSetStatus("ASSIGN BLOCKERS", "Choose which attacker each blocker will block\nDONE ASSIGNING")
    elseif BridgeIsDiscardChoice(decision) then
        if decision.decisionCauseKind == "cleanup_hand_size" then
            BridgeSetStatus("DISCARD TO MAXIMUM HAND SIZE", "Choose " .. tostring(decision.minSelections or 1) .. " card(s) from your hand.")
        elseif decision.decisionCauseKind == "spell_or_ability" then
            BridgeSetStatus("DISCARD " .. tostring(decision.minSelections or 1) .. " CARD", "Caused by: " .. tostring(decision.sourceCardName or "Forge spell or ability"))
        else
            BridgeSetStatus("DISCARD", "Choose Forge's legal discard card(s), then CONFIRM.")
        end
    elseif decision.kind == "mulligan"
        and tostring(decision.mulliganStage or "") == "bottom_selection" then
        BridgeSetStatus("MULLIGAN — PUT CARD ON BOTTOM",
            "Choose " .. tostring(decision.minSelections or 1) .. " card(s) to put on the bottom of your library, then CONFIRM.")
    elseif decision.kind == "card_selection" then
        BridgeSetStatus("CHOOSE CARD", "Required Forge selection (this is not a cast action)")
    elseif decision.kind == "cost_selection" and tostring(decision.costKind or "") == "crew" then
        BridgeSetStatus("CREW", "Select Forge-provided creatures, then CONFIRM.")
    elseif decision.kind == "entity_selection" and tostring(decision.selectionKind or "") == "proliferate" then
        BridgeSetStatus("PROLIFERATE", "Select any Forge-provided permanents and/or players, then CONFIRM.")
    elseif decision.kind == "target_selection" or decision.kind == "defender_selection" then
        BridgeSetStatus("CHOOSE TARGET", BridgeTurnLabel() .. " - " .. tostring(actor) .. " priority")
    elseif decision.kind == "generic_numeric_selection" then
        BridgeSetStatus("CHOOSE OPTION", BridgeTurnLabel() .. " - " .. tostring(actor) .. " priority")
    elseif decision.kind == "creature_type_selection" then
        BridgeSetStatus("CHOOSE CREATURE TYPE", BridgeTurnLabel() .. " - " .. tostring(actor) .. " priority")
    else
        local priorityHeadline = decision.seatId == "forge-player-1" and "YOUR PRIORITY" or "OPPONENT PRIORITY"
        BridgeSetStatus(priorityHeadline, BridgeTurnLabel() .. " - " .. tostring(actor) .. " - " .. tostring(BridgeState.currentPhase or "Forge decision"))
    end
    BridgeRenderDecision(decision)
    BridgeRecordDecisionLifecycle(decision, origin, "RENDERED", "decision-accepted")

    BridgeLog("[Bridge] decision " .. tostring(decision.decisionId) .. " kind=" .. tostring(decision.kind))

    if decision.actions == nil then
        BridgeLog("[Bridge] no actions.")
        return
    end

    for index, action in ipairs(decision.actions) do
        local followup = action.requiresFollowup and "yes" or "no"
        BridgeLog(string.format("[Bridge]   %d. %s (%s) id=%s followup=%s", index, tostring(action.displayName), tostring(action.type), tostring(action.actionId), followup))
    end

    BridgeLog("[Bridge] use BridgeChoose('<actionId>') to submit an action.")
end

function BridgeNormalizeCardName(name)
    if name == nil then
        return ""
    end

    local normalized = string.lower(tostring(name))
    local lineBreak = string.find(normalized, "\n", 1, true)
    if lineBreak ~= nil then
        normalized = string.sub(normalized, 1, lineBreak - 1)
    end
    lineBreak = string.find(normalized, "\r", 1, true)
    if lineBreak ~= nil then
        normalized = string.sub(normalized, 1, lineBreak - 1)
    end
    local separator = string.find(normalized, " // ", 1, true)
    if separator ~= nil then
        normalized = string.sub(normalized, 1, separator - 1)
    end

    normalized = string.gsub(normalized, "^%s+", "")
    normalized = string.gsub(normalized, "%s+$", "")
    normalized = string.gsub(normalized, "%s+", " ")
    return normalized
end

function BridgeCardNameMatches(ttsName, forgeName)
    local normalizedTts = BridgeNormalizeCardName(ttsName)
    local normalizedForge = BridgeNormalizeCardName(forgeName)
    if normalizedTts == "" or normalizedForge == "" then
        return false
    end

    if normalizedTts == normalizedForge then
        return true
    end

    return string.sub(normalizedTts, 1, string.len(normalizedForge) + 1) == normalizedForge .. " "
end

function BridgeClearHighlights()
    -- Clearing is itself a presentation invalidation. This keeps a later
    -- render from being skipped after an event or interaction removed the
    -- currently rendered highlight set.
    BridgeAdvancePhysicalPresentationGeneration("highlights-cleared")
    local highlighted = BridgeState.highlightedGuids or {}
    for _, guid in _ip(highlighted) do
        local object = BridgeGetLiveObjectByGuid(guid)
        if object ~= nil then BridgeSafeObjectCall(object, function(o) o.highlightOff() end) end
    end

    local targetButtons = BridgeState.targetButtonIndexByGuid or {}
    for guid, buttonIndex in _pairs(targetButtons) do
        local object = BridgeGetLiveObjectByGuid(guid)
        if object ~= nil then
            BridgeSafeObjectCall(object, function(o)
                -- Verify button still exists before removal to avoid "Could not find matching button" errors.
                -- TTS button indices can shift if buttons are removed during rapid decision redraws.
                local buttons = o.getButtons() or {}
                for _, btn in ipairs(buttons) do
                    if btn.index == buttonIndex then
                        o.removeButton(buttonIndex)
                        return
                    end
                end
            end)
        end
    end

    BridgeState.highlightedGuids = {}
    BridgeState.actionByGuid = {}
    BridgeState.targetButtonIndexByGuid = {}
    for _, guid in ipairs(BridgeState.playerTargetControlGuids or {}) do
        local object = BridgeGetLiveObjectByGuid(guid)
        if object ~= nil then BridgeSafeObjectCall(object, function(o) o.destruct() end) end
    end
    BridgeState.playerTargetControlGuids = {}
    BridgeState.discardPresentation = nil
end

function BridgeApplyDiscardPresentation(decision)
    if decision == nil or decision.kind ~= "discard" then return end
    local cause = tostring(decision.decisionCauseKind or "")
    if cause == "spell_or_ability" and decision.sourceCardInstanceId ~= nil then
        local guid = BridgeState.physicalByInstanceId[decision.sourceCardInstanceId]
        local source = guid and BridgeGetLiveObjectByGuid(guid) or nil
        if source ~= nil then
            source.highlightOn({1.0, 0.25, 0.1})
            table.insert(BridgeState.highlightedGuids, guid)
            BridgeState.discardPresentation = {kind = cause, sourceGuid = guid}
        end
    elseif cause == "cleanup_hand_size" then
        -- A hand is a TTS zone, not a source card. Keep the warning in the
        -- world-space/HUD status rather than inventing a hostile card.
        BridgeState.discardPresentation = {kind = cause, seatId = decision.seatId}
    end
end

function BridgeClearOptionControls()
    local controls = BridgeState.optionControlGuids or {}
    for i = 1, #controls do
        local object = BridgeGetLiveObjectByGuid(controls[i])
        if object ~= nil then BridgeSafeObjectCall(object, function(o) o.destruct() end) end
    end
    BridgeState.optionControlGuids = {}
    BridgeState.optionControlDecisionId = nil
end

function BridgeDecisionOptionLabel(action, index, decision)
    if action.type == "choose_none" and decision ~= nil and decision.confirmRequired == true then
        return string.format("DONE / CONFIRM\nSelected %d / %d",
            tonumber(decision.selectedCount or 0), tonumber(decision.maxSelections or 0))
    end
    local text = tostring(action.displayName or action.type or ("Option " .. tostring(index)))
    if #text > 34 then text = text:sub(1, 31) .. "..." end
    return "CHOOSE\n" .. text
end

function BridgeEnsureDecisionOptionControls(decision, representedActionIds)
    if BridgeState.ui ~= nil and BridgeState.ui.mounted then
        BridgeClearOptionControls()
        return
    end
    if decision == nil or decision.actions == nil then
        BridgeClearOptionControls()
        return
    end

    local unbound = {}
    local filters = representedActionIds or {}
    for _, action in _ip(decision.actions or {}) do
        local skip = not BridgeActionPresentationAuthorized(action)
        if skip then BridgeLog("[Bridge] suppressed unauthorized hidden-zone option control") end
        if not skip then skip = filters[action.actionId] == true end
        if not skip and decision.kind == "main_priority" and action.type == "pass_priority" then
            skip = true
        end
        if not skip and (action.type == "finish_attacking" or action.type == "finish_blocking") then
            skip = true
        end
        if not skip then table.insert(unbound, action) end
    end

    if #unbound == 0 then
        BridgeClearOptionControls()
        return
    end
-- END GENERATED SOURCE: 20-ui-decisions.lua
-- BEGIN GENERATED SOURCE: 25-revealed-cards.lua
-- Read-only projection of structured Forge reveal payloads. This surface is
-- separate from zones, decisions, combat highlights, and the event cursor.
BRIDGE_REVEAL_SURFACE_SLOTS = 6

local function BridgeRevealUiDirty(reason)
    local ui = BridgeState.ui
    if ui ~= nil then
        ui.dirty = true
        ui.dirtyReason = reason
        if not ui.flushScheduled and BridgeWaitFrames ~= nil then
            ui.flushScheduled = true
            BridgeWaitFrames(function()
                ui.flushScheduled = false
                if BridgeUiFlush ~= nil then BridgeUiFlush() end
            end, 1)
        end
    end
end

local function BridgeRevealKey(presentation, eventSequence)
    return tostring(presentation.presentationId or "") .. "@" .. tostring(eventSequence or presentation.originatingEventSequence or 0)
end

function BridgeRevealViewerMaySee(presentation)
    local visibility = string.lower(tostring(presentation.visibility or "public"))
    if visibility == "public" then return true end
    for _, seatId in ipairs(presentation.entitledViewerSeatIds or {}) do
        if seatId == "forge-player-1" then return true end
    end
    return false
end

function BridgeRevealCardArt(entry)
    if BridgeResolveCanonicalCardArt ~= nil then
        local ok, image = pcall(BridgeResolveCanonicalCardArt, entry.cardFaceIdentity, entry.cardName)
        if ok and image ~= nil and tostring(image) ~= "" then return tostring(image) end
    end
    return entry.imageUrl or entry.image or nil
end

function BridgeApplyRevealPresentation(presentation, appliedEventSequence)
    if presentation == nil or not BridgeRevealViewerMaySee(presentation) then return false end
    local sequence = tonumber(appliedEventSequence or presentation.originatingEventSequence or 0) or 0
    if sequence > (tonumber(BridgeState.lastAppliedEventSequence or 0) or 0) then return false end
    local key = BridgeRevealKey(presentation, sequence)
    if BridgeState.dismissedRevealKeys[key] == true then return false end
    local lifecycle = string.lower(tostring(presentation.lifecycle or "opened"))
    if lifecycle == "resolved" or lifecycle == "dismissed" then
        BridgeState.dismissedRevealKeys[key] = true
        if BridgeState.activeRevealPresentationKey == key then BridgeState.activeRevealPresentationKey = nil end
        BridgeRevealUiDirty("reveal-closed")
        return true
    end
    if BridgeState.revealedPresentationsByKey[key] == nil then table.insert(BridgeState.revealedPresentationOrder, key) end
    BridgeState.revealedPresentationsByKey[key] = presentation
    BridgeState.activeRevealPresentationKey = key
    BridgeState.revealSurfaceOffset = 1
    BridgeRevealUiDirty("reveal-updated")
    return true
end

function BridgeResolveRevealForDecision(decision)
    local key = BridgeState.activeRevealPresentationKey
    local presentation = key and BridgeState.revealedPresentationsByKey[key] or nil
    if presentation == nil or presentation.associatedDecisionId == nil then return end
    if decision == nil or decision.decisionId ~= presentation.associatedDecisionId then
        BridgeState.dismissedRevealKeys[key] = true
        BridgeState.revealedPresentationsByKey[key] = nil
        BridgeState.activeRevealPresentationKey = nil
        BridgeRevealUiDirty("reveal-decision-ended")
    end
end

function BridgeRestoreAuthoritativeReveals(snapshot)
    for _, presentation in ipairs(snapshot and (snapshot.activeRevealPresentations or snapshot.revealPresentations) or {}) do
        local sequence = tonumber(presentation.originatingEventSequence or 0) or 0
        if string.lower(tostring(presentation.lifecycle or "opened")) == "opened"
            and sequence <= (tonumber(BridgeState.lastAppliedEventSequence or 0) or 0) then
            BridgeApplyRevealPresentation(presentation, sequence)
        end
    end
end

function BridgeHudRevealScroll(player, value, id)
    local key = BridgeState.activeRevealPresentationKey
    local presentation = key and BridgeState.revealedPresentationsByKey[key] or nil
    if presentation == nil then return end
    local maxOffset = math.max(1, #(presentation.cards or {}) - BRIDGE_REVEAL_SURFACE_SLOTS + 1)
    local offset = tonumber(BridgeState.revealSurfaceOffset or 1) or 1
    if tostring(id or "") == "BridgeHudRevealPrev" then offset = offset - 1 else offset = offset + 1 end
    BridgeState.revealSurfaceOffset = math.min(math.max(offset, 1), maxOffset)
    BridgeRevealUiDirty("reveal-scroll")
end

function BridgeHudRevealClose(player, value, id)
    local key = BridgeState.activeRevealPresentationKey
    local presentation = key and BridgeState.revealedPresentationsByKey[key] or nil
    if presentation == nil then return end
    if presentation.associatedDecisionId ~= nil then return end
    BridgeState.dismissedRevealKeys[key] = true
    BridgeState.revealedPresentationsByKey[key] = nil
    BridgeState.activeRevealPresentationKey = nil
    BridgeRevealUiDirty("reveal-dismissed")
end

function BridgeRenderRevealSurface()
    local key = BridgeState.activeRevealPresentationKey
    local presentation = key and BridgeState.revealedPresentationsByKey[key] or nil
    local visible = presentation ~= nil and BridgeRevealViewerMaySee(presentation)
    BridgeUiSet("BridgeHudRevealSurface", "active", visible and "true" or "false")
    if not visible then return end
    local cards = presentation.cards or {}
    local offset = tonumber(BridgeState.revealSurfaceOffset or 1) or 1
    local maxOffset = math.max(1, #cards - BRIDGE_REVEAL_SURFACE_SLOTS + 1)
    offset = math.min(math.max(offset, 1), maxOffset)
    BridgeState.revealSurfaceOffset = offset
    BridgeUiSet("BridgeHudRevealHeading", "text", "REVEALED CARDS (" .. tostring(#cards) .. ")")
    BridgeUiSet("BridgeHudRevealReason", "text", tostring(presentation.reason or presentation.sourceName or ""))
    local endIndex = math.min(#cards, offset + BRIDGE_REVEAL_SURFACE_SLOTS - 1)
    for slot = 1, BRIDGE_REVEAL_SURFACE_SLOTS do
        local entry = cards[offset + slot - 1]
        local image = entry and BridgeRevealCardArt(entry) or nil
        BridgeUiSet("BridgeHudRevealCard" .. tostring(slot), "active", entry ~= nil and "true" or "false")
        BridgeUiSet("BridgeHudRevealImage" .. tostring(slot), "active", image ~= nil and "true" or "false")
        BridgeUiSet("BridgeHudRevealImage" .. tostring(slot), "image", image or "")
        BridgeUiSet("BridgeHudRevealFallback" .. tostring(slot), "active", entry ~= nil and image == nil and "true" or "false")
        BridgeUiSet("BridgeHudRevealFallback" .. tostring(slot), "text", entry and tostring(entry.cardName or "Revealed card") or "")
        BridgeUiSet("BridgeHudRevealCard" .. tostring(slot), "tooltip", entry and tostring(entry.cardName or "Revealed card") or "")
    end
    BridgeUiSet("BridgeHudRevealPrev", "active", offset > 1 and "true" or "false")
    BridgeUiSet("BridgeHudRevealNext", "active", endIndex < #cards and "true" or "false")
    BridgeUiSet("BridgeHudRevealCount", "text", #cards > BRIDGE_REVEAL_SURFACE_SLOTS
        and (tostring(offset) .. "-" .. tostring(endIndex) .. " / " .. tostring(#cards)) or "")
    BridgeUiSet("BridgeHudRevealClose", "active", presentation.associatedDecisionId == nil and "true" or "false")
    BridgeUiSet("BridgeHudRevealClose", "text", presentation.acknowledgmentRequired == true and "ACKNOWLEDGE" or "CLOSE")
end
-- END GENERATED SOURCE: 25-revealed-cards.lua
-- BEGIN GENERATED SOURCE: 30-input-identity.lua

    if BridgeState.optionControlDecisionId == decision.decisionId and #BridgeState.optionControlGuids == #unbound then
        return
    end

    BridgeClearOptionControls()
    BridgeState.optionControlDecisionId = decision.decisionId

    local seat = BRIDGE_SEATS[decision.seatId]
    local sideZ = seat and seat.tableSideZ or -1
    for index, action in _ip(unbound) do
        local column = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        local x = 9.5 + (column * 4.1)
        local z = sideZ * (7.5 + row * 2.0)
        _spawn({
            type = "BlockSquare",
            position = {x, 1.6, z},
            scale = {3.8, 0.35, 1.25},
            callback_function = function(object)
                object.setName("Forge Decision Option " .. tostring(index))
                object.setLock(true)
                object.setColorTint({0.38, 0.24, 0.62})
                object.setRotation({0, sideZ < 0 and 180 or 0, 0})
                object.createButton({
                    click_function = "BridgeChooseDecisionOption",
                    function_owner = Global,
                    label = BridgeDecisionOptionLabel(action, index, decision),
                    position = {0, 0.6, 0},
                    width = 1320,
                    height = 460,
                    font_size = 100,
                    color = {0.38, 0.24, 0.62, 1},
                    font_color = {1, 1, 1, 1},
                    tooltip = "Submit Forge option: " .. tostring(action.displayName or action.type)
                })
                object.setVar("bridgeDecisionId", decision.decisionId)
                object.setVar("bridgeActionId", action.actionId)
                table.insert(BridgeState.optionControlGuids, object.getGUID())
            end
        })
    end
end

function BridgeChooseDecisionOption(object, playerColor, altClick)
    -- Guard against dead object parameter from stale embedded button callbacks
    if object ~= nil then
        local ok = pcall(function() return object.getGUID() end)
        if not ok then return end
    end
    if object == nil or BridgeState.submitting then return end
    local decision = BridgeState.lastDecision
    local decisionId = object.getVar("bridgeDecisionId")
    local actionId = object.getVar("bridgeActionId")
    if decision == nil or decision.decisionId ~= decisionId then
        BridgeShowError("decision option control is stale")
        BridgeClearOptionControls()
        return
    end
    BridgeClaimHumanTtsColor(decision.seatId, playerColor)
    local action = nil
    for _, candidate in ipairs(decision.actions or {}) do
        if candidate.actionId == actionId then action = candidate; break end
    end
    if action ~= nil and action.type == "choose_none" and not BridgeCanSubmitStructuredDone(decision, "physical_option_done") then
        return
    end
    BridgeClearHighlights()
    BridgeResetSelectionState()
    BridgeSubmitChoice(decisionId, actionId, "generic_option_control")
end

function BridgeEnsureContextualCompletionControl(decision)
    if decision == nil or (decision.kind ~= "attacker_selection" and decision.kind ~= "blocker_selection" and decision.kind ~= "blocker_assignment") then return end
    local completionAction = nil
    for _, action in ipairs(decision.actions or {}) do
        if action.type == "finish_attacking" or action.type == "finish_blocking" or action.type == "choose_none" then
            completionAction = action
            break
        end
    end
    if completionAction == nil then return end
    if #(BridgeState.selectionControlGuids or {}) > 0 then
        if BridgeState.selectionControlDecisionId == decision.decisionId
            and BridgeState.selectionControlActionId == completionAction.actionId then
            return
        end
        for _, guid in ipairs(BridgeState.selectionControlGuids) do
            local stale = BridgeGetLiveObjectByGuid(guid)
            if stale ~= nil then BridgeSafeObjectCall(stale, function(o) o.destruct() end) end
        end
        BridgeState.selectionControlGuids = {}
    end
    local seat = BRIDGE_SEATS[decision.seatId]
    if seat == nil then return end
    local isAttacking = completionAction.type == "finish_attacking"
    local label = isAttacking and "DONE ATTACKING\n(NO MORE ATTACKERS)" or "DONE BLOCKING\n(NO MORE BLOCKERS)"
    BridgeState.selectionControlDecisionId = decision.decisionId
    BridgeState.selectionControlActionId = completionAction.actionId
    spawnObject({
        type = "BlockSquare",
        position = {-2.0, 1.6, seat.tableSideZ * 10.0},
        scale = {4.0, 0.35, 1.45},
        callback_function = function(object)
            if BridgeState.lastDecision == nil
                or BridgeState.lastDecision.decisionId ~= decision.decisionId
                or BridgeState.selectionControlDecisionId ~= decision.decisionId
                or BridgeState.selectionControlActionId ~= completionAction.actionId then
                if object ~= nil then BridgeSafeObjectCall(object, function(o) o.destruct() end) end
                return
            end
            object.setName("Forge Combat Completion " .. tostring(decision.decisionId))
            object.setLock(true)
            local color = isAttacking and {0.76, 0.3, 0.08} or {0.14, 0.42, 0.72}
            object.setColorTint(color)
            object.setRotation({0, seat.tableSideZ < 0 and 180 or 0, 0})
            object.createButton({
                click_function = "BridgeCompleteCombatSelection",
                function_owner = Global,
                label = label,
                position = {0, 0.6, 0},
                width = 1450,
                height = 480,
                font_size = 130,
                color = color,
                font_color = {1, 1, 1, 1},
                tooltip = "Submit Forge's explicit no-further-selection action"
            })
            object.setVar("bridgeDecisionId", decision.decisionId)
            object.setVar("bridgeActionId", completionAction.actionId)
            table.insert(BridgeState.selectionControlGuids, object.getGUID())
        end
    })
end

function BridgeCompleteCombatSelection(object, playerColor, altClick)
    -- Guard against dead object parameter from stale embedded button callbacks
    if object ~= nil then
        local ok = pcall(function() return object.getGUID() end)
        if not ok then return end
    end
    if object == nil or BridgeState.submitting then return end
    local decision = BridgeState.lastDecision
    local decisionId = object.getVar("bridgeDecisionId")
    local actionId = object.getVar("bridgeActionId")
    if decision == nil or decision.decisionId ~= decisionId then
        BridgeShowError("combat completion control is stale")
        BridgeResetSelectionState()
        return
    end
    local currentAction = nil
    for _, candidate in ipairs(decision.actions or {}) do
        if candidate.actionId == actionId
            and (candidate.type == "finish_attacking" or candidate.type == "finish_blocking" or candidate.type == "choose_none") then
            currentAction = candidate
            break
        end
    end
    if currentAction == nil then
        BridgeShowError("combat completion action is stale; waiting for Forge redraw")
        BridgeResetSelectionState()
        return
    end
    BridgeClaimHumanTtsColor(decision.seatId, playerColor)
    BridgeClearHighlights()
    BridgeResetSelectionState()
    BridgeSubmitChoice(decisionId, currentAction.actionId, "contextual_done")
end

function BridgeInstallTargetButton(object, targetSeatId)
    if object == nil then return end
    local nextIndex = 0
    for _, button in ipairs(object.getButtons and object.getButtons() or {}) do
        nextIndex = math.max(nextIndex, (button.index or -1) + 1)
    end
    object.createButton({
        click_function = "BridgeSelectPlayerTarget",
        function_owner = Global,
        label = "TARGET\n" .. tostring((BRIDGE_SEATS[targetSeatId] or {}).ttsColor or targetSeatId),
        position = {0, 0.35, 0},
        width = 520,
        height = 260,
        font_size = 90,
        color = {1.0, 0.55, 0.0, 0.35},
        font_color = {0.1, 0.1, 0.1, 1.0},
        tooltip = "Choose this player as the Forge target"
    })
    BridgeState.targetButtonIndexByGuid[object.getGUID()] = nextIndex
end

function BridgeSpawnPlayerTargetControl(targetObject, targetSeatId, decision, action)
    if targetObject == nil or decision == nil or action == nil then return end
    local targetPosition = targetObject.getPosition()
    local targetSeat = BRIDGE_SEATS[targetSeatId]
    spawnObject({
        type = "BlockSquare",
        position = {x = targetPosition.x, y = targetPosition.y + 1.1, z = targetPosition.z},
        scale = {1.65, 0.22, 0.90},
        callback_function = function(control)
            if control == nil then return end
            if BridgeState.lastDecision == nil or BridgeState.lastDecision.decisionId ~= decision.decisionId then
                control.destruct()
                return
            end
            control.setName("Forge Player Target")
            control.setLock(true)
            control.setColorTint({1.0, 0.55, 0.0})
            control.setRotation({0, targetSeat and targetSeat.tableSideZ < 0 and 180 or 0, 0})
            control.setVar("bridgeDecisionId", decision.decisionId)
            control.setVar("bridgeActionId", action.actionId)
            control.createButton({
                click_function = "BridgeSelectPlayerTargetControl",
                function_owner = Global,
                label = "TARGET\n" .. tostring(targetSeat and targetSeat.ttsColor or targetSeatId),
                position = {0, 0.45, 0},
                width = 1000,
                height = 420,
                font_size = 140,
                color = {1.0, 0.55, 0.0, 1.0},
                font_color = {0.08, 0.08, 0.08, 1.0},
                tooltip = "Choose this player as the Forge target"
            })
            table.insert(BridgeState.playerTargetControlGuids, control.getGUID())
        end
    })
end

function BridgeSelectPlayerTargetControl(object, playerColor, altClick)
    if object == nil or BridgeState.submitting then return end
    local decision = BridgeState.lastDecision
    local decisionId = object.getVar("bridgeDecisionId")
    local actionId = object.getVar("bridgeActionId")
    if decision == nil or decision.decisionId ~= decisionId or actionId == nil then
        BridgeShowError("player target control is stale")
        return
    end
    local actorSeat = BRIDGE_SEATS[decision.seatId]
    if actorSeat ~= nil and actorSeat.ttsColor ~= playerColor then
        BridgeShowError("this target decision belongs to TTS color " .. tostring(actorSeat.ttsColor))
        return
    end
    BridgeClaimHumanTtsColor(decision.seatId, playerColor)
    BridgeClearHighlights()
    local source = BridgeIsStructuredForgeToggleChoice(decision)
        and "physical_player_structured_toggle" or "player_target_control"
    BridgeSubmitChoice(decisionId, actionId, source)
end

function BridgeEnsureEndTurnButton(seatId)
    local existingGuid = BridgeState.endTurnObjectGuidBySeatId[seatId]
    local existing = BridgeGetLiveObjectByGuid(existingGuid)
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then return end
    local targetPosition = {-11.0, 1.6, seat.tableSideZ * 4.2}
    if existing == nil then
        existing = BridgeFindNamedObject("Forge End Turn")
        if existing ~= nil then
            BridgeState.endTurnObjectGuidBySeatId[seatId] = existing.getGUID()
        end
    end
    if existing ~= nil then
        existing.setLock(true)
        existing.setRotation({0, seat.tableSideZ < 0 and 180 or 0, 0})
        existing.setPositionSmooth(targetPosition, false, true)
        return
    end
    spawnObject({
        type = "BlockSquare",
        position = targetPosition,
        scale = {3.2, 0.35, 1.6},
        callback_function = function(object)
            object.setName("Forge End Turn")
            object.setLock(true)
            object.setColorTint({0.12, 0.3, 0.62})
            object.setRotation({0, seat.tableSideZ < 0 and 180 or 0, 0})
            object.createButton({
                click_function = "BridgePressEndTurn",
                function_owner = Global,
                label = "END TURN\n(YIELD)",
                position = {0, 0.6, 0},
                width = 1100,
                height = 520,
                font_size = 170,
                color = {0.15, 0.35, 0.65, 1.0},
                font_color = {1.0, 1.0, 1.0, 1.0},
                tooltip = "Yield Forge priority for the rest of this turn"
            })
            BridgeState.endTurnObjectGuidBySeatId[seatId] = object.getGUID()
        end
    })
end

function BridgeEnsurePassButton(seatId)
    local existingGuid = BridgeState.passObjectGuidBySeatId[seatId]
    local existing = BridgeGetLiveObjectByGuid(existingGuid)
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then return end
    local targetPosition = {-6.8, 1.6, seat.tableSideZ * 4.2}
    if existing == nil then
        existing = BridgeFindNamedObject("Forge Pass Priority")
        if existing ~= nil then
            BridgeState.passObjectGuidBySeatId[seatId] = existing.getGUID()
        end
    end
    if existing ~= nil then
        existing.setLock(true)
        existing.setRotation({0, seat.tableSideZ < 0 and 180 or 0, 0})
        existing.setPositionSmooth(targetPosition, false, true)
        return
    end
    spawnObject({
        type = "BlockSquare",
        position = targetPosition,
        scale = {2.7, 0.35, 1.6},
        callback_function = function(object)
            object.setName("Forge Pass Priority")
            object.setLock(true)
            object.setColorTint({0.22, 0.5, 0.56})
            object.setRotation({0, seat.tableSideZ < 0 and 180 or 0, 0})
            object.createButton({
                click_function = "BridgePressPass",
                function_owner = Global,
                label = "PASS /\nCONTINUE",
                position = {0, 0.6, 0},
                width = 1000,
                height = 520,
                font_size = 160,
                color = {0.22, 0.5, 0.56, 1.0},
                font_color = {1, 1, 1, 1},
                tooltip = "Pass exactly this Forge priority decision"
            })
            BridgeState.passObjectGuidBySeatId[seatId] = object.getGUID()
        end
    })
end

function BridgePressPass(object, playerColor, altClick)
    -- Guard against dead object parameter from stale embedded button callbacks
    if object ~= nil then
        local ok = pcall(function() return object.getGUID() end)
        if not ok then return end
    end
    if BridgeState.submitting then return end
    local decision = BridgeState.lastDecision
    if decision == nil and BridgeState.pendingDecision ~= nil then
        BridgeTryPresentPendingDecision("manual-pass")
        decision = BridgeState.lastDecision
    end
    if decision == nil or decision.kind ~= "main_priority" then
        BridgeHideMainPriorityControls()
        BridgeShowError("Pass is unavailable while waiting for a Forge main-priority decision")
        return
    end
    BridgeClaimHumanTtsColor(decision.seatId, playerColor)
    for _, action in ipairs(decision.actions or {}) do
        if action.type == "pass_priority" then
            BridgeClearHighlights()
            BridgeSubmitChoice(decision.decisionId, action.actionId, "pass_button")
            return
        end
    end
    BridgeShowError("Forge did not offer a one-shot pass action")
end

function BridgePressEndTurn(object, playerColor, altClick)
    -- Guard against dead object parameter from stale embedded button callbacks
    if object ~= nil then
        local ok = pcall(function() return object.getGUID() end)
        if not ok then return end
    end
    if BridgeState.submitting then return end
    local decision = BridgeState.lastDecision
    if decision == nil and BridgeState.pendingDecision ~= nil then
        BridgeTryPresentPendingDecision("manual-yield")
        decision = BridgeState.lastDecision
    end
    BridgeArmYieldPolicy(BridgeState.currentTurnSeatId, decision == nil and "physical-yield-no-decision" or "physical-yield")
    if decision ~= nil then BridgeRenderDecision(decision, true) end
end

function BridgeClaimHumanTtsColor(seatId, playerColor)
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil or seat.animateAuthoritativeEvents ~= false or playerColor == nil then return end

    -- Screen-space XML callbacks use LuaPlayer rather than a real TTS player
    -- color. It is not a valid Player[...] key and must never replace the
    -- configured physical-seat binding used for hands and card embodiment.
    if playerColor == "LuaPlayer" then
        BridgeLog("[Bridge] ignoring synthetic UI callback color for seat " .. tostring(seatId))
        return
    end

    local playerOk, player = pcall(function() return Player[playerColor] end)
    if not playerOk or player == nil then
        BridgeLog("[Bridge] ignoring unavailable TTS player color " .. tostring(playerColor)
            .. " for seat " .. tostring(seatId))
        return
    end

    -- A started match has already mapped hands and physical objects to its
    -- configured table seat. Do not let a later callback reassign that seat.
    if BridgeState.eventSessionId ~= nil and seat.ttsColor ~= playerColor then
        BridgeLog("[Bridge] ignoring attempted active-match seat-color rebind for " .. tostring(seatId)
            .. ": " .. tostring(seat.ttsColor) .. " -> " .. tostring(playerColor))
        return
    end

    if seat.ttsColor ~= playerColor then
        BridgeLog("[Bridge] bound human seat " .. tostring(seatId) .. " to TTS color " .. tostring(playerColor))
        seat.ttsColor = playerColor
    end
end

function BridgeSelectPlayerTarget(object, playerColor, altClick)
    -- Guard against dead object parameter from stale embedded button callbacks
    if object ~= nil then
        local ok = pcall(function() return object.getGUID() end)
        if not ok then return end
    end
    if object == nil or BridgeState.submitting then return end
    local action = BridgeState.actionByGuid[object.getGUID()]
    local decision = BridgeState.lastDecision
    if action == nil or action.targetKind ~= "player" or decision == nil then
        BridgeShowError("player target surface is stale")
        return
    end
    local actorSeat = BRIDGE_SEATS[decision.seatId]
    if actorSeat ~= nil and actorSeat.ttsColor ~= playerColor then
        BridgeShowError("this target decision belongs to TTS color " .. tostring(actorSeat.ttsColor))
        return
    end
    if BridgeIsStructuredForgeToggleChoice(decision) then
        BridgeSubmitChoice(decision.decisionId, action.actionId, "physical_player_structured_toggle")
        return
    end
    BridgeSubmitChoice(decision.decisionId, action.actionId, "player_target_surface")
end

function BridgeResetSelectionState()
    BridgeState.selectedActionIds = {}
    BridgeState.selectedGuidByActionId = {}
    BridgeState.selectionDecisionId = nil
    for _, guid in ipairs(BridgeState.selectionControlGuids or {}) do
        local object = BridgeGetLiveObjectByGuid(guid)
        if object ~= nil then BridgeSafeObjectCall(object, function(o) o.destruct() end) end
    end
    BridgeState.selectionControlGuids = {}
    BridgeState.selectionControlDecisionId = nil
    BridgeState.selectionControlActionId = nil
    BridgeClearOptionControls()
    BridgeClearPendingIntentControls()
    BridgeUiMarkDirty("selection-reset")
end

function BridgeClearPendingIntentControls()
    for _, guid in ipairs(BridgeState.pendingIntentControlGuids or {}) do
        local object = BridgeGetLiveObjectByGuid(guid)
        if object ~= nil then BridgeSafeObjectCall(object, function(o) o.destruct() end) end
    end
    BridgeState.pendingIntentControlGuids = {}
end

function BridgeEnsureCastPreviewControls(intent)
    if intent == nil or intent.action == nil or intent.action.type ~= "cast_spell" then return end
    if #(BridgeState.pendingIntentControlGuids or {}) > 0 then return end
    BridgeUiMarkDirty("cast-preview")
    local seat = BRIDGE_SEATS[intent.seatId]
    if seat == nil then return end
    local function spawnControl(name, label, x, color, callback)
        spawnObject({
            type = "BlockSquare",
            position = {x = x, y = 1.6, z = seat.tableSideZ * 10.0},
            scale = {2.7, 0.35, 1.4},
            callback_function = function(control)
                if control == nil then return end
                control.setName(name)
                control.setLock(true)
                control.setColorTint(color)
                control.setRotation({0, seat.tableSideZ < 0 and 180 or 0, 0})
                control.createButton({
                    click_function = callback,
                    function_owner = Global,
                    label = label,
                    position = {0, 0.6, 0},
                    width = 1050,
                    height = 460,
                    font_size = 145,
                    color = color,
                    font_color = {1, 1, 1, 1}
                })
                table.insert(BridgeState.pendingIntentControlGuids, control.getGUID())
            end
        })
    end
    spawnControl("Forge Confirm Cast", "CAST /\nCONFIRM", -0.5, {0.12, 0.52, 0.24}, "BridgeConfirmCastPreview")
    spawnControl("Forge Cancel Cast", "CANCEL /\nRETURN", 5.5, {0.65, 0.2, 0.12}, "BridgeCancelCastPreview")
end

function BridgeConfirmCastPreview(object, playerColor, altClick)
    local intent = BridgeState.pendingIntent
    local decision = BridgeState.lastDecision
    if intent == nil or decision == nil or decision.decisionId ~= intent.decisionId then
        BridgeClearPendingIntentControls()
        BridgeShowError("cast preview is stale")
        return
    end
    BridgeClaimHumanTtsColor(intent.seatId, playerColor)
    BridgeClearPendingIntentControls()
    BridgeUiMarkDirty("cast-preview-confirm")
    BridgeSubmitChoice(intent.decisionId, intent.action.actionId, "cast_confirm")
end

function BridgeCancelCastPreview(object, playerColor, altClick)
    local decision = BridgeState.lastDecision
    BridgeClearPendingIntentControls()
    BridgeRollbackPendingIntent()
    BridgeUiMarkDirty("cast-preview-cancel")
    if decision ~= nil then BridgeRenderDecision(decision) end
end

function BridgeSelectionCount()
    local count = 0
    for _, selected in pairs(BridgeState.selectedActionIds or {}) do
        if selected then count = count + 1 end
    end
    return count
end

-- Forge's numeric chooser accepts one card number at a time and then prints a
-- new authoritative menu. Keep the local draft to one card so CONFIRM always
-- advances rather than leaving an unsubmitable multi-card selection.
function BridgeToggleSingleSelection(decision, actionId, guid)
    if decision == nil or actionId == nil then return false end
    local selected = BridgeState.selectedActionIds[actionId] == true
    if not selected and BridgeSelectionCount() >= 1 then
        BridgeShowError("choose one card, confirm it, then Forge will request any remaining cards")
        return false
    end
    BridgeState.selectedActionIds[actionId] = not selected
    BridgeState.selectedGuidByActionId[actionId] = selected and nil or guid
    BridgeState.selectionDecisionId = decision.decisionId
    BridgeLog("[Bridge] staged Forge selection decision=" .. tostring(decision.decisionId)
        .. " action=" .. tostring(actionId) .. " selected=" .. tostring(not selected))
    return true
end

function BridgeEnsureSelectionControls(decision)
    if BridgeState.ui ~= nil and BridgeState.ui.mounted then return end
    -- Combat declarations have an explicit Forge finish action and their own
    -- contextual DONE ATTACKING/DONE BLOCKING control. They are not legacy
    -- local selections, so never create the generic CONFIRM/CANCEL pair here.
    if decision ~= nil and (decision.kind == "attacker_selection"
        or decision.kind == "blocker_selection" or decision.kind == "blocker_assignment") then
        return
    end
    if not BridgeDecisionNeedsConfirmation(decision)
        and not (decision ~= nil and decision.allowsCancel == true
            and (decision.kind == "target_selection" or decision.kind == "defender_selection"
                or decision.kind == "player_selection")) then return end
    local targetCanCancel = decision ~= nil and decision.allowsCancel == true
        and (decision.kind == "target_selection" or decision.kind == "defender_selection"
            or decision.kind == "player_selection")
    if #(BridgeState.selectionControlGuids or {}) > 0 then return end
    local seat = BRIDGE_SEATS[decision.seatId]
    if seat == nil then return end
    local function spawnSelectionControl(name, label, x, color, callback)
        spawnObject({
            type = "BlockSquare",
            position = {x, 1.6, seat.tableSideZ * 10.0},
            scale = {2.6, 0.35, 1.4},
            callback_function = function(object)
                object.setName(name)
                object.setLock(true)
                object.setColorTint(color)
                object.setRotation({0, seat.tableSideZ < 0 and 180 or 0, 0})
                object.createButton({
                    click_function = callback,
                    function_owner = Global,
                    label = label,
                    position = {0, 0.6, 0},
                    width = 950,
                    height = 460,
                    font_size = 150,
                    color = color,
                    font_color = {1, 1, 1, 1}
                })
                table.insert(BridgeState.selectionControlGuids, object.getGUID())
            end
        })
    end
    if BridgeDecisionNeedsConfirmation(decision) then
        spawnSelectionControl("Forge Confirm Selection", "DONE /\nCONFIRM", 2.0, {0.12, 0.52, 0.24}, "BridgeConfirmSelection")
    end
    if targetCanCancel then
        spawnSelectionControl("Forge Cancel Cast", "CANCEL /\nCAST", 7.5, {0.65, 0.2, 0.12}, "BridgeCancelSelection")
    elseif not BridgeIsStructuredForgeToggleChoice(decision) then
        spawnSelectionControl("Forge Cancel Selection", "CANCEL /\nUNDO", 7.5, {0.65, 0.2, 0.12}, "BridgeCancelSelection")
    end
end

function BridgeConfirmSelection(object, playerColor, altClick)
    -- Guard against dead object parameter from stale embedded button callbacks
    if object ~= nil then
        local ok = pcall(function() return object.getGUID() end)
        if not ok then return end
    end
    local decision = BridgeState.lastDecision

    -- Keep an older/stale presentation safe if it invokes the generic
    -- confirmation callback for a combat decision. Combat completion is always
    -- an exact Forge finish action, never a local selection count.
    if decision ~= nil and (decision.kind == "attacker_selection"
        or decision.kind == "blocker_selection" or decision.kind == "blocker_assignment") then
        for _, action in ipairs(decision.actions or {}) do
            if action.type == "finish_attacking" or action.type == "finish_blocking" or action.type == "choose_none" then
                BridgeClearHighlights()
                BridgeResetSelectionState()
                BridgeSubmitChoice(decision.decisionId, action.actionId, "contextual_done")
                return
            end
        end
        BridgeShowError("Forge supplied no current combat completion action")
        return
    end

    -- Structured Forge collections are already staged in Forge. Candidate
    -- clicks have been submitted individually and the redraw is the sole
    -- source of selectedCount/isSelected. Never consult the legacy local
    -- selectedActionIds map for this transaction.
    if BridgeIsStructuredForgeToggleChoice(decision) then
        local doneAction = nil
        for _, action in ipairs(decision.actions or {}) do
            if action.type == "choose_none" then
                doneAction = action
                break
            end
        end
        if doneAction == nil then
            BridgeShowError("Forge structured collection supplied no Done action")
            BridgeLog("[Bridge] STRUCTURED_DONE_BLOCKED reason=missing_done_action decision="
                .. tostring(decision.decisionId))
            return
        end
        if not BridgeCanSubmitStructuredDone(decision, "physical_structured_done") then return end
        BridgeLog(string.format(
            "[Bridge] STRUCTURED_DONE decision=%s kind=%s selected=%s action=%s source=physical_structured_done",
            tostring(decision.decisionId), tostring(decision.kind),
            tostring(decision.selectedCount or 0), tostring(doneAction.actionId)))
        -- Do not clear local selection state before this call: the existing
        -- BridgeSubmitChoice bookkeeping records Forge-selected mulligan
        -- bottom identities when the exact Done action is committed.
        BridgeSubmitChoice(decision.decisionId, doneAction.actionId, "physical_structured_done")
        return
    end

    if decision == nil or decision.decisionId ~= BridgeState.selectionDecisionId then
        BridgeShowError("selection is stale")
        BridgeResetSelectionState()
        return
    end
    local count = BridgeSelectionCount()
    local minimum = decision.minSelections or 1
    local maximum = decision.maxSelections or 1
    if count < minimum or count > maximum then
        BridgeShowError(string.format("selection requires %d to %d choices; currently selected %d", minimum, maximum, count))
        return
    end
    if count == 0 then
        for _, action in ipairs(decision.actions or {}) do
            if action.type == "finish_attacking" or action.type == "finish_blocking" or action.type == "choose_none" then
                BridgeResetSelectionState()
                BridgeSubmitChoice(decision.decisionId, action.actionId, "selection_zero_confirm")
                return
            end
        end
        BridgeShowError("Forge permits zero selections but supplied no explicit zero-selection action")
        return
    end
    for actionId, selected in pairs(BridgeState.selectedActionIds) do
        if selected then
            BridgeResetSelectionState()
            BridgeSubmitChoice(decision.decisionId, actionId, "selection_confirm")
            return
        end
    end
end

function BridgeCancelSelection(object, playerColor, altClick)
    -- Guard against dead object parameter from stale embedded button callbacks
    if object ~= nil then
        local ok = pcall(function() return object.getGUID() end)
        if not ok then return end
    end
    local decision = BridgeState.lastDecision
    if BridgeIsStructuredForgeToggleChoice(decision) then
        -- Forge owns the selected set for a structured collection. There is
        -- no generic cancel action in this protocol, so never visually clear
        -- a selection that Forge still holds. The HUD affordance is disabled
        -- and the physical control is not spawned for this decision.
        BridgeLog("[Bridge] STRUCTURED_CANCEL_BLOCKED decision=" .. tostring(decision.decisionId)
            .. " reason=no_forge_cancel_action")
        BridgeShowError("Forge-owned selection cannot be cancelled here; deselect cards through Forge choices")
        return
    end
    if decision ~= nil and decision.allowsCancel == true then
        local cancelAction = nil
        for _, action in ipairs(decision.actions or {}) do
            if action.type == "cancel_cast" then
                cancelAction = action
                break
            end
        end
        if cancelAction == nil then
            BridgeShowError("Forge supplied no current cast-cancel action")
            return
        end
        BridgeClaimHumanTtsColor(decision.seatId, playerColor)
        BridgeClearHighlights()
        BridgeResetSelectionState()
        BridgeSubmitChoice(decision.decisionId, cancelAction.actionId, "physical_cancel_cast")
        return
    end
    BridgeResetSelectionState()
    if decision ~= nil then BridgeRenderDecision(decision) end
end

function BridgeDecisionPresentationKey(decision)
    if decision == nil then return "decision:<nil>" end

    local parts = {}
    local function add(name, value)
        local text = value == nil and "<nil>" or tostring(value)
        table.insert(parts, name .. "=" .. tostring(#text) .. ":" .. text)
    end

    for _, name in ipairs({
        "decisionId", "kind", "seatId", "selectedCount", "minSelections", "maxSelections",
        "confirmRequired", "requiresConfirmation", "allowsCancel", "selectionKind", "costKind",
        "mulliganStage", "requiredTotalPower", "selectedTotalPower", "phaseName", "prioritySeatId",
        "activeSeatId", "prompt", "contextCardName", "decisionCauseKind", "sourceCardInstanceId",
        "sourceCardName", "turnNumber"
    }) do
        add(name, decision[name])
    end

    add("actionCount", #(decision.actions or {}))
    for index, action in ipairs(decision.actions or {}) do
        add("action[" .. tostring(index) .. "]", table.concat({
            tostring(action.actionId or "<nil>"),
            tostring(action.type or "<nil>"),
            tostring(action.actionKind or "<nil>"),
            tostring(action.cardInstanceId or "<nil>"),
            tostring(action.preparedSourceCardInstanceId or "<nil>"),
            tostring(action.sourceCardInstanceId or "<nil>"),
            tostring(action.cardIdentity or "<nil>"),
            tostring(action.sourceCardName or "<nil>"),
            tostring(action.sourceZone or "<nil>"),
            tostring(action.targetKind or "<nil>"),
            tostring(action.targetSeatId or "<nil>"),
            tostring(action.isSelected),
            tostring(action.displayName or "<nil>"),
            tostring(action.shortLabel or "<nil>"),
            tostring(action.displayManaCost or "<nil>"),
            tostring(action.castMode or "<nil>"),
            tostring(action.requiresFollowup),
            tostring(action.requiresSelection),
            tostring(action.isGraveyardFolder)
        }, "\31"))
    end
    return table.concat(parts, "\30")
end

function BridgeRecordDecisionPresentationRendered(key)
    BridgeState.renderedDecisionPresentationKey = key
    BridgeState.renderedDecisionPhysicalGeneration =
        BridgeState.currentPhysicalPresentationGeneration or 0
end

function BridgeDecisionPhysicalMappingsReady(decision)
    if decision == nil then return true, nil end
    for _, action in ipairs(decision.actions or {}) do
        local instanceId = action.preparedSourceCardInstanceId or action.sourceCardInstanceId or action.cardInstanceId
        if instanceId ~= nil then
            local descriptor = BridgeState.authoritativeObjectByInstanceId[instanceId]
            local policy = descriptor and tostring(descriptor.materializationPolicy or "") or ""
            local physicalRequired = descriptor == nil
                or (descriptor.isVirtual ~= true and policy ~= "virtual" and policy ~= "virtual-stack")
            if physicalRequired then
                local guid = BridgeState.physicalByInstanceId[instanceId]
                local object = guid and BridgeGetLiveObjectByGuid(guid) or nil
                local inverse = guid and BridgeState.physicalInstanceIdByGuid[guid] or nil
                if object == nil or object.tag ~= "Card" or inverse ~= instanceId then
                    return false, instanceId
                end
            end
        end
    end
    return true, nil
end

function BridgeRenderDecision(decision, force)
    if BridgeResolveRevealForDecision ~= nil then BridgeResolveRevealForDecision(decision) end
    BridgePresentationMetric("decisionRenderAttempts")
    BridgeRecordDecisionLifecycle(decision, "render", "RENDER_BEGIN", force == true and "forced" or "normal")
    local key = BridgeDecisionPresentationKey(decision)
    if force ~= true
        and key == BridgeState.renderedDecisionPresentationKey
        and BridgeState.renderedDecisionPhysicalGeneration
            == (BridgeState.currentPhysicalPresentationGeneration or 0) then
        BridgePresentationMetric("decisionRenderSkippedIdentical")
        return
    end
    local mappingsReady, missingInstanceId = BridgeDecisionPhysicalMappingsReady(decision)
    if not mappingsReady then
        BridgeRecordDecisionLifecycle(decision, "render", "DEFERRED_PHYSICAL_MAPPING",
            "missing-live-physical-mapping", missingInstanceId)
        if BridgeState.lastPhysicalDecisionBarrier ~= decision.decisionId then
            BridgeState.lastPhysicalDecisionBarrier = decision.decisionId
            BridgeLog("[Bridge] decision presentation deferred: missing live physical mapping instance="
                .. tostring(missingInstanceId) .. " decision=" .. tostring(decision.decisionId))
            BridgeShowError("Forge decision is waiting for a physical card mapping; retrying authoritative recovery")
        end
        if BridgeScheduleSnapshotReconcile ~= nil then
            BridgeScheduleSnapshotReconcile("decision physical mapping missing", "RECOVERY")
        end
        return
    end
    BridgePresentationMetric("decisionRenderExecuted")
    BridgeClearHighlights()
    BridgeRenderPreparedSpellPresentations(decision)

    if decision == nil or decision.actions == nil then
        BridgeResetSelectionState()
        BridgeRecordDecisionPresentationRendered(key)
        return
    end

    if BridgeState.selectionDecisionId ~= decision.decisionId then
        BridgeResetSelectionState()
        BridgeState.selectionDecisionId = decision.decisionId
    end
    BridgeEnsureSelectionControls(decision)
    BridgeEnsureContextualCompletionControl(decision)

    if (BridgeState.ui == nil or not BridgeState.ui.mounted)
        and decision.kind == "main_priority" and BridgeDecisionOffersActionType(decision, "pass_priority") then
        BridgeEnsureEndTurnButton(decision.seatId)
        BridgeEnsurePassButton(decision.seatId)
    else
        BridgeHideMainPriorityControls()
    end

    -- One controller owns all automatic priority decisions. The persistent
    -- checkbox only consumes pass-only priority; transient fast-forward may
    -- consume optional priority too, but never structured human choices.
    local controllerMode = BridgeYieldControllerMode ~= nil and BridgeYieldControllerMode() or "normal"
    local policyTurn = tonumber(BridgeState.yieldPolicyTurnNumber or 0) or 0
    local policyActiveSeat = BridgeState.yieldPolicyActiveSeatId
    local policyOwnTurn = BridgeState.yieldPolicyOwnTurn == true
    local policySessionMatches = BridgeState.yieldPolicySessionId == nil
        or BridgeState.yieldPolicySessionId == BridgeState.eventSessionId
    local policyTurnMatches = policyTurn == 0
        or (tonumber(BridgeState.tableTurnCount or 0) or 0) == policyTurn
    local policySeatMatches = policyActiveSeat == nil
        or BridgeState.currentTurnSeatId == policyActiveSeat
    -- A freshly started match may expose the opponent turn before Forge has
    -- emitted its first numeric turn counter. In that bootstrap window, the
    -- active-seat fence remains authoritative; turn_changed retires the
    -- policy once the real boundary is observed.
    local legacyYield = BridgeState.ui ~= nil and BridgeState.ui.fastForwardActive ~= true
        and BridgeState.ui.autoAdvanceMode == "YIELD" and BridgeState.yieldPolicyTurnNumber ~= nil
    local fastForward = BridgeState.ui ~= nil and BridgeState.ui.fastForwardActive == true
    if fastForward and BridgeState.ui.fastForwardActive == true
        and (BridgeState.ui.fastForwardSessionId ~= BridgeState.eventSessionId
            or (tonumber(BridgeState.ui.fastForwardTurnNumber or 0) or 0) ~= (tonumber(BridgeState.tableTurnCount or 0) or 0)) then
        BridgeCancelFastForward("turn-or-session-boundary")
        fastForward = false
    end
    local controllerActive = controllerMode ~= "normal"
        or (BridgeState.ui ~= nil and BridgeState.ui.autoAdvanceMode == "YIELD")
    if controllerActive and policyTurnMatches and policySeatMatches and policySessionMatches then
        local humanDecision = decision.seatId == "forge-player-1"
        local automaticAction = nil
        if humanDecision and decision.kind == "main_priority" then
            for _, action in ipairs(decision.actions or {}) do
                if action.type == "pass_priority" then automaticAction = action; break end
            end
        elseif humanDecision and decision.kind == "attacker_selection" then
            for _, action in ipairs(decision.actions or {}) do
                if action.type == "finish_attacking" or action.type == "choose_none" then
                    automaticAction = action
                    break
                end
            end
        end

        local phaseKey = BridgeYieldPhaseKey(decision.phaseName or BridgeState.currentPhase)
        local stopScope = BridgeYieldScopeForDecision(decision)
        local stopped = BridgeState.ui and BridgeState.ui.fastForwardStops
            and BridgeState.ui.fastForwardStops[stopScope]
            and phaseKey ~= nil and BridgeState.ui.fastForwardStops[stopScope][phaseKey] == true
        if fastForward and stopped then
            BridgeYieldRecord(decision, "AUTO_ACTION_BLOCKED", "phase-stop", "FAST_FORWARD")
            BridgeCancelFastForward("phase-stop")
        elseif legacyYield and policyOwnTurn and automaticAction ~= nil then
            if BridgeConsiderYieldAutomaticAction(decision, automaticAction, "OWN_TURN_YIELD") then
                BridgeRecordDecisionPresentationRendered(key)
                return
            end
        elseif legacyYield and not policyOwnTurn
            and decision.kind == "main_priority"
            and BridgeDecisionOffersActionType(decision, "pass_priority")
            and not BridgeDecisionHasNonPassAction(decision) then
            for _, action in ipairs(decision.actions or {}) do
                if action.type == "pass_priority" then
                    if BridgeConsiderYieldAutomaticAction(decision, action, "OPPONENT_YIELD") then
                        BridgeRecordDecisionPresentationRendered(key)
                        return
                    end
                    break
                end
            end
        elseif fastForward and automaticAction ~= nil then
            if BridgeConsiderYieldAutomaticAction(decision, automaticAction, "FAST_FORWARD") then
                BridgeRecordDecisionPresentationRendered(key)
                return
            end
        elseif not fastForward and BridgeState.ui ~= nil and BridgeState.ui.autoPassEmpty
            and decision.kind == "main_priority"
            and BridgeDecisionOffersActionType(decision, "pass_priority")
            and not BridgeDecisionHasNonPassAction(decision) then
            for _, action in ipairs(decision.actions or {}) do
                if action.type == "pass_priority" then
                    if BridgeConsiderYieldAutomaticAction(decision, action, "AUTO_PASS_EMPTY") then
                        BridgeRecordDecisionPresentationRendered(key)
                        return
                    end
                    break
                end
            end
        elseif legacyYield and humanDecision then
            BridgeDisarmYieldPolicy("mandatory-human-decision")
            policyTurnMatches = false
        elseif fastForward or (humanDecision and (decision.kind ~= "main_priority"
            or BridgeDecisionHasNonPassAction(decision)
            or not BridgeDecisionOffersActionType(decision, "pass_priority"))) then
            BridgeRecordDecisionLifecycle(decision, "yield", "AUTO_ACTION_CONSIDERED",
                "stopped_meaningful_choice", nil, nil,
                fastForward and "FAST_FORWARD" or "AUTO_PASS_EMPTY",
                "stopped_meaningful_choice")
            if fastForward then BridgeCancelFastForward("required-human-choice") end
            policyTurnMatches = false
        end
    end

    -- Keep passive auto-pass off for the human seat. This avoids skipping a
    -- playable window when decision/action rendering lags a frame; explicit
    -- PASS and END TURN controls still provide intentional progression.
    if decision.kind == "main_priority"
        -- Passive automation is only safe for an explicitly identified
        -- opponent window.  A missing/legacy seat field must never be treated
        -- as evidence that the human can be auto-passed through Main 1.
        and decision.seatId == "forge-player-2"
        and (decision.activeSeatId == nil or decision.activeSeatId == "forge-player-2")
        and BridgeDecisionOffersActionType(decision, "pass_priority")
        and not BridgeDecisionHasNonPassAction(decision) then
        for _, action in ipairs(decision.actions) do
            if action.type == "pass_priority" then
                local blockedReason = BridgeAutomaticDecisionBlocked(decision)
                if blockedReason ~= nil then
                    BridgeRecordDecisionLifecycle(decision, "smart", "AUTO_ACTION_BLOCKED",
                        blockedReason, action.actionId, action.type, "SMART", "blocked")
                    return
                end
                if BridgeAutomaticPassBackpressured() then
                    BridgeRecordDecisionLifecycle(decision, "smart", "AUTO_ACTION_BLOCKED",
                        "event-backpressure", action.actionId, action.type, "SMART", "blocked_backpressure")
                    return
                end
                BridgeRecordDecisionLifecycle(decision, "smart", "AUTO_ACTION_CONSIDERED",
                    "pass-only-opponent-window", action.actionId, action.type, "SMART", "submitted")
                BridgeSubmitChoice(decision.decisionId, action.actionId, "empty_priority_auto_pass")
                BridgeRecordDecisionPresentationRendered(key)
                return
            end
        end
    end

    local highlightColor = {0.53, 0.81, 0.98}
    local selectedCombatColor = {0.2, 1.0, 0.35}
    -- Discard is an immediate destructive choice and must remain visibly
    -- distinct from ordinary action availability.  Structured discard menus
    -- are Forge-owned toggles, but their physical candidates still use the
    -- orange choice treatment so the player can see that a discard decision
    -- is awaiting input.  Main-priority actions (including the pre-combat
    -- land/spell window) remain blue.
    if BridgeIsDiscardChoice(decision)
        or BridgeIsMulliganBottomSelection(decision)
        or (decision.kind == "card_selection" and BridgeDecisionContainsDiscardAction(decision))
        or (decision.kind ~= "main_priority" and not BridgeIsStructuredForgeToggleChoice(decision)) then
        highlightColor = {1.0, 0.55, 0.0}
    end

    local representedActionIds = {}
    local decisionSeat = BRIDGE_SEATS[decision.seatId]
    local cards = {}
    local candidateGuid = {}
    local seatHandGuids = {}
    if decision.kind == "main_priority" and decisionSeat ~= nil then
        seatHandGuids = BridgeBuildSeatHandGuidSet(decision.seatId)
    end
    local function addDecisionCandidate(object)
        if object == nil or object.tag ~= "Card" then return end
        local guid = BridgeSafeObjectGuid(object)
        if guid ~= nil and candidateGuid[guid] == true then return end
        if guid ~= nil then candidateGuid[guid] = true end
        local mappedInDecisionHand = guid ~= nil
            and BridgeState.physicalSeatByGuid[guid] == decision.seatId
            and BridgeState.physicalZoneByGuid[guid] == "hand"
            and decisionSeat ~= nil
            and BridgeObjectIsOnSeatSide(object, decisionSeat)
        local observedInDecisionHand = guid ~= nil and seatHandGuids[guid] == true
        if observedInDecisionHand then
            -- Keep the authoritative mapping sticky to the live hand object so
            -- legal hand actions remain interactable even if zone bookkeeping
            -- lags a frame behind physical hand ownership.
            local handMappingChanged = BridgeState.physicalSeatByGuid[guid] ~= decision.seatId
                or BridgeState.physicalZoneByGuid[guid] ~= "hand"
            BridgeState.physicalSeatByGuid[guid] = decision.seatId
            BridgeState.physicalZoneByGuid[guid] = "hand"
            if handMappingChanged then
                BridgeAdvancePhysicalPresentationGeneration("hand-mapping-repaired")
                -- A discard decision may have been shown via the HUD while
                -- this exact hand mapping was pending. Re-render once the
                -- physical identity is repaired so the same Forge action is
                -- available from the card as well.
                if BridgeState.lastDecision ~= nil
                    and BridgeState.lastDecision.decisionId == decision.decisionId then
                    BridgeWaitFrames(function()
                        if BridgeState.lastDecision ~= nil
                            and BridgeState.lastDecision.decisionId == decision.decisionId then
                            BridgeRenderDecision(BridgeState.lastDecision, true)
                        end
                    end, 1)
                end
            end
        end
        local isCandidate = decision.kind ~= "main_priority"
            or mappedInDecisionHand
            or observedInDecisionHand
            or (guid ~= nil
                and BridgeState.physicalSeatByGuid[guid] == decision.seatId
                and (BridgeState.physicalZoneByGuid[guid] == "battlefield"
                    or BridgeState.physicalZoneByGuid[guid] == "graveyard"
                    or BridgeState.physicalZoneByGuid[guid] == "exile"
                    or BridgeState.physicalZoneByGuid[guid] == "command"))
        if isCandidate then
            table.insert(cards, object)
        end
    end
    -- Exact Forge identities are resolved through the bridge indexes below;
    -- a world scan is only needed for legacy/name-only actions.  In
    -- particular, KEEP/MULLIGAN and pass-only menus contain no card
    -- candidates at all.  Scanning every TTS object for those menus was the
    -- measured freeze hot path during opening-hand presentation.
    local scanWorldCandidates = false
    for _, action in ipairs(decision.actions or {}) do
        local exactInstanceId = action.preparedSourceCardInstanceId
            or action.sourceCardInstanceId or action.cardInstanceId
        local actionType = action.type or action.actionKind
        local hasDisplayCard = action.cardIdentity ~= nil and tostring(action.cardIdentity) ~= ""
        if exactInstanceId == nil
            and hasDisplayCard
            and actionType ~= "pass_priority"
            and actionType ~= "keep_hand"
            and actionType ~= "mulligan" then
            scanWorldCandidates = true
            break
        end
    end
    if scanWorldCandidates then
        for _, object in ipairs(getAllObjects()) do
            addDecisionCandidate(object)
        end
    end
    -- TTS does not guarantee that cards held in a hand are returned by
    -- getAllObjects().  This is especially visible after mulligan replacement
    -- cards arrive through a hand callback, so include the authoritative
    -- decision seat's live hand as an explicit candidate source.
    if decisionSeat ~= nil then
        local handObjects = BridgeTryGetSeatHandObjects(decision.seatId)
        for _, object in ipairs(handObjects or {}) do
            addDecisionCandidate(object)
        end
    end

    for _, action in ipairs(decision.actions) do
        if action.targetKind == "player" and action.targetSeatId ~= nil then
            local suppressSelfDefenderTarget = decision.kind == "defender_selection"
                and action.targetSeatId == decision.seatId
                and BRIDGE_SEATS["forge-player-1"] ~= nil
                and BRIDGE_SEATS["forge-player-2"] ~= nil
            if suppressSelfDefenderTarget then
                representedActionIds[action.actionId] = true
                BridgeLog("[Bridge] suppressing illegal self-defender target in two-player match seat="
                    .. tostring(action.targetSeatId))
            else
                local targetSeat = BRIDGE_SEATS[action.targetSeatId]
                local targetObject = targetSeat and getObjectFromGUID(targetSeat.targetSurfaceGuid) or nil
                if targetObject ~= nil then
                    local guid = targetObject.getGUID()
                    targetObject.highlightOn({1.0, 0.55, 0.0})
                    BridgeState.actionByGuid[guid] = action
                    representedActionIds[action.actionId] = true
                    table.insert(BridgeState.highlightedGuids, guid)
                    BridgeInstallTargetButton(targetObject, action.targetSeatId)
                    BridgeSpawnPlayerTargetControl(targetObject, action.targetSeatId, decision, action)
                else
                    BridgeShowError("no physical target surface configured for seat " .. tostring(action.targetSeatId))
                end
            end
        end

        local matches = {}
        local presentationInstanceId = action.preparedSourceCardInstanceId or action.cardInstanceId
        local mappedGuid = presentationInstanceId and BridgeState.physicalByInstanceId[presentationInstanceId] or nil
        local mappedObject = BridgeGetLiveObjectByGuid(mappedGuid)
        local mappedSeatMatches = mappedObject ~= nil and (decision.kind ~= "main_priority"
            or BridgeState.physicalSeatByGuid[mappedGuid] == decision.seatId)
        -- Main-priority actions are not limited to cards in hand: activated
        -- abilities (including Crew) originate from a permanent in the
        -- battlefield, and alternate-cost abilities may originate in a
        -- graveyard or exile.  Exact CardInstanceId mapping is authoritative;
        -- use its structured source zone to bind the same physical card rather
        -- than caching a stale "hand-actionable" classification across
        -- decisions.  The hand candidate set remains the safe fallback for
        -- legacy actions without provenance metadata.
        local mappedPhysicalZone = mappedGuid and BridgeState.physicalZoneByGuid[mappedGuid] or nil
        local combatActionKind = action.type or action.actionKind
        local combatSelection = combatActionKind == "choose_attacker" or combatActionKind == "choose_blocker"
        local actionSourceZone = string.lower(tostring(action.sourceZone or ""))
        local mappedSourceZoneMatches = actionSourceZone ~= ""
            and mappedPhysicalZone == actionSourceZone
        if not mappedSourceZoneMatches and actionSourceZone == ""
            and (action.type == "activate_ability" or action.type == "activate_mana") then
            mappedSourceZoneMatches = mappedPhysicalZone == "battlefield"
                or mappedPhysicalZone == "graveyard"
                or mappedPhysicalZone == "exile"
        end
        local mappedZoneMatches = decision.kind ~= "main_priority"
            or candidateGuid[mappedGuid] == true
            or mappedSourceZoneMatches
        -- Combat candidates are Forge battlefield objects.  A stale mapping
        -- can otherwise make a spent instant (or any card that has since left
        -- the battlefield) inherit a combat highlight because non-priority
        -- decisions historically accepted every mapped zone.
        if combatSelection and mappedPhysicalZone ~= "battlefield" then
            mappedZoneMatches = false
        end
        local exactMappingContradictsActionSource = mappedObject ~= nil
            and action.cardInstanceId ~= nil
            and ((actionSourceZone ~= "" and not mappedSourceZoneMatches)
                or not mappedSeatMatches)
        if exactMappingContradictsActionSource then
            -- The exact Forge instance is still live, but it is no longer in
            -- the action's declared source zone (for example, Lotus Petal has
            -- already been sacrificed into the graveyard). Never recover a
            -- stale action by matching another card with the same name.
            BridgeLog(string.format(
                "[Bridge] suppressing stale exact action instance=%s card=%s sourceZone=%s mappedZone=%s mappedSeat=%s decisionSeat=%s",
                tostring(action.cardInstanceId), tostring(action.cardIdentity or action.type),
                tostring(actionSourceZone), tostring(mappedPhysicalZone),
                tostring(BridgeState.physicalSeatByGuid[mappedGuid]), tostring(decision.seatId)))
        elseif mappedSeatMatches and mappedZoneMatches then
            table.insert(matches, mappedObject)
        else
            local fallbackMatches = {}
            -- A combat candidate with an exact Forge identity must never fall
            -- back to a same-name physical card. A spent instant (or another
            -- stale card that left the battlefield) could otherwise receive an
            -- attacker highlight and submit the wrong object.
            if not (combatSelection and action.cardInstanceId ~= nil) then
                for _, object in ipairs(cards) do
                    local objectGuid = BridgeSafeObjectGuid(object)
                    local objectZone = objectGuid and BridgeState.physicalZoneByGuid[objectGuid] or nil
                    if (not combatSelection or objectZone == "battlefield")
                        and BridgeCardNameMatches(object.getName(), action.cardIdentity) then
                        table.insert(fallbackMatches, object)
                    end
                end
            else
                BridgeLog(string.format(
                    "[Bridge] suppressing combat action without exact physical mapping instance=%s card=%s",
                    tostring(action.cardInstanceId), tostring(action.cardIdentity or action.type)))
            end
            if action.cardInstanceId == nil then
                matches = fallbackMatches
            elseif #fallbackMatches == 1 then
                local recoveredGuid = BridgeSafeObjectGuid(fallbackMatches[1])
                if recoveredGuid ~= nil then
                    local recoveredZone = decision.kind == "main_priority"
                        and "hand" or BridgeState.physicalZoneByGuid[recoveredGuid]
                    BridgeRecordLooseCardIdentity(action.cardInstanceId, recoveredGuid, decision.seatId, recoveredZone)
                    if action.cardIdentity ~= nil then
                        BridgeState.cardNameByInstanceId[action.cardInstanceId] = action.cardIdentity
                    end
                    matches = fallbackMatches
                    BridgeLog(string.format(
                        "[Bridge] repaired instance mapping for %s -> %s (%s)",
                        tostring(action.cardInstanceId), tostring(recoveredGuid), tostring(action.cardIdentity or action.type)))
                end
            elseif #fallbackMatches > 1 then
                BridgeLog(string.format(
                    "[Bridge] instance mapping ambiguous for %s (%s): %d candidates",
                    tostring(action.cardInstanceId), tostring(action.cardIdentity or action.type), #fallbackMatches))
            end
        end

        if #matches > 0 and (action.cardIdentity ~= nil or action.cardInstanceId ~= nil) then
            if mappedGuid == nil and #matches > 1 then
                BridgeLog(string.format("[Bridge] duplicate card name '%s': highlighting all %d candidates", tostring(action.cardIdentity), #matches))
            end

            for _, object in ipairs(matches) do
                local guid = object.getGUID()
                -- Forge reprints selected combatants in the next decision. Keep
                -- their action binding so selecting the same physical card sends
                -- the toggle back to Forge instead of making it inert in TTS.
                if action.type == "choose_attacker" or action.type == "choose_blocker" then
                    BridgeState.combatSelectedByGuid[guid] = action.isSelected == true or nil
                end
                local selected = BridgeState.selectedActionIds[action.actionId] == true
                    or BridgeState.combatSelectedByGuid[guid] == true
                    or action.isSelected == true
                object.highlightOn(selected and selectedCombatColor or highlightColor)
                BridgeState.actionByGuid[guid] = action
                representedActionIds[action.actionId] = true
                table.insert(BridgeState.highlightedGuids, guid)
            end
        end
    end

    BridgeEnsureDecisionOptionControls(decision, representedActionIds)
    BridgeApplyDiscardPresentation(decision)
    BridgeUiMarkDirty("decision-render")
    BridgeRecordDecisionPresentationRendered(key)
end

function BridgeShowError(message)
    local text = "[Bridge] " .. tostring(message)
    BridgeLog(text)
    broadcastToAll(text, {1.0, 0.2, 0.2})
end

function BridgeCaptureUnboundPickupIntent(object)
    if object == nil or object.tag ~= "Card" then return end
    local guid = BridgeSafeObjectGuid(object)
    if guid == nil then return end
    local seatId = BridgeState.physicalSeatByGuid[guid]
    local zone = BridgeState.physicalZoneByGuid[guid]
    if seatId == nil or zone == nil then return end
    BridgeState.unboundPickupIntent = {
        guid = guid,
        seatId = seatId,
        zone = zone,
        position = object.getPosition(),
        rotation = object.getRotation(),
        useHands = object.use_hands
    }
end

function BridgeRejectUnboundDropIfIllegal(object)
    local intent = BridgeState.unboundPickupIntent
    BridgeState.unboundPickupIntent = nil
    if intent == nil or object == nil then return end
    if BridgeSafeObjectGuid(object) ~= intent.guid then return end
    if intent.zone ~= "hand" then return end

    local current = object.getPosition()
    local dx = current.x - intent.position.x
    local dz = current.z - intent.position.z
    local movedSq = dx * dx + dz * dz
    if movedSq < 1.0 then return end
    if BridgeObjectNearSeatZone(object, intent.seatId, "hand") then return end

    object.use_hands = intent.useHands
    object.setPositionSmooth(intent.position, false, true)
    object.setRotationSmooth(intent.rotation, false, true)
    object.highlightOn({1.0, 0.1, 0.1}, 2)
    BridgeShowError("illegal physical move rejected; use a highlighted Forge action")
end

function onObjectPickUp(playerColor, object)
    if object == nil or BridgeState.submitting then
        return
    end

    BridgeState.unboundPickupIntent = nil
    local action = BridgeState.actionByGuid[object.getGUID()]
    if action == nil then
        BridgeCaptureUnboundPickupIntent(object)
        return
    end

    local decision = BridgeState.lastDecision
    if decision == nil then
        BridgeClearHighlights()
        BridgeShowError("highlighted card has no active bridge decision")
        return
    end

    if not BridgeDecisionHasAction(decision, action.actionId) then
        -- The object was highlighted by an older decision. Never turn a
        -- physical pickup into a submission for a different Forge prompt.
        BridgeClearHighlights()
        BridgeShowError("card action is stale; waiting for the current Forge decision")
        return
    end

    BridgeClaimHumanTtsColor(decision.seatId, playerColor)

    -- A prepared spell is a Forge-owned virtual copy in exile. The physical
    -- permanent is only its contextual selection surface and must not be
    -- moved as though it were the spell being cast.
    if object.tag == "Card" and tostring(action.castMode or "") == "prepare" then
        BridgeSubmitChoice(decision.decisionId, action.actionId, "physical_prepared_spell")
        return
    end

    -- A target is a single Forge choice, not a local collection. Requiring a
    -- second confirmation after touching a legal instant target left the stack
    -- waiting while TTS had not actually sent Forge any input.
    if object.tag == "Card" and action.type == "choose_target" then
        BridgeClearHighlights()
        BridgeSubmitChoice(decision.decisionId, action.actionId, "physical_card_target_pickup")
        return
    end

    -- Sacrifice costs are Forge's toggle-plus-Done transport. Send the toggle
    -- immediately; the accepted fixed-count response is completed above.
    if object.tag == "Card" and action.type == "sacrifice" and decision.confirmRequired == true then
        BridgeClearHighlights()
        BridgeSubmitChoice(decision.decisionId, action.actionId, "physical_sacrifice_pickup")
        return
    end

    -- Keep a discard pickup staged until TTS tells us where the card was
    -- released.  A release in the hand is the physical click/selection
    -- gesture; a release over the graveyard is the explicit drag gesture.
    -- Both paths submit the same exact Forge action and never move the card
    -- locally before Forge accepts it.
    if object.tag == "Card" and action.type == "discard_card" and BridgeIsDiscardChoice(decision) then
        BridgeState.pendingIntent = {
            guid = object.getGUID(),
            position = object.getPosition(),
            rotation = object.getRotation(),
            useHands = object.use_hands,
            physicalSeatId = BridgeState.physicalSeatByGuid[object.getGUID()],
            physicalZone = BridgeState.physicalZoneByGuid[object.getGUID()],
            decisionId = decision.decisionId,
            action = action,
            seatId = decision.seatId
        }
        BridgeClearHighlights()
        return
    end

    -- Delve and post-mulligan bottom choices use Forge's native sequential
    -- toggle transaction. A physical pickup submits the exact candidate
    -- ActionId; the returned Forge decision redraws both physical highlights
    -- and the HUD from the same staged state. No local zone move is made.
    if object.tag == "Card" and BridgeIsStructuredForgeToggleChoice(decision) then
        BridgeSubmitChoice(decision.decisionId, action.actionId, "physical_structured_toggle")
        return
    end

    BridgeState.pendingIntent = {
        guid = object.getGUID(),
        position = object.getPosition(),
        rotation = object.getRotation(),
        useHands = object.use_hands,
        physicalSeatId = BridgeState.physicalSeatByGuid[object.getGUID()],
        physicalZone = BridgeState.physicalZoneByGuid[object.getGUID()],
        decisionId = decision.decisionId,
        action = action,
        seatId = decision.seatId
    }
    BridgeClearHighlights()

    if object.tag == "Card" and (BridgeDecisionNeedsConfirmation(decision)
        or (action.requiresSelection == true
            and action.type ~= "choose_attacker"
            and action.type ~= "choose_blocker")) then
        local actionId = action.actionId
        if not BridgeToggleSingleSelection(decision, actionId, object.getGUID()) then
            BridgeRollbackPendingIntent()
            BridgeRenderDecision(decision)
            return
        end
        object.use_hands = BridgeState.pendingIntent.useHands
        object.setPositionSmooth(BridgeState.pendingIntent.position, false, true)
        object.setRotationSmooth(BridgeState.pendingIntent.rotation, false, true)
        BridgeState.pendingIntent = nil
        -- The physical snap-back is asynchronous.  A spell/target choice can
        -- resolve and Forge can publish a newer decision before these frames
        -- elapse (Thought Scour is a particularly visible example).  Never
        -- redraw the captured decision after it has retired: doing so brings
        -- back stale cast/target highlights over the authoritative next
        -- decision.  The normal decision/event pipeline owns the replacement
        -- render.
        local capturedDecisionId = decision.decisionId
        local capturedSessionId = BridgeState.eventSessionId
        local capturedRuntimeEpoch = BRIDGE_RUNTIME_EPOCH_LOCAL
        BridgeWaitFrames(function()
            local current = BridgeState.lastDecision
            local decisionIsUnsubmitted = BridgeState.choiceTransactions[capturedDecisionId] == nil
                and BridgeState.retiredChoiceDecisionIds[capturedDecisionId] ~= true
            local sameRuntime = BridgeRuntimeIsCurrent(capturedRuntimeEpoch)
            local sameSession = BridgeState.eventSessionId == capturedSessionId
            local actionable = current ~= nil and #(current.actions or {}) > 0
            if sameRuntime and sameSession and decisionIsUnsubmitted
                and actionable and current.decisionId == capturedDecisionId then
                BridgeRenderDecision(current, true)
            end
        end, 2)
        return
    end

    -- Player scoreboards and other non-card targets are selection surfaces,
    -- not draggable game pieces, so the grab itself commits the offered target.
    if object.tag ~= "Card" then
        BridgeSubmitChoice(decision.decisionId, action.actionId, "physical_target_pickup")
    end
end

function onObjectDrop(playerColor, object)
    if object == nil or BridgeState.submitting then
        BridgeState.unboundPickupIntent = nil
        return
    end

    local intent = BridgeState.pendingIntent
    if intent == nil then
        BridgeRejectUnboundDropIfIllegal(object)
        return
    end
    if object.getGUID() ~= intent.guid then
        return
    end
    BridgeState.unboundPickupIntent = nil

    local decision = BridgeState.lastDecision
    if decision == nil or decision.decisionId ~= intent.decisionId then
        BridgeRollbackPendingIntent()
        BridgeShowError("staged intent became stale before drop")
        return
    end

    -- Dropping a card onto the graveyard is an explicit physical discard
    -- confirmation.  Releasing it in the hand (including a normal click)
    -- submits the same exact action after restoring the presentation-only
    -- preview.  Forge remains the sole authority for the actual zone move.
    if intent.action.type == "discard_card" and BridgeIsDiscardChoice(decision) then
        local decisionId = intent.decisionId
        local actionId = intent.action.actionId
        if BridgeObjectNearSeatZone(object, intent.seatId, "graveyard") then
            BridgeSubmitChoice(decisionId, actionId, "physical_discard_graveyard")
            return
        end
        BridgeRollbackPendingIntent()
        BridgeRenderDecision(decision)
        BridgeSubmitChoice(decisionId, actionId, "physical_discard_click")
        return
    end

    if intent.action.type == "play_land" or intent.action.type == "cast_spell" then
        local current = object.getPosition()
        local dx = current.x - intent.position.x
        local dz = current.z - intent.position.z
        if dx * dx + dz * dz < 1.0 then
            BridgeRollbackPendingIntent()
            BridgeRenderDecision(decision)
            return
        end
        BridgeState.physicalSeatByGuid[intent.guid] = intent.seatId
        if intent.action.type == "play_land" then
            BridgeState.physicalZoneByGuid[intent.guid] = "battlefield"
        else
            BridgeState.physicalZoneByGuid[intent.guid] = "stack"
            object.use_hands = false
            object.setPositionSmooth(BRIDGE_STACK_POSITION, false, true)
            BridgeTracePermanentTransition("CAST_CONFIRM", {
                cardInstanceId = intent.action.cardInstanceId,
                seatId = intent.seatId,
                sourceZone = intent.physicalZone,
                destinationZone = "stack",
                sequence = "intent:" .. tostring(intent.action.actionId)
            }, object, intent.physicalZone)
            BridgeTracePermanentTransition("STACK_MOVE", {
                cardInstanceId = intent.action.cardInstanceId,
                seatId = intent.seatId,
                sourceZone = intent.physicalZone,
                destinationZone = "stack",
                sequence = "intent:" .. tostring(intent.action.actionId)
            }, object, intent.physicalZone)
            BridgeEnsureCastPreviewControls(intent)
            BridgeAdvancePhysicalPresentationGeneration("cast-preview-entered")
            return
        end
        BridgeAdvancePhysicalPresentationGeneration("physical-intent-accepted")
    end

    if intent.action.type == "choose_attacker" or intent.action.type == "choose_blocker" then
        local current = object.getPosition()
        local dx = current.x - intent.position.x
        local dz = current.z - intent.position.z
        local movedEnough = (dx * dx + dz * dz) >= 1.0
        local laneZ = intent.action.type == "choose_attacker"
            and (BRIDGE_SEATS[intent.seatId] and BRIDGE_SEATS[intent.seatId].attackLaneZ or nil)
            or (BRIDGE_SEATS[intent.seatId] and BRIDGE_SEATS[intent.seatId].blockerLaneZ or nil)
        local droppedInLane = laneZ ~= nil and math.abs(current.z - laneZ) <= 1.35
        -- A normal pickup/drop is a valid desktop and VR selection gesture.
        -- The bridge performs the lane preview after Forge accepts the exact
        -- offered action, so players need not drag a card to a narrow row.
        if not movedEnough and not droppedInLane then
            BridgeLog(string.format(
                "[Bridge] combat selection accepted in place for %s (guid=%s)",
                tostring(intent.action.type), tostring(intent.guid)))
        end
        BridgeLog(string.format(
            "[Bridge] combat drop accepted for %s (guid=%s movedSq=%.3f laneHit=%s action=%s decision=%s)",
            tostring(intent.action.type), tostring(intent.guid), dx * dx + dz * dz, tostring(droppedInLane),
            tostring(intent.action.actionId), tostring(intent.decisionId)))
        object.use_hands = false
        if intent.action.type == "choose_attacker" then
            BridgeMoveToAttackLane(intent.seatId, object)
        else
            BridgeMoveToBlockerLane(intent.seatId, object)
        end
    end

    local submissionSource = "physical_card_drop"
    if intent.action.type == "choose_attacker" then
        submissionSource = "attacker_drop"
    elseif intent.action.type == "choose_blocker" then
        submissionSource = "blocker_drop"
    elseif intent.action.type == "play_land" then
        submissionSource = "physical_land_drop"
    end
    BridgeSubmitChoice(intent.decisionId, intent.action.actionId, submissionSource)
end

function BridgeCommitPendingIntent()
    local intent = BridgeState.pendingIntent
    BridgeState.pendingIntent = nil
    BridgeClearPendingIntentControls()
    if intent == nil then return end

    if intent.action.type == "choose_attacker" or intent.action.type == "choose_blocker" then
        -- The Forge combat menu is a toggle: selecting a card shown as
        -- [ATTACKING]/[BLOCKING] removes that staged declaration.
        local object = getObjectFromGUID(intent.guid)
        if object ~= nil then
            object.use_hands = false
            if intent.action.isSelected == true then
                BridgeReturnCombatPreviewCard(intent.seatId, object)
            else
                BridgeState.combatSelectedByGuid[intent.guid] = true
                object.highlightOn({0.2, 1.0, 0.35})
            end
        end
    elseif intent.action.type ~= "play_land" and intent.action.type ~= "cast_spell" then
        local object = getObjectFromGUID(intent.guid)
        if object ~= nil then
            object.use_hands = intent.useHands
            object.setPositionSmooth(intent.position, false, true)
            object.setRotationSmooth(intent.rotation, false, true)
        end
    else
        local object = getObjectFromGUID(intent.guid)
        if object ~= nil then object.use_hands = false end
        if intent.action.type == "cast_spell" then
            BridgeState.pendingCastBySeatId[intent.seatId] = {
                guid = intent.guid,
                cardInstanceId = intent.action.cardInstanceId,
                cardIdentity = intent.action.cardIdentity,
                actionId = intent.action.actionId,
                decisionId = intent.decisionId,
            }
        end
    end
end

function BridgeRollbackPendingIntent()
    local intent = BridgeState.pendingIntent
    BridgeState.pendingIntent = nil
    BridgeClearPendingIntentControls()
    if intent == nil then
        return
    end

    local object = getObjectFromGUID(intent.guid)
    if object ~= nil then
        object.use_hands = intent.useHands
        object.setPositionSmooth(intent.position, false, true)
        object.setRotationSmooth(intent.rotation, false, true)
        object.highlightOn({1.0, 0.1, 0.1}, 2)
    end
    -- Preview/cancel must never discard an established Forge-instance mapping.
    -- Losing it caused a later authoritative hand->battlefield event to be
    -- unembodiable even though the player had only cancelled a physical move.
    BridgeState.physicalSeatByGuid[intent.guid] = intent.physicalSeatId
    BridgeState.physicalZoneByGuid[intent.guid] = intent.physicalZone
    BridgeAdvancePhysicalPresentationGeneration("intent-rolled-back")
    if intent.action ~= nil and intent.action.type == "cast_spell" then
        BridgeState.pendingCastBySeatId[intent.seatId] = nil
    end
end

function BridgeBootstrapCurrentSnapshot(sessionId, callback, resumeFromSnapshotCursor, resyncOrigin)
    if BridgeState.bootstrapping then
        -- A previous hand-readiness/bootstrap attempt can leave only its
        -- local ownership flag behind after a callback is abandoned.  A
        -- same-session authoritative resync is the recovery owner and must
        -- be able to supersede that stale attempt; otherwise every valid
        -- snapshot is rejected before reconciliation even begins.  The
        -- generation fence makes the old continuation inert.
        if resumeFromSnapshotCursor == true and BridgeState.resyncInFlight == true
            and BridgeState.eventSessionId == sessionId then
            BridgeState.resyncBootstrapGeneration = (BridgeState.resyncBootstrapGeneration or 0) + 1
            BridgeState.bootstrapping = false
            BridgeLog("[Bridge] superseded stale bootstrap ownership for authoritative resync")
        else
            callback(false, "an embodiment bootstrap is already in progress")
            return
        end
    end
    BridgeState.resyncBootstrapGeneration = (BridgeState.resyncBootstrapGeneration or 0) + 1
    local bootstrapGeneration = BridgeState.resyncBootstrapGeneration
    BridgeSetResyncStage("FetchingSnapshot", "bootstrap", nil)
    BridgeRecordResyncLifecycle("SNAPSHOT_REQUESTED", resyncOrigin, bootstrapGeneration)
    local function currentBootstrap()
        return BridgeState.resyncBootstrapGeneration == bootstrapGeneration
            and BridgeState.eventSessionId == sessionId
            and BridgeState.bootstrapping == true
    end
    local function finishBootstrap(ok, errorMessage)
        if not currentBootstrap() then return end
        BridgeState.bootstrapping = false
        callback(ok, errorMessage)
    end
    -- Establish the event session before populating instance mappings. Event
    -- polling must not clear the authoritative snapshot we just reconciled.
    -- A same-session recovery already has a committed event session and a
    -- checkpoint. Re-preparing it here needlessly increments every
    -- presentation generation and clears/restores the mapping registry on
    -- each retry, which was the source of the longitudinal recovery churn.
    local sameSessionRecovery = resumeFromSnapshotCursor == true
        and BridgeState.eventSessionId == sessionId
    BridgeTraceStart("START-09 event-session-prepare", sameSessionRecovery and "preserved" or "required")
    if not sameSessionRecovery then
        BridgePrepareEventSession(sessionId, true, resumeFromSnapshotCursor == true)
    end
    -- A resync rebuilds physical embodiment, not the Forge match.  The card
    -- snapshot intentionally does not carry the live phase/priority mirror,
    -- so retain those last authoritative scalar values while the rebuild is
    -- in flight.  This prevents the HUD from looking like a new match until
    -- the resumed decision/event stream supplies its next update.
    local preservedResyncPresentation = BridgeState.resyncPresentationState
    BridgeState.resyncPresentationState = nil
    if preservedResyncPresentation ~= nil then
        BridgeState.currentTurnSeatId = preservedResyncPresentation.currentTurnSeatId
        BridgeState.currentPhase = preservedResyncPresentation.currentPhase
        BridgeState.prioritySeatId = preservedResyncPresentation.prioritySeatId
        BridgeState.tableTurnCount = preservedResyncPresentation.tableTurnCount or BridgeState.tableTurnCount
        BridgeUiMarkDirty("resync-state-preserved")
    end
    BridgeState.bootstrapping = true
    BridgeTraceStart("START-10 snapshot-request")
    BridgeGetEmbodimentSnapshot(function(ok, snapshot, err)
        if not currentBootstrap() then return end
        BridgeRecordResyncLifecycle("SNAPSHOT_RECEIVED", resyncOrigin, bootstrapGeneration, snapshot, ok and nil or err)
        BridgeRunTraced("START-11 snapshot-response", function()
            if not currentBootstrap() then return end
            BridgeTraceStart("START-11 snapshot-response", ok and tostring(snapshot and snapshot.sessionId or "ok") or tostring(err))
            if not ok or snapshot == nil then
                if snapshot ~= nil and snapshot.errorCode == "session_not_started" then
                    finishBootstrap(false, "session_not_started: bridge has no active Forge session")
                    return
                end
                finishBootstrap(false, "authoritative snapshot unavailable: " .. tostring(err))
                return
            end
            if snapshot.sessionId ~= sessionId then
                finishBootstrap(false, "snapshot session mismatch")
                return
            end
            local snapshotCursor = tonumber(snapshot.eventCursor)
            if snapshotCursor == nil or snapshotCursor < 0 then
                finishBootstrap(false, "authoritative snapshot is missing a valid event cursor")
                return
            end
            local snapshotFingerprint = table.concat({
                tostring(snapshot.sessionId), tostring(snapshot.eventCursor),
                tostring(snapshot.forgeSequence or "")
            }, "|")
            if BridgeState.resyncSnapshotFingerprint == snapshotFingerprint then
                BridgeState.resyncSnapshotRepeatCount = (BridgeState.resyncSnapshotRepeatCount or 0) + 1
            else
                BridgeState.resyncSnapshotFingerprint = snapshotFingerprint
                BridgeState.resyncSnapshotRepeatCount = 1
            end
            if BridgeState.resyncSnapshotRepeatCount > 2 then
                BridgeLog("[Bridge] RESYNC_NO_PROGRESS identical snapshot limit reached fingerprint=" .. snapshotFingerprint)
                finishBootstrap(false, "authoritative resync made no progress across identical snapshots")
                return
            end
            if resumeFromSnapshotCursor == true then
                -- Validation is deliberately side-effect free.  The queued
                -- prefix is superseded only by BridgeCommitSnapshotCheckpoint
                -- after physical reconciliation has completed successfully.
                BridgeRecordResyncLifecycle("VALIDATING_SNAPSHOT", resyncOrigin, bootstrapGeneration, snapshot)
            end
            BridgeRecordResyncSnapshotProgress(resyncOrigin, snapshot)
            BridgeRecordExpectedHandIdentities(snapshot)
            local duplicateGuidCount = BridgeAuditDuplicateLibraryGuids()
            if duplicateGuidCount > 0 then
                local detail = "physical library identity audit found " .. tostring(duplicateGuidCount)
                    .. " loose/contained duplicate GUID(s)"
                BridgeLog("[Bridge] " .. detail)
                finishBootstrap(false, detail)
                return
            end
            BridgeTraceStart("START-12 physical-bootstrap-begin")
            BridgeSetResyncStage("ReconcilingSnapshot", "snapshot-validated", snapshot)
            BridgeState.resyncReconcileStarted = true
            BridgeState.resyncLastProgressAt = BridgeResyncClockNow()
            BridgeRecordResyncLifecycle("RECONCILE_STARTED", resyncOrigin, bootstrapGeneration, snapshot)
            BridgeStageSeatCardsForBootstrap(snapshot, function(stagedOk, stagedError, stagedGuids)
                if not currentBootstrap() then return end
                if not stagedOk then
                    finishBootstrap(false, stagedError)
                    return
                end

                -- Each staged Card was individually containment-verified.
                -- Keep the terminal strict audit as a corruption canary
                -- before rebuilding exact Forge mappings.
                BridgeTraceStart("START-13 library-settle")
                BridgeVerifyLibraryIdentityStability(function(stable, stabilityError)
                    if not currentBootstrap() then return end
                    if not stable then
                        local detail = "physical library identity audit found " .. tostring(stabilityError)
                            .. " after staging"
                        BridgeLog("[Bridge] " .. detail)
                        finishBootstrap(false, detail)
                        return
                    end
                    BridgeAnnotateSnapshotBattlefieldKinds(snapshot, function(annotated, annotationError)
                        if not currentBootstrap() then return end
                        BridgeRunTraced("START annotate-callback", function()
                            if not currentBootstrap() then return end
                            if not annotated then
                                finishBootstrap(false, annotationError)
                                return
                            end
                            BridgeBootstrapSeats(snapshot, 1, function(seatsOk, seatsError)
                                if not currentBootstrap() then return end
                                BridgeRunTraced("START seat-bootstrap-callback", function()
                                    if not currentBootstrap() then return end
                                    if not seatsOk then finishBootstrap(false, seatsError); return end
                                    BridgeState.snapshotForgeSequence = snapshot.forgeSequence or 0
                                    if resumeFromSnapshotCursor == true then
                                        local cursor = snapshotCursor
                                        -- The snapshot is coherent through this bridge event cursor.
                                        -- Resume polling after it so no pre-snapshot transition is
                                        -- replayed over the just-rebuilt physical embodiment.
                                        local committed, commitError = BridgeCommitSnapshotCheckpoint(
                                            snapshot, "physical-reconcile-complete")
                                        if not committed then finishBootstrap(false, commitError); return end
                                    end
                                    BridgeLog(string.format(
                                        "[Bridge] authoritative embodiment bootstrap complete: seats=%d forgeSequence=%s (hidden identities redacted)",
                                        #(snapshot.seats or {}), tostring(BridgeState.snapshotForgeSequence)))
                                    finishBootstrap(true, nil)
                                end)
                            end)
                        end)
                    end)
                end, 1, stagedGuids)
            end)
        end)
    end)
end

function BridgeBootstrapWhenAvailable(sessionId, attempt, callback)
    BridgeBootstrapCurrentSnapshot(sessionId, function(ok, err)
        local detail = tostring(err or "")
        if string.find(detail, "session_not_started", 1, true) ~= nil
            or string.find(detail, "no active Forge session", 1, true) ~= nil then
            BridgeCleanupLocalSession("snapshot-no-session", BRIDGE_LIFECYCLE_READY_NO_SESSION)
            callback(false, "bridge reports no active session")
            return
        end
        if ok or string.find(tostring(err), "HTTP 404", 1, true) == nil then
            callback(ok, err)
            return
        end
        if attempt >= 30 then
            callback(false, "authoritative snapshot was unavailable after 60 seconds")
            return
        end
        if attempt == 1 or attempt % 5 == 0 then
            BridgeLog("[Bridge] waiting for Forge's authoritative snapshot...")
        end
        BridgeWaitTime(function() BridgeBootstrapWhenAvailable(sessionId, attempt + 1, callback) end, 2)
    end)
end

function BridgeAnnotateSnapshotBattlefieldKinds(snapshot, callback)
    local needsHistory = false
    for _, seatSnapshot in ipairs(snapshot.seats or {}) do
        for _, zone in ipairs(seatSnapshot.zones or {}) do
            if zone.name == "battlefield" then
                for _, card in ipairs(zone.cards or {}) do
                    if card.battlefieldKind == nil then needsHistory = true; break end
                end
            end
        end
    end
    if not needsHistory then callback(true, nil); return end

    BridgeHttp.requestJson("GET", "/api/v1/events?after=0", nil, function(ok, body, err)
        if not ok or body == nil then
            callback(false, "authoritative event history unavailable for battlefield reconstruction: " .. tostring(err))
            return
        end
        if body.hasGap == true then
            callback(false, "authoritative event history gap prevents battlefield reconstruction")
            return
        end
        local landByInstanceId = {}
        for _, event in ipairs(body.events or {}) do
            if event.kind == "land_played" and event.cardInstanceId ~= nil then
                landByInstanceId[event.cardInstanceId] = true
            end
        end
        for _, seatSnapshot in ipairs(snapshot.seats or {}) do
            for _, zone in ipairs(seatSnapshot.zones or {}) do
                if zone.name == "battlefield" then
                    for _, card in ipairs(zone.cards or {}) do
                        if landByInstanceId[card.cardInstanceId] then card.battlefieldKind = "land" end
                    end
                end
            end
        end
        callback(true, nil)
    end)
end

function BridgeBootstrapSeats(snapshot, seatIndex, callback)
    local seats = snapshot.seats or {}
    if seatIndex > #seats then callback(true, nil); return end
    local seatSnapshot = seats[seatIndex]
    local seat = BRIDGE_SEATS[seatSnapshot.seatId]
    if seat == nil then callback(false, "snapshot has no configured TTS seat " .. tostring(seatSnapshot.seatId)); return end

    BridgeTryBootstrapSeatSnapshot(seatSnapshot, 1, function(ok, bootstrapError)
        if not ok then callback(false, bootstrapError); return end
        BridgeBootstrapSeats(snapshot, seatIndex + 1, callback)
    end)
end

-- A recovery is a controlled, Forge-authoritative rebuild of TTS embodiment.
-- It never infers a card, replays a stale event, or changes Forge state. The
-- snapshot's bridge event cursor becomes the new resume point only after every
-- seat has been materially reconciled.
function BridgeIsExplicitResyncOrigin(origin)
    local value = string.lower(tostring(origin or ""))
    return value == "hud" or value == "manual" or value == "manual-control"
        or value == "user" or value == "user-resync"
end

local function BridgeCopyResyncValue(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] ~= nil then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do
        copy[BridgeCopyResyncValue(key, seen)] = BridgeCopyResyncValue(item, seen)
    end
    return copy
end

local function BridgeCopyResyncTable(value)
    return BridgeCopyResyncValue(value or {}, {})
end

function BridgeBeginResyncMappingTransaction()
    if BridgeState.resyncMappingTransaction ~= nil then return end
    local names = {
        "physicalByInstanceId", "physicalInstanceIdByGuid", "physicalSeatByGuid",
        "physicalZoneByGuid", "cardNameByInstanceId", "canonicalCardNameByGuid",
        "authoritativeObjectByInstanceId", "battlefieldKindByInstanceId",
        "pendingPrivateHandIdentityByInstanceId", "untappedRotationByGuid",
        "physicalTappedByGuid", "counterStateByInstanceId", "keywordStateByInstanceId",
        "cardDesignationsByInstanceId"
    }
    local snapshot = {}
    for _, name in ipairs(names) do snapshot[name] = BridgeCopyResyncTable(BridgeState[name]) end
    BridgeState.resyncMappingTransaction = snapshot
end

function BridgeRestoreResyncMappingTransaction(reason)
    local snapshot = BridgeState.resyncMappingTransaction
    if snapshot == nil then return end
    for name, value in pairs(snapshot) do BridgeState[name] = value end
    BridgeState.resyncMappingTransaction = nil
    BridgeState.resyncLastBlockingPredicate = tostring(reason or "mapping-rollback")
    BridgeLog("[Bridge] RESYNC_MAPPING_ROLLBACK reason=" .. tostring(reason or "unspecified"))
end

function BridgeCommitResyncMappingTransaction()
    BridgeState.resyncMappingTransaction = nil
    BridgeState.resyncReconcileStarted = true
end

function BridgeResyncClockNow()
    if BridgePerformanceWallNow ~= nil then
        local wall = BridgePerformanceWallNow()
        if wall ~= nil then return wall end
    end
    return os.clock()
end

function BridgeRetireLocalPhysicalTransactions(reason)
    -- This only abandons TTS presentation work. Forge is not contacted and
    -- the authoritative event queue/cursors remain intact until the snapshot
    -- successfully replaces them.
    BridgeAdvancePhysicalPresentationGeneration(reason or "manual-resync-force")
    BridgeAdvancePhysicalTransactionGeneration(reason or "manual-resync-force")
    BridgeState.libraryExtractionQueueBySeatId = {}
    BridgeState.libraryExtractionActiveBySeatId = {}
    BridgeState.mulliganBottomQueueBySeatId = {}
    BridgeState.mulliganBottomInsertionActiveBySeatId = {}
    BridgeState.mulliganReturningInstanceIds = {}
    BridgeState.mulliganBottomInstanceIds = {}
    BridgeState.animationRunning = false
    BridgeState.eventDrainTransaction = nil
    BridgeLog("[Bridge] local physical transaction queues retired reason=" .. tostring(reason or "unspecified")
        .. " generation=" .. tostring(BridgeState.currentPhysicalPresentationGeneration))
end

function BridgeRestoreResyncCheckpoint(reason)
    local checkpoint = BridgeState.resyncCheckpoint
    if checkpoint == nil or checkpoint.sessionId ~= BridgeState.eventSessionId then return false end
    BridgeState.lastReceivedEventSequence = checkpoint.lastReceived
    BridgeState.lastAppliedEventSequence = checkpoint.lastApplied
    BridgeState.eventQueue = checkpoint.eventQueue
    BridgeState.resyncCheckpoint = nil
    BridgeLog(string.format("[Bridge] RESYNC_CHECKPOINT_RESTORED received=%s applied=%s reason=%s",
        tostring(checkpoint.lastReceived), tostring(checkpoint.lastApplied), tostring(reason)))
    return true
end

-- A validated authoritative snapshot supersedes the unsafe queued prefix.
-- This is essential for mulligan batches: replaying intermediate hand-return
-- events can dismantle an already-correct replacement hand and block recovery.
function BridgeSupersedeEventsThroughSnapshot(snapshotCursor, reason)
    local cursor = tonumber(snapshotCursor or 0) or 0
    local prior = BridgeState.eventQueue or {}
    local retained = {}
    local supersededCount = 0
    local firstSuperseded = nil
    local lastSuperseded = nil
    for _, event in ipairs(prior) do
        if tonumber(event.sequence or 0) > cursor then
            table.insert(retained, event)
        else
            supersededCount = supersededCount + 1
            firstSuperseded = firstSuperseded or event.sequence
            lastSuperseded = event.sequence
        end
    end
    BridgeState.eventQueue = retained
    BridgeState.lastReceivedEventSequence = math.max(
        tonumber(BridgeState.lastReceivedEventSequence or 0) or 0, cursor)
    BridgeState.lastSnapshotSupersededRange = supersededCount > 0 and {
        first = firstSuperseded, last = lastSuperseded, count = supersededCount,
        cursor = cursor, reason = reason
    } or nil
    BridgeLog(string.format("[Bridge] SNAPSHOT_CHECKPOINT_QUEUE_SUPERSEDED cursor=%s prior=%s retained=%s superseded=%s..%s(%s) reason=%s",
        tostring(cursor), tostring(#prior), tostring(#retained), tostring(firstSuperseded),
        tostring(lastSuperseded), tostring(supersededCount), tostring(reason)))
end

function BridgeCommitSnapshotCheckpoint(snapshot, reason)
    if snapshot == nil then return false, "snapshot is required for checkpoint commit" end
    local cursor = tonumber(snapshot.eventCursor)
    if cursor == nil or cursor < 0 then return false, "snapshot checkpoint has no valid cursor" end
    BridgeSetResyncStage("CommittingCheckpoint", reason or "snapshot-reconciled", snapshot)
    BridgeState.snapshotForgeSequence = snapshot.forgeSequence or BridgeState.snapshotForgeSequence or 0
    BridgeState.lastReceivedEventSequence = math.max(
        tonumber(BridgeState.lastReceivedEventSequence or 0) or 0, cursor)
    BridgeState.lastConsumedEventSequence = cursor
    BridgeState.lastStateProjectedEventSequence = cursor
    BridgeState.lastPhysicalPresentationEventSequence = cursor
    BridgeState.lastAppliedEventSequence = cursor
    BridgeSupersedeEventsThroughSnapshot(cursor, reason or "checkpoint-commit")
    BridgeState.skipExistingEventsOnAttach = false
    BridgeRecordResyncLifecycle("CHECKPOINT_COMMITTED", BridgeState.resyncOrigin,
        BridgeState.resyncBootstrapGeneration, snapshot, reason)
    return true, nil
end

function BridgeReleaseStalledResync(sessionId, token, reason)
    if BridgeState.eventSessionId ~= sessionId
        or BridgeState.resyncToken ~= token
        or BridgeState.resyncInFlight ~= true then return false end

    BridgeLog(string.format(
        "[Bridge] RESYNC_STALLED origin=%s session=%s token=%s startedAt=%s received=%s applied=%s queueLength=%s reason=%s",
        tostring(BridgeState.resyncOrigin), tostring(sessionId), tostring(token),
        tostring(BridgeState.resyncStartedAt), tostring(BridgeState.lastReceivedEventSequence),
        tostring(BridgeState.lastAppliedEventSequence), tostring(#(BridgeState.eventQueue or {})),
        tostring(reason or "watchdog")))

    -- A stalled bootstrap must stop owning the presentation.  Both the
    -- resync token and bootstrap generation fence callbacks that were already
    -- issued by the abandoned recovery; a later manual recovery can therefore
    -- start without an old callback changing its state.
    BridgeState.resyncToken = (BridgeState.resyncToken or token) + 1
    BridgeState.resyncBootstrapGeneration = (BridgeState.resyncBootstrapGeneration or 0) + 1
    BridgeState.resyncWatchdogToken = nil
    BridgeState.resyncInFlight = false
    BridgeState.resyncScheduled = false
    BridgeState.bootstrapping = false
    BridgeState.resyncStartedAt = nil
    BridgeState.resyncLastFailureReason = tostring(reason or "watchdog")
    BridgeState.resyncDeferredReason = tostring(reason or "watchdog")
    BridgeSetSchedulerOwner("NORMAL", "resync-stalled")
    BridgeState.animationRunning = false
    BridgeState.eventDrainTransaction = nil
    BridgeRestoreResyncMappingTransaction("resync-watchdog:" .. tostring(reason or "watchdog"))
    BridgeRestoreResyncCheckpoint("resync-watchdog:" .. tostring(reason or "watchdog"))
    BridgeRecordResyncLifecycle("FAILED", BridgeState.resyncOrigin, token, nil, reason,
        nil, BridgeState.lastReceivedEventSequence, BridgeState.lastAppliedEventSequence)
    if BridgeState.ui ~= nil then BridgeState.ui.resyncInFlight = false end
    BridgeSetStatus("RESYNC AVAILABLE", "Authoritative recovery stopped: " .. tostring(reason or "watchdog") .. ". Try RESYNC FORGE again.")
    BridgeUiMarkDirty("resync-stalled")
    return true
end

function BridgeCheckResyncWatchdog(reason)
    if BridgeState.resyncInFlight ~= true or BridgeState.resyncStartedAt == nil then return false end
    local now = BridgeResyncClockNow()
    if now == nil or now - BridgeState.resyncStartedAt < BRIDGE_RESYNC_STALL_SECONDS then return false end
    local token = BridgeState.resyncToken
    return BridgeReleaseStalledResync(BridgeState.eventSessionId, token, reason or "clock")
end

function BridgeScheduleResyncWatchdog(sessionId, token)
    BridgeState.resyncWatchdogToken = token
    local function check(source)
        if BridgeState.resyncWatchdogToken ~= token then return end
        BridgeReleaseStalledResync(sessionId, token, source)
    end
    -- Keep the time watchdog for normal TTS operation and add a frame/clock
    -- fallback.  A single delayed Wait.time callback must not leave the match
    -- in RESYNCING forever.
    BridgeWaitTime(function() check("time") end, BRIDGE_RESYNC_STALL_SECONDS)
    BridgeWaitFrames(function() check("frames") end, BRIDGE_RESYNC_STALL_FRAMES)
end

function BridgeResyncFromAuthoritativeSnapshot(origin)
    if BridgeState.resyncInFlight == true then
        BridgeLog("[Bridge] RESYNC_DEFERRED reason=already-in-flight origin=" .. tostring(origin))
        return false
    end
    if BridgeState.resyncCircuitOpen == true and not BridgeIsExplicitResyncOrigin(origin) then
        BridgeLog("[Bridge] RESYNC_BLOCKED reason=circuit-open rootCause=" .. tostring(BridgeState.resyncRootCause))
        BridgeSetStatus("RESYNC PAUSED", "Recovery made no progress; use manual RESYNC FORGE to retry.")
        return false
    end
    local sessionId = BridgeState.eventSessionId
    if sessionId == nil then
        BridgeShowError("cannot resync before Forge has started a session")
        BridgeLog("[Bridge] RESYNC_FAILED reason=no-session origin=" .. tostring(origin))
        return false
    end
    -- A resync requested from a library-order mismatch commonly arrives from
    -- inside the active extraction callback. Do not rebuild the snapshot while
    -- that physical transaction is still mutating the Deck; the callback's
    -- completion retires the queue and this bounded retry then starts from a
    -- stable physical order.
    local explicit = BridgeIsExplicitResyncOrigin(origin)
    if explicit then BridgeState.resyncCircuitOpen = false end
    if not BridgePhysicalLibraryQueuesIdle() then
        local now = BridgeResyncClockNow()
        if explicit and (BridgeState.manualResyncGraceUntil or 0) <= 0 then
            BridgeState.manualResyncGraceUntil = now + BRIDGE_RESYNC_PHYSICAL_QUEUE_GRACE_SECONDS
        end
        if explicit and now >= (BridgeState.manualResyncGraceUntil or 0) then
            BridgeLog("[Bridge] RESYNC_FORCE_LOCAL_RETIRE origin=" .. tostring(origin)
                .. " reason=physical-library-queue-timeout")
            BridgeRetireLocalPhysicalTransactions("manual-resync-force")
        else
            if not explicit and (BridgeState.resyncDeferredSince or 0) <= 0 then
                BridgeState.resyncDeferredSince = now
            end
            if not explicit and now - (BridgeState.resyncDeferredSince or now)
                >= BRIDGE_RESYNC_AUTOMATIC_QUEUE_GRACE_SECONDS then
                BridgeState.resyncDeferredReason = "physical-library-queue-timeout"
                BridgeLog("[Bridge] RESYNC_DEFERRED reason=physical-library-queue-timeout origin=" .. tostring(origin)
                    .. "; stopping automatic progression for manual recovery")
                BridgeStopOnDesync("automatic authoritative resync blocked by physical library queue")
                return false
            end
            BridgeState.resyncDeferredReason = "physical-library-queue"
            BridgeLog("[Bridge] RESYNC_DEFERRED reason=physical-library-queue origin=" .. tostring(origin)
                .. " graceUntil=" .. tostring(BridgeState.manualResyncGraceUntil))
            if BridgeState.resyncDeferredRetryScheduled then return false end
            BridgeState.resyncDeferredRetryScheduled = true
            BridgeWaitFrames(function()
                BridgeState.resyncDeferredRetryScheduled = false
                BridgeResyncFromAuthoritativeSnapshot(origin)
            end, 2)
            return false
        end
    end
    BridgeState.resyncDeferredSince = nil
    BridgeState.resyncDeferredRetryScheduled = false
    BridgeState.resyncScheduled = false
    if explicit then
        -- Invalidate delayed local callbacks even when the physical queues
        -- happened to look idle.  An event-drain continuation or other frame
        -- callback from the pre-resync presentation must not run against the
        -- table while the authoritative snapshot is rebuilding it.
        BridgeAdvancePhysicalTransactionGeneration("explicit-authoritative-resync")
        BridgeState.animationRunning = false
        BridgeState.eventDrainTransaction = nil
    end
    BridgeState.manualResyncGraceUntil = 0
    BridgeState.resyncDeferredReason = nil
    if BridgeState.resyncRootCause == nil then BridgeState.resyncRootCause = origin end
    BridgeState.resyncLastFailureReason = nil
    BridgeState.resyncLastProgressAt = BridgeResyncClockNow()
    -- The previous failure stopped both pollers.  Opening an explicit
    -- resync starts a new presentation generation; failures from that old
    -- generation must not remain latched against the recovery attempt.
    BridgeState.desyncLatched = false
    BridgeState.desyncLastMessage = nil
    BridgeState.resyncPresentationState = {
        currentTurnSeatId = BridgeState.currentTurnSeatId,
        currentPhase = BridgeState.currentPhase,
        prioritySeatId = BridgeState.prioritySeatId,
        tableTurnCount = BridgeState.tableTurnCount
    }
    BridgeState.resyncCheckpoint = {
        sessionId = sessionId,
        lastReceived = tonumber(BridgeState.lastReceivedEventSequence or 0) or 0,
        lastApplied = tonumber(BridgeState.lastAppliedEventSequence or 0) or 0,
        eventQueue = BridgeState.eventQueue
    }
    BridgeBeginResyncMappingTransaction()
    BridgeState.resyncToken = (BridgeState.resyncToken or 0) + 1
    local resyncToken = BridgeState.resyncToken
    BridgeState.resyncAttempt = (BridgeState.resyncAttempt or 0) + 1
    BridgeSetResyncStage("Requested", origin, nil)
    BridgeState.resyncBootstrapGeneration = (BridgeState.resyncBootstrapGeneration or 0) + 1
    BridgeState.resyncOrigin = origin
    BridgeState.resyncStartedAt = BridgeResyncClockNow()
    BridgeState.resyncInFlight = true
    BridgeState.resyncReconcileStarted = false
    BridgeState.resyncLastBlockingPredicate = nil
    BridgeSetSchedulerOwner("RESYNC", origin)
    if BridgeState.ui ~= nil and BridgeState.ui.fastForwardActive == true then
        BridgeState.fastForwardSuspendedByResync = true
        BridgeState.ui.fastForwardActive = false
        BridgeState.ui.autoAdvanceMode = "RESYNC"
    end
    if BridgeState.ui ~= nil then BridgeState.ui.resyncInFlight = true end
    local checkpointReceived = BridgeState.resyncCheckpoint.lastReceived
    local checkpointApplied = BridgeState.resyncCheckpoint.lastApplied
    BridgeScheduleResyncWatchdog(sessionId, resyncToken)
    -- Recovery is an explicit way out of a stale-choice/protocol pause.  Any
    -- outstanding request belongs to the pre-rebuild presentation and must
    -- not keep the replacement decision pipeline permanently blocked.
    BridgeState.submitting = false
    BridgeResumeChoiceProtocol("authoritative_resync")
    BridgeStopEventPolling("authoritative-resync")
    BridgeStopDecisionPolling()
    BridgeClearHighlights()
    BridgeResetSelectionState()
    BridgeHideMainPriorityControls()
    BridgeSetStatus("RESYNCING FROM FORGE", "Rebuilding physical cards from the authoritative snapshot...")
    BridgeUiMarkDirty("resync-start")
    BridgeLog("[Bridge] RESYNC_STARTED origin=" .. tostring(origin or "unknown")
        .. " session=" .. tostring(sessionId) .. " token=" .. tostring(resyncToken))
    BridgeRecordResyncLifecycle("REQUESTED", origin, resyncToken, nil, nil, nil,
        checkpointReceived, checkpointApplied)
    BridgeSetResyncStage("FetchingSnapshot", "request-started", nil)
    BridgeBootstrapCurrentSnapshot(sessionId, function(ok, err)
        if BridgeState.resyncToken ~= resyncToken or BridgeState.eventSessionId ~= sessionId then
            BridgeLog("[Bridge] RESYNC_FAILED reason=stale-callback token=" .. tostring(resyncToken))
            return
        end
        BridgeSetResyncStage(ok and "RestartingPipelines" or "Failed", ok and "snapshot-committed" or tostring(err), nil)
        BridgeState.resyncInFlight = false
        BridgeState.resyncScheduled = false
        BridgeState.resyncWatchdogToken = nil
        BridgeState.resyncStartedAt = nil
        BridgeState.resyncSnapshotFingerprint = nil
        BridgeState.resyncSnapshotRepeatCount = 0
        if BridgeState.ui ~= nil then BridgeState.ui.resyncInFlight = false end
        if not ok then
            BridgeState.resyncLastFailureReason = tostring(err)
            if string.find(tostring(err), "no progress", 1, true) ~= nil then
                BridgeState.resyncNoProgressAttempts = (BridgeState.resyncNoProgressAttempts or 0) + 1
                if BridgeState.resyncNoProgressAttempts >= 2 then
                    BridgeState.resyncCircuitOpen = true
                end
            end
            BridgeRestoreResyncMappingTransaction("bootstrap-failed:" .. tostring(err))
            BridgeRestoreResyncCheckpoint("bootstrap-failed")
            BridgeState.desyncLatched = true
            BridgeSetSchedulerOwner("NORMAL", "resync-failed")
            BridgeStopOnDesync("authoritative resync failed: " .. tostring(err))
            BridgeUiMarkDirty("resync-failed")
            BridgeLog("[Bridge] RESYNC_FAILED reason=" .. tostring(err))
            return
        end
        BridgeState.resyncCheckpoint = nil
        BridgeCommitResyncMappingTransaction()
        BridgeState.resyncNoProgressAttempts = 0
        BridgeState.resyncLastProgressAt = BridgeResyncClockNow()
        BridgeSetSchedulerOwner("NORMAL", "resync-commit")
        BridgeStartEventPolling(sessionId, false)
        BridgeState.desyncLatched = false
        BridgeState.desyncFailureCount = 0
        BridgeState.desyncLastMessage = nil
        BridgeSetStatus("RESYNCING FROM FORGE", "Checkpoint committed; reattaching the current Forge decision...")
        BridgeUiMarkDirty("resync-complete")
        BridgeLog("[Bridge] RESYNC_COMPLETE eventCursor="
            .. tostring(BridgeState.lastAppliedEventSequence))
        -- Reattach exactly one authoritative decision after the checkpoint.
        -- Polling while resync is active was the captured infinite loop: the
        -- decision was valid, but it could not be accepted against cursor 0.
        local decisionSession = BridgeState.eventSessionId
        local decisionGeneration = BridgeState.decisionPresentationGeneration
        BridgeGetDecision(function(decisionOk, decision, decisionErr)
            if BridgeState.resyncToken ~= resyncToken
                or BridgeState.eventSessionId ~= decisionSession
                or BridgeState.decisionPresentationGeneration ~= decisionGeneration then
                return
            end
            if decisionOk and decision ~= nil then
                BridgeAcceptDecision(decision, "resync-decision-reattach", decisionSession, decisionGeneration)
            else
                BridgeLog("[Bridge] RESYNC_DECISION_REATTACH_FAILED reason=" .. tostring(decisionErr))
                BridgeStartDecisionPolling()
            end
            BridgeSetStatus("MATCH ACTIVE", "Physical table resynced from Forge.")
            BridgeUiMarkDirty("resync-complete")
            BridgeRecordResyncLifecycle("COMPLETED", origin, resyncToken, decision, nil, nil, nil, nil)
            BridgeSetResyncStage("Completed", "pipelines-restarted", decision)
        end)
    end, true, origin)
    return true
end

-- Forge's snapshot is the only authoritative library order after its shuffle.
-- The physical importer deck begins in its own order, so merely matching card
-- names is insufficient: the first later draw can otherwise reveal a valid
-- but wrong physical card. Reinsert each expected card from bottom to top at
-- TTS's explicit top index (0). Do not rely on putObject's default insertion
-- behavior: that default is not an ordering contract across Deck/Card merges.
function BridgeSnapshotLibraryOrderAlreadyMatches(seatSnapshot)
    local libraryCards = {}
    for _, zone in ipairs(seatSnapshot.zones or {}) do
        if zone.name == "library" then
            for _, card in ipairs(zone.cards or {}) do table.insert(libraryCards, card) end
            break
        end
    end
    if #libraryCards == 0 then return true end
    for _, card in ipairs(libraryCards) do
        if card.zonePosition == nil then return false end
    end
    table.sort(libraryCards, function(left, right)
        return (tonumber(left.zonePosition or 0) or 0) < (tonumber(right.zonePosition or 0) or 0)
    end)
    local deck = BridgeResolveSeatLibraryDeck(seatSnapshot.seatId)
    if deck == nil or deck.tag ~= "Deck" then return false end
    local entries = BridgeLibraryEntries(deck)
    if entries == nil or #entries ~= #libraryCards then return false end
    for index, card in ipairs(libraryCards) do
        local entry = entries[index]
        local entryName = entry and (entry.nickname or entry.name or entry.Name) or ""
        if BridgeNormalizeCardName(entryName) ~= BridgeNormalizeCardName(card.cardName) then
            return false
        end
    end
    return true
end

function BridgeAlignLibraryOrderForSnapshot(seatSnapshot, callback)
    local libraryCards = {}
    for _, zone in ipairs(seatSnapshot.zones or {}) do
        if zone.name == "library" then
            for _, card in ipairs(zone.cards or {}) do table.insert(libraryCards, card) end
            break
        end
    end
    if #libraryCards == 0 then callback(true, nil); return end
    table.sort(libraryCards, function(left, right)
        return (tonumber(left.zonePosition or 0) or 0) < (tonumber(right.zonePosition or 0) or 0)
    end)

    local deck, _, deckError = BridgeResolveSeatLibraryDeck(seatSnapshot.seatId)
    if deck == nil then
        callback(false, "library order alignment could not resolve library: " .. tostring(deckError))
        return
    end
    if deck.tag == "Card" then
        if #libraryCards ~= 1 or not BridgeCardNameMatches(deck.getName(), libraryCards[1].cardName) then
            callback(false, "library order alignment found a single-card library that disagrees with Forge")
            return
        end
        callback(true, nil)
        return
    end
    -- Mulligan recovery often arrives after the final replacement hand and
    -- library are already physically correct. Avoid re-extracting every
    -- hidden library card in that case; a mismatch still takes the full
    -- authoritative repair path below.
    if BridgeSnapshotLibraryOrderAlreadyMatches(seatSnapshot) then
        callback(true, nil)
        return
    end
    local entries = BridgeLibraryEntries(deck)
    if entries == nil or #entries ~= #libraryCards then
        callback(false, string.format("library order alignment count mismatch: physical=%d authoritative=%d",
            #(entries or {}), #libraryCards))
        return
    end
    local seat = BRIDGE_SEATS[seatSnapshot.seatId]
    local libraryZone = seat and BridgeGetLiveObjectByGuid(seat.libraryZoneGuid) or nil
    if libraryZone == nil then
        callback(false, "library order alignment has no library zone")
        return
    end
    local position = libraryZone.getPosition()
    local nextIndex = #libraryCards
    local function reinsertNext()
        if nextIndex < 1 then callback(true, nil); return end
        local expected = libraryCards[nextIndex]
        local liveDeck, _, liveError = BridgeResolveSeatLibraryDeck(seatSnapshot.seatId)
        if liveDeck == nil then
            callback(false, "library order alignment lost physical library: " .. tostring(liveError))
            return
        end
        BridgeTakeCardFromDeckByIdentity(liveDeck, expected.cardName,
            {position.x, position.y + 2, position.z}, false,
            function(taken, takeError)
                if taken == nil then
                    callback(false, "library order alignment could not take " .. tostring(expected.cardName)
                        .. ": " .. tostring(takeError))
                    return
                end
                local target, _, targetError = BridgeResolveSeatLibraryDeck(seatSnapshot.seatId)
                if target == nil then
                    callback(false, "library order alignment lost remaining deck: " .. tostring(targetError))
                    return
                end
                local inserted = BridgeSafeObjectCall(target, function(current)
                    current.setLock(false)
                    current.putObject(taken, 0)
                end)
                if not inserted then
                    callback(false, "library order alignment could not reinsert " .. tostring(expected.cardName))
                    return
                end
                nextIndex = nextIndex - 1
                BridgeWaitFrames(reinsertNext, 2)
            end)
    end
    reinsertNext()
end

function BridgeTryBootstrapSeatSnapshot(seatSnapshot, attempt, callback)
    BridgeCollectSeatAssets(seatSnapshot.seatId, seatSnapshot, function(ok, assets, collectError)
        if not ok then callback(false, collectError); return end
        local reconciled, reconcileError = BridgeReconcileSeatSnapshot(seatSnapshot, assets, attempt >= 4)
        if not reconciled then
            if attempt < 4 then
                local authoritativeCount = 0
                for _, zone in ipairs(seatSnapshot.zones or {}) do
                    authoritativeCount = authoritativeCount + #(zone.cards or {})
                end
                BridgeLog(string.format(
                    "[Bridge] seat asset inventory not ready: seat=%s attempt=%d physical=%d authoritative=%d; retrying",
                    tostring(seatSnapshot.seatId), attempt, #assets, authoritativeCount))
                BridgeWaitFrames(function()
                    BridgeTryBootstrapSeatSnapshot(seatSnapshot, attempt + 1, callback)
                end, 60)
                return
            end
            callback(false, reconcileError)
            return
        end
        BridgeMaterializeSeatSnapshot(seatSnapshot, 1, 1, function(materialized, materializeError)
-- END GENERATED SOURCE: 30-input-identity.lua
-- BEGIN GENERATED SOURCE: 40-zones-materialization.lua
            if not materialized then callback(false, materializeError); return end
            -- Materialization removes the snapshot hand and public-zone cards
            -- from the imported deck first. Only then does the remaining deck
            -- exactly correspond to Forge's library and become safe to order.
            BridgeAlignLibraryOrderForSnapshot(seatSnapshot, function(aligned, alignmentError)
                if not aligned then callback(false, alignmentError); return end
                BridgeWaitFrames(function()
                    BridgeApplySeatSnapshotVisualState(seatSnapshot)
                    callback(true, nil)
                end, 30)
            end)
        end)
    end)
end

function BridgeCollectSeatAssets(seatId, seatSnapshot, callback)
    local seat = BRIDGE_SEATS[seatId]
    local assets = {}
    local assetByGuid = {}
    -- Reuse one TTS object snapshot for both library discovery and candidate
    -- collection.  TTS getAllObjects() is a native boundary and can take
    -- hundreds of milliseconds in a large table; scanning it twice during
    -- bootstrap needlessly amplifies a freeze already visible in diagnostics.
    local objectSnapshot = _all()
    -- Resolve the library once. BridgeResolveSeatLibraryDeck scans the TTS
    -- object list; doing that for every candidate made bootstrap O(n^2) and
    -- was the measured multi-second freeze hot path.
    local library = BridgeResolveSeatLibraryDeck(seatId, objectSnapshot)
    local libraryGuid = BridgeSafeObjectGuid(library)
    local context = {
        expectedCardNamesBySeat = {},
        handGuidsBySeat = {}
    }
    context.expectedCardNamesBySeat[seatId] = BridgeExpectedCardNamesForSeatSnapshot(seatSnapshot)
    context.handGuidsBySeat[seatId] = BridgeBuildSeatHandGuidSet(seatId)
    BridgeTraceStart("START-14 library-indexing", tostring(seatId))

    local function addAsset(object)
        if not BridgeObjectIsUsable(object) or object.tag ~= "Card" then return end
        if libraryGuid ~= nil and libraryGuid == BridgeSafeObjectGuid(object) then return end
        if not IsGameCardCandidate(object, seatId, context) then return end
        local guid = BridgeSafeObjectGuid(object)
        local cardName = BridgePhysicalCanonicalCardName(object)
        if guid == nil or assetByGuid[guid] then return end
        assetByGuid[guid] = true
        table.insert(assets, {
            guid = guid,
            cardName = cardName,
            object = object
        })
    end

    -- TTS hand objects are not guaranteed to be present in getAllObjects().
    -- Index them explicitly so preserving hands does not make the inventory
    -- audit under-count the authoritative card set.
    local handObjects, handError = BridgeTryGetSeatHandObjects(seatId)
    if handObjects == nil then
        callback(false, nil, handError)
        return
    end
    for _, object in ipairs(handObjects) do addAsset(object) end

    for _, object in ipairs(objectSnapshot) do
        addAsset(object)
    end
    callback(true, assets, nil)
end

function BridgeBuildSeatLibraryLedger(seatSnapshot)
    local seatId = seatSnapshot.seatId
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then
        return nil, "library ledger has no configured seat " .. tostring(seatId)
    end

    local deck, _, deckError = BridgeResolveSeatLibraryDeck(seatId)
    if deck == nil then
        return nil, "library ledger cannot resolve deck for seat " .. tostring(seatId) .. ": " .. tostring(deckError)
    end
    if not BridgeObjectIsUsable(deck) then
        return nil, "library ledger resolved an unusable deck object for seat " .. tostring(seatId)
    end
    local deckGuid = BridgeSafeObjectGuid(deck)
    if deckGuid == nil then
        return nil, "library ledger resolved a deck with no GUID for seat " .. tostring(seatId)
    end

    local containedCards = {}
    if deck.tag == "Card" then
        local guid = BridgeSafeObjectGuid(deck)
        if guid == nil then return nil, "single-card library has no GUID for seat " .. tostring(seatId) end
        if not BridgeRequireArtBearingLibraryCard(deck, seatId, nil) then
            return nil, "single-card library contains an artless normal game card for seat " .. tostring(seatId)
        end
        table.insert(containedCards, {guid = guid, nickname = BridgePhysicalCanonicalCardName(deck), index = 1})
    else
        local containedOk = pcall(function() containedCards = deck.getObjects() or {} end)
        if not containedOk then
            return nil, "library ledger could not inspect deck contents for seat " .. tostring(seatId)
        end
    end

    table.sort(containedCards, function(left, right)
        local leftIndex = tonumber(left.index or -1) or -1
        local rightIndex = tonumber(right.index or -1) or -1
        if leftIndex == rightIndex then
            return tostring(left.guid or "") < tostring(right.guid or "")
        end
        return leftIndex < rightIndex
    end)

    local byName = {}
    local countByName = {}
    for _, contained in ipairs(containedCards) do
        if contained.guid ~= nil then
            local containedName = contained.nickname or contained.name or ""
            local normalizedName = BridgeNormalizeCardName(containedName)
            local entry = {
                guid = contained.guid,
                normalizedName = normalizedName,
                cardName = containedName,
                index = tonumber(contained.index or -1) or -1
            }
            byName[normalizedName] = byName[normalizedName] or {}
            table.insert(byName[normalizedName], entry)
            countByName[normalizedName] = (countByName[normalizedName] or 0) + 1
        end
    end

    return {
        deck = deck,
        deckGuid = deckGuid,
        byName = byName,
        countByName = countByName
    }, nil
end

function BridgeObjectIsOnSeatSide(object, seat)
    if seat == nil or not BridgeObjectIsUsable(object) then return false end
    local okPosition, position = pcall(function() return object.getPosition() end)
    if not okPosition or position == nil then return false end
    if seat.assetMaxAbsX ~= nil and math.abs(position.x) > seat.assetMaxAbsX then
        return false
    end
    if object.tag == "Deck" then
        local libraryZone = BridgeGetLiveObjectByGuid(seat.libraryZoneGuid)
        if libraryZone == nil then return false end
        local okLibraryPos, libraryPosition = pcall(function() return libraryZone.getPosition() end)
        if not okLibraryPos or libraryPosition == nil then return false end
        local dx = position.x - libraryPosition.x
        local dz = position.z - libraryPosition.z
        local radius = seat.libraryAssetRadius or 4
        return dx * dx + dz * dz <= radius * radius
    end
    if seat.tableSideZ < 0 then return position.z < -0.25 end
    return position.z > 0.25
end

function BridgeLibraryMismatchMessage(seatId, cardName, expected, contained, loose)
    return string.format("LIBRARY MISMATCH\nseat=%s\ncard=%s\nexpected=%d\ndeck=%d\nloose=%d",
        tostring(seatId), tostring(cardName), expected, contained, loose)
end

-- Importers commonly put set/collector metadata below the printed card name.
-- Forge deck input needs only the stable front/imported identity.
function BridgeImportedCardName(name)
    local imported = tostring(name or "")
    imported = string.gsub(imported, "\r", "\n")
    local lineBreak = string.find(imported, "\n", 1, true)
    if lineBreak ~= nil then imported = string.sub(imported, 1, lineBreak - 1) end
    local separator = string.find(imported, " // ", 1, true)
    if separator ~= nil then imported = string.sub(imported, 1, separator - 1) end
    imported = string.gsub(imported, "^%s+", "")
    imported = string.gsub(imported, "%s+$", "")
    return imported
end

function BridgeInventoryRejectionReason(object, seatId, context)
    if BridgeIsPresentationOnlyObject(object) then
        local metadata = BridgeState.presentationOnlyGuids[BridgeSafeObjectGuid(object)] or {}
        return "presentation_only:" .. tostring(metadata.kind or "presentation")
    end
    if object.tag ~= "Card" and object.tag ~= "Deck" then return "not_card_or_deck" end
    local guid = BridgeSafeObjectGuid(object)
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then return "unknown_seat" end
    if seat.excludeCardGuids and seat.excludeCardGuids[guid] then return "seat_excluded" end
    if seat.includeCardGuids and seat.includeCardGuids[guid] then return "seat_included" end
    if BridgeState.physicalSeatByGuid[guid] == seatId then return "tracked_for_seat" end
    local hands = context and context.handGuidsBySeat or {}
    for configuredSeatId, handGuids in pairs(hands or {}) do
        if handGuids and handGuids[guid] then
            return configuredSeatId == seatId and "seat_hand" or "other_seat_hand:" .. tostring(configuredSeatId)
        end
    end
    if not BridgeObjectIsOnSeatSide(object, seat) then return "outside_seat_side" end
    if object.tag == "Deck" then return "seat_side_deck" end
    local expected = context and context.expectedCardNamesBySeat and context.expectedCardNamesBySeat[seatId] or nil
    if expected and expected[BridgeNormalizeCardName(BridgePhysicalCanonicalCardName(object))] then return "expected_name" end
    if BridgeCardMetadataLooksLikeMtg(object) then return "mtg_metadata" end
    if BridgeCardFootprintLooksLikeMtg(object) then return "mtg_footprint" end
    return "not_mtg_candidate"
end

function BridgeLogLibraryMismatchInventory(seatSnapshot, failedName, displayName)
    local seatId = seatSnapshot.seatId
    local context = BridgeBuildGameCardContext({seats = {seatSnapshot}})
    context.handGuidsBySeat[seatId] = BridgeBuildSeatHandGuidSet(seatId)
    -- Include all seats' hands solely to explain why an object was rejected.
    for configuredSeatId, _ in pairs(BRIDGE_SEATS) do
        context.handGuidsBySeat[configuredSeatId] = BridgeBuildSeatHandGuidSet(configuredSeatId)
    end
    BridgeLog("[Bridge] LIBRARY MISMATCH INVENTORY seat=" .. tostring(seatId) .. " card=" .. tostring(displayName or failedName))
    for _, object in ipairs(getAllObjects()) do
        if BridgeObjectIsUsable(object) and (object.tag == "Card" or object.tag == "Deck") then
            local canonical = BridgePhysicalCanonicalCardName(object)
            local containedCount = 0
            if object.tag == "Deck" then
                local ok, contained = pcall(function() return object.getObjects() or {} end)
                if ok then
                    for _, entry in ipairs(contained) do
                        if BridgeNormalizeCardName(entry.nickname or entry.name or "") == failedName then containedCount = containedCount + 1 end
                    end
                end
            end
            if BridgeNormalizeCardName(canonical) == failedName or containedCount > 0 then
                local guid = BridgeSafeObjectGuid(object)
                local position = object.getPosition()
                local nearest = BridgeNearestSeatIdForPosition(position, {"forge-player-1", "forge-player-2"})
                local handSeat = nil
                for configuredSeatId, handGuids in pairs(context.handGuidsBySeat) do
                    if handGuids and handGuids[guid] then handSeat = configuredSeatId end
                end
                BridgeLog(string.format(
                    "[Bridge] inventory guid=%s tag=%s name=%s canonical=%s pos=(%.2f,%.2f,%.2f) nearestSeat=%s presentationOnly=%s candidate=%s mappedForgeInstance=%s trackedZone=%s handSeat=%s containedCount=%d reason=%s",
                    tostring(guid), tostring(object.tag), tostring(BridgeSafeObjectName(object)), tostring(canonical),
                    tonumber(position.x) or 0, tonumber(position.y) or 0, tonumber(position.z) or 0,
                    tostring(nearest), tostring(BridgeIsPresentationOnlyObject(object)),
                    tostring(IsGameCardCandidate(object, seatId, context)),
                    tostring(BridgeState.physicalInstanceIdByGuid[guid]), tostring(BridgeState.physicalZoneByGuid[guid]),
                    tostring(handSeat), containedCount, BridgeInventoryRejectionReason(object, seatId, context)))
            end
        end
    end
end

function BridgeReconcileSeatSnapshot(seatSnapshot, assets, includeInventoryDiagnostic)
    local handByName = {}
    local nonHandByName = {}
    local looseCountByName = {}
    local assetByGuid = {}
    local mappings = {}
    local handGuids = BridgeBuildSeatHandGuidSet(seatSnapshot.seatId)
    for _, asset in ipairs(assets) do
        local name = BridgeNormalizeCardName(asset.cardName)
        local assetGuid = asset.guid or (asset.object and BridgeSafeObjectGuid(asset.object))
        local destination = handGuids[assetGuid] == true and handByName or nonHandByName
        destination[name] = destination[name] or {}
        table.insert(destination[name], asset)
        if assetGuid ~= nil then assetByGuid[tostring(assetGuid)] = asset end
        looseCountByName[name] = (looseCountByName[name] or 0) + 1
    end

    local ledger, ledgerError = BridgeBuildSeatLibraryLedger(seatSnapshot)
    if ledger == nil then
        return false, ledgerError
    end

    local authoritativeCards = {}
    local authoritativeCountByName = {}
    local authoritativeDisplayNameByName = {}
    for _, zone in ipairs(seatSnapshot.zones or {}) do
        for _, card in ipairs(zone.cards or {}) do
            table.insert(authoritativeCards, {zoneName = zone.name, card = card})
            local normalized = BridgeNormalizeCardName(card.cardName)
            authoritativeCountByName[normalized] = (authoritativeCountByName[normalized] or 0) + 1
            authoritativeDisplayNameByName[normalized] = authoritativeDisplayNameByName[normalized] or card.cardName
        end
    end

    for normalizedName, expectedCount in pairs(authoritativeCountByName) do
        local looseCount = looseCountByName[normalizedName] or 0
        local containedCount = ledger.countByName[normalizedName] or 0
        local physicalCount = looseCount + containedCount
        if physicalCount < expectedCount then
            local deficit = expectedCount - physicalCount
            local displayName = authoritativeDisplayNameByName[normalizedName] or normalizedName
            local detail = string.format(
                "library reconciliation failed: seat=%s card=%s forgeExpectedTotal=%d containedPhysicalTotal=%d loosePhysicalTotal=%d physicalTotal=%d deficit=%d unmappedForgeInstances=%d",
                tostring(seatSnapshot.seatId), tostring(displayName), expectedCount, containedCount, looseCount,
                physicalCount, deficit, deficit)
            BridgeLog("[Bridge] " .. detail)
            if includeInventoryDiagnostic then BridgeLogLibraryMismatchInventory(seatSnapshot, normalizedName, displayName) end
            return false, BridgeLibraryMismatchMessage(seatSnapshot.seatId, displayName, expectedCount, containedCount, looseCount)
        end
    end

    local assignedByName = {}
    local assignedContainedByName = {}
    for _, mapped in ipairs(authoritativeCards) do
        local card = mapped.card
        local zoneName = mapped.zoneName
        local normalized = BridgeNormalizeCardName(card.cardName)
        local assigned = nil

        local function consumeContained()
            local containedCandidates = ledger.byName[normalized] or {}
            while #containedCandidates > 0 and containedCandidates[1].assigned == true do
                table.remove(containedCandidates, 1)
            end
            if #containedCandidates > 0 then
                local contained = table.remove(containedCandidates, 1)
                contained.assigned = true
                assigned = {
                    cardName = contained.cardName,
                    object = nil
                }
                assignedContainedByName[normalized] = (assignedContainedByName[normalized] or 0) + 1
            end
        end
        local function consumeLoose()
            -- TTS can expose hand cards in a different order from getAllObjects.
            -- Reserve those exact hand members for the authoritative hand zone;
            -- otherwise duplicate names can cross-link a hand card with a
            -- battlefield card and opening-hand readiness will correctly reject
            -- the resulting mapping.
            local looseCandidates = zoneName == "hand"
                and (handByName[normalized] or {})
                or (nonHandByName[normalized] or {})
            while #looseCandidates > 0 and looseCandidates[1].assigned == true do
                table.remove(looseCandidates, 1)
            end
            if #looseCandidates > 0 then
                assigned = table.remove(looseCandidates, 1)
                assigned.assigned = true
            end
        end

        -- Same-session resync preserves live public mappings. Prefer that exact
        -- GUID before any duplicate-name fallback so a played land or already
        -- milled card can never be replaced by another copy from the library.
        local preservedGuid = BridgeState.physicalByInstanceId[card.cardInstanceId]
        local preservedAsset = preservedGuid and assetByGuid[tostring(preservedGuid)] or nil
        -- A failed asynchronous move can retire the forward index before the
        -- reverse index is rebuilt. Recover the exact live asset by identity;
        -- never fall through to duplicate-name matching in that case.
        if preservedAsset == nil then
            for guid, mappedInstanceId in pairs(BridgeState.physicalInstanceIdByGuid or {}) do
                if mappedInstanceId == card.cardInstanceId then
                    local reverseAsset = assetByGuid[tostring(guid)]
                    if reverseAsset ~= nil then
                        preservedGuid = guid
                        preservedAsset = reverseAsset
                        break
                    end
                end
            end
        end
        if preservedAsset ~= nil and preservedAsset.assigned ~= true then
            assigned = preservedAsset
            preservedAsset.assigned = true
        elseif zoneName == "library" then
            consumeContained()
            if assigned == nil then consumeLoose() end
        else
            consumeLoose()
            if assigned == nil then consumeContained() end
        end

        if assigned == nil then
            local expectedCount = authoritativeCountByName[normalized] or 0
            local displayName = authoritativeDisplayNameByName[normalized] or card.cardName or normalized
            local containedCount = ledger.countByName[normalized] or 0
            local looseCount = looseCountByName[normalized] or 0
            local alreadyAssigned = assignedByName[normalized] or 0
            local unmappedForgeInstances = math.max(expectedCount - alreadyAssigned, 1)
            local containedAssigned = assignedContainedByName[normalized] or 0
            local looseAssigned = alreadyAssigned - containedAssigned
            local containedRemaining = math.max(containedCount - containedAssigned, 0)
            local looseRemaining = math.max(looseCount - looseAssigned, 0)
            local detail = string.format(
                "library reconciliation assignment failed: seat=%s card=%s forgeExpectedTotal=%d containedPhysicalTotal=%d loosePhysicalTotal=%d containedAssigned=%d looseAssigned=%d containedRemaining=%d looseRemaining=%d unmappedForgeInstances=%d",
                tostring(seatSnapshot.seatId), tostring(displayName), expectedCount, containedCount, looseCount,
                containedAssigned, looseAssigned, containedRemaining, looseRemaining, unmappedForgeInstances)
            BridgeLog("[Bridge] " .. detail)
            if includeInventoryDiagnostic then BridgeLogLibraryMismatchInventory(seatSnapshot, normalized, displayName) end
            return false, BridgeLibraryMismatchMessage(seatSnapshot.seatId, displayName, expectedCount, containedCount, looseCount)
        end

        assignedByName[normalized] = (assignedByName[normalized] or 0) + 1
        table.insert(mappings, {card = card, asset = assigned, zoneName = zoneName})
    end

    -- Publish mappings only after every authoritative card has a physical
    -- counterpart. A retry must never inherit a partially reconciled seat.
    for _, mapping in ipairs(mappings) do
        BridgeState.cardNameByInstanceId[mapping.card.cardInstanceId] = mapping.card.cardName
        local guid = mapping.asset.guid
        if mapping.zoneName == "library" or guid == nil then
            BridgeRecordLibraryContainedState(mapping.card.cardInstanceId, seatSnapshot.seatId, mapping.card.cardName)
        else
            BridgeRecordLooseCardIdentity(mapping.card.cardInstanceId, guid, seatSnapshot.seatId, mapping.zoneName)
            if mapping.asset.object ~= nil then
                BridgeState.untappedRotationByGuid[guid] = mapping.asset.object.getRotation()
            end
        end
    end
    BridgeTraceStart("START-17 mapping-complete", tostring(seatSnapshot.seatId))
    BridgeAdvancePhysicalPresentationGeneration("bootstrap-complete")
    return true, nil
end

function BridgeMaterializeSeatSnapshot(seatSnapshot, zoneIndex, cardIndex, callback)
    local zones = seatSnapshot.zones or {}
    if zoneIndex > #zones then callback(true, nil); return end
    local zone = zones[zoneIndex]
    local cards = zone.cards or {}

    if zone.name == "library" or cardIndex > #cards then
        BridgeMaterializeSeatSnapshot(seatSnapshot, zoneIndex + 1, 1, callback)
        return
    end

    local card = cards[cardIndex]
    -- Forge may expose transient copies (for example a copied spell on the
    -- stack) that are intentionally virtual. Keep their authoritative
    -- identity in bridge state, but never invent a physical deck card.
    if card.isVirtual == true or tostring(card.materializationPolicy or "") == "virtual"
        or tostring(card.materializationPolicy or "") == "virtual-stack" then
        BridgeState.authoritativeObjectByInstanceId[card.cardInstanceId] = {
            objectId = card.authoritativeObjectId or card.cardInstanceId,
            originObjectId = card.originObjectId,
            copySourceObjectId = card.copySourceObjectId,
            objectKind = card.objectKind,
            isCopy = card.isCopy == true,
            isVirtual = true,
            materializationPolicy = card.materializationPolicy
        }
        BridgeMaterializeSeatSnapshot(seatSnapshot, zoneIndex, cardIndex + 1, callback)
        return
    end
    local guid = BridgeState.physicalByInstanceId[card.cardInstanceId]

    local function continueWith(object)
        if card.isToken ~= true and not BridgeRequireArtBearingLibraryCard(object, seatSnapshot.seatId, card.cardInstanceId) then
            callback(false, "snapshot materialization rejected an artless normal game card")
            return
        end
        local actualGuid = object.getGUID()
        if guid ~= nil and actualGuid ~= guid then
            BridgeState.physicalSeatByGuid[guid] = nil
            BridgeState.physicalZoneByGuid[guid] = nil
        end
        local recorded, recordError = BridgeRecordLooseCardIdentity(card.cardInstanceId, actualGuid, seatSnapshot.seatId, zone.name)
        if not recorded then
            callback(false, recordError or "snapshot physical identity registration failed")
            return
        end
        BridgeState.cardNameByInstanceId[card.cardInstanceId] = card.cardName
        local placed, placeError = BridgePlaceSnapshotCard(object, card, zone, seatSnapshot)
        if not placed then
            callback(false, placeError)
            return
        end
        BridgeWaitFrames(function()
            BridgeMaterializeSeatSnapshot(seatSnapshot, zoneIndex, cardIndex + 1, callback)
        end, 2)
    end

    local object = guid and BridgeGetLiveObjectByGuid(guid) or nil
    if object ~= nil then continueWith(object); return end

    -- A Forge copy of a permanent has no deck inventory entry. When Forge
    -- supplies the exact copied-permanent identity, clone that already-
    -- materialized physical presentation as a starting surface, then apply
    -- the copy's authoritative characteristics below. The creating effect
    -- (originObjectId) is provenance, not the clone source. The clone receives
    -- the copy's own CardInstanceId and never steals the source mapping.
    local copySourceObjectId = card.copySourceObjectId or card.originObjectId
    if card.isCopy == true and copySourceObjectId ~= nil then
        local originGuid = BridgeState.physicalByInstanceId[copySourceObjectId]
        local origin = originGuid and BridgeGetLiveObjectByGuid(originGuid) or nil
        if origin ~= nil and type(origin.clone) == "function" then
            local cloned = nil
            local ok = pcall(function()
                cloned = origin.clone({position = origin.getPosition(), rotation = origin.getRotation()})
            end)
            if ok and cloned ~= nil then
                continueWith(cloned)
                return
            end
        end
    end

    local function tryTokenFallback(takeError)
        if card.isToken ~= true then
            callback(false, "ordinary deck card was not found in its authoritative physical zone: " .. tostring(takeError))
            return true
        end
        if zone.name ~= "battlefield" and zone.name ~= "graveyard" and zone.name ~= "exile" and zone.name ~= "command" then
            callback(false, takeError)
            return true
        end
        BridgeTakeCardFromTokenFetcher(card.cardName, seatSnapshot.seatId, function(taken, tokenError)
            if taken == nil then
                callback(false, "snapshot token fetcher has no matching card for " .. tostring(card.cardName)
                    .. ": " .. tostring(tokenError))
                return
            end
            continueWith(taken)
        end)
        return false
    end

    local seat = BRIDGE_SEATS[seatSnapshot.seatId]
    if BridgeState.resyncInFlight == true then
        -- Exact same-session public mappings have already been preferred and
        -- retained above. Any remaining deck extraction is therefore limited
        -- to an object that is genuinely still contained in the library; keep
        -- this diagnostic visible because a name-only fallback is only a
        -- recovery path, never an identity source.
        BridgeLog("[Bridge] resync materialization using contained-library fallback for unmapped public card")
    end
    local deck = BridgeFindSeatLibraryDeckWithCard(seat, card.cardName)
    if deck == nil then deck = BridgeFindLibraryDeckForSeat(seatSnapshot.seatId) end
    if deck == nil then
        local terminal = tryTokenFallback("snapshot card identity is not present in the resolved physical library deck")
        if terminal then return end
        return
    end

    local libraryZone = BridgeGetLiveObjectByGuid(seat.libraryZoneGuid)
    if libraryZone == nil then
        callback(false, "snapshot card staging failed: missing library zone for seat " .. tostring(seatSnapshot.seatId))
        return
    end
    local staging = libraryZone.getPosition()
    BridgeTakeCardFromDeckByIdentity(
        deck,
        card.cardName,
        {staging.x + 4, staging.y + 2, staging.z},
        false,
        function(taken, takeError)
            if taken == nil then
                local terminal = tryTokenFallback(takeError)
                if terminal then return end
                return
            end
            continueWith(taken)
        end)
end

function BridgePlaceSnapshotCard(object, card, zone, seatSnapshot)
    if not BridgeObjectIsUsable(object) then
        return false, "snapshot placement target object is unavailable"
    end
    local seat = BRIDGE_SEATS[seatSnapshot.seatId]
    if zone.name == "library" then
        local libraryZone = BridgeGetLiveObjectByGuid(seat.libraryZoneGuid)
        if libraryZone == nil then
            return false, "missing library zone for seat " .. tostring(seatSnapshot.seatId)
        end
        local position = libraryZone.getPosition()
        local count = #(zone.cards or {})
        local moved = BridgeSafeObjectCall(object, function(o)
            o.use_hands = false
            o.setPosition({position.x, position.y + 1.5 + (count - card.zonePosition) * 0.025, position.z})
        end)
        if not moved then return false, "failed to place library card for seat " .. tostring(seatSnapshot.seatId) end
        return true, nil
    end
    BridgeSetPhysicalFaceDown(object, seat, card.faceDown == true)
    if zone.name == "hand" then
        BridgeTraceStart("START-15 hand-reconstruction", tostring(seatSnapshot.seatId))
        local hand, handError = BridgeTryGetSeatHandTransform(seatSnapshot.seatId)
        if hand == nil then
            return false, handError
        end
        local moved = BridgeSafeObjectCall(object, function(o)
            o.use_hands = true
            o.setPosition({hand.position.x + (card.zonePosition - (#zone.cards - 1) / 2) * 1.2, hand.position.y, hand.position.z})
        end)
        if not moved then return false, "failed to place hand card for seat " .. tostring(seatSnapshot.seatId) end
        return true, nil
    end
    if not BridgeSafeObjectCall(object, function(o) o.use_hands = false end) then
        return false, "failed to clear hand interaction while placing card"
    end
    if zone.name == "battlefield" then
        BridgeTraceStart("START-16 battlefield-reconstruction", tostring(seatSnapshot.seatId))
        local row = card.battlefieldKind == "land" and "land" or "creature"
        local position, positionError = BridgeBattlefieldPosition(seatSnapshot.seatId, row)
        if position == nil then
            BridgeStopOnDesync(positionError)
            return false, positionError
        end
        object.setPosition(position)
        local rowKey = seatSnapshot.seatId .. ":" .. row
        BridgeState.battlefieldCounts[rowKey] = (BridgeState.battlefieldCounts[rowKey] or 0) + 1
    elseif zone.name == "graveyard" then
        local position = BridgeResolveSeatZoneAnchor(seatSnapshot.seatId, "graveyard")
        if position == nil then
            return false, "missing graveyard anchor for seat " .. tostring(seatSnapshot.seatId)
        end
        if not BridgeSafeObjectCall(object, function(o) o.setPosition(position) end) then
            return false, "failed to place graveyard card for seat " .. tostring(seatSnapshot.seatId)
        end
    elseif zone.name == "exile" then
        local position = BridgeResolveSeatZoneAnchor(seatSnapshot.seatId, "exile")
        if position == nil then
            return false, "missing exile anchor for seat " .. tostring(seatSnapshot.seatId)
        end
        if not BridgeSafeObjectCall(object, function(o) o.setPosition(position) end) then
            return false, "failed to place exile card for seat " .. tostring(seatSnapshot.seatId)
        end
    elseif zone.name == "command" then
        local position = BridgeResolveSeatZoneAnchor(seatSnapshot.seatId, "command")
        if position == nil then return false, "missing command anchor for seat " .. tostring(seatSnapshot.seatId) end
        if not BridgeSafeObjectCall(object, function(o) o.setPosition(position) end) then
            return false, "failed to place command card for seat " .. tostring(seatSnapshot.seatId)
        end
    end
    return true, nil
end

function BridgeApplySeatSnapshotVisualState(seatSnapshot)
    local seat = BRIDGE_SEATS[seatSnapshot.seatId]
    BridgeState.playerCountersBySeatId[seatSnapshot.seatId] = {}
    for counterKind, counterValue in pairs(seatSnapshot.counters or {}) do
        BridgeState.playerCountersBySeatId[seatSnapshot.seatId][BridgeNormalizeCounterName(counterKind)] = tonumber(counterValue) or 0
    end
    BridgeState.playerStateBySeatId[seatSnapshot.seatId] = BridgeState.playerStateBySeatId[seatSnapshot.seatId] or {}
    BridgeState.playerStateBySeatId[seatSnapshot.seatId].life = seatSnapshot.life
    BridgeState.playerStateBySeatId[seatSnapshot.seatId].poison = seatSnapshot.poison
    BridgeState.playerStateBySeatId[seatSnapshot.seatId].counters = BridgeState.playerCountersBySeatId[seatSnapshot.seatId]
    local lifeCounter = BridgeGetLiveObjectByGuid(seat.lifeCounterGuid)
    if lifeCounter ~= nil then lifeCounter.setValue(seatSnapshot.life) end
    -- Seat counters and mana are loaded as one authoritative row update;
    -- avoid a transient half-populated row during snapshot reconciliation.
    BridgeSetManaBank(seatSnapshot.seatId, seatSnapshot.manaPool or {}, true)
    BridgeApplySeatTrackers(seatSnapshot, true)
    -- All authoritative seat values are now in memory. Reconcile the row once
    -- so a snapshot never paints a half-old/half-new resource state.
    BridgeRefreshResourceRow(seatSnapshot.seatId)
    local battlefieldInstances = {}
    for _, zone in ipairs(seatSnapshot.zones or {}) do
        for _, card in ipairs(zone.cards or {}) do
            BridgeState.authoritativeObjectByInstanceId[card.cardInstanceId] = {
                objectId = card.authoritativeObjectId or card.cardInstanceId,
                originObjectId = card.originObjectId,
                copySourceObjectId = card.copySourceObjectId,
                objectKind = card.objectKind,
                isCopy = card.isCopy == true,
                isVirtual = card.isVirtual == true,
                materializationPolicy = card.materializationPolicy
            }
        end
        if zone.name == "battlefield" then
            for _, card in ipairs(zone.cards or {}) do
                BridgeState.battlefieldKindByInstanceId[card.cardInstanceId] = card.battlefieldKind == "land"
                    and "land" or "creature"
                battlefieldInstances[card.cardInstanceId] = true
                local designations = {}
                for _, designation in ipairs(card.cardDesignations or {}) do
                    designations[string.lower(tostring(designation))] = true
                end
                -- Keep designation truth even while the physical card is
                -- still materializing. Snapshot reconciliation, not the
                -- presence of a TTS object, owns removal as well as addition.
                BridgeState.cardDesignationsByInstanceId[card.cardInstanceId] = designations
                local previousPrepared = BridgeState.preparedDesignationStateByInstanceId[card.cardInstanceId]
                local hadPreparedBaseline = previousPrepared ~= nil
                local wasPrepared = previousPrepared == true
                local isPrepared = designations["prepared"] == true
                BridgeState.preparedDesignationStateByInstanceId[card.cardInstanceId] = isPrepared
                local guid = BridgeState.physicalByInstanceId[card.cardInstanceId]
                local object = guid and BridgeGetLiveObjectByGuid(guid) or nil
                if object ~= nil then
                    BridgeSetPhysicalTapped(object, card.tapped == true)
                    BridgeState.counterStateByInstanceId[card.cardInstanceId] = BridgeCopyCounterMap(card.counters)
                    BridgePresentationMetric("snapshotVisualCounters")
                    local countersApplied, counterError = BridgeSetCardCounters(object, card.counters)
                    if not countersApplied then BridgeLog("[Bridge] counter visual unsupported: " .. tostring(counterError)) end
                    local keywords = {}
                    for _, keyword in ipairs(card.keywords or {}) do
                        keywords[BridgeNormalizeKeywordName(keyword)] = true
                    end
                    BridgeState.keywordStateByInstanceId[card.cardInstanceId] = keywords
                    BridgePresentationMetric("snapshotVisualKeywords")
                    local keywordsApplied, keywordError = BridgeSetCardKeywords(object, card.keywords)
                    if not keywordsApplied then BridgeLog("[Bridge] keyword visual unsupported: " .. tostring(keywordError)) end
                    -- Encoder rebuilds performed by counters/keywords may
                    -- recreate the card UI.  Apply Unified P/T and ownership
                    -- last so a static characteristic update remains visible.
                    BridgePresentationMetric("snapshotVisualCharacteristics")
                    local presentationApplied, presentationError = BridgeApplyCardPresentationSnapshot(object, card)
                    if not presentationApplied then
                        BridgeLog("[Bridge] optional card presentation skipped: " .. tostring(presentationError))
                    end
                    BridgePresentationMetric("snapshotVisualDesignations")
                    BridgeSetPreparedDesignationPresentation(object, isPrepared)
                    BridgeEnsurePreparedBadge(object, card.cardInstanceId, isPrepared)
                    -- A snapshot establishes persistent truth; only a change
                    -- from an already-established false baseline gets the
                    -- one-shot transition pulse.  Reload/reconcile of an
                    -- already-prepared permanent must not replay it.
                    if isPrepared and hadPreparedBaseline and not wasPrepared then
                        BridgePulsePreparedDesignation(object, card.cardInstanceId)
                    end
                    BridgeSetPrototypeDesignationPresentation(object, designations["prototyped"] == true)
                end
            end
        end
    end
    -- A prepared designation is meaningful only while the permanent remains
    -- on the battlefield. Clear any saved presentation as soon as an
    -- authoritative snapshot places that identity elsewhere.
    local stalePreparedInstances = {}
    local trackedDesignationInstances = {}
    for instanceId, _ in pairs(BridgeState.cardDesignationsByInstanceId or {}) do
        trackedDesignationInstances[instanceId] = true
    end
    for instanceId, _ in pairs(BridgeState.preparedDesignationStateByInstanceId or {}) do
        trackedDesignationInstances[instanceId] = true
    end
    for instanceId, _ in pairs(trackedDesignationInstances) do
        local guid = BridgeState.physicalByInstanceId[instanceId]
        local mappedSeat = guid and BridgeState.physicalSeatByGuid[guid] or nil
        if mappedSeat == seatSnapshot.seatId and not battlefieldInstances[instanceId] then
            table.insert(stalePreparedInstances, {instanceId = instanceId, guid = guid})
        end
    end
    for _, stale in ipairs(stalePreparedInstances) do
        local object = stale.guid and BridgeGetLiveObjectByGuid(stale.guid) or nil
        local priorZone = stale.guid and BridgeState.physicalZoneByGuid[stale.guid] or nil
        if object ~= nil then
            BridgeSetPreparedDesignationPresentation(object, false)
            if priorZone ~= "stack" then BridgeSetPrototypeDesignationPresentation(object, false) end
        end
        BridgeDestroyPreparedBadge(stale.instanceId)
        BridgeState.preparedPresentationGuidByInstanceId[stale.instanceId] = nil
        BridgeState.preparedDesignationStateByInstanceId[stale.instanceId] = nil
        BridgeState.cardDesignationsByInstanceId[stale.instanceId] = nil
    end
    for instanceId, badgeGuid in pairs(BridgeState.preparedBadgeGuidByInstanceId or {}) do
        local cardGuid = BridgeState.physicalByInstanceId[instanceId]
        local cardZone = cardGuid and BridgeState.physicalZoneByGuid[cardGuid] or nil
        if BridgeState.preparedDesignationStateByInstanceId[instanceId] ~= true
            or cardGuid == nil or (cardZone ~= nil and cardZone ~= "battlefield") then
            BridgeDestroyPreparedBadge(instanceId)
        end
    end
end

function BridgeResourceDefinition(kind)
    if kind == "W" or kind == "U" or kind == "B" or kind == "R" or kind == "G" or kind == "C" then
        return {key = kind, sourceGuid = BRIDGE_MANA_COUNTER_SOURCES[kind], name = "Forge Mana " .. kind}
    end
    return {key = kind, sourceGuid = BRIDGE_PLAYER_TRACKER_SOURCES[kind], name = "Forge " .. tostring(kind)}
end

function BridgeResourceValue(seatId, kind)
    local player = BridgeState.playerStateBySeatId[seatId] or {}
    if kind == "W" or kind == "U" or kind == "B" or kind == "R" or kind == "G" or kind == "C" then
        return math.max(0, tonumber((player.mana or {})[kind] or 0) or 0)
    end
    return math.max(0, tonumber((player.counters or {})[kind] or 0) or 0)
end

function BridgeResourceRowPosition(seatId, slot)
    local seat = BRIDGE_SEATS[seatId]
    local lifeCounter = seat and BridgeGetLiveObjectByGuid(seat.lifeCounterGuid) or nil
    if seat == nil or seat.manaBankOffset == nil or lifeCounter == nil then return nil end
    local p = lifeCounter.getPosition()
    return {
        p.x + seat.manaBankOffset.x + (slot - 1) * BRIDGE_RESOURCE_ROW_SPACING,
        p.y + seat.manaBankOffset.y,
        p.z + seat.manaBankOffset.z
    }
end

function BridgeHideResourceCounter(counter)
    if counter == nil then return end
    -- Retire only the spawned presentation instance.  Never touch a native
    -- source/template object; it remains available for the next non-zero value.
    pcall(function() counter.setPosition({0, -20, 0}) end)
    pcall(function() counter.setInvisibleTo({"White", "Blue"}) end)
end

function BridgeShowResourceCounter(counter, position, seat)
    if counter == nil or position == nil then return end
    pcall(function() counter.setInvisibleTo({}) end)
    -- Mana counters must face the same direction as the life counter they are
    -- positioned relative to. Match the life counter orientation: 180° when
    -- player is on far side (tableSideZ < 0), 0° when on near side.
    if seat ~= nil then
        pcall(function() counter.setRotation({0, seat.tableSideZ < 0 and 180 or 0, 0}) end)
    end
    pcall(function() counter.setPosition(position) end)
end

-- Resource-row and Monarch objects are presentation-owned, named objects. A
-- single hydration pass indexes objects that survived Save & Play; steady
-- state must use the index and never scan the whole table to prove that a
-- zero-valued object is absent.
function BridgeHydratePresentationObjectIndexes()
    if BridgeState.resourceCounterIndexHydrated == true
        and BridgeState.monarchHelperIndexHydrated == true then return end

    BridgePresentationMetric("worldScanCount")
    BridgePresentationMetric("resourceWorldScanCount")
    local resourceObjects = {}
    for _, object in ipairs(getAllObjects()) do
        if BridgeObjectIsUsable(object) then
            local guid = BridgeSafeObjectGuid(object)
            local name = tostring(BridgeSafeObjectName(object) or "")
            local manaKind, manaSeat = string.match(name, "^Forge Mana ([WUBRGC]) (forge%-player%-[12])$")
            local trackerKind, trackerSeat = string.match(name, "^Forge (energy|experience|poison|speed) (forge%-player%-[12])$")
            local kind = manaKind or trackerKind
            local seatId = manaSeat or trackerSeat
            if guid ~= nil and kind ~= nil and seatId ~= nil then
                BridgeRegisterPresentationObject(object, "resource_row_" .. tostring(kind))
                resourceObjects[seatId] = resourceObjects[seatId] or {}
                if resourceObjects[seatId][kind] == nil then
                    resourceObjects[seatId][kind] = guid
                end
            end
            if BridgeState.monarchHelperGuid == nil and object.tag == "Card"
                and string.sub(string.lower(name), 1, 10) == "the monarch" then
                BridgeRegisterPresentationObject(object, "monarch_helper")
                BridgeState.monarchHelperGuid = guid
            end
        end
    end
    for seatId, resources in pairs(resourceObjects) do
        BridgeState.resourceCounterGuidBySeatId[seatId] = BridgeState.resourceCounterGuidBySeatId[seatId] or {}
        for kind, guid in pairs(resources) do
            if BridgeState.resourceCounterGuidBySeatId[seatId][kind] == nil then
                BridgeState.resourceCounterGuidBySeatId[seatId][kind] = guid
            end
        end
    end
    BridgeState.resourceCounterIndexHydrated = true
    BridgeState.monarchHelperIndexHydrated = true
end

function BridgeFindResourceCounter(seatId, kind, definition)
    BridgeState.resourceCounterGuidBySeatId[seatId] = BridgeState.resourceCounterGuidBySeatId[seatId] or {}
    local guid = BridgeState.resourceCounterGuidBySeatId[seatId][kind]
    local counter = guid and BridgeGetLiveObjectByGuid(guid) or nil
    if counter ~= nil then return counter end
    -- A missing cached GUID is an ordinary zero-resource state, not evidence
    -- that the world needs to be searched. Hydration is performed once at the
    -- session boundary; positive values can create a new presentation object.
    return nil
end

function BridgeCreateResourceCounter(seatId, kind, definition, position)
    BridgeState.resourceCounterSpawnInFlightBySeatId[seatId] = BridgeState.resourceCounterSpawnInFlightBySeatId[seatId] or {}
    if BridgeState.resourceCounterSpawnInFlightBySeatId[seatId][kind] then return nil end
    BridgeState.resourceCounterSpawnInFlightBySeatId[seatId][kind] = true
    local source = definition.sourceGuid and BridgeGetLiveObjectByGuid(definition.sourceGuid) or nil
    if source == nil then
        BridgeState.resourceCounterSpawnInFlightBySeatId[seatId][kind] = nil
        BridgeLog("[Bridge] resource row source unavailable kind=" .. tostring(kind) .. " seat=" .. tostring(seatId))
        return nil
    end
    local expectedName = definition.name .. " " .. tostring(seatId)
    local epoch = BRIDGE_RUNTIME_EPOCH_LOCAL
    local sessionId = BridgeState.eventSessionId
    if kind == "W" or kind == "U" or kind == "B" or kind == "R" or kind == "G" or kind == "C" then
        local counter = source.clone({position = position})
        if not BridgeObjectIsUsable(counter) then
            BridgeState.resourceCounterSpawnInFlightBySeatId[seatId][kind] = nil
            return nil
        end
        counter.setName(expectedName)
        counter.setScale({0.55, 0.55, 0.55})
        counter.setLock(true)
        BridgeRegisterPresentationObject(counter, "resource_row_" .. tostring(kind))
        BridgeState.resourceCounterGuidBySeatId[seatId][kind] = BridgeSafeObjectGuid(counter)
        BridgeState.resourceCounterSpawnInFlightBySeatId[seatId][kind] = nil
        BridgeWaitFrames(function()
            if sessionId == BridgeState.eventSessionId then
                BridgeSetNativeTrackerValue(counter, BridgeResourceValue(seatId, kind))
                -- Re-run once after TTS has registered the clone. This covers
                -- resource events that arrive during the clone's first frame.
                BridgeRefreshResourceRow(seatId)
            end
        end, 2)
        return counter
    end
    source.takeObject({position = position, smooth = false, callback_function = function(taken)
        if BridgeState.resourceCounterSpawnInFlightBySeatId[seatId] ~= nil then
            BridgeState.resourceCounterSpawnInFlightBySeatId[seatId][kind] = nil
        end
        if sessionId ~= BridgeState.eventSessionId or not BridgeRuntimeIsCurrent(epoch) or not BridgeObjectIsUsable(taken) then
            if BridgeObjectIsUsable(taken) then BridgeSafeObjectCall(taken, function(o) o.destruct() end) end
            return
        end
        taken.setName(expectedName)
        taken.setLock(true)
        -- Preserve the existing tracker presentation classification while the
        -- physical object is now managed by the unified resource row.
        BridgeRegisterPresentationObject(taken, "player_tracker_" .. kind)
        BridgeRegisterPresentationObject(taken, "resource_row_" .. tostring(kind))
        BridgeState.resourceCounterGuidBySeatId[seatId][kind] = BridgeSafeObjectGuid(taken)
        BridgeWaitFrames(function()
            if sessionId == BridgeState.eventSessionId then
                BridgeSetNativeTrackerValue(taken, BridgeResourceValue(seatId, kind))
                BridgeRefreshResourceRow(seatId)
            end
        end, 2)
    end})
    return nil
end

-- Reconcile one compact row from authoritative Forge values.  Zero-valued
-- resources are hidden/retired and never occupy a slot; remaining counters
-- are packed contiguously in the stable order above.
function BridgeRefreshResourceRow(seatId)
    BridgePresentationMetric("resourceRowRefreshCount")
    local resourceToken = BridgePerformanceBegin("resource_row_total")
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil or BridgeResourceRowPosition(seatId, 1) == nil then
        BridgePerformanceEnd(resourceToken, "resource_row_total_end", "resourceRow")
        return false
    end
    BridgeState.resourceCounterGuidBySeatId[seatId] = BridgeState.resourceCounterGuidBySeatId[seatId] or {}
    BridgeState.manaCounterGuidBySeatId[seatId] = BridgeState.resourceCounterGuidBySeatId[seatId]
    BridgeState.playerTrackerGuidBySeatId[seatId] = BridgeState.resourceCounterGuidBySeatId[seatId]
    local slot = 0
    for _, kind in ipairs(BRIDGE_RESOURCE_ORDER) do
        local definition = BridgeResourceDefinition(kind)
        local value = BridgeResourceValue(seatId, kind)
        -- Do not look up absent zero-valued resources. A cached object is still
        -- hidden in O(1), while an uncached zero needs no physical operation.
        local counter = nil
        if value > 0 or BridgeState.resourceCounterGuidBySeatId[seatId][kind] ~= nil then
            counter = BridgeFindResourceCounter(seatId, kind, definition)
        end
        if value > 0 then
            slot = slot + 1
            local position = BridgeResourceRowPosition(seatId, slot)
            if counter == nil then counter = BridgeCreateResourceCounter(seatId, kind, definition, position) end
            if counter ~= nil then
                BridgeShowResourceCounter(counter, position, seat)
                BridgeSetNativeTrackerValue(counter, value)
            end
        elseif counter ~= nil then
            BridgeHideResourceCounter(counter)
        end
    end
    BridgePerformanceEnd(resourceToken, "resource_row_total_end", "resourceRow", slot)
    return true
end

-- Compatibility entry point retained for existing callers; it now refreshes
-- the unified row and never materializes zero-valued mana counters.
function BridgeEnsureManaBank(seatId)
    -- Compatibility notes for table integrations: the row reacquires the
    -- live anchors through BridgeGetLiveObjectByGuid(seat.lifeCounterGuid),
    -- source objects through BridgeGetLiveObjectByGuid(BRIDGE_MANA_COUNTER_SOURCES[color]),
    -- and validates candidates with BridgeObjectIsUsable(object) and BridgeSafeObjectName(object) == expectedName.
    return BridgeRefreshResourceRow(seatId)
end

function BridgeSetManaBank(seatId, manaPool, deferRefresh)
    if seatId == nil then
        BridgeLog("[Bridge] ignored mana pool update without seatId")
        return false
    end
    BridgeState.playerStateBySeatId[seatId] = BridgeState.playerStateBySeatId[seatId] or {}
    -- Forge's structured producer uses W/U/B/R/G/C, but older adapters and
    -- hand-authored event fixtures have emitted lowercase keys or numeric
    -- strings. Normalize at the authority boundary so every mana event and
    -- snapshot feeds the same absolute resource row.
    local normalized = {}
    for key, value in pairs(manaPool or {}) do
        local canonical = string.upper(tostring(key))
        normalized[canonical] = tonumber(value) or 0
    end
    for _, key in ipairs({"W", "U", "B", "R", "G", "C"}) do
        if normalized[key] == nil then normalized[key] = 0 end
    end
    BridgeState.playerStateBySeatId[seatId].mana = normalized
    if not deferRefresh then BridgeRefreshResourceRow(seatId) end
    return true
end

function BridgeSetNativeTrackerValue(counter, value)
    if counter == nil then return false end
    local amount = math.max(0, tonumber(value or 0) or 0)
    -- Native Counter objects expose setValue.  Do not call assumed helper
    -- functions on cloned table assets: a missing updateVal/updateSave hook
    -- produces a visible TTS error even when wrapped in pcall.
    local nativeOk = pcall(function() counter.setValue(amount) end)
    if nativeOk then return true end

    -- Keep a quiet compatibility fallback for a non-native scripted tracker.
    local setVarOk, setVarError = pcall(function() counter.setVar("val", amount) end)
    if not setVarOk then
        BridgeLog("[Bridge] tracker has no supported value update API: " .. tostring(setVarError))
    end
    return setVarOk
end

function BridgeTrackerPosition(seatId, kind)
    local seat = BRIDGE_SEATS[seatId]
    local offset = seat and seat.trackerOffsets and seat.trackerOffsets[kind]
    local lifeCounter = seat and BridgeGetLiveObjectByGuid(seat.lifeCounterGuid) or nil
    if offset == nil or lifeCounter == nil then return nil end
    local lifePosition = lifeCounter.getPosition()
    return {lifePosition.x + offset.x, lifePosition.y + offset.y, lifePosition.z + offset.z}
end

function BridgeSetSeatTracker(seatId, kind, value)
    local amount = math.max(0, tonumber(value or 0) or 0)
    BridgeState.playerCountersBySeatId[seatId] = BridgeState.playerCountersBySeatId[seatId] or {}
    BridgeState.playerCountersBySeatId[seatId][kind] = amount
    BridgeState.playerStateBySeatId[seatId] = BridgeState.playerStateBySeatId[seatId] or {}
    BridgeState.playerStateBySeatId[seatId].counters = BridgeState.playerCountersBySeatId[seatId]
    BridgeRefreshResourceRow(seatId)
    return true, nil
end

function BridgeApplySeatTrackers(seatSnapshot, deferRefresh)
    if seatSnapshot == nil then return end
    local counters = BridgeState.playerCountersBySeatId[seatSnapshot.seatId] or {}
    counters.poison = math.max(0, tonumber(seatSnapshot.poison or counters.poison or 0) or 0)
    counters.speed = math.max(0, tonumber(seatSnapshot.speed or counters.speed or 0) or 0)
    BridgeState.playerCountersBySeatId[seatSnapshot.seatId] = counters
    BridgeState.playerStateBySeatId[seatSnapshot.seatId] = BridgeState.playerStateBySeatId[seatSnapshot.seatId] or {}
    BridgeState.playerStateBySeatId[seatSnapshot.seatId].counters = counters
    if not deferRefresh then BridgeRefreshResourceRow(seatSnapshot.seatId) end
end

function BridgeFindLiveMonarchHelper()
    local known = BridgeState.monarchHelperGuid and BridgeGetLiveObjectByGuid(BridgeState.monarchHelperGuid) or nil
    if known ~= nil then return known end
    BridgeState.monarchHelperGuid = nil
    if BridgeState.monarchHelperIndexHydrated ~= true then
        BridgeHydratePresentationObjectIndexes()
        local hydrated = BridgeState.monarchHelperGuid and BridgeGetLiveObjectByGuid(BridgeState.monarchHelperGuid) or nil
        if hydrated ~= nil then return hydrated end
    end
    return nil
end

function BridgePositionMonarchHelper(helper, seatId)
    local seat = BRIDGE_SEATS[seatId]
    if helper == nil or seat == nil or seat.monarchAnchor == nil then return false end
    BridgeRegisterPresentationObject(helper, "monarch_helper")
    BridgeState.monarchHelperGuid = BridgeSafeObjectGuid(helper)
    BridgeState.monarchSeatId = seatId
    BridgeSafeObjectCall(helper, function(card)
        card.setLock(true)
        card.interactable = false
        card.setPositionSmooth(seat.monarchAnchor, false, true)
        card.setRotationSmooth(seat.monarchRotation or seat.faceUpRotation, false, true)
    end)
    return true
end

function BridgeReturnMonarchHelper()
    -- No monarch is the normal steady state. Do not rediscover an absent
    -- helper with a full-world scan during every snapshot.
    local helper = BridgeState.monarchHelperGuid and BridgeGetLiveObjectByGuid(BridgeState.monarchHelperGuid) or nil
    local utilityDeck = BridgeGetLiveObjectByGuid("946716")
    if helper ~= nil and utilityDeck ~= nil and utilityDeck.tag == "Deck" then
        BridgeSafeObjectCall(utilityDeck, function(deck) deck.putObject(helper) end)
        BridgeUnregisterPresentationObject(helper)
        BridgeState.monarchHelperGuid = nil
    end
    BridgeState.monarchSeatId = nil
end

function BridgeSetMonarchSeat(seatId)
    if seatId == nil or BRIDGE_SEATS[seatId] == nil then
        BridgeReturnMonarchHelper()
        return
    end
    BridgeState.monarchSeatId = seatId
    local helper = BridgeFindLiveMonarchHelper()
    if helper ~= nil then
        BridgePositionMonarchHelper(helper, seatId)
        return
    end
    if BridgeState.monarchSpawnInFlight then return end
    local utilityDeck = BridgeGetLiveObjectByGuid("946716")
    if utilityDeck == nil or utilityDeck.tag ~= "Deck" then
        BridgeLog("[Bridge] Monarch helper unavailable: native utility deck 946716 is missing")
        return
    end
    local entry = nil
    for _, contained in ipairs(utilityDeck.getObjects() or {}) do
        local name = string.lower(tostring(contained.nickname or contained.name or ""))
        if string.sub(name, 1, 10) == "the monarch" then entry = contained; break end
    end
    if entry == nil then
        BridgeLog("[Bridge] Monarch helper unavailable: utility deck has no The Monarch card")
        return
    end
    BridgeState.monarchSpawnInFlight = true
    local epoch = BRIDGE_RUNTIME_EPOCH_LOCAL
    utilityDeck.takeObject({
        index = entry.index,
        position = BRIDGE_SEATS[seatId].monarchAnchor,
        smooth = false,
        callback_function = function(taken)
            if not BridgeRuntimeIsCurrent(epoch) then return end
            BridgeState.monarchSpawnInFlight = false
            if BridgeObjectIsUsable(taken) and BridgeState.monarchSeatId ~= nil then
                BridgePositionMonarchHelper(taken, BridgeState.monarchSeatId)
            end
        end
    })
end

function BridgeAdvanceEventPollGeneration(reason)
    local oldGeneration = BridgeState.eventPollGeneration or 0
    BridgeState.eventPollGeneration = oldGeneration + 1
    local head = BridgeState.eventQueue ~= nil and BridgeState.eventQueue[1] or nil
    BridgeLog(string.format(
        "[Bridge] EVENT_POLL_GENERATION old=%d new=%d reason=%s session=%s received=%s applied=%s queueHead=%s animation=%s",
        oldGeneration,
        BridgeState.eventPollGeneration,
        tostring(reason or "unspecified"),
        tostring(BridgeState.eventSessionId),
        tostring(BridgeState.lastReceivedEventSequence),
        tostring(BridgeState.lastAppliedEventSequence),
        tostring(head ~= nil and head.sequence or nil),
        tostring(BridgeState.animationRunning)))
    return BridgeState.eventPollGeneration
end

function BridgeAdvanceEventSessionGeneration(reason)
    local oldGeneration = BridgeState.eventSessionGeneration or 0
    BridgeState.eventSessionGeneration = oldGeneration + 1
    BridgeLog(string.format(
        "[Bridge] EVENT_SESSION_GENERATION old=%d new=%d reason=%s session=%s received=%s applied=%s",
        oldGeneration,
        BridgeState.eventSessionGeneration,
        tostring(reason or "unspecified"),
        tostring(BridgeState.eventSessionId),
        tostring(BridgeState.lastReceivedEventSequence),
        tostring(BridgeState.lastAppliedEventSequence)))
    return BridgeState.eventSessionGeneration
end

function BridgeStartEventPolling(sessionId, skipExisting)
    if sessionId == nil then
        BridgeStopOnDesync("cannot poll events without a sessionId")
        return
    end

    if BridgeState.schedulerOwner == "RESYNC" then
        BridgeLog("[Bridge] event polling start deferred: resync owns scheduler")
        return
    end

    if BridgeState.eventSessionId == sessionId and BridgeState.eventPolling then
        return
    end

    BridgePrepareEventSession(sessionId, false)

    BridgeState.skipExistingEventsOnAttach = skipExisting == true
    BridgeState.eventPolling = true
    BridgeState.eventRetryCount = 0
    local generation = BridgeAdvanceEventPollGeneration("start")
    BridgePollEvents(generation)
end

function BridgeRetireResourceRowObjects()
    for seatId, resources in pairs(BridgeState.resourceCounterGuidBySeatId or {}) do
        for _, guid in pairs(resources or {}) do
            BridgeHideResourceCounter(BridgeGetLiveObjectByGuid(guid))
        end
    end
    BridgeState.resourceCounterSpawnInFlightBySeatId = {}
end

function BridgePrepareEventSession(sessionId, forceReset, preserveLiveMappings)
    if not forceReset and BridgeState.eventSessionId == sessionId then
        return
    end

    local replacingMatch = BridgeState.eventSessionId ~= nil and BridgeState.eventSessionId ~= sessionId
    local checkpoint = BridgeState.resyncCheckpoint
    local preserveCheckpoint = checkpoint ~= nil and checkpoint.sessionId == sessionId and not replacingMatch
    local preservedLiveMappings = nil
    if preserveLiveMappings == true and BridgeState.eventSessionId == sessionId then
        preservedLiveMappings = {}
        for instanceId, guid in pairs(BridgeState.physicalByInstanceId or {}) do
            local object = BridgeGetLiveObjectByGuid(guid)
            if object ~= nil and object.tag == "Card" then
                preservedLiveMappings[instanceId] = {
                    guid = guid,
                    seatId = BridgeState.physicalSeatByGuid[guid],
                    zoneName = BridgeState.physicalZoneByGuid[guid],
                    cardName = BridgeState.cardNameByInstanceId[instanceId]
                }
            end
        end
    end

    BridgeStopEventPolling("session-prepare")
    BridgeAdvanceEventSessionGeneration("session-prepare")
    BridgeStopDecisionPolling()
    BridgeReturnAttackPresentation(nil)
    BridgeRetireResourceRowObjects()
    -- One world scan recovers named row/helper objects after Save & Play.
    -- Subsequent snapshots use the indexed GUIDs, including the all-zero case.
    BridgeHydratePresentationObjectIndexes()
    BridgeClearPreparedPresentationObjects()
    BridgeState.decisionPresentationGeneration = BridgeState.decisionPresentationGeneration + 1
    BridgeAdvancePhysicalPresentationGeneration("session-replaced")
    BridgeAdvancePhysicalTransactionGeneration("session-replaced")
    BridgeState.renderedDecisionPresentationKey = nil
    BridgeState.renderedDecisionPhysicalGeneration = nil
    BridgeState.eventSessionId = sessionId
    if replacingMatch or checkpoint == nil then
        BridgeState.resyncStage = "Idle"
        BridgeState.resyncStageChangedAt = nil
        BridgeState.resyncAttempt = 0
        BridgeState.resyncRootCause = nil
        BridgeState.resyncLastFailureReason = nil
        BridgeState.resyncLastProgressAt = nil
        BridgeState.resyncNoProgressAttempts = 0
        BridgeState.resyncCircuitOpen = false
        BridgeState.resyncSnapshotFingerprint = nil
        BridgeState.resyncSnapshotRepeatCount = 0
    end
    BridgeState.schedulerOwner = "NORMAL"
    BridgeState.fastForwardSuspendedByResync = false
    BridgeState.desyncLatched = false
    BridgeState.desyncFailureCount = 0
    BridgeState.desyncLastMessage = nil
    if preserveCheckpoint then
        -- A same-session recovery is staged. Keep the last committed cursor
        -- visible until the new snapshot has passed every physical audit.
        BridgeState.lastReceivedEventSequence = checkpoint.lastReceived
        BridgeState.lastAppliedEventSequence = checkpoint.lastApplied
        BridgeState.eventQueue = checkpoint.eventQueue
    else
        BridgeState.lastReceivedEventSequence = 0
        BridgeState.lastAppliedEventSequence = 0
        BridgeState.eventQueue = {}
    end
    BridgeState.animationRunning = false
    BridgeState.eventDrainTransaction = nil
    BridgeState.eventDrainWatchdog = {
        sessionId = sessionId,
        sessionGeneration = BridgeState.eventSessionGeneration,
        eventSequence = nil,
        lastAppliedEventSequence = 0,
        blockedSince = nil,
        lastBlockReason = nil,
        logged = false,
        scheduled = false
    }
    BridgeState.decisionLifecycle = {}
    BridgeState.diagnosticCaptureLifecycle = {}
    BridgeState.diagnosticCaptureFollowupToken = nil
    BridgeState.diagnosticCaptureFollowupUntil = 0
    BridgeState.lastChoiceAttempt = nil
    BridgeState.yieldPolicyOwnTurn = false
    BridgeCreatureTypeClearDraft("session-replaced")
    BridgeGraveyardClear("session-replaced")
    BridgeState.physicalByInstanceId = {}
    BridgeState.physicalInstanceIdByGuid = {}
    BridgeState.cardNameByInstanceId = {}
    BridgeState.canonicalCardNameByGuid = {}
    BridgeState.encoderIdentityLoggedGuids = {}
    BridgeState.presentedStatsByGuid = {}
    BridgeState.presentedOwnerControllerByGuid = {}
    BridgeState.presentedPhasedByGuid = {}
    BridgeState.presentedCounterSignatureByGuid = {}
    BridgeState.presentedCounterFallbackSignatureByGuid = {}
    BridgeState.presentedKeywordSignatureByGuid = {}
    BridgeState.presentedIconLayoutByGuid = {}
    BridgeState.unsupportedKeywordLogged = {}
    BridgeState.presentationMetrics = {
        encoderRebuildCount = 0,
        keywordPropWriteCount = 0,
        decalWriteCount = 0,
        fullSnapshotReconcileCount = 0,
        resourceRowRefreshCount = 0,
        resourceWorldScanCount = 0,
        worldScanCount = 0,
        yieldBackpressurePauseCount = 0,
        snapshotVisualCounters = 0,
        snapshotVisualKeywords = 0,
        snapshotVisualCharacteristics = 0,
        snapshotVisualDesignations = 0,
        decisionRenderAttempts = 0,
        decisionRenderExecuted = 0,
        decisionRenderSkippedIdentical = 0
    }
    BridgeState.performanceTrace = {capacity = BRIDGE_PERFORMANCE_TRACE_CAPACITY, head = 0, count = 0, records = {}}
    BridgeState.performanceSummary = {
        slowRenderCount = 0,
        worstRenderDurationMs = 0,
        worstClearHighlightsDurationMs = 0,
        worstPreparedPresentationDurationMs = 0,
        worstCandidateCollectionDurationMs = 0,
        worstActionMatchingDurationMs = 0,
        worstUiFlushDurationMs = 0,
        worstSnapshotReconcileDurationMs = 0,
        ttsRepresentedPlayLandCount = 0,
        ttsRepresentedCastSpellCount = 0
    }
    BridgeState.physicalSeatByGuid = {}
    BridgeState.physicalZoneByGuid = {}
    BridgeState.tokenPhysicalGuids = {}
    BridgeState.tokenMaterializationByInstanceId = {}
    BridgeState.canonicalCardScaleByGuid = {}
    BridgeState.landPlacementMode = BRIDGE_LAND_PLACEMENT_MODE
    BridgeState.landInsertionOrderByInstanceId = {}
    BridgeState.nextLandInsertionOrder = 0
    BridgeState.discardPresentation = nil
    BridgeState.mulliganBottomInstanceIds = {}
    BridgeState.mulliganReturningInstanceIds = {}
    BridgeState.mulliganBottomQueueBySeatId = {}
    BridgeState.mulliganBottomInsertionActiveBySeatId = {}
    BridgeState.libraryExtractionQueueBySeatId = {}
    BridgeState.libraryExtractionActiveBySeatId = {}
    BridgeState.libraryBatchBySeatId = {}
    BridgeState.battlefieldCounts = {}
    BridgeState.graveyardCounts = {}
    BridgeState.counterStateByInstanceId = {}
    BridgeState.keywordStateByInstanceId = {}
    BridgeState.cardDesignationsByInstanceId = {}
    BridgeState.authoritativeObjectByInstanceId = {}
    BridgeState.preparedDescriptionByGuid = {}
    BridgeState.prototypeDescriptionByGuid = {}
    BridgeState.preparedBadgeGuidByInstanceId = {}
    BridgeState.preparedPresentationGuidByInstanceId = {}
    BridgeState.preparedDesignationStateByInstanceId = {}
    BridgeState.preparedSpellControlGuids = {}
    BridgeState.untappedRotationByGuid = {}
    BridgeState.physicalTappedByGuid = {}
    BridgeState.pendingCastBySeatId = {}
    BridgeState.attackOriginByGuid = {}
    BridgeState.attackLaneGuidBySeatId = {}
    BridgeState.snapshotForgeSequence = 0
    BridgeState.deferredSnapshotReconcile = nil
    BridgeState.snapshotReconcilePending = false
    BridgeState.snapshotReconcilePendingRequest = nil
    BridgeState.snapshotReconcileRequestGeneration = 0
    BridgeState.snapshotReconcileLastAppliedCursor = 0
    BridgeState.snapshotReconcileLastAppliedGeneration = 0
    BridgeState.snapshotReconcileLastAppliedCategory = nil
    BridgeState.lastTurnEventSignature = nil
    BridgeState.lastPhaseEventSignature = nil
    BridgeState.lastPriorityEventSignature = nil
    BridgeState.zoneAnchorGuidBySeatAndZone = {}
    BridgeState.yieldPolicyTurnNumber = nil
    BridgeState.yieldPolicyActiveSeatId = nil
    BridgeState.yieldPolicySessionId = nil
    if BridgeState.ui ~= nil then
        BridgeState.ui.fastForwardActive = false
        BridgeState.ui.fastForwardSessionId = nil
        BridgeState.ui.fastForwardTurnNumber = nil
        BridgeState.ui.fastForwardActiveSeatId = nil
        if replacingMatch then BridgeState.ui.autoPassEmpty = false end
        BridgeState.ui.autoAdvanceMode = BridgeState.ui.autoPassEmpty and "AUTO-PASS EMPTY" or "NORMAL"
    end
    BridgeState.gameEnded = nil
    BridgeState.playerStateBySeatId = {}
    BridgeState.playerCountersBySeatId = {}

    -- Same-session authoritative resyncs rebuild presentation, but must not
    -- discard exact public CardInstanceId -> TTS GUID identity. Clearing that
    -- mapping forces bootstrap to reconstruct battlefield/graveyard cards by
    -- display name from the library, which can steal a played land or an
    -- already-milled duplicate during a Thought Scour burst. New sessions
    -- never enter this branch, so old-match identities cannot cross the fence.
    for instanceId, mapping in pairs(preservedLiveMappings or {}) do
        if mapping.guid ~= nil and BridgeGetLiveObjectByGuid(mapping.guid) ~= nil then
            BridgeState.physicalByInstanceId[instanceId] = mapping.guid
            BridgeState.physicalInstanceIdByGuid[mapping.guid] = instanceId
            BridgeState.physicalSeatByGuid[mapping.guid] = mapping.seatId
            BridgeState.physicalZoneByGuid[mapping.guid] = mapping.zoneName
            if mapping.cardName ~= nil then
                BridgeState.cardNameByInstanceId[instanceId] = mapping.cardName
            end
        end
    end
    if BridgeState.ui ~= nil then
        -- A report callback can be lost while TTS is frozen or while a match
        -- is replaced. The capture belongs to the old session, so release
        -- its UI latch at the generation boundary; the guarded callback
        -- cannot mutate the new session.
        if BridgeState.ui.reportCaptureInFlight then
            BridgeLog("[Bridge] retiring diagnostic capture at session boundary")
        end
        BridgeState.ui.reportCaptureInFlight = false
        BridgeState.ui.reportStatus = ""
        BridgeState.ui.uiAttributeCache = {}
        BridgeState.ui.uiAttributeAttemptCount = 0
        BridgeState.ui.uiAttributeWriteCount = 0
        BridgeState.ui.uiAttributeSkippedCount = 0
        BridgeState.ui.uiAttributeUpdateCount = 0
    end
    BridgeState.currentTurnSeatId = nil
    BridgeState.currentPhase = nil
    BridgeState.prioritySeatId = nil
    BridgeState.stackSummary = {}
    BridgeUiMarkDirty("session-reset")
    BridgeState.transitionExpectedUntil = 0
    BridgeState.latencyProbe = nil
    BridgeState.choiceTransactions = {}
    BridgeState.retiredChoiceDecisionIds = {}
    BridgeState.retiredChoiceDecisionOrder = {}
    BridgeState.pendingDecision = nil
    BridgeState.pendingDecisionDeferredAt = nil
    BridgeState.pendingDecisionDeferredCursor = 0
    BridgeState.pendingDecisionDeferredApplied = 0
    BridgeState.expectedHandInstanceIdsBySeatId = {}
    BridgeState.openingHandReadinessDecisionId = nil
    BridgeState.openingHandReadinessSnapshotPending = false
    BridgeState.openingHandReadinessSnapshotRequested = false
    BridgeState.openingHandReadinessRetryScheduled = false
    BridgeState.handActionReadinessSnapshotDecisionId = nil
    BridgeState.handActionReadinessSnapshotSessionId = nil
    BridgeState.handReadinessRecoveryDecisionId = nil
    BridgeState.handReadinessRecoverySessionId = nil
    BridgeState.handReadinessRecoveryAttempts = 0
    BridgeResetSelectionState()
    BridgeHideMainPriorityControls()
    if BridgeState.turnCounterSessionId ~= sessionId then
        BridgeState.turnCounterSessionId = sessionId
        BridgeState.tableTurnCount = 0
        BridgeState.turnCountsBySeatId = {}
        BridgeRefreshTurnCounterLabels()
    end
end

function BridgeStopEventPolling(reason)
    BridgeState.eventPolling = false
    BridgeAdvanceEventPollGeneration(reason or "stop")
    BridgeState.eventRequestInFlight = false
    BridgeState.eventPollScheduled = false
end

function BridgeScheduleEventPoll(delay, generation)
    if not BridgeState.eventPolling or generation ~= BridgeState.eventPollGeneration then
        return
    end
    if BridgeState.eventRequestInFlight or BridgeState.eventPollScheduled then
        return
    end

    BridgeState.eventPollScheduled = true
    BridgeWaitTime(function()
        if not BridgeState.eventPolling or generation ~= BridgeState.eventPollGeneration then
            return
        end
        BridgeState.eventPollScheduled = false
        BridgePollEvents(generation)
    end, delay)
end

function BridgePollEvents(generation)
    generation = generation or BridgeState.eventPollGeneration
    if not BridgeState.eventPolling or generation ~= BridgeState.eventPollGeneration then
        return
    end
    if BridgeState.eventRequestInFlight or BridgeState.eventPollScheduled then
        return
    end

    local requestedAfter = BridgeState.lastReceivedEventSequence
    local path = "/api/v1/events?after=" .. tostring(requestedAfter)
    BridgeState.eventRequestInFlight = true
    BridgeState.eventRequestGeneration = generation
    BridgeHttp.requestJson("GET", path, nil, function(ok, body, err)
        if generation ~= BridgeState.eventPollGeneration then
            if BridgeState.eventRequestGeneration == generation then
                BridgeState.eventRequestInFlight = false
                BridgeState.eventRequestGeneration = nil
            end
            return
        end

        BridgeState.eventRequestInFlight = false
        BridgeState.eventRequestGeneration = nil
        if not ok or body == nil then
            if body ~= nil and body.errorCode == "event_history_gap" then
                BridgeStopOnDesync("event history gap after sequence " .. tostring(requestedAfter) .. ": " .. tostring(body.message))
                return
            end

            BridgeState.eventRetryCount = BridgeState.eventRetryCount + 1
            local retryDelay = math.min(2 ^ (BridgeState.eventRetryCount - 1), 5)
            BridgeLog(string.format("[Bridge] transient event poll failure (%s); retrying in %.1f seconds", tostring(err), retryDelay))
            BridgeScheduleEventPoll(retryDelay, generation)
            return
        end

        BridgeState.eventRetryCount = 0
        if body.hasGap == true then
            BridgeStopOnDesync("event history gap after sequence " .. tostring(requestedAfter))
            return
        end

        if BridgeState.skipExistingEventsOnAttach then
            BridgeState.lastReceivedEventSequence = body.latestSequence or BridgeState.lastReceivedEventSequence
            BridgeState.lastAppliedEventSequence = BridgeState.lastReceivedEventSequence
            BridgeState.skipExistingEventsOnAttach = false
            BridgeLog("[Bridge] attached at authoritative event sequence " .. tostring(BridgeState.lastAppliedEventSequence))
            BridgeTryPresentPendingDecision("attach-catchup")
        else
            for _, event in ipairs(body.events or {}) do
                local expected = BridgeState.lastReceivedEventSequence + 1
                if event.sequence ~= expected then
                    BridgeStopOnDesync("event sequence gap: expected " .. tostring(expected) .. " but received " .. tostring(event.sequence))
                    return
                end

                local probe = BridgeState.latencyProbe
                if probe ~= nil and probe.acceptedAt ~= nil and probe.firstEventReceivedAt == nil then
                    probe.firstEventReceivedAt = os.clock()
                end
                BridgeState.lastReceivedEventSequence = event.sequence
                table.insert(BridgeState.eventQueue, event)
                if #BridgeState.eventQueue > BRIDGE_EVENT_QUEUE_MAX then
                    BridgeStopOnDesync("authoritative event queue exceeded bounded capacity")
                    return
                end
            end
            BridgeProcessEventQueue()
            BridgeTryPresentPendingDecision("poll-noqueue")
            end

            BridgeScheduleEventPoll(BridgeCurrentEventPollDelay(), generation)
    end)
end

function BridgeResetEventCommitWatchdog()
    BridgeState.eventCommitWatchdog = {
        eventSequence = nil,
        successfulApplyAttemptsWithoutCommit = 0,
        firstAttemptTimestamp = nil,
        lastAbortReason = nil
    }
end

function BridgeRecordEventCommitAbort(event, reason, sessionId, sessionGeneration)
    local watchdog = BridgeState.eventCommitWatchdog or {}
    if watchdog.eventSequence ~= event.sequence
        or watchdog.sessionId ~= sessionId
        or watchdog.sessionGeneration ~= sessionGeneration then
        watchdog = {
            eventSequence = event.sequence,
            sessionId = sessionId,
            sessionGeneration = sessionGeneration,
            successfulApplyAttemptsWithoutCommit = 0,
            firstAttemptTimestamp = os.clock(),
            lastAbortReason = nil
        }
        BridgeState.eventCommitWatchdog = watchdog
    end
    watchdog.successfulApplyAttemptsWithoutCommit = watchdog.successfulApplyAttemptsWithoutCommit + 1
    watchdog.lastAbortReason = reason
    BridgeLog(string.format(
        "[Bridge] EVENT_TX_ABORT eventSequence=%s eventKind=%s reason=%s session=%s sessionGeneration=%s pollGeneration=%s eventPolling=%s received=%s applied=%s queueLength=%s successfulApplyAttemptsWithoutCommit=%s",
        tostring(event.sequence), tostring(event.kind), tostring(reason), tostring(sessionId),
        tostring(sessionGeneration), tostring(BridgeState.eventPollGeneration),
        tostring(BridgeState.eventPolling), tostring(BridgeState.lastReceivedEventSequence),
        tostring(BridgeState.lastAppliedEventSequence), tostring(#BridgeState.eventQueue),
        tostring(watchdog.successfulApplyAttemptsWithoutCommit)))
    if watchdog.successfulApplyAttemptsWithoutCommit >= 3 then
        BridgeLog(string.format(
            "[Bridge] EVENT_COMMIT_LIVELOCK eventSequence=%s eventKind=%s session=%s lastAbortReason=%s",
            tostring(event.sequence), tostring(event.kind), tostring(sessionId), tostring(reason)))
        BridgeStopOnDesync("EVENT_COMMIT_LIVELOCK event " .. tostring(event.sequence))
    end
end

local function BridgeNormalizeForgeSequence(value)
    local sequence = tonumber(value)
    if sequence == nil or sequence <= 0 then return nil end
    return sequence
end

function BridgeEventsShareForgeMutationGroup(leftEvent, rightEvent)
    if leftEvent == nil or rightEvent == nil then return false, nil end
    local leftSequence = BridgeNormalizeForgeSequence(leftEvent.forgeSequence)
    local rightSequence = BridgeNormalizeForgeSequence(rightEvent.forgeSequence)
    if leftSequence == nil or rightSequence == nil then return false, nil end
    return leftSequence == rightSequence, leftSequence
end

function BridgeProcessEventQueue()
    local queue = BridgeState.eventQueue or {}
    if #queue == 0 then
        BridgeState.eventDrainWatchdog = {
            sessionId = BridgeState.eventSessionId,
            sessionGeneration = BridgeState.eventSessionGeneration,
            eventSequence = nil,
            lastAppliedEventSequence = BridgeState.lastAppliedEventSequence,
            blockedSince = nil,
            lastBlockReason = nil,
            logged = false,
            scheduled = false
        }
        -- Routine verification is allowed only at a quiescent boundary. The
        -- exact event stream gets first chance to establish the physical state.
        BridgeTryApplyDeferredSnapshotReconcile("event-drain")
        BridgeTryStartPendingSnapshotReconcile("event-drain")
        return
    end

    local blockReason = BridgeEventDrainBlockReason()
    if blockReason ~= "none" then
        -- Never turn a scheduler fence into a silent cursor stall. The
        -- watchdog records the exact state and, if the fence clears without a
        -- normal callback, performs one state-aware retry.
        BridgeObserveEventDrainBlocked(blockReason)
        return
    end

    local processingSessionId = BridgeState.eventSessionId
    local processingSessionGeneration = BridgeState.eventSessionGeneration or 0
    local processingPhysicalTransactionGeneration = BridgeState.physicalTransactionGeneration or 0
    local processingQueue = BridgeState.eventQueue
    local event = BridgeState.eventQueue[1]
    local expected = BridgeState.lastAppliedEventSequence + 1
    if event.sequence ~= expected then
        BridgeStopOnDesync("event application gap: expected " .. tostring(expected) .. " but queued " .. tostring(event.sequence))
        return
    end

    BridgeState.animationRunning = true
    BridgeState.eventDrainTransaction = {
        sessionId = processingSessionId,
        sessionGeneration = processingSessionGeneration,
        physicalTransactionGeneration = processingPhysicalTransactionGeneration,
        eventSequence = event.sequence,
        startedAt = os.clock(),
        continuationScheduled = false
    }
    BridgeState.eventDrainWatchdog = {
        sessionId = processingSessionId,
        sessionGeneration = processingSessionGeneration,
        eventSequence = event.sequence,
        lastAppliedEventSequence = BridgeState.lastAppliedEventSequence,
        blockedSince = nil,
        lastBlockReason = nil,
        logged = false,
        scheduled = false
    }
    BridgeLog(string.format(
        "[Bridge] EVENT_TX_BEGIN eventSequence=%s eventKind=%s session=%s sessionGeneration=%s pollGeneration=%s eventPolling=%s queueHead=%s received=%s applied=%s",
        tostring(event.sequence), tostring(event.kind), tostring(processingSessionId),
        tostring(processingSessionGeneration), tostring(BridgeState.eventPollGeneration),
        tostring(BridgeState.eventPolling), tostring(event.sequence),
        tostring(BridgeState.lastReceivedEventSequence), tostring(BridgeState.lastAppliedEventSequence)))
    local applyCallOk, applied, delay, applyError = pcall(BridgeApplyAuthoritativeEvent, event)
    if not applyCallOk then
        applyError = applied
        applied = false
        delay = nil
        BridgeLog(string.format(
            "[Bridge] EVENT_TX_APPLY_EXCEPTION eventSequence=%s error=%s",
            tostring(event.sequence), tostring(applyError)))
    end
    BridgeLog(string.format(
        "[Bridge] EVENT_TX_APPLY_RESULT eventSequence=%s applied=%s error=%s sessionGenerationBefore=%s sessionGenerationAfter=%s pollGeneration=%s eventPolling=%s queueHead=%s",
        tostring(event.sequence), tostring(applied), tostring(applyError),
        tostring(processingSessionGeneration), tostring(BridgeState.eventSessionGeneration or 0),
        tostring(BridgeState.eventPollGeneration), tostring(BridgeState.eventPolling),
        tostring(BridgeState.eventQueue ~= nil and BridgeState.eventQueue[1] ~= nil
            and BridgeState.eventQueue[1].sequence or nil)))
    if not applied then
        BridgeState.animationRunning = false
        BridgeState.eventDrainTransaction = nil
        BridgeLog(string.format("[Bridge] EVENT_TX_ABORT eventSequence=%s reason=apply_failed", tostring(event.sequence)))
        BridgeStopOnDesync(applyError or ("failed to apply event " .. tostring(event.sequence)))
        return
    end

    -- Polling generation belongs to HTTP callback freshness.  It may change
    -- while this synchronous event transaction is applying and must not turn
    -- a successful physical mutation into a replay.  Only replacement of the
    -- authoritative session/queue can abandon this transaction.
    if processingSessionId ~= BridgeState.eventSessionId
        or processingSessionGeneration ~= (BridgeState.eventSessionGeneration or 0) then
        BridgeState.animationRunning = false
        BridgeState.eventDrainTransaction = nil
        BridgeLog(string.format(
            "[Bridge] EVENT_TX_ABORT eventSequence=%s reason=session_replaced sessionBefore=%s sessionAfter=%s sessionGenerationBefore=%s sessionGenerationAfter=%s",
            tostring(event.sequence), tostring(processingSessionId), tostring(BridgeState.eventSessionId),
            tostring(processingSessionGeneration), tostring(BridgeState.eventSessionGeneration or 0)))
        return
    end
    if BridgeState.eventQueue ~= processingQueue then
        BridgeState.animationRunning = false
        BridgeState.eventDrainTransaction = nil
        BridgeRecordEventCommitAbort(event, "queue_replaced", processingSessionId, processingSessionGeneration)
        BridgeStopOnDesync("event queue replaced while applying event " .. tostring(event.sequence))
        return
    end
    if BridgeState.eventQueue[1] ~= event then
        BridgeState.animationRunning = false
        BridgeState.eventDrainTransaction = nil
        BridgeRecordEventCommitAbort(event, "queue_head_changed", processingSessionId, processingSessionGeneration)
        BridgeStopOnDesync("event queue changed while applying event " .. tostring(event.sequence))
        return
    end

    local oldLastApplied = BridgeState.lastAppliedEventSequence
    table.remove(BridgeState.eventQueue, 1)
    BridgeState.lastAppliedEventSequence = event.sequence
    BridgeState.lastConsumedEventSequence = event.sequence
    BridgeState.lastStateProjectedEventSequence = event.sequence
    BridgeState.lastPhysicalPresentationEventSequence = event.sequence
    if event.forgeSequence ~= nil then
        local forgeSequence = tonumber(event.forgeSequence)
        if forgeSequence ~= nil then
            BridgeState.lastAppliedForgeSequence = math.max(
                tonumber(BridgeState.lastAppliedForgeSequence or 0) or 0,
                forgeSequence)
        end
    end
    if event.revealPresentation ~= nil and BridgeApplyRevealPresentation ~= nil then
        local revealOk, revealError = pcall(BridgeApplyRevealPresentation, event.revealPresentation, event.sequence)
        if not revealOk then BridgeLog("[Bridge] reveal presentation failed: " .. tostring(revealError)) end
    end
    BridgeResetEventCommitWatchdog()
    local nextQueuedEvent = BridgeState.eventQueue[1]
    local delayPostCommitWork, mutationSequence = BridgeEventsShareForgeMutationGroup(event, nextQueuedEvent)
    if delayPostCommitWork then
        BridgeLog(string.format(
            "[Bridge] EVENT_TX_GROUP_PENDING forgeSequence=%s committed=%s next=%s",
            tostring(mutationSequence), tostring(event.sequence), tostring(nextQueuedEvent.sequence)))
    end
    BridgeLog(string.format(
        "[Bridge] EVENT_TX_COMMIT eventSequence=%s oldLastApplied=%s newLastApplied=%s queueLength=%s",
        tostring(event.sequence), tostring(oldLastApplied), tostring(BridgeState.lastAppliedEventSequence),
        tostring(#BridgeState.eventQueue)))
    if BridgeCheckProjectionCoherence ~= nil then
        BridgeCheckProjectionCoherence(BridgeState.lastDecision, "event-drain")
    end
    local transaction = BridgeState.eventDrainTransaction
    if transaction ~= nil then transaction.continuationScheduled = true end

    -- Install the serialized continuation immediately after the cursor commit.
    -- Optional post-commit presentation work is allowed to fail without
    -- stranding animationRunning and blocking the next authoritative event.
    local continuationDelay = (function()
        if delayPostCommitWork then return 0 end
        local nextDelay = delay or 0.1
        if BridgeState.ui ~= nil and BridgeState.ui.fastPlaytest then nextDelay = math.min(nextDelay, 0.05) end
        return nextDelay
    end)()
    BridgeWaitTime(function()
        local ok, continuationError = pcall(function()
            if processingSessionId ~= BridgeState.eventSessionId
                or processingSessionGeneration ~= (BridgeState.eventSessionGeneration or 0)
                or not BridgePhysicalPresentationIsCurrent(processingSessionId, processingPhysicalTransactionGeneration) then
                return
            end
            BridgeState.animationRunning = false
            BridgeState.eventDrainTransaction = nil
            BridgeProcessEventQueue()
        end)
        if not ok then
            BridgeState.animationRunning = false
            BridgeState.eventDrainTransaction = nil
            BridgeLog("[Bridge] EVENT_DRAIN_CONTINUATION_FAILED error=" .. tostring(continuationError))
            BridgeStopOnDesync("event drain continuation failed: " .. tostring(continuationError))
        end
    end, continuationDelay)

    if not delayPostCommitWork then
        local postCommitOk, postCommitError = pcall(function()
            BridgeTryPresentPendingDecision("event-applied")
            if event.kind == "draw" or event.kind == "turn_changed" or event.kind == "phase_changed" then
                -- The old menu may still be rendered when Forge changes state. Ask
                -- Forge for the replacement directly; the refresh is bounded and
                -- single-flight, and acceptance preserves hand-action readiness.
                BridgeRefreshDecisionAfterStateTransition(event.kind)
            end
            if BridgeShouldReconcileAfterEvent(event) then
                BridgeScheduleSnapshotReconcile("event " .. tostring(event.sequence) .. " recovery", "RECOVERY")
            end
        end)
        if not postCommitOk then
            BridgeLog("[Bridge] EVENT_TX_POST_COMMIT_FAILED eventSequence=" .. tostring(event.sequence)
                .. " error=" .. tostring(postCommitError))
            BridgeStopOnDesync("event post-commit failed: " .. tostring(postCommitError))
        end
    end
end

-- Decisions are fetched from Forge independently of the animation queue.
-- A decision can therefore already describe event N while TTS is still
-- presenting an older event. Those older events must not erase the current
-- decision or regress its authoritative phase/turn/priority mirror.
function BridgeCurrentDecisionOutrunsEvent(event)
    local decision = BridgeState.lastDecision
    if decision == nil or event == nil then return false end
    local decisionCursor = tonumber(decision.eventCursor or 0) or 0
    local eventSequence = tonumber(event.sequence or 0) or 0
    return decisionCursor > 0 and eventSequence > 0 and decisionCursor > eventSequence
end

function BridgePhaseEventMatchesCurrentDecision(event)
    local decision = BridgeState.lastDecision
    if decision == nil or event == nil then return false end
    local decisionCursor = tonumber(decision.eventCursor or 0) or 0
    local eventSequence = tonumber(event.sequence or 0) or 0
    if decisionCursor ~= eventSequence or decisionCursor <= 0 then return false end
    local decisionPhase = string.lower(tostring(decision.phaseName or ""))
    local eventPhase = string.lower(tostring(event.phase or ""))
    return decisionPhase ~= "" and decisionPhase == eventPhase
end

-- A poll response can outrun the event queue, but it can also be followed by
-- an already-buffered event from an older turn/phase.  Applying that older
-- event would regress the HUD while trying to preserve the newer decision.
-- Only contradictory events are suppressed; a matching or corroborating
-- event still updates the authoritative BridgeState fields below.
function BridgeAuthoritativeEventSupersededByDecision(event)
    if not BridgeCurrentDecisionOutrunsEvent(event) then return false end
    local decision = BridgeState.lastDecision
    if decision == nil then return false end
    local eventTurn = tonumber(event.turnNumber or 0) or 0
    local decisionTurn = tonumber(decision.turnNumber or 0) or 0
    if eventTurn > 0 and decisionTurn > 0 and eventTurn < decisionTurn then return true end
    if event.kind == "turn_changed"
        and event.activeSeatId ~= nil and decision.activeSeatId ~= nil
        and event.activeSeatId ~= decision.activeSeatId then
        return true
    end
    if event.kind == "phase_changed"
        and event.phase ~= nil and tostring(event.phase) ~= ""
        and decision.phaseName ~= nil and tostring(decision.phaseName) ~= "" then
        local eventPhase = string.upper(tostring(event.phase))
        local decisionPhase = string.upper(tostring(decision.phaseName))
        local function family(value)
            if string.find(value, "UPKEEP", 1, true) then return "UPKEEP" end
            if string.find(value, "DRAW", 1, true) then return "DRAW" end
            if string.find(value, "MAIN", 1, true) then return "MAIN" end
            if string.find(value, "ATTACK", 1, true)
                or string.find(value, "BLOCK", 1, true)
                or string.find(value, "DAMAGE", 1, true)
                or string.find(value, "COMBAT", 1, true) then return "COMBAT" end
            if string.find(value, "END", 1, true) or string.find(value, "CLEANUP", 1, true) then return "END" end
            return value
        end
        if family(eventPhase) ~= family(decisionPhase) then return true end
    end
    return false
end

function BridgeApplyAuthoritativeEvent(event)
    BridgeUiRecordEvent(event)
    if event.containsHiddenIdentity == true then
        BridgeLog(string.format(
            "[Bridge] private event seq=%s kind=%s seat=%s instance=%s source=%s dest=%s (card identity redacted)",
            tostring(event.sequence),
            tostring(event.kind),
            tostring(event.seatId),
            tostring(event.cardInstanceId),
            tostring(event.sourceZone),
            tostring(event.destinationZone)))
    else
        BridgeLog(string.format(
            "[Bridge] event seq=%s kind=%s seat=%s instance=%s source=%s dest=%s card=%s",
            tostring(event.sequence),
            tostring(event.kind),
            tostring(event.seatId),
            tostring(event.cardInstanceId),
            tostring(event.sourceZone),
            tostring(event.destinationZone),
            tostring(event.cardName)))
    end

    if event.kind == "game_ended" then
        BridgeState.gameEnded = {
            winnerSeatIds = event.winnerSeatIds or {},
            loserSeatIds = event.loserSeatIds or {},
            reason = event.gameEndReason
        }
        BridgeState.pendingDecision = nil
        BridgeState.lastDecision = nil
        BridgeState.submitting = false
        if BridgeCancelFastForward ~= nil then BridgeCancelFastForward("game-ended") end
        BridgeClearHighlights()
        BridgeRollbackPendingIntent()
        BridgeResetSelectionState()
        BridgeHideMainPriorityControls()
        BridgeStopDecisionPolling()
        BridgeStopEventPolling("game-ended")
        BridgeScheduleSnapshotReconcile("game_ended final state")
        local humanWon = false
        for _, seatId in ipairs(BridgeState.gameEnded.winnerSeatIds) do
            if seatId == "forge-player-1" then humanWon = true end
        end
        local label = #BridgeState.gameEnded.winnerSeatIds == 0 and "DRAW"
            or (humanWon and "VICTORY" or "DEFEAT")
        BridgeSetStatus(label, "GAME OVER" .. (event.gameEndReason and (": " .. tostring(event.gameEndReason)) or ""))
        broadcastToAll("[Bridge] " .. label .. " — game over", humanWon and {0.2, 0.9, 0.3} or {0.95, 0.3, 0.3})
        BridgeLog("[Bridge] GAME_ENDED winners=" .. table.concat(BridgeState.gameEnded.winnerSeatIds, ",")
            .. " losers=" .. table.concat(BridgeState.gameEnded.loserSeatIds, ",")
            .. " reason=" .. tostring(event.gameEndReason))
        return true, 0
    end

    local seat = BRIDGE_SEATS[event.seatId]
    if seat == nil then
        -- Combat layout is cosmetic and an exact structured combat snapshot
        -- can repair it.  Never guess a physical owner from an unscoped text
        -- event, but also never stop a live match before that snapshot arrives.
        if event.kind == "attack_declared" or event.kind == "block_declared" then
            BridgeLog("[Bridge] ignored unscoped combat presentation event=" .. tostring(event.sequence)
                .. " kind=" .. tostring(event.kind) .. "; awaiting structured combat snapshot")
            BridgeScheduleSnapshotReconcile("unscoped combat event " .. tostring(event.sequence))
            return true, 0
        end
        return false, 0, "event " .. tostring(event.sequence) .. " has no configured seat " .. tostring(event.seatId)
    end

    if event.kind == "turn_changed" then
        local supersededByDecision = BridgeAuthoritativeEventSupersededByDecision(event)
        if supersededByDecision then
            BridgeLog(string.format(
                "[Bridge] applying superseded turn projection while retaining decision event=%s decision=%s",
                tostring(event.sequence), tostring(BridgeState.lastDecision and BridgeState.lastDecision.decisionId)))
        end
        local retainCurrentDecision = supersededByDecision or BridgeCurrentDecisionOutrunsEvent(event)
        if retainCurrentDecision then
            BridgeLog(string.format(
                "[Bridge] applying queued turn event while retaining newer decision %s event=%s decisionCursor=%s",
                tostring(BridgeState.lastDecision.decisionId), tostring(event.sequence),
                tostring(BridgeState.lastDecision.eventCursor)))
        end
        local turnSignature = table.concat({
            tostring(event.turnNumber or ""),
            tostring(event.activeSeatId or event.seatId or ""),
            tostring(event.prioritySeatId or "")
        }, "|")
        if BridgeState.lastTurnEventSignature == turnSignature then
            return true, 0
        end
        BridgeState.lastTurnEventSignature = turnSignature
        BridgeState.turnSourceEventSequence = event.sequence
        BridgeReturnAttackPresentation(nil)
        local probe = BridgeState.latencyProbe
        if probe ~= nil and probe.acceptedAt ~= nil and probe.turnChangedAppliedAt == nil then
            probe.turnChangedAppliedAt = os.clock()
        end
        if event.activeSeatId ~= nil then
            BridgeState.currentTurnSeatId = event.activeSeatId
        else
            BridgeState.currentTurnSeatId = event.seatId
        end
        BridgeState.activePlayerSourceEventSequence = event.sequence
        -- Priority is an independent Forge state transition. Keep the last
        -- known value here when this turn event has no priority payload; the
        -- following priority event will update it authoritatively.
        if event.prioritySeatId ~= nil then
            BridgeState.prioritySeatId = event.prioritySeatId
            BridgeState.prioritySourceEventSequence = event.sequence
        end
        BridgeRecordAuthoritativeTurn(BridgeState.currentTurnSeatId, tonumber(event.turnNumber or 0))
        local turnSeat = BRIDGE_SEATS[BridgeState.currentTurnSeatId]
        BridgeSetStatus("CURRENT TURN: " .. tostring(turnSeat and turnSeat.ttsColor or BridgeState.currentTurnSeatId), BridgeTurnLabel() .. " - AI THINKING")
        BridgeLog("[Bridge] authoritative turn changed to seat " .. tostring(BridgeState.currentTurnSeatId) .. " turn=" .. tostring(event.turnNumber))
        -- End Turn means "the remainder of this turn". A turn transition is
        -- authoritative proof that scope has ended even when a legacy text
        -- event lacks a numeric turn value or a reliable seat label.
        if BridgeState.yieldPolicyTurnNumber ~= nil then
            BridgeState.yieldPolicyTurnNumber = nil
            BridgeState.yieldPolicyActiveSeatId = nil
            BridgeState.yieldPolicySessionId = nil
            BridgeState.yieldPolicyOwnTurn = false
            BridgeLog("[Bridge] cleared HUD yield policy at authoritative turn transition")
        end
        if BridgeCancelFastForward ~= nil then BridgeCancelFastForward("turn-change") end
        -- A turn boundary retires any decision belonging to the previous
        -- priority/phase transaction. BridgeCurrentDecisionOutrunsEvent above
        -- protects a genuinely newer decision that arrived before this event;
        -- once the event is authoritative, retaining the old decision would
        -- keep stale decision controls mounted and can hide YIELD TURN on the
        -- new opponent turn.
        if not retainCurrentDecision then
            BridgeState.lastDecision = nil
            BridgeState.pendingDecision = nil
            BridgeResetSelectionState()
            BridgeClearHighlights()
        end
        BridgeMarkTransitionExpected(0)
        BridgeUiMarkDirty("turn")
        return true, 0.1
    end

    if event.kind == "phase_changed" then
        local supersededByDecision = BridgeAuthoritativeEventSupersededByDecision(event)
        if supersededByDecision then
            BridgeLog(string.format(
                "[Bridge] applying superseded phase projection while retaining decision event=%s phase=%s decision=%s",
                tostring(event.sequence), tostring(event.phase),
                tostring(BridgeState.lastDecision and BridgeState.lastDecision.decisionId)))
        end
        local retainCurrentDecision = supersededByDecision or BridgeCurrentDecisionOutrunsEvent(event)
        if retainCurrentDecision then
            BridgeLog(string.format(
                "[Bridge] applying queued phase event while retaining newer decision %s event=%s decisionCursor=%s",
                tostring(BridgeState.lastDecision.decisionId), tostring(event.sequence),
                tostring(BridgeState.lastDecision.eventCursor)))
        end
        retainCurrentDecision = retainCurrentDecision or BridgePhaseEventMatchesCurrentDecision(event)
        local phaseSignature = table.concat({
            tostring(event.turnNumber or ""),
            tostring(event.activeSeatId or ""),
            tostring(event.prioritySeatId or ""),
            tostring(event.phase or "")
        }, "|")
        if BridgeState.lastPhaseEventSignature == phaseSignature then
            return true, 0
        end
        BridgeState.lastPhaseEventSignature = phaseSignature
        BridgeState.currentPhase = event.phase or "Unknown phase"
        BridgeState.phaseSourceEventSequence = event.sequence
        if event.turnNumber ~= nil and tonumber(event.turnNumber) ~= nil and tonumber(event.turnNumber) > 0 then
            BridgeState.tableTurnCount = tonumber(event.turnNumber)
            BridgeRefreshTurnCounterLabels()
        end
        if event.activeSeatId ~= nil then
            BridgeState.currentTurnSeatId = event.activeSeatId
            BridgeState.activePlayerSourceEventSequence = event.sequence
        end
        -- Phase and priority are independent authoritative values. Do not
        -- overwrite priority from a phase event that carries no priority.
        if event.prioritySeatId ~= nil then
            BridgeState.prioritySeatId = event.prioritySeatId
            BridgeState.prioritySourceEventSequence = event.sequence
        end
        if not retainCurrentDecision then
            BridgeClearHighlights()
        end
        if not retainCurrentDecision and BridgeState.lastDecision ~= nil and not BridgeState.submitting then
            BridgeState.lastDecision = nil
        end
        if BridgeState.pendingDecision ~= nil then
            local ignorePending = BridgeShouldIgnoreStaleDecision(BridgeState.pendingDecision)
            if ignorePending then
                BridgeState.pendingDecision = nil
                BridgeState.pendingDecisionDeferredAt = nil
                BridgeState.pendingDecisionDeferredCursor = 0
                BridgeState.pendingDecisionDeferredApplied = 0
            end
        end
        if not retainCurrentDecision then
            BridgeResetSelectionState()
            BridgeHideMainPriorityControls()
        end
        BridgeSetStatus(
            "CURRENT TURN: " .. tostring((BRIDGE_SEATS[BridgeState.currentTurnSeatId] or {}).ttsColor or BridgeState.currentTurnSeatId or "Unknown"),
            BridgeTurnLabel() .. " - PHASE: " .. tostring(BridgeState.currentPhase))
        local phase = string.lower(tostring(event.phase or ""))
        if string.find(phase, "main phase", 1, true) ~= nil
            or string.find(phase, "end", 1, true) ~= nil
            or string.find(phase, "cleanup", 1, true) ~= nil then
            BridgeReturnAttackPresentation(event.seatId)
        end
        BridgeTryPresentPendingDecision("phase-change")
        if retainCurrentDecision and BridgeState.lastDecision ~= nil then
            -- The exact same Forge cursor/phase remains actionable. Refresh
            -- status and highlights after the phase ribbon update without
            -- replacing its selection/cast-preview state.
            BridgeRenderDecision(BridgeState.lastDecision, true)
        end
        BridgeUiMarkDirty("phase")
        return true, 0.1
    end

    if event.kind == "priority_changed" then
        if BridgeCurrentDecisionOutrunsEvent(event) then
            BridgeLog(string.format(
                "[Bridge] retaining newer decision %s over queued priority event=%s decisionCursor=%s",
                tostring(BridgeState.lastDecision.decisionId), tostring(event.sequence),
                tostring(BridgeState.lastDecision.eventCursor)))
            return true, 0
        end
        local prioritySignature = table.concat({
            tostring(event.turnNumber or ""),
            tostring(event.activeSeatId or ""),
            tostring(event.seatId or ""),
            tostring(event.prioritySeatId or ""),
            tostring(event.phase or "")
        }, "|")
        if BridgeState.lastPriorityEventSignature == prioritySignature then
            return true, 0
        end
        BridgeState.lastPriorityEventSignature = prioritySignature
        -- Priority is an independent Forge state transition. It may change
        -- while active turn and phase remain unchanged and must not depend on
        -- a decision menu being visible.
        BridgeState.prioritySeatId = event.prioritySeatId or event.seatId
        if event.activeSeatId ~= nil then BridgeState.currentTurnSeatId = event.activeSeatId end
        if event.phase ~= nil and tostring(event.phase) ~= "" then BridgeState.currentPhase = event.phase end
        if event.turnNumber ~= nil and tonumber(event.turnNumber) ~= nil and tonumber(event.turnNumber) > 0 then
            BridgeState.tableTurnCount = tonumber(event.turnNumber)
            BridgeRefreshTurnCounterLabels()
        end
        BridgeLog("[Bridge] authoritative priority changed to seat " .. tostring(BridgeState.prioritySeatId))
        BridgeUiMarkDirty("priority")
        return true, 0.1
    end

    if event.kind == "player_state" and event.lifeTotal ~= nil then
        BridgeState.playerStateBySeatId[event.seatId] = BridgeState.playerStateBySeatId[event.seatId] or {}
        BridgeState.playerStateBySeatId[event.seatId].life = event.lifeTotal
        BridgeState.playerStateBySeatId[event.seatId].poison = event.poisonCounters
        if event.counters ~= nil then
            local counters = {}
            for counterKind, counterValue in pairs(event.counters) do
                counters[BridgeNormalizeCounterName(counterKind)] = tonumber(counterValue) or 0
            end
            BridgeState.playerCountersBySeatId[event.seatId] = counters
            BridgeState.playerStateBySeatId[event.seatId].counters = counters
        end
        local lifeCounter = getObjectFromGUID(seat.lifeCounterGuid)
        if lifeCounter == nil then
            return false, 0, "missing life counter for seat " .. tostring(event.seatId)
        end
        local updated, lifeError = pcall(function()
            lifeCounter.setValue(event.lifeTotal)
        end)
        if not updated then
            return false, 0, "could not set life for seat " .. tostring(event.seatId) .. ": " .. tostring(lifeError)
        end
        if event.poisonCounters ~= nil then
            BridgeSetSeatTracker(event.seatId, "poison", event.poisonCounters)
        end
        if event.counters ~= nil then BridgeRefreshResourceRow(event.seatId) end
        BridgeUiMarkDirty("player-state")
        return true, 0.1
    end

    if event.kind == "designation_changed" then
        if event.speed ~= nil then BridgeSetSeatTracker(event.seatId, "speed", event.speed) end
        BridgeSetMonarchSeat(event.monarchSeatId)
        BridgeUiMarkDirty("designation")
        return true, 0.1
    end

    if event.kind == "mana_pool_changed" and event.manaPool ~= nil then
        BridgeSetManaBank(event.seatId, event.manaPool)
        BridgeUiMarkDirty("mana")
        return true, 0.1
    end

    if event.kind == "draw" then
        local applied, drawError = BridgeApplyStructuredCardMove(event)
        return applied, BRIDGE_DRAW_EVENT_PRESENTATION_DELAY, drawError
    end

    if event.kind == "card_moved" then
        local applied, moveError = BridgeApplyStructuredCardMove(event)
        if event.cardInstanceId ~= nil and event.destinationZone ~= nil then
            BridgeState.pendingStructuredZoneTransitionByInstanceId[event.cardInstanceId] = {
                sourceZone = event.sourceZone,
                destinationZone = event.destinationZone,
                sequence = event.sequence,
                applied = applied == true,
            }
        end
        if not applied and BridgeCanDeferStructuredMoveToSnapshot(event) then
            BridgeLog("[Bridge] structured move deferred to snapshot reconcile: " .. tostring(moveError))
            return true, 0.1
        end
        -- A stack/battlefield transition is already embodied by an exact
        -- physical card. Do not hold it behind the long library/zone
        -- presentation delay while Forge has already advanced its phase.
        local presentationDelay = (event.destinationZone == "battlefield"
            or event.destinationZone == "stack") and 0.1 or 1.0
        return applied, presentationDelay, moveError
    end

    -- Some tested Forge TUI resolution lines do not have a second text event
    -- for stack -> graveyard. The resolved card identity is still Forge's;
    -- this only gives its already-authoritative result a physical location.
    if event.kind == "spell_resolved" and event.destinationZone == "graveyard" then
        -- Some Forge TUI resolution lines omit the numeric object id.  If the
        -- exact human cast preview is still present, the pending GUID below
        -- remains safe to use.  Otherwise this is only a semantic duplicate
        -- (the structured snapshot/card_moved stream owns identity); do not
        -- guess a same-name card from the battlefield, hand, or stack.
        if event.cardInstanceId == nil then
            local pendingCast = BridgeState.pendingCastBySeatId[event.seatId]
            local pendingObject = pendingCast ~= nil and getObjectFromGUID(pendingCast.guid) or nil
            if pendingObject == nil or not BridgeCardNameMatches(pendingObject.getName(), event.cardName) then
                BridgeState.pendingCastBySeatId[event.seatId] = nil
                BridgeLog(string.format(
                    "[Bridge] semantic spell resolution deferred event=%s card=%s: no exact Forge instance; awaiting structured snapshot",
                    tostring(event.sequence), tostring(event.cardName)))
                BridgeScheduleSnapshotReconcile("semantic spell resolution without exact instance")
                return true, 0.1
            end
            -- A crew/activated-ability resolution can be printed by Forge's TUI
            -- with spell-like wording even though the source permanent never
            -- entered the stack.  Never turn that semantic line into a physical
            -- zone move.  A pending physical cast is the only case in which this
            -- instance may be moved by the instance-less resolution fallback, and
            -- it must still be tracked on the bridge stack.
            local pendingGuid = BridgeSafeObjectGuid(pendingObject)
            local pendingZone = pendingGuid and BridgeState.physicalZoneByGuid[pendingGuid] or nil
            if pendingZone ~= "stack" then
                BridgeState.pendingCastBySeatId[event.seatId] = nil
                BridgeLog(string.format(
                    "[Bridge] semantic spell resolution ignored for non-stack object event=%s card=%s guid=%s trackedZone=%s; awaiting authoritative snapshot",
                    tostring(event.sequence), tostring(event.cardName), tostring(pendingGuid), tostring(pendingZone)))
                BridgeScheduleSnapshotReconcile("semantic ability resolution for non-stack object")
                return true, 0.1
            end
        end
        if event.cardInstanceId ~= nil then
            local structuredMove = BridgeState.pendingStructuredZoneTransitionByInstanceId[event.cardInstanceId]
            if structuredMove ~= nil and structuredMove.applied == true
                and structuredMove.destinationZone == "graveyard" then
                -- The exact instance has already been embodied by the ordered
                -- card_moved event. Do not require it to still be in stack (or
                -- re-resolve it by name) for this explanatory semantic event.
                BridgeState.pendingCastBySeatId[event.seatId] = nil
                BridgeLog(string.format(
                    "[Bridge] idempotent spell resolution event=%s instance=%s after structured graveyard move=%s",
                    tostring(event.sequence), tostring(event.cardInstanceId), tostring(structuredMove.sequence)))
                return true, 0.1
            end
            local mappedGuid = BridgeState.physicalByInstanceId[event.cardInstanceId]
            local mappedObject = BridgeGetLiveObjectByGuid(mappedGuid)
            local mappedSeat = mappedGuid and BridgeState.physicalSeatByGuid[mappedGuid] or nil
            local mappedZone = mappedGuid and BridgeState.physicalZoneByGuid[mappedGuid] or nil
            local inverseInstanceId = mappedGuid and BridgeState.physicalInstanceIdByGuid[mappedGuid] or nil
            if mappedObject ~= nil and mappedObject.tag == "Card" and mappedZone == "graveyard" then
                if mappedSeat ~= event.seatId then
                    return false, 0, BridgePhysicalMappingError(event, "graveyard", 0,
                        "exact resolved spell destination belongs to a different seat", {mappedGuid = mappedGuid})
                end
                if inverseInstanceId ~= event.cardInstanceId then
                    return false, 0, BridgePhysicalMappingError(event, "graveyard", 0,
                        "resolved spell destination GUID belongs to a different Forge instance", {mappedGuid = mappedGuid})
                end
                BridgeState.pendingCastBySeatId[event.seatId] = nil
                BridgeLog(string.format(
                    "[Bridge] idempotent spell resolution event=%s instance=%s already at graveyard",
                    tostring(event.sequence), tostring(event.cardInstanceId)))
                return true, 0.1
            end
            if mappedObject ~= nil and mappedObject.tag == "Card" and mappedZone ~= "stack" then
                -- An exact Forge instance already embodied on the battlefield
                -- (or another non-stack public zone) cannot be the physical
                -- spell being resolved.  This is the characteristic shape of
                -- a crew/activated-ability line: leave the Vehicle in place
                -- and let the authoritative snapshot carry any characteristic
                -- changes instead of moving it to the graveyard.
                BridgeState.pendingCastBySeatId[event.seatId] = nil
                BridgeLog(string.format(
                    "[Bridge] semantic spell resolution ignored for non-stack mapped object event=%s instance=%s guid=%s trackedZone=%s; awaiting authoritative snapshot",
                    tostring(event.sequence), tostring(event.cardInstanceId), tostring(mappedGuid), tostring(mappedZone)))
                BridgeScheduleSnapshotReconcile("semantic ability resolution for non-stack mapped object")
                return true, 0.1
            end
        end
        local object, resolveError = BridgeResolveResolvedSpellObject(event)
        if object == nil then
            -- A semantic resolution line is not an identity-bearing source of
            -- truth.  If its exact physical object is not currently visible,
            -- let the cursor-ordered authoritative snapshot repair the public
            -- zone.  A genuinely missing card still fails in snapshot
            -- multiplicity/reconciliation; do not guess by display name here.
            BridgeLog(string.format(
                "[Bridge] resolved spell presentation deferred event=%s instance=%s card=%s reason=%s",
                tostring(event.sequence), tostring(event.cardInstanceId), tostring(event.cardName), tostring(resolveError)))
            BridgeState.pendingCastBySeatId[event.seatId] = nil
            BridgeScheduleSnapshotReconcile("unmapped resolved spell " .. tostring(event.cardInstanceId or event.cardName))
            return true, 0.1
        end
        local moved, moveError = BridgeMoveToGraveyard(event, object)
        if not moved then return false, 0, moveError end
        return true, 0.8
    end

    if event.kind == "tap_changed" then
        local object, resolveError = BridgeResolveMappedInstance(event)
        if object == nil then
            BridgeLog("[Bridge] tap update deferred to snapshot reconcile: " .. tostring(resolveError))
            return true, 0.1
        end
        local guid = BridgeSafeObjectGuid(object)
        local trackedZone = guid and BridgeState.physicalZoneByGuid[guid] or nil
        if trackedZone ~= "battlefield" then
            BridgeLog(string.format(
                "[Bridge] tap presentation deferred event=%s instance=%s trackedZone=%s",
                tostring(event.sequence), tostring(event.cardInstanceId), tostring(trackedZone)))
            return true, 0.1
        end
        BridgeSetPhysicalTapped(object, event.tapped == true)
        return true, 0.5
    end

    if event.kind == "counter_changed" then
        local object, resolveError = BridgeResolveMappedInstance(event)
        if object == nil then
            BridgeLog("[Bridge] counter update deferred to snapshot reconcile: " .. tostring(resolveError))
            return true, 0.1
        end
        local counters = BridgeState.counterStateByInstanceId[event.cardInstanceId] or {}
        counters[BridgeNormalizeCounterName(event.counterType)] = tonumber(event.counterValue) or 0
        BridgeState.counterStateByInstanceId[event.cardInstanceId] = BridgeCopyCounterMap(counters)
        local applied, counterError = BridgeSetCardCounters(object, counters)
        if not applied then
            BridgeLog("[Bridge] optional physical counter decoration skipped: " .. tostring(counterError))
        end
        return true, 0.1, nil
    end

    if event.kind == "keyword_added" or event.kind == "keyword_removed" then
        local object, resolveError = BridgeResolveMappedInstance(event)
        if object == nil then
            BridgeLog("[Bridge] keyword update deferred to snapshot reconcile: " .. tostring(resolveError))
            return true, 0.1
        end
        local keywords = BridgeState.keywordStateByInstanceId[event.cardInstanceId] or {}
        local normalized = BridgeNormalizeKeywordName(event.keyword)
        if event.kind == "keyword_added" then keywords[normalized] = true else keywords[normalized] = nil end
        BridgeState.keywordStateByInstanceId[event.cardInstanceId] = keywords
        local absoluteKeywords = {}
        for keyword, isEnabled in pairs(keywords) do
            if isEnabled then table.insert(absoluteKeywords, keyword) end
        end
        local applied, keywordError = BridgeSetCardKeywords(object, absoluteKeywords)
        if not applied then
            BridgeLog("[Bridge] optional physical keyword decoration skipped: " .. tostring(keywordError))
        end
        return true, 0.1, nil
    end

    if event.kind == "stats_changed" then
        local object, resolveError = BridgeResolveMappedInstance(event)
        if object == nil then
            BridgeLog("[Bridge] stats update deferred to snapshot reconcile: " .. tostring(resolveError))
            return true, 0.1
        end
        -- NetPower/NetToughness are legacy transport fields.  They are zero
        -- for noncreatures, so using them here incorrectly displays 0/0 on
        -- lands.  Only Forge's nullable current characteristics may drive the
        -- native P/T display; nil/nil explicitly clears a stale display.
        local power = event.currentPower
        local toughness = event.currentToughness
        if event.currentTypes ~= nil and #event.currentTypes > 0 then
            local creature = false
            for _, cardType in ipairs(event.currentTypes) do
                if string.lower(tostring(cardType)) == "creature" then creature = true; break end
            end
            if not creature then power, toughness = nil, nil end
        end
        local applied, statsError = BridgeSetDerivedStats(object, power, toughness)
        if not applied then BridgeLog("[Bridge] optional P/T presentation skipped: " .. tostring(statsError)) end
        BridgeLog(string.format(
            "[Bridge] authoritative stats instance=%s power=%s toughness=%s",
            tostring(event.cardInstanceId), tostring(power), tostring(toughness)))
        return true, 0.1, nil
    end

    if event.kind == "controller_changed" then
        local object, resolveError = BridgeResolveMappedInstance(event)
        if object == nil then
            BridgeLog("[Bridge] ownership update deferred to snapshot reconcile: " .. tostring(resolveError))
            return true, 0.1
        end
        local applied, ownershipError = BridgeSetOwnerController(object, event.ownerSeatId, event.controllerSeatId)
        if not applied then BridgeLog("[Bridge] optional owner/controller presentation skipped: " .. tostring(ownershipError)) end
        return true, 0.1, nil
    end

    if event.kind == "characteristic_changed" then
        local object, resolveError = BridgeResolveMappedInstance(event)
        if object == nil then
            BridgeLog("[Bridge] characteristic update deferred to snapshot reconcile: " .. tostring(resolveError))
            return true, 0.1
        end
        if event.currentPower ~= nil or event.currentToughness ~= nil then
            local applied, statsError = BridgeSetDerivedStats(object, event.currentPower, event.currentToughness)
            if not applied then BridgeLog("[Bridge] optional characteristic P/T presentation skipped: " .. tostring(statsError)) end
        end
        return true, 0.1, nil
    end

    if event.kind == "phasing_changed" then
        local object, resolveError = BridgeResolveMappedInstance(event)
        if object == nil then
            BridgeLog("[Bridge] phasing update deferred to snapshot reconcile: " .. tostring(resolveError))
            return true, 0.1
        end
        local applied, phaseError = BridgeSetPhasedState(object, event.phasedOut == true)
        if not applied then BridgeLog("[Bridge] optional phasing presentation skipped: " .. tostring(phaseError)) end
        return true, 0.1, nil
    end

    if event.kind == "face_changed" then
        local object, resolveError = BridgeResolveMappedInstance(event)
        if object == nil then
            BridgeLog("[Bridge] face update deferred to snapshot reconcile: " .. tostring(resolveError))
            return true, 0.1
        end
        BridgeSetFaceState(object, event, event.seatId)
        return true, 0.1, nil
    end

    if not seat.animateAuthoritativeEvents then
        if event.kind == "land_played" and event.cardInstanceId ~= nil then
            -- The semantic land event still describes a hand/library source;
            -- resolving directly against battlefield makes a valid exact card
            -- look missing when the physical move has not happened yet.
            local sourceZone = event.sourceZone or "hand"
            local object, resolveError = BridgeResolvePhysicalCard(event, sourceZone)
            if object == nil then
                BridgeLog(string.format(
                    "[Bridge] non-animated land presentation deferred event=%s instance=%s reason=%s",
                    tostring(event.sequence), tostring(event.cardInstanceId), tostring(resolveError)))
                BridgeScheduleSnapshotReconcile("unmapped non-animated land " .. tostring(event.cardInstanceId))
                return true, 0.1
            end
            local moved, moveError = BridgeMoveToBattlefield(event, object, "land")
            if not moved then return false, 0, moveError end
        end
        if event.kind == "card_moved" and event.destinationZone == "graveyard" and event.cardInstanceId ~= nil then
            local sourceZone = event.sourceZone or "battlefield"
            -- Exile is a valid source zone but might not have been tracked
            if sourceZone == "exile" then
                -- Try multiple zones since exile tracking might have failed
                for _, fallbackZone in ipairs({"battlefield", "hand", "stack", "exile"}) do
                    local object, resolveError = BridgeResolvePhysicalCard(event, fallbackZone)
                    if object ~= nil then
                        local moved, moveError = BridgeMoveToGraveyard(event, object)
                        if not moved then return false, 0, moveError end
                        return true, 0.1
                    end
                end
                return false, 0, "card_moved from exile: could not locate physical card in any zone"
            end
            
            local object, resolveError = BridgeResolvePhysicalCard(event, sourceZone)
            if object == nil then return false, 0, resolveError end
            local moved, moveError = BridgeMoveToGraveyard(event, object)
            if not moved then return false, 0, moveError end
        end
        return true, 0.1
    end

    if event.kind == "land_played" then
        -- Land can be played from hand or library (e.g., via abilities)
        local sourceZone = event.sourceZone or "hand"
        if event.cardInstanceId ~= nil then
            BridgeState.battlefieldKindByInstanceId[event.cardInstanceId] = "land"
        end
        local pendingTransition = event.cardInstanceId ~= nil
            and BridgeState.pendingStructuredZoneTransitionByInstanceId[event.cardInstanceId]
            or nil
        local mappedGuid = event.cardInstanceId and BridgeState.physicalByInstanceId[event.cardInstanceId] or nil
        local mappedObject = mappedGuid and BridgeGetLiveObjectByGuid(mappedGuid) or nil
        if mappedObject ~= nil and mappedObject.tag == "Card"
            and BridgeState.physicalZoneByGuid[mappedGuid] == "battlefield" then
            if BridgeState.physicalSeatByGuid[mappedGuid] ~= event.seatId then
                return false, BridgePhysicalMappingError(event, "battlefield", 0,
                    "exact mapped destination belongs to a different seat", {mappedGuid = mappedGuid})
            end
            local inverseInstanceId = BridgeState.physicalInstanceIdByGuid[mappedGuid]
            if inverseInstanceId ~= nil and inverseInstanceId ~= event.cardInstanceId then
                return false, BridgePhysicalMappingError(event, "battlefield", 0,
                    "mapped destination GUID belongs to a different Forge instance", {mappedGuid = mappedGuid})
            end
            BridgeRecordLooseCardIdentity(event.cardInstanceId, mappedGuid, event.seatId, "battlefield")
            BridgeSetPhysicalFaceDown(mappedObject, seat, event.faceDown == true)
            local repositioned, repositionError = BridgeMoveToBattlefield(event, mappedObject, "land")
            if not repositioned then
                BridgeLog("[Bridge] idempotent land row correction skipped: " .. tostring(repositionError))
            end
            BridgeLog(string.format(
                "[Bridge] idempotent move event=%s instance=%s already at battlefield",
                tostring(event.sequence), tostring(event.cardInstanceId)))
            return true, 0.1
        end
        local object, resolveError = BridgeResolvePhysicalCard(event, sourceZone)
        if object == nil then
            -- Forge emitted an ordered, exact card_moved immediately before
            -- this text-derived land_played event.  If that structured move
            -- could not yet bind the physical card, do not make a second
            -- source-zone lookup (or name fallback) fatal.  The deferred
            -- snapshot is deliberately held behind the event cursor and will
            -- repair the public embodiment after the ordered stream catches
            -- up.  This does not suppress unrelated or wrong-instance moves.
            if pendingTransition ~= nil
                and pendingTransition.destinationZone == "battlefield"
                and pendingTransition.sourceZone == sourceZone then
                BridgeLog(string.format(
                    "[Bridge] semantic land presentation deferred event=%s instance=%s after structured move=%s",
                    tostring(event.sequence), tostring(event.cardInstanceId), tostring(pendingTransition.sequence)))
                return true, 0.1
            end
            if mappedGuid == nil then
                -- Forge may draw and immediately play a land before its
                -- coalesced structured transition reaches TTS. Do not choose
                -- a same-name hand card: wait for that exact instance event.
                BridgeLog(string.format(
                    "[Bridge] semantic land presentation deferred event=%s instance=%s: awaiting exact structured transition",
                    tostring(event.sequence), tostring(event.cardInstanceId)))
                BridgeScheduleSnapshotReconcile("unmapped semantic land " .. tostring(event.cardInstanceId))
                return true, 0.1
            end
            -- This is a redundant human-readable event.  The exact
            -- structured card_moved event may already have taken the card out
            -- of its source zone, leaving a live mapped Card in a different
            -- tracked zone.  Never turn that normal ordering race into a
            -- hard synchronization stop; the authoritative snapshot repairs
            -- any genuinely missing destination.
            BridgeLog(string.format(
                "[Bridge] semantic land presentation deferred event=%s instance=%s mappedGuid=%s reason=%s",
                tostring(event.sequence), tostring(event.cardInstanceId), tostring(mappedGuid), tostring(resolveError)))
            BridgeScheduleSnapshotReconcile("semantic land source already changed " .. tostring(event.cardInstanceId))
            return true, 0.1
        end
        
        -- If it's a deck object (from library), draw the top card
        if object.tag == "Deck" then
            local drawn = object.takeObject({
                position = {object.getPosition()[1], object.getPosition()[2] + 3, object.getPosition()[3]},
                smooth = false
            })
            if drawn == nil then return false, 0, "could not draw land from library deck" end
            object = drawn
            BridgeWaitFrames(function()
                if event.cardInstanceId ~= nil then
                    BridgeRecordLooseCardIdentity(event.cardInstanceId, object.getGUID(), event.seatId, "library")
                end
                local moved, moveError = BridgeMoveToBattlefield(event, object, "land")
                if not moved then
                    BridgeShowError("land from library could not be moved: " .. tostring(moveError))
                end
            end, 2)
            return true, 1.25
        end
        
        local moved, moveError = BridgeMoveToBattlefield(event, object, "land")
        if not moved then return false, 0, moveError end
        return true, 1.25
    end

    if event.kind == "spell_resolved" and event.destinationZone == "battlefield" then
        local resolvedMappedGuid = event.cardInstanceId ~= nil
            and BridgeState.physicalByInstanceId[event.cardInstanceId] or nil
        local resolvedMappedObject = resolvedMappedGuid ~= nil
            and BridgeGetLiveObjectByGuid(resolvedMappedGuid) or nil
        BridgeTracePermanentTransition(
            "SPELL_RESOLVED", event, resolvedMappedObject, event.sourceZone)
        -- Structured card_moved already moved this exact instance from stack to
        -- battlefield. The human-readable semantic line has no instance ID and
        -- must not attempt a second name-based move from an empty stack.
        if event.cardInstanceId == nil then
            -- A human cast has an exact pending physical object even when the
            -- TUI resolution line omits Forge's numeric object id. It is safe
            -- to present that object immediately: the cast action selected its
            -- exact CardInstanceId and the object is still tracked on stack.
            -- AI casts have no pending physical intent and continue to wait for
            -- the exact structured snapshot transition.
            local pendingCast = event.seatId ~= nil
                and BridgeState.pendingCastBySeatId[event.seatId] or nil
            if pendingCast ~= nil and pendingCast.cardInstanceId ~= nil then
                local pendingObject = getObjectFromGUID(pendingCast.guid)
                local pendingName = pendingObject ~= nil and pendingObject.getName() or nil
                local pendingZone = pendingObject ~= nil
                    and BridgeState.physicalZoneByGuid[pendingCast.guid] or nil
                if pendingObject ~= nil and pendingName ~= nil
                    and BridgeCardNameMatches(pendingName, event.cardName)
                    and pendingZone == "stack" then
                    local resolvedEvent = {}
                    for key, value in pairs(event) do resolvedEvent[key] = value end
                    resolvedEvent.cardInstanceId = pendingCast.cardInstanceId
                    BridgeTracePermanentTransition(
                        "STACK_MOVE stack->battlefield", resolvedEvent, pendingObject, "stack")
                    local moved, moveError = BridgeMoveToBattlefield(
                        resolvedEvent, pendingObject, BridgeBattlefieldRowForEvent(resolvedEvent, "creature"))
                    if not moved then return false, 0, moveError end
                    BridgeRetirePendingCastForInstance(
                        event.seatId, resolvedEvent.cardInstanceId, pendingCast.guid,
                        "semantic stack-to-battlefield")
                    BridgeLog(string.format(
                        "[Bridge] presented exact pending cast on semantic resolution event=%s instance=%s",
                        tostring(event.sequence), tostring(resolvedEvent.cardInstanceId)))
                    return true, 0.1
                end
            end
            return true, 0.1
        end
        if resolvedMappedObject ~= nil and resolvedMappedObject.tag == "Card"
            and BridgeState.physicalZoneByGuid[resolvedMappedGuid] == "battlefield"
            and BridgePhysicalObjectAtStackAnchor(resolvedMappedObject) then
            BridgeTracePermanentTransition(
                "STACK_MOVE stack->battlefield", event, resolvedMappedObject, "stack",
                "semantic resolution repaired stranded exact mapping")
            local corrected, correctionError = BridgeMoveToBattlefield(
                event, resolvedMappedObject, BridgeBattlefieldRowForEvent(event, "creature"), false)
            if not corrected then return false, 0, correctionError end
            BridgeRetirePendingCastForInstance(
                event.seatId, event.cardInstanceId, resolvedMappedGuid,
                "semantic stack-to-battlefield correction")
            return true, 0.1
        end
        local object, resolveError = BridgeResolvePhysicalCard(event, "stack")
        if object == nil then return false, 0, resolveError end
        BridgeTracePermanentTransition("STACK_MOVE stack->battlefield", event, object, "stack")
        local moved, moveError = BridgeMoveToBattlefield(event, object, BridgeBattlefieldRowForEvent(event, "creature"))
        if not moved then return false, 0, moveError end
        BridgeRetirePendingCastForInstance(
            event.seatId, event.cardInstanceId, BridgeSafeObjectGuid(object),
            "semantic stack-to-battlefield")
        return true, 1.25
    end

    if event.kind == "mana_ability_used" then
        -- Mana use is a presentation-only consequence of Forge's exact card
        -- instance.  Never resolve it by name: duplicate Mountains are common
        -- and choosing one locally would be a rules/UI lie.  A preceding
        -- structured move may still be awaiting the cursor-gated snapshot;
        -- defer the visual tap in that case (and for any other missing exact
        -- mapping) rather than turning a correct Forge action into a desync.
        local object, resolveError = BridgeResolveMappedInstance(event)
        if object == nil then
            BridgeLog(string.format(
                "[Bridge] mana presentation deferred event=%s instance=%s reason=%s",
                tostring(event.sequence), tostring(event.cardInstanceId), tostring(resolveError)))
            BridgeScheduleSnapshotReconcile("mana event " .. tostring(event.sequence))
            return true, 0.1
        end
        local guid = BridgeSafeObjectGuid(object)
        local trackedZone = guid and BridgeState.physicalZoneByGuid[guid] or nil
        if trackedZone ~= "battlefield" then
            BridgeLog(string.format(
                "[Bridge] mana presentation deferred event=%s instance=%s trackedZone=%s",
                tostring(event.sequence), tostring(event.cardInstanceId), tostring(trackedZone)))
            BridgeScheduleSnapshotReconcile("mana event " .. tostring(event.sequence))
            return true, 0.1
        end
        local rotated, rotationError = pcall(function() BridgeSetPhysicalTapped(object, true) end)
        if not rotated then
            return false, 0, "event " .. tostring(event.sequence) .. " could not tap mapped object: " .. tostring(rotationError)
        end
        return true, 0.8
    end

    if event.kind == "attack_declared" then
        local object, resolveError = BridgeResolvePhysicalCard(event, "battlefield", {allowUntrackedByName = true})
        if object == nil then
            -- Attack declaration is a presentation event, not a zone
            -- transition. A just-created/just-reconciled permanent may not yet
            -- have its reverse GUID ledger entry; let the authoritative
            -- snapshot repair that mapping instead of halting the match.
            BridgeLog("[Bridge] attack presentation deferred: " .. tostring(resolveError))
            BridgeScheduleSnapshotReconcile("attack presentation " .. tostring(event.sequence))
            return true, 0.1
        end
        BridgeMoveToAttackLane(event.seatId, object)
        object.highlightOn({1.0, 0.45, 0.0}, 2)
        return true, 1.0
    end


    if event.kind == "block_declared" then
        local object, resolveError = BridgeResolvePhysicalCard(event, "battlefield", {allowUntrackedByName = true})
        if object == nil then
            BridgeLog("[Bridge] block presentation deferred: " .. tostring(resolveError))
            BridgeScheduleSnapshotReconcile("block presentation " .. tostring(event.sequence))
            return true, 0.1
        end
        BridgeMoveToBlockerLane(event.seatId, object)
        object.highlightOn({1.0, 0.55, 0.0}, 2)
        return true, 1.0
    end

    return true, 0.1
end

function BridgeResolveResolvedSpellObject(event)
    if event == nil then return nil, "resolved spell event is missing" end
    local pendingBySeat = BridgeState.pendingCastBySeatId or {}
    local pendingCast = event.seatId ~= nil and pendingBySeat[event.seatId] or nil
    local pendingObject = pendingCast ~= nil and pendingCast.guid ~= nil and getObjectFromGUID(pendingCast.guid) or nil
    local pendingName = nil
    if pendingObject ~= nil and type(pendingObject.getName) == "function" then
        local ok, value = pcall(function() return pendingObject.getName() end)
        if ok then pendingName = value end
    end
    if pendingObject ~= nil and pendingName ~= nil and BridgeCardNameMatches(pendingName, event.cardName) then
        local pendingGuid = BridgeSafeObjectGuid(pendingObject)
        local pendingZone = pendingGuid and BridgeState.physicalZoneByGuid[pendingGuid] or nil
        if pendingZone ~= "stack" then
            return nil, "pending resolution object is not tracked on stack (zone=" .. tostring(pendingZone) .. ")"
        end
        if event.cardInstanceId ~= nil then
            BridgeRecordLooseCardIdentity(event.cardInstanceId, pendingCast.guid, event.seatId, "stack")
        end
        return pendingObject, nil
    end

    if event.cardInstanceId ~= nil then
        local mapped, mappedError = BridgeResolveMappedInstance(event)
        if mapped ~= nil then return mapped, nil end
        -- An exact Forge instance that is not mapped cannot be recovered by
        -- searching battlefield/hand by display name: that could move a
        -- crewed Vehicle (or any other permanent) for an unrelated semantic
        -- resolution line.  Only the authoritative stack source is eligible
        -- for this presentation-only fallback; otherwise the next ordered
        -- snapshot must repair the mapping.
        local stackObject, stackError = BridgeResolvePhysicalCard(event, "stack")
        if stackObject ~= nil then return stackObject, nil end
        return nil, mappedError or stackError
    end
    local object, resolveError = BridgeResolvePhysicalCard(event, "stack")
    if object ~= nil then return object, nil end
    return nil, resolveError or "resolved spell cannot be uniquely located on the physical stack"
end

-- Prepared is a Forge card designation, not a counter or keyword.  Keep the
-- indication presentation-only by prefixing the card inspection description;
-- the saved description is restored when Forge removes the designation.
function BridgeSetPreparedDesignationPresentation(object, prepared)
    if object == nil or type(object.setDescription) ~= "function" then return false end
    local guid = BridgeSafeObjectGuid(object)
    if guid == nil then return false end
    BridgeState.preparedDescriptionByGuid = BridgeState.preparedDescriptionByGuid or {}
    local saved = BridgeState.preparedDescriptionByGuid[guid]
    local current = ""
    if type(object.getDescription) == "function" then
        local ok, value = pcall(function() return object.getDescription() end)
        if ok and value ~= nil then current = tostring(value) end
    end
    if prepared == true then
        if saved == nil then
            saved = current
            while string.sub(saved, 1, 9) == "PREPARED\n" or string.sub(saved, 1, 10) == "PROTOTYPE\n" do
                saved = string.sub(saved, string.sub(saved, 1, 9) == "PREPARED\n" and 10 or 11)
            end
            BridgeState.preparedDescriptionByGuid[guid] = saved
        end
        local instanceId = BridgeState.physicalInstanceIdByGuid[guid]
        if instanceId ~= nil then
            BridgeState.preparedPresentationGuidByInstanceId[instanceId] = guid
        end
        local desired = "PREPARED"
        if saved ~= "" then desired = desired .. "\n" .. saved end
        if current ~= desired then pcall(function() object.setDescription(desired) end) end
    elseif saved ~= nil then
        pcall(function() object.setDescription(saved) end)
        BridgeState.preparedDescriptionByGuid[guid] = nil
    end
    return true
end

function BridgeSetPrototypeDesignationPresentation(object, prototyped)
    if object == nil or type(object.setDescription) ~= "function" then return false end
    local guid = BridgeSafeObjectGuid(object)
    if guid == nil then return false end
    BridgeState.prototypeDescriptionByGuid = BridgeState.prototypeDescriptionByGuid or {}
    local saved = BridgeState.prototypeDescriptionByGuid[guid]
    local current = ""
    if type(object.getDescription) == "function" then
        local ok, value = pcall(function() return object.getDescription() end)
        if ok and value ~= nil then current = tostring(value) end
    end
    if prototyped == true then
        if saved == nil then
            saved = current
            while string.sub(saved, 1, 9) == "PREPARED\n" or string.sub(saved, 1, 10) == "PROTOTYPE\n" do
                saved = string.sub(saved, string.sub(saved, 1, 9) == "PREPARED\n" and 10 or 11)
            end
            BridgeState.prototypeDescriptionByGuid[guid] = saved
        end
        local desired = "PROTOTYPE"
        if saved ~= "" then desired = desired .. "\n" .. saved end
        if current ~= desired then pcall(function() object.setDescription(desired) end) end
    elseif saved ~= nil then
        pcall(function() object.setDescription(saved) end)
        BridgeState.prototypeDescriptionByGuid[guid] = nil
    end
    return true
end

function BridgeClearCardDesignationPresentation(instanceId, object, clearPrototype)
    if instanceId == nil then return end
    local guid = BridgeState.physicalByInstanceId[instanceId]
        or BridgeState.preparedPresentationGuidByInstanceId[instanceId]
    local live = object or BridgeGetLiveObjectByGuid(guid)
    if live ~= nil then
        BridgeSetPreparedDesignationPresentation(live, false)
        if clearPrototype ~= false then BridgeSetPrototypeDesignationPresentation(live, false) end
    end
    BridgeDestroyPreparedBadge(instanceId)
    BridgeState.preparedPresentationGuidByInstanceId[instanceId] = nil
    BridgeState.preparedDesignationStateByInstanceId[instanceId] = nil
    BridgeState.cardDesignationsByInstanceId[instanceId] = nil
end

function BridgePresentationBadgeNoop(object, playerColor, altClick)
    -- Locked presentation badge; intentionally has no gameplay behavior.
end

function BridgeDestroyPreparedBadge(instanceId)
    local guid = BridgeState.preparedBadgeGuidByInstanceId
        and BridgeState.preparedBadgeGuidByInstanceId[instanceId] or nil
    if guid ~= nil then BridgeUnregisterPresentationObject(guid) end
    local badge = BridgeGetLiveObjectByGuid(guid)
    if badge ~= nil then
        BridgeSafeObjectCall(badge, function(o) o.destruct() end)
    end
    if BridgeState.preparedBadgeGuidByInstanceId ~= nil then
        BridgeState.preparedBadgeGuidByInstanceId[instanceId] = nil
    end
end

function BridgeClearPreparedPresentationObjects()
    local badgeInstances = {}
    for instanceId, _ in pairs(BridgeState.preparedBadgeGuidByInstanceId or {}) do
        table.insert(badgeInstances, instanceId)
    end
    for _, instanceId in ipairs(badgeInstances) do BridgeDestroyPreparedBadge(instanceId) end
    for _, guid in ipairs(BridgeState.preparedSpellControlGuids or {}) do
        BridgeUnregisterPresentationObject(guid)
        local object = BridgeGetLiveObjectByGuid(guid)
        if object ~= nil then
            BridgeSafeObjectCall(object, function(o) o.destruct() end)
        end
    end
    BridgeState.preparedSpellControlGuids = {}
end

function BridgePreparedBadgePosition(object)
    local ok, position = pcall(function() return object.getPosition() end)
    if not ok or position == nil then return nil end
    return {x = position.x, y = position.y + 0.55, z = position.z}
end

function BridgeEnsurePreparedBadge(object, instanceId, prepared)
    if instanceId == nil then return false end
    if not prepared then
        BridgeDestroyPreparedBadge(instanceId)
        return true
    end
    if object == nil or not BridgeObjectIsUsable(object) then return false end
    local position = BridgePreparedBadgePosition(object)
    if position == nil then return false end
    local existingGuid = BridgeState.preparedBadgeGuidByInstanceId[instanceId]
    local existing = BridgeGetLiveObjectByGuid(existingGuid)
    if existing ~= nil then
        pcall(function()
            existing.setPosition(position)
            existing.setRotation(object.getRotation())
        end)
        return true
    end
    local epoch = BRIDGE_RUNTIME_EPOCH_LOCAL
    spawnObject({
        type = "BlockSquare",
        position = position,
        rotation = object.getRotation(),
        scale = {1.45, 0.18, 0.34},
        callback_function = function(badge)
            if not BridgeRuntimeIsCurrent(epoch) then
                if badge ~= nil then badge.destruct() end
                return
            end
            if badge == nil or BridgeState.preparedDesignationStateByInstanceId[instanceId] ~= true then
                if badge ~= nil then badge.destruct() end
                return
            end
            badge.setName("Forge Prepared Status")
            badge.setLock(true)
            BridgeRegisterPresentationObject(badge, "prepared_badge")
            badge.setColorTint({0.42, 0.16, 0.62})
            badge.setRotation(object.getRotation())
            badge.createButton({
                click_function = "BridgePresentationBadgeNoop",
                function_owner = Global,
                label = "PREPARED",
                position = {0, 0.45, 0},
                width = 900,
                height = 250,
                font_size = 90,
                color = {0.42, 0.16, 0.62, 1},
                font_color = {1, 1, 1, 1},
                tooltip = "Forge designation: Prepared"
            })
            badge.setVar("bridgePreparedInstanceId", instanceId)
            BridgeState.preparedBadgeGuidByInstanceId[instanceId] = badge.getGUID()
        end
    })
    return true
end

function BridgePulsePreparedDesignation(object, instanceId)
    if object == nil or BridgeState.preparedDesignationStateByInstanceId[instanceId] ~= true then return end
    -- This is a short transition cue only.  It is deliberately not retained
    -- in highlightedGuids, so blue/orange legal-action semantics remain clear.
    pcall(function() object.highlightOn({0.62, 0.18, 0.86}, 1.5) end)
end

function BridgePreparedSpellPosition(seatId, index)
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then return nil end
    local base = nil
    local ttsColor = seat.ttsColor
    if ttsColor ~= nil and Player[ttsColor] ~= nil and type(Player[ttsColor].getHandTransform) == "function" then
        local ok, hand = pcall(function() return Player[ttsColor].getHandTransform(1) end)
        if ok and hand ~= nil then base = hand.position end
    end
    base = base or seat.libraryAnchor
    if base == nil then return nil end
    local column = ((tonumber(index or 1) or 1) - 1) % 3
    return {x = base.x + 3.2 + column * 3.6, y = base.y + 0.8, z = base.z + seat.tableSideZ * 1.8}
end

function BridgeCastPreparedSpellTile(object, playerColor, altClick)
    if object == nil or BridgeState.submitting then return end
    local decision = BridgeState.lastDecision
    local decisionId = object.getVar("bridgeDecisionId")
    local actionId = object.getVar("bridgeActionId")
    if decision == nil or decision.decisionId ~= decisionId or actionId == nil then
        BridgeShowError("prepared spell presentation is stale")
        return
    end
    local action = nil
    for _, candidate in ipairs(decision.actions or {}) do
        if candidate.actionId == actionId then action = candidate; break end
    end
    if action == nil or tostring(action.castMode or "") ~= "prepare" then
        BridgeShowError("prepared spell action is no longer offered by Forge")
        return
    end
    BridgeClaimHumanTtsColor(decision.seatId, playerColor)
    if BridgeIsStructuredForgeToggleChoice(decision) then
        BridgeSubmitChoice(decisionId, actionId, "physical_player_structured_toggle")
        return
    end
    BridgeClearHighlights()
    BridgeSubmitChoice(decision.decisionId, action.actionId, "prepared_spell_tile")
end

function BridgeRenderPreparedSpellPresentations(decision)
    BridgeClearPreparedSpellControls()
    if decision == nil or decision.actions == nil then return end
    local seat = BRIDGE_SEATS[decision.seatId]
    if seat == nil then return end
    local index = 0
    for _, action in ipairs(decision.actions) do
        if tostring(action.castMode or "") == "prepare" and action.actionId ~= nil then
            index = index + 1
            local position = BridgePreparedSpellPosition(decision.seatId, index)
            if position ~= nil then
                -- Capture loop values before registering the asynchronous TTS
                -- callback so multiple prepared sources cannot cross-bind
                -- their exact Forge ActionIds.
                local renderedDecisionId = decision.decisionId
                local renderedActionId = action.actionId
                local display = tostring(action.displayName or action.shortLabel or "Prepared spell")
                if string.sub(display, 1, 16) == "PREPARED SPELL: " then
                    display = string.sub(display, 17)
                end
                local cost = tostring(action.displayManaCost or "")
                local sourceName = action.preparedSourceCardInstanceId
                    and BridgeState.cardNameByInstanceId[action.preparedSourceCardInstanceId] or nil
                local sourceLabel = sourceName ~= nil and tostring(sourceName) ~= ""
                    and ("\nBY " .. tostring(sourceName)) or ""
                if #display > 28 then display = string.sub(display, 1, 25) .. "..." end
                spawnObject({
                    type = "BlockSquare",
                    position = position,
                    rotation = {0, seat.tableSideZ < 0 and 180 or 0, 0},
                    scale = {1.7, 0.24, 1.15},
                    callback_function = function(control)
                        if control == nil then return end
                        if BridgeState.lastDecision == nil or BridgeState.lastDecision.decisionId ~= renderedDecisionId then
                            BridgeUnregisterPresentationObject(control)
                            control.destruct()
                            return
                        end
                        control.setName("Forge Prepared Spell")
                        control.setLock(true)
                        BridgeRegisterPresentationObject(control, "prepared_spell_affordance")
                        control.setColorTint({0.38, 0.18, 0.60})
                        control.createButton({
                            click_function = "BridgeCastPreparedSpellTile",
                            function_owner = Global,
                            label = "PREPARED SPELL\n" .. display .. sourceLabel
                                .. (cost ~= "" and ("\n" .. cost) or "") .. "\nCAST",
                            position = {0, 0.55, 0},
                            width = 1300,
                            height = 900,
                            font_size = 70,
                            color = {0.38, 0.18, 0.60, 1},
                            font_color = {1, 1, 1, 1},
                            tooltip = "Forge action: cast this prepared spell"
                        })
                        control.setVar("bridgeDecisionId", renderedDecisionId)
                        control.setVar("bridgeActionId", renderedActionId)
                        table.insert(BridgeState.preparedSpellControlGuids, control.getGUID())
                    end
                })
            end
        end
    end
end

function BridgeClearPreparedSpellControls()
    local hadControls = #(BridgeState.preparedSpellControlGuids or {}) > 0
    for _, guid in ipairs(BridgeState.preparedSpellControlGuids or {}) do
        BridgeUnregisterPresentationObject(guid)
        local object = BridgeGetLiveObjectByGuid(guid)
        if object ~= nil then
            BridgeSafeObjectCall(object, function(o) o.destruct() end)
        end
    end
    BridgeState.preparedSpellControlGuids = {}
    if hadControls then BridgeAdvancePhysicalPresentationGeneration("prepared-controls-changed") end
end

function BridgeRecoverFromLibraryOrderMismatch(detail)
    local message = tostring(detail or "")
    local isOrderMismatch = string.find(message, "library top order mismatched", 1, true) ~= nil
        or string.find(message, "single-card library top order mismatched", 1, true) ~= nil
    if not isOrderMismatch then return false end

    -- The physical deck is no longer a trustworthy embodiment of Forge's
    -- ordered library. Rebuild it from the current authoritative snapshot;
    -- this also absorbs any consecutive mill transitions into the graveyard.
    -- Do not select a later contained card by name, which would preserve the
    -- wrong order and make the next draw another synchronization failure.
    BridgeLog("[Bridge] library order mismatch; requesting authoritative resync: " .. message)
    BridgeResyncFromAuthoritativeSnapshot("library order mismatch")
    return true
end

function BridgePreparePhysicalCardForPublicZoneMove(object, destinationZone)
    if object == nil or object.tag ~= "Card" then
        return false, "public-zone move requires a physical game card"
    end
    if destinationZone ~= "battlefield" then
        -- Zone transitions clear presentation-only tap orientation before the
        -- object is placed in a public pile. Forge remains authoritative for
        -- the destination and final tapped state.
        BridgeSetPhysicalTapped(object, false)
        if destinationZone == "graveyard" or destinationZone == "library" then
            return true, nil
        end
    end
    -- Graveyard cards are intentionally locked for readable pile presentation.
    -- A later authoritative public-zone transition must unlock that exact card
    -- before TTS can reuse it; Forge's zone change remains the authority.
    local unlocked, unlockError = pcall(function() object.setLock(false) end)
    if not unlocked then
        return false, "could not unlock card for " .. tostring(destinationZone) .. " move: " .. tostring(unlockError)
    end
    return true, nil
end

function BridgeApplyStructuredCardMove(event)
    if event.cardInstanceId == nil then return false, "structured zone change has no cardInstanceId" end
    BridgeBeginLibraryBatch(event)
    local seat = BRIDGE_SEATS[event.seatId]
    if seat == nil then return false, "structured zone change has no configured seat" end

    -- Preserve the complete producer descriptor alongside the physical map.
    -- Identity/provenance is authoritative transport data; it is never
    -- reconstructed from the card's display name or from a chosen candidate.
    BridgeState.authoritativeObjectByInstanceId[event.cardInstanceId] = {
        objectId = event.authoritativeObjectId or event.cardInstanceId,
        originObjectId = event.originObjectId,
        copySourceObjectId = event.copySourceObjectId,
        objectKind = event.objectKind,
        isCopy = event.isCopy == true,
        isToken = event.isToken == true,
        isVirtual = event.isVirtual == true,
        materializationPolicy = event.materializationPolicy,
        ownerSeatId = event.ownerSeatId,
        controllerSeatId = event.controllerSeatId,
        battlefieldKind = event.battlefieldKind,
        characteristics = event.characteristics
    }

    local staleMappedGuid = nil
    local attemptedZones = {}
    local resolveError = nil

    local guid = BridgeState.physicalByInstanceId[event.cardInstanceId]
    local object = guid ~= nil and BridgeGetLiveObjectByGuid(guid) or nil
    if guid ~= nil and object == nil then
        staleMappedGuid = guid
        BridgeState.physicalByInstanceId[event.cardInstanceId] = nil
        BridgeState.physicalSeatByGuid[guid] = nil
        BridgeState.physicalZoneByGuid[guid] = nil
        BridgeAdvancePhysicalPresentationGeneration("stale-card-mapping")
        guid = nil
    end

    local function allowsMappedDeckHandle(mappedObject)
        if mappedObject == nil or mappedObject.tag ~= "Deck" then return false end
        return event.sourceZone == "library" or event.destinationZone == "library"
    end

    if object ~= nil and object.tag ~= "Card" and not allowsMappedDeckHandle(object) then
        BridgeLog(string.format(
            "[Bridge] stale mapped object for structured move seq=%s kind=%s instance=%s source=%s dest=%s mappedGuid=%s mappedTag=%s",
            tostring(event.sequence), tostring(event.kind), tostring(event.cardInstanceId),
            tostring(event.sourceZone), tostring(event.destinationZone), tostring(guid), tostring(object.tag)))
        BridgeState.physicalByInstanceId[event.cardInstanceId] = nil
        BridgeState.physicalSeatByGuid[guid] = nil
        BridgeState.physicalZoneByGuid[guid] = nil
        BridgeAdvancePhysicalPresentationGeneration("invalid-card-mapping")
        object = nil
        guid = nil
    end

    -- A snapshot may have already placed this exact Forge instance at the
    -- authoritative destination. This is safe only with the inverse exact-id
    -- check and matching seat; never use a same-name card as an idempotence
    -- substitute.
    if object ~= nil and object.tag == "Card" and event.destinationZone ~= nil then
        local mappedSeat = BridgeState.physicalSeatByGuid[guid]
        local mappedZone = BridgeState.physicalZoneByGuid[guid]
        local inverseInstanceId = BridgeState.physicalInstanceIdByGuid[guid]
        if mappedZone == event.destinationZone then
            if mappedSeat ~= event.seatId then
                return false, BridgePhysicalMappingError(event, event.destinationZone, 0,
                    "exact mapped destination belongs to a different seat", {mappedGuid = guid})
            end
            if inverseInstanceId ~= nil and inverseInstanceId ~= event.cardInstanceId then
                return false, BridgePhysicalMappingError(event, event.destinationZone, 0,
                    "mapped destination GUID belongs to a different Forge instance", {mappedGuid = guid})
            end
            if event.destinationZone == "battlefield" then
                local expectedRow = BridgeBattlefieldRowForEvent(event, "creature")
                local priorRow = BridgeState.battlefieldKindByInstanceId[event.cardInstanceId]
                local strandedAtStack = BridgePhysicalObjectAtStackAnchor(object)
                if strandedAtStack then
                    BridgeTracePermanentTransition(
                        "STRUCTURED_MOVE stack->battlefield", event, object, mappedZone,
                        "mapping said battlefield but physical object was at stack anchor")
                end
                if strandedAtStack or priorRow ~= expectedRow then
                    local corrected, correctionError = BridgeMoveToBattlefield(
                        event, object, expectedRow, false)
                    if not corrected then return false, correctionError end
                    BridgeSetPhysicalFaceDown(object, seat, event.faceDown == true)
                    BridgeLog(string.format(
                        "[Bridge] corrected existing battlefield row instance=%s row=%s",
                        tostring(event.cardInstanceId), tostring(expectedRow)))
                    BridgeRetirePendingCastForInstance(
                        event.seatId, event.cardInstanceId, guid, "structured stack-to-battlefield")
                    return true, nil
                end
            end
            BridgeRecordLooseCardIdentity(event.cardInstanceId, guid, event.seatId, event.destinationZone)
            if event.destinationZone == "battlefield" then
                BridgeSetPhysicalFaceDown(object, seat, event.faceDown == true)
            else
                BridgeClearCardDesignationPresentation(event.cardInstanceId, object, event.destinationZone ~= "stack")
            end
            BridgeLog(string.format(
                "[Bridge] idempotent move event=%s instance=%s already at %s",
                tostring(event.sequence), tostring(event.cardInstanceId), tostring(event.destinationZone)))
            return true, nil
        end
    end

    local function recordAttempt(zoneName)
        if zoneName == nil or zoneName == "" then return end
        table.insert(attemptedZones, zoneName)
    end

    local function tryResolveFromZone(zoneName)
        if zoneName == nil or zoneName == "" then return nil end
        recordAttempt(zoneName)
        local candidate, candidateError = BridgeResolvePhysicalCard(event, zoneName, {skipMappedLookup = true})
        if candidate ~= nil then
            resolveError = nil
            return candidate
        end
        resolveError = candidateError
        return nil
    end

    local function libraryDrawError(detail)
        local attemptSummary = #attemptedZones > 0 and table.concat(attemptedZones, ",") or "none"
        return BridgePhysicalMappingError(
            event,
            event.sourceZone or "library",
            0,
            tostring(detail) .. "; authoritativeSource=" .. tostring(event.sourceZone)
                .. "; authoritativeDestination=" .. tostring(event.destinationZone)
                .. "; attemptedZones=" .. attemptSummary,
            {mappedGuid = staleMappedGuid}
        )
    end

    local function moveFromLibraryDeckToHand(deck)
        local hand, handError = BridgeTryGetSeatHandTransform(event.seatId)
        if hand == nil then return false, handError end
        local expectedName = BridgeState.cardNameByInstanceId[event.cardInstanceId] or event.cardName
        local transactionSessionId = BridgeState.eventSessionId
        local transactionGeneration = BridgeState.physicalTransactionGeneration or 0
        BridgeQueueLibraryExtraction(event.seatId, function(complete)
            if not BridgePhysicalPresentationIsCurrent(transactionSessionId, transactionGeneration) then complete(); return end
            local liveDeck = BridgeFindLibraryDeckForSeat(event.seatId)
            if liveDeck == nil then
                BridgeStopOnDesync(libraryDrawError("physical library deck not found while processing queued extraction"))
                complete()
                return
            end
            BridgeTakeTopCardFromLibrary(liveDeck, expectedName, hand.position, true, function(drawn, takeError)
                if not BridgePhysicalPresentationIsCurrent(transactionSessionId, transactionGeneration) then return end
                if drawn == nil then
                    if BridgeRecoverFromLibraryOrderMismatch(takeError) then complete(); return end
                    BridgeStopOnDesync(libraryDrawError(takeError))
                    complete()
                    return
                end
                local drawnGuid = BridgeSafeObjectGuid(drawn)
                if drawnGuid == nil then
                    BridgeStopOnDesync(libraryDrawError("physical library returned a card with no GUID"))
                    complete()
                    return
                end
                if not BridgeRequireArtBearingLibraryCard(drawn, event.seatId, event.cardInstanceId) then
                    BridgeStopOnDesync(libraryDrawError("physical library returned an artless normal game card"))
                    complete()
                    return
                end
                BridgeRecordLooseCardIdentity(event.cardInstanceId, drawnGuid, event.seatId, event.destinationZone)
                drawn.use_hands = true
                BridgeSetPhysicalFaceDown(drawn, seat, event.faceDown == true)
                BridgeWaitFrames(complete, 1)
            end)
        end)
        return true, nil
    end

    local function moveFromLibraryDeckToBattlefield(deck)
        local expectedName = BridgeState.cardNameByInstanceId[event.cardInstanceId] or event.cardName
        local libraryZone = BridgeGetLiveObjectByGuid(seat.libraryZoneGuid)
        if libraryZone == nil then
            return false, "library zone is unavailable for authoritative library-to-battlefield move"
        end
        local staging = libraryZone.getPosition()
        local transactionSessionId = BridgeState.eventSessionId
        local transactionGeneration = BridgeState.physicalTransactionGeneration or 0
        BridgeQueueLibraryExtraction(event.seatId, function(complete)
            if not BridgePhysicalPresentationIsCurrent(transactionSessionId, transactionGeneration) then complete(); return end
            local liveDeck = BridgeFindLibraryDeckForSeat(event.seatId)
            if liveDeck == nil then
                BridgeStopOnDesync(libraryDrawError("physical library deck not found while processing queued extraction"))
                complete()
                return
            end
            BridgeTakeTopCardFromLibrary(liveDeck, expectedName, {staging.x + 4, staging.y + 2, staging.z}, false,
                function(taken, takeError)
                    if not BridgePhysicalPresentationIsCurrent(transactionSessionId, transactionGeneration) then return end
                    if taken == nil then
                        if BridgeRecoverFromLibraryOrderMismatch(takeError) then complete(); return end
                        BridgeStopOnDesync(libraryDrawError(takeError))
                        complete()
                        return
                    end
                    if not BridgeRequireArtBearingLibraryCard(taken, event.seatId, event.cardInstanceId) then
                        BridgeStopOnDesync(libraryDrawError("physical library returned an artless normal game card"))
                        complete()
                        return
                    end
                    local row = BridgeBattlefieldRowForEvent(event, "creature")
                    local moved, moveError = BridgeMoveToBattlefield(event, taken, row)
                    if not moved then BridgeStopOnDesync(libraryDrawError(moveError)) end
                    BridgeWaitFrames(complete, 1)
                end)
        end)
        return true, nil
    end

    -- Mill effects are authoritative library -> graveyard transitions. They
    -- must use the same serialized Deck.takeObject path as draws so each
    -- exact physical card is extracted, turned face-up, and placed in the
    -- graveyard before a later queued draw can present the next hand card.
    -- A Deck handle is never itself a card move.
    local function moveFromLibraryDeckToGraveyard(deck)
        local expectedName = BridgeState.cardNameByInstanceId[event.cardInstanceId] or event.cardName
        local libraryZone = BridgeGetLiveObjectByGuid(seat.libraryZoneGuid)
        if libraryZone == nil then
            return false, "library zone is unavailable for authoritative library-to-graveyard move"
        end
        local staging = libraryZone.getPosition()
        local transactionSessionId = BridgeState.eventSessionId
        local transactionGeneration = BridgeState.physicalTransactionGeneration or 0
        BridgeQueueLibraryExtraction(event.seatId, function(complete)
            if not BridgePhysicalPresentationIsCurrent(transactionSessionId, transactionGeneration) then complete(); return end
            local liveDeck = BridgeFindLibraryDeckForSeat(event.seatId)
            if liveDeck == nil then
                BridgeStopOnDesync(libraryDrawError("physical library deck not found while processing queued graveyard extraction"))
                complete()
                return
            end
            BridgeTakeTopCardFromLibrary(liveDeck, expectedName, {staging.x + 4, staging.y + 2, staging.z}, false,
                function(taken, takeError)
                    if not BridgePhysicalPresentationIsCurrent(transactionSessionId, transactionGeneration) then return end
                    if taken == nil then
                        if BridgeRecoverFromLibraryOrderMismatch(takeError) then complete(); return end
                        BridgeStopOnDesync(libraryDrawError(takeError))
                        complete()
                        return
                    end
                    if not BridgeRequireArtBearingLibraryCard(taken, event.seatId, event.cardInstanceId) then
                        BridgeStopOnDesync(libraryDrawError("physical library returned an artless normal game card"))
                        complete()
                        return
                    end
                    local moved, moveError = BridgeMoveToGraveyard(event, taken)
                    if not moved then
                        BridgeStopOnDesync(libraryDrawError(moveError))
                    end
                    -- Preserve event order in visible presentation: a mill
                    -- must settle in the graveyard before the next queued
                    -- library extraction (including its following draw).
                    BridgeWaitTime(complete, BRIDGE_DRAW_EVENT_PRESENTATION_DELAY)
                end)
        end)
        return true, nil
    end

    local function moveFromTokenFetcherToBattlefield()
        local expectedName = BridgeState.cardNameByInstanceId[event.cardInstanceId] or event.cardName
        local row = BridgeBattlefieldRowForEvent(event, "creature")
        local sessionId = BridgeState.eventSessionId
        local epoch = BRIDGE_RUNTIME_EPOCH_LOCAL
        local started, state = BridgeBeginTokenMaterialization(event.cardInstanceId)
        if not started then
            BridgeLog("[Bridge] token materialization suppressed instance=" .. tostring(event.cardInstanceId)
                .. " state=" .. tostring(state))
            return true, nil
        end
        BridgeTakeCardFromTokenFetcher(expectedName, event.seatId, function(taken, takeError)
            if not BridgeTokenMaterializationIsCurrent(event.cardInstanceId, sessionId, epoch) then
                -- A NEW MATCH/reload or a successful concurrent exact bind made
                -- this callback obsolete. Never cross-bind its returned object.
                if taken ~= nil then BridgeSafeObjectCall(taken, function(card) card.destruct() end) end
                return
            end
            if taken == nil then
                BridgeState.tokenMaterializationByInstanceId[event.cardInstanceId] = nil
                BridgeStopOnDesync(BridgePhysicalMappingError(
                    event,
                    event.sourceZone or "token",
                    0,
                    "token fetcher failed for battlefield materialization: " .. tostring(takeError),
                    {mappedGuid = staleMappedGuid}
                ))
                return
            end
            local moved, moveError = BridgeBindTokenMaterialization(event, taken, row, sessionId, epoch)
            if not moved then
                -- A rejected asynchronous importer object must never turn into
                -- a fake card_moved failure for an unrelated physical card.
                -- Keep Forge authoritative and let the next snapshot retry.
                BridgeLog("[Bridge] token materialization deferred instance="
                    .. tostring(event.cardInstanceId) .. " reason=" .. tostring(moveError))
                BridgeScheduleSnapshotReconcile("token materialization deferred")
            end
        end)
        return true, nil
    end

    local function moveFromCopySourceToBattlefield()
        local copySourceObjectId = event.copySourceObjectId or event.originObjectId
        local sourceGuid = copySourceObjectId ~= nil
            and BridgeState.physicalByInstanceId[copySourceObjectId] or nil
        local source = sourceGuid and BridgeGetLiveObjectByGuid(sourceGuid) or nil
        if source == nil or source.tag ~= "Card" or type(source.clone) ~= "function" then
            return false
        end
        local sessionId = BridgeState.eventSessionId
        local epoch = BRIDGE_RUNTIME_EPOCH_LOCAL
        local started, state = BridgeBeginTokenMaterialization(event.cardInstanceId)
        if not started then
            BridgeLog("[Bridge] copy materialization suppressed instance=" .. tostring(event.cardInstanceId)
                .. " state=" .. tostring(state))
            return true
        end
        local cloned = nil
        local ok = pcall(function()
            cloned = source.clone({position = source.getPosition(), rotation = source.getRotation()})
        end)
        if not ok or cloned == nil then
            BridgeState.tokenMaterializationByInstanceId[event.cardInstanceId].state = "FAILED"
            return false
        end
        local moved, moveError = BridgeBindTokenMaterialization(event, cloned,
            BridgeBattlefieldRowForEvent(event, "creature"), sessionId, epoch)
        if not moved then
            BridgeLog("[Bridge] copy materialization deferred instance="
                .. tostring(event.cardInstanceId) .. " reason=" .. tostring(moveError))
            BridgeScheduleSnapshotReconcile("copy materialization deferred")
        end
        return true
    end

    if object == nil then
        object = tryResolveFromZone(event.sourceZone)
    end
    if object == nil and event.destinationZone ~= nil and event.destinationZone ~= event.sourceZone then
        local idempotent = tryResolveFromZone(event.destinationZone)
        if idempotent ~= nil and idempotent.tag == "Card" then
            object = idempotent
        end
    end
    -- A cast is physically previewed on the stack, while Forge may report the
    -- authoritative transition as hand -> battlefield. Resolve that exact
    -- mapped instance from stack before falling back to a hard mapping error.
    if object == nil and event.destinationZone == "battlefield" then
        object = tryResolveFromZone("stack")
    end

    if event.sourceZone == "library" and event.destinationZone == "hand" and (object == nil or object.tag == "Deck") then
        local deck = object
        if deck == nil then
            deck = BridgeFindLibraryDeckForSeat(event.seatId)
        end
        if deck == nil then
            return false, libraryDrawError(resolveError or "physical library deck not found for authoritative draw")
        end
        return moveFromLibraryDeckToHand(deck)
    end

    if event.sourceZone == "library" and event.destinationZone == "battlefield" and (object == nil or object.tag == "Deck") then
        local deck = object
        if deck == nil then
            deck = BridgeFindLibraryDeckForSeat(event.seatId)
        end
        if deck == nil then
            return false, libraryDrawError(resolveError or "physical library deck not found for authoritative library-to-battlefield move")
        end
        return moveFromLibraryDeckToBattlefield(deck)
    end

    if event.sourceZone == "library" and event.destinationZone == "graveyard" and (object == nil or object.tag == "Deck") then
        local deck = object
        if deck == nil then
            deck = BridgeFindLibraryDeckForSeat(event.seatId)
        end
        if deck == nil then
            return false, libraryDrawError(resolveError or "physical library deck not found for authoritative library-to-graveyard move")
        end
        return moveFromLibraryDeckToGraveyard(deck)
    end

    if object == nil and event.destinationZone == "battlefield"
        and (event.isToken == true or event.sourceZone == "token" or event.sourceZone == "tokens") then
        if event.isCopy == true and moveFromCopySourceToBattlefield() then
            return true, nil
        end
        return moveFromTokenFetcherToBattlefield()
    end

    if object == nil and event.sourceZone == "exile" and event.destinationZone == "hand" then
        -- Hands deliberately do not expose a stable visible identity for every
        -- card. With duplicate Plains, selecting either physical card would be
        -- a lie; Forge has already made the authoritative move. Preserve that
        -- instance as pending and repair its association only when it later
        -- becomes public again.
        BridgeState.pendingPrivateHandIdentityByInstanceId[event.cardInstanceId] = {
            seatId = event.seatId,
            cardName = event.cardName,
            sequence = event.sequence
        }
        BridgeLog(string.format(
            "[Bridge] deferred indistinguishable private-hand mapping seq=%s instance=%s card='%s' reason=%s; Forge move remains authoritative",
            tostring(event.sequence), tostring(event.cardInstanceId), tostring(event.cardName), tostring(resolveError)))
        BridgeScheduleSnapshotReconcile("deferred private hand identity " .. tostring(event.sequence))
        return true, nil
    end

    if object == nil then
        local attemptSummary = #attemptedZones > 0 and table.concat(attemptedZones, ",") or "none"
        return false, BridgePhysicalMappingError(
            event,
            event.sourceZone or "unknown",
            0,
            tostring(resolveError or ("no physical GUID mapped for authoritative instance " .. tostring(event.cardInstanceId)))
                .. "; authoritativeSource=" .. tostring(event.sourceZone)
                .. "; authoritativeDestination=" .. tostring(event.destinationZone)
                .. "; attemptedZones=" .. attemptSummary,
            {mappedGuid = staleMappedGuid}
        )
    end

    if object.tag == "Deck" then
        return false, BridgePhysicalMappingError(
            event,
            event.sourceZone or "unknown",
            0,
            "resolved object is a deck for non-library extraction move",
            {mappedGuid = staleMappedGuid}
        )
    end

    guid = BridgeSafeObjectGuid(object)
    if guid == nil then
        return false, BridgePhysicalMappingError(
            event,
            event.sourceZone or "unknown",
            0,
            "resolved physical card has no GUID",
            {mappedGuid = staleMappedGuid}
        )
    end

    if event.destinationZone ~= "battlefield" then
        local prepared, prepareError = BridgePreparePhysicalCardForPublicZoneMove(object, event.destinationZone)
        if not prepared then return false, prepareError end
        -- Prepared/prototyped are zone-scoped Forge state. Retire their
        -- presentation as soon as the exact physical card leaves the
        -- battlefield; a later snapshot remains authoritative for recovery.
        BridgeClearCardDesignationPresentation(event.cardInstanceId, object, event.destinationZone ~= "stack")
    end

    if event.destinationZone == "hand" then
        local hand, handError = BridgeTryGetSeatHandTransform(event.seatId)
        if hand == nil then return false, handError end
        object.use_hands = true
        BridgeSetPhysicalFaceDown(object, seat, event.faceDown == true)
        object.setPositionSmooth(hand.position, false, true)
    elseif event.destinationZone == "battlefield" then
        object.use_hands = false
        local row = BridgeBattlefieldRowForEvent(event, "creature")
        local sourcePhysicalZone = BridgeState.physicalZoneByGuid[guid] or event.sourceZone
        if sourcePhysicalZone == "stack" then
            BridgeTracePermanentTransition("STRUCTURED_MOVE stack->battlefield", event, object, sourcePhysicalZone)
        end
        local moved, moveError = BridgeMoveToBattlefield(event, object, row)
        if not moved then return false, moveError end
        if sourcePhysicalZone == "stack" then
            BridgeRetirePendingCastForInstance(
                event.seatId, event.cardInstanceId, guid, "structured stack-to-battlefield")
        end
    elseif event.destinationZone == "stack" then
        object.use_hands = false
        BridgeSetPhysicalFaceDown(object, seat, event.faceDown == true)
        object.setPosition(BRIDGE_STACK_POSITION)
    elseif event.destinationZone == "graveyard" then
        local moved, moveError = BridgeMoveToGraveyard(event, object)
        if not moved then return false, moveError end
    elseif event.destinationZone == "exile" then
        object.use_hands = false
        BridgeSetPhysicalTapped(object, false)
        local exilePosition = BridgeResolveSeatZoneAnchor(event.seatId, "exile")
        if exilePosition == nil then
            return false, "no exile anchor configured for seat " .. tostring(event.seatId)
        end
        object.setPositionSmooth(exilePosition, false, true)
    elseif event.destinationZone == "command" then
        object.use_hands = false
        local commandPosition = BridgeResolveSeatZoneAnchor(event.seatId, "command")
        if commandPosition == nil then
            return false, "no command anchor configured for seat " .. tostring(event.seatId)
        end
        object.setPositionSmooth(commandPosition, false, true)
    elseif event.destinationZone == "library" then
        local libraryZone = BridgeGetLiveObjectByGuid(seat.libraryZoneGuid)
        if libraryZone == nil then
            return false, "cannot move to library: configured library zone is unavailable"
        end
        object.use_hands = false
        local returningMarker = BridgeState.mulliganReturningInstanceIds[event.cardInstanceId]
        if returningMarker ~= nil and returningMarker.sessionId == BridgeState.eventSessionId
            and returningMarker.seatId == event.seatId then
            -- Rejected opening-hand cards are authoritative hand->library
            -- moves during the MULLIGAN action.  They belong at the physical
            -- bottom before the replacement draw, not at the deck anchor.
            BridgeState.mulliganReturningInstanceIds[event.cardInstanceId] = nil
            BridgeQueueMulliganBottomInsertion(event.seatId, object)
        elseif BridgeState.mulliganBottomInstanceIds[event.cardInstanceId] == true then
            -- This exact physical placement is only a presentation response to
            -- Forge's accepted post-mulligan selection; it never decides which
            -- cards go to the bottom.
            BridgeState.mulliganBottomInstanceIds[event.cardInstanceId] = nil
            BridgeQueueMulliganBottomInsertion(event.seatId, object)
        else
            local transactionSessionId = BridgeState.eventSessionId
            local transactionGeneration = BridgeState.physicalTransactionGeneration or 0
            BridgeInsertPhysicalCardIntoLibrary(event.seatId, object, "NORMAL", function(inserted, insertError)
                if not BridgePhysicalPresentationIsCurrent(transactionSessionId, transactionGeneration) then
                    BridgeLog("[Bridge] ignored stale library insertion callback event=" .. tostring(event.sequence)
                        .. " generation=" .. tostring(transactionGeneration))
                    return
                end
                if not inserted then
                    BridgeStopOnDesync(BridgePhysicalMappingError(
                        event, "library", 0,
                        "authoritative library move was not physically contained: " .. tostring(insertError),
                        {mappedGuid = guid}))
                    return
                end
                -- The exact loose GUID is retired only after Deck.getObjects()
                -- proves that TTS absorbed this card.
                BridgeRecordLibraryContainedState(event.cardInstanceId, event.seatId, event.cardName)
            end, event.cardInstanceId)
        end
        return true, nil
    end

    BridgeRecordLooseCardIdentity(event.cardInstanceId, guid, event.seatId, event.destinationZone)
    return true, nil
end

function BridgeMoveToGraveyard(event, object)
    local seat = BRIDGE_SEATS[event.seatId]
    if seat == nil then return false, "graveyard move has no configured seat" end
    local graveyardPosition = BridgeGraveyardPosition(event.seatId)
    if graveyardPosition == nil then
        return false, "no graveyard anchor configured for seat " .. tostring(event.seatId)
    end
    local moved, movementError = pcall(function()
        object.use_hands = false
        BridgeSetPhysicalFaceDown(object, seat, false)
        object.setPositionSmooth(graveyardPosition, false, true)
        object.setLock(true)
    end)
    if not moved then return false, "could not move card to graveyard: " .. tostring(movementError) end
    local guid = object.getGUID()
    -- Retire only the exact cast that reached the graveyard. Clearing the
    -- seat-wide slot here can discard a different pending physical cast when
    -- an older semantic resolution event is delivered after the next cast has
    -- already been previewed.
    BridgeRetirePendingCastForInstance(
        event.seatId, event.cardInstanceId, guid, "graveyard-move")
    BridgeClearCardDesignationPresentation(event.cardInstanceId, object)
    BridgeRecordLooseCardIdentity(event.cardInstanceId, guid, event.seatId, "graveyard")
    return true, nil
end

function BridgeFindSeatLibraryDeckWithCard(seat, expectedName)
    local seatId = BridgeSeatIdForSeatConfig(seat)
    local preferred = seatId and BridgeFindLibraryDeckForSeat(seatId) or nil
    if preferred ~= nil and ((preferred.tag == "Card" and BridgeCardNameMatches(BridgePhysicalCanonicalCardName(preferred), expectedName))
        or BridgeDeckContainsCardName(preferred, expectedName)) then
        return preferred
    end
-- END GENERATED SOURCE: 40-zones-materialization.lua
-- BEGIN GENERATED SOURCE: 50-presentation-session.lua

    local candidates = seatId and BridgeFindLibraryDeckCandidatesForSeat(seatId) or {}
    local matches = {}
    for _, deck in ipairs(candidates) do
        if BridgeDeckContainsCardName(deck, expectedName) then
            table.insert(matches, deck)
        end
    end
    if #matches == 1 then return matches[1] end
    if #matches > 1 then
        local nearest = BridgeSelectNearestDeckCandidate(seat, matches)
        if nearest ~= nil then return nearest end
        BridgeLog(string.format("[Bridge] ambiguous library deck match for %s (%d candidates)", tostring(expectedName), #matches))
        return nil
    end

    return nil
end

function BridgeTakeCardFromDeckByIdentity(deck, expectedName, position, smooth, callback)
    if not BridgeObjectIsUsable(deck) then
        callback(nil, "physical library deck is no longer available")
        return
    end

    -- TTS turns a one-card Deck into a Card. It is still the authoritative
    -- library object and must be drawable rather than reported as empty.
    if deck.tag == "Card" then
        if expectedName ~= nil and expectedName ~= "" and not BridgeCardNameMatches(deck.getName(), expectedName) then
            callback(nil, "physical single-card library mismatched authoritative identity")
            return
        end
        deck.setLock(false)
        deck.use_hands = true
        deck.setPositionSmooth(position, smooth == true, true)
        callback(deck, nil)
        return
    end

    local containedCards = {}
    local containedOk = pcall(function() containedCards = deck.getObjects() or {} end)
    if not containedOk then
        callback(nil, "could not inspect physical library deck contents")
        return
    end
    if #containedCards == 0 then
        callback(nil, "physical library deck is empty")
        return
    end

    table.sort(containedCards, function(left, right)
        local leftIndex = tonumber(left.index or -1) or -1
        local rightIndex = tonumber(right.index or -1) or -1
        if leftIndex == rightIndex then
            return tostring(left.guid or "") < tostring(right.guid or "")
        end
        return leftIndex < rightIndex
    end)

    local matched = nil
    for _, contained in ipairs(containedCards) do
        if contained.index ~= nil then
            if expectedName == nil or expectedName == "" then
                matched = contained
                break
            end
            local containedName = contained.nickname or contained.name
            if BridgeCardNameMatches(containedName, expectedName) then
                matched = contained
                break
            end
        end
    end
    if matched == nil then
        callback(nil, "physical library inventory has no card matching authoritative identity")
        return
    end

    local deckGuid = BridgeSafeObjectGuid(deck)
    deck.takeObject({
        index = matched.index,
        position = position,
        smooth = smooth,
        callback_function = function(taken)
            if not BridgeObjectIsUsable(taken) then
                callback(nil, "physical library returned an unusable card object")
                return
            end
            if expectedName ~= nil and expectedName ~= "" and not BridgeCardNameMatches(taken.getName(), expectedName) then
                local liveDeck = BridgeGetLiveObjectByGuid(deckGuid)
                if liveDeck ~= nil then
                    BridgeSafeObjectCall(liveDeck, function(d) d.putObject(taken) end)
                end
                callback(nil, "physical library extraction mismatched authoritative identity")
                return
            end
            callback(taken, nil)
        end
    })
end

-- Forge's library event already identifies the exact instance and its order.
-- For a live transition, take TTS's physical top card rather than selecting a
-- later contained card by its display name. The name is checked only after
-- selecting the top entry, to diagnose a physical-order desync without
-- changing which object Forge's ordered transition embodies.
function BridgeTakeTopCardFromLibrary(deck, expectedName, position, smooth, callback)
    if not BridgeObjectIsUsable(deck) then
        callback(nil, "physical library deck is no longer available")
        return
    end

    if deck.tag == "Card" then
        if expectedName ~= nil and expectedName ~= "" and not BridgeCardNameMatches(deck.getName(), expectedName) then
            callback(nil, "physical single-card library top order mismatched authoritative transition")
            return
        end
        deck.setLock(false)
        deck.use_hands = true
        deck.setPositionSmooth(position, smooth == true, true)
        callback(deck, nil)
        return
    end

    local containedCards = {}
    local containedOk = pcall(function() containedCards = deck.getObjects() or {} end)
    if not containedOk then
        callback(nil, "could not inspect physical library deck contents")
        return
    end
    if #containedCards == 0 then
        callback(nil, "physical library deck is empty")
        return
    end
    table.sort(containedCards, function(left, right)
        local leftIndex = tonumber(left.index or -1) or -1
        local rightIndex = tonumber(right.index or -1) or -1
        if leftIndex == rightIndex then return tostring(left.guid or "") < tostring(right.guid or "") end
        return leftIndex < rightIndex
    end)

    local top = containedCards[1]
    local topName = top and (top.nickname or top.name) or nil
    if top == nil or top.index == nil then
        callback(nil, "physical library has no extractable top card")
        return
    end
    if expectedName ~= nil and expectedName ~= "" and not BridgeCardNameMatches(topName, expectedName) then
        callback(nil, "physical library top order mismatched authoritative transition")
        return
    end

    deck.takeObject({
        index = top.index,
        position = position,
        smooth = smooth,
        callback_function = function(taken)
            if not BridgeObjectIsUsable(taken) then
                callback(nil, "physical library returned an unusable top card object")
                return
            end
            callback(taken, nil)
        end
    })
end

function BridgeTakeNamedCardFromDeck(deck, expectedName, position, smooth, callback)
    BridgeTakeCardFromDeckByIdentity(deck, expectedName, position, smooth, callback)
end

function BridgeTokenNameKey(name)
    local normalized = BridgeNormalizeCardName(name)
    normalized = string.gsub(normalized, "[,%./%-]", " ")
    normalized = string.gsub(normalized, "%f[%a]token%f[%A]", " ")
    normalized = string.gsub(normalized, "^%s+", "")
    normalized = string.gsub(normalized, "%s+$", "")
    normalized = string.gsub(normalized, "%s+", " ")
    return normalized
end

function BridgeTokenNameMatches(ttsName, forgeName)
    -- Token materialization has no safe fallback from a partial name.  A
    -- fuzzy match can bind a similarly named token (or the source permanent)
    -- and is especially dangerous when the utility deck is searched first.
    -- Treat the normalized token name as the reusable visual identity; Forge's
    -- exact CardInstanceId still owns the spawned object's session identity.
    local left = BridgeTokenNameKey(ttsName)
    local right = BridgeTokenNameKey(forgeName)
    if left == "" or right == "" then return false end
    return left == right
end

function BridgeMarkTokenPhysicalObject(object)
    local guid = BridgeSafeObjectGuid(object)
    if guid ~= nil then BridgeState.tokenPhysicalGuids[guid] = true end
end

function BridgeButtonLooksLikeTokenSpawner(button)
    if button == nil then return false end
    local label = string.lower(tostring(button.label or ""))
    local tooltip = string.lower(tostring(button.tooltip or ""))
    local text = label .. " " .. tooltip
    -- A generic Encoder button is not a token producer.  Invoking one here
    -- causes Easy Modules MakeExactCopy/APIobjGetPropData errors and can
    -- mutate an ordinary game card.  Only accept explicit token/emblem
    -- controls; the generic proxy fallback below handles tables without one.
    return string.find(text, "emblem", 1, true) ~= nil
        or string.find(text, "spawn token", 1, true) ~= nil
        or string.find(text, "create token", 1, true) ~= nil
        or string.find(text, "make token", 1, true) ~= nil
end

function BridgeInvokeButtonClick(source, button, seatColor)
    if source == nil or button == nil then return false end
    local clickFunction = tostring(button.click_function or "")
    if clickFunction == "" then return false end

    -- TTS invokes a card button as callback(card, playerColor, altClick).
    -- Card Importer's EmblemsAndTokens handler has exactly that positional
    -- shape. Object.call instead supplies one table, leaving playerColor nil
    -- and producing the Easy Modules nil-call failure seen at the table.
    local globalHandler = _G[clickFunction]
    if type(globalHandler) == "function" then
        local ok, callError = pcall(function()
            globalHandler(source, seatColor, false)
        end)
        if ok then
            BridgeLog("[Bridge] invoked built-in card button positionally function=" .. clickFunction)
            return true
        end
        BridgeLog("[Bridge] positional built-in card button failed function=" .. clickFunction
            .. " error=" .. tostring(callError))
    end

    local payload = {
        obj = source,
        player_color = seatColor,
        alt_click = false,
        altClick = false,
        playerColor = seatColor,
    }

    local owner = button.function_owner
    if type(owner) == "string" then
        if owner == "Global" then
            owner = Global
        else
            owner = BridgeGetLiveObjectByGuid(owner)
        end
    end

    if owner ~= nil and type(owner.call) == "function" then
        local ok = pcall(function()
            owner.call(clickFunction, payload)
        end)
        if ok then return true end
    end

    if source.call ~= nil then
        local ok = pcall(function()
            source.call(clickFunction, payload)
        end)
        if ok then return true end
    end

    return false
end

function BridgeTrySpawnTokenViaEncodeButton(expectedName, seatId, callback)
    -- Kept for diagnostics/backward compatibility only.  A source-card
    -- EmblemsAndTokens callback is not safely invocable through Object.call;
    -- automatic materialization uses BridgeImportExactTokenVisual instead.
    BridgeLog("[Bridge] legacy source-card token button path disabled name=" .. tostring(expectedName))
    callback(nil, "legacy source-card token button path disabled")
end

function BridgeSpawnGenericTokenProxy(expectedName, seatId, callback)
    if expectedName == nil or tostring(expectedName) == "" then
        callback(nil, "generic token proxy requires an authoritative card name")
        return
    end
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then
        callback(nil, "generic token proxy has no configured seat")
        return
    end
    local anchor = seat.battlefieldAnchors and seat.battlefieldAnchors.creature or seat.commandAnchor
    local position = anchor and {anchor.x, (anchor.y or 2.0) + 1.5, anchor.z} or {0, 3.0, 0}
    _spawn({
        type = "Card",
        position = position,
        rotation = seat.faceUpRotation or {0, 0, 0},
        callback_function = function(object)
            if not BridgeObjectIsUsable(object) then
                callback(nil, "generic token proxy spawn returned an unusable object")
                return
            end
            local ok, setupError = pcall(function()
                object.setName(tostring(expectedName))
                object.setDescription("Forge-created token; characteristics are authoritative in Forge")
                object.use_hands = false
                object.setLock(false)
            end)
            if not ok then
                callback(nil, "generic token proxy setup failed: " .. tostring(setupError))
                return
            end
            BridgeLog("[Bridge] DEGRADED token presentation: exact art-bearing import unavailable; using generic Forge token proxy for " .. tostring(expectedName))
            BridgeMarkTokenPhysicalObject(object)
            callback(object, nil)
        end
    })
end

function BridgeIsArtBearingCard(object)
    if not BridgeObjectIsUsable(object) or object.tag ~= "Card" then return false end
    local ok, data = pcall(function() return object.getData() end)
    if not ok or type(data) ~= "table" then return false end
    local customDeck = data.CustomDeck
    if type(customDeck) ~= "table" or next(customDeck) == nil then return false end
    for _, deck in pairs(customDeck) do
        if type(deck) == "table" and tostring(deck.FaceURL or "") ~= "" then
            return true
        end
    end
    return false
end

local BRIDGE_TOKEN_IMPORT_BACK_URL = "https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/"
local BRIDGE_TOKEN_IMPORT_PRIMARY_URL = "https://importer.rikrassen.xyz/build"
local BRIDGE_TOKEN_IMPORT_FALLBACK_URL = "https://importer-m7vpzqazfa-uc.a.run.app/build"

function BridgeExactTokenImportPayload(expectedName)
    return {
        url = "",
        -- This is an exact token request, not a source-card request. The
        -- Rikrassen backend returns one TTS custom-card JSON object for it.
        data = "1 " .. tostring(expectedName),
        backURL = BRIDGE_TOKEN_IMPORT_BACK_URL,
        useStates = true,
        hand = {
            position = {x = 0, y = 0, z = 0},
            forward = {x = 0, y = 0, z = 1},
            right = {x = 1, y = 0, z = 0},
            up = {x = 0, y = 1, z = 0}
        }
    }
end

function BridgeParseExactTokenImportJson(text, expectedName)
    local candidates = {}
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        local ok, candidate = pcall(function() return JSON.decode(line) end)
        if ok and type(candidate) == "table" and candidate.error == nil then
            table.insert(candidates, candidate)
        end
    end
    if #candidates ~= 1 then
        return nil, "exact token importer returned " .. tostring(#candidates) .. " visual results"
    end
    local cardJson = candidates[1]
    local importedName = BridgeNormalizeCardName(cardJson.Nickname or "")
    if importedName ~= BridgeNormalizeCardName(expectedName) then
        return nil, "exact token importer returned " .. tostring(cardJson.Nickname) .. " instead of " .. tostring(expectedName)
    end
    local customDeck = cardJson.CustomDeck
    local hasFace = false
    for _, deck in pairs(customDeck or {}) do
        if type(deck) == "table" and tostring(deck.FaceURL or "") ~= "" then hasFace = true; break end
    end
    if cardJson.Name ~= "Card" or tonumber(cardJson.CardID or -1) < 0 or not hasFace then
        return nil, "exact token importer returned a non-art-bearing card JSON"
    end
    return cardJson, nil
end

function BridgeImportExactTokenVisual(expectedName, seatId, callback)
    if expectedName == nil or tostring(expectedName) == "" then
        callback(nil, "exact token visual import requires an authoritative card name")
        return
    end
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then
        callback(nil, "exact token visual import has no configured seat")
        return
    end

    local anchor = seat.battlefieldAnchors and seat.battlefieldAnchors.creature or seat.commandAnchor
    local position = {x = anchor and anchor.x or 0, y = (anchor and anchor.y or 2.0) + 1.5, z = anchor and anchor.z or 0}
    local rotation = seat.faceUpRotation or {x = 0, y = 0, z = 0}
    local epoch = BRIDGE_RUNTIME_EPOCH_LOCAL
    local completed = false
    local function finish(object, err)
        if completed then return end
        completed = true
        if object ~= nil and not BridgeIsArtBearingCard(object) then
            callback(nil, "exact token visual importer returned a non-art-bearing card")
            return
        end
        callback(object, err)
    end

    local function requestVisual(endpoint, allowFallback)
        WebRequest.custom(endpoint, "POST", true, JSON.encode(BridgeExactTokenImportPayload(expectedName)), {
            ["Content-Type"] = "application/json",
            ["User-Agent"] = "Vokerr-TTS-MTG-Card-Importer",
            ["X-Client-Version"] = "0.9.1"
        }, function(request)
            if not BridgeRuntimeIsCurrent(epoch) then return end
            if request == nil or request.is_error or tonumber(request.response_code or 0) < 200 or tonumber(request.response_code or 0) >= 300 then
                if allowFallback then
                    requestVisual(BRIDGE_TOKEN_IMPORT_FALLBACK_URL, false)
                else
                    finish(nil, "exact token visual backend failed: " .. tostring(request and (request.error or request.response_code) or "unknown error"))
                end
                return
            end
            local cardJson, parseError = BridgeParseExactTokenImportJson(request.text, expectedName)
            if cardJson == nil then
                finish(nil, parseError)
                return
            end
            local spawnHandled = false
            local function handleSpawned(object)
                if spawnHandled then return end
                spawnHandled = true
                if not BridgeObjectIsUsable(object) then
                    finish(nil, "exact token visual spawn returned an unusable object")
                    return
                end
                BridgeWaitFrames(function()
                    if BridgeIsArtBearingCard(object) then
                        BridgeMarkTokenPhysicalObject(object)
                        BridgeLog("[Bridge] token fetcher resolved via exact Rikrassen visual import for " .. tostring(expectedName))
                        finish(object, nil)
                    else
                        finish(nil, "exact token visual spawn produced no CustomDeck/FaceURL")
                    end
                end, 2)
            end
            local spawnOk, objectOrError = pcall(function()
                return spawnObjectJSON({
                    json = JSON.encode(cardJson), position = position, rotation = rotation,
                    callback_function = handleSpawned
                })
            end)
            if not spawnOk then
                finish(nil, "exact token visual spawn failed: " .. tostring(objectOrError))
                return
            end
            if BridgeObjectIsUsable(objectOrError) then handleSpawned(objectOrError) end
        end)
    end

    requestVisual(BRIDGE_TOKEN_IMPORT_PRIMARY_URL, true)
end

function BridgeFindDeckWithContainedCardName(expectedName, excludeDeckGuidSet)
    if expectedName == nil or expectedName == "" then return nil, nil end
    local preferredUtilityDeck = BridgeGetLiveObjectByGuid("946716")
    local candidates = {}
    local expectedTokenKey = BridgeTokenNameKey(expectedName)

    local function addCandidate(container)
        if not BridgeObjectIsUsable(container) then return end
        if container.tag ~= "Deck" and container.tag ~= "Bag" then return end
        local containerGuid = BridgeSafeObjectGuid(container)
        if containerGuid == nil then return end
        if excludeDeckGuidSet ~= nil and excludeDeckGuidSet[containerGuid] == true then return end

        local contained = {}
        local ok = pcall(function() contained = container.getObjects() or {} end)
        if not ok then return end

        local containerName = string.lower(tostring(BridgeSafeObjectName(container) or ""))
        local scoreBase = 0
        if containerGuid == "946716" then scoreBase = scoreBase + 1000 end
        if BridgeIsPresentationOnlyObject(container) then scoreBase = scoreBase + 500 end
        if container.tag == "Bag" then scoreBase = scoreBase + 250 end
        if string.find(containerName, "token", 1, true) ~= nil then scoreBase = scoreBase + 200 end
        if string.find(containerName, "utility", 1, true) ~= nil then scoreBase = scoreBase + 150 end

        for _, item in ipairs(contained) do
            local containedName = item.nickname or item.name or ""
            local exact = BridgeNormalizeCardName(containedName) == BridgeNormalizeCardName(expectedName)
            local tokenExact = expectedTokenKey ~= "" and BridgeTokenNameKey(containedName) == expectedTokenKey
            if exact or tokenExact then
                local entryScore = scoreBase + (exact and 50 or 0) + (tokenExact and 25 or 0)
                table.insert(candidates, {deck = container, entry = item, score = entryScore})
                return
            end
        end
    end

    if preferredUtilityDeck ~= nil then
        addCandidate(preferredUtilityDeck)
        if #candidates > 0 then return candidates[1].deck, candidates[1].entry end
    end

    for _, object in ipairs(getAllObjects()) do
        addCandidate(object)
    end

    if #candidates == 0 then return nil, nil end
    table.sort(candidates, function(left, right)
        if left.score == right.score then
            local leftGuid = BridgeSafeObjectGuid(left.deck) or ""
            local rightGuid = BridgeSafeObjectGuid(right.deck) or ""
            return leftGuid < rightGuid
        end
        return left.score > right.score
    end)
    return candidates[1].deck, candidates[1].entry
end

function BridgeTakeCardFromTokenFetcher(expectedName, seatId, callback)
    local finished = false
    local function finish(object, err)
        if finished then
            BridgeLog("[Bridge] ignored duplicate token visual callback name=" .. tostring(expectedName))
            return
        end
        finished = true
        callback(object, err)
    end
    local excludeDeckGuidSet = {}
    for _, configuredSeatId in ipairs({"forge-player-1", "forge-player-2"}) do
        local deck = BridgeFindLibraryDeckForSeat(configuredSeatId)
        local guid = deck and BridgeSafeObjectGuid(deck) or nil
        if guid ~= nil then excludeDeckGuidSet[guid] = true end
    end

    local function fallbackVisualImport(reason)
        -- Source-card buttons such as EmblemsAndTokens are not a generic
        -- token-import API.  Their TTS callback ABI is (card, player, alt),
        -- which Object.call cannot reproduce, and they may emit a bundle of
        -- related tokens.  Go directly to the exact one-token visual import;
        -- retain the button scanner only as an explicit legacy diagnostic.
        BridgeLog("[Bridge] exact token visual import requested name=" .. tostring(expectedName)
            .. " reason=" .. tostring(reason or "no art-bearing reusable token"))
        BridgeImportExactTokenVisual(expectedName, seatId, function(imported, importError)
            if imported ~= nil then
                finish(imported, nil)
                return
            end
            BridgeSpawnGenericTokenProxy(expectedName, seatId, function(proxy, proxyError)
                if proxy ~= nil then
                    BridgeLog("[Bridge] DEGRADED token presentation: exact art importer failed name="
                        .. tostring(expectedName) .. " importError=" .. tostring(importError))
                    finish(proxy, nil)
                    return
                end
                finish(nil, "exact token visual import failed: " .. tostring(importError)
                    .. "; generic proxy failed: " .. tostring(proxyError))
            end)
        end)
    end

    local deck, entry = BridgeFindDeckWithContainedCardName(expectedName, excludeDeckGuidSet)
    if deck == nil or entry == nil then
        fallbackVisualImport("no matching reusable token in table containers")
        return
    end

    local seat = BRIDGE_SEATS[seatId]
    local anchor = seat and (seat.commandAnchor or (seat.battlefieldAnchors and seat.battlefieldAnchors.creature)) or nil
    local position = anchor and {anchor.x, (anchor.y or 2.0) + 1.5, anchor.z} or {0, 3.0, 0}
    local options = {
        position = position,
        smooth = false,
        callback_function = function(taken)
            if not BridgeObjectIsUsable(taken) then
                finish(nil, "token fetcher returned an unusable card")
                return
            end
            if BridgeIsArtBearingCard(taken) then
                BridgeMarkTokenPhysicalObject(taken)
                finish(taken, nil)
                return
            end
            -- Do not leave the unusable blank fetch result beside the exact
            -- imported token; one Forge identity must yield one physical card.
            pcall(function() taken.destruct() end)
            fallbackVisualImport("reusable token container returned a blank card")
        end
    }
    if deck.tag == "Deck" then
        options.index = entry.index
    elseif deck.tag == "Bag" then
        options.guid = entry.guid
    else
        finish(nil, "unsupported token container tag " .. tostring(deck.tag))
        return
    end
    deck.takeObject(options)
end

function BridgeSetPhysicalFaceDown(object, seat, faceDown)
    if not BridgeObjectIsUsable(object) then return end
    local faceUp = seat.faceUpRotation
    if faceUp == nil then return end
    local guid = BridgeSafeObjectGuid(object)
    if guid == nil then return end
    local baseRotation = {
        x = faceUp.x,
        y = faceUp.y,
        z = faceUp.z + (faceDown and 180 or 0)
    }
    local rotation = {
        x = baseRotation.x,
        y = baseRotation.y + (BridgeState.physicalTappedByGuid[guid] == true and 90 or 0),
        z = baseRotation.z
    }
    if not BridgeSafeObjectCall(object, function(o) o.setRotation(rotation) end) then return end
    BridgeState.untappedRotationByGuid[guid] = baseRotation
end

function BridgeSetPhysicalTapped(object, tapped)
    local guid = BridgeSafeObjectGuid(object)
    if guid == nil then return end
    BridgeState.physicalTappedByGuid[guid] = tapped == true
    local base = BridgeState.untappedRotationByGuid[guid]
    if base == nil then
        local ok, rotation = pcall(function() return object.getRotation() end)
        if not ok or rotation == nil then return end
        base = rotation
        BridgeState.untappedRotationByGuid[guid] = base
    end
    local targetY = base.y + (tapped and 90 or 0)
    BridgeSafeObjectCall(object, function(o) o.setRotationSmooth({base.x, targetY, base.z}, false, true) end)
end

function BridgeResolveMappedInstance(event)
    if event.cardInstanceId == nil then
        return nil, "authoritative card-state event has no cardInstanceId"
    end
    local guid = BridgeState.physicalByInstanceId[event.cardInstanceId]
    if guid == nil then
        return nil, "no physical GUID mapped for card instance " .. tostring(event.cardInstanceId)
    end
    local object = getObjectFromGUID(guid)
    if object == nil then
        return nil, "mapped physical object vanished for card instance " .. tostring(event.cardInstanceId)
    end
    return object, nil
end

-- Table-native presentation adapter.  Forge supplies the resulting state; this
-- code only drives the already-installed Encoder modules to display it.
local BRIDGE_UNIFIED_PROPERTY = "_MTG_Simplified_UNIFIED"
local BRIDGE_KEYWORDS_PROPERTY = "πKeywords"
local BRIDGE_PHASE_PROPERTY = "MTG_Phase"
local BRIDGE_COUNTER_FALLBACK_PROPERTY = "ForgeBotState"

function BridgeEnsureTableEncoded(object)
    if not BridgeObjectIsUsable(object) then return nil, "card object is unavailable" end
    local encoder = Global.getVar("Encoder")
    if encoder == nil then return nil, "Easy Modules Encoder is unavailable" end

    local guid = BridgeSafeObjectGuid(object)
    local beforeName = BridgeSafeObjectName(object)
    local beforeDescription = object.getDescription()
    local beforeData = object.getData() or {}
    local beforeNickname = beforeData.Nickname or beforeData.nickname

    local ok, encodedOrError = pcall(function()
        return encoder.call("APIobjectExists", {obj = object})
    end)
    if not ok then return nil, "could not inspect Encoder state: " .. tostring(encodedOrError) end
    if encodedOrError ~= true then
        local encoded, encodeError = BridgeEncoderMutation(object, function()
            encoder.call("APIencodeObject", {obj = object})
        end, "APIencodeObject")
        if not encoded then return nil, "could not encode card: " .. tostring(encodeError) end
    end
    if guid ~= nil and BridgeState.encoderIdentityLoggedGuids[guid] ~= true then
        local afterData = object.getData() or {}
        BridgeState.encoderIdentityLoggedGuids[guid] = true
        BridgeLog(string.format(
            "[Bridge] table-encoding identity guid=%s beforeName=%s afterName=%s beforeDescription=%s afterDescription=%s beforeDataNickname=%s afterDataNickname=%s canonical=%s encoderMetadata=%s",
            tostring(guid), tostring(beforeName), tostring(BridgeSafeObjectName(object)),
            tostring(beforeDescription), tostring(object.getDescription()), tostring(beforeNickname),
            tostring(afterData.Nickname or afterData.nickname), tostring(BridgePhysicalCanonicalCardName(object)),
            encodedOrError == true and "existing" or "encoded"))
    end
    return encoder, nil
end

function BridgeEnsureEncoderProperty(object, propertyId)
    local encoder, encoderError = BridgeEnsureTableEncoded(object)
    if encoder == nil then return nil, encoderError end
    local ok, enabledOrError = pcall(function()
        return encoder.call("APIobjIsPropEnabled", {obj = object, propID = propertyId})
    end)
    if not ok then return nil, "could not inspect Encoder property " .. tostring(propertyId) .. ": " .. tostring(enabledOrError) end
    if enabledOrError ~= true then
        local enabled, enableError = BridgeEncoderMutation(object, function()
            encoder.call("APIobjEnableProp", {obj = object, propID = propertyId})
        end, "APIobjEnableProp")
        if not enabled then return nil, "could not enable Encoder property " .. tostring(propertyId) .. ": " .. tostring(enableError) end
    end
    return encoder, nil
end

local function BridgeCardScaleSnapshot(object)
    local ok, scale = pcall(function() return object.getScale() end)
    if not ok or scale == nil then return nil end
    return {x = scale.x, y = scale.y, z = scale.z}
end

-- The first live game-card scale is its canonical embodiment scale. Zones,
-- token imports, Encoder/state rebuilds, and characteristic changes may alter
-- presentation but must never silently resize that physical card.
function BridgeCaptureCanonicalCardScale(object)
    if object == nil or object.tag ~= "Card" then return nil end
    local guid = BridgeSafeObjectGuid(object)
    if guid == nil then return nil end
    local canonical = BridgeState.canonicalCardScaleByGuid[guid]
    if canonical == nil then
        canonical = BridgeCardScaleSnapshot(object)
        if canonical ~= nil then BridgeState.canonicalCardScaleByGuid[guid] = canonical end
    end
    return canonical
end

function BridgeRestoreCanonicalCardScale(object)
    local guid = BridgeSafeObjectGuid(object)
    local canonical = guid and BridgeState.canonicalCardScaleByGuid[guid] or nil
    if canonical == nil then canonical = BridgeCaptureCanonicalCardScale(object) end
    if canonical ~= nil then BridgeRestoreCardScaleIfChanged(object, canonical) end
end

function BridgeRestoreCardScaleIfChanged(object, beforeScale)
    if beforeScale == nil then return end
    local afterScale = BridgeCardScaleSnapshot(object)
    if afterScale == nil then return end
    if math.abs(afterScale.x - beforeScale.x) > 0.001
        or math.abs(afterScale.y - beforeScale.y) > 0.001
        or math.abs(afterScale.z - beforeScale.z) > 0.001 then
        -- Encoder presentation must never resize a physical game card. Apart
        -- from looking wrong, a changed scale desynchronizes the local keyword
        -- decal geometry from the card it annotates.
        object.setScale(beforeScale)
        BridgeLog("[Bridge] restored card scale after Encoder rebuild guid=" .. tostring(BridgeSafeObjectGuid(object)))
    end
end

-- All Encoder mutations on real game cards cross this boundary.  The first
-- call captures the canonical scale before Encoder can alter the transform;
-- the immediate and deferred restores cover both synchronous and delayed TTS
-- rebuild work.  Presentation-only helper objects are intentionally exempt.
function BridgeEncoderMutation(object, operation, label)
    if object == nil or object.tag ~= "Card" then
        return pcall(operation)
    end
    local canonical = BridgeCaptureCanonicalCardScale(object)
    local ok, result = pcall(operation)
    if canonical ~= nil then
        BridgeRestoreCardScaleIfChanged(object, canonical)
        BridgeWaitFrames(function()
            if BridgeObjectIsUsable(object) then
                BridgeRestoreCardScaleIfChanged(object, canonical)
            end
        end, 2)
    end
    if not ok then return false, result end
    BridgeLog("[Bridge] Encoder mutation scale-safe operation=" .. tostring(label or "unknown")
        .. " guid=" .. tostring(BridgeSafeObjectGuid(object)))
    return true, result
end

function BridgeMutateUnifiedState(object, mutate)
    local encoder, encoderError = BridgeEnsureEncoderProperty(object, BRIDGE_UNIFIED_PROPERTY)
    if encoder == nil then return false, encoderError end
    local ok, applyError = pcall(function()
        local encoded = encoder.call("APIobjGetPropData", {obj = object, propID = BRIDGE_UNIFIED_PROPERTY})
        if encoded == nil or encoded.tyrantUnified == nil then error("card lacks Easy Modules Unified metadata") end
        mutate(encoded.tyrantUnified)
        local mutated, mutationError = BridgeEncoderMutation(object, function()
            encoder.call("APIobjSetPropData", {obj = object, propID = BRIDGE_UNIFIED_PROPERTY, data = encoded})
            BridgePresentationMetric("unifiedPropWriteCount")
            -- Rebuild through Encoder: direct card buttons do not survive this call.
            encoder.call("APIrebuildButtons", {obj = object})
            BridgePresentationMetric("encoderRebuildCount")
        end, "APIobjSetPropData+APIrebuildButtons")
        if not mutated then error(mutationError) end
    end)
    if not ok then return false, tostring(applyError) end
    return true, nil
end

function BridgeSetUnifiedState(object, patch)
    if type(patch) ~= "table" then return false, "Unified patch must be a table" end
    return BridgeMutateUnifiedState(object, function(unified)
        for field, value in pairs(patch) do
            unified[field] = value
        end
    end)
end

local function BridgeUnifiedPrintedFace(unified)
    local faces = unified and unified.cardFaces or nil
    if type(faces) ~= "table" then return nil end
    local activeFace = unified.activeFace
    local face = activeFace ~= nil and faces[activeFace] or nil
    -- Easy Modules alternate layouts do not consistently populate activeFace.
    -- The imported front is still the correct printed base unless Forge later
    -- supplies a verified face change.
    if face == nil then face = faces[1] or faces[0] or faces.front end
    if face == nil then
        for _, candidate in pairs(faces) do
            if type(candidate) == "table" then face = candidate; break end
        end
    end
    return face
end

local function BridgeApplyDerivedStatsToUnified(unified, power, toughness)
    if power == nil and toughness == nil then
        -- Clear stale imported P/T values as well as hiding the display. A
        -- land that previously held a creature must never retain its old
        -- derived characteristics in Unified.
        unified.power = 0
        unified.toughness = 0
        unified.displayPowTou = false
        return
    end
    local cardFace = BridgeUnifiedPrintedFace(unified)
    local basePower = cardFace and tonumber(cardFace.basePower) or nil
    local baseToughness = cardFace and tonumber(cardFace.baseToughness) or nil
    if power ~= nil then unified.power = basePower and (tonumber(power) - basePower) or tonumber(power) end
    if toughness ~= nil then unified.toughness = baseToughness and (tonumber(toughness) - baseToughness) or tonumber(toughness) end
    unified.displayPowTou = true
end

function BridgeSetDerivedStats(object, power, toughness)
    local guid = BridgeSafeObjectGuid(object)
    local previous = guid and BridgeState.presentedStatsByGuid[guid] or nil
    if previous ~= nil and previous.power == power and previous.toughness == toughness then return true, nil end
    return BridgeMutateUnifiedState(object, function(unified)
        BridgeApplyDerivedStatsToUnified(unified, power, toughness)
        if guid ~= nil then BridgeState.presentedStatsByGuid[guid] = {power = power, toughness = toughness} end
    end)
end

local function BridgeApplyOwnerControllerToUnified(unified, ownerSeatId, controllerSeatId)
    local ownerSeat = BRIDGE_SEATS[ownerSeatId]
    local controllerSeat = BRIDGE_SEATS[controllerSeatId]
    if ownerSeat ~= nil then unified.ownerColor = ownerSeat.ttsColor end
    if controllerSeat ~= nil then unified.controllerColor = controllerSeat.ttsColor end
    unified.displayOwnership = ownerSeat ~= nil or controllerSeat ~= nil
end

function BridgeSetOwnerController(object, ownerSeatId, controllerSeatId)
    local guid = BridgeSafeObjectGuid(object)
    local signature = tostring(ownerSeatId or "") .. "|" .. tostring(controllerSeatId or "")
    if guid ~= nil and BridgeState.presentedOwnerControllerByGuid[guid] == signature then return true, nil end
    return BridgeMutateUnifiedState(object, function(unified)
        BridgeApplyOwnerControllerToUnified(unified, ownerSeatId, controllerSeatId)
        if guid ~= nil then BridgeState.presentedOwnerControllerByGuid[guid] = signature end
    end)
end

function BridgeSetPhasedState(object, phased)
    -- On this table the Phasing property has visible behavior merely by being
    -- enabled.  It must not be activated as a generic false-state container.
    local encoder, encoderError = BridgeEnsureTableEncoded(object)
    if encoder == nil then return false, encoderError end
    local guid = BridgeSafeObjectGuid(object)
    if guid ~= nil and BridgeState.presentedPhasedByGuid[guid] == (phased == true) then return true, nil end
    local ok, applyError = pcall(function()
        local mutated, mutationError = BridgeEncoderMutation(object, function()
            local enabled = encoder.call("APIobjIsPropEnabled", {obj = object, propID = BRIDGE_PHASE_PROPERTY})
            if phased == true then
                if enabled ~= true then
                    encoder.call("APIobjEnableProp", {obj = object, propID = BRIDGE_PHASE_PROPERTY})
                end
                local data = encoder.call("APIobjGetPropData", {obj = object, propID = BRIDGE_PHASE_PROPERTY})
                if data == nil then error("card lacks Phasing metadata") end
                data.mtg_phased = true
                encoder.call("APIobjSetPropData", {obj = object, propID = BRIDGE_PHASE_PROPERTY, data = data})
            elseif enabled == true then
                -- Clear stale module data before hiding the property so a later,
                -- genuine phasing event cannot resurrect an old visual state.
                local data = encoder.call("APIobjGetPropData", {obj = object, propID = BRIDGE_PHASE_PROPERTY})
                if data ~= nil then
                    data.mtg_phased = false
                    encoder.call("APIobjSetPropData", {obj = object, propID = BRIDGE_PHASE_PROPERTY, data = data})
                end
                encoder.call("APIobjDisableProp", {obj = object, propID = BRIDGE_PHASE_PROPERTY})
            end
            encoder.call("APIrebuildButtons", {obj = object})
            BridgePresentationMetric("encoderRebuildCount")
        end, "phase-property+APIrebuildButtons")
        if not mutated then error(mutationError) end
        if guid ~= nil then BridgeState.presentedPhasedByGuid[guid] = phased == true end
    end)
    if not ok then return false, tostring(applyError) end
    return true, nil
end

function BridgeSetFaceState(object, forgeState, seatId)
    if object == nil or forgeState == nil then return object end
    local guid = BridgeSafeObjectGuid(object)
    local resolvedSeatId = seatId or (guid and BridgeState.physicalSeatByGuid[guid]) or forgeState.ownerSeatId
    local seat = BRIDGE_SEATS[resolvedSeatId]
    if seat ~= nil and forgeState.faceDown ~= nil then
        -- Face-down is an explicit Forge state. Do not infer Morph/Manifest or
        -- DFC state IDs from text; a native state replacement needs a runtime
        -- verified structured face identifier before it is safe to use.
        BridgeSetPhysicalFaceDown(object, seat, forgeState.faceDown == true)
    end
    return object
end

function BridgeApplyCardPresentationSnapshot(object, cardSnapshot)
    if object == nil or cardSnapshot == nil then return false, "missing card presentation input" end
    BridgeSetFaceState(object, cardSnapshot)
    local guid = BridgeSafeObjectGuid(object)
    local stats = {power = cardSnapshot.currentPower, toughness = cardSnapshot.currentToughness}
    local types = cardSnapshot.currentTypes or {}
    if #types > 0 then
        local creature = false
        for _, cardType in ipairs(types) do
            if string.lower(tostring(cardType)) == "creature" then creature = true; break end
        end
        if not creature then stats.power, stats.toughness = nil, nil end
    end
    local ownerSignature = tostring(cardSnapshot.ownerSeatId or "") .. "|" .. tostring(cardSnapshot.controllerSeatId or "")
    local statsChanged = guid == nil
        or BridgeState.presentedStatsByGuid[guid] == nil
        or BridgeState.presentedStatsByGuid[guid].power ~= stats.power
        or BridgeState.presentedStatsByGuid[guid].toughness ~= stats.toughness
    local ownershipChanged = guid == nil or BridgeState.presentedOwnerControllerByGuid[guid] ~= ownerSignature
    if statsChanged or ownershipChanged then
        local applied, applyError = BridgeMutateUnifiedState(object, function(unified)
            if statsChanged then BridgeApplyDerivedStatsToUnified(unified, stats.power, stats.toughness) end
            if ownershipChanged then BridgeApplyOwnerControllerToUnified(unified, cardSnapshot.ownerSeatId, cardSnapshot.controllerSeatId) end
            if guid ~= nil then
                BridgeState.presentedStatsByGuid[guid] = stats
                BridgeState.presentedOwnerControllerByGuid[guid] = ownerSignature
            end
        end)
        if not applied then return false, applyError end
    end
    local phased, phaseError = BridgeSetPhasedState(object, cardSnapshot.phasedOut == true)
    if not phased then BridgeLog("[Bridge] optional phasing presentation skipped: " .. tostring(phaseError)) end
    return true, nil
end

-- Existing table integration: Easy Modules Unified is the authoritative visual
-- sink for +1/+1 and generic named counters. Values are set absolutely so event
-- replay cannot double the physical display.
function BridgeNormalizeCounterName(counterType)
    local normalized = string.lower(tostring(counterType or ""))
    normalized = string.gsub(normalized, "^%s+", "")
    normalized = string.gsub(normalized, "%s+$", "")
    return normalized
end

function BridgeCopyCounterMap(counters)
    local result = {}
    for counterType, counterValue in pairs(counters or {}) do
        local normalized = BridgeNormalizeCounterName(counterType)
        local numeric = tonumber(counterValue) or 0
        if normalized ~= "" and numeric > 0 then result[normalized] = numeric end
    end
    return result
end

function BridgeSetCardCounters(object, absoluteCounters)
    local counters = BridgeCopyCounterMap(absoluteCounters)
    local plusOne = counters["+1/+1"] or 0
    local named = {}
    for counterType, counterValue in pairs(counters) do
        if counterType ~= "+1/+1" and counterType ~= "stun" then
            table.insert(named, {counterType = counterType, counterValue = counterValue})
        end
    end
    table.sort(named, function(left, right) return left.counterType < right.counterType end)
    local signatureParts = {"+1/+1=" .. tostring(plusOne), "stun=" .. tostring(counters.stun or 0)}
    for _, entry in ipairs(named) do table.insert(signatureParts, entry.counterType .. "=" .. tostring(entry.counterValue)) end
    local signature = table.concat(signatureParts, "|")
    local guid = BridgeSafeObjectGuid(object)
    local unifiedAlreadyPresented = guid ~= nil and BridgeState.presentedCounterSignatureByGuid[guid] == signature
    if not unifiedAlreadyPresented then
        local applied, applyError = BridgeMutateUnifiedState(object, function(unified)
            unified.plusOneCounters = plusOne
            unified.displayPlusOne = plusOne ~= 0
            -- Unified has one generic named counter display. Never combine
            -- different Forge counter types into an invented total.
            if #named == 1 then
                unified.namedCounters = named[1].counterValue
                unified.displayCounters = named[1].counterValue ~= 0
            else
                unified.namedCounters = 0
                unified.displayCounters = false
            end
            if guid ~= nil then BridgeState.presentedCounterSignatureByGuid[guid] = signature end
        end)
        if not applied then return false, applyError end

        local stunApplied, stunError = BridgeSetCardKeywordState(object, "stun", (counters.stun or 0) > 0)
        if not stunApplied then
            BridgeLog("[Bridge] optional stun presentation skipped: " .. tostring(stunError))
        end
    end

    local fallbackSignature = table.concat(signatureParts, "|")
    local fallbackAlreadyPresented = guid ~= nil
        and BridgeState.presentedCounterFallbackSignatureByGuid[guid] == fallbackSignature
    if not fallbackAlreadyPresented then
        local fallbackApplied, fallbackError = BridgeSetForgeBotCounterFallback(object, named)
        if fallbackApplied then
            if guid ~= nil then BridgeState.presentedCounterFallbackSignatureByGuid[guid] = fallbackSignature end
        else
            -- Do not cache failure. Encoder can become available after the
            -- first snapshot; an unchanged authoritative lore/level counter
            -- must be retried on a later reconciliation.
            BridgeLog("[Bridge] optional counter fallback skipped: " .. tostring(fallbackError))
        end
    end
    return true, nil
end

function BridgeSetCardCounterState(object, counterType, counterValue)
    if counterValue == nil or counterValue < 0 then
        return false, "invalid authoritative counter value " .. tostring(counterValue)
    end
    local field = nil
    if counterType == "+1/+1" then field = "plusOneCounters" end
    if counterType == "named" then field = "namedCounters" end
    if field == nil then
        return false, "unsupported existing-table counter type " .. tostring(counterType)
    end

    local ok, applyError = BridgeMutateUnifiedState(object, function(unified)
        unified[field] = counterValue
        if field == "plusOneCounters" then unified.displayPlusOne = counterValue ~= 0 end
        if field == "namedCounters" then unified.displayCounters = counterValue ~= 0 end
    end)
    return ok, applyError
end

local BRIDGE_KEYWORD_PROPERTIES = {
    flying = "mtg_flyingcounter", haste = "mtg_hastecounter",
    deathtouch = "mtg_deathtouchcounter", defender = "mtg_defendercounter",
    ["double strike"] = "mtg_doublestrikecounter", ["first strike"] = "mtg_firststrikecounter",
    hexproof = "mtg_hexproofcounter", indestructible = "mtg_indestructiblecounter",
    lifelink = "mtg_lifelinkcounter", menace = "mtg_menacecounter",
    reach = "mtg_reachcounter", trample = "mtg_tramplecounter",
    vigilance = "mtg_vigilancecounter", stun = "mtg_stuncounter"
}

-- πKeywords only creates decals when its own UI toggle marks a global redraw.
-- Forge updates property data directly, so mirror the module's visible decal
-- output for both `art` and alternate `above` layouts without changing rules.
local BRIDGE_KEYWORD_DECALS = {
    flying = {name="Flying", url="http://cloud-3.steamusercontent.com/ugc/1647720820459775349/912974BD1EAE7E35274F2228F0275C08473F73C2/"},
    haste = {name="Haste", url="http://cloud-3.steamusercontent.com/ugc/1647720820459776460/2384D15814E736DCED6F3D755E9C7750DE844CF1/"},
    deathtouch = {name="Deathtouch", url="http://cloud-3.steamusercontent.com/ugc/1647720820459770551/8ED7C2CF930BB048D5D0F281CEE139681D9FC132/"},
    defender = {name="Defender", url="http://cloud-3.steamusercontent.com/ugc/1647720820459771131/766BD64F624C102D6B7824B3D2065DEF1F15BD65/"},
    ["double strike"] = {name="Double Strike", url="http://cloud-3.steamusercontent.com/ugc/1647720820459771597/06334C3958CF7B3C50A76A4F2F22ACD6389D2169/"},
    ["first strike"] = {name="First Strike", url="http://cloud-3.steamusercontent.com/ugc/1647720820459774469/9FB16BFF1B02B2455C3D844127EC39A141534F33/"},
    hexproof = {name="Hexproof", url="http://cloud-3.steamusercontent.com/ugc/1647720820459777186/41A7105B5FBBFE116EBFD950C5809724CCD508B1/"},
    indestructible = {name="Indestructible", url="http://cloud-3.steamusercontent.com/ugc/1647721275620396729/06E0D42899D763E8C179326CB8A904543C1F25DA/"},
    lifelink = {name="Lifelink", url="https://steamusercontent-a.akamaihd.net/ugc/1647720820459778541/EC0A9AE3F2A92ED0070E0050A3AB451046D79A35/"},
    menace = {name="Menace", url="http://cloud-3.steamusercontent.com/ugc/1647720820459779239/1C65FC6264E001EB3DCBC88A8473B0EABE33834A/"},
    reach = {name="Reach", url="http://cloud-3.steamusercontent.com/ugc/1647720820459781368/2390550F830E8BF214F9FF9CD971976A35C95230/"},
    trample = {name="Trample", url="http://cloud-3.steamusercontent.com/ugc/1647720820459785398/41B89DCAC842C5C2624AC5EFA9428492C2841515/"},
    vigilance = {name="Vigilance", url="http://cloud-3.steamusercontent.com/ugc/1647720820459786000/AF931371F2426EF81E336C0BD668EA983AE843D9/"}
}

function BridgeRenderKeywordDecals(object, enabled, encoder)
    local active = {}
    for keyword, isEnabled in pairs(enabled or {}) do if isEnabled and BRIDGE_KEYWORD_DECALS[keyword] ~= nil then table.insert(active, keyword) end end
    table.sort(active)
    local removable = {}
    for _, definition in pairs(BRIDGE_KEYWORD_DECALS) do removable[definition.name] = true end
    local decals = object.getDecals() or {}
    local retained = {}
    for _, decal in ipairs(decals) do if not removable[decal.name] then table.insert(retained, decal) end end
    local layout = "art"
    local ok, layoutData = pcall(function() return encoder.call("APIobjGetValueData", {obj = object, valueID = "iconLayout"}) end)
    if ok and layoutData ~= nil and layoutData.iconLayout ~= nil then layout = layoutData.iconLayout end
    local flip = 1
    local flipOk, flipValue = pcall(function() return encoder.call("APIgetFlip", {obj = object}) end)
    if flipOk and tonumber(flipValue) ~= nil then flip = tonumber(flipValue) end
    for index, keyword in ipairs(active) do
        local position = nil
        local scale = nil
        if layout == "above" then
            local column = (index - 1) % 5
            local row = math.floor((index - 1) / 5)
            position = {(-1) * (1 - 1 / 5 - column * (2 / 5)) * flip, 0.3 * flip, -1.55 - 1 / 5 - row * 2 / 5}
            scale = {0.8, 0.8, 0.8}
        else
            position = {0, 0.3 * flip, -0.5 + (index - 1) * 0.45}
            scale = {0.55, 0.55, 0.55}
        end
        local definition = BRIDGE_KEYWORD_DECALS[keyword]
        table.insert(retained, {name = definition.name, url = definition.url, position = position, rotation = {180 - flip * 90, 90 + flip * 90, 0}, scale = scale})
    end
    object.setDecals(retained)
    BridgePresentationMetric("decalWriteCount")
end

function BridgeEnsureKeywordIconLayout(object, encoder)
    local guid = BridgeSafeObjectGuid(object)
    if guid ~= nil and BridgeState.presentedIconLayoutByGuid[guid] == "above" then return true, nil, false end
    local ok, valueData = pcall(function()
        return encoder.call("APIobjGetValueData", {obj = object, valueID = "iconLayout"})
    end)
    if not ok then return false, "could not inspect icon layout", false end
    if valueData ~= nil and valueData.iconLayout == "above" then
        if guid ~= nil then BridgeState.presentedIconLayoutByGuid[guid] = "above" end
        return true, nil, false
    end
    local applied, applyError = BridgeEncoderMutation(object, function()
        encoder.call("APIobjSetValueData", {obj = object, valueID = "iconLayout", data = {iconLayout = "above"}})
    end, "APIobjSetValueData")
    if not applied then return false, tostring(applyError), false end
    if guid ~= nil then BridgeState.presentedIconLayoutByGuid[guid] = "above" end
    return true, nil, true
end

function BridgeNormalizeKeywordName(keyword)
    local normalized = string.lower(tostring(keyword or ""))
    normalized = string.gsub(normalized, "^%s+", "")
    normalized = string.gsub(normalized, "%s+$", "")
    normalized = string.gsub(normalized, "%s+", " ")
    local reminderStart = string.find(normalized, " (", 1, true)
    if reminderStart ~= nil then
        normalized = string.sub(normalized, 1, reminderStart - 1)
        normalized = string.gsub(normalized, "%s+$", "")
    end
    normalized = string.gsub(normalized, "%.$", "")
    return normalized
end

function BridgeSetCardKeywordState(object, keyword, enabled)
    local normalized = BridgeNormalizeKeywordName(keyword)
    local property = BRIDGE_KEYWORD_PROPERTIES[normalized]
    if property == nil then return false, "unsupported existing-table keyword " .. tostring(keyword) end

    local encoder, encoderError = BridgeEnsureEncoderProperty(object, BRIDGE_KEYWORDS_PROPERTY)
    if encoder == nil then return false, encoderError end
    local layoutOk, layoutError = BridgeEnsureKeywordIconLayout(object, encoder)
    if not layoutOk then return false, layoutError end
    local ok, applyError = pcall(function()
        local data = encoder.call("APIobjGetPropData", {obj = object, propID = BRIDGE_KEYWORDS_PROPERTY})
        if data == nil then error("card is not encoded with πKeywords") end
        data[property] = enabled and 1 or 0
        data.activeIcons = data.activeIcons or {}
        local found = nil
        for index, value in ipairs(data.activeIcons) do
            if value == property then found = index; break end
        end
        if enabled and found == nil then table.insert(data.activeIcons, property) end
        if not enabled and found ~= nil then table.remove(data.activeIcons, found) end
        local mutated, mutationError = BridgeEncoderMutation(object, function()
            encoder.call("APIobjSetPropData", {obj = object, propID = BRIDGE_KEYWORDS_PROPERTY, data = data})
            BridgePresentationMetric("keywordPropWriteCount")
            encoder.call("APIrebuildButtons", {obj = object})
            BridgePresentationMetric("encoderRebuildCount")
        end, "keyword-state+APIrebuildButtons")
        if not mutated then error(mutationError) end
        BridgeRenderKeywordDecals(object, enabled, encoder)
    end)
    if not ok then return false, tostring(applyError) end
    return true, nil
end

function BridgeSetCardKeywords(object, absoluteKeywords)
    local enabled = {}
    local unsupported = {}
    for _, keyword in ipairs(absoluteKeywords or {}) do
        local normalized = BridgeNormalizeKeywordName(keyword)
        if BRIDGE_KEYWORD_PROPERTIES[normalized] ~= nil then
            enabled[normalized] = true
        elseif normalized ~= "" then
            table.insert(unsupported, normalized)
        end
    end
    local supported = {}
    for keyword, isEnabled in pairs(enabled) do if isEnabled then table.insert(supported, keyword) end end
    table.sort(supported)
    table.sort(unsupported)
    local guid = BridgeSafeObjectGuid(object)
    local signature = table.concat(supported, "|")
    local encoder, encoderError = BridgeEnsureEncoderProperty(object, BRIDGE_KEYWORDS_PROPERTY)
    if encoder == nil then return false, encoderError end
    local layoutOk, layoutError, layoutChanged = BridgeEnsureKeywordIconLayout(object, encoder)
    if not layoutOk then return false, layoutError end
    if guid ~= nil and BridgeState.presentedKeywordSignatureByGuid[guid] == signature then
        if layoutChanged then
            local rebuilt, rebuildError = BridgeEncoderMutation(object, function()
                encoder.call("APIrebuildButtons", {obj = object})
                BridgePresentationMetric("encoderRebuildCount")
            end, "keyword-layout+APIrebuildButtons")
            if not rebuilt then return false, rebuildError end
        end
        return true, nil
    end
    for _, keyword in ipairs(unsupported) do
        local logKey = tostring(guid or "unknown") .. "|" .. keyword
        if BridgeState.unsupportedKeywordLogged[logKey] ~= true then
            BridgeState.unsupportedKeywordLogged[logKey] = true
            BridgeLog("[Bridge] presentation capability gap: unsupported native keyword icon " .. tostring(keyword))
        end
    end
    local ok, applyError = pcall(function()
        local data = encoder.call("APIobjGetPropData", {obj = object, propID = BRIDGE_KEYWORDS_PROPERTY})
        if data == nil then error("card lacks πKeywords metadata") end
        data.activeIcons = {}
        for keyword, property in pairs(BRIDGE_KEYWORD_PROPERTIES) do
            local isEnabled = enabled[keyword] == true
            data[property] = isEnabled and 1 or 0
            if isEnabled then table.insert(data.activeIcons, property) end
        end
        local mutated, mutationError = BridgeEncoderMutation(object, function()
            encoder.call("APIobjSetPropData", {obj = object, propID = BRIDGE_KEYWORDS_PROPERTY, data = data})
            BridgePresentationMetric("keywordPropWriteCount")
            encoder.call("APIrebuildButtons", {obj = object})
            BridgePresentationMetric("encoderRebuildCount")
        end, "keywords+APIrebuildButtons")
        if not mutated then error(mutationError) end
        BridgeRenderKeywordDecals(object, enabled, encoder)
        if guid ~= nil then BridgeState.presentedKeywordSignatureByGuid[guid] = signature end
    end)
    if not ok then return false, tostring(applyError) end
    return true, nil
end

-- This hidden Encoder property is only enabled when Unified's single generic
-- counter display cannot faithfully show the complete Forge counter map.
function BridgeEnsureForgeBotCounterFallbackProperty()
    local encoder = Global.getVar("Encoder")
    if encoder == nil then return nil, "Easy Modules Encoder is unavailable" end
    local ok, existsOrError = pcall(function()
        return encoder.call("APIpropertyExists", {propID = BRIDGE_COUNTER_FALLBACK_PROPERTY})
    end)
    if not ok then return nil, "could not inspect ForgeBot counter property: " .. tostring(existsOrError) end
    if existsOrError ~= true then
        local registered, registerError = pcall(function()
            encoder.call("APIregisterProperty", {
                propID = BRIDGE_COUNTER_FALLBACK_PROPERTY,
                name = "ForgeBot Counters",
                values = {},
                funcOwner = Global,
                activateFunc = "",
                visible = false
            })
        end)
        if not registered then return nil, "could not register ForgeBot counter property: " .. tostring(registerError) end
    end
    return encoder, nil
end

function BridgeSetForgeBotCounterFallback(object, namedCounters)
    local encoder, encoderError = BridgeEnsureForgeBotCounterFallbackProperty()
    if encoder == nil then return false, encoderError end
    -- Encoder's generic counter presentation is not reliably visible for a
    -- single named counter, such as lore on a Saga or level on a Class.
    local needsFallback = #(namedCounters or {}) > 0
    local ok, applyError = pcall(function()
        local encoded = encoder.call("APIobjectExists", {obj = object})
        if encoded ~= true then error("card is not Encoder-managed") end
        local mutated, mutationError = BridgeEncoderMutation(object, function()
            local enabled = encoder.call("APIobjIsPropEnabled", {obj = object, propID = BRIDGE_COUNTER_FALLBACK_PROPERTY})
            if needsFallback and enabled ~= true then
                encoder.call("APIobjEnableProp", {obj = object, propID = BRIDGE_COUNTER_FALLBACK_PROPERTY})
            elseif not needsFallback and enabled == true then
                encoder.call("APIobjDisableProp", {obj = object, propID = BRIDGE_COUNTER_FALLBACK_PROPERTY})
            end
            encoder.call("APIrebuildButtons", {obj = object})
            BridgePresentationMetric("encoderRebuildCount")
        end, "counter-fallback+APIrebuildButtons")
        if not mutated then error(mutationError) end
    end)
    if not ok then return false, tostring(applyError) end
    return true, nil
end

function BridgeIgnoreCardPresentationClick()
end

-- Encoder invokes createButtons on the property owner during every rebuild.
-- This is deliberately a property-owned button, never a persistent direct card
-- button that would be erased by APIrebuildButtons.
function createButtons(t)
    local object = t and t.obj or nil
    local guid = BridgeSafeObjectGuid(object)
    local instanceId = guid and BridgeState.physicalInstanceIdByGuid[guid] or nil
    local counters = instanceId and BridgeState.counterStateByInstanceId[instanceId] or nil
    if counters == nil then return end
    local labels = {}
    for counterType, counterValue in pairs(counters) do
        if counterType ~= "+1/+1" and counterType ~= "stun" and tonumber(counterValue or 0) > 0 then
            table.insert(labels, tostring(counterType) .. " " .. tostring(counterValue))
        end
    end
    table.sort(labels)
    if #labels == 0 then return end
    BridgeSafeObjectCall(object, function(card)
        card.createButton({
            click_function = "BridgeIgnoreCardPresentationClick",
            function_owner = Global,
            label = table.concat(labels, "\n"),
            position = {0.82, 0.29, -1.05},
            rotation = {0, 0, 0},
            width = 0,
            height = 0,
            font_size = 105,
            color = {0, 0, 0, 0},
            font_color = {1, 0.9, 0.35, 1},
            tooltip = "Forge-authoritative counters"
        })
    end)
end

function BridgeResolvePhysicalCard(event, expectedZone, options)
    options = options or {}
    if not options.skipMappedLookup and event.cardInstanceId ~= nil then
        local existingGuid = BridgeState.physicalByInstanceId[event.cardInstanceId]
        if existingGuid ~= nil then
            local existing = getObjectFromGUID(existingGuid)
            if existing == nil then
                -- TTS Card GUIDs can disappear when cards become deck-contained.
                BridgeState.physicalByInstanceId[event.cardInstanceId] = nil
                BridgeState.physicalSeatByGuid[existingGuid] = nil
                BridgeState.physicalZoneByGuid[existingGuid] = nil
                BridgeAdvancePhysicalPresentationGeneration("missing-card-mapping")
            else
                if existing.tag == "Card" then
                    local mappedZone = BridgeState.physicalZoneByGuid[existingGuid]
                    if expectedZone == "hand" and mappedZone ~= "hand" then
                        -- A land-play event can race the physical hand-zone
                        -- bookkeeping. The exact Forge-instance mapping is
                        -- still authoritative, but only trust it here when
                        -- TTS confirms that this same GUID is actually in the
                        -- configured seat hand.
                        local handObjects = BridgeTryGetSeatHandObjects(event.seatId)
                        for _, handObject in ipairs(handObjects or {}) do
                            if BridgeSafeObjectGuid(handObject) == existingGuid then
                                BridgeRecordLooseCardIdentity(event.cardInstanceId, existingGuid, event.seatId, "hand")
                                BridgeLog(string.format(
                                    "[Bridge] repaired stale hand mapping event=%s instance=%s guid=%s previousZone=%s",
                                    tostring(event.sequence), tostring(event.cardInstanceId), tostring(existingGuid), tostring(mappedZone)))
                                return existing, nil
                            end
                        end
                    end
                    if options.allowMappedZoneMismatch == true or expectedZone == nil or mappedZone == nil or mappedZone == expectedZone then
                        return existing, nil
                    end
                end
                if expectedZone == "library" and existing.tag == "Deck" then
                    return existing, nil
                end
                if existing.tag ~= "Card" and not (expectedZone == "library" and existing.tag == "Deck") then
                    -- A stale mapping can temporarily point at a deck object while the
                    -- authoritative card instance has moved into a public zone.
                    BridgeState.physicalByInstanceId[event.cardInstanceId] = nil
                    BridgeAdvancePhysicalPresentationGeneration("stale-object-mapping")
                end
            end
        end
    end

    local seat = BRIDGE_SEATS[event.seatId]
    if seat == nil then
        return nil, BridgePhysicalMappingError(event, expectedZone, 0, "seat is not configured")
    end

    local source = {}
    if expectedZone == "hand" then
        local handObjects, handError = BridgeTryGetSeatHandObjects(event.seatId)
        if handObjects == nil then
            return nil, BridgePhysicalMappingError(event, expectedZone, 0, handError)
        end
        source = handObjects
    elseif expectedZone == "library" then
        local deck = nil
        if event.cardName ~= nil and event.cardName ~= "" then
            deck = BridgeFindSeatLibraryDeckWithCard(seat, event.cardName)
        end
        if deck == nil then deck = BridgeFindLibraryDeckForSeat(event.seatId) end
        if deck ~= nil then
            return deck, nil
        end
        return nil, BridgePhysicalMappingError(event, expectedZone, 0, "library deck not found or empty")
    else
        for _, object in ipairs(getAllObjects()) do
            if object.tag == "Card"
                and IsGameCardCandidate(object, event.seatId, nil)
                and BridgeState.physicalSeatByGuid[object.getGUID()] == event.seatId
                and BridgeState.physicalZoneByGuid[object.getGUID()] == expectedZone then
                table.insert(source, object)
            end
        end
    end

    local matches = {}
    for _, sourceObject in ipairs(source) do
        if sourceObject.tag == "Card" then
            if event.cardName == nil or event.cardName == "" or BridgeCardNameMatches(sourceObject.getName(), event.cardName) then
                table.insert(matches, sourceObject)
            end
        end
    end

    if #matches == 0 and options.allowUntrackedByName == true then
        -- A semantic attack/block event can arrive before the normal snapshot
        -- has recorded the physical reverse mapping. Recover only from a
        -- unique, same-seat, same-name game card; never guess among duplicates.
        for _, candidate in ipairs(getAllObjects()) do
            if candidate.tag == "Card"
                and IsGameCardCandidate(candidate, event.seatId, nil)
                and BridgeObjectIsOnSeatSide(candidate, seat)
                and (event.cardName == nil or event.cardName == "" or BridgeCardNameMatches(candidate.getName(), event.cardName)) then
                table.insert(matches, candidate)
            end
        end
        if #matches == 1 then
            BridgeLog("[Bridge] repaired untracked attack presentation mapping instance=" .. tostring(event.cardInstanceId)
                .. " guid=" .. tostring(matches[1].getGUID()))
        end
    end

    if #matches ~= 1 then
        return nil, BridgePhysicalMappingError(event, expectedZone, #matches, "cannot uniquely identify physical card")
    end

    local object = matches[1]
    local guid = object.getGUID()
    BridgeRecordLooseCardIdentity(event.cardInstanceId, guid, event.seatId, expectedZone)
    return object, nil
end

function BridgePhysicalMappingError(event, expectedZone, candidateCount, detail, options)
    options = options or {}
    local mappedGuid = options.mappedGuid or (event.cardInstanceId and BridgeState.physicalByInstanceId[event.cardInstanceId] or nil)
    local mappedObject = BridgeGetLiveObjectByGuid(mappedGuid)
    local mappedTag = mappedObject and mappedObject.tag or "nil"
    return string.format(
        "physical mapping failed: seq=%s kind=%s seat=%s instance=%s card='%s' source=%s dest=%s expectedZone=%s mappedGuid=%s mappedTag=%s candidates=%d (%s)",
        tostring(event.sequence),
        tostring(event.kind),
        tostring(event.seatId),
        tostring(event.cardInstanceId),
        tostring(event.cardName),
        tostring(event.sourceZone),
        tostring(event.destinationZone),
        tostring(expectedZone),
        tostring(mappedGuid),
        tostring(mappedTag),
        candidateCount,
        tostring(detail))
end

function BridgeBattlefieldRowForEvent(event, defaultRow)
    if event ~= nil then
        local hasCurrentType = false
        for _, cardType in ipairs(event.currentTypes or {}) do
            local normalizedType = string.lower(tostring(cardType))
            if normalizedType ~= "" then hasCurrentType = true end
            if normalizedType == "land" then return "land" end
        end
        -- CurrentTypes is the live Forge characteristic state. Prefer it
        -- whenever present so a stale event-level BattlefieldKind cannot put
        -- a land into the permanent row (or vice versa).
        if hasCurrentType then
            return "creature"
        end
        if event.battlefieldKind == "land" or event.battlefieldKind == "creature" then
            return event.battlefieldKind
        end
        local knownRow = event.cardInstanceId ~= nil
            and BridgeState.battlefieldKindByInstanceId[event.cardInstanceId] or nil
        if knownRow == "land" or knownRow == "creature" then return knownRow end
    end
    return defaultRow == "land" and "land" or "creature"
end

function BridgeMoveToBattlefield(event, object, row, countAsNewPlacement)
    row = row == "land" and "land" or "creature"
    if event ~= nil and event.cardInstanceId ~= nil then
        BridgeState.battlefieldKindByInstanceId[event.cardInstanceId] = row
    end
    BridgeLog(string.format("[Bridge] ROW_PLACEMENT seat=%s instance=%s row=%s source=%s destination=%s",
        tostring(event and event.seatId), tostring(event and event.cardInstanceId), tostring(row),
        tostring(event and event.sourceZone), tostring(event and event.destinationZone)))
    local destination, positionError = BridgeBattlefieldPosition(event.seatId, row)
    if destination == nil then
        return false, positionError
    end

    local sourcePhysicalZone = nil
    local guidBeforeMove = BridgeSafeObjectGuid(object)
    if guidBeforeMove ~= nil then sourcePhysicalZone = BridgeState.physicalZoneByGuid[guidBeforeMove] end
    local moved, movementError = pcall(function()
        local prepared, prepareError = BridgePreparePhysicalCardForPublicZoneMove(object, "battlefield")
        if not prepared then error(prepareError) end
        BridgeCaptureCanonicalCardScale(object)
        object.use_hands = false
        BridgeSetPhysicalFaceDown(object, BRIDGE_SEATS[event.seatId], event.faceDown == true)
        object.setPosition(destination)
        BridgeRestoreCanonicalCardScale(object)
    end)
    if not moved then
        return false, "event " .. tostring(event.sequence) .. " could not move physical card: " .. tostring(movementError)
    end

    BridgeTracePermanentTransition(
        "PHYSICAL_MOVE_TO_BATTLEFIELD", event, object, sourcePhysicalZone)

    -- TTS hand/Encoder presentation can apply a scale change on the frame in
    -- which the card leaves its prior container. Restore again after that
    -- deferred work has run. Also verify the exact object did not get put back
    -- at the temporary stack anchor by a previously queued smooth movement.
    BridgeWaitFrames(function()
        if not BridgeObjectIsUsable(object) then return end
        if guidBeforeMove == nil or BridgeState.physicalZoneByGuid[guidBeforeMove] ~= "battlefield" then return end
        BridgeRestoreCanonicalCardScale(object)
        if not BridgePhysicalObjectAtStackAnchor(object) then return end
        local corrected = pcall(function() object.setPosition(destination) end)
        BridgeTracePermanentTransition(
            "PHYSICAL_MOVE_TO_BATTLEFIELD", event, object, "stack",
            corrected and "deferred stack-anchor correction" or "deferred correction failed")
        if corrected then
            BridgeRestoreCanonicalCardScale(object)
            BridgeWaitFrames(function()
                if not BridgeObjectIsUsable(object) then return end
                if BridgeState.physicalZoneByGuid[guidBeforeMove] ~= "battlefield" then return end
                if BridgePhysicalObjectAtStackAnchor(object) then
                    BridgeStopOnDesync(BridgePhysicalMappingError(
                        event, "battlefield", 1,
                        "exact battlefield card remained at the physical stack anchor",
                        {mappedGuid = guidBeforeMove}))
                end
            end, 2)
        end
    end, 2)

    local guid = object.getGUID()
    BridgeRecordLooseCardIdentity(event.cardInstanceId, guid, event.seatId, "battlefield")
    if row == "land" and event.cardInstanceId ~= nil and BridgeState.landInsertionOrderByInstanceId[event.cardInstanceId] == nil then
        BridgeState.nextLandInsertionOrder = (BridgeState.nextLandInsertionOrder or 0) + 1
        BridgeState.landInsertionOrderByInstanceId[event.cardInstanceId] = BridgeState.nextLandInsertionOrder
    end
    local rowKey = event.seatId .. ":" .. row
    if countAsNewPlacement ~= false then
        BridgeState.battlefieldCounts[rowKey] = (BridgeState.battlefieldCounts[rowKey] or 0) + 1
    end
    if row == "land" and BridgeLandPlacementMode() == "STRICT" then BridgeRelayoutStrictLandRow(event.seatId) end
    return true, nil
end

function BridgeLandPlacementMode()
    local mode = string.upper(tostring(BridgeState.landPlacementMode or BRIDGE_LAND_PLACEMENT_MODE or "FREEFORM"))
    return mode == "STRICT" and "STRICT" or "FREEFORM"
end

function BridgeSetLandPlacementMode(mode)
    local normalized = string.upper(tostring(mode or "FREEFORM"))
    if normalized ~= "STRICT" and normalized ~= "FREEFORM" then
        BridgeShowError("unknown land placement mode " .. tostring(mode))
        return false
    end
    BridgeState.landPlacementMode = normalized
    BRIDGE_LAND_PLACEMENT_MODE = normalized
    if normalized == "STRICT" then
        for seatId, _ in pairs(BRIDGE_SEATS) do BridgeRelayoutStrictLandRow(seatId) end
    end
    BridgeLog("[Bridge] land placement mode=" .. normalized)
    return true
end

function BridgeRelayoutStrictLandRow(seatId)
    if BridgeLandPlacementMode() ~= "STRICT" then return end
    local seat = BRIDGE_SEATS[seatId]
    local anchor = seat and seat.battlefieldAnchors and seat.battlefieldAnchors.land
    if anchor == nil then return end
    local lands = {}
    for instanceId, order in pairs(BridgeState.landInsertionOrderByInstanceId or {}) do
        local guid = BridgeState.physicalByInstanceId[instanceId]
        local object = guid and BridgeGetLiveObjectByGuid(guid) or nil
        if object ~= nil and BridgeState.physicalSeatByGuid[guid] == seatId
            and BridgeState.physicalZoneByGuid[guid] == "battlefield" then
            table.insert(lands, {instanceId = instanceId, order = order, object = object})
        end
    end
    table.sort(lands, function(left, right) return left.order < right.order end)
    local x = anchor.x
    for index, land in ipairs(lands) do
        local bounds = nil
        pcall(function() bounds = land.object.getBoundsNormalized() end)
        local width = bounds and bounds.size and tonumber(bounds.size.x) or 2.8
        local position = {x = x + width / 2, y = anchor.y, z = anchor.z}
        BridgeSafeObjectCall(land.object, function(card)
            BridgeCaptureCanonicalCardScale(card)
            card.setPositionSmooth(position, false, true)
            BridgeRestoreCanonicalCardScale(card)
        end)
        x = position.x + width / 2 + 0.35
    end
end

function BridgeBattlefieldPosition(seatId, row)
    local seat = BRIDGE_SEATS[seatId]
    local anchor = seat and seat.battlefieldAnchors and seat.battlefieldAnchors[row]
    if anchor == nil then
        return nil, "no battlefield anchor configured for seat " .. tostring(seatId) .. " row " .. tostring(row)
    end

    local rowKey = seatId .. ":" .. row
    local count = BridgeState.battlefieldCounts[rowKey] or 0
    for offset = 0, 11 do
        local slot = count + offset
        local candidate = {
            -- A tapped card is roughly as wide as an upright card is tall.
            -- Four wider slots preserve a grab/tap gap instead of overlapping
            -- adjacent creatures in the old six-card row.
            x = anchor.x + (slot % 4) * 3.4,
            y = anchor.y,
            z = anchor.z + math.floor(slot / 4) * seat.tableSideZ * 4.0
        }
        if not BridgeBattlefieldPositionOccupied(candidate) then
            BridgeState.battlefieldCounts[rowKey] = slot
            return candidate, nil
        end
    end
    return nil, "no unoccupied battlefield slot for seat " .. tostring(seatId) .. " row " .. tostring(row)
end

function BridgeBattlefieldPositionOccupied(candidate)
    for _, object in ipairs(getAllObjects()) do
        if object.tag == "Card" or object.tag == "Deck" then
            local position = object.getPosition()
            local dx = position.x - candidate.x
            local dz = position.z - candidate.z
            if dx * dx + dz * dz < 3.0 then return true end
        end
    end
    return false
end

function BridgeUnitTowardTableCenter(position)
    local length = math.sqrt(position.x * position.x + position.z * position.z)
    if length < 0.01 then
        return {x = 0, z = 1}
    end
    return {x = -position.x / length, z = -position.z / length}
end

function BridgeMoveToAttackLane(seatId, object)
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then return end
    local guid = object.getGUID()
    local position = object.getPosition()
    if BridgeState.attackOriginByGuid[guid] == nil then
        BridgeState.attackOriginByGuid[guid] = {x = position.x, y = position.y, z = position.z}
    end
    BridgeState.attackLaneGuidBySeatId[seatId] = BridgeState.attackLaneGuidBySeatId[seatId] or {}
    BridgeState.attackLaneGuidBySeatId[seatId][guid] = true
    -- Parallel translation preserves the battlefield's lateral X separation.
    object.setPositionSmooth({x = position.x, y = math.max(position.y, 2.0), z = seat.attackLaneZ}, false, true)
end

function BridgeCombatLaneXAvailable(laneZ, candidateX, ignoredGuid)
    for _, other in ipairs(getAllObjects()) do
        if other.tag == "Card" then
            local guid = BridgeSafeObjectGuid(other)
            if guid ~= nil and guid ~= ignoredGuid then
                local position = other.getPosition()
                local dx = position.x - candidateX
                local dz = position.z - laneZ
                if dx * dx < 2.8 * 2.8 and dz * dz < 1.0 * 1.0 then
                    return false
                end
            end
        end
    end
    return true
end

function BridgeFindCombatLaneX(object, laneZ)
    local position = object.getPosition()
    local guid = BridgeSafeObjectGuid(object)
    local candidates = {position.x}
    for distance = 3.4, 20.4, 3.4 do
        table.insert(candidates, position.x + distance)
        table.insert(candidates, position.x - distance)
    end
    for _, candidateX in ipairs(candidates) do
        if BridgeCombatLaneXAvailable(laneZ, candidateX, guid) then return candidateX end
    end
    return position.x
end

function BridgeMoveToBlockerLane(seatId, object)
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then return end
    local guid = object.getGUID()
    local position = object.getPosition()
    if BridgeState.attackOriginByGuid[guid] == nil then
        BridgeState.attackOriginByGuid[guid] = {x = position.x, y = position.y, z = position.z}
    end
    local laneX = BridgeFindCombatLaneX(object, seat.blockerLaneZ)
    object.setPositionSmooth({x = laneX, y = math.max(position.y, 2.0), z = seat.blockerLaneZ}, false, true)
end

function BridgeGraveyardPosition(seatId)
    local seat = BRIDGE_SEATS[seatId]
    local anchor = BridgeResolveSeatZoneAnchor(seatId, "graveyard")
    if anchor == nil then return nil end

    -- Visually pile the graveyard in one place, but retain each card object
    -- and its exact Forge-instance mapping rather than letting TTS merge the
    -- pile into a Deck.
    local count = BridgeState.graveyardCounts[seatId] or 0
    BridgeState.graveyardCounts[seatId] = count + 1
    return {
        x = anchor.x,
        y = anchor.y + 0.08 + count * 0.12,
        z = anchor.z
    }
end

function BridgeReturnCombatPreviewCard(seatId, object)
    if object == nil then return end
    local guid = BridgeSafeObjectGuid(object)
    if guid == nil then return end
    local origin = BridgeState.attackOriginByGuid[guid]
    if origin ~= nil and BridgeState.physicalZoneByGuid[guid] == "battlefield" then
        object.setPositionSmooth(origin, false, true)
    end
    BridgeState.attackOriginByGuid[guid] = nil
    if BridgeState.attackLaneGuidBySeatId[seatId] ~= nil then
        BridgeState.attackLaneGuidBySeatId[seatId][guid] = nil
    end
    BridgeState.combatSelectedByGuid[guid] = nil
end

function BridgeReturnAttackPresentation(seatId)
    for guid, origin in pairs(BridgeState.attackOriginByGuid or {}) do
        local objectSeat = BridgeState.physicalSeatByGuid[guid]
        if seatId == nil or seatId == objectSeat then
            local object = getObjectFromGUID(guid)
            if object ~= nil and BridgeState.physicalZoneByGuid[guid] == "battlefield" then
                object.setPositionSmooth(origin, false, true)
            end
            BridgeState.attackOriginByGuid[guid] = nil
            if BridgeState.attackLaneGuidBySeatId[objectSeat] ~= nil then
                BridgeState.attackLaneGuidBySeatId[objectSeat][guid] = nil
            end
            BridgeState.combatSelectedByGuid[guid] = nil
        end
    end
    for guid, _ in pairs(BridgeState.combatSelectedByGuid or {}) do
        if seatId == nil or BridgeState.physicalSeatByGuid[guid] == seatId then
            BridgeState.combatSelectedByGuid[guid] = nil
        end
    end
end

function BridgeStopOnDesync(message)
    local diagnostic = tostring(message or "")
    if BridgeState.resyncInFlight == true then
        BridgeState.desyncFailureCount = (BridgeState.desyncFailureCount or 0) + 1
        BridgeState.desyncLastMessage = diagnostic
        BridgeLog("[Bridge] suppressed desync during authoritative resync: " .. diagnostic)
        return
    end
    if BridgeState.desyncLatched == true then
        BridgeState.desyncFailureCount = (BridgeState.desyncFailureCount or 0) + 1
        BridgeState.desyncLastMessage = diagnostic
        BridgeStopEventPolling("desync-latched")
        BridgeEnsureDesyncRecovery("duplicate-desync")
        BridgeLog("[Bridge] duplicate synchronization failure suppressed: " .. diagnostic)
        return
    end
    BridgeState.desyncLatched = true
    BridgeState.desyncFailureCount = (BridgeState.desyncFailureCount or 0) + 1
    BridgeState.desyncLastMessage = diagnostic
    BridgeStopEventPolling("desync-latched")
    BridgeStopDecisionPolling()
    BridgeState.animationRunning = false
    BridgeState.pendingDecision = nil
    BridgeState.pendingDecisionDeferredAt = nil
    BridgeState.pendingDecisionDeferredCursor = 0
    BridgeState.pendingDecisionDeferredApplied = 0
    BridgeClearHighlights()
    BridgeResetSelectionState()
    BridgeHideMainPriorityControls()
    if string.sub(diagnostic, 1, 16) == "LIBRARY MISMATCH" then
        -- Bootstrap mismatch has already emitted its complete, read-only
        -- inventory to the scripting log.  Keep the table-facing signal to
        -- one concise status diagnostic rather than broadcasting retries.
        BridgeLog("[Bridge] synchronization stopped: " .. diagnostic)
        BridgeSetStatus("LIBRARY MISMATCH", diagnostic)
        BridgeEnsureDesyncRecovery("library-mismatch")
        return
    end
    BridgeShowError("synchronization stopped: " .. diagnostic)
    BridgeEnsureDesyncRecovery("desync")
end

function BridgeEnforceDesyncRecovery(reason)
    if BridgeState.desyncLatched == true
        and not BridgeState.resyncInFlight
        and not BridgeState.resyncScheduled
        and not BridgeState.recoveryCheckpointCommitInProgress then
        BridgeEnsureDesyncRecovery(reason or "liveness-watchdog")
    end
end

function BridgeCheckRecoveryConvergence(reason)
    local received = tonumber(BridgeState.lastReceivedEventSequence or 0) or 0
    local applied = tonumber(BridgeState.lastAppliedEventSequence or 0) or 0
    local queueLength = #(BridgeState.eventQueue or {})
    if received <= applied then return false end
    if BridgeState.eventPolling == true or BridgeState.eventRequestInFlight == true
        or BridgeState.eventPollScheduled == true then
        return false
    end
    if BridgeState.resyncInFlight == true or BridgeState.resyncScheduled == true
        or BridgeState.snapshotReconcileInFlight == true or BridgeState.snapshotReconcilePending == true then
        return false
    end
    if queueLength > 0 then return false end

    local missing = nil
    if BridgeState.lastDecision ~= nil and BridgeDecisionPhysicalMappingsReady ~= nil then
        local ready, detail = BridgeDecisionPhysicalMappingsReady(BridgeState.lastDecision)
        if not ready then missing = detail end
    end
    local descriptor = string.format(
        "cursor-ahead-without-recovery reason=%s received=%s applied=%s resyncDeferredReason=%s circuitOpen=%s missing=%s",
        tostring(reason), tostring(received), tostring(applied), tostring(BridgeState.resyncDeferredReason),
        tostring(BridgeState.resyncCircuitOpen == true), tostring(missing))

    BridgeState.desyncLatched = true
    BridgeState.resyncLastFailureReason = descriptor
    BridgeSetStatus("RECOVERY BLOCKED", descriptor)
    BridgeLog("[Bridge] TERMINAL_RECOVERY_ERROR " .. descriptor)
    return true
end

function BridgeEnsureDesyncRecovery(reason)
    if BridgeState.desyncLatched ~= true or BridgeState.resyncInFlight == true then return end
    if BridgeState.resyncScheduled == true then return end
    if BridgeState.eventSessionId == nil then
        BridgeState.desyncLatched = false
        BridgeLog("[Bridge] cleared desync latch: no active session reason=" .. tostring(reason))
        return
    end
    BridgeState.resyncScheduled = true
    BridgeLog("[Bridge] RESYNC_SCHEDULED reason=" .. tostring(reason))
    BridgeWaitFrames(function()
        if BridgeState.resyncScheduled ~= true then return end
        if BridgeState.desyncLatched ~= true or BridgeState.resyncInFlight == true then
            BridgeState.resyncScheduled = false
            return
        end
        BridgeResyncFromAuthoritativeSnapshot("automatic-desync-recovery")
    end, 1)
end

function BridgePrintEventSyncStatus()
    BridgeLog(string.format(
        "[Bridge] event sync session=%s polling=%s received=%s applied=%s queued=%d retries=%d inFlight=%s",
        tostring(BridgeState.eventSessionId), tostring(BridgeState.eventPolling),
        tostring(BridgeState.lastReceivedEventSequence), tostring(BridgeState.lastAppliedEventSequence),
        #BridgeState.eventQueue, BridgeState.eventRetryCount, tostring(BridgeState.eventRequestInFlight)))
end

function BridgeDumpSyncState()
    BridgePrintEventSyncStatus()
    BridgeLogPresentationMetrics("sync-dump")
    BridgeLog("[Bridge] pendingIntent=" .. JSON.encode(BridgeState.pendingIntent or {}))
    BridgeLog("[Bridge] yieldPolicyActiveSeatId=" .. tostring(BridgeState.yieldPolicyActiveSeatId))
    BridgeLog("[Bridge] pendingQueue=" .. JSON.encode(BridgeState.eventQueue))
    BridgeLog("[Bridge] physicalByInstanceId=" .. JSON.encode(BridgeState.physicalByInstanceId))
    BridgeLog("[Bridge] physicalSeatByGuid=" .. JSON.encode(BridgeState.physicalSeatByGuid))
    BridgeLog("[Bridge] physicalZoneByGuid=" .. JSON.encode(BridgeState.physicalZoneByGuid))
end

-- ============================================================
-- F2D GAME HUD / DEV PRESENTATION OVERRIDES
--
-- This block intentionally sits at the end of Global.lua so the HUD polish
-- remains easy to remove or split into a generated module later.  It only
-- overrides presentation helpers; Forge remains authoritative for game state.
-- ============================================================

BRIDGE_DEV_UI_ENABLED = true
BRIDGE_DEV_ANNOTATIONS_ENABLED = true
BRIDGE_PHYSICAL_PRIORITY_CONTROLS_ENABLED = true
BRIDGE_SCRIPT_REVISION = "2026-08-30-u2-gameplay-repair"

BRIDGE_HUD_COLORS = {
    active = "#6DB5FF",
    inactive = "#718096",
    success = "#7BD88F",
    warning = "#F4C76B",
    danger = "#F27D7D"
}

function BridgeHudToggleDev(player, value, id)
    if BRIDGE_DEV_UI_ENABLED ~= true or BridgeState.ui == nil then return end
    BridgeState.ui.diagnosticsVisible = not (BridgeState.ui.diagnosticsVisible == true)
    BridgeUiMarkDirty("dev-drawer-toggle")
end

BRIDGE_REPORT_CATEGORIES = {
    "Gameplay sync", "Combat", "Card movement", "Presentation/UI", "Decision/prompt",
    "Mana/payment", "Performance / Freeze", "Crash/error", "Other"
}

function BridgeHudReportOpen(player, value, id)
    if BRIDGE_DEV_UI_ENABLED ~= true or BridgeState.ui == nil then return end
    BridgeState.ui.reportPanelVisible = true
    BridgeState.ui.reportStatus = "Ready to capture local diagnostic ZIP."
    BridgeUiMarkDirty("report-open")
end

function BridgeHudReportCancel(player, value, id)
    if BridgeState.ui == nil or BridgeState.ui.reportCaptureInFlight then return end
    BridgeState.ui.reportPanelVisible = false
    BridgeState.ui.reportStatus = ""
    BridgeUiMarkDirty("report-cancel")
end

function BridgeHudReportCategoryChanged(player, value, id)
    if BridgeState.ui == nil or BridgeState.ui.reportCaptureInFlight then return end
    for index, category in ipairs(BRIDGE_REPORT_CATEGORIES) do
        if value == category then
            BridgeState.ui.reportCategoryIndex = index
            BridgeUiMarkDirty("report-category-dropdown")
            return
        end
    end
end

function BridgeHudReportCategoryPrevious(player, value, id)
    local ui = BridgeState.ui
    if ui == nil or ui.reportCaptureInFlight then return end
    local count = #BRIDGE_REPORT_CATEGORIES
    if count == 0 then return end
    local index = (tonumber(ui.reportCategoryIndex or 1) or 1) - 1
    if index < 1 then index = count end
    ui.reportCategoryIndex = index
    BridgeUiMarkDirty("report-category-previous")
end

function BridgeHudReportCategory(player, value, id)
    local ui = BridgeState.ui
    if ui == nil or ui.reportCaptureInFlight then return end
    local count = #BRIDGE_REPORT_CATEGORIES
    if count == 0 then return end
    local index = (tonumber(ui.reportCategoryIndex or 1) or 1) + 1
    if index > count then index = 1 end
    ui.reportCategoryIndex = index
    BridgeUiMarkDirty("report-category-next")
end

function BridgeHudReportMappedCardInstanceIds()
    local ids = {}
    for cardInstanceId, _ in pairs(BridgeState.physicalByInstanceId or {}) do
        table.insert(ids, cardInstanceId)
    end
    table.sort(ids)
    return ids
end

function BridgeHudReportPhysicalMappings()
    local mappings = {}
    local seenGuids = {}
    for cardInstanceId, guid in pairs(BridgeState.physicalByInstanceId or {}) do
        local object = BridgeGetLiveObjectByGuid(guid)
        table.insert(mappings, {
            cardInstanceId = cardInstanceId,
            guid = guid,
            zone = BridgeState.physicalZoneByGuid[guid],
            isLive = object ~= nil,
            advertisedCardInstanceId = BridgeReadPhysicalIdentity(object)
        })
        seenGuids[guid] = true
    end
    -- A mapped table entry cannot reveal an extra physical duplicate.  Only
    -- inspect cards that explicitly advertise a Bridge identity; foreign or
    -- importer-owned cards remain outside Forge mapping ownership.
    if type(getAllObjects) == "function" then
        for _, object in ipairs(getAllObjects() or {}) do
            if object ~= nil and object.tag == "Card" then
                local guid = BridgeSafeObjectGuid(object)
                local advertised = BridgeReadPhysicalIdentity(object)
                if guid ~= nil and advertised ~= nil and not seenGuids[guid] then
                    table.insert(mappings, {
                        cardInstanceId = advertised,
                        guid = guid,
                        zone = nil,
                        isLive = true,
                        advertisedCardInstanceId = advertised
                    })
                    seenGuids[guid] = true
                end
            end
        end
    end
    table.sort(mappings, function(left, right)
        return tostring(left.cardInstanceId) < tostring(right.cardInstanceId)
    end)
    return mappings
end

function BridgeHudReportSummaryText()
    local ok, value = pcall(function() return UI.getAttribute("BridgeHudReportSummary", "text") end)
    if not ok or value == nil then return nil end
    value = tostring(value)
    return value ~= "" and value or nil
end

function BridgeScheduleDiagnosticCaptureFollowup(token, sessionId, epoch)
    if token == nil or BridgeState.diagnosticCaptureFollowupToken == token then return end
    BridgeState.diagnosticCaptureFollowupToken = token
    BridgeState.diagnosticCaptureFollowupUntil = os.clock() + BRIDGE_DIAGNOSTIC_CAPTURE_FOLLOWUP_SECONDS
    local function sample()
        if not BridgeRuntimeIsCurrent(epoch)
            or BridgeState.eventSessionId ~= sessionId
            or BridgeState.diagnosticCaptureFollowupToken ~= token then
            return
        end
        if os.clock() > BridgeState.diagnosticCaptureFollowupUntil then return end
        BridgeRecordDiagnosticCaptureLifecycle("DIAG_CAPTURE_POSTCHECK", token, "post-capture")
        BridgeWaitTime(sample, BRIDGE_DIAGNOSTIC_CAPTURE_FOLLOWUP_INTERVAL_SECONDS)
    end
    BridgeWaitTime(sample, BRIDGE_DIAGNOSTIC_CAPTURE_FOLLOWUP_INTERVAL_SECONDS)
end

function BridgeDiagnosticCaptureGameplayFingerprint()
    local decision = BridgeState.lastDecision
    local pending = BridgeState.pendingDecision
    local ui = BridgeState.ui or {}
    local function value(v) return tostring(v == nil and "<nil>" or v) end
    return table.concat({
        value(BridgeState.eventSessionId), value(decision and decision.decisionId),
        value(pending and pending.decisionId), value(BridgeState.currentPhase),
        value(BridgeState.currentTurnSeatId), value(BridgeState.prioritySeatId),
        value(BridgeState.lastReceivedEventSequence), value(BridgeState.lastAppliedEventSequence),
        value(BridgeState.lastConsumedEventSequence), value(BridgeState.lastStateProjectedEventSequence),
        value(BridgeState.lastPhysicalPresentationEventSequence), value(#(BridgeState.eventQueue or {})),
        value(BridgeState.eventPollGeneration), value(BridgeState.eventSessionGeneration),
        value(BridgeState.eventPolling), value(BridgeState.eventRequestInFlight),
        value(BridgeState.eventPollScheduled), value(BridgeState.decisionPollGeneration),
        value(BridgeState.decisionPollInFlight), value(BridgeState.decisionPollScheduled),
        value(BridgeState.decisionPresentationGeneration), value(BridgeState.submitting),
        value(BridgeState.choiceProtocolPaused), value(BridgeState.animationRunning),
        value(BridgeState.yieldPolicyTurnNumber), value(BridgeState.yieldPolicyActiveSeatId),
        value(BridgeState.yieldPolicySessionId), value(BridgeState.resyncInFlight),
        value(BridgeState.resyncScheduled), value(BridgeState.desyncLatched),
        value(ui.autoAdvanceMode), value(ui.autoPassEmpty), value(ui.fastForwardActive)
    }, "|")
end

function BridgeCheckDiagnosticCapturePurity(before, token, stage)
    local after = BridgeDiagnosticCaptureGameplayFingerprint()
    if before ~= after then
        BridgeLog(string.format("[Bridge] DIAG_CAPTURE_PURITY_VIOLATION token=%s stage=%s before=%s after=%s",
            tostring(token), tostring(stage), tostring(before), tostring(after)))
        BridgeRecordDiagnosticCaptureLifecycle("DIAG_CAPTURE_PURITY_VIOLATION", token, stage)
        return false
    end
    return true
end

function BridgeRecoverGameplayPumps(reason, expectedSessionId, expectedEpoch, captureToken)
    local sessionId = expectedSessionId or BridgeState.eventSessionId
    local epoch = expectedEpoch or BRIDGE_RUNTIME_EPOCH_LOCAL
    local isCaptureRecovery = captureToken ~= nil
    local recoveryEnded = false
    local function endRecovery(detail)
        if recoveryEnded then return end
        recoveryEnded = true
        if isCaptureRecovery then
            BridgeRecordDiagnosticCaptureLifecycle("DIAG_CAPTURE_RECOVERY_END", captureToken, detail or reason)
            BridgeScheduleDiagnosticCaptureFollowup(captureToken, sessionId, epoch)
        else
            BridgeLog("[Bridge] gameplay pump recovery complete reason=" .. tostring(detail or reason))
        end
    end
    if isCaptureRecovery then
        BridgeRecordDiagnosticCaptureLifecycle("DIAG_CAPTURE_RECOVERY_BEGIN", captureToken, reason)
    end
    if not BridgeRuntimeIsCurrent(epoch)
        or BridgeState.eventSessionId ~= sessionId
        or sessionId == nil
        or BridgeState.desyncLatched then
        endRecovery("recovery-fence-not-current")
        return false
    end

    -- The event poll generation belongs to HTTP callback freshness. These
    -- checks deliberately inspect the request/schedule state too; `true`
    -- alone is not evidence that an event pump is alive.
    if BridgeState.eventPolling ~= true then
        BridgeStartEventPolling(sessionId, false)
    elseif not BridgeState.eventRequestInFlight and not BridgeState.eventPollScheduled then
        BridgePollEvents(BridgeState.eventPollGeneration)
    end

    if BridgeState.lastDecision == nil then
        if BridgeState.gameEnded == nil and not BridgeState.submitting
            and not BridgeState.decisionPollInFlight
            and not BridgeState.decisionPollScheduled
            and not BridgeState.choiceProtocolPaused then
            BridgeStartDecisionPolling()
        end
        endRecovery("no-current-decision")
        return true
    end

    -- A non-nil decision can still have lost its render/control path. Ask
    -- Forge for the current decision once, then use the existing acceptance
    -- path. Same-id responses are rendered again without creating a choice.
    if BridgeState.decisionRefreshInFlight then
        endRecovery("decision-refresh-already-in-flight")
        return true
    end
    local expectedPresentationGeneration = BridgeState.decisionPresentationGeneration
    local priorDecision = BridgeState.lastDecision
    local priorDecisionId = priorDecision.decisionId
    BridgeState.decisionRefreshInFlight = true
    BridgeGetDecision(function(ok, body, err)
        if (expectedSessionId ~= nil and expectedSessionId ~= BridgeState.eventSessionId)
            or not BridgeRuntimeIsCurrent(epoch)
            or expectedPresentationGeneration ~= BridgeState.decisionPresentationGeneration then
            BridgeState.decisionRefreshInFlight = false
            if isCaptureRecovery then
                BridgeRecordDiagnosticCaptureLifecycle("DIAG_CAPTURE_DECISION_REFRESH_CALLBACK", captureToken, "stale")
            end
            return
        end
        BridgeState.decisionRefreshInFlight = false
        if ok and body ~= nil then
            local sameDecision = body.decisionId == priorDecisionId
            local transactionExists = BridgeState.choiceTransactions[priorDecisionId] ~= nil
            if sameDecision and transactionExists then
                -- A submitted/active transaction is presentation-live only
                -- through its existing response path. Do not re-accept it and
                -- risk clearing the transaction during diagnostic recovery.
                BridgeLog("[Bridge] diagnostic decision refresh preserved active choice transaction decision=" .. tostring(priorDecisionId))
            else
                BridgeAcceptDecision(body, "diagnostic_capture_recovery", sessionId, expectedPresentationGeneration)
            end
            if isCaptureRecovery then
                BridgeRecordDiagnosticCaptureLifecycle("DIAG_CAPTURE_DECISION_REFRESH_CALLBACK", captureToken, sameDecision and "same-decision" or "new-decision")
            end
            endRecovery(sameDecision and "same-decision-represented" or "new-decision-accepted")
            return
        end
        local responseCode = nil
        if body ~= nil and body.errorCode ~= nil then responseCode = tostring(body.errorCode) end
        if responseCode == "no_pending_decision" then
            -- Keep the existing presentation intact while Forge is between
            -- decisions. The ordinary poller is allowed to observe through
            -- that presentation and will replace it only with an
            -- authoritative response.
            BridgeStartDecisionPolling(true)
        end
        BridgeLog("[Bridge] diagnostic decision refresh failed: " .. tostring(err or responseCode or "unknown"))
        if isCaptureRecovery then
            BridgeRecordDiagnosticCaptureLifecycle("DIAG_CAPTURE_DECISION_REFRESH_CALLBACK", captureToken, responseCode or "failed")
        end
        endRecovery("decision-refresh-failed")
    end)
    return true
end

function BridgeHudRecoverPumps(player, value, id)
    if BRIDGE_DEV_UI_ENABLED ~= true or BridgeState.ui == nil then return end
    if BridgeState.eventSessionId == nil then
        BridgeState.ui.reportStatus = "No active Forge session to recover."
        BridgeUiMarkDirty("manual-pump-recovery-unavailable")
        return
    end
    BridgeState.ui.reportStatus = "Recovering gameplay observation..."
    BridgeUiMarkDirty("manual-pump-recovery-start")
    BridgeRecoverGameplayPumps("manual-control", BridgeState.eventSessionId, BRIDGE_RUNTIME_EPOCH_LOCAL, nil)
end

function BridgeHudSubmitReport(category, summary)
    local ui = BridgeState.ui
    if ui == nil or ui.reportCaptureInFlight then return end
    local requestUi = ui
    local requestEpoch = BRIDGE_RUNTIME_EPOCH_LOCAL
    local requestSession = BridgeState.eventSessionId
    requestUi.reportCaptureToken = (tonumber(requestUi.reportCaptureToken or 0) or 0) + 1
    local captureToken = requestUi.reportCaptureToken
    local completed = false

    BridgeRecordDiagnosticCaptureLifecycle("DIAG_CAPTURE_REQUESTED", captureToken, "user-request")
    BridgeRecordDiagnosticCaptureLifecycle("DIAG_CAPTURE_BEGIN", captureToken, "capture-start")
    local capturePurityBefore = BridgeDiagnosticCaptureGameplayFingerprint()

    ui.reportCaptureInFlight = true
    ui.reportStatus = "Capturing..."
    BridgeUiMarkDirty("report-capture-start")

    local function finish(ok, body, err, recoveryReason, lifecycleStage)
        BridgeRecordDiagnosticCaptureLifecycle(lifecycleStage or "DIAG_CAPTURE_CALLBACK", captureToken, recoveryReason or "callback")
        if completed then return end
        if requestUi.reportCaptureToken ~= captureToken then return end
        completed = true
        if not BridgeRuntimeIsCurrent(requestEpoch)
            or BridgeState.ui ~= requestUi
            or BridgeState.eventSessionId ~= requestSession then
            BridgeLog("[Bridge] diagnostic capture completion ignored by runtime/session fence")
            return
        end
        requestUi.reportCaptureInFlight = false
        if ok and body ~= nil and body.success == true then
            local reportId = tostring(body.reportId or "unknown")
            local reportPath = tostring(body.reportPath or "BugReports")
            requestUi.reportStatus = "CAPTURED â€¢ " .. reportId .. "\n" .. reportPath
            BridgeLog("[Bridge] diagnostic report captured id=" .. reportId .. " path=" .. reportPath)
            BridgeRecordDiagnosticCaptureLifecycle("DIAG_CAPTURE_COMPLETED", captureToken, "response-success")
        else
            local detail = BridgeHttpFailureDetail(body, err or "capture failed")
            requestUi.reportStatus = "ERROR â€¢ " .. detail
            BridgeLog("[Bridge] diagnostic report failed: " .. detail)
            BridgeRecordDiagnosticCaptureLifecycle("DIAG_CAPTURE_FAILED", captureToken, detail)
        end
        BridgeRecordDiagnosticCaptureLifecycle("DIAG_CAPTURE_CLEANUP_COMPLETED", captureToken, "capture-state-released")
        BridgeUiMarkDirty("report-capture-result")
        -- A report is an observer. Completion must not restart pollers,
        -- refresh a decision, or rebuild presentation; normal liveness and
        -- recovery watchdogs own those mutations.
        BridgeCheckDiagnosticCapturePurity(capturePurityBefore, captureToken, "completion")
    end

    -- Arm the watchdog before collecting any diagnostic payload.  Payload
    -- collection runs inside TTS and may encounter a transient/invalid object;
    -- an exception there must not strand reportCaptureInFlight forever.
    BridgeWaitTime(function()
        if requestUi.reportCaptureToken == captureToken and requestUi.reportCaptureInFlight then
            finish(false, nil, "diagnostic capture timed out after " .. tostring(BRIDGE_REPORT_CAPTURE_TIMEOUT_SECONDS) .. " seconds", "watchdog", "DIAG_CAPTURE_TIMEOUT")
        end
    end, BRIDGE_REPORT_CAPTURE_TIMEOUT_SECONDS)

    local performanceOk, performance = pcall(BridgePerformanceDiagnosticPayload)
    if not performanceOk or performance == nil then
        finish(false, nil, "diagnostic payload failed: " .. tostring(performance), "payload-failure")
        return
    end
    BridgeRecordDiagnosticCaptureLifecycle("DIAG_CAPTURE_SNAPSHOT_COPIED", captureToken, "immutable-payload-copied")
    local request = {
        summary = summary or BridgeHudReportSummaryText(),
        category = category or BRIDGE_REPORT_CATEGORIES[tonumber(ui.reportCategoryIndex or 1) or 1] or "Other",
        sessionId = BridgeState.eventSessionId,
        decisionId = BridgeState.lastDecision and BridgeState.lastDecision.decisionId or nil,
        clientRuntimeId = BRIDGE_CLIENT_RUNTIME_ID,
        clientRevision = BRIDGE_SCRIPT_REVISION,
        lastAppliedEventSequence = BridgeState.lastAppliedEventSequence,
        turn = BridgeState.tableTurnCount,
        phase = BridgeState.currentPhase,
        activePlayer = BridgeState.currentTurnSeatId,
        priorityPlayer = BridgeState.prioritySeatId,
        mappedCardInstanceIds = BridgeHudReportMappedCardInstanceIds(),
        physicalMappings = BridgeHudReportPhysicalMappings(),
        status = BridgeState.statusHeadline,
        performanceSummary = performance.performanceSummary,
        recentTtsTrace = performance.recentTtsTrace,
        diagnosticCaptureLifecycle = performance.diagnosticCaptureLifecycle,
        eventDrainDiagnostics = performance.eventDrainDiagnostics
    }
    local requestOk, requestError = pcall(function()
        BridgeRecordDiagnosticCaptureLifecycle("DIAG_CAPTURE_HANDED_OFF", captureToken, "bridge-request")
        BridgeHttp.requestJson("POST", "/api/v1/diagnostics/report", request, function(ok, body, err)
            finish(ok, body, err, "callback", "DIAG_CAPTURE_CALLBACK")
            return
        --[[ legacy inline completion retained only as a source-compatible
             comment while all completion is routed through finish above.
        ui.reportCaptureInFlight = false
        if ok and body ~= nil and body.success == true then
            local reportId = tostring(body.reportId or "unknown")
            local reportPath = tostring(body.reportPath or "BugReports")
            ui.reportStatus = "CAPTURED • " .. reportId .. "\n" .. reportPath
            BridgeLog("[Bridge] diagnostic report captured id=" .. reportId .. " path=" .. reportPath)
        else
            local detail = BridgeHttpFailureDetail(body, err or "capture failed")
            ui.reportStatus = "ERROR • " .. detail
            BridgeLog("[Bridge] diagnostic report failed: " .. detail)
        end
        BridgeUiMarkDirty("report-capture-result") ]]
        end)
    end)
    if not requestOk then
        finish(false, nil, "diagnostic request failed: " .. tostring(requestError), "request-error")
    end
end

function BridgeHudReportCapture(player, value, id)
    BridgeHudSubmitReport(nil, nil)
end

function BridgeHudRollingCapture(player, value, id)
    local ui = BridgeState.ui
    if ui == nil or ui.reportCaptureInFlight then return end
    -- This button is intentionally visible outside the developer drawer so a
    -- recovered freeze can be captured without first navigating another UI.
    -- Open the drawer after the one-click request so the result path/status is
    -- still visible to the host.
    ui.diagnosticsVisible = true
    ui.reportPanelVisible = true
    BridgeHudSubmitReport("Performance / Freeze", "Rolling freeze capture")
end

function BridgeHudResyncFromForge(player, value, id)
    local ui = BridgeState.ui
    if ui == nil then
        BridgeLog("[Bridge] RESYNC_CLICK ignored reason=ui-unavailable")
        return
    end
    local queueState = BridgeEventDrainQueueState()
    BridgeLog(string.format(
        "[Bridge] RESYNC_CLICK session=%s resyncInFlight=%s physicalQueuesIdle=%s eventQueueHead=%s eventQueueLength=%s desyncLatched=%s bootstrapping=%s runtimeEpoch=%s",
        tostring(BridgeState.eventSessionId), tostring(ui.resyncInFlight),
        tostring(queueState.physicalLibraryQueuesIdle), tostring(queueState.headSequence),
        tostring(queueState.queueLength), tostring(queueState.desyncLatched),
        tostring(queueState.bootstrapping), tostring(BRIDGE_RUNTIME_EPOCH_LOCAL)))
    if ui.resyncInFlight == true then
        BridgeLog("[Bridge] RESYNC_DEFERRED reason=ui-latched")
        return
    end
    local started = BridgeResyncFromAuthoritativeSnapshot("hud")
    if started ~= true then
        BridgeLog("[Bridge] RESYNC_DEFERRED reason=local-recovery-path")
    end
end

function BridgeHudPhaseElementId(phase)
    local value = string.upper(tostring(phase or ""))
    if string.find(value, "UNTAP", 1, true) then return "BridgePhaseUntap" end
    if string.find(value, "UPKEEP", 1, true) then return "BridgePhaseUpkeep" end
    if string.find(value, "DRAW", 1, true) then return "BridgePhaseDraw" end
    if string.find(value, "MAIN", 1, true) then
        if string.find(value, "POSTCOMBAT", 1, true)
            or string.find(value, "MAIN 2", 1, true)
            or string.find(value, "SECOND", 1, true) then
            return "BridgePhaseMain2"
        end
        if string.find(value, "PRECOMBAT", 1, true)
            or string.find(value, "MAIN 1", 1, true)
            or string.find(value, "FIRST", 1, true) then
            return "BridgePhaseMain1"
        end
        return "BridgePhaseMain1"
    end
    if string.find(value, "COMBAT", 1, true)
        or string.find(value, "ATTACK", 1, true)
        or string.find(value, "BLOCK", 1, true)
        or string.find(value, "DAMAGE", 1, true) then
        return "BridgePhaseCombat"
    end
    if string.find(value, "END", 1, true) or string.find(value, "CLEANUP", 1, true) then
        return "BridgePhaseEnd"
    end
    return nil
end

function BridgeHudRefreshPhaseRibbon()
    local phaseIds = {
        "BridgePhaseUntap",
        "BridgePhaseUpkeep",
        "BridgePhaseDraw",
        "BridgePhaseMain1",
        "BridgePhaseCombat",
        "BridgePhaseMain2",
        "BridgePhaseEnd"
    }
    local activeId = BridgeHudPhaseElementId(BridgeState.currentPhase)
    for _, phaseId in ipairs(phaseIds) do
        BridgeUiSet(
            phaseId,
            "color",
            phaseId == activeId and BRIDGE_HUD_COLORS.active or BRIDGE_HUD_COLORS.inactive
        )
    end
end

-- Phase presentation is derived from the authoritative Forge phase field.
-- The HUD never advances phases; this color is only a readable cue that the
-- state machine has already moved to a new phase.
function BridgeHudPhaseColor(phase)
    local value = string.upper(tostring(phase or ""))
    if string.find(value, "UNTAP", 1, true) then return "#94A3B8" end
    if string.find(value, "UPKEEP", 1, true) then return "#F59E0B" end
    if string.find(value, "DRAW", 1, true) then return "#22C55E" end
    if string.find(value, "MAIN", 1, true) then return "#38BDF8" end
    if string.find(value, "COMBAT", 1, true)
        or string.find(value, "ATTACK", 1, true)
        or string.find(value, "BLOCK", 1, true)
        or string.find(value, "DAMAGE", 1, true) then return "#F97316" end
    if string.find(value, "END", 1, true) or string.find(value, "CLEANUP", 1, true) then return "#A78BFA" end
    return "#F8FAFC"
end

function BridgeHudConnectionPresentation()
    local headline = string.upper(tostring(BridgeState.statusHeadline or ""))
    if BridgeState.choiceProtocolPaused == true then
        return "● PAUSED", BRIDGE_HUD_COLORS.danger
    end
    if string.find(headline, "OFFLINE", 1, true) then
        return "● OFFLINE", BRIDGE_HUD_COLORS.danger
    end
    if BridgeState.eventSessionId ~= nil then
        return "● MATCH", BRIDGE_HUD_COLORS.success
    end
    if string.find(headline, "ERROR", 1, true) then
        return "● ERROR", BRIDGE_HUD_COLORS.danger
    end
    return "○ SETUP", BRIDGE_HUD_COLORS.warning
end

-- Preserve the existing HUD renderer and layer game-HUD presentation over it.
-- Existing IDs, action rows, exact Forge choices, FAST/MANA/LOG behavior, and
-- footer semantics remain owned by the original renderer above.
local BridgeUiFlushBase = BridgeUiFlush
function BridgeUiFlush()
    BridgeUiFlushBase()
    local ui = BridgeState.ui
    if ui == nil or not ui.mounted then return end

    local devEnabled = BRIDGE_DEV_UI_ENABLED == true
    local devExpanded = devEnabled and ui.diagnosticsVisible == true
    BridgeUiSet("BridgeHudDevToggle", "active", devEnabled and "true" or "false")
    BridgeUiSet("BridgeHudDevRoot", "active", devExpanded and "true" or "false")
    local yieldUi = ui.fastForwardActive and "FAST-FORWARD" or (ui.autoPassEmpty and "AUTO-PASS: ON" or "AUTO-PASS: OFF")
    BridgeUiSet("BridgeHudMode", "text", yieldUi)
    BridgeUiSet("BridgeHudFastForward", "text", ui.fastForwardActive and "CANCEL FAST-FORWARD" or "FAST-FORWARD")
    local stops = ui.fastForwardStops or {own_turn = {}, other_turn = {}}
    local stopButtons = {
        BridgeHudStopOwn_Upkeep = {"own_turn", "upkeep"}, BridgeHudStopOwn_Draw = {"own_turn", "draw"},
        BridgeHudStopOwn_MainPre = {"own_turn", "main_precombat"}, BridgeHudStopOwn_BeginningCombat = {"own_turn", "beginning_combat"},
        BridgeHudStopOwn_Attackers = {"own_turn", "declare_attackers"}, BridgeHudStopOwn_Blockers = {"own_turn", "declare_blockers"},
        BridgeHudStopOwn_Damage = {"own_turn", "combat_damage"}, BridgeHudStopOwn_EndCombat = {"own_turn", "end_combat"},
        BridgeHudStopOwn_MainPost = {"own_turn", "main_postcombat"}, BridgeHudStopOwn_EndStep = {"own_turn", "end_step"},
        BridgeHudStopOther_Upkeep = {"other_turn", "upkeep"}, BridgeHudStopOther_Draw = {"other_turn", "draw"},
        BridgeHudStopOther_MainPre = {"other_turn", "main_precombat"}, BridgeHudStopOther_BeginningCombat = {"other_turn", "beginning_combat"},
        BridgeHudStopOther_Attackers = {"other_turn", "declare_attackers"}, BridgeHudStopOther_Blockers = {"other_turn", "declare_blockers"},
        BridgeHudStopOther_Damage = {"other_turn", "combat_damage"}, BridgeHudStopOther_EndCombat = {"other_turn", "end_combat"},
        BridgeHudStopOther_MainPost = {"other_turn", "main_postcombat"}, BridgeHudStopOther_EndStep = {"other_turn", "end_step"}
    }
    for id, value in pairs(stopButtons) do
        local active = stops[value[1]] and stops[value[1]][value[2]] == true
        BridgeUiSet(id, "color", active and "#A16207EE" or "#334155CC")
    end
    BridgeUiSet("BridgeHudDevToggle", "text", devExpanded and "DEV ▲" or "DEV ▼")
    local reportVisible = devExpanded and ui.reportPanelVisible == true
    local reportCategoryIndex = tonumber(ui.reportCategoryIndex or 1) or 1
    BridgeUiSet("BridgeHudReportPanel", "active", reportVisible and "true" or "false")
    BridgeUiSet("BridgeHudReportOpen", "active", devEnabled and "true" or "false")
    BridgeUiSet("BridgeHudRollingCapture", "active", devEnabled and (ui.reportCaptureInFlight and "false" or "true") or "false")
    -- Keep recovery available after BridgeStopOnDesync.  The handler gives a
    -- diagnostic error if no Forge session exists; hiding it here made the
    -- recovery control disappear exactly when a library mismatch needed it.
    BridgeUiSet("BridgeHudResyncFromForge", "active", devEnabled and not ui.resyncInFlight and "true" or "false")
    BridgeUiSet("BridgeHudResyncFromForge", "text", ui.resyncInFlight and "RESYNCING..." or "RESYNC FORGE")
    -- Some TTS clients render Dropdown as a non-interactive checkbox. The
    -- adjacent previous/current buttons use ordinary Button callbacks and are
    -- reliable in desktop and VR, so they are the supported category control.
    BridgeUiSet("BridgeHudReportCategoryDropdown", "active", "false")
    BridgeUiSet("BridgeHudReportCategoryDropdown", "options", table.concat(BRIDGE_REPORT_CATEGORIES, "|"))
    BridgeUiSet("BridgeHudReportCategoryDropdown", "value", BRIDGE_REPORT_CATEGORIES[reportCategoryIndex] or "Other")
    local categoryControlsActive = reportVisible and not ui.reportCaptureInFlight
    BridgeUiSet("BridgeHudReportCategoryPrevious", "active", categoryControlsActive and "true" or "false")
    BridgeUiSet("BridgeHudReportCategory", "active", categoryControlsActive and "true" or "false")
    BridgeUiSet("BridgeHudReportCategory", "text", BRIDGE_REPORT_CATEGORIES[reportCategoryIndex] or "Other")
    BridgeUiSet("BridgeHudReportCapture", "active", reportVisible and (ui.reportCaptureInFlight and "false" or "true") or "false")
    BridgeUiSet("BridgeHudReportCancel", "active", reportVisible and (ui.reportCaptureInFlight and "false" or "true") or "false")
    BridgeUiSet("BridgeHudReportStatus", "text", ui.reportStatus or "")
    BridgeUiSet("BridgeHudReportStatus", "color", string.find(string.upper(tostring(ui.reportStatus or "")), "ERROR", 1, true) and BRIDGE_HUD_COLORS.danger or BRIDGE_HUD_COLORS.success)

    local decision = BridgeState.lastDecision
    local terminal = BridgeState.gameEnded
    local requiresConfirm = decision ~= nil and BridgeDecisionNeedsConfirmation(decision)
    local creatureTypeDecision = decision ~= nil and decision.kind == "creature_type_selection"
    local castPreviewPending = BridgeState.pendingIntent ~= nil
        and BridgeState.pendingIntent.action ~= nil
        and BridgeState.pendingIntent.action.type == "cast_spell"
    local gameControlsActive = terminal == nil and not requiresConfirm and not creatureTypeDecision
        and not castPreviewPending
    BridgeUiSet("BridgeHudGameControls", "active", gameControlsActive and "true" or "false")
    BridgeUiSet("BridgeHudDecisionControls", "active", (terminal == nil and (requiresConfirm or castPreviewPending)) and "true" or "false")

    -- Keep the fixed 24-row action transport intact.  The tray itself is now
    -- contextual and disappears when PASS/YIELD are the only available choice.
    local hasTextChoices = false
    for _, action in ipairs(ui.actionRows or {}) do
        if action.type ~= "pass_priority" then
            hasTextChoices = true
            break
        end
    end
    local graveyardFolderVisible = decision ~= nil
        and ui.graveyardFolderDecisionId == decision.decisionId
        and ui.graveyardFolderOpen == true
    BridgeUiSet("BridgeHudChoiceTray", "active", hasTextChoices and not creatureTypeDecision
        and not graveyardFolderVisible and "true" or "false")
    BridgeUiSet("BridgeHudGraveyardPanel", "active", graveyardFolderVisible and "true" or "false")
    local graveyardPage = tonumber(ui.graveyardFolderPage or 1) or 1
    local graveyardPageCount = math.max(math.ceil(#(ui.graveyardActionRows or {}) / 24), 1)
    BridgeUiSet("BridgeHudGraveyardOverflow", "text", graveyardFolderVisible
        and ("Page " .. tostring(graveyardPage) .. " / " .. tostring(graveyardPageCount)) or "")
    BridgeUiSet("BridgeHudGraveyardPrev", "active", graveyardFolderVisible and graveyardPage > 1 and "true" or "false")
    BridgeUiSet("BridgeHudGraveyardNext", "active", graveyardFolderVisible and graveyardPage < graveyardPageCount and "true" or "false")
    for i = 1, 24 do
        local action = graveyardFolderVisible and ui.graveyardActionRows[(graveyardPage - 1) * 24 + i] or nil
        BridgeUiSet("BridgeHudGraveyardAction" .. tostring(i), "active", action ~= nil and "true" or "false")
        if action ~= nil then
            BridgeUiSet("BridgeHudGraveyardAction" .. tostring(i), "text", BridgeUiActionLabel(action))
            BridgeUiSet("BridgeHudGraveyardAction" .. tostring(i), "tooltip", "Forge action from "
                .. tostring(action.sourceCardName or action.cardIdentity or "graveyard card")
                .. "\nAction ID: " .. tostring(action.actionId))
        end
    end
    BridgeUiSet("BridgeHudGraveyardClose", "active", graveyardFolderVisible and "true" or "false")
    local creatureTypeLabels = {}
    local creatureTypeSelectedLabel = ""
    for _, option in ipairs(ui.creatureTypeOptions or {}) do
        table.insert(creatureTypeLabels, option.label)
        if option.actionId == ui.creatureTypeDraftActionId then creatureTypeSelectedLabel = option.label end
    end
    BridgeUiSet("BridgeHudCreatureTypePanel", "active", creatureTypeDecision and "true" or "false")
    -- TTS Dropdown cannot safely hold an empty option list, even while the
    -- containing panel is inactive. Keep a neutral sentinel until Forge
    -- supplies a creature-type decision.
    local creatureTypeOptions = #creatureTypeLabels > 0 and table.concat(creatureTypeLabels, "|") or "Choose"
    local creatureTypeValue = creatureTypeSelectedLabel ~= "" and creatureTypeSelectedLabel or "Choose"
    BridgeUiSet("BridgeHudCreatureTypeDropdown", "options", creatureTypeOptions)
    BridgeUiSet("BridgeHudCreatureTypeDropdown", "value", creatureTypeValue)
    BridgeUiSet("BridgeHudCreatureTypeConfirm", "active", creatureTypeDecision
        and ui.creatureTypeDraftActionId ~= nil and "true" or "false")
    BridgeUiSet("BridgeHudCreatureTypeStatus", "text", creatureTypeDecision
        and (ui.creatureTypeDraftActionId and "Draft selected — press CONFIRM to submit to Forge"
            or "Choose a creature type, then press CONFIRM") or "")

    local connectionText, connectionColor = BridgeHudConnectionPresentation()
    BridgeUiSet("BridgeHudConnection", "text", connectionText)
    BridgeUiSet("BridgeHudConnection", "color", connectionColor)

    local stack = BridgeState.stackSummary or {}
    BridgeUiSet("BridgeHudStack", "text", #stack > 0 and ("STACK " .. tostring(#stack)) or "")
    BridgeUiSet("BridgeHudStackDetails", "text", #stack > 0 and table.concat(stack, " | ") or "")
    local stackObjects = BridgeState.stackObjects or {}
    local fallback = {}
    for i = 1, 6 do
        local stackObject = stackObjects[i]
        local image = stackObject ~= nil and BridgeRevealCardArt ~= nil
            and BridgeRevealCardArt({cardName = stackObject.sourceName}) or nil
        BridgeUiSet("BridgeHudStackImage" .. tostring(i), "active", image ~= nil and "true" or "false")
        BridgeUiSet("BridgeHudStackImage" .. tostring(i), "image", image or "")
        if stackObject ~= nil and image == nil then
            table.insert(fallback, tostring(stackObject.sourceName or "Stack object") .. ": "
                .. tostring(stackObject.abilityText or stackObject.abilityName or "Triggered ability"))
        end
    end
    BridgeUiSet("BridgeHudStackFallback", "text", table.concat(fallback, " | "))
    BridgeHudRefreshPhaseRibbon()

    if BRIDGE_DEV_ANNOTATIONS_ENABLED == true then
        local diagnostic = string.format(
            "session=%s  decision=%s  events=%s/%s  queue=%d  forgeSeq=%s",
            tostring(BridgeState.eventSessionId or "none"),
            tostring(decision and decision.decisionId or "none"),
            tostring(BridgeState.lastAppliedEventSequence or 0),
            tostring(BridgeState.lastReceivedEventSequence or 0),
            #(BridgeState.eventQueue or {}),
            tostring(BridgeState.snapshotForgeSequence or 0)
        )
        BridgeUiSet("BridgeHudDevDiagnostic", "text", diagnostic)
    else
        BridgeUiSet("BridgeHudDevDiagnostic", "text", "")
    end
end

-- Dedicated physical priority controls can survive Save & Play while their
-- scripted createButton overlay does not.  Always rehydrate that overlay when
-- an existing control is rediscovered, instead of leaving a blank colored slab.
function BridgeConfigureEndTurnObject(object, seat)
    if object == nil or seat == nil or not BridgeObjectIsUsable(object) then return end
    BridgeSafeObjectCall(object, function(o)
        o.setName("Forge End Turn")
        o.setLock(true)
        o.setColorTint({0.12, 0.3, 0.62})
        o.setRotation({0, seat.tableSideZ < 0 and 180 or 0, 0})
        if o.clearButtons ~= nil then o.clearButtons() end
        o.createButton({
            click_function = "BridgePressEndTurn",
            function_owner = Global,
            label = "END TURN\n(YIELD)",
            position = {0, 0.6, 0},
            width = 1100,
            height = 520,
            font_size = 170,
            color = {0.15, 0.35, 0.65, 1.0},
            font_color = {1.0, 1.0, 1.0, 1.0},
            tooltip = "Yield Forge priority for the rest of this turn"
        })
    end)
end

function BridgeConfigurePassObject(object, seat)
    if object == nil or seat == nil or not BridgeObjectIsUsable(object) then return end
    BridgeSafeObjectCall(object, function(o)
        o.setName("Forge Pass Priority")
        o.setLock(true)
        o.setColorTint({0.22, 0.5, 0.56})
        o.setRotation({0, seat.tableSideZ < 0 and 180 or 0, 0})
        if o.clearButtons ~= nil then o.clearButtons() end
        o.createButton({
            click_function = "BridgePressPass",
            function_owner = Global,
            label = "PASS /\nCONTINUE",
            position = {0, 0.6, 0},
            width = 1000,
            height = 520,
            font_size = 160,
            color = {0.22, 0.5, 0.56, 1.0},
            font_color = {1, 1, 1, 1},
            tooltip = "Pass exactly this Forge priority decision"
        })
    end)
end

function BridgeEnsureEndTurnButton(seatId)
    if BRIDGE_PHYSICAL_PRIORITY_CONTROLS_ENABLED ~= true then return end
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then return end
    local targetPosition = {-11.0, 1.6, seat.tableSideZ * 4.2}
    local existing = BridgeGetLiveObjectByGuid(BridgeState.endTurnObjectGuidBySeatId[seatId])
    if existing == nil then
        existing = BridgeFindNamedObject("Forge End Turn")
        if existing ~= nil then
            BridgeState.endTurnObjectGuidBySeatId[seatId] = existing.getGUID()
        end
    end
    if existing ~= nil then
        BridgeConfigureEndTurnObject(existing, seat)
        BridgeSafeObjectCall(existing, function(o) o.setPositionSmooth(targetPosition, false, true) end)
        return
    end
    spawnObject({
        type = "BlockSquare",
        position = targetPosition,
        scale = {3.2, 0.35, 1.6},
        callback_function = function(object)
            BridgeConfigureEndTurnObject(object, seat)
            if BridgeObjectIsUsable(object) then
                BridgeState.endTurnObjectGuidBySeatId[seatId] = object.getGUID()
            end
        end
    })
end

function BridgeEnsurePassButton(seatId)
    if BRIDGE_PHYSICAL_PRIORITY_CONTROLS_ENABLED ~= true then return end
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then return end
    local targetPosition = {-6.8, 1.6, seat.tableSideZ * 4.2}
    local existing = BridgeGetLiveObjectByGuid(BridgeState.passObjectGuidBySeatId[seatId])
    if existing == nil then
        existing = BridgeFindNamedObject("Forge Pass Priority")
        if existing ~= nil then
            BridgeState.passObjectGuidBySeatId[seatId] = existing.getGUID()
        end
    end
    if existing ~= nil then
        BridgeConfigurePassObject(existing, seat)
        BridgeSafeObjectCall(existing, function(o) o.setPositionSmooth(targetPosition, false, true) end)
        return
    end
    spawnObject({
        type = "BlockSquare",
        position = targetPosition,
        scale = {2.7, 0.35, 1.6},
        callback_function = function(object)
            BridgeConfigurePassObject(object, seat)
            if BridgeObjectIsUsable(object) then
                BridgeState.passObjectGuidBySeatId[seatId] = object.getGUID()
            end
        end
    })
end

-- Flight-recorder wrappers keep the hot paths unchanged. They append a few
-- scalar values to the bounded in-memory ring and never perform I/O.
local BridgeAcceptDecisionFlightRecorderBase = BridgeAcceptDecision
function BridgeAcceptDecision(decision, origin, expectedSessionId, presentationGeneration)
    local token = BridgePerformanceBegin("decision_accept_begin")
    BridgeAcceptDecisionFlightRecorderBase(decision, origin, expectedSessionId, presentationGeneration)
    BridgePerformanceEnd(token, "decision_accept_end")
end

local BridgeRenderDecisionFlightRecorderBase = BridgeRenderDecision
function BridgeRenderDecision(decision, force)
    local token = BridgePerformanceBegin("decision_render_begin")
    local key = BridgeDecisionPresentationKey(decision)
    local skipped = force ~= true and key == BridgeState.renderedDecisionPresentationKey
        and BridgeState.renderedDecisionPhysicalGeneration == (BridgeState.currentPhysicalPresentationGeneration or 0)
    if skipped then BridgePerformanceTrace("decision_render_skipped") end
    local candidateToken = BridgePerformanceBegin("candidate_collection_begin")
    local matchingToken = BridgePerformanceBegin("action_matching_begin")
    BridgeRenderDecisionFlightRecorderBase(decision, force)
    BridgePerformanceRecordTtsActionRepresentation()
    BridgePerformanceEnd(matchingToken, "action_matching_end", "actionMatching")
    BridgePerformanceEnd(candidateToken, "candidate_collection_end", "candidateCollection")
    BridgePerformanceEnd(token, "decision_render_end", "render")
end

local BridgeClearHighlightsFlightRecorderBase = BridgeClearHighlights
function BridgeClearHighlights()
    local token = BridgePerformanceBegin("clear_highlights_begin")
    BridgeClearHighlightsFlightRecorderBase()
    BridgePerformanceEnd(token, "clear_highlights_end", "clearHighlights")
end

local BridgeRenderPreparedFlightRecorderBase = BridgeRenderPreparedSpellPresentations
function BridgeRenderPreparedSpellPresentations(decision)
    local token = BridgePerformanceBegin("prepared_presentation_begin")
    BridgeRenderPreparedFlightRecorderBase(decision)
    BridgePerformanceEnd(token, "prepared_presentation_end", "preparedPresentation")
end

local BridgeApplyEventFlightRecorderBase = BridgeApplyAuthoritativeEvent
function BridgeApplyAuthoritativeEvent(event)
    local token = BridgePerformanceBegin("authoritative_event_begin", event and event.sequence)
    local applied, delay, errorMessage = BridgeApplyEventFlightRecorderBase(event)
    BridgePerformanceEnd(token, "authoritative_event_end", nil, event and event.sequence)
    return applied, delay, errorMessage
end

local BridgeSnapshotReconcileFlightRecorderBase = BridgeApplySafeSnapshotReconcile
function BridgeApplySafeSnapshotReconcile(snapshot, reason)
    local totalToken = BridgePerformanceBegin("snapshot_reconcile.total", snapshot and snapshot.eventCursor)
    local token = BridgePerformanceBegin("snapshot_reconcile_begin", snapshot and snapshot.eventCursor)
    BridgeSnapshotReconcileFlightRecorderBase(snapshot, reason)
    BridgePerformanceEnd(token, "snapshot_reconcile_end", "snapshotReconcile")
    BridgePerformanceEnd(totalToken, "snapshot_reconcile.total.end", "snapshotReconcile")
end

local BridgeMoveToBattlefieldFlightRecorderBase = BridgeMoveToBattlefield
function BridgeMoveToBattlefield(event, object, row, countAsNewPlacement)
    local token = BridgePerformanceBegin("physical_move_begin", event and event.sequence)
    local moved, errorMessage = BridgeMoveToBattlefieldFlightRecorderBase(event, object, row, countAsNewPlacement)
    BridgePerformanceEnd(token, "physical_move_end", nil, event and event.sequence)
    return moved, errorMessage
end

local BridgeCollectSeatAssetsFlightRecorderBase = BridgeCollectSeatAssets
function BridgeCollectSeatAssets(seatId, seatSnapshot, callback)
    local token = BridgePerformanceBegin("candidate_collection_begin")
    return BridgeCollectSeatAssetsFlightRecorderBase(seatId, seatSnapshot, function(ok, assets, errorMessage)
        BridgePerformanceEnd(token, "candidate_collection_end", "candidateCollection", assets and #assets or 0)
        callback(ok, assets, errorMessage)
    end)
end

local BridgeUiFlushFlightRecorderBase = BridgeUiFlush
function BridgeUiFlush()
    local token = BridgePerformanceBegin("ui_flush_begin")
    BridgeUiFlushFlightRecorderBase()
    BridgePerformanceEnd(token, "ui_flush_end", "uiFlush")
end
-- END GENERATED SOURCE: 50-presentation-session.lua
