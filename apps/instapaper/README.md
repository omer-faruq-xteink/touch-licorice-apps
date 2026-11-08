# Instapaper — XTOS Licorice mini app (API 2.18)

**Needs firmware with API 2.18** (XT Licorice 26110201 or later): older firmware refuses to install it
and asks for an update.

Reads your [Instapaper](https://www.instapaper.com) articles on the device, as text. The app talks
to the Instapaper API v2 directly with a personal access token: no Worker, no other service. It
works like the RSS app (same list, preview and article screens) and adds what a read-later list
needs: reading progress, **Archive** and **Star**.


**Optional: questions to an AI** about the article you are reading (Claude, OpenAI, Gemini,
OpenRouter, Groq, Mistral, DeepSeek, Ollama or any OpenAI-compatible server, with your own key).
It is **off by default**, and while it is off nothing of it shows anywhere. See
[AI questions (optional)](#ai-questions-optional).

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
- **Long-press** an article for a preview with the saved description, in a box of one fixed size
  that takes the screen (the list's buttons are hidden meanwhile): **Prev / Next** step through
  the list, **Open** reads it, **Archive** archives it and moves on to the next one. A tap outside
  the box or Back closes it.
- Articles are laid out with the system fonts (headings, quotes, lists) and open **where you left
  off**: the progress Instapaper keeps (also from KOReader or the website). Leaving an article
  sends the page you reached back to Instapaper: one request per article, not per page. If you
  leave the app from inside an article, or the request fails, the position is kept on the card and
  sent at the next start. Tap the left third to go back a page, elsewhere to go on; the side
  buttons and swipes work too.
- The last page shows the article's link as a **QR code** (to open it on a phone), then
  **Archive** (archives it and returns to the list) and **Star**.
- **Text size** in Settings: small / default / large, as in RSS.
- **Screen** in Settings: portrait or landscape. The app turns at once and
  opens that way next time; in landscape a list page holds 6 rows (the server is asked for 6 at a
  time), the menu and Settings take two columns, and an open article is laid out again at about the
  same place.
- **Images in articles** in Settings (off by default): pictures appear where they are in the text,
  as greyscale JPEGs fitted to the screen width, from the free images.weserv.nl resizer, loaded
  for the page on screen only. Icons and tracking pixels are left out; a picture that cannot be
  loaded shows as `[image]`, the text never waits for it.
- Opened articles and lists are saved on the card and open again without a connection. The 100
  most recently opened articles stay; older copies are removed, and an archived article's copy
  goes at once. **Articles saved offline** in Settings shows how many there are; tap it twice to
  delete them all (lists, settings and reading progress stay).

## AI questions (optional)

Nothing here is needed to read your articles. **AI is off by default**; while it is off (or not set
up) the app shows no AI button anywhere and sends nothing to any AI service. It works as in the
RSS app; each app keeps its own settings, and none needs another installed.

- **Settings → AI**: **AI** on / off; **Service** from a list (Claude, OpenAI, Gemini, OpenRouter,
  Groq, Mistral, DeepSeek, Ollama on your network, or **Other** for any OpenAI-compatible address);
  **Address** (empty: the service's own), **Key**, **Model** (empty: the service's starting model),
  **Answer in** (a language), **Extra parameters (JSON)** merged into every request (e.g.
  `{"reasoning_effort":"minimal"}`), and **Connection: Tap to test**.
- A long key is easier over USB: put `ai.txt` into `AppFiles/instapaper/` with lines such as
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
kept in `AppFiles/instapaper/ai_buttons.txt`, one `Label | question` a line, which you can also edit
over USB.

## Files

- `src/main.lua` — the app (Instapaper API v2 layer, HTML-to-text, screens); `bundle.py` joins it with
  `tools/gamekit/ai.lua` and `aiui.lua` (the optional AI questions) into `index.lua`.
- `test_instapaper.py` — offline test against a fake Instapaper API: `python -I apps/instapaper/test_instapaper.py`.
