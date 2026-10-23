# v0.1.0 — first release

Mini apps for the **Xteink X4 Pro** on its stock **XTOS Licorice** firmware. Nothing is flashed:
you copy a package to the SD card and install it from the reader's own file browser.

Tested on an X4 Pro running **XTOS Licorice build 26102301** (Settings → About). Other builds of
Licorice should work as long as Xteink has not changed the package key; other Xteink models are
untested.

## Packages

| file | app | notes |
|---|---|---|
| `game2048.xtapp` | **2048** | swipe or side buttons; score and best are kept |
| `sudoku.xtapp` | **Sudoku** | 2400 puzzles in four difficulties, mistake marking, progress kept |
| `sokoban.xtapp` | **Sokoban** | 385 levels: Microban, Sasquatch, LOMA, Microcosmos, Minicosmos; undo, pack list |
| `notes.xtapp` | **Notes** | typed notes plus tap-placed lines, boxes and circles; a page can be your lock screen |
| `netprobe.xtapp` | Net Probe | developer tool: paints the Lua host's API on screen. Not needed to play |

`SHA256SUMS.txt` lists the checksums.

## Install

1. Put the reader in **USB mode** (drawer → USB mode), copy the `.xtapp` files to the **root of
   the SD card**, eject, leave USB mode.
2. Open **All Files**, tap a `.xtapp`, confirm **Install this package?** → toast **Installed**.
   Repeat per file.
3. Once: **Settings → About → tap "Model" ten times**, each tap under two seconds after the last.
   The side drawer (≡) now shows **Mini Apps**.
4. **≡ → Mini Apps** → tap an app. The Home pad (the touch pad under the screen) leaves it.

Apps keep their state between runs; leaving an app saves it.

## Known limits

- Taps and swipes only: the firmware does not report finger movement, so Notes places shapes with
  two taps instead of freehand drawing.
- One text size (the system font).
- No network access for apps on this firmware.
- Packages are bound to the firmware generation. If an update rotates the key, these files stop
  installing until rebuilt from source.

## Troubleshooting

- **Install failed**: built for a different firmware key, or a damaged file. Compare your build
  number with the one above and open an issue.
- **App error, closed**: a fault inside the app; please report your build number and what you did.
- No **Mini Apps** row: repeat the ten taps a little faster, right after the status-bar clock
  changes minute.

## Credits

Built on the firmware reverse engineering of [kycube/x4pro-emu](https://github.com/kycube/x4pro-emu)
(MIT). Puzzles from the public-domain sudoku-exchange bank; Sokoban packs by David W. Skinner and
Aymeric du Peloux as published on sokobano.de with the authors' permission. The games were first
written for the CPR-vCodex custom firmware and ported to the stock host.

Unofficial; use at your own risk. Source, build instructions and firmware notes are in the
repository.
