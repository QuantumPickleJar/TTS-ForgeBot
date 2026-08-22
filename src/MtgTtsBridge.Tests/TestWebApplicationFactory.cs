using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using MtgTtsBridge.Forge;

namespace MtgTtsBridge.Tests;

public sealed class TestWebApplicationFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.ConfigureAppConfiguration((_, configurationBuilder) =>
        {
            configurationBuilder.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Bridge:Adapter"] = "Mock"
            });
        });
        builder.ConfigureServices(services =>
        {
            services.RemoveAll<IForgeAdapter>();
            services.AddSingleton<IForgeAdapter, MockForgeAdapter>();
        });
    }
}
