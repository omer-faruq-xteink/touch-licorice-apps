# Hacker News — XTOS Licorice mini app (API 2.9)

[Hacker News](https://news.ycombinator.com) on the reader. Needs Wi-Fi; read-only (no login, no
voting).

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

The article text needs the Worker's `/api/read` route (rss-opds after October 2026: `git pull`,
`npx wrangler deploy`) and one of its full-text services (Instaparser, Diffbot or Instapaper);
without it the app says why and shows the QR code.

Files: `src/hn.lua` (the APIs' addresses, HN's HTML as text, word wrap), `src/main.lua` (on
`tools/gamekit`), `bundle.py`, `test_hackernews.py` (`python -I apps/hackernews/test_hackernews.py`).
