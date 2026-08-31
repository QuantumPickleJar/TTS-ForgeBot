using System.Collections.Generic;
using System.Text;
using System.Text.Json;

namespace MtgTtsBridge.Forge;

/// <summary>Removes framed private state records before ordinary text reaches the TUI parsers.</summary>
public sealed class ForgeStructuredOutputParser
{
    public const string Sentinel = "@@FORGE_BRIDGE_STATE@@";

    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = true,
    };

    private readonly StringBuilder _buffer = new();

    public void Reset() => _buffer.Clear();

    public ForgeStructuredOutputResult Append(string chunk)
    {
        _buffer.Append(chunk);
        var tui = new StringBuilder();
        var snapshots = new List<ForgeStructuredSnapshot>();

        while (true)
        {
            var text = _buffer.ToString();
            var newline = text.IndexOf('\n');
            if (newline < 0) break;

            var line = text[..newline].TrimEnd('\r');
            _buffer.Remove(0, newline + 1);
            if (line.StartsWith(Sentinel, StringComparison.Ordinal))
            {
                snapshots.Add(ParseFrame(line[Sentinel.Length..]));
            }
            else
            {
                tui.Append(line).Append('\n');
            }
        }

        var tail = _buffer.ToString();
        if (tail.Length > 0 && !tail.StartsWith(Sentinel, StringComparison.Ordinal)
            && !Sentinel.StartsWith(tail, StringComparison.Ordinal))
        {
            tui.Append(tail);
            _buffer.Clear();
        }

        return new ForgeStructuredOutputResult(tui.ToString(), snapshots);
    }

    private static ForgeStructuredSnapshot ParseFrame(string json)
    {
        try
        {
            var snapshot = JsonSerializer.Deserialize<ForgeStructuredSnapshot>(json, JsonOptions)
                ?? throw new ForgeStructuredFrameException("Forge emitted an empty structured state frame.");
            if (snapshot.Version != 1 || !string.Equals(snapshot.Type, "snapshot", StringComparison.Ordinal))
            {
                throw new ForgeStructuredFrameException(
                    $"Unsupported Forge structured frame version/type: {snapshot.Version}/{snapshot.Type}.");
            }
            return snapshot;
        }
        catch (ForgeStructuredFrameException)
        {
            throw;
        }
        catch (JsonException ex)
        {
            throw new ForgeStructuredFrameException(BuildMalformedJsonMessage(ex), ex);
        }
    }

    private static string BuildMalformedJsonMessage(JsonException ex)
    {
        var metadata = new List<string>();
        if (!string.IsNullOrWhiteSpace(ex.Path))
        {
            metadata.Add($"path={ex.Path}");
        }
        if (ex.LineNumber.HasValue)
        {
            metadata.Add($"line={ex.LineNumber.Value}");
        }
        if (ex.BytePositionInLine.HasValue)
        {
            metadata.Add($"byte={ex.BytePositionInLine.Value}");
        }

        return metadata.Count == 0
            ? "Forge emitted malformed structured state JSON."
            : $"Forge emitted malformed structured state JSON ({string.Join(", ", metadata)}).";
    }
}

public sealed record ForgeStructuredOutputResult(
    string TuiText,
    IReadOnlyList<ForgeStructuredSnapshot> Snapshots);

public sealed record ForgeStructuredSnapshot(
    int Version,
    string Type,
    long Sequence,
    string Reason,
    IReadOnlyList<ForgeStructuredPlayer> Players,
    IReadOnlyList<ForgeStructuredCard> Stack,
    string? MonarchSeatId = null,
    ForgeStructuredCombat? Combat = null,
    ForgeStructuredGameEnded? GameEnded = null);

public sealed record ForgeStructuredCombat(IReadOnlyList<ForgeStructuredCombatAttack> Attacks);
public sealed record ForgeStructuredCombatAttack(int AttackerForgeObjectId, string? DefenderSeatId, int? DefenderForgeObjectId, IReadOnlyList<int> BlockerForgeObjectIds);

public sealed record ForgeStructuredGameEnded(
    IReadOnlyList<string> WinnerSeatIds,
    IReadOnlyList<string> LoserSeatIds,
    string? Reason);

public sealed record ForgeStructuredPlayer(
    string SeatId,
    int ForgePlayerId,
    string DisplayName,
    int Life,
    int Poison,
    IReadOnlyDictionary<string, int> Counters,
    IReadOnlyList<ForgeStructuredZone> Zones,
    IReadOnlyDictionary<string, int>? ManaPool = null,
    int Speed = 0,
    IReadOnlyList<string>? Designations = null);

public sealed record ForgeStructuredZone(string Name, IReadOnlyList<ForgeStructuredCard> Cards);

public sealed record ForgeStructuredCard(
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
    int? CurrentPower = null,
    int? CurrentToughness = null,
    IReadOnlyList<string>? CurrentTypes = null,
    ForgeStructuredCharacteristics? Characteristics = null,
    IReadOnlyList<string>? CardDesignations = null,
    bool IsToken = false,
    string? AuthoritativeObjectId = null,
    string? OriginObjectId = null,
    string? CopySourceObjectId = null,
    string ObjectKind = "physical-original",
    bool IsCopy = false,
    bool IsVirtual = false,
    string? MaterializationPolicy = null);

public sealed record ForgeStructuredCharacteristics(
    string CurrentCardName,
    string? CurrentManaCost = null,
    int? CurrentManaValue = null,
    IReadOnlyList<string>? CurrentColors = null,
    IReadOnlyList<string>? CurrentSupertypes = null,
    IReadOnlyList<string>? CurrentCardTypes = null,
    IReadOnlyList<string>? CurrentSubtypes = null,
    string? CurrentPower = null,
    string? CurrentToughness = null,
    string? CurrentLoyalty = null,
    string? CurrentDefense = null,
    IReadOnlyList<string>? CurrentKeywords = null);

public sealed class ForgeStructuredFrameException : InvalidOperationException
{
    public ForgeStructuredFrameException(string message) : base(message) { }
    public ForgeStructuredFrameException(string message, Exception innerException) : base(message, innerException) { }
}
