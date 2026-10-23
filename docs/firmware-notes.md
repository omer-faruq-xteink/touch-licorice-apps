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
4. Open the side drawer (≡) → **Mini Apps** → **Net Probe**.
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
