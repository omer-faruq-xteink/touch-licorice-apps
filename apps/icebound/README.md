# Icebound — XTOS Licorice mini app

Lead a team of six across an uncharted polar region, one day a turn. Every expedition has a new map and
a new mission; what you have not seen is hidden; the weather comes in spells; the team has skills,
flaws, moods and memories; and every morning may bring an event to answer.

## Playing

- **The hub** shows the day of the season (`Day 23 of 60`), the weather, what is left of the mission, a
  window of the map around the party, your supplies, the six people with their health, and warnings
  ("Food for 3 days", "Moss's feet are freezing", "8 days of the season left").
- **Route:** tap the ice tile by tile, or a far tile you have seen; the panel says how many days it takes
  and what lies on the way. **Map** shows the whole region; tap a tile you have seen on it to plan the
  way there. Next to a nunatak, **Climb** spends a day on top and shows far.
- **Pace:** rest (a camp day), steady or hard; after about six days on the march without a rest, people
  wear out. **Rations:** short, normal or full. Both stay set. Supplies are packed for the journey with a
  modest margin, so time, pace and rations matter.
- **March:** the day passes: the party moves along the route, eats, burns fuel; people grow tired, cold
  or ill, and better with rest, food and the doctor. A short report follows, then the next morning's
  event, if any. Back gives an event's safe answer when it has one (a tap outside the box does
  nothing). A lost party's cairns say roughly which way they came from; their camp shows only when
  you are close to it.
- **The ice:** flat ice is fast; sastrugi and pressure ridges are slow and break sledges; crevasses are
  quick but people fall in (a surveyor helps); open water and rock bar the way (a hard frost freezes the
  leads); slopes are slow uphill.
- **The team:** a navigator (sees further, forecasts storms), a doctor (treats; choose whom first on the
  doctor's card) and a dog driver, and three of cook, mechanic, surveyor, hunter, geologist and
  photographer. Someone fed up won't march hard. Nobody dies without days of warning.
- **Supplies:** stocks and days left; Leave depot (on the way to the pole), Kill a dog, Call rescue (once),
  Turn back.

## Missions

| mission | goal |
|---|---|
| Crossing | from the coast where you land to the station on the far side |
| Pole and back | reach the pole and return to base; depots wait for the way home |
| Lost expedition | follow the cairns to a lost party's last camp, then reach the pick-up point |
| Survey | fix four survey points along the coast, then reach the ship |

The expedition ends at the goal (three levels, by who came home and how fast), **turned back** with
everyone home, **rescued** by radio (or when the season ends), or **lost**. A survivor may come again on
the next expedition as a veteran. Finished expeditions go into the **Chronicle**.

## Settings

Difficulty: Easy, Normal or Hard (supplies, the season's length, storms and cold); it applies to the next
expedition. **New expedition** starts one from here too.

The game is saved on every tap (`expedition.txt`), with `chronicle.txt` and `prefs.txt`.

## Files

- `src/main.lua`: the screens; bundled with `tools/gamekit` into `index.lua` by `bundle.py`.
- `game/`: `region` (the map generator and path search), `rules` (travel, supplies, weather, sight),
  `team`, `events` (the event engine shared with Riverstead), `event_list` (this game's events), `sim`
  (the expedition as a whole), `text`, `rng`, `save`, and `bots` (automated players for the balance tests
  only).
- Tests: `test_region.py`, `test_rules.py`, `test_team.py`, `test_events.py`, `test_sim.py`,
  `test_balance.py` (bots over hundreds of regions), `test_icebound.py` (playing by taps), `test_fixes.py`
  and `test_studio.py` (the review's and the Studio playthrough's findings).
