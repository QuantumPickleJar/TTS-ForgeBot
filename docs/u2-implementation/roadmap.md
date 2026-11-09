
# TTS-ForgeBot Updated Development Roadmap

**Revision: November 9, 2026**  
**Status: H0 active; November external-playtest findings are observations, not certified fixes.**

## Roadmap Objective

ForgeBot's remaining development should progress from **runtime correctness → generic Magic rules coverage → difficult integration systems → multiplayer certification → exotic supplemental rules**.

The central architectural rule remains:

> **Forge owns Magic. TTS presents Forge.**

TTS should not independently determine game legality, costs, targets, characteristics, combat legality, state-based actions, or card-specific behavior. New milestones should expand generic Forge-to-TTS capabilities rather than accumulate special cases.

---

# Current Roadmap

```text
FOUNDATION — M2C / F2C / U0-U3 (banked)
  ↓
H0 — Runtime correctness gate (CURRENT)
  H0-R  Persistent lifecycle controls / safe cleanup (NEXT)
  H0-FR Persistent match Flight Recorder (NEXT)
  H0-C  Gameplay coherence (phase, equipment, tap/mana, land layout)
  H0-S  Stack causality / response presentation
  ↓
T0 — Table adapter + Workshop migration certification
  ↓
U4 → U4.5 → U5 — Combat, merged permanents, designations
  ↓
PW0 (+ PW0.5 chosen values, PW0.75 emblems)
  ↓
R702 → R701 → PW1
  ↓
CMD — 1v1 Commander baseline
  ↓
MP0 — Multi-seat bot simulation
  ↓
MP1 — Human multiplayer + multiplayer Commander certification
  ↓
PW2 → SUP → UNF → completeness/release hardening

Parallel (after H0-R/H0-FR): T0 discovery, U3 torture-test backlog,
UX/presentation; CMD-F (Commander format/deck/command-zone
foundation) may begin alongside U4/U5 once H0/T0 are stable.
```

---

# 0. Banked Foundation — M2C / F2C / U0-U3

These phases form the architecture that future work should consume rather than replace.

Major capabilities already established include:

* Forge-authoritative game state.
* Structured legal actions and decisions.
* Hidden-information handling.
* Relationship/provenance infrastructure.
* Generic cast/payment provenance.
* Structured current characteristics.
* Stable logical card identity and physical reconciliation work.
* Snapshot/resync architecture.
* Token and permanent materialization infrastructure.
* Human decision presentation.
* Bug-report and diagnostic capture infrastructure.

U2 in particular established structured authoritative characteristics such as loyalty and defense, which means planeswalker support does **not** need to invent a new counter/state model.

Future milestones should extend these contracts instead of bypassing them.

---

# H0 — Runtime Hardening & Build-Loop Cleanup

**STATUS: ACTIVE — HARD GATE**

No major feature phase begins until ordinary games can survive prolonged play without protocol collapse.

Recent testing has exposed failures severe enough that feature expansion should remain paused:

* repeated synchronization/desynchronization loops;
* protocol-recovery failures;
* recoverable states falling back into repeated recovery;
* new-match/rebuild failures;
* false game conclusion, including a game ending as a draw on turn 1;
* stale or mismatched decisions surviving state transitions;
* reconstruction/resume paths behaving differently from ordinary play.

## Required work

Harden:

```text
Forge process
     ↕
Bridge session
     ↕
authoritative cursor
     ↕
snapshot / event stream
     ↕
TTS physical embodiment
```

Particular attention goes to:

* session identity;
* runtime epochs;
* stale callback rejection;
* decision generation identity;
* event cursor recovery;
* exactly-once materialization;
* snapshot reconstruction;
* new-match teardown;
* resync convergence;
* format/deck provenance;
* bug-report capture without runtime mutation.

## Exit Gate — H0

A hardening build passes only when:

1. Repeated new matches work without reloading TTS.
2. A complete game can end normally and another can begin.
3. Snapshot/resync converges rather than repeatedly re-triggering itself.
4. No stale decision from an earlier state can be accepted.
5. Manual recovery does not create a second protocol failure.
6. Tokens/permanents remain exactly once physically represented.
7. Game-end state agrees with Forge.
8. Turn-one false draw/win/loss conditions are eliminated.
9. Bug-report creation does not alter game state.
10. Automated regression coverage exists for every critical failure discovered during this hardening cycle.

**H0 is the current priority.** H0-R and H0-FR are the immediate implementation tasks; H0-C and H0-S remain mandatory to exit H0.

---


# November 9, 2026 — External Playtest Intake and Near-Term Gates

These are **unverified runtime observations** from a tester, not proof of where Forge, Bridge, or TTS failed. No diagnostic ZIP was captured. Do not mark an issue fixed without automated regression and, where needed, a live TTS canary.

| Observation | Track | Evidence or leading hypothesis | Status |
| --- | --- | --- | --- |
| World-space START / RESUME / NEW MATCH controls disappear or become inaccessible; resetting requires Save & Play and manual card cleanup | H0-R | Setup buttons are spawned as TTS objects; HUD NEW MATCH is initially inactive and its handler currently refuses ordinary active-match resets | Reproduce; fix |
| Apparent phase reversal or incorrect advance near Draw → Main 1, sometimes after cancelled actions | H0-C + H0-FR | Need correlated Forge phase/priority, event cursor, offered choices, action submission, and HUD projection | Unconfirmed |
| Captain America, First Avenger Throw/Catch or multi-target/payment flow misbehaves | H0-C | Throw **unattaches**, not sacrifices, an Equipment; cost/target division and relationship state need exact decision capture | Unconfirmed |
| Equipment logically attached but not physically arranged as attached | H0-C | Audit authoritative attachment identity and generic snapshot/event embodiment; do not derive rules from physical proximity | Unconfirmed |
| ForgeBot/opponent lands fall outside intended battlefield | H0-C / T0 | Investigate seat-specific land anchor and table bounds before moving coordinates | Unconfirmed |
| Manual tapping and mana accounting disagree with player expectation; physical collisions occur | H0-C | Separate TTS rotation/gesture intent from Forge tap legality, payment, and mana pool truth | Unconfirmed |
| Context button displays `ACT 1`, confused with numeric card cost | UX | Existing Lua builds `ACT\\n` + count of contextual Forge actions; `1` is action count, not mana or damage | Meaning identified; UI polish pending |
| Tester could not provide a capture | H0-FR | Current bounded diagnostics and on-demand ZIP capture do not guarantee durable full-match evidence | Address with recorder |

**Non-negotiable authority boundary:** Forge owns Magic rules and authoritative phase/zone/attachment/cost state. The Bridge transports identities and observations. TTS owns interaction and physical presentation. A physical gesture is never automatically an accepted Forge action.

---

# H0-R — Recovery Controls and Safe New-Match Lifecycle

**STATUS: NEXT IMPLEMENTATION; required before the next unsupervised playtest.**

Design one always-discoverable lifecycle-control surface, with a **vertical world-space stack** and equivalent controls under the HUD Options menu. Keep controls available throughout a match and after recoverable faults, not only during initial setup. Match/session status must drive enabled/disabled state and helpful explanation, not removal of the control.

- **START MATCH:** only creates a session when no active match exists; no duplicate sessions.
- **RESUME:** resumes a compatible paused local session; an incoherent session needs explicit recovery/resync, never an unsafe implicit bootstrap.
- **NEW MATCH:** always discoverable, including during an active match or nonterminal softlock. It is destructive; require confirmation, fence old callbacks, and use existing bridge session reset.
- **RECOVER / RESYNC:** clearly distinguished from RESUME and NEW MATCH; cannot silently change Forge rules truth. Retain external capture/bridge recovery when TTS Lua is frozen.
- Shared lifecycle handlers for the world controls and HUD controls. Do not implement competing reset paths or infer safety solely from whether a button is visible.
- Durable idempotent setup control identity across Save & Play, stale GUIDs, TTS object destruction/recreation, and reset races. Do not overwrite game objects or rely solely on a one-time spawn.
- New-match teardown must verify generated objects retire exactly once, old session/presentation IDs are invalidated, and deck inventories/physical zones are reconstructed from authoritative or validated inputs. Fail with actionable diagnostics if physical restoration cannot be proven; do not silently leave the user to rebuild piles.
- World-space stack position must be seat/table-aware so it cannot obstruct play or go out of bounds on the existing table; T0 reconfigures the anchors for the Workshop table.
- Host/admin permissions and confirmation remain enforced by handlers. Avoid making a destructive action broadly executable by UI refactoring.

**H0-R exit:** tests for initial/active/paused/terminal/desync/recovery/loading states; repeated new matches without Save & Play; reconnect and Save & Play rehydration; stale/cancelled confirmation; mid-reset failure; no duplicate controls or orphaned physical cards. A genuine TTS hard freeze is not solved by TTS buttons.

---

# H0-FR — Persistent Match Flight Recorder

**STATUS: NEXT IMPLEMENTATION; required before the next complex external playtest.**

Extend the existing `DiagnosticTelemetryBuffer`, diagnostic bundle writer/collector, TTS execution breadcrumbs, bridge process identity, and Forge adapter history; do **not** replace the current emergency capture or watchdog. The current in-memory capacities are bounded and are not an entire-match record.

Record a **versioned, replay-analyzable match journal**, where each entry includes timestamps and an ordered local sequence, session/runtime/process/build identity, Forge event/decision cursors and relevant causality IDs:

1. Every **offered** human decision and its complete authorized legal-action set (including nonchosen actions, cost/target candidate metadata, and provenance), action chosen or cancelled, request/ack/response, rejection, automatic pass/yield policy, and stale-choice handling.
2. Every authoritative Forge phase, turn, priority, stack, zone, tap, mana, triggered ability, and other state transition available from the producer, with event ordering.
3. Physical TTS actions/observations at meaningful boundaries: source/target GUID ↔ exact CardInstanceId, zone, position/rotation, object creation/retirement, equip/attachment presentation where supported, and command/result/error. Separate **requested** vs **observed** vs **authoritatively committed**.
4. Initial and periodic Forge snapshots plus physical-map checkpoints; correlate intervening events, and preserve enough state to find the **first divergence**.
5. Reporter annotations/bookmarks and pre/post-trigger diagnostic windows; record reasons and counters for dropped, coalesced, unavailable or truncated data, instead of claiming a complete recording silently.
6. Build/session/format/deck fingerprint metadata sufficient to correlate a capture with an exact test. Hidden cards, hands, libraries, and confidential choices require explicit privacy/visibility policy; never expose to unauthorized viewers or upload automatically to a public repository.

**Performance and durability:** write asynchronously on the .NET Bridge side using a bounded queue, segmenting and compression, finite disk quota/retention, explicit backpressure/drop metrics, crash-tolerant segment recovery, opt-in recording configuration and capture-safe fallbacks. The Lua side must not synchronously write files or enumerate the table every frame. Capture-only high-cost physical snapshots; no per-frame full Forge state, full-table object scan, or synchronous third-party request. A local headless/export reader or CLI must inspect the journal without a browser; a web UI is deferred.

**Recorder guarantees:** instrumentation is passive (must not advance Forge, mutate physical state or influence decision order); frozen TTS still permits external bridge-side capture of evidence already recorded; an incomplete/no-TTS-telemetry capture must be labeled honestly. Distinguish reconstructing a recorded history from deterministic re-execution, which additionally requires RNG/deck/build preconditions.

**H0-FR exit:** focused tests prove offered-vs-chosen fidelity, ordered phase/decision/event correlation, snapshot/checkpoint recovery, bounded overhead and backpressure, disk rotation, crash recovery, secret-safe export, unchanged legacy diagnostic ZIPs and watchdog behavior, and usable external-playtester artifacts.

---

# H0-C — Gameplay/Physical Coherence Follow-Up

**STATUS: queued after H0-R and H0-FR; fixes require evidence from the recorder or focused deterministic reproductions.**

Investigate: Draw → Main 1/priority/decision regression; Captain America's Throw (unattach, mana/value, split damage/targets) and Catch attachment trigger; a generic Forge-authored attachment relationship and TTS physical embodiment; opponent land positioning; manual tap intent/rotation and mana-pool reconciliation; collisions and no-GUID-fallback failure handling. The `ACT N` label is an action count and should be clarified without conflating it with mana, damage, targets, or cost.

Separate bridge contract/model deficiencies from Lua presentation defects and Forge rule defects. Preserve old U3 critical canaries (Mental Note/Stitcher's Supplier, Delve, generated tokens and copies, resync during materialization) and H0-S stack causality.

**H0-C exit:** every corrected behavior has a focused automated regression, a reproducible test deck/sequence, and live TTS evidence where physical presentation matters.

---

# T0 — Workshop Table Migration and Layout Adapters

**TARGET:** Steam Workshop `2296042369` (four-seat scripted Magic table); evaluate matching six-/eight-seat variants as related future adapters. **STATUS: read-only discovery may start now; adoption follows the H0 baseline.**

- Obtain and inspect actual Workshop save JSON and object scripts before assuming compatibility based on the listing.
- Audit Global/object Lua callbacks, HUD ownership, importer/Encoder reuse, scripting zones, deck/hand/graveyard/exile detection, board bounds, GUID stability, seat colors and visibility. Do not run a second source of Magic rules truth alongside Forge.
- Introduce table-specific seat/layout/source config with stable named anchors; preserve the original table as a rollback baseline; do not rewrite Forge's state model just to adopt a table.
- Keep the working two-seat game first. Configurability for more physical seats is **not** MP0/MP1 gameplay support.
- Recertify H0-R/H0-FR, full H0 gate, per-seat physical placement, token/attachment reconciliation, priority and the U3 canaries after migration.

**T0 exit:** repeatable install/configuration, verified lifecycle controls, no duplicate game automation, correct physical zones, preserved hidden information, resync convergence, and a documented rollback path.

---

# CMD-F — Early Commander Foundation (Parallel Preparation)

After H0/T0 stability, this may proceed alongside U4/U5 as a **limited generic capability track**, not a premature multiplayer rollout: Commander deck/format metadata, singleton/size validation, color identity delegated to Forge, command-zone and designation contract research, and deterministic two-seat test fixtures.

Full **CMD 1v1 certification** remains gated on U4/U5, Forge-supported Commander semantics, and other necessary general mechanics; **MP0** then validates multi-seat bots, **MP1** validates independent human multiplayer and multiplayer Commander. No Commander-specific legality or replacement effects in Lua.

---

# U4 — Extended Combat Relationship Graph

**PREREQUISITES: H0 + T0 acceptance on the selected test table**

Combat needs to stop assuming that every attacker simply attacks the opposing player.

The graph must generically represent:

```text
attacker
    │
    └── attacks ──► defending object

defending object:
    player
    planeswalker
    battle
    future Forge-supported defender types
```

Forge remains authoritative for whether an attack or block is legal.

TTS only:

* displays legal attackers;
* displays legal defending objects;
* records the player's selected declaration;
* presents Forge's resulting combat state.

## Required coverage

* multiple attackers;
* attackers split among different defenders;
* attacking a player;
* attacking planeswalker A;
* attacking planeswalker B;
* blocking creatures attacking different defenders;
* creature tokens as attackers/blockers;
* attack restrictions;
* block restrictions;
* multiple blockers;
* forced attacks/blocks;
* combat state surviving snapshot/resync.

## Exit Gate — U4

No Lua logic should need to infer whether a creature may attack or block or what objects are legal defenders.

---
# TTS-ForgeBot Development Roadmap — Revised Ordering

```text
FOUNDATION — M2C / F2C / U0-U3 (banked)
  ↓
H0 — Runtime correctness gate (CURRENT)
  H0-R  Persistent lifecycle controls / safe cleanup (NEXT)
  H0-FR Persistent match Flight Recorder (NEXT)
  H0-C  Gameplay coherence (phase, equipment, tap/mana, land layout)
  H0-S  Stack causality / response presentation
  ↓
T0 — Table adapter + Workshop migration certification
  ↓
U4 → U4.5 → U5 — Combat, merged permanents, designations
  ↓
PW0 (+ PW0.5 chosen values, PW0.75 emblems)
  ↓
R702 → R701 → PW1
  ↓
CMD — 1v1 Commander baseline
  ↓
MP0 — Multi-seat bot simulation
  ↓
MP1 — Human multiplayer + multiplayer Commander certification
  ↓
PW2 → SUP → UNF → completeness/release hardening

Parallel (after H0-R/H0-FR): T0 discovery, U3 torture-test backlog,
UX/presentation; CMD-F (Commander format/deck/command-zone
foundation) may begin alongside U4/U5 once H0/T0 are stable.
```

---

# H0-S — Stack Causality / Response Presentation

**SUBTRACK OF H0 — REQUIRED FOR H0 EXIT**

Physical table state must make the cause of an authoritative game transition visible before presenting its consequence.

For a spell:

```text
cast
  ↓
physical card enters STACK / CASTING area
  ↓
Forge publishes logical stack object + targets
  ↓
TTS presents source and targets
  ↓
players receive ordinary Forge priority
  ↓
Forge resolves/counters the object
  ↓
resulting zone/state changes are embodied
```

Example:

```text
AI casts Lightning Strike
        ↓
Lightning Strike remains physically in stack area
        ↓
CHAT: AI casts Lightning Strike → Stitcher's Supplier
        ↓
Stitcher's Supplier receives target presentation
        ↓
Player may respond
        ↓
Forge resolves Lightning Strike
        ↓
only now:
  Stitcher's Supplier → graveyard
  Lightning Strike    → graveyard
```

## Structured stack targets

Targets should evolve beyond display-name-only values into authoritative identities such as:

```text
stack target
 ├─ kind: CARD
 │   └─ cardInstanceId
 ├─ kind: PLAYER
 │   └─ seatId
 └─ kind: STACK_OBJECT
     └─ stackObjectId
```

This enables:

```text
Counterspell
    targets
Lightning Strike stack object
```

without TTS inferring spell legality.

Triggered and activated abilities remain logical stack objects and do not require fake physical cards.

## H0 additional exit requirements

11. A spell remains visibly associated with the stack while Forge says it is on the stack.

12. Public targets are presented before resolution-induced physical changes occur.

13. Counterspell/response windows arise from Forge priority, never artificial animation delays.

14. Diagnostic/chat presentation can explain the immediate cause of destructive zone changes without TTS interpreting card text.

---

# U4.5 — Composite / Merged Permanent Graph

**PREREQUISITES: H0 + U4**

Forge already understands merged permanents. ForgeBot must expose and physically present that authoritative topology without recreating Mutate rules in Lua.

This milestone generalizes the relationship/provenance foundation into:

```text
logical permanent
      │
      ├── component 0 — TOP
      │      card identity
      │
      ├── component 1
      │      card identity
      │
      └── component N
             card identity
```

The logical permanent's identity is distinct from the identity of whichever physical card currently appears on top.

## U4.5-A — Authoritative Component Contract

Forge/Bridge should expose, where applicable:

```text
logicalPermanentId
component count
ordered component identities
top component identity
component owners
component physical/materialization identity
merged/composite kind
```

Effective characteristics remain supplied independently by Forge's existing current-characteristics contract.

TTS must never calculate:

```text
power
toughness
name
types
color
mana value
abilities
```

from the component cards.

Forge already knows the resulting characteristics.

The component graph exists to answer:

```text
What physical cards constitute this one permanent?
Which physical card goes on top?
How must they separate when the permanent changes zones?
```

## U4.5-B — Mutate

Primary black-border canary: **Mutate**

Required flow:

```text
mutating creature spell on stack
        ↓
Forge validates target
        ↓
Forge asks TOP / BOTTOM
        ↓
Bridge receives authoritative merged topology
        ↓
TTS constructs one physical composite permanent
```

Physical presentation should visibly preserve its component cards without turning them into a TTS Deck.

Example:

```text
Gemrazer
──────────────
Supplier
```

represents **one selectable permanent**, not two creatures.

The top card is presentation of the authoritative top component.

Counters, attachments, targeting, attack/block selection, tapped state, damage presentation, etc. belong to the logical permanent rather than independently to each component.

## U4.5-C — Stable Logical Identity

Critical torture test:

```text
Supplier #17 exists
        ↓
Gemrazer #42 mutates on TOP
        ↓
logical battlefield object remains #17
top physical component becomes #42
current characteristics become Gemrazer-derived
        ↓
another creature #63 mutates underneath
        ↓
logical object is still #17
```

No subsystem may assume:

```text
logical permanent identity == top physical card identity
```

## U4.5-D — Zone Changes

When a composite permanent leaves the battlefield, Forge determines the resulting zones of its components.

TTS follows those authoritative transitions.

Example:

```text
3-card mutated creature dies
        ↓
logical merged permanent disappears
        ↓
component A → graveyard
component B → graveyard
component C → graveyard
```

Those cards then become ordinary independent cards in the graveyard and may enter the existing native searchable graveyard Deck.

Replacement effects, commander replacement choices, exile, bounce, and unusual component outcomes remain Forge-owned.

## U4.5-E — Snapshot / Resync

Snapshot reconstruction must recover:

```text
one logical permanent
three physical components
correct component order
correct top component
exactly once
```

without producing three battlefield permanents.

A resync may destroy and rebuild the physical presentation without changing Forge's merged relationship.

## U4.5-F — Interaction With Combat

U4 combat should consume the logical permanent.

A three-card mutated creature produces:

```text
ONE attacker
ONE blocker
ONE targetable permanent
```

not three choices.

The combat graph references the logical permanent identity.

## U4.5-G — Copy and Characteristic Canaries

Certification should include:

* mutate on top;
* mutate underneath;
* mutate a creature already mutated;
* top component changes;
* triggered "whenever this creature mutates" abilities;
* counters and Equipment survive mutation;
* tapped/summoning-state continuity;
* merged creature dies;
* merged creature is bounced/exiled;
* copy of a merged permanent;
* transform/face-down interactions supported by Forge;
* snapshot/resync during an active merged permanent.

## Exit Gate — U4.5

ForgeBot can represent an arbitrary Forge-supported composite permanent as:

```text
one authoritative logical game object
+
N ordered physical component cards
```

without deriving its rules characteristics or legality in Lua.

---

# R702 — Comprehensive §702 Keyword Ability Sweep

Mutate is no longer permitted to discover a missing architecture during this phase.

By R702, Mutate should be a **certification consumer of U4.5**.

The Mutate sweep verifies:

```text
alternative mutate cost
targeting
top/bottom choice
merged topology
mutate triggers
stack interaction
zone departure
snapshot/resync
```

against the generic systems already established.

Any remaining Mutate issue discovered here is classified as:

1. Forge engine deficiency;
2. generic bridge-contract deficiency;
3. TTS presentation deficiency;

rather than solved with card-specific or Mutate-specific Lua rules.

---

# UNF — Future Composite Consumers

U4.5 should deliberately avoid Mutate-specific naming in its core data model.

Later supplemental/Unfinity systems may reuse the same component graph for mechanics such as:

```text
Host / Augment
other Forge-supported merged permanents
future composite game pieces
```

Their rules remain independently Forge-owned.

U4.5 provides only the generic physical/logical composition language.

----


# U5 — Generalized Designations / Persistent State Presentation

**PREREQUISITE: U4**

ForgeBot needs a generic presentation model for game state that is neither a battlefield permanent nor an ordinary counter.

Examples include:

* Monarch;
* Initiative;
* emblems;
* persistent player designations;
* command-zone-like rule objects;
* future supplemental mechanics.

Architecture:

```text
Forge authoritative designation
            │
            ▼
Bridge structured state
            │
            ▼
TTS presentation proxy
```

The physical object is never the authority.

## Required properties

* stable identity;
* controller/owner where applicable;
* creation/removal events;
* snapshot persistence;
* no duplicate presentation after resync;
* correct teardown between games.

## Exit Gate — U5

A persistent game designation must survive destruction/recreation of its TTS presentation without altering the underlying Forge state.

---

# PW0 — Planeswalker Systems Foundation

**PREREQUISITES: U4 + U5**

PW0 establishes ordinary planeswalker behavior before attempting Karn/Sorin-class edge cases.

This is **not** a card-specific planeswalker implementation.

## PW0-A — Loyalty Ability Contract

Forge determines:

* whether a loyalty ability is currently legal;
* timing;
* activation limits;
* loyalty cost;
* whether the cost can be paid;
* counter changes;
* targets;
* resolution.

TTS determines none of those things.

TTS only presents the legal Forge actions.

This is critical because ForgeBot must naturally support cards that modify normal loyalty rules rather than locally assuming:

```text
one loyalty activation
once per turn
sorcery speed
```

## PW0-B — Loyalty Presentation

Required canaries:

```text
enter with N loyalty
+N ability → correct loyalty
-N ability → correct loyalty
0 ability  → unchanged loyalty
damage     → authoritative reduction
0 loyalty  → authoritative zone transition
```

Encoder counters are presentation only.

## PW0-C — Planeswalker Combat

Consume U4 directly:

* attack player;
* attack one planeswalker;
* attack several planeswalkers;
* split attackers among player/walkers;
* block normally afterward.

## PW0-D — Characteristic Mutation

Canaries must include:

* planeswalker becomes creature;
* creature becomes/also becomes planeswalker;
* transform into/out of planeswalker;
* copy planeswalker;
* type-loss/type-gain;
* changed characteristics retained through snapshot/resync.

Gideon-style walkers should be treated primarily as a **current-characteristics integration test**, not as Gideon-specific code.

---

# PW0.5 — Generic Chosen Values

**SUBPHASE OF PW0**

Existing typed choice infrastructure should be generalized into:

```text
choice<string>

CARD_NAME
CREATURE_TYPE
COLOR
BASIC_LAND_TYPE
CARD_TYPE
SUBTYPE
ENUMERATED_VALUE
```

## Card-name selection

Card-name selection should receive a searchable presentation rather than a gigantic dropdown.

Example:

```text
NAME A CARD

[ lightning bol________ ]

Lightning Bolt
Lightning Helix
Lightning Strike
...
```

Forge owns:

* candidate validity;
* canonical value;
* whether the answer is acceptable.

TTS owns:

* search;
* autocomplete;
* presentation.

This subsystem immediately benefits many non-planeswalker cards as well.

## Exit Gate — PW0.5

No effect requiring a chosen name/type/color/etc. should require a card-specific Lua dialog.

---

# PW0.75 — Generic Emblems

**SUBPHASE OF PW0 / CONSUMER OF U5**

Emblems are authoritative persistent game objects, not ordinary permanents.

Architecture:

```text
Forge emblem identity/state
          │
          ▼
Bridge authoritative representation
          │
          ▼
TTS visual emblem proxy
```

## Acceptance

```text
create emblem
    ↓
exactly one visual proxy

snapshot/resync
    ↓
still exactly one

planeswalker leaves battlefield
    ↓
emblem remains

effect continues
    ↓
physical proxy is not required for rules operation

new game
    ↓
old emblem is gone
```

---

# R702 — Comprehensive §702 Keyword Ability Sweep

**PREREQUISITE: PW0**

Perform systematic coverage of Forge-supported keyword abilities.

The purpose is not merely checking that Forge understands the keyword.

For each keyword determine whether ForgeBot requires a generic presentation/interaction capability involving:

* decisions;
* targeting;
* costs;
* alternative costs;
* linked objects;
* zone changes;
* current characteristics;
* combat;
* reveal/search;
* replacement effects;
* triggered actions;
* hidden information.

Every missing bridge capability becomes a generic subsystem issue.

Do not create keyword-specific Lua rules unless the information is purely presentational.

## Exit Gate — R702

Every Forge-supported §702 interaction class either:

1. works through an existing generic bridge capability, or
2. has a documented generic capability still requiring implementation.

---

# R701 — Comprehensive §701 Actions + Special Game Operations

**PREREQUISITE: R702**

Repeat the systematic sweep for game actions and special operations.

This is particularly important before PW1 because exotic planeswalkers invoke unusual but still ordinary black-border Magic operations.

Expected stress areas include:

* search;
* reveal;
* look at;
* choose;
* exile;
* return;
* copy;
* cast/play from unusual zones;
* outside-game access;
* control changes;
* turn manipulation;
* game restart;
* linked information.

R701 should establish the generic language PW1 consumes.

---

# PW1 — Exotic Planeswalker Systems

**PREREQUISITES: PW0 + R702 + R701**

PW1 contains the architectural monsters.

They are useful specifically because each one forces ForgeBot to solve a generic Magic problem.

## PW1-A — Outside-the-Game Card Sources

Primary canary:

**Karn, the Great Creator**

Introduce a generic candidate-source abstraction:

```text
card candidate
    ├── exile
    └── outside_game
```

Forge controls candidate legality.

TTS presents candidates.

Deck/import architecture should eventually distinguish:

```text
main deck
sideboard / external pool
commander(s)
```

No Karn-specific card retrieval.

---

## PW1-B — Linked Ability Provenance

Primary canary:

**Karn Liberated**

Forge knows which objects were exiled by which linked ability belonging to which logical Karn.

ForgeBot's job is to preserve that identity.

Mandatory torture test:

```text
Karn A
Karn B

A exiles cards
B exiles different cards

A's linked effects may reference only A's cards.
B's linked effects may reference only B's cards.
```

This validates earlier object-identity work under an interaction where getting identity merely “mostly right” is insufficient.

---

## PW1-C — Control Another Player's Turn

Primary canary:

**Sorin Markov**

ForgeBot must separate:

```text
active player
priority holder
resource owner
decision subject
decision controller
physical TTS seat
```

The current conceptual shortcut:

```text
decision.seatId == person allowed to answer
```

cannot survive controlled turns.

Generic authority should support something equivalent to:

```text
actingSeatId
decisionControllerSeatId
```

Example:

```text
Blue controls White's turn

Active player:       White
Resources:           White
Hand:                White
Permanents:          White

Human supplying
decisions:           Blue
```

This architecture must not be Sorin-specific.

---

## PW1-D — Game Restart / Game Epochs

Final-boss canary:

**Karn Liberated**

A rules-driven game restart is not ForgeBot's NEW MATCH command.

Required session model:

```text
Bridge Session
     │
     ├── Game Epoch 1
     │       │
     │       └── Karn restart
     │
     └── Game Epoch 2
```

Not:

```text
destroy everything
launch unrelated Forge session
```

The protocol needs a first-class restart transition carrying enough authoritative information to reconstruct the new game.

An epoch rebuild must invalidate:

* pending decisions;
* physical callbacks;
* old highlights;
* old selections;
* obsolete physical mappings;
* old cursor assumptions.

Then rebuild:

* players;
* life;
* libraries;
* hands;
* zones;
* designations;
* relevant exempted cards;
* post-restart permanents;
* event polling state.

This should deliberately reuse H0's recovery infrastructure.

**Karn is an intentional catastrophic-resync test.**

## Exit Gate — PW1

Karn/Sorin-class effects work without introducing code branches based on card names.

---

# CMD — Commander

**PREREQUISITES: U4 + U5 + PW1 and sufficient generic format/zone support. CMD-F may run earlier in parallel.**

This is the **1v1 Commander baseline**, prior to full multiplayer certification. Commander remains after ordinary black-border single-player mechanisms are broadly expressible.

Required systems include:

* commander designation;
* command zone;
* commander color-identity validation where Forge exposes it;
* commander tax;
* command-zone replacement decisions;
* commander damage;
* partner/background/multiple-commander configurations as supported;
* planeswalker commanders;
* deck importer Commander metadata;
* format-specific startup state.

Commander must consume generic zone/designation/choice architecture.

It should not fork ForgeBot into a separate rules engine.

## Exit Gate — CMD

A complete **1v1** Commander game can be represented without Commander-only state hacks in Lua. Multiplayer Commander requires MP0/MP1 certification as well.

---

# MP — Multiplayer (MP0 / MP1)

**PREREQUISITE: CMD 1v1 baseline for Commander-oriented multiplayer certification**

**MP0** establishes multi-seat Forge-controlled bot simulation and topology/priority/hidden-information contracts before adding human clients. **MP1** adds independent human multiplayer, complete decision ownership, recovery across clients/seats, and multiplayer Commander certification.

Multiplayer comes before final planeswalker certification because several ordinary planeswalker interactions cannot be genuinely validated with only two seats.

Required infrastructure:

* 3+ authoritative seats;
* independent hidden information;
* priority rotation;
* active-player/non-active-player ordering;
* multiple opponents;
* opponent-set targeting;
* attacks against different players and their planeswalkers;
* decision routing;
* controlled turns;
* concessions/player departure;
* synchronization/recovery involving multiple physical clients/seats.

## Mandatory cross-test

Controlled-turn architecture from PW1-C must be retested here.

For example:

```text
Player A controls Player B's turn
while Players C and D remain independent opponents.
```

---

# PW2 — Full Planeswalker Certification

**PREREQUISITES: PW0 + PW1 + COMMANDER + MULTIPLAYER**

PW2 is **not another implementation sprint**.

PW2 is a certification campaign.

Generate a machine-assisted inventory of every Forge-supported black-border planeswalker and classify abilities according to generic capabilities.

Example capability matrix:

| Capability                     | Certified |
| ------------------------------ | --------: |
| Target object/player           |         ☐ |
| Positive loyalty cost          |         ☐ |
| Negative loyalty cost          |         ☐ |
| Zero loyalty cost              |         ☐ |
| Modified activation timing     |         ☐ |
| Additional loyalty activations |         ☐ |
| Token creation                 |         ☐ |
| Emblem creation                |         ☐ |
| Named-value choice             |         ☐ |
| Copy/change characteristics    |         ☐ |
| Linked exile provenance        |         ☐ |
| Outside-game selection         |         ☐ |
| Control another player         |         ☐ |
| Restart game                   |         ☐ |
| Multiplayer opponent sets      |         ☐ |
| Attack opposing planeswalker   |         ☐ |
| Planeswalker commander         |         ☐ |

Representative torture families should include:

* ordinary Liliana/Jace-style +/− walkers;
* 0-loyalty walkers;
* Teferi, Master of Time-style timing changes;
* The Chain Veil / extra activation interactions;
* Gideon creature transformation;
* emblem-generating walkers;
* copied walkers;
* two Karn Liberated objects simultaneously;
* Karn, the Great Creator;
* Sorin Markov;
* Karn Liberated restart;
* planeswalker commanders;
* walkers controlled by multiple opponents.

## PW2 Exit Criterion

> **No Forge-supported black-border planeswalker requires card-name-specific Bridge/TTS rules logic, and every distinct planeswalker interaction class has at least one executable or live canary.**

PW2 is a **hard prerequisite for Unfinity**.

---

# SUP — Supplemental Product Coverage

After ordinary black-border architecture has passed PW2, broaden certification across supplemental products that stress less-common combinations of otherwise conventional Magic rules.

The objective here is discovering uncommon capability combinations without yet crossing into intentionally nonstandard physical/meta mechanics.

Any failure discovered here should still be classified as:

```text
missing generic capability
```

rather than:

```text
special supplemental card
```

whenever possible.

---

# UNF — Unfinity / Acorn / Intentionally Weird Rules

**PREREQUISITE: PW2 PASS**

Only at this point should ForgeBot intentionally confront mechanics whose difficulty comes from Magic deliberately doing unusual things.

Likely families include:

* Attractions;
* stickers;
* unusual physical interactions;
* meta-information;
* nonstandard choice surfaces;
* mechanics that cannot cleanly map to conventional game objects;
* acorn behavior where implementation is desirable.

The architectural distinction is important:

**Card-name selection, outside-game retrieval, controlled turns, linked exiles, emblems, and game restarts are not Unfinity problems.**

They are ordinary Magic capabilities and must already work.

---

# Parallel Release / UX Track

Core rules work should remain sequential. H0-R and H0-FR are priority hardening work; a read-only T0 audit may run in parallel, and other project-health tasks can resume after H0 stability:

```text
Diagnostics
    → persistent match Flight Recorder (H0-FR)
    → bounded disk/retention and tester-safe exports
    → one-button in-game bug submission
    → authoritative snapshot/log/state bundle
    → reproducible intake package

Deployment
    → automated dependency acquisition
    → minimal bootstrap command
    → generated/bundled TTS script
    → version compatibility checks
    → eventual near-two-step installation

UX
    → revealed-card presentation
    → searchable card/name chooser
    → sideboard/external-card carousel
    → clearer combat selection
    → multiplayer decision ownership cues
    → status/recovery feedback
    → general layout/polish

Testing
    → deterministic regression decks
    → capability-specific torture decks
    → long-session soak tests
    → repeated-match tests
    → snapshot/resync fault injection
    → closed-beta telemetry/bug intake
```

These tracks should never create alternate game authority in TTS.

---

# Final Phase Ordering

```text
[Banked] M2C / F2C / U0-U3
  ↓
[CURRENT] H0-R → H0-FR → H0-C + H0-S → full H0 certification
  ↓
T0  Four-seat Workshop table migration / adapter certification
  ↓
U4 → U4.5 → U5
  ↓
PW0 (+ PW0.5 / PW0.75)
  ↓
R702 → R701 → PW1
  ↓
CMD  1v1 Commander baseline
  ↓
MP0  Multi-seat bot simulation
  ↓
MP1  Human multiplayer and multiplayer Commander
  ↓
PW2  Full planeswalker certification (hard pre-Unfinity gate)
  ↓
SUP → UNF → Completeness / Packaging / Closed beta / Release

Parallel: table read-only audit now; CMD-F after H0/T0 stable,
alongside U4/U5, without bypassing later Commander gates.
```

# Architectural North Star

The roadmap should continuously reduce the number of concepts TTS needs to understand.

The desired endpoint is not:

```text
TTS knows how Karn works.
TTS knows how Sorin works.
TTS knows how Gideon works.
TTS knows how Commander works.
```

It is:

```text
Forge says what exists.
Forge says what is legal.
Forge says who may decide.
Forge says what changed.

Bridge transports that meaning faithfully.

TTS presents the choices
and physically embodies the resulting state.
```

Under this roadmap, **Karn Liberated becomes the final boss of conventional ForgeBot architecture, while PW2 proves that the solution generalized to the rest of the planeswalker card pool before ForgeBot ever enters Unfinity territory.**
