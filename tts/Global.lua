BRIDGE_BASE_URL = "http://127.0.0.1:43110"
BRIDGE_STACK_POSITION = {x = -5.5, y = 1.6, z = 0}
BRIDGE_MANA_COUNTER_SOURCES = {
    W = "cd8bb6", U = "4783af", B = "1c4a59",
    R = "220d2f", G = "cdbccc", C = "aeeb11"
}
BRIDGE_MANA_COLORS = {"W", "U", "B", "R", "G", "C"}
BRIDGE_EVENT_POLL_INTERVAL_IDLE = 1.0
BRIDGE_EVENT_POLL_INTERVAL_ACTIVE = 0.12
BRIDGE_DECISION_DEFER_STALL_SECONDS = 0.6

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
        faceUpRotation = {x = 0, y = 180, z = 0},
        graveyardZoneGuid = nil,
        exileZoneGuid = nil,
        graveyardAnchor = {x = 4.5, y = 2.0, z = -13.8},
        exileAnchor = {x = 10.8, y = 2.0, z = -13.8},
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
        faceUpRotation = {x = 0, y = 0, z = 0},
        graveyardZoneGuid = nil,
        exileZoneGuid = nil,
        graveyardAnchor = {x = 4.5, y = 2.0, z = 13.8},
        exileAnchor = {x = 10.8, y = 2.0, z = 13.8},
        includeCardGuids = {},
        excludeCardGuids = {},
        battlefieldAnchors = {
            land = {x = 6.5, y = 2.0, z = 11.5},
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
    resetConfirmationGuid = nil,
    selectedActionIds = {},
    selectedGuidByActionId = {},
    selectionDecisionId = nil,
    selectionControlGuids = {},
    optionControlGuids = {},
    optionControlDecisionId = nil,
    attackOriginByGuid = {},
    attackLaneGuidBySeatId = {},
    manaCounterGuidBySeatId = {},
    submitting = false,
    pendingIntent = nil,
    pendingDecision = nil,
    pendingDecisionDeferredAt = nil,
    pendingDecisionDeferredCursor = 0,
    pendingDecisionDeferredApplied = 0,
    eventSessionId = nil,
    lastReceivedEventSequence = 0,
    lastAppliedEventSequence = 0,
    eventPolling = false,
    eventPollGeneration = 0,
    eventRequestInFlight = false,
    eventPollScheduled = false,
    decisionPollGeneration = 0,
    decisionPollInFlight = false,
    decisionPollScheduled = false,
    eventRetryCount = 0,
    skipExistingEventsOnAttach = false,
    eventQueue = {},
    animationRunning = false,
    physicalByInstanceId = {},
    physicalInstanceIdByGuid = {},
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
    deferredSnapshotReconcile = nil,
    -- A textual semantic event (such as land_played) can immediately follow
    -- the same exact structured card_moved event.  Keep the exact transition
    -- identity so the second renderer never treats a temporarily unresolved
    -- first renderer as a name-based physical desync.
    pendingStructuredZoneTransitionByInstanceId = {},
    zoneAnchorGuidBySeatAndZone = {},
    bootstrapping = false,
    setupBusy = false,
    doctorInitializedUi = false,
    doctorRetryAttempt = 0,
    transitionExpectedUntil = 0,
    latencyProbe = nil,
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

function BridgeSafeObjectName(object)
    if not BridgeObjectIsUsable(object) then return nil end
    local ok, name = pcall(function() return object.getName() end)
    if not ok then return nil end
    return tostring(name or "")
end

function BridgeSafeObjectCall(object, action)
    if not BridgeObjectIsUsable(object) or action == nil then return false end
    local ok = pcall(action, object)
    return ok
end

function BridgeRecordLooseCardIdentity(cardInstanceId, guid, seatId, zoneName)
    if cardInstanceId ~= nil then
        local previousGuid = BridgeState.physicalByInstanceId[cardInstanceId]
        if previousGuid ~= nil and previousGuid ~= guid then
            BridgeState.physicalInstanceIdByGuid[previousGuid] = nil
        end
        local previousInstanceId = BridgeState.physicalInstanceIdByGuid[guid]
        if previousInstanceId ~= nil and previousInstanceId ~= cardInstanceId then
            BridgeState.physicalByInstanceId[previousInstanceId] = nil
        end
        BridgeState.physicalByInstanceId[cardInstanceId] = guid
        BridgeState.physicalInstanceIdByGuid[guid] = cardInstanceId
    end
    BridgeState.physicalSeatByGuid[guid] = seatId
    BridgeState.physicalZoneByGuid[guid] = zoneName
end

function BridgeRecordLibraryContainedState(cardInstanceId, seatId, cardName)
    if cardInstanceId == nil then return end
    local existingGuid = BridgeState.physicalByInstanceId[cardInstanceId]
    if existingGuid ~= nil then
        BridgeState.physicalInstanceIdByGuid[existingGuid] = nil
        BridgeState.physicalSeatByGuid[existingGuid] = nil
        BridgeState.physicalZoneByGuid[existingGuid] = nil
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
    print(message)
    pcall(function() log(message) end)
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
    if seat == nil then
        return nil, "unknown configured seat " .. tostring(seatId)
    end
    local color = seat.ttsColor
    if color == nil or color == "" then
        return nil, "seat " .. tostring(seatId) .. " has no configured TTS color"
    end
    local player = Player[color]
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

    local expectedBySeat = context and context.expectedCardNamesBySeat or nil
    local expectedNames = expectedBySeat and expectedBySeat[seatId] or nil
    if expectedNames ~= nil and next(expectedNames) ~= nil then
        local normalized = BridgeNormalizeCardName(BridgeSafeObjectName(object))
        return expectedNames[normalized] == true
    end

    local handGuidsBySeat = context and context.handGuidsBySeat or nil
    local seatHandGuids = handGuidsBySeat and handGuidsBySeat[seatId] or nil
    if seatHandGuids == nil then
        seatHandGuids = BridgeBuildSeatHandGuidSet(seatId)
        if handGuidsBySeat ~= nil then handGuidsBySeat[seatId] = seatHandGuids end
    end
    if seatHandGuids ~= nil and seatHandGuids[guid] == true then
        return true
    end

    if not BridgeObjectIsOnSeatSide(object, seat) then
        return false
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

function BridgeFindLibraryDeckCandidatesForSeat(seatId)
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then return {} end
    local candidates = {}
    for _, object in ipairs(getAllObjects()) do
        if BridgeObjectIsUsable(object) and object.tag == "Deck" and BridgeObjectIsOnSeatSide(object, seat) then
            table.insert(candidates, object)
        end
    end
    return candidates
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

function BridgeResolveSeatLibraryDeck(seatId)
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then return nil, {}, "unknown seat" end
    local candidates = BridgeFindLibraryDeckCandidatesForSeat(seatId)

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
        return nil, candidates, "no deck candidates found near library anchor"
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
    BridgeState.optionControlGuids = {}
    BridgeState.optionControlDecisionId = nil
    BridgeState.setupObjectGuidByKind = {}
    BridgeState.resetConfirmationArmed = false
    BridgeState.resetConfirmationGuid = nil
end

function BridgeFindNamedObject(name)
    for _, object in _ip(_all()) do
        if BridgeObjectIsUsable(object) then
            if BridgeSafeObjectName(object) == name then return object end
        end
    end
    return nil
end

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

function BridgeStagePhysicalCardForBootstrap(object, seatId, stagedBySeat)
    if not BridgeObjectIsUsable(object) then return false end
    local seat = seatId and BRIDGE_SEATS[seatId] or nil
    if seat == nil then return false end
    local staging = BridgeLibraryStagingPosition(seat, stagedBySeat, seatId)
    if staging == nil then return false end
    local staged = BridgeSafeObjectCall(object, function(o)
        o.use_hands = false
        BridgeSetPhysicalFaceDown(o, seat, true)
        o.setPosition(staging)
    end)
    return staged
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

function BridgeStageSeatCardsForBootstrap(snapshot)
    BridgeTraceStart("START-13 loose-card-staging")
    local knownSeatIds = {}
    local knownSeatIdSet = {}
    local context = BridgeBuildGameCardContext(snapshot)
    for _, seatSnapshot in ipairs(snapshot.seats or {}) do
        table.insert(knownSeatIds, seatSnapshot.seatId)
        knownSeatIdSet[seatSnapshot.seatId] = true
    end

    local stagedBySeat = {}
    local stagedCount = 0
    for seatId, seat in pairs(BRIDGE_SEATS) do
        local handObjects, handError = BridgeTryGetSeatHandObjects(seatId)
        if handObjects == nil then
            return false, handError
        end
        context.handGuidsBySeat[seatId] = BridgeBuildSeatHandGuidSet(seatId)
        for _, object in ipairs(handObjects) do
            if IsGameCardCandidate(object, seatId, context)
                and BridgeStagePhysicalCardForBootstrap(object, seatId, stagedBySeat) then
                stagedCount = stagedCount + 1
            end
        end
    end

    for _, object in ipairs(getAllObjects()) do
        if BridgeObjectIsUsable(object) and object.tag == "Card" then
            local seatId = BridgeSeatIdForObjectSide(object)
            if seatId == nil or not knownSeatIdSet[seatId] then
                local ok, position = pcall(function() return object.getPosition() end)
                if ok and position ~= nil then
                    seatId = BridgeNearestSeatIdForPosition(position, knownSeatIds)
                end
            end
            if seatId ~= nil
                and IsGameCardCandidate(object, seatId, context)
                and BridgeStagePhysicalCardForBootstrap(object, seatId, stagedBySeat) then
                stagedCount = stagedCount + 1
            end
        end
    end

    if stagedCount > 0 then
        print("[Bridge] staged " .. tostring(stagedCount) .. " loose card(s) near library before authoritative bootstrap")
    end
    return true, nil
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
            BridgeState.pendingDecision = nil
            BridgeState.pendingDecisionDeferredAt = nil
            BridgeState.pendingDecisionDeferredCursor = 0
            BridgeState.pendingDecisionDeferredApplied = 0
            BridgeClearHighlights()
            BridgeResetSelectionState()
            BridgeHideMainPriorityControls()
        end

        callback(ok, body, err, request)
    end)
end

function BridgeStopDecisionPolling()
    BridgeState.decisionPollGeneration = BridgeState.decisionPollGeneration + 1
    BridgeState.decisionPollInFlight = false
    BridgeState.decisionPollScheduled = false
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
    print(string.format(
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

function BridgeScheduleDecisionPoll(delay, generation, attempt)
    if generation ~= BridgeState.decisionPollGeneration then return end
    if BridgeState.lastDecision ~= nil or BridgeState.submitting then return end
    if BridgeState.decisionPollInFlight or BridgeState.decisionPollScheduled then return end

    BridgeState.decisionPollScheduled = true
    Wait.time(function()
        if generation ~= BridgeState.decisionPollGeneration then return end
        BridgeState.decisionPollScheduled = false
        BridgePollForNextDecision(generation, attempt)
    end, delay)
end

function BridgePollForNextDecision(generation, attempt)
    if generation ~= BridgeState.decisionPollGeneration then return end
    if BridgeState.lastDecision ~= nil or BridgeState.submitting then return end
    if BridgeState.decisionPollInFlight then return end

    BridgeState.decisionPollInFlight = true
    BridgeHttp.requestJson("GET", "/api/v1/decision", nil, function(ok, body, err, request)
        if generation ~= BridgeState.decisionPollGeneration then return end

        BridgeState.decisionPollInFlight = false
        if ok and body ~= nil then
            BridgeState.lastDecision = body
            BridgeMarkTransitionExpected(0)
            BridgeRecordLatencyProbeDecisionReady(body)
            printDecision(body)
            return
        end

        local responseCode = request and tonumber(request.response_code) or nil
        local noPendingDecision = (body ~= nil and body.errorCode == "no_pending_decision") or responseCode == 404
        if noPendingDecision then
            if attempt == 1 or attempt % 10 == 0 then
                print("[Bridge] waiting for Forge's next decision...")
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
            BridgeScheduleDecisionPoll(retryDelay, generation, attempt + 1)
            return
        end

        BridgeShowError("decision poll failed: " .. tostring(err))
        BridgeScheduleDecisionPoll(1.0, generation, attempt + 1)
    end)
end

function BridgeStartDecisionPolling()
    BridgeStopDecisionPolling()
    BridgeScheduleDecisionPoll(BridgeTransitionExpected() and 0.1 or 0.25, BridgeState.decisionPollGeneration, 1)
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

    BridgeState.pendingDecision = nil
    BridgeState.pendingDecisionDeferredAt = nil
    BridgeState.pendingDecisionDeferredCursor = 0
    BridgeState.pendingDecisionDeferredApplied = 0
    BridgeState.submitting = true
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
    BridgeHttp.requestJson("POST", "/api/v1/choice", payload, function(ok, body, err)
        BridgeState.submitting = false
        if not ok then
            BridgeState.latencyProbe = nil
            BridgeMarkTransitionExpected(0)
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
        local probe = BridgeState.latencyProbe
        if probe ~= nil then
            probe.acceptedAt = os.clock()
            local submitMs = math.floor((probe.acceptedAt - probe.submittedAt) * 1000)
            print(string.format("[Bridge latency] choice POST accepted in %dms (action=%s)", submitMs, tostring(actionId)))
        end
        BridgeMarkTransitionExpected(2.5)
        BridgeScheduleEventPoll(0.05, BridgeState.eventPollGeneration)

        if body ~= nil and body.committedEvent ~= nil then
            print("[Bridge] committed: " .. tostring(body.committedEvent.summary))
        end

        if body ~= nil and body.currentDecision ~= nil then
            BridgeStopDecisionPolling()
            BridgeState.lastDecision = body.currentDecision
            BridgeMarkTransitionExpected(0)
            BridgeRecordLatencyProbeDecisionReady(body.currentDecision)
            printDecision(body.currentDecision)
        else
            BridgeState.lastDecision = nil
            BridgeClearHighlights()
            BridgeHideMainPriorityControls()
            print("[Bridge] no pending decision.")
            BridgeStartDecisionPolling()
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

function BridgeDecisionOffersActionType(decision, actionType)
    for _, action in ipairs(decision.actions or {}) do
        if action.type == actionType then return true end
    end
    return false
end

function BridgeShouldIgnoreStaleDecision(decision)
    local eventCursor = tonumber(decision and decision.eventCursor or 0) or 0
    local applied = tonumber(BridgeState.lastAppliedEventSequence or 0) or 0
    if eventCursor <= 0 or eventCursor >= applied then
        return false, eventCursor, applied
    end

    if decision.kind ~= "main_priority" then
        -- Combat/target decisions can arrive after additional phase events; they
        -- remain valid and suppressing them causes interaction softlocks.
        return false, eventCursor, applied
    end

    local decisionTurn = tonumber(decision.turnNumber or 0) or 0
    local tableTurn = tonumber(BridgeState.tableTurnCount or 0) or 0
    if decisionTurn > 0 and tableTurn > 0 and decisionTurn < tableTurn then
        return true, eventCursor, applied
    end

    local stalePrioritySeat = decision.prioritySeatId ~= nil
        and decision.seatId ~= nil
        and decision.prioritySeatId ~= decision.seatId
    local activeMismatch = decision.activeSeatId ~= nil
        and BridgeState.currentTurnSeatId ~= nil
        and decision.activeSeatId ~= BridgeState.currentTurnSeatId
    local staleLandWindow = BridgeDecisionOffersActionType(decision, "play_land")
        and ((BridgeState.currentTurnSeatId ~= nil and decision.seatId ~= BridgeState.currentTurnSeatId)
            or (decision.activeSeatId ~= nil and decision.activeSeatId ~= decision.seatId))
    if stalePrioritySeat or activeMismatch or staleLandWindow then
        return true, eventCursor, applied
    end

    return false, eventCursor, applied
end

function BridgeShouldDeferDecision(decision)
    local eventCursor = tonumber(decision and decision.eventCursor or 0) or 0
    local applied = tonumber(BridgeState.lastAppliedEventSequence or 0) or 0
    if eventCursor <= 0 then return false, eventCursor, applied end
    return eventCursor > applied, eventCursor, applied
end

function BridgeTryPresentPendingDecision(reason)
    if BridgeState.pendingDecision == nil or BridgeState.submitting then return end
    local pending = BridgeState.pendingDecision
    local defer, eventCursor, applied = BridgeShouldDeferDecision(pending)
    if defer then
        local deferredAt = tonumber(BridgeState.pendingDecisionDeferredAt or 0) or 0
        if deferredAt <= 0 then deferredAt = os.clock() end
        local elapsed = os.clock() - deferredAt
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
            print(string.format(
                "[Bridge] dropping stale deferred decision %s after %.1fs wait (cursor=%s applied=%s)",
                tostring(pending.decisionId), elapsed, tostring(eventCursor), tostring(applied)))
            BridgeState.pendingDecision = nil
            BridgeState.pendingDecisionDeferredAt = nil
            BridgeState.pendingDecisionDeferredCursor = 0
            BridgeState.pendingDecisionDeferredApplied = 0
            return
        end
        print(string.format(
            "[Bridge] forcing deferred decision %s after %.1fs with unchanged cursor/applied (%s/%s)",
            tostring(pending.decisionId), elapsed, tostring(eventCursor), tostring(applied)))
    end
    local decision = BridgeState.pendingDecision
    BridgeState.pendingDecision = nil
    BridgeState.pendingDecisionDeferredAt = nil
    BridgeState.pendingDecisionDeferredCursor = 0
    BridgeState.pendingDecisionDeferredApplied = 0
    print(string.format(
        "[Bridge] releasing gated decision %s (%s) cursor=%s applied=%s",
        tostring(decision.decisionId), tostring(reason or "event"),
        tostring(eventCursor), tostring(applied)))
    printDecision(decision)
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
end

function BridgeCanDeferStructuredMoveToSnapshot(event)
    local destinationZone = string.lower(tostring(event.destinationZone or ""))
    return event.kind == "card_moved" and BridgeZoneIsPublicForReconcile(destinationZone)
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
    print(string.format(
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

function BridgeApplySafeSnapshotReconcile(snapshot, reason)
    local movedCount = 0
    for _, seatSnapshot in ipairs(snapshot.seats or {}) do
        BridgeApplySeatSnapshotVisualState(seatSnapshot)
        for _, zone in ipairs(seatSnapshot.zones or {}) do
            local zoneName = string.lower(tostring(zone.name or ""))
            if BridgeZoneIsPublicForReconcile(zoneName) then
                for _, card in ipairs(zone.cards or {}) do
                    local mappedGuid = BridgeState.physicalByInstanceId[card.cardInstanceId]
                    local mappedObject = mappedGuid and getObjectFromGUID(mappedGuid) or nil
                    local mappedZone = mappedGuid and BridgeState.physicalZoneByGuid[mappedGuid] or nil
                    local mappedNeedsFix = mappedObject == nil or mappedObject.tag ~= "Card" or mappedZone ~= zoneName
                    if mappedNeedsFix then
                        -- The log intentionally omits cardName: a snapshot can
                        -- contain identities that should not be public chat.
                        print(string.format(
                            "[Bridge] snapshot candidate instance=%s oldZone=%s destinationZone=%s",
                            tostring(card.cardInstanceId), tostring(mappedZone), tostring(zoneName)))
                        local evt = {
                            seatId = seatSnapshot.seatId,
                            cardInstanceId = card.cardInstanceId,
                            cardName = card.cardName,
                            sourceZone = nil,
                            destinationZone = zoneName,
                            faceDown = card.faceDown
                        }
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
    BridgeLogSnapshotOrdering("applied", snapshot, reason)
    if movedCount > 0 then
        print(string.format("[Bridge] snapshot reconcile (%s): corrected %d public card location(s)", tostring(reason), movedCount))
    end
end

function BridgeTryApplyDeferredSnapshotReconcile(reason)
    local pending = BridgeState.deferredSnapshotReconcile
    if pending == nil or not BridgeSnapshotMayMutatePublicZones(pending.snapshot) then return end
    BridgeState.deferredSnapshotReconcile = nil
    BridgeState.pendingStructuredZoneTransitionByInstanceId = {}
    BridgeApplySafeSnapshotReconcile(pending.snapshot, pending.reason or reason or "deferred")
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
            if BridgeSnapshotMayMutatePublicZones(snapshot) then
                BridgeApplySafeSnapshotReconcile(snapshot, reason)
            else
                BridgeState.deferredSnapshotReconcile = {snapshot = snapshot, reason = reason}
                BridgeLogSnapshotOrdering("deferred", snapshot, reason)
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
    print(string.format(
        "[BridgeDoctor] PASS=%d WARN=%d FAIL=%d",
        tonumber(report.pass or 0), tonumber(report.warn or 0), tonumber(report.fail or 0)))
    for _, check in ipairs(report.checks or {}) do
        print(string.format("[BridgeDoctor] %-4s %s :: %s", check.status, check.name, check.detail))
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

        BridgeDoctorCheckTable(report, body)
        BridgeDoctorPrintReport(report)
        if done ~= nil then done(report) end
    end)
end

function BridgeInitializeInteractiveUi()
    if BridgeState.doctorInitializedUi then return end
    BridgeState.doctorInitializedUi = true
    Wait.frames(function()
        BridgeTryStartupStep("destroy_transient_controls", BridgeDestroyTransientControls)
        BridgeTryStartupStep("ensure_setup_controls", BridgeEnsureSetupControls)
        BridgeTryStartupStep("ensure_turn_counters", BridgeEnsureTurnCounters)
        BridgeTryStartupStep("ensure_status_panel", BridgeEnsureStatusPanel)
        BridgeTryStartupStep("show_preparation_readiness", BridgeShowPreparationReadiness)
    end, 30)
end

function BridgeScheduleCompanionRetry(attempt)
    if BridgeState.doctorInitializedUi then return end
    local currentAttempt = tonumber(attempt or 1) or 1
    BridgeState.doctorRetryAttempt = currentAttempt
    Wait.time(function()
        if BridgeState.doctorInitializedUi then return end
        BridgeGetHealth(function(ok, body, err)
            if ok and body ~= nil then
                print("[Bridge] companion became reachable; initializing controls.")
                BridgeInitializeInteractiveUi()
                return
            end
            if currentAttempt == 1 or currentAttempt % 6 == 0 then
                print("[Bridge] companion still offline; retrying health in 5s (" .. tostring(currentAttempt) .. ")")
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
    -- This integration does not use Global XML UI; clear stale/broken XML left in saves.
    pcall(function() UI.setXml("") end)
    print("[Bridge] ForgeBot integration loaded.")
    BridgeSetStatus("CLIENT LOADED", "Running ForgeBot preflight...")
    BridgeDoctor(function(report)
        if report.companionOk then
            BridgeInitializeInteractiveUi()
        else
            BridgeSetStatus("COMPANION OFFLINE", "Bridge unreachable at 127.0.0.1:43110")
            print("[Bridge] companion unavailable on load; skipping bootstrap and waiting for retry.")
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
            print("[Bridge] preparation: companion unavailable: " .. tostring(err))
            return
        end
        local humanDeck, humanCandidates = BridgeResolveSeatLibraryDeck("forge-player-1")
        local aiDeck, aiCandidates = BridgeResolveSeatLibraryDeck("forge-player-2")
        local humanDeckOk = humanDeck ~= nil and #humanCandidates <= 1
        local aiDeckOk = aiDeck ~= nil and #aiCandidates <= 1
        print(string.format(
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
    Wait.frames(function()
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
    BridgeSetSetupBusy(true, "Forge match is loading; START and RESUME are temporarily disabled.")
    BridgeTraceStart("START-03 health-request")
    BridgeGetHealth(function(ok, body, err)
        BridgeRunTraced("START-04 health-response", function()
            BridgeTraceStart("START-04 health-response", ok and "ok" or tostring(err))
            if not ok then BridgeSetSetupBusy(false); BridgeShowError("cannot start: companion unavailable: " .. tostring(err)); return end
            if body.adapterState == "starting" then
                BridgeSetSetupBusy(true, "Forge is still initializing; wait for startup to finish before starting a new match.")
                BridgeSetStatus("FORGE INITIALIZING", "Loading Forge card database")
                return
            end
            local active = body.sessionId ~= nil and body.sessionId ~= "session-not-started"
                and body.adapterState ~= "not_started" and body.adapterState ~= "failed"
            if active then BridgeSetSetupBusy(false); BridgeShowError("a Forge match already exists; use RESUME or explicitly choose NEW MATCH"); return end
            BridgeTraceStart("START-05 deck-check-begin")
            local humanDeck, humanCandidates = BridgeResolveSeatLibraryDeck("forge-player-1")
            local aiDeck, aiCandidates = BridgeResolveSeatLibraryDeck("forge-player-2")
            if humanDeck == nil or aiDeck == nil or #humanCandidates > 1 or #aiCandidates > 1 then
                BridgeSetSetupBusy(false)
                BridgeShowError("both physical library decks must be uniquely identifiable before START")
                return
            end
            BridgeTraceStart("START-06 deck-check-complete")
            BridgeStartSessionIfNone(function() BridgeSetSetupBusy(false) end)
        end)
    end)
end

function BridgePressResume(object, playerColor, altClick)
    local color = playerColor
    local alt = altClick == true
    Wait.frames(function()
        BridgeDoPressResume(color, alt)
    end, 1)
end

function BridgeDoPressResume(playerColor, altClick)
    if BridgeState.setupBusy then
        BridgeShowError("Forge is still initializing; wait for the loading controls to finish")
        return
    end
    BridgeSetSetupBusy(true, "Checking the active Forge match; RESUME is temporarily disabled.")
    BridgeAttachToActiveSession(function() BridgeSetSetupBusy(false) end)
end

function BridgePressNewMatch(object, playerColor, altClick)
    local color = playerColor
    local alt = altClick == true
    print("setup-click:new-match")
    Wait.frames(function()
        BridgeDoPressNewMatch(color, alt)
    end, 1)
end

function BridgeDoPressNewMatch(playerColor, altClick)
    print("setup-deferred:new-match")
    if BridgeState.setupBusy then
        BridgeShowError("Forge is still initializing; wait for the loading controls to finish")
        return
    end
    BridgeState.resetConfirmationArmed = true
    BridgeClearResetConfirmationControl()
    BridgeSpawnResetConfirmationControl()
    broadcastToAll("[Bridge] NEW MATCH is destructive. Click it again within 10 seconds to confirm.", {1.0, 0.55, 0.1})
    Wait.time(function()
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
            Wait.frames(function()
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
                print("setup-confirm-spawned")
            end, 1)
        end
    })
end

function BridgePressConfirmNewMatch(object, playerColor, altClick)
    local color = playerColor
    local alt = altClick == true
    print("setup-click:confirm")
    Wait.frames(function()
        BridgeDoPressConfirmNewMatch(color, alt)
    end, 1)
end

function BridgeDoPressConfirmNewMatch(playerColor, altClick)
    print("setup-deferred:confirm")
    if BridgeState.setupBusy then
        BridgeShowError("Forge is still initializing; wait for the loading controls to finish")
        return
    end
    if not BridgeState.resetConfirmationArmed then
        BridgeShowError("NEW MATCH confirmation expired; click NEW MATCH again")
        BridgeClearResetConfirmationControl()
        return
    end
    BridgeState.resetConfirmationArmed = false
    BridgeClearResetConfirmationControl()
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

        BridgeHideMainPriorityControls()
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

    BridgeTraceStart("START-07 session-start-request")
    BridgeStartSession(function(ok, body, err)
        BridgeRunTraced("START-08 session-start-response", function()
            BridgeTraceStart("START-08 session-start-response", ok and tostring(body and body.sessionId or "ok") or tostring(err))
            if not ok then
                if done then done() end
                BridgeShowError("session start failed: " .. tostring(err))
                return
            end

            print("[Bridge] started or attached session: " .. tostring(body and body.sessionId))
            -- The start route may attach to a match that already exists. Do not replay
            -- its historical physical events; an explicit reset is the new-match path.
            BridgeBootstrapWhenAvailable(body.sessionId, 1, function(bootstrapOk, bootstrapError)
                BridgeRunTraced("START bootstrap-callback", function()
                    if not bootstrapOk then if done then done() end; BridgeStopOnDesync(bootstrapError); return end
                    BridgeTraceStart("START-18 event-poll-start")
                    BridgeStartEventPolling(body.sessionId, true)
                    BridgeTraceStart("START-19 decision-poll-start")
                    if body ~= nil and body.currentDecision ~= nil then printDecision(body.currentDecision)
                    else BridgeRefreshDecision() end
                    BridgeTraceStart("START-20 ready")
                    if done then done() end
                end)
            end)
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

    local ignoreStale, eventCursor, applied = BridgeShouldIgnoreStaleDecision(decision)
    if ignoreStale then
        print(string.format(
            "[Bridge] ignoring stale main-priority decision %s (cursor=%s, applied=%s)",
            tostring(decision.decisionId), tostring(eventCursor), tostring(applied)))
        return
    end

    local deferDecision, deferCursor, deferApplied = BridgeShouldDeferDecision(decision)
    if deferDecision then
        BridgeState.pendingDecision = decision
        BridgeState.lastDecision = decision
        BridgeState.pendingDecisionDeferredAt = os.clock()
        BridgeState.pendingDecisionDeferredCursor = deferCursor
        BridgeState.pendingDecisionDeferredApplied = deferApplied
        BridgeClearHighlights()
        BridgeResetSelectionState()
        BridgeHideMainPriorityControls()
        print(string.format(
            "[Bridge] gating decision %s until events catch up (cursor=%s, applied=%s)",
            tostring(decision.decisionId), tostring(deferCursor), tostring(deferApplied)))
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
    elseif decision.kind == "blocker_assignment" then
        BridgeSetStatus("ASSIGN BLOCKERS", "Choose which attacker each blocker will block\nDONE ASSIGNING")
    elseif decision.kind == "target_selection" or decision.kind == "defender_selection" then
        BridgeSetStatus("CHOOSE TARGET", BridgeTurnLabel() .. " - " .. tostring(actor) .. " priority")
    elseif decision.kind == "generic_numeric_selection" then
        BridgeSetStatus("CHOOSE OPTION", BridgeTurnLabel() .. " - " .. tostring(actor) .. " priority")
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
    local highlighted = BridgeState.highlightedGuids or {}
    for _, guid in _ip(highlighted) do
        local object = BridgeGetLiveObjectByGuid(guid)
        if object ~= nil then BridgeSafeObjectCall(object, function(o) o.highlightOff() end) end
    end

    local targetButtons = BridgeState.targetButtonIndexByGuid or {}
    for guid, buttonIndex in _pairs(targetButtons) do
        local object = BridgeGetLiveObjectByGuid(guid)
        if object ~= nil then BridgeSafeObjectCall(object, function(o) o.removeButton(buttonIndex) end) end
    end

    BridgeState.highlightedGuids = {}
    BridgeState.actionByGuid = {}
    BridgeState.targetButtonIndexByGuid = {}
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

function BridgeDecisionOptionLabel(action, index)
    local text = tostring(action.displayName or action.type or ("Option " .. tostring(index)))
    if #text > 34 then text = text:sub(1, 31) .. "..." end
    return "CHOOSE\n" .. text
end

function BridgeEnsureDecisionOptionControls(decision, representedActionIds)
    if decision == nil or decision.actions == nil then
        BridgeClearOptionControls()
        return
    end

    local unbound = {}
    local filters = representedActionIds or {}
    for _, action in _ip(decision.actions or {}) do
        local skip = filters[action.actionId] == true
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
                    label = BridgeDecisionOptionLabel(action, index),
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
    BridgeClearHighlights()
    BridgeResetSelectionState()
    BridgeSubmitChoice(decisionId, actionId)
end

function BridgeEnsureContextualCompletionControl(decision)
    if decision == nil or (decision.kind ~= "attacker_selection" and decision.kind ~= "blocker_selection" and decision.kind ~= "blocker_assignment") then return end
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
    BridgeClaimHumanTtsColor(decision.seatId, playerColor)
    BridgeClearHighlights()
    BridgeResetSelectionState()
    BridgeSubmitChoice(decisionId, actionId)
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
    if decision == nil or decision.kind ~= "main_priority" then
        BridgeHideMainPriorityControls()
        BridgeShowError("End Turn is unavailable while waiting for a Forge main-priority decision")
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
    BridgeSubmitChoice(decision.decisionId, action.actionId)
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
    BridgeClearOptionControls()
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
    -- Guard against dead object parameter from stale embedded button callbacks
    if object ~= nil then
        local ok = pcall(function() return object.getGUID() end)
        if not ok then return end
    end
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
    -- Guard against dead object parameter from stale embedded button callbacks
    if object ~= nil then
        local ok = pcall(function() return object.getGUID() end)
        if not ok then return end
    end
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

    if decision.kind == "main_priority" and BridgeDecisionOffersActionType(decision, "pass_priority") then
        BridgeEnsureEndTurnButton(decision.seatId)
        BridgeEnsurePassButton(decision.seatId)
    else
        BridgeHideMainPriorityControls()
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
    if decision.kind == "target_selection" or decision.kind == "defender_selection" or decision.kind == "blocker_selection" or decision.kind == "blocker_assignment" then
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
    for _, object in ipairs(getAllObjects()) do
        if object.tag == "Card" then
            local guid = BridgeSafeObjectGuid(object)
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
                BridgeState.physicalSeatByGuid[guid] = decision.seatId
                BridgeState.physicalZoneByGuid[guid] = "hand"
            end
            local isCandidate = decision.kind ~= "main_priority"
                or mappedInDecisionHand
                or observedInDecisionHand
            if isCandidate then
                table.insert(cards, object)
                if guid ~= nil then
                    candidateGuid[guid] = true
                end
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
                representedActionIds[action.actionId] = true
                table.insert(BridgeState.highlightedGuids, guid)
                BridgeInstallTargetButton(targetObject, action.targetSeatId)
            else
                BridgeShowError("no physical target surface configured for seat " .. tostring(action.targetSeatId))
            end
        end

        local matches = {}
        local mappedGuid = action.cardInstanceId and BridgeState.physicalByInstanceId[action.cardInstanceId] or nil
        local mappedObject = BridgeGetLiveObjectByGuid(mappedGuid)
        local mappedSeatMatches = mappedObject ~= nil and (decision.kind ~= "main_priority"
            or BridgeState.physicalSeatByGuid[mappedGuid] == decision.seatId)
        local mappedZoneMatches = decision.kind ~= "main_priority" or candidateGuid[mappedGuid] == true
        if mappedSeatMatches and mappedZoneMatches then
            table.insert(matches, mappedObject)
        else
            local fallbackMatches = {}
            for _, object in ipairs(cards) do
                if BridgeCardNameMatches(object.getName(), action.cardIdentity) then
                    table.insert(fallbackMatches, object)
                end
            end
            if action.cardInstanceId == nil then
                matches = fallbackMatches
            elseif #fallbackMatches == 1 then
                local recoveredGuid = BridgeSafeObjectGuid(fallbackMatches[1])
                if recoveredGuid ~= nil then
                    BridgeState.physicalByInstanceId[action.cardInstanceId] = recoveredGuid
                    BridgeState.physicalInstanceIdByGuid[recoveredGuid] = action.cardInstanceId
                    if action.cardIdentity ~= nil then
                        BridgeState.cardNameByInstanceId[action.cardInstanceId] = action.cardIdentity
                    end
                    BridgeState.physicalSeatByGuid[recoveredGuid] = decision.seatId
                    if decision.kind == "main_priority" then
                        BridgeState.physicalZoneByGuid[recoveredGuid] = "hand"
                    end
                    matches = fallbackMatches
                    print(string.format(
                        "[Bridge] repaired instance mapping for %s -> %s (%s)",
                        tostring(action.cardInstanceId), tostring(recoveredGuid), tostring(action.cardIdentity or action.type)))
                end
            elseif #fallbackMatches > 1 then
                print(string.format(
                    "[Bridge] instance mapping ambiguous for %s (%s): %d candidates",
                    tostring(action.cardInstanceId), tostring(action.cardIdentity or action.type), #fallbackMatches))
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
                representedActionIds[action.actionId] = true
                table.insert(BridgeState.highlightedGuids, guid)
            end
        end
    end

    BridgeEnsureDecisionOptionControls(decision, representedActionIds)
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
        -- A normal pickup/drop is a valid desktop and VR selection gesture.
        -- The bridge performs the lane preview after Forge accepts the exact
        -- offered action, so players need not drag a card to a narrow row.
        if not movedEnough and not droppedInLane then
            print(string.format(
                "[Bridge] combat selection accepted in place for %s (guid=%s)",
                tostring(intent.action.type), tostring(intent.guid)))
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
    BridgeTraceStart("START-09 event-session-prepare")
    BridgePrepareEventSession(sessionId, true)
    BridgeState.bootstrapping = true
    BridgeTraceStart("START-10 snapshot-request")
    BridgeGetEmbodimentSnapshot(function(ok, snapshot, err)
        BridgeRunTraced("START-11 snapshot-response", function()
            BridgeTraceStart("START-11 snapshot-response", ok and tostring(snapshot and snapshot.sessionId or "ok") or tostring(err))
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
            BridgeTraceStart("START-12 physical-bootstrap-begin")
            local stagedOk, stagedError = BridgeStageSeatCardsForBootstrap(snapshot)
            if not stagedOk then
                BridgeState.bootstrapping = false
                callback(false, stagedError)
                return
            end

            BridgeAnnotateSnapshotBattlefieldKinds(snapshot, function(annotated, annotationError)
                BridgeRunTraced("START annotate-callback", function()
                    if not annotated then
                        BridgeState.bootstrapping = false
                        callback(false, annotationError)
                        return
                    end
                    BridgeBootstrapSeats(snapshot, 1, function(seatsOk, seatsError)
                        BridgeRunTraced("START seat-bootstrap-callback", function()
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
    BridgeCollectSeatAssets(seatSnapshot.seatId, seatSnapshot, function(ok, assets, collectError)
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

function BridgeCollectSeatAssets(seatId, seatSnapshot, callback)
    local seat = BRIDGE_SEATS[seatId]
    local assets = {}
    local context = {
        expectedCardNamesBySeat = {},
        handGuidsBySeat = {}
    }
    context.expectedCardNamesBySeat[seatId] = BridgeExpectedCardNamesForSeatSnapshot(seatSnapshot)
    context.handGuidsBySeat[seatId] = BridgeBuildSeatHandGuidSet(seatId)
    BridgeTraceStart("START-14 library-indexing", tostring(seatId))
    for _, object in ipairs(getAllObjects()) do
        if BridgeObjectIsUsable(object)
            and object.tag == "Card"
            and BridgeObjectIsOnSeatSide(object, seat)
            and IsGameCardCandidate(object, seatId, context) then
            local guid = BridgeSafeObjectGuid(object)
            local cardName = BridgeSafeObjectName(object)
            if guid ~= nil then
                table.insert(assets, {
                    guid = guid,
                    cardName = cardName,
                    object = object
                })
            end
        end
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
    local containedOk = pcall(function() containedCards = deck.getObjects() or {} end)
    if not containedOk then
        return nil, "library ledger could not inspect deck contents for seat " .. tostring(seatId)
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

function BridgeReconcileSeatSnapshot(seatSnapshot, assets)
    local byName = {}
    local looseCountByName = {}
    local mappings = {}
    for _, asset in ipairs(assets) do
        local name = BridgeNormalizeCardName(asset.cardName)
        byName[name] = byName[name] or {}
        table.insert(byName[name], asset)
        looseCountByName[name] = (looseCountByName[name] or 0) + 1
    end

    local ledger, ledgerError = BridgeBuildSeatLibraryLedger(seatSnapshot)
    if ledger == nil then
        return false, ledgerError
    end

    local authoritativeCards = {}
    local authoritativeCountByName = {}
    for _, zone in ipairs(seatSnapshot.zones or {}) do
        for _, card in ipairs(zone.cards or {}) do
            table.insert(authoritativeCards, {zoneName = zone.name, card = card})
            local normalized = BridgeNormalizeCardName(card.cardName)
            authoritativeCountByName[normalized] = (authoritativeCountByName[normalized] or 0) + 1
        end
    end

    for normalizedName, expectedCount in pairs(authoritativeCountByName) do
        local looseCount = looseCountByName[normalizedName] or 0
        local containedCount = ledger.countByName[normalizedName] or 0
        local physicalCount = looseCount + containedCount
        if physicalCount < expectedCount then
            local detail = string.format(
                "library reconciliation failed: seat=%s card=%s forgeExpected=%d physicalContained=%d physicalLoose=%d unmappedForgeInstances=%d unassignedContained=%d",
                tostring(seatSnapshot.seatId), tostring(normalizedName), expectedCount, containedCount, looseCount,
                expectedCount - physicalCount, math.max(containedCount, 0))
            print("[Bridge] " .. detail)
            return false, "library reconciliation failed for seat " .. tostring(seatSnapshot.seatId)
                .. "; see host log for multiplicity diagnostics"
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
            if #containedCandidates > 0 then
                local contained = table.remove(containedCandidates, 1)
                assigned = {
                    cardName = contained.cardName,
                    object = nil
                }
                assignedContainedByName[normalized] = (assignedContainedByName[normalized] or 0) + 1
            end
        end
        local function consumeLoose()
            local looseCandidates = byName[normalized] or {}
            if #looseCandidates > 0 then
                assigned = table.remove(looseCandidates, 1)
            end
        end

        if zoneName == "library" then
            consumeContained()
            if assigned == nil then consumeLoose() end
        else
            consumeLoose()
            if assigned == nil then consumeContained() end
        end

        if assigned == nil then
            local expectedCount = authoritativeCountByName[normalized] or 0
            local containedCount = ledger.countByName[normalized] or 0
            local looseCount = looseCountByName[normalized] or 0
            local alreadyAssigned = assignedByName[normalized] or 0
            local unmappedForgeInstances = math.max(expectedCount - alreadyAssigned, 1)
            local unassignedContained = math.max(containedCount - (assignedContainedByName[normalized] or 0), 0)
            local detail = string.format(
                "library reconciliation failed: seat=%s card=%s forgeExpected=%d physicalContained=%d physicalLoose=%d unmappedForgeInstances=%d unassignedContained=%d",
                tostring(seatSnapshot.seatId), tostring(normalized), expectedCount, containedCount, looseCount,
                unmappedForgeInstances, unassignedContained)
            print("[Bridge] " .. detail)
            return false, "library reconciliation failed for seat " .. tostring(seatSnapshot.seatId)
                .. "; see host log for multiplicity diagnostics"
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
            BridgeState.physicalByInstanceId[mapping.card.cardInstanceId] = guid
            BridgeState.physicalInstanceIdByGuid[guid] = mapping.card.cardInstanceId
            BridgeState.physicalSeatByGuid[guid] = seatSnapshot.seatId
            BridgeState.physicalZoneByGuid[guid] = mapping.zoneName
            if mapping.asset.object ~= nil then
                BridgeState.untappedRotationByGuid[guid] = mapping.asset.object.getRotation()
            end
        end
    end
    BridgeTraceStart("START-17 mapping-complete", tostring(seatSnapshot.seatId))
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

    local function continueWith(object)
        local actualGuid = object.getGUID()
        if guid ~= nil and actualGuid ~= guid then
            BridgeState.physicalSeatByGuid[guid] = nil
            BridgeState.physicalZoneByGuid[guid] = nil
        end
        BridgeState.physicalByInstanceId[card.cardInstanceId] = actualGuid
        BridgeState.physicalInstanceIdByGuid[actualGuid] = card.cardInstanceId
        BridgeState.cardNameByInstanceId[card.cardInstanceId] = card.cardName
        BridgeState.physicalSeatByGuid[actualGuid] = seatSnapshot.seatId
        BridgeState.physicalZoneByGuid[actualGuid] = zone.name
        local placed, placeError = BridgePlaceSnapshotCard(object, card, zone, seatSnapshot)
        if not placed then
            callback(false, placeError)
            return
        end
        Wait.frames(function()
            BridgeMaterializeSeatSnapshot(seatSnapshot, zoneIndex, cardIndex + 1, callback)
        end, 2)
    end

    local object = guid and BridgeGetLiveObjectByGuid(guid) or nil
    if object ~= nil then continueWith(object); return end

    local seat = BRIDGE_SEATS[seatSnapshot.seatId]
    local deck = BridgeFindSeatLibraryDeckWithCard(seat, card.cardName)
    if deck == nil then deck = BridgeFindLibraryDeckForSeat(seatSnapshot.seatId) end
    if deck == nil then
        callback(false, "snapshot card identity is not present in the resolved physical library deck")
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
            if taken == nil then callback(false, takeError); return end
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
    end
    return true, nil
end

function BridgeApplySeatSnapshotVisualState(seatSnapshot)
    local seat = BRIDGE_SEATS[seatSnapshot.seatId]
    local lifeCounter = BridgeGetLiveObjectByGuid(seat.lifeCounterGuid)
    if lifeCounter ~= nil then lifeCounter.setValue(seatSnapshot.life) end
    BridgeSetManaBank(seatSnapshot.seatId, seatSnapshot.manaPool or {})
    for _, zone in ipairs(seatSnapshot.zones or {}) do
        if zone.name == "battlefield" then
            for _, card in ipairs(zone.cards or {}) do
                local guid = BridgeState.physicalByInstanceId[card.cardInstanceId]
                local object = guid and BridgeGetLiveObjectByGuid(guid) or nil
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
    local lifeCounter = BridgeGetLiveObjectByGuid(seat.lifeCounterGuid)
    if lifeCounter == nil then
        BridgeShowError("missing life counter for mana bank in seat " .. tostring(seatId))
        return false
    end
    local lifePosition = lifeCounter.getPosition()
    BridgeState.manaCounterGuidBySeatId[seatId] = BridgeState.manaCounterGuidBySeatId[seatId] or {}
    for index, color in ipairs(BRIDGE_MANA_COLORS) do
        local expectedName = "Forge Mana " .. color .. " " .. seatId
        local currentGuid = BridgeState.manaCounterGuidBySeatId[seatId][color]
        local counter = currentGuid and BridgeGetLiveObjectByGuid(currentGuid) or nil
        if counter == nil then
            for _, object in ipairs(getAllObjects()) do
                if BridgeObjectIsUsable(object) and BridgeSafeObjectName(object) == expectedName then counter = object; break end
            end
        end
        if counter == nil then
            local source = BridgeGetLiveObjectByGuid(BRIDGE_MANA_COUNTER_SOURCES[color])
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
            local counter = guid and BridgeGetLiveObjectByGuid(guid) or nil
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
    BridgeStopDecisionPolling()
    BridgeReturnAttackPresentation(nil)
    BridgeState.eventSessionId = sessionId
    BridgeState.lastReceivedEventSequence = 0
    BridgeState.lastAppliedEventSequence = 0
    BridgeState.eventQueue = {}
    BridgeState.animationRunning = false
    BridgeState.physicalByInstanceId = {}
    BridgeState.physicalInstanceIdByGuid = {}
    BridgeState.cardNameByInstanceId = {}
    BridgeState.physicalSeatByGuid = {}
    BridgeState.physicalZoneByGuid = {}
    BridgeState.battlefieldCounts = {}
    BridgeState.counterStateByInstanceId = {}
    BridgeState.keywordStateByInstanceId = {}
    BridgeState.untappedRotationByGuid = {}
    BridgeState.pendingCastBySeatId = {}
    BridgeState.attackOriginByGuid = {}
    BridgeState.attackLaneGuidBySeatId = {}
    BridgeState.snapshotForgeSequence = 0
    BridgeState.deferredSnapshotReconcile = nil
    BridgeState.zoneAnchorGuidBySeatAndZone = {}
    BridgeState.yieldSeatId = nil
    BridgeState.transitionExpectedUntil = 0
    BridgeState.latencyProbe = nil
    BridgeState.pendingDecision = nil
    BridgeState.pendingDecisionDeferredAt = nil
    BridgeState.pendingDecisionDeferredCursor = 0
    BridgeState.pendingDecisionDeferredApplied = 0
    BridgeResetSelectionState()
    BridgeHideMainPriorityControls()
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
            end
            BridgeProcessEventQueue()
            BridgeTryPresentPendingDecision("poll-noqueue")
            end

            BridgeScheduleEventPoll(BridgeCurrentEventPollDelay(), generation)
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
    BridgeTryApplyDeferredSnapshotReconcile("event " .. tostring(event.sequence))
    BridgeTryPresentPendingDecision("event-applied")
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
        print(string.format(
            "[Bridge] private event seq=%s kind=%s seat=%s instance=%s source=%s dest=%s (card identity redacted)",
            tostring(event.sequence),
            tostring(event.kind),
            tostring(event.seatId),
            tostring(event.cardInstanceId),
            tostring(event.sourceZone),
            tostring(event.destinationZone)))
    else
        print(string.format(
            "[Bridge] event seq=%s kind=%s seat=%s instance=%s source=%s dest=%s card=%s",
            tostring(event.sequence),
            tostring(event.kind),
            tostring(event.seatId),
            tostring(event.cardInstanceId),
            tostring(event.sourceZone),
            tostring(event.destinationZone),
            tostring(event.cardName)))
    end

    local seat = BRIDGE_SEATS[event.seatId]
    if seat == nil then
        return false, 0, "event " .. tostring(event.sequence) .. " has no configured seat " .. tostring(event.seatId)
    end

    if event.kind == "turn_changed" then
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
        BridgeRecordAuthoritativeTurn(BridgeState.currentTurnSeatId, tonumber(event.turnNumber or 0))
        local turnSeat = BRIDGE_SEATS[BridgeState.currentTurnSeatId]
        BridgeSetStatus("CURRENT TURN: " .. tostring(turnSeat and turnSeat.ttsColor or BridgeState.currentTurnSeatId), BridgeTurnLabel() .. " - AI THINKING")
        print("[Bridge] authoritative turn changed to seat " .. tostring(BridgeState.currentTurnSeatId) .. " turn=" .. tostring(event.turnNumber))
        if BridgeState.yieldSeatId ~= nil and BridgeState.yieldSeatId ~= event.seatId then
            BridgeState.yieldSeatId = nil
        end
        BridgeMarkTransitionExpected(0)
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
        if BridgeState.pendingDecision ~= nil then
            local ignorePending = BridgeShouldIgnoreStaleDecision(BridgeState.pendingDecision)
            if ignorePending then
                BridgeState.pendingDecision = nil
                BridgeState.pendingDecisionDeferredAt = nil
                BridgeState.pendingDecisionDeferredCursor = 0
                BridgeState.pendingDecisionDeferredApplied = 0
            end
        end
        BridgeResetSelectionState()
        BridgeHideMainPriorityControls()
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
        if event.cardInstanceId ~= nil and event.destinationZone ~= nil then
            BridgeState.pendingStructuredZoneTransitionByInstanceId[event.cardInstanceId] = {
                sourceZone = event.sourceZone,
                destinationZone = event.destinationZone,
                sequence = event.sequence,
                applied = applied == true,
            }
        end
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
        local guid = BridgeSafeObjectGuid(object)
        local trackedZone = guid and BridgeState.physicalZoneByGuid[guid] or nil
        if trackedZone ~= "battlefield" then
            print(string.format(
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
            print(string.format(
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
                print(string.format(
                    "[Bridge] semantic land presentation deferred event=%s instance=%s after structured move=%s",
                    tostring(event.sequence), tostring(event.cardInstanceId), tostring(pendingTransition.sequence)))
                return true, 0.1
            end
            return false, 0, resolveError
        end
        
        -- If it's a deck object (from library), draw the top card
        if object.tag == "Deck" then
            local drawn = object.takeObject({
                position = {object.getPosition()[1], object.getPosition()[2] + 3, object.getPosition()[3]},
                smooth = false
            })
            if drawn == nil then return false, 0, "could not draw land from library deck" end
            object = drawn
            Wait.frames(function()
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
        -- Mana use is a presentation-only consequence of Forge's exact card
        -- instance.  Never resolve it by name: duplicate Mountains are common
        -- and choosing one locally would be a rules/UI lie.  A preceding
        -- structured move may still be awaiting the cursor-gated snapshot;
        -- defer the visual tap in that case (and for any other missing exact
        -- mapping) rather than turning a correct Forge action into a desync.
        local object, resolveError = BridgeResolveMappedInstance(event)
        if object == nil then
            print(string.format(
                "[Bridge] mana presentation deferred event=%s instance=%s reason=%s",
                tostring(event.sequence), tostring(event.cardInstanceId), tostring(resolveError)))
            BridgeScheduleSnapshotReconcile("mana event " .. tostring(event.sequence))
            return true, 0.1
        end
        local guid = BridgeSafeObjectGuid(object)
        local trackedZone = guid and BridgeState.physicalZoneByGuid[guid] or nil
        if trackedZone ~= "battlefield" then
            print(string.format(
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
            BridgeRecordLooseCardIdentity(event.cardInstanceId, pendingCast.guid, event.seatId, "stack")
        end
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
        guid = nil
    end

    local function allowsMappedDeckHandle(mappedObject)
        if mappedObject == nil or mappedObject.tag ~= "Deck" then return false end
        return event.sourceZone == "library" or event.destinationZone == "library"
    end

    if object ~= nil and object.tag ~= "Card" and not allowsMappedDeckHandle(object) then
        print(string.format(
            "[Bridge] stale mapped object for structured move seq=%s kind=%s instance=%s source=%s dest=%s mappedGuid=%s mappedTag=%s",
            tostring(event.sequence), tostring(event.kind), tostring(event.cardInstanceId),
            tostring(event.sourceZone), tostring(event.destinationZone), tostring(guid), tostring(object.tag)))
        BridgeState.physicalByInstanceId[event.cardInstanceId] = nil
        BridgeState.physicalSeatByGuid[guid] = nil
        BridgeState.physicalZoneByGuid[guid] = nil
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
            BridgeRecordLooseCardIdentity(event.cardInstanceId, guid, event.seatId, event.destinationZone)
            if event.destinationZone == "battlefield" then
                BridgeSetPhysicalFaceDown(object, seat, event.faceDown == true)
            end
            print(string.format(
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
        BridgeTakeCardFromDeckByIdentity(deck, expectedName, hand.position, true, function(drawn, takeError)
            if drawn == nil then
                BridgeStopOnDesync(libraryDrawError(takeError))
                return
            end
            local drawnGuid = BridgeSafeObjectGuid(drawn)
            if drawnGuid == nil then
                BridgeStopOnDesync(libraryDrawError("physical library returned a card with no GUID"))
                return
            end
            BridgeRecordLooseCardIdentity(event.cardInstanceId, drawnGuid, event.seatId, event.destinationZone)
            drawn.use_hands = true
            BridgeSetPhysicalFaceDown(drawn, seat, event.faceDown == true)
        end)
        return true, nil
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

    if event.sourceZone == "library" and event.destinationZone == "hand" and (object == nil or object.tag == "Deck") then
        local deck = object
        if deck == nil then
            local expectedName = BridgeState.cardNameByInstanceId[event.cardInstanceId] or event.cardName
            if expectedName ~= nil and expectedName ~= "" then
                deck = BridgeFindSeatLibraryDeckWithCard(seat, expectedName)
            end
            if deck == nil then deck = BridgeFindLibraryDeckForSeat(event.seatId) end
        end
        if deck == nil then
            return false, libraryDrawError(resolveError or "physical library deck not found for authoritative draw")
        end
        return moveFromLibraryDeckToHand(deck)
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
            "resolved object is a deck for non-library->hand move",
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

    if event.destinationZone == "hand" then
        local hand, handError = BridgeTryGetSeatHandTransform(event.seatId)
        if hand == nil then return false, handError end
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
        object.use_hands = false
        local exilePosition = BridgeResolveSeatZoneAnchor(event.seatId, "exile")
        if exilePosition == nil then
            return false, "no exile anchor configured for seat " .. tostring(event.seatId)
        end
        object.setPositionSmooth(exilePosition, false, true)
    elseif event.destinationZone == "library" then
        local libraryZone = BridgeGetLiveObjectByGuid(seat.libraryZoneGuid)
        if libraryZone == nil then
            return false, "cannot move to library: configured library zone is unavailable"
        end
        object.use_hands = false
        object.setPositionSmooth(libraryZone.getPosition(), false, true)
        BridgeRecordLibraryContainedState(event.cardInstanceId, event.seatId, event.cardName)
        return true, nil
    end

    BridgeRecordLooseCardIdentity(event.cardInstanceId, guid, event.seatId, event.destinationZone)
    return true, nil
end

function BridgeMoveToGraveyard(event, object)
    local seat = BRIDGE_SEATS[event.seatId]
    if seat == nil then return false, "graveyard move has no configured seat" end
    local graveyardPosition = BridgeResolveSeatZoneAnchor(event.seatId, "graveyard")
    if graveyardPosition == nil then
        return false, "no graveyard anchor configured for seat " .. tostring(event.seatId)
    end
    local moved, movementError = pcall(function()
        object.use_hands = false
        BridgeSetPhysicalFaceDown(object, seat, false)
        object.setPositionSmooth(graveyardPosition, false, true)
    end)
    if not moved then return false, "could not move card to graveyard: " .. tostring(movementError) end
    local guid = object.getGUID()
    BridgeState.pendingCastBySeatId[event.seatId] = nil
    BridgeRecordLooseCardIdentity(event.cardInstanceId, guid, event.seatId, "graveyard")
    return true, nil
end

function BridgeFindSeatLibraryDeckWithCard(seat, expectedName)
    local seatId = BridgeSeatIdForSeatConfig(seat)
    local preferred = seatId and BridgeFindLibraryDeckForSeat(seatId) or nil
    if preferred ~= nil and BridgeDeckContainsCardName(preferred, expectedName) then
        return preferred
    end

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
        print(string.format("[Bridge] ambiguous library deck match for %s (%d candidates)", tostring(expectedName), #matches))
        return nil
    end

    return nil
end

function BridgeTakeCardFromDeckByIdentity(deck, expectedName, position, smooth, callback)
    if not BridgeObjectIsUsable(deck) then
        callback(nil, "physical library deck is no longer available")
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

function BridgeTakeNamedCardFromDeck(deck, expectedName, position, smooth, callback)
    BridgeTakeCardFromDeckByIdentity(deck, expectedName, position, smooth, callback)
end

function BridgeSetPhysicalFaceDown(object, seat, faceDown)
    if not BridgeObjectIsUsable(object) then return end
    local faceUp = seat.faceUpRotation
    if faceUp == nil then return end
    local rotation = {
        x = faceUp.x,
        y = faceUp.y,
        z = faceUp.z + (faceDown and 180 or 0)
    }
    if not BridgeSafeObjectCall(object, function(o) o.setRotation(rotation) end) then return end
    local guid = BridgeSafeObjectGuid(object)
    if guid == nil then return end
    BridgeState.untappedRotationByGuid[guid] = {
        x = faceUp.x,
        y = faceUp.y,
        z = faceUp.z
    }
end

function BridgeSetPhysicalTapped(object, tapped)
    local guid = BridgeSafeObjectGuid(object)
    if guid == nil then return end
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
    prowess = "mtg_prowesscounter",
    reach = "mtg_reachcounter", trample = "mtg_tramplecounter",
    vigilance = "mtg_vigilancecounter", stun = "mtg_stuncounter"
}

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
            else
                if existing.tag == "Card" then
                    local mappedZone = BridgeState.physicalZoneByGuid[existingGuid]
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
    BridgeRecordLooseCardIdentity(event.cardInstanceId, guid, event.seatId, "battlefield")
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
    BridgeStopDecisionPolling()
    BridgeState.animationRunning = false
    BridgeState.pendingDecision = nil
    BridgeState.pendingDecisionDeferredAt = nil
    BridgeState.pendingDecisionDeferredCursor = 0
    BridgeState.pendingDecisionDeferredApplied = 0
    BridgeClearHighlights()
    BridgeResetSelectionState()
    BridgeHideMainPriorityControls()
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
