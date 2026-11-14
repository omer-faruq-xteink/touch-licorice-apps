"""Riverstead's villagers (game/people.lua): the founding families, a month of their lives (aging, health,
happiness, marriage, births, deaths, leaving), skills, and assigning work.

  python -I apps/riverstead/test_people.py
"""
import os
from collections import Counter
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
L = lua54.LuaRuntime(unpack_returned_tuples=True)
L.execute(f"package.path = [[{HERE.replace(os.sep, '/')}/?.lua;]] .. package.path")
L.execute("""
Rng = require('game.rng'); V = require('game.valley')(Rng); R = require('game.rules')(Rng, V)
T = require('game.text'); P = require('game.people')(Rng, R, T)
function fresh(seed)
  local st = R.new_state(V.make(seed))
  st.res.food, st.res.wood, st.res.stone, st.res.tools = 400, 400, 200, 20
  P.founders(st, Rng.new(seed))
  return st
end
-- n houses on open land
function houses(st, n)
  local v = st.valley
  for i = 1, 121 do
    if n > 0 and R.can_place(st, 'house', i) then R.place(st, 'house', i); st.b[i].left = 0; n = n - 1 end
  end
end
function live(st, months, r, feed)
  for _ = 1, months do
    if feed then st.res.food = 400 end
    local rep = { lines = {}, hunger = 0 }
    if not feed then rep.hunger = 10 end
    P.month(st, r, rep)
    st.month = st.month + 1
  end
end
""")
P, fresh, houses, live = L.eval('P'), L.eval('fresh'), L.eval('houses'), L.eval('live')
Rng = L.eval('Rng')


def people(st):
    return [p for p in st.people.values()]


# the founders
for seed in range(1, 51):
    st = fresh(seed)
    ps = people(st)
    assert 10 <= len(ps) <= 14, (seed, len(ps))
    skills = Counter(p.skill for p in ps)
    assert skills['farming'] >= 1 and skills['wood'] >= 1 and skills['building'] >= 1, (seed, skills)
    assert all(p.alive and 0 <= p.health <= 100 and 0 <= p.happy <= 100 for p in ps)
    assert len({p.name for p in ps}) == len(ps), 'names are unique'
    assert len([p for p in ps if p.spouse]) >= 4, 'families have couples'
assert [p.name for p in people(fresh(5))] == [p.name for p in people(fresh(5))], 'deterministic'

# ten well-fed years with houses: the village grows, marries, has children, loses its old
grew = married = born_ok = old_died = 0
for seed in range(1, 51):
    st = fresh(seed)
    start = len(people(st))
    houses(st, 8)
    before_ids = {p.id for p in people(st)}
    singles_before = {p.id for p in people(st) if not p.spouse}
    live(st, 120, Rng.new(seed), True)
    alive = [p for p in people(st) if p.alive and not p.gone]
    if len(alive) > start:
        grew += 1
    if any(p.spouse and p.id in singles_before for p in people(st)):
        married += 1
    kids = [p for p in people(st) if p.id not in before_ids and p.mother]
    if kids and all(p.name.split()[-1] == st.people[p.father].name.split()[-1] for p in kids if p.father):
        born_ok += 1
    if any(not p.alive and p.age >= 60 * 12 for p in people(st)):
        old_died += 1
assert grew >= 35 and married >= 20 and born_ok >= 35 and old_died >= 5, (grew, married, born_ok, old_died)

# no houses, no births
st = fresh(9)
ids = {p.id for p in people(st)}
live(st, 36, Rng.new(9), True)
assert not [p for p in people(st) if p.id not in ids and p.mother], 'born without a house'

# hunger: health falls and someone dies
st = fresh(11)
h0 = sum(p.health for p in people(st))
live(st, 6, Rng.new(11), False)
assert sum(p.health for p in people(st) if p.alive) < h0
assert any(not p.alive for p in people(st)), 'nobody died of six months of hunger'

# unhappy people leave
st = fresh(13)
victim = people(st)[0]
for _ in range(6):
    victim.happy = 5
    live(st, 1, Rng.new(13), True)
    victim.happy = 5
assert victim.gone, 'unhappy for months and still here'

# auto-assign: farmers to fields first, builders kept while something is being built
L.execute("""
st = fresh(17)
houses(st, 2)
local v = st.valley
local placed = 0
for i = 1, 121 do
  if placed < 2 and R.can_place(st, 'field', i) then R.place(st, 'field', i); st.b[i].left = 0; placed = placed + 1 end
end
for i = 1, 121 do if R.can_place(st, 'chapel', i) then R.place(st, 'chapel', i); break end end
P.auto_assign(st)
""")
st = L.eval('st')
fields = [i for i, b in st.b.items() if b.kind == 'field']
on_fields = [p for p in people(st) if p.job in fields]
farmers = [p for p in people(st) if p.skill == 'farming' and p.age >= 144]
slots = 2 * len(fields)
on = [p for p in farmers if p.job in fields]
assert len(on) == min(len(farmers), slots), ([(p.skill, p.job) for p in farmers], fields)
builders = [p for p in people(st) if p.job == 'build']
assert len(builders) >= 2, len(builders)
children = [p for p in people(st) if p.age < 144]
assert all(p.job is None for p in children), 'children do not work'

# ids are never reused
st = fresh(19)
houses(st, 6)
live(st, 120, Rng.new(19), True)
ids = [p.id for p in people(st)]
assert len(ids) == len(set(ids)) and max(ids) == st.next_id - 1
print('people: all tests passed', dict(grew=grew, married=married, born=born_ok, old_died=old_died))
