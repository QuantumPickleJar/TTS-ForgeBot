using MoonSharp.Interpreter;

namespace MtgTtsBridge.Tests;

public sealed class TtsGlobalLuaSyntaxTests
{
    private static readonly string GlobalLuaPath = Path.Combine(
        AppContext.BaseDirectory, "Fixtures", "Global.lua");

    [Fact]
    public void GlobalLua_CompilesAsOneCompleteTtsLuaChunk()
    {
        LuaSyntaxValidator.CompileFile(GlobalLuaPath);
    }

    [Theory]
    [InlineData("function broken()\n  return (1\nend", "unbalanced parenthesis")]
    [InlineData("function broken()\n  return true", "missing function end")]
    [InlineData("local broken = { key = }", "malformed table")]
    [InlineData("function broken(\n", "malformed function")]
    public void MalformedLua_IsRejectedByTheSameCompiler(string source, string description)
    {
        var error = Assert.Throws<SyntaxErrorException>(
            () => LuaSyntaxValidator.Compile(source, description));

        Assert.Contains(description, error.DecoratedMessage, StringComparison.OrdinalIgnoreCase);
    }
}
