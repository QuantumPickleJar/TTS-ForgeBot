using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using MtgTtsBridge.Forge;

namespace MtgTtsBridge.Tests;

public sealed class TestWebApplicationFactory : WebApplicationFactory<Program>
{
    private readonly string _reportDirectory;

    public TestWebApplicationFactory(string? reportDirectory = null)
    {
        _reportDirectory = reportDirectory ?? Path.Combine(Path.GetTempPath(), $"MtgTtsBridge-tests-{Guid.NewGuid():N}");
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.ConfigureAppConfiguration((_, configurationBuilder) =>
        {
            configurationBuilder.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Bridge:Adapter"] = "Mock",
                ["Diagnostics:ReportDirectory"] = _reportDirectory
            });
        });
        builder.ConfigureServices(services =>
        {
            services.RemoveAll<IForgeAdapter>();
            services.AddSingleton<IForgeAdapter, MockForgeAdapter>();
        });
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        if (disposing)
        {
            try { if (Directory.Exists(_reportDirectory)) Directory.Delete(_reportDirectory, recursive: true); } catch { }
        }
    }
}
