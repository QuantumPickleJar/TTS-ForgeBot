using System.IO.Compression;
using System.Text;
using System.Text.Json;

namespace MtgTtsBridge.Diagnostics;

public sealed class DiagnosticBundleWriter
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public void WriteJson(string root, string relativePath, object value) =>
        WriteText(root, relativePath, JsonSerializer.Serialize(value, JsonOptions));

    public void WriteJsonLines<T>(string root, string relativePath, IEnumerable<T> values)
    {
        var builder = new StringBuilder();
        foreach (var value in values) builder.AppendLine(JsonSerializer.Serialize(value, JsonOptions));
        WriteText(root, relativePath, builder.ToString());
    }

    public void WriteText(string root, string relativePath, string content)
    {
        var fullPath = Path.GetFullPath(Path.Combine(root, relativePath));
        var fullRoot = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        if (!fullPath.StartsWith(fullRoot, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Diagnostic bundle path escaped its staging directory.");
        Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
        File.WriteAllText(fullPath, content, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
    }

    public void CreateZip(string sourceDirectory, string destinationZip)
    {
        var destination = Path.GetFullPath(destinationZip);
        Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
        if (File.Exists(destination)) File.Delete(destination);
        ZipFile.CreateFromDirectory(sourceDirectory, destination, CompressionLevel.Fastest, includeBaseDirectory: false);
    }
}
