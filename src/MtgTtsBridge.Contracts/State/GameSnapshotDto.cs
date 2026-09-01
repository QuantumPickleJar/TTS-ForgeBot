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
    IReadOnlyList<GameCardSnapshotDto> Stack,
    // Bridge event-stream cursor captured with this snapshot. ForgeSequence is
    // producer-local; EventCursor is the only safe ordering comparison for TTS.
    long EventCursor = 0,
    // Player-level designation identity is Forge truth. This supports a
    // table-native Monarch helper without implementing Monarch in Lua.
    string? MonarchSeatId = null,
    GameCombatSnapshotDto? Combat = null,
    GameResultDto? Result = null,
    // These are continuous Forge state, not UI-derived values. Keeping them
    // in snapshots lets reconciliation recover the turn pipeline even when a
    // diagnostic line or transient phase event is missed.
    int? TurnNumber = null,
    string? ActiveSeatId = null,
    string? PrioritySeatId = null,
    string? Phase = null);

public sealed record GameCombatSnapshotDto(IReadOnlyList<GameCombatAttackSnapshotDto> Attacks);
public sealed record GameCombatAttackSnapshotDto(string AttackerCardInstanceId, string? DefenderSeatId, int? DefenderForgeObjectId, IReadOnlyList<string> BlockerCardInstanceIds);

public sealed record GameResultDto(
    IReadOnlyList<string> WinnerSeatIds,
    IReadOnlyList<string> LoserSeatIds,
    string? Reason);

public sealed record GameSeatSnapshotDto(
    string SeatId,
    int ForgePlayerId,
    string DisplayName,
    int Life,
    int Poison,
    IReadOnlyDictionary<string, int> Counters,
    IReadOnlyList<GameZoneSnapshotDto> Zones,
    IReadOnlyDictionary<string, int>? ManaPool = null,
    int Speed = 0,
    IReadOnlyList<string>? Designations = null);

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
    IReadOnlyList<string> Keywords,
    int? NetPower = null,
    int? NetToughness = null,
    // Current characteristics are emitted by Forge, never calculated by TTS.
    int? CurrentPower = null,
    int? CurrentToughness = null,
    IReadOnlyList<string>? CurrentTypes = null)
{
    // U3 identity is deliberately separate from the physical TTS mapping.
    // CardInstanceId remains the stable bridge key for backwards compatibility;
    // these fields describe the authoritative Forge object and its provenance.
    public string AuthoritativeObjectId { get; init; } = CardInstanceId;
    public string? OriginObjectId { get; init; }
    public string? CopySourceObjectId { get; init; }
    public string ObjectKind { get; init; } = "physical-original";
    public bool IsCopy { get; init; }
    public bool IsVirtual { get; init; }
    public string? MaterializationPolicy { get; init; }
    /// <summary>Forge-event-derived physical row hint; never inferred from card text.</summary>
    public string? BattlefieldKind { get; init; }
    // Card-level designation data is Forge truth, not a counter or keyword.
    public IReadOnlyList<string> CardDesignations { get; init; } = [];
    // Forge-created tokens are not printed deck inventory and must not use the
    // ordinary library-card materialization fallback in TTS.
    public bool IsToken { get; init; }
    /// <summary>
    /// Complete Forge-authoritative current characteristics. When present, provides
    /// full structured type-line, mana cost/value, colors, loyalty, defense, etc.
    /// Flat fields above are preserved for backward compatibility.
    /// </summary>
    public CurrentCharacteristicsDto? Characteristics { get; init; }
}
