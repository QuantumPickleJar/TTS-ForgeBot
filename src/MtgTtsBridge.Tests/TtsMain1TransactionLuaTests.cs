using MoonSharp.Interpreter;

namespace MtgTtsBridge.Tests;

public sealed class TtsMain1TransactionLuaTests
{
    private static readonly string Script = File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.lua"));

    [Theory]
    [InlineData("SMART")]
    [InlineData("MANUAL")]
    [InlineData("YIELD")]
    public void ExactForgeMain1DecisionWithPlayLand_IsNotAutomaticallyPassed(string mode)
    {
        var lua = new Script();
        lua.DoString(@"
            function log(message) end
            function broadcastToAll(message, color) end
            function printToAll(message, color) end
            function getAllObjects() return {} end
            function getObjectFromGUID(guid) return nil end
            function getObjectsWithTag(tag) return {} end
            Wait = {time = function(callback, delay) end, frames = function(callback, frames) end}
            Time = {time = 0}
            JSON = {encode = function(value) return '{}'; end, decode = function(value) return {}; end}
            os = {time = function() return 1 end, clock = function() return 0 end}
            math.random = function(minimum, maximum) return 123456 end
            table.concat = function(values, separator) return 'probe-runtime' end
        ");
        lua.DoString(Script);
        lua.DoString($@"
            BridgeState.eventSessionId = 'probe-session'
            BridgeState.decisionPresentationGeneration = 1
            BridgeState.retiredChoiceDecisionIds = {{}}
            BridgeState.choiceTransactions = {{}}
            BridgeState.lastDecision = nil
            BridgeState.pendingDecision = nil
            BridgeState.lastAppliedEventSequence = 10
            BridgeState.lastReceivedEventSequence = 10
            BridgeState.eventQueue = {{}}
            BridgeState.animationRunning = false
            BridgeState.snapshotReconcileInFlight = false
            BridgeState.tableTurnCount = 1
            BridgeState.currentTurnSeatId = 'forge-player-1'
            BridgeState.currentPhase = 'Main phase, precombat'
            BridgeState.physicalByInstanceId = {{['forge:probe:46'] = 'hand-guid'}}
            BridgeState.physicalInstanceIdByGuid = {{['hand-guid'] = 'forge:probe:46'}}
            BridgeState.physicalSeatByGuid = {{['hand-guid'] = 'forge-player-1'}}
            BridgeState.physicalZoneByGuid = {{['hand-guid'] = 'hand'}}
            BridgeState.ui = {{mounted = true, autoAdvanceMode = '{mode}'}}
            BRIDGE_SEATS['forge-player-1'] = {{ttsColor = 'White'}}
            function BridgeBuildSeatHandGuidSet(seatId) return {{['hand-guid'] = true}} end
            function BridgeTryGetSeatHandObjects(seatId) return {{}} end
            function BridgeRefreshTurnCounterLabels() end
            function BridgeSetStatus(title, subtitle) end
            function BridgeClearHighlights() end
            function BridgeRenderPreparedSpellPresentations(decision) end
            function BridgeResetSelectionState() end
            function BridgeEnsureSelectionControls(decision) end
            function BridgeEnsureContextualCompletionControl(decision) end
            function BridgeHideMainPriorityControls() end
            function BridgeEnsureDecisionOptionControls(decision, representedActionIds) end
            function BridgeUiMarkDirty(reason) end
            submitCalls = 0
            function BridgeSubmitChoice(decisionId, actionId, source) submitCalls = submitCalls + 1 end
            decision = {{
                decisionId = 'forge-tui-main1',
                sessionId = 'probe-session',
                kind = 'main_priority',
                seatId = 'forge-player-1',
                activeSeatId = 'forge-player-1',
                prioritySeatId = 'forge-player-1',
                phaseName = 'Main phase, precombat',
                turnNumber = 1,
                eventCursor = 10,
                actions = {{
                    {{actionId = 'forge-tui-main1-choice-0', type = 'pass_priority', displayName = 'Pass priority', isPresentationAuthorized = true}},
                    {{actionId = 'forge-tui-main1-choice-1', type = 'play_land', displayName = 'Play land: Mountain', cardIdentity = 'Mountain', cardInstanceId = 'forge:probe:46', sourceCardInstanceId = 'forge:probe:46', sourceZone = 'hand', isPresentationAuthorized = true}}
                }}
            }}
            BridgeAcceptDecision(decision, 'lua-main1-probe', 'probe-session', 1)
        ");

        Assert.Equal(0, lua.Globals.Get("submitCalls").Number);
        var bridgeState = lua.Globals.Get("BridgeState").Table;
        var lastDecision = bridgeState.Get("lastDecision").Table;
        Assert.Equal("forge-tui-main1", lastDecision.Get("decisionId").String);
        var actions = lastDecision.Get("actions").Table;
        Assert.Equal(2, actions.Length);
        lua.DoString("probeHasPlayLand = false; for _, action in ipairs(BridgeState.lastDecision.actions) do if action.type == 'play_land' then probeHasPlayLand = true end end");
        Assert.True(lua.Globals.Get("probeHasPlayLand").Boolean);
        lua.DoString(@"
            probeObserved = false
            probeAccepted = false
            probeRendered = false
            for _, record in ipairs(BridgeState.decisionLifecycle) do
                if record.decisionId == 'forge-tui-main1' and record.disposition == 'OBSERVED' then probeObserved = true end
                if record.decisionId == 'forge-tui-main1' and record.disposition == 'ACCEPTED' then probeAccepted = true end
                if record.decisionId == 'forge-tui-main1' and record.disposition == 'RENDERED' then probeRendered = true end
            end
        ");
        Assert.True(lua.Globals.Get("probeObserved").Boolean);
        Assert.True(lua.Globals.Get("probeAccepted").Boolean);
        Assert.True(lua.Globals.Get("probeRendered").Boolean);
        if (mode == "YIELD") Assert.Null(lua.Globals.Get("BridgeState").Table.Get("yieldPolicyTurnNumber").ToObject());
    }
}
