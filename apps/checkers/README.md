# Checkers — XTOS Licorice mini app (API 2.0)

Two draughts games against the reader, at four levels, or two players on one reader.

- **Checkers** (English / American): 12 men each on the dark squares. Men move one square
  diagonally forward and take by jumping; kings move and jump one square in any diagonal.
  Captures are compulsory and go on while the piece can jump again; a man crowned by a jump stops
  there. Black moves first.
- **Dama** (Turkish draughts): 16 men each on the second and third rows, every square used. Men
  move one square forward or sideways and take the same way; kings move any distance along a row
  or column and take a piece any distance away, landing on any empty square beyond. The line that
  takes the most pieces must be played; pieces taken leave the board at once; a king may not turn
  back between two captures. A man reaching the far row during a capture finishes it as a man and
  is crowned when the move ends. White moves first.
- **Tap a piece, then where it goes**: its moves are marked (a dot, or a ring for a capture), and
  a capture goes the whole way in one tap. While a capture is due, only pieces that can take can
  be picked. The last move is marked, with a small cross where pieces were taken.
- **Undo** takes back your last move and the reader's reply; **Hint** frames a good move; **New
  game** picks the rules, the opponent (Beginner, Easy, Medium, Hard or Two players) and your side.
- A side with no move left loses; 40 moves each without a capture or a man moving, or the same
  position three times, is a draw. The game is kept when you leave.

The reader thinks only on its own move (up to about 8 seconds on Hard) and nothing runs while it
is your move. Files: `src/rules.lua` (both rule sets), `src/engine.lua` (alpha-beta, captures
searched to the end), `src/main.lua` (on `tools/gamekit`), `bundle.py`, `test_checkers.py`
(`python -I apps/checkers/test_checkers.py`: perft of English checkers, the Dama rules, the
engine, and games by taps).
