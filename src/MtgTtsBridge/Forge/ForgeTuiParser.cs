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
    private string? _activeCollectionKey;
    private string? _activeCollectionDecisionId;

    public ForgeTuiParser(IReadOnlyDictionary<string, string>? playerSeats = null, string opponentSeatId = "forge-player-2")
    {
        _playerSeats = playerSeats ?? new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        _opponentSeatId = opponentSeatId;
    }

    public void Reset()
    {
        _buffer.Clear();
        _decisionNumber = 0;
        _activeCollectionKey = null;
        _activeCollectionDecisionId = null;
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
            .ToList();

        // PlayerControllerTUI writes the target prompt with print(), then the
        // numbered targets with println().  stdout chunking can therefore put
        // the prompt in one Append call and the menu options in the next one.
        // Only consume a contiguous, complete block of numeric lines directly
        // after the prompt.  A non-option line terminates that block so a later
        // unrelated menu cannot be greedily folded into this decision.
        var trailingMenu = definition is not null
            ? ParseTrailingMenuOptions(text, prompt)
            : new TrailingMenuParse(Array.Empty<ForgeTuiMenuOption>(), prompt.Index + prompt.Length);
        if (trailingMenu.Options.Count > 0)
        {
            actions.AddRange(trailingMenu.Options);
        }

        var selectionMetadata = SelectionMetadataRegex().Match(promptContext);
        var decisionProvenance = DecisionProvenanceRegex().Matches(promptContext).Cast<Match>().LastOrDefault();
        var decisionContext = DecisionContextRegex().Matches(promptContext).Cast<Match>().LastOrDefault();
        var paymentContext = PaymentContextRegex().Matches(promptContext).Cast<Match>().LastOrDefault();
        var paymentContextId = paymentContext is { Success: true }
            ? NullIfBlank(paymentContext.Groups["paymentContextId"].Value)
            : null;
        var paymentCostComponents = paymentContextId is null
            ? Array.Empty<CostComponentDto>()
            : ParseCostComponents(promptContext, paymentContextId);
        var promptKind = selectionMetadata.Success
            ? selectionMetadata.Groups["kind"].Value
            : definition?.Definition.Kind ?? inferredKind;
        if (actions.Count == 0 && promptKind is "blocker_selection" or "attacker_selection"
            && prompt.Value.Contains("done", StringComparison.OrdinalIgnoreCase))
        {
            actions.Add(new ForgeTuiMenuOption(0, "done"));
        }

        if (actions.Count == 0)
        {
            var promptLooksLikeFinalInput = ExplicitNumericInputPromptRegex().IsMatch(prompt.Value);
            var trailing = text[(prompt.Index + prompt.Length)..];
            if (definition is not null
                || (!promptLooksLikeFinalInput && string.IsNullOrWhiteSpace(trailing)))
            {
                // Forge frequently streams prompt headers and numbered options in
                // separate stdout chunks. Preserve the current buffer whenever
                // a supported menu is incomplete; certainty is preferable to
                // killing a live session on a transient framing boundary.
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

        var consumedLength = prompt.Index + prompt.Length;
        if (trailingMenu.ConsumedThrough > consumedLength)
        {
            consumedLength = trailingMenu.ConsumedThrough;
        }
        _buffer.Remove(0, consumedLength);

        var kind = promptKind ?? "generic_numeric_selection";
        // A collection choice is a single Forge transaction even though the
        // TUI redraws its menu after every candidate toggle.  Reuse the
        // logical decision identity until its explicit Done action is sent;
        // otherwise the bridge treats the next toggle as stale and Forge
        // never receives the completed discard.
        var collectionKey = selectionMetadata.Success && RequiresForgeCollectionConfirmation(kind,
            selectionMetadata.Groups["mulliganStage"].Value)
            ? string.Join("|", kind,
                selectionMetadata.Groups["selectionKind"].Value,
                selectionMetadata.Groups["costKind"].Value,
                selectionMetadata.Groups["mulliganStage"].Value,
                selectionMetadata.Groups["sourceZone"].Value)
            : null;
        var reuseCollectionDecision = collectionKey is not null
            && string.Equals(_activeCollectionKey, collectionKey, StringComparison.Ordinal)
            && _activeCollectionDecisionId is not null;
        if (!reuseCollectionDecision)
        {
            _decisionNumber++;
            if (collectionKey is not null)
            {
                _activeCollectionKey = collectionKey;
                _activeCollectionDecisionId = $"forge-tui-{_decisionNumber}";
            }
            else
            {
                _activeCollectionKey = null;
                _activeCollectionDecisionId = null;
            }
        }
        var decisionId = reuseCollectionDecision
            ? _activeCollectionDecisionId!
            : $"forge-tui-{_decisionNumber}";
        var bridgeActions = actions.Select(option => BuildAction(option, decisionId, kind)).ToList();
        var mulliganStage = selectionMetadata.Success ? NullIfBlank(selectionMetadata.Groups["mulliganStage"].Value) : null;
        var selectionKind = selectionMetadata.Success ? NullIfBlank(selectionMetadata.Groups["selectionKind"].Value) : null;
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

        // Target selection is a cancellable follow-up to casting. Keep the
        // cancel intent explicit in the same decision so the bridge can send
        // Forge's supported textual cancel command instead of inventing a
        // local rollback.
        var cancelActionId = $"{decisionId}-cancel";
        var targetDecision = kind is "target_selection" or "defender_selection" or "player_selection";
        if (targetDecision && shape.AllowsCancel)
        {
            bridgeActions.Add(new LegalActionDto(
                ActionId: cancelActionId,
                Type: "cancel_cast",
                DisplayName: "Cancel casting",
                RequiresFollowup: false,
                CardIdentity: null,
                ObjectIdentity: null,
                ActionKind: "cancel_cast",
                ShortLabel: "Cancel casting"));
        }
        var inputMap = actions.ToDictionary(
            option => $"{decisionId}-choice-{option.Number}",
            option => GetInputValue(option, kind, prompt.Value),
            StringComparer.Ordinal);
        if (targetDecision && shape.AllowsCancel) inputMap[cancelActionId] = "q";

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
                SelectionKind = selectionKind,
                MulliganStage = mulliganStage,
                CandidateSourceZone = selectionMetadata.Success ? NullIfBlank(selectionMetadata.Groups["sourceZone"].Value) : null,
                RequiredTotalPower = selectionMetadata.Success && selectionMetadata.Groups["requiredTotalPower"].Success
                    ? int.Parse(selectionMetadata.Groups["requiredTotalPower"].Value, CultureInfo.InvariantCulture) : null,
                SelectedTotalPower = selectionMetadata.Success && selectionMetadata.Groups["selectedTotalPower"].Success
                    ? int.Parse(selectionMetadata.Groups["selectedTotalPower"].Value, CultureInfo.InvariantCulture) : null,
                PaymentContext = paymentContextId is null
                    ? null
                    : new PaymentContextDto(
                        OriginActionId: paymentContext is { Success: true } && paymentContext.Groups["originActionId"].Success
                            ? paymentContext.Groups["originActionId"].Value
                            : decisionId,
                        PaymentContextId: paymentContextId,
                        SourceCardInstanceId: paymentContext is { Success: true } && paymentContext.Groups["sourceCardId"].Success
                            ? $"forge-object:{paymentContext.Groups["sourceCardId"].Value}" : null,
                        SourceZone: paymentContext is { Success: true } ? NullIfBlank(paymentContext.Groups["sourceZone"].Value) : null,
                        ActionKind: paymentContext is { Success: true } ? NullIfBlank(paymentContext.Groups["actionKind"].Value) : null,
                        CastMode: paymentContext is { Success: true } ? NullIfBlank(paymentContext.Groups["castMode"].Value) : null,
                        CostComponents: paymentCostComponents)
            },
             inputMap));
    }

    private static TrailingMenuParse ParseTrailingMenuOptions(string text, Match prompt)
    {
        var options = new List<ForgeTuiMenuOption>();
        var cursor = prompt.Index + prompt.Length;
        var consumedThrough = cursor;

        while (cursor < text.Length)
        {
            var newline = text.IndexOf('\n', cursor);
            var hasCompleteLine = newline >= 0;
            var lineEnd = hasCompleteLine ? newline : text.Length;
            var line = text[cursor..lineEnd].TrimEnd('\r');

            if (string.IsNullOrWhiteSpace(line))
            {
                if (!hasCompleteLine) break;
                cursor = newline + 1;
                continue;
            }

            var match = MenuOptionRegex().Match(line);
            if (!match.Success || match.Index != 0 || match.Length != line.Length)
            {
                break;
            }

            // A final line without its newline may still be receiving bytes in
            // the next stdout chunk. Do not expose a partial or prematurely
            // truncated menu as a Forge decision.
            if (!hasCompleteLine) break;

            options.Add(new ForgeTuiMenuOption(
                int.Parse(match.Groups["number"].Value, CultureInfo.InvariantCulture),
                match.Groups["label"].Value.Trim()));
            consumedThrough = newline + 1;
            cursor = consumedThrough;
        }

        return new TrailingMenuParse(options, consumedThrough);
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
        var entityProvenance = EntityProvenanceRegex().Match(option.Label);
        var label = ForgeCardIdRegex().Replace(option.Label, string.Empty).Trim();
        if (entityProvenance.Success)
        {
            label = EntityProvenanceRegex().Replace(label, string.Empty).Trim();
        }
        if (provenance.Success)
        {
            label = ActionProvenanceRegex().Replace(label, string.Empty).Trim();
            if (string.Equals(provenance.Groups["castMode"].Value, "prepare", StringComparison.OrdinalIgnoreCase))
            {
                label = "PREPARED SPELL: " + label;
            }
        }
        var entityKind = entityProvenance.Success
            ? NullIfBlank(entityProvenance.Groups["entityKind"].Value) : null;
        var entitySeatId = entityProvenance.Success
            ? NullIfBlank(entityProvenance.Groups["seatId"].Value) : null;
        var entityCardId = entityProvenance.Success && entityProvenance.Groups["cardInstanceId"].Success
            ? $"forge-object:{entityProvenance.Groups["cardInstanceId"].Value}" : null;
        string? targetKind = null;
        string? targetSeatId = null;
        if (kind is "target_selection" or "defender_selection" or "player_selection"
            || string.Equals(entityKind, "player", StringComparison.OrdinalIgnoreCase))
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
        if (string.Equals(entityKind, "player", StringComparison.OrdinalIgnoreCase))
        {
            targetKind = "player";
            targetSeatId ??= entitySeatId;
        }

        // Entity provenance is additive metadata.  It must not change the
        // established action contract for discard/sacrifice/delve/mulligan
        // collections merely because those candidates are cards too.  Only
        // the generic entity-selection decision (used by Proliferate) maps to
        // choose_entity; the Forge decision kind remains authoritative for
        // every other collection.
        var actionType = kind == "mulligan"
            && label.Equals("Mulligan", StringComparison.OrdinalIgnoreCase)
                ? "mulligan"
            : kind == "mulligan"
                && label.Equals("Keep", StringComparison.OrdinalIgnoreCase)
                    ? "keep_hand"
            : kind is "target_selection" or "player_selection"
            ? "choose_target"
            : kind == "entity_selection"
                && (string.Equals(entityKind, "player", StringComparison.OrdinalIgnoreCase)
                    || string.Equals(entityKind, "permanent", StringComparison.OrdinalIgnoreCase))
                ? "choose_entity"
                : provenance.Success && provenance.Groups["actionKind"].Success
                    ? provenance.Groups["actionKind"].Value
                    : GetActionType(label, kind);
        var sourceInstanceId = entityCardId
            ?? (forgeCardId.Success ? $"forge-object:{forgeCardId.Groups["id"].Value}" : null);
        var sourceName = string.Equals(entityKind, "player", StringComparison.OrdinalIgnoreCase)
            ? null : GetCardIdentity(label, kind);
        var sourceZone = entityProvenance.Success && entityProvenance.Groups["sourceZone"].Success
            ? entityProvenance.Groups["sourceZone"].Value
            : provenance.Success ? provenance.Groups["sourceZone"].Value : null;
        // A legacy producer did not emit visibility metadata. Its only
        // actionable hidden-zone source was library, so fail closed for that
        // source while preserving existing hand/graveyard/exile contracts.
        var presentationAuthorized = !string.Equals(sourceZone, "library", StringComparison.OrdinalIgnoreCase)
            || provenance.Success
                && string.Equals(provenance.Groups["visibility"].Value, "authorized", StringComparison.OrdinalIgnoreCase);
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
            SourceZone: sourceZone,
            AbilityKind: provenance.Success ? provenance.Groups["abilityKind"].Value : null,
            CastMode: provenance.Success ? provenance.Groups["castMode"].Value : null,
            CostKind: provenance.Success ? provenance.Groups["costKind"].Value : null,
            PreparedSourceCardInstanceId: provenance.Success && provenance.Groups["preparedSourceId"].Success
                ? $"forge-object:{provenance.Groups["preparedSourceId"].Value}" : null,
            PrototypePower: provenance.Success ? NullIfBlank(provenance.Groups["prototypePower"].Value) : null,
            PrototypeToughness: provenance.Success ? NullIfBlank(provenance.Groups["prototypeToughness"].Value) : null,
            DisplayManaCost: provenance.Success ? NullIfBlank(provenance.Groups["displayManaCost"].Value) : null,
            EntityKind: entityKind,
            EntitySeatId: entitySeatId)
        {
            IsPresentationAuthorized = presentationAuthorized,
            // U2: Populate structured action provenance when bridge metadata is present
            Provenance = provenance.Success ? new ActionProvenanceDto(
                ActionKind: provenance.Groups["actionKind"].Success ? provenance.Groups["actionKind"].Value : actionType,
                SourceCardInstanceId: sourceInstanceId,
                SourceZone: provenance.Groups["sourceZone"].Success ? provenance.Groups["sourceZone"].Value : null,
                SourceSeatId: null, // Not yet emitted by Forge TUI
                AbilityKind: provenance.Groups["abilityKind"].Success ? NullIfBlank(provenance.Groups["abilityKind"].Value) : null,
                CastMode: provenance.Groups["castMode"].Success ? provenance.Groups["castMode"].Value : null,
                CastFace: null, // Future: split/modal card face
                DisplayLabel: label,
                DisplayCost: provenance.Groups["displayManaCost"].Success ? NullIfBlank(provenance.Groups["displayManaCost"].Value) : null,
                PaymentContextId: provenance.Groups["paymentContextId"].Success
                    ? NullIfBlank(provenance.Groups["paymentContextId"].Value)
                    : null,
                IsPresentationAuthorized: presentationAuthorized)
            : null
        };
    }

    private static IReadOnlyList<CostComponentDto> ParseCostComponents(string context, string paymentContextId)
    {
        var components = new List<CostComponentDto>();
        foreach (Match match in CostComponentRegex().Matches(context))
        {
            if (!match.Success || !string.Equals(match.Groups["paymentContextId"].Value, paymentContextId, StringComparison.Ordinal))
            {
                continue;
            }

            int? minSelections = match.Groups["minSelections"].Success
                ? int.Parse(match.Groups["minSelections"].Value, CultureInfo.InvariantCulture)
                : null;
            int? maxSelections = match.Groups["maxSelections"].Success
                ? int.Parse(match.Groups["maxSelections"].Value, CultureInfo.InvariantCulture)
                : null;
            components.Add(new CostComponentDto(
                CostComponentId: match.Groups["componentId"].Value,
                Kind: match.Groups["kind"].Value,
                DisplayLabel: DecodeBridgeToken(match.Groups["displayLabel"].Value),
                RequiredValue: DecodeBridgeToken(match.Groups["requiredValue"].Value),
                SelectedValue: DecodeBridgeToken(match.Groups["selectedValue"].Value),
                SourceZone: NullIfBlank(match.Groups["sourceZone"].Value),
                SelectionKind: NullIfBlank(match.Groups["selectionKind"].Value),
                MinSelections: minSelections,
                MaxSelections: maxSelections));
        }

        return components;
    }

    private static string? DecodeBridgeToken(string value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        return Uri.UnescapeDataString(value.Replace('+', ' '));
    }

    /// <summary>Ends the current redraw-based collection transaction.</summary>
    public void CompleteCollectionDecision()
    {
        _activeCollectionKey = null;
        _activeCollectionDecisionId = null;
    }

    private static bool RequiresForgeCollectionConfirmation(string kind, string? mulliganStage) =>
        kind is "discard" or "sacrifice" or "payment_option" or "search_selection" or "entity_selection" or "cost_selection" or "mode_selection"
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
        ("entity_selection", _) => "choose_entity",
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

    [GeneratedRegex(@"(?im)^(?:.*?(?:Enter|Select|Choose|Pick|Type|Press)[ \t]+(?:an?[ \t]+)?(?:[A-Za-z]+[ \t]+)?(?:choice|selection|option|number|answer|decision|assignment|target)\b.*?(?:\:|\?)|.*?(?:Choose|Select|Pick|Type)[ \t]+(?:one|(?:an?[ \t]+)?(?:option|choice|selection|number|assignment|target))[ \t]*[:\-])[ \t]*\r?$", RegexOptions.CultureInvariant)]
    private static partial Regex InputPromptRegex();

    [GeneratedRegex(@"(?i)\b(?:Enter|Type|Press)\b.*\b(?:choice|selection|option|target|number|answer|decision|assignment)\b|\bSelect\b.*\b(?:option|choice|number)\b", RegexOptions.CultureInvariant)]
    private static partial Regex ExplicitNumericInputPromptRegex();

    [GeneratedRegex(@"(?m)^\s*(?<number>\d+)\s*(?:[.):\-])?\s+(?<label>.+?)\s*\r?$", RegexOptions.CultureInvariant)]
    private static partial Regex MenuOptionRegex();

    // Forge emits this additive machine-readable suffix while constructing
    // numeric choices. Display labels remain presentation-only.
    [GeneratedRegex(@"\[bridge\s+sourceZone=(?<sourceZone>[A-Za-z_]+)(?:\s+visibility=(?<visibility>authorized|redacted))?(?:\s+actionKind=(?<actionKind>[A-Za-z_]+))?(?:\s+abilityKind=(?<abilityKind>[A-Za-z0-9_$]+))?(?:\s+castMode=(?<castMode>[A-Za-z0-9_-]+))?(?:\s+costKind=(?<costKind>[A-Za-z0-9_-]+))?(?:\s+displayManaCost=(?<displayManaCost>[A-Za-z0-9{}+*/-]+))?(?:\s+prototypePower=(?<prototypePower>[A-Za-z0-9+*/-]+))?(?:\s+prototypeToughness=(?<prototypeToughness>[A-Za-z0-9+*/-]+))?(?:\s+preparedSourceCardId=(?<preparedSourceId>\d+))?(?:\s+paymentContextId=(?<paymentContextId>[A-Za-z0-9:_-]+))?\]", RegexOptions.CultureInvariant)]
    private static partial Regex ActionProvenanceRegex();

    [GeneratedRegex(@"\[bridge\s+paymentContextId=(?<paymentContextId>[A-Za-z0-9:_-]+)(?:\s+originActionId=(?<originActionId>[A-Za-z0-9:_-]+))?(?:\s+sourceCardId=(?<sourceCardId>\d+))?(?:\s+sourceZone=(?<sourceZone>[A-Za-z_]+))?(?:\s+actionKind=(?<actionKind>[A-Za-z_]+))?(?:\s+castMode=(?<castMode>[A-Za-z0-9_-]+))?(?:\s+paymentStage=(?<paymentStage>[A-Za-z0-9_-]+))?\]", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex PaymentContextRegex();

    [GeneratedRegex(@"\[bridge\s+costComponent\s+paymentContextId=(?<paymentContextId>[A-Za-z0-9:_-]+)\s+componentId=(?<componentId>[A-Za-z0-9:_-]+)\s+kind=(?<kind>[A-Za-z0-9_-]+)(?:\s+displayLabel=(?<displayLabel>[^\s\]]+))?(?:\s+requiredValue=(?<requiredValue>[^\s\]]+))?(?:\s+selectedValue=(?<selectedValue>[^\s\]]+))?(?:\s+sourceZone=(?<sourceZone>[A-Za-z_]+))?(?:\s+selectionKind=(?<selectionKind>[A-Za-z0-9_-]+))?(?:\s+minSelections=(?<minSelections>\d+))?(?:\s+maxSelections=(?<maxSelections>\d+))?\]", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex CostComponentRegex();

    [GeneratedRegex(@"\[bridge\s+entityKind=(?<entityKind>[A-Za-z_]+)(?:\s+cardInstanceId=(?<cardInstanceId>\d+))?(?:\s+seatId=(?<seatId>[A-Za-z0-9_-]+))?(?:\s+sourceZone=(?<sourceZone>[A-Za-z_]+))?\]", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex EntityProvenanceRegex();

    [GeneratedRegex(@"^Play land:\s*(?<name>.+)$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex PlayLandRegex();

    [GeneratedRegex(@"^Cast (?:creature|artifact|enchantment|sorcery|instant|spell):\s*(?<name>.+?)(?:\s+\([^)]*\))?\s+-\s+.+$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex CastSpellRegex();

    [GeneratedRegex(@"^(?<name>.+?):\s*.*\bAdd\b", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex ManaAbilityRegex();

    [GeneratedRegex(@"(?:\s+\(\d+/\d+\))?(?:\s+\[[^\]]+\])+$|\s+\(\d+/\d+\)$", RegexOptions.CultureInvariant)]
    private static partial Regex CardOptionSuffixRegex();

    // Forge may append controller/identity annotations after the life total
    // (for example, a target row can end in "[id=2]").  Those annotations are
    // presentation metadata; retain the player target identity instead of
    // degrading the row into an untyped option that the TTS response surface
    // cannot submit.
    [GeneratedRegex(@"^(?<player>.+?)\s+\(Life:\s*-?\d+\)(?:\s+\[[^\]]+\])*$", RegexOptions.CultureInvariant)]
    private static partial Regex PlayerTargetRegex();

    [GeneratedRegex(@"^.+?\s+\(\d+/\d+\)\s+\[[^\]]+\]$", RegexOptions.CultureInvariant)]
    private static partial Regex CardTargetRegex();

    [GeneratedRegex(@"\s+\[id=(?<id>\d+)\]", RegexOptions.CultureInvariant)]
    private static partial Regex ForgeCardIdRegex();

    [GeneratedRegex(@"\[kind=(?<kind>[a-z_]+)(?:\s+selectionKind=(?<selectionKind>[a-z_]+))?(?:\s+costKind=(?<costKind>[a-z_]+))?(?:\s+mulliganStage=(?<mulliganStage>[a-z_]+))?(?:\s+sourceZone=(?<sourceZone>[a-z_]+))?(?:\s+requiredTotalPower=(?<requiredTotalPower>\d+))?(?:\s+selectedTotalPower=(?<selectedTotalPower>\d+))?\s+min=(?<min>\d+)\s+max=(?<max>\d+)\s+selected=(?<selected>\d+)\s+ordered=(?<ordered>true|false)\]", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
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

internal readonly record struct TrailingMenuParse(
    IReadOnlyList<ForgeTuiMenuOption> Options,
    int ConsumedThrough);

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
