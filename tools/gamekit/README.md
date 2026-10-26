# gamekit

Shared pieces for the API 2.9 puzzle games (Lights Out, Peg Solitaire, Nonograms, Knight's Tour):
text measuring and wrapping, storage helpers, side-button debounce, dialog boxes, framed buttons,
and a full refresh every 8 moves (`ctx:defer_full_refresh(0)`; its exact meaning is not
documented, so failures are ignored). `bundle.py` puts `gamekit.lua` and an app's `src/*.lua`
into its `index.lua`; `harness.py` is the offline test harness (lupa) the games' tests use.
Nothing is filled black: large black areas ghost on e-ink, and the host draws text black even
when asked for white.
