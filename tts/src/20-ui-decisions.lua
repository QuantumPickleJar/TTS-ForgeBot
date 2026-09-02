
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
    local castPreviewPending = BridgeState.pendingIntent ~= nil
        and BridgeState.pendingIntent.action ~= nil
        and BridgeState.pendingIntent.action.type == "cast_spell"
    local prompt = decision and (decision.prompt or decision.kind or "Choose an action") or "AI THINKING..."
    if castPreviewPending then
        prompt = "CAST PREVIEW — press CAST / CONFIRM or CANCEL / RETURN"
    end
    if decision ~= nil and decision.kind == "cost_selection" and decision.costKind == "crew" then
        prompt = "CREW — SELECT CREATURES"
    end
    if decision ~= nil and BridgeIsDiscardChoice(decision) then
        -- Keep post-mulligan discard explicit even when Forge's prompt is
        -- generic. Exact candidate/action identities remain Forge-owned.
        prompt = "DISCARD A CARD - SELECT IN ORANGE, THEN CONFIRM"
    elseif decision ~= nil and decision.kind == "mulligan"
        and tostring(decision.mulliganStage or "") == "bottom_selection" then
        prompt = "MULLIGAN - PUT CARD ON BOTTOM, THEN CONFIRM"
    end
    BridgeUiSet("BridgeHudPrompt", "text", terminal and BridgeUiTerminalLabel(terminal) or prompt)
    BridgeUiSet("BridgeHudMana", "text", "MANA: " .. tostring(ui.manaMode or "AUTO"))
    local yieldMode = BridgeYieldControllerMode ~= nil and BridgeYieldControllerMode() or "normal"
    BridgeUiSet("BridgeHudMode", "text", ui.autoPassEmpty and "AUTO-PASS: ON" or "AUTO-PASS: OFF")
    BridgeUiSet("BridgeHudFast", "text", ui.fastPlaytest and "FAST: ON" or "FAST: OFF")
    BridgeUiSet("BridgeHudLog", "text", ui.gameLogVisible and "LOG: ON" or "LOG: OFF")
    local help = yieldMode == "fast_forward" and "FAST-FORWARD: " .. (ui.fastForwardStopScope or "own_turn")
        or (yieldMode == "auto_pass_empty" and "AUTO-PASS: EMPTY PRIORITY"
            or "NORMAL: every human Forge decision requires input.")
    BridgeUiSet("BridgeHudHelp", "text", help)
    local actions = {}
    for _, action in ipairs(terminal and {} or (decision and decision.actions or {})) do
        if BridgeActionPresentationAuthorized(action) then
            table.insert(actions, action)
        end
    end
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
                -- Ordinary priority actions are immediate exact Forge inputs,
                -- not local checkbox selections. Reserve selection marks for
                -- Forge collections and combat redraws so a draw/main menu
                -- cannot misleadingly advertise multi-select behavior.
                local selectionPresentation = BridgeDecisionNeedsConfirmation(decision)
                    or decision.kind == "attacker_selection"
                    or decision.kind == "blocker_selection"
                    or decision.kind == "blocker_assignment"
                local prefix = ""
                if selectionPresentation then
                    prefix = (BridgeState.selectedActionIds[action.actionId] == true or action.isSelected == true)
                        and "[x] " or "[ ] "
                end
                BridgeUiSet("BridgeHudAction" .. tostring(i), "text", prefix .. BridgeUiActionLabel(action))
                BridgeUiSet("BridgeHudAction" .. tostring(i), "tooltip", "Forge action: " .. BridgeUiActionLabel(action)
                    .. "\nKind: " .. tostring(action.actionKind or action.type or "choice")
                    .. (action.sourceCardName and ("\nSource: " .. tostring(action.sourceCardName)) or ""))
            end
        end
    end
    -- Card context may intentionally narrow the action rows, but it must not
    -- hide Forge's priority controls. Pass/Yield are properties of the full
    -- authoritative decision, not of a contextual HUD subset.
    local hasPass = false
    local hasYield = false
    for _, action in ipairs(decision and decision.actions or {}) do
        if action.type == "pass_priority" then hasPass = true; hasYield = true end
    end
    local targetCanCancel = decision ~= nil and decision.allowsCancel == true
        and (decision.kind == "target_selection" or decision.kind == "defender_selection"
            or decision.kind == "player_selection")
    local yieldPolicyAvailable = BridgeState.gameEnded == nil
        and not BridgeDecisionNeedsConfirmation(decision)
        and BridgeState.pendingIntent == nil
    BridgeUiSet("BridgeHudPass", "active", hasPass and "true" or "false")
    -- Keep YIELD visible during an AI/opponent turn even when Forge is not
    -- currently waiting on a human decision; clicking it arms the policy and
    -- does not fabricate a pass. When a human pass decision exists, it uses
    -- the exact Forge action as before.
    BridgeUiSet("BridgeHudYield", "active", (hasYield or yieldPolicyAvailable) and "true" or "false")
    BridgeUiSet("BridgeHudConfirm", "active", (decision and BridgeDecisionNeedsConfirmation(decision))
        or castPreviewPending and "true" or "false")
    BridgeUiSet("BridgeHudConfirm", "text", castPreviewPending and "CAST / CONFIRM" or "CONFIRM")
    BridgeUiSet("BridgeHudConfirm", "tooltip", castPreviewPending
        and "Submit this Forge-approved spell after reviewing the cast preview."
        or "Submit the staged Forge selection when its required count is satisfied.")
    BridgeUiSet("BridgeHudCancel", "active", (castPreviewPending or (decision and
        ((BridgeDecisionNeedsConfirmation(decision) and not BridgeIsStructuredForgeToggleChoice(decision))
            or targetCanCancel))) and "true" or "false")
    BridgeUiSet("BridgeHudCancel", "text", castPreviewPending and "CANCEL / RETURN" or "CANCEL")
    BridgeUiSet("BridgeHudNewMatch", "active", terminal and "true" or "false")
    BridgeUiSet("BridgeHudNewMatch", "text", BridgeState.resetConfirmationArmed and "CONFIRM NEW MATCH" or "NEW MATCH")
    local footer = terminal and "NEW MATCH is available on the table."
        or (ui.contextInstanceId and "CARD CONTEXT — choose a Forge-provided action" or "Forge decides legality. Screen actions submit exact Forge choices.")
    if not terminal and #(BridgeState.stackSummary or {}) > 0 then footer = "STACK: " .. table.concat(BridgeState.stackSummary, " > ") end
    if not terminal and ui.gameLogVisible and #(ui.gameLog or {}) > 0 then footer = ui.gameLog[#ui.gameLog] end
    BridgeUiSet("BridgeHudFooter", "text", footer)
    if BridgeRenderRevealSurface ~= nil then BridgeRenderRevealSurface() end
end

function BridgeUiMount()
    local ui = BridgeState.ui
    if ui ~= nil and ui.mounted then return end
    pcall(function() UI.setAttribute("BridgeHudRoot", "active", "true") end)
    BridgeState.ui.mounted = true
    BridgeState.ui.uiAttributeCache = {}
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
    if BridgeState.pendingIntent ~= nil and BridgeState.pendingIntent.action ~= nil
        and BridgeState.pendingIntent.action.type == "cast_spell" then
        BridgeConfirmCastPreview(nil, player, false)
        return
    end
    if BridgeState.lastDecision == nil or not BridgeDecisionNeedsConfirmation(BridgeState.lastDecision) then return end
    BridgeConfirmSelection(nil, player, false)
end

function BridgeHudCancel(player, value, id)
    if BridgeState.pendingIntent ~= nil and BridgeState.pendingIntent.action ~= nil
        and BridgeState.pendingIntent.action.type == "cast_spell" then
        BridgeCancelCastPreview(nil, player, false)
        return
    end
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

function BridgeArmYieldPolicy(activeSeat, reason)
    -- Compatibility entry point for the physical END TURN/YIELD control.
    -- It uses the same transient controller as FAST-FORWARD.
    BridgeState.yieldPolicyTurnNumber = tonumber(BridgeState.tableTurnCount or 0) or 0
    BridgeState.yieldPolicyActiveSeatId = activeSeat
    BridgeState.yieldPolicySessionId = BridgeState.eventSessionId
    BridgeState.yieldPolicyOwnTurn = activeSeat == "forge-player-1"
    if BridgeState.yieldPolicyOwnTurn then
        BridgeSetStatus("YIELDING REST OF TURN", "Forge will pass optional priority and finish your attack step using exact Forge actions.")
    else
        BridgeSetStatus("YIELD ARMED — STOPPING ON INTERACTION", "Forge will pass only empty opponent-turn priority windows.")
    end
    if BridgeState.eventSessionId ~= nil and BridgeState.gameEnded == nil then
        if not BridgeState.eventPolling then
            BridgeStartEventPolling(BridgeState.eventSessionId, false)
        end
        if BridgeState.lastDecision == nil and not BridgeState.submitting then
            BridgeStartDecisionPolling()
        end
    end
    BridgeStartFastForward(reason or "yield")
    -- Keep the established physical-control label while routing behavior
    -- through the shared fast-forward controller.
    if BridgeState.ui ~= nil then BridgeState.ui.autoAdvanceMode = "YIELD" end
    BridgeLog("[Bridge] yield policy armed activeSeat=" .. tostring(activeSeat)
        .. " ownTurn=" .. tostring(BridgeState.yieldPolicyOwnTurn)
        .. " reason=" .. tostring(reason or "user"))
end

function BridgeHudYield(player, value, id)
    local decision = BridgeState.lastDecision
    local activeSeat = BridgeState.currentTurnSeatId
    -- Yield is a turn-scoped policy. During the opponent's turn it must arm
    -- the policy even when Forge is between AI priority windows; if a real
    -- human response is already required, leave that decision untouched so
    -- the policy stops at the intervention boundary.
    BridgeArmYieldPolicy(activeSeat, decision == nil and "no-human-decision" or "hud-yield")
    if decision ~= nil then BridgeRenderDecision(decision, true) end
end

function BridgeDisarmYieldPolicy(reason)
    if BridgeState.ui ~= nil and BridgeState.ui.fastForwardActive == true then
        BridgeState.ui.fastForwardActive = false
        BridgeState.ui.fastForwardSessionId = nil
        BridgeState.ui.fastForwardTurnNumber = nil
        BridgeState.ui.fastForwardActiveSeatId = nil
    end
    if BridgeState.yieldPolicyTurnNumber ~= nil then
        BridgeState.yieldPolicyTurnNumber = nil
        BridgeState.yieldPolicyActiveSeatId = nil
        BridgeState.yieldPolicySessionId = nil
        BridgeState.yieldPolicyOwnTurn = false
        if BridgeState.ui ~= nil then
            BridgeState.ui.autoAdvanceMode = BridgeState.ui.autoPassEmpty and "AUTO-PASS EMPTY" or "NORMAL"
            BridgeUiMarkDirty("yield-policy-stopped")
        end
        BridgeLog("[Bridge] yield policy stopped reason=" .. tostring(reason))
    end
end

function BridgeAutomaticDecisionBlocked(decision)
    if decision == nil or decision.decisionId == nil or decision.decisionId == "" then return "no-current-decision" end
    if BridgeState.desyncLatched == true then return "desync-latched" end
    if BridgeState.resyncInFlight == true or BridgeState.resyncScheduled == true then return "resync-active" end
    local ui = BridgeState.ui or {}
    if ui.reportCaptureInFlight == true then return "diagnostic-capture" end
    local received = tonumber(BridgeState.lastReceivedEventSequence or 0) or 0
    local applied = tonumber(BridgeState.lastAppliedEventSequence or 0) or 0
    if received ~= applied or #(BridgeState.eventQueue or {}) > 0 then return "event-backpressure" end
    local cursor = tonumber(decision.eventCursor or 0) or 0
    local projected = math.max(applied, tonumber(BridgeState.lastStateProjectedEventSequence or 0) or 0)
    if cursor > 0 and cursor > projected then return "decision-cursor-mismatch" end
    return nil
end

function BridgeConsiderYieldAutomaticAction(decision, action, policy)
    if decision == nil or action == nil then return false end
    local blockedReason = BridgeAutomaticDecisionBlocked(decision)
    if blockedReason ~= nil then
        BridgeRecordDecisionLifecycle(decision, "yield", "AUTO_ACTION_BLOCKED", blockedReason,
            action.actionId, action.type or action.actionType, policy, "blocked")
        return false
    end
    local actionType = tostring(action.type or action.actionType or "unknown")
    local result = "submitted"
    if BridgeAutomaticPassBackpressured() then
        result = "blocked_backpressure"
        BridgeRecordDecisionLifecycle(decision, "yield", "AUTO_ACTION_BLOCKED", "event-backpressure",
            action.actionId, actionType, policy, result)
        return false
    end
    BridgeRecordDecisionLifecycle(decision, "yield", "AUTO_ACTION_CONSIDERED", "yield-policy",
        action.actionId, actionType, policy, result)
    local submitSource = policy == "FAST_FORWARD"
        and "fast_forward"
        or policy == "AUTO_PASS_EMPTY"
        and "auto_pass_empty"
        or policy == "OWN_TURN_YIELD"
        and ((actionType == "finish_attacking" or actionType == "choose_none")
            and "own_turn_yield_auto_finish_attacking" or "own_turn_yield_auto_pass")
        or "yield_policy_auto_pass"
    BridgeSubmitChoice(decision.decisionId, action.actionId, submitSource)
    return true
end

function BridgeHudMode(player, value, id)
    BridgeSetAutoPassEmpty(not (BridgeState.ui and BridgeState.ui.autoPassEmpty == true), "hud")
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
    BridgeHttp.requestJson("GET", "/health", nil, function(ok, body, err, request)
        if ok and body ~= nil and BridgeObserveBridgeHealth ~= nil then
            BridgeObserveBridgeHealth(body)
        end
        if callback ~= nil then callback(ok, body, err, request) end
    end)
end

function BridgeStartSession(callback)
    BridgeSetupTrace("SESSION_START_REQUEST_SENT", "POST /api/v1/session/start")
    BridgeHttp.requestJson("POST", "/api/v1/session/start", nil, callback)
end

function BridgeResetSessionRequest(callback)
    BridgeHttp.requestJson("POST", "/api/v1/session/reset", nil, callback)
end

function BridgeNormalizedDeckFormat()
    local value = string.lower(tostring(BridgeState.selectedFormat or BRIDGE_DEFAULT_MATCH_FORMAT or "limited"))
    if value == "standard" or value == "legacy" then return "constructed" end
    if value == "constructed" or value == "limited" then return value end
    return value
end

function BridgeDeckMinimumForFormat(format)
    local normalized = string.lower(tostring(format or ""))
    if normalized == "limited" then return 40 end
    if normalized == "constructed" then return 60 end
    return nil
end

function BridgeDeckCardCount(deck)
    if deck == nil or not BridgeObjectIsUsable(deck) then return 0 end
    if deck.tag == "Deck" then return #(deck.getObjects() or {}) end
    if deck.tag == "Card" then return 1 end
    return 0
end

function BridgeBuildDeckGuidManifest(deck)
    local manifest = {}
    if deck == nil or not BridgeObjectIsUsable(deck) then return manifest end
    if deck.tag == "Deck" then
        for _, entry in ipairs(deck.getObjects() or {}) do
            if entry ~= nil and tostring(entry.guid or "") ~= "" then
                manifest[tostring(entry.guid)] = true
            end
        end
    elseif deck.tag == "Card" then
        local guid = BridgeSafeObjectGuid(deck)
        if guid ~= nil then manifest[tostring(guid)] = true end
    end
    return manifest
end

function BridgeCollectManagedCardPreflightIssues(humanDeck, aiDeck)
    local allowed = BridgeBuildDeckGuidManifest(humanDeck)
    local aiAllowed = BridgeBuildDeckGuidManifest(aiDeck)
    for guid, _ in pairs(aiAllowed) do allowed[guid] = true end

    local stale = {}
    local byInstanceId = {}
    for _, object in ipairs(getAllObjects() or {}) do
        if BridgeObjectIsUsable(object) and object.tag == "Card" then
            local guid = BridgeSafeObjectGuid(object)
            local instanceId = BridgeReadPhysicalIdentity(object)
            local sessionId = BridgeReadPhysicalSessionIdentity(object)
            if guid ~= nil and (instanceId ~= nil or sessionId ~= nil) then
                if allowed[tostring(guid)] ~= true then
                    table.insert(stale, string.format("%s(instance=%s,session=%s)", tostring(guid), tostring(instanceId), tostring(sessionId)))
                end
                if instanceId ~= nil then
                    byInstanceId[instanceId] = byInstanceId[instanceId] or {}
                    table.insert(byInstanceId[instanceId], guid)
                end
            end
        end
    end

    local duplicates = {}
    for instanceId, guids in pairs(byInstanceId) do
        if #guids > 1 then
            table.sort(guids)
            table.insert(duplicates, string.format("%s=>%s", tostring(instanceId), table.concat(guids, ",")))
        end
    end
    table.sort(stale)
    table.sort(duplicates)
    return stale, duplicates
end

function BridgeStartMatchPreflight(humanDeck, aiDeck)
    if BridgeState.eventSessionId ~= nil and BridgeState.eventSessionId ~= "session-not-started" then
        return false, "an active TTS session already exists; use NEW MATCH for cleanup"
    end
    if BridgeState.eventPolling == true or BridgeState.decisionPollInFlight == true
        or BridgeState.resyncInFlight == true or BridgeState.bootstrapping == true then
        return false, "bridge is not in clean setup state; use NEW MATCH to clean existing match state"
    end

    local stale, duplicates = BridgeCollectManagedCardPreflightIssues(humanDeck, aiDeck)
    if #stale > 0 then
        return false, "managed cards from a previous session are still live outside deck piles: " .. table.concat(stale, "; ")
    end
    if #duplicates > 0 then
        return false, "duplicate cardInstanceId identities detected: " .. table.concat(duplicates, "; ")
    end

    local format = BridgeNormalizedDeckFormat()
    local provenance = tostring(BridgeState.selectedFormatProvenance or "")
    if provenance == "" then
        return false, "format provenance missing; configure explicit format provenance before START MATCH"
    end
    local minimum = BridgeDeckMinimumForFormat(format)
    if minimum == nil then
        return false, "unsupported selected format '" .. tostring(format) .. "'"
    end
    local humanCards = BridgeDeckCardCount(humanDeck)
    local aiCards = BridgeDeckCardCount(aiDeck)
    local override = BridgeState.allowDeckMinimumOverride == true
    if not override and (humanCards < minimum or aiCards < minimum) then
        return false, string.format(
            "deck count below minimum for %s (min=%d): humanCards=%d aiCards=%d",
            tostring(format), minimum, humanCards, aiCards)
    end
    if override then
        BridgeLog(string.format(
            "[Bridge] DECK_VALIDATION_OVERRIDE enabled=true format=%s min=%d provenance=%s humanCards=%d aiCards=%d",
            tostring(format), minimum, tostring(provenance), humanCards, aiCards))
    end
    BridgeSetupTrace("START_PREFLIGHT_OK", string.format(
        "format=%s provenance=%s min=%s override=%s humanCards=%s aiCards=%s",
        tostring(format), tostring(provenance), tostring(minimum), tostring(override), tostring(humanCards), tostring(aiCards)))
    return true, nil
end

-- TTS's imported library piles are the deck chooser.  We send printed
-- identities and explicit format provenance so Bridge-side validation never
-- falls back to an implicit format assumption.
function BridgeConfigureDecks(callback)
    local seats = {}
    for _, seatId in ipairs({"forge-player-1", "forge-player-2"}) do
        BridgeSetupTrace("DECK_PILE_SCAN_BEGIN", "seat=" .. tostring(seatId))
        local deck, _, deckError = BridgeResolveSeatLibraryDeck(seatId)
        if deck == nil then
            BridgeSetupTrace("DECK_PILE_SCAN_RESULT", "seat=" .. tostring(seatId) .. " pileGuid=nil objectType=nil cardCount=0 detectedFormat=unknown error=" .. tostring(deckError))
            callback(false, nil, "cannot load TTS library for " .. tostring(seatId) .. ": " .. tostring(deckError)); return
        end
        local counts = {}
        local containedCards = deck.getObjects() or {}
        for _, contained in ipairs(containedCards) do
            local name = BridgeImportedCardName(contained.nickname or contained.name or "")
            if BridgeNormalizeCardName(name) ~= "" then counts[name] = (counts[name] or 0) + 1 end
        end
        local cards = {}
        for name, count in pairs(counts) do table.insert(cards, {cardName = name, count = count}) end
        BridgeSetupTrace("DECK_PILE_SCAN_RESULT", string.format(
            "seat=%s pileGuid=%s objectType=%s cardCount=%s detectedFormat=%s uniqueNames=%s",
            tostring(seatId), tostring(BridgeSafeObjectGuid(deck)), tostring(deck.tag), tostring(#containedCards),
            tostring(BridgeState.selectedFormat or "unknown"), tostring(#cards)))
        if #cards == 0 then callback(false, nil, "TTS library is empty for " .. tostring(seatId)); return end
        BridgeLog(string.format("[Bridge] TTS deck inventory seat=%s uniqueNames=%d totalCards=%d revision=%s",
            tostring(seatId), #cards, #(deck.getObjects() or {}), tostring(BRIDGE_SCRIPT_REVISION)))
        table.insert(seats, {seatId = seatId, cards = cards})
    end
    local selectedFormat = BridgeNormalizedDeckFormat()
    local formatProvenance = tostring(BridgeState.selectedFormatProvenance or "")
    local allowMinimumOverride = BridgeState.allowDeckMinimumOverride == true
    BridgeSetupStage("VALIDATING_DECKS", "posting TTS deck inventory")
    BridgeLog("[Bridge] posting TTS deck inventory to /api/v1/decks")
    BridgeHttp.requestJson("POST", "/api/v1/decks", {
        seats = seats,
        format = selectedFormat,
        formatProvenance = formatProvenance,
        allowDeckMinimumOverride = allowMinimumOverride
    }, function(ok, body, err, request)
        BridgeSetupTrace("DECK_VALIDATION_RESULT", "ok=" .. tostring(ok) .. " error=" .. tostring(err or "none"))
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
    BridgeState.decisionPollScheduledAt = nil
    BridgeState.decisionPollDueAt = nil
    BridgeState.decisionPollTimerToken = nil
end

function BridgeDecisionPollNow()
    return os.clock()
end

-- A scheduled flag is only a claim made by the scheduler.  The timer token
-- and deadline make that claim auditable and let the frame watchdog recover a
-- callback which TTS silently drops.
function BridgeCheckDecisionPollingLiveness(reason)
    if BridgeState.gameEnded ~= nil or BridgeState.eventSessionId == nil
        or BridgeState.submitting or BridgeState.choiceProtocolPaused then return false end

    local now = BridgeDecisionPollNow()
    if BridgeState.decisionPollScheduled == true
        and BridgeState.decisionPollDueAt ~= nil
        and now >= tonumber(BridgeState.decisionPollDueAt) then
        BridgeLog(string.format("[Bridge] DECISION_POLL_TIMER_LOST reason=%s token=%s due=%s now=%s",
            tostring(reason), tostring(BridgeState.decisionPollTimerToken),
            tostring(BridgeState.decisionPollDueAt), tostring(now)))
        BridgeState.decisionPollScheduled = false
        BridgeState.decisionPollScheduledAt = nil
        BridgeState.decisionPollDueAt = nil
        BridgeState.decisionPollTimerToken = nil
        BridgeState.lastDecisionPollOutcome = "timer_lost"
    end

    -- A current decision is presentation state, not proof that a poller is
    -- alive.  The normal caller may explicitly allow a same-decision refresh.
    if BridgeState.lastDecision == nil
        and not BridgeState.decisionPollInFlight
        and not BridgeState.decisionPollScheduled then
        BridgeLog("[Bridge] DECISION_POLL_LIVENESS_REARM reason=" .. tostring(reason))
        BridgeStartDecisionPolling()
        return true
    end
    return false
end

function BridgeRecordStaleDecisionConvergence(decision, eventCursor, applied)
    local decisionId = tostring(decision and decision.decisionId or "(missing)")
    local retryKey = table.concat({
        decisionId,
        tostring(decision and decision.kind or "(unknown)"),
        tostring(eventCursor or 0),
        tostring(applied or 0),
        tostring(BridgeState.eventSessionId or "(no-session)"),
        tostring(BridgeState.decisionPresentationGeneration or 0)
    }, "|")
    if BridgeState.staleDecisionRetryKey ~= retryKey then
        BridgeState.staleDecisionRetryKey = retryKey
        BridgeState.staleDecisionRetryCount = 0
        BridgeState.staleDecisionRetryStartedAt = os.clock()
        BridgeState.staleDecisionRetryDeadlineAt = BridgeState.staleDecisionRetryStartedAt + BRIDGE_STALE_DECISION_CONVERGENCE_SECONDS
    end
    BridgeState.staleDecisionRetryCount = (BridgeState.staleDecisionRetryCount or 0) + 1
    BridgeState.decisionAwaitingCausallyCurrent = true
    BridgeState.lastDecisionPollOutcome = "awaiting_causally_current_decision"
    if BridgeState.staleDecisionRetryCount > BRIDGE_STALE_DECISION_CONVERGENCE_ATTEMPTS
        or (BridgeState.staleDecisionRetryDeadlineAt ~= nil and os.clock() > BridgeState.staleDecisionRetryDeadlineAt) then
        local detail = string.format(
            "stale decision did not converge decision=%s kind=%s cursor=%s applied=%s retries=%s",
            decisionId, tostring(decision and decision.kind or "(unknown)"), tostring(eventCursor), tostring(applied),
            tostring(BridgeState.staleDecisionRetryCount))
        BridgeLog("[Bridge] " .. detail)
        BridgeStopOnDesync(detail)
        return false
    end
    return true
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

function BridgeScheduleDecisionPoll(delay, generation, attempt, allowCurrentDecision)
    if BridgeState.gameEnded ~= nil then return end
    if generation ~= BridgeState.decisionPollGeneration then return end
    if (BridgeState.lastDecision ~= nil and allowCurrentDecision ~= true) or BridgeState.submitting then return end
    if BridgeState.decisionPollInFlight or BridgeState.decisionPollScheduled then return end

    local nextDelay = delay or 0.1
    -- FAST is for a known short authoritative transition, not a blanket
    -- override of Forge's normal no-decision backoff. Polling an idle Forge at
    -- 20 Hz can race a just-drawn card's physical embodiment and repeatedly
    -- retry the same presentation work before the 0.5 s authoritative wait.
    if BridgeState.ui ~= nil and BridgeState.ui.fastPlaytest and BridgeTransitionExpected() then
        nextDelay = math.min(nextDelay, 0.05)
    end
    BridgeState.decisionPollScheduled = true
    BridgeState.decisionPollScheduledAt = BridgeDecisionPollNow()
    BridgeState.decisionPollDueAt = BridgeState.decisionPollScheduledAt + nextDelay
    BridgeState.decisionPollTimerToken = (BridgeState.decisionPollTimerToken or 0) + 1
    local timerToken = BridgeState.decisionPollTimerToken
    BridgeWaitTime(function()
        if generation ~= BridgeState.decisionPollGeneration then return end
        if BridgeState.decisionPollTimerToken ~= timerToken then return end
        BridgeState.decisionPollScheduled = false
        BridgeState.decisionPollScheduledAt = nil
        BridgeState.decisionPollDueAt = nil
        BridgeState.decisionPollTimerToken = nil
        BridgeState.lastDecisionPollStartedAt = BridgeDecisionPollNow()
        BridgeState.lastDecisionPollOutcome = "started"
        BridgePollForNextDecision(generation, attempt, allowCurrentDecision)
    end, nextDelay)
end

function BridgeYieldControllerMode()
    local ui = BridgeState.ui or {}
    if ui.fastForwardActive == true then return "fast_forward" end
    if ui.autoPassEmpty == true then return "auto_pass_empty" end
    return "normal"
end

function BridgeYieldPhaseKey(value)
    local phase = string.upper(tostring(value or ""))
    if string.find(phase, "UPKEEP", 1, true) then return "upkeep" end
    if string.find(phase, "DRAW", 1, true) then return "draw" end
    if string.find(phase, "MAIN", 1, true) then
        if string.find(phase, "POST", 1, true) or string.find(phase, "MAIN 2", 1, true) then return "main_postcombat" end
        return "main_precombat"
    end
    if string.find(phase, "BEGINNING", 1, true) and string.find(phase, "COMBAT", 1, true) then return "beginning_combat" end
    if string.find(phase, "ATTACK", 1, true) then return "declare_attackers" end
    if string.find(phase, "BLOCK", 1, true) then return "declare_blockers" end
    if string.find(phase, "DAMAGE", 1, true) then return "combat_damage" end
    if string.find(phase, "END OF COMBAT", 1, true) then return "end_combat" end
    if string.find(phase, "END", 1, true) then return "end_step" end
    return nil
end

function BridgeYieldScopeForDecision(decision)
    local active = decision and (decision.activeSeatId or decision.seatId) or BridgeState.currentTurnSeatId
    return active == "forge-player-1" and "own_turn" or "other_turn"
end

function BridgeYieldRecord(decision, disposition, reason, policy, action)
    if decision == nil or BridgeRecordDecisionLifecycle == nil then return end
    BridgeRecordDecisionLifecycle(decision, "yield-controller", disposition, reason,
        action and action.actionId or nil, action and action.type or nil, policy, reason)
end

function BridgeSetAutoPassEmpty(enabled, reason)
    local ui = BridgeState.ui
    if ui == nil then return end
    ui.autoPassEmpty = enabled == true
    if not ui.fastForwardActive then ui.autoAdvanceMode = ui.autoPassEmpty and "AUTO-PASS EMPTY" or "NORMAL" end
    BridgeSetStatus(ui.autoPassEmpty and "AUTO-PASS: EMPTY PRIORITY" or "NORMAL MODE",
        ui.autoPassEmpty and "Only pass-only human priority decisions will be submitted automatically." or "Every human Forge decision is presented normally.")
    BridgeUiMarkDirty("auto-pass-empty-" .. tostring(reason or "user"))
end

function BridgeToggleYieldPhaseStop(scope, phaseKey)
    local ui = BridgeState.ui
    if ui == nil or (scope ~= "own_turn" and scope ~= "other_turn") or phaseKey == nil then return end
    ui.fastForwardStops = ui.fastForwardStops or {own_turn = {}, other_turn = {}}
    local stops = ui.fastForwardStops[scope] or {}
    stops[phaseKey] = not (stops[phaseKey] == true)
    ui.fastForwardStops[scope] = stops
    BridgeUiMarkDirty("phase-stop-" .. scope .. "-" .. phaseKey)
end

function BridgeClearYieldPhaseStops()
    local ui = BridgeState.ui
    if ui == nil then return end
    ui.fastForwardStops = {own_turn = {}, other_turn = {}}
    BridgeUiMarkDirty("phase-stops-cleared")
end

function BridgeStartFastForward(reason)
    local ui = BridgeState.ui
    if ui == nil or BridgeState.gameEnded ~= nil then return end
    if BridgeState.schedulerOwner == "RESYNC" or BridgeState.resyncInFlight == true
        or BridgeState.bootstrapping == true then
        BridgeState.fastForwardSuspendedByResync = true
        BridgeLog("[Bridge] FAST_FORWARD_SUSPENDED reason=resync-active")
        return
    end
    ui.fastForwardActive = true
    ui.fastForwardSessionId = BridgeState.eventSessionId
    ui.fastForwardTurnNumber = tonumber(BridgeState.tableTurnCount or 0) or 0
    ui.fastForwardActiveSeatId = BridgeState.currentTurnSeatId
    ui.autoAdvanceMode = "FAST-FORWARD"
    BridgeSetStatus("FAST-FORWARD ACTIVE", "Stops at configured phase gates or any required human choice.")
    BridgeUiMarkDirty("fast-forward-started")
    BridgeLog("[Bridge] fast_forward_started reason=" .. tostring(reason or "user"))
    if BridgeState.eventSessionId ~= nil then
        if not BridgeState.eventPolling then BridgeStartEventPolling(BridgeState.eventSessionId, false) end
        if BridgeState.lastDecision == nil and not BridgeState.submitting then BridgeStartDecisionPolling() end
    end
    if BridgeState.lastDecision ~= nil then BridgeRenderDecision(BridgeState.lastDecision, true) end
end

function BridgeCancelFastForward(reason)
    local ui = BridgeState.ui
    if ui == nil or ui.fastForwardActive ~= true then return end
    ui.fastForwardActive = false
    ui.fastForwardSessionId = nil
    ui.fastForwardTurnNumber = nil
    ui.fastForwardActiveSeatId = nil
    ui.autoAdvanceMode = ui.autoPassEmpty and "AUTO-PASS EMPTY" or "NORMAL"
    BridgeSetStatus("FAST-FORWARD CANCELLED", tostring(reason or "user"))
    BridgeUiMarkDirty("fast-forward-cancelled")
    BridgeLog("[Bridge] fast_forward_cancelled reason=" .. tostring(reason or "user"))
end

function BridgeHudFastForward(player, value, id)
    if BridgeState.ui and BridgeState.ui.fastForwardActive then BridgeCancelFastForward("manual")
    else BridgeStartFastForward("manual") end
end

function BridgeHudYieldPhaseStop(player, value, id)
    local names = {
        Upkeep = "upkeep", Draw = "draw", MainPre = "main_precombat",
        BeginningCombat = "beginning_combat", Attackers = "declare_attackers",
        Blockers = "declare_blockers", Damage = "combat_damage",
        EndCombat = "end_combat", MainPost = "main_postcombat", EndStep = "end_step"
    }
    local raw = string.match(tostring(id or ""), "BridgeHudStop[^_]*_(.+)$")
    local scope = string.find(tostring(id or ""), "BridgeHudStopOwn_", 1, true) == 1 and "own_turn" or "other_turn"
    local phaseKey = names[raw]
    if phaseKey ~= nil then BridgeToggleYieldPhaseStop(scope, phaseKey) end
end

function BridgeHudClearYieldStops(player, value, id)
    BridgeClearYieldPhaseStops()
end

function BridgePollForNextDecision(generation, attempt, allowCurrentDecision)
    if BridgeState.gameEnded ~= nil then return end
    if BridgeState.schedulerOwner == "RESYNC" then return end
    if generation ~= BridgeState.decisionPollGeneration then return end
    if (BridgeState.lastDecision ~= nil and allowCurrentDecision ~= true) or BridgeState.submitting then return end
    if BridgeState.decisionPollInFlight then return end

    local expectedSessionId = BridgeState.eventSessionId
    local presentationGeneration = BridgeState.decisionPresentationGeneration
    BridgeState.decisionPollInFlight = true
    BridgeState.lastDecisionPollStartedAt = BridgeDecisionPollNow()
    BridgeHttp.requestJson("GET", "/api/v1/decision", nil, function(ok, body, err, request)
        if generation ~= BridgeState.decisionPollGeneration then return end
        if not ok and body ~= nil and body.errorCode == "session_not_started" then
            BridgeCleanupLocalSession("decision-no-session", BRIDGE_LIFECYCLE_READY_NO_SESSION)
            return
        end
        if expectedSessionId ~= BridgeState.eventSessionId
            or presentationGeneration ~= BridgeState.decisionPresentationGeneration then return end

        BridgeState.decisionPollInFlight = false
        BridgeState.lastDecisionPollCompletedAt = BridgeDecisionPollNow()
        if ok and body ~= nil then
            BridgeState.lastDecisionPollOutcome = "decision"
            BridgeState.decisionAuthoritativeWatermark = body.eventCursor
            BridgeMarkTransitionExpected(0)
            BridgeRecordLatencyProbeDecisionReady(body)
            BridgeAcceptDecision(body, "decision_poll", expectedSessionId, presentationGeneration)
            return
        end

        local responseCode = request and tonumber(request.response_code) or nil
        local noPendingDecision = (body ~= nil and body.errorCode == "no_pending_decision") or responseCode == 404
        if noPendingDecision then
            BridgeState.lastDecisionPollOutcome = "no_pending_decision"
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
            BridgeScheduleDecisionPoll(retryDelay, generation, attempt + 1, allowCurrentDecision)
            return
        end

        BridgeShowError("decision poll failed: " .. tostring(err))
        BridgeState.lastDecisionPollOutcome = "failed"
        BridgeScheduleDecisionPoll(1.0, generation, attempt + 1, allowCurrentDecision)
    end)
end

function BridgeStartDecisionPolling(allowCurrentDecision)
    if BridgeState.gameEnded ~= nil then return end
    if BridgeState.schedulerOwner == "RESYNC" then return end
    BridgeStopDecisionPolling()
    BridgeScheduleDecisionPoll(BridgeTransitionExpected() and 0.1 or 0.25,
        BridgeState.decisionPollGeneration, 1, allowCurrentDecision == true)
end

-- State-changing events can invalidate the currently rendered decision even
-- while it is still non-nil. Fetch exactly one authoritative replacement and
-- feed it through the normal decision acceptance/readiness path.
function BridgeRefreshDecisionAfterStateTransition(reason)
    if BridgeState.eventSessionId == nil or BridgeState.gameEnded ~= nil
        or BridgeState.desyncLatched or BridgeState.decisionRefreshInFlight then
        return
    end

    local expectedSessionId = BridgeState.eventSessionId
    local presentationGeneration = BridgeState.decisionPresentationGeneration
    BridgeState.decisionRefreshInFlight = true
    BridgeLog("[Bridge] requesting authoritative decision refresh reason=" .. tostring(reason))
    BridgeGetDecision(function(ok, body, err)
        if expectedSessionId ~= BridgeState.eventSessionId
            or presentationGeneration ~= BridgeState.decisionPresentationGeneration then
            BridgeState.decisionRefreshInFlight = false
            BridgeLog("[Bridge] ignored delayed transition decision refresh")
            return
        end

        BridgeState.decisionRefreshInFlight = false
        if ok and body ~= nil then
            BridgeAcceptDecision(body, "state_transition_refresh", expectedSessionId, presentationGeneration)
        else
            BridgeLog("[Bridge] state transition decision refresh failed: " .. tostring(err))
        end
    end)
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
        or kind == "mode_selection"
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

function BridgeIsMulliganBottomSelection(decision)
    return decision ~= nil and decision.kind == "mulligan"
        and tostring(decision.mulliganStage or "") == "bottom_selection"
        and decision.confirmRequired == true
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
    BridgeState.lastChoiceAttempt = {
        timestamp = os.clock(),
        decisionId = decisionId,
        actionId = actionId,
        source = source,
        transactionState = transactionState
    }
    BridgeLog(string.format(
        "[Bridge] choice-attempt=%s source=%s session=%s decision=%s action=%s submitting=%s transactionState=%s yieldSeat=%s",
        tostring(attempt), tostring(source or "unknown"), tostring(BridgeState.eventSessionId or "nil"),
        tostring(decisionId), tostring(actionId), tostring(BridgeState.submitting == true),
        tostring(transactionState or "none"), tostring(BridgeState.yieldPolicyActiveSeatId or "nil")))
    local decision = BridgeState.lastDecision
    if decision ~= nil and decision.decisionId == decisionId then
        local actionType = "unknown"
        for _, action in ipairs(decision.actions or {}) do
            if action.actionId == actionId then actionType = action.type or action.actionType or "unknown"; break end
        end
        local policy = string.find(tostring(source or ""), "own_turn_yield_auto_", 1, true) == 1 and "OWN_TURN_YIELD"
            or (source == "yield_policy_auto_pass" and "OPPONENT_YIELD"
                or (source == "auto_pass_empty" and "AUTO_PASS_EMPTY"
                    or (source == "fast_forward" and "FAST_FORWARD" or nil)))
        BridgeRecordDecisionLifecycle(decision, source, "CHOICE_ATTEMPT", "choice-submit",
            actionId, actionType, policy, "submitted")
    end
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
    if activeDecision == nil or activeDecision.decisionId ~= decisionId then
        return
    end
    if activeDecision ~= nil and activeDecision.decisionId == decisionId
        and activeDecision.kind == "main_priority"
        and activeDecision.seatId == "forge-player-1"
        and string.find(string.lower(tostring(activeDecision.phaseName or "")), "main", 1, true) ~= nil
        and actionId ~= nil
        and BridgeDecisionOffersActionType(activeDecision, "pass_priority")
        and (source == "empty_priority_auto_pass" or source == "yield_policy_auto_pass"
            or source == "auto_pass_empty" or source == "fast_forward"
            or string.find(tostring(source or ""), "auto_", 1, true) ~= nil)
        and source ~= "own_turn_yield_auto_pass" then
        BridgeRecordDecisionLifecycle(activeDecision, source, "AUTO_ACTION_BLOCKED",
            "HUMAN_MAIN1_AUTOPASS_BLOCKED", actionId, "pass_priority", "UNAUTHORIZED", "wrong-policy")
        BridgeLog("[Bridge] HUMAN_MAIN1_AUTOPASS_BLOCKED decision=" .. tostring(decisionId)
            .. " source=" .. tostring(source) .. " action=" .. tostring(actionId))
        return
    end
    local ownTurnYieldSource = string.find(tostring(source or ""), "own_turn_yield_auto_", 1, true) == 1
    if ownTurnYieldSource
        and (BridgeState.yieldPolicyOwnTurn ~= true
            or BridgeState.yieldPolicySessionId ~= BridgeState.eventSessionId
            or BridgeState.yieldPolicyActiveSeatId ~= BridgeState.currentTurnSeatId
            or (tonumber(BridgeState.yieldPolicyTurnNumber or 0) or 0) ~= (tonumber(BridgeState.tableTurnCount or 0) or 0)) then
        BridgeRecordDecisionLifecycle(activeDecision, source, "AUTO_ACTION_BLOCKED",
            "own-turn-yield-policy-no-longer-authorized", actionId, "unknown", "OWN_TURN_YIELD", "stale-policy")
        BridgeLog("[Bridge] own-turn yield action blocked: policy is no longer authoritative")
        return
    end
    local activeActionType = "unknown"
    for _, action in ipairs(activeDecision.actions or {}) do
        if action.actionId == actionId then activeActionType = action.type or action.actionType or "unknown"; break end
    end
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
        actionType = activeActionType,
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
    BridgeRecordDecisionLifecycle(activeDecision, source, "CHOICE_POST", "choice-post",
        actionId, transaction.actionType, string.find(tostring(transaction.source or ""), "own_turn_yield_auto_", 1, true) == 1 and "OWN_TURN_YIELD"
            or (transaction.source == "yield_policy_auto_pass" and "OPPONENT_YIELD"
                or (transaction.source == "auto_pass_empty" and "AUTO_PASS_EMPTY"
                    or (transaction.source == "fast_forward" and "FAST_FORWARD" or nil))), "posted")
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
            local rejectedDecision = BridgeState.lastDecision
            if rejectedDecision ~= nil and rejectedDecision.decisionId == decisionId then
                BridgeRecordDecisionLifecycle(rejectedDecision, activeTransaction.source, "CHOICE_REJECTED",
                    tostring(body and body.errorCode or err or "request-failed"), actionId,
                    activeTransaction.actionType, nil, "rejected")
            end
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
        local acceptedDecision = BridgeState.lastDecision
        if acceptedDecision ~= nil and acceptedDecision.decisionId == decisionId then
            BridgeRecordDecisionLifecycle(acceptedDecision, activeTransaction.source, "CHOICE_ACCEPTED",
                "forge-accepted", actionId, activeTransaction.actionType, nil, "accepted")
        end
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
                    or BridgeIsDiscardChoice(body.currentDecision)
                    or body.currentDecision.kind == "attacker_selection"
                    or body.currentDecision.kind == "blocker_selection"
                    or body.currentDecision.kind == "blocker_assignment") then
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
    BridgeState.lastDecision = nil
    BridgeState.pendingDecision = nil
    BridgeClearHighlights()
    BridgeRollbackPendingIntent()
    BridgeResetSelectionState()
    BridgeHideMainPriorityControls()
    BridgeStopDecisionPolling()
    BridgeStopEventPolling("stale-session-recovery")
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

function BridgeActionPresentationAuthorized(action)
    if action == nil then return false end
    if action.isPresentationAuthorized == false then return false end
    local provenance = action.provenance or {}
    if provenance.isPresentationAuthorized == false then return false end
    -- Older producers did not carry authorization metadata. Library identity
    -- is hidden by default, so never render it without an explicit grant.
    local sourceZone = string.lower(tostring(action.sourceZone or provenance.sourceZone or ""))
    if sourceZone == "library" then
        return action.isPresentationAuthorized == true
            or provenance.isPresentationAuthorized == true
    end
    return true
end

function BridgeDecisionHasUnauthorizedPresentationAction(decision)
    for _, action in ipairs((decision and decision.actions) or {}) do
        if not BridgeActionPresentationAuthorized(action) then return true end
    end
    return false
end

function BridgeDecisionHasNonPassAction(decision)
    for _, action in ipairs((decision and decision.actions) or {}) do
        if action.type ~= "pass_priority" and BridgeActionPresentationAuthorized(action) then return true end
    end
    return false
end

-- Keep phase-family normalization shared by stale-decision checks and
-- diagnostics. It is descriptive only; Forge remains legality authority.
function BridgePriorityPhaseFamily(value)
    local phase = string.upper(tostring(value or ""))
    if phase == "" then return "" end
    if string.find(phase, "UPKEEP", 1, true) then return "UPKEEP" end
    if string.find(phase, "DRAW", 1, true) then return "DRAW" end
    if string.find(phase, "MAIN", 1, true) then return "MAIN" end
    if string.find(phase, "ATTACK", 1, true)
        or string.find(phase, "BLOCK", 1, true)
        or string.find(phase, "DAMAGE", 1, true)
        or string.find(phase, "COMBAT", 1, true) then return "COMBAT" end
    if string.find(phase, "CLEANUP", 1, true) then return "CLEANUP" end
    if string.find(phase, "END", 1, true) then return "END" end
    return phase
end

function BridgeShouldIgnoreStaleDecision(decision)
    local eventCursor = tonumber(decision and decision.eventCursor or 0) or 0
    local applied = tonumber(BridgeState.lastAppliedEventSequence or 0) or 0
    local decisionForgeSequence = tonumber(decision and decision.forgeSequence or 0) or 0
    local appliedForgeSequence = tonumber(BridgeState.lastAppliedForgeSequence or 0) or 0
    if decisionForgeSequence > 0 and appliedForgeSequence > 0
        and decisionForgeSequence < appliedForgeSequence then
        BridgeLog(string.format(
            "[Bridge] ignoring stale decision %s due to forgeSequence ordering decision=%s applied=%s",
            tostring(decision and decision.decisionId), tostring(decisionForgeSequence), tostring(appliedForgeSequence)))
        return true, eventCursor, applied
    end
    if eventCursor < 1 or eventCursor >= applied then
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

    -- A same-turn priority menu can still be returned by a delayed poll after
    -- the authoritative phase event has already been applied. Keeping that
    -- menu would make an Upkeep pass look current and can carry the game
    -- straight past Main 1. Decision phase metadata never advances or
    -- regresses BridgeState.currentPhase; when its cursor is stale it is only
    -- used as a contradiction check. Coarse families keep Forge labels such
    -- as "Main phase, precombat" and "Main 1" equivalent.
    -- A pass-only menu from an older phase is never actionable, even when
    -- the decision and phase event happen to share the same cursor.  That
    -- race was allowing an Upkeep/DRAW pass to be submitted after Main 1 had
    -- already become authoritative, effectively consuming the Main 1 window.
    -- A menu carrying a real Forge action remains eligible to bridge the
    -- short event-publication gap; legality is still Forge-owned.
    -- Keep the phase-family normalization local to this stale-decision
    -- comparison so the guard remains self-contained and easy to audit.
    local function phaseFamily(value)
        return BridgePriorityPhaseFamily(value)
    end
    local decisionFamily = BridgePriorityPhaseFamily(decision.phaseName)
    local authoritativeFamily = BridgePriorityPhaseFamily(BridgeState.currentPhase)
    local contradictoryPassOnly = decisionFamily ~= "" and authoritativeFamily ~= ""
        and decisionFamily ~= authoritativeFamily
        and not BridgeDecisionHasNonPassAction(decision)
    if (eventCursor > 0 and eventCursor < applied) or contradictoryPassOnly then
        if decisionFamily ~= "" and authoritativeFamily ~= ""
            and decisionFamily ~= authoritativeFamily then
            -- Forge can publish the first Main 1 menu (including a legal land
            -- or sorcery action) with the prior draw/upkeep event cursor while
            -- its event stream catches up.  Discarding that menu makes the
            -- bridge look as if upkeep jumped straight to combat.  A stale
            -- pass-only menu is still unsafe and is retired; a menu carrying
            -- an exact meaningful Forge action is authoritative enough to
            -- present and submit.  Legality remains entirely Forge-owned.
            if not BridgeDecisionHasNonPassAction(decision) then
                -- Legacy diagnostic wording retained for contract readers:
                -- "ignoring stale pass-only priority menu".
                BridgeLog(string.format(
                    "[Bridge] ignoring stale main-priority pass-only decision phase=%s authoritativePhase=%s cursor=%s applied=%s",
                    tostring(decision.phaseName), tostring(BridgeState.currentPhase),
                    tostring(eventCursor), tostring(applied)))
                return true, eventCursor, applied
            end
            BridgeLog(string.format(
                -- Legacy diagnostic wording: "retaining regenerated Forge action menu".
                "[Bridge] retaining stale main-priority decision with Forge action phase=%s authoritativePhase=%s cursor=%s applied=%s",
                tostring(decision.phaseName), tostring(BridgeState.currentPhase),
                tostring(eventCursor), tostring(applied)))
        end
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

-- Empty cursor handling remains explicit in the stale-decision policy:
-- if eventCursor <= 0, no cross-domain ordering comparison is possible.
function BridgeShouldDeferDecision(decision)
    local openingMulligan = decision ~= nil and decision.kind == "mulligan"
        and tostring(decision.mulliganStage or "") == "keep_or_mulligan"
    local function globalPhysicalQueueBusy()
        for seatId, _ in pairs(BRIDGE_SEATS or {}) do
            if BridgeState.libraryExtractionActiveBySeatId[seatId] == true
                or #(BridgeState.libraryExtractionQueueBySeatId[seatId] or {}) > 0
                or BridgeState.mulliganBottomInsertionActiveBySeatId[seatId] == true
                or #(BridgeState.mulliganBottomQueueBySeatId[seatId] or {}) > 0 then
                return true, seatId
            end
        end
        return false, nil
    end
    local busy, busySeatId = globalPhysicalQueueBusy()
    if busy then
        return true, tonumber(decision and decision.eventCursor or 0) or 0,
            tonumber(BridgeState.lastAppliedEventSequence or 0) or 0,
            "physical_transition_pending_global",
            "seat=" .. tostring(busySeatId)
    end
    -- A decision can arrive before the tail of its own Forge mutation group is
    -- physically committed. Keep that decision non-actionable until every
    -- queued event in the same forgeSequence is embodied.
    if decision ~= nil then
        local decisionForgeSequence = tonumber(decision.forgeSequence or 0) or 0
        if decisionForgeSequence > 0 then
            for _, queued in ipairs(BridgeState.eventQueue or {}) do
                local queuedForgeSequence = tonumber(queued and queued.forgeSequence or 0) or 0
                if queuedForgeSequence == decisionForgeSequence then
                    return true, tonumber(decision.eventCursor or 0) or 0,
                        tonumber(BridgeState.lastAppliedEventSequence or 0) or 0,
                        "causal_dependency_pending",
                        "forgeSequence=" .. tostring(decisionForgeSequence)
                            .. " queuedEvent=" .. tostring(queued.sequence)
                end
            end
        end
    end
    -- Forge can produce the next priority menu before the bridge event poll
    -- has received the matching draw. Do not reveal or make actionable a
    -- hand-source action until its exact instance has an exact physical card
    -- in the chooser's live TTS hand. This is stronger than event-cursor
    -- ordering: the menu itself can legitimately carry an older cursor while
    -- already reflecting Forge's newly drawn hand.
    if not openingMulligan and decision ~= nil and decision.seatId ~= nil then
        local handGuids, handError = BridgeBuildSeatHandGuidSet(decision.seatId)
        for _, action in ipairs(decision.actions or {}) do
            if string.lower(tostring(action.sourceZone or "")) == "hand" then
                local instanceId = action.preparedSourceCardInstanceId
                    or action.sourceCardInstanceId or action.cardInstanceId
                local guid = instanceId and BridgeState.physicalByInstanceId[instanceId] or nil
                if instanceId == nil or guid == nil
                    or BridgeState.physicalInstanceIdByGuid[guid] ~= instanceId
                    or handGuids[guid] ~= true then
                    return true, tonumber(decision.eventCursor or 0) or 0,
                        tonumber(BridgeState.lastAppliedEventSequence or 0) or 0,
                        "hand_action_readiness",
                        string.format("instance=%s guid=%s hand=%s error=%s",
                            tostring(instanceId), tostring(guid), tostring(handGuids[guid] == true), tostring(handError))
                end
            end
        end
    end
    -- A draw is authoritative before its physical Deck extraction callback
    -- completes. Do not expose a priority menu whose new hand card cannot yet
    -- be embodied; otherwise the player can pass a stale menu and only then
    -- see the card/action refresh. The extraction completion path releases
    -- and rerenders the same Forge decision after the exact card is in hand.
    if not openingMulligan and decision ~= nil and decision.seatId ~= nil then
        local extractionQueue = BridgeState.libraryExtractionQueueBySeatId[decision.seatId]
        if BridgeState.libraryExtractionActiveBySeatId[decision.seatId] == true
            or (extractionQueue ~= nil and #extractionQueue > 0) then
            return true, tonumber(decision.eventCursor or 0) or 0,
                tonumber(BridgeState.lastAppliedEventSequence or 0) or 0
        end
    end

    -- Do not show KEEP/MULLIGAN until the exact opening-hand draws from Forge's
    -- authoritative snapshot is physically settled in the human's TTS hand.
    -- This deliberately uses the snapshot identities, not a hard-coded hand
    -- size or the transient extraction queue length.
    if openingMulligan then
        if BridgeState.openingHandReadinessDecisionId ~= decision.decisionId then
            BridgeState.openingHandReadinessDecisionId = decision.decisionId
            BridgeState.openingHandReadinessSnapshotPending = true
            BridgeState.openingHandReadinessSnapshotRequested = false
        end
        if BridgeState.openingHandReadinessSnapshotPending then
            return true, tonumber(decision.eventCursor or 0) or 0,
                tonumber(BridgeState.lastAppliedEventSequence or 0) or 0,
                "opening_hand_readiness", "waiting for authoritative opening-hand snapshot"
        end
        local ready, readyCount, expectedCount, readinessDetail =
            BridgeCheckOpeningHandReadiness(decision.seatId)
        if not ready then
            return true, tonumber(decision.eventCursor or 0) or 0,
                tonumber(BridgeState.lastAppliedEventSequence or 0) or 0,
                "opening_hand_readiness",
                string.format("ready=%d expected=%d missing=%s", readyCount, expectedCount, readinessDetail)
        end
    end
    local eventCursor = tonumber(decision and decision.eventCursor or 0) or 0
    local applied = math.max(
        tonumber(BridgeState.lastAppliedEventSequence or 0) or 0,
        tonumber(BridgeState.lastStateProjectedEventSequence or 0) or 0)
    if eventCursor <= 0 then return false, eventCursor, applied end
    return eventCursor > applied, eventCursor, applied
end

function BridgeScheduleOpeningHandReadinessRetry()
    if BridgeState.openingHandReadinessRetryScheduled then return end
    BridgeState.openingHandReadinessRetryScheduled = true
    BridgeWaitFrames(function()
        BridgeState.openingHandReadinessRetryScheduled = false
        if BridgeState.pendingDecision ~= nil and not BridgeState.submitting then
            BridgeTryPresentPendingDecision("opening-hand-readiness-retry")
        end
    end, BRIDGE_OPENING_HAND_READINESS_RETRY_FRAMES)
end

function BridgeScheduleHandActionReadinessRetry()
    if BridgeState.handActionReadinessRetryScheduled then return end
    BridgeState.handActionReadinessRetryScheduled = true
    BridgeWaitFrames(function()
        BridgeState.handActionReadinessRetryScheduled = false
        if BridgeState.pendingDecision ~= nil and not BridgeState.submitting then
            BridgeTryPresentPendingDecision("hand-action-readiness-retry")
        end
    end, BRIDGE_OPENING_HAND_READINESS_RETRY_FRAMES)
end

-- A readiness timeout is not, by itself, evidence that Forge and TTS disagree.
-- Mulligan replacement cards can be present in the authoritative snapshot while
-- TTS is still finishing Deck/Card callbacks.  Recover from that transient
-- state with an exact-session snapshot refresh, then (once) a full
-- authoritative rebuild.  The decision is never fabricated and the bounded
-- attempt ledger prevents an endless retry loop.
function BridgeRecoverFromHandReadinessTimeout(decision, deferReason, detail)
    local decisionId = decision and decision.decisionId or nil
    local sessionId = BridgeState.eventSessionId
    if decisionId == nil or sessionId == nil then return false end
    if BridgeState.handReadinessRecoveryDecisionId ~= decisionId
        or BridgeState.handReadinessRecoverySessionId ~= sessionId then
        BridgeState.handReadinessRecoveryDecisionId = decisionId
        BridgeState.handReadinessRecoverySessionId = sessionId
        BridgeState.handReadinessRecoveryAttempts = 0
    end
    local attempts = (BridgeState.handReadinessRecoveryAttempts or 0) + 1
    BridgeState.handReadinessRecoveryAttempts = attempts
    BridgeState.pendingDecisionDeferredAt = os.clock()
    BridgeState.pendingDecisionDeferredCursor = tonumber(decision.eventCursor or 0) or 0
    BridgeState.pendingDecisionDeferredApplied = tonumber(BridgeState.lastAppliedEventSequence or 0) or 0
    BridgeLog(string.format(
        "[Bridge] hand readiness timeout is recoverable decision=%s reason=%s attempt=%d/%d session=%s detail=%s",
        tostring(decisionId), tostring(deferReason), attempts,
        BRIDGE_HAND_READINESS_RECOVERY_ATTEMPTS, tostring(sessionId), tostring(detail)))

    if attempts < BRIDGE_HAND_READINESS_RECOVERY_ATTEMPTS then
        -- Keep the exact Forge decision pending while refreshing the snapshot;
        -- no local selection or physical move is performed.
        BridgeState.openingHandReadinessSnapshotRequested = false
        BridgeState.openingHandReadinessSnapshotPending = true
        BridgeScheduleSnapshotReconcile("hand-readiness-timeout")
        if deferReason == "opening_hand_readiness" then
            BridgeScheduleOpeningHandReadinessRetry()
        else
            BridgeScheduleHandActionReadinessRetry()
        end
        return true
    end

    -- A second timeout means the ordinary snapshot refresh did not settle the
    -- physical hand. Rebuild from Forge's current snapshot and resume polling;
    -- this is still recoverable and is intentionally not a guessed card bind.
    if BridgeState.resyncInFlight ~= true then
        BridgeResyncFromAuthoritativeSnapshot("hand-readiness-timeout")
        return true
    end
    return true
end

function BridgeTryPresentPendingDecision(reason)
    if BridgeState.pendingDecision == nil or BridgeState.submitting then return end
    local pending = BridgeState.pendingDecision
    local defer, eventCursor, applied, deferReason, deferDetail = BridgeShouldDeferDecision(pending)
    if defer then
        local deferredAt = tonumber(BridgeState.pendingDecisionDeferredAt or 0) or 0
        if deferredAt <= 0 then deferredAt = os.clock() end
        local elapsed = os.clock() - deferredAt
        if deferReason == "opening_hand_readiness" then
            BridgeState.pendingDecisionDeferredAt = deferredAt
            BridgeState.pendingDecisionDeferredCursor = eventCursor
            BridgeState.pendingDecisionDeferredApplied = applied
            if not BridgeState.openingHandReadinessSnapshotRequested then
                BridgeState.openingHandReadinessSnapshotRequested = true
                BridgeState.openingHandReadinessSnapshotPending = true
                BridgeScheduleSnapshotReconcile("opening-hand-readiness")
            end
            if elapsed >= BRIDGE_OPENING_HAND_READINESS_TIMEOUT_SECONDS then
                local ready, readyCount, expectedCount, readinessDetail =
                    BridgeCheckOpeningHandReadiness(pending.seatId)
                if ready then
                    -- The readiness reason was captured before TTS published
                    -- all hand membership callbacks.  Re-evaluate the full
                    -- decision now that the exact hand is ready; otherwise a
                    -- stale defer reason can stop a valid seven-card opening
                    -- hand with ready=expected in the diagnostic.
                    BridgeState.openingHandReadinessSnapshotPending = false
                    BridgeLog(string.format(
                        "[Bridge] opening hand readiness recovered: ready=%d expected=%d; re-evaluating decision",
                        readyCount, expectedCount))
                    BridgeTryPresentPendingDecision(reason .. "-readiness-recovered")
                    return
                end
                if BridgeRecoverFromHandReadinessTimeout(pending, deferReason, string.format(
                    "ready=%d expected=%d missing=%d mappings=%s",
                    readyCount, expectedCount, math.max(expectedCount - readyCount, 0), readinessDetail)) then
                    return
                end
                BridgeStopOnDesync(string.format(
                    "opening hand readiness timeout: ready=%d expected=%d missing=%d mappings=%s",
                    readyCount, expectedCount, math.max(expectedCount - readyCount, 0), readinessDetail))
                return
            end
            BridgeLog(string.format(
                "[Bridge] holding opening mulligan decision %s: %s",
                tostring(pending.decisionId), tostring(deferDetail)))
            BridgeScheduleOpeningHandReadinessRetry()
            return
        end
        if deferReason == "hand_action_readiness" then
            BridgeState.pendingDecisionDeferredAt = deferredAt
            BridgeState.pendingDecisionDeferredCursor = eventCursor
            BridgeState.pendingDecisionDeferredApplied = applied
            -- Keep a discard/bottoming transaction visible through the HUD
            -- while exact hand GUIDs finish converging.  The HUD submits only
            -- the exact Forge ActionId; physical cards remain inert until
            -- their identity mapping is verified.  Without this fallback a
            -- post-mulligan hand race looked like "no discard prompt" and
            -- could never be recovered by the player.
            if BridgeIsDiscardChoice(pending) or BridgeIsMulliganBottomSelection(pending) then
                BridgeState.lastDecision = pending
                BridgeUiMarkDirty("hand-action-readiness-fallback")
                BridgeRenderDecision(pending, true)
            end
            -- Mulligan replacement cards can leave the next hand-based
            -- discard/cast menu one polling cycle ahead of its physical TTS
            -- mappings. Request one exact-session snapshot immediately so
            -- readiness converges without waiting for the long timeout.
            if BridgeState.handActionReadinessSnapshotDecisionId ~= pending.decisionId
                or BridgeState.handActionReadinessSnapshotSessionId ~= BridgeState.eventSessionId then
                BridgeState.handActionReadinessSnapshotDecisionId = pending.decisionId
                BridgeState.handActionReadinessSnapshotSessionId = BridgeState.eventSessionId
                BridgeScheduleSnapshotReconcile("hand-action-readiness")
            end
            if elapsed >= BRIDGE_OPENING_HAND_READINESS_TIMEOUT_SECONDS then
                if BridgeRecoverFromHandReadinessTimeout(pending, deferReason, deferDetail) then
                    return
                end
                BridgeStopOnDesync("hand action readiness timeout: " .. tostring(deferDetail))
                return
            end
            BridgeLog(string.format(
                "[Bridge] holding decision %s until exact hand action is embodied: %s",
                tostring(pending.decisionId), tostring(deferDetail)))
            BridgeScheduleHandActionReadinessRetry()
            return
        end
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
            -- Retiring a stale deferred menu must not strand the protocol.
            -- Poll again for the exact current Forge decision after the
            -- event/physical-mapping fence has been observed.
            BridgeStartDecisionPolling()
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
    -- Exact land/spell/card events are already the authoritative physical
    -- delta. Full snapshots are recovery authority only; routine verification
    -- here used to repaint the whole table after every ordinary mutation.
    local transition = event ~= nil and event.kind == "card_moved"
        and BridgeState.pendingStructuredZoneTransitionByInstanceId[event.cardInstanceId] or nil
    return transition ~= nil and transition.applied ~= true
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

-- A snapshot is authoritative for the resulting public zone, but it does not
-- carry the physical source of a card that was already public. In particular,
-- a missing graveyard/battlefield mapping must not be guessed as a library
-- extraction: during a burst such as Thought Scour (mill, mill, draw), that
-- would take the current library top by name and can pull a land or a card
-- which was already milled back out of the deck. Only an exact transition
-- which is still pending/in-flight may supply a source zone for a synthetic
-- snapshot repair.
function BridgeFindAuthoritativeSnapshotTransitionSourceZone(cardInstanceId, destinationZone)
    if cardInstanceId == nil or destinationZone == nil then return nil end
    local pending = BridgeState.pendingStructuredZoneTransitionByInstanceId[cardInstanceId]
    if pending ~= nil and tostring(pending.destinationZone or "") == tostring(destinationZone)
        and pending.sourceZone ~= nil and tostring(pending.sourceZone) ~= "" then
        return pending.sourceZone
    end
    for _, queued in ipairs(BridgeState.eventQueue or {}) do
        if queued ~= nil
            and queued.cardInstanceId == cardInstanceId
            and tostring(queued.destinationZone or "") == tostring(destinationZone)
            and queued.sourceZone ~= nil and tostring(queued.sourceZone) ~= "" then
            return queued.sourceZone
        end
    end
    return nil
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

-- A snapshot can be authoritative while its physical library transitions are
-- still being embodied.  Applying it during a Thought Scour-style burst lets
-- bootstrap/reconcile extract a same-name card from the current Deck top,
-- racing the exact queued mill/draw operations.  Keep snapshot mutation
-- deferred until every seat's ordered library queue is idle.
function BridgePhysicalLibraryQueuesIdle()
    for seatId, _ in pairs(BRIDGE_SEATS or {}) do
        if BridgeState.libraryBatchBySeatId[seatId] ~= nil
            and BridgeState.libraryBatchBySeatId[seatId].active == true then
            return false
        end
        if BridgeState.libraryExtractionActiveBySeatId[seatId] == true
            or #(BridgeState.libraryExtractionQueueBySeatId[seatId] or {}) > 0
            or BridgeState.mulliganBottomInsertionActiveBySeatId[seatId] == true
            or #(BridgeState.mulliganBottomQueueBySeatId[seatId] or {}) > 0 then
            return false
        end
    end
    return true
end

function BridgeSnapshotRequestCategory(reason, category)
    if category ~= nil then return string.upper(tostring(category)) end
    local text = string.lower(tostring(reason or ""))
    if string.find(text, "final", 1, true) or string.find(text, "game_ended", 1, true) then return "FINAL" end
    if string.sub(text, 1, 6) == "event " then return "ROUTINE_VERIFY" end
    return "RECOVERY"
end

function BridgeEventBacklogCount()
    local received = tonumber(BridgeState.lastReceivedEventSequence or 0) or 0
    local applied = tonumber(BridgeState.lastAppliedEventSequence or 0) or 0
    return math.max(#(BridgeState.eventQueue or {}), math.max(0, received - applied))
end

function BridgeRoutineSnapshotBlocked()
    return BridgeEventBacklogCount() > 0 or BridgeState.animationRunning == true
end

function BridgeSnapshotRequestPriority(category)
    if category == "FINAL" then return 3 end
    if category == "RECOVERY" then return 2 end
    return 1
end

function BridgeRememberSnapshotRequest(reason, category)
    BridgeState.snapshotReconcileRequestGeneration = (BridgeState.snapshotReconcileRequestGeneration or 0) + 1
    local request = {
        reason = reason,
        category = category,
        generation = BridgeState.snapshotReconcileRequestGeneration
    }
    local prior = BridgeState.snapshotReconcilePendingRequest
    if prior == nil or BridgeSnapshotRequestPriority(category) >= BridgeSnapshotRequestPriority(prior.category) then
        -- Routine requests are latest-wins. Recovery/final requests retain
        -- priority over a routine request arriving in the same burst.
        BridgeState.snapshotReconcilePendingRequest = request
    end
    BridgeState.snapshotReconcilePending = true
end

function BridgeTryStartPendingSnapshotReconcile(reason)
    local request = BridgeState.snapshotReconcilePendingRequest
    if request == nil or BridgeState.snapshotReconcileInFlight then return false end
    if request.category == "ROUTINE_VERIFY" and BridgeRoutineSnapshotBlocked() then return false end
    BridgeState.snapshotReconcilePendingRequest = nil
    BridgeState.snapshotReconcilePending = false
    BridgeScheduleSnapshotReconcile(request.reason or reason or "pending", request.category)
    return true
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
    local queueBefore = #(BridgeState.eventQueue or {})
    local receivedBefore = tonumber(BridgeState.lastReceivedEventSequence or 0) or 0
    local appliedBefore = tonumber(BridgeState.lastAppliedEventSequence or 0) or 0
    local scansBefore = tonumber(BridgeState.presentationMetrics and BridgeState.presentationMetrics.worldScanCount or 0) or 0
    BridgePerformanceTrace("snapshot_reconcile.queue_lag_before", nil,
        math.max(0, receivedBefore - appliedBefore), queueBefore)
    BridgePresentationMetric("fullSnapshotReconcileCount")
    local pending = BridgeState.pendingDecision
    local requiredSeatId = pending ~= nil and pending.kind == "mulligan"
        and tostring(pending.mulliganStage or "") == "keep_or_mulligan"
        and pending.seatId or nil
    local handToken = BridgePerformanceBegin("snapshot_reconcile.hand_identity")
    BridgeRecordExpectedHandIdentities(snapshot, requiredSeatId)
    BridgePerformanceEnd(handToken, "snapshot_reconcile.hand_identity.end", "snapshotReconcileHandIdentity")
    local monarchToken = BridgePerformanceBegin("snapshot_reconcile.monarch")
    BridgeSetMonarchSeat(snapshot and snapshot.monarchSeatId or nil)
    BridgePerformanceEnd(monarchToken, "snapshot_reconcile.monarch.end", "snapshotReconcileMonarch")
    local stackToken = BridgePerformanceBegin("snapshot_reconcile.stack")
    BridgeState.stackSummary = {}
    BridgeState.stackObjects = snapshot and snapshot.stackObjects or {}
    for _, stackObject in ipairs(snapshot and snapshot.stackObjects or {}) do
        local source = tostring(stackObject.sourceName or "Forge source")
        local kind = tostring(stackObject.stackKind or "stack object")
        local text = tostring(stackObject.abilityText or stackObject.abilityName or "")
        table.insert(BridgeState.stackSummary, source .. " — " .. kind .. (text ~= "" and (": " .. text) or ""))
    end
    for _, card in ipairs(snapshot and snapshot.stack or {}) do
        if #(snapshot and snapshot.stackObjects or {}) == 0 then
            table.insert(BridgeState.stackSummary, tostring(card.currentCardName or card.cardName or "Forge stack object"))
        end
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
    BridgeUiMarkDirty("stack")
    BridgePerformanceEnd(stackToken, "snapshot_reconcile.stack.end", "snapshotReconcileStack")
    local publicZoneToken = BridgePerformanceBegin("snapshot_reconcile.public_zone_diff")
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
                    local strandedAtStack = zoneName == "battlefield"
                        and mappedObject ~= nil and mappedObject.tag == "Card"
                        and BridgePhysicalObjectAtStackAnchor(mappedObject)
                    local mappedNeedsFix = mappedObject == nil or mappedObject.tag ~= "Card" or mappedZone ~= zoneName
                        or (snapshotRow ~= nil and priorRow ~= snapshotRow)
                        or strandedAtStack
                    if strandedAtStack then
                        BridgeTracePermanentTransition(
                            "SNAPSHOT_ZONE battlefield", {
                                cardInstanceId = card.cardInstanceId,
                                seatId = seatSnapshot.seatId,
                                sourceZone = mappedZone,
                                destinationZone = zoneName,
                                sequence = snapshot.forgeSequence
                            }, mappedObject, mappedZone, "physical object remains at stack anchor")
                    end
                    if mappedNeedsFix then
                        -- The log intentionally omits cardName: a snapshot can
                        -- contain identities that should not be public chat.
                        -- A public card absent from the reverse mapping has no
                        -- trustworthy physical source in a snapshot alone.
                        -- Never assume library here: a Thought Scour-style
                        -- mill/draw burst can otherwise extract the wrong top
                        -- card (including a land or an already-milled card).
                        -- The exact queued transition, when present, is the
                        -- only safe source for a synthetic repair.
                        local snapshotSourceZone = mappedObject ~= nil
                            and mappedObject.tag == "Card" and mappedZone or nil
                        if snapshotSourceZone == nil then
                            snapshotSourceZone = BridgeFindAuthoritativeSnapshotTransitionSourceZone(
                                card.cardInstanceId, zoneName)
                        end
                        BridgeLog(string.format(
                            "[Bridge] snapshot candidate instance=%s oldZone=%s destinationZone=%s",
                            tostring(card.cardInstanceId), tostring(mappedZone), tostring(zoneName)))
                        if snapshotSourceZone == nil then
                            BridgeLog(string.format(
                                "[Bridge] snapshot candidate deferred instance=%s destinationZone=%s: no exact source transition",
                                tostring(card.cardInstanceId), tostring(zoneName)))
                        else
                            local evt = {
                                seatId = seatSnapshot.seatId,
                                cardInstanceId = card.cardInstanceId,
                                cardName = card.cardName,
                                sourceZone = snapshotSourceZone,
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
        local seatVisualToken = BridgePerformanceBegin("snapshot_reconcile.seat_visual")
        BridgeApplySeatSnapshotVisualState(seatSnapshot)
        BridgePerformanceEnd(seatVisualToken, "snapshot_reconcile.seat_visual.end", "snapshotReconcileSeatVisual")
    end
    BridgePerformanceEnd(publicZoneToken, "snapshot_reconcile.public_zone_diff.end", "snapshotReconcilePublicZoneDiff", movedCount)
    local combatToken = BridgePerformanceBegin("snapshot_reconcile.combat")
    BridgeApplyCombatSnapshot(snapshot.combat)
    BridgePerformanceEnd(combatToken, "snapshot_reconcile.combat.end", "snapshotReconcileCombat")
    -- Snapshot reconciliation is also recovery authority for the turn
    -- pipeline. These values come directly from Forge; they never advance a
    -- phase or infer legality in Lua.
    local turnStateToken = BridgePerformanceBegin("snapshot_reconcile.turn_state")
    local snapshotCursor = tonumber(snapshot and snapshot.eventCursor or 0) or 0
    local projectedCursor = tonumber(BridgeState.lastStateProjectedEventSequence
        or BridgeState.lastAppliedEventSequence or 0) or 0
    local mayProjectTurnState = snapshotCursor >= projectedCursor
    if mayProjectTurnState then
        if snapshot.turnNumber ~= nil then BridgeState.tableTurnCount = snapshot.turnNumber end
        if snapshot.activeSeatId ~= nil then BridgeState.currentTurnSeatId = snapshot.activeSeatId end
        if snapshot.prioritySeatId ~= nil then BridgeState.prioritySeatId = snapshot.prioritySeatId end
        if snapshot.phase ~= nil and tostring(snapshot.phase) ~= "" then
            BridgeState.currentPhase = snapshot.phase
        end
    else
        BridgeLog(string.format("[Bridge] retaining newer event projection over older snapshot cursor=%s projected=%s",
            tostring(snapshotCursor), tostring(projectedCursor)))
    end
    BridgeUiMarkDirty("authoritative-snapshot-turn-state")
    BridgeState.snapshotForgeSequence = snapshot.forgeSequence or BridgeState.snapshotForgeSequence
    if BridgeRestoreAuthoritativeReveals ~= nil then BridgeRestoreAuthoritativeReveals(snapshot) end
    BridgeState.snapshotReconcileLastAppliedCursor = snapshotCursor
    BridgeState.snapshotReconcileLastAppliedGeneration = BridgeState.snapshotReconcileRequestGeneration or 0
    BridgeState.snapshotReconcileLastAppliedCategory = BridgeSnapshotRequestCategory(reason)
    BridgePerformanceEnd(turnStateToken, "snapshot_reconcile.turn_state.end", "snapshotReconcileTurnState")
    local receivedAfter = tonumber(BridgeState.lastReceivedEventSequence or 0) or 0
    local appliedAfter = tonumber(BridgeState.lastAppliedEventSequence or 0) or 0
    local queueAfter = #(BridgeState.eventQueue or {})
    local scansAfter = tonumber(BridgeState.presentationMetrics and BridgeState.presentationMetrics.worldScanCount or 0) or 0
    BridgePerformanceTrace("snapshot_reconcile.queue_lag_after", nil,
        math.max(0, receivedAfter - appliedAfter), queueAfter)
    BridgeLogSnapshotOrdering("applied", snapshot, reason)
    BridgeLog(string.format(
        "[Bridge] snapshot reconcile metrics cursor=%s received=%s applied=%s queueBefore=%s queueAfter=%s reason=%s corrected=%s physicalCorrection=%s worldScans=%s",
        tostring(snapshot.eventCursor), tostring(receivedAfter), tostring(appliedAfter), tostring(queueBefore),
        tostring(queueAfter), tostring(reason), tostring(movedCount), tostring(movedCount > 0), tostring(scansAfter - scansBefore)))
    if movedCount > 0 then
        BridgeLog(string.format("[Bridge] snapshot reconcile (%s): corrected %d public card location(s)", tostring(reason), movedCount))
    end
end

function BridgeTryApplyDeferredSnapshotReconcile(reason)
    local pending = BridgeState.deferredSnapshotReconcile
    if pending == nil or not BridgeSnapshotMayMutatePublicZones(pending.snapshot)
        or not BridgePhysicalLibraryQueuesIdle() then return false end
    if pending.category == "ROUTINE_VERIFY" and BridgeRoutineSnapshotBlocked() then
        return false
    end
    local snapshotCursor = tonumber(pending.snapshot and pending.snapshot.eventCursor or 0) or 0
    if pending.category == "ROUTINE_VERIFY"
        and snapshotCursor <= tonumber(BridgeState.snapshotReconcileLastAppliedCursor or 0) then
        BridgeState.deferredSnapshotReconcile = nil
        BridgeLogSnapshotOrdering("skipped-superseded", pending.snapshot, pending.reason or reason)
        return false
    end
    BridgeState.deferredSnapshotReconcile = nil
    BridgeState.pendingStructuredZoneTransitionByInstanceId = {}
    BridgeApplySafeSnapshotReconcile(pending.snapshot, pending.reason or reason or "deferred")
    return true
end

function BridgeScheduleSnapshotReconcile(reason, category)
    if BridgeState.eventSessionId == nil then return end
    category = BridgeSnapshotRequestCategory(reason, category)
    if category == "ROUTINE_VERIFY" and BridgeRoutineSnapshotBlocked() then
        BridgeRememberSnapshotRequest(reason, category)
        BridgeLog("[Bridge] routine snapshot held behind event drain reason=" .. tostring(reason)
            .. " backlog=" .. tostring(BridgeEventBacklogCount()))
        return
    end
    if BridgeState.snapshotReconcileInFlight then
        BridgeRememberSnapshotRequest(reason, category)
        return
    end
    BridgeState.snapshotReconcileInFlight = true
    local requestGeneration = (BridgeState.snapshotReconcileRequestGeneration or 0) + 1
    BridgeState.snapshotReconcileRequestGeneration = requestGeneration
    BridgeGetEmbodimentSnapshot(function(ok, snapshot, err)
        BridgeState.snapshotReconcileInFlight = false
        if ok and snapshot ~= nil and snapshot.sessionId == BridgeState.eventSessionId then
            local pending = BridgeState.pendingDecision
            local requiredSeatId = pending ~= nil and pending.kind == "mulligan"
                and tostring(pending.mulliganStage or "") == "keep_or_mulligan"
                and pending.seatId or nil
            local hasHandIdentities = BridgeRecordExpectedHandIdentities(snapshot, requiredSeatId)
            if not hasHandIdentities then
                BridgeState.openingHandReadinessSnapshotRequested = false
                BridgeLog("[Bridge] opening-hand-readiness snapshot contained no exact hand identities; retrying")
            end
            local snapshotCursor = tonumber(snapshot.eventCursor or 0) or 0
            local alreadyCovered = category == "ROUTINE_VERIFY"
                and snapshotCursor <= tonumber(BridgeState.snapshotReconcileLastAppliedCursor or 0)
            local canApply = not alreadyCovered
                and BridgeSnapshotMayMutatePublicZones(snapshot)
                and BridgePhysicalLibraryQueuesIdle()
                and (category ~= "ROUTINE_VERIFY" or not BridgeRoutineSnapshotBlocked())
            if canApply then
                BridgeApplySafeSnapshotReconcile(snapshot, reason)
            elseif alreadyCovered then
                BridgeLogSnapshotOrdering("skipped-superseded", snapshot, reason)
            else
                local prior = BridgeState.deferredSnapshotReconcile
                if prior == nil or BridgeSnapshotRequestPriority(category) >= BridgeSnapshotRequestPriority(prior.category) then
                    -- Keep one latest useful payload. Never let an older routine
                    -- response replace an explicit recovery snapshot.
                    BridgeState.deferredSnapshotReconcile = {
                        snapshot = snapshot,
                        reason = reason,
                        category = category,
                        generation = requestGeneration
                    }
                end
                local queueState = BridgePhysicalLibraryQueuesIdle() and "event-cursor" or "physical-library-queue"
                BridgeLogSnapshotOrdering("deferred-" .. queueState, snapshot, reason)
            end
        elseif not ok then
            BridgeLog("[Bridge] snapshot reconcile failed: " .. tostring(err))
        elseif snapshot ~= nil then
            BridgeLog("[Bridge] snapshot reconcile skipped due to session mismatch")
        end

        if BridgeState.pendingDecision ~= nil then
            BridgeTryPresentPendingDecision("snapshot-reconcile")
        end

        BridgeTryStartPendingSnapshotReconcile("pending")
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

    local startup = BridgeState.startupTrace
    local healthDispatchToken = nil
    if startup ~= nil and not startup.healthDispatchRecorded then
        startup.healthDispatchRecorded = true
        healthDispatchToken = BridgeStartupStageBegin("startup_bridge_health_begin")
    end
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

        local discoveryToken = nil
        if startup ~= nil and not startup.objectDiscoveryRecorded then
            startup.objectDiscoveryRecorded = true
            discoveryToken = BridgeStartupStageBegin("startup_object/bootstrap_discovery_begin")
        end
        BridgeDoctorCheckTable(report, body)
        BridgeStartupStageEnd(discoveryToken, "startup_object/bootstrap_discovery_end",
            "objectDiscoveryDurationMs")
        BridgeDoctorPrintReport(report)
        if done ~= nil then done(report) end
    end)
    BridgeStartupStageEnd(healthDispatchToken, "startup_bridge_health_dispatched",
        "healthDispatchDurationMs")
end

function BridgeInitializeInteractiveUi()
    if BridgeState.doctorInitializedUi then return end
    BridgeState.doctorInitializedUi = true
    local startupUiToken = BridgeStartupStageBegin("startup_ui_begin")
    BridgeWaitFrames(function()
        local cleanupToken = BridgeStartupStageBegin("startup_transient_cleanup_begin")
        BridgeTryStartupStep("destroy_transient_controls", BridgeDestroyTransientControls)
        BridgeStartupStageEnd(cleanupToken, "startup_transient_cleanup_end",
            "transientCleanupDurationMs")
        BridgeTryStartupStep("ensure_setup_controls", BridgeEnsureSetupControls)
        BridgeTryStartupStep("ensure_turn_counters", BridgeEnsureTurnCounters)
        BridgeTryStartupStep("ensure_status_panel", BridgeEnsureStatusPanel)
        BridgeTryStartupStep("show_preparation_readiness", BridgeShowPreparationReadiness)
        BridgeStartupStageEnd(startupUiToken, "startup_ui_end", "uiDurationMs")
        BridgeLogStartupSummary()
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
    BridgePerformanceTrace("BridgeOnLoad_enter")
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
    if not BridgeGuardLifecycleCommand("START_MATCH") then return end
    BridgeSetSetupBusy(true, "Forge match is loading; START and RESUME are temporarily disabled.")
    BridgeSetupStage("CONTACTING_BRIDGE", "checking bridge health")
    BridgeTraceStart("START-03 health-request")
    BridgeGetHealth(function(ok, body, err)
        BridgeRunTraced("START-04 health-response", function()
            BridgeTraceStart("START-04 health-response", ok and "ok" or tostring(err))
            if not ok then
                BridgeSetSetupBusy(false)
                BridgeSetupFailure("bridge-health", err)
                BridgeShowError("cannot start: companion unavailable: " .. tostring(err))
                return
            end
            if body.adapterState == "starting" then
                BridgeSetSetupBusy(true, "Forge is still initializing; wait for startup to finish before starting a new match.")
                BridgeSetStatus("FORGE INITIALIZING", "Loading Forge card database")
                return
            end
            local active = body.sessionId ~= nil and body.sessionId ~= "session-not-started"
                and body.adapterState ~= "not_started" and body.adapterState ~= "failed"
            if active then BridgeSetSetupBusy(false); BridgeShowError("a Forge match already exists; use RESUME or explicitly choose NEW MATCH"); return end
            BridgeSetupStage("READING_DECKS", "scanning both configured piles")
            BridgeTraceStart("START-05 deck-check-begin")
            local humanDeck, humanCandidates = BridgeResolveSeatLibraryDeck("forge-player-1")
            local aiDeck, aiCandidates = BridgeResolveSeatLibraryDeck("forge-player-2")
            if humanDeck == nil or aiDeck == nil or #humanCandidates > 1 or #aiCandidates > 1 then
                BridgeSetSetupBusy(false)
                BridgeSetupFailure("deck-reading", "both physical library decks must be uniquely identifiable before START")
                BridgeShowError("both physical library decks must be uniquely identifiable before START")
                return
            end
            local preflightOk, preflightError = BridgeStartMatchPreflight(humanDeck, aiDeck)
            if not preflightOk then
                BridgeSetSetupBusy(false)
                BridgeSetupFailure("start-preflight", preflightError)
                BridgeShowError("START MATCH refused: " .. tostring(preflightError) .. ". Use NEW MATCH to clean existing session objects.")
                return
            end
            BridgeSetupTrace("SETUP_STATE_VALIDATED", "deck piles uniquely identified")
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
    if not BridgeGuardLifecycleCommand("RESUME_MATCH") then return end
    -- RESUME is a continuation operation, not an attach/bootstrap operation.
    -- An active session already owns its event cursor and physical mappings;
    -- routing it through BridgeAttachToActiveSession used the fresh-attach
    -- bootstrap path (BridgePrepareEventSession(..., true)), which reset a
    -- healthy cursor and rebuilt unrelated cards.  Classify the local state
    -- before considering authoritative recovery.
    if BridgeState.eventSessionId ~= nil
        and BridgeState.eventSessionId ~= "session-not-started"
        and BridgeState.lifecycleState ~= BRIDGE_LIFECYCLE_READY_NO_SESSION
        and BridgeState.lifecycleState ~= BRIDGE_LIFECYCLE_START_FAILED then
        BridgeResumeActiveSession("resume")
        return
    end
    BridgeShowError("RESUME requires an already-paused local session. Use START MATCH from clean setup or NEW MATCH for explicit teardown.")
end

function BridgeClassifyResumeState()
    if BridgeState.eventSessionId == nil or BridgeState.eventSessionId == "session-not-started" then
        return "SESSION_MISMATCH"
    end
    if BridgeState.lifecycleState == BRIDGE_LIFECYCLE_ENDING then return "MATCH_TEARDOWN_ACTIVE" end
    if BridgeState.resyncInFlight == true or BridgeState.bootstrapping == true then return "RECOVERY_ACTIVE" end
    local received = tonumber(BridgeState.lastReceivedEventSequence or 0) or 0
    local applied = tonumber(BridgeState.lastAppliedEventSequence or 0) or 0
    if received ~= applied or #(BridgeState.eventQueue or {}) > 0 then return "CURSOR_BEHIND" end
    if BridgeState.lastDecision ~= nil and BridgeDecisionPhysicalMappingsReady ~= nil then
        local ready, missing = BridgeDecisionPhysicalMappingsReady(BridgeState.lastDecision)
        if not ready then
            return "CURSOR_CURRENT_MAPPING_DEFECT", missing
        end
    end
    if BridgeState.desyncLatched == true then
        return "CURSOR_CURRENT_MAPPING_DEFECT", BridgeState.desyncLastMessage
    end
    if BridgeState.lastDecision ~= nil then return "PROTOCOL_PAUSED_AND_COHERENT" end
    return "PROTOCOL_PAUSED_AND_COHERENT"
end

function BridgeResumeActiveSession(reason)
    local classification, detail = BridgeClassifyResumeState()
    BridgeLog("[Bridge] RESUME_CLASSIFIED state=" .. tostring(classification)
        .. " detail=" .. tostring(detail) .. " session=" .. tostring(BridgeState.eventSessionId)
        .. " received=" .. tostring(BridgeState.lastReceivedEventSequence)
        .. " applied=" .. tostring(BridgeState.lastAppliedEventSequence))

    if classification == "MATCH_TEARDOWN_ACTIVE" or classification == "SESSION_MISMATCH" then
        BridgeShowError("RESUME is unavailable because no continuous active Forge session can be proven")
        return false
    end
    if classification == "RECOVERY_ACTIVE" then
        BridgeShowError("authoritative recovery is already in progress; use RESUME after it completes")
        return false
    end
    if classification == "CURSOR_BEHIND" then
        BridgeSetStatus("SYNCHRONIZING", "RESUME is waiting for the authoritative event checkpoint")
        if BridgeState.desyncLatched == true then
            BridgeEnsureDesyncRecovery("resume-cursor-behind")
        else
            -- A paused poller with queued authoritative work is not a new
            -- session. Resume its existing event session and let the normal
            -- ordered consumer catch up; only a latched desync escalates to
            -- snapshot recovery.
            BridgeStartEventPolling(BridgeState.eventSessionId, false)
            BridgeStartDecisionPolling(false)
        end
        return false
    end
    if classification == "CURSOR_CURRENT_MAPPING_DEFECT" then
        -- Never use the fresh-session bootstrap here.  The recovery scheduler
        -- owns any authoritative identity repair and its transaction preserves
        -- the committed cursor/mapping registry until a replacement is valid.
        BridgeLog("[Bridge] TARGETED_MAPPING_REPAIR_REQUESTED instance=" .. tostring(detail))
        BridgeSetStatus("MAPPING REPAIR", "Repairing only the missing authoritative physical identity")
        BridgeScheduleSnapshotReconcile("resume-targeted-mapping-repair", "RECOVERY")
        return false
    end

    BridgeResumeChoiceProtocol(reason or "resume-active-session")
    if BridgeStartEventPolling ~= nil then BridgeStartEventPolling(BridgeState.eventSessionId, false) end
    if BridgeState.lastDecision ~= nil then
        BridgeRenderDecision(BridgeState.lastDecision, true)
    else
        BridgeStartDecisionPolling(true)
    end
    BridgeSetSetupBusy(false)
    BridgeSetStatus("MATCH ACTIVE", "Resumed the existing Forge match without resetting its checkpoint")
    BridgeUiMarkDirty("resume-active-session")
    return true
end

function BridgePressNewMatch(object, playerColor, altClick)
    local color = playerColor
    local alt = altClick == true
    BridgeSetupTrace("TTS_NEW_MATCH_CLICKED", "player=" .. tostring(color or "unknown") .. " confirmed=" .. tostring(alt))
    BridgeSetStatus("NEW MATCH", alt and "Preparing match..." or "Click again to confirm")
    BridgeLog("setup-click:new-match")
    BridgeWaitFrames(function()
        BridgeRunSetupProtected("new-match-click", function() BridgeDoPressNewMatch(color, alt) end)
    end, 1)
end

function BridgeDoPressNewMatch(playerColor, altClick)
    BridgeLog("setup-deferred:new-match")
    if BridgeState.setupBusy then
        BridgeShowError("Forge is still initializing; wait for the loading controls to finish")
        return
    end
    if not BridgeGuardLifecycleCommand("NEW_MATCH") then return end
    BridgeSetupStage("SETUP_STATE_VALIDATED", "new-match confirmation path ready")
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
        BridgeRunSetupProtected("new-match-confirm", function() BridgeDoPressConfirmNewMatch(color, alt) end)
    end, 1)
end

function BridgeDoPressConfirmNewMatch(playerColor, altClick)
    BridgeLog("setup-deferred:confirm")
    if BridgeState.setupBusy then
        BridgeShowError("Forge is still initializing; wait for the loading controls to finish")
        return
    end
    if not BridgeGuardLifecycleCommand("CONFIRM_NEW_MATCH") then return end
    if not BridgeState.resetConfirmationArmed then
        BridgeShowError("NEW MATCH confirmation expired; click NEW MATCH again")
        BridgeClearResetConfirmationControl()
        return
    end
    BridgeState.resetConfirmationArmed = false
    BridgeClearResetConfirmationControl()
    BridgeSetupStage("SETUP_STATE_VALIDATED", "confirmed new-match request")
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

        if body.adapterState == "not_started" or body.sessionId == nil
            or body.sessionId == "session-not-started" then
            BridgeCleanupLocalSession("attach-no-session", BRIDGE_LIFECYCLE_READY_NO_SESSION)
        else
            BridgeFetchDecisionAfterAttach()
        end
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

    BridgeSetupStage("READING_DECKS", "building Bridge deck inventory")
    BridgeTraceStart("START-07 TTS-library-deck-load")
    BridgeConfigureDecks(function(deckOk, _, deckError)
        if not deckOk then
            if done then done() end
            BridgeSetupFailure("deck-reading", BridgeHttpFailureDetail(_, deckError))
            BridgeShowError("TTS library load failed: " .. BridgeHttpFailureDetail(_, deckError))
            return
        end
        BridgeSetupTrace("SESSION_START_REQUEST_BEGIN", "POST /api/v1/session/start")
        BridgeSetupStage("STARTING_FORGE", "requesting Forge session")
        BridgeTraceStart("START-07 session-start-request")
        BridgeStartSession(function(ok, body, err)
        BridgeRunTraced("START-08 session-start-response", function()
            BridgeTraceStart("START-08 session-start-response", ok and tostring(body and body.sessionId or "ok") or tostring(err))
            if not ok then
                if done then done() end
                BridgeSetLifecycleState(BRIDGE_LIFECYCLE_START_FAILED, "session-start-failed")
                BridgeSetupFailure("session-start", BridgeHttpFailureDetail(body, err))
                BridgeShowError("session start failed: " .. BridgeHttpFailureDetail(body, err))
                return
            end

            BridgeLog("[Bridge] started or attached session: " .. tostring(body and body.sessionId))
            BridgeState.sessionCleanupApplied = false
            BridgeSetLifecycleState(BRIDGE_LIFECYCLE_ACTIVE, "session-started")
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
    BridgeStopEventPolling("session-reset")
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
            BridgeState.sessionCleanupApplied = false
            BridgeSetLifecycleState(BRIDGE_LIFECYCLE_ACTIVE, "session-reset")
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
    local function reject(reason)
        return false, tostring(reason or "rejected")
    end
    local function defer(reason)
        return true, tostring(reason or "deferred")
    end

    if decision == nil then
        BridgeLog("[Bridge] DECISION_REJECT origin=" .. tostring(origin) .. " reason=missing_payload")
        return reject("missing_payload")
    end

    BridgeRecordDecisionLifecycle(decision, origin, "OBSERVED", "decision-payload")

    if expectedSessionId ~= nil and (expectedSessionId ~= BridgeState.eventSessionId
        or presentationGeneration ~= BridgeState.decisionPresentationGeneration) then
        BridgeRecordDecisionLifecycle(decision, origin, "REJECTED_STALE", "replaced-generation")
        BridgeLog("[Bridge] DECISION_REJECT origin=" .. tostring(origin) .. " reason=replaced_generation decision=" .. tostring(decision.decisionId))
        return reject("replaced_generation")
    end

    if decision.sessionId == nil or decision.sessionId ~= BridgeState.eventSessionId then
        BridgeRecordDecisionLifecycle(decision, origin, "REJECTED_STALE", "wrong-session")
        BridgeLog("[Bridge] DECISION_REJECT origin=" .. tostring(origin) .. " reason=wrong_session decision="
            .. tostring(decision.decisionId) .. " decisionSession=" .. tostring(decision.sessionId)
            .. " activeSession=" .. tostring(BridgeState.eventSessionId))
        return reject("wrong_session")
    end

    if BridgeState.retiredChoiceDecisionIds[decision.decisionId] == true
        or BridgeState.choiceTransactions[decision.decisionId] ~= nil then
        BridgeRecordDecisionLifecycle(decision, origin, "REJECTED_STALE", "decision-retired-or-submitting")
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
        return reject("decision_retired_or_submitting")
    end

    if BridgeState.lastDecision == nil or BridgeState.lastDecision.decisionId ~= decision.decisionId then
        local previousDecision = BridgeState.lastDecision
        if previousDecision ~= nil and previousDecision.decisionId ~= decision.decisionId
            and previousDecision.kind == "main_priority"
            and previousDecision.seatId == "forge-player-1"
            and string.find(string.lower(tostring(previousDecision.phaseName or "")), "main", 1, true) ~= nil
            and decision.kind == "attacker_selection"
            and BridgeState.choiceTransactions[previousDecision.decisionId] == nil
            and BridgeState.retiredChoiceDecisionIds[previousDecision.decisionId] ~= true then
            BridgeRecordDecisionLifecycle(previousDecision, "main1", "RETIRED",
                "advanced-to-attacker-without-choice")
            BridgeLog(string.format(
                "[Bridge] MAIN1_ADVANCED_WITHOUT_BRIDGE_CHOICE previousDecision=%s newDecision=%s previousCursor=%s newCursor=%s eventCursorDelta=%s lastChoiceDecision=%s lastChoiceAction=%s lastChoiceSource=%s",
                tostring(previousDecision.decisionId), tostring(decision.decisionId),
                tostring(previousDecision.eventCursor), tostring(decision.eventCursor),
                tostring((tonumber(decision.eventCursor or 0) or 0) - (tonumber(previousDecision.eventCursor or 0) or 0)),
                tostring(BridgeState.lastChoiceAttempt and BridgeState.lastChoiceAttempt.decisionId or nil),
                tostring(BridgeState.lastChoiceAttempt and BridgeState.lastChoiceAttempt.actionId or nil),
                tostring(BridgeState.lastChoiceAttempt and BridgeState.lastChoiceAttempt.source or nil)))
        end
        BridgeCreatureTypeClearDraft("decision-replaced")
        BridgeGraveyardClear("decision-replaced")
        -- A card context is only a convenience filter for the decision in
        -- which it was opened. Retaining it after Forge changes decisions can
        -- hide newly drawn legal cards and the next Main 1 action list.
        if BridgeState.ui ~= nil then BridgeState.ui.contextInstanceId = nil end
    end

    BridgeRetireChoiceTransactionsForDecision(decision.decisionId)

    local ignoreStale, eventCursor, applied = BridgeShouldIgnoreStaleDecision(decision)
    if ignoreStale then
        BridgeRecordDecisionLifecycle(decision, origin, "REJECTED_STALE", "stale-event-cursor")
        BridgeLog(string.format(
            "[Bridge] ignoring stale decision %s kind=%s (cursor=%s, applied=%s)",
            tostring(decision.decisionId), tostring(decision.kind), tostring(eventCursor), tostring(applied)))
        -- A stale poll response is not a terminal state.  The GET that
        -- delivered it has already completed, so simply returning would
        -- leave the bridge with no current decision and Forge would continue
        -- advancing its priority windows.  Start a fresh poll against the
        -- current event/session generation; only that newer Forge decision
        -- may replace the stale one.
        -- If this was the menu currently rendered, retire it before polling;
        -- otherwise a newer menu is already authoritative and must remain.
        if BridgeState.lastDecision == nil
            or BridgeState.lastDecision.decisionId == decision.decisionId then
            BridgeState.lastDecision = nil
            BridgeClearHighlights()
            BridgeHideMainPriorityControls()
            if BridgeRecordStaleDecisionConvergence(decision, eventCursor, applied) then
                local retryDelay = BridgeState.staleDecisionRetryCount == 1 and 0.1
                    or math.min(0.1 * (BridgeState.staleDecisionRetryCount or 1), BRIDGE_STALE_DECISION_CONVERGENCE_SECONDS / 6)
                BridgeScheduleDecisionPoll(retryDelay, BridgeState.decisionPollGeneration, 1, false)
            end
        end
        return reject("stale_event_cursor")
    end

    -- The producer must never turn Forge's private library inspection into a
    -- human-visible option. Fail safely before action rows, tooltips, or
    -- physical controls can expose an unapproved identity.
    if BridgeDecisionHasUnauthorizedPresentationAction(decision) then
        BridgeLog("[Bridge] stopped: Forge supplied an unapproved hidden-zone action")
        BridgeStopOnDesync("Forge supplied an unapproved hidden-zone action; presentation paused safely")
        return reject("unauthorized_hidden_zone_action")
    end

    local deferDecision, deferCursor, deferApplied, deferReason = BridgeShouldDeferDecision(decision)
    if deferDecision then
        BridgeRecordDecisionLifecycle(decision, origin,
            deferReason == "opening_hand_readiness" and "DEFERRED_HAND_READINESS" or "DEFERRED_CURSOR",
            deferReason)
        BridgeState.pendingDecision = decision
        -- A pending decision is not yet presentation-safe.  In particular, a
        -- post-draw menu can describe a card whose extraction from the
        -- library has not completed. Keeping it as lastDecision lets the HUD
        -- render those action rows even though physical interaction is gated.
        -- Keep the decision only in the private pending slot until the exact
        -- embodiment/event cursor gate releases it.
        BridgeState.lastDecision = nil
        BridgeState.pendingDecisionDeferredAt = os.clock()
        BridgeState.pendingDecisionDeferredCursor = deferCursor
        BridgeState.pendingDecisionDeferredApplied = deferApplied
        BridgeClearHighlights()
        BridgeResetSelectionState()
        BridgeHideMainPriorityControls()
        BridgeUiMarkDirty("decision-deferred")
        BridgeLog(string.format(
            "[Bridge] gating decision %s until events catch up (cursor=%s, applied=%s)",
            tostring(decision.decisionId), tostring(deferCursor), tostring(deferApplied)))
        if deferReason == "opening_hand_readiness" then
            BridgeScheduleOpeningHandReadinessRetry()
        end
        return defer(deferReason)
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
    -- corroborating hint and must not overwrite the phase event stream. The
    -- initial decision may seed an otherwise-uninitialized display, but once
    -- any authoritative phase is known, a poll response can never move it.
    local decisionPhase = tostring(decision.phaseName or "")
    local decisionCursor = tonumber(decision.eventCursor or 0) or 0
    local appliedCursor = tonumber(BridgeState.lastAppliedEventSequence or 0) or 0
    if decisionPhase ~= "" and BridgeState.currentPhase == nil
        and (decisionCursor <= 0 or decisionCursor >= appliedCursor) then
        BridgeState.currentPhase = decisionPhase
    elseif decisionPhase ~= "" then
        BridgeLog(string.format("[Bridge] retaining event phase=%s over stale decision phase=%s cursor=%s applied=%s",
            tostring(BridgeState.currentPhase), decisionPhase, tostring(decisionCursor), tostring(appliedCursor)))
    end
    if decision.prioritySeatId ~= nil then
        BridgeState.prioritySeatId = decision.prioritySeatId
    end

    BridgeState.lastDecision = decision
    BridgeRecordDecisionLifecycle(decision, origin, "ACCEPTED", "authoritative-current")
    if BridgeCheckProjectionCoherence ~= nil then
        BridgeCheckProjectionCoherence(decision, "decision-accepted")
    end
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
    elseif BridgeIsDiscardChoice(decision) then
        if decision.decisionCauseKind == "cleanup_hand_size" then
            BridgeSetStatus("DISCARD TO MAXIMUM HAND SIZE", "Choose " .. tostring(decision.minSelections or 1) .. " card(s) from your hand.")
        elseif decision.decisionCauseKind == "spell_or_ability" then
            BridgeSetStatus("DISCARD " .. tostring(decision.minSelections or 1) .. " CARD", "Caused by: " .. tostring(decision.sourceCardName or "Forge spell or ability"))
        else
            BridgeSetStatus("DISCARD", "Choose Forge's legal discard card(s), then CONFIRM.")
        end
    elseif decision.kind == "mulligan"
        and tostring(decision.mulliganStage or "") == "bottom_selection" then
        BridgeSetStatus("MULLIGAN — PUT CARD ON BOTTOM",
            "Choose " .. tostring(decision.minSelections or 1) .. " card(s) to put on the bottom of your library, then CONFIRM.")
    elseif decision.kind == "card_selection" then
        BridgeSetStatus("CHOOSE CARD", "Required Forge selection (this is not a cast action)")
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
    BridgeState.decisionAwaitingCausallyCurrent = false
    BridgeState.staleDecisionRetryKey = nil
    BridgeState.staleDecisionRetryCount = 0
    BridgeState.staleDecisionRetryStartedAt = nil
    BridgeState.staleDecisionRetryDeadlineAt = nil

    BridgeRenderDecision(decision)
    BridgeRecordDecisionLifecycle(decision, origin, "RENDERED", "decision-accepted")

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
    return true, "accepted"
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
    -- Clearing is itself a presentation invalidation. This keeps a later
    -- render from being skipped after an event or interaction removed the
    -- currently rendered highlight set.
    BridgeAdvancePhysicalPresentationGeneration("highlights-cleared")
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
        local skip = not BridgeActionPresentationAuthorized(action)
        if skip then BridgeLog("[Bridge] suppressed unauthorized hidden-zone option control") end
        if not skip then skip = filters[action.actionId] == true end
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
