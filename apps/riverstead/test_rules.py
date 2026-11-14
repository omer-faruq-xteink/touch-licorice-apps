"""Riverstead's rules (game/rules.lua): placing, yields by terrain, workers and season, construction,
eating and hunger, spoilage, storage, floods and levees, and integers kept below 2^31.

  python -I apps/riverstead/test_rules.py
"""
import os
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
L = lua54.LuaRuntime(unpack_returned_tuples=True)
L.execute(f"package.path = [[{HERE.replace(os.sep, '/')}/?.lua;]] .. package.path")
L.execute("""
Rng = require('game.rng'); V = require('game.valley')(Rng); R = require('game.rules')(Rng, V)
function person(st, skill, lv, age)
  local id = st.next_id; st.next_id = id + 1
  st.people[id] = { id = id, name = 'P' .. id, sex = 'f', age = age or 300, skill = skill, lv = lv or 1, trait = 'hardy',
                    health = 80, happy = 60, alive = true, story = {}, came = 1 }
  return id
end
function find(v, test) for i = 1, 121 do if test(i) then return i end end end
function months(st, n, r) local rep; for _ = 1, n do rep = R.produce(st, r); st.month = st.month + 1 end; return rep end
""")
R, V = L.eval('R'), L.eval('V')
person, find, months = L.eval('person'), L.eval('find'), L.eval('months')
fails = []


def check(ok, what):
    if not ok:
        fails.append(what)


def valley_with(test_fn_src, seed0=1):
    """the first valley (from seed0) where the Lua predicate holds"""
    pred = L.eval(f'function(v) {test_fn_src} end')
    for s in range(seed0, seed0 + 500):
        v = V.make(s)
        if pred(v):
            return v
    raise AssertionError('no valley for ' + test_fn_src)


def state(v):
    st = R.new_state(v)
    st.res.wood, st.res.stone, st.res.tools, st.res.coin, st.res.food = 500, 500, 50, 100, 500
    return st


def finish(st, i):
    st.b[i].left = 0


def harvest(kind_tile, st, workers):
    """a year from March: the food the field at kind_tile gives at harvest"""
    for pid in workers:
        st.people[pid].job = kind_tile
    before = st.res.food
    total = 0
    for _ in range(12):
        f0 = st.res.food
        rep = R.produce(st, L.eval('Rng.new(1)'))
        total += rep.harvest or 0
        st.month += 1
    return total


# fertile and riverside fields give more than plain meadow ones
v = valley_with("local f, m = false, false for i = 1, 121 do if v.t[i] == 'fertile' and not V.riverside(v, i) then f = true end if v.t[i] == 'meadow' and not V.riverside(v, i) and i ~= v.special then m = true end end return f and m")
yields = {}
for name, test in [('fertile', "v.t[i] == 'fertile' and not V.riverside(v, i)"), ('meadow', "v.t[i] == 'meadow' and not V.riverside(v, i) and i ~= v.special and i ~= v.camp")]:
    st = state(v)
    i = L.eval(f"function(v) for i = 1, 121 do if {test} then return i end end end")(v)
    ok, why = R.can_place(st, 'field', i)
    check(ok, f'a field on {name}: {why}')
    R.place(st, 'field', i)
    finish(st, i)
    a, b = person(st, 'farming', 1), person(st, 'farming', 1)
    yields[name] = harvest(i, st, [a, b])
check(yields['fertile'] > yields['meadow'] > 0, f'fertile beats meadow: {yields}')

v = valley_with("for i = 1, 121 do if V.riverside(v, i) and (v.t[i] == 'meadow' or v.t[i] == 'fertile') then return true end end return false")
st = state(v)
rs = L.eval("function(v) for i = 1, 121 do if V.riverside(v, i) and v.t[i] == 'meadow' then return i end end end")(v)
inland = L.eval("function(v) for i = 1, 121 do if not V.riverside(v, i) and v.t[i] == 'meadow' and V.near(v, i, 'river', 1) == 0 and i ~= v.special then return i end end end")(v)
if rs and inland:
    out = {}
    for name, i in (('riverside', rs), ('inland', inland)):
        st = state(v)
        R.place(st, 'field', i); finish(st, i)
        out[name] = harvest(i, st, [person(st, 'farming', 1), person(st, 'farming', 1)])
    check(out['riverside'] > out['inland'], f'the river helps: {out}')

# a field nobody worked in spring gives nothing at harvest
st = state(v)
R.place(st, 'field', inland); finish(st, inland)
pid = person(st, 'farming', 1)
st.month = 4      # June: past sowing
total = 0
for _ in range(8):
    if st.month >= 6:
        st.people[pid].job = inland
    rep = R.produce(st, L.eval('Rng.new(2)')); total += rep.harvest or 0; st.month += 1
check(total == 0, f'no spring work, no harvest: {total}')

# placement rules
v = valley_with("return v.special ~= nil")
st = state(v)
land = L.eval("function(v) for i = 1, 121 do if v.t[i] == 'meadow' and i ~= v.special and not V.riverside(v, i) and V.near(v, i, 'forest', 1) == 0 and V.near(v, i, 'rock', 1) == 0 then return i end end end")(v)
water = L.eval("function(v) for i = 1, 121 do if v.t[i] == 'river' then return i end end end")(v)
check(not R.can_place(st, 'mill', land)[0], 'a mill only on the river')
check(R.can_place(st, 'mill', water)[0], 'a mill on the river')
check(not R.can_place(st, 'shrine', land)[0], 'a shrine only on the special spot')
check(R.can_place(st, 'shrine', v.special)[0], 'a shrine on the special spot')
check(not R.can_place(st, 'woodcutter', land)[0], 'a woodcutter needs forest')
check(not R.can_place(st, 'field', water)[0], 'no field in the river')
check(not R.can_place(st, 'tradingpost', land)[0], 'a trading post needs a market')
R.place(st, 'market', land); finish(st, land)
other = L.eval("function(v, a) for i = 1, 121 do if v.t[i] == 'meadow' and i ~= a and i ~= v.special then return i end end end")(v, land)
check(R.can_place(st, 'tradingpost', other)[0], 'a trading post once the market stands')
check(not R.can_place(st, 'house', land)[0], 'a tile holds one building')

# Review focus 3: exactly enough leaves 0; hunger never goes negative; demolishing frees and refunds nothing
st = state(v)
cost = R.BUILD['house'].cost
st.res.wood, st.res.stone, st.res.tools, st.res.coin = cost.wood or 0, cost.stone or 0, cost.tools or 0, cost.coin or 0
check(R.can_place(st, 'house', other)[0], 'exactly enough is enough')
R.place(st, 'house', other)
check(st.res.wood == 0 and st.res.stone == 0, (st.res.wood, st.res.stone))
check(not R.can_place(st, 'house', land)[0], 'and then not enough')
st = state(v)
st.res.food = 3
for _ in range(10):
    person(st, 'farming', 1)
rep = R.produce(st, L.eval('Rng.new(3)'))
check(st.res.food == 0 and rep.hunger > 0, (st.res.food, rep.hunger))
st = state(v)
R.place(st, 'field', other); finish(st, other)
pid = person(st, 'farming', 1); st.people[pid].job = other
wood = st.res.wood
R.demolish(st, other)
check(st.b[other] is None and st.people[pid].job is None and st.res.wood == wood, 'demolish frees and refunds nothing')

# construction: builders shorten it; nothing happens without one
st = state(v)
R.place(st, 'chapel', other)
left = st.b[other].left
R.produce(st, L.eval('Rng.new(4)'))
check(st.b[other].left == left, 'no builder, no progress')
b = person(st, 'building', 1); st.people[b].job = 'build'
R.produce(st, L.eval('Rng.new(4)'))
check(st.b[other].left < left, 'a builder makes progress')

# spoilage is lower with a storehouse; storage caps
st1, st2 = state(v), state(v)
st1.res.food = st2.res.food = 180
sh = L.eval("function(v, a) for i = 1, 121 do if v.t[i] == 'meadow' and i ~= a and i ~= v.special then return i end end end")(v, other)
R.place(st2, 'storehouse', sh); finish(st2, sh); st2.res.food = 180
R.produce(st1, L.eval('Rng.new(5)')); R.produce(st2, L.eval('Rng.new(5)'))
check(st2.res.food > st1.res.food, f'spoilage: {st1.res.food} vs {st2.res.food}')
st = state(v)
st.res.wood = 10000
R.produce(st, L.eval('Rng.new(5)'))
check(st.res.wood <= R.capacity(st), f'storage cap: {st.res.wood}')

# floods never hit a tile behind a levee
for seed in range(1, 200):
    v = V.make(seed)
    st = state(v)
    rsides = [i for i in range(1, 122) if V.riverside(v, i) and v.t[i] in ('meadow', 'fertile')]
    if len(rsides) < 3:
        continue
    R.place(st, 'levee', rsides[0]); finish(st, rsides[0])
    hit = list(R.flood(st, L.eval(f'Rng.new({seed})')).values())
    lx, ly = V.xy(rsides[0])
    for i in hit:
        x, y = V.xy(i)
        check(max(abs(x - lx), abs(y - ly)) > 2, f'seed {seed}: a flood behind the levee at {i}')
        check(V.riverside(v, i), 'floods only on the riverside')

# 120 months of busy play: every number stays below 2^31
st = state(V.make(3))
for k in range(12):
    person(st, ['farming', 'wood', 'building', 'crafting'][k % 4], 3)
r = L.eval('Rng.new(9)')
for m in range(120):
    for i in range(1, 122):
        for kind in ('field', 'woodcutter', 'quarry', 'house', 'toolmaker'):
            if R.can_place(st, kind, i)[0]:
                R.place(st, kind, i); finish(st, i); break
        if st.b[i] is not None:
            break
    rep = R.produce(st, r)
    st.month += 1
    for k, val in st.res.items():
        check(0 <= val < 2 ** 31, (m, k, val))

for f in fails[:12]:
    print('FAIL', f)
assert not fails, f'{len(fails)} failures'
print('rules: all tests passed', yields)
