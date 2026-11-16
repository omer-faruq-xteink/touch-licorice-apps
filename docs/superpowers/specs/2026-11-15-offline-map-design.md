# Offline Map: a pocket paper map for the Xteink X4 Pro (design)

Status: draft, 2026-11-15. To be shared on GitHub by the user.

## Intent

An offline map on the reader, for anyone, anywhere in the world. It should work like a folding paper
map in your pocket: you prepare the area you need on a computer, copy it to the reader, and look at it
without a connection, for days, on almost no battery, readable in sunlight.

Two uses matter equally (the user's words: city walks and nature hikes, for general use, not just
for the author):

- **In a city:** streets with their names, squares, stations, parks; find a place by name.
- **On a hike:** paths and tracks, water, peaks, shelters; a route prepared beforehand, drawn on the
  map.

The idea comes from ExplorInk (github.com/rfordinal/explorink, a CrossPoint firmware fork in C that
draws OpenStreetMap vector tiles on similar e-ink devices). This app is our own: an XTApp on the stock
firmware, with its own data format and its own site tool.

**Distribution** (the user's choice): both channels, as with the other apps. The app goes to the
Xteink store and into the GitHub releases. The map maker is a page of the GitHub Pages site's
**Tools**.

## Goals

- **The whole world.** Any area a user can draw on a map can become a map pack. Nothing is tied to
  one country.
- **Fast enough to feel like a map** (measured, see Constraints): a full screen in about 0.7 s,
  panning faster, zooming one step in about 0.7 s.
- **Twelve zoom levels, from a region to a building's door:** zoom 8 (about 480 m per pixel at
  Istanbul's latitude) to zoom 19 (about 0.25 m per pixel). Zoom 8–9 come only from Overview packs;
  the other presets start at zoom 10.
  - The user found zoom 12–16 too few on the device and asked for one more level after zoom 18.
  - The deepest levels hold the most data, so the tool limits them to small areas (see Map maker).
- **Readable on 1-bit e-ink:**
  - black and white only;
  - thick roads, large labels with a white halo;
  - patterns instead of grey: water, parks, forest.
- **Search by name:** towns, districts, streets, stations, peaks, parks. Results are listed, and
  tapping one jumps there.
- **Bookmarks:** mark a place with a name; list, jump, delete.
- **A prepared route:** GPX files (from a phone app, Komoot, Strava, a hiking site) copied next to
  the maps and drawn on the map as a bold line, with its length.
- **"Where am I" without GPS:** a **Go to coordinates** box. Read the position off a phone, type it
  in, and a marker shows the place. Long press on the map shows that point's coordinates.
- **Several packs side by side**, e.g. an overview of a country and detailed packs of two cities. The
  app picks the most detailed pack that covers what is on screen.
- **A map maker that never seems frozen** (the user's request):
  - a progress bar, tiles done of total, time left;
  - Cancel;
  - a size and time estimate before it starts.

## Non-goals (version 1)

- **Live position.** XTApp Bluetooth is central-only, so a phone app cannot connect to the reader as
  ExplorInk's does. A Bluetooth GPS receiver with the standard Location and Navigation service could
  work later; it is not in this version.
- **Turn-by-turn navigation and routing.**
- **Online maps.** The app never uses the network, so it needs no "net" permission.
- **Contour lines and hill shading.** OpenStreetMap vector tiles carry none; they could come later
  from free elevation data.
- **Editing OpenStreetMap.**

## Anti-goals (a failure even if it technically works)

- **A map maker that looks frozen** for minutes, or loses the work on a slow connection.
- **The app ending itself.** It must never run past the device's time budget (11 s per callback with
  `ctx.budget:extend()`), hold more than 8 runtime images, or free an image before its draw has
  finished. All three were seen in the spike.
- **An unreadable map:** grey anti-aliased lines that vanish in 1-bit, labels cut at tile edges,
  labels on top of each other.
- **Breaking a data provider's rules**, e.g. bulk-downloading OpenStreetMap's own raster tiles,
  which their policy forbids.
- **Needing an account or an API key** to make a map.

## Constraints (measured on the X4 Pro, firmware 26111201, with a spike app)

A throwaway probe (`tools/mapprobe`) and a test pack of Istanbul (Kadıköy and Beyoğlu, zoom 10–18)
measured:

| operation | time |
|---|---|
| read 64 B / 4 KB / 64 KB from AppFiles (`ctx.files:read` with offset) | 17 / 18 / 40 ms |
| decode a 256 px tile: PNG 1-bit / PNG grey / JPEG | 199 / 262 / 72 ms |
| decode a 256 px tile: **BMP 1-bit** | **31 ms** |
| unzip a 4 KB zlib-compressed BMP (`ctx.zlib:decompress`) | 3 ms |
| a full view, 480 x 714, 12 tiles (reads 145, unzip 43, decode 421, draw 86) | **712 ms** |
| copy a layer into another layer | 17 ms |
| draw a layer scaled 2x (nearest) | 1.2 s, too slow for a digital zoom |
| polyline, 1 px wide, 10 x 32 points | 72 ms |
| polyline, 2 px wide, 3 x 32 points | 704 ms; 100 of them ended the session |

Consequences, all decided:

- **Tiles are pre-rendered pictures, not vectors drawn on the reader.** Wide lines are far too slow,
  and Lua could not lay out labels in time.
- **Tiles are 256 x 256 1-bit BMP, zlib-compressed.** This is the fastest to decode, and smaller
  than PNG: 1.65 MB against 1.79 MB for the same tiles.
- **The view is put together in an offscreen layer** (`ctx.layers`, at most 4, each up to 800 px a
  side).
  - Tiles are decoded up to 6 at a time and drawn into the layer in one `layer:draw`. They are freed
    only after that call returns: a picture freed inside the draw call is not drawn (the probe's
    blank map).
  - Panning copies the old layer shifted and decodes only the strips that came into view.
- **One pack file per area**, with each row of tiles stored together, so a row costs one read of its
  index and one read of its pictures.
- **No pinch zoom:** the reader reports a single pointer. Zoom is by double tap and +/- buttons, as
  in the reader apps' picture zoom.
- **A route line is drawn as several 1-px polylines side by side**, not as one wide line.
- Typical sizes:
  - a dense city: 3–4 KB per tile at zoom 14–16, 2.3 KB at 17, 1.4 KB at 18;
  - countryside is much smaller.
  - An average Turkish province (about 10,000 km²) is about 18 MB to zoom 15 and about 55 MB to
    zoom 16. A city centre of 3 x 3 km to zoom 19 is a few MB.

## Approaches

- **A. Pre-rendered 1-bit tile packs, made in the browser (chosen).**
  - The site tool draws OpenStreetMap vector data with an e-ink map style, cuts it into tiles and
    writes one pack file.
  - The reader only decodes and places pictures. The measurements say this is fast enough.
  - Cartography is done once, on a computer with a real map renderer.
- **B. Vector tiles drawn on the reader (rejected).** Smaller files and any zoom, but wide lines and
  label placement are far too slow on the device. ExplorInk does it in C and still takes 1–2.5 s per
  view.
- **C. Online tiles (rejected).**
  - No offline use, which is the point.
  - OpenStreetMap's tile servers forbid prefetching.
  - Wi-Fi drains the battery.
- **D. Ready-made packs hosted by us (rejected for version 1).** The whole world cannot be hosted or
  kept fresh. A few sample packs on the Tools page may come later.

## The map maker (GitHub Pages Tools page)

A page like the other tools (`site/tools/<id>/`, listed in `site/assets/site.js` TOOLS). Everything
runs in the browser, and no account is needed.

**1. Choose the area.**
- A normal web map (MapLibre GL JS with a VersaTiles style) to pan and zoom. Drag a rectangle; a
  search box can jump to a place first.
- One rectangle per pack (my call for version 1). Several packs cover irregular areas.

**2. Choose the detail.** Three presets, each the levels it holds:
- **Overview** (zoom 8–13): a region or a small country; roads, towns, water, forests.
- **Streets** (zoom 10–17): a city or a hiking area; every street and path, with names.
- **Close-up** (zoom 10–19): a city centre or a village; buildings, house numbers, every footpath.
  Allowed only for small areas.

**3. Estimate, then make.**
- Before starting, the tool shows the number of tiles, an estimated size (a range: town or
  countryside), and an estimated time.
- It refuses areas over the data source's per-download limit (below) with a plain explanation and a
  suggestion: a smaller area, or less detail.
- While making: a progress bar, "1,240 of 15,800 tiles", time left, and Cancel.
- Vector tiles already downloaded are kept in the browser (Cache Storage), so a cancelled or failed
  run continues where it stopped.

**4. Get it onto the reader.**
- **Copy to reader** writes the pack into `AppFiles/offlinemap/` on the card (Chrome or Edge on a
  computer, the site's existing File System Access code, as the Piano tool does).
- **Download** gives the file to copy by hand.
- The file name is the pack's name, e.g. `Istanbul centre.map`.

**Data source.**
- VersaTiles vector tiles (`tiles.versatiles.org`, tileset `osm`): OpenStreetMap data in the
  Shortbread 1.0 schema, zoom 0–14; zoom 15–19 are drawn from the zoom 14 data (overzoom). No API key
  or account; the server sends `Access-Control-Allow-Origin: *`. Checked 2026-11-15.
- The server is free and open to everyone, with per-IP rate limits (429 with `Retry-After`) and no
  rule against fetching ahead. The tool is polite anyway: at most 4 parallel requests, it obeys
  `Retry-After`, keeps every fetched tile in Cache Storage (never fetched twice), and holds a pack to
  **10,000 vector tiles** (my call; about 60,000 km² × cos²(latitude) of Streets). Bigger areas are
  cut into several packs. Fonts and sprites come from our site.
- **Fallback, same module:** VersaTiles also publishes the whole planet as one file on
  `download.versatiles.org`, readable by HTTP range requests (206, CORS open) with their
  `@versatiles/container` library (Unlicense); their docs show cutting a region out of it this way.
  The builder switches to it if the tile server's rate limit makes packs too slow.
- **Known gap:** Shortbread 1.0 has no peaks or springs (it has drinking water, shelters, campsites
  and alpine huts). Hiking packs show no peak names until a source with peaks is added; OpenFreeMap
  (OpenMapTiles, which has `mountain_peak` with heights) is that source if its maintainer agrees
  (asked 2026-11-15).

**Rendering.**
- MapLibre GL JS with our own e-ink style, drawn offscreen into large canvases (several tiles a
  side), turned into 1-bit with a threshold, and cut into 256 px tiles.
- Large canvases with a margin, plus MapLibre's own label collision, keep labels whole and apart.
  Labels run along roads.
- Each tile becomes a 1-bit BMP, zlib-compressed in the browser (CompressionStream "deflate", which
  is the zlib format).
- **Label language:** an option with two choices: local (the default) or English. Shortbread carries
  `name`, `name_en` and `name_de`; English falls back to the local name.
- **Attribution** is written into the pack and shown in the app's About: "© OpenStreetMap
  contributors, VersaTiles".

**The e-ink style** (black on white, no grey):

| element | how it is drawn |
|---|---|
| motorways and main roads | thick cased lines |
| streets | solid lines |
| paths and tracks | dashed |
| railways | thin line with ties |
| water | horizontal line pattern, with an edge line |
| parks | sparse dots |
| forest | a different sparse pattern |
| buildings (zoom 16+) | outlines |

- **Labels:** large type with a white halo. Place names grow with the place's rank, and street names
  run along their roads.
- **Symbols, chosen for both uses:**
  - city: station, bus stop (zoom 17+), hospital, pharmacy, toilets, museum, viewpoint;
  - nature: drinking water, shelter, campsite, alpine hut; peaks with their height and springs once a source has them (see Data source).
- **Builder's freedom:** the exact sizes and patterns are left to the builder, but they must be
  checked on the device, in photos, before release.

**Search data.** The tool also writes a name index into the pack:
- places, streets, stations, peaks, parks, notable POIs;
- each with its name in the chosen label language, a kind and a position.

## The pack format (version 1)

One file, little endian.

1. **Header.**
   - `"XTMAP1\0\0"`, a format version, the number of zoom levels, the tile size, the tile format
     (2 = zlib-compressed 1-bit BMP);
   - offsets of the metadata, the zoom table and the name index.
2. **Metadata** (JSON, small):
   - the pack's name, its bounds (west, south, east, north), the levels;
   - the label language, the date made, the data date, the attribution, the tool version.
3. **Zoom table:** per level, z, the tile range (x0, y0, columns, rows) and the index offset.
4. **Index per level:**
   - columns x rows entries, row-major, each u32 offset and u32 length;
   - length 0 means empty paper, drawn as white without reading.
5. **Tiles:** row-major per level, so each row's tiles lie together. Web Mercator, standard XYZ
   numbering.
6. **Name index:**
   - entries sorted by a folded key (lowercase, accents removed, so "Kadıköy" matches "kadikoy");
   - each entry: the key, the display name, a kind, and the position (as 32-bit integers in 1e-7
     degrees: Lua numbers on the reader are 32-bit);
   - stored in blocks, with a small block directory, so a prefix search costs a binary search over
     the directory and one or two reads.

The spike's packs (`tools/mapprobe`) used a shorter header. Version 1 adds the metadata, the format
version and the name index.

## The app

Name **Offline Map**, app_id `offlinemap` (my call, a plain name that is easy to find in the store).
Portrait and landscape. No network permission. Data:
- `AppFiles/offlinemap/*.map` for packs;
- `AppFiles/offlinemap/*.gpx` for routes;
- private storage for bookmarks, the last view and settings.

**The map screen.**
- **Header line:** the pack's name, the zoom level and a scale bar (e.g. "200 m"), from the latitude
  and zoom.
- **Bottom bar:** − / + / Search / Menu.
- **Drag** to pan; the picture follows on release, as in the reader apps' picture zoom.
- **Double tap** to zoom in at that point; − and + zoom on the middle.
- **The page keys** pan by half a screen.
- **Long press:** a box with the point's coordinates, and Add bookmark here.
- **Back:** closes a box, or leaves search and menus; on the map itself it exits, as the firmware
  intends.
- **Pack switching:**
  - **tile by tile** (my call, after the builder check): each tile on screen comes from a pack that
    has that zoom level at that place. When several do, the smallest pack wins (it is the most
    detailed area), then the newest. So a city pack sits seamlessly inside an overview pack at the
    zooms both have.
  - Where no pack has the tile, it stays white with a faint dotted frame, and the header says "Edge
    of the map".
  - Choosing a pack per tile is cheap: a handful of rectangles, checked when the visible tile range
    changes.
  - **zoom stops where the pictures stop** (the user's request):
    - when no pack has a closer level at that point, + and double tap do nothing, and the header
      says so for a few seconds ("No closer level here");
    - zooming out past the most distant level works the same way ("No wider level here").
    - The + or − button is drawn faded while it cannot be used, so the user sees it before tapping.
  - outside every pack, the screen says so and offers the list of packs.
- The last view is kept and restored at start.

**Search.**
- The firmware keyboard; results appear as you type (prefix match on the folded key) from every pack.
- Each result shows its name, kind and pack.
- A tap jumps to the place at a sensible zoom: street 17, town 13, peak 15. A marker stays there
  until the map is moved twice.

**Menu.**
- **Bookmarks:** the list, sorted by name; tap to jump, long press to rename or delete.
- **Routes:** the GPX files in the folder. Opening one draws it and shows its length; there is a
  button to fit the whole route on screen.
  - Tracks and routes are read. Points are thinned for each zoom so a long track still draws fast.
  - The route is drawn into the map layer after the tiles, as two or three 1-px polylines.
- **Go to coordinates:**
  - typed as decimal degrees ("41.0082, 28.9784") or degrees, minutes and seconds;
  - draws a marker; Add bookmark from there.
- **Map packs:** the list with each pack's area, levels, size and date.
- **Screen:** portrait / landscape.
- **About:** how to make a pack (the Tools page address as a QR code), the attribution, the version.

**First start with no packs.** A plain page:
- what the app is, and that it has no live position;
- the Tools page address as a QR code;
- where to put the files.

**Performance rules.**
- Every redraw calls `ctx.budget:extend()`.
- Decoding happens in input or timer callbacks, never in `on_draw`, which only shows the layer.
- At most 6 pictures are held at once, freed after each layer draw.
- The name index is read in blocks, never whole.

## Tests

- **App (lupa harness, like the other apps):**
  - the pack reader (header, zoom table, index, row reads, empty tiles);
  - pack choice by zoom and position;
  - the name search (folding, prefix, several packs);
  - the GPX parser (tracks, routes, broken files) and point thinning;
  - the scale bar;
  - coordinate parsing;
  - the time-budget and freeing rules (a fake layer that fails when a picture is freed before its
    draw ends, as in the probe's test);
  - lint (`lualint55.py`).
- **Tool (node tests in `site/test/`):**
  - the BMP and zlib writer, read back;
  - the pack writer, read back by a port of the app's reader;
  - the size and limit estimate;
  - the name-key folding: the same rules as the app, checked on a shared word list.
- **On the device, before release:**
  - a city pack and a hiking pack;
  - full view and pan times;
  - every zoom level;
  - search, a GPX route, coordinates;
  - portrait and landscape;
  - photos of the style.

## Data source: decided

OpenFreeMap's terms ask each offline download to send "a unique User-Agent identifying your app",
which a web page cannot set. Protomaps' API needs a key, which would be public in a static page.
OSM's own vector tiles forbid offline use, and the public Overpass API asks apps for a wide audience
not to use it as their backend.

**Decision (user, 2026-11-15): VersaTiles**, as above: no key, CORS open, documented regional
downloads. Compared on three z14 tiles (Kadıköy, Uludağ, Chamonix) with OpenFreeMap: the same OSM
data, buildings kept one by one, fewer POIs and no peaks; data of 2026-10-19 against OpenFreeMap's
build of 2026-11-01 (VersaTiles builds come every few weeks to months). The user emailed OpenFreeMap
on 2026-11-15; a yes adds it as a second source for peaks, behind the same data-source module.

**Addendum (2026-11-16): OpenFreeMap agreed.** Its founder replied that a browser tool is identified
well enough by Origin and Referer (no User-Agent needed) and that our limits and caching are right:
at most 3000 tiles and 50 MB downloaded per pack, every tile cached. **Decision (user): automatic by
size.**
- A pack that fits the 3000 tiles (with the estimate's quarter for MapLibre's margins) is checked when
  Make is pressed: up to 9 tiles at its deepest vector zoom and 4 two zooms up are sampled, and the
  download is estimated from them. Under 70% of 50 MB it comes from OpenFreeMap, otherwise from
  VersaTiles. Dense city z14 tiles are 0.4–1.2 MB on OpenFreeMap and mountains about 1 KB, so cities
  hit the bytes and mountains the tiles.
- The fetcher stops at 50 MB. If OpenFreeMap's tiles or bytes run out mid-pack, the pack starts again
  from VersaTiles.
- If a tile server fails mid-run (HTTP errors, no connection, tiles that never come), the run starts
  again from the other source: from OpenFreeMap to VersaTiles always, and from VersaTiles to
  OpenFreeMap when the pack fits it. Routes always fit OpenFreeMap. If both fail, one message names
  both errors. Tested in the browser with faked 502s: a Moda pack and a Moda route (same five street
  names) came out of the other source.
- Routes stay on VersaTiles: they need only street names. `?source=openfreemap|versatiles` forces
  one source.
- The OpenMapTiles style matches the Shortbread one, with these differences:
  - **Peaks:** only peaks and volcanoes are drawn, with their height in metres.
  - **Parks:** come from landcover and landuse. OpenMapTiles' park layer is protected areas (the whole
    of Uludağ National Park), so it is not drawn.
  - **Stops:** tram stops are drawn with the bus stops, and subway stations with the stations.
  - **Labels:** no country or state labels.
  - **Search:** bus and tram stops are left out of search, as in Shortbread.
- Known difference: OpenMapTiles has paths and small lakes only from vector zoom 14, so they appear
  from output zoom 15, one level later than with VersaTiles.
- Found while measuring: MapLibre asks a tile again after leaving a view. Where Cache Storage fails
  (the app's browser pane), that downloaded tiles 2–3 times. The fetcher now keeps up to 200 MB of
  tiles in memory and joins requests for the same tile. The map also opens on its first view, not at
  zoom 0. Afterwards a run fetched 96 tiles against an estimate of 92 (Moda) and 428 against 408
  (Uludağ), samples included.

## Left to the builder

- The exact e-ink style: widths, patterns, label sizes, which POIs at which zoom.
- The metatile size and margin used to keep labels whole.
- The size estimator's formula; it should be within about a factor of 2.
- The exact name index layout and block size, within the rules above.
- The tool's page layout, as long as it matches the other tools.

## Questions settled

- **Where it lives:** the store and GitHub (the user).
- **For whom:** general use, city and nature (the user).
- **Zoom:** up to 19 (the user, after trying 10–18 on the device); 8–9 for Overview packs (my call).
- **Zoom stops where the pictures stop,** with a short message and a faded button (the user).
- **Pack edges:** tile by tile from the best pack; white with a dotted frame where none has it (my
  call, after the builder check).
- **Progress in the map maker** (the user).
- **Pictures, not vectors, on the reader:** the measurements.
- **The name and app_id, one rectangle per pack, three detail presets, the label-language option:**
  my calls, open to change.

## Addendum (2026-11-15, after the first device test): route labels and drawing routes

The user asked for both, after seeing a route hide the street under it.

**Street names along a route (the app).**
- The route's beads cover its street and the street's name, so the names of the streets the route
  follows are written beside it, parallel to it, about 18 px to one side, in bold on a white box.
- Where the names come from:
  - a GPX made by our tool carries them as waypoints, `<wpt lat lon><name>…</name><type>street</type></wpt>`,
    one per stretch of a street (exact, from the map data);
  - any other GPX: when the route is opened, the street entries (kind 6) of the name index of the packs
    the route crosses are read once, and those within 12 m of the route are taken. The index keeps a
    street's middle, so the street the route runs along is found, and most streets it only crosses are
    not.
- Drawing (after the device test): the reader turns no pictures (`image_transform` is missing), and
  letters set one by one along the route read badly, so the names are written level, in a white box
  beside the route: to the right of a north-south piece, above an east-west one. **Menu: Street names
  on / off** (kept in settings).
- From zoom 15; a box that would overlap one already drawn is left out.

**Drawing a route (the tool).** Two modes, chosen under the map (the user: one thing at a time, and a
route should not need a pack made each time): **A map pack** and **A route**.
- **Draw route**: each click adds a point, joined by straight lines; the length shows as you go;
  **Undo point** and **Clear route**. No snapping to streets: that needs a routing service, which needs
  a key or forbids a public tool (the same problem as the map data).
- **Load GPX** shows a route from another app.
- **Use route area** sets the pack's area to the route's bounds with a margin of 500 m.
- Points can be dragged; a faint point in the middle of each piece adds a point when dragged.
- **Make the route** reads the street names along it from the vector tiles at zoom 14 along the route
  only (the street label lines within 12 m of a route segment and within 25° of its direction), with no
  pack made, and writes them into the route's GPX as street waypoints.
- **Copy to reader** writes the GPX to `AppFiles/offlinemap/`; **Download .gpx** gives it as a file. In
  map pack mode, **Use route area** sets the area around the route.
