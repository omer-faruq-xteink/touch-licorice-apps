"""Offline test of notes/index.lua and notes/lockscreen.lua under Lua 5.4 (lupa).

  python -I notes/test_notes.py        (from the Xteink folder)
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
from lupa import lua54 as L  # noqa: E402

SRC = open(os.path.join(HERE, 'index.lua'), encoding='utf-8').read()
LOCK = open(os.path.join(HERE, 'lockscreen.lua'), encoding='utf-8').read()
STUBS = r'''
cmds = 0; texts = {}; calls = {}
g = setmetatable({}, {__index = function(_, k) return function(self, ...)
  cmds = cmds + 1
  if k == 'text' then local x, y, s = ...; texts[#texts+1] = s end
  if k == 'measure_text' then local s = ...; return 13 * #s, 24 end
end end})
ctx = { state = {}, invalidate = function() end,
        display = { full_refresh = function() calls[#calls+1] = 'full_refresh' end },
        sys = { clock = function() return { hour = 9, minute = 5 } end },
        system = { set_as_lockscreen_app = function(...) calls[#calls+1] = 'set_as_lockscreen_app'; return true end },
        lock = { interval_sec = 60, set_interval = function() end, flush_once = function() end },
        layers = { create = function(self, w, h) return { draw_with = function(self, f) f(g) end, dispose = function() end } end } }
__TEST = {}
'''


def make(src=SRC, extra=''):
    rt = L.LuaRuntime(unpack_returned_tuples=True)
    rt.execute(STUBS + extra)
    rt.execute(src)
    return rt


rt = make()
api = rt.eval('__TEST.api'); T = lambda **kw: rt.table_from(kw)  # noqa: E731
on_input = rt.eval('on_input')
def tap(x, y): on_input(None, T(type='touch', gesture='tap', x=x, y=y))
def toolbar(k, n): w = (450 - (n - 1) * 5) // n; tap(15 + (k - 1) * (w + 5) + w // 2, 580 + 28)
def texts(): return list(rt.eval('texts').values())
def draw(): rt.execute('cmds = 0; texts = {}'); rt.eval('on_draw')(); return rt.eval('cmds')

# key positions from the app's own keyboard walker
def key_positions():
    pos = {}
    def cb(k, x, y, w, h):
        label = k[1] if hasattr(k, 'values') or not isinstance(k, str) else k
        pos[label] = (x + w // 2, y + h // 2)
    api.each_key(cb)
    return pos

# wrap
w = api.wrap('hello world this is a fairly long line of text that must wrap nicely', 34)
w = [w[i] for i in range(1, len(w) + 1)]
assert all(len(l) <= 34 for l in w) and ' '.join(w) == 'hello world this is a fairly long line of text that must wrap nicely', w
w2 = api.wrap('a\n\nb', 34); assert [w2[i] for i in range(1, len(w2) + 1)] == ['a', '', 'b']
print('wrap OK')

# load, view, type
rt.eval('on_load')(rt.eval('ctx'))
S = api.state(); assert len(S['pages']) == 1 and S['cur'] == 1 and api.mode() == 'view'
n = draw(); print('draw commands (view, empty page):', n); assert n < 1024
toolbar(1, 5); assert api.mode() == 'type'
pos = key_positions()
assert 'q' in pos and 'space' in pos and 'Done' in pos and '1' in pos, list(pos)[:12]
for ch in 'hi': tap(*pos[ch])
tap(*pos['space'])
tap(*pos['Sh']); tap(*pos['t']); tap(*pos['h']); tap(*pos['e'])     # shift applies to one letter
tap(*pos['Ent']); tap(*pos['1']); tap(*pos['2'])
tap(*pos['?!']); pos2 = key_positions(); tap(*pos2['!']); tap(*pos2['?!'])
tap(*pos['<-'])                                                   # backspace removes the '!'
assert api.page()['text'] == 'hi The\n12', repr(api.page()['text'])
n = draw(); print('draw commands (keyboard):', n); assert n < 1024 and any('_' in t for t in texts())
tap(*pos['Done']); assert api.mode() == 'view'
print('typing: letters, shift, enter, digits, symbols, backspace, done OK')

# draw: line, box, circle, undo, pending marker
toolbar(2, 5); assert api.mode() == 'draw'
tap(100, 200); tap(300, 400)                                       # line
toolbar(2, 5); tap(50, 100); tap(150, 180)                          # box
toolbar(3, 5); tap(240, 300); tap(240, 350)                         # circle r=50
sh = api.page()['shapes']; shapes = [dict(sh[i].items()) for i in range(1, len(sh) + 1)]
assert [s['k'] for s in shapes] == ['l', 'r', 'c'] and shapes[1][3] == 100 and shapes[1][4] == 80 and shapes[2][3] == 50, shapes
toolbar(4, 5); assert len(api.page()['shapes']) == 2                 # undo removes the circle
tap(60, 80); assert rt.eval('__TEST.api.msg')() == 'tap the second point'; toolbar(4, 5)   # undo cancels a pending point
assert len(api.page()['shapes']) == 2
tap(600, 300)                                                        # outside the canvas: ignored
assert len(api.page()['shapes']) == 2
toolbar(5, 5); assert api.mode() == 'view'
n = draw(); print('draw commands (text + shapes):', n); assert n < 1024
print('shapes: line, box, circle, undo, cancel, outside OK')

# pages: new, switch, delete, side buttons, swipes
toolbar(3, 5); assert api.mode() == 'pages'
toolbar(1, 3); assert len(api.state()['pages']) == 2 and api.state()['cur'] == 2 and api.mode() == 'type'
tap(*pos['a']); tap(*pos['Done'])
toolbar(3, 5); tap(240, 70 + 0 * 40 + 20); assert api.state()['cur'] == 1 and api.mode() == 'view'
on_input(None, T(type='key', key='down', state='down')); assert api.state()['cur'] == 2
on_input(None, T(type='touch', gesture='swipe_right', x=10, y=10)); assert api.state()['cur'] == 1
toolbar(3, 5); rt.execute('texts = {}'); rt.eval('on_draw')(); assert any(t.strip().startswith('> hi The') for t in texts()), texts()
toolbar(2, 3); S = api.state(); assert len(S['pages']) == 1 and S['pages'][1]['text'] == 'a'      # delete current (page 1)
toolbar(2, 3); assert len(api.state()['pages']) == 1 and api.state()['pages'][1]['text'] == ''  # last page: cleared
toolbar(3, 3); assert api.mode() == 'view'
print('pages: new, open, delete, clear, keys, swipe OK')

# lock + info
tap(*[0, 0]); toolbar(4, 5); S = api.state()
assert S['lock'] == 1 and 'set_as_lockscreen_app' in list(rt.eval('calls').values()) and 'set_as_lockscreen_app: true' in api.msg()
toolbar(5, 5); assert api.mode() == 'info'
info = [l for l in api.info().values()]; assert info[0] == 'ctx.lock:' and any('set_interval' in l for l in info) and any('set_as_lockscreen_app' in l for l in info)
n = draw(); assert n < 1024; toolbar(1, 1); assert api.mode() == 'view'
print('lock + info OK')

# resume + garbage
rt2 = make(); api2 = rt2.eval('__TEST.api')
rt2.eval('on_load')(rt2.table_from({'pages': rt2.table_from({1: rt2.table_from({'text': 'saved', 'shapes': rt2.table_from({})})}), 'cur': 1, 'lock': 1}))
rt3 = make(); api3 = rt3.eval('__TEST.api')
rt3.eval('ctx').state = rt3.table_from({'pages': 'junk', 'cur': 'x', 'lock': 99})
rt3.eval('on_load')(rt3.eval('ctx')); S3 = api3.state(); assert len(S3['pages']) == 1 and S3['cur'] == 1 and S3['lock'] is None
print('resume + garbage OK')

# the lock-screen entry renders the chosen page from the same state
rl = make(LOCK, extra='ctx.state = { pages = { { text = "note one", shapes = { { k = "c", 100, 100, 20 } } }, { text = "two", shapes = {} } }, cur = 1, lock = 2 }')
rl.execute('texts = {}; cmds = 0'); rl.eval('on_draw')()
lt = list(rl.eval('texts').values()); assert '09:05' in lt and 'two' in lt and 'note one' not in lt, lt
rl2 = make(LOCK, extra='ctx.state = {}'); rl2.execute('texts = {}'); rl2.eval('on_draw')(); assert any('no page chosen' in t for t in rl2.eval('texts').values())
print('lockscreen.lua renders the lock page (clock + text), handles empty state OK')
assert api.err() is None
print('ALL NOTES TESTS PASSED')
