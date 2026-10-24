# Notes — XTOS Licorice mini app (API 2.9)

Freehand drawing and typed text on up to eight pages, kept on the device, with one page shown as
the lock screen together with the clock and battery level.

## Using it

The toolbar: **Draw** · **Text S/M/L** · **Undo** · **Page** · **Lock** · **Clear**.

- **Draw**: draw with a finger. Strokes are thin lines (e-ink ghosting stays low).
- **Text**: tap the page where the text should start; the firmware's own keyboard opens; **OK**
  places it. Tapping **Text** again cycles the size (small / medium / large).
- **Undo** removes the last stroke or text. **Page** cycles through the eight pages. **Clear**
  asks (**Erase** / **Cancel**), then empties the page.
- **Lock**: the app asks **With clock**, **No clock** or **Cancel**; the first time the firmware
  then asks **Set as lock screen**. From then on the chosen page is drawn whenever the device
  locks or sleeps. With the clock (and the battery level) it is redrawn once a minute
  (`interval_sec` in the manifest); without it the app asks the host to stop the minute redraw.
  Lock again on another page, or to switch the clock on or off, at any time. Settings → Display → Off wallpaper must stay on
  **Default** (the lock-screen app route; the "Custom" image slot is a different mechanism).

Pages are files in the app's storage (`page1.txt` … `page8.txt`; strokes as `S x,y x,y …`, text
as `T x y size text`), written after every change; `lock.txt` names the lock page.

## How it is built

API 2.9 (`"api": "2.0"` in the manifest, no permissions needed): pointer events with
`phase = down / move / up` give the strokes; each stroke is drawn with one `g:polyline` per
60-point chunk, so even a busy page stays far below the frame's command budget; text uses
`ctx.input:text(opts, fn)`; the lock entry `lockscreen.lua` reads the same storage files and adds
`ctx.clock:now()` and `ctx.device:battery()`.

```bash
python xtpack.py apps/notes
python -I apps/notes/test_notes.py   # offline, Lua 5.4 via lupa
```

Verified on an X4 Pro running Licorice 26102301 (2026-10-24): drawing, text, pages, the lock
screen with its clock. The previous API 0.8 version (tap-placed shapes, own keyboard) is in the
git history before v0.2.0.
