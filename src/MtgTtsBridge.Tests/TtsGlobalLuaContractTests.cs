namespace MtgTtsBridge.Tests;

public sealed class TtsGlobalLuaContractTests
{
    private static readonly string Script = File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.lua"));

    [Fact]
    public void EventPolling_IsSingleFlightAndRetriesTransientFailures()
    {
        Assert.Contains("eventPollGeneration", Script);
        Assert.Contains("eventRequestInFlight", Script);
        Assert.Contains("eventPollScheduled", Script);
        Assert.Contains("math.min(2 ^ (BridgeState.eventRetryCount - 1), 5)", Script);
        Assert.Contains("BridgeState.eventRetryCount = 0", Script);
        Assert.DoesNotContain("event poll failed: \" .. tostring(err)", Script);
    }

    [Fact]
    public void EventApplication_TracksReceivedAndAppliedCursorsSeparately()
    {
        Assert.Contains("lastReceivedEventSequence", Script);
        Assert.Contains("lastAppliedEventSequence", Script);
        Assert.DoesNotContain("lastEventSequence", Script);

        var failedApplication = Script.IndexOf("if not applied then", StringComparison.Ordinal);
        var appliedAdvance = Script.IndexOf("BridgeState.lastAppliedEventSequence = event.sequence", StringComparison.Ordinal);
        Assert.True(failedApplication >= 0);
        Assert.True(appliedAdvance > failedApplication);
    }

    [Fact]
    public void EventHistoryAndSequenceGaps_StopSynchronization()
    {
        Assert.Contains("body.errorCode == \"event_history_gap\"", Script);
        Assert.Contains("event sequence gap: expected", Script);
        Assert.Contains("event application gap: expected", Script);
        Assert.Contains("BridgeStopOnDesync", Script);
    }

    [Fact]
    public void BattlefieldMovement_ReleasesHandsAndUsesMeasuredBlueAnchors()
    {
        Assert.Contains("land = {x = 6.5, y = 2.0, z = 11.5}", Script);
        Assert.Contains("creature = {x = 7.0, y = 2.0, z = 3.5}", Script);

        var releaseHand = Script.IndexOf("object.use_hands = false", StringComparison.Ordinal);
        var directMove = Script.IndexOf("object.setPosition(destination)", StringComparison.Ordinal);
        Assert.True(releaseHand >= 0);
        Assert.True(directMove > releaseHand);
    }

    [Fact]
    public void HumanIntent_IsStagedUntilDropAndRollbackRestoresPhysicalState()
    {
        var pickup = Script.IndexOf("function onObjectPickUp", StringComparison.Ordinal);
        var drop = Script.IndexOf("function onObjectDrop", StringComparison.Ordinal);
        var submit = Script.IndexOf("BridgeSubmitChoice(intent.decisionId, intent.action.actionId)", drop, StringComparison.Ordinal);

        Assert.True(pickup >= 0);
        Assert.True(drop > pickup);
        Assert.True(submit > drop);
        Assert.Contains("useHands = object.use_hands", Script);
        Assert.Contains("object.use_hands = intent.useHands", Script);
        Assert.Contains("BridgeRenderDecision(BridgeState.lastDecision)", Script);
    }

    [Fact]
    public void TurnYield_UsesForgePassAndTurnEventsDriveTtsPresentation()
    {
        Assert.Contains("function onPlayerTurnEnd", Script);
        Assert.Contains("BridgeState.yieldSeatId = decision.seatId", Script);
        Assert.Contains("if action.type == \"pass_yield\"", Script);
        Assert.Contains("Turns.turn_color = seat.ttsColor", Script);
    }

    [Fact]
    public void PlayerTargets_AreMachineTypedAndUseConfiguredSeatSurface()
    {
        Assert.Contains("action.targetKind == \"player\"", Script);
        Assert.Contains("action.targetSeatId", Script);
        Assert.Contains("targetSurfaceGuid", Script);
        Assert.Contains("click_function = \"BridgeSelectPlayerTarget\"", Script);
        Assert.DoesNotContain("action.displayName == \"Player", Script);
    }

    [Fact]
    public void ExistingCardModules_AreUpdatedByAbsoluteAuthoritativeState()
    {
        Assert.Contains("APIobjGetPropData", Script);
        Assert.Contains("propID = \"_MTG_Simplified_UNIFIED\"", Script);
        Assert.Contains("encoded.tyrantUnified[field] = counterValue", Script);
        Assert.Contains("propID = \"πKeywords\"", Script);
        Assert.Contains("data[property] = enabled and 1 or 0", Script);
        Assert.Contains("APIobjSetPropData", Script);
        Assert.Contains("APIrebuildButtons", Script);
    }

    [Fact]
    public void ManualDrawCannotMutateForgeAuthoritativeLibrary()
    {
        var drawStart = Script.IndexOf("function drawSwap", StringComparison.Ordinal);
        var drawEnd = Script.IndexOf("function BridgeGetHealth", drawStart, StringComparison.Ordinal);
        var drawFunction = Script[drawStart..drawEnd];

        Assert.Contains("manual Draw is disabled", drawFunction);
        Assert.DoesNotContain(".deal(", drawFunction);
    }

    [Fact]
    public void DeveloperSyncDumpIncludesMappingsZonesAndCursors()
    {
        Assert.Contains("function BridgeDumpSyncState", Script);
        Assert.Contains("physicalByInstanceId", Script);
        Assert.Contains("physicalZoneByGuid", Script);
        Assert.Contains("lastReceivedEventSequence", Script);
        Assert.Contains("lastAppliedEventSequence", Script);
    }

    [Fact]
    public void SnapshotBootstrap_MapsUniqueInstancesAndPreservesForgeLibraryPosition()
    {
        Assert.Contains("/api/v1/embodiment/snapshot", Script);
        Assert.Contains("BridgeState.physicalByInstanceId[card.cardInstanceId] = guid", Script);
        Assert.Contains("count - card.zonePosition", Script);
        Assert.Contains("BridgeNormalizeCardName(card.cardName)", Script);
        Assert.Contains("hidden identities redacted", Script);
    }

    [Fact]
    public void AuthoritativeDraw_TakesExactMappedGuidFromPhysicalDeckWithoutChatLeak()
    {
        Assert.Contains("if event.kind == \"draw\"", Script);
        Assert.Contains("BridgeFindDeckContainingGuid(guid)", Script);
        Assert.Contains("deck.takeObject({", Script);
        Assert.Contains("guid = guid", Script);
        Assert.Contains("card identity redacted", Script);
    }

    [Fact]
    public void StructuredZoneAndTapChanges_UseInstanceMappingAndAbsoluteState()
    {
        Assert.Contains("if event.kind == \"card_moved\"", Script);
        Assert.Contains("if event.kind == \"tap_changed\"", Script);
        Assert.Contains("BridgeSetPhysicalTapped(object, event.tapped == true)", Script);
        Assert.Contains("local targetZ = base.z + (tapped and 90 or 0)", Script);
    }

    [Fact]
    public void RealDecisionIdentity_WinsOverDuplicateNameFallback()
    {
        Assert.Contains("action.cardInstanceId and BridgeState.physicalByInstanceId[action.cardInstanceId]", Script);
        Assert.Contains("if mappedObject ~= nil then", Script);
        Assert.Contains("if mappedGuid == nil and #matches > 1 then", Script);
    }
}
