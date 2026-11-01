# Word Hive — XTOS Licorice mini app (API 2.0)

A daily word puzzle for the X4 Pro: seven letters in a honeycomb, one of them in the middle. Make
as many words as you can; every word uses the middle letter.

## Playing

- Tap the letters to build a word, **Enter** to try it, **Delete** to take back a letter,
  **Shuffle** to move the outer letters around. Letters may be used more than once.
- Words have at least four letters. A four-letter word scores 1 point, a longer word a point a
  letter, and a **pangram** (all seven letters, at least one in every hive) 7 more.
- The marks under the title are the ranks, from Beginner through Good, Solid, Great and
  Brilliant to Queen bee (every word found), set as shares of the day's points.
- **Hints** counts the words still to find by first letter and length, and by their first two
  letters. **Yesterday** shows the answers of the day before, the ones you found and the ones you
  missed. Tap the found words for the whole list.
- **Menu**: Today, Earlier and Later days (each day keeps its own words), How to play.

## Puzzles

730 puzzles, a new one every day from 1 November 2026, then from the start again. Each has 20 to
50 answers. The letter S never appears, so plurals do not double the lists. `make_puzzles.py`
builds them from **2of12inf** of Alan Beale's [12dicts](http://wordlist.aspell.net/12dicts/)
(public domain; its inflections come from Kevin Atkinson's AGID, see `LICENSE-12dicts.txt`), a list
of common words with their plurals and verb forms, leaving out offensive words.

## Build

```bash
python -I apps/wordhive/make_puzzles.py PATH/2of12inf.txt   # data/puzzles.txt (from 12dicts-6.0.2.zip)
python -I apps/wordhive/bundle.py                           # tools/gamekit + src/main.lua -> index.lua
python -I apps/wordhive/test_wordhive.py                    # offline
python xtpack.py apps/wordhive
```
