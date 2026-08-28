using System.Text.Json;
using System.Text.Json.Serialization;

namespace MtgTtsBridge.Compatibility;

public static class CompatibilityLayers
{
    public static readonly string[] All = ["forgeRules", "humanController", "bridgeTransport", "snapshotState", "ttsPresentation", "automatedCanary", "liveTtsCanary"];
    public static readonly HashSet<string> Statuses = ["VERIFIED", "PARTIAL", "MISSING", "UNKNOWN", "NOT_APPLICABLE"];
    public static readonly HashSet<string> Families = ["BASIC_STATE", "GENERIC_HUMAN_CHOICE", "U0_HIDDEN_INFORMATION", "U1_RELATIONSHIPS", "U2_CAST_PAYMENT", "U3_VIRTUAL_COPY", "U4_COMBAT_RELATIONSHIP", "U5_DESIGNATION_STATE", "U6_MULTIPLAYER_SUPPLEMENTAL"];
    public static readonly HashSet<string> EvidenceKinds = ["forge_test", "forgebot_test", "contract_test", "automated_test", "live_tts_canary", "known_limitation", "source_contract", "manual_canary"];
}

public sealed class CompatibilityManifest
{
    public int SchemaVersion { get; set; }
    public string RulesBaseline { get; set; } = "";
    public string EffectiveDate { get; set; } = "";
    public RuleRange Range { get; set; } = new();
    public List<KeywordAbility> Abilities { get; set; } = [];
}
public sealed class RuleRange { public string First { get; set; } = ""; public string Last { get; set; } = ""; }
public sealed class KeywordAbility
{
    public string Rule { get; set; } = "";
    public string Name { get; set; } = "";
    public List<string> CapabilityFamilies { get; set; } = [];
    public Dictionary<string,string> Status { get; set; } = new(StringComparer.Ordinal);
    public List<Evidence> Evidence { get; set; } = [];
}
public sealed class Evidence
{
    public string Layer { get; set; } = "";
    public string Kind { get; set; } = "";
    public string Path { get; set; } = "";
    public string? Test { get; set; }
    public string? Description { get; set; }
}

public static class ManifestLoader
{
    public static readonly JsonSerializerOptions JsonOptions = new() { PropertyNameCaseInsensitive = true, ReadCommentHandling = JsonCommentHandling.Disallow };
    public static CompatibilityManifest Load(string path)
    {
        var manifest = JsonSerializer.Deserialize<CompatibilityManifest>(File.ReadAllText(path), JsonOptions) ?? throw new InvalidDataException("Manifest is empty.");
        Validate(manifest, path);
        return manifest;
    }
    public static void Validate(CompatibilityManifest m, string? source = null)
    {
        var errors = new List<string>();
        if (m.SchemaVersion != 1) errors.Add("schemaVersion must be 1");
        if (m.EffectiveDate != "2026-08-07") errors.Add("effectiveDate must be 2026-08-07");
        if (m.Range is null || m.Range.First != "702.2" || m.Range.Last != "702.195") errors.Add("range must be 702.2 through 702.195");
        if (m.Abilities is null) { errors.Add("abilities array is missing"); throw new InvalidDataException($"Invalid compatibility manifest{(source is null ? "" : $" '{source}'")}:\n - "+string.Join("\n - ",errors)); }
        if (m.Abilities.Count != 194) errors.Add($"abilities must contain exactly 194 entries (found {m.Abilities.Count})");
        var rules = new HashSet<string>(StringComparer.Ordinal); var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        for (var i=0; i<m.Abilities.Count; i++)
        {
            var a=m.Abilities[i]; if (a is null) { errors.Add($"entry {i} is null"); continue; } var expected=$"702.{i+2}";
            if (a.Rule != expected) errors.Add($"entry {i} rule must be {expected}");
            if (!rules.Add(a.Rule)) errors.Add($"duplicate rule {a.Rule}");
            if (string.IsNullOrWhiteSpace(a.Name) || !names.Add(a.Name.Trim())) errors.Add($"blank or duplicate keyword name at {a.Rule}");
            if (a.CapabilityFamilies is null || a.CapabilityFamilies.Count==0) errors.Add($"{a.Rule} has no capability family");
            foreach(var f in a.CapabilityFamilies ?? []) if(!CompatibilityLayers.Families.Contains(f)) errors.Add($"{a.Rule} has invalid family {f}");
            if (a.Status is null) { errors.Add($"{a.Rule} status object is missing"); continue; }
            foreach(var layer in CompatibilityLayers.All)
            {
                if(!a.Status.TryGetValue(layer,out var s)) errors.Add($"{a.Rule} missing layer {layer}");
                else if(!CompatibilityLayers.Statuses.Contains(s)) errors.Add($"{a.Rule} has invalid status {s} for {layer}");
            }
            foreach(var e in a.Evidence ?? [])
            {
                if (e is null) { errors.Add($"{a.Rule} evidence entry is null"); continue; }
                if(!CompatibilityLayers.All.Contains(e.Layer)) errors.Add($"{a.Rule} evidence has invalid layer");
                if(string.IsNullOrWhiteSpace(e.Kind) || string.IsNullOrWhiteSpace(e.Path)) errors.Add($"{a.Rule} evidence requires kind and path");
                if(!CompatibilityLayers.EvidenceKinds.Contains(e.Kind)) errors.Add($"{a.Rule} evidence has invalid kind {e.Kind}");
                if(Path.IsPathRooted(e.Path) || e.Path.Split(['/', '\\'],StringSplitOptions.RemoveEmptyEntries).Contains("..")) errors.Add($"{a.Rule} evidence path must be repository-relative");
                if((e.Kind.Equals("automated_test",StringComparison.OrdinalIgnoreCase) || e.Kind.Equals("contract_test",StringComparison.OrdinalIgnoreCase) || e.Kind.Equals("forge_test",StringComparison.OrdinalIgnoreCase) || e.Kind.Equals("forgebot_test",StringComparison.OrdinalIgnoreCase)) && string.IsNullOrWhiteSpace(e.Test)) errors.Add($"{a.Rule} test evidence requires test");
            }
        }
        if(errors.Count>0) throw new InvalidDataException($"Invalid compatibility manifest{(source is null ? "" : $" '{source}'")}:\n - "+string.Join("\n - ",errors));
    }
}

public sealed record StatusCounts(int VERIFIED, int PARTIAL, int MISSING, int UNKNOWN, int NOT_APPLICABLE);
public sealed class CompatibilityReport
{
    public CompatibilityManifest Manifest { get; init; } = new();
    public Dictionary<string,StatusCounts> Layers { get; init; } = new();
    public Dictionary<string,StatusCounts> Families { get; init; } = new();
    public List<string> HighestImpactGaps { get; init; } = [];
}
public static class ReportBuilder
{
    static StatusCounts Count(IEnumerable<string> values) => new(values.Count(x=>x=="VERIFIED"),values.Count(x=>x=="PARTIAL"),values.Count(x=>x=="MISSING"),values.Count(x=>x=="UNKNOWN"),values.Count(x=>x=="NOT_APPLICABLE"));
    public static CompatibilityReport Build(CompatibilityManifest m)
    {
        var layers=CompatibilityLayers.All.ToDictionary(l=>l,l=>Count(m.Abilities.Select(a=>a.Status[l])),StringComparer.Ordinal);
        var fam=new Dictionary<string,StatusCounts>(StringComparer.Ordinal); foreach(var f in CompatibilityLayers.Families) fam[f]=Count(m.Abilities.Where(a=>a.CapabilityFamilies.Contains(f)).Select(a=>Overall(a.Status.Values)));
        var gaps=m.Abilities.Where(a=>a.Status.Values.Any(s=>s is "MISSING" or "UNKNOWN" or "PARTIAL"))
            .OrderByDescending(a=>a.Status.Values.Any(s=>s=="MISSING") ? 3 : a.Status.Values.Any(s=>s=="UNKNOWN") ? 2 : 1)
            .ThenBy(a=>int.Parse(a.Rule.Split('.')[1])).Select(a=>$"{a.Rule} {a.Name}").Take(20).ToList();
        return new(){Manifest=m,Layers=layers,Families=fam,HighestImpactGaps=gaps};
    }
    static string Overall(IEnumerable<string> values)
    {
        var v=values.ToArray();
        if(v.Contains("MISSING")) return "MISSING";
        if(v.Contains("UNKNOWN")) return "UNKNOWN";
        if(v.Contains("PARTIAL")) return "PARTIAL";
        return v.All(x=>x=="NOT_APPLICABLE") ? "NOT_APPLICABLE" : "VERIFIED";
    }
}
