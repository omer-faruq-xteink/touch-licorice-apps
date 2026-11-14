# Port Wren: a detective game in a harbour town (design)

Status: draft, 2026-11-14. Not committed until the device test passes (the user's rule).

This is the first of three new games the user asked for. They are built in this order, each fully finished
and device-tested before the next: the detective game (this doc), then a village builder, then a polar
expedition. Those two get their own design docs later.

## Intent

The user wants a game for the Xteink X4 Pro (e-ink, 480x800, touch) that is more complex than Delve,
our small roguelike, with a completely different setting and style of play. Among three concepts the
user liked this one: generated murder cases in a small 1920s harbour town. You visit places, question
suspects, show them clues, tie clues to suspects on a board, and name the culprit, the motive and the means.

Why this one fits the device: it is a reading game. The reader is built for reading, every input is a tap,
nothing moves between taps, and a case can be left and resumed at any moment. Because cases are
generated, the answer can't be looked up, and every case plays differently.

## Goals

- **Generated cases.** Every case is new, consistent and solvable by reasoning from the clues the game
  gives. The generator builds the truth first, derives the clues from it, and a solver inside the game
  proves the case can be solved before the player sees it.
- **Case length setting.** Short (the default) or Long, always available in Settings and taking effect
  from the next case:
  - **Short:** 4 suspects, 5 places, about 10 clues; one sitting of 20-30 minutes.
  - **Long:** 6 suspects, 7 places, about 16 clues, including 2 false trails; about an hour, spread
    over several sittings if the player likes.
  - **What a false trail is (my call):** a true but misleading fact, such as an innocent who had a motive,
    was near the scene, or owns an object like the weapon. Evidence is never planted or false, so the
    solver can treat every physical clue as true. False trails are separate from the Innocent liar pattern.
- **Solving is mixed: elimination, then catching a lie.** Each case is built on one of four patterns,
  picked at random among those the player's rank has unlocked:
  - **Classic** (the most frequent): the clues eliminate all but 2 suspects; the last step is catching
    the killer's lie, a statement contradicted by a clue.
  - **False alibi:** every suspect has an alibi, but a witness lies to cover the killer. Catching the
    witness breaks the killer's alibi.
  - **Timeline:** times matter (the ferry leaves at 9, a stopped clock, the tide). The killer is the only
    one whose movements fit the time of the crime.
  - **Innocent liar** (Long cases only): someone else also lies, to hide something unrelated (smuggling,
    an affair, a debt). Not every lie is about the murder; the secret can be found, and that clears them.
  - **The pattern is not shown to the player during the case (my call):** finding out what kind of case
    it is is part of the game. The end screen names it. All four patterns are solved under the same
    reasoning rules (see The solver), so the player never needs to know the pattern.
- **A wrong accusation lets the killer strike again.** A wrong culprit means a new victim, new clues, and
  the case goes on. A second wrong accusation means the killer flees town: the case is lost and the real
  solution is shown (the user picked "the killer strikes again"; the second-strike rule is my call).
- **A town with a memory, and rank.**
  - **The townspeople:** 20-30 fixed people, and every case is made from them. The innkeeper you wrongly
    accused in case 4 trusts you less when she is a witness in case 7. The dead and the jailed leave the
    town. When the population drops, new people move in. A newcomer has no history with anyone (my call).
  - **Rank:** solving earns reputation, and rank rises: Constable, Sergeant, Inspector, Chief Inspector.
    Rank unlocks the harder patterns: Classic from the start, then False alibi and Timeline, Innocent
    liar last. Rank does not lock the Long setting (my call, so players can play the way they like).
- **Two ways to play,** chosen when a game starts:
  - **Career** (the default): the town with a memory, and rank.
  - **Single cases** (the user's idea): every case happens in a newly generated town, with no memory and
    no rank, and all four patterns open from the start (Innocent liar still only in Long).
  - Settings has **Reset career**, which asks first.
- **As much variation as possible** (the user's general preference for games): the 1st and the 10th
  play should feel different.
  - Each town is generated, with new people, names and relationships, and 10 places drawn from a pool of
    about 16.
  - Patterns, motives and means vary per case.
  - Every text template has several variants.
- **Everything saved on every tap**, like our other games.

## Non-goals (v1)

- Multi-evening cases with sub-plots.
- A story arc running across cases.
- Today's case (one shared seed per day, like Delve's daily dungeon).
- AI-written dialogue or anything that needs the network.
- Landscape layout.
- Translations: the text is English, like our other apps.

## Anti-goals (a failure even if it works)

- **A case that can't be solved,** or has two defensible answers. Every case must reach exactly one
  culprit, motive and means from the clues the player can get.
- **A clue the player can't reach.** Low trust may make a clue cost more time; it must never make it
  unavailable.
- **Text that contradicts the facts.** A sentence saying 9 pm when the truth is 10 pm breaks the game.
  Text is generated only from the truth model, never written around it.
- **Waiting on a frozen screen.** Making a case takes time on the device. It runs in slices behind a
  "Preparing a new case…" screen and never trips the host's time limits.
- **Gore.** Deaths are reported, not described: period-detective tone.
- **A recreation of an existing game:** names, town and characters are original.

## Constraints (platform facts)

- **Screen and input:** 480x800, 1-bit e-ink. A frame costs roughly 0.5-0.65 s, so a tap that changes
  the screen redraws once. Touch, and the Back key.
- **Time limits:** 1000 ms for an input callback, 1500 ms for `on_draw`. An `on_draw` over 1500 ms is
  killed silently. `ctx.budget:extend()` exists for heavy work, and long work runs in slices through
  `ctx:after`, the way the Checkers engine thinks (apps/checkers).
- **Code loading:** `require` of other package `.lua` files works on current firmware and is lazy;
  compiling costs about 1.4 ms per KB. Optional heavy parts live in their own files, loaded with
  `_G.require` (the bundle's local `require` shadows the host's), as in apps/calculator/modes.
- **Draw commands:** about 1024 per frame at most (Checkers keeps under 900).
- **Files:** `ctx.store`-style text files, as our other games use.
- **Back key:** a short Back sends down, then up, and only the up event's return value counts. The
  outermost screen returns false on up, so the host offers to exit; inner screens go back a level.
  Use the pattern in apps/checkers/src/main.lua, and test it with down then up.
- **Firmware:** the newest. No fallbacks for older firmware (the user's rule until general
  distribution). The manifest `api` is the lowest version that covers what the app uses.

## Approaches considered

- **A. Solution-first generation (picked).** Build the truth (victim, killer, motive, means, time, and
  everyone's real movements), derive clues and lies from it according to the pattern, then run a solver
  that reasons only from the clues the player can get. Discard and retry until exactly one answer
  remains.
  - Pros: every case is consistent and provably solvable, which tests can check over thousands of seeds.
  - Cons: the most work; generation must be sliced on the device.
- **B. Hand-written case skeletons** (about 30 plans, roles filled from the town). Better prose and an
  easy generator, but it repeats after 20-30 cases and ties weakly to the town's memory. Rejected:
  against "every case is different".
- **C. AI-written dialogue** on top of A. Needs the network, an API key and money, and the text can
  contradict the clues. Rejected for an offline game.

The accepted cost of A is that text comes from template sentences with variations (per clue type, role
and mood). With enough variants it reads naturally, but it is not novel prose.

## The design

### The town

Made once, when a career starts, from a seed:
- **24 people** (the population is kept between 20 and 30). Each has:
  - a name, from original period name lists;
  - an occupation, tied to a place (innkeeper, ferry master, harbour clerk, doctor, fishwife, chaplain…);
  - two traits from a small set (nervous, proud, honest, gossip, greedy, loyal…);
  - trust toward the detective (0-100, starting near 50);
  - a status: alive, dead, jailed or moved away;
  - a short history of what the detective did to or with them, used in dialogue ("You arrested my
    brother in the spring.").
- **Relationships**, made at town creation and growing with cases: spouse, sibling, employer, debtor,
  rival, lover, old grudge. Motives come from these.
- **Places:** 10 places per town, drawn from a pool of about 16, for example the Anchor inn, the harbour office, the ferry pier, the
  fish market, a warehouse, the chapel, the doctor's house, the lighthouse, a boarding house, the bank.
  A Short case uses 5 of them and a Long case 7.

### A case: the truth model

- **The crime:**
  - a victim (a living townsperson) and the killer (another);
  - a motive from their relationship: debt, inheritance, jealousy, blackmail, revenge or a secret
    exposed;
  - a means the killer had access to: poison, a blunt object, a knife or drowning, each tied to places
    and occupations;
  - a place, and a time slot.
- **The evening:** split into 30-minute slots (for example 18:00-24:00, 12 slots). Every suspect has a
  true location for every slot, and the killer's path reaches the crime scene at the crime slot.
- **The crime slot is known from the start in most patterns (my call):** the doctor's examination gives
  it. In Timeline the doctor gives only a window of 3-4 slots, and time clues (a stopped clock, the tide,
  the ferry) narrow it to one. The solver derives the slot first, then applies the other rules.
- **Suspects:** the killer plus 3 (Short) or 5 (Long) others. Each innocent has a reason to look
  suspicious (a motive, access to the means, or being nearby), so elimination needs clues.

### Clues and statements

Clues are derived from the truth. Types:
- **Physical:** found by searching a place. It points to a means, a person or a time (a torn ferry ticket,
  a cellar key, a cup of cold tea).
- **Testimony:** a witness saw person X at place P at time T.
- **Documents:** they show a motive or a relationship (a ledger page, a letter, an IOU).
- **Observation:** something noticed while questioning someone ("her hands are wet: salt water, not beer").
- **Statements:** each suspect's own account of their evening, slot by slot. The killer lies about at
  least the crime slot. Under False alibi, a witness lies to back the killer up. Under Innocent liar,
  an innocent lies about a slot to hide a secret, and that secret has its own discoverable clue.

**Getting a clue:** a clue is gated by an action. You visit and search a place, ask someone about a topic,
or show a clue to someone. Some clues need an earlier clue shown first. The gates form a graph with no
cycles, and every clue the solution needs is reachable.

**Trust:** low trust makes a person need an extra question (extra time) before they answer, or makes a
document sit behind a search instead of being handed over. It never removes a clue the solution needs.

### The solver

The solver models what the player can know: every fact from reachable clues, plus the statements.

**The reasoning rules (my call).** They are the same for every pattern, and the help screen explains
them to the player in plain words:
- **Certain facts:** physical evidence and documents are always true.
- **Believed until caught:** testimony from witnesses is believed unless a certain fact, or a believed
  source, contradicts it. A person caught in one lie is not believed about anything.
- **No self-alibi:** a suspect's own statement never clears them. It matters only when it is contradicted.
- **Cleared:** a suspect is out when they had no access to the means, or when a believed third party (a
  witness or physical evidence) places them elsewhere at the crime slot. Being cleared overrides
  everything else. This is how an innocent liar is freed: their found secret places them elsewhere.
- **Proven guilty:** a suspect who is not cleared, had access to the means and had the motive, and whose
  account of the crime slot is shown to be a lie, or who is placed at the scene at that slot.
- **The motive:** it comes from documents and testimony. The accusation needs it.

How the patterns fit these rules:
- **Classic:** both finalists are uncleared. Only the killer's account of the crime slot is contradicted.
- **False alibi:** the killer looks cleared by a witness until a certain fact catches the witness lying.
  Then the alibi falls, and the same fact, or another, contradicts the killer's own account.
- **Innocent liar:** the innocent's lie is contradicted, but their secret clears them.

A case is accepted only if:
- applying the rules to all reachable facts leaves exactly one suspect proven guilty, with one motive and
  one means;
- the pattern's shape holds. For Classic: elimination alone leaves exactly 2 suspects, and only the
  contradiction separates them. For False alibi: the killer's alibi stands until the witness's lie is
  found. For Timeline: the decisive facts are times. For Innocent liar: the innocent's lie is
  explainable by a found secret, and the killer's is not;
- the clues the solution needs fit within 60% of the case's time.

Otherwise the generator retries with the next seed. After about 50 failed tries it falls back to the
Classic pattern, which must always succeed. Tests prove that.

### Time in a case

- **The clock (my call):** a case runs over days of four parts (morning, afternoon, evening, night), and
  each part holds 3 actions.
  - **What costs an action:** searching a place costs 1. Questioning a person costs 1, and covers the
    whole conversation: their statement, any topics, and showing any clues. Low trust adds 1 more
    action before they open up.
  - **What is free:** walking between places, and reading the notebook or board.
  - Short: 2 days, so 24 actions. Long: 3 days, so 36 actions.
  - The solution's needed actions stay within 60% of these.
- **People move (my call):** each person follows a simple schedule by part of the day, made from their
  occupation (at work by day, at home or the inn in the evening). The hub shows who is where now. Every
  person can be found at least 2 parts of every day, so the reachability check counts actions, not
  routes.
- **Statements come from questioning:** a suspect's account of the evening is given at the first
  questioning, and is not known before.
- **Running out of time counts as a strike** (my call, to keep the pressure real without being harsh).
  The killer strikes again, the case gains a victim and new clues, and the clock gets one more day.
  A second strike, from time or a wrong accusation, means the killer flees.
- **A wrong accusation also adds a day,** for the same reason: the new clues must stay reachable.

### Accusing and the end of a case

- **The Accuse screen:** pick a culprit, a motive and a means from lists.
  - **Right culprit, right motive and right means:** solved, with full reputation.
  - **Right culprit, motive or means wrong:** solved, with less reputation and a note on what you missed.
  - **Wrong culprit:** a strike. The wrongly accused person's trust drops a lot (and their family's a
    little); this goes into their history.
- **The killer strikes again (my calls):**
  - the second victim is a living suspect or witness, neither the killer nor the wrongly accused;
  - **when it happens:** the second crime happens that night. The truth gains that night's slots
    (for example 21:00-24:00, 6 slots) with everyone's true movements.
  - **what the player gets:** questioning gives a second account, for that night, and the Statements
    view gets a second tab;
  - **the motive:** the second crime's motive is silencing, which is not asked in the accusation.
    Accuse asks about the first murder only. The killer is the same, so one culprit answers both;
  - the generator extends the same truth with the second crime;
  - the solver re-checks the combined case;
  - the new clues are reachable within the added day.
- **The end screen:** the solution, told as a short account. Who did it, why, how and when, and which
  clues proved it, so a lost case still teaches the reasoning. After it come the reputation gained and
  any rank change.
- **After the case:** the dead and the jailed leave the town, newcomers arrive if the population is under
  20, and relationships shift (a widow, a grudge against the detective).

### Screens

All are portrait, with a row of buttons at the bottom, as in the mockups (docs/ideas/game-detective.png,
game-detective-board.png):
- **Case file (the hub):**
  - the case title, the day and part, the strikes;
  - the victim and the known facts;
  - the list of places, with who is there now;
  - buttons: Places, Notebook, Board, Accuse.
- **Place:** a short description, Search, the people here (tap one to question them), and clues found.
- **Questioning:**
  - a sketch frame; the name and occupation; the mood and trust bar;
  - the conversation;
  - "Ask about" topic chips; Show clue (pick from the notebook); Leave.
  - A new clue is shown as a filled chip.
- **Notebook:**
  - clues grouped by type;
  - a Statements view: a timeline table, one column per suspect and one row per slot, showing what each
    claimed. Contradicted cells are marked once the contradicting clue is known.
- **Board:**
  - suspect cards; tap a clue, then a suspect, to tie them;
  - the player's own notes, which the solver does not use;
  - kept within the draw-command limit.
- **Accuse:** three pickers and Confirm.
- **End of case:** the account and the reputation.
- **Career:** rank and reputation, cases solved and lost, and the townspeople list with status, trust and
  history. Opened from the case file.
- **Settings:** case length (Short / Long); the play mode (Career / Single cases); Reset career (it
  asks first).
- **Preparing a new case…:** the generation progress, which takes slices; it shows a line of
  town gossip while it waits.

### Text

- **Templates in English,** with several variants per clue type, role, mood and trust band, filled
  only from the truth model (names, places, times, objects).
- **Statements and testimony use one time format** (for example "half past nine"), and times are
  printed from the slot, never typed into templates.
- **Each person keeps a voice** through a small trait-based choice of phrasing (nervous people hedge,
  proud people bristle).

### Code layout

`apps/portwren/` follows Delve's layout (gamekit bundle into `index.lua`):
- **`src/main.lua`:** the screens, input, saving, the Back handling.
- **Package files, loaded with `_G.require`:**
  - `game/town.lua` (making and evolving the town);
  - `game/gen.lua` (the truth model and clues);
  - `game/solver.lua`;
  - `game/text.lua` (templates and names).
- **Loading:** the generator and solver load only when a case is made; screens need only the saved case
  and `text.lua`.
- **Saves:**
  - `town.txt`: the people, relationships and career;
  - `case.txt`: the open case, meaning its seed and pattern, the clues found, the time, the strikes,
    and the board notes. The truth is rebuilt from the seed, or stored compactly. That's the builder's
    choice, but resuming must give the exact same case.

### Testing

Lupa harness tests, as for our other games (tools/gamekit/harness.py):
- **The generator and solver over many seeds** (at least 1000 per pattern and size):
  - every accepted case has exactly one answer under an independent brute-force checker (it tries every
    culprit, motive and means against all reachable facts);
  - every needed clue is reachable;
  - the time rule holds;
  - the Classic fallback always succeeds;
  - text never names a time or place that differs from the truth.
- **Generation cost:** each slice stays well under the input limit in the harness, and a whole case is
  made in a few seconds on the device.
- **Play by taps:** a scripted solve of a seeded case. A wrong accusation leads to a second victim; a
  second wrong one, to the killer fleeing. Saving and resuming mid-case gives the same case. Trust and
  history carry into the next case. Rank unlocks patterns.
- **Draw-command counts** on the board and notebook screens are under the limit.
- **Back,** down then up, on each screen.
- **The repo's Lua 5.5 lint.**
- **On the device:** generation time, tap latency, a full Short case played, and a Long case resumed
  over a restart.

### Release

- A manifest at 1.0.0, an icon, and a README row and help text.
- RELEASE_NOTES bullets that name the app in their bold lead (for the site's What's new), the site
  catalog text and screenshots, and the release folder routine.
- The store submission comes after the device test.

## Left to the builder

- Exact numbers, tuned by playtesting within the rules above:
  - name lists; the template counts;
  - the trust effects; the reputation thresholds;
  - the time budget per case.
- Whether `case.txt` stores the truth or regenerates it from the seed.
- The sketch art for portraits (simple, 1-bit, maybe varied by occupation) and the app icon.
- The names: the app (Port Wren, my placeholder), the town and the places.
