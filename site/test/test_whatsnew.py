"""What's new on the app pages (tools/site_catalog.py): the release notes' bullets, each given to the
apps it is about, newest first, and nothing from a release that is not out yet.

  python -I site/test/test_whatsnew.py
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'tools'))
import site_catalog as S  # noqa: E402

fails = []


def check(ok, what):
    print(('ok    ' if ok else 'FAIL  ') + what)
    if not ok:
        fails.append(what)


NOTES = """# v0.3.0

Intro line.

## Changed

- **Weather 1.1.1: the lock screen keeps itself up to date.** Fetches while locked.
- **Back on the main screen offers to exit** in 3 more apps: Chess puzzles, Notes and 2048.

## Files

| file | content |
|---|---|
| `weather.xtapp` | Weather 1.1.1 |

# v0.2.0

## New

- **New: Chess** (`chessplay.xtapp`): a whole game against the reader.
- **Instapaper 1.2.1, RSS 1.3.1, Hacker News 1.2.1: long articles no longer close the app.** Turning
  a long article no longer closes it; the one RSS uses as well.

# v0.1.0

## Added

- **New: Chess puzzles** — 2400 puzzles.
- **Notebook**: blocks.
"""
NAMES = {'weather': 'Weather', 'chess': 'Chess puzzles', 'chessplay': 'Chess', 'notes': 'Notes', 'notebook': 'Notebook',
         'game2048': '2048', 'instapaper': 'Instapaper', 'rss': 'RSS', 'hackernews': 'Hacker News', 'tasks': 'Tasks'}

by_app = S.changes_by_app(NOTES, NAMES)
tags = lambda app: [t for t, _ in by_app.get(app, [])]
leads = lambda app: [b.split('**')[1] for _, b in by_app.get(app, [])]

check(tags('weather') == ['v0.3.0'] and leads('weather') == ['Weather 1.1.1: the lock screen keeps itself up to date.'],
      f'a bullet named after its app: {by_app.get("weather")}')
check(leads('chess') == ['Back on the main screen offers to exit', 'New: Chess puzzles'],
      f'"Chess puzzles" is not "Chess", and a list in the text counts when the lead names no app: {leads("chess")}')
check(leads('chessplay') == ['New: Chess'], f'"Chess" alone: {leads("chessplay")}')
check(tags('notes') == ['v0.3.0'] and tags('notebook') == ['v0.1.0'], 'Notes is not Notebook')
check(tags('game2048') == ['v0.3.0'], '2048 found by its name')
check(tags('rss') == ['v0.2.0'] and tags('hackernews') == ['v0.2.0'] and tags('instapaper') == ['v0.2.0'],
      'one bullet for several apps named in its lead')
check(len([1 for _, b in by_app.get('rss', [])]) == 1, 'a name in the text of a bullet whose lead names apps does not count')
check('tasks' not in by_app, 'no bullet, no entry')
check(all('weather.xtapp' not in b for _, b in by_app.get('weather', [])), 'the Files table is not a change')
check('Turning a long article' in by_app['rss'][0][1], 'a bullet\'s wrapped lines are joined')

# a release not out yet is left out: only up to the given tag
later = S.changes_by_app(NOTES, NAMES, upto='v0.2.0')
check('weather' not in later and [t for t, _ in later['chessplay']] == ['v0.2.0'], f'up to v0.2.0: {sorted(later)}')

html = S.whats_new_html(by_app.get('chess', []))
check(html.startswith('<details class="fold" id="whats-new"><summary>What') and html.count('<li>') == 2 and '<strong>' in html,
      f'a folded list: {html[:120]}')
check(S.whats_new_html([]) == '', 'nothing to show, nothing drawn')

# the badge: the app's own version in that release, the release in its tooltip
html = S.whats_new_html(by_app['weather'], lambda tag, b: '1.1.1')
check('<span class="rel" title="release v0.3.0">1.1.1</span>' in html, f'the app\'s version on the badge: {html[:200]}')
# from the manifest at the release's git tag, else the version the bullet gives the app, else the release
check(S.app_version('v0.24.0', 'klondike', '**Back on the main screen offers to exit**', 'Klondike') == '1.0.1',
      'Klondike 1.0.1 in v0.24.0, from its manifest at the tag')
check(S.app_version('v9.9.9', 'weather', '**Weather 1.1.1: the lock screen.**', 'Weather') == '1.1.1',
      'no such tag: the version in the bullet')
check(S.app_version('v9.9.9', 'chess', '**Back on the main screen offers to exit**', 'Chess puzzles') == 'v9.9.9',
      'neither: the release')

# the real notes: every app with a package has its entries, xkcd's newest first
real = S.changes_by_app(open(os.path.join(S.ROOT, 'RELEASE_NOTES.md'), encoding='utf-8').read(), S.display_names())
check(real.get('xkcd', [[None]])[0][0] == 'v0.24.0', f'xkcd: {real.get("xkcd", [])[:1]}')
check(any('Back on the main screen' in b for _, b in real.get('klondike', [])), 'Klondike has the Back change')
check(not any('Back on the main screen' in b for _, b in real.get('notebook', [])), 'Notebook does not')

# New and Updated badges: a release out for at most 7 days; New when the app arrived in it, Updated
# when a bullet of it names the app in its lead (not a change about many apps, like the Back one)
from datetime import datetime, timedelta, timezone  # noqa: E402
now = datetime(2026, 11, 20, tzinfo=timezone.utc)
dates = {'v0.3.0': now - timedelta(days=2), 'v0.2.0': now - timedelta(days=6), 'v0.1.0': now - timedelta(days=30)}
arrived = {('v0.2.0', 'chessplay'), ('v0.1.0', 'chess'), ('v0.1.0', 'notebook')}
b = S.badges(by_app, NAMES, now, date_of=dates.get, new_in=lambda t, a: (t, a) in arrived)
check(b.get('chessplay') == 'new', f'arrived 6 days ago: New ({b.get("chessplay")})')
check(b.get('weather') == 'updated', 'its own bullet 2 days ago: Updated')
check(b.get('rss') == 'updated' and b.get('hackernews') == 'updated', 'named in a shared lead: Updated')
check('chess' not in b and 'notes' not in b and 'game2048' not in b, f'only in a change about many apps: no badge ({sorted(b)})')
check('notebook' not in b, 'a release a month old: no badge')
b8 = S.badges(by_app, NAMES, now + timedelta(days=5), date_of=dates.get, new_in=lambda t, a: (t, a) in arrived)
check('chessplay' not in b8 and b8.get('weather') == 'updated', f'a week on, the older badge is gone: {sorted(b8)}')
check(S.badges(by_app, NAMES, now, date_of=lambda t: None, new_in=lambda t, a: False) == {}, 'no dates, no badges')
# the real tags: xkcd arrived in v0.24.0 (its manifest is not in v0.23.0); Weather did not
check(S.app_new_in('v0.24.0', 'xkcd') and not S.app_new_in('v0.24.0', 'weather'), 'xkcd new in v0.24.0, Weather not')
check(S.release_date('v0.24.0') is not None and S.release_date('v9.9.9') is None, 'a tag\'s date from git')

# every package a release's Files table lists as changed has a bullet of that release on its page:
# a bullet whose lead (or, for one about many apps, its text) does not name the app reaches no page
import re  # noqa: E402
notes = open(os.path.join(S.ROOT, 'RELEASE_NOTES.md'), encoding='utf-8').read()
listed, tag, in_files = {}, None, False
for line in notes.split('\n'):
    m = re.match(r'# (v\d+(?:\.\d+)*)\s*$', line)
    if m:
        tag, in_files = m.group(1), False
    elif line.startswith('## '):
        in_files = line.strip() == '## Files'
    elif in_files and line.startswith('| `'):
        cells = line.split('|')
        for n in re.findall(r'`([\w-]+?)(?:\.xtapp)?`', cells[1]):
            if os.path.isdir(os.path.join(S.ROOT, 'apps', n)):
                listed.setdefault(tag, set()).add(n)
for tag in sorted(listed, key=S.version_key, reverse=True):
    if S.version_key(tag) < (0, 17, 0):          # older notes were written before the pages had What's new
        continue
    missing = sorted(n for n in listed[tag] if not any(t == tag for t, _ in real.get(n, [])))
    check(not missing, f'{tag}: every changed package has its bullet ({len(listed[tag])} packages){" missing " + str(missing) if missing else ""}')

# the site's What's new page: every release out, newest first and open, the others folded; its date
# and time; app names in a lead linked to their pages; no Files tables; nothing not out yet
rels = S.releases(NOTES)
check([t for t, _, _ in rels] == ['v0.3.0', 'v0.2.0', 'v0.1.0'], f'releases newest first: {[t for t, _, _ in rels]}')
check(rels[0][1] == ['Intro line.'] and [s for s, _ in rels[0][2]] == ['Changed'], f'intro and sections, no Files: {rels[0][1:]}')
check('Turning a long article' in rels[1][2][0][1][1], 'wrapped bullet lines joined')
check([t for t, _, _ in S.releases(NOTES, upto='v0.2.0')] == ['v0.2.0', 'v0.1.0'], 'a release not out yet is left out')
linked = S.link_names('**New: Chess puzzles** — and Chess too', NAMES, {'chess', 'chessplay'})
check(linked.startswith('**New: [Chess puzzles](../apps/chess/)**') and linked.endswith('and Chess too'),
      f'only the lead is linked, longest name first: {linked}')
check(S.link_names('**Weather 1.1.1: x**', NAMES, set()) == '**Weather 1.1.1: x**', 'an app without a page is not linked')
when = {'v0.3.0': datetime(2026, 11, 14, 6, 12, tzinfo=timezone.utc)}
page = S.whats_new_page(rels, NAMES, when.get, {'weather', 'chessplay'})
check(page.count('<details class="fold release"') == 3 and page.count('<details class="fold release" open') == 1
      and page.index(' open') < page.index('v0.2.0'), 'the newest release open, the others folded')
check('<time datetime="2026-11-14T06:12:00+00:00">14 Nov 2026, 06:12 UTC</time>' in page, 'date and time of a release')
check('<a href="../apps/weather/">Weather</a>' in page and 'weather.xtapp' not in page, 'app names linked, Files table left out')
check('<h3>Changed</h3>' in page and 'Intro line.' in page, 'sections and the intro shown')
real_rels = S.releases(notes, upto='v0.24.0')
check(real_rels[0][0] == 'v0.24.0' and len(real_rels) >= 20, f'the real notes up to v0.24.0: {len(real_rels)} releases')

print('\n' + ('all passed' if not fails else f'{len(fails)} FAILED'))
sys.exit(1 if fails else 0)
