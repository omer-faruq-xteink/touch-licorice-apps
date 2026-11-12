# Piano Follow — XTOS Licorice mini app (API 2.21)

Sheet music on the reader that follows your playing. Pick a piece from a free catalog (or convert
your own), put the reader on the music stand (it runs in landscape: wide lines, bigger notes) and play: with a Bluetooth MIDI keyboard the app
turns the pages for you, and in Practice it waits for the right notes. Without a keyboard it is a
plain sheet-music reader: tap the left or right third of the page, or use the side buttons.

## Pieces

- **Catalog**: free pieces, mostly for learners (beginner and easy) plus well-known classical works,
  by level, then composer, or by search. Each piece shows its composer, arranger, size, license
  and source. Download puts it on the reader; it then stays under **My pieces**, offline too.
- **Your own scores**: on the [converter page](https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/piano/)
  a MusicXML file (MuseScore, Sibelius, Finale and Dorico export it) or an ABC file is engraved for
  the reader's screen and written to its card (`AppFiles/pianofollow/`). The file stays on your
  computer and your reader. MIDI, PDF and photos of sheet music cannot be converted.
- Delete a piece from its score screen: the mode button, **Delete this piece**.

## Modes

The button in the middle of the score's top bar switches the mode (kept per piece, with its page):

- **Page turn**: the app follows silently and turns the page on the page's last note (at a written
  repeat, back to where the repeat starts).
- **Follow**: the same, with a dashed line under the bar you are playing (redrawn about once a
  second: the e-ink screen needs about half a second a frame).
- **Practice** (right hand, left hand or both): the score waits until the next note or chord is
  played right; a small mark under the staff shows which. A chord counts when all its notes are down within a
  second, in any order. Wrong notes are counted (top bar) and listed by bar at the end, with
  **Practice from bar n** for each.

Mistakes are expected: extra and missed notes are skipped, and starting a bar or a passage again
is found within a few notes. A page turns only when the app is sure you are at its end: a late
turn is better than an early one. Turning a page by hand also tells the app where you are.

## Keyboard

**Keyboard** on the first screen: **Search** lists Bluetooth MIDI keyboards (those advertising the
standard BLE MIDI service; USB keyboards need a Bluetooth MIDI adapter), tap one to connect. It is
remembered: the app connects to it when it opens, and the Keyboard screen searches for it by itself. A keyboard that asks for pairing is paired
automatically. If it goes away, the top bar says **Keyboard lost** and the app tries again every
5 seconds. **Forget** removes it.

## The .xtscore file

One file per piece: `XTSCORE1`, a 4-byte little-endian header length, a JSON header (title,
composer, arranger, license, source, url, level, page size, the offset and length of each page and
of the note map), then zlib streams: each page 440 rows of 100 bytes (800 x 440, the landscape
screen under the app's top bar; 1 bit a pixel, 1 = black),
and the note map (JSON: bars with their place on the page, onsets in playing order with their
pitches per hand, and each page's turn points). `site/tools/piano/convert.mjs` writes it with
[Verovio](https://www.verovio.org/) (LGPL); the app only reads it.

## Testing

- `python -I apps/pianofollow/test_pianofollow.py`: the app under the gamekit harness (file reading,
  the BLE MIDI parser, following with mistakes, practice, the screens, the keyboard, the catalog).
- `cd tools/piano && npm install && npm test`: the converter, the level estimate, the catalog build.
- `tools/piano/blemidi_sim.py`: the PC as a Bluetooth MIDI keyboard (Windows), fed by a USB MIDI
  keyboard or by a piece's notes with mistakes; `python -I tools/piano/test_sim.py` tests its packets.

## Catalog sources

The catalog is built by `tools/piano/build_catalog.mjs` from `tools/piano/catalog.yaml`, a reviewed
selection from [PDMX](https://zenodo.org/records/15571083) (public-domain and CC0 MusicXML from
MuseScore; the dataset is CC BY 4.0), with only traditional pieces and composers who died before
1955, each page checked by hand. It is published as `catalog/piano/` in the repository, which the
app reads directly, so new pieces appear without an app update.
