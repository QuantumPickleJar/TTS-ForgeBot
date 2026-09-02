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
