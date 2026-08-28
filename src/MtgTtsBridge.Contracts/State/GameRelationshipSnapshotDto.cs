namespace MtgTtsBridge.Contracts.State;

/// <summary>
/// A Forge-authoritative relationship between exact game identities.  A
/// relationship is presentation-neutral: the bridge never infers it from
/// names, zones, transforms, or physical overlap.
/// </summary>
public sealed record GameRelationshipSnapshotDto(
    string RelationshipId,
    string Kind,
    string? SourceCardInstanceId = null,
    string? TargetCardInstanceId = null,
    string? TargetSeatId = null,
    string? GroupId = null,
    string? Role = null,
    int? Order = null);

/// <summary>Deterministic, snapshot-reconstructible relationship collection.</summary>
public static class GameRelationshipGraph
{
    public static IReadOnlyList<GameRelationshipSnapshotDto> Normalize(
        IEnumerable<GameRelationshipSnapshotDto>? relationships)
    {
        ArgumentNullException.ThrowIfNull(relationships);
        return relationships
            .Select(NormalizeOne)
            .OrderBy(item => item.RelationshipId, StringComparer.Ordinal)
            .ThenBy(item => item.Kind, StringComparer.Ordinal)
            .ThenBy(item => item.Order ?? int.MaxValue)
            .ThenBy(item => item.SourceCardInstanceId ?? string.Empty, StringComparer.Ordinal)
            .ThenBy(item => item.TargetCardInstanceId ?? string.Empty, StringComparer.Ordinal)
            .ThenBy(item => item.TargetSeatId ?? string.Empty, StringComparer.Ordinal)
            .ToArray();
    }

    private static GameRelationshipSnapshotDto NormalizeOne(GameRelationshipSnapshotDto relation)
    {
        ArgumentNullException.ThrowIfNull(relation);
        if (string.IsNullOrWhiteSpace(relation.RelationshipId))
            throw new ArgumentException("RelationshipId is required.", nameof(relation));
        if (string.IsNullOrWhiteSpace(relation.Kind))
            throw new ArgumentException("Relationship kind is required.", nameof(relation));

        return relation with
        {
            RelationshipId = relation.RelationshipId.Trim(),
            Kind = relation.Kind.Trim().ToLowerInvariant(),
            SourceCardInstanceId = TrimOrNull(relation.SourceCardInstanceId),
            TargetCardInstanceId = TrimOrNull(relation.TargetCardInstanceId),
            TargetSeatId = TrimOrNull(relation.TargetSeatId),
            GroupId = TrimOrNull(relation.GroupId),
            Role = TrimOrNull(relation.Role)
        };
    }

    private static string? TrimOrNull(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
