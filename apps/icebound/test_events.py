"""Icebound's events: the reusable engine (game/events.lua, a copy of Riverstead's) and this game's events
(game/event_list.lua): every one can occur, fills its blanks, never kills, and reads the route ahead.

  python -I apps/icebound/test_events.py
"""
import os
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
L = lua54.LuaRuntime(unpack_returned_tuples=True)
L.execute(f"package.path = [[{HERE.replace(os.sep, '/')}/?.lua;]] .. package.path")
L.execute("""
Rng = require('game.rng'); G = require('game.region')(Rng); R = require('game.rules')(Rng, G)
T = require('game.text'); TM = require('game.team')(Rng, R, T); E = require('game.events')
EL = require('game.event_list')(Rng, R, TM, T, G)
-- an expedition state on day `day`, with varied weather, conditions and moods from the seed
function trek(seed, mission, day)
  local r = Rng.new(seed * 13 + 1)
  local reg = G.make(seed, mission or G.MISSIONS[seed % 4 + 1])
  local st = { v = 1, seed = seed, diff = ({ 'easy', 'normal', 'hard' })[seed % 3 + 1], mission = reg.mission, season = 'early',
               day = day or (1 + seed % 40), days = 60, region = reg, pos = reg.start, route = {}, seen = {}, frozen = {},
               pace = 'steady', ration = 'normal', progress = 0, sup = { food = 300, dogfood = 300, fuel = 60, dogs = 12, sledges = 3 },
               radio = 'unused', depots = {}, phase = 'out', found = {}, team = {}, next_id = 1, flags = {}, pending = {},
               extras = { samples = 0, plates = 0 }, broken = 0, photo = {}, name = 'the expedition' }
  st.month = st.day
  st.weather = { kind = R.WEATHER[r:int(1, 5)], temp = -10 - r:int(0, 40), wind = r:int(0, 50), left = 2 }
  TM.make(st, r)
  if r:chance(0.2) then st.sup.dogfood = r:int(5, 40) end
  for _, p in pairs(st.team) do
    if r:chance(0.3) then p.cond[T.CONDS[r:int(1, 5)]] = r:int(1, 3) end
    if r:chance(0.3) then p.mood = r:int(10, 40) end
  end
  -- a route north through whatever lies there, and the party somewhere along the map
  local x, y = G.xy(reg.start)
  y = math.max(4, y - r:int(0, 20))
  st.pos = G.idx(x, y)
  st.region.t[st.pos] = 'flat'
  for k = 1, 3 do st.route[k] = G.idx(x, y - k) end
  if r:chance(0.3) then st.region.t[st.route[r:int(1, 2)]] = ({ 'crevasse', 'water', 'ridge', 'sastrugi' })[r:int(1, 4)] end
  if r:chance(0.2) then st.region.t[G.idx(math.min(11, x + 1), y)] = 'rock' end
  if r:chance(0.2) then st.region.t[G.idx(math.max(1, x - 1), y)] = 'water' end
  if r:chance(0.15) and #reg.cairns > 0 then st.pos = reg.cairns[1] end
  R.reveal(st)
  return st
end
function ahead_has(st, terrain)
  for k = 1, math.min(2, #st.route) do
    local j = st.route[k]
    if st.region.t[j] == terrain then return true end
    if terrain == 'water' then for _, n in ipairs(G.around(j)) do if st.region.t[n] == 'water' then return true end end end
  end
  return false
end
function anyone_dead(st) for _, p in pairs(st.team) do if not p.alive then return true end end; return false end
""")
E, EL, trek = L.eval('E'), L.eval('EL'), L.eval('trek')
Rng, T = L.eval('Rng'), L.eval('T')
defs = [d for d in EL.defs.values()]
fails = []


def check(ok, what):
    if not ok:
        fails.append(what)


def pick(st, r):
    res = E.pick(EL.defs, st, r, EL.ctx)
    return res if isinstance(res, tuple) else (None, None)

check(len(defs) >= 40, f'{len(defs)} events')
check(len([d for d in defs if any(c.chance for c in d.choices.values())]) >= 8, 'chance events')
check(len([d for d in defs if any(c['then'] for c in d.choices.values())]) >= 3, 'follow-ups')
check(len([d for d in defs if d.once]) >= 4, 'once-only events')
check(len({d.id for d in defs}) == len(defs), 'ids are unique')
check(len([d for d in defs if d.cond and d.cond.ahead]) >= 4, 'events about the route ahead')
backs = [d for d in defs if any(c.back for c in d.choices.values())]
check(len(backs) >= 12, f'{len(backs)} events with a safe choice for Back')
for d in defs:
    check(len([c for c in d.choices.values() if c.back]) <= 1, f'{d.id}: more than one Back choice')
src = open(os.path.join(HERE, 'game', 'events.lua'), encoding='utf-8').read()
rv = open(os.path.join(HERE, '..', 'riverstead', 'game', 'events.lua'), encoding='utf-8').read()
check(src == rv, 'events.lua is the same as Riverstead\'s')

# picks only events whose condition holds, never the last one; no effect ever kills; stocks never negative
seen = set()
for seed in range(1, 301):
    st = trek(seed)
    r = Rng.new(seed)
    for d_ in range(12):
        ev, vars_ = pick(st, r)
        if ev is None:
            st.day += 1; st.month = st.day
            continue
        check(EL.ctx.cond(ev, st) or ev.followup, f'{ev.id} picked with its condition false')
        check(ev.id != st.last_event or ev.followup, f'{ev.id} twice in a row')
        if ev.cond and ev.cond.ahead:
            check(L.eval('ahead_has')(st, ev.cond.ahead), f'{ev.id} with no {ev.cond.ahead} ahead')
        seen.add(ev.id)
        chs = list(E.choices(ev, st, vars_, EL.ctx).values())
        check(len(chs) >= 1, f'{ev.id} offers no choice')
        E.apply(ev, chs[seed % len(chs)], st, vars_, r, EL.ctx)
        check(not L.eval('anyone_dead')(st), f'{ev.id} killed someone')
        for k in ('food', 'fuel', 'dogfood', 'dogs', 'sledges'):
            check(st.sup[k] >= 0, f'{ev.id} made {k} negative')
        st.day += 1; st.month = st.day
check(len(seen) >= 36, f'only {len(seen)} events seen in 300 expeditions')

# every outcome of every choice (ok and fail) on a busy state: no deaths, no negatives
for d in defs:
    for seed in range(1, 60):
        st = trek(seed)
        vars_ = E.fill(d, st, Rng.new(seed), EL.ctx)
        if not vars_:
            continue
        for ci, c in d.choices.items():
            for outcome in ('ok', 'fail'):
                st2 = trek(seed)
                vars2 = E.fill(d, st2, Rng.new(seed), EL.ctx)
                fx = c.ok if outcome == 'ok' else c.fail
                if fx and vars2:
                    EL.ctx.fx(fx, st2, vars2, Rng.new(seed))
                    check(not L.eval('anyone_dead')(st2), f'{d.id} {ci} {outcome} killed someone')
                    for k in ('food', 'fuel', 'dogfood', 'dogs', 'sledges'):
                        check(st2.sup[k] >= 0, f'{d.id} made {k} negative')
        break

# a follow-up due now comes first
st = trek(7)
fid = next(d.id for d in defs if d.followup)
st.pending = L.table_from({1: L.table_from({'at': st.month, 'id': fid, 'vars': L.table_from({})})})
ev, vars_ = pick(st, Rng.new(1))
check(ev is not None and ev.id == fid, f'the follow-up first: {ev and ev.id}')

# a skilled person succeeds more often; someone who refuses lends no skill
chance_ev = next(d for d in defs if any(c.chance and c.chance.role for c in d.choices.values()))
ci = next(i for i, c in chance_ev.choices.items() if c.chance and c.chance.role)
role = chance_ev.choices[ci].chance.role
wins = {}
for case in ('lv1', 'lv5', 'lv5sulk'):
    n = 0
    for k in range(600):
        st = trek(11 + k % 7)
        for p in st.team.values():
            p.lv = 1 if case == 'lv1' else 5
            p.mood = 10 if case == 'lv5sulk' else 70
            p.role = role
        vars_ = E.fill(chance_ev, st, Rng.new(k), EL.ctx)
        if not vars_:
            continue
        st.last_event = None
        _, outcome = E.apply(chance_ev, ci, st, vars_, Rng.new(k + 7), EL.ctx)
        n += outcome == 'ok'
    wins[case] = n
check(wins['lv5'] > wins['lv1'] and wins['lv5sulk'] < wins['lv5'], f'skill helps, refusing does not: {wins}')

# a choice that needs two people together is hidden while they are at odds
tog = [(d, i, c) for d in defs for i, c in d.choices.items() if c.when and c.when.together]
check(len(tog) >= 1, 'a choice needs two people together')
if tog:
    d, i, c = tog[0]
    a, b = str(c.when.together[1]), str(c.when.together[2])
    for rel, shown in ((-1, False), (1, True)):
        for seed in range(1, 200):
            st = trek(seed)
            vars_ = E.fill(d, st, Rng.new(seed), EL.ctx)
            if not vars_ or not EL.ctx.cond(d, st):
                continue
            pa, pb = vars_[a + '_id'], vars_[b + '_id']
            if pa is None or pb is None:
                continue
            st.team[pa].rel[pb], st.team[pb].rel[pa] = rel, rel
            idx = list(E.choices(d, st, vars_, EL.ctx).values())
            check((i in idx) == shown, f'{d.id}: together choice shown={i in idx} with rel {rel}')
            break

# every cast names every role it chose (the cast once lost names by adding keys during a pairs loop)
for d in defs:
    roles = [str(x) for x in (d.roles or L.table_from([])).values()]
    for seed in range(1, 80):
        st = trek(seed)
        vars_ = E.fill(d, st, Rng.new(seed), EL.ctx)
        if not vars_:
            continue
        for role in roles:
            if role == 'n':
                continue
            check(vars_[role] is not None, f'{d.id}: no name for {role}')

# every event can happen somewhere, and renders with no blank
for d in defs:
    if d.followup:
        continue
    ok = any(EL.ctx.cond(d, trek(seed)) for seed in range(1, 400))
    check(ok, f'{d.id} can never happen')
for d in defs:
    for seed in range(1, 40):
        st = trek(seed)
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
