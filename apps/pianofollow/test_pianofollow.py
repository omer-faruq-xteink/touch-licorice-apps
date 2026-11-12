"""Offline tests of Piano Follow (gamekit harness, Lua 5.4 under lupa): .xtscore reading, the BLE MIDI
parser, the follower, practice, the score screen, the keyboard connection and the catalog.

  python -I apps/pianofollow/test_pianofollow.py

Pieces are made with the real converter (node tools/piano/test/make_fixture.mjs), so the Lua reader is
checked against what the converter writes. Lua strings are latin-1 in Python (binary-safe).
"""
import hashlib, json, os, random, struct, subprocess, sys, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'gamekit'))
from harness import Game  # noqa: E402

FIX = os.path.join(ROOT, 'tools', 'piano', 'test', 'fixtures')
OUT = os.path.join(ROOT, 'dist', 'piano', 'test')
os.makedirs(OUT, exist_ok=True)


CONVERTER = os.path.join(ROOT, 'site', 'tools', 'piano', 'convert.mjs')


def piece(name):
    """converts a fixture once (again when the fixture or the converter changed); returns its bytes"""
    out = os.path.join(OUT, name.rsplit('.', 1)[0] + '.xtscore')
    src = os.path.join(FIX, name)
    newest = max(os.path.getmtime(src), os.path.getmtime(CONVERTER))
    if not os.path.exists(out) or os.path.getmtime(out) < newest:
        subprocess.run(['node', os.path.join(ROOT, 'tools', 'piano', 'test', 'make_fixture.mjs'), src, out],
                       check=True, capture_output=True)
    return open(out, 'rb').read()


def py_unpack(b):
    n = struct.unpack('<I', b[8:12])[0]
    h = json.loads(b[12:12 + n])
    pages = [zlib.decompress(b[o:o + l]) for o, l in h['pages']]
    mo, ml = h['map']
    return h, pages, json.loads(zlib.decompress(b[mo:mo + ml]))


L1 = lambda b: b.decode('latin-1')            # bytes -> Lua string (latin-1 str)
B = lambda s: s.encode('latin-1')             # Lua string -> bytes

STUBS = r'''
files, timers, set_bits_calls, images, net_calls, extends, invalidates = {}, {}, 0, 0, {}, 0, 0
-- private files: the reader allows only [a-z0-9._-], at most 64 bytes (section 9)
local plain_write = ctx.storage.write
ctx.storage.write = function(self, n, d)
  if type(n) ~= 'string' or #n > 64 or not n:match('^[a-z0-9._-]+$') then return nil, 'invalid_argument' end
  return plain_write(self, n, d)
end
ctx.invalidate = function() invalidates = invalidates + 1 end
ctx.api = { major = 2, minor = 21 }
local function M(t)
  local out = {}
  for k, f in pairs(t) do
    if type(f) == 'function' then out[k] = function(self, ...) assert(self == out, 'method call expected for ' .. k); return f(...) end
    else out[k] = f end
  end
  return out
end
ctx.files = M({
  path = '/AppFiles/pianofollow',
  list = function() local t = {} for n, d in pairs(files) do t[#t + 1] = { name = n, size = #d } end return t end,
  exists = function(n) file_ops = (file_ops or 0) + 1; return files[n] ~= nil end,
  size = function(n) file_ops = (file_ops or 0) + 1; if not files[n] then return nil, 'not_found' end return #files[n] end,
  read = function(n, off, len)
    file_ops = (file_ops or 0) + 1
    local s = files[n]; if not s then return nil, 'not_found' end
    off = off or 0; len = len or 65536
    if len > 65536 then return nil, 'limit_exceeded' end
    return s:sub(off + 1, off + len)
  end,
  write = function(n, d) files[n] = d; return true end,
  remove = function(n) files[n] = nil; return true end,
})
ctx.zlib = M({ decompress = function(s, opts) local r = py_inflate(s); if r == nil then return nil, 'invalid_argument' end return r end })
ctx.json = M({ decode = function(s) local v = py_json_decode(s); if v == nil then return nil, 'invalid_argument' end return v end,
               encode = function(v) return py_json_encode(v) end })
ctx.budget = M({ extend = function() extends = extends + 1; return true end })
ctx.after = function(self, ms, fn) local t = { at = fake_ms + ms, fn = fn }; timers[#timers + 1] = t
  return { cancel = function() t.fn = nil end } end
function run_timers()
  local again = true
  while again do
    again = false
    table.sort(timers, function(a, b) return a.at < b.at end)
    for i, t in ipairs(timers) do
      if t.at <= fake_ms then table.remove(timers, i); if t.fn then t.fn(ctx) end; again = true; break end
    end
  end
end
local function layer(w, h)
  local l = { width = w, height = h, rows = {} }
  function l:set_bits(bytes, y) set_bits_calls = set_bits_calls + 1; last_bits = #bytes; self.rows[#self.rows + 1] = { y = y, n = #bytes } return true end
  function l:draw(fn) fn(gg) end
  function l:release() return true end
  return l
end
ctx.layers = M({ create = function(w, h) return layer(w, h) end })
ctx.screen = { width = 800, height = 480, orientation = 'landscape' }   -- the manifest asks for landscape
local gmt = getmetatable(gg)
local old = gmt.__index
gmt.__index = function(t, k)
  if k == 'image' then return function(_, l, x, y) images = images + 1; commands = commands + 1 end end
  if k == 'clear' then return function() end end
  return old(t, k)
end
'''


def to_lua(L, v):
    if isinstance(v, dict):
        return L.table_from({k: to_lua(L, x) for k, x in v.items()})
    if isinstance(v, list):
        return L.table_from([to_lua(L, x) for x in v])
    return v


def setup(g):
    G = g.L.globals()

    def inflate(s):
        try:
            return L1(zlib.decompress(B(s)))
        except Exception:
            return None

    def jdec(s):
        try:
            return to_lua(g.L, json.loads(B(s).decode('utf-8')))
        except Exception:
            return None

    G.py_inflate = inflate
    G.py_json_decode = jdec
    G.py_json_encode = lambda v: json.dumps(lua_to_py(v))
    G.files['long.xtscore'] = L1(piece('long.musicxml'))
    G.files['scale.xtscore'] = L1(piece('scale.musicxml'))


def lua_to_py(v):
    try:
        keys = list(v.keys())
    except AttributeError:
        return v
    if keys and all(isinstance(k, int) for k in keys):
        return [lua_to_py(v[k]) for k in sorted(keys)]
    return {k: lua_to_py(v[k]) for k in keys}


g = Game(HERE, stubs=STUBS, encoding='latin-1', before_load=setup)
A = lambda: g.api
G = g.L.globals()
S = A().S


def two(r):
    """a Lua call's (value, err) as a pair, also when Lua returned one value"""
    return tuple(r) + (None,) * (2 - len(r)) if isinstance(r, tuple) else (r, None)


# ---------------------------------------------------------------- .xtscore reading (Task 4)
LONG = piece('long.musicxml')
h, pages, pmap = py_unpack(LONG)
p, err = two(S.open('long.xtscore'))
assert p and err is None, err
assert p.header.title == 'long' and len(list(p.header.pages.keys())) == len(pages) >= 3
bits = S.page_bits(p, 2)
assert len(B(bits)) == 44000 and hashlib.sha1(B(bits)).digest() == hashlib.sha1(pages[1]).digest()
m = S.load_map(p)
assert list(m.onsets[1][6].values()) == pmap['onsets'][0][5] and len(m.onsets) == len(pmap['onsets'])
assert int(G.extends) > 0
G.files['short.xtscore'] = L1(LONG[:100])
r = two(S.open('short.xtscore'))
assert r[0] is None and r[1] == 'bad_file', r
G.files['junk.xtscore'] = L1(bytes(random.Random(1).randrange(256) for _ in range(5000)))
assert two(S.open('junk.xtscore'))[1] == 'bad_file'
assert two(S.open('missing.xtscore'))[1] == 'not_found'
rows = S.list()
names = [rows[k].name for k in rows]
assert names[0] == 'junk.xtscore' or 'junk.xtscore' in names
bad = {rows[k].name: bool(rows[k].bad) for k in rows}
assert bad['junk.xtscore'] and bad['short.xtscore'] and not bad['long.xtscore'], bad
titles = [rows[k].title for k in rows]
assert 'long' in titles and 'scale' in titles

# Home lists the pieces; a bad one says it can't be opened; a good one opens on page 1
g.restart()
t = g.texts()
assert 'My pieces' in t and 'long' in t and 'scale' in t, t
g.tap_label('junk.xtscore')
assert any("Can't open this file" in x for x in g.texts()), g.texts()
g.key('back')
g.tap_label('long')
t = g.texts()
assert 'long' in t and any(x.startswith('1/') for x in t), t
assert int(G.set_bits_calls) > 0 and int(G.images) > 0
before = int(G.set_bits_calls)
g.tap(760, 300)                                       # right third: next page
assert any(x.startswith('2/') for x in g.texts()) and int(G.set_bits_calls) > before
g.key('left')
assert any(x.startswith('1/') for x in g.texts())
g.key('right'); g.key('right')
assert any(x.startswith('3/') for x in g.texts())
g.tap(40, 300)                                        # left third: previous page
assert any(x.startswith('2/') for x in g.texts())
g.key('back')
assert 'My pieces' in g.texts()
assert g.L.eval("on_input(ctx, {type='key', key='back'})") is False   # Back on Home: the host asks to leave
assert g.commands() < 200
print('reading ok')

# ---------------------------------------------------------------- BLE MIDI parser (Task 5)
Mi = A().M


def feed(st, *hexes):
    out = []
    for hx in hexes:
        evs = Mi.feed(st, L1(bytes.fromhex(hx)))
        for k in sorted(evs.keys()):
            e = evs[k]
            out.append((bool(e.on), int(e.note), int(e.vel)))
    return out


assert feed(Mi.new(), '8080903C64') == [(True, 60, 100)]
assert feed(Mi.new(), '8080903C64814064') == [(True, 60, 100), (True, 64, 100)]      # running status, timestamp byte
assert feed(Mi.new(), '8080903C644064') == [(True, 60, 100), (True, 64, 100)]        # running status, no timestamp
assert feed(Mi.new(), '8080903C00') == [(False, 60, 0)]                              # velocity 0 is note-off
assert feed(Mi.new(), '8080803C40') == [(False, 60, 64)]
assert feed(Mi.new(), '8080F00102', '8003F780903C64') == [(True, 60, 100)]           # SysEx across packets
assert feed(Mi.new(), '8080B0407F80903E50') == [(True, 62, 80)]                        # a pedal CC is skipped
st = Mi.new()
assert feed(st, '8080903C64', '80813E64') == [(True, 60, 100), (True, 62, 100)]      # running status kept across packets
assert feed(Mi.new(), '8080F880903C64') == [(True, 60, 100)]                           # realtime byte skipped
assert feed(Mi.new(), '8080913C64') == [(True, 60, 100)]                             # any channel
assert feed(Mi.new(), '80') == [] and feed(Mi.new(), '00903C64') == []               # too short / no header bit
ts = Mi.feed(Mi.new(), L1(bytes.fromhex('8385903C64')))
assert int(ts[1].ts) == (3 << 7) | 5
print('midi ok')

# ---------------------------------------------------------------- follower (Task 6)
F = A().F
NB, PER_BAR, BARS_PER_PAGE = 12, 4, 4


def synth_map():
    """12 bars of 4 onsets, 4 bars a page (3 pages), the last system = the last 2 bars of a page;
    every 8th onset a 3-note RH chord, LH on beat 1"""
    onsets, bars = [], []
    for b in range(NB):
        page = b // BARS_PER_PAGE + 1
        bars.append([page, 20, 100 + (b % BARS_PER_PAGE) * 150, 400])
        for k in range(PER_BAR):
            i = b * PER_BAR + k
            p = 55 + (i * 5) % 29
            rh = [p, p + 4, p + 7] if i % 8 == 7 else [p]
            lh = [36 + (b % 7)] if k == 0 else []
            onsets.append([i, b + 1, page, 40 + k * 100, 100 + (b % 4) * 150, rh, lh])
    turn = []
    for pg in range(1, NB // BARS_PER_PAGE + 1):
        first_bar = (pg - 1) * BARS_PER_PAGE
        turn.append([(first_bar + 2) * PER_BAR + 1, (first_bar + 3) * PER_BAR + 1])
    return {'bars': bars, 'onsets': onsets, 'turn': turn}


SYN = synth_map()
NPAGES = NB // BARS_PER_PAGE


def first_onset(page, bar_in_page=1):
    return ((page - 1) * BARS_PER_PAGE + bar_in_page - 1) * PER_BAR + 1


def play(st, seq):
    """seq: list of (onset index, pitches); returns [(onset index, event)]"""
    evs = []
    for idx, pitches in seq:
        for p in pitches:
            e = F.note(st, p, idx * 400)                 # a position every 400 ms, a chord's notes together
            if e:
                evs.append((idx, str(e), int(st.page)))
    return evs


def clean(idxs):
    return [(i, SYN['onsets'][i - 1][5] + SYN['onsets'][i - 1][6]) for i in idxs]


LMAP = to_lua(g.L, SYN)
ALL = list(range(1, len(SYN['onsets']) + 1))
for turn_at, ti in (('bar', 1), ('system', 0)):
    st = F.new(LMAP, 1, turn_at)
    turns = [(i, pg) for i, e, pg in play(st, clean(ALL)) if e == 'turn']
    assert len(turns) == NPAGES - 1, (turn_at, turns)
    for (i, pg), page_before in zip(turns, range(1, NPAGES)):
        assert pg == page_before + 1
        assert i >= SYN['turn'][page_before - 1][ti], (turn_at, i, page_before)          # never early
        assert i < first_onset(page_before + 1, 3), (turn_at, i)                        # not later than 2 bars into the next page

# 'end' (the default): the page turns on its last note, not at the start of its last bar
st = F.new(LMAP, 1, 'end')
turns = [(i, pg) for i, e, pg in play(st, clean(ALL)) if e == 'turn']
assert [i for i, _pg in turns] == [first_onset(2) - 1, first_onset(3) - 1], turns
assert F.new(LMAP, 1).turn_at == 'end'

# 5% wrong notes and 5% skipped onsets: every page turns, none early
for seed in range(1, 21):
    rnd = random.Random(seed)
    seq = []
    for i in ALL:
        r = rnd.random()
        if r < 0.05:
            continue
        pitches = SYN['onsets'][i - 1][5] + SYN['onsets'][i - 1][6]
        if r < 0.10:
            pitches = [rnd.randrange(30, 100)]
        seq.append((i, pitches))
    st = F.new(LMAP, 1, 'bar')
    turns = [(i, pg) for i, e, pg in play(st, seq) if e == 'turn']
    assert [pg for _i, pg in turns] == list(range(2, NPAGES + 1)), (seed, turns)
    for i, pg in turns:
        assert i >= SYN['turn'][pg - 2][1], (seed, i, pg)

# harder: 10% wrong and 10% skipped, 200 runs: never early, never back; a missed turn (the player turns
# by hand) is allowed in at most 2% of the runs
missed = 0
for seed in range(1, 201):
    rnd = random.Random(seed)
    seq = []
    for i in ALL:
        r = rnd.random()
        if r < 0.10:
            continue
        pitches = SYN['onsets'][i - 1][5] + SYN['onsets'][i - 1][6]
        if r < 0.20:
            pitches = [rnd.randrange(30, 100)]
        seq.append((i, pitches))
    st = F.new(LMAP, 1, 'bar')
    turns = [(i, pg) for i, e, pg in play(st, seq) if e == 'turn']
    pgs = [pg for _i, pg in turns]
    assert pgs == sorted(pgs) and len(set(pgs)) == len(pgs), (seed, turns)          # never back, never twice
    assert all(i >= SYN['turn'][pg - 2][1] for i, pg in turns), (seed, turns)    # never early
    missed += pgs != list(range(2, NPAGES + 1))
assert missed <= 4, missed

# a written repeat that goes back a page (unfolded in the map): bars 1-8 twice, then 9-12.
# Expected: page 2, back to page 1 at the repeat, page 2 again, page 3; forward turns in each page's last bar
rep_on = [list(o) for o in SYN['onsets'] if o[1] <= 8] + [list(o) for o in SYN['onsets'] if o[1] <= 8] + [list(o) for o in SYN['onsets'] if o[1] > 8]
for k, o in enumerate(rep_on):
    o[0] = k
REP = {'bars': SYN['bars'], 'onsets': rep_on, 'turn': SYN['turn']}      # turn points: the first pass
st = F.new(to_lua(g.L, REP), 1, 'bar')
evs = []
for idx, o in enumerate(rep_on, 1):
    for pch in o[5] + o[6]:
        e = F.note(st, pch, 0)
        if e == 'turn':
            evs.append((idx, o[1], int(st.page)))
assert [pg for _i, _b, pg in evs] == [2, 1, 2, 3], evs
fwd = [(b, pg) for _i, b, pg in evs if pg != 1]
assert all(b == (pg - 1) * BARS_PER_PAGE for b, pg in fwd), evs       # in the last bar of the page before
assert evs[1][1] == 8 and evs[1][0] <= 32, evs                         # back to page 1 in bar 8, before the repeat starts
# a page turned by hand in the second pass of the repeat keeps the player in that pass
st = F.new(to_lua(g.L, REP), 1, 'bar')
for idx, o in enumerate(rep_on[:36], 1):                                # into the second pass, page 1
    for pch in o[5] + o[6]:
        F.note(st, pch, idx * 400)
F.goto_page(st, 2)
assert int(st.pos) == 32 + first_onset(2), int(st.pos)                 # page 2 of the second pass, not the first

# a real piece with chords and repeats (the catalog Minuet, as the device test played it): the line
# moves bar by bar, goes back only at the written repeats, and the page follows the repeats
sys.path.insert(0, os.path.join(ROOT, 'tools', 'piano'))
import blemidi_sim as sim  # noqa: E402
MIN = os.path.join(ROOT, 'catalog', 'piano', 'pieces', 'minuet-in-g-petzold.xtscore')
if os.path.exists(MIN):
    _mh, _mp, mmap = sim.read_xtscore(MIN)
    for seed, wrong, skip in ((9, 0.0, 0.0), (9, 0.03, 0.03), (4, 0.03, 0.03)):
        stm = F.new(to_lua(g.L, mmap), 1, 'bar')
        bars, pages = [], [1]
        for t, on_, n, v in sim.piece_events(MIN, 90, wrong, skip, 0, seed):
            if not on_:
                continue
            e = F.note(stm, n, t)
            if stm.bar and (not bars or bars[-1] != int(stm.bar)):
                bars.append(int(stm.bar))
            if e == 'turn':
                pages.append(int(stm.page))
        backs = [(a, b) for a, b in zip(bars, bars[1:]) if b < a]
        extra = [x for x in backs if x not in ((16, 1), (32, 17))]
        assert (16, 1) in backs and (32, 17) in backs, (seed, wrong, backs, bars)
        # clean playing: only the written repeats; with mistakes, at most one one-bar correction
        assert (not extra) if wrong == 0 else (len(extra) <= 1 and all(a - b == 1 for a, b in extra)), (seed, wrong, backs, bars)
        leaps = [(a, b) for a, b in zip(bars, bars[1:]) if b > a + 1]
        assert len(leaps) <= (0 if wrong == 0 else 2), (seed, wrong, leaps, bars)
        assert pages == [1, 2, 1, 2, 3, 4, 2, 3, 4], (seed, wrong, pages)

# catalog pieces, a bar played twice or a restart from the bar before (the review's stress): a forward
# turn before the page's last note stays rare (pitch alone cannot tell literally repeated figures apart)
import glob  # noqa: E402
cat_files = sorted(glob.glob(os.path.join(ROOT, 'catalog', 'piano', 'pieces', '*.xtscore')))[::4]
rnd = random.Random(11)
early_runs = runs = 0
for path in cat_files:
    _ch, _cp, cm = sim.read_xtscore(path)
    con = cm['onsets']
    if len(cm['turn']) < 2:
        continue
    lcm = to_lua(g.L, cm)
    for trial in range(10):
        k = rnd.randrange(5, len(con) - 2)
        e_ = k
        while e_ + 1 < len(con) and con[e_ + 1][1] == con[k][1]:
            e_ += 1
        s_ = k
        while s_ > 0 and con[s_ - 1][1] == con[k][1]:
            s_ -= 1
        order = list(range(0, e_ + 1)) + list(range(s_, len(con))) if trial % 2 == 0 else list(range(0, k + 1)) + list(range(max(0, s_ - 1), len(con)))
        stc, t_, early = F.new(lcm, 1, 'end'), 0, False
        for i_ in order:
            o_ = con[i_]
            for kk, pch in enumerate(o_[5] + o_[6]):
                if F.note(stc, pch, t_ + kk * 5) == 'turn' and int(stc.page) > o_[2] and i_ + 1 < len(con) and con[i_ + 1][2] == o_[2]:
                    early = True
            t_ += 400
        runs += 1
        early_runs += early
assert runs >= 100 and early_runs <= runs * 0.05, (early_runs, runs)

# the player repeats bar 3 (page 1) twice: relocated into bar 3, no turn until bar 4 is played again
st = F.new(LMAP, 1, 'bar')
b = lambda n: list(range((n - 1) * PER_BAR + 1, n * PER_BAR + 1))
evs = play(st, clean(b(1) + b(2) + b(3) + b(3) + b(3)))
assert not [e for e in evs if e[1] == 'turn'], evs
assert int(st.bar) == 3 and int(st.page) == 1, (int(st.bar), int(st.pos))
evs = play(st, clean(b(4)))
assert [e[2] for e in evs if e[1] == 'turn'] == [2], evs

# a single matching note after silence turns nothing
st = F.new(LMAP, 1, 'bar')
tp = SYN['turn'][0][1]
assert not play(st, [(tp, SYN['onsets'][tp - 1][5][:1])])
# 2 of a 3-note chord complete it
st = F.new(LMAP, 1, 'bar')
play(st, clean(range(1, 8)))
assert int(st.pos) == 8
play(st, [(8, SYN['onsets'][7][5][:2])])
assert int(st.pos) == 9, int(st.pos)
# a manual turn moves the position to the page's first onset
F.goto_page(st, 2)
assert int(st.pos) == first_onset(2) and int(st.page) == 2
print('follow ok')

# ---------------------------------------------------------------- practice (Task 7)
P = A().P
ON = SYN['onsets']


def req(i, hands='b'):
    o = ON[i - 1]
    return (o[5] if hands in 'rb' else []) + (o[6] if hands in 'lb' else [])


st = P.new(LMAP, 'b', 1)
assert int(st.pos) == 1
now = 1000
for i in range(1, 8):                                       # single notes (+ LH on beat 1) advance
    res = [P.note_on(st, p, now) for p in req(i)]
    assert res[-1] == 'advance' and all(r is None for r in res[:-1]), (i, res)
    for p in req(i):
        P.note_off(st, p)
    now += 400
assert int(st.pos) == 8
c = req(8)                                                  # a 3-note chord, pressed G, C, E within 1 s
assert len(c) == 3
assert [P.note_on(st, c[2], now), P.note_on(st, c[0], now + 300), P.note_on(st, c[1], now + 600)] == [None, None, 'advance']
for p in c:
    P.note_off(st, p)
now += 2000
# the next chord: the first note released and 1.2 s before the last -> no advance until pressed again
st2 = P.new(LMAP, 'b', 16)
c = req(16)
assert P.note_on(st2, c[0], now) is None
P.note_off(st2, c[0])
assert P.note_on(st2, c[1], now + 600) is None
assert P.note_on(st2, c[2], now + 1200) is None and int(st2.pos) == 16
assert P.note_on(st2, c[0], now + 1300) == 'advance'
# a wrong note: counted for its bar, the position stays
st3 = P.new(LMAP, 'b', 1)
assert P.note_on(st3, 20, now) == 'wrong' and int(st3.pos) == 1 and int(st3.wrong) == 1
assert P.note_on(st3, req(1)[0], now) is None              # pressing a required note again is not wrong
summ = P.summary(st3)
assert int(summ.wrong) == 1 and int(summ.bars[1].bar) == 1 and int(summ.bars[1].wrong) == 1
# the left hand alone, on a piece where it rests in bars 2-3: those onsets are skipped
rest = json.loads(json.dumps(SYN))
for o in rest['onsets']:
    if o[1] in (2, 3):
        o[6] = []
st4 = P.new(to_lua(g.L, rest), 'l', 1)
assert int(st4.pos) == 1
assert P.note_on(st4, req(1, 'l')[0], now) == 'advance'
assert int(st4.pos) == first_onset(1, 4), int(st4.pos)      # bar 1's other onsets and bars 2-3 have no LH
# while the left hand rests, the right hand's notes in those bars are not mistakes
for i in range(2, first_onset(1, 4)):
    for q in rest['onsets'][i - 1][5]:
        assert P.note_on(st4, q, now + i * 400) is None, (i, q)
assert int(st4.wrong) == 0, int(st4.wrong)
# starting from bar 5
st5 = P.new(LMAP, 'r', first_onset(2))
assert int(st5.pos) == first_onset(2)
# to the end
st6 = P.new(LMAP, 'r', len(ON))
assert [P.note_on(st6, q, now) for q in req(len(ON), 'r')][-1] == 'advance' and st6.done
print('practice ok')

# ---------------------------------------------------------------- score screen modes (Task 8)
LMAPS = {}


def note(n, on=True, ms=100):
    g.advance(ms)
    G.run_timers()
    G.on_midi(g.L.table_from({'on': on, 'note': n, 'vel': 80 if on else 0, 'ts': 0}))


def open_piece(title):
    while A().screen() != 'home':
        g.key('back')
    g.tap_label(title)


def set_mode(label, hands=None):
    g.tap_label(A().mode_label())
    g.tap_label(label)
    if hands:
        g.tap_label(hands)


def fill_rects():
    return [r for r in g.rects() if r.fill]


h_long, pages_long, map_long = py_unpack(LONG)
G.store[G.piece_key_for_test('long.xtscore')] = None
open_piece('long')
assert A().mode_label() == 'Page turn'                     # the default mode
assert not fill_rects()                                     # page turn: no marker
set_mode('Follow')
assert A().mode_label() == 'Follow'
t0, inv0, sb0 = int(G.fake_ms), int(G.invalidates), int(G.set_bits_calls)
on = map_long['onsets']
first_p2 = next(i for i, o in enumerate(on) if o[2] == 2)
for o in on[:first_p2 + 4]:                                  # page 1 and into page 2, a note every 100 ms
    for p in o[5] + o[6]:
        note(p, True, 50)
        note(p, False, 50)
elapsed = int(G.fake_ms) - t0
redraws = int(G.invalidates) - inv0
assert redraws <= elapsed // 1000 + 2, (redraws, elapsed)
assert int(G.set_bits_calls) - sb0 == 1, int(G.set_bits_calls) - sb0      # one page written: the turn to page 2
assert any(x.startswith('2/') for x in g.texts())
fr = fill_rects()                                           # follow: the bar marker, dashed, apart from the staff
assert len(fr) >= 4 and len({int(r.y) for r in fr}) == 1 and all(int(r.w) <= 10 for r in fr), [(r.x, r.y, r.w) for r in fr]
bar = A().cur().map.bars[A().cur().fst.bar]
assert int(fr[0].y) >= 40 + int(bar[3]) + 10, (fr[0].y, bar[3])
# mode and page come back after a restart
g.restart()
open_piece('long')
assert A().mode_label() == 'Follow' and any(x.startswith('2/') for x in g.texts())
# practice on the scale: a wrong note in bar 3, then to the end
G.store[G.piece_key_for_test('scale.xtscore')] = None
open_piece('scale')
set_mode('Practice', 'Both hands')
assert A().mode_label() == 'Practice: both'
h_s, pages_s, map_s = py_unpack(piece('scale.musicxml'))
for i, o in enumerate(map_s['onsets']):
    if o[1] == 3 and i == next(k for k, q in enumerate(map_s['onsets']) if q[1] == 3):
        note(20)
        assert any('Wrong 1' in x for x in g.texts()), g.texts()
    for p in o[5] + o[6]:
        note(p, True, 100)
    for p in o[5] + o[6]:
        note(p, False, 50)
g.advance(1000); G.run_timers()
t = g.texts()
assert any('Bar 3' in x for x in t) and 'Practice from bar 3' in t, t
g.tap_label('Practice from bar 3')
assert A().screen() == 'score' and int(A().practice().pos) == next(k for k, q in enumerate(map_s['onsets']) if q[1] == 3) + 1
fr = fill_rects()                                           # practice: the note mark, under the system, not in the notes
st = A().practice(); o = A().cur().map.onsets[st.pos]; bar = A().cur().map.bars[o[2]]
assert len(fr) == 1 and int(fr[0].y) == 40 + int(bar[3]) + 10, (fr[0].y, bar[3], o[5])
assert abs(int(fr[0].x) + int(fr[0].w) // 2 - int(o[4])) <= 2
assert g.commands() < 200
print('modes ok')

# ---------------------------------------------------------------- keyboard (Task 9)
BLE = r'''
ble_scans, ble_conns = {}, {}
function make_ble()
  local function M(t)
    local out = {}
    for k, f in pairs(t) do out[k] = function(self, ...) assert(self == out, 'method call expected for ' .. k); return f(...) end end
    return out
  end
  return M({
    scan = function(opts, cb) local s = { opts = opts, cb = cb, stopped = false }
      s.stop = function() s.stopped = true end
      ble_scans[#ble_scans + 1] = s; return s end,
    connect = function(opts, cb)
      if ble_busy then ble_busy = false; return nil, 'busy' end
      local c = { opts = opts, cb = cb, subs = {}, closed = false }
      c.subscribe = function(self, chr, on, fn) c.subs[#c.subs + 1] = { chr = chr, on = on, fn = fn }; return true end
      c.close = function(self) c.closed = true; return true end
      c.mtu = function() return 23 end
      ble_conns[#ble_conns + 1] = c; return c end,
  })
end
'''
SVC, CHR = '03b80e5a-ede8-4b33-a751-6ce34ec4c700', '7772e5db-3868-4112-a1a9-f2669d106bf3'
g.L.execute(BLE)


def last_conn():
    return G.ble_conns[len(G.ble_conns)]


def ble_fresh():
    g.L.execute("ble_scans, ble_conns = {}, {}; ctx.ble = make_ble()")


def seen(address, atype='random', name='PF-Sim'):
    """the last scan finds a keyboard"""
    sc = G.ble_scans[len(G.ble_scans)]
    sc.cb.on_device(G.ctx, sc, g.L.table_from({'address': address, 'address_type': atype, 'name': name, 'rssi': -50, 'connectable': True}))
    return sc


# no Bluetooth on this reader: a message, no error
g.L.execute('ctx.ble = nil')
G.store['kbd.txt'] = None
g.restart()
g.tap_label('Keyboard')
assert any('no Bluetooth' in x for x in g.texts()), g.texts()
g.no_err()
g.key('back')
# scan -> pick -> connect -> subscribe -> notes reach the score
ble_fresh()
g.restart()
assert len(G.ble_scans) == 0 and len(G.ble_conns) == 0          # nothing remembered: no scan until asked
g.tap_label('Keyboard')
g.tap_label('Search')
s = G.ble_scans[1]
assert list(s.opts.services.values()) == [SVC]
dev = g.L.table_from({'address': 'AA:BB:CC:DD:EE:01', 'address_type': 'random', 'name': 'PF-Sim', 'rssi': -50, 'connectable': True})
s.cb.on_device(G.ctx, s, dev)
s.cb.on_done(G.ctx, s, g.L.table_from([dev]), None)
assert 'PF-Sim' in g.texts()
g.tap_label('PF-Sim')
c = last_conn()
assert c.opts.address == 'AA:BB:CC:DD:EE:01' and not c.opts.secure
c.cb.on_connect(G.ctx, c)
sub = c.subs[1]
assert sub.chr == CHR and sub.on
sub.fn(G.ctx, c, None)
assert any('Connected' in x for x in g.texts()), g.texts()
assert str(G.store['kbd.txt']).split('\n')[:3] == ['AA:BB:CC:DD:EE:01', 'random', 'PF-Sim']
c.cb.on_notify(G.ctx, c, 12, L1(bytes.fromhex('8080903C64')))
assert any('Last note: C4' in x for x in g.texts()), g.texts()
g.key('back')
# a remembered keyboard is looked for when the app opens and connected as soon as it is seen
ble_fresh()
g.restart()
assert len(G.ble_scans) == 1 and len(G.ble_conns) == 0
sc = seen('AA:BB:CC:DD:EE:01')
assert sc.stopped and len(G.ble_conns) == 1 and last_conn().opts.address == 'AA:BB:CC:DD:EE:01'
c = last_conn()
c.cb.on_connect(G.ctx, c); c.subs[1].fn(G.ctx, c, None)
G.store[G.piece_key_for_test('scale.xtscore')] = None
open_piece('scale')
set_mode('Follow')
for k, o in enumerate(map_s['onsets'][:6]):
    for p in o[5] + o[6]:
        c.cb.on_notify(G.ctx, c, 12, L1(bytes([0x80, 0x80, 0x90, p, 80])))
assert int(A().cur().fst.pos) == 7, int(A().cur().fst.pos)
# the keyboard goes away mid-piece: status says so, the page stays, it reconnects after 5 s
page_before = int(A().cur().page)
c.cb.on_disconnect(G.ctx, c, 'io_error')
assert any('Keyboard lost' in x for x in g.texts()) and int(A().cur().page) == page_before, g.texts()
n_conn = len(G.ble_conns)
g.advance(5000); G.run_timers()
assert len(G.ble_conns) == n_conn + 1
c = last_conn(); c.cb.on_connect(G.ctx, c); c.subs[1].fn(G.ctx, c, None)
assert not any('Keyboard lost' in x for x in g.texts())
# a keyboard that needs pairing: subscribe fails, the next connect is secure, and that is remembered
ble_fresh()
G.store['kbd.txt'] = 'AA:BB:CC:DD:EE:02\npublic\nPiano BT\n0\n'
g.restart()
seen('AA:BB:CC:DD:EE:02', 'public', 'Piano BT')
c = last_conn()
assert not c.opts.secure
c.cb.on_connect(G.ctx, c)
c.subs[1].fn(G.ctx, c, 'io_error')
assert c.closed
c.cb.on_disconnect(G.ctx, c, None)                          # our own close: nothing to retry
g.advance(300); G.run_timers()
c2 = last_conn()
assert c2 is not c and c2.opts.secure
c2.cb.on_connect(G.ctx, c2); c2.subs[1].fn(G.ctx, c2, None)
assert str(G.store['kbd.txt']).rstrip('\n').endswith('1')
# busy: tried again after 200 ms
ble_fresh()
g.L.execute('ble_busy = true')
g.restart()
seen('AA:BB:CC:DD:EE:02', 'public', 'Piano BT')
assert len(G.ble_conns) == 0
g.advance(200); G.run_timers()
assert len(G.ble_conns) == 1
# not seen in the search: one direct try anyway
ble_fresh()
g.restart()
sc = G.ble_scans[1]
sc.cb.on_done(G.ctx, sc, g.L.table_from([]), None)
assert len(G.ble_conns) == 1 and last_conn().opts.address == 'AA:BB:CC:DD:EE:02'
c = last_conn(); c.cb.on_disconnect(G.ctx, c, 'timeout')       # it is not there: lost, tried again later
# opening the Keyboard screen when not connected searches again, and connects to the remembered one
n_scans = len(G.ble_scans)
g.tap_label('Keyboard')
assert len(G.ble_scans) == n_scans + 1, (len(G.ble_scans), n_scans)
seen('AA:BB:CC:DD:EE:02', 'public', 'Piano BT')
c = last_conn(); c.cb.on_connect(G.ctx, c); c.subs[1].fn(G.ctx, c, None)
assert any('Connected' in x for x in g.texts()), g.texts()
g.key('back')
# and does not search again while connected
n_scans = len(G.ble_scans)
g.tap_label('Keyboard')
assert len(G.ble_scans) == n_scans
g.key('back')
g.tap_label('Keyboard')
# races: a pick while connecting is ignored; a stale connection's late events change nothing
ble_fresh()
G.store['kbd.txt'] = None
g.restart()
g.tap_label('Keyboard')                                   # searches by itself (nothing remembered)
sc = G.ble_scans[len(G.ble_scans)]
dA = g.L.table_from({'address': 'AA:00:00:00:00:0A', 'address_type': 'random', 'name': 'Piano A', 'rssi': -50, 'connectable': True})
dB = g.L.table_from({'address': 'BB:00:00:00:00:0B', 'address_type': 'random', 'name': 'Piano B', 'rssi': -60, 'connectable': True})
sc.cb.on_device(G.ctx, sc, dA); sc.cb.on_device(G.ctx, sc, dB); sc.cb.on_done(G.ctx, sc, g.L.table_from([dA, dB]), None)
g.tap_label('Piano A')
cA = last_conn()
n_conn = len(G.ble_conns)
g.tap_label('Piano B')                                    # still connecting to A: ignored
assert len(G.ble_conns) == n_conn
cA.cb.on_connect(G.ctx, cA); cA.subs[1].fn(G.ctx, cA, None)
assert str(G.store['kbd.txt']).startswith('AA:00:00:00:00:0A')
g.tap_label('Search')
sc = G.ble_scans[len(G.ble_scans)]
sc.cb.on_device(G.ctx, sc, dB); sc.cb.on_done(G.ctx, sc, g.L.table_from([dB]), None)
g.tap_label('Piano B')                                    # connected to A: switching closes A first
assert cA.closed
cB = last_conn()
cA.cb.on_disconnect(G.ctx, cA, 'io_error')                 # A's late disconnect: B is not lost
cB.cb.on_connect(G.ctx, cB); cB.subs[1].fn(G.ctx, cB, None)
assert any('Connected: Piano B' in x for x in g.texts()), g.texts()
assert str(G.store['kbd.txt']).startswith('BB:00:00:00:00:0B')
cA.cb.on_notify(G.ctx, cA, 12, L1(bytes.fromhex('8080903C64')))   # stale notes are ignored too
g.key('back')
G.store['kbd.txt'] = chr(10).join(['AA:BB:CC:DD:EE:02', 'public', 'Piano BT', '0', ''])
ble_fresh()
g.restart()
seen('AA:BB:CC:DD:EE:02', 'public', 'Piano BT')

# Forget: closes and removes the remembered keyboard
g.tap_label('Keyboard')
g.tap_label('Forget')
assert last_conn().closed and not G.store['kbd.txt']
g.key('back')
print('keyboard ok')

# ---------------------------------------------------------------- catalog (Task 11)
BASE = 'https://raw.githubusercontent.com/omer-faruq-xteink/touch-licorice-apps/main/catalog/piano/'
CAT = {'v': 1, 'pieces': [
    {'id': 'scale-test', 'title': 'Scale Study', 'composer': 'Test', 'level': 'beginner', 'pages': 1, 'size': 3000, 'license': 'CC0'},
    {'id': 'tune-trad', 'title': 'Test Tune', 'composer': 'Trad.', 'level': 'beginner', 'pages': 1, 'size': 2500, 'license': 'Public domain'},
    {'id': 'minuet-g', 'title': 'Minuet in G', 'composer': 'Petzold', 'level': 'easy', 'pages': 8, 'size': 19000, 'license': 'CC0'},
]}
SERVED = {BASE + 'catalog.json': json.dumps(CAT).encode(), BASE + 'pieces/scale-test.xtscore': piece('scale.musicxml'),
          BASE + 'pieces/tune-trad.xtscore': piece('tune.abc'), BASE + 'pieces/minuet-g.xtscore': LONG}
NET = r'''
net_off = false
ctx.net = setmetatable({}, { __index = { request = function(self, opts, fn)
  net_calls[#net_calls + 1] = opts.url
  local res
  if net_off then res = { ok = false, err = 'no_network' }
  else
    local st, body = py_serve(opts.url)
    res = { ok = true, status = st, body = body, bytes = #body, headers = {} }
    if opts.save and st >= 200 and st < 300 then files[opts.save.name] = body; res.body = ''; res.saved = true end
  end
  timers[#timers + 1] = { at = fake_ms, fn = function() fn(ctx, res) end }
  return { cancel = function() end }
end } })
'''
g.L.execute(NET)
G.py_serve = lambda url: (200, L1(SERVED[url])) if url in SERVED else (404, '')


def flush():
    G.run_timers()


for k in [k for k in G.files.keys() if str(k).endswith('.xtscore') or str(k) == 'catalog.json']:
    if str(k) not in ('long.xtscore', 'scale.xtscore'):
        G.files[k] = None
g.restart()
g.tap_label('Catalog'); flush()
assert G.net_calls[len(G.net_calls)] == BASE + 'catalog.json'
t = g.texts()
assert 'Beginner (2)' in t and 'Easy (1)' in t, t
g.tap_label('Beginner (2)')
assert 'Test' in g.texts() and 'Trad.' in g.texts()
g.tap_label('Trad.')
g.tap_label('Test Tune')
t = g.texts()
assert any('Public domain' in x for x in t) and 'Download' in t, t
g.tap_label('Download'); flush()
assert G.files['tune-trad.xtscore'] is not None and 'Open' in g.texts(), g.texts()
g.tap_label('Open')
assert A().screen() == 'score' and A().cur().name == 'tune-trad.xtscore'
g.key('back')
assert 'tune' in g.texts()                                   # in My pieces, under the file's own title
# search by title
g.tap_label('Catalog'); flush()
g.tap_label('Search')
G.inputs[len(G.inputs)](G.ctx, 'minuet')
assert 'Minuet in G' in g.texts(), g.texts()
g.key('back'); g.key('back')
# offline: a message, and the cached catalog still lists the pieces
G.net_off = True
g.tap_label('Catalog'); flush()
t = g.texts()
assert any('No connection' in x for x in t) and 'Beginner (2)' in t, t
G.net_off = False
g.key('back')
# delete a piece from its score screen
g.tap_label('tune')
g.tap_label(A().mode_label())
g.tap_label('Delete this piece')
g.tap_label('Delete')
assert A().screen() == 'home' and G.files['tune-trad.xtscore'] is None and 'tune' not in g.texts()
# a download that is not a score is removed again
SERVED[BASE + 'pieces/scale-test.xtscore'] = b'<html>not found</html>'
g.tap_label('Catalog'); flush()
g.tap_label('Beginner (2)'); g.tap_label('Test'); g.tap_label('Scale Study')
g.tap_label('Download'); flush()
assert G.files['scale-test.xtscore'] is None and any('damaged' in x for x in g.texts()), g.texts()
g.no_err()
print('catalog ok')

# ---------------------------------------------------------------- landscape everywhere
g.restart()
assert int(G.ctx.screen.width) == 800
g.tap_label('long')
assert int(G.last_bits) == 44000                    # an 800 x 440 page
pg = [x for x in g.texts() if __import__('re').match(r'^\d+/\d+$', x)][0]
assert g.recs()[pg][0] > 700                        # the page number at the right edge
g.tap_label(A().mode_label())                       # the mode menu fits the 480-high screen
r = g.recs()
assert all(y < 480 for _x, y in r.values()) and 'Practice' in r and 'Delete this piece' in r, r
g.key('back'); g.key('back')
# a file from the upright converter is refused with a hint
h, pages_l, map_l = py_unpack(LONG)


def repack(header, pages, mp):
    blobs = [zlib.compress(x) for x in pages]
    mz = zlib.compress(json.dumps(mp).encode())
    n = 0
    while True:
        off, ranges = 12 + n, []
        for b in blobs:
            ranges.append([off, len(b)]); off += len(b)
        hj = json.dumps({**header, 'pages': ranges, 'map': [off, len(mz)]}).encode()
        if len(hj) == n:
            break
        n = len(hj)
    return b'XTSCORE1' + struct.pack('<I', n) + hj + b''.join(blobs) + mz


G.files['upright.xtscore'] = L1(repack({**h, 'w': 480, 'h': 760, 'title': 'upright'}, [bytes(45600)] * 2, map_l))
g.restart()
g.tap_label('upright')
assert any('upright screen' in x for x in g.texts()), g.texts()
g.key('back')
G.files['upright.xtscore'] = None
# more pieces than a page holds: Next / Prev
for k in range(12):
    G.files[f'extra{k:02d}.xtscore'] = L1(repack({**h, 'title': f'Extra {k:02d}'}, pages_l[:1], map_l))
g.restart()
t = g.texts()
assert 'Next' in t and 'Extra 11' not in t, t
g.tap_label('Next')
assert 'Extra 11' in g.texts() and 'Prev' in g.texts()
g.tap_label('Prev')
for k in range(12):
    G.files[f'extra{k:02d}.xtscore'] = None
g.restart()
# the practice summary uses both columns of the wide screen: six bars, then "+n more"
G.store[G.piece_key_for_test('long.xtscore')] = 'mode=practice' + chr(10) + 'hands=b' + chr(10) + 'page=1' + chr(10)
g.restart()
g.tap_label('long')
on = A().cur().map.onsets
bars_hit = []
for i in range(1, len(on) + 1):
    o = on[i]
    if int(o[2]) % 3 == 1 and int(o[2]) not in bars_hit:
        note(20); bars_hit.append(int(o[2]))
    for k in list(o[6].values()) + list(o[7].values()):
        note(int(k), True, 60)
    for k in list(o[6].values()) + list(o[7].values()):
        note(int(k), False, 30)
g.advance(1000); G.run_timers()
t = g.texts()
labels = [x for x in t if x.startswith('Practice from bar')]
assert A().screen() == 'summary' and len(labels) == 6, t
r = g.recs()
assert len({r[l][0] for l in labels}) == 2 and all(r[l][1] < 480 - 60 for l in labels), r
assert any(x.startswith('+') and 'more' in x for x in t), t
g.key('back'); g.key('back')
# many pieces: Home reads only new or changed files (a cached index), with time allowed for it
for k in range(30):
    G.files[f'lib{k:02d}.xtscore'] = L1(repack({**h, 'title': f'Lib {k:02d}'}, pages_l[:1], map_l))
g.restart()
G.file_ops, G.extends = 0, 0
g.L.execute('go_home_for_test()')
assert int(G.extends) > 0
G.file_ops = 0
g.L.execute('go_home_for_test()')
assert int(G.file_ops) <= 3, int(G.file_ops)                     # nothing changed: the index, no file opened
G.files['lib05.xtscore'] = L1(repack({**h, 'title': 'Lib renamed'}, pages_l[:2], map_l))
G.file_ops = 0
g.L.execute('go_home_for_test()')
assert 3 <= int(G.file_ops) <= 8, int(G.file_ops)               # the changed one only
assert 'Lib renamed' in [str(r.title) for r in A().pieces().values()]
# the catalog: drawing a list does not ask the card about each entry
g.tap_label('Catalog'); flush()
G.file_ops = 0
g.draw(); g.draw()
assert int(G.file_ops) == 0, int(G.file_ops)
g.key('back')
for k in range(30):
    G.files[f'lib{k:02d}.xtscore'] = None
g.restart()
# a piece whose file name has capitals, spaces and length still keeps its mode and page
LONGNAME = 'Minuet in G - My Own Arrangement For The Reader (v2).xtscore'
G.files[LONGNAME] = L1(repack({**h, 'title': 'My Minuet'}, pages_l[:3], map_l))
g.restart()
g.tap_label('My Minuet')
set_mode('Follow')
g.tap(760, 300)
g.key('back')
g.restart()
g.tap_label('My Minuet')
assert A().mode_label() == 'Follow' and any(x.startswith('2/') for x in g.texts()), (A().mode_label(), g.texts())
g.key('back')
G.files[LONGNAME] = None
g.restart()
print('landscape ok')
