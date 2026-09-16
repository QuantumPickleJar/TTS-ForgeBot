namespace MtgTtsBridge.Tests;

public sealed class ForgeHareApparentRulesContractTests
{
    [Fact]
    public void CurrentForgeCardDefinitionUsesOtherHareCountAndRabbitTokenScript()
    {
        var root = FindRepositoryRoot();
        var hare = File.ReadAllText(Path.Combine(root, ".deps", "forge", "forge-gui", "res", "cardsfolder", "h", "hare_apparent.txt"));
        var rabbit = File.ReadAllText(Path.Combine(root, ".deps", "forge", "forge-gui", "res", "tokenscripts", "w_1_1_rabbit.txt"));

        Assert.Contains("SVar:X:Count$Valid Creature.namedHare Apparent+YouCtrl+Other", hare);
        Assert.Contains("TokenScript$ w_1_1_rabbit", hare);
        Assert.Contains("Name:Rabbit Token", rabbit);
        Assert.Contains("Types:Creature Rabbit", rabbit);
        Assert.Contains("PT:1/1", rabbit);
    }

    private static string FindRepositoryRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            if (File.Exists(Path.Combine(directory.FullName, "tools", "forge", "bridge-headless.patch")))
                return directory.FullName;
            directory = directory.Parent;
        }

        throw new DirectoryNotFoundException("Could not locate repository root from test output directory.");
    }
}
