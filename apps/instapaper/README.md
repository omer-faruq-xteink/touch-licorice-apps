# Instapaper — XTOS Licorice mini app (API 2.9)

Reads your [Instapaper](https://www.instapaper.com) articles on the device, as text. The app talks
to the Instapaper API v2 directly with a personal access token: no Worker, no other service. It
works like the RSS app (same list, preview and article screens) and adds what a read-later list
needs: reading progress, **Archive** and **Star**.

## Setup

1. On <https://www.instapaper.com/developers/applications/create> create an application of your
   own (any title, e.g. `<your name> Xteink`; leave it "Owner Only"). On
   <https://www.instapaper.com/developers/applications> generate an **access token** for it.
2. Install `instapaper.xtapp` and open it; it starts on **Settings**. Tap **Access token** and type
   the token with the firmware keyboard. Easier for a long token: open the app once, put the
   reader in USB mode and write a line `token=<your token>` into
   `XTApps/instapaper/files/config.txt` on the SD card.
3. **Back** → **Unread**.

The device must be on Wi-Fi; the app keeps it on while in use and lets it go when you leave.

## Using it

- Menu: **Unread**, **Starred**, **Archive**, **Folders** (your Instapaper folders), **Settings**.
- Lists show twelve articles per screen: title, then site, the day it was saved, how far you read
  (`40%`) and `*` for starred. **Prev / Next**, the side buttons or a swipe page through them;
  Next past the last one loads the next twelve. **Reload** starts over.
- **Long-press** an article for a preview with the saved description: **Prev / Next** step through
  the list, **Open** reads it, **Archive** archives it and moves on to the next one. A tap outside
  the box or Back closes it.
- Articles are laid out with the system fonts (headings, quotes, lists) and open **where you left
  off**: the progress Instapaper keeps (also from KOReader or the website). Leaving an article
  sends the page you reached back to Instapaper. Tap the left third to go back a page, elsewhere
  to go on; the side buttons and swipes work too.
- The last page shows the article's link as a **QR code** (to open it on a phone), then
  **Archive** (archives it and returns to the list) and **Star**.
- **Text size** in Settings: small / default / large, as in RSS.
- **Images in articles** in Settings (off by default): pictures appear where they are in the text,
  as greyscale JPEGs fitted to the screen width, from the free images.weserv.nl resizer, loaded
  for the page on screen only. Icons and tracking pixels are left out; a picture that cannot be
  loaded shows as `[image]`, the text never waits for it.
- Opened articles and lists are saved on the card and open again without a connection.

## Files

- `index.lua` — the app (Instapaper API v2 layer, HTML-to-text, screens).
- `test_instapaper.py` — offline test against a fake Instapaper API: `python -I apps/instapaper/test_instapaper.py`.
