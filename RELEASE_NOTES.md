# v0.3.1

Bug fixes for **RSS** and **Dictionary** on the **Xteink X4 Pro** (stock XTOS Licorice, build **26102301**).

## Fixed

- **Side buttons turned two pages at once** in RSS and Dictionary. The firmware sends more than one
  key event for a single press; release events and a repeat of the same button within 250 ms are now
  ignored, so one press turns one page.
- **RSS: an `ERR … attempt to index a nil value` line** could appear at the bottom while an article
  was loading and then stayed on every screen. The loading frame no longer reads the previous
  article's pages, and in RSS, Notes and Dictionary an error message now disappears with the next tap.

## Update

Install the new `rss.xtapp`, `dict.xtapp` and `notes.xtapp` **over** the installed apps (SD card root
→ All Files → Install). Do not uninstall first: that deletes the app's folder (RSS settings and cache,
Notes pages, Dictionary files). Settings, pages and dictionaries are kept when you install over them.

## Files

| file | content |
|---|---|
| `rss.xtapp`, `dict.xtapp` | **changed**: both fixes |
| `notes.xtapp` | **changed**: error message clears with the next tap |
| `game2048.xtapp`, `sudoku.xtapp`, `sokoban.xtapp` | unchanged |
| `probe.xtapp`, `netprobe.xtapp` | developer tools, unchanged |
| `dict-wordnet-en.zip` | WordNet for Dictionary, unchanged (see v0.3.0) |

All packages are included so one release has everything. `SHA256SUMS.txt` has the checksums.

# v0.3.0

New app: **Dictionary** (`dict.xtapp`). Offline StarDict lookup on the **Xteink X4 Pro** (stock XTOS Licorice,
build **26102301**): the firmware keyboard docked at the bottom, suggestions as you type, paged entries,
several dictionaries side by side, recent lookups.

## Install

1. Install `dict.xtapp` like the other apps (SD card root → All Files → Install).
2. In **USB mode** unzip `dict-wordnet-en.zip` (WordNet, English–English, Princeton license) into
   `XTApps/dict/files/` on the SD card. Any other StarDict dictionary: run
   `python apps/dict/stardict2shards.py <folder> out --prefix xx` and copy `out/*` there too.
3. Leave USB mode, open **Dictionary**.

**Do not uninstall the app** — the firmware deletes `XTApps/dict/files/` with it. Install updates over it.

## Files

| file | content |
|---|---|
| `dict.xtapp` | **Dictionary** (new) |
| `dict-wordnet-en.zip` | WordNet converted (128 shards, 25 MB unpacked), with its license |
| `game2048.xtapp`, `sudoku.xtapp`, `sokoban.xtapp` | the games, same builds as v0.2.0 |
| `notes.xtapp`, `rss.xtapp` | Notes and RSS, same builds as v0.2.0 |
| `probe.xtapp`, `netprobe.xtapp` | developer tools, not needed to play |

All packages are included so one release has everything. `SHA256SUMS.txt` has the checksums.

# v0.2.0

Mini apps for the **Xteink X4 Pro** on stock **XTOS Licorice** firmware. No flashing: copy, install, play.
Tested on build **26102301**. Unofficial, use at your own risk.

## New

- **RSS** (`rss.xtapp`): read your CommaFeed articles on the device, as text, through the free
  [rss-opds](https://github.com/omer-faruq-xteink/rss-opds) Worker — unread / starred / all / by
  feed, full-text option, offline cache. Enter the Worker host and token in Settings once.
- **Notes** rewritten (`notes.xtapp`): freehand drawing, the firmware's own keyboard, three text
  sizes, eight pages, and a real lock screen with clock and battery (the firmware asks once).
  Pages from the old Notes are not migrated.
- Both use the firmware's **API 2.9** (manifest `"api": "2.0"`), newly mapped: network, JSON,
  file storage, native keyboard, pointer movement, fonts, lock screen. Details in
  `docs/firmware-notes.md`; `probe.xtapp` is the tool that found them.

## Packages

| file | app |
|---|---|
| `game2048.xtapp` | **2048** — swipe or side buttons, best score kept |
| `sudoku.xtapp` | **Sudoku** — 2400 puzzles in four difficulties, mistake marking |
| `sokoban.xtapp` | **Sokoban** — 385 levels (Microban, Sasquatch, LOMA, Microcosmos, Minicosmos), undo |
| `notes.xtapp` | **Notes** — draw and type, lock-screen page with clock |
| `rss.xtapp` | **RSS** — CommaFeed via rss-opds, needs Wi-Fi |
| `probe.xtapp`, `netprobe.xtapp` | developer tools, not needed to play |

`SHA256SUMS.txt` has the checksums.

## Install

1. USB mode → copy the `.xtapp` files to the **SD card root**.
2. **All Files** → tap a file → **Install**.
3. Once: **Settings → About → tap "Model" 10 times** quickly. **Mini Apps** appears in the drawer (≡).
4. **≡ → Mini Apps** → tap an app. The Home pad leaves it. State is saved on leave.

## Limits

- Games: taps and swipes, one text size. Notes / RSS: the three system fonts, 1-bit screen, no images yet.
- Packages are tied to the firmware's key; a future update may require a rebuild.

Credits: [kycube/x4pro-emu](https://github.com/kycube/x4pro-emu) for the firmware reverse engineering;
puzzles from the sudoku-exchange bank (public domain); Sokoban packs by David W. Skinner and
Aymeric du Peloux via sokobano.de. Source and build instructions are in the repository.
