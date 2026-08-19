using System.Text;
using System.Text.RegularExpressions;

namespace MtgTtsBridge.Forge;

/// <summary>Parses only authoritative event lines actually emitted by the tested Forge headless ref.</summary>
public sealed partial class ForgeTuiEventParser
{
    private readonly StringBuilder _lineBuffer = new();
    private readonly IReadOnlyDictionary<string, string> _playerSeats;
    private readonly Dictionary<int, (string? SeatId, string CardName)> _knownInstances = [];
    private readonly List<(string? SeatId, string CardName)> _pendingCasts = [];

    public ForgeTuiEventParser(IReadOnlyDictionary<string, string> playerSeats) => _playerSeats = playerSeats;

    public void Reset()
    {
        _lineBuffer.Clear();
        _knownInstances.Clear();
        _pendingCasts.Clear();
    }

    public IReadOnlyList<ForgeTuiRawEvent> Append(string chunk)
    {
        _lineBuffer.Append(AnsiEscapeRegex().Replace(chunk, string.Empty));
        var events = new List<ForgeTuiRawEvent>();

        while (true)
        {
            var text = _lineBuffer.ToString();
            var newline = text.IndexOf('\n');
            if (newline < 0) break;

            var line = text[..newline].TrimEnd('\r');
            _lineBuffer.Remove(0, newline + 1);
            var parsed = ParseLine(line);
            if (parsed.Count > 0) events.AddRange(parsed);
        }

        return events;
    }

    private IReadOnlyList<ForgeTuiRawEvent> ParseLine(string line)
    {
        var match = TurnRegex().Match(line);
        if (match.Success)
        {
            return [Create("turn_changed", match.Groups["player"].Value, null, null, null, null, line)];
        }

        match = PhaseRegex().Match(line);
        if (match.Success)
        {
            return [Create("phase_changed", match.Groups["player"].Value, null, null, null, null, line)];
        }

        match = LandRegex().Match(line);
        if (match.Success)
        {
            var player = match.Groups["player"].Value;
            var card = match.Groups["card"].Value;
            var id = int.Parse(match.Groups["id"].Value, System.Globalization.CultureInfo.InvariantCulture);
            _knownInstances[id] = (ResolveSeat(player), card);
            return [Create("land_played", player, card, id, "hand", "battlefield", line)];
        }

        match = ManaRegex().Match(line);
        if (match.Success)
        {
            var id = int.Parse(match.Groups["id"].Value, System.Globalization.CultureInfo.InvariantCulture);
            _knownInstances.TryGetValue(id, out var known);
            return [new ForgeTuiRawEvent("mana_ability_used", known.SeatId, match.Groups["card"].Value, id, null, null, line)];
        }

        match = CastRegex().Match(line);
        if (match.Success)
        {
            var player = match.Groups["player"].Value;
            var card = match.Groups["card"].Value;
            _pendingCasts.Add((ResolveSeat(player), card));
            return [Create("spell_cast", player, card, null, "hand", "stack", line)];
        }

        match = ResolveRegex().Match(line);
        if (match.Success)
        {
            var card = match.Groups["card"].Value;
            var details = match.Groups["details"].Value;
            var pendingIndex = _pendingCasts.FindLastIndex(item => string.Equals(item.CardName, card, StringComparison.OrdinalIgnoreCase));
            string? seatId = null;
            if (pendingIndex >= 0)
            {
                seatId = _pendingCasts[pendingIndex].SeatId;
                _pendingCasts.RemoveAt(pendingIndex);
            }
            var destination = details.StartsWith("Creature ", StringComparison.Ordinal) ? "battlefield" : null;
            return [new ForgeTuiRawEvent("spell_resolved", seatId, card, null, "stack", destination, line)];
        }

        match = CombatRegex().Match(line);
        if (match.Success)
        {
            var player = match.Groups["player"].Value;
            var seatId = ResolveSeat(player);
            var result = new List<ForgeTuiRawEvent>();
            foreach (Match attacker in AttackerRegex().Matches(match.Groups["attackers"].Value))
            {
                var card = attacker.Groups["card"].Value.Trim();
                var id = int.Parse(attacker.Groups["id"].Value, System.Globalization.CultureInfo.InvariantCulture);
                _knownInstances[id] = (seatId, card);
                result.Add(new ForgeTuiRawEvent("attack_declared", seatId, card, id, "battlefield", "battlefield", line));
            }
            return result;
        }

        return [];
    }

    private ForgeTuiRawEvent Create(
        string kind,
        string playerName,
        string? cardName,
        int? forgeObjectId,
        string? sourceZone,
        string? destinationZone,
        string summary) =>
        new(kind, ResolveSeat(playerName), cardName, forgeObjectId, sourceZone, destinationZone, summary);

    private string? ResolveSeat(string playerName) =>
        _playerSeats.TryGetValue(playerName, out var seatId) ? seatId : null;

    [GeneratedRegex(@"^\+\+\+ Turn: Turn \d+ \((?<player>.+)\)$", RegexOptions.CultureInvariant)]
    private static partial Regex TurnRegex();

    [GeneratedRegex(@"^\+\+\+ Phase: (?<player>.+?)'s .+$", RegexOptions.CultureInvariant)]
    private static partial Regex PhaseRegex();

    [GeneratedRegex(@"^\+\+\+ Land: (?<player>.+?) played (?<card>.+) \((?<id>\d+)\)$", RegexOptions.CultureInvariant)]
    private static partial Regex LandRegex();

    [GeneratedRegex(@"^\+\+\+ Mana: (?<card>.+) \((?<id>\d+)\) - .+$", RegexOptions.CultureInvariant)]
    private static partial Regex ManaRegex();

    [GeneratedRegex(@"^\+\+\+ Add To Stack: (?<player>.+?) cast (?<card>.+)$", RegexOptions.CultureInvariant)]
    private static partial Regex CastRegex();

    [GeneratedRegex(@"^\+\+\+ Resolve Stack: (?<card>.+?) - (?<details>.+)$", RegexOptions.CultureInvariant)]
    private static partial Regex ResolveRegex();

    [GeneratedRegex(@"^\+\+\+ Combat: (?<player>.+?) assigned (?<attackers>.+) to attack .+\.$", RegexOptions.CultureInvariant)]
    private static partial Regex CombatRegex();

    [GeneratedRegex(@"(?<card>.+?) \((?<id>\d+)\)(?: and |, |$)", RegexOptions.CultureInvariant)]
    private static partial Regex AttackerRegex();

    [GeneratedRegex("\\x1B\\[[0-?]*[ -/]*[@-~]", RegexOptions.CultureInvariant)]
    private static partial Regex AnsiEscapeRegex();
}

public sealed record ForgeTuiRawEvent(
    string Kind,
    string? SeatId,
    string? CardName,
    int? ForgeObjectId,
    string? SourceZone,
    string? DestinationZone,
    string Summary);
