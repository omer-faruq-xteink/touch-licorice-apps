# Knight's Tour — XTOS Licorice mini app (API 2.9)

Move a chess knight so that it visits every square exactly once.

- Boards **6x6** and **8x8** (on 5x5 a full tour does not exist from every square).
- The first tap places the knight. The squares it can jump to (not visited yet) carry a small
  ring; visited squares show their move number; the knight's square is framed twice.
- **Hint** frames the jump Warnsdorff's rule suggests (the square with the fewest onward jumps;
  following it usually completes the tour). **Undo**, **New**, size button.
- When the knight is stuck the game says how far it got and offers Undo; complete tours and the
  best result are kept per size. Saved after every move.

Files: `src/main.lua`, `bundle.py`, `test_knightstour.py` (plays complete tours on both sizes:
`python -I apps/knightstour/test_knightstour.py`).
