featurelist

- context-based menu for cards

- could do do a sims-like web  menu where one clicks on a highlighted card to bring up options.  
These would include Tap abilities, Pump abilities, Sacrifice abilities, and any other action such as "Whenever you X you **may**...{action}"
- overhaul interactivity
- ability to mulligan on each player's first turn
- chat and diagnosticss ovrerhaul
sshould be able to toggle whether or not tapping is automatic or should require human input to proceed (PROVIDED THAT IT IS A HUMAN'S TURN! Forgebot-controlled players will also auto-tap)

- prepared spells and indication

-  prototype abilities
- Unearth

- if  graveyard choices exceed a number set in config, they should be grouped into GRAVEYARD ACTIONS or some kind of folder

- physical preferred (with UI fallback) for Delve abilties

- functionality for abilities that allow you to search enemy's hand (could just parse them into a list for now, but eventually we'll want to physicall reveal their hand until they submit and confim a choice)

- Bug (UI) when a player needs to discard a card, it should indicate why (if it was a spell, it should glow red or yellow, with a messsaage on the HUD or the chat. if due to hand size, the hand should glow red)
NOT FIXED

- When cards enter the battlfield they change size.  This should be disabled to provide ample width for the keywords
NOT FIXED

- large armies: when there are too m any carsd on the battlefield to count, we need a cleanup to regain space just from organization, but also ways to utilize stacks of tokens.  This my entail a way to promppt the player how many attackerss thye wish to attack with with if they select a stack (we could use T:# / U:# to reresesn numbrer  of untapped and tapped in a stack)

- one should not be able to crew a vehicle if its already been converted into an artifact creature, mount, or otherwise (unless game logic needs this for combos)
NOT A BUG — Forge owns Crew legality; the bridge must not locally prohibit this action

Bug: cannot select attackers  by clicking on card (UI button works), noticed on crewed vehicle

Bug: token fetching fails to resolve to the proper token when the attack ability of prodigy's prototype activates. 
FIXED GENERICALLY — exact normalized token identity is required; LIVE CONFIRMATION PENDING

bug: an additional token  is created when only one shuold be spawned during prodigy's prototype activation
LIVE CONFIRMATION PENDING — exactly-once materialization guard is present; no card-name special case added

UI BUG: dropdown for bug selection is broken, no menu or choices appear, just a checkbox

Bug: lita, mechanical engineer does not fetch the appropriate card when activating her mana ability
FIXED GENERICALLY — token/card lookup no longer accepts fuzzy name collisions; LIVE CONFIRMATION PENDING

Bug: when crewing, player cannot select creature to tap, it is chosen for them (NOTE: this could be an artifact of SMART play, this sshould not be considered smart behavior and must collect a human choice before proceeding to tap anything)
IMPLEMENTED GENERICALLY — TUI cost-decision seam exposes Forge-valid aggregate candidates; LIVE CONFIRMATION PENDING

bug: if white is attacking, we have to pass priority to advance even though it's blue selectting blockers that would ideally be where priority passess from them to us, rather than us gating progresssion 

Bug: pilot tokens are viable blockers, but for some reason don't get considered as such when blue attacks
LIVE CONFIRMATION PENDING — Forge producer path includes Forge-valid creature tokens; exact physical mapping still needs canary

Flaw: blocking selection does not allow defenders to select which creature they wish to have it block, or multiples if they want it to block multiple creature.   Heavily lean on arena's gameplay solution to this **where you can select attacker -> blocker(s) relations, as opposed to the current sequential advance through each attacker in a given combat step
DEFERRED TO U4 — new generalized multi-blocker/assignment relationship architecture is out of U2 scope

- for multiplayer to work, UI code needs to be injected clientside

- optional choices like pay 2 land to have a land enter untapped are  not presented to the player

bug: sagas and classes do not have a level counter on them (might be called loyalty by the encoder)
IMPLEMENTED GENERICALLY — named-counter fallback retries after temporary Encoder unavailability; NEEDS LIVE CONFIRMATION

- feature: use Arena-style "Card Carousel" in the UI.  Ideally this comes up in a new modal.  Main point is to mimic Arena's usage of card art within UI elements

bug: terramorphic expanse does not make it to the graveyard after being activated
FIXED GENERICALLY IN EMBODIMENT PATH — follows authoritative battlefield-to-graveyard transition; LIVE CONFIRMATION PENDING


bug: Mulligan of opening hands sstill places them on top of the library face-up
FIXED

CRITICAL BUG: attempting to play a land on your draw step results in skipping straight to combat phase
NOT A BUG — lands are normally illegal during Draw; verify the subsequent Main 1 decision instead


Bug: lands can get misplacedin the creatures row, vice versa for  blue seats
FIXED GENERICALLY — battlefield row fallback derives from Forge current types; LIVE CONFIRMATION PENDING

bug: UI presents your next card before you should have access to this information (e.g before it reaches the hand)
FIXED 122d25d

Bug: cannot cast sorceries before combat
FIXED

CRITICAL: sorceries with graveyard return is failing. the choice accepts but no functionality ensues and the card goes unconsumed despite it advancing the phases which is inappropriate--see logs using Tune Up
NEEDS LIVE CONFIRMATION

Bug: Casting a creature can  take up to an entire  turn for it to move from this weird area I call the "cast zone"   to its correct place on the battlefiedl
NEEDS LIVE CONFIRMATION

Bug: Main 1 still gets skipped 
FIXED

Bug: the option to play a land does not get checked until  the next phase, it needs to be checked on every relevant choice
FIXED

Bug: Crewing a creature from the UI fails, it does not initiate anythhing  (observed during combat:pre)

bug: player is offered choices they should not have (instants and things with flash get this, but  not playing lands; after a mulligan their choices show before the cards are in the hand)
NEEDS LIVE CONFIRMATION

bug: next card is revealed through choices presented from the UI
IMPLEMENTED — exact hand embodiment gate plus FAST-mode idle backoff preservation (`2eedd16`); NEEDS LIVE CONFIRMATION

UI BUG: user is not prompted to discard a card when the choice is presented after a mulligan, highlights should appear orange during the discard, and blue after opting to keep theh card but ESPECIALLY before the combat phase
NOT FIXED

bug: you can only highlight one card max for attacker selection, multiple ones are available if done through the UI

BUG: main 1 phase is skipped on to combat turn 1
FIXED

BUG: valid choices are not presented until both are satisfied - A the combat step is reached and B - the user has clicked Done on the UI
FIXED?

BUG: you can multi-select during times when it does not make sensse to be able to do so (draw step provided max  hand size is not forcing a discard)
FIXED

BUG:  when casting mental note, the top two cards must be transported from the top of library to the  graveyard face-up before the draw triggers. 
FIXED as of 8-30-u2-gameplay-repair

FLAW/FEATURE: there is no visible or configurable manner of how first-order of play should be determined.  Release behavior is to simultaneously physically roll a die (there are bags of all size of dice on the table already, though a d6 and d20 are already placed  on every battlefield) for all players, re-rolling on ties as necessary.  This is the behavior for "Dice" option.  A debug option should allow you to manually set the color and direction of play, defaulting to clockwise.
NOT IMPLEMENTED 

Bug: mana counters do not face the respective seat.  For white, counters sshould be rotaatedd 90  degrees clockwise
NOT FIXED

Bug: mana counters do not update properly using spells like Dark or Cabal Ritual
AWAITING CONFIRMATION

Bug: mulliganing causes a desync followed by errors on each card  move (the cards still  move and the hand EVENTUALLY cycles)
SEEMINGLY FIXED

Bug: highlights fail to appear on a mulliganed hand
IMPLEMENTED — structured Forge collections, including mulligan bottom selection, use blue legal-choice highlights; NEEDS LIVE CONFIRMATION

Critical: reporting a bug or capturing a freeze softlocks the process from progressing (suspected to be on a per-match basis) 
RESURFACED - NOT FIXED

Bug: hands are not properly cleaned up when destructively requesting to start a new match
FIXED

CRITICAL BUG: 
Card importer is broken with the current UI.  
Workaround: clearing the Global.xml restores card importer functionality
NOT FIXED

Bug: 
opening the card importer breaks the custom UI such that it takes up the entire screen
WAS FIXED - HAS RESURFACED

Bug: cannot play lands already in hand on draw nor upkeep steps, must wait for combat to pass
NOT FIXED 

Bug: casting stitcher's suppplier failed to trigger the mill-adjacent effect that mental note shares
FIXED

Bug: you can select spent instants as attackers 
NOT FIXED

Bug: passing priority on the upkeep step skips Main 
NOT FIXED

Bug: YIELD TURN does not pass priority during opponent's steps, seems to be defunct
NOT FIXED

Bug: legal actions don't appear until combat step, they should be displayed by the upkeep step. (Acceptance: drawing the new card should present new options, and playing a land pre-main 1 should be presented so it can be enqueued)
NOT FIXED

CRITCAL: Effects from Young Pyromancer fail to trigger.


Bug: Land cannot be played before combat due to main 1 consistently being skipped
NOT FIXED

Bug: YIELD TURN is missing during Blue's turn (should advance until human intervention required OR turn change)
FIXED

Bug: casting thought scour picks up played lands and the already milled card back into the libray
FIXED

Bug: casting Thought Scour inappropriately highlights after the effects have physically finished
NOT FIXED


Bug: resync does not sseem to do anything
IMPLEMENTED — bootstrap staging now serializes verified library containment before strict duplicate audit (`b3aa409`); NEEDS LIVE CONFIRMATION FROM A CLEAN TABLE

(high priority) Bug: if a player opts to keep the opening hand, it can sometimes still gets mulliganned
NEEDS LIVE CONFIRMATION

bug: sacrifice cards say "sacrifice CARDNAME" instead of the actual card's name
NOT FIXED

Bug: Consider does not resolve at the appropriate speed

Bug: Sacrificing a tapped permanent does not untap it before transporting to its destination (exile or graveyard) is complete
NOT FIXED

bug: application does not safely shut down, must be crtl+shift+c interrupted
FIXED

==========================
Live smoke matrix:

P0 — Real spell-copy identity: Reverberate / Narset’s Reversal / Dualcaster. Cast something simple like Consider, copy it, and watch the original and copy independently. The copy should never steal the original GUID, move the original card, or require a physical deck card. Then use Narset’s Reversal, because it is particularly vicious: the virtual copy resolves while the original physical spell returns to your hand. If the original instead goes to graveyard, vanishes, gets duplicated, or remains stranded at the stack anchor, capture immediately. The U3 model deliberately records virtual copies without materializing them, so this is the cleanest proof that the model actually works end-to-end rather than only in DTO tests.
UNTESTED

P0 — Prototype regression. This one jumped out at me during the audit. The producer currently treats card.isCloned() as evidence that something is a copy. But Prototype already required us to deal with Forge’s internal clone-state machinery separately during U2. I therefore want at least one Prototype card in the test gauntlet. Confirm that a physical card cast for its prototype cost remains the same physical original object, not copy-permanent, and does not suddenly get a cloned TTS embodiment. I’m not asserting Forge's isCloned() definitely returns true for Prototype—I’d want the Forge implementation inspected before claiming that—but the overlap is suspicious enough that this deserves a regression test.
UNTESTED

P0 — Virtual spell → physical permanent: Double Major. This is probably the single strongest U3 lifecycle test. Copy a creature spell with Double Major. While on the stack, the copied spell should be virtual. When it resolves into a token copy, a new physical embodiment should appear exactly once with a new GUID, while the original creature spell follows its ordinary physical-card lifecycle. This tests the transition from “authoritative identity with no TTS object” to “authoritative identity that now requires embodiment.” Immediately RESYNC afterward. If you get zero copies, two copies, an ordinary-card-not-found desync, or a second copy after RESYNC, we have a very useful U3 bug.
UNTESTED

P0 — RESYNC while materialization is still in flight. This is the race I’m most suspicious of. The latest fixes very carefully fence library queues before snapshot reconciliation/resync, because Thought Scour exposed exactly that class of asynchronous race. But U3 now also has asynchronous token/copy creation. I have not seen an equivalent broad “all U3 materializations are idle” fence around RESYNC. So kick Rite of Replication or produce several copies, and hit RESYNC while objects are visibly still appearing. Watch for a late callback from the old presentation generation creating an orphan or a duplicate after the resync has rebuilt state.
UNTESTED

P1 — Copy source disappears before the copy is embodied. Copied permanents are currently materialized by looking up originObjectId, resolving its GUID, then calling origin.clone(...). That is elegant when the source still exists physically. The interesting case is when the source is bounced, sacrificed, destroyed, exiled, or otherwise leaves before TTS gets around to materializing the copy. Try creating a copy and arranging for the source to disappear during the same stack sequence. Watch for failure to produce the copy, a fallback to the wrong same-name object, or a hard “ordinary deck card not found” error.
UNTESTED

P1 — Copy-of-copy lineage. OriginObjectId and CopySourceObjectId are currently11 both populated from the same card.getCloneOrigin() value. That means the model technically has two provenance fields, but the producer does not yet demonstrate different semantics for “ultimate physical origin” versus “immediate object copied.” Make copy A, then copy A to produce B. Pay attention to whether B inherits from A or mysteriously jumps back to the original. The final authoritative characteristics may still be correct, but this is exactly where provenance shortcuts become visible later.
UNTESTED

P1 — Cloned TTS state contamination. origin.clone() clones the whole TTS card object before Forge-authoritative characteristics are reapplied. Make the source ugly first: put +1/+1 counters on it, tap it, give it a named counter if possible, have an Encoder property/badge/keyword applied, then copy it. The new permanent should ultimately show whatever Forge says the copy has—not accidentally preserve TTS-local state copied from the source. Particularly watch for copied counters, stale tapped state, prototype/prepared badges, buttons, decals, and Encoder metadata that Forge says should be absent.
UNTESTED

P1 — Temporary-copy retirement: Twinflame / Heat Shimmer. Produce a temporary copy that must disappear at end step. Verify it disappears once, its GUID/mapping is gone, and RESYNC does not resurrect it. I found lots of session/reset cleanup and normal zone-transition cleanup, but I did not find an obviously dedicated generic “authoritative U3 generated object disappeared, therefore retire its physical embodiment” subsystem in the pieces I inspected. That doesn't prove retirement is broken—the ordinary event path may handle it perfectly—but it makes this a worthwhile live test. U3’s authoritative-object metadata itself is maintained separately from GUID mappings and reset during session preparation.
UNTESTED

P1 — Mass same-name creation: kicked Rite of Replication. This should produce exactly five new identities. Count them. Then RESYNC. Count again. Then interact with individual copies if possible. This hammers exactly-once materialization and identity mapping when every object has the same printed/current name. The latest resync work now deliberately prefers preserved exact GUID mappings over by-name fallback, which is encouraging, but mass copies are a much harder version of the same problem.
UNTESTED

P1 — Generated object as a later action source. Once a copied/token creature exists, don't merely look at it—use it. Attack with it, activate an ability, target it, sacrifice it, Crew with it, or block with it. Snapshot IDs are normalized into session-scoped IDs such as forge:<session>:<id>, while some TUI provenance still originates as forge-object:<id>. If you ever see a perfectly visible generated card that cannot receive a highlight/action because “exact physical mapping” is missing, that is where I'd start looking.
UNTESTED

P2 — Token-copy classification. Forge's producer gives token status precedence when choosing objectKind: token cards become forge-token, even if isCopy is separately true. That's not inherently wrong—the two concepts really are orthogonal—but it means any consumer that later assumes objectKind=="copy-permanent" is the only way to recognize copied permanents could miss token copies. Test Twinflame/Quasiduplicate on a token, and copy an already-copied token if Forge permits it.
UNTESTED

P2 — Freeze test: kicked Rite + immediate RESYNC. The modularization landed, and some lookup caching landed too, but bootstrap/reconciliation still contains intentional whole-table/inventory work such as getAllObjects() scans. The named-presentation cache reduces one kind of scan, not every scan. Mass creation followed by RESYNC is probably the best U3-era freeze workload. If TTS hard-freezes, let it recover and hit CAPTURE FREEZE immediately; the wall-clock recorder should now tell us whether snapshot reconciliation/materialization is actually the culprit.
UNTESTED


Bug: Upkeep pass → Draw → Main 1: land/sorcery/instant actions exactly as Forge offers.
NOT FIXED

- Permanent hand → stack → battlefield promptly after Forge event.

- Yield visibility and normal single-action decision behavior.

Bug: you cannot play cards pre-combat on first turn for some reason

Bug: lotus petal prompts the uses to sacrifice it when its already in the graveyard

Bug: lotus petal does not move the top three cards of library to graveyard