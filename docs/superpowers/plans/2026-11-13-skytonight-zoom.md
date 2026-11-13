# Sky Tonight 1.1.0 Zoom, Pan and Cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tap the sky chart to zoom in 2.5x there, drag to pan, and read a card about the constellation under the finger (English, all 88), with deep-sky objects drawn while zoomed.

**Architecture:** draw_sky in `src/sky.lua` gains a view transform (zoom, centre in chart pixels) applied after the existing stereographic projection, a mask over the non-chart areas, and a card block that replaces the facts while zoomed. New package data (`bounds.txt`, `objects.txt`, `cards.txt`; `names.txt` gains the IAU abbreviation) is read on the first zoom. `src/app.lua` handles down/up pointer pairs (tap vs drag), Zoom out, Back.

**Tech Stack:** Lua 5.4 subset on XTOS Licorice (API 2.9), Python 3 + lupa for tests (`test_sky.py`), `make_data.py` for data.

**Spec:** docs/superpowers/specs/2026-11-13-skytonight-zoom-design.md

## Global Constraints
- ZOOM = 2.5; the chart is CX 240, CY 322, R 206; the zoomed window is the band y 92..540, full width.
- A frame: <= 1024 drawing commands (MAX_CMDS 1000 in sky.lua), on_draw with `ctx.budget:extend()`.
- The full chart, the lock screen and -1 h / +1 h / Now / Place behave exactly as in 1.0.1.
- Card text is original, English; constellation names keep the app's language (names.txt).
- Data is read with `ctx.package:read` (pread), the new files only on the first zoom.
- Version 1.1.0; API 2.9 unless a newer feature is needed (newest allowed).
- Lint: `python tools/lualint55.py`; tests: `python -I apps/skytonight/test_sky.py` (prints "all passed").
- No commits until the device test passes.

## Review Focus
1. RA wrap-around and the poles: a tap near Polaris (UMi encloses the pole) or across RA 0/360 (And, Psc, Peg, Oct) must find the right constellation.
2. A tap on or just outside the horizon rim: nothing happens, no error.
3. Pan to the disc's edge: the centre is clamped so part of the sky stays visible.
4. Southern sky (Sydney): a tap on Crux shows the Crux card.
5. Dense region (Sagittarius / Scorpius, zoomed): <= 1024 commands and nothing drawn outside the screen.

---

### Task 1: Data: abbreviations, boundaries, objects

**Files:**
- Modify: `apps/skytonight/make_data.py` (new arg BOUNDS.json; names.txt gets the abbreviation; writes bounds.txt)
- Create: `apps/skytonight/data/objects.txt` (hand-written: "id type ra dec mag abbr|name|note")
- Create: `apps/skytonight/test_data.py`
- Modify: `apps/skytonight/src/sky.lua` load_data (names.txt pattern now "ra dec rank ABBR en|tr|de")

**Interfaces:**
- Produces: `data/names.txt` rows `"ra dec rank ABBR en|tr|de"` (ABBR: IAU 3 letters as in d3-celestial ids, e.g. `UMi`); `data/bounds.txt` rows `"ABBR ra dec ra dec ..."` (one closed polygon a row, degrees J2000; a constellation may have several rows); `data/objects.txt` rows `"M31 gx 10.68 41.27 3.4 And|Andromeda Galaxy|<one sentence>"` with types `gx` (galaxy), `oc` (open cluster), `gc` (globular cluster), `nb` (nebula), `pn` (planetary nebula).
- Produces: in sky.lua `CNAMES[i] = { ra, dec, rank, names, abbr }`.

- [ ] **Step 1:** Fetch d3-celestial `data/constellations.bounds.json` (and, if not at hand, `constellations.lines.json`, `constellations.json`, BSC5) into a scratch folder, not the repo.
- [ ] **Step 2: Write the failing test** `test_data.py`: 88 rows in names.txt each with an ABBR; every ABBR has >= 1 polygon in bounds.txt; 30..40 objects; every object's `abbr` equals the constellation whose polygon contains its ra/dec (point-in-polygon in Python, RA unwrapped around the polygon's first vertex); objects include M31 (And), M42 (Ori), M45 (Tau), M13 (Her), M44 (Cnc), M8 (Sgr), Omega Centauri (Cen), 47 Tuc (Tuc), the Double Cluster (Per), LMC (Dor), SMC (Tuc).
- [ ] **Step 3:** Run `python -I apps/skytonight/test_data.py` — Expected: FAIL (no bounds.txt).
- [ ] **Step 4:** Extend make_data.py; write objects.txt (positions from public catalogues, notes written fresh, <= 90 characters); update load_data's names pattern.
- [ ] **Step 5:** Run test_data.py and test_sky.py — Expected: both pass (the full chart unchanged).

### Task 2: The 88 cards

**Files:**
- Create: `apps/skytonight/data/cards.txt` rows `"ABBR|story|star, star|M31 M32"` (story 1-2 sentences, <= 200 characters; up to 4 star names; up to 3 object ids from objects.txt, may be empty)
- Modify: `apps/skytonight/test_data.py`

- [ ] **Step 1: Failing test:** 88 cards, one per ABBR of names.txt; story 40..200 characters; every object id in a card exists in objects.txt and lies in that constellation; each object appears on at most one card.
- [ ] **Step 2:** Run — Expected: FAIL (no cards.txt).
- [ ] **Step 3:** Write the 88 cards (original English text: what the figure is, the story or origin in a phrase, the brightest stars' common names).
- [ ] **Step 4:** Run — Expected: PASS.

### Task 3: Geometry: chart point -> sky -> constellation

**Files:**
- Modify: `apps/skytonight/src/sky.lua`
- Modify: `apps/skytonight/test_sky.py`

**Interfaces:**
- Produces: `chart_to_radec(x, y, view) -> ra, dec | nil` (screen point, with view.zoom/view.zx/view.zy, back through the zoom and the stereographic projection; nil when outside the horizon); `constellation_at(ra, dec) -> abbr | nil` (loads bounds.txt once; bounding-box check then ray casting with RA unwrapped near the point; precession ignored, the boundaries are B1875 in d3 converted to J2000 by d3 already); exported in `__TEST.sky`.
- Consumes: Task 1 data.

- [ ] **Step 1: Failing tests** in test_sky.py: for Istanbul 2026-10-29 23:00, the chart point of Polaris's ra/dec (via the forward projection) maps back to within 0.5 degrees and `constellation_at` gives `UMi`; Betelgeuse -> `Ori`; M31 -> `And`; ra 359.9/dec 30 -> `And` and ra 0.1/dec 10 -> `Psc` (RA wrap); dec -89 -> `Oct`; a point at radius R + 3 from CX/CY -> nil; with view zoom 2.5 and a centre, a round trip of a star's point stays within 0.5 degrees; Sydney 2026-01-15 23:00, Acrux -> `Cru`.
- [ ] **Step 2:** Run — Expected: FAIL (functions missing).
- [ ] **Step 3:** Implement both functions.
- [ ] **Step 4:** Run — Expected: PASS.

### Task 4: Drawing the zoomed view and the card

**Files:**
- Modify: `apps/skytonight/src/sky.lua` (draw_sky)
- Modify: `apps/skytonight/test_sky.py`

**Interfaces:**
- Consumes: `view.zoom` (nil or 1: the full chart, unchanged), `view.zx, view.zy` (the chart point at the window's centre), `view.card` (ABBR or nil).
- Produces: draw_sky draws, when zoomed: the chart through `(p - (zx, zy)) * zoom + (CX, WIN_CY)` with WIN_CY = 316 (centre of y 92..540), items outside the window skipped, deep-sky objects with symbols and id labels, then paper rectangles over y < 92 and y > 540, the header, and the card in y 548..(y_end - 8): the constellation name (its language), the story (wrapped), "Brightest: ...", "Best in the evening: <month>" (the month its name point crosses the meridian at 21:00: then the Sun's RA is RA - 9 h; the Sun's RA is 0 h on 21 March and gains 2 h a month, so the month is March + round(((RA_h - 9) mod 24) / 2), wrapped to 1..12), and the objects "M31 Andromeda Galaxy: note"; text that does not fit is dropped from the end.

- [ ] **Step 1: Failing tests:** Istanbul 2026-10-29 23:00 zoomed on M31's chart point with card `And`: <= 1024 commands, `inside()` == 0, texts include `Andromeda`, a story line, `M31`; zoomed on Sagittarius at Sydney 2026-07-15 22:00: <= 1024, inside 0; the unzoomed frame's command count equals 1.0.1's (record it before the change); an unknown card ABBR still draws the name and season.
- [ ] **Step 2:** Run — Expected: FAIL.
- [ ] **Step 3:** Implement (render PNGs with `OUT` to look at it).
- [ ] **Step 4:** Run — Expected: PASS.

### Task 5: Interaction

**Files:**
- Modify: `apps/skytonight/src/app.lua`
- Modify: `apps/skytonight/test_sky.py` (helpers `press(L, x0, y0, x1, y1)` sending down then up, `key(L, name)`)

**Interfaces:**
- Consumes: Task 3 functions, Task 4 view fields.
- Produces: state `zoom` (nil or {zx, zy, card}); buttons while zoomed: `Zoom out`, `-1 h`, `+1 h`.

- [ ] **Step 1: Failing tests:** tap on Orion's chart point (full view) -> zoomed, card `Ori`, buttons `Zoom out` `-1 h` `+1 h`; drag of 100 px left -> zx grows by 40 (100 / 2.5), card unchanged; a tap in the zoomed window on another constellation -> card changes, zx/zy unchanged; Back key -> full chart and `on_input` returns true; Back on the full chart -> returns false; `+1 h` while zoomed re-centres on the card's name point when above the horizon; a tap outside the disc in the full view -> no zoom; pan far to the left -> centre clamped inside the disc; the page keys still step the hour while zoomed.
- [ ] **Step 2:** Run — Expected: FAIL.
- [ ] **Step 3:** Implement: remember the down position; on up, a move > 20 px pans (centre minus drag / ZOOM, clamped to radius R), else a tap; Back key handled in on_input.
- [ ] **Step 4:** Run test_sky.py and test_data.py; lint src/*.lua and the bundle — Expected: PASS, no lint problems.

### Task 6: Release

**Files:**
- Modify: `apps/skytonight/manifest.json` (1.1.0, description mentions tap to zoom), `apps/skytonight/README.md`, `apps/skytonight/data/NOTICE.txt` (boundaries from d3-celestial), `RELEASE_NOTES.md` + `release/v0.24.0/` (notes, package, SHA256SUMS), README.md app table if it lists versions.

- [ ] **Step 1:** Bundle, `python xtpack.py apps/skytonight -o release/v0.24.0/skytonight.xtapp`, refresh its SHA256 line, copy to the card root.
- [ ] **Step 2:** `python -I tools/store_export.py skytonight` — Expected: the zip carries cards.txt, objects.txt and bounds.txt the same way it carries stars.txt today.
- [ ] **Step 3:** Device test by the user (tap, drag, Zoom out, Back, time steps); no commit before it passes.
