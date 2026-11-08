# gamekit

Shared pieces for the API 2.9 puzzle games (Lights Out, Peg Solitaire, Nonograms, Knight's Tour,
Minesweeper, Mahjong):
text measuring and wrapping, storage helpers, side-button debounce, dialog boxes, framed buttons,
and `kit.moved()` as the hook for a periodic full refresh (none is asked for: API 2.9's
`ctx:defer_full_refresh(n)` did not trigger one on the device, and the games showed no ghosting
problem without it). `bundle.py` puts `gamekit.lua` and an app's `src/*.lua`
into its `index.lua` (with shared modules such as `cards.lua`, the playing cards of FreeCell and
Klondike, when an app asks for them); `harness.py` is the offline test harness (lupa) the games' tests use.
`ai.lua` is the optional AI questions of the reading apps (services, requests, answers, the
Settings → AI logic) and `aiui.lua` their screens for the apps built like RSS (RSS, Instapaper,
Readwise, wallabag), which `bundle_reader.py` bundles; Hacker News asks for `ai.lua` as a
shared module and draws its own screens. Each package gets its own copy, so no app needs another
installed. `ai_reader_test.py` is the AI check those apps' tests run.
Nothing is filled black: large black areas ghost on e-ink, and the host draws text black even
when asked for white.
