using MtgTtsBridge.Contracts.State;

namespace MtgTtsBridge.Forge;

/// <summary>Raised when one authoritative snapshot locates a Forge card identity more than once.</summary>
public sealed class ForgeStructuredDuplicateCardInstanceException : InvalidOperationException
{
    public ForgeStructuredDuplicateCardInstanceException(string sessionId, long forgeSequence, string cardInstanceId, IReadOnlyList<string> locations)
        : base($"Duplicate structured CardInstanceId session={sessionId} forgeSequence={forgeSequence} cardInstanceId={cardInstanceId} locations={string.Join("; ", locations)}")
    {
        SessionId = sessionId;
        ForgeSequence = forgeSequence;
        CardInstanceId = cardInstanceId;
        Locations = locations;
    }

    public string SessionId { get; }
    public long ForgeSequence { get; }
    public string CardInstanceId { get; }
    public IReadOnlyList<string> Locations { get; }
}

/// <summary>Diffs authoritative snapshots into bounded embodiment changes; it never derives game rules.</summary>
public sealed class ForgeStructuredStateReconciler
{
    private bool _hasBaseline;

    public GameSnapshotDto? Current { get; private set; }

    public void Reset()
    {
        Current = null;
        _hasBaseline = false;
    }

    public IReadOnlyList<ForgeTuiRawEvent> Apply(string sessionId, ForgeStructuredSnapshot source)
    {
        if (Current is not null && source.Sequence <= Current.ForgeSequence)
        {
            throw new ForgeStructuredFrameException(
                $"Forge structured sequence did not advance: {source.Sequence} after {Current.ForgeSequence}.");
        }

        var next = ConvertSnapshot(sessionId, source);
        // Validate even the initial baseline. Otherwise a malformed startup
        // snapshot could be accepted and only fail later during its first
        // diff, after contaminating the authoritative current state.
        _ = Flatten(sessionId, next);
        if (!_hasBaseline || Current is null)
        {
            Current = next;
            _hasBaseline = true;
            return [];
        }

        var events = Diff(sessionId, Current, next);
        Current = next;
        // Preserve the producer-local snapshot sequence on every event. It is
        // diagnostic metadata only; TTS orders physical work by the bridge's
        // monotonic event cursor, not by this Forge-local value.
        return events.Select(@event => @event with { ForgeSequence = next.ForgeSequence }).ToArray();
    }

    private static GameSnapshotDto ConvertSnapshot(string sessionId, ForgeStructuredSnapshot source)
    {
        GameCardSnapshotDto ConvertCard(ForgeStructuredCard card) => new(
            CardInstanceId: $"forge:{sessionId}:{card.ForgeCardId}",
            ForgeCardId: card.ForgeCardId,
            CardName: card.CardName,
            CurrentCardName: card.CurrentCardName,
            Zone: card.Zone,
            ZonePosition: card.ZonePosition,
            OwnerSeatId: card.OwnerSeatId,
            ControllerSeatId: card.ControllerSeatId,
            Tapped: card.Tapped,
            FaceDown: card.FaceDown,
            PhasedOut: card.PhasedOut,
            Counters: new Dictionary<string, int>(card.Counters, StringComparer.OrdinalIgnoreCase),
            Keywords: card.Keywords
                .Select(NormalizeKeyword)
                .Where(keyword => !string.IsNullOrWhiteSpace(keyword))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToArray(),
            NetPower: card.NetPower,
            NetToughness: card.NetToughness,
            // NetPower/NetToughness are retained as legacy transport fields,
            // but they are deliberately zero for non-creatures. Never promote
            // those zeros into nullable current characteristics or TTS will
            // render lands and other non-creatures as 0/0. Older structured
            // feeds may omit current characteristics for creatures, so retain
            // the compatibility fallback only when the authoritative type
            // list explicitly identifies a creature.
            CurrentPower: card.CurrentPower ?? (HasCreatureType(card) ? card.NetPower : null),
            CurrentToughness: card.CurrentToughness ?? (HasCreatureType(card) ? card.NetToughness : null),
            CurrentTypes: (card.CurrentTypes ?? [])
                .Select(NormalizeType)
                .Where(type => !string.IsNullOrWhiteSpace(type))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .OrderBy(type => type, StringComparer.Ordinal)
                .ToArray())
        {
            BattlefieldKind = string.Equals(card.Zone, "battlefield", StringComparison.OrdinalIgnoreCase)
                ? (HasLandType(card) ? "land" : "creature")
                : null,
            CardDesignations = (card.CardDesignations ?? [])
                .Select(NormalizeDesignation)
                .Where(designation => !string.IsNullOrWhiteSpace(designation))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .OrderBy(designation => designation, StringComparer.Ordinal)
                .ToArray(),
            IsToken = card.IsToken
        };

        static bool HasCreatureType(ForgeStructuredCard card) =>
            card.CurrentTypes?.Any(type => string.Equals(type, "creature", StringComparison.OrdinalIgnoreCase)) == true;

        static bool HasLandType(ForgeStructuredCard card) =>
            card.CurrentTypes?.Any(type => string.Equals(type, "land", StringComparison.OrdinalIgnoreCase)) == true;

        var seats = source.Players.Select(player => new GameSeatSnapshotDto(
            player.SeatId,
            player.ForgePlayerId,
            player.DisplayName,
            player.Life,
            player.Poison,
            new Dictionary<string, int>(player.Counters, StringComparer.OrdinalIgnoreCase),
            player.Zones.Select(zone => new GameZoneSnapshotDto(
                zone.Name,
                zone.Cards.Select(ConvertCard).ToArray())).ToArray(),
            new Dictionary<string, int>(player.ManaPool ?? EmptyManaPool, StringComparer.OrdinalIgnoreCase),
            player.Speed,
            (player.Designations ?? [])
                .Select(NormalizeDesignation)
                .Where(designation => !string.IsNullOrWhiteSpace(designation))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .OrderBy(designation => designation, StringComparer.Ordinal)
                .ToArray())).ToArray();

        var combat = source.Combat is null ? null : new GameCombatSnapshotDto(source.Combat.Attacks.Select(attack => new GameCombatAttackSnapshotDto(
            $"forge:{sessionId}:{attack.AttackerForgeObjectId}", attack.DefenderSeatId, attack.DefenderForgeObjectId,
            attack.BlockerForgeObjectIds.Select(id => $"forge:{sessionId}:{id}").ToArray())).ToArray());
        return new GameSnapshotDto(
            sessionId,
            source.Sequence,
            source.Reason,
            seats,
            source.Stack.Select(ConvertCard).ToArray(),
            MonarchSeatId: source.MonarchSeatId,
            Combat: combat,
            Result: source.GameEnded is null ? null : new GameResultDto(
                source.GameEnded.WinnerSeatIds,
                source.GameEnded.LoserSeatIds,
                source.GameEnded.Reason));
    }

    private static IReadOnlyList<ForgeTuiRawEvent> Diff(string sessionId, GameSnapshotDto previous, GameSnapshotDto next)
    {
        var events = new List<ForgeTuiRawEvent>();
        if (!CombatEqual(previous.Combat, next.Combat))
        {
            foreach (var attack in next.Combat?.Attacks ?? [])
            {
                var attacker = Flatten(sessionId, next).GetValueOrDefault(attack.AttackerCardInstanceId);
                if (attacker is not null) events.Add(new ForgeTuiRawEvent("attack_declared", attacker.ControllerSeatId ?? attacker.OwnerSeatId, attacker.CardName, attacker.ForgeCardId, "battlefield", "battlefield", "Authoritative combat assignment."));
                foreach (var blockerId in attack.BlockerCardInstanceIds)
                {
                    var blocker = Flatten(sessionId, next).GetValueOrDefault(blockerId);
                    if (blocker is not null) events.Add(new ForgeTuiRawEvent("block_declared", blocker.ControllerSeatId ?? blocker.OwnerSeatId, blocker.CardName, blocker.ForgeCardId, "battlefield", "battlefield", "Authoritative combat assignment."));
                }
            }
        }
        if (previous.Result is null && next.Result is not null)
        {
            events.Add(new ForgeTuiRawEvent(
                "game_ended", null, null, null, null, null,
                "Forge declared the game over.",
                WinnerSeatIds: next.Result.WinnerSeatIds,
                LoserSeatIds: next.Result.LoserSeatIds,
                GameEndReason: next.Result.Reason));
        }
        var beforeSeats = previous.Seats.ToDictionary(seat => seat.SeatId, StringComparer.Ordinal);
        foreach (var seat in next.Seats)
        {
            if (!beforeSeats.TryGetValue(seat.SeatId, out var oldSeat)
                || oldSeat.Life != seat.Life
                || oldSeat.Poison != seat.Poison
                || !DictionaryEqual(oldSeat.Counters, seat.Counters))
            {
                events.Add(new ForgeTuiRawEvent(
                    "player_state", seat.SeatId, null, null, null, null,
                    $"Authoritative player state changed for {seat.SeatId}.",
                    LifeTotal: seat.Life,
                    PoisonCounters: seat.Poison,
                    Counters: new Dictionary<string, int>(seat.Counters, StringComparer.OrdinalIgnoreCase),
                    Speed: seat.Speed));
            }

            if (beforeSeats.TryGetValue(seat.SeatId, out var beforeSeat)
                && !DictionaryEqual(beforeSeat.ManaPool ?? EmptyManaPool, seat.ManaPool ?? EmptyManaPool))
            {
                events.Add(new ForgeTuiRawEvent(
                    "mana_pool_changed", seat.SeatId, null, null, null, null,
                    $"Authoritative mana pool changed for {seat.SeatId}.",
                    ManaPool: seat.ManaPool));
            }

            if (beforeSeats.TryGetValue(seat.SeatId, out beforeSeat)
                && (beforeSeat.Speed != seat.Speed
                    || !SetEqual(beforeSeat.Designations, seat.Designations)
                    || !string.Equals(previous.MonarchSeatId, next.MonarchSeatId, StringComparison.Ordinal)))
            {
                events.Add(new ForgeTuiRawEvent(
                    "designation_changed", seat.SeatId, null, null, null, null,
                    $"Authoritative player designations changed for {seat.SeatId}.",
                    Speed: seat.Speed,
                    Designations: seat.Designations,
                    MonarchSeatId: next.MonarchSeatId));
            }
        }

        var beforeCards = Flatten(sessionId, previous);
        var afterCards = Flatten(sessionId, next);
        foreach (var (id, card) in afterCards.OrderBy(pair => pair.Value.ZonePosition))
        {
            beforeCards.TryGetValue(id, out var oldCard);
            var seatId = card.ControllerSeatId ?? card.OwnerSeatId;
            if (oldCard is null || !string.Equals(oldCard.Zone, card.Zone, StringComparison.OrdinalIgnoreCase))
            {
                var sourceZone = oldCard?.Zone;
                var isDraw = string.Equals(sourceZone, "library", StringComparison.OrdinalIgnoreCase)
                    && string.Equals(card.Zone, "hand", StringComparison.OrdinalIgnoreCase);
                var containsHiddenIdentity = isDraw
                    || string.Equals(card.Zone, "library", StringComparison.OrdinalIgnoreCase)
                    || string.Equals(card.Zone, "hand", StringComparison.OrdinalIgnoreCase);
                events.Add(new ForgeTuiRawEvent(
                    isDraw ? "draw" : "card_moved",
                    seatId,
                    card.CardName,
                    card.ForgeCardId,
                    sourceZone,
                    card.Zone,
                    isDraw ? $"Authoritative draw for {seatId}." : $"Authoritative zone change for card {card.ForgeCardId}.",
                    ContainsHiddenIdentity: containsHiddenIdentity,
                    BattlefieldKind: string.Equals(card.Zone, "battlefield", StringComparison.OrdinalIgnoreCase)
                        ? (HasLandType(card.CurrentTypes) ? "land" : "creature")
                        : null));
            }

            if (oldCard is not null && oldCard.Tapped != card.Tapped)
            {
                events.Add(new ForgeTuiRawEvent(
                    "tap_changed", seatId, card.CardName, card.ForgeCardId,
                    card.Zone, card.Zone, $"Authoritative tap state is {card.Tapped}.",
                    Tapped: card.Tapped));
            }

            if (oldCard is not null
                && (!string.Equals(oldCard.ControllerSeatId, card.ControllerSeatId, StringComparison.Ordinal)
                    || !string.Equals(oldCard.OwnerSeatId, card.OwnerSeatId, StringComparison.Ordinal)))
            {
                events.Add(new ForgeTuiRawEvent(
                    "controller_changed", seatId, card.CardName, card.ForgeCardId,
                    card.Zone, card.Zone, "Authoritative owner/controller changed.",
                    OwnerSeatId: card.OwnerSeatId,
                    ControllerSeatId: card.ControllerSeatId));
            }

            if (oldCard is not null
                && (!string.Equals(oldCard.CurrentCardName, card.CurrentCardName, StringComparison.Ordinal)
                    || !SetEqual(oldCard.CurrentTypes, card.CurrentTypes)))
            {
                events.Add(new ForgeTuiRawEvent(
                    "characteristic_changed", seatId, card.CardName, card.ForgeCardId,
                    card.Zone, card.Zone, "Authoritative card characteristics changed.",
                    CurrentCardName: card.CurrentCardName,
                    CurrentTypes: card.CurrentTypes,
                    CurrentPower: card.CurrentPower,
                    CurrentToughness: card.CurrentToughness));
            }

            if (oldCard is not null && oldCard.FaceDown != card.FaceDown)
            {
                events.Add(new ForgeTuiRawEvent(
                    "face_changed", seatId, card.CardName, card.ForgeCardId,
                    card.Zone, card.Zone, "Authoritative face-down state changed.",
                    CurrentCardName: card.CurrentCardName,
                    FaceDown: card.FaceDown));
            }

            if (oldCard is not null && oldCard.PhasedOut != card.PhasedOut)
            {
                events.Add(new ForgeTuiRawEvent(
                    "phasing_changed", seatId, card.CardName, card.ForgeCardId,
                    card.Zone, card.Zone, "Authoritative phased state changed.",
                    PhasedOut: card.PhasedOut));
            }

            if (oldCard is not null
                && (oldCard.CurrentPower != card.CurrentPower || oldCard.CurrentToughness != card.CurrentToughness)
                && (card.CurrentPower is not null || card.CurrentToughness is not null))
            {
                events.Add(new ForgeTuiRawEvent(
                    "stats_changed", seatId, card.CardName, card.ForgeCardId,
                    card.Zone, card.Zone,
                    $"Authoritative characteristics are {card.CurrentPower}/{card.CurrentToughness}.",
                    NetPower: card.CurrentPower,
                    NetToughness: card.CurrentToughness,
                    CurrentPower: card.CurrentPower,
                    CurrentToughness: card.CurrentToughness));
            }

            var enteringBattlefield = oldCard is not null
                && !string.Equals(oldCard.Zone, "battlefield", StringComparison.OrdinalIgnoreCase)
                && string.Equals(card.Zone, "battlefield", StringComparison.OrdinalIgnoreCase);
            var isOrWasOnBattlefield = string.Equals(card.Zone, "battlefield", StringComparison.OrdinalIgnoreCase)
                || string.Equals(oldCard?.Zone, "battlefield", StringComparison.OrdinalIgnoreCase);
            foreach (var counter in isOrWasOnBattlefield ? UnionKeys(oldCard?.Counters, card.Counters) : [])
            {
                var oldValue = oldCard?.Counters.GetValueOrDefault(counter) ?? 0;
                var newValue = card.Counters.GetValueOrDefault(counter);
                if (oldValue != newValue || (enteringBattlefield && newValue != 0))
                {
                    events.Add(new ForgeTuiRawEvent(
                        "counter_changed", seatId, card.CardName, card.ForgeCardId,
                        card.Zone, card.Zone, $"Authoritative {counter} counter state is {newValue}.",
                        CounterType: counter,
                        CounterValue: newValue));
                }
            }

            var oldKeywords = oldCard?.Keywords.ToHashSet(StringComparer.OrdinalIgnoreCase)
                ?? new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var newKeywords = card.Keywords.ToHashSet(StringComparer.OrdinalIgnoreCase);
            foreach (var keyword in isOrWasOnBattlefield
                         ? newKeywords.Where(keyword => enteringBattlefield || !oldKeywords.Contains(keyword))
                         : [])
            {
                events.Add(new ForgeTuiRawEvent(
                    "keyword_added", seatId, card.CardName, card.ForgeCardId,
                    card.Zone, card.Zone, $"Authoritative keyword present: {keyword}.",
                    Keyword: keyword));
            }
            foreach (var keyword in isOrWasOnBattlefield
                         ? oldKeywords.Where(keyword => !newKeywords.Contains(keyword))
                         : [])
            {
                events.Add(new ForgeTuiRawEvent(
                    "keyword_removed", seatId, card.CardName, card.ForgeCardId,
                    card.Zone, card.Zone, $"Authoritative keyword absent: {keyword}.",
                    Keyword: keyword));
            }
        }

        return events;
    }

    private static Dictionary<string, GameCardSnapshotDto> Flatten(string sessionId, GameSnapshotDto snapshot)
    {
        var located = snapshot.Seats
            .SelectMany(seat => seat.Zones.SelectMany(zone => zone.Cards.Select(card => new
            {
                Card = card,
                Location = $"seat={seat.SeatId} zone={zone.Name} owner={card.OwnerSeatId ?? "none"} controller={card.ControllerSeatId ?? "none"} forgeCardId={card.ForgeCardId} card={card.CardName}"
            })))
            .Concat(snapshot.Stack.Select(card => new
            {
                Card = card,
                Location = $"stack owner={card.OwnerSeatId ?? "none"} controller={card.ControllerSeatId ?? "none"} forgeCardId={card.ForgeCardId} card={card.CardName}"
            }))
            .ToArray();

        var duplicate = located.GroupBy(item => item.Card.CardInstanceId, StringComparer.Ordinal)
            .FirstOrDefault(group => group.Count() > 1);
        if (duplicate is not null)
        {
            throw new ForgeStructuredDuplicateCardInstanceException(
                sessionId,
                snapshot.ForgeSequence,
                duplicate.Key,
                duplicate.Select(item => item.Location).ToArray());
        }

        return located.ToDictionary(item => item.Card.CardInstanceId, item => item.Card, StringComparer.Ordinal);
    }

    private static string NormalizeKeyword(string keyword)
    {
        var normalized = (keyword ?? string.Empty).Trim();
        var reminderIndex = normalized.IndexOf(" (", StringComparison.Ordinal);
        if (reminderIndex > 0)
        {
            normalized = normalized[..reminderIndex].TrimEnd();
        }
        return normalized;
    }

    private static string NormalizeType(string type) => (type ?? string.Empty).Trim().ToLowerInvariant();

    private static string NormalizeDesignation(string designation) => (designation ?? string.Empty).Trim().ToLowerInvariant();

    private static bool HasLandType(ForgeStructuredCard card) =>
        card.CurrentTypes?.Any(type => string.Equals(type, "land", StringComparison.OrdinalIgnoreCase)) == true;

    private static bool HasLandType(IReadOnlyList<string>? types) =>
        types?.Any(type => string.Equals(type, "land", StringComparison.OrdinalIgnoreCase)) == true;

    private static bool SetEqual(IReadOnlyList<string>? first, IReadOnlyList<string>? second) =>
        new HashSet<string>(first ?? [], StringComparer.OrdinalIgnoreCase)
            .SetEquals(second ?? []);

    private static bool CombatEqual(GameCombatSnapshotDto? first, GameCombatSnapshotDto? second) =>
        string.Join(";", first?.Attacks.Select(a => $"{a.AttackerCardInstanceId}|{a.DefenderSeatId}|{a.DefenderForgeObjectId}|{string.Join(',', a.BlockerCardInstanceIds)}") ?? []) ==
        string.Join(";", second?.Attacks.Select(a => $"{a.AttackerCardInstanceId}|{a.DefenderSeatId}|{a.DefenderForgeObjectId}|{string.Join(',', a.BlockerCardInstanceIds)}") ?? []);

    private static IEnumerable<string> UnionKeys(
        IReadOnlyDictionary<string, int>? first,
        IReadOnlyDictionary<string, int> second) =>
        (first?.Keys ?? []).Concat(second.Keys).Distinct(StringComparer.OrdinalIgnoreCase);

    private static bool DictionaryEqual(
        IReadOnlyDictionary<string, int> first,
        IReadOnlyDictionary<string, int> second) =>
        first.Count == second.Count && first.All(pair => second.TryGetValue(pair.Key, out var value) && value == pair.Value);

    private static readonly IReadOnlyDictionary<string, int> EmptyManaPool =
        new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
}
