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
        eventPollScheduled = BridgeState.eventPollScheduled == true,
        eventPollGeneration = BridgeState.eventPollGeneration,
        eventSessionGeneration = BridgeState.eventSessionGeneration,
        decisionPollInFlight = BridgeState.decisionPollInFlight == true,
        decisionPollScheduled = BridgeState.decisionPollScheduled == true,
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
        physicalTransactionGeneration = BridgeState.physicalTransactionGeneration,
        eventDrainBlockReason = BridgeEventDrainBlockReason(),
        resyncInFlight = BridgeState.resyncInFlight == true,
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
    if snapshot == nil or string.find(tostring(origin or ""), "readiness", 1, true) == nil then return end
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
    if same and progress.count >= 3 and progress.lastLoggedCount < 3 then
        progress.lastLoggedCount = progress.count
        BridgeLog(string.format(
            "[Bridge] RESYNC_NO_PROGRESS origin=%s session=%s forgeSequence=%s eventCursor=%s previousForgeSequence=%s previousEventCursor=%s count=%s lastReceived=%s lastApplied=%s pendingDecision=%s pendingDecisionCursor=%s",
            tostring(origin), tostring(sessionId), tostring(forgeSequence), tostring(eventCursor),
            tostring(previousForgeSequence), tostring(previousEventCursor), tostring(progress.count),
            tostring(BridgeState.lastReceivedEventSequence), tostring(BridgeState.lastAppliedEventSequence),
            tostring(BridgeState.pendingDecision and BridgeState.pendingDecision.decisionId or nil),
            tostring(BridgeState.pendingDecision and BridgeState.pendingDecision.eventCursor or nil)))
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
    eventPolling = false,
    eventPollGeneration = 0,
    eventRequestInFlight = false,
    eventPollScheduled = false,
    decisionPollGeneration = 0,
    decisionPresentationGeneration = 0,
    decisionPollInFlight = false,
    decisionPollScheduled = false,
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
    battlefieldCounts = {},
    graveyardCounts = {},
    currentTurnSeatId = nil,
    prioritySeatId = nil,
    stackSummary = {},
    -- HUD YIELD can be armed while the AI is acting and no human decision is
    -- currently visible.  Keep that policy scoped to the authoritative turn
    -- and active seat so it cannot leak into a later turn.
    yieldPolicyTurnNumber = nil,
    yieldPolicyActiveSeatId = nil,
    yieldPolicySessionId = nil,
    yieldPolicyOwnTurn = false,
    decisionLifecycle = {},
    diagnosticCaptureLifecycle = {},
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
    doctorInitializedUi = false,
    doctorRetryAttempt = 0,
    transitionExpectedUntil = 0,
    latencyProbe = nil,
    sessionRecoveryInFlight = false,
    resyncToken = 0,
    resyncStartedAt = nil,
    resyncOrigin = nil,
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
    if BridgeIsPresentationOnlyObject(guid) then
        BridgeLog("[Bridge] refusing Forge mapping for presentation object " .. tostring(guid))
        return false
    end
    local object = BridgeGetLiveObjectByGuid ~= nil and BridgeGetLiveObjectByGuid(guid) or nil
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
