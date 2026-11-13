# xkcd — XTOS Licorice mini app (API 2.26)

**Needs firmware with API 2.26** (XT Licorice 26111201 or later): older firmware refuses to install it
and asks for an update. Needs Wi-Fi for comics not saved on the reader yet.

[xkcd](https://xkcd.com), the webcomic by Randall Munroe, on the reader. This app is not affiliated
with xkcd; the comics come from xkcd.com's own JSON interface (no account) under xkcd's licence,
[CC BY-NC 2.5](https://xkcd.com/license.html).

- **Reading**: the app opens on the latest comic. **Prev** and **Next** (swipes and the side
  buttons too), **Random**, and under **More**: **Go to #** (a comic number), **Latest**,
  **Favourites** and **Settings**.
- **Turned for wide comics**: a comic wider than tall turns the screen to landscape (800 px
  across), a tall one back to portrait, so most strips show at nearly full size.
- **Zoom**: a tap shows the comic twice as large as on the screen (or at its original size, when
  that is larger; at most 1024 px a side), made by the same resizer (fetched then: needs Wi-Fi);
  drag to move around it, tap again to fit it.
- **The alt text** (the extra joke under each comic): under a portrait comic, in full with **Alt**.
- **Favourites**: the star at the top right adds or removes the comic; **More → Favourites** lists
  them.
- **Offline**: the last 20 comics seen stay on the reader and open without Wi-Fi (the app then
  opens on the last one seen).
- **Sharp lines**: xkcd's lines are thin with grey edges, which the reader's black-and-white
  dithering broke into dots. So every picture comes through [images.weserv.nl](https://images.weserv.nl),
  a public image resizer (no account): made for exactly the space it gets (from the size in the
  picture's first 64 bytes, asked from xkcd first), greyscale at full contrast, and drawn as it is.
  Very faint grey details may come out lighter. A comic larger than the 1024 px the reader decodes is
  marked "(reduced)"; its Alt page has a QR code of the comic's page for the full size on a phone.
  Interactive comics show their title, alt text and a QR code to open them elsewhere.
- **Sleep screen** (Settings → Sleep screen: every 3, 6 or 12 hours, or off): the latest comic with
  its number, title and when it was looked for. While locked the reader asks xkcd.com again when that
  much time has passed, and fetches the picture only when a new comic is out. The store's build shows
  the latest comic the app saw.

Private files (`XTApps/xkcd/files/` on the card): `cache.txt` and `c_<n>.png` (the saved comics),
`favourites.txt`, `settings.txt`, `lock.txt` and `lock.png` (the sleep screen's comic), `wakes.txt`
(a log of the sleep screen's last 20 wakes).

## Files

`src/xk.lua` (addresses, a comic from its JSON, a PNG's size, fitting, saved lines, Random),
`src/main.lua` (the app), `src/lock/lock.lua` (the sleep screen), `bundle.py` (makes `index.lua`
and `lockscreen.lua` with `tools/gamekit/gamekit.lua`), tests: `test_xk.py`, `test_xkcd.py`
(a stand-in xkcd.com, picture host, resizer and decoder), `test_lock.py`.
