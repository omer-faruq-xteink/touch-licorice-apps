"""Riverstead's events: the reusable engine (game/events.lua: conditions, weights, no repeats, once-only,
follow-ups, choice conditions, chance) and this game's events (game/event_list.lua): every one can occur,
fills its blanks, and renders.

  python -I apps/riverstead/test_events.py
"""
import os, re
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
L = lua54.LuaRuntime(unpack_returned_tuples=True)
L.execute(f"package.path = [[{HERE.replace(os.sep, '/')}/?.lua;]] .. package.path")
L.execute("""
Rng = require('game.rng'); V = require('game.valley')(Rng); R = require('game.rules')(Rng, V)
T = require('game.text'); P = require('game.people')(Rng, R, T); E = require('game.events')
EL = require('game.event_list')(Rng, R, P, T)
function village(seed, year, kinds)
  local st = R.new_state(V.make(seed))
  st.res.food, st.res.wood, st.res.stone, st.res.tools, st.res.coin = 300, 200, 150, 20, 80
  P.founders(st, Rng.new(seed))
  st.month = (year - 1) * 12 + 1 + (seed % 12)
  st.name = 'Willowford'
  for _, kind in ipairs(kinds or {}) do
    for i = 1, 121 do
      if not st.b[i] and R.BUILD[kind].place(st.valley, st, i) then st.b[i] = { kind = kind, left = 0 }; break end
    end
  end
  return st
end
""")
E, EL, _village = L.eval('E'), L.eval('EL'), L.eval('village')


def village(seed, year, kinds=None):
    return _village(seed, year, L.table_from(kinds or []))

Rng, T = L.eval('Rng'), L.eval('T')
defs = [d for d in EL.defs.values()]
by_id = {d.id: d for d in defs}
fails = []


def check(ok, what):
    if not ok:
        fails.append(what)


ALL = ['house', 'field', 'fisher', 'woodcutter', 'quarry', 'toolmaker', 'storehouse', 'well', 'herbalist', 'chapel', 'levee',
       'market', 'tradingpost', 'wharf', 'mill', 'barn', 'bakery', 'smithy', 'pottery', 'weaving', 'shrine', 'temple', 'hostel']
pick = lambda st, r: E.pick(EL.defs, st, r, EL.ctx)

# the counts the plan asks for
check(len(defs) >= 38, f'{len(defs)} events')
check(len([d for d in defs if any(c.chance for c in d.choices.values())]) >= 4, 'chance events')
check(len([d for d in defs if any(c['then'] for c in d.choices.values())]) >= 3, 'follow-ups')
check(len([d for d in defs if d.once]) >= 5, 'once-only events')
for way in ('trade', 'grain', 'craft', 'faith'):
    check(len([d for d in defs if d.way == way]) >= 3, f'events of the {way} way')
check(len({d.id for d in defs}) == len(defs), 'ids are unique')

# the engine knows nothing of this game
src = open(os.path.join(HERE, 'game', 'events.lua'), encoding='utf-8').read()
check('rules' not in src and 'people' not in src and 'R.' not in src, 'events.lua is game-independent')

# picks only events whose condition holds, never the last one, once-only at most once
seen = set()
for seed in range(1, 201):
    st = village(seed, 1 + seed % 9, ALL if seed % 3 == 0 else (['house', 'field'] if seed % 3 == 1 else ['market', 'mill', 'smithy', 'shrine']))
    r = Rng.new(seed)
    for m in range(24):
        ev, vars_ = pick(st, r)
        if ev is None:
            st.month += 1
            continue
        check(EL.ctx.cond(ev, st) or ev.followup, f'{ev.id} picked with its condition false')
        check(ev.id != st.last_event or ev.followup, f'{ev.id} twice in a row')
        seen.add(ev.id)
        chs = E.choices(ev, st, vars_, EL.ctx)
        check(len(list(chs.values())) >= 1, f'{ev.id} offers no choice')
        ci = list(chs.values())[0]
        E.apply(ev, ci, st, vars_, r, EL.ctx)
        for k in ('food', 'wood', 'stone', 'tools', 'coin'):
            check(st.res[k] >= 0, f'{ev.id} made {k} negative')
        st.month += 1
once_ids = [d.id for d in defs if d.once]
st = village(5, 4, ALL)
r = Rng.new(5)
count = {}
for m in range(120):
    ev, vars_ = pick(st, r)
    if ev:
        count[ev.id] = count.get(ev.id, 0) + 1
        E.apply(ev, list(E.choices(ev, st, vars_, EL.ctx).values())[0], st, vars_, r, EL.ctx)
    st.month += 1
for i in once_ids:
    check(count.get(i, 0) <= 1, f'once-only {i} came {count.get(i)} times')

# a follow-up due now comes first
st = village(7, 3, ALL)
fid = next(d.id for d in defs if d.followup)
st.pending = L.table_from({1: L.table_from({'at': st.month, 'id': fid, 'vars': L.table_from({})})})
ev, vars_ = pick(st, Rng.new(1))
check(ev is not None and ev.id == fid, f'the follow-up first: {ev and ev.id}')

# a choice's condition hides it: a trade the village can't pay for
cond_ev = next((d for d in defs if any(c.when for c in d.choices.values())), None)
check(cond_ev is not None, 'some choice has a condition')
if cond_ev:
    st = village(9, 3, ALL)
    for k in ('food', 'wood', 'stone', 'tools', 'coin'):
        st.res[k] = 0
    vars_ = E.fill(cond_ev, st, Rng.new(2), EL.ctx)
    shown = list(E.choices(cond_ev, st, vars_ or L.table_from({}), EL.ctx).values())
    check(len(shown) < len(list(cond_ev.choices.values())), f'{cond_ev.id}: a choice it can\'t afford is hidden')

# chance: a skilled person succeeds more often
chance_ev = next(d for d in defs if any(c.chance and c.chance.skill for c in d.choices.values()))
ci = next(i for i, c in chance_ev.choices.items() if c.chance and c.chance.skill)
skill = chance_ev.choices[ci].chance.skill
wins = {}
for lv in (1, 5):
    st = village(11, 3, ALL)
    for p in st.people.values():
        p.lv = lv
        p.skill = skill
    n = 0
    for k in range(1000):
        vars_ = E.fill(chance_ev, st, Rng.new(k), EL.ctx)
        if not vars_:
            continue
        st.last_event = None
        key, outcome = E.apply(chance_ev, ci, st, vars_, Rng.new(k + 7), EL.ctx)
        n += outcome == 'ok'
        st.pending = L.table_from({})
        st.res.food, st.res.wood, st.res.stone, st.res.coin = 300, 200, 150, 80
        for p in st.people.values():
            p.alive, p.gone, p.health = True, None, 80
    wins[lv] = n
check(wins[5] > wins[1], f'skill helps: {wins}')

# every event can happen somewhere, fills its roles in a busy year-3 village, and renders with no blank
for d in defs:
    if d.followup:
        continue
    ok = False
    for seed in range(1, 300):
        st = village(seed, 2 + seed % 8, ALL)
        st.month = st.month - (st.month - 1) % 12 + (seed % 12)
        if seed % 2:
            for p in st.people.values():
                p.happy = 20                       # a gloomy village, for the events of unhappiness
        if EL.ctx.cond(d, st):
            ok = True
            break
    check(ok, f'{d.id} can never happen')
for d in defs:
    for seed in range(1, 40):
        st = village(seed, 3, ALL)
        vars_ = E.fill(d, st, Rng.new(seed), EL.ctx)
        if not vars_:
            continue
        r = Rng.new(seed)
        texts = [str(T.event_text(d, vars_, r))]
        for c in d.choices.values():
            texts.append(str(T.fill(c.label, vars_)))
            for key in ('ok_text', 'fail_text'):
                if c[key]:
                    texts.append(str(T.fill(c[key], vars_)))
        for s in texts:
            check('{' not in s and s.strip(), f'{d.id}: a blank left: {s}')
    check(len(list(d.text.values())) >= 3, f'{d.id} has fewer than 3 texts')

for f in fails[:15]:
    print('FAIL', f)
assert not fails, f'{len(fails)} failures'
print(f'events: all tests passed ({len(defs)} events, {len(seen)} seen in random play)')
