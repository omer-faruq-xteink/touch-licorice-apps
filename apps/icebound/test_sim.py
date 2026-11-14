"""Icebound's simulation (game/sim.lua): a new expedition, the day, the missions, the actions (depot, dog,
rescue, turn back, climb), the warnings, and the end with its score.

  python -I apps/icebound/test_sim.py
"""
import os
from collections import Counter
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
L = lua54.LuaRuntime(unpack_returned_tuples=True)
L.execute(f"package.path = [[{HERE.replace(os.sep, '/')}/?.lua;]] .. package.path")
L.execute("""
Rng = require('game.rng'); G = require('game.region')(Rng); R = require('game.rules')(Rng, G)
T = require('game.text'); TM = require('game.team')(Rng, R, T); E = require('game.events')
EL = require('game.event_list')(Rng, R, TM, T, G); S = require('game.sim')(Rng, G, R, TM, E, T, EL)
Sv = require('game.save')
function answer(st, r) if st.event then local k = S.back_choice(st) or 1; S.answer(st, k, r) end end
-- walk towards the current target by the cheapest path over all passable tiles, plenty of supplies
function walk(st, r, max_days)
  st.days = 400
  for _ = 1, max_days or 300 do
    if st.over then break end
    answer(st, r)
    st.sup.food, st.sup.fuel, st.sup.dogfood = 500, 200, 500
    for _, p in pairs(st.team) do for k, _ in pairs(p.cond) do p.cond[k] = 0 end; p.mood = 70 end
    local t = S.target(st)
    if t and t ~= st.pos then
      local p = G.path(st.region, st.pos, t, function(i) return R.cost(st, i) end, nil)
      if p then table.remove(p, 1); st.route = p end
    end
    st.pace = 'steady'
    S.march(st, r)
    S.morning(st, r)
  end
  return st
end
function new(seed, mission, opts)
  for k = 0, 200 do
    local st = S.new(seed + k * 1000, 'normal', opts or {})
    if not mission or st.mission == mission then return st end
  end
end
""")
ev = L.eval
S = L.eval('S')

# ---------------------------------------------------------------- a new expedition
ms = Counter()
for seed in range(1, 201):
    st = S.new(seed, 'normal', L.table_from({'last_mission': 'pole'}))
    assert st.mission != 'pole', seed
    ms[str(S.new(seed, 'normal', L.table_from({})).mission)] += 1
    assert st.day == 1 and st.month == 1 and st.days >= 56 and st.days >= st.par + 12 and len(list(st.team.values())) == 6
    assert st.seen[st.pos] and st.season in ('early', 'late')
assert set(ms) == {'crossing', 'pole', 'lost', 'survey'}, ms
assert S.new(5, 'hard', L.table_from({})).sup.food < S.new(5, 'normal', L.table_from({})).sup.food < S.new(5, 'easy', L.table_from({})).sup.food
assert ev("S.new(9, 'normal', {}).region.t[1] == S.new(9, 'normal', {}).region.t[1] and S.new(9, 'normal', {}).mission == S.new(9, 'normal', {}).mission")

# ---------------------------------------------------------------- the missions
for mission in ('crossing', 'pole', 'lost', 'survey'):
    wins = 0
    for seed in range(1, 6):
        st = ev(f"walk(new({seed}, '{mission}'), Rng.new({seed}))")
        assert st.over, (mission, seed, st.day)
        wins += st.over == 'goal'
        if st.over == 'goal' and mission == 'pole':
            assert st.phase == 'back' and st.pos == st.region.start
        if st.over == 'goal' and mission in ('lost', 'survey'):
            assert all(st.found[t] for t in st.region.targets.values())
    assert wins >= 4, (mission, wins)

# ---------------------------------------------------------------- turn back, rescue, the season
st = ev("""(function() local st = new(21, 'crossing'); st.days = 400
  local p = G.path(st.region, st.pos, G.idx(select(1, G.xy(st.pos)), 22), function(i) return R.cost(st, i) end, nil)
  table.remove(p, 1); st.route = p; for _ = 1, 4 do answer(st, Rng.new(1)); S.march(st, Rng.new(2)) end
  S.turn_back(st); return walk(st, Rng.new(3)) end)()""")
assert st.over == 'back' and st.pos == st.region.start, (st.over, st.pos)
st = ev("""(function() local st = new(22); st.days = 400; S.call_rescue(st); assert(st.radio == 'called')
  local ok = S.call_rescue(st); assert(not ok); st.pace = 'rest'
  for _ = 1, 10 do if st.over then break end; st.event = nil; S.march(st, Rng.new(4)) end; return st end)()""")
assert st.over == 'rescued' and st.day <= 8, (st.over, st.day)
assert ev("""(function() local st = new(23); st.days = 3; st.pace = 'rest'
  for _ = 1, 5 do st.event = nil; S.march(st, Rng.new(1)) end; return st.over end)()""") == 'rescued'
assert ev("""(function() local st = new(23); st.days = 3; st.pace = 'rest'; st.radio = 'used'
  for _ = 1, 5 do st.event = nil; S.march(st, Rng.new(1)) end; return st.over end)()""") == 'lost'
assert ev("""(function() local st = new(24); for _, p in pairs(st.team) do p.alive = false end; st.event = nil; S.march(st, Rng.new(1)); return st.over end)()""") == 'lost'

# ---------------------------------------------------------------- the end: once, follow-ups dropped, stable over a reload (Review Focus 3)
r3 = ev("""(function() local st = new(25); st.days = 1; st.pace = 'rest'
  st.pending = { { at = 5, id = 'dog_returns', vars = {} } }; st.event = nil
  S.march(st, Rng.new(1)); local over1, pend = st.over, #st.pending
  local e1 = S.ending(st); local c1 = S.chronicle_entry(st)
  local back = Sv.decode(Sv.encode(st)); local e2 = S.ending(back); local c2 = S.chronicle_entry(back)
  local day = st.day; S.march(st, Rng.new(2)); S.morning(st, Rng.new(3))
  return over1, pend, e1.score == e2.score and e1.title == e2.title and c1.score == c2.score, st.day == day and st.event == nil end)()""")
assert r3[0] and r3[1] == 0 and r3[2] and r3[3], r3

# ---------------------------------------------------------------- score
sc = ev("""(function() local a = new(26); local b = new(26); a.over, b.over = 'goal', 'goal'
  b.team[1].alive = false; b.team[2].alive = false
  local c = new(26); c.over = 'goal'; c.day = 50; a.day = 20
  return S.score(a), S.score(b), S.score(c) end)()""")
assert sc[0] > sc[1] and sc[0] > sc[2], sc
lv = ev("""(function() local a = new(27); a.over = 'goal'; a.day = a.par; local b = new(27); b.over = 'goal'; b.day = b.par
  for k = 1, 3 do b.team[k].alive = false end; return S.ending(a).level, S.ending(b).level end)()""")
assert lv[0] == 1 and lv[1] == 3, lv
slow = ev("(function() local a = new(27); a.over = 'goal'; a.day = a.par + 5; return S.ending(a).level end)()")
assert slow == 2, ('slower than par is not the best ending', slow)

# ---------------------------------------------------------------- actions
d = ev("""(function() local st = new(28, 'pole'); local f = st.sup.food; local ok = S.leave_depot(st)
  return ok, st.sup.food < f, st.depots[st.pos] ~= nil end)()""")
assert d == (True, True, True), d
assert not ev("(function() local st = new(28, 'crossing'); return (S.leave_depot(st)) end)()")
k = ev("(function() local st = new(29); local d, f = st.sup.dogs, st.sup.dogfood; S.kill_dog(st); return st.sup.dogs == d - 1 and st.sup.dogfood > f end)()")
assert k
sr = ev("""(function() local st = new(30); local x, y = G.xy(st.pos)
  local ok1 = S.set_route(st, { G.idx(x, y - 1), G.idx(x, y - 2) })
  local ok2 = S.set_route(st, { G.idx(x, y - 2) })
  st.seen[G.idx(x, y - 9)] = nil
  local ok3 = S.set_route(st, { G.idx(x, y - 9) })
  return ok1, ok2, ok3, #st.route end)()""")
assert sr[1] is False and sr[2] is False, sr

# re-setting the same next step keeps the way already made into a slow tile
kp = ev("""(function() local st = new(33); local x, y = G.xy(st.pos); local n = G.idx(x, y - 1)
  st.region.t[n] = 'ridge'; st.seen[n] = true; st.progress = 7; st.route = { n }
  S.set_route(st, { n }); local kept = st.progress
  local m = G.idx(math.min(11, x + 1), y - 1); st.region.t[m] = 'flat'; st.seen[m] = true
  S.set_route(st, { m }); return kept, st.progress end)()""")
assert kp == (7, 0), kp

# ---------------------------------------------------------------- warnings
w = ev("""(function() local st = new(31); st.days = 20; st.day = 12; st.month = 12; return table.concat(S.warnings(st), ' | ') end)()""")
assert 'season' in str(w), w
w2 = ev("""(function() local st = new(31); st.day = 5; st.month = 5; return table.concat(S.warnings(st), ' | ') end)()""")
assert 'season' not in str(w2), w2
w3 = ev("""(function() local st = new(32); st.sup.food = 10; return table.concat(S.warnings(st), ' | ') end)()""")
assert 'Food' in str(w3), w3
print('sim: all tests passed', dict(ms))
