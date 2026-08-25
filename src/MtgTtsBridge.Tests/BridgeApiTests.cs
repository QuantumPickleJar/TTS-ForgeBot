using System.Net;
using System.Net.Http.Json;
using MtgTtsBridge.Contracts.Actions;
using MtgTtsBridge.Contracts.Events;
using MtgTtsBridge.Contracts.State;

namespace MtgTtsBridge.Tests;

public sealed class BridgeApiTests
{
    [Fact]
    public async Task HealthEndpoint_ReturnsAdapterState()
    {
        using var factory = new TestWebApplicationFactory();
        using var client = factory.CreateClient();

        var response = await client.GetAsync("/health");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var health = await response.Content.ReadFromJsonAsync<HealthResponseDto>();
        Assert.NotNull(health);
        Assert.Equal("ok", health.Status);
        Assert.Equal("MockForgeAdapter", health.Adapter);
        Assert.Equal(BridgeProcessIdentity.Revision, health.BridgeRevision);
        Assert.False(string.IsNullOrWhiteSpace(health.BridgeProcessInstanceId));
        Assert.True(health.ProcessId > 0);
        Assert.NotNull(health.ProcessStartUtc);
    }

    [Fact]
    public async Task InitialDecision_IsDeterministic()
    {
        using var factory = new TestWebApplicationFactory();
        using var client = factory.CreateClient();

        await StartSessionAsync(client);
        var decision = await GetDecisionAsync(client);

        Assert.Equal("decision-1-main", decision.DecisionId);
        Assert.Equal("main_priority", decision.Kind);

        var actionIds = decision.Actions.Select(action => action.ActionId).ToArray();

        Assert.Equal(new[] { "pass_priority", "play_mountain", "cast_lightning_strike" }, actionIds);
    }

    [Fact]
    public async Task ValidChoice_AdvancesDecision()
    {
        using var factory = new TestWebApplicationFactory();
        using var client = factory.CreateClient();

        var sessionId = await StartSessionAsync(client);

        var response = await client.PostAsJsonAsync(
            "/api/v1/choice",
            Choice(sessionId, "decision-1-main", "cast_lightning_strike"));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var choice = await response.Content.ReadFromJsonAsync<ChoiceResponseDto>();
        Assert.NotNull(choice);
        Assert.True(choice.Accepted);
        Assert.NotNull(choice.CurrentDecision);
        Assert.Equal("decision-2-target", choice.CurrentDecision.DecisionId);
        var playerTarget = Assert.Single(choice.CurrentDecision.Actions, action => action.TargetKind == "player");
        Assert.Equal("forge-player-2", playerTarget.TargetSeatId);
    }

    [Fact]
    public async Task StaleDecisionId_IsRejected()
    {
        using var factory = new TestWebApplicationFactory();
        using var client = factory.CreateClient();

        var sessionId = await StartSessionAsync(client);

        var initialChoice = await client.PostAsJsonAsync(
            "/api/v1/choice",
            Choice(sessionId, "decision-1-main", "cast_lightning_strike"));

        Assert.Equal(HttpStatusCode.OK, initialChoice.StatusCode);

        var staleChoice = await client.PostAsJsonAsync(
            "/api/v1/choice",
            Choice(sessionId, "decision-1-main", "play_mountain"));

        Assert.Equal(HttpStatusCode.Conflict, staleChoice.StatusCode);

        var error = await staleChoice.Content.ReadFromJsonAsync<ErrorResponseDto>();
        Assert.NotNull(error);
        Assert.Equal("stale_decision_id", error.ErrorCode);
    }

    [Fact]
    public async Task UnknownActionId_IsRejected()
    {
        using var factory = new TestWebApplicationFactory();
        using var client = factory.CreateClient();

        var sessionId = await StartSessionAsync(client);

        var response = await client.PostAsJsonAsync(
            "/api/v1/choice",
            Choice(sessionId, "decision-1-main", "not_a_real_action"));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);

        var error = await response.Content.ReadFromJsonAsync<ErrorResponseDto>();
        Assert.NotNull(error);
        Assert.Equal("unknown_action_id", error.ErrorCode);
    }

    [Fact]
    public async Task TargetFollowupDecision_Works()
    {
        using var factory = new TestWebApplicationFactory();
        using var client = factory.CreateClient();

        var sessionId = await StartSessionAsync(client);

        var toTargetDecision = await client.PostAsJsonAsync(
            "/api/v1/choice",
            Choice(sessionId, "decision-1-main", "cast_lightning_strike"));

        Assert.Equal(HttpStatusCode.OK, toTargetDecision.StatusCode);

        var targetResponse = await client.PostAsJsonAsync(
            "/api/v1/choice",
            Choice(sessionId, "decision-2-target", "target_opponent"));

        Assert.Equal(HttpStatusCode.OK, targetResponse.StatusCode);

        var choice = await targetResponse.Content.ReadFromJsonAsync<ChoiceResponseDto>();
        Assert.NotNull(choice);
        Assert.True(choice.Accepted);
        Assert.Null(choice.CurrentDecision);
        Assert.NotNull(choice.CommittedEvent);
        Assert.Equal("cast_lightning_strike", choice.CommittedEvent.SourceActionId);
        Assert.Equal("player:opponent", choice.CommittedEvent.TargetIdentity);

        var decisionAfterCommit = await client.GetAsync("/api/v1/decision");
        Assert.Equal(HttpStatusCode.NotFound, decisionAfterCommit.StatusCode);
    }

    [Fact]
    public async Task Reset_ReturnsKnownState()
    {
        using var factory = new TestWebApplicationFactory();
        using var client = factory.CreateClient();

        var sessionId = await StartSessionAsync(client);

        var playMountain = await client.PostAsJsonAsync(
            "/api/v1/choice",
            Choice(sessionId, "decision-1-main", "play_mountain"));

        Assert.Equal(HttpStatusCode.OK, playMountain.StatusCode);

        var resetResponse = await client.PostAsync("/api/v1/session/reset", content: null);
        Assert.Equal(HttpStatusCode.OK, resetResponse.StatusCode);

        var resetStart = await resetResponse.Content.ReadFromJsonAsync<SessionStartResponseDto>();
        Assert.NotNull(resetStart);
        Assert.NotNull(resetStart.CurrentDecision);
        Assert.Equal("decision-1-main", resetStart.CurrentDecision.DecisionId);

        var decision = await GetDecisionAsync(client);
        Assert.Equal("decision-1-main", decision.DecisionId);
        Assert.Equal(3, decision.Actions.Count);
    }

    [Fact]
    public async Task Start_AttachesButResetExplicitlyReplacesActiveSession()
    {
        using var factory = new TestWebApplicationFactory();
        using var client = factory.CreateClient();

        var firstResponse = await client.PostAsync("/api/v1/session/start", content: null);
        var first = await firstResponse.Content.ReadFromJsonAsync<SessionStartResponseDto>();
        Assert.NotNull(first);

        var attachedResponse = await client.PostAsync("/api/v1/session/start", content: null);
        var attached = await attachedResponse.Content.ReadFromJsonAsync<SessionStartResponseDto>();
        Assert.NotNull(attached);
        Assert.Equal(first.SessionId, attached.SessionId);

        var healthResponse = await client.GetAsync("/health");
        var health = await healthResponse.Content.ReadFromJsonAsync<HealthResponseDto>();
        Assert.NotNull(health);
        Assert.Equal(first.SessionId, health.SessionId);

        var resetResponse = await client.PostAsync("/api/v1/session/reset", content: null);
        var reset = await resetResponse.Content.ReadFromJsonAsync<SessionStartResponseDto>();
        Assert.NotNull(reset);
        Assert.NotEqual(first.SessionId, reset.SessionId);
        Assert.Equal("decision-1-main", reset.CurrentDecision?.DecisionId);
    }

    [Fact]
    public async Task EventsEndpoint_UsesIncrementalSequenceContract()
    {
        using var factory = new TestWebApplicationFactory();
        using var client = factory.CreateClient();

        var response = await client.GetAsync("/api/v1/events?after=0");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var batch = await response.Content.ReadFromJsonAsync<EventBatchDto>();
        Assert.NotNull(batch);
        Assert.Equal(0, batch.RequestedAfterSequence);
        Assert.Empty(batch.Events);
        Assert.False(batch.HasGap);
    }

    [Fact]
    public async Task SnapshotEndpoint_IsSeparateAndUnavailableForMockAdapter()
    {
        using var factory = new TestWebApplicationFactory();
        using var client = factory.CreateClient();

        var response = await client.GetAsync("/api/v1/embodiment/snapshot");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        var error = await response.Content.ReadFromJsonAsync<ErrorResponseDto>();
        Assert.Equal("snapshot_unavailable", error?.ErrorCode);
    }

    private static async Task<string> StartSessionAsync(HttpClient client)
    {
        var response = await client.PostAsync("/api/v1/session/start", content: null);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<SessionStartResponseDto>();
        return Assert.IsType<string>(body?.SessionId);
    }

    [Fact]
    public async Task ChoiceWireShapeFromTts_BindsEveryProtocolIdentityField()
    {
        using var factory = new TestWebApplicationFactory();
        using var client = factory.CreateClient();
        var sessionId = await StartSessionAsync(client);
        var json = $$"""{"sessionId":"{{sessionId}}","decisionId":"decision-1-main","actionId":"play_mountain","requestId":"runtime-1-choice-1","clientRuntimeId":"runtime-1","clientRevision":"2026-08-25-f2b-v2","source":"pass_button"}""";

        var response = await client.PostAsync("/api/v1/choice", new StringContent(json, System.Text.Encoding.UTF8, "application/json"));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task LegacyChoiceWireShape_ReturnsExactMissingFields()
    {
        using var factory = new TestWebApplicationFactory();
        using var client = factory.CreateClient();

        var response = await client.PostAsync("/api/v1/choice", new StringContent("{\"decisionId\":\"forge-tui-1\",\"actionId\":\"forge-tui-1-choice-0\"}", System.Text.Encoding.UTF8, "application/json"));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var error = await response.Content.ReadFromJsonAsync<ErrorResponseDto>();
        Assert.NotNull(error);
        Assert.Equal("invalid_request", error.ErrorCode);
        Assert.Equal(new[] { "sessionId", "requestId", "clientRuntimeId", "clientRevision", "source" }, error.MissingFields);
        Assert.Equal("Missing required fields: sessionId, requestId, clientRuntimeId, clientRevision, source.", error.Message);
    }

    [Fact]
    public async Task PreviousSessionChoice_IsRejectedAsStaleSessionWithoutAdvancingTheNewSession()
    {
        using var factory = new TestWebApplicationFactory();
        using var client = factory.CreateClient();

        var oldSessionId = await StartSessionAsync(client);
        var reset = await client.PostAsync("/api/v1/session/reset", content: null);
        var replacement = await reset.Content.ReadFromJsonAsync<SessionStartResponseDto>();
        Assert.NotNull(replacement);
        Assert.NotEqual(oldSessionId, replacement.SessionId);

        var stale = await client.PostAsJsonAsync("/api/v1/choice", Choice(oldSessionId, "decision-1-main", "pass_priority"));

        Assert.Equal(HttpStatusCode.Conflict, stale.StatusCode);
        var error = await stale.Content.ReadFromJsonAsync<ErrorResponseDto>();
        Assert.Equal("stale_session", error?.ErrorCode);
        Assert.Equal(replacement.SessionId, error?.ExpectedSessionId);
        Assert.Equal(oldSessionId, error?.ReceivedSessionId);

        var decision = await GetDecisionAsync(client);
        Assert.Equal("decision-1-main", decision.DecisionId);
        Assert.Equal(replacement.SessionId, decision.SessionId);
    }

    private static ChoiceRequestDto Choice(string sessionId, string decisionId, string actionId) =>
        new(decisionId, actionId)
        {
            SessionId = sessionId,
            RequestId = $"test-{Guid.NewGuid():N}",
            ClientRuntimeId = "test-runtime",
            ClientRevision = "test-revision",
            Source = "test"
        };

    private static async Task<DecisionDto> GetDecisionAsync(HttpClient client)
    {
        var response = await client.GetAsync("/api/v1/decision");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var decision = await response.Content.ReadFromJsonAsync<DecisionDto>();
        Assert.NotNull(decision);

        return decision;
    }
}

