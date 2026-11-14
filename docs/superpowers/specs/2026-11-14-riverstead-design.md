# Riverstead: a village through ten years (design)

Status: draft, 2026-11-14. Not committed until the device test passes (the user's rule).

This is the second of three games the user asked for, built one at a time: Port Wren (the
detective game, done), this village builder, then a polar expedition. The expedition will reuse this
game's event system.

## Intent

The user wants a calm building game for the Xteink X4 Pro (e-ink, 480x800, touch) that is played for
about ten minutes a day. You found a small village in a river valley and guide it for ten years, one
month per turn. You place buildings, put villagers to work, prepare for winter, and answer what the
seasons and strangers bring.

The user's general preference is as much variation as possible: the 1st and the 10th game should
feel different. Here that comes from a valley generated anew every game, named villagers with lives
of their own, events, and four different ways the village can grow, each with its own ending.

## Goals

- **Ten years, then an ending.** A game is 120 months. The ending depends on the way the village grew
  and on how well it did, with a score. Then a new valley starts. (The user chose a limited game of
  10 years.)
- **The map is the heart of the game** (the user's choice).
  - The valley is generated from a seed every game: the river's course, fertile soil, meadow, forest,
    rock, marsh.
  - Where a building stands changes what it does:
    - a field on fertile soil or by the river gives more, but a riverside field can flood;
    - a mill must stand on the river;
    - a woodcutter gets more with more forest around it;
    - houses near the market or the chapel are happier.
  - The same plan does not work in every valley.
- **Named villagers** (the user's choice).
  - Each villager has:
    - a name and an age;
    - one skill (farming, woodcraft, building, crafting, healing or trade);
    - one trait (hardy, sickly, cheerful, lazy, greedy, devout, clever, quarrelsome);
    - health and happiness.
  - Over the ten years they marry, have children, grow old and die; some leave and newcomers arrive,
    so generations change.
  - Events are told through them ("Mara's daughter is lost in the forest").
  - Work is assigned by person, with an **Auto-assign** button that puts the best-suited person in
    each place.
- **The village can die before the ten years are up** (the user's choice): through famine, sickness,
  or everyone leaving. Warnings come in good time ("Food for 2 months; winter is coming").
- **Four ways to grow, four endings** (the user's choice). The village leans the way its buildings
  go, and the valley favours some ways over others:
  - **Market town** (trade): a market, then a trading post, then a river wharf. Strong on a wide
    river and at a crossing.
  - **Granary of the valley** (grain): a mill, then a great barn, then a bakery. Strong on fertile
    land.
  - **Craftsmen's village** (craft): a smithy, then a pottery, then a weaving shed. Strong with rock
    and forest close by.
  - **Pilgrim's rest** (faith): a shrine, then a temple, then a pilgrims' hostel. It needs a special
    spot (a spring, an old stone) that only some valleys have.

  Each way has its own buildings and its own ending text. The score counts, but the ending and the
  village's story are the real reward.
- **Variation:**
  - a valley generated every game, with a character drawn at random (fertile plain, rocky hills, wide
    river, marshland), which changes which ways are strong;
  - a different starting band of families;
  - events in a different order, and only those whose conditions are met;
  - text with several variants.
- **Saved on every tap**, like our other games.

## Non-goals (v1)

- An endless or sandbox mode, and scenario missions (the user chose the limited 10-year game).
- Villagers walking around on the map, or anything animated.
- Trade with other villages as a system of its own. Traders arrive as events.
- War or raiders.
- Landscape layout.
- Translations: the text is English.

## Anti-goals (a failure even if it works)

- **A game decided at the start.** A valley must never be unwinnable, and no single plan may win
  every valley.
- **A sudden death the player never saw coming.** Famine and sickness are announced months ahead.
- **A month that takes long to play.** One month is about 1-2 minutes; ten minutes covers 5-8 months.
- **A map you can't read on e-ink.** Terrain and buildings need clear 1-bit symbols, and the map must
  never flicker or redraw slowly.
- **Gore or cruelty.** Deaths are reported gently.
- **A recreation of an existing game.** Names, buildings and art are original.

## Constraints (platform facts)

- **Screen and frames:** 480x800, 1-bit e-ink; a frame costs about 0.5-0.65 s, so a tap redraws once.
- **Time limits:** 1000 ms for input callbacks and 1500 ms for `on_draw`. Use `ctx.budget:extend()`
  and `ctx:after` slices for heavy work, as in Port Wren and Checkers.
- **Draw commands:** about 1024 per frame. A map of 11x11 tiles with symbols would go over that if
  drawn tile by tile every frame. It is drawn once into an **offscreen layer** (API section 11,
  `ctx.layers:create`, at most 4 layers; drawing into a layer does not count toward the frame's
  commands, and the layer can't be drawn from inside `on_draw`), whenever the map changes. The frame
  then draws the layer plus the selection and the panel. On the reader a single `layer:draw` call
  also keeps only about 1024 commands (docs/xtapp-api/API-UPDATES.md), so the map is drawn into its
  layer in several calls (for example, a few rows per call). Text drawn into a layer did not show in
  Studio's preview, so the map's symbols are shapes, not letters.
- **Code loading:** package files under `game/` are loaded with `_G.require`, as in Port Wren and
  Calculator. Lua 5.5 on the device, so the repo's `tools/lualint55.py` must pass.
- **Integers:** keep every intermediate below 2^31 (seeds and arithmetic), as Port Wren's rng does.
  Reuse `apps/portwren/game/rng.lua` and `save.lua` (copies in this app).
- **Back:** act on the up event, close a box or go back a screen, and on the outermost screen return
  false so the host offers to exit. Use the pattern in `apps/checkers/src/main.lua`.
- **Firmware:** the newest; no fallbacks. The manifest `api` is the lowest version covering what is
  used. Layers need checking against the API docs.

## Approaches considered

- **A. A rule-based monthly simulation (picked).**
  - The valley is generated from a seed.
  - Each month, a building's output is its base value times the terrain, its workers' skill and the
    season.
  - People are simulated one by one each month.
  - Events come from a deck of conditional cards.
  - The four ways open with their own buildings.
  - Balance is proven by automated players over hundreds of valleys.
  - The most work, but the only way the map truly matters and the balance can be tested.
- **B. An event-card game with the map as a multiplier.** Easier to write and rich in story, but
  strategy would come from the cards, not the map, against the user's choice that the map is the
  heart.
- **C. An hour-by-hour agent simulation**, with villagers walking the map. Lively, but movement means
  nothing on e-ink, and a month would take long to compute on the device.

## The design

### The valley

- **The map:** 11 x 11 tiles, 40 px each, on the top part of the screen (440 x 440).
- **Terrain:**
  - plain meadow;
  - fertile soil;
  - forest;
  - rock (hills);
  - marsh;
  - river, with a **riverside** strip (the tiles next to the river);
  - a **ford**, where the river can be crossed, which helps trade;
  - and, in some valleys, one **special spot** (a spring or a standing stone) that the faith way needs.
- **How it is made:**
  - The river runs from one edge to another and winds; in "wide river" valleys it is two tiles wide
    in places.
  - Forest, rock, marsh and fertile patches grow from seeds scattered according to the valley's
    character.
  - The starting camp sits near the middle, on meadow.
- **Valley characters:** fertile plain, rocky hills, wide river, marshland. The character sets the
  terrain mix and makes some ways stronger (the table above).
- **The generator checks every valley:**
  - there is enough fertile or meadow land for fields to feed the starting village;
  - forest and rock can be reached;
  - at least two of the four ways are workable.

### Buildings

A building has:
- a cost (wood, stone, sometimes tools);
- the time it takes to build (in months, faster with more builders);
- where it may stand;
- how many work there;
- what it makes.

**The core set:**

| building | where | work | what it does |
|---|---|---|---|
| House | meadow or fertile | — | homes 4 people; happier near the chapel or market, less happy next to a smithy or quarry |
| Field | meadow or fertile | 2 | grain at harvest; more on fertile soil, more by the river, floods by the river |
| Fisher's hut | riverside | 1 | fish all year, less in winter |
| Woodcutter | next to forest | 2 | wood; more with more forest around |
| Quarry | on or next to rock | 2 | stone |
| Toolmaker | anywhere | 1 | tools from wood and stone; tools speed up farming, building and the trades |
| Storehouse | anywhere | — | holds more of everything; food spoils less |
| Well | anywhere | — | less sickness for houses near it |
| Herbalist | anywhere | 1 | treats the sick; a healer works better |
| Chapel | anywhere | 1 | happiness for houses near it |
| Levee | riverside | — | protects the tiles behind it from floods |

**The four ways**, three buildings each, every tier needing the one before:

| way | tier 1 | tier 2 | tier 3 |
|---|---|---|---|
| Trade | Market | Trading post (near the ford) | Wharf (on a wide river) |
| Grain | Mill (on the river) | Great barn | Bakery |
| Craft | Smithy | Pottery (near marsh clay) | Weaving shed |
| Faith | Shrine (on the special spot) | Temple | Pilgrims' hostel |

- Each way's buildings make **renown points** for that way every month, and the village leans toward
  the way with the most.
- They also help the economy:
  - trade brings coin and traders, which turn surplus into what is lacking;
  - grain multiplies food;
  - craft makes goods that bring coin and tools;
  - faith brings happiness and pilgrims who leave coin.

**Coin** is a fifth resource, used for buying from traders and for some tier-3 buildings. The
resources are food, wood, stone, tools and coin.

**Trading (my call):**
- Before a Market exists, trade happens only when a trader event comes: an offer you take or leave.
- A Market opens a small **Trade** screen. You sell a surplus for coin and buy what is lacking at a
  worse rate. Prices move with the season (food is dear in late winter, cheap after the harvest) and
  with events.
- A Trading post improves the rates and brings trader events more often, with rare goods such as
  tools in bulk.
- So coin is always useful once the village leans to trade, and the bots can model it as plain rules.

**Hard rules and bonuses (my call):**
- **Hard placement rules**, because the building can't work anywhere else:
  - the Mill on the river;
  - the Fisher's hut on the riverside;
  - the Woodcutter next to forest;
  - the Quarry on or next to rock;
  - the Levee on the riverside;
  - the Shrine on the special spot.
- **Bonuses**, everything else: the Trading post near the ford and the Wharf on a wide stretch give
  more renown and coin there, and the Pottery near marsh makes more. All three can be built anywhere
  allowed (the Wharf on the riverside).
- **Every valley has at least one ford.** Wide stretches appear in any valley, rarely, and often in
  "wide river" valleys.
- So trade, grain and craft can reach tier 3 in every valley; only faith depends on the special spot,
  which about 40% of valleys have.
- The generator's check becomes: at least three ways are workable, the fourth (faith) when the spot
  exists.
- The balance test checks each way at tier 3 over the valleys where it is possible.

### The year

- **Months and seasons:**
  - Spring (March to May) is sowing: a field must be worked in spring to give a harvest.
  - The harvest comes in September and October.
  - In winter (December to February) fields and fishing give little, and people eat from the store.
  - The game starts in March of year 1 and ends after February of year 10.
- **Food:** each person eats every month. A month without food makes people sick, then some die, and
  the weakest first.
- **Spoilage:** stored food loses a little each month, less with a storehouse.

### People

- **The start:** 3 or 4 families, 10 to 14 people, with a mix of skills.
- **Each month, for every person:**
  - **Age:** they get older; children start working at 12, and people get weaker past 60.
  - **Health:** it falls with hunger, cold (not enough houses in winter), marsh nearby and sickness;
    it rises with a well, a herbalist and food.
  - **Happiness:** it comes from food, a home, the chapel or market nearby, work that fits their skill,
    events, and their trait.
  - **Life events:**
    - unmarried adults may marry;
    - a couple with room in their house may have a child;
    - the old and the sick may die;
    - a person unhappy for months may leave.
- **Newcomers** arrive by event, or when the village is happy and has room.
- **Families:**
  - children take a parent's surname and one of the parents' skills;
  - a person's skill grows a little with years of the same work.
- **Work:**
  - every building with work places has slots;
  - Auto-assign fills them by skill and keeps a few on building sites;
  - you can move a person by hand.

### Events

- **The engine** (`game/events.lua`) is a separate module made to be reused by the expedition game.
  - An event is data: an id, a condition on the state, a weight, story text with name and place
    blanks, and 1 to 3 choices, each with effects and a result text.
  - **Extras, built in now so the data and save formats don't have to change later (my call):**
    - **Choice conditions:** a choice shows only when you can afford it or a person fits ("Trade",
      only with the food to pay).
    - **Chance outcomes:** a choice can succeed or fail by a chance that a person's skill or trait
      changes ("send the best woodsman to look for the child"). This is what the expedition's "Trust
      Arvid" needs.
    - **Follow-ups:** a choice can schedule another event some months later ("Mara's daughter is
      found" or "...is not").
    - **One-time events and flags:** some events happen once a game, and flags remember what was
      decided. Pending follow-ups and flags go into the save.
  - The engine picks at most one event a month from those whose conditions hold (weighted, never the
    same one twice in a row), fills in the names, and applies the choice.
- **About 40 events at first:** floods on the riverside, a bad or a rich harvest, sickness, a
  travelling trader, a family asking to stay, a lost child, a wolf winter, a fire, a wedding feast, a
  quarrel between neighbours, a pedlar of tools, pilgrims passing, and so on. Many of them are tied to
  the four ways.
- **Warnings are not events.** They show on the village screen every month: food months left before
  the harvest, sickness, the unhappy.

### The end

The game can end in two ways:
- **After 120 months:**
  - The way with the most renown decides the ending, if it reached at least tier 2; otherwise the
    ending is "a quiet hamlet".
  - Each ending has three levels by score, for example "A great market town", "A busy market village"
    and "A crossroads stall".
  - **The score:** people, happiness, coin and stores, the way's tier, and buildings, plus small
    bonuses (no famine, no one left).
- **Earlier:** everyone is dead or gone. The ending tells what happened.
- **The chronicle:** every finished game is kept with its valley character, ending, score and year.
  It is shown from the title screen, so games can be compared.

### Screens

All screens are portrait, with a row of buttons at the bottom. The mockup is
`docs/ideas/game-village.png`.

- **Village (the hub):**
  - top: the village name, the month and year, and the season;
  - the map, from the layer;
  - under the map: food, wood, stone, tools and coin with their monthly change, then the warnings
    line;
  - bottom buttons: **Build**, **People**, **Ledger**, **Next month**.
  - A tap on a tile shows what is there (terrain, building, workers, output) in a panel under the map,
    with actions: workers, demolish.
- **Build:**
  - a list of the buildings you can build now, with their costs (the locked ones are greyed, with the
    reason);
  - pick one, then tap a tile: the panel shows what it would make there ("Field here: 14 grain at
    harvest; floods") before you confirm;
  - tiles where it can't stand are not accepted.
- **People:**
  - the villagers in pages, with name, age, job, a health and happiness mark, and family;
  - tap one for their card: their skill, trait, spouse, children and story lines ("came in year 3",
    "survived the fever"), and a job to choose from;
  - **Auto-assign**.
- **Ledger:**
  - last month's report: harvest, born, died, came, left;
  - stocks and their trend;
  - food months left;
  - the renown of the four ways with their tier;
  - the score so far.
- **The event box:** the story and the choices, over the village screen. Back closes it with the
  first (safe) choice only if the event allows it; otherwise it stays.
- **The month's summary:** a short box after Next month (harvest, births, deaths, newcomers), or
  straight on if nothing happened. The builder decides.
- **The end:** the ending's title, its text drawn from what happened, the score, then New valley.
- **Title:** Continue, New valley, Chronicle, Settings, How to play.
- **Settings:**
  - **Difficulty** (my call): Gentle, Normal or Harsh. It changes the harvest's swing, how often hard
    events come, and how strong winter is; it applies from the next game. Normal is the default.
  - **New valley** (it asks first).

### Text

- Templates with several variants, filled from the state (names, places by terrain, months).
- Never literal names or months.
- English.

### Code layout

`apps/riverstead/`, like Port Wren:
- `src/main.lua`: the screens and input, bundled with gamekit into `index.lua`.
- `game/`, loaded with `_G.require`:
  - `rng.lua`, `save.lua`: copies of Port Wren's;
  - `valley.lua`: the generator;
  - `rules.lua`: the buildings, terrain, yields and the monthly step;
  - `people.lua`;
  - `events.lua`: the reusable engine;
  - `event_list.lua`: this game's events;
  - `text.lua`;
  - `bots.lua`: the automated players, used only by tests.
- **Saves:** `village.txt` (the whole state), `chronicle.txt` and `prefs.txt`.

### Testing

Lupa harness tests, as for Port Wren:
- **The valley:**
  - deterministic per seed, and the checks above hold over 1000 seeds;
  - each character makes its own mix;
  - the special spot exists in some valleys but not all.
- **The rules:**
  - yields per terrain and season;
  - floods hit only unprotected riverside tiles;
  - spoilage, food and hunger;
  - building time;
  - the ways' tiers and requirements;
  - integers stay below 2^31.
- **People:**
  - aging, marriage, births limited by housing, death, leaving;
  - children's surnames and skills;
  - deterministic per seed.
- **Events:**
  - the engine (conditions, weights, no repeats, effects);
  - every event's text fills in with no blank left.
- **Balance, with automated players over hundreds of valleys and every difficulty:**
  - a sensible bot (build fields and houses, prepare for winter, keep a storehouse, follow the
    valley's strongest way) reaches year 10 in most valleys on Normal (the target: at least 90%);
  - an idle bot (does nothing) dies;
  - over all valleys, each of the four ways is reached at tier 3 by a bot that follows it;
  - no single fixed build order reaches tier 3 everywhere;
  - famine always has warnings at least 2 months before;
  - Harsh is harder than Normal, and Normal harder than Gentle, measured by the bot's survival.
- **Play by taps:** a new valley, building, assigning, Next month through a winter, an event choice,
  saving and resuming, the end screen (by fast-forwarding a bot), Back on every screen, draw commands
  under 900, text within 480 px.
- **On the device:** the map's look (symbols readable at 40 px), the time Next month takes, and a few
  months played.

### Release

- A manifest at 1.0.0 and an icon.
- A README row and section, and RELEASE_NOTES bullets that name the app in their bold lead.
- Site shots, and the store copy after the device test.

## Left to the builder

- Exact numbers: costs, yields, building times, the health and happiness formulas, score weights,
  renown per building. They are tuned with the bots until the balance tests pass.
- The tile symbols (1-bit, 40 px) and the icon.
- The event list's content beyond the kinds named, and the ending texts.
- The names: the app (Riverstead, my placeholder), and the name lists for villagers and villages.
