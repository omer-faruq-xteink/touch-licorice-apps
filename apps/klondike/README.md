# Klondike — XTOS Licorice mini app (API 2.9)

The classic solitaire. Build the four foundations up by suit from the aces; in the seven
columns cards go down in alternating colours, and an empty column takes a king.

- **Tap the stock** to turn cards, one or three at a time (**Draw 1 / Draw 3**, from the next deal
  on), and to turn the waste over when the stock is empty.
- **Tap a card** to pick it up with the cards above it, then tap where it goes: a column or a
  foundation. Tap a picked card again to send it home or to the first place it fits. Foundation
  cards can come back down. A column left with face-down cards only turns its top one up.
- **Hint** shows a useful move: a card home, a move that turns up a hidden card, a waste card
  onto a column, else the stock; it says so when going round the stock no longer helps. Klondike
  deals hide cards, so this is advice rather than a guaranteed winning line.
- **Finish** (in place of Hint) sends every card home once nothing is hidden or left to draw.
- **Undo** (also the up / left side buttons; down / right turns the stock), **New**: a random deal,
  the same deal again, or one by number (1 to 1 000 000; deals are reproducible). Saved after
  every move; deals won are counted.
- Cards as in FreeCell (`tools/gamekit/cards.lua`): black suits solid, red suits hollow.

Files: `src/rules.lua`, `src/main.lua` (on `tools/gamekit`), `bundle.py`, `test_klondike.py`
(`python -I apps/klondike/test_klondike.py`, which plays 60 deals by following Hint).
