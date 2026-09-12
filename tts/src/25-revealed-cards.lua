-- Viewer-aware projection of structured Forge reveal payloads.
--
-- Forge owns the reveal and its exact CardInstanceIds. This file owns only
-- presentation state: each configured TTS color receives one fixed surface,
-- one fixed magnifier, and one local timer/pin/hover projection.
BRIDGE_REVEAL_SURFACE_SLOTS = 6
BRIDGE_REVEAL_AUTO_DISMISS_SECONDS = 10
BRIDGE_REVEAL_TIMER_MODES = {0, 3, 5, 10}
BRIDGE_REVEAL_SUPPORTED_VIEWER_SEATS = {"forge-player-1", "forge-player-2"}

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

local function BridgeRevealLower(value)
    return string.lower(tostring(value or ""))
end

local function BridgeRevealSeatForColor(color)
    local wanted = BridgeRevealLower(color)
    for seatId, seat in pairs(BRIDGE_SEATS or {}) do
        if BridgeRevealLower(seat.ttsColor) == wanted then return seatId end
    end
    -- Small source-only MoonSharp probes load this module without the full
    -- configuration. The production path always resolves through BRIDGE_SEATS.
    if wanted == "white" then return "forge-player-1" end
    if wanted == "blue" then return "forge-player-2" end
    return nil
end

local function BridgeRevealColorForSeat(seatId)
    local seat = BRIDGE_SEATS and BRIDGE_SEATS[seatId] or nil
    if seat ~= nil then return seat.ttsColor end
    if seatId == "forge-player-1" then return "White" end
    if seatId == "forge-player-2" then return "Blue" end
    return nil
end

local function BridgeRevealColorForViewer(viewer)
    if type(viewer) == "table" then
        if viewer.color ~= nil then return tostring(viewer.color) end
        if viewer.playerColor ~= nil then return tostring(viewer.playerColor) end
    elseif type(viewer) == "string" then
        local color = BridgeRevealColorForSeat(viewer)
        if color ~= nil then return color end
        return viewer
    end
    return tostring(BridgeState.revealCurrentViewerColor or "White")
end

local function BridgeRevealSeatForViewer(viewer)
    if type(viewer) == "string" and BRIDGE_SEATS ~= nil and BRIDGE_SEATS[viewer] ~= nil then
        return viewer
    end
    return BridgeRevealSeatForColor(BridgeRevealColorForViewer(viewer))
end

local function BridgeRevealSurfaceDefinitions()
    local definitions = {}
    -- This is the fixed 1v1 surface inventory. The seat-to-color mapping is
    -- still resolved from BRIDGE_SEATS, so a table color change changes the
    -- viewer identity without changing reveal authorization semantics.
    local firstColor = BridgeRevealColorForSeat("forge-player-1") or "White"
    local secondColor = BridgeRevealColorForSeat("forge-player-2") or "Blue"
    definitions[1] = {color = firstColor, seatId = "forge-player-1", suffix = ""}
    definitions[2] = {color = secondColor, seatId = "forge-player-2", suffix = "Blue"}
    return definitions
end

local function BridgeRevealDefinitionForColor(color)
    local wanted = BridgeRevealLower(color)
    for _, definition in pairs(BridgeRevealSurfaceDefinitions()) do
        if BridgeRevealLower(definition.color) == wanted then return definition end
    end
    return nil
end

local function BridgeRevealViewerState(color)
    BridgeState.revealViewerStateByColor = BridgeState.revealViewerStateByColor or {}
    local definition = BridgeRevealDefinitionForColor(color)
    local normalized = definition and definition.color or tostring(color or "White")
    local state = BridgeState.revealViewerStateByColor[normalized]
    if state == nil then
        state = {
            seatId = definition and definition.seatId or BridgeRevealSeatForColor(normalized),
            activeKey = nil, offset = 1, pinned = false, dismissedKeys = {},
            timerMode = 10, physicalGated = false, gateState = "not-applicable",
            timerGeneration = 0, timerDeadline = nil, hovered = nil,
            magnifier = {active = false, pinned = false, key = nil, instanceId = nil, token = 0, hotkeyToken = nil}
        }
        BridgeState.revealViewerStateByColor[normalized] = state
    end
    BridgeState.revealPreferencesBySeatId = BridgeState.revealPreferencesBySeatId or {}
    local preferences = BridgeState.revealPreferencesBySeatId[state.seatId]
    if preferences == nil then
        preferences = {timerMode = 10, physicalGated = false}
        BridgeState.revealPreferencesBySeatId[state.seatId] = preferences
    end
    state.timerMode = tonumber(preferences.timerMode or 10) or 10
    state.physicalGated = preferences.physicalGated == true
    return state
end

local function BridgeRevealKey(presentation, eventSequence)
    return tostring(presentation.presentationId or "") .. "@"
        .. tostring(eventSequence or presentation.originatingEventSequence or 0)
end

local function BridgeRevealKeyForLifecycle(presentation, eventSequence)
    local exactKey = BridgeRevealKey(presentation, eventSequence)
    if BridgeState.revealedPresentationsByKey ~= nil
        and BridgeState.revealedPresentationsByKey[exactKey] ~= nil then
        return exactKey
    end
    -- A producer may send a lifecycle update with the same authoritative
    -- presentation id but a later event sequence. Lifecycle identity belongs
    -- to the presentation, not to the delivery event, so retire the existing
    -- projection instead of leaving a stale surface behind.
    for key, current in pairs(BridgeState.revealedPresentationsByKey or {}) do
        if current ~= nil and tostring(current.presentationId or "")
            == tostring(presentation.presentationId or "") then
            return key
        end
    end
    return exactKey
end

-- MoonSharp can expose a Lua array received from a host callback with a
-- zero-based numeric key. TTS JSON arrays are normally one-based in Lua, so
-- accept both representations without using card names as identity.
local function BridgeRevealArrayValue(values, index)
    if values == nil then return nil end
    if values[0] ~= nil then return values[index - 1] end
    return values[index]
end

local function BridgeRevealArrayCount(values)
    if values == nil then return 0 end
    local count = 0
    for index, _ in pairs(values) do
        if type(index) == "number" and index >= 0 then count = count + 1 end
    end
    return count
end

local function BridgeRevealStableSort(values, less)
    -- Keep ordering deterministic in TTS and MoonSharp alike. The built-in
    -- table.sort implementation is not consistently available in the small
    -- host callback environments used by the bridge probes.
    local valueCount = BridgeRevealArrayCount(values)
    for index = 2, valueCount do
        local value, cursor = values[index], index - 1
        while cursor >= 1 and less(value, values[cursor]) do
            values[cursor + 1] = values[cursor]
            cursor = cursor - 1
        end
        values[cursor + 1] = value
    end
    return values
end

local function BridgeRevealArrayEntries(values)
    local entries = {}
    local entryCount = 0
    for index, entry in pairs(values or {}) do
        if type(index) == "number" then
            entryCount = entryCount + 1
            entries[entryCount] = {index = index, value = entry}
        end
    end
    return BridgeRevealStableSort(entries, function(left, right) return left.index < right.index end)
end

local function BridgeRevealAppendArray(values, value)
    local nextIndex = 1
    for index, _ in pairs(values or {}) do
        if type(index) == "number" and index >= nextIndex then nextIndex = index + 1 end
    end
    values[nextIndex] = value
    return nextIndex
end

local function BridgeRevealIsDecisionBound(presentation)
    return presentation ~= nil and (presentation.associatedDecisionId ~= nil
        or presentation.acknowledgmentRequired == true)
end

local function BridgeRevealIsPhysicalInteractionSupported(presentation)
    return presentation ~= nil and presentation.physicalInteractionSupported == true
        and tostring(presentation.interactionKind or "") ~= ""
        and BridgeRevealLower(presentation.sourceZone or "library") == "library"
end

local function BridgeRevealPresentationVisibleForSeat(presentation, seatId)
    if presentation == nil or seatId == nil then return false end
    if BridgeRevealLower(presentation.visibility or "public") == "public" then return true end
    -- Payload arrays can arrive from MoonSharp/JSON with either a one-based
    -- or zero-based numeric representation.  Entitlement is an identity
    -- boundary, so inspect all values rather than relying on ipairs.
    for _, entitledSeatId in pairs(presentation.entitledViewerSeatIds or {}) do
        if tostring(entitledSeatId) == tostring(seatId) then return true end
    end
    return false
end

function BridgeRevealViewerMaySee(presentation, viewer)
    return BridgeRevealPresentationVisibleForSeat(presentation, BridgeRevealSeatForViewer(viewer))
end

function BridgeRevealSetCurrentViewer(viewer)
    BridgeState.revealCurrentViewerColor = BridgeRevealColorForViewer(viewer)
    return BridgeRevealSeatForViewer(viewer)
end

function BridgeRevealTimerLabel(mode)
    local value = tonumber(mode or 10) or 10
    return value == 0 and "OFF" or tostring(value) .. " SEC"
end

function BridgeRevealGetPreferences(viewer)
    local seatId = BridgeRevealPreferenceSeat(viewer)
    BridgeRevealViewerState(BridgeRevealColorForSeat(seatId) or "White")
    return BridgeState.revealPreferencesBySeatId[seatId]
end

function BridgeRevealPreferenceSeat(viewer)
    return BridgeRevealSeatForViewer(viewer) or "forge-player-1"
end

function BridgeRevealSetTimerForViewer(viewer, mode)
    local seatId, value = BridgeRevealPreferenceSeat(viewer), tonumber(mode or 0) or 0
    local valid = false
    for _, allowed in ipairs(BRIDGE_REVEAL_TIMER_MODES) do if value == allowed then valid = true end end
    if not valid then return false end
    BridgeState.revealPreferencesBySeatId = BridgeState.revealPreferencesBySeatId or {}
    BridgeState.revealPreferencesBySeatId[seatId] = BridgeState.revealPreferencesBySeatId[seatId] or {}
    BridgeState.revealPreferencesBySeatId[seatId].timerMode = value
    local color = BridgeRevealColorForSeat(seatId)
    if color ~= nil then
        local state = BridgeRevealViewerState(color)
        state.timerMode, state.timerGeneration = value, (state.timerGeneration or 0) + 1
        state.timerDeadline = value > 0 and (BridgeRevealTimerNow() + value) or nil
    end
    BridgeRevealRescheduleTimers()
    BridgeRevealUiDirty("reveal-timer-setting")
    return value
end

function BridgeHudRevealTimerCycle(player, value, id)
    local seatId = BridgeRevealPreferenceSeat(player)
    local preferences = BridgeState.revealPreferencesBySeatId
        and BridgeState.revealPreferencesBySeatId[seatId] or nil
    local current, nextMode = tonumber(preferences and preferences.timerMode or 10) or 10, 0
    for index, mode in ipairs(BRIDGE_REVEAL_TIMER_MODES) do
        if mode == current then nextMode = BRIDGE_REVEAL_TIMER_MODES[(index % #BRIDGE_REVEAL_TIMER_MODES) + 1] end
    end
    BridgeRevealSetTimerForViewer(player, nextMode)
end

function BridgeRevealPhysicalGateLabel(enabled)
    return enabled == true and "ON" or "OFF"
end

function BridgeRevealSetPhysicalGateForViewer(viewer, enabled)
    local seatId = BridgeRevealPreferenceSeat(viewer)
    BridgeState.revealPreferencesBySeatId = BridgeState.revealPreferencesBySeatId or {}
    BridgeState.revealPreferencesBySeatId[seatId] = BridgeState.revealPreferencesBySeatId[seatId] or {}
    BridgeState.revealPreferencesBySeatId[seatId].physicalGated = enabled == true
    local color = BridgeRevealColorForSeat(seatId)
    if color ~= nil then BridgeRevealViewerState(color).physicalGated = enabled == true end
    BridgeRevealUiDirty("reveal-physical-gate-setting")
    return enabled == true
end

function BridgeHudRevealPhysicalGateCycle(player, value, id)
    local seatId = BridgeRevealPreferenceSeat(player)
    local preferences = BridgeState.revealPreferencesBySeatId
        and BridgeState.revealPreferencesBySeatId[seatId] or nil
    BridgeRevealSetPhysicalGateForViewer(player, not (preferences and preferences.physicalGated == true))
end

local function BridgeRevealSetActiveForViewer(color, key, presentation, gateState)
    local state = BridgeRevealViewerState(color)
    local replacing = state.activeKey ~= key
    state.activeKey = key
    if replacing then
        state.offset, state.pinned = 1, false
        state.timerDeadline, state.hovered = nil, nil
        state.timerGeneration = (state.timerGeneration or 0) + 1
        state.magnifier.active, state.magnifier.pinned = false, false
        state.magnifier.key, state.magnifier.instanceId, state.magnifier.hotkeyToken = nil, nil, nil
    end
    state.gateState = gateState or "open"
    return state
end

local function BridgeRevealClearViewer(color, key, rememberDismissal)
    local state = BridgeRevealViewerState(color)
    if key ~= nil and state.activeKey ~= key then return end
    if key ~= nil and rememberDismissal then state.dismissedKeys[key] = true end
    state.activeKey, state.offset, state.pinned = nil, 1, false
    state.gateState, state.timerDeadline, state.hovered = "not-applicable", nil, nil
    state.magnifier.active, state.magnifier.pinned = false, false
    state.magnifier.key, state.magnifier.instanceId, state.magnifier.hotkeyToken = nil, nil, nil
end

local function BridgeRevealAnyProjection(key)
    for _, definition in pairs(BridgeRevealSurfaceDefinitions()) do
        if BridgeRevealViewerState(definition.color).activeKey == key then return true end
    end
    return false
end

local function BridgeRevealRemoveOrderKey(key)
    local order = BridgeState.revealedPresentationOrder or {}
    for index = #order, 1, -1 do
        if order[index] == key then
            for shift = index, #order - 1 do order[shift] = order[shift + 1] end
            order[#order] = nil
        end
    end
end

local function BridgeRevealRemoveIfUnprojected(key)
    if not BridgeRevealAnyProjection(key) then
        BridgeState.revealedPresentationsByKey[key] = nil
        BridgeRevealRemoveOrderKey(key)
    end
end

local function BridgeRevealRetire(key, rememberDismissal)
    if key == nil then return end
    for _, definition in pairs(BridgeRevealSurfaceDefinitions()) do
        BridgeRevealClearViewer(definition.color, key, rememberDismissal == true)
    end
    if BridgeState.activeRevealPresentationKey == key then BridgeState.activeRevealPresentationKey = nil end
    BridgeState.dismissedRevealKeys = BridgeState.dismissedRevealKeys or {}
    BridgeState.dismissedRevealOrder = BridgeState.dismissedRevealOrder or {}
    if rememberDismissal and BridgeState.dismissedRevealKeys[key] ~= true then
        BridgeState.dismissedRevealKeys[key] = true
        table.insert(BridgeState.dismissedRevealOrder, key)
    end
    BridgeRevealRemoveIfUnprojected(key)
end

local function BridgeRevealRetireViewer(color, key, rememberDismissal)
    BridgeRevealClearViewer(color, key, rememberDismissal == true)
    if BridgeRevealLower(color) == BridgeRevealLower(BridgeState.revealCurrentViewerColor or "White")
        and BridgeState.activeRevealPresentationKey == key then BridgeState.activeRevealPresentationKey = nil end
    BridgeRevealRemoveIfUnprojected(key)
end

function BridgeRevealTimerNow()
    return Time and tonumber(Time.time or 0) or 0
end

function BridgeRevealRescheduleTimers()
    local earliest, timerKey, timerPresentation = nil, nil, nil
    for key, presentation in pairs(BridgeState.revealedPresentationsByKey or {}) do
        if not BridgeRevealIsDecisionBound(presentation) then
            for _, definition in pairs(BridgeRevealSurfaceDefinitions()) do
                local state = BridgeRevealViewerState(definition.color)
                if state.activeKey == key and not state.pinned and state.timerMode > 0 then
                    state.timerDeadline = state.timerDeadline or (BridgeRevealTimerNow() + state.timerMode)
                    if earliest == nil or state.timerDeadline < earliest then
                        earliest, timerKey, timerPresentation = state.timerDeadline, key, presentation
                    end
                end
            end
        end
    end
    if timerKey == nil then return end
    BridgeState.revealPresentationGeneration = (BridgeState.revealPresentationGeneration or 0) + 1
    local token = BridgeState.revealPresentationGeneration
    timerPresentation.revealTimerToken = token
    local sessionId, sessionGeneration = BridgeState.eventSessionId, BridgeState.eventSessionGeneration
    local schedule = BridgeWaitTime or function(callback, delay) Wait.time(callback, delay) end
    schedule(function()
        local current = BridgeState.revealedPresentationsByKey[timerKey]
        if current ~= timerPresentation or current.revealTimerToken ~= token
            or BridgeState.eventSessionId ~= sessionId or BridgeState.eventSessionGeneration ~= sessionGeneration then return end
        local dueTime
        for _, definition in pairs(BridgeRevealSurfaceDefinitions()) do
            local state = BridgeRevealViewerState(definition.color)
            if state.activeKey == timerKey and not state.pinned and state.timerMode > 0
                and (dueTime == nil or state.timerDeadline < dueTime) then dueTime = state.timerDeadline end
        end
        for _, definition in pairs(BridgeRevealSurfaceDefinitions()) do
            local state = BridgeRevealViewerState(definition.color)
            if state.activeKey == timerKey and not state.pinned and state.timerMode > 0
                and (state.timerDeadline == dueTime or BridgeRevealTimerNow() >= state.timerDeadline) then
                BridgeRevealRetireViewer(definition.color, timerKey, true)
            end
        end
        timerPresentation.revealTimerToken = nil
        BridgeRevealRescheduleTimers()
        BridgeRevealUiDirty("reveal-auto-dismissed")
    end, math.max(0, earliest - BridgeRevealTimerNow()))
end

function BridgeRevealCardArt(entry)
    if BridgeResolveCanonicalCardArt ~= nil then
        local ok, image = pcall(BridgeResolveCanonicalCardArt, entry.cardFaceIdentity, entry.cardName)
        if ok and image ~= nil and tostring(image) ~= "" then return tostring(image), "canonical" end
    end
    if entry.imageUrl ~= nil and tostring(entry.imageUrl) ~= "" then return tostring(entry.imageUrl), "producer-url" end
    if entry.image ~= nil and tostring(entry.image) ~= "" then return tostring(entry.image), "physical-custom-face" end
    return nil, "fallback-text"
end

function BridgeRevealPresentationNeedsPhysicalGate(presentation, color)
    local state = BridgeRevealViewerState(color)
    return BridgeRevealIsPhysicalInteractionSupported(presentation) and state.physicalGated == true
        and BridgeRevealPresentationVisibleForSeat(presentation, state.seatId)
end

local function BridgeRevealAllowedDestinations(presentation)
    local result = {}
    for _, entry in pairs(BridgeRevealArrayEntries(presentation.allowedPhysicalDestinations)) do
        result[BridgeRevealLower(entry.value)] = true
    end
    if next(result) ~= nil then return result end
    local kind = BridgeRevealLower(presentation.interactionKind)
    if kind == "scry" then return {top = true, bottom = true} end
    if kind == "surveil" then return {top = true, graveyard = true} end
    return {}
end

local function BridgeLibraryLookTargetCenter(session, destination)
    local seat = BRIDGE_SEATS and BRIDGE_SEATS[session.sourceSeatId] or nil
    local anchor = seat and seat.libraryAnchor or {x = 0, y = 2, z = 0}
    local side = seat and (seat.tableSideZ or -1) or -1
    if destination == "bottom" or destination == "graveyard" then
        return {x = anchor.x + 2.8, y = anchor.y, z = anchor.z + side * 2.0, radius = 0.72}
    end
    return {x = anchor.x + 2.8, y = anchor.y, z = anchor.z, radius = 0.72}
end

function BridgeLibraryLookStagingTargets(session)
    local targets = {}
    for destination in pairs(session and session.allowedDestinations or {}) do
        targets[destination] = BridgeLibraryLookTargetCenter(session, destination)
    end
    return targets
end

local function BridgeLibraryLookCreateStagingAffordances(session)
    session.stagingTargets, session.stagingMarkers = BridgeLibraryLookStagingTargets(session), {}
    if type(spawnObject) ~= "function" then return end
    for destination, target in pairs(session.stagingTargets) do
        local capturedSession = session
        pcall(function()
            spawnObject({type = "BlockSquare", position = {target.x, target.y - 0.35, target.z},
                scale = {1.55, 0.25, 1.05}, callback_function = function(marker)
                    if BridgeState.libraryLookInteractionSession ~= capturedSession then
                        if BridgeObjectIsUsable ~= nil and BridgeObjectIsUsable(marker)
                            and marker.destruct ~= nil then pcall(function() marker.destruct() end) end
                        return
                    end
                    if BridgeObjectIsUsable ~= nil and not BridgeObjectIsUsable(marker) then return end
                    pcall(function() marker.setName("ForgeBot " .. string.upper(destination)) end)
                    pcall(function() marker.setLock(true) end)
                    capturedSession.stagingMarkers[destination] = marker
                end})
        end)
    end
end

local function BridgeLibraryLookDestroyStagingAffordances(session)
    for _, marker in pairs(session and session.stagingMarkers or {}) do
        if marker ~= nil and marker.destruct ~= nil then pcall(function() marker.destruct() end) end
    end
    if session ~= nil then session.stagingMarkers = {} end
end

function BridgeEndLibraryLookInteractionSession(reason)
    local session = BridgeState.libraryLookInteractionSession
    if session == nil then return false end
    session.lifecycle, session.retirementReason = "retired", tostring(reason or "ended")
    BridgeLibraryLookDestroyStagingAffordances(session)
    BridgeState.libraryLookInteractionSession = nil
    BridgeState.libraryLookSessionGeneration = (BridgeState.libraryLookSessionGeneration or 0) + 1
    BridgeRevealUiDirty("library-look-retired")
    return true
end

local function BridgeLibraryLookReject(reason)
    BridgeState.libraryLookLastFailure = tostring(reason or "rejected")
    return false
end

local function BridgeRevealStoredKey(presentation)
    for key, current in pairs(BridgeState.revealedPresentationsByKey or {}) do
        if current == presentation then return key end
    end
    return BridgeRevealKey(presentation, presentation and presentation.originatingEventSequence or 0)
end

function BridgeBeginLibraryLookInteractionSession(presentation, decision)
    if not BridgeRevealIsPhysicalInteractionSupported(presentation) then return BridgeLibraryLookReject("unsupported-reveal-semantics") end
    local sourceSeatId = presentation.revealingSeatId or (decision and decision.seatId)
    if sourceSeatId == nil or (BRIDGE_SEATS ~= nil and BRIDGE_SEATS[sourceSeatId] == nil) then return BridgeLibraryLookReject("missing-source-seat") end
    local allowed = BridgeRevealAllowedDestinations(presentation)
    if next(allowed) == nil then return BridgeLibraryLookReject("no-allowed-destination") end
    local expected, expectedById, expectedCount = {}, {}, 0
    for _, cardEntry in pairs(BridgeRevealArrayEntries(presentation.cards)) do
        local entry = cardEntry.value
        local instanceId = entry and entry.authoritativeObjectId or nil
        if instanceId == nil or tostring(instanceId) == "" or expectedById[instanceId] ~= nil then return BridgeLibraryLookReject("invalid-or-duplicate-expected-card") end
        expectedCount = expectedCount + 1
        expectedById[instanceId], expected[expectedCount] = entry, instanceId
    end
    if expectedCount == 0 then return BridgeLibraryLookReject("no-expected-cards") end
    BridgeEndLibraryLookInteractionSession("replaced")
    BridgeState.libraryLookSessionGeneration = (BridgeState.libraryLookSessionGeneration or 0) + 1
    local session = {
        sessionKey = BridgeRevealKey(presentation, presentation.originatingEventSequence) .. "|"
            .. tostring(decision and decision.decisionId or presentation.associatedDecisionId or ""),
        presentationId = presentation.presentationId,
        presentationKey = BridgeRevealStoredKey(presentation),
        decisionId = decision and decision.decisionId or presentation.associatedDecisionId,
        sessionId = BridgeState.eventSessionId, sessionGeneration = BridgeState.eventSessionGeneration,
        generation = BridgeState.libraryLookSessionGeneration, sourceSeatId = sourceSeatId,
        sourceZone = presentation.sourceZone or "library", interactionKind = presentation.interactionKind,
        expectedCount = expectedCount, expectedInstanceIds = expected,
        expectedByInstanceId = expectedById, allowedDestinations = allowed,
        observedPhysicalCards = {}, observedPhysicalObjects = {}, stagedDestinationByInstanceId = {},
        destinationGroups = {top = {}, bottom = {}, graveyard = {}},
        lifecycle = "waiting-for-drop", completionState = "waiting-for-drop"
    }
    BridgeState.libraryLookInteractionSession = session
    BridgeState.libraryLookLastFailure = nil
    BridgeLibraryLookCreateStagingAffordances(session)
    return session
end

local function BridgeLibraryLookObjectGuid(object)
    if object == nil then return nil end
    if BridgeSafeObjectGuid ~= nil then return BridgeSafeObjectGuid(object) end
    if type(object.getGUID) == "function" then
        local ok, guid = pcall(function() return object.getGUID() end)
        if ok then return guid end
    end
    return nil
end

local function BridgeLibraryLookInstanceIds(object)
    local guid = BridgeLibraryLookObjectGuid(object)
    if object ~= nil and object.tag == "Deck" and type(object.getObjects) == "function" then
        local ok, entries = pcall(function() return object.getObjects() or {} end)
        if not ok then return {}, {} end
        local deckGuid = guid and tostring(guid) or nil
        local instanceIds, guidByInstanceId, indexByInstanceId, instanceCount = {}, {}, {}, 0
        for nativeIndex, entry in pairs(entries) do
            local entryGuid = entry and (entry.guid or entry.GUID) or nil
            local containedByGuid = BridgeState.physicalContainedInstanceIdByGuid or {}
            local instanceId = entryGuid and (containedByGuid[entryGuid]
                or containedByGuid[tostring(entryGuid)]) or nil
            if instanceId == nil and entryGuid ~= nil then
                for knownGuid, knownInstanceId in pairs(containedByGuid) do
                    if tostring(knownGuid) == tostring(entryGuid) then
                        instanceId = knownInstanceId
                        break
                    end
                end
            end
            if instanceId == nil and entryGuid ~= nil then
                for candidateId, mapping in pairs(BridgeState.physicalContainerByInstanceId or {}) do
                    if tostring(mapping.deckGuid or "") == deckGuid
                        and tostring(mapping.cardGuid or "") == tostring(entryGuid) then
                        instanceId = candidateId
                        break
                    end
                end
            end
            if instanceId ~= nil then
                instanceCount = instanceCount + 1
                instanceIds[instanceCount] = instanceId
                guidByInstanceId[instanceId] = entryGuid
                indexByInstanceId[instanceId] = tonumber(entry and entry.index or nativeIndex)
            end
        end
        return instanceIds, guidByInstanceId, indexByInstanceId, instanceCount
    end
    if guid ~= nil and BridgeState.physicalInstanceIdByGuid ~= nil then
        local instanceId = BridgeState.physicalInstanceIdByGuid[guid]
        if instanceId ~= nil then
            local instanceIds, guidByInstanceId = {}, {}
            instanceIds[1], guidByInstanceId[instanceId] = instanceId, guid
            return instanceIds, guidByInstanceId, {}, 1
        end
    end
    if BridgeReadPhysicalIdentity ~= nil then
        local instanceId = BridgeReadPhysicalIdentity(object)
        if instanceId ~= nil then
            local instanceIds, guidByInstanceId = {}, {}
            instanceIds[1], guidByInstanceId[instanceId] = instanceId, guid
            return instanceIds, guidByInstanceId, {}, 1
        end
    end
    return {}, {}, {}, 0
end

local function BridgeLibraryLookDropDestination(session, object)
    if object == nil or type(object.getPosition) ~= "function" then return nil end
    local ok, position = pcall(function() return object.getPosition() end)
    if not ok or position == nil then return nil end
    for destination, target in pairs(session.stagingTargets or {}) do
        local dx = (position.x or position[1] or 0) - target.x
        local dz = (position.z or position[3] or 0) - target.z
        local radius = 0.72
        if math.abs(dx) <= radius and math.abs(dz) <= radius then return destination end
    end
    return nil
end

local function BridgeLibraryLookRemoveFromGroups(session, instanceId)
    for _, group in pairs(session.destinationGroups or {}) do
        for index = #group, 1, -1 do if group[index] == instanceId then table.remove(group, index) end end
    end
    session.stagedDestinationByInstanceId[instanceId] = nil
end

local function BridgeLibraryLookOpenViewer(session, color)
    local presentation = BridgeState.revealedPresentationsByKey[session.presentationKey]
    if presentation == nil or not BridgeRevealPresentationVisibleForSeat(presentation, BridgeRevealSeatForColor(color)) then return end
    local state = BridgeRevealSetActiveForViewer(color, session.presentationKey, presentation, "opened-by-physical-drop")
    state.gateState = "opened"
    BridgeRevealRescheduleTimers()
end

function BridgeLibraryLookHandleDrop(playerColor, object)
    local session = BridgeState.libraryLookInteractionSession
    if session == nil or (session.lifecycle ~= "waiting-for-drop" and session.lifecycle ~= "active") or object == nil then return false end
    if session.sessionId ~= BridgeState.eventSessionId or session.sessionGeneration ~= BridgeState.eventSessionGeneration then
        BridgeEndLibraryLookInteractionSession("stale-session-callback")
        return false
    end
    local viewerSeatId = BridgeRevealSeatForViewer(playerColor)
    local isEntitled = viewerSeatId == session.sourceSeatId
    local presentation = BridgeState.revealedPresentationsByKey[session.presentationKey]
    if presentation ~= nil and BridgeRevealLower(presentation.visibility or "public") ~= "public" then
        isEntitled = isEntitled and BridgeRevealPresentationVisibleForSeat(presentation, viewerSeatId)
    end
    -- While Forge owns this interaction, every drop is consumed by the
    -- library-look gate. This keeps a foreign card from falling through to
    -- the ordinary action-intent handler and accidentally becoming a spell or
    -- zone choice. Non-owners still cannot unlock the private projection.
    if not isEntitled then return true end
    local instanceIds, guidByInstanceId, indexByInstanceId, instanceCount = BridgeLibraryLookInstanceIds(object)
    if instanceCount == 0 then return true end
    local seenInObject = {}
    for index = 1, instanceCount do
        local instanceId = instanceIds[index]
        if seenInObject[instanceId] or session.expectedByInstanceId[instanceId] == nil
            or (session.sessionId ~= nil and BridgeCardInstanceBelongsToSession ~= nil
                and not BridgeCardInstanceBelongsToSession(instanceId, session.sessionId)) then
            return true
        end
        seenInObject[instanceId] = true
    end
    local destination = BridgeLibraryLookDropDestination(session, object)
    if destination == nil or session.allowedDestinations[destination] ~= true then return true end
    local position = nil
    if type(object.getPosition) == "function" then
        local positionOk, observedPosition = pcall(function() return object.getPosition() end)
        if positionOk then position = observedPosition end
    end
    for index = 1, instanceCount do
        local instanceId = instanceIds[index]
        BridgeLibraryLookRemoveFromGroups(session, instanceId)
        BridgeRevealAppendArray(session.destinationGroups[destination], instanceId)
        session.stagedDestinationByInstanceId[instanceId] = destination
        session.observedPhysicalCards[instanceId] = {
            guid = guidByInstanceId[instanceId], nativeIndex = indexByInstanceId[instanceId],
            destination = destination, position = position}
        session.observedPhysicalObjects[instanceId] = object
    end
    session.lifecycle, session.completionState = "active", "staging"
    local viewerColor = BridgeRevealColorForSeat(viewerSeatId)
    if viewerColor ~= nil and BridgeRevealPresentationNeedsPhysicalGate(presentation, viewerColor) then
        BridgeLibraryLookOpenViewer(session, viewerColor)
    end
    -- Public physical interaction is owned by the revealing/deciding seat,
    -- but the resulting exact drop is meaningful to every public projection
    -- whose local gate is enabled. A secondary viewer must not remain hidden
    -- forever merely because that viewer cannot own the Forge interaction.
    if presentation ~= nil and BridgeRevealLower(presentation.visibility or "public") == "public" then
        for _, definition in pairs(BridgeRevealSurfaceDefinitions()) do
            if BridgeRevealPresentationNeedsPhysicalGate(presentation, definition.color) then
                BridgeLibraryLookOpenViewer(session, definition.color)
            end
        end
    end
    BridgeRevealUiDirty("library-look-card-staged")
    return true
end

local function BridgeLibraryLookCurrentPlacement(session, instanceId)
    local observed = session.observedPhysicalCards and session.observedPhysicalCards[instanceId] or nil
    local object = session.observedPhysicalObjects and session.observedPhysicalObjects[instanceId] or nil
    local usable = object ~= nil
    if usable and BridgeObjectIsUsable ~= nil then usable = BridgeObjectIsUsable(object) == true end
    if usable and object.tag == "Deck" and type(object.getObjects) == "function" then
        local ok, _, _, indexByInstanceId = pcall(function()
            return BridgeLibraryLookInstanceIds(object)
        end)
        local nativeIndex = ok and indexByInstanceId and indexByInstanceId[instanceId] or nil
        if nativeIndex ~= nil then
            return {kind = "deck", containerGuid = BridgeLibraryLookObjectGuid(object), index = tonumber(nativeIndex)}
        end
    elseif usable and type(object.getPosition) == "function" then
        local ok, position = pcall(function() return object.getPosition() end)
        if ok and position ~= nil then
            return {kind = "loose", containerGuid = BridgeLibraryLookObjectGuid(object), position = position}
        end
    end

    local mapping = BridgeState.physicalContainerByInstanceId
        and BridgeState.physicalContainerByInstanceId[instanceId] or nil
    if mapping ~= nil then
        return {kind = "deck", containerGuid = mapping.deckGuid,
            index = tonumber(mapping.slotIndex or mapping.index)}
    end
    if observed ~= nil then
        return {kind = "loose", containerGuid = observed.guid, index = tonumber(observed.nativeIndex),
            position = observed.position}
    end
    return {kind = "unknown", containerGuid = nil}
end

local function BridgeLibraryLookSortGroup(session, group)
    local copy = {}
    local copyCount = 0
    for _, entry in pairs(BridgeRevealArrayEntries(group)) do
        copyCount = copyCount + 1
        copy[copyCount] = entry.value
    end
    local placementByInstanceId = {}
    for _, instanceId in pairs(copy) do
        placementByInstanceId[instanceId] = BridgeLibraryLookCurrentPlacement(session, instanceId)
    end
    BridgeRevealStableSort(copy, function(left, right)
        local lpInfo, rpInfo = placementByInstanceId[left] or {}, placementByInstanceId[right] or {}
        if lpInfo.kind == "deck" and rpInfo.kind == "deck"
            and tostring(lpInfo.containerGuid or "") == tostring(rpInfo.containerGuid or "") then
            local li, ri = lpInfo.index, rpInfo.index
            if li ~= nil and ri ~= nil and li ~= ri then return li < ri end
        end
        local lp, rp = lpInfo.position, rpInfo.position
        local lx = lp and tonumber(lp.x or lp[1]) or nil
        local rx = rp and tonumber(rp.x or rp[1]) or nil
        if lx ~= nil and rx ~= nil and lx ~= rx then return lx < rx end
        local lz = lp and tonumber(lp.z or lp[3]) or nil
        local rz = rp and tonumber(rp.z or rp[3]) or nil
        if lz ~= nil and rz ~= nil and lz ~= rz then return lz < rz end
        local lc, rc = tostring(lpInfo.containerGuid or ""), tostring(rpInfo.containerGuid or "")
        if lc ~= rc then return lc < rc end
        return tostring(left) < tostring(right)
    end)
    return copy
end

function BridgeLibraryLookBuildIntent()
    local session = BridgeState.libraryLookInteractionSession
    if session == nil or session.lifecycle == "retired" then return nil, "no active library-look session" end
    local seen, destinations, accounted = {}, {}, 0
    for destination, group in pairs(session.destinationGroups or {}) do
        if session.allowedDestinations[destination] == true then
            destinations[destination] = BridgeLibraryLookSortGroup(session, group)
            for _, entry in pairs(BridgeRevealArrayEntries(destinations[destination])) do
                local instanceId = entry.value
                if seen[instanceId] then return nil, "duplicate expected CardInstanceId in staging" end
                if session.expectedByInstanceId[instanceId] == nil then return nil, "foreign CardInstanceId in staging" end
                seen[instanceId], accounted = true, accounted + 1
            end
        end
    end
    if accounted ~= session.expectedCount then return nil, "library-look staging is missing expected cards" end
    for _, entry in pairs(BridgeRevealArrayEntries(session.expectedInstanceIds)) do
        local instanceId = entry.value
        if not seen[instanceId] then return nil, "expected CardInstanceId has no destination" end
    end
    return {sessionKey = session.sessionKey, presentationId = session.presentationId,
        decisionId = session.decisionId, interactionKind = session.interactionKind,
        destinations = destinations}, nil
end

function BridgeLibraryLookFinalizeIntent()
    local intent, errorMessage = BridgeLibraryLookBuildIntent()
    if intent == nil then return false, errorMessage end
    if BridgeLibraryLookSubmitIntent ~= nil then return BridgeLibraryLookSubmitIntent(intent, BridgeState.libraryLookInteractionSession) end
    return true, intent
end

function BridgeResetRevealSessionState(reason)
    if BridgeState.libraryLookInteractionSession ~= nil then BridgeEndLibraryLookInteractionSession(reason or "session-reset") end
    BridgeState.revealedPresentationsByKey, BridgeState.revealedPresentationOrder = {}, {}
    BridgeState.dismissedRevealKeys, BridgeState.dismissedRevealOrder = {}, {}
    BridgeState.activeRevealPresentationKey, BridgeState.revealSurfaceOffset = nil, 1
    BridgeState.revealViewerStateByColor = {}
    BridgeState.revealMagnifierGeneration = (BridgeState.revealMagnifierGeneration or 0) + 1
    BridgeState.revealPresentationGeneration = (BridgeState.revealPresentationGeneration or 0) + 1
    BridgeState.libraryLookLastFailure = nil
end

function BridgeApplyRevealPresentation(presentation, appliedEventSequence)
    if presentation == nil then return false end
    local sequence = tonumber(appliedEventSequence or presentation.originatingEventSequence or 0) or 0
    if sequence > (tonumber(BridgeState.lastAppliedEventSequence or 0) or 0) then return false end
    local key, lifecycle = BridgeRevealKeyForLifecycle(presentation, sequence), BridgeRevealLower(presentation.lifecycle or "opened")
    if lifecycle == "resolved" or lifecycle == "dismissed" then
        BridgeRevealRetire(key, true); BridgeRevealUiDirty("reveal-closed"); return true
    end
    BridgeState.revealedPresentationsByKey = BridgeState.revealedPresentationsByKey or {}
    if BridgeState.revealedPresentationsByKey[key] == nil then table.insert(BridgeState.revealedPresentationOrder, key) end
    BridgeState.revealedPresentationsByKey[key] = presentation
    local existingSession, needsPhysicalSession, hasProjection = BridgeState.libraryLookInteractionSession, false, false
    for _, definition in pairs(BridgeRevealSurfaceDefinitions()) do
        local state = BridgeRevealViewerState(definition.color)
        if BridgeRevealPresentationVisibleForSeat(presentation, definition.seatId) then
            hasProjection = true
            local gated = BridgeRevealPresentationNeedsPhysicalGate(presentation, definition.color)
            needsPhysicalSession = needsPhysicalSession or gated
            if state.dismissedKeys[key] ~= true then
                if state.activeKey ~= nil and state.activeKey ~= key then
                    BridgeRevealRetireViewer(definition.color, state.activeKey, true)
                end
                if not gated then BridgeRevealSetActiveForViewer(definition.color, key, presentation, "open")
                else state.activeKey, state.gateState = nil, "waiting-for-drop" end
            end
        else
            BridgeRevealClearViewer(definition.color, key, false)
        end
    end
    if needsPhysicalSession and (existingSession == nil or existingSession.presentationKey ~= key) then
        BridgeBeginLibraryLookInteractionSession(presentation, nil)
    elseif not needsPhysicalSession and existingSession ~= nil then
        -- A new authoritative presentation retires any prior physical-look
        -- session, even when the replacement is informational or has a
        -- different presentation key.  Otherwise a stale drop could still
        -- consume a card after the UI has moved on.
        BridgeEndLibraryLookInteractionSession("gate-disabled-or-replaced")
    end
    local defaultState = BridgeRevealViewerState(BridgeState.revealCurrentViewerColor or "White")
    BridgeState.activeRevealPresentationKey, BridgeState.revealSurfaceOffset = defaultState.activeKey, defaultState.offset
    if not hasProjection then
        -- Do not retain a private payload that no configured viewer is
        -- entitled to inspect. The authoritative event remains in the Forge
        -- event history; this presentation cache is only a viewer projection.
        BridgeState.revealedPresentationsByKey[key] = nil
        BridgeRevealRemoveOrderKey(key)
        return false
    end
    BridgeRevealRescheduleTimers(); BridgeRevealUiDirty("reveal-updated")
    return defaultState.activeKey == key or BridgeRevealViewerMaySee(presentation)
end

function BridgeResolveRevealForDecision(decision)
    local keys = {}
    for _, definition in pairs(BridgeRevealSurfaceDefinitions()) do
        local state = BridgeRevealViewerState(definition.color)
        local p = state.activeKey and BridgeState.revealedPresentationsByKey[state.activeKey] or nil
        if p ~= nil and p.associatedDecisionId ~= nil and (decision == nil or decision.decisionId ~= p.associatedDecisionId) then
            keys[state.activeKey] = true
        end
    end
    for key in pairs(keys) do BridgeRevealRetire(key, true) end
    if next(keys) ~= nil then BridgeRevealUiDirty("reveal-decision-ended") end
end

function BridgeRestoreAuthoritativeReveals(snapshot)
    for _, entry in pairs(BridgeRevealArrayEntries(snapshot and (snapshot.activeRevealPresentations or snapshot.revealPresentations))) do
        local presentation = entry.value
        local sequence = tonumber(presentation and presentation.originatingEventSequence or 0) or 0
        if presentation ~= nil and BridgeRevealLower(presentation.lifecycle or "opened") == "opened"
            and sequence <= (tonumber(BridgeState.lastAppliedEventSequence or 0) or 0) then BridgeApplyRevealPresentation(presentation, sequence) end
    end
end

local function BridgeRevealSlotFromId(id)
    return tonumber(string.match(tostring(id or ""), "(%d+)$"))
end

function BridgeHudRevealInteract(player, value, id)
    local color, state = BridgeRevealColorForViewer(player), BridgeRevealViewerState(BridgeRevealColorForViewer(player))
    local key, presentation = state.activeKey, state.activeKey and BridgeState.revealedPresentationsByKey[state.activeKey] or nil
    if presentation == nil or not BridgeRevealViewerMaySee(presentation, player) then return false end
    state.pinned, state.timerDeadline = true, nil
    -- Compatibility diagnostic only; timeout behavior is per-viewer above.
    presentation.pinnedByUser = true
    BridgeRevealUiDirty("reveal-pinned"); return true
end

function BridgeHudRevealScroll(player, value, id)
    local color, state = BridgeRevealColorForViewer(player), BridgeRevealViewerState(BridgeRevealColorForViewer(player))
    local presentation = state.activeKey and BridgeState.revealedPresentationsByKey[state.activeKey] or nil
    if presentation == nil then return end
    BridgeHudRevealInteract(player, value, id)
    local cardCount = BridgeRevealArrayCount(presentation.cards)
    local maxOffset, offset = math.max(1, cardCount - BRIDGE_REVEAL_SURFACE_SLOTS + 1), tonumber(state.offset or 1) or 1
    if string.find(tostring(id or ""), "Prev", 1, true) ~= nil then offset = offset - 1 else offset = offset + 1 end
    state.offset = math.min(math.max(offset, 1), maxOffset)
    if BridgeRevealLower(color) == BridgeRevealLower(BridgeState.revealCurrentViewerColor or "White") then BridgeState.revealSurfaceOffset = state.offset end
    BridgeRevealUiDirty("reveal-scroll")
end

function BridgeHudRevealClose(player, value, id)
    local color, state = BridgeRevealColorForViewer(player), BridgeRevealViewerState(BridgeRevealColorForViewer(player))
    local key, presentation = state.activeKey, state.activeKey and BridgeState.revealedPresentationsByKey[state.activeKey] or nil
    if presentation == nil then return end
    BridgeHudRevealInteract(player, value, id)
    if BridgeRevealIsDecisionBound(presentation) then return end
    BridgeRevealRetireViewer(color, key, true); BridgeRevealUiDirty("reveal-dismissed")
end

function BridgeHudRevealCardHoverEnter(player, value, id)
    local color, state = BridgeRevealColorForViewer(player), BridgeRevealViewerState(BridgeRevealColorForViewer(player))
    local p, slot = state.activeKey and BridgeState.revealedPresentationsByKey[state.activeKey] or nil, BridgeRevealSlotFromId(id)
    local entry = slot and p and BridgeRevealArrayValue(p.cards, (state.offset or 1) + slot - 1) or nil
    if entry == nil or not BridgeRevealViewerMaySee(p, player) then return end
    state.hovered = {key = state.activeKey, slot = slot, instanceId = entry.authoritativeObjectId}
end

function BridgeHudRevealCardHoverExit(player, value, id)
    local state = BridgeRevealViewerState(BridgeRevealColorForViewer(player))
    if state.hovered ~= nil and (id == nil or state.hovered.slot == BridgeRevealSlotFromId(id)) then state.hovered = nil end
end

function BridgeHudRevealCard(player, value, id)
    if not BridgeHudRevealInteract(player, value, id) then return end
    local state, slot = BridgeRevealViewerState(BridgeRevealColorForViewer(player)), BridgeRevealSlotFromId(id)
    local p = state.activeKey and BridgeState.revealedPresentationsByKey[state.activeKey] or nil
    local entry = slot and p and BridgeRevealArrayValue(p.cards, (state.offset or 1) + slot - 1) or nil
    if entry ~= nil and BridgeRevealCardInteractionHandler ~= nil then BridgeRevealCardInteractionHandler(p, entry, player) end
end

local function BridgeRevealMagnifierRender(color)
    local definition, state = BridgeRevealDefinitionForColor(color), BridgeRevealViewerState(color)
    if definition == nil then return end
    local suffix, prefix = definition.suffix, "BridgeHudRevealMagnifier" .. definition.suffix
    local p = state.magnifier.key and BridgeState.revealedPresentationsByKey[state.magnifier.key] or nil
    local entry
    if state.magnifier.active and p ~= nil and BridgeRevealViewerMaySee(p, definition.color) then
        for index = 1, BridgeRevealArrayCount(p.cards) do
            local candidate = BridgeRevealArrayValue(p.cards, index)
            if candidate ~= nil and candidate.authoritativeObjectId == state.magnifier.instanceId then entry = candidate end
        end
    end
    local image = entry and BridgeRevealCardArt(entry) or nil
    BridgeUiSet(prefix .. "Overlay", "active", entry ~= nil and "true" or "false")
    BridgeUiSet(prefix .. "Image", "active", entry ~= nil and image ~= nil and "true" or "false")
    BridgeUiSet(prefix .. "Image", "image", image or "")
    BridgeUiSet(prefix .. "Fallback", "active", entry ~= nil and image == nil and "true" or "false")
    BridgeUiSet(prefix .. "Fallback", "text", entry and tostring(entry.cardName or "Revealed card") or "")
    BridgeUiSet(prefix .. "Heading", "text", entry and "MAGNIFIED REVEAL" or "")
end

function BridgeRevealMagnifyPress(viewer)
    local color, state = BridgeRevealColorForViewer(viewer), BridgeRevealViewerState(BridgeRevealColorForViewer(viewer))
    local hovered = state.hovered
    local p = hovered and BridgeState.revealedPresentationsByKey[hovered.key] or nil
    if hovered == nil or p == nil or state.activeKey ~= hovered.key or not BridgeRevealViewerMaySee(p, viewer) then return false end
    BridgeState.revealMagnifierGeneration = (BridgeState.revealMagnifierGeneration or 0) + 1
    state.magnifier = {active = true, pinned = false, key = hovered.key, instanceId = hovered.instanceId, token = BridgeState.revealMagnifierGeneration}
    BridgeRevealMagnifierRender(color); return true, state.magnifier.token
end

function BridgeRevealMagnifyRelease(viewer, token)
    local color, state = BridgeRevealColorForViewer(viewer), BridgeRevealViewerState(BridgeRevealColorForViewer(viewer))
    if not state.magnifier.active or state.magnifier.pinned then return false end
    if token ~= nil and tonumber(token) ~= tonumber(state.magnifier.token) then return false end
    state.magnifier.active = false; BridgeRevealMagnifierRender(color); return true
end

function BridgeHudRevealMagnifyToggle(player, value, id)
    local state = BridgeRevealViewerState(BridgeRevealColorForViewer(player))
    if state.magnifier.active then state.magnifier.pinned = false; return BridgeRevealMagnifyRelease(player) end
    local opened = BridgeRevealMagnifyPress(player)
    if opened then state.magnifier.pinned = true end
    return opened
end

function BridgeRevealMagnifyHotkey(playerColor, isKeyUp)
    local color = BridgeRevealColorForViewer(playerColor)
    local state = BridgeRevealViewerState(color)
    if isKeyUp == true or BridgeRevealLower(isKeyUp) == "keyup" then
        local token = state.magnifier.hotkeyToken
        state.magnifier.hotkeyToken = nil
        if token == nil then return false end
        return BridgeRevealMagnifyRelease(playerColor, token)
    end
    local opened, token = BridgeRevealMagnifyPress(playerColor)
    if opened then state.magnifier.hotkeyToken = token end
    return opened, token
end

function BridgeRegisterRevealHotkey()
    if type(addHotkey) ~= "function" then return false end
    return pcall(function() addHotkey("ForgeBot: Magnify Revealed Card", BridgeRevealMagnifyHotkey, true) end)
end

local function BridgeRevealRenderViewer(definition)
    local state = BridgeRevealViewerState(definition.color)
    local key, presentation = state.activeKey, state.activeKey and BridgeState.revealedPresentationsByKey[state.activeKey] or nil
    local visible = presentation ~= nil and BridgeRevealPresentationVisibleForSeat(presentation, definition.seatId)
        and state.gateState ~= "waiting-for-drop"
    local suffix = definition.suffix
    local function id(base) return "BridgeHudReveal" .. base .. suffix end
    BridgeUiSet(id("Surface"), "active", visible and "true" or "false")
    if visible then
        local cards, offset = presentation.cards or {}, tonumber(state.offset or 1) or 1
        local cardCount = BridgeRevealArrayCount(cards)
        local maxOffset = math.max(1, cardCount - BRIDGE_REVEAL_SURFACE_SLOTS + 1)
        offset = math.min(math.max(offset, 1), maxOffset); state.offset = offset
        local endIndex, artSources = math.min(cardCount, offset + BRIDGE_REVEAL_SURFACE_SLOTS - 1), {}
        BridgeUiSet(id("Heading"), "text", "REVEALED CARDS (" .. tostring(cardCount) .. ")")
        BridgeUiSet(id("Reason"), "text", tostring(presentation.reason or presentation.sourceName or ""))
        for slot = 1, BRIDGE_REVEAL_SURFACE_SLOTS do
            local entry, image, source = BridgeRevealArrayValue(cards, offset + slot - 1), nil, nil
            if entry ~= nil then image, source = BridgeRevealCardArt(entry) end
            BridgeUiSet(id("Card" .. tostring(slot)), "active", entry ~= nil and "true" or "false")
            BridgeUiSet(id("Image" .. tostring(slot)), "active", entry ~= nil and image ~= nil and "true" or "false")
            BridgeUiSet(id("Image" .. tostring(slot)), "image", image or "")
            BridgeUiSet(id("Fallback" .. tostring(slot)), "active", entry ~= nil and image == nil and "true" or "false")
            BridgeUiSet(id("Fallback" .. tostring(slot)), "text", entry and tostring(entry.cardName or "Revealed card") or "")
            BridgeUiSet(id("Card" .. tostring(slot)), "tooltip", entry and tostring(entry.cardName or "Revealed card") or "")
            BridgeUiSet(id("CardButton" .. tostring(slot)), "active", entry ~= nil and "true" or "false")
            if entry ~= nil and source ~= nil then artSources[source] = (artSources[source] or 0) + 1 end
        end
        BridgeUiSet(id("Prev"), "active", offset > 1 and "true" or "false")
        BridgeUiSet(id("Next"), "active", endIndex < cardCount and "true" or "false")
        BridgeUiSet(id("Count"), "text", cardCount > BRIDGE_REVEAL_SURFACE_SLOTS and (tostring(offset) .. "-" .. tostring(endIndex) .. " / " .. tostring(cardCount)) or "")
        BridgeUiSet(id("Close"), "active", not BridgeRevealIsDecisionBound(presentation) and "true" or "false")
        BridgeUiSet(id("Close"), "text", presentation.acknowledgmentRequired == true and "ACKNOWLEDGE" or "CLOSE")
        local sourceText = ""
        local function appendSource(sourceName)
            if artSources[sourceName] == nil then return end
            if sourceText ~= "" then sourceText = sourceText .. " | " end
            sourceText = sourceText .. sourceName .. ":" .. tostring(artSources[sourceName])
        end
        appendSource("canonical")
        appendSource("producer-url")
        appendSource("physical-custom-face")
        appendSource("fallback-text")
        BridgeUiSet(id("ArtSource"), "text", sourceText)
    else
        BridgeUiSet(id("Heading"), "text", "")
        BridgeUiSet(id("Reason"), "text", "")
        BridgeUiSet(id("Count"), "text", "")
        BridgeUiSet(id("ArtSource"), "text", "")
        BridgeUiSet(id("Prev"), "active", "false")
        BridgeUiSet(id("Next"), "active", "false")
        BridgeUiSet(id("Close"), "active", "false")
        for slot = 1, BRIDGE_REVEAL_SURFACE_SLOTS do
            BridgeUiSet(id("Card" .. tostring(slot)), "active", "false")
            BridgeUiSet(id("CardButton" .. tostring(slot)), "active", "false")
            BridgeUiSet(id("Image" .. tostring(slot)), "image", "")
            BridgeUiSet(id("Card" .. tostring(slot)), "tooltip", "")
            BridgeUiSet(id("Fallback" .. tostring(slot)), "text", "")
        end
    end
    BridgeRevealMagnifierRender(definition.color)
end

function BridgeRenderRevealSurface()
    for _, definition in pairs(BridgeRevealSurfaceDefinitions()) do BridgeRevealRenderViewer(definition) end
    local state = BridgeRevealViewerState(BridgeState.revealCurrentViewerColor or "White")
    BridgeState.activeRevealPresentationKey, BridgeState.revealSurfaceOffset = state.activeKey, state.offset
end
