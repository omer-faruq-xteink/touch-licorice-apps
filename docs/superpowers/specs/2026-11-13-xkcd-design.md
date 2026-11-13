# xkcd 1.0.0: a new app

## Intent
The user (2026-11-13): add xkcd.com as a new app if it has a suitable API. It does: xkcd's JSON
interface needs no key, and the comics are black-and-white line art that suits e-ink. Read xkcd on
the reader as comfortably as the screen allows, with the alt text (half of each joke), favourites,
the latest comic on the sleep screen, and the last ones readable without Wi-Fi.

## Goals
- Opens on the latest comic; **Prev**, **Next**, **Random**, **#** (go to a number).
- Wide comics turn the screen to landscape (800 px across), tall ones stay portrait; a tap on the
  comic zooms to full size and a drag moves around it; another tap fits it again.
- The alt text: under the comic in portrait; an **Alt** button opens it in a box in landscape.
- **Favourites**: a ★ on a comic adds or removes it; a Favourites list opens any of them.
- **Sleep screen**: the latest comic (portrait, scaled to fit), its number and title, the fetch
  time; while locked it looks for a new one every 3, 6 or 12 hours (the user's choice, default 6),
  only when that much time has passed.
- **Offline**: the last 20 comics viewed (and the favourites' pages once viewed) open without Wi-Fi.

## Non-goals
- No explanations (explainxkcd), no text search, no interactive comics (they show their title,
  alt text and a QR code of xkcd.com/N to open elsewhere).
- No Worker needed for anything.

## Anti-goals
- More than one JSON and one image request to show a comic.
- Waking or connecting on the sleep screen more often than needed (the lock-screen rules of
  Weather 1.1 apply: set_interval each session, 120 s slack, an early wake held past its aligned
  time with ctx:after, done() when nothing is pending, a due fetch that cannot go out waits).

## Approach (one sensible way)
- **Turn the whole screen per comic** with `ctx.screen:set_orientation` (API 2.18, as Hacker News
  does from Settings): landscape when the comic is wider than tall, else portrait; the buttons and
  layout follow `ctx.screen.width/height`.
- Not chosen: drawing the picture rotated in portrait (the drawing API cannot rotate an image);
  a Worker that rotates it (the app would need a Worker for every comic).

## Decisions
- API: `https://xkcd.com/info.0.json` (latest) and `https://xkcd.com/<n>/info.0.json`
  (num, title, safe_title, alt, img, year, month, day). There is no comic 404.
- Image size: read from the PNG header (IHDR width/height) before decoding. The reader decodes
  PNG/JPEG up to 1024 px a side and keeps 131072 bytes of a response. A comic over either limit
  (or a cut-off body) is fetched once more through `https://images.weserv.nl/?url=<img>&w=1024&h=1024&fit=inside&output=jpg&q=70&filt=greyscale`
  (the public resizer the rss-opds Worker already uses; no account), with "(reduced)" shown.
  Fitting: decode with max_w/max_h of the comic area (portrait 480 x the space above the alt
  text; landscape 800 x 480 minus the title line and buttons); zoom: decode at full size (≤ 1024)
  and draw the visible part with `g:image(img, x, y, { src = { x, y, w, h } })` (2.13), moved by
  the drag. (`g:image` can also rotate with the optional capability `image_transform`; it is not
  known to be on the X4 Pro, and turning the screen keeps the title and buttons upright too.)
- Interactive or image-less comics (no `img`, or not a PNG/JPEG): title, alt text, QR code of
  `https://xkcd.com/<n>/`.
- Storage (private): `cache.txt` the last 20 comics' JSON lines (newest first) with
  `c_<n>.png` (or `.jpg` when reduced) next to each, older ones removed; `favourites.txt`
  "n<TAB>title" lines; `settings.txt` (last comic shown, lockevery hours: 3, 6, 12; 0 off).
- Random: 1..latest without 404. **#**: the system keyboard, digits; out of range: a message.
- Sleep screen (`lockscreen.lua`): API 2.26 lockscreen {enabled, entry, interval_sec 3600,
  net true}; `set_interval(3600)` each session (hourly wakes, the longest allowed); when due,
  the latest JSON, and the image only when its number is new; draws the saved latest comic
  scaled to fit the portrait screen, "xkcd 3323: Meteor Fear", "updated HH:MM". Settings in the
  app: **Sleep screen** Off / every 3 / 6 / 12 hours (set_default / clear_default, the real state
  from is_default each time). The lock network code is in `-- store: cut` blocks.
- Manifest: app_id `xkcd`, display name "xkcd", version 1.0.0, api 2.26, permissions net,
  `requires` pointer. Store build: API 2.18 (set_orientation), no lock network.
- Credit on the About line (Settings) and in the README: "xkcd by Randall Munroe, xkcd.com,
  CC BY-NC 2.5"; the app is free and not affiliated.
- Release: staged in release/v0.24.0 (notes, package, SHA256SUMS), root README, site catalog,
  store export.

- After the builder check (my calls):
  - The image is downloaded with `save = { to = "storage" }` (API 2.2x, up to 262144 B, confirmed
    on the reader) and read back to decode, so comics between 128 and 256 KB need no resizer;
    weserv only for a side over 1024 px or a file over 256 KB (and in the store's 2.18 build, for
    anything over 128 KB).
  - A comic reduced to 1024 px (very tall or wide ones) shows "(reduced)" and its alt box carries
    a QR code of xkcd.com/N for the full size elsewhere.
  - The sleep screen keeps its own files (`lock.txt`, `lock.png`/`.jpg`), apart from the app's
    cache; "new" means a number above the one in lock.txt.
  - Offline: the app opens on the newest saved comic; Prev/Next to one not saved says "Not saved
    on the reader: needs Wi-Fi" and stays; Random picks among the saved ones.
  - A comic smaller than the comic area is drawn at its own size, centred; tap-to-zoom only when
    it was scaled down.
  - Interactive comics: `img` missing or not PNG/JPEG, or the JSON has `extra_parts`: title, alt,
    QR code (no hardcoded list).

## Left to the builder
- Layout and button sets per orientation (gamekit kit helpers, as the other apps).
- PNG IHDR parsing; the zoom's drawing with negative offsets (check the harness and Studio).
- Cache eviction details, the favourites list paging.
