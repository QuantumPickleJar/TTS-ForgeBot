namespace MtgTtsBridge.Tests;

public sealed class RelationshipProducerContractTests
{
    private static readonly string RepositoryRoot = FindRepositoryRoot();
    private static readonly string Patch = File.ReadAllText(Path.Combine(RepositoryRoot, "tools", "forge", "bridge-headless.patch"));

    private static string FindRepositoryRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null && !File.Exists(Path.Combine(directory.FullName, "tools", "forge", "bridge-headless.patch")))
            directory = directory.Parent;
        return directory?.FullName ?? throw new DirectoryNotFoundException("Repository root not found");
    }

    [Fact]
    public void ProducerExportsNativeAttachmentAndPairIdentityPointers()
    {
        Assert.Contains("appendRelationships(json)", Patch);
        Assert.Contains("source.isAttachedToEntity()", Patch);
        Assert.Contains("source.getEntityAttachedTo()", Patch);
        Assert.Contains("source.getPairedWith()", Patch);
        Assert.Contains("source.getHaunting()", Patch);
        Assert.Contains("source.getEncodedCards()", Patch);
        Assert.Contains("source.getRemembered()", Patch);
        Assert.Contains("source.getExiledWith()", Patch);
        Assert.Contains("source.getMergedCards()", Patch);
        Assert.Contains("source.getMeldedWith()", Patch);
        Assert.Contains("ZoneType.Merged", Patch);
        Assert.Contains("sourceForgeObjectId", Patch);
        Assert.Contains("targetForgeObjectId", Patch);
        Assert.Contains("targetSeatId", Patch);
    }

    [Fact]
    public void ProducerDoesNotInferRelationshipsFromPresentationNamesOrGeometry()
    {
        var start = Patch.IndexOf("private void appendRelationships", StringComparison.Ordinal);
        Assert.True(start >= 0);
        var end = Patch.IndexOf("private void appendCombat", start, StringComparison.Ordinal);
        Assert.True(end > start);
        var relationshipProducer = Patch[start..end];
        Assert.DoesNotContain("getName()", relationshipProducer);
        Assert.DoesNotContain("position", relationshipProducer);
        Assert.DoesNotContain("getObjects", relationshipProducer);
    }

    [Fact]
    public void ProducerCarriesGroupedAndOrderedNativeRelationshipMetadata()
    {
        Assert.Contains("groupId", Patch);
        Assert.Contains("role", Patch);
        Assert.Contains("order", Patch);
        Assert.Contains("source.hasKeyword(\"Champion\")", Patch);
        Assert.Contains("\"cipher\"", Patch);
        Assert.Contains("\"haunt\"", Patch);
        Assert.Contains("\"linked_exile\"", Patch);
        Assert.Contains("\"mutate\"", Patch);
    }
}
