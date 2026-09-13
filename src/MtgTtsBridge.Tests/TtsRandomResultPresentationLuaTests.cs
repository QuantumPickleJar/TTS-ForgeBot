using MoonSharp.Interpreter;

namespace MtgTtsBridge.Tests;

public sealed class TtsRandomResultPresentationLuaTests
{
    private static readonly string Source = File.ReadAllText(Path.GetFullPath(Path.Combine(
        AppContext.BaseDirectory, "..", "..", "..", "..", "..", "tts", "src", "45-random-result-presentation.lua")));
    private static readonly string DecisionSource = File.ReadAllText(Path.GetFullPath(Path.Combine(
        AppContext.BaseDirectory, "..", "..", "..", "..", "..", "tts", "src", "20-ui-decisions.lua")));

    [Fact]
    public void DependentDecisionIsDeferredWhileRandomPresentationIsActive()
    {
        var lua = NewProbe("d20", 17, 17);
        var functionStart = DecisionSource.IndexOf("function BridgeShouldDeferDecision", StringComparison.Ordinal);
        var functionEnd = DecisionSource.IndexOf("\nfunction BridgeTryPresentPendingDecision", functionStart, StringComparison.Ordinal);
        lua.DoString(DecisionSource.Substring(functionStart, functionEnd - functionStart));
        lua.DoString(@"
            BridgeState.activeRandomResultPresentation = {finished=false, sessionId='session', eventSequence=12}
            decision = {decisionId='dependent-1', seatId='forge-player-1', eventCursor=12}
            deferred, _, _, reason = BridgeShouldDeferDecision(decision)
        ");

        Assert.True(lua.Globals.Get("deferred").Boolean);
        Assert.Equal("random_result_presentation_pending", lua.Globals.Get("reason").String);
    }

    [Fact]
    public void RerollStartsANewPresentationWithItsNewAuthoritativeResult()
    {
        var lua = NewProbe("d20", 17, 17);
        lua.DoString(@"
            firstResults = {0,17}
            secondResults = {0,9}
            setmetatable(firstResults, {__len=function() return 1 end})
            setmetatable(secondResults, {__len=function() return 1 end})
            first = {sequence=20, randomResultPresentation={rollGroupId='roll-1', seatId='forge-player-1', sides=20, naturalResults=firstResults}}
            second = {sequence=21, randomResultPresentation={rollGroupId='roll-2', seatId='forge-player-1', sides=20, naturalResults=secondResults, isReroll=true}}
            BridgeStartRandomResultPresentation(first)
            firstPresentation = BridgeState.activeRandomResultPresentation
            BridgeStartRandomResultPresentation(second)
            secondPresentation = BridgeState.activeRandomResultPresentation
        ");

        Assert.Equal("roll-1", lua.Globals.Get("firstPresentation").Table.Get("rollGroupId").String);
        Assert.Equal("roll-2", lua.Globals.Get("secondPresentation").Table.Get("rollGroupId").String);
        Assert.True(lua.Globals.Get("secondPresentation").Table.Get("isReroll").Boolean);
        Assert.Equal(9, lua.Globals.Get("secondPresentation").Table.Get("naturalResults").Table.Get(1).Number);
    }

    [Fact]
    public void OneD20UsesForgeValueAndCompletesOnlyAfterFaceAndHold()
    {
        var lua = NewProbe("d20", 4, 17);
        lua.DoString(@"
            forgeNaturalResults = {0,17}
            forgeFinalResults = {0,17}
            setmetatable(forgeNaturalResults, {__len=function() return 1 end})
            setmetatable(forgeFinalResults, {__len=function() return 1 end})
            event = {sequence=10, randomResultPresentation={rollGroupId='r1', seatId='forge-player-1', sides=20, naturalResults=forgeNaturalResults, finalResults=forgeFinalResults},
                _bridgePhysicalCompletion=function(ok, reason) completedCallback = ok end}
            started = BridgeStartRandomResultPresentation(event)
            stageAfterStart = BridgeState.activeRandomResultPresentation and BridgeState.activeRandomResultPresentation.stage or 'nil'
            RunUntilReadable()
            stageAfterSettle = BridgeState.activeRandomResultPresentation and BridgeState.activeRandomResultPresentation.stage or 'nil'
            holdLog = lastLog
            face = die.value
            completedBeforeHold = completedCallback
            RunReadableHold()
            completedAfterHold = completedCallback
        ");

        Assert.True(lua.Globals.Get("started").Boolean);
        Assert.Equal("ANIMATING", lua.Globals.Get("stageAfterStart").String);
        Assert.Contains("HOLDING_READABLE_RESULT", lua.Globals.Get("holdLog").String);
        Assert.Equal(17, lua.Globals.Get("face").Number);
        Assert.Equal(1.5, lua.Globals.Get("BRIDGE_RANDOM_RESULT_PRESENTATION_SETTINGS").Table.Get("readableHoldSeconds").Number);
        Assert.Equal(DataType.Nil, lua.Globals.Get("completedBeforeHold").Type);
        Assert.True(lua.Globals.Get("completedAfterHold").Boolean);
    }

    [Fact]
    public void TwoD6IsOneGroupWithOneReadableHoldAndBothValuesPreserved()
    {
        var lua = NewProbe("d6", 2, 2);
        lua.DoString(@"
            forgeNaturalResults = {0,2,5}
            forgeFinalResults = {0,2,5}
            setmetatable(forgeNaturalResults, {__len=function() return 2 end})
            setmetatable(forgeFinalResults, {__len=function() return 2 end})
            die2 = {tag='Die', guid='die-2', name='d6', value=5, getGUID=function() return 'die-2' end,
                getName=function() return 'd6' end, getDescription=function() return '' end,
                getPosition=function() return {{x=1, z=0}} end,
                getRotationValue=function() return die2.value end, setLock=function() end,
                randomize=function() die2.value = 5 end}
            objects = {die, die2}
            event = {sequence=11, randomResultPresentation={rollGroupId='r2', seatId='forge-player-1', sides=6, naturalResults=forgeNaturalResults, finalResults=forgeFinalResults},
                _bridgePhysicalCompletion=function(ok) completedCallback = ok end}
            inputFirst = event.randomResultPresentation.naturalResults[1]
            inputSecond = event.randomResultPresentation.naturalResults[2]
            BridgeStartRandomResultPresentation(event)
            timersAtStart = timeTimerCount
            presentationRef = BridgeState.activeRandomResultPresentation
            RunUntilReadable()
            stageAfterFirstTimer = BridgeState.activeRandomResultPresentation and BridgeState.activeRandomResultPresentation.stage or 'nil'
            holdLog = lastLog
            timersBeforeHold = timeTimerCount
            physicalCount = (presentationRef.physicalDieGuids[1] ~= nil and 1 or 0)
                + (presentationRef.physicalDieGuids[2] ~= nil and 1 or 0)
            naturalFirst = presentationRef.naturalResults[1]
            naturalSecond = presentationRef.naturalResults[2]
            holdReady = pendingTimeCallback ~= nil
            if holdReady then RunReadableHold() end
        ");

        Assert.Equal(1, lua.Globals.Get("timersAtStart").Number);
        Assert.Equal(1, lua.Globals.Get("maxTimeTimerCount").Number);
        Assert.True(lua.Globals.Get("holdReady").Boolean, "stage=" + lua.Globals.Get("stageAfterFirstTimer") + " log=" + lua.Globals.Get("holdLog"));
        Assert.Contains("HOLDING_READABLE_RESULT", lua.Globals.Get("holdLog").String);
        Assert.Equal(2, lua.Globals.Get("physicalCount").Number);
        Assert.Equal("random-result-die", lua.Globals.Get("die").Table.Get("presentationKind").String);
        Assert.Equal("random-result-die", lua.Globals.Get("die2").Table.Get("presentationKind").String);
        Assert.True(lua.Globals.Get("naturalFirst").Number == 2,
            "input=" + lua.Globals.Get("inputFirst") + "," + lua.Globals.Get("inputSecond")
            + " naturalFirst=" + lua.Globals.Get("naturalFirst") + " naturalSecond=" + lua.Globals.Get("naturalSecond"));
        Assert.Equal(5, lua.Globals.Get("naturalSecond").Number);
        Assert.True(lua.Globals.Get("completedCallback").Boolean);
    }

    [Fact]
    public void WrongSidedAssetFailsDiagnosticallyAndStaleCallbackCannotCompleteNewRuntime()
    {
        var lua = NewProbe("d6", 1, 6);
        lua.DoString(@"
            forgeNaturalResults = {0,17}
            forgeSixResults = {0,6}
            setmetatable(forgeNaturalResults, {__len=function() return 1 end})
            setmetatable(forgeSixResults, {__len=function() return 1 end})
            event = {sequence=12, randomResultPresentation={rollGroupId='missing', seatId='forge-player-1', sides=20, naturalResults=forgeNaturalResults},
                _bridgePhysicalCompletion=function(ok, reason) completedCallback = ok; failure = reason end}
            BridgeStartRandomResultPresentation(event)
            latestDiagnostic = BridgeState.randomResultPresentationDiagnostics[1] or {}
            failed = latestDiagnostic.failed
            failureText = latestDiagnostic.failureReason
            oldGeneration = BridgeState.randomResultPresentationGeneration
            die.value = 3
            event2 = {sequence=13, randomResultPresentation={rollGroupId='stale', seatId='forge-player-1', sides=6, naturalResults=forgeSixResults},
                _bridgePhysicalCompletion=function(ok) secondCompleted = ok end}
            BridgeStartRandomResultPresentation(event2)
            BRIDGE_RUNTIME_EPOCH = BRIDGE_RUNTIME_EPOCH + 1
            RunTimeTimer()
            staleDidNotFinish = secondCompleted == nil
        ");

        Assert.True(lua.Globals.Get("failed").Boolean);
        Assert.Contains("no existing physical d20", lua.Globals.Get("failureText").String);
        Assert.True(lua.Globals.Get("oldGeneration").Number > 0);
        Assert.True(lua.Globals.Get("staleDidNotFinish").Boolean);
    }

    private static Script NewProbe(string dieName, int initialValue, int forcedValue)
    {
        var lua = new Script();
        lua.DoString($@"
            now = 0
            function log(message) end
            function BridgeLog(message) lastLog = message; if string.find(message, 'HOLDING_READABLE_RESULT', 1, true) ~= nil then holdLog = message end end
            function broadcastToAll(message, color) end
            JSON = {{encode=function(value) return '{{}}' end}}
            function getAllObjects() return objects or {{}} end
            function BridgeSetStatus(headline, detail) lastStatus = headline .. '|' .. detail end
            function BridgeShowError(message) lastError = message end
            function BridgeObjectIsUsable(object) return object ~= nil and object.live ~= false end
            function BridgeSafeObjectGuid(object) return object and object.getGUID() or nil end
            function BridgeSafeObjectName(object) return object and object.getName() or '' end
            function BridgeGetLiveObjectByGuid(guid)
                for _, object in ipairs(objects or {{die}}) do
                    if object.getGUID() == guid and not (guid == 'die-1' and die1Used) then return object end
                end
                return nil
            end
            function BridgeRegisterPresentationObject(object, kind) object.presentationKind = kind; if object.getGUID() == 'die-1' then die1Used = true end end
            function BridgeRegisterPhysicalReadinessDependency(decision, reason, detail, seatId) readinessReason = reason end
            function BridgeRuntimeIsCurrent(epoch) return epoch == BRIDGE_RUNTIME_EPOCH end
            function BridgeWaitTime(callback, delay) pendingTimeCallback = callback; pendingTimeDelay = delay; timeTimerCount = timeTimerCount + 1; if timeTimerCount > maxTimeTimerCount then maxTimeTimerCount = timeTimerCount end end
            function BridgeWaitFrames(callback, frames) pendingFrameCallback = callback; frameTimerCount = frameTimerCount + 1 end
            function BridgeResyncClockNow() return now end
            function RunTimeTimer()
                if pendingTimeCallback then local callback = pendingTimeCallback; local delay = pendingTimeDelay; pendingTimeCallback = nil; pendingTimeDelay = nil; timeTimerCount = timeTimerCount - 1; now = now + delay; callback(); return end
                if pendingFrameCallback then local callback = pendingFrameCallback; pendingFrameCallback = nil; frameTimerCount = frameTimerCount - 1; callback(); return end
            end
            function RunReadableHold()
                local callback = pendingTimeCallback
                local delay = pendingTimeDelay
                pendingTimeCallback = nil
                pendingTimeDelay = nil
                timeTimerCount = timeTimerCount - 1
                now = now + delay
                callback()
            end
            function RunUntilReadable()
                for index = 1, 32 do
                    if string.find(lastLog or '', 'HOLDING_READABLE_RESULT', 1, true) ~= nil then return end
                    RunTimeTimer()
                end
            end
            timeTimerCount = 0
            frameTimerCount = 0
            maxTimeTimerCount = 0
            die1Used = false
            BRIDGE_RUNTIME_EPOCH = 1
            BRIDGE_RUNTIME_EPOCH_LOCAL = 1
            BRIDGE_RANDOM_RESULT_PRESENTATION_SETTINGS = {{readableHoldSeconds=1.5, settleSeconds=0.25, settleTimeoutSeconds=4, maxAuthoritativeFaceAttempts=3, extraReturnDelayFrames=2, dieBagGuids={{}}}}
            BRIDGE_SEATS = {{['forge-player-1']={{battlefieldAnchors={{creature={{x=0, y=2, z=0}}}}, battlefieldDieGuidBySides={{[6]='die-1', [20]='die-1'}}}}}}
            die = {{tag='Die', guid='die-1', name='{dieName}', value={initialValue}, getGUID=function() return 'die-1' end,
                getName=function() return '{dieName}' end, getDescription=function() return '' end,
                getPosition=function() return {{x=0, z=0}} end,
                getRotationValue=function() return die.value end, setLock=function() end,
                randomize=function() die.value = {forcedValue} end}}
            objects = {{die}}
            BridgeState = {{eventSessionId='session', randomResultPresentationGeneration=0, activeRandomResultPresentation=nil, randomResultPresentationDiagnostics={{}}}}
        ");
        lua.DoString(Source);
        return lua;
    }

}
