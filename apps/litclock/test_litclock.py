"""Offline test of the Literary Clock (Lua 5.4 through lupa, with stand-ins for the clock, the
package's data files, fonts, private files and the canvas): every minute of the day has a quote;
the lock screen draws the quote with its phrase in bold, inside the screen, and the time line when
asked; the app steps through a minute's quotes, saves the time-line setting and follows the clock.

  python -I apps/litclock/test_litclock.py
"""
import os, re, subprocess, sys
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, 'data')
subprocess.run([sys.executable, '-I', os.path.join(HERE, 'bundle.py')], check=True)

# the data: every minute present, in time order, well-formed
lines = {}
for h in range(24):
    prev = ''
    for line in open(os.path.join(DATA, 'h%02d.txt' % h), encoding='utf-8').read().splitlines():
        f = line.split('\t')
        assert len(f) == 7 and f[1] in ('e', 'n') and f[3] and f[5] and f[6], line
        assert f[0][:2] == '%02d' % h and f[0] >= prev, (h, line)
        assert len(line.encode()) < 2048, line
        prev = f[0]
        lines.setdefault(f[0], []).append(f)
assert all('%02d%02d' % (t // 60, t % 60) in lines for t in range(1440)), 'a minute without a quote'
exact = sum(1 for k, v in lines.items() if v[0][1] == 'e')
print(f'{exact} of 1440 minutes have their own quote')

STUBS = r'''
store = {}
drawn = {}
clock = { valid = true, year = 2026, month = 10, day = 29, weekday = 4, hour = 21, minute = 15, second = 10, hour12 = false }
timers = {}
lock_default = false
local function font(px)
  return { line_height = math.floor(px * 1.3), measure = function(self, s) return math.floor(#s * px * 0.52) end, px = px }
end
ctx = {
  clock = { now = function(self) return clock end },
  storage = { read = function(self, n) return store[n] end, write = function(self, n, s) store[n] = s end },
  fonts = { size = function(self, px) return font(px) end, small = font(20), medium = font(24), large = font(32) },
  package = { open_text = function(self, name, opts)
    local f = io.open(DATA .. name, 'rb')
    if not f then return nil, 'not_found' end
    return { read_line = function(self) local l = f:read('l'); if l then l = l:gsub('\r$', '') end; return l end,
             close = function(self) f:close() end }
  end },
  lockscreen = { is_default = function(self) return lock_default end,
                 set_default = function(self) lock_default = true end,
                 clear_default = function(self) lock_default = false end },
  after = function(self, ms, fn) local tm = { ms = ms, fn = fn, cancel = function(t) t.dead = true end }; timers[#timers + 1] = tm; return tm end,
  invalidate = function(self) end,
}
gg = {
  clear = function(self) drawn = {} end,
  text = function(self, x, y, s, o) drawn[#drawn + 1] = { x = x, y = y, s = s, px = o and o.font and o.font.px or 0, align = o and o.align } end,
  line = function() end, rect = function() end,
}
'''


def runtime(entry):
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    L.execute(f'DATA = [[{DATA.replace(os.sep, "/")}/]]')
    L.execute(STUBS)
    L.execute(open(os.path.join(HERE, entry), encoding='utf-8').read())
    return L


def texts(L):
    d = L.eval('drawn')
    return [(d[i].x, d[i].y, d[i].s, d[i].px) for i in range(1, len(d) + 1)]


def check_layout(L, hh, mm):
    L.execute(f'clock.hour = {hh}; clock.minute = {mm}')
    L.eval('on_load')(L.eval('ctx'))
    L.eval('on_draw')(L.eval('ctx'), L.eval('gg'))
    t = texts(L)
    assert not any(s.startswith(('lock error', 'draw error')) for _, _, s, _ in t), t
    for x, y, s, px in t:
        assert 0 <= y < 800 - 24 and (x <= 480), (hh, mm, x, y, s)
    return t


# the lock screen at 21:15: the phrase's words drawn twice (bold), the attribution, the time line
L = runtime('lockscreen.lua')
t = check_layout(L, 21, 15)
words = [s for _, _, s, _ in t]
shown = [q for q in lines['2115'] if q[6] in words]
assert len(shown) == 1, words
q = shown[0]
for w in q[3].split():
    assert words.count(w) >= 2, (w, words)              # bold: drawn twice
for x, y, s, px in t:                                     # punctuation sits right after its word
    if s in ('.', ',', ';', '?', '!', '"', "'"):
        left = max((p for p in t if p[1] == y and p[0] < x), key=lambda p: p[0])
        assert x - (left[0] + len(left[2]) * px * 0.52) < 3, (s, left, x)
assert q[5][:20] in ' '.join(words) and q[6] in words
assert '21:15  ·  Thursday 29 October' in words, words
L.execute("store['settings.txt'] = 'timeline=0\\n'")
words = [s for _, _, s, _ in check_layout(L, 21, 15)]
assert ('21:15  ·  Thursday 29 October' in words) == (q[1] == 'n'), words
L.execute("clock.hour12 = true")
L.execute("store['settings.txt'] = 'timeline=1\\n'")
assert '9:15 pm  ·  Thursday 29 October' in [s for _, _, s, _ in check_layout(L, 21, 15)]
L.execute("clock.hour12 = false")

# every minute of the day lays out inside the screen, the quote text right of the margin
sizes = []
for m in range(0, 1440, 7):
    t = check_layout(L, m // 60, m % 60)
    body = [px for x, y, s, px in t if px >= 20]
    sizes.append(max(body))
    xs = [x for x, y, s, px in t if px == max(body)]
    assert min(xs) >= 30, (m, xs)
print('quote sizes from', min(sizes), 'to', max(sizes), 'px')

# no clock: a message, no error
L.execute('clock = { valid = false, hour12 = false }')
L.eval('on_load')(L.eval('ctx')); L.eval('on_draw')(L.eval('ctx'), L.eval('gg'))
assert any('not set' in s for _, _, s, _ in texts(L))

# the app: Another steps through the minute's quotes, Time toggles and is saved, Lock screen
A = runtime('index.lua')
A.execute('clock.hour = 9; clock.minute = 0')
A.eval('on_load')(A.eval('ctx'))
draw = lambda: (A.eval('on_draw')(A.eval('ctx'), A.eval('gg')), texts(A))[1]
tap = lambda x, y: A.eval('on_input')(A.eval('ctx'), A.table_from({'type': 'pointer', 'phase': 'up', 'x': x, 'y': y, 'gesture': 'tap'}))
first = ' '.join(s for _, _, s, _ in draw())
n = len(lines['0900'])
assert n > 1 and f'Another 1/{n}' in first and 'Time: on' in first and 'Lock screen' in first, first
seen = [first]
for k in range(2, n + 1):                         # every quote once, counted 2/n ... n/n
    tap(80, 760)
    now_ = ' '.join(s for _, _, s, _ in draw())
    assert f'Another {k}/{n}' in now_ and now_ not in seen, now_
    seen.append(now_)
tap(240, 300)                                     # a tap on the quote: another too, back to the first
assert ' '.join(s for _, _, s, _ in draw()) == first
# a minute with a single quote: "(only one)", and a tap changes nothing
one = next(k for k, v in lines.items() if len(v) == 1)
B = runtime('index.lua')
B.execute(f'clock.hour = {int(one[:2])}; clock.minute = {int(one[2:])}')
B.eval('on_load')(B.eval('ctx'))
B.eval('on_draw')(B.eval('ctx'), B.eval('gg')); before = texts(B)
assert '(only one)' in [s for _, _, s, _ in before], before
B.eval('on_input')(B.eval('ctx'), B.table_from({'type': 'pointer', 'phase': 'up', 'x': 80, 'y': 760, 'gesture': 'tap'}))
B.eval('on_draw')(B.eval('ctx'), B.eval('gg'))
assert texts(B) == before
tap(240, 760)
assert 'Time: off' in ' '.join(s for _, _, s, _ in draw()) and A.eval("store['settings.txt']") == 'timeline=0\n'
tap(400, 760)
assert A.eval('lock_default') is True and 'Lock: on' in ' '.join(s for _, _, s, _ in draw())
tap(400, 760)
assert A.eval('lock_default') is False
# the minute timer: due at the next whole minute, then the new minute's quote
tm = A.eval('timers')
last = tm[len(tm)]
assert 49000 < last.ms <= 50200, last.ms
A.execute('clock.minute = 1; clock.second = 0')
last.fn(A.eval('ctx'))
assert any(s in ' '.join(x[2] for x in draw()) for s in (lines['0901'][0][3].split()[-1],))
print('litclock tests passed')
