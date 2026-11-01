# Tasks — XTOS Licorice mini app (API 2.9)

Lists of things to do, ticked off with a tap.

- **Lists**: New list; tap one to open it. A long press on a list: Rename, Delete, Lock screen.
- **Items**: tap the box to tick it (ticked items are struck through), tap the text for Edit,
  Delete, Up and Down (a long press opens the same menu). Add types a new item with the
  firmware keyboard; **Clear done** removes the ticked items after asking.
- **Repeat** (in an item's menu): Every day, Every week, Every 2 weeks, Every month, or Other
  ("3 days", "2 weeks", "6 months"). A ticked repeating item keeps the day and comes back (un-ticked)
  when it is due again, counted from that day; months are calendar months (31 Jan + 1 month =
  28 or 29 Feb). Under it: "every 4 days, next Thu 5 Nov" while ticked, "due today" or
  "late 2 days" while open. **Clear done** leaves repeating items in place.
- Swipes and the side buttons turn the page in long lists.
- **Lock screen**: any one list (List → Lock screen): the date and that list's open items in the
  large font. The firmware asks once to make the app the lock screen; it shows the list as it was
  when you last changed it, and a ticked repeating item appears on it again on the day it is due.
  Only one app can be the lock screen at a time (Notes, Anki, Weather).
- Everything is kept in one plain text file, `XTApps/tasks/files/lists.txt`, which you can also
  write or edit on a computer:

  ```
  # Shopping
  [ ] bread
  [x] milk

  # Home
  [x] Water plants {every 4 days, done 2026-11-01}
  [ ] Change the water filter {every 3 months, done 2026-08-10}
  ```

Files: `src/main.lua` (on `tools/gamekit`), `lockscreen.lua`, `bundle.py`, `test_tasks.py`
(`python -I apps/tasks/test_tasks.py`).
