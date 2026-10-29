"""Offline test of Sky Tonight (Lua 5.4 through lupa) against known sky events: full and new
moons (two of them eclipses, so exact), planet oppositions and Venus's greatest elongation,
Polaris's altitude, sunrise and sunset against NOAA's solar calculator, and the precision the
reader's single floats leave.

  python -I apps/skytonight/test_sky.py
"""
import calendar, math, os, struct, sys
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
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
}
local function rec(kind) return function(self, ...) cmds[#cmds + 1] = { kind, ... } end end
gg = { clear = function(self) cmds = {} end, text = rec('text'), rect = rec('rect'), circle = rec('circle'),
       line = rec('line'), polyline = rec('polyline'), polygon = rec('polygon') }
"""
DATA = {n: open(os.path.join(HERE, 'data', n), encoding='utf-8').read() for n in ('stars.txt', 'lines.txt', 'names.txt', 'stars_named.txt')}


def host(entry, epoch_sec, offset_min, locale='en', store=None):
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    L.execute(STUBS)
    L.globals().DATA = L.table_from(DATA)
    L.execute(f'clock.epoch_sec = {epoch_sec}; clock.offset_minutes = {offset_min}; locale = "{locale}"')
    if store:
        for k, v in store.items():
            L.globals().store[k] = v
    L.execute(open(os.path.join(HERE, entry), encoding='utf-8').read())
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


print('\n' + ('all passed' if not fails else f'{len(fails)} FAILED'))
sys.exit(1 if fails else 0)
