# Queens — XTOS Licorice mini app

Two logic puzzles on one board. The grid is split into regions (thick borders).

- **Queens**: place one queen in every row, every column and every region.
- **Star Battle**: place two stars in every row, every column and every region.

In both, no two pieces may touch, not even diagonally. Every puzzle has one solution, found by
reasoning: no guessing.

## Playing

- Tap a cell once for a **cross** (no piece here), again for a **queen** or **star**, a third time
  to clear it.
- **Dots** (on by default, under More): the cells your pieces already rule out (around a piece, or
  in a row, column or region that is full) get a dot, so you need not cross them.
- A ringed piece breaks a rule (two touching, or too many in a row, column or region), and the
  line under the board says which.
- **Undo** takes back a tap. **Hint** removes a wrong piece or a cross where a piece belongs, else
  places a right piece (underlined, and kept). **Next** moves to the next puzzle; **More** picks a
  size, goes back a puzzle, starts over, or turns the dots off. The side buttons step through the
  bank.
- Your place, your marks and the puzzles you solved are kept between runs. A short Back press
  offers to exit.

Regions are told apart by their borders, as printed Star Battle puzzles are, since the panel has no
colours.

## Banks

| bank | size | pieces | puzzles |
|---|---|---|---|
| `queens-6x6` | 6 x 6 | 1 | 200 |
| `queens-7x7` | 7 x 7 | 1 | 200 |
| `queens-8x8` | 8 x 8 | 1 | 200 |
| `queens-9x9` | 9 x 9 | 1 | 200 |
| `stars-9x9` | 9 x 9 | 2 | 200 |
| `stars-10x10` | 10 x 10 | 2 | 200 |

(An 8 x 8 board has only two ways to place two stars a row and column, so Star Battle starts at
9 x 9.)

The puzzles are made by `make_bank.py` (our own code, no third-party puzzles): a solution is placed
at random, regions are grown around it (none over twice the board's width), then reshaped a cell
at a time while that leaves fewer cells a reasoning solver cannot settle. A puzzle is kept when the
solver settles every cell, which also proves its solution is the only one.

| level | techniques | banks |
|---|---|---|
| 1 | a full row, column or region rules out the rest, a piece the cells around it; a unit with only as many cells left as pieces it needs takes them all; a region left in one row (or column) rules out the rest of it, and the other way round | 6x6 |
| 2 | the same for groups of two or three regions, rows or columns | 7x7 |
| 3 | a cell is ruled out when a piece there would leave some row, column or region without room | 8x8, 9x9, both Star Battle sizes |

The 8 x 8 and 9 x 9 Queens and the 10 x 10 Star Battle puzzles are never solved by level 1 alone.

  python -I apps/queens/make_bank.py [COUNT]    # default 200 a bank

## Files

`src/main.lua` (on `tools/gamekit`), `bundle.py` (builds `index.lua`), `make_bank.py`, `data/`
(the banks), `test_queens.py` (`python -I apps/queens/test_queens.py`).
