# Readwise — XTOS Licorice mini app (API 2.18)

Reads your [Readwise Reader](https://readwise.io/read) library on the device, as text. The app
reads Reader directly with a personal access token. It works like the Instapaper app (same list,
preview and article screens) and adds Reader's locations, tags and feed.

Changes (**Archive**, **Later** / **Inbox**, **tags**, marking a document seen) are `PATCH`es to
Reader's update endpoint, sent with the same token.

**Needs firmware with API 2.18** (XT Licorice 26110201 or later): the manifest asks for 2.18, so
older firmware refuses to install it and asks for an update. (Up to 0.2.0 the app also ran on older
firmware, where changes went through the rss-opds Worker's `/readwise` relay; no Worker is used
now.)


**Optional: questions to an AI** about the article you are reading (Claude, OpenAI, Gemini,
OpenRouter, Groq, Mistral, DeepSeek, Ollama or any OpenAI-compatible server, with your own key).
It is **off by default**, and while it is off nothing of it shows anywhere. See
[AI questions (optional)](#ai-questions-optional).

## Setup

1. Get your access token at <https://readwise.io/access_token>.
2. Install `readwise.xtapp` and open it; it starts on **Settings**. Tap **Access token** and type
   the token with the firmware keyboard. Easier for a long token: open the app once, put the
   reader in USB mode and write a line `token=<your token>` into
   `XTApps/readwise/files/config.txt` on the SD card.
3. **Back** → **Inbox**.

The device must be on Wi-Fi; the app keeps it on while in use and lets it go when you leave. The
menu's second line says `changes go straight to Readwise`, or `no access token: open Settings`.

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
- **Screen**: portrait or landscape. The app turns at once and opens that
  way next time; in landscape a list page holds 6 rows (Reader is asked for 6 at a time), the menu
  and Settings take two columns, and an open article is laid out again at about the same place.
- **Books, PDFs and long articles** are read in parts of a few dozen pages (`part 2` in the line
  under the title). **Next** on the last page of a part, or the **Next part** button there, opens
  the next one; **Prev** on the first page goes back to the end of the one before; the app opens
  again at the part and page you left. Reader sends an EPUB or a PDF as one piece of HTML, often
  megabytes, which the reader cannot hold at once: the app has it saved to
  `AppFiles/readwise/doc_<id>.json` and reads it a part at a time. The files of the 5 documents
  opened last stay (archiving one, or deleting the offline copies in Settings, removes it); an
  older one is fetched again when needed. A PDF that Reader has no text for shows its summary.
- Opened documents and lists are saved on the card and open again without a connection. The 100
  most recently opened documents stay; an archived document's copy goes at once. **Articles saved
  offline** in Settings shows how many there are; tap it twice to delete them all.
- Reader allows 20 list requests a minute; paging very fast can answer `Readwise: too many
  requests, wait a minute`.

Highlights are not shown, and Shortlist cannot be set (Reader's API does not take it).

## AI questions (optional)

Nothing here is needed to read your articles. **AI is off by default**; while it is off (or not set
up) the app shows no AI button anywhere and sends nothing to any AI service. It works as in the
RSS app; each app keeps its own settings, and none needs another installed.

- **Settings → AI**: **AI** on / off; **Service** from a list (Claude, OpenAI, Gemini, OpenRouter,
  Groq, Mistral, DeepSeek, Ollama on your network, or **Other** for any OpenAI-compatible address);
  **Address** (empty: the service's own), **Key**, **Model** (empty: the service's starting model),
  **Answer in** (a language), **Extra parameters (JSON)** merged into every request (e.g.
  `{"reasoning_effort":"minimal"}`), and **Connection: Tap to test**.
- A long key is easier over USB: put `ai.txt` into `AppFiles/readwise/` with lines such as
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
kept in `AppFiles/readwise/ai_buttons.txt`, one `Label | question` a line, which you can also edit
over USB.

## Files

- `src/main.lua` — the app (Reader API layer, changes as PATCH, HTML-to-text, screens); `bundle.py`
  joins it with `tools/gamekit/ai.lua` and `aiui.lua` (the optional AI questions) into `index.lua`.
- `test_readwise.py` — offline test against a fake Reader API: `python -I apps/readwise/test_readwise.py`.
