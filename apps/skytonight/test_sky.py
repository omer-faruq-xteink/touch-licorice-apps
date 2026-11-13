"""Offline test of Sky Tonight (Lua 5.4 through lupa) against known sky events: full and new
moons (two of them eclipses, so exact), planet oppositions and Venus's greatest elongation,
Polaris's altitude, sunrise and sunset against NOAA's solar calculator, and the precision the
reader's single floats leave.

  python -I apps/skytonight/test_sky.py
"""
import calendar, math, os, struct, sys
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from bundle import debug_source  # noqa: E402
fails = []
sys.stdout.reconfigure(encoding="utf-8")


def check(ok, what):
    print(('ok    ' if ok else 'FAIL  ') + what)
    if not ok:
        fails.append(what)


def runtime(*parts):
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    L.execute('__TEST = {}')
    L.execute(chr(10).join(open(os.path.join(HERE, 'src', p), encoding='utf-8').read() for p in parts))
    return L


def epoch(y, mo, d, h=0, mi=0):
    return calendar.timegm((y, mo, d, h, mi, 0))


L = runtime('astro.lua')
A = L.eval('__TEST.A')
days = lambda *a: A.secs(epoch(*a))      # seconds since J2000, what astro.lua takes

# --- the moon: lit fraction at known full and new moons (UTC, from the almanac)
for when, want, what in (((2026, 3, 3, 11, 38), 1, 'full moon 3 Mar 2026 (total eclipse)'),
                         ((2026, 8, 28, 4, 18), 1, 'full moon 28 Aug 2026 (partial eclipse)'),
                         ((2026, 10, 26, 4, 12), 1, 'full moon 26 Oct 2026'),
                         ((2026, 2, 17, 12, 1), 0, 'new moon 17 Feb 2026 (annular eclipse)'),
                         ((2026, 8, 12, 17, 37), 0, 'new moon 12 Aug 2026 (total eclipse)')):
    lit, waxing, age = A.phase(days(*when))
    check(abs(lit - want) < 0.01, f'{what}: {lit * 100:.1f}% lit, age {age:.1f} d')
lit, waxing, age = A.phase(days(2026, 10, 29, 20))
check(0.80 < lit < 0.92 and not waxing, f'29 Oct 2026 23:00 Istanbul: waning gibbous, {lit * 100:.0f}% lit')
lit, waxing, _ = A.phase(days(2026, 10, 18, 16, 13))
check(abs(lit - 0.5) < 0.03 and waxing, f'first quarter 18 Oct 2026: {lit * 100:.0f}% lit, waxing')

# --- planets: oppositions put them opposite the sun; Venus at greatest elongation
for name, when, lo, hi, what in (('saturn', (2026, 10, 4), 177, 180.1, 'Saturn opposition 4 Oct 2026'),
                                 ('jupiter', (2026, 1, 10), 177, 180.1, 'Jupiter opposition 10 Jan 2026'),
                                 ('mars', (2027, 2, 19), 175, 180.1, 'Mars opposition 19 Feb 2027'),
                                 ('venus', (2026, 8, 15), 45, 46.7, 'Venus greatest elongation 15 Aug 2026 (45.9)')):
    el = A.elongation(name, days(*when))
    check(lo <= el <= hi, f'{what}: {el:.1f} degrees from the sun')
# Saturn in Pisces (RA about 0h-1h) and Jupiter in Gemini (RA about 7h) in 2026
_, _, ra, dec, dist = A.planet('saturn', days(2026, 10, 4))
check(0 <= ra <= 15 or ra >= 355, f'Saturn RA {ra / 15:.2f}h dec {dec:.1f}, {dist:.2f} AU')
_, _, ra, dec, dist = A.planet('jupiter', days(2026, 1, 10))
check(100 <= ra <= 115 and 20 < dec < 25, f'Jupiter RA {ra / 15:.2f}h dec {dec:.1f}, {dist:.2f} AU')

# --- Polaris (RA 2h31m49s, dec +89.264) sits at about the observer's latitude, all night
for lat in (41.01, 52.52, 10.0):
    worst = 0
    for h in range(24):
        alt, az = A.horizon(37.954, 89.264, A.gmst(days(2026, 10, 29, h)) + 28.98, lat)
        worst = max(worst, abs(alt - lat))
    check(worst < 0.8, f'Polaris at latitude {lat}: altitude within {worst:.2f} degrees')

# --- sidereal time against the IAU 1982 formula (with its T squared term)
for when in ((2026, 1, 1), (2026, 10, 29, 20), (2040, 7, 1, 3, 17)):
    d = days(*when) / 86400
    ref = (280.46061837 + 360.98564736629 * d + 0.000387933 * (d / 36525) ** 2) % 360
    g = A.gmst(days(*when))
    check(abs(g - ref) < 0.01, f'GMST {when}: {g:.3f} degrees, IAU {ref:.3f}')


# --- sunrise and sunset against NOAA's calculator (the spreadsheet's formulas, in Python)
def noaa(y, mo, d, lat, lon, tz):
    jd = epoch(y, mo, d, 12) / 86400 + 2440587.5 - tz / 24
    T = (jd - 2451545) / 36525
    L0 = (280.46646 + T * (36000.76983 + T * 0.0003032)) % 360
    M = 357.52911 + T * (35999.05029 - 0.0001537 * T)
    e = 0.016708634 - T * (0.000042037 + 0.0000001267 * T)
    C = (math.sin(math.radians(M)) * (1.914602 - T * (0.004817 + 0.000014 * T))
         + math.sin(math.radians(2 * M)) * (0.019993 - 0.000101 * T) + math.sin(math.radians(3 * M)) * 0.000289)
    lam = L0 + C - 0.00569 - 0.00478 * math.sin(math.radians(125.04 - 1934.136 * T))
    eps0 = 23 + (26 + (21.448 - T * (46.815 + T * (0.00059 - T * 0.001813))) / 60) / 60
    eps = eps0 + 0.00256 * math.cos(math.radians(125.04 - 1934.136 * T))
    dec = math.degrees(math.asin(math.sin(math.radians(eps)) * math.sin(math.radians(lam))))
    yv = math.tan(math.radians(eps / 2)) ** 2
    l0, m = math.radians(L0), math.radians(M)
    eot = 4 * math.degrees(yv * math.sin(2 * l0) - 2 * e * math.sin(m) + 4 * e * yv * math.sin(m) * math.cos(2 * l0)
                           - 0.5 * yv * yv * math.sin(4 * l0) - 1.25 * e * e * math.sin(2 * m))
    ha = math.degrees(math.acos(math.cos(math.radians(90.833)) / (math.cos(math.radians(lat)) * math.cos(math.radians(dec)))
                                - math.tan(math.radians(lat)) * math.tan(math.radians(dec))))
    noon = (720 - 4 * lon - eot + tz * 60) / 60
    return noon - ha * 4 / 60, noon + ha * 4 / 60


def hm(x):
    x = round(x * 60)
    return f'{x // 60:02d}:{x % 60:02d}'


for city, lat, lon, tz, dates in (('Istanbul', 41.01, 28.98, 3, ((2026, 10, 29), (2026, 6, 21), (2026, 12, 21))),
                                  ('Berlin', 52.52, 13.40, 1, ((2026, 12, 21), (2026, 3, 20))),
                                  ('New York', 40.71, -74.01, -5, ((2026, 1, 15),)),
                                  ('Sydney', -33.87, 151.21, 11, ((2026, 1, 1),))):
    for y, mo, d in dates:
        s0 = A.secs(epoch(y, mo, d) - tz * 3600)                 # local midnight
        rise, sset = A.crossings('sun', s0, lat, lon, -0.833)
        rl, sl = (rise - s0) / 3600, (sset - s0) / 3600
        nr, ns = noaa(y, mo, d, lat, lon, tz)
        ok = abs(rl - nr) * 60 < 2 and abs(sl - ns) * 60 < 2
        check(ok, f'{city} {y}-{mo:02d}-{d:02d}: sun {hm(rl)}-{hm(sl)}, NOAA {hm(nr)}-{hm(ns)}')

# --- the moon rises and sets, about 50 minutes later each day
s0 = A.secs(epoch(2026, 10, 29) - 3 * 3600)
r1, s1 = A.crossings('moon', s0, 41.01, 28.98, -0.833)
r2, s2 = A.crossings('moon', s0 + 86400, 41.01, 28.98, -0.833)
check(r1 is not None and r2 is not None and 30 < (r2 - 86400 - r1) / 60 < 75,
      f'Istanbul moonrise 29 Oct {hm((r1 - s0) / 3600)}, 30 Oct {hm((r2 - s0 - 86400) / 3600)}')
# the midnight sun: no sunset at 78 N in June, no sunrise in December
r, s = A.crossings('sun', days(2026, 6, 21), 78.22, 15.65, -0.833)
check(r is None and s is None, 'Svalbard 21 Jun: the sun neither rises nor sets')
r, s = A.crossings('sun', days(2026, 12, 21), 78.22, 15.65, -0.833)
check(r is None and s is None, 'Svalbard 21 Dec: the sun neither rises nor sets')


# the next full and new moon, from a day before each
Lsky = runtime('astro.lua', 'places.lua', 'sky.lua')
SKY = Lsky.eval('__TEST.sky')
for start, kind, want, what in (((2026, 8, 27), 180, (2026, 8, 28, 4, 18), 'full moon 28 Aug 2026'),
                                ((2026, 10, 29), 0, (2026, 11, 9, 7, 2), 'new moon 9 Nov 2026'),
                                ((2026, 10, 29), 180, (2026, 11, 24, 14, 53), 'full moon 24 Nov 2026')):
    got = SKY.next_phase(days(*start), kind)
    off_h = (got - days(*want)) / 3600
    check(abs(off_h) < 2, f'{what}: off by {off_h:.1f} h')

# --- single floats: the reader keeps 24-bit mantissas. Redo the sidereal time (the most sensitive
# number, a turn a day) rounding every step to a single float, in astro.lua's order
def f32(x):
    return struct.unpack('f', struct.pack('f', x))[0]


worst = 0
for k in range(500):
    s = days(2026, 1, 1) + k * 291037
    d = s // 86400
    g = f32(f32(280.46061837 + f32(f32(0.98564736629) * d)) + f32(f32(360.98564736629) * f32((s - d * 86400) / 86400)))
    worst = max(worst, abs((g - A.gmst(s) + 180) % 360 - 180))
check(worst < 0.01, f'single floats move the sidereal time by at most {worst:.4f} degrees')
# and the slow motions with t a single float: the moon, the fastest, moves under 0.02 degrees
worst = 0
for k in range(200):
    t = A.days(days(2026, 1, 1) + k * 291037)
    worst = max(worst, abs(13.176396 * (f32(t) - t)))
check(worst < 0.02, f'single-float t moves the moon by at most {worst:.4f} degrees')

# --- the app and the lock screen on a stand-in host: they draw inside the 1024-command frame,
# inside the screen, with the buttons working. With an output folder, each frame is also drawn
# to a PNG to look at:  python -I apps/skytonight/test_sky.py OUT_DIR
import subprocess
subprocess.run([sys.executable, '-I', os.path.join(HERE, 'bundle.py')], check=True, capture_output=True)
OUT = sys.argv[1] if len(sys.argv) > 1 else None

STUBS = r"""
__TEST = {}
store, cmds, timers = {}, {}, {}
clock = { valid = true, epoch_sec = 0, offset_minutes = 180, hour = 0, minute = 0, second = 0, hour12 = false }
locale = 'en'
lock_default = false
local function font(px) return { px = px, line_height = math.floor(px * 1.3),
  measure = function(self, s) return math.floor(utf8.len(s) * px * 0.55) end } end
ctx = {
  clock = { now = function(self) return clock end },
  storage = { read = function(self, n) return store[n] end, write = function(self, n, s) store[n] = s end },
  package = { read = function(self, n) return DATA[n] end },
  fonts = { size = function(self, px, sample) return font(px) end, small = font(20), medium = font(24), large = font(32) },
  i18n = setmetatable({}, { __index = function(t, k) if k == 'locale' then return locale end end }),
  lockscreen = { is_default = function(self) return lock_default end,
                 set_default = function(self) lock_default = true end,
                 clear_default = function(self) lock_default = false end },
  input = { text = function(self, o, fn) PENDING = fn end },
  after = function(self, ms, fn) local tm = { ms = ms, fn = fn, cancel = function(t) t.dead = true end }; timers[#timers + 1] = tm; return tm end,
  invalidate = function(self) end,
  budget = { extend = function(self) extends = extends + 1; return true end },
}
extends = 0
local function rec(kind) return function(self, ...) cmds[#cmds + 1] = { kind, ... } end end
gg = { clear = function(self) cmds = {} end, text = rec('text'), rect = rec('rect'), circle = rec('circle'),
       line = rec('line'), polyline = rec('polyline'), polygon = rec('polygon') }
"""
DATA = {n: open(os.path.join(HERE, 'data', n), encoding='utf-8').read() for n in ('stars.txt', 'lines.txt', 'names.txt', 'stars_named.txt',
                                                                  'bounds.txt', 'objects.txt', 'cards.txt', 'cards_tr.txt',
                                                                  'cards_de.txt', 'objects_tr.txt', 'objects_de.txt')
        if os.path.exists(os.path.join(HERE, 'data', n))}


def host(entry, epoch_sec, offset_min, locale='en', store=None, debug=False):
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    L.execute(STUBS)
    L.globals().DATA = L.table_from(DATA)
    L.execute(f'clock.epoch_sec = {epoch_sec}; clock.offset_minutes = {offset_min}; locale = "{locale}"')
    if store:
        for k, v in store.items():
            L.globals().store[k] = v
    src = open(os.path.join(HERE, entry), encoding='utf-8').read()
    L.execute(debug_source(src) if debug else src)
    L.execute('on_load(ctx)')
    return L


def frame(L):
    L.execute('on_draw(ctx, gg)')
    out = []
    for c in L.globals().cmds.values():
        out.append([c[k] for k in range(1, len(c) + 1)])
    return out


def tap(L, x, y):
    L.execute(f'on_input(ctx, {{ type = "pointer", phase = "up", x = {x}, y = {y} }})')


def texts(cmds):
    return [c[3] for c in cmds if c[0] == 'text']


def inside(cmds):
    bad = 0
    for c in cmds:
        if c[0] in ('text', 'circle', 'line', 'rect'):
            if not (-2 <= c[1] <= 482 and -2 <= c[2] <= 802):
                bad += 1
    return bad


def render(cmds, path):
    from PIL import Image, ImageDraw, ImageFont
    im = Image.new('L', (480, 800), 255)
    d = ImageDraw.Draw(im)
    fonts = {}

    def font(px):
        if px not in fonts:
            fonts[px] = ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf', px)
        return fonts[px]

    def col(o):
        return 255 if (o is not None and o['color'] == 0) else 0

    for c in cmds:
        k = c[0]
        if k in ('polyline', 'polygon'):
            o = c[2] if len(c) > 2 else None
        else:
            o = c[-1] if not isinstance(c[-1], (int, float, str)) else None
        if k == 'text':
            x, y, s = c[1], c[2], c[3]
            f = font(int(o['font']['px'])) if o is not None and o['font'] is not None else font(20)
            al = (o is not None and o['align']) or 'left'
            va = (o is not None and o['valign']) or 'top'
            anchor = {'left': 'l', 'center': 'm', 'right': 'r'}[al] + {'top': 'a', 'middle': 'm', 'bottom': 'd', 'baseline': 's'}[va]
            d.text((x, y), s, font=f, fill=col(o), anchor=anchor)
        elif k == 'rect':
            x, y, w, h = c[1:5]
            if o is not None and o['fill']:
                d.rounded_rectangle((x, y, x + w - 1, y + h - 1), radius=(o['radius'] or 0), fill=col(o))
            else:
                d.rounded_rectangle((x, y, x + w - 1, y + h - 1), radius=((o is not None and o['radius']) or 0), outline=col(o), width=2)
        elif k == 'circle':
            x, y, r = c[1:4]
            if o is not None and o['fill']:
                d.ellipse((x - r, y - r, x + r, y + r), fill=col(o))
            else:
                d.ellipse((x - r, y - r, x + r, y + r), outline=col(o), width=(o is not None and o['line_width']) or 1)
        elif k == 'line':
            d.line(c[1:5], fill=col(o), width=(o is not None and o['line_width']) or 1)
        elif k in ('polyline', 'polygon'):
            pts = [c[1][i] for i in range(1, len(c[1]) + 1)]
            xy = list(zip(pts[0::2], pts[1::2]))
            if k == 'polygon' and o is not None and o['fill']:
                d.polygon(xy, fill=col(o))
            else:
                d.line(xy, fill=col(o), width=1)
    im.save(path)


ist = lambda *a: epoch(*a) - 3 * 3600          # Istanbul wall-clock time to epoch seconds
cases = [('night_now', ist(2026, 10, 29, 23), 180, 'en', None),
         ('day_tonight', ist(2026, 10, 29, 14), 180, 'tr', None),
         ('berlin_de', epoch(2026, 12, 20, 21), 60, 'de', None),
         ('sydney', epoch(2026, 1, 15, 11), 660, 'en', {'settings.txt': 'place=Sydney\nlat=-33.87\nlon=151.21\n'})]
for name, es, off, loc, st in cases:
    for entry in ('index.lua', 'lockscreen.lua'):
        L = host(entry, es, off, loc, st)
        cm = frame(L)
        tx = texts(cm)
        errs = [t for t in tx if 'error' in str(t)]
        check(len(cm) <= 1024 and not errs and inside(cm) == 0,
              f'{name} {entry}: {len(cm)} commands, {inside(cm)} outside{", " + errs[0] if errs else ""}; header {tx[:3]}')
        if OUT:
            render(cm, os.path.join(OUT, f'sky_{name}_{entry.split(".")[0]}.png'))

# constellation names on the chart (names.txt carries the IAU abbreviation before them)
tx = texts(frame(host('index.lua', ist(2026, 10, 29, 23), 180, 'en')))
check('Pegasus' in tx and not any(str(t).startswith(('And ', 'Peg ')) for t in tx),
      f'constellation names: {[t for t in tx if "dromeda" in str(t) or "egasus" in str(t)]}')

# --- from a point on the chart back to the sky, and the constellation there (the zoom's tap)
L = host('index.lua', ist(2026, 10, 29, 23), 180, 'en')
SK = L.eval('__TEST.sky')
s23 = A.secs(ist(2026, 10, 29, 23))
ISTV = L.eval('function(s, z, zx, zy) return { s = s, place = { name = "x", lat = 41.01, lon = 28.98 }, zoom = z, zx = zx, zy = zy } end')


def round_trip(ra, dec, view):
    x, y, u = SK.radec_to_screen(ra, dec, view)
    back = SK.chart_to_radec(x, y, view)
    if back is None:
        return None
    r2, d2 = back
    return max(abs((r2 - ra + 180) % 360 - 180) * math.cos(math.radians(dec)), abs(d2 - dec)), SK.constellation_at(r2, d2)


v1 = ISTV(s23, None, None, None)
for ra, dec, want in ((37.95, 89.26, 'UMi'), (88.79, 7.41, 'Ori'), (10.68, 41.27, 'And'), (2.29, 59.15, 'Cas'), (279.23, 38.78, 'Lyr')):
    rt = round_trip(ra, dec, v1)
    check(rt is not None and rt[0] < 0.5 and rt[1] == want, f'{want}: the chart point leads back to it: {rt}')
check(SK.constellation_at(359.5, 60) == 'Cas' and SK.constellation_at(0.5, 60) == 'Cas' and SK.constellation_at(0.1, 10) == 'Psc',
      'RA 0/360 is no seam')
check(SK.constellation_at(200, -89) == 'Oct' and SK.constellation_at(10, 89.9) == 'UMi' and SK.constellation_at(200, 82) == 'Cam',
      'the poles and the ring around the north pole')
check(SK.chart_to_radec(240 + 209, 322, v1) is None, 'a point outside the horizon is not in the sky')
vz = ISTV(s23, 2.5, 200, 250)
rt = round_trip(88.79, 7.41, vz)
check(rt is not None and rt[0] < 0.5, f'zoomed 2.5x: the round trip holds: {rt}')
LS = host('index.lua', epoch(2026, 1, 15, 12), 660, 'en', {'settings.txt': 'place=Sydney' + chr(10) + 'lat=-33.87' + chr(10) + 'lon=151.21' + chr(10)})
SKS = LS.eval('__TEST.sky')
vs = LS.eval('function(s) return { s = s, place = { name = "Sydney", lat = -33.87, lon = 151.21 } } end')(A.secs(epoch(2026, 1, 15, 12)))
x, y, u = SKS.radec_to_screen(186.65, -63.10, vs)
back = SKS.chart_to_radec(x, y, vs)
check(u > 0 and back is not None and SKS.constellation_at(back[0], back[1]) == 'Cru', 'Sydney, 23:00 in January: Acrux is in the Southern Cross')

# --- the zoomed view (1.1.0): the chart 2.5x around a point, objects drawn, the card under it
BASE = {'night_now': 472, 'day_tonight': 452, 'berlin_de': 451, 'sydney': 533}
for name, es, off, loc, st in cases:
    n = len(frame(host('index.lua', es, off, loc, st)))
    check(n == BASE[name] + 3, f'{name}: the full chart is as in 1.0.1, plus the 3 bars of the ☰ ({n} commands, was {BASE[name]})')
ZF = """function(s, lat, lon, off, zx, zy, card)
  gg:clear(0)
  __TEST.sky.draw_sky(gg, { s = s, place = { name = 'Here', lat = lat, lon = lon }, off = off, zoom = 2.5, zx = zx, zy = zy, card = card }, 738)
end"""


def zoomed(L, s, lat, lon, off, ra, dec, card):
    sk = L.eval('__TEST.sky')
    v = L.eval('function(s, lat, lon) return { s = s, place = { name = "x", lat = lat, lon = lon } } end')(s, lat, lon)
    zx, zy, _ = sk.radec_to_screen(ra, dec, v)
    L.eval(ZF)(s, lat, lon, off, zx, zy, card)
    return [[c[k] for k in range(1, len(c) + 1)] for c in L.globals().cmds.values()]


L = host('index.lua', ist(2026, 10, 29, 23), 180, 'en')
cm = zoomed(L, s23, 41.01, 28.98, 10800, 10.68, 41.27, 'And')
tx = texts(cm)
check(len(cm) <= 1024 and inside(cm) == 0 and not any('error' in str(t) for t in tx),
      f'zoomed on Andromeda: {len(cm)} commands, {inside(cm)} outside')
check('Andromeda' in tx and 'M31' in tx and any('chained princess' in str(t) for t in tx), f'its card and M31: {tx[-8:]}')
check(any(str(t).startswith('Brightest: Alpheratz') for t in tx) and any('November' in str(t) for t in tx), 'the brightest stars and when to look')
if OUT:
    render(cm, os.path.join(OUT, 'zoom_andromeda.png'))
# in Turkish and German: the card's story and the objects in that language (the stars keep their names)
def line_of(name, prefix):
    return [l.split('|') for l in DATA.get(name, '').split('\n') if l.startswith(prefix)]


EN_STORY = line_of('cards.txt', 'And|')[0][1]
for loc, month, label in (('tr', 'Akşamları: Kasım', 'En parlak: '), ('de', 'Abends: November', 'Hellste: ')):
    card, obj = line_of(f'cards_{loc}.txt', 'And|'), line_of(f'objects_{loc}.txt', 'M31|')
    if not card or not obj:
        check(False, f'{loc}: cards_{loc}.txt / objects_{loc}.txt')
        continue
    LT = host('index.lua', ist(2026, 10, 29, 23), 180, loc)
    cmz = zoomed(LT, s23, 41.01, 28.98, 10800, 10.68, 41.27, 'And')
    if OUT:
        render(cmz, os.path.join(OUT, f'zoom_andromeda_{loc}.png'))
    tx = [str(t) for t in texts(cmz)]
    joined = ' '.join(tx)
    check(month in tx and card[0][1].split()[0] in joined and EN_STORY not in joined, f'{loc}: the card in that language: {tx[-6:]}')
    check(any(t.startswith('M31 ' + obj[0][1]) for t in tx) and any(t.startswith(label) for t in tx), f'{loc}: M31 by its {loc} name, {label!r}')

LS = host('index.lua', epoch(2026, 7, 15, 12), 600, 'en')
cm = zoomed(LS, A.secs(epoch(2026, 7, 15, 12)), -33.87, 151.21, 36000, 270.92, -24.38, 'Sgr')
tx = texts(cm)
check(len(cm) <= 1024 and inside(cm) == 0 and 'M8' in tx and 'Archer' in tx, f'Sydney, Sagittarius zoomed: {len(cm)} commands, {inside(cm)} outside')
check(not any(str(t).startswith('M22 M22') for t in tx), 'an object named by its number is not named twice')
last = [str(t) for t in tx][-1]
check(last.endswith('.'), f'the card ends with a whole object, not half of one: {last!r}')
if OUT:
    render(cm, os.path.join(OUT, 'zoom_sagittarius.png'))
L = host('index.lua', ist(2026, 10, 29, 23), 180, 'en')
L.execute('DATA["cards.txt"] = DATA["cards.txt"]:gsub("Lyr|[^\\n]*\\n", "")')
tx = texts(zoomed(L, s23, 41.01, 28.98, 10800, 279.23, 38.78, 'Lyr'))
check('Lyre' in tx and any('Evenings' in str(t) for t in tx) and not any('error' in str(t) for t in tx), f'a constellation without a card: its name and when to look ({tx[-3:]})')

# --- touch (1.1.0): a tap on the chart zooms in there with the card of the constellation tapped; a
# drag pans, a tap in the zoomed chart picks another card, Zoom out / Back go back
def press(L, x0, y0, x1, y1):
    L.execute(f'on_input(ctx, {{ type = "pointer", phase = "down", x = {x0}, y = {y0} }})')
    L.execute(f'on_input(ctx, {{ type = "pointer", phase = "up", x = {x1}, y = {y1} }})')


def key(L, k, phase):
    return L.eval(f'on_input(ctx, {{ type = "key", key = "{k}", phase = "{phase}" }})')


def zstate(L):
    z = L.eval('__TEST.app.zoom()')
    return None if z is None else (z.zx, z.zy, z.card)


L = host('index.lua', ist(2026, 10, 29, 23), 180, 'en')
frame(L)
SK = L.eval('__TEST.sky')
ISTV = L.eval('function(s, z, zx, zy) return { s = s, place = { name = "x", lat = 41.01, lon = 28.98 }, zoom = z, zx = zx, zy = zy } end')
fullv = ISTV(s23, None, None, None)
x, y, _ = SK.radec_to_screen(10.68, 41.27, fullv)
tap(L, x, y)
z = zstate(L)
tx = texts(frame(L))
check(z is not None and z[2] == 'And' and abs(z[0] - x) < 1 and abs(z[1] - y) < 1, f'a tap on M31 zooms in there on Andromeda: {z}')
check(tx[-4:] == ['Zoom out', '-1 h', '+1 h', 'Card'], f'the buttons while zoomed: {tx[-4:]}')
press(L, 300, 300, 200, 300)
z2 = zstate(L)
check(z2 and abs(z2[0] - (z[0] + 40)) < 0.01 and abs(z2[1] - z[1]) < 0.01 and z2[2] == 'And', f'a drag of 100 px pans 40 px of the chart: {z2}')
zv = ISTV(s23, 2.5, z2[0], z2[1])
cx, cy, cu = SK.radec_to_screen(10.13, 56.54, zv)               # Schedar
tap(L, cx, cy)
z3 = zstate(L)
check(92 < cy < 500 and z3 and z3[2] == 'Cas' and z3[:2] == z2[:2], f'a tap on Schedar picks Cassiopeia, the view stays: {z3}')
tap(L, 240, 440)
check(zstate(L)[:2] == z2[:2], 'a tap on the card does nothing')
check(key(L, 'right', 'down') and zstate(L) is not None, 'the page keys still step the hour while zoomed')
check(key(L, 'back', 'down') and zstate(L) is not None, 'Back acts on its release')
check(key(L, 'back', 'up') and zstate(L) is None, 'Back zooms out')
check(not key(L, 'back', 'up'), 'Back on the full chart is left to the host (it offers to exit)')
tap(L, 240 + 209, 322)
check(zstate(L) is None, 'a tap outside the horizon does not zoom')
tap(L, x, y)
tap(L, 300, 760)                                                # +1 h (the third of four)
z4 = zstate(L)
nx, ny, nu = SK.radec_to_screen(0.75, 43.0, ISTV(s23 + 2 * 3600, None, None, None))
check(z4 and nu > 0 and abs(z4[0] - nx) < 1 and abs(z4[1] - ny) < 1, f'+1 h re-centres on Andromeda: {z4} ({nx:.0f}, {ny:.0f})')
for _ in range(8):
    press(L, 40, 300, 440, 300)
z5 = zstate(L)
check(z5 and (z5[0] - 240) ** 2 + (z5[1] - 322) ** 2 <= 206 ** 2 + 1, f'panning stops at the horizon: {z5}')
tap(L, 80, 760)                                                 # Zoom out
check(zstate(L) is None and texts(frame(L))[-4:-1] == ['-1 h', 'now', '+1 h'], 'Zoom out: the full chart and its buttons')

# the card can be hidden: the zoomed chart takes its place, down to the buttons; the choice is kept
def disc_bottom(cmds):
    polys = [c for c in cmds if c[0] == 'polygon']
    return max(polys[0][1][k] for k in range(2, len(polys[0][1]) + 1, 2)) if polys else 0


x, y, _ = SK.radec_to_screen(10.68, 41.27, ISTV(s23 + 2 * 3600, None, None, None))
tap(L, x, y)
cm = frame(L)
tx = texts(cm)
check(tx[-4:] == ['Zoom out', '-1 h', '+1 h', 'Card'] and any('chained princess' in str(t) for t in tx), f'zoomed: a Card button: {tx[-4:]}')
check(disc_bottom(cm) <= 500, 'with the card: the chart stops above it')
check(len([c for c in cm if c[0] == 'line']) > 5, 'with the card: its constellation dashed')
tap(L, 420, 760)                                                # Card: hide
cm = frame(L)
check(not any('chained princess' in str(t) for t in texts(cm)) and disc_bottom(cm) > 600, f'hidden: no card, the chart to the buttons ({disc_bottom(cm)})')
if OUT:
    render(cm, os.path.join(OUT, 'zoom_no_card.png'))
check('card=0' in str(L.eval('store["view.txt"]')), 'kept in view.txt')
lines_ = lambda cmds: len([c for c in cmds if c[0] == 'line'])
check(lines_(cm) <= 1, f'hidden: no dashed outline ({lines_(cm)} lines)')
before = zstate(L)
vz = L.eval('function(s, zx, zy) return { s = s, place = { name = "x", lat = 41.01, lon = 28.98 }, zoom = 2.5, zx = zx, zy = zy, win_y1 = 730 } end')(
    s23 + 2 * 3600, before[0], before[1])
sx, sy, _ = SK.radec_to_screen(10.13, 56.54, vz)                # Schedar, in Cassiopeia
tap(L, sx, sy)
check(zstate(L) == before, 'hidden: a tap picks nothing')
tap(L, 420, 760)                                                # Card: show again
check(any('chained princess' in str(t) for t in texts(frame(L))) and 'card=1' in str(L.eval('store["view.txt"]')), 'shown again')
LH = host('index.lua', ist(2026, 10, 29, 23), 180, 'en', {'view.txt': 'card=0'})
frame(LH)
SKH = LH.eval('__TEST.sky')
vh = LH.eval('function(s) return { s = s, place = { name = "x", lat = 41.01, lon = 28.98 } } end')(s23)
hx, hy, _ = SKH.radec_to_screen(10.68, 41.27, vh)
tap(LH, hx, hy)
check(not any('chained princess' in str(t) for t in texts(frame(LH))), 'hidden stays hidden on the next start')
tap(L, 80, 760)

# the ☰ menu (under the time): Names and Lines on the chart, on or off, kept in view.txt; the sleep
# screen keeps both
LM = host('index.lua', ist(2026, 10, 29, 23), 180, 'en')
mrow = lambda Lx, i: (lambda t: (int(t[1]), int(t[2])))(Lx.eval('__TEST.app.menu_row')(i))
cm = frame(LM)
MX, MY = 480 - 34, 70                                          # the ☰ in the header
polylines = lambda cmds: len([c for c in cmds if c[0] == 'polyline'])
check('Pegasus' in texts(cm) and polylines(cm) > 20, 'by default: names and lines')
tap(LM, MX, MY)
cm = frame(LM)
tx = texts(cm)
check('Names' in tx and 'Lines' in tx and 'Objects' in tx, f'☰ opens the options: {tx[-6:]}')
if OUT:
    render(cm, os.path.join(OUT, 'sky_menu.png'))
tap(LM, *mrow(LM, 1))  # Names: off
cm = frame(LM)
check('Pegasus' not in texts(cm) and 'Names' in texts(cm), 'Names off: no names on the chart, the menu stays open')
tap(LM, *mrow(LM, 2))  # Lines: off
cm = frame(LM)
check(polylines(cm) == 0, f'Lines off: no figures ({polylines(cm)})')
check('names=0' in str(LM.eval('store["view.txt"]')) and 'lines=0' in str(LM.eval('store["view.txt"]')), 'kept in view.txt')
tap(LM, 240, 400)                                             # elsewhere: closes the menu, nothing else
check('Names' not in texts(frame(LM)) and LM.eval('__TEST.app.zoom()') is None, 'a tap elsewhere closes it and does not zoom')
tap(LM, 240, 400)
cm = frame(LM)
figures = [c for c in cm if c[0] == 'polyline' and len(c[1]) != 26]       # a galaxy's oval has 13 points
check(LM.eval('__TEST.app.zoom()') is not None and not figures and 'M31' not in texts(cm), 'zoomed too: no lines (the objects stay), no names')
symbols = lambda cmds: len([c for c in cmds if (c[0] == 'polyline' and len(c[1]) == 26) or c[0] == 'circle'])
n_sym = symbols(cm)
check(n_sym > 0, f'zoomed: the objects drawn ({n_sym} ovals and circles)')
tap(LM, MX, MY)
tap(LM, *mrow(LM, 3))                                         # Objects: off
tap(LM, 10, 600)                                               # closes the list
cm = frame(LM)
check(symbols(cm) < n_sym and not [c for c in cm if c[0] == 'polyline' and len(c[1]) == 26] and 'objects=0' in str(LM.eval('store["view.txt"]')),
      f'Objects off: no galaxy ovals or cluster circles ({symbols(cm)} circles left: stars and planets)')
check(LM.eval('on_input(ctx, { type = "key", key = "back", phase = "up" })') is True, 'Back zooms out')
st = {'view.txt': str(LM.eval('store["view.txt"]'))}
LR = host('index.lua', ist(2026, 10, 29, 23), 180, 'en', st)
check('Pegasus' not in texts(frame(LR)), 'off after a restart too')
LK = host('lockscreen.lua', ist(2026, 10, 29, 23), 180, 'en', st)
check('Pegasus' in texts(frame(LK)), 'the sleep screen keeps its names')
tap(LR, MX, MY)
tap(LR, *mrow(LR, 1))
tap(LR, *mrow(LR, 2))
tap(LR, *mrow(LR, 3))
check('Pegasus' in texts(frame(LR)) and polylines(frame(LR)) > 20 and 'objects=1' in str(LR.eval('store["view.txt"]')), 'all on again')

# the buttons: -1 h moves the time, Now shows the current time, Place lists cities and a pick is saved
L = host('index.lua', ist(2026, 10, 29, 14), 180, 'en')
t0 = texts(frame(L))
check('tonight' in t0[2] and t0[1] == '20:00', f'by day the app opens on tonight: {t0[1]}, {t0[2]}')
tap(L, 60, 760)
check(texts(frame(L))[1] == '19:00', '-1 h steps back an hour')
tap(L, 180, 760)
t1 = texts(frame(L))
check(t1[1] == '14:00' and 'now' in t1[2], f'Now shows the current time: {t1[1]}')
tap(L, 420, 760)
tp = texts(frame(L))
check(tp[0] == 'Place', f'Place lists cities: {tp[3:6]}')
check('İstanbul' in tp, 'the list opens on the page with the current place')
tap(L, 100, 92 + 2 * 54 + 20)                     # the third row of that page
st = L.eval('store["settings.txt"]')
picked = tp[3 + 2]
check(st is not None and ('place=' + picked) in st, f'a pick is saved: {st!r}')
check(texts(frame(L))[0] == picked, 'and the sky is drawn for it')
tap(L, 420, 760)
tap(L, 80, 760)
L.execute('PENDING(ctx, "-33.9, 18.4")')
check(texts(frame(L))[0] == '33.9°S 18.4°E', 'typed coordinates name the place')
if OUT:
    tap(L, 420, 760)
    render(frame(L), os.path.join(OUT, 'sky_place.png'))

# settings.txt written by hand on a PC (Windows line ends): an own place name and coordinates
own = {'settings.txt': 'place=Home\r\nlat=48.14\r\nlon=11.58\r\nlang=de\r\n'}
for entry in ('index.lua', 'lockscreen.lua'):
    tx = texts(frame(host(entry, ist(2026, 10, 29, 23), 60, 'en', own)))
    check(tx[0] == 'Home' and 'jetzt' in tx[2], f'{entry}: a hand-written settings.txt is read: {tx[:3]}')

# the language button on the Place page: English -> Türkçe, kept with the place, the lock follows
L = host('index.lua', ist(2026, 10, 29, 23), 180, 'en')
tap(L, 420, 760)
tap(L, 400, 30)
tp = texts(frame(L))
check(tp[0] == 'Yer' and tp[1] == 'Türkçe', f'the language button switches to Turkish: {tp[:2]}')
st = L.eval('store["settings.txt"]')
check('lang=tr' in st, f'and keeps it: {st!r}')
Lk = host('lockscreen.lua', ist(2026, 10, 29, 23), 180, 'en', {'settings.txt': st})
check('şimdi' in texts(frame(Lk))[2], 'the lock screen follows the picked language')

# an error at start is shown in full instead of closing the app ("App-Fehler, beendet" on a German
# reader, 2026-11-04): here the clock has no time zone, so working out tonight fails
for entry, title in (('index.lua', 'Sky Tonight could not start:'), ('lockscreen.lua', 'Sky Tonight lock screen error:')):
    L = host(entry, ist(2026, 10, 29, 14), 'nil', 'de')
    tx = texts(frame(L))
    check(tx and tx[0] == title and any('offset_minutes' in t or 'nil' in t for t in tx[1:]),
          f'{entry}: an error at start is shown on the screen: {tx[:3]}')

# the debug build (bundle.py --debug) writes each step to debug.txt / debug_lock.txt
for entry, fn in (('index.lua', 'debug.txt'), ('lockscreen.lua', 'debug_lock.txt')):
    L = host(entry, ist(2026, 10, 29, 23), 180, 'de', debug=True)
    frame(L)
    log = L.eval(f'store["{fn}"]') or ''
    check('place: Berlin' in log or 'lock view: Berlin' in log, f'{entry}: the debug log names the place')
    check(log.rstrip().endswith('draw done'), f'{entry}: and ends with the finished frame: {log.splitlines()[-1:]}')
L = host('index.lua', ist(2026, 10, 29, 23), 180, 'de')
frame(L)
check(L.eval('store["debug.txt"]') is None, 'the normal build writes no debug log')

# the first frame opens five font sizes, which with a user-chosen font took the German reader past
# on_draw's 1500 ms: the app asks for more time in on_load, on_draw and on_input
L = host('index.lua', ist(2026, 10, 29, 23), 180, 'de')
n0 = L.eval('extends')
frame(L)
n1 = L.eval('extends')
tap(L, 420, 760)
check(n0 == 1 and n1 == 2 and L.eval('extends') == 3, f'the app extends its time budget: {n0}, {n1}, {L.eval("extends")}')


print('\n' + ('all passed' if not fails else f'{len(fails)} FAILED'))
sys.exit(1 if fails else 0)
