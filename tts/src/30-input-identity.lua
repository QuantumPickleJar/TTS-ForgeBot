
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
    BridgeArmYieldPolicy(BridgeState.currentTurnSeatId, decision == nil and "physical-yield-no-decision" or "physical-yield")
    if decision ~= nil then BridgeRenderDecision(decision, true) end
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
    BridgeUiMarkDirty("cast-preview")
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
    BridgeUiMarkDirty("cast-preview-confirm")
    BridgeSubmitChoice(intent.decisionId, intent.action.actionId, "cast_confirm")
end

function BridgeCancelCastPreview(object, playerColor, altClick)
    local decision = BridgeState.lastDecision
    BridgeClearPendingIntentControls()
    BridgeRollbackPendingIntent()
    BridgeUiMarkDirty("cast-preview-cancel")
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

function BridgeDecisionPresentationKey(decision)
    if decision == nil then return "decision:<nil>" end

    local parts = {}
    local function add(name, value)
        local text = value == nil and "<nil>" or tostring(value)
        table.insert(parts, name .. "=" .. tostring(#text) .. ":" .. text)
    end

    for _, name in ipairs({
        "decisionId", "kind", "seatId", "selectedCount", "minSelections", "maxSelections",
        "confirmRequired", "requiresConfirmation", "allowsCancel", "selectionKind", "costKind",
        "mulliganStage", "requiredTotalPower", "selectedTotalPower", "phaseName", "prioritySeatId",
        "activeSeatId", "prompt", "contextCardName", "decisionCauseKind", "sourceCardInstanceId",
        "sourceCardName", "turnNumber"
    }) do
        add(name, decision[name])
    end

    add("actionCount", #(decision.actions or {}))
    for index, action in ipairs(decision.actions or {}) do
        add("action[" .. tostring(index) .. "]", table.concat({
            tostring(action.actionId or "<nil>"),
            tostring(action.type or "<nil>"),
            tostring(action.actionKind or "<nil>"),
            tostring(action.cardInstanceId or "<nil>"),
            tostring(action.preparedSourceCardInstanceId or "<nil>"),
            tostring(action.sourceCardInstanceId or "<nil>"),
            tostring(action.cardIdentity or "<nil>"),
            tostring(action.sourceCardName or "<nil>"),
            tostring(action.sourceZone or "<nil>"),
            tostring(action.targetKind or "<nil>"),
            tostring(action.targetSeatId or "<nil>"),
            tostring(action.isSelected),
            tostring(action.displayName or "<nil>"),
            tostring(action.shortLabel or "<nil>"),
            tostring(action.displayManaCost or "<nil>"),
            tostring(action.castMode or "<nil>"),
            tostring(action.requiresFollowup),
            tostring(action.requiresSelection),
            tostring(action.isGraveyardFolder)
        }, "\31"))
    end
    return table.concat(parts, "\30")
end

function BridgeRecordDecisionPresentationRendered(key)
    BridgeState.renderedDecisionPresentationKey = key
    BridgeState.renderedDecisionPhysicalGeneration =
        BridgeState.currentPhysicalPresentationGeneration or 0
end

function BridgeDecisionPhysicalMappingsReady(decision)
    if decision == nil then return true, nil end
    for _, action in ipairs(decision.actions or {}) do
        local instanceId = action.preparedSourceCardInstanceId or action.sourceCardInstanceId or action.cardInstanceId
        if instanceId ~= nil then
            local descriptor = BridgeState.authoritativeObjectByInstanceId[instanceId]
            local policy = descriptor and tostring(descriptor.materializationPolicy or "") or ""
            local physicalRequired = descriptor == nil
                or (descriptor.isVirtual ~= true and policy ~= "virtual" and policy ~= "virtual-stack")
            if physicalRequired then
                local guid = BridgeState.physicalByInstanceId[instanceId]
                local object = guid and BridgeGetLiveObjectByGuid(guid) or nil
                local inverse = guid and BridgeState.physicalInstanceIdByGuid[guid] or nil
                if object == nil or object.tag ~= "Card" or inverse ~= instanceId then
                    return false, instanceId
                end
            end
        end
    end
    return true, nil
end

function BridgeRenderDecision(decision, force)
    if BridgeResolveRevealForDecision ~= nil then BridgeResolveRevealForDecision(decision) end
    BridgePresentationMetric("decisionRenderAttempts")
    BridgeRecordDecisionLifecycle(decision, "render", "RENDER_BEGIN", force == true and "forced" or "normal")
    local key = BridgeDecisionPresentationKey(decision)
    if force ~= true
        and key == BridgeState.renderedDecisionPresentationKey
        and BridgeState.renderedDecisionPhysicalGeneration
            == (BridgeState.currentPhysicalPresentationGeneration or 0) then
        BridgePresentationMetric("decisionRenderSkippedIdentical")
        return
    end
    local mappingsReady, missingInstanceId = BridgeDecisionPhysicalMappingsReady(decision)
    if not mappingsReady then
        BridgeRecordDecisionLifecycle(decision, "render", "DEFERRED_PHYSICAL_MAPPING",
            "missing-live-physical-mapping", missingInstanceId)
        if BridgeState.lastPhysicalDecisionBarrier ~= decision.decisionId then
            BridgeState.lastPhysicalDecisionBarrier = decision.decisionId
            BridgeLog("[Bridge] decision presentation deferred: missing live physical mapping instance="
                .. tostring(missingInstanceId) .. " decision=" .. tostring(decision.decisionId))
            BridgeShowError("Forge decision is waiting for a physical card mapping; retrying authoritative recovery")
        end
        if BridgeScheduleSnapshotReconcile ~= nil then
            BridgeScheduleSnapshotReconcile("decision physical mapping missing", "RECOVERY")
        end
        return
    end
    BridgePresentationMetric("decisionRenderExecuted")
    BridgeClearHighlights()
    BridgeRenderPreparedSpellPresentations(decision)

    if decision == nil or decision.actions == nil then
        BridgeResetSelectionState()
        BridgeRecordDecisionPresentationRendered(key)
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

    -- One controller owns all automatic priority decisions. The persistent
    -- checkbox only consumes pass-only priority; transient fast-forward may
    -- consume optional priority too, but never structured human choices.
    local controllerMode = BridgeYieldControllerMode ~= nil and BridgeYieldControllerMode() or "normal"
    local policyTurn = tonumber(BridgeState.yieldPolicyTurnNumber or 0) or 0
    local policyActiveSeat = BridgeState.yieldPolicyActiveSeatId
    local policyOwnTurn = BridgeState.yieldPolicyOwnTurn == true
    local policySessionMatches = BridgeState.yieldPolicySessionId == nil
        or BridgeState.yieldPolicySessionId == BridgeState.eventSessionId
    local policyTurnMatches = policyTurn == 0
        or (tonumber(BridgeState.tableTurnCount or 0) or 0) == policyTurn
    local policySeatMatches = policyActiveSeat == nil
        or BridgeState.currentTurnSeatId == policyActiveSeat
    -- A freshly started match may expose the opponent turn before Forge has
    -- emitted its first numeric turn counter. In that bootstrap window, the
    -- active-seat fence remains authoritative; turn_changed retires the
    -- policy once the real boundary is observed.
    local legacyYield = BridgeState.ui ~= nil and BridgeState.ui.fastForwardActive ~= true
        and BridgeState.ui.autoAdvanceMode == "YIELD" and BridgeState.yieldPolicyTurnNumber ~= nil
    local fastForward = BridgeState.ui ~= nil and BridgeState.ui.fastForwardActive == true
    if fastForward and BridgeState.ui.fastForwardActive == true
        and (BridgeState.ui.fastForwardSessionId ~= BridgeState.eventSessionId
            or (tonumber(BridgeState.ui.fastForwardTurnNumber or 0) or 0) ~= (tonumber(BridgeState.tableTurnCount or 0) or 0)) then
        BridgeCancelFastForward("turn-or-session-boundary")
        fastForward = false
    end
    local controllerActive = controllerMode ~= "normal"
        or (BridgeState.ui ~= nil and BridgeState.ui.autoAdvanceMode == "YIELD")
    if controllerActive and policyTurnMatches and policySeatMatches and policySessionMatches then
        local humanDecision = decision.seatId == "forge-player-1"
        local automaticAction = nil
        if humanDecision and decision.kind == "main_priority" then
            for _, action in ipairs(decision.actions or {}) do
                if action.type == "pass_priority" then automaticAction = action; break end
            end
        elseif humanDecision and decision.kind == "attacker_selection" then
            for _, action in ipairs(decision.actions or {}) do
                if action.type == "finish_attacking" or action.type == "choose_none" then
                    automaticAction = action
                    break
                end
            end
        end

        local phaseKey = BridgeYieldPhaseKey(decision.phaseName or BridgeState.currentPhase)
        local stopScope = BridgeYieldScopeForDecision(decision)
        local stopped = BridgeState.ui and BridgeState.ui.fastForwardStops
            and BridgeState.ui.fastForwardStops[stopScope]
            and phaseKey ~= nil and BridgeState.ui.fastForwardStops[stopScope][phaseKey] == true
        if fastForward and stopped then
            BridgeYieldRecord(decision, "AUTO_ACTION_BLOCKED", "phase-stop", "FAST_FORWARD")
            BridgeCancelFastForward("phase-stop")
        elseif legacyYield and policyOwnTurn and automaticAction ~= nil then
            if BridgeConsiderYieldAutomaticAction(decision, automaticAction, "OWN_TURN_YIELD") then
                BridgeRecordDecisionPresentationRendered(key)
                return
            end
        elseif legacyYield and not policyOwnTurn
            and decision.kind == "main_priority"
            and BridgeDecisionOffersActionType(decision, "pass_priority")
            and not BridgeDecisionHasNonPassAction(decision) then
            for _, action in ipairs(decision.actions or {}) do
                if action.type == "pass_priority" then
                    if BridgeConsiderYieldAutomaticAction(decision, action, "OPPONENT_YIELD") then
                        BridgeRecordDecisionPresentationRendered(key)
                        return
                    end
                    break
                end
            end
        elseif fastForward and automaticAction ~= nil then
            if BridgeConsiderYieldAutomaticAction(decision, automaticAction, "FAST_FORWARD") then
                BridgeRecordDecisionPresentationRendered(key)
                return
            end
        elseif not fastForward and BridgeState.ui ~= nil and BridgeState.ui.autoPassEmpty
            and decision.kind == "main_priority"
            and BridgeDecisionOffersActionType(decision, "pass_priority")
            and not BridgeDecisionHasNonPassAction(decision) then
            for _, action in ipairs(decision.actions or {}) do
                if action.type == "pass_priority" then
                    if BridgeConsiderYieldAutomaticAction(decision, action, "AUTO_PASS_EMPTY") then
                        BridgeRecordDecisionPresentationRendered(key)
                        return
                    end
                    break
                end
            end
        elseif legacyYield and humanDecision then
            BridgeDisarmYieldPolicy("mandatory-human-decision")
            policyTurnMatches = false
        elseif fastForward or (humanDecision and (decision.kind ~= "main_priority"
            or BridgeDecisionHasNonPassAction(decision)
            or not BridgeDecisionOffersActionType(decision, "pass_priority"))) then
            BridgeRecordDecisionLifecycle(decision, "yield", "AUTO_ACTION_CONSIDERED",
                "stopped_meaningful_choice", nil, nil,
                fastForward and "FAST_FORWARD" or "AUTO_PASS_EMPTY",
                "stopped_meaningful_choice")
            if fastForward then BridgeCancelFastForward("required-human-choice") end
            policyTurnMatches = false
        end
    end

    -- Keep passive auto-pass off for the human seat. This avoids skipping a
    -- playable window when decision/action rendering lags a frame; explicit
    -- PASS and END TURN controls still provide intentional progression.
    if decision.kind == "main_priority"
        -- Passive automation is only safe for an explicitly identified
        -- opponent window.  A missing/legacy seat field must never be treated
        -- as evidence that the human can be auto-passed through Main 1.
        and decision.seatId == "forge-player-2"
        and (decision.activeSeatId == nil or decision.activeSeatId == "forge-player-2")
        and BridgeDecisionOffersActionType(decision, "pass_priority")
        and not BridgeDecisionHasNonPassAction(decision) then
        for _, action in ipairs(decision.actions) do
            if action.type == "pass_priority" then
                local blockedReason = BridgeAutomaticDecisionBlocked(decision)
                if blockedReason ~= nil then
                    BridgeRecordDecisionLifecycle(decision, "smart", "AUTO_ACTION_BLOCKED",
                        blockedReason, action.actionId, action.type, "SMART", "blocked")
                    return
                end
                if BridgeAutomaticPassBackpressured() then
                    BridgeRecordDecisionLifecycle(decision, "smart", "AUTO_ACTION_BLOCKED",
                        "event-backpressure", action.actionId, action.type, "SMART", "blocked_backpressure")
                    return
                end
                BridgeRecordDecisionLifecycle(decision, "smart", "AUTO_ACTION_CONSIDERED",
                    "pass-only-opponent-window", action.actionId, action.type, "SMART", "submitted")
                BridgeSubmitChoice(decision.decisionId, action.actionId, "empty_priority_auto_pass")
                BridgeRecordDecisionPresentationRendered(key)
                return
            end
        end
    end

    local highlightColor = {0.53, 0.81, 0.98}
    local selectedCombatColor = {0.2, 1.0, 0.35}
    -- Discard is an immediate destructive choice and must remain visibly
    -- distinct from ordinary action availability.  Structured discard menus
    -- are Forge-owned toggles, but their physical candidates still use the
    -- orange choice treatment so the player can see that a discard decision
    -- is awaiting input.  Main-priority actions (including the pre-combat
    -- land/spell window) remain blue.
    if BridgeIsDiscardChoice(decision)
        or BridgeIsMulliganBottomSelection(decision)
        or (decision.kind == "card_selection" and BridgeDecisionContainsDiscardAction(decision))
        or (decision.kind ~= "main_priority" and not BridgeIsStructuredForgeToggleChoice(decision)) then
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
    local function addDecisionCandidate(object)
        if object == nil or object.tag ~= "Card" then return end
        local guid = BridgeSafeObjectGuid(object)
        if guid ~= nil and candidateGuid[guid] == true then return end
        if guid ~= nil then candidateGuid[guid] = true end
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
            local handMappingChanged = BridgeState.physicalSeatByGuid[guid] ~= decision.seatId
                or BridgeState.physicalZoneByGuid[guid] ~= "hand"
            BridgeState.physicalSeatByGuid[guid] = decision.seatId
            BridgeState.physicalZoneByGuid[guid] = "hand"
            if handMappingChanged then
                BridgeAdvancePhysicalPresentationGeneration("hand-mapping-repaired")
                -- A discard decision may have been shown via the HUD while
                -- this exact hand mapping was pending. Re-render once the
                -- physical identity is repaired so the same Forge action is
                -- available from the card as well.
                if BridgeState.lastDecision ~= nil
                    and BridgeState.lastDecision.decisionId == decision.decisionId then
                    BridgeWaitFrames(function()
                        if BridgeState.lastDecision ~= nil
                            and BridgeState.lastDecision.decisionId == decision.decisionId then
                            BridgeRenderDecision(BridgeState.lastDecision, true)
                        end
                    end, 1)
                end
            end
        end
        local isCandidate = decision.kind ~= "main_priority"
            or mappedInDecisionHand
            or observedInDecisionHand
            or (guid ~= nil
                and BridgeState.physicalSeatByGuid[guid] == decision.seatId
                and (BridgeState.physicalZoneByGuid[guid] == "battlefield"
                    or BridgeState.physicalZoneByGuid[guid] == "graveyard"
                    or BridgeState.physicalZoneByGuid[guid] == "exile"
                    or BridgeState.physicalZoneByGuid[guid] == "command"))
        if isCandidate then
            table.insert(cards, object)
        end
    end
    -- Exact Forge identities are resolved through the bridge indexes below;
    -- a world scan is only needed for legacy/name-only actions.  In
    -- particular, KEEP/MULLIGAN and pass-only menus contain no card
    -- candidates at all.  Scanning every TTS object for those menus was the
    -- measured freeze hot path during opening-hand presentation.
    local scanWorldCandidates = false
    for _, action in ipairs(decision.actions or {}) do
        local exactInstanceId = action.preparedSourceCardInstanceId
            or action.sourceCardInstanceId or action.cardInstanceId
        local actionType = action.type or action.actionKind
        local hasDisplayCard = action.cardIdentity ~= nil and tostring(action.cardIdentity) ~= ""
        if exactInstanceId == nil
            and hasDisplayCard
            and actionType ~= "pass_priority"
            and actionType ~= "keep_hand"
            and actionType ~= "mulligan" then
            scanWorldCandidates = true
            break
        end
    end
    if scanWorldCandidates then
        for _, object in ipairs(getAllObjects()) do
            addDecisionCandidate(object)
        end
    end
    -- TTS does not guarantee that cards held in a hand are returned by
    -- getAllObjects().  This is especially visible after mulligan replacement
    -- cards arrive through a hand callback, so include the authoritative
    -- decision seat's live hand as an explicit candidate source.
    if decisionSeat ~= nil then
        local handObjects = BridgeTryGetSeatHandObjects(decision.seatId)
        for _, object in ipairs(handObjects or {}) do
            addDecisionCandidate(object)
        end
    end

    for _, action in ipairs(decision.actions) do
        if action.targetKind == "player" and action.targetSeatId ~= nil then
            local suppressSelfDefenderTarget = decision.kind == "defender_selection"
                and action.targetSeatId == decision.seatId
                and BRIDGE_SEATS["forge-player-1"] ~= nil
                and BRIDGE_SEATS["forge-player-2"] ~= nil
            if suppressSelfDefenderTarget then
                representedActionIds[action.actionId] = true
                BridgeLog("[Bridge] suppressing illegal self-defender target in two-player match seat="
                    .. tostring(action.targetSeatId))
            else
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
        local combatActionKind = action.type or action.actionKind
        local combatSelection = combatActionKind == "choose_attacker" or combatActionKind == "choose_blocker"
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
        -- Combat candidates are Forge battlefield objects.  A stale mapping
        -- can otherwise make a spent instant (or any card that has since left
        -- the battlefield) inherit a combat highlight because non-priority
        -- decisions historically accepted every mapped zone.
        if combatSelection and mappedPhysicalZone ~= "battlefield" then
            mappedZoneMatches = false
        end
        local exactMappingContradictsActionSource = mappedObject ~= nil
            and action.cardInstanceId ~= nil
            and ((actionSourceZone ~= "" and not mappedSourceZoneMatches)
                or not mappedSeatMatches)
        if exactMappingContradictsActionSource then
            -- The exact Forge instance is still live, but it is no longer in
            -- the action's declared source zone (for example, Lotus Petal has
            -- already been sacrificed into the graveyard). Never recover a
            -- stale action by matching another card with the same name.
            BridgeLog(string.format(
                "[Bridge] suppressing stale exact action instance=%s card=%s sourceZone=%s mappedZone=%s mappedSeat=%s decisionSeat=%s",
                tostring(action.cardInstanceId), tostring(action.cardIdentity or action.type),
                tostring(actionSourceZone), tostring(mappedPhysicalZone),
                tostring(BridgeState.physicalSeatByGuid[mappedGuid]), tostring(decision.seatId)))
        elseif mappedSeatMatches and mappedZoneMatches then
            table.insert(matches, mappedObject)
        else
            local fallbackMatches = {}
            -- A combat candidate with an exact Forge identity must never fall
            -- back to a same-name physical card. A spent instant (or another
            -- stale card that left the battlefield) could otherwise receive an
            -- attacker highlight and submit the wrong object.
            if not (combatSelection and action.cardInstanceId ~= nil) then
                for _, object in ipairs(cards) do
                    local objectGuid = BridgeSafeObjectGuid(object)
                    local objectZone = objectGuid and BridgeState.physicalZoneByGuid[objectGuid] or nil
                    if (not combatSelection or objectZone == "battlefield")
                        and BridgeCardNameMatches(object.getName(), action.cardIdentity) then
                        table.insert(fallbackMatches, object)
                    end
                end
            else
                BridgeLog(string.format(
                    "[Bridge] suppressing combat action without exact physical mapping instance=%s card=%s",
                    tostring(action.cardInstanceId), tostring(action.cardIdentity or action.type)))
            end
            if action.cardInstanceId == nil then
                matches = fallbackMatches
            elseif #fallbackMatches == 1 then
                local recoveredGuid = BridgeSafeObjectGuid(fallbackMatches[1])
                if recoveredGuid ~= nil then
                    local recoveredZone = decision.kind == "main_priority"
                        and "hand" or BridgeState.physicalZoneByGuid[recoveredGuid]
                    BridgeRecordLooseCardIdentity(action.cardInstanceId, recoveredGuid, decision.seatId, recoveredZone)
                    if action.cardIdentity ~= nil then
                        BridgeState.cardNameByInstanceId[action.cardInstanceId] = action.cardIdentity
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
    BridgeRecordDecisionPresentationRendered(key)
end

function BridgeShowError(message)
    local text = "[Bridge] " .. tostring(message)
    BridgeLog(text)
    broadcastToAll(text, {1.0, 0.2, 0.2})
end

function BridgeCaptureUnboundPickupIntent(object)
    if object == nil or object.tag ~= "Card" then return end
    local guid = BridgeSafeObjectGuid(object)
    if guid == nil then return end
    local seatId = BridgeState.physicalSeatByGuid[guid]
    local zone = BridgeState.physicalZoneByGuid[guid]
    if seatId == nil or zone == nil then return end
    BridgeState.unboundPickupIntent = {
        guid = guid,
        seatId = seatId,
        zone = zone,
        position = object.getPosition(),
        rotation = object.getRotation(),
        useHands = object.use_hands
    }
end

function BridgeRejectUnboundDropIfIllegal(object)
    local intent = BridgeState.unboundPickupIntent
    BridgeState.unboundPickupIntent = nil
    if intent == nil or object == nil then return end
    if BridgeSafeObjectGuid(object) ~= intent.guid then return end
    if intent.zone ~= "hand" then return end

    local current = object.getPosition()
    local dx = current.x - intent.position.x
    local dz = current.z - intent.position.z
    local movedSq = dx * dx + dz * dz
    if movedSq < 1.0 then return end
    if BridgeObjectNearSeatZone(object, intent.seatId, "hand") then return end

    object.use_hands = intent.useHands
    object.setPositionSmooth(intent.position, false, true)
    object.setRotationSmooth(intent.rotation, false, true)
    object.highlightOn({1.0, 0.1, 0.1}, 2)
    BridgeShowError("illegal physical move rejected; use a highlighted Forge action")
end

function onObjectPickUp(playerColor, object)
    if object == nil or BridgeState.submitting then
        return
    end

    BridgeState.unboundPickupIntent = nil
    local action = BridgeState.actionByGuid[object.getGUID()]
    if action == nil then
        BridgeCaptureUnboundPickupIntent(object)
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

    if object.tag == "Card" and (BridgeDecisionNeedsConfirmation(decision)
        or (action.requiresSelection == true
            and action.type ~= "choose_attacker"
            and action.type ~= "choose_blocker")) then
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
        -- The physical snap-back is asynchronous.  A spell/target choice can
        -- resolve and Forge can publish a newer decision before these frames
        -- elapse (Thought Scour is a particularly visible example).  Never
        -- redraw the captured decision after it has retired: doing so brings
        -- back stale cast/target highlights over the authoritative next
        -- decision.  The normal decision/event pipeline owns the replacement
        -- render.
        local capturedDecisionId = decision.decisionId
        local capturedSessionId = BridgeState.eventSessionId
        local capturedRuntimeEpoch = BRIDGE_RUNTIME_EPOCH_LOCAL
        BridgeWaitFrames(function()
            local current = BridgeState.lastDecision
            local decisionIsUnsubmitted = BridgeState.choiceTransactions[capturedDecisionId] == nil
                and BridgeState.retiredChoiceDecisionIds[capturedDecisionId] ~= true
            local sameRuntime = BridgeRuntimeIsCurrent(capturedRuntimeEpoch)
            local sameSession = BridgeState.eventSessionId == capturedSessionId
            local actionable = current ~= nil and #(current.actions or {}) > 0
            if sameRuntime and sameSession and decisionIsUnsubmitted
                and actionable and current.decisionId == capturedDecisionId then
                BridgeRenderDecision(current, true)
            end
        end, 2)
        return
    end

    -- Player scoreboards and other non-card targets are selection surfaces,
    -- not draggable game pieces, so the grab itself commits the offered target.
    if object.tag ~= "Card" then
        BridgeSubmitChoice(decision.decisionId, action.actionId, "physical_target_pickup")
    end
end

function onObjectDrop(playerColor, object)
    if object == nil or BridgeState.submitting then
        BridgeState.unboundPickupIntent = nil
        return
    end

    local intent = BridgeState.pendingIntent
    if intent == nil then
        BridgeRejectUnboundDropIfIllegal(object)
        return
    end
    if object.getGUID() ~= intent.guid then
        return
    end
    BridgeState.unboundPickupIntent = nil

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
            BridgeTracePermanentTransition("CAST_CONFIRM", {
                cardInstanceId = intent.action.cardInstanceId,
                seatId = intent.seatId,
                sourceZone = intent.physicalZone,
                destinationZone = "stack",
                sequence = "intent:" .. tostring(intent.action.actionId)
            }, object, intent.physicalZone)
            BridgeTracePermanentTransition("STACK_MOVE", {
                cardInstanceId = intent.action.cardInstanceId,
                seatId = intent.seatId,
                sourceZone = intent.physicalZone,
                destinationZone = "stack",
                sequence = "intent:" .. tostring(intent.action.actionId)
            }, object, intent.physicalZone)
            BridgeEnsureCastPreviewControls(intent)
            BridgeAdvancePhysicalPresentationGeneration("cast-preview-entered")
            return
        end
        BridgeAdvancePhysicalPresentationGeneration("physical-intent-accepted")
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
    BridgeAdvancePhysicalPresentationGeneration("intent-rolled-back")
    if intent.action ~= nil and intent.action.type == "cast_spell" then
        BridgeState.pendingCastBySeatId[intent.seatId] = nil
    end
end

function BridgeBootstrapCurrentSnapshot(sessionId, callback, resumeFromSnapshotCursor, resyncOrigin)
    if BridgeState.eventSessionId == sessionId
        and BridgeState.lifecycleState == BRIDGE_LIFECYCLE_ACTIVE
        and tonumber(BridgeState.lastAppliedEventSequence or 0) > 0
        and resumeFromSnapshotCursor ~= true then
        BridgeLog("[Bridge] ACTIVE_GAME_REENTERED_BOOTSTRAP origin=" .. tostring(resyncOrigin))
        callback(false, "ACTIVE_GAME_REENTERED_BOOTSTRAP")
        return
    end
    if BridgeState.bootstrapping then
        -- A previous hand-readiness/bootstrap attempt can leave only its
        -- local ownership flag behind after a callback is abandoned.  A
        -- same-session authoritative resync is the recovery owner and must
        -- be able to supersede that stale attempt; otherwise every valid
        -- snapshot is rejected before reconciliation even begins.  The
        -- generation fence makes the old continuation inert.
        if resumeFromSnapshotCursor == true and BridgeState.resyncInFlight == true
            and BridgeState.eventSessionId == sessionId then
            BridgeState.resyncBootstrapGeneration = (BridgeState.resyncBootstrapGeneration or 0) + 1
            BridgeState.bootstrapping = false
            BridgeLog("[Bridge] superseded stale bootstrap ownership for authoritative resync")
        else
            callback(false, "an embodiment bootstrap is already in progress")
            return
        end
    end
    BridgeState.resyncBootstrapGeneration = (BridgeState.resyncBootstrapGeneration or 0) + 1
    local bootstrapGeneration = BridgeState.resyncBootstrapGeneration
    BridgeSetResyncStage("FetchingSnapshot", "bootstrap", nil)
    BridgeRecordResyncLifecycle("SNAPSHOT_REQUESTED", resyncOrigin, bootstrapGeneration)
    local function currentBootstrap()
        return BridgeState.resyncBootstrapGeneration == bootstrapGeneration
            and BridgeState.eventSessionId == sessionId
            and BridgeState.bootstrapping == true
    end
    local function finishBootstrap(ok, errorMessage)
        if not currentBootstrap() then return end
        BridgeState.bootstrapCompletionInFlight = true
        BridgeState.bootstrapStage = ok and "BOOTSTRAP_COMPLETE" or "BOOTSTRAP_ABORTED"
        local success, callbackError = xpcall(function()
            BridgeState.bootstrapping = false
            callback(ok, errorMessage)
        end, debug ~= nil and debug.traceback ~= nil and debug.traceback or function(err) return tostring(err) end)
        BridgeState.bootstrapCompletionInFlight = false
        if not success then
            BridgeState.bootstrapping = false
            BridgeState.bootstrapStage = "BOOTSTRAP_ABORTED"
            BridgeLog("[Bridge] bootstrap completion callback failed: " .. tostring(callbackError))
        end
    end
    -- Establish the event session before populating instance mappings. Event
    -- polling must not clear the authoritative snapshot we just reconciled.
    -- A same-session recovery already has a committed event session and a
    -- checkpoint. Re-preparing it here needlessly increments every
    -- presentation generation and clears/restores the mapping registry on
    -- each retry, which was the source of the longitudinal recovery churn.
    local sameSessionRecovery = resumeFromSnapshotCursor == true
        and BridgeState.eventSessionId == sessionId
    BridgeTraceStart("START-09 event-session-prepare", sameSessionRecovery and "preserved" or "required")
    if not sameSessionRecovery then
        BridgePrepareEventSession(sessionId, true, resumeFromSnapshotCursor == true)
    end
    -- A resync rebuilds physical embodiment, not the Forge match.  The card
    -- snapshot intentionally does not carry the live phase/priority mirror,
    -- so retain those last authoritative scalar values while the rebuild is
    -- in flight.  This prevents the HUD from looking like a new match until
    -- the resumed decision/event stream supplies its next update.
    local preservedResyncPresentation = BridgeState.resyncPresentationState
    BridgeState.resyncPresentationState = nil
    if preservedResyncPresentation ~= nil then
        BridgeState.currentTurnSeatId = preservedResyncPresentation.currentTurnSeatId
        BridgeState.currentPhase = preservedResyncPresentation.currentPhase
        BridgeState.prioritySeatId = preservedResyncPresentation.prioritySeatId
        BridgeState.tableTurnCount = preservedResyncPresentation.tableTurnCount or BridgeState.tableTurnCount
        BridgeUiMarkDirty("resync-state-preserved")
    end
    BridgeState.bootstrapping = true
    BridgeState.bootstrapStage = "BOOTSTRAP_DECISION_PENDING"
    BridgeTraceStart("START-10 snapshot-request")
    BridgeGetEmbodimentSnapshot(function(ok, snapshot, err)
        if not currentBootstrap() then return end
        BridgeRecordResyncLifecycle("SNAPSHOT_RECEIVED", resyncOrigin, bootstrapGeneration, snapshot, ok and nil or err)
        BridgeRunTraced("START-11 snapshot-response", function()
            if not currentBootstrap() then return end
            BridgeTraceStart("START-11 snapshot-response", ok and tostring(snapshot and snapshot.sessionId or "ok") or tostring(err))
            if not ok or snapshot == nil then
                if snapshot ~= nil and snapshot.errorCode == "session_not_started" then
                    finishBootstrap(false, "session_not_started: bridge has no active Forge session")
                    return
                end
                finishBootstrap(false, "authoritative snapshot unavailable: " .. tostring(err))
                return
            end
            if snapshot.sessionId ~= sessionId then
                finishBootstrap(false, "snapshot session mismatch")
                return
            end
            local snapshotCursor = tonumber(snapshot.eventCursor)
            if snapshotCursor == nil or snapshotCursor < 0 then
                finishBootstrap(false, "authoritative snapshot is missing a valid event cursor")
                return
            end
            local snapshotFingerprint = table.concat({
                tostring(snapshot.sessionId), tostring(snapshot.eventCursor),
                tostring(snapshot.forgeSequence or "")
            }, "|")
            if BridgeState.resyncSnapshotFingerprint == snapshotFingerprint then
                BridgeState.resyncSnapshotRepeatCount = (BridgeState.resyncSnapshotRepeatCount or 0) + 1
            else
                BridgeState.resyncSnapshotFingerprint = snapshotFingerprint
                BridgeState.resyncSnapshotRepeatCount = 1
            end
            if BridgeState.resyncSnapshotRepeatCount > 2 then
                BridgeLog("[Bridge] RESYNC_NO_PROGRESS identical snapshot limit reached fingerprint=" .. snapshotFingerprint)
                finishBootstrap(false, "authoritative resync made no progress across identical snapshots")
                return
            end
            if resumeFromSnapshotCursor == true then
                -- Validation is deliberately side-effect free.  The queued
                -- prefix is superseded only by BridgeCommitSnapshotCheckpoint
                -- after physical reconciliation has completed successfully.
                BridgeRecordResyncLifecycle("VALIDATING_SNAPSHOT", resyncOrigin, bootstrapGeneration, snapshot)
            end
            BridgeRecordResyncSnapshotProgress(resyncOrigin, snapshot)
            BridgeRecordExpectedHandIdentities(snapshot)
            local duplicateGuidCount = BridgeAuditDuplicateLibraryGuids()
            if duplicateGuidCount > 0 then
                local detail = "physical library identity audit found " .. tostring(duplicateGuidCount)
                    .. " loose/contained duplicate GUID(s)"
                BridgeLog("[Bridge] " .. detail)
                finishBootstrap(false, detail)
                return
            end
            BridgeTraceStart("START-12 physical-bootstrap-begin")
            BridgeSetResyncStage("ReconcilingSnapshot", "snapshot-validated", snapshot)
            BridgeState.resyncReconcileStarted = true
            BridgeState.resyncLastProgressAt = BridgeResyncClockNow()
            BridgeRecordResyncLifecycle("RECONCILE_STARTED", resyncOrigin, bootstrapGeneration, snapshot)
            BridgeStageSeatCardsForBootstrap(snapshot, function(stagedOk, stagedError, stagedGuids)
                if not currentBootstrap() then return end
                if not stagedOk then
                    finishBootstrap(false, stagedError)
                    return
                end

                -- Each staged Card was individually containment-verified.
                -- Keep the terminal strict audit as a corruption canary
                -- before rebuilding exact Forge mappings.
                BridgeTraceStart("START-13 library-settle")
                BridgeVerifyLibraryIdentityStability(function(stable, stabilityError)
                    if not currentBootstrap() then return end
                    if not stable then
                        local detail = "physical library identity audit found " .. tostring(stabilityError)
                            .. " after staging"
                        BridgeLog("[Bridge] " .. detail)
                        finishBootstrap(false, detail)
                        return
                    end
                    BridgeAnnotateSnapshotBattlefieldKinds(snapshot, function(annotated, annotationError)
                        if not currentBootstrap() then return end
                        BridgeRunTraced("START annotate-callback", function()
                            if not currentBootstrap() then return end
                            if not annotated then
                                finishBootstrap(false, annotationError)
                                return
                            end
                            BridgeBootstrapSeats(snapshot, 1, function(seatsOk, seatsError)
                                if not currentBootstrap() then return end
                                BridgeRunTraced("START seat-bootstrap-callback", function()
                                    if not currentBootstrap() then return end
                                    if not seatsOk then finishBootstrap(false, seatsError); return end
                                    BridgeState.snapshotForgeSequence = snapshot.forgeSequence or 0
                                    if resumeFromSnapshotCursor == true then
                                        local cursor = snapshotCursor
                                        -- The snapshot is coherent through this bridge event cursor.
                                        -- Resume polling after it so no pre-snapshot transition is
                                        -- replayed over the just-rebuilt physical embodiment.
                                        local committed, commitError = BridgeCommitSnapshotCheckpoint(
                                            snapshot, "physical-reconcile-complete")
                                        if not committed then finishBootstrap(false, commitError); return end
                                    end
                                    BridgeLog(string.format(
                                        "[Bridge] authoritative embodiment bootstrap complete: seats=%d forgeSequence=%s (hidden identities redacted)",
                                        #(snapshot.seats or {}), tostring(BridgeState.snapshotForgeSequence)))
                                    finishBootstrap(true, nil)
                                end)
                            end)
                        end)
                    end)
                end, 1, stagedGuids)
            end)
        end)
    end)
end

function BridgeBootstrapWhenAvailable(sessionId, attempt, callback)
    BridgeBootstrapCurrentSnapshot(sessionId, function(ok, err)
        local detail = tostring(err or "")
        if string.find(detail, "session_not_started", 1, true) ~= nil
            or string.find(detail, "no active Forge session", 1, true) ~= nil then
            BridgeCleanupLocalSession("snapshot-no-session", BRIDGE_LIFECYCLE_READY_NO_SESSION)
            callback(false, "bridge reports no active session")
            return
        end
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

-- A recovery is a controlled, Forge-authoritative rebuild of TTS embodiment.
-- It never infers a card, replays a stale event, or changes Forge state. The
-- snapshot's bridge event cursor becomes the new resume point only after every
-- seat has been materially reconciled.
function BridgeIsExplicitResyncOrigin(origin)
    local value = string.lower(tostring(origin or ""))
    return value == "hud" or value == "manual" or value == "manual-control"
        or value == "user" or value == "user-resync"
end

local function BridgeCopyResyncValue(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] ~= nil then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, item in pairs(value) do
        copy[BridgeCopyResyncValue(key, seen)] = BridgeCopyResyncValue(item, seen)
    end
    return copy
end

local function BridgeCopyResyncTable(value)
    return BridgeCopyResyncValue(value or {}, {})
end

function BridgeBeginResyncMappingTransaction()
    if BridgeState.resyncMappingTransaction ~= nil then return end
    local names = {
        "physicalByInstanceId", "physicalInstanceIdByGuid", "physicalSeatByGuid",
        "physicalZoneByGuid", "physicalContainerByInstanceId", "physicalContainedInstanceIdByGuid",
        "cardNameByInstanceId", "canonicalCardNameByGuid",
        "authoritativeObjectByInstanceId", "battlefieldKindByInstanceId",
        "pendingPrivateHandIdentityByInstanceId", "untappedRotationByGuid",
        "physicalTappedByGuid", "counterStateByInstanceId", "keywordStateByInstanceId",
        "cardDesignationsByInstanceId"
    }
    local snapshot = {}
    for _, name in ipairs(names) do snapshot[name] = BridgeCopyResyncTable(BridgeState[name]) end
    BridgeState.resyncMappingTransaction = snapshot
end

function BridgeRestoreResyncMappingTransaction(reason)
    local snapshot = BridgeState.resyncMappingTransaction
    if snapshot == nil then return end
    for name, value in pairs(snapshot) do BridgeState[name] = value end
    BridgeState.resyncMappingTransaction = nil
    BridgeState.resyncLastBlockingPredicate = tostring(reason or "mapping-rollback")
    BridgeLog("[Bridge] RESYNC_MAPPING_ROLLBACK reason=" .. tostring(reason or "unspecified"))
end

function BridgeCommitResyncMappingTransaction()
    BridgeState.resyncMappingTransaction = nil
    BridgeState.resyncReconcileStarted = true
end

function BridgeResyncClockNow()
    if BridgePerformanceWallNow ~= nil then
        local wall = BridgePerformanceWallNow()
        if wall ~= nil then return wall end
    end
    return os.clock()
end

function BridgeRetireLocalPhysicalTransactions(reason)
    -- This only abandons TTS presentation work. Forge is not contacted and
    -- the authoritative event queue/cursors remain intact until the snapshot
    -- successfully replaces them.
    BridgeAdvancePhysicalPresentationGeneration(reason or "manual-resync-force")
    BridgeAdvancePhysicalTransactionGeneration(reason or "manual-resync-force")
    BridgeState.libraryExtractionQueueBySeatId = {}
    BridgeState.libraryExtractionActiveBySeatId = {}
    BridgeState.libraryExtractionTransactionBySeatId = {}
    BridgeState.graveyardExtractionActiveBySeatId = {}
    BridgeState.mulliganBottomQueueBySeatId = {}
    BridgeState.mulliganBottomInsertionActiveBySeatId = {}
    BridgeState.mulliganReturningInstanceIds = {}
    BridgeState.mulliganBottomInstanceIds = {}
    BridgeState.animationRunning = false
    BridgeState.eventDrainTransaction = nil
    BridgeLog("[Bridge] local physical transaction queues retired reason=" .. tostring(reason or "unspecified")
        .. " generation=" .. tostring(BridgeState.currentPhysicalPresentationGeneration))
end

function BridgeRestoreResyncCheckpoint(reason)
    local checkpoint = BridgeState.resyncCheckpoint
    if checkpoint == nil or checkpoint.sessionId ~= BridgeState.eventSessionId then return false end
    BridgeState.lastReceivedEventSequence = checkpoint.lastReceived
    BridgeState.lastAppliedEventSequence = checkpoint.lastApplied
    BridgeState.eventQueue = checkpoint.eventQueue
    BridgeState.resyncCheckpoint = nil
    BridgeLog(string.format("[Bridge] RESYNC_CHECKPOINT_RESTORED received=%s applied=%s reason=%s",
        tostring(checkpoint.lastReceived), tostring(checkpoint.lastApplied), tostring(reason)))
    return true
end

-- A validated authoritative snapshot supersedes the unsafe queued prefix.
-- This is essential for mulligan batches: replaying intermediate hand-return
-- events can dismantle an already-correct replacement hand and block recovery.
function BridgeSupersedeEventsThroughSnapshot(snapshotCursor, reason)
    local cursor = tonumber(snapshotCursor or 0) or 0
    local prior = BridgeState.eventQueue or {}
    local retained = {}
    local supersededCount = 0
    local firstSuperseded = nil
    local lastSuperseded = nil
    for _, event in ipairs(prior) do
        if tonumber(event.sequence or 0) > cursor then
            table.insert(retained, event)
        else
            supersededCount = supersededCount + 1
            firstSuperseded = firstSuperseded or event.sequence
            lastSuperseded = event.sequence
        end
    end
    BridgeState.eventQueue = retained
    BridgeState.lastReceivedEventSequence = math.max(
        tonumber(BridgeState.lastReceivedEventSequence or 0) or 0, cursor)
    BridgeState.lastSnapshotSupersededRange = supersededCount > 0 and {
        first = firstSuperseded, last = lastSuperseded, count = supersededCount,
        cursor = cursor, reason = reason
    } or nil
    BridgeLog(string.format("[Bridge] SNAPSHOT_CHECKPOINT_QUEUE_SUPERSEDED cursor=%s prior=%s retained=%s superseded=%s..%s(%s) reason=%s",
        tostring(cursor), tostring(#prior), tostring(#retained), tostring(firstSuperseded),
        tostring(lastSuperseded), tostring(supersededCount), tostring(reason)))
end

function BridgeCommitSnapshotCheckpoint(snapshot, reason)
    if snapshot == nil then return false, "snapshot is required for checkpoint commit" end
    local cursor = tonumber(snapshot.eventCursor)
    if cursor == nil or cursor < 0 then return false, "snapshot checkpoint has no valid cursor" end
    BridgeSetResyncStage("CommittingCheckpoint", reason or "snapshot-reconciled", snapshot)
    BridgeState.snapshotForgeSequence = snapshot.forgeSequence or BridgeState.snapshotForgeSequence or 0
    BridgeState.lastReceivedEventSequence = math.max(
        tonumber(BridgeState.lastReceivedEventSequence or 0) or 0, cursor)
    BridgeState.lastConsumedEventSequence = cursor
    BridgeState.lastStateProjectedEventSequence = cursor
    BridgeState.lastPhysicalPresentationEventSequence = cursor
    BridgeState.lastAppliedEventSequence = cursor
    BridgeSupersedeEventsThroughSnapshot(cursor, reason or "checkpoint-commit")
    BridgeState.skipExistingEventsOnAttach = false
    BridgeRecordResyncLifecycle("CHECKPOINT_COMMITTED", BridgeState.resyncOrigin,
        BridgeState.resyncBootstrapGeneration, snapshot, reason)
    return true, nil
end

function BridgeReleaseStalledResync(sessionId, token, reason)
    if BridgeState.eventSessionId ~= sessionId
        or BridgeState.resyncToken ~= token
        or BridgeState.resyncInFlight ~= true then return false end

    BridgeLog(string.format(
        "[Bridge] RESYNC_STALLED origin=%s session=%s token=%s startedAt=%s received=%s applied=%s queueLength=%s reason=%s",
        tostring(BridgeState.resyncOrigin), tostring(sessionId), tostring(token),
        tostring(BridgeState.resyncStartedAt), tostring(BridgeState.lastReceivedEventSequence),
        tostring(BridgeState.lastAppliedEventSequence), tostring(#(BridgeState.eventQueue or {})),
        tostring(reason or "watchdog")))

    -- A stalled bootstrap must stop owning the presentation.  Both the
    -- resync token and bootstrap generation fence callbacks that were already
    -- issued by the abandoned recovery; a later manual recovery can therefore
    -- start without an old callback changing its state.
    BridgeState.resyncToken = (BridgeState.resyncToken or token) + 1
    BridgeState.resyncBootstrapGeneration = (BridgeState.resyncBootstrapGeneration or 0) + 1
    BridgeState.resyncWatchdogToken = nil
    BridgeState.resyncInFlight = false
    BridgeState.resyncScheduled = false
    BridgeState.bootstrapping = false
    BridgeState.resyncStartedAt = nil
    BridgeState.resyncLastFailureReason = tostring(reason or "watchdog")
    BridgeState.resyncDeferredReason = tostring(reason or "watchdog")
    BridgeSetSchedulerOwner("NORMAL", "resync-stalled")
    BridgeState.animationRunning = false
    BridgeState.eventDrainTransaction = nil
    BridgeRestoreResyncMappingTransaction("resync-watchdog:" .. tostring(reason or "watchdog"))
    BridgeRestoreResyncCheckpoint("resync-watchdog:" .. tostring(reason or "watchdog"))
    BridgeRecordResyncLifecycle("FAILED", BridgeState.resyncOrigin, token, nil, reason,
        nil, BridgeState.lastReceivedEventSequence, BridgeState.lastAppliedEventSequence)
    if BridgeState.ui ~= nil then BridgeState.ui.resyncInFlight = false end
    BridgeSetStatus("RESYNC AVAILABLE", "Authoritative recovery stopped: " .. tostring(reason or "watchdog") .. ". Try RESYNC FORGE again.")
    BridgeUiMarkDirty("resync-stalled")
    return true
end

function BridgeCheckResyncWatchdog(reason)
    if BridgeState.resyncInFlight ~= true or BridgeState.resyncStartedAt == nil then return false end
    local now = BridgeResyncClockNow()
    if now == nil or now - BridgeState.resyncStartedAt < BRIDGE_RESYNC_STALL_SECONDS then return false end
    local token = BridgeState.resyncToken
    return BridgeReleaseStalledResync(BridgeState.eventSessionId, token, reason or "clock")
end

function BridgeScheduleResyncWatchdog(sessionId, token)
    BridgeState.resyncWatchdogToken = token
    local function check(source)
        if BridgeState.resyncWatchdogToken ~= token then return end
        BridgeReleaseStalledResync(sessionId, token, source)
    end
    -- Keep the time watchdog for normal TTS operation and add a frame/clock
    -- fallback.  A single delayed Wait.time callback must not leave the match
    -- in RESYNCING forever.
    BridgeWaitTime(function() check("time") end, BRIDGE_RESYNC_STALL_SECONDS)
    BridgeWaitFrames(function() check("frames") end, BRIDGE_RESYNC_STALL_FRAMES)
end

function BridgeResyncFromAuthoritativeSnapshot(origin)
    if BridgeState.terminalRecoveryError ~= nil then
        BridgeLog("[Bridge] RESYNC_BLOCKED reason=terminal-recovery-error origin=" .. tostring(origin)
            .. " kind=" .. tostring(BridgeState.terminalRecoveryError.kind))
        BridgeSetStatus("SYNCHRONIZATION STOPPED", "Forge must publish a replacement decision before recovery can continue.")
        if BridgeState.ui ~= nil then BridgeState.ui.resyncInFlight = false end
        BridgeState.resyncInFlight = false
        BridgeState.resyncScheduled = false
        BridgeState.resyncDeferredRetryScheduled = false
        BridgeUiMarkDirty("terminal-recovery-resync-blocked")
        return false
    end
    if BridgeState.resyncInFlight == true then
        BridgeLog("[Bridge] RESYNC_DEFERRED reason=already-in-flight origin=" .. tostring(origin))
        return false
    end
    if BridgeState.resyncCircuitOpen == true and not BridgeIsExplicitResyncOrigin(origin) then
        BridgeLog("[Bridge] RESYNC_BLOCKED reason=circuit-open rootCause=" .. tostring(BridgeState.resyncRootCause))
        BridgeSetStatus("RESYNC PAUSED", "Recovery made no progress; use manual RESYNC FORGE to retry.")
        return false
    end
    local sessionId = BridgeState.eventSessionId
    if sessionId == nil then
        BridgeShowError("cannot resync before Forge has started a session")
        BridgeLog("[Bridge] RESYNC_FAILED reason=no-session origin=" .. tostring(origin))
        return false
    end
    -- A resync requested from a library-order mismatch commonly arrives from
    -- inside the active extraction callback. Do not rebuild the snapshot while
    -- that physical transaction is still mutating the Deck; the callback's
    -- completion retires the queue and this bounded retry then starts from a
    -- stable physical order.
    local explicit = BridgeIsExplicitResyncOrigin(origin)
    if explicit then BridgeState.resyncCircuitOpen = false end
    if not BridgePhysicalLibraryQueuesIdle() then
        local now = BridgeResyncClockNow()
        if explicit and (BridgeState.manualResyncGraceUntil or 0) <= 0 then
            BridgeState.manualResyncGraceUntil = now + BRIDGE_RESYNC_PHYSICAL_QUEUE_GRACE_SECONDS
        end
        if explicit and now >= (BridgeState.manualResyncGraceUntil or 0) then
            BridgeLog("[Bridge] RESYNC_FORCE_LOCAL_RETIRE origin=" .. tostring(origin)
                .. " reason=physical-library-queue-timeout")
            BridgeRetireLocalPhysicalTransactions("manual-resync-force")
        else
            if not explicit and (BridgeState.resyncDeferredSince or 0) <= 0 then
                BridgeState.resyncDeferredSince = now
            end
            if not explicit and now - (BridgeState.resyncDeferredSince or now)
                >= BRIDGE_RESYNC_AUTOMATIC_QUEUE_GRACE_SECONDS then
                BridgeState.resyncDeferredReason = "physical-library-queue-timeout"
                BridgeLog("[Bridge] RESYNC_DEFERRED reason=physical-library-queue-timeout origin=" .. tostring(origin)
                    .. "; stopping automatic progression for manual recovery")
                BridgeStopOnDesync("automatic authoritative resync blocked by physical library queue")
                return false
            end
            BridgeState.resyncDeferredReason = "physical-library-queue"
            BridgeLog("[Bridge] RESYNC_DEFERRED reason=physical-library-queue origin=" .. tostring(origin)
                .. " graceUntil=" .. tostring(BridgeState.manualResyncGraceUntil))
            if BridgeState.resyncDeferredRetryScheduled then return false end
            BridgeState.resyncDeferredRetryScheduled = true
            BridgeWaitFrames(function()
                BridgeState.resyncDeferredRetryScheduled = false
                BridgeResyncFromAuthoritativeSnapshot(origin)
            end, 2)
            return false
        end
    end
    BridgeState.resyncDeferredSince = nil
    BridgeState.resyncDeferredRetryScheduled = false
    BridgeState.resyncScheduled = false
    if explicit then
        -- Invalidate delayed local callbacks even when the physical queues
        -- happened to look idle.  An event-drain continuation or other frame
        -- callback from the pre-resync presentation must not run against the
        -- table while the authoritative snapshot is rebuilding it.
        BridgeAdvancePhysicalTransactionGeneration("explicit-authoritative-resync")
        BridgeState.animationRunning = false
        BridgeState.eventDrainTransaction = nil
    end
    BridgeState.manualResyncGraceUntil = 0
    BridgeState.resyncDeferredReason = nil
    if BridgeState.resyncRootCause == nil then BridgeState.resyncRootCause = origin end
    BridgeState.resyncLastFailureReason = nil
    BridgeState.resyncLastProgressAt = BridgeResyncClockNow()
    -- The previous failure stopped both pollers.  Opening an explicit
    -- resync starts a new presentation generation; failures from that old
    -- generation must not remain latched against the recovery attempt.
    BridgeState.desyncLatched = false
    BridgeState.desyncLastMessage = nil
    BridgeState.resyncPresentationState = {
        currentTurnSeatId = BridgeState.currentTurnSeatId,
        currentPhase = BridgeState.currentPhase,
        prioritySeatId = BridgeState.prioritySeatId,
        tableTurnCount = BridgeState.tableTurnCount
    }
    BridgeState.resyncCheckpoint = {
        sessionId = sessionId,
        lastReceived = tonumber(BridgeState.lastReceivedEventSequence or 0) or 0,
        lastApplied = tonumber(BridgeState.lastAppliedEventSequence or 0) or 0,
        eventQueue = BridgeState.eventQueue
    }
    BridgeBeginResyncMappingTransaction()
    BridgeState.resyncToken = (BridgeState.resyncToken or 0) + 1
    local resyncToken = BridgeState.resyncToken
    BridgeState.resyncAttempt = (BridgeState.resyncAttempt or 0) + 1
    BridgeSetResyncStage("Requested", origin, nil)
    BridgeState.resyncBootstrapGeneration = (BridgeState.resyncBootstrapGeneration or 0) + 1
    BridgeState.resyncOrigin = origin
    BridgeState.resyncStartedAt = BridgeResyncClockNow()
    BridgeState.resyncInFlight = true
    BridgeState.resyncReconcileStarted = false
    BridgeState.resyncLastBlockingPredicate = nil
    BridgeSetSchedulerOwner("RESYNC", origin)
    if BridgeState.ui ~= nil and BridgeState.ui.fastForwardActive == true then
        BridgeState.fastForwardSuspendedByResync = true
        BridgeState.ui.fastForwardActive = false
        BridgeState.ui.autoAdvanceMode = "RESYNC"
    end
    if BridgeState.ui ~= nil then BridgeState.ui.resyncInFlight = true end
    local checkpointReceived = BridgeState.resyncCheckpoint.lastReceived
    local checkpointApplied = BridgeState.resyncCheckpoint.lastApplied
    BridgeScheduleResyncWatchdog(sessionId, resyncToken)
    -- Recovery is an explicit way out of a stale-choice/protocol pause.  Any
    -- outstanding request belongs to the pre-rebuild presentation and must
    -- not keep the replacement decision pipeline permanently blocked.
    BridgeState.submitting = false
    BridgeResumeChoiceProtocol("authoritative_resync")
    BridgeStopEventPolling("authoritative-resync")
    BridgeStopDecisionPolling()
    BridgeClearHighlights()
    BridgeResetSelectionState()
    BridgeHideMainPriorityControls()
    BridgeSetStatus("RESYNCING FROM FORGE", "Rebuilding physical cards from the authoritative snapshot...")
    BridgeUiMarkDirty("resync-start")
    BridgeLog("[Bridge] RESYNC_STARTED origin=" .. tostring(origin or "unknown")
        .. " session=" .. tostring(sessionId) .. " token=" .. tostring(resyncToken))
    BridgeRecordResyncLifecycle("REQUESTED", origin, resyncToken, nil, nil, nil,
        checkpointReceived, checkpointApplied)
    BridgeSetResyncStage("FetchingSnapshot", "request-started", nil)
    BridgeBootstrapCurrentSnapshot(sessionId, function(ok, err)
        if BridgeState.resyncToken ~= resyncToken or BridgeState.eventSessionId ~= sessionId then
            BridgeLog("[Bridge] RESYNC_FAILED reason=stale-callback token=" .. tostring(resyncToken))
            return
        end
        BridgeSetResyncStage(ok and "RestartingPipelines" or "Failed", ok and "snapshot-committed" or tostring(err), nil)
        BridgeState.resyncInFlight = false
        BridgeState.resyncScheduled = false
        BridgeState.resyncWatchdogToken = nil
        BridgeState.resyncStartedAt = nil
        BridgeState.resyncSnapshotFingerprint = nil
        BridgeState.resyncSnapshotRepeatCount = 0
        if BridgeState.ui ~= nil then BridgeState.ui.resyncInFlight = false end
        if not ok then
            BridgeState.resyncLastFailureReason = tostring(err)
            if string.find(tostring(err), "no progress", 1, true) ~= nil then
                BridgeState.resyncNoProgressAttempts = (BridgeState.resyncNoProgressAttempts or 0) + 1
                if BridgeState.resyncNoProgressAttempts >= 2 then
                    BridgeState.resyncCircuitOpen = true
                end
            end
            BridgeRestoreResyncMappingTransaction("bootstrap-failed:" .. tostring(err))
            BridgeRestoreResyncCheckpoint("bootstrap-failed")
            BridgeState.desyncLatched = true
            BridgeSetSchedulerOwner("NORMAL", "resync-failed")
            BridgeStopOnDesync("authoritative resync failed: " .. tostring(err))
            BridgeUiMarkDirty("resync-failed")
            BridgeLog("[Bridge] RESYNC_FAILED reason=" .. tostring(err))
            return
        end
        BridgeState.resyncCheckpoint = nil
        BridgeCommitResyncMappingTransaction()
        BridgeState.resyncNoProgressAttempts = 0
        BridgeState.resyncLastProgressAt = BridgeResyncClockNow()
        BridgeSetSchedulerOwner("NORMAL", "resync-commit")
        BridgeStartEventPolling(sessionId, false)
        BridgeState.desyncLatched = false
        BridgeState.desyncFailureCount = 0
        BridgeState.desyncLastMessage = nil
        BridgeSetStatus("RESYNCING FROM FORGE", "Checkpoint committed; reattaching the current Forge decision...")
        BridgeUiMarkDirty("resync-complete")
        BridgeLog("[Bridge] RESYNC_COMPLETE eventCursor="
            .. tostring(BridgeState.lastAppliedEventSequence))
        -- Reattach exactly one authoritative decision after the checkpoint.
        -- Polling while resync is active was the captured infinite loop: the
        -- decision was valid, but it could not be accepted against cursor 0.
        local decisionSession = BridgeState.eventSessionId
        local decisionGeneration = BridgeState.decisionPresentationGeneration
        BridgeGetDecision(function(decisionOk, decision, decisionErr)
            if BridgeState.resyncToken ~= resyncToken
                or BridgeState.eventSessionId ~= decisionSession
                or BridgeState.decisionPresentationGeneration ~= decisionGeneration then
                return
            end
            if decisionOk and decision ~= nil then
                BridgeAcceptDecision(decision, "resync-decision-reattach", decisionSession, decisionGeneration)
            else
                BridgeLog("[Bridge] RESYNC_DECISION_REATTACH_FAILED reason=" .. tostring(decisionErr))
                BridgeStartDecisionPolling()
            end
            BridgeSetStatus("MATCH ACTIVE", "Physical table resynced from Forge.")
            BridgeUiMarkDirty("resync-complete")
            BridgeRecordResyncLifecycle("COMPLETED", origin, resyncToken, decision, nil, nil, nil, nil)
            BridgeSetResyncStage("Completed", "pipelines-restarted", decision)
        end)
    end, true, origin)
    return true
end

-- Forge's snapshot is the only authoritative library order after its shuffle.
-- The physical importer deck begins in its own order, so merely matching card
-- names is insufficient: the first later draw can otherwise reveal a valid
-- but wrong physical card. Reinsert each expected card from bottom to top at
-- TTS's explicit top index (0). Do not rely on putObject's default insertion
-- behavior: that default is not an ordering contract across Deck/Card merges.
function BridgeSnapshotLibraryOrderAlreadyMatches(seatSnapshot)
    local libraryCards = {}
    for _, zone in ipairs(seatSnapshot.zones or {}) do
        if zone.name == "library" then
            for _, card in ipairs(zone.cards or {}) do table.insert(libraryCards, card) end
            break
        end
    end
    if #libraryCards == 0 then return true end
    for _, card in ipairs(libraryCards) do
        if card.zonePosition == nil then return false end
    end
    table.sort(libraryCards, function(left, right)
        return (tonumber(left.zonePosition or 0) or 0) < (tonumber(right.zonePosition or 0) or 0)
    end)
    local deck = BridgeResolveSeatLibraryDeck(seatSnapshot.seatId)
    if deck == nil or deck.tag ~= "Deck" then return false end
    local entries = BridgeLibraryEntries(deck)
    if entries == nil or #entries ~= #libraryCards then return false end
    for index, card in ipairs(libraryCards) do
        local entry = entries[index]
        local entryName = entry and (entry.nickname or entry.name or entry.Name) or ""
        if BridgeNormalizeCardName(entryName) ~= BridgeNormalizeCardName(card.cardName) then
            return false
        end
    end
    return true
end

function BridgeAlignLibraryOrderForSnapshot(seatSnapshot, callback)
    local libraryCards = {}
    for _, zone in ipairs(seatSnapshot.zones or {}) do
        if zone.name == "library" then
            for _, card in ipairs(zone.cards or {}) do table.insert(libraryCards, card) end
            break
        end
    end
    if #libraryCards == 0 then callback(true, nil); return end
    table.sort(libraryCards, function(left, right)
        return (tonumber(left.zonePosition or 0) or 0) < (tonumber(right.zonePosition or 0) or 0)
    end)

    local deck, _, deckError = BridgeResolveSeatLibraryDeck(seatSnapshot.seatId)
    if deck == nil then
        callback(false, "library order alignment could not resolve library: " .. tostring(deckError))
        return
    end
    if deck.tag == "Card" then
        if #libraryCards ~= 1 or not BridgeCardNameMatches(deck.getName(), libraryCards[1].cardName) then
            callback(false, "library order alignment found a single-card library that disagrees with Forge")
            return
        end
        callback(true, nil)
        return
    end
    -- Mulligan recovery often arrives after the final replacement hand and
    -- library are already physically correct. Avoid re-extracting every
    -- hidden library card in that case; a mismatch still takes the full
    -- authoritative repair path below.
    if BridgeSnapshotLibraryOrderAlreadyMatches(seatSnapshot) then
        callback(true, nil)
        return
    end
    local entries = BridgeLibraryEntries(deck)
    if entries == nil or #entries ~= #libraryCards then
        callback(false, string.format("library order alignment count mismatch: physical=%d authoritative=%d",
            #(entries or {}), #libraryCards))
        return
    end
    local seat = BRIDGE_SEATS[seatSnapshot.seatId]
    local libraryZone = seat and BridgeGetLiveObjectByGuid(seat.libraryZoneGuid) or nil
    if libraryZone == nil then
        callback(false, "library order alignment has no library zone")
        return
    end
    local position = libraryZone.getPosition()
    local nextIndex = #libraryCards
    local function reinsertNext()
        if nextIndex < 1 then callback(true, nil); return end
        local expected = libraryCards[nextIndex]
        local liveDeck, _, liveError = BridgeResolveSeatLibraryDeck(seatSnapshot.seatId)
        if liveDeck == nil then
            callback(false, "library order alignment lost physical library: " .. tostring(liveError))
            return
        end
        BridgeTakeCardFromDeckByIdentity(liveDeck, expected.cardName,
            {position.x, position.y + 2, position.z}, false,
            function(taken, takeError)
                if taken == nil then
                    callback(false, "library order alignment could not take " .. tostring(expected.cardName)
                        .. ": " .. tostring(takeError))
                    return
                end
                local target, _, targetError = BridgeResolveSeatLibraryDeck(seatSnapshot.seatId)
                if target == nil then
                    callback(false, "library order alignment lost remaining deck: " .. tostring(targetError))
                    return
                end
                local inserted = BridgeSafeObjectCall(target, function(current)
                    current.setLock(false)
                    current.putObject(taken, 0)
                end)
                if not inserted then
                    callback(false, "library order alignment could not reinsert " .. tostring(expected.cardName))
                    return
                end
                nextIndex = nextIndex - 1
                BridgeWaitFrames(reinsertNext, 2)
            end)
    end
    reinsertNext()
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
