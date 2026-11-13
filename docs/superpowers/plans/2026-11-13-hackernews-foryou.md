# Hacker News 1.3.0 For you and Sleep-Screen Digest Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A For you tab built from the user's topics (one Algolia search, mutes filtered on the reader), More/Less like this on stories, a Settings page to see, edit and remove topics and mutes, and a sleep screen that shows the For you stories and refreshes them while locked.

**Architecture:** Pure For you functions in `src/hn.lua` (shared by the app and the lock screen); the app (`src/main.lua`) gets the tab, the story links and the Settings page; `src/lock/lock.lua` is bundled with hn.lua into `lockscreen.lua` by `bundle.py` (the Weather pattern), with the lock-screen network inside `-- store: cut` blocks.

**Tech Stack:** Lua (XTOS Licorice API 2.26), tools/gamekit (kit, harness), Python + lupa tests.

**Spec:** docs/superpowers/specs/2026-11-13-hackernews-foryou-design.md

## Global Constraints
- One request per For you page or sleep-screen refresh: Algolia `search`, `tags=story`, `query` = topics (multi-word ones in double quotes), `optionalWords` = the same, `advancedSyntax=true`, `numericFilters=created_at_i>(now-172800),points>=10`, `hitsPerPage=40`, `page=N`, the existing FIELDS.
- `foryou.txt`: a line a entry; `rust` topic, `-crypto` muted word, `-site:medium.com` muted site; case-insensitive.
- Lock screen: `set_interval(min(chosen, 3600))` each session, SLACK_S 120, an early timer wake held with `ctx:after` until 2 s past its aligned time, `ctx.lock:done()` when nothing is pending, a due fetch that cannot go out waits a whole interval; shows the fetch time ("updated HH:MM").
- Manifest 1.3.0, api 2.26, lockscreen {enabled, entry lockscreen.lua, interval_sec 1800, net true}.
- Existing tabs, stories, comments, AI unchanged; Back on a list returns false.
- Tests: `python -I apps/hackernews/test_hackernews.py`, `test_ai.py`, new `test_foryou.py`, `test_lock.py`; lint `python tools/lualint55.py`. No commits before the device test.

## Review Focus
1. A topic with quotes, `|`, non-ASCII (İ, ü) or a lone `-`: saved and sent safely (percent-encoded), never breaks foryou.txt parsing.
2. A muted site matches subdomains (`news.medium.com`) but not look-alikes (`notmedium.com`).
3. The sleep screen with no topics, no cache, or no network: draws a sensible screen and ends (done), wakes hourly.
4. Every story muted out of 40 hits: the empty message, not a blank list or an endless "loading".
5. Editing a topic to empty removes it; editing to a duplicate keeps one.

---

### Task 1: For you functions in hn.lua

**Files:** Modify `apps/hackernews/src/hn.lua`; Create `apps/hackernews/test_foryou.py` (lupa, loads src/hn.lua alone).

**Interfaces (produces):**
- `N.foryou_parse(text) -> { topics = {..}, words = {..}, sites = {..} }` (lower-cased, trimmed, duplicates dropped, blank and `-` alone ignored)
- `N.foryou_text(fy) -> string` (topics, then `-word`, then `-site:x`, one a line)
- `N.foryou_url(topics, now, page) -> string`
- `N.muted(row, fy) -> bool` (a muted word = a whole word of the title, case-insensitive; a muted site = row's domain equal or ending in "." .. site)
- `N.topics_in(title, topics) -> { topic, ... }` (a topic is in when all its words are whole words of the title)
- `N.title_words(title) -> { word, ... }` (lower-case, 3+ letters, not in a short English stop list, in title order, no duplicates)

- [ ] **Step 1: Failing tests** in test_foryou.py: parse `"Rust\n-crypto\n-site:Medium.com\nmachine learning\nrust\n-\n\n"` -> topics `['rust', 'machine learning']`, words `['crypto']`, sites `['medium.com']`; `foryou_text` round-trips it; `foryou_url({'rust','machine learning'}, 1793070000, 0)` decoded has query `rust "machine learning"`, optionalWords the same, advancedSyntax `true`, numericFilters `created_at_i>1792897200,points>=10`, hitsPerPage `40`, page `0`, tags `story`, attributesToHighlight `[]`; `muted` true for title "Crypto winter" with word crypto, for url `https://news.medium.com/x` with site medium.com, false for `https://notmedium.com/`; `topics_in('Machine learning in Rust', ...)` == both; `title_words('The Rust compiler and the borrow checker')` == `['rust','compiler','borrow','checker']`; a topic `İstanbul|x"` round-trips through foryou_text/parse and appears percent-encoded in the URL.
- [ ] **Step 2:** Run `python -I apps/hackernews/test_foryou.py` — Expected: FAIL (functions missing).
- [ ] **Step 3:** Implement the six functions.
- [ ] **Step 4:** Run test_foryou.py, test_hackernews.py, test_ai.py — Expected: all pass.

### Task 2: The For you tab

**Files:** Modify `apps/hackernews/src/main.lua` (TABS, open_tab/load_more, start-up tab, the empty states, list_foryou.txt); Modify `apps/hackernews/test_hackernews.py` (the stand-in answers Algolia's For you query from its own story set honouring optionalWords loosely: a hit when any topic word is in the title).

**Interfaces:** Consumes Task 1. Produces `fy` (the loaded For you entries, module state) and `load_foryou()` / `save_foryou()` used by Tasks 3 and 4.

- [ ] **Step 1: Failing tests:** the tab row starts with `For you` (or `You` if the label is cut in the harness's font) and has 7 tabs; with foryou.txt `rust\n-site:spam.example`, a restart opens on For you, the request is the For you URL, rows are the matching hits minus spam.example, a row's meta names `rust`; Next asks page 1; no foryou.txt: opens on Top as before, the For you tab shows `Add a topic`, typing `lua` saves foryou.txt `lua` and lists Lua stories; all 40 hits muted: `Nothing for your topics in the last 2 days`; list_foryou.txt is written after the first page.
- [ ] **Step 2:** Run test_hackernews.py — Expected: FAIL.
- [ ] **Step 3:** Implement (the For you list behaves like Find for paging; save_list allows `foryou`).
- [ ] **Step 4:** Run all HN tests and lint — Expected: PASS.

### Task 3: More/Less like this and the Settings page

**Files:** Modify `apps/hackernews/src/main.lua`, `apps/hackernews/test_hackernews.py`.

- [ ] **Step 1: Failing tests:** an opened story's first page shows `More like this` and `Less like this`; More lists title_words as buttons, a tap adds the topic to foryou.txt and the For you list is marked stale; Less lists the words and `site:<domain>`, a tap mutes it; Settings has `For you`; its page lists topics, then `-` words, then `site:` mutes; a tap on a topic offers `Edit`, `Remove`, `Cancel`; Edit with `go` replaces it, Edit with empty text removes it, Edit to an existing topic leaves one; `Add a topic`, `Mute a word` work; the `Sleep screen` row shows `Off` when `is_default()` is false, choosing `Every hour` calls set_default and saves `lockevery=60` in settings.txt, `Off` calls clear_default.
- [ ] **Step 2:** Run — Expected: FAIL.
- [ ] **Step 3:** Implement with kit.modal / the existing settings grid; `lockevery` minutes in settings.txt (0 off; 30, 60, 180, 360).
- [ ] **Step 4:** Run all HN tests and lint — Expected: PASS.

### Task 4: The sleep screen

**Files:** Create `apps/hackernews/src/lock/lock.lua`; Modify `apps/hackernews/bundle.py` (also writes `lockscreen.lua` = `local N = (function() <hn.lua> end)()` + lock.lua), `apps/hackernews/manifest.json`; Create `apps/hackernews/test_lock.py` (the Weather/Tasks lock-session stubs: ctx.lock with reason, net, interval_sec, done, set_interval; ctx.after recording timers; ctx.net answering the For you URL).

- [ ] **Step 1: Failing tests:** manifest api `2.26`, lockscreen net true, interval_sec 1800; a timer wake with a fresh cache (updated 10 min ago, lockevery 60): no request, up to 8 titles drawn, `updated HH:MM`, done once, wake 3600; due (61 min): one request (the For you URL), the frame after the answer shows the new titles and the new time, cache rewritten; 90 s early still fetches; lockevery 30 -> wake 1800; 180 -> wake 3600 and a fetch only after 3 h; no topics: a line saying to add topics in the app, no request; no network (ctx.net nil): old list, done, wake = the interval; first session: drawn at once, again after the answer, done after the second draw; an early timer wake (40 s before the aligned time): ctx:after(42000) and no done until it fires; < 900 draw commands; each session adds a line to `wakes.txt` (reason, lock.net, what it did; the last 20), inside the store cut.
- [ ] **Step 2:** Run `python -I apps/hackernews/test_lock.py` — Expected: FAIL.
- [ ] **Step 3:** Implement lock.lua (the network parts in `-- store: cut` blocks) and bundle_lock in bundle.py.
- [ ] **Step 4:** Run all HN tests, lint index.lua and lockscreen.lua; `python -I tools/store_export.py hackernews` — Expected: PASS, and the store zip's lockscreen.lua has no `ctx.net` / `set_interval` / `ctx:after`.

### Task 5: Release

**Files:** `apps/hackernews/manifest.json` (1.3.0, description), `apps/hackernews/README.md`, root `README.md`, `RELEASE_NOTES.md` + `release/v0.24.0/` (notes, body, package, SHA256SUMS).

- [ ] **Step 1:** Bundle, pack `release/v0.24.0/hackernews.xtapp`, refresh its SHA256 line, copy to the card when connected.
- [ ] **Step 2:** Device test by the user: For you, More/Less like this, the Settings page, the sleep screen over a couple of hours (wakes.txt).
