# Text adventures — XTOS Licorice mini app (API 2.9)

Plays classic text adventures on the X4 Pro: Z-machine story files, the format of Infocom's games
(Zork, Planetfall, Enchanter...) and of most games written in Inform. Little typing: the common
commands are buttons and the game's own words are chips to tap.

## Games

- Copy story files (`.z3`, `.z5`, `.z8`; also `.z4`, `.z7`) into `AppFiles/textadv/` on the SD card
  (USB mode). Version 6 games (`.z6`, with pictures) and Glulx games (`.ulx`, `.gblorb`) do not run.
- **Zork I is built in**, and **Zork II and III** are a free pack: Microsoft released the three under
  the MIT licence in 2025. The built-in copy sits in the package's data section as hex text
  (`data/zork1.txt`, made by `make_data.py` from `games/Zork I.z3`); the
  [tools site](https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/textadv/) zips `games/` as the
  pack, and the library shows a QR code to that page. A `Zork I.z3` on the card takes the built-in
  one's place (same progress).
- More games: the [IF Archive](https://ifarchive.org/indexes/if-archive/games/zcode/) and
  [IFDB](https://ifdb.org). Each game has its own terms.

## Playing

- The library lists the games; one in progress says so. The last game played opens at once.
- Top: the status line (location, score and moves; or the game's own upper window).
- The transcript: each reply opens at its beginning; tap the left third of the text (or a side
  button) to page back, the rest to page on.
- Buttons: the eight directions; Up, Down, In, Out, Look, Inv, Wait play at once. Below them the
  **word chips**: the words of the last reply that the game knows, then common verbs (take, drop,
  examine, open...); tapping them builds the command shown above (`> open mailbox`), **Send**
  plays it. **Keys** opens the keyboard, **Del** takes the last word away, **Clear** all of them,
  **Again** repeats the last command.
- Saving: the game is saved after every turn (leave the app, it continues there, with
  "[Continued]"). The game's own SAVE and RESTORE keep one more save per game.
- Menu (or Back): text size, restart, the list of games.

## How it works

`src/zmachine.lua` is a Z-machine interpreter after the Z-Machine Standards Document 1.1:
versions 3, 4, 5, 7 and 8, every opcode but version 6's graphics, output streams, the upper
window as a grid of text (the status line of v4+ games), tokenising with the game's dictionary,
and save / restore as a snapshot of the dynamic memory, the stack and the call frames. The story
stays one Lua string; the writable part of memory is packed four bytes to an integer (the reader
has about 2 MB of heap). The game runs in slices of a few seconds with the time budget extended,
going on in a timer, so a long turn never ends the app. On the X4 Pro a Zork turn takes about a
second, the automatic save included.

## Build and test

```bash
python -I apps/textadv/make_data.py                 # games/Zork I.z3 -> data/zork1.txt (built in)
python -I apps/textadv/bundle.py                    # gamekit + src/zmachine.lua + src/main.lua -> index.lua
python -I apps/textadv/test_textadv.py              # the app, playing Zork I
python -I apps/textadv/zrun.py STORY [-c "cmd;cmd"]  # the interpreter alone, on the PC
python xtpack.py apps/textadv
```

`test_textadv.py PATH/zork1.z3` also runs the interpreter checks CZECH (output identical to its
reference) and Praxix ("All tests passed") when their files sit beside the story file (from the
IF Archive, `if-archive/infocom/interpreters/tools/`).
