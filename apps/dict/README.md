# Dictionary — XTOS Licorice mini app (API 2.9)

Looks words up in StarDict dictionaries, offline, with the firmware's own keyboard: type, pick a
suggestion or press Done, read the entry. Several dictionaries can be installed side by side.

## Why a conversion step

Mini apps are confined to their own storage folder (`XTApps/dict/files/` on the SD card) and can
only read whole files, so the reader's own `dictionaries/` folder is out of reach and a 50 MB
`.dict` cannot be loaded. `stardict2shards.py` therefore cuts a StarDict dictionary into sorted
text shards of about 200 KB; a lookup reads one shard. The conversion runs once, on a computer.

## Install

1. Install `dict.xtapp` like the other apps.
2. Get a dictionary into the app's folder, in **USB mode**:
   - the ready-made **WordNet (English–English)** set from the release: unzip it into
     `XTApps/dict/files/` on the SD card; or
   - any StarDict dictionary you have (`.ifo` + `.idx` + `.dict` or `.dict.dz`):
     ```bash
     python apps/dict/stardict2shards.py "path/to/stardict-en-tr" out --prefix entr
     ```
     then copy everything in `out/` into `XTApps/dict/files/` (with no dictionary yet the app shows its folder's path, `ctx.files.path`; a store install has its own). Use a different `--prefix`
     for each dictionary; the app's storage holds 512 files, so keep the total under ~500.
3. Leave USB mode and open **Dictionary**.

**Never uninstall the app** — the firmware deletes `XTApps/dict/files/` with it. To update,
install the new `dict.xtapp` over the old one; the files stay.

## Using it

- The keyboard opens at once; suggestions appear above it as you type (prefix match, case-
  insensitive). **Done** or a tap on a suggestion opens the entry.
- Entry pages: **Back**, **Prev / Next**, tap the right / left third, side buttons, swipes.
- **Settings** at the top right: pick the dictionary in use (the choice is remembered), turn
  **Word of the Day** on the lock screen on or off, choose the dictionary it comes from and how often a new word comes (every day,
  12, 6, 3 hours or every hour). With an empty search box the last 30 lookups
  are listed.

## Word of the Day (lock screen)

Turned on in Settings (the firmware asks to confirm; Settings → Display → Off wallpaper must be
**Default**), the locked reader shows one word a day from the dictionary chosen for it (the
**from ...** row; at first the one in use), with its senses,
up to two examples each and its synonyms. The word is a plain one (lower-case letters, no
phrases or names), picked from the date (and the hour, when it changes more often than daily), so
it changes at midnight, or every 12, 6, 3 hours or every hour as set in Settings; the day's pick is kept in
`wotd.txt` and the lock screen reads no shard again that day; choosing another dictionary picks
again. Only dictionaries in the app's
folder are used.

## Format of a converted dictionary

`<prefix>_info.txt` (name, word count), `<prefix>_shards.tsv` (`file<TAB>first word<TAB>last
word` per shard), `<prefix>_d000.txt …` with lines `headword<TAB>definition`, line breaks inside
a definition written as `\n`. HTML dictionaries are reduced to text; dictd-style plain text is
unwrapped with one sense per line.

## Build and test

```bash
python xtpack.py apps/dict
python -I apps/dict/test_dict.py                 # stub dictionary, both data paths
python -I apps/dict/test_dict.py out             # against a real converted set
python -I apps/dict/test_lockscreen.py           # Word of the Day; 60 days of WordNet from the release zip
```

Verified on an X4 Pro running Licorice 26102301 (2026-10-24) with the Tureng En–Tr StarDict
(246 479 entries): instant suggestions, entries with examples. A self-contained package with the
dictionary in its data section was also tried; the installer refused the 34 MB file, so the
storage-folder route is the one that works.
