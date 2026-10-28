# wallabag — XTOS Licorice mini app (API 2.9)

Reads your [wallabag](https://wallabag.org) articles on the device, as text. wallabag is an open
read-later service: your own server, or a hosted one (wallabag.it, or a free public instance).
The app talks to the server's API directly: no Worker, no other service. It is built from the
Instapaper app (same list, preview and article screens) with **Archive**, **Star** and **Tags**.

## Setup

1. In wallabag on the web, open **API clients management** (in the menu, or
   `https://<your server>/developer`) and **Create a new client** (any name). Note its
   **Client ID** and **Client secret**.
2. Install `wallabag.xtapp` and open it; it starts on **Settings**. Fill in **Server** (e.g.
   `app.wallabag.it`, or `https://wallabag.example.org`; `http://` works for a server on your own
   network), **Client ID**, **Client secret**, **Username** and **Password** with the firmware
   keyboard. Easier: open the app once, put the reader in USB mode and write the lines
   `host=...`, `client_id=...`, `client_secret=...`, `username=...`, `password=...` into
   `XTApps/wallabag/files/config.txt` on the SD card.
3. **Back**: the app signs in. Then **Unread**.

The app signs in with OAuth: the password gets an access token (an hour) and a refresh token
(about two weeks), kept in `token.txt`; later the refresh token gets a new one. The password is
kept in `config.txt` to sign in again once the refresh token has run out; leave it empty and
the app asks for it then. Changing any sign-in setting signs in afresh.

The device must be on Wi-Fi; the app keeps it on while in use and lets it go when you leave.

## Using it

- Menu: **Unread**, **Starred**, **Archive**, **Tags**, **Settings**.
- Lists show twelve articles per screen: title, then site, the day it was saved, the reading
  time, how far you read (`40%`) and `*` for starred. **Prev / Next**, the side buttons or a
  swipe page through them; Next past the last one loads the next twelve. **Reload** starts over.
- **Long-press** an article for a preview (site, date, reading time, tags): **Prev / Next** step
  through the list, **Open** reads it, **Archive** archives it and moves on to the next one.
- Articles are laid out with the system fonts (headings, quotes, lists) from the text wallabag
  saved. wallabag keeps no reading position, so the page you reached is kept on the reader and
  the article opens there again (the last 200 articles).
- The reader takes at most 128 KB per answer: a longer article comes as wallabag's plain-text
  export instead (no headings or pictures; the status line says "text only"). A server older
  than 2.4 sends every article's text with the list too; the app then asks 3 at a time.
- The last page shows the article's link as a **QR code**, then **Archive** and **Star** (tap
  **Starred** to remove the star).
- **Text size** and **Images in articles** in Settings, as in Instapaper: pictures come as
  greyscale JPEGs from the free images.weserv.nl resizer, for the page on screen only.
- Opened articles and lists are saved on the card and open without a connection. The 100 most
  recently opened articles stay; an archived article's copy goes at once. **Articles saved
  offline** in Settings: tap twice to delete them all.

## Files

- `index.lua` — the app (OAuth and the wallabag API v2, HTML-to-text, screens).
- `test_wallabag.py` — offline test against a fake wallabag server: `python -I apps/wallabag/test_wallabag.py`.
