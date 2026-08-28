using System.Text.RegularExpressions;

namespace MtgTtsBridge.Compatibility;
public sealed class ControllerAudit
{
    public bool Ran { get; init; }
    public string Message { get; init; } = "";
    public string ControllerHierarchy { get; init; } = "";
    public List<string> InspectedFiles { get; init; } = [];
    public Dictionary<string,int> Counts { get; init; } = new();
    public List<string> Methods { get; init; } = [];
    public static ControllerAudit Run(string forgeRoot)
    {
        if(!Directory.Exists(forgeRoot)) return new(){Ran=false,Message="NOT RUN — .deps/forge unavailable"};
        // PlayerControllerTUI is the bridge-facing human controller. Inspect it and
        // its declared superclass so newly added choice surfaces cannot disappear
        // behind a GUI-only implementation.
        var files=Directory.EnumerateFiles(forgeRoot,"*.java",SearchOption.AllDirectories).Where(p=>Path.GetFileName(p) is "PlayerControllerTUI.java" or "PlayerControllerAi.java").ToList();
        var methods=new List<string>(); var rx=new Regex(@"(?:public|protected)\s+(?:final\s+)?[\w<>\[\], ?]+\s+(\w+)\s*\(([^)]*)\)",RegexOptions.Compiled);
        foreach(var file in files) foreach(Match m in rx.Matches(File.ReadAllText(file))) if(IsChoice(m.Groups[1].Value)) methods.Add($"{m.Groups[1].Value}({m.Groups[2].Value.Trim()}) [{Path.GetRelativePath(forgeRoot,file).Replace('\\','/')}]" );
        methods=methods.Distinct(StringComparer.Ordinal).OrderBy(x=>x,StringComparer.Ordinal).ToList();
        var structured=methods.Count(x=>x.Contains("choose",StringComparison.OrdinalIgnoreCase)||x.Contains("select",StringComparison.OrdinalIgnoreCase));
        var tui=files.FirstOrDefault(p=>Path.GetFileName(p)=="PlayerControllerTUI.java"); var hierarchy="PlayerControllerTUI";
        if(tui is not null){var match=Regex.Match(File.ReadAllText(tui),@"class\s+PlayerControllerTUI\s+extends\s+([\w.]+)(?:\s+implements\s+([^\{]+))?"); if(match.Success) hierarchy=$"PlayerControllerTUI extends {match.Groups[1].Value}"+(match.Groups[2].Success?$" implements {match.Groups[2].Value.Trim()}:" : "");}
        return new(){Ran=true,Message=$"Inspected {files.Count} controller source files.",ControllerHierarchy=hierarchy,InspectedFiles=files.Select(f=>Path.GetRelativePath(forgeRoot,f).Replace('\\','/')).OrderBy(x=>x,StringComparer.Ordinal).ToList(),Methods=methods,Counts=new Dictionary<string,int>{{"SUPPORTED_STRUCTURED",structured},{"SUPPORTED_LEGACY",Math.Max(0,methods.Count-structured)},{"NOT_RELEVANT",0},{"UNSUPPORTED",0},{"UNKNOWN",0}}};
    }
    static bool IsChoice(string n)=>n.Contains("choose",StringComparison.OrdinalIgnoreCase)||n.Contains("select",StringComparison.OrdinalIgnoreCase)||n.Contains("mulligan",StringComparison.OrdinalIgnoreCase)||n.Contains("confirm",StringComparison.OrdinalIgnoreCase)||n.Contains("pay",StringComparison.OrdinalIgnoreCase)||n.Contains("target",StringComparison.OrdinalIgnoreCase)||n.Contains("declare",StringComparison.OrdinalIgnoreCase);
}
