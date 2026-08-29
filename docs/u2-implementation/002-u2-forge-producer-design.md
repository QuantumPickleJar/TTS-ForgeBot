# Checkpoint 002: U2 Forge Producer Design

## Status
Branch: u2/cast-payment-provenance @ 5c41d9c  
Tests: 338 passing  
Phase: Forge Producer Implementation (4 todos in progress)

## Context
U2-A (contracts + parser foundation) complete. Now implementing complete Forge producer to emit:
1. Payment context tracking
2. Cost component metadata
3. Current characteristics
4. Characteristic change events

## Current Forge Patch Structure

### BridgeStateFeed.java (NEW FILE, lines 462-883)
Emits structured JSON snapshots to stdout for bridge consumption.

Key methods:
- `emitSnapshot()` - Main snapshot emission (lines 584-624)
- `appendPlayer()` - Player/zones emission (lines 626-664)
- `appendCard()` - Card state emission (lines 666-715)
  - Currently emits: forgeCardId, cardName, currentCardName, zone, position, owner, controller, tapped, faceDown, phasedOut, netPower/Toughness, currentPower/Toughness, currentTypes (flat array), isToken, cardDesignations, counters, keywords
  - **NEEDS**: Full CurrentCharacteristicsDto fields
- `appendCombat()` - Combat snapshot (lines 717-745)
- `appendCurrentTypes()` - Type array emission (lines 806-819)
  - **NEEDS**: Separate supertypes/cardTypes/subtypes

### PlayerControllerTUI.java (MODIFIED, lines 1000-1900+)
Handles TUI player input and emits choice metadata.

Key methods:
- `bridgeChoiceMetadata()` - Emits action provenance metadata (lines 1844-1876)
  - Currently emits: sourceZone, actionKind, abilityKind, castMode, costKind, displayManaCost, prototypePower/Toughness, preparedSourceCardId
  - **NEEDS**: paymentContextId, cost components
- `bridgeDisplayedManaCost()` - Cost display (lines 1881-1886)
- `bridgeEntityMetadata()` - Entity metadata (lines 1890+)

## Design for U2 Forge Producer Enhancements

### 1. Payment Context Tracking

**Problem**: Need stable PaymentContextId that survives across:
- Root cast/activation action
- Optional cost decisions
- Nonmana payment decisions (Delve, Crew, etc.)
- Mana/payment continuation
- Final accepted action

**Solution**: Add payment context tracking to `PlayerControllerTUI`
```java
private final Map<SpellAbility, String> activePaymentContexts = new IdentityHashMap<>();
private int nextPaymentContextId = 1;

private String getOrCreatePaymentContext(SpellAbility sa) {
    return activePaymentContexts.computeIfAbsent(sa, 
        unused -> "payment-ctx-" + (nextPaymentContextId++));
}
```

Emit in `bridgeChoiceMetadata()`:
```java
+ " paymentContextId=" + getOrCreatePaymentContext(sa)
```

Clear contexts when:
- Cast/activation completes successfully
- Player cancels
- Turn/phase transitions

### 2. Cost Component Metadata

**Problem**: Need structured cost component emission for:
- mana (already have displayManaCost)
- discard
- sacrifice
- exile
- tap-selection (Crew)
- total-power (Crew requiredTotalPower/selectedTotalPower)
- variable/X
- optional costs

**Solution**: Add `appendCostComponents()` helper:
```java
private String bridgeCostComponents(SpellAbility sa) {
    if (sa == null || sa.getPayCosts() == null) return "";
    StringBuilder components = new StringBuilder(" costComponents=[");
    int componentId = 0;
    for (CostPart cost : sa.getPayCosts().getCostParts()) {
        if (componentId > 0) components.append(',');
        components.append('{');
        components.append("id:").append(componentId++);
        components.append(",kind:\"").append(getCostKind(cost)).append('"');
        // Add RequiredValue, SelectionKind, Min/MaxSelections where applicable
        components.append('}');
    }
    components.append(']');
    return components.toString();
}

private String getCostKind(CostPart cost) {
    if (cost instanceof CostPayMana) return "mana";
    if (cost instanceof CostDiscard) return "discard";
    if (cost instanceof CostSacrifice) return "sacrifice";
    if (cost instanceof CostExile) return "exile";
    if (cost instanceof CostTap) return "tap";
    if (cost instanceof CostTapType) return "tap-selection";
    // ... etc
    return "other";
}
```

Emit in `bridgeChoiceMetadata()`.

### 3. Current Characteristics in Snapshots

**Problem**: `appendCard()` currently emits flat fields. Need structured CurrentCharacteristicsDto.

**Solution**: Extend `appendCard()` to emit characteristics object:
```java
json.append(",\"characteristics\":{");
property(json, "currentCardName", card.getName()).append(',');
property(json, "currentManaCost", String.valueOf(card.getManaCost())).append(',');
property(json, "currentManaValue", card.getCMC()).append(',');
json.append("\"currentColors\":[");
// Emit color array from card.getColor()
json.append("],\"currentSupertypes\":[");
// Emit from card.getType().getSupertypes()
json.append("],\"currentCardTypes\":[");
// Emit from card.getType().getCoreTypes()
json.append("],\"currentSubtypes\":[");
// Emit from card.getType().getSubtypes()
json.append("],");
property(json, "currentPower", card.isCreature() ? String.valueOf(card.getNetPower()) : null).append(',');
property(json, "currentToughness", card.isCreature() ? String.valueOf(card.getNetToughness()) : null).append(',');
property(json, "currentLoyalty", card.isPlaneswalker() ? card.getCounters(CounterType.LOYALTY) : null).append(',');
property(json, "currentDefense", card.isBattle() ? card.getCounters(CounterType.DEFENSE) : null).append(',');
json.append("\"currentKeywords\":[");
// Emit keywords array (already have this logic)
json.append("]}");
```

Keep flat fields for backward compatibility.

### 4. Characteristic Change Events

**Problem**: Need to emit events when characteristics change (color change, type change, P/T change, etc.)

**Solution**: Extend `BridgeStateFeed.receive()` to listen for characteristic-changing events:
```java
if (event instanceof GameEventCardStatsChanged 
    || event instanceof GameEventCardTypeChanged  // if exists
    || event instanceof GameEventCardAttributesChanged) {  // if exists
    // Emit characteristic_changed event before scheduling snapshot
    emitCharacteristicChangedEvent((Card) event.affected);
    scheduleSnapshot(event.getClass().getSimpleName());
}
```

Add `emitCharacteristicChangedEvent()`:
```java
private void emitCharacteristicChangedEvent(Card card) {
    StringBuilder json = new StringBuilder();
    json.append('{');
    property(json, "type", "characteristic_changed").append(',');
    property(json, "cardInstanceId", card.getId()).append(',');
    property(json, "characteristics", "{");
    // Emit full CurrentCharacteristicsDto
    json.append("}");
    json.append('}');
    
    synchronized (System.out) {
        System.out.println(SENTINEL + json);
    }
}
```

## Implementation Plan

Given credit constraints, implement incrementally but commit together:

1. Add payment context tracking fields and helper methods
2. Extend bridgeChoiceMetadata() to emit paymentContextId
3. Add bridgeCostComponents() helper and emit in metadata
4. Extend appendCard() to emit full characteristics object
5. Add characteristic_changed event emission
6. Test manually with simple Forge scenarios

## Files to Modify

All changes in `tools/forge/bridge-headless.patch`:

1. **BridgeStateFeed.java section**
   - Extend `appendCard()` for characteristics
   - Add `appendCharacteristics()` helper
   - Add characteristic_changed event emission
   - Update `receive()` to handle char-change events

2. **PlayerControllerTUI.java section**
   - Add payment context tracking fields
   - Add `getOrCreatePaymentContext()` helper
   - Add `bridgeCostComponents()` helper
   - Extend `bridgeChoiceMetadata()` to emit both

## Next Steps

1. Locate exact line numbers in patch for modifications
2. Implement changes incrementally
3. Manually test with simple Forge game
4. Commit as single "feat(u2): complete Forge producer for payment/characteristics"
5. Move to bridge parser updates (next 3 todos)

## Notes

- Keep backward compatibility (flat fields remain)
- Payment contexts cleared on turn/phase transitions
- Cost components use generic "kind" strings, not enums
- Characteristics always from current Forge object, never printed card DB
- Characteristic events emit before snapshot for ordering
