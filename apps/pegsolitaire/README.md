# Peg Solitaire — XTOS Licorice mini app (API 2.9)

Jump a peg over a neighbour into an empty hole; the jumped peg is removed. Leave as few pegs as
possible: one is a win, one in the centre of the English board the classic perfect game.

- Boards: **English** (33 holes, the centre empty, jumps along rows and columns) and **Triangle**
  (15 holes, the top empty, jumps in the six directions of the triangle). **Board** switches.
- Tap a peg to select it (framed); the holes it can jump to get a small mark; tap one to jump.
  Tap the selected peg again to let it go. Pegs are thick rings, holes small circles.
- **Undo** takes jumps back (also from the end box), **New** starts the board again. When no jump
  is left the game rates the result and keeps your best per board. Saved after every jump.

Files: `src/main.lua`, `bundle.py`, `test_pegsolitaire.py` (plays a full game to one peg on both
boards: `python -I apps/pegsolitaire/test_pegsolitaire.py`).
