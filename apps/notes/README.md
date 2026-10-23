# Notes — XTOS Licorice mini app

Pages of typed text and tap-placed shapes, kept between sessions, with one page shown on the
device's lock screen.

## What the host allows

Touch arrives as **taps and swipes only**; there is no stream of finger positions in API 0.8, so
freehand drawing is not possible. Instead:

- **Type**: an on-screen keyboard (letters, Sh for one capital, ?! for a symbol row, digits, space,
  Ent, backspace). Text wraps at 34 characters; up to 2000 characters per page.
- **Draw**: Line (two ends), Box (two corners), Circle (centre, then a point on the rim), each
  placed with two taps on the page; Undo removes the last shape or cancels a first tap. Up to 120
  shapes per page.
- **Pages**: a list; New, Delete (the last page is cleared instead), tap a page to open it. Side
  buttons and left / right swipes change pages in view mode. Up to 12 pages.
- Everything is in `ctx.state`, saved by the host when you leave.

## Lock screen

**Lock** marks the current page and calls `ctx.system.set_as_lockscreen_app()`. The manifest
declares `requires: ["lockscreen_timer"]` and a `lockscreen` block whose entry is
`lockscreen.lua`; when the device goes to standby, the host runs that entry and it paints the
chosen page with the time in the corner. **Verified on an X4 Pro running Licorice 26102301
(2026-10-23)**: the standby screen showed the page's text and shapes under the clock.

**Info** lists what `ctx.lock`, `ctx.system` and `ctx.display` contain on your host, for anyone
re-checking a newer firmware.

## Build

```bash
python xtpack.py apps/notes
```

## Verification status

On the device: typing, shapes, the lock screen. Offline under Lua 5.4 (`test_notes.py`): wrapping;
the keyboard through the app's own key walker incl. shift, symbols, enter, backspace, done; shapes
incl. undo, cancel and out-of-canvas taps; pages incl. new, open, delete, clear, side buttons and
swipes; Lock against a stubbed host; Info; state resume and garbage; the lock entry rendering the
chosen page; draw budget under 1024 in every mode. The page code is inlined into both entries
rather than shared through `require`, because the code-section module loader has not been
exercised on this build.
