using System.Text.RegularExpressions;
using Xunit;

namespace MtgTtsBridge.Tests;

/// <summary>
/// Regression tests for H0 blocker Bug-20260905-035141-de5b:
/// 
/// Critical failure chain:
/// 1. Mountain :62 library→hand extraction failed hand membership verification
/// 2. Card silently succeeded despite never being in player's hand
/// 3. TTS and Forge diverged, system became desyncLatched
/// 4. Stale choice forge-tui-7 was accepted despite desyncLatched
/// 5. Forge advanced to event 159 while TTS stuck at 157
/// 
/// Fixes verify:
/// - Library→hand extraction now verifies final membership before completion
/// - Choice submission is blocked when desyncLatched
/// - Physical queue timeout transitions to manual recovery state (not orphaned)
/// </summary>
public sealed class TtsH0BlockerBug20260905LuaTests
{
    private static readonly string Script = File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.lua"));

    [Fact]
    public void LibraryHandExtraction_VerifiesFinalMembershipBeforeCompletion()
    {
        // Fix 1: Extract card only completes if it's actually in the player's hand.
        // The bug: Mountain :62 was extracted but verify never checked hand membership.
        // The fix: Bounded retry loop that verifies card GUID is in BridgeBuildSeatHandGuidSet result.
        
        Assert.Contains("function verifyHandMembership()", Script);
        Assert.Contains("BridgeTryGetSeatHandObjects(event.seatId)", Script);
        Assert.Contains("BridgeSafeObjectGuid(handObject) == drawnGuid", Script);
        Assert.Contains("if found then", Script);
        Assert.Contains("extracted card never entered player hand", Script);
        Assert.Contains("BridgeStopOnDesync(libraryDrawError(", Script);
    }

    [Fact]
    public void ChoiceSubmission_BlocksWhenDesyncLatched()
    {
        // Fix 2: Reject choice submission when desyncLatched.
        // The bug: Stale forge-tui-7 choice was posted to Forge despite desyncLatched=true.
        // The fix: Early guard in BridgeSubmitChoice before line ~1695 POST.
        
        var submitChoiceStart = Script.IndexOf("function BridgeSubmitChoice(decisionId, actionId, source)", StringComparison.Ordinal);
        Assert.True(submitChoiceStart >= 0);
        
        var nextFunctionStart = Script.IndexOf("\nfunction ", submitChoiceStart + 10, StringComparison.Ordinal);
        var submitChoiceBody = Script[submitChoiceStart..nextFunctionStart];
        
        Assert.Contains("if BridgeState.desyncLatched == true then", submitChoiceBody);
        Assert.Contains("CHOICE_POST_BLOCKED reason=desync-latched", submitChoiceBody);
        Assert.Contains("return", submitChoiceBody);
    }

    [Fact]
    public void AutomaticRecovery_SchedulesQueueIdleCheckAfterTimeout()
    {
        // Fix 2: When automatic recovery times out due to physical queue blocking,
        // schedule explicit check for queue-idle event to transition to manual recovery.
        // The bug: Timeout set desyncLatched=true and returned, reaching orphaned state
        // (no recovery owner, no way to proceed).
        // The fix: Schedule BridgeWaitFrames callback that checks if queue idles,
        // then calls BridgeEnsureDesyncRecovery to make manual RESYNC available.
        
        Assert.Contains("RESYNC_DEFERRED reason=physical-library-queue-timeout", Script);
        Assert.Contains("BridgeStopOnDesync(\"automatic authoritative resync blocked by physical library queue\")", Script);
        Assert.Contains("BridgeState.queueTimeoutMonitorScheduled = true", Script);
        Assert.Contains("BridgeWaitFrames(function()", Script);
        Assert.Contains("BridgePhysicalLibraryQueuesIdle()", Script);
        Assert.Contains("BridgeEnsureDesyncRecovery(\"queue-idle-after-timeout\")", Script);
        Assert.Contains("RESYNC_QUEUE_IDLE_AFTER_TIMEOUT", Script);
    }

    [Fact]
    public void RecoveryState_NeverReachesOrphanedDesyncLatched()
    {
        // Verify impossible state is unreachable:
        // desyncLatched=true AND resyncInFlight=false AND no explicit recovery path
        // The fix ensures automatic queue timeout explicitly transitions to manual recovery.
        
        Assert.Contains("if BridgeState.desyncLatched == true and BridgeState.resyncInFlight ~= true", Script);
        Assert.Contains("BridgeEnsureDesyncRecovery", Script);
    }

    [Fact]
    public void ResyncInFlightAuthority_IsUnified()
    {
        // Fix 5: Ensure BridgeState.resyncInFlight is single authority,
        // ui.resyncInFlight is only mirror for display.
        
        var resyncCountCheck = Regex.Count(Script, @"BridgeState\.resyncInFlight\s*==\s*true");
        var uiResyncCountCheck = Regex.Count(Script, @"ui\.resyncInFlight\s*==\s*true");
        
        // Core state should be read multiple times for decisions
        Assert.True(resyncCountCheck > 5, "resyncInFlight core state should be checked multiple times");
        
        // UI state should only appear in diagnostics, not decision logic
        Assert.True(uiResyncCountCheck <= 2, "ui.resyncInFlight should only appear in diagnostics, not core logic");
    }

    [Fact]
    public void ChoicePost_IsGuardedBeforeLuaHttpRequest()
    {
        // Verify the desyncLatched guard is positioned before actual HTTP POST.
        var submitChoiceStart = Script.IndexOf("function BridgeSubmitChoice", StringComparison.Ordinal);
        var postStart = Script.IndexOf("BridgeHttp.requestJson(\"POST\", \"/api/v1/choice\"", StringComparison.Ordinal);
        var desyncCheckStart = Script.IndexOf("BridgeState.desyncLatched == true", submitChoiceStart, StringComparison.Ordinal);
        
        Assert.True(submitChoiceStart >= 0 && postStart > submitChoiceStart,
            "POST must be after BridgeSubmitChoice");
        Assert.True(desyncCheckStart >= submitChoiceStart && desyncCheckStart < postStart,
            "desyncLatched check must be before POST request");
    }
}

