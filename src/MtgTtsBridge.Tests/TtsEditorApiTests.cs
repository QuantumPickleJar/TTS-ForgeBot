using System.Net;
using System.Net.Http.Json;
using MtgTtsBridge.Contracts.State;

namespace MtgTtsBridge.Tests;

public sealed class TtsEditorApiTests
{
    [Fact]
    public async Task StatusEndpoint_ReportsDisabledServiceInTestingEnvironment()
    {
        using var factory = new TestWebApplicationFactory();
        using var client = factory.CreateClient();

        var response = await client.GetAsync("/api/v1/tts-editor/status");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<TtsEditorStatusResponseDto>();
        Assert.NotNull(body);
        Assert.False(body.Enabled);
        Assert.False(body.ListenerActive);
    }

    [Fact]
    public async Task RefreshEndpoint_ReturnsStructuredUnavailableErrorInTestingEnvironment()
    {
        using var factory = new TestWebApplicationFactory();
        using var client = factory.CreateClient();

        var response = await client.PostAsync("/api/v1/tts-editor/refresh", null);

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<TtsEditorErrorResponseDto>();
        Assert.NotNull(body);
        Assert.Equal("listener_unavailable", body.ErrorCode);
    }

    [Fact]
    public async Task PushGlobalEndpoint_ReturnsStructuredUnavailableErrorInTestingEnvironment()
    {
        using var factory = new TestWebApplicationFactory();
        using var client = factory.CreateClient();

        var request = new TtsEditorPushGlobalRequestDto("print('x')", new string('a', 64));
        var response = await client.PostAsJsonAsync("/api/v1/tts-editor/push-global", request);

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<TtsEditorErrorResponseDto>();
        Assert.NotNull(body);
        Assert.Equal("listener_unavailable", body.ErrorCode);
    }
}
