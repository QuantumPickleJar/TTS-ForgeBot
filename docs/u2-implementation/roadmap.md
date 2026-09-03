
# TTS-ForgeBot Updated Development Roadmap

**Revision: September 2, 2026**

## Roadmap Objective

ForgeBot's remaining development should progress from **runtime correctness → generic Magic rules coverage → difficult integration systems → multiplayer certification → exotic supplemental rules**.

The central architectural rule remains:

> **Forge owns Magic. TTS presents Forge.**

TTS should not independently determine game legality, costs, targets, characteristics, combat legality, state-based actions, or card-specific behavior. New milestones should expand generic Forge-to-TTS capabilities rather than accumulate special cases.

---

# Current Roadmap

```text
FOUNDATIONAL WORK
M2C / F2C / U0-U3
        │
        ▼
H0 — Runtime Hardening & Build-Loop Cleanup       ← CURRENT
        │
        ▼
U4 — Extended Combat Relationship Graph
        │
        ▼
U5 — Generalized Designations / Persistent State
        │
        ▼
PW0 — Planeswalker Systems Foundation
 ├─ PW0.5 — Generic Chosen Values
 └─ PW0.75 — Emblems
        │
        ▼
R702 — §702 Keyword Ability Sweep
        │
        ▼
R701 — §701 Actions + Special Game Operations
        │
        ▼
PW1 — Exotic Planeswalker Systems
        │
        ▼
CMD — Commander
        │
        ▼
MP — Multiplayer
        │
        ▼
PW2 — Full Planeswalker Certification
        │
        ▼
SUP — Supplemental Product Coverage
        │
        ▼
UNF — Unfinity / Acorn / Intentionally Weird Rules
        │
        ▼
COMPLETENESS / RELEASE HARDENING
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

**H0 is the current priority.**

---

# U4 — Extended Combat Relationship Graph

**PREREQUISITE: H0**

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
FOUNDATIONAL WORK
M2C / F2C / U0-U3
        │
        ▼
H0 — Runtime Hardening & Build-Loop Cleanup          ← CURRENT
 │
 └─ H0-S — Stack Causality / Response Presentation
        │
        ▼
U4 — Extended Combat Relationship Graph
        │
        ▼
U4.5 — Composite / Merged Permanent Graph
        │
        ▼
U5 — Generalized Designations / Persistent State
        │
        ▼
PW0 — Planeswalker Systems Foundation
 ├─ PW0.5 — Generic Chosen Values
 └─ PW0.75 — Emblems
        │
        ▼
R702 — §702 Keyword Ability Sweep
        │
        ▼
R701 — §701 Actions + Special Game Operations
        │
        ▼
PW1 — Exotic Planeswalker Systems
        │
        ▼
MP0 — Multi-Seat Bot Simulation
        │
        ▼
CMD — Commander
        │
        ▼
MP1 — Human Multiplayer
        │
        ▼
PW2 — Full Planeswalker Certification
        │
        ▼
SUP — Supplemental Product Coverage
        │
        ▼
UNF — Unfinity / Acorn / Intentionally Weird Rules
        │
        ▼
COMPLETENESS / RELEASE HARDENING
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

**PREREQUISITE: PW1**

Commander now occurs after ordinary black-border single-player mechanics are broadly expressible.

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

A complete Commander game can be represented without Commander-only state hacks in Lua.

---

# MP — Multiplayer

**PREREQUISITE: COMMANDER BASELINE**

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

Core rules work should remain sequential, but several project-health tasks can proceed alongside it once H0 is stable:

```text
Diagnostics
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
[Banked]
M2C / F2C / U0-U3

        ↓

[CURRENT]
H0  Runtime Hardening / Recovery / Build-Loop Cleanup

        ↓

U4  Extended Combat Relationship Graph

        ↓

U5  Generalized Designations / Persistent State

        ↓

PW0 Planeswalker Foundations
    ├─ PW0.5 Generic Chosen Values
    └─ PW0.75 Emblems

        ↓

R702  §702 Keyword Ability Sweep

        ↓

R701  §701 Actions + Special Game Operations

        ↓

PW1 Exotic Planeswalker Systems
    ├─ External / outside-game card sources
    ├─ Linked ability provenance
    ├─ Controlled-turn decision authority
    └─ Game epochs / Karn restart

        ↓

CMD Commander

        ↓

MP Multiplayer

        ↓

PW2 Full Planeswalker Certification
        🔒 HARD PRE-UNFINITY GATE

        ↓

SUP Supplemental Product Coverage

        ↓

UNF Unfinity / Acorn / Intentional Weirdness

        ↓

Final completeness testing
UX polish
Packaging / installer
Closed beta
Release candidates
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
