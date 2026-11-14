# Riverstead — XTOS Licorice mini app

Guide a village in a river valley for ten years, one month a turn. Every game is a new valley; where a
building stands changes what it gives; named villagers live, marry, grow old and leave; the seasons and
strangers bring events; and the village grows one of four ways, each with its own ending.

## Playing

- **The village screen** shows the valley (11 x 11 tiles), the month and season, your stock (food,
  wood, stone, tools, coin, with last month's change) and warnings ("Food for 2 months; harvest in 3",
  "Nobody is building", the sick and the unhappy). Tap a tile to see what is there.
- **Build:** pick a building (the ones you can't build yet say why), then tap a tile. Before you place
  it, the panel says what it would make there ("Field here: about 110 food a year; floods").
- **Where things stand matters:**
  - fields give more on fertile soil and by the river, but a riverside field can flood (a levee
    shields what is near it);
  - the mill stands on the river, the fisher's hut on the riverside, the woodcutter next to forest
    (more forest, more wood), the quarry on or next to rock;
  - the shrine needs the valley's special spot (a spring or a standing stone), which some valleys have.
- **People:** everyone with their age and job; Auto-assign puts each person where they fit best (and
  two on building sites); tap a person for their card (skill, trait, family, story) and to give them a
  job by hand.
- **+1 month:** fields are sown in spring and harvested in September and October; people eat every
  month, more in a hard winter; stored food spoils a little (less with a storehouse). A short report
  follows, then the month's event, if any: a choice, sometimes a gamble on someone's skill.
- **Ledger:** last month's report, food months left, the four ways' renown and tier, the score so far.
  With a market, **Trade goods** sells what you have too much of and buys what you lack; food is dear in
  late winter and cheap after the harvest.

## The four ways

| way | buildings | strong where |
|---|---|---|
| Market town | market, trading post, wharf | by a ford and a wide river |
| Granary of the valley | mill, great barn, bakery | on fertile land |
| Craftsmen's village | smithy, pottery, weaving shed | near rock, forest and marsh clay |
| Pilgrims' rest | shrine, temple, pilgrims' hostel | in a valley with a special spot |

Each way's buildings earn renown every month (more where the valley suits them) and coin. After the
tenth winter the way with the most renown decides the ending, at three levels by score; famine,
sickness or everyone leaving can end the village sooner. Finished games go into the **Chronicle**.

## Settings

Difficulty: Gentle, Normal or Harsh (harvests, winters, floods and hard times); it applies to the next
valley.

The game is saved on every tap (`village.txt`), with `chronicle.txt` and `prefs.txt`.

## Files

- `src/main.lua`: the screens; bundled with `tools/gamekit` into `index.lua` by `bundle.py`.
- `game/`: `valley` (the generator), `rules` (buildings, yields, the month's economy, trade, floods),
  `people`, `events` (a small event engine shared with other games), `event_list` (this game's events),
  `sim` (the game as a whole: the month, the ways, the end), `text`, `rng`, `save`, and `bots` (automated
  players for the balance tests only).
- Tests: `test_valley.py`, `test_rules.py`, `test_people.py`, `test_events.py`, `test_sim.py`,
  `test_balance.py` (bots over hundreds of valleys), `test_riverstead.py` (playing by taps).
