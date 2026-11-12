# v0.23.0

Updates for the **Xteink X4 Pro** mini apps (stock XTOS Licorice). Tested on build **26110501**. Instapaper, wallabag, RSS, Hacker News and Readwise need **26110201** or later (API 2.18).

## Changed

- **Readwise 1.2.1: books, PDFs and long articles, read in parts.** Opening a long document could close the app with an error, and an EPUB bigger than 128 KB showed "bad json": Reader sends an EPUB or a PDF as one piece of HTML, often megabytes, more than the reader keeps of an answer, and turning a long one into pages took longer than the reader allows. Now Reader's answer is saved to a file (`AppFiles/readwise/doc_<id>.json`, kept for the 5 documents opened last) and read a part of a few dozen pages at a time: **Next** on a part's last page, or its **Next part** button, opens the next part, **Prev** on the first page the end of the one before, and the app opens again at the part and page you left. A PDF that Reader has no text for shows its summary.
- **Instapaper 1.2.1, wallabag 1.3.1, RSS 1.3.1, Hacker News 1.2.1: long articles no longer close the app.** Turning a long article (or a long comment thread) into pages could take longer than the reader allows for one step, and the reader then closed the app with an error. Each app now asks the reader for more time before that work, as Readwise 1.2.1 does.

## Files

| file | content |
|---|---|
| `readwise.xtapp` | Readwise 1.2.1 |
| `instapaper.xtapp` | Instapaper 1.2.1 |
| `wallabag.xtapp` | wallabag 1.3.1 |
| `rss.xtapp` | RSS 1.3.1 |
| `hackernews.xtapp` | Hacker News 1.2.1 |
| all other packages | unchanged since v0.22.0 |

All packages are included so one release has everything. `SHA256SUMS.txt` has the checksums.

# v0.22.0

Updates for the **Xteink X4 Pro** mini apps (stock XTOS Licorice). Tested on build **26110501**. Instapaper, wallabag, RSS, Hacker News and Readwise need **26110201** or later (API 2.18).

## Changed

- **Calculator 1.1.0: a graphing calculator's tools.** The button at the top right is now **Mode**, named after the mode you are in; its list has Basic and Sci, then ten modes: **Graph** (Y1–Y4 as lines, thick lines or dashes; Window, Zoom, Trace; Calc finds a value, zeros, minimum, maximum, intersections, dy/dx and integrals from the formula), **Table**, **Stats** (lists L1 and L2; 1-Var with quartiles; LinReg, QuadReg, ExpReg; a scatter plot with the fit), **Distributions** (normal, t, chi², binomial, Poisson, geometric; tails computed as tails), **Solve** (Left = Right, every solution in a range), **Matrix** (up to 4 × 4: det, inverse, transpose, rref, +, −, ×), and beyond a graphing calculator **Units** (eleven kinds, every unit at once), **Base** (hex, decimal, octal, binary; bit operations on 32 bits), **Finance** (TVM, a loan schedule, percent) and **Dates** (days between dates, weekday, ISO week, a date plus or minus days). Sci has a **2nd** page: 10^x, e^x, x³, cube and n-th roots, abs, int, round, mod, nPr, nCr, gcd, lcm, rand, EE, variables A–F (Sto, Var) and **Frac** (the result as a fraction). Every mode asks for its numbers on the calculator's own keys. Each mode is a file of its own, loaded only when it is opened, so Basic and Sci open and answer as quickly as before; a key now takes one screen refresh instead of two (the finger going down no longer draws a frame). Back on the calculator lets the reader ask whether to leave the app.
- **Tasks 1.2.0: Todoist, Google Tasks and TickTick.** Your Todoist and TickTick projects and Google Tasks lists can show after your own lists, each marked with its service (**Sources**): tick, untick and add items on the reader, the rest in their own apps. A change is sent a moment later (several go together) and waits while there is no Wi-Fi; **Sync** (and opening the app) fetches every list again. Sub-items are drawn further in, dates show as "due today" or "late 2 days", Todoist's repeating tasks come back with their next date, and any of these lists can be the lock screen. Several accounts of one service (personal and work) each get a file of their own and are marked on their lists ("Google (work)"); one that fails does not stop the others. Todoist needs your API token (typed in, or in `todoist.txt`); Google Tasks a one-time sign-in on a computer (your own OAuth client and a refresh token in `google.txt`; the README has the steps), since Google does not let a device without a browser sign in to Tasks. TickTick needs an app of your own at developer.ticktick.com and a sign-in code (`ticktick.txt`), which the reader trades for a token; its token lasts months. The services' code is a file of its own, loaded only once one is set up. Also: more lists or items than fit on a screen get **Prev** and **Next** buttons (a swipe still turns the page, and no longer opens the list under the finger when there is no page to go to), Back on the list of lists lets the reader ask whether to leave the app, and a tap draws one frame.

## Files

| file | content |
|---|---|
| `calculator.xtapp` | Calculator 1.1.0 |
| `tasks.xtapp` | Tasks 1.2.0 |
| all other packages | unchanged since v0.21.0 |

All packages are included so one release has everything. `SHA256SUMS.txt` has the checksums.

# v0.21.0

Updates for the **Xteink X4 Pro** mini apps (stock XTOS Licorice). Tested on build **26110501**. Instapaper, wallabag, RSS, Hacker News and Readwise need **26110201** or later (API 2.18).

## Added

- **New: Timekeeper** (`timekeeper.xtapp`): timers (up to six, named, set by steps or typed), a focus timer (Pomodoro: focus and breaks in turn, logged by day), a stopwatch with laps, an interval timer for exercise, tally counters (a large +1, the side buttons count too) and a log of the week's focus, with the time of day on top. Everything keeps running when you leave the app. Light on power: running timers show whole minutes and the app wakes only when they change; a tap on the digits shows the seconds. The reader has no sound, so when time is up the screen flashes, the reader stays awake while something runs (firmware 26110201), and the lock screen shows what runs and blinks slowly for three minutes after an end.

## Changed

- **Bookworm 1.1.0: company.** Under Family, an **ink octopus** and a **shelf dragon** can share the reader with the bookworm, one awake at a time: the octopus's egg comes with the first hatching, the dragon's with the first finished book. Tap one to hatch or wake it and the one awake goes to sleep; a sleeping one does not eat, grow or get hungry. Each has its own drawings at every stage, its own voice for everything it says (a dreamy octopus scribbler, a dragon who hoards books), its own names and its own generations, on the app and on the sleep screen. Also: "an elder bookworm" (it said "a elder").
- **Calendar 1.1.2: addresses that move.** A calendar address that answers with a redirect is now followed (up to three moves; the reader does not follow them itself), as iCloud's published calendars can: before, it said "not an iCal address". The help explains Apple's Public Calendar link and lists Apple's holiday calendars (`https://calendars.icloud.com/holidays/tr_tr.ics`).
- **RSS 1.3.0: optional AI questions.** Entirely optional and **off by default**: while it is off, nothing of it shows and nothing is sent to any AI service. Switched on in **Settings → AI** with your own key, from a list of services (Claude, OpenAI, Gemini, OpenRouter, Groq, Mistral, DeepSeek, Ollama on your network) or **Other** for any OpenAI-compatible address; **Extra parameters** (JSON) go into every request, e.g. to turn a model's thinking down; a long key can come in an `ai.txt` file over USB, which the app takes in and deletes, an article gets one **AI** button: ready questions (Summarize, Key points, Explain simply, Background, What is missing?, Translate) or your own, answers laid out and paged like the article, and follow-up questions with **Ask**. Also: Back on the first menu now lets the reader ask whether to leave the app.
- **Hacker News 1.2.0: optional AI questions.** The same as in RSS, also **off by default** and invisible while off (each app keeps its own settings; neither needs the other). With AI on, a story and its comments get an **AI** button, and **Send** chooses what goes with the questions: **Article + comments**, **Article**, **Comments** or **Link + comments**. The comments are fetched at once (up to 600) and given with their replies under them; with comments there are two more ready questions, **The discussion** and **Disagreements**. Also: Back on the story list lets the reader ask whether to leave the app, and Settings takes three columns in landscape.
- **Instapaper 1.2.0, Readwise 1.2.0, wallabag 1.3.0: optional AI questions.** The same as in RSS: **off by default** and invisible while off; switched on in **Settings → AI**, an open article gets an **AI** button with the ready questions, your own question and follow-ups. Each app keeps its own settings and none needs another installed (the AI part is built into every package). Also: Back on the first menu lets the reader ask whether to leave the app.
- **In all five apps with AI: web search and your own buttons.** A **Web search** switch at the top of the ready questions: while it is on, every question searches the web first, ready ones and your own, follow-ups too; it is off again for each new article (Claude, OpenAI, Gemini and OpenRouter search themselves; for DeepSeek the model writes a short search query from the whole article, the conversation and the question, then the app runs DeepSeek's search with it; that request begins like the answer's, so the article comes from DeepSeek's cache the second time). The conversation's buttons are now Back, Prev, Next and More (your own question is under More). **My buttons** in Settings → AI holds up to six questions of your own, shown after the ready ones, kept in `ai_buttons.txt` in the app's folder (editable over USB). DeepSeek's starting model is now `deepseek-flash`. A new answer opens at its question.
- **Dictionary 1.0.0: My words and Review.** Every word you look up is kept (up to 500) with how often you looked it up; **My words** lists them, opens an entry again, removes one (its x, tapped twice) or all (**Clear history**). **Review** brings them back as cards (the word, then its entry) on FSRS, the schedule Anki uses: Again, Hard, Good or Easy, each showing when the word comes back; up to 10 new words a day. Also: Back on the search screen lets the reader ask whether to leave the app.

## Files

| file | content |
|---|---|
| `timekeeper.xtapp` | new: Timekeeper |
| `bookworm.xtapp` | Bookworm 1.1.0: an ink octopus and a shelf dragon join the bookworm |
| `calendar.xtapp` | Calendar 1.1.2: redirects followed (iCloud published calendars) |
| `rss.xtapp` | RSS 1.3.0: optional AI questions about an article (off by default) |
| `hackernews.xtapp` | Hacker News 1.2.0: optional AI questions about a story and its comments (off by default) |
| `instapaper.xtapp` | Instapaper 1.2.0: optional AI questions about an article (off by default) |
| `readwise.xtapp` | Readwise 1.2.0: optional AI questions about an article (off by default) |
| `wallabag.xtapp` | wallabag 1.3.0: optional AI questions about an article (off by default) |
| `dict.xtapp` | Dictionary 1.0.0: My words (every word looked up) and Review with spaced repetition |
| all other packages | unchanged since v0.20.0 |

All packages are included so one release has everything. `SHA256SUMS.txt` has the checksums.

# v0.20.0

Updates for the **Xteink X4 Pro** mini apps (stock XTOS Licorice, builds **26102301**, **26102401**, **26102801** (beta), **26102901** and **26110201**). Instapaper, wallabag, RSS, Hacker News and Readwise now need **26110201** or later (API 2.18).

## Added

- **New: Case Files** (`casefiles.xtapp`): logic-grid mysteries. Each person in a case has one item of every group (a floor, an arrival time, a lost item...) and the clues settle who has what: tap the grids for a cross or a tick, one grid for each pair of groups, and tap a clue to cross it out. A tick dots the rest of its row and column; Undo, Hint and Check. Six settings, 600 cases in three levels (3 groups of 4 people up to 4 groups of 5), each with one answer reached by reasoning.
- **New: Lamplighter** (`lamplighter.xtapp`): a wiring puzzle. Tap a tile to turn it until power from the source reaches every lamp: all the wires joined in one network, no loose ends, no loops, nothing running off the board. Lit wires are drawn thick; Lock frames the tiles you are sure of so a stray tap cannot turn them; Undo and Hint. 600 puzzles (5x5, 7x7, 9x9), each with one solution reached by reasoning.
- **New: Notebook** (`notebook.xtapp`): plain text notes written in blocks of up to 512 characters (the docked keyboard's limit). Tap a block to edit it with the keyboard docked at the bottom: Enter makes a new line, Save and Cancel are at the top, a blank line splits it, an empty one is deleted. Writing on past 500 characters goes on in a new block by itself, the keyboard staying open. Folders and tags filter the list, which sorts by last edited, title or date; Search looks through every note and shows the line it found (Turkish letters too). Each note is a `.txt` file in `AppFiles/notebook/`, readable and writable on a computer.

## Changed

- **Calendar 1.1.1: a calendar without a calendar file.** With no iCal address added, the app now opens on its views (Day, Week, Month, Agenda) instead of a page of instructions, with a short hint at the bottom; + adds events to My calendar on the reader as before. Back on the main view now lets the reader offer to exit.

## Files

| file | content |
|---|---|
| `casefiles.xtapp` | new: Case Files |
| `lamplighter.xtapp` | new: Lamplighter |
| `notebook.xtapp` | new: Notebook |
| `calendar.xtapp` | Calendar 1.1.1: the views without a calendar file; Back |
| all other packages | unchanged since v0.19.0 |

All packages are included so one release has everything. `SHA256SUMS.txt` has the checksums.

# v0.19.0

Updates for the **Xteink X4 Pro** mini apps (stock XTOS Licorice, builds **26102301**, **26102401**, **26102801** (beta), **26102901** and **26110201**). Instapaper, wallabag, RSS, Hacker News and Readwise now need **26110201** or later (API 2.18).

## Added

- **New: Backgammon** (`backgammon.xtapp`): backgammon (tavla) against the reader at four levels (Beginner, Easy, Medium, Hard; Hard looks one roll ahead), or two players on one reader. Tap Roll, then a checker: the points it can reach are marked, combined moves too; a checker on the bar is picked by itself. Single games or a match to 3, 5 or 7 points, gammons and backgammons, and an optional doubling cube (off, it plays like Turkish tavla) with the Crawford rule. Undo takes back a checker or the whole turn, with the same dice again; Hint frames a good play; the game is kept when you leave.

## Changed

- **Anki 1.1.0: Arabic, Persian, Urdu and Hebrew decks.** The reader cannot lay out right-to-left text, so the [Anki converter](https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/anki/) on the tools site now draws it as pictures (letters joined, vowel marks placed), and Anki shows them, on the lock screen too: for example AnkiWeb's *Qur'anic Vocabulary: all word forms, translations & examples* (15,346 words in order of frequency, about 10 MB on the card). `apkg2cards.py` points such decks to the tools site. For Arabic with vowel marks (Quran decks) the converter can also put the **pronunciation** on the first line of the back (*allâhi*, *wash-shamsi*), worked out by rules from the marks. Back now closes a box, leaves a study session for the deck list, and on the deck list lets the reader offer to exit.
- **Sky Tonight 1.0.1: no more "App error, closed" at start.** On some readers the first frame (five font sizes, 900 stars) took longer than the 1.5 seconds the reader gives a frame, and the reader closed the app. Sky Tonight now asks for more time, and an error at start is shown on the screen instead of closing the app. The place can also be set on a computer in `settings.txt` in the app's folder (`place=`, `lat=`, `lon=`); a file saved with Windows line endings is now read correctly.

## Files

| file | content |
|---|---|
| `backgammon.xtapp` | new: Backgammon |
| `anki.xtapp` | Anki 1.1.0: right-to-left decks as pictures; Back |
| `apkg2cards.py` | warns about right-to-left decks |
| `skytonight.xtapp` | Sky Tonight 1.0.1: no longer closes at start on slower first frames; reads a settings.txt edited on Windows |
| all other packages | unchanged since v0.18.0 |

All packages are included so one release has everything. `SHA256SUMS.txt` has the checksums.

# v0.18.0

Updates for the **Xteink X4 Pro** mini apps (stock XTOS Licorice, builds **26102301**, **26102401**, **26102801** (beta), **26102901** and **26110201**). Instapaper, wallabag, RSS, Hacker News and Readwise now need **26110201** or later (API 2.18).

## Added

- **New: Chess** (`chessplay.xtapp`): a whole game against the reader at four levels (Beginner, Easy, Medium, Hard), or two players on one reader. Tap a piece and its moves are marked; a pawn on the last rank asks what it becomes. Undo takes back your move and the reply, Hint frames a good move, New game picks the opponent and your side (playing Black turns the board). Checkmate, stalemate and the draws (repetition, 50 moves, too little material) end the game; the last moves show in chess notation, and the game is kept when you leave. The reader thinks only on its own move: under a second on Easy, about 3.5 s on Medium, 8 s on Hard (four moves ahead).
- **New: Checkers** (`checkers.xtapp`): English checkers or Turkish draughts (Dama), against the reader at four levels or two players on one reader. Tap a piece and its moves are marked; a capture goes the whole way in one tap. Captures are compulsory (in Dama the longest line must be taken, kings fly and may not turn back); Undo, Hint, playing either side, and the game kept when you leave. As in Chess, the reader thinks only on its own move.
- **New: Queens** (`queens.xtapp`): Queens and Star Battle. Place one queen (or two stars) in every row, every column and every region, none touching, not even diagonally. Tap a cell for a cross, again for a piece; with Dots on, the cells your pieces rule out get a dot. Touching pieces and too many in a row are ringed; Undo, Hint, your place kept. Queens 6x6 to 9x9 and Star Battle 9x9 and 10x10, 200 puzzles each, every one with one solution reached by reasoning (our own generator); regions drawn with thick borders, as the panel has no colours.
- **New: Bookworm** (`bookworm.xtapp`): a little pet that lives on your reading. It uses the reader's reading statistics (minutes per day, the books, your streak; nothing leaves the reader): ten minutes of reading hatch its egg, it grows from hatchling to elder as the hours add up and at 100 hours leaves an egg for the next generation. Days without reading make it hungry, then it hides in a book; its character follows how you read (night owl, marathon reader, butterfly...), and its taste what you read: from authors and titles it guesses horror, mystery, fantasy and so on, and dresses and talks to match. It talks about the book it is eating, keeps a diary of the last two weeks, earns awards, and sleeps on the sleep screen dreaming of your book.
- **New: the app site** ([omer-faruq-xteink.github.io/touch-licorice-apps](https://omer-faruq-xteink.github.io/touch-licorice-apps/)): every app with its screenshots, search and categories, and a page of its own to share. In Chrome or Edge on a computer, connect the reader in USB mode and choose its SD card: the site copies apps there (install them from All Files) and shows which installed apps have an update. The packages are those of the latest release. The tools moved to [/tools/](https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/). **Community apps** by other developers appear at the bottom, found daily from GitHub repos with the topic `licorice-ink-app` and an `inkapp.json`; they are only linked, never copied or checked ([add your app](https://omer-faruq-xteink.github.io/touch-licorice-apps/developers/)).

## Changed

- **Gamebook 1.0.1**: the QR code on its help screen (More stories) now opens the story tools (the story pack and the Twine, Ink and Project Aon converters) instead of the site's home page, which is now the app list.
- **Notes 0.3.1**: a lock-screen page without the clock now refreshes once an hour instead of every minute. Turning the refresh off is not possible, so it asks for the longest interval the firmware allows; before, its request was refused and the page kept refreshing every minute.

## Files

| file | content |
|---|---|
| `chessplay.xtapp` | **new**: Chess |
| `checkers.xtapp` | **new**: Checkers (and Dama) |
| `bookworm.xtapp` | **new**: Bookworm |
| `queens.xtapp` | **new**: Queens and Star Battle |
| `gamebook.xtapp` | Gamebook 1.0.1: help QR code opens the story tools |
| `notes.xtapp` | Notes 0.3.1: a lock screen without the clock refreshes hourly |
| all other packages | unchanged since v0.17.0 |

All packages are included so one release has everything. `SHA256SUMS.txt` has the checksums.


# v0.17.0

Updates for the **Xteink X4 Pro** mini apps (stock XTOS Licorice, builds **26102301**, **26102401**, **26102801** (beta), **26102901** and **26110201**). Instapaper, wallabag, RSS, Hacker News and Readwise now need **26110201** or later (API 2.18).

## Added

- **Delve** (new, `delve.xtapp`): a small roguelike. Go down ten depths of rooms, corridors and monsters and take the Amulet from the dragon on the last; every run is a new dungeon, and **Today's dungeon** is the same for everyone on a day. Pixel-art pictures at 48 px a tile, the view following the hero; a tap near the hero steps that way (no need to hit the tile), a tap further away walks there and stops when a monster comes into view. The torch burns down a point a turn and with it your light; potions and scrolls are unknown until tried; monsters wander, give up the chase or run off when hurt, each in its own way, and a tap on one shows what a fight would cost. Death ends the run; the run in progress is saved and continued.

## Changed

- **Instapaper, wallabag, RSS and Hacker News: landscape; they now need firmware with API 2.18** (XT Licorice 26110201 or later; older firmware refuses to install them and asks for an update). Settings has **Screen** (portrait or landscape). In landscape a list page holds 6 articles and the server (for RSS, your Worker) is asked for 6 at a time; Hacker News shows 4 stories a page. The menu and Settings take two columns, titles and articles use the wider lines, and an open article keeps its place when the app turns. Short settings (text size, pictures, screen) sit two to a row in portrait, so Settings fits the screen in RSS, Hacker News and wallabag. Pictures in articles are never taller than a page, here and in Readwise (0.3.1). wallabag sends Archive and Star as a real PATCH now, so they work with servers that do not take a POST in its place.

- **Readwise 0.3.0: needs firmware with API 2.18, no Worker**: the reader can now send PATCH, so **Archive**, **Later** / **Inbox**, **tags** and marking a document seen go straight to Readwise with your access token; the Worker fields are gone from Settings. Firmware older than XT Licorice 26110201 refuses to install it and asks for an update. **Landscape**: Settings has **Screen** (portrait or landscape); in landscape a list page holds 6 rows and Reader is asked for 6 at a time, the menu and Settings take two columns, and articles and titles use the wider lines.

- **Tasks: items that repeat**: an item's menu has **Repeat**: every day, week, 2 weeks, month, or any number of days, weeks or months (Other: "3 days", "6 months"). Tick it when done: it keeps the day and comes back un-ticked when it is due again, counted from that day, so chores like watering plants or changing a filter keep coming round. Under it: "next Thu 5 Nov" while ticked, "due today" or "late 2 days" while open. **Clear done** leaves repeating items; on the lock screen a repeating item appears again on its day. In `lists.txt` it is a tail you can also write by hand: `[x] Water plants {every 4 days, done 2026-11-01}`.

## Update

Install the changed packages **over** the installed apps (SD card root → All Files → Install).
Do not uninstall first: that deletes the app's folder (settings, pages, dictionaries, decks).

## Files

| file | content |
|---|---|
| `delve.xtapp` | **new**: Delve |
| `instapaper.xtapp` | Instapaper 0.3.0: landscape; needs firmware 2.18 |
| `wallabag.xtapp` | wallabag 1.2.0: landscape, a real PATCH; needs firmware 2.18 |
| `rss.xtapp` | RSS 1.2.0: landscape; needs firmware 2.18 |
| `hackernews.xtapp` | Hacker News 1.1.0: landscape; needs firmware 2.18 |
| `readwise.xtapp` | Readwise 0.3.1: changes straight to Readwise, landscape; needs firmware 2.18 |
| `tasks.xtapp` | Tasks 1.1.0: items that repeat |
| all other `.xtapp` packages, `apkg2cards.py`, `gamebook-stories.zip`, `zork-pack.zip` | unchanged since v0.16.0 |
| `dict-wordnet-en.zip` | WordNet for Dictionary, unchanged (see v0.3.0) |
| `wikipedia-en-vital.zip` | the offline Wikipedia pack, unchanged (see v0.11.0) |

All packages are included so one release has everything. `SHA256SUMS.txt` has the checksums.


# v0.16.0

Updates for the **Xteink X4 Pro** mini apps (stock XTOS Licorice, builds **26102301**, **26102401**, **26102801** (beta) and **26102901**).

## Added

- **Text adventures** (new, `textadv.xtapp`): plays classic text adventures, Z-machine story files (Zork, Infocom's other games, most Inform games: `.z3`, `.z5`, `.z8`) copied into `AppFiles/textadv/`. Little typing: the eight directions, Up, Down, In, Out, Look, Inventory and Wait are buttons; the game's own words from its last reply and common verbs are chips that build the command; the keyboard does the rest. The game is saved after every turn and continues where you left it; the game's own SAVE and RESTORE keep one more save. Zork I is built in; Zork II and III, released by Microsoft under the MIT licence like Zork I, are a free pack (`zork-pack.zip`, also on the [tools site](https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/textadv/)). The interpreter passes the CZECH and Praxix test programs.

- **Go problems** (new, `tsumego.xtapp`): life-and-death problems (tsumego) in the corner, 620 of them in three levels: Easy (one move kills or lives), Medium (two moves) and Hard (three or more). They were made for this app and checked by a solver, so each has exactly one first move that works; the other side answers with its strongest reply, and Why shows the reply that refutes a wrong first move. Hint marks the point (twice plays it), Retry sets the problem up again, progress is kept. Your own SGF problem files copied into `AppFiles/tsumego/` become collections too (RIGHT / Correct marks are understood).

- **Word Hive** (new, `wordhive.xtapp`): a daily word puzzle. Seven letters in a honeycomb; make words of four letters or more that use the middle letter (letters may repeat). A four-letter word scores 1, a longer one a point a letter, a pangram (all seven letters, one in every hive) 7 more; the ranks go from Beginner to Queen bee. Hints counts the words still to find by first letter and length and by their first two letters; Yesterday shows the answers you found and missed; earlier days can be played and keep their words. 730 puzzles of 20 to 50 answers, built from Alan Beale's public-domain 12dicts list of common words with their plurals and verb forms.

- **Cryptogram** (new, `cryptogram.xtapp`): a quote a day with every letter swapped for another. Tap a letter of the puzzle (every place it appears is framed, with how often it appears), then the key it stands for; the next open letter is chosen. Hint shows a letter, Check strikes out wrong guesses, Erase clears one; the author is part of the puzzle. Earlier days keep their guesses. 471 proverbs and public-domain quotes (Shakespeare, Austen, Twain, Wilde, Franklin and others); How to play lists the classic tips.

- **Word Ladder** (new, `wordladder.xtapp`): change the start word into the target one letter at a time, every step a word. Tap a letter of the newest word, then the new letter; letters already in their target place are underlined. Par is the shortest ladder; Undo takes back a step; Hint adds the next word of a shortest ladder from wherever you are. A new ladder every day (four letters, five on every third day), earlier days kept; 730 ladders from the public-domain 12dicts lists.

- **Hashi** (new, `hashi.xtapp`): Bridges. Join the numbered islands with one or two bridges each way, straight, never crossing, all joined. Tap the water between two islands (one, two, none), or two islands in line; full islands get a second ring, overfull ones a cross. Undo, Restart, levels Easy 7x7, Medium 9x9, Hard 11x11, 200 puzzles each, every one with one solution reached by reasoning (made by our own generator).

- **Kakuro** (new, `kakuro.xtapp`): cross sums. Fill the white cells so each run adds up to its clue, no digit twice. The selected cell's runs and every way to make them are shown under the grid ("Across 16 in 2: 79"); repeated digits and wrong full runs are crossed; Hint fills a cell. Easy 6x6, Medium 7x7, Hard 8x8, 200 puzzles each, every one solved by reasoning about the runs alone (our own generator).

- **Tarot** (new, `tarot.xtapp`): tarot cards as prompts for reflection, not fortune telling, with the pictures of Pamela Colman Smith's 1909 deck (public domain), dithered for e-ink. **Today**: tap the face-down card for the day's card; it stays until midnight, and **Journal** keeps the earlier days. **Reading**: three cards, Situation, Obstacle and Way forward; tap a card to read it. **Deck**: all 78 cards by suit with both meanings; the side buttons step through them. Every card has an upright and a reversed meaning, written for the app; reversed draws can be switched off. The pictures use the reader's image decoding, as RSS pictures do; without it the cards show as framed names.
## Changed

- **RSS: feeds on the reader**: RSS now reads feeds by itself, with no account and no Worker. **Add feed** takes a site (the app finds its feed), a feed or an OPML address, or offers feeds by topic from the new [Feed lists](https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/feeds/) page. Feeds go into the collection you add them from (**My feeds**, `AppFiles/rss/My feeds.opml`, is always there); any other OPML file copied into `AppFiles/rss/` becomes a collection of its own. A collection opens on its feeds, in the folders its OPML has (hundreds of feeds are fine); tap a feed for its articles, long-press it to remove it. Long-press an article for a preview; opening it marks it read, on the reader. A feed is fetched when you open it, with gzip and "not modified" answers; one over the reader's 128 KB limit is read in pieces where its server allows it. With a Worker set, feeds of any size come through it, and **Full text** fetches whole articles for feeds that carry only a summary (Full text without a Worker shows a QR code to the setup page). CommaFeed and your collections sit side by side in the menu. The [Worker setup](https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/worker/) page has a "feeds on the reader (full text only)" choice that needs no CommaFeed account. Needs the updated rss-opds Worker for large feeds through the Worker.

- **Calendar: My calendar on the reader** (1.1.0): **+** (right of the date) adds an event without any account or Wi-Fi: title, date, start or all day, length, repeat (every day, week, month or year), place and notes. Tap one of its events to **Edit** or **Delete** it (a repeating one: this one or all). The events are an ordinary iCalendar file, `AppFiles/calendar/My calendar.ics` on the SD card, written after every change: import it into any calendar program, or edit it elsewhere (the app reads it again at every start). My calendar shows with your Google calendars, on the lock screen too, and is never synced; uninstalling the app leaves the file on the card.

- **2048, Sokoban and Suguru on the store's API**: these three were the last packages on the reader's older API; they now declare API 2.2, the same as their store versions, so the GitHub and store copies run the same way. This also brings back Sokoban's 385 levels in five packs and Suguru's 800 puzzles: installed from the `.xtapp` files, v0.15.0 showed only the few built into the code ("built-in bank (no data section)"), because the packs are read the way the newer API names them. The store versions were not affected.

## Update

Install the changed packages **over** the installed apps (SD card root → All Files → Install).
Do not uninstall first: that deletes the app's folder (settings, pages, dictionaries, decks).

## Files

| file | content |
|---|---|
| `wordhive.xtapp` | **new**: Word Hive |
| `cryptogram.xtapp` | **new**: Cryptogram |
| `wordladder.xtapp` | **new**: Word Ladder |
| `hashi.xtapp` | **new**: Hashi |
| `kakuro.xtapp` | **new**: Kakuro |
| `tarot.xtapp` | **new**: Tarot |
| `tsumego.xtapp` | **new**: Go problems |
| `textadv.xtapp` + `zork-pack.zip` | **new**: Text adventures, and Zork I-III to copy into `AppFiles/textadv/` |
| `rss.xtapp` | changed: feeds on the reader, OPML collections, full text through the Worker |
| `calendar.xtapp` | changed: My calendar, events added on the reader (`AppFiles/calendar/My calendar.ics`) |
| `game2048.xtapp`, `sokoban.xtapp`, `suguru.xtapp` | changed: API 2.2 as in the store; Sokoban's and Suguru's packs load again |
| all other `.xtapp` packages, `apkg2cards.py`, `gamebook-stories.zip` | unchanged since v0.15.0 |
| `dict-wordnet-en.zip` | WordNet for Dictionary, unchanged (see v0.3.0) |
| `wikipedia-en-vital.zip` | the offline Wikipedia pack, unchanged (see v0.11.0) |

All packages are included so one release has everything. `SHA256SUMS.txt` has the checksums.


# v0.15.0

Updates for the **Xteink X4 Pro** mini apps (stock XTOS Licorice, builds **26102301**, **26102401** and **26102801** (beta)).

## Changed

- **New: Gamebook** (`gamebook.xtapp`) — choose-your-own-adventure stories: read a page, pick one of the choices under it. Seven stories are built in: six of ours, from a lighthouse in a storm to a market where you pay with memories, and inkle's *The Intercept*. The **story pack** (`gamebook-stories.zip`) adds three more: *The Dragon's Riddles*, *The Orchard Ghost* and *Courier to Kepler Station*. More are `.story` files copied into `AppFiles/gamebook/`. Undo, three text sizes, progress kept per story. The `.story` format is plain text (`apps/gamebook/FORMAT.md`), and stories made with Twine or Ink, and Project Aon gamebooks such as Lone Wolf, convert on the tools site.
- **New: the tools site** ([omer-faruq-xteink.github.io/touch-licorice-apps/tools](https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/)) — converters that run in the browser, with nothing to install and nothing uploaded: **Anki decks** (`.apkg`, `.tsv`, `.csv`; the same files as `apkg2cards.py`, including updates that keep your progress), **StarDict dictionaries** for Dictionary (the same files as `stardict2shards.py`; archives such as `.zip`, `.tar.gz` and `.tar.zst` open directly), **Gamebook stories** from Twine (Harlowe, SugarCube) and Ink, and Project Aon's gamebooks such as Lone Wolf from their EPUB (the Random Number Table built in), with a list of where to find stories, and a step-by-step **Worker setup** for RSS, Hacker News and Readwise (each on its own needs only what it uses: no CommaFeed account for Hacker News or Readwise) that works out what to type in each app.
- **New: Sky Tonight** (`skytonight.xtapp`) — the night sky over your city, worked out on the reader with no network: a round chart of the sky looking up (stars to magnitude 4.5, constellation figures and names, the moon in its phase, the planets), the moon's phase and rise and set, sunset, dark and sunrise, and the planets that are up. By day it shows tonight; **-1 h** / **+1 h** step through the night. 76 cities or typed coordinates; English, Türkçe, Deutsch. Works as the lock screen (every 15 minutes, with the next new and full moon). Checked against the 2026 eclipses, planet oppositions and NOAA's sunrise times.
- **New: Word Clock** (`wordclock.xtapp`) — the time in words on a grid of letters, in English ("IT IS HALF PAST TEN"), Türkçe ("SAAT ONU YİRMİ GEÇİYOR", "SAAT ONA ÇEYREK VAR", "SAAT YARIM") or Deutsch ("ES IST FÜNF VOR HALB ELF"): the words of the time as black blocks with white letters, four dots for the minutes between the five-minute steps. The language follows the system's and has a button; best as the lock screen, which wakes on every minute.
- **New: Literary Clock** (`litclock.xtapp`) — the time told by a sentence from a public-domain book: every minute a quote that names the time, the time phrase in bold, then the book and author; the digital time and date under it (can be turned off). Best as the lock screen, which wakes on every minute; **Another** shows another quote of the same minute. 566 quotes from 1,400 public-domain novels (Project Gutenberg texts, authors who died before 1956), mostly detective stories; 450 minutes have their own quote, the others show the nearest earlier one with the exact time below it.
- **New: Readwise** (`readwise.xtapp`) — your [Readwise Reader](https://readwise.io/read) library as text: Inbox, Later, Shortlist, Archive, Feed and Tags, the list, preview and article screens of Instapaper, offline copies, and the page you reached kept on the card. Reading needs only a Reader access token. **Archive**, **Later** / **Inbox**, **tags** and marking documents seen go through the rss-opds Worker with the same user and password as RSS (the reader cannot send PATCH, the only way Reader changes a document); update the Worker for its new `/readwise` relay. Without the Worker the app only reads.
- **Notes: QR codes**: a new **QR code** row in the Tool list. Tap where it goes and type a link, a phone number, Wi-Fi details or a contact card (`MECARD:N:Surname,Name;TEL:…;;`); a 180 px code is placed there and saved with the page. Erase and Undo work on it, and the lock screen shows it too: write your name with Text, add a contact-card code, **Lock** the page, and the lock screen is an ID card a phone can scan.
- **Hacker News**: the list is easier to read: a story's points / comments line follows its title right away (no gap after a one-line title) and a thicker rule separates stories. The status line ("Loading stories…", errors) is now under the buttons; above them it ran into the last story.
- **Ready for the official XTApp API (2.17)**: the apps now call `ctx:invalidate()` as the API defines it (all games and Calculator, TBR, Anki, Wikipedia, Hacker News, Notes); Calendar, Notes and Tasks ask for up to 256 characters in their keyboard fields (the official default is 64, too short for a calendar address); Calendar frees memory with `ctx.gc:collect()` and unpacks gzip with `ctx.zlib:decompress()` only, and draws its white event boxes only when the reader can decode images. Nothing changes in use.
- **Store builds**: `tools/store_export.py` turns an app into an XTApp Studio project backup for the Xteink store (Studio → ⋯ → Import backup): the official 2.x manifest, an 88 px icon and a 512 px store icon. Code only the sideloaded packages keep (Calendar's and Weather's lock screens fetching on their own) sits between `-- store: cut` and `-- store: end` and is left out of store builds.
- **More apps ready for the store**: Hacker News, Instapaper, Readwise, RSS, TBR Planner, wallabag and Wikipedia use the official API calls too: keyboard fields take up to 256 characters (tokens, server addresses), pictures are decoded only when the reader can decode images, and Instapaper and wallabag read the time from `ctx.clock:now()`. **Wikipedia** now finds offline packs in the app's user folder (`ctx.files`, read 64 KB at a time) as well as where they were before, and with no pack its start screen shows that folder's path.
- **Dictionary**: **Word of the Day** picks a different word again: on the reader it always showed the first word of the dictionary ("aalii"), because the reader's numbers are 32-bit and the pick's arithmetic overflowed. A long definition's "..." no longer runs into the dictionary's name at the bottom. Dictionary and **Anki** also find copied dictionaries and decks in the app's user folder (`ctx.files`), as the store versions will need; Anki's built-in deck ships as declared data files.
- **Menus and dialog boxes are opaque**: in the games and the apps built on the shared kit (Anki, Calendar, Chess puzzles, FreeCell, Hacker News, Klondike, Knight's Tour, Lights Out, Mahjong, Minesweeper, Nonograms, Peg Solitaire, Tasks, TBR Planner, Weather, Wikipedia) a box such as a menu or a "New game?" question now has a white background, so the page under it no longer shows through and mixes with its buttons.
- **Games ready for the store**: **2048**, **Sokoban** and **Suguru** take the canvas from `on_draw` and understand the official touch events (pointer with a phase) as well as the reader's own, ask for a full refresh with `ctx:invalidate("full")` and measure text with the font; 2048 seeds its tiles from `ctx.clock`. **Sudoku**, **Sokoban** and **Suguru** read their puzzles only through `ctx.package`. **Merchant** draws a plain `-` where it had an em dash, which the system's small font cannot draw (it showed a box). Nothing else changes in play.

## Update

Install the changed packages **over** the installed apps (SD card root → All Files → Install).
Do not uninstall first: that deletes the app's folder (settings, pages, dictionaries, decks).

## Files

| file | content |
|---|---|
| `gamebook.xtapp` | new: Gamebook |
| `gamebook-stories.zip` | the Gamebook story pack: three more stories to copy into `AppFiles/gamebook/` |
| `readwise.xtapp` | new: Readwise Reader |
| `skytonight.xtapp` | new: Sky Tonight |
| `litclock.xtapp` | new: Literary Clock |
| `wordclock.xtapp` | new: Word Clock |
| `notes.xtapp` | changed: QR codes on a page (and on the lock screen) |
| `hackernews.xtapp` | changed: clearer list, status line under the buttons, opaque boxes |
| `dict.xtapp` | changed: Word of the Day picks a different word each day again; reads the user folder |
| `game2048.xtapp`, `merchant.xtapp`, `slidepuzzle.xtapp`, `sokoban.xtapp`, `sudoku.xtapp`, `suguru.xtapp` | changed: official API calls for the store (Merchant: a plain dash for the em dash) |
| `anki.xtapp`, `calculator.xtapp`, `calendar.xtapp`, `chess.xtapp`, `freecell.xtapp`, `klondike.xtapp`, `knightstour.xtapp`, `lightsout.xtapp`, `mahjong.xtapp`, `minesweeper.xtapp`, `nonogram.xtapp`, `pegsolitaire.xtapp`, `tasks.xtapp`, `tbr.xtapp`, `weather.xtapp`, `wikipedia.xtapp` | changed: menus and dialog boxes are opaque; official API calls; Wikipedia and Anki also read files from the app's user folder |
| `instapaper.xtapp`, `readwise.xtapp`, `rss.xtapp`, `wallabag.xtapp` | changed: official API calls (no change in use) |
| all other `.xtapp` packages, `apkg2cards.py` | unchanged since v0.14.0 |
| `dict-wordnet-en.zip` | WordNet for Dictionary, unchanged (see v0.3.0) |
| `wikipedia-en-vital.zip` | the offline Wikipedia pack, unchanged (see v0.11.0) |

All packages are included so one release has everything. `SHA256SUMS.txt` has the checksums.


# v0.14.0

Updates for the **Xteink X4 Pro** mini apps (stock XTOS Licorice, builds **26102301** and **26102401**).

## Changed

- **New: wallabag** (`wallabag.xtapp`) — your [wallabag](https://wallabag.org) articles as text, from your own server or a hosted one: Unread, Starred, Archive and Tags, the list, preview and article screens of Instapaper, Archive and Star, offline copies. Sign in once with an API client's ID and secret plus your username and password.
- **RSS** (`rss.xtapp`): **Star**, **Mark unread** / **Mark read** and **Tags** in the long-press preview, which also shows the article's tags; a new **Tags** menu lists your CommaFeed tags and each tag's articles. Back from a feed's or tag's articles returns to that list. Needs the updated rss-opds Worker; editing tags needs the Worker signed in with the CommaFeed username and password.
- **Every keyboard field now opens with its current text**: the apps filled the editor through an option the firmware ignores, so editing a setting, a task, a calendar address, RSS tags and so on started from an empty box. Fixed in Anki, Calendar, FreeCell, Hacker News, Instapaper, Klondike, Merchant, RSS, Tasks, TBR Planner, wallabag and Wikipedia (Notes and Weather open an empty box on purpose and only follow along).

## Update

Install the changed packages **over** the installed apps (SD card root → All Files → Install).
Do not uninstall first: that deletes the app's folder (settings, pages, dictionaries, decks).

## Files

| file | content |
|---|---|
| `wallabag.xtapp` | new: wallabag |
| `rss.xtapp` | changed: star, read / unread, tags; keyboard fields filled |
| `anki.xtapp`, `calendar.xtapp`, `freecell.xtapp`, `hackernews.xtapp`, `instapaper.xtapp`, `klondike.xtapp`, `merchant.xtapp`, `notes.xtapp`, `tasks.xtapp`, `tbr.xtapp`, `weather.xtapp`, `wikipedia.xtapp` | changed: keyboard fields open with their current text |
| all other `.xtapp` packages, `apkg2cards.py` | unchanged since v0.13.0 |
| `dict-wordnet-en.zip` | WordNet for Dictionary, unchanged (see v0.3.0) |
| `wikipedia-en-vital.zip` | the offline Wikipedia pack, unchanged (see v0.11.0) |

All packages are included so one release has everything. `SHA256SUMS.txt` has the checksums.


# v0.13.0

Updates for the **Xteink X4 Pro** mini apps (stock XTOS Licorice, builds **26102301** and **26102401**).

## Changed

- **New: TBR Planner** (`tbr.xtapp`) — plan your to-be-read books: Wishlist, Planned with start and end dates, a month Calendar and Done. Add books from the reader's list (progress and reading time follow, finished books move to Done) or by title; an end date from the book's total pages at your pages a day (or your pace on this reader); the lock screen shows today's books. A port of tbrplanner.koplugin (GPL v3).
- **Calendar** (`calendar.xtapp`): the event box now has a white background, so the view behind it no longer shows through. The **Today** button is wider and shows the whole word; the arrows beside it are narrower.
- **RSS** (`rss.xtapp`) and **Instapaper** (`instapaper.xtapp`): saved articles no longer pile up. The 100 most recently opened stay, older copies are removed, and Instapaper drops an archived article's copy. **Articles saved offline** in Settings shows the count; tap it twice to delete them all.
- **Dictionary** (`dict.xtapp`): new **Word of the Day** lock screen, one word a day with its senses, examples and synonyms. The **dict n/m** box at the top right is now **Settings**: pick the dictionary for lookups, turn the lock screen on or off, choose the dictionary its word comes from and how often a new word comes (every day, 12, 6, 3 hours or every hour).

## Update

Install the changed packages **over** the installed apps (SD card root → All Files → Install).
Do not uninstall first: that deletes the app's folder (settings, pages, dictionaries, decks).

## Files

| file | content |
|---|---|
| `tbr.xtapp` | new: TBR Planner |
| `calendar.xtapp`, `dict.xtapp`, `rss.xtapp`, `instapaper.xtapp` | updated (see above) |
| all other `.xtapp` packages, `apkg2cards.py` | unchanged since v0.12.0 |
| `dict-wordnet-en.zip` | WordNet for Dictionary, unchanged (see v0.3.0) |
| `wikipedia-en-vital.zip` | the offline Wikipedia pack, unchanged (see v0.11.0) |

All packages are included so one release has everything. `SHA256SUMS.txt` has the checksums.

# v0.12.0

Updates for the **Xteink X4 Pro** mini apps (stock XTOS Licorice, builds **26102301** and **26102401**).

## Changed

- **New: Calendar** — your Google Calendar (or any calendar with an iCal address), read-only, in
  Day, Week, Month and Agenda views. A port of calendar.koplugin, laid out for the X4 Pro. Add
  calendars with their secret iCal address in Settings, or as a `calendars.txt` over USB. It
  syncs over Wi-Fi and works offline. Repeating events, changed and cancelled occurrences, and
  shared invitations are handled; a tap on an event shows its place and notes. It can be the
  **lock screen** in any view: Day starts at the current hour and shows as many hours as fit,
  and the day's earlier and later events go on one line above and below, so none is missing.
  Google's calendar file (its whole history, in a new order each time) is asked for packed
  (gzip, a quarter of the size) and read a piece at a time (the reader closes an app that
  thinks too long in one go); a file that still arrives cut off is never used, so events
  can't go missing at random.
  Settings shows the clock and time zone the app uses.

## Update

Install the changed packages **over** the installed apps (SD card root → All Files → Install).
Do not uninstall first: that deletes the app's folder (settings, pages, dictionaries, decks).

## Files

| file | content |
|---|---|
| `calendar.xtapp` | new: Calendar |
| all other `.xtapp` packages, `apkg2cards.py` | unchanged since v0.11.0 |
| `dict-wordnet-en.zip` | WordNet for Dictionary, unchanged (see v0.3.0) |
| `wikipedia-en-vital.zip` | the offline Wikipedia pack, unchanged (see v0.11.0) |

All packages are included so one release has everything. `SHA256SUMS.txt` has the checksums.

# v0.11.0

Updates for the **Xteink X4 Pro** mini apps (stock XTOS Licorice, builds **26102301** and **26102401**).

## Changed

- **New: Hacker News** — Top, New, Best, Ask and Show in HN's own order, and search. Stories open
  with their text, or the linked article as text and pictures through your rss-opds Worker (update
  it for the new `/api/read` route), and end with a QR code of the address. A tap turns the page. Comments come level by level,
  loaded while you read; a long press on a story goes straight to them.
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
| `calculator.xtapp`, `klondike.xtapp`, `tasks.xtapp`, `weather.xtapp`, `hackernews.xtapp` | **new** |
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
