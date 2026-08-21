using MtgTtsBridge.Contracts.State;

namespace MtgTtsBridge.Forge;

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
        if (!_hasBaseline || Current is null)
        {
            Current = next;
            _hasBaseline = true;
            return [];
        }

        var events = Diff(Current, next);
        Current = next;
        return events;
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
            Keywords: card.Keywords.Distinct(StringComparer.OrdinalIgnoreCase).ToArray());

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
            new Dictionary<string, int>(player.ManaPool ?? EmptyManaPool, StringComparer.OrdinalIgnoreCase))).ToArray();

        return new GameSnapshotDto(
            sessionId,
            source.Sequence,
            source.Reason,
            seats,
            source.Stack.Select(ConvertCard).ToArray());
    }

    private static IReadOnlyList<ForgeTuiRawEvent> Diff(GameSnapshotDto previous, GameSnapshotDto next)
    {
        var events = new List<ForgeTuiRawEvent>();
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
                    PoisonCounters: seat.Poison));
            }

            if (beforeSeats.TryGetValue(seat.SeatId, out var beforeSeat)
                && !DictionaryEqual(beforeSeat.ManaPool ?? EmptyManaPool, seat.ManaPool ?? EmptyManaPool))
            {
                events.Add(new ForgeTuiRawEvent(
                    "mana_pool_changed", seat.SeatId, null, null, null, null,
                    $"Authoritative mana pool changed for {seat.SeatId}.",
                    ManaPool: seat.ManaPool));
            }
        }

        var beforeCards = Flatten(previous);
        var afterCards = Flatten(next);
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
                    ContainsHiddenIdentity: containsHiddenIdentity));
            }

            if (oldCard is not null && oldCard.Tapped != card.Tapped)
            {
                events.Add(new ForgeTuiRawEvent(
                    "tap_changed", seatId, card.CardName, card.ForgeCardId,
                    card.Zone, card.Zone, $"Authoritative tap state is {card.Tapped}.",
                    Tapped: card.Tapped));
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

    private static Dictionary<string, GameCardSnapshotDto> Flatten(GameSnapshotDto snapshot) =>
        snapshot.Seats
            .SelectMany(seat => seat.Zones)
            .SelectMany(zone => zone.Cards)
            .Concat(snapshot.Stack)
            .ToDictionary(card => card.CardInstanceId, StringComparer.Ordinal);

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
