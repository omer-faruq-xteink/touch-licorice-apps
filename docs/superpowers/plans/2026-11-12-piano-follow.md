# Piano Follow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An XTApp that shows pre-engraved sheet music on the Xteink X4 Pro, follows a BLE MIDI keyboard, turns pages and runs a practice mode, plus a converter (web page + Node catalog tool) and a PC BLE MIDI simulator for testing.

**Architecture:** A shared JavaScript converter (Verovio → 1-bit pages + note map → one `.xtscore` file) runs in the browser (converter page) and in Node (catalog tool). The Lua app reads `.xtscore` files from `AppFiles/pianofollow/`, writes pages into a layer with `set_bits`, parses BLE MIDI notifications, and runs a follower or a practice tracker. A Python `bless` GATT server on the PC pretends to be a BLE MIDI keyboard.

**Tech Stack:** Lua (XTApp API 2.21, gamekit bundle + harness under lupa), Node 24 (`verovio`, `@resvg/resvg-js`, `yaml`, `node:test`), browser ES modules (Verovio from jsDelivr, `CompressionStream`), Python 3.12 (`bless`, `mido`, `python-rtmidi`, `lupa`).

**Spec:** `docs/superpowers/specs/2026-11-12-piano-follow-design.md`

## Global Constraints

- **No git commits** until Task 12 (device test) passes and the user says so (user's rule). Each task ends with a checkpoint run instead of a commit.
- Manifest: `app_id` `pianofollow`, display name "Piano Follow", `api` `"2.21"`, `permissions` `["net", "ble"]`, no `requires`.
- BLE MIDI service `03b80e5a-ede8-4b33-a751-6ce34ec4c700`, characteristic `7772e5db-3868-4112-a1a9-f2669d106bf3` (notify). Note-on with velocity 0 = note-off.
- Page bitmap: 480 x 760 px, rows of 60 bytes, high bit first, 1 = black; status bar 40 px above it (screen 480 x 800, portrait only).
- Every compressed page < 65536 bytes (one `ctx.files:read`).
- Callback limits: 1000 ms input/net/timer/BLE callbacks, 1500 ms `on_draw`; call `ctx.budget:extend()` before heavy work (page decode, note-map decode).
- Lua runs with 32-bit integers on the reader; keep under 200 locals per chunk (use do-blocks with export tables).
- Back on the app's main (Home) screen returns false (host asks to exit).
- Nothing filled black in UI chrome (ghosting); the page bitmaps are the exception.
- Verovio (LGPL-3.0) is never copied into the repo: npm dependency in `tools/piano/`, CDN in the browser. Pin the same version in both (`verovio@4.3.1` unless the npm registry's latest stable at install time differs; use that exact version in both places).
- Catalog raw base URL: `https://raw.githubusercontent.com/omer-faruq-xteink/touch-licorice-apps/main/catalog/piano/`.
- Licenses accepted: public domain, CC0, CC-BY, CC-BY-SA (credits shown). Composers: traditional or died before 1955.
- Follower anti-goal: **never turn a page early**; when unsure, do not turn.

## Review Focus

1. A packet holding several MIDI messages with running status and per-message timestamp bytes (as real keyboards send) → every note is seen. Test in Task 5.
2. The player repeats a bar or restarts a passage → the follower relocates within a few notes and does not turn the page. Test in Task 6.
3. A piece where one hand rests for a long stretch, in Practice with that hand chosen → onsets without notes for the chosen hand are skipped, not waited on forever. Test in Task 7.
4. A `.xtscore` file the user copied that is truncated or not ours → "Can't open this file" message, no crash. Test in Task 4.
5. The keyboard switches off mid-piece → status shows "Keyboard lost", reconnection is retried, the page stays where it is. Test in Task 9.

---

## File Structure

```
site/tools/piano/convert.mjs      shared converter: Verovio options, raster → 1-bit, note map, pack/unpack
site/tools/piano/index.html       converter page (pick file, preview, write to card / download)
site/tools/piano/page.js          page logic (browser raster via canvas, card writing)
tools/piano/package.json          Node deps: verovio, @resvg/resvg-js, yaml
tools/piano/node_raster.mjs       Node rasterizer (resvg) for convert.mjs
tools/piano/level.mjs             difficulty estimate from a note map
tools/piano/build_catalog.mjs     catalog.yaml → catalog/piano/{catalog.json, pieces/*.xtscore} + review sheets
tools/piano/pdmx_select.py        PDMX metadata → candidates.csv (license/composer/title filters, ranking)
tools/piano/composers.json        allowed composers with death years
tools/piano/title_block.txt       titles/composers to drop (modern songs, film/game themes)
tools/piano/catalog.yaml          hand-kept selection: id, source path, level override, review status
tools/piano/test/*.test.mjs       node:test tests + fixtures (fixtures/*.musicxml, *.abc)
tools/piano/blemidi_sim.py        PC BLE MIDI keyboard simulator
tools/piano/test_sim.py           encoder/event tests, cross-checked with the Lua parser
apps/pianofollow/manifest.json, bundle.py, icon.png, README.md
apps/pianofollow/src/main.lua     screens, input, drawing, wiring
apps/pianofollow/src/score.lua    .xtscore reading (header, pages, note map)
apps/pianofollow/src/midi.lua     BLE MIDI packet parser
apps/pianofollow/src/follow.lua   follower (Page turn / Follow)
apps/pianofollow/src/practice.lua practice tracker
apps/pianofollow/src/kbd.lua      BLE scan/connect/subscribe/reconnect
apps/pianofollow/src/catalog.lua  catalog download, lists, piece download
apps/pianofollow/test_pianofollow.py  harness tests
tools/gamekit/harness.py          (modify) optional extra stubs argument
catalog/piano/                    generated catalog (built in Task 11)
```

## `.xtscore` format (fixed here; README documents it)

- Bytes 0-7: ASCII `XTSCORE1`. Bytes 8-11: header length N, uint32 little-endian. Then N bytes of UTF-8 JSON header.
- Header: `{"v":1,"title":s,"composer":s,"arranger":s,"license":s,"source":s,"url":s,"level":"beginner|easy|intermediate|advanced","w":480,"h":760,"pages":[[off,len],...],"map":[off,len]}`; offsets absolute from file start.
- Each page: zlib stream (RFC 1950) of 760 rows x 60 bytes.
- Note map: zlib stream of JSON `{"bars":[[page,x,y,w],...],"onsets":[[t,bar,page,x,y,[rh pitches],[lh pitches]],...],"turn":[[sys_onset,bar_onset],...]}`.
  - `t`: onset time in quarter notes from the start (performance order, repeats unfolded when Verovio expands them). `bar`: 1-based index into `bars`. `x,y`: notehead position on the page (first note of the onset). Pitches: MIDI numbers.
  - `turn[i]` for page i: index (1-based) of the first onset of that page's last system, and of its last bar.

---

### Task 1: Converter core (shared module + Node raster)

**Files:**
- Create: `site/tools/piano/convert.mjs`, `tools/piano/package.json`, `tools/piano/node_raster.mjs`, `tools/piano/test/make_fixture.mjs` (CLI: `node make_fixture.mjs IN OUT.xtscore`, used by the Lua tests)
- Test: `tools/piano/test/convert.test.mjs`, fixtures `tools/piano/test/fixtures/scale.musicxml` (C major scale RH quarter notes + LH whole-note C3/G3, 4 bars), `fixtures/long.musicxml` (64 bars, enough for ≥ 3 pages), `fixtures/repeat.musicxml` (2 bars inside repeat signs), `fixtures/tune.abc`

**Interfaces:**
- Produces (`convert.mjs`):
  - `async convert(toolkit, raster, input, meta) -> {header, pages: Uint8Array[] /* raw 45600 B each */, map}` where `toolkit` is a Verovio toolkit instance, `raster(svg: string, w: number, h: number) -> Promise<Uint8Array /* RGBA */>`, `input: {name: string, data: string|Uint8Array}` (`.musicxml`, `.xml`, `.mxl`, `.abc`), `meta: {title?, composer?, arranger?, license?, source?, url?, level?}`.
  - `to1bit(rgba: Uint8Array, w, h) -> Uint8Array` (luminance < 128 → black).
  - `async pack(result, deflate) -> Uint8Array` where `deflate(bytes) -> Promise<Uint8Array>` (zlib format).
  - `async unpack(bytes, inflate) -> {header, pages, map}` (for tests and preview).
  - `VEROVIO_OPTIONS` constant (pageWidth/pageHeight for 480x760 at the chosen scale, `breaks:'auto'`, `header:'none'` except title on page 1, `footer:'none'`, `svgViewBox:false`, `adjustPageHeight:false`).
- Produces (`node_raster.mjs`): `nodeRaster(svg, w, h) -> Promise<Uint8Array>` (resvg, white background), `nodeToolkit() -> Promise<toolkit>`, `nodeDeflate`, `nodeInflate` (node:zlib).

- [ ] **Step 1: Install deps** — `cd tools/piano && npm init -y && npm install verovio @resvg/resvg-js yaml`; record the exact verovio version in package.json (no `^`).
- [ ] **Step 2: Write failing tests** in `convert.test.mjs`:

```js
test('scale: one page, right sizes, all onsets', async () => {
  const r = await convertFixture('scale.musicxml');
  assert.equal(r.pages.length, 1);
  assert.equal(r.pages[0].length, 760 * 60);
  const on = r.map.onsets;
  assert.deepEqual(on.slice(0, 8).map(o => o[5]), [[60],[62],[64],[65],[67],[69],[71],[72]]);
  assert.deepEqual(on[0][6], [48, 55]);                       // LH chord C3+G3 at t=0
  assert.ok(on.every(o => o[3] >= 0 && o[3] < 480 && o[4] >= 0 && o[4] < 760));
  assert.ok(on.every((o, i) => i === 0 || o[0] >= on[i - 1][0]));
});
test('long: ≥3 pages, turn points inside each page', async () => {
  const r = await convertFixture('long.musicxml');
  assert.ok(r.pages.length >= 3);
  r.map.turn.forEach(([s, b], i) => { assert.equal(r.map.onsets[s - 1][2], i + 1); assert.ok(b >= s); });
});
test('repeat: unfolded', async () => {               // 2 bars of 4 quarters inside repeat signs
  const on = (await convertFixture('repeat.musicxml')).map.onsets;
  assert.equal(on.length, 16);
  assert.deepEqual(on[8][5], on[0][5]); assert.equal(on[8][1], on[0][1]);   // same pitches, same bar
  assert.ok(on.every((o, i) => i === 0 || o[0] > on[i - 1][0]));
});
test('abc input converts', async () => { assert.ok((await convertFixture('tune.abc')).map.onsets.length > 0); });
test('pack/unpack round trip, every compressed page < 65536', async () => {
  const r = await convertFixture('long.musicxml'); const bytes = await pack(r, nodeDeflate);
  assert.equal(new TextDecoder().decode(bytes.slice(0, 8)), 'XTSCORE1');
  const u = await unpack(bytes, nodeInflate);
  assert.deepEqual(u.pages[2], r.pages[2]); assert.deepEqual(u.map, r.map);
  u.header.pages.forEach(([o, l]) => assert.ok(l < 65536));
});
```

- [ ] **Step 3: Run** `cd tools/piano && node --test` → FAIL (module missing).
- [ ] **Step 4: Implement** `convert.mjs` and `node_raster.mjs`. Note map: `toolkit.renderToTimemap({includeMeasures:true})` for onset order/times and note ids; `toolkit.getMIDIValuesForElement(id)` for pitch; staff from the element's ancestor `staff` (`n` attribute in MEI via `getElementAttr`/`getMEI` lookup) — staff 1 → RH, 2 → LH, other staves → RH; notehead x/y from the page SVG (`<g id=note>` → `use` x/y, scaled by the SVG's viewBox to pixels); bars from `measure` groups' bounding boxes; systems from `g.system`. Repeats: use Verovio's expansion when the MEI has one; otherwise unfold in `convert.mjs` by duplicating the onsets of the repeated bars (same bar/page/x/y, `t` shifted).
- [ ] **Step 5: Run** `node --test` → PASS. Write the four page images of `long.musicxml` to `dist/piano/check/*.png` and look at them (readable on a stand, no clipping at the edges); tune the scale in `VEROVIO_OPTIONS` until 3-4 systems fit a page.
- [ ] **Step 6: Checkpoint** (no commit).

### Task 2: Difficulty estimate

**Files:** Create `tools/piano/level.mjs`; Test `tools/piano/test/level.test.mjs`

**Interfaces:**
- Consumes: the `map` from Task 1.
- Produces: `level(map, bpm = 90) -> 'beginner'|'easy'|'intermediate'|'advanced'` and `features(map, bpm) -> {notesPerSec, span, chordMean, lhActive, onsets}`; CLI `tools/piano/level_cli.mjs FILE.musicxml` prints the level (used by `pdmx_select.py`).

- [ ] **Step 1: Failing tests** — scale fixture → `'beginner'`; a fixture of dense 16ths with 3-4 note LH chords over 3 octaves (`fixtures/dense.musicxml`) → `'advanced'`; `features(scale).span === 24` (C3..C5).
- [ ] **Step 2: Run** `node --test test/level.test.mjs` → FAIL.
- [ ] **Step 3: Implement** score = notesPerSec·1.0 + span/12·0.5 + (chordMean−1)·1.5 + lhActive·1.0; thresholds < 1.5 beginner, < 3 easy, < 5 intermediate, else advanced (tune thresholds on fixtures; `catalog.yaml` overrides win).
- [ ] **Step 4: Run** → PASS. **Checkpoint.**

### Task 3: Converter page

**Files:** Create `site/tools/piano/index.html`, `site/tools/piano/page.js`; Modify `site/tools/index.html` (add a "Piano Follow converter" entry like the other tools).

**Interfaces:**
- Consumes: `convert`, `pack`, `unpack` (Task 1); `card` and `canCopy` from `site/assets/store.js` (`card.connect()`, `card.restore()`, `card.handle` = the card's root `FileSystemDirectoryHandle`).
- Produces: browser `raster(svg,w,h)` via `Image` + `OffscreenCanvas`; `deflate` via `new CompressionStream('deflate')`; writing to `AppFiles/pianofollow/<name>.xtscore` (`getDirectoryHandle('AppFiles',{create:true})` → `'pianofollow'`).

- [ ] **Step 1:** Page: file input (`.musicxml,.xml,.mxl,.abc`), title/composer fields prefilled from the file, Convert button, preview of every page as a 480x760 canvas (1-bit), size readout, "Write to reader" (Connect the reader flow when not connected) and "Download .xtscore". Text: files stay on your computer; copyright is the user's responsibility; formats not accepted (MIDI, PDF, photos) and why.
- [ ] **Step 2: Verify in the browser pane** (preview_start on `site/` static server from `.claude/launch.json`; add a config if missing): convert `fixtures/long.musicxml` → preview shows ≥3 pages; Download → the file's first 8 bytes are `XTSCORE1` and `unpack` in the console gives the same page count. Writing to a card is checked by the user in Chrome/Edge (the built-in pane has no folder picker).
- [ ] **Step 3: Checkpoint.**

### Task 4: App skeleton and `.xtscore` reading

**Files:**
- Create: `apps/pianofollow/{manifest.json,bundle.py,src/main.lua,src/score.lua,test_pianofollow.py}`; icon via `tools/make_icons.py` (piano keys motif).
- Modify: `tools/gamekit/harness.py` — `Game(app_dir, stubs='')`: extra Lua executed after `STUBS`, before loading.

**Interfaces:**
- Produces (`score.lua`, module `require('score')`):
  - `S.open(name) -> piece | nil, err` (`piece = {name, header, map=nil}`; reads magic + header only; err ∈ `'bad_file'`, `'not_found'`).
  - `S.page_bits(piece, i) -> string | nil, err` (read `[off,len]`, `ctx.zlib:decompress(data, {format='zlib'})`, length must be 45600).
  - `S.load_map(piece) -> map | nil, err` (decompress + `ctx.json:decode`; caches in `piece.map`; calls `ctx.budget:extend()` first).
  - `S.list() -> {{name, title, composer, level, size}}` from `ctx.files:list()` filtered by `%.xtscore$`, headers read, sorted by title; bad files listed with title = file name and `bad=true`.
- Test stubs (in `test_pianofollow.py`): `ctx.files` over a Python dict, `ctx.zlib:decompress` via Python `zlib`, `ctx.json` via Python `json`, `ctx.layers:create` returning a layer whose `set_bits(bytes, y)` records calls, `ctx.budget:extend`, `ctx:after` queue, `ctx.api = {major=2, minor=21}`. Test pieces are made by running `node tools/piano/test/make_fixture.mjs <in> <out>` (small CLI over Task 1) once per test run.

- [ ] **Step 1: Failing tests**: `S.open` on `long.xtscore` → title matches, `#header.pages >= 3`; `S.page_bits(p, 2)` length 45600 and equals the Node raw page (compare SHA-1 via Python); `S.load_map(p).onsets[1][6]` equals the Node map; truncated file (first 100 bytes) → `nil, 'bad_file'`; a `.xtscore` of random bytes → listed with `bad=true`, opening it shows "Can't open this file" on the Home screen.
- [ ] **Step 2: Run** `python -I apps/pianofollow/test_pianofollow.py` → FAIL.
- [ ] **Step 3: Implement** `score.lua` (`string.unpack('<I4', s, 9)` for N) and a minimal `main.lua`: Home (My pieces list, Catalog, Keyboard, Help buttons), Score screen with the page layer (`set_bits` row block per call, 760 rows), status bar (title, `n/m`), tap left third / right third and keys `left`/`right` turn pages, Back → Home; Back on Home returns false.
- [ ] **Step 4: Run** → PASS; `python -I tools/lualint55.py apps/pianofollow/index.lua` clean. **Checkpoint.**

### Task 5: BLE MIDI parser

**Files:** Create `apps/pianofollow/src/midi.lua`; Test: add to `test_pianofollow.py`.

**Interfaces:**
- Produces: `M.new() -> parser`; `M.feed(parser, packet: string) -> {{on=bool, note=int, vel=int, ts=int}, ...}` (ts = 13-bit BLE timestamp in ms). Running status kept in `parser` across packets; SysEx (F0..F7, possibly across packets) and system/realtime bytes skipped; channels ignored (any channel).

- [ ] **Step 1: Failing tests** (packets built in Python):
  - `80 80 90 3C 64` → one note-on 60 vel 100;
  - `80 80 90 3C 64 81 40 64` (running status with timestamp byte) → notes 60, 64;
  - `80 80 90 3C 64 40 64` (running status without timestamp byte) → notes 60, 64;
  - `80 80 90 3C 00` → note-off 60; `80 80 80 3C 40` → note-off 60;
  - `80 80 F0 01 02` then `80 03 F7 80 90 3C 64` → SysEx skipped, one note 60;
  - `80 80 B0 40 7F 90 3E 50` → CC skipped, note 62.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS. **Checkpoint.**

### Task 6: Follower (Page turn / Follow)

**Files:** Create `apps/pianofollow/src/follow.lua`; Test: add to `test_pianofollow.py` (maps generated in Python as plain tables).

**Interfaces:**
- Consumes: `map` (format above).
- Produces: `F.new(map, page, turn_at /* 'system'|'bar' */) -> st` with `st.pos` (index of the next expected onset), `st.bar`, `st.page`; `F.note(st, pitch, now_ms) -> ev | nil`, `ev ∈ {'bar', 'turn'}` (a `'turn'` sets `st.page` to the next page); `F.goto_page(st, page)` (manual turn: pos = first onset of that page).

Algorithm (fixed here):
- Window match: candidates are onsets `j` in `[pos−2, pos+6]` whose RH∪LH pitches contain `pitch`; take the one with the smallest `j ≥ pos`, else the largest `j < pos`. Mark the pitch as hit for `j`; onset `j` is complete when ≥ half (rounded up) of its pitches are hit. When complete and `j ≥ pos`: `pos = j+1`, `matched_run += 1`; a match with `j > pos+2` needs a second consecutive match before `pos` moves.
- Lost: 4 consecutive unmatched note-ons → relocate: among all `j` where the last 3 played pitches occur in onsets `j−2, j−1, j` in order, take the nearest to `pos` (ties → earlier); if none, stay.
- Turn: when `turn_at == 'system'` and `pos−1 ≥ turn[page][1]` and `matched_run ≥ 2` → `'turn'`; same with `turn[page][2]` for `'bar'`. A relocation resets `matched_run` to 0, and never turns by itself; a relocation to an earlier page sets `st.page` (event `'turn'`).

- [ ] **Step 1: Failing tests** over a 3-page synthetic map (12 bars, 4 onsets per bar, 4 bars per page, last system = last 2 bars):
  - clean play of all onsets → exactly 2 `'turn'` events, each emitted at an onset index ≥ the page's `turn[1]` and before the first onset of the next page's 3rd bar;
  - 5% wrong pitches + 5% skipped onsets (seeded 1..20 runs) → every run turns both pages, **no run turns before `turn[1]`**;
  - player repeats bar 3 (on page 1) twice → no turn until bar 4's last system is played again; relocation lands in bar 3;
  - a single matching note near the turn point after silence → no `'turn'`;
  - chord onsets: playing 2 of 3 chord notes completes the onset;
  - `F.goto_page(st, 2)` → `st.pos` = first onset of page 2.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS. **Checkpoint.**

### Task 7: Practice tracker

**Files:** Create `apps/pianofollow/src/practice.lua`; Test: add to `test_pianofollow.py`.

**Interfaces:**
- Produces: `P.new(map, hands /* 'r'|'l'|'b' */, from_onset) -> st`; `P.note_on(st, pitch, now_ms) -> 'advance' | 'wrong' | nil`; `P.note_off(st, pitch)`; `st.pos`, `st.wrong` (total), `st.done`; `P.summary(st) -> {wrong=n, bars={{bar=b, wrong=k}, ...}}` (bars sorted by bar number).
- Rules: required pitches of onset = RH, LH or both by `hands`; onsets with no required pitch are skipped automatically (also at `new`). The onset completes when every required pitch is held or was pressed within the last 1000 ms. A pressed pitch not in the required set → `'wrong'` (counted for the current onset's bar). Extra repeated presses of a required pitch are not wrong.

- [ ] **Step 1: Failing tests:** single notes advance; C-E-G chord pressed G,C,E within 1 s → one `'advance'`; chord with 1.2 s between first and last press and the first released → no advance until it is pressed again; wrong pitch → `'wrong'`, pos unchanged, summary lists that bar; `hands='l'` on a map where LH rests for bars 2-3 → those onsets skipped, pos jumps to bar 4's first LH onset; `from_onset` = first onset of bar 5 starts there.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS. **Checkpoint.**

### Task 8: Score screen modes and markers

**Files:** Modify `apps/pianofollow/src/main.lua`; Test: add to `test_pianofollow.py`.

**Interfaces:**
- Consumes: `S.*` (Task 4), `F.*` (Task 6), `P.*` (Task 7), `M.*` (Task 5).
- Produces: `on_midi(ev)` in main.lua (one parsed note event; Task 9 calls it); per-piece settings in storage `p_<file name>.txt`: `mode=turn|follow|practice`, `hands=r|l|b`, `page=n`; global `settings.txt`: `turn_at=system|bar`.
- Behaviour: mode chooser in the status bar (Page turn / Follow / Practice + hands); Follow marker = 3 px line under the current bar (`bars[bar]`), redraw coalesced to ≤ 1 per 1000 ms with `ctx:after`; Practice marker = small triangle under the next notehead, redraw after each `'advance'` (coalesced at 300 ms), wrong count in the status bar; end of piece in Practice → summary screen (bars with mistakes, "Practice from bar n" buttons).

- [ ] **Step 1: Failing tests** (harness; feed `on_midi` directly):
  - Follow: playing a page's onsets with 100 ms steps → at most one redraw per 1000 ms of fake time, the page layer is rewritten only on `'turn'` (count `set_bits` calls);
  - Page turn mode draws no marker;
  - Practice with a wrong note → status shows `Wrong 1`; end → summary lists that bar; "Practice from bar 3" starts at bar 3;
  - the mode and page are restored after `g.restart()`;
  - `g.commands()` on the Score screen < 200.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS. **Checkpoint.**

### Task 9: Keyboard connection

**Files:** Create `apps/pianofollow/src/kbd.lua`; Modify `main.lua` (Keyboard screen, status bar state); Test: fake `ctx.ble` in `test_pianofollow.py`.

**Interfaces:**
- Consumes: `M.new/M.feed`, `on_midi`.
- Produces: `K.start(on_note, on_state)` (called from `on_load` when `ctx.ble`), `K.scan()`, `K.forget()`, `K.state() -> 'off'|'scanning'|'connecting'|'connected'|'lost'|'none'`, `K.name()`. Remembers `kbd.txt` = `address\naddress_type\nname\nsecure(0|1)`.
- Flow: on start with a remembered device → `connect` directly; else `scan({services={BLE_MIDI_SVC}, duration_ms=8000})` → list of found devices on the Keyboard screen → user picks → `connect` → `on_connect` → `subscribe(BLE_MIDI_CHR, true)`; if subscribe fails with `io_error`/`timeout` → `close`, wait 300 ms (`ctx:after`), reconnect with `secure=true` and remember `secure=1`. `on_disconnect` with `io_error` → state `'lost'`, retry `connect` every 5 s (max 12 tries), then `'none'`. `busy` from connect → retry after 200 ms. No `ctx.ble` → Keyboard screen says "This reader has no Bluetooth"; page turning by hand only.

- [ ] **Step 1: Failing tests:** remembered device connects without scanning and notes reach `on_midi`; scan → pick → connect → subscribe; subscribe failure → second connect has `secure=true` and `kbd.txt` ends with `1`; disconnect mid-piece → status `Keyboard lost`, page unchanged, reconnect after fake 5 s; `ctx.ble = nil` → message shown, no error.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS. **Checkpoint.**

### Task 10: PC BLE MIDI simulator (+ first device check)

**Files:** Create `tools/piano/blemidi_sim.py`, `tools/piano/test_sim.py`, `tools/piano/requirements.txt` (`bless`, `mido`, `python-rtmidi`).

**Interfaces:**
- Produces: `encode(events, ts_ms, packing) -> list[bytes]` (`events = [(on, note, vel)]`, `packing='multi'` puts up to MTU−3 bytes per packet with running status, `'single'` one message per packet); `piece_events(path, bpm, wrong, skip, repeat_bar, seed) -> list[(t_ms, on, note, vel)]` from an `.xtscore` note map; CLI: `--probe`, `--keyboard [PORT]`, `--piece FILE --bpm 80 --wrong 0.05 --skip 0.05 --repeat-bar 3 --seed 1 --packing multi|single`, advertised name `PF-Sim`.

- [ ] **Step 1: Failing tests** (`python -I tools/piano/test_sim.py`): encoded packets fed to the Lua `midi.lua` (via lupa) give back the same notes for both packings; `piece_events` with `wrong=0, skip=0` yields every map pitch in order; with `seed=1` the same sequence twice.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** (`bless` `BlessServer`, service + characteristic with `notify|read|write_without_response`, `update_value` per packet).
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Device check 1 (with the user):** `pip install -r tools/piano/requirements.txt`; `python tools/piano/blemidi_sim.py --probe` prints "advertising"; build and copy the app to the card (`python build_all.py`, card in USB mode); on the reader: Keyboard → scan finds `PF-Sim` → connected; `--piece` on `long.xtscore` → notes arrive (status bar note readout). If Windows refuses the peripheral role: stop and switch to the fallback in the spec (Android BLE MIDI peripheral app, then ESP32) — ask the user before buying anything.
- [ ] **Step 6: Checkpoint.**

### Task 11: Catalog: selection, build, app screens

**Files:**
- Create: `tools/piano/pdmx_select.py`, `tools/piano/composers.json`, `tools/piano/title_block.txt`, `tools/piano/catalog.yaml`, `tools/piano/build_catalog.mjs`, `apps/pianofollow/src/catalog.lua`; output `catalog/piano/`.
- Modify: `main.lua` (Catalog screens), `test_pianofollow.py`.

**Interfaces:**
- `pdmx_select.py --pdmx DIR --out dist/piano/candidates.csv`: reads PDMX's metadata CSV (inspect its column names first and map: license, license-conflict flag, instrument/track info, composer, title, rating, views); keeps piano-only, license ∈ accepted, no conflict, composer in `composers.json` with death year < 1955 or composer/genre traditional/folk, title/composer not in `title_block.txt`; ranks by rating then views; writes id, title, composer, license, rating, path, estimated level (calls `node tools/piano/level_cli.mjs`).
- `catalog.yaml` entries: `{id, src (path under PDMX DIR), title, composer, arranger, license, url, level?, review: todo|ok|rejected}`.
- `node tools/piano/build_catalog.mjs --pdmx DIR`: builds only `review: ok` entries → `catalog/piano/pieces/<id>.xtscore`, `catalog/piano/catalog.json` = `{"v":1,"pieces":[{id,title,composer,level,pages,size,license}]}`; for `review: todo` writes contact sheets `dist/piano/review/<id>.png` (all pages side by side).
- `catalog.lua`: `C.refresh(done)` (`ctx.net:request{url=BASE..'catalog.json', save={to='files', name='catalog.json'}}`), `C.levels()`, `C.composers(level)`, `C.pieces(level, composer)`, `C.search(text)`, `C.download(id, done)` (`save` to `<id>.xtscore`, then `S.open` check), `C.installed(id) -> bool`.

- [ ] **Step 1: Failing tests** (harness, fake net serving a 3-piece catalog + pieces): Catalog → Beginner → composer → piece → Download → appears in My pieces and opens; search "minuet" finds the piece by title; offline (`no_network`) → message "No connection", cached catalog still listed; delete from My pieces removes the file.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** `catalog.lua` + screens; **Step 4: Run** → PASS.
- [ ] **Step 5: Build the starter set:** download PDMX (Zenodo) to a local folder outside the repo; run `pdmx_select.py`; pick about 60 candidates (≈70% beginner/easy; the classical names from the spec); fill `catalog.yaml`; build contact sheets; review every page (wrong notes, collisions, unreadable layouts), set `review: ok/rejected`; build until 30-50 `ok` pieces; show the user a sample of 5 contact sheets for their spot check.
- [ ] **Step 6: Checkpoint.**

### Task 12: Docs, packaging, device test (the gate)

**Files:**
- Create: `apps/pianofollow/README.md` (what it does, modes, keyboard pairing, converter, `.xtscore` format, credits/licensing note).
- Modify: `tools/store_export.py` (api map: `'pianofollow': '2.21'`), `tools/site_catalog.py` (app entry, category, text), `site/tools/index.html` (converter link, if not done in Task 3), `RELEASE_NOTES.md` and `release/v0.23.0/` (per the release staging routine), Help screen text in `main.lua`.

- [ ] **Step 1:** Run every test: `python -I apps/pianofollow/test_pianofollow.py`, `cd tools/piano && node --test`, `python -I tools/piano/test_sim.py`, `python -I tools/lualint55.py apps/pianofollow/index.lua` → all pass.
- [ ] **Step 2:** Studio preview check (Home, Catalog, Score with a piece, Practice summary) in the browser pane; fix layout issues.
- [ ] **Step 3: Device test with the user** (pass criteria from the spec):
  - three catalog pieces (beginner, easy, intermediate), Follow mode, simulator with `--wrong 0.05 --skip 0.05 --repeat-bar N`: every page turned, **zero early turns**, no turn later than the first two bars of the next page;
  - the same three played by the user on the USB keyboard through `--keyboard`;
  - Practice on one piece with r, l and b: advances only on right notes, chords in any order, summary lists the bars with injected errors;
  - no callback over its limit in a full run (no "callback killed" in the reader log); keyboard off and on → reconnects.
- [ ] **Step 4:** Report results to the user; on pass and their go-ahead: commit (app, tools, site page, catalog, docs/spec/plan), then store export and submission, release notes. On fail: fix, re-run Step 1-3.
