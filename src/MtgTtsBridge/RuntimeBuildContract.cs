using System.Reflection;
using System.Text.RegularExpressions;

namespace MtgTtsBridge;

/// <summary>Immutable compatibility contract compiled into this Bridge build.</summary>
public static partial class RuntimeBuildContract
{
    private const string ResourceName = "MtgTtsBridge.GeneratedGlobalLua";

    public static string ExpectedGeneratedGlobalLuaSha256 { get; } = ReadExpectedLuaHash();
    public static string BuildIdentity { get; } =
        $"{typeof(RuntimeBuildContract).Assembly.ManifestModule.ModuleVersionId:N}:{ExpectedGeneratedGlobalLuaSha256}";

    public static bool IsCompatible(string? generatedGlobalLuaSha256) =>
        !string.IsNullOrWhiteSpace(generatedGlobalLuaSha256)
        && string.Equals(ExpectedGeneratedGlobalLuaSha256, generatedGlobalLuaSha256.Trim(), StringComparison.OrdinalIgnoreCase);

    private static string ReadExpectedLuaHash()
    {
        using var stream = typeof(RuntimeBuildContract).Assembly.GetManifestResourceStream(ResourceName)
            ?? throw new InvalidOperationException("The generated TTS Global.lua build artifact was not embedded.");
        using var reader = new StreamReader(stream);
        var header = reader.ReadLine() ?? string.Empty;
        var match = GeneratedLuaHash().Match(header);
        if (!match.Success) throw new InvalidOperationException("The embedded TTS Global.lua artifact has no generated SHA-256 header.");
        return match.Groups[1].Value.ToLowerInvariant();
    }

    [GeneratedRegex("^-- GENERATED GLOBAL\\.LUA SOURCE SHA256: ([0-9a-fA-F]{64})$")]
    private static partial Regex GeneratedLuaHash();
}
