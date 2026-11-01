# Tarot — XTOS Licorice mini app (API 2.0)

Tarot cards on the X4 Pro as prompts for reflection, not fortune telling: a card a day and
three-card readings, with the pictures of Pamela Colman Smith's 1909 deck and an upright and a
reversed meaning for every card. Each card is a theme to think about; nothing is predicted.

## Using it

- **Today**: tap the face-down card to draw the day's card. It stays the same until midnight; tap
  it to open it as a page. **Journal** lists the earlier days' cards; tap one to read it again.
- **Reading**: think of something on your mind and tap **New reading**: Situation, Obstacle
  and Way forward, three different cards with their keywords. Tap a card to read it. The reading
  stays until the next one.
- **Deck**: every card by suit (Major Arcana, Wands, Cups, Swords, Pentacles) with both meanings;
  the side buttons step to the previous or next card. **Reversed** switches reversed draws on
  or off.
- Reversed cards are drawn upside down on hosts that can rotate images, and named "(reversed)".

## Cards

The pictures are the 1909 printing drawn by Pamela Colman Smith (public domain), from the scans
on Wikimedia Commons (Category: Rider-Waite tarot deck (Roses & Lilies)). `make_data.py` crops
each to its frame, raises the contrast and Atkinson-dithers it to black and white at 240x418 and
144x251. They travel in the package's data section as base64 PNG, one card a line, padded to one
length so the app seeks straight to a card, and `ctx.image:decode` (the optional capability
`image_decode`) turns one into a picture when it is shown. Without that capability the cards are
framed names. The meanings (`cards.txt`) were written for this app and are CC0.

## Build

```bash
python -I apps/tarot/make_data.py PATH/TO/SCANS   # data/ from cards.txt and the 78 "RWS1909 - ..." scans
python -I apps/tarot/bundle.py                    # tools/gamekit + src/main.lua -> index.lua
python -I apps/tarot/test_tarot.py                # offline
python xtpack.py apps/tarot
```
