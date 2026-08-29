# U2 COMPLETION REQUIREMENTS - CRITICAL ADDENDUM

**MUST READ BEFORE IMPLEMENTING**

These requirements supersede any conflicting guidance in the implementation guide.

---

## 1. PAYMENT CONTEXT LIFETIME

**REQUIREMENT**: `PaymentContextId` has explicit lifecycle semantics.

### Begins When
Forge enters a cast/activation payment transaction (NOT just when action is presented).

### Must Survive
- Root action
- Optional-cost decisions
- Variable/X decisions  
- Nonmana payment decisions
- Mana/payment continuation
- Final payment acceptance

### Retires On
- Successful completion
- Explicit cancellation
- Failed/aborted cast
- Session reset

### Turn/Phase Transitions
May clean leaked stale contexts **defensively**, but must NOT be the primary semantic lifetime mechanism.

### Diagnostics Required
- Log context creation with PaymentContextId and SpellAbility reference
- Log context retirement with reason (success/cancel/failed/reset)
- Warn on defensive cleanup of stale contexts

**IMPLEMENTATION NOTE**: Original guide suggested turn/phase cleanup as primary mechanism. This is WRONG. Use explicit lifecycle tracking.

---

## 2. PROVE SPELLABILITY IDENTITY ⚠️ CRITICAL

**BLOCKER**: Before using `IdentityHashMap<SpellAbility, String>`:

### Required Proof
With a **real multi-stage Forge transaction**, prove that Forge retains the **SAME** `SpellAbility` identity across every payment stage.

### If Forge Clones/Replaces SpellAbility
**DO NOT** paper over it with hacks.

**INSTEAD**:
- Choose a stable Forge-side transaction key, OR
- Propagate context explicitly to replacement object

### Acceptance Criterion
The **SAME** `PaymentContextId` must appear across all stages of a multi-step cast.

**IMPLEMENTATION NOTE**: The `IdentityHashMap<SpellAbility, String>` approach in the guide is **UNVERIFIED** and may fail if Forge clones SpellAbility. This MUST be tested first or use an alternative stable key (e.g., Forge-side transaction ID).

**SUGGESTED ALTERNATIVE**:
```java
// Instead of: Map<SpellAbility, String> activePaymentContexts
// Consider: Store context in Forge's decision state or use a stable SA property
private final Map<Integer, String> paymentContextBySaId = new HashMap<>();

private String getOrCreatePaymentContext(SpellAbility sa) {
    if (sa == null) return null;
    // Use sa.getId() if it's stable across payment stages
    // OR store context in Forge's SpellAbilityView or Player decision state
    return paymentContextBySaId.computeIfAbsent(sa.getId(), 
        id -> "pctx-" + (nextPaymentContextId++));
}
```

**ACTION REQUIRED**: Test multi-stage cast (e.g., optional cost) and verify SpellAbility identity stability BEFORE committing to IdentityHashMap.

---

## 3. STRUCTURED COST TRANSPORT

**REQUIREMENT**: Do NOT evolve `[bridge ...]` suffix into arbitrarily nested mini-language.

### Simple Scalars MAY Stay in Suffix
Temporarily acceptable:
```
paymentContextId
sourceZone
castMode  
costKind
```

### Multiple CostComponentDto Records
**PREFER**: Explicit machine-readable structured producer record or equivalent structured JSON transport.

**NOT**: Complex nested syntax in bridge suffix.

### Compatibility
Keep existing flat fields while migrating.

### Parser Constraint
C# must **NOT** parse English prompts to recover cost components.

**IMPLEMENTATION NOTE**: The guide's `costComponents=[{...},{...}]` approach in the bridge suffix is acceptable IF kept simple. For complex costs, consider separate structured JSON output stream (like snapshots) rather than overloading the TUI choice line.

**SUGGESTED REFINEMENT**:
- Simple costs (mana, single tap, etc.): OK in bridge suffix
- Complex costs (Delve with component IDs, Crew with selection tracking): Emit separate structured cost decision JSON message

---

## 4. COST COMPONENT STABILITY

**REQUIREMENT**: `CostComponentId` must remain stable across redraws of SAME payment context.

### Example - CORRECT
```
P7/component-0 = mana
P7/component-1 = discard
(redraw happens)
P7/component-0 = mana  ← SAME
P7/component-1 = discard  ← SAME
```

### Example - WRONG
```
P7/component-0 = mana
P7/component-1 = discard
(redraw happens)
P7/component-0 = discard  ← CHANGED
P7/component-1 = mana  ← CHANGED
```

### Scoping
Component identity is scoped to `PaymentContextId`.

**IMPLEMENTATION NOTE**: Simple counter-based IDs (`component-0`, `component-1`) are UNSTABLE if Forge rebuilds cost collections in different order. 

**SOLUTION**: Use deterministic ordering or stable Forge-side component identifiers:
```java
// Deterministic ordering by cost type
List<CostPart> sortedCosts = new ArrayList<>(costs.getCostParts());
sortedCosts.sort((a, b) -> getCostKind(a).compareTo(getCostKind(b)));

// OR: Use Forge's internal cost identifiers if available
```

---

## 5. UNKNOWN COSTS

**REQUIREMENT**: Unknown-but-valid Forge cost parts must remain representable.

### Required Behavior
```java
Kind = "other"
DisplayLabel = Forge-derived description
PaymentContextId = retained
// + diagnostic emitted
```

### NEVER
- Silently omit cost
- Assume cost paid
- Invent legality

### Authority
Forge remains authoritative.

**IMPLEMENTATION NOTE**: Guide's catch-all `return "other"` is correct. Add diagnostic logging for unknown costs:
```java
private String getCostKind(CostPart cost) {
    // ... known cost types ...
    
    // Unknown cost
    System.err.println("[U2 diagnostic] Unknown cost type: " 
        + cost.getClass().getSimpleName() + " - " + cost.toString());
    return "other";
}
```

---

## 6. SNAPSHOT AUTHORITY

**REQUIREMENT**: Complete current characteristics in `GameSnapshotDto` are **REQUIRED**.

### Fresh Snapshot Must Reconstruct
From CURRENT Forge object:
- name
- mana cost
- mana value
- colors
- supertypes
- card types
- subtypes
- power
- toughness
- loyalty (where semantically applicable)
- defense (where semantically applicable)
- keywords

### Historic Events
No historic characteristic events may be **required** for correctness.

**IMPLEMENTATION NOTE**: Guide's `appendCharacteristics()` approach is correct for snapshot authority. Snapshots are truth, events are optimization.

---

## 7. EVENTS ARE AN OPTIMIZATION

**REQUIREMENT**: `characteristic_changed` is desirable but **secondary**.

### Hierarchy
```
snapshot = authoritative truth
events = low-latency synchronization hints
```

### If Forge Exposes Clean Events
Emit structured update promptly.

### If Forge Does NOT Expose Clean Events
**DO NOT** invent events from prompt text or card names.

Snapshot reconciliation remains sufficient.

**IMPLEMENTATION NOTE**: Guide's event emission from `GameEventCardStatsChanged` is correct. Do NOT add additional event fabrication beyond what Forge already emits.

---

## 8. SEMANTICS OF LOYALTY / DEFENSE ⚠️ CLARIFICATION NEEDED

**REQUIREMENT**: Do not ambiguously duplicate counter state.

### Before Implementing, Define
Do these fields mean:

**Option A**: Current characteristic/base value (printed + continuous effects)
**Option B**: Current battlefield counter quantity

### Problem
Counters already have authoritative representation in `counters` field.

Avoid two DTO fields claiming to represent same state differently.

### If Only Counter-Based Value Available
Document that semantic **explicitly**.

**IMPLEMENTATION NOTE**: Guide's current approach uses:
```java
property(json, "currentLoyalty", card.getCounters(CounterType.LOYALTY));
```

This is **Option B** (counter quantity). This may be WRONG if:
- Planeswalker enters with starting loyalty from characteristic
- Defense is printed value vs counter tracking

**ACTION REQUIRED**: 
1. Determine if Forge has separate "base loyalty" vs "current counters"
2. If they're the same, document it explicitly
3. If they're different, decide which semantic CurrentCharacteristicsDto.CurrentLoyalty represents
4. May need both: `currentBaseLoyalty` and `currentLoyaltyCounters`

**SUGGESTED CLARIFICATION**:
```java
// Loyalty: For planeswalkers, the current loyalty counter value
// (This equals starting loyalty on entry, then tracks +/- abilities)
if (card.isPlaneswalker()) {
    property(json, "currentLoyalty", card.getCounters(CounterType.LOYALTY));
} else {
    property(json, "currentLoyalty", (String) null);
}

// Defense: For battles, the current defense counter value  
if (card.isBattle()) {
    property(json, "currentDefense", card.getCounters(CounterType.DEFENSE));
} else {
    property(json, "currentDefense", (String) null);
}
```

Add comment explaining: "Loyalty and Defense are counter-based battlefield values, not separate characteristics."

---

## 9. MULTI-STAGE TRANSACTION ACCEPTANCE TRACE

**REQUIREMENT**: At least one automated/live canary must produce trace equivalent to:

```
ROOT
ActionId=A17
CardInstanceId=C42
PaymentContextId=P7

OPTIONAL COST
PaymentContextId=P7

NONMANA PAYMENT
PaymentContextId=P7
ComponentId=P7-C1
Kind=exile
Selected=3

DONE
PaymentContextId=P7

PAYMENT ACCEPTED
PaymentContextId=P7 retired
```

### Acceptance
ANY unexpected context change is a U2 failure.

**IMPLEMENTATION NOTE**: This requires both:
1. Forge producer emitting the context consistently
2. Test infrastructure capturing and verifying the trace
3. Live canary demonstrating the full flow

Add this to the Kicker or Delve canary as the acceptance test.

---

## 10. REQUIRED CANARY MATRIX

**REQUIREMENT**: Before U2 completion, prove:

- ✅ Normal cast
- ✅ Prototype / multiple cast modes
- ✅ Delve
- ✅ Crew aggregate payment
- ✅ Optional/additional cost
- ✅ X / variable choice
- ✅ Cast from non-hand zone
- ✅ Current characteristic change
- ✅ Fresh snapshot reconstruction

### Purpose
Each canary proves a **generic U2 property**, not polished TTS presentation.

**IMPLEMENTATION NOTE**: These align with existing todo canaries. No changes needed to guide, but emphasize that presentation quality is NOT the acceptance criterion—correct data flow is.

---

## 11. U3 BOUNDARY

**REQUIREMENT**: U2 does NOT own:

- Copy identity
- Virtual-object identity
- Delayed object identity
- New-object replacement identity
- Generic token/copy provenance

### If Canary Requires U3 Semantics
Report:
```
U3 DEPENDENCY
```
and choose another U2 canary.

### Prohibited
Do NOT add mechanic-specific identity hacks.

**IMPLEMENTATION NOTE**: If token/copy tracking comes up during canaries, STOP and document as U3 dependency. Do not implement copy tracking in U2.

---

## 12. U2 COMPLETE MEANS

**DO NOT** report completion until **ALL** are true:

- [ ] Contracts populated at runtime
- [ ] Stable payment context demonstrated
- [ ] Generic cost components emitted
- [ ] Unknown cost behavior defined
- [ ] Current characteristics emitted by Forge
- [ ] Fresh snapshots reconstruct characteristics
- [ ] Event/snapshot reconciliation works
- [ ] Representative canaries pass
- [ ] Full automated suite passes
- [ ] Live TTS acceptance passes

**IMPLEMENTATION NOTE**: This is the final gate. All 18 todos must be done, all tests pass, all canaries verified.

---

## CRITICAL IMPLEMENTATION BLOCKERS

Before proceeding with guide implementation:

### 🚨 BLOCKER 1: SpellAbility Identity
**Status**: UNVERIFIED  
**Risk**: IdentityHashMap may break on multi-stage casts  
**Action**: Test or use alternative stable key (SA ID, Forge transaction state)

### 🚨 BLOCKER 2: Loyalty/Defense Semantics  
**Status**: AMBIGUOUS  
**Risk**: May duplicate counter state incorrectly  
**Action**: Clarify if using base value vs counter quantity, document explicitly

### ⚠️ WARNING 1: Cost Component Stability
**Status**: DESIGN ISSUE  
**Risk**: Simple counter IDs may reorder on redraw  
**Action**: Use deterministic ordering or stable Forge IDs

### ⚠️ WARNING 2: Structured Cost Transport
**Status**: DESIGN DECISION NEEDED  
**Risk**: Complex costs may overflow bridge suffix  
**Action**: Consider separate structured JSON stream for complex costs

---

## UPDATED IMPLEMENTATION SEQUENCE

1. **FIRST**: Resolve BLOCKER 1 (SpellAbility identity) via test or alternative design
2. **FIRST**: Resolve BLOCKER 2 (Loyalty/Defense semantics) via Forge API inspection
3. **THEN**: Implement Part 1 (Payment Context) with explicit lifecycle
4. **THEN**: Implement Part 2 (Cost Components) with stable ordering
5. **THEN**: Implement Part 3 (Characteristics) with clarified Loyalty/Defense
6. **THEN**: Implement Part 4 (Events) as optimization only
7. **THEN**: Add diagnostics for context lifecycle and unknown costs
8. **THEN**: Test multi-stage trace (Requirement 9)
9. **THEN**: Run canary matrix (Requirement 10)
10. **FINALLY**: Verify complete checklist (Requirement 12)

---

## FILES TO UPDATE

1. **implementation guide** - Note blockers and updated sequence
2. **design doc** - Add addendum requirements
3. **RESUME doc** - Flag blockers before implementation

Do NOT proceed with blind implementation. Address blockers first.
