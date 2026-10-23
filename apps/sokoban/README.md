# Sokoban — XTOS Licorice mini app

A port of CPR-vCodex's Sokoban to the stock firmware's Lua mini-app host (API 0.8). Same rules:
one step at a time, a box is pushed when the cell behind it is free, solved when no box is off a
goal. Undo takes back one move with its push; Reset asks first.

## Your own level packs

The fork reads `.txt` packs from `/sokoban` on the SD card; an app cannot read the card, so the
packs ride inside the package's data section. Put any number of XSB / `.sok` / `.xsb` files (or a
whole folder of them) through the prepare script, pack, reinstall:

```bash
python apps/sokoban/prepare_data.py --clean "C:/path/to/my sokoban levels"   # folders or single files
python xtpack.py apps/sokoban                                                   # -> dist/sokoban.xtapp
```

For every pack the script writes `data/<name>.txt` (the file unchanged, line ends normalised) and
`data/<name>.idx.tsv`, one line per level with the byte offset of its first board line and its
title. The app seeks to that offset and reads just that level, so a pack of thousands of levels
costs one small read per level instead of filling the 1 MB Lua heap. Names are made to fit the
firmware's rule ("Original & Extra.sok" → `original_extra.txt`). Limit: 63 packs (two files each
plus the index of files; the firmware allows 128).

Formats, as downloaded: a level is a run of lines made of `# @ + $ * . - _` and spaces containing
a `#`; a following `Title:` line names it. That reads sokobano.de `.sok` files, YASC packs and bare
XSB. Run-length-encoded single-line levels are not supported.

Shipped by default: **Microban** (155) and **Sasquatch** (50) by David W. Skinner, **LOMA** (100), **Microcosmos** (40) and **Minicosmos** (40) by Aymeric du
Peloux, both as published on sokobano.de with the authors' permission (the notices stay in the
files). The first 12 Microban levels are also embedded in `index.lua` as the fallback when the data
section is unavailable.

## Controls

| input | action |
|---|---|
| swipe | move / push in that direction |
| tap on the board beside the player | move toward the tap (dominant axis) |
| side buttons | up / down; after a solve the lower button goes to the next level |
| Undo | take back the last move |
| Reset | restart the level (Yes / No) |
| Prev / Next | other levels in the pack (wraps) |
| Set | the pack list: tap a pack to play it; Page up / down; Back. Side buttons page too |
| Home pad → Leave app | exit; the exact position comes back next time |

`ctx.state` keeps the move history (LURD letters, upper case = push), the current pack, the last
level of every pack and the best move count per level.

Drawing: walls are hatched squares, goals small circles, boxes nested squares (crossed when on a
goal), the player a double circle. Cell size adapts to the level, down to 12 px.

## Verification status

Offline under Lua 5.4 (`test_sokoban.py`, `ctx.data` emulated from the firmware's reader code and
fed the packed files): every level of every pack read through the index equals the whole-pack
parse, and packs are never read whole; move, wall, push, undo; a BFS-found solution played through
swipes ends in "Solved" with the best recorded and the lower side button advancing; Undo, the Reset
dialog, Prev / Next wrap; the pack list with remembered per-pack positions; tap-beside-player;
history replay on resume; the draw budget over all 255 levels; the no-data fallback. The package
decrypts and its data section parses with the firmware's XTDT checks, every index offset landing on
a board line. **Not yet run on the device.**
