BRIDGE_BASE_URL = "http://127.0.0.1:43110"
BRIDGE_STACK_POSITION = {x = -5.5, y = 1.6, z = 0}
BRIDGE_MANA_COUNTER_SOURCES = {
    W = "cd8bb6", U = "4783af", B = "1c4a59",
    R = "220d2f", G = "cdbccc", C = "aeeb11"
}
BRIDGE_MANA_COLORS = {"W", "U", "B", "R", "G", "C"}

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
        manaBankOffset = {x = -3.8, y = 0.45, z = -0.55},
        faceUpRotation = {x = 0, y = 180, z = 0},
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
        manaBankOffset = {x = -3.8, y = 0.45, z = 0.55},
        faceUpRotation = {x = 0, y = 0, z = 0},
        battlefieldAnchors = {
            land = {x = 6.5, y = 2.0, z = 11.5},
            creature = {x = 7.0, y = 2.0, z = 3.5}
        }
    }
}

BridgeState = {
    lastDecision = nil,
    actionByGuid = {},
    highlightedGuids = {},
    targetButtonIndexByGuid = {},
    endTurnObjectGuidBySeatId = {},
    passObjectGuidBySeatId = {},
    setupObjectGuidByKind = {},
    statusObjectGuid = nil,
    statusHeadline = "CLIENT LOADED",
    statusDetail = "Checking companion...",
    turnCounterObjectGuidByKind = {},
    turnCountsBySeatId = {},
    tableTurnCount = 0,
    turnCounterSessionId = nil,
    resetConfirmationArmed = false,
    selectedActionIds = {},
    selectedGuidByActionId = {},
    selectionDecisionId = nil,
    selectionControlGuids = {},
    attackOriginByGuid = {},
    attackLaneGuidBySeatId = {},
    manaCounterGuidBySeatId = {},
    submitting = false,
    pendingIntent = nil,
    eventSessionId = nil,
    lastReceivedEventSequence = 0,
    lastAppliedEventSequence = 0,
    eventPolling = false,
    eventPollGeneration = 0,
    eventRequestInFlight = false,
    eventPollScheduled = false,
    eventRetryCount = 0,
    skipExistingEventsOnAttach = false,
    eventQueue = {},
    animationRunning = false,
    physicalByInstanceId = {},
    cardNameByInstanceId = {},
    physicalSeatByGuid = {},
    physicalZoneByGuid = {},
    battlefieldCounts = {},
    currentTurnSeatId = nil,
    yieldSeatId = nil,
    counterStateByInstanceId = {},
    keywordStateByInstanceId = {},
    untappedRotationByGuid = {},
    pendingCastBySeatId = {},
    snapshotForgeSequence = 0,
    snapshotReconcileInFlight = false,
    snapshotReconcilePending = false,
    bootstrapping = false,
    setupBusy = false,
}

BridgeHttp = {}

function BridgeHttp.requestJson(method, path, payload, callback)
    local url = BRIDGE_BASE_URL .. path

    if method == "GET" then
        WebRequest.get(url, function(request)
            BridgeHttp.handleResponse(request, callback)
        end)
        return
    end

    local body = payload and JSON.encode(payload) or ""
    local headers = {
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/json"
    }

    WebRequest.custom(url, method, true, body, headers, function(request)
        BridgeHttp.handleResponse(request, callback)
    end)
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
    BridgeOnLoad()
end

function onUpdate()
end

-- Forge owns draws. The legacy button remains present, but cannot mutate the
-- physical library independently of an authoritative Forge transition.
function drawSwap(me, clickerColor)
    BridgeShowError("manual Draw is disabled while Forge is authoritative; wait for Forge's draw event")
end

function BridgeGetHealth(callback)
    BridgeHttp.requestJson("GET", "/health", nil, callback)
end

function BridgeStartSession(callback)
    BridgeHttp.requestJson("POST", "/api/v1/session/start", nil, callback)
end

function BridgeResetSessionRequest(callback)
    BridgeHttp.requestJson("POST", "/api/v1/session/reset", nil, callback)
end

function BridgeGetDecision(callback)
    BridgeHttp.requestJson("GET", "/api/v1/decision", nil, function(ok, body, err, request)
        if ok and body ~= nil then
            BridgeState.lastDecision = body
        else
            BridgeState.lastDecision = nil
            BridgeClearHighlights()
            BridgeResetSelectionState()
        end

        callback(ok, body, err, request)
    end)
end

function BridgeSubmitChoice(decisionId, actionId)
    if BridgeState.submitting then
        print("[Bridge] choice submission already in progress.")
        return
    end

    if decisionId == nil or decisionId == "" then
        if BridgeState.lastDecision == nil then
            print("[Bridge] No cached decision. Run BridgeSmokeTest() first.")
            return
        end

        decisionId = BridgeState.lastDecision.decisionId
    end

    if actionId == nil or actionId == "" then
        print("[Bridge] actionId is required.")
        return
    end

    local payload = {
        decisionId = decisionId,
        actionId = actionId
    }

    BridgeState.submitting = true
    BridgeHttp.requestJson("POST", "/api/v1/choice", payload, function(ok, body, err)
        BridgeState.submitting = false
        if not ok then
            BridgeClearHighlights()
            BridgeRollbackPendingIntent()
            BridgeResetSelectionState()
            BridgeShowError("choice rejected: " .. tostring(err))
            if body ~= nil and body.errorCode ~= nil then
                BridgeShowError("errorCode=" .. tostring(body.errorCode) .. " message=" .. tostring(body.message))
            end
            if BridgeState.lastDecision ~= nil then
                BridgeRenderDecision(BridgeState.lastDecision)
            end
            return
        end

        print("[Bridge] choice accepted.")

        if body ~= nil and body.committedEvent ~= nil then
            print("[Bridge] committed: " .. tostring(body.committedEvent.summary))
        end

        if body ~= nil and body.currentDecision ~= nil then
            BridgeState.lastDecision = body.currentDecision
            printDecision(body.currentDecision)
        else
            BridgeState.lastDecision = nil
            BridgeClearHighlights()
            print("[Bridge] no pending decision.")
        end

        BridgeCommitPendingIntent()
    end)
end

function BridgeChoose(actionId)
    BridgeSubmitChoice(nil, actionId)
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

function BridgeZoneIsPublicForReconcile(zoneName)
    return zoneName == "battlefield"
        or zoneName == "graveyard"
        or zoneName == "stack"
        or zoneName == "exile"
end

function BridgeShouldReconcileAfterEvent(event)
    return event.kind == "spell_resolved"
        or event.kind == "land_played"
        or event.kind == "card_moved"
        or event.kind == "mana_ability_used"
        or event.kind == "tap_changed"
        or event.kind == "counter_changed"
end

function BridgeCanDeferStructuredMoveToSnapshot(event)
    local destinationZone = string.lower(tostring(event.destinationZone or ""))
    return event.kind == "card_moved" and BridgeZoneIsPublicForReconcile(destinationZone)
end

function BridgeScheduleSnapshotReconcile(reason)
    if BridgeState.eventSessionId == nil then return end
    if BridgeState.snapshotReconcileInFlight then
        BridgeState.snapshotReconcilePending = true
        return
    end
    BridgeState.snapshotReconcileInFlight = true
    BridgeGetEmbodimentSnapshot(function(ok, snapshot, err)
        BridgeState.snapshotReconcileInFlight = false
        if ok and snapshot ~= nil and snapshot.sessionId == BridgeState.eventSessionId then
            local movedCount = 0
            for _, seatSnapshot in ipairs(snapshot.seats or {}) do
                for _, zone in ipairs(seatSnapshot.zones or {}) do
                    local zoneName = string.lower(tostring(zone.name or ""))
                    if BridgeZoneIsPublicForReconcile(zoneName) then
                        for _, card in ipairs(zone.cards or {}) do
                            local evt = {
                                seatId = seatSnapshot.seatId,
                                cardInstanceId = card.cardInstanceId,
                                cardName = card.cardName,
                                sourceZone = nil,
                                destinationZone = zoneName,
                                faceDown = card.faceDown
                            }
                            local mappedGuid = BridgeState.physicalByInstanceId[card.cardInstanceId]
                            local mappedObject = mappedGuid and getObjectFromGUID(mappedGuid) or nil
                            local mappedZone = mappedGuid and BridgeState.physicalZoneByGuid[mappedGuid] or nil
                            local mappedNeedsFix = mappedObject == nil
                                or mappedObject.tag ~= "Card"
                                or mappedZone ~= zoneName
                            if mappedNeedsFix then
                                local moved, moveError = BridgeApplyStructuredCardMove(evt)
                                if moved then
                                    movedCount = movedCount + 1
                                else
                                    print("[Bridge] snapshot reconcile skipped a move: " .. tostring(moveError))
                                end
                            end

                            local guid = BridgeState.physicalByInstanceId[card.cardInstanceId]
                            local object = guid and getObjectFromGUID(guid) or nil
                            if object ~= nil and object.tag == "Card" and zoneName == "battlefield" then
                                BridgeSetPhysicalTapped(object, card.tapped == true)
                            end
                        end
                    end
                end
            end
            BridgeState.snapshotForgeSequence = snapshot.forgeSequence or BridgeState.snapshotForgeSequence
            if movedCount > 0 then
                print(string.format("[Bridge] snapshot reconcile (%s): corrected %d public card location(s)", tostring(reason), movedCount))
            end
        elseif not ok then
            print("[Bridge] snapshot reconcile failed: " .. tostring(err))
        elseif snapshot ~= nil then
            print("[Bridge] snapshot reconcile skipped due to session mismatch")
        end

        if BridgeState.snapshotReconcilePending then
            BridgeState.snapshotReconcilePending = false
            BridgeScheduleSnapshotReconcile("pending")
        end
    end)
end

function BridgeOnLoad()
    print("[Bridge] ForgeBot integration loaded.")
    BridgeSetStatus("CLIENT LOADED", "Checking companion...")
    Wait.frames(function()
        BridgeEnsureSetupControls()
        BridgeEnsureTurnCounters()
        BridgeEnsureStatusPanel()
        BridgeShowPreparationReadiness()
    end, 30)
end

function BridgeEnsureStatusPanel()
    local existing = BridgeState.statusObjectGuid and getObjectFromGUID(BridgeState.statusObjectGuid) or nil
    if existing ~= nil then BridgeRefreshStatusPanel(); return end
    for _, object in ipairs(getAllObjects()) do
        if object.getName() == "Forge Status" then
            BridgeState.statusObjectGuid = object.getGUID()
            BridgeRefreshStatusPanel()
            return
        end
    end
    spawnObject({
        type = "BlockSquare",
        position = {-1.0, 1.6, 0},
        scale = {4.8, 0.3, 1.25},
        callback_function = function(object)
            object.setName("Forge Status")
            object.setLock(true)
            object.setColorTint({0.12, 0.12, 0.16})
            object.createButton({
                click_function = "BridgeIgnoreStatusClick",
                function_owner = Global,
                label = "",
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
end

function BridgeTurnLabel()
    return "TURN " .. tostring(BridgeState.tableTurnCount or 0)
end

function BridgeCurrentSeatLabel(seatId)
    local seat = BRIDGE_SEATS[seatId]
    return tostring((seat and seat.ttsColor) or seatId or "Unknown")
end

function BridgeRefreshStatusPanel()
    local object = BridgeState.statusObjectGuid and getObjectFromGUID(BridgeState.statusObjectGuid) or nil
    if object ~= nil then
        pcall(function()
            object.editButton({index = 0, label = tostring(BridgeState.statusHeadline) .. "\n" .. tostring(BridgeState.statusDetail)})
        end)
    end
end

function BridgeShowPreparationReadiness()
    BridgeGetHealth(function(ok, body, err)
        if not ok then
            BridgeSetStatus("ERROR", "Companion unavailable")
            print("[Bridge] preparation: companion unavailable: " .. tostring(err))
            return
        end
        local humanDeck = BridgeFindLibraryDeckForSeat("forge-player-1") ~= nil
        local aiDeck = BridgeFindLibraryDeckForSeat("forge-player-2") ~= nil
        print(string.format(
            "[Bridge] preparation: Companion=READY Human deck=%s AI deck=%s active=%s",
            humanDeck and "FOUND" or "MISSING", aiDeck and "FOUND" or "MISSING",
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
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then return nil end
    for _, object in ipairs(getAllObjects()) do
        if object.tag == "Deck" and BridgeObjectIsOnSeatSide(object, seat) then return object end
    end
    return nil
end

function BridgeEnsureSetupControl(kind, label, x, color, clickFunction, tooltip)
    local existingGuid = BridgeState.setupObjectGuidByKind[kind]
    if existingGuid ~= nil and getObjectFromGUID(existingGuid) ~= nil then return end
    for _, object in ipairs(getAllObjects()) do
        if object.getName() == "Forge Setup " .. kind then
            BridgeState.setupObjectGuidByKind[kind] = object.getGUID()
            return
        end
    end
    spawnObject({
        type = "BlockSquare",
        position = {x, 1.6, -15.0},
        scale = {2.5, 0.35, 1.25},
        callback_function = function(object)
            object.setName("Forge Setup " .. kind)
            object.setLock(true)
            object.setColorTint(color)
            object.setRotation({0, 180, 0})
            object.createButton({
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
    local labels = busy and {Start = "LOADING...", Resume = "LOADING...", Reset = "WAIT..."}
        or {Start = "START\nMATCH", Resume = "RESUME", Reset = "NEW MATCH\n(2 CLICKS)"}
    for kind, label in pairs(labels) do
        local guid = BridgeState.setupObjectGuidByKind[kind]
        local object = guid and getObjectFromGUID(guid) or nil
        if object ~= nil then
            pcall(function() object.editButton({index = 0, label = label}) end)
        end
    end
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
    if existingGuid ~= nil and getObjectFromGUID(existingGuid) ~= nil then return end
    local objectName = "Forge Turn Counter " .. kind
    for _, object in ipairs(getAllObjects()) do
        if object.getName() == objectName then
            BridgeState.turnCounterObjectGuidByKind[kind] = object.getGUID()
            return
        end
    end
    spawnObject({
        type = "BlockSquare",
        position = position,
        scale = {1.7, 0.28, 0.9},
        callback_function = function(object)
            object.setName(objectName)
            object.setLock(true)
            object.setColorTint(color)
            object.setRotation({0, 180, 0})
            object.createButton({
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
    for kind, label in pairs(labels) do
        local guid = BridgeState.turnCounterObjectGuidByKind[kind]
        local object = guid and getObjectFromGUID(guid) or nil
        if object ~= nil then pcall(function() object.editButton({index = 0, label = label}) end) end
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
    if BridgeState.setupBusy then
        BridgeShowError("Forge is still initializing; wait for the loading controls to finish")
        return
    end
    BridgeSetSetupBusy(true, "Forge match is loading; START and RESUME are temporarily disabled.")
    BridgeGetHealth(function(ok, body, err)
        if not ok then BridgeSetSetupBusy(false); BridgeShowError("cannot start: companion unavailable: " .. tostring(err)); return end
        local active = body.sessionId ~= nil and body.sessionId ~= "session-not-started"
            and body.adapterState ~= "not_started" and body.adapterState ~= "failed"
        if active then BridgeSetSetupBusy(false); BridgeShowError("a Forge match already exists; use RESUME or explicitly choose NEW MATCH"); return end
        if BridgeFindLibraryDeckForSeat("forge-player-1") == nil or BridgeFindLibraryDeckForSeat("forge-player-2") == nil then
            BridgeSetSetupBusy(false); BridgeShowError("both physical library decks must be present before START")
            return
        end
        BridgeStartSessionIfNone(function() BridgeSetSetupBusy(false) end)
    end)
end

function BridgePressResume(object, playerColor, altClick)
    if BridgeState.setupBusy then
        BridgeShowError("Forge is still initializing; wait for the loading controls to finish")
        return
    end
    BridgeSetSetupBusy(true, "Checking the active Forge match; RESUME is temporarily disabled.")
    BridgeAttachToActiveSession(function() BridgeSetSetupBusy(false) end)
end

function BridgePressNewMatch(object, playerColor, altClick)
    if BridgeState.setupBusy then
        BridgeShowError("Forge is still initializing; wait for the loading controls to finish")
        return
    end
    if not BridgeState.resetConfirmationArmed then
        BridgeState.resetConfirmationArmed = true
        broadcastToAll("[Bridge] NEW MATCH is destructive. Click it again within 10 seconds to confirm.", {1.0, 0.55, 0.1})
        Wait.time(function() BridgeState.resetConfirmationArmed = false end, 10)
        return
    end
    BridgeState.resetConfirmationArmed = false
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

        print("[Bridge] health ok. adapter=" .. tostring(body.adapter) .. " state=" .. tostring(body.adapterState))
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

        BridgeFetchDecisionAfterAttach()
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
                print("[Bridge] Forge is initializing... (" .. tostring(attempt * 2) .. "s)")
            end
            Wait.time(function() BridgeWaitForForgeInitialization(attempt + 1, done) end, 2)
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
    BridgeGetDecision(function(decisionOk, decisionBody, decisionErr)
        if decisionOk and decisionBody ~= nil then
            printDecision(decisionBody)
            return
        end

        print("[Bridge] no active decision available (" .. tostring(decisionErr) .. "). This script will not restart Forge automatically.")
        print("[Bridge] When Forge reaches a decision, run BridgeRefreshDecision().")
    end)
end

function BridgeRefreshDecision()
    BridgeGetDecision(function(ok, body, err)
        if ok and body ~= nil then
            printDecision(body)
        else
            BridgeShowError("decision fetch failed: " .. tostring(err))
        end
    end)
end

function BridgeStartSessionIfNone(done)
    BridgeClearHighlights()
    BridgeState.lastDecision = nil

    BridgeStartSession(function(ok, body, err)
        if not ok then
            if done then done() end
            BridgeShowError("session start failed: " .. tostring(err))
            return
        end

        print("[Bridge] started or attached session: " .. tostring(body and body.sessionId))
        -- The start route may attach to a match that already exists. Do not replay
        -- its historical physical events; an explicit reset is the new-match path.
        BridgeBootstrapWhenAvailable(body.sessionId, 1, function(bootstrapOk, bootstrapError)
            if not bootstrapOk then if done then done() end; BridgeStopOnDesync(bootstrapError); return end
            BridgeStartEventPolling(body.sessionId, true)
            if body ~= nil and body.currentDecision ~= nil then printDecision(body.currentDecision)
            else BridgeRefreshDecision() end
            if done then done() end
        end)
    end)
end

function BridgeResetSession()
    BridgeStopEventPolling()
    BridgeClearHighlights()
    BridgeState.lastDecision = nil

    BridgeResetSessionRequest(function(ok, body, err)
        if not ok then
            BridgeSetSetupBusy(false)
            BridgeShowError("explicit session reset failed: " .. tostring(err))
            return
        end

        print("[Bridge] active match explicitly replaced: " .. tostring(body and body.sessionId))
        BridgeBootstrapWhenAvailable(body.sessionId, 1, function(bootstrapOk, bootstrapError)
            if not bootstrapOk then BridgeSetSetupBusy(false); BridgeStopOnDesync(bootstrapError); return end
            -- The snapshot is authoritative through this point, so opening
            -- mutation records are acknowledged instead of replayed.
            BridgeStartEventPolling(body.sessionId, true)
            if body ~= nil and body.currentDecision ~= nil then printDecision(body.currentDecision)
            else BridgeRefreshDecision() end
            BridgeSetSetupBusy(false)
        end)
    end)
end

function BridgeSmokeTest()
    BridgeAttachToActiveSession()
end

function printDecision(decision)
    if decision == nil then
        print("[Bridge] decision payload missing.")
        return
    end

    local eventCursor = tonumber(decision.eventCursor or 0) or 0
    if eventCursor > 0 and eventCursor < (BridgeState.lastAppliedEventSequence or 0) then
        print(string.format(
            "[Bridge] ignoring stale decision %s (cursor=%s, applied=%s)",
            tostring(decision.decisionId), tostring(eventCursor), tostring(BridgeState.lastAppliedEventSequence)))
        return
    end

    if decision.turnNumber ~= nil and tonumber(decision.turnNumber) ~= nil and tonumber(decision.turnNumber) > 0 then
        BridgeState.tableTurnCount = tonumber(decision.turnNumber)
        BridgeRefreshTurnCounterLabels()
    end
    if decision.activeSeatId ~= nil then
        BridgeState.currentTurnSeatId = decision.activeSeatId
    end
    if decision.phaseName ~= nil and decision.phaseName ~= "" then
        BridgeState.currentPhase = decision.phaseName
    end

    BridgeState.lastDecision = decision
    local seat = BRIDGE_SEATS[decision.seatId]
    local actor = seat and seat.ttsColor or decision.seatId
    if decision.kind == "attacker_selection" then
        BridgeSetStatus("DECLARE ATTACKERS", "Drag/select highlighted creatures into attack row\nDONE ATTACKING")
    elseif decision.kind == "blocker_selection" then
        BridgeSetStatus("DECLARE BLOCKERS", "Drag/select highlighted creatures into block row\nDONE BLOCKING")
    elseif decision.kind == "target_selection" then
        BridgeSetStatus("CHOOSE TARGET", BridgeTurnLabel() .. " - " .. tostring(actor) .. " priority")
    else
        BridgeSetStatus("YOUR PRIORITY", BridgeTurnLabel() .. " - " .. tostring(actor) .. " - " .. tostring(BridgeState.currentPhase or "Forge decision"))
    end
    BridgeRenderDecision(decision)

    print("[Bridge] decision " .. tostring(decision.decisionId) .. " kind=" .. tostring(decision.kind))

    if decision.actions == nil then
        print("[Bridge] no actions.")
        return
    end

    for index, action in ipairs(decision.actions) do
        local followup = action.requiresFollowup and "yes" or "no"
        print(string.format("[Bridge]   %d. %s (%s) id=%s followup=%s", index, tostring(action.displayName), tostring(action.type), tostring(action.actionId), followup))
    end

    print("[Bridge] use BridgeChoose('<actionId>') to submit an action.")
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
    for _, guid in ipairs(BridgeState.highlightedGuids) do
        local object = getObjectFromGUID(guid)
        if object ~= nil then
            object.highlightOff()
        end
    end

    for guid, buttonIndex in pairs(BridgeState.targetButtonIndexByGuid) do
        local object = getObjectFromGUID(guid)
        if object ~= nil then object.removeButton(buttonIndex) end
    end

    BridgeState.highlightedGuids = {}
    BridgeState.actionByGuid = {}
    BridgeState.targetButtonIndexByGuid = {}
end

function BridgeEnsureContextualCompletionControl(decision)
    if decision == nil or (decision.kind ~= "attacker_selection" and decision.kind ~= "blocker_selection") then return end
    if #(BridgeState.selectionControlGuids or {}) > 0 then return end
    local completionAction = nil
    for _, action in ipairs(decision.actions or {}) do
        if action.type == "finish_attacking" or action.type == "finish_blocking" or action.type == "choose_none" then
            completionAction = action
            break
        end
    end
    if completionAction == nil then return end
    local seat = BRIDGE_SEATS[decision.seatId]
    if seat == nil then return end
    local isAttacking = completionAction.type == "finish_attacking"
    local label = isAttacking and "DONE ATTACKING\n(NO MORE ATTACKERS)" or "DONE BLOCKING\n(NO MORE BLOCKERS)"
    spawnObject({
        type = "BlockSquare",
        position = {-2.0, 1.6, seat.tableSideZ * 10.0},
        scale = {4.0, 0.35, 1.45},
        callback_function = function(object)
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
    if object == nil or BridgeState.submitting then return end
    local decision = BridgeState.lastDecision
    local decisionId = object.getVar("bridgeDecisionId")
    local actionId = object.getVar("bridgeActionId")
    if decision == nil or decision.decisionId ~= decisionId then
        BridgeShowError("combat completion control is stale")
        BridgeResetSelectionState()
        return
    end
    BridgeClaimHumanTtsColor(decision.seatId, playerColor)
    BridgeClearHighlights()
    BridgeResetSelectionState()
    BridgeSubmitChoice(decisionId, actionId)
end

function BridgeInstallTargetButton(object, targetSeatId)
    local nextIndex = 0
    for _, button in ipairs(object.getButtons() or {}) do
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

function BridgeEnsureEndTurnButton(seatId)
    local existingGuid = BridgeState.endTurnObjectGuidBySeatId[seatId]
    if existingGuid ~= nil and getObjectFromGUID(existingGuid) ~= nil then return end
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then return end
    spawnObject({
        type = "BlockSquare",
        position = {-4.5, 1.6, seat.tableSideZ * 7.0},
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
    if existingGuid ~= nil and getObjectFromGUID(existingGuid) ~= nil then return end
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then return end
    spawnObject({
        type = "BlockSquare",
        position = {0.5, 1.6, seat.tableSideZ * 7.0},
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
    if BridgeState.submitting then return end
    local decision = BridgeState.lastDecision
    if decision == nil or decision.kind ~= "main_priority" then
        BridgeShowError("Pass is unavailable without a Forge main-priority decision")
        return
    end
    BridgeClaimHumanTtsColor(decision.seatId, playerColor)
    BridgeState.yieldSeatId = nil
    for _, action in ipairs(decision.actions or {}) do
        if action.type == "pass_priority" then
            BridgeClearHighlights()
            BridgeSubmitChoice(decision.decisionId, action.actionId)
            return
        end
    end
    BridgeShowError("Forge did not offer a one-shot pass action")
end

function BridgePressEndTurn(object, playerColor, altClick)
    if BridgeState.submitting then return end
    local decision = BridgeState.lastDecision
    if decision == nil or decision.kind ~= "main_priority" then
        BridgeShowError("End Turn is unavailable without a Forge main-priority decision")
        return
    end
    BridgeClaimHumanTtsColor(decision.seatId, playerColor)
    for _, action in ipairs(decision.actions or {}) do
        if action.type == "pass_priority" then
            BridgeState.yieldSeatId = decision.seatId
            BridgeClearHighlights()
            BridgeSubmitChoice(decision.decisionId, action.actionId)
            return
        end
    end
    BridgeShowError("Forge did not offer a pass/yield action")
end

function BridgeClaimHumanTtsColor(seatId, playerColor)
    local seat = BRIDGE_SEATS[seatId]
    if seat ~= nil and seat.animateAuthoritativeEvents == false and playerColor ~= nil then
        if seat.ttsColor ~= playerColor then
            print("[Bridge] bound human seat " .. tostring(seatId) .. " to TTS color " .. tostring(playerColor))
        end
        seat.ttsColor = playerColor
    end
end

function BridgeSelectPlayerTarget(object, playerColor, altClick)
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
    BridgeSubmitChoice(decision.decisionId, action.actionId)
end

function BridgeResetSelectionState()
    BridgeState.selectedActionIds = {}
    BridgeState.selectedGuidByActionId = {}
    BridgeState.selectionDecisionId = nil
    for _, guid in ipairs(BridgeState.selectionControlGuids or {}) do
        local object = getObjectFromGUID(guid)
        if object ~= nil then object.destruct() end
    end
    BridgeState.selectionControlGuids = {}
end

function BridgeSelectionCount()
    local count = 0
    for _, selected in pairs(BridgeState.selectedActionIds or {}) do
        if selected then count = count + 1 end
    end
    return count
end

function BridgeEnsureSelectionControls(decision)
    if decision.requiresConfirmation ~= true or #(BridgeState.selectionControlGuids or {}) > 0 then return end
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
    spawnSelectionControl("Forge Confirm Selection", "DONE /\nCONFIRM", 2.0, {0.12, 0.52, 0.24}, "BridgeConfirmSelection")
    spawnSelectionControl("Forge Cancel Selection", "CANCEL /\nUNDO", 7.5, {0.65, 0.2, 0.12}, "BridgeCancelSelection")
end

function BridgeConfirmSelection(object, playerColor, altClick)
    local decision = BridgeState.lastDecision
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
                BridgeSubmitChoice(decision.decisionId, action.actionId)
                return
            end
        end
        BridgeShowError("Forge permits zero selections but supplied no explicit zero-selection action")
        return
    end
    if count > 1 then
        BridgeShowError("this Forge TUI transport cannot atomically submit multiple selections yet")
        return
    end
    for actionId, selected in pairs(BridgeState.selectedActionIds) do
        if selected then
            BridgeResetSelectionState()
            BridgeSubmitChoice(decision.decisionId, actionId)
            return
        end
    end
end

function BridgeCancelSelection(object, playerColor, altClick)
    local decision = BridgeState.lastDecision
    BridgeResetSelectionState()
    if decision ~= nil then BridgeRenderDecision(decision) end
end

function BridgeRenderDecision(decision)
    BridgeClearHighlights()

    if decision == nil or decision.actions == nil then
        BridgeResetSelectionState()
        return
    end

    if BridgeState.selectionDecisionId ~= decision.decisionId then
        BridgeResetSelectionState()
        BridgeState.selectionDecisionId = decision.decisionId
    end
    BridgeEnsureSelectionControls(decision)
    BridgeEnsureContextualCompletionControl(decision)

    if decision.kind == "main_priority" then
        BridgeEnsureEndTurnButton(decision.seatId)
        BridgeEnsurePassButton(decision.seatId)
    end

    if BridgeState.yieldSeatId ~= nil then
        if decision.seatId ~= BridgeState.yieldSeatId or decision.kind ~= "main_priority" then
            BridgeState.yieldSeatId = nil
        else
            for _, action in ipairs(decision.actions) do
                if action.type == "pass_priority" then
                    BridgeSubmitChoice(decision.decisionId, action.actionId)
                    return
                end
            end
        end
    end

    local highlightColor = {0.53, 0.81, 0.98}
    if decision.kind == "target_selection" or decision.kind == "blocker_selection" then
        highlightColor = {1.0, 0.55, 0.0}
    end

    local decisionSeat = BRIDGE_SEATS[decision.seatId]
    local cards = {}
    local candidateGuid = {}
    for _, object in ipairs(getAllObjects()) do
        if object.tag == "Card" then
            local guid = object.getGUID()
            local isCandidate = decision.kind ~= "main_priority"
                or (BridgeState.physicalSeatByGuid[guid] == decision.seatId
                    and BridgeState.physicalZoneByGuid[guid] == "hand"
                    and decisionSeat ~= nil
                    and BridgeObjectIsOnSeatSide(object, decisionSeat))
            if isCandidate then
                table.insert(cards, object)
                candidateGuid[guid] = true
            end
        end
    end

    for _, action in ipairs(decision.actions) do
        if action.targetKind == "player" and action.targetSeatId ~= nil then
            local targetSeat = BRIDGE_SEATS[action.targetSeatId]
            local targetObject = targetSeat and getObjectFromGUID(targetSeat.targetSurfaceGuid) or nil
            if targetObject ~= nil then
                local guid = targetObject.getGUID()
                targetObject.highlightOn({1.0, 0.55, 0.0})
                BridgeState.actionByGuid[guid] = action
                table.insert(BridgeState.highlightedGuids, guid)
                BridgeInstallTargetButton(targetObject, action.targetSeatId)
            else
                BridgeShowError("no physical target surface configured for seat " .. tostring(action.targetSeatId))
            end
        end

        local matches = {}
        local mappedGuid = action.cardInstanceId and BridgeState.physicalByInstanceId[action.cardInstanceId] or nil
        local mappedObject = mappedGuid and getObjectFromGUID(mappedGuid) or nil
        local mappedSeatMatches = mappedObject ~= nil and (decision.kind ~= "main_priority"
            or BridgeState.physicalSeatByGuid[mappedGuid] == decision.seatId)
        local mappedZoneMatches = decision.kind ~= "main_priority" or candidateGuid[mappedGuid] == true
        if mappedSeatMatches and mappedZoneMatches then
            table.insert(matches, mappedObject)
        elseif action.cardInstanceId == nil then
            for _, object in ipairs(cards) do
                if BridgeCardNameMatches(object.getName(), action.cardIdentity) then
                    table.insert(matches, object)
                end
            end
        end

        if action.cardIdentity ~= nil and #matches > 0 then
            if mappedGuid == nil and #matches > 1 then
                print(string.format("[Bridge] duplicate card name '%s': highlighting all %d candidates", tostring(action.cardIdentity), #matches))
            end

            for _, object in ipairs(matches) do
                local guid = object.getGUID()
                local selected = BridgeState.selectedActionIds[action.actionId] == true
                object.highlightOn(selected and {0.2, 1.0, 0.35} or highlightColor)
                BridgeState.actionByGuid[guid] = action
                table.insert(BridgeState.highlightedGuids, guid)
            end
        end
    end
end

function BridgeShowError(message)
    local text = "[Bridge] " .. tostring(message)
    print(text)
    broadcastToAll(text, {1.0, 0.2, 0.2})
end

function onObjectPickUp(playerColor, object)
    if object == nil or BridgeState.submitting then
        return
    end

    local action = BridgeState.actionByGuid[object.getGUID()]
    if action == nil then
        return
    end

    local decision = BridgeState.lastDecision
    if decision == nil then
        BridgeClearHighlights()
        BridgeShowError("highlighted card has no active bridge decision")
        return
    end

    BridgeClaimHumanTtsColor(decision.seatId, playerColor)

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

    if object.tag == "Card" and decision.requiresConfirmation == true then
        local actionId = action.actionId
        local selected = BridgeState.selectedActionIds[actionId] == true
        BridgeState.selectedActionIds[actionId] = not selected
        BridgeState.selectedGuidByActionId[actionId] = selected and nil or object.getGUID()
        object.use_hands = BridgeState.pendingIntent.useHands
        object.setPositionSmooth(BridgeState.pendingIntent.position, false, true)
        object.setRotationSmooth(BridgeState.pendingIntent.rotation, false, true)
        BridgeState.pendingIntent = nil
        Wait.frames(function() BridgeRenderDecision(decision) end, 2)
        return
    end

    -- Player scoreboards and other non-card targets are selection surfaces,
    -- not draggable game pieces, so the grab itself commits the offered target.
    if object.tag ~= "Card" then
        BridgeSubmitChoice(decision.decisionId, action.actionId)
    end
end

function onObjectDrop(playerColor, object)
    local intent = BridgeState.pendingIntent
    if intent == nil or object == nil or object.getGUID() ~= intent.guid or BridgeState.submitting then
        return
    end

    local decision = BridgeState.lastDecision
    if decision == nil or decision.decisionId ~= intent.decisionId then
        BridgeRollbackPendingIntent()
        BridgeShowError("staged intent became stale before drop")
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
            BridgeState.pendingCastBySeatId[intent.seatId] = {
                guid = intent.guid,
                cardIdentity = intent.action.cardIdentity,
                actionId = intent.action.actionId,
                decisionId = intent.decisionId,
            }
        end
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
        if not movedEnough and not droppedInLane then
            print(string.format(
                "[Bridge] combat drop ignored for %s (guid=%s movedSq=%.3f laneHit=%s)",
                tostring(intent.action.type), tostring(intent.guid), dx * dx + dz * dz, tostring(droppedInLane)))
            BridgeRollbackPendingIntent()
            BridgeRenderDecision(decision)
            return
        end
        print(string.format(
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

    BridgeSubmitChoice(intent.decisionId, intent.action.actionId)
end

function BridgeCommitPendingIntent()
    local intent = BridgeState.pendingIntent
    BridgeState.pendingIntent = nil
    if intent == nil then return end

    if intent.action.type == "choose_attacker" or intent.action.type == "choose_blocker" then
        -- Keep the physical preview in its combat lane. Forge's subsequent
        -- authoritative attack/block event will confirm or correct it.
        local object = getObjectFromGUID(intent.guid)
        if object ~= nil then object.use_hands = false end
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
    end
end

function BridgeRollbackPendingIntent()
    local intent = BridgeState.pendingIntent
    BridgeState.pendingIntent = nil
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
end

function BridgeBootstrapCurrentSnapshot(sessionId, callback)
    if BridgeState.bootstrapping then
        callback(false, "an embodiment bootstrap is already in progress")
        return
    end
    -- Establish the event session before populating instance mappings. Event
    -- polling must not clear the authoritative snapshot we just reconciled.
    BridgePrepareEventSession(sessionId, true)
    BridgeState.bootstrapping = true
    BridgeGetEmbodimentSnapshot(function(ok, snapshot, err)
        if not ok or snapshot == nil then
            BridgeState.bootstrapping = false
            callback(false, "authoritative snapshot unavailable: " .. tostring(err))
            return
        end
        if snapshot.sessionId ~= sessionId then
            BridgeState.bootstrapping = false
            callback(false, "snapshot session mismatch")
            return
        end

        BridgeAnnotateSnapshotBattlefieldKinds(snapshot, function(annotated, annotationError)
            if not annotated then
                BridgeState.bootstrapping = false
                callback(false, annotationError)
                return
            end
            BridgeBootstrapSeats(snapshot, 1, function(seatsOk, seatsError)
                BridgeState.bootstrapping = false
                if not seatsOk then callback(false, seatsError); return end
                BridgeState.snapshotForgeSequence = snapshot.forgeSequence or 0
                print(string.format(
                    "[Bridge] authoritative embodiment bootstrap complete: seats=%d forgeSequence=%s (hidden identities redacted)",
                    #(snapshot.seats or {}), tostring(BridgeState.snapshotForgeSequence)))
                callback(true, nil)
            end)
        end)
    end)
end

function BridgeBootstrapWhenAvailable(sessionId, attempt, callback)
    BridgeBootstrapCurrentSnapshot(sessionId, function(ok, err)
        if ok or string.find(tostring(err), "HTTP 404", 1, true) == nil then
            callback(ok, err)
            return
        end
        if attempt >= 30 then
            callback(false, "authoritative snapshot was unavailable after 60 seconds")
            return
        end
        if attempt == 1 or attempt % 5 == 0 then
            print("[Bridge] waiting for Forge's authoritative snapshot...")
        end
        Wait.time(function() BridgeBootstrapWhenAvailable(sessionId, attempt + 1, callback) end, 2)
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

function BridgeTryBootstrapSeatSnapshot(seatSnapshot, attempt, callback)
    BridgeCollectSeatAssets(seatSnapshot.seatId, function(ok, assets, collectError)
        if not ok then callback(false, collectError); return end
        local reconciled, reconcileError = BridgeReconcileSeatSnapshot(seatSnapshot, assets)
        if not reconciled then
            if attempt < 4 then
                local authoritativeCount = 0
                for _, zone in ipairs(seatSnapshot.zones or {}) do
                    authoritativeCount = authoritativeCount + #(zone.cards or {})
                end
                print(string.format(
                    "[Bridge] seat asset inventory not ready: seat=%s attempt=%d physical=%d authoritative=%d; retrying",
                    tostring(seatSnapshot.seatId), attempt, #assets, authoritativeCount))
                Wait.frames(function()
                    BridgeTryBootstrapSeatSnapshot(seatSnapshot, attempt + 1, callback)
                end, 60)
                return
            end
            callback(false, reconcileError)
            return
        end
        BridgeMaterializeSeatSnapshot(seatSnapshot, 1, 1, function(materialized, materializeError)
            if not materialized then callback(false, materializeError); return end
            Wait.frames(function()
                BridgeApplySeatSnapshotVisualState(seatSnapshot)
                callback(true, nil)
            end, 30)
        end)
    end)
end

function BridgeCollectSeatAssets(seatId, callback)
    local seat = BRIDGE_SEATS[seatId]
    local assets = {}
    for _, object in ipairs(getAllObjects()) do
        if (object.tag == "Card" or object.tag == "Deck") and BridgeObjectIsOnSeatSide(object, seat) then
            if object.tag == "Card" then
                table.insert(assets, {
                    guid = object.getGUID(),
                    cardName = object.getName(),
                    object = object
                })
            else
                for _, contained in ipairs(object.getObjects() or {}) do
                    table.insert(assets, {
                        guid = contained.guid,
                        cardName = contained.nickname or contained.name,
                        object = nil
                    })
                end
            end
        end
    end
    callback(true, assets, nil)
end

function BridgeObjectIsOnSeatSide(object, seat)
    local position = object.getPosition()
    if seat.assetMaxAbsX ~= nil and math.abs(position.x) > seat.assetMaxAbsX then
        return false
    end
    if object.tag == "Deck" then
        local libraryZone = getObjectFromGUID(seat.libraryZoneGuid)
        if libraryZone == nil then return false end
        local libraryPosition = libraryZone.getPosition()
        local dx = position.x - libraryPosition.x
        local dz = position.z - libraryPosition.z
        local radius = seat.libraryAssetRadius or 4
        return dx * dx + dz * dz <= radius * radius
    end
    if seat.tableSideZ < 0 then return position.z < -0.25 end
    return position.z > 0.25
end

function BridgeReconcileSeatSnapshot(seatSnapshot, assets)
    local byName = {}
    local mappings = {}
    for _, asset in ipairs(assets) do
        local name = BridgeNormalizeCardName(asset.cardName)
        byName[name] = byName[name] or {}
        table.insert(byName[name], asset)
    end

    local seat = BRIDGE_SEATS[seatSnapshot.seatId]
    for _, zone in ipairs(seatSnapshot.zones or {}) do
        for _, card in ipairs(zone.cards or {}) do
            local normalized = BridgeNormalizeCardName(card.cardName)
            local candidates = byName[normalized] or {}
            if #candidates == 0 then
                return false, "missing physical asset for authoritative card in seat " .. tostring(seat.ttsColor)
                    .. " (identity redacted from normal chat)"
            end
            local asset = table.remove(candidates, 1)
            table.insert(mappings, {card = card, asset = asset, zoneName = zone.name})
        end
    end

    -- Publish mappings only after every authoritative card has a physical
    -- counterpart. A retry must never inherit a partially reconciled seat.
    for _, mapping in ipairs(mappings) do
        local guid = mapping.asset.guid
        BridgeState.physicalByInstanceId[mapping.card.cardInstanceId] = guid
        BridgeState.cardNameByInstanceId[mapping.card.cardInstanceId] = mapping.card.cardName
        BridgeState.physicalSeatByGuid[guid] = seatSnapshot.seatId
        BridgeState.physicalZoneByGuid[guid] = mapping.zoneName
        if mapping.asset.object ~= nil then
            BridgeState.untappedRotationByGuid[guid] = mapping.asset.object.getRotation()
        end
    end
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
    local guid = BridgeState.physicalByInstanceId[card.cardInstanceId]
    if guid == nil then callback(false, "snapshot card has no physical GUID mapping"); return end

    local function continueWith(object)
        local actualGuid = object.getGUID()
        if actualGuid ~= guid then
            BridgeState.physicalSeatByGuid[guid] = nil
            BridgeState.physicalZoneByGuid[guid] = nil
        end
        BridgeState.physicalByInstanceId[card.cardInstanceId] = actualGuid
        BridgeState.cardNameByInstanceId[card.cardInstanceId] = card.cardName
        BridgeState.physicalSeatByGuid[actualGuid] = seatSnapshot.seatId
        BridgeState.physicalZoneByGuid[actualGuid] = zone.name
        BridgePlaceSnapshotCard(object, card, zone, seatSnapshot)
        Wait.frames(function()
            BridgeMaterializeSeatSnapshot(seatSnapshot, zoneIndex, cardIndex + 1, callback)
        end, 2)
    end

    local object = getObjectFromGUID(guid)
    if object ~= nil then continueWith(object); return end

    local seat = BRIDGE_SEATS[seatSnapshot.seatId]
    local deck = BridgeFindSeatLibraryDeckWithCard(seat, card.cardName)
    if deck == nil then
        callback(false, "snapshot card identity is not present in its physical library")
        return
    end

    local libraryZone = getObjectFromGUID(seat.libraryZoneGuid)
    local staging = libraryZone.getPosition()
    BridgeTakeNamedCardFromDeck(
        deck,
        card.cardName,
        {staging.x + 4, staging.y + 2, staging.z},
        false,
        function(taken, takeError)
            if taken == nil then callback(false, takeError); return end
            continueWith(taken)
        end)
end

function BridgePlaceSnapshotCard(object, card, zone, seatSnapshot)
    local seat = BRIDGE_SEATS[seatSnapshot.seatId]
    if zone.name == "library" then
        local libraryZone = getObjectFromGUID(seat.libraryZoneGuid)
        local position = libraryZone.getPosition()
        local count = #(zone.cards or {})
        object.use_hands = false
        object.setPosition({position.x, position.y + 1.5 + (count - card.zonePosition) * 0.025, position.z})
        return
    end
    BridgeSetPhysicalFaceDown(object, seat, card.faceDown == true)
    if zone.name == "hand" then
        local hand = Player[seat.ttsColor].getHandTransform(1)
        object.use_hands = true
        object.setPosition({hand.position.x + (card.zonePosition - (#zone.cards - 1) / 2) * 1.2, hand.position.y, hand.position.z})
        return
    end
    object.use_hands = false
    if zone.name == "battlefield" then
        local row = card.battlefieldKind == "land" and "land" or "creature"
        local position, positionError = BridgeBattlefieldPosition(seatSnapshot.seatId, row)
        if position == nil then
            BridgeStopOnDesync(positionError)
            return
        end
        object.setPosition(position)
        local rowKey = seatSnapshot.seatId .. ":" .. row
        BridgeState.battlefieldCounts[rowKey] = (BridgeState.battlefieldCounts[rowKey] or 0) + 1
    elseif zone.name == "graveyard" then
        local anchor = seat.battlefieldAnchors.creature
        object.setPosition({anchor.x + 8, anchor.y, anchor.z})
    elseif zone.name == "exile" then
        local anchor = seat.battlefieldAnchors.creature
        object.setPosition({anchor.x + 10, anchor.y, anchor.z})
    end
end

function BridgeApplySeatSnapshotVisualState(seatSnapshot)
    local seat = BRIDGE_SEATS[seatSnapshot.seatId]
    local lifeCounter = getObjectFromGUID(seat.lifeCounterGuid)
    if lifeCounter ~= nil then lifeCounter.setValue(seatSnapshot.life) end
    BridgeSetManaBank(seatSnapshot.seatId, seatSnapshot.manaPool or {})
    for _, zone in ipairs(seatSnapshot.zones or {}) do
        if zone.name == "battlefield" then
            for _, card in ipairs(zone.cards or {}) do
                local guid = BridgeState.physicalByInstanceId[card.cardInstanceId]
                local object = guid and getObjectFromGUID(guid) or nil
                if object ~= nil then
                    BridgeSetPhysicalTapped(object, card.tapped == true)
                    for counterType, counterValue in pairs(card.counters or {}) do
                        local ok, counterError = BridgeSetCardCounterState(object, counterType, counterValue)
                        if not ok then print("[Bridge] counter visual unsupported: " .. tostring(counterError)) end
                    end
                    for _, keyword in ipairs(card.keywords or {}) do
                        local ok, keywordError = BridgeSetCardKeywordState(object, keyword, true)
                        if not ok then print("[Bridge] keyword visual unsupported: " .. tostring(keywordError)) end
                    end
                end
            end
        end
    end
end

function BridgeEnsureManaBank(seatId)
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil or seat.manaBankOffset == nil then return false end
    local lifeCounter = getObjectFromGUID(seat.lifeCounterGuid)
    if lifeCounter == nil then
        BridgeShowError("missing life counter for mana bank in seat " .. tostring(seatId))
        return false
    end
    local lifePosition = lifeCounter.getPosition()
    BridgeState.manaCounterGuidBySeatId[seatId] = BridgeState.manaCounterGuidBySeatId[seatId] or {}
    for index, color in ipairs(BRIDGE_MANA_COLORS) do
        local expectedName = "Forge Mana " .. color .. " " .. seatId
        local currentGuid = BridgeState.manaCounterGuidBySeatId[seatId][color]
        local counter = currentGuid and getObjectFromGUID(currentGuid) or nil
        if counter == nil then
            for _, object in ipairs(getAllObjects()) do
                if object.getName() == expectedName then counter = object; break end
            end
        end
        if counter == nil then
            local source = getObjectFromGUID(BRIDGE_MANA_COUNTER_SOURCES[color])
            if source == nil then
                BridgeShowError("missing reusable table mana counter source for " .. color)
                return false
            end
            counter = source.clone({
                position = {
                    lifePosition.x + seat.manaBankOffset.x + (index - 1) * 1.25,
                    lifePosition.y + seat.manaBankOffset.y,
                    lifePosition.z + seat.manaBankOffset.z
                }
            })
            counter.setName(expectedName)
            counter.setScale({0.55, 0.55, 0.55})
            counter.setLock(true)
        end
        counter.setPosition({
            lifePosition.x + seat.manaBankOffset.x + (index - 1) * 1.25,
            lifePosition.y + seat.manaBankOffset.y,
            lifePosition.z + seat.manaBankOffset.z
        })
        BridgeState.manaCounterGuidBySeatId[seatId][color] = counter.getGUID()
    end
    return true
end

function BridgeSetManaBank(seatId, manaPool)
    if not BridgeEnsureManaBank(seatId) then return end
    Wait.frames(function()
        for _, color in ipairs(BRIDGE_MANA_COLORS) do
            local guid = BridgeState.manaCounterGuidBySeatId[seatId][color]
            local counter = guid and getObjectFromGUID(guid) or nil
            if counter ~= nil then
                local amount = tonumber(manaPool[color] or 0) or 0
                counter.setVar("val", amount)
                pcall(function() counter.call("updateVal") end)
                pcall(function() counter.call("updateSave") end)
            end
        end
    end, 2)
end

function BridgeStartEventPolling(sessionId, skipExisting)
    if sessionId == nil then
        BridgeStopOnDesync("cannot poll events without a sessionId")
        return
    end

    if BridgeState.eventSessionId == sessionId and BridgeState.eventPolling then
        return
    end

    BridgePrepareEventSession(sessionId, false)

    BridgeState.skipExistingEventsOnAttach = skipExisting == true
    BridgeState.eventPolling = true
    BridgeState.eventRetryCount = 0
    BridgeState.eventPollGeneration = BridgeState.eventPollGeneration + 1
    BridgePollEvents(BridgeState.eventPollGeneration)
end

function BridgePrepareEventSession(sessionId, forceReset)
    if not forceReset and BridgeState.eventSessionId == sessionId then
        return
    end

    BridgeStopEventPolling()
    BridgeState.eventSessionId = sessionId
    BridgeState.lastReceivedEventSequence = 0
    BridgeState.lastAppliedEventSequence = 0
    BridgeState.eventQueue = {}
    BridgeState.animationRunning = false
    BridgeState.physicalByInstanceId = {}
    BridgeState.cardNameByInstanceId = {}
    BridgeState.physicalSeatByGuid = {}
    BridgeState.physicalZoneByGuid = {}
    BridgeState.battlefieldCounts = {}
    BridgeState.counterStateByInstanceId = {}
    BridgeState.keywordStateByInstanceId = {}
    BridgeState.untappedRotationByGuid = {}
    BridgeState.pendingCastBySeatId = {}
    BridgeState.snapshotForgeSequence = 0
    BridgeState.yieldSeatId = nil
    if BridgeState.turnCounterSessionId ~= sessionId then
        BridgeState.turnCounterSessionId = sessionId
        BridgeState.tableTurnCount = 0
        BridgeState.turnCountsBySeatId = {}
        BridgeRefreshTurnCounterLabels()
    end
end

function BridgeStopEventPolling()
    BridgeState.eventPolling = false
    BridgeState.eventPollGeneration = BridgeState.eventPollGeneration + 1
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
    Wait.time(function()
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
    BridgeHttp.requestJson("GET", path, nil, function(ok, body, err)
        if generation ~= BridgeState.eventPollGeneration then
            return
        end

        BridgeState.eventRequestInFlight = false
        if not ok or body == nil then
            if body ~= nil and body.errorCode == "event_history_gap" then
                BridgeStopOnDesync("event history gap after sequence " .. tostring(requestedAfter) .. ": " .. tostring(body.message))
                return
            end

            BridgeState.eventRetryCount = BridgeState.eventRetryCount + 1
            local retryDelay = math.min(2 ^ (BridgeState.eventRetryCount - 1), 5)
            print(string.format("[Bridge] transient event poll failure (%s); retrying in %.1f seconds", tostring(err), retryDelay))
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
            print("[Bridge] attached at authoritative event sequence " .. tostring(BridgeState.lastAppliedEventSequence))
        else
            for _, event in ipairs(body.events or {}) do
                local expected = BridgeState.lastReceivedEventSequence + 1
                if event.sequence ~= expected then
                    BridgeStopOnDesync("event sequence gap: expected " .. tostring(expected) .. " but received " .. tostring(event.sequence))
                    return
                end

                BridgeState.lastReceivedEventSequence = event.sequence
                table.insert(BridgeState.eventQueue, event)
            end
            BridgeProcessEventQueue()
        end

        BridgeScheduleEventPoll(1, generation)
    end)
end

function BridgeProcessEventQueue()
    if BridgeState.animationRunning or #BridgeState.eventQueue == 0 then
        return
    end

    local event = BridgeState.eventQueue[1]
    local expected = BridgeState.lastAppliedEventSequence + 1
    if event.sequence ~= expected then
        BridgeStopOnDesync("event application gap: expected " .. tostring(expected) .. " but queued " .. tostring(event.sequence))
        return
    end

    BridgeState.animationRunning = true
    local applied, delay, applyError = BridgeApplyAuthoritativeEvent(event)
    if not applied then
        BridgeState.animationRunning = false
        BridgeStopOnDesync(applyError or ("failed to apply event " .. tostring(event.sequence)))
        return
    end

    table.remove(BridgeState.eventQueue, 1)
    BridgeState.lastAppliedEventSequence = event.sequence
    if BridgeShouldReconcileAfterEvent(event) then
        BridgeScheduleSnapshotReconcile("event " .. tostring(event.sequence))
    end
    local generation = BridgeState.eventPollGeneration
    Wait.time(function()
        if generation ~= BridgeState.eventPollGeneration then
            return
        end
        BridgeState.animationRunning = false
        BridgeProcessEventQueue()
    end, delay or 0.1)
end

function BridgeApplyAuthoritativeEvent(event)
    if event.containsHiddenIdentity == true then
        print(string.format("[Bridge] private event %s %s seat=%s (card identity redacted)", tostring(event.sequence), tostring(event.kind), tostring(event.seatId)))
    else
        print(string.format("[Bridge] event %s %s seat=%s card=%s", tostring(event.sequence), tostring(event.kind), tostring(event.seatId), tostring(event.cardName)))
    end

    local seat = BRIDGE_SEATS[event.seatId]
    if seat == nil then
        return false, 0, "event " .. tostring(event.sequence) .. " has no configured seat " .. tostring(event.seatId)
    end

    if event.kind == "turn_changed" then
        BridgeReturnAttackPresentation(nil)
        if event.activeSeatId ~= nil then
            BridgeState.currentTurnSeatId = event.activeSeatId
        else
            BridgeState.currentTurnSeatId = event.seatId
        end
        BridgeRecordAuthoritativeTurn(BridgeState.currentTurnSeatId, tonumber(event.turnNumber or 0))
        local turnSeat = BRIDGE_SEATS[BridgeState.currentTurnSeatId]
        BridgeSetStatus("CURRENT TURN: " .. tostring(turnSeat and turnSeat.ttsColor or BridgeState.currentTurnSeatId), BridgeTurnLabel() .. " - AI THINKING")
        print("[Bridge] authoritative turn changed to seat " .. tostring(BridgeState.currentTurnSeatId) .. " turn=" .. tostring(event.turnNumber))
        if BridgeState.yieldSeatId ~= nil and BridgeState.yieldSeatId ~= event.seatId then
            BridgeState.yieldSeatId = nil
        end
        return true, 0.1
    end

    if event.kind == "phase_changed" then
        BridgeState.currentPhase = event.phase or "Unknown phase"
        if event.turnNumber ~= nil and tonumber(event.turnNumber) ~= nil and tonumber(event.turnNumber) > 0 then
            BridgeState.tableTurnCount = tonumber(event.turnNumber)
            BridgeRefreshTurnCounterLabels()
        end
        if event.activeSeatId ~= nil then
            BridgeState.currentTurnSeatId = event.activeSeatId
        end
        BridgeClearHighlights()
        if BridgeState.lastDecision ~= nil and not BridgeState.submitting then
            BridgeState.lastDecision = nil
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
        return true, 0.1
    end

    if event.kind == "player_state" and event.lifeTotal ~= nil then
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
        return true, 0.1
    end

    if event.kind == "mana_pool_changed" and event.manaPool ~= nil then
        BridgeSetManaBank(event.seatId, event.manaPool)
        return true, 0.1
    end

    if event.kind == "draw" then
        local applied, drawError = BridgeApplyStructuredCardMove(event)
        return applied, 1.25, drawError
    end

    if event.kind == "card_moved" then
        local applied, moveError = BridgeApplyStructuredCardMove(event)
        if not applied and BridgeCanDeferStructuredMoveToSnapshot(event) then
            print("[Bridge] structured move deferred to snapshot reconcile: " .. tostring(moveError))
            return true, 0.1
        end
        return applied, 1.0, moveError
    end

    -- Some tested Forge TUI resolution lines do not have a second text event
    -- for stack -> graveyard. The resolved card identity is still Forge's;
    -- this only gives its already-authoritative result a physical location.
    if event.kind == "spell_resolved" and event.destinationZone == "graveyard" then
        local object, resolveError = BridgeResolveResolvedSpellObject(event)
        if object == nil then
            return false, 0, resolveError
        end
        local moved, moveError = BridgeMoveToGraveyard(event, object)
        if not moved then return false, 0, moveError end
        return true, 0.8
    end

    if event.kind == "tap_changed" then
        local object, resolveError = BridgeResolveMappedInstance(event)
        if object == nil then
            print("[Bridge] tap update deferred to snapshot reconcile: " .. tostring(resolveError))
            return true, 0.1
        end
        BridgeSetPhysicalTapped(object, event.tapped == true)
        return true, 0.5
    end

    if event.kind == "counter_changed" then
        local object, resolveError = BridgeResolveMappedInstance(event)
        if object == nil then
            print("[Bridge] counter update deferred to snapshot reconcile: " .. tostring(resolveError))
            return true, 0.1
        end
        local applied, counterError = BridgeSetCardCounterState(object, event.counterType, event.counterValue)
        if not applied then
            print("[Bridge] optional physical counter decoration skipped: " .. tostring(counterError))
        end
        return true, 0.1, nil
    end

    if event.kind == "keyword_added" or event.kind == "keyword_removed" then
        local object, resolveError = BridgeResolveMappedInstance(event)
        if object == nil then
            print("[Bridge] keyword update deferred to snapshot reconcile: " .. tostring(resolveError))
            return true, 0.1
        end
        local applied, keywordError = BridgeSetCardKeywordState(object, event.keyword, event.kind == "keyword_added")
        if not applied then
            print("[Bridge] optional physical keyword decoration skipped: " .. tostring(keywordError))
        end
        return true, 0.1, nil
    end

    if not seat.animateAuthoritativeEvents then
        if event.kind == "land_played" and event.cardInstanceId ~= nil then
            local object, resolveError = BridgeResolvePhysicalCard(event, "battlefield")
            if object == nil then return false, 0, resolveError end
            local moved, moveError = BridgeMoveToBattlefield(event, object, "land")
            if not moved then return false, 0, moveError end
        end
        if event.kind == "card_moved" and event.destinationZone == "graveyard" and event.cardInstanceId ~= nil then
            local object, resolveError = BridgeResolvePhysicalCard(event, "graveyard")
            if object == nil then return false, 0, resolveError end
        end
        return true, 0.1
    end

    if event.kind == "land_played" then
        local object, resolveError = BridgeResolvePhysicalCard(event, "hand")
        if object == nil then return false, 0, resolveError end
        local moved, moveError = BridgeMoveToBattlefield(event, object, "land")
        if not moved then return false, 0, moveError end
        return true, 1.25
    end

    if event.kind == "spell_resolved" and event.destinationZone == "battlefield" then
        -- Structured card_moved already moved this exact instance from stack to
        -- battlefield. The human-readable semantic line has no instance ID and
        -- must not attempt a second name-based move from an empty stack.
        if event.cardInstanceId == nil then return true, 0.1 end
        local object, resolveError = BridgeResolvePhysicalCard(event, "stack")
        if object == nil then return false, 0, resolveError end
        local moved, moveError = BridgeMoveToBattlefield(event, object, "creature")
        if not moved then return false, 0, moveError end
        return true, 1.25
    end

    if event.kind == "mana_ability_used" then
        local object, resolveError = BridgeResolvePhysicalCard(event, "battlefield")
        if object == nil then return false, 0, resolveError end
        local rotated, rotationError = pcall(function() BridgeSetPhysicalTapped(object, true) end)
        if not rotated then
            return false, 0, "event " .. tostring(event.sequence) .. " could not tap mapped object: " .. tostring(rotationError)
        end
        return true, 0.8
    end

    if event.kind == "attack_declared" then
        local object, resolveError = BridgeResolvePhysicalCard(event, "battlefield")
        if object == nil then return false, 0, resolveError end
        BridgeMoveToAttackLane(event.seatId, object)
        object.highlightOn({1.0, 0.45, 0.0}, 2)
        return true, 1.0
    end


    if event.kind == "block_declared" then
        local object, resolveError = BridgeResolvePhysicalCard(event, "battlefield")
        if object == nil then return false, 0, resolveError end
        BridgeMoveToBlockerLane(event.seatId, object)
        object.highlightOn({1.0, 0.55, 0.0}, 2)
        return true, 1.0
    end

    return true, 0.1
end

function BridgeResolveResolvedSpellObject(event)
    local pendingCast = BridgeState.pendingCastBySeatId[event.seatId]
    local pendingObject = pendingCast ~= nil and getObjectFromGUID(pendingCast.guid) or nil
    if pendingObject ~= nil and BridgeCardNameMatches(pendingObject.getName(), event.cardName) then
        if event.cardInstanceId ~= nil then
            BridgeState.physicalByInstanceId[event.cardInstanceId] = pendingCast.guid
        end
        BridgeState.physicalSeatByGuid[pendingCast.guid] = event.seatId
        BridgeState.physicalZoneByGuid[pendingCast.guid] = "stack"
        BridgeState.pendingCastBySeatId[event.seatId] = nil
        return pendingObject, nil
    end

    if event.cardInstanceId ~= nil then
        local mapped, mappedError = BridgeResolveMappedInstance(event)
        if mapped ~= nil then return mapped, nil end
        -- Fall through only when Forge's textual resolution supplied a stale
        -- object id; the physical card still has an unambiguous Forge name.
    end
    for _, zone in ipairs({"stack", "battlefield", "hand"}) do
        local object, resolveError = BridgeResolvePhysicalCard(event, zone)
        if object ~= nil then return object, nil end
    end
    return nil, "resolved spell cannot be uniquely located for its authoritative graveyard move"
end

function BridgeApplyStructuredCardMove(event)
    if event.cardInstanceId == nil then return false, "structured zone change has no cardInstanceId" end
    local seat = BRIDGE_SEATS[event.seatId]
    if seat == nil then return false, "structured zone change has no configured seat" end

    local guid = BridgeState.physicalByInstanceId[event.cardInstanceId]
    local object = guid ~= nil and getObjectFromGUID(guid) or nil
    if object == nil then
        local fallbackZones = {}
        if event.destinationZone ~= nil and event.destinationZone ~= "" then
            table.insert(fallbackZones, event.destinationZone)
        end
        table.insert(fallbackZones, event.sourceZone or "hand")
        if event.destinationZone ~= nil and event.destinationZone ~= "" and event.destinationZone ~= event.sourceZone then
            table.insert(fallbackZones, event.destinationZone)
        end
        for _, zoneName in ipairs({"hand", "battlefield", "graveyard", "stack", "exile", "library"}) do
            if zoneName ~= event.sourceZone and zoneName ~= event.destinationZone then
                table.insert(fallbackZones, zoneName)
            end
        end

        local resolved, resolveError = nil, nil
        for _, zoneName in ipairs(fallbackZones) do
            local candidate, candidateError = BridgeResolvePhysicalCard(event, zoneName)
            if candidate ~= nil then
                resolved = candidate
                resolveError = nil
                break
            end
            resolveError = candidateError
        end
        if resolved == nil then
            return false, resolveError or ("no physical GUID mapped for authoritative instance " .. tostring(event.cardInstanceId))
        end
        object = resolved
        guid = object.getGUID()
    end

    if object == nil and event.sourceZone == "library" then
        local expectedName = BridgeState.cardNameByInstanceId[event.cardInstanceId]
        if expectedName == nil then return false, "mapped library card has no physical identity" end
        local deck = BridgeFindSeatLibraryDeckWithCard(seat, expectedName)
        if deck == nil then return false, "mapped library card identity is not present in a physical deck" end
        local hand = Player[seat.ttsColor].getHandTransform(1)
        BridgeTakeNamedCardFromDeck(deck, expectedName, hand.position, true, function(drawn, takeError)
            if drawn == nil then
                BridgeStopOnDesync(takeError)
                return
            end
                BridgeState.physicalByInstanceId[event.cardInstanceId] = drawn.getGUID()
                BridgeState.physicalSeatByGuid[drawn.getGUID()] = event.seatId
                BridgeState.physicalZoneByGuid[drawn.getGUID()] = event.destinationZone
                drawn.use_hands = true
                BridgeSetPhysicalFaceDown(drawn, seat, event.faceDown == true)
        end)
        return true, nil
    end
    if object == nil then return false, "mapped physical card is unavailable for structured zone change" end

    if event.destinationZone == "hand" then
        local hand = Player[seat.ttsColor].getHandTransform(1)
        object.use_hands = true
        BridgeSetPhysicalFaceDown(object, seat, event.faceDown == true)
        object.setPositionSmooth(hand.position, false, true)
    elseif event.destinationZone == "battlefield" then
        object.use_hands = false
        if event.sourceZone ~= "hand" then
            local moved, moveError = BridgeMoveToBattlefield(event, object, "creature")
            if not moved then return false, moveError end
        end
    elseif event.destinationZone == "stack" then
        object.use_hands = false
        BridgeSetPhysicalFaceDown(object, seat, event.faceDown == true)
        object.setPosition(BRIDGE_STACK_POSITION)
    elseif event.destinationZone == "graveyard" then
        local moved, moveError = BridgeMoveToGraveyard(event, object)
        if not moved then return false, moveError end
    elseif event.destinationZone == "exile" then
        local anchor = seat.battlefieldAnchors.creature
        object.use_hands = false
        object.setPositionSmooth({anchor.x + 10, anchor.y, anchor.z}, false, true)
    elseif event.destinationZone == "library" then
        local libraryZone = getObjectFromGUID(seat.libraryZoneGuid)
        object.use_hands = false
        object.setPositionSmooth(libraryZone.getPosition(), false, true)
    end

    BridgeState.physicalSeatByGuid[guid] = event.seatId
    BridgeState.physicalZoneByGuid[guid] = event.destinationZone
    return true, nil
end

function BridgeMoveToGraveyard(event, object)
    local seat = BRIDGE_SEATS[event.seatId]
    if seat == nil then return false, "graveyard move has no configured seat" end
    local anchor = seat.battlefieldAnchors.creature
    local moved, movementError = pcall(function()
        object.use_hands = false
        BridgeSetPhysicalFaceDown(object, seat, false)
        object.setPositionSmooth({anchor.x + 8, anchor.y, anchor.z}, false, true)
    end)
    if not moved then return false, "could not move card to graveyard: " .. tostring(movementError) end
    local guid = object.getGUID()
    BridgeState.physicalSeatByGuid[guid] = event.seatId
    BridgeState.physicalZoneByGuid[guid] = "graveyard"
    BridgeState.pendingCastBySeatId[event.seatId] = nil
    if event.cardInstanceId ~= nil then BridgeState.physicalByInstanceId[event.cardInstanceId] = guid end
    return true, nil
end

function BridgeFindSeatLibraryDeckWithCard(seat, expectedName)
    for _, object in ipairs(getAllObjects()) do
        if object.tag == "Deck" and BridgeObjectIsOnSeatSide(object, seat) then
            for _, contained in ipairs(object.getObjects() or {}) do
                if BridgeCardNameMatches(contained.nickname or contained.name, expectedName) then
                    return object
                end
            end
        end
    end
    return nil
end

function BridgeTakeNamedCardFromDeck(deck, expectedName, position, smooth, callback)
    local matched = nil
    for _, contained in ipairs(deck.getObjects() or {}) do
        if BridgeCardNameMatches(contained.nickname or contained.name, expectedName) then
            matched = contained
            break
        end
    end
    if matched == nil or matched.index == nil then
        callback(nil, "physical library has no indexed card matching the authoritative identity")
        return
    end

    deck.takeObject({
        index = matched.index,
        position = position,
        smooth = smooth,
        callback_function = function(taken)
            if not BridgeCardNameMatches(taken.getName(), expectedName) then
                deck.putObject(taken)
                callback(nil, "physical library returned a card with the wrong identity")
                return
            end
            callback(taken, nil)
        end
    })
end

function BridgeSetPhysicalFaceDown(object, seat, faceDown)
    local faceUp = seat.faceUpRotation
    if faceUp == nil then return end
    local rotation = {
        x = faceUp.x,
        y = faceUp.y,
        z = faceUp.z + (faceDown and 180 or 0)
    }
    object.setRotation(rotation)
    BridgeState.untappedRotationByGuid[object.getGUID()] = {
        x = faceUp.x,
        y = faceUp.y,
        z = faceUp.z
    }
end

function BridgeSetPhysicalTapped(object, tapped)
    local guid = object.getGUID()
    local base = BridgeState.untappedRotationByGuid[guid]
    if base == nil then
        base = object.getRotation()
        BridgeState.untappedRotationByGuid[guid] = base
    end
    local targetY = base.y + (tapped and 90 or 0)
    object.setRotationSmooth({base.x, targetY, base.z}, false, true)
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

-- Existing table integration: Easy Modules Unified is the authoritative visual
-- sink for +1/+1 and generic named counters. Values are set absolutely so event
-- replay cannot double the physical display.
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

    local encoder = Global.getVar("Encoder")
    if encoder == nil then return false, "Easy Modules Encoder is unavailable" end
    local ok, applyError = pcall(function()
        local encoded = encoder.call("APIobjGetPropData", {obj = object, propID = "_MTG_Simplified_UNIFIED"})
        if encoded == nil or encoded.tyrantUnified == nil then error("card is not encoded with Easy Modules Unified") end
        encoded.tyrantUnified[field] = counterValue
        if field == "plusOneCounters" then encoded.tyrantUnified.displayPlusOne = counterValue ~= 0 end
        if field == "namedCounters" then encoded.tyrantUnified.displayCounters = counterValue ~= 0 end
        encoder.call("APIobjSetPropData", {obj = object, propID = "_MTG_Simplified_UNIFIED", data = encoded})
        encoder.call("APIrebuildButtons", {obj = object})
    end)
    if not ok then return false, tostring(applyError) end
    return true, nil
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

function BridgeSetCardKeywordState(object, keyword, enabled)
    local normalized = string.lower(tostring(keyword or ""))
    local property = BRIDGE_KEYWORD_PROPERTIES[normalized]
    if property == nil then return false, "unsupported existing-table keyword " .. tostring(keyword) end

    local encoder = Global.getVar("Encoder")
    if encoder == nil then return false, "Easy Modules Encoder is unavailable" end
    local ok, applyError = pcall(function()
        local data = encoder.call("APIobjGetPropData", {obj = object, propID = "πKeywords"})
        if data == nil then error("card is not encoded with πKeywords") end
        data[property] = enabled and 1 or 0
        data.activeIcons = data.activeIcons or {}
        local found = nil
        for index, value in ipairs(data.activeIcons) do
            if value == property then found = index; break end
        end
        if enabled and found == nil then table.insert(data.activeIcons, property) end
        if not enabled and found ~= nil then table.remove(data.activeIcons, found) end
        encoder.call("APIobjSetPropData", {obj = object, propID = "πKeywords", data = data})
        encoder.call("APIrebuildButtons", {obj = object})
    end)
    if not ok then return false, tostring(applyError) end
    return true, nil
end

function BridgeResolvePhysicalCard(event, expectedZone)
    if event.cardInstanceId ~= nil then
        local existingGuid = BridgeState.physicalByInstanceId[event.cardInstanceId]
        if existingGuid ~= nil then
            local existing = getObjectFromGUID(existingGuid)
            if existing == nil then
                return nil, BridgePhysicalMappingError(event, expectedZone, 0, "mapped object disappeared")
            end
            if existing.tag == "Card" then
                return existing, nil
            end
            if expectedZone == "library" and existing.tag == "Deck" then
                return existing, nil
            end
            -- A stale mapping can temporarily point at a deck object while the
            -- authoritative card instance has moved into a public zone.
            BridgeState.physicalByInstanceId[event.cardInstanceId] = nil
        end
    end

    local seat = BRIDGE_SEATS[event.seatId]
    if seat == nil then
        return nil, BridgePhysicalMappingError(event, expectedZone, 0, "seat is not configured")
    end

    local source = {}
    if expectedZone == "hand" then
        source = Player[seat.ttsColor].getHandObjects()
    else
        for _, object in ipairs(getAllObjects()) do
            if object.tag == "Card" and BridgeState.physicalSeatByGuid[object.getGUID()] == event.seatId and BridgeState.physicalZoneByGuid[object.getGUID()] == expectedZone then
                table.insert(source, object)
            end
        end
    end

    local matches = {}
    for _, object in ipairs(source) do
        if object.tag == "Card" and BridgeCardNameMatches(object.getName(), event.cardName) then
            table.insert(matches, object)
        end
    end

    if #matches ~= 1 then
        return nil, BridgePhysicalMappingError(event, expectedZone, #matches, "cannot uniquely identify physical card")
    end

    local object = matches[1]
    local guid = object.getGUID()
    if event.cardInstanceId ~= nil then
        BridgeState.physicalByInstanceId[event.cardInstanceId] = guid
    end
    BridgeState.physicalSeatByGuid[guid] = event.seatId
    BridgeState.physicalZoneByGuid[guid] = expectedZone
    return object, nil
end

function BridgePhysicalMappingError(event, expectedZone, candidateCount, detail)
    return string.format(
        "physical mapping failed: event=%s seat=%s card='%s' sourceZone=%s candidates=%d (%s)",
        tostring(event.sequence), tostring(event.seatId), tostring(event.cardName), tostring(expectedZone), candidateCount, tostring(detail))
end

function BridgeMoveToBattlefield(event, object, row)
    local destination, positionError = BridgeBattlefieldPosition(event.seatId, row)
    if destination == nil then
        return false, positionError
    end

    local moved, movementError = pcall(function()
        object.use_hands = false
        BridgeSetPhysicalFaceDown(object, BRIDGE_SEATS[event.seatId], event.faceDown == true)
        object.setPosition(destination)
    end)
    if not moved then
        return false, "event " .. tostring(event.sequence) .. " could not move physical card: " .. tostring(movementError)
    end

    local guid = object.getGUID()
    BridgeState.physicalSeatByGuid[guid] = event.seatId
    BridgeState.physicalZoneByGuid[guid] = "battlefield"
    if event.cardInstanceId ~= nil then
        BridgeState.physicalByInstanceId[event.cardInstanceId] = guid
    end
    local rowKey = event.seatId .. ":" .. row
    BridgeState.battlefieldCounts[rowKey] = (BridgeState.battlefieldCounts[rowKey] or 0) + 1
    return true, nil
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
            x = anchor.x + (slot % 6) * 2.2,
            y = anchor.y,
            z = anchor.z + math.floor(slot / 6) * seat.tableSideZ * 2.5
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
            if dx * dx + dz * dz < 1.5 then return true end
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

function BridgeMoveToBlockerLane(seatId, object)
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then return end
    local guid = object.getGUID()
    local position = object.getPosition()
    if BridgeState.attackOriginByGuid[guid] == nil then
        BridgeState.attackOriginByGuid[guid] = {x = position.x, y = position.y, z = position.z}
    end
    object.setPositionSmooth({x = position.x, y = math.max(position.y, 2.0), z = seat.blockerLaneZ}, false, true)
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
        end
    end
end

function BridgeStopOnDesync(message)
    BridgeStopEventPolling()
    BridgeState.animationRunning = false
    BridgeClearHighlights()
    BridgeShowError("synchronization stopped: " .. tostring(message))
end

function BridgePrintEventSyncStatus()
    print(string.format(
        "[Bridge] event sync session=%s polling=%s received=%s applied=%s queued=%d retries=%d inFlight=%s",
        tostring(BridgeState.eventSessionId), tostring(BridgeState.eventPolling),
        tostring(BridgeState.lastReceivedEventSequence), tostring(BridgeState.lastAppliedEventSequence),
        #BridgeState.eventQueue, BridgeState.eventRetryCount, tostring(BridgeState.eventRequestInFlight)))
end

function BridgeDumpSyncState()
    BridgePrintEventSyncStatus()
    print("[Bridge] pendingIntent=" .. JSON.encode(BridgeState.pendingIntent or {}))
    print("[Bridge] yieldSeatId=" .. tostring(BridgeState.yieldSeatId))
    print("[Bridge] pendingQueue=" .. JSON.encode(BridgeState.eventQueue))
    print("[Bridge] physicalByInstanceId=" .. JSON.encode(BridgeState.physicalByInstanceId))
    print("[Bridge] physicalSeatByGuid=" .. JSON.encode(BridgeState.physicalSeatByGuid))
    print("[Bridge] physicalZoneByGuid=" .. JSON.encode(BridgeState.physicalZoneByGuid))
end
