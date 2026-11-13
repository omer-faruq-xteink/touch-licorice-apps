# Hacker News 1.3.0: For you and a sleep-screen digest

## Intent
The Xteink team asked for "a personalized news feed or push notifications". The reader has no push
service, and HN has no personal recommendations (its API is the same lists for everyone, no
sign-in). So: a **For you** list made from topics the user chooses, and a **sleep-screen digest**
of it that refreshes while locked (API 2.26 lock-screen network, as Weather 1.1 does). The user's
condition: it must not strain the device.

## Goals
- A **For you** tab: recent stories matching any of the user's topics, best matches first, muted
  words and sites left out.
- Topics are explicit: typed by the user, or added from a story with **More like this** (pick a
  word of its title). **Less like this** mutes a word of the title or the story's site.
- The topics and mutes can be seen and removed in the app, and edited as a text file over USB.
- The sleep screen can show the top For you stories, fetched again while locked at an interval the
  user chooses, only when that interval has passed.

## Non-goals
- No learning from what is opened (the user chose explicit topics: predictable, no drift).
- No HN account, votes or favourites; no notifications.
- No change to Top, New, Best, Ask, Show, Find, stories, comments or AI.

## Anti-goals
- More than one request for a For you page or a sleep-screen refresh.
- Ranking hundreds of stories on the reader.
- Waking or connecting more often than the chosen interval (the lock-screen rules from Weather /
  Calendar / Tasks apply: set_interval each session, 120 s slack, hold an early wake past its
  aligned time with ctx:after, done() when nothing is pending, a due fetch that cannot go out waits
  a whole interval).

## Approach (chosen: A)
- **A. One Algolia search with all topics (chosen).** `search` (relevance) with
  `tags=story`, `query` = the topics, `optionalWords` = the same (any topic matches; more matches
  rank higher, then Algolia's ranking by points), `numericFilters=created_at_i>now-48h,points>=10`,
  40 hits (room for mutes), the existing FIELDS. Checked 2026-11-13: "rust lua e-ink" with
  optionalWords gave 129 stories of the last 2 days; without it, 0. `search_by_date` with
  optionalWords matches everything, so it is not used. Mutes are filtered on the reader.
- B. One search per topic, merged on the reader: better for multi-word topics, but one request per
  topic (slow on the reader's Wi-Fi, costly on the sleep screen). Not chosen.
- C. Re-rank HN's Top 500 on the reader: ~20 requests for the titles. Dropped.

## Decisions
- Tab: **For you** first in the tab row (7 tabs). The app opens on it when there is at least one
  topic, else on Top as now. If "For you" does not fit the tab width, the label is "You" (builder
  checks in the harness and Studio preview).
- With no topics, the For you tab shows a short explanation and **Add a topic** (system keyboard).
- More pages: **Next** at the end asks Algolia's next page (page=1, 2...), like Find.
- Each row as in the other tabs; the meta line also names the topic(s) found in the title.
- `foryou.txt` (private storage, editable over USB): one entry a line, `rust` a topic,
  `-crypto` a muted word, `-site:medium.com` a muted site. Case-insensitive; a mute matches a whole
  word of the title, a site matches the story's domain or its subdomains.
- **More like this / Less like this**: two text links on the first page of an opened story, under
  its title. More: the title's words (stop words and words under 3 letters left out) as buttons in a
  modal; a tap adds the topic. Less: the same words plus the site; a tap mutes it. The For you list
  is fetched again next time it is shown.
- Settings gets a **For you** row: a page listing all topics, then muted words, then muted sites
  (paged when long); a tap on one opens **Edit** (the system keyboard with its text; emptied:
  removed), **Remove** and **Cancel** (the user, 2026-11-13: see them all at once and change or drop
  them one by one later); **Add a topic**, **Mute a word**, and **Sleep screen**: Off / every 30 min / 1 h / 3 h /
  6 h (on = this app becomes the sleep screen via ctx.lockscreen:set_default; off clears it).
- Sleep screen (`lockscreen.lua`): the date, "Hacker News · For you", up to 8 stories (title wrapped
  to two lines, points and comments), "updated HH:MM" (the fetch time, not an age). It reads the
  list the app saved (`list_foryou.txt`, the same row format as the other tabs' caches) and, when
  the interval has passed, fetches with the same query and saves it. No topics: a line saying to
  add some in the app.
- Manifest: version 1.3.0, api 2.26, `lockscreen` {enabled, entry lockscreen.lua, interval_sec
  1800, net true}. The lock-screen network code is inside `-- store: cut` blocks; the store build
  keeps the cached list on its sleep screen (the store's API gives the lock screen no network).
- Back on a list returns false (the host asks to exit), as now.
- Wake interval (as Weather 1.1): each lock session calls `set_interval(min(chosen, 3600))`; 3 h
  and 6 h wake hourly and fetch only when due (the host allows at most an hour; interval_sec 1800
  gives the network at every hourly wake). Off = no topics or Never: hourly wakes, no network.
- Multi-word topics are allowed and sent as a quoted phrase with `advancedSyntax=true` (checked
  2026-11-13: `"machine learning" rust` with optionalWords works); a topic is found in a title when
  all its words are there.
- The Sleep screen row shows the real state from `ctx.lockscreen:is_default()` each time it is
  drawn (the user can change it in the system), as Weather does.
- Few or no stories after the mutes: the list shows what there is; none: "Nothing for your topics
  in the last 2 days" and the topics. The window (48 h, 10 points) is fixed; one request only.
- Release: staged in release/v0.24.0 (notes, package, SHA256SUMS), README, store export.

## Left to the builder
- The stop-word list (short, English).
- Where the query lives (hn.lua builds the URL; a pure function, tested).
- How the For you page and the modals are laid out with the existing kit helpers.
- Whether the lock screen shares hn.lua's row parsing (bundle.py can put it in front).
