BRIDGE_BASE_URL = "http://127.0.0.1:43110"

-- Seat identity remains independent of controller type and TTS color.
BRIDGE_SEATS = {
    ["forge-player-1"] = {
        ttsColor = "White",
        animateAuthoritativeEvents = false,
        targetSurfaceGuid = "2a7098",
        lifeCounterGuid = "2a7098",
        libraryZoneGuid = "ddf5c3",
        tableSideZ = -1,
        battlefieldAnchors = {
            land = {x = 6.5, y = 2.0, z = -11.5},
            creature = {x = 7.0, y = 2.0, z = -3.5}
        }
    },
    ["forge-player-2"] = {
        ttsColor = "Blue",
        animateAuthoritativeEvents = true,
        targetSurfaceGuid = "3ef92a",
        lifeCounterGuid = "3ef92a",
        libraryZoneGuid = "548812",
        tableSideZ = 1,
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
    physicalSeatByGuid = {},
    physicalZoneByGuid = {},
    battlefieldCounts = {},
    yieldSeatId = nil,
    counterStateByInstanceId = {},
    keywordStateByInstanceId = {},
    untappedRotationByGuid = {},
    snapshotForgeSequence = 0,
    bootstrapping = false,
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

function onPlayerTurnEnd(playerColor, nextPlayerColor)
    local decision = BridgeState.lastDecision
    if decision == nil then return end
    local seat = BRIDGE_SEATS[decision.seatId]
    if seat == nil or seat.ttsColor ~= playerColor then return end

    BridgeState.yieldSeatId = decision.seatId
    BridgeRenderDecision(decision)
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
        if body.sessionId ~= nil and body.sessionId ~= "session-not-started"
            and body.adapterState ~= "failed" and body.adapterState ~= "not_started" then
            BridgeBootstrapCurrentSnapshot(body.sessionId, function(bootstrapOk, bootstrapError)
                if bootstrapOk then
                    BridgeStartEventPolling(body.sessionId, true)
                else
                    BridgeStopOnDesync(bootstrapError)
                end
            end)
        end

        BridgeGetDecision(function(decisionOk, decisionBody, decisionErr)
            if decisionOk and decisionBody ~= nil then
                printDecision(decisionBody)
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

function BridgeStartSessionIfNone()
    BridgeClearHighlights()
    BridgeState.lastDecision = nil

    BridgeStartSession(function(ok, body, err)
        if not ok then
            BridgeShowError("session start failed: " .. tostring(err))
            return
        end

        print("[Bridge] started or attached session: " .. tostring(body and body.sessionId))
        -- The start route may attach to a match that already exists. Do not replay
        -- its historical physical events; an explicit reset is the new-match path.
        BridgeBootstrapCurrentSnapshot(body.sessionId, function(bootstrapOk, bootstrapError)
            if not bootstrapOk then BridgeStopOnDesync(bootstrapError); return end
            BridgeStartEventPolling(body.sessionId, true)
            if body ~= nil and body.currentDecision ~= nil then printDecision(body.currentDecision)
            else BridgeRefreshDecision() end
        end)
    end)
end

function BridgeResetSession()
    BridgeStopEventPolling()
    BridgeClearHighlights()
    BridgeState.lastDecision = nil

    BridgeResetSessionRequest(function(ok, body, err)
        if not ok then
            BridgeShowError("explicit session reset failed: " .. tostring(err))
            return
        end

        print("[Bridge] active match explicitly replaced: " .. tostring(body and body.sessionId))
        BridgeBootstrapCurrentSnapshot(body.sessionId, function(bootstrapOk, bootstrapError)
            if not bootstrapOk then BridgeStopOnDesync(bootstrapError); return end
            -- The snapshot is authoritative through this point, so opening
            -- mutation records are acknowledged instead of replayed.
            BridgeStartEventPolling(body.sessionId, true)
            if body ~= nil and body.currentDecision ~= nil then printDecision(body.currentDecision)
            else BridgeRefreshDecision() end
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

    for guid, buttonIndex in pairs(BridgeState.targetButtonIndexByGuid) do
        local object = getObjectFromGUID(guid)
        if object ~= nil then object.removeButton(buttonIndex) end
    end

    BridgeState.highlightedGuids = {}
    BridgeState.actionByGuid = {}
    BridgeState.targetButtonIndexByGuid = {}
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

function BridgeRenderDecision(decision)
    BridgeClearHighlights()

    if decision == nil or decision.actions == nil then
        return
    end

    if BridgeState.yieldSeatId ~= nil then
        if decision.seatId ~= BridgeState.yieldSeatId or decision.kind ~= "main_priority" then
            BridgeState.yieldSeatId = nil
        else
            for _, action in ipairs(decision.actions) do
                if action.type == "pass_yield" then
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
        if mappedObject ~= nil then
            table.insert(matches, mappedObject)
        else
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
                object.highlightOn(highlightColor)
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

    local decisionSeat = BRIDGE_SEATS[decision.seatId]
    local expectedColor = decisionSeat and decisionSeat.ttsColor or nil
    if expectedColor ~= nil and expectedColor ~= playerColor then
        BridgeShowError("this decision belongs to TTS color " .. tostring(expectedColor))
        return
    end

    BridgeState.pendingIntent = {
        guid = object.getGUID(),
        position = object.getPosition(),
        rotation = object.getRotation(),
        useHands = object.use_hands,
        decisionId = decision.decisionId,
        action = action,
        seatId = decision.seatId
    }
    BridgeClearHighlights()

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
        if BridgeObjectIsInHand(object, playerColor) then
            BridgeRollbackPendingIntent()
            BridgeRenderDecision(decision)
            return
        end
        BridgeState.physicalSeatByGuid[intent.guid] = intent.seatId
        BridgeState.physicalZoneByGuid[intent.guid] = "battlefield"
    elseif decision.kind == "card_selection" then
        BridgeState.physicalSeatByGuid[intent.guid] = intent.seatId
        BridgeState.physicalZoneByGuid[intent.guid] = "graveyard"
    end

    BridgeSubmitChoice(intent.decisionId, intent.action.actionId)
end

function BridgeObjectIsInHand(object, playerColor)
    for _, handObject in ipairs(Player[playerColor].getHandObjects()) do
        if handObject.getGUID() == object.getGUID() then
            return true
        end
    end
    return false
end

function BridgeCommitPendingIntent()
    local intent = BridgeState.pendingIntent
    BridgeState.pendingIntent = nil
    if intent == nil then return end

    if intent.action.targetKind ~= nil or intent.action.type == "choose_blocker" then
        local object = getObjectFromGUID(intent.guid)
        if object ~= nil then
            object.use_hands = intent.useHands
            object.setPositionSmooth(intent.position, false, true)
            object.setRotationSmooth(intent.rotation, false, true)
        end
    elseif intent.action.type == "play_land" or intent.action.type == "cast_spell" then
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
    BridgeState.physicalSeatByGuid[intent.guid] = nil
    BridgeState.physicalZoneByGuid[intent.guid] = nil
end

function BridgeBootstrapCurrentSnapshot(sessionId, callback)
    if BridgeState.bootstrapping then
        callback(false, "an embodiment bootstrap is already in progress")
        return
    end
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
end

function BridgeBootstrapSeats(snapshot, seatIndex, callback)
    local seats = snapshot.seats or {}
    if seatIndex > #seats then callback(true, nil); return end
    local seatSnapshot = seats[seatIndex]
    local seat = BRIDGE_SEATS[seatSnapshot.seatId]
    if seat == nil then callback(false, "snapshot has no configured TTS seat " .. tostring(seatSnapshot.seatId)); return end

    BridgeCollectSeatAssets(seatSnapshot.seatId, function(ok, assets, collectError)
        if not ok then callback(false, collectError); return end
        local reconciled, reconcileError = BridgeReconcileSeatSnapshot(seatSnapshot, assets)
        if not reconciled then callback(false, reconcileError); return end
        Wait.frames(function()
            BridgeApplySeatSnapshotVisualState(seatSnapshot)
            BridgeBootstrapSeats(snapshot, seatIndex + 1, callback)
        end, 90)
    end)
end

function BridgeCollectSeatAssets(seatId, callback)
    local seat = BRIDGE_SEATS[seatId]
    local cards = {}
    local decks = {}
    for _, object in ipairs(getAllObjects()) do
        if (object.tag == "Card" or object.tag == "Deck") and BridgeObjectIsOnSeatSide(object, seat) then
            if object.tag == "Card" then table.insert(cards, object)
            else table.insert(decks, object) end
        end
    end

    BridgeExtractSeatDecks(decks, 1, cards, seat, function(ok, extractError)
        if not ok then callback(false, nil, extractError); return end
        callback(true, cards, nil)
    end)
end

function BridgeObjectIsOnSeatSide(object, seat)
    local position = object.getPosition()
    if seat.tableSideZ < 0 then return position.z < -0.25 end
    return position.z > 0.25
end

function BridgeExtractSeatDecks(decks, index, cards, seat, callback)
    if index > #decks then callback(true, nil); return end
    local libraryZone = getObjectFromGUID(seat.libraryZoneGuid)
    if libraryZone == nil then callback(false, "missing configured library zone " .. tostring(seat.libraryZoneGuid)); return end
    local origin = libraryZone.getPosition()
    local staging = {x = origin.x + 4, y = 2.5, z = origin.z}
    BridgeExtractOneDeck(decks[index], staging, cards, function(ok, extractError)
        if not ok then callback(false, extractError); return end
        BridgeExtractSeatDecks(decks, index + 1, cards, seat, callback)
    end)
end

function BridgeExtractOneDeck(container, staging, cards, callback)
    if container == nil then callback(false, "physical deck disappeared during bootstrap"); return end
    if container.tag == "Card" then table.insert(cards, container); callback(true, nil); return end
    if container.tag ~= "Deck" then callback(false, "expected a Card or Deck while extracting assets"); return end

    local contents = container.getObjects() or {}
    if #contents == 0 then callback(false, "physical deck reported no card contents"); return end
    if #contents == 1 then
        local remainder = getObjectFromGUID(contents[1].guid)
        if remainder ~= nil then table.insert(cards, remainder); callback(true, nil)
        else callback(false, "could not resolve final card in physical deck") end
        return
    end

    local take = contents[1]
    local remainderGuid = #contents == 2 and contents[2].guid or nil
    container.takeObject({
        guid = take.guid,
        position = {staging.x + (#cards % 10) * 0.7, staging.y, staging.z + math.floor(#cards / 10) * 0.9},
        smooth = false,
        callback_function = function(card)
            table.insert(cards, card)
            Wait.frames(function()
                if remainderGuid ~= nil then
                    local remainder = getObjectFromGUID(remainderGuid)
                    if remainder == nil then callback(false, "physical deck remainder disappeared")
                    else table.insert(cards, remainder); callback(true, nil) end
                else
                    BridgeExtractOneDeck(container, staging, cards, callback)
                end
            end, 2)
        end
    })
end

function BridgeReconcileSeatSnapshot(seatSnapshot, assets)
    local byName = {}
    for _, object in ipairs(assets) do
        local name = BridgeNormalizeCardName(object.getName())
        byName[name] = byName[name] or {}
        table.insert(byName[name], object)
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
            local object = table.remove(candidates, 1)
            local guid = object.getGUID()
            BridgeState.physicalByInstanceId[card.cardInstanceId] = guid
            BridgeState.physicalSeatByGuid[guid] = seatSnapshot.seatId
            BridgeState.physicalZoneByGuid[guid] = zone.name
            BridgeState.untappedRotationByGuid[guid] = object.getRotation()
            BridgePlaceSnapshotCard(object, card, zone, seatSnapshot)
        end
    end
    return true, nil
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
    if zone.name == "hand" then
        local hand = Player[seat.ttsColor].getHandTransform(1)
        object.use_hands = true
        object.setPosition({hand.position.x + (card.zonePosition - (#zone.cards - 1) / 2) * 1.2, hand.position.y, hand.position.z})
        return
    end
    object.use_hands = false
    local anchor = seat.battlefieldAnchors.creature
    if zone.name == "battlefield" then
        object.setPosition({anchor.x + card.zonePosition * 1.4, anchor.y, anchor.z})
    elseif zone.name == "graveyard" then
        object.setPosition({anchor.x + 8, anchor.y, anchor.z})
    elseif zone.name == "exile" then
        object.setPosition({anchor.x + 10, anchor.y, anchor.z})
    end
end

function BridgeApplySeatSnapshotVisualState(seatSnapshot)
    local seat = BRIDGE_SEATS[seatSnapshot.seatId]
    local lifeCounter = getObjectFromGUID(seat.lifeCounterGuid)
    if lifeCounter ~= nil then lifeCounter.setValue(seatSnapshot.life) end
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

function BridgeStartEventPolling(sessionId, skipExisting)
    if sessionId == nil then
        BridgeStopOnDesync("cannot poll events without a sessionId")
        return
    end

    if BridgeState.eventSessionId == sessionId and BridgeState.eventPolling then
        return
    end

    if BridgeState.eventSessionId ~= sessionId then
        BridgeStopEventPolling()
        BridgeState.eventSessionId = sessionId
        BridgeState.lastReceivedEventSequence = 0
        BridgeState.lastAppliedEventSequence = 0
        BridgeState.eventQueue = {}
        BridgeState.animationRunning = false
        BridgeState.physicalByInstanceId = {}
        BridgeState.physicalSeatByGuid = {}
        BridgeState.physicalZoneByGuid = {}
        BridgeState.battlefieldCounts = {}
        BridgeState.counterStateByInstanceId = {}
        BridgeState.keywordStateByInstanceId = {}
        BridgeState.untappedRotationByGuid = {}
        BridgeState.snapshotForgeSequence = 0
        BridgeState.yieldSeatId = nil
    end

    BridgeState.skipExistingEventsOnAttach = skipExisting == true
    BridgeState.eventPolling = true
    BridgeState.eventRetryCount = 0
    BridgeState.eventPollGeneration = BridgeState.eventPollGeneration + 1
    BridgePollEvents(BridgeState.eventPollGeneration)
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
        Turns.turn_color = seat.ttsColor
        if BridgeState.yieldSeatId ~= nil and BridgeState.yieldSeatId ~= event.seatId then
            BridgeState.yieldSeatId = nil
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

    if event.kind == "draw" then
        local applied, drawError = BridgeApplyStructuredCardMove(event)
        return applied, 1.25, drawError
    end

    if event.kind == "card_moved" then
        local applied, moveError = BridgeApplyStructuredCardMove(event)
        return applied, 1.0, moveError
    end

    if event.kind == "tap_changed" then
        local object, resolveError = BridgeResolveMappedInstance(event)
        if object == nil then return false, 0, resolveError end
        BridgeSetPhysicalTapped(object, event.tapped == true)
        return true, 0.5
    end

    if event.kind == "counter_changed" then
        local object, resolveError = BridgeResolveMappedInstance(event)
        if object == nil then return false, 0, resolveError end
        local applied, counterError = BridgeSetCardCounterState(object, event.counterType, event.counterValue)
        return applied, 0.1, counterError
    end

    if event.kind == "keyword_added" or event.kind == "keyword_removed" then
        local object, resolveError = BridgeResolveMappedInstance(event)
        if object == nil then return false, 0, resolveError end
        local applied, keywordError = BridgeSetCardKeywordState(object, event.keyword, event.kind == "keyword_added")
        return applied, 0.1, keywordError
    end

    if not seat.animateAuthoritativeEvents then
        if event.kind == "land_played" and event.cardInstanceId ~= nil then
            local object, resolveError = BridgeResolvePhysicalCard(event, "battlefield")
            if object == nil then return false, 0, resolveError end
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
        local object, resolveError = BridgeResolvePhysicalCard(event, "hand")
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
        local position = object.getPosition()
        local towardCenter = BridgeUnitTowardTableCenter(position)
        object.setPositionSmooth({position.x + towardCenter.x * 2, position.y, position.z + towardCenter.z * 2}, false, true)
        object.highlightOn({1.0, 0.45, 0.0}, 2)
        return true, 1.0
    end

    return true, 0.1
end

function BridgeApplyStructuredCardMove(event)
    if event.cardInstanceId == nil then return false, "structured zone change has no cardInstanceId" end
    local guid = BridgeState.physicalByInstanceId[event.cardInstanceId]
    if guid == nil then return false, "no physical GUID mapped for authoritative instance " .. tostring(event.cardInstanceId) end
    local seat = BRIDGE_SEATS[event.seatId]
    if seat == nil then return false, "structured zone change has no configured seat" end

    local object = getObjectFromGUID(guid)
    if object == nil and event.sourceZone == "library" then
        local deck = BridgeFindDeckContainingGuid(guid)
        if deck == nil then return false, "mapped library card is not present in a physical deck" end
        local hand = Player[seat.ttsColor].getHandTransform(1)
        deck.takeObject({
            guid = guid,
            position = hand.position,
            smooth = true,
            callback_function = function(drawn)
                BridgeState.physicalByInstanceId[event.cardInstanceId] = drawn.getGUID()
                BridgeState.physicalSeatByGuid[drawn.getGUID()] = event.seatId
                BridgeState.physicalZoneByGuid[drawn.getGUID()] = event.destinationZone
                BridgeState.untappedRotationByGuid[drawn.getGUID()] = drawn.getRotation()
                drawn.use_hands = true
            end
        })
        return true, nil
    end
    if object == nil then return false, "mapped physical card is unavailable for structured zone change" end

    if event.destinationZone == "hand" then
        local hand = Player[seat.ttsColor].getHandTransform(1)
        object.use_hands = true
        object.setPositionSmooth(hand.position, false, true)
    elseif event.destinationZone == "battlefield" then
        local moved, moveError = BridgeMoveToBattlefield(event, object, "creature")
        if not moved then return false, moveError end
    elseif event.destinationZone == "stack" then
        object.use_hands = false
        object.setPositionSmooth({0, 2.5, seat.tableSideZ * 1.2}, false, true)
    elseif event.destinationZone == "graveyard" then
        local anchor = seat.battlefieldAnchors.creature
        object.use_hands = false
        object.setPositionSmooth({anchor.x + 8, anchor.y, anchor.z}, false, true)
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

function BridgeFindDeckContainingGuid(guid)
    for _, object in ipairs(getAllObjects()) do
        if object.tag == "Deck" then
            for _, card in ipairs(object.getObjects() or {}) do
                if card.guid == guid then return object end
            end
        end
    end
    return nil
end

function BridgeSetPhysicalTapped(object, tapped)
    local guid = object.getGUID()
    local base = BridgeState.untappedRotationByGuid[guid]
    if base == nil then
        base = object.getRotation()
        BridgeState.untappedRotationByGuid[guid] = base
    end
    local targetZ = base.z + (tapped and 90 or 0)
    object.setRotationSmooth({base.x, base.y, targetZ}, false, true)
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
            return existing, nil
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
    return {
        x = anchor.x + (count % 5) * 2.2,
        y = anchor.y,
        z = anchor.z
    }, nil
end

function BridgeUnitTowardTableCenter(position)
    local length = math.sqrt(position.x * position.x + position.z * position.z)
    if length < 0.01 then
        return {x = 0, z = 1}
    end
    return {x = -position.x / length, z = -position.z / length}
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
