namespace MtgTtsBridge.Tests;

public sealed class ForgeProducerContractTests
{
    private static readonly string RepositoryRoot = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", ".."));
    private static readonly string Patch = File.ReadAllText(Path.Combine(RepositoryRoot, "tools", "forge", "bridge-headless.patch"));
    private static readonly string Bootstrap = File.ReadAllText(Path.Combine(RepositoryRoot, "tools", "forge", "bootstrap.ps1"));
    private static readonly string Launcher = File.ReadAllText(Path.Combine(RepositoryRoot, "tools", "Start-ForgeBot.ps1"));

    [Fact]
    public void TrackedBridgeStateFeed_EmitsTheStructuredCharacteristicAndPlayerContract()
    {
        Assert.Contains("\"currentPower\"", Patch);
        Assert.Contains("\"currentToughness\"", Patch);
        Assert.Contains("\\\"currentTypes\\\"", Patch);
        Assert.Contains("\"ownerSeatId\"", Patch);
        Assert.Contains("\"controllerSeatId\"", Patch);
        Assert.Contains("\"tapped\"", Patch);
        Assert.Contains("\\\"counters\\\"", Patch);
        Assert.Contains("\\\"keywords\\\"", Patch);
        Assert.Contains("\"speed\"", Patch);
        Assert.Contains("\\\"designations\\\"", Patch);
        Assert.Contains("\"monarchSeatId\"", Patch);
        Assert.Contains("ZoneType.Command", Patch);
    }

    [Fact]
    public void TrackedBridgeStateFeed_UsesADirtyGenerationInsteadOfLossyOneShotCoalescing()
    {
        Assert.Contains("AtomicLong mutationGeneration", Patch);
        Assert.Contains("mutationGeneration.incrementAndGet()", Patch);
        Assert.Contains("if (mutationGeneration.get() != generation)", Patch);
        Assert.Contains("ThreadUtil.delay(25, this::emitWhenStable)", Patch);
        Assert.Contains("trace(\"event=\"", Patch);
        Assert.Contains("battlefieldSummary()", Patch);
    }

    [Fact]
    public void TrackedBridgeStateFeed_UsesOnlyTheCompleteCombatSnapshotForBlockers()
    {
        Assert.Contains("GameEventBlockersDeclared", Patch);
        Assert.Contains("not an exact blocker identity", Patch);
        Assert.Contains("sole authoritative source for presentation", Patch);
        Assert.Contains("\\\"blockerForgeObjectIds\\\"", Patch);
        Assert.Contains("combat.getBlockers(attacker)", Patch);
        Assert.DoesNotContain("emitBlockerDeclarations", Patch);
        Assert.DoesNotContain("+++ Block: ", Patch);
    }

    [Fact]
    public void TrackedBridgeStateFeed_EmitsEmptyCombatDuringNewMatchStartup()
    {
        Assert.Contains("json.append(\"],\\\"combat\\\":\");", Patch);
        Assert.Contains("if (combat == null)", Patch);
        Assert.Contains("json.append(\"]}\");", Patch);
    }

    [Fact]
    public void ForgeBuildStamp_BindsJarToPatchAndUpstreamCommit()
    {
        Assert.Contains("forge-headless-bridge-build.json", Bootstrap);
        Assert.Contains("Skipping patch application because Forge has local bridge changes", Bootstrap);
        Assert.Contains("if ($hasLocalChanges)", Bootstrap);
        Assert.Contains("bridgePatchSha256", Bootstrap);
        Assert.Contains("upstreamForgeCommit", Bootstrap);
        Assert.Contains("jarSha256", Bootstrap);
        Assert.Contains("patchedSourceSha256", Bootstrap);
        Assert.Contains("bridgePatchSha256", Launcher);
        Assert.Contains("patchedSourceSha256", Launcher);
        Assert.Contains("BridgeStateFeed source is newer than the assembled JAR", Launcher);
    }
}
