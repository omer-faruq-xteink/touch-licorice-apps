# Mahjong Solitaire — XTOS Licorice mini app (API 2.9)

Clear the board by taking off matching pairs of free tiles.

- **Layout for the portrait screen:** 100 tiles in a 7x8 pyramid of stacks one to four high, tiles
  64x70 px. The board is drawn from above: each stack shows its top tile, and the tiles below it as
  stepped edges at the bottom right.
- **Free tile:** on top of its stack, with the stack to its left or to its right lower.
- **Faces** are drawn with lines and circles: dots 1-9, bamboo 1-9, the four winds (N E S W) and
  three dragons (a boxed stroke, a diamond, a double frame); four of each.
- **Every deal can be cleared:** it is made by playing a random game backwards. That solution is
  kept as a plan and follows your moves (two tiles of a kind paired differently just swap
  partners), so **Hint** shows a pair from which the board can still be cleared; if your moves
  closed every way, Hint says so (Undo or Shuffle).
- **Shuffle** deals the tiles left anew, again clearable; offered when no free pair is left.
  **Undo** takes pairs and shuffles back. Saved after every move; games cleared are counted.

Files: `src/main.lua` (on the shared `tools/gamekit`), `bundle.py` (makes `index.lua`),
`test_mahjong.py` (`python -I apps/mahjong/test_mahjong.py`).
