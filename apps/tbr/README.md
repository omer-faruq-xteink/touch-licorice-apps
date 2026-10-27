# TBR Planner — XTOS Licorice mini app (API 2.9)

Plan your **to-be-read** books: a **Wishlist** (no dates yet), **Planned** books with start and
end dates, a month **Calendar**, a **Done** list, and a **lock screen** with today's books. A port
of [tbrplanner.koplugin](https://github.com/omer-faruq/tbrplanner.koplugin) for KOReader, laid
out for the X4 Pro's 480x800 screen. Works offline.

## Adding a book

**+ New** asks how:

- **From the reader**: the books you have opened on this reader at least once, the last read
  first, with author, progress and the last reading day. A linked book follows the reader: its
  progress and reading time show in the planner, and it moves to **Done** when you finish it.
- **Type the title**: any book, also one you haven't got yet. You can give it pages (`40/320`:
  read / total) for the estimate.

The reader shares only the books it has opened, without file paths or page counts, and an app
can't open a book: open it from the library as usual.

In **Planned** a new book starts today; in **Calendar** on the day you tapped; in **Wishlist** it
has no dates.

## A book

Tap a book to edit it: title, author, the reader's book (link, change or unlink), priority (−/+),
tags, **Start** and **End** (−7 / −1 / +1 / +7 days; tap the date for Today, typing a date or no
date), **Keep duration** (on: moving Start moves End too), progress, and the estimate:

- a book from the reader: the reader's percent can include pages read elsewhere (another reader,
  a synced position) while its reading time counts only this reader, so their ratio says
  nothing. Tap **Progress** and type the book's **total pages**: the pages left (the percent left
  of them) at the **pages a day** goal give the days. Without pages, the app measures your pace
  from the moment the book came into the planner, once you have read 2% and 10 minutes more on
  this reader, and uses the **daily reading goal** (minutes);
- a typed book: the pages left at the **pages a day** goal.

Both goals are in More.

**Set end** puts the estimated end date in. **Plan** / **To wishlist** adds or removes the dates,
**Done** / **Not done** moves it (a reader book marked not done stays so), **Delete** forgets it.

## Lists and calendar

- **Planned** shows each book's dates, progress, days left (or late, with `!`), priority and
  `#tags`; the books you should be reading today are framed. **Sort**: by date, priority or
  title. **Wishlist** sorts by priority, title, newest or oldest; **Done** by finishing day or
  title. A **filter** (in More) keeps the books whose title, author or tags contain a text.
- **Calendar**: a month with a bar for each planned book; tap a day for its books and **+ New
  from this day**. `<` / `>`, swipes and the side buttons page.

## More (settings)

Daily reading goal (10–120 minutes), pages a day (5–100, for every book with its pages), the first day of the week,
the filter, and the **lock screen**.

## Lock screen

Turned on in More (the firmware asks to confirm; Settings → Display → Off wallpaper must be
**Default**): today's books (and late ones) with progress, days left and time left, the next
books to start, or the top of the wishlist when nothing is planned, and your reading streak. It
is redrawn every hour.

## Files

`XTApps/tbr/files/` on the SD card: `items.txt` (one book a line, tab-separated: id, status,
title, author, reader id, priority, tags, start, end, pages, pages read, added, done, auto, and
the reader's last percent and seconds) and `settings.txt`.

## Development

- `src/tbr.lua` (dates, the book list, the reader, estimates), `src/main.lua` (the app),
  `src/lock/lock.lua` (the lock screen); `bundle.py` builds `index.lua` and `lockscreen.lua`.
- `test_tbr.py` — offline test with a stand-in reader: `python -I apps/tbr/test_tbr.py`.

## License

GNU GPL v3 (`LICENSE`), as tbrplanner.koplugin.
