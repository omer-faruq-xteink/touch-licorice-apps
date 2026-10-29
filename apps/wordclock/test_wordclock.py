"""Offline test of the Word Clock (Lua 5.4 through lupa, stand-ins for the clock, fonts, private
files and the canvas): every minute in every language lights words that exist and read in order;
sample sentences in English, German and Turkish; the lock screen and the app draw inside the
screen; the language button cycles and is saved; the minute dots.

  python -I apps/wordclock/test_wordclock.py
"""
import os, subprocess, sys
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
subprocess.run([sys.executable, '-I', os.path.join(HERE, 'make_grids.py')], check=True, capture_output=True)
subprocess.run([sys.executable, '-I', os.path.join(HERE, 'bundle.py')], check=True)

STUBS = r'''
__TEST = {}
samples = {}
store = {}
drawn, rects, circles = {}, {}, {}
clock = { valid = true, hour = 22, minute = 30, second = 5 }
timers = {}
lock_default = false
local function font(px) return { px = px, line_height = math.floor(px * 1.3) } end
ctx = {
  clock = { now = function(self) return clock end },
  storage = { read = function(self, n) return store[n] end, write = function(self, n, s) store[n] = s end },
  fonts = { size = function(self, px, sample) samples[#samples + 1] = sample or ''; return font(px) end, small = font(20), medium = font(24), large = font(32) },
  i18n = { locale = 'en' },
  lockscreen = { is_default = function(self) return lock_default end,
                 set_default = function(self) lock_default = true end,
                 clear_default = function(self) lock_default = false end },
  after = function(self, ms, fn) local tm = { ms = ms, fn = fn, cancel = function(t) t.dead = true end }; timers[#timers + 1] = tm; return tm end,
  invalidate = function(self) end,
}
gg = {
  clear = function(self) drawn, rects, circles = {}, {}, {} end,
  text = function(self, x, y, s, o) drawn[#drawn + 1] = { x = x, y = y, s = s, color = o and o.color } end,
  rect = function(self, x, y, w, h, o) rects[#rects + 1] = { x = x, y = y, w = w, h = h, fill = o and o.fill } end,
  circle = function(self, x, y, r, o) circles[#circles + 1] = { x = x, y = y, fill = o and o.fill } end,
  line = function() end,
}
'''


def runtime(entry):
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    L.execute(STUBS)
    L.execute(open(os.path.join(HERE, entry), encoding='utf-8').read())
    return L


L = runtime('lockscreen.lua')
said = L.eval('''function(lang, h, m)
  local GRIDS, sentence = __TEST.GRIDS, __TEST.sentence
  local g = GRIDS[lang]
  local out = {}
  for _, key in ipairs(sentence(lang, h, m)) do
    local w = g.words[key]
    if not w then return 'MISSING ' .. key end
    local s = ''
    for c = w[2], w[2] + w[3] - 1 do s = s .. g.rows[w[1]][c] end
    out[#out + 1] = string.format('%d:%d:%s', w[1], w[2], s)
  end
  return table.concat(out, ' ')
end''')


def words(lang, h, m):
    r = said(lang, h, m)
    assert not r.startswith('MISSING'), (lang, h, m, r)
    parts = [p.split(':') for p in r.split(' ')]
    pos = [(int(a), int(b)) for a, b, _ in parts]
    assert pos == sorted(pos) and len(set(pos)) == len(pos), (lang, h, m, r)   # reading order
    return ' '.join(w for _, _, w in parts)


for lang in ('en', 'de', 'tr'):
    for t in range(1440):
        words(lang, t // 60, t % 60)

EXPECT = {
    ('en', 22, 30): 'IT IS HALF PAST TEN', ('en', 9, 40): 'IT IS TWENTY TO TEN', ('en', 12, 0): 'IT IS TWELVE OCLOCK',
    ('en', 0, 17): 'IT IS A QUARTER PAST TWELVE', ('en', 13, 25): 'IT IS TWENTY FIVE PAST ONE',
    ('en', 23, 55): 'IT IS FIVE TO TWELVE', ('en', 7, 10): 'IT IS TEN PAST SEVEN',
    ('de', 10, 25): 'ES IST FÜNF VOR HALB ELF', ('de', 1, 0): 'ES IST EIN UHR', ('de', 10, 35): 'ES IST FÜNF NACH HALB ELF',
    ('de', 8, 45): 'ES IST VIERTEL VOR NEUN', ('de', 16, 20): 'ES IST ZWANZIG NACH VIER', ('de', 0, 30): 'ES IST HALB EINS',
    ('de', 21, 10): 'ES IST ZEHN NACH NEUN', ('de', 11, 55): 'ES IST FÜNF VOR ZWÖLF',
    ('tr', 10, 20): 'SAAT ONU YİRMİ GEÇİYOR', ('tr', 9, 45): 'SAAT ONA ÇEYREK VAR', ('tr', 10, 30): 'SAAT ON BUÇUK',
    ('tr', 0, 30): 'SAAT YARIM', ('tr', 12, 31): 'SAAT YARIM', ('tr', 11, 20): 'SAAT ON BİRİ YİRMİ GEÇİYOR',
    ('tr', 12, 40): 'SAAT BİRE YİRMİ VAR', ('tr', 23, 55): 'SAAT ON İKİYE BEŞ VAR', ('tr', 4, 5): 'SAAT DÖRDÜ BEŞ GEÇİYOR',
    ('tr', 3, 35): 'SAAT DÖRDE YİRMİ BEŞ VAR', ('tr', 6, 0): 'SAAT ALTI', ('tr', 20, 15): 'SAAT SEKİZİ ÇEYREK GEÇİYOR',
    ('tr', 14, 50): 'SAAT ÜÇE ON VAR', ('tr', 17, 25): 'SAAT BEŞİ YİRMİ BEŞ GEÇİYOR', ('tr', 13, 30): 'SAAT BİR BUÇUK',
    ('tr', 11, 0): 'SAAT ON BİR', ('tr', 9, 10): 'SAAT DOKUZU ON GEÇİYOR',
}
for (lang, h, m), want in EXPECT.items():
    got = words(lang, h, m)
    assert got == want, (lang, h, m, got, want)


def draw(R):
    R.eval('on_load')(R.eval('ctx'))
    R.eval('on_draw')(R.eval('ctx'), R.eval('gg'))
    d = R.eval('drawn')
    return [(d[i].x, d[i].y, d[i].s, d[i].color) for i in range(1, len(d) + 1)]


# the lock screen: every letter on screen, the lit ones white on black blocks; the dots
for lang, rows, cols in (('en', 10, 11), ('de', 10, 11), ('tr', 14, 12)):
    L.execute(f"store['settings.txt'] = 'lang={lang}\\n'; clock.hour = 22; clock.minute = 32")
    t = draw(L)
    assert not any(str(s).startswith('lock error') for _, _, s, _ in t), t
    letters = [p for p in t]
    lit = [p for p in t if p[3] == 0]
    assert len(letters) == rows * cols + len(lit) // 2 * 1, (lang, len(letters), len(lit))   # lit drawn twice
    for x, y, s, c in t:
        assert 0 < x < 480 and 0 < y < 790, (lang, x, y, s)
    blocks = L.eval('rects')
    assert len(blocks) == len(said(lang, 22, 32).split(' ')), (lang, len(blocks))
    smp = list(L.eval('samples').values())
    want = {'en': '', 'de': 'ÜÖ', 'tr': 'İÜÇÖŞ'}[lang]
    assert any(sorted(x) == sorted(want) for x in smp), (lang, smp[-3:])
    dots = L.eval('circles')
    assert [dots[i].fill for i in range(1, 5)] == [True, True, False, False]

# the default language follows the system's; the app's button cycles and saves it
A = runtime('index.lua')
A.execute("ctx.i18n.locale = 'tr'")
names = lambda: [s for _, _, s, _ in draw(A)]
assert 'Türkçe' in names() and 'SAAT' not in names()          # the grid letters are single characters
tap = lambda x, y: A.eval('on_input')(A.eval('ctx'), A.table_from({'type': 'pointer', 'phase': 'up', 'x': x, 'y': y}))
tap(100, 760)
A.eval('on_draw')(A.eval('ctx'), A.eval('gg'))
assert 'Deutsch' in [d.s for d in A.eval('drawn').values()] and A.eval("store['settings.txt']") == 'lang=de\n'
tap(100, 760); tap(100, 760)
assert A.eval("store['settings.txt']") == 'lang=tr\n'
tap(360, 760)
assert A.eval('lock_default') is True
tm = A.eval('timers'); last = tm[len(tm)]
assert 54000 < last.ms <= 55200, last.ms
print('wordclock tests passed')
