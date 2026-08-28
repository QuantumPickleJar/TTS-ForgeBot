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
    private readonly IReadOnlyDictionary<string, string> _playerSeats;
    private readonly string _opponentSeatId;
    private int _decisionNumber;

    public ForgeTuiParser(IReadOnlyDictionary<string, string>? playerSeats = null, string opponentSeatId = "forge-player-2")
    {
        _playerSeats = playerSeats ?? new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        _opponentSeatId = opponentSeatId;
    }

    public void Reset()
    {
        _buffer.Clear();
        _decisionNumber = 0;
    }

    public ForgeTuiParserResult Append(string chunk)
    {
        _buffer.Append(StripAnsi(chunk));
        var text = _buffer.ToString();
        var prompt = InputPromptRegex().Matches(text).Cast<Match>().LastOrDefault();

        if (prompt is null || !prompt.Success)
        {
            return ForgeTuiParserResult.None;
        }

        var promptContext = text[..prompt.Index];
        var definition = FindPromptDefinition(promptContext);
        var inferredKind = InferKindFromPrompt(promptContext, prompt.Value);
        var optionMatches = MenuOptionRegex().Matches(promptContext);
        var actions = optionMatches
            .Where(match => definition is null || match.Index > definition.Value.Index)
            .Select(match => new ForgeTuiMenuOption(
                int.Parse(match.Groups["number"].Value, CultureInfo.InvariantCulture),
                match.Groups["label"].Value.Trim()))
            .ToArray();

        var selectionMetadata = SelectionMetadataRegex().Match(promptContext);
        var decisionProvenance = DecisionProvenanceRegex().Matches(promptContext).Cast<Match>().LastOrDefault();
        var decisionContext = DecisionContextRegex().Matches(promptContext).Cast<Match>().LastOrDefault();
        var promptKind = selectionMetadata.Success
            ? selectionMetadata.Groups["kind"].Value
            : definition?.Definition.Kind ?? inferredKind;
        if (actions.Length == 0 && promptKind is "blocker_selection" or "attacker_selection"
            && prompt.Value.Contains("done", StringComparison.OrdinalIgnoreCase))
        {
            actions = [new ForgeTuiMenuOption(0, "done")];
        }

        if (actions.Length == 0)
        {
            var trailing = text[(prompt.Index + prompt.Length)..];
            var promptLooksLikeFinalInput = ExplicitNumericInputPromptRegex().IsMatch(prompt.Value);
            if (string.IsNullOrWhiteSpace(trailing) && !promptLooksLikeFinalInput)
            {
                // Forge frequently streams prompt headers and numbered options in
                // separate stdout chunks. Preserve the current buffer so parsing
                // can complete once the numeric options arrive.
                return ForgeTuiParserResult.None;
            }

            _buffer.Remove(0, prompt.Index + prompt.Length);
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

        _buffer.Remove(0, prompt.Index + prompt.Length);

        _decisionNumber++;
        var kind = promptKind ?? "generic_numeric_selection";
        var decisionId = $"forge-tui-{_decisionNumber}";
        var bridgeActions = actions.Select(option => BuildAction(option, decisionId, kind)).ToArray();
        var mulliganStage = selectionMetadata.Success ? NullIfBlank(selectionMetadata.Groups["mulliganStage"].Value) : null;
        var forgeCollectionRequiresDone = selectionMetadata.Success
            && RequiresForgeCollectionConfirmation(kind, mulliganStage);
        var shape = selectionMetadata.Success
            ? (
                Min: int.Parse(selectionMetadata.Groups["min"].Value, CultureInfo.InvariantCulture),
                Max: int.Parse(selectionMetadata.Groups["max"].Value, CultureInfo.InvariantCulture),
                RequiresConfirmation: false,
                AllowsCancel: true,
                IsOrdered: string.Equals(selectionMetadata.Groups["ordered"].Value, "true", StringComparison.OrdinalIgnoreCase))
            : GetSelectionShape(kind, bridgeActions);

        return ForgeTuiParserResult.Decision(new ForgeTuiDecision(
            new DecisionDto(
                decisionId,
                kind,
                bridgeActions,
                Prompt: definition?.Definition.Header,
                MinSelections: shape.Min,
                MaxSelections: shape.Max,
                RequiresConfirmation: shape.RequiresConfirmation,
                AllowsCancel: shape.AllowsCancel,
                IsOrdered: shape.IsOrdered)
            {
                SelectedCount = selectionMetadata.Success
                    ? int.Parse(selectionMetadata.Groups["selected"].Value, CultureInfo.InvariantCulture)
                    : bridgeActions.Count(action => action.IsSelected),
                ConfirmRequired = forgeCollectionRequiresDone || shape.RequiresConfirmation,
                DecisionCauseKind = decisionProvenance is { Success: true } ? decisionProvenance.Groups["cause"].Value : null,
                DecisionReason = decisionProvenance is { Success: true } ? NullIfBlank(decisionProvenance.Groups["reason"].Value) : null,
                SourceCardInstanceId = decisionProvenance is { Success: true } && decisionProvenance.Groups["sourceId"].Success
                    ? $"forge-object:{decisionProvenance.Groups["sourceId"].Value}" : null,
                SourceCardName = decisionProvenance is { Success: true } ? NullIfBlank(decisionProvenance.Groups["sourceName"].Value) : null,
                ContextCardInstanceId = decisionContext is { Success: true } ? $"forge-object:{decisionContext.Groups["cardId"].Value}" : null,
                ContextCardName = decisionContext is { Success: true } ? NullIfBlank(decisionContext.Groups["cardName"].Value) : null,
                CostKind = selectionMetadata.Success ? NullIfBlank(selectionMetadata.Groups["costKind"].Value) : null,
                MulliganStage = mulliganStage,
                CandidateSourceZone = selectionMetadata.Success ? NullIfBlank(selectionMetadata.Groups["sourceZone"].Value) : null,
            },
            actions.ToDictionary(
                option => $"{decisionId}-choice-{option.Number}",
                option => GetInputValue(option, kind, prompt.Value),
                StringComparer.Ordinal)));
    }

    private static string GetInputValue(ForgeTuiMenuOption option, string kind, string inputPrompt)
    {
        if ((kind is "blocker_selection" or "attacker_selection")
            && (string.Equals(option.Label, "done", StringComparison.OrdinalIgnoreCase)
                || option.Label.StartsWith("No further blockers", StringComparison.OrdinalIgnoreCase)
                || option.Label.StartsWith("No further attackers", StringComparison.OrdinalIgnoreCase)))
        {
            // --numeric-choices presents 0 as the explicit finish action.
            // The text controller's one-at-a-time prompts alone accept "done".
            return inputPrompt.Contains("Enter choice", StringComparison.OrdinalIgnoreCase)
                ? option.Number.ToString(CultureInfo.InvariantCulture)
                : "done";
        }

        return option.Number.ToString(CultureInfo.InvariantCulture);
    }

    private LegalActionDto BuildAction(ForgeTuiMenuOption option, string decisionId, string kind)
    {
        var forgeCardId = ForgeCardIdRegex().Match(option.Label);
        var provenance = ActionProvenanceRegex().Match(option.Label);
        var label = ForgeCardIdRegex().Replace(option.Label, string.Empty).Trim();
        if (provenance.Success)
        {
            label = ActionProvenanceRegex().Replace(label, string.Empty).Trim();
            if (string.Equals(provenance.Groups["castMode"].Value, "prepare", StringComparison.OrdinalIgnoreCase))
            {
                label = "PREPARED SPELL: " + label;
            }
        }
        string? targetKind = null;
        string? targetSeatId = null;
        if (kind is "target_selection" or "defender_selection" or "player_selection")
        {
            var player = PlayerTargetRegex().Match(label);
            if (player.Success && TryResolveSeat(player.Groups["player"].Value.Trim(), out var seatId))
            {
                targetKind = "player";
                targetSeatId = seatId;
            }
            else if (CardTargetRegex().IsMatch(label))
            {
                targetKind = "card";
            }
        }

        var actionType = kind is "target_selection" or "player_selection"
            ? "choose_target"
            : provenance.Success && provenance.Groups["actionKind"].Success
                ? provenance.Groups["actionKind"].Value
                : GetActionType(label, kind);
        var sourceInstanceId = forgeCardId.Success ? $"forge-object:{forgeCardId.Groups["id"].Value}" : null;
        var sourceName = GetCardIdentity(label, kind);
        return new LegalActionDto(
            ActionId: $"{decisionId}-choice-{option.Number}",
            Type: actionType,
            DisplayName: label,
            RequiresFollowup: false,
            CardIdentity: sourceName,
            ObjectIdentity: null,
            TargetKind: targetKind,
            TargetSeatId: targetSeatId,
            CardInstanceId: sourceInstanceId,
            IsSelected: label.Contains("[SELECTED]", StringComparison.OrdinalIgnoreCase)
                || (kind == "attacker_selection" && label.Contains("[ATTACKING]", StringComparison.OrdinalIgnoreCase))
                || (kind is "blocker_selection" or "blocker_assignment" && label.Contains("[BLOCKING]", StringComparison.OrdinalIgnoreCase)),
            ActionKind: actionType,
            SourceCardInstanceId: sourceInstanceId,
            SourceCardName: sourceName,
            ShortLabel: label.Length <= 72 ? label : label[..69] + "...",
            // A target is one exact TUI input. It must be sent as soon as the
            // highlighted target is selected, not staged behind the collection
            // confirmation control used for discard/sacrifice menus.
            RequiresSelection: kind is "card_selection" or "attacker_selection" or "blocker_selection" or "blocker_assignment",
            SourceZone: provenance.Success ? provenance.Groups["sourceZone"].Value : null,
            AbilityKind: provenance.Success ? provenance.Groups["abilityKind"].Value : null,
            CastMode: provenance.Success ? provenance.Groups["castMode"].Value : null,
            CostKind: provenance.Success ? provenance.Groups["costKind"].Value : null,
            PreparedSourceCardInstanceId: provenance.Success && provenance.Groups["preparedSourceId"].Success
                ? $"forge-object:{provenance.Groups["preparedSourceId"].Value}" : null);
    }

    private static bool RequiresForgeCollectionConfirmation(string kind, string? mulliganStage) =>
        kind is "discard" or "sacrifice" or "payment_option" or "search_selection" or "entity_selection" or "cost_selection"
        || (kind == "mulligan" && string.Equals(mulliganStage, "bottom_selection", StringComparison.Ordinal));

    private bool TryResolveSeat(string playerName, out string seatId)
    {
        if (_playerSeats.TryGetValue(playerName, out seatId!)) return true;
        // Forge names the AI after the supplied deck file (for example
        // AI-mono-red or AI-legacy).  That is presentation, never identity.
        if (playerName.StartsWith("AI-", StringComparison.OrdinalIgnoreCase))
        {
            seatId = _opponentSeatId;
            return true;
        }
        seatId = string.Empty;
        return false;
    }

    private static (ForgeTuiPromptDefinition Definition, int Index)? FindPromptDefinition(string text)
    {
        (ForgeTuiPromptDefinition Definition, int Index)? found = null;
        foreach (var definition in PromptDefinitions)
        {
            var index = text.LastIndexOf(definition.Header, StringComparison.OrdinalIgnoreCase);
            if (index >= 0 && (found is null || index > found.Value.Index)) found = (definition, index);
        }

        return found;
    }

    private static string? InferKindFromPrompt(string promptContext, string promptValue)
    {
        var normalizedPrompt = promptValue.ToLowerInvariant();
        var normalizedContext = promptContext.ToLowerInvariant();
        
        // Blocker assignment is a followup after blocker selection
        if (normalizedContext.Contains("<blocker_num> blocks <attacker_num>") ||
            normalizedContext.Contains("enter block assignment") ||
            normalizedContext.Contains("block assignment"))
            return "blocker_assignment";
        
        if (normalizedPrompt.Contains("attacker number")) return "attacker_selection";
        if (normalizedPrompt.Contains("blocker number")) return "blocker_selection";

        if (normalizedContext.Contains("choose attackers one at a time")) return "attacker_selection";
        if (normalizedContext.Contains("choose blockers one at a time")) return "blocker_selection";

        return null;
    }

    private static string GetActionType(string label, string kind) => (kind, label) switch
    {
        ("blocker_assignment", var value) when value.Equals("done", StringComparison.OrdinalIgnoreCase) => "finish_blocking",
        ("blocker_selection", var value) when value.Equals("done", StringComparison.OrdinalIgnoreCase) => "finish_blocking",
        ("blocker_selection", var value) when value.StartsWith("No further blockers", StringComparison.OrdinalIgnoreCase) => "finish_blocking",
        ("blocker_selection", _) => "choose_blocker",
        ("attacker_selection", var value) when value.Equals("done", StringComparison.OrdinalIgnoreCase) => "finish_attacking",
        ("attacker_selection", var value) when value.StartsWith("No further attackers", StringComparison.OrdinalIgnoreCase) => "finish_attacking",
        ("attacker_selection", _) => "choose_attacker",
        (_, var value) when value.Equals("Done", StringComparison.OrdinalIgnoreCase) => "choose_none",
        ("sacrifice", _) => "sacrifice",
        ("discard", _) => "discard_card",
        ("mode_selection", _) => "choose_mode",
        ("creature_type_selection", _) => "choose_creature_type",
        ("numeric_selection", _) => "choose_number",
        ("yes_no", _) => "choose_option",
        ("defender_selection", _) => "choose_target",
        ("card_selection", _) => "discard_card",
        (_, var value) when value.StartsWith("Pass priority", StringComparison.OrdinalIgnoreCase) => "pass_priority",
        (_, var value) when value.StartsWith("Play land:", StringComparison.OrdinalIgnoreCase) => "play_land",
        (_, var value) when value.StartsWith("Cast ", StringComparison.OrdinalIgnoreCase) => "cast_spell",
        (_, var value) when ManaAbilityRegex().IsMatch(value) => "activate_mana",
        _ => "choose_option",
    };

    // CardIdentity is presentation identity only. Forge remains authoritative for
    // the card's rules; this extracts only the name Forge printed in the real menu.
    private static string? GetCardIdentity(string label, string kind)
    {
        if (label.Equals("Done", StringComparison.OrdinalIgnoreCase)) return null;
        var land = PlayLandRegex().Match(label);
        if (land.Success) return land.Groups["name"].Value.Trim();

        var spell = CastSpellRegex().Match(label);
        if (spell.Success) return spell.Groups["name"].Value.Trim();

        var mana = ManaAbilityRegex().Match(label);
        if (mana.Success) return mana.Groups["name"].Value.Trim();

        if (kind is not ("target_selection" or "defender_selection" or "blocker_selection" or "attacker_selection" or "card_selection" or "generic_numeric_selection" or "sacrifice" or "discard" or "entity_selection" or "cost_selection" or "search_selection" or "mulligan")) return null;
        if (label.StartsWith("No ", StringComparison.OrdinalIgnoreCase) ||
            PlayerTargetRegex().IsMatch(label) ||
            label.StartsWith("Spell:", StringComparison.OrdinalIgnoreCase)) return null;

        var stripped = CardOptionSuffixRegex().Replace(label, string.Empty).Trim();
        if (stripped.Length == 0) return null;

        if (kind == "generic_numeric_selection" && stripped.Equals("Pass", StringComparison.OrdinalIgnoreCase)) return null;

        return stripped;
    }

    private static (int Min, int Max, bool RequiresConfirmation, bool AllowsCancel, bool IsOrdered)
        GetSelectionShape(string kind, IReadOnlyList<LegalActionDto> actions) => kind switch
        {
            // The current numeric Forge TUI commits attackers one at a time and
            // then emits another decision. Cardinality is therefore one per
            // transport decision, even though the physical presenter retains a
            // generic selection shape for future atomic Forge controllers.
            "attacker_selection" => (0, 1, false, true, false),
            "blocker_selection" => (0, 1, false, true, false),
            "blocker_assignment" => (0, 1, false, true, false),
            // Legacy Forge cleanup prompts do not emit selection metadata, but
            // they are still staged card choices. Require an explicit confirm
            // so a physical grab cannot silently become an uncommitted move.
            "card_selection" => (1, 1, true, true, false),
            "target_selection" => (1, 1, false, true, false),
            "defender_selection" => (1, 1, false, true, false),
            _ => (1, 1, false, false, false),
        };

    private static string BoundContext(string context) =>
        context.Length <= 4096 ? context : context[^4096..];

    private static string? NullIfBlank(string value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static string StripAnsi(string text) => AnsiEscapeRegex().Replace(text, string.Empty);

    [GeneratedRegex(@"(?im)^(?:.*?(?:Enter|Select|Choose|Pick|Type|Press)[ \t]+(?:an?[ \t]+)?(?:[A-Za-z]+[ \t]+)?(?:choice|selection|option|number|answer|decision|assignment)\b.*?(?:\:|\?)|.*?(?:Choose|Select|Pick|Type)[ \t]+(?:one|(?:an?[ \t]+)?(?:option|choice|selection|number|assignment))[ \t]*[:\-])[ \t]*\r?$", RegexOptions.CultureInvariant)]
    private static partial Regex InputPromptRegex();

    [GeneratedRegex(@"(?i)\b(?:Enter|Type|Press)\b.*\b(?:choice|selection|option|target|number|answer|decision|assignment)\b|\bSelect\b.*\b(?:option|choice|number)\b", RegexOptions.CultureInvariant)]
    private static partial Regex ExplicitNumericInputPromptRegex();

    [GeneratedRegex(@"(?m)^\s*(?<number>\d+)\s*(?:[.):\-])?\s+(?<label>.+?)\s*\r?$", RegexOptions.CultureInvariant)]
    private static partial Regex MenuOptionRegex();

    // Forge emits this additive machine-readable suffix while constructing
    // numeric choices. Display labels remain presentation-only.
    [GeneratedRegex(@"\[bridge\s+sourceZone=(?<sourceZone>[A-Za-z_]+)(?:\s+actionKind=(?<actionKind>[A-Za-z_]+))?(?:\s+abilityKind=(?<abilityKind>[A-Za-z0-9_$]+))?(?:\s+castMode=(?<castMode>[A-Za-z0-9_-]+))?(?:\s+costKind=(?<costKind>[A-Za-z0-9_-]+))?(?:\s+preparedSourceCardId=(?<preparedSourceId>\d+))?\]", RegexOptions.CultureInvariant)]
    private static partial Regex ActionProvenanceRegex();

    [GeneratedRegex(@"^Play land:\s*(?<name>.+)$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex PlayLandRegex();

    [GeneratedRegex(@"^Cast (?:creature|artifact|sorcery|instant|spell):\s*(?<name>.+?)(?:\s+\([^)]*\))?\s+-\s+.+$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex CastSpellRegex();

    [GeneratedRegex(@"^(?<name>.+?):\s*.*\bAdd\b", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex ManaAbilityRegex();

    [GeneratedRegex(@"(?:\s+\(\d+/\d+\))?(?:\s+\[[^\]]+\])+$|\s+\(\d+/\d+\)$", RegexOptions.CultureInvariant)]
    private static partial Regex CardOptionSuffixRegex();

    [GeneratedRegex(@"^(?<player>.+?)\s+\(Life:\s*-?\d+\)$", RegexOptions.CultureInvariant)]
    private static partial Regex PlayerTargetRegex();

    [GeneratedRegex(@"^.+?\s+\(\d+/\d+\)\s+\[[^\]]+\]$", RegexOptions.CultureInvariant)]
    private static partial Regex CardTargetRegex();

    [GeneratedRegex(@"\s+\[id=(?<id>\d+)\]", RegexOptions.CultureInvariant)]
    private static partial Regex ForgeCardIdRegex();

    [GeneratedRegex(@"\[kind=(?<kind>[a-z_]+)(?:\s+costKind=(?<costKind>[a-z_]+))?(?:\s+mulliganStage=(?<mulliganStage>[a-z_]+))?(?:\s+sourceZone=(?<sourceZone>[a-z_]+))?\s+min=(?<min>\d+)\s+max=(?<max>\d+)\s+selected=(?<selected>\d+)\s+ordered=(?<ordered>true|false)\]", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex SelectionMetadataRegex();

    // This compact record is emitted by the controlled Forge producer, not
    // inferred from the English discard prompt. sourceName is deliberately
    // last because card names may contain spaces.
    [GeneratedRegex(@"\[bridge\s+decisionCause=(?<cause>[a-z_]+)(?:\s+decisionReason=(?<reason>[a-z_]+))?(?:\s+sourceCardId=(?<sourceId>\d+))?(?:\s+sourceCardName=(?<sourceName>[^\]]*?))?\]", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex DecisionProvenanceRegex();

    [GeneratedRegex(@"\[bridge\s+blockerForCardId=(?<cardId>\d+)\s+blockerForName=(?<cardName>[^\]]*?)\]", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex DecisionContextRegex();

    [GeneratedRegex("\\x1B\\[[0-?]*[ -/]*[@-~]", RegexOptions.CultureInvariant)]
    private static partial Regex AnsiEscapeRegex();

    private static readonly ForgeTuiPromptDefinition[] PromptDefinitions =
    [
        new("What would you like to do?", "main_priority"),
        new("Choose a target:", "target_selection"),
        new("Select a target:", "target_selection"),
        new("Choose target:", "target_selection"),
        new("Choose a target for ", "target_selection"),
        new("Choose target for ", "target_selection"),
        new("Who should block this attacker?", "blocker_selection"),
        new("Declare blockers", "blocker_selection"),
        new("Declare attackers", "attacker_selection"),
        new("Select attackers", "attacker_selection"),
        new("Choose attackers one at a time", "attacker_selection"),
        new("Choose blockers one at a time", "blocker_selection"),
        new("Choose defender for ", "defender_selection"),
        new(" to discard:", "card_selection"),
        new("=== FORGE CHOICE ===", "generic_numeric_selection"),
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
