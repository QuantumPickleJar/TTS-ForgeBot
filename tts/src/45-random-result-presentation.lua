-- Forge-authoritative random-result presentation.  This is deliberately
-- broader than dice so a future coin renderer can share the barrier.

local function BridgeRandomSettings()
    return BRIDGE_RANDOM_RESULT_PRESENTATION_SETTINGS or {
        readableHoldSeconds = nil, settleSeconds = 0.25,
        settleTimeoutSeconds = 4.0, maxAuthoritativeFaceAttempts = 80,
        extraReturnDelayFrames = 2, dieBagGuids = {}
    }
end

local function BridgeRandomReadableHoldSeconds()
    local configured = BridgeRandomSettings().readableHoldSeconds
    if configured ~= nil then return tonumber(configured) or 0 end
    return BridgePresentationHoldSeconds("random_result")
end

local function BridgeRandomNow()
    return BridgeResyncClockNow ~= nil and BridgeResyncClockNow() or os.clock()
end

local function BridgeRandomDieText(object)
    if object == nil then return "" end
    local name = BridgeSafeObjectName ~= nil and BridgeSafeObjectName(object) or ""
    local description = ""
    pcall(function() description = tostring(object.getDescription() or "") end)
    return string.lower(tostring(name) .. " " .. description)
end

local function BridgeRandomDieSides(object)
    local guid = BridgeSafeObjectGuid(object)
    local configured = nil
    pcall(function()
        configured = BridgeState ~= nil and BridgeState.randomResultDieSidesByGuid
            and BridgeState.randomResultDieSidesByGuid[guid]
    end)
    if configured ~= nil then return tonumber(configured) end
    local text = BridgeRandomDieText(object)
    local sides = string.match(text, "d(%d+)")
        or string.match(text, "(%d+)%s*%-?%s*sided")
        or string.match(text, "die%s*(%d+)")
    return sides ~= nil and tonumber(sides) or nil
end

local function BridgeRandomDieValue(object)
    local ok, value = pcall(function() return object.getRotationValue() end)
    if not ok or value == nil then return nil end
    return tonumber(value)
end

local function BridgeRandomDieMatches(object, sides)
    if not BridgeObjectIsUsable(object) or object.tag ~= "Die" then return false end
    local knownSides = BridgeRandomDieSides(object)
    return knownSides ~= nil and knownSides == tonumber(sides)
end

local function BridgeRandomCandidateIsFree(presentation, guid)
    for _, usedGuid in pairs(presentation.physicalDieGuids or {}) do
        if usedGuid == guid then return false end
    end
    for _, item in ipairs(presentation.dice or {}) do
        if item.guid == guid then return false end
    end
    return true
end

local function BridgeRandomRecord(presentation, stage, reason)
    presentation.stage = stage
    presentation.lastReason = reason
    presentation.lastUpdatedAt = BridgeRandomNow()
    BridgeState.randomResultPresentationDiagnostics = BridgeState.randomResultPresentationDiagnostics or {}
    local diagnostics = BridgeState.randomResultPresentationDiagnostics
    local record = {
        rollGroupId = presentation.rollGroupId,
        eventSequence = presentation.eventSequence,
        seatId = presentation.seatId,
        sides = presentation.sides,
        naturalResults = presentation.naturalResults,
        finalResults = presentation.finalResults,
        physicalDieGuids = presentation.physicalDieGuids,
        stage = stage,
        startedAt = presentation.startedAt,
        settledAt = presentation.settledAt,
        authoritativeFaceEstablishedAt = presentation.authoritativeFaceEstablishedAt,
        holdDuration = presentation.holdDuration,
        completed = presentation.completed == true,
        failed = presentation.failed == true,
        failureReason = presentation.failureReason,
        pendingDependentDecision = BridgeState.pendingDecision and BridgeState.pendingDecision.decisionId or nil,
        pendingEventCursor = BridgeState.pendingDecision and BridgeState.pendingDecision.eventCursor or nil,
        reason = reason
    }
    diagnostics[#diagnostics + 1] = record
    while #diagnostics > 32 do table.remove(diagnostics, 1) end
    BridgeLog(string.format(
        "[Bridge] RANDOM_RESULT stage=%s group=%s event=%s seat=%s sides=%s natural=%s final=%s dice=%s hold=%s reason=%s",
        tostring(stage), tostring(presentation.rollGroupId), tostring(presentation.eventSequence),
        tostring(presentation.seatId), tostring(presentation.sides),
        JSON.encode(presentation.naturalResults or {}), JSON.encode(presentation.finalResults or {}),
        JSON.encode(presentation.physicalDieGuids or {}), tostring(presentation.holdDuration), tostring(reason)))
end

local function BridgeRandomFail(presentation, reason)
    if presentation.finished then return end
    presentation.finished = true
    presentation.failed = true
    presentation.failureReason = tostring(reason or "random-result presentation failed")
    BridgeRandomRecord(presentation, "FAILED", presentation.failureReason)
    BridgeState.activeRandomResultPresentation = nil
    BridgeSetStatus("DICE PRESENTATION FAILED", presentation.failureReason)
    BridgeLog("[Bridge] DICE_ASSET_FAILURE " .. presentation.failureReason)
    if BridgeShowError ~= nil then BridgeShowError(presentation.failureReason) end
    if presentation.event ~= nil and presentation.event._bridgePhysicalCompletion ~= nil then
        presentation.event._bridgePhysicalCompletion(false, presentation.failureReason)
    end
end

local function BridgeRandomFinish(presentation)
    if presentation.finished then return end
    presentation.finished = true
    presentation.completed = true
    presentation.holdDuration = BridgeRandomReadableHoldSeconds()
    BridgeRandomRecord(presentation, "COMPLETED", "readable hold expired")
    BridgeState.activeRandomResultPresentation = nil
    local values = {}
    for index, result in ipairs(presentation.naturalResults or {}) do
        local final = presentation.finalResults[index] or result
        values[#values + 1] = final == result and tostring(result)
            or tostring(result) .. " -> " .. tostring(final)
    end
    BridgeSetStatus("DICE RESULT", table.concat(values, ", "))
    if presentation.event ~= nil and presentation.event._bridgePhysicalCompletion ~= nil then
        presentation.event._bridgePhysicalCompletion(true, nil)
    end
end

local function BridgeRandomReturnExtras(presentation)
    for _, item in ipairs(presentation.dice or {}) do
        if item.transient == true and item.sourceBag ~= nil then
            local bag = BridgeGetLiveObjectByGuid(item.sourceBag)
            if BridgeObjectIsUsable(bag) and type(bag.putObject) == "function"
                and BridgeObjectIsUsable(item.object) then
                pcall(function() bag.putObject(item.object) end)
            end
        end
    end
end

local function BridgeRandomHold(presentation)
    if not BridgeRuntimeIsCurrent(presentation.runtimeEpoch)
        or presentation.sessionId ~= BridgeState.eventSessionId
        or presentation.generation ~= BridgeState.randomResultPresentationGeneration then
        return
    end
    BridgeRandomRecord(presentation, "HOLDING_READABLE_RESULT", "authoritative face established")
    BridgeWaitTime(function()
        if not BridgeRuntimeIsCurrent(presentation.runtimeEpoch)
            or presentation.sessionId ~= BridgeState.eventSessionId
            or presentation.generation ~= BridgeState.randomResultPresentationGeneration
            or BridgeState.activeRandomResultPresentation ~= presentation then return end
        BridgeRandomReturnExtras(presentation)
        BridgeRandomFinish(presentation)
    end, BridgeRandomReadableHoldSeconds())
end

local function BridgeRandomEstablishFaces(presentation, index, attempts)
    if presentation.finished then return end
    if not BridgeRuntimeIsCurrent(presentation.runtimeEpoch)
        or presentation.sessionId ~= BridgeState.eventSessionId
        or presentation.generation ~= BridgeState.randomResultPresentationGeneration then return end
    local item = presentation.dice[index]
    if item == nil then
        presentation.authoritativeFaceEstablishedAt = BridgeRandomNow()
        BridgeRandomHold(presentation)
        return
    end
    local current = BridgeRandomDieValue(item.object)
    if current == item.authoritativeResult then
        item.authoritativeFaceEstablishedAt = BridgeRandomNow()
        presentation.authoritativeFaceEstablishedAt = presentation.authoritativeFaceEstablishedAt or item.authoritativeFaceEstablishedAt
        BridgeRandomEstablishFaces(presentation, index + 1, 0)
        return
    end
    local maxAttempts = tonumber(BridgeRandomSettings().maxAuthoritativeFaceAttempts or 80) or 80
    if (attempts or 0) >= maxAttempts
        or BridgeRandomNow() - presentation.startedAt > (tonumber(BridgeRandomSettings().settleTimeoutSeconds or 4) or 4) then
        BridgeRandomFail(presentation, "die " .. tostring(item.guid) .. " could not visibly establish Forge result " .. tostring(item.authoritativeResult))
        return
    end
    local ok, errorMessage = pcall(function() item.object.randomize() end)
    if not ok then
        BridgeRandomFail(presentation, "die " .. tostring(item.guid) .. " randomize failed: " .. tostring(errorMessage))
        return
    end
    BridgeWaitFrames(function()
        BridgeRandomEstablishFaces(presentation, index, (attempts or 0) + 1)
    end, 1)
end

local function BridgeRandomAnimateAndSettle(presentation)
    BridgeRandomRecord(presentation, "ANIMATING", "physical dice allocated")
    for _, item in ipairs(presentation.dice) do
        local ok, errorMessage = pcall(function()
            item.object.setLock(false)
            item.object.randomize()
        end)
        if not ok then
            BridgeRandomFail(presentation, "die " .. tostring(item.guid) .. " animation failed: " .. tostring(errorMessage))
            return
        end
    end
    BridgeWaitTime(function()
        local state = BridgeState
        if BridgeRuntimeIsCurrent == nil or not BridgeRuntimeIsCurrent(presentation.runtimeEpoch)
            or state == nil
            or presentation.sessionId ~= state.eventSessionId
            or presentation.generation ~= state.randomResultPresentationGeneration then return end
        presentation.settledAt = BridgeRandomNow()
        BridgeRandomRecord(presentation, "SETTLED", "bounded physical settle window elapsed")
        BridgeRandomEstablishFaces(presentation, 1, 0)
    end, tonumber(BridgeRandomSettings().settleSeconds or 0.25) or 0.25)
end

local function BridgeRandomTakeFromBag(presentation, bag, entry, callback)
    local guid = entry.guid
    local target = BRIDGE_SEATS[presentation.seatId].battlefieldAnchors.creature
    local ok = pcall(function()
        bag.takeObject({guid = guid, position = {x = target.x, y = target.y + 1, z = target.z}, smooth = false,
            callback_function = function(object)
                local current = BridgeRuntimeIsCurrent(presentation.runtimeEpoch)
                    and presentation.sessionId == BridgeState.eventSessionId
                    and presentation.generation == BridgeState.randomResultPresentationGeneration
                if not current then
                    if BridgeObjectIsUsable(object) and BridgeObjectIsUsable(bag)
                        and type(bag.putObject) == "function" then
                        pcall(function() bag.putObject(object) end)
                    end
                    return
                end
                if not BridgeRandomDieMatches(object, presentation.sides) then
                    callback(nil, "dice bag returned an unavailable or wrong-sided die")
                    return
                end
                local objectGuid = BridgeSafeObjectGuid(object)
                BridgeRegisterPresentationObject(object, "random-result-die")
                callback({object = object, guid = objectGuid, transient = true, sourceBag = BridgeSafeObjectGuid(bag)}, nil)
            end})
    end)
    if not ok then callback(nil, "could not obtain die from existing dice bag") end
end

local function BridgeRandomFindAsset(presentation, callback)
    local seat = BRIDGE_SEATS[presentation.seatId]
    local configured = seat and seat.battlefieldDieGuidBySides and seat.battlefieldDieGuidBySides[presentation.sides]
    if configured ~= nil then
        local object = BridgeGetLiveObjectByGuid(configured)
        if BridgeRandomDieMatches(object, presentation.sides) and BridgeRandomCandidateIsFree(presentation, configured) then
            BridgeRegisterPresentationObject(object, "random-result-die")
            callback({object = object, guid = configured, transient = false}, nil)
            return
        end
    end

    local objects = type(getAllObjects) == "function" and getAllObjects() or {}
    local best, bestDistance = nil, math.huge
    local anchor = seat and seat.battlefieldAnchors and seat.battlefieldAnchors.creature or {x = 0, z = 0}
    for _, object in ipairs(objects) do
        local guid = BridgeSafeObjectGuid(object)
        if guid ~= nil and BridgeRandomDieMatches(object, presentation.sides)
            and BridgeRandomCandidateIsFree(presentation, guid) then
            local position = nil
            pcall(function() position = object.getPosition() end)
            local distance = position and math.abs((position.x or 0) - (anchor.x or 0))
                + math.abs((position.z or 0) - (anchor.z or 0)) or math.huge
            if distance < bestDistance then best, bestDistance = object, distance end
        end
    end
    if best ~= nil then
        local guid = BridgeSafeObjectGuid(best)
        BridgeRegisterPresentationObject(best, "random-result-die")
        callback({object = best, guid = guid, transient = false}, nil)
        return
    end

    local bags = {}
    local configuredBags = BridgeRandomSettings().dieBagGuids or {}
    for _, bagGuid in ipairs(configuredBags) do
        local bag = BridgeGetLiveObjectByGuid(bagGuid)
        if BridgeObjectIsUsable(bag) then bags[#bags + 1] = bag end
    end
    if #bags == 0 then
        for _, object in ipairs(objects) do
            local name = string.lower(BridgeSafeObjectName(object) or "")
            if BridgeObjectIsUsable(object) and object.tag == "Bag"
                and string.find(name, "dice", 1, true) ~= nil then bags[#bags + 1] = object end
        end
    end
    for _, bag in ipairs(bags) do
        local entries = {}
        local inspected = pcall(function() entries = bag.getObjects() or {} end)
        if inspected then
            for _, entry in ipairs(entries) do
                local entryText = string.lower(tostring(entry.name or "") .. " " .. tostring(entry.description or ""))
                if string.find(entryText, "d" .. tostring(presentation.sides), 1, true) ~= nil then
                    BridgeRandomTakeFromBag(presentation, bag, entry, callback)
                    return
                end
            end
        end
    end
    callback(nil, "no existing physical d" .. tostring(presentation.sides) .. " asset is available")
end

local function BridgeRandomAllocate(presentation, index)
    if presentation.finished then return end
    if index > #presentation.naturalResults then
        BridgeRandomAnimateAndSettle(presentation)
        return
    end
    BridgeRandomFindAsset(presentation, function(item, errorMessage)
        if item == nil then BridgeRandomFail(presentation, errorMessage); return end
        item.authoritativeResult = tonumber(presentation.naturalResults[index])
        item.finalResult = tonumber(presentation.finalResults[index] or item.authoritativeResult)
        presentation.dice[index] = item
        presentation.physicalDieGuids[index] = item.guid
        BridgeRandomAllocate(presentation, index + 1)
    end)
end

function BridgeRetireRandomResultPresentations(reason)
    BridgeState.randomResultPresentationGeneration = (BridgeState.randomResultPresentationGeneration or 0) + 1
    local presentation = BridgeState.activeRandomResultPresentation
    if presentation ~= nil then
        presentation.finished = true
        presentation.failed = true
        presentation.failureReason = "retired: " .. tostring(reason or "session boundary")
        BridgeRandomRecord(presentation, "RETIRED", presentation.failureReason)
        BridgeRandomReturnExtras(presentation)
    end
    BridgeState.activeRandomResultPresentation = nil
end

function BridgeStartRandomResultPresentation(event)
    local result = event and event.randomResultPresentation or nil
    if result == nil or result.seatId == nil or BRIDGE_SEATS[result.seatId] == nil then
        return false, 0, "random-result event has no configured seat"
    end
    if tonumber(result.sides or 0) < 2 or type(result.naturalResults) ~= "table" or #result.naturalResults == 0 then
        return false, 0, "random-result event has invalid sides or natural results"
    end
    if BridgeState.activeRandomResultPresentation ~= nil then
        BridgeRetireRandomResultPresentations("new random-result event")
    end
    local presentation = {
        event = event,
        eventSequence = event.sequence,
        sessionId = BridgeState.eventSessionId,
        runtimeEpoch = BRIDGE_RUNTIME_EPOCH_LOCAL,
        generation = (BridgeState.randomResultPresentationGeneration or 0) + 1,
        rollGroupId = result.rollGroupId,
        seatId = result.seatId,
        sides = tonumber(result.sides),
        naturalResults = result.naturalResults,
        finalResults = result.finalResults or result.naturalResults,
        isReroll = result.isReroll == true,
        sourceObjectId = result.sourceObjectId,
        sourceName = result.sourceName,
        purpose = result.purpose or "rules/gameplay",
        dice = {}, physicalDieGuids = {}, stage = "STARTED", startedAt = BridgeRandomNow()
    }
    BridgeState.randomResultPresentationGeneration = presentation.generation
    BridgeState.activeRandomResultPresentation = presentation
    event._bridgePhysicalCompletionPending = true
    BridgeRandomRecord(presentation, "ALLOCATING", presentation.isReroll and "reroll" or "authoritative roll")
    BridgeRandomAllocate(presentation, 1)
    return true, 0
end

-- Opponent spell readability shares this file's random-result presentation
-- boundary, but it deliberately has no event-drain barrier.  Forge events,
-- mappings, and decisions continue while a disposable visual proxy lingers.
local BRIDGE_OPPONENT_SPELL_PRESENTATION_CAPACITY = 6

local function BridgeOpponentSpellNow()
    return BridgeResyncClockNow ~= nil and BridgeResyncClockNow() or os.clock()
end

local function BridgeOpponentSpellSeatUsesPresentation(seatId)
    local seat = BRIDGE_SEATS ~= nil and BRIDGE_SEATS[seatId] or nil
    return seat ~= nil and seat.animateAuthoritativeEvents == true
end

local function BridgeOpponentSpellDiagnostic(presentation, stage, reason)
    presentation.stage = stage
    presentation.lastUpdatedAt = BridgeOpponentSpellNow()
    presentation.retirementReason = reason
    local diagnostics = BridgeState.opponentSpellPresentationDiagnostics
        or {}
    BridgeState.opponentSpellPresentationDiagnostics = diagnostics
    local record = {
        presentationId = presentation.presentationId,
        sessionId = presentation.sessionId,
        sourceEventSequence = presentation.sourceEventSequence,
        castEventSequence = presentation.castEventSequence,
        cardInstanceId = presentation.cardInstanceId,
        seatId = presentation.seatId,
        startedAt = presentation.startedAt,
        realObjectDepartureAt = presentation.realObjectDepartureAt,
        expiresAt = presentation.expiresAt,
        proxyGuid = presentation.proxyGuid,
        stage = stage,
        retirementReason = reason,
        active = presentation.finished ~= true,
        completed = presentation.completed == true,
        failed = presentation.failed == true
    }
    table.insert(diagnostics, record)
    while #diagnostics > 32 do table.remove(diagnostics, 1) end
    if BridgeLog ~= nil then
        BridgeLog(string.format(
            "[Bridge] OPPONENT_SPELL_PRESENTATION stage=%s id=%s event=%s cast=%s seat=%s instance=%s proxy=%s expires=%s reason=%s",
            tostring(stage), tostring(presentation.presentationId),
            tostring(presentation.sourceEventSequence), tostring(presentation.castEventSequence),
            tostring(presentation.seatId), tostring(presentation.cardInstanceId),
            tostring(presentation.proxyGuid), tostring(presentation.expiresAt), tostring(reason)))
    end
end

local function BridgeOpponentSpellDestroyProxy(presentation)
    local proxy = presentation.proxyObject
    if proxy ~= nil then
        BridgeUnregisterPresentationProxy(proxy)
        pcall(function()
            if type(proxy.destruct) == "function" then proxy.destruct() end
        end)
    elseif presentation.proxyGuid ~= nil then
        BridgeUnregisterPresentationProxy(presentation.proxyGuid)
    end
    presentation.proxyObject = nil
end

local function BridgeOpponentSpellRemoveActive(presentation)
    BridgeState.opponentSpellPresentationsById[presentation.presentationId] = nil
    for index, candidate in ipairs(BridgeState.opponentSpellPresentationOrder or {}) do
        if candidate == presentation then
            table.remove(BridgeState.opponentSpellPresentationOrder, index)
            break
        end
    end
end

local function BridgeOpponentSpellRetire(presentation, reason)
    if presentation == nil or presentation.finished == true then return end
    presentation.finished = true
    presentation.completed = reason == "hold-expired" or reason == "real-permanent-visible"
    if reason == "hold-expired" then
        BridgeOpponentSpellDiagnostic(presentation, "COMPLETED", reason)
    else
        BridgeOpponentSpellDiagnostic(presentation, "RETIRED", reason)
    end
    BridgeOpponentSpellDestroyProxy(presentation)
    BridgeOpponentSpellRemoveActive(presentation)
end

function BridgeRetireOpponentSpellPresentations(reason)
    BridgeState.opponentSpellPresentationOrder = BridgeState.opponentSpellPresentationOrder or {}
    BridgeState.opponentSpellPresentationsById = BridgeState.opponentSpellPresentationsById or {}
    BridgeState.opponentSpellCastHintsBySeatId = BridgeState.opponentSpellCastHintsBySeatId or {}
    BridgeState.opponentSpellPresentationGeneration =
        (BridgeState.opponentSpellPresentationGeneration or 0) + 1
    local active = {}
    for _, presentation in ipairs(BridgeState.opponentSpellPresentationOrder or {}) do
        table.insert(active, presentation)
    end
    for _, presentation in ipairs(active) do
        BridgeOpponentSpellRetire(presentation, "session-boundary:" .. tostring(reason or "cleanup"))
    end
    BridgeState.opponentSpellPresentationsById = {}
    BridgeState.opponentSpellPresentationOrder = {}
    BridgeState.opponentSpellCastHintsBySeatId = {}
end

local function BridgeOpponentSpellActiveCount()
    BridgeState.opponentSpellPresentationOrder = BridgeState.opponentSpellPresentationOrder or {}
    local count = 0
    for _, presentation in ipairs(BridgeState.opponentSpellPresentationOrder or {}) do
        if presentation.finished ~= true then count = count + 1 end
    end
    return count
end

local function BridgeOpponentSpellEnforceBound()
    while BridgeOpponentSpellActiveCount() > BRIDGE_OPPONENT_SPELL_PRESENTATION_CAPACITY do
        local oldest = BridgeState.opponentSpellPresentationOrder[1]
        if oldest == nil then break end
        BridgeOpponentSpellRetire(oldest, "capacity")
    end
end

local function BridgeOpponentSpellFind(cardInstanceId)
    for _, presentation in pairs(BridgeState.opponentSpellPresentationsById or {}) do
        if presentation.cardInstanceId == cardInstanceId and presentation.finished ~= true then
            return presentation
        end
    end
    return nil
end

local function BridgeOpponentSpellStart(event, startedAt, castEventSequence)
    if event == nil or event.cardInstanceId == nil
        or not BridgeOpponentSpellSeatUsesPresentation(event.seatId) then return nil end
    if event.isVirtual == true or event.materializationPolicy == "virtual"
        or event.objectKind == "virtual" then return nil end
    BridgeState.opponentSpellPresentationsById = BridgeState.opponentSpellPresentationsById or {}
    BridgeState.opponentSpellPresentationOrder = BridgeState.opponentSpellPresentationOrder or {}
    BridgeState.opponentSpellCastHintsBySeatId = BridgeState.opponentSpellCastHintsBySeatId or {}
    local existing = BridgeOpponentSpellFind(event.cardInstanceId)
    if existing ~= nil then return existing end
    local generation = BridgeState.opponentSpellPresentationGeneration or 0
    local presentation = {
        presentationId = tostring(BridgeState.eventSessionId) .. ":"
            .. tostring(event.cardInstanceId) .. ":" .. tostring(castEventSequence or event.sequence or generation),
        sessionId = BridgeState.eventSessionId,
        runtimeEpoch = BRIDGE_RUNTIME_EPOCH_LOCAL,
        generation = generation,
        sourceEventSequence = event.sequence,
        castEventSequence = castEventSequence,
        cardInstanceId = event.cardInstanceId,
        seatId = event.seatId,
        startedAt = startedAt or BridgeOpponentSpellNow(),
        finished = false,
        proxyObject = nil,
        proxyGuid = nil
    }
    BridgeState.opponentSpellPresentationsById[presentation.presentationId] = presentation
    table.insert(BridgeState.opponentSpellPresentationOrder, presentation)
    BridgeOpponentSpellDiagnostic(presentation, "CAST_OBSERVED", "authoritative spell cast")
    BridgeOpponentSpellEnforceBound()
    return presentation
end

function BridgeOpponentSpellObserveCast(event)
    if event == nil or not BridgeOpponentSpellSeatUsesPresentation(event.seatId) then return true end
    if event.cardInstanceId ~= nil then
        BridgeOpponentSpellStart(event, BridgeOpponentSpellNow(), event.sequence)
        return true
    end
    local hints = BridgeState.opponentSpellCastHintsBySeatId[event.seatId] or {}
    BridgeState.opponentSpellCastHintsBySeatId[event.seatId] = hints
    table.insert(hints, {startedAt = BridgeOpponentSpellNow(), castEventSequence = event.sequence})
    while #hints > 8 do table.remove(hints, 1) end
    return true
end

local function BridgeOpponentSpellConsumeHint(seatId)
    local hints = BridgeState.opponentSpellCastHintsBySeatId[seatId] or {}
    if #hints == 0 then return nil end
    local hint = table.remove(hints, 1)
    BridgeState.opponentSpellCastHintsBySeatId[seatId] = hints
    return hint
end

function BridgeOpponentSpellObserveStackEntry(event, object)
    if event == nil or object == nil or not BridgeOpponentSpellSeatUsesPresentation(event.seatId) then return end
    if event.isVirtual == true or event.materializationPolicy == "virtual"
        or event.objectKind == "virtual" then return end
    local hint = BridgeOpponentSpellConsumeHint(event.seatId)
    local presentation = BridgeOpponentSpellStart(event,
        hint and hint.startedAt or BridgeOpponentSpellNow(),
        hint and hint.castEventSequence or event.sequence)
    if presentation == nil then return end
    presentation.realObjectGuid = BridgeSafeObjectGuid(object)
    presentation.sourceEventSequence = event.sequence or presentation.sourceEventSequence
    BridgeOpponentSpellDiagnostic(presentation, "STACK_VISIBLE", "exact physical stack object established")
end

local function BridgeOpponentSpellProxyPosition(presentation)
    local base = BRIDGE_STACK_POSITION or {x = 0, y = 1.6, z = 0}
    local slot = 0
    for index, candidate in ipairs(BridgeState.opponentSpellPresentationOrder or {}) do
        if candidate == presentation then slot = index - 1 break end
    end
    return {
        x = (base.x or 0) + (slot % 3) * 0.65,
        y = (base.y or 1.6) + 0.35,
        z = (base.z or 0) + math.floor(slot / 3) * 0.65
    }
end

local function BridgeOpponentSpellCreateProxy(presentation, object)
    if presentation.proxyObject ~= nil then return true end
    local clone = nil
    local hidden = {x = (BRIDGE_STACK_POSITION and BRIDGE_STACK_POSITION.x or 0), y = -4, z = (BRIDGE_STACK_POSITION and BRIDGE_STACK_POSITION.z or 0)}
    local ok, cloneError = pcall(function() clone = object.clone({position = hidden, smooth = false}) end)
    if not ok or clone == nil then
        BridgeOpponentSpellDiagnostic(presentation, "PROXY_FAILED", tostring(cloneError or "clone returned no object"))
        return false
    end
    BridgeRegisterPresentationProxy(clone, "opponent-spell")
    pcall(function() clone.setVar("bridgeCardInstanceId", nil) end)
    pcall(function() clone.setVar("bridgeSessionId", nil) end)
    pcall(function() clone.clearButtons() end)
    pcall(function() clone.setLock(true) end)
    pcall(function() clone.use_hands = false end)
    pcall(function() clone.interactable = false end)
    pcall(function() clone.setPosition(hidden) end)
    local seat = BRIDGE_SEATS[presentation.seatId]
    pcall(function() clone.setRotation(seat and seat.faceUpRotation or {x = 0, y = 180, z = 0}) end)
    presentation.proxyObject = clone
    presentation.proxyGuid = BridgeSafeObjectGuid(clone)
    return true
end

function BridgeOpponentSpellPrepareDeparture(event, object)
    if event == nil or object == nil or event.sourceZone ~= "stack"
        or not BridgeOpponentSpellSeatUsesPresentation(event.seatId) then return nil end
    local presentation = BridgeOpponentSpellFind(event.cardInstanceId)
    if presentation == nil then presentation = BridgeOpponentSpellStart(event) end
    if presentation == nil then return nil end
    presentation.destinationZone = event.destinationZone
    presentation.realObjectDepartureAt = BridgeOpponentSpellNow()
    local destination = tostring(event.destinationZone or "")
    if destination == "battlefield" then
        BridgeOpponentSpellRetire(presentation, "real-permanent-visible")
        return presentation
    end
    local hold = BridgePresentationHoldSeconds("opponent_spell")
    local remaining = hold - (presentation.realObjectDepartureAt - presentation.startedAt)
    if remaining <= 0 then
        BridgeOpponentSpellRetire(presentation, "hold-already-expired")
        return presentation
    end
    if not BridgeOpponentSpellCreateProxy(presentation, object) then
        presentation.failed = true
        return presentation
    end
    presentation.expiresAt = presentation.realObjectDepartureAt + remaining
    BridgeOpponentSpellDiagnostic(presentation, "PROXY_PENDING", "authoritative object departing")
    return presentation
end

function BridgeOpponentSpellCommitDeparture(presentation, event, moved)
    if presentation == nil or presentation.finished == true then return end
    if moved ~= true then
        BridgeOpponentSpellRetire(presentation, "authoritative departure failed")
        return
    end
    if presentation.proxyObject == nil then return end
    pcall(function() presentation.proxyObject.setPosition(BridgeOpponentSpellProxyPosition(presentation)) end)
    BridgeOpponentSpellDiagnostic(presentation, "PROXY_VISIBLE", "readable presentation proxy shown")
    local epoch = presentation.runtimeEpoch
    local sessionId = presentation.sessionId
    local generation = presentation.generation
    local remaining = math.max(0, (presentation.expiresAt or BridgeOpponentSpellNow()) - BridgeOpponentSpellNow())
    if BridgeWaitTime == nil then return end
    BridgeWaitTime(function()
        if not BridgeRuntimeIsCurrent(epoch)
            or sessionId ~= BridgeState.eventSessionId
            or BridgeState.opponentSpellPresentationGeneration < generation
            or BridgeState.opponentSpellPresentationsById[presentation.presentationId] ~= presentation then return end
        BridgeOpponentSpellRetire(presentation, "hold-expired")
    end, remaining)
end

function BridgeOpponentSpellPresentationDiagnostics()
    local records = {}
    for _, record in ipairs(BridgeState.opponentSpellPresentationDiagnostics or {}) do
        table.insert(records, record)
    end
    return {
        timing = BridgePresentationTimingDiagnostics(),
        activeCount = BridgeOpponentSpellActiveCount(),
        records = records
    }
end
