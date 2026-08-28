using MtgTtsBridge.Forge;

namespace MtgTtsBridge.Tests;

public sealed class RelationshipSnapshotIntegrationTests
{
    [Fact]
    public void SnapshotRoundTripsExactGroupedAndOrderedRelationships()
    {
        var parser = new ForgeStructuredOutputParser();
        var snapshot = Assert.Single(parser.Append(ForgeStructuredOutputParser.Sentinel +
            "{\"version\":1,\"type\":\"snapshot\",\"sequence\":1,\"reason\":\"test\",\"players\":[],\"stack\":[],\"relationships\":[" +
            "{\"relationshipId\":\"merge-2\",\"kind\":\"mutate\",\"sourceForgeObjectId\":10,\"targetForgeObjectId\":12,\"groupId\":\"merge\",\"role\":\"component\",\"order\":2}," +
            "{\"relationshipId\":\"merge-1\",\"kind\":\"mutate\",\"sourceForgeObjectId\":10,\"targetForgeObjectId\":11,\"groupId\":\"merge\",\"role\":\"top\",\"order\":1}]}\n").Snapshots);

        var reconciler = new ForgeStructuredStateReconciler();
        reconciler.Apply("session-a", snapshot);

        var graph = reconciler.Current!.Relationships!;
        Assert.Equal(["merge-1", "merge-2"], graph.Select(item => item.RelationshipId));
        Assert.Equal("forge:session-a:11", graph[0].TargetCardInstanceId);
        Assert.Equal("merge", graph[1].GroupId);
    }

    [Fact]
    public void RelationshipRemovalAndTargetChangeAreSnapshotAuthoritative()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        var first = Parse(parser, Frame(1, "[{\"relationshipId\":\"equip\",\"kind\":\"equip\",\"sourceForgeObjectId\":1,\"targetForgeObjectId\":2}]"));
        reconciler.Apply("s", first);
        var second = Parse(parser, Frame(2, "[{\"relationshipId\":\"equip\",\"kind\":\"equip\",\"sourceForgeObjectId\":1,\"targetForgeObjectId\":3}]"));
        reconciler.Apply("s", second);
        Assert.Equal("forge:s:3", Assert.Single(reconciler.Current!.Relationships!).TargetCardInstanceId);
        var third = Parse(parser, Frame(3, "[]"));
        reconciler.Apply("s", third);
        Assert.Empty(reconciler.Current!.Relationships!);
    }

    [Fact]
    public void RelationshipsSurviveUnrelatedSnapshotChanges()
    {
        var parser = new ForgeStructuredOutputParser();
        var reconciler = new ForgeStructuredStateReconciler();
        reconciler.Apply("s", Parse(parser, Frame(1, "[{\"relationshipId\":\"pair\",\"kind\":\"soulbond\",\"sourceForgeObjectId\":1,\"targetForgeObjectId\":2}]")));
        reconciler.Apply("s", Parse(parser, Frame(2, "[{\"relationshipId\":\"pair\",\"kind\":\"soulbond\",\"sourceForgeObjectId\":1,\"targetForgeObjectId\":2}]", reason: "phase_changed")));
        Assert.Equal("pair", Assert.Single(reconciler.Current!.Relationships!).RelationshipId);
    }

    private static ForgeStructuredSnapshot Parse(ForgeStructuredOutputParser parser, string frame) =>
        Assert.Single(parser.Append(frame + "\n").Snapshots);

    private static string Frame(long sequence, string relationships, string reason = "test") =>
        ForgeStructuredOutputParser.Sentinel +
        $"{{\"version\":1,\"type\":\"snapshot\",\"sequence\":{sequence},\"reason\":\"{reason}\",\"players\":[],\"stack\":[],\"relationships\":{relationships}}}";
}
