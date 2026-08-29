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

- when a player needs to discard a card, it should indicate why (if it was a spell, it should glow red or yellow, with a messsaage on the HUD or the chat. if due to hand size, the hand should glow red)

- When cards enter the battlfield they change size.  This should be disabled to provide ample width for the keywordss

- large armies: when there are too m any carsd on the battlefield to count, we need a cleanup to regain space just from organization, but also ways to utilize stacks of tokens.  This my entail a way to promppt the player how many attackerss thye wish to attack with with if they select a stack (we could use T:# / U:# to reresesn numbrer  of untapped and tapped in a stack)

- lands are still very freeform.   there sshould be a config ssetting to enforce strict land placement

- one should not be able to crew a vehicle if its already been converted into an artifact creature, mount, or otherwise (unless game logic needs this for combos)

Bug: cannot select attackers  by clicking on card (UI button works), noticed on crewed vehicle

Bug: token fetching fails to resolve to the proper token when the attack ability of prodigy's prototype activates. 

bug: an additional token  is created when only one shuold be spawned during prodigy's prototype activation

Bug: lita, mechanical engineer does not fetch the appropriate card when activating her mana ability

Bug: when crewing, player cannot select creature to tap, it is chosen for them (NOTE: this could be an artifact of SMART play, this sshould not be considered smart behavior and must collect a human choice before proceeding to tap anything)

bug: if white is attacking, we have to pass priority to advance even though it's blue selectting blockers that would ideally be where priority passess from them to us, rather than us gating progresssion 

Bug: pilot tokens are viable blockers, but for some reason don't get considered as such when blue attacks

Flaw: blocking selection does not allow defenders to select which creature they wish to have it block, or multiples if they want it to block multiple creature.   Heavily lean on arena's gameplay solution to this

- for multiplayer to work, UI code needs to be injected clientside

- optional choices like pay 2 land to have a land enter untapped are  not presented to the player

bug: sagas and classes do not have a level counter on them (might be called loyalty by the encoder)

- feature: use Arena-style "Card Carousel" in the UI.  Ideally this comes up in a new modal.  Main point is to mimic Arena's usage of card art within UI elements

bug: terramorphic expanse does not make it to the graveyard after being activated


bug: Mulligan of opening hands sstill places them on top of the library face-up

CRITICAL BUG: attempting to play a land on your draw step results in skipping straight to combat phase

Bug: lands can get misplacedin the creatures row, vice versa for  blue seats

bug: UI presents your next card before you should have access to this information (e.g before it reaches the hand)

Bug: cannot cast sorceries before combat

CRITICAL: sorceries with graveyard return is failing. the choice accepts but no functionality ensues and the card goes unconsumed despite it advancing the phases which is inappropriate--see logs using Tune Up


Bug: Casting a creature can  take up to an entire  turn for it to move from this weird area I call the "cast zone"   to its correct place on the battlefiedl

Bug: Main 1 still  gets skipped when certain cards are played (lands, casting any type of spell)

Bug: Crewing a creature from the UI fails, it does not initiate anythhing  (observed during combat:pre)

bug: player is offered choices they should not have (instants and things with flash get this, but  not playing lands)

bug: next card is revealed through choices presented from the UI

bug: you can only highlight one card max for attacker selection, multiple ones are available if done through the UI