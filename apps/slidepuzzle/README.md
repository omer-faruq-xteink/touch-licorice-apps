# Slide Puzzle — XTOS Licorice mini app (API 2.9)

The classic sliding-tile puzzle, ported from the KOReader plugin
[slidepuzzle.koplugin](https://github.com/omer-faruq/slidepuzzle.koplugin): put the tiles in order
with the gap in the bottom-right corner. Boards from 3x3 to 7x7; every puzzle is solvable (it is
made by sliding tiles at random from the solved board).

## How to play

- **Tap** a tile next to the gap to slide it, or **swipe**: the tile on the far side of the gap
  slides into it. The side buttons slide too.
- A tile already in its final place gets a **second frame** inside its border, so you see at a
  glance what is done. (The plugin draws it black; on this e-ink screen a black tile leaves
  ghosts, and the host would draw its number black too.)
- The header shows the moves and the time, and your best time and fewest moves for the size.
- **New** shuffles a new puzzle, **Size** picks 3x3 to 7x7 (each size keeps its own puzzle),
  **Stats** lists the best time, fewest moves and games played per size, **Settings** has the
  language (English, Português, Español, Français, Deutsch, 한국어, Türkçe), "always start a new
  puzzle on open", and resetting the best results.
- Everything is saved after every move; leaving and coming back continues the puzzle.

The clock is not redrawn every second (that would refresh the e-ink screen each second): it
advances with your moves, and a pause between two moves counts at most 60 seconds, so time away
from the game does not count.

## Files

- `src/slidepuzzle_game.lua`, `src/slidepuzzle_i18n.lua` — the game rules and translations,
  unchanged from slidepuzzle.koplugin v1.3.0 (commit 3b9805d).
- `src/ui.lua` — the device screen.
- `bundle.py` — puts them into `index.lua` (the device has no `require` for package files);
  `build_all.py` runs it. Edit `src/`, not `index.lua`.
- `test_slidepuzzle.py` — plays through the screen offline: `python -I apps/slidepuzzle/test_slidepuzzle.py`.

## License

Slide Puzzle is licensed under the **GNU GPL v3** (`LICENSE` in this folder), like the KOReader
plugin it comes from; the rest of this repository is MIT.
