"""Offline harness for gamekit games under Lua 5.4 (lupa): a method-style ctx stub (storage, fonts
that measure 10 px per character, clock, input), a gg that records texts, rects and circles, and
helpers to tap, tap a label, press keys and restart.

    from harness import Game
    g = Game('apps/lightsout')     # bundles, loads index.lua, calls on_load
    g.texts(), g.tap(x, y), g.tap_label('New'), g.key('back'), g.store, g.restart()
"""
import os, subprocess, sys
from lupa import lua54

STUBS = r'''
drawn, rects, circles, store, inputs = {}, {}, {}, {}, {}
fake_ms = 100000
local gmt = {}
gmt.__index = function(_, k) return function(_, ...)
  if k == 'text' then local x, y, s = ...; drawn[#drawn + 1] = { s = s, x = x, y = y } end
  if k == 'rect' then local x, y, w, h, o = ...; rects[#rects + 1] = { x = x, y = y, w = w, h = h, fill = type(o) == 'table' and o.fill or false } end
  if k == 'circle' then local x, y, r = ...; circles[#circles + 1] = { x = x, y = y, r = r } end
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
  defer_full_refresh = function(self, n) full_refreshes = (full_refreshes or 0) + 1 end,
  storage = M({ write = function(n, d) store[n] = d; return true end, read = function(n) if store[n] then return store[n] end return nil, 'not_found' end }),
  fonts = { small = font('small', 20), medium = font('medium', 24), large = font('large', 30) },
  input = M({ text = function(opts, fn) inputs[#inputs + 1] = fn end }),
  clock = M({ millis = function() return fake_ms end }),
}
__TEST = {}
'''


class Game:
    def __init__(self, app_dir):
        self.app = os.path.abspath(app_dir)
        subprocess.run([sys.executable, '-I', os.path.join(self.app, 'bundle.py')], check=True)
        self.L = lua54.LuaRuntime(unpack_returned_tuples=True)
        self.L.execute(STUBS)
        self.g = self.L.globals()
        self.store = self.g.store
        self._tap = self.L.eval("function(x, y) on_input(ctx, {type='pointer', phase='down', x=x, y=y}); on_input(ctx, {type='pointer', phase='up', gesture='tap', x=x, y=y}) end")
        self._key = self.L.eval("function(k) fake_ms = fake_ms + 300; on_input(ctx, {type='key', key=k}) end")
        self._draw = self.L.eval("function() drawn, rects, circles = {}, {}, {}; on_draw(ctx, gg); return drawn end")
        self.restart()

    def restart(self):
        self.L.execute(f"dofile([[{os.path.join(self.app, 'index.lua').replace(os.sep, '/')}]])")
        self.g.on_load(self.g.ctx)
        self.api = self.L.eval('__TEST.api')

    def draw(self):
        return list(self._draw().values())

    def texts(self):
        return [str(v.s) for v in self.draw()]

    def recs(self):
        out = {}
        for r in self.draw():
            out[str(r.s)] = (int(r.x), int(r.y))       # the last one drawn: a button over a title
        return out

    def rects(self):
        self.draw()
        return list(self.g.rects.values())

    def circles(self):
        self.draw()
        return list(self.g.circles.values())

    def tap(self, x, y):
        self._tap(x, y)

    def tap_label(self, label):
        r = self.recs()
        assert label in r, (label, list(r))
        x, y = r[label]
        self._tap(x + 3, y + 5)

    def key(self, k):
        self._key(k)

    def advance(self, ms):
        self.L.execute(f'fake_ms = fake_ms + {int(ms)}')

    def no_err(self):
        t = self.texts()
        assert not any('ERR' in x for x in t), t
