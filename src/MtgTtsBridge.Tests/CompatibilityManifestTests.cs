using System.Text.Json;
using MtgTtsBridge.Compatibility;

namespace MtgTtsBridge.Tests;

public sealed class CompatibilityManifestTests
{
    private static string ManifestPath => Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "Fixtures", "keyword-abilities.json"));
    [Fact] public void CanonicalManifestHasExactBaseline() { var m=ManifestLoader.Load(ManifestPath); Assert.Equal(194,m.Abilities.Count); Assert.Equal("702.2",m.Abilities[0].Rule); Assert.Equal("702.195",m.Abilities[^1].Rule); }
    [Fact] public void EveryEntryHasLegalLayersAndFamilies() { var m=ManifestLoader.Load(ManifestPath); foreach(var a in m.Abilities){Assert.Equal(7,a.Status.Count); Assert.All(a.Status.Values,s=>Assert.Contains(s,CompatibilityLayers.Statuses)); Assert.All(a.CapabilityFamilies,f=>Assert.Contains(f,CompatibilityLayers.Families));} }
    [Fact] public void UnknownStatusesSurviveReportAndEvidenceIsSurfaced() { var m=ManifestLoader.Load(ManifestPath); var r=ReportBuilder.Build(m); var c=r.Layers["forgeRules"]; Assert.Equal(194,c.VERIFIED+c.PARTIAL+c.MISSING+c.UNKNOWN+c.NOT_APPLICABLE); Assert.True(c.UNKNOWN>0); Assert.Contains(m.Abilities.Single(x=>x.Name=="Crew").Evidence,e=>e.Path=="tools/forge/bridge-headless.patch"); }
    [Fact] public void InvalidDuplicateAndMalformedEvidenceAreRejected() { var m=ManifestLoader.Load(ManifestPath); m.Abilities[1].Rule=m.Abilities[0].Rule; m.Abilities[0].Evidence.Add(new Evidence{Layer="forgeRules",Kind="contract_test",Path="C:\\secret",Test="x"}); var p=Path.Combine(Path.GetTempPath(),$"compat-{Guid.NewGuid():N}.json"); try { File.WriteAllText(p,JsonSerializer.Serialize(m)); Assert.Throws<InvalidDataException>(()=>ManifestLoader.Load(p)); } finally { if(File.Exists(p))File.Delete(p); } }
    [Fact] public void AuditExplicitlyReportsMissingForgeCheckout() { var a=ControllerAudit.Run(Path.Combine(Path.GetTempPath(),Guid.NewGuid().ToString("N"))); Assert.False(a.Ran); Assert.Contains("NOT RUN",a.Message); }
    [Fact] public void ValidatorDoesNotRequireForgeCheckout() { var m=ManifestLoader.Load(ManifestPath); Assert.NotNull(m); }
    [Fact] public void ReportLayerTotalsMatchManifest() { var m=ManifestLoader.Load(ManifestPath); var r=ReportBuilder.Build(m); foreach(var c in r.Layers.Values) Assert.Equal(194,c.VERIFIED+c.PARTIAL+c.MISSING+c.UNKNOWN+c.NOT_APPLICABLE); foreach(var f in CompatibilityLayers.Families) { var c=r.Families[f]; Assert.Equal(m.Abilities.Count(a=>a.CapabilityFamilies.Contains(f)),c.VERIFIED+c.PARTIAL+c.MISSING+c.UNKNOWN+c.NOT_APPLICABLE); } }
}
