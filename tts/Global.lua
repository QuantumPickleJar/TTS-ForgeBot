BRIDGE_BASE_URL = "http://127.0.0.1:43110"

-- Seat identity remains independent of controller type and TTS color.
BRIDGE_SEATS = {
    ["forge-player-1"] = {
        ttsColor = "White",
        animateAuthoritativeEvents = false
    },
    ["forge-player-2"] = {
        ttsColor = "Blue",
        animateAuthoritativeEvents = true
    }
}

BridgeState = {
    lastDecision = nil,
    actionByGuid = {},
    highlightedGuids = {},
    submitting = false,
    pendingIntent = nil,
    eventSessionId = nil,
    lastEventSequence = 0,
    eventPolling = false,
    skipExistingEventsOnAttach = false,
    eventQueue = {},
    animationRunning = false,
    physicalByInstanceId = {},
    physicalSeatByGuid = {},
    physicalZoneByGuid = {},
    battlefieldCounts = {},
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

-- Existing table draw-button behavior: deal from the owning player's deck zone.
function drawSwap(me, clickerColor)
    local ownerColor = me.getVar("color")
    local deckZoneGuid = me.getVar("deckZone")
    local deckZone = getObjectFromGUID(deckZoneGuid)

    if not deckZone then
        print("[Draw] Missing deck zone: " .. tostring(deckZoneGuid))
        return
    end

    local zoneObjects = deckZone.getObjects()
    for i = #zoneObjects, 1, -1 do
        local cardOrDeck = zoneObjects[i]
        if cardOrDeck.tag == "Card" or cardOrDeck.tag == "Deck" then
            cardOrDeck.deal(1, ownerColor)
            return
        end
    end
end

function BridgeGetHealth(callback)
    BridgeHttp.requestJson("GET", "/health", nil, callback)
end

function BridgeStartSession(callback)
    BridgeHttp.requestJson("POST", "/api/v1/session/start", nil, callback)
end

function BridgeGetDecision(callback)
    BridgeHttp.requestJson("GET", "/api/v1/decision", nil, function(ok, body, err, request)
        if ok and body ~= nil then
            BridgeState.lastDecision = body
        else
            BridgeState.lastDecision = nil
            BridgeClearHighlights()
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
            BridgeShowError("choice rejected: " .. tostring(err))
            if body ~= nil and body.errorCode ~= nil then
                BridgeShowError("errorCode=" .. tostring(body.errorCode) .. " message=" .. tostring(body.message))
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

        BridgeState.pendingIntent = nil
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

function BridgeOnLoad()
    print("[Bridge] ForgeBot integration loaded.")
    Wait.frames(function()
        BridgeAttachToActiveSession()
    end, 30)
end

function BridgeAttachToActiveSession()
    BridgeGetHealth(function(ok, body, err)
        if not ok then
            BridgeClearHighlights()
            BridgeShowError("health failed: " .. tostring(err))
            return
        end

        print("[Bridge] health ok. adapter=" .. tostring(body.adapter) .. " state=" .. tostring(body.adapterState))

        BridgeGetDecision(function(decisionOk, decisionBody, decisionErr)
            if decisionOk and decisionBody ~= nil then
                printDecision(decisionBody)
                BridgeStartEventPolling(body.sessionId, true)
                return
            end

            print("[Bridge] no active decision available (" .. tostring(decisionErr) .. "). This script will not restart Forge automatically.")
            print("[Bridge] When Forge reaches a decision, run BridgeRefreshDecision().")
        end)
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

function BridgeStartNewSession()
    BridgeClearHighlights()
    BridgeState.lastDecision = nil

    BridgeStartSession(function(ok, body, err)
        if not ok then
            BridgeShowError("session start failed: " .. tostring(err))
            return
        end

        print("[Bridge] session started: " .. tostring(body and body.sessionId))
        BridgeStartEventPolling(body.sessionId, false)
        if body ~= nil and body.currentDecision ~= nil then
            printDecision(body.currentDecision)
        else
            BridgeRefreshDecision()
        end
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

    BridgeState.lastDecision = decision
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

    BridgeState.highlightedGuids = {}
    BridgeState.actionByGuid = {}
end

function BridgeRenderDecision(decision)
    BridgeClearHighlights()

    if decision == nil or decision.actions == nil then
        return
    end

    local highlightColor = {0.53, 0.81, 0.98}
    if decision.kind == "target_selection" or decision.kind == "blocker_selection" then
        highlightColor = {1.0, 0.55, 0.0}
    end

    local candidateObjects = getAllObjects()
    local decisionSeat = BRIDGE_SEATS[decision.seatId]
    if decision.kind == "main_priority" and decisionSeat ~= nil then
        candidateObjects = Player[decisionSeat.ttsColor].getHandObjects()
    end

    local cards = {}
    for _, object in ipairs(candidateObjects) do
        if object.tag == "Card" then
            table.insert(cards, object)
        end
    end

    for _, action in ipairs(decision.actions) do
        local matches = {}
        for _, object in ipairs(cards) do
            if BridgeCardNameMatches(object.getName(), action.cardIdentity) then
                table.insert(matches, object)
            end
        end

        if action.cardIdentity ~= nil and #matches > 0 then
            if #matches > 1 then
                print(string.format("[Bridge] duplicate card name '%s': highlighting all %d candidates", tostring(action.cardIdentity), #matches))
            end

            for _, object in ipairs(matches) do
                local guid = object.getGUID()
                object.highlightOn(highlightColor)
                BridgeState.actionByGuid[guid] = action.actionId
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

    local actionId = BridgeState.actionByGuid[object.getGUID()]
    if actionId == nil then
        return
    end

    local decision = BridgeState.lastDecision
    if decision == nil then
        BridgeClearHighlights()
        BridgeShowError("highlighted card has no active bridge decision")
        return
    end

    local decisionSeat = BRIDGE_SEATS[decision.seatId]
    local expectedColor = decisionSeat and decisionSeat.ttsColor or nil
    if expectedColor ~= nil and expectedColor ~= playerColor then
        BridgeShowError("this decision belongs to TTS color " .. tostring(expectedColor))
        return
    end

    BridgeState.pendingIntent = {
        guid = object.getGUID(),
        position = object.getPosition(),
        rotation = object.getRotation()
    }
    BridgeClearHighlights()
    BridgeSubmitChoice(decision.decisionId, actionId)
end

function BridgeRollbackPendingIntent()
    local intent = BridgeState.pendingIntent
    BridgeState.pendingIntent = nil
    if intent == nil then
        return
    end

    local object = getObjectFromGUID(intent.guid)
    if object ~= nil then
        object.setPositionSmooth(intent.position, false, true)
        object.setRotationSmooth(intent.rotation, false, true)
        object.highlightOn({1.0, 0.1, 0.1}, 2)
    end
end

function BridgeStartEventPolling(sessionId, skipExisting)
    if sessionId == nil then
        BridgeStopOnDesync("cannot poll events without a sessionId")
        return
    end

    if BridgeState.eventSessionId ~= sessionId then
        BridgeState.eventSessionId = sessionId
        BridgeState.lastEventSequence = 0
        BridgeState.physicalByInstanceId = {}
        BridgeState.physicalSeatByGuid = {}
        BridgeState.physicalZoneByGuid = {}
        BridgeState.battlefieldCounts = {}
    end

    BridgeState.skipExistingEventsOnAttach = skipExisting == true
    if BridgeState.eventPolling then
        return
    end

    BridgeState.eventPolling = true
    BridgePollEvents()
end

function BridgePollEvents()
    if not BridgeState.eventPolling then
        return
    end

    local path = "/api/v1/events?after=" .. tostring(BridgeState.lastEventSequence)
    BridgeHttp.requestJson("GET", path, nil, function(ok, body, err)
        if not ok or body == nil then
            BridgeStopOnDesync("event poll failed: " .. tostring(err))
            return
        end

        if BridgeState.skipExistingEventsOnAttach then
            BridgeState.lastEventSequence = body.latestSequence or BridgeState.lastEventSequence
            BridgeState.skipExistingEventsOnAttach = false
            print("[Bridge] attached at authoritative event sequence " .. tostring(BridgeState.lastEventSequence))
        else
            for _, event in ipairs(body.events or {}) do
                local expected = BridgeState.lastEventSequence + 1
                if event.sequence ~= expected then
                    BridgeStopOnDesync("event sequence gap: expected " .. tostring(expected) .. " but received " .. tostring(event.sequence))
                    return
                end

                BridgeState.lastEventSequence = event.sequence
                table.insert(BridgeState.eventQueue, event)
            end
            BridgeProcessEventQueue()
        end

        Wait.time(BridgePollEvents, 1)
    end)
end

function BridgeProcessEventQueue()
    if BridgeState.animationRunning or #BridgeState.eventQueue == 0 then
        return
    end

    BridgeState.animationRunning = true
    local event = table.remove(BridgeState.eventQueue, 1)
    local delay = BridgeApplyAuthoritativeEvent(event)
    Wait.time(function()
        BridgeState.animationRunning = false
        BridgeProcessEventQueue()
    end, delay or 0.1)
end

function BridgeApplyAuthoritativeEvent(event)
    print(string.format("[Bridge] event %s %s seat=%s card=%s", tostring(event.sequence), tostring(event.kind), tostring(event.seatId), tostring(event.cardName)))

    local seat = BRIDGE_SEATS[event.seatId]
    if seat == nil or not seat.animateAuthoritativeEvents then
        return 0.1
    end

    if event.kind == "land_played" then
        local object = BridgeResolvePhysicalCard(event, "hand")
        if object == nil then return 0.1 end
        BridgeMoveToBattlefield(event, object, "land")
        return 1.25
    end

    if event.kind == "spell_resolved" and event.destinationZone == "battlefield" then
        local object = BridgeResolvePhysicalCard(event, "hand")
        if object == nil then return 0.1 end
        BridgeMoveToBattlefield(event, object, "creature")
        return 1.25
    end

    if event.kind == "mana_ability_used" then
        local object = BridgeResolvePhysicalCard(event, "battlefield")
        if object == nil then return 0.1 end
        local rotation = object.getRotation()
        object.setRotationSmooth({rotation.x, rotation.y, rotation.z + 90}, false, true)
        return 0.8
    end

    if event.kind == "attack_declared" then
        local object = BridgeResolvePhysicalCard(event, "battlefield")
        if object == nil then return 0.1 end
        local position = object.getPosition()
        local towardCenter = BridgeUnitTowardTableCenter(position)
        object.setPositionSmooth({position.x + towardCenter.x * 2, position.y, position.z + towardCenter.z * 2}, false, true)
        object.highlightOn({1.0, 0.45, 0.0}, 2)
        return 1.0
    end

    return 0.1
end

function BridgeResolvePhysicalCard(event, expectedZone)
    if event.cardInstanceId ~= nil then
        local existingGuid = BridgeState.physicalByInstanceId[event.cardInstanceId]
        if existingGuid ~= nil then
            local existing = getObjectFromGUID(existingGuid)
            if existing == nil then
                BridgeStopOnDesync("mapped object disappeared for " .. tostring(event.cardInstanceId))
            end
            return existing
        end
    end

    local seat = BRIDGE_SEATS[event.seatId]
    if seat == nil then
        BridgeStopOnDesync("event has no configured seat: " .. tostring(event.seatId))
        return nil
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
        BridgeStopOnDesync(string.format(
            "cannot uniquely map event %s card '%s' in %s for seat %s: found %d candidates",
            tostring(event.sequence), tostring(event.cardName), tostring(expectedZone), tostring(event.seatId), #matches))
        return nil
    end

    local object = matches[1]
    local guid = object.getGUID()
    if event.cardInstanceId ~= nil then
        BridgeState.physicalByInstanceId[event.cardInstanceId] = guid
    end
    BridgeState.physicalSeatByGuid[guid] = event.seatId
    BridgeState.physicalZoneByGuid[guid] = expectedZone
    return object
end

function BridgeMoveToBattlefield(event, object, row)
    local destination = BridgeBattlefieldPosition(event.seatId, row)
    object.setPositionSmooth(destination, false, true)
    local guid = object.getGUID()
    BridgeState.physicalSeatByGuid[guid] = event.seatId
    BridgeState.physicalZoneByGuid[guid] = "battlefield"
    if event.cardInstanceId ~= nil then
        BridgeState.physicalByInstanceId[event.cardInstanceId] = guid
    end
end

function BridgeBattlefieldPosition(seatId, row)
    local seat = BRIDGE_SEATS[seatId]
    local hand = Player[seat.ttsColor].getHandTransform()
    local towardCenter = BridgeUnitTowardTableCenter(hand.position)
    local perpendicular = {x = -towardCenter.z, z = towardCenter.x}
    local rowKey = seatId .. ":" .. row
    local count = BridgeState.battlefieldCounts[rowKey] or 0
    BridgeState.battlefieldCounts[rowKey] = count + 1
    local distance = row == "land" and 5 or 8
    local lateral = (count % 5) * 2.2 - 4.4
    return {
        x = hand.position.x + towardCenter.x * distance + perpendicular.x * lateral,
        y = 2,
        z = hand.position.z + towardCenter.z * distance + perpendicular.z * lateral
    }
end

function BridgeUnitTowardTableCenter(position)
    local length = math.sqrt(position.x * position.x + position.z * position.z)
    if length < 0.01 then
        return {x = 0, z = 1}
    end
    return {x = -position.x / length, z = -position.z / length}
end

function BridgeStopOnDesync(message)
    BridgeState.eventPolling = false
    BridgeState.eventQueue = {}
    BridgeState.animationRunning = false
    BridgeClearHighlights()
    BridgeShowError("synchronization stopped: " .. tostring(message))
end
