# Lights Out — XTOS Licorice mini app (API 2.9)

A 5x5 board of lights. Tapping a square switches it and its four neighbours; switch them all off.

- A lit square is a thick ring (no black fill: it ghosts on e-ink).
- Every puzzle can be solved: it is made by pressing random squares from the dark board. A solver
  (linear algebra over GF(2)) finds the fewest presses, shown as the **Target**.
- **Hint** frames one square of a fewest-press solution from where you are. **Undo** takes presses
  back. **New** makes a new puzzle; the level button (**Easy / Normal / Hard**) sets how scrambled
  the next one is (targets of at least 3 / 6 / 10 presses).
- Saved after every press; solved puzzles are counted.

Files: `src/main.lua` (the game, on the shared `tools/gamekit`), `bundle.py` (makes `index.lua`),
`test_lightsout.py` (`python -I apps/lightsout/test_lightsout.py`).
