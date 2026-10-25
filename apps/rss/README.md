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
   token. Each field opens the firmware's keyboard. **Text size** (small / default / large) sets
   the type of articles and previews; tap it to change. **Images in articles** (off by default)
   shows article pictures where they are in the text.
3. **Back** → **Unread**.

The device must be on Wi-Fi; the app asks the host to keep it on while in use.

## Several CommaFeed accounts

If your Worker serves more than one CommaFeed account (`COMMAFEED_API_KEY_2` etc., see the
rss-opds README), the menu starts with one folder per account, named by the Worker's labels.
Each folder holds the usual Unread / Starred / All / Feeds; lists, articles, the offline cache and
mark-as-read stay in that account. **Accounts** (or Back) returns to the folders. With one account,
or with an older Worker, the app looks exactly as before. Nothing to set in the app.

## Using it

- Menu: **Unread**, **Starred**, **All**, **Feeds** (one subscription at a time), **Settings**.
- Lists show twelve articles per screen: title, feed and date; `*` marks unread; the header shows
  which rows are on screen and how many are loaded (`13-24 / 24+`, `+` = more on the server).
  **Prev / Next**, the side buttons or a swipe scroll through what is loaded; Next past the last
  loaded article fetches the next twelve and appends them, so the list simply continues.
  **Reload** starts over at the newest. Up to 240 rows are kept.
- **Long-press** an article for a preview: the whole title, feed and date, and the feed's summary
  (up to 400 characters, from the Worker's list). **Prev / Next** in the box, the side buttons or
  a swipe move to the previous / next article's preview; Next on the last loaded article loads the
  next page and shows its first article. **Open** reads it, and Back from that article returns to
  the preview (an article opened straight from the list returns to the list); **Close**, a tap outside the box or
  the Back key returns to the list, on the screen of the article you were looking at (also when
  you close while the next page is still loading). Previews fetch nothing else and mark nothing
  read.
- Tap an article: it is fetched as text (and marked read in CommaFeed), laid out with the three
  system fonts — title large, feed and date small, headings large, quotes and list items indented —
  and paged. Tap the right / left third of the screen, use the side buttons or swipe to turn pages.
- At start the app asks the account list at once; that small request also brings Wi-Fi up for
  the first list. Lists and feed answers carry the account list too and keep it current.
- Each article ends with "Source:" and its link as a QR code to open on a phone (just the address
  if no QR can be made).
- Wi-Fi is kept up while the app is used (5 minutes from the last tap) and let go when you leave,
  so pages load in about a second and a half even with Wi-Fi off in the device settings.
- Network requests run one at a time (the device does not carry two at once). One with no
  answer is cancelled after 30 s, 60 s for an article; Reload gives up a stuck one at once.
- A list that fails to load is tried once more; if it still fails, the screen says why (and
  Reload tries again) rather than showing an empty list.
- Everything fetched is cached in the app's storage (lists, feed list, article texts), so lists
  and already-opened articles work offline, marked "(offline)".

## Images

With **Images in articles** on, pictures appear where they are in the text, as greyscale JPEGs at
most 456 px wide (the reader decodes JPEG but runs out of memory on PNG). The app fetches each
one from the free images.weserv.nl resizer itself; the Worker only reads the first bytes of each
original to know the size in advance, so the page layout never shifts. When the size cannot be
read, the picture is fitted into a 456×342 box. Only the pictures of the page on screen are
downloaded, one after the other, after the text; until then a frame marks their place. If the
resizer cannot deliver a picture, it shows as `[image]` and the article reads normally. Icons and
emoji are left out. Needs the updated rss-opds Worker.

## Build

```bash
python xtpack.py apps/rss
python -I apps/rss/test_rss.py   # offline, Lua 5.4 via lupa, fake Worker
```

Verified on an X4 Pro running Licorice 26102301 (2026-10-24) against a deployed Worker: HTTPS,
JSON decoding, list paging, article layout, Basic auth and path-token auth, offline cache.

Images are not shown (the screen is 1-bit); a later version may fetch them through the Worker.
