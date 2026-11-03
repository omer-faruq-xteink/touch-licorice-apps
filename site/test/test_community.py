"""Community apps: tools/site_community.py reads the sample inkapp.json files in community/ (named
<owner>__<repo>.json) the way it reads GitHub's: checks, cleaning, addresses, the blocklist.

  python -I site/test/test_community.py
"""
import os, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'tools'))
import site_community as C  # noqa: E402

FIX = os.path.join(HERE, 'community')
logs = []
C.BLOCKLIST = os.path.join(tempfile.mkdtemp(), 'none.txt')
apps = C.collect(FIX, logs.append)
by = {a['app_id']: a for a in apps}

# the good app, cleaned: repo paths become raw GitHub addresses, the owner and repo are kept
r = by['reversi']
assert r['devices'] == ['X4 Pro', 'X4 Classic'] and r['category'] == 'games' and r['version'] == '1.2.0', r
assert r['package'] == 'https://raw.githubusercontent.com/alice/ink-games/main/dist/reversi.xtapp', r['package']
assert r['icon'] == 'https://raw.githubusercontent.com/alice/ink-games/main/icons/reversi.png', r['icon']
assert r['homepage'] == 'https://github.com/alice/ink-games' and r['owner'] == 'alice' and r['repo'] == 'alice/ink-games', r

# the bad ones are skipped with a reason, and the rest of the file still counts
assert 'Bad-Id' not in str(apps) and any('app 2: app_id' in l for l in logs), logs
assert 'habits' not in by and any('bob/habits: not format 1' in l for l in logs), logs

# addresses: only https, or a plain path inside the repo
for v in ('http://x/a.xtapp', 'javascript:alert(1)', '../up.xtapp', '/abs.xtapp', 'ftp://x/a.xtapp'):
    assert C.url_in('a/b', 'main', v, raw=True) is None, v
assert C.check_app({'app_id': 'x', 'name': 'X', 'version': '1.0', 'devices': ['X4 Pro'], 'package': 'x.zip'}, 'a/b', 'main')[0] is None
assert C.check_app({'app_id': 'x', 'name': 'X', 'version': '1.0', 'devices': ['Kindle'], 'package': 'x.xtapp'}, 'a/b', 'main')[0] is None
long = C.check_app({'app_id': 'x', 'name': 'N' * 90, 'version': '1.0', 'devices': ['X4 Pro'], 'package': 'x.xtapp',
                    'description': 'line one\n\nline two ' + 'd' * 400}, 'a/b', 'main')[0]
assert len(long['name']) == 40 and len(long['summary']) == 200 and '\n' not in long['summary'], long

# the blocklist: an owner, or one repo
with tempfile.TemporaryDirectory() as d:
    C.BLOCKLIST = os.path.join(d, 'block.txt')
    open(C.BLOCKLIST, 'w').write('# comment\nmallory   # spam\n')
    assert 'spam' not in {a['app_id'] for a in C.collect(FIX, logs.append)}
    open(C.BLOCKLIST, 'w').write('alice/ink-games\n')
    assert {a['app_id'] for a in C.collect(FIX, logs.append)} == {'spam'}

print('community: all tests passed')
