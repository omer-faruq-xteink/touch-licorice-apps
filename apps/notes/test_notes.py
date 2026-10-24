"""Offline test of the API 2.9 Notes app under Lua 5.4 (lupa) with a method-style ctx stub.

  python notes29/test_notes29.py
"""
import os, sys
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
L = lua54.LuaRuntime(unpack_returned_tuples=True)
L.execute(r'''
drawn, cmds, store = {}, 0, {}
local gmt = {}
gmt.__index = function(_, k)
  return function(_, ...)
    cmds = cmds + 1
    if k == 'text' then drawn[#drawn + 1] = select(3, ...) end
    if k == 'polyline' then
      local pts = select(1, ...)
      assert(type(pts) == 'table' and type(pts[1]) == 'number', 'flat polyline expected')
    end
  end
end
gg = setmetatable({}, gmt)
local function M(t)
  local out = {}
  for k, f in pairs(t) do
    if type(f) == 'function' then out[k] = function(self, ...) assert(self == out, 'method call expected for ' .. k); return f(...) end
    else out[k] = f end
  end
  return out
end
pending = {}
ctx = {
  invalidate = function() end, state = {},
  storage = M({ write = function(n, d) store[n] = d; return true end, read = function(n) if store[n] then return store[n] end return nil, 'not_found' end }),
  fonts = { small = M({ measure = function(s) return #s * 8 end }), medium = M({ measure = function(s) return #s * 10 end }), large = M({ measure = function(s) return #s * 14 end }) },
  input = M({ text = function(opts, fn) pending[#pending + 1] = fn end }),
  dialog = M({ confirm = function(opts, fn) pending[#pending + 1] = fn end }),
  lockscreen = M({ set_default = function() set_default_calls = (set_default_calls or 0) + 1 end }),
  clock = M({ now = function() return { hour = 9, minute = 5 } end }),
  device = M({ battery = function() return { percent = 77 } end }),
}
''')
L.execute(f"dofile([[{os.path.join(HERE, 'index.lua').replace(os.sep, '/')}]])")
g = L.globals()
ev = L.eval("function(ph, x, y) on_input(ctx, {type='pointer', phase=ph, x=x, y=y}) end")
tap = L.eval("function(x, y) on_input(ctx, {type='pointer', phase='down', x=x, y=y}); on_input(ctx, {type='pointer', phase='up', gesture='tap', x=x, y=y}) end")
draw = L.eval("function() drawn = {}; cmds = 0; on_draw(ctx, gg); return cmds end")

g.on_load(g.ctx)
# a stroke with 200 points -> saved, drawn with few commands
ev('down', 100, 300)
for i in range(1, 200):
    ev('move', 100 + i, 300 + (i % 7))
ev('up', 300, 310)
assert 'page1.txt' in g.store and g.store['page1.txt'].startswith('S '), g.store.keys()
n = draw()
assert n < 40, f'too many draw commands for one stroke: {n}'
# text tool: tap Text, tap canvas, answer the editor
tap(4 + 79 + 5, 20)
tap(200, 500)
assert len(g.pending) == 1
g.pending[1](g.ctx, 'hello world')
assert 'T 200 500 2 hello world' in g.store['page1.txt'], g.store['page1.txt']
# undo removes the text
tap(4 + 2 * 79 + 5, 20)
assert 'hello' not in g.store['page1.txt']
# page cycles and comes back with the stroke intact
tap(4 + 3 * 79 + 5, 20)
assert g.ctx.state.page == 2
for _ in range(7):
    tap(4 + 3 * 79 + 5, 20)
assert g.ctx.state.page == 1
g.on_load(g.ctx)
assert g.store['page1.txt'].startswith('S ')
# lock: confirm dialog -> lock.txt + set_default
tap(4 + 4 * 79 + 5, 20)
g.pending[2](g.ctx, True)
assert g.store['lock.txt'] == '1\nclock' and g.set_default_calls == 1
# clear: confirm -> empty page
tap(4 + 5 * 79 + 5, 20)
g.pending[3](g.ctx, True)
assert g.store['page1.txt'] == ''
draw()
assert not any('ERR' in str(s) for s in g.drawn.values()), list(g.drawn.values())

# lock screen entry draws the chosen page with a clock
g.store['page1.txt'] = 'S 10,100 50,140 90,100\nT 20 200 3 good morning'
L.execute("on_draw, on_load = nil, nil")
L.execute(f"dofile([[{os.path.join(HERE, 'lockscreen.lua').replace(os.sep, '/')}]])")
draw()
texts = list(g.drawn.values())
assert 'good morning' in texts and '09:05' in texts and '77%' in texts, texts
print('notes29 tests passed')
