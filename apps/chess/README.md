# Chess puzzles — XTOS Licorice mini app (API 2.9)

Tactics puzzles from the [Lichess puzzle database](https://database.lichess.org/#puzzles) (CC0):
find the best move, then keep going until the line is over.

- **Six banks**, about 400 puzzles each, easiest first: **Mate in 1**, **Mate in 2**, **Easy**
  (rated 800-1200), **Medium** (1200-1600), **Hard** (1600-2000), **Expert** (2000-2400). Only
  well-tried puzzles (played at least 1000 times, liked by at least 90 % of players).
- The opponent's move that sets the puzzle is made for you and marked; the board turns so your
  side is at the bottom. **Tap a piece, then its square.** A right move gets the reply at once; a
  wrong one is counted and you try again.
- **Hint** frames the piece to move, a second Hint its square; **Show** makes the move for you.
  **Next** (or the side buttons) moves through the bank; the last button picks a bank. After a
  puzzle its themes are shown (fork, pin, mate in 2 ...). Puzzles solved, and solved without a
  mistake or help, are counted per bank; a puzzle left half way is resumed.
- Pieces are drawn (the fonts may lack chess symbols): white ones as outlines, black ones solid.
  Dark squares have an inner frame.

`make_banks.py` picks the banks from `lichess_db_puzzle.csv.zst` (needs `pip install zstandard`).
Files: `src/main.lua` (on `tools/gamekit`), `data/*.txt`, `bundle.py`, `test_chess.py`
(`python -I apps/chess/test_chess.py`, which solves all of them by taps).
