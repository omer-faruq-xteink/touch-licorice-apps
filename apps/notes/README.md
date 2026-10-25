# Notes — XTOS Licorice mini app (API 2.9)

Freehand drawing and typed text on up to eight pages, kept on the device, with one page shown as
the lock screen together with the clock and battery level.

## Using it

The toolbar: **Tool** · **Undo** · **Page** · **Lock** · **Clear**. **Tool** shows the current tool
and opens a list to pick another: **Draw S / M / L**, **Erase**, **Text S / M / L**.

- **Draw S / M / L**: draw with a finger with a thin, medium or thick pen (thin keeps e-ink
  ghosting lowest). The lock screen shows the same widths.
- **Erase**: rub over the page with a finger. Strokes are cut where the eraser (a circle that
  follows the finger) passes and the rest stays; a text it touches is removed whole.
- **Text S / M / L**: tap the page where the text should start; the firmware's own keyboard opens;
  **OK** places it in the chosen size.
- **Undo** removes the last stroke or text, or brings back what the last erase took. **Page** cycles through the eight pages. **Clear**
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
