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
            function log(message) table.insert(startupLogs, tostring(message or '')) end
            function broadcastToAll(message, color) end
            function printToAll(message, color) end
            function getAllObjects() return {} end
            function getObjectFromGUID(guid) return nil end
            function getObjectsWithTag(tag) return {} end
            function spawnObject(config)
                local object = {}
                object.tag = 'BlockSquare'
                object.guid = 'startup-object'
                object.name = ''
                object.buttons = {}
                object.setName = function(value) object.name = value end
                object.setLock = function() end; object.setColorTint = function() end; object.setRotation = function() end
                object.getGUID = function() return object.guid end
                object.getName = function() return object.name end
                object.getButtons = function() return object.buttons end
                object.createButton = function(buttonConfig)
                    table.insert(object.buttons, buttonConfig)
                    if buttonConfig.label == 'START\nMATCH' then startupStartLabel = buttonConfig.label end
                    if buttonConfig.label == 'RESUME' then startupResumeLabel = buttonConfig.label end
                    if buttonConfig.label == 'NEW MATCH\n(2 CLICKS)' then startupResetLabel = buttonConfig.label end
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
            onLoad()
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        Assert.True(state.Get("doctorInitializedUi").Boolean);
        Assert.True(state.Get("ui").Table.Get("mounted").Boolean);
        Assert.Equal("COMPANION READY", state.Get("statusHeadline").String);
        Assert.Equal("MATCH", state.Get("runtimeCompatibilityState").String);
        Assert.Equal(1, lua.Globals.Get("startupCompatibilityRequests").Number);
        Assert.Equal("START\nMATCH", lua.Globals.Get("startupStartLabel").String);
        Assert.Equal("RESUME", lua.Globals.Get("startupResumeLabel").String);
        Assert.Equal("NEW MATCH\n(2 CLICKS)", lua.Globals.Get("startupResetLabel").String);
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
