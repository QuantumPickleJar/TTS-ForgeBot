using MtgTtsBridge.Contracts.Actions;
using MtgTtsBridge.Contracts.Events;
using MtgTtsBridge.Contracts.State;

namespace MtgTtsBridge.Forge;

public sealed class MockForgeAdapter : IForgeAdapter
{
    private const string MainDecisionId = "decision-1-main";
    private const string TargetDecisionId = "decision-2-target";

    private readonly object _sync = new();
    private readonly HashSet<string> _resolvedDecisionIds = new(StringComparer.Ordinal);

    private string _sessionId = "session-not-started";
    private string _state = "not_started";
    private string? _pendingFollowupActionId;
    private DecisionDto? _currentDecision;
    private CommittedEventDto? _lastCommittedEvent;
    private int _eventCounter;
    private bool _sessionActive;

    public string Name => "MockForgeAdapter";

    public Task<AdapterStateDto> GetStateAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        lock (_sync)
        {
            return Task.FromResult(CreateStateSnapshot());
        }
    }

    public Task<AdapterStateDto> StartSessionAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        lock (_sync)
        {
            if (!_sessionActive)
            {
                ResetState();
            }
            return Task.FromResult(CreateStateSnapshot());
        }
    }

    public Task<AdapterStateDto> ResetSessionAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        lock (_sync)
        {
            ResetState();
            return Task.FromResult(CreateStateSnapshot());
        }
    }

    public Task<ForgeChoiceResult> SubmitChoiceAsync(ChoiceRequestDto request, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        lock (_sync)
        {
            if (!string.Equals(request.SessionId, _sessionId, StringComparison.Ordinal))
            {
                return Task.FromResult(Reject(
                    "stale_session",
                    "The provided choice belongs to a different Forge session.",
                    _sessionId,
                    request.SessionId));
            }

            if (_currentDecision is null)
            {
                return Task.FromResult(Reject("no_pending_decision", "No decision is currently active."));
            }

            var activeDecisionId = _currentDecision.DecisionId;

            if (!string.Equals(request.DecisionId, activeDecisionId, StringComparison.Ordinal))
            {
                var isStale = _resolvedDecisionIds.Contains(request.DecisionId);
                var errorCode = isStale ? "stale_decision_id" : "unknown_decision_id";
                var errorMessage = isStale
                    ? "The provided decisionId is stale and no longer active."
                    : "The provided decisionId is unknown for the current session state.";

                return Task.FromResult(Reject(errorCode, errorMessage));
            }

            var selectedAction = _currentDecision.Actions
                .FirstOrDefault(action => string.Equals(action.ActionId, request.ActionId, StringComparison.Ordinal));

            if (selectedAction is null)
            {
                return Task.FromResult(Reject("unknown_action_id", "The provided actionId is not legal for this decision."));
            }

            return activeDecisionId switch
            {
                MainDecisionId => Task.FromResult(HandleMainDecisionChoice(selectedAction)),
                TargetDecisionId => Task.FromResult(HandleTargetDecisionChoice(selectedAction)),
                _ => Task.FromResult(Reject("unsupported_decision_kind", "The mock adapter does not recognize this decision kind.")),
            };
        }
    }

    public Task<EventBatchDto> GetEventsAsync(long afterSequence, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult(new EventBatchDto(afterSequence, 1, 0, false, []));
    }

    public Task<GameSnapshotDto?> GetSnapshotAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult<GameSnapshotDto?>(null);
    }

    private void ResetState()
    {
        _sessionId = Guid.NewGuid().ToString("N");
        _state = "awaiting_human_decision";
        _pendingFollowupActionId = null;
        _currentDecision = BuildMainDecision() with { SessionId = _sessionId };
        _lastCommittedEvent = null;
        _eventCounter = 0;
        _resolvedDecisionIds.Clear();
        _sessionActive = true;
    }

    private ForgeChoiceResult HandleMainDecisionChoice(LegalActionDto action)
    {
        _resolvedDecisionIds.Add(MainDecisionId);

        switch (action.ActionId)
        {
            case "pass_priority":
                _lastCommittedEvent = CreateCommittedEvent(
                    sourceActionId: action.ActionId,
                    summary: "Human passed priority.",
                    targetIdentity: null);
                _currentDecision = null;
                _state = "action_committed";
                _pendingFollowupActionId = null;
                return Accept();

            case "play_mountain":
                _lastCommittedEvent = CreateCommittedEvent(
                    sourceActionId: action.ActionId,
                    summary: "Human played Mountain.",
                    targetIdentity: action.ObjectIdentity);
                _currentDecision = null;
                _state = "action_committed";
                _pendingFollowupActionId = null;
                return Accept();

            case "cast_lightning_strike":
                _pendingFollowupActionId = action.ActionId;
                _currentDecision = BuildTargetDecision() with { SessionId = _sessionId };
                _state = "awaiting_followup_choice";
                _lastCommittedEvent = null;
                return Accept();

            default:
                return Reject("unknown_action_id", "The provided actionId is not legal for this decision.");
        }
    }

    private ForgeChoiceResult HandleTargetDecisionChoice(LegalActionDto action)
    {
        var pendingActionId = _pendingFollowupActionId;

        if (pendingActionId is null)
        {
            return Reject("invalid_followup_state", "A target choice was submitted without a matching pending action.");
        }

        if (!string.Equals(pendingActionId, "cast_lightning_strike", StringComparison.Ordinal))
        {
            return Reject("invalid_followup_state", "A target choice was submitted without a matching pending action.");
        }

        _resolvedDecisionIds.Add(TargetDecisionId);

        _lastCommittedEvent = CreateCommittedEvent(
            sourceActionId: pendingActionId,
            summary: $"Lightning Strike committed on {action.DisplayName}.",
            targetIdentity: action.ObjectIdentity ?? action.CardIdentity);

        _pendingFollowupActionId = null;
        _currentDecision = null;
        _state = "action_committed";

        return Accept();
    }

    private ForgeChoiceResult Accept()
    {
        return new ForgeChoiceResult(
            Accepted: true,
            State: CreateStateSnapshot(),
            ErrorCode: null,
            ErrorMessage: null);
    }

    private ForgeChoiceResult Reject(string errorCode, string errorMessage, string? expectedSessionId = null, string? receivedSessionId = null)
    {
        return new ForgeChoiceResult(
            Accepted: false,
            State: CreateStateSnapshot(),
            ErrorCode: errorCode,
            ErrorMessage: errorMessage,
            ExpectedSessionId: expectedSessionId,
            ReceivedSessionId: receivedSessionId);
    }

    private AdapterStateDto CreateStateSnapshot()
    {
        return new AdapterStateDto(
            SessionId: _sessionId,
            State: _state,
            CurrentDecision: CloneDecision(_currentDecision),
            LastCommittedEvent: CloneCommittedEvent(_lastCommittedEvent));
    }

    private CommittedEventDto CreateCommittedEvent(string sourceActionId, string summary, string? targetIdentity)
    {
        _eventCounter += 1;

        return new CommittedEventDto(
            EventId: $"event-{_eventCounter}",
            Kind: "action_committed",
            Summary: summary,
            SourceActionId: sourceActionId,
            TargetIdentity: targetIdentity,
            OccurredAtUtc: DateTimeOffset.UtcNow);
    }

    private static DecisionDto BuildMainDecision()
    {
        return new DecisionDto(
            DecisionId: MainDecisionId,
            Kind: "main_priority",
            Actions:
            [
                new LegalActionDto(
                    ActionId: "pass_priority",
                    Type: "pass_priority",
                    DisplayName: "Pass",
                    RequiresFollowup: false,
                    CardIdentity: null,
                    ObjectIdentity: null),
                new LegalActionDto(
                    ActionId: "play_mountain",
                    Type: "play_land",
                    DisplayName: "Play Mountain",
                    RequiresFollowup: false,
                    CardIdentity: "card:mountain-001",
                    ObjectIdentity: "tts:mountain-guid-001"),
                new LegalActionDto(
                    ActionId: "cast_lightning_strike",
                    Type: "cast_spell",
                    DisplayName: "Cast Lightning Strike",
                    RequiresFollowup: true,
                    CardIdentity: "card:lightning-strike-001",
                    ObjectIdentity: "tts:lightning-strike-guid-001"),
            ]);
    }

    private static DecisionDto BuildTargetDecision()
    {
        return new DecisionDto(
            DecisionId: TargetDecisionId,
            Kind: "target_selection",
            Actions:
            [
                new LegalActionDto(
                    ActionId: "target_opponent",
                    Type: "choose_target",
                    DisplayName: "Target Opponent",
                    RequiresFollowup: false,
                    CardIdentity: null,
                    ObjectIdentity: "player:opponent",
                    TargetKind: "player",
                    TargetSeatId: "forge-player-2"),
                new LegalActionDto(
                    ActionId: "target_test_creature",
                    Type: "choose_target",
                    DisplayName: "Target Test Creature",
                    RequiresFollowup: false,
                    CardIdentity: "card:test-creature-001",
                    ObjectIdentity: "tts:test-creature-guid-001",
                    TargetKind: "card",
                    CardInstanceId: "mock:test-creature-001"),
            ]);
    }

    private static DecisionDto? CloneDecision(DecisionDto? decision)
    {
        if (decision is null)
        {
            return null;
        }

        var actions = decision.Actions
            .Select(action => new LegalActionDto(
                ActionId: action.ActionId,
                Type: action.Type,
                DisplayName: action.DisplayName,
                RequiresFollowup: action.RequiresFollowup,
                CardIdentity: action.CardIdentity,
                ObjectIdentity: action.ObjectIdentity,
                TargetKind: action.TargetKind,
                TargetSeatId: action.TargetSeatId,
                CardInstanceId: action.CardInstanceId))
            .ToArray();

        return decision with { Actions = actions };
    }

    private static CommittedEventDto? CloneCommittedEvent(CommittedEventDto? committedEvent)
    {
        if (committedEvent is null)
        {
            return null;
        }

        return new CommittedEventDto(
            EventId: committedEvent.EventId,
            Kind: committedEvent.Kind,
            Summary: committedEvent.Summary,
            SourceActionId: committedEvent.SourceActionId,
            TargetIdentity: committedEvent.TargetIdentity,
            OccurredAtUtc: committedEvent.OccurredAtUtc);
    }
}
