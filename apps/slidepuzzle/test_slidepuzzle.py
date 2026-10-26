"""Offline test of Slide Puzzle (API 2.9) under Lua 5.4 (lupa): bundles src/ into index.lua, then
plays through the device screen with a method-style ctx stub: taps and swipes, the inverted tiles
in their final place, a solve with best results, time, sizes, settings, save and reload.

  python -I apps/slidepuzzle/test_slidepuzzle.py
"""
import os, re, subprocess, sys
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
subprocess.run([sys.executable, '-I', os.path.join(HERE, 'bundle.py')], check=True)
L = lua54.LuaRuntime(unpack_returned_tuples=True)
L.execute(r'''
drawn, fills, store, inputs = {}, 0, {}, {}
fake_ms = 100000
local gmt = {}
gmt.__index = function(_, k) return function(_, ...)
  if k == 'text' then local x, y, s, o = ...; drawn[#drawn + 1] = { s = s, x = x, y = y, white = type(o) == 'table' and o.color == 15 } end
  if k == 'rect' then local x, y, w, h, o = ...; if type(o) == 'table' and o.fill then fills = fills + 1 end end
end end
gg = setmetatable({}, gmt)
local function M(t)
  local out = {}
  for k, f in pairs(t) do
    if type(f) == 'function' then out[k] = function(self, ...) assert(self == out, 'method call expected for ' .. k); return f(...) end
    else out[k] = f end
  end
  return out
end
local function font(name, lh) local f = M({ measure = function(s) return (utf8.len(s) or #s) * 10 end }); f.line_height = lh; return f end
ctx = {
  invalidate = function() end,
  storage = M({ write = function(n, d) store[n] = d; return true end, read = function(n) if store[n] then return store[n] end return nil, 'not_found' end }),
  fonts = { small = font('small', 20), medium = font('medium', 24), large = font('large', 30) },
  input = M({ text = function(opts, fn) inputs[#inputs + 1] = fn end }),
  clock = M({ millis = function() return fake_ms end }),
}
''')
INDEX = os.path.join(HERE, 'index.lua').replace(os.sep, '/')


def start():
    L.execute(f"dofile([[{INDEX}]])")
    gl = L.globals()
    gl.on_load(gl.ctx)
    return gl


g = start()
tap_ = L.eval("function(x, y) on_input(ctx, {type='pointer', phase='down', x=x, y=y}); on_input(ctx, {type='pointer', phase='up', gesture='tap', x=x, y=y}) end")
swipe = L.eval("function(d) on_input(ctx, {type='pointer', phase='up', gesture='swipe_' .. d, x=240, y=300}) end")
key = L.eval("function(k) fake_ms = fake_ms + 300; on_input(ctx, {type='key', key=k}) end")
draw = L.eval("function() drawn = {}; fills = 0; on_draw(ctx, gg); return drawn end")


def texts():
    return [str(v.s) for v in draw().values()]


def recs():
    out = {}
    for r in draw().values():
        out[str(r.s)] = (int(r.x), int(r.y))
    return out


def tap_label(label):
    r = recs()
    assert label in r, (label, list(r))
    x, y = r[label]
    tap_(x + 3, y + 5)


def tap_tile(n, r, c):
    tile = 456 // n
    tap_(12 + (c - 1) * tile + tile // 2, 84 + (r - 1) * tile + tile // 2)


def no_err():
    assert not any('ERR' in x for x in texts()), texts()


t = texts()
assert any(x.startswith('4x4 Puzzle    Moves: 0    Time: 00:00') for x in t), t
assert 'Best: not set yet' in t and 'New' in t and 'Size' in t and 'Stats' in t and 'Settings' in t, t
assert sorted(int(x) for x in set(t) if x.isdigit()) == list(range(1, 16)), t
assert 'game4.txt' in g.store

# a puzzle one move from solved: tiles in place are inverted (filled, white digits)
g.store['game4.txt'] = 'grid=1,2,3,4;5,6,7,8;9,10,11,12;13,14,0,15\nmoves=5\nelapsed=30\nstarted=1'
g = start()
draw()
assert int(L.eval('fills')) == 14, L.eval('fills')                        # 1..14 are home, 15 is not
whites = {str(v.s) for v in draw().values() if v.white}
assert whites == {str(i) for i in range(1, 15)}, whites
# a tile not next to the gap does not move
tap_tile(4, 1, 1)
assert 'Only tiles next to the gap can move.' in texts()
# tapping 15 solves it: the win box, best results, plays
L.execute('fake_ms = fake_ms + 20000')
tap_tile(4, 4, 4)
t = texts()
assert any('You solved the 4x4 puzzle!' in x for x in t) and 'Moves: 6' in t, t
assert re.match(r'^4=50,6,1$', g.store['best.txt']), g.store['best.txt']   # 30 s + 20 s, 6 moves, 1 play
tap_label('Close')
assert 'Best: 00:50    Fewest moves: 6' in texts(), texts()
no_err()

# swipes: the tile on the far side of the gap slides into it; the idle cap keeps time honest
g.store['game4.txt'] = 'grid=1,2,3,4;5,6,7,8;9,10,11,12;13,14,0,15\nmoves=0\nelapsed=0\nstarted=1'
g = start()
L.execute('fake_ms = fake_ms + 3600000')                                    # an hour away: counts 60 s
swipe('left')
t = texts()
assert any('You solved the 4x4 puzzle!' in x for x in t), t
assert any('Time: 01:00' in x for x in t), t
assert g.store['best.txt'] == '4=50,1,2', g.store['best.txt']               # best time kept, fewer moves
tap_label('New')
assert any(x.startswith('4x4 Puzzle    Moves: 0') for x in texts())
assert 'New puzzle — good luck!' in texts()

# side keys slide too
before = g.store['game4.txt']
for k in ('left', 'up', 'right', 'down'):
    key(k)
assert g.store['game4.txt'] != before
no_err()

# sizes: each keeps its own puzzle
moves4 = re.search(r'moves=(\d+)', g.store['game4.txt']).group(1)
tap_label('Size')
assert 'Select board size' in texts()
tap_label('5 × 5')
assert any(x.startswith('5x5 Puzzle') for x in texts()) and 'game5.txt' in g.store
assert sorted(int(x) for x in set(texts()) if x.isdigit()) == list(range(1, 25))
tap_label('Size'); tap_label('4 × 4')
assert any(x.startswith('4x4 Puzzle    Moves: ' + moves4) for x in texts()), texts()
tap_label('Size'); tap_label('7 × 7')
assert sorted(int(x) for x in set(texts()) if x.isdigit()) == list(range(1, 49))
tap_label('Size'); tap_label('4 × 4')

# stats, settings: language, always new, reset
tap_label('Stats')
t = texts()
assert 'Records:' in t and any(x.startswith('4 × 4') and 'Plays 2' in x for x in t), t
tap_label('Close')
tap_label('Settings')
seen = []
for _ in range(7):
    lang = [x for x in texts() if ': ' in x and x.split(': ', 1)[1] in ('English', 'Português', 'Español', 'Français', 'Deutsch', '한국어', 'Türkçe')][0]
    tap_label(lang)
    seen.append([x for x in texts() if ': ' in x and x.split(': ', 1)[1] in ('English', 'Português', 'Español', 'Français', 'Deutsch', '한국어', 'Türkçe')][0])
    no_err()
assert len(set(seen)) == 7 and seen[-1].endswith('English'), seen
key('back')
tap_label('Settings')
tap_label('[ ] Always start a new puzzle on open')
assert '[x] Always start a new puzzle on open' in texts()
key('back')
assert 'settings.txt' in g.store and 'always_new=1' in g.store['settings.txt']
tap_label('Settings')
tap_label('Reset best results')
tap_label('Reset')
assert g.store['best.txt'] == '' and 'Best results cleared.' in texts()
saved = g.store['game4.txt']
g = start()
assert g.store['game4.txt'] != saved                                       # always new: a fresh shuffle
no_err()

# leaving saves
L.execute('fake_ms = fake_ms + 5000')
L.execute('on_leave()')
assert 'game4.txt' in g.store
print('slidepuzzle tests passed')
