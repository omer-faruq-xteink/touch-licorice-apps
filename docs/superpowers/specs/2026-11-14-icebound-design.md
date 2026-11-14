# Icebound: a polar expedition (design)

Status: draft, 2026-11-14. Not committed until the device test passes (the user's rule).

This is the third of three games the user asked for, built one at a time: Port Wren (the detective
game, live in the store), Riverstead (the village builder, in store review), and this polar
expedition. It reuses Riverstead's event engine. The concept mockup is `docs/ideas/game-expedition.png`.

## Intent

The user wants a game for the Xteink X4 Pro (e-ink, 480x800, touch) in which you lead a team of six
across an uncharted polar region. One day is one turn: you pick the route on a map that reveals itself
as you go, set the pace and the rations, march, and answer what the ice and the team bring.

The user's general preference is as much variation as possible: the 1st and the 10th game should feel
different. Here that comes from a map generated anew every game, a mission that changes, a team of
named people with their own skills, flaws and moods, changing weather, and events.

## Goals

- **One crossing per game** (the user's choice).
  - A game is one expedition, from the start to one of the endings, then a new one.
  - Finished expeditions go into a **Chronicle**.
  - **A veteran:** when the last expedition came back with survivors, the next one may take one of them
    again (my proposal, accepted). The veteran has +1 skill and a memory from the last trip
    ("frostbite scars", "never forgave Arvid"). At most one veteran per expedition.
- **The route is the heart of the game** (the user's choice).
  - Every day's main decision is where to go on the map.
  - The map is generated from a seed. Its terrain changes speed and risk: a short dangerous way against
    a long safe one.
  - What you have not seen is hidden. Weather and the navigator change how far you see; a high point
    shows further.
  - The team and the events make each game's story; the route makes each day's choice.
- **The mission changes every game** (my proposal, accepted). It is drawn at random but never the
  same as the last expedition's (my call); the early or late season too is drawn at random:
  - **Crossing:** from the coast where you land to the station on the far side.
  - **Pole and back:** reach the pole and return to base. Depots left on the way out wait for the way
    back.
  - **Lost expedition:** find a missing party's last camp (cairns and old tracks point the way), then
    reach the pick-up point.
  - **Survey:** visit a number of survey points along a coast, then reach the ship before it leaves.
- **The team** (my proposal, accepted):
  - Six people, each with a name, a role (with a skill level), a trait, health, a mood, and their
    relations to the others.
  - Always a navigator, a doctor and a dog driver, then three more from the other roles.
  - Roles do something: the navigator sees further and loses the way less, the doctor treats, the dog
    driver keeps the dogs fast and healthy, the cook saves food, the mechanic mends sledges, the
    surveyor finds safe ways through crevasses, the hunter brings seal meat by open water.
  - They remember: being overruled, being saved, a quarrel. A memory changes their mood and how they
    act in later events.
- **Losses are possible but always warned of** (the user's choice).
  - A person dies only after a visible decline: a condition that worsens over days with a warning line
    ("Moss's feet are freezing"), and time to treat, rest or change course.
  - No death without a warning at least two days before. This is tested.
- **The season is the clock** (my call, from the mockup's "Day 23 of 60"):
  - every expedition has a season of a set length (about 60 days on Normal, longer on Easy, shorter on
    Hard), shown in the header as "Day 23 of 60";
  - the last ship or plane leaves when the season ends; warnings come from ten days before;
  - if the season ends before the mission is done, the expedition ends: Rescued if the radio is still
    unused (the last plane comes for you), otherwise Lost. The Survey mission's ship is this same rule.
- **Four endings** (the user's choice):
  - **Reached the goal**, at three levels by how many came home and how fast.
  - **Turned back:** the goal was not reached, but you brought everyone back. An honourable ending.
  - **Rescued:** you called for help on the radio. The expedition failed, but nobody died waiting.
  - **Lost:** food, fuel and hope ran out.
  - Each ending has a score.

## Non-goals (v1)

- Real history, real explorers or real places. The setting is a fictional polar region in an early
  20th-century spirit, with sledges, dogs and a radio.
- Several expeditions in a row as one campaign (the user picked one crossing per game; the veteran is
  the only link).
- Moving people around on the map, hunting minigames, or real-time anything.
- Sound, colour, animation.

## Anti-goals (a failure even if it works)

- A death that comes with no warning, or a run lost to one unlucky roll.
- A best route that is the same every game (always go straight, always hug the coast).
- A day that takes many taps: a normal day is Route (if it changes), then March.
- Text that does not fit the screen, or a map that cannot be read at 40 px on e-ink.
- An expedition that can get stuck: there is always a way to the goal, or at least back.

## Constraints (platform facts)

The same as Riverstead's (see `docs/superpowers/specs/2026-11-14-riverstead-design.md`, Constraints),
in short:
- 480x800, 1-bit; a frame costs about 0.5-0.65 s, so a tap redraws once.
- 1000 ms for input callbacks and 1500 ms for `on_draw`; `ctx.budget:extend()` for heavy work.
- About 1024 draw commands per frame and per `layer:draw` call. The map is drawn into an offscreen
  layer in chunks, only after input, never from `on_draw` (Riverstead's 1.0.0 device bug). The frame
  draws the layer plus the overlay (party, route, selection). Symbols are shapes, not text.
- Package files under `game/` load with `_G.require`. `tools/lualint55.py` must pass.
- 32-bit integers on the device: every intermediate below 2^31.
- Back acts on the up event; the outermost screen returns false.
- The manifest `api` is "2.0" like Port Wren and Riverstead; layers were checked there.

## Approaches considered

- **A. A separate app like Riverstead (picked).** `apps/icebound/` with copies of `events.lua`,
  `rng.lua` and `save.lua`, and the rest written for this game: the map generator, the travel rules,
  the team, the event list, the simulation and the balance bots. The published games are not touched.
  The cost is a second copy of the engine.
- **B. A shared library.** `events`, `rng` and `save` move into gamekit and all three games use them.
  One copy, but the bundler changes and the two other games (one live, one in review) would need
  re-testing and new store versions. It can be done later as its own task.
- **C. A fork of Riverstead**, turning the village into an expedition. Rejected: the monthly economy,
  buildings and placement are no use here, and removing them takes longer than writing anew.

## The design

### The region and the map

- **A grid of 11 columns by about 28 rows** of 40 px tiles (the builder settles the height and the
  scale; one tile is about 10 km).
- **Terrain:**
  - flat ice: fast;
  - sastrugi (hard wind ridges): slow, and wear sledges;
  - pressure ridges: very slow; a sledge can break;
  - crevasse fields: normal speed, but a fall risk (the surveyor and roping up lower it);
  - open water (leads): impassable, unless a cold snap freezes it; seals for the hunter at its edge;
  - nunataks (rock through the ice): impassable for sledges; standing next to one lets you climb it
    for a day to see far;
  - glacier slopes: slow uphill, faster down;
  - special tiles: the start, the goal, depots (yours and old caches), cairns and wreckage (stories),
    survey points.
- **Generated from a seed** with a check that a passable way from the start to every target exists
  (a path search over passable tiles). Regions have a character, chosen per game: a broken coast,
  a high plateau, a crevassed glacier, a sea of pressure ice. Each changes the mix.
- **Fog:** a tile is unknown until seen. Seeing distance is 1 in a blizzard or whiteout, 2 normally,
  3 in clear weather; +1 with a good navigator; 4 or 5 from a nunatak. Unknown tiles are hatched.
  Tiles once seen stay known.
- **The view:** the hub shows a window of 11 x 6 tiles around the party (as in the mockup). A **Map**
  screen shows the whole region at a smaller scale for planning.

### A day

0. **Morning** (my call): the day's event, if any, comes first, before the march, as in the mockup
   ("Crevasses ahead ... Go round / Trust Arvid / Camp"). It may be tied to the tiles just ahead
   (crevasses, thin ice, a cairn) and its choices may change the route or turn the day into a camp.
   Events about the camp (a quarrel, a bad dream) come here too. The event is drawn when the
   previous day ends, so it is shown on arrival at the hub, as Riverstead does with the month's event.
1. **Route** (only when it changes): tap tiles to set a path of up to a few tiles ahead, or a far
   known tile, which the party then follows day after day. The panel shows the terrain, the days it
   takes and the risks ("crevasses; 2 days").
2. **Pace:** rest (camp), steady, or hard. Hard covers more but tires people and dogs and raises
   frostbite; rest recovers health and mood.
3. **Rations:** short, normal or full. Short saves food and costs health and mood; full helps recovery.
4. **March:** the day is computed:
   - progress along the route by terrain, pace, weather, dogs and sledges;
   - consumption of food, dog food and fuel (more in the cold and at hard pace);
   - health: cold, hunger, exhaustion, conditions getting better or worse;
   - moods and relations;
   - newly seen tiles.
   A short day report follows when something happened, then the next morning's event, if any.

Pace and rations stay set until changed, so a normal day is one tap on March.

### Supplies

- **Food** (person-days), **dog food**, **fuel** (for warmth and melting snow; without it, frostbite
  and thirst), **dogs** (they pull; fewer dogs, slower), **sledges** (they carry; a broken sledge means
  leaving supplies or a slow repair by the mechanic), **the radio** (one call for rescue; help comes
  after a few days if you hold out).
- **Depots:** on Pole and back, leave a depot on the way out to pick it up on the way back. Old caches
  on the map may hold food or fuel, or nothing.
- **Last resorts:** kill a dog for dog food (morale drops); leave a sledge and its load.

### Weather

- A day's weather: clear, overcast, wind, blizzard or whiteout, with a temperature and a wind.
- It runs in spells (a few days of storm, then clearing) rather than day by day at random.
- A good navigator warns of a storm a day ahead.
- A blizzard makes marching slow and dangerous; resting through it is usually wise.
- The season moves on: the expedition starts in early or late season (chosen per game), and the cold
  deepens over the days, so time matters.

### The team

- **Roles:** navigator, doctor, dog driver (always); then three of cook, mechanic, surveyor, hunter,
  geologist, photographer (the last two bring score and story: samples, plates).
- **Skill** 1-5 in their role; the veteran +1.
- **Traits** (one each): steady, cheerful, sulky, brave, reckless, careful, proud, nervous (the builder
  may add a few). Traits change event chances and how moods move.
- **Health** with conditions: frostbite, snow blindness, exhaustion, injury, sickness. Each has stages
  and gets better or worse each day by rest, rations, weather and the doctor. The worst stage of a
  condition, left untreated for days, can kill, always after a warning line.
- **Mood** and **relations:** each pair is neutral, friendly or tense. Quarrels, shared danger and
  your decisions move them. A very low mood brings quarrel events and **refusals** (my call): someone
  who is fed up will not march at a hard pace (the day goes at steady) and does not lend their skill
  to an event's chance. Tense pairs change which event choices are offered ("Ask Ilse to go with
  Arvid" is not offered while they are at odds); the team never physically splits.
- **Memories:** short lines on the person's card ("pulled Tomas out of a crevasse on day 12").

### Events

- Riverstead's `events.lua` engine, unchanged: conditions, weights, roles, chances by skill and trait,
  follow-ups, once-only events, a safe choice for Back.
- At least 40 events, each with three or more text variants. Kinds: storms, crevasses and snow bridges,
  thin ice, a sledge breaking, dogs fighting or running off, frostbite and sickness, a quarrel, a
  bad dream, a mirage, old cairns and a lost party's traces, seals by open water, a rival expedition's
  flag, a gift found in a cache, the radio crackling, a birthday in the tent.
- Events name people by their role and their name, and their outcome depends on the right person's
  skill (the mockup's "Trust Arvid").

### The end

- **Reached the goal** (and, for Pole and back, home again): three levels by survivors and days.
- **Turned back:** you chose Turn back and reached the start (or the pick-up point) alive.
- **Rescued:** after a radio call you held out until help came.
- **Lost** (my call on what it means): everyone died; or the party cannot go on (no food and no
  dogs to eat, or no sledge and no way to carry on) with the radio already used; or the season ended
  with the radio used. Each of these is warned of: starvation and the season days ahead, the last
  dog and the last sledge when they go.
- **Events never kill outright** (my call): a fall or thin ice adds a condition (injury, frostbite)
  or loses supplies; a death only ever comes through a condition's warned decline.
- **Score:** survivors, days, the mission's extras (survey points, samples, photographs, the lost
  party's journal), supplies left; a bonus when nobody died.
- The ending's text is drawn from what happened (who was lost, who carried whom).

### Screens

All screens are portrait. The mockup is `docs/ideas/game-expedition.png`.

- **The hub:**
  - top: the day, the weather and temperature, the distance or what is left of the mission;
  - the map window (11 x 6) from the layer, with the party, the route and the selection drawn over it;
  - under the map: food (in days), fuel, dogs, sledges; a tap opens Supplies;
  - the team: six rows with name, role, a health bar and a one-word state (steady, tired, frostbite);
    a tap opens the person's card;
  - bottom buttons: **Route**, **Pace**, **Rations**, **March**.
- **Route mode:** taps on the map set the path; the panel shows the cost and risks; Done or Cancel.
- **Pace** and **Rations:** small boxes with three choices.
- **Map:** the whole region at a smaller scale, the known part and the route.
- **Supplies:** stocks and days left at the present rations, the mission's progress, and the actions:
  Leave depot, Kill a dog, Call rescue, Turn back (each asks first).
- **Person card:** role and skill, trait, health with conditions, mood, relations, memories; for the
  doctor, whom to treat first.
- **The event box** and **the day report**, over the hub.
- **The end**, **Title** (Continue, New expedition, Chronicle, Settings, How to play), **Chronicle**,
  **Settings** (difficulty Easy, Normal or Hard for the next expedition; New expedition).
- **Starting an expedition:** the mission, the region's character and the team are shown, with the
  veteran offer when there is one, then the first day.

### Text

- Templates with variants, filled from the state; English; never literal names.

### Code layout

`apps/icebound/`, like Riverstead:
- `src/main.lua`: the screens and input, bundled with gamekit into `index.lua`.
- `game/`, loaded with `_G.require`:
  - `rng.lua`, `save.lua`, `events.lua`: copies of Riverstead's;
  - `region.lua`: the map generator and its checks;
  - `rules.lua`: terrain, travel, supplies, weather and the day's step;
  - `team.lua`: the people, conditions, moods, relations;
  - `event_list.lua`: this game's events;
  - `sim.lua`: the game as a whole (start, day, end, score);
  - `text.lua`;
  - `bots.lua`: automated players for the balance tests only.
- **Saves:** `expedition.txt`, `chronicle.txt`, `prefs.txt`.

### Testing

Lupa harness tests, as for Riverstead:
- **The region:** deterministic per seed; a passable way to every target over 1000 seeds; each
  character makes its own mix; every mission places its targets sensibly.
- **The rules:** travel by terrain, pace and weather; consumption; sight distance; depots; weather
  spells; integers below 2^31.
- **The team:** conditions worsen and heal; deaths only after a warning two days before; moods and
  relations move; the veteran carries over.
- **Events:** the engine's tests carried over; every event's text fills in.
- **Balance, with bots over hundreds of regions and every difficulty and mission:**
  - a sensible bot (path search over known tiles towards the target, rest in blizzards, rations by
    food left, treat the sick, turn back when supplies cannot reach the goal) reaches the goal in most
    expeditions on Normal (the target to tune: about 60-85%), more on Easy, fewer on Hard;
  - the sensible bot's crew almost never loses anyone without a warning, and loses nobody in most runs;
  - a reckless bot (always hard pace, straight at the goal) fails or loses people much more often;
  - every mission type can be won;
  - no fixed plan (one pace, one ration, the straight line) wins the best ending everywhere.
- **Play by taps:** a new expedition, setting a route, pace, rations, March through a storm, an event,
  a person card, Supplies actions, saving and resuming, the end (by fast-forwarding a bot), Back on
  every screen, draw commands under 900, text within 480 px.
- **On the device:** the map's look, the time a March takes, a few days played.

### Release

- Manifest 1.0.0 and an icon; a README row and section; RELEASE_NOTES bullets with the app in the bold
  lead (the next open release); site shots; the store copy after the device test.

## Left to the builder

- Exact numbers: the scale, speeds, consumption, condition stages, mood formulas, weather spells,
  score weights, supplies per difficulty. Tuned with the bots until the balance tests pass.
- The tile symbols (1-bit, 40 px and the small scale), the icon.
- The event list's content beyond the kinds named; the ending texts; the name lists for people and
  places.
- How the route is drawn and how many tiles ahead it may be set.

## Tuning after play (2026-11-14, the user's call after the first device games)

The first build was too easy: missions took about 20 of 56 days and half the food was left, so time,
supplies, pace and rations hardly mattered, and the lost camp was found almost by walking north.

- **Time and supplies matter:** travel is slower (steady 6 points a day, hard 9), so a mission takes
  about 30-45 days; supplies are packed for the journey (the par's days at normal rations, +50% on Easy,
  +22% on Normal, +8% on Hard; a lost-party search +20% more); the season is at least par + 12 days;
  the cold deepens every 5 days; after about six marching days without a rest, exhaustion builds.
- **The lost party is a real search:** the camp lies mostly off the straight line north and shows only
  within two tiles; the pick-up is on the far side from it; the party's trail wandered (via another
  place) with a cairn every 3-5 tiles and one buried; a cairn's note gives one of four directions, towards
  the next cairn, and reveals nothing.
- **Balance targets** (test_balance.py): Normal wins 60-85% (now 66%), each mission at least 40%, a
  mission takes 26-46 days on average, at most 35% of the food is left at the goal (now 20%), and the
  sensible bot brings everyone home to the goal at least 10 points more often than a fixed plan.
