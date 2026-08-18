namespace MtgTtsBridge.Contracts.Events;

public sealed record CommittedEventDto(
    string EventId,
    string Kind,
    string Summary,
    string SourceActionId,
    string? TargetIdentity,
    DateTimeOffset OccurredAtUtc);