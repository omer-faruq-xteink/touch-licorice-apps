# Xteink Licorice mini apps

Games and tools for the **Xteink X4 Pro** e-reader running its stock **XTOS Licorice** firmware,
written in Lua for the firmware's built-in mini-app host: **InkApps**, as Xteink calls them. No custom firmware, no flashing: you
copy a package to the SD card and install it from the reader's own file browser. Most of them are
also on Xteink's own app store ([xtapp-ai.xteink.cc](https://xtapp-ai.xteink.cc)), where updates
arrive by themselves. The [app site](https://omer-faruq-xteink.github.io/touch-licorice-apps/) lists
every app with its screenshots and, in Chrome or Edge on a computer, copies apps straight to the
reader's SD card in USB mode and shows which installed apps have an update. Its
[tools](https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/)
convert Anki decks, StarDict dictionaries, Twine / Ink stories and piano scores in the browser, has ready
[feed lists](https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/feeds/) for RSS and the
[Zork pack](https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/textadv/) for Text adventures, and walks through
the [Worker setup](https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/worker/) for RSS and Hacker News.

| app | what it is |
|---|---|
| **2048** | the sliding-tile game; swipe or side buttons, score and best kept |
| **Sudoku** | 9x9 puzzles, 2400 of them in four difficulties, mistake marking, progress kept |
| **Lights Out** | switch all the lights off on a 5x5 board; target, hint, undo, three levels |
| **Peg Solitaire** | jump pegs down to one, on the English 33-hole board or the 15-hole triangle |
| **Nonograms** | picture logic puzzles from 5x5 to 12x12, 600 of them, all solvable line by line |
| **Knight's Tour** | take a knight over every square of a 6x6 or 8x8 board; hint, undo |
| **Minesweeper** | never needs a guess: every board can be cleared by logic; 8x10, 9x11, 10x13; flags, hint, undo |
| **Chess** | a whole game against the reader at four levels (Beginner to Hard), or two players on one reader; moves marked, undo, hint, the game kept |
| **Checkers** | English checkers or Turkish draughts (Dama) against the reader at four levels, or two players on one reader; compulsory and longest captures, undo, hint, the game kept |
| **Backgammon** | backgammon (tavla) against the reader at four levels, or two players; single games or a match to 3, 5 or 7, gammons, an optional doubling cube; undo with the same dice, hint, the game kept |
| **Chess puzzles** | 2400 tactics puzzles from Lichess: mate in 1, mate in 2 and four levels by rating; hint, show the move |
| **Go problems** | 620 life-and-death problems (tsumego) in three levels, made and checked for the app, and your own SGF files; hint, retry |
| **Text adventures** | plays Z-machine story files (Zork, Infocom and Inform games) with tappable directions and words; Zork I built in, II and III free as a pack |
| **Word Hive** | a daily honeycomb of seven letters: make words with the middle letter, find the pangram, climb the ranks; hints, yesterday's answers |
| **Cryptogram** | a daily quote with every letter swapped for another: work out the code; hint, check, 471 quotes |
| **Word Ladder** | a daily ladder from one word to another, one letter at a time; par, hints, 730 ladders |
| **Hashi** | Bridges: join the numbered islands, no crossings; 600 puzzles in three levels |
| **Queens** | Queens and Star Battle: one queen (or two stars) in every row, column and region, none touching; dots for ruled-out cells; 1200 puzzles |
| **Case Files** | logic-grid mysteries: read the clues, cross and tick the grids, work out who had what; six settings, 600 cases in three levels |
| **Lamplighter** | turn the tiles until power from the source reaches every lamp: one network, no loose ends; lock mode; 600 puzzles in three sizes |
| **Kakuro** | Cross sums: runs that add up to their clues, no digit twice; the ways to make each run shown; 600 puzzles |
| **Delve** | a small roguelike: ten depths, a new dungeon every run or today's dungeon, one torch burning down, a dragon guarding the Amulet |
| **Tarot** | tarot cards as prompts for reflection, not fortune telling: a card a day and three-card readings with the 1909 Pamela Colman Smith deck |
| **Klondike** | the classic solitaire, draw one or three; hint, undo, Finish; numbered deals |
| **FreeCell** | the solitaire with Microsoft's numbered deals; Hint follows a winning line (deals 1-1000), undo, autoplay |
| **Mahjong** | Mahjong Solitaire: 100 tiles in a pyramid made for the portrait screen; every deal clearable; hint, shuffle, undo |
| **Slide Puzzle** | the classic sliding-tile puzzle, 3x3 to 7x7; tiles in place framed twice; best results per size |
| **Suguru** | also called Tectonic: fill each region with 1..n, touching cells never repeat; 800 puzzles from 5x5 to 8x8, all solvable by logic |
| **Sokoban** | 385 levels in five classic packs, undo, pack list, position kept per pack; add your own packs |
| **Merchant** | a turn-based trading game in four settings (caravan, star trader, clipper, antiques); seven languages |
| **Notes** | freehand drawing, typed text and QR codes on eight pages; one page becomes the lock screen (an ID card with a contact QR), with clock and battery |
| **RSS** | RSS and Atom feeds as text over Wi-Fi: fetched on the reader with no account, or your CommaFeed articles through the [rss-opds](https://github.com/omer-faruq-xteink/rss-opds) Worker; offline cache; portrait or landscape; optional AI questions about an article (off by default, your own key); needs firmware 2.18 |
| **Instapaper** | your Instapaper articles as text, straight from Instapaper with an access token; progress kept in sync, archive and star; optional AI questions about an article (off by default, your own key); portrait or landscape; needs firmware 2.18 |
| **wallabag** | your wallabag articles as text, from your own server or a hosted one; archive, star, tags, offline copies; optional AI questions about an article (off by default, your own key); portrait or landscape; needs firmware 2.18 |
| **Readwise** | your Readwise Reader documents and feed as text, straight from Reader; archive, Later and tags straight to Reader; optional AI questions about an article (off by default, your own key); portrait or landscape; needs firmware 2.18 |
| **Hacker News** | Top, New, Best, Ask and Show in HN's order, search, comments level by level; articles as text through the rss-opds Worker; portrait or landscape; optional AI questions about a story and its comments (off by default, your own key); needs firmware 2.18 |
| **Bookworm** | a little pet that lives on your reading time: it hatches, grows through four stages and a new generation, gets hungry when you stop, takes after how you read, and sleeps on the sleep screen; an ink octopus and a shelf dragon can join it |
| **Wikipedia** | search or a random article over Wi-Fi, in the language you choose; articles read are kept for offline reading |
| **Timekeeper** | timers, a focus timer (Pomodoro), a stopwatch with laps, an interval timer for exercise, counters and a log of focus time; whole minutes to save power, a flash when time is up; can be the lock screen |
| **Tasks** | to-do lists ticked off with a tap, items that repeat (chores every week, every 3 months), kept as a plain text file; your Todoist, Google Tasks and TickTick lists too (tick and add); a list can be the lock screen |
| **Notebook** | plain text notes written in blocks (Enter makes a new line; a long text goes on into the next block by itself), folders, tags, sorting and a search through all notes; kept as .txt files you can also edit on a computer |
| **Weather** | the forecast from Open-Meteo: now, the next hours and four days; can be the lock screen |
| **Calendar** | your Google (or any iCal) calendars in Day, Week, Month and Agenda views, and My calendar for events added on the reader (an .ics file); can be the lock screen |
| **TBR Planner** | plan your to-be-read books: wishlist, dates, a month calendar, progress from the reader; can be the lock screen |
| **Calculator** | exact decimal arithmetic and a scientific mode; its Mode button adds Graph, Table, Stats, Distributions, Solve, Matrix, Units, Base, Finance and Dates |
| **Anki** | flashcards with spaced repetition: a built-in English deck (B2-C1 words with examples), your own cards, Anki decks converted on a computer |
| **Dictionary** | offline StarDict lookup with the firmware keyboard; WordNet (English) ready-made, any StarDict after a one-time conversion; Word of the Day lock screen; My words (every word looked up) and Review with spaced repetition |
| **Literary Clock** | the time told by a sentence from a public-domain book, a new quote every minute; made for the lock screen |
| **Word Clock** | the time in words on a grid of letters, in English, Türkçe or Deutsch; made for the lock screen |
| **Sky Tonight** | the night sky over your city, computed on the reader: stars, constellations, moon phase, planets, sunset and sunrise; can be the lock screen |
| **Piano Follow** | sheet music in landscape that follows your playing on a Bluetooth MIDI keyboard: turns the pages, marks the bar, or waits for the right notes in Practice; a free catalog of 51 pieces and your own MusicXML / ABC scores; needs firmware with API 2.21 |
| **Gamebook** | choose-your-own-adventure stories: seven built in, a pack of more, and Twine, Ink or Project Aon stories converted on the tools site |
| **API Probe**, **Net Probe** | developer tools that exercise the Lua host and paint the results |

Everything here is unofficial and was reverse-engineered from the firmware. It worked on an X4
Pro running **XTOS Licorice build 26102301** (October 2026). Read "Caveats" before installing.

Two host APIs exist on this build. 2048, Sokoban and Suguru use the default **API 0.8** (taps,
swipes, one text size, no network). The other apps declare `"api": "2.0"` and get **API 2.9**: finger movement,
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

### Lights Out

A tap switches a square and its four neighbours; switch the whole 5x5 board off. Every puzzle is
solvable, with the fewest presses shown as the target; Hint frames a square of a best solution,
Undo, three levels. [More](apps/lightsout/README.md)

### Peg Solitaire

Tap a peg, then the hole to jump to; the jumped peg goes. The English 33-hole board and the
15-hole triangle, Undo, a rating at the end and the best result per board. [More](apps/pegsolitaire/README.md)

### Nonograms

Fill the cells so every row and column matches its clue. 150 puzzles each of 5x5, 8x8, 10x10 and
12x12 (larger would be too small to tap), every one solvable line by line; X marks by mode or long
press, finished lines struck through, Undo, half-done puzzles kept. [More](apps/nonogram/README.md)

### Knight's Tour

Visit every square of a 6x6 or 8x8 board once with a chess knight: the possible jumps are marked,
Hint follows Warnsdorff's rule, Undo, best result and complete tours per size. [More](apps/knightstour/README.md)

### Minesweeper

Boards that never need a guess: the mines go down after your first tap, and only a board that logic
clears from there is kept. Easy 8x10, Normal 9x11 and Hard 10x13 fit the screen with finger-sized
cells; long press or Flag mode for flags, open by tapping a finished number, Hint, Undo, best times.
[More](apps/minesweeper/README.md)

### Chess

A whole game against the reader at four levels (Beginner, Easy, Medium, Hard), or two players on
one reader. Tap a piece and its moves are marked; Undo takes back your move and the reply, Hint
frames a good move, and the game is kept when you leave. The reader thinks only on its own move,
a few seconds at most. [More](apps/chessplay/README.md)

### Checkers

English checkers (diagonal moves on the dark squares) or Turkish draughts, Dama (forward and sideways,
flying kings, the longest capture compulsory), against the reader at four levels or two players on one
reader. A capture goes the whole way in one tap; Undo, Hint and the game kept as in Chess.
[More](apps/checkers/README.md)

### Backgammon

Backgammon (tavla) against the reader at four levels (Hard looks one roll ahead) or two players on
one reader. Tap Roll, then a checker: the points it can reach are marked, combined moves too. Single
games or a match to 3, 5 or 7 points with gammons and backgammons; the doubling cube is optional (off,
it plays like tavla) with the Crawford rule. Undo takes back a checker or the whole turn with the same
dice, Hint frames a good play, the game is kept. [More](apps/backgammon/README.md)

### Chess puzzles

Find the best move: 2400 puzzles from the Lichess database (CC0) in six banks, from mate in 1 to
2000+ rated tactics. Tap a piece and its square; the reply comes at once. Hint frames the piece
and then its square, Show makes the move; themes and counts per bank. [More](apps/chess/README.md)

### Text adventures

Classic parser games on the reader: Zork, Infocom's other games and most Inform games (`.z3`, `.z5`,
`.z8` in `AppFiles/textadv/`). Directions and common commands are buttons, the game's own words from
its last reply are chips that build the command, the keyboard does the rest; saved after every turn.
Zork I is built in; Zork II and III (MIT licence since 2025, like Zork I) are a free pack on the
[tools site](https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/textadv/). [More](apps/textadv/README.md)

### Go problems

Life and death in the corner: find the move that kills the group or saves it. 620 problems in three
levels (one, two, three or more moves), made for the app and checked by a solver: exactly one first
move works, the other side answers with its strongest reply, a wrong move with its refutation.
Your own SGF problem files in `AppFiles/tsumego/` become collections too. [More](apps/tsumego/README.md)

### Word Hive

A new hive of seven letters every day: make words of four letters or more that use the middle
letter, find the pangram (all seven), climb the ranks to Queen bee. Hints counts the words still to
find by first letter and length; Yesterday shows the answers you missed. 730 puzzles from the
public-domain 12dicts word list. [More](apps/wordhive/README.md)

### Cryptogram

A quote a day with every letter swapped for another. Tap a letter, then the key it stands for;
every place it appears fills in. Hint, Check (strikes out wrong guesses), earlier days kept.
471 proverbs and public-domain quotes. [More](apps/cryptogram/README.md)

### Word Ladder

Change the start word into the target one letter at a time, every step a word (COLD, CORD, CARD,
WARD, WARM). A new ladder every day, four or five letters, with par, Undo and a Hint that finds the
next step from wherever you are. 730 ladders from the public-domain 12dicts lists. [More](apps/wordladder/README.md)

### Hashi

Bridges: join the numbered islands with one or two bridges each way, none crossing, all joined.
Tap the water between two islands. 600 puzzles (7x7, 9x9, 11x11), each with one solution reached
by reasoning. [More](apps/hashi/README.md)

### Queens

Queens (one queen a row, column and region) and Star Battle (two stars): no two pieces touch, not
even diagonally. Tap a cell for a cross, again for a piece; the cells your pieces rule out are
dotted, mistakes ringed; Undo and Hint. 1200 puzzles (Queens 6x6 to 9x9, Star Battle 9x9 and
10x10), each with one solution reached by reasoning. [More](apps/queens/README.md)

### Case Files

Logic-grid mysteries: at a hotel, on a night train, at a bake-off... each person has one item of
every group, and the clues settle who has what. Tap a cell for a cross, again for a tick; a grid
for each pair of groups, chosen by tabs; tap a clue to cross it out. Undo, Hint, Check. 600 cases
(Easy, Medium, Hard), each with one answer reached by reasoning. [More](apps/casefiles/README.md)

### Lamplighter

A wiring puzzle: turn the tiles until power from the source reaches every lamp, all the wires in
one network with no loose ends or loops. Tap a tile to turn it; lit wires are thick; Lock frames the
tiles you are sure of. Undo and Hint. 600 puzzles (5x5, 7x7, 9x9), each with one solution reached
by reasoning. [More](apps/lamplighter/README.md)

### Kakuro

Cross sums: fill the runs so they add up to their clues, no digit twice. The selected cell's runs
and every way to make them are shown under the grid; Hint fills a cell. 600 puzzles (6x6, 7x7,
8x8), each with one solution reached by reasoning. [More](apps/kakuro/README.md)

### Delve

A small roguelike: go down ten depths and take the Amulet from the dragon. Every run is a new
dungeon (or today's dungeon, the same for everyone); pixel-art tiles of 48 px, the view following
the hero. Tap near the hero to step that way, further away to walk there; tap a monster to see
what a fight costs. The torch burns down, potions and scrolls are unknown until tried, monsters
chase, wander, give up or flee in their own ways; death ends the run. [More](apps/delve/README.md)

### Tarot

A card a day (tap the face-down card; it stays until midnight, and a journal keeps the earlier
ones) and three-card readings (Situation, Obstacle, Way forward), with the pictures of Pamela Colman Smith's
1909 deck dithered for e-ink. The cards are prompts to think with, not predictions: every card has
an upright and a reversed meaning, written for the app; the Deck lists all 78. [More](apps/tarot/README.md)

### Klondike

The classic solitaire: turn the stock one or three cards at a time, tap a card and then where it
goes, Finish sends everything home once nothing is hidden. Hint suggests a useful move; Undo,
numbered deals. [More](apps/klondike/README.md)

### FreeCell

Microsoft's numbered deals: tap a card (with the cards above it, as far as free cells and empty
columns allow), then where it goes. Safe cards go home by themselves; Hint shows a move of a
winning line for deals 1 to 1000 (solutions ship with the app) and the way back to it when you
leave it. Cards are drawn: black suits solid, red suits hollow. [More](apps/freecell/README.md)

### Mahjong

Mahjong Solitaire on a 7x8 pyramid of 100 tiles, drawn from above with stack heights as stepped
edges. Every deal can be cleared, and Hint keeps pointing at a pair that leaves the board clearable;
Shuffle and Undo when you get stuck. [More](apps/mahjong/README.md)

### Slide Puzzle

Tap a tile next to the gap or swipe to slide it; tiles already in their final place get a
second frame. Boards from 3x3 to 7x7, each with its own saved puzzle, best time, fewest moves and games
played; seven languages. Ported from the KOReader plugin slidepuzzle.koplugin. [More](apps/slidepuzzle/README.md)

### Suguru

Also called Tectonic. Regions of one to five cells (thick borders) each hold 1 to n; touching
cells, diagonals included, never hold the same number. Tap a cell, then a number; **Erase**, **Chk**,
**Next** and **Bank** work as in Sudoku. 200 generated puzzles each of 5x5 easy, 6x6 medium, 7x7 hard
and 8x8 expert, every one with a single solution that logic reaches without guessing, easiest
first. Drawn with heavy lines and bold digits for faint panels. [More](apps/suguru/README.md)

### Sokoban

Swipe, or tap the board on the side of the player you want to go; side buttons move up / down and,
after a solve, the lower one goes to the next level. **Undo** takes a move back, **Reset** asks,
**Prev / Next** change level, **Set** opens the pack list. Shipped packs: Microban, Sasquatch, LOMA,
Microcosmos, Minicosmos. Any XSB / `.sok` pack you have can be added with one command.
[More](apps/sokoban/README.md)

### Notes

**Draw** with a finger; **Text** places typed text where you tap, using the firmware's own keyboard
(small / medium / large); **QR code** places a code a phone camera can scan, holding a link, a
phone number, Wi-Fi details or a contact card. **Undo**, **Page** (eight pages), **Clear**.
**Lock** makes the current page the device's lock screen — the firmware asks once — with or
without the time and battery level (with them it is redrawn every minute): your name and a
contact-card QR code on a page make the lock screen an ID card. Pages live in the app's storage.
[More](apps/notes/README.md)

### RSS

Feeds on the reader, with no account: **Add feed** takes a site, a feed or an OPML address, or
offers [feed lists](https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/feeds/) by topic;
OPML files copied into `AppFiles/rss/` become collections. Or your [CommaFeed](https://www.commafeed.com)
account: **Unread**, **Starred**, **All**, by **Feed** and by **Tag**. Articles open inside the app, laid out with the system fonts (headings, quotes,
lists), optionally as full text extracted by the Worker; opening one marks it read. The long-press preview
stars an article, marks it unread and edits its tags. Lists and read
articles are cached for offline use. CommaFeed, and full text for feeds on the reader, need the free
[rss-opds](https://github.com/omer-faruq-xteink/rss-opds) Cloudflare Worker: the [Worker setup](https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/worker/) walks through it and works out what to enter in the
app's Settings. [More](apps/rss/README.md)

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

### wallabag

Your [wallabag](https://wallabag.org) account on the reader, from your own server or a hosted
one: **Unread**, **Starred**, **Archive** and your **Tags**, with the same list, preview and
article screens as Instapaper; **Archive** and **Star** from the preview or the article's end.
Sign in once with an API client's ID and secret and your username and password (OAuth: then
refresh tokens). Articles open where you left off on the reader. [More](apps/wallabag/README.md)

### Readwise

Your [Readwise Reader](https://readwise.io/read) library on the reader: **Inbox**, **Later**,
**Shortlist**, **Archive**, **Feed** and your **Tags**, with the same list, preview and article
screens as Instapaper. Reading needs only a Reader access token: the app talks to Reader directly.
**Archive**, **Later** / **Inbox**, editing **tags** and marking a document seen go straight to
Reader with the same token; Settings can turn the app to landscape. Needs firmware with API 2.18
(XT Licorice 26110201 or later).
[More](apps/readwise/README.md).

### Hacker News

Top, New, Best, Ask and Show in HN's own order, and search. A story opens with its text (Ask HN) or
the linked article as text through your rss-opds Worker (the one RSS uses), and ends with its
address as a QR code. Comments come level by level, loaded while you read; tap "replies" to go
down a level. Read-only: no login. The Worker needs no CommaFeed account for this, only a full-text
service: [Worker setup](https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/worker/), [more](apps/hackernews/README.md).

### Bookworm

A little bookworm that lives on your reading, from the reader's own reading statistics (nothing
leaves the reader). Ten minutes of reading hatch its egg; it grows to an elder with a scholar's cap
as the hours add up, and at 100 hours leaves an egg for the next generation. It gets hungry on days
without a book, takes after how you read (night owl, marathon reader, butterfly...) and what you read (a candle
for a horror fan, a magnifier for mysteries, a wizard's hat for fantasy...), talks about
the book it is eating, keeps a diary and awards, and sleeps on the sleep screen dreaming of your
book. An ink octopus and a shelf dragon can join it, one awake at a time, each with its own
drawings and voice. [More](apps/bookworm/README.md)

### Wikipedia

Search or open a random article; it comes as plain text in the language you choose (English,
Türkçe, Deutsch, ... or any Wikipedia's code) and is paged like an RSS article. The last 30
articles stay on the reader for reading without Wi-Fi. Offline: the release's pack of English
Wikipedia's 10 000 vital articles (opening sections), or one made with `wiki2pack.py`; the app then
opens on a list of sources. [More](apps/wikipedia/README.md)

### Notebook

Plain text notes, written in blocks of up to 512 characters (the docked keyboard's limit): Enter
makes a new line, Save and Cancel sit above it, and a long text goes on into a new block by itself. Folders and tags, filtered from the list; sorted by last edited, title or
date; Search looks through every note and shows the line it found. Each note is a `.txt` file in
`AppFiles/notebook/`, readable and writable on a computer. [More](apps/notebook/README.md)

### Timekeeper

Timers (up to six, named), a focus timer (Pomodoro) that logs your focus time, a stopwatch with
laps, an interval timer for exercise and tally counters, with the time of day on top. Everything
keeps running when you leave the app. Light on power: running timers show whole minutes, a tap
on the digits the seconds. The reader has no sound, so an end flashes the screen, the reader can
stay awake while something runs, and the lock screen shows what runs and blinks when time is up.
[More](apps/timekeeper/README.md)

### Tasks

To-do lists: tap the box to tick an item, Add with the firmware keyboard, Clear done to remove the
ticked ones; edit, move and delete items, several lists. **Repeat** makes an item come back when it
is due again (every day, week, 2 weeks, month, or any number of days, weeks or months, counted
from the day you ticked it), with "late 2 days" or the next date under it. One list can be the lock
screen. Kept in
`XTApps/tasks/files/lists.txt`, plain text you can also edit on a computer. **Todoist**, **Google
Tasks** and **TickTick** lists can show after yours (Sources): tick, untick and add items on the reader, the rest in
their own apps; changes wait while there is no Wi-Fi. [More](apps/tasks/README.md)

### Weather

The forecast from [Open-Meteo](https://open-meteo.com) (free, no key) for a place found by name:
now, the next 12 hours and four days, in °C or °F. The forecast is kept, so it opens at once; it
can be the lock screen. [More](apps/weather/README.md)

### Calendar

Your Google Calendar, or any calendar with an iCal address, read-only: Day (a timeline), Week,
Month and Agenda, with each event's time, place and notes a tap away. Add a calendar with its
secret iCal address, on the reader or as a `calendars.txt` over USB. It syncs over Wi-Fi and
works offline. **+** adds an event to My calendar, kept on the reader as
`AppFiles/calendar/My calendar.ics`, editable, repeating if you like, and readable by any calendar
program. It can be the lock screen in any of the four views; Day then runs from the current
hour on. A port of calendar.koplugin (AGPL v3). [More](apps/calendar/README.md)

### TBR Planner

Your to-be-read list: a Wishlist, Planned books with start and end dates (−7 / −1 / +1 / +7
buttons, Keep duration), a month Calendar and a Done list. Add a book from the reader's own list
(every book opened once: its progress and reading time follow, and it moves to Done when you
finish it) or by its title. The daily reading goal gives an end date from your pace so far. The
lock screen shows today's books. A port of tbrplanner.koplugin (GPL v3). [More](apps/tbr/README.md)

### Calculator

Thumb-sized keys, the expression typed as on paper, and exact decimal arithmetic: 0.1 + 0.2 − 0.3
is 0. Sci adds trigonometry in degrees or radians, logarithms, powers, roots, n!, pi and e,
brackets and Ans, and a 2nd page (10^x, e^x, n-th roots, abs, round, mod, nPr, nCr, gcd, lcm,
variables A–F, results as fractions). The Mode button lists Basic, Sci and what a graphing calculator adds: Graph
(Y1–Y4, zoom, trace, zeros, minimum and maximum, intersections, dy/dx, integrals) and its Table,
Stats (lists, 1-Var, LinReg, QuadReg, ExpReg, a scatter plot), Distributions (normal, t, chi²,
binomial, Poisson, geometric), Solve, Matrix (up to 4 × 4), and Units, Base (hex/bin, bit
operations), Finance (TVM, a loan schedule, percent) and Dates. Each mode is a file of its own,
loaded only when opened, so Basic and Sci stay as quick as before. [More](apps/calculator/README.md)

### Anki

Flashcards with spaced repetition (Again / Hard / Good / Easy, scheduled with FSRS, as in
Anki). Ships with 1438 English words (B2-C1) with example sentences; add and delete your own
cards on the reader. Any Anki deck (`.apkg`, e.g. from [AnkiWeb's shared decks](https://ankiweb.net/shared/decks))
converts into small text files for the app's folder on the
[tools site](https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/anki/) or with
`apps/anki/apkg2cards.py`: only the text is kept, so even large decks fit. Arabic, Persian and
Hebrew decks convert on the tools site, which draws the right-to-left text as pictures (the
reader cannot lay it out). [More](apps/anki/README.md)

### Dictionary

Type with the firmware keyboard, pick a suggestion, read the entry; several dictionaries side by
side. Dictionaries are StarDict files converted once on a computer into text shards and copied
over USB into `XTApps/dict/files/` on the SD card — the release ships **WordNet** (English–English)
converted; anything else converts on the
[tools site](https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/dictionary/) or with
`apps/dict/stardict2shards.py`. It can be the lock screen: a
Word of the Day with its senses and examples, a new one each day. Never uninstall the app (the
folder goes with it); install updates over it. [More](apps/dict/README.md)

### Literary Clock

Every minute a sentence from a novel that names that moment ("At five minutes to ten he went down
to the station"), the time phrase in bold, then the book and its author; the digital time and date
under it (can be switched off). 566 quotes from 1,400 public-domain novels on Project Gutenberg,
mostly detective stories; a minute with no quote of its own keeps the nearest earlier one.
**Another** shows the minute's other quotes. Best as the lock screen. [More](apps/litclock/README.md)

### Word Clock

The time in words on a grid of letters, the words of the time as black blocks with white letters
and four dots for the minutes between: "IT IS HALF PAST TEN", "SAAT ONU YİRMİ GEÇİYOR",
"ES IST FÜNF VOR HALB ELF". The language follows the system's and has a button. Best as the lock
screen. [More](apps/wordclock/README.md)

### Sky Tonight

A round chart of the sky over your city as you see it looking up: stars to magnitude 4.5, the
constellation figures and names, the moon in its phase, the planets. Under it the moon's phase and
rise and set, sunset, dark and sunrise, and the planets that are up. At night it opens on now, by
day on tonight; **-1 h** / **+1 h** step through the night. 76 cities or typed coordinates;
English, Türkçe, Deutsch. Everything is computed on the reader (no network) and checked against
the 2026 eclipses, planet oppositions and NOAA's sunrise times. It can be the lock screen,
redrawn every 15 minutes. [More](apps/skytonight/README.md)

### Gamebook

Choose-your-own-adventure stories: read a page, pick one of the choices under it. Seven stories are
built in (six of ours and inkle's *The Intercept*); the story pack on the site has three more. More
are `.story` files copied into `AppFiles/gamebook/`: the
[tools site](https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/gamebook/) converts stories made with Twine (Harlowe, SugarCube) or Ink, yours or the many
shared online, and Project Aon's free gamebooks such as Lone Wolf (their EPUB). Undo, three text sizes, progress kept per story. The
`.story` format is plain text and easy to write by hand: [FORMAT.md](apps/gamebook/FORMAT.md).
[More](apps/gamebook/README.md)

### Piano Follow

Sheet music on the reader, in landscape on the music stand, that follows your playing. Pieces come
from a free catalog read straight from this repository (51 public-domain and CC0 pieces from
[PDMX](https://zenodo.org/records/15571083), mostly beginner and easy plus well-known classics), or
from your own MusicXML or ABC files through the
[score converter](https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/piano/). With a
Bluetooth MIDI keyboard (remembered and found again by itself) **Page turn** turns each page on its
last note, back to the start of a written repeat; **Follow** also draws a dashed line under the
bar you are playing; **Practice** (right hand, left hand or both) waits for the right notes and
lists the bars with mistakes. Without a keyboard it is a plain score reader. Needs firmware with
API 2.21 (26110501 or later). [More](apps/pianofollow/README.md)

## Tools site

`site/` is a static site published to GitHub Pages by `.github/workflows/pages.yml`
(`python -I tools/build_site.py` builds it into `dist/site`, with the story pack). Its converters
are JavaScript ports of `apkg2cards.py` and `stardict2shards.py` that give the same files
(`python -I site/test/test_converters.py`), plus the Gamebook converter, the piano score converter (Verovio; `cd tools/piano && npm test`, which
also builds the Piano Follow catalog) and the Worker setup guide. A
new tool is a folder under `site/tools/` and a line in `site/assets/site.js`.

## Build from source

Requirements: Python 3.10+ and one package.

```bash
pip install cryptography
python build_all.py
```

Every app lands in `dist/` as `<name>.xtapp`. A single app: `python xtpack.py apps/sudoku`.
An app's `icon.png` (96x96, black on white) becomes its icon in the Ink App grid; `python -I
tools/make_icons.py` redraws them all.

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
python -I apps/slidepuzzle/test_slidepuzzle.py
python -I apps/lightsout/test_lightsout.py
python -I apps/pegsolitaire/test_pegsolitaire.py
python -I apps/nonogram/test_nonogram.py
python -I apps/knightstour/test_knightstour.py
python -I apps/minesweeper/test_minesweeper.py
python -I apps/mahjong/test_mahjong.py
python -I apps/anki/test_anki.py
python -I apps/freecell/test_freecell.py
python -I apps/chess/test_chess.py
python -I apps/tsumego/test_tsumego.py
python -I apps/textadv/test_textadv.py
python -I apps/wordhive/test_wordhive.py
python -I apps/cryptogram/test_cryptogram.py
python -I apps/wordladder/test_wordladder.py
python -I apps/hashi/test_hashi.py
python -I apps/kakuro/test_kakuro.py
python -I apps/queens/test_queens.py
python -I apps/casefiles/test_casefiles.py
python -I apps/lamplighter/test_lamplighter.py
python -I apps/timekeeper/test_timekeeper.py
python -I apps/delve/test_delve.py
python -I apps/tarot/test_tarot.py
python -I apps/wikipedia/test_wikipedia.py
python -I apps/calculator/test_calculator.py
python -I apps/calculator/test_modes.py
python -I apps/klondike/test_klondike.py
python -I apps/notes/test_notes.py
python -I apps/rss/test_feeds.py
python -I apps/rss/test_rss.py
python -I apps/rss/test_rss_local.py
python -I apps/instapaper/test_instapaper.py
python -I apps/merchant/test_merchant.py
python -I apps/dict/test_dict.py
python -I apps/litclock/test_litclock.py
python -I apps/wordclock/test_wordclock.py
python -I apps/skytonight/test_sky.py
python -I apps/gamebook/test_gamebook.py
python -I apps/pianofollow/test_pianofollow.py
python -I tools/piano/test_sim.py
python -I site/test/test_converters.py
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
- **Network.** Only the apps that read something online use it, and each talks only to the
  service it names or you enter: RSS and Hacker News to your Worker, Instapaper to
  www.instapaper.com, wallabag to your server, Readwise to readwise.io, Calendar to your calendars' addresses, Weather to
  Open-Meteo, Wikipedia to Wikipedia; article pictures come through images.weserv.nl. Nothing
  else leaves the device. Notes needs no permission at all.
- Other Xteink models (X4, X4 Classic, X3) are untested.

## Releases

Each release attaches the `dist/*.xtapp` files and names the Licorice build they were tested on.
To make one: `python build_all.py`, tag, upload `dist/`.

The store builds come from `python -I tools/store_export.py APP` (an XTApp Studio project backup
under `dist/store/APP/`); what is on the store and in which version is tracked in
[store/STATUS.md](store/STATUS.md).

## Credits

Built on the reverse engineering in [kycube/x4pro-emu](https://github.com/kycube/x4pro-emu) (MIT),
whose `xtapp.py` is vendored here. Puzzle and level sources are listed in [NOTICE.md](NOTICE.md).
Games were first written for the CPR-vCodex custom firmware and ported to the stock host.

License: MIT (see `LICENSE`); third-party content as in `NOTICE.md`.
