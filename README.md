# Xteink Licorice mini apps

Games and tools for the **Xteink X4 Pro** e-reader running its stock **XTOS Licorice** firmware,
written in Lua for the firmware's built-in mini-app host. No custom firmware, no flashing: you
copy a package to the SD card and install it from the reader's own file browser.

| app | what it is |
|---|---|
| **2048** | the sliding-tile game; swipe or side buttons, score and best kept |
| **Sudoku** | 9x9 puzzles, 2400 of them in four difficulties, mistake marking, progress kept |
| **Sokoban** | 385 levels in five classic packs, undo, pack list, position kept per pack; add your own packs |
| **Notes** | typed notes (on-screen keyboard) plus tap-placed lines, boxes and circles; a page can be your lock screen |
| **Net Probe** | a developer tool that paints the Lua host's API on screen |

Everything here is unofficial and was reverse-engineered from the firmware. It worked on an X4
Pro running **XTOS Licorice build 26102301** (October 2026). Read "Caveats" before installing.

## Install

You need an X4 Pro on XTOS Licorice (Settings → About shows "XT Licorice …") and the `.xtapp`
files from the [latest release](../../releases).

1. Put the reader in **USB mode** (drawer → USB mode) and copy the `.xtapp` files to the **root
   of the SD card**. Eject and leave USB mode.
2. On the reader open **All Files**, tap a `.xtapp` file, confirm **Install this package?**. The
   toast **Installed** appears. Repeat for each file.
3. Unlock the hidden menu, once: **Settings → About → tap "Model" ten times**, each tap less than
   two seconds after the previous one. Nothing is shown, but the side drawer (≡) now has a
   **Mini Apps** row between Cloud and USB mode.
4. **≡ → Mini Apps** lists the installed apps. Tap one to start it. The **Home pad** (the touch pad
   under the screen) asks "Leave app" to return.

Apps keep their state (your Sudoku grid, your Sokoban position, your notes) between runs; leaving
an app saves it.

### If the install fails

- **Install failed**: the package was built for a different firmware key, or the file is damaged.
  Check the release notes for the Licorice build it was made with. See "Caveats".
- **Cannot run yet** / **App error, closed**: a problem inside the app; please open an issue with
  your firmware build (Settings → About) and what you did.
- No **Mini Apps** row: repeat the ten taps a little faster, right after the status-bar clock
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

### Sokoban

Swipe, or tap the board on the side of the player you want to go; side buttons move up / down and,
after a solve, the lower one goes to the next level. **Undo** takes a move back, **Reset** asks,
**Prev / Next** change level, **Set** opens the pack list. Shipped packs: Microban, Sasquatch, LOMA,
Microcosmos, Minicosmos. Any XSB / `.sok` pack you have can be added with one command.
[More](apps/sokoban/README.md)

### Notes

**Type** opens an on-screen keyboard. **Draw** places a line, box or circle with two taps (the host
reports taps, not finger movement, so there is no freehand drawing). **Pages** manages up to twelve
pages. **Lock** makes the current page the device's standby screen, shown with the clock.
[More](apps/notes/README.md)

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
python -I apps/notes/test_notes.py
```

## Writing your own app

An app is a folder with `manifest.json` and `index.lua`, optionally a `data/` folder. The host
calls `on_load(ctx)`, `on_draw(ctx, g)`, `on_input(ctx, event)`, `on_leave()`; `g` draws (rect, line,
circle, polygon, text, text_box …), `ctx.state` is a persisted table, `ctx.data` reads the package's
data files. What the host exposes, what it does not (no network, no filesystem, no freehand touch),
the frame budget of 1024 drawing commands and the 1 MB Lua heap are written up in
[docs/firmware-notes.md](docs/firmware-notes.md); `apps/game2048/index.lua` is the smallest
complete example. Lua is 5.5: do not assign to `for` loop variables, and wrap your callbacks in
`pcall` the way the apps here do, so an error is shown on screen instead of "App error, closed".

## Caveats

- **Unofficial.** Xteink has not published this API; the firmware's own strings mention an upcoming
  app store with a different, per-device signing scheme. Nothing here touches the firmware itself,
  but installing anything the manufacturer did not provide is at your own risk.
- **Firmware-bound.** A package installs on any X4 Pro on the same Licorice generation. If Xteink
  rotates the key in an update, existing packages stop installing until rebuilt.
- **e-ink.** The apps draw lightly and trigger a full refresh every few moves to limit ghosting.
- Other Xteink models (X4, X4 Classic, X3) are untested.

## Releases

Each release attaches the `dist/*.xtapp` files and names the Licorice build they were tested on.
To make one: `python build_all.py`, tag, upload `dist/`.

## Credits

Built on the reverse engineering in [kycube/x4pro-emu](https://github.com/kycube/x4pro-emu) (MIT),
whose `xtapp.py` is vendored here. Puzzle and level sources are listed in [NOTICE.md](NOTICE.md).
Games were first written for the CPR-vCodex custom firmware and ported to the stock host.

License: MIT (see `LICENSE`); third-party content as in `NOTICE.md`.
