namespace MtgTtsBridge.Contracts.State;

/// <summary>
/// Bridge-internal authoritative state used to embody and reconcile a local TTS match.
/// It can contain hidden card identities and must not be written to ordinary logs.
/// </summary>
public sealed record GameSnapshotDto(
    string SessionId,
    long ForgeSequence,
    string Reason,
    IReadOnlyList<GameSeatSnapshotDto> Seats,
    IReadOnlyList<GameCardSnapshotDto> Stack);

public sealed record GameSeatSnapshotDto(
    string SeatId,
    int ForgePlayerId,
    string DisplayName,
    int Life,
    int Poison,
    IReadOnlyDictionary<string, int> Counters,
    IReadOnlyList<GameZoneSnapshotDto> Zones,
    IReadOnlyDictionary<string, int>? ManaPool = null);

public sealed record GameZoneSnapshotDto(
    string Name,
    IReadOnlyList<GameCardSnapshotDto> Cards);

public sealed record GameCardSnapshotDto(
    string CardInstanceId,
    int ForgeCardId,
    string CardName,
    string CurrentCardName,
    string Zone,
    int ZonePosition,
    string? OwnerSeatId,
    string? ControllerSeatId,
    bool Tapped,
    bool FaceDown,
    bool PhasedOut,
    IReadOnlyDictionary<string, int> Counters,
    IReadOnlyList<string> Keywords)
{
    /// <summary>Forge-event-derived physical row hint; never inferred from card text.</summary>
    public string? BattlefieldKind { get; init; }
}
