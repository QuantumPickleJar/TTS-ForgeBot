# U2 Forge Producer Implementation Guide

**Task**: Complete Forge producer enhancements for payment context, cost components, and characteristics.

**Target File**: `tools/forge/bridge-headless.patch`

**Strategy**: Add new code to the patch file at specific insertion points. The patch format uses `+` prefix for new lines.

---

## Part 1: Payment Context Tracking (PlayerControllerTUI)

### Step 1.1: Add Payment Context Fields

**Location**: After line 477 in BridgeStateFeed class fields OR in PlayerControllerTUI class fields (search for private final fields in PlayerControllerTUI section of patch)

**What to find**: Look for the PlayerControllerTUI class definition in the patch (around line 1000-1100). Add fields near the top of the class.

**Code to add** (in patch format with + prefix):
```java
+    // U2: Track payment contexts across multi-step cast/activation decisions
+    private final Map<SpellAbility, String> activePaymentContexts = new IdentityHashMap<>();
+    private int nextPaymentContextId = 1;
```

### Step 1.2: Add Payment Context Helper Method

**Location**: Before or after `bridgeChoiceMetadata()` method (around line 1844)

**Code to add**:
```java
+    private String getOrCreatePaymentContext(SpellAbility sa) {
+        if (sa == null) return null;
+        return activePaymentContexts.computeIfAbsent(sa, 
+            unused -> "pctx-" + player.getId() + "-" + (nextPaymentContextId++));
+    }
+
+    private void clearPaymentContext(SpellAbility sa) {
+        if (sa != null) activePaymentContexts.remove(sa);
+    }
```

### Step 1.3: Emit Payment Context ID in Metadata

**Location**: Inside `bridgeChoiceMetadata()` method, before the final return (around line 1875)

**Current code** ends with:
```java
+            + (preparedSource == null ? "" : " preparedSourceCardId=" + preparedSource.getId()) + "]";
```

**Modify to**:
```java
+            + (preparedSource == null ? "" : " preparedSourceCardId=" + preparedSource.getId())
+            + " paymentContextId=" + getOrCreatePaymentContext(sa) + "]";
```

### Step 1.4: Clear Contexts on Turn Transitions

**Location**: Find where turn/phase changes are handled in PlayerControllerTUI. Look for methods handling turn begin/end.

**Code to add** (at appropriate turn transition point):
```java
+        // Clear stale payment contexts on turn transition
+        activePaymentContexts.clear();
```

---

## Part 2: Cost Components Emission (PlayerControllerTUI)

### Step 2.1: Add Cost Components Helper Method

**Location**: After `getOrCreatePaymentContext()` method

**Code to add**:
```java
+    private String bridgeCostComponents(SpellAbility sa) {
+        if (sa == null || sa.getPayCosts() == null) return "";
+        CostCollection costs = sa.getPayCosts();
+        if (costs.getCostParts().isEmpty()) return "";
+        
+        StringBuilder json = new StringBuilder(" costComponents=[");
+        int componentId = 0;
+        
+        for (CostPart cost : costs.getCostParts()) {
+            if (componentId > 0) json.append(',');
+            json.append("{id:").append(componentId++);
+            json.append(",kind:\"").append(getCostKind(cost)).append('"');
+            
+            // Add required/selected values where applicable
+            if (cost instanceof CostPayMana) {
+                CostPayMana manaCost = (CostPayMana) cost;
+                json.append(",displayLabel:\"").append(manaCost.getAmount()).append('"');
+            } else if (cost instanceof CostDiscard) {
+                CostDiscard discardCost = (CostDiscard) cost;
+                json.append(",minSelections:").append(discardCost.convertAmount());
+                json.append(",maxSelections:").append(discardCost.convertAmount());
+            } else if (cost instanceof CostSacrifice) {
+                CostSacrifice sacCost = (CostSacrifice) cost;
+                json.append(",minSelections:").append(sacCost.getAmount());
+                json.append(",maxSelections:").append(sacCost.getAmount());
+            } else if (cost instanceof CostTapType) {
+                CostTapType tapCost = (CostTapType) cost;
+                json.append(",minSelections:").append(tapCost.getTotalP());
+                // For Crew: this is the total power requirement
+            }
+            
+            json.append('}');
+        }
+        
+        json.append(']');
+        return json.toString();
+    }
+    
+    private String getCostKind(CostPart cost) {
+        if (cost instanceof CostPayMana) return "mana";
+        if (cost instanceof CostDiscard) return "discard";
+        if (cost instanceof CostSacrifice) return "sacrifice";
+        if (cost instanceof CostExile) return "exile";
+        if (cost instanceof CostExiledMoveToGrave) return "exile_to_graveyard";
+        if (cost instanceof CostTap) return "tap";
+        if (cost instanceof CostTapType) return "tap_selection";
+        if (cost instanceof CostPayLife) return "pay_life";
+        if (cost instanceof CostRemoveCounter) return "remove_counter";
+        if (cost instanceof CostMill) return "mill";
+        if (cost instanceof CostPartMana) return "mana";
+        // Variable costs (X)
+        if (cost.getAmount() != null && cost.getAmount().toString().contains("X")) return "variable";
+        return "other";
+    }
```

### Step 2.2: Emit Cost Components in Metadata

**Location**: Inside `bridgeChoiceMetadata()`, before the final return (after paymentContextId)

**Modify the return to**:
```java
+            + " paymentContextId=" + getOrCreatePaymentContext(sa)
+            + bridgeCostComponents(sa) + "]";
```

---

## Part 3: Complete Characteristics in Snapshots (BridgeStateFeed)

### Step 3.1: Add Characteristics Helper Method

**Location**: After `appendCard()` method (after line 715), before `appendCombat()`

**Code to add**:
```java
+    private void appendCharacteristics(final StringBuilder json, final Card card) {
+        json.append("\"characteristics\":{");
+        
+        // Current card name
+        property(json, "currentCardName", card.getName()).append(',');
+        
+        // Mana cost and mana value
+        property(json, "currentManaCost", String.valueOf(card.getManaCost())).append(',');
+        property(json, "currentManaValue", card.getCMC()).append(',');
+        
+        // Colors
+        json.append("\"currentColors\":[");
+        boolean firstColor = true;
+        for (byte color : card.getColor().getColors()) {
+            if (!firstColor) json.append(',');
+            firstColor = false;
+            String colorName = MagicColor.toLongString(color).toLowerCase(java.util.Locale.ROOT);
+            string(json, colorName);
+        }
+        json.append("],");
+        
+        // Type line - separated into supertypes/cardTypes/subtypes
+        json.append("\"currentSupertypes\":[");
+        boolean first = true;
+        for (Supertype st : card.getType().getSupertypes()) {
+            if (!first) json.append(',');
+            first = false;
+            string(json, st.toString().toLowerCase(java.util.Locale.ROOT));
+        }
+        json.append("],\"currentCardTypes\":[");
+        first = true;
+        for (CardType ct : card.getType().getCoreTypes()) {
+            if (!first) json.append(',');
+            first = false;
+            string(json, ct.toString().toLowerCase(java.util.Locale.ROOT));
+        }
+        json.append("],\"currentSubtypes\":[");
+        first = true;
+        for (String subtype : card.getType().getSubtypes()) {
+            if (!first) json.append(',');
+            first = false;
+            string(json, subtype.toLowerCase(java.util.Locale.ROOT));
+        }
+        json.append("],");
+        
+        // Power/Toughness (strings to support */X)
+        if (card.isCreature()) {
+            property(json, "currentPower", String.valueOf(card.getNetPower())).append(',');
+            property(json, "currentToughness", String.valueOf(card.getNetToughness())).append(',');
+        } else {
+            property(json, "currentPower", (String) null).append(',');
+            property(json, "currentToughness", (String) null).append(',');
+        }
+        
+        // Loyalty and Defense
+        if (card.isPlaneswalker()) {
+            property(json, "currentLoyalty", card.getCounters(CounterType.LOYALTY));
+        } else {
+            property(json, "currentLoyalty", (String) null);
+        }
+        json.append(',');
+        
+        if (card.isBattle()) {
+            property(json, "currentDefense", card.getCounters(CounterType.DEFENSE));
+        } else {
+            property(json, "currentDefense", (String) null);
+        }
+        json.append(',');
+        
+        // Keywords
+        json.append("\"currentKeywords\":[");
+        final Set<String> keywords = new LinkedHashSet<>();
+        for (KeywordInterface keyword : card.getKeywords()) {
+            final String name = keyword.getKeyword().toString();
+            if (!name.isEmpty()) keywords.add(name);
+        }
+        first = true;
+        for (String keyword : keywords) {
+            if (!first) json.append(',');
+            first = false;
+            string(json, keyword);
+        }
+        json.append("]}");
+    }
```

### Step 3.2: Emit Characteristics in appendCard()

**Location**: Inside `appendCard()` method, before the final closing brace (before line 714: `json.append("]}")`

**Current code** ends with:
```java
+        json.append("]}");
+    }
```

**Modify to**:
```java
+        json.append("],");
+        appendCharacteristics(json, card);
+        json.append('}');
+    }
```

---

## Part 4: Characteristic Change Events (BridgeStateFeed)

### Step 4.1: Add Characteristic Changed Event Emission Method

**Location**: After `emitSnapshot()` method (after line 624), before `appendPlayer()`

**Code to add**:
```java
+    private void emitCharacteristicChangedEvent(final Card card) {
+        final StringBuilder json = new StringBuilder(2048);
+        json.append('{');
+        property(json, "version", 1).append(',');
+        property(json, "type", "characteristic_changed").append(',');
+        property(json, "sequence", ++sequence).append(',');
+        property(json, "cardInstanceId", card.getId()).append(',');
+        appendCharacteristics(json, card);
+        json.append('}');
+        
+        synchronized (System.out) {
+            System.out.println(SENTINEL + json);
+        }
+    }
```

### Step 4.2: Trigger Characteristic Events from Game Events

**Location**: Inside `receive()` method in BridgeStateFeed (around line 494-522)

**Find**: The event instanceof chain (lines 507-522)

**Current code** has:
```java
+        if (event instanceof GameEventCardChangeZone
+                || event instanceof GameEventCardTapped
+                || event instanceof GameEventCardCounters
+                || event instanceof GameEventCardStatsChanged
```

**Modify** the `GameEventCardStatsChanged` case to emit characteristic event first:
```java
+        if (event instanceof GameEventCardStatsChanged) {
+            // Emit characteristic changed event before scheduling snapshot
+            if (event.affected instanceof Card) {
+                emitCharacteristicChangedEvent((Card) event.affected);
+            }
+            scheduleSnapshot(event.getClass().getSimpleName());
+            return;
+        }
+        if (event instanceof GameEventCardChangeZone
+                || event instanceof GameEventCardTapped
+                || event instanceof GameEventCardCounters
```

---

## Testing Strategy

### Quick Manual Test (Before Committing)

1. **Build the patch**:
```bash
cd tools/forge
# Apply to clean Forge checkout in .deps/forge-source/
git apply bridge-headless.patch
cd .deps/forge-source
mvn clean package -DskipTests
```

2. **Run simple Forge game**:
```bash
cd TTS-ForgeBot-U2
dotnet run --project src/MtgTtsBridge
# Start Forge in another terminal
# Cast a simple creature, check stdout for:
#   - paymentContextId in action metadata
#   - costComponents array
#   - characteristics object in snapshot
```

3. **Look for**:
- `paymentContextId=pctx-1-1` in action lines
- `costComponents=[{id:0,kind:"mana",...}]` in cost metadata
- `"characteristics":{"currentCardName":...}` in snapshot
- `characteristic_changed` events when P/T changes

### Integration Test Verification

After committing, verify bridge parser tests still pass:
```bash
dotnet test
# Should still be 338 passing
```

---

## Commit Strategy

**Single commit** after all 4 parts implemented:

```bash
git add tools/forge/bridge-headless.patch
git commit -m "feat(u2): complete Forge producer for payment context, cost components, and characteristics

Forge TUI now emits:
- Stable paymentContextId across multi-step cast/activation transactions
- Structured costComponents with generic cost kinds (mana, discard, sacrifice, tap, etc.)
- Complete currentCharacteristics with separated type-line, colors, mana cost/value, P/T, loyalty, defense
- characteristic_changed events when card stats change

Payment contexts:
- Tracked per SpellAbility in PlayerControllerTUI
- Cleared on turn transitions
- Correlate root actions with follow-up decisions (optional costs, Delve, Crew, etc.)

Cost components:
- Generic 'kind' strings avoid keyword-specific enums
- Support mana, discard, sacrifice, exile, tap-selection, variable/X
- Unknown costs represented as 'other'

Characteristics:
- Emitted from current Forge Card object, not printed database
- Supertypes/CardTypes/Subtypes separated for structured type-line
- P/T as strings to support */X notation
- Flat fields preserved for backward compatibility

Characteristic events:
- Emitted before snapshot when GameEventCardStatsChanged fires
- Contains full current characteristic vector

Next: Update bridge parsers to populate DTOs from new Forge metadata.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Potential Issues & Solutions

### Issue 1: Java Imports Missing
**Symptom**: Compile errors about missing classes (CostPartMana, CardType, etc.)

**Solution**: The patch file should already have necessary imports in the PlayerControllerTUI and BridgeStateFeed class sections. If not, check what Forge classes are already imported in those sections and use similar patterns.

### Issue 2: Method Signature Changes
**Symptom**: Methods like `getPayCosts()` don't exist on SpellAbility

**Solution**: Check actual Forge codebase at `.deps/forge-source/` for correct method names. May need `getPayCostList()` or similar.

### Issue 3: Payment Context IDs Too Long
**Symptom**: TUI output is extremely verbose

**Solution**: Shorten format to just `pctx-N` instead of `pctx-playerId-N`.

### Issue 4: Characteristic Events Fire Too Often
**Symptom**: Hundreds of characteristic_changed events during combat

**Solution**: Add debouncing or filter to only emit when characteristics actually changed (compare before/after values).

---

## Progress Checklist

- [ ] Part 1: Payment context tracking fields added
- [ ] Part 1: Payment context helpers implemented
- [ ] Part 1: Payment context emitted in metadata
- [ ] Part 1: Context clearing on turn transitions
- [ ] Part 2: Cost components helper implemented
- [ ] Part 2: Cost kind mapping complete
- [ ] Part 2: Cost components emitted in metadata
- [ ] Part 3: Characteristics helper implemented
- [ ] Part 3: Characteristics emitted in appendCard
- [ ] Part 4: Characteristic changed event method added
- [ ] Part 4: Event triggered from GameEventCardStatsChanged
- [ ] Manual test: Build succeeds
- [ ] Manual test: Simple game shows new metadata
- [ ] Integration test: Bridge tests pass (338)
- [ ] Commit with comprehensive message
- [ ] Update todos: Mark forge producer todos as 'done'

---

## Next Session Resume Point

After completing this implementation:

1. **Mark Forge producer todos done**:
```sql
UPDATE todos SET status = 'done' 
WHERE id IN ('u2-forge-payment-context', 'u2-forge-cost-components', 
             'u2-forge-characteristics', 'u2-forge-char-events');
```

2. **Query next ready todos**:
```sql
SELECT t.id, t.title FROM todos t
WHERE t.status = 'pending'
AND NOT EXISTS (
    SELECT 1 FROM todo_deps td
    JOIN todos dep ON td.depends_on = dep.id
    WHERE td.todo_id = t.id AND dep.status != 'done'
)
ORDER BY t.id;
```

Expected next: u2-parser-payment-context, u2-parser-cost-components, u2-parser-characteristics (all unblocked)

3. **Start bridge parser phase**: Update ForgeTuiParser and ForgeStructuredOutputParser to populate DTOs from new Forge metadata.

---

## File Locations Quick Reference

- **Patch file**: `tools/forge/bridge-headless.patch`
- **Session state**: `~/.copilot/session-state/d4b01a68-e1fc-494d-8feb-b4d310b00fdb/`
- **Plan**: `plan.md` in session state
- **Checkpoints**: `checkpoints/002-u2-forge-producer-design.md`
- **This guide**: `files/u2-forge-producer-implementation-guide.md`

Branch: `u2/cast-payment-provenance`  
Current HEAD: `5c41d9c`  
Tests: 338 passing
