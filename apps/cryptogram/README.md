# Cryptogram — XTOS Licorice mini app (API 2.0)

A daily quote for the X4 Pro with every letter swapped for another, the same one all through:
work out the code and read the quote.

## Playing

- Tap a letter of the puzzle: every place it appears is framed, and the line under the puzzle says
  how often it appears. Tap the key it stands for; the next open letter is chosen for you. A key
  already used elsewhere moves to the new place; used keys are underlined.
- **Hint** shows the framed letter (or the first one still open), **Check** strikes out the wrong
  guesses, **Erase** clears the framed letter. A full and correct puzzle is solved at once.
- The author is part of the puzzle; a proverb just says "Proverb".
- **Menu**: Today, Earlier and Later days (each day keeps its guesses), Start over, How to play.
- Tips: a one-letter word is A or I; THE and AND are the commonest three-letter words; the
  commonest letters are E, T, A, O, I, N; a letter never stands for itself.

## Quotes

471 quotes, a new one every day from 1 November 2026, then from the start again: proverbs and
lines by writers and thinkers long out of copyright (Shakespeare, Austen, Twain, Wilde, Franklin,
Emerson, Thoreau, Dickinson, Seneca and others), in `quotes.txt`. `make_data.py` checks them (short
enough for one screen, enough different letters to work out) and shuffles them into
`data/quotes.txt`. Each day's code is made from the date, so it is the same on every reader.

## Build

```bash
python -I apps/cryptogram/make_data.py        # quotes.txt -> data/quotes.txt
python -I apps/cryptogram/bundle.py           # tools/gamekit + src/main.lua -> index.lua
python -I apps/cryptogram/test_cryptogram.py  # offline
python xtpack.py apps/cryptogram
```
