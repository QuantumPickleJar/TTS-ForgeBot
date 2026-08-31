using System.Text;

var root = FindRepositoryRoot();
var sourceDirectory = Path.Combine(root, "tts", "src");
var outputPath = Path.Combine(root, "tts", "Global.lua");
var parts = Directory.GetFiles(sourceDirectory, "*.lua")
    .OrderBy(Path.GetFileName, StringComparer.Ordinal)
    .ToArray();
if (parts.Length == 0) throw new InvalidOperationException($"No Lua authoring sources found in {sourceDirectory}");

var builder = new StringBuilder();
foreach (var part in parts)
{
    builder.Append("-- BEGIN GENERATED SOURCE: ")
        .Append(Path.GetFileName(part))
        .AppendLine();
    builder.Append(File.ReadAllText(part));
    if (builder.Length == 0 || builder[^1] != '\n') builder.AppendLine();
    builder.Append("-- END GENERATED SOURCE: ")
        .Append(Path.GetFileName(part))
        .AppendLine();
}

var generated = builder.ToString();
if (args.Contains("--check", StringComparer.Ordinal))
{
    var current = File.Exists(outputPath) ? File.ReadAllText(outputPath) : string.Empty;
    if (!string.Equals(current, generated, StringComparison.Ordinal))
    {
        Console.Error.WriteLine($"Generated Lua is stale: {Path.GetRelativePath(root, outputPath)}");
        return 1;
    }
    Console.WriteLine("TTS Global.lua bundle: PASS");
    return 0;
}

File.WriteAllText(outputPath, generated, new UTF8Encoding(false));
Console.WriteLine($"Wrote {Path.GetRelativePath(root, outputPath)} from {parts.Length} Lua sources.");
return 0;

static string FindRepositoryRoot()
{
    var directory = new DirectoryInfo(Environment.CurrentDirectory);
    while (directory is not null && !File.Exists(Path.Combine(directory.FullName, "AGENTS.md")))
        directory = directory.Parent;
    return directory?.FullName ?? throw new DirectoryNotFoundException("Could not locate repository root.");
}
