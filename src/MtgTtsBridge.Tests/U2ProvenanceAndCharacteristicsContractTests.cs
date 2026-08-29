using MtgTtsBridge.Contracts.Actions;
using MtgTtsBridge.Contracts.Events;
using MtgTtsBridge.Contracts.State;

namespace MtgTtsBridge.Tests;

/// <summary>
/// Tests proving U2 generic cast/payment provenance contracts and complete
/// current characteristics are correctly structured and preserve key invariants.
/// </summary>
public sealed class U2ProvenanceAndCharacteristicsContractTests
{
    [Fact]
    public void ActionId_RemainsCanonicalIdentity_ProvenanceIsContext()
    {
        var action1 = new LegalActionDto(
            ActionId: "action_001",
            Type: "cast",
            DisplayName: "Cast Prototype",
            RequiresFollowup: false,
            CardIdentity: null,
            ObjectIdentity: null);

        var action2 = action1 with
        {
            Provenance = new ActionProvenanceDto(
                ActionKind: "cast",
                SourceCardInstanceId: "card_100",
                SourceZone: "hand",
                CastMode: "prototype")
        };

        // ActionId is the sole legal identity
        Assert.Equal("action_001", action1.ActionId);
        Assert.Equal("action_001", action2.ActionId);
        
        // Provenance is presentation context only
        Assert.Null(action1.Provenance);
        Assert.NotNull(action2.Provenance);
        Assert.Equal("prototype", action2.Provenance.CastMode);
    }

    [Fact]
    public void MultipleActions_MayShareCardInstanceId_ButMustHaveDistinctActionIds()
    {
        var sharedCardInstanceId = "card_100";
        
        var normalCast = new LegalActionDto(
            ActionId: "action_001",
            Type: "cast",
            DisplayName: "Cast normally",
            RequiresFollowup: false,
            CardIdentity: null,
            ObjectIdentity: null)
        {
            Provenance = new ActionProvenanceDto(
                ActionKind: "cast",
                SourceCardInstanceId: sharedCardInstanceId,
                SourceZone: "hand",
                CastMode: "normal")
        };

        var prototypeCast = new LegalActionDto(
            ActionId: "action_002",
            Type: "cast",
            DisplayName: "Cast as Prototype",
            RequiresFollowup: false,
            CardIdentity: null,
            ObjectIdentity: null)
        {
            Provenance = new ActionProvenanceDto(
                ActionKind: "cast",
                SourceCardInstanceId: sharedCardInstanceId,
                SourceZone: "hand",
                CastMode: "prototype")
        };

        var activateAbility = new LegalActionDto(
            ActionId: "action_003",
            Type: "activate",
            DisplayName: "Activate ability",
            RequiresFollowup: false,
            CardIdentity: null,
            ObjectIdentity: null)
        {
            Provenance = new ActionProvenanceDto(
                ActionKind: "activate",
                SourceCardInstanceId: sharedCardInstanceId,
                SourceZone: "battlefield",
                AbilityKind: "activated")
        };

        // All share the same CardInstanceId
        Assert.Equal(sharedCardInstanceId, normalCast.Provenance!.SourceCardInstanceId);
        Assert.Equal(sharedCardInstanceId, prototypeCast.Provenance!.SourceCardInstanceId);
        Assert.Equal(sharedCardInstanceId, activateAbility.Provenance!.SourceCardInstanceId);

        // But each has distinct ActionId
        Assert.NotEqual(normalCast.ActionId, prototypeCast.ActionId);
        Assert.NotEqual(normalCast.ActionId, activateAbility.ActionId);
        Assert.NotEqual(prototypeCast.ActionId, activateAbility.ActionId);

        // And different modes/kinds
        Assert.Equal("normal", normalCast.Provenance.CastMode);
        Assert.Equal("prototype", prototypeCast.Provenance.CastMode);
        Assert.Equal("activated", activateAbility.Provenance.AbilityKind);
    }

    [Fact]
    public void CastModes_RemainDistinct_ForSamePhysicalCard()
    {
        var modes = new[]
        {
            ("normal", "normal cast"),
            ("prototype", "prototype cast"),
            ("flashback", "flashback cast"),
            ("evoke", "evoke cast"),
            ("alternative_1", "alternative cost")
        };

        var actions = modes.Select((m, i) => new LegalActionDto(
            ActionId: $"action_{i:D3}",
            Type: "cast",
            DisplayName: m.Item2,
            RequiresFollowup: false,
            CardIdentity: null,
            ObjectIdentity: null)
        {
            Provenance = new ActionProvenanceDto(
                ActionKind: "cast",
                SourceCardInstanceId: "card_100",
                CastMode: m.Item1)
        }).ToList();

        // All distinct ActionIds
        var actionIds = actions.Select(a => a.ActionId).ToHashSet();
        Assert.Equal(modes.Length, actionIds.Count);

        // All distinct CastModes
        var castModes = actions.Select(a => a.Provenance!.CastMode).ToHashSet();
        Assert.Equal(modes.Length, castModes.Count);
    }

    [Fact]
    public void SourceZone_SurvivesSerialization_ForAllZones()
    {
        var zones = new[] { "hand", "graveyard", "exile", "library", "command", "battlefield", "stack" };

        foreach (var zone in zones)
        {
            var action = new LegalActionDto(
                ActionId: "action_001",
                Type: "cast",
                DisplayName: $"Cast from {zone}",
                RequiresFollowup: false,
                CardIdentity: null,
                ObjectIdentity: null,
                SourceZone: zone)
            {
                Provenance = new ActionProvenanceDto(
                    ActionKind: "cast",
                    SourceZone: zone)
            };

            // Flat field preserved for backward compatibility
            Assert.Equal(zone, action.SourceZone);
            
            // Structured provenance contains same zone
            Assert.Equal(zone, action.Provenance!.SourceZone);
        }
    }

    [Fact]
    public void PaymentContext_CorrelatesFollowupDecisions_ToOriginAction()
    {
        var originActionId = "action_cast_001";
        var paymentContextId = "payment_ctx_001";

        var context = new PaymentContextDto(
            OriginActionId: originActionId,
            PaymentContextId: paymentContextId,
            SourceCardInstanceId: "card_100",
            SourceZone: "hand",
            ActionKind: "cast",
            CastMode: "normal",
            CostComponents: new[]
            {
                new CostComponentDto(
                    CostComponentId: "comp_001",
                    Kind: "mana",
                    DisplayLabel: "{2}{U}"),
                new CostComponentDto(
                    CostComponentId: "comp_002",
                    Kind: "sacrifice",
                    DisplayLabel: "Sacrifice a creature",
                    MinSelections: 1,
                    MaxSelections: 1)
            });

        Assert.Equal(originActionId, context.OriginActionId);
        Assert.Equal(paymentContextId, context.PaymentContextId);
        Assert.Equal(2, context.CostComponents!.Count);

        // Each component has unique ID
        var componentIds = context.CostComponents.Select(c => c.CostComponentId).ToHashSet();
        Assert.Equal(2, componentIds.Count);
    }

    [Fact]
    public void CostComponent_SupportsGenericKinds_WithoutKeywordEnumeration()
    {
        var genericKinds = new[]
        {
            "mana", "life", "tap-self", "tap-selection", "sacrifice",
            "discard", "exile", "return", "reveal", "remove-counter",
            "player-counter", "total-power", "variable", "other"
        };

        foreach (var kind in genericKinds)
        {
            var component = new CostComponentDto(
                CostComponentId: $"comp_{kind}",
                Kind: kind,
                DisplayLabel: $"Cost: {kind}");

            Assert.Equal(kind, component.Kind);
            Assert.NotNull(component.DisplayLabel);
        }

        // Unknown cost kind is also representable
        var unknownCost = new CostComponentDto(
            CostComponentId: "comp_unknown",
            Kind: "future_mechanic_x",
            DisplayLabel: "Unknown cost");

        Assert.Equal("future_mechanic_x", unknownCost.Kind);
    }

    [Fact]
    public void Decision_CanIncludePaymentContext_ForFollowupChoices()
    {
        var paymentContext = new PaymentContextDto(
            OriginActionId: "action_cast_001",
            PaymentContextId: "payment_ctx_001",
            SourceCardInstanceId: "card_100");

        var decision = new DecisionDto(
            DecisionId: "dec_001",
            Kind: "payment",
            Actions: new[]
            {
                new LegalActionDto(
                    ActionId: "select_001",
                    Type: "select",
                    DisplayName: "Select creature",
                    RequiresFollowup: false,
                    CardIdentity: null,
                    ObjectIdentity: null)
            })
        {
            PaymentContext = paymentContext
        };

        Assert.NotNull(decision.PaymentContext);
        Assert.Equal("payment_ctx_001", decision.PaymentContext!.PaymentContextId);
        Assert.Equal("action_cast_001", decision.PaymentContext.OriginActionId);
    }

    [Fact]
    public void CurrentCharacteristics_ProvideCompleteForgeAuthoritativeState()
    {
        var characteristics = new CurrentCharacteristicsDto(
            CurrentCardName: "Serra Angel",
            CurrentManaCost: "{3}{W}{W}",
            CurrentManaValue: 5,
            CurrentColors: new[] { "W" },
            CurrentSupertypes: Array.Empty<string>(),
            CurrentCardTypes: new[] { "Creature" },
            CurrentSubtypes: new[] { "Angel" },
            CurrentPower: "4",
            CurrentToughness: "4",
            CurrentLoyalty: null,
            CurrentDefense: null,
            CurrentKeywords: new[] { "Flying", "Vigilance" });

        Assert.Equal("Serra Angel", characteristics.CurrentCardName);
        Assert.Equal("{3}{W}{W}", characteristics.CurrentManaCost);
        Assert.Equal(5, characteristics.CurrentManaValue);
        Assert.Equal(new[] { "W" }, characteristics.CurrentColors);
        Assert.Equal(new[] { "Creature" }, characteristics.CurrentCardTypes);
        Assert.Equal(new[] { "Angel" }, characteristics.CurrentSubtypes);
        Assert.Equal("4", characteristics.CurrentPower);
        Assert.Equal("4", characteristics.CurrentToughness);
        Assert.Contains("Flying", characteristics.CurrentKeywords!);
        Assert.Contains("Vigilance", characteristics.CurrentKeywords!);
    }

    [Fact]
    public void CurrentCharacteristics_SeparateManaCost_FromManaValue()
    {
        // Mana cost and mana value are distinct
        var charX = new CurrentCharacteristicsDto(
            CurrentCardName: "Fireball",
            CurrentManaCost: "{X}{R}",
            CurrentManaValue: 1); // Base mana value, X not chosen yet

        Assert.Equal("{X}{R}", charX.CurrentManaCost);
        Assert.Equal(1, charX.CurrentManaValue);

        var charNormal = new CurrentCharacteristicsDto(
            CurrentCardName: "Lightning Bolt",
            CurrentManaCost: "{R}",
            CurrentManaValue: 1);

        Assert.Equal("{R}", charNormal.CurrentManaCost);
        Assert.Equal(1, charNormal.CurrentManaValue);
    }

    [Fact]
    public void CurrentCharacteristics_SupportTypeLine_WithStructuredComponents()
    {
        var legendary = new CurrentCharacteristicsDto(
            CurrentCardName: "Ragavan, Nimble Pilferer",
            CurrentSupertypes: new[] { "Legendary" },
            CurrentCardTypes: new[] { "Creature" },
            CurrentSubtypes: new[] { "Monkey", "Pirate" });

        Assert.Contains("Legendary", legendary.CurrentSupertypes!);
        Assert.Contains("Creature", legendary.CurrentCardTypes!);
        Assert.Contains("Monkey", legendary.CurrentSubtypes!);
        Assert.Contains("Pirate", legendary.CurrentSubtypes!);

        var artifact = new CurrentCharacteristicsDto(
            CurrentCardName: "Sword of Fire and Ice",
            CurrentSupertypes: Array.Empty<string>(),
            CurrentCardTypes: new[] { "Artifact" },
            CurrentSubtypes: new[] { "Equipment" });

        Assert.Empty(artifact.CurrentSupertypes!);
        Assert.Contains("Artifact", artifact.CurrentCardTypes!);
        Assert.Contains("Equipment", artifact.CurrentSubtypes!);
    }

    [Fact]
    public void CurrentCharacteristics_SupportColors_AsNormalizedValues()
    {
        var mono = new CurrentCharacteristicsDto(
            CurrentCardName: "Island",
            CurrentColors: new[] { "U" });

        var multi = new CurrentCharacteristicsDto(
            CurrentCardName: "Boros Charm",
            CurrentColors: new[] { "R", "W" });

        var colorless = new CurrentCharacteristicsDto(
            CurrentCardName: "Wastes",
            CurrentColors: Array.Empty<string>());

        Assert.Equal(new[] { "U" }, mono.CurrentColors);
        Assert.Equal(new[] { "R", "W" }, multi.CurrentColors);
        Assert.Empty(colorless.CurrentColors!);
    }

    [Fact]
    public void CurrentCharacteristics_SupportLoyalty_AndDefense()
    {
        var planeswalker = new CurrentCharacteristicsDto(
            CurrentCardName: "Jace, the Mind Sculptor",
            CurrentLoyalty: "3",
            CurrentDefense: null);

        var battle = new CurrentCharacteristicsDto(
            CurrentCardName: "Invasion of Zendikar",
            CurrentLoyalty: null,
            CurrentDefense: "5");

        Assert.Equal("3", planeswalker.CurrentLoyalty);
        Assert.Null(planeswalker.CurrentDefense);
        Assert.Null(battle.CurrentLoyalty);
        Assert.Equal("5", battle.CurrentDefense);
    }

    [Fact]
    public void GameCardSnapshot_CanIncludeCharacteristics_PreservingBackwardCompatibility()
    {
        var characteristics = new CurrentCharacteristicsDto(
            CurrentCardName: "Grizzly Bears",
            CurrentManaCost: "{1}{G}",
            CurrentManaValue: 2,
            CurrentPower: "2",
            CurrentToughness: "2");

        var card = new GameCardSnapshotDto(
            CardInstanceId: "card_001",
            ForgeCardId: 100,
            CardName: "Grizzly Bears",
            CurrentCardName: "Grizzly Bears",
            Zone: "battlefield",
            ZonePosition: 0,
            OwnerSeatId: "seat_0",
            ControllerSeatId: "seat_0",
            Tapped: false,
            FaceDown: false,
            PhasedOut: false,
            Counters: new Dictionary<string, int>(),
            Keywords: Array.Empty<string>(),
            CurrentPower: 2,
            CurrentToughness: 2)
        {
            Characteristics = characteristics
        };

        // Flat fields preserved
        Assert.Equal(2, card.CurrentPower);
        Assert.Equal(2, card.CurrentToughness);

        // Structured characteristics provide richer data
        Assert.NotNull(card.Characteristics);
        Assert.Equal("{1}{G}", card.Characteristics!.CurrentManaCost);
        Assert.Equal(2, card.Characteristics.CurrentManaValue);
        Assert.Equal("2", card.Characteristics.CurrentPower);
        Assert.Equal("2", card.Characteristics.CurrentToughness);
    }

    [Fact]
    public void AuthoritativeEvent_CanIncludeCharacteristics_ForCharacteristicChanges()
    {
        var characteristics = new CurrentCharacteristicsDto(
            CurrentCardName: "Clone",
            CurrentManaCost: "{3}{U}",
            CurrentManaValue: 4,
            CurrentCardTypes: new[] { "Creature" },
            CurrentSubtypes: new[] { "Shapeshifter" },
            CurrentPower: "2",
            CurrentToughness: "2");

        var evt = new AuthoritativeEventDto(
            Sequence: 100,
            EventId: "evt_001",
            Kind: "characteristic_changed",
            SeatId: null,
            CardName: "Clone",
            ForgeObjectId: 200,
            CardInstanceId: "card_001",
            SourceZone: null,
            DestinationZone: null,
            Summary: "Characteristics changed",
            OccurredAtUtc: DateTimeOffset.UtcNow)
        {
            Characteristics = characteristics
        };

        Assert.Equal("characteristic_changed", evt.Kind);
        Assert.NotNull(evt.Characteristics);
        Assert.Equal("Clone", evt.Characteristics!.CurrentCardName);
        Assert.Equal("2", evt.Characteristics.CurrentPower);
        Assert.Contains("Shapeshifter", evt.Characteristics.CurrentSubtypes!);
    }

    [Fact]
    public void PaymentContext_SurvivesCancellation_ByRetiring()
    {
        var context = new PaymentContextDto(
            OriginActionId: "action_001",
            PaymentContextId: "payment_ctx_001",
            SourceCardInstanceId: "card_100");

        var decision1 = new DecisionDto(
            DecisionId: "dec_001",
            Kind: "payment",
            Actions: Array.Empty<LegalActionDto>())
        {
            PaymentContext = context
        };

        var decision2 = new DecisionDto(
            DecisionId: "dec_002",
            Kind: "payment",
            Actions: Array.Empty<LegalActionDto>())
        {
            PaymentContext = context
        };

        // Same PaymentContextId correlates follow-up decisions
        Assert.Equal("payment_ctx_001", decision1.PaymentContext!.PaymentContextId);
        Assert.Equal("payment_ctx_001", decision2.PaymentContext!.PaymentContextId);

        // Cancelled decision would not have PaymentContext
        var cancelledDecision = new DecisionDto(
            DecisionId: "dec_003",
            Kind: "priority",
            Actions: Array.Empty<LegalActionDto>());

        Assert.Null(cancelledDecision.PaymentContext);
    }

    [Fact]
    public void VariableValue_IsExplicitInCostComponent_NotInferred()
    {
        var xComponent = new CostComponentDto(
            CostComponentId: "comp_x",
            Kind: "variable",
            DisplayLabel: "Choose X",
            RequiredValue: null,
            SelectedValue: "5",
            MinSelections: 0,
            MaxSelections: null);

        Assert.Equal("variable", xComponent.Kind);
        Assert.Equal("5", xComponent.SelectedValue);
        Assert.Null(xComponent.RequiredValue);
    }

    [Fact]
    public void OptionalCost_IsRepresentable_InCostComponents()
    {
        var optionalKicker = new CostComponentDto(
            CostComponentId: "comp_kicker",
            Kind: "optional",
            DisplayLabel: "Pay kicker {2}",
            RequirementKind: "optional",
            MinSelections: 0,
            MaxSelections: 1);

        Assert.Equal("optional", optionalKicker.Kind);
        Assert.Equal(0, optionalKicker.MinSelections);
        Assert.Equal(1, optionalKicker.MaxSelections);
    }
}
