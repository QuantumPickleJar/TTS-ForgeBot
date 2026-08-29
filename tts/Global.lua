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
BRIDGE_EVENT_POLL_INTERVAL_ACTIVE = 0.12
BRIDGE_DECISION_DEFER_STALL_SECONDS = 0.6
BRIDGE_GRAVEYARD_ACTION_GROUP_THRESHOLD = 6
-- Configuration, not rules: FREEFORM permits a player to arrange their own
-- lands after they enter. STRICT re-applies the persistent land row only on
-- authoritative layout events or an explicit organize request.
BRIDGE_LAND_PLACEMENT_MODE = BRIDGE_LAND_PLACEMENT_MODE or "FREEFORM"
BRIDGE_SCRIPT_REVISION = "2026-08-27-f2c-v14-delve-mulligan"

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

function BridgePresentationMetric(name)
    BridgeState.presentationMetrics[name] = (BridgeState.presentationMetrics[name] or 0) + 1
end

function BridgeLogPresentationMetrics(label)
    local metrics = BridgeState.presentationMetrics or {}
    BridgeLog(string.format(
        "[Bridge] presentation-metrics label=%s encoderRebuilds=%d keywordWrites=%d decalWrites=%d snapshotReconciles=%d",
        tostring(label or "manual"), tonumber(metrics.encoderRebuildCount or 0),
        tonumber(metrics.keywordPropWriteCount or 0), tonumber(metrics.decalWriteCount or 0),
        tonumber(metrics.fullSnapshotReconcileCount or 0)))
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
    pendingIntentControlGuids = {},
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
    decisionPresentationGeneration = 0,
    decisionPollInFlight = false,
    decisionPollScheduled = false,
    eventRetryCount = 0,
    skipExistingEventsOnAttach = false,
    eventQueue = {},
    animationRunning = false,
    physicalByInstanceId = {},
    physicalInstanceIdByGuid = {},
    cardNameByInstanceId = {},
    canonicalCardNameByGuid = {},
    encoderIdentityLoggedGuids = {},
    presentedStatsByGuid = {},
    presentedOwnerControllerByGuid = {},
    presentedPhasedByGuid = {},
    presentedCounterSignatureByGuid = {},
    presentedKeywordSignatureByGuid = {},
    presentedIconLayoutByGuid = {},
    preparedDescriptionByGuid = {},
    prototypeDescriptionByGuid = {},
    preparedBadgeGuidByInstanceId = {},
    preparedPresentationGuidByInstanceId = {},
    preparedDesignationStateByInstanceId = {},
    preparedSpellControlGuids = {},
    unsupportedKeywordLogged = {},
    presentationMetrics = {encoderRebuildCount = 0, keywordPropWriteCount = 0, decalWriteCount = 0, fullSnapshotReconcileCount = 0},
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
    yieldSeatId = nil,
    -- End Turn is scoped to the current Forge turn. Keeping only a seat ID
    -- allowed a prior yield to resume when that same player received their
    -- next turn, silently skipping an entire turn cycle.
    yieldTurnNumber = nil,
    counterStateByInstanceId = {},
    keywordStateByInstanceId = {},
    cardDesignationsByInstanceId = {},
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
    bootstrapping = false,
    setupBusy = false,
    doctorInitializedUi = false,
    doctorRetryAttempt = 0,
    transitionExpectedUntil = 0,
    latencyProbe = nil,
    sessionRecoveryInFlight = false,
    choiceProtocolPaused = false,
    choiceProtocolFailureTimes = {},
    gameEnded = nil,
    playerStateBySeatId = {},
    playerCountersBySeatId = {},
    ui = {mounted = false, dirty = false, flushScheduled = false, actionRows = {}, contextInstanceId = nil,
        graveyardActionRows = {}, graveyardFolderDecisionId = nil, graveyardFolderOpen = false,
        graveyardFolderPage = 1,
        manaMode = "AUTO", autoAdvanceMode = "SMART", fastPlaytest = false, gameLogVisible = true,
        gameLog = {},
        diagnosticsVisible = false, reportPanelVisible = false, reportCategoryIndex = 1,
        creatureTypeDecisionId = nil, creatureTypeDraftActionId = nil, creatureTypeOptions = {},
        reportStatus = "", reportCaptureInFlight = false, uiFullRebuildCount = 0, uiAttributeUpdateCount = 0,
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

function BridgeRecordLooseCardIdentity(cardInstanceId, guid, seatId, zoneName)
    if BridgeIsPresentationOnlyObject(guid) then
        BridgeLog("[Bridge] refusing Forge mapping for presentation object " .. tostring(guid))
        return false
    end
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
    if BridgeCaptureCanonicalCardScale ~= nil then BridgeCaptureCanonicalCardScale(BridgeGetLiveObjectByGuid(guid)) end
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
    BridgeRecordLooseCardIdentity(event.cardInstanceId, guid, event.seatId, "battlefield")
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

function BridgeFindSingleCardLibraryCandidateForSeat(seatId)
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then return nil end
    local anchor = BridgeGetLiveObjectByGuid(seat.libraryZoneGuid)
    if anchor == nil then return nil end
    local okAnchor, anchorPosition = pcall(function() return anchor.getPosition() end)
    if not okAnchor or anchorPosition == nil then return nil end
    local nearest = nil
    local nearestDistance = nil
    local radius = (seat.libraryAssetRadius or 4) + 0.75
    for _, object in ipairs(getAllObjects()) do
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
        -- TTS collapses a one-card Deck into a loose Card.  That Card is still
        -- the physical library, but it must only be promoted back to a Deck by
        -- a verified insertion; proximity alone is never enough to clear a
        -- Forge identity mapping.
        local singleCard = BridgeFindSingleCardLibraryCandidateForSeat(seatId)
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

function BridgeStagePhysicalCardForBootstrap(object, seatId, stagedBySeat)
    if not BridgeObjectIsUsable(object) then return false end
    -- This helper is intentionally Card-only. TTS Deck-on-Deck operations
    -- are not a safe reset primitive and can corrupt the physical pile.
    if object.tag ~= "Card" then return false end
    local seat = seatId and BRIDGE_SEATS[seatId] or nil
    if seat == nil then return false end

    -- Do not merely drop cards above the scripting-zone marker and hope that
    -- physics merges them before the library ledger is inspected. On this
    -- table the marker is several units above the actual Deck, which left a
    -- transient (and occasionally permanent) under-count during bootstrap.
    -- Inserting into the resolved physical Deck is deterministic and does not
    -- assign any Forge identity; the later ledger remains authoritative.
    local deck = BridgeResolveSeatLibraryDeck(seatId)
    if deck ~= nil then
        local objectGuid = BridgeSafeObjectGuid(object)
        local deckGuid = BridgeSafeObjectGuid(deck)
        if objectGuid ~= nil and objectGuid == deckGuid then
            BridgeLog("[Bridge] refused to stage a library card into itself guid=" .. tostring(objectGuid)
                .. " seat=" .. tostring(seatId))
            return false
        end
        if not BridgeRequireArtBearingLibraryCard(object, seatId, nil) then return false end
        if deck.tag == "Card" then
            -- TTS collapses a one-card Deck to a Card.  Form the next Deck
            -- deterministically and let the post-bootstrap containment audit
            -- decide whether the physical merge really happened.
            local libraryPosition = deck.getPosition()
            local inserted = BridgeSafeObjectCall(object, function(o)
                o.setLock(false)
                o.use_hands = false
                BridgeSetPhysicalFaceDown(o, seat, true)
                deck.setLock(false)
                deck.use_hands = false
                BridgeSetPhysicalFaceDown(deck, seat, true)
                o.setPosition({libraryPosition.x, libraryPosition.y + 0.06, libraryPosition.z})
                deck.setPosition(libraryPosition)
            end)
            if inserted then return true end
            return false
        end
        local inserted = BridgeSafeObjectCall(object, function(o)
            o.use_hands = false
            o.setLock(false)
            BridgeSetPhysicalFaceDown(o, seat, true)
            deck.putObject(o)
        end)
        if inserted then return true end
    end

    BridgeLog("[Bridge] refused spatial-only library staging seat=" .. tostring(seatId))
    return false
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
        BridgeLog("[Bridge] staged " .. tostring(stagedCount) .. " loose card(s) near library before authoritative bootstrap")
    end
    return true, nil
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

function BridgeAuditDuplicateLibraryGuids()
    local looseByGuid = {}
    for _, object in ipairs(getAllObjects()) do
        if BridgeObjectIsUsable(object) and object.tag == "Card" then
            local guid = BridgeSafeObjectGuid(object)
            if guid ~= nil then
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

function BridgeVerifyLibraryContainment(seatId, guid, callback, attempt)
    attempt = attempt or 1
    local library = BridgeResolveSeatLibraryDeck(seatId)
    if library ~= nil and library.tag == "Deck" and BridgeLibraryContainsGuid(library, guid) then
        callback(true, library, nil)
        return
    end
    local containingDeck = BridgeFindLibraryDeckContainingGuid(seatId, guid)
    if containingDeck ~= nil then
        callback(true, containingDeck, nil)
        return
    end
    if attempt >= 6 then
        callback(false, nil, "TTS did not verify library containment for GUID " .. tostring(guid))
        return
    end
    BridgeWaitFrames(function()
        BridgeVerifyLibraryContainment(seatId, guid, callback, attempt + 1)
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
                library.putObject(object, #entries + 1)
            else
                library.putObject(object)
            end
            inserted = true
        elseif library.tag == "Card" then
            -- TTS represents a one-card Deck as a loose Card.  Stack the new
            -- card deterministically, then require TTS to form a Deck before
            -- publishing contained state.  This never creates or destroys a
            -- second card.
            local libraryPosition = library.getPosition()
            library.setLock(false)
            library.use_hands = false
            BridgeSetPhysicalFaceDown(library, seat, true)
            local yOffset = mode == "BOTTOM" and -0.06 or 0.06
            object.setPosition({libraryPosition.x, libraryPosition.y + yOffset, libraryPosition.z})
            library.setPosition(libraryPosition)
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
        local duplicateGuidCount = BridgeAuditDuplicateLibraryGuids()
        if duplicateGuidCount > 0 then
            local duplicateError = "library insertion produced " .. tostring(duplicateGuidCount)
                .. " loose/contained duplicate GUID(s)"
            BridgeLog("[Bridge] " .. duplicateError)
            callback(false, duplicateError)
            return
        end
        callback(true, nil, deck)
    end)
end

function BridgeProcessMulliganBottomQueue(seatId)
    if BridgeState.mulliganBottomInsertionActiveBySeatId[seatId] == true then return end
    local queue = BridgeState.mulliganBottomQueueBySeatId[seatId]
    local item = queue and queue[1] or nil
    if item == nil then return end
    BridgeState.mulliganBottomInsertionActiveBySeatId[seatId] = true

    local function complete()
        local current = BridgeState.mulliganBottomQueueBySeatId[seatId]
        if current ~= nil then table.remove(current, 1) end
        BridgeState.mulliganBottomInsertionActiveBySeatId[seatId] = nil
        BridgeProcessMulliganBottomQueue(seatId)
        -- A replacement opening-hand draw must not overtake a preceding
        -- authoritative hand->library insertion.
        BridgeProcessLibraryExtractionQueue(seatId)
    end

    local guid = BridgeSafeObjectGuid(item.object)
    local instanceId = guid and BridgeState.physicalInstanceIdByGuid[guid] or nil
    BridgeInsertPhysicalCardIntoLibrary(seatId, item.object, "BOTTOM", function(ok, err)
        if not ok then
            BridgeStopOnDesync("mulligan bottom library insertion failed: " .. tostring(err))
        elseif instanceId ~= nil then
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
    local finished = false
    local function complete()
        if finished then return end
        finished = true
        local current = BridgeState.libraryExtractionQueueBySeatId[seatId]
        if current ~= nil then table.remove(current, 1) end
        BridgeState.libraryExtractionActiveBySeatId[seatId] = nil
        BridgeProcessLibraryExtractionQueue(seatId)
        BridgeTryPresentPendingDecision("library-extraction-complete")
    end
    job(complete)
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
                        BridgeInsertPhysicalCardIntoLibrary(job.seatId, card, "NORMAL", function(inserted, insertError)
                            if not inserted then
                                done(false, "could not return graveyard card " .. tostring(cardGuid) .. " to library: " .. tostring(insertError))
                                return
                            end
                            drained = drained + 1
                            BridgeWaitFrames(nextCard, 1)
                        end, BridgeState.physicalInstanceIdByGuid[cardGuid])
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
    BridgeOnLoad()
end

function onUpdate()
end

-- The stable static tree lives in Global.xml. Dynamic decision content is
-- routed through its fixed IDs, never through a second Forge choice transport.

function BridgeUiSet(id, attribute, value)
    if BridgeState.ui == nil or BridgeState.ui.mounted ~= true then return end
    pcall(function() UI.setAttribute(id, attribute, tostring(value or "")) end)
    BridgeState.ui.uiAttributeUpdateCount = (BridgeState.ui.uiAttributeUpdateCount or 0) + 1
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
    local prompt = decision and (decision.prompt or decision.kind or "Choose an action") or "AI THINKING..."
    if decision ~= nil and decision.kind == "cost_selection" and decision.costKind == "crew" then
        prompt = "CREW — SELECT CREATURES"
    end
    BridgeUiSet("BridgeHudPrompt", "text", terminal and BridgeUiTerminalLabel(terminal) or prompt)
    BridgeUiSet("BridgeHudMana", "text", "MANA: " .. tostring(ui.manaMode or "AUTO"))
    BridgeUiSet("BridgeHudMode", "text", tostring(ui.autoAdvanceMode or "SMART"))
    BridgeUiSet("BridgeHudFast", "text", ui.fastPlaytest and "FAST: ON" or "FAST: OFF")
    BridgeUiSet("BridgeHudLog", "text", ui.gameLogVisible and "LOG: ON" or "LOG: OFF")
    local help = ui.autoAdvanceMode == "SMART" and "SMART: Forge auto-advances only when it has no meaningful human choice."
        or (ui.autoAdvanceMode == "YIELD" and "YIELD: keep passing Forge priority until a meaningful choice interrupts it."
            or "MANUAL: use PASS for each Forge priority window.")
    BridgeUiSet("BridgeHudHelp", "text", help)
    local actions = terminal and {} or (decision and decision.actions or {})
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
                local prefix = (BridgeState.selectedActionIds[action.actionId] == true or action.isSelected == true)
                    and "[x] " or "[ ] "
                BridgeUiSet("BridgeHudAction" .. tostring(i), "text", prefix .. BridgeUiActionLabel(action))
                BridgeUiSet("BridgeHudAction" .. tostring(i), "tooltip", "Forge action: " .. BridgeUiActionLabel(action)
                    .. "\nKind: " .. tostring(action.actionKind or action.type or "choice")
                    .. (action.sourceCardName and ("\nSource: " .. tostring(action.sourceCardName)) or ""))
            end
        end
    end
    local hasPass = false
    local hasYield = false
    for _, action in ipairs(actions) do
        if action.type == "pass_priority" then hasPass = true; hasYield = true end
    end
    local targetCanCancel = decision ~= nil and decision.allowsCancel == true
        and (decision.kind == "target_selection" or decision.kind == "defender_selection"
            or decision.kind == "player_selection")
    BridgeUiSet("BridgeHudPass", "active", hasPass and "true" or "false")
    BridgeUiSet("BridgeHudYield", "active", hasYield and "true" or "false")
    BridgeUiSet("BridgeHudConfirm", "active", decision and BridgeDecisionNeedsConfirmation(decision) and "true" or "false")
    BridgeUiSet("BridgeHudCancel", "active", decision and
        ((BridgeDecisionNeedsConfirmation(decision) and not BridgeIsStructuredForgeToggleChoice(decision))
            or targetCanCancel) and "true" or "false")
    BridgeUiSet("BridgeHudNewMatch", "active", terminal and "true" or "false")
    BridgeUiSet("BridgeHudNewMatch", "text", BridgeState.resetConfirmationArmed and "CONFIRM NEW MATCH" or "NEW MATCH")
    local footer = terminal and "NEW MATCH is available on the table."
        or (ui.contextInstanceId and "CARD CONTEXT — choose a Forge-provided action" or "Forge decides legality. Screen actions submit exact Forge choices.")
    if not terminal and #(BridgeState.stackSummary or {}) > 0 then footer = "STACK: " .. table.concat(BridgeState.stackSummary, " > ") end
    if not terminal and ui.gameLogVisible and #(ui.gameLog or {}) > 0 then footer = ui.gameLog[#ui.gameLog] end
    BridgeUiSet("BridgeHudFooter", "text", footer)
end

function BridgeUiMount()
    local ui = BridgeState.ui
    if ui ~= nil and ui.mounted then return end
    pcall(function() UI.setAttribute("BridgeHudRoot", "active", "true") end)
    BridgeState.ui.mounted = true
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
    if BridgeState.lastDecision == nil or not BridgeDecisionNeedsConfirmation(BridgeState.lastDecision) then return end
    BridgeConfirmSelection(nil, player, false)
end

function BridgeHudCancel(player, value, id)
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

function BridgeHudYield(player, value, id)
    BridgePressEndTurn(nil, player, false)
end

function BridgeHudMode(player, value, id)
    local ui = BridgeState.ui
    ui.autoAdvanceMode = ui.autoAdvanceMode == "MANUAL" and "SMART" or (ui.autoAdvanceMode == "SMART" and "YIELD" or "MANUAL")
    BridgeUiMarkDirty("mode")
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
    BridgeHttp.requestJson("GET", "/health", nil, callback)
end

function BridgeStartSession(callback)
    BridgeHttp.requestJson("POST", "/api/v1/session/start", nil, callback)
end

function BridgeResetSessionRequest(callback)
    BridgeHttp.requestJson("POST", "/api/v1/session/reset", nil, callback)
end

-- TTS's imported library piles are the deck chooser.  We send only printed
-- identities and counts; Forge decides whether the Legacy-assumed deck is legal.
function BridgeConfigureDecks(callback)
    local seats = {}
    for _, seatId in ipairs({"forge-player-1", "forge-player-2"}) do
        local deck, _, deckError = BridgeResolveSeatLibraryDeck(seatId)
        if deck == nil then callback(false, nil, "cannot load TTS library for " .. tostring(seatId) .. ": " .. tostring(deckError)); return end
        local counts = {}
        for _, contained in ipairs(deck.getObjects() or {}) do
            local name = BridgeImportedCardName(contained.nickname or contained.name or "")
            if BridgeNormalizeCardName(name) ~= "" then counts[name] = (counts[name] or 0) + 1 end
        end
        local cards = {}
        for name, count in pairs(counts) do table.insert(cards, {cardName = name, count = count}) end
        if #cards == 0 then callback(false, nil, "TTS library is empty for " .. tostring(seatId)); return end
        BridgeLog(string.format("[Bridge] TTS deck inventory seat=%s uniqueNames=%d totalCards=%d revision=%s",
            tostring(seatId), #cards, #(deck.getObjects() or {}), tostring(BRIDGE_SCRIPT_REVISION)))
        table.insert(seats, {seatId = seatId, cards = cards})
    end
    BridgeLog("[Bridge] posting TTS deck inventory to /api/v1/decks")
    BridgeHttp.requestJson("POST", "/api/v1/decks", {seats = seats}, function(ok, body, err, request)
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

function BridgeScheduleDecisionPoll(delay, generation, attempt)
    if BridgeState.gameEnded ~= nil then return end
    if generation ~= BridgeState.decisionPollGeneration then return end
    if BridgeState.lastDecision ~= nil or BridgeState.submitting then return end
    if BridgeState.decisionPollInFlight or BridgeState.decisionPollScheduled then return end

    BridgeState.decisionPollScheduled = true
    local nextDelay = delay or 0.1
    if BridgeState.ui ~= nil and BridgeState.ui.fastPlaytest then nextDelay = math.min(nextDelay, 0.05) end
    BridgeWaitTime(function()
        if generation ~= BridgeState.decisionPollGeneration then return end
        BridgeState.decisionPollScheduled = false
        BridgePollForNextDecision(generation, attempt)
    end, nextDelay)
end

function BridgePollForNextDecision(generation, attempt)
    if BridgeState.gameEnded ~= nil then return end
    if generation ~= BridgeState.decisionPollGeneration then return end
    if BridgeState.lastDecision ~= nil or BridgeState.submitting then return end
    if BridgeState.decisionPollInFlight then return end

    local expectedSessionId = BridgeState.eventSessionId
    local presentationGeneration = BridgeState.decisionPresentationGeneration
    BridgeState.decisionPollInFlight = true
    BridgeHttp.requestJson("GET", "/api/v1/decision", nil, function(ok, body, err, request)
        if generation ~= BridgeState.decisionPollGeneration then return end
        if expectedSessionId ~= BridgeState.eventSessionId
            or presentationGeneration ~= BridgeState.decisionPresentationGeneration then return end

        BridgeState.decisionPollInFlight = false
        if ok and body ~= nil then
            BridgeMarkTransitionExpected(0)
            BridgeRecordLatencyProbeDecisionReady(body)
            BridgeAcceptDecision(body, "decision_poll", expectedSessionId, presentationGeneration)
            return
        end

        local responseCode = request and tonumber(request.response_code) or nil
        local noPendingDecision = (body ~= nil and body.errorCode == "no_pending_decision") or responseCode == 404
        if noPendingDecision then
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
            BridgeScheduleDecisionPoll(retryDelay, generation, attempt + 1)
            return
        end

        BridgeShowError("decision poll failed: " .. tostring(err))
        BridgeScheduleDecisionPoll(1.0, generation, attempt + 1)
    end)
end

function BridgeStartDecisionPolling()
    if BridgeState.gameEnded ~= nil then return end
    BridgeStopDecisionPolling()
    BridgeScheduleDecisionPoll(BridgeTransitionExpected() and 0.1 or 0.25, BridgeState.decisionPollGeneration, 1)
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
    BridgeLog(string.format(
        "[Bridge] choice-attempt=%s source=%s session=%s decision=%s action=%s submitting=%s transactionState=%s yieldSeat=%s",
        tostring(attempt), tostring(source or "unknown"), tostring(BridgeState.eventSessionId or "nil"),
        tostring(decisionId), tostring(actionId), tostring(BridgeState.submitting == true),
        tostring(transactionState or "none"), tostring(BridgeState.yieldSeatId or "nil")))
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
                BridgeState.yieldSeatId = nil
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
                    or BridgeIsDiscardChoice(body.currentDecision)) then
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
    BridgeState.yieldSeatId = nil
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
    BridgeState.yieldSeatId = nil
    BridgeState.lastDecision = nil
    BridgeState.pendingDecision = nil
    BridgeClearHighlights()
    BridgeRollbackPendingIntent()
    BridgeResetSelectionState()
    BridgeHideMainPriorityControls()
    BridgeStopDecisionPolling()
    BridgeStopEventPolling()
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

function BridgeDecisionHasNonPassAction(decision)
    for _, action in ipairs((decision and decision.actions) or {}) do
        if action.type ~= "pass_priority" then return true end
    end
    return false
end

function BridgeShouldIgnoreStaleDecision(decision)
    local eventCursor = tonumber(decision and decision.eventCursor or 0) or 0
    local applied = tonumber(BridgeState.lastAppliedEventSequence or 0) or 0
    if eventCursor <= 0 or eventCursor >= applied then
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

function BridgeShouldDeferDecision(decision)
    -- Do not show KEEP/MULLIGAN until the authoritative opening-hand draws
    -- have all completed their serialized physical extraction. Otherwise a
    -- player can be asked to assess six visible cards while Forge has seven.
    if decision ~= nil and decision.kind == "mulligan" then
        local queue = BridgeState.libraryExtractionQueueBySeatId[decision.seatId]
        if BridgeState.libraryExtractionActiveBySeatId[decision.seatId] == true
            or (queue ~= nil and #queue > 0) then
            return true, tonumber(decision.eventCursor or 0) or 0,
                tonumber(BridgeState.lastAppliedEventSequence or 0) or 0
        end
    end
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
            BridgeLog(string.format(
                "[Bridge] dropping stale deferred decision %s after %.1fs wait (cursor=%s applied=%s)",
                tostring(pending.decisionId), elapsed, tostring(eventCursor), tostring(applied)))
            BridgeState.pendingDecision = nil
            BridgeState.pendingDecisionDeferredAt = nil
            BridgeState.pendingDecisionDeferredCursor = 0
            BridgeState.pendingDecisionDeferredApplied = 0
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
    return event.kind == "spell_resolved"
        or event.kind == "land_played"
        or event.kind == "card_moved"
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
    BridgePresentationMetric("fullSnapshotReconcileCount")
    BridgeSetMonarchSeat(snapshot and snapshot.monarchSeatId or nil)
    BridgeState.stackSummary = {}
    for _, card in ipairs(snapshot and snapshot.stack or {}) do
        table.insert(BridgeState.stackSummary, tostring(card.currentCardName or card.cardName or "Forge stack object"))
    end
    BridgeUiMarkDirty("stack")
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
                    local mappedNeedsFix = mappedObject == nil or mappedObject.tag ~= "Card" or mappedZone ~= zoneName
                        or (snapshotRow ~= nil and priorRow ~= nil and priorRow ~= snapshotRow)
                    if mappedNeedsFix then
                        -- The log intentionally omits cardName: a snapshot can
                        -- contain identities that should not be public chat.
                        BridgeLog(string.format(
                            "[Bridge] snapshot candidate instance=%s oldZone=%s destinationZone=%s",
                            tostring(card.cardInstanceId), tostring(mappedZone), tostring(zoneName)))
                        local evt = {
                            seatId = seatSnapshot.seatId,
                            cardInstanceId = card.cardInstanceId,
                            cardName = card.cardName,
                            sourceZone = nil,
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
        BridgeApplySeatSnapshotVisualState(seatSnapshot)
    end
    BridgeApplyCombatSnapshot(snapshot.combat)
    BridgeState.snapshotForgeSequence = snapshot.forgeSequence or BridgeState.snapshotForgeSequence
    BridgeLogSnapshotOrdering("applied", snapshot, reason)
    if movedCount > 0 then
        BridgeLog(string.format("[Bridge] snapshot reconcile (%s): corrected %d public card location(s)", tostring(reason), movedCount))
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
            BridgeLog("[Bridge] snapshot reconcile failed: " .. tostring(err))
        elseif snapshot ~= nil then
            BridgeLog("[Bridge] snapshot reconcile skipped due to session mismatch")
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
    BridgeWaitFrames(function()
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
    BridgeWaitFrames(function()
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
    BridgeLog("setup-click:new-match")
    BridgeWaitFrames(function()
        BridgeDoPressNewMatch(color, alt)
    end, 1)
end

function BridgeDoPressNewMatch(playerColor, altClick)
    BridgeLog("setup-deferred:new-match")
    if BridgeState.setupBusy then
        BridgeShowError("Forge is still initializing; wait for the loading controls to finish")
        return
    end
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
        BridgeDoPressConfirmNewMatch(color, alt)
    end, 1)
end

function BridgeDoPressConfirmNewMatch(playerColor, altClick)
    BridgeLog("setup-deferred:confirm")
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

    BridgeTraceStart("START-07 TTS-library-deck-load")
    BridgeConfigureDecks(function(deckOk, _, deckError)
        if not deckOk then
            if done then done() end
            BridgeShowError("TTS library load failed: " .. BridgeHttpFailureDetail(_, deckError))
            return
        end
        BridgeTraceStart("START-07 session-start-request")
        BridgeStartSession(function(ok, body, err)
        BridgeRunTraced("START-08 session-start-response", function()
            BridgeTraceStart("START-08 session-start-response", ok and tostring(body and body.sessionId or "ok") or tostring(err))
            if not ok then
                if done then done() end
            BridgeShowError("session start failed: " .. BridgeHttpFailureDetail(body, err))
                return
            end

            BridgeLog("[Bridge] started or attached session: " .. tostring(body and body.sessionId))
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
    BridgeStopEventPolling()
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

    if expectedSessionId ~= nil and (expectedSessionId ~= BridgeState.eventSessionId
        or presentationGeneration ~= BridgeState.decisionPresentationGeneration) then
        BridgeLog("[Bridge] DECISION_REJECT origin=" .. tostring(origin) .. " reason=replaced_generation decision=" .. tostring(decision.decisionId))
        return
    end

    if decision.sessionId == nil or decision.sessionId ~= BridgeState.eventSessionId then
        BridgeLog("[Bridge] DECISION_REJECT origin=" .. tostring(origin) .. " reason=wrong_session decision="
            .. tostring(decision.decisionId) .. " decisionSession=" .. tostring(decision.sessionId)
            .. " activeSession=" .. tostring(BridgeState.eventSessionId))
        return
    end

    if BridgeState.retiredChoiceDecisionIds[decision.decisionId] == true
        or BridgeState.choiceTransactions[decision.decisionId] ~= nil then
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
        BridgeCreatureTypeClearDraft("decision-replaced")
        BridgeGraveyardClear("decision-replaced")
    end

    BridgeRetireChoiceTransactionsForDecision(decision.decisionId)

    local ignoreStale, eventCursor, applied = BridgeShouldIgnoreStaleDecision(decision)
    if ignoreStale then
        BridgeLog(string.format(
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
        BridgeLog(string.format(
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
    -- Phase transitions are authoritative events. Decision metadata is only a
    -- corroborating hint and must not regress a newer event (or replace it
    -- with a stale/blank phase during polling).
    local decisionPhase = tostring(decision.phaseName or "")
    local decisionCursor = tonumber(decision.eventCursor or 0) or 0
    local appliedCursor = tonumber(BridgeState.lastAppliedEventSequence or 0) or 0
    if decisionPhase ~= "" and (decisionCursor <= 0 or decisionCursor >= appliedCursor) then
        BridgeState.currentPhase = decisionPhase
    elseif decisionPhase ~= "" then
        BridgeLog(string.format("[Bridge] retaining event phase=%s over stale decision phase=%s cursor=%s applied=%s",
            tostring(BridgeState.currentPhase), decisionPhase, tostring(decisionCursor), tostring(appliedCursor)))
    end
    if decision.prioritySeatId ~= nil then
        BridgeState.prioritySeatId = decision.prioritySeatId
    end

    BridgeState.lastDecision = decision
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
    elseif decision.kind == "card_selection" then
        BridgeSetStatus("CHOOSE CARD", "Required Forge selection (for example, discard) — this is not a cast action")
    elseif decision.kind == "discard" then
        if decision.decisionCauseKind == "cleanup_hand_size" then
            BridgeSetStatus("DISCARD TO MAXIMUM HAND SIZE", "Choose " .. tostring(decision.minSelections or 1) .. " card(s) from your hand.")
        elseif decision.decisionCauseKind == "spell_or_ability" then
            BridgeSetStatus("DISCARD " .. tostring(decision.minSelections or 1) .. " CARD", "Caused by: " .. tostring(decision.sourceCardName or "Forge spell or ability"))
        else
            BridgeSetStatus("DISCARD", "Choose Forge's legal discard card(s).")
        end
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
    BridgeState.yieldSeatId = nil
    BridgeState.yieldTurnNumber = nil
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
    if decision == nil or decision.kind ~= "main_priority" then
        BridgeHideMainPriorityControls()
        BridgeShowError("End Turn is unavailable while waiting for a Forge main-priority decision")
        return
    end
    BridgeClaimHumanTtsColor(decision.seatId, playerColor)
    for _, action in ipairs(decision.actions or {}) do
        if action.type == "pass_priority" then
            BridgeState.yieldSeatId = decision.seatId
            BridgeState.yieldTurnNumber = tonumber(decision.turnNumber or BridgeState.tableTurnCount or 0) or 0
            BridgeClearHighlights()
            BridgeSubmitChoice(decision.decisionId, action.actionId, "yield_button")
            return
        end
    end
    BridgeShowError("Forge did not offer a pass/yield action")
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
    BridgeSubmitChoice(intent.decisionId, intent.action.actionId, "cast_confirm")
end

function BridgeCancelCastPreview(object, playerColor, altClick)
    local decision = BridgeState.lastDecision
    BridgeClearPendingIntentControls()
    BridgeRollbackPendingIntent()
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

function BridgeRenderDecision(decision)
    BridgeClearHighlights()
    BridgeRenderPreparedSpellPresentations(decision)

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

    if (BridgeState.ui == nil or not BridgeState.ui.mounted)
        and decision.kind == "main_priority" and BridgeDecisionOffersActionType(decision, "pass_priority") then
        BridgeEnsureEndTurnButton(decision.seatId)
        BridgeEnsurePassButton(decision.seatId)
    else
        BridgeHideMainPriorityControls()
    end

    if BridgeState.yieldSeatId ~= nil then
        local yieldTurn = tonumber(BridgeState.yieldTurnNumber or 0) or 0
        local decisionTurn = tonumber(decision.turnNumber or 0) or 0
        if decision.seatId ~= BridgeState.yieldSeatId or decision.kind ~= "main_priority"
            or (yieldTurn > 0 and decisionTurn > 0 and decisionTurn ~= yieldTurn) then
            BridgeState.yieldSeatId = nil
            BridgeState.yieldTurnNumber = nil
        else
            for _, action in ipairs(decision.actions) do
                if action.type == "pass_priority" then
                    BridgeSubmitChoice(decision.decisionId, action.actionId, "yield_auto_pass")
                    return
                end
            end
        end
    end

    -- With only Pass priority available, Forge has exposed no meaningful human
    -- action. Advance upkeep/draw and other empty windows automatically. Any
    -- legal land, spell, ability, target, or structured choice remains visible.
    if decision.kind == "main_priority"
        and BridgeDecisionOffersActionType(decision, "pass_priority")
        and not BridgeDecisionHasNonPassAction(decision) then
        for _, action in ipairs(decision.actions) do
            if action.type == "pass_priority" then
                BridgeSubmitChoice(decision.decisionId, action.actionId, "empty_priority_auto_pass")
                return
            end
        end
    end

    local highlightColor = {0.53, 0.81, 0.98}
    local selectedCombatColor = {0.2, 1.0, 0.35}
    if decision.kind ~= "main_priority" then
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
                BridgeSpawnPlayerTargetControl(targetObject, action.targetSeatId, decision, action)
            else
                BridgeShowError("no physical target surface configured for seat " .. tostring(action.targetSeatId))
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
end

function BridgeShowError(message)
    local text = "[Bridge] " .. tostring(message)
    BridgeLog(text)
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

    if object.tag == "Card" and (BridgeDecisionNeedsConfirmation(decision) or action.requiresSelection == true) then
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
        BridgeWaitFrames(function() BridgeRenderDecision(decision) end, 2)
        return
    end

    -- Player scoreboards and other non-card targets are selection surfaces,
    -- not draggable game pieces, so the grab itself commits the offered target.
    if object.tag ~= "Card" then
        BridgeSubmitChoice(decision.decisionId, action.actionId, "physical_target_pickup")
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
            BridgeEnsureCastPreviewControls(intent)
            return
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
    if intent.action ~= nil and intent.action.type == "cast_spell" then
        BridgeState.pendingCastBySeatId[intent.seatId] = nil
    end
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
            local duplicateGuidCount = BridgeAuditDuplicateLibraryGuids()
            if duplicateGuidCount > 0 then
                BridgeState.bootstrapping = false
                local detail = "physical library identity audit found " .. tostring(duplicateGuidCount)
                    .. " loose/contained duplicate GUID(s)"
                BridgeLog("[Bridge] " .. detail)
                callback(false, detail)
                return
            end
            BridgeTraceStart("START-12 physical-bootstrap-begin")
            local stagedOk, stagedError = BridgeStageSeatCardsForBootstrap(snapshot)
            if not stagedOk then
                BridgeState.bootstrapping = false
                callback(false, stagedError)
                return
            end

            -- Let Tabletop Simulator commit Deck.putObject before reading the
            -- contained-card ledger. This is a short state-settle, not a
            -- timing-based replacement for deterministic insertion above.
            BridgeTraceStart("START-13 library-settle")
            BridgeWaitFrames(function()
                local postStageDuplicateCount = BridgeAuditDuplicateLibraryGuids()
                if postStageDuplicateCount > 0 then
                    BridgeState.bootstrapping = false
                    local detail = "physical library identity audit found " .. tostring(postStageDuplicateCount)
                        .. " loose/contained duplicate GUID(s) after staging"
                    BridgeLog("[Bridge] " .. detail)
                    callback(false, detail)
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
                                BridgeLog(string.format(
                                    "[Bridge] authoritative embodiment bootstrap complete: seats=%d forgeSequence=%s (hidden identities redacted)",
                                    #(snapshot.seats or {}), tostring(BridgeState.snapshotForgeSequence)))
                                callback(true, nil)
                            end)
                        end)
                    end)
                end)
            end, 15)
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
            if not materialized then callback(false, materializeError); return end
            BridgeWaitFrames(function()
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
            and (function()
                local library = BridgeResolveSeatLibraryDeck(seatId)
                return library == nil or BridgeSafeObjectGuid(library) ~= BridgeSafeObjectGuid(object)
            end)()
            and IsGameCardCandidate(object, seatId, context) then
            local guid = BridgeSafeObjectGuid(object)
            local cardName = BridgePhysicalCanonicalCardName(object)
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
        if card.isToken ~= true and not BridgeRequireArtBearingLibraryCard(object, seatSnapshot.seatId, card.cardInstanceId) then
            callback(false, "snapshot materialization rejected an artless normal game card")
            return
        end
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
        BridgeWaitFrames(function()
            BridgeMaterializeSeatSnapshot(seatSnapshot, zoneIndex, cardIndex + 1, callback)
        end, 2)
    end

    local object = guid and BridgeGetLiveObjectByGuid(guid) or nil
    if object ~= nil then continueWith(object); return end

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
    BridgeApplySeatTrackers(seatSnapshot)
    local battlefieldInstances = {}
    for _, zone in ipairs(seatSnapshot.zones or {}) do
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
                    local countersApplied, counterError = BridgeSetCardCounters(object, card.counters)
                    if not countersApplied then BridgeLog("[Bridge] counter visual unsupported: " .. tostring(counterError)) end
                    local keywords = {}
                    for _, keyword in ipairs(card.keywords or {}) do
                        keywords[BridgeNormalizeKeywordName(keyword)] = true
                    end
                    BridgeState.keywordStateByInstanceId[card.cardInstanceId] = keywords
                    local keywordsApplied, keywordError = BridgeSetCardKeywords(object, card.keywords)
                    if not keywordsApplied then BridgeLog("[Bridge] keyword visual unsupported: " .. tostring(keywordError)) end
                    -- Encoder rebuilds performed by counters/keywords may
                    -- recreate the card UI.  Apply Unified P/T and ownership
                    -- last so a static characteristic update remains visible.
                    local presentationApplied, presentationError = BridgeApplyCardPresentationSnapshot(object, card)
                    if not presentationApplied then
                        BridgeLog("[Bridge] optional card presentation skipped: " .. tostring(presentationError))
                    end
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

function BridgeShowResourceCounter(counter, position)
    if counter == nil or position == nil then return end
    pcall(function() counter.setInvisibleTo({}) end)
    pcall(function() counter.setPosition(position) end)
end

function BridgeFindResourceCounter(seatId, kind, definition)
    BridgeState.resourceCounterGuidBySeatId[seatId] = BridgeState.resourceCounterGuidBySeatId[seatId] or {}
    local guid = BridgeState.resourceCounterGuidBySeatId[seatId][kind]
    local counter = guid and BridgeGetLiveObjectByGuid(guid) or nil
    if counter ~= nil then return counter end

    local expectedName = definition.name .. " " .. tostring(seatId)
    for _, object in ipairs(getAllObjects()) do
        if BridgeObjectIsUsable(object) and BridgeSafeObjectName(object) == expectedName then
            counter = object
            BridgeRegisterPresentationObject(counter, "resource_row_" .. tostring(kind))
            BridgeState.resourceCounterGuidBySeatId[seatId][kind] = BridgeSafeObjectGuid(counter)
            return counter
        end
    end
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
            if sessionId == BridgeState.eventSessionId then BridgeSetNativeTrackerValue(counter, BridgeResourceValue(seatId, kind)) end
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
            if sessionId == BridgeState.eventSessionId then BridgeSetNativeTrackerValue(taken, BridgeResourceValue(seatId, kind)) end
        end, 2)
    end})
    return nil
end

-- Reconcile one compact row from authoritative Forge values.  Zero-valued
-- resources are hidden/retired and never occupy a slot; remaining counters
-- are packed contiguously in the stable order above.
function BridgeRefreshResourceRow(seatId)
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil or BridgeResourceRowPosition(seatId, 1) == nil then return false end
    BridgeState.resourceCounterGuidBySeatId[seatId] = BridgeState.resourceCounterGuidBySeatId[seatId] or {}
    BridgeState.manaCounterGuidBySeatId[seatId] = BridgeState.resourceCounterGuidBySeatId[seatId]
    BridgeState.playerTrackerGuidBySeatId[seatId] = BridgeState.resourceCounterGuidBySeatId[seatId]
    local slot = 0
    for _, kind in ipairs(BRIDGE_RESOURCE_ORDER) do
        local definition = BridgeResourceDefinition(kind)
        local value = BridgeResourceValue(seatId, kind)
        local counter = BridgeFindResourceCounter(seatId, kind, definition)
        if value > 0 then
            slot = slot + 1
            local position = BridgeResourceRowPosition(seatId, slot)
            if counter == nil then counter = BridgeCreateResourceCounter(seatId, kind, definition, position) end
            if counter ~= nil then
                BridgeShowResourceCounter(counter, position)
                BridgeSetNativeTrackerValue(counter, value)
            end
        elseif counter ~= nil then
            BridgeHideResourceCounter(counter)
        end
    end
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
    BridgeState.playerStateBySeatId[seatId] = BridgeState.playerStateBySeatId[seatId] or {}
    BridgeState.playerStateBySeatId[seatId].mana = manaPool or {}
    if not deferRefresh then BridgeRefreshResourceRow(seatId) end
end

function BridgeSetNativeTrackerValue(counter, value)
    if counter == nil then return end
    local amount = math.max(0, tonumber(value or 0) or 0)
    counter.setVar("val", amount)
    pcall(function() counter.call("updateVal") end)
    pcall(function() counter.call("updateSave") end)
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

function BridgeApplySeatTrackers(seatSnapshot)
    if seatSnapshot == nil then return end
    local counters = BridgeState.playerCountersBySeatId[seatSnapshot.seatId] or {}
    counters.poison = math.max(0, tonumber(seatSnapshot.poison or counters.poison or 0) or 0)
    counters.speed = math.max(0, tonumber(seatSnapshot.speed or counters.speed or 0) or 0)
    BridgeState.playerCountersBySeatId[seatSnapshot.seatId] = counters
    BridgeState.playerStateBySeatId[seatSnapshot.seatId] = BridgeState.playerStateBySeatId[seatSnapshot.seatId] or {}
    BridgeState.playerStateBySeatId[seatSnapshot.seatId].counters = counters
    BridgeRefreshResourceRow(seatSnapshot.seatId)
end

function BridgeFindLiveMonarchHelper()
    local known = BridgeState.monarchHelperGuid and BridgeGetLiveObjectByGuid(BridgeState.monarchHelperGuid) or nil
    if known ~= nil then return known end
    for _, object in ipairs(getAllObjects()) do
        local name = string.lower(tostring(BridgeSafeObjectName(object) or ""))
        if BridgeObjectIsUsable(object) and object.tag == "Card" and string.sub(name, 1, 10) == "the monarch" then
            BridgeRegisterPresentationObject(object, "monarch_helper")
            BridgeState.monarchHelperGuid = BridgeSafeObjectGuid(object)
            return object
        end
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
    local helper = BridgeFindLiveMonarchHelper()
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

function BridgeRetireResourceRowObjects()
    local retired = {}
    for seatId, resources in pairs(BridgeState.resourceCounterGuidBySeatId or {}) do
        for _, guid in pairs(resources or {}) do
            local object = BridgeGetLiveObjectByGuid(guid)
            if object ~= nil and not retired[guid] then
                retired[guid] = true
                -- These GUIDs are registered only after a source has been
                -- cloned/taken, so native source/template objects are never
                -- destroyed during a session reset.
                if BridgeIsPresentationOnlyObject(object) then
                    BridgeSafeObjectCall(object, function(o) o.destruct() end)
                end
            end
        end
    end
    -- A Save & Play can reload Lua after the old GUID maps were cleared. Find
    -- only our explicitly named spawned instances in that case, excluding all
    -- configured native source GUIDs/templates.
    local sourceGuids = {}
    for _, guid in pairs(BRIDGE_MANA_COUNTER_SOURCES or {}) do sourceGuids[guid] = true end
    for _, guid in pairs(BRIDGE_PLAYER_TRACKER_SOURCES or {}) do sourceGuids[guid] = true end
    for _, object in ipairs(getAllObjects()) do
        local guid = BridgeSafeObjectGuid(object)
        local name = tostring(BridgeSafeObjectName(object) or "")
        local spawned = string.match(name, "^Forge Mana [WUBRGC] forge%-player%-[12]$")
            or string.match(name, "^Forge (energy|experience|poison|speed) forge%-player%-[12]$")
        if guid ~= nil and spawned and not sourceGuids[guid] and not retired[guid] then
            retired[guid] = true
            BridgeSafeObjectCall(object, function(o) o.destruct() end)
        end
    end
    BridgeState.resourceCounterGuidBySeatId = {}
    BridgeState.resourceCounterSpawnInFlightBySeatId = {}
    BridgeState.manaCounterGuidBySeatId = {}
    BridgeState.playerTrackerGuidBySeatId = {}
end

function BridgePrepareEventSession(sessionId, forceReset)
    if not forceReset and BridgeState.eventSessionId == sessionId then
        return
    end

    BridgeStopEventPolling()
    BridgeStopDecisionPolling()
    BridgeReturnAttackPresentation(nil)
    BridgeRetireResourceRowObjects()
    BridgeClearPreparedPresentationObjects()
    BridgeState.decisionPresentationGeneration = BridgeState.decisionPresentationGeneration + 1
    BridgeState.eventSessionId = sessionId
    BridgeState.lastReceivedEventSequence = 0
    BridgeState.lastAppliedEventSequence = 0
    BridgeState.eventQueue = {}
    BridgeState.animationRunning = false
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
    BridgeState.presentedKeywordSignatureByGuid = {}
    BridgeState.presentedIconLayoutByGuid = {}
    BridgeState.unsupportedKeywordLogged = {}
    BridgeState.presentationMetrics = {encoderRebuildCount = 0, keywordPropWriteCount = 0, decalWriteCount = 0, fullSnapshotReconcileCount = 0}
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
    BridgeState.battlefieldCounts = {}
    BridgeState.graveyardCounts = {}
    BridgeState.counterStateByInstanceId = {}
    BridgeState.keywordStateByInstanceId = {}
    BridgeState.cardDesignationsByInstanceId = {}
    BridgeState.preparedDescriptionByGuid = {}
    BridgeState.prototypeDescriptionByGuid = {}
    BridgeState.preparedBadgeGuidByInstanceId = {}
    BridgeState.preparedPresentationGuidByInstanceId = {}
    BridgeState.preparedDesignationStateByInstanceId = {}
    BridgeState.preparedSpellControlGuids = {}
    BridgeState.untappedRotationByGuid = {}
    BridgeState.pendingCastBySeatId = {}
    BridgeState.attackOriginByGuid = {}
    BridgeState.attackLaneGuidBySeatId = {}
    BridgeState.snapshotForgeSequence = 0
    BridgeState.deferredSnapshotReconcile = nil
    BridgeState.zoneAnchorGuidBySeatAndZone = {}
    BridgeState.yieldSeatId = nil
    BridgeState.gameEnded = nil
    BridgeState.playerStateBySeatId = {}
    BridgeState.playerCountersBySeatId = {}
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
    local nextDelay = delay or 0.1
    if BridgeState.ui ~= nil and BridgeState.ui.fastPlaytest then nextDelay = math.min(nextDelay, 0.05) end
    BridgeWaitTime(function()
        if generation ~= BridgeState.eventPollGeneration then
            return
        end
        BridgeState.animationRunning = false
        BridgeProcessEventQueue()
    end, nextDelay)
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
        BridgeState.yieldSeatId = nil
        BridgeState.pendingDecision = nil
        BridgeState.lastDecision = nil
        BridgeState.submitting = false
        BridgeClearHighlights()
        BridgeRollbackPendingIntent()
        BridgeResetSelectionState()
        BridgeHideMainPriorityControls()
        BridgeStopDecisionPolling()
        BridgeStopEventPolling()
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
        -- Priority is an independent Forge state transition. Keep the last
        -- known value here when this turn event has no priority payload; the
        -- following priority event will update it authoritatively.
        if event.prioritySeatId ~= nil then BridgeState.prioritySeatId = event.prioritySeatId end
        BridgeRecordAuthoritativeTurn(BridgeState.currentTurnSeatId, tonumber(event.turnNumber or 0))
        local turnSeat = BRIDGE_SEATS[BridgeState.currentTurnSeatId]
        BridgeSetStatus("CURRENT TURN: " .. tostring(turnSeat and turnSeat.ttsColor or BridgeState.currentTurnSeatId), BridgeTurnLabel() .. " - AI THINKING")
        BridgeLog("[Bridge] authoritative turn changed to seat " .. tostring(BridgeState.currentTurnSeatId) .. " turn=" .. tostring(event.turnNumber))
        -- End Turn means "the remainder of this turn". A turn transition is
        -- authoritative proof that scope has ended even when a legacy text
        -- event lacks a numeric turn value or a reliable seat label.
        if BridgeState.yieldSeatId ~= nil then
            BridgeState.yieldSeatId = nil
            BridgeState.yieldTurnNumber = nil
            BridgeLog("[Bridge] cleared end-turn yield at authoritative turn transition")
        end
        BridgeMarkTransitionExpected(0)
        BridgeUiMarkDirty("turn")
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
        -- Phase and priority are independent authoritative values. Do not
        -- overwrite priority from a phase event that carries no priority.
        if event.prioritySeatId ~= nil then BridgeState.prioritySeatId = event.prioritySeatId end
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
        BridgeUiMarkDirty("phase")
        return true, 0.1
    end

    if event.kind == "priority_changed" then
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
        BridgeState.playerStateBySeatId[event.seatId] = BridgeState.playerStateBySeatId[event.seatId] or {}
        BridgeState.playerStateBySeatId[event.seatId].mana = event.manaPool
        BridgeUiMarkDirty("mana")
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
                    local moved, moveError = BridgeMoveToBattlefield(
                        resolvedEvent, pendingObject, BridgeBattlefieldRowForEvent(resolvedEvent, "creature"))
                    if not moved then return false, 0, moveError end
                    BridgeState.pendingCastBySeatId[event.seatId] = nil
                    BridgeLog(string.format(
                        "[Bridge] presented exact pending cast on semantic resolution event=%s instance=%s",
                        tostring(event.sequence), tostring(resolvedEvent.cardInstanceId)))
                    return true, 0.1
                end
            end
            return true, 0.1
        end
        local object, resolveError = BridgeResolvePhysicalCard(event, "stack")
        if object == nil then return false, 0, resolveError end
        local moved, moveError = BridgeMoveToBattlefield(event, object, BridgeBattlefieldRowForEvent(event, "creature"))
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
        pendingBySeat[event.seatId] = nil
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
    for _, guid in ipairs(BridgeState.preparedSpellControlGuids or {}) do
        BridgeUnregisterPresentationObject(guid)
        local object = BridgeGetLiveObjectByGuid(guid)
        if object ~= nil then
            BridgeSafeObjectCall(object, function(o) o.destruct() end)
        end
    end
    BridgeState.preparedSpellControlGuids = {}
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
        BridgeLog(string.format(
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
        BridgeQueueLibraryExtraction(event.seatId, function(complete)
            local liveDeck = BridgeFindSeatLibraryDeckWithCard(seat, expectedName) or BridgeFindLibraryDeckForSeat(event.seatId)
            if liveDeck == nil then
                BridgeStopOnDesync(libraryDrawError("physical library deck not found while processing queued extraction"))
                complete()
                return
            end
            BridgeTakeCardFromDeckByIdentity(liveDeck, expectedName, hand.position, true, function(drawn, takeError)
                if drawn == nil then
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
        BridgeQueueLibraryExtraction(event.seatId, function(complete)
            local liveDeck = BridgeFindSeatLibraryDeckWithCard(seat, expectedName) or BridgeFindLibraryDeckForSeat(event.seatId)
            if liveDeck == nil then
                BridgeStopOnDesync(libraryDrawError("physical library deck not found while processing queued extraction"))
                complete()
                return
            end
            BridgeTakeCardFromDeckByIdentity(liveDeck, expectedName, {staging.x + 4, staging.y + 2, staging.z}, false,
                function(taken, takeError)
                    if taken == nil then
                        BridgeStopOnDesync(libraryDrawError(takeError))
                        complete()
                        return
                    end
                    if not BridgeRequireArtBearingLibraryCard(taken, event.seatId, event.cardInstanceId) then
                        BridgeStopOnDesync(libraryDrawError("physical library returned an artless normal game card"))
                        complete()
                        return
                    end
                    local row = event.battlefieldKind
                        or BridgeState.battlefieldKindByInstanceId[event.cardInstanceId]
                        or "creature"
                    local moved, moveError = BridgeMoveToBattlefield(event, taken, row)
                    if not moved then BridgeStopOnDesync(libraryDrawError(moveError)) end
                    BridgeWaitFrames(complete, 1)
                end)
        end)
        return true, nil
    end

    local function moveFromTokenFetcherToBattlefield()
        local expectedName = BridgeState.cardNameByInstanceId[event.cardInstanceId] or event.cardName
        local row = event.battlefieldKind
            or BridgeState.battlefieldKindByInstanceId[event.cardInstanceId]
            or "creature"
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

    if event.sourceZone == "library" and event.destinationZone == "battlefield" and (object == nil or object.tag == "Deck") then
        local deck = object
        if deck == nil then
            local expectedName = BridgeState.cardNameByInstanceId[event.cardInstanceId] or event.cardName
            if expectedName ~= nil and expectedName ~= "" then
                deck = BridgeFindSeatLibraryDeckWithCard(seat, expectedName)
            end
            if deck == nil then deck = BridgeFindLibraryDeckForSeat(event.seatId) end
        end
        if deck == nil then
            return false, libraryDrawError(resolveError or "physical library deck not found for authoritative library-to-battlefield move")
        end
        return moveFromLibraryDeckToBattlefield(deck)
    end

    if object == nil and event.destinationZone == "battlefield"
        and (event.isToken == true or event.sourceZone == "token" or event.sourceZone == "tokens") then
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

    if event.destinationZone ~= "battlefield" then
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
        local row = event.battlefieldKind
            or BridgeState.battlefieldKindByInstanceId[event.cardInstanceId]
            or "creature"
        local moved, moveError = BridgeMoveToBattlefield(event, object, row)
        if not moved then return false, moveError end
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
            BridgeInsertPhysicalCardIntoLibrary(event.seatId, object, "NORMAL", function(inserted, insertError)
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
    BridgeState.pendingCastBySeatId[event.seatId] = nil
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

function BridgeTakeNamedCardFromDeck(deck, expectedName, position, smooth, callback)
    BridgeTakeCardFromDeckByIdentity(deck, expectedName, position, smooth, callback)
end

function BridgeTokenNameMatches(ttsName, forgeName)
    if BridgeCardNameMatches(ttsName, forgeName) or BridgeCardNameMatches(forgeName, ttsName) then
        return true
    end

    local function normalizeTokenName(name)
        local normalized = BridgeNormalizeCardName(name)
        normalized = string.gsub(normalized, "[,%./%-]", " ")
        normalized = string.gsub(normalized, "%f[%a]token%f[%A]", " ")
        normalized = string.gsub(normalized, "^%s+", "")
        normalized = string.gsub(normalized, "%s+$", "")
        normalized = string.gsub(normalized, "%s+", " ")
        return normalized
    end

    local left = normalizeTokenName(ttsName)
    local right = normalizeTokenName(forgeName)
    if left == "" or right == "" then return false end
    if left == right then return true end
    return string.find(left, right, 1, true) ~= nil or string.find(right, left, 1, true) ~= nil
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
            if exact or BridgeCardNameMatches(containedName, expectedName) or BridgeTokenNameMatches(containedName, expectedName) then
                local entryScore = scoreBase + (exact and 50 or 0)
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
    if guid ~= nil and BridgeState.presentedCounterSignatureByGuid[guid] == signature then return true, nil end

    local applied, applyError = BridgeMutateUnifiedState(object, function(unified)
        unified.plusOneCounters = plusOne
        unified.displayPlusOne = plusOne ~= 0
        -- Unified has one generic named counter display.  Never combine
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
    local fallbackApplied, fallbackError = BridgeSetForgeBotCounterFallback(object, named)
    if not fallbackApplied then
        BridgeLog("[Bridge] optional counter fallback skipped: " .. tostring(fallbackError))
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
        if event.battlefieldKind == "land" or event.battlefieldKind == "creature" then
            return event.battlefieldKind
        end
        for _, cardType in ipairs(event.currentTypes or {}) do
            if string.lower(tostring(cardType)) == "land" then return "land" end
        end
        local knownRow = event.cardInstanceId ~= nil
            and BridgeState.battlefieldKindByInstanceId[event.cardInstanceId] or nil
        if knownRow == "land" or knownRow == "creature" then return knownRow end
    end
    return defaultRow == "land" and "land" or "creature"
end

function BridgeMoveToBattlefield(event, object, row)
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

    local moved, movementError = pcall(function()
        BridgeCaptureCanonicalCardScale(object)
        object.use_hands = false
        BridgeSetPhysicalFaceDown(object, BRIDGE_SEATS[event.seatId], event.faceDown == true)
        object.setPosition(destination)
        BridgeRestoreCanonicalCardScale(object)
    end)
    if not moved then
        return false, "event " .. tostring(event.sequence) .. " could not move physical card: " .. tostring(movementError)
    end

    -- TTS hand/Encoder presentation can apply a scale change on the frame in
    -- which the card leaves its prior container. Restore again after that
    -- deferred work has run; this is visual only and retains the exact card.
    BridgeWaitFrames(function()
        if BridgeObjectIsUsable(object) then BridgeRestoreCanonicalCardScale(object) end
    end, 2)

    local guid = object.getGUID()
    BridgeRecordLooseCardIdentity(event.cardInstanceId, guid, event.seatId, "battlefield")
    if row == "land" and event.cardInstanceId ~= nil and BridgeState.landInsertionOrderByInstanceId[event.cardInstanceId] == nil then
        BridgeState.nextLandInsertionOrder = (BridgeState.nextLandInsertionOrder or 0) + 1
        BridgeState.landInsertionOrderByInstanceId[event.cardInstanceId] = BridgeState.nextLandInsertionOrder
    end
    local rowKey = event.seatId .. ":" .. row
    BridgeState.battlefieldCounts[rowKey] = (BridgeState.battlefieldCounts[rowKey] or 0) + 1
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
    local diagnostic = tostring(message or "")
    if string.sub(diagnostic, 1, 16) == "LIBRARY MISMATCH" then
        -- Bootstrap mismatch has already emitted its complete, read-only
        -- inventory to the scripting log.  Keep the table-facing signal to
        -- one concise status diagnostic rather than broadcasting retries.
        BridgeLog("[Bridge] synchronization stopped: " .. diagnostic)
        BridgeSetStatus("LIBRARY MISMATCH", diagnostic)
        return
    end
    BridgeShowError("synchronization stopped: " .. diagnostic)
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
    BridgeLog("[Bridge] pendingIntent=" .. JSON.encode(BridgeState.pendingIntent or {}))
    BridgeLog("[Bridge] yieldSeatId=" .. tostring(BridgeState.yieldSeatId))
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
BRIDGE_SCRIPT_REVISION = "2026-08-27-f2c-v14-delve-mulligan"

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
    "Mana/payment", "Performance", "Crash/error", "Other"
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

function BridgeHudReportCategory(player, value, id)
    if BridgeState.ui == nil or BridgeState.ui.reportCaptureInFlight then return end
    local index = tonumber(BridgeState.ui.reportCategoryIndex or 1) or 1
    index = index + 1
    if index > #BRIDGE_REPORT_CATEGORIES then index = 1 end
    BridgeState.ui.reportCategoryIndex = index
    BridgeUiMarkDirty("report-category")
end

function BridgeHudReportMappedCardInstanceIds()
    local ids = {}
    for cardInstanceId, _ in pairs(BridgeState.physicalByInstanceId or {}) do
        table.insert(ids, cardInstanceId)
    end
    table.sort(ids)
    return ids
end

function BridgeHudReportSummaryText()
    local ok, value = pcall(function() return UI.getAttribute("BridgeHudReportSummary", "text") end)
    if not ok or value == nil then return nil end
    value = tostring(value)
    return value ~= "" and value or nil
end

function BridgeHudReportCapture(player, value, id)
    local ui = BridgeState.ui
    if ui == nil or ui.reportCaptureInFlight then return end
    ui.reportCaptureInFlight = true
    ui.reportStatus = "Capturing..."
    BridgeUiMarkDirty("report-capture-start")

    local categoryIndex = tonumber(ui.reportCategoryIndex or 1) or 1
    local request = {
        summary = BridgeHudReportSummaryText(),
        category = BRIDGE_REPORT_CATEGORIES[categoryIndex] or "Other",
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
        status = BridgeState.statusHeadline
    }
    BridgeHttp.requestJson("POST", "/api/v1/diagnostics/report", request, function(ok, body, err)
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
        BridgeUiMarkDirty("report-capture-result")
    end)
end

function BridgeHudPhaseElementId(phase)
    local value = string.upper(tostring(phase or ""))
    if string.find(value, "UNTAP", 1, true) then return "BridgePhaseUntap" end
    if string.find(value, "UPKEEP", 1, true) then return "BridgePhaseUpkeep" end
    if string.find(value, "DRAW", 1, true) then return "BridgePhaseDraw" end
    if string.find(value, "COMBAT", 1, true)
        or string.find(value, "ATTACK", 1, true)
        or string.find(value, "BLOCK", 1, true)
        or string.find(value, "DAMAGE", 1, true) then
        return "BridgePhaseCombat"
    end
    if string.find(value, "MAIN", 1, true) then
        if string.find(value, "2", 1, true)
            or string.find(value, "SECOND", 1, true)
            or string.find(value, "POST", 1, true) then
            return "BridgePhaseMain2"
        end
        return "BridgePhaseMain1"
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
    BridgeUiSet("BridgeHudDevToggle", "text", devExpanded and "DEV ▲" or "DEV ▼")
    local reportVisible = devExpanded and ui.reportPanelVisible == true
    local reportCategoryIndex = tonumber(ui.reportCategoryIndex or 1) or 1
    BridgeUiSet("BridgeHudReportPanel", "active", reportVisible and "true" or "false")
    BridgeUiSet("BridgeHudReportOpen", "active", devEnabled and "true" or "false")
    BridgeUiSet("BridgeHudReportCategory", "active", reportVisible and (ui.reportCaptureInFlight and "false" or "true") or "false")
    BridgeUiSet("BridgeHudReportCategory", "text", BRIDGE_REPORT_CATEGORIES[reportCategoryIndex] or "Other")
    BridgeUiSet("BridgeHudReportCapture", "active", reportVisible and (ui.reportCaptureInFlight and "false" or "true") or "false")
    BridgeUiSet("BridgeHudReportCancel", "active", reportVisible and (ui.reportCaptureInFlight and "false" or "true") or "false")
    BridgeUiSet("BridgeHudReportStatus", "text", ui.reportStatus or "")
    BridgeUiSet("BridgeHudReportStatus", "color", string.find(string.upper(tostring(ui.reportStatus or "")), "ERROR", 1, true) and BRIDGE_HUD_COLORS.danger or BRIDGE_HUD_COLORS.success)

    local decision = BridgeState.lastDecision
    local terminal = BridgeState.gameEnded
    local requiresConfirm = decision ~= nil and BridgeDecisionNeedsConfirmation(decision)
    local creatureTypeDecision = decision ~= nil and decision.kind == "creature_type_selection"
    BridgeUiSet("BridgeHudGameControls", "active", (terminal == nil and not requiresConfirm and not creatureTypeDecision) and "true" or "false")
    BridgeUiSet("BridgeHudDecisionControls", "active", (terminal == nil and requiresConfirm) and "true" or "false")

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
