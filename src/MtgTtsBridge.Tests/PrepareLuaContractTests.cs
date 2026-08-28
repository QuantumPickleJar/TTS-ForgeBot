namespace MtgTtsBridge.Tests;

public sealed class PrepareLuaContractTests
{
    private static readonly string Script = File.ReadAllText(
        Path.Combine(AppContext.BaseDirectory, "Fixtures", "Global.lua"));

    [Fact]
    public void PreparedSpell_UsesVirtualActionAndNeverMovesTheSourcePermanent()
    {
        Assert.Contains("preparedSourceCardInstanceId", Script);
        Assert.Contains("physical_prepared_spell", Script);
        Assert.Contains("moved as though it were the spell being cast", Script);
        Assert.Contains("cardDesignationsByInstanceId", Script);
    }
}
