# Word Clock — XTOS Licorice mini app (API 2.9)

The time in words on a grid of letters: "IT IS HALF PAST TEN", "SAAT ONU YİRMİ GEÇİYOR",
"ES IST FÜNF VOR HALB ELF". The words of the time are black blocks with white letters, the other
letters small and plain (the lock screen shows only black and white, so they cannot be gray). The
words move in five-minute steps; four dots under the grid fill for the minutes between.

- **English** and **German** use the classic 11x10 word-clock layouts ("viertel vor", "fünf vor
  halb", "ein Uhr").
- **Türkçe** puts each hour in the three forms the sentence needs: bare on the hour and with
  "buçuk" ("SAAT ON BUÇUK"), the object form for past ("SAAT ONU YİRMİ GEÇİYOR"), the dative for to
  ("SAAT ONA ÇEYREK VAR"); 11 and 12 are "ON" + the form of one or two ("SAAT ON BİRİ ..."); 12:30
  and 0:30 are "SAAT YARIM". A 12x14 grid holds them in reading order (`make_grids.py`).
- The language follows the system's (tr, de, else English); the first button changes it, and the
  lock screen follows. **Lock screen** makes the Word Clock the lock screen (the system asks
  first); tap it again to give it back. The lock screen wakes on every minute.

## Files

`make_grids.py` (writes `src/grids.lua`: the rows and each word's place), `src/clock.lua` (the
sentence for a time, drawing), `src/app.lua`, `src/lock.lua`, `bundle.py` (makes `index.lua` and
`lockscreen.lua`), `test_wordclock.py` (`python -I apps/wordclock/test_wordclock.py`: every
minute in every language, sample sentences, drawing).
