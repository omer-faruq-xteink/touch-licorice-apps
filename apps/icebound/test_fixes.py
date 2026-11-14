"""Icebound: the final review's findings, each a test that failed first.

  python -I apps/icebound/test_fixes.py
"""
import os, sys
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
L = lua54.LuaRuntime(unpack_returned_tuples=True)
L.execute(f"package.path = [[{HERE.replace(os.sep, '/')}/?.lua;]] .. package.path")
L.execute("""
Rng = require('game.rng'); G = require('game.region')(Rng); R = require('game.rules')(Rng, G)
T = require('game.text'); TM = require('game.team')(Rng, R, T); E = require('game.events')
EL = require('game.event_list')(Rng, R, TM, T, G); S = require('game.sim')(Rng, G, R, TM, E, T, EL)
B = require('game.bots')(G, R, TM, S)
function new(seed, mission)
  for k = 0, 300 do local st = S.new(seed + k * 1000, 'normal', {}); if not mission or st.mission == mission then st.event = nil; return st end end
end
-- a flat straight corridor north of the party, everything known and calm
function corridor(st, n)
  local x, y = G.xy(st.pos)
  st.route = {}
  for k = 1, n do local j = G.idx(x, y - k); st.region.t[j] = 'flat'; st.region.up[j] = nil; st.seen[j] = true; st.route[k] = j end
  st.weather = { kind = 'clear', temp = -20, wind = 5, left = 3 }
  st.pace = 'hard'
  local copy = {}
  for k, j in ipairs(st.route) do copy[k] = j end
  return copy
end
function role_off(st, role) for _, p in pairs(st.team) do if p.role == role then p.role = 'photographer' end end end
function role_on(st, role) for _, p in pairs(st.team) do if p.role == 'cook' or p.role == 'hunter' or p.role == 'geologist' then p.role = role; return end end; st.team[6].role = role end
""")
ev = L.eval
fails = []


def check(ok, what):
    if not ok:
        fails.append(what)


# 1. a target, the pole or the goal passed in the middle of a day's march counts, and the march stops there
r1 = ev("""(function()
  local st = new(3, 'survey'); local route = corridor(st, 4); st.region.targets[1] = route[2]
  S.march(st, Rng.new(1)); return st.found[route[2]] == true end)()""")
check(r1, 'a survey point passed mid-day is found')
r1b = ev("""(function()
  local st = new(4, 'pole'); local route = corridor(st, 4); st.region.goal = route[2]
  S.march(st, Rng.new(1)); return st.phase, st.pos == route[2] end)()""")
check(r1b == ('back', True), f'the pole passed mid-day turns the expedition home and stops there: {r1b}')
r1c = ev("""(function()
  local st = new(5, 'crossing'); local route = corridor(st, 4); st.region.goal = route[2]
  S.march(st, Rng.new(1)); return st.over end)()""")
check(r1c == 'goal', f'the station passed mid-day ends the crossing: {r1c}')

# 2. turning back at once is no reward; turning back after the pole is refused
sc = ev("""(function()
  local st = new(6, 'crossing'); S.turn_back(st); st.event = nil; S.march(st, Rng.new(1))
  local a = S.score(st)
  local w = new(6, 'crossing'); w.over = 'goal'; w.day = w.par
  return st.over, a, S.score(w) end)()""")
check(sc[0] == 'back' and sc[1] < 0.4 * sc[2], f'turning back on day 1: {sc}')
far = ev("""(function()
  local st = new(6, 'crossing'); st.best_left = 2; S.turn_back(st); st.event = nil; S.march(st, Rng.new(1))
  local near = new(6, 'crossing'); S.turn_back(near); near.event = nil; S.march(near, Rng.new(1))
  return S.score(st), S.score(near) end)()""")
check(far[0] > far[1], f'turning back after coming far scores more: {far}')
tb = ev("""(function() local st = new(7, 'pole'); st.phase = 'back'; local ok = S.turn_back(st); return ok, st.turned == true end)()""")
check(tb == (False, False), f'no turning back on the way home from the pole: {tb}')

# 3. thin ice: open water beside the route ahead (a route set_route accepts) brings the event
ti = ev("""(function()
  local def; for _, d in ipairs(EL.defs) do if d.id == 'thin_ice' then def = d end end
  local st = new(8); local route = corridor(st, 3)
  local x, y = G.xy(route[1]); local side = G.idx(x < 11 and x + 1 or x - 1, y); st.region.t[side] = 'water'; st.seen[side] = true
  local ok = S.set_route(st, route)
  return ok and EL.ctx.cond(def, st) end)()""")
check(ti, 'thin ice comes with water beside the route ahead')

# 4. a broken sledge: without a mechanic its load is left; with one it is kept and mended
sl = ev("""(function()
  local a = new(9); role_off(a, 'mechanic'); local f0 = a.sup.food
  EL.ctx.fx({ break_sledge = true }, a, {}, Rng.new(1))
  local b = new(9); role_on(b, 'mechanic'); local g0 = b.sup.food
  EL.ctx.fx({ break_sledge = true }, b, {}, Rng.new(1))
  local s1 = b.sup.sledges; b.pace = 'rest'; b.route = {}; R.step(b, Rng.new(2))
  return a.sup.food < f0, b.sup.food >= g0 - 20, s1 < b.sup.sledges end)()""")
check(sl == (True, True, True), f'a broken sledge costs its load without a mechanic, is mended with one: {sl}')
pw = ev("""(function() local a = new(10); a.weather = { kind = 'clear', temp = -20, wind = 5, left = 3 }; local p3 = R.power(a)
  a.sup.sledges = 2; local p2 = R.power(a); return p2 <= p3 end)()""")
check(pw, 'losing a sledge never makes the party faster')

# 5. caches and depots say what they held
ca = ev("""(function()
  local st = new(11); local route = corridor(st, 2); st.pace = 'steady'
  st.region.caches[route[1]] = { food = 25, fuel = 4, dogfood = 10 }; st.region.caches[route[2]] = {}
  local rep = R.step(st, Rng.new(1)); local s = table.concat(rep.lines, ' | ')
  return s end)()""")
check('cache' in str(ca).lower() and '25' in str(ca) and 'empty' in str(ca).lower(), f'cache lines: {ca}')

# 7. each nunatak gives its sample and plate once
cl = ev("""(function()
  local st = new(12); role_on(st, 'geologist'); local x, y = G.xy(st.pos); st.region.t[G.idx(x < 11 and x + 1 or x - 1, y)] = 'rock'
  for d = 1, 3 do st.day = d; R.climb(st) end
  return st.extras.samples end)()""")
check(cl == 1, f'samples from three climbs of one nunatak: {cl}')

# 8. the doctor's chosen patient, once healed, no longer takes the care
tr = ev("""(function()
  local st = new(13); local healthy, sick
  for id, p in pairs(st.team) do if p.role ~= 'doctor' then if not healthy then healthy = p elseif not sick then sick = p end end end
  for _, p in pairs(st.team) do for k, _ in pairs(p.cond) do p.cond[k] = 0 end end
  sick.cond.injury = 3; st.treat = healthy.id; st.pace = 'rest'
  local healed = 0
  for k = 1, 60 do sick.cond.injury = 3; local rep = { lines = {}, falls = {}, moved = 0 }; TM.day(st, Rng.new(k), rep); if sick.cond.injury < 3 then healed = healed + 1 end end
  local base = 0
  local st2 = new(13); for _, p in pairs(st2.team) do for k, _ in pairs(p.cond) do p.cond[k] = 0 end end
  for id, p in pairs(st2.team) do if p.role == 'doctor' then p.alive = false end end
  local s2; for id, p in pairs(st2.team) do if p.alive and p.name == sick.name then s2 = p end end
  st2.pace = 'rest'
  for k = 1, 60 do s2.cond.injury = 3; TM.day(st2, Rng.new(k), { lines = {}, falls = {}, moved = 0 }); if s2.cond.injury < 3 then base = base + 1 end end
  return healed, base end)()""")
check(tr[0] > tr[1], f'care goes to the sick when the chosen patient is healthy: {tr}')

for f in fails:
    print('FAIL', f)
assert not fails, f'{len(fails)} failures'
print('fixes: all tests passed')
