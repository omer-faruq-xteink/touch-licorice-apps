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
