# gamekit

Shared pieces for the API 2.9 puzzle games (Lights Out, Peg Solitaire, Nonograms, Knight's Tour,
Minesweeper, Mahjong):
text measuring and wrapping, storage helpers, side-button debounce, dialog boxes, framed buttons,
and `kit.moved()` as the hook for a periodic full refresh (none is asked for: API 2.9's
`ctx:defer_full_refresh(n)` did not trigger one on the device, and the games showed no ghosting
problem without it). `bundle.py` puts `gamekit.lua` and an app's `src/*.lua`
into its `index.lua`; `harness.py` is the offline test harness (lupa) the games' tests use.
Nothing is filled black: large black areas ghost on e-ink, and the host draws text black even
when asked for white.
