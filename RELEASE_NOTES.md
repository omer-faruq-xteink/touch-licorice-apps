# v0.5.0

Updates for the **Xteink X4 Pro** mini apps (stock XTOS Licorice, build **26102301**).

## Changed

- **RSS**: Back from an article opened with the preview's **Open** returns to that preview (now
  shown as read), so you can keep stepping through the summaries with Prev / Next. An article
  opened straight from the list still returns to the list.
- **RSS: several CommaFeed accounts.** If your rss-opds Worker serves more than one account (for
  example a personal and a work one, set with `COMMAFEED_API_KEY_2` and optional names
  `COMMAFEED_LABEL` / `COMMAFEED_LABEL_2`, see the rss-opds README), the menu starts with one folder
  per account; lists, articles, the offline cache and mark-as-read stay in their account. With one
  account, or an older Worker, nothing changes. Needs the updated Worker (`git pull`,
  `npx wrangler deploy`); the OPDS catalog shows the same account folders.
- **RSS: text size.** Settings → **Text size**: *small*, *default* (as before) or *large*, for
  articles and previews; headings and the title follow it. The firmware has three fonts, so these
  are the steps there are; with *large* the title gets a rule under it.
- **RSS: images (optional).** Settings → **Images in articles**, off by default. Pictures appear
  where they are in the text, as greyscale JPEGs fitted to the screen width, loaded after the
  text for the page on screen only, straight from the free images.weserv.nl resizer. If it cannot
  deliver a picture, the picture shows as `[image]`; the text is never held up. Icons and emoji
  are left out. Needs the updated Worker.
- **Notes: lock screen with or without the clock.** **Lock** now asks in the app: *With clock*,
  *No clock* or *Cancel* (the firmware dialog it used did not appear on every device). Without
  the clock the lock screen shows only your page. **Clear** asks the same way before erasing.
- **RSS: fewer "no feeds".** A list or the feed list that fails to load (Wi-Fi still waking up,
  a slow CommaFeed) is tried once more by itself; if it still fails, the screen says why and
  suggests Reload instead of showing an empty list. The Worker also retries CommaFeed once.
- **RSS: no more lists stuck on "loading".** The device answered only one network request at a
  time, so a list opened while the app was still asking for the account list (or loading a
  picture) never arrived. Requests now go one after the other; one with no answer is cancelled
  after 30 s (60 s for an article), and Reload gives up a stuck one at once.
- **RSS: the first list after start no longer waits for the account list.** The Worker now sends
  the account list with every list and feed answer, so the first answer after each app start
  refreshes it (an account added since shows up). The app asks for it separately only with
  nothing saved yet or after Settings. Needs the updated rss-opds Worker; with an older one
  the app asks after the first list.
- **RSS: load times on screen.** After each load the status line says how long the answer took
  and how much of it the Worker spent (`took 2.1 s, server 0.6 s`).
- **RSS: no more 7–8 s per page with Wi-Fi off in the settings.** The app asked the device to keep
  Wi-Fi up with a number in seconds, but the device counts milliseconds, so Wi-Fi went down right
  after every request and the next one waited for it to come back. RSS now keeps Wi-Fi up while
  it is used (5 minutes from the last tap) and lets it go when you leave the app.

## Update

Install the changed packages **over** the installed apps (SD card root → All Files → Install).
Do not uninstall first: that deletes the app's folder (settings, pages, dictionaries).

## Files

| file | content |
|---|---|
| `rss.xtapp`, `notes.xtapp` | **changed** |
| `dict.xtapp` | unchanged since v0.3.1 |
| `game2048.xtapp`, `sudoku.xtapp`, `sokoban.xtapp` | unchanged |
| `probe.xtapp`, `netprobe.xtapp` | developer tools, unchanged |
| `dict-wordnet-en.zip` | WordNet for Dictionary, unchanged (see v0.3.0) |

All packages are included so one release has everything. `SHA256SUMS.txt` has the checksums.

# v0.4.0

**RSS** gets a preview and an endless list, on the **Xteink X4 Pro** (stock XTOS Licorice, build **26102301**).

## New in RSS

- **Long-press an article** for a preview: the whole title, feed and date, and the feed's summary.
  **Prev / Next** in the box — or the side buttons, or a swipe — move to the previous / next
  article's preview; at the end of what is loaded, Next fetches the next page and shows its first
  article. **Open** reads it; **Close**, a tap outside the box or Back returns to the list on the
  screen of the article you were looking at. A preview fetches nothing else and marks nothing read.
- **The list keeps going**: Next, a side button or a swipe past the last article loads the next
  twelve and appends them, so the list simply continues; Prev scrolls back without reloading.
  The header shows where you are (`13-24 / 24+`, `+` = more on the server). Reload starts over.

## Worker

The summary in the preview comes from your [rss-opds](https://github.com/omer-faruq-xteink/rss-opds)
Worker. Update and redeploy it (`git pull`, `npx wrangler deploy`) to get summaries of up to 400
characters; an older Worker still works, with 120-character summaries.

## Update

Install the new `rss.xtapp` **over** the installed RSS app (SD card root → All Files → Install).
Do not uninstall first: that deletes its settings and cache.

## Files

| file | content |
|---|---|
| `rss.xtapp` | **changed** |
| `notes.xtapp`, `dict.xtapp` | unchanged since v0.3.1 |
| `game2048.xtapp`, `sudoku.xtapp`, `sokoban.xtapp` | unchanged |
| `probe.xtapp`, `netprobe.xtapp` | developer tools, unchanged |
| `dict-wordnet-en.zip` | WordNet for Dictionary, unchanged (see v0.3.0) |

All packages are included so one release has everything. `SHA256SUMS.txt` has the checksums.

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
