using MtgTtsBridge.Contracts.State;

namespace MtgTtsBridge.Tests;

public sealed class RelationshipGraphTests
{
    [Fact]
    public void NormalizesOneToOneRelationshipByExactIdentity()
    {
        var relation = new GameRelationshipSnapshotDto(
            " equip-2 ", " Equip ", "forge:s:2", "forge:s:9", Role: "carrier");

        var normalized = Assert.Single(GameRelationshipGraph.Normalize([relation]));

        Assert.Equal("equip-2", normalized.RelationshipId);
        Assert.Equal("equip", normalized.Kind);
        Assert.Equal("forge:s:2", normalized.SourceCardInstanceId);
        Assert.Equal("forge:s:9", normalized.TargetCardInstanceId);
    }

    [Fact]
    public void PreservesOneToManyGroupedAndOrderedRelationsDeterministically()
    {
        var relations = new[]
        {
            new GameRelationshipSnapshotDto("g-2", "mutate", "forge:s:1", "forge:s:3", GroupId: "merge", Role: "component", Order: 2),
            new GameRelationshipSnapshotDto("g-1", "mutate", "forge:s:1", "forge:s:2", GroupId: "merge", Role: "component", Order: 1),
            new GameRelationshipSnapshotDto("g-3", "mutate", "forge:s:1", "forge:s:4", GroupId: "merge", Role: "top", Order: 3)
        };

        var normalized = GameRelationshipGraph.Normalize(relations);

        Assert.Equal(["g-1", "g-2", "g-3"], normalized.Select(item => item.RelationshipId));
        Assert.All(normalized, item => Assert.Equal("merge", item.GroupId));
        Assert.Equal([1, 2, 3], normalized.Select(item => item.Order));
    }

    [Fact]
    public void KeepsDuplicateNamesAndCardToPlayerTargetAsIndependentRelations()
    {
        var normalized = GameRelationshipGraph.Normalize([
            new GameRelationshipSnapshotDto("a", "soulbond", "forge:s:a", "forge:s:b"),
            new GameRelationshipSnapshotDto("b", "soulbond", "forge:s:c", "forge:s:d"),
            new GameRelationshipSnapshotDto("c", "linked", "forge:s:e", TargetSeatId: "forge-player-2")]);

        Assert.Equal(3, normalized.Count);
        Assert.NotEqual(normalized[0].SourceCardInstanceId, normalized[1].SourceCardInstanceId);
        Assert.Equal("forge-player-2", normalized[2].TargetSeatId);
    }

    [Fact]
    public void RelationshipRemovalIsRepresentedBySnapshotSetDifference()
    {
        var before = GameRelationshipGraph.Normalize([
            new GameRelationshipSnapshotDto("old", "equip", "forge:s:a", "forge:s:b"),
            new GameRelationshipSnapshotDto("keep", "equip", "forge:s:c", "forge:s:d")]);
        var after = GameRelationshipGraph.Normalize([
            new GameRelationshipSnapshotDto("keep", "equip", "forge:s:c", "forge:s:d")]);

        Assert.Equal(["old"], before.Select(item => item.RelationshipId).Except(after.Select(item => item.RelationshipId)));
    }

    [Fact]
    public void RejectsBlankRelationshipIdentityOrKind()
    {
        Assert.Throws<ArgumentException>(() => GameRelationshipGraph.Normalize([
            new GameRelationshipSnapshotDto("", "equip")]));
        Assert.Throws<ArgumentException>(() => GameRelationshipGraph.Normalize([
            new GameRelationshipSnapshotDto("id", " ")]));
    }
}
