namespace MtgTtsBridge.Tests;

public sealed class RelationshipPresentationContractTests
{
    private static readonly string RepositoryRoot = FindRepositoryRoot();
    private static readonly string Script = File.ReadAllText(Path.Combine(RepositoryRoot, "tts", "Global.lua"));

    private static string FindRepositoryRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null && !File.Exists(Path.Combine(directory.FullName, "tts", "Global.lua")))
            directory = directory.Parent;
        return directory?.FullName ?? throw new DirectoryNotFoundException("Repository root not found");
    }

    [Fact]
    public void SnapshotPresentationConsumesExactForgeRelationshipIdentity()
    {
        Assert.Contains("function BridgeApplyRelationshipSnapshot", Script);
        Assert.Contains("relation.sourceCardInstanceId", Script);
        Assert.Contains("relation.targetCardInstanceId", Script);
        Assert.Contains("BridgeState.physicalByInstanceId", Script);
        Assert.Contains("BridgeApplyRelationshipSnapshot(snapshot.relationships", Script);
        Assert.Contains("relationshipPresentationById", Script);
    }

    [Fact]
    public void AttachmentsAreDepictedWithoutWeldingOrInferringFromGeometry()
    {
        var start = Script.IndexOf("function BridgeApplyPhysicalRelationship", StringComparison.Ordinal);
        var end = Script.IndexOf("function BridgeRelationshipFooter", start, StringComparison.Ordinal);
        Assert.True(start >= 0);
        Assert.True(end > start);
        var attachment = Script[start..end];
        Assert.Contains("BridgeRelationshipIsAttachmentKind", Script);
        Assert.Contains("target.getPosition()", Script);
        Assert.Contains("setPositionSmooth", attachment);
        Assert.DoesNotContain("setLock", attachment);
        Assert.DoesNotContain("getObjects", attachment);
    }

    [Fact]
    public void NonAttachmentsUseReadableLabelsAndHaveAnIdentityAuthorizationHook()
    {
        Assert.Contains("function BridgeRelationshipIdentityAuthorized", Script);
        Assert.Contains("relationshipIdentityAuthorization", Script);
        Assert.Contains("LINKED FACE-DOWN CARD", Script);
        Assert.Contains("PAIRED WITH", Script);
        Assert.Contains("CHAMPIONED", Script);
        Assert.Contains("LINKED EXILE", Script);
        Assert.Contains("BridgeState.relationshipSummary", Script);
        Assert.Contains("BridgeUiSet(\"BridgeHudFooter\", \"text\", footer)", Script);
    }
}
