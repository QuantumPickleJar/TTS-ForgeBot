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
    string? Keyword = null);

public sealed record EventBatchDto(
    long RequestedAfterSequence,
    long OldestAvailableSequence,
    long LatestSequence,
    bool HasGap,
    IReadOnlyList<AuthoritativeEventDto> Events);
