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

# the real notes: every app with a package has its entries, xkcd's newest first
real = S.changes_by_app(open(os.path.join(S.ROOT, 'RELEASE_NOTES.md'), encoding='utf-8').read(), S.display_names())
check(real.get('xkcd', [[None]])[0][0] == 'v0.24.0', f'xkcd: {real.get("xkcd", [])[:1]}')
check(any('Back on the main screen' in b for _, b in real.get('klondike', [])), 'Klondike has the Back change')
check(not any('Back on the main screen' in b for _, b in real.get('notebook', [])), 'Notebook does not')

print('\n' + ('all passed' if not fails else f'{len(fails)} FAILED'))
sys.exit(1 if fails else 0)
