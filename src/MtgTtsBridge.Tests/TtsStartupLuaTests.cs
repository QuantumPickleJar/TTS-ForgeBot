using MoonSharp.Interpreter;

namespace MtgTtsBridge.Tests;

public sealed class TtsStartupLuaTests
{
    private static readonly string GlobalScript = File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.lua"));

    [Fact]
    public void OnLoad_InitializesLuaDrivenSetupControlsAfterHudMountAndHealthyBridge()
    {
        var lua = new Script();
        Execute(lua, "startup-host.lua", @"
            startupUiWrites = {}
            startupLogs = {}
            startupObjects = {}
            function log(message) table.insert(startupLogs, tostring(message or '')) end
            function broadcastToAll(message, color) end
            function printToAll(message, color) end
            function getAllObjects() return startupObjects end
            function getObjectFromGUID(guid)
                for _, object in ipairs(startupObjects) do if object.guid == guid then return object end end
                return nil
            end
            function getObjectsWithTag(tag) return {} end
            function spawnObject(config)
                local object = {}
                object.tag = 'BlockSquare'
                object.guid = 'startup-object-' .. tostring(#startupObjects + 1)
                object.name = ''
                object.buttons = {}
                object.position = config.position
                table.insert(startupObjects, object)
                object.setName = function(value) object.name = value end
                object.setLock = function() end; object.setColorTint = function() end; object.setRotation = function() end
                object.getGUID = function() return object.guid end
                object.getName = function() return object.name end
                object.getButtons = function() return object.buttons end
                object.createButton = function(buttonConfig)
                    table.insert(object.buttons, buttonConfig)
                    if buttonConfig.label == 'START MATCH' then startupStartLabel = buttonConfig.label end
                    if buttonConfig.label == 'RESUME' then startupResumeLabel = buttonConfig.label end
                    if buttonConfig.label == 'RECOVER / RESYNC' then startupRecoverLabel = buttonConfig.label end
                    if buttonConfig.label == 'NEW MATCH' then startupResetLabel = buttonConfig.label end
                end
                config.callback_function(object)
                return object
            end
            UI = {setAttribute = function(id, attribute, value)
                table.insert(startupUiWrites, {id=id, attribute=attribute, value=value})
            end, getXml = function() return '<Panel id=""BridgeHudRoot"" />' end}
            Global = {getVar = function(name) return nil end}
            Player = {White = {getHandObjects = function() return {} end}, Blue = {getHandObjects = function() return {} end}}
            Wait = {time = function(callback, delay) callback() end, frames = function(callback, frames) callback() end}
            Time = {time = 0}
            JSON = {encode = function(value) return '{}' end, decode = function(value)
                if string.find(tostring(value), 'runtimeCompatibilityState') ~= nil then
                    return {runtimeCompatibilityState='MATCH', expectedGeneratedGlobalLuaSha256=BRIDGE_GENERATED_GLOBAL_LUA_SOURCE_SHA256}
                end
                return {adapter='forge', adapterState='not_started', sessionId='session-not-started'}
            end}
            os = {time = function() return 1 end, clock = function() return 0 end}
            math.random = function(minimum, maximum) return 123456 end
            table.concat = function(values, separator) return 'startup-runtime' end
            WebRequest = {post = function() end, get = function(url, callback)
                callback({is_error=false, response_code=200,
                    text='{ ""adapter"": ""forge"", ""adapterState"": ""not_started"", ""sessionId"": ""session-not-started"" }'})
            end, custom = function(url, method, download, body, headers, callback)
                startupCompatibilityRequests = (startupCompatibilityRequests or 0) + 1
                callback({is_error=false, response_code=200, text='{ ""runtimeCompatibilityState"": ""MATCH"" }'})
            end}
        ");
        Execute(lua, "Global.lua", GlobalScript);
        Execute(lua, "startup-call.lua", @"
            local ensureSetupControl = BridgeEnsureSetupControl
            startupControlPositions = {}
            BridgeEnsureSetupControl = function(kind, label, x, color, clickFunction, tooltip, sharedObjects, z)
                startupControlPositions[kind] = {x=x, z=z}
                return ensureSetupControl(kind, label, x, color, clickFunction, tooltip, sharedObjects, z)
            end
            onLoad()
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        Assert.True(state.Get("doctorInitializedUi").Boolean);
        Assert.True(state.Get("ui").Table.Get("mounted").Boolean);
        Assert.Equal("COMPANION READY", state.Get("statusHeadline").String);
        Assert.Equal("MATCH", state.Get("runtimeCompatibilityState").String);
        Assert.Equal(1, lua.Globals.Get("startupCompatibilityRequests").Number);
        Assert.Equal("START MATCH", lua.Globals.Get("startupStartLabel").String);
        Assert.Equal("RESUME", lua.Globals.Get("startupResumeLabel").String);
        Assert.Equal("RECOVER / RESYNC", lua.Globals.Get("startupRecoverLabel").String);
        Assert.Equal("NEW MATCH", lua.Globals.Get("startupResetLabel").String);
        var controls = lua.Globals.Get("startupObjects").Table.Values
            .Select(value => value.Table)
            .Where(value => value.Get("name").String.StartsWith("Forge Setup V2 ", StringComparison.Ordinal))
            .ToArray();
        Assert.Equal(4, controls.Length);
        var positions = lua.Globals.Get("startupControlPositions").Table.Values
            .Select(value => value.Table).ToArray();
        Assert.Equal(4, positions.Length);
        Assert.All(positions, position => Assert.Equal(positions[0].Get("x").Number, position.Get("x").Number));
        Assert.Equal(4, positions.Select(position => position.Get("z").Number).Distinct().Count());
        Assert.Contains("position = {x, 1.6, z or -17.0}", GlobalScript, StringComparison.Ordinal);
        Assert.True(lua.Globals.Get("startupUiWrites").Table.Length > 0);
    }

    [Fact]
    public void SetupControl_RehydratesStaleButtonInsteadOfTreatingItAsReady()
    {
        var lua = new Script();
        Execute(lua, "setup-control-host.lua", @"
            function log(message) end
            function broadcastToAll(message, color) end
            function printToAll(message, color) end
            function getAllObjects() return {} end
            function getObjectFromGUID(guid) return staleSetupObject end
            Wait = {time = function(callback, delay) end, frames = function(callback, frames) end}
            Time = {time = 0}
            JSON = {encode = function(value) return '{}' end, decode = function(value) return {} end}
            os = {time = function() return 1 end, clock = function() return 0 end}
            math.random = function(minimum, maximum) return 123456 end
            table.concat = function(values, separator) return 'startup-runtime' end
        ");
        Execute(lua, "Global.lua", GlobalScript);
        Execute(lua, "setup-control-call.lua", @"
            staleSetupObject = {
                guid='stale-start', tag='BlockSquare',
                getGUID=function() return 'stale-start' end,
                getButtons=function() return {{label='', click_function='RetiredCallback'}} end,
                clearButtons=function() staleCleared = true end
            }
            BridgeState.setupObjectGuidByKind = {Start='stale-start'}
            function BridgeEnsureObjectButton(object, config)
                rehydratedConfig = config
                return true
            end
            BridgeEnsureSetupControl('Start', 'START\nMATCH', -7.0, {0.12, 0.48, 0.25},
                'BridgePressStartMatch', 'Start only when no Forge match exists')
        ");

        Assert.True(lua.Globals.Get("staleCleared").Boolean);
        var config = lua.Globals.Get("rehydratedConfig").Table;
        Assert.Equal("START\nMATCH", config.Get("label").String);
        Assert.Equal("BridgePressStartMatch", config.Get("click_function").String);
    }

    [Fact]
    public void LifecycleControlsRemainAvailableDuringActiveGameplayAndUseSharedNewMatchHandler()
    {
        var lua = new Script();
        Execute(lua, "active-lifecycle-host.lua", @"
            function log(message) end
            function broadcastToAll(message, color) end
            function printToAll(message, color) end
            function getAllObjects() return {} end
            function getObjectFromGUID(guid) return nil end
            Wait = {time = function(callback, delay) end, frames = function(callback, frames) callback() end}
            Time = {time = 0}
            JSON = {encode = function(value) return '{}' end, decode = function(value) return {} end}
            os = {time = function() return 1 end, clock = function() return 0 end}
            math.random = function(minimum, maximum) return 123456 end
            table.concat = function(values, separator) return 'active-runtime' end
        ");
        Execute(lua, "Global.lua", GlobalScript);
        Execute(lua, "active-lifecycle-call.lua", @"
            BridgeState.lifecycleState = BRIDGE_LIFECYCLE_ACTIVE
            BridgeState.eventSessionId = 'session-active'
            BridgeState.eventPolling = true
            function BridgeWaitFrames(callback, frames) callback() end
            function BridgeWaitTime(callback, seconds) lifecycleTimeout = callback end
            function BridgeResyncClockNow() return lifecycleClock or 0 end
            function BridgeSetStatus(headline, detail) end
            function BridgeStartupPerfEvent(kind, detail) end
            function BridgeSetupTrace(kind, detail) end
            function BridgeShowError(message) lifecycleError = message end
            function BridgeEnsureRuntimeCompatibility(callback) callback(true) end
            actualResetCount = 0
            function BridgeResetSession(token)
                actualResetCount = actualResetCount + 1
                resetOperationToken = token
            end
            activeStartEnabled = BridgeLifecycleControlState('Start')
            activeResetEnabled = BridgeLifecycleControlState('Reset')
            BridgeHudNewMatch('White', '', 'BridgeHudNewMatch')
            firstClickArmed = BridgeState.resetConfirmationArmed
            BridgePressNewMatch(nil, 'White', false)
            resetAfterConfirm = actualResetCount
            BridgePressNewMatch(nil, 'White', false)
            resetAfterDuplicate = actualResetCount
        ");

        Assert.False(lua.Globals.Get("activeStartEnabled").Boolean);
        Assert.True(lua.Globals.Get("activeResetEnabled").Boolean);
        Assert.True(lua.Globals.Get("firstClickArmed").Boolean);
        Assert.Equal(1, lua.Globals.Get("resetAfterConfirm").Number);
        Assert.Equal(1, lua.Globals.Get("resetAfterDuplicate").Number);
    }

    [Fact]
    public void ExpiredConfirmationAndStaleTimeoutCannotResetOrCancelANewerConfirmation()
    {
        var lua = new Script();
        Execute(lua, "confirmation-host.lua", @"
            function log(message) end
            function broadcastToAll(message, color) end
            function printToAll(message, color) end
            function getAllObjects() return {} end
            function getObjectFromGUID(guid) return nil end
            Wait = {time = function(callback, delay) end, frames = function(callback, frames) callback() end}
            Time = {time = 0}
            JSON = {encode = function(value) return '{}' end, decode = function(value) return {} end}
            os = {time = function() return 1 end, clock = function() return 0 end}
            math.random = function(minimum, maximum) return 123456 end
            table.concat = function(values, separator) return 'confirmation-runtime' end
        ");
        Execute(lua, "Global.lua", GlobalScript);
        Execute(lua, "confirmation-call.lua", @"
            BridgeState.lifecycleState = BRIDGE_LIFECYCLE_ACTIVE
            BridgeState.eventSessionId = 'session-active'
            BridgeState.eventPolling = true
            function BridgeWaitFrames(callback, frames) callback() end
            lifecycleClock = 0
            function BridgeResyncClockNow() return lifecycleClock end
            function BridgeSetStatus(headline, detail) end
            function BridgeStartupPerfEvent(kind, detail) end
            function BridgeSetupTrace(kind, detail) end
            function BridgeShowError(message) lifecycleError = message end
            function BridgeEnsureRuntimeCompatibility(callback) callback(true) end
            actualResetCount = 0
            function BridgeResetSession(token) actualResetCount = actualResetCount + 1 end
            BridgeDoPressNewMatch('White', false)
            oldConfirmationToken = BridgeState.resetConfirmationToken
            lifecycleClock = 11
            BridgeDoPressNewMatch('White', false)
            expiredClickResetCount = actualResetCount
            BridgeDoPressNewMatch('White', false)
            newerToken = BridgeState.resetConfirmationToken
            BridgeExpireResetConfirmation(oldConfirmationToken, 'stale-timeout')
            newerConfirmationStillArmed = BridgeState.resetConfirmationArmed
            newerConfirmationToken = BridgeState.resetConfirmationToken
        ");

        Assert.Equal(0, lua.Globals.Get("expiredClickResetCount").Number);
        Assert.True(lua.Globals.Get("newerConfirmationStillArmed").Boolean);
        Assert.Equal(lua.Globals.Get("newerToken").Number, lua.Globals.Get("newerConfirmationToken").Number);
    }

    [Fact]
    public void ResumeContinuesAtExistingCursorAndDesyncRemainsAnExplicitRecoveryOperation()
    {
        var lua = new Script();
        Execute(lua, "resume-host.lua", @"
            function log(message) end
            function broadcastToAll(message, color) end
            function printToAll(message, color) end
            function getAllObjects() return {} end
            function getObjectFromGUID(guid) return nil end
            Wait = {time = function(callback, delay) end, frames = function(callback, frames) callback() end}
            Time = {time = 0}
            JSON = {encode = function(value) return '{}' end, decode = function(value) return {} end}
            os = {time = function() return 1 end, clock = function() return 0 end}
            math.random = function(minimum, maximum) return 123456 end
            table.concat = function(values, separator) return 'resume-runtime' end
        ");
        Execute(lua, "Global.lua", GlobalScript);
        Execute(lua, "resume-call.lua", @"
            BridgeState.lifecycleState = BRIDGE_LIFECYCLE_ACTIVE
            BridgeState.eventSessionId = 'session-resume'
            BridgeState.lastReceivedEventSequence = 73
            BridgeState.lastAppliedEventSequence = 73
            BridgeState.eventQueue = {}
            BridgeState.eventPolling = false
            BridgeState.lastDecision = nil
            BridgeState.desyncLatched = false
            function BridgeResumeChoiceProtocol(reason) resumeReason = reason end
            function BridgeStartEventPolling(sessionId, skipExisting)
                resumedEventSession = sessionId
                resumedSkipExisting = skipExisting
            end
            function BridgeStartDecisionPolling(allowCurrent)
                resumedDecisionPoll = true
            end
            function BridgeSetStatus(headline, detail) end
            function BridgeLog(message) end
            function BridgeShowError(message) resumeError = message end
            resyncCalls = 0
            function BridgeResyncFromAuthoritativeSnapshot(origin) resyncCalls = resyncCalls + 1 end
            resumeResult = BridgeResumeActiveSession('resume')
            cursorAfterResume = BridgeState.lastAppliedEventSequence
            BridgeState.desyncLatched = true
            desyncResumeResult = BridgeResumeActiveSession('resume')
        ");

        Assert.True(lua.Globals.Get("resumeResult").Boolean);
        Assert.Equal(73, lua.Globals.Get("cursorAfterResume").Number);
        Assert.Equal("session-resume", lua.Globals.Get("resumedEventSession").String);
        Assert.False(lua.Globals.Get("resumedSkipExisting").Boolean);
        Assert.Equal(0, lua.Globals.Get("resyncCalls").Number);
        Assert.False(lua.Globals.Get("desyncResumeResult").Boolean);
        Assert.Contains("RECOVER / RESYNC", lua.Globals.Get("resumeError").String);
    }

    [Fact]
    public void DestroyedRegisteredControlSchedulesOneScopedReconciliation()
    {
        var lua = new Script();
        Execute(lua, "destroy-control-host.lua", @"
            function log(message) end
            function broadcastToAll(message, color) end
            function printToAll(message, color) end
            function getAllObjects() return {} end
            function getObjectFromGUID(guid) return nil end
            Wait = {time = function(callback, delay) end, frames = function(callback, frames) end}
            Time = {time = 0}
            JSON = {encode = function(value) return '{}' end, decode = function(value) return {} end}
            os = {time = function() return 1 end, clock = function() return 0 end}
            math.random = function(minimum, maximum) return 123456 end
            table.concat = function(values, separator) return 'destroy-runtime' end
        ");
        Execute(lua, "Global.lua", GlobalScript);
        Execute(lua, "destroy-control-call.lua", @"
            BridgeState.setupObjectGuidByKind.Start = 'destroyed-guid'
            function BridgeWaitFrames(callback, frames) scheduledControlReconcile = callback end
            onObjectDestroy({getGUID=function() return 'destroyed-guid' end})
        ");

        Assert.Equal(DataType.Nil, lua.Globals.Get("BridgeState").Table
            .Get("setupObjectGuidByKind").Table.Get("Start").Type);
        Assert.Equal(DataType.Function, lua.Globals.Get("scheduledControlReconcile").Type);
    }

    private static void Execute(Script lua, string sourceName, string source)
    {
        try
        {
            lua.DoString(source, null, sourceName);
        }
        catch (ScriptRuntimeException exception)
        {
            throw new Xunit.Sdk.XunitException($"Lua failure in {sourceName}:{Environment.NewLine}{exception.DecoratedMessage}");
        }
    }
}
