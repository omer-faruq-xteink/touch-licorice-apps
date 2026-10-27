# Tasks — XTOS Licorice mini app (API 2.9)

Lists of things to do, ticked off with a tap.

- **Lists**: New list; tap one to open it. A long press on a list: Rename, Delete, Lock screen.
- **Items**: tap the box to tick it (ticked items are struck through), tap the text for Edit,
  Delete, Up and Down (a long press opens the same menu). Add types a new item with the
  firmware keyboard; **Clear done** removes the ticked items after asking.
- Swipes and the side buttons turn the page in long lists.
- **Lock screen**: any one list (List → Lock screen): the date and that list's open items in the
  large font. The firmware asks once to make the app the lock screen; it shows the list as it was
  when you last changed it. Only one app can be the lock screen at a time (Notes, Anki, Weather).
- Everything is kept in one plain text file, `XTApps/tasks/files/lists.txt`, which you can also
  write or edit on a computer:

  ```
  # Shopping
  [ ] bread
  [x] milk
  ```

Files: `src/main.lua` (on `tools/gamekit`), `lockscreen.lua`, `bundle.py`, `test_tasks.py`
(`python -I apps/tasks/test_tasks.py`).
