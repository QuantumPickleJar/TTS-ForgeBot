-- Forge-authoritative random-result presentation.  This is deliberately
-- broader than dice so a future coin renderer can share the barrier.

local function BridgeRandomSettings()
    return BRIDGE_RANDOM_RESULT_PRESENTATION_SETTINGS or {
        readableHoldSeconds = 1.5, settleSeconds = 0.25,
        settleTimeoutSeconds = 4.0, maxAuthoritativeFaceAttempts = 80,
        extraReturnDelayFrames = 2, dieBagGuids = {}
    }
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
    presentation.holdDuration = BridgeRandomSettings().readableHoldSeconds
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
    end, BridgeRandomSettings().readableHoldSeconds)
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
