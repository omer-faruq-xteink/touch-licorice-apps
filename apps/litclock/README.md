# Literary Clock — XTOS Licorice mini app (API 2.9)

The time of day told by a sentence from a book. Every minute a quote that names the time, the time
phrase in bold, then the book and its author; best as the lock screen, which the reader wakes on
every minute.

- **Quotes** come only from public-domain books (Project Gutenberg texts by authors who died more
  than 70 years ago, no translators), so they are free in the US and in life+70 countries.
  Detective stories mention the time most: Conan Doyle, Wilkie Collins, Anna Katharine Green,
  Fergus Hume, Edgar Wallace and others.
- A minute no book names shows the nearest earlier quote; the digital time under it always tells
  the exact minute then.
- **Another** (or a tap on the quote) shows another quote of the same minute; the choice changes
  every day by itself. **Time: on / off** shows or hides the digital time and date (the lock screen
  follows it). **Lock screen** makes the Literary Clock the lock screen (the system asks first);
  tap it again to give the lock screen back.
- The quote is drawn as large as fits, 20 to 46 px; bold is each glyph drawn twice, 1 px apart.

## The quotes

`make_quotes.py BOOKS.tsv BOOKS_DIR` finds time phrases ("half past nine", "a quarter to ten",
"twenty minutes past four", "nine o'clock", "9.30 p.m.", "midnight") in the books' sentences and
writes `data/hHH.txt`, one file per hour, one quote per line:

    HHMM<TAB>flag<TAB>before<TAB>time phrase<TAB>after<TAB>title<TAB>author

A phrase without a.m. / p.m. or a part of the day counts for both halves of the day. Bare
"three to four" / "ten past two" only count after a word that leads to a time ("at", "about",
"it was" ...), since they are often ranges; "ten to one that ..." (odds) is left out. Up to three
quotes per minute, from different books and authors, sentences near 140 characters first.

## Files

`src/common.lua` (data, layout, drawing), `src/app.lua`, `src/lock.lua`, `bundle.py` (makes
`index.lua` and `lockscreen.lua`), `make_quotes.py`, `data/`, `test_litclock.py`
(`python -I apps/litclock/test_litclock.py`).
