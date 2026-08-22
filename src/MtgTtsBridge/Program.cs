using System.Drawing;
using System.Windows.Forms;
using MtgTtsBridge.Contracts.Actions;
using MtgTtsBridge.Contracts.State;
using MtgTtsBridge.Forge;

var trayIcon = new BridgeTrayIcon();

var builder = WebApplication.CreateBuilder(args);

var listenUrl = builder.Configuration["Bridge:ListenUrl"] ?? "http://127.0.0.1:43110";
builder.WebHost.UseUrls(listenUrl);

var adapterName = builder.Environment.IsEnvironment("Testing")
	? "Mock"
	: builder.Configuration["Bridge:Adapter"] ?? "Mock";

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
	trayIcon.Update(state);

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
	trayIcon.Update(state);
	return Results.Ok(new SessionStartResponseDto(
		SessionId: state.SessionId,
		CurrentDecision: state.CurrentDecision));
});

app.MapPost("/api/v1/session/reset", async (IForgeAdapter adapter, CancellationToken cancellationToken) =>
{
	var state = await adapter.ResetSessionAsync(cancellationToken);
	trayIcon.Update(state);
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

app.MapGet("/api/v1/embodiment/snapshot", async (IForgeAdapter adapter, CancellationToken cancellationToken) =>
{
	var snapshot = await adapter.GetSnapshotAsync(cancellationToken);
	return snapshot is null
		? Results.NotFound(new ErrorResponseDto(
			ErrorCode: "snapshot_unavailable",
			Message: "The active adapter has not produced an authoritative embodiment snapshot.",
			DecisionId: null))
		: Results.Ok(snapshot);
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
