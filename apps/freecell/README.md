# FreeCell — XTOS Licorice mini app (API 2.9)

The solitaire: move every card to the four foundations, ace to king by suit, using four free
cells and the eight columns (down in alternating colours).

- **Microsoft's numbered deals**, 1 to 32000 (deal 1 starts JD 2D 9H JC ...). **New**: the next
  deal, a random one (1-1000) or one by number.
- **Tap a card** to pick it up with the cards above it, as many as the free cells and empty
  columns let move at once; tap where it goes: a column, a free cell, its foundation. Tap a picked
  card again to send it home or to the first place it fits. Cards no other card can need go home
  by themselves.
- **Hint** shows a move of a winning line for deals 1 to 1000: their solutions ship with the app
  (`data/sol00.txt` ...). The line is recognised after moves made in another order; off it, Hint
  offers to undo back to it (the position may still be winnable).
- **Undo** (also the side buttons up / left; down / right is Hint), **Restart**. Saved after every
  move; deals won are counted.
- Cards are drawn, not printed (the fonts may lack the suit signs): clubs and spades solid,
  diamonds and hearts hollow.

Files: `src/rules.lua` (rules, deals, solver), `src/main.lua` (the game, on `tools/gamekit`),
`make_solutions.py` (solves deals 1..1000 with the same rules and checks each solution by
replaying it), `bundle.py`, `test_freecell.py` (`python -I apps/freecell/test_freecell.py`).
