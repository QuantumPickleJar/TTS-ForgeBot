using System.Drawing;
using System.Windows.Forms;
using MtgTtsBridge;
using MtgTtsBridge.Contracts.Actions;
using MtgTtsBridge.Contracts.Diagnostics;
using MtgTtsBridge.Contracts.State;
using MtgTtsBridge.Diagnostics;
using MtgTtsBridge.Forge;

var trayIcon = new BridgeTrayIcon();

var builder = WebApplication.CreateBuilder(args);

var processIdentity = new BridgeProcessIdentity();
builder.Services.AddSingleton(processIdentity);
var diagnosticTelemetry = new DiagnosticTelemetryBuffer();
builder.Services.AddSingleton(diagnosticTelemetry);
builder.Services.Configure<DiagnosticOptions>(builder.Configuration.GetSection("Diagnostics"));
builder.Services.AddSingleton(serviceProvider => serviceProvider.GetRequiredService<Microsoft.Extensions.Options.IOptions<DiagnosticOptions>>().Value);
builder.Services.AddSingleton<DiagnosticSelfTestRunner>();
builder.Services.AddSingleton<DiagnosticBundleWriter>();
builder.Services.AddSingleton<ProcessSampler>();
builder.Services.AddSingleton<DiagnosticReportCollector>();
builder.Logging.AddProvider(new DiagnosticLoggerProvider(diagnosticTelemetry));

var listenUrl = builder.Configuration["Bridge:ListenUrl"] ?? "http://127.0.0.1:43110";
builder.WebHost.UseUrls(listenUrl);

var adapterName = builder.Environment.IsEnvironment("Testing")
	? "Mock"
	: builder.Configuration["Bridge:Adapter"] ?? "Mock";

if (!builder.Environment.IsEnvironment("Testing"))
{
	BridgePortOwnershipGuard.ThrowIfAlreadyListening(listenUrl);
}

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
var processSampler = app.Services.GetRequiredService<ProcessSampler>();
processSampler.Start();
app.Lifetime.ApplicationStopping.Register(processSampler.Dispose);

app.MapGet("/health", async (IForgeAdapter adapter, BridgeProcessIdentity identity, CancellationToken cancellationToken) =>
{
	var state = await adapter.GetStateAsync(cancellationToken);
	trayIcon.Update(state);

	return Results.Ok(new HealthResponseDto(
		Status: "ok",
		Adapter: adapter.Name,
		AdapterState: state.State,
		SessionId: state.SessionId,
		HasActiveDecision: state.CurrentDecision is not null,
		CurrentDecisionId: state.CurrentDecision?.DecisionId,
		LastCommittedEvent: state.LastCommittedEvent,
		Diagnostic: state.Diagnostic,
		BridgeRevision: BridgeProcessIdentity.Revision,
		BridgeProcessInstanceId: identity.ProcessInstanceId,
		ProcessId: identity.ProcessId,
		ProcessStartUtc: identity.ProcessStartUtc));
});

app.MapPost("/api/v1/session/start", async (IForgeAdapter adapter, ILogger<Program> logger, CancellationToken cancellationToken) =>
{
	logger.LogInformation("Bridge SESSION_START_RECEIVED adapterState={AdapterState}", (await adapter.GetStateAsync(cancellationToken)).State);
	try
	{
		var state = await adapter.StartSessionAsync(cancellationToken);
		trayIcon.Update(state);
		return Results.Ok(new SessionStartResponseDto(state.SessionId, state.CurrentDecision));
	}
	catch (InvalidOperationException exception)
	{
		return Results.BadRequest(new ErrorResponseDto("deck_inventory_required", exception.Message, null));
	}
});

app.MapPost("/api/v1/decks", async (DeckLoadRequestDto request, IForgeAdapter adapter, ILogger<Program> logger, CancellationToken cancellationToken) =>
{
	static string NormalizeFormat(string? format)
	{
		var value = (format ?? string.Empty).Trim().ToLowerInvariant();
		return value switch
		{
			"standard" => "constructed",
			"legacy" => "constructed",
			"constructed" => "constructed",
			"limited" => "limited",
			_ => value
		};
	}

	static int? MinimumDeckSize(string normalizedFormat)
	{
		return normalizedFormat switch
		{
			"limited" => 40,
			"constructed" => 60,
			_ => null
		};
	}

	if (request.Seats.Count != 2 || request.Seats.Any(seat => string.IsNullOrWhiteSpace(seat.SeatId) || seat.Cards.Count == 0)
		|| request.Seats.Select(seat => seat.SeatId).Distinct(StringComparer.Ordinal).Count() != 2
		|| request.Seats.SelectMany(seat => seat.Cards).Any(card => string.IsNullOrWhiteSpace(card.CardName) || card.Count <= 0))
	{
		logger.LogWarning("DECK_VALIDATION_RESULT ok=false reason=invalid-shape seats={SeatCount}", request.Seats.Count);
		return Results.BadRequest(new ErrorResponseDto("invalid_deck_inventory", "Provide two non-empty seat deck inventories with positive card counts.", null));
	}

	var rawFormat = (request.Format ?? string.Empty).Trim();
	var normalizedFormat = NormalizeFormat(rawFormat);
	if (string.IsNullOrWhiteSpace(rawFormat))
	{
		logger.LogWarning("DECK_VALIDATION_RESULT ok=false reason=missing-format humanCards={HumanCards} aiCards={AiCards}",
			request.Seats[0].Cards.Sum(card => card.Count), request.Seats[1].Cards.Sum(card => card.Count));
		return Results.BadRequest(new ErrorResponseDto("missing_format", "Deck format is required (limited or constructed).", null));
	}
	if (string.IsNullOrWhiteSpace(request.FormatProvenance))
	{
		logger.LogWarning("DECK_VALIDATION_RESULT ok=false reason=missing-format-provenance format={Format}", rawFormat);
		return Results.BadRequest(new ErrorResponseDto("missing_format_provenance", "Deck format provenance is required; silent fallback is not allowed.", null));
	}
	var minimum = MinimumDeckSize(normalizedFormat);
	if (minimum is null)
	{
		logger.LogWarning("DECK_VALIDATION_RESULT ok=false reason=unsupported-format format={Format} provenance={FormatProvenance}",
			rawFormat, request.FormatProvenance);
		return Results.BadRequest(new ErrorResponseDto("unsupported_format", "Unsupported deck format. Use limited, constructed, or legacy.", null));
	}

	var humanSeat = request.Seats.SingleOrDefault(seat => string.Equals(seat.SeatId, "forge-player-1", StringComparison.Ordinal));
	var aiSeat = request.Seats.SingleOrDefault(seat => string.Equals(seat.SeatId, "forge-player-2", StringComparison.Ordinal));
	if (humanSeat is null || aiSeat is null)
	{
		logger.LogWarning("DECK_VALIDATION_RESULT ok=false reason=missing-expected-seat seatIds={SeatIds}",
			string.Join(',', request.Seats.Select(seat => seat.SeatId)));
		return Results.BadRequest(new ErrorResponseDto("invalid_deck_inventory", "Deck inventory must include forge-player-1 and forge-player-2 seats.", null));
	}
	var humanCards = humanSeat.Cards.Sum(card => card.Count);
	var aiCards = aiSeat.Cards.Sum(card => card.Count);
	if (!request.AllowDeckMinimumOverride && (humanCards < minimum.Value || aiCards < minimum.Value))
	{
		logger.LogWarning("DECK_VALIDATION_RESULT ok=false reason=deck-minimum format={Format} min={Minimum} humanCards={HumanCards} aiCards={AiCards} override={Override} provenance={FormatProvenance}",
			normalizedFormat, minimum.Value, humanCards, aiCards, request.AllowDeckMinimumOverride, request.FormatProvenance);
		return Results.BadRequest(new ErrorResponseDto(
			"invalid_deck_count",
			$"Deck count below minimum for {normalizedFormat}: required at least {minimum.Value} cards per deck.",
			null));
	}

	if (request.AllowDeckMinimumOverride)
	{
		logger.LogWarning("DECK_VALIDATION_OVERRIDE enabled=true format={Format} min={Minimum} humanCards={HumanCards} aiCards={AiCards} provenance={FormatProvenance}",
			normalizedFormat, minimum.Value, humanCards, aiCards, request.FormatProvenance);
	}
	try
	{
		await adapter.ConfigureDecksAsync(request, cancellationToken);
		logger.LogInformation("DECK_VALIDATION_RESULT ok=true format={Format} min={Minimum} override={Override} provenance={FormatProvenance} humanCards={HumanCards} aiCards={AiCards}",
			normalizedFormat, minimum.Value, request.AllowDeckMinimumOverride, request.FormatProvenance, humanCards, aiCards);
		return Results.NoContent();
	}
	catch (InvalidOperationException exception)
	{
		logger.LogWarning(exception, "DECK_VALIDATION_RESULT ok=false reason=adapter-rejected");
		return Results.BadRequest(new ErrorResponseDto("invalid_deck_inventory", exception.Message, null));
	}
});

app.MapPost("/api/v1/session/reset", async (IForgeAdapter adapter, CancellationToken cancellationToken) =>
{
	try
	{
		var state = await adapter.ResetSessionAsync(cancellationToken);
		trayIcon.Update(state);
		return Results.Ok(new SessionStartResponseDto(state.SessionId, state.CurrentDecision));
	}
	catch (InvalidOperationException exception)
	{
		return Results.BadRequest(new ErrorResponseDto("deck_inventory_required", exception.Message, null));
	}
});

app.MapGet("/api/v1/decision", async (IForgeAdapter adapter, DiagnosticTelemetryBuffer telemetry, CancellationToken cancellationToken) =>
{
	telemetry.RecordProtocol("tts_to_bridge", "/api/v1/decision");
	var state = await adapter.GetStateAsync(cancellationToken);

	if (state.CurrentDecision is null)
	{
		return Results.NotFound(new ErrorResponseDto(
			ErrorCode: state.State == "not_started" || string.IsNullOrWhiteSpace(state.SessionId)
				? "session_not_started" : "no_pending_decision",
			Message: state.State == "not_started" || string.IsNullOrWhiteSpace(state.SessionId)
				? "The Bridge has no active Forge session." : "No active decision is available.",
			DecisionId: null));
	}

	telemetry.RecordProtocol("bridge_to_tts", "/api/v1/decision", 200, state.SessionId, state.CurrentDecision.DecisionId, payload: state.CurrentDecision);
	return Results.Ok(state.CurrentDecision);
});

app.MapPost("/api/v1/diagnostics/report", async (DiagnosticReportRequestDto request, DiagnosticReportCollector collector, DiagnosticTelemetryBuffer telemetry, CancellationToken cancellationToken) =>
{
	telemetry.RecordProtocol("tts_to_bridge", "/api/v1/diagnostics/report", sessionId: request.SessionId, decisionId: request.DecisionId, clientRuntimeId: request.ClientRuntimeId, clientRevision: request.ClientRevision, payload: request);
	var result = await collector.CaptureAsync(request, cancellationToken);
	if (!result.Success)
	{
		telemetry.RecordProtocol("bridge_to_tts", "/api/v1/diagnostics/report", 500, request.SessionId, request.DecisionId, clientRuntimeId: request.ClientRuntimeId, clientRevision: request.ClientRevision, payload: result.Message);
		return Results.Json(new DiagnosticReportFailureDto("diagnostic_capture_failed", result.Message, result.ReportId), statusCode: StatusCodes.Status500InternalServerError);
	}
	telemetry.RecordProtocol("bridge_to_tts", "/api/v1/diagnostics/report", 200, request.SessionId, request.DecisionId, clientRuntimeId: request.ClientRuntimeId, clientRevision: request.ClientRevision, payload: new { result.ReportId, result.ReportPath });
	return Results.Ok(new DiagnosticReportResponseDto(true, result.ReportId, result.ReportPath!, result.Message));
});

app.MapGet("/api/v1/events", async (long? after, IForgeAdapter adapter, DiagnosticTelemetryBuffer telemetry, CancellationToken cancellationToken) =>
{
	var afterSequence = after ?? 0;
	if (afterSequence < 0)
	{
		return Results.BadRequest(new ErrorResponseDto(
			ErrorCode: "invalid_event_sequence",
			Message: "The after sequence must be zero or greater.",
			DecisionId: null));
	}

	telemetry.RecordProtocol("tts_to_bridge", "/api/v1/events", sessionId: null, payload: new { after = afterSequence });
	var batch = await adapter.GetEventsAsync(afterSequence, cancellationToken);
	telemetry.RecordProtocol("bridge_to_tts", "/api/v1/events", batch.HasGap ? 409 : 200, payload: new { batch.LatestSequence, batch.OldestAvailableSequence, batch.HasGap, eventCount = batch.Events.Count });
	if (batch.HasGap)
	{
		return Results.Conflict(new ErrorResponseDto(
			ErrorCode: "event_history_gap",
			Message: $"Events after sequence {afterSequence} are no longer available; oldest available is {batch.OldestAvailableSequence}.",
			DecisionId: null));
	}

	return Results.Ok(batch);
});

app.MapGet("/api/v1/embodiment/snapshot", async (IForgeAdapter adapter, DiagnosticTelemetryBuffer telemetry, CancellationToken cancellationToken) =>
{
	telemetry.RecordProtocol("tts_to_bridge", "/api/v1/embodiment/snapshot");
	var state = await adapter.GetStateAsync(cancellationToken);
	if (state.State == "not_started" || string.IsNullOrWhiteSpace(state.SessionId)
		|| state.SessionId == "session-not-started")
	{
		telemetry.RecordProtocol("bridge_to_tts", "/api/v1/embodiment/snapshot", 404,
			sessionId: "session-not-started", payload: "no active session");
		return Results.NotFound(new ErrorResponseDto(
			ErrorCode: "session_not_started",
			Message: "The Bridge has no active Forge session.",
			DecisionId: null));
	}
	var snapshot = await adapter.GetSnapshotAsync(cancellationToken);
	telemetry.RecordProtocol("bridge_to_tts", "/api/v1/embodiment/snapshot", snapshot is null ? 404 : 200, sessionId: snapshot?.SessionId, payload: snapshot is null ? "unavailable" : new { snapshot.EventCursor, snapshot.ForgeSequence });
	return snapshot is null
		? Results.NotFound(new ErrorResponseDto(
			ErrorCode: "snapshot_unavailable",
			Message: "The active adapter has not produced an authoritative embodiment snapshot.",
			DecisionId: null))
		: Results.Ok(snapshot);
});

app.MapPost("/api/v1/choice", async (ChoiceRequestDto request, IForgeAdapter adapter, HttpContext httpContext, ILogger<Program> logger, DiagnosticTelemetryBuffer telemetry, CancellationToken cancellationToken) =>
{
	telemetry.RecordProtocol("tts_to_bridge", "/api/v1/choice", sessionId: request.SessionId, decisionId: request.DecisionId, requestId: request.RequestId, clientRuntimeId: request.ClientRuntimeId, clientRevision: request.ClientRevision, payload: request);
	var missingFields = new List<string>();
	if (string.IsNullOrWhiteSpace(request.DecisionId)) missingFields.Add("decisionId");
	if (string.IsNullOrWhiteSpace(request.ActionId)) missingFields.Add("actionId");
	if (string.IsNullOrWhiteSpace(request.SessionId)) missingFields.Add("sessionId");
	if (string.IsNullOrWhiteSpace(request.RequestId)) missingFields.Add("requestId");
	if (string.IsNullOrWhiteSpace(request.ClientRuntimeId)) missingFields.Add("clientRuntimeId");
	if (string.IsNullOrWhiteSpace(request.ClientRevision)) missingFields.Add("clientRevision");
	if (string.IsNullOrWhiteSpace(request.Source)) missingFields.Add("source");

	if (missingFields.Count > 0)
	{
		logger.LogWarning(
			"LEGACY_OR_MALFORMED_CHOICE missingFields={MissingFields} decisionId={DecisionId} actionId={ActionId} sessionId={SessionId} requestId={RequestId} clientRuntimeId={ClientRuntimeId} clientRevision={ClientRevision} source={Source} remote={Remote} bridgeProcessInstanceId={BridgeProcessInstanceId} bridgeRevision={BridgeRevision}",
			string.Join(',', missingFields),
			request.DecisionId ?? "(missing)",
			request.ActionId ?? "(missing)",
			request.SessionId ?? "(missing)",
			request.RequestId ?? "(missing)",
			request.ClientRuntimeId ?? "(missing)",
			request.ClientRevision ?? "(missing)",
			request.Source ?? "(missing)",
			httpContext.Connection.RemoteIpAddress,
			BridgeProcessIdentity.InstanceId,
			BridgeProcessIdentity.Revision);
		return Results.BadRequest(new ErrorResponseDto(
			ErrorCode: "invalid_request",
			Message: "Missing required fields: " + string.Join(", ", missingFields) + ".",
			DecisionId: request.DecisionId,
			ReceivedSessionId: request.SessionId,
			RequestId: request.RequestId,
			MissingFields: missingFields));
	}

	var outcome = await adapter.SubmitChoiceAsync(request, cancellationToken);
	telemetry.RecordChoice(request, outcome.Accepted ? "accepted" : "rejected", outcome.ErrorCode, outcome.ErrorMessage);

	if (!outcome.Accepted)
	{
		var errorResponse = new ErrorResponseDto(
			ErrorCode: outcome.ErrorCode ?? "choice_rejected",
			Message: outcome.ErrorMessage ?? "Choice was rejected by the adapter.",
			DecisionId: request.DecisionId,
			ExpectedSessionId: outcome.ExpectedSessionId,
			ReceivedSessionId: outcome.ReceivedSessionId,
			RequestId: request.RequestId);

		telemetry.RecordProtocol("bridge_to_tts", "/api/v1/choice", 409, request.SessionId, request.DecisionId, request.RequestId, request.ClientRuntimeId, request.ClientRevision, errorResponse);
		return outcome.ErrorCode switch
		{
			"stale_decision_id" => Results.Conflict(errorResponse),
			"decision_already_resolved" => Results.Conflict(errorResponse),
			"stale_session" => Results.Conflict(errorResponse),
			"unknown_decision_id" => Results.NotFound(errorResponse),
			"unknown_action_id" => Results.BadRequest(errorResponse),
			"no_pending_decision" => Results.Conflict(errorResponse),
			_ => Results.BadRequest(errorResponse),
		};
	}

	var response = new ChoiceResponseDto(
		Accepted: true,
		ErrorCode: null,
		ErrorMessage: null,
		CurrentDecision: outcome.State.CurrentDecision,
		CommittedEvent: outcome.State.LastCommittedEvent);
	telemetry.RecordProtocol("bridge_to_tts", "/api/v1/choice", 200, request.SessionId, request.DecisionId, request.RequestId, request.ClientRuntimeId, request.ClientRevision, response);
	return Results.Ok(response);
});

app.Logger.LogInformation("BRIDGE_PROCESS_STARTED revision={Revision} instance={Instance} pid={Pid} startUtc={StartUtc} listenUrl={ListenUrl}", BridgeProcessIdentity.Revision, processIdentity.ProcessInstanceId, processIdentity.ProcessId, processIdentity.ProcessStartUtc, listenUrl);
Console.WriteLine($"MtgTtsBridge listening on {listenUrl} revision={BridgeProcessIdentity.Revision} instance={processIdentity.ProcessInstanceId} pid={processIdentity.ProcessId} startUtc={processIdentity.ProcessStartUtc:O}");
trayIcon.Show();

try
{
    app.Run();
}
finally
{
    trayIcon.Dispose();
}

public partial class Program;

public sealed class BridgeTrayIcon : IDisposable
{
    private readonly NotifyIcon _notifyIcon;

    public BridgeTrayIcon()
    {
        _notifyIcon = new NotifyIcon
        {
            Visible = false,
            Text = "MtgTtsBridge"
        };

        var icon = TryLoadTtsIcon() ?? SystemIcons.Information;
        _notifyIcon.Icon = icon;
        _notifyIcon.ContextMenuStrip = new ContextMenuStrip();
        _notifyIcon.ContextMenuStrip.Items.Add("MtgTtsBridge");
        _notifyIcon.ContextMenuStrip.Items.Add(new ToolStripSeparator());
        var exitItem = new ToolStripMenuItem("Exit");
        exitItem.Click += (_, _) => Environment.Exit(0);
        _notifyIcon.ContextMenuStrip.Items.Add(exitItem);
    }

    public void Show() => _notifyIcon.Visible = true;

    public void Update(AdapterStateDto state)
    {
        var detail = state.State switch
        {
            "not_started" => "not started",
            "starting" => "Forge booting",
            "awaiting_human_decision" => state.CurrentDecision is null ? "waiting" : $"decision: {state.CurrentDecision.Kind}",
            "awaiting_forge" => "waiting for Forge",
            "unsupported_decision" => "unsupported prompt",
            "failed" => "Forge failed",
            _ => state.State
        };

        _notifyIcon.Text = BuildTooltipText(detail);
        _notifyIcon.Icon = GetIconForState(state.State, detail);
    }

    public void Dispose() => _notifyIcon.Dispose();

    private Icon GetIconForState(string state, string detail)
    {
        var baseIcon = TryLoadTtsIcon();
        if (state == "failed") return SystemIcons.Error;
        if (state == "starting") return SystemIcons.Warning;
        if (state == "awaiting_human_decision") return SystemIcons.Shield;
        if (state == "awaiting_forge") return SystemIcons.Information;
        return baseIcon ?? SystemIcons.Information;
    }

    private static Icon? TryLoadTtsIcon()
    {
        var candidates = new[]
        {
            "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Tabletop Simulator\\TabletopSimulator.exe",
            "C:\\Program Files\\Steam\\steamapps\\common\\Tabletop Simulator\\TabletopSimulator.exe",
            "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Tabletop Simulator\\Tabletop Simulator.exe",
            "C:\\Program Files\\Steam\\steamapps\\common\\Tabletop Simulator\\Tabletop Simulator.exe"
        };

        foreach (var candidate in candidates)
        {
            if (File.Exists(candidate))
            {
                try { return Icon.ExtractAssociatedIcon(candidate); }
                catch { }
            }
        }

        return null;
    }

    private static string BuildTooltipText(string detail)
    {
        const string appName = "MtgTtsBridge";
        var summary = $"{appName} - {detail}";
        if (summary.Length <= 63) return summary;
        return summary[..63];
    }
}
