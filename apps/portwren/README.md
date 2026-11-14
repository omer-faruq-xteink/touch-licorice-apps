# Port Wren — XTOS Licorice mini app (API 2.0)

A detective game in a small 1920s harbour town. Every case is a new murder, made from a seed and
proven solvable before you see it: search places, question people, show them what you found, catch
the lie and name the culprit, the motive and the means.

## Playing

- **The case file** is the hub. It tells you who died, where, and when (as close as the doctor can
  say), and lists the places of the case with who is there now. People move: at work in the morning
  and afternoon, out in the evening, home at night. **Wait** passes the rest of the current part of
  the day.
- **Time:** a case has two days (three for a Long case) of four parts each, and each part holds
  three actions. Searching a place costs one; talking to someone costs one, and covers the whole
  conversation. Someone who trusts you little needs one more the first time. Walking about, the
  notebook and the board cost nothing.
- **A place:** **Search** it (once, until something new happens) and tap a person to talk.
- **Talking:** the first talk with a suspect gives their account of the evening. **Ask about** the
  victim, the evening or another suspect; **Show clue** shows them something you found. Some
  people only tell what they know when asked the right thing or shown the right clue.
- **Notebook:** every clue found, numbered. **Statements** is a table of where each suspect says
  they were, half-hour by half-hour; a cell a clue contradicts gets a heavy frame.
- **Board:** tap a clue number, then a suspect, to tie them (your own notes; tap again to untie).
- **Accuse:** pick the culprit, the motive and the means, then confirm. All three right: solved.
  The culprit right but the motive or means wrong: solved, partly. The wrong person: the killer
  strikes again that night, a second victim, new clues and one more day. A second wrong accusation,
  or running out of time twice, and the killer flees; the end of the case tells what really
  happened either way.

## How to reason

- Physical evidence and documents are certain.
- A witness is believed until a certain fact contradicts them; after that, nothing they say counts.
- A suspect's own account never clears them; it matters only when it is contradicted.
- A suspect is cleared when they could not get the means, or when a believed witness or evidence
  puts them somewhere else at the time of the crime.
- The culprit had the means and the motive, and their account of that time is shown to be a lie
  (or they are placed at the scene).

Cases come in four kinds, never named until the end: a classic case, a false alibi, a question of
time, and (Long cases only) an innocent liar. Long cases add two false trails: true facts that point
at the wrong people.

## Career and single cases

- **Career:** one town of about two dozen people that remembers. The dead and the jailed leave,
  families remember who you arrested, and someone you wrongly accused trusts you less next time.
  Newcomers move in when the town thins. Solving earns reputation; rank (Constable, Sergeant,
  Inspector, Chief Inspector) opens the harder kinds of case.
- **Single cases:** every case in a new town, no rank, every kind of case open.
- **Settings:** case length (Short: 4 suspects, about 25 minutes; Long: 6 suspects, about an hour),
  the way to play, and Reset career. Changes apply from the next case.

The game is saved on every tap: `town.txt` (the career), `case.txt` (the open case) and
`prefs.txt` (settings). Closing the app while a case is being prepared prepares the same case again.

## Files

- `src/main.lua`: the screens; bundled with `tools/gamekit` into `index.lua` by `bundle.py`.
- `game/`: package files loaded when needed: `rng` (seeded random numbers), `save` (the save
  format), `text` (names, places and every sentence), `town`, `gen` (the case generator) and
  `solver` (the reasoning rules, and the check that accepts a case).
- Tests: `test_cases.py` (generator and solver over thousands of seeds, with an independent
  brute-force checker), `test_text.py`, `test_town.py`, `test_portwren.py` (playing by taps).
