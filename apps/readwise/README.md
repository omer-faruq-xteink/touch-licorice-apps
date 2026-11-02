# Readwise — XTOS Licorice mini app (API 2.9)

Reads your [Readwise Reader](https://readwise.io/read) library on the device, as text. The app
reads Reader directly with a personal access token. It works like the Instapaper app (same list,
preview and article screens) and adds Reader's locations, tags and feed.

Changes (**Archive**, **Later** / **Inbox**, **tags**, marking a document seen) are `PATCH`es to
Reader's update endpoint:

- **Firmware with API 2.18** (XT Licorice 26110201 and later): the app sends them to Reader itself
  with your access token. No Worker is needed.
- **Older firmware** sends only GET and POST, so changes go through the
  [rss-opds](https://github.com/omer-faruq-xteink/rss-opds) Worker, the one the RSS app uses: the
  app posts the change to the Worker's `/readwise/update/<id>` route, which passes it on to Reader
  as `PATCH`. Without the Worker in Settings the app only reads there.

## Setup

1. Get your access token at <https://readwise.io/access_token>.
2. Install `readwise.xtapp` and open it; it starts on **Settings**. Tap **Access token** and type
   the token with the firmware keyboard. Easier for a long token: open the app once, put the
   reader in USB mode and write a line `token=<your token>` into
   `XTApps/readwise/files/config.txt` on the SD card.
3. Only on firmware before 2.18, for changes: **Worker for changes on firmware before 2.18** is your Worker's address (`rss.example.workers.dev`, or
   with its path token `rss.example.workers.dev/k/<token>`), **Worker user:password** the same
   `user:password` the RSS app uses. The Worker must be a version with the Readwise relay; it
   needs no CommaFeed account for it. The [Worker setup](https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/worker/) page walks through one for
   Readwise alone and works out both values.
4. **Back** → **Inbox**.

The device must be on Wi-Fi; the app keeps it on while in use and lets it go when you leave. The
menu's second line says how changes go: `changes go straight to Readwise` (firmware 2.18),
`changes go through your Worker`, or `read-only: no Worker in Settings`.

## Using it

- Menu: **Inbox**, **Later**, **Shortlist**, **Archive**, **Feed** (your RSS and newsletter feed
  in Reader), **Tags** (your Reader tags; tap one for its documents), **Settings**.
- Lists show twelve documents per screen: title, then site, the day it was saved, how far you
  read (`40%`) and `· unseen` for documents never opened. **Prev / Next**, the side buttons or a
  swipe page through them; Next past the last one loads the next twelve. **Reload** starts over.
- **Long-press** a document for a preview with its tags and Reader's summary: **Prev / Next** step
  through the list, **Open** reads it, **Archive** archives it and moves on to the next one, and a
  second row has **Later** and **Tags**. In Later the buttons are Archive and **Inbox**; in the
  Archive, Inbox and Later. A tap outside the box or Back closes it.
- **Tags** opens the keyboard with the document's tags, comma-separated; what you type replaces
  them (an empty box removes them all).
- Documents open on the page you reached last time on the reader, or else where Reader's own
  progress points (from the app or the website). Reader's API cannot set reading progress, so the
  position stays on the card. Opening an unseen document marks it seen in Reader.
- The last page shows the source's link as a **QR code**, then the two moves and **Tags**.
- **Text size** and **Images in articles** in Settings, as in Instapaper.
- **Screen** (firmware with API 2.18): portrait or landscape. The app turns at once and opens that
  way next time; in landscape a list page holds 6 rows (Reader is asked for 6 at a time), the menu
  and Settings take two columns, and an open article is laid out again at about the same place.
- Opened documents and lists are saved on the card and open again without a connection. The 100
  most recently opened documents stay; an archived document's copy goes at once. **Articles saved
  offline** in Settings shows how many there are; tap it twice to delete them all.
- Reader allows 20 list requests a minute; paging very fast can answer `Readwise: too many
  requests, wait a minute`.

Highlights are not shown, and Shortlist cannot be set (Reader's API does not take it).

## Files

- `index.lua` — the app (Reader API layer, the relay for changes, HTML-to-text, screens).
- `test_readwise.py` — offline test against a fake Reader API and relay: `python -I apps/readwise/test_readwise.py`.
