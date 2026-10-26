# Xteink Licorice mini apps

Games and tools for the **Xteink X4 Pro** e-reader running its stock **XTOS Licorice** firmware,
written in Lua for the firmware's built-in mini-app host. No custom firmware, no flashing: you
copy a package to the SD card and install it from the reader's own file browser.

| app | what it is |
|---|---|
| **2048** | the sliding-tile game; swipe or side buttons, score and best kept |
| **Sudoku** | 9x9 puzzles, 2400 of them in four difficulties, mistake marking, progress kept |
| **Suguru** | also called Tectonic: fill each region with 1..n, touching cells never repeat; 800 generated puzzles from 5x5 to 8x8 |
| **Sokoban** | 385 levels in five classic packs, undo, pack list, position kept per pack; add your own packs |
| **Merchant** | a turn-based trading game in four settings (caravan, star trader, clipper, antiques); seven languages |
| **Notes** | freehand drawing and typed text on eight pages; one page becomes the lock screen, with clock and battery |
| **RSS** | reads your CommaFeed articles as text over Wi-Fi, through the [rss-opds](https://github.com/omer-faruq-xteink/rss-opds) Worker; offline cache |
| **Instapaper** | your Instapaper articles as text, straight from Instapaper with an access token; progress kept in sync, archive and star |
| **Dictionary** | offline StarDict lookup with the firmware keyboard; WordNet (English) ready-made, any StarDict after a one-time conversion |
| **API Probe**, **Net Probe** | developer tools that exercise the Lua host and paint the results |

Everything here is unofficial and was reverse-engineered from the firmware. It worked on an X4
Pro running **XTOS Licorice build 26102301** (October 2026). Read "Caveats" before installing.

Two host APIs exist on this build. The games use the default **API 0.8** (taps, swipes, one text
size, no network). Notes, RSS, Instapaper, Dictionary and Merchant declare `"api": "2.0"` and get **API 2.9**: finger movement,
the firmware's keyboard, HTTPS, JSON, file storage, three font sizes, a live lock screen. Both
install the same way.

## Install

You need an X4 Pro on XTOS Licorice (Settings → About shows "XT Licorice …") and the `.xtapp`
files from the [latest release](../../releases).

1. Put the reader in **USB mode** (drawer → USB mode) and copy the `.xtapp` files to the **root
   of the SD card**. Eject and leave USB mode.
2. On the reader open **All Files**, tap a `.xtapp` file, confirm **Install this package?**. The
   toast **Installed** appears. Repeat for each file.
3. Unlock the hidden menu, once: **Settings → About → tap "Model" ten times**, each tap less than
   two seconds after the previous one. Nothing is shown, but the side drawer (≡) now has a
   **Ink App** row between Cloud and USB mode.
4. **≡ → Ink App** lists the installed apps. Tap one to start it. The **Home pad** (the touch pad
   under the screen) asks "Leave app" to return.

Apps keep their state (your Sudoku grid, your Sokoban position, your notes) between runs; leaving
an app saves it.

### If the install fails

- **Install failed**: the package was built for a different firmware key, or the file is damaged.
  Check the release notes for the Licorice build it was made with. See "Caveats".
- **Cannot run yet** / **App error, closed**: a problem inside the app; please open an issue with
  your firmware build (Settings → About) and what you did.
- No **Ink App** row: repeat the ten taps a little faster, right after the status-bar clock
  changes minute.

## The apps

### 2048

Swipe in any direction, or use the side buttons for up / down. **New game** asks first. Tiles get
heavier outlines as they grow. Score and best score persist. [More](apps/game2048/README.md)

### Sudoku

Tap a cell, then a digit on the pad. **Erase** clears, **Chk on/off** marks the cells that break a
rule, **Next** and **Bank** move through 600 puzzles each of easy, medium, hard and diabolical. Side
buttons go to the previous / next puzzle. Puzzle banks are plain text files inside the package;
adding your own is one command. [More](apps/sudoku/README.md)

### Suguru

Also called Tectonic. Regions of one to five cells (thick borders) each hold 1 to n; touching
cells, diagonals included, never hold the same number. Tap a cell, then a number; **Erase**, **Chk**,
**Next** and **Bank** work as in Sudoku. 200 generated puzzles each of 5x5 easy, 6x6 medium, 7x7 hard
and 8x8 expert, every one with a single solution. Drawn with heavy lines and bold digits for faint
panels. [More](apps/suguru/README.md)

### Sokoban

Swipe, or tap the board on the side of the player you want to go; side buttons move up / down and,
after a solve, the lower one goes to the next level. **Undo** takes a move back, **Reset** asks,
**Prev / Next** change level, **Set** opens the pack list. Shipped packs: Microban, Sasquatch, LOMA,
Microcosmos, Minicosmos. Any XSB / `.sok` pack you have can be added with one command.
[More](apps/sokoban/README.md)

### Notes

**Draw** with a finger; **Text** places typed text where you tap, using the firmware's own keyboard
(tap **Text** again for small / medium / large). **Undo**, **Page** (eight pages), **Clear**.
**Lock** makes the current page the device's lock screen — the firmware asks once — with or
without the time and battery level (with them it is redrawn every minute). Pages live in the app's storage.
[More](apps/notes/README.md)

### RSS

Your [CommaFeed](https://www.commafeed.com) account on the reader, as text: **Unread**, **Starred**,
**All**, by **Feed**. Articles open inside the app, laid out with the system fonts (headings, quotes,
lists), optionally as full text extracted by the Worker; opening one marks it read. Lists and read
articles are cached for offline use. Needs the free [rss-opds](https://github.com/omer-faruq-xteink/rss-opds)
Cloudflare Worker: enter its host and token in the app's Settings once. [More](apps/rss/README.md)

### Merchant

Buy low, sell high across six trading posts in 30 days, with a moneylender, a bank, raiders and
offers on the road, ported from the KOReader plugin merchant.koplugin with its rules, four themes
and seven languages unchanged. Saved after every move; best score per theme. [More](apps/merchant/README.md)

### Instapaper

Your [Instapaper](https://www.instapaper.com) account on the reader: **Unread**, **Starred**,
**Archive** and your folders, with the same list, preview and article screens as RSS. Articles open
where you left off (the progress Instapaper keeps, also from KOReader or the website) and send it
back when you leave; **Archive** and **Star** from the preview or the article's end. No Worker: the
app talks to Instapaper directly with a personal access token. [More](apps/instapaper/README.md)

### Dictionary

Type with the firmware keyboard, pick a suggestion, read the entry; several dictionaries side by
side. Dictionaries are StarDict files converted once on a computer into text shards and copied
over USB into `XTApps/dict/files/` on the SD card — the release ships **WordNet** (English–English)
converted; for anything else run `apps/dict/stardict2shards.py`. Never uninstall the app (the
folder goes with it); install updates over it. [More](apps/dict/README.md)

## Build from source

Requirements: Python 3.10+ and one package.

```bash
pip install cryptography
python build_all.py
```

Every app lands in `dist/` as `<name>.xtapp`. A single app: `python xtpack.py apps/sudoku`.

No firmware dump is needed: packages must be encrypted for a key the firmware carries, and that
key is a constant shared by every unit, so its public half is embedded in `xtpack.py`. If a future
firmware changes it, derive the new one from your own device with `tools/netprobe/pack.py` and
pass `--image` (see [docs/firmware-notes.md](docs/firmware-notes.md)).

### Adding puzzles and levels

- **Sudoku**: drop a bank file into `apps/sudoku/data/` (sudoku-exchange lines, 81-character lines
  or Kaggle CSV, as downloaded) and rebuild. `apps/sudoku/prepare_data.py` fetches the public-domain
  sudoku-exchange bank.
- **Sokoban**: `python apps/sokoban/prepare_data.py --clean "folder of .txt/.sok packs"` then
  rebuild. Up to 63 packs; names are sanitised automatically.

### Tests

The apps have offline tests under Lua 5.4 (`pip install lupa`), including an emulation of the
firmware's file reader written from the firmware's own code:

```bash
python -I apps/game2048/test_2048.py
python -I apps/sudoku/test_sudoku.py
python -I apps/sokoban/test_sokoban.py
python -I apps/suguru/test_suguru.py
python -I apps/notes/test_notes.py
python -I apps/rss/test_rss.py
python -I apps/instapaper/test_instapaper.py
python -I apps/merchant/test_merchant.py
python -I apps/dict/test_dict.py
```

`build_all.py` also runs `tools/lualint55.py` over every Lua file: the device's Lua 5.5 rejects an
assignment to a `for` loop variable at compile time (the package then only says "App error,
closed"), which the Lua 5.4 tests cannot catch.

## Writing your own app

An app is a folder with `manifest.json` and `index.lua`, optionally a `data/` folder. The host
calls `on_load(ctx)`, `on_draw(ctx, g)`, `on_input(ctx, event)`, `on_leave()`; `g` draws (rect, line,
circle, polygon, polyline, text, text_box, image …), `ctx.state` is a persisted table, `ctx.data`
reads the package's data files. Lua is 5.5: do not assign to `for` loop variables, and wrap your
callbacks in `pcall` the way the apps here do, so an error is shown on screen instead of
"App error, closed". `apps/game2048/index.lua` is the smallest complete example (API 0.8).

For **API 2.9** put `"api": "2.0"` in the manifest with `permissions` drawn from `net` and
`reader` (or none). Then `g` is only the argument of `on_draw`, every `ctx.*` function is a method
(`ctx.storage:write(name, data)`, `ctx.net:request({url=…}, function(ctx, resp) … end)`,
`ctx.input:text({title=…}, function(ctx, s) … end)`, `ctx.json:decode(s)`), pointer events carry
`phase = down / move / up`, `ctx.fonts.small / medium / large` go into `g:text(x, y, s, {font = f})`,
and a manifest `lockscreen` block plus `ctx.lockscreen:set_default()` make your `lockscreen.lua`
the device's lock screen. `apps/notes` and `apps/rss` are the examples; the probed signatures,
limits and gotchas are in [docs/firmware-notes.md](docs/firmware-notes.md).

## Caveats

- **Unofficial.** Xteink has not published this API; the firmware's own strings mention an upcoming
  app store with a different, per-device signing scheme. Nothing here touches the firmware itself,
  but installing anything the manufacturer did not provide is at your own risk.
- **Firmware-bound.** A package installs on any X4 Pro on the same Licorice generation. If Xteink
  rotates the key in an update, existing packages stop installing until rebuilt.
- **e-ink.** The apps draw lightly and trigger a full refresh every few moves to limit ghosting.
- **Network.** Only RSS and Instapaper use it: RSS towards the Worker host you enter, Instapaper
  towards www.instapaper.com with your token; nothing else leaves the device. Notes needs no
  permission at all.
- Other Xteink models (X4, X4 Classic, X3) are untested.

## Releases

Each release attaches the `dist/*.xtapp` files and names the Licorice build they were tested on.
To make one: `python build_all.py`, tag, upload `dist/`.

## Credits

Built on the reverse engineering in [kycube/x4pro-emu](https://github.com/kycube/x4pro-emu) (MIT),
whose `xtapp.py` is vendored here. Puzzle and level sources are listed in [NOTICE.md](NOTICE.md).
Games were first written for the CPR-vCodex custom firmware and ported to the stock host.

License: MIT (see `LICENSE`); third-party content as in `NOTICE.md`.
