# Anki — XTOS Licorice mini app (API 2.9)

Flashcards with spaced repetition on the reader: a built-in English deck, your own cards, and any
Anki deck converted on a computer.

## Studying

- **Tap a deck** to study it. A card shows its front; tap it (or press a side button) for the
  answer, then rate it: **Again / Hard / Good / Easy**. Each button shows when the card comes
  back. Long cards scroll: swipe up, swipe down for the top.
- Scheduling is **FSRS** (version 4.5, its default parameters), the open scheduler Anki itself
  offers: each card has a stability (the days until you would recall it with 90 % chance) and a
  difficulty, both updated from each answer, so a card comes back just before you would forget
  it. New and forgotten cards first go through steps of minutes and come back in the same
  session. Intervals are at most 1000 days. Progress from versions before v0.11 (SM-2) carries
  over. Reviews come first, then new cards up to **New/day** (5 to 50, 15 by default).
- **Menu** while studying: **Undo** the last rating, **Add card** (front and back with the
  firmware keyboard), **Delete card** (it never comes back in this deck), back to the **Decks**.
- **Long-press a deck** to add a card to it. **My cards** is a deck of your own cards only.
- **Lock screen**: long-press a deck, **Lock screen**. When the reader locks it shows one of that
  deck's next cards (due within a day, then new ones), front and answer, a different one every
  30 minutes; the firmware asks once to make Anki the lock screen (it needs Settings > Display >
  Off wallpaper on *Default*, and replaces another app's lock screen such as Notes'). Long-press
  the deck again for **Lock screen off**.

## The built-in deck: English words B2-C1

1438 English words past the everyday basics but in general use (frequency ranks 4000 to 16000),
each with its part of speech, its main sense (and a second one where WordNet has a good example),
an example sentence and similar words. Built by `make_default_deck.py` from **wordfreq** (Robyn
Speer, word frequencies, CC BY-SA 4.0) and **WordNet 3.0** (Princeton University, see
`LICENSE-WORDNET.txt`). It lives inside the package: nothing to copy.

## More decks from Anki

1. Get a deck as an `.apkg` file: export one from Anki (desktop or mobile), or download one of the
   many shared decks at https://ankiweb.net/shared/decks (like the KOReader Anki Viewer's decks).
2. Convert it on a computer (Python 3):

   ```bash
   python apkg2cards.py My_Deck.apkg out
   ```

   `python apkg2cards.py My_Deck.apkg --list-fields` shows the deck's fields and which ones go on
   the front and back; choose others with `--front FIELD --back FIELD,FIELD`. `--reverse` adds
   back-to-front cards, `--name` sets the name shown on the reader. Newer Anki exports need
   `pip install zstandard` once.
3. Put the reader in USB mode and copy the files from `out` into `XTApps/anki/files/` on the SD
   card (the folder appears after the app's first start). The deck shows up in the list.
   The app from the Xteink store reads its own folder instead: Menu → Help shows the path
   (`AppFiles/<app id>`).

Only text is kept: pictures and sounds are left out (the reader has no sound), which is why a deck
of 200 MB usually becomes a few hundred kilobytes. To update a deck you study, convert the new
export with `--update` into the same `out` folder (with the old files in it) and copy again:
cards keep their places, so progress is kept.

A plain list works too: a `.tsv` file with `front<TAB>back` per line, copied into
`XTApps/anki/files/` as it is (up to 300 KB), or converted like an `.apkg` (`.tsv`, `.csv`).

Never uninstall the app: the firmware deletes `XTApps/anki/files/` with it, decks and progress.
Install updates over it.

## Files

`src/main.lua` (on `tools/gamekit`), `lockscreen.lua`, `bundle.py`, `apkg2cards.py` (the converter),
`make_default_deck.py` and `data/` (the built-in deck), `test_anki.py`
(`python -I apps/anki/test_anki.py`).
