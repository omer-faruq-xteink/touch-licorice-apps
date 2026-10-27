# v0.11.0

Updates for the **Xteink X4 Pro** mini apps (stock XTOS Licorice, builds **26102301** and **26102401**).

## Changed

- **New: Tasks** — to-do lists: tick an item with a tap, add with the keyboard, **Clear done**
  removes the ticked ones (after asking); edit, move and delete items, several lists. One list can
  be the **lock screen**. Everything is kept in a plain text file you can also edit on a computer.
- **New: Weather** — the forecast from Open-Meteo (free, no key) for a place you search by name:
  the temperature now in large digits, the next 12 hours and four days, °C or °F. Kept between
  visits, and it can be the **lock screen**.
- **Wikipedia offline**: a pack of English Wikipedia's 10 000 vital articles (opening sections,
  `wikipedia-en-vital.zip`: 7 MB, 18 MB unzipped) reads without Wi-Fi; search by the start of a title,
  random article, read before. With a pack on the card the app opens on a list of sources
  (Online, and each pack). `wiki2pack.py` makes packs for any language or list of titles.
- **New: Klondike** — the classic solitaire, draw one or three, cards drawn like FreeCell's. Tap a
  card and then where it goes; Hint suggests a useful move, Finish sends everything home once
  nothing is hidden, Undo, numbered deals.
- **New: Calculator** — thumb-sized keys and exact decimal arithmetic (0.1 + 0.2 − 0.3 is 0, as on a
  desk calculator); a scientific mode with trigonometry in degrees or radians, logarithms,
  powers, roots, n!, pi and e, brackets and Ans. The last results stay above the display.
- **Anki now schedules with FSRS** (version 4.5), the scheduler Anki itself offers: every card
  keeps a stability and a difficulty learned from your answers, so it comes back just before you
  would forget it, with fewer reviews than before. Your progress carries over.

## Update

Install the changed packages **over** the installed apps (SD card root → All Files → Install).
Do not uninstall first: that deletes the app's folder (settings, pages, dictionaries, decks).

## Files

| file | content |
|---|---|
| `calculator.xtapp`, `klondike.xtapp`, `tasks.xtapp`, `weather.xtapp` | **new** |
| `anki.xtapp` | **updated**: FSRS scheduling |
| `wikipedia.xtapp` | **updated**: offline packs |
| `wikipedia-en-vital.zip` | **new**: the offline pack (unzip into `XTApps/wikipedia/files/`) |
| all other `.xtapp` packages, `apkg2cards.py` | unchanged since v0.10.0 |
| `dict-wordnet-en.zip` | WordNet for Dictionary, unchanged (see v0.3.0) |

All packages are included so one release has everything. `SHA256SUMS.txt` has the checksums.

# v0.10.0

Updates for the **Xteink X4 Pro** mini apps (stock XTOS Licorice, builds **26102301** and **26102401**).

## Changed

- **New: Chess puzzles** — 2400 tactics puzzles from the Lichess database (CC0) in six banks:
  mate in 1, mate in 2, and Easy to Expert by rating (800 to 2400). Tap a piece and its square;
  Hint frames the piece and then its square, Show makes the move. Themes after each puzzle,
  counts per bank.
- **New: Wikipedia** — search or a random article over Wi-Fi, as plain text paged like the RSS
  articles, in the language you choose (a list of common ones, or any Wikipedia's code). The
  last 30 articles read stay on the reader for offline reading. Long articles come in parts
  (Next past a part's last page loads the next one).
- **New: FreeCell** — the solitaire with Microsoft's numbered deals (1 to 32000). Tap a card and
  then where it goes; runs move as far as free cells and empty columns allow, safe cards go home
  by themselves. **Hint** shows a move of a winning line for deals 1 to 1000 (their solutions ship
  with the app) and offers the way back when you leave it. Undo, restart.
- **Mahjong** draws its dots with fewer commands, so even a crowded board stays well inside what
  the reader draws on one screen.
- **Anki on the lock screen**: long-press a deck and choose **Lock screen**; when the reader locks
  it shows one of the deck's next cards with its answer, a different one every 30 minutes.

## Update

Install the changed packages **over** the installed apps (SD card root → All Files → Install).
Do not uninstall first: that deletes the app's folder (settings, pages, dictionaries, decks).

## Files

| file | content |
|---|---|
| `chess.xtapp`, `freecell.xtapp`, `wikipedia.xtapp` | **new** |
| `anki.xtapp` | **updated**: lock screen |
| `mahjong.xtapp` | **updated**: lighter drawing |
| all other `.xtapp` packages, `apkg2cards.py` | unchanged since v0.9.0 |
| `dict-wordnet-en.zip` | WordNet for Dictionary, unchanged (see v0.3.0) |

All packages are included so one release has everything. `SHA256SUMS.txt` has the checksums.

# v0.9.0

Updates for the **Xteink X4 Pro** mini apps (stock XTOS Licorice, builds **26102301** and **26102401**).

## Changed

- **New: Anki** — flashcards with spaced repetition (Again / Hard / Good / Easy, scheduled like
  the KOReader Anki Viewer). Ships with **1438 English words (B2-C1)**, each with its meaning, an
  example sentence and similar words. Add and delete cards on the reader, undo a rating. Any Anki
  deck converts on a computer with `apkg2cards.py` (included) into small text files for
  `XTApps/anki/files/`; pictures and sounds are dropped, so even 200 MB decks shrink to a few
  hundred kilobytes, and `--update` keeps your progress when a deck changes.
- **Sudoku** moves to the newer API 2.9: digits in the bold large system font, solid grid lines
  (2 px, boxes 4 px) and a thick frame on the selected cell, for panels that show thin strokes
  faintly. The puzzle you were on should carry over; if not, the bank starts again at its first
  puzzle.

## Update

Install the changed packages **over** the installed apps (SD card root → All Files → Install).
Do not uninstall first: that deletes the app's folder (settings, pages, dictionaries).

## Files

| file | content |
|---|---|
| `anki.xtapp`, `apkg2cards.py` | **new**: the app and its deck converter (Python 3) |
| `sudoku.xtapp` | **updated**: API 2.9, bold digits, heavier lines |
| all other `.xtapp` packages | unchanged since v0.8.0 |
| `dict-wordnet-en.zip` | WordNet for Dictionary, unchanged (see v0.3.0) |

All packages are included so one release has everything. `SHA256SUMS.txt` has the checksums.

# v0.8.0

Updates for the **Xteink X4 Pro** mini apps (stock XTOS Licorice, builds **26102301** and **26102401**).

## Changed

- **New: Minesweeper** that never needs a guess: the mines go down after the first tap and a
  board is kept only if logic clears it. Easy 8x10, Normal 9x11 (default) and Hard 10x13, sized
  for finger taps; flags by long press or Flag mode, open around a finished number, Hint (safe
  cell, mine or wrong flag), Undo, best times.
- **New: Mahjong Solitaire.** 100 tiles in a 7x8 pyramid made for the portrait screen, drawn from
  above with stack heights as stepped edges and free tiles in bold frames. Every deal can be cleared, and Hint keeps pointing at
  a pair that leaves the board clearable; Shuffle and Undo when stuck.
- **Nonograms:** a long press marks one X however long the finger stays down (it used to
  switch back and forth).
- **App icons.** Every app now has its own icon in the Ink App grid instead of an empty frame.
  Install the packages over the installed apps to get them.

## Update

Install the changed packages **over** the installed apps (SD card root → All Files → Install).
Do not uninstall first: that deletes the app's folder (settings, pages, dictionaries).

## Files

| file | content |
|---|---|
| `minesweeper.xtapp`, `mahjong.xtapp` | **new** |
| `nonogram.xtapp` | **updated**: long press, icon |
| all app `.xtapp` packages | **updated**: icons only, the apps themselves are unchanged |
| `probe.xtapp`, `netprobe.xtapp` | unchanged since v0.7.0 |
| `dict-wordnet-en.zip` | WordNet for Dictionary, unchanged (see v0.3.0) |

All packages are included so one release has everything. `SHA256SUMS.txt` has the checksums.

# v0.7.0

Updates for the **Xteink X4 Pro** mini apps (stock XTOS Licorice, builds **26102301** and **26102401**).

## Changed

- **New: Suguru** (also called Tectonic). Regions of one to five cells each hold 1 to n, and
  touching cells, diagonals included, never hold the same number. 200 puzzles each of 5x5 easy,
  6x6 medium, 7x7 hard and 8x8 expert, generated for this app; like published Suguru, every one
  has a single solution reached by logic, without guessing, and each bank runs from easiest to
  hardest. Mistake marking, progress kept. Drawn with heavy region borders and bold digits so the grid
  stays readable on panels that show thin lines faintly.
- **New: Slide Puzzle.** The KOReader plugin's sliding-tile puzzle on the reader: 3x3 to 7x7, tap
  or swipe to slide, tiles already in place framed twice, moves and time, best time / fewest
  moves / games played per size, seven languages, saved after every move. GPL-3.0 like the plugin.
- **New: four puzzle games** on a shared toolkit (`tools/gamekit`), all tap-to-select /
  tap-to-target, nothing filled black, saved after every move:
  - **Lights Out**: 5x5, every puzzle solvable with the fewest presses as the target, Hint, Undo,
    three levels.
  - **Peg Solitaire**: the English 33-hole board and the 15-hole triangle, marked jumps, Undo, a
    rating and the best result per board.
  - **Nonograms**: 600 picture puzzles from 5x5 to 12x12, all solvable line by line (generated
    here), X marks, struck-through finished lines, half-done puzzles kept.
  - **Knight's Tour**: 6x6 and 8x8, marked jumps, a Warnsdorff hint, Undo, complete tours counted.
- **Sudoku: diabolical puzzles a person can solve.** All 2400 puzzles were checked: each has a
  single solution, and easy, medium and hard need only standard techniques. The diabolical bank
  held 320 puzzles rated 7.0 to 9.1 that need dynamic forcing chains, which come down to trial and
  error; they are replaced by puzzles from the same public-domain source rated 5.0 to 6.9.
  Diabolical still needs chains, but no guessing.
- **RSS and Instapaper: a steady preview box.** The long-press preview no longer grows and shrinks
  with the summary: it always has the same, tallest size, and the list's buttons and header are
  hidden while it is open.
- **Instapaper: no reading position lost.** Progress is still sent once per article, when you go
  back to the list. Leaving the app from inside an article, or a request that fails, used to lose
  it; now the position is kept on the card and sent at the next start, with the time it was read.

## Update

Install the changed packages **over** the installed apps (SD card root → All Files → Install).
Do not uninstall first: that deletes the app's folder (settings, pages, dictionaries).

## Files

| file | content |
|---|---|
| `suguru.xtapp`, `slidepuzzle.xtapp`, `lightsout.xtapp`, `pegsolitaire.xtapp`, `nonogram.xtapp`, `knightstour.xtapp` | **new** |
| `sudoku.xtapp` | **changed**: diabolical bank |
| `rss.xtapp`, `instapaper.xtapp` | **changed**: preview box; Instapaper also keeps unsent progress |
| all other `.xtapp` packages | unchanged since v0.6.0 |
| `dict-wordnet-en.zip` | WordNet for Dictionary, unchanged (see v0.3.0) |

All packages are included so one release has everything. `SHA256SUMS.txt` has the checksums.

# v0.6.0

Updates for the **Xteink X4 Pro** mini apps (stock XTOS Licorice, build **26102301**).

## Changed

- **New: Merchant.** The KOReader trading game on the reader: buy low and sell high across six
  trading posts in 30 days, with a moneylender, a bank, raiders and offers on the road; four
  settings (Silk Road caravan, star trader, clipper captain, antique dealer) and seven languages
  (Settings). Tap a good to trade; amounts by steps, Max or typed. Saved after every move, best
  score per theme. AGPL-3.0 like the plugin it comes from.
- **New: Instapaper.** Your Instapaper articles on the reader, straight from Instapaper with a
  personal access token (no Worker): **Unread**, **Starred**, **Archive** and your folders, with
  the RSS app's list, long-press preview and article screens. Articles open where you left off and
  send your progress back (so KOReader and the website continue there too); **Archive** and
  **Star** from the preview or the article's end, which also shows the link as a QR code. The token
  can be typed in Settings or written to `XTApps/instapaper/files/config.txt` over USB.
  **Images in articles** (Settings, off by default) shows the pictures as in RSS.
- **Docs**: the hidden drawer row is called **Ink App** (it was described as "Mini Apps"); install
  steps now name it right.

## Update

Install the changed packages **over** the installed apps (SD card root → All Files → Install).
Do not uninstall first: that deletes the app's folder (settings, pages, dictionaries).

## Files

| file | content |
|---|---|
| `instapaper.xtapp`, `merchant.xtapp` | **new** |
| all other `.xtapp` packages | unchanged since v0.5.0 |
| `dict-wordnet-en.zip` | WordNet for Dictionary, unchanged (see v0.3.0) |

All packages are included so one release has everything. `SHA256SUMS.txt` has the checksums.

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
- **RSS: Wi-Fi comes up as the app opens.** Right at start the app asks the Worker for the account
  list (so an account added since shows up); that small request also brings Wi-Fi up, which the
  first list needs anyway, so a list opened meanwhile only waits for the rest. The Worker also
  sends the account list with every list and feed answer, which keeps it current.
- **RSS: no more 7–8 s per page with Wi-Fi off in the settings.** The app asked the device to keep
  Wi-Fi up with a number in seconds, but the device counts milliseconds, so Wi-Fi went down right
  after every request and the next one waited for it to come back. RSS now keeps Wi-Fi up while
  it is used (5 minutes from the last tap) and lets it go when you leave the app.
- **RSS: the source as a QR code.** Every article ends with a rule, "Source:" and the article's
  link as a QR code (the firmware's own encoder), so it opens on a phone, with the address
  wrapped under it (up to three lines). If no QR can be made, only the address is shown; the
  article reads as before.
- **Notes: an eraser.** A new **Erase** tool cuts strokes where your finger passes (the rest of
  each stroke stays) and removes text it touches, so any earlier item can be removed, not only
  the last one. **Undo** brings back what the last erase took. The drawing tools moved under one
  **Tool** button (Draw S / M / L, Erase, Text S / M / L), so the toolbar has five roomy buttons;
  **Draw** now has three pen widths, shown on the lock screen too.

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
3. Once: **Settings → About → tap "Model" 10 times** quickly. **Ink App** appears in the drawer (≡).
4. **≡ → Ink App** → tap an app. The Home pad leaves it. State is saved on leave.

## Limits

- Games: taps and swipes, one text size. Notes / RSS: the three system fonts, 1-bit screen, no images yet.
- Packages are tied to the firmware's key; a future update may require a rebuild.

Credits: [kycube/x4pro-emu](https://github.com/kycube/x4pro-emu) for the firmware reverse engineering;
puzzles from the sudoku-exchange bank (public domain); Sokoban packs by David W. Skinner and
Aymeric du Peloux via sokobano.de. Source and build instructions are in the repository.
