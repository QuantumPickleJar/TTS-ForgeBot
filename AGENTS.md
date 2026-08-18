# AGENTS.md

## Project

**Working name:** MTG TTS Bot Bridge

This repository is a rapid prototype for playing **single-player Magic: The Gathering in Tabletop Simulator** against a Forge-controlled AI.

The first target is **1v1, 60-card Standard**. Commander, multiplayer, deck persistence, broad format support, and polished distribution are explicitly later concerns.

The prototype is being developed under a **hard two-hour implementation timebox**. Prefer a narrow end-to-end vertical slice over broad but incomplete infrastructure.

---

## Core Architecture

There are three authorities in the system:

1. **Forge owns Magic truth.**
   - Forge is authoritative for game state, legality, priority, phases, the stack, combat legality, targeting, triggers, costs, resolution, win/loss state, and AI decisions.
   - Do not reimplement Magic rules in C# or Lua.

2. **Tabletop Simulator owns embodiment and interaction.**
   - TTS represents cards, zones, highlights, buttons, physical movement, visible state, and player interaction.
   - TTS should present choices from Forge and collect player intent.
   - TTS is not authoritative for rules legality.

3. **MtgTtsBridge owns synchronization.**
   - The bridge maps TTS objects/GUIDs to Forge identities.
   - It transports player intent to Forge and Forge decisions/state changes to TTS.
   - It supervises the Forge process, logs protocol traffic, detects synchronization failures, and fails safely.

Keep these boundaries intact.

---

## Prototype Goal

The first useful vertical slice is:

- Start a local bridge.
- Start or attach to a local headless Forge process.
- Start a two-player game with one human-controlled seat and one Forge AI seat.
- Load simple 60-card test decks.
- Expose Forge's currently legal human actions to TTS.
- Highlight legal human card actions spatially in TTS.
- Let the player choose an action using normal TTS interactions.
- Highlight required targets spatially.
- Allow the player to cancel an uncommitted interaction.
- Automatically advance through phases/priority when no meaningful human decision is required.
- Let the player use an **End Turn / yield** control that means "auto-pass unless a meaningful decision requires me."
- Let the Forge AI take its turn.
- Reflect AI actions physically in TTS at understandable human speed.
- Stop safely on desynchronization or unsupported interaction.

A full polished match is desirable, but a smaller verified path is preferable to speculative completeness.

---

## Scope Guard

### In scope for the prototype

- 1v1.
- 60-card Standard-style decks.
- Simple creatures.
- Lands.
- Straightforward sorceries.
- Straightforward instants.
- Simple targeted spells.
- Basic activated abilities if Forge exposes them cleanly.
- Ordinary combat.
- Human versus Forge AI.
- Localhost-only bridge communications.
- Desktop and VR-compatible interaction from the same implementation.

### Explicitly out of scope unless requested

- Commander rules.
- Commander tax/damage/command zone.
- 3+ players.
- Multiplayer political AI.
- Deck saving/persistence.
- Matchmaking.
- Remote bridge hosting.
- Accounts/authentication.
- Custom MTG rules implementation.
- Exhaustive support for every card mechanic.
- Reproducing MTG Arena's UI.
- Separate VR UI.
- Elaborate installer/updater.
- Production security hardening beyond safe localhost defaults.
- Premature abstraction unrelated to the vertical slice.

When time is constrained, remove scope rather than weakening architecture boundaries.

---

## VR and Interaction Requirements

**VR compatibility is a first-pass requirement, not a later port.**

Every core gameplay action must be possible without requiring:

- keyboard input,
- mouse-only gestures,
- a conventional screen-space menu,
- tiny controls,
- text entry during play.

Prefer:

- physical tabletop objects,
- normal card grabbing/pointing,
- large world-space buttons,
- scripting zones,
- spatial highlights,
- visible object motion,
- simple point-and-activate interactions.

Desktop shortcuts may exist, but they must be optional enhancements.

### Spatial interaction language

Use a small, consistent set of spatial cues.

Recommended semantics:

- **Light blue highlight:** currently legal/selectable action.
- **Orange highlight:** target or follow-up choice required by an action in progress.
- **Red highlight/flash:** rejected or illegal physical interaction.
- **No highlight:** no currently offered action.

Do not rely on color alone when a second cue is inexpensive. Object motion, labels, or temporary state markers may supplement highlights.

Avoid excessive floating UI.

---

## Turn and Priority UX

The player should not manually advance through every Magic phase.

Forge owns the actual phase and priority sequence.

The interaction layer should:

- auto-pass when Forge reports no meaningful human action,
- pause when a meaningful human decision exists,
- expose legal actions spatially,
- resume automatic advancement after the decision.

The physical **End Turn** control is conceptually a yield/autopass policy, not a rules shortcut.

Interpret it as:

> Auto-pass my priority for the remainder of this turn unless Forge presents a decision that should interrupt the yield.

Do not implement phase skipping independently of Forge.

---

## Action Preview and Cancel

Treat player manipulation as **intent** until Forge accepts/commits the action.

Desired flow:

1. Forge exposes legal actions.
2. TTS highlights corresponding objects.
3. Player selects/moves an object.
4. Bridge submits or stages the intent.
5. Forge requests any required choices, such as targets.
6. TTS highlights those choices.
7. Player chooses or cancels.
8. Forge commits/resolves the action.
9. TTS reflects the authoritative result.

Before commitment, **Cancel** should restore the interaction to the previous authoritative state when practical.

Never fabricate a legal resolution locally merely because the tabletop object was moved.

---

## Failure Policy

Prefer loud, recoverable failure over silent divergence.

If any layer cannot reconcile state:

- stop automatic progression,
- stop AI actions,
- remove misleading "legal action" highlights,
- log the discrepancy,
- surface a clear diagnostic state,
- preserve enough information for manual inspection.

Do not guess missing Forge decisions.
Do not continue from a known desynchronized state.

A future physical debug object may expose state such as:

- bridge connected,
- Forge connected,
- current turn,
- current phase,
- priority holder,
- pending decision,
- last rejected action,
- sync status,
- resync/dump/pause controls.

For early development, console/log output is sufficient.

---

## Forge Integration Strategy

Forge is an external dependency and should remain behind an adapter.

Use an interface such as:

```csharp
public interface IForgeAdapter
{
    // Exact members should follow implementation needs.
}
```

Do not let TTS-facing code depend directly on Forge's current draft protocol.

The first implementation may use a **headless/TUI adapter** if that is the fastest reliable path.

A later implementation may replace it with a structured JSON-RPC or other Forge adapter.

The rest of the application should not care which Forge transport is active.

### Forge process rules

- Run Forge locally on the host machine.
- Prefer process supervision by the bridge.
- Capture stdout/stderr.
- Use deterministic startup/configuration where possible.
- Fail clearly if the expected Forge build/version is unavailable.
- Do not vendor the Forge source tree into this repository unless explicitly instructed.
- Keep local Forge checkouts/build artifacts under a gitignored dependency directory such as `.deps/`.

---

## Bridge Requirements

Preferred stack: **.NET 8 / C#**.

The bridge should remain small.

Likely responsibilities:

- HTTP endpoint(s) for TTS.
- Forge process lifecycle.
- `IForgeAdapter`.
- action/choice contracts.
- TTS GUID ↔ Forge/card identity mapping.
- state/version correlation.
- structured logging.
- cancellation and timeout handling.
- sync detection.
- mock adapter for tests and TTS development without Forge.

Prefer typed contracts over anonymous dictionaries once a message shape becomes stable.

Do not add distributed-system complexity to a localhost prototype.

### Networking

Default to loopback only:

```text
127.0.0.1
```

Do not bind the prototype service to all interfaces unless explicitly requested.

TTS clients should communicate with the service running on the **host machine**.

---

## Tabletop Simulator Requirements

TTS scripting should be thin.

Lua may:

- call the bridge,
- listen to relevant TTS events,
- map GUIDs and scripting zones,
- display highlights,
- create/use physical buttons,
- preview/rollback tentative physical interactions,
- animate authoritative Forge actions,
- report player selections.

Lua must not:

- maintain a parallel implementation of Magic legality,
- independently resolve spells,
- independently decide valid targets,
- independently advance the rules engine,
- silently repair a Forge/TTS rules disagreement.

Prefer existing table/importer/helper scripts where they save time, but isolate our integration enough that another MTG table can be adapted later.

Do not hardcode "60 cards" into reusable game/deck abstractions. Standard is the current scope, not a permanent deck-size architecture constraint.

---

## Expected Repository Shape

Use this as guidance, not as an excuse for empty abstraction layers:

```text
mtg-tts-bot/
├── AGENTS.md
├── .gitignore
├── src/
│   ├── MtgTtsBridge/
│   │   ├── Api/
│   │   ├── Forge/
│   │   ├── Game/
│   │   └── Program.cs
│   ├── MtgTtsBridge.Contracts/
│   │   ├── Actions/
│   │   ├── Events/
│   │   └── State/
│   └── MtgTtsBridge.Tests/
├── tts/
│   ├── Global.lua
│   ├── interaction/
│   └── objects/
├── tools/
│   └── forge/
├── .dev/       # gitignored
└── .deps/      # gitignored
```

Collapse directories if the prototype does not yet justify them.

---

## Documentation and Repository Privacy

During development, assume the repository is private.

**Do not create committed Markdown planning/task files unless explicitly asked.**

`AGENTS.md` is the durable agent-facing repository contract.

Task-specific Codex prompts should be supplied externally rather than committed as files.

Use `.dev/` for local private/disposable notes and keep it gitignored.

Examples of files that should normally NOT be committed:

```text
.dev/
TASK*.md
PLAN*.md
NOTES*.md
PROMPT*.md
codex-*.md
scratch/
logs/
transcripts/
```

Do not create a public-facing `README.md`, design document, roadmap, or architecture document unless explicitly requested.

If documentation becomes necessary later, confirm whether it should be public before committing it.

---

## Codex Working Rules

When performing a task:

1. Read this file first.
2. Inspect existing code before inventing replacement architecture.
3. Preserve the Forge/TTS/bridge authority boundaries.
4. Keep the requested task narrow.
5. Prefer the smallest end-to-end working increment.
6. Add or update tests for deterministic bridge behavior.
7. Do not silently broaden scope.
8. Do not add dependencies without a concrete reason.
9. Do not create extra Markdown planning files.
10. Report blockers directly rather than filling gaps with invented behavior.

If the task prompt conflicts with this file, the explicit current task wins, but call out the conflict.

---

## Testing Strategy

Prioritize deterministic tests that do not require launching TTS.

### Bridge unit/integration tests

Test:

- Forge output → structured bridge decision.
- bridge choice → Forge input.
- action IDs remain stable within a decision.
- target/follow-up choices.
- pass/yield behavior.
- malformed/unexpected Forge output.
- process exit.
- timeout/cancellation.
- state mismatch handling.

Where practical, capture small Forge transcripts as test fixtures.

If transcript fixtures are committed, keep them minimal and scrub machine-specific paths or private data.

### TTS smoke test

Before real Forge integration, support a mock bridge response capable of proving:

```text
TTS → localhost bridge → mock legal actions → TTS highlight/selection → bridge
```

This is a key early milestone.

### Initial gameplay fixtures

Use intentionally simple decks first.

Avoid exotic mechanics until basic integration is proven.

The purpose of the first decks is to diagnose the bridge, not stress Forge's card coverage.

---

## Definition of Prototype Success

Within the timeboxed prototype, success means demonstrating as much of this path as possible:

```text
TTS starts
  ↓
Bridge reachable
  ↓
Forge reachable
  ↓
Game state initialized
  ↓
Human receives legal action(s)
  ↓
TTS highlights valid choice
  ↓
Human selects in desktop OR VR-compatible fashion
  ↓
Target choice is shown if needed
  ↓
Forge accepts and advances authoritative state
  ↓
TTS reflects result
  ↓
AI receives control and takes an action
  ↓
Control returns to human
```

A single reliable turn cycle is more valuable than many half-implemented mechanics.

A complete simple match is the stretch target.

---

## Timebox Discipline

This prototype has a **hard two-hour cap**.

Agents should optimize for information gained and vertical-slice progress.

When encountering a choice between:

- polishing versus completing the loop,
- generalized infrastructure versus a working adapter,
- several mechanics versus one verified mechanic,
- replacing an existing workable component versus adapting it,

prefer the option that gets the end-to-end loop working sooner.

Do not spend the sprint on:

- speculative refactors,
- exhaustive card/mechanic support,
- elaborate UI polish,
- packaging,
- Commander,
- documentation expansion.

At the end of the sprint, leave the repository in a state that clearly shows:

- what works,
- what was mocked,
- what failed,
- the next smallest useful step.

Use code comments, test names, issue notes, or the final task report for that information rather than creating extra Markdown documents.

---

## Engineering Style

- Prefer clear C# over clever C#.
- Prefer async I/O for process/network interaction.
- Use cancellation tokens where operations can hang.
- Avoid static global state unless TTS integration genuinely requires it.
- Keep protocol parsing isolated from game orchestration.
- Log protocol boundaries at debug/trace level.
- Never log hidden-information card data to a client that should not receive it.
- Keep message contracts versionable where inexpensive.
- Treat TTS GUIDs as physical-object identifiers, not canonical Magic card identity.
- Preserve a path toward swapping TTS tables and Forge transports independently.

The prototype may contain tactical shortcuts. Put shortcuts behind clean boundaries whenever doing so is cheap.

The governing rule remains:

> **Forge owns truth. TTS owns embodiment. The bridge owns synchronization.**
