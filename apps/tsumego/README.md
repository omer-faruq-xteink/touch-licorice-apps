# Go problems — XTOS Licorice mini app (API 2.9)

Life-and-death problems (tsumego) for the X4 Pro: find the move that kills a group or saves
it. Black and white stones suit the e-ink screen, and every problem is a few calm moves.

## Problems

- **Built in: 620 corner problems in three levels.** Easy (300: one move kills or lives),
  Medium (200: two moves), Hard (120: three or more), each from easiest to hardest.
  They were made for this app by `make_problems.py`, not copied from a book: a corner eye space,
  the defender's stones around it and the attacker's wall, then tuned until the group's fate
  depends on who plays first. A solver (`goboard.py`) reads each one out and keeps it only when
  exactly one first move works and no ko is involved; it also writes the strongest reply to
  every move and the refutation of every wrong first move. Free to share (CC BY 4.0, omer-faruq).
- **Your own SGF files.** Copy `.sgf` files into `AppFiles/tsumego/` on the SD card (USB mode).
  A file holding several problems becomes a collection of its own; files holding one problem
  each are gathered under **Single files**. A line counts as correct when it ends at a comment
  with RIGHT or Correct (the usual marks of problem collections); a tree with no such marks counts
  every line as correct except those marked Wrong. Collections of this kind are easy to find
  online; check that you may use them.

## Playing

- The task is above the board ("Black to kill", "Black to live", or the file's own comment).
  The board shows only the corner in play, as large as it fits; the board's real edges are thick.
- Tap a point to play. The other side answers from the problem's tree. A move that is not in the
  tree is refused ("Not the move"). A known wrong move stays on the board: **Why** (in place of
  Hint) then plays the reply that refutes it (often the key point itself, so it is not shown
  unasked; it may capture your stone), and **Retry** sets the problem up again.
- **Hint** marks the point; Hint again plays it (the problem then counts as solved with help).
- **Next**, the side buttons or a swipe move between problems. The last button chooses the
  collection. Progress (where you are, which problems you solved) is kept per collection.

## Build

```bash
python -I apps/tsumego/make_problems.py      # data/*.txt (about half an hour on 12 cores)
python -I apps/tsumego/bundle.py             # tools/gamekit + src/main.lua -> index.lua
python -I apps/tsumego/test_tsumego.py       # offline; also solves every built-in problem by taps
python xtpack.py apps/tsumego
```
