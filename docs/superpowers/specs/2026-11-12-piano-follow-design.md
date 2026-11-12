# Piano Follow: sheet music that follows your playing (design)

Status: draft, 2026-11-12. Not committed until the device test passes (user's rule).

## Intent

An XTApp for the Xteink X4 Pro (e-ink, 480x800, touch, BLE) for anyone with a MIDI keyboard. The
user picks a piece from a free catalog we prepare (or converts their own), downloads it to the
reader, puts the reader on the music stand and plays. The app follows the playing over Bluetooth
MIDI and turns the pages; in practice mode it waits for the right notes. Without a keyboard it is
a plain sheet-music reader. It is for the general public, mostly learners, not for the author.

Why e-ink: no glare, days of battery, paper-like reading on a stand. Page turning without hands
is the main daily value; practice mode is the learning value.

## Goals

- Three play modes, chosen per piece and remembered:
  - **Page turn**: follows silently, turns the page near its end. Minimal expectations.
  - **Follow**: page turn plus a small marker under the current bar, refreshed about once a second.
  - **Practice**: the score waits until the next note/chord is played right; hand choice (right,
    left, both); wrong notes are counted but do not advance; at the end a summary lists the bars
    with mistakes.
- A curated catalog growing to about 200-300 pieces (30-50 at first release), mostly beginner and easy, plus well-known classical
  works; browsed by level (beginner, easy, intermediate, advanced), then composer, plus title
  search; every piece shows its source, license and credits.
- A converter page on our site: the user's own MusicXML/MXL/ABC becomes a piece file, written
  straight to the reader's card.
- Works without a keyboard: tap or key turns pages.

## Non-goals (v1)

- Sound output, metronome, tempo grading or rhythm scoring.
- MIDI files, PDF or photo scans as input (MIDI-to-notation looks bad; OMR is a separate problem).
- Portrait, two-page view, zoom levels (one fixed engraving size per piece).
- The phone bridge (phone Chrome reads a USB keyboard with Web MIDI and sends notes to the reader
  with Web Bluetooth): a later version; the app's own GATT service would make it possible.
- Accounts, syncing, sharing user files.

## Anti-goals (would be a failure even if it works)

- Turning a page too early or jumping around while the player is still on the page. A late turn
  is acceptable; a wrong turn is not. When unsure, do not turn.
- Notation that looks amateur or is hard to read on a stand.
- Shipping scores we have no clear right to publish.
- Slow reading: opening a downloaded piece and turning a page must feel instant.

## Constraints (platform facts)

- XTApp API: `layer:set_bits` (2.21) writes 1-bit rows into a layer; `ctx.ble` (2.19, optional
  capability `ble`, permission `ble`); `ctx.files` (2.9) = `AppFiles/<app_id>/`, reads of at most
  64 KB per call; `ctx.net:request` with `save={to='files'}` up to 8 MB (2.18); `ctx.zlib:decompress`
  up to 1 MB output; `ctx.hash:crc32`. The user's reader runs firmware 26110501 (API 2.21).
- Callback limits: 1000 ms for input and net callbacks, 1500 ms for `on_draw`, `ctx.budget:extend()`
  for heavy work. A frame costs roughly 0.5-0.65 s on e-ink, so per-note highlighting at playing
  speed is impossible; markers are coalesced.
- BLE (section 31): central `scan` / `connect` / `subscribe`, `on_notify` per packet; at most 32
  notifications queued per connection (oldest dropped); radio latency jitters by a few hundred
  ms during refresh. One central connection per app. `secure=true` does Just Works pairing.
- BLE MIDI: service `03b80e5a-ede8-4b33-a751-6ce34ec4c700`, characteristic
  `7772e5db-3868-4112-a1a9-f2669d106bf3` (notify). Packet = header byte, then one or more
  (timestamp byte, MIDI message) with running status; note-on with velocity 0 is note-off; SysEx
  and other messages are ignored.
- Lua 5.x with 32-bit integers on the reader; 200-locals limit per chunk; native `require` of
  other package files works on 26110501.
- Store: static check refuses API calls newer than the manifest's `api`; the Back key on the main
  screen returns false (house rule). No back-compat for older firmware (house rule): manifest
  `api` 2.21, permissions `net`, `ble`. `ble` is not put in `requires`, so a reader without BLE
  still installs it as a reader.
- Repo: MIT; never copy GPL code in. Verovio (LGPL-3.0) is used unmodified as an npm dependency of
  the tools and loaded from a CDN by the converter page; it is not vendored into the repo.

## Decision after the device trial (2026-11-12)

The user compared portrait (480 x 760 pages) and landscape (800 x 440 pages, music about 15% bigger)
on the reader and chose landscape; portrait is dropped. The whole app runs in landscape (manifest
`display.orientation`), so nothing rotates during a session. Lists show two columns with Prev / Next.
Where this document says 480 x 760 or portrait, read 800 x 440 and landscape.

## Approaches considered

- **A. Catalog prepared on the PC, pages pre-engraved (chosen).** A tool engraves each piece with
  Verovio at the screen size into 1-bit page images plus a note map; we publish them as static
  files on our GitHub Pages; the app downloads, shows and follows. Professional notation, light
  device code. Cost: only pieces we add (batch tooling makes hundreds cheap).
- B. Engraving on the device from MusicXML/ABC. Any file, but a very large job, weaker notation,
  heavy XML parsing in Lua, and the free sources have no API anyway. Rejected.
- C. Folk melodies from thesession.org (ABC, live search). Melody only, not piano. Possible later
  as a separate section.

The user picked A, and added the converter page for their own files.

## Design

### 1. The piece file (`.xtscore`), one file per piece

One binary file holds everything, so a catalog download is one `save` and a user copy is one file.
Layout (builder fixes the exact bytes and documents them in the app's README):

- magic + version;
- a JSON header: title, composer, arranger, source, source URL, license, level, page count,
  page width/height, page directory (offset + length of each compressed page), and the offset of
  the note map;
- pages: each a zlib-compressed 1-bit bitmap (rows of ceil(480/8) bytes, high bit first, 1 = black),
  ready for `layer:set_bits`; expected 5-10 KB each, always under 64 KB so one `read` gets a page;
- the note map (compact, JSON or packed): the performance-ordered list of onsets. Each onset: a
  sequence index, the pitches per hand (staff 1 = right, staff 2 = left), its bar number, page,
  system, and the x/y of the bar (for the Follow marker) and of the notehead (for Practice). Bars
  per page and the first onset of each page's last system are listed for page turning.

### 2. The converter (one JavaScript module, two front ends)

- `tools/piano/convert.mjs` (shared module): input MusicXML/MXL/ABC → Verovio (npm `verovio`) →
  per-page SVG with options for the reader's page (480 wide, music area about 480x760 below a
  status bar; scale tuned once for stand reading; no header/footer except the title on page 1;
  `breaks: auto`) → raster → threshold to 1 bit → zlib → `.xtscore`. The note map comes from
  Verovio's timemap (onsets in order, element ids) plus the SVG element positions.
- Rasterizing: in the browser, SVG drawn onto a canvas; in Node, `@resvg/resvg-js`. Same layout,
  near-identical pixels.
- **Converter page** `site/tools/piano/`: pick a file, preview the pages, then write the
  `.xtscore` to `AppFiles/pianofollow/` using the existing "Connect the reader" code
  (`site/assets/store.js`, File System Access API), or download it. Nothing is uploaded. The
  user's files are theirs; copyright is their responsibility (said on the page).
- **Catalog tool** `tools/piano/build_catalog.mjs` (Node): reads a hand-kept selection list
  (`tools/piano/catalog.yaml`: source id, level override, credits), converts each piece, writes
  `catalog/piano/catalog.json` (small index: id, title, composer, level, pages, size, license)
  and `catalog/piano/pieces/<id>.xtscore`.

### 3. The catalog content

- Source: mainly PDMX (about 250k public-domain/CC0 MusicXML files scraped from MuseScore, bulk
  download from Zenodo, with metadata). Drop entries with `license_conflict`; keep public domain,
  CC0 and CC-BY(-SA) with credits. Piano-only instrumentation. Prefer higher ratings and views.
  Mutopia is out for now (LilyPond, not readable by Verovio).
- Mix: mostly beginner and easy (familiar melodies, children's and folk songs, simple
  arrangements, easy classical pieces such as Anna Magdalena Bach, Czerny, Burgmüller), plus a
  smaller set of famous intermediate and advanced works (Für Elise, Bach preludes, Satie...).
- Level: estimated on the PC from note density, range, chord size and tempo; checked by hand once,
  overrides kept in `catalog.yaml`.
- Rights and quality check (user's choice, 2026-11-12): an automated filter, then the builder's
  review; the user spot-checks a sample.
  - Filter: keep only traditional pieces or composers who died before 1955 (public domain in
    most countries); drop modern songs and film/game themes by title/composer lists; drop
    `license_conflict`; keep the uploader's license and credits.
  - Review: contact sheets of every page of every piece, checked by the builder for wrong notes,
    messy engraving and unreadable layouts; `catalog.yaml` records the review status, and only
    reviewed pieces are built.
- Hosting (user's choice): the app reads the catalog from the repo's raw files on the main branch
  (`https://raw.githubusercontent.com/omer-faruq-xteink/touch-licorice-apps/main/catalog/piano/...`),
  so new pieces go live when pushed, independent of app releases and of site deploys (the Pages
  site is redeployed only when a release is opened). Kept outside `site/` so the site stays small.
  About 30 MB for 300 pieces.
- First release (user's choice): a starter set of 30-50 reviewed pieces, mostly beginner and
  easy, growing later in pushes. The converter page ships with the first release.

### 4. The app (`apps/pianofollow`, display name "Piano Follow")

Screens:
- **Home**: My pieces (downloaded and user files in `AppFiles/pianofollow/`, with delete), Catalog,
  Keyboard (connection state), Help.
- **Catalog** (downloaded from the raw catalog URL above): levels → composers → pieces; title search; piece card with credits, size,
  Download (`save` to files) then Open.
- **Score**: one page at a time; a thin status bar (title, page n/m, mode, keyboard state); mode
  switch; tap left/right or keys to turn pages; Back returns to Home.
- **Practice summary**: bars with mistakes, wrong-note count, Practice again (from a chosen bar).

Drawing: the page bitmap is decompressed and written with `set_bits` into an offscreen layer once
per page; markers are drawn on top in `on_draw`. Page turn = new layer + one full refresh.

Keyboard: scan for the BLE MIDI service, connect, subscribe; remember the last device and
reconnect on open; a keyboard that needs pairing is retried with `secure=true`. Notes go into a
small queue processed in `on_notify`; the follower runs there, and a redraw is requested only when
the page or the marker's bar changes (coalesced to about one per second).

Following (Page turn and Follow), my calls:
- Online alignment against the note map: keep a current position; each played pitch is matched
  within a window ahead (and a little behind) of it; extra and missing notes are tolerated; a
  position moves only after two or three consistent matches.
- Jump back (repeats, starting a bar again): if matching fails for a few notes, search the whole
  piece for the last few pitches played and resume there.
- Turn the page when the player is confidently in the last system of the page (turn point
  configurable in settings: last system or last bar). Never turn on a single match.

Practice: strict next-onset waiting with the hand filter; a chord counts when all its notes of the
chosen hand(s) are down in any order (within about 1 s); wrong pitches count as mistakes per bar;
the summary at the end or on Back.

Without BLE (`ctx.ble` nil, or no keyboard found): the same screens, manual page turning only.

### 5. Testing (user's routes 1 and 2), nothing committed until the device test passes

1. **Harness** (`apps/pianofollow/test_pianofollow.py`, lupa like our other apps): a `ctx.ble`
   stub that delivers BLE MIDI packets; tests for the packet parser (running status, several
   messages per packet, velocity-0 off), the follower (clean play, wrong notes, skipped notes,
   repeats, jumping back, page turns at the right time and never early), Practice (hands, chords,
   mistakes summary), file reading and catalog download with the `save`/`files` stubs. The
   converter gets Node tests with a few golden pieces.
2. **PC BLE MIDI simulator** (`tools/piano/blemidi_sim.py`, Python `bless` as a GATT server on
   Windows, `mido` + `python-rtmidi` for MIDI input): advertises the BLE MIDI service like a
   keyboard and sends (a) the notes of a USB MIDI keyboard plugged into the PC, or (b) a piece's
   note map with an optional tempo and injected errors, so the device can be tested hands-free.
   First step: a probe that the PC's Bluetooth can act as a peripheral and the reader connects.
3. Device test on the reader: connect, follow a catalog piece, practice mode, page-turn timing,
   battery and refresh feel. Then (and only then) commit, store submission, site and catalog.

Test hardware (answered): the user has no BLE keyboard; their keyboard is USB (normally plugged
into a phone). The device test therefore uses the PC simulator, fed by the user's USB keyboard
plugged into the PC, or by a piece's note map. Keyboards differ in packing and pairing, so the
parser follows the BLE MIDI spec fully (several messages per packet, running status, timestamp
bytes, velocity-0 off) and the simulator can send both packed and one-note-per-packet styles.
If the PC probe fails (Windows Bluetooth cannot act as a peripheral), fallback (my call): an
Android app that acts as a BLE MIDI peripheral for a USB keyboard; if none works, an ESP32 board
running a BLE MIDI sketch.

Pass criteria (my call):
- three catalog pieces (beginner, easy, intermediate), each played start to end in Follow mode
  from the simulator with injected errors (5% wrong, 5% skipped notes, one repeated bar) and once
  by the user on the USB keyboard: every page turned, **zero early turns** (hard), no turn later
  than the first two bars of the next page;
- Practice on one piece with each hand setting: advances only on right notes, chord in any order,
  the summary lists the bars where errors were injected;
- no callback over its time limit in a full run; reconnects after the keyboard goes away and back.

Practice screen (my call): while waiting, a small marker sits under the next notehead; it moves
after each correct onset (one coalesced frame, fine because the player waits for it). A wrong
note shows only a mistake count in the status bar (coalesced with the marker frame), and is
listed in the summary.

## Left to the builder

- Exact `.xtscore` byte layout and note-map encoding; Verovio options and the engraving scale.
- The alignment algorithm's details and thresholds, within the anti-goals above.
- How Verovio's repeats are unfolded into performance order (expand when possible, otherwise the
  written order with jump-back search covering repeats).
- PDMX download and filtering scripts; the difficulty formula.
- UI details within the existing house style (kit buttons, lists, fonts).
