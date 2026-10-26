# Sudoku — XTOS Licorice mini app

A port of CPR-vCodex's Sudoku to the stock firmware's Lua mini-app host (API 2.9; API 0.8 before
v0.9.0). Same rules: givens are fixed, "solved" is a full grid with no repeated digit in any row,
column or 3x3 box, optional marking of the cells that currently break a rule. Digits use the
large system font and the grid solid 2 px / 4 px lines, so it reads on panels that show thin
strokes faintly. Progress is kept in `state.txt` (and the host's `ctx.state`, which is all the
API 0.8 version used, so an update should keep the puzzle you were on).

## Puzzle banks: data files inside the package

The device cannot read the SD card from an app, but the `.xtapp` has a **data section** the app
reads through `ctx.data`. `xtpack.py` packs every `*.txt` / `*.tsv` / `*.csv` in `apps/sudoku/data/`
into it and writes `banks.tsv` (`file<TAB>count<TAB>stride<TAB>label`). Files are used **as
downloaded**: the app recognises the sudoku-exchange line (`<id> <81 digits> <rating>`), line81
(`<81 chars>`, `0`/`.`/`-` for blanks) and Kaggle CSV (`<puzzle>,<solution>`). Each file needs one
uniform line length (the packer drops odd lines and says so) so puzzle N is read at `(N-1) * stride`.

`prepare_data.py SRC_DIR` fills `data/` from the public-domain
[sudoku-exchange puzzle bank](https://github.com/grantm/sudoku-exchange-puzzle-bank) (600 puzzles
per difficulty by default) and refreshes the 40-puzzle **built-in fallback** embedded in
`index.lua`, which the app uses when the data section is missing or fails to open. The status line
says which bank is active.

Every puzzle has a single solution (checked), and the source rates each one with Sukaku Explainer:
easy 1.2 (singles), medium 1.5-2.3 (locked candidates, pairs, triples), hard 2.5-4.7 (up to X-wing,
swordfish, XY-wing). The diabolical bank is limited to 5.0-6.9 (chains), with
`--max-rating diabolical=6.9`: from about 7.0 up the source's puzzles need dynamic forcing chains
and nets, which come down to systematic trial and error.

To add your own bank: drop the file into `data/`, run `python xtpack.py apps/sudoku`, reinstall.
Names: 1..64 chars of letters, digits, `-`, `.`, `_`, lowercase `.txt` or `.tsv` (`.csv` is
renamed to `.txt` by the packer). At most 127 files.

## Controls

| input | action |
|---|---|
| tap a cell | select it (double outline) |
| tap 1–9 | enter the digit into the selected cell |
| Erase | clear the selected cell |
| Chk on / off | toggle mistake marking (an X in the cell's corner) |
| Next / Bank | next puzzle in this bank / switch to the next bank |
| side buttons | previous / next puzzle |
| Home pad → Leave app | exit; the current grid, selection and position are restored next time |

Digits you entered have a short underline; givens do not.

## Build

```bash
python apps/sudoku/prepare_data.py PATH_TO_DOWNLOADED_BANK   # once, or when changing the banks
python xtpack.py apps/sudoku                                 # -> apps/sudoku/sudoku.xtapp
```

## Verification status

Offline, under Lua 5.4 with a `ctx.data` emulation written from the firmware's own reader code:
format parsing, conflict detection, solved detection, bank index and seek-based reads against the
real data files, a full solve through taps, the draw budget, controls, state resume and the
no-data fallback all pass. The package's data section decrypts and parses with the firmware's XTDT
checks. **Not yet run on the device**; the data section is the first time this path is exercised.
