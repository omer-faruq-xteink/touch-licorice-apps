"""Riverstead 1.0.0 polish before the store: the review's minors and the spec items left out of the first
build (each a test that failed first).

  python -I apps/riverstead/test_polish.py
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

PATH = f"package.path = [[{HERE.replace(os.sep, '/')}/?.lua;]] .. package.path"
STUBS = '''
timers = {}
ctx.after = function(self, ms, fn) timers[#timers + 1] = fn; return true end
function run_timers() while #timers > 0 do local f = table.remove(timers, 1); f(ctx) end end
layer_fail = nil
ctx.layers = { create = function(self, w, h)
  if layer_fail then return nil, layer_fail end
  local lay = { width = w, height = h }
  function lay:draw(fn) local mt = { __index = function() return function() end end }; fn(setmetatable({}, mt)); return true end
  function lay:release() return true end
  return lay
end }
'''


def game(seed=5, layers=True):
    g = Game(HERE, stubs=STUBS, before_load=lambda gm: gm.L.execute(PATH))
    if not layers:
        g.L.execute("layer_fail = 'no layers'")
    g.L.execute(f'riverstead_seed = {seed}')
    return g


def clear(g):
    for _ in range(4):
        if g.api.modal_open():
            g.api.modal_pick(1)


g = game()
L = g.L
g.tap_label('New valley')
clear(g)
L.execute("""
api = __TEST.api
Rn = api.mod('rng'); T = api.mod('text'); V = api.mod('valley')(Rn); R = api.mod('rules')(Rn, V)
P = api.mod('people')(Rn, R, T); E = api.mod('events'); EL = api.mod('event_list')(Rn, R, P, T)
S = api.mod('sim')(Rn, V, R, P, E, T, EL)
function def_of(id) for _, d in ipairs(EL.defs) do if d.id == id then return d end end end
function fresh(seed) local st = S.new(seed, 'normal'); st.event = nil; return st end
function count(st) return R.population(st) end
function married(st) for _, id in ipairs(P.living(st)) do local p = st.people[id]; if p.spouse and p.age >= 192 then return p end end end
""")
ev = lambda s: L.eval(s)

# ---------------------------------------------------------------- the foundling is a baby, the family brings {n}
assert ev("""(function()
  local st = fresh(11); local n0 = st.next_id
  E.apply(def_of('foundling'), 1, st, { village = st.name }, Rn.new(1), EL.ctx)
  local b = st.people[n0]
  return b and b.age < 12 and b.mother ~= nil and b.father ~= nil
end)()"""), 'the foundling arrives as a baby with adoptive parents'
assert ev("""(function()
  local st = fresh(11); local n0 = count(st)
  E.apply(def_of('family'), 1, st, { village = st.name, n = 5 }, Rn.new(1), EL.ctx)
  return count(st) - n0
end)()""") == 5, 'a family of 5 brings 5'

# ---------------------------------------------------------------- someone who leaves is no longer married
assert ev("""(function()
  local st = fresh(12); local p = married(st); local q = st.people[p.spouse]
  EL.ctx.fx({ leave = 'unhappy' }, st, { unhappy_id = p.id }, Rn.new(1))
  return q.spouse == nil and p.gone
end)()"""), 'the partner of someone who left can marry again'
assert ev("""(function()
  local st = fresh(12); local p = married(st); local q = st.people[p.spouse]
  p.sad, p.happy, p.mood, p.health = 3, 0, -10, 100
  P.month(st, Rn.new(2), { lines = {}, hunger = 0 })
  return p.gone and q.spouse == nil
end)()"""), 'leaving from unhappiness ends the marriage too'

# ---------------------------------------------------------------- buying needs room in storage
assert ev("""(function()
  local st = fresh(13); st.b[1] = nil
  for i = 1, 121 do if R.can_place(st, 'market', i) then st.b[i] = { kind = 'market', left = 0 }; break end end
  st.res.coin = 100; st.res.food = R.capacity(st) - 5
  local ok, why = R.trade(st, 'food', 10)
  return (not ok) and why:find('room') ~= nil and st.res.coin == 100
end)()"""), 'no charge for goods that do not fit'

# ---------------------------------------------------------------- the change figures are what really changed
assert ev("""(function()
  local st = fresh(14); st.res.food = 3
  local rep = R.produce(st, Rn.new(3))
  return rep.delta.food == st.res.food - 3
end)()"""), 'eating with too little food records what was eaten, not what was needed'
assert ev("""(function()
  local st = fresh(14); st.res.wood = R.capacity(st) + 40
  local rep = R.produce(st, Rn.new(3))
  return (rep.delta.wood or 0) <= -40
end)()"""), 'wood thrown away for lack of storage shows in the change'
assert ev("""(function()
  local st = fresh(14); st.report = { delta = {} }; st.res.food = 4
  EL.ctx.fx({ food = -10, coin = 5 }, st, {}, Rn.new(1))
  return st.report.delta.food == -4 and st.report.delta.coin == 5
end)()"""), "an event's gains and losses count in the month's change"

# ---------------------------------------------------------------- the ledger's born, died, came and left
assert ev("""(function()
  local st = fresh(15); local p = married(st); p.sad, p.happy, p.mood, p.health = 3, 0, -10, 100
  local rep = { lines = {}, hunger = 0 }
  P.month(st, Rn.new(2), rep)
  return rep.people and rep.people.left == 1
end)()"""), 'the month counts who left'
assert ev("""(function()
  local st = fresh(15); st.report = { delta = {}, people = {} }
  EL.ctx.fx({ newcomers = 2 }, st, {}, Rn.new(1))
  return st.report.people.came == 2
end)()"""), 'newcomers from an event are counted'

# ---------------------------------------------------------------- Back takes the safe choice where there is one
assert ev("""(function()
  local st = fresh(16); st.event = { id = 'pedlar', vars = { village = st.name } }
  local k = S.back_choice(st)
  return k ~= nil and S.offered(st)[k].label == 'Send him on'
end)()"""), 'the pedlar can be sent on with Back'
assert ev("""(function()
  local st = fresh(16); st.event = { id = 'rich_harvest', vars = { village = st.name } }
  return S.back_choice(st) == nil
end)()"""), 'an event with no safe choice waits for an answer'

# ---------------------------------------------------------------- newcomers come to a happy village with room
arrived = ev("""(function()
  local n = 0
  for seed = 1, 20 do
    local st = fresh(seed)
    for _, i in ipairs({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 }) do end
    local k = 0
    for i = 1, 121 do if k < 6 and R.can_place(st, 'house', i) then st.b[i] = { kind = 'house', left = 0 }; k = k + 1 end end
    for m = 1, 24 do
      for _, id in ipairs(P.living(st)) do st.people[id].happy = 90; st.people[id].mood = 10 end
      st.res.food = 300
      local rep = { lines = {}, hunger = 0 }
      P.month(st, Rn.new(seed * 100 + m), rep)
      n = n + ((rep.people or {}).came or 0)
      st.month = st.month + 1
    end
  end
  return n
end)()""")
assert arrived > 0, 'nobody ever came to a happy village with room'
crowded = ev("""(function()
  local n = 0
  for seed = 1, 20 do
    local st = fresh(seed)
    for m = 1, 24 do
      for _, id in ipairs(P.living(st)) do st.people[id].happy = 90 end
      st.res.food = 300
      local rep = { lines = {}, hunger = 0 }
      P.month(st, Rn.new(seed * 100 + m), rep)
      n = n + ((rep.people or {}).came or 0)
      st.month = st.month + 1
    end
  end
  return n
end)()""")
assert crowded == 0, ('newcomers came with no room', crowded)

# ---------------------------------------------------------------- marsh houses are unhealthy, smithy houses unhappy
assert ev("""(function()
  local Sv = api.mod('save')
  local st, house
  for seed = 1, 400 do
    st = fresh(seed)
    for i = 1, 121 do
      if not house and not st.b[i] and R.can_place(st, 'house', i) and V.near(st.valley, i, 'marsh', 1) > 0 then house = i end
    end
    if house then break end
  end
  local function run(with)
    local c = Sv.decode(Sv.encode(st))
    if with then c.b[house] = { kind = 'house', left = 0 } end
    for _, id in ipairs(P.living(c)) do c.people[id].health = 50 end
    P.month(c, Rn.new(4), { lines = {}, hunger = 0 })
    local h = 0; for _, id in ipairs(P.living(c)) do h = h + c.people[id].health end
    return h
  end
  return run(true) < run(false)
end)()"""), 'a house by the marsh makes the village less healthy'
assert ev("""(function()
  local st = fresh(17)
  local h, s
  for i = 1, 121 do
    if not st.b[i] and R.BUILD.house.place(st.valley, st, i) then
      for j = 1, 121 do
        if j ~= i and not st.b[j] and R.BUILD.smithy.place(st.valley, st, j) and math.abs(V.xy(i) - V.xy(j)) <= 1
          and math.abs(select(2, V.xy(i)) - select(2, V.xy(j))) <= 1 then h, s = i, j; break end
      end
    end
    if h then break end
  end
  local Sv = api.mod('save')
  local function run(with)
    local c = Sv.decode(Sv.encode(st))
    c.b[h] = { kind = 'house', left = 0 }
    if with then c.b[s] = { kind = 'smithy', left = 0 } end
    for _, id in ipairs(P.living(c)) do c.people[id].happy = 50; c.people[id].job = nil end
    P.month(c, Rn.new(5), { lines = {}, hunger = 0 })
    local t = 0; for _, id in ipairs(P.living(c)) do t = t + c.people[id].happy end
    return t
  end
  return run(true) < run(false)
end)()"""), 'a house next to the smithy makes people less happy'
g.no_err()

# ---------------------------------------------------------------- the screens
st = g.api.state()
# the placing panel warns of the marsh
L.execute("local st = __TEST.api.state(); st.res.wood, st.res.stone = 300, 100")
marsh_tile = next((i for i in range(1, 122) if st.b[i] is None and ev(f"R.can_place(__TEST.api.state(), 'house', {i})")
                   and ev(f"V.near(__TEST.api.state().valley, {i}, 'marsh', 1)") > 0), None)
if marsh_tile:
    g.tap_label('Build'); g.tap_label('House')
    x, y = g.api.tile_xy(marsh_tile)
    g.tap(x + 20, y + 20)
    assert any('marsh' in s for s in g.texts()), g.texts()
    g.key('back')
def to_village(g):
    for _ in range(4):
        if g.api.screen() != 'village':
            g.key('back')
    if 'Cancel' in g.texts():
        g.key('back')
    assert g.api.screen() == 'village' and 'Cancel' not in g.texts(), (g.api.screen(), g.texts())


to_village(g)
# every text on the village screen fits the width (10 px a character, the reader's wide font)
g.tap_label('Build'); g.tap_label('Storehouse')
for d in g.draw():
    assert int(d.x) + len(str(d.s)) * 10 <= 482 or str(d.s).endswith('…'), (str(d.s), int(d.x))
to_village(g)

# the tile panel names the tile, the person card names each field by it
L.execute("""
local st = __TEST.api.state()
local n = 0
for i = 1, 121 do if n < 3 and R.can_place(st, 'field', i) then st.b[i] = { kind = 'field', left = 0 }; n = n + 1 end end
for i = 1, 121 do if n < 9 and R.can_place(st, 'woodcutter', i) then st.b[i] = { kind = 'woodcutter', left = 0 }; n = n + 1 end end
for i = 1, 121 do if n < 34 and R.can_place(st, 'toolmaker', i) then st.b[i] = { kind = 'toolmaker', left = 0 }; n = n + 1 end end
for _, p in pairs(st.people) do p.job = nil end
""")
fields = [i for i in range(1, 122) if st.b[i] is not None and st.b[i].kind == 'field']
x, y = g.api.tile_xy(fields[0])
g.tap(x + 20, y + 20)
coord = ev(f"string.char(64 + ({fields[0]} - 1) % 11 + 1) .. (({fields[0]} - 1) // 11 + 1)")
assert any(coord in s for s in g.texts()), (coord, g.texts())
g.key('back')
g.tap_label('People')
adult = next(p for p in st.people.values() if p.alive and p.age >= 144)
g.tap_label(str(adult.name))
labels = [s for s in g.texts() if s.startswith('Field')]
assert len(labels) == len(set(labels)) and len(labels) >= 2, labels
assert 'More jobs' in g.texts(), g.texts()
before = set(g.texts())
g.tap_label('More jobs')
assert set(g.texts()) != before, 'the next page of jobs'
g.key('back'); g.key('back')

# event choices name people by their first name, so the labels fit
L.execute("""
local st = __TEST.api.state()
local kid, wm
for _, id in ipairs(P.living(st)) do local p = st.people[id]; if p.age < 168 and p.age >= 48 then kid = id elseif p.age >= 192 then wm = id end end
st.event = { id = 'lost_child', vars = { village = st.name, kid_id = kid, woodsman_id = wm, kid = st.people[kid].name, woodsman = st.people[wm].name } }
first_name = st.people[wm].name:match('^(%S+)'); full_name = st.people[wm].name
""")
g.api.show_event()
t = g.texts()
assert any(s.startswith('Send ' + str(ev('first_name')) + ' to') for s in t), t
assert not any(str(ev('full_name')) in s and s.startswith('Send') for s in t), t
# Back on an event with a safe choice takes it; on one without, it waits
clear(g)
L.execute("local st = __TEST.api.state(); st.event = { id = 'pedlar', vars = { village = st.name } }")
g.api.show_event()
g.key('back')
assert g.api.state().event is None and g.api.state().last_event == 'pedlar', 'Back sent the pedlar on'
clear(g)
L.execute("local st = __TEST.api.state(); st.event = { id = 'rich_harvest', vars = { village = st.name } }")
g.api.show_event()
g.key('back')
assert g.api.modal_open() and g.api.state().event is not None, 'the harvest waits for an answer'
clear(g); clear(g)

# the ledger lists who was born, died, came and left last month
L.execute("local st = __TEST.api.state(); st.report = st.report or { delta = {}, lines = {} }; st.report.people = { born = 1, died = 2, came = 0, left = 1 }")
g.tap_label('Ledger')
t = ' '.join(g.texts())
assert '1 born' in t and '2 died' in t and '1 left' in t, t
g.key('back')

# the last month's news shows before the end
for _ in range(80):
    L.execute("local st = __TEST.api.state(); for _, p in pairs(st.people) do p.health = 0; p.age = 90 * 12 end; st.event = nil")
    g.tap_label('+1 month')
    L.eval('run_timers')()
    if g.api.state().over:
        break
    clear(g); clear(g)
assert g.api.state().over == 'dead', g.api.state().over
assert g.api.modal_open(), 'the deaths are told before the end screen'
assert any('died' in s.lower() or 'sickness' in s.lower() or 'recover' in s.lower() for s in g.texts()), g.texts()
clear(g)
assert g.api.screen() == 'end', g.api.screen()
g.key('back')

# the title of a finished game, and a save that can't be read
assert g.api.screen() == 'title'
assert 'See the ending' in g.texts() and 'Continue' not in g.texts(), g.texts()
g2 = game(6)
g2.L.execute("store['village.txt'] = '{{{ not a village'")
g2.restart()
g2.tap_label('Continue')
assert g2.api.modal_open() and any('could not be read' in s for s in g2.texts()), g2.texts()

# New valley in Settings
g3 = game(7)
g3.tap_label('New valley'); clear(g3)
seed0 = g3.api.state().seed
g3.key('back')
g3.tap_label('Settings')
g3.L.execute('riverstead_seed = 8')
g3.tap_label('New valley')
assert g3.api.modal_open()
g3.api.modal_pick(1)
assert g3.api.screen() == 'village' and g3.api.state().seed != seed0

# the plain map (no layers) still shows the valley: the special spot, rock, fertile soil
g4 = game(9, layers=False)
g4.tap_label('New valley'); clear(g4)
assert not g4.api.layer_ok()
sp = g4.api.state().valley.special
plain = g4.commands()
assert plain < 900, plain
if sp:
    sx, sy = g4.api.tile_xy(sp)
    assert any(sx <= int(c.x) <= sx + 40 and sy <= int(c.y) <= sy + 40 for c in g4.circles()), 'the special spot'
st4 = g4.api.state()
marked = sum(1 for i in range(1, 122) if st4.b[i] is not None or str(st4.valley.t[i]) != 'meadow')
assert any(str(st4.valley.t[i]) in ('rock', 'fertile', 'marsh') for i in range(1, 122))
assert plain >= marked, ('every tile but a plain meadow has a mark on the plain map', plain, marked)
g4.no_err()
print('polish: all tests passed')
