# Gamebook — XTOS Licorice mini app (API 2.9)

Choose-your-own-adventure stories: read a page, pick what happens next. One story comes built in;
more are `.story` files on the SD card.

## Reading

- The **library** lists the built-in story and every `.story` file in the app's folder, with
  "in progress" or "finished". Tap one: its first screen shows the author, a line about it and
  its licence, with **Start**, or **Continue** and **Start over** when you have begun it.
- A page shows the text and the choices as buttons under it. Long pages turn with **<** / **>**,
  a tap on the right or left third of the text, a swipe or the side buttons; the choices are on
  the last page. A page with no choices has **Continue**; an ending says *The End*, with **Play
  again** and **Library**.
- **Menu** (or the Back key): **Undo** the last choice (up to 30 back), **Text size** (small,
  medium, large), **Start over**, **Library**.
- Progress is saved on every page, per story; reopening a story continues where you were.

## More stories

**More stories** in the library shows the folder and a QR code of the
[tools site](https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/gamebook/), which has:

- the **story pack**: original stories (CC BY 4.0) as a zip, five in `EN/` and three in `TR/`; copy
  the `.story` files, not the folder (the app does not look inside folders);
- a **converter**, running in the browser, for stories made with [Twine](https://twinery.org)
  (Harlowe, SugarCube; text and links of Chapbook and Snowman) or
  [Ink](https://www.inklestudios.com/ink/) (the `.ink` source), and for
  [Project Aon](https://www.projectaon.org) gamebooks such as Lone Wolf (the book's `.epub`: each
  section a page, each "turn to" a choice, the Random Number Table built in, the rules first);
- **where to find stories**: shared Twine and Ink games (the IF Archive, IFDB, inkle's *The
  Intercept*) and Project Aon's books, which are free for your own use but may not be shared.

Copy `.story` files into `AppFiles/gamebook/` on the SD card (USB mode). On the command line the
same converter is `node site/tools/gamebook/cli.mjs STORY_FILE OUT.story`.

## Writing a story

The format is plain text, described in [FORMAT.md](FORMAT.md): passages (`== name`), choices
(`* Label -> passage`), variables, conditions and text that changes with them.
`data/lighthouse.txt` (the built-in story) and `stories/` are examples.

## Files

`src/story.lua` (reads and plays the format), `src/main.lua` (the screens), bundled into
`index.lua` by `bundle.py` (with `tools/gamekit`); `data/lighthouse.txt`, the built-in story;
`stories/en`, `stories/tr`, the pack (`tools/build_site.py` zips it for the site); `test_gamebook.py`:

```bash
python -I apps/gamebook/test_gamebook.py   # the engine, the screens, converted Twine and Ink
                                           # stories (needs Node), every story played at random
```
