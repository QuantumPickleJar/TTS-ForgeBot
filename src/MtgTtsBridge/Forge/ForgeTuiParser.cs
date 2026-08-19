using System.Text;
using System.Text.RegularExpressions;
using System.Globalization;
using MtgTtsBridge.Contracts.Actions;
using MtgTtsBridge.Contracts.State;

namespace MtgTtsBridge.Forge;

/// <summary>
/// Parses bounded numeric choices emitted by the rrn-headless-rebased TUI.
/// Prompt classification conveys interaction shape only; Forge remains authoritative.
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

        var promptContext = text[..prompt.Index];
        var definition = FindPromptDefinition(promptContext);
        var optionMatches = MenuOptionRegex().Matches(promptContext);
        var actions = optionMatches
            .Where(match => definition is null || match.Index > definition.Value.Index)
            .Select(match => new ForgeTuiMenuOption(
                int.Parse(match.Groups["number"].Value, CultureInfo.InvariantCulture),
                match.Groups["label"].Value.Trim()))
            .ToArray();

        _buffer.Remove(0, prompt.Index + prompt.Length);

        if (actions.Length == 0)
        {
            var context = BoundContext(text[..(prompt.Index + prompt.Length)]);
            if (definition is null)
            {
                return ForgeTuiParserResult.Unsupported(new ForgeTuiUnsupportedPrompt(
                    "unsupported_numeric_prompt",
                    "Forge requested numeric input, but no numbered choices could be recovered.",
                    context));
            }

            return ForgeTuiParserResult.Error("unrecognized_tui_menu", "Forge printed a supported menu header without numeric actions.");
        }

        _decisionNumber++;
        var kind = definition?.Definition.Kind ?? "generic_numeric_selection";
        var decisionId = $"forge-tui-{_decisionNumber}";
        var bridgeActions = actions.Select(option => new LegalActionDto(
            ActionId: $"{decisionId}-choice-{option.Number}",
            Type: GetActionType(option.Label, kind),
            DisplayName: option.Label,
            RequiresFollowup: false,
            CardIdentity: GetCardIdentity(option.Label, kind),
            ObjectIdentity: null)).ToArray();

        return ForgeTuiParserResult.Decision(new ForgeTuiDecision(
            new DecisionDto(decisionId, kind, bridgeActions),
            actions.ToDictionary(
                option => $"{decisionId}-choice-{option.Number}",
                option => option.Number.ToString(CultureInfo.InvariantCulture),
                StringComparer.Ordinal)));
    }

    private static (ForgeTuiPromptDefinition Definition, int Index)? FindPromptDefinition(string text)
    {
        (ForgeTuiPromptDefinition Definition, int Index)? found = null;
        foreach (var definition in PromptDefinitions)
        {
            var index = text.LastIndexOf(definition.Header, StringComparison.Ordinal);
            if (index >= 0 && (found is null || index > found.Value.Index)) found = (definition, index);
        }

        return found;
    }

    private static string GetActionType(string label, string kind) => (kind, label) switch
    {
        ("blocker_selection", var value) when value.StartsWith("No further blockers", StringComparison.OrdinalIgnoreCase) => "finish_blocking",
        ("blocker_selection", _) => "choose_blocker",
        (_, var value) when value.StartsWith("Pass priority", StringComparison.OrdinalIgnoreCase) => "pass_yield",
        (_, var value) when value.StartsWith("Play land:", StringComparison.OrdinalIgnoreCase) => "play_land",
        (_, var value) when value.StartsWith("Cast ", StringComparison.OrdinalIgnoreCase) => "cast_spell",
        _ => "choose_option",
    };

    // CardIdentity is presentation identity only. Forge remains authoritative for
    // the card's rules; this extracts only the name Forge printed in the real menu.
    private static string? GetCardIdentity(string label, string kind)
    {
        var land = PlayLandRegex().Match(label);
        if (land.Success) return land.Groups["name"].Value.Trim();

        var spell = CastSpellRegex().Match(label);
        if (spell.Success) return spell.Groups["name"].Value.Trim();

        if (kind is not ("target_selection" or "blocker_selection" or "attacker_selection" or "card_selection")) return null;
        if (label.StartsWith("No ", StringComparison.OrdinalIgnoreCase) ||
            label.StartsWith("Player ", StringComparison.OrdinalIgnoreCase) ||
            label.StartsWith("Spell:", StringComparison.OrdinalIgnoreCase)) return null;

        return CardOptionSuffixRegex().Replace(label, string.Empty).Trim();
    }

    private static string BoundContext(string context) =>
        context.Length <= 4096 ? context : context[^4096..];

    private static string StripAnsi(string text) => AnsiEscapeRegex().Replace(text, string.Empty);

    [GeneratedRegex(@"Enter choice \(\d+-\d+(?:, or \?)?\):\s*", RegexOptions.CultureInvariant)]
    private static partial Regex InputPromptRegex();

    [GeneratedRegex(@"(?m)^\s*(?<number>\d+)\.\s+(?<label>.+?)\s*\r?$", RegexOptions.CultureInvariant)]
    private static partial Regex MenuOptionRegex();

    [GeneratedRegex(@"^Play land:\s*(?<name>.+)$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex PlayLandRegex();

    [GeneratedRegex(@"^Cast (?:creature|artifact|sorcery|instant|spell):\s*(?<name>.+?)(?:\s+\([^)]*\))?\s+-\s+.+$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex CastSpellRegex();

    [GeneratedRegex(@"(?:\s+\(\d+/\d+\))?(?:\s+\[[^\]]+\])+$|\s+\(\d+/\d+\)$", RegexOptions.CultureInvariant)]
    private static partial Regex CardOptionSuffixRegex();

    [GeneratedRegex("\\x1B\\[[0-?]*[ -/]*[@-~]", RegexOptions.CultureInvariant)]
    private static partial Regex AnsiEscapeRegex();

    private static readonly ForgeTuiPromptDefinition[] PromptDefinitions =
    [
        new("What would you like to do?", "main_priority"),
        new("Select a target:", "target_selection"),
        new("Who should block this attacker?", "blocker_selection"),
        new("Declare attackers:", "attacker_selection"),
        new("Choose defender for ", "defender_selection"),
        new(" to discard:", "card_selection"),
    ];
}

public sealed record ForgeTuiMenuOption(int Number, string Label);

public sealed record ForgeTuiPromptDefinition(string Header, string Kind);

public sealed record ForgeTuiDecision(DecisionDto Decision, IReadOnlyDictionary<string, string> Inputs);

public sealed record ForgeTuiUnsupportedPrompt(string Code, string Message, string Context);

public sealed record ForgeTuiParserResult(
    ForgeTuiDecision? ParsedDecision,
    ForgeTuiUnsupportedPrompt? UnsupportedPrompt,
    string? ErrorCode,
    string? ErrorMessage)
{
    public static ForgeTuiParserResult None { get; } = new(null, null, null, null);

    public static ForgeTuiParserResult Decision(ForgeTuiDecision decision) => new(decision, null, null, null);

    public static ForgeTuiParserResult Unsupported(ForgeTuiUnsupportedPrompt prompt) => new(null, prompt, null, null);

    public static ForgeTuiParserResult Error(string code, string message) => new(null, null, code, message);
}
