using MoonSharp.Interpreter;

namespace MtgTtsBridge.Tests;

public sealed class TtsDiagnosticCaptureLuaTests
{
    private static readonly string Script = File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.lua"));

    [Fact]
    public void Recovery_WithCurrentDecision_ReobservesAndRendersWithoutSubmitting()
    {
        var lua = NewProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'capture-session'
            BridgeState.eventPolling = true
            BridgeState.eventRequestInFlight = false
            BridgeState.eventPollScheduled = false
            BridgeState.eventQueue = {}
            BridgeState.lastReceivedEventSequence = 22
            BridgeState.lastAppliedEventSequence = 22
            BridgeState.desyncLatched = false
            BridgeState.gameEnded = nil
            BridgeState.submitting = false
            BridgeState.choiceProtocolPaused = false
            BridgeState.choiceTransactions = {}
            BridgeState.diagnosticCaptureLifecycle = {}
            BridgeState.diagnosticCaptureFollowupToken = nil
            BridgeState.yieldPolicyTurnNumber = 6
            BridgeState.yieldPolicyActiveSeatId = 'forge-player-1'
            BridgeState.yieldPolicySessionId = 'capture-session'
            BridgeState.yieldPolicyOwnTurn = true
            BridgeState.decisionPresentationGeneration = 4
            BridgeState.lastDecision = {
                decisionId = 'forge-tui-12', sessionId = 'capture-session',
                kind = 'main_priority', eventCursor = 22,
                actions = {
                    {actionId = 'pass-12', type = 'pass_priority'},
                    {actionId = 'land-12', type = 'play_land'}
                }
            }
            BridgeState.ui = {reportCaptureInFlight = false}
            eventPollCalls = 0
            decisionGets = 0
            accepted = 0
            submitted = 0
            function BridgePollEvents(generation) eventPollCalls = eventPollCalls + 1 end
            function BridgeGetDecision(callback)
                decisionGets = decisionGets + 1
                callback(true, BridgeState.lastDecision, nil)
            end
            function BridgeAcceptDecision(decision, origin, sessionId, presentationGeneration)
                accepted = accepted + 1
                acceptedOrigin = origin
            end
            function BridgeSubmitChoice(decisionId, actionId, source) submitted = submitted + 1 end
            function BridgeWaitTime(callback, delay) end
            BridgeRecoverGameplayPumps('diagnostic-callback', 'capture-session', BRIDGE_RUNTIME_EPOCH, 17)
        ");

        Assert.Equal(1, lua.Globals.Get("eventPollCalls").Number);
        Assert.Equal(1, lua.Globals.Get("decisionGets").Number);
        Assert.Equal(1, lua.Globals.Get("accepted").Number);
        Assert.Equal("diagnostic_capture_recovery", lua.Globals.Get("acceptedOrigin").String);
        Assert.Equal(0, lua.Globals.Get("submitted").Number);
        Assert.Equal("forge-tui-12", lua.Globals.Get("BridgeState").Table.Get("lastDecision").Table.Get("decisionId").String);
        var state = lua.Globals.Get("BridgeState").Table;
        Assert.Equal(6, state.Get("yieldPolicyTurnNumber").Number);
        Assert.Equal("forge-player-1", state.Get("yieldPolicyActiveSeatId").String);
        lua.DoString(@"
            hasBegin = false; hasRefresh = false; hasEnd = false
            for _, record in ipairs(BridgeState.diagnosticCaptureLifecycle) do
                if record.stage == 'DIAG_CAPTURE_RECOVERY_BEGIN' then hasBegin = true end
                if record.stage == 'DIAG_CAPTURE_DECISION_REFRESH_CALLBACK' then hasRefresh = true end
                if record.stage == 'DIAG_CAPTURE_RECOVERY_END' then hasEnd = true end
            end
        ");
        Assert.True(lua.Globals.Get("hasBegin").Boolean);
        Assert.True(lua.Globals.Get("hasRefresh").Boolean);
        Assert.True(lua.Globals.Get("hasEnd").Boolean);
    }

    [Fact]
    public void FailedCapture_IsObserverOnlyAndDoesNotRecoverGameplay()
    {
        var lua = NewProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'capture-session'
            BridgeState.eventPolling = true
            BridgeState.eventRequestInFlight = false
            BridgeState.eventPollScheduled = false
            BridgeState.eventQueue = {}
            BridgeState.lastReceivedEventSequence = 22
            BridgeState.lastAppliedEventSequence = 22
            BridgeState.desyncLatched = false
            BridgeState.gameEnded = nil
            BridgeState.submitting = false
            BridgeState.choiceProtocolPaused = false
            BridgeState.choiceTransactions = {}
            BridgeState.lastDecision = {
                decisionId = 'forge-tui-12', sessionId = 'capture-session',
                kind = 'main_priority', eventCursor = 22,
                actions = {{actionId = 'pass-12', type = 'pass_priority'}}
            }
            BridgeState.ui = {reportCaptureInFlight = false, reportCaptureToken = 0, reportCategoryIndex = 1}
            eventPollCalls = 0; decisionGets = 0; accepted = 0; submitted = 0
            function BridgePollEvents(generation) eventPollCalls = eventPollCalls + 1 end
            function BridgeAcceptDecision(decision, origin, sessionId, presentationGeneration) accepted = accepted + 1 end
            function BridgeSubmitChoice(decisionId, actionId, source) submitted = submitted + 1 end
            function BridgeWaitTime(callback, delay) end
            function BridgeWaitFrames(callback, frames) callback() end
            function BridgePerformanceDiagnosticPayload() return {performanceSummary = {}, recentTtsTrace = {}, diagnosticCaptureLifecycle = {}} end
            function BridgeHudReportSummaryText() return nil end
            function BridgeHudReportMappedCardInstanceIds() return {} end
            function BridgeUiMarkDirty(reason) end
            BridgeHttp.requestJson = function(method, path, payload, callback)
                if method == 'POST' and path == '/api/v1/diagnostics/report' then
                    callback(false, nil, 'capture failed')
                elseif method == 'GET' and path == '/api/v1/decision' then
                    decisionGets = decisionGets + 1
                    callback(true, BridgeState.lastDecision, nil)
                end
            end
            BridgeHudSubmitReport('Gameplay sync', 'capture probe')
        ");

        var bridgeState = lua.Globals.Get("BridgeState").Table;
        Assert.False(bridgeState.Get("ui").Table.Get("reportCaptureInFlight").Boolean);
        Assert.Equal(0, lua.Globals.Get("decisionGets").Number);
        Assert.Equal(0, lua.Globals.Get("accepted").Number);
        Assert.Equal(0, lua.Globals.Get("submitted").Number);
        Assert.Equal(0, lua.Globals.Get("eventPollCalls").Number);
    }

    [Fact]
    public void StaleCaptureCallback_CannotStartRecoveryForNewerToken()
    {
        var lua = NewProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'capture-session'
            BridgeState.lastDecision = {decisionId = 'forge-tui-12', sessionId = 'capture-session', kind = 'main_priority', actions = {{actionId = 'pass-12', type = 'pass_priority'}}}
            BridgeState.choiceTransactions = {}
            BridgeState.retiredChoiceDecisionIds = {}
            BridgeState.ui = {reportCaptureInFlight = false, reportCaptureToken = 0, reportCategoryIndex = 1}
            BridgeState.desyncLatched = false
            function BridgeWaitTime(callback, delay) end
            function BridgeWaitFrames(callback, frames) end
            function BridgePerformanceDiagnosticPayload() return {performanceSummary = {}, recentTtsTrace = {}, diagnosticCaptureLifecycle = {}} end
            function BridgeHudReportSummaryText() return nil end
            function BridgeHudReportMappedCardInstanceIds() return {} end
            function BridgeUiMarkDirty(reason) end
            recoveryCalls = 0
            function BridgeRecoverGameplayPumps(reason, sessionId, epoch, token) recoveryCalls = recoveryCalls + 1 end
            pendingReportCallback = nil
            BridgeHttp.requestJson = function(method, path, payload, callback)
                if method == 'POST' then pendingReportCallback = callback end
            end
            BridgeHudSubmitReport('Gameplay sync', 'capture probe')
            BridgeState.ui.reportCaptureInFlight = false
            BridgeState.ui.reportCaptureToken = BridgeState.ui.reportCaptureToken + 1
            pendingReportCallback(true, {success = true, reportId = 'old'}, nil)
        ");

        Assert.Equal(0, lua.Globals.Get("recoveryCalls").Number);
        Assert.Equal(2, lua.Globals.Get("BridgeState").Table.Get("ui").Table.Get("reportCaptureToken").Number);
    }

    [Fact]
    public void RepeatedIdenticalReadinessResyncSnapshot_EmitsBoundedNoProgressDiagnostic()
    {
        var lua = NewProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'capture-session'
            BridgeState.lastReceivedEventSequence = 60
            BridgeState.lastAppliedEventSequence = 0
            BridgeState.pendingDecision = {decisionId = 'forge-tui-1', eventCursor = 60}
            BridgeState.resyncNoProgress = {count = 0, lastLoggedCount = 0}
            resyncLogs = {}
            function BridgeLog(message) table.insert(resyncLogs, message) end
            local stale = {forgeSequence = 2, eventCursor = 60}
            BridgeRecordResyncSnapshotProgress('hand-readiness-timeout', stale)
            BridgeRecordResyncSnapshotProgress('hand-readiness-timeout', stale)
            BridgeRecordResyncSnapshotProgress('hand-readiness-timeout', stale)
            BridgeRecordResyncSnapshotProgress('hand-readiness-timeout', stale)
        ");

        Assert.Equal(4, lua.Globals.Get("BridgeState").Table.Get("resyncNoProgress").Table.Get("count").Number);
        Assert.Equal(1, lua.Globals.Get("resyncLogs").Table.Values
            .Count(value => value.String.Contains("RESYNC_NO_PROGRESS", StringComparison.Ordinal)));
    }

    [Fact]
    public void DroppedDecisionTimer_IsRearmedByIndependentLivenessWatchdog()
    {
        var lua = NewProbe();
        lua.DoString(@"
            BridgeState.eventSessionId = 'timer-session'
            BridgeState.gameEnded = nil
            BridgeState.submitting = false
            BridgeState.choiceProtocolPaused = false
            BridgeState.lastDecision = nil
            BridgeState.decisionPollInFlight = false
            BridgeState.decisionPollScheduled = true
            BridgeState.decisionPollScheduledAt = 1
            BridgeState.decisionPollDueAt = 1
            BridgeState.decisionPollTimerToken = 9
            BridgeState.decisionPollGeneration = 4
            BridgeState.eventQueue = {}
            BridgeState.lastReceivedEventSequence = 12
            BridgeState.lastAppliedEventSequence = 12
            os.clock = function() return 2 end
            rearmed = 0
            function BridgeStartDecisionPolling() rearmed = rearmed + 1 end
            BridgeCheckDecisionPollingLiveness('test-dropped-timer')
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        Assert.Equal(1, lua.Globals.Get("rearmed").Number);
        Assert.False(state.Get("decisionPollScheduled").Boolean);
        Assert.Equal("timer_lost", state.Get("lastDecisionPollOutcome").String);
    }

    [Fact]
    public void AlreadyProjectedDecisionCursor_IsNotRejectedForExactEqualityMismatch()
    {
        var lua = NewProbe();
        lua.DoString(@"
            BridgeState.lastAppliedEventSequence = 324
            BridgeState.lastStateProjectedEventSequence = 324
            BridgeState.lastReceivedEventSequence = 324
            BridgeState.eventQueue = {}
            decision = {decisionId = 'forge-tui-48', eventCursor = 323, kind = 'main_priority', actions = {}}
            blocked = BridgeAutomaticDecisionBlocked(decision)
        ");

        Assert.True(lua.Globals.Get("blocked").IsNil());
    }

    private static Script NewProbe()
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
        return lua;
    }
}
