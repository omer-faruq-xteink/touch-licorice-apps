"""Riverstead's valley generator (game/valley.lua): every valley from its seed, checked, with its character.

  python -I apps/riverstead/test_valley.py
"""
import os, time
from collections import Counter
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
L = lua54.LuaRuntime(unpack_returned_tuples=True)
L.execute(f"package.path = [[{HERE.replace(os.sep, '/')}/?.lua;]] .. package.path")
L.execute("Rng = require('game.rng'); V = require('game.valley')(Rng)")
V = L.eval('V')


def tiles(v):
    return [v.t[i] for i in range(1, 122)]


t0 = time.perf_counter()
chars, special, by_char = Counter(), 0, {}
for seed in range(1, 1001):
    v = V.make(seed)
    ok, why = V.check(v)
    assert ok, (seed, why)
    ts = tiles(v)
    assert all(t in ('meadow', 'fertile', 'forest', 'rock', 'marsh', 'river') for t in ts), seed
    assert len(list(v.ford.values())) >= 1 and all(v.t[i] == 'river' for i in v.ford.values()), seed
    assert v.t[v.camp] == 'meadow', seed
    if v.special:
        special += 1
        assert v.t[v.special] == 'meadow' and not V.riverside(v, v.special), seed
    for i in range(1, 122):
        if v.t[i] == 'river':
            assert not V.riverside(v, i)
    for i in v.wide.keys():
        assert v.t[i] == 'river'
    chars[v.char] += 1
    c = Counter(ts)
    c['wide'] = len(list(v.wide.keys()))
    by_char.setdefault(v.char, []).append(c)
ms = (time.perf_counter() - t0) * 1000
assert 250 <= special <= 550, special
assert set(chars) == {'plain', 'hills', 'river', 'marsh'}, chars


def avg(char, key):
    lst = by_char[char]
    return sum(c[key] for c in lst) / len(lst)


assert avg('plain', 'fertile') > avg('hills', 'fertile'), 'plains are more fertile'
assert avg('hills', 'rock') > avg('plain', 'rock'), 'hills are rockier'
assert avg('marsh', 'marsh') > avg('plain', 'marsh'), 'marshland has marsh'
assert avg('river', 'wide') > avg('plain', 'wide'), 'wide rivers are wide'

# deterministic, and different between seeds
assert tiles(V.make(7)) == tiles(V.make(7)) and tiles(V.make(7)) != tiles(V.make(8))
assert ms < 2000, ms
print(f'valley: all tests passed ({ms:.0f} ms for 1000 valleys; chars {dict(chars)}; special {special})')
