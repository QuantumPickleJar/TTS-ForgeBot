BRIDGE_BASE_URL = "http://127.0.0.1:43110"

-- Transport seat identity is kept separate from TTS color. Change this table
-- when the TUI-controlled Forge seat is assigned to another physical player.
BRIDGE_SEAT_COLORS = {
    ["forge-player-1"] = "White"
}

BridgeState = {
    lastDecision = nil,
    actionByGuid = {},
    highlightedGuids = {},
    submitting = false,
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
    createBridgeSmokeButton()
    print("[Bridge] Global loaded. Click Bridge Smoke or run BridgeSmokeTest().")
end

function createBridgeSmokeButton()
    self.createButton({
        click_function = "BridgeSmokeTest",
        function_owner = self,
        label = "Bridge Smoke",
        position = {0, 0.3, 0},
        rotation = {0, 180, 0},
        width = 2000,
        height = 500,
        font_size = 250,
        tooltip = "Health + decision smoke test"
    })
end

function BridgeGetHealth(callback)
    BridgeHttp.requestJson("GET", "/health", nil, callback)
end

function BridgeStartSession(callback)
    BridgeHttp.requestJson("POST", "/api/v1/session/start", nil, callback)
end

function BridgeGetDecision(callback)
    BridgeHttp.requestJson("GET", "/api/v1/decision", nil, function(ok, body, err, request)
        if ok and body ~= nil then
            BridgeState.lastDecision = body
        else
            BridgeClearHighlights()
        end

        callback(ok, body, err, request)
    end)
end

function BridgeSubmitChoice(decisionId, actionId)
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

    BridgeHttp.requestJson("POST", "/api/v1/choice", payload, function(ok, body, err)
        BridgeState.submitting = false
        if not ok then
            BridgeClearHighlights()
            BridgeShowError("choice rejected: " .. tostring(err))
            if body ~= nil and body.errorCode ~= nil then
                BridgeShowError("errorCode=" .. tostring(body.errorCode) .. " message=" .. tostring(body.message))
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

function BridgeSmokeTest()
    BridgeGetHealth(function(ok, body, err)
        if not ok then
            BridgeClearHighlights()
            BridgeShowError("health failed: " .. tostring(err))
            return
        end

        print("[Bridge] health ok. adapter=" .. tostring(body.adapter) .. " state=" .. tostring(body.adapterState))

        BridgeGetDecision(function(decisionOk, decisionBody)
            if decisionOk then
                printDecision(decisionBody)
                return
            end

            print("[Bridge] no active decision, starting session.")
            BridgeStartSession(function(startOk, startBody, startErr)
                if not startOk then
                    BridgeClearHighlights()
                    BridgeShowError("session start failed: " .. tostring(startErr))
                    return
                end

                print("[Bridge] session started: " .. tostring(startBody.sessionId))

                BridgeGetDecision(function(finalOk, finalBody, finalErr)
                    if finalOk then
                        printDecision(finalBody)
                    else
                        BridgeClearHighlights()
                        BridgeShowError("decision fetch failed: " .. tostring(finalErr))
                    end
                end)
            end)
        end)
    end)
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

function BridgeClearHighlights()
    for _, guid in ipairs(BridgeState.highlightedGuids) do
        local object = getObjectFromGUID(guid)
        if object ~= nil then
            object.highlightOff()
        end
    end

    BridgeState.highlightedGuids = {}
    BridgeState.actionByGuid = {}
end

function BridgeRenderDecision(decision)
    BridgeClearHighlights()

    if decision == nil or decision.actions == nil then
        return
    end

    local highlightColor = {0.53, 0.81, 0.98}
    if decision.kind == "target_selection" then
        highlightColor = {1.0, 0.55, 0.0}
    end

    local cardsByName = {}
    for _, object in ipairs(getAllObjects()) do
        if object.tag == "Card" then
            local normalizedName = BridgeNormalizeCardName(object.getName())
            if normalizedName ~= "" then
                cardsByName[normalizedName] = cardsByName[normalizedName] or {}
                table.insert(cardsByName[normalizedName], object)
            end
        end
    end

    for _, action in ipairs(decision.actions) do
        local normalizedIdentity = BridgeNormalizeCardName(action.cardIdentity)
        local matches = cardsByName[normalizedIdentity]
        if normalizedIdentity ~= "" and matches ~= nil then
            if #matches > 1 then
                print(string.format("[Bridge] duplicate card name '%s': highlighting all %d candidates", tostring(action.cardIdentity), #matches))
            end

            for _, object in ipairs(matches) do
                local guid = object.getGUID()
                object.highlightOn(highlightColor)
                BridgeState.actionByGuid[guid] = action.actionId
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

    local actionId = BridgeState.actionByGuid[object.getGUID()]
    if actionId == nil then
        return
    end

    local decision = BridgeState.lastDecision
    if decision == nil then
        BridgeClearHighlights()
        BridgeShowError("highlighted card has no active bridge decision")
        return
    end

    local expectedColor = BRIDGE_SEAT_COLORS[decision.seatId]
    if expectedColor ~= nil and expectedColor ~= playerColor then
        BridgeShowError("this decision belongs to TTS color " .. tostring(expectedColor))
        return
    end

    BridgeState.submitting = true
    BridgeClearHighlights()
    BridgeSubmitChoice(decision.decisionId, actionId)
end
