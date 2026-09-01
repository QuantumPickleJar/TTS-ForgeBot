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
            CheckEventSequence(eventBatch),
            CheckTtsNotAhead(eventBatch, request),
            CheckTtsBehind(eventBatch, request),
            CheckSnapshot(snapshot),
            CheckCardMappings(snapshot, request)
        };
        return new DiagnosticSelfTestResult(checks);
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
        // Cards still contained in an opaque Forge/TTS library Deck do not
        // have distinct loose TTS embodiments. Requiring their instance IDs
        // here turns a normal early-turn snapshot into a false mapping alarm.
        var snapshotCards = snapshot.Seats
            .SelectMany(seat => seat.Zones)
            .Where(zone => !string.Equals(zone.Name, "library", StringComparison.OrdinalIgnoreCase))
            .SelectMany(zone => zone.Cards)
            .Where(card => !card.IsVirtual
                && !string.Equals(card.MaterializationPolicy, "virtual", StringComparison.OrdinalIgnoreCase)
                && !string.Equals(card.MaterializationPolicy, "virtual-stack", StringComparison.OrdinalIgnoreCase));
        var snapshotStackCards = snapshot.Stack
            .Where(card => !card.IsVirtual
                && !string.Equals(card.MaterializationPolicy, "virtual", StringComparison.OrdinalIgnoreCase)
                && !string.Equals(card.MaterializationPolicy, "virtual-stack", StringComparison.OrdinalIgnoreCase));
        var combatCards = snapshot.Combat?.Attacks
            .SelectMany(item => new[] { item.AttackerCardInstanceId }.Concat(item.BlockerCardInstanceIds))
            ?? [];
        var referenced = snapshotCards
            .Concat(snapshotStackCards)
            .Select(card => card.CardInstanceId)
            .Concat(combatCards)
            .Distinct(StringComparer.Ordinal)
            .ToArray();
        if (request.PhysicalMappings is not null)
        {
            var mappings = request.PhysicalMappings;
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
            if (duplicateInstances.Length > 0 || duplicateGuids.Length > 0 || invalid.Length > 0 || missing.Length > 0)
            {
                return Check("snapshot_card_mappings", "error", "fail",
                    "Authoritative physical mappings are not live and unique.",
                    new Dictionary<string, object?>
                    {
                        ["missingCardInstanceIds"] = missing,
                        ["duplicateCardInstanceIds"] = duplicateInstances,
                        ["duplicateGuids"] = duplicateGuids,
                        ["invalidMappings"] = invalid,
                        ["referencedCount"] = referenced.Length
                    });
            }
            return Check("snapshot_card_mappings", "info", "pass",
                "Authoritative physical mappings are live, unique, and identity-consistent.",
                new Dictionary<string, object?> { ["referencedCount"] = referenced.Length, ["mappingCount"] = mappings.Count });
        }
        if (request.MappedCardInstanceIds is null) return Check("snapshot_card_mappings", "info", "unavailable", "TTS did not supply card instance mapping information.");
        var mapped = request.MappedCardInstanceIds.ToHashSet(StringComparer.Ordinal);
        var missingLegacy = referenced.Where(item => !mapped.Contains(item)).ToArray();
        return missingLegacy.Length == 0
            ? Check("snapshot_card_mappings", "info", "pass", "Snapshot combat card instances are represented in TTS mapping information.", new Dictionary<string, object?> { ["referencedCount"] = referenced.Length })
            : Check("snapshot_card_mappings", "error", "fail", "Authoritative combat card instances are missing from TTS mapping information.", new Dictionary<string, object?> { ["missingCardInstanceIds"] = missingLegacy, ["referencedCount"] = referenced.Length });
    }

    private static DiagnosticSelfTestCheck Check(string id, string severity, string status, string message, Dictionary<string, object?>? evidence = null) =>
        new(id, severity, status, message, evidence);
}
