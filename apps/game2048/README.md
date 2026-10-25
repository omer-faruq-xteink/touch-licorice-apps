# 2048 — XTOS Licorice mini app

A port of CPR-vCodex's 2048 to the stock firmware's Lua mini-app host (API 0.8). Same rules: slide,
merge each adjacent equal pair once per move, score adds merged values, a 2 (90%) or 4 (10%) spawns
after every move that changed the board, game over when full with no merges, a message once at
2048 and play continues.

## Controls

| input | action |
|---|---|
| swipe left / right / up / down | slide the tiles |
| side buttons (upper / lower) | slide up / down |
| tap **New game** | asks "Start a new game?" with Yes / No |
| Home pad → Leave app | exit; board, score and best are restored next time |

Tile weight is shown by outline thickness (there is no fill in this API): 2 and 4 are thin, 2048 is
seven nested outlines. A full e-ink refresh runs every 10 moves to clear ghosting.

## Build and install

```bash
python xtpack.py apps/game2048
```

writes `dist/game2048.xtapp` (the app id must be letters only, so it is not `2048`).
Copy it to the SD card root, install from All Files, then open it from the drawer's Ink App
(unlocked once with ten taps on Settings → About → Model).

## Test

`index.lua` exposes its rules under `__TEST.api` when that global exists; the Lua 5.4 test in the
session scratchpad (`test2048.py`, via `lupa`) checks the slide rules, the four directions, game-over
and win detection, a 2000-input random playthrough, the draw-command count on a fresh and a
worst-case board (limit 1024 per frame), the confirm dialog and state restore. Not yet run on the
device.
