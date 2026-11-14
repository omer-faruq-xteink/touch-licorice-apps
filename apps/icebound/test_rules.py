"""Icebound's rules (game/rules.lua): travel by terrain, pace, weather, dogs and sledges; eating and fuel;
sight; weather spells; depots and caches; and what each role does.

  python -I apps/icebound/test_rules.py
"""
import os
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
L = lua54.LuaRuntime(unpack_returned_tuples=True)
L.execute(f"package.path = [[{HERE.replace(os.sep, '/')}/?.lua;]] .. package.path")
L.execute("""
Rng = require('game.rng'); G = require('game.region')(Rng); R = require('game.rules')(Rng, G)
-- a bare state on a hand-made flat region, with a team of the given roles (level 3)
function bare(roles, terrain)
  local reg = G.make(5, 'crossing')
  for i = 1, 308 do reg.t[i] = terrain or 'flat'; reg.up[i] = nil end
  reg.caches = {}
  local st = { day = 1, month = 1, days = 60, diff = 'normal', season = 'early', region = reg, pos = G.idx(6, 28), route = {},
               seen = {}, frozen = {}, pace = 'steady', ration = 'normal', progress = 0,
               sup = { food = 300, dogfood = 300, fuel = 60, dogs = 12, sledges = 3 }, depots = {}, team = {}, next_id = 1,
               weather = { kind = 'overcast', temp = -20, wind = 10, left = 3 }, flags = {}, extras = { samples = 0, plates = 0 },
               broken = 0, photo = {} }
  for _, role in ipairs(roles or { 'navigator', 'doctor', 'driver', 'cook', 'mechanic', 'surveyor' }) do
    st.team[st.next_id] = { id = st.next_id, name = role, role = role, lv = 3, health = 90, mood = 60, alive = true,
                            cond = { frostbite = 0, snowblind = 0, exhaustion = 0, injury = 0, sickness = 0 }, rel = {}, mem = {} }
    st.next_id = st.next_id + 1
  end
  return st
end
-- a straight route north from pos, n tiles
function north(st, n)
  local x, y = G.xy(st.pos)
  st.route = {}
  for k = 1, n do st.route[k] = G.idx(x, y - k) end
end
function moved_in_a_day(st) north(st, 10); local rep = R.step(st, Rng.new(3)); return rep.moved end
""")
ev = L.eval

# ---------------------------------------------------------------- travel
m = ev("moved_in_a_day(bare())")
assert 2 <= m <= 3, ('steady on flat', m)
assert ev("(function() local s = bare(); s.pace = 'hard'; return moved_in_a_day(s) end)()") > m or \
    ev("(function() local s = bare(); s.pace = 'hard'; north(s, 10); R.step(s, Rng.new(3)); return s.progress end)()") > 0
assert ev("(function() local s = bare(); s.pace = 'rest'; return moved_in_a_day(s) end)()") == 0
assert ev("(function() local s = bare(); s.weather = { kind = 'whiteout', temp = -30, wind = 40, left = 3 }; return moved_in_a_day(s) end)()") == 0
# man-hauling: no dogs, no sledges, still moving within two days (Review Focus 4)
assert ev("""(function() local s = bare(); s.sup.dogs = 0; s.sup.sledges = 0; north(s, 10)
  R.step(s, Rng.new(1)); s.weather = { kind = 'overcast', temp = -20, wind = 10, left = 3 }; R.step(s, Rng.new(2)); return G.xy(s.pos) end)()""") is not None
assert ev("""(function() local s = bare(); s.sup.dogs = 0; s.sup.sledges = 0; north(s, 10); local y0 = select(2, G.xy(s.pos))
  for k = 1, 2 do s.weather = { kind = 'overcast', temp = -20, wind = 10, left = 3 }; R.step(s, Rng.new(k)) end
  return y0 - select(2, G.xy(s.pos)) end)()""") >= 1, 'man-hauling moves'
# slower terrain moves fewer tiles
assert ev("moved_in_a_day(bare(nil, 'ridge'))") < m and ev("moved_in_a_day(bare(nil, 'sastrugi'))") <= m

# ---------------------------------------------------------------- consumption, never below zero (Review Focus 4)
d = ev("""(function() local s = bare(); local f0 = s.sup.food; s.ration = 'normal'; R.step(s, Rng.new(1)); local n = f0 - s.sup.food
  local t = bare(); t.ration = 'short'; R.step(t, Rng.new(1)); local sh = 300 - t.sup.food
  local u = bare(); u.ration = 'full'; R.step(u, Rng.new(1)); return n, sh, 300 - u.sup.food end)()""")
normal, short, full = d
assert short < normal < full, d
assert ev("""(function() local s = bare(); s.weather.temp = -45; local w = bare(); w.weather.temp = -15
  R.step(s, Rng.new(1)); R.step(w, Rng.new(1)); return (60 - s.sup.fuel) > (60 - w.sup.fuel) end)()"""), 'more fuel in deep cold'
z = ev("""(function() local s = bare(); s.sup.food, s.sup.fuel, s.sup.dogfood = 3, 0, 1
  local rep = R.step(s, Rng.new(1)); return s.sup.food, s.sup.fuel, s.sup.dogfood, rep.delta.food, rep.hunger, rep.cold end)()""")
assert z[0] == 0 and z[1] == 0 and z[2] == 0 and z[3] == -3 and z[4] and z[5], z

# ---------------------------------------------------------------- impassable tiles on the route (Review Focus 2)
r = ev("""(function() local s = bare(); local x, y = G.xy(s.pos); s.region.t[G.idx(x, y - 2)] = 'water'
  north(s, 5); local rep = R.step(s, Rng.new(1)); return select(2, G.xy(s.pos)), #s.route, #rep.lines end)()""")
assert r[0] == 27 and r[1] == 0 and r[2] >= 1, r
bad = ev("""(function()
  local bad = 0
  for k = 1, 2000 do
    local s = bare(); local rr = Rng.new(k)
    for i = 1, 308 do local q = rr:int(1, 100); s.region.t[i] = q <= 15 and 'water' or (q <= 22 and 'rock' or 'flat') end
    s.region.t[s.pos] = 'flat'
    local x, y = G.xy(s.pos); s.route = {}
    for j = 1, 6 do x = math.max(1, math.min(11, x + rr:int(-1, 1))); y = y - 1; s.route[j] = G.idx(x, y) end
    s.pace = 'hard'; R.step(s, rr)
    local t = s.region.t[s.pos]; if t == 'water' or t == 'rock' then bad = bad + 1 end
  end
  return bad end)()""")
assert bad == 0, bad

# ---------------------------------------------------------------- sight
s3 = ev("""(function() local s = bare({ 'doctor' }); s.weather.kind = 'clear'; return R.sight(s) end)()""")
assert s3 == 3
assert ev("(function() local s = bare({ 'doctor' }); s.weather.kind = 'blizzard'; return R.sight(s) end)()") == 1
assert ev("(function() local s = bare({ 'doctor' }); s.weather.kind = 'overcast'; return R.sight(s) end)()") == 2
assert ev("(function() local s = bare({ 'navigator' }); s.weather.kind = 'overcast'; return R.sight(s) end)()") == 3
n = ev("""(function() local s = bare({ 'doctor' }); s.weather.kind = 'overcast'; s.pos = G.idx(6, 14); R.reveal(s)
  local n, far = 0, false
  for i, _ in pairs(s.seen) do n = n + 1; local x, y = G.xy(i); if math.max(math.abs(x - 6), math.abs(y - 14)) > 2 then far = true end end
  return n, far end)()""")
assert n[0] == 25 and not n[1], n
c = ev("""(function() local s = bare({ 'doctor', 'geologist' }); s.pos = G.idx(6, 14); s.region.t[G.idx(7, 14)] = 'rock'
  local ok = R.climb(s); local n = 0; for _ in pairs(s.seen) do n = n + 1 end
  local t = bare(); t.pos = G.idx(6, 14); local ok2 = R.climb(t)
  return ok, n, ok2, s.extras.samples end)()""")
assert c[0] and c[1] >= 70 and not c[2] and c[3] == 1, c

# ---------------------------------------------------------------- weather
w = ev("""(function() local s = bare(); local runs, prev, len, short, temps = 0, nil, 0, 0, {}
  for d = 1, 500 do
    s.day = d; s.month = d; R.weather_next(s, Rng.new(d * 7))
    local k = s.weather.kind
    if k == prev then len = len + 1 else if prev and len == 1 then short = short + 1 end; prev, len = k, 1 end
  end
  local a, b = 0, 0
  local t = bare()
  for d = 1, 60 do t.day = d; t.month = d; R.weather_next(t, Rng.new(d)); if d <= 20 then a = a + t.weather.temp elseif d > 40 then b = b + t.weather.temp end end
  return short, a // 20, b // 20 end)()""")
assert w[0] == 0, ('1-day spells', w)
assert w[2] < w[1], ('the cold deepens', w)
fc = ev("""(function() local seen = 0
  for k = 1, 300 do
    local s = bare(); s.weather = { kind = 'clear', temp = -20, wind = 5, left = 2, next = 'blizzard' }
    R.weather_next(s, Rng.new(k)); if s.forecast == nil then return false end
    local t = bare({ 'doctor' }); t.weather = { kind = 'clear', temp = -20, wind = 5, left = 2, next = 'blizzard' }
    R.weather_next(t, Rng.new(k)); if t.forecast ~= nil then return false end
    seen = seen + 1
  end
  return seen > 0 end)()""")
assert fc, 'a navigator forecasts the coming blizzard; nobody else does'

# ---------------------------------------------------------------- depots and caches
dp = ev("""(function() local s = bare(); R.leave_depot(s, { food = 50, fuel = 10, dogfood = 40 })
  local a = s.sup.food; local d = s.depots[s.pos]
  local got = R.take(s, s.pos)
  return a, d.food, s.sup.food, s.depots[s.pos] == nil, got end)()""")
assert dp[0] == 250 and dp[1] == 50 and dp[2] == 300 and dp[3] and dp[4], dp
assert not ev("(function() local s = bare(); s.region.caches[s.pos] = {}; local f = s.sup.food; R.take(s, s.pos); return s.sup.food ~= f end)()")

# ---------------------------------------------------------------- the roles
cook = ev("""(function() local a = bare({ 'doctor', 'cook' }); local b = bare({ 'doctor', 'surveyor' })
  for i = 1, 6 do a.team[10 + i] = { role = 'x', alive = true, lv = 1, cond = {}, rel = {}, mem = {} }; b.team[10 + i] = a.team[10 + i] end
  R.step(a, Rng.new(1)); R.step(b, Rng.new(1)); return 300 - a.sup.food, 300 - b.sup.food end)()""")
assert cook[0] < cook[1], cook
falls = ev("""(function() local with, without = 0, 0
  for k = 1, 400 do
    local a = bare({ 'doctor', 'surveyor' }, 'crevasse'); north(a, 6); with = with + #R.step(a, Rng.new(k)).falls
    local b = bare({ 'doctor', 'cook' }, 'crevasse'); north(b, 6); without = without + #R.step(b, Rng.new(k)).falls
  end
  return with, without end)()""")
assert falls[1] > 0 and falls[0] < falls[1], falls
seal = ev("""(function() local a = bare({ 'doctor', 'hunter' }); a.pace = 'rest'; local x, y = G.xy(a.pos); a.region.t[G.idx(x, y - 1)] = 'water'
  local f = a.sup.food; R.step(a, Rng.new(1)); local b = bare({ 'doctor', 'cook' }); b.pace = 'rest'; b.region.t[G.idx(x, y - 1)] = 'water'
  R.step(b, Rng.new(1)); return a.sup.food - b.sup.food end)()""")
assert seal > 0, seal
mend = ev("""(function() local a = bare({ 'doctor', 'mechanic' }); a.sup.sledges, a.broken, a.pace = 2, 1, 'rest'; R.step(a, Rng.new(1))
  local b = bare({ 'doctor', 'cook' }); b.sup.sledges, b.broken, b.pace = 2, 1, 'rest'; R.step(b, Rng.new(1))
  return a.sup.sledges, b.sup.sledges end)()""")
assert mend[0] == 3 and mend[1] == 2, mend

# ---------------------------------------------------------------- integers stay below 2^31
big = ev("""(function() local m = 0
  for k = 1, 100 do local s = bare(); for d = 1, 120 do s.day = d; s.month = d; north(s, 3); s.pos = G.idx(6, 28); R.step(s, Rng.new(k * 1000 + d))
    for _, v in pairs(s.sup) do if math.abs(v) > m then m = math.abs(v) end end
    if math.abs(s.weather.temp) > m then m = math.abs(s.weather.temp) end end end
  return m end)()""")
assert big < 2 ** 31, big
print('rules: all tests passed', {'steady flat': m, 'eat short/normal/full': d, 'falls with/without surveyor': falls})
