# Gamebook — XTOS Licorice mini app (API 2.9)

Choose-your-own-adventure stories: read a page, pick what happens next. Seven stories come built
in; more are `.story` files on the SD card.

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

## Built-in stories

*The Dark Lighthouse*, *The Night Train*, *The Mountain Hut*, *The Clockmaker's Shop*, *Signal from
Station Nine*, *The Midnight Market* (by omer-faruq, CC BY 4.0), and
[*The Intercept*](https://github.com/inkle/the-intercept) by inkle (MIT licence, converted from its
Ink source with the tools site's converter; the notice is at the top of `data/the-intercept.txt`).

Stories you copied in come first in the library; built-in stories in the reader's language come
before others, and a story in another language is marked with it.

## More stories

**More stories** in the library shows the folder and a QR code of the
[tools site](https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/gamebook/), which has:

- the **story pack** (CC BY 4.0): three more stories, *The Dragon's Riddles*, *The Orchard Ghost*
  and *Courier to Kepler Station*, to copy in;
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
The built-in stories in `data/` are examples.

## Files

`src/story.lua` (reads and plays the format), `src/main.lua` (the screens), bundled into
`index.lua` by `bundle.py` (with `tools/gamekit`); `data/lighthouse.txt`, the built-in story;
`data/`, the built-in stories (all data files are listed in the library); `stories/`, the pack's
(`tools/build_site.py` zips them for the site); `test_gamebook.py`:

```bash
python -I apps/gamebook/test_gamebook.py   # the engine, the screens, converted Twine and Ink
                                           # stories (needs Node), every story played at random
```
