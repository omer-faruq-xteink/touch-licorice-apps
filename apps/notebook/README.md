# Notebook — XTOS Licorice mini app (API 2.9)

Plain text notes, written paragraph by paragraph, with folders, tags, sorting and a search through
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
  note on a first paragraph (in the folder and with the tag the list is filtered on, if any).
- **A note**: its paragraphs, a page at a time. **Tap a paragraph to edit it**: the keyboard opens
  at the bottom, the paragraph above it, and **Enter starts a new line**; **Save** and **Cancel** are
  at the top. A blank line splits it into two paragraphs; saved empty, it is deleted. Back while
  typing asks whether to keep a change. **Add** puts a new one at the end. A paragraph holds up to
  512 characters (the keyboard's limit); a note can have as many as you like.
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
a blank line, and the paragraphs with a blank line between them. Any `.txt` file you copy into the
folder is a note too: its first line is the title and the rest its text (a paragraph longer than
512 characters is cut in two at a space when it is edited). The file name comes from the title. The
reader's app folder has no subfolders, so a note's folder is its `folder:` line. Up to about 500
notes (the folder holds 512 files).

The list reads each file once and keeps titles, folders and tags in an index of its own, so it
opens quickly; a file that changed size on a computer is read again.

## Files

`src/book.lua` (the note format, file names, the index, search), `src/main.lua` (on `tools/gamekit`),
`bundle.py`, `test_notebook.py` (`python -I apps/notebook/test_notebook.py`: the format, file names,
search folding, and the app by taps with stand-ins for the card, the clock and the docked keyboard).
