# RSS — XTOS Licorice mini app (API 2.9)

Reads your [CommaFeed](https://www.commafeed.com) articles on the device, as text, through the
[rss-opds](https://github.com/omer-faruq-xteink/rss-opds) Cloudflare Worker (free plan). The
Worker already publishes the account as an OPDS catalog for the stock reader; this app uses its
JSON API instead, so articles open inside the app without downloading an EPUB, with the Worker's
optional full-text extraction.

## Setup

1. Deploy rss-opds (its README, ten minutes) and note the Worker host, e.g.
   `rss-opds.<you>.workers.dev`, and either the path token (`OPDS_TOKEN`) or the Basic-auth
   user and password (`OPDS_USER` / `OPDS_PASS`).
2. Install `rss.xtapp`, open it; it starts on **Settings**. Fill **Host**, then **Token** (the part
   after `/k/`) or **user:password**, and switch **Full text** on if the Worker has a sanitizer
   token. Each field opens the firmware's keyboard.
3. **Back** → **Unread**.

The device must be on Wi-Fi; the app asks the host to keep it on while in use.

## Using it

- Menu: **Unread**, **Starred**, **All**, **Feeds** (one subscription at a time), **Settings**.
- Lists show twelve articles per screen: title, feed and date; `*` marks unread; the header shows
  which rows are on screen and how many are loaded (`13-24 / 24+`, `+` = more on the server).
  **Prev / Next**, the side buttons or a swipe scroll through what is loaded. After the last
  article comes a **Load more** row: tapping it — or Next when nothing else is left — fetches the
  next twelve and appends them. **Reload** starts over at the newest. Up to 240 rows are kept.
- **Long-press** an article for a preview: the whole title, feed and date, and the feed's summary
  (up to 400 characters, from the Worker's list). **Open** reads it, **Close**, a tap outside the
  box or the Back key returns to the list. Nothing is fetched and nothing is marked read.
- Tap an article: it is fetched as text (and marked read in CommaFeed), laid out with the three
  system fonts — title large, feed and date small, headings large, quotes and list items indented —
  and paged. Tap the right / left third of the screen, use the side buttons or swipe to turn pages.
- Everything fetched is cached in the app's storage (lists, feed list, article texts), so lists
  and already-opened articles work offline, marked "(offline)".

## Build

```bash
python xtpack.py apps/rss
python -I apps/rss/test_rss.py   # offline, Lua 5.4 via lupa, fake Worker
```

Verified on an X4 Pro running Licorice 26102301 (2026-10-24) against a deployed Worker: HTTPS,
JSON decoding, list paging, article layout, Basic auth and path-token auth, offline cache.

Images are not shown (the screen is 1-bit); a later version may fetch them through the Worker.
