# Chess — XTOS Licorice mini app (API 2.0)

A whole game of chess against the reader, at four levels, or two players on one reader.

- **Tap a piece, then a square.** The piece's moves are marked: a dot on an empty square, a ring
  round a piece it takes. A pawn reaching the last rank asks what it becomes. The last move is
  marked on its squares, and a king in check is framed.
- **The reader plays** at four levels: **Beginner** (one move ahead, with plenty of mistakes),
  **Easy**, **Medium** and **Hard**. It thinks in short slices, so the screen stays responsive;
  Hard thinks longest (up to about 8 seconds) and sees furthest.
- **Undo** takes back your last move and the reader's reply; **Hint** frames a good move for you;
  **New game** picks the opponent (a level, or **Two players**) and your side (White, Black or
  either). Playing Black turns the board.
- The game ends on checkmate, stalemate, threefold repetition, the 50-move rule or too little
  material to mate, and says so. The last moves are shown in chess notation (Nf3, exd5, O-O).
- The game is kept: leave the app and it carries on where you were.

Battery: the reader only computes on its own move, a few seconds at most; while it is your move
nothing runs, and the e-ink screen uses power only when it changes.

Files: `src/rules.lua` (the rules: legal moves, check, mate, the draws, notation), `src/engine.lua`
(alpha-beta search with iterative deepening and a quiescence search, material and piece-square
evaluation), `src/pieces.lua` (the drawn pieces, as in Chess puzzles), `src/main.lua` (on
`tools/gamekit`), `bundle.py`, `test_chessplay.py` (`python -I apps/chessplay/test_chessplay.py`:
perft of standard positions, the draws, notation, the engine, and the game by taps). Each think is
noted in `think.txt` (level, depth reached, time), in the app's private folder.
