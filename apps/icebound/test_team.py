"""Icebound's team (game/team.lua): six named people with roles, traits, conditions that worsen and heal,
moods and relations, deaths only after a warning, and the veteran.

  python -I apps/icebound/test_team.py
"""
import os
from collections import Counter
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
L = lua54.LuaRuntime(unpack_returned_tuples=True)
L.execute(f"package.path = [[{HERE.replace(os.sep, '/')}/?.lua;]] .. package.path")
L.execute("""
Rng = require('game.rng'); G = require('game.region')(Rng); R = require('game.rules')(Rng, G)
T = require('game.text'); TM = require('game.team')(Rng, R, T)
function fresh(seed, veteran)
  local st = { day = 1, month = 1, team = {}, next_id = 1, pace = 'steady', ration = 'normal', sup = { food = 300, fuel = 60, dogs = 12, sledges = 3, dogfood = 300 },
               weather = { kind = 'overcast', temp = -20, wind = 10, left = 3 } }
  TM.make(st, Rng.new(seed), veteran)
  return st
end
function day(st, r, opts)
  opts = opts or {}
  local rep = { lines = {}, falls = opts.falls or {}, hunger = opts.hunger or false, cold = opts.cold or false, moved = 2 }
  TM.day(st, r, rep)
  st.day = st.day + 1; st.month = st.day
  return rep
end
function stages(st, kind) local n = 0; for _, p in pairs(st.team) do if p.alive then n = n + p.cond[kind] end end; return n end
function avg_mood(st) local n, s = 0, 0; for _, p in pairs(st.team) do if p.alive then n = n + 1; s = s + p.mood end end; return s // math.max(1, n) end
""")
ev = L.eval

# ---------------------------------------------------------------- the team
for seed in range(1, 201):
    st = ev(f'fresh({seed})')
    ps = list(st.team.values())
    assert len(ps) == 6 and len({str(p.name) for p in ps}) == 6, seed
    roles = Counter(str(p.role) for p in ps)
    assert roles['navigator'] == 1 and roles['doctor'] == 1 and roles['driver'] == 1, roles
    assert all(1 <= p.lv <= 3 and p.alive for p in ps)
    rels = Counter()
    for p in ps:
        for q, v in p.rel.items():
            rels[v] += 1
    assert rels[-1] == 2 and rels[1] == 2, (seed, rels)       # one tense pair, one friendly pair (both ways)
assert ev("(function() local a, b = fresh(9), fresh(9); local s, t = {}, {}; for i = 1, 6 do s[i] = a.team[i].name .. a.team[i].trait; t[i] = b.team[i].name .. b.team[i].trait end; return table.concat(s) == table.concat(t) end)()")
vet = ev("""(function()
  local v = { name = 'Ruth', role = 'surveyor', lv = 3, trait = 'brave', mem = { 'pulled Tomas out of a crevasse' } }
  local st = fresh(12, v)
  for _, p in pairs(st.team) do if p.veteran then return p.name, p.role, p.lv, #p.mem, p.health end end
end)()""")
assert vet[0] == 'Ruth' and vet[1] == 'surveyor' and vet[2] == 4 and vet[3] >= 1 and vet[4] >= 70, vet

# ---------------------------------------------------------------- frostbite comes in deep cold and goes with rest and fuel
up = ev("""(function() local st = fresh(3); st.pace = 'hard'; st.weather = { kind = 'wind', temp = -45, wind = 40, left = 3 }
  local r = Rng.new(1); for _ = 1, 6 do day(st, r, { cold = true }) end; return stages(st, 'frostbite') end)()""")
assert up >= 3, up
down = ev("""(function() local st = fresh(3); for _, p in pairs(st.team) do p.cond.frostbite = 2 end
  st.pace = 'rest'; st.weather = { kind = 'overcast', temp = -15, wind = 5, left = 3 }
  local r = Rng.new(2); for _ = 1, 10 do day(st, r) end; return stages(st, 'frostbite') end)()""")
assert down < 12, down

# ---------------------------------------------------------------- no death without two days of warning
res = ev("""(function()
  local deaths, unwarned = 0, 0
  for seed = 1, 40 do
    local st = fresh(seed); local r = Rng.new(seed * 31)
    local warned_on = {}
    for d = 1, 50 do
      st.pace = 'hard'; st.ration = 'short'; st.weather = { kind = 'blizzard', temp = -48, wind = 50, left = 3 }
      for _, line in ipairs(TM.warnings(st)) do
        for id, p in pairs(st.team) do if p.alive and line:find(p.name, 1, true) then warned_on[id] = warned_on[id] or {}; warned_on[id][st.day] = true end end
      end
      local before = {}
      for id, p in pairs(st.team) do before[id] = p.alive end
      day(st, r, { cold = true, hunger = true })
      for id, p in pairs(st.team) do
        if before[id] and not p.alive then
          deaths = deaths + 1
          local w = warned_on[id] or {}
          if not (w[st.day - 1] and w[st.day - 2]) then unwarned = unwarned + 1 end
        end
      end
    end
  end
  return deaths, unwarned end)()""")
assert res[0] > 0 and res[1] == 0, res

# ---------------------------------------------------------------- the doctor and rest
heal = ev("""(function()
  local function run(with_doctor)
    local total = 0
    for seed = 1, 40 do
      local st = fresh(seed)
      for _, p in pairs(st.team) do p.cond.injury = 2; if p.role == 'doctor' and not with_doctor then p.alive = false end end
      st.pace = 'rest'; local r = Rng.new(seed); for _ = 1, 6 do day(st, r) end
      for _, p in pairs(st.team) do if p.role ~= 'doctor' then total = total + p.cond.injury end end
    end
    return total
  end
  return run(true), run(false) end)()""")
assert heal[0] < heal[1], heal
ex = ev("""(function() local st = fresh(4); for _, p in pairs(st.team) do p.cond.exhaustion = 2 end; st.pace = 'rest'
  local r = Rng.new(3); for _ = 1, 5 do day(st, r) end; return stages(st, 'exhaustion') end)()""")
assert ex < 12, ex

# ---------------------------------------------------------------- moods
m = ev("""(function() local a, b = fresh(5), fresh(5); a.ration = 'short'; b.ration = 'full'
  local r1, r2 = Rng.new(1), Rng.new(1); for _ = 1, 8 do day(a, r1); day(b, r2) end; return avg_mood(a), avg_mood(b) end)()""")
assert m[0] < m[1], m
loss = ev("""(function() local a, b = fresh(6), fresh(6); local r1, r2 = Rng.new(1), Rng.new(1)
  a.team[6].alive = false; TM.mourn(a, a.team[6]); b.team[6].alive = false
  return avg_mood(a), avg_mood(b) end)()""")
assert loss[0] < loss[1], loss
cheer = ev("""(function()
  local function run(trait)
    local st = fresh(7); for _, p in pairs(st.team) do if p.id ~= 1 then p.trait = 'steady' end end; st.team[1].trait = trait
    local r = Rng.new(2); for _ = 1, 8 do day(st, r) end
    local s = 0; for id, p in pairs(st.team) do if id ~= 1 then s = s + p.mood end end; return s
  end
  return run('cheerful'), run('steady') end)()""")
assert cheer[0] > cheer[1], cheer
tense = ev("""(function()
  local function run(rel)
    local st = fresh(8); st.ration = 'short'; for _, p in pairs(st.team) do p.rel = {}; p.mood = 20; p.trait = 'steady' end
    st.team[1].rel[2], st.team[2].rel[1] = rel, rel
    local r = Rng.new(4); day(st, r); return st.team[1].mood + st.team[2].mood
  end
  return run(-1), run(0) end)()""")
assert tense[0] < tense[1], tense
assert ev("(function() local st = fresh(2); local p = st.team[1]; p.mood = 20; local q = st.team[2]; q.mood = 60; return TM.refuses(p), TM.refuses(q) end)()") == (True, False)
assert str(ev("(function() local st = fresh(2); st.team[3].cond.frostbite = 3; return TM.warnings(st)[1] end)()")).find(str(ev('fresh(2).team[3].name'))) >= 0
print('team: all tests passed', {'deaths/unwarned in hard runs': res, 'heal with/without doctor': heal})
