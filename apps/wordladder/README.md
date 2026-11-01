# Word Ladder — XTOS Licorice mini app (API 2.0)

A daily word puzzle for the X4 Pro (Lewis Carroll's "doublets"): change the start word into the
target one letter at a time, and every step must be a word. COLD, CORD, CARD, WARD, WARM.

## Playing

- Tap a letter of the newest word (the one to change is framed), then the new letter on the
  keyboard. If the result is a word, it joins the ladder; the side buttons move the frame too.
- Letters already where the target has them are underlined. **Par** is the shortest ladder.
- **Undo** takes back the last step. **Hint** adds the next word of a shortest ladder from where
  you are, also when you have left the usual one.
- **Menu**: Today, Earlier and Later days (each keeps its own ladder), Start over, Answer (a
  shortest ladder), How to play.

## Puzzles

730 ladders, a new one every day from 1 November 2026, then from the start again: four letters,
and five on every third day, with a shortest ladder of 4 to 6 steps. `make_puzzles.py` builds them
from Alan Beale's [12dicts](http://wordlist.aspell.net/12dicts/) (public domain; its inflections
come from Kevin Atkinson's AGID, see `LICENSE-12dicts.txt`). Any word of 2of12inf counts as a step
(plurals and verb forms too); start and target words are everyday words (in 2of12, 3of6game and
3esl). Offensive words are left out with Word Hive's filter.

## Build

```bash
python -I apps/wordladder/make_puzzles.py FOLDER       # data/ from 12dicts (see the script)
python -I apps/wordladder/bundle.py                    # tools/gamekit + src/main.lua -> index.lua
python -I apps/wordladder/test_wordladder.py           # offline
python xtpack.py apps/wordladder
```
