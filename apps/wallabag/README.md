# wallabag — XTOS Licorice mini app (API 2.18)

**Needs firmware with API 2.18** (XT Licorice 26110201 or later): older firmware refuses to install it
and asks for an update.

Reads your [wallabag](https://wallabag.org) articles on the device, as text. wallabag is an open
read-later service: your own server, or a hosted one (wallabag.it, or a free public instance).
The app talks to the server's API directly: no Worker, no other service. It is built from the
Instapaper app (same list, preview and article screens) with **Archive**, **Star** and **Tags**.


**Optional: questions to an AI** about the article you are reading (Claude, OpenAI, Gemini,
OpenRouter, Groq, Mistral, DeepSeek, Ollama or any OpenAI-compatible server, with your own key).
It is **off by default**, and while it is off nothing of it shows anywhere. See
[AI questions (optional)](#ai-questions-optional).

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
- **Screen** in Settings: portrait or landscape. The app turns at once and
  opens that way next time; in landscape a list page holds 6 rows (the server is asked for 6 at a
  time), the menu and Settings take two columns, and an open article is laid out again at about the
  same place.
- Opened articles and lists are saved on the card and open without a connection. The 100 most
  recently opened articles stay; an archived article's copy goes at once. **Articles saved
  offline** in Settings: tap twice to delete them all.

## AI questions (optional)

Nothing here is needed to read your articles. **AI is off by default**; while it is off (or not set
up) the app shows no AI button anywhere and sends nothing to any AI service. It works as in the
RSS app; each app keeps its own settings, and none needs another installed.

- **Settings → AI**: **AI** on / off; **Service** from a list (Claude, OpenAI, Gemini, OpenRouter,
  Groq, Mistral, DeepSeek, Ollama on your network, or **Other** for any OpenAI-compatible address);
  **Address** (empty: the service's own), **Key**, **Model** (empty: the service's starting model),
  **Answer in** (a language), **Extra parameters (JSON)** merged into every request (e.g.
  `{"reasoning_effort":"minimal"}`), and **Connection: Tap to test**.
- A long key is easier over USB: put `ai.txt` into `AppFiles/wallabag/` with lines such as
  `service=deepseek`, `key=...`, `model=...`. Opening Settings → AI (or the app) takes it in and
  **deletes the file**.
- With AI on, an open article has one more button in its bar, **AI**: the ready questions
  (**Summarize**, **Key points**, **Explain simply**, **Background**, **What is missing?**,
  **Translate** when an answer language is set) and **Your question**. The answer is laid
  out and paged like the article; **More** returns to the ready questions (with **Your question** for a follow-up; the whole
conversation goes along) (and **Start over**), Back returns to the article. The article's title, link and text
  as shown (the first 24 KB) go to the service you chose, nowhere else.

**Web search.** At the top of the ready questions, **Web search: off / on** (where the service has
a web search): while it is on, every question searches the web first, the ready ones (Background,
What is missing?, your own buttons) and your own, the first and the follow-ups; it is off again for
each new article. Claude, OpenAI, Gemini and OpenRouter search themselves; for DeepSeek the model first writes a short search
query from the whole article, the conversation and the question, the app runs DeepSeek's search
with it, and the results go with the question (one more request, which begins like the answer's,
so DeepSeek serves the article from its cache the second time). Groq, Mistral, Ollama and
Other have no web search here, so the switch does not show. Searches cost extra at the service.

**My buttons** (Settings → AI): up to six questions of your own, shown after the ready ones. Tap
one to change it (empty it to delete it), or **Add a button**, as `Label | question`. They are
kept in `AppFiles/wallabag/ai_buttons.txt`, one `Label | question` a line, which you can also edit
over USB.

## Files

- `icon.png`, from `logo-square.svg`: the [wallabag logo](https://github.com/wallabag/logo) by Maylis
  Agniel, Free Art License 1.3 (see NOTICE.md).
- `src/main.lua` — the app (OAuth and the wallabag API v2, HTML-to-text, screens); `bundle.py` joins
  it with `tools/gamekit/ai.lua` and `aiui.lua` (the optional AI questions) into `index.lua`.
- `test_wallabag.py` — offline test against a fake wallabag server: `python -I apps/wallabag/test_wallabag.py`.
