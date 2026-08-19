using MtgTtsBridge.Contracts.Actions;
using MtgTtsBridge.Contracts.State;
using MtgTtsBridge.Forge;

var builder = WebApplication.CreateBuilder(args);

var listenUrl = builder.Configuration["Bridge:ListenUrl"] ?? "http://127.0.0.1:43110";
builder.WebHost.UseUrls(listenUrl);

var adapterName = builder.Configuration["Bridge:Adapter"] ?? "Mock";

if (string.Equals(adapterName, "ForgeTui", StringComparison.OrdinalIgnoreCase))
{
	builder.Services.Configure<ForgeTuiOptions>(builder.Configuration.GetSection("Forge"));
	builder.Services.AddSingleton<IForgeAdapter, ForgeTuiAdapter>();
}
else
{
	builder.Services.AddSingleton<IForgeAdapter, MockForgeAdapter>();
}

var app = builder.Build();

app.MapGet("/health", async (IForgeAdapter adapter, CancellationToken cancellationToken) =>
{
	var state = await adapter.GetStateAsync(cancellationToken);

	return Results.Ok(new HealthResponseDto(
		Status: "ok",
		Adapter: adapter.Name,
		AdapterState: state.State,
		SessionId: state.SessionId,
		HasActiveDecision: state.CurrentDecision is not null,
		CurrentDecisionId: state.CurrentDecision?.DecisionId,
		LastCommittedEvent: state.LastCommittedEvent,
		Diagnostic: state.Diagnostic));
});

app.MapPost("/api/v1/session/start", async (IForgeAdapter adapter, CancellationToken cancellationToken) =>
{
	var state = await adapter.StartSessionAsync(cancellationToken);

	if (state.CurrentDecision is null)
	{
		return Results.Problem("The adapter did not provide an initial decision.", statusCode: StatusCodes.Status500InternalServerError);
	}

	return Results.Ok(new SessionStartResponseDto(
		SessionId: state.SessionId,
		CurrentDecision: state.CurrentDecision));
});

app.MapGet("/api/v1/decision", async (IForgeAdapter adapter, CancellationToken cancellationToken) =>
{
	var state = await adapter.GetStateAsync(cancellationToken);

	if (state.CurrentDecision is null)
	{
		return Results.NotFound(new ErrorResponseDto(
			ErrorCode: "no_pending_decision",
			Message: "No active decision is available.",
			DecisionId: null));
	}

	return Results.Ok(state.CurrentDecision);
});

app.MapGet("/api/v1/events", async (long? after, IForgeAdapter adapter, CancellationToken cancellationToken) =>
{
	var afterSequence = after ?? 0;
	if (afterSequence < 0)
	{
		return Results.BadRequest(new ErrorResponseDto(
			ErrorCode: "invalid_event_sequence",
			Message: "The after sequence must be zero or greater.",
			DecisionId: null));
	}

	var batch = await adapter.GetEventsAsync(afterSequence, cancellationToken);
	if (batch.HasGap)
	{
		return Results.Conflict(new ErrorResponseDto(
			ErrorCode: "event_history_gap",
			Message: $"Events after sequence {afterSequence} are no longer available; oldest available is {batch.OldestAvailableSequence}.",
			DecisionId: null));
	}

	return Results.Ok(batch);
});

app.MapPost("/api/v1/choice", async (ChoiceRequestDto request, IForgeAdapter adapter, CancellationToken cancellationToken) =>
{
	if (string.IsNullOrWhiteSpace(request.DecisionId) || string.IsNullOrWhiteSpace(request.ActionId))
	{
		return Results.BadRequest(new ErrorResponseDto(
			ErrorCode: "invalid_request",
			Message: "Both decisionId and actionId are required.",
			DecisionId: request.DecisionId));
	}

	var outcome = await adapter.SubmitChoiceAsync(request, cancellationToken);

	if (!outcome.Accepted)
	{
		var errorResponse = new ErrorResponseDto(
			ErrorCode: outcome.ErrorCode ?? "choice_rejected",
			Message: outcome.ErrorMessage ?? "Choice was rejected by the adapter.",
			DecisionId: request.DecisionId);

		return outcome.ErrorCode switch
		{
			"stale_decision_id" => Results.Conflict(errorResponse),
			"unknown_decision_id" => Results.NotFound(errorResponse),
			"unknown_action_id" => Results.BadRequest(errorResponse),
			"no_pending_decision" => Results.Conflict(errorResponse),
			_ => Results.BadRequest(errorResponse),
		};
	}

	return Results.Ok(new ChoiceResponseDto(
		Accepted: true,
		ErrorCode: null,
		ErrorMessage: null,
		CurrentDecision: outcome.State.CurrentDecision,
		CommittedEvent: outcome.State.LastCommittedEvent));
});

app.Logger.LogInformation("MtgTtsBridge listening on {ListenUrl}", listenUrl);
Console.WriteLine($"MtgTtsBridge listening on {listenUrl}");

app.Run();

public partial class Program;
