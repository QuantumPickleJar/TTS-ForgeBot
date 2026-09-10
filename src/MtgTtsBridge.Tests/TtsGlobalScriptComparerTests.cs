using MtgTtsBridge.TtsEditor;

namespace MtgTtsBridge.Tests;

public sealed class TtsGlobalScriptComparerTests
{
    [Fact]
    public void CanonicalComparison_TreatsLfAndCrLfAsEqual()
    {
        var expected = "line1\nline2\n";
        var actual = "line1\r\nline2\r\n";

        var comparison = TtsGlobalScriptComparer.CompareCanonicalContent(expected, actual);

        Assert.True(comparison.IsMatch);
        Assert.Equal(comparison.ExpectedCanonicalContentSha256, comparison.ActualCanonicalContentSha256);
        Assert.Equal(-1, comparison.FirstDiffIndex);
    }

    [Fact]
    public void CanonicalComparison_IgnoresTerminalNewlineCount()
    {
        var expected = "print('x')\n\n\n";
        var actual = "print('x')\n";

        var comparison = TtsGlobalScriptComparer.CompareCanonicalContent(expected, actual);

        Assert.True(comparison.IsMatch);
        Assert.Equal(comparison.ExpectedCanonicalLength, comparison.ActualCanonicalLength);
    }

    [Fact]
    public void CanonicalComparison_DetectsSubstantiveMiddleDifference()
    {
        var expected = "abc\ndef\nxyz\n";
        var actual = "abc\ndEf\nxyz\n";

        var comparison = TtsGlobalScriptComparer.CompareCanonicalContent(expected, actual);

        Assert.False(comparison.IsMatch);
        Assert.Equal(5, comparison.FirstDiffIndex);
    }

    [Fact]
    public void ExtractEmbeddedGeneratedSha256_ReturnsExpectedValue()
    {
        var script = "BRIDGE_GENERATED_GLOBAL_LUA_SOURCE_SHA256 = \"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\"\n";

        var sha = TtsGlobalScriptComparer.ExtractEmbeddedGeneratedSha256(script);

        Assert.Equal("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", sha);
    }

    [Fact]
    public void ExtractEmbeddedGeneratedSha256_ReturnsNullWhenMissing()
    {
        Assert.Null(TtsGlobalScriptComparer.ExtractEmbeddedGeneratedSha256("print('no hash')"));
    }
}
