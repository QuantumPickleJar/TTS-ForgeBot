using System.Text.Json;
using MtgTtsBridge.Compatibility;

var argsList=args.ToList();
if(argsList.Contains("--help")){ Console.WriteLine("MTG ForgeBot §702 compatibility report\nUsage: dotnet run --project tools/MtgTtsBridge.Compatibility -- [--json] [--manifest <path>] [--compare <manifest>]\n  --json       emit deterministic machine-readable totals\n  --compare    compare statuses with another manifest\n  --help       show this help"); return; }
var root=FindRoot(); var manifestPath=GetValue("--manifest") ?? Path.Combine(root,"tools","compatibility","keyword-abilities.json");
var manifest=ManifestLoader.Load(manifestPath); var report=ReportBuilder.Build(manifest); var audit=ControllerAudit.Run(Path.Combine(root,".deps","forge"));
var compare=GetValue("--compare");
if(argsList.Contains("--json"))
{
    var payload=new { baseline=new { manifest.RulesBaseline, manifest.EffectiveDate, first=manifest.Range.First,last=manifest.Range.Last, abilities=manifest.Abilities.Count }, layers=report.Layers, families=report.Families, highestImpactGaps=report.HighestImpactGaps, humanControllerAudit=new { audit.Ran,audit.Message,audit.ControllerHierarchy,audit.InspectedFiles,audit.Counts,audit.Methods }, buildIdentity=new { forgeBotHead=GitHead(root), forgeStamp=LoadBuildStamp(root) }, comparison=compare is null?null:Compare(manifest,ManifestLoader.Load(Path.GetFullPath(compare))) };
    Console.WriteLine(JsonSerializer.Serialize(payload,new JsonSerializerOptions{WriteIndented=true}));
}
else
{
    Console.WriteLine("MTG FORGEBOT §702 COMPATIBILITY"); Console.WriteLine($"Baseline\n  {manifest.RulesBaseline}\n  {manifest.EffectiveDate}\n  {manifest.Range.First} -> {manifest.Range.Last}\n  {manifest.Abilities.Count} abilities");
    foreach(var layer in CompatibilityLayers.All){var c=report.Layers[layer]; Console.WriteLine($"\n{layer}\n  VERIFIED {c.VERIFIED}  PARTIAL {c.PARTIAL}  MISSING {c.MISSING}  UNKNOWN {c.UNKNOWN}  NOT_APPLICABLE {c.NOT_APPLICABLE}");}
    Console.WriteLine("\nBy capability family:"); foreach(var kv in report.Families){var c=kv.Value; Console.WriteLine($"  {kv.Key}: VERIFIED {c.VERIFIED}, PARTIAL {c.PARTIAL}, MISSING {c.MISSING}, UNKNOWN {c.UNKNOWN}, NOT_APPLICABLE {c.NOT_APPLICABLE}");}
    Console.WriteLine("\nHighest-impact gaps:"); foreach(var g in report.HighestImpactGaps) Console.WriteLine($"  {g}");
    Console.WriteLine($"\nForge human-controller source audit: {audit.Message}"); if(audit.Ran){Console.WriteLine($"  hierarchy: {audit.ControllerHierarchy}"); foreach(var c in audit.Counts) Console.WriteLine($"  {c.Key}: {c.Value}"); foreach(var m in audit.Methods) Console.WriteLine($"  {m}");}
    var stamp=LoadBuildStamp(root); if(stamp is not null || GitHead(root) is not null) Console.WriteLine($"\nBuild identity: ForgeBot HEAD {GitHead(root) ?? "unknown"}; Forge stamp {JsonSerializer.Serialize(stamp)}");
    if(compare is not null) PrintCompare(Compare(manifest,ManifestLoader.Load(Path.GetFullPath(compare))));
}

string? GetValue(string key){var i=argsList.IndexOf(key); return i>=0&&i+1<argsList.Count?argsList[i+1]:null;}
string FindRoot(){var d=Directory.GetCurrentDirectory(); while(!File.Exists(Path.Combine(d,"tools","compatibility","keyword-abilities.json")) && Directory.GetParent(d) is not null)d=Directory.GetParent(d)!.FullName; return d;}
object? LoadBuildStamp(string root){var candidates=Directory.EnumerateFiles(root,"forge-headless-bridge-build.json",SearchOption.AllDirectories).ToList(); var p=candidates.FirstOrDefault(x=>x.Replace('\\','/').Contains("/.deps/forge/forge-headless/",StringComparison.OrdinalIgnoreCase)) ?? candidates.OrderBy(x=>x,StringComparer.OrdinalIgnoreCase).FirstOrDefault(); if(p is null)return null; try{return JsonSerializer.Deserialize<JsonElement>(File.ReadAllText(p));}catch{return null;}}
string? GitHead(string root){try{var psi=new System.Diagnostics.ProcessStartInfo("git","rev-parse HEAD"){WorkingDirectory=root,RedirectStandardOutput=true,UseShellExecute=false,CreateNoWindow=true}; using var p=System.Diagnostics.Process.Start(psi); var value=p?.StandardOutput.ReadToEnd().Trim(); p?.WaitForExit(2000); return string.IsNullOrWhiteSpace(value)?null:value;}catch{return null;}}
Dictionary<string,List<string>> Compare(CompatibilityManifest a,CompatibilityManifest b){var result=new Dictionary<string,List<string>>{{"newlyVerified",[]},{"regressed",[]}}; foreach(var x in a.Abilities){var y=b.Abilities.FirstOrDefault(z=>z.Rule==x.Rule); if(y is null)continue; foreach(var l in CompatibilityLayers.All){var old=y.Status[l];var now=x.Status[l];if(now=="VERIFIED"&&old!="VERIFIED")result["newlyVerified"].Add($"{x.Name}.{l} {old} -> VERIFIED"); if(now is "MISSING" or "UNKNOWN"&&old=="VERIFIED")result["regressed"].Add($"{x.Name}.{l} VERIFIED -> {now}");}} return result;}
void PrintCompare(Dictionary<string,List<string>> c){Console.WriteLine("\nComparison:"); foreach(var x in c){Console.WriteLine($"  {x.Key}"); foreach(var v in x.Value)Console.WriteLine($"    {v}");}}
