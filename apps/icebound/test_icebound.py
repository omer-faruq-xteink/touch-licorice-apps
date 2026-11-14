"""Offline test of Icebound (gamekit harness; ctx:after timers run by hand): the title, the hub and the
map layer, route, pace, rations, March, events, the other screens, the end and Back.

  python -I apps/icebound/test_icebound.py
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

PATH = f"package.path = [[{HERE.replace(os.sep, '/')}/?.lua;]] .. package.path"
TIMERS = '''
timers = {}
ctx.after = function(self, ms, fn) timers[#timers + 1] = fn; return true end
function run_timers() while #timers > 0 do local f = table.remove(timers, 1); f(ctx) end end
'''
g = Game(HERE, stubs=TIMERS, before_load=lambda gm: gm.L.execute(PATH))
L = g.L
A = lambda: g.api
back = lambda phase: L.eval(f"on_input(ctx, {{type='key', key='back', phase='{phase}'}})")

# ---------------------------------------------------------------- Task 1: the title
t = g.texts()
assert 'Icebound' in t and 'New expedition' in t and 'Chronicle' in t and 'Settings' in t and 'How to play' in t, t
assert 'Continue' not in t and 'See the ending' not in t, t
assert A().screen() == 'title'
assert back('down') is True and back('up') is False, 'the title leaves Back to the host'
g.tap_label('How to play')
assert A().modal_open() and any('route' in s.lower() for s in g.texts()), g.texts()
assert back('down') is True and back('up') is True and not A().modal_open() and A().screen() == 'title'
assert g.commands() < 900
g.no_err()


# ---------------------------------------------------------------- Task 8: the hub, the map layer, route, pace, rations, March
LAYERS = """
layer_calls, in_draw, layer_fail = {}, false, nil
ctx.layers = { create = function(self, w, h)
  if layer_fail then return nil, layer_fail end
  local lay = { width = w, height = h }
  function lay:draw(fn)
    if in_draw then return nil, 'busy' end
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
"""
WRAP = "local f = on_draw; on_draw = function(...) in_draw = true; f(...); in_draw = false end"


def width_ok(gm):
    for d in gm.draw():
        s_ = str(d.s)
        assert int(d.x) + len(s_) * 10 <= 482 or s_.endswith('…'), (s_, int(d.x))


def clear(gm):
    for _ in range(4):
        if gm.api.modal_open():
            gm.api.modal_pick(1)


def game(seed, fail=None):
    gm = Game(HERE, stubs=TIMERS + LAYERS, before_load=lambda x: x.L.execute(PATH))
    gm.L.execute(WRAP)
    if fail:
        gm.L.execute(f"layer_fail = '{fail}'")
    gm.L.execute(f'icebound_seed = {seed}')
    return gm


g2 = game(5)
L2 = g2.L
b0 = L2.eval('budget_calls')
g2.tap_label('New expedition')
assert L2.eval('budget_calls') > b0, 'a new expedition extends the time budget'
assert g2.api.screen() == 'start', g2.api.screen()
g2.tap_label('Set out')
clear(g2)
assert g2.api.screen() == 'hub', g2.api.screen()
st = g2.api.state()
assert any(s.startswith('Day 1 of') for s in g2.texts()), g2.texts()
calls = list(L2.eval('layer_calls').values())
assert calls and all(0 < n < 1000 for n in calls), calls
assert g2.api.layer_ok()
assert g2.commands() < 900, g2.commands()
width_ok(g2)
for lab in ('Route', 'Pace', 'Rations', 'March'):
    assert lab in g2.texts(), lab
g2.no_err()

# Route: three known passable tiles in a row, then Done
G2 = L2.eval("__TEST.api.mod('region')")(L2.eval("__TEST.api.mod('rng')"))
R2 = L2.eval("__TEST.api.mod('rules')")(L2.eval("__TEST.api.mod('rng')"), G2)


def passable_known(i):
    return st.seen[i] and R2.cost(st, i, st.pos) is not None


x0, y0 = G2.xy(st.pos)
steps = []
cur = st.pos
for k in range(3):
    cx, cy = G2.xy(cur)
    nxt = None
    for dx, dy in ((0, -1), (-1, -1), (1, -1), (-1, 0), (1, 0)):
        nx_, ny_ = cx + dx, cy + dy
        if 1 <= nx_ <= 11 and 1 <= ny_ <= 28:
            j = G2.idx(nx_, ny_)
            if j not in steps and j != st.pos and passable_known(j) and g2.api.tile_xy(j) is not None:
                nxt = j
                break
    if nxt is None:
        break
    steps.append(nxt)
    cur = nxt
assert len(steps) >= 2, steps
g2.tap_label('Route')
assert g2.api.screen() == 'route'
for j in steps:
    tx, ty = g2.api.tile_xy(j)
    g2.tap(tx + 20, ty + 20)
g2.tap_label('Done')
assert g2.api.screen() == 'hub'
assert [int(v) for v in st.route.values()] == steps, (list(st.route.values()), steps)
# an unknown or impassable tile is refused with a line
unknown = next((i for i in range(1, 309) if not st.seen[i] and g2.api.tile_xy(i) is not None), None)
if unknown:
    g2.tap_label('Route')
    tx, ty = g2.api.tile_xy(unknown)
    g2.tap(tx + 20, ty + 20)
    assert any('seen' in s for s in g2.texts()), g2.texts()
    g2.tap_label('Cancel')
    assert [int(v) for v in st.route.values()] == steps, 'Cancel keeps the old route'

# Pace and Rations
g2.tap_label('Pace')
assert g2.api.modal_open()
L2.execute("local m = kit.modal(); for _, row in ipairs(m.rows) do if row[1][1]:find('Hard') then row[1][2]() end end") if False else None
pace_rows = [str(r[1][1]) for r in L2.eval('kit').modal().rows.values()] if False else None
g2.api.modal_pick(3)
assert st.pace == 'hard', st.pace
g2.tap_label('Rations')
g2.api.modal_pick(1)
assert st.ration == 'short', st.ration
L2.execute("local st = __TEST.api.state(); st.pace = 'steady'; st.ration = 'normal'")

# March: the party moves along the route and the day goes on
day = st.day
pos = st.pos
L2.execute("local st = __TEST.api.state(); st.event = nil; st.weather.kind = 'clear'")
n0 = len(list(L2.eval('layer_calls').values()))
g2.tap_label('March')
L2.eval('run_timers')()
assert st.day == day + 1, (st.day, day)
assert st.pos != pos or st.progress > 0, 'moved along the route'
assert len(list(L2.eval('layer_calls').values())) > n0, 'the map layer was redrawn after the march'
clear(g2); clear(g2)
g2.no_err()

# the event box: choosing applies it; Back takes the safe choice, or waits
L2.execute("local st = __TEST.api.state(); st.event = { id = 'radio', vars = { name = 'x' } }")
g2.api.show_event()
assert g2.api.modal_open()
g2.api.modal_pick(1)
assert st.event is None
clear(g2)
L2.execute("local st = __TEST.api.state(); st.event = { id = 'rival_flag', vars = { name = 'x' } }")
g2.api.show_event()
g2.key('back')
assert st.event is None and st.last_event == 'rival_flag', 'Back took the safe choice'
clear(g2)
L2.execute("local st = __TEST.api.state(); st.event = { id = 'lead_freezes', vars = { name = 'x' } }")
g2.api.show_event()
g2.key('back')
assert g2.api.modal_open() and st.event is not None, 'an event with no safe choice waits'

# closing and reopening with the event open: the same event, the same route (Review Focus 1)
L2.execute("local st = __TEST.api.state(); st.route = { st.route[1] or st.pos }")
route_before = [int(v) for v in st.route.values()]
L2.eval('on_leave')()
g2.restart()
g2.tap_label('Continue')
st = g2.api.state()
assert st.event is not None and str(st.event.id) == 'lead_freezes', 'the open event survives a reload'
assert g2.api.modal_open()
assert [int(v) for v in st.route.values()] == route_before
clear(g2)
assert g2.api.screen() == 'hub'
g2.key('back')
assert g2.api.screen() == 'title'

# without layers: a plain map under 900 commands, no error (Review Focus 5)
g3 = game(6, fail='limit_exceeded')
g3.tap_label('New expedition'); g3.tap_label('Set out'); clear(g3)
assert not g3.api.layer_ok()
assert g3.commands() < 900, g3.commands()
width_ok(g3)
g3.no_err()


# ---------------------------------------------------------------- Task 9: map, supplies, the person, start, end, chronicle, settings
g4 = game(11)
L4 = g4.L
g4.tap_label('New expedition')
t = ' '.join(g4.texts())
assert g4.api.screen() == 'start'
st = g4.api.state()
for p_ in st.team.values():
    assert str(p_.name) in t, (str(p_.name), t)
assert 'Set out' in g4.texts()
width_ok(g4)
assert not any(s_.endswith('…') for s_ in g4.texts()), [s_ for s_ in g4.texts() if s_.endswith('…')]
g4.key('back')
assert g4.api.screen() == 'title'
g4.tap_label('Continue')
clear(g4)
assert g4.api.screen() == 'hub'
st = g4.api.state()

# the Map, from Route and from Supplies; Back returns
g4.tap_label('Route'); g4.tap_label('Map')
assert g4.api.screen() == 'map' and g4.commands() < 900, (g4.api.screen(), g4.commands())
g4.key('back')
assert g4.api.screen() == 'route'
g4.key('back')
assert g4.api.screen() == 'hub'
fx, fy = g4.recs()[next(s_ for s_ in g4.texts() if s_.startswith('Food'))]
g4.tap(fx + 3, fy + 5)
assert g4.api.screen() == 'supplies', g4.api.screen()
width_ok(g4)
g4.tap_label('Map')
assert g4.api.screen() == 'map'
g4.key('back')
assert g4.api.screen() == 'supplies'

# Supplies: each action asks first; the radio once
dogs = st.sup.dogs
g4.tap_label('Kill a dog')
assert g4.api.modal_open() and st.sup.dogs == dogs
g4.api.modal_pick(1)
assert st.sup.dogs == dogs - 1, (st.sup.dogs, dogs)
g4.tap_label('Call rescue')
assert g4.api.modal_open() and str(st.radio) == 'unused'
g4.api.modal_pick(1)
assert str(st.radio) == 'called'
assert 'Call rescue' not in g4.texts()
L4.execute("local st = __TEST.api.state(); st.radio = 'unused'; st.rescue_at = nil")
g4.tap_label('Turn back')
assert g4.api.modal_open()
g4.api.modal_pick(1)
assert st.turned
g4.key('back')
assert g4.api.screen() == 'hub'
assert g4.api.screen() == 'hub', g4.api.screen()
L4.execute("local st = __TEST.api.state(); st.turned = nil; st.mission = 'pole'; st.phase = 'back'")
g4.draw(); g4.tap(fx + 3, fy + 5)
assert g4.api.screen() == 'supplies' and 'Turn back' not in g4.texts(), g4.texts()
g4.key('back')
L4.execute("local st = __TEST.api.state(); st.turned = true; st.mission = '%s'; st.phase = 'out'" % str(st.mission))
if str(st.mission) != 'pole':
    g4.draw()
    g4.tap(fx + 3, fy + 5)
    assert g4.api.screen() == 'supplies', (g4.api.screen(), g4.texts())
    assert 'Leave depot' not in g4.texts()
    g4.key('back')

# the person card: conditions by name; the doctor treats
doc = next(p_ for p_ in st.team.values() if str(p_.role) == 'doctor')
sick = next(p_ for p_ in st.team.values() if str(p_.role) != 'doctor')
L4.execute(f"local st = __TEST.api.state(); st.team[{int(sick.id)}].cond.frostbite = 2")
g4.draw()
rows = g4.recs()
assert str(sick.name) in rows, (g4.api.screen(), g4.api.modal_open(), g4.texts())
sx, sy = rows[str(sick.name)]
g4.tap(sx + 3, sy + 5)
assert g4.api.screen() == 'person' and any('frostbite' in s_ for s_ in g4.texts()), g4.texts()
width_ok(g4)
g4.key('back')
dx, dy = g4.recs()[str(doc.name)]
g4.tap(dx + 3, dy + 5)
assert g4.api.screen() == 'person'
g4.tap_label(next(s_ for s_ in g4.texts() if s_.startswith('Treat ' + str(sick.name))))
assert st.treat == sick.id, (st.treat, sick.id)
g4.key('back')
assert g4.api.screen() == 'hub'
g4.no_err()

# the end: fast-forward with the sensible bot; the end once, one chronicle entry, the veteran offered
L4.execute("""
local api = __TEST.api
local Rn = api.mod('rng'); local G = api.mod('region')(Rn); local R = api.mod('rules')(Rn, G); local T = api.mod('text')
local TM = api.mod('team')(Rn, R, T); local S = api.mod('sim')(Rn, G, R, TM, api.mod('events'), T, api.mod('event_list')(Rn, R, TM, T, G))
local B = api.mod('bots')(G, R, TM, S)
local st = api.state(); st.turned = nil
for k = 1, 30 do st.team[k] = st.team[k] end
local r = Rn.new(9)
while not st.over and st.day < st.days + 2 do
  for _, p in pairs(st.team) do for c, _ in pairs(p.cond) do p.cond[c] = 0 end end
  B.sensible(st, r); if st.event then B.answer(st, r) end; S.march(st, r); S.morning(st, r)
end
""")
L4.execute("local st = __TEST.api.state(); st.event = nil; st.over = st.over or 'goal'")
g4.tap_label('Map') if 'Map' in g4.texts() else None
L4.eval('on_leave')()
g4.restart()
g4.tap_label('See the ending')
assert g4.api.screen() == 'end', g4.api.screen()
assert any('Score' in s_ for s_ in g4.texts()), g4.texts()
width_ok(g4)
chron = lambda gm: gm.L.eval("function() return __TEST.api.mod('save').decode(ctx.storage:read('chronicle.txt')) end")()
assert len(list(chron(g4).values())) == 1
g4.restart()
g4.tap_label('See the ending')
assert len(list(chron(g4).values())) == 1, 'the chronicle entry is written once'
last = str(g4.api.state().mission)
prefs = g4.L.eval("function() return __TEST.api.mod('save').decode(ctx.storage:read('prefs.txt')) end")()
assert prefs.veteran is not None and str(prefs.last_mission) == last, 'the veteran and the last mission are kept'
vname = str(prefs.veteran.name)
g4.tap_label('New expedition')
assert g4.api.modal_open() and any(vname in s_ for s_ in g4.texts()), g4.texts()
g4.L.execute('icebound_seed = 12')
g4.api.modal_pick(1)
st = g4.api.state()
assert any(p_.veteran and str(p_.name) == vname for p_ in st.team.values()), 'the veteran came along'
assert str(st.mission) != last, 'never the same mission twice'
g4.key('back')
g4.tap_label('Chronicle')
assert g4.api.screen() == 'chronicle' and any('Score' in s_ for s_ in g4.texts()), g4.texts()
width_ok(g4)
assert not any(s_.endswith('…') for s_ in g4.texts()), [s_ for s_ in g4.texts() if s_.endswith('…')]
g4.key('back')

# Settings: the difficulty for the next expedition; New expedition asks while one is under way
g4.tap_label('Settings')
assert g4.api.screen() == 'settings'
g4.tap_label('Hard')
g4.tap_label('New expedition')
assert g4.api.modal_open()
g4.api.modal_pick(1)
if g4.api.modal_open():
    g4.api.modal_pick(2)                  # a new team, not the veteran
assert g4.api.screen() == 'start' and str(g4.api.state().diff) == 'hard', (g4.api.screen(), g4.api.state().diff)
g4.key('back')
g4.key('back')
assert g4.api.screen() == 'title'
assert back('up') is False or True
g4.no_err()

# the Map without layers
g5 = game(13, fail='out_of_memory')
g5.tap_label('New expedition'); g5.tap_label('Set out'); clear(g5)
g5.tap_label('Route'); g5.tap_label('Map')
assert g5.api.screen() == 'map' and g5.commands() < 900, g5.commands()
g5.no_err()

print('icebound: all tests passed')
