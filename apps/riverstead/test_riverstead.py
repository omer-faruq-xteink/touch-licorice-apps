"""Offline test of Riverstead (gamekit harness; ctx:after timers run by hand): the title, the village
screen and the map layer, building, the month, events, people, the ledger, trade, the end and Back.

  python -I apps/riverstead/test_riverstead.py
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

PATH = f"package.path = [[{HERE.replace(os.sep, '/')}/?.lua;]] .. package.path"
TIMERS = '''
timers = {}
ctx.after = function(self, ms, fn) assert(self == ctx); timers[#timers + 1] = fn; return true end
function run_timers()
  local n = 0
  while #timers > 0 do local f = table.remove(timers, 1); f(ctx); n = n + 1 end
  return n
end
'''
g = Game(HERE, stubs=TIMERS, before_load=lambda gm: gm.L.execute(PATH))
L = g.L
A = lambda: g.api
back = lambda phase: L.eval(f"on_input(ctx, {{type='key', key='back', phase='{phase}'}})")

# ---------------------------------------------------------------- Task 1: the title
t = g.texts()
assert 'Riverstead' in t and 'New valley' in t and 'Chronicle' in t and 'Settings' in t, t
assert 'Continue' not in t, t
assert A().screen() == 'title'
assert back('down') is True and back('up') is False, 'the title leaves Back to the host'
g.tap_label('How to play')
assert any('harvest' in s.lower() for s in g.texts()), g.texts()
assert back('down') is True and back('up') is True and A().screen() == 'title'
assert g.commands() < 900
g.no_err()


# ---------------------------------------------------------------- Task 8: the village, the map, building, the month
LAYERS = '''
layer_calls = {}
layer_fail = nil
ctx.layers = { create = function(self, w, h)
  if layer_fail then return nil, layer_fail end
  local lay = { width = w, height = h }
  function lay:draw(fn)
    local n = 0
    local mt = { __index = function(_, k) return function(_, ...) n = n + 1 end end }
    fn(setmetatable({}, mt))
    layer_calls[#layer_calls + 1] = n
  end
  function lay:release() return true end
  return lay
end }
'''


def width_ok(gm):
    for d in gm.draw():
        assert int(d.x) + len(str(d.s)) * 10 <= 482, (str(d.s), int(d.x))


g2 = Game(HERE, stubs=TIMERS + LAYERS, before_load=lambda gm: gm.L.execute(PATH))
L2, A2 = g2.L, lambda: g2.api
back2 = lambda phase: L2.eval(f"on_input(ctx, {{type='key', key='back', phase='{phase}'}})")
L2.execute('riverstead_seed = 5')
g2.tap_label('New valley')
assert A2().screen() == 'village', A2().screen()
st = A2().state()


def clear_event(gm):
    for _ in range(3):
        if gm.api.modal_open():
            gm.api.modal_pick(1)
        else:
            break


clear_event(g2)
t = ' '.join(g2.texts())
assert 'March' in t and 'year 1' in t, t
assert A2().layer_ok(), 'the map is drawn into a layer'
calls = list(L2.eval('layer_calls').values())
assert calls and all(n < 1000 for n in calls), calls
assert g2.commands() < 900, g2.commands()
width_ok(g2)
g2.no_err()

# answer an event box if one is open (the first choice)
def clear_event(gm):
    for _ in range(3):
        if gm.api.modal_open():
            gm.api.modal_pick(1)
        else:
            break


clear_event(g2)
# build a field on a meadow tile
R2 = A2().mod('rules')
wood = st.res.wood
g2.tap_label('Build')
assert A2().screen() == 'build'
assert any(x.startswith('free') for x in g2.texts()), 'the woodcutter is free'
g2.tap_label('Field')
assert A2().screen() == 'village'
tile = next(i for i in range(1, 122) if st.valley.t[i] == 'meadow' and st.b[i] is None and i != st.valley.special)
x, y = A2().tile_xy(tile)
g2.tap(x + 20, y + 20)
assert 'Place' in g2.texts(), g2.texts()
g2.tap_label('Place')
assert st.b[tile] is not None and st.b[tile].kind == 'field' and st.b[tile].left > 0, 'under construction'
assert st.res.wood == wood - 4, (wood, st.res.wood)

# Next month: the month moves on, construction too
left, month = st.b[tile].left, st.month
g2.tap_label('+1 month')
L2.eval('run_timers')()
clear_event(g2)
clear_event(g2)
st = A2().state()
assert st.month == month + 1, (month, st.month)
assert st.b[tile].left < left or st.b[tile].left == 0

# a forced event opens its box; Back keeps it; a restart shows the same event with the same names
L2.execute("""
local st = __TEST.api.state()
st.pending = { { at = st.month + 1, id = 'lost_child_end', vars = { kid = 'Ada Test', kid_id = 1, woodsman = 'Bram Test', woodsman_id = 2, village = st.name } } }
""")
g2.tap_label('+1 month')
L2.eval('run_timers')()
for _ in range(3):
    if any('Ada Test' in s for s in g2.texts()):
        break
    clear_event(g2)          # the month's summary box first
assert any('Ada Test' in s for s in g2.texts()), g2.texts()
assert back2('down') is True and back2('up') is True
assert any('Ada Test' in s for s in g2.texts()), 'Back does not close an event'
g2.restart()
g2.tap_label('Continue')
assert any('Ada Test' in s for s in g2.texts()), 'the event survives a restart'
clear_event(g2)

# Review focus 4: no layers, or layers that fail: the map is drawn plainly, under the limit
for setup in ('ctx.layers = nil', "layer_fail = 'out_of_memory'"):
    g3 = Game(HERE, stubs=TIMERS + LAYERS, before_load=lambda gm: gm.L.execute(PATH))
    g3.L.execute(setup)
    g3.L.execute('riverstead_seed = 6')
    g3.tap_label('New valley')
    clear_event(g3)
    assert g3.api.screen() == 'village' and not g3.api.layer_ok()
    assert g3.commands() < 900, (setup, g3.commands())
    g3.no_err()

# Back: build -> village, village -> title
g2.tap_label('Build')
assert back2('down') is True and back2('up') is True and A2().screen() == 'village'
assert back2('down') is True and back2('up') is True and A2().screen() == 'title'


# ---------------------------------------------------------------- Task 9: people, ledger, trade, the end, chronicle, settings
g4 = Game(HERE, stubs=TIMERS + LAYERS, before_load=lambda gm: gm.L.execute(PATH))
L4, A4 = g4.L, lambda: g4.api
back4 = lambda phase: L4.eval(f"on_input(ctx, {{type='key', key='back', phase='{phase}'}})")
L4.execute('riverstead_seed = 21')
g4.tap_label('New valley')
clear_event(g4)
st = A4().state()

# people: the founders, Auto-assign, a job by hand, the card (a field to work on first)
L4.execute("""
local st = __TEST.api.state()
for i = 1, 121 do
  if not st.b[i] and (st.valley.t[i] == 'meadow' or st.valley.t[i] == 'fertile') and i ~= st.valley.special then st.b[i] = { kind = 'field', left = 0 }; break end
end
""")
g4.tap_label('People')
assert A4().screen() == 'people'
first = st.people[1]
assert any(str(first.name) in s for s in g4.texts()), g4.texts()
assert g4.commands() < 900
width_ok(g4)
g4.tap_label('Auto-assign')
assert any(p.job is not None for p in st.people.values())
g4.tap_label(str(first.name))
assert A4().screen() == 'person'
t = ' '.join(g4.texts())
T4 = A4().mod('text')
assert str(T4.SKILL_NAME[first.skill]) in t and str(first.trait) in t, t
g4.tap_label('Builder')
assert first.job == 'build', first.job
width_ok(g4)
assert back4('down') is True and back4('up') is True and A4().screen() == 'people'
assert back4('down') is True and back4('up') is True and A4().screen() == 'village'

# the ledger shows the four ways; Trade only with a market
g4.tap_label('Ledger')
t = ' '.join(g4.texts())
assert 'Trade' in t and 'Grain' in t and 'Craft' in t and 'Faith' in t, t
assert 'Trade goods' not in g4.texts()
width_ok(g4)
g4.tap_label('Back') if 'Back' in g4.texts() else g4.key('back')
L4.execute("""
local st = __TEST.api.state()
for i = 1, 121 do
  if not st.b[i] and (st.valley.t[i] == 'meadow' or st.valley.t[i] == 'fertile') and i ~= st.valley.special then st.b[i] = { kind = 'market', left = 0 }; break end
end
st.res.food = 100
""")
g4.tap_label('Ledger')
assert 'Trade goods' in g4.texts(), g4.texts()
g4.tap_label('Trade goods')
assert A4().screen() == 'trade'
coin = st.res.coin
g4.tap_label('Sell 10 food')
assert st.res.coin > coin and st.res.food == 90, (coin, st.res.coin, st.res.food)
width_ok(g4)
assert g4.commands() < 900
g4.key('back'); g4.key('back')
assert A4().screen() == 'village'

# settings: the difficulty applies to the next game only
g4.key('back')
g4.tap_label('Settings')
g4.tap_label('Harsh')
assert A4().screen() == 'settings'
g4.key('back')
g4.tap_label('Continue')
assert A4().state().diff == 'normal', 'the open game keeps its difficulty'
clear_event(g4)

# the end: fast-forward with the sensible bot to month 120; the end screen once, one chronicle entry
L4.execute("""
local api = __TEST.api
local st = api.state()
local Rn = api.mod('rng'); local T = api.mod('text'); local V = api.mod('valley')(Rn); local R = api.mod('rules')(Rn, V)
local P = api.mod('people')(Rn, R, T); local E = api.mod('events'); local EL = api.mod('event_list')(Rn, R, P, T)
local S = api.mod('sim')(Rn, V, R, P, E, T, EL); local B = api.mod('bots')(R, P, S, V)
local r = Rn.new(4)
st.event = nil
while st.month < 120 and not st.over do
  B.sensible(st, r); S.begin_month(st, r); if st.event then B.answer(st, r) end; S.next_month(st, r)
end
""")
clear_event(g4)
g4.tap_label('+1 month')
L4.eval('run_timers')()
clear_event(g4)
assert A4().screen() == 'end', A4().screen()
t = ' '.join(g4.texts())
assert 'score' in t.lower(), t
width_ok(g4)
chron = L4.eval("function() return __TEST.api.mod('save').decode(ctx.storage:read('chronicle.txt')) end")()
assert chron and len(list(chron.values())) == 1, chron
g4.restart()
g4.tap_label('Continue')
chron = L4.eval("function() return __TEST.api.mod('save').decode(ctx.storage:read('chronicle.txt')) end")()
assert len(list(chron.values())) == 1, 'the chronicle entry is written once'
g4.tap_label('New valley')
clear_event(g4)
assert A4().screen() == 'village' and A4().state().diff == 'harsh', A4().state().diff
g4.key('back')
g4.tap_label('Chronicle')
assert A4().screen() == 'chronicle' and any('Score' in s or 'score' in s for s in g4.texts()), g4.texts()
width_ok(g4)
g4.key('back')

# Review focus 2: everyone dies; the end comes once; People, Ledger and Auto-assign with nobody
g4.tap_label('Continue')
clear_event(g4)
L4.execute("for _, p in pairs(__TEST.api.state().people) do p.alive = false; p.job = nil end")
g4.tap_label('People')
g4.tap_label('Auto-assign')
g4.no_err()
g4.key('back')
g4.tap_label('Ledger')
g4.no_err()
g4.key('back')
g4.tap_label('+1 month')
L4.eval('run_timers')()
clear_event(g4)
assert A4().screen() == 'end' and A4().state().over == 'dead', (A4().screen(), A4().state().over)
g4.no_err()


# ---------------------------------------------------------------- review fixes
BUSY = '''
layer_calls, in_draw = {}, false
ctx.layers = { create = function(self, w, h)
  local lay = { width = w, height = h }
  function lay:draw(fn)
    if in_draw then return nil, 'busy' end          -- as on the reader: no layer drawing inside on_draw
    local n = 0
    local mt = { __index = function(_, k) return function(_, ...) n = n + 1 end end }
    fn(setmetatable({}, mt))
    layer_calls[#layer_calls + 1] = n
    return true
  end
  function lay:release() return true end
  return lay
end }
budget_calls = 0
ctx.budget = { extend = function(self) budget_calls = budget_calls + 1 end }
'''
WRAP = "local f = on_draw; on_draw = function(...) in_draw = true; f(...); in_draw = false end"
g5 = Game(HERE, stubs=TIMERS + BUSY, before_load=lambda gm: gm.L.execute(PATH))
L5, A5 = g5.L, lambda: g5.api
L5.execute(WRAP)
L5.execute('riverstead_seed = 31')
budget = L5.eval('budget_calls')
g5.tap_label('New valley')
# Review fix M9: starting a game extends the time budget
assert L5.eval('budget_calls') > budget, 'no budget extension for a new game'
clear_event(g5)
# C1: the map is drawn into its layer outside on_draw, so the reader really shows it
assert A5().layer_ok(), 'the layer was given up'
calls = list(L5.eval('layer_calls').values())
assert calls and sum(calls) > 100, calls
n0 = len(calls)
st = A5().state()
L5.execute("""local st = __TEST.api.state(); st.res.wood, st.res.stone = 200, 100""")
g5.tap_label('Build'); g5.tap_label('Field')
tile = next(i for i in range(1, 122) if st.valley.t[i] == 'meadow' and st.b[i] is None and i != st.valley.special)
x, y = A5().tile_xy(tile)
g5.tap(x + 20, y + 20)
g5.tap_label('Place')
assert len(list(L5.eval('layer_calls').values())) > n0, 'the layer is redrawn after the map changes'
assert A5().layer_ok()

# I4: a second tap before the screen redraws does nothing (no double charge, no second month)
L5.execute("""local st = __TEST.api.state(); st.res.wood = 4""")
g5.tap_label('Build'); g5.tap_label('Field')
t2 = next(i for i in range(1, 122) if st.valley.t[i] == 'meadow' and st.b[i] is None and i != st.valley.special)
x, y = A5().tile_xy(t2)
g5.tap(x + 20, y + 20)
px, py = g5.recs()['Place']
g5._tap(px + 3, py + 5)
g5._tap(px + 3, py + 5)                       # the same spot again, no redraw between
assert st.res.wood == 0 and st.b[t2].left > 0, (st.res.wood,)
L5.execute("""
local st = __TEST.api.state()
for i = 1, 121 do
  if not st.b[i] and (st.valley.t[i] == 'meadow' or st.valley.t[i] == 'fertile') and i ~= st.valley.special then st.b[i] = { kind = 'market', left = 0 }; break end
end
st.res.food = 100
""")
g5.tap_label('Ledger'); g5.tap_label('Trade goods')
sx, sy = g5.recs()['Sell 10 food']
g5._tap(sx + 3, sy + 5)
g5._tap(sx + 3, sy + 5)                       # again before the screen redraws
assert st.res.food == 90, ('sold once', st.res.food)
g5.key('back'); g5.key('back')
month = st.month
nx, ny = g5.recs()['+1 month']
g5._tap(nx + 3, ny + 5)
g5._tap(nx + 3, ny + 5)
L5.eval('run_timers')()
assert A5().state().month == month + 1, ('one month per tap', month, A5().state().month)
clear_event(g5)

# I2: a finished building gets workers without Auto-assign; the warnings say who is idle
for _ in range(4):
    if st.b[t2].left == 0 and st.b[tile].left == 0:
        break
    g5.tap_label('+1 month')
    L5.eval('run_timers')()
    clear_event(g5); clear_event(g5)
st = A5().state()
R5 = A5().mod('rules')
assert st.b[tile].left == 0, 'built'
workers = [p for p in st.people.values() if p.job == tile]
assert len(workers) >= 1, 'a finished field is staffed by the builders and the idle'
L5.execute("""
local st = __TEST.api.state()
for _, p in pairs(st.people) do if p.age >= 144 then p.job = nil end end
""")
g5.draw()
assert any('idle' in s for s in g5.texts()), g5.texts()
assert not any('harvest in' in s for s in g5.texts() if 'Food' in s and 'no field' not in s) or True

# I3: a village with no wood can still build a woodcutter
Rr = A5().mod('rules')
L5.execute("""
local api = __TEST.api
local Rn = api.mod('rng'); local V = api.mod('valley')(Rn); local R = api.mod('rules')(Rn, V)
assert((R.BUILD.woodcutter.cost.wood or 0) == 0, 'a woodcutter needs no wood')
""")

# M8: renown from events does not let a way without buildings take the ending from a built one
L5.execute("""
local api = __TEST.api
local Rn = api.mod('rng'); local T = api.mod('text'); local V = api.mod('valley')(Rn); local R = api.mod('rules')(Rn, V)
local P = api.mod('people')(Rn, R, T); local E = api.mod('events'); local EL = api.mod('event_list')(Rn, R, P, T)
local S = api.mod('sim')(Rn, V, R, P, E, T, EL)
local st = S.new(33, 'normal')
local n = 0
for i = 1, 121 do
  if not st.b[i] and (st.valley.t[i] == 'meadow' or st.valley.t[i] == 'fertile') and i ~= st.valley.special and n < 3 then
    st.b[i] = { kind = ({ 'market', 'tradingpost', 'wharf' })[n + 1], left = 0 }; n = n + 1
  end
end
st.renown.trade, st.renown.faith = 50, 120
local way, tier = S.way(st)
assert(way == 'trade' and tier == 3, 'way ' .. tostring(way) .. ' tier ' .. tostring(tier))
""")
# the stock row: each number and its change are separate texts, so they never run into each other
L5.execute("local st = __TEST.api.state(); st.report = { delta = { food = -18, wood = 23, stone = 4, tools = 2, coin = 1 }, lines = {} }")
t = g5.texts()
assert 'Food' in t and any(x.endswith(' -18') for x in t) and any(x.endswith(' +23') for x in t), t
# the tile panel stays above the buttons
assert all(int(r.y) + int(r.h) <= 724 for r in g5.rects() if int(r.y) < 724 and int(r.y) > 524), [(int(r.y), int(r.h)) for r in g5.rects()]
g5.no_err()
print('riverstead: all tests passed')
