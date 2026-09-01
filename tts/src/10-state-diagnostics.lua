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

    local function handleIfCurrent(request)
        if not BridgeRuntimeIsCurrent(epoch) then
            BridgeLog("[Bridge] ignored HTTP callback from retired Global.lua runtime")
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
    -- Wait.time is normally sufficient, but a bootstrap can be waiting on a
    -- TTS callback while the time scheduler is delayed.  Keep the resync
    -- watchdog reactive from the frame loop as well.
    if BridgeCheckResyncWatchdog ~= nil then BridgeCheckResyncWatchdog("onUpdate") end
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
