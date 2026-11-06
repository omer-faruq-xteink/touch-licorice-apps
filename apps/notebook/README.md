# Notebook — XTOS Licorice mini app (API 2.9)

Plain text notes, written block by block, with folders, tags, sorting and a search through
all notes. Each note is a `.txt` file in `AppFiles/notebook/` on the SD card, so you can also read
and write your notes on a computer.

## Using it

- **The list**: every note with its folder, tags, the date it was last edited and its first words,
  seven to a page (swipe or the side buttons for the next). The buttons on top:
  - **Folders**: show one folder only (or the notes with no folder); the button then shows its name.
  - **Tags**: show the notes with one tag.
  - **Sort**: last edited, title A-Z, or newest first.
  - **Search**: type a word; every note is searched (titles and text, upper and lower case alike,
    Turkish letters too: *istanbul* finds *İSTANBUL*), and each note found shows the line it was
    found in. **Clear** ends the search.

  The filters and the order are kept for the next time. **New note** asks for a title and opens the
  note on a first block (in the folder and with the tag the list is filtered on, if any).
- **A note**: its blocks of text, a page at a time. A block is what the keyboard edits at once: up
  to 512 characters, the firmware's limit for its docked keyboard, as many lines and paragraphs as
  fit. **Tap a block to edit it**: the keyboard opens at the bottom, the block above it, and
  **Enter starts a new line**; **Save** and **Cancel** are at the top. A blank line splits it into
  two blocks; saved empty, it is deleted. Back while typing asks whether to keep a change. **Add**
  puts a new one at the end. A note can have as many blocks as you like.
- **Writing on**: when a block you are writing at its end reaches 500 characters, it is kept and
  the writing goes on in a new block right below it, the keyboard staying open; the cut is at the
  last space or line break, so the word you are typing moves along whole. (Typing in the middle of
  a full block just stops at 512.)
- **Menu** (top right of a note): **Rename**, **Folder** (one of yours, none, or a new one),
  **Tags** (with commas between them), **Delete** (asks first).
- Back leaves a note for the list, ends a search, and on the list lets the reader offer to exit.

## The files

```
Shopping list
folder: Home
tags: weekly, market
edited: 2026-11-06 14:30
created: 2026-11-06 14:02

Milk, bread, eggs
Butter

Olive oil from the market on Saturday
```

The first line is the title, then the optional folder and tags lines and the dates the app writes,
a blank line, and the blocks with a blank line between them. Any `.txt` file you copy into the
folder is a note too: its first line is the title and the rest its text (a block longer than 512
characters is cut at a space when the note is opened). The file name comes from the title. The
reader's app folder has no subfolders, so a note's folder is its `folder:` line. Up to about 500
notes (the folder holds 512 files).

The list reads each file once and keeps titles, folders and tags in an index of its own, so it
opens quickly; a file that changed size on a computer is read again.

## Files

`src/book.lua` (the note format, file names, the index, search), `src/main.lua` (on `tools/gamekit`),
`bundle.py`, `test_notebook.py` (`python -I apps/notebook/test_notebook.py`: the format, file names,
search folding, and the app by taps with stand-ins for the card, the clock and the docked keyboard).
