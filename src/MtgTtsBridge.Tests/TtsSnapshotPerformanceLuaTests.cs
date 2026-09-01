using MoonSharp.Interpreter;

namespace MtgTtsBridge.Tests;

public sealed class TtsSnapshotPerformanceLuaTests
{
    private static readonly string Script = File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.lua"));

    [Fact]
    public void ZeroResources_DoNotScanTheWorldDuringSteadyStateRefresh()
    {
        var lua = new Script();
        lua.DoString($@"
            BRIDGE_RESOURCE_ORDER = {{""W"", ""U"", ""B"", ""R"", ""G"", ""C"", ""energy"", ""experience"", ""poison"", ""speed""}}
            BRIDGE_SEATS = {{[""forge-player-1""] = {{lifeCounterGuid = ""life""}}}}
            BridgeState = {{presentationMetrics = {{}}, resourceCounterGuidBySeatId = {{}}, playerStateBySeatId = {{}}, manaCounterGuidBySeatId = {{}}, playerTrackerGuidBySeatId = {{}}}}
            worldScanCalls = 0
            function getAllObjects() worldScanCalls = worldScanCalls + 1; return {{}} end
            function BridgePresentationMetric(name) BridgeState.presentationMetrics[name] = (BridgeState.presentationMetrics[name] or 0) + 1 end
            function BridgePerformanceBegin(name) return {{}} end
            function BridgePerformanceEnd(token, marker, summaryKey, detail) end
            function BridgeGetLiveObjectByGuid(guid)
                if guid == ""life"" then return {{getPosition = function() return {{x=0,y=0,z=0}} end}} end
                return nil
            end
            function BridgeResourceDefinition(kind) return {{name = ""Forge "" .. kind}} end
            function BridgeResourceValue(seatId, kind) return 0 end
            function BridgeResourceRowPosition(seatId, slot) return {{0, 0, 0}} end
            function BridgeObjectIsUsable(object) return object ~= nil end
            function BridgeSafeObjectName(object) return object.name end
            function BridgeSafeObjectGuid(object) return object.guid end
            function BridgeHideResourceCounter(counter) end
            function BridgeCreateResourceCounter(seatId, kind, definition, position) return nil end
            function BridgeShowResourceCounter(counter, position, seat) end
            function BridgeSetNativeTrackerValue(counter, value) end
            function BridgeRegisterPresentationObject(object, kind) end
            {Extract("function BridgeFindResourceCounter", "function BridgeCreateResourceCounter")}
            {Extract("function BridgeRefreshResourceRow", "function BridgeEnsureManaBank")}
            BridgeRefreshResourceRow(""forge-player-1"")
        ");

        Assert.Equal(0, lua.Globals.Get("worldScanCalls").Number);
        Assert.Equal(1, lua.Globals.Get("BridgeState").Table.Get("presentationMetrics").Table.Get("resourceRowRefreshCount").Number);
    }

    [Fact]
    public void Hydration_UsesOneWorldScanToRecoverExistingPresentationObjects()
    {
        var lua = new Script();
        lua.DoString($@"
            BridgeState = {{presentationMetrics = {{}}, resourceCounterGuidBySeatId = {{}}, monarchHelperGuid = nil, resourceCounterIndexHydrated = false, monarchHelperIndexHydrated = false}}
            worldScanCalls = 0
            function getAllObjects() worldScanCalls = worldScanCalls + 1; return {{ {{guid=""u1"", name=""Forge Mana U forge-player-1"", tag=""Counter""}} }} end
            function BridgePresentationMetric(name) BridgeState.presentationMetrics[name] = (BridgeState.presentationMetrics[name] or 0) + 1 end
            function BridgeObjectIsUsable(object) return object ~= nil end
            function BridgeSafeObjectGuid(object) return object.guid end
            function BridgeSafeObjectName(object) return object.name end
            function BridgeRegisterPresentationObject(object, kind) end
            {Extract("function BridgeHydratePresentationObjectIndexes", "function BridgeFindResourceCounter")}
            BridgeHydratePresentationObjectIndexes()
        ");

        Assert.Equal(1, lua.Globals.Get("worldScanCalls").Number);
        var resources = lua.Globals.Get("BridgeState").Table.Get("resourceCounterGuidBySeatId").Table;
        Assert.Equal("u1", resources.Get("forge-player-1").Table.Get("U").String);
        lua.DoString("BridgeHydratePresentationObjectIndexes()");
        Assert.Equal(1, lua.Globals.Get("worldScanCalls").Number);
    }

    [Fact]
    public void OneSeatSnapshot_PerformsOneFinalResourceRowRefresh()
    {
        var lua = new Script();
        lua.DoString($@"
            BRIDGE_SEATS = {{[""forge-player-1""] = {{lifeCounterGuid = ""life""}}}}
            BridgeState = {{playerCountersBySeatId = {{}}, playerStateBySeatId = {{}}, preparedDesignationStateByInstanceId = {{}}, cardDesignationsByInstanceId = {{}}, physicalByInstanceId = {{}}, physicalSeatByGuid = {{}}, physicalZoneByGuid = {{}}, preparedBadgeGuidByInstanceId = {{}}, preparedPresentationGuidByInstanceId = {{}}}}
            refreshes = 0
            function BridgeNormalizeCounterName(name) return name end
            function BridgeGetLiveObjectByGuid(guid) return {{setValue = function(self, value) end}} end
            function BridgeSetManaBank(seatId, mana, deferRefresh) end
            function BridgeRefreshResourceRow(seatId) refreshes = refreshes + 1 end
            function BridgeSetPhysicalTapped(object, tapped) end
            function BridgeSetPreparedDesignationPresentation(object, prepared) end
            function BridgeEnsurePreparedBadge(object, instanceId, prepared) end
            function BridgePulsePreparedDesignation(object, instanceId) end
            function BridgeSetPrototypeDesignationPresentation(object, prototyped) end
            function BridgeDestroyPreparedBadge(instanceId) end
            {Extract("function BridgeApplySeatTrackers", "function BridgeFindLiveMonarchHelper")}
            {Extract("function BridgeApplySeatSnapshotVisualState", "function BridgeResourceDefinition")}
            BridgeApplySeatSnapshotVisualState({{seatId=""forge-player-1"", life=20, poison=0, manaPool={{U=0}}, counters={{}}, zones={{}}}})
        ");

        Assert.Equal(1, lua.Globals.Get("refreshes").Number);
    }

    [Fact]
    public void RoutineSnapshotRequests_AreLatestWinsAndSingleFlight()
    {
        var lua = new Script();
        lua.DoString($@"
            BridgeState = {{snapshotReconcileRequestGeneration = 0, snapshotReconcilePendingRequest = nil, snapshotReconcilePending = false, eventQueue = {{}}, lastReceivedEventSequence = 3, lastAppliedEventSequence = 3, animationRunning = false}}
            {Extract("function BridgeSnapshotRequestCategory", "function BridgeApplyCombatSnapshot")}
            BridgeRememberSnapshotRequest(""event 1"", ""ROUTINE_VERIFY"")
            BridgeRememberSnapshotRequest(""event 2"", ""ROUTINE_VERIFY"")
            BridgeRememberSnapshotRequest(""event 3"", ""ROUTINE_VERIFY"")
        ");

        var state = lua.Globals.Get("BridgeState").Table;
        Assert.Equal("event 3", state.Get("snapshotReconcilePendingRequest").Table.Get("reason").String);
        Assert.Equal(3, state.Get("snapshotReconcileRequestGeneration").Number);
        Assert.True(state.Get("snapshotReconcilePending").Boolean);
    }

    [Fact]
    public void DeferredRoutineSnapshot_IsSkippedAfterEquivalentCursorAndRecoveryStillApplies()
    {
        var lua = new Script();
        lua.DoString($@"
            BridgeState = {{deferredSnapshotReconcile = {{snapshot={{eventCursor=4}}, category=""ROUTINE_VERIFY"", reason=""event 4""}}, snapshotReconcileLastAppliedCursor=4, eventQueue={{}}, animationRunning=false, presentationMetrics={{}}, pendingStructuredZoneTransitionByInstanceId={{}}}}
            function BridgeSnapshotMayMutatePublicZones(snapshot) return true end
            function BridgePhysicalLibraryQueuesIdle() return true end
            function BridgeRoutineSnapshotBlocked() return false end
            function BridgeSnapshotRequestCategory(reason, category) return category or ""RECOVERY"" end
            function BridgeLogSnapshotOrdering(marker, snapshot, reason) end
            applied = 0
            function BridgeApplySafeSnapshotReconcile(snapshot, reason) applied = applied + 1 end
            {Extract("function BridgeSnapshotRequestPriority", "function BridgeApplyCombatSnapshot")}
            {Extract("function BridgeTryApplyDeferredSnapshotReconcile", "function BridgeScheduleSnapshotReconcile")}
            BridgeTryApplyDeferredSnapshotReconcile(""drain"")
            BridgeState.deferredSnapshotReconcile = {{snapshot={{eventCursor=4}}, category=""RECOVERY"", reason=""recovery""}}
            BridgeTryApplyDeferredSnapshotReconcile(""drain"")
        ");

        Assert.Equal(1, lua.Globals.Get("applied").Number);
    }

    [Fact]
    public void AutomatedYield_IsHeldWhileAuthoritativeEventsAreUnapplied()
    {
        var lua = new Script();
        lua.DoString($@"
            BridgeState = {{lastReceivedEventSequence=8, lastAppliedEventSequence=6, eventQueue={{}}, animationRunning=false, snapshotReconcileInFlight=false, presentationMetrics={{}}}}
            function BridgePresentationMetric(name) BridgeState.presentationMetrics[name] = (BridgeState.presentationMetrics[name] or 0) + 1 end
            function BridgeLog(message) end
            {Extract("function BridgeAutomaticPassBackpressured", "-- Freeze-flight telemetry")}
        ");

        Assert.True(lua.Globals.Get("BridgeAutomaticPassBackpressured").Function.Call().Boolean);
        Assert.Equal(1, lua.Globals.Get("BridgeState").Table.Get("presentationMetrics").Table.Get("yieldBackpressurePauseCount").Number);
        lua.DoString("BridgeState.lastAppliedEventSequence = 8; BridgeState.snapshotReconcileInFlight = false");
        Assert.False(lua.Globals.Get("BridgeAutomaticPassBackpressured").Function.Call().Boolean);
    }

    private string Extract(string startMarker, string endMarker)
    {
        var start = Script.IndexOf(startMarker, StringComparison.Ordinal);
        var end = Script.IndexOf(endMarker, start, StringComparison.Ordinal);
        Assert.True(start >= 0 && end > start, $"Could not extract {startMarker}");
        return Script[start..end];
    }
}
