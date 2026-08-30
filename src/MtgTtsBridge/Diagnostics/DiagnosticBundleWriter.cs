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

    public static readonly JsonSerializerOptions CompactJsonOptions = new()
    {
        WriteIndented = false,
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

    /// <summary>Writes entries directly into a same-directory temporary ZIP.</summary>
    public void WriteZipAtomically(string destinationZip, Action<ZipArchive> writeEntries)
    {
        var destination = Path.GetFullPath(destinationZip);
        var directory = Path.GetDirectoryName(destination)!;
        Directory.CreateDirectory(directory);
        var temporary = destination + ".tmp-" + Guid.NewGuid().ToString("N");
        try
        {
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            using (var archive = new ZipArchive(file, ZipArchiveMode.Create, leaveOpen: false))
            {
                writeEntries(archive);
            }

            File.Move(temporary, destination, overwrite: true);
        }
        catch
        {
            try { if (File.Exists(temporary)) File.Delete(temporary); } catch { }
            throw;
        }
    }

    public static ZipArchiveEntry CreateSafeEntry(ZipArchive archive, string relativePath)
    {
        var normalized = relativePath.Replace('\\', '/');
        if (string.IsNullOrWhiteSpace(normalized) || normalized.StartsWith('/') || Path.IsPathRooted(normalized)
            || normalized.Split('/').Any(part => part is "" or "." or ".."))
            throw new InvalidOperationException("Diagnostic ZIP entry path is invalid.");
        return archive.CreateEntry(normalized, CompressionLevel.Fastest);
    }

    public static void WriteJsonEntry(ZipArchive archive, string path, object? value)
    {
        using var stream = CreateSafeEntry(archive, path).Open();
        JsonSerializer.Serialize(stream, value, CompactJsonOptions);
    }

    public static void WriteTextEntry(ZipArchive archive, string path, string content)
    {
        using var stream = CreateSafeEntry(archive, path).Open();
        using var writer = new StreamWriter(stream, new UTF8Encoding(false), leaveOpen: false);
        writer.Write(content);
    }
}
