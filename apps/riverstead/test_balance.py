"""Riverstead's balance, proven by automated players (game/bots.lua) over many valleys: a sensible player
survives the ten years in most valleys at every difficulty (Gentle > Normal > Harsh), an idle one dies,
every way can reach its third tier, no fixed plan wins everywhere, and famine is always warned of.

  python -I apps/riverstead/test_balance.py          (RIVERSTEAD_VALLEYS lowers the 300 valleys)
"""
import os, time
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
L = lua54.LuaRuntime(unpack_returned_tuples=True)
L.execute(f"package.path = [[{HERE.replace(os.sep, '/')}/?.lua;]] .. package.path")
L.execute("""
Rng = require('game.rng'); V = require('game.valley')(Rng); R = require('game.rules')(Rng, V)
T = require('game.text'); P = require('game.people')(Rng, R, T); E = require('game.events')
EL = require('game.event_list')(Rng, R, P, T); S = require('game.sim')(Rng, V, R, P, E, T, EL)
B = require('game.bots')(R, P, S, V)
-- a whole game by a bot; returns the state, whether famine was warned of, and the slowest month (ms)
function play(seed, diff, bot, arg)
  local st = S.new(seed, diff)
  local r = Rng.new(Rng.mix(seed, 3))
  local fm, warned = {}, true
  while not st.over do
    fm[st.month] = R.food_warning(st)
    bot(st, r, arg)
    S.begin_month(st, r)
    if st.event then
      if bot == B.idle then S.answer(st, 1, r) else B.answer(st, r) end
    end
    local m = st.month
    local rep = S.next_month(st, r)
    if rep.hunger and rep.hunger > 0 and m > 3 then
      local ok = false
      for k = math.max(1, m - 6), m - 2 do if fm[k] then ok = true end end
      if not ok then warned = false end
    end
  end
  return st, warned
end
""")
play, B, S, V, R = L.eval('play'), L.eval('B'), L.eval('S'), L.eval('V'), L.eval('R')
N = int(os.environ.get('RIVERSTEAD_VALLEYS', '300'))
fails = []


def check(ok, what):
    if not ok:
        fails.append(what)


t0 = time.perf_counter()
alive, warned_all, avg, top = {}, True, {}, {}
for diff in ('gentle', 'normal', 'harsh'):
    n = total = lv1 = 0
    for seed in range(1, N + 1):
        st, warned = play(seed, diff, B.sensible, None)
        n += st.over == 'end'
        total += S.score(st)
        lv1 += S.ending(st).level == 1
        warned_all = warned_all and warned
    alive[diff] = n / N
    avg[diff] = total / N
    top[diff] = lv1 / N
check(avg['gentle'] > avg['normal'] > avg['harsh'], f'average score falls with difficulty {avg}')
check(0.2 <= top['normal'] <= 0.8, f'the best ending is reachable but not certain on Normal: {top}')
check(alive['normal'] >= 0.90 and alive['gentle'] >= 0.97 and alive['harsh'] >= 0.70, f'survival {alive}')
check(alive['gentle'] >= alive['normal'] >= alive['harsh'], f'difficulty order {alive}')
check(warned_all, 'a famine came without a warning two months before (R.food_warning)')

idle_dead = 0
for seed in range(1, N + 1):
    st, _ = play(seed, 'normal', B.idle, None)
    idle_dead += st.over == 'dead' and st.month <= 60
check(idle_dead == N, f'the idle bot survived in {N - idle_dead} valleys')

tier3 = {}
for way in ('trade', 'grain', 'craft', 'faith'):
    ok = possible = 0
    for seed in range(1, N + 1):
        if way == 'faith' and not V.make(seed).special:
            continue
        possible += 1
        st, _ = play(seed, 'normal', B.sensible, way)
        w, tier = S.way(st)
        ok += (w == way and tier == 3)
    tier3[way] = ok / max(1, possible)
    check(tier3[way] >= 0.60, f'{way} reaches tier 3 in {tier3[way]:.0%}')

fixed_ok = 0
order = L.table_from(['field', 'field', 'house', 'woodcutter', 'field', 'house', 'quarry', 'market', 'house', 'field',
                      'storehouse', 'tradingpost', 'house', 'field', 'wharf', 'house'])
for seed in range(1, N + 1):
    st, _ = play(seed, 'normal', B.fixed, order)
    w, tier = S.way(st)
    fixed_ok += st.over == 'end' and S.ending(st).level == 1
check(fixed_ok / N < 0.90, f'one fixed plan reaches the best ending in {fixed_ok / N:.0%} of valleys')

t1 = time.perf_counter()
st, _ = play(1, 'normal', B.sensible, None)
one = time.perf_counter() - t1
check(one < 1.5, f'one game takes {one:.2f} s')

for f in fails:
    print('FAIL', f)
print(f'balance: survival {alive}, avg score {avg}, best ending {top}, tier 3 {tier3}, fixed plan {fixed_ok / N:.0%}, idle dead {idle_dead}/{N}, '
      f'one game {one:.2f} s, all {time.perf_counter() - t0:.0f} s')
assert not fails, f'{len(fails)} failures'
print('balance: all tests passed')
