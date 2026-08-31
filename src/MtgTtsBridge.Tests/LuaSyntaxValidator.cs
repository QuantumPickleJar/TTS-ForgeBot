using MoonSharp.Interpreter;

namespace MtgTtsBridge.Tests;

internal static class LuaSyntaxValidator
{
    public static void CompileFile(string path)
    {
        Compile(File.ReadAllText(path), path);
    }

    public static void Compile(string source, string sourceName = "Global.lua")
    {
        // LoadString compiles the chunk and returns its function without invoking it.
        // CoreModules.None keeps this a parser/compiler-only check.
        var script = new Script(CoreModules.None);
        script.LoadString(source, null, sourceName);
    }
}
