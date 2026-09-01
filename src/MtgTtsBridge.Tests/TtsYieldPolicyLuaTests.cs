using MoonSharp.Interpreter;

namespace MtgTtsBridge.Tests;

public sealed class TtsYieldPolicyLuaTests
{
    private static readonly string Source = File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.lua"));

    [Fact]
    public void OwnTurnYieldPassesMainPriorityEvenWhenOptionalActionsExist()
    {
        var lua = NewProbe(true, "forge-player-1");
        lua.DoString(@"
            decision = {
                decisionId='own-main', sessionId='session', kind='main_priority',
                seatId='forge-player-1', activeSeatId='forge-player-1', prioritySeatId='forge-player-1',
                turnNumber=1, phaseName='Main phase, precombat', eventCursor=10,
                actions={
                    {actionId='pass-1', type='pass_priority', isPresentationAuthorized=true},
                    {actionId='land-1', type='play_land', isPresentationAuthorized=true},
                    {actionId='spell-1', type='cast_spell', isPresentationAuthorized=true},
                    {actionId='ability-1', type='activate_ability', isPresentationAuthorized=true}
                }
            }
            BridgeRenderDecision(decision, true)
        ");

        Assert.Equal("pass-1", lua.Globals.Get("submittedAction").String);
        Assert.Equal("own_turn_yield_auto_pass", lua.Globals.Get("submittedSource").String);
        Assert.Equal("YIELD", lua.Globals.Get("BridgeState").Table.Get("ui").Table.Get("autoAdvanceMode").String);
    }

    [Fact]
    public void OwnTurnYieldFinishesAttackingWithForgeCompletionAction()
    {
        var lua = NewProbe(true, "forge-player-1");
        lua.DoString(@"
            decision = {
                decisionId='own-attackers', sessionId='session', kind='attacker_selection',
                seatId='forge-player-1', activeSeatId='forge-player-1', prioritySeatId='forge-player-1',
                turnNumber=1, phaseName='Combat, declare attackers', eventCursor=11,
                actions={
                    {actionId='attacker-1', type='choose_attacker', isPresentationAuthorized=true, isSelected=true},
                    {actionId='finish-1', type='finish_attacking', isPresentationAuthorized=true}
                }
            }
            BridgeRenderDecision(decision, true)
        ");

        Assert.Equal("finish-1", lua.Globals.Get("submittedAction").String);
        Assert.Equal("own_turn_yield_auto_finish_attacking", lua.Globals.Get("submittedSource").String);
    }

    [Theory]
    [InlineData("target_selection")]
    [InlineData("payment_option")]
    [InlineData("blocker_selection")]
    public void OwnTurnYieldStopsAtStructuredHumanChoice(string kind)
    {
        var lua = NewProbe(true, "forge-player-1");
        lua.DoString($@"
            decision = {{
                decisionId='mandatory', sessionId='session', kind='{kind}',
                seatId='forge-player-1', activeSeatId='forge-player-1', prioritySeatId='forge-player-1',
                turnNumber=1, phaseName='Main phase, precombat', eventCursor=12,
                actions={{{{actionId='choice-1', type='choose_target', isPresentationAuthorized=true}}}}
            }}
            BridgeRenderDecision(decision, true)
        ");

        Assert.Null(lua.Globals.Get("submittedAction").ToObject());
        Assert.Null(lua.Globals.Get("BridgeState").Table.Get("yieldPolicyTurnNumber").ToObject());
    }

    [Fact]
    public void OpponentYieldStillStopsForAResponseAction()
    {
        var lua = NewProbe(false, "forge-player-2");
        lua.DoString(@"
            decision = {
                decisionId='opponent-response', sessionId='session', kind='main_priority',
                seatId='forge-player-1', activeSeatId='forge-player-2', prioritySeatId='forge-player-1',
                turnNumber=1, phaseName='Main phase, precombat', eventCursor=13,
                actions={
                    {actionId='pass-2', type='pass_priority', isPresentationAuthorized=true},
                    {actionId='response-1', type='cast_spell', isPresentationAuthorized=true}
                }
            }
            BridgeRenderDecision(decision, true)
        ");

        Assert.Null(lua.Globals.Get("submittedAction").ToObject());
        Assert.Null(lua.Globals.Get("BridgeState").Table.Get("yieldPolicyTurnNumber").ToObject());
    }

    [Fact]
    public void YieldBackpressureBlocksOwnTurnAutomaticAction()
    {
        var lua = NewProbe(true, "forge-player-1");
        lua.DoString(@"
            BridgeState.lastReceivedEventSequence = 20
            BridgeState.lastAppliedEventSequence = 10
            decision = {
                decisionId='backpressured', sessionId='session', kind='main_priority',
                seatId='forge-player-1', activeSeatId='forge-player-1', prioritySeatId='forge-player-1',
                turnNumber=1, phaseName='Main phase, precombat', eventCursor=20,
                actions={{actionId='pass-3', type='pass_priority', isPresentationAuthorized=true}}
            }
            BridgeRenderDecision(decision, true)
        ");

        Assert.Null(lua.Globals.Get("submittedAction").ToObject());
        Assert.Equal(1, lua.Globals.Get("BridgeState").Table.Get("yieldPolicyTurnNumber").Number);
    }

    [Fact]
    public void AutoPassEmpty_PassesOnlyAForgePassOnlyHumanPriority()
    {
        var lua = NewProbe(false, "forge-player-1");
        lua.DoString(@"
            BridgeState.ui.autoAdvanceMode = 'AUTO-PASS EMPTY'
            BridgeState.ui.autoPassEmpty = true
            BridgeState.yieldPolicyTurnNumber = nil
            decision = {
                decisionId='empty-priority', sessionId='session', kind='main_priority',
                seatId='forge-player-1', activeSeatId='forge-player-1', prioritySeatId='forge-player-1',
                turnNumber=1, phaseName='Upkeep', eventCursor=10,
                actions={{actionId='pass-empty', type='pass_priority', isPresentationAuthorized=true}}
            }
            BridgeRenderDecision(decision, true)
        ");

        Assert.Equal("pass-empty", lua.Globals.Get("submittedAction").String);
        Assert.Equal("auto_pass_empty", lua.Globals.Get("submittedSource").String);
    }

    [Fact]
    public void AutoPassEmpty_LeavesMain1LegalActionVisible()
    {
        var lua = NewProbe(false, "forge-player-1");
        lua.DoString(@"
            BridgeState.ui.autoAdvanceMode = 'AUTO-PASS EMPTY'
            BridgeState.ui.autoPassEmpty = true
            decision = {
                decisionId='main-land', sessionId='session', kind='main_priority',
                seatId='forge-player-1', activeSeatId='forge-player-1', prioritySeatId='forge-player-1',
                turnNumber=1, phaseName='Main phase, precombat', eventCursor=10,
                actions={
                    {actionId='pass-main', type='pass_priority', isPresentationAuthorized=true},
                    {actionId='land-main', type='play_land', isPresentationAuthorized=true}
                }
            }
            BridgeRenderDecision(decision, true)
        ");

        Assert.Null(lua.Globals.Get("submittedAction").ToObject());
        Assert.True(lua.Globals.Get("BridgeState").Table.Get("ui").Table.Get("autoPassEmpty").Boolean);
    }

    [Fact]
    public void FastForward_SubmitsOptionalMainPriorityUsingExactPassAction()
    {
        var lua = NewProbe(false, "forge-player-1");
        lua.DoString(@"
            BridgeState.ui.autoAdvanceMode = 'FAST-FORWARD'
            BridgeState.ui.fastForwardActive = true
            BridgeState.ui.fastForwardSessionId = 'session'
            BridgeState.ui.fastForwardTurnNumber = 1
            decision = {
                decisionId='fast-main', sessionId='session', kind='main_priority',
                seatId='forge-player-1', activeSeatId='forge-player-1', prioritySeatId='forge-player-1',
                turnNumber=1, phaseName='Main phase, precombat', eventCursor=10,
                actions={
                    {actionId='pass-fast', type='pass_priority', isPresentationAuthorized=true},
                    {actionId='spell-fast', type='cast_spell', isPresentationAuthorized=true}
                }
            }
            BridgeRenderDecision(decision, true)
        ");

        Assert.Equal("pass-fast", lua.Globals.Get("submittedAction").String);
        Assert.Equal("fast_forward", lua.Globals.Get("submittedSource").String);
    }

    [Fact]
    public void FastForward_PhaseStopPreventsFirstPrioritySubmission()
    {
        var lua = NewProbe(false, "forge-player-1");
        lua.DoString(@"
            BridgeState.ui.autoAdvanceMode = 'FAST-FORWARD'
            BridgeState.ui.fastForwardActive = true
            BridgeState.ui.fastForwardSessionId = 'session'
            BridgeState.ui.fastForwardTurnNumber = 1
            BridgeState.ui.fastForwardStops = {own_turn={main_precombat=true}, other_turn={}}
            decision = {
                decisionId='stop-main', sessionId='session', kind='main_priority',
                seatId='forge-player-1', activeSeatId='forge-player-1', prioritySeatId='forge-player-1',
                turnNumber=1, phaseName='Main phase, precombat', eventCursor=10,
                actions={{actionId='pass-stop', type='pass_priority', isPresentationAuthorized=true}}
            }
            BridgeRenderDecision(decision, true)
        ");

        Assert.Null(lua.Globals.Get("submittedAction").ToObject());
        Assert.False(lua.Globals.Get("BridgeState").Table.Get("ui").Table.Get("fastForwardActive").Boolean);
    }

    [Fact]
    public void FastForward_StopsAtTargetSelectionWithoutSubmitting()
    {
        var lua = NewProbe(false, "forge-player-1");
        lua.DoString(@"
            BridgeState.ui.autoAdvanceMode = 'FAST-FORWARD'
            BridgeState.ui.fastForwardActive = true
            BridgeState.ui.fastForwardSessionId = 'session'
            BridgeState.ui.fastForwardTurnNumber = 1
            decision = {
                decisionId='target-required', sessionId='session', kind='target_selection',
                seatId='forge-player-1', activeSeatId='forge-player-1', prioritySeatId='forge-player-1',
                turnNumber=1, phaseName='Main phase, precombat', eventCursor=10,
                actions={{actionId='target-choice', type='choose_target', isPresentationAuthorized=true}}
            }
            BridgeRenderDecision(decision, true)
        ");

        Assert.Null(lua.Globals.Get("submittedAction").ToObject());
        Assert.False(lua.Globals.Get("BridgeState").Table.Get("ui").Table.Get("fastForwardActive").Boolean);
    }

    [Theory]
    [InlineData("Upkeep", "upkeep")]
    [InlineData("Draw step", "draw")]
    [InlineData("Main phase, precombat", "main_precombat")]
    [InlineData("Beginning of Combat Step", "beginning_combat")]
    [InlineData("Declare Attackers Step", "declare_attackers")]
    [InlineData("Declare Blockers Step", "declare_blockers")]
    [InlineData("Combat Damage Step", "combat_damage")]
    [InlineData("End of Combat Step", "end_combat")]
    [InlineData("Main phase, postcombat", "main_postcombat")]
    [InlineData("End step", "end_step")]
    public void YieldPhaseClassifierUsesCanonicalStopKeys(string phase, string expected)
    {
        var lua = NewProbe(false, "forge-player-1");
        lua.DoString($"classified = BridgeYieldPhaseKey('{phase}')");
        Assert.Equal(expected, lua.Globals.Get("classified").String);
    }

    [Fact]
    public void AutoPassToggleIsPersistentUntilExplicitlyUnchecked()
    {
        var lua = NewProbe(false, "forge-player-1");
        lua.DoString(@"
            BridgeSetAutoPassEmpty(true, 'test')
            enabled = BridgeState.ui.autoPassEmpty
            BridgeSetAutoPassEmpty(false, 'test')
            disabled = BridgeState.ui.autoPassEmpty
        ");

        Assert.True(lua.Globals.Get("enabled").Boolean);
        Assert.False(lua.Globals.Get("disabled").Boolean);
    }

    private static Script NewProbe(bool ownTurn, string activeSeat)
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
        lua.DoString(Source);
        lua.DoString($@"
            BridgeState.eventSessionId = 'session'
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
            BridgeState.currentTurnSeatId = '{activeSeat}'
            BridgeState.currentPhase = 'Main phase, precombat'
            BridgeState.ui = {{mounted=true, autoAdvanceMode='YIELD'}}
            BridgeState.yieldPolicyTurnNumber = 1
            BridgeState.yieldPolicyActiveSeatId = '{activeSeat}'
            BridgeState.yieldPolicySessionId = 'session'
            BridgeState.yieldPolicyOwnTurn = {(ownTurn ? "true" : "false")}
            BridgeState.decisionLifecycle = {{}}
            function BridgeSetStatus(title, subtitle) end
            function BridgeClearHighlights() end
            function BridgeRenderPreparedSpellPresentations(decision) end
            function BridgeResetSelectionState() end
            function BridgeEnsureSelectionControls(decision) end
            function BridgeEnsureContextualCompletionControl(decision) end
            function BridgeHideMainPriorityControls() end
            function BridgeEnsureDecisionOptionControls(decision, representedActionIds) end
            function BridgeUiMarkDirty(reason) end
            submittedAction = nil
            submittedSource = nil
            function BridgeSubmitChoice(decisionId, actionId, source)
                submittedAction = actionId
                submittedSource = source
            end
        ");
        return lua;
    }
}
