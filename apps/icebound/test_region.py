"""Icebound's region (game/region.lua): an 11 x 28 polar map from a seed, its terrain mix by character, the
mission's targets, and the path search.

  python -I apps/icebound/test_region.py
"""
import os, time
from collections import Counter
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
L = lua54.LuaRuntime(unpack_returned_tuples=True)
L.execute(f"package.path = [[{HERE.replace(os.sep, '/')}/?.lua;]] .. package.path")
L.execute("""
Rng = require('game.rng'); G = require('game.region')(Rng)
function one(i) return 1 end
function cost(reg) return function(i) if G.passable(reg, nil, i) then return 1 end end end
function sig(reg)
  local s = {}
  for i = 1, reg.w * reg.h do s[#s + 1] = reg.t[i] end
  return table.concat(s, ',') .. '|' .. reg.start .. '|' .. reg.goal .. '|' .. table.concat(reg.targets, ',')
end
""")
G = L.eval('G')
sig, cost = L.eval('sig'), L.eval('cost')

missions = ['crossing', 'pole', 'lost', 'survey']
SIGNATURE = {'coast': 'water', 'plateau': 'sastrugi', 'glacier': 'crevasse', 'pack': 'ridge'}
chars = Counter()
mix = {c: Counter() for c in SIGNATURE}
t0 = time.perf_counter()
for m in missions:
    for seed in range(1, 1001):
        reg = G.make(seed, m)
        ok, why = G.check(reg)
        assert ok, (m, seed, why)
        assert reg.mission == m and reg.w == 11 and reg.h == 28
        chars[reg.char] += 1
        for i in range(1, 309):
            mix[reg.char][str(reg.t[i])] += 1
        if seed <= 20:
            assert sig(reg) == sig(G.make(seed, m)), 'deterministic'
        # targets as the mission says
        ty = [G.xy(t)[1] for t in reg.targets.values()]
        if m == 'crossing':
            assert G.xy(reg.start)[1] >= 26 and G.xy(reg.goal)[1] <= 2, (G.xy(reg.start), G.xy(reg.goal))
        elif m == 'pole':
            assert G.xy(reg.start)[1] >= 26 and 3 <= G.xy(reg.goal)[1] <= 6
        elif m == 'lost':
            assert len(ty) == 1 and 4 <= ty[0] <= 14 and len(list(reg.cairns.values())) >= 2
        else:
            assert len(ty) == 4
            xs = {G.xy(t)[0] for t in reg.targets.values()}
            assert xs <= {1, 2} or xs <= {10, 11}, xs
        for t in list(reg.targets.values()) + [reg.start, reg.goal]:
            assert G.passable(reg, None, t), (m, seed, 'target on impassable')
t1 = time.perf_counter()
L.execute("for _, m in ipairs(G.MISSIONS) do for s = 1, 1000 do G.make(s, m) end end")
dt = time.perf_counter() - t1                 # the generator alone, without Python reading every tile back
assert set(chars) == set(SIGNATURE), chars
for c, terr in SIGNATURE.items():
    order = [k for k, _ in mix[c].most_common() if k != 'flat']
    assert order[0] == terr, (c, mix[c].most_common(4))
assert dt < 12, f'4000 regions took {dt:.1f} s'          # 1000 per mission: under 3 s each

# the path search: finds what the check found, and nil when the goal is walled off
reg = G.make(7, 'crossing')
p = G.path(reg, reg.start, reg.goal, cost(reg), None)
assert p and p[1] == reg.start and p[len(p)] == reg.goal, 'a path from start to goal'
for k in range(1, len(p)):
    a, b = G.xy(p[k]), G.xy(p[k + 1])
    assert max(abs(a[0] - b[0]), abs(a[1] - b[1])) == 1, 'steps are adjacent'
    assert G.passable(reg, None, p[k + 1])
L.execute("""
walled = G.make(7, 'crossing')
local gx, gy = G.xy(walled.goal)
for _, j in ipairs(G.around(walled.goal)) do walled.t[j] = 'rock' end
""")
w = L.eval('walled')
assert G.path(w, w.start, w.goal, cost(w), None) is None, 'no path through rock'
assert not G.check(w)[0]
# with `known`, never through an unknown tile
L.execute("""
known = {}
local reg = G.make(7, 'crossing')
for i = 1, 308 do local x, y = G.xy(i); if x <= 6 then known[i] = true end end
kreg = reg
""")
kreg, known = L.eval('kreg'), L.eval('known')
if known[kreg.start] and known[kreg.goal]:
    kp = G.path(kreg, kreg.start, kreg.goal, cost(kreg), known)
    if kp:
        assert all(known[i] for i in kp.values()), 'only known tiles'
assert len(list(G.around(1).values())) == 3 and len(list(G.around(G.idx(5, 5)).values())) == 8
print(f'region: all tests passed ({dt:.1f} s for 4000 regions; chars {dict(chars)})')
