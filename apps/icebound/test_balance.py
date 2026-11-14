"""Icebound's balance, proven by bots over hundreds of regions: a sensible player usually reaches the goal,
each mission can be won, losses are rare and always warned of, recklessness costs, no fixed plan wins
the best ending everywhere, and every run ends.

  ICEBOUND_RUNS=300 python -I apps/icebound/test_balance.py
"""
import os, time
from collections import Counter
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
L = lua54.LuaRuntime(unpack_returned_tuples=True)
L.execute(f"package.path = [[{HERE.replace(os.sep, '/')}/?.lua;]] .. package.path")
L.execute("""
Rng = require('game.rng'); G = require('game.region')(Rng); R = require('game.rules')(Rng, G)
T = require('game.text'); TM = require('game.team')(Rng, R, T); E = require('game.events')
EL = require('game.event_list')(Rng, R, TM, T, G); S = require('game.sim')(Rng, G, R, TM, E, T, EL)
B = require('game.bots')(G, R, TM, S)
-- a whole expedition by a bot; returns the state, whether every death was warned of two days before,
-- and the slowest day (ms)
function play(seed, diff, bot)
  local st = S.new(seed, diff, {})
  local r = Rng.new(Rng.mix(seed, 5))
  local warned, ok = {}, true
  local slow = 0
  while not st.over do
    for _, line in ipairs(TM.warnings(st)) do
      for id, p in pairs(st.team) do
        if p.alive and line:find(p.name, 1, true) then warned[id] = warned[id] or {}; warned[id][st.day] = true end
      end
    end
    local alive = {}
    for id, p in pairs(st.team) do alive[id] = p.alive end
    bot(st, r)
    if st.event then B.answer(st, r) end
    local t0 = os.clock()                 -- what the reader runs: the day, the morning, the warnings
    S.march(st, r)
    S.morning(st, r)
    S.warnings(st)
    local ms = (os.clock() - t0) * 1000
    if ms > slow then slow = ms end
    for id, p in pairs(st.team) do
      if alive[id] and not p.alive then
        local w = warned[id] or {}
        if not (w[st.day - 2] and w[st.day - 3]) then ok = false end
      end
    end
    if st.day > st.days + 2 then break end
  end
  return st, ok, slow
end
""")
play, B, S = L.eval('play'), L.eval('B'), L.eval('S')
N = int(os.environ.get('ICEBOUND_RUNS', '300'))
fails = []


def check(ok, what):
    if not ok:
        fails.append(what)


def survivors(st):
    return sum(1 for p in st.team.values() if p.alive)


t0 = time.perf_counter()
win, clean, by_mission, slowest, unwarned, ended = {}, {}, {}, 0.0, 0, True
for diff in ('easy', 'normal', 'hard'):
    w = c = 0
    for seed in range(1, N + 1):
        st, ok, slow = play(seed, diff, B.sensible)
        slowest = max(slowest, slow)
        unwarned += not ok
        ended = ended and bool(st.over) and st.day <= st.days + 1
        w += st.over == 'goal'
        c += survivors(st) == 6
        if diff == 'normal':
            m = by_mission.setdefault(str(st.mission), [0, 0])
            m[0] += st.over == 'goal'
            m[1] += 1
    win[diff], clean[diff] = w / N, c / N
check(0.60 <= win['normal'] <= 0.85, f'the sensible bot wins 60-85% on Normal: {win}')
check(win['easy'] > win['normal'] > win['hard'], f'difficulty order {win}')
for m, (a, b) in by_mission.items():
    check(a / b >= 0.40, f'{m} is won in {a}/{b} Normal runs')
check(clean['normal'] >= 0.60, f'nobody lost in most Normal runs: {clean}')

rw = rl = 0
fixed_top = 0
outcomes = Counter()
for seed in range(1, N + 1):
    st, ok, _ = play(seed, 'normal', B.reckless)
    unwarned += not ok
    ended = ended and bool(st.over) and st.day <= st.days + 1
    rw += st.over == 'goal'
    rl += survivors(st) < 6
    outcomes[str(st.over)] += 1
    st, ok, _ = play(seed, 'normal', B.fixed)
    unwarned += not ok
    ended = ended and bool(st.over) and st.day <= st.days + 1
    fixed_top += st.over == 'goal' and S.ending(st).level == 1
reckless_win, reckless_loss = rw / N, rl / N
check(reckless_win <= win['normal'] - 0.20 or reckless_loss >= 2 * (1 - clean['normal']),
      f'recklessness costs: wins {reckless_win:.2f} vs {win["normal"]:.2f}, losses {reckless_loss:.2f} vs {1 - clean["normal"]:.2f}')
check(fixed_top / N < 0.50, f'a fixed plan reaches the best ending in {fixed_top}/{N}')
check(unwarned == 0, f'{unwarned} runs had a death without two days of warning')
check(ended, 'every run ends by the last day of the season')
check(slowest < 30, f'the slowest day took {slowest:.1f} ms')
dt = time.perf_counter() - t0

for f in fails:
    print('FAIL', f)
print(f"balance: win {win}, nobody lost {clean}, by mission { {m: round(a / b, 2) for m, (a, b) in by_mission.items()} }, "
      f"reckless win {reckless_win:.2f} loss {reckless_loss:.2f} {dict(outcomes)}, fixed best {fixed_top}/{N}, "
      f"slowest day {slowest:.1f} ms, all {dt:.0f} s")
assert not fails, f'{len(fails)} failures'
print('balance: all tests passed')
