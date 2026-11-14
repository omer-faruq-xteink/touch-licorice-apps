"""Port Wren's cases (game/gen.lua, game/solver.lua): the truth model and its clues over many seeds, the
solver, and an independent brute-force checker written here in Python from the spec's reasoning rules.

  python -I apps/portwren/test_cases.py
"""
import os, sys, time
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
L = lua54.LuaRuntime(unpack_returned_tuples=True)
L.execute(f"package.path = [[{HERE.replace(os.sep, '/')}/?.lua;]] .. package.path")
L.execute("T = require('game.text'); R = require('game.rng'); W = require('game.town')(T, R); G = require('game.gen')(T, R, W)")
G, Wn = L.eval('G'), L.eval('W')
SIZES = {'short': (4, 5, 8, 12), 'long': (6, 7, 13, 19)}


def py(v):
    """a Lua value as Python: tables become dicts (integer keys stay integers)"""
    if lua54.lua_type(v) == 'table':
        return {k: py(x) for k, x in v.items()}
    return v


def lst(d):
    return [d[k] for k in sorted(d)] if isinstance(d, dict) else []


TOWNS = {}


def town_for(seed):
    if seed not in TOWNS:
        TOWNS[seed] = Wn.make(1000 + seed % 7, 'career')
    return TOWNS[seed]


def build(seed, size, pattern='classic'):
    tw = town_for(seed)
    c = G.build(tw, L.table_from({'seed': seed, 'size': size, 'pattern': pattern, 'no': 1}))
    return (py(c) if c else None), tw


# ---------------------------------------------------------------- Task 3: the truth model
made = {'short': 0, 'long': 0}
for size, (ns, npl, cmin, cmax) in SIZES.items():
    for seed in range(1, 201):
        c, tw = build(seed, size)
        if c is None:
            continue
        made[size] += 1
        sus = lst(c['suspects'])
        k, s, scene = c['killer'], c['slot'], c['scene']
        assert len(sus) == ns and k in sus and c['victim'] not in sus, (seed, sus)
        assert 3 <= s <= 10 and c['window'] == {'lo': s, 'hi': s}
        assert c['moves'][k][s] == scene and c['says'][k][s] != scene, (seed, size)
        for p in sus:
            assert sorted(c['moves'][p]) == list(range(1, 13)), (seed, p)
            if p != k:
                assert c['says'][p] == c['moves'][p], (seed, 'an innocent tells the truth', p)
        places = lst(c['places'])
        assert len(places) == npl and len(set(places)) == npl and scene in places, (seed, places)
        assert all(tw.people[p].work in places for p in sus), 'every suspect can be met at work'
        clues = lst(c['clues'])
        assert cmin <= len(clues) <= cmax, (seed, size, len(clues))
        assert [cl['id'] for cl in clues] == list(range(1, len(clues) + 1))
        for cl in clues:
            gt = cl['gate']
            if gt['k'] == 'search':
                assert gt['place'] in places, (seed, gt)
            else:
                assert tw.people[gt['who']].status == 'alive' and gt['who'] != c['victim'], (seed, gt)
                assert tw.people[gt['who']].work in places, (seed, 'a gate person can be met', gt)
            if gt['k'] == 'show':
                assert gt['clue'] < cl['id'], (seed, 'show gates point back', gt)
            assert cl['src'] == 'cert' or cl['kind'] == 'testimony'
        assert c['days'] == (2 if size == 'short' else 3) and c['clock'] == {'day': 1, 'part': 1, 'used': 0}
for size in SIZES:
    assert made[size] >= 100, (size, made[size], 'one build in two at least')
print(f"cases: truth model ok ({made['short']} short, {made['long']} long of 200 seeds)")

# ---------------------------------------------------------------- Task 4: the solver and the checker
L.execute("V = require('game.solver')")
V = L.eval('V')


def reach_of(c_lua, tw):
    return set(py(G.reachable(c_lua, tw)).keys())


def analyse(c, known):
    """what the known facts and the statements prove, by the spec's rules, written without the Lua
    solver: the possible slots, the caught witnesses, the suspects caught lying, the cleared, and every
    (suspect, motive, means) left proven"""
    facts = [(f, cl['src']) for cl in lst(c['clues']) if cl['id'] in known for f in lst(cl['facts'])]
    lo, hi = c['window']['lo'], c['window']['hi']
    for f, _ in facts:
        if f['t'] == 'window':
            lo, hi = max(lo, f['lo']), min(hi, f['hi'])
    slot = lo if lo == hi else None
    weapon = next((f['means'] for f, _ in facts if f['t'] == 'weapon'), None)
    # a secret found puts its keeper somewhere for certain
    places = [(f['who'], f['slot'], f['place'], src) for f, src in facts if f['t'] in ('at', 'secret')]
    caught = set()
    while True:
        more = {src for who, s, pl, src in places if src != 'cert' and src not in caught and any(
            s2 == 'cert' and w2 == who and t2 == s and p2 != pl for w2, t2, p2, s2 in places)}
        if not more:
            break
        caught |= more
    seen = [(who, s, pl) for who, s, pl, src in places if src == 'cert' or src not in caught]
    not_at = [(f['who'], f['slot'], f['place']) for f, src in facts if f['t'] == 'not_at' and (src == 'cert' or src not in caught)]
    acc = {(f['who'], f['means']): f['yes'] for f, _ in facts if f['t'] == 'access'}
    mot = {}
    for f, _ in facts:
        if f['t'] == 'motive':
            mot.setdefault(f['who'], f['motive'])

    def lied(x, s):
        said = c['says'][x].get(s)
        return said is not None and (any(p == x and t == s and pl != said for p, t, pl in seen) or (x, s, said) in not_at)

    liars = {x for x in lst(c['suspects']) for s in c['says'][x] if lied(x, s)}
    cleared = set()
    for x in lst(c['suspects']):
        if weapon is not None and acc.get((x, weapon)) is False:
            cleared.add(x)
        if slot is not None and any(p == x and t == slot and pl != c['scene'] for p, t, pl in seen) and                 not any(p == x and t == slot and pl == c['scene'] for p, t, pl in seen):
            cleared.add(x)
    night2 = c.get('night2')
    out = []
    for x in lst(c['suspects']):
        for m in ['debt', 'inheritance', 'jealousy', 'blackmail', 'revenge', 'secret']:
            for w in ['poison', 'blunt', 'knife', 'drowning']:
                if x in cleared or weapon is None or w != weapon or mot.get(x) != m or acc.get((x, w)) is not True:
                    continue

                def proven(s, scene):
                    return lied(x, s) or any(p == x and t == s and pl == scene for p, t, pl in seen)
                if (slot is not None and proven(slot, c['scene'])) or (night2 and proven(night2['slot'], night2['scene'])):
                    out.append((x, m, w))
    return {'triples': out, 'slots': list(range(lo, hi + 1)), 'caught': caught, 'liars': liars, 'cleared': cleared}


def brute(c, known):
    return analyse(c, known)['triples']


def new_case(tw, seed, size, pattern='classic'):
    c = G.new_case(tw, L.table_from({'seed': seed, 'size': size, 'pattern': pattern, 'no': 1}))
    return c, py(c)


N = int(os.environ.get('PORTWREN_SEEDS', '1000'))
stats = {}
for size in SIZES:
    limit = 14 if size == 'short' else 21
    tries = []
    for seed in range(1, N + 1):
        tw = town_for(seed)
        cl, c = new_case(tw, seed, size)
        known = reach_of(cl, tw)
        b = brute(c, known)
        assert b == [(c['killer'], c['motive'], c['means'])], (seed, size, b, c['killer'], c['motive'], c['means'])
        res = py(V.solve(cl, L.table_from({k: True for k in known})))
        assert lst(res['guilty']) == [c['killer']], (seed, res)
        assert G.cost(cl, tw) <= limit, (seed, size, G.cost(cl, tw))
        tries.append(c['tries'])
    stats[size] = sum(tries) / len(tries)
print(f"cases: classic solver and checker agree over {N} seeds; tries on average {stats}")

# trust adds actions, never removes a clue: a town that trusts nobody still gets solvable cases in time
for seed in range(1, 101):
    tw = Wn.make(5000 + seed, 'career')
    for pid in py(Wn.living(tw)).values():
        tw.people[pid].trust = 0
    for size in SIZES:
        cl, c = new_case(tw, seed, size)
        assert brute(c, reach_of(cl, tw)) == [(c['killer'], c['motive'], c['means'])]
        assert G.cost(cl, tw) <= (14 if size == 'short' else 21), (seed, size, G.cost(cl, tw))

# the cost of one attempt (harness Lua time; the reader is slower)
tw = town_for(1)
t0 = time.perf_counter()
for seed in range(1, 101):
    cl = G.build(tw, L.table_from({'seed': seed, 'size': 'long', 'pattern': 'classic', 'no': 1}))
    if cl:
        V.check(cl, tw, G)
ms = (time.perf_counter() - t0) * 1000 / 100
assert ms < 150, ms
print(f'cases: one long attempt {ms:.1f} ms in the harness')

# ---------------------------------------------------------------- Task 5: the other patterns, false trails
def is_decisive(c, cl):
    k, s = c['killer'], c['slot']
    return any(f['t'] == 'at' and f['who'] == k and f['slot'] == s and f['place'] != c['says'][k][s] for f in lst(cl['facts']))


ALLOWED = [('alibi', 'short'), ('alibi', 'long'), ('timeline', 'short'), ('timeline', 'long'), ('liar', 'long')]
M = max(N // 2, 100)
rates = {}
for pattern, size in ALLOWED:
    limit = 14 if size == 'short' else 21
    tries = []
    for seed in range(1, M + 1):
        tw = town_for(seed)
        cl, c = new_case(tw, seed, size, pattern)
        assert c['pattern'] == pattern, (seed, pattern, size, 'fell back to', c['pattern'], c['tries'])
        tries.append(c['tries'])
        known = reach_of(cl, tw)
        truth = [(c['killer'], c['motive'], c['means'])]
        assert brute(c, known) == truth, (seed, pattern, size, brute(c, known))
        assert lst(py(V.solve(cl, L.table_from({k: True for k in known})))['guilty']) == [c['killer']]
        assert G.cost(cl, tw) <= limit, (seed, pattern, size, G.cost(cl, tw))
        clues = lst(c['clues'])
        k, s = c['killer'], c['slot']
        if pattern == 'alibi':
            cover = [cl2 for cl2 in clues if cl2['src'] != 'cert' and any(
                f['t'] == 'at' and f['who'] == k and f['slot'] == s and f['place'] != c['scene'] for f in lst(cl2['facts']))]
            assert cover and cover[0]['need'], (seed, 'a witness covers the killer')
            w = cover[0]['src']
            before = analyse(c, {i for i in known if not is_decisive(c, clues[i - 1]) or clues[i - 1]['src'] != 'cert'})
            assert k in before['cleared'], (seed, 'the alibi holds until the certain fact is found')
            after = analyse(c, known)
            assert w in after['caught'] and k not in after['cleared'], (seed, 'the witness is caught')
        elif pattern == 'timeline':
            lo, hi = c['window']['lo'], c['window']['hi']
            assert 3 <= hi - lo + 1 <= 4 and lo <= s <= hi, (seed, c['window'])
            timed = {cl2['id'] for cl2 in clues if any(f['t'] == 'window' for f in lst(cl2['facts']))}
            assert timed and all(clues[i - 1]['need'] for i in timed)
            before = analyse(c, known - timed)
            assert len(before['slots']) > 1 and len(set(lst(c['suspects'])) - before['cleared']) >= 2, (seed, before['slots'])
            for one in timed:
                assert len(analyse(c, known - {one})['slots']) > 1, (seed, 'every time clue is needed')
            assert analyse(c, known)['slots'] == [s]
        elif pattern == 'liar':
            liars = [p for p in lst(c['suspects']) if p != k and c['says'][p][s] != c['moves'][p][s]]
            assert len(liars) == 1, (seed, liars)
            i = liars[0]
            sec = [cl2 for cl2 in clues if any(f['t'] == 'secret' and f['who'] == i for f in lst(cl2['facts']))]
            assert sec and sec[0]['need'] and sec[0]['id'] in known, (seed, 'the secret can be found')
            before = analyse(c, known - {sec[0]['id']})
            assert i in before['liars'] and i not in before['cleared'], (seed, 'caught lying, not cleared')
            assert i in analyse(c, known)['cleared'], (seed, 'the secret clears them')
        trails = [cl2 for cl2 in clues if cl2['trail']]
        if size == 'long':
            assert len(trails) == 2 and not any(t['need'] for t in trails), (seed, len(trails))
            for t in trails:
                assert all(f.get('who') != k for f in lst(t['facts'])), (seed, 'a trail is never about the killer')
        else:
            assert not trails
    rates[(pattern, size)] = round(sum(tries) / len(tries), 2)
print(f'cases: alibi, timeline and liar over {M} seeds each; tries on average {rates}')

# Long classic cases have their two false trails as well
for seed in range(1, 101):
    tw = town_for(seed)
    cl, c = new_case(tw, seed, 'long')
    assert len([t for t in lst(c['clues']) if t['trail']]) == 2

# an innocent liar is a long case only
try:
    new_case(town_for(1), 1, 'short', 'liar')
    raise AssertionError('liar short must fail')
except lua54.LuaError:
    pass

# when a pattern cannot be made, Classic is: a solver refusing every other pattern
L.execute('''
real_check = V.check
V.check = function(case, town, G) if case.pattern ~= 'classic' then return false, 'stub' end return real_check(case, town, G) end
''')
cl, c = new_case(town_for(3), 3, 'long', 'timeline')
assert c['pattern'] == 'classic' and c['tries'] > 50, (c['pattern'], c['tries'])
L.execute('V.check = real_check')
# ---------------------------------------------------------------- Task 6: the killer strikes again
pick_new = L.eval('function(c, n0) return function(cl) return cl.id > n0 and cl.need end end')
for size in SIZES:
    for seed in range(1, 301):
        tw = town_for(seed)
        pattern = ['classic', 'alibi', 'timeline', 'liar' if size == 'long' else 'classic'][seed % 4]
        cl, c = new_case(tw, seed, size, pattern)
        innocent = next(p for p in lst(c['suspects']) if p != c['killer'])
        n0 = len(lst(c['clues']))
        alive_before = {p for p in py(Wn.living(tw)).values()}
        cl = G.strike(tw, cl, seed * 31 + 7, innocent)
        c = py(cl)
        n2 = c['night2']
        assert c['strikes'] == 1 and n2 and 13 <= n2['slot'] <= 18, (seed, n2)
        v2 = n2['victim']
        assert v2 != c['killer'] and v2 != innocent and v2 in alive_before and v2 != c['victim'], (seed, v2)
        assert v2 not in lst(c['suspects']) and v2 not in lst(c['witnesses'])
        assert c['killer'] in lst(c['suspects']) and c['moves'][c['killer']][n2['slot']] == n2['scene']
        assert c['says'][c['killer']][n2['slot']] != n2['scene']
        assert len(lst(c['clues'])) > n0 and any(x['need'] for x in lst(c['clues'])[n0:])
        known = reach_of(cl, tw)
        assert brute(c, known) == [(c['killer'], c['motive'], c['means'])], (seed, size, brute(c, known))
        assert lst(py(V.solve(cl, L.table_from({k: True for k in known})))['guilty']) == [c['killer']]
        assert all(x['id'] in known for x in lst(c['clues']) if x['need']), (seed, 'needed clues still reachable')
        assert G.cost(cl, tw, pick_new(cl, n0)) <= G.ACTIONS_PER_DAY, (seed, 'the new clues fit in the added day')
        assert c['days'] == (3 if size == 'short' else 4)
print('cases: the second crime keeps one answer (300 cases a size)')
# ---------------------------------------------------------------- review fixes: witnesses and names
def witness_places(c):
    """slot -> {witness -> places they imply they were at}: seeing someone at a place, or being at a
    place where someone was not"""
    out = {}
    for cl in lst(c['clues']):
        w = cl['src']
        if w == 'cert':
            continue
        for f in lst(cl['facts']):
            if f['t'] in ('at', 'not_at'):
                out.setdefault((w, f['slot']), set()).add(f['place'])
    return out


def first_names(c, tw):
    return [str(tw.people[p].name).split()[0] for p in lst(c['suspects'])]


for size in SIZES:
    for seed in range(1, 401):
        tw = town_for(seed)
        pattern = ['classic', 'alibi', 'timeline', 'liar' if size == 'long' else 'classic'][seed % 4]
        cl, c = new_case(tw, seed, size, pattern)
        bad = {k: v for k, v in witness_places(c).items() if len(v) > 1}
        assert not bad, (seed, size, pattern, 'a witness in two places at once', bad)
        fn = first_names(c, tw)
        assert len(fn) == len(set(fn)), (seed, size, 'suspects share a first name', fn)
        if seed % 3 == 0:
            G.strike(tw, cl, seed, next(p for p in lst(c['suspects']) if p != c['killer']))
            c = py(cl)
            bad = {k: v for k, v in witness_places(c).items() if len(v) > 1}
            assert not bad, (seed, size, 'after a strike, a witness in two places', bad)
print('cases: witnesses are in one place at a time; suspects have their own first names')
print('cases: all tests passed')
