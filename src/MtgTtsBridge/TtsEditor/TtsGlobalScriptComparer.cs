using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace MtgTtsBridge.TtsEditor;

public sealed record TtsCanonicalComparisonResult(
    bool IsMatch,
    string ExpectedCanonicalContentSha256,
    string ActualCanonicalContentSha256,
    int ExpectedCanonicalLength,
    int ActualCanonicalLength,
    int FirstDiffIndex);

public static partial class TtsGlobalScriptComparer
{
    public static string NormalizeLineEndings(string? text)
    {
        if (string.IsNullOrEmpty(text)) return string.Empty;
        return text.Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n');
    }

    public static string CanonicalizeForTransportComparison(string? text)
    {
        var normalized = NormalizeLineEndings(text);
        return normalized.TrimEnd('\n');
    }

    public static string CanonicalSha256(string? text)
    {
        var canonical = CanonicalizeForTransportComparison(text);
        var bytes = Encoding.UTF8.GetBytes(canonical);
        return Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
    }

    public static string? ExtractEmbeddedGeneratedSha256(string? script)
    {
        if (string.IsNullOrWhiteSpace(script)) return null;
        var match = GeneratedLuaHashRegex().Match(script);
        return match.Success ? match.Groups[1].Value.ToLowerInvariant() : null;
    }

    public static TtsCanonicalComparisonResult CompareCanonicalContent(string? expected, string? actual)
    {
        var expectedCanonical = CanonicalizeForTransportComparison(expected);
        var actualCanonical = CanonicalizeForTransportComparison(actual);
        var firstDiffIndex = FirstDifferenceIndex(expectedCanonical, actualCanonical);
        return new TtsCanonicalComparisonResult(
            firstDiffIndex < 0,
            CanonicalSha256(expectedCanonical),
            CanonicalSha256(actualCanonical),
            expectedCanonical.Length,
            actualCanonical.Length,
            firstDiffIndex);
    }

    public static int FirstDifferenceIndex(string? expected, string? actual)
    {
        var expectedText = expected ?? string.Empty;
        var actualText = actual ?? string.Empty;
        var minLength = Math.Min(expectedText.Length, actualText.Length);
        for (var index = 0; index < minLength; index++)
        {
            if (expectedText[index] != actualText[index]) return index;
        }

        return expectedText.Length == actualText.Length ? -1 : minLength;
    }

    [GeneratedRegex("BRIDGE_GENERATED_GLOBAL_LUA_SOURCE_SHA256\\s*=\\s*\"([0-9a-fA-F]{64})\"")]
    private static partial Regex GeneratedLuaHashRegex();
}
