# Case Files — XTOS Licorice mini app

Logic-grid mysteries. Each case has a few people, and each of them has one item of every group: a
floor and an arrival time at the Seaview Hotel, a car and a destination on the Night Train, a
place and a cake at the village bake-off. The clues tell you who has what; the grids are where you
work it out. Every case has one answer, reached by reasoning: no guessing.

## Playing

- **The clues** are at the top, under what the case asks for. Tap a clue to cross it out once you
  have used it (tap again to bring it back). A hard case has more clues than fit: the line under
  them turns the page.
- **The grids**: one for each pair of groups (Name / Floor, Name / Time, Floor / Time...), chosen
  by the tabs above the grid (or the side buttons). Tap a cell once for a **cross** (these two do
  not go together), again for a **tick** (they do), a third time to clear it. A tick dots the rest
  of its row and column. Two ticks in one row or column are ringed.
- Use the grids together: if Ada stayed on the 2nd floor and the guest on the 2nd floor lost the
  key, Ada lost the key. *Either ... or* means exactly one of the two is true; *of A and B, one ...
  and the other ...* means A and B are those two, in some order.
- The case is **closed** when every person has the right tick in each of the people's grids (the
  first tabs); the answer is shown.
- **Undo** takes back a tap. **Hint** removes a wrong mark, else puts a right tick (underlined, and
  kept). **Check** tells how many marks are wrong, without saying which. **More** picks a level,
  goes to the previous or next case, starts over, or shows the rules (and the answer of a closed
  case).
- Your place, your marks and crossed-out clues, and the cases you closed are kept between runs. A
  short Back press offers to exit.

## Cases

| level | groups | people | cases | clues |
|---|---|---|---|---|
| Easy | 3 | 4 | 200 | 3 to 8 |
| Medium | 4 | 4 | 200 | 5 to 10 |
| Hard | 4 | 5 | 200 | 6 to 12 |

Six settings (`src/themes.lua`): The Seaview Hotel, The Night Train, The Village Bake-off, The Old
Library, Harbour Morning and Museum Night, each with its people and three groups, at least one of
them in order (floors, times, places in a contest), for clues such as *Ada arrived two hours after
the guest who lost the key*.

The cases are made by `make_bank.py` (our own code and settings, no third-party puzzles): a secret
answer is drawn at random, then true clues are added until a solver doing the player's reasoning
settles every cell of every grid, and each clue is dropped that is not needed. The reasoning:

- a tick rules out the rest of its row and column; a row or column with one open cell left takes it
- across grids: a tick with a tick (or a cross) gives a tick (or a cross); an item none of whose
  possible partners in a third group goes with Z does not go with Z
- each clue rules out what it can from what is known (for order clues, the values each side can
  still have)

When that settles every cell, the answer is the only one.

  python -I apps/casefiles/make_bank.py [COUNT]    # default 200 a level

A case is one line of a bank (`data/easy.txt`, `medium.txt`, `hard.txt`), all lines of a bank the
same length so the app seeks straight to case N; `make_bank.py`'s docstring has the format.
`src/case.lua` reads a line and words its clues from the setting's templates.

## Files

`src/main.lua` (on `tools/gamekit`), `src/case.lua`, `src/themes.lua`, `bundle.py` (builds
`index.lua`), `make_bank.py`, `data/` (the banks), `test_casefiles.py`
(`python -I apps/casefiles/test_casefiles.py`: every case solved by reasoning with no clue to
spare, every clue worded, and the app played by taps).
