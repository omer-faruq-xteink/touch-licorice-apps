"""Hacker News' sleep screen (lockscreen.lua): the For you stories the app saved, fetched again while
locked when the interval chosen in the app has passed (API 2.26: lockscreen "net": true), the fetch
time shown, the wake set each session, an early wake held past the aligned time, done() at the end.

  python -I apps/hackernews/test_lock.py
"""
import json, os, re, subprocess, sys, time, urllib.parse
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
sys.stdout.reconfigure(encoding='utf-8')
subprocess.run([sys.executable, '-I', os.path.join(HERE, 'bundle.py')], check=True, capture_output=True)
fails = []


def check(ok, what):
    print(('ok    ' if ok else 'FAIL  ') + what)
    if not ok:
        fails.append(what)


NOW = 1793070000                       # 03:00:00 UTC (the clock below is UTC)
man = json.load(open(os.path.join(HERE, 'manifest.json'), encoding='utf-8'))
lk = man.get('lockscreen', {})
check(man['api'] == '2.26' and lk.get('net') is True and lk.get('interval_sec') == 1800 and lk.get('entry') == 'lockscreen.lua'
      and 'net' in man['permissions'], f'manifest: api 2.26, lockscreen net, 30 min: {lk}')

STUBS = r"""
store, requests, timers, drawn = {}, {}, {}, {}
done_calls, inval, wake, commands = 0, 0, nil, 0
local function font(px) return { px = px, line_height = math.floor(px * 1.3),
  measure = function(self, s) return math.floor(utf8.len(s) * px * 0.5) end } end
ctx = {
  storage = { read = function(self, n) return store[n] end, write = function(self, n, s) store[n] = s end },
  fonts = { small = font(20), medium = font(24), large = font(32) },
  clock = { now = function(self) local d = os.date('!*t', now_sec)
    return { epoch_sec = now_sec, valid = true, year = d.year, month = d.month, day = d.day, hour = d.hour, minute = d.min,
             second = d.sec, offset_minutes = 0 } end,
    millis = function(self) return 0 end },
  net = { request = function(self, opts, fn) requests[#requests + 1] = opts.url; pending_fn = fn; return {} end },
  invalidate = function(self) inval = inval + 1 end,
  after = function(self, ms, fn) timers[#timers + 1] = { ms = ms, fn = fn }; return {} end,
  lock = { reason = 'timer', net = true, interval_sec = 3600,
           done = function(self) done_calls = done_calls + 1 end,
           set_interval = function(self, s) wake = s; return s end },
}
local function rec(self, ...) commands = commands + 1 end
gg = { clear = function(self) drawn = {}; commands = 0 end, line = rec, rect = rec, circle = rec, polyline = rec,
       text = function(self, x, y, s, o) commands = commands + 1; drawn[#drawn + 1] = s end }
"""
FY = [{'objectID': str(80000000 + k), 'title': t, 'url': f'https://s{k}.example/a', 'points': 100 - k, 'num_comments': k,
       'author': 'a', 'created_at_i': NOW - 3600} for k, t in enumerate(['Rust 2.0 is out', 'Writing a Lua VM in Rust',
                                                                        'Why Rust won', 'Rust on e-ink readers'])]


def to_lua(L, v):
    if isinstance(v, dict):
        return L.table_from({k: to_lua(L, x) for k, x in v.items()})
    if isinstance(v, list):
        return L.table_from([to_lua(L, x) for x in v])
    return v


def session(store, now, reason='timer', interval=3600, net=True, answer_first=True):
    """a lock session: on_load, (a timer wake holds its frame for) the answer, then on_draw"""
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    L.execute(STUBS)
    L.globals().ctx.json = L.table_from({'decode': lambda self, s: to_lua(L, json.loads(s))})
    for k, v in store.items():
        L.globals().store[k] = v
    L.execute(f"now_sec = {now}; ctx.lock.reason = '{reason}'; ctx.lock.interval_sec = {interval}")
    if not net:
        L.execute('ctx.net = nil; ctx.lock.net = false')
    L.execute(open(os.path.join(HERE, 'lockscreen.lua'), encoding='utf-8').read())
    L.execute('on_load(ctx)')
    if answer_first:
        answer(L)
    L.execute('on_draw(ctx, gg)')
    return L


def answer(L):
    fn = L.globals().pending_fn
    if fn is None:
        return False
    L.globals().pending_fn = None
    fn(L.globals().ctx, L.table_from({'ok': True, 'status': 200, 'body': json.dumps({'hits': FY, 'nbPages': 1})}))
    return True


texts = lambda L: [str(s) for s in L.globals().drawn.values()]
reqs = lambda L: [str(u) for u in L.globals().requests.values()]
row = lambda i, t: f'{i}\t{t}\thttps://old.example/{i}\t10\t2\tz\t{NOW - 7200}'
OLD = {'foryou.txt': 'rust', 'settings.txt': 'host=\nlockevery=60', 'foryou_at.txt': str(NOW - 600),
       'list_foryou.txt': '\n'.join(row(70000000 + k, f'Old rust story {k}') for k in range(3))}

# fresh (fetched 10 min ago, every hour): no request, the saved stories, the fetch time, done
L = session(OLD, NOW)
t = texts(L)
check(reqs(L) == [] and 'Old rust story 0' in t and 'updated 02:50' in t, f'fresh: the saved list, no request: {t[:6]}')
check(int(L.globals().done_calls) == 1 and int(L.globals().wake) == 3600, 'done; the next wake in an hour')
check(int(L.globals().commands) < 900, f'{L.globals().commands} commands')
check(any(s.startswith('rust · 10 pts') for s in t) or any('10 pts' in s for s in t), 'points and comments under each title')
# due (61 min): one request, the For you search; the frame after the answer has the new stories
st = dict(OLD, **{'foryou_at.txt': str(NOW - 3660)})
L = session(st, NOW)
r = reqs(L)
q = dict(urllib.parse.parse_qsl(urllib.parse.urlsplit(r[0]).query)) if r else {}
check(len(r) == 1 and q.get('optionalWords') == 'rust' and q.get('hitsPerPage') == '40', f'due: one For you search: {r}')
t = texts(L)
check('Rust 2.0 is out' in t and 'updated 03:00' in t and 'Old rust story 0' not in t, f'the new stories and time: {t[:6]}')
check(str(L.globals().store['foryou_at.txt']) == str(NOW) and 'Writing a Lua VM in Rust' in str(L.globals().store['list_foryou.txt']), 'kept for the next wake')
check(int(L.globals().done_calls) == 1, 'done after it')
# muted ones are left out on the sleep screen too
L = session(dict(st, **{'foryou.txt': 'rust\n-site:s0.example'}), NOW)
check('Rust 2.0 is out' not in texts(L) and 'Why Rust won' in texts(L), 'mutes apply')
# 90 s early still fetches, and the session holds until 2 s past the hour
L = session(dict(OLD, **{'foryou_at.txt': str(NOW - 3600)}), NOW - 90, answer_first=True)
check(len(reqs(L)) == 1, 'a wake 90 s early still fetches')
tm = L.globals().timers
check(len(tm) == 1 and int(tm[1].ms) == 92000 and int(L.globals().done_calls) == 0, 'held with ctx:after until 2 s past the hour')
L.execute('now_sec = now_sec + 92; timers[1].fn(ctx); on_draw(ctx, gg)')
check(int(L.globals().done_calls) == 1, 'then done')
# the interval: 30 min wakes every 30 min; 3 h wakes hourly and fetches only after 3 h
L = session(dict(OLD, **{'settings.txt': 'lockevery=30', 'foryou_at.txt': str(NOW - 1900)}), NOW, interval=1800)
check(int(L.globals().wake) == 1800 and len(reqs(L)) == 1, 'every 30 min')
L = session(dict(OLD, **{'settings.txt': 'lockevery=180', 'foryou_at.txt': str(NOW - 7200)}), NOW)
check(int(L.globals().wake) == 3600 and reqs(L) == [], 'every 3 h: hourly wakes, 2 h old: not yet')
L = session(dict(OLD, **{'settings.txt': 'lockevery=180', 'foryou_at.txt': str(NOW - 3 * 3600)}), NOW)
check(len(reqs(L)) == 1, 'every 3 h: 3 h old: fetched')
# no topics: a line about adding some, no request
L = session({'settings.txt': 'lockevery=60'}, NOW)
check(reqs(L) == [] and any('add topics' in s.lower() for s in texts(L)) and int(L.globals().done_calls) == 1, f'no topics: {texts(L)}')
# no network on the lock screen: the old list, done, the next try a whole interval later
L = session(dict(OLD, **{'foryou_at.txt': str(NOW - 7200)}), NOW, net=False)
check(reqs(L) == [] and 'Old rust story 0' in texts(L) and int(L.globals().done_calls) == 1 and int(L.globals().wake) == 3600, 'no network: the old list')
# the first session (the moment of locking): drawn at once, again after the answer, then done
L = session(dict(OLD, **{'foryou_at.txt': str(NOW - 7200)}), NOW + 1200, reason='first', answer_first=False)
check('Old rust story 0' in texts(L) and int(L.globals().done_calls) == 0, 'first: the old list at once, not done yet')
answer(L)
L.execute('on_draw(ctx, gg)')
check('Rust 2.0 is out' in texts(L) and int(L.globals().inval) == 1 and int(L.globals().done_calls) == 1, 'then the new one, then done')
# the wake log (private storage, over USB): a line a session
log = str(L.globals().store['wakes.txt'] or '')
check(re.search(r'^\d\d:\d\d:\d\d first lock\.net true', log, re.M) is not None and 'reply' in log, f'wakes.txt: {log!r}')

print('\n' + ('all passed' if not fails else f'{len(fails)} FAILED'))
sys.exit(1 if fails else 0)
