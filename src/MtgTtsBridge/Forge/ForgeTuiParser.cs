using System.Text;
using System.Text.RegularExpressions;
using MtgTtsBridge.Contracts.Actions;
using MtgTtsBridge.Contracts.State;

namespace MtgTtsBridge.Forge;

/// <summary>
/// Parses the numeric menu emitted by the rrn-headless-rebased TUI. It deliberately
/// recognizes only menus terminated by the TUI's "Enter choice" prompt.
/// </summary>
public sealed partial class ForgeTuiParser
{
    private readonly StringBuilder _buffer = new();
    private int _decisionNumber;

    public void Reset()
    {
        _buffer.Clear();
        _decisionNumber = 0;
    }

    public ForgeTuiParserResult Append(string chunk)
    {
        _buffer.Append(StripAnsi(chunk));
        var text = _buffer.ToString();
        var prompt = InputPromptRegex().Match(text);

        if (!prompt.Success)
        {
            return ForgeTuiParserResult.None;
        }

        var menuStart = Math.Max(text.LastIndexOf("What would you like to do?", StringComparison.Ordinal),
            text.LastIndexOf("Select a target:", StringComparison.Ordinal));

        if (menuStart < 0)
        {
            _buffer.Clear();
            return ForgeTuiParserResult.Error("unrecognized_tui_prompt", "Forge printed a numeric input prompt without a supported menu.");
        }

        var menu = text[menuStart..prompt.Index];
        var actions = MenuOptionRegex().Matches(menu)
            .Select(match => new ForgeTuiMenuOption(
                int.Parse(match.Groups["number"].Value, System.Globalization.CultureInfo.InvariantCulture),
                match.Groups["label"].Value.Trim()))
            .ToArray();

        _buffer.Remove(0, prompt.Index + prompt.Length);

        if (actions.Length == 0)
        {
            return ForgeTuiParserResult.Error("unrecognized_tui_menu", "Forge printed a supported menu header without numeric actions.");
        }

        _decisionNumber++;
        var kind = menuStart == text.LastIndexOf("Select a target:", StringComparison.Ordinal)
            ? "target_selection"
            : "main_priority";
        var decisionId = $"forge-tui-{_decisionNumber}";
        var bridgeActions = actions.Select(option => new LegalActionDto(
            ActionId: $"{decisionId}-choice-{option.Number}",
            Type: GetActionType(option.Label),
            DisplayName: option.Label,
            RequiresFollowup: false,
            CardIdentity: GetCardIdentity(option.Label),
            ObjectIdentity: null)).ToArray();

        return ForgeTuiParserResult.Decision(new ForgeTuiDecision(
            new DecisionDto(decisionId, kind, bridgeActions),
            actions.ToDictionary(option => $"{decisionId}-choice-{option.Number}", option => option.Number, StringComparer.Ordinal)));
    }

    private static string GetActionType(string label) => label switch
    {
        var value when value.StartsWith("Pass priority", StringComparison.OrdinalIgnoreCase) => "pass_yield",
        var value when value.StartsWith("Play land:", StringComparison.OrdinalIgnoreCase) => "play_land",
        var value when value.StartsWith("Cast ", StringComparison.OrdinalIgnoreCase) => "cast_spell",
        _ => "choose_option",
    };

    // CardIdentity is presentation identity only. Forge remains authoritative for
    // the card's rules; this extracts only the name Forge printed in the real menu.
    private static string? GetCardIdentity(string label)
    {
        var land = PlayLandRegex().Match(label);
        if (land.Success) return land.Groups["name"].Value.Trim();

        var spell = CastSpellRegex().Match(label);
        return spell.Success ? spell.Groups["name"].Value.Trim() : null;
    }

    private static string StripAnsi(string text) => AnsiEscapeRegex().Replace(text, string.Empty);

    [GeneratedRegex(@"Enter choice \(\d+-\d+(?:, or \?)?\):\s*", RegexOptions.CultureInvariant)]
    private static partial Regex InputPromptRegex();

    [GeneratedRegex(@"(?m)^\s*(?<number>\d+)\.\s+(?<label>.+?)\s*\r?$", RegexOptions.CultureInvariant)]
    private static partial Regex MenuOptionRegex();

    [GeneratedRegex(@"^Play land:\s*(?<name>.+)$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex PlayLandRegex();

    [GeneratedRegex(@"^Cast (?:creature|spell):\s*(?<name>.+?)(?:\s+\([^)]*\))?\s+-\s+.+$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex CastSpellRegex();

    [GeneratedRegex("\\x1B\\[[0-?]*[ -/]*[@-~]", RegexOptions.CultureInvariant)]
    private static partial Regex AnsiEscapeRegex();
}

public sealed record ForgeTuiMenuOption(int Number, string Label);

public sealed record ForgeTuiDecision(DecisionDto Decision, IReadOnlyDictionary<string, int> Inputs);

public sealed record ForgeTuiParserResult(ForgeTuiDecision? ParsedDecision, string? ErrorCode, string? ErrorMessage)
{
    public static ForgeTuiParserResult None { get; } = new(null, null, null);

    public static ForgeTuiParserResult Decision(ForgeTuiDecision decision) => new(decision, null, null);

    public static ForgeTuiParserResult Error(string code, string message) => new(null, code, message);
}
