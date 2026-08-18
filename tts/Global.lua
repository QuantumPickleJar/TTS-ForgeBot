BRIDGE_BASE_URL = "http://127.0.0.1:43110"

BridgeState = {
    lastDecision = nil,
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
        if not ok then
            print("[Bridge] choice rejected: " .. tostring(err))
            if body ~= nil and body.errorCode ~= nil then
                print("[Bridge] errorCode=" .. tostring(body.errorCode) .. " message=" .. tostring(body.message))
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
            print("[Bridge] health failed: " .. tostring(err))
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
                    print("[Bridge] session start failed: " .. tostring(startErr))
                    return
                end

                print("[Bridge] session started: " .. tostring(startBody.sessionId))

                BridgeGetDecision(function(finalOk, finalBody, finalErr)
                    if finalOk then
                        printDecision(finalBody)
                    else
                        print("[Bridge] decision fetch failed: " .. tostring(finalErr))
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
