# Lamplighter — XTOS Licorice mini app

A wiring puzzle. Each tile holds a piece of wire from its centre to some of its sides; one tile is
the source (the framed square), the tiles with a single wire are lamps. Turn the tiles until power
from the source reaches every lamp: all the wires joined in one network, no loose ends, no loops,
nothing running off the board. Every puzzle has one solution, found by reasoning: no guessing.

## Playing

- Tap a tile to turn it a quarter clockwise. Power runs from the source along wires that meet:
  lit wires are thick, lit lamps filled, the rest thin and hollow.
- **Lock**: while it is on (the button says *Lock on*), a tap frames a tile you are sure of, so a
  stray tap cannot turn it; tap it again to free it.
- **Undo** takes back a turn. **Hint** turns a tile to its place (next to the lit part when one
  there is wrong) and frames it with a thicker line; it stays. **More** picks a size, goes to the
  previous or next puzzle, starts over, or shows the rules. The side buttons step through the
  puzzles.
- The line under the board counts the lamps lit and your moves. When everything is lit, *Next*
  takes you on.
- Your place, your tiles and locks, and the puzzles you solved are kept between runs. A short Back
  press offers to exit.

## Puzzles

| level | board | puzzles |
|---|---|---|
| Easy | 5 x 5 | 200 |
| Medium | 7 x 7 | 200 |
| Hard | 9 x 9 | 200 |

The puzzles are made by `make_bank.py` (our own code, no third-party puzzles): a random spanning
tree of the grid (Wilson's algorithm) is the solution, kept when a solver reasoning as a player
does settles every tile, which also proves the solution is the only one. Its rules:

- a wire cannot lead off the board, and two neighbours agree on the wire between them
- a turn that would close a loop with the wires already settled is ruled out
- a turn that would close off a group of tiles from the rest (no wire left that could join it to
  anything) is ruled out, unless the group is the whole board

Medium and hard puzzles always need the last two rules. The tiles then start turned at random.

  python -I apps/lamplighter/make_bank.py [COUNT]    # default 200 a level

## Files

`src/main.lua` (on `tools/gamekit`), `bundle.py` (builds `index.lua`), `make_bank.py`, `data/`
(the banks), `test_lamplighter.py` (`python -I apps/lamplighter/test_lamplighter.py`).
