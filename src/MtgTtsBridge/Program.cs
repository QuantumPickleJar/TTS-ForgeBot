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

app.MapPost("/api/v1/session/start", async (IForgeAdapter adapter, CancellationToken cancellationToken) =>
{
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

app.MapPost("/api/v1/decks", async (DeckLoadRequestDto request, IForgeAdapter adapter, CancellationToken cancellationToken) =>
{
	if (request.Seats.Count != 2 || request.Seats.Any(seat => string.IsNullOrWhiteSpace(seat.SeatId) || seat.Cards.Count == 0)
		|| request.Seats.Select(seat => seat.SeatId).Distinct(StringComparer.Ordinal).Count() != 2
		|| request.Seats.SelectMany(seat => seat.Cards).Any(card => string.IsNullOrWhiteSpace(card.CardName) || card.Count <= 0))
	{
		return Results.BadRequest(new ErrorResponseDto("invalid_deck_inventory", "Provide two non-empty seat deck inventories with positive card counts.", null));
	}
	try
	{
		await adapter.ConfigureDecksAsync(request, cancellationToken);
		return Results.NoContent();
	}
	catch (InvalidOperationException exception)
	{
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
			ErrorCode: "no_pending_decision",
			Message: "No active decision is available.",
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
