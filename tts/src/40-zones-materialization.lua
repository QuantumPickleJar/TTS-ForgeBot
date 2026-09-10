            if not materialized then callback(BridgeMakeEmbodimentResult("FAILED", nil, materializeError, nil)); return end
            -- Materialization removes snapshot hand/public cards first. The
            -- remaining native Deck is then bound to Forge library instances
            -- by exact contained GUID without destructive reordering.
            if BridgeRecordBootstrapStage ~= nil then
                BridgeRecordBootstrapStage(stagePrefix .. "-materialization",
                    materialized and "OBSERVED" or "FAILED", materializeError)
            end
            BridgeWaitFrames(function()
                BridgeApplySeatSnapshotVisualState(seatSnapshot)
                if markPhysicalReady == true and BridgeState.resyncInFlight == true
                    and BridgeState.resyncCandidateSnapshot ~= nil
                    and BridgeMarkResyncPhysicalRebuildReady ~= nil then
                    BridgeMarkResyncPhysicalRebuildReady(BridgeState.resyncCandidateSnapshot)
                end
                callback(BridgeMakeEmbodimentResult("SUCCESS", nil, nil, {status = "SUCCESS"}))
            end, 30)
        end)
        end)
        end)
        end)
        end)
    end)
end

local function BridgeSourceCardSort(left, right)
    local leftZone = tostring(left.zone or "")
    local rightZone = tostring(right.zone or "")
    if leftZone ~= rightZone then return leftZone < rightZone end
    local leftPosition = tonumber(left.zonePosition or left.index or 0) or 0
    local rightPosition = tonumber(right.zonePosition or right.index or 0) or 0
    if leftPosition ~= rightPosition then return leftPosition < rightPosition end
    return tostring(left.cardInstanceId or left.guid or "") < tostring(right.cardInstanceId or right.guid or "")
end

local function BridgeSourceEntrySort(left, right)
    local leftIndex = tonumber(left.index or 0) or 0
    local rightIndex = tonumber(right.index or 0) or 0
    if leftIndex ~= rightIndex then return leftIndex < rightIndex end
    return tostring(left.guid or "") < tostring(right.guid or "")
end

-- Build a complete seat-local source assignment before touching any committed
-- physical ledger.  This is intentionally broader than the final library
-- binder: a 40-card Deck is a valid source inventory for a 33-card library
-- plus a seven-card opening hand.
function BridgeBuildSeatSourceAssignment(seatSnapshot, assets)
    local seatId = seatSnapshot.seatId
    BridgeState.physicalContainerByInstanceId = BridgeState.physicalContainerByInstanceId or {}
    BridgeState.physicalZoneByGuid = BridgeState.physicalZoneByGuid or {}
    BridgeState.physicalInstanceIdByGuid = BridgeState.physicalInstanceIdByGuid or {}
    local deck = BridgeResolveSeatLibraryDeck(seatId)
    if deck == nil then return nil, "source assignment cannot resolve seat library" end
    local entries = {}
    if deck.tag == "Card" then
        entries = {{guid = BridgeSafeObjectGuid(deck), nickname = BridgePhysicalCanonicalCardName(deck), index = 1}}
    else
        local ok, native = pcall(function() return deck.getObjects() or {} end)
        if not ok then return nil, "source assignment cannot inspect seat library" end
        entries = native
    end
    table.sort(entries, BridgeSourceEntrySort)
    local sources = {}
    local sourceByGuid = {}
    for _, entry in ipairs(entries) do
        local rawGuid = entry and (entry.guid or entry.GUID) or nil
        local guid = rawGuid ~= nil and tostring(rawGuid) or ""
        local item = {
            sourceZone = "library", deck = deck, deckGuid = BridgeSafeObjectGuid(deck),
            guid = string.match(guid, "%S") ~= nil and guid or nil,
            index = tonumber(entry and entry.index or -1) or -1,
            cardName = entry and (entry.nickname or entry.name or "") or "",
            normalizedName = BridgeNormalizeCardName(entry and (entry.nickname or entry.name or "") or ""),
            locatorType = string.match(guid, "%S") ~= nil and "GUID_LOCATOR" or "SLOT_LOCATOR"
        }
        table.insert(sources, item)
        if item.guid ~= nil then sourceByGuid[item.guid] = item end
    end
    local handObjects = BridgeTryGetSeatHandObjects(seatId) or {}
    local handSeen = {}
    for _, object in ipairs(handObjects) do
        local guid = BridgeSafeObjectGuid(object)
        if guid ~= nil and not handSeen[guid] then
            handSeen[guid] = true
            table.insert(sources, {
                sourceZone = "hand", object = object, guid = guid,
                cardName = BridgePhysicalCanonicalCardName(object),
                normalizedName = BridgeNormalizeCardName(BridgePhysicalCanonicalCardName(object)),
                instanceId = BridgeReadCurrentSessionPhysicalIdentity(object) or BridgeState.physicalInstanceIdByGuid[guid]
            })
        end
    end
    local knownSourceGuid = {}
    for _, source in ipairs(sources) do if source.guid ~= nil then knownSourceGuid[source.guid] = true end end
    for _, asset in ipairs(assets or {}) do
        local guid = asset.guid or (asset.object and BridgeSafeObjectGuid(asset.object))
        if guid ~= nil and not knownSourceGuid[guid] then
            local object = asset.object
            local assetSeat, assetZone = BridgeObserveObjectPhysicalZone(object, seatId)
            if assetSeat == nil or tostring(assetSeat) == tostring(seatId) then
                local zone = assetZone or BridgeState.physicalZoneByGuid[guid] or "public"
                table.insert(sources, {
                    sourceZone = zone, object = object, guid = guid,
                    cardName = asset.cardName or BridgePhysicalCanonicalCardName(object),
                    normalizedName = BridgeNormalizeCardName(asset.cardName or BridgePhysicalCanonicalCardName(object)),
                    instanceId = BridgeReadCurrentSessionPhysicalIdentity(object) or BridgeState.physicalInstanceIdByGuid[guid]
                })
                knownSourceGuid[guid] = true
            end
        end
    end

    local desired = {}
    for _, zone in ipairs(seatSnapshot.zones or {}) do
        for _, card in ipairs(zone.cards or {}) do
            if card.isVirtual ~= true and tostring(card.materializationPolicy or "") ~= "virtual" then
                local cardInstanceId = card.cardInstanceId or card.instanceId
                local cardName = card.cardName or card.currentCardName or card.name or card.Name
                if cardInstanceId == nil or tostring(cardInstanceId) == "" then
                    return nil, "source assignment missing Forge CardInstanceId"
                end
                if cardName == nil or BridgeNormalizeCardName(cardName) == "" then
                    return nil, "source assignment missing canonical card name for " .. tostring(cardInstanceId)
                end
                table.insert(desired, {
                    card = card, cardInstanceId = tostring(cardInstanceId), cardName = tostring(cardName), zone = zone.name,
                    zonePosition = card.zonePosition, normalizedName = BridgeNormalizeCardName(cardName)
                })
            end
        end
    end
    table.sort(desired, BridgeSourceCardSort)
    local byName = {}
    for _, source in ipairs(sources) do
        byName[source.normalizedName] = byName[source.normalizedName] or {}
        table.insert(byName[source.normalizedName], source)
    end
    for _, list in pairs(byName) do table.sort(list, BridgeSourceEntrySort) end

    local assignments, used = {}, {}
    local function takeCandidate(desiredCard, preferZone)
        local list = byName[desiredCard.normalizedName] or {}
        for _, source in ipairs(list) do
            if not used[source] and (preferZone == nil or source.sourceZone == preferZone) then
                used[source] = true; return source
            end
        end
        for _, source in ipairs(list) do
            if not used[source] then used[source] = true; return source end
        end
        return nil
    end
    -- Preserve exact advertised hand identities first.
    for _, desiredCard in ipairs(desired) do
        local exact = nil
        for _, source in ipairs(sources) do
            if not used[source] and source.instanceId ~= nil
                and tostring(source.instanceId) == tostring(desiredCard.cardInstanceId) then exact = source; break end
        end
        if exact == nil then
            local committed = BridgeState.physicalContainerByInstanceId[desiredCard.cardInstanceId]
            local committedGuid = committed and committed.cardGuid or nil
            local committedSlot = committed and committed.slotIndex or nil
            for _, source in ipairs(sources) do
                if not used[source] and source.sourceZone == "library"
                    and ((committedGuid ~= nil and tostring(source.guid or "") == tostring(committedGuid))
                        or (committedGuid == nil and committedSlot ~= nil and tonumber(source.index) == tonumber(committedSlot))) then
                    exact = source; break
                end
            end
        end
        if exact ~= nil then used[exact] = true end
        assignments[desiredCard.cardInstanceId] = {desired = desiredCard, source = exact}
    end
    for _, desiredCard in ipairs(desired) do
        local assignment = assignments[desiredCard.cardInstanceId]
        if assignment.source == nil then
            assignment.source = takeCandidate(desiredCard, desiredCard.zone)
        end
        if assignment.source == nil then
            return nil, "source assignment missing physical card " .. tostring(desiredCard.cardName)
        end
    end
    local moves = {}
    for _, assignment in pairs(assignments) do
        local source = assignment.source
        if source.sourceZone ~= assignment.desired.zone then table.insert(moves, assignment) end
    end
    table.sort(moves, function(left, right)
        return tostring(left.desired.cardInstanceId) < tostring(right.desired.cardInstanceId)
    end)
    local sourceAssignments = {}
    for _, assignment in pairs(assignments) do table.insert(sourceAssignments, {
        cardInstanceId = assignment.desired.cardInstanceId,
        cardName = assignment.desired.cardName,
        desiredZone = assignment.desired.zone,
        sourceZone = assignment.source.sourceZone,
        locatorType = assignment.source.locatorType,
        deckGuid = assignment.source.deckGuid,
        containedGuid = assignment.source.guid,
        slotIndex = assignment.source.index,
        physicalGuid = assignment.source.guid
    }) end
    table.sort(sourceAssignments, function(left, right)
        return tostring(left.cardInstanceId) < tostring(right.cardInstanceId)
    end)
    if #sources ~= #desired then
        return nil, string.format("seat physical inventory count mismatch: observed=%d desired=%d", #sources, #desired)
    end
    return {
        seatId = seatId, deck = deck, assignments = assignments, sourceAssignments = sourceAssignments, moves = moves,
        observedTotalInventory = #sources, desiredTotalInventory = #desired,
        observedLibraryCount = #entries, observedHandCount = #handObjects,
        desiredLibraryCount = 0, desiredHandCount = 0,
        plannedLibraryToHand = 0, plannedHandToLibrary = 0,
        completedMoves = 0,
        alreadyCorrectZoneCount = #desired - #moves
    }, nil
end

function BridgeTakeSeatSourceCard(source, expectedName, position, callback)
    if source == nil or source.deck == nil then callback(nil, "missing source locator"); return end
    local deck = source.deck
    local entries = {}
    local ok = pcall(function() entries = deck.getObjects() or {} end)
    if not ok then callback(nil, "source Deck could not be reobserved"); return end
    local selected = nil
    for _, entry in ipairs(entries) do
        local entryName = BridgeNormalizeCardName(entry.nickname or entry.name or "")
        local entryGuid = entry.guid or entry.GUID
        if entryName == BridgeNormalizeCardName(expectedName)
            and (source.guid == nil or tostring(source.guid) == tostring(entryGuid)) then
            if source.guid ~= nil or tonumber(entry.index or -1) == tonumber(source.index or -1) then selected = entry; break end
            if selected == nil then selected = entry end
        end
    end
    if selected == nil then callback(nil, "source locator no longer uniquely resolves expected card"); return end
    local takeArgs = {position = position, smooth = false,
        guid = (selected.guid ~= nil and string.match(tostring(selected.guid), "%S") ~= nil) and tostring(selected.guid) or nil,
        index = (selected.guid == nil or string.match(tostring(selected.guid or ""), "%S") == nil) and selected.index or nil}
    local finished = false
    local function finish(object, errorMessage)
        if finished then return end; finished = true; callback(object, errorMessage)
    end
    local takeOk, takeError = pcall(function()
        deck.takeObject({guid = takeArgs.guid, index = takeArgs.index, position = position,
            smooth = false, callback_function = function(taken)
                if not BridgeObjectIsUsable(taken) then finish(nil, "source extraction returned unusable Card"); return end
                if BridgeNormalizeCardName(BridgePhysicalCanonicalCardName(taken)) ~= BridgeNormalizeCardName(expectedName) then
                    finish(nil, "source extraction returned wrong card identity"); return
                end
                finish(taken, nil)
            end})
    end)
    if not takeOk then finish(nil, "source extraction failed: " .. tostring(takeError)) end
end

function BridgeApplySeatSourceAssignment(plan, seatSnapshot, moveIndex, callback)
    moveIndex = moveIndex or 1
    if moveIndex > #(plan.moves or {}) then callback(BridgeMakeEmbodimentResult("SUCCESS", nil, nil, plan)); return end
    local move = plan.moves[moveIndex]
    local destination = move.desired.zone
    local source = move.source
    local function nextMove()
        plan.completedMoves = (plan.completedMoves or 0) + 1
        -- A Deck mutation invalidates every native slot observed before it.
        -- Retain the logical desired assignment, but rebuild its ephemeral
        -- physical locators before issuing another native mutation.
        BridgeWaitFrames(function()
            local refreshed, refreshError = BridgeBuildSeatSourceAssignment(seatSnapshot, plan.assets or {})
            if refreshed == nil then callback(BridgeMakeEmbodimentResult("FAILED", nil, refreshError, nil)); return end
            refreshed.assets = plan.assets
            refreshed.completedMoves = plan.completedMoves
            BridgeApplySeatSourceAssignment(refreshed, seatSnapshot, 1, callback)
        end, 1)
    end
    if source.sourceZone == "library" and destination == "hand" then
        local hand, handError = BridgeTryGetSeatHandTransform(seatSnapshot.seatId)
        if hand == nil then callback(BridgeMakeEmbodimentResult("FAILED", nil, handError, nil)); return end
        BridgeTakeSeatSourceCard(source, move.desired.cardName, hand.position, function(taken, errorMessage)
            if taken == nil then callback(BridgeMakeEmbodimentResult("FAILED", nil, errorMessage, nil)); return end
            -- The extracted loose Card receives the exact Forge identity that
            -- drove this source move.  The committed bridge ledger is still
            -- published only by the final atomic hand binder.
            BridgeWritePhysicalIdentity(taken, move.desired.cardInstanceId)
            BridgeWritePhysicalSessionIdentity(taken, BridgeState.eventSessionId)
            pcall(function() taken.use_hands = true; taken.setPosition(hand.position) end)
            BridgeWaitFrames(nextMove, 2)
        end)
    elseif source.sourceZone == "hand" and destination == "library" then
        local deck = plan.deck
        local putOk, putError = pcall(function() deck.putObject(source.object, 0) end)
        if not putOk then callback(BridgeMakeEmbodimentResult("FAILED", nil, "hand-to-library move failed: " .. tostring(putError), nil)); return end
        BridgeWaitFrames(nextMove, 2)
    else
        nextMove()
    end
end

-- Keep the execution plan transaction-local.  This projection is deliberately
-- boring: it is durable diagnostic state and must remain JSON-safe even when
-- a source locator contains live Deck/Card userdata.
function BridgeSeatReconciliationDiagnostic(plan)
    local result = {
        seatId = plan and plan.seatId or nil,
        observedTotalInventory = plan and plan.observedTotalInventory or 0,
        desiredTotalInventory = plan and plan.desiredTotalInventory or 0,
        observedLibraryCount = plan and plan.observedLibraryCount or 0,
        observedHandCount = plan and plan.observedHandCount or 0,
        desiredLibraryCount = plan and plan.desiredLibraryCount or 0,
        desiredHandCount = plan and plan.desiredHandCount or 0,
        sourceAssignmentCount = plan and #(plan.sourceAssignments or {}) or 0,
        alreadyCorrectZoneCount = plan and plan.alreadyCorrectZoneCount or 0,
        plannedLibraryToHand = plan and plan.plannedLibraryToHand or 0,
        plannedHandToLibrary = plan and plan.plannedHandToLibrary or 0,
        completedMoves = plan and plan.completedMoves or 0,
        finalLibraryBindings = plan and plan.finalLibraryBindings or 0,
        finalHandBindings = plan and plan.finalHandBindings or 0,
        sourceAssignments = {}
    }
    for index, assignment in ipairs(plan and plan.sourceAssignments or {}) do
        if index > 32 then break end
        table.insert(result.sourceAssignments, {
            cardInstanceId = assignment.cardInstanceId,
            desiredZone = assignment.desiredZone,
            sourceZone = assignment.sourceZone,
            locatorType = assignment.locatorType,
            deckGuid = assignment.deckGuid,
            containedGuid = assignment.containedGuid,
            slotIndex = assignment.slotIndex,
            physicalGuid = assignment.physicalGuid
        })
    end
    return result
end

function BridgePrepareSeatSourceAssignment(seatSnapshot, assets, callback)
    local plan, planError = BridgeBuildSeatSourceAssignment(seatSnapshot, assets)
    if plan == nil then callback(BridgeMakeEmbodimentResult("FAILED", nil, planError, nil)); return end
    plan.assets = assets
    for _, zone in ipairs(seatSnapshot.zones or {}) do
        if zone.name == "library" then plan.desiredLibraryCount = #(zone.cards or {}) end
        if zone.name == "hand" then plan.desiredHandCount = #(zone.cards or {}) end
    end
    for _, move in ipairs(plan.moves) do
        if move.source.sourceZone == "library" and move.desired.zone == "hand" then plan.plannedLibraryToHand = plan.plannedLibraryToHand + 1 end
        if move.source.sourceZone == "hand" and move.desired.zone == "library" then plan.plannedHandToLibrary = plan.plannedHandToLibrary + 1 end
    end
    BridgeState.seatReconciliationDiagnosticsBySeatId = BridgeState.seatReconciliationDiagnosticsBySeatId or {}
    BridgeState.seatReconciliationDiagnosticsBySeatId[seatSnapshot.seatId] = BridgeSeatReconciliationDiagnostic(plan)
    BridgeApplySeatSourceAssignment(plan, seatSnapshot, 1, callback)
end

function BridgeCollectSeatAssets(seatId, seatSnapshot, callback)
    local seat = BRIDGE_SEATS[seatId]
    local assets = {}
    local assetByGuid = {}
    local graveyardReady, graveyardError = BridgeEnsureNativeGraveyardContainer(seatId)
    if not graveyardReady then
        callback(false, nil, graveyardError)
        return
    end
    -- Reuse one TTS object snapshot for both library discovery and candidate
    -- collection.  TTS getAllObjects() is a native boundary and can take
    -- hundreds of milliseconds in a large table; scanning it twice during
    -- bootstrap needlessly amplifies a freeze already visible in diagnostics.
    local objectSnapshot = _all()
    -- Resolve the library once. BridgeResolveSeatLibraryDeck scans the TTS
    -- object list; doing that for every candidate made bootstrap O(n^2) and
    -- was the measured multi-second freeze hot path.
    local library = BridgeResolveSeatLibraryDeck(seatId, objectSnapshot)
    local libraryGuid = BridgeSafeObjectGuid(library)
    local context = {
        expectedCardNamesBySeat = {},
        handGuidsBySeat = {}
    }
    context.expectedCardNamesBySeat[seatId] = BridgeExpectedCardNamesForSeatSnapshot(seatSnapshot)
    context.handGuidsBySeat[seatId] = BridgeBuildSeatHandGuidSet(seatId)
    BridgeTraceStart("START-14 library-indexing", tostring(seatId))

    local function addAsset(object)
        if not BridgeObjectIsUsable(object) or object.tag ~= "Card" then return end
        if libraryGuid ~= nil and libraryGuid == BridgeSafeObjectGuid(object) then return end
        if not IsGameCardCandidate(object, seatId, context) then return end
        local guid = BridgeSafeObjectGuid(object)
        local cardName = BridgePhysicalCanonicalCardName(object)
        if guid == nil or assetByGuid[guid] then return end
        assetByGuid[guid] = true
        table.insert(assets, {
            guid = guid,
            cardName = cardName,
            object = object
        })
    end

    -- TTS hand objects are not guaranteed to be present in getAllObjects().
    -- Index them explicitly so preserving hands does not make the inventory
    -- audit under-count the authoritative card set.
    local handObjects, handError = BridgeTryGetSeatHandObjects(seatId)
    if handObjects == nil then
        callback(false, nil, handError)
        return
    end
    for _, object in ipairs(handObjects) do addAsset(object) end

    for _, object in ipairs(objectSnapshot) do
        addAsset(object)
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
    local seenContainedGuid = {}
    for _, contained in ipairs(containedCards) do
        local rawGuid = contained and (contained.guid or contained.GUID) or nil
        local normalizedGuid = rawGuid ~= nil and tostring(rawGuid) or ""
        local hasUsableGuid = string.match(normalizedGuid, "%S") ~= nil
        if hasUsableGuid and seenContainedGuid[normalizedGuid] then
            return nil, "library ledger found duplicate real contained GUID " .. normalizedGuid
        end
        if hasUsableGuid then
            seenContainedGuid[normalizedGuid] = true
        end
        if contained ~= nil then
            local containedName = contained.nickname or contained.name or ""
            local normalizedName = BridgeNormalizeCardName(containedName)
            local entry = {
                guid = hasUsableGuid and normalizedGuid or nil,
                deckGuid = deckGuid,
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

function BridgeBuildSeatGraveyardLedger(seatId)
    local ledger = {byName = {}, countByName = {}, byGuid = {}}
    local container = BridgeFindGraveyardContainer(seatId)
    if container == nil then return ledger, nil end
    local deckGuid = BridgeSafeObjectGuid(container)
    local entries = {}
    if container.tag == "Deck" then
        local ok = pcall(function() entries = container.getObjects() or {} end)
        if not ok then return nil, "graveyard ledger could not inspect native Deck" end
    else
        entries = {{guid = BridgeSafeObjectGuid(container), nickname = BridgePhysicalCanonicalCardName(container), index = 1}}
    end
    for _, entry in ipairs(entries) do
        local guid = entry and (entry.guid or entry.GUID) or nil
        if guid ~= nil then
            local name = entry.nickname or entry.name or ""
            local normalized = BridgeNormalizeCardName(name)
            local item = {
                guid = guid,
                deckGuid = container.tag == "Deck" and deckGuid or nil,
                cardName = name,
                normalizedName = normalized,
                index = tonumber(entry.index or -1) or -1,
                instanceId = BridgeState.physicalContainedInstanceIdByGuid[guid]
                    or BridgeState.physicalInstanceIdByGuid[guid]
            }
            ledger.byName[normalized] = ledger.byName[normalized] or {}
            table.insert(ledger.byName[normalized], item)
            ledger.countByName[normalized] = (ledger.countByName[normalized] or 0) + 1
            ledger.byGuid[guid] = item
        end
    end
    return ledger, nil
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
    local handByName = {}
    local nonHandByName = {}
    local looseCountByName = {}
    local assetByGuid = {}
    local mappings = {}
    local handGuids = BridgeBuildSeatHandGuidSet(seatSnapshot.seatId)
    for _, asset in ipairs(assets) do
        local name = BridgeNormalizeCardName(asset.cardName)
        local assetGuid = asset.guid or (asset.object and BridgeSafeObjectGuid(asset.object))
        local destination = handGuids[assetGuid] == true and handByName or nonHandByName
        destination[name] = destination[name] or {}
        table.insert(destination[name], asset)
        if assetGuid ~= nil then assetByGuid[tostring(assetGuid)] = asset end
        looseCountByName[name] = (looseCountByName[name] or 0) + 1
    end

    local ledger, ledgerError = BridgeBuildSeatLibraryLedger(seatSnapshot)
    if ledger == nil then
        return false, ledgerError
    end
    local graveyardLedger, graveyardLedgerError = BridgeBuildSeatGraveyardLedger(seatSnapshot.seatId)
    if graveyardLedger == nil then return false, graveyardLedgerError end

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
        local containedCount = (ledger.countByName[normalizedName] or 0)
            + (graveyardLedger.countByName[normalizedName] or 0)
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
            local containedCandidates = (zoneName == "graveyard"
                and graveyardLedger.byName[normalized] or ledger.byName[normalized]) or {}
            while #containedCandidates > 0 and containedCandidates[1].assigned == true do
                table.remove(containedCandidates, 1)
            end
            if #containedCandidates > 0 then
                local contained = table.remove(containedCandidates, 1)
                contained.assigned = true
                assigned = {
                    cardName = contained.cardName,
                    object = nil,
                    guid = contained.guid,
                    deckGuid = contained.deckGuid,
                    slotIndex = contained.index,
                    contained = zoneName == "graveyard" or contained.deckGuid ~= nil
                }
                assignedContainedByName[normalized] = (assignedContainedByName[normalized] or 0) + 1
            end
        end
        local function consumeLoose()
            -- TTS can expose hand cards in a different order from getAllObjects.
            -- Reserve those exact hand members for the authoritative hand zone;
            -- otherwise duplicate names can cross-link a hand card with a
            -- battlefield card and opening-hand readiness will correctly reject
            -- the resulting mapping.
            local looseCandidates = zoneName == "hand"
                and (handByName[normalized] or {})
                or (nonHandByName[normalized] or {})
            while #looseCandidates > 0 and looseCandidates[1].assigned == true do
                table.remove(looseCandidates, 1)
            end
            if #looseCandidates > 0 then
                assigned = table.remove(looseCandidates, 1)
                assigned.assigned = true
            end
        end

        -- Same-session resync preserves live public mappings. Prefer that exact
        -- GUID before any duplicate-name fallback so a played land or already
        -- milled card can never be replaced by another copy from the library.
        local preservedGuid = BridgeState.physicalByInstanceId[card.cardInstanceId]
        local preservedAsset = preservedGuid and assetByGuid[tostring(preservedGuid)] or nil
        -- A failed asynchronous move can retire the forward index before the
        -- reverse index is rebuilt. Recover the exact live asset by identity;
        -- never fall through to duplicate-name matching in that case.
        if preservedAsset == nil then
            for guid, mappedInstanceId in pairs(BridgeState.physicalInstanceIdByGuid or {}) do
                if mappedInstanceId == card.cardInstanceId then
                    local reverseAsset = assetByGuid[tostring(guid)]
                    if reverseAsset ~= nil then
                        preservedGuid = guid
                        preservedAsset = reverseAsset
                        break
                    end
                end
            end
        end
        local preservedContainer = BridgeState.physicalContainerByInstanceId[card.cardInstanceId]
        local preservedContained = preservedContainer ~= nil and zoneName == "graveyard"
        if preservedContained then
            local preservedEntry = graveyardLedger.byGuid[preservedContainer.cardGuid]
            if preservedEntry ~= nil and preservedEntry.cardName ~= nil
                and BridgeCardNameMatches(preservedEntry.cardName, card.cardName) then
                assigned = {
                    cardName = preservedEntry.cardName,
                    object = nil,
                    guid = preservedEntry.guid,
                    deckGuid = preservedEntry.deckGuid,
                    contained = true
                }
                preservedEntry.assigned = true
                assignedContainedByName[normalized] = (assignedContainedByName[normalized] or 0) + 1
            end
        end
        if assigned == nil and preservedAsset ~= nil and preservedAsset.assigned ~= true then
            assigned = preservedAsset
            preservedAsset.assigned = true
        elseif zoneName == "library" then
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
    local priorLedger = BridgeCapturePhysicalLedger()
    local priorNames = BridgeDiagnosticSnapshot(BridgeState.cardNameByInstanceId or {})
    for _, mapping in ipairs(mappings) do
        if mapping.zoneName == "library" and mapping.asset.contained == true
            and mapping.asset.guid == nil and (tonumber(mapping.asset.slotIndex or -1) or -1) < 0 then
            if BridgeEmbodimentRecordBlockingObservation ~= nil then
                BridgeEmbodimentRecordBlockingObservation(BridgeState.embodimentTransaction,
                    "library contained identity unsettled for seat=" .. tostring(seatSnapshot.seatId))
            end
            return false, "library contained identity unsettled", {status = "WAITING_FOR_PHYSICAL_SETTLEMENT"}
        end
    end
    for _, mapping in ipairs(mappings) do
        BridgeState.cardNameByInstanceId[mapping.card.cardInstanceId] = mapping.card.cardName
        if mapping.zoneName == "library" then
            -- Library identity was atomically committed by the orderless
            -- binder before this legacy adapter ran.
        else
        local guid = mapping.asset.guid
        if mapping.asset.contained == true and mapping.asset.deckGuid ~= nil then
            local mapped = false
            if mapping.asset.guid ~= nil then
                mapped = BridgeRecordContainedCardIdentity(mapping.card.cardInstanceId, mapping.asset.deckGuid,
                    mapping.asset.guid, seatSnapshot.seatId, mapping.zoneName, mapping.card.cardName)
            elseif mapping.zoneName == "library" and tonumber(mapping.asset.slotIndex or -1) >= 0 then
                mapped = BridgeRecordSlotLibraryIdentity(mapping.card.cardInstanceId, mapping.asset.deckGuid,
                    mapping.asset.slotIndex, seatSnapshot.seatId, mapping.zoneName, mapping.card.cardName,
                    (BridgeState.libraryBindingGenerationBySeatId[seatSnapshot.seatId] or 0) + 1)
            end
            if not mapped then
                BridgeActivatePhysicalLedger(priorLedger)
                BridgeState.cardNameByInstanceId = priorNames
                return false, "library contained identity could not be published", {status = "FAILED"}
            end
        elseif mapping.zoneName == "library" or guid == nil then
            BridgeRecordLibraryContainedState(mapping.card.cardInstanceId, seatSnapshot.seatId,
                mapping.card.cardName, ledger.deck, mapping.asset.guid)
        else
            BridgeRecordLooseCardIdentity(mapping.card.cardInstanceId, guid, seatSnapshot.seatId, mapping.zoneName)
            if mapping.asset.object ~= nil then
                BridgeState.untappedRotationByGuid[guid] = mapping.asset.object.getRotation()
            end
        end
        end
    end
    BridgeTraceStart("START-17 mapping-complete", tostring(seatSnapshot.seatId))
    BridgeAdvancePhysicalPresentationGeneration("bootstrap-complete")
    return true, nil
end

function BridgeMaterializeSeatSnapshot(seatSnapshot, zoneIndex, cardIndex, callback)
    local zones = seatSnapshot.zones or {}
    if zoneIndex > #zones then
        local graveyardOk, graveyardError = BridgeEnsureNativeGraveyardContainer(seatSnapshot.seatId)
        if not graveyardOk then callback(false, graveyardError); return end
        callback(true, nil)
        return
    end
    local zone = zones[zoneIndex]
    local cards = zone.cards or {}

    if zone.name == "library" or cardIndex > #cards then
        BridgeMaterializeSeatSnapshot(seatSnapshot, zoneIndex + 1, 1, callback)
        return
    end

    local card = cards[cardIndex]
    -- Forge may expose transient copies (for example a copied spell on the
    -- stack) that are intentionally virtual. Keep their authoritative
    -- identity in bridge state, but never invent a physical deck card.
    if card.isVirtual == true or tostring(card.materializationPolicy or "") == "virtual"
        or tostring(card.materializationPolicy or "") == "virtual-stack" then
        BridgeState.authoritativeObjectByInstanceId[card.cardInstanceId] = {
            objectId = card.authoritativeObjectId or card.cardInstanceId,
            originObjectId = card.originObjectId,
            copySourceObjectId = card.copySourceObjectId,
            objectKind = card.objectKind,
            isCopy = card.isCopy == true,
            isVirtual = true,
            materializationPolicy = card.materializationPolicy
        }
        BridgeMaterializeSeatSnapshot(seatSnapshot, zoneIndex, cardIndex + 1, callback)
        return
    end
    if zone.name == "graveyard" and BridgeState.physicalContainerByInstanceId[card.cardInstanceId] ~= nil then
        local containedDeck, containedEntry = BridgeFindContainedCardEntry(card.cardInstanceId, "graveyard")
        if containedDeck ~= nil and containedEntry ~= nil
            and BridgeCardNameMatches(containedEntry.nickname or containedEntry.name, card.cardName) then
            BridgeState.cardNameByInstanceId[card.cardInstanceId] = card.cardName
            BridgeMaterializeSeatSnapshot(seatSnapshot, zoneIndex, cardIndex + 1, callback)
            return
        end
    end
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
        local recorded, recordError = BridgeRecordLooseCardIdentity(card.cardInstanceId, actualGuid, seatSnapshot.seatId, zone.name)
        if not recorded then
            callback(false, recordError or "snapshot physical identity registration failed")
            return
        end
        BridgeState.cardNameByInstanceId[card.cardInstanceId] = card.cardName
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

    -- A Forge copy of a permanent has no deck inventory entry. When Forge
    -- supplies the exact copied-permanent identity, clone that already-
    -- materialized physical presentation as a starting surface, then apply
    -- the copy's authoritative characteristics below. The creating effect
    -- (originObjectId) is provenance, not the clone source. The clone receives
    -- the copy's own CardInstanceId and never steals the source mapping.
    local copySourceObjectId = card.copySourceObjectId or card.originObjectId
    if card.isCopy == true and copySourceObjectId ~= nil then
        local originGuid = BridgeState.physicalByInstanceId[copySourceObjectId]
        local origin = originGuid and BridgeGetLiveObjectByGuid(originGuid) or nil
        if origin ~= nil and type(origin.clone) == "function" then
            local cloned = nil
            local ok = pcall(function()
                cloned = origin.clone({position = origin.getPosition(), rotation = origin.getRotation()})
            end)
            if ok and cloned ~= nil then
                continueWith(cloned)
                return
            end
        end
    end

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
    if BridgeState.resyncInFlight == true then
        -- Exact same-session public mappings have already been preferred and
        -- retained above. Any remaining deck extraction is therefore limited
        -- to an object that is genuinely still contained in the library; keep
        -- this diagnostic visible because a name-only fallback is only a
        -- recovery path, never an identity source.
        BridgeLog("[Bridge] resync materialization using contained-library fallback for unmapped public card")
    end
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
    BridgeApplySeatTrackers(seatSnapshot, true)
    -- All authoritative seat values are now in memory. Reconcile the row once
    -- so a snapshot never paints a half-old/half-new resource state.
    BridgeRefreshResourceRow(seatSnapshot.seatId)
    local battlefieldInstances = {}
    for _, zone in ipairs(seatSnapshot.zones or {}) do
        for _, card in ipairs(zone.cards or {}) do
            BridgeState.authoritativeObjectByInstanceId[card.cardInstanceId] = {
                objectId = card.authoritativeObjectId or card.cardInstanceId,
                originObjectId = card.originObjectId,
                copySourceObjectId = card.copySourceObjectId,
                objectKind = card.objectKind,
                isCopy = card.isCopy == true,
                isVirtual = card.isVirtual == true,
                materializationPolicy = card.materializationPolicy
            }
        end
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
                    BridgePresentationMetric("snapshotVisualCounters")
                    local countersApplied, counterError = BridgeSetCardCounters(object, card.counters)
                    if not countersApplied then BridgeLog("[Bridge] counter visual unsupported: " .. tostring(counterError)) end
                    local keywords = {}
                    for _, keyword in ipairs(card.keywords or {}) do
                        keywords[BridgeNormalizeKeywordName(keyword)] = true
                    end
                    BridgeState.keywordStateByInstanceId[card.cardInstanceId] = keywords
                    BridgePresentationMetric("snapshotVisualKeywords")
                    local keywordsApplied, keywordError = BridgeSetCardKeywords(object, card.keywords)
                    if not keywordsApplied then BridgeLog("[Bridge] keyword visual unsupported: " .. tostring(keywordError)) end
                    -- Encoder rebuilds performed by counters/keywords may
                    -- recreate the card UI.  Apply Unified P/T and ownership
                    -- last so a static characteristic update remains visible.
                    BridgePresentationMetric("snapshotVisualCharacteristics")
                    local presentationApplied, presentationError = BridgeApplyCardPresentationSnapshot(object, card)
                    if not presentationApplied then
                        BridgeLog("[Bridge] optional card presentation skipped: " .. tostring(presentationError))
                    end
                    BridgePresentationMetric("snapshotVisualDesignations")
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

function BridgeShowResourceCounter(counter, position, seat)
    if counter == nil or position == nil then return end
    pcall(function() counter.setInvisibleTo({}) end)
    -- Mana counters must face the same direction as the life counter they are
    -- positioned relative to. Match the life counter orientation: 180Â° when
    -- player is on far side (tableSideZ < 0), 0Â° when on near side.
    if seat ~= nil then
        pcall(function() counter.setRotation({0, seat.tableSideZ < 0 and 180 or 0, 0}) end)
    end
    pcall(function() counter.setPosition(position) end)
end

-- Resource-row and Monarch objects are presentation-owned, named objects. A
-- single hydration pass indexes objects that survived Save & Play; steady
-- state must use the index and never scan the whole table to prove that a
-- zero-valued object is absent.
function BridgeHydratePresentationObjectIndexes()
    if BridgeState.resourceCounterIndexHydrated == true
        and BridgeState.monarchHelperIndexHydrated == true then return end

    BridgePresentationMetric("worldScanCount")
    BridgePresentationMetric("resourceWorldScanCount")
    local resourceObjects = {}
    for _, object in ipairs(getAllObjects()) do
        if BridgeObjectIsUsable(object) then
            local guid = BridgeSafeObjectGuid(object)
            local name = tostring(BridgeSafeObjectName(object) or "")
            local manaKind, manaSeat = string.match(name, "^Forge Mana ([WUBRGC]) (forge%-player%-[12])$")
            local trackerKind, trackerSeat = string.match(name, "^Forge (energy|experience|poison|speed) (forge%-player%-[12])$")
            local kind = manaKind or trackerKind
            local seatId = manaSeat or trackerSeat
            if guid ~= nil and kind ~= nil and seatId ~= nil then
                BridgeRegisterPresentationObject(object, "resource_row_" .. tostring(kind))
                resourceObjects[seatId] = resourceObjects[seatId] or {}
                if resourceObjects[seatId][kind] == nil then
                    resourceObjects[seatId][kind] = guid
                end
            end
            if BridgeState.monarchHelperGuid == nil and object.tag == "Card"
                and string.sub(string.lower(name), 1, 10) == "the monarch" then
                BridgeRegisterPresentationObject(object, "monarch_helper")
                BridgeState.monarchHelperGuid = guid
            end
        end
    end
    for seatId, resources in pairs(resourceObjects) do
        BridgeState.resourceCounterGuidBySeatId[seatId] = BridgeState.resourceCounterGuidBySeatId[seatId] or {}
        for kind, guid in pairs(resources) do
            if BridgeState.resourceCounterGuidBySeatId[seatId][kind] == nil then
                BridgeState.resourceCounterGuidBySeatId[seatId][kind] = guid
            end
        end
    end
    BridgeState.resourceCounterIndexHydrated = true
    BridgeState.monarchHelperIndexHydrated = true
end

function BridgeFindResourceCounter(seatId, kind, definition)
    BridgeState.resourceCounterGuidBySeatId[seatId] = BridgeState.resourceCounterGuidBySeatId[seatId] or {}
    local guid = BridgeState.resourceCounterGuidBySeatId[seatId][kind]
    local counter = guid and BridgeGetLiveObjectByGuid(guid) or nil
    if counter ~= nil then return counter end
    -- A missing cached GUID is an ordinary zero-resource state, not evidence
    -- that the world needs to be searched. Hydration is performed once at the
    -- session boundary; positive values can create a new presentation object.
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
            if sessionId == BridgeState.eventSessionId then
                BridgeSetNativeTrackerValue(counter, BridgeResourceValue(seatId, kind))
                -- Re-run once after TTS has registered the clone. This covers
                -- resource events that arrive during the clone's first frame.
                BridgeRefreshResourceRow(seatId)
            end
        end, 2)
        return counter
    end
    BridgeStartupPerfCounter("deckTakeObjectCalls", 1)
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
            if sessionId == BridgeState.eventSessionId then
                BridgeSetNativeTrackerValue(taken, BridgeResourceValue(seatId, kind))
                BridgeRefreshResourceRow(seatId)
            end
        end, 2)
    end})
    return nil
end

-- Reconcile one compact row from authoritative Forge values.  Zero-valued
-- resources are hidden/retired and never occupy a slot; remaining counters
-- are packed contiguously in the stable order above.
function BridgeRefreshResourceRow(seatId)
    BridgePresentationMetric("resourceRowRefreshCount")
    local resourceToken = BridgePerformanceBegin("resource_row_total")
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil or BridgeResourceRowPosition(seatId, 1) == nil then
        BridgePerformanceEnd(resourceToken, "resource_row_total_end", "resourceRow")
        return false
    end
    BridgeState.resourceCounterGuidBySeatId[seatId] = BridgeState.resourceCounterGuidBySeatId[seatId] or {}
    BridgeState.manaCounterGuidBySeatId[seatId] = BridgeState.resourceCounterGuidBySeatId[seatId]
    BridgeState.playerTrackerGuidBySeatId[seatId] = BridgeState.resourceCounterGuidBySeatId[seatId]
    local slot = 0
    for _, kind in ipairs(BRIDGE_RESOURCE_ORDER) do
        local definition = BridgeResourceDefinition(kind)
        local value = BridgeResourceValue(seatId, kind)
        -- Do not look up absent zero-valued resources. A cached object is still
        -- hidden in O(1), while an uncached zero needs no physical operation.
        local counter = nil
        if value > 0 or BridgeState.resourceCounterGuidBySeatId[seatId][kind] ~= nil then
            counter = BridgeFindResourceCounter(seatId, kind, definition)
        end
        if value > 0 then
            slot = slot + 1
            local position = BridgeResourceRowPosition(seatId, slot)
            if counter == nil then counter = BridgeCreateResourceCounter(seatId, kind, definition, position) end
            if counter ~= nil then
                BridgeShowResourceCounter(counter, position, seat)
                BridgeSetNativeTrackerValue(counter, value)
            end
        elseif counter ~= nil then
            BridgeHideResourceCounter(counter)
        end
    end
    BridgePerformanceEnd(resourceToken, "resource_row_total_end", "resourceRow", slot)
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
    if seatId == nil then
        BridgeLog("[Bridge] ignored mana pool update without seatId")
        return false
    end
    BridgeState.playerStateBySeatId[seatId] = BridgeState.playerStateBySeatId[seatId] or {}
    -- Forge's structured producer uses W/U/B/R/G/C, but older adapters and
    -- hand-authored event fixtures have emitted lowercase keys or numeric
    -- strings. Normalize at the authority boundary so every mana event and
    -- snapshot feeds the same absolute resource row.
    local normalized = {}
    for key, value in pairs(manaPool or {}) do
        local canonical = string.upper(tostring(key))
        normalized[canonical] = tonumber(value) or 0
    end
    for _, key in ipairs({"W", "U", "B", "R", "G", "C"}) do
        if normalized[key] == nil then normalized[key] = 0 end
    end
    BridgeState.playerStateBySeatId[seatId].mana = normalized
    if not deferRefresh then BridgeRefreshResourceRow(seatId) end
    return true
end

function BridgeSetNativeTrackerValue(counter, value)
    if counter == nil then return false end
    local amount = math.max(0, tonumber(value or 0) or 0)
    -- Native Counter objects expose setValue.  Do not call assumed helper
    -- functions on cloned table assets: a missing updateVal/updateSave hook
    -- produces a visible TTS error even when wrapped in pcall.
    local nativeOk = pcall(function() counter.setValue(amount) end)
    if nativeOk then return true end

    -- Keep a quiet compatibility fallback for a non-native scripted tracker.
    local setVarOk, setVarError = pcall(function() counter.setVar("val", amount) end)
    if not setVarOk then
        BridgeLog("[Bridge] tracker has no supported value update API: " .. tostring(setVarError))
    end
    return setVarOk
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

function BridgeApplySeatTrackers(seatSnapshot, deferRefresh)
    if seatSnapshot == nil then return end
    local counters = BridgeState.playerCountersBySeatId[seatSnapshot.seatId] or {}
    counters.poison = math.max(0, tonumber(seatSnapshot.poison or counters.poison or 0) or 0)
    counters.speed = math.max(0, tonumber(seatSnapshot.speed or counters.speed or 0) or 0)
    BridgeState.playerCountersBySeatId[seatSnapshot.seatId] = counters
    BridgeState.playerStateBySeatId[seatSnapshot.seatId] = BridgeState.playerStateBySeatId[seatSnapshot.seatId] or {}
    BridgeState.playerStateBySeatId[seatSnapshot.seatId].counters = counters
    if not deferRefresh then BridgeRefreshResourceRow(seatSnapshot.seatId) end
end

function BridgeFindLiveMonarchHelper()
    local known = BridgeState.monarchHelperGuid and BridgeGetLiveObjectByGuid(BridgeState.monarchHelperGuid) or nil
    if known ~= nil then return known end
    BridgeState.monarchHelperGuid = nil
    if BridgeState.monarchHelperIndexHydrated ~= true then
        BridgeHydratePresentationObjectIndexes()
        local hydrated = BridgeState.monarchHelperGuid and BridgeGetLiveObjectByGuid(BridgeState.monarchHelperGuid) or nil
        if hydrated ~= nil then return hydrated end
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
    -- No monarch is the normal steady state. Do not rediscover an absent
    -- helper with a full-world scan during every snapshot.
    local helper = BridgeState.monarchHelperGuid and BridgeGetLiveObjectByGuid(BridgeState.monarchHelperGuid) or nil
    local utilityDeck = BridgeGetLiveObjectByGuid("946716")
    if helper ~= nil and utilityDeck ~= nil and utilityDeck.tag == "Deck" then
        BridgeStartupPerfCounter("deckPutObjectCalls", 1)
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
    BridgeStartupPerfCounter("deckTakeObjectCalls", 1)
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

function BridgeAdvanceEventPollGeneration(reason)
    local oldGeneration = BridgeState.eventPollGeneration or 0
    BridgeState.eventPollGeneration = oldGeneration + 1
    local head = BridgeState.eventQueue ~= nil and BridgeState.eventQueue[1] or nil
    BridgeLog(string.format(
        "[Bridge] EVENT_POLL_GENERATION old=%d new=%d reason=%s session=%s received=%s applied=%s queueHead=%s animation=%s",
        oldGeneration,
        BridgeState.eventPollGeneration,
        tostring(reason or "unspecified"),
        tostring(BridgeState.eventSessionId),
        tostring(BridgeState.lastReceivedEventSequence),
        tostring(BridgeState.lastAppliedEventSequence),
        tostring(head ~= nil and head.sequence or nil),
        tostring(BridgeState.animationRunning)))
    return BridgeState.eventPollGeneration
end

function BridgeAdvanceEventSessionGeneration(reason)
    local oldGeneration = BridgeState.eventSessionGeneration or 0
    BridgeState.eventSessionGeneration = oldGeneration + 1
    BridgeLog(string.format(
        "[Bridge] EVENT_SESSION_GENERATION old=%d new=%d reason=%s session=%s received=%s applied=%s",
        oldGeneration,
        BridgeState.eventSessionGeneration,
        tostring(reason or "unspecified"),
        tostring(BridgeState.eventSessionId),
        tostring(BridgeState.lastReceivedEventSequence),
        tostring(BridgeState.lastAppliedEventSequence)))
    return BridgeState.eventSessionGeneration
end

function BridgeStartEventPolling(sessionId, skipExisting)
    if sessionId == nil then
        BridgeStopOnDesync("cannot poll events without a sessionId")
        return
    end

    if BridgeState.schedulerOwner == "RESYNC" then
        BridgeLog("[Bridge] event polling start deferred: resync owns scheduler")
        return
    end

    if BridgeState.eventSessionId == sessionId and BridgeState.eventPolling then
        return
    end

    BridgePrepareEventSession(sessionId, false)

    BridgeState.skipExistingEventsOnAttach = skipExisting == true
    BridgeState.eventPolling = true
    BridgeState.eventRetryCount = 0
    local generation = BridgeAdvanceEventPollGeneration("start")
    BridgePollEvents(generation)
end

function BridgeRetireResourceRowObjects()
    for seatId, resources in pairs(BridgeState.resourceCounterGuidBySeatId or {}) do
        for _, guid in pairs(resources or {}) do
            BridgeHideResourceCounter(BridgeGetLiveObjectByGuid(guid))
        end
    end
    BridgeState.resourceCounterSpawnInFlightBySeatId = {}
end

function BridgePrepareEventSession(sessionId, forceReset, preserveLiveMappings)
    if not forceReset and BridgeState.eventSessionId == sessionId then
        return
    end

    local replacingMatch = BridgeState.eventSessionId ~= nil and BridgeState.eventSessionId ~= sessionId
    local replacingPhysicalOwnership = BridgeState.physicalOwnershipSessionId ~= nil
        and BridgeState.physicalOwnershipSessionId ~= sessionId
    local checkpoint = BridgeState.resyncCheckpoint
    local preserveCheckpoint = checkpoint ~= nil and checkpoint.sessionId == sessionId and not replacingMatch
    local preservedLiveMappings = nil
    if preserveLiveMappings == true and BridgeState.eventSessionId == sessionId
        and BridgeState.physicalOwnershipSessionId == sessionId then
        preservedLiveMappings = {}
        for instanceId, guid in pairs(BridgeState.physicalByInstanceId or {}) do
            local object = BridgeGetLiveObjectByGuid(guid)
            if BridgeCardInstanceBelongsToSession(instanceId, sessionId)
                and object ~= nil and object.tag == "Card" then
                preservedLiveMappings[instanceId] = {
                    guid = guid,
                    seatId = BridgeState.physicalSeatByGuid[guid],
                    zoneName = BridgeState.physicalZoneByGuid[guid],
                    cardName = BridgeState.cardNameByInstanceId[instanceId]
                }
            end
        end
        for instanceId, mapping in pairs(BridgeState.physicalContainerByInstanceId or {}) do
            if BridgeCardInstanceBelongsToSession(instanceId, sessionId)
                and mapping.deckGuid ~= nil and mapping.cardGuid ~= nil
                and BridgeGetLiveObjectByGuid(mapping.deckGuid) ~= nil then
                preservedLiveMappings[instanceId] = {
                    deckGuid = mapping.deckGuid,
                    cardGuid = mapping.cardGuid,
                    seatId = mapping.seatId,
                    zoneName = mapping.zoneName,
                    cardName = BridgeState.cardNameByInstanceId[instanceId]
                }
            end
        end
    end

    BridgeStopEventPolling("session-prepare")
    BridgeAdvanceEventSessionGeneration("session-prepare")
    BridgeStopDecisionPolling()
    BridgeReturnAttackPresentation(nil)
    BridgeRetireResourceRowObjects()
    -- One world scan recovers named row/helper objects after Save & Play.
    -- Subsequent snapshots use the indexed GUIDs, including the all-zero case.
    BridgeHydratePresentationObjectIndexes()
    BridgeClearPreparedPresentationObjects()
    BridgeState.decisionPresentationGeneration = BridgeState.decisionPresentationGeneration + 1
    BridgeAdvancePhysicalPresentationGeneration("session-replaced")
    BridgeAdvancePhysicalTransactionGeneration("session-replaced")
    -- Resetting the Lua ledgers is not sufficient for a physical Card that
    -- survives cleanup: its TTS custom variables would otherwise advertise
    -- an OLD Forge CardInstanceId into the NEW session.  Fence old callbacks
    -- first (the generation advance above), then retire only identities owned
    -- by the outgoing session before new bootstrap is allowed to inspect the
    -- neutral physical inventory.
    if replacingMatch or replacingPhysicalOwnership then
        local retiringSessionId = BridgeState.physicalOwnershipSessionId or BridgeState.eventSessionId
        if BridgeRetireLivePhysicalIdentitiesForSession ~= nil then
            BridgeRetireLivePhysicalIdentitiesForSession(retiringSessionId, "session-prepare")
        end
    end
    BridgeState.renderedDecisionPresentationKey = nil
    BridgeState.renderedDecisionPhysicalGeneration = nil
    BridgeState.eventSessionId = sessionId
    if BridgeRetireStaleTerminalRecoveryError ~= nil then
        BridgeRetireStaleTerminalRecoveryError("session-prepare")
    end
    BridgeState.hudResyncPending = false
    -- This is the ownership barrier for all physical CardInstance mappings.
    -- A session id can be announced before bootstrap enters this function;
    -- keep an independent marker so a new snapshot cannot mistake old maps
    -- for current-session physical state.
    BridgeState.physicalOwnershipSessionId = sessionId
    if replacingMatch or replacingPhysicalOwnership or checkpoint == nil then
        BridgeState.resyncStage = "Idle"
        BridgeState.resyncStageChangedAt = nil
        BridgeState.resyncAttempt = 0
        BridgeState.resyncRootCause = nil
        BridgeState.resyncLastFailureReason = nil
        BridgeState.resyncLastProgressAt = nil
        BridgeState.resyncNoProgressAttempts = 0
        BridgeState.resyncCircuitOpen = false
        BridgeState.resyncSnapshotFingerprint = nil
        BridgeState.resyncSnapshotRepeatCount = 0
        BridgeState.terminalRecoveryError = nil
        BridgeState.staleDecisionFault = nil
        BridgeState.staleDecisionFaultsByKey = {}
        BridgeState.staleDecisionRetryKey = nil
        BridgeState.staleDecisionRetryCount = 0
        BridgeState.staleDecisionRetryStartedAt = nil
        BridgeState.staleDecisionRetryDeadlineAt = nil
    end
    BridgeState.schedulerOwner = "NORMAL"
    BridgeState.fastForwardSuspendedByResync = false
    BridgeState.desyncLatched = false
    BridgeState.desyncFailureCount = 0
    BridgeState.desyncLastMessage = nil
    if preserveCheckpoint then
        -- A same-session recovery is staged. Keep the last committed cursor
        -- visible until the new snapshot has passed every physical audit.
        BridgeState.lastReceivedEventSequence = checkpoint.lastReceived
        BridgeState.lastAppliedEventSequence = checkpoint.lastApplied
        BridgeState.eventQueue = checkpoint.eventQueue
    else
    BridgeState.lastReceivedEventSequence = 0
    BridgeState.lastAppliedEventSequence = 0
    BridgeState.eventQueue = {}
    BridgeState.eventHistoryGapDeclared = false
    BridgeState.eventHistoryGapAfter = nil
    end
    BridgeState.animationRunning = false
    BridgeState.eventDrainTransaction = nil
    BridgeState.eventDrainWatchdog = {
        sessionId = sessionId,
        sessionGeneration = BridgeState.eventSessionGeneration,
        eventSequence = nil,
        lastAppliedEventSequence = 0,
        blockedSince = nil,
        lastBlockReason = nil,
        logged = false,
        scheduled = false
    }
    BridgeState.decisionLifecycle = {}
    BridgeState.decisionAcceptanceRejections = {}
    BridgeState.diagnosticCaptureLifecycle = {}
    BridgeState.diagnosticCaptureFollowupToken = nil
    BridgeState.diagnosticCaptureFollowupUntil = 0
    BridgeState.lastChoiceAttempt = nil
    BridgeState.yieldPolicyOwnTurn = false
    BridgeCreatureTypeClearDraft("session-replaced")
    BridgeGraveyardClear("session-replaced")
    BridgeState.physicalByInstanceId = {}
    BridgeState.physicalInstanceIdByGuid = {}
    BridgeState.physicalContainerByInstanceId = {}
    BridgeState.physicalContainedInstanceIdByGuid = {}
    -- Slot indices and their generations are session-owned locator state.
    -- Never carry an old match's native Deck topology into a replacement.
    BridgeState.physicalSlotByInstanceId = {}
    BridgeState.libraryBindingGenerationBySeatId = {}
    BridgeState.cardNameByInstanceId = {}
    BridgeState.canonicalCardNameByGuid = {}
    BridgeState.encoderIdentityLoggedGuids = {}
    BridgeState.presentedStatsByGuid = {}
    BridgeState.presentedOwnerControllerByGuid = {}
    BridgeState.presentedPhasedByGuid = {}
    BridgeState.presentedCounterSignatureByGuid = {}
    BridgeState.presentedCounterFallbackSignatureByGuid = {}
    BridgeState.presentedKeywordSignatureByGuid = {}
    BridgeState.presentedIconLayoutByGuid = {}
    BridgeState.unsupportedKeywordLogged = {}
    BridgeState.presentationMetrics = {
        encoderRebuildCount = 0,
        keywordPropWriteCount = 0,
        decalWriteCount = 0,
        fullSnapshotReconcileCount = 0,
        resourceRowRefreshCount = 0,
        resourceWorldScanCount = 0,
        worldScanCount = 0,
        yieldBackpressurePauseCount = 0,
        snapshotVisualCounters = 0,
        snapshotVisualKeywords = 0,
        snapshotVisualCharacteristics = 0,
        snapshotVisualDesignations = 0,
        decisionRenderAttempts = 0,
        decisionRenderExecuted = 0,
        decisionRenderSkippedIdentical = 0
    }
    BridgeState.performanceTrace = {capacity = BRIDGE_PERFORMANCE_TRACE_CAPACITY, head = 0, count = 0, records = {}}
    BridgeState.performanceSummary = {
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
    }
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
    BridgeState.libraryExtractionTransactionBySeatId = {}
    BridgeState.graveyardExtractionActiveBySeatId = {}
    BridgeState.libraryBatchBySeatId = {}
    BridgeState.battlefieldCounts = {}
    BridgeState.graveyardCounts = {}
    BridgeState.counterStateByInstanceId = {}
    BridgeState.keywordStateByInstanceId = {}
    BridgeState.cardDesignationsByInstanceId = {}
    BridgeState.authoritativeObjectByInstanceId = {}
    BridgeState.preparedDescriptionByGuid = {}
    BridgeState.prototypeDescriptionByGuid = {}
    BridgeState.preparedBadgeGuidByInstanceId = {}
    BridgeState.preparedPresentationGuidByInstanceId = {}
    BridgeState.preparedDesignationStateByInstanceId = {}
    BridgeState.preparedSpellControlGuids = {}
    BridgeState.untappedRotationByGuid = {}
    BridgeState.physicalTappedByGuid = {}
    BridgeState.pendingCastBySeatId = {}
    BridgeState.pendingSemanticResolutionByInstanceId = {}
    BridgeState.attackOriginByGuid = {}
    BridgeState.attackLaneGuidBySeatId = {}
    BridgeState.snapshotForgeSequence = 0
    BridgeState.deferredSnapshotReconcile = nil
    BridgeState.snapshotReconcilePending = false
    BridgeState.snapshotReconcilePendingRequest = nil
    BridgeState.snapshotReconcileRequestGeneration = 0
    BridgeState.snapshotReconcileLastAppliedCursor = 0
    BridgeState.snapshotReconcileLastAppliedGeneration = 0
    BridgeState.snapshotReconcileLastAppliedCategory = nil
    BridgeState.lastTurnEventSignature = nil
    BridgeState.lastPhaseEventSignature = nil
    BridgeState.lastPriorityEventSignature = nil
    BridgeState.zoneAnchorGuidBySeatAndZone = {}
    BridgeState.yieldPolicyTurnNumber = nil
    BridgeState.yieldPolicyActiveSeatId = nil
    BridgeState.yieldPolicySessionId = nil
    if BridgeState.ui ~= nil then
        BridgeState.ui.fastForwardActive = false
        BridgeState.ui.fastForwardSessionId = nil
        BridgeState.ui.fastForwardTurnNumber = nil
        BridgeState.ui.fastForwardActiveSeatId = nil
        if replacingMatch then BridgeState.ui.autoPassEmpty = false end
        BridgeState.ui.autoAdvanceMode = BridgeState.ui.autoPassEmpty and "AUTO-PASS EMPTY" or "NORMAL"
    end
    BridgeState.gameEnded = nil
    BridgeState.resultSourceEventId = nil
    BridgeState.resultEventCursor = nil
    BridgeState.resultSessionId = nil
    BridgeState.resultOutcome = nil
    BridgeState.resultReason = nil
    BridgeState.resultPresentationGeneration = 0
    BridgeState.playerStateBySeatId = {}
    BridgeState.playerCountersBySeatId = {}

    -- Same-session authoritative resyncs rebuild presentation, but must not
    -- discard exact public CardInstanceId -> TTS GUID identity. Clearing that
    -- mapping forces bootstrap to reconstruct battlefield/graveyard cards by
    -- display name from the library, which can steal a played land or an
    -- already-milled duplicate during a Thought Scour burst. New sessions
    -- never enter this branch, so old-match identities cannot cross the fence.
    for instanceId, mapping in pairs(preservedLiveMappings or {}) do
        if mapping.deckGuid ~= nil and mapping.cardGuid ~= nil
            and BridgeGetLiveObjectByGuid(mapping.deckGuid) ~= nil then
            BridgeRecordContainedCardIdentity(instanceId, mapping.deckGuid, mapping.cardGuid,
                mapping.seatId, mapping.zoneName, mapping.cardName)
        elseif mapping.guid ~= nil and BridgeGetLiveObjectByGuid(mapping.guid) ~= nil then
            BridgeState.physicalByInstanceId[instanceId] = mapping.guid
            BridgeState.physicalInstanceIdByGuid[mapping.guid] = instanceId
            BridgeState.physicalSeatByGuid[mapping.guid] = mapping.seatId
            BridgeState.physicalZoneByGuid[mapping.guid] = mapping.zoneName
            if mapping.cardName ~= nil then
                BridgeState.cardNameByInstanceId[instanceId] = mapping.cardName
            end
        end
    end
    if BridgeState.ui ~= nil then
        -- A report callback can be lost while TTS is frozen or while a match
        -- is replaced. The capture belongs to the old session, so release
        -- its UI latch at the generation boundary; the guarded callback
        -- cannot mutate the new session.
        if BridgeState.ui.reportCaptureInFlight then
            BridgeLog("[Bridge] retiring diagnostic capture at session boundary")
        end
        BridgeState.ui.reportCaptureInFlight = false
        BridgeState.ui.reportStatus = ""
        BridgeState.ui.uiAttributeCache = {}
        BridgeState.ui.uiAttributeAttemptCount = 0
        BridgeState.ui.uiAttributeWriteCount = 0
        BridgeState.ui.uiAttributeSkippedCount = 0
        BridgeState.ui.uiAttributeUpdateCount = 0
    end
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
    BridgeState.expectedHandInstanceIdsBySeatId = {}
    BridgeState.openingHandReadinessDecisionId = nil
    BridgeState.openingHandReadinessSnapshotPending = false
    BridgeState.openingHandReadinessSnapshotRequested = false
    BridgeState.openingHandReadinessRetryScheduled = false
    BridgeState.handActionReadinessSnapshotDecisionId = nil
    BridgeState.handActionReadinessSnapshotSessionId = nil
    BridgeState.handReadinessRecoveryDecisionId = nil
    BridgeState.handReadinessRecoverySessionId = nil
    BridgeState.handReadinessRecoveryAttempts = 0
    BridgeResetSelectionState()
    BridgeHideMainPriorityControls()
    if BridgeState.turnCounterSessionId ~= sessionId then
        BridgeState.turnCounterSessionId = sessionId
        BridgeState.tableTurnCount = 0
        BridgeState.turnCountsBySeatId = {}
        BridgeRefreshTurnCounterLabels()
    end
end

function BridgeStopEventPolling(reason)
    BridgeState.eventPolling = false
    BridgeAdvanceEventPollGeneration(reason or "stop")
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
    BridgeState.eventRequestGeneration = generation
    BridgeHttp.requestJson("GET", path, nil, function(ok, body, err)
        if generation ~= BridgeState.eventPollGeneration then
            if BridgeState.eventRequestGeneration == generation then
                BridgeState.eventRequestInFlight = false
                BridgeState.eventRequestGeneration = nil
            end
            return
        end

        BridgeState.eventRequestInFlight = false
        BridgeState.eventRequestGeneration = nil
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
            BridgeState.eventHistoryGapDeclared = true
            BridgeState.eventHistoryGapAfter = requestedAfter
            BridgeStopOnDesync("event history gap after sequence " .. tostring(requestedAfter))
            return
        end
        -- A successful no-gap response means the event stream remains owner
        -- of any later cursor Forge has already published.
        BridgeState.eventHistoryGapDeclared = false
        BridgeState.eventHistoryGapAfter = nil

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
                if #BridgeState.eventQueue > BRIDGE_EVENT_QUEUE_MAX then
                    BridgeStopOnDesync("authoritative event queue exceeded bounded capacity")
                    return
                end
            end
            BridgeProcessEventQueue()
            BridgeTryPresentPendingDecision("poll-noqueue")
            end

            BridgeScheduleEventPoll(BridgeCurrentEventPollDelay(), generation)
    end)
end

function BridgeResetEventCommitWatchdog()
    BridgeState.eventCommitWatchdog = {
        eventSequence = nil,
        successfulApplyAttemptsWithoutCommit = 0,
        firstAttemptTimestamp = nil,
        lastAbortReason = nil
    }
end

function BridgeRecordEventCommitAbort(event, reason, sessionId, sessionGeneration)
    local watchdog = BridgeState.eventCommitWatchdog or {}
    if watchdog.eventSequence ~= event.sequence
        or watchdog.sessionId ~= sessionId
        or watchdog.sessionGeneration ~= sessionGeneration then
        watchdog = {
            eventSequence = event.sequence,
            sessionId = sessionId,
            sessionGeneration = sessionGeneration,
            successfulApplyAttemptsWithoutCommit = 0,
            firstAttemptTimestamp = os.clock(),
            lastAbortReason = nil
        }
        BridgeState.eventCommitWatchdog = watchdog
    end
    watchdog.successfulApplyAttemptsWithoutCommit = watchdog.successfulApplyAttemptsWithoutCommit + 1
    watchdog.lastAbortReason = reason
    BridgeLog(string.format(
        "[Bridge] EVENT_TX_ABORT eventSequence=%s eventKind=%s reason=%s session=%s sessionGeneration=%s pollGeneration=%s eventPolling=%s received=%s applied=%s queueLength=%s successfulApplyAttemptsWithoutCommit=%s",
        tostring(event.sequence), tostring(event.kind), tostring(reason), tostring(sessionId),
        tostring(sessionGeneration), tostring(BridgeState.eventPollGeneration),
        tostring(BridgeState.eventPolling), tostring(BridgeState.lastReceivedEventSequence),
        tostring(BridgeState.lastAppliedEventSequence), tostring(#BridgeState.eventQueue),
        tostring(watchdog.successfulApplyAttemptsWithoutCommit)))
    if watchdog.successfulApplyAttemptsWithoutCommit >= 3 then
        BridgeLog(string.format(
            "[Bridge] EVENT_COMMIT_LIVELOCK eventSequence=%s eventKind=%s session=%s lastAbortReason=%s",
            tostring(event.sequence), tostring(event.kind), tostring(sessionId), tostring(reason)))
        BridgeStopOnDesync("EVENT_COMMIT_LIVELOCK event " .. tostring(event.sequence))
    end
end

local function BridgeNormalizeForgeSequence(value)
    local sequence = tonumber(value)
    if sequence == nil or sequence <= 0 then return nil end
    return sequence
end

function BridgeEventsShareForgeMutationGroup(leftEvent, rightEvent)
    if leftEvent == nil or rightEvent == nil then return false, nil end
    local leftSequence = BridgeNormalizeForgeSequence(leftEvent.forgeSequence)
    local rightSequence = BridgeNormalizeForgeSequence(rightEvent.forgeSequence)
    if leftSequence == nil or rightSequence == nil then return false, nil end
    return leftSequence == rightSequence, leftSequence
end

-- Retained only as a forensic reference for the pre-H0 per-event drain.  The
-- active coordinator below owns a contiguous Forge mutation as one physical
-- presentation transaction.
function BridgeProcessEventQueueLegacy()
    local queue = BridgeState.eventQueue or {}
    if #queue == 0 then
        BridgeState.eventDrainWatchdog = {
            sessionId = BridgeState.eventSessionId,
            sessionGeneration = BridgeState.eventSessionGeneration,
            eventSequence = nil,
            lastAppliedEventSequence = BridgeState.lastAppliedEventSequence,
            blockedSince = nil,
            lastBlockReason = nil,
            logged = false,
            scheduled = false
        }
        -- Routine verification is allowed only at a quiescent boundary. The
        -- exact event stream gets first chance to establish the physical state.
        BridgeTryApplyDeferredSnapshotReconcile("event-drain")
        BridgeTryStartPendingSnapshotReconcile("event-drain")
        return
    end

    local blockReason = BridgeEventDrainBlockReason()
    if blockReason ~= "none" then
        -- Never turn a scheduler fence into a silent cursor stall. The
        -- watchdog records the exact state and, if the fence clears without a
        -- normal callback, performs one state-aware retry.
        BridgeObserveEventDrainBlocked(blockReason)
        return
    end

    local processingSessionId = BridgeState.eventSessionId
    local processingSessionGeneration = BridgeState.eventSessionGeneration or 0
    local processingPhysicalTransactionGeneration = BridgeState.physicalTransactionGeneration or 0
    local processingQueue = BridgeState.eventQueue
    local event = BridgeState.eventQueue[1]
    local expected = BridgeState.lastAppliedEventSequence + 1
    if event.sequence ~= expected then
        BridgeStopOnDesync("event application gap: expected " .. tostring(expected) .. " but queued " .. tostring(event.sequence))
        return
    end

    BridgeState.animationRunning = true
    BridgeState.eventDrainTransaction = {
        sessionId = processingSessionId,
        sessionGeneration = processingSessionGeneration,
        physicalTransactionGeneration = processingPhysicalTransactionGeneration,
        eventSequence = event.sequence,
        startedAt = os.clock(),
        continuationScheduled = false
    }
    BridgeState.eventDrainWatchdog = {
        sessionId = processingSessionId,
        sessionGeneration = processingSessionGeneration,
        eventSequence = event.sequence,
        lastAppliedEventSequence = BridgeState.lastAppliedEventSequence,
        blockedSince = nil,
        lastBlockReason = nil,
        logged = false,
        scheduled = false
    }
    BridgeTtsExecutionBreadcrumb("EVENT_ENTER", "authoritative_event", event, "event:" .. tostring(event.sequence))
    BridgeLog(string.format(
        "[Bridge] EVENT_TX_BEGIN eventSequence=%s eventKind=%s session=%s sessionGeneration=%s pollGeneration=%s eventPolling=%s queueHead=%s received=%s applied=%s",
        tostring(event.sequence), tostring(event.kind), tostring(processingSessionId),
        tostring(processingSessionGeneration), tostring(BridgeState.eventPollGeneration),
        tostring(BridgeState.eventPolling), tostring(event.sequence),
        tostring(BridgeState.lastReceivedEventSequence), tostring(BridgeState.lastAppliedEventSequence)))
    local applyCallOk, applied, delay, applyError = pcall(BridgeApplyAuthoritativeEvent, event)
    if not applyCallOk then
        applyError = applied
        applied = false
        delay = nil
        BridgeLog(string.format(
            "[Bridge] EVENT_TX_APPLY_EXCEPTION eventSequence=%s error=%s",
            tostring(event.sequence), tostring(applyError)))
    end
    BridgeLog(string.format(
        "[Bridge] EVENT_TX_APPLY_RESULT eventSequence=%s applied=%s error=%s sessionGenerationBefore=%s sessionGenerationAfter=%s pollGeneration=%s eventPolling=%s queueHead=%s",
        tostring(event.sequence), tostring(applied), tostring(applyError),
        tostring(processingSessionGeneration), tostring(BridgeState.eventSessionGeneration or 0),
        tostring(BridgeState.eventPollGeneration), tostring(BridgeState.eventPolling),
        tostring(BridgeState.eventQueue ~= nil and BridgeState.eventQueue[1] ~= nil
            and BridgeState.eventQueue[1].sequence or nil)))
    BridgeTtsExecutionBreadcrumb("EVENT_EXIT", "authoritative_event", event, "event:" .. tostring(event.sequence))
    if not applied then
        BridgeState.animationRunning = false
        BridgeState.eventDrainTransaction = nil
        BridgeLog(string.format("[Bridge] EVENT_TX_ABORT eventSequence=%s reason=apply_failed", tostring(event.sequence)))
        BridgeStopOnDesync(applyError or ("failed to apply event " .. tostring(event.sequence)))
        return
    end

    -- Polling generation belongs to HTTP callback freshness.  It may change
    -- while this synchronous event transaction is applying and must not turn
    -- a successful physical mutation into a replay.  Only replacement of the
    -- authoritative session/queue can abandon this transaction.
    if processingSessionId ~= BridgeState.eventSessionId
        or processingSessionGeneration ~= (BridgeState.eventSessionGeneration or 0) then
        BridgeState.animationRunning = false
        BridgeState.eventDrainTransaction = nil
        BridgeLog(string.format(
            "[Bridge] EVENT_TX_ABORT eventSequence=%s reason=session_replaced sessionBefore=%s sessionAfter=%s sessionGenerationBefore=%s sessionGenerationAfter=%s",
            tostring(event.sequence), tostring(processingSessionId), tostring(BridgeState.eventSessionId),
            tostring(processingSessionGeneration), tostring(BridgeState.eventSessionGeneration or 0)))
        return
    end
    if BridgeState.eventQueue ~= processingQueue then
        BridgeState.animationRunning = false
        BridgeState.eventDrainTransaction = nil
        BridgeRecordEventCommitAbort(event, "queue_replaced", processingSessionId, processingSessionGeneration)
        BridgeStopOnDesync("event queue replaced while applying event " .. tostring(event.sequence))
        return
    end
    if BridgeState.eventQueue[1] ~= event then
        BridgeState.animationRunning = false
        BridgeState.eventDrainTransaction = nil
        BridgeRecordEventCommitAbort(event, "queue_head_changed", processingSessionId, processingSessionGeneration)
        BridgeStopOnDesync("event queue changed while applying event " .. tostring(event.sequence))
        return
    end

    local oldLastApplied = BridgeState.lastAppliedEventSequence
    table.remove(BridgeState.eventQueue, 1)
    BridgeState.lastAppliedEventSequence = event.sequence
    BridgeState.lastConsumedEventSequence = event.sequence
    BridgeState.lastStateProjectedEventSequence = event.sequence
    BridgeState.lastPhysicalPresentationEventSequence = event.sequence
    if event.forgeSequence ~= nil then
        local forgeSequence = tonumber(event.forgeSequence)
        if forgeSequence ~= nil then
            BridgeState.lastAppliedForgeSequence = math.max(
                tonumber(BridgeState.lastAppliedForgeSequence or 0) or 0,
                forgeSequence)
        end
    end
    if event.revealPresentation ~= nil and BridgeApplyRevealPresentation ~= nil then
        local revealOk, revealError = pcall(BridgeApplyRevealPresentation, event.revealPresentation, event.sequence)
        if not revealOk then BridgeLog("[Bridge] reveal presentation failed: " .. tostring(revealError)) end
    end
    BridgeResetEventCommitWatchdog()
    local nextQueuedEvent = BridgeState.eventQueue[1]
    local delayPostCommitWork, mutationSequence = BridgeEventsShareForgeMutationGroup(event, nextQueuedEvent)
    if delayPostCommitWork then
        BridgeLog(string.format(
            "[Bridge] EVENT_TX_GROUP_PENDING forgeSequence=%s committed=%s next=%s",
            tostring(mutationSequence), tostring(event.sequence), tostring(nextQueuedEvent.sequence)))
    end
    BridgeLog(string.format(
        "[Bridge] EVENT_TX_COMMIT eventSequence=%s oldLastApplied=%s newLastApplied=%s queueLength=%s",
        tostring(event.sequence), tostring(oldLastApplied), tostring(BridgeState.lastAppliedEventSequence),
        tostring(#BridgeState.eventQueue)))
    if BridgeCheckProjectionCoherence ~= nil then
        BridgeCheckProjectionCoherence(BridgeState.lastDecision, "event-drain")
    end
    local transaction = BridgeState.eventDrainTransaction
    if transaction ~= nil then transaction.continuationScheduled = true end

    -- Install the serialized continuation immediately after the cursor commit.
    -- Optional post-commit presentation work is allowed to fail without
    -- stranding animationRunning and blocking the next authoritative event.
    local continuationDelay = (function()
        if delayPostCommitWork then return 0 end
        local nextDelay = delay or 0.1
        if BridgeState.ui ~= nil and BridgeState.ui.fastPlaytest then nextDelay = math.min(nextDelay, 0.05) end
        return nextDelay
    end)()
    BridgeWaitTime(function()
        local ok, continuationError = pcall(function()
            if processingSessionId ~= BridgeState.eventSessionId
                or processingSessionGeneration ~= (BridgeState.eventSessionGeneration or 0)
                or not BridgePhysicalPresentationIsCurrent(processingSessionId, processingPhysicalTransactionGeneration) then
                return
            end
            BridgeState.animationRunning = false
            BridgeState.eventDrainTransaction = nil
            BridgeProcessEventQueue()
        end)
        if not ok then
            BridgeState.animationRunning = false
            BridgeState.eventDrainTransaction = nil
            BridgeLog("[Bridge] EVENT_DRAIN_CONTINUATION_FAILED error=" .. tostring(continuationError))
            BridgeStopOnDesync("event drain continuation failed: " .. tostring(continuationError))
        end
    end, continuationDelay)

    if not delayPostCommitWork then
        local postCommitOk, postCommitError = pcall(function()
            BridgeTryPresentPendingDecision("event-applied")
            if event.kind == "draw" or event.kind == "turn_changed" or event.kind == "phase_changed" then
                -- The old menu may still be rendered when Forge changes state. Ask
                -- Forge for the replacement directly; the refresh is bounded and
                -- single-flight, and acceptance preserves hand-action readiness.
                BridgeRefreshDecisionAfterStateTransition(event.kind)
            end
            if BridgeShouldReconcileAfterEvent(event) then
                BridgeScheduleSnapshotReconcile("event " .. tostring(event.sequence) .. " recovery", "RECOVERY")
            end
        end)
        if not postCommitOk then
            BridgeLog("[Bridge] EVENT_TX_POST_COMMIT_FAILED eventSequence=" .. tostring(event.sequence)
                .. " error=" .. tostring(postCommitError))
            BridgeStopOnDesync("event post-commit failed: " .. tostring(postCommitError))
        end
    end
end

function BridgeZoneLedger(seatId, zoneName)
    BridgeState.zoneLedgerBySeatAndZone = BridgeState.zoneLedgerBySeatAndZone or {}
    BridgeState.zoneLedgerBySeatAndZone[seatId] = BridgeState.zoneLedgerBySeatAndZone[seatId] or {}
    local ledger = BridgeState.zoneLedgerBySeatAndZone[seatId][zoneName]
    if ledger == nil then
        ledger = {}
        BridgeState.zoneLedgerBySeatAndZone[seatId][zoneName] = ledger
    end
    return ledger
end

-- A library batch may remain logically open until the grouped event queue is
-- retired. That bookkeeping must not block the transaction that retires the
-- queue: only outstanding physical workers are a readiness fence here.
function BridgePhysicalMutationOperationsIdle()
    for seatId, _ in pairs(BRIDGE_SEATS or {}) do
        if BridgeState.libraryExtractionActiveBySeatId[seatId] == true
            or #(BridgeState.libraryExtractionQueueBySeatId[seatId] or {}) > 0
            or BridgeState.graveyardExtractionActiveBySeatId[seatId] == true
            or BridgeState.mulliganBottomInsertionActiveBySeatId[seatId] == true
            or #(BridgeState.mulliganBottomQueueBySeatId[seatId] or {}) > 0 then
            return false
        end
    end
    return true
end

function BridgeApplyCommittedZoneLedger(events, eventCount)
    local count = tonumber(eventCount)
    if count == nil then count = # (events or {}) end
    for index = 1, count do
        local event = events[index]
        if event == nil then break end
        local instanceId = event.cardInstanceId
        if instanceId ~= nil and event.seatId ~= nil and event.sourceZone ~= event.destinationZone then
            if event.sourceZone ~= nil then
                local source = BridgeZoneLedger(event.seatId, event.sourceZone)
                for index = #source, 1, -1 do
                    if source[index] == instanceId then table.remove(source, index) end
                end
            end
            if event.destinationZone ~= nil then
                local destination = BridgeZoneLedger(event.seatId, event.destinationZone)
                local found = false
                local destinationCount = 0
                for key, known in pairs(destination) do
                    local numericKey = tonumber(key)
                    if numericKey ~= nil then
                        if numericKey > destinationCount then destinationCount = numericKey end
                        if known == instanceId then found = true end
                    end
                end
                if not found then destination[destinationCount + 1] = instanceId end
            end
        end
    end
end

function BridgeMutationJoinInstanceIds(instanceIds)
    local parts = {}
    for index, instanceId in ipairs(instanceIds or {}) do
        parts[index] = tostring(instanceId)
    end
    return table.concat(parts, ",")
end

local function BridgeAtomicGraveyardPosition(object)
    local position = nil
    if BridgeObjectIsUsable(object) and type(object.getPosition) == "function" then
        pcall(function() position = object.getPosition() end)
    end
    return position
end

local function BridgeAtomicGraveyardGuidSet(values)
    local set = {}
    for _, value in ipairs(values or {}) do
        local guid = value and value.guid or nil
        if guid ~= nil and tostring(guid) ~= "" then set[tostring(guid)] = true end
    end
    return set
end

-- Bounded, public-zone-only topology for future incident ZIPs. Names are read
-- only from the graveyard or from the exact cards Forge is moving there; no
-- library inventory is enumerated.
function BridgeCaptureAtomicGraveyardTopology(seatId, batch, phase)
    local expectedCount = 0
    for _, _ in ipairs(batch and batch.expectedInstances or {}) do
        expectedCount = expectedCount + 1
    end
    local topology = {
        phase = phase, seatId = seatId,
        sessionId = BridgeState.eventSessionId,
        physicalGeneration = BridgeState.physicalTransactionGeneration,
        resyncInFlight = BridgeState.resyncInFlight == true,
        expectedCount = expectedCount,
        staged = {}, graveyardContainers = {}, graveyardEntries = {}, nearby = {}
    }
    local allObjects = {}
    if type(getAllObjects) == "function" then
        pcall(function() allObjects = getAllObjects() or {} end)
    end
    local stagedGuidSet = {}
    for index = 1, (tonumber(batch and batch.stagedCount) or 0) do
        local staged = batch.stagedPhysicalMoves and batch.stagedPhysicalMoves[index] or nil
        local object = staged and staged.object or nil
        local guid = object and BridgeSafeObjectGuid(object) or staged and staged.guid or nil
        if guid ~= nil then stagedGuidSet[tostring(guid)] = true end
    end

    local containedByDeck = {}
    for _, object in ipairs(allObjects) do
        if BridgeObjectIsUsable(object) and object.tag == "Deck" then
            local deckGuid = BridgeSafeObjectGuid(object)
            pcall(function()
                for _, entry in ipairs(object.getObjects() or {}) do
                    local containedGuid = entry and (entry.guid or entry.GUID) or nil
                    if containedGuid ~= nil and stagedGuidSet[tostring(containedGuid)] then
                        containedByDeck[tostring(containedGuid)] = deckGuid
                    end
                end
            end)
        end
    end

    for index = 1, (tonumber(batch and batch.stagedCount) or 0) do
        local staged = batch.stagedPhysicalMoves and batch.stagedPhysicalMoves[index] or nil
        local object = staged and staged.object or nil
        local guid = object and BridgeSafeObjectGuid(object) or staged and staged.guid or nil
        topology.staged[index] = {
            guid = guid, originalGuid = staged and staged.guid or nil,
            cardInstanceId = staged and staged.cardInstanceId or nil,
            tag = object and object.tag or nil, live = BridgeObjectIsUsable(object),
            position = BridgeAtomicGraveyardPosition(object),
            insideDeckGuid = guid and containedByDeck[tostring(guid)] or nil,
            advertisedInstanceId = BridgeReadPhysicalIdentity(object),
            advertisedSessionId = BridgeReadPhysicalSessionIdentity(object),
            inverseInstanceId = guid and BridgeState.physicalInstanceIdByGuid[guid] or nil
        }
    end

    local container = nil
    pcall(function() container = BridgeFindGraveyardContainer(seatId) end)
    if container ~= nil then
        local containerGuid = BridgeSafeObjectGuid(container)
        topology.graveyardContainers[1] = {
            guid = containerGuid, tag = container.tag, live = BridgeObjectIsUsable(container),
            position = BridgeAtomicGraveyardPosition(container)
        }
        local entries = {}
        if container.tag == "Deck" then
            pcall(function() entries = container.getObjects() or {} end)
        elseif container.tag == "Card" then
            entries = {{guid = containerGuid, nickname = BridgeSafeObjectName(container)}}
        end
        local preMutation = batch and batch.preMutationContainedGuidSet or {}
        local preGroup = batch and batch.preGroupContainedGuidSet or {}
        local seenInstances = {}
        local seenEntryGuids = {}
        for index, entry in ipairs(entries) do
            local guid = entry and (entry.guid or entry.GUID) or nil
            local inverse = guid and (BridgeState.physicalContainedInstanceIdByGuid[guid]
                or BridgeState.physicalInstanceIdByGuid[guid]) or nil
            local duplicateInstance = inverse ~= nil and seenInstances[tostring(inverse)] == true
            if inverse ~= nil then seenInstances[tostring(inverse)] = true end
            local duplicateGuid = guid ~= nil and seenEntryGuids[tostring(guid)] == true
            if guid ~= nil then seenEntryGuids[tostring(guid)] = true end
            topology.graveyardEntries[index] = {
                guid = guid, nickname = entry and (entry.nickname or entry.name) or nil,
                stagedGuid = guid and stagedGuidSet[tostring(guid)] == true or false,
                advertisedInstanceId = inverse, inverseInstanceId = inverse,
                existedBeforeMutation = guid and preMutation[tostring(guid)] == true or false,
                appearedDuringGroup = phase == "after-group" and guid
                    and preGroup[tostring(guid)] ~= true or false,
                duplicateContainedGuid = duplicateGuid,
                duplicatePhysicalInstance = duplicateInstance
            }
        end
    end

    local anchor = nil
    pcall(function() anchor = BridgeGraveyardPosition(seatId) end)
    for _, object in ipairs(allObjects) do
        if BridgeObjectIsUsable(object) and (object.tag == "Card" or object.tag == "Deck") then
            local position = BridgeAtomicGraveyardPosition(object)
            local near = anchor ~= nil and position ~= nil
                and (((tonumber(position.x) or 0) - (tonumber(anchor.x) or 0)) ^ 2
                    + ((tonumber(position.z) or 0) - (tonumber(anchor.z) or 0)) ^ 2) <= 144
            if near then
                local guid = BridgeSafeObjectGuid(object)
                topology.nearby[#topology.nearby + 1] = {
                    guid = guid, tag = object.tag,
                    name = object.tag == "Card" and BridgeSafeObjectName(object) or nil,
                    live = true, position = position,
                    staged = guid and stagedGuidSet[tostring(guid)] == true or false,
                    advertisedInstanceId = BridgeReadPhysicalIdentity(object),
                    advertisedSessionId = BridgeReadPhysicalSessionIdentity(object),
                    inverseInstanceId = guid and BridgeState.physicalInstanceIdByGuid[guid] or nil,
                    trackedZone = guid and BridgeState.physicalZoneByGuid[guid] or nil
                }
            end
        end
    end
    return topology
end

function BridgeLogAtomicGraveyardTopology(seatId, batch, phase)
    local topology = BridgeCaptureAtomicGraveyardTopology(seatId, batch, phase)
    local encoded = nil
    pcall(function() encoded = JSON.encode(topology) end)
    BridgeLog("[Bridge] MUTATION_GRAVEYARD_TOPOLOGY " .. tostring(encoded or phase))
    return topology
end

function BridgeBuildAtomicLibraryToGraveyardBatches(tx)
    tx.graveyardMutationBatchesBySeatId = {}
    local candidates = {}
    for index = 1, (tonumber(tx.eventCount) or 0) do
        local event = tx.events[index]
        if event == nil then break end
        if tostring(event and event.kind or "") == "card_moved"
            and tostring(event.sourceZone or "") == "library"
            and tostring(event.destinationZone or "") == "graveyard"
            and event.seatId ~= nil then
            local seatId = event.seatId
            local batch = candidates[seatId]
            if batch == nil then
                batch = {
                    seatId = seatId,
                    requiredCount = 0,
                    incomingInstanceIds = {},
                    eventSequences = {},
                    eventSequenceSet = {},
                    stagedPhysicalMoves = {},
                    stagedBySequence = {},
                    stagedCount = 0,
                    stagedSettledCount = 0,
                    deferredEvents = {},
                    deferredEventSequenceSet = {},
                    deferredPendingCount = 0,
                    state = "PENDING_STAGE",
                    generation = tx.physicalTransactionGeneration,
                    sessionId = tx.sessionId,
                    eventSessionGeneration = tx.eventSessionGeneration,
                    token = tx.token
                }
                candidates[seatId] = batch
            end
            batch.requiredCount = batch.requiredCount + 1
            batch.eventSequences[batch.requiredCount] = tonumber(event.sequence or 0) or 0
            batch.eventSequenceSet[tostring(event.sequence or "")] = true
            batch.incomingInstanceIds[batch.requiredCount] = event.cardInstanceId
        end
    end

    for seatId, batch in pairs(candidates) do
        if batch.requiredCount >= 2 then
            local committed = BridgeZoneLedger(seatId, "graveyard")
            local stagedLedger = {}
            for _, instanceId in ipairs(committed or {}) do
                table.insert(stagedLedger, instanceId)
            end
            for _, instanceId in ipairs(batch.incomingInstanceIds) do
                table.insert(stagedLedger, instanceId)
            end
            batch.stagedGraveyardLedger = stagedLedger
            batch.baseExpectedInstances = {}
            for index, instanceId in ipairs(stagedLedger) do
                batch.baseExpectedInstances[index] = {
                    instanceId = instanceId,
                    cardName = BridgeState.cardNameByInstanceId[instanceId]
                }
            end
            batch.expectedInstances = batch.baseExpectedInstances
            batch.finalExpectedInstances = nil
            local preMutation = BridgeLogAtomicGraveyardTopology(seatId, batch, "before-mutation")
            batch.preMutationContainedGuidSet = BridgeAtomicGraveyardGuidSet(
                preMutation and preMutation.graveyardEntries or {})
            tx.graveyardMutationBatchesBySeatId[seatId] = batch
        end
    end

    -- A compound Forge sequence may contain a stack -> graveyard event after
    -- two library -> graveyard events (Mental Note). Keep that card under the
    -- same transaction owner: applying it immediately would make the strict
    -- graveyard shape audit observe an intermediate multi-loose state while
    -- the owned library batch is still staging. Keep a distinct final
    -- expectation for the post-settlement state so the batch can verify the
    -- 5-card base before the deferred move settles and then the 6-card final
    -- state afterwards.
    for index = 1, (tonumber(tx.eventCount) or 0) do
        local event = tx.events[index]
        if event ~= nil and event.destinationZone == "graveyard"
            and event.sourceZone ~= "library" and event.seatId ~= nil then
            local batch = tx.graveyardMutationBatchesBySeatId[event.seatId]
            if batch ~= nil then
                local key = tostring(event.sequence or "")
                if batch.deferredEventSequenceSet[key] ~= true then
                    batch.deferredEventSequenceSet[key] = true
                    table.insert(batch.deferredEvents, event)
                end
                local finalExpected = {}
                for _, entry in ipairs(batch.baseExpectedInstances or {}) do
                    table.insert(finalExpected, {
                        instanceId = entry and entry.instanceId or nil,
                        cardName = entry and entry.cardName or nil
                    })
                end
                if event.cardInstanceId ~= nil then
                    table.insert(finalExpected, {
                        instanceId = event.cardInstanceId,
                        cardName = BridgeState.cardNameByInstanceId[event.cardInstanceId]
                    })
                end
                batch.finalExpectedInstances = finalExpected
            end
        end
    end
end

local BRIDGE_ATOMIC_GRAVEYARD_STAGING_CLEARANCE = 3.25
local BRIDGE_ATOMIC_GRAVEYARD_STAGING_SPACING = 3.60
local BRIDGE_ATOMIC_GRAVEYARD_DESTINATION_RADIUS = 3.50
local BRIDGE_ATOMIC_GRAVEYARD_STAGING_RADIUS = 0.35
local BRIDGE_ATOMIC_GRAVEYARD_STABLE_SAMPLES = 2
local BRIDGE_ATOMIC_GRAVEYARD_MAX_STAGING_SAMPLES = 30

local function BridgeAtomicHorizontalDistance(left, right)
    if left == nil or right == nil then return nil end
    local dx = (tonumber(left.x) or 0) - (tonumber(right.x) or 0)
    local dz = (tonumber(left.z) or 0) - (tonumber(right.z) or 0)
    return math.sqrt(dx * dx + dz * dz)
end

local function BridgeAtomicGraveyardStagingBlocker(position, batch)
    local stagedGuids = {}
    for _, staged in ipairs(batch and batch.stagedPhysicalMoves or {}) do
        local guid = staged and (staged.guid or BridgeSafeObjectGuid(staged.object)) or nil
        if guid ~= nil then stagedGuids[tostring(guid)] = true end
    end
    local nearest = nil
    for _, object in ipairs(getAllObjects() or {}) do
        local guid = BridgeSafeObjectGuid(object)
        local tag = BridgeSafeObjectTag(object)
        if guid ~= nil and (tag == "Card" or tag == "Deck")
            and stagedGuids[tostring(guid)] ~= true
            and not BridgeIsPresentationOnlyObject(object) then
            local zone = BridgeState.physicalZoneByGuid[guid]
            -- An unknown live game card is conservative blocking evidence;
            -- only a known graveyard object may share this presentation lane.
            if zone ~= "graveyard" then
                local distance = BridgeAtomicHorizontalDistance(position, BridgeAtomicGraveyardPosition(object))
                if distance ~= nil and distance < BRIDGE_ATOMIC_GRAVEYARD_STAGING_CLEARANCE
                    and (nearest == nil or distance < nearest.distance) then
                    nearest = {guid = guid, zone = zone or "unknown", distance = distance}
                end
            end
        end
    end
    return nearest
end

-- Keep staged mill cards separated until owned group() forms the native pile.
-- The lane deliberately extends away from the configured battlefield rows
-- (which live on +X for both seats), rather than through them as the former
-- +X offset did. A live non-graveyard object can still occupy any configured
-- space under FREEFORM play, so probe and advance deterministically.
function BridgeAtomicGraveyardStagingPosition(seatId, offset, batch)
    local anchor = BridgeGraveyardPosition(seatId)
    if anchor == nil then return nil, nil end
    local ordinal = math.max(1, tonumber(offset or 1) or 1)
    local nearestBlocker = nil
    for candidateOrdinal = ordinal, ordinal + 11 do
        local position = {
            x = anchor.x - 6.0 - ((candidateOrdinal - 1) * BRIDGE_ATOMIC_GRAVEYARD_STAGING_SPACING),
            y = anchor.y + 1.1,
            z = anchor.z
        }
        local blocker = BridgeAtomicGraveyardStagingBlocker(position, batch)
        if blocker == nil then return position, nearestBlocker end
        nearestBlocker = blocker
    end
    return nil, nearestBlocker
end

-- Native Card userdata is presentation state, not transaction identity. A
-- takeObject/group/putObject transition may retire it between frames, so every
-- asynchronous staging observation resolves the logical member by its stable
-- loose GUID and revalidates the exact Forge instance before touching it.
function BridgeResolveAtomicGraveyardStagedCard(staged)
    if staged == nil or staged.guid == nil then
        return nil, "atomic graveyard staged member has no source GUID"
    end
    local object = BridgeGetLiveObjectByGuid ~= nil and BridgeGetLiveObjectByGuid(staged.guid) or nil
    if not BridgeObjectIsUsable(object) or BridgeSafeObjectTag(object) ~= "Card" then
        return nil, "atomic graveyard staged Card is no longer independently usable guid="
            .. tostring(staged.guid)
    end
    if tostring(BridgeSafeObjectGuid(object) or "") ~= tostring(staged.guid) then
        return nil, "atomic graveyard staged Card GUID changed before destination formation"
    end
    local inverse = BridgeState.physicalInstanceIdByGuid[staged.guid]
        or BridgeReadCurrentSessionPhysicalIdentity(object)
    if inverse ~= nil and tostring(inverse) ~= tostring(staged.cardInstanceId) then
        return nil, "atomic graveyard staged Card exact identity changed guid=" .. tostring(staged.guid)
    end
    staged.object = object
    return object, nil
end

function BridgeObserveAtomicGraveyardStagingSettlement(tx, batch, staged)
    if not BridgeEventMutationIsCurrent(tx) or batch == nil or staged == nil then return end
    if batch.state == "FAILED" or batch.state == "VERIFIED" or staged.settled == true then return end
    staged.settlementSampleCount = (tonumber(staged.settlementSampleCount or 0) or 0) + 1
    local object, resolveError = BridgeResolveAtomicGraveyardStagedCard(staged)
    if object == nil then
        BridgeAbortAtomicGraveyardMutation(tx, batch, resolveError)
        return
    end
    local position = BridgeAtomicGraveyardPosition(object)
    local distance = BridgeAtomicHorizontalDistance(position, staged.stagingPosition)
    local atStagingPosition = distance ~= nil and distance <= BRIDGE_ATOMIC_GRAVEYARD_STAGING_RADIUS
    local sameAsLast = staged.lastObservedPosition ~= nil
        and BridgeAtomicHorizontalDistance(position, staged.lastObservedPosition) <= 0.02
    staged.stableSampleCount = sameAsLast and ((staged.stableSampleCount or 0) + 1) or 1
    staged.lastObservedPosition = position and {x = position.x, y = position.y, z = position.z} or nil
    BridgeRecordPhysicalMutationJournal({
        token = tx.token, forgeSequence = tx.forgeSequence, stage = "STAGING_SETTLEMENT_SAMPLE",
        seatId = batch.seatId, eventSequence = staged.eventSequence,
        cardGuid = staged.guid, sampleCount = staged.settlementSampleCount,
        stableSampleCount = staged.stableSampleCount, distance = distance,
        atStagingPosition = atStagingPosition
    })
    if atStagingPosition and staged.stableSampleCount >= BRIDGE_ATOMIC_GRAVEYARD_STABLE_SAMPLES then
        staged.settled = true
        batch.stagedSettledCount = (batch.stagedSettledCount or 0) + 1
        batch.lastProgressUpdateTick = tonumber(BridgeState.updateTick or 0) or 0
        batch.lastProgressStage = "STAGING_SETTLED"
        BridgeRecordPhysicalMutationProgress(tx, "STAGING_SETTLED", tostring(staged.eventSequence))
        BridgeRecordPhysicalMutationJournal({
            token = tx.token, forgeSequence = tx.forgeSequence, stage = "STAGING_SETTLED",
            seatId = batch.seatId, eventSequence = staged.eventSequence,
            cardGuid = staged.guid, stagedCount = batch.stagedCount,
            settledCount = batch.stagedSettledCount, requiredCount = batch.requiredCount
        })
        if batch.stagedCount >= batch.requiredCount
            and batch.stagedSettledCount >= batch.requiredCount then
            BridgeCommitAtomicGraveyardMutation(tx, batch)
        end
        return
    end
    if staged.settlementSampleCount >= BRIDGE_ATOMIC_GRAVEYARD_MAX_STAGING_SAMPLES then
        BridgeAbortAtomicGraveyardMutation(tx, batch,
            "atomic graveyard staged Card did not become physically ready guid=" .. tostring(staged.guid))
        return
    end
    BridgeWaitFrames(function()
        BridgeObserveAtomicGraveyardStagingSettlement(tx, batch, staged)
    end, 1)
end

function BridgeValidateAtomicGraveyardDestination(batch, container)
    local seatId = batch and batch.seatId or nil
    local anchor = seatId and BridgeGraveyardPosition(seatId) or nil
    local position = BridgeAtomicGraveyardPosition(container)
    local distance = BridgeAtomicHorizontalDistance(position, anchor)
    if BridgeSafeObjectTag(container) ~= "Deck" then
        return false, "graveyard destination is not a usable native Deck", distance, nil
    end
    if distance == nil or distance > BRIDGE_ATOMIC_GRAVEYARD_DESTINATION_RADIUS then
        return false, "graveyard destination is outside its seat anchor radius", distance, nil
    end
    local expected = {}
    for _, entry in ipairs(batch.expectedInstances or {}) do
        local instanceId = entry and entry.instanceId or nil
        if instanceId ~= nil then expected[tostring(instanceId)] = true end
    end
    local unexpected = {}
    local seenExpected = {}
    local entries = BridgeLibraryEntries(container) or {}
    for _, entry in ipairs(entries) do
        local guid = entry and (entry.guid or entry.GUID) or nil
        local instanceId = guid and (BridgeState.physicalContainedInstanceIdByGuid[guid]
            or BridgeState.physicalInstanceIdByGuid[guid]) or nil
        if instanceId ~= nil then
            if expected[tostring(instanceId)] ~= true then
                table.insert(unexpected, tostring(instanceId))
            else
                seenExpected[tostring(instanceId)] = true
            end
        end
    end
    if #unexpected > 0 then
        return false, "graveyard destination contains tracked non-graveyard instance", distance, unexpected
    end
    if BridgeTableSize(entries) ~= BridgeTableSize(expected) then
        return false, "graveyard destination has an unexpected contained-card count", distance, unexpected
    end
    for instanceId, _ in pairs(expected) do
        if seenExpected[instanceId] ~= true then
            return false, "graveyard destination is missing an exact expected instance", distance, unexpected
        end
    end
    return true, nil, distance, unexpected
end

function BridgeMutationBatchForLibraryToGraveyardEvent(event)
    local tx = BridgeState.eventDrainTransaction
    if tx == nil or tx.graveyardMutationBatchesBySeatId == nil or event == nil or event.seatId == nil then
        return nil, nil
    end
    if not BridgeEventMutationIsCurrent(tx) then return nil, nil end
    local batch = tx.graveyardMutationBatchesBySeatId[event.seatId]
    if batch == nil then return tx, nil end
    local sequenceKey = tostring(event.sequence or "")
    if batch.eventSequenceSet[sequenceKey] ~= true
        and batch.deferredEventSequenceSet[sequenceKey] ~= true then return tx, nil end
    return tx, batch
end

function BridgeMutationPhysicalBatchesReady(tx)
    if tx == nil or tx.graveyardMutationBatchesBySeatId == nil then return true, nil end
    for seatId, batch in pairs(tx.graveyardMutationBatchesBySeatId) do
        if batch ~= nil and batch.requiredCount >= 2 then
            if (tonumber(batch.deferredPendingCount or 0) or 0) > 0 then
                return false, string.format("seat=%s deferred-graveyard-events=%s",
                    tostring(seatId), tostring(batch.deferredPendingCount))
            end
            if batch.deferredFailureReason ~= nil then
                return false, string.format("seat=%s deferred-graveyard-failure=%s",
                    tostring(seatId), tostring(batch.deferredFailureReason))
            end
            if batch.state ~= "VERIFIED" then
                return false, string.format("seat=%s state=%s staged=%s/%s",
                    tostring(seatId), tostring(batch.state), tostring(batch.stagedCount or 0),
                    tostring(batch.requiredCount or 0))
            end
        end
    end
    return true, nil
end

function BridgeAbortAtomicGraveyardMutation(tx, batch, reason)
    if batch ~= nil then
        batch.state = "FAILED"
        batch.failureReason = reason
        if BridgeState.libraryBatchBySeatId ~= nil and batch.seatId ~= nil then
            BridgeState.libraryBatchBySeatId[batch.seatId] = nil
        end
    end
    if tx ~= nil then
        BridgeRecordPhysicalMutationProgress(tx, "MUTATION_ABORT", tostring(reason))
        BridgeRecordPhysicalMutationJournal({
            token = tx.token, forgeSequence = tx.forgeSequence, stage = "MUTATION_ABORT",
            seatId = batch and batch.seatId or nil,
            stagedCount = batch and batch.stagedCount or nil,
            requiredCount = batch and batch.requiredCount or nil,
            reason = tostring(reason)
        })
    end
    BridgeLog(string.format(
        "[Bridge] MUTATION_ABORT token=%s forgeSequence=%s range=%s..%s seat=%s cardInstanceIds=%s generation=%s reason=%s",
        tostring(tx and tx.token), tostring(tx and tx.forgeSequence),
        tostring(tx and tx.firstEventSequence), tostring(tx and tx.lastEventSequence),
        tostring(batch and batch.seatId), BridgeMutationJoinInstanceIds(batch and batch.incomingInstanceIds or nil),
        tostring(tx and tx.physicalTransactionGeneration), tostring(reason)))
    if tx ~= nil and BridgeEventMutationIsCurrent(tx) then
        BridgeAbortEventMutationTransaction(tx, "atomic graveyard mutation failed: " .. tostring(reason))
    end
end

-- Native object callbacks are the only place where TTS can invalidate a
-- Card/Deck after the authoritative event function has returned. Keep this
-- error boundary transaction-owned: an exception is a failed physical
-- mutation, never a reason to leave animationRunning without an owner.
function BridgeFailAtomicGraveyardCallback(tx, batch, stage, callbackError)
    local detail = tostring(callbackError or "unknown native callback error")
    BridgeState.lastTtsRuntimeError = {
        stage = tostring(stage),
        detail = detail,
        sessionId = tx and tx.sessionId or BridgeState.eventSessionId,
        eventSessionGeneration = tx and tx.eventSessionGeneration or BridgeState.eventSessionGeneration,
        physicalTransactionGeneration = tx and tx.physicalTransactionGeneration
            or BridgeState.physicalTransactionGeneration,
        transactionToken = tx and tx.token or nil,
        firstEventSequence = tx and tx.firstEventSequence or nil,
        lastEventSequence = tx and tx.lastEventSequence or nil,
        updateTick = tonumber(BridgeState.updateTick or 0) or 0
    }
    BridgeRecordPhysicalMutationJournal({
        token = tx and tx.token or nil, forgeSequence = tx and tx.forgeSequence or nil,
        stage = "NATIVE_CALLBACK_EXCEPTION", seatId = batch and batch.seatId or nil,
        firstEventSequence = tx and tx.firstEventSequence or nil,
        lastEventSequence = tx and tx.lastEventSequence or nil,
        reason = tostring(stage) .. ": " .. detail
    })
    BridgeAbortAtomicGraveyardMutation(tx, batch,
        "native callback exception stage=" .. tostring(stage) .. ": " .. detail)
end

-- Apply non-library graveyard arrivals only after the owned library batch has
-- produced its native destination. Their completion remains part of the same
-- event transaction readiness fence, so a cursor cannot commit while the
-- deferred card is still settling into that Deck.
function BridgeFinalizeDeferredGraveyardBatch(tx, batch)
    if tx == nil or batch == nil or batch.state == "FAILED" or batch.state == "VERIFIED" then
        return
    end
    if (tonumber(batch.deferredPendingCount or 0) or 0) > 0 then
        return
    end
    local finalExpectedInstances = batch.finalExpectedInstances or batch.expectedInstances or nil
    if batch.targetDeckGuid ~= nil then
        local finalDeck = BridgeGetLiveObjectByGuid ~= nil and BridgeGetLiveObjectByGuid(batch.targetDeckGuid) or nil
        if BridgeSafeObjectTag(finalDeck) == "Deck" then
            batch.targetDeck = finalDeck
        end
    end
    local settledDeck = batch.targetDeck or BridgeFindGraveyardContainer(batch.seatId)
    if BridgeSafeObjectTag(settledDeck) ~= "Deck" then
        return
    end
    batch.expectedInstances = finalExpectedInstances or batch.expectedInstances or nil
    if finalExpectedInstances ~= nil then
        if not BridgeRecordGraveyardContainerEntries(batch.seatId, settledDeck, finalExpectedInstances) then
            local reason = "graveyard-final-reconciliation:" .. tostring(batch.seatId)
                .. ":entries=" .. tostring(#(BridgeLibraryEntries(settledDeck) or {}))
                .. ":expected=" .. tostring(BridgeTableSize(finalExpectedInstances or {}))
                .. ":rebind=" .. tostring(BridgeState.lastGraveyardRebindFailure)
            BridgeAbortAtomicGraveyardMutation(tx, batch, reason)
            return
        end
    end
    local shapeOk, shapeReason = BridgeAssertGraveyardObjectShape(
        batch.seatId, "after-deferred-graveyard-settlement", batch.containmentOwner)
    if not shapeOk then
        BridgeAbortAtomicGraveyardMutation(tx, batch, "graveyard-shape:" .. tostring(shapeReason))
        return
    end
    batch.state = "VERIFIED"
    batch.lastProgressUpdateTick = tonumber(BridgeState.updateTick or 0) or 0
    batch.lastProgressStage = "VERIFIED"
    batch.verifiedAt = os.clock()
    if BridgeState.libraryBatchBySeatId ~= nil then
        BridgeState.libraryBatchBySeatId[batch.seatId] = nil
    end
    BridgeRecordPhysicalMutationProgress(tx, "FINAL_VERIFY", "graveyard-shape")
    BridgeRecordPhysicalMutationJournal({
        token = tx.token, forgeSequence = tx.forgeSequence, stage = "FINAL_VERIFY",
        seatId = batch.seatId, targetDeckGuid = batch.targetDeckGuid,
        stagedCount = batch.stagedCount, requiredCount = batch.requiredCount,
        expectedCount = BridgeTableSize(finalExpectedInstances or batch.expectedInstances or {})
    })
    BridgeRecordPhysicalMutationProgress(tx, "VERIFIED", "graveyard-batch")
    BridgeRecordPhysicalMutationJournal({
        token = tx.token, forgeSequence = tx.forgeSequence, stage = "VERIFIED",
        seatId = batch.seatId, targetDeckGuid = batch.targetDeckGuid,
        stagedCount = batch.stagedCount, requiredCount = batch.requiredCount,
        expectedCount = BridgeTableSize(finalExpectedInstances or batch.expectedInstances or {})
    })
    if BridgeWakePhysicalReadinessDependency ~= nil then
        BridgeWakePhysicalReadinessDependency(tx.physicalTransactionGeneration, "atomic-graveyard-verified")
    end
end

function BridgeStartDeferredGraveyardEvents(tx, batch)
    local deferredCount = batch ~= nil and BridgeTableSize(batch.deferredEvents or {}) or 0
    if tx == nil or batch == nil or deferredCount == 0 then return end
    if batch.deferredStarted == true then return end
    batch.deferredStarted = true
    batch.deferredPendingCount = deferredCount
    for _, event in ipairs(batch.deferredEvents or {}) do
        local completed = false
        -- Keep the transaction completion installed until the native
        -- graveyard settlement callback finishes.  BridgeApplyStructuredCardMove
        -- returns as soon as it has dispatched Card -> Deck work; clearing
        -- this field on that synchronous return orphaned Thought Scour's
        -- resolving-spell callback, leaving the batch permanently pending
        -- after its physical cards had already moved.
        local transactionCompletion = event._bridgePhysicalCompletion
        local function completeDeferred(ok, reason)
            if completed then return end
            completed = true
            event._bridgePhysicalCompletion = nil
            event._bridgeDeferredGraveyardDispatch = nil
            if not BridgeEventMutationIsCurrent(tx) then
                BridgeRecordPhysicalMutationJournal({
                    token = tx.token, forgeSequence = tx.forgeSequence,
                    stage = "DEFERRED_GRAVEYARD_STALE_CALLBACK", eventSequence = event.sequence,
                    cardInstanceId = event.cardInstanceId, reason = tostring(reason)
                })
                return
            end
            batch.deferredPendingCount = math.max(0, (tonumber(batch.deferredPendingCount or 0) or 0) - 1)
            if not ok then
                batch.deferredFailureReason = tostring(reason or "deferred graveyard move failed")
                BridgeRecordPhysicalMutationJournal({
                    token = tx.token, forgeSequence = tx.forgeSequence,
                    stage = "DEFERRED_GRAVEYARD_FAILED", eventSequence = event.sequence,
                    cardInstanceId = event.cardInstanceId, reason = batch.deferredFailureReason
                })
                if BridgeEventMutationIsCurrent(tx) then
                    BridgeAbortEventMutationTransaction(tx, batch.deferredFailureReason)
                end
                if transactionCompletion ~= nil then transactionCompletion(false, batch.deferredFailureReason) end
                return
            end
            event._bridgeDeferredGraveyardExecutedToken = tx.token
            BridgeRecordPhysicalMutationProgress(tx, "DEFERRED_GRAVEYARD_SETTLED",
                tostring(event.sequence))
            BridgeRecordPhysicalMutationJournal({
                token = tx.token, forgeSequence = tx.forgeSequence,
                stage = "DEFERRED_GRAVEYARD_SETTLED", eventSequence = event.sequence,
                cardInstanceId = event.cardInstanceId,
                pendingCount = batch.deferredPendingCount
            })
            if batch.deferredPendingCount == 0 then
                BridgeFinalizeDeferredGraveyardBatch(tx, batch)
                if BridgeWakePhysicalReadinessDependency ~= nil then
                    BridgeWakePhysicalReadinessDependency(tx.physicalTransactionGeneration,
                        "deferred-graveyard-settled")
                end
            end
            if transactionCompletion ~= nil then transactionCompletion(true, reason) end
        end
        event._bridgePhysicalCompletion = completeDeferred
        event._bridgeDeferredGraveyardDispatch = true
        event._bridgeContainmentOwner = batch.containmentOwner
        BridgeRecordPhysicalMutationJournal({
            token = tx.token, forgeSequence = tx.forgeSequence,
            stage = "DEFERRED_GRAVEYARD_DISPATCH", eventSequence = event.sequence,
            cardInstanceId = event.cardInstanceId, pendingCount = batch.deferredPendingCount,
            sessionId = tx.sessionId, sessionGeneration = tx.eventSessionGeneration,
            physicalGeneration = tx.physicalTransactionGeneration
        })
        local ok, applied, errorMessage = pcall(BridgeApplyStructuredCardMove, event)
        if not ok or applied ~= true then
            completeDeferred(false, errorMessage or applied or "deferred graveyard move failed")
        else
            BridgeRecordPhysicalMutationJournal({
                token = tx.token, forgeSequence = tx.forgeSequence,
                stage = "DEFERRED_GRAVEYARD_PHYSICAL_DISPATCHED", eventSequence = event.sequence,
                cardInstanceId = event.cardInstanceId
            })
            BridgeLog("[Bridge] DEFERRED_GRAVEYARD_PHYSICAL_DISPATCHED token="
                .. tostring(tx.token) .. " event=" .. tostring(event.sequence)
                .. " instance=" .. tostring(event.cardInstanceId))
        end
    end
end

-- TTS's native group API can return either the new Deck directly or a table
-- containing it. During the creation frame getGUID() may still be unavailable,
-- so do not discard a Deck-shaped result merely because it is not usable yet:
-- the later settlement loop owns that readiness check.
function BridgeDeckFromNativeGroupResult(groupResult)
    if groupResult == nil then return nil end
    local function isDeck(candidate)
        if candidate == nil then return false end
        local ok, tag = pcall(function() return candidate.tag end)
        return ok and tag == "Deck"
    end
    if isDeck(groupResult) then return groupResult end
    if type(groupResult) == "table" then
        for _, candidate in ipairs(groupResult) do
            if isDeck(candidate) then return candidate end
        end
        for _, candidate in pairs(groupResult) do
            if isDeck(candidate) then return candidate end
        end
    end
    return nil
end

function BridgeValidateLooseGraveyardStaging(stagedMoves, stagedCount)
    local seenGuids = {}
    for index = 1, (tonumber(stagedCount) or 0) do
        local staged = stagedMoves and stagedMoves[index] or nil
        local object, resolveError = BridgeResolveAtomicGraveyardStagedCard(staged)
        if object == nil then return false, tostring(resolveError) .. " index=" .. tostring(index) end
        if staged.settled ~= true then
            return false, "staged object has not reached physical readiness index=" .. tostring(index)
        end
        local tag = nil
        pcall(function() tag = object.tag end)
        if tag ~= "Card" then
            return false, "staged object is no longer a loose Card index=" .. tostring(index)
                .. " tag=" .. tostring(tag)
        end
        local guid = BridgeSafeObjectGuid(object)
        if guid == nil or guid == "" then
            return false, "staged loose Card has no GUID index=" .. tostring(index)
        end
        if staged.guid ~= nil and tostring(staged.guid) ~= tostring(guid) then
            return false, "staged loose Card GUID changed before grouping index=" .. tostring(index)
                .. " stagedGuid=" .. tostring(staged.guid) .. " liveGuid=" .. tostring(guid)
        end
        if seenGuids[tostring(guid)] then
            return false, "duplicate staged loose Card GUID before grouping guid=" .. tostring(guid)
        end
        seenGuids[tostring(guid)] = true
    end
    return true, nil
end

function BridgeFindExistingLooseGraveyardCardForBatch(batch, stagedMoves)
    if batch == nil then return nil, nil, nil end
    local stagedGuidSet = {}
    for index = 1, (tonumber(batch.stagedCount) or 0) do
        local staged = stagedMoves and stagedMoves[index] or nil
        local stagedGuid = staged and staged.guid or (staged and BridgeSafeObjectGuid(staged.object) or nil)
        if stagedGuid ~= nil then stagedGuidSet[tostring(stagedGuid)] = true end
    end
    local incomingInstanceSet = {}
    for _, incomingInstanceId in pairs(batch.incomingInstanceIds or {}) do
        incomingInstanceSet[tostring(incomingInstanceId)] = true
    end
    local committedInstanceSet = {}
    for _, committedInstanceId in pairs(BridgeZoneLedger(batch.seatId, "graveyard") or {}) do
        committedInstanceSet[tostring(committedInstanceId)] = true
    end

    local selected = nil
    for guid, mappedSeat in pairs(BridgeState.physicalSeatByGuid or {}) do
        if tostring(mappedSeat) == tostring(batch.seatId)
            and tostring(BridgeState.physicalZoneByGuid[guid] or "") == "graveyard"
            and stagedGuidSet[tostring(guid)] ~= true then
            local object = BridgeGetLiveObjectByGuid ~= nil and BridgeGetLiveObjectByGuid(guid) or nil
            local instanceId = BridgeState.physicalInstanceIdByGuid[guid]
            if BridgeObjectIsUsable(object) and object.tag == "Card"
                and instanceId ~= nil
                and incomingInstanceSet[tostring(instanceId)] ~= true
                and committedInstanceSet[tostring(instanceId)] == true then
                if selected ~= nil then
                    return nil, "multiple existing loose graveyard cards found while forming atomic deck", nil
                end
                selected = {object = object, guid = guid, instanceId = instanceId}
            end
        end
    end
    if selected == nil then return nil, nil, nil end
    return selected.object, nil, selected
end

function BridgeCommitAtomicGraveyardMutation(tx, batch)
    if tx == nil or batch == nil then return end
    if not BridgeEventMutationIsCurrent(tx) then return end
    if batch.state == "VERIFIED" or batch.state == "FAILED" then return end
    batch.state = "DESTINATION_COMMITTING"
    batch.containmentOwner = batch.containmentOwner or {
        token = tx.token,
        generation = tx.physicalTransactionGeneration,
        operation = "AtomicGraveyardFormation",
        provenContainedGuids = {}
    }
    batch.lastProgressUpdateTick = tonumber(BridgeState.updateTick or 0) or 0
    batch.lastProgressStage = "DESTINATION_COMMIT_BEGIN"
    BridgeRecordPhysicalMutationProgress(tx, "DESTINATION_COMMIT_BEGIN", "graveyard")
    BridgeRecordPhysicalMutationJournal({
        token = tx.token, forgeSequence = tx.forgeSequence, stage = "DESTINATION_COMMIT_BEGIN",
        seatId = batch.seatId, stagedCount = batch.stagedCount, requiredCount = batch.requiredCount
    })
    BridgeLog(string.format(
        "[Bridge] MUTATION_DESTINATION_COMMIT_BEGIN token=%s forgeSequence=%s range=%s..%s seat=%s cardInstanceIds=%s generation=%s",
        tostring(tx.token), tostring(tx.forgeSequence), tostring(tx.firstEventSequence),
        tostring(tx.lastEventSequence), tostring(batch.seatId),
        BridgeMutationJoinInstanceIds(batch.incomingInstanceIds), tostring(tx.physicalTransactionGeneration)))

    local target = BridgeFindGraveyardContainer(batch.seatId)
    local stagedMoves = batch.stagedPhysicalMoves or {}
    local startIndex = 1
    if type(group) == "function" then
        local stagingValid, stagingError = BridgeValidateLooseGraveyardStaging(
            stagedMoves, batch.stagedCount)
        if not stagingValid then
            BridgeLogAtomicGraveyardTopology(batch.seatId, batch, "invalid-before-destination-commit")
            BridgeAbortAtomicGraveyardMutation(tx, batch, stagingError)
            return
        end
    end
    local needsNewContainer = target == nil
    local existingLooseCard = nil
    local existingLooseGuid = nil
    local existingLooseInstanceId = nil
    if target ~= nil and target.tag == "Card" then
        existingLooseCard = target
    end
    if existingLooseCard == nil and type(group) == "function" then
        local discoveredCard, discoverError, discoveredMetadata = BridgeFindExistingLooseGraveyardCardForBatch(batch, stagedMoves)
        if discoverError ~= nil then
            BridgeAbortAtomicGraveyardMutation(tx, batch, discoverError)
            return
        end
        if discoveredCard ~= nil then
            existingLooseCard = discoveredCard
            existingLooseGuid = discoveredMetadata and discoveredMetadata.guid or nil
            existingLooseInstanceId = discoveredMetadata and discoveredMetadata.instanceId or nil
            target = discoveredCard
        end
    end

    if type(group) == "function" and (needsNewContainer or existingLooseCard ~= nil) then
        local preGroup = BridgeLogAtomicGraveyardTopology(batch.seatId, batch, "before-group")
        batch.preGroupContainedGuidSet = BridgeAtomicGraveyardGuidSet(
            preGroup and preGroup.graveyardEntries or {})
        local cardsToGroup = {}
        local groupCardCount = 0
        local stagedGuidSet = {}
        local committedInstanceSet = {}
        for _, committedInstanceId in pairs(BridgeZoneLedger(batch.seatId, "graveyard") or {}) do
            committedInstanceSet[tostring(committedInstanceId)] = true
        end
        for index = 1, (tonumber(batch.stagedCount) or 0) do
            local staged = stagedMoves[index]
            local stagedGuid = staged and staged.guid or (staged and BridgeSafeObjectGuid(staged.object) or nil)
            if stagedGuid ~= nil then stagedGuidSet[tostring(stagedGuid)] = true end
        end

        if existingLooseCard ~= nil then
            if not BridgeObjectIsUsable(existingLooseCard) or existingLooseCard.tag ~= "Card" then
                BridgeAbortAtomicGraveyardMutation(tx, batch,
                    "existing loose graveyard object is unavailable or not a Card before grouping")
                return
            end
            existingLooseGuid = existingLooseGuid or BridgeSafeObjectGuid(existingLooseCard)
            if existingLooseGuid == nil or existingLooseGuid == "" then
                BridgeAbortAtomicGraveyardMutation(tx, batch,
                    "existing loose graveyard Card has no GUID before grouping")
                return
            end
            if stagedGuidSet[tostring(existingLooseGuid)] == true then
                BridgeAbortAtomicGraveyardMutation(tx, batch,
                    "existing loose graveyard Card collides with staged incoming GUID " .. tostring(existingLooseGuid))
                return
            end
            if tostring(BridgeState.physicalSeatByGuid[existingLooseGuid] or "") ~= tostring(batch.seatId)
                or tostring(BridgeState.physicalZoneByGuid[existingLooseGuid] or "") ~= "graveyard" then
                BridgeAbortAtomicGraveyardMutation(tx, batch,
                    "existing loose graveyard Card mapping is not seat graveyard guid=" .. tostring(existingLooseGuid))
                return
            end
            existingLooseInstanceId = existingLooseInstanceId or BridgeState.physicalInstanceIdByGuid[existingLooseGuid]
            if existingLooseInstanceId == nil or committedInstanceSet[tostring(existingLooseInstanceId)] ~= true then
                BridgeAbortAtomicGraveyardMutation(tx, batch,
                    "existing loose graveyard Card is not an already-committed graveyard instance guid="
                    .. tostring(existingLooseGuid) .. " instance=" .. tostring(existingLooseInstanceId))
                return
            end
            pcall(function()
                existingLooseCard.setLock(false)
                existingLooseCard.use_hands = false
            end)
            table.insert(cardsToGroup, existingLooseCard)
            groupCardCount = groupCardCount + 1
        end

        for index = 1, (tonumber(batch.stagedCount) or 0) do
            local staged = stagedMoves[index]
            local stagedObject, stagedError = BridgeResolveAtomicGraveyardStagedCard(staged)
            if stagedObject == nil then
                BridgeAbortAtomicGraveyardMutation(tx, batch, tostring(stagedError) .. " index=" .. tostring(index))
                return
            end
            pcall(function()
                stagedObject.setLock(false)
                stagedObject.use_hands = false
            end)
            table.insert(cardsToGroup, stagedObject)
            groupCardCount = groupCardCount + 1
            staged.containmentTransition = BridgeBeginPhysicalContainmentTransition(
                staged.guid, batch.seatId, "atomic-graveyard-staging", nil, {
                    token = tx.token,
                    operation = "AtomicGraveyardFormation",
                    cardInstanceId = staged.cardInstanceId
                })
        end

        if groupCardCount == 0 then
            BridgeAbortAtomicGraveyardMutation(tx, batch,
                "native graveyard grouping had no source Cards")
            return
        end

        local groupOk, groupResult = pcall(function() return group(cardsToGroup) end)
        if not groupOk then
            BridgeAbortAtomicGraveyardMutation(tx, batch,
                "native graveyard group failed: " .. tostring(groupResult))
            return
        end
        local groupedCandidate = BridgeDeckFromNativeGroupResult(groupResult)
        -- group() returns a table and native Card->Deck replacement can lag
        -- behind that return. Keep a logical source handle only as a cue for
        -- the settlement loop; correctness still requires reacquiring one
        -- live Deck from the table before any mapping is published.
        target = groupedCandidate or existingLooseCard or cardsToGroup[1]
        batch.groupRequested = true
        batch.targetDeckGuid = groupedCandidate and BridgeSafeObjectGuid(groupedCandidate) or nil
        batch.lastProgressUpdateTick = tonumber(BridgeState.updateTick or 0) or 0
        batch.lastProgressStage = "GROUP_RESULT"
        BridgeRecordPhysicalMutationProgress(tx, "GROUP_RESULT", "native-group")
        BridgeRecordPhysicalMutationJournal({
            token = tx.token, forgeSequence = tx.forgeSequence, stage = "GROUP_RESULT",
            seatId = batch.seatId, targetDeckGuid = batch.targetDeckGuid,
            stagedCount = batch.stagedCount, requiredCount = batch.requiredCount
        })
        local groupedTag = BridgeSafeObjectTag(groupedCandidate)
        BridgeLog(string.format(
            "[Bridge] MUTATION_DESTINATION_GROUP_REQUESTED token=%s forgeSequence=%s seat=%s cards=%s resultTag=%s generation=%s",
            tostring(tx.token), tostring(tx.forgeSequence), tostring(batch.seatId), tostring(groupCardCount),
            tostring(groupedTag), tostring(tx.physicalTransactionGeneration)))
        local groupShape = {rawType = type(groupResult), resultCount = 0, resultTags = {},
            deckGuid = groupedCandidate and BridgeSafeObjectGuid(groupedCandidate) or nil,
            deckEntryCount = nil}
        if type(groupResult) == "table" and groupedCandidate ~= groupResult then
            for index, candidate in ipairs(groupResult) do
                groupShape.resultCount = groupShape.resultCount + 1
                groupShape.resultTags[index] = BridgeSafeObjectTag(candidate)
            end
        elseif groupResult ~= nil then
            groupShape.resultCount = 1
            groupShape.resultTags[1] = BridgeSafeObjectTag(groupResult)
        end
        if groupedTag == "Deck" then
            pcall(function() groupShape.deckEntryCount = #(groupedCandidate.getObjects() or {}) end)
        end
        local encodedShape = nil
        pcall(function() encodedShape = JSON.encode(groupShape) end)
        BridgeLog("[Bridge] MUTATION_GRAVEYARD_GROUP_RESULT " .. tostring(encodedShape or type(groupResult)))
        BridgeLogAtomicGraveyardTopology(batch.seatId, batch, "after-group")
        startIndex = (tonumber(batch.stagedCount) or 0) + 1
    elseif needsNewContainer then
        local first = stagedMoves[1]
        if first == nil or not BridgeObjectIsUsable(first.object) then
            BridgeAbortAtomicGraveyardMutation(tx, batch,
                "missing first staged card while creating native graveyard container")
            return
        end
        target = first.object
        startIndex = 2
    end

    local targetTag = BridgeSafeObjectTag(target)
    if targetTag ~= "Deck" and targetTag ~= "Card" and batch.groupRequested ~= true then
        BridgeAbortAtomicGraveyardMutation(tx, batch,
            "native graveyard destination is neither Deck nor Card seat=" .. tostring(batch.seatId))
        return
    end

    if startIndex <= (tonumber(batch.stagedCount) or 0) then
        for index = startIndex, (tonumber(batch.stagedCount) or 0) do
            local staged = stagedMoves[index]
            local stagedObject, stagedError = BridgeResolveAtomicGraveyardStagedCard(staged)
            if stagedObject == nil then
                BridgeAbortAtomicGraveyardMutation(tx, batch,
                    tostring(stagedError) .. " index=" .. tostring(index))
                return
            end
            BridgeStartupPerfCounter("deckPutObjectCalls", 1)
            staged.containmentTransition = BridgeBeginPhysicalContainmentTransition(
                staged.guid, batch.seatId, "atomic-graveyard-staging", target, {
                    token = tx.token,
                    operation = "AtomicGraveyardFormation",
                    cardInstanceId = staged.cardInstanceId
                })
            local putOk, putResult = pcall(function() return target.putObject(stagedObject, 0) end)
            if not putOk then
                BridgeAbortAtomicGraveyardMutation(tx, batch,
                    "native graveyard putObject failed index=" .. tostring(index) .. " error=" .. tostring(putResult))
                return
            end
            if BridgeSafeObjectTag(putResult) == "Deck" then target = putResult end
        end
    end

    -- putObject() is asynchronous in TTS.  In particular, the first Card ->
    -- Deck promotion can return nil or the original Card while the live Deck
    -- is only registered on a later frame.  Do not turn that normal physical
    -- settlement window into a Forge/TTS desync.
    local deckResolutionRetries = 0
    local maxDeckResolutionRetries = 60
    local function settleDestinationDeck()
        if not BridgeEventMutationIsCurrent(tx) then return end
        if batch.state == "FAILED" or batch.state == "VERIFIED" then return end

        local resolved = nil
        if BridgeSafeObjectTag(target) == "Deck" then
            resolved = target
        else
            local discovered = BridgeFindGraveyardContainer(batch.seatId)
            if BridgeSafeObjectTag(discovered) == "Deck" then
                resolved = discovered
            end
        end
        if BridgeSafeObjectTag(resolved) == "Deck" then
            local graveyardAnchor = BridgeGraveyardPosition(batch.seatId)
            if graveyardAnchor == nil then
                BridgeAbortAtomicGraveyardMutation(tx, batch, "missing graveyard anchor for destination Deck")
                return
            end
            -- group() inherits a staged Card's position. Move only the newly
            -- formed/selected graveyard container to its authoritative anchor;
            -- never displace battlefield permanents that may occupy a bad
            -- staging coordinate in a legacy table state.
            local positioned, positionError = pcall(function()
                if type(resolved.setPosition) == "function" then
                    resolved.setPosition(graveyardAnchor)
                else
                    resolved.setPositionSmooth(graveyardAnchor, false, true)
                end
            end)
            if not positioned then
                BridgeAbortAtomicGraveyardMutation(tx, batch,
                    "could not position native graveyard Deck: " .. tostring(positionError))
                return
            end
            batch.targetDeck = resolved
            batch.targetDeckGuid = BridgeSafeObjectGuid(resolved)
            batch.settlementSampleCount = (batch.settlementSampleCount or 0) + 1
            batch.lastProgressUpdateTick = tonumber(BridgeState.updateTick or 0) or 0
            batch.lastProgressStage = "DECK_OBSERVED"
            BridgeRecordPhysicalMutationProgress(tx, "DECK_OBSERVED", "graveyard-deck")
            BridgeRecordPhysicalMutationJournal({
                token = tx.token, forgeSequence = tx.forgeSequence, stage = "DECK_OBSERVED",
                seatId = batch.seatId, targetDeckGuid = batch.targetDeckGuid,
                settlementSampleCount = batch.settlementSampleCount,
                stagedCount = batch.stagedCount, requiredCount = batch.requiredCount
            })
            BridgeVerifyGraveyardDeckSettlement(resolved, 8, function(settled, settleError)
        local callbackOk, callbackError = xpcall(function()
        if not BridgeEventMutationIsCurrent(tx) then return end
        if not settled then
            BridgeAbortAtomicGraveyardMutation(tx, batch,
                "graveyard-settlement:" .. tostring(settleError))
            return
        end
        -- `resolved` was observed before the asynchronous settlement frames.
        -- Re-resolve by the stable native Deck GUID (or the seat's current
        -- graveyard container) before dereferencing it again.
        local settledDeck = batch.targetDeckGuid and BridgeGetLiveObjectByGuid(batch.targetDeckGuid) or nil
        if BridgeSafeObjectTag(settledDeck) ~= "Deck" then
            local discovered = BridgeFindGraveyardContainer(batch.seatId)
            if BridgeSafeObjectTag(discovered) == "Deck" then settledDeck = discovered end
        end
        if BridgeSafeObjectTag(settledDeck) ~= "Deck" then
            BridgeAbortAtomicGraveyardMutation(tx, batch,
                "graveyard-settlement target Deck was replaced before reconciliation")
            return
        end
        batch.targetDeck = settledDeck
        batch.targetDeckGuid = BridgeSafeObjectGuid(settledDeck)
        local expectedInstances = batch.expectedInstances
        if batch.finalExpectedInstances ~= nil and (tonumber(batch.deferredPendingCount or 0) or 0) > 0 then
            expectedInstances = batch.baseExpectedInstances or batch.expectedInstances
        end
        if not BridgeRecordGraveyardContainerEntries(batch.seatId, settledDeck, expectedInstances) then
            BridgeLogAtomicGraveyardTopology(batch.seatId, batch, "settled-reconciliation-failed")
            local reason = "graveyard-reconciliation:entries="
                .. tostring(#(BridgeLibraryEntries(settledDeck) or {}))
                .. ":expected=" .. tostring(BridgeTableSize(expectedInstances or {}))
                .. ":rebind=" .. tostring(BridgeState.lastGraveyardRebindFailure)
            BridgeAbortAtomicGraveyardMutation(tx, batch, reason)
            return
        end
        -- Exact contained identity is the native Card->Deck commit point. TTS
        -- may continue to enumerate the retired Card userdata for a few
        -- frames; retain that alias under this transaction instead of
        -- misclassifying it as a second physical Card.
        for stagedIndex = 1, (tonumber(batch.stagedCount) or 0) do
            local staged = batch.stagedPhysicalMoves and batch.stagedPhysicalMoves[stagedIndex] or nil
            local mapping = staged and BridgeState.physicalContainerByInstanceId[staged.cardInstanceId] or nil
            if mapping ~= nil and tostring(mapping.deckGuid or "") == tostring(batch.targetDeckGuid or "")
                and tostring(mapping.seatId or "") == tostring(batch.seatId)
                and tostring(mapping.zoneName or "") == "graveyard" then
                if staged.containmentTransition == nil then
                    staged.containmentTransition = BridgeBeginPhysicalContainmentTransition(
                        staged.guid, batch.seatId, "atomic-graveyard-staging", settledDeck, {
                            token = tx.token,
                            operation = "AtomicGraveyardFormation",
                            cardInstanceId = staged.cardInstanceId
                        })
                end
                staged.containmentTransition.cardInstanceId = staged.cardInstanceId
                BridgeMarkPhysicalContainmentProven(staged.containmentTransition,
                    settledDeck, batch.containmentOwner)
            end
        end
        local destinationOk, destinationError, destinationDistance, unexpectedInstances =
            BridgeValidateAtomicGraveyardDestination(batch, settledDeck)
        BridgeRecordPhysicalMutationJournal({
            token = tx.token, forgeSequence = tx.forgeSequence, stage = "GRAVEYARD_DESTINATION_VERIFY",
            seatId = batch.seatId, targetDeckGuid = BridgeSafeObjectGuid(settledDeck),
            positionX = BridgeAtomicGraveyardPosition(settledDeck)
                and BridgeAtomicGraveyardPosition(settledDeck).x or nil,
            positionZ = BridgeAtomicGraveyardPosition(settledDeck)
                and BridgeAtomicGraveyardPosition(settledDeck).z or nil,
            anchorX = BridgeGraveyardPosition(batch.seatId) and BridgeGraveyardPosition(batch.seatId).x or nil,
            anchorZ = BridgeGraveyardPosition(batch.seatId) and BridgeGraveyardPosition(batch.seatId).z or nil,
            distance = destinationDistance, expectedCount = BridgeTableSize(batch.expectedInstances or {}),
            unexpectedTrackedInstanceCount = #(unexpectedInstances or {}),
            valid = destinationOk == true
        })
        if not destinationOk then
            BridgeAbortAtomicGraveyardMutation(tx, batch,
                "graveyard-destination:" .. tostring(destinationError))
            return
        end
        BridgeRecordPhysicalMutationProgress(tx, "CONTAINED_REBIND", "graveyard-mappings")
        batch.lastProgressUpdateTick = tonumber(BridgeState.updateTick or 0) or 0
        batch.lastProgressStage = "CONTAINED_REBIND"
        BridgeRecordPhysicalMutationJournal({
            token = tx.token, forgeSequence = tx.forgeSequence, stage = "CONTAINED_REBIND",
            seatId = batch.seatId, targetDeckGuid = batch.targetDeckGuid,
            stagedCount = batch.stagedCount, requiredCount = batch.requiredCount
        })
        for _, expected in ipairs(batch.expectedInstances or {}) do
            local instanceId = expected and expected.instanceId or nil
            if instanceId ~= nil then
                local represented, representationError = BridgeVerifyFinalPhysicalRepresentation(
                    instanceId, batch.seatId, "graveyard")
                if not represented then
                    BridgeAbortAtomicGraveyardMutation(tx, batch,
                        "final-representation:" .. tostring(instanceId) .. ":" .. tostring(representationError))
                    return
                end
            end
        end
        local shapeOk, shapeReason = BridgeAssertGraveyardObjectShape(
            batch.seatId, "after-mutation-batch", batch.containmentOwner)
        if not shapeOk then
            BridgeAbortAtomicGraveyardMutation(tx, batch, "graveyard-shape:" .. tostring(shapeReason))
            return
        end
        if (tonumber(batch.deferredPendingCount or 0) or 0) > 0 then
            batch.state = "DEFERRED_SETTLING"
            batch.lastProgressUpdateTick = tonumber(BridgeState.updateTick or 0) or 0
            batch.lastProgressStage = "DEFERRED_SETTLING"
            BridgeRecordPhysicalMutationProgress(tx, "DEFERRED_SETTLING", "graveyard-deferred")
            BridgeRecordPhysicalMutationJournal({
                token = tx.token, forgeSequence = tx.forgeSequence, stage = "DEFERRED_SETTLING",
                seatId = batch.seatId, targetDeckGuid = batch.targetDeckGuid,
                stagedCount = batch.stagedCount, requiredCount = batch.requiredCount,
                deferredPendingCount = batch.deferredPendingCount
            })
            BridgeStartDeferredGraveyardEvents(tx, batch)
            return
        end
        BridgeRecordPhysicalMutationProgress(tx, "FINAL_VERIFY", "graveyard-shape")
        batch.lastProgressUpdateTick = tonumber(BridgeState.updateTick or 0) or 0
        batch.lastProgressStage = "FINAL_VERIFY"
        BridgeRecordPhysicalMutationJournal({
            token = tx.token, forgeSequence = tx.forgeSequence, stage = "FINAL_VERIFY",
            seatId = batch.seatId, targetDeckGuid = batch.targetDeckGuid,
            stagedCount = batch.stagedCount, requiredCount = batch.requiredCount
        })
        batch.state = "VERIFIED"
        batch.lastProgressUpdateTick = tonumber(BridgeState.updateTick or 0) or 0
        batch.lastProgressStage = "VERIFIED"
        batch.verifiedAt = os.clock()
        if BridgeState.libraryBatchBySeatId ~= nil then
            BridgeState.libraryBatchBySeatId[batch.seatId] = nil
        end
        BridgeLog(string.format(
            "[Bridge] MUTATION_DESTINATION_VERIFIED token=%s forgeSequence=%s range=%s..%s seat=%s cardInstanceIds=%s generation=%s",
            tostring(tx.token), tostring(tx.forgeSequence), tostring(tx.firstEventSequence),
            tostring(tx.lastEventSequence), tostring(batch.seatId),
            BridgeMutationJoinInstanceIds(batch.incomingInstanceIds), tostring(tx.physicalTransactionGeneration)))
        BridgeRecordPhysicalMutationProgress(tx, "VERIFIED", "graveyard-batch")
        BridgeRecordPhysicalMutationJournal({
            token = tx.token, forgeSequence = tx.forgeSequence, stage = "VERIFIED",
            seatId = batch.seatId, targetDeckGuid = batch.targetDeckGuid,
            stagedCount = batch.stagedCount, requiredCount = batch.requiredCount
        })
        if BridgeWakePhysicalReadinessDependency ~= nil then
            BridgeWakePhysicalReadinessDependency(tx.physicalTransactionGeneration, "atomic-graveyard-verified")
        end
        end, function(error) return tostring(error) end)
        if not callbackOk then
            BridgeFailAtomicGraveyardCallback(tx, batch, "graveyard-settlement", callbackError)
        end
    end, function(sampleCount, inventory)
        BridgeLog(string.format(
            "[Bridge] MUTATION_DESTINATION_SETTLEMENT_SAMPLE token=%s forgeSequence=%s seat=%s sample=%s inventoryCount=%s generation=%s",
            tostring(tx.token), tostring(tx.forgeSequence), tostring(batch.seatId),
            tostring(sampleCount), tostring(#(inventory or {})), tostring(tx.physicalTransactionGeneration)))
            end)
            return
        end

        deckResolutionRetries = deckResolutionRetries + 1
        if deckResolutionRetries >= maxDeckResolutionRetries then
            BridgeAbortAtomicGraveyardMutation(tx, batch,
                "TTS did not produce an active graveyard Deck for staged cards after "
                .. tostring(maxDeckResolutionRetries) .. " frame checks")
            return
        end
        BridgeLog(string.format(
            "[Bridge] MUTATION_DESTINATION_WAITING_FOR_DECK token=%s forgeSequence=%s seat=%s retry=%s/%s generation=%s",
            tostring(tx.token), tostring(tx.forgeSequence), tostring(batch.seatId),
            tostring(deckResolutionRetries), tostring(maxDeckResolutionRetries),
            tostring(tx.physicalTransactionGeneration)))
        BridgeWaitFrames(settleDestinationDeck, 1)
    end
    settleDestinationDeck()
end

function BridgeStageAtomicLibraryToGraveyardMove(tx, batch, event, taken, complete)
    if tx == nil or batch == nil then
        if complete ~= nil then complete("missing-mutation-batch") end
        return
    end
    if not BridgeEventMutationIsCurrent(tx) then
        if complete ~= nil then complete("stale-mutation") end
        return
    end
    if batch.state == "FAILED" or batch.state == "VERIFIED" then
        if complete ~= nil then complete("terminal-mutation") end
        return
    end
    local sequenceKey = tostring(event and event.sequence or "")
    if batch.stagedBySequence[sequenceKey] ~= nil then
        if complete ~= nil then complete("duplicate-stage-callback") end
        return
    end
    if not BridgeObjectIsUsable(taken) then
        BridgeAbortAtomicGraveyardMutation(tx, batch,
            "staged extraction returned unusable object sequence=" .. tostring(event and event.sequence))
        if complete ~= nil then complete("unusable-staged-object") end
        return
    end
    local seat = BRIDGE_SEATS[event.seatId]
    local anchor = BridgeGraveyardPosition(event.seatId)
    local stagedPosition = nil
    if seat ~= nil and anchor ~= nil then
        local offset = (batch.stagedCount or 0) + 1
        local nearestBlocker = nil
        stagedPosition, nearestBlocker = BridgeAtomicGraveyardStagingPosition(event.seatId, offset, batch)
        if stagedPosition == nil then
            BridgeAbortAtomicGraveyardMutation(tx, batch,
                "no safe atomic graveyard staging position")
            if complete ~= nil then complete("no-safe-staging-position") end
            return
        end
        local stagedOk, stagedError = pcall(function()
            taken.use_hands = false
            BridgeSetPhysicalFaceDown(taken, seat, false)
            if type(taken.setPosition) == "function" then
                taken.setPosition(stagedPosition)
            else
                -- Non-TTS deterministic probes may expose only the smooth API.
                taken.setPositionSmooth(stagedPosition, false, true)
            end
            taken.setLock(true)
        end)
        if not stagedOk then
            BridgeAbortAtomicGraveyardMutation(tx, batch,
                "could not position atomic graveyard staging Card: " .. tostring(stagedError))
            if complete ~= nil then complete("staging-position-failed") end
            return
        end
        BridgeRecordPhysicalMutationJournal({
            token = tx.token, forgeSequence = tx.forgeSequence, stage = "STAGING_POSITION",
            seatId = event.seatId, eventSequence = event.sequence,
            stagingX = stagedPosition.x, stagingY = stagedPosition.y, stagingZ = stagedPosition.z,
            graveyardAnchorX = anchor.x, graveyardAnchorY = anchor.y, graveyardAnchorZ = anchor.z,
            nearestBlockerGuid = nearestBlocker and nearestBlocker.guid or nil,
            nearestBlockerZone = nearestBlocker and nearestBlocker.zone or nil,
            nearestBlockerDistance = nearestBlocker and nearestBlocker.distance or nil
        })
    end
    local staged = {
        eventSequence = event.sequence,
        cardInstanceId = event.cardInstanceId,
        sourceZone = event.sourceZone,
        destinationZone = event.destinationZone,
        guid = BridgeSafeObjectGuid(taken),
        object = taken,
        stagingPosition = stagedPosition,
        token = tx.token,
        sessionId = tx.sessionId,
        eventSessionGeneration = tx.eventSessionGeneration,
        physicalTransactionGeneration = tx.physicalTransactionGeneration
    }
    batch.stagedBySequence[sequenceKey] = staged
    batch.stagedCount = (batch.stagedCount or 0) + 1
    -- Keep staged move ordering explicit so commit/verification never depends
    -- on implicit length behavior while asynchronous callbacks are retiring.
    batch.stagedPhysicalMoves[batch.stagedCount] = staged
    batch.state = "STAGING"
    batch.lastProgressUpdateTick = tonumber(BridgeState.updateTick or 0) or 0
    batch.lastProgressStage = "STAGED"
    BridgeRecordPhysicalMutationProgress(tx, "STAGED", "library-extraction")
    BridgeRecordPhysicalMutationJournal({
        token = tx.token, forgeSequence = tx.forgeSequence, stage = "STAGED",
        seatId = batch.seatId, eventSequence = event.sequence,
        cardInstanceId = event.cardInstanceId, cardGuid = staged.guid,
        stagedCount = batch.stagedCount, requiredCount = batch.requiredCount
    })
    BridgeLog(string.format(
        "[Bridge] MUTATION_STAGE_EXTRACTED token=%s forgeSequence=%s range=%s..%s seat=%s sequence=%s cardInstanceId=%s staged=%s/%s generation=%s",
        tostring(tx.token), tostring(tx.forgeSequence), tostring(tx.firstEventSequence),
        tostring(tx.lastEventSequence), tostring(batch.seatId), tostring(event.sequence),
        tostring(event.cardInstanceId), tostring(batch.stagedCount), tostring(batch.requiredCount),
        tostring(tx.physicalTransactionGeneration)))

    BridgeObserveAtomicGraveyardStagingSettlement(tx, batch, staged)
    if complete ~= nil then complete() end
end

-- H0: a Forge sequence is a mutation boundary, not a post-commit hint.
-- Queue ownership remains with this object until every event in the contiguous
-- group has finished its physical work.  In particular, lastApplied is never
-- advanced between two events sharing forgeSequence.
function BridgeBuildEventMutationTransaction(queue)
    local first = queue and queue[1] or nil
    if first == nil then return nil end
    local forgeSequence = BridgeNormalizeForgeSequence(first.forgeSequence)
    -- Assign the first entry explicitly so transaction indexing is deterministic
    -- even if a host has mixed-key queue instrumentation.
    local events = {}
    events[1] = first
    local eventCount = 1
    local lastEvent = first
    if forgeSequence ~= nil then
        local index = 2
        while queue[index] ~= nil
            and BridgeNormalizeForgeSequence(queue[index].forgeSequence) == forgeSequence do
            eventCount = eventCount + 1
            events[eventCount] = queue[index]
            lastEvent = queue[index]
            index = index + 1
        end
    end
    local tx = {
        sessionId = BridgeState.eventSessionId,
        eventSessionGeneration = BridgeState.eventSessionGeneration or 0,
        physicalTransactionGeneration = BridgeState.physicalTransactionGeneration or 0,
        forgeSequence = forgeSequence,
        firstEventSequence = first.sequence,
        eventCount = eventCount,
        lastEventSequence = lastEvent.sequence,
        events = events,
        state = "PREPARING",
        queue = queue,
        pendingPhysicalEvents = {},
        token = tostring(BridgeState.eventSessionId) .. ":" .. tostring(BridgeState.eventSessionGeneration)
            .. ":" .. tostring(BridgeState.physicalTransactionGeneration or 0) .. ":" .. tostring(first.sequence),
        startedAt = os.clock()
    }
    BridgeRecordPhysicalMutationProgress(tx, "TX_CREATED", "event-transaction")
    BridgeRecordPhysicalMutationJournal({
        token = tx.token, forgeSequence = tx.forgeSequence, stage = "TX_CREATED",
        firstEventSequence = tx.firstEventSequence, lastEventSequence = tx.lastEventSequence,
        requiredCount = tx.eventCount
    })
    BridgeBuildAtomicLibraryToGraveyardBatches(tx)
    BridgeRecordPhysicalMutationProgress(tx, "BATCH_BUILT", "event-transaction")
    return tx
end

function BridgeEventMutationIsCurrent(tx)
    return tx ~= nil and BridgeState.eventDrainTransaction == tx
        and tx.state ~= "ABORTED"
        and tx.sessionId == BridgeState.eventSessionId
        and tx.eventSessionGeneration == (BridgeState.eventSessionGeneration or 0)
        and tx.physicalTransactionGeneration == (BridgeState.physicalTransactionGeneration or 0)
        and BridgeState.eventQueue == tx.queue
end

function BridgeAbortEventMutationTransaction(tx, reason)
    if tx == nil or tx.state == "ABORTED" then return end
    tx.state = "ABORTED"
    BridgeRecordPhysicalMutationProgress(tx, "EVENT_ABORT", tostring(reason))
    BridgeRecordPhysicalMutationJournal({
        token = tx.token, forgeSequence = tx.forgeSequence, stage = "EVENT_ABORT",
        firstEventSequence = tx.firstEventSequence, lastEventSequence = tx.lastEventSequence,
        reason = tostring(reason)
    })
    if BridgeState.eventDrainTransaction == tx then BridgeState.eventDrainTransaction = nil end
    BridgeState.animationRunning = false
    BridgeState.presentationState = "DESYNCED"
    BridgeLog("[Bridge] MUTATION_ABORT token=" .. tostring(tx.token) .. " first="
        .. tostring(tx.firstEventSequence) .. " last=" .. tostring(tx.lastEventSequence)
        .. " reason=" .. tostring(reason))
    BridgeLog("[Bridge] EVENT_MUTATION_ABORT token=" .. tostring(tx.token) .. " first="
        .. tostring(tx.firstEventSequence) .. " last=" .. tostring(tx.lastEventSequence)
        .. " reason=" .. tostring(reason))
    BridgeStopOnDesync("event mutation " .. tostring(tx.firstEventSequence) .. "-"
        .. tostring(tx.lastEventSequence) .. " aborted: " .. tostring(reason))
end

function BridgeCommitEventMutationTransaction(tx)
    if not BridgeEventMutationIsCurrent(tx) then return false end
    tx.state = "COMMITTING"
    BridgeRecordPhysicalMutationProgress(tx, "EVENT_COMMIT_BEGIN", "event-transaction")
    local queueHead = tx.queue[1]
    local expectedFirst = tonumber(tx.firstEventSequence or 0) or 0
    if queueHead == nil or (tonumber(queueHead.sequence or 0) or 0) ~= expectedFirst then
        BridgeAbortEventMutationTransaction(tx, "queue ownership changed before commit")
        return false
    end
    if tx.eventCount > 1 then
        local expectedSequence = expectedFirst
        for index = 1, tx.eventCount do
            local queued = tx.queue[index]
            expectedSequence = expectedFirst + (index - 1)
            if queued == nil or (tonumber(queued.sequence or 0) or 0) ~= expectedSequence then
                BridgeAbortEventMutationTransaction(tx, "queue ownership changed before commit")
                return false
            end
        end
    end
    local old = BridgeState.lastAppliedEventSequence
    for _ = 1, tx.eventCount do table.remove(tx.queue, 1) end
    BridgeApplyCommittedZoneLedger(tx.events, tx.eventCount)
    BridgeState.lastAppliedEventSequence = tx.lastEventSequence
    BridgeState.lastConsumedEventSequence = tx.lastEventSequence
    BridgeState.lastStateProjectedEventSequence = tx.lastEventSequence
    BridgeState.lastPhysicalPresentationEventSequence = tx.lastEventSequence
    if tx.forgeSequence ~= nil then
        BridgeState.lastAppliedForgeSequence = math.max(tonumber(BridgeState.lastAppliedForgeSequence or 0) or 0, tx.forgeSequence)
    end
    tx.state = "COMMITTED"
    BridgeRecordPhysicalMutationProgress(tx, "EVENT_COMMIT", "event-transaction")
    BridgeRecordPhysicalMutationJournal({
        token = tx.token, forgeSequence = tx.forgeSequence, stage = "EVENT_COMMIT",
        firstEventSequence = tx.firstEventSequence, lastEventSequence = tx.lastEventSequence,
        stagedCount = tx.eventCount, requiredCount = tx.eventCount
    })
    BridgeState.eventDrainTransaction = nil
    BridgeState.animationRunning = false
    BridgeState.presentationState = "RUNNING"
    BridgeResetEventCommitWatchdog()
    BridgeLog("[Bridge] MUTATION_COMMIT token=" .. tostring(tx.token) .. " forgeSequence="
        .. tostring(tx.forgeSequence) .. " first=" .. tostring(tx.firstEventSequence)
        .. " last=" .. tostring(tx.lastEventSequence)
        .. " count=" .. tostring(tx.eventCount)
        .. " generation=" .. tostring(tx.physicalTransactionGeneration))
    BridgeLog("[Bridge] EVENT_TX_COMMIT transaction=" .. tostring(tx.token) .. " oldLastApplied="
        .. tostring(old) .. " newLastApplied=" .. tostring(tx.lastEventSequence)
        .. " count=" .. tostring(tx.eventCount))
    BridgeTryPresentPendingDecision("mutation-committed")
    -- Preserve one turn of the event loop between mutations.  Besides keeping
    -- animations readable, this prevents synchronous MoonSharp test clocks
    -- from recursively draining an arbitrary queued history in one call.
    BridgeScheduleEventDrainContinuation(tx, 0.01)
    return true
end

function BridgeProcessEventQueue()
    local queue = BridgeState.eventQueue or {}
    if #queue == 0 then
        BridgeTryApplyDeferredSnapshotReconcile("event-drain")
        BridgeTryStartPendingSnapshotReconcile("event-drain")
        return
    end
    BridgeRetireInvalidEventDrainOwnership("queue-entry")
    if BridgeState.eventDrainTransaction ~= nil then return end
    if BridgeState.eventDrainContinuation ~= nil then return end
    local blockReason = BridgeEventDrainBlockReason()
    if blockReason ~= "none" then BridgeObserveEventDrainBlocked(blockReason); return end
    local expected = (tonumber(BridgeState.lastAppliedEventSequence or 0) or 0) + 1
    if queue[1].sequence ~= expected then
        BridgeStopOnDesync("event application gap: expected " .. tostring(expected) .. " but queued " .. tostring(queue[1].sequence))
        return
    end
    local tx = BridgeBuildEventMutationTransaction(queue)
    BridgeState.eventDrainTransaction = tx
    BridgeState.animationRunning = true
    BridgeState.presentationState = "TX_PREPARING"
    BridgeLog("[Bridge] EVENT_TX_BEGIN transaction=" .. tostring(tx.token) .. " forgeSequence="
        .. tostring(tx.forgeSequence) .. " first=" .. tostring(tx.firstEventSequence)
        .. " last=" .. tostring(tx.lastEventSequence) .. " count=" .. tostring(tx.eventCount))
    for seatId, batch in pairs(tx.graveyardMutationBatchesBySeatId or {}) do
        BridgeLog(string.format(
            "[Bridge] MUTATION_STAGE_BEGIN token=%s forgeSequence=%s range=%s..%s seat=%s cardInstanceIds=%s generation=%s",
            tostring(tx.token), tostring(tx.forgeSequence), tostring(tx.firstEventSequence),
            tostring(tx.lastEventSequence), tostring(seatId),
            BridgeMutationJoinInstanceIds(batch.incomingInstanceIds), tostring(tx.physicalTransactionGeneration)))
    end
    for index = 1, (tonumber(tx.eventCount) or 0) do
        local event = tx.events[index]
        if event == nil then
            BridgeAbortEventMutationTransaction(tx, "transaction event array missing index " .. tostring(index))
            return
        end
        -- Every event receives one transaction-owned completion callback.  An
        -- async adapter (library extraction, graveyard settlement, hand
        -- movement) completes it through the serialized physical queue; a
        -- synchronous/idempotent adapter completes it on return.  Cursor
        -- commit is fenced on this owner, not merely on a visible card.
        event._bridgePhysicalCompletionPending = false
        event._bridgePhysicalCompletion = function(ok, reason)
            if not BridgeEventMutationIsCurrent(tx) then return end
            if tx.pendingPhysicalEvents[event.sequence] == nil then return end
            if not ok then
                tx.pendingPhysicalEvents[event.sequence] = nil
                tx.physicalCompletionError = tostring(reason or "physical event completion failed")
                BridgeAbortEventMutationTransaction(tx, tx.physicalCompletionError)
                return
            end
            BridgeFinalizeStructuredStackDeparture(event, reason)
            tx.pendingPhysicalEvents[event.sequence] = nil
            BridgeRecordPhysicalMutationProgress(tx, "EVENT_PHYSICAL_COMPLETE", tostring(event.sequence))
            BridgeRecordPhysicalMutationJournal({
                token = tx.token, forgeSequence = tx.forgeSequence,
                stage = "EVENT_PHYSICAL_COMPLETE", eventSequence = event.sequence,
                cardInstanceId = event.cardInstanceId, reason = reason
            })
        end
        tx.pendingPhysicalEvents[event.sequence] = true
        BridgeState.eventMutationApplyingEvent = event
        local ok, applied, _, err = pcall(BridgeApplyAuthoritativeEvent, event)
        BridgeState.eventMutationApplyingEvent = nil
        if not ok or not applied then
            BridgeAbortEventMutationTransaction(tx, err or applied or "apply failed")
            return
        end
        if event._bridgePhysicalCompletionPending ~= true then
            event._bridgePhysicalCompletion(true, nil)
        end
    end
    -- Async library extraction/Deck settlement callbacks are fenced by the
    -- transaction generation they captured.  Commit only after they have
    -- drained; an aborted transaction can never satisfy this predicate.
    local function awaitPhysicalSettlement()
        if not BridgeEventMutationIsCurrent(tx) then return end
        if BridgeState.desyncLatched == true then
            BridgeAbortEventMutationTransaction(tx, "physical presentation desynchronized")
            return
        end
        -- Tests and hot-reloaded tables can predate these queue maps. They are
        -- presentation caches, never transaction identity, so initialize the
        -- empty form before asking the shared readiness predicate.
        BridgeState.libraryBatchBySeatId = BridgeState.libraryBatchBySeatId or {}
        BridgeState.libraryExtractionQueueBySeatId = BridgeState.libraryExtractionQueueBySeatId or {}
        BridgeState.libraryExtractionActiveBySeatId = BridgeState.libraryExtractionActiveBySeatId or {}
        BridgeState.graveyardExtractionActiveBySeatId = BridgeState.graveyardExtractionActiveBySeatId or {}
        BridgeState.mulliganBottomQueueBySeatId = BridgeState.mulliganBottomQueueBySeatId or {}
        BridgeState.mulliganBottomInsertionActiveBySeatId = BridgeState.mulliganBottomInsertionActiveBySeatId or {}
        local queueProbeOk, queuesIdle = pcall(BridgePhysicalMutationOperationsIdle)
        if not queueProbeOk then
            BridgeAbortEventMutationTransaction(tx,
                "physical-readiness-probe-failed: " .. tostring(queuesIdle))
            return
        end
        local mutationReady, mutationReason = BridgeMutationPhysicalBatchesReady(tx)
        if not mutationReady then
            BridgeState.resyncLastBlockingPredicate = "mutation-batch-pending:" .. tostring(mutationReason)
            BridgeWaitFrames(awaitPhysicalSettlement, 1)
            return
        end
        if next(tx.pendingPhysicalEvents or {}) ~= nil then
            BridgeState.resyncLastBlockingPredicate = "event-physical-completion-pending"
            BridgeWaitFrames(awaitPhysicalSettlement, 1)
            return
        end
        if queuesIdle then
            BridgeCommitEventMutationTransaction(tx)
            return
        end
        BridgeWaitFrames(awaitPhysicalSettlement, 1)
    end
    awaitPhysicalSettlement()
end

-- Decisions are fetched from Forge independently of the animation queue.
-- A decision can therefore already describe event N while TTS is still
-- presenting an older event. Those older events must not erase the current
-- decision or regress its authoritative phase/turn/priority mirror.
function BridgeDecisionOutrunsEvent(decision, event)
    if decision == nil or event == nil then return false end
    local decisionCursor = tonumber(decision.eventCursor or 0) or 0
    local eventSequence = tonumber(event.sequence or 0) or 0
    return decisionCursor > 0 and eventSequence > 0 and decisionCursor > eventSequence
end

function BridgeCurrentDecisionOutrunsEvent(event)
    return BridgeDecisionOutrunsEvent(BridgeState.lastDecision, event)
end

function BridgePendingDecisionOutrunsEvent(event)
    return BridgeDecisionOutrunsEvent(BridgeState.pendingDecision, event)
end

function BridgePhaseEventMatchesCurrentDecision(event)
    local decision = BridgeState.lastDecision
    if decision == nil or event == nil then return false end
    local decisionCursor = tonumber(decision.eventCursor or 0) or 0
    local eventSequence = tonumber(event.sequence or 0) or 0
    if decisionCursor ~= eventSequence or decisionCursor <= 0 then return false end
    local decisionPhase = string.lower(tostring(decision.phaseName or ""))
    local eventPhase = string.lower(tostring(event.phase or ""))
    return decisionPhase ~= "" and decisionPhase == eventPhase
end

-- A poll response can outrun the event queue, but it can also be followed by
-- an already-buffered event from an older turn/phase.  Applying that older
-- event would regress the HUD while trying to preserve the newer decision.
-- Only contradictory events are suppressed; a matching or corroborating
-- event still updates the authoritative BridgeState fields below.
function BridgeAuthoritativeEventSupersededByDecision(event)
    if not BridgeCurrentDecisionOutrunsEvent(event) then return false end
    local decision = BridgeState.lastDecision
    if decision == nil then return false end
    local eventTurn = tonumber(event.turnNumber or 0) or 0
    local decisionTurn = tonumber(decision.turnNumber or 0) or 0
    if eventTurn > 0 and decisionTurn > 0 and eventTurn < decisionTurn then return true end
    if event.kind == "turn_changed"
        and event.activeSeatId ~= nil and decision.activeSeatId ~= nil
        and event.activeSeatId ~= decision.activeSeatId then
        return true
    end
    if event.kind == "phase_changed"
        and event.phase ~= nil and tostring(event.phase) ~= ""
        and decision.phaseName ~= nil and tostring(decision.phaseName) ~= "" then
        local eventPhase = string.upper(tostring(event.phase))
        local decisionPhase = string.upper(tostring(decision.phaseName))
        local function family(value)
            if string.find(value, "UPKEEP", 1, true) then return "UPKEEP" end
            if string.find(value, "DRAW", 1, true) then return "DRAW" end
            if string.find(value, "MAIN", 1, true) then return "MAIN" end
            if string.find(value, "ATTACK", 1, true)
                or string.find(value, "BLOCK", 1, true)
                or string.find(value, "DAMAGE", 1, true)
                or string.find(value, "COMBAT", 1, true) then return "COMBAT" end
            if string.find(value, "END", 1, true) or string.find(value, "CLEANUP", 1, true) then return "END" end
            return value
        end
        if family(eventPhase) ~= family(decisionPhase) then return true end
    end
    return false
end

-- spell_resolved is semantic projection, not an identity-bearing physical
-- transition. Forge's structured card_moved event is the sole normal owner of
-- stack departures. Keeping the pending cast alive here is essential: a
-- later exact stack -> graveyard/battlefield move must still resolve the same
-- physical CardInstanceId and GUID.
function BridgeRecordSemanticSpellResolution(event)
    BridgeState.pendingSemanticResolutionByInstanceId =
        BridgeState.pendingSemanticResolutionByInstanceId or {}
    local pendingCast = event.seatId ~= nil
        and (BridgeState.pendingCastBySeatId or {})[event.seatId] or nil
    local instanceId = event.cardInstanceId
    if instanceId == nil and pendingCast ~= nil and pendingCast.cardInstanceId ~= nil then
        local pendingObject = pendingCast.guid ~= nil and BridgeGetLiveObjectByGuid(pendingCast.guid) or nil
        local pendingName = pendingObject ~= nil and BridgeSafeObjectName(pendingObject) or nil
        local pendingZone = pendingCast.guid ~= nil and BridgeState.physicalZoneByGuid[pendingCast.guid] or nil
        if pendingZone == "stack" and pendingName ~= nil
            and BridgeCardNameMatches(pendingName, event.cardName) then
            instanceId = pendingCast.cardInstanceId
        end
    end
    local structured = instanceId ~= nil
        and BridgeState.pendingStructuredZoneTransitionByInstanceId[instanceId] or nil
    if instanceId ~= nil then
        BridgeState.pendingSemanticResolutionByInstanceId[instanceId] = {
            sessionId = BridgeState.eventSessionId,
            sessionGeneration = BridgeState.eventSessionGeneration,
            eventSequence = event.sequence,
            sourceZone = event.sourceZone,
            destinationZone = event.destinationZone,
            structuredMoveApplied = structured ~= nil and structured.applied == true
        }
    end
    BridgeTracePermanentTransition("SEMANTIC_SPELL_RESOLVED", event,
        pendingCast ~= nil and BridgeGetLiveObjectByGuid(pendingCast.guid) or nil,
        event.sourceZone, "physical-transition-owner=structured-card-moved")
    BridgeLog(string.format(
        "[Bridge] semantic spell resolution retained pending physical transition event=%s instance=%s destination=%s structuredApplied=%s",
        tostring(event.sequence), tostring(instanceId), tostring(event.destinationZone),
        tostring(structured ~= nil and structured.applied == true)))
    -- If a particular Forge transport omits the structured transition, the
    -- cursor-ordered snapshot remains the explicit fallback. Snapshot mutation
    -- is fenced behind the event-drain owner and cannot preempt a later
    -- card_moved event in the same delivered range.
    if structured == nil or structured.applied ~= true then
        BridgeScheduleSnapshotReconcile("semantic spell resolution awaiting structured move "
            .. tostring(instanceId or event.sequence))
    end
    return true, 0.1
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

    if event.kind == "spell_resolved" then
        return BridgeRecordSemanticSpellResolution(event)
    end

    if event.kind == "game_ended" then
        local winners = event.winnerSeatIds or {}
        local losers = event.loserSeatIds or {}
        local reason = event.gameEndReason
        local function recognizedDrawReason(value)
            local normalized = string.lower(tostring(value or ""))
            return normalized == "draw"
                or normalized == "mutual_destruction"
                or normalized == "simultaneous_loss"
                or normalized == "state_based_draw"
                or normalized == "both_lost"
        end
        local humanWon = false
        for _, seatId in ipairs(winners) do
            if seatId == "forge-player-1" then humanWon = true end
        end
        local outcome = nil
        if #winners == 0 and recognizedDrawReason(reason) then
            outcome = "draw"
        elseif #winners > 0 then
            outcome = humanWon and "victory" or "defeat"
        else
            outcome = "unknown"
        end

        BridgeState.gameEnded = {
            authoritative = true,
            winnerSeatIds = winners,
            loserSeatIds = losers,
            reason = reason,
            outcome = outcome,
            sourceEventId = event.eventId,
            sourceEventCursor = event.sequence,
            sourceSessionId = BridgeState.eventSessionId,
            presentationGeneration = BridgeState.decisionPresentationGeneration
        }
        BridgeState.resultSourceEventId = event.eventId
        BridgeState.resultEventCursor = event.sequence
        BridgeState.resultSessionId = BridgeState.eventSessionId
        BridgeState.resultOutcome = outcome
        BridgeState.resultReason = reason
        BridgeState.resultPresentationGeneration = BridgeState.decisionPresentationGeneration
        BridgeState.pendingDecision = nil
        BridgeState.lastDecision = nil
        BridgeState.submitting = false
        if BridgeCancelFastForward ~= nil then BridgeCancelFastForward("game-ended") end
        BridgeClearHighlights()
        BridgeRollbackPendingIntent()
        BridgeResetSelectionState()
        BridgeHideMainPriorityControls()
        BridgeStopDecisionPolling()
        BridgeStopEventPolling("game-ended")
        BridgeScheduleSnapshotReconcile("game_ended final state")
        local label = outcome == "draw" and "DRAW"
            or (outcome == "victory" and "VICTORY"
                or (outcome == "defeat" and "DEFEAT" or "GAME OVER"))
        BridgeSetStatus(label, "GAME OVER" .. (event.gameEndReason and (": " .. tostring(event.gameEndReason)) or ""))
        local bannerColor = outcome == "draw" and {0.95, 0.78, 0.15}
            or (humanWon and {0.2, 0.9, 0.3}
                or (outcome == "defeat" and {0.95, 0.3, 0.3} or {0.9, 0.9, 0.9}))
        broadcastToAll("[Bridge] " .. label .. " â€” game over", bannerColor)
        BridgeLog("[Bridge] GAME_ENDED winners=" .. table.concat(BridgeState.gameEnded.winnerSeatIds, ",")
            .. " losers=" .. table.concat(BridgeState.gameEnded.loserSeatIds, ",")
            .. " reason=" .. tostring(event.gameEndReason)
            .. " outcome=" .. tostring(outcome)
            .. " sourceEventId=" .. tostring(event.eventId)
            .. " cursor=" .. tostring(event.sequence)
            .. " session=" .. tostring(BridgeState.eventSessionId))
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
        local supersededByDecision = BridgeAuthoritativeEventSupersededByDecision(event)
        if supersededByDecision then
            BridgeLog(string.format(
                "[Bridge] applying superseded turn projection while retaining decision event=%s decision=%s",
                tostring(event.sequence), tostring(BridgeState.lastDecision and BridgeState.lastDecision.decisionId)))
        end
        local retainPendingDecision = BridgePendingDecisionOutrunsEvent(event)
        local retainCurrentDecision = supersededByDecision or BridgeCurrentDecisionOutrunsEvent(event)
            or retainPendingDecision
        if retainCurrentDecision then
            local retainedDecision = BridgeState.lastDecision or BridgeState.pendingDecision
            BridgeLog(string.format(
                "[Bridge] applying queued turn event while retaining newer decision %s event=%s decisionCursor=%s",
                tostring(retainedDecision and retainedDecision.decisionId), tostring(event.sequence),
                tostring(retainedDecision and retainedDecision.eventCursor)))
        end
        local turnSignature = table.concat({
            tostring(event.turnNumber or ""),
            tostring(event.activeSeatId or event.seatId or ""),
            tostring(event.prioritySeatId or "")
        }, "|")
        if BridgeState.lastTurnEventSignature == turnSignature then
            return true, 0
        end
        BridgeState.lastTurnEventSignature = turnSignature
        BridgeState.turnSourceEventSequence = event.sequence
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
        BridgeState.activePlayerSourceEventSequence = event.sequence
        -- Priority is an independent Forge state transition. Keep the last
        -- known value here when this turn event has no priority payload; the
        -- following priority event will update it authoritatively.
        if event.prioritySeatId ~= nil then
            BridgeState.prioritySeatId = event.prioritySeatId
            BridgeState.prioritySourceEventSequence = event.sequence
        end
        BridgeRecordAuthoritativeTurn(BridgeState.currentTurnSeatId, tonumber(event.turnNumber or 0))
        local turnSeat = BRIDGE_SEATS[BridgeState.currentTurnSeatId]
        BridgeSetStatus("CURRENT TURN: " .. tostring(turnSeat and turnSeat.ttsColor or BridgeState.currentTurnSeatId), BridgeTurnLabel() .. " - AI THINKING")
        BridgeLog("[Bridge] authoritative turn changed to seat " .. tostring(BridgeState.currentTurnSeatId) .. " turn=" .. tostring(event.turnNumber))
        -- End Turn means "the remainder of this turn". A turn transition is
        -- authoritative proof that scope has ended even when a legacy text
        -- event lacks a numeric turn value or a reliable seat label.
        if BridgeState.yieldPolicyTurnNumber ~= nil then
            BridgeState.yieldPolicyTurnNumber = nil
            BridgeState.yieldPolicyActiveSeatId = nil
            BridgeState.yieldPolicySessionId = nil
            BridgeState.yieldPolicyOwnTurn = false
            BridgeLog("[Bridge] cleared HUD yield policy at authoritative turn transition")
        end
        if BridgeCancelFastForward ~= nil then BridgeCancelFastForward("turn-change") end
        -- A turn boundary retires any decision belonging to the previous
        -- priority/phase transaction. BridgeCurrentDecisionOutrunsEvent above
        -- protects a genuinely newer decision that arrived before this event;
        -- once the event is authoritative, retaining the old decision would
        -- keep stale decision controls mounted and can hide YIELD TURN on the
        -- new opponent turn.
        if not retainCurrentDecision then
            BridgeState.lastDecision = nil
            BridgeState.pendingDecision = nil
            BridgeResetSelectionState()
            BridgeClearHighlights()
        end
        BridgeMarkTransitionExpected(0)
        BridgeUiMarkDirty("turn")
        return true, 0.1
    end

    if event.kind == "phase_changed" then
        local supersededByDecision = BridgeAuthoritativeEventSupersededByDecision(event)
        if supersededByDecision then
            BridgeLog(string.format(
                "[Bridge] applying superseded phase projection while retaining decision event=%s phase=%s decision=%s",
                tostring(event.sequence), tostring(event.phase),
                tostring(BridgeState.lastDecision and BridgeState.lastDecision.decisionId)))
        end
        local retainCurrentDecision = supersededByDecision or BridgeCurrentDecisionOutrunsEvent(event)
        if retainCurrentDecision then
            BridgeLog(string.format(
                "[Bridge] applying queued phase event while retaining newer decision %s event=%s decisionCursor=%s",
                tostring(BridgeState.lastDecision.decisionId), tostring(event.sequence),
                tostring(BridgeState.lastDecision.eventCursor)))
        end
        retainCurrentDecision = retainCurrentDecision or BridgePhaseEventMatchesCurrentDecision(event)
        local phaseSignature = table.concat({
            tostring(event.turnNumber or ""),
            tostring(event.activeSeatId or ""),
            tostring(event.prioritySeatId or ""),
            tostring(event.phase or "")
        }, "|")
        if BridgeState.lastPhaseEventSignature == phaseSignature then
            return true, 0
        end
        BridgeState.lastPhaseEventSignature = phaseSignature
        BridgeState.currentPhase = event.phase or "Unknown phase"
        BridgeState.phaseSourceEventSequence = event.sequence
        if event.turnNumber ~= nil and tonumber(event.turnNumber) ~= nil and tonumber(event.turnNumber) > 0 then
            BridgeState.tableTurnCount = tonumber(event.turnNumber)
            BridgeRefreshTurnCounterLabels()
        end
        if event.activeSeatId ~= nil then
            BridgeState.currentTurnSeatId = event.activeSeatId
            BridgeState.activePlayerSourceEventSequence = event.sequence
        end
        -- Phase and priority are independent authoritative values. Do not
        -- overwrite priority from a phase event that carries no priority.
        if event.prioritySeatId ~= nil then
            BridgeState.prioritySeatId = event.prioritySeatId
            BridgeState.prioritySourceEventSequence = event.sequence
        end
        if not retainCurrentDecision then
            BridgeClearHighlights()
        end
        if not retainCurrentDecision and BridgeState.lastDecision ~= nil and not BridgeState.submitting then
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
        if not retainCurrentDecision then
            BridgeResetSelectionState()
            BridgeHideMainPriorityControls()
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
        BridgeTryPresentPendingDecision("phase-change")
        if retainCurrentDecision and BridgeState.lastDecision ~= nil then
            -- The exact same Forge cursor/phase remains actionable. Refresh
            -- status and highlights after the phase ribbon update without
            -- replacing its selection/cast-preview state.
            BridgeRenderDecision(BridgeState.lastDecision, true)
        end
        BridgeUiMarkDirty("phase")
        return true, 0.1
    end

    if event.kind == "priority_changed" then
        if BridgeCurrentDecisionOutrunsEvent(event) then
            BridgeLog(string.format(
                "[Bridge] retaining newer decision %s over queued priority event=%s decisionCursor=%s",
                tostring(BridgeState.lastDecision.decisionId), tostring(event.sequence),
                tostring(BridgeState.lastDecision.eventCursor)))
            return true, 0
        end
        local prioritySignature = table.concat({
            tostring(event.turnNumber or ""),
            tostring(event.activeSeatId or ""),
            tostring(event.seatId or ""),
            tostring(event.prioritySeatId or ""),
            tostring(event.phase or "")
        }, "|")
        if BridgeState.lastPriorityEventSignature == prioritySignature then
            return true, 0
        end
        BridgeState.lastPriorityEventSignature = prioritySignature
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
        BridgeUiMarkDirty("mana")
        return true, 0.1
    end

    if event.kind == "draw" then
        local applied, drawError = BridgeApplyStructuredCardMove(event)
        return applied, BRIDGE_DRAW_EVENT_PRESENTATION_DELAY, drawError
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

    if event.kind == "tap_changed" then
        BridgeTtsExecutionBreadcrumb("TAP_CHANGED_ENTER", "tap_changed", event, "event:" .. tostring(event.sequence))
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
        BridgeTtsExecutionBreadcrumb("TAP_CHANGED_EXIT", "tap_changed", event, "event:" .. tostring(event.sequence))
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
    local hadControls = #(BridgeState.preparedSpellControlGuids or {}) > 0
    for _, guid in ipairs(BridgeState.preparedSpellControlGuids or {}) do
        BridgeUnregisterPresentationObject(guid)
        local object = BridgeGetLiveObjectByGuid(guid)
        if object ~= nil then
            BridgeSafeObjectCall(object, function(o) o.destruct() end)
        end
    end
    BridgeState.preparedSpellControlGuids = {}
    if hadControls then BridgeAdvancePhysicalPresentationGeneration("prepared-controls-changed") end
end

function BridgeRecoverFromLibraryOrderMismatch(detail)
    local message = tostring(detail or "")
    local isOrderMismatch = string.find(message, "library top order mismatched", 1, true) ~= nil
        or string.find(message, "single-card library top order mismatched", 1, true) ~= nil
    if not isOrderMismatch then return false end

    -- The physical deck is no longer a trustworthy embodiment of Forge's
    -- ordered library. Rebuild it from the current authoritative snapshot;
    -- this also absorbs any consecutive mill transitions into the graveyard.
    -- Do not select a later contained card by name, which would preserve the
    -- wrong order and make the next draw another synchronization failure.
    BridgeLog("[Bridge] library order mismatch; requesting authoritative resync: " .. message)
    BridgeResyncFromAuthoritativeSnapshot("library order mismatch")
    return true
end

function BridgePreparePhysicalCardForPublicZoneMove(object, destinationZone)
    if object == nil or object.tag ~= "Card" then
        return false, "public-zone move requires a physical game card"
    end
    if destinationZone ~= "battlefield" then
        -- Zone transitions clear presentation-only tap orientation before the
        -- object is placed in a public pile. Forge remains authoritative for
        -- the destination and final tapped state.
        BridgeSetPhysicalTapped(object, false)
        if destinationZone == "graveyard" or destinationZone == "library" then
            return true, nil
        end
    end
    -- Graveyard cards are intentionally locked for readable pile presentation.
    -- A later authoritative public-zone transition must unlock that exact card
    -- before TTS can reuse it; Forge's zone change remains the authority.
    local unlocked, unlockError = pcall(function() object.setLock(false) end)
    if not unlocked then
        return false, "could not unlock card for " .. tostring(destinationZone) .. " move: " .. tostring(unlockError)
    end
    return true, nil
end

local function BridgeApplyStructuredCardMoveCore(event)
    if event.cardInstanceId == nil then return false, "structured zone change has no cardInstanceId" end
    BridgeBeginLibraryBatch(event)
    -- When a same-forgeSequence transaction already owns a multi-card
    -- library->graveyard batch, defer other graveyard arrivals (notably the
    -- resolving Mental Note itself) until the owned native Deck exists. This
    -- is a physical ordering fence, not a name-based reconciliation shortcut.
    if event.destinationZone == "graveyard" and event.sourceZone ~= "library"
        and event._bridgeDeferredGraveyardDispatch ~= true then
        if event._bridgeDeferredGraveyardExecutedToken ~= nil then
            return false, "deferred structured graveyard event was already physically executed by owner "
                .. tostring(event._bridgeDeferredGraveyardExecutedToken)
        end
        local deferredTx, deferredBatch = BridgeMutationBatchForLibraryToGraveyardEvent(event)
        if deferredBatch ~= nil and deferredBatch.state ~= "FAILED"
            and deferredBatch.deferredStarted ~= true then
            local sequenceKey = tostring(event.sequence or "")
            if deferredBatch.deferredEventSequenceSet[sequenceKey] ~= true then
                deferredBatch.deferredEventSequenceSet[sequenceKey] = true
                table.insert(deferredBatch.deferredEvents, event)
            end
            -- The outer event transaction must wait for the later owned
            -- dispatch.  Returning synchronous success here only means the
            -- event was enrolled in the graveyard batch, not that its Card
            -- has reached the final native Deck.
            event._bridgePhysicalCompletionPending = true
            event._bridgeDeferredGraveyardOwnerToken = deferredTx.token
            BridgeRecordPhysicalMutationProgress(deferredTx, "DEFERRED_GRAVEYARD_EVENT", sequenceKey)
            BridgeRecordPhysicalMutationJournal({
                token = deferredTx.token, forgeSequence = deferredTx.forgeSequence,
                stage = "DEFERRED_GRAVEYARD_EVENT", eventSequence = event.sequence,
                cardInstanceId = event.cardInstanceId, seatId = event.seatId
            })
            return true, nil
        end
    end
    local seat = BRIDGE_SEATS[event.seatId]
    if seat == nil then return false, "structured zone change has no configured seat" end

    -- Preserve the complete producer descriptor alongside the physical map.
    -- Identity/provenance is authoritative transport data; it is never
    -- reconstructed from the card's display name or from a chosen candidate.
    BridgeState.authoritativeObjectByInstanceId[event.cardInstanceId] = {
        objectId = event.authoritativeObjectId or event.cardInstanceId,
        originObjectId = event.originObjectId,
        copySourceObjectId = event.copySourceObjectId,
        objectKind = event.objectKind,
        isCopy = event.isCopy == true,
        isToken = event.isToken == true,
        isVirtual = event.isVirtual == true,
        materializationPolicy = event.materializationPolicy,
        ownerSeatId = event.ownerSeatId,
        controllerSeatId = event.controllerSeatId,
        battlefieldKind = event.battlefieldKind,
        characteristics = event.characteristics
    }

    local staleMappedGuid = nil
    local attemptedZones = {}
    local resolveError = nil

    local guid = BridgeState.physicalByInstanceId[event.cardInstanceId]
    local object = guid ~= nil and BridgeGetLiveObjectByGuid(guid) or nil
    local contained = BridgeState.physicalContainerByInstanceId[event.cardInstanceId]
    if object == nil and event.sourceZone == "graveyard" and event.destinationZone ~= "graveyard"
        and contained ~= nil then
        if BridgeState.graveyardExtractionActiveBySeatId[event.seatId] == true then
            return true, nil
        end
        BridgeState.graveyardExtractionActiveBySeatId[event.seatId] = true
        local extractionSessionId = BridgeState.eventSessionId
        local extractionGeneration = BridgeState.physicalTransactionGeneration or 0
        local function finishGraveyardExtraction(taken, extractionError)
            if BridgeState.graveyardExtractionActiveBySeatId[event.seatId] ~= true then
                if taken ~= nil then BridgeSafeObjectCall(taken, function(card) card.destruct() end) end
                return
            end
            BridgeState.graveyardExtractionActiveBySeatId[event.seatId] = nil
            if extractionSessionId ~= BridgeState.eventSessionId
                or extractionGeneration ~= (BridgeState.physicalTransactionGeneration or 0) then
                BridgeLog(string.format("[Bridge] stale graveyard extraction completion seat=%s generation=%s instance=%s",
                    tostring(event.seatId), tostring(extractionGeneration), tostring(event.cardInstanceId)))
                return
            end
            if taken == nil then
                BridgeStopOnDesync("contained graveyard extraction failed: " .. tostring(extractionError))
                return
            end
            local takenGuid = BridgeSafeObjectGuid(taken)
            local recorded = BridgeRecordLooseCardIdentity(event.cardInstanceId, takenGuid,
                event.seatId, event.destinationZone)
            if not recorded then
                BridgeStopOnDesync("contained graveyard extraction could not rebind exact Card")
                return
            end
            BridgeApplyStructuredCardMove(event)
        end
        BridgeTakeContainedCardByIdentity(event.cardInstanceId,
            BridgeResolveSeatZoneAnchor(event.seatId, event.destinationZone or "graveyard"), false,
            finishGraveyardExtraction)
        return true, nil
    end
    if guid ~= nil and object == nil then
        staleMappedGuid = guid
        BridgeState.physicalByInstanceId[event.cardInstanceId] = nil
        BridgeState.physicalSeatByGuid[guid] = nil
        BridgeState.physicalZoneByGuid[guid] = nil
        BridgeAdvancePhysicalPresentationGeneration("stale-card-mapping")
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
        BridgeAdvancePhysicalPresentationGeneration("invalid-card-mapping")
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
            if event.destinationZone == "battlefield" then
                local expectedRow = BridgeBattlefieldRowForEvent(event, "creature")
                local priorRow = BridgeState.battlefieldKindByInstanceId[event.cardInstanceId]
                local strandedAtStack = BridgePhysicalObjectAtStackAnchor(object)
                if strandedAtStack then
                    BridgeTracePermanentTransition(
                        "STRUCTURED_MOVE stack->battlefield", event, object, mappedZone,
                        "mapping said battlefield but physical object was at stack anchor")
                end
                if strandedAtStack or priorRow ~= expectedRow then
                    local corrected, correctionError = BridgeMoveToBattlefield(
                        event, object, expectedRow, false)
                    if not corrected then return false, correctionError end
                    BridgeSetPhysicalFaceDown(object, seat, event.faceDown == true)
                    BridgeLog(string.format(
                        "[Bridge] corrected existing battlefield row instance=%s row=%s",
                        tostring(event.cardInstanceId), tostring(expectedRow)))
                    return true, nil
                end
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
        local transactionSessionId = BridgeState.eventSessionId
        local transactionGeneration = BridgeState.physicalTransactionGeneration or 0
        BridgeTtsExecutionBreadcrumb("LIBRARY_EXTRACTION_DISPATCH_ENTER", "library_extraction", event, "event:" .. tostring(event.sequence))
        BridgeQueueLibraryExtraction(event.seatId, function(complete)
            if not BridgePhysicalPresentationIsCurrent(transactionSessionId, transactionGeneration) then complete("stale-presentation"); return end
            if BridgeFindLibraryDeckForSeat(event.seatId) == nil then
                BridgeStopOnDesync(libraryDrawError("physical library deck not found while processing queued extraction"))
                complete()
                return
            end
            BridgeTakeContainedLibraryCardByIdentity(event.cardInstanceId, hand.position, true, function(drawn, takeError)
                if not BridgePhysicalPresentationIsCurrent(transactionSessionId, transactionGeneration) then complete("stale-presentation"); return end
                if drawn == nil then
                    BridgeStopOnDesync(libraryDrawError("contained extraction failed: " .. tostring(takeError)))
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
                -- CRITICAL: Verify card actually enters player's hand before completing.
                -- Library→hand is asynchronous in TTS; setPositionSmooth is not terminal.
                -- Bounded retry (5 frames) to allow hand settlement.
                local verifyRetryCount = 0
                local maxRetries = 5
                local function verifyHandMembership()
                    verifyRetryCount = verifyRetryCount + 1
                    local handObjects, handError = BridgeTryGetSeatHandObjects(event.seatId)
                    if handObjects == nil then
                        if verifyRetryCount < maxRetries then
                            BridgeWaitFrames(verifyHandMembership, 1)
                            return
                        end
                        BridgeStopOnDesync(libraryDrawError("cannot verify hand membership: " .. tostring(handError)))
                        complete()
                        return
                    end
                    -- Check if the exact drawn card GUID is in the player's hand
                    local found = false
                    for _, handObject in ipairs(handObjects) do
                        if BridgeSafeObjectGuid(handObject) == drawnGuid then
                            found = true
                            break
                        end
                    end
                    if found then
                        -- Card is verified in hand; transaction is complete
                        complete()
                        return
                    end
                    if verifyRetryCount < maxRetries then
                        -- Retry bounded times for TTS hand settlement
                        BridgeWaitFrames(verifyHandMembership, 1)
                        return
                    end
                    -- Card never reached the hand despite extraction completion
                    BridgeStopOnDesync(libraryDrawError(
                        "extracted card never entered player hand; cardInstanceId=" .. tostring(event.cardInstanceId)
                        .. " drawnGuid=" .. tostring(drawnGuid)))
                    complete()
                end
                verifyHandMembership()
            end)
        end, {cardInstanceId = event.cardInstanceId, expectedCardName = event.cardName,
            event = event, physicalCompletion = event._bridgePhysicalCompletion})
        BridgeTtsExecutionBreadcrumb("LIBRARY_EXTRACTION_DISPATCH_RETURNED", "library_extraction", event, "event:" .. tostring(event.sequence))
        return true, nil
    end

    local function moveFromLibraryDeckToBattlefield(deck)
        local libraryZone = BridgeGetLiveObjectByGuid(seat.libraryZoneGuid)
        if libraryZone == nil then
            return false, "library zone is unavailable for authoritative library-to-battlefield move"
        end
        local staging = libraryZone.getPosition()
        local transactionSessionId = BridgeState.eventSessionId
        local transactionGeneration = BridgeState.physicalTransactionGeneration or 0
        BridgeTtsExecutionBreadcrumb("LIBRARY_EXTRACTION_DISPATCH_ENTER", "library_extraction", event, "event:" .. tostring(event.sequence))
        BridgeQueueLibraryExtraction(event.seatId, function(complete)
            if not BridgePhysicalPresentationIsCurrent(transactionSessionId, transactionGeneration) then complete("stale-presentation"); return end
            if BridgeFindLibraryDeckForSeat(event.seatId) == nil then
                BridgeStopOnDesync(libraryDrawError("physical library deck not found while processing queued extraction"))
                complete()
                return
            end
            BridgeTakeContainedLibraryCardByIdentity(event.cardInstanceId, {staging.x + 4, staging.y + 2, staging.z}, false,
                function(taken, takeError)
                if not BridgePhysicalPresentationIsCurrent(transactionSessionId, transactionGeneration) then complete("stale-presentation"); return end
                    if taken == nil then
                        BridgeStopOnDesync(libraryDrawError("contained extraction failed: " .. tostring(takeError)))
                        complete()
                        return
                    end
                    if not BridgeRequireArtBearingLibraryCard(taken, event.seatId, event.cardInstanceId) then
                        BridgeStopOnDesync(libraryDrawError("physical library returned an artless normal game card"))
                        complete()
                        return
                    end
                    local row = BridgeBattlefieldRowForEvent(event, "creature")
                    local moved, moveError = BridgeMoveToBattlefield(event, taken, row)
                    if not moved then BridgeStopOnDesync(libraryDrawError(moveError)) end
                    BridgeWaitFrames(complete, 1)
                end)
        end, {cardInstanceId = event.cardInstanceId, expectedCardName = event.cardName,
            event = event, physicalCompletion = event._bridgePhysicalCompletion})
        BridgeTtsExecutionBreadcrumb("LIBRARY_EXTRACTION_DISPATCH_RETURNED", "library_extraction", event, "event:" .. tostring(event.sequence))
        return true, nil
    end

    -- Mill effects are authoritative library -> graveyard transitions. They
    -- must use the same serialized Deck.takeObject path as draws so each
    -- exact physical card is extracted, turned face-up, and placed in the
    -- graveyard before a later queued draw can present the next hand card.
    -- A Deck handle is never itself a card move.
    local function moveFromLibraryDeckToGraveyard(deck)
        local libraryZone = BridgeGetLiveObjectByGuid(seat.libraryZoneGuid)
        if libraryZone == nil then
            return false, "library zone is unavailable for authoritative library-to-graveyard move"
        end
        local staging = libraryZone.getPosition()
        local transactionSessionId = BridgeState.eventSessionId
        local transactionGeneration = BridgeState.physicalTransactionGeneration or 0
        local mutationTx, atomicBatch = BridgeMutationBatchForLibraryToGraveyardEvent(event)
        BridgeTtsExecutionBreadcrumb("LIBRARY_EXTRACTION_DISPATCH_ENTER", "library_extraction", event, "event:" .. tostring(event.sequence))
        BridgeQueueLibraryExtraction(event.seatId, function(complete)
            if not BridgePhysicalPresentationIsCurrent(transactionSessionId, transactionGeneration) then complete("stale-presentation"); return end
            if BridgeFindLibraryDeckForSeat(event.seatId) == nil then
                BridgeStopOnDesync(libraryDrawError("physical library deck not found while processing queued graveyard extraction"))
                complete()
                return
            end
            BridgeTakeContainedLibraryCardByIdentity(event.cardInstanceId, {staging.x + 4, staging.y + 2, staging.z}, false,
                function(taken, takeError)
                if not BridgePhysicalPresentationIsCurrent(transactionSessionId, transactionGeneration) then complete("stale-presentation"); return end
                    if taken == nil then
                        BridgeStopOnDesync(libraryDrawError("contained extraction failed: " .. tostring(takeError)))
                        complete()
                        return
                    end
                    if not BridgeRequireArtBearingLibraryCard(taken, event.seatId, event.cardInstanceId) then
                        BridgeStopOnDesync(libraryDrawError("physical library returned an artless normal game card"))
                        complete()
                        return
                    end
                    if atomicBatch ~= nil then
                        BridgeStageAtomicLibraryToGraveyardMove(mutationTx, atomicBatch, event, taken, complete)
                        return
                    end
                    local moved, moveError = BridgeMoveToGraveyard(event, taken, function(mergeSucceeded, mergeError)
                        if not mergeSucceeded then
                            -- Settlement or reconciliation failed; the
                            -- transaction remains recoverable and desync is
                            -- already latched by the merge owner.
                            return
                        end
                        BridgeTtsExecutionBreadcrumb("FINAL_REPRESENTATION_VERIFY_ENTER", "final_physical_representation", event,
                            "event:" .. tostring(event.sequence))
                        local settled, settleError = BridgeVerifyFinalPhysicalRepresentation(
                            event.cardInstanceId, event.seatId, event.destinationZone)
                        BridgeTtsExecutionBreadcrumb("FINAL_REPRESENTATION_VERIFY_RETURNED", "final_physical_representation", event,
                            "event:" .. tostring(event.sequence))
                        if not settled then
                            BridgeState.resyncLastBlockingPredicate = "missing-public-instance:" .. tostring(event.cardInstanceId)
                            BridgeStopOnDesync(libraryDrawError(settleError))
                            return
                        end
                        complete()
                    end)
                    if not moved then
                        BridgeStopOnDesync(libraryDrawError(moveError))
                        -- Do not retire the physical extraction as success.
                        -- The card has no proven final graveyard embodiment;
                        -- leaving the transaction owned lets recovery inspect
                        -- and repair the exact failed settlement.
                        return
                    end
                    -- Completion is owned by the asynchronous settlement
                    -- callback above; no synchronous success is assumed.
                end)
        end, {cardInstanceId = event.cardInstanceId, expectedCardName = event.cardName,
            event = event, physicalCompletion = event._bridgePhysicalCompletion})
        BridgeTtsExecutionBreadcrumb("LIBRARY_EXTRACTION_DISPATCH_RETURNED", "library_extraction", event, "event:" .. tostring(event.sequence))
        return true, nil
    end

    local function moveFromTokenFetcherToBattlefield()
        local expectedName = BridgeState.cardNameByInstanceId[event.cardInstanceId] or event.cardName
        local row = BridgeBattlefieldRowForEvent(event, "creature")
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

    local function moveFromCopySourceToBattlefield()
        local copySourceObjectId = event.copySourceObjectId or event.originObjectId
        local sourceGuid = copySourceObjectId ~= nil
            and BridgeState.physicalByInstanceId[copySourceObjectId] or nil
        local source = sourceGuid and BridgeGetLiveObjectByGuid(sourceGuid) or nil
        if source == nil or source.tag ~= "Card" or type(source.clone) ~= "function" then
            return false
        end
        local sessionId = BridgeState.eventSessionId
        local epoch = BRIDGE_RUNTIME_EPOCH_LOCAL
        local started, state = BridgeBeginTokenMaterialization(event.cardInstanceId)
        if not started then
            BridgeLog("[Bridge] copy materialization suppressed instance=" .. tostring(event.cardInstanceId)
                .. " state=" .. tostring(state))
            return true
        end
        local cloned = nil
        local ok = pcall(function()
            cloned = source.clone({position = source.getPosition(), rotation = source.getRotation()})
        end)
        if not ok or cloned == nil then
            BridgeState.tokenMaterializationByInstanceId[event.cardInstanceId].state = "FAILED"
            return false
        end
        local moved, moveError = BridgeBindTokenMaterialization(event, cloned,
            BridgeBattlefieldRowForEvent(event, "creature"), sessionId, epoch)
        if not moved then
            BridgeLog("[Bridge] copy materialization deferred instance="
                .. tostring(event.cardInstanceId) .. " reason=" .. tostring(moveError))
            BridgeScheduleSnapshotReconcile("copy materialization deferred")
        end
        return true
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
            deck = BridgeFindLibraryDeckForSeat(event.seatId)
        end
        if deck == nil then
            return false, libraryDrawError(resolveError or "physical library deck not found for authoritative draw")
        end
        return moveFromLibraryDeckToHand(deck)
    end

    if event.sourceZone == "library" and event.destinationZone == "battlefield" and (object == nil or object.tag == "Deck") then
        local deck = object
        if deck == nil then
            deck = BridgeFindLibraryDeckForSeat(event.seatId)
        end
        if deck == nil then
            return false, libraryDrawError(resolveError or "physical library deck not found for authoritative library-to-battlefield move")
        end
        return moveFromLibraryDeckToBattlefield(deck)
    end

    if event.sourceZone == "library" and event.destinationZone == "graveyard" and (object == nil or object.tag == "Deck") then
        local deck = object
        if deck == nil then
            deck = BridgeFindLibraryDeckForSeat(event.seatId)
        end
        if deck == nil then
            return false, libraryDrawError(resolveError or "physical library deck not found for authoritative library-to-graveyard move")
        end
        return moveFromLibraryDeckToGraveyard(deck)
    end

    if object == nil and event.destinationZone == "battlefield"
        and (event.isToken == true or event.sourceZone == "token" or event.sourceZone == "tokens") then
        if event.isCopy == true and moveFromCopySourceToBattlefield() then
            return true, nil
        end
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
            "resolved object is a deck for non-library extraction move",
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
        local prepared, prepareError = BridgePreparePhysicalCardForPublicZoneMove(object, event.destinationZone)
        if not prepared then return false, prepareError end
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
        local row = BridgeBattlefieldRowForEvent(event, "creature")
        local sourcePhysicalZone = BridgeState.physicalZoneByGuid[guid] or event.sourceZone
        if sourcePhysicalZone == "stack" then
            BridgeTracePermanentTransition("STRUCTURED_MOVE stack->battlefield", event, object, sourcePhysicalZone)
        end
        local moved, moveError = BridgeMoveToBattlefield(event, object, row)
        if not moved then return false, moveError end
    elseif event.destinationZone == "stack" then
        object.use_hands = false
        BridgeSetPhysicalFaceDown(object, seat, event.faceDown == true)
        object.setPosition(BRIDGE_STACK_POSITION)
    elseif event.destinationZone == "graveyard" then
        local moved, moveError = BridgeMoveToGraveyard(event, object, event._bridgePhysicalCompletion)
        if not moved then return false, moveError end
    elseif event.destinationZone == "exile" then
        object.use_hands = false
        BridgeSetPhysicalTapped(object, false)
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
            local transactionSessionId = BridgeState.eventSessionId
            local transactionGeneration = BridgeState.physicalTransactionGeneration or 0
            BridgeInsertPhysicalCardIntoLibrary(event.seatId, object, "NORMAL", function(inserted, insertError, containingDeck, containedGuid)
                if not BridgePhysicalPresentationIsCurrent(transactionSessionId, transactionGeneration) then
                    BridgeLog("[Bridge] ignored stale library insertion callback event=" .. tostring(event.sequence)
                        .. " generation=" .. tostring(transactionGeneration))
                    return
                end
                if not inserted then
                    BridgeStopOnDesync(BridgePhysicalMappingError(
                        event, "library", 0,
                        "authoritative library move was not physically contained: " .. tostring(insertError),
                        {mappedGuid = guid}))
                    return
                end
                -- The exact loose GUID is retired only after Deck.getObjects()
                -- proves that TTS absorbed this card.
                BridgeRecordLibraryContainedState(event.cardInstanceId, event.seatId, event.cardName,
                    containingDeck, containedGuid)
            end, event.cardInstanceId)
        end
        return true, nil
    end

    BridgeRecordLooseCardIdentity(event.cardInstanceId, guid, event.seatId, event.destinationZone)
    return true, nil
end

-- Only the successful completion of an exact structured stack departure may
-- retire its pending-cast and semantic-resolution ownership.  This uses only
-- stable Lua scalars; the native Card userdata may already have been replaced
-- by a Deck by the time an asynchronous graveyard callback settles.
function BridgeFinalizeStructuredStackDeparture(event, completionReason)
    if event == nil or event.cardInstanceId == nil or event.seatId == nil
        or event.sourceZone ~= "stack" or event.destinationZone == "stack" then
        return false
    end
    local retiredCast = false
    local pending = (BridgeState.pendingCastBySeatId or {})[event.seatId]
    if pending ~= nil and pending.cardInstanceId == event.cardInstanceId then
        BridgeState.pendingCastBySeatId[event.seatId] = nil
        retiredCast = true
    end
    local retiredSemantic = false
    if BridgeState.pendingSemanticResolutionByInstanceId ~= nil
        and BridgeState.pendingSemanticResolutionByInstanceId[event.cardInstanceId] ~= nil then
        BridgeState.pendingSemanticResolutionByInstanceId[event.cardInstanceId] = nil
        retiredSemantic = true
    end
    if retiredCast or retiredSemantic then
        BridgeLog("[Bridge] structured stack ownership retired event="
            .. tostring(event.sequence) .. " instance=" .. tostring(event.cardInstanceId)
            .. " seat=" .. tostring(event.seatId)
            .. " destination=" .. tostring(event.destinationZone)
            .. " pendingCast=" .. tostring(retiredCast)
            .. " semanticResolution=" .. tostring(retiredSemantic)
            .. " reason=" .. tostring(completionReason or "physical completion"))
    end
    return retiredCast or retiredSemantic
end

function BridgeApplyStructuredCardMove(event)
    local operationId = "event:" .. tostring(event and event.sequence or "unknown")
    BridgeTtsExecutionBreadcrumb("STRUCTURED_CARD_MOVE_ENTER", "structured_card_move", event, operationId)
    local ok, err = BridgeApplyStructuredCardMoveCore(event)
    -- Correlation identity is immutable across the synchronous call. Encoding
    -- the outcome into RETURNED's operationId left every ENTER open forever in
    -- the bridge watchdog even though Core returned within milliseconds.
    BridgeTtsExecutionBreadcrumb("STRUCTURED_CARD_MOVE_RETURNED", "structured_card_move", event, operationId)
    BridgeLog(string.format("[Bridge] STRUCTURED_CARD_MOVE_RESULT operationId=%s ok=%s error=%s",
        tostring(operationId), tostring(ok), tostring(err)))
    -- Normal event-drain calls install a transaction-owned completion callback
    -- before reaching this function.  A direct synchronous structured move
    -- (used by narrow presentation callers and tests) has no such callback,
    -- so its non-graveyard physical operation is already the success point.
    -- Graveyard moves are deliberately excluded: Card -> Deck settlement is
    -- asynchronous and must retire stack ownership only from that callback.
    if ok == true and event ~= nil and event._bridgePhysicalCompletion == nil
        and event.destinationZone ~= "graveyard" then
        BridgeFinalizeStructuredStackDeparture(event, "direct structured move")
    end
    return ok, err
end

function BridgeFindGraveyardContainer(seatId, excludeGuid, allowMappedOffAnchorFallback)
    local seat = BRIDGE_SEATS[seatId]
    if seat == nil then return nil end
    local anchor = BridgeResolveSeatZoneAnchor(seatId, "graveyard")
    local library = BridgeResolveSeatLibraryDeck(seatId)
    local libraryGuid = library and BridgeSafeObjectGuid(library) or nil
    local fallback = nil

    -- A singleton graveyard card can remain authoritative even when the seat
    -- anchor has not yet been recreated for this turn or the object is still in
    -- a transient unanchored state. The exact mapping is stronger than a mere
    -- spatial proximity heuristic.
    for guid, mappedSeat in pairs(BridgeState.physicalSeatByGuid or {}) do
        if tostring(mappedSeat) == tostring(seatId)
            and tostring(BridgeState.physicalZoneByGuid[guid] or "") == "graveyard"
            and tostring(guid) ~= tostring(excludeGuid)
            and tostring(guid) ~= tostring(libraryGuid) then
            local candidate = BridgeGetLiveObjectByGuid ~= nil and BridgeGetLiveObjectByGuid(guid) or nil
            if BridgeObjectIsUsable(candidate) and candidate.tag == "Card" then
                if anchor == nil or BridgeObjectNearSeatZone(candidate, seatId, "graveyard") then
                    return candidate
                end
                if allowMappedOffAnchorFallback == true or BridgeState.resyncInFlight == true then
                    fallback = candidate
                end
            end
        end
    end

    for _, candidate in ipairs(getAllObjects()) do
        if BridgeObjectIsUsable(candidate) and candidate ~= nil then
            local guid = BridgeSafeObjectGuid(candidate)
            if guid ~= excludeGuid and guid ~= libraryGuid
                and not BridgeIsPresentationOnlyObject(candidate) then
                if candidate.tag == "Deck" then
                    if BridgeDeckContainsTrackedCardForSeat(candidate, seatId)
                        or (anchor ~= nil and BridgeObjectNearSeatZone(candidate, seatId, "graveyard")) then
                        return candidate
                    end
                elseif candidate.tag == "Card"
                    and BridgeState.physicalSeatByGuid[guid] == seatId
                    and BridgeState.physicalZoneByGuid[guid] == "graveyard" then
                    if anchor == nil or BridgeObjectNearSeatZone(candidate, seatId, "graveyard") then
                        return candidate
                    end
                    if fallback == nil and (allowMappedOffAnchorFallback == true or BridgeState.resyncInFlight == true) then
                        fallback = candidate
                    end
                end
            end
        end
    end
    return fallback
end

-- Diagnostic utility: Count entries in a Lua table
function BridgeTableSize(t)
    if t == nil then return 0 end
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

-- Object-shape assertion: Validate graveyard container invariants.
-- Returns (success: bool, errorDescription: string or nil).
-- Violations checked:
--   - TWO_OR_MORE_LOOSE_CARDS: >= 2 loose Cards (critical C11D regression)
--   - MULTIPLE_DECKS: >= 2 Deck objects
--   - LOOSE_CARD_WITH_DECK: >= 1 loose Card AND >= 1 Deck (mixed state)
--   - UNMAPPED_CONTAINED_CARDS: Deck contains Cards not in identity mapping
function BridgeAssertGraveyardObjectShape(seatId, context, containmentOwner)
    if seatId == nil then return true, nil end
    context = context or "unnamed"

    local looseCards = 0
    local deckObjects = 0
    local deckGuids = {}

    for _, object in ipairs(getAllObjects()) do
        local guid = BridgeSafeObjectGuid(object)
        if BridgeObjectIsUsable(object) and guid ~= nil
            and not BridgeIsPresentationOnlyObject(object)
            and BridgeState.physicalSeatByGuid[guid] == seatId
            and BridgeState.physicalZoneByGuid[guid] == "graveyard" then

            if object.tag == "Card" then
                local aliasProven = false
                if BridgePhysicalContainmentAliasIsProven ~= nil then
                    aliasProven = BridgePhysicalContainmentAliasIsProven(
                        guid, seatId, "graveyard", containmentOwner) == true
                end
                if not aliasProven then looseCards = looseCards + 1 end
            elseif object.tag == "Deck" then
                deckObjects = deckObjects + 1
                table.insert(deckGuids, guid)
            end
        end
    end

    -- Check for critical violations
    if looseCards >= 2 then
        return false, string.format("[%s] TWO_OR_MORE_LOOSE_CARDS: seatId=%s found %d loose Cards (invariant: 0 or 1)",
            context, tostring(seatId), looseCards)
    end
    if deckObjects >= 2 then
        return false, string.format("[%s] MULTIPLE_DECKS: seatId=%s found %d Deck objects (invariant: 0 or 1)",
            context, tostring(seatId), deckObjects)
    end
    if looseCards >= 1 and deckObjects >= 1 then
        return false, string.format("[%s] LOOSE_CARD_WITH_DECK: seatId=%s has both loose Card and Deck (mixed state)",
            context, tostring(seatId))
    end

    -- Check for unmapped contained Cards in Deck
    for _, deckGuid in ipairs(deckGuids) do
        local deck = getObjectFromGUID(deckGuid)
        if BridgeObjectIsUsable(deck) and deck.tag == "Deck" then
            local entries = BridgeLibraryEntries(deck)
            if entries ~= nil then
                for _, entry in ipairs(entries) do
                    local cardGuid = entry and (entry.guid or entry.GUID) or nil
                    if cardGuid ~= nil and BridgeState.physicalContainedInstanceIdByGuid[cardGuid] == nil
                        and BridgeState.physicalInstanceIdByGuid[cardGuid] == nil then
                        return false, string.format("[%s] UNMAPPED_CONTAINED_CARDS: seatId=%s deckGuid=%s contains unmapped cardGuid=%s",
                            context, tostring(seatId), tostring(deckGuid), tostring(cardGuid))
                    end
                end
            end
        end
    end

    return true, nil
end

    -- After putObject() merge completes, TTS may assign a new contained GUID to
    -- the incoming card. Existing contained GUIDs are authoritative when they
    -- are still present; any remaining entry is assigned only from the exact
    -- authoritative instance set supplied by the serialized move. Printed
    -- names are deliberately not used to identify a Forge instance.
function BridgeRecordGraveyardContainerEntries(seatId, deck, expectedInstances)
    if not BridgeObjectIsUsable(deck) or deck.tag ~= "Deck" then return false end
    local entries = BridgeLibraryEntries(deck)
    if entries == nil then return false end
    local deckGuid = BridgeSafeObjectGuid(deck)

    -- A merge transaction carries the complete authoritative set in the
    -- native Deck order. Rebind every observed contained GUID by that exact
    -- transaction position. This is deliberately independent of stale GUID
    -- inverses and printed names, both of which can be invalid after
    -- Card->Deck/Deck.putObject reassignment.
    if expectedInstances ~= nil then
        local expectedCount = BridgeTableSize(expectedInstances)
        if expectedCount ~= #entries then
            BridgeState.lastGraveyardRebindFailure = "index-count:entries=" .. tostring(#entries)
                .. ":expected=" .. tostring(expectedCount)
            return false
        end
        -- TTS Deck.getObjects() returns a Lua array, but its per-entry
        -- `index` is the native Deck position and is zero-based in live TTS.
        -- Treating that value as a Lua array key discards position zero,
        -- shifts every remaining identity, and can then try to bind a known
        -- contained GUID to the wrong Forge instance.  Mental Note's
        -- [library -> graveyard, library -> graveyard, stack -> graveyard]
        -- mutation exposed exactly that shape: three valid entries, but the
        -- first native position was skipped during rebind.
        --
        -- Either normalize a complete native index set or preserve the Lua
        -- inventory order when no native indices are available.  A partial or
        -- ambiguous index set is not identity evidence, so fail closed rather
        -- than guessing a Forge binding.
        local ordered = {}
        local indexedCount = 0
        local hasZeroIndex = false
        for _, entry in ipairs(entries) do
            local inventoryIndex = tonumber(entry and entry.index or nil)
            if inventoryIndex ~= nil then
                indexedCount = indexedCount + 1
                if inventoryIndex == 0 then hasZeroIndex = true end
            end
        end
        if indexedCount ~= 0 and indexedCount ~= #entries then
            BridgeState.lastGraveyardRebindFailure = "partial-native-index:entries="
                .. tostring(#entries) .. ":indexed=" .. tostring(indexedCount)
            return false
        end
        for sourceIndex, entry in ipairs(entries) do
            local orderedIndex = sourceIndex
            if indexedCount == #entries then
                local inventoryIndex = tonumber(entry and entry.index or nil)
                orderedIndex = hasZeroIndex and (inventoryIndex + 1) or inventoryIndex
            end
            if orderedIndex == nil or orderedIndex < 1 or orderedIndex > #entries
                or ordered[orderedIndex] ~= nil then
                BridgeState.lastGraveyardRebindFailure = "invalid-native-index:source="
                    .. tostring(sourceIndex) .. ":index=" .. tostring(entry and entry.index or nil)
                return false
            end
            ordered[orderedIndex] = entry
        end
        for index = 1, #entries do
            local entry = ordered[index] or entries[index]
            local guid = entry and (entry.guid or entry.GUID) or nil
            local pair = expectedInstances[index]
            local expectedInstanceId = pair and (pair.instanceId or pair[1]) or nil
            local expectedCardName = pair and (pair.cardName or pair[2]) or nil
            if guid == nil or pair == nil or expectedInstanceId == nil then
                BridgeState.lastGraveyardRebindFailure = "index=" .. tostring(index)
                    .. ":guid=" .. tostring(guid) .. ":instance=" .. tostring(expectedInstanceId)
                return false
            end
            if not BridgeRecordContainedCardIdentity(expectedInstanceId, deckGuid, guid,
                    seatId, "graveyard", expectedCardName) then
                BridgeState.lastGraveyardRebindFailure = "index=" .. tostring(index)
                    .. ":guid=" .. tostring(guid) .. ":instance=" .. tostring(expectedInstanceId)
                return false
            end
        end
        return true
    end
    local recorded = 0

    -- expectedInstances: table of {instanceId, cardName} pairs, or nil for no expected instances
    local expectedByIndex = {}
    local matchedInstances = {}
    if expectedInstances ~= nil then
        for _, pair in ipairs(expectedInstances) do
            local instanceId = pair[1]
            table.insert(expectedByIndex, instanceId)
        end
    end

    for _, entry in ipairs(entries) do
        local cardGuid = entry and (entry.guid or entry.GUID) or nil
        local entryName = entry and (entry.nickname or entry.name) or nil
        local instanceId = cardGuid and (BridgeState.physicalContainedInstanceIdByGuid[cardGuid]
            or BridgeState.physicalInstanceIdByGuid[cardGuid]) or nil

        -- Pass 1: Try to match by existing GUID first (cards already in container before merge)
        if instanceId ~= nil then
            local cardName = BridgeState.cardNameByInstanceId[instanceId] or entryName
            if BridgeRecordContainedCardIdentity(instanceId, deckGuid, cardGuid,
                seatId, "graveyard", cardName) then
                recorded = recorded + 1
                matchedInstances[instanceId] = true
            end
        else
            -- The serialized operation supplies the exact identities involved.
            -- Remove identities already recovered by contained GUID, then bind
            -- the remaining native entries in their stable Deck order. This is
            -- safe for duplicate printed names because names never participate.
            for _, expectedInstanceId in ipairs(expectedByIndex) do
                if not matchedInstances[expectedInstanceId] then
                    local expectedCardName = BridgeState.cardNameByInstanceId[expectedInstanceId]
                    if BridgeRecordContainedCardIdentity(expectedInstanceId, deckGuid, cardGuid,
                        seatId, "graveyard", expectedCardName) then
                        recorded = recorded + 1
                        matchedInstances[expectedInstanceId] = true
                    end
                    break
                end
            end
        end
    end
    return recorded == #entries
end

-- TTS's native putObject is the graveyard presentation boundary. A one-card
-- graveyard remains a loose Card; adding a second card promotes it to a Deck,
-- and all subsequent cards enter that same Deck at its authoritative top.

-- Verify that a native Deck's contained GUID inventory has stabilized after putObject().
-- TTS Card→Deck merges assign new contained GUIDs asynchronously; we must not
-- attempt reconciliation until the inventory is provably stable.
-- Returns: (stable, stableError) where stable is bool.
function BridgeVerifyGraveyardDeckSettlement(deck, maxRetries, callback, sampleObserver)
    -- This operation is asynchronous.  A scheduled frame does not suspend
    -- Lua, so never return the result of checkStable() to the caller.
    local finished = false
    local retryCount = 0
    local lastInventory = nil
    maxRetries = maxRetries or 5

    local function finish(ok, reason, inventory)
        if finished then return end
        finished = true
        if callback ~= nil then callback(ok, reason, inventory) end
    end

    if BridgeSafeObjectTag(deck) ~= "Deck" then
        finish(false, "target is not a usable Deck")
        return
    end

    local function checkStable()
        -- This is deliberately a *narrow* protected boundary around a native
        -- Deck settlement callback. The Deck may have been promoted, absorbed,
        -- or replaced since the previous frame. Report that owned physical
        -- failure to the caller; never let it escape Lua and orphan the event
        -- transaction's animation fence.
        local ok, callbackError = xpcall(function()
            if finished then return end
            if BridgeSafeObjectTag(deck) ~= "Deck" then
                finish(false, "target Deck became unavailable during settlement")
                return
            end
            retryCount = retryCount + 1
            local entries = BridgeLibraryEntries(deck)
            if entries == nil then
                finish(false, "could not read Deck inventory at retry " .. tostring(retryCount))
                return
            end
            local inventory = {}
            for _, entry in ipairs(entries) do
                local guid = entry and (entry.guid or entry.GUID) or nil
                if guid == nil then
                    finish(false, "Deck inventory contained an entry without a GUID")
                    return
                end
                table.insert(inventory, tostring(guid))
            end
            if sampleObserver ~= nil then
                pcall(sampleObserver, retryCount, inventory, lastInventory, maxRetries)
            end
            local stable = lastInventory ~= nil and #lastInventory == #inventory
            if stable then
                for index, guid in ipairs(inventory) do
                    if lastInventory[index] ~= guid then stable = false; break end
                end
            end
            if stable then
                finish(true, nil, inventory)
                return
            end
            lastInventory = inventory
            if retryCount >= maxRetries then
                finish(false, "contained GUID inventory did not stabilize after " .. tostring(maxRetries) .. " observations", inventory)
                return
            end
            BridgeWaitFrames(checkStable, 1)
        end, function(error) return tostring(error) end)
        if not ok then
            finish(false, "native Deck settlement callback exception: " .. tostring(callbackError))
        end
    end
    checkStable()
end

function BridgeEnsureNativeGraveyardContainer(seatId)
    local loose = {}
    local looseInstanceByGuid = {}
    local allExpectedInstances = {}

    for _, object in ipairs(getAllObjects()) do
        local guid = BridgeSafeObjectGuid(object)
        if BridgeObjectIsUsable(object) and object.tag == "Card" and guid ~= nil
            and not BridgeIsPresentationOnlyObject(object)
            and BridgeState.physicalSeatByGuid[guid] == seatId
            and BridgeState.physicalZoneByGuid[guid] == "graveyard" then
            table.insert(loose, object)
            looseInstanceByGuid[guid] = BridgeState.physicalInstanceIdByGuid[guid]
            local instanceId = looseInstanceByGuid[guid]
            local cardName = BridgeState.cardNameByInstanceId[instanceId]
            table.insert(allExpectedInstances, {instanceId, cardName})
        end
    end

    local container = BridgeFindGraveyardContainer(seatId)
    if container ~= nil and container.tag == "Deck" then
        -- A recovery can find an already-valid native Deck plus one or more
        -- loose Cards from the interrupted mutation.  Reconciliation must
        -- cover the complete physical destination, not just those loose
        -- arrivals. Each putObject(..., 0) prepends its exact Forge instance
        -- before the pre-existing Deck inventory.
        local expectedInstances = BridgeCollectGraveyardExpectedInstances(
            seatId, container, nil, false, false)
        local expectedByInstanceId = {}
        for _, expected in ipairs(expectedInstances or {}) do
            local instanceId = expected and expected.instanceId or nil
            if instanceId ~= nil then expectedByInstanceId[tostring(instanceId)] = true end
        end
        for _, object in ipairs(loose) do
            local guid = BridgeSafeObjectGuid(object)
            local instanceId = looseInstanceByGuid[guid]
            if instanceId == nil or expectedByInstanceId[tostring(instanceId)] == true then
                return false, "cannot recover existing graveyard Deck with untracked or duplicate loose Card guid="
                    .. tostring(guid) .. " instance=" .. tostring(instanceId)
            end
            table.insert(expectedInstances, 1, {
                instanceId = instanceId,
                cardName = BridgeState.cardNameByInstanceId[instanceId]
            })
            expectedByInstanceId[tostring(instanceId)] = true
            local ok = pcall(function() container.putObject(object, 0) end)
            if not ok then return false, "could not merge loose graveyard card into native Deck" end
            BridgeLog(string.format("[Bridge] graveyard container merge seat=%s deckGuid=%s cardGuid=%s",
                tostring(seatId), tostring(BridgeSafeObjectGuid(container)), tostring(guid)))
        end
        return BridgeRecordGraveyardContainerEntries(seatId, container, expectedInstances), nil
    end
    if #loose < 2 then return true, nil end

    -- Rebuild can encounter several loose graveyard Cards after a failed
    -- mutation. A Card is not a dependable native container: asking the
    -- first Card to putObject the next can report success without ever
    -- creating a Deck. Use TTS's group primitive whenever it is available so
    -- manual and automatic recovery use the same formation semantics as the
    -- atomic mill path.
    if type(group) == "function" then
        for _, card in ipairs(loose) do
            pcall(function()
                card.setLock(false)
                card.use_hands = false
            end)
        end
        local groupOk, groupResult = pcall(function() return group(loose) end)
        if not groupOk then return false, "could not group loose graveyard Cards into a native Deck" end
        container = BridgeDeckFromNativeGroupResult(groupResult)
            or BridgeFindGraveyardContainer(seatId)
        if container == nil or container.tag ~= "Deck" then
            return false, "TTS did not produce a native graveyard Deck after grouping Cards"
        end
        BridgeLog(string.format("[Bridge] graveyard container group seat=%s deckGuid=%s cards=%s",
            tostring(seatId), tostring(BridgeSafeObjectGuid(container)), tostring(#loose)))
        local stable = BridgeRecordGraveyardContainerEntries(seatId, container, allExpectedInstances)
        if stable then
            local shapeOk, shapeReason = BridgeAssertGraveyardObjectShape(seatId, "after-container-formation")
            if not shapeOk then
                BridgeLog("[Bridge] CRITICAL graveyard object-shape violation after formation: " .. tostring(shapeReason))
                return false, shapeReason
            end
        end
        return stable, stable and nil or "native graveyard Deck inventory did not preserve exact identities"
    end

    container = loose[1]
    for index = 2, #loose do
        local card = loose[index]
        local cardGuid = BridgeSafeObjectGuid(card)
        local cardInstanceId = looseInstanceByGuid[cardGuid]
        local containerGuidBefore = BridgeSafeObjectGuid(container)
        local containerInstanceId = looseInstanceByGuid[containerGuidBefore]
        local ok, result = pcall(function() return container.putObject(card, 0) end)
        if not ok then return false, "could not promote graveyard Cards into a native Deck" end
        if result ~= nil and result.tag == "Deck" then container = result end
        if container == nil or container.tag ~= "Deck" then
            container = BridgeFindGraveyardContainer(seatId)
        end
        if container == nil or container.tag ~= "Deck" then
            return false, "TTS did not produce a native graveyard Deck after merging Cards"
        end
        local deckGuid = BridgeSafeObjectGuid(container)
        if containerInstanceId ~= nil then
            BridgeRecordContainedCardIdentity(containerInstanceId, deckGuid, containerGuidBefore,
                seatId, "graveyard", BridgeState.cardNameByInstanceId[containerInstanceId])
        end
        if cardInstanceId ~= nil then
            BridgeRecordContainedCardIdentity(cardInstanceId, deckGuid, cardGuid,
                seatId, "graveyard", BridgeState.cardNameByInstanceId[cardInstanceId])
        end
    end

    -- Full reconciliation after all merges complete: pass all expected instances atomically
    local stable = BridgeRecordGraveyardContainerEntries(seatId, container, allExpectedInstances)
    if stable then
        -- P2: Assert object-shape contract after container formation
        local shapeOk, shapeReason = BridgeAssertGraveyardObjectShape(seatId, "after-container-formation")
        if not shapeOk then
            BridgeLog("[Bridge] CRITICAL graveyard object-shape violation after formation: " .. tostring(shapeReason))
            return false, shapeReason
        end
    end
    return stable, stable and nil or "native graveyard Deck inventory did not preserve exact identities"
end

function BridgeCollectGraveyardExpectedInstances(seatId, container, incomingInstanceId, incomingAtTop, includeLooseCards)
    local expected = {}
    local expectedCount = 0
    local seen = {}
    local function addInstance(instanceId)
        if instanceId == nil or seen[tostring(instanceId)] then return end
        local cardName = BridgeState.cardNameByInstanceId[instanceId]
        expectedCount = expectedCount + 1
        expected[expectedCount] = {instanceId = instanceId, cardName = cardName}
        seen[tostring(instanceId)] = true
    end
    local entries = container and BridgeLibraryEntries(container) or nil
    if entries ~= nil then
        for _, entry in ipairs(entries) do
            local guid = entry and (entry.guid or entry.GUID) or nil
            local instanceId = guid and (BridgeState.physicalContainedInstanceIdByGuid[guid]
                or BridgeState.physicalInstanceIdByGuid[guid]) or nil
            addInstance(instanceId)
        end
    else
        local guid = container and BridgeSafeObjectGuid(container) or nil
        local instanceId = guid and BridgeState.physicalInstanceIdByGuid[guid] or nil
        addInstance(instanceId)
    end
    -- The inventory can expose freshly reassigned contained GUIDs before the
    -- inverse index has caught up. The structured ledger remains the
    -- authoritative ownership record, so include every instance already
    -- belonging to this exact seat/zone/Deck as a second pass.
    local deckGuid = container and BridgeSafeObjectGuid(container) or nil
    for instanceId, mapping in pairs(BridgeState.physicalContainerByInstanceId or {}) do
        if mapping.deckGuid == deckGuid and mapping.seatId == seatId
            and mapping.zoneName == "graveyard" then
            addInstance(instanceId)
        end
    end
    if includeLooseCards ~= false then
        for _, object in ipairs(getAllObjects() or {}) do
            if BridgeObjectIsUsable(object) and object.tag == "Card"
                and not BridgeIsPresentationOnlyObject(object) then
                local guid = BridgeSafeObjectGuid(object)
                if guid ~= nil
                    and tostring(BridgeState.physicalSeatByGuid[guid] or "") == tostring(seatId)
                    and tostring(BridgeState.physicalZoneByGuid[guid] or "") == "graveyard" then
                    addInstance(BridgeState.physicalInstanceIdByGuid[guid])
                end
            end
        end
    end
    -- Deck.putObject(card, 0) has a physical ordering contract: the incoming
    -- Card becomes native position zero.  Preserve that fact in the expected
    -- identity sequence before contained GUIDs churn. Appending this identity
    -- after the pre-insert inventory shifts every expected instance during the
    -- later exact rebind (Mental Note: mill two, then resolve itself).
    if incomingInstanceId ~= nil then
        if incomingAtTop == true then
            local incomingName = BridgeState.cardNameByInstanceId[incomingInstanceId]
            local alreadyPresent = seen[tostring(incomingInstanceId)] == true
            if not alreadyPresent then
                for index = expectedCount, 1, -1 do
                    expected[index + 1] = expected[index]
                end
                expected[1] = {instanceId = incomingInstanceId, cardName = incomingName}
                expectedCount = expectedCount + 1
                seen[tostring(incomingInstanceId)] = true
            end
        else
            addInstance(incomingInstanceId)
        end
    end
    return expected
end

function BridgeMoveToGraveyard(event, object, completion)
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
    local guid = BridgeSafeObjectGuid(object)
    if guid == nil then
        return false, "graveyard move source Card became unavailable after native movement"
    end
    -- Do not retire pending stack ownership here.  putObject and native Deck
    -- settlement are asynchronous; the transaction-owned physical completion
    -- callback is the only proof that this exact stack departure succeeded.
    BridgeClearCardDesignationPresentation(event.cardInstanceId, object)
    local existing = BridgeFindGraveyardContainer(event.seatId, guid)
    if existing == nil then
        BridgeRecordLooseCardIdentity(event.cardInstanceId, guid, event.seatId, "graveyard")
        -- P2: Assert object-shape contract for single loose card
        local shapeOk, shapeReason = BridgeAssertGraveyardObjectShape(event.seatId, "after-loose-card")
        if not shapeOk then
            BridgeLog("[Bridge] CRITICAL graveyard object-shape violation for loose card: " .. tostring(shapeReason))
            BridgeStopOnDesync("graveyard object-shape contract violation: " .. tostring(shapeReason))
            return false, shapeReason
        end
        if completion ~= nil then completion(true, nil) end
        return true, nil
    end

    -- putObject(..., 0) makes the incoming resolving spell the native top
    -- (Deck entry index zero), so snapshot the expected identity order before
    -- the merge and include it at that same physical position.
    local expectedInstances = BridgeCollectGraveyardExpectedInstances(
        event.seatId, existing, event.cardInstanceId, true)

    local target = existing
    local containmentOwner = event._bridgeContainmentOwner or {
        token = "graveyard:" .. tostring(BridgeState.eventSessionGeneration or 0)
            .. ":" .. tostring(event.sequence or 0),
        generation = BridgeState.physicalTransactionGeneration or 0,
        operation = "GraveyardMerge",
        provenContainedGuids = {}
    }
    local containmentTransition = BridgeBeginPhysicalContainmentTransition(
        guid, event.seatId, event.sourceZone, target, {
            token = containmentOwner.token,
            operation = "GraveyardMerge",
            cardInstanceId = event.cardInstanceId
        })
    BridgeTtsExecutionBreadcrumb("GRAVEYARD_PUT_OBJECT_ENTER", "graveyard_materialization", event,
        "event:" .. tostring(event.sequence))
    local ok, result = pcall(function() return target.putObject(object, 0) end)
    BridgeTtsExecutionBreadcrumb("GRAVEYARD_PUT_OBJECT_RETURNED", "graveyard_materialization", event,
        "event:" .. tostring(event.sequence))
    if not ok then return false, "could not add card to native graveyard container: " .. tostring(result) end
    if BridgeSafeObjectTag(result) == "Deck" then target = result end
    if BridgeSafeObjectTag(target) ~= "Deck" then
        target = BridgeFindGraveyardContainer(event.seatId)
    end
    if BridgeSafeObjectTag(target) ~= "Deck" then
        return false, "TTS did not produce a native graveyard Deck for two cards"
    end

    local merge = {
        seatId = event.seatId,
        target = target,
        targetDeckGuid = BridgeSafeObjectGuid(target),
        expectedInstances = expectedInstances,
        eventSequence = event.sequence,
        cardInstanceId = event.cardInstanceId,
        containmentOwner = containmentOwner,
        containmentTransition = containmentTransition,
        generation = BridgeState.physicalTransactionGeneration or 0,
        sessionId = BridgeState.eventSessionId
    }
    -- P2: Physical move succeeded; final reconciliation is deferred until
    -- settlement is verified. The context belongs to this callback chain,
    -- never to one global pending slot.
    if completion ~= nil then
        BridgeCompletePendingGraveyardMerge(merge, completion)
    end
    return true, nil
end

-- Complete a deferred graveyard merge after verifying the Deck's contained GUID settlement.
-- Must be called from within an async context (e.g., BridgeWaitTime callback).
-- This separates the physical move (putObject) from final reconciliation, allowing TTS time
-- to settle the Deck's internal GUID structure before we attempt to read/map contained cards.
function BridgeCompletePendingGraveyardMerge(merge, callback)
    if merge == nil then
        if callback then callback(false, "missing graveyard merge context") end
        return
    end
    local finished = false
    local function finish(ok, reason)
        if finished then return end
        finished = true
        if callback then callback(ok, reason) end
    end
    if merge.sessionId ~= BridgeState.eventSessionId
        or merge.generation ~= (BridgeState.physicalTransactionGeneration or 0) then
        finish(false, "stale graveyard merge context")
        return
    end
    local function resolveTargetDeck()
        local target = merge.targetDeckGuid and BridgeGetLiveObjectByGuid(merge.targetDeckGuid) or nil
        if BridgeSafeObjectTag(target) ~= "Deck" then
            local discovered = BridgeFindGraveyardContainer(merge.seatId)
            if BridgeSafeObjectTag(discovered) == "Deck" then target = discovered end
        end
        if BridgeSafeObjectTag(target) ~= "Deck" then return nil end
        merge.target = target
        merge.targetDeckGuid = BridgeSafeObjectGuid(target)
        return target
    end
    local target = resolveTargetDeck()
    if target == nil then
        finish(false, "graveyard merge target Deck is unavailable before settlement")
        return
    end
    -- Verify the Deck has settled its contained GUID inventory
    BridgeTtsExecutionBreadcrumb("GRAVEYARD_SETTLEMENT_VERIFY_ENTER", "graveyard_materialization", nil,
        "merge:event" .. tostring(merge.eventSequence))
    BridgeVerifyGraveyardDeckSettlement(target, 5, function(settled, settleError)
        local callbackOk, callbackError = xpcall(function()
        BridgeTtsExecutionBreadcrumb("GRAVEYARD_SETTLEMENT_VERIFY_RETURNED", "graveyard_materialization", nil,
            "merge:event" .. tostring(merge.eventSequence))
        if not settled then
            local reason = "graveyard-settlement:" .. tostring(merge.cardInstanceId) .. ":" .. tostring(settleError)
            BridgeState.resyncLastBlockingPredicate = reason
            BridgeStopOnDesync(reason)
            finish(false, reason)
            return
        end
        local settledTarget = resolveTargetDeck()
        if settledTarget == nil then
            local reason = "graveyard-settlement:" .. tostring(merge.cardInstanceId)
                .. ":target Deck was replaced before reconciliation"
            BridgeState.resyncLastBlockingPredicate = reason
            BridgeStopOnDesync(reason)
            finish(false, reason)
            return
        end
        if not BridgeRecordGraveyardContainerEntries(merge.seatId, settledTarget,
            (BridgeTableSize(merge.expectedInstances or {}) > 0 and merge.expectedInstances or nil)) then
            local reason = "graveyard-reconciliation:" .. tostring(merge.cardInstanceId)
                .. ":entries=" .. tostring(#(BridgeLibraryEntries(settledTarget) or {}))
                .. ":expected=" .. tostring(BridgeTableSize(merge.expectedInstances or {}))
                .. ":rebind=" .. tostring(BridgeState.lastGraveyardRebindFailure)
            BridgeState.resyncLastBlockingPredicate = reason
            BridgeStopOnDesync(reason)
            finish(false, reason)
            return
        end
        if merge.containmentTransition ~= nil then
            merge.containmentTransition.cardInstanceId = merge.cardInstanceId
            BridgeMarkPhysicalContainmentProven(merge.containmentTransition,
                settledTarget, merge.containmentOwner)
        end
        local shapeOk, shapeReason = BridgeAssertGraveyardObjectShape(
            merge.seatId, "after-merge", merge.containmentOwner)
        if not shapeOk then
            local reason = "graveyard-shape:" .. tostring(shapeReason)
            BridgeState.resyncLastBlockingPredicate = reason
            BridgeStopOnDesync(reason)
            finish(false, reason)
            return
        end
        finish(true, nil)
        end, function(error) return tostring(error) end)
        if not callbackOk then
            local reason = "graveyard-merge callback exception:" .. tostring(callbackError)
            BridgeState.lastTtsRuntimeError = {
                stage = "graveyard-merge-settlement", detail = tostring(callbackError),
                sessionId = merge.sessionId, physicalTransactionGeneration = merge.generation,
                eventSequence = merge.eventSequence, transactionToken = merge.token,
                updateTick = tonumber(BridgeState.updateTick or 0) or 0
            }
            BridgeState.resyncLastBlockingPredicate = reason
            BridgeStopOnDesync(reason)
            finish(false, reason)
        end
    end)
end

-- A physical extraction is not complete merely because TTS accepted a move.
-- Native Deck merges can invalidate the loose GUID, so verify the final
-- instance/container mapping after settlement before retiring the worker.
function BridgeVerifyFinalPhysicalRepresentation(instanceId, seatId, zoneName)
    if instanceId == nil then return false, "missing physical instance id" end
    local guid = BridgeState.physicalByInstanceId[instanceId]
    if guid ~= nil
        and BridgeState.physicalSeatByGuid[guid] == seatId
        and BridgeState.physicalZoneByGuid[guid] == zoneName
        and BridgeState.physicalInstanceIdByGuid[guid] == instanceId then
        local object = BridgeGetLiveObjectByGuid(guid)
        if object ~= nil and object.tag == "Card" and BridgeObjectIsUsable(object) then
            return true, nil
        end
    end
    local mapping = BridgeState.physicalContainerByInstanceId[instanceId]
    if mapping == nil then
        return false, "missing final physical representation for " .. tostring(instanceId)
    end
    if mapping.seatId ~= seatId then
        return false, "contained final representation belongs to another seat"
    end
    if mapping.zoneName ~= zoneName then
        return false, "contained final representation is in " .. tostring(mapping.zoneName)
    end
    local container, entry, containmentError = BridgeFindContainedCardEntry(instanceId, zoneName)
    if container == nil then
        return false, "contained final representation is invalid: " .. tostring(containmentError)
    end
    if container.tag ~= "Deck" or not BridgeObjectIsUsable(container) then
        return false, "contained final representation is not a usable native Deck"
    end
    if mapping.locatorType == "GUID_LOCATOR" then
        if mapping.cardGuid == nil or string.match(tostring(mapping.cardGuid), "%S") == nil then
            return false, "contained GUID final representation has no usable GUID"
        end
        if BridgeState.physicalContainedInstanceIdByGuid[mapping.cardGuid] ~= instanceId then
            return false, "contained GUID final representation has no exact inverse identity"
        end
        if BridgeState.physicalSeatByGuid[mapping.cardGuid] ~= seatId
            or BridgeState.physicalZoneByGuid[mapping.cardGuid] ~= zoneName then
            return false, "contained GUID final representation has incorrect seat or zone"
        end
    elseif mapping.locatorType ~= "SLOT_LOCATOR" then
        return false, "contained final representation has unknown locator type"
    end
    return true, nil
end

function BridgeFindSeatLibraryDeckWithCard(seat, expectedName)
    local seatId = BridgeSeatIdForSeatConfig(seat)
    local preferred = seatId and BridgeFindLibraryDeckForSeat(seatId) or nil
    if preferred ~= nil and ((preferred.tag == "Card" and BridgeCardNameMatches(BridgePhysicalCanonicalCardName(preferred), expectedName))
        or BridgeDeckContainsCardName(preferred, expectedName)) then
        return preferred
    end
