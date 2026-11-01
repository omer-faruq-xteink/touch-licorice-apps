# Kakuro (Cross Sums) — XTOS Licorice mini app (API 2.0)

Fill the white cells with digits 1 to 9. Each run of white cells, across or down, adds up to the
clue at its start (across in the top right of the clue cell, down in the bottom left), and no
digit appears twice in a run.

## Playing

- Tap a cell, then a digit. **Erase** clears it.
- Under the grid are the selected cell's runs and every way to make them: `Across 16 in 2: 79`.
- A digit repeated in a run, or a run that is full and adds up wrong, is crossed.
- **Hint** fills the selected cell (or the first open one); hinted digits are underlined.
- **Next**; **More**: Easy, Medium and Hard, the previous puzzle, Start over, How to play. Left
  and right move the selection, up and down step through the bank. Your place and the digits are
  kept.

Clue cells are drawn with a double border and a diagonal, not filled black: large black areas
ghost on e-ink. Empty blocks open to the edge of the board are left blank; an enclosed one keeps
its box, so it is not taken for a cell to fill.

## Banks

| bank | board | puzzles |
|---|---|---|
| `6x6-easy` | 6 x 6 (5 x 5 to fill) | 200 |
| `7x7-medium` | 7 x 7 | 200 |
| `8x8-hard` | 8 x 8 | 200 |

Made by `make_bank.py` (our own generator, no third-party puzzles). A layout symmetric under a
half turn is filled with digits; while reasoning leaves a cell open, the digit of an open cell is
changed so that more is settled. A puzzle is kept when run reasoning alone fills it (each cell
keeps the digits some filling of each of its runs gives it), which also makes its solution the
only one. A bank line is the solution itself; the app works out the clues.

## Build

```bash
python -I apps/kakuro/make_bank.py       # data/, 200 puzzles a bank (a few minutes)
python -I apps/kakuro/bundle.py          # tools/gamekit + src/main.lua -> index.lua
python -I apps/kakuro/test_kakuro.py     # offline
python xtpack.py apps/kakuro
```
