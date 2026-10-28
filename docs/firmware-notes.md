# Net Probe — does XTOS Licorice give mini apps an HTTP API?

## Conclusion (build 26102301): no.

A mini app on this firmware cannot make network requests, and no manifest declaration changes that.
Three independent findings, all from the device and its firmware image:

1. **The `api` manifest field only accepts the built-in level (0.8).** `"api": "1.0"` and `"2.0"`
   both make the installer say "Install failed". So the "XTApp Lua API 2.0" the firmware's own
   `ui.lua` is written against cannot be requested by an app yet.
2. **No manifest key unlocks `net`.** The parser matches `requires` / `required_features` /
   `optional_features` against a fixed 15-name table in the firmware (pointer, up, down, left,
   right, ok, pattern, image_transform, ttf, ui, lockscreen_timer, reader, dialog, frontlight,
   image_decode). `net` is not in it. `requires: ["net"]` is accepted but silently matches nothing.
3. **The Lua context builder never attaches a network member.** The firmware does contain
   `xtapp.net_job`, `xtapp.websocket`, `xtapp.json` and `xtapp.reader` libraries, but they are
   wired to its own cloud sync, font download and reader features. The code that builds the `ctx`
   handed to a mini app has no path that adds `net`, `http`, `json` or `reader`, which is exactly
   what both probe runs showed on screen (all nil).

**So a native RSS reader mini app is not feasible on this build.** The pieces are compiled in, which
suggests a later firmware may open them, but today an app only gets drawing, input, battery/clock,
read-only per-app files and state. The working options for RSS on this device stay: the
`commafeed-opds` worker through the built-in OPDS client, or community firmware (CrossPoint Apps
ships an RSS app).

The probe, variants and the reverse-engineering tools below remain useful for re-checking a future
firmware: re-dump, re-pack, and watch whether `ctx.api` rises above 0.8 or `ctx.net` appears.

---


A Lua mini app for the Xteink X4 Pro stock firmware (XTOS Licorice). It paints the Lua host's API
on screen, page by page: `ctx.api`, `ctx.capabilities`, `ctx.system`, `ctx.sys`, `ctx.ui`,
`ctx.data`, which `require()` names resolve, and every key anywhere in `ctx` whose name looks like
networking or file writing. Nothing is changed on the device: functions are only called when their
name is harmless, with no arguments, inside `pcall`.

Format and tooling come from [kycube/x4pro-emu](https://github.com/kycube/x4pro-emu)
(`docs/licorice-apps.md`), cloned next to this folder.

## 1. Get the Licorice firmware image (one time)

The `.xtapp` must be encrypted for a key that lives in the firmware. The repo does not ship the
image (it would carry its owner's Wi-Fi credentials), so read it from **your** device:

```bash
pip install esptool cryptography
```

Connect the X4 Pro over USB (the stock firmware shows up as USB Serial/JTAG when it is awake and not
in USB disk mode), then dump the 16 MB flash. It is a read, nothing is written:

```bash
python -m esptool --chip esp32s3 read-flash 0 0x1000000 x4pro-flash.bin
```

Afterwards the reader shows its last screen and ignores input until you unplug it and hold the
power button. Keep `x4pro-flash.bin` private: it contains your Wi-Fi password.

## 2. Pack

```bash
python netprobe/pack.py x4pro-flash.bin
```

It finds the slot holding Licorice (project `dragon_example`), writes `licorice-app.bin` beside the
output and produces `netprobe/netprobe.xtapp`. The device-key address was reversed from build
261013; on a newer build the script warns and the install may fail.

## 3. Install and run on the device

1. USB mode on the reader, copy `netprobe.xtapp` to the SD card root.
2. All Files → tap `netprobe.xtapp` → *Install this package?* → OK. Expect the toast **Installed**.
3. Unlock the hidden menu: Settings → About → tap **Model** ten times, each tap under 2 s apart.
4. Open the side drawer (≡) → **Ink App** → **Net Probe**.
5. Tap anywhere to page; photograph every page. The Home pad → *Leave app* exits.

## Findings so far (2026-10-23, device build XTOS Licorice 26102301)

- The device key moved from 261013's address; `pack.py` finds it via the AES-KW IV marker
  (`a6` x 8) that sits 8 bytes before it in DROM (0x3c3610f0 in 26102301).
- **First install attempt: "Install failed."** Cause, from the firmware's string table: the
  manifest parser of this build knows only three permission names, `sys.battery`, `sys.status`,
  `net.http`. The first package also asked for `net.https`, `storage.app`, `storage.user_file`,
  `device.status`, which do not exist in this build and set the parser's reject bit. The manifest
  now uses the three known names.
- The firmware embeds `@public/ui.lua` headed "XTApp Lua API 2.0" and references a document
  `XTApp-Lua-API-2.0.md` (not public). Its Lua object names include `xtapp.net_job`,
  `xtapp.websocket`, `xtapp.json.*`, `xtapp.reader`, `xtapp.reader.stats`, `xtapp.timer`,
  `xtapp.canvas`, `xtapp.font`, `xtapp.image`, `xtapp.layer`, `xtapp.edit`, `hmac_sha256`. So a
  network job API, WebSocket, JSON and a reader hook exist in this build; the probe is there to
  learn how they are reached. In API 2.0 `g` is a userdata, so the probe asks objects by name when
  `pairs` is blocked. The extracted ui.lua text is in `firmware-lua-text.txt`.
- Other manifest keys this build reads: `requires`, `display_names`, `data_files`,
  `required_features`, `optional_features`, `ttf_reserve_kb`, `app_icon_s/l`, `preload_assets`.

## Probe run 1 on the device (2026-10-23, `netprobe.xtapp`, permissions battery/status/net.http)

Installed and ran. Six pages, read off the photos:

- `_VERSION` Lua 5.5; 31 globals, no `print/io/os`, no network global.
- `g` is a plain table (no metatable): `arc circle clear fill_pattern image layer line measure
  measure_text pattern_rect polygon polyline rect round_rect size text text_box` (+ the `ttf_*`
  trio, cut off at the margin).
- `ctx` keys: `api assets capabilities data display fonts gc i18n input invalidate layers lock log
  longtask perf quit request_refresh save screen set_tick_rate state sys system watchdog`.
- `ctx.api = {major=0, minor=8}`. **API 0.8**, not the "2.0" the embedded ui.lua is written for.
- `ctx.capabilities` (9): `app_fonts_v1=false display_full_refresh=true perf_info=false
  ui_components=true ui_image_transform=true ui_patterns=false ui_round_rect=true
  ui_text_layout=true ui_ttf_fonts=true`. Nothing about networking.
- `ctx.sys` (7): `battery()={charging,percent}`, `clock`, `epoch_sec`, `local_sec`, `millis`,
  `status()={bt_on,wifi_conn…}`, `uptime_ms`.
- `ctx.system`: `set_as_lockscreen_app` only. `ctx.longtask` / `ctx.watchdog`: `feed start stop`.
- `ctx.data` (5): `exists open_text read read_text size`. **No write.**
- **`ctx.net`, `ctx.http`, `ctx.json`, `ctx.reader`, `ctx.ui` are all nil.**
- `require` finds nothing: not `@public/ui`, not `xtapp.json` / `xtapp.net_job` /
  `xtapp.websocket` / `xtapp.reader`, no `json`, `socket`, `http`.
- Name hunt in `ctx` to depth 3: only `data.open_text`, `display.request_refresh`,
  `request_refresh`, `save`.
- Event table: `type="touch" gesture="tap" x y time_ms duration_ms`.

Conclusion: on build 26102301, declaring `net.http` alone exposes **no network API**. The
`xtapp.net_job` / `xtapp.websocket` / `xtapp.json` / `xtapp.storage` code is compiled in but gated.
The firmware's string table shows `net`, `storage`, `secret`, `radios` as ctx-level names and a
feature-name list (`x4_3_touch occlusion gray_levels x4_3 lock_timer storage image_decode`), so the
gate is most likely a manifest declaration (`requires` / `required_features` / `optional_features`).

### The manifest parser's literal pool (build 26102301, IROM file offset 0x43e998..0x43ea1c)

Read in order, it is the list of manifest words the parser knows:

```
%d.%d%c  app_id  name  display_name  version  api  display_names  entry  index.lua
display  orientation  landscape  portrait  ttf_reserve_kb
permissions  net  reader  requires
lockscreen  interval_sec  sys.battery  sys.status  net.http
required_features  optional_features  enabled  lockscreen.lua  dek_wrap_alg  dek_wrap_key_id …
```

So: `api` is a manifest key (parsed with `%d.%d%c`, next to `version`), and `requires` takes the
values `net` and `reader`. A second ctx-builder pool (0x43d1f4..0x43d304) references `net`,
`storage`, `secret` together with a richer capability set (`pointer x4_3_touch occlusion
gray_levels x4_3 lock_timer image_decode`). The `net` library's own pool (0x43d63c..0x43d6d8)
holds `xtapp.net_job`, `net job`, `request`, `keep_wifi`, `settings.wifi`, and the strings nearby
are `GET`, `POST`, `content-type`, `no_network`, `err`.

## Round 2 variants (`../netprobe-variants/`, `python netprobe-variants/build.py`)

Each has its own `app_id`; the probe prints `VARIANT <name>  api=<major.minor>  g=<type>` and
`gated tables: …` as the first two lines of page 1.

| file | manifest addition |
|---|---|
| `apitwo.xtapp` | `"api": "2.0"` |
| `apione.xtapp` | `"api": "1.0"` |
| `reqnet.xtapp` | `"requires": ["net"]` |
| `reqobj.xtapp` | `"requires": {"net": true}` |
| `reqrdr.xtapp` | `"requires": ["net", "reader"]` |
| `combo.xtapp` | `"api": "2.0"` + `"requires": ["net","reader"]` + `"optional_features": ["net","storage"]` |
| `probe.xtapp` | x4pro-emu's own probe, control |

Round 1 (`netprobe.xtapp`, `netprobemin.xtapp`) is superseded: `netprobe.xtapp` installed and ran.

### Round 2 results on the device

| variant | result |
|---|---|
| apitwo (`"api": "2.0"`) | **Install failed** |
| apione (`"api": "1.0"`) | **Install failed** |
| combo (api 2.0 + requires + optional_features) | **Install failed** (the api part) |
| reqnet (`"requires": ["net"]`) | installed; api 0.8, gated tables NONE |
| reqobj (`"requires": {"net": true}`) | installed; api 0.8, gated tables NONE |
| reqrdr (`"requires": ["net","reader"]`) | installed; api 0.8, gated tables NONE |
| probe (control) | installed and ran, 9 pages, API as documented for 261013 |

So the `api` field only accepts its default (0.8 or lower), and `requires` is accepted in every
shape without exposing anything.

### Disassembly of the manifest parser (function 0x421396cf..0x4213b176)

Found by scanning IROM for `l32r` into the parser's literal pool (`xref.py`). Right after loading
`requires` (0x42139a56) the code loads DROM 0x3c361070: a **(name, bit) table of 15 feature
names** that `requires` / `required_features` / `optional_features` are matched against:

```
pointer 0x1  up 0x2  down 0x4  left 0x8  right 0x10  ok 0x20  pattern 0x40
image_transform 0x80  ttf 0x100  ui 0x200  lockscreen_timer 0x400  reader 0x800
dialog 0x1000  frontlight 0x2000  image_decode 0x4000
```

`net` is not in this table. The parser references the strings `net` (0x421399e3) and `reader`
(0x421399f3) directly after `permissions` (0x421399d0), so those two are handled by dedicated code
next to the permission check, not by the feature table. Decoding that stretch needs a real Xtensa
disassembler: capstone 6's Xtensa decoder stops on this code, so `xdis.py` wraps Espressif's
`xtensa-esp-elf-objdump`.

## What to look for

- `ctx.api` or `ctx.capabilities` listing anything named `http`, `fetch`, `request`, `net`.
- A `require('@public/...')` line marked `OK`.
- `ctx.data` members beyond `exists / size / read / read_text / open_text` (a write would make
  offline caching possible).
- The name hunt page at the end: `nothing matched` means no networking surface was found at all.

## Toasts and what they mean

| toast | cause |
|---|---|
| Install failed | HMAC/key mismatch: wrong firmware image or a build that moved the key |
| Cannot run yet | code section did not decrypt (IV/key) |
| App error, closed | a Lua error in `index.lua` |

## API 2.9 is reachable (2026-10-24)

A package with `"api": "2.0"` installs and runs if its `permissions` use the API-2 vocabulary:
only `net` and `reader` (the 0.8 names `sys.battery`, `sys.status`, `net.http` make the installer
reject it). The host then reports `ctx.api = {major = 2, minor = 9}` and a much larger surface,
read off the device with the v3 probe (`tools/netprobe/index3.lua`):

- **`g` is not a global**: it arrives only as the second argument of `on_draw(ctx, g)`, a userdata
  whose metatable holds `arc circle clear image line pattern_rect fill_pattern rect round_rect text
  text_box size measure measure_text polygon polyline`. `g:text(x, y, s)` and `g:clear(0)` work as
  in 0.8. `ctx` is still a global and is also passed.
- **Events** are pointer events: `type = "pointer"`, `phase = "up"` (and the other phases),
  `gesture = "tap"`, `x, y, down_x, down_y, time_ms`. `ctx.input.pointer = true`; the key table lists
  `back down left ok right up`. Finger movement is therefore available: freehand drawing is possible.
- **ctx members**: `after api base64 budget capabilities clock defer_full_refresh device dialog
  files fonts frontlight gc hash hex i18n image input invalidate json layers log net package perf qr
  quit random reader save_state screen set_tick state storage system ui url zlib`.
- `ctx.net` (with the `net` permission): `keep_wifi`, `request`, `websocket`.
- `ctx.storage`: `exists list read remove size usage write` — apps can write files.
- `ctx.json`: `decode`, `encode`, `null`. `ctx.input`: `text`, `edit` (native keyboard; `keyboard_h`
  436). `ctx.fonts`: `small`, `medium`, `large` font handles plus `size`. `ctx.ui.create`: the
  native immediate-mode UI. `ctx.reader` (with the `reader` permission): `all_books book_days books
  cover current days summary`. `ctx.system`: `can_open`, `open`.
- `ctx.capabilities`: `dialog frontlight image_decode image_transform pattern reader ui` true,
  `ttf` false.
- `ctx.lockscreen` appears only when the manifest has a `lockscreen` block (see below).
- `require('@public/ui')` still reports module not found.

The statements elsewhere in this document that apps have no network and no file write describe
the API 0.8 path only.

### API 2.9 signatures, as probed on the device (2026-10-24)

Rounds 4–7 of the probe (`tools/probe`) called everything live and painted the host's own error
messages; the Notes and RSS apps are built on the results.

**Calling convention.** Every function on a `ctx.*` table is a *method*: call it colon-style
(`ctx.storage:write(...)`). A dot call shifts the arguments and fails with
`bad argument #2 to '?' (... expected, got no value)`. A few read-only calls (`storage:list()`,
`storage:usage()`, `clock:now()`, `frontlight:get()`) tolerate a dot.

| call | notes |
|---|---|
| `ctx.net:keep_wifi(ms)` | keeps Wi-Fi up for **milliseconds** (a number; `true` is "bad argument"); see probe rounds 10–11 below |
| `ctx.net:request({url, method, body, headers, timeout_ms}, fn)` | returns a job userdata with `cancel`; `fn(ctx, resp)` with `resp.body`, `resp.headers`, status; HTTP, HTTPS and POST verified; missing url → "bad extra argument (string expected)"; bad url → `nil, "invalid_argument"` |
| `ctx.storage:write(name, data)` / `read` / `exists` / `size` / `remove(name)` / `list()` / `usage()` | plain file names only (no `/`, no spaces; an extension is optional), binary data fine, 40 KB fine; quota `{max_bytes = 134217728, max_files = 512}`; missing file → `nil, "not_found"`. `ctx.files` offers the same verbs (`files.path` is a string) |
| `ctx.input:text({title, value}, fn)` | full-screen editor with the firmware keyboard (64-character counter); `fn(ctx, text)` on OK |
| `ctx.input:edit({text, on_change, on_end})` | docked keyboard (436 px) while the app keeps drawing above; returns `{text, set_text, close}`; `on_change(ctx, text)` per key, `on_end(ctx, text, "enter")` on Done |
| `ctx.dialog:confirm({title, text}, fn)` / `ctx.dialog:toast(s)` | system dialog; `fn(ctx, true/false)` |
| `ctx.fonts.small / medium / large` | userdata with `measure(s)`, `ascent`, `line_height` (20 / 24 / 30), `name`; `fonts:size(n)` snaps to these three (`ttf` is false); use as `g:text(x, y, s, {font = f})` or `g:text_box(..., {font = f})` |
| `g:polyline({x1, y1, x2, y2, …})` | one command per stroke chunk; there is a point limit, chunk at ~60 points |
| `g:image(img, x, y, {w =, h =})` | the only working argument order (`g:image(x, y, img)` draws nothing) |
| `g:rect(x, y, w, h, {fill = true})` / `g:text(..., {color = 15})` | the fill draws a solid black box; the text colour is ignored (the text stays black, so it vanishes on a filled box; seen in Slide Puzzle on 26102401). Mark things with frames instead: a large black area also ghosts on e-ink |
| `g:image(white, x, y, {w =, h =})` | **a white area over a drawn screen**: a 1x1 white JPEG (`ctx.image:decode`) stretched to any size draws opaque white, so text under it is hidden (Calendar's event box on 26102401). The way to give a box a white background |
| `ctx.json:decode` of `{"items":[{"tags":["a","b"]}]}` | **the inner list of strings is lost**: RSS list items' `tags` came through empty on 26102401, while the strings, numbers and objects beside it (and the `images` objects of an article) decode fine. Send such a list as one string as well (the Worker's `tag_line`) and read that |
| `ctx.net:request({method = 'PATCH', ...})` | **never answers**: no callback, the request hangs until the app's own timeout (wallabag's Archive and Star, 26102401). GET and POST work; send a PATCH as a POST with `_method=PATCH` / `X-HTTP-Method-Override: PATCH` where the server honours that (Symfony does) |
| `ctx.qr:encode(text)` | QR image for `g:image`, one pixel per module (33×33 for a short URL); draw it scaled with `{w =, h =}` by a whole factor |
| `ctx.image:decode(bytes, opts_table)` | not yet exercised with real image data |
| `ctx.layers:create(w, h)` | layer userdata `{width, height, draw(fn), release}`; `layer:draw(fn)` draws into it (0.8's `draw_with`) |
| `ctx.json:decode(s)` / `encode(v)`, `ctx.base64`, `ctx.hex`, `ctx.hash:sha1/sha256`, `ctx.url:encode/decode`, `ctx.random:uuid()` | as named |
| `ctx.clock:now()` | `{hour, minute, second, epoch_sec, local_sec, date_order, hour12, …}`; `clock:millis()` |
| `ctx.device:battery()` | `{percent, charging, voltage_mv, temperature_c}`; `device.firmware`, `device.model`, `device.id_for_app` |
| `ctx.reader:summary()` / `books()` / `all_books()` / `current()` | reading statistics (streak, books, seconds) and the current book `{title, author, percent, read_sec, format, id}`; needs the `reader` permission |
| `ctx.save_state()`, `ctx.defer_full_refresh(n)`, `ctx.perf:info()` | as named; `ctx.budget = {extend}`. `ctx:defer_full_refresh(0)` every 8 moves did **not** trigger a full refresh (26102401); API 2.9 has no counterpart of 0.8's `ctx.display:full_refresh()` |

**Pointer events**: `phase = down / move / up / hold`, `gesture = tap / long / swipe_*` on the
`up` event. Movement really streams (≈40 moves for two strokes), so freehand drawing works.

**Lock screen.** With a manifest `lockscreen` block (`{"enabled": true, "entry": "lockscreen.lua",
"interval_sec": 60}`) the host exposes `ctx.lockscreen` = `set_default clear_default is_default
set_wallpaper clear_wallpaper is_wallpaper`. `set_default()` pops the system dialog "Set as lock
screen"; after OK the entry is drawn full-screen whenever the device locks and redrawn every
`interval_sec` (verified: a clock on it keeps time). It needs Settings → Display → Off wallpaper on
**Default**. `set_wallpaper(layer)` returns true and `is_wallpaper()` turns true, but the
"Custom" off-wallpaper mode then shows only "Powered off" on this build, so that route is not
usable yet.

**Gotchas.** Lua 5.5 for-loop variables are const (`tools/lualint55.py`). `"•"` is three UTF-8
bytes. Articles of 20 000 characters lay out fine within the 1 MB heap.

### Files, keys and images (probes 8 and 9, 2026-10-24)

- **Sandbox.** `ctx.files.path` is `/AppFiles/<app_id>`; any path outside it (`/sdcard/...`,
  `..`) gives `nil, "invalid_argument"`, so the reader's own `dictionaries/` folder cannot be read.
  The sandbox is the SD-card folder `XTApps/<app_id>/files/`: files copied there over USB are
  visible to `ctx.storage`, and **uninstalling the app deletes the folder** (installing over it
  keeps it). The Dictionary app relies on this.
- **Whole files only.** `storage:read(name, offset, len)` returns the whole file; there is no
  `open` / `read_range`. Large data has to be cut into files the app reads whole (the Dictionary
  uses ~200 KB shards). `ctx.zlib:decompress(s)` exists; `collectgarbage` does not (use `ctx.gc`).
  `ctx.package` = `open_text exists read size image cache_stats` (the package's data section);
  the installer refused a 34 MB package.
- **Ticks.** `ctx.set_tick(ms)` did nothing when called with a dot; call it as `ctx:set_tick(ms)`.
- **Side buttons** arrive as more than one `type = "key"` event per press (press and release or a
  repeat): ignore release phases and the same key again within ~250 ms.
- **Network bodies are binary-safe** (a PNG with zero bytes in its header arrives whole).
- **`ctx.image:decode(bytes)`** decodes **JPEG** (baseline and progressive, grey and colour) to
  an image of its own size (`width`, `height`, `release`); option tables are ignored, so there is
  no scaling on decode. **Decoding a PNG closed the app** in all three tries (78–224 KB files,
  456×342 and larger) — feed the device JPEG only. `g:image(img, x, y)` draws it.
- The free resizer images.weserv.nl answers the device but refuses Cloudflare Workers
  (HTTP 403, "error code: 1106"); the RSS app therefore fetches resized JPEGs itself.

## Probe rounds 10–11: Wi-Fi and request timing (2026-10-25)

Run with Wi-Fi **off** in the device settings, against the rss-opds Worker (`/k/x/api`, a tiny
401 answer that the Worker serves in well under a second; its own timing said 0.3–0.4 s for a
real list).

- The first request after Wi-Fi was down took **7–8 s**: Wi-Fi coming up. Back-to-back HTTPS
  requests then took **~1.4 s** each (a fresh TLS handshake every time, no connection reuse);
  plain HTTP took 0.16 s.
- **`keep_wifi(n)` counts milliseconds.** After `keep_wifi(300)` Wi-Fi was down again after an idle
  gap of 10, 30 and 60 s (the next request took ~7 s). After `keep_wifi(300000)` it was still up
  after 30 and 60 s (~1.4 s). Without any `keep_wifi` call it stayed up for at least 60 s.
- So an app that passes a number meaning seconds (`keep_wifi(120)`) makes Wi-Fi drop right after
  each request. Keep it up with minutes in ms while the app is used; a tiny value (`keep_wifi(1)`)
  lets it go when the app is left.
- With Wi-Fi on in the settings none of this applies: Wi-Fi is already up.


## About 1024 draw commands a screen (2026-10-27, build 26102401)

The host carries out at most about 1024 drawing commands per redraw and silently leaves out the
rest: FreeCell's first version drew its suit signs as runs of filled boxes (1256 commands), and
the screen on the device stopped at command ~1010, in the seventh column, without the buttons.
Count what an on_draw issues (`tools/gamekit/harness.py`: `Game.commands()`) and keep a margin:
draw shapes as one `g:polyline` (one command for many points), merge boxes that repeat on
consecutive rows, and draw stacked things (cards in a column) as one frame with dividing lines.

## Numbers may be 32-bit (2026-10-27, build 26102401)

`string.format('%08x', h)` with `h` kept below 2^32 (`% 4294967296`) failed on the device with
"bad argument", while it works under the 64-bit Lua 5.4 of the tests: the host's Lua is most
likely built with 32-bit integers (as is usual on the ESP32), where 4294967296 is a float and the
result no longer an integer. Keep integer arithmetic below 2^31 (hashes with moduli under 2^24,
epoch seconds plus at most a few years). Not probed directly yet (`math.maxinteger` would say).

## App icons in the Ink App grid (2026-10-26, build 26102401)

The grid reads a package's **icons section** (header offset 0x30, never encrypted, no HMAC) and
needs no feature bit or manifest key. `xtpack.py` packs `APP_DIR/icon.png` into it.

- **XTAB table:** 64-byte header: `XTAB`, u16 version 1 at 4, u32 count at 8 (≤ 8 for icons),
  u32 64 at 12, u32 data start = 64 + 40·count at 16, u32 section length at 20. Then 40-byte
  entries: name[24], u32 offset from the data start, u32 length, u16 width, u16 height, u8 format.
  The reader (around 0x4213a194) takes the entry named exactly `app_icon_s`, else `app_icon_l`.
- **Image (decoder 0x42137330, validator 0x42136918):** a 24-byte header: `XIC\0`, u16 width at 4,
  u16 height at 6, u8 1 at 8, u8 format at 9, u8 planes at 10, u8 0 at 11, u8 alpha kind at 14,
  u8 alpha flag at 15, u32 pixel-data size at 16, which must match exactly. Formats are 1 = 1 bpp
  (planes 1, ceil(w/8)·h bytes), 4 = 2 bpp as two 1-bit planes, and 16 = 4 bpp packed
  (ceil(w/2)·h). Alpha kinds 1–3 add a 1-bit, 4-bit or 8-bit mask.
- **Tested on the device (1 bpp, rows MSB first):** a **set bit is drawn black**. The icon is
  **scaled to the slot** (64×64 and 96×96 showed at the same size) and clipped to its rounded
  corners.
