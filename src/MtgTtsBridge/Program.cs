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
		LastCommittedEvent: state.LastCommittedEvent));
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
