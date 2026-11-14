"""Port Wren's town (game/town.lua) and the data of game/text.lua: making a town from a seed, schedules,
newcomers, rank and the patterns rank opens.

  python -I apps/portwren/test_town.py
"""
import os
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
L = lua54.LuaRuntime(unpack_returned_tuples=True)
L.execute(f"package.path = [[{HERE.replace(os.sep, '/')}/?.lua;]] .. package.path")
L.execute("T = require('game.text'); R = require('game.rng'); W = require('game.town')(T, R)")
T, R, Wn = L.eval('T'), L.eval('R'), L.eval('W')


def people(town):
    return [p for p in town.people.values()]


def alive(town):
    return [p for p in people(town) if p.status == 'alive']


town = Wn.make(5, 'career')
ps = alive(town)
assert len(ps) == 24, len(ps)
names = [p.name for p in ps]
assert len(set(names)) == 24, names
places = list(town.places.values())
assert len(places) == 10 and len(set(places)) == 10, places
assert all(k in T.PLACES for k in places)
for must in ('inn', 'cottages', 'pier'):
    assert must in places, (must, places)
assert all(p.work in places and p.home in places for p in ps)
assert all(T.JOBS[p.job].place == p.work for p in ps), 'a job belongs to its place'
assert all(40 <= p.trust <= 60 and len(list(p.hist.values())) == 0 for p in ps)
assert all(len(list(p.traits.values())) == 2 for p in ps)
assert len(list(town.rel.values())) >= 12
assert town.mode == 'career' and town.rank == 1 and town.rep == 0 and town.case_no == 0

# deterministic per seed, different between seeds
again = Wn.make(5, 'career')
assert [p.name for p in alive(again)] == names
assert [p.name for p in alive(Wn.make(6, 'career'))] != names

# schedules: every person can be met at a place of the town in at least 2 of the 4 parts
r = R.new(1)
for p in ps:
    s = Wn.schedule(town, p.id, r)
    parts = [s[k] for k in range(1, 5)]
    assert all(x in places for x in parts), parts
    assert parts[0] == p.work and parts[1] == p.work, parts

# times
assert T.time(1) == 'six o\'clock' and T.time(4) == 'half past seven', (T.time(1), T.time(4))
assert T.time(12) == 'half past eleven' and T.time(13) == 'nine o\'clock' and T.time(14) == 'half past nine'

# a thinned town is filled again; newcomers have no history and no relationships
for p in ps[:10]:
    p.status = 'dead' if p.id % 2 else 'jailed'
before = len(list(town.rel.values()))
Wn.fill(town, R.new(3))
now = alive(town)
assert len(now) >= 20, len(now)
new = [p for p in now if p.id > 24]
assert new and all(len(list(p.hist.values())) == 0 for p in new)
assert all(p.work in places and p.home in places for p in new)
assert len(set(p.name for p in people(town))) == len(people(town)), 'names stay unique'
rel_ids = {x for rl in town.rel.values() for x in (rl.a, rl.b)}
assert not any(p.id in rel_ids for p in new), 'newcomers know nobody yet'
assert len(list(town.rel.values())) == before

# trust is clamped
pid = now[0].id
Wn.trust(town, pid, -500)
assert town.people[pid].trust == 0
Wn.trust(town, pid, 500)
assert town.people[pid].trust == 100

# rank
assert [Wn.rank_of(v) for v in (0, 29, 30, 79, 80, 159, 160, 999)] == [1, 1, 2, 2, 3, 3, 4, 4]
assert list(T.RANKS.values()) == ['Constable', 'Sergeant', 'Inspector', 'Chief Inspector']


def pats(rank, size, mode='career'):
    tw = Wn.make(9, mode)
    tw.rank = rank
    return sorted(Wn.patterns(tw, size).values())


assert pats(1, 'short') == ['classic'] and pats(1, 'long') == ['classic']
assert pats(2, 'short') == ['alibi', 'classic', 'timeline'] == pats(2, 'long')
assert pats(3, 'short') == ['alibi', 'classic', 'timeline']
assert pats(3, 'long') == ['alibi', 'classic', 'liar', 'timeline'] == pats(4, 'long')
assert pats(1, 'short', 'single') == ['alibi', 'classic', 'timeline']
assert pats(1, 'long', 'single') == ['alibi', 'classic', 'liar', 'timeline']

# family and relationships
rl = town.rel[1]
assert Wn.related(town, rl.a, rl.b) == rl.k and Wn.related(town, rl.b, rl.a) == rl.k

# seeds stay inside 32-bit integers (the reader may have them): R.mix follows the wrapped sum
M31 = 2147483647


def seed31(x):
    return abs(int(x)) % (M31 - 1) + 1


def nxt(s):
    v = 16807 * (s % 127773) - 2836 * (s // 127773)
    return v + M31 if v <= 0 else v


def mix32(a, b):
    s = nxt(seed31(a))
    k = seed31(b) % 1000003
    s = s - (M31 - k) if s > M31 - k else s + k          # never past 2^31 - 1
    s = seed31(s)
    for _ in range(3):
        s = nxt(s)
        assert s < 2 ** 31
    return s


import random as _r  # noqa: E402
rng = _r.Random(5)
near = 0
for _ in range(20000):
    a, b = rng.randint(1, 2 ** 31 - 2), rng.randint(1, 2 ** 31 - 2)
    if nxt(seed31(a)) > M31 - 1000003:
        near += 1
    assert R.mix(a, b) == mix32(a, b), (a, b)
for a in range(1, 4000):          # the starts that land near the top, where the old sum overflowed
    if nxt(seed31(a)) > M31 - 1000003:
        near += 1
        assert R.mix(a, 999) == mix32(a, 999), a
assert near > 0

# a long career: the dead and the jailed nobody remembers are dropped, so the save stays small
tw = Wn.make(77, 'career')
r = R.new(9)
for n in range(1, 41):
    alive = list(Wn.living(tw).values())
    v, k = alive[n % len(alive)], alive[(n * 7 + 3) % len(alive)]
    if v == k:
        continue
    case = L.table_from({'no': n, 'victim': v, 'killer': k, 'over': ['solved', 'partial', 'lost'][n % 3]})
    Wn.after_case(tw, case)
people_now = {pid: p for pid, p in tw.people.items()}
alive_ids = {pid for pid, p in people_now.items() if p.status == 'alive'}
remembered = {h.who for pid in alive_ids for h in people_now[pid].hist.values() if h.who}
for pid, p in people_now.items():
    assert p.status == 'alive' or pid in remembered, (pid, p.status, 'kept though nobody remembers them')
assert remembered <= set(people_now), 'a memory points at a dropped person'
for rl in tw.rel.values():
    assert rl.a in people_now and rl.b in people_now, 'a relationship points at a dropped person'
assert len(people_now) < 24 + 40, len(people_now)
assert len(alive_ids) >= 20
print('town: all tests passed')
