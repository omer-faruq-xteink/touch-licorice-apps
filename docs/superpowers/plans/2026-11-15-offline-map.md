# Offline Map Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build two pieces. The first is a browser map maker on the Pages site's Tools page that turns any rectangle of the world into a pack of 1-bit tiles. The second is the Offline Map app, which shows those packs on the X4 Pro without a network.

**Architecture:**
- The tool renders OpenStreetMap vector tiles with MapLibre GL JS and our own e-ink style, offscreen. It thresholds the result to 1 bit, cuts it into 256 px tiles, and writes one `.map` pack file, format v1.
- **Two seams make the data provider replaceable:**
  - a *source* module: where vector tiles come from, under which limits;
  - a *schema* module: how that provider's layers map to our map's drawing roles and to name-index entries.
- VersaTiles (Shortbread) is the live pair. OpenFreeMap (OpenMapTiles) is built now as a dormant pair, so returning to OpenFreeMap, or adding it as a second source for peaks, is a config change plus a check.
- The app reads packs with offset reads, composes the view in an offscreen layer, and never holds pictures past a layer draw.

**Tech Stack:**
- Tool: vanilla ES modules in `site/tools/offlinemap/`, MapLibre GL JS 5 from jsDelivr, the Compression Streams API, the site's existing card-writing code (`site/assets/store.js`).
- Tool tests: Node 24, plain `.mjs` scripts like `site/test/test_translit.mjs`.
- App: Lua 5.5 (XTApp API 2.26), bundled with `tools/gamekit/bundle.py`, tested under lupa with a custom ctx stub.

**Spec:** `docs/superpowers/specs/2026-11-15-offline-map-design.md`

## Global Constraints

- **App identity:**
  - app_id `offlinemap`; display name `Offline Map`; manifest `"api": "2.26"`;
  - no `"net"` permission; `"requires": ["pointer"]`; portrait and landscape.
- **Zoom:** levels 8–19. Presets: **Overview** 8–13, **Streets** 10–17, **Close-up** 10–19.
- **Tiles:** 256×256 1-bit BMP, zlib-compressed (tile format 2). An empty-paper tile has index length 0.
- **Live data source:**
  - VersaTiles `https://tiles.versatiles.org/tiles/osm/{z}/{x}/{y}`, Shortbread 1.0, max zoom 14;
  - attribution `© OpenStreetMap contributors, VersaTiles`.
- **Tool limits:**
  - at most 4 parallel requests;
  - obey `Retry-After` on 429;
  - every fetched vector tile kept in Cache Storage (`offlinemap-tiles-v1`);
  - at most **10,000 vector tiles** per pack.
- **Dormant source:**
  - OpenFreeMap: TileJSON `https://tiles.openfreemap.org/planet`, OpenMapTiles;
  - limits 3000 tiles / 50 MB per pack;
  - attribution `© OpenStreetMap contributors, OpenMapTiles, OpenFreeMap`;
  - selectable only with `?source=openfreemap`, and never linked, until its maintainer answers the email of 2026-11-15.
- **Label language:** `local` (the default) or `en`. English falls back to the local name.
- **Device rules (anti-goals):**
  - every input or timer callback that decodes or draws calls `ctx.budget:extend()` first;
  - at most 6 decoded pictures per `layer:draw`, released only after that call returns;
  - at most 8 runtime images alive at once;
  - nothing is decoded in `on_draw`.
- **Numbers on the device:**
  - 32-bit integers and single-precision floats (API section 1);
  - global pixel coordinates and tile numbers are integers;
  - degrees are stored as integers in 1e-7 degrees;
  - float math only on small differences (see Task 7).
- **No commits until the device test passes** (the user's rule for new apps). Each task ends with its tests green, not with a commit.
- Never commit `docs/ideas/`, `tools/ao3probe/`, `tools/apiprobe/` or `.claude/`. `tools/mapprobe/` stays uncommitted (throwaway spike).

## Review Focus

1. **Float32 drift at zoom 17–19:**
   - a GPX line or marker must not jitter or drift from the streets, even though the harness runs 64-bit Lua and cannot show single-precision errors;
   - Task 7 pins the relative-projection rule and a test that every float input is a small difference.
2. **A pack edge and an overview pack together:**
   - the city pack's tiles win inside it, the overview's outside, and white with a dotted frame beyond both;
   - zoom stops exactly where no pack has a closer level at the screen centre (Task 7 and Task 9 tests).
3. **Large rows:**
   - a Streets row at zoom 17 can be wider than 64 KB of tile data;
   - the reader splits reads at 65,536 bytes and never asks for more (Task 7 test with a 70 KB row).
4. **A slow or rate-limited connection in the tool:**
   - 429 with `Retry-After`, a dropped request, a closed tab mid-run;
   - the run waits, retries, and on Make again resumes from Cache Storage without fetching a tile twice (Task 3 tests).
5. **Names in any script:**
   - Turkish dotted/dotless i, German ß, Vietnamese stacked accents, Cyrillic and Greek capitals fold the same in the tool and on the device;
   - CJK passes through unchanged (Task 1 shared word list, run by both sides).

---

## File structure

**Tool** (`site/tools/offlinemap/`):
- `index.html`: the page.
- `page.js`: UI wiring.
- `fold.js`: name folding (generated table).
- `bmpz.js`: 1-bit BMP plus zlib.
- `pack.js`: pack v1 writer and name index.
- `tiles.js`: tile math, presets, estimate, limits.
- `sources.js`: source definitions.
- `fetcher.js`: Cache Storage fetcher and the MapLibre protocol.
- `eink.js`: drawing roles and shared style values.
- `schema/shortbread.js` and `schema/openmaptiles.js`: per-provider style layers and name extraction.
- `render.js`: metatile rendering and thresholding.

**Tool tests** (`site/test/`):
- `test_offlinemap.mjs`;
- `mapread.mjs` (a JS port of the app's reader, used only by tests);
- `offlinemap_cli.mjs` (writes fixture packs for the Lua tests);
- `fixtures/fold_words.tsv`.

**Shared generator:** `tools/offlinemap_fold.py` writes the fold table into `site/tools/offlinemap/fold.js` and `apps/offlinemap/src/fold.lua`.

**App** (`apps/offlinemap/`):
- `bundle.py`, `manifest.json`, `icon.png`, `README.md`;
- `src/fold.lua` (generated);
- `src/geo.lua`: tile math, anchor projection, scale bar, coordinate parsing;
- `src/pack.lua`: the pack reader;
- `src/choose.lua`: tile-by-tile pack choice and zoom limits;
- `src/view.lua`: layer composition and pan;
- `src/names.lua`: search;
- `src/gpx.lua`: GPX parse, thinning, length;
- `src/main.lua`: screens;
- `test_offlinemap.py`: lupa tests.

**Site wiring:**
- `site/assets/site.js` TOOLS gets `{ id: 'offlinemap', title: 'Offline maps', app: 'Offline Map', blurb: 'Choose any area of the world and make a map pack for the reader: streets, paths and names, offline.' }`.

## Pack format v1 (pinned here: Tasks 1, 7 and 10 depend on it)

All values are little endian. Offsets are from the file start, and every file is smaller than 2^31 bytes.

**Header, 64 bytes:**

| at | type | value |
|---|---|---|
| 0 | 8 bytes | `XTMAP1\0\0` |
| 8 | u16 | version = 1 |
| 10 | u8 | number of levels |
| 11 | u8 | tile format = 2 |
| 12 | u16 | tile size = 256 |
| 14 | u16 | 0 |
| 16 | u32 | meta offset |
| 20 | u32 | meta length |
| 24 | u32 | zoom table offset |
| 28 | u32 | names offset |
| 32 | u32 | names length (0 = no names) |
| 36–63 | | zero |

**Meta:** UTF-8 JSON with these keys:
`{"name","bounds":[w,s,e,n],"levels":[..],"lang":"local"|"en","made":"YYYY-MM-DD","data_date":"YYYY-MM-DD","source":"versatiles","attribution":"...","tool":1}`

**Zoom table:** levels × 20 bytes, sorted by z.
`u8 z, u8 0, u16 0, u32 x0, u32 y0, u16 nx, u16 ny, u32 index offset`

**Index per level:** nx×ny entries, row-major, each `u32 offset, u32 length`.

**Tiles:** the zlib BMPs, row-major per level, in index order. A row's non-empty tiles are contiguous.

**BMP:** 62-byte header (BITMAPFILEHEADER plus a 40-byte BITMAPINFOHEADER), then pixel rows.
- 1 bpp, palette entry 0 black and entry 1 white (as Pillow writes mode "1", which the device decoded in the spike).
- Bottom-up, 32 bytes a row, 8254 bytes in all before zlib.

**Names section:**
- `u32 nblocks`, then a directory of nblocks × `u32 offset, u16 length, u16 count, u8 klen, first key bytes`.
- Then the blocks, each ≤ 4096 bytes.
- Each entry: `u8 klen, key, u8 nlen, name (UTF-8, ≤ 255 bytes, cut on a character boundary), u8 kind, i32 lon7, i32 lat7`.
- Entries are sorted by key (byte order), then by name.
- The directory is at most 65,536 bytes; the writer refuses more.

**Kinds** and the zoom a search jumps to:

| kind | name | zoom |
|---|---|---|
| 1 | city | 12 |
| 2 | town | 13 |
| 3 | village | 14 |
| 4 | suburb | 14 |
| 5 | other place | 15 |
| 6 | street | 17 |
| 7 | station | 16 |
| 8 | peak | 15 |
| 9 | park | 15 |
| 10 | water | 13 |
| 11 | POI | 17 |

---

### Task 1: Folding, BMP + zlib, pack writer, and a reader port

**Files:**
- Create:
  - `tools/offlinemap_fold.py`;
  - `site/tools/offlinemap/fold.js`, `bmpz.js`, `pack.js`;
  - `site/test/mapread.mjs`, `site/test/test_offlinemap.mjs`, `site/test/offlinemap_cli.mjs`;
  - `site/test/fixtures/fold_words.tsv`;
  - `apps/offlinemap/src/fold.lua`.

**Interfaces:**
- Produces:
  - `fold(s: string) -> string`;
  - `bmp1(bits: Uint8Array /*256*256, 1=black*/) -> Uint8Array`;
  - `zlib(bytes) -> Promise<Uint8Array>`;
  - `isBlank(bits) -> boolean`;
  - `writePack({meta, levels: [{z,x0,y0,nx,ny,tiles: (Uint8Array|null)[]}], names: [{name,kind,lon,lat}]}) -> Uint8Array`, where `tiles` holds compressed tiles row-major and null means empty;
  - `readPack(bytes) -> {header, meta, levels, tile(z,x,y)->Uint8Array|null, search(prefix, limit)->[{name,kind,lon7,lat7}]}` (test-only, in `mapread.mjs`);
  - the CLI: `node site/test/offlinemap_cli.mjs fixtures OUT_DIR` writes `city.map`, `overview.map`, `inner.map` (Task 7 uses them).

**The fold rule** (both sides):
- ASCII A–Z become lowercase.
- Every code point in U+00C0–U+024F, U+1E00–U+1EFF, U+0370–U+03FF and U+0400–U+04FF goes through the generated table:
  - Latin letters become their base ASCII letters, lowercase (`İ ı I` → `i`, `ß` → `ss`, `æ` → `ae`, `ø` → `o`, `đ` → `d`, `ł` → `l`);
  - Greek and Cyrillic capitals become lowercase.
- Whitespace and the characters `-_.,'’()/` become one space; the result is trimmed.
- Everything else passes unchanged.
- `offlinemap_fold.py` builds the table with `unicodedata` (NFD, drop combining marks, `.lower()`, plus the explicit specials above). It writes the same table into both files, each with a "GENERATED" header.

- [ ] **Step 1: Write the failing tests** in `site/test/test_offlinemap.mjs`:
  - `fold` against every row of `fixtures/fold_words.tsv`: at least 120 rows covering Turkish, German, French, Polish, Czech, Vietnamese, Icelandic, Russian, Greek, Chinese and Japanese. Each row is `input\tfolded`, with `Kadıköy\tkadikoy`, `İstanbul\tistanbul`, `Straße\tstrasse`, `Hà Nội\tha noi`, `Москва\tмосква`, `東京\t東京`, `Rue de l'Église\true de l eglise`;
  - `bmp1(allWhite)`: 8254 bytes, `BM` magic, width = height = 256, bpp 1, palette `00 00 00 00 ff ff ff 00`;
  - `isBlank(allWhite) === true`;
  - `writePack` round trip with `readPack`:
    - two levels, a null tile reads back null, a tile reads back byte-equal;
    - `meta` is equal;
    - `search('kad')` finds `Kadıköy` (kind 4) with lon7/lat7 equal to round(lon·1e7);
  - 3,000 names give several blocks, and `search` still finds the first and the last;
  - a name of 300 bytes is cut to ≤ 255 bytes without a broken UTF-8 sequence.
- [ ] **Step 2: Run** `node site/test/test_offlinemap.mjs`. Expected: fails on the missing imports.
- [ ] **Step 3: Implement.**
  - `fold.js`, `fold.lua`: generated, then a small `fold()` around the table.
  - `bmpz.js`: `zlib` uses `new CompressionStream('deflate')`, which is the zlib format.
  - `pack.js`: the writer, per the pinned format.
  - `mapread.mjs`: the reader, using `DecompressionStream`.
  - `offlinemap_cli.mjs`: fixtures from synthetic tiles. Each tile is a pattern encoding its z/x/y, e.g. the black pixel count = (x + y) % 200 + 1.
    - `city.map`: z15–16, a 4×3 range at z15 around Kadıköy (29.03, 40.99). Two empty tiles at z16, and one z16 row padded with incompressible noise to over 70 KB.
    - `inner.map`: z15–17, smaller, inside `city.map`.
    - `overview.map`: z8–13 over 28.0–30.0 E, 40.5–41.5 N.
    - Names: `Kadıköy` (4), `Moda Caddesi` (6), `Haydarpaşa` (7), `Fenerbahçe Parkı` (9).
- [ ] **Step 4: Run** `node site/test/test_offlinemap.mjs`. Expected: `all passed`.

### Task 2: Tile math, presets, estimate and limits

**Files:**
- Create: `site/tools/offlinemap/tiles.js`.
- Test: `site/test/test_offlinemap.mjs`.

**Interfaces:**
- Produces:
  - `lonLatToTile(lon, lat, z) -> {x, y}` (floats);
  - `tileRange(bbox:[w,s,e,n], z) -> {x0,y0,nx,ny}`;
  - `PRESETS = {overview:[8..13], streets:[10..17], closeup:[10..19]}`;
  - `vectorZoom(z) = min(z-1, 14)`. MapLibre vector sources use 512 px tiles, so output level z is map zoom z−1;
  - `vectorTiles(bbox, levels) -> number`: for each distinct vector zoom, `(nx+2)·(ny+2)` at that zoom, summed;
  - `estimate(bbox, levels, limits) -> {tiles, vectorTiles, bytesLow, bytesHigh, seconds, refused: null | 'vector-tiles' | 'bytes', advice}`.

- [ ] **Step 1: Write the failing tests.**
  - `tileRange([29.0,40.95,29.1,41.03], 16)` equals Python's `math.floor` reference values. Hard-code numbers computed once with the spike's `lonlat_to_tile`.
  - `estimate` for that bbox with `PRESETS.streets`:
    - `tiles` is the exact sum of nx·ny;
    - `bytesLow` uses 0.6 KB per tile;
    - `bytesHigh` uses 3.5 KB per tile at z ≤ 16, 2.3 KB at z17, 1.4 KB at z18, 1.0 KB at z19.
  - The whole of Turkey with `streets` against the 10,000 limit:
    - `refused === 'vector-tiles'`;
    - `advice` names the two ways out: a smaller area or Overview.
  - OpenFreeMap's limits `{maxVectorTiles: 3000, maxBytes: 50e6}` refuse a bbox that VersaTiles' 10,000 accepts.
- [ ] **Step 2: Run** `node site/test/test_offlinemap.mjs`. Expected: the new tests fail.
- [ ] **Step 3: Implement `tiles.js`.**
  - `seconds = tiles·0.03 + vectorTiles·0.03`, a first guess that the progress display replaces with the measured rate.
- [ ] **Step 4: Run.** Expected: `all passed`.

### Task 3: Sources and the polite fetcher

**Files:**
- Create: `site/tools/offlinemap/sources.js`, `fetcher.js`.
- Test: `site/test/test_offlinemap.mjs`.

**Interfaces:**
- Produces:
  - `SOURCES`: `{ versatiles: {id, title, schema:'shortbread', tiles:'https://tiles.versatiles.org/tiles/osm/{z}/{x}/{y}', maxzoom:14, attribution, limits:{maxVectorTiles:10000, parallel:4}, enabled:true}, openfreemap: {id, title, schema:'openmaptiles', tileJson:'https://tiles.openfreemap.org/planet', maxzoom:14, attribution, limits:{maxVectorTiles:3000, maxBytes:50e6, parallel:4}, enabled:false} }`;
  - `pickSource(search: string) -> source`: `?source=openfreemap` picks the dormant one, anything else gives versatiles;
  - `class TileFetcher(source, {fetch, caches, signal, onCount})` with:
    - `get(z,x,y) -> Promise<Uint8Array|null>`: 404 and an empty body give null;
    - `count`, `bytes`, `fromCache`;
    - `resolve() -> Promise<void>`: for a `tileJson` source, reads `tiles[0]`;
  - `registerProtocol(maplibregl, fetcher)`: registers `xtmap://{z}/{x}/{y}` with `maplibregl.addProtocol('xtmap', async (params, abort) => ({data}))`.

- [ ] **Step 1: Write the failing tests** with a fake `fetch` and an in-memory `caches`:
  - never more than `parallel` requests in flight, with 20 queued gets;
  - a 429 with `Retry-After: 2` waits ≥ 2 s on a fake clock, then retries and succeeds;
  - a network error retries 3 times with backoff, then rejects with a message naming the tile;
  - the second `get` of a tile comes from the cache (`fromCache` 1, fetch not called);
  - over `maxVectorTiles` the fetcher rejects with `'limit'`;
  - an aborted signal rejects pending gets, and no further fetch starts;
  - `pickSource('?source=openfreemap').id === 'openfreemap'` and `pickSource('').id === 'versatiles'`.
- [ ] **Step 2: Run.** Expected: the new tests fail.
- [ ] **Step 3: Implement.**
  - The cache key is the resolved tile URL.
  - Store with `cache.put(url, new Response(bytes))`.
- [ ] **Step 4: Run.** Expected: `all passed`.

### Task 4: E-ink roles and the two schemas

**Files:**
- Create: `site/tools/offlinemap/eink.js`, `schema/shortbread.js`, `schema/openmaptiles.js`.
- Test: `site/test/test_offlinemap.mjs`.

**Interfaces:**
- Produces:
  - `ROLES` in `eink.js`: `['water','water-edge','waterway','forest','park','building','road-major-casing','road-major','road-street','path','rail','place-label','street-label','water-label','poi-station','poi-health','poi-toilets','poi-museum','poi-viewpoint','poi-water','poi-shelter','poi-camp','poi-hut','peak']`, plus `PATTERNS` (water lines, park dots, forest dots, as 1-bit ImageData specs) and `GLYPHS = 'https://tiles.versatiles.org/assets/glyphs/{fontstack}/{range}.pbf'`;
  - each schema module exports `{ id, missing: string[], layers({lang}) -> MapLibre layer[], nameLayers: string[], nameEntry(sourceLayer, props, geometry, lang) -> {name, kind, lon, lat} | null }`;
  - each layer carries `metadata: {'xt:role': role}` and `source: 'xt'`;
  - `missing` is `['peak']` for shortbread and `[]` for openmaptiles.

- [ ] **Step 1: Write the failing tests.**
  - For each schema, every role in `ROLES` minus `missing` appears on at least one layer.
  - Every `source-layer` is one of the schema's known layers:
    - shortbread: `ocean, water_polygons, water_lines, land, sites, buildings, streets, street_labels, place_labels, pois, public_transport, water_polygons_labels, water_lines_labels, bridges, aerialways, addresses`;
    - openmaptiles: `water, waterway, landcover, landuse, park, building, transportation, transportation_name, place, poi, mountain_peak, water_name, housenumber, aeroway`.
  - `layers({lang:'en'})` text fields are `['coalesce', ['get','name_en'], ['get','name']]`; `lang:'local'` gives `['get','name']`.
  - No layer uses a grey or colour paint value: every colour is `#000` or `#fff`.
  - `nameEntry` fixtures:
    - a Shortbread `place_labels` point `{kind:'suburb', name:'Kadıköy'}` gives kind 4;
    - a `streets`/`street_labels` line `Moda Caddesi` gives kind 6 at the midpoint of its longest part;
    - an OpenMapTiles `mountain_peak` gives kind 8;
    - a feature without a name gives null.
- [ ] **Step 2: Run.** Expected: the new tests fail.
- [ ] **Step 3: Implement.**
  - Follow the spec's style table: cased major roads, dashed paths, ties on rail, patterns for water, park and forest, building outlines from z16, halo labels, symbols from simple shapes drawn with `map.addImage` at runtime (no sprite file).
  - Fonts: `noto_sans_regular` and `noto_sans_bold`.
  - The exact widths and sizes are the builder's choice, to be checked on the device in Task 12.
- [ ] **Step 4: Run.** Expected: `all passed`.

### Task 5: Rendering metatiles into pack tiles

**Files:**
- Create: `site/tools/offlinemap/render.js`.
- Test: `site/test/test_offlinemap.mjs` (pure parts only).

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces:
  - `metatiles(range:{x0,y0,nx,ny}, n=4) -> [{x, y, cols, rows}]`;
  - `toBits(rgba: Uint8ClampedArray, w, h, scale=2, threshold) -> Uint8Array`: a 2×2 box average, then luma < threshold is black;
  - `cut(bits, w, margin, col, row) -> Uint8Array` (one 256×256 tile);
  - `renderPack({bbox, levels, name, lang, source, schema, maplibregl, onProgress, signal}) -> Promise<{bytes: Uint8Array, stats}>`.
- **Render settings, pinned:**
  - a hidden container of (4·256 + 2·256) CSS px square, with `pixelRatio: 2`, `interactive: false`, `fadeDuration: 0`, `preserveDrawingBuffer: true`;
  - for each metatile, `map.jumpTo({center, zoom: z − 1})`, then wait for `idle`;
  - copy the canvas, `toBits` with threshold 150 (the spike's value; tune on the device), then cut 16 tiles;
  - blank tiles are stored as length 0;
  - at the deepest level with vector zoom ≥ 13, run `map.querySourceFeatures('xt', {sourceLayer})` for each name layer and pass the results to `schema.nameEntry`;
  - de-duplicate names: the same folded key and kind within 300 m keep one entry (streets: the first);
  - `onProgress({done, total, vectorTiles, fromCache, eta})` after each metatile, where `eta` comes from the measured rate.

- [ ] **Step 1: Write the failing tests.**
  - `metatiles({x0:10,y0:20,nx:9,ny:5}, 4)`: 3×2 metatiles; the last column has 1 tile and the last row 1.
  - `toBits` on a synthetic 2×2-upscaled image round-trips a known 8×8 pattern.
  - `cut` takes the right window with a margin of 256.
- [ ] **Step 2: Run.** Expected: the new tests fail.
- [ ] **Step 3: Implement `render.js`.**
- [ ] **Step 4: Run.** Expected: `all passed`.
- [ ] **Step 5: Browser check.**
  - Add a temporary page `site/tools/offlinemap/dev.html` that renders Kadıköy (29.02, 40.98, 29.04, 40.995) at Streets into a pack.
  - Read it back with `mapread.mjs` in the page and show z14 and z17 tiles at 1:1.
  - Look at them in the browser pane: roads cased, paths dashed, water lined, labels whole across tile edges, no grey.
  - Delete `dev.html` after Task 6 replaces it.

### Task 6: The map maker page

**Files:**
- Create: `site/tools/offlinemap/index.html`, `page.js`.
- Modify: `site/assets/site.js` (TOOLS entry above).

**Interfaces:**
- Consumes:
  - `renderPack`, `estimate`, `PRESETS`, `pickSource`, `TileFetcher`, `registerProtocol`;
  - `chrome`, `message`, `download`, `esc` from `site/assets/site.js`;
  - `canCopy`, `card` from `site/assets/store.js`, as `site/tools/piano/page.js` uses them.

The page, top to bottom:
1. **Choose the area.**
   - A MapLibre map with `https://tiles.versatiles.org/assets/styles/colorful/style.json`.
   - **Draw area** toggles rectangle drawing: drag on the map; the rectangle stays editable by its corners.
   - A place search box queries Nominatim (`https://nominatim.openstreetmap.org/search?format=json&limit=5&q=`) on Enter only, at most one request per second, and lists the results to jump to.
2. **Choose the detail.**
   - The three presets as radio buttons, with their level ranges;
   - Label language (Local / English);
   - Pack name (default: the first search result's name, else "My map").
3. **Estimate.**
   - Shown live: tiles, vector tiles, size range, time.
   - A refusal shows the advice and disables Make.
4. **Make.**
   - A progress bar, `1,240 of 15,800 tiles`, time left, `from cache: N`, and Cancel.
   - Cancel stops the run; Make again resumes from the cache.
5. **Get it onto the reader.**
   - **Copy to reader** writes `AppFiles/offlinemap/<name>.map` (Chrome/Edge). **Download** saves the file.
   - The hint names the folder and says to open Offline Map.
6. **Note:** the attribution, the data date (from the source's TileJSON), and that nothing is uploaded.

- [ ] **Step 1: Build the page** and add the TOOLS entry.
- [ ] **Step 2: Check it** with `python -I tools/build_site.py`, the `store` preview (port 8781) and the browser pane:
  - draw a 2×2 km area in Kadıköy with Close-up;
  - the estimate appears;
  - Make shows progress and finishes;
  - the console has no errors;
  - Download gives a `.map` file that `mapread.mjs` reads (run it with node on the downloaded file).
- [ ] **Step 3: Refusal check.** Draw Turkey with Streets: Make is disabled and the advice is shown.
- [ ] **Step 4: Cancel and resume check.**
  - Cancel a run halfway and Make again;
  - `from cache` equals the vector tiles fetched in the first run, and the fetch count does not repeat them.

### Task 7: App pack reader, pack choice and geography

**Files:**
- Create:
  - `apps/offlinemap/bundle.py` (calls `bundle.bundle(HERE)` like `apps/xkcd/bundle.py`);
  - `manifest.json`;
  - `src/geo.lua`, `src/pack.lua`, `src/choose.lua`;
  - `test_offlinemap.py`.

**Interfaces:**
- Consumes: the fixtures from `node site/test/offlinemap_cli.mjs fixtures DIR`, which the Python test runs into a temp dir and serves through the `ctx.files` stub.
- Produces:
  - `geo.tile_px(z) = 256 << z`;
  - `geo.anchor(z, cx, cy) -> A`: A holds `z, cx, cy, lon7, lat7, kx, ky`, where kx and ky are pixels per 1e-7 degree at the anchor;
  - `geo.to_px(A, lon7, lat7) -> x, y`: global pixels, integers, computed as `cx + (lon7 − A.lon7)·kx` and the same for y with the anchor's ky. **Only differences are multiplied by floats.**
  - `geo.from_px(A, x, y) -> lon7, lat7`: the inverse, the same way;
  - `geo.scale_bar(z, lat7) -> metres, px`: the nice value 1/2/5×10ⁿ whose bar is 60–120 px;
  - `geo.parse_coords(s) -> lat7, lon7 | nil, err`: accepts `41.0082, 28.9784`, `41.0082 28.9784`, `41°0'29.5"N 28°58'42.2"E` and negative values;
  - `pack.open(name) -> P | nil, err`, with fields `name, meta, levels[z] = {x0,y0,nx,ny,index}, file_size, area` (area = nx·ny at the deepest level, used to rank packs), and methods:
    - `P:has(z, x, y) -> boolean`;
    - `P:read_row(z, y, xa, xb) -> { [x] = blob | false }`: false means empty paper;
  - `choose.pick(packs, z, x, y) -> P | nil`: among packs that have z and contain (x, y), the smallest `area` wins, then the newest `meta.made`;
  - `choose.limits(packs, z, cx, cy) -> can_in, can_out`: is there any pack with level z+1 (or z−1) containing the centre.
- **Rules:**
  - every `ctx.files:read` asks for ≤ 65,536 bytes;
  - a row read covers only xa..xb: one index read, then the tile bytes from the first non-empty offset to the last end, split at 65,536.

- [ ] **Step 1: Write the failing tests** in `test_offlinemap.py`. Use a lupa runtime with `encoding='latin-1'` and `ctx.files` with `list`, `read(name, off, len)` (asserting len ≤ 65536) and `size`.
  - `pack.open('city.map')` reads meta `name` and the levels 15 and 16.
  - `read_row` gives blobs byte-equal to the fixture's tiles, and false for the two empty tiles.
  - The 70 KB row reads correctly with every read ≤ 65,536.
  - A file with a wrong magic or version gives `nil, 'not a map pack'`.
  - `choose.pick`:
    - inside the inner area at z16, `inner.map` wins over `city.map`;
    - at z13 only `overview.map` has the tile;
    - outside all packs, nil.
  - `choose.limits` at z16 in `inner.map` gives (true, true); at z17 (false, true); at z8 in overview (true, false).
  - `geo.scale_bar(14, 410000000)` = (500, 69); `(17, 410000000)` = (100, 111); `(19, 410000000)` = (20, 89); `(10, 600000000)` = (5000, 65), each px ±1.
  - `geo.to_px` at z19, for 20 points within 2 km of an anchor at (29.03, 40.99), is within 1 px of Python's double-precision Web Mercator.
  - A float-input guard: wrap `geo.to_px` in the test so it fails if `|lon7 − A.lon7|` or `|lat7 − A.lat7|` exceeds 2e7 (2°), pinning that callers re-anchor instead of projecting far points.
  - `parse_coords` on the three forms and on `abc` (nil, error).
- [ ] **Step 2: Run** `python -I apps/offlinemap/test_offlinemap.py`. Expected: the new tests fail.
- [ ] **Step 3: Implement** `geo.lua`, `pack.lua`, `choose.lua`, and a minimal `main.lua` (`on_load` / `on_draw` stubs) so the bundle loads.
  - For the anchor's own `lon7` and `lat7`, a single float computation is fine. Its error shifts everything equally and stays under 10 px at z19.
- [ ] **Step 4: Run.** Expected: `all passed`. Also run `python -I tools/lualint55.py apps/offlinemap/src/*.lua`: no findings.

### Task 8: The view (layers, batches, pan, zoom)

**Files:**
- Create: `apps/offlinemap/src/view.lua`.
- Test: `apps/offlinemap/test_offlinemap.py`.

**Interfaces:**
- Consumes: `pack`, `choose`, `geo`.
- Produces `view.new(ctx, w, h) -> V`, where V has:
  - `V:set(z, cx, cy)`: a full compose;
  - `V:pan(dx, dy)`: copy the old layer shifted into the spare layer and compose only the strips that came into view;
  - `V:zoom(dir, px, py)`: zoom by one level, keeping the screen point (px, py) fixed;
  - `V:draw(g, x, y)`: draws the current layer, nothing else;
  - `V.edge`: true when any visible tile had no pack;
  - `V.missing`: the count of tiles without a pack.
- **Rules:**
  - two layers of exactly the map area;
  - decode at most 6 tiles, draw them in one `layer:draw`, release them after it returns;
  - a tile without a pack: white with a dotted frame (1-px dashes every 8 px);
  - empty paper: white;
  - `ctx.budget:extend()` before composing.

- [ ] **Step 1: Write the failing tests.**
  - The fake layer records draws and errors if an image is released before its `layer:draw` returns (the spike's `test_probe.py` check).
  - A counter errors if more than 8 images are alive.
  - `V:set` on `city.map` at z16 decodes every visible tile once, in batches of ≤ 6.
  - `V:pan(128, 0)` decodes only the new column (count ≤ ny + 1).
  - `V:zoom(1, 240, 357)` keeps the geographic point under (240, 357) within 1 px.
  - Outside every pack, `V.edge` is true and nothing is decoded.
  - `on_draw` never calls `ctx.image:decode` (a stub that errors when called inside on_draw).
- [ ] **Step 2: Run.** Expected: the new tests fail.
- [ ] **Step 3: Implement `view.lua`.**
- [ ] **Step 4: Run.** Expected: `all passed`, lint clean.

### Task 9: The map screen

**Files:**
- Modify: `apps/offlinemap/src/main.lua`.
- Test: `apps/offlinemap/test_offlinemap.py`.

**Interfaces:**
- Consumes: `view`, `choose.limits`, `geo.scale_bar`, `geo.from_px`; kit buttons and messages from gamekit.
- Produces the screen layout:
  - a 34 px header: the pack name of the centre tile, `z16`, and the scale bar;
  - the map;
  - a 52 px bottom bar: `−`, `+`, `Search`, `Menu`.
- **Storage keys:** `view` (`z cx cy`), `bookmarks` (lines `name\tlat7\tlon7`), `settings`.

- [ ] **Step 1: Write the failing tests.**
  - A drag (pointer up with down_x/down_y 100 px apart) pans by that amount.
  - A double tap zooms in at the tap point. `+` and `−` zoom on the centre.
  - The keys `left`, `right`, `up` and `down` pan by half the map.
  - **Zoom stops where the pictures stop:**
    - at the deepest level `+` is drawn faded, and a tap or double tap does nothing except set the header to `No closer level here` for 3 s;
    - the same for `−` with `No wider level here`.
  - With `V.edge`, the header says `Edge of the map`.
  - A long press opens a box with the point's coordinates (`41.00820, 28.97840`) and `Add bookmark here`.
  - `back` closes the box; on the map itself, `on_input` returns false on the Back up event (the firmware's exit rule, as in the other apps).
  - The view is saved after each move and restored after `restart()`.
  - With no `.map` files: the first-start page names `AppFiles/offlinemap/` and shows a QR code (a `ctx.qr:encode` call with the Tools page address `https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/offlinemap/`).
  - A view outside all packs offers `Map packs`.
- [ ] **Step 2: Run.** Expected: the new tests fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: `all passed`, lint clean.

### Task 10: Search

**Files:**
- Create: `apps/offlinemap/src/names.lua`.
- Modify: `src/main.lua`.
- Test: `test_offlinemap.py`.

**Interfaces:**
- Consumes: `fold.lua`, `pack.open`'s directory (read at open, ≤ 64 KB).
- Produces:
  - `names.search(packs, query, limit) -> [{name, kind, lat7, lon7, pack}]`: fold the query, binary-search each pack's directory, read one or two blocks, prefix-match, and merge by key across packs;
  - `names.ZOOM[kind]`: the table in the pack format section.

- [ ] **Step 1: Write the failing tests.**
  - `search(packs, 'kad', 10)` finds `Kadıköy` from `city.map`; `'KADI'` and `'kadı'` find it too.
  - `'moda'` finds `Moda Caddesi` (kind 6).
  - No match gives an empty list.
  - At most 2 block reads per pack per query (count the `read` calls).
  - The search screen opens the keyboard (`ctx.input:text`) and lists results with name, kind word and pack name.
  - A tap jumps to the place at `ZOOM[kind]` (street 17, town 13, peak 15) and draws a marker. The marker is gone after the second pan.
- [ ] **Step 2: Run.** Expected: the new tests fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: `all passed`, lint clean.

### Task 11: Menu (bookmarks, routes, coordinates, packs, screen, about)

**Files:**
- Create: `apps/offlinemap/src/gpx.lua`.
- Modify: `src/main.lua`.
- Test: `test_offlinemap.py`.

**Interfaces:**
- Produces:
  - `gpx.parse(text) -> {name, points = {lat7, lon7, …}} | nil, err`: reads `<trkpt>` and `<rtept>` and attributes in either order; ignores `<wpt>`;
  - `gpx.thin(points, z) -> points`: drops points closer than 2 px at z to the last point kept;
  - `gpx.length_m(points) -> integer` (haversine, computed in steps with float differences);
  - the route is drawn into the map layer after the tiles, as three 1-px polylines offset by −1, 0 and +1 px across the line. Each polyline has ≤ 128 points, split as needed.

- [ ] **Step 1: Write the failing tests.**
  - A GPX with one track of 5 points parses.
  - A route file parses; `lat`/`lon` in either attribute order parse.
  - A broken file gives nil and an error.
  - `thin` at z10 shrinks a 2,000-point line to fewer than 200 points.
  - `length_m` of a 1° meridian segment is 111,195 ± 200 m.
  - **Bookmarks:** add, list sorted by name, jump, long-press rename and delete; kept in storage.
  - **Routes:** lists `*.gpx` from `ctx.files:list()`; opening one draws polylines and shows its length (`3.4 km`); `Fit` picks the deepest zoom where the whole route fits.
  - **Go to coordinates:** `41.0082, 28.9784` jumps and draws a marker; bad input shows the error.
  - **Map packs:** each pack's name, levels (`z10–17`), size (`12.3 MB`) and date.
  - **Screen:** portrait / landscape.
  - **About:** the attribution of every pack, the version, and the QR code.
- [ ] **Step 2: Run.** Expected: the new tests fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: `all passed`, lint clean.

### Task 12: Device test, release files, then the one commit

**Files:**
- Create:
  - `apps/offlinemap/icon.png` (via `tools/make_icons.py`);
  - `apps/offlinemap/README.md`.
- Modify:
  - root `README.md` (intro, table, section, tests), `NOTICE.md` (MapLibre BSD-3, VersaTiles, OSM ODbL, Nominatim);
  - `RELEASE_NOTES.md` (v0.26.0, a **New: Offline Map** bullet and a Files row);
  - `release/v0.26.0/` (package, notes, `RELEASE_v0.26.0.md` "All apps" row, SHA256SUMS);
  - `store/apps.json` after submitting.

- [ ] **Step 1: Make two packs with the live tool:** a Kadıköy Close-up and a hiking Streets pack (Belgrad Forest, 28.95–29.02 E, 41.15–41.20 N).
  - Copy them and `dist/offlinemap.xtapp` to the card when the user says USB is on.
- [ ] **Step 2: On the device,** measure and look:
  - full view ≤ 1 s, pan, and every zoom level 10–19;
  - zoom stops with the message at both ends;
  - the pack edge looks right;
  - search, a GPX route, coordinates;
  - portrait and landscape;
  - photos of the style;
  - the route stays on its streets at z19 (Review Focus 1).
  - Tune `eink.js` and the threshold from the photos, re-make, re-check.
- [ ] **Step 3: Run every test:**
  - `node site/test/test_offlinemap.mjs`;
  - `python -I apps/offlinemap/test_offlinemap.py`;
  - `python -I site/test/test_whatsnew.py`;
  - lint.
  - Expected: all pass.
- [ ] **Step 4: Release files** as in the release staging routine (build with `build_all.py`, copy the package, notes and checksums). Site screenshots come from `python -I tools/site_shots.py offlinemap`.
- [ ] **Step 5: Commit** after the user confirms the device test:
  ```bash
  git add apps/offlinemap site/tools/offlinemap site/test/test_offlinemap.mjs site/test/mapread.mjs site/test/offlinemap_cli.mjs site/test/fixtures/fold_words.tsv tools/offlinemap_fold.py site/assets/site.js README.md NOTICE.md RELEASE_NOTES.md docs/superpowers/specs/2026-11-15-offline-map-design.md docs/superpowers/plans/2026-11-15-offline-map.md site/shots
  git commit -m "Offline Map 1.0.0: offline 1-bit map packs and the map maker tool"
  ```
- [ ] **Step 6: Store** (`tools/store_export.py offlinemap`, then the Studio and Developer Center flow).

### Later, when OpenFreeMap answers (not part of this plan's run)

- **Yes:**
  - set `SOURCES.openfreemap.enabled = true`;
  - add a source picker to the page (or render peaks from it as a second MapLibre source: a `peak` role layer from the openmaptiles schema on top of the shortbread style);
  - make one pack from it and compare on the device;
  - nothing in the app changes.
- **No answer or no:** nothing to do; the dormant entry stays hidden.

---

## Addendum (2026-11-15): Tasks 13 and 14 (spec, "Addendum: route labels and drawing routes")

### Task 13: Street names along a route (app)

**Files:** `apps/offlinemap/src/gpx.lua`, `src/labels.lua` (new), `src/main.lua`, `test_offlinemap.py`.

**Interfaces:**
- `gpx.parse` also returns `labels = { {name, lat7, lon7}, ... }` from `<wpt>` with `<type>street</type>`.
- `labels.from_index(packs, points, max_m) -> { {name, lat7, lon7} }`: street entries (kind 6) of the packs
  whose bounds meet the route's, within `max_m` (12) metres of a route segment; each name once per 300 m.
- `labels.place(route_px, labels, z, left, top, w, h) -> { {row, x, y, deg} }`: each label's point on the
  route at zoom z, the route's direction there turned to -90..90, moved 18 px to the left of the
  direction; dropped within 150 px of a placed one; only from zoom 15.
- Drawing: one label layer, made when the route opens (rows of 30 px, bold `medium`, white box);
  `g:image(layer, x, y, { src = {0, row*30, w, 30}, rotate = deg })`; on `nil, "not_supported"` (or no
  `ctx.capabilities.image_transform`), `g:text` level with a white box.

- [ ] Tests: street waypoints parse; `from_index` finds `Moda Caddesi` near a route along it and not a far
  one; `place` turns a south-going route's label to read left to right and drops a second label within
  150 px; opening a route with street waypoints draws label images with `rotate` (stub), and level text when
  the stub says `not_supported`; the label layer counts towards the 4 layers.

### Task 14: Drawing a route (tool)

**Files:** `site/tools/offlinemap/route.js` (new), `render.js`, `page.js`, `index.html`, `site/test/test_offlinemap.mjs`.

**Interfaces:**
- `route.js`: `lengthM(points) -> number`; `bboxWithMargin(points, m) -> [w,s,e,n]`;
  `toGpx({name, points: [[lon,lat]], labels: [{name, lon, lat}]}) -> string`; `parseGpx(text) -> {name, points}`;
  `streetLabels(routePoints, features, maxM = 12, maxDeg = 25) -> [{name, lon, lat}]` (features: GeoJSON
  street label lines with `properties.name`).
- `renderPack({..., route})`: at the name level, `querySourceFeatures('xt', {sourceLayer: schema.streetLabelLayer})`
  goes to `streetLabels`; returns `{ bytes, stats, routeGpx }` (null without a route).
- Page: Draw route, Undo point, Clear route, Load GPX, Use route area, the length; Copy to reader writes
  `<pack>.gpx` too; Download route.

- [ ] Tests: `lengthM` of 1° of meridian is 111,195 ± 200 m; `bboxWithMargin` adds 500 m; `toGpx`
  round-trips through `parseGpx` with names escaped (`&`, `<`); `streetLabels` names a route along a label
  line and not a crossing one; the app's `gpx.parse` reads the tool's GPX labels (the Lua test parses a
  `toGpx` output written by the CLI).
