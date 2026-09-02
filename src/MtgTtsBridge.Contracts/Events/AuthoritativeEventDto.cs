namespace MtgTtsBridge.Contracts.Events;

public sealed record AuthoritativeEventDto(
    long Sequence,
    string EventId,
    string Kind,
    string? SeatId,
    string? CardName,
    int? ForgeObjectId,
    string? CardInstanceId,
    string? SourceZone,
    string? DestinationZone,
    string Summary,
    DateTimeOffset OccurredAtUtc,
    int? LifeTotal = null,
    int? PoisonCounters = null,
    string? CounterType = null,
    int? CounterValue = null,
    string? Keyword = null,
    bool? Tapped = null,
    bool ContainsHiddenIdentity = false,
    IReadOnlyDictionary<string, int>? ManaPool = null,
    string? Phase = null,
    int? TurnNumber = null,
    long? ForgeSequence = null,
    string? ActiveSeatId = null,
    string? PrioritySeatId = null,
    int? NetPower = null,
    int? NetToughness = null,
    int? CurrentPower = null,
    int? CurrentToughness = null,
    IReadOnlyList<string>? CurrentTypes = null,
    string? CurrentCardName = null,
    string? OwnerSeatId = null,
    string? ControllerSeatId = null,
    bool? FaceDown = null,
    bool? PhasedOut = null,
    int? Speed = null,
    IReadOnlyList<string>? Designations = null,
    string? MonarchSeatId = null,
    IReadOnlyList<string>? WinnerSeatIds = null,
    IReadOnlyList<string>? LoserSeatIds = null,
    string? GameEndReason = null,
    IReadOnlyDictionary<string, int>? Counters = null,
    string? BattlefieldKind = null,
    string? AuthoritativeObjectId = null,
    string? OriginObjectId = null,
    string? CopySourceObjectId = null,
    string? ObjectKind = null,
    bool IsCopy = false,
    bool IsVirtual = false,
    string? MaterializationPolicy = null,
    // A Forge-created token has no printed-deck embodiment. This flag is
    // producer truth and permits TTS to select its token materializer without
    // inferring from a display name or an unmapped battlefield object.
    bool IsToken = false,
    RevealPresentationDto? RevealPresentation = null)
{
    /// <summary>
    /// Complete current characteristics change when present. Provides structured
    /// type-line, mana cost/value, colors, loyalty, defense for characteristic
    /// change events. Flat fields above preserved for backward compatibility.
    /// </summary>
    public MtgTtsBridge.Contracts.State.CurrentCharacteristicsDto? Characteristics { get; init; }
};

public sealed record EventBatchDto(
    long RequestedAfterSequence,
    long OldestAvailableSequence,
    long LatestSequence,
    bool HasGap,
    IReadOnlyList<AuthoritativeEventDto> Events);
