using MtgTtsBridge.Contracts.Diagnostics;
using MtgTtsBridge.Contracts.Events;
using MtgTtsBridge.Contracts.State;

namespace MtgTtsBridge.Diagnostics;

public sealed record DiagnosticSelfTestCheck(
    string Id,
    string Severity,
    string Status,
    string Message,
    IReadOnlyDictionary<string, object?>? Evidence = null);

public sealed record DiagnosticSelfTestResult(IReadOnlyList<DiagnosticSelfTestCheck> Checks)
{
    public int PassCount => Checks.Count(item => item.Status == "pass");
    public int WarningCount => Checks.Count(item => item.Status == "warning");
    public int FailCount => Checks.Count(item => item.Status == "fail");
    public int UnavailableCount => Checks.Count(item => item.Status == "unavailable");
}

/// <summary>Runs synchronization checks only; it never evaluates Magic legality.</summary>
public sealed class DiagnosticSelfTestRunner
{
    public DiagnosticSelfTestResult Run(
        AdapterStateDto? adapterState,
        EventBatchDto? eventBatch,
        GameSnapshotDto? snapshot,
        DiagnosticReportRequestDto request,
        BridgeProcessIdentity identity)
    {
        var checks = new List<DiagnosticSelfTestCheck>
        {
            CheckBridgeProcess(identity, adapterState),
            CheckAdapter(adapterState),
            CheckSessionExists(adapterState, request),
            CheckSessionAgreement(adapterState, request),
            CheckDecisionAgreement(adapterState, request),
            CheckDecisionWatermarks(adapterState),
            CheckEventSequence(eventBatch),
            CheckTtsNotAhead(eventBatch, request),
            CheckTtsBehind(eventBatch, request),
            CheckSnapshot(snapshot),
            CheckCardMappings(snapshot, request),
            CheckDecisionProvenanceLag(adapterState, eventBatch, snapshot, request),
            CheckResultPresentationInvariants(adapterState, request),
            CheckRecoveryInvariants(eventBatch, snapshot, request),
            CheckTerminalStatusHonesty(request),
            CheckGenerationChurn(adapterState, eventBatch, snapshot, request)
        };
        return new DiagnosticSelfTestResult(checks);
    }

    private static DiagnosticSelfTestCheck CheckDecisionWatermarks(AdapterStateDto? state)
    {
        if (state?.Diagnostic is null)
            return Check("decision_watermark_ordering", "info", "unavailable", "Adapter did not provide decision watermark diagnostics.");
        var decision = state.CurrentDecision;
        if (decision is null)
            return Check("decision_watermark_ordering", "info", "unavailable", "No authoritative current decision is available.");

        var eligible = state.Diagnostic.LatestDecisionEligibleCursor;
        if (eligible is not null && decision.EventCursor is not null && decision.EventCursor < eligible)
        {
            return Check("decision_watermark_ordering", "error", "fail",
                "Current decision cursor is behind the latest decision-eligible cursor.",
                new Dictionary<string, object?>
                {
                    ["decisionId"] = decision.DecisionId,
                    ["decisionCursor"] = decision.EventCursor,
                    ["eligibleCursor"] = eligible,
                    ["committedCursor"] = state.Diagnostic.LatestCommittedMutationCursor,
                    ["observedCursor"] = state.Diagnostic.LatestObservedEventCursor
                });
        }

        if (state.Diagnostic.PendingDecisionAwaitingWatermark
            && string.Equals(state.Diagnostic.PendingDecisionId, decision.DecisionId, StringComparison.Ordinal))
        {
            return Check("decision_watermark_ordering", "error", "fail",
                "A pending textual decision is exposed before its structured watermark completed.",
                new Dictionary<string, object?> { ["decisionId"] = decision.DecisionId });
        }

        return Check("decision_watermark_ordering", "info", "pass", "Decision publication respects watermark ordering.");
    }

    private static DiagnosticSelfTestCheck CheckBridgeProcess(BridgeProcessIdentity identity, AdapterStateDto? state) =>
        state is null
            ? Check("bridge_process_healthy", "error", "unavailable", "Bridge state could not be read.")
            : state.State == "failed"
                ? Check("bridge_process_healthy", "error", "fail", "The bridge reports a failed adapter state.", new Dictionary<string, object?> { ["adapterState"] = state.State })
                : Check("bridge_process_healthy", "info", "pass", "Bridge process identity is available.", new Dictionary<string, object?> { ["processId"] = identity.ProcessId, ["processStartUtc"] = identity.ProcessStartUtc });

    private static DiagnosticSelfTestCheck CheckAdapter(AdapterStateDto? state) =>
        state is null
            ? Check("forge_adapter_responding", "error", "unavailable", "The Forge adapter did not return state.")
            : state.State == "failed"
                ? Check("forge_adapter_responding", "error", "fail", "The Forge adapter reports failure.", new Dictionary<string, object?> { ["diagnostic"] = state.Diagnostic?.Message })
                : Check("forge_adapter_responding", "info", "pass", "The Forge adapter returned state.", new Dictionary<string, object?> { ["state"] = state.State, ["sessionId"] = state.SessionId });

    private static DiagnosticSelfTestCheck CheckSessionExists(AdapterStateDto? state, DiagnosticReportRequestDto request)
    {
        if (string.IsNullOrWhiteSpace(request.SessionId)) return Check("active_session_exists", "info", "unavailable", "TTS did not report a session ID.");
        return state is not null && !string.IsNullOrWhiteSpace(state.SessionId) && state.SessionId != "session-not-started"
            ? Check("active_session_exists", "info", "pass", "An authoritative session exists.", new Dictionary<string, object?> { ["sessionId"] = state.SessionId })
            : Check("active_session_exists", "warning", "warning", "TTS reported a session, but the bridge has no active authoritative session.");
    }

    private static DiagnosticSelfTestCheck CheckSessionAgreement(AdapterStateDto? state, DiagnosticReportRequestDto request)
    {
        if (string.IsNullOrWhiteSpace(request.SessionId)) return Check("session_ids_agree", "info", "unavailable", "TTS did not report a session ID.");
        if (state is null) return Check("session_ids_agree", "error", "unavailable", "Bridge session could not be read.");
        return string.Equals(request.SessionId, state.SessionId, StringComparison.Ordinal)
            ? Check("session_ids_agree", "info", "pass", "TTS and bridge session IDs agree.", new Dictionary<string, object?> { ["sessionId"] = state.SessionId })
            : Check("session_ids_agree", "error", "fail", "TTS and bridge session IDs disagree.", new Dictionary<string, object?> { ["ttsSessionId"] = request.SessionId, ["bridgeSessionId"] = state.SessionId });
    }

    private static DiagnosticSelfTestCheck CheckDecisionAgreement(AdapterStateDto? state, DiagnosticReportRequestDto request)
    {
        if (string.IsNullOrWhiteSpace(request.DecisionId)) return Check("decision_ids_agree", "info", "unavailable", "TTS did not report a decision ID.");
        if (state?.CurrentDecision is null) return Check("decision_ids_agree", "warning", "unavailable", "No authoritative current decision is available for comparison.");
        return string.Equals(request.DecisionId, state.CurrentDecision.DecisionId, StringComparison.Ordinal)
            ? Check("decision_ids_agree", "info", "pass", "TTS and authoritative decision IDs agree.", new Dictionary<string, object?> { ["decisionId"] = request.DecisionId })
            : Check("decision_ids_agree", "error", "fail", "TTS and authoritative decision IDs disagree.", new Dictionary<string, object?> { ["ttsDecisionId"] = request.DecisionId, ["bridgeDecisionId"] = state.CurrentDecision.DecisionId });
    }

    private static DiagnosticSelfTestCheck CheckEventSequence(EventBatchDto? batch)
    {
        if (batch is null) return Check("event_sequence_contiguous", "error", "unavailable", "Authoritative event history could not be read.");
        if (batch.HasGap) return Check("event_sequence_contiguous", "error", "fail", "The available authoritative event history has a gap.", new Dictionary<string, object?> { ["oldestAvailableSequence"] = batch.OldestAvailableSequence, ["requestedAfterSequence"] = batch.RequestedAfterSequence });
        long? previous = null;
        foreach (var item in batch.Events)
        {
            if (previous is not null && item.Sequence != previous + 1)
                return Check("event_sequence_contiguous", "error", "fail", "The captured authoritative events contain a sequence gap.", new Dictionary<string, object?> { ["previous"] = previous, ["current"] = item.Sequence });
            previous = item.Sequence;
        }
        return Check("event_sequence_contiguous", "info", "pass", "No event sequence gap was detected.", new Dictionary<string, object?> { ["latestSequence"] = batch.LatestSequence });
    }

    private static DiagnosticSelfTestCheck CheckTtsNotAhead(EventBatchDto? batch, DiagnosticReportRequestDto request)
    {
        if (request.LastAppliedEventSequence is null) return Check("tts_not_ahead", "info", "unavailable", "TTS did not report its last applied event sequence.");
        if (batch is null) return Check("tts_not_ahead", "error", "unavailable", "Authoritative event history could not be read.");
        return request.LastAppliedEventSequence > batch.LatestSequence
            ? Check("tts_not_ahead", "error", "fail", "TTS reports an applied event sequence ahead of the bridge history.", new Dictionary<string, object?> { ["ttsApplied"] = request.LastAppliedEventSequence, ["bridgeLatest"] = batch.LatestSequence })
            : Check("tts_not_ahead", "info", "pass", "TTS is not ahead of the authoritative event history.", new Dictionary<string, object?> { ["ttsApplied"] = request.LastAppliedEventSequence, ["bridgeLatest"] = batch.LatestSequence });
    }

    private static DiagnosticSelfTestCheck CheckTtsBehind(EventBatchDto? batch, DiagnosticReportRequestDto request)
    {
        if (request.LastAppliedEventSequence is null) return Check("tts_current_or_behind", "info", "unavailable", "TTS did not report its last applied event sequence.");
        if (batch is null) return Check("tts_current_or_behind", "error", "unavailable", "Authoritative event history could not be read.");
        return request.LastAppliedEventSequence < batch.LatestSequence
            ? Check("tts_current_or_behind", "warning", "warning", "TTS appears behind the latest authoritative event.", new Dictionary<string, object?> { ["ttsApplied"] = request.LastAppliedEventSequence, ["bridgeLatest"] = batch.LatestSequence })
            : Check("tts_current_or_behind", "info", "pass", "TTS has applied the latest captured authoritative event.");
    }

    private static DiagnosticSelfTestCheck CheckSnapshot(GameSnapshotDto? snapshot) =>
        snapshot is null
            ? Check("authoritative_snapshot_available", "warning", "unavailable", "The adapter did not provide an authoritative embodiment snapshot.")
            : Check("authoritative_snapshot_available", "info", "pass", "An authoritative embodiment snapshot is available.", new Dictionary<string, object?> { ["eventCursor"] = snapshot.EventCursor, ["forgeSequence"] = snapshot.ForgeSequence });

    private static DiagnosticSelfTestCheck CheckCardMappings(GameSnapshotDto? snapshot, DiagnosticReportRequestDto request)
    {
        if (snapshot is null) return Check("snapshot_card_mappings", "info", "unavailable", "No snapshot is available for mapping comparison.");
        var referenced = ReferencedPhysicalCardInstanceIds(snapshot);
        if (request.PhysicalMappings is not null)
        {
            var audit = AuditPhysicalMappings(referenced, request.PhysicalMappings);
            if (!audit.IsCoherent)
            {
                return Check("snapshot_card_mappings", "error", "fail",
                    "Authoritative physical mappings are not live and unique.",
                    new Dictionary<string, object?>
                    {
                        ["missingCardInstanceIds"] = audit.Missing,
                        ["duplicateCardInstanceIds"] = audit.DuplicateInstances,
                        ["duplicateGuids"] = audit.DuplicateGuids,
                        ["invalidMappings"] = audit.Invalid,
                        ["referencedCount"] = referenced.Length
                    });
            }
            return Check("snapshot_card_mappings", "info", "pass",
                "Authoritative physical mappings are live, unique, and identity-consistent.",
                new Dictionary<string, object?> { ["referencedCount"] = referenced.Length, ["mappingCount"] = request.PhysicalMappings.Count });
        }
        if (request.MappedCardInstanceIds is null) return Check("snapshot_card_mappings", "info", "unavailable", "TTS did not supply card instance mapping information.");
        var mapped = request.MappedCardInstanceIds.ToHashSet(StringComparer.Ordinal);
        var missingLegacy = referenced.Where(item => !mapped.Contains(item)).ToArray();
        return missingLegacy.Length == 0
            ? Check("snapshot_card_mappings", "info", "pass", "Snapshot combat card instances are represented in TTS mapping information.", new Dictionary<string, object?> { ["referencedCount"] = referenced.Length })
            : Check("snapshot_card_mappings", "error", "fail", "Authoritative combat card instances are missing from TTS mapping information.", new Dictionary<string, object?> { ["missingCardInstanceIds"] = missingLegacy, ["referencedCount"] = referenced.Length });
    }

    private static DiagnosticSelfTestCheck CheckDecisionProvenanceLag(
        AdapterStateDto? state,
        EventBatchDto? batch,
        GameSnapshotDto? snapshot,
        DiagnosticReportRequestDto request)
    {
        var decision = state?.CurrentDecision;
        if (decision is null) return Check("decision_provenance_current", "info", "unavailable", "No authoritative current decision is available.");
        if (request.LastAppliedEventSequence is null) return Check("decision_provenance_current", "info", "unavailable", "TTS did not report its committed cursor.");
        var decisionCursor = decision.EventCursor;
        if (decisionCursor is null) return Check("decision_provenance_current", "info", "unavailable", "The authoritative decision has no event cursor.");

        var ttsApplied = request.LastAppliedEventSequence.Value;
        var bridgeLatest = batch?.LatestSequence;
        var snapshotCursor = snapshot?.EventCursor;
        var cursorsAgree = CursorMissingOrEquals(bridgeLatest, ttsApplied)
            && CursorMissingOrEquals(snapshotCursor, ttsApplied);
        var noInstalledDecision = string.IsNullOrWhiteSpace(request.DecisionId);
        var noRepairWork = RequestHasNoRepairWork(request);
        var mappingsCoherent = snapshot is not null && RequestMappingsCoherent(snapshot, request);
        if (decisionCursor.Value < ttsApplied && cursorsAgree && noInstalledDecision && noRepairWork && mappingsCoherent)
        {
            return Check("decision_provenance_current", "error", "fail",
                "Forge is still publishing a stale decision while TTS, the event stream, snapshot, and physical mappings are coherent.",
                new Dictionary<string, object?>
                {
                    ["classification"] = "decision_provenance_lag",
                    ["decisionId"] = decision.DecisionId,
                    ["decisionEventCursor"] = decision.EventCursor,
                    ["ttsApplied"] = ttsApplied,
                    ["bridgeLatest"] = bridgeLatest,
                    ["snapshotCursor"] = snapshotCursor
                });
        }

        return decisionCursor.Value < ttsApplied
            ? Check("decision_provenance_current", "warning", "warning", "The authoritative decision is behind TTS, but other recovery evidence is not fully coherent.")
            : Check("decision_provenance_current", "info", "pass", "The authoritative decision cursor is not behind TTS.");
    }

    private static DiagnosticSelfTestCheck CheckRecoveryInvariants(EventBatchDto? batch, GameSnapshotDto? snapshot, DiagnosticReportRequestDto request)
    {
        var drain = request.EventDrainDiagnostics;
        if (drain is null) return Check("recovery_state_invariants", "info", "unavailable", "TTS did not provide recovery scheduler diagnostics.");
        var failures = new List<string>();
        if (drain.Bootstrapping && ((request.Turn ?? snapshot?.TurnNumber ?? 0) > 1 || (request.LastAppliedEventSequence ?? 0) > 0))
            failures.Add("ACTIVE_GAME_REENTERED_BOOTSTRAP");
        if (drain.ResyncInFlight && !drain.DesyncLatched && RequestHasNoRepairWork(request)
            && request.LastAppliedEventSequence.HasValue
            && CursorMissingOrEquals(batch?.LatestSequence, request.LastAppliedEventSequence.Value)
            && CursorMissingOrEquals(snapshot?.EventCursor, request.LastAppliedEventSequence.Value))
            failures.Add("RESYNC_ACTIVE_WITHOUT_LATCH_OR_REPAIR_WORK");
        if (drain.ResyncInFlight && StatusLooksTerminal(request.Status))
            failures.Add("TERMINAL_RECOVERY_ERROR_WITH_RESYNC_IN_FLIGHT");

        return failures.Count == 0
            ? Check("recovery_state_invariants", "info", "pass", "No recovery scheduler invariant failure was detected.")
            : Check("recovery_state_invariants", "error", "fail", "Recovery scheduler state violates terminal/liveness invariants.",
                new Dictionary<string, object?> { ["failures"] = failures.ToArray() });
    }

    private static DiagnosticSelfTestCheck CheckResultPresentationInvariants(AdapterStateDto? state, DiagnosticReportRequestDto request)
    {
        var presented = request.PresentedResult;
        if (presented is null || !presented.Presented)
            return Check("result_presentation_invariants", "info", "unavailable", "TTS did not report a presented match result.");

        var failures = new List<string>();
        if (presented.TerminalRecoveryError) failures.Add("TERMINAL_RECOVERY_PRESENTED_AS_MATCH_RESULT");
        if (state?.Result is null && string.Equals(presented.Outcome, "draw", StringComparison.OrdinalIgnoreCase))
            failures.Add("NULL_RESULT_PRESENTED_AS_DRAW");
        if (string.IsNullOrWhiteSpace(presented.SourceEventId) || presented.SourceEventCursor is null)
            failures.Add("RESULT_PRESENTED_WITHOUT_SOURCE_EVENT");
        if (!string.IsNullOrWhiteSpace(presented.SourceSessionId)
            && !string.IsNullOrWhiteSpace(request.SessionId)
            && !string.Equals(presented.SourceSessionId, request.SessionId, StringComparison.Ordinal))
            failures.Add("RESULT_EVENT_FROM_OTHER_SESSION");

        if (failures.Count > 0)
        {
            return Check("result_presentation_invariants", "error", "fail",
                "Result presentation violates authoritative result gating.",
                new Dictionary<string, object?> { ["failures"] = failures.ToArray() });
        }

        return Check("result_presentation_invariants", "info", "pass", "Presented match result has authoritative source metadata.");
    }

    private static DiagnosticSelfTestCheck CheckTerminalStatusHonesty(DiagnosticReportRequestDto request)
    {
        var terminal = request.EventDrainDiagnostics?.TerminalRecoveryError == true;
        if (!terminal) return Check("terminal_status_honesty", "info", "unavailable", "TTS did not report terminal recovery state.");
        if (string.Equals(request.Status, "MATCH ACTIVE", StringComparison.OrdinalIgnoreCase))
        {
            return Check("terminal_status_honesty", "error", "fail",
                "TTS reports MATCH ACTIVE while terminal recovery error is set.",
                new Dictionary<string, object?> { ["failure"] = "MATCH_ACTIVE_WITH_TERMINAL_RECOVERY_ERROR", ["status"] = request.Status });
        }
        return Check("terminal_status_honesty", "info", "pass", "Terminal recovery is not presented as an active match.", new Dictionary<string, object?> { ["status"] = request.Status });
    }

    private static DiagnosticSelfTestCheck CheckGenerationChurn(
        AdapterStateDto? state,
        EventBatchDto? batch,
        GameSnapshotDto? snapshot,
        DiagnosticReportRequestDto request)
    {
        var lifecycle = request.DiagnosticCaptureLifecycle;
        if (lifecycle is null || lifecycle.Count < 2)
            return Check("generation_churn_without_progress", "info", "unavailable", "TTS did not provide enough lifecycle samples.");
        var first = lifecycle.First();
        var last = lifecycle.Last();
        var noAuthoritativeProgress = first.LastAppliedEventSequence == last.LastAppliedEventSequence
            && first.LastReceivedEventSequence == last.LastReceivedEventSequence
            && CursorMissingOrEquals(batch?.LatestSequence, last.LastAppliedEventSequence)
            && CursorMissingOrEquals(snapshot?.EventCursor, last.LastAppliedEventSequence);
        var presentationChurn = last.PhysicalPresentationGeneration - first.PhysicalPresentationGeneration;
        var transactionChurn = last.PhysicalTransactionGeneration - first.PhysicalTransactionGeneration;
        var repeatedRecovery = lifecycle.Count(item => item.ResyncInFlight || !string.IsNullOrWhiteSpace(item.ResyncOrigin)) > 1;
        if (noAuthoritativeProgress && repeatedRecovery && presentationChurn > 4 && transactionChurn <= 1)
        {
            return Check("generation_churn_without_progress", "error", "fail",
                "Recovery generations changed repeatedly without physical or authoritative progress.",
                new Dictionary<string, object?>
                {
                    ["firstApplied"] = first.LastAppliedEventSequence,
                    ["lastApplied"] = last.LastAppliedEventSequence,
                    ["physicalPresentationGenerationDelta"] = presentationChurn,
                    ["physicalTransactionGenerationDelta"] = transactionChurn,
                    ["currentDecisionId"] = state?.CurrentDecision?.DecisionId
                });
        }

        return Check("generation_churn_without_progress", "info", "pass", "No no-progress generation churn was detected.");
    }

    private static string[] ReferencedPhysicalCardInstanceIds(GameSnapshotDto snapshot)
    {
        // Cards still contained in an opaque Forge/TTS library Deck do not
        // have distinct loose TTS embodiments. Requiring their instance IDs
        // here turns a normal early-turn snapshot into a false mapping alarm.
        var snapshotCards = snapshot.Seats
            .SelectMany(seat => seat.Zones)
            .Where(zone => !string.Equals(zone.Name, "library", StringComparison.OrdinalIgnoreCase))
            .SelectMany(zone => zone.Cards)
            .Where(IsPhysicalCard);
        var snapshotStackCards = snapshot.Stack.Where(IsPhysicalCard);
        var combatCards = snapshot.Combat?.Attacks
            .SelectMany(item => new[] { item.AttackerCardInstanceId }.Concat(item.BlockerCardInstanceIds))
            ?? [];
        return snapshotCards
            .Concat(snapshotStackCards)
            .Select(card => card.CardInstanceId)
            .Concat(combatCards)
            .Distinct(StringComparer.Ordinal)
            .ToArray();
    }

    private static bool IsPhysicalCard(GameCardSnapshotDto card) =>
        !card.IsVirtual
        && !string.Equals(card.MaterializationPolicy, "virtual", StringComparison.OrdinalIgnoreCase)
        && !string.Equals(card.MaterializationPolicy, "virtual-stack", StringComparison.OrdinalIgnoreCase);

    private sealed record MappingAudit(string[] Missing, string[] DuplicateInstances, string[] DuplicateGuids, string[] Invalid)
    {
        public bool IsCoherent => Missing.Length == 0 && DuplicateInstances.Length == 0 && DuplicateGuids.Length == 0 && Invalid.Length == 0;
    }

    private static MappingAudit AuditPhysicalMappings(string[] referenced, IReadOnlyList<DiagnosticPhysicalMappingDto> mappings)
    {
        var duplicateInstances = mappings.GroupBy(item => item.CardInstanceId, StringComparer.Ordinal)
            .Where(group => group.Count() > 1).Select(group => group.Key).ToArray();
        var duplicateGuids = mappings.GroupBy(item => item.Guid, StringComparer.Ordinal)
            .Where(group => group.Count() > 1).Select(group => group.Key).ToArray();
        var invalid = mappings.Where(item => string.IsNullOrWhiteSpace(item.Guid)
                || !item.IsLive
                || string.IsNullOrWhiteSpace(item.AdvertisedCardInstanceId)
                || !string.Equals(item.CardInstanceId, item.AdvertisedCardInstanceId, StringComparison.Ordinal))
            .Select(item => item.CardInstanceId).Distinct(StringComparer.Ordinal).ToArray();
        var mappingByInstance = mappings
            .GroupBy(item => item.CardInstanceId, StringComparer.Ordinal)
            .ToDictionary(group => group.Key, group => group.First(), StringComparer.Ordinal);
        var missing = referenced.Where(item => !mappingByInstance.ContainsKey(item)).ToArray();
        return new MappingAudit(missing, duplicateInstances, duplicateGuids, invalid);
    }

    private static bool RequestMappingsCoherent(GameSnapshotDto snapshot, DiagnosticReportRequestDto request)
    {
        var referenced = ReferencedPhysicalCardInstanceIds(snapshot);
        if (request.PhysicalMappings is not null) return AuditPhysicalMappings(referenced, request.PhysicalMappings).IsCoherent;
        if (request.MappedCardInstanceIds is null) return false;
        var mapped = request.MappedCardInstanceIds.ToHashSet(StringComparer.Ordinal);
        return referenced.All(mapped.Contains);
    }

    private static bool RequestHasNoRepairWork(DiagnosticReportRequestDto request)
    {
        var drain = request.EventDrainDiagnostics;
        if (drain is null) return true;
        return drain.QueueLength == 0
            && drain.PhysicalLibraryQueuesIdle
            && !drain.AnimationRunning
            && !drain.EventRequestInFlight
            && !drain.EventPollScheduled
            && !drain.SnapshotReconcilePending
            && !drain.SnapshotReconcileInFlight
            && (drain.PhysicalQueues is null || drain.PhysicalQueues.Values.All(queue =>
                !queue.LibraryExtractionActive
                && queue.LibraryExtractionLength == 0
                && !queue.MulliganInsertionActive
                && queue.MulliganInsertionLength == 0));
    }

    private static bool StatusLooksTerminal(string? status)
    {
        var value = status ?? string.Empty;
        return value.Contains("SYNCHRONIZATION STOPPED", StringComparison.OrdinalIgnoreCase)
            || value.Contains("TERMINAL_RECOVERY_ERROR", StringComparison.OrdinalIgnoreCase)
            || value.Contains("terminal_recovery_error", StringComparison.OrdinalIgnoreCase);
    }

    private static bool CursorMissingOrEquals(long? cursor, long? expected) =>
        cursor is null || expected is null || cursor.Value == expected.Value;

    private static DiagnosticSelfTestCheck Check(string id, string severity, string status, string message, Dictionary<string, object?>? evidence = null) =>
        new(id, severity, status, message, evidence);
}
