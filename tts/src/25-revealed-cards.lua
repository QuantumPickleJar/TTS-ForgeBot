-- Read-only projection of structured Forge reveal payloads. This surface is
-- separate from zones, decisions, combat highlights, and the event cursor.
BRIDGE_REVEAL_SURFACE_SLOTS = 6
BRIDGE_REVEAL_AUTO_DISMISS_SECONDS = 10

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

local function BridgeRevealIsDecisionBound(presentation)
    return presentation ~= nil and (presentation.associatedDecisionId ~= nil or presentation.acknowledgmentRequired == true)
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

local function BridgeRevealPruneDismissedKeys()
    local order = BridgeState.dismissedRevealOrder or {}
    while #order > 64 do
        local stale = order[1]
        for shift = 1, #order - 1 do order[shift] = order[shift + 1] end
        order[#order] = nil
        BridgeState.dismissedRevealKeys[stale] = nil
    end
    BridgeState.dismissedRevealOrder = order
end

local function BridgeRevealRetire(key, rememberDismissal)
    if key == nil then return end
    BridgeState.revealedPresentationsByKey[key] = nil
    BridgeRevealRemoveOrderKey(key)
    if BridgeState.activeRevealPresentationKey == key then BridgeState.activeRevealPresentationKey = nil end
    if rememberDismissal then
        if BridgeState.dismissedRevealKeys[key] ~= true then
            BridgeState.dismissedRevealKeys[key] = true
            BridgeState.dismissedRevealOrder = BridgeState.dismissedRevealOrder or {}
            table.insert(BridgeState.dismissedRevealOrder, key)
            BridgeRevealPruneDismissedKeys()
        end
    end
end

function BridgeHudRevealInteract(player, value, id)
    local key = BridgeState.activeRevealPresentationKey
    local presentation = key and BridgeState.revealedPresentationsByKey[key] or nil
    if presentation == nil then return false end
    presentation.pinnedByUser = true
    BridgeRevealUiDirty("reveal-pinned")
    return true
end

local function BridgeScheduleRevealAutoDismiss(key, presentation)
    if BridgeRevealIsDecisionBound(presentation) then return end
    BridgeState.revealPresentationGeneration = (BridgeState.revealPresentationGeneration or 0) + 1
    local token = BridgeState.revealPresentationGeneration
    presentation.revealPresentationToken = token
    presentation.openedAt = Time and Time.time or nil
    presentation.autoDismissDeadline = (presentation.openedAt or 0) + BRIDGE_REVEAL_AUTO_DISMISS_SECONDS
    local sessionId, sessionGeneration = BridgeState.eventSessionId, BridgeState.eventSessionGeneration
    local schedule = BridgeWaitTime or function(callback, delay) Wait.time(callback, delay) end
    schedule(function()
        local active = BridgeState.activeRevealPresentationKey
        local current = active and BridgeState.revealedPresentationsByKey[active] or nil
        if active ~= key or current ~= presentation or current.revealPresentationToken ~= token
            or current.pinnedByUser == true
            or BridgeState.eventSessionId ~= sessionId
            or BridgeState.eventSessionGeneration ~= sessionGeneration then return end
        BridgeRevealRetire(key, true)
        BridgeRevealUiDirty("reveal-auto-dismissed")
    end, BRIDGE_REVEAL_AUTO_DISMISS_SECONDS)
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
        if ok and image ~= nil and tostring(image) ~= "" then return tostring(image), "canonical" end
    end
    if entry.imageUrl ~= nil and tostring(entry.imageUrl) ~= "" then
        return tostring(entry.imageUrl), "producer-url"
    end
    if entry.image ~= nil and tostring(entry.image) ~= "" then
        return tostring(entry.image), "physical-custom-face"
    end
    return nil, "fallback-text"
end

function BridgeApplyRevealPresentation(presentation, appliedEventSequence)
    if presentation == nil or not BridgeRevealViewerMaySee(presentation) then return false end
    local sequence = tonumber(appliedEventSequence or presentation.originatingEventSequence or 0) or 0
    if sequence > (tonumber(BridgeState.lastAppliedEventSequence or 0) or 0) then return false end
    local key = BridgeRevealKey(presentation, sequence)
    if BridgeState.dismissedRevealKeys[key] == true then return false end
    local lifecycle = string.lower(tostring(presentation.lifecycle or "opened"))
    if lifecycle == "resolved" or lifecycle == "dismissed" then
        BridgeRevealRetire(key, true)
        BridgeRevealUiDirty("reveal-closed")
        return true
    end
    local priorKey = BridgeState.activeRevealPresentationKey
    if priorKey ~= nil and priorKey ~= key then BridgeRevealRetire(priorKey, true) end
    if BridgeState.revealedPresentationsByKey[key] == nil then table.insert(BridgeState.revealedPresentationOrder, key) end
    BridgeState.revealedPresentationsByKey[key] = presentation
    BridgeState.activeRevealPresentationKey = key
    BridgeState.revealSurfaceOffset = 1
    if presentation.revealPresentationToken == nil then BridgeScheduleRevealAutoDismiss(key, presentation) end
    BridgeRevealUiDirty("reveal-updated")
    return true
end

function BridgeResolveRevealForDecision(decision)
    local key = BridgeState.activeRevealPresentationKey
    local presentation = key and BridgeState.revealedPresentationsByKey[key] or nil
    if presentation == nil or presentation.associatedDecisionId == nil then return end
    if decision == nil or decision.decisionId ~= presentation.associatedDecisionId then
        BridgeRevealRetire(key, true)
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
    BridgeHudRevealInteract(player, value, id)
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
    BridgeHudRevealInteract(player, value, id)
    if BridgeRevealIsDecisionBound(presentation) then return end
    BridgeRevealRetire(key, true)
    BridgeRevealUiDirty("reveal-dismissed")
end

-- Card buttons deliberately do not infer Scry/Surveil semantics. Future
-- decision code may install BridgeRevealCardInteractionHandler and receive the
-- exact Forge identity carried by this structured presentation.
function BridgeHudRevealCard(player, value, id)
    if not BridgeHudRevealInteract(player, value, id) then return end
    local slot = tonumber(string.match(tostring(id or ""), "(%d+)$"))
    local presentation = BridgeState.revealedPresentationsByKey[BridgeState.activeRevealPresentationKey]
    local entry = slot and presentation and (presentation.cards or {})[(BridgeState.revealSurfaceOffset or 1) + slot - 1] or nil
    if entry ~= nil and BridgeRevealCardInteractionHandler ~= nil then
        BridgeRevealCardInteractionHandler(presentation, entry, player)
    end
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
    local artSources = {}
    for slot = 1, BRIDGE_REVEAL_SURFACE_SLOTS do
        local entry = cards[offset + slot - 1]
        local image, source
        if entry ~= nil then
            image, source = BridgeRevealCardArt(entry)
        end
        BridgeUiSet("BridgeHudRevealCard" .. tostring(slot), "active", entry ~= nil and "true" or "false")
        BridgeUiSet("BridgeHudRevealImage" .. tostring(slot), "active", image ~= nil and "true" or "false")
        BridgeUiSet("BridgeHudRevealImage" .. tostring(slot), "image", image or "")
        BridgeUiSet("BridgeHudRevealFallback" .. tostring(slot), "active", entry ~= nil and image == nil and "true" or "false")
        BridgeUiSet("BridgeHudRevealFallback" .. tostring(slot), "text", entry and tostring(entry.cardName or "Revealed card") or "")
        BridgeUiSet("BridgeHudRevealCard" .. tostring(slot), "tooltip", entry and tostring(entry.cardName or "Revealed card") or "")
        BridgeUiSet("BridgeHudRevealCardButton" .. tostring(slot), "active", entry ~= nil and "true" or "false")
        if entry ~= nil and source then
            if artSources[source] == nil then artSources[source] = 0 end
            artSources[source] = artSources[source] + 1
        end
    end
    BridgeUiSet("BridgeHudRevealPrev", "active", offset > 1 and "true" or "false")
    BridgeUiSet("BridgeHudRevealNext", "active", endIndex < #cards and "true" or "false")
    BridgeUiSet("BridgeHudRevealCount", "text", #cards > BRIDGE_REVEAL_SURFACE_SLOTS
        and (tostring(offset) .. "-" .. tostring(endIndex) .. " / " .. tostring(#cards)) or "")
    BridgeUiSet("BridgeHudRevealClose", "active", not BridgeRevealIsDecisionBound(presentation) and "true" or "false")
    BridgeUiSet("BridgeHudRevealClose", "text", presentation.acknowledgmentRequired == true and "ACKNOWLEDGE" or "CLOSE")
    
    -- Display art resolution diagnostics
    local artSourceStr = ""
    for _, source in ipairs({"canonical", "producer-url", "physical-custom-face", "fallback-text"}) do
        if artSources[source] and artSources[source] > 0 then
            if artSourceStr ~= "" then artSourceStr = artSourceStr .. " | " end
            artSourceStr = artSourceStr .. source .. ":" .. tostring(artSources[source])
        end
    end
    BridgeUiSet("BridgeHudRevealArtSource", "text", artSourceStr)
end
