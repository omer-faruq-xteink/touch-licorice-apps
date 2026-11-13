"""xkcd's sleep screen (lockscreen.lua): the latest comic saved for it (lock.txt, lock.png), looked for
again while locked when the interval chosen in the app has passed (API 2.26: lockscreen "net": true),
the picture fetched only for a new comic, the fetch time shown, the wake set each session, an early
wake held past the aligned time, done() at the end.

  python -I apps/xkcd/test_lock.py
"""
import json, os, re, struct, subprocess, sys, urllib.parse, zlib
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
check(man['api'] == '2.26' and lk.get('net') is True and lk.get('interval_sec') == 3600 and lk.get('entry') == 'lockscreen.lua',
      f'manifest: api 2.26, lockscreen net, an hour: {lk}')


def png(w, h, size=2000):
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 0, 0, 0, 0)
    chunk = struct.pack('>I', len(ihdr)) + b'IHDR' + ihdr + struct.pack('>I', zlib.crc32(b'IHDR' + ihdr) & 0xffffffff)
    b = b'\x89PNG\r\n\x1a\n' + chunk
    return (b + b'\x00' * max(0, size - len(b))).decode('latin-1')


STUBS = r"""
store, requests, timers, drawn, images = {}, {}, {}, {}, {}
done_calls, inval, wake, commands = 0, 0, nil, 0
local function font(px) return { px = px, line_height = math.floor(px * 1.3),
  measure = function(self, s) return math.floor(#s * px * 0.5) end } end
ctx = {
  storage = { read = function(self, n) return store[n] end, write = function(self, n, s) store[n] = s; return true end,
              remove = function(self, n) store[n] = nil; return true end },
  fonts = { small = font(20), medium = font(24), large = font(32) },
  clock = { now = function(self) local d = os.date('!*t', now_sec)
    return { epoch_sec = now_sec, valid = true, year = d.year, month = d.month, day = d.day, hour = d.hour, minute = d.min,
             second = d.sec, offset_minutes = 0 } end,
    millis = function(self) return 0 end },
  net = { request = function(self, opts, fn) requests[#requests + 1] = opts.url; pending[#pending + 1] = { opts = opts, fn = fn }; return {} end },
  invalidate = function(self) inval = inval + 1 end,
  after = function(self, ms, fn) timers[#timers + 1] = { ms = ms, fn = fn }; return {} end,
  capabilities = { image_decode = true },
  image = { decode = function(self, b, o)
    local w, h
    if b:sub(1, 4) == '\137PNG' then w, h = string.unpack('>I4I4', b, 17)
    else w, h = b:match('W=(%d+);H=(%d+);'); w, h = tonumber(w), tonumber(h) end
    if not w then return nil, 'invalid_argument' end
    if w > 1024 or h > 1024 then return nil, 'limit_exceeded' end
    local s = 1
    if o and o.max_w then s = math.min(1, o.max_w / w, o.max_h / h) end
    return { width = math.floor(w * s), height = math.floor(h * s), release = function() end }
  end },
  lock = { reason = 'timer', net = true, interval_sec = 3600,
           done = function(self) done_calls = done_calls + 1 end,
           set_interval = function(self, s) wake = s; return s end },
}
pending = {}
local function rec(self, ...) commands = commands + 1 end
gg = { clear = function(self) drawn = {}; images = {}; commands = 0 end, line = rec, rect = rec, circle = rec, polyline = rec, polygon = rec,
       text = function(self, x, y, s, o) commands = commands + 1; drawn[#drawn + 1] = s end,
       image = function(self, img, x, y, o) commands = commands + 1; images[#images + 1] = { img = img, x = x, y = y, o = o } end }
"""
LATEST = {'num': 31, 'title': 'New One', 'safe_title': 'New One', 'alt': 'An alt.', 'img': 'https://imgs.xkcd.com/comics/new_one.png',
          'year': '2026', 'month': '11', 'day': '13'}
big = {'on': False}
sizes = []


def to_lua(L, v):
    if isinstance(v, dict):
        return L.table_from({k: to_lua(L, x) for k, x in v.items()})
    if isinstance(v, list):
        return L.table_from([to_lua(L, x) for x in v])
    return v


def answer(L):
    """answer the requests out, one after another (an answer may ask the next)"""
    n = 0
    while len(L.globals().pending) > 0 and n < 10:
        p = L.globals().pending[1]
        L.eval('table.remove(pending, 1)')
        opts, fn = p.opts, p.fn
        u = urllib.parse.urlsplit(str(opts.url))
        if u.netloc == 'xkcd.com':
            res = {'ok': True, 'status': 200, 'body': json.dumps(LATEST)}
        else:
            src = png(1500, 500) if big['on'] else png(740, 300)
            hd = opts.headers
            if u.netloc == 'imgs.xkcd.com':                    # only its first 64 bytes are asked
                assert hd is not None and str(hd.Range) == 'bytes=0-63', 'a Range request'
                fn(L.globals().ctx, to_lua(L, {'ok': True, 'status': 206, 'body': src[:64]}))
                n += 1
                continue
            q = dict(urllib.parse.parse_qsl(u.query))
            assert q['con'] == '100' and q['filt'] == 'greyscale' and q['output'] == 'png', q
            sizes.append((int(q['w']), int(q['h'])))
            sw, sh = struct.unpack('>II', src[16:24].encode('latin-1'))
            k = min(int(q['w']) / sw, int(q['h']) / sh)
            body = png(int(sw * k), int(sh * k))
            L.globals().store[str(opts.save.name)] = body
            res = {'ok': True, 'status': 200, 'saved': True, 'body': ''}
        fn(L.globals().ctx, to_lua(L, res))
        n += 1


def session(store, now, reason='timer', interval=3600, net=True, answer_first=True):
    L = lua54.LuaRuntime(unpack_returned_tuples=True, encoding='latin-1')
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


texts = lambda L: [str(s) for s in L.globals().drawn.values()]
reqs = lambda L: [str(u) for u in L.globals().requests.values()]
SAVED = {'settings.txt': 'last=30\nlockevery=6',
         'lock.txt': 'png\t30\tComic 30\tThe alt.\thttps://imgs.xkcd.com/comics/c30.png\t2026-11-11\t0\nat=' + str(NOW - 3600),
         'lock.png': png(740, 300)}

# fresh (looked 1 h ago, every 6 h): no request, the saved comic drawn, its time, done
L = session(SAVED, NOW)
t = texts(L)
check(reqs(L) == [] and 'xkcd 30: Comic 30' in t and 'updated 02:00' in t, f'fresh: the saved comic, no request: {t}')
check(len(L.globals().images) == 1 and int(L.globals().done_calls) == 1 and int(L.globals().wake) == 3600, 'drawn; done; the next wake in an hour')
im = L.globals().images[1]
check(int(im.img.width) <= 480 and int(im.x) >= 0, 'fitted to the screen')
# a saved picture is drawn as it is (made for this box by the resizer; no scaling on the reader)
L = session(dict(SAVED, **{'lock.png': png(400, 300)}), NOW)
im = L.globals().images[1]
check(im.o is None and int(im.img.width) == 400 and int(im.x) == 40, 'drawn as it is, centred')
check(int(L.globals().commands) < 200, f'{L.globals().commands} commands')
# due (6 h), the same comic: the JSON only, the time updated
same = dict(SAVED)
same['lock.txt'] = SAVED['lock.txt'].replace('at=' + str(NOW - 3600), 'at=' + str(NOW - 6 * 3600))
LATEST.update({'num': 30, 'title': 'Comic 30', 'img': 'https://imgs.xkcd.com/comics/c30.png'})
L = session(same, NOW)
check(reqs(L) == ['https://xkcd.com/info.0.json'] and 'at=' + str(NOW) in str(L.globals().store['lock.txt']) and 'updated 03:00' in texts(L),
      f'due, nothing new: the JSON only: {reqs(L)}')
# a new comic: its picture saved for the sleep screen, drawn after the answers
LATEST.update({'num': 31, 'title': 'New One', 'img': 'https://imgs.xkcd.com/comics/new_one.png'})
L = session(same, NOW)
r = reqs(L)
check(len(r) == 3 and r[:2] == ['https://xkcd.com/info.0.json', 'https://imgs.xkcd.com/comics/new_one.png'] and r[2].startswith('https://images.weserv.nl/'),
      f'a new one: its size, then its picture made for the sleep screen: {r}')
check(sizes[-1] == (464, 600), f'made for 464 x 680, at most twice its 300 px height: {sizes[-1]}')
check('xkcd 31: New One' in texts(L) and str(L.globals().store['lock.txt']).startswith('png\t31\t') and int(L.globals().done_calls) == 1,
      f'drawn and kept: {texts(L)}')
# 90 s early still looks, and the session holds until 2 s past the hour
L = session(dict(same), NOW - 90)
tm = L.globals().timers
check(len(reqs(L)) >= 1 and len(tm) == 1 and int(tm[1].ms) == 92000 and int(L.globals().done_calls) == 0, 'early: looked, held with ctx:after')
L.execute('now_sec = now_sec + 92; timers[1].fn(ctx); on_draw(ctx, gg)')
check(int(L.globals().done_calls) == 1, 'then done')
# a picture too wide for the reader: through the resizer
big['on'] = True
L = session(same, NOW)
big['on'] = False
r = reqs(L)
check(str(L.globals().store['lock.txt']).startswith('png	31	') and sizes[-1] == (464, 680), f'too wide (1500 px): made for the box all the same: {sizes[-1]}')
check(L.globals().store['lock.png'] is not None, 'its picture kept')
# every 12 h: 6 h old is not due
L = session(dict(same, **{'settings.txt': 'lockevery=12'}), NOW)
check(reqs(L) == [], 'every 12 h: 6 h old, not yet')
# nothing saved and no network: a line saying to open the app
L = session({'settings.txt': 'lockevery=6'}, NOW, net=False)
check(reqs(L) == [] and any('open the app' in s.lower() for s in texts(L)) and int(L.globals().done_calls) == 1, f'nothing yet: {texts(L)}')
# the first session (the moment of locking): drawn at once, again after the answers, then done
L = session(same, NOW, reason='first', answer_first=False)
check('xkcd 30: Comic 30' in texts(L) and int(L.globals().done_calls) == 0, 'first: the saved comic at once, not done yet')
answer(L)
L.execute('on_draw(ctx, gg)')
check('xkcd 31: New One' in texts(L) and int(L.globals().done_calls) == 1, 'then the new one, then done')
log = str(L.globals().store['wakes.txt'] or '')
check(re.search(r'^\d\d:\d\d:\d\d first lock\.net true', log, re.M) is not None and 'new comic 31' in log, f'wakes.txt: {log!r}')

print('\n' + ('all passed' if not fails else f'{len(fails)} FAILED'))
sys.exit(1 if fails else 0)
