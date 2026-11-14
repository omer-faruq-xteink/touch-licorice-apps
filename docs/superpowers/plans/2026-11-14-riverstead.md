# Riverstead Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** a new XTApp, Riverstead 1.0.0: a ten-year village builder on a generated river valley, with named villagers, events, and four ways to grow, each with its own ending.

**Architecture:**
- **`src/main.lua`:** the screens, bundled with gamekit into `index.lua`.
- **Package files under `game/`, loaded with `_G.require`:**
  - the valley generator;
  - the rules and the monthly step;
  - people;
  - a reusable event engine and this game's events;
  - text;
  - bots for the balance tests.
- **The map:** drawn into an offscreen layer in chunks whenever it changes.

**Tech Stack:** Lua (the device runs 5.5 with 32-bit integers), the gamekit lupa harness, and Python tests.

**Spec:** `docs/superpowers/specs/2026-11-14-riverstead-design.md`

## Global Constraints

- **No commits until the device test passes.** Tasks end on a green test run, and Task 10 commits.
- **The package:** `apps/riverstead/`. Manifest: `app_id` "riverstead", `display_name` "Riverstead", `version` "1.0.0", `entry` "index.lua", `permissions` []. `api` is the lowest version that covers layers (check `docs/xtapp-api/en/11-Offscreen-layers.md` and API-UPDATES).
- **Screen:** 480x800, portrait, 1-bit.
- **Frames and commands:**
  - one redraw per tap;
  - under 900 draw commands per frame;
  - at most about 1024 commands per `layer:draw` call;
  - no text drawn into layers.
- **Time:** 1000 ms per input callback and 1500 ms for `on_draw`; use `ctx.budget:extend()` for the monthly step.
- **Integers:** every intermediate stays below 2^31. Copy `apps/portwren/game/rng.lua` and `save.lua` unchanged.
- **Back:** act on the up event; inner screens go back a level; the title returns false on up.
- **Saving:** `village.txt`, `chronicle.txt` and `prefs.txt`, written on every tap that changes state.
- **Text:** English. Deaths are reported gently. The names are original.
- **Lint:** `python -I tools/lualint55.py` passes on every `.lua`.
- **Variation:** nothing in a game is fixed. Everything comes from the seed: the valley, the families, the order of events, the text variants.

## Shared data model

**Terrain** (`game/rules.lua`, `R.TERRAIN`): `'meadow'`, `'fertile'`, `'forest'`, `'rock'`, `'marsh'`, `'river'`.

**Valley:**
```
{seed=, char='plain'|'hills'|'river'|'marsh', w=11, h=11, t={[i]=terrain}, wide={[i]=true}, ford={i...},
 special=i|nil, special_kind='spring'|'stone'|nil, camp=i}
```
- `i = (y-1)*11 + x`, with x and y from 1 to 11.
- Riverside: a non-river tile next to (4 directions) a river tile. `V.riverside(valley, i)`.

**Building** (`R.BUILD[kind]`):
```
{name=, cost={wood=,stone=,tools=,coin=}, months=, slots=, place=fn(valley, state, i) -> ok, why,
 way=nil|'trade'|'grain'|'craft'|'faith', tier=nil|1|2|3, needs=kind|nil}
```
- **The core kinds:** `house`, `field`, `fisher`, `woodcutter`, `quarry`, `toolmaker`, `storehouse`, `well`, `herbalist`, `chapel`, `levee`.
- **The ways:**
  - Trade: `market`, `tradingpost`, `wharf`.
  - Grain: `mill`, `barn`, `bakery`.
  - Craft: `smithy`, `pottery`, `weaving`.
  - Faith: `shrine`, `temple`, `hostel`.
- **Hard placement rules**, the spec's "Hard rules and bonuses": the mill on the river, the fisher and the levee on the riverside, the woodcutter next to forest, the quarry on or next to rock, the shrine on the special spot. Every other building goes on meadow or fertile land, not on the river.

**Person:**
```
{id=, name=, sex='f'|'m', age=months, skill='farming'|'wood'|'building'|'crafting'|'healing'|'trade', lv=1..5,
 trait='hardy'|'sickly'|'cheerful'|'lazy'|'greedy'|'devout'|'clever'|'quarrelsome', health=0..100, happy=0..100,
 spouse=id|nil, mother=id|nil, father=id|nil, job=i|'build'|nil, sad=months, alive=true|false, gone=true|nil, story={str...}, came=month}
```

**State (`village.txt`):**
```
{v=1, seed=, name=, diff='gentle'|'normal'|'harsh', month=1..121 (1 = March of year 1), valley=,
 b={[i]={kind=, left=months to finish (0 = working), workers={id...}}}, res={food=,wood=,stone=,tools=,coin=},
 people={[id]=person}, next_id=, renown={trade=,grain=,craft=,faith=}, flags={}, pending={{at=month, id=event id, vars=}},
 event=nil|{id=, vars=} (the open event box), last_event=, report={...}, over=nil|'end'|'dead', ending=nil|{...}}
```

**Calendar:**
- `R.moy(month)` gives 1..12, the month of the year, with month 1 being March: `(month + 1) % 12 + 1`.
- `R.season(month)`: spring is moy 3-5, summer 6-8, autumn 9-11, winter 12, 1 and 2.
- The harvest is in moy 9-10, sowing in moy 3-5.

## Review Focus

1. **The app is closed while an event box is open.** Reopening shows the same event with the same names; it is never lost or rolled again. The test goes in Task 8.
2. **Everyone dies in the middle of a month.** The end screen comes up once. The people list, auto-assign and the ledger work with nobody. The test goes in Task 9.
3. **Resources at the edge.** Building with exactly enough works and leaves 0. No resource ever goes below 0 (food at 0 becomes hunger, not a negative number). Demolishing returns no resources and frees the workers. The test goes in Task 3.
4. **Layers unavailable** (no `ctx.layers`, like the harness, or `create` failing with `limit_exceeded` or `out_of_memory`). The map is drawn straight into the frame in a simplified form (terrain letters off, one rect per building) under 900 commands, with no crash. The test goes in Task 8.
5. **The last month.** Month 120 ends the game exactly once, a pending follow-up event is dropped, and the score and ending stay the same over a restart. The test goes in Task 6.

---

### Task 1: The app skeleton

**Files:** create `apps/riverstead/manifest.json`, `bundle.py` (like `apps/portwren/bundle.py`), `src/main.lua`, `game/rng.lua` and `game/save.lua` (copies), and `test_riverstead.py`.

**Interfaces:**
- **Produces:** the title screen (`Continue` only when `village.txt` holds a game, `New valley`, `Chronicle`, `Settings`, `How to play`), `__TEST.api = {screen=, state=, mod=}`, and `mod(name)` returning `(_G.require('game.' .. name))`.

- [ ] **Step 1: Test** (`test_riverstead.py`, harness setup as in `apps/portwren/test_portwren.py`: TIMERS stubs and `package.path`). It checks the title texts, that Continue is missing with an empty store, Back down/up on the title (`True`/`False`), the how-to box opening and closing with Back, `g.commands() < 900` and `no_err`.
- [ ] **Step 2: Run** `python -I apps/riverstead/test_riverstead.py`. Expected: it fails because the bundle is missing.
- [ ] **Step 3: Implement** the skeleton: the Port Wren host-callback pattern (hits, the modal, Back) and the how-to text from the spec's "The year" and "The end".
- [ ] **Step 4: Run** it again. Expected: `riverstead: all tests passed`.

### Task 2: The valley

**Files:** create `game/valley.lua` and `test_valley.py`.

**Interfaces:**
- **Consumes:** `R`, the rng.
- **Produces:** `game/valley.lua` returns `function(Rng) -> V`, with:
  - `V.make(seed) -> valley`. It retries child seeds internally until the checks pass.
  - `V.riverside(valley, i) -> bool`, `V.near(valley, i, terrain, dist) -> count` (Chebyshev distance), and `V.xy(i)`.
  - `V.check(valley) -> ok, why`.
  - `V.CHARS = {'plain','hills','river','marsh'}`.
- **How a valley is made:**
  - the character is picked at random;
  - the river winds edge to edge;
  - wide stretches cover at most 1/3 of the river in `river` valleys, and none or one short stretch elsewhere;
  - there are 1-2 fords on river tiles;
  - forest, rock, marsh and fertile soil grow from seed points, with the counts weighted by character;
  - `special` is set in about 40% of valleys, on meadow away from the river;
  - `camp` is a meadow tile near the middle, with at least 6 meadow or fertile tiles within 2.
- **`V.check`** requires:
  - at least 12 meadow or fertile tiles;
  - at least 6 forest and 3 rock tiles;
  - at least one ford;
  - a camp with forest within 4 tiles.

- [ ] **Step 1: Test.** It checks that:
  - over seeds 1..1000, `V.check` holds;
  - each valley is deterministic per seed;
  - `#ford >= 1`;
  - `special` is set in 25-55% of seeds;
  - every character occurs;
  - `plain` valleys average more fertile tiles than `hills`, `hills` more rock, `marsh` more marsh, and `river` more wide tiles;
  - `riverside` is false for river tiles;
  - generating 1000 valleys takes under 2 s in the harness.
- [ ] **Step 2: Run** `python -I apps/riverstead/test_valley.py`. Expected: it fails.
- [ ] **Step 3: Implement `valley.lua`.**
- [ ] **Step 4: Run.** Expected: it passes.

### Task 3: The rules and the economy

**Files:** create `game/rules.lua` and `test_rules.py`.

**Interfaces:**
- **Consumes:** `V`.
- **Produces:** `game/rules.lua` returns `function(Rng, V) -> R`, with:
  - `R.BUILD`, `R.TERRAIN`, `R.moy`, `R.season`;
  - `R.can_place(state, kind, i) -> ok, why`: the terrain, the tile free, the `needs` building built, resources enough;
  - `R.place(state, kind, i)`: pays and starts construction;
  - `R.demolish(state, i)`: frees the workers, no refund;
  - `R.yield_preview(state, kind, i) -> {resource=amount}`, the yearly or harvest estimate for the build panel;
  - `R.produce(state, r) -> report` (one month of production, spoilage and eating, and construction progress), `R.food_months(state) -> int` (months of food at the current eating, counting the expected harvest until the next one);
  - `R.flood(state, r) -> {i...}` (the riverside tiles hit, minus those a levee protects: levee tiles and tiles within 2 of a levee on the same side of the river);
  - `R.DIFF = {gentle=, normal=, harsh=}` (multipliers: harvest swing, winter eating, the chance of a hard event).
- **The rules, from the spec's tables:**
  - **Yield** = base x terrain multiplier x workers (each worker 0.5 + 0.1 x lv, +0.2 if the skill matches) x tools (1.0, or 1.25 when `res.tools` >= the number of people / 4) x the season.
  - **Fields:** produce only in moy 9-10, and only if they had workers in moy 3-5.
  - **Fisher:** half in winter.
  - **Woodcutter:** x(1 + 0.1 x the forest within 2).
  - **Quarry:** x(1 + 0.1 x the rock within 1).
  - **Eating:** each person eats 1 food a month, 0.5 under 12 years old, and 1.25 in winter on `harsh`.
  - **Spoilage:** 3% of food a month, 1% with a storehouse.
  - **Storage:** 200 of each resource, plus 300 per storehouse.
  - **Construction:** each builder takes 1 month off `left`, and a building needs at least 1 builder.
  - **Resources:** clamp at 0. A shortfall of food is recorded as `report.hunger = missing`.
  - The exact base numbers are tuned in Task 7; start them so a field on fertile soil with 2 farmers feeds about 8 people for a year.

- [ ] **Step 1: Test.** It checks that:
  - a fertile field gives more than a meadow field, and a riverside field more than an inland one;
  - a field with no workers in spring gives 0 at harvest;
  - a mill can't be placed off the river, a shrine only on `special`, and a woodcutter not away from forest;
  - a tier-2 building needs its tier-1;
  - **Review Focus 3:** building with exactly enough leaves exactly 0; after a month with too little food, food is 0 and not negative and `report.hunger > 0`; demolishing frees the workers and returns nothing;
  - a flood never hits a tile behind a levee;
  - spoilage is lower with a storehouse;
  - over 120 months of random play, every intermediate in `res` is below 2^31.
- [ ] **Step 2: Run** `python -I apps/riverstead/test_rules.py`. Expected: it fails.
- [ ] **Step 3: Implement `rules.lua`.**
- [ ] **Step 4: Run.** Expected: it passes.

### Task 4: People

**Files:** create `game/people.lua`, `game/text.lua` (the name lists and the person story lines for now), and `test_people.py`.

**Interfaces:**
- **Consumes:** `R`, `T`.
- **Produces:** `game/people.lua` returns `function(Rng, R, T) -> P`, with:
  - `P.founders(state, r)`: 3 or 4 families, 10-14 people, with a mix of skills (at least one each of farming, wood and building);
  - `P.month(state, r, report)`: aging, health, happiness, marriage, births, deaths and leaving, with lines written into `report.lines` and `person.story`;
  - `P.living(state) -> {ids}`, sorted;
  - `P.workers(state) -> {ids}` (aged 12 years and over, alive, not gone);
  - `P.auto_assign(state)`: fills the slots of finished buildings by skill match, then level; keeps 2 builders while anything is under construction;
  - `P.assign(state, id, job)` and `P.newcomers(state, r, n, reason)`.
- **The rules:**
  - **Health** -10 with hunger, -5 with winter crowding (more people than 4 per house), -3 near marsh; +5 near a well, +5 with a herbalist; `sickly` and `hardy` x1.5 and x0.5 on losses.
  - **Death** chance per month rises after 60 years of age and below 20 health.
  - **Happiness:** food, a home, a chapel or market within 3 of their house, a job matching the skill, and the trait.
  - **Marriage** between unmarried adults aged 18-45, not siblings.
  - **Births:** a couple under 42 with room in the houses, at most one a year each; the child takes the father's surname and a parent's skill at lv 1.
  - **Leaving:** `sad >= 4` months below 25 happiness.
  - Skill rises one level per 2 years of the matching job, up to 5.

- [ ] **Step 1: Test.** It checks that:
  - the founders count 10-14, with the required skills, deterministic per seed;
  - over 120 months of a well-fed state with houses, the population grows, someone marries, children are born with a parent's surname, and someone over 60 dies over seeds 1..50;
  - with no houses, there are no births;
  - with food 0 for 3 months, health falls and someone dies;
  - auto-assign puts farmers on fields first and keeps 2 builders while something is being built;
  - a person with happiness below 25 for 4 months leaves (`gone`);
  - ids are never reused.
- [ ] **Step 2: Run** `python -I apps/riverstead/test_people.py`. Expected: it fails.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: it passes.

### Task 5: The event engine, the events and the text

**Files:** create `game/events.lua` (the reusable engine), `game/event_list.lua`, add the templates to `game/text.lua`, and create `test_events.py`.

**Interfaces:**
- **Produces:**
  - **`game/events.lua`** returns `E`, independent of this game. The game gives it callbacks:
    - `E.pick(defs, state, r, ctx) -> ev|nil`, where `ctx = {cond=fn(def,state), weight=fn(def,state)}`. It picks one event weighted from those whose `cond` holds. A pending follow-up due now comes first. It never picks `state.last_event`, and never an `once` event whose flag is set.
    - `E.fill(def, state, r, cast) -> vars`: chooses the people and places the text needs (`cast(def.roles, state, r)`).
    - `E.choices(def, state, vars) -> {choice...}`: only those whose `when` holds.
    - `E.apply(def, choice, state, vars, r, effects) -> result_text_key, outcome`. A `chance` choice rolls `chance + skill bonus`, from `choice.chance = {base=, skill=, trait=}`. It applies `choice.ok` or `choice.fail` through the game's `effects` table, sets flags, and pushes follow-ups `{at = state.month + n, id=, vars=}` into `state.pending`.
  - **An event definition:** `{id=, once=bool, weight=, cond=..., roles={...}, text=tpl, choices={{label=, when=..., chance=..., ok={effects}, fail={effects}, then={id=, after=n}}}}`. Conditions and effects are data (`{res_at_least={food=40}}`, `{season='winter'}`, `{has='market'}`, `{food=-30}`, `{happy=+10}`, `{newcomers=3}`, `{sick=2}`, `{flag='x'}`), read by small game-side functions.
  - **`game/event_list.lua`:** about 40 events, covering every kind in the spec's Events list. Every way has at least 3 events tied to it. At least 4 events use chance, at least 3 schedule follow-ups, and at least 5 are `once`.
- **Text:**
  - `T.event_text(def, vars, r)`, `T.result_text(...)`, and `T.warning_lines(state, R)`;
  - name lists of at least 40 female and 40 male first names and 60 surnames, original, and village names;
  - at least 3 variants per event text.

- [ ] **Step 1: Test.** It checks that:
  - the engine never returns an event whose condition fails;
  - it never repeats the last one;
  - `once` events come at most once in a 120-month run;
  - a due follow-up comes first;
  - a choice's `when` hides it;
  - chance outcomes with a high-skill person succeed more often than with a low-skill one, over 1000 rolls;
  - for every event, its roles fill in a typical state of year 3, and its text, choices and results render with no `{` left;
  - every event can occur in some state, over 200 random states;
  - the counts above hold;
  - the engine module does not reference `rules` or `people` (grep the file).
- [ ] **Step 2: Run** `python -I apps/riverstead/test_events.py`. Expected: it fails.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: it passes.

### Task 6: The ways, trade, the month and the end

**Files:** modify `game/rules.lua`; create `game/sim.lua` (the month as a whole) and `test_sim.py`.

**Interfaces:**
- **Consumes:** Tasks 2-5.
- **Produces:** `game/sim.lua` returns `function(Rng, V, R, P, E, T, L) -> S` (where `L` is the event list), with:
  - `S.new(seed, diff) -> state`: the valley, the founders, the starting stock (food 60, wood 40, stone 10, tools 4, coin 0), and the village name;
  - `S.begin_month(state, r)`: sets `state.event` from `E.pick`, or nil;
  - `S.answer(state, choice_index, r) -> text`;
  - `S.next_month(state, r) -> report`: production, people, renown, trade upkeep, floods (in moy 4-6, by chance x the difficulty), the end check, then `month += 1`;
  - `S.score(state) -> int`, `S.ending(state) -> {way=, level=1..3|nil, title=, lines={...}, score=}`;
  - `R.trade_prices(state) -> {resource={buy=, sell=}}` and `R.trade(state, resource, amount)` (positive buys, negative sells).
- **Renown:** each way's buildings add renown every month (tier 1 = 1, tier 2 = 3, tier 3 = 6), with bonuses (the trading post within 2 of a ford x1.5, the wharf on a wide stretch x1.5, the pottery within 2 of marsh x1.5).
- **The way:** the one with the most renown, if its tier >= 2; otherwise `'hamlet'`.
- **Trade:** only with a market. The sell price is lower than the buy price. Food is dear in moy 1-3 and cheap in moy 10-11. A trading post improves the rates by 20%.
- **Coin:** also comes from the bakery, the pottery, the weaving shed and the hostel.
- **The end:** after month 120 is processed, `over='end'` and the ending is set. When no living, un-gone person is left, `over='dead'`.
- **The score:** people x 10 + average happiness + stock/20 + coin/5 + tier x 50 + buildings x 5, + 30 if there was no famine and + 20 if no one left.
- **The ending levels** by score: below 250 is level 3, 250-450 level 2, over 450 level 1. The thresholds are tuned in Task 7.

- [ ] **Step 1: Test.** It checks that:
  - a 120-month run with a scripted plan that builds a market, a trading post and a wharf ends with `way = 'trade'` and `level` set;
  - an empty run (nothing built, no assignment) ends `over = 'dead'` before month 120;
  - trade without a market is refused; buying more than the coin is refused; sell < buy;
  - **Review Focus 5:** at month 120 with a pending follow-up, `next_month` ends the game once, `pending` is cleared, and `S.ending` gives the same result after `save.encode` and `decode`;
  - `S.new` is deterministic per seed.
- [ ] **Step 2: Run** `python -I apps/riverstead/test_sim.py`. Expected: it fails.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: it passes.

### Task 7: Bots and balance

**Files:** create `game/bots.lua` and `test_balance.py`; tune the numbers in `rules.lua`, `people.lua` and `sim.lua`.

**Interfaces:**
- **Consumes:** `S`.
- **Produces:** `game/bots.lua` returns `function(R, P, S, V) -> B`, with `B.sensible(state, r, way)`, `B.idle(state, r)` and `B.fixed(state, r, order)`. Each returns nothing and acts on the state for one month: it builds, assigns, trades and answers the open event (the first choice it can afford).
- **The sensible bot:**
  - keeps food for 4 months before winter;
  - builds fields on the best land, and houses when crowded;
  - builds a storehouse in year 1 and a well by year 2;
  - follows `way`, or the valley's best;
  - auto-assigns.
- **`B.fixed`:** the same build order in every valley (for the "no single plan wins everywhere" test).

- [ ] **Step 1: Test** (`test_balance.py`, over 300 valleys per difficulty; time it). It checks that:
  - the sensible bot reaches month 120 in at least 90% of Normal valleys, 97% of Gentle and 70% of Harsh, so Gentle > Normal > Harsh;
  - the idle bot dies in every valley before month 60;
  - for each way, the sensible bot following it reaches tier 3 in at least 60% of the valleys where it is possible (faith: valleys with `special`);
  - `B.fixed` with a trade-first order reaches tier 3 in under 90% of valleys;
  - in every famine (food 0 with hunger), `R.food_months` was 2 or less at least 2 months earlier, so the warnings came in time;
  - one 120-month run takes under 1.5 s in the harness, and every month under 50 ms.
- [ ] **Step 2: Run** `python -I apps/riverstead/test_balance.py`. Expected: it fails or misses the targets.
- [ ] **Step 3: Implement the bots,** then tune the numbers until the targets hold. Don't loosen the targets. Record the final rates in the test's output.
- [ ] **Step 4: Run** every test file. Expected: all pass.

### Task 8: The village screen, the map layer, building, the month

**Files:** modify `src/main.lua` and `test_riverstead.py`.

**Interfaces:**
- **Consumes:** `S`, `R`, `P`, `T`, `V`.
- **Produces:** the screens `'village'`, `'build'`, `'tile'` and `'summary'`, plus `__TEST.api` fields `tile_xy(i) -> x, y`, `layer_ok()` and `run_month()`.
- **The map:**
  - 11 x 11 tiles of 40 px at (20, 84).
  - A terrain symbol per tile (1-bit shapes, no text, as in the mockup `docs/ideas/game-village.png`: furrows, trees, triangles for rock, tufts for marsh, waves for the river, a double line for a ford, a star for the special spot).
  - Buildings as framed blocks with a small shape per kind, and an outline for one under construction.
  - It is drawn into `ctx.layers:create(440, 440)` in 4 `layer:draw` calls, about 3 rows each, whenever the map changes (`map_dirty`).
  - The frame draws `g:image(layer, 20, 84)` plus the selection frame.
- **Without layers** (Review Focus 4): draw straight into the frame with one rect per building and a simplified terrain (river and forest only), under 900 commands.
- **Village:**
  - top: the name, the month (`March, year 1`) and the season;
  - the map;
  - under the map: the 5 resources with their change, and the warnings line (`T.warning_lines`);
  - the panel for the selected tile;
  - bottom: `Build`, `People`, `Ledger`, `Next month`.
- **A tap on the map** selects a tile: its terrain, its building, the workers and the output, with `Workers` and `Demolish` (asks first).
- **Build:**
  - lists what can be built, with costs; the locked ones are dimmed, with the reason;
  - pick one, then tap a tile: the panel shows `R.yield_preview` and `Place` / `Cancel`;
  - a tile it can't stand on shows `why`.
- **Next month:**
  - `S.next_month` is sliced with budget extend;
  - then the summary box, if there is anything to tell;
  - then `S.begin_month`: if an event comes, the event box opens.
- **The event box:**
  - the story text and up to 3 choices (kit modal rows);
  - Back does nothing while an event is open (the user must choose);
  - saved, so reopening shows it again (Review Focus 1).

- [ ] **Step 1: Test.** It checks that:
  - New valley draws the village with the month text;
  - `layer_ok()` is true with a layers stub (add a stub `ctx.layers` to the harness stubs that counts commands per `draw` call), and each `draw` call stays under 1000 commands;
  - building a field on a meadow tile takes resources and shows it under construction;
  - Next month advances the month and the construction;
  - the event box appears when an event is forced (`state.pending` due now);
  - Back with an event open keeps it, and a restart keeps the same event and the same names;
  - **Review Focus 4:** with `ctx.layers = nil`, the village draws under 900 commands with `no_err`; with a `create` returning nil and `'out_of_memory'`, the same;
  - the frame stays under 900 commands with layers;
  - no text runs past 480 px;
  - Back from build and tile goes to the village, and from the village to the title.
- [ ] **Step 2: Run** `python -I apps/riverstead/test_riverstead.py`. Expected: the new checks fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: it passes.

### Task 9: People, ledger, trade, the end, chronicle, settings

**Files:** modify `src/main.lua` and `test_riverstead.py`.

**Interfaces:**
- **Produces:** the screens `'people'`, `'person'`, `'ledger'`, `'trade'`, `'end'`, `'chronicle'` and `'settings'`.
- **People:**
  - 8 a page;
  - each row: the name, age, job and marks (sick, unhappy);
  - `Auto-assign`;
  - a tap opens the card: skill, level, trait, spouse, children, story lines, and `Job` (a list of the buildings with free slots, plus Builder and Idle).
- **Ledger:**
  - the last report;
  - the stock and its trend;
  - food months;
  - the four ways' renown and tier;
  - the score so far;
  - a `Trade` button, only with a market.
- **Trade:**
  - per resource: the buy and sell price, and `Buy 10` / `Sell 10`;
  - the coin shown.
- **The end:**
  - the ending title, its lines and the score;
  - it writes the chronicle entry once (`{seed, name, char, ending title, score, month, diff}`) to `chronicle.txt`;
  - then `New valley`.
- **Chronicle:** the past games, newest first, in pages.
- **Settings:**
  - Difficulty Gentle / Normal / Harsh (`prefs.txt`, used by the next game);
  - `New valley` (asks first).

- [ ] **Step 1: Test.** It checks that:
  - People lists the founders, Auto-assign fills the jobs, and moving a person to Builder by hand changes `job`;
  - the person card shows the skill and the trait;
  - Ledger shows the four ways;
  - Trade is missing without a market; with a forced market, `Sell 10` food adds coin;
  - fast-forwarding with `B.sensible` to month 120 shows the end screen once and writes one chronicle entry, and a restart doesn't write a second;
  - **Review Focus 2:** killing everyone (all `alive=false`) and then `Next month` shows the end screen with `dead`; People, Ledger and Auto-assign with nobody give no error;
  - changing the difficulty mid-game leaves `state.diff`, and the next game uses the new one;
  - Back on each new screen goes back a level;
  - commands under 900 and widths within 480 on each screen.
- [ ] **Step 2: Run.** Expected: the new checks fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** every test file and the lint. Expected: all pass.

### Task 10: Release, the device test, the commit

**Files:** create `apps/riverstead/README.md` and `icon.png` (`tools/make_icons.py`: a house by a river); modify `README.md` (a row, a section, the tests), `RELEASE_NOTES.md` (a bullet under v0.25.0 with the bold lead "New: Riverstead"), and `tools/site_catalog.py` (the games category); add `site/shots/riverstead-*.png`.

- [ ] **Step 1:** write the README and the notes; run `python -I site/test/test_whatsnew.py`. Expected: `all passed`.
- [ ] **Step 2:** the final review, by a fresh reviewer on the most capable model: give it the Review Focus, then fix what it finds, with tests.
- [ ] **Step 3:** build the package, copy it to the reader, export it for Studio, play it in Studio's preview, then take the store screenshots and the cover (as for Port Wren), and the site shots.
- [ ] **Step 4: The device test with the user:** the map's look, how long Next month takes, and a few months played.
- [ ] **Step 5:** once the user confirms, commit (with the release folder updated), and push when asked.
