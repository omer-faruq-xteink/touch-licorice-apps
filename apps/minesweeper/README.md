# Minesweeper — XTOS Licorice mini app (API 2.9)

Open every cell that holds no mine; a number tells how many of the eight neighbours hold one.

- **Never a guess.** The mines are laid after the first tap, which always opens an empty area, and a
  board is kept only if logic alone clears it from there (single numbers, pairs of overlapping
  numbers, the mine count). Hint frames a cell that logic proves safe, a mine to flag, or a wrong
  flag; Hint after Hint wins every game.
- Sizes made for the 480x800 touch screen, cells a finger can hit: **Easy** 8x10 with 10 mines,
  **Normal** 9x11 with 17 (the default), **Hard** 10x13 with 27. Classic boards like 16x16 or 30x16
  would need cells under 30 px.
- A tap opens a cell. A **long press** sets or removes a flag (once per press, however long), or switch the **Dig / Flag** button so
  a tap flags. A tap on a number whose mines are all flagged opens its other neighbours.
- **Undo** takes moves back, also the one that hit a mine. Time (pauses over 30 s do not count),
  games won and the best time per size are kept; the game is saved after every move.

Files: `src/main.lua` (on the shared `tools/gamekit`), `bundle.py` (makes `index.lua`),
`test_minesweeper.py` (`python -I apps/minesweeper/test_minesweeper.py`, which also wins 75 games
from hints alone).
