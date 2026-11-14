"""Riverstead's game as a whole (game/sim.lua): a new game, the month (events, production, people, floods,
renown, coin), trade, the end after ten years or when no one is left, and the score and ending.

  python -I apps/riverstead/test_sim.py
"""
import os
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
L = lua54.LuaRuntime(unpack_returned_tuples=True)
L.execute(f"package.path = [[{HERE.replace(os.sep, '/')}/?.lua;]] .. package.path")
L.execute("""
Rng = require('game.rng'); V = require('game.valley')(Rng); R = require('game.rules')(Rng, V)
T = require('game.text'); P = require('game.people')(Rng, R, T); E = require('game.events')
EL = require('game.event_list')(Rng, R, P, T); S = require('game.sim')(Rng, V, R, P, E, T, EL)
Save = require('game.save')
-- place the first of `kinds` that fits somewhere, built at once
function put(st, kind)
  for i = 1, 121 do
    if R.can_place(st, kind, i) then R.place(st, kind, i); st.b[i].left = 0; return i end
  end
end
-- a fed, scripted run: houses and the given way's buildings, everyone assigned, events answered
function scripted(seed, way_kinds)
  local st = S.new(seed, 'normal')
  local r = Rng.new(seed)
  for m = 1, 130 do
    if st.over then break end
    st.res.food, st.res.wood, st.res.stone, st.res.tools, st.res.coin = 400, 400, 400, 40, math.max(st.res.coin, 60)
    if m % 6 == 1 then put(st, 'house') end
    for _, k in ipairs(way_kinds) do if not R.has(st, k) then put(st, k) end end
    P.auto_assign(st)
    S.begin_month(st, r)
    if st.event then S.answer(st, 1, r) end
    S.next_month(st, r)
  end
  return st
end
""")
S, R, Save, Rng = L.eval('S'), L.eval('R'), L.eval('Save'), L.eval('Rng')
scripted, put = L.eval('scripted'), L.eval('put')

# a new game
st = S.new(5, 'normal')
assert st.month == 1 and st.diff == 'normal' and st.name and st.res.food == 130 and st.res.wood == 50
assert 10 <= len([p for p in st.people.values()]) <= 14
assert len([b for b in st.b.values() if b.kind == 'house']) == 2, 'two houses at the camp'
assert Save.encode(S.new(5, 'normal')) == Save.encode(S.new(5, 'normal')), 'deterministic'

# a fed run that follows the trade way ends as a market town
st = scripted(7, L.table_from(['market', 'tradingpost', 'wharf']))
assert st.over == 'end' and st.month == 121, (st.over, st.month)
e = S.ending(st)
assert e.way == 'trade' and e.level in (1, 2, 3) and e.title and e.score == S.score(st), (e.way, e.level, e.title)
assert st.renown.trade > st.renown.grain

# doing nothing: the village dies before the ten years are up
st = S.new(9, 'normal')
r = Rng.new(9)
while not st.over:
    S.begin_month(st, r)
    if st.event:
        S.answer(st, 1, r)             # the first choice on offer
    S.next_month(st, r)
assert st.over == 'dead' and st.month < 121, (st.over, st.month)
assert S.ending(st).way == 'dead'

# trade: only with a market; you can't buy more than your coin; selling pays less than buying
st = S.new(11, 'normal')
assert R.trade_prices(st) is None and not R.trade(st, 'food', 10)[0]
put(st, 'market')
pr = R.trade_prices(st)
for k in ('food', 'wood', 'stone', 'tools'):
    assert pr[k].sell < pr[k].buy, (k, pr[k].sell, pr[k].buy)
st.res.coin = 0
assert not R.trade(st, 'food', 10)[0], 'no coin, no buying'
st.res.food = 50
ok, why = R.trade(st, 'food', -10)
assert ok and st.res.coin > 0 and st.res.food == 40, (ok, why, st.res.coin)
put(st, 'tradingpost')
pr2 = R.trade_prices(st)
assert pr2.food.buy <= pr.food.buy and pr2.food.sell >= pr.food.sell, 'a trading post improves the rates'

# Review focus 5: the last month ends the game once, drops a pending follow-up, and keeps its ending
st = scripted(13, L.table_from(['mill', 'barn']))
st2 = S.new(15, 'normal')
st2.month = 120
st2.res.food = 400
st2.pending = L.table_from({1: L.table_from({'at': 121, 'id': 'charter_paid', 'vars': L.table_from({})})})
S.next_month(st2, Rng.new(1))
assert st2.over == 'end' and len(list(st2.pending.values())) == 0, (st2.over, len(list(st2.pending.values())))
again = S.next_month(st2, Rng.new(1))
assert st2.month == 121, 'the end does not run twice'
e1 = S.ending(st2)
back = Save.decode(Save.encode(st2))
e2 = S.ending(back)
assert (e1.way, e1.level, e1.title, e1.score) == (e2.way, e2.level, e2.title, e2.score)
print('sim: all tests passed', dict(trade_title=str(S.ending(scripted(7, L.table_from(['market', 'tradingpost', 'wharf']))).title)))
