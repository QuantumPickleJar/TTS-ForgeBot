using System;
using System.IO;
using MoonSharp.Interpreter;

var script = new Script();
script.Globals["print"] = (Action<object>)(obj => Console.WriteLine(obj));
script.Globals["BridgeLog"] = (Action<string>)(msg => Console.WriteLine("BridgeLog: " + msg));
script.Globals["BridgeLogLibraryExtraction"] = (Action<string, string, object, object, object, string>)(
    (seatId, stage, generation, item, library, reason) => Console.WriteLine($"BridgeLogLibraryExtraction: {seatId} {stage} gen={generation} reason={reason} queue={((DynValue?)null).ToString()}"));
script.DoString(@"
    function log(message) end
    function broadcastToAll(message, color) end
    function printToAll(message, color) end
    function getObjectFromGUID(guid) return nil end
    function Wait(frames) end
    Time = { waitForSeconds = function(seconds, callback) callback() end }
    JSON = { encode = function(value) return '{}' end, decode = function(value) return {} end }
    os = { time = function() return 1 end, clock = function() return 0 end }
    math.randomseed(1)
    table.concat = function(values, separator)
        local result = ''
        for index, value in ipairs(values) do
            if index > 1 then result = result .. separator end
            result = result .. tostring(value)
        end
        return result
    end
    function BridgeTryApplyDeferredSnapshotReconcile(reason) end
    function BridgeTryStartPendingSnapshotReconcile(reason) end
    function BridgeTryPresentPendingDecision(reason) end
    function BridgeRefreshDecisionAfterStateTransition(reason) end
    function BridgeShouldReconcileAfterEvent(event) return false end
    function BridgeScheduleSnapshotReconcile(reason, category) end
    function BridgeStopOnDesync(reason) end
    function BridgeWaitTime(callback, delay) end
    BridgeState = { eventPolling = true, eventPollGeneration = 4, eventSessionId = 'session', eventSessionGeneration = 1, lastAppliedEventSequence = 7, lastReceivedEventSequence = 9, eventQueue = {}, animationRunning = false, eventCommitWatchdog = nil, eventDrainWatchdog = {}, libraryExtractionQueueBySeatId = {}, libraryExtractionActiveBySeatId = {}, mulliganBottomQueueBySeatId = {}, mulliganBottomInsertionActiveBySeatId = {} }
");
script.DoString(File.ReadAllText(Path.Combine("..", "tts", "Global.lua")));
script.DoString(@"
    BridgeState.eventSessionId = 'session'
    BridgeState.physicalTransactionGeneration = 7
    BridgeState.libraryExtractionQueueBySeatId['forge-player-1'] = {
        {
            cardInstanceId = 'forge-object:17',
            expectedCardName = 'Island',
            run = function(complete)
                local tx = BridgeState.libraryExtractionTransactionBySeatId['forge-player-1']
                print('job before generation=' .. tostring(BridgeState.physicalTransactionGeneration))
                BridgeState.physicalTransactionGeneration = 8
                if tx ~= nil then tx.generation = 8 end
                print('job before complete generation=' .. tostring(BridgeState.physicalTransactionGeneration))
                complete('stale-callback')
            end
        }
    }
    BridgeState.libraryExtractionActiveBySeatId['forge-player-1'] = nil
    BridgeState.libraryExtractionTransactionBySeatId['forge-player-1'] = nil
    print('BEFORE=' .. tostring(#(BridgeState.libraryExtractionQueueBySeatId['forge-player-1'] or {})))
    BridgeProcessLibraryExtractionQueue('forge-player-1')
    local q = BridgeState.libraryExtractionQueueBySeatId['forge-player-1']
    print('AFTER=' .. tostring(q and #q or 'nil'))
    print('AFTER-RAW=' .. tostring(q and q[1] or 'nil'))
    print('ACTIVE=' .. tostring(BridgeState.libraryExtractionActiveBySeatId['forge-player-1']))
    print('TX=' .. tostring(BridgeState.libraryExtractionTransactionBySeatId['forge-player-1']))
");
