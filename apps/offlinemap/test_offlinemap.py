"""Offline test of Offline Map (gamekit harness, lupa): the pack reader on packs written by the tool's
own writer (site/test/offlinemap_cli.mjs, Node 24), pack choice, geography, the view's layer rules,
the map screen, search, and the menu.

  python -I apps/offlinemap/test_offlinemap.py
"""
import json, math, os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'gamekit'))
from harness import Game  # noqa: E402

fails = []
sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def check(cond, name):
    print(('ok    ' if cond else 'FAIL  ') + name)
    if not cond:
        fails.append(name)


FIX = tempfile.mkdtemp(prefix='omfix-')
out = subprocess.run([shutil.which('node'), os.path.join(ROOT, 'site', 'test', 'offlinemap_cli.mjs'), 'fixtures', FIX],
                     capture_output=True, text=True, check=True).stdout
INFO = json.loads(out.strip().splitlines()[-1])
FILES = {n: open(os.path.join(FIX, n), 'rb').read().decode('latin-1') for n in os.listdir(FIX)}
reads = []

STUBS = r'''
files_store = {}
read_log = {}
images_alive, images_max, decodes, layer_draws = 0, 0, 0, 0
in_draw = false
ctx.budget = { extend = function(self) extends = (extends or 0) + 1; return true end }
timers = {}
ctx.after = function(self, ms, fn)
  if math.type(ms) ~= 'integer' or ms < 1 then return nil, 'invalid_argument' end   -- the API takes 1 .. 2^31-1
  timers[#timers + 1] = fn; return {} end
ctx.files = {
  list = function(self) local t = {}; for n, b in pairs(files_store) do t[#t + 1] = { name = n, size = #b } end
    table.sort(t, function(a, b) return a.name < b.name end); return t end,
  size = function(self, n) local b = files_store[n]; if not b then return nil, 'not_found' end; return #b end,
  read = function(self, n, off, len)
    off = off or 0; len = len or 65536
    assert(len <= 65536, 'a read of more than 65536 bytes: ' .. len)
    read_log[#read_log + 1] = { n = n, off = off, len = len }
    local b = files_store[n]; if not b then return nil, 'not_found' end
    return b:sub(off + 1, off + len)
  end,
}
ctx.zlib = { decompress = function(self, b) return py_unzlib(b) end }
ctx.image = { decode = function(self, b)
  assert(not in_draw, 'decode inside on_draw')
  decodes = decodes + 1
  images_alive = images_alive + 1
  if images_alive > images_max then images_max = images_alive end
  assert(images_alive <= 8, 'more than 8 runtime images alive')
  local im = { width = 256, height = 256, bytes = b }
  im.release = function(s) assert(not s.released, 'released twice'); s.released = true; images_alive = images_alive - 1 end
  return im
end }
ctx.qr = { encode = function(self, s, o) qr_last = s; images_alive = images_alive + 1
  local im = { width = 200, height = 200 }; im.release = function(x) x.released = true; images_alive = images_alive - 1 end; return im end }
ctx.screen = { width = 480, height = 800, orientation = 'portrait', set_orientation = function(self, o)
  if o == 'landscape' then ctx.screen.width, ctx.screen.height = 800, 480 else ctx.screen.width, ctx.screen.height = 480, 800 end
  ctx.screen.orientation = o; return true end }
-- offscreen layers: a picture freed before its layer:draw returns is an error (the device draws it blank)
layers_made = 0
ctx.layers = { create = function(self, w, h)
  assert(w <= 800 and h <= 800, 'a layer over 800 px')
  layers_made = layers_made + 1
  assert(layers_made <= 4, 'more than 4 layers')
  local L = { width = w, height = h, ops = {} }
  function L:draw(fn)
    layer_draws = layer_draws + 1
    local used = {}
    local lg = setmetatable({}, { __index = function(_, k) return function(_, ...)
      local a = { ... }
      if k == 'image' and a[4] and a[4].rotate and g_no_rotate then return nil, 'not_supported' end
      if k == 'image' and a[1].bytes then assert(not a[1].released, 'a freed picture drawn'); used[#used + 1] = a[1] end
      assert(#used <= 6, 'more than 6 pictures in one layer:draw')
      L.ops[#L.ops + 1] = { k = k, a = a }
    end end })
    fn(lg)
    for _, im in ipairs(used) do assert(not im.released, 'a picture freed before its layer:draw returned') end
  end
  function L:release() layers_made = layers_made - 1 end
  return L
end }
'''


def game():
    def before(g):
        L = g.L
        L.globals().py_unzlib = lambda b: __import__('zlib').decompress(b.encode('latin-1')).decode('latin-1')
        L.globals().ctx.json = L.table_from({'decode': lambda self, s: to_lua(L, json.loads(s.encode('latin-1').decode('utf-8')))})
        for n, b in FILES.items():
            L.globals().files_store[n] = b
    return Game(HERE, stubs=STUBS, encoding='latin-1', before_load=before)


def to_lua(L, v):
    if isinstance(v, dict):
        return L.table_from({k: to_lua(L, x) for k, x in v.items()})
    if isinstance(v, list):
        return L.table_from([to_lua(L, x) for x in v])
    if isinstance(v, str):
        return v.encode('utf-8').decode('latin-1')
    return v


g = game()
L = g.L
A = g.api
geo, pack, choose, view = A.geo, A.pack, A.choose, A.view

# ------------------------------------------------------------------ Task 7: pack reader, choice, geography
X15, Y15 = INFO['X15'], INFO['Y15']
P = pack.open('city.map')
check(P is not None and str(P.meta.name) == 'City' and P.levels[15] is not None and P.levels[16] is not None, 'pack.open reads meta and levels')
row = P.read_row(P, 16, 2 * Y15, 2 * X15, 2 * X15 + 9)


def fixture_tile(name, z, x, y):
    """the fixture's own bytes of a tile, read here independently of the app"""
    import struct
    b = FILES[name].encode('latin-1')
    nlev, zoff = b[10], struct.unpack_from('<I', b, 24)[0]
    for i in range(nlev):
        lz, _, _, x0, y0, nx, ny, idx = struct.unpack_from('<BBHIIHHI', b, zoff + 20 * i)
        if lz == z and x0 <= x < x0 + nx and y0 <= y < y0 + ny:
            off, ln = struct.unpack_from('<II', b, idx + 8 * ((y - y0) * nx + (x - x0)))
            return b[off:off + ln].decode('latin-1') if ln else None
    return None


want = fixture_tile('city.map', 16, 2 * X15, 2 * Y15)
check(row[2 * X15] == want, 'read_row gives the fixture tile byte for byte')
check(row[2 * X15 + 1] is False and P.read_row(P, 16, 2 * Y15 + 2, 2 * X15 + 3, 2 * X15 + 3)[2 * X15 + 3] is False, 'empty tiles read as false')
L.execute('read_log = {}')
big = P.read_row(P, 16, 2 * Y15 + 4, 2 * X15, 2 * X15 + 9)
n_ok = sum(1 for i in range(10) if big[2 * X15 + i] == fixture_tile('city.map', 16, 2 * X15 + i, 2 * Y15 + 4))
check(n_ok == 10 and all(int(r.len) <= 65536 for r in L.globals().read_log.values()) and len(L.globals().read_log) >= 3,
      f'a row of over 70 KB reads right in reads of at most 64 KB ({len(L.globals().read_log)} reads)')
L.globals().files_store['bad.map'] = 'NOTAMAP!' + '\0' * 60
bad, err = pack.open('bad.map')
check(bad is None and str(err) == 'not a map pack', f'a wrong magic: {err}')
packs = L.table_from([pack.open('city.map'), pack.open('inner.map'), pack.open('overview.map')])
inner_x, inner_y = 4 * X15 + 5, 4 * Y15 + 5
pk = choose.pick(packs, 16, 2 * X15 + 3, 2 * Y15 + 2)
check(pk is not None and str(pk.meta.name) == 'Inner', 'pick: inside the inner area at z16, the smaller pack wins')
check(str(choose.pick(packs, 16, 2 * X15, 2 * Y15).meta.name) == 'City', 'pick: outside it, the city pack')
ox = (X15 >> 2)
check(str(choose.pick(packs, 13, ox, Y15 >> 2).meta.name) == 'Overview', 'pick: z13, only the overview')
check(choose.pick(packs, 16, 0, 0) is None, 'pick: outside every pack, nil')
cxi, cyi = (2 * X15 + 3) * 256 + 128, (2 * Y15 + 2) * 256 + 128
ci, co = choose.limits(packs, 16, cxi, cyi)
check(ci is True and co is True, 'limits: z16 in the inner area can go in and out')
ci, co = choose.limits(packs, 17, cxi * 2, cyi * 2)
check(ci is False and co is True, 'limits: z17 is the deepest there')
ci, co = choose.limits(packs, 8, (ox >> 5) * 256 + 128, ((Y15 >> 2) >> 5) * 256 + 128)
check(ci is True and co is False, 'limits: z8 is the widest')
for z, lat, m, px in ((14, 410000000, 500, 69), (17, 410000000, 100, 111), (19, 410000000, 20, 89), (10, 600000000, 5000, 65), (15, 409850000, 200, 55)):
    a, b = geo.scale_bar(z, lat)
    check(int(a) == m and abs(int(b) - px) <= 1, f'scale bar z{z}: {a} m / {b} px')


def merc(lon, lat, z):
    w = 256 * 2 ** z
    return (lon + 180) / 360 * w, (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * w


ax, ay = merc(29.03, 40.99, 19)
anc = geo.anchor(19, int(ax), int(ay))
worst = 0
for i in range(20):
    lon = 29.03 + (i % 5 - 2) * 0.006
    lat = 40.99 + (i // 5 - 2) * 0.0045
    x, y = geo.to_px(anc, round(lon * 1e7), round(lat * 1e7))
    rx, ry = merc(lon, lat, 19)
    worst = max(worst, abs(x - rx), abs(y - ry))
check(worst <= 1.0, f'to_px at z19 within 2 km is within 1 px (worst {worst:.2f})')
lo, la = geo.from_px(anc, int(ax) + 1000, int(ay) - 800)
x2, y2 = geo.to_px(anc, lo, la)
check(abs(x2 - int(ax) - 1000) <= 1 and abs(y2 - int(ay) + 800) <= 1, 'from_px inverts to_px')
lat7, lon7 = geo.parse_coords('41.0082, 28.9784')
check(int(lat7) == 410082000 and int(lon7) == 289784000, f'coords decimal: {lat7} {lon7}')
lat7, lon7 = geo.parse_coords('-33.8688 151.2093')
check(int(lat7) == -338688000 and int(lon7) == 1512093000, f'coords with a space and a minus: {lat7} {lon7}')
lat7, lon7 = geo.parse_coords('41°0\'29.5"N 28°58\'42.2"E'.encode('utf-8').decode('latin-1'))
check(lat7 is not None and abs(int(lat7) - 410081944) <= 3 and abs(int(lon7) - 289783889) <= 3, f'coords DMS: {lat7} {lon7}')
r1, r2 = geo.parse_coords('abc')
check(r1 is None and r2 is not None, 'bad coords: nil and a reason')
# every later caller re-anchors instead of projecting far points (single-precision floats on the device)
L.execute('''local g = __TEST.api.geo; local f = g.to_px
g.to_px = function(A, lon7, lat7)
  assert(math.abs(lon7 - A.lon7) <= 20000000 and math.abs(lat7 - A.lat7) <= 20000000, 'to_px far from its anchor')
  return f(A, lon7, lat7) end''')

# ------------------------------------------------------------------ Task 8: the view
L.execute('layers_made = 0')
V = view.new(L.globals().ctx, 480, 714)
V.packs = L.table_from([pack.open('city.map')])
cx, cy = (2 * X15 + 5) * 256, (2 * Y15 + 3) * 256
L.execute('decodes = 0; layer_draws = 0')
V.set(V, 16, cx, cy)
left, top = cx - 240, cy - 357
vis = [(x, y) for y in range(top >> 8, (top + 713 >> 8) + 1) for x in range(left >> 8, (left + 479 >> 8) + 1)]
nonempty = [t for t in vis if fixture_tile('city.map', 16, *t) is not None]
check(int(L.globals().decodes) == len(nonempty) and int(L.globals().layer_draws) >= math.ceil(len(nonempty) / 6),
      f'set: every visible tile decoded once, in batches of at most 6 ({L.globals().decodes} of {len(vis)}; {L.globals().layer_draws} draws)')
check(int(L.globals().images_alive) == 0, 'no picture left alive after composing')
L.execute('decodes = 0')
V.pan(V, 128, 0)
nl, nt = cx + 128 - 240, cy - 357
strip = [(x, y) for y in range(nt >> 8, (nt + 713 >> 8) + 1) for x in range((nl + 479 - 127) >> 8, ((nl + 479) >> 8) + 1)]
want_n = sum(1 for t in strip if fixture_tile('city.map', 16, *t) is not None)
vis2 = [(x, y) for y in range(nt >> 8, (nt + 713 >> 8) + 1) for x in range(nl >> 8, ((nl + 479) >> 8) + 1)]
check(int(L.globals().decodes) == want_n and want_n < sum(1 for t in vis2 if fixture_tile('city.map', 16, *t)) and int(V.cx) == cx + 128,
      f'pan by 128 px: only the tiles of the new strip decoded ({L.globals().decodes} of {want_n})')
gx, gy = int(V.cx) - 240 + 240, int(V.cy) - 357 + 357
z0 = int(V.z)
V.zoom(V, 1, 240, 357)
check(int(V.z) == z0 + 1 and abs(int(V.cx) - 2 * gx) <= 1 and abs(int(V.cy) - 2 * gy) <= 1, 'zoom in keeps the point under the finger')
gx2 = int(V.cx) - 240 + 100
V.zoom(V, -1, 100, 357)
check(int(V.z) == z0 and abs((int(V.cx) - 240 + 100) - gx2 // 2) <= 1, 'zoom out keeps the point too')
L.execute('decodes = 0')
V.set(V, 16, 1000, 1000)
check(V.edge is True and int(L.globals().decodes) == 0 and int(V.missing) > 0, 'outside every pack: the edge, nothing decoded')
V.set(V, 16, cx, cy)
check(V.edge is False, 'inside: no edge')
L.execute('in_draw = true')
V.draw(V, L.globals().gg, 0, 34)
L.execute('in_draw = false')
check(int(L.globals().images_alive) == 0, 'drawing the view decodes nothing')



# ------------------------------------------------------------------ Task 9: the map screen
L.execute('''
function ev_drag(x0, y0, x1, y1) on_input(ctx, {type='pointer', phase='down', x=x0, y=y0})
  return on_input(ctx, {type='pointer', phase='up', x=x1, y=y1, down_x=x0, down_y=y0, gesture='swipe'}) end
function ev_dtap(x, y) on_input(ctx, {type='pointer', phase='down', x=x, y=y})
  return on_input(ctx, {type='pointer', phase='up', x=x, y=y, down_x=x, down_y=y, gesture='double_tap'}) end
function ev_long(x, y) on_input(ctx, {type='pointer', phase='down', x=x, y=y})
  on_input(ctx, {type='pointer', phase='hold', gesture='long', x=x, y=y})
  return on_input(ctx, {type='pointer', phase='up', x=x, y=y, down_x=x, down_y=y, gesture='long'}) end
function ev_key(k) on_input(ctx, {type='key', key=k, phase='down'}); return on_input(ctx, {type='key', key=k, phase='up'}) end
''')


def seed_view(z, cx, cy):
    L.globals().store['view.txt'] = f'{z} {cx} {cy}'
    L.execute('layers_made = 0')
    g.restart()
    return g.api.state()


st = seed_view(16, (2 * X15 + 5) * 256, (2 * Y15 + 3) * 256)
t = g.texts()
check(st.screen == 'map' and int(st.z) == 16 and 'Inner' in t and 'z16' in t, f'restored view: the pack at the centre (the smaller one) and the zoom in the header: {t[:4]}')
check(any(s.endswith(' m') for s in t) and '-' in t and '+' in t and 'Search' in t and 'Menu' in t, f'scale bar and the bottom bar: {t}')
cx0 = int(g.api.state().cx)
L.eval('ev_drag')(300, 400, 200, 400)
check(int(g.api.state().cx) == cx0 + 100, 'a drag pans by its length')
check(str(L.globals().store['view.txt']).startswith('16 '), 'the view is saved after a move')
L.eval('ev_key')('right')
check(int(g.api.state().cx) == cx0 + 100 + 240, 'the right key pans by half the map')
L.eval('ev_dtap')(240, 34 + 357)
check(int(g.api.state().z) == 17 or 'No closer level here' in g.texts(), 'a double tap zooms in (or says there is none)')
# the deepest level here: + is faded and does nothing but say so
st = seed_view(17, (4 * X15 + 8) * 256, (4 * Y15 + 6) * 256)       # inside inner.map at z17
check(int(st.z) == 17 and '(+)' in g.texts(), f'at the deepest level + is faded: {g.texts()}')
g.tap_label('(+)')
check(int(g.api.state().z) == 17 and 'No closer level here' in g.texts(), 'tapping it says there is no closer level')
L.eval('ev_dtap')(240, 300)
check(int(g.api.state().z) == 17, 'a double tap does nothing there either')
check(len(L.globals().timers) >= 1, 'a timer redraws the header when the message is due to go (on_tick never runs)')
L.execute('timers = {}')
g.advance(3500)
check('No closer level here' not in g.texts(), 'the message goes after 3 s')
g.tap_label('-')
check(int(g.api.state().z) == 16, '- zooms out')
st = seed_view(8, ((X15 >> 7) * 256) + 128, ((Y15 >> 7) * 256) + 128)
check('(-)' in g.texts(), f'at the widest level - is faded: {g.texts()}')
g.tap_label('(-)')
check(int(g.api.state().z) == 8 and 'No wider level here' in g.texts(), 'and says so')
# the edge of the map
st = seed_view(16, (2 * X15 + 9) * 256 + 200, (2 * Y15 + 3) * 256)
check('Edge of the map' in g.texts(), f'part of the screen outside every pack: {g.texts()[:3]}')
# long press: the coordinates and Add bookmark here
st = seed_view(16, (2 * X15 + 5) * 256, (2 * Y15 + 3) * 256)
L.eval('ev_long')(240, 34 + 357)
t = g.texts()
check(any(s.startswith('40.') and ', 29.' in s for s in t) and 'Add bookmark here' in t, f'long press: coordinates and a bookmark button: {t[-6:]}')
r = L.eval('ev_key')('back')
check(r is True and g.api.state().modal is None, 'Back closes the box')
r = L.eval('ev_key')('back')
check(r is False, 'Back on the map leaves it to the host (exit)')
# outside every pack: Map packs offered
st = seed_view(16, 1000, 1000)
check('Map packs' in g.texts(), 'outside every pack: Map packs offered')
# no packs at all: the first page
saved_files = {n: L.globals().files_store[n] for n in FILES}
saved_files['bad.map'] = L.globals().files_store['bad.map']
for n in saved_files:
    L.globals().files_store[n] = None
L.execute('qr_last = nil')
L.globals().store['view.txt'] = None
L.execute('layers_made = 0')
g.restart()
t = ' '.join(g.texts())
check(g.api.state().screen == 'start' and 'AppFiles/offlinemap/' in t and 'no live position' in t.lower(), f'no packs: the first page: {t[:160]}')
check(str(L.globals().qr_last) == 'https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/offlinemap/', 'with a QR code of the Tools page')
for n, b in saved_files.items():
    L.globals().files_store[n] = b
L.execute('layers_made = 0')
g.restart()
L.execute('in_draw = true')
g.draw()
L.execute('in_draw = false')
check(g.api.state().screen == 'map', 'on_draw decodes nothing (the stub asserts it)')

# ------------------------------------------------------------------ Task 10: search
names = g.api.names
ps = L.table_from([pack.open('city.map'), pack.open('inner.map'), pack.open('overview.map')])
res = names.search(ps, 'kad', 10)
check(len(res) >= 1 and str(res[1].name) == 'Kadıköy'.encode('utf-8').decode('latin-1') and str(res[1].pack.meta.name) == 'City',
      f'search kad finds Kadıköy in city.map ({len(res)})')
check(len(names.search(ps, 'KADI', 10)) >= 1 and len(names.search(ps, 'kadı'.encode('utf-8').decode('latin-1'), 10)) >= 1, 'KADI and kadı find it too')
m = names.search(ps, 'moda', 10)
kinds = sorted((str(e.name), int(e.kind)) for e in m.values())
check(('Moda Caddesi', 6) in kinds and ('Moda', 4) in kinds, f'moda: the street and the district from two packs: {kinds}')
check(len(names.search(ps, 'zzz', 10)) == 0, 'no match: an empty list')
check(int(names.ZOOM[6]) == 17 and int(names.ZOOM[2]) == 13 and int(names.ZOOM[8]) == 15, 'jump zooms: street 17, town 13, peak 15')
L.execute('read_log = {}')
names.search(L.table_from([pack.open('city.map')]), 'fener', 5)
blocks = [r for r in L.globals().read_log.values() if int(r.len) < 65536 and int(r.off) > 64]
check(len(L.globals().read_log) <= 2 + 4, f'a search reads at most two blocks a pack (after the open: {len(L.globals().read_log)} reads)')
# the search screen
st = seed_view(16, (2 * X15 + 5) * 256, (2 * Y15 + 3) * 256)
n_in = len(L.globals().inputs)
g.tap_label('Search')
check(len(L.globals().inputs) == n_in + 1, 'Search opens the keyboard')
L.globals().inputs[len(L.globals().inputs)](L.globals().ctx, 'fener')
t = g.texts()
check(g.api.state().screen == 'search' and any('Fenerbahçe Parkı'.encode('utf-8').decode('latin-1') in s for s in t) and any('City' in s for s in t),
      f'results with the name, kind and pack: {t[:6]}')
g.tap_label('Fenerbahçe Parkı'.encode('utf-8').decode('latin-1'))
st = g.api.state()
check(st.screen == 'map' and int(st.z) == 15 and st.marker is not None, f'a tap jumps to the place at its zoom (a park: 15, got {st.z}) with a marker')
L.eval('ev_drag')(300, 400, 260, 400)
check(g.api.state().marker is not None, 'the marker stays after one pan')
L.eval('ev_drag')(300, 400, 260, 400)
check(g.api.state().marker is None, 'and goes after the second')
L.eval('ev_key')('back')

# ------------------------------------------------------------------ Task 11: the menu
gpx = g.api.gpx
G1 = '''<?xml version="1.0"?><gpx><trk><name>Walk</name><trkseg>
<trkpt lat="40.9900" lon="29.0300"></trkpt><trkpt lon="29.0310" lat="40.9905"/>
<trkpt lat="40.9910" lon="29.0320"/><trkpt lat="40.9915" lon="29.0330"/><trkpt lat="40.9920" lon="29.0340"/></trkseg></trk></gpx>'''
r = gpx.parse(G1)
check(r is not None and str(r.name) == 'Walk' and len(r.points) == 5 and int(r.points[2].lon7) == 290310000, 'a track of 5 points, attributes in either order')
r2 = gpx.parse('<gpx><rte><name>R</name><rtept lat="1.5" lon="2.25"/><rtept lat="1.6" lon="2.35"/></rte></gpx>')
check(r2 is not None and len(r2.points) == 2 and int(r2.points[1].lat7) == 15000000, 'a route parses')
bad1, why = gpx.parse('<gpx><trk></trk></gpx>')
check(bad1 is None and why is not None, 'a file with no points: nil and a reason')
long_pts = L.table_from([L.table_from({'lat7': 409000000 + i * 1000, 'lon7': 290000000 + i * 1000}) for i in range(2000)])
check(len(gpx.thin(long_pts, 10)) < 200 and len(gpx.thin(long_pts, 19)) > 1000, 'thinning: a 2000-point line at z10 keeps fewer than 200')
mer = L.table_from([L.table_from({'lat7': 400000000, 'lon7': 290000000}), L.table_from({'lat7': 410000000, 'lon7': 290000000})])
check(abs(int(gpx.length_m(mer)) - 111195) <= 200, f'length of 1 degree of meridian: {gpx.length_m(mer)}')
# bookmarks
st = seed_view(16, (2 * X15 + 5) * 256, (2 * Y15 + 3) * 256)
L.globals().store['bookmarks.txt'] = None
L.execute('layers_made = 0'); g.restart()
L.eval('ev_long')(240, 300)
g.tap_label('Add bookmark here')
L.globals().inputs[len(L.globals().inputs)](L.globals().ctx, 'Zeta point')
L.eval('ev_long')(100, 200)
g.tap_label('Add bookmark here')
L.globals().inputs[len(L.globals().inputs)](L.globals().ctx, 'Alpha cafe')
check(str(L.globals().store['bookmarks.txt']).count('\n') >= 1 and 'Zeta point\t' in str(L.globals().store['bookmarks.txt']), 'bookmarks are kept in storage')
g.tap_label('Menu')
check(g.api.state().screen == 'list' and 'Bookmarks' in g.texts() and 'Routes' in g.texts() and 'Go to coordinates' in g.texts(), f'the menu: {g.texts()}')
g.tap_label('Bookmarks')
t = g.texts()
check(t.index('Alpha cafe') < t.index('Zeta point'), f'bookmarks sorted by name: {t}')
L.execute("on_input(ctx, {type='pointer', phase='down', x=40, y=0})")
xa, ya = g.recs()['Alpha cafe']
L.eval('ev_long')(xa + 3, ya + 5)
check('Rename' in g.texts() and 'Delete' in g.texts(), 'long press on a bookmark: Rename and Delete')
g.tap_label('Delete')
check('Alpha cafe' not in g.texts() and 'Alpha cafe' not in str(L.globals().store['bookmarks.txt']), 'deleted')
g.tap_label('Zeta point')
check(g.api.state().screen == 'map' and g.api.state().marker is not None, 'a tap on a bookmark jumps there with a marker')
# routes
L.globals().files_store['Walk.gpx'] = G1
g.tap_label('Menu'); g.tap_label('Routes')
check('Walk.gpx' in g.texts(), f'routes list the GPX files: {g.texts()}')
L.execute('layers_made = 0')
g.tap_label('Walk.gpx')
t = g.texts()
check(g.api.state().screen == 'map' and any('km' in s or ' m' in s for s in t) and g.api.state().route is not None, f'opening a route: back to the map, its length: {t[:4]}')
dots = [o for o in g.api.layer_ops().values() if str(o.k) == 'circle']
halos = [o for o in dots if o.a[4] is not None and int(o.a[4].color) == 0 and o.a[4].fill]
cores = [o for o in dots if o.a[4] is not None and int(o.a[4].color) == 15 and o.a[4].fill]
check(len(cores) >= 5 and len(halos) == len(cores), f'the route drawn as black beads with white rings ({len(cores)} beads)')
g.tap_label('Menu'); g.tap_label('Routes'); g.tap_label('Fit route')
check(g.api.state().screen == 'map' and int(g.api.state().z) >= 15, f'Fit: the deepest level the route fits ({g.api.state().z})')
# go to coordinates
g.tap_label('Menu'); g.tap_label('Go to coordinates')
L.globals().inputs[len(L.globals().inputs)](L.globals().ctx, '40.9905, 29.0310')
check(g.api.state().screen == 'map' and g.api.state().marker is not None, 'Go to coordinates jumps there with a marker')
g.tap_label('Menu'); g.tap_label('Go to coordinates')
L.globals().inputs[len(L.globals().inputs)](L.globals().ctx, 'nonsense')
check(any('41.0082' in s for s in g.texts()), f'bad coordinates: the reason shown: {g.texts()[:3]}')
L.eval('ev_key')('back')
# packs, screen, about
g.tap_label('Menu'); g.tap_label('Map packs')
t = ' '.join(g.texts())
check('City' in t and 'z15-16' in t and 'Overview' in t and 'z8-13' in t and ('MB' in t or 'KB' in t), f'map packs: names, levels, sizes: {t[:200]}')
L.eval('ev_key')('back')
g.tap_label('Menu')
L.execute('layers_made = 0')
g.tap_label('Screen: portrait')
check(int(L.globals().ctx.screen.width) == 800 and 'landscape' in str(L.globals().store['settings.txt']), 'Screen turns to landscape and is saved')
L.execute('layers_made = 0')
g.tap_label('Menu'); g.tap_label('Screen: landscape')
check(int(L.globals().ctx.screen.width) == 480, 'and back to portrait')
g.tap_label('Menu'); g.tap_label('About')
t = ' '.join(g.texts())
check('OpenStreetMap' in t and '1.0.0' in t and str(L.globals().qr_last).endswith('/tools/offlinemap/'), f'About: attribution, version, QR: {t[:160]}')
L.eval('ev_key')('back')

# ------------------------------------------------------------------ review fixes
# M4: the shared fold word list, through fold.lua
fold_lua = L.eval('function(s) return __TEST.api.fold(s) end')
rows = [r.split('\t') for r in open(os.path.join(ROOT, 'site', 'test', 'fixtures', 'fold_words.tsv'), encoding='utf-8').read().split('\n')
        if r and not r.startswith('#')]
bad_rows = [a for a, b in rows if str(fold_lua(a.encode('utf-8').decode('latin-1'))).encode('latin-1').decode('utf-8') != b]
check(len(rows) >= 120 and not bad_rows, f'fold.lua agrees with every row of the shared word list ({len(rows)}; {bad_rows[:3]})')
# I3: a key that spans several blocks is found in full
many = pack.open('many.map')
got = g.api.names.search(L.table_from([many]), 'moda', 1000)
check(len(got) == 400, f'a name in 400 entries across blocks: all found ({len(got)})')
# I1: a long press as the firmware sends it (hold without a gesture; the gesture comes on up)
L.execute('''function ev_long2(x, y) on_input(ctx, {type='pointer', phase='down', x=x, y=y})
  on_input(ctx, {type='pointer', phase='hold', x=x, y=y, down_x=x, down_y=y})
  return on_input(ctx, {type='pointer', phase='up', x=x, y=y, down_x=x, down_y=y, gesture='long'}) end''')
st = seed_view(16, (2 * X15 + 5) * 256, (2 * Y15 + 3) * 256)
L.eval('ev_long2')(240, 300)
check('Add bookmark here' in g.texts(), f'a hold without a gesture opens the point box: {g.texts()[-4:]}')
L.eval('ev_key')('back')
# C1: a pan draws the route at the same global pixels, without re-anchoring
g.tap_label('Menu'); g.tap_label('Routes'); g.tap_label('Walk.gpx')
L.execute('''anchor_calls = 0; local G = __TEST.api.geo; local f = G.anchor
G.anchor = function(...) anchor_calls = anchor_calls + 1; return f(...) end''')


def route_points():
    """the beads drawn by the last paint, as global pixels, and the view's rectangle"""
    st = g.api.state()
    left, top = int(st.cx) - 240, int(st.cy) - 357
    pts = set()
    for o in g.api.layer_ops().values():
        if str(o.k) == 'circle' and o.a[4] is not None and int(o.a[4].color) == 15:
            pts.add((int(o.a[1]) + left, int(o.a[2]) + top))
    return pts, (left, top, left + 480, top + 714)


def inside_both(p, r1, r2):
    return all(r[0] + 10 <= p[0] < r[2] - 10 and r[1] + 10 <= p[1] < r[3] - 10 for r in (r1, r2))


g.api.clear_ops()
L.eval('ev_drag')(300, 400, 250, 400)          # drags over 20 px: real pans
p1, r1 = route_points()
g.api.clear_ops()
L.eval('ev_drag')(300, 400, 343, 370)
p2, r2 = route_points()
c1 = {p for p in p1 if inside_both(p, r1, r2)}
c2 = {p for p in p2 if inside_both(p, r1, r2)}
check(int(L.globals().anchor_calls) == 0 and c1 and c1 == c2,
      f'pans draw the beads at the same global pixels, no re-anchoring ({L.globals().anchor_calls} anchors, {len(c1)} / {len(c2)})')
# I5: a route is read with the time budget extended first
L.execute('''local X = __TEST.api.gpx; local f = X.parse
X.parse = function(...) extends_at_parse = extends or 0; return f(...) end''')
L.execute('extends = 0')
g.tap_label('Menu'); g.tap_label('Routes'); g.tap_label('Walk.gpx')
check(int(L.globals().extends_at_parse or 0) >= 1, 'the budget is extended before a route is read')
# M1: the poles do not crash a jump
g.tap_label('Menu'); g.tap_label('Go to coordinates')
L.globals().inputs[len(L.globals().inputs)](L.globals().ctx, '90, 0')
check(not any(s.startswith('ERR') for s in g.texts()) and g.api.state().screen == 'map', f'90, 0: no error: {g.texts()[:3]}')

# the user, on the device: choosing a pack in Map packs goes to it
st = seed_view(16, (2 * X15 + 5) * 256, (2 * Y15 + 3) * 256)
g.tap_label('Menu'); g.tap_label('Map packs')
g.tap_label('Overview')
st = g.api.state()
check(st.screen == 'map' and 8 <= int(st.z) <= 13 and 'Overview' in g.texts(), f'a tap on a pack goes to it: z{st.z}, {g.texts()[:3]}')

# the user, on the device: opening a route goes to it (no separate Fit needed)
st = seed_view(8, ((X15 >> 7) * 256) + 128, ((Y15 >> 7) * 256) + 128)     # far out, at z8
g.tap_label('Menu'); g.tap_label('Routes'); g.tap_label('Walk.gpx')
st = g.api.state()
check(st.screen == 'map' and int(st.z) >= 15, f'opening a route goes to it, as close as it fits (z{st.z})')
L.globals().files_store['Far.gpx'] = '<gpx><trk><trkseg><trkpt lat="-33.86" lon="151.20"/><trkpt lat="-33.87" lon="151.21"/></trkseg></trk></gpx>'
g.tap_label('Menu'); g.tap_label('Routes'); g.tap_label('Far.gpx')
check(any('No map pack' in s for s in g.texts()), f'a route outside every pack says so: {g.texts()[:2]}')
L.globals().files_store['Far.gpx'] = None

# the user, on the device: the screen turns only after the callback that asked for it
L.execute('''defer_orient = true
pending_orient = nil
local so = ctx.screen.set_orientation
ctx.screen.set_orientation = function(self, o) if defer_orient then pending_orient = o; return true end return so(self, o) end
function apply_orient()
  if pending_orient then
    if pending_orient == 'landscape' then ctx.screen.width, ctx.screen.height = 800, 480 else ctx.screen.width, ctx.screen.height = 480, 800 end
    ctx.screen.orientation = pending_orient; pending_orient = nil
  end
end
function run_timers() local t = timers; timers = {}; for _, f in ipairs(t) do f() end end''')
st = seed_view(16, (2 * X15 + 5) * 256, (2 * Y15 + 3) * 256)
L.execute('layers_made = 0')
g.tap_label('Menu'); g.tap_label('Screen: portrait')
L.execute('apply_orient()')                 # the host turns the screen between callbacks
g.draw()                                    # the next frame notices
L.execute('run_timers()')
r = g.recs()
check('Menu' in r and r['Menu'][1] < 480 and int(g.api.state().vw) == 800, f'after turning, the map and the buttons fit the landscape screen: {r.get("Menu")}, view {g.api.state().vw}')
g.tap_label('Menu'); g.tap_label('Screen: landscape')
L.execute('apply_orient()')
g.draw(); L.execute('run_timers()')
r = g.recs()
check('Menu' in r and r['Menu'][1] > 700 and int(g.api.state().vw) == 480, f'and back to portrait: {r.get("Menu")}')
L.execute('defer_orient = false')

# ------------------------------------------------------------------ Task 13: street names along a route
labels = g.api.labels
SG = ('<?xml version="1.0"?><gpx><metadata><name>Street walk</name></metadata>'
      '<wpt lat="40.9840000" lon="29.0260000"><name>Moda Caddesi</name><type>street</type></wpt>'
      '<wpt lat="40.9841000" lon="29.0261000"><name>Not a street</name></wpt>'
      '<trk><name>Street walk</name><trkseg><trkpt lat="40.9830" lon="29.0260"/><trkpt lat="40.9850" lon="29.0260"/></trkseg></trk></gpx>')
r = gpx.parse(SG)
check(str(r.name) == 'Street walk' and len(r.labels) == 1 and str(r.labels[1].name) == 'Moda Caddesi' and int(r.labels[1].lat7) == 409840000,
      'street waypoints become labels; the route keeps its own name')
near = L.table_from([L.table_from({'lat7': 409830000, 'lon7': 290260000}), L.table_from({'lat7': 409850000, 'lon7': 290260000})])
far = L.table_from([L.table_from({'lat7': 409930000, 'lon7': 290360000}), L.table_from({'lat7': 409950000, 'lon7': 290360000})])
ps1 = L.table_from([pack.open('city.map')])
got = [str(e.name) for e in labels.from_index(ps1, near, 12).values()]
check(got == ['Moda Caddesi'], f'from the name index: the street the route runs along ({got})')
check(len(labels.from_index(ps1, far, 12)) == 0, 'and nothing for a route far from it')
check(abs(int(labels.angle(0, 10))) == 90 and int(labels.angle(-10, 0)) == 0 and int(labels.angle(-10, -10)) == 45 and int(labels.angle(10, -10)) == -45,
      'label angles read left to right (-90..90)')
# two names close together on a route: the second one, whose box would overlap, is left out
vpx = L.table_from([1000, 1000, 1000, 1400])
two = L.table_from([L.table_from({'name': 'Moda Caddesi', 'lat7': 0, 'lon7': 0}), L.table_from({'name': 'Moda Caddesi', 'lat7': 0, 'lon7': 0})])
L.execute("""local G = __TEST.api.geo; orig_lonlat = G.lonlat_px; local f = orig_lonlat
G.lonlat_px = function(z, lon7, lat7) if lon7 == 0 and lat7 == 0 then return 1000, 1200 end return f(z, lon7, lat7) end""")
placed = labels.place(vpx, two, 16, lambda ch: 10 * len(ch), 20)
check(len(placed) == 1 and int(placed[1].x) > 1000, f'an overlapping second label is left out; the box sits right of a north-south route ({len(placed)})')
L.execute("""local G = __TEST.api.geo; local f = orig_lonlat
G.lonlat_px = function(z, lon7, lat7) if lon7 < 100 and lat7 == 0 then return 1000, 1000 + lon7 end return f(z, lon7, lat7) end""")
three = L.table_from([L.table_from({'name': 'Sahil Yolu', 'lat7': 0, 'lon7': 0}), L.table_from({'name': 'Sahil Yolu', 'lat7': 0, 'lon7': 60}),
                      L.table_from({'name': 'Other Street', 'lat7': 0, 'lon7': 90})])
vpx2 = L.table_from([1000, 900, 1000, 1500])
names_placed = [str(three[int(p.idx)].name) for p in labels.place(vpx2, three, 16, lambda s: 10 * len(s), 20).values()]
check(names_placed.count('Sahil Yolu') == 1, f'the same name not twice within 700 px ({names_placed})')
L.execute("__TEST.api.geo.lonlat_px = orig_lonlat")
# opening a route with street waypoints writes its street's name beside it, level, in a white box
# (the reader turns no pictures); on a north-south route the box is to its right, off the beads
L.globals().files_store['Street walk.gpx'] = SG
st = seed_view(16, (2 * X15 + 5) * 256, (2 * Y15 + 3) * 256)
L.execute('layers_made = 0')
L.globals().store['settings.txt'] = None
g.restart()
g.api.clear_ops()
g.tap_label('Menu'); g.tap_label('Routes'); g.tap_label('Street walk.gpx')


def label_ops():
    return [(str(o.a[3]), int(o.a[1]), int(o.a[2])) for o in g.api.layer_ops().values() if str(o.k) == 'text']


lt = label_ops()
beads = [int(o.a[1]) for o in g.api.layer_ops().values() if str(o.k) == 'circle' and o.a[4] is not None and int(o.a[4].color) == 15]
check(int(g.api.state().z) >= 15 and [t for t, _, _ in lt] == ['Moda Caddesi'] and beads and lt[0][1] > max(beads) + 4,
      f'the name written level, to the right of a north-south route ({lt}, beads at x {min(beads) if beads else None}..{max(beads) if beads else None})')
# the menu turns street names off (and on), and it is kept
g.tap_label('Menu')
check('Street names: on' in g.texts(), f'the menu offers street names: {g.texts()}')
g.tap_label('Street names: on')
g.api.clear_ops()
L.eval('ev_drag')(300, 400, 250, 400)
check(not label_ops() and 'names=off' in str(L.globals().store['settings.txt']), 'turned off: no names drawn, and it is kept')
g.tap_label('Menu'); g.tap_label('Street names: off')
g.api.clear_ops()
L.eval('ev_drag')(250, 400, 300, 400)
check([t for t, _, _ in label_ops()] == ['Moda Caddesi'], 'and on again')
g.tap_label('Menu'); g.tap_label('Routes'); g.tap_label('Hide route')
L.globals().files_store['Street walk.gpx'] = None

print('\n' + ('all passed' if not fails else f'{len(fails)} FAILED'))
shutil.rmtree(FIX, ignore_errors=True)
sys.exit(1 if fails else 0)
