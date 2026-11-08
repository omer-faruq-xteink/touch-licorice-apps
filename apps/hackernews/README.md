# Hacker News — XTOS Licorice mini app (API 2.18)

**Needs firmware with API 2.18** (XT Licorice 26110201 or later): older firmware refuses to install it
and asks for an update.

[Hacker News](https://news.ycombinator.com) on the reader. Needs Wi-Fi; read-only (no login, no
voting).

**Optional: questions to an AI** about a story and its comments (Claude, OpenAI, Gemini,
OpenRouter, Groq, Mistral, DeepSeek, Ollama or any OpenAI-compatible server, with your own key).
It is **off by default**, and while it is off nothing of it shows anywhere. See
[AI questions (optional)](#ai-questions-optional).

- **Top, New, Best, Ask, Show** in HN's own order (the official Firebase API), 24 stories at a
  time: Next past the last one loads more. **Find** searches all stories (Algolia's HN search).
  The last list of each tab is kept, so the app opens with something to read.
- **A story** opens with its title, points, author and age, then its text (Ask HN), or the
  linked article as text through your [rss-opds](https://github.com/omer-faruq-xteink/rss-opds)
  Worker, the one the RSS app uses, with its pictures where they are in the text (Settings:
  Pictures in articles, on by default). Every linked story ends with its address as a QR code,
  to open on a phone.
- **Comments** (the button on a story, or a long press on a story in the list) come level by
  level in HN's order: the replies to the story, each with its author and age; tap
  "n replies >" to read the replies to that comment, Back to come up, Top for the first level.
  They load one by one while you read (two pages ahead), so long threads start at once.
- A tap on a page turns it: the left third back, elsewhere on (in comments, tap "n replies >" to
  go down instead). Swipes and the side buttons turn pages too; three text sizes in Settings.

**Settings**, the same values as in the RSS app:

- **Worker host**: the Worker's address alone, e.g. `rss-opds.<you>.workers.dev` (`https://` and
  a trailing `/` may be typed too; they are left out).
- **Path token** (the part after `/k/`) or **user:password** for Basic auth, whichever your Worker
  uses (`OPDS_TOKEN`, or `OPDS_USER` / `OPDS_PASS`); the other stays empty.
- **Screen**: portrait or landscape. The app turns at once and opens that
  way next time; in landscape a list page shows 4 stories, Settings takes three columns, and an
  open story or comment page is laid out again at about the same place.

The [Worker setup](https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/worker/) page walks through a Worker for Hacker News alone (no CommaFeed account
needed) and works out these two values. The article text needs the Worker's `/api/read` route (rss-opds after October 2026: `git pull`,
`npx wrangler deploy`) and one of its full-text services (Instaparser, Diffbot or Instapaper);
without it the app says why and shows the QR code.

## AI questions (optional)

Nothing here is needed to read Hacker News. **AI is off by default**; while it is off (or not set
up) the app shows no AI button anywhere and sends nothing to any AI service. The settings are the
RSS app's (each app keeps its own; neither needs the other installed):

- **Settings → AI**: **AI** on / off; **Service** from a list (Claude, OpenAI, Gemini, OpenRouter,
  Groq, Mistral, DeepSeek, Ollama on your network, or **Other** for any OpenAI-compatible address);
  **Address** (empty: the service's own), **Key**, **Model** (empty: the service's starting model),
  **Answer in** (a language), **Extra parameters (JSON)** merged into every request (e.g.
  `{"reasoning_effort":"minimal"}`, or for Gemini 2.5 Flash without thinking
  `{"generationConfig":{"thinkingConfig":{"thinkingBudget":0}}}`), and **Test the connection**.
- A long key is easier over USB: put `ai.txt` into `AppFiles/hackernews/` with lines such as
  `service=deepseek`, `key=...`, `model=...`. Opening Settings → AI (or the app) takes it in and
  **deletes the file**.

With AI on, a story and its comments get an **AI** button. It opens the ready questions:

- **Send** (tap to change, remembered): what goes with the questions —
  **Article + comments**, **Article** (the story's text: the article through your Worker, or an
  Ask HN post), **Comments** (the discussion only), or **Link + comments** (the article's address
  instead of its text, cheaper; the model sees only the address).
- **Summarize**, **Key points**, **Explain simply**, **Background**, **What is missing?** (not with
  Comments alone), **The discussion** and **Disagreements** (when comments go), **Translate** (when
  an answer language is set), **Your question**, and **Start over**.

The answer is laid out and paged like a story; **More** returns to the ready questions (with **Your question** for a follow-up; the whole
conversation goes along), Back returns to the story or comments. The
conversation stays while that story is open.

The comments are fetched all at once (Algolia's search, 200 a request, at most 600) the first time
they are to be sent, and written out as "author: text" with replies indented under the comment
they answer, the first level in HN's order; long discussions are cut (about 50 KB with the
article, as the reader sends at most 64 KB). A reply must come within 60 s; a failed one says why
and the question can be asked again.

Files: `src/hn.lua` (the APIs' addresses, HN's HTML as text, the comments as text for the AI, word
wrap), `src/main.lua` (on `tools/gamekit`), `tools/gamekit/ai.lua` (the AI part, shared with RSS),
`bundle.py`, `test_hackernews.py` and `test_ai.py` (`python -I apps/hackernews/test_hackernews.py`,
`python -I apps/hackernews/test_ai.py`).

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
kept in `AppFiles/hackernews/ai_buttons.txt`, one `Label | question` a line, which you can also edit
over USB.
