"""Offline test of Backgammon (gamekit harness, ctx:after timers run by hand).

Rules: the start, both dice must be played, the larger die when only one fits, the bar first and
a closed board, hits, doubles, bearing off (exact, the higher die from the highest point, not with
a checker outside), the plays of a roll one per position, single game / gammon / backgammon.
Engine: the openings it should know, a race scored by the pips, thinking in slices, Medium beating
Beginner and Hard holding its own against Medium in self-play (15 checkers each throughout).
The game by taps: the opening roll, marked targets and a combined move, the reader's reply, Undo
with the same dice, the bar picked by itself, no move, the cube (taken, passed, the Crawford
game), the end of a game and of a match, the game kept, Back, Hint and the draw commands.

  python -I apps/backgammon/test_backgammon.py
"""
import os, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

sys.stdout.reconfigure(encoding='utf-8')
g = Game(HERE)
L = g.L
L.execute('''
timers = {}
ctx.after = function(self, ms, fn) assert(self == ctx); timers[#timers + 1] = fn; return true end
function run_timers()
  local n = 0
  while #timers > 0 do local f = table.remove(timers, 1); f(ctx); n = n + 1; fake_ms = fake_ms + 50 end
  return n
end
function lua_list(t) local out = {}; for i, v in ipairs(t) do out[i] = v end; return out end
''')
g.restart()
A = lambda: g.api
R = g.api.R
E = g.api.E
BT, BB = 136, 616
fails = []


def check(ok, what):
    print(('ok    ' if ok else 'FAIL  ') + what)
    if not ok:
        fails.append(what)


def lt(*xs):
    return L.table_from(list(xs))


def pos(white, black, bar=(0, 0), off=None, side=1):
    """a position from {point: n} for White (side 1) and Black (side -1), board numbers"""
    b = [0] * 28
    for p, n in white.items():
        b[p - 1] = n
    for p, n in black.items():
        b[p - 1] = -n
    b[24], b[25] = bar
    w = 15 - sum(white.values()) - bar[0]
    k = 15 - sum(black.values()) - bar[1]
    b[26], b[27] = off if off else (w, k)
    return L.table_from(b)


def key(t):
    return str(R.key(t))


def plays(b, s, d1, d2):
    ps = R.plays(b, s, d1, d2)[0]
    return sorted(str(R.text(p.moves)) for p in ps.values())


def total(b, s):
    n = int(b[R.bar(s)]) + int(b[R.off(s)])
    for i in range(1, 25):
        v = int(b[i]) * s
        if v > 0:
            n += v
    return n


# ---------------------------------------------------------------- rules
b = R.new()
check(R.pips(b, 1) == 167 and R.pips(b, -1) == 167 and total(b, 1) == 15 and total(b, -1) == 15, 'the start: 15 checkers each, 167 pips')
counts = {(a, c): int(R.count_plays(b, 1, a, c)) for a in range(1, 7) for c in range(a, 7)}
check(counts[(1, 3)] > 10 and counts[(6, 6)] > 5 and all(v > 0 for v in counts.values()), f'every roll has plays from the start: 3-1 {counts[(1, 3)]}, 6-6 {counts[(6, 6)]}')

# both dice must be played: the 6 first is blocked (the 7 point held), the 5 then the 6 works
b = pos({13: 1, 1: 14}, {7: 2, 24: 13})
got = plays(b, 1, 6, 5)
check(got == ['13/8 8/2'], f'both dice played when they can be: {got}')
b = pos({13: 1, 1: 14}, {7: 2, 2: 2, 24: 11})
got = plays(b, 1, 6, 5)
check(got == ['13/8'], f'only the 5 when the 6 is blocked either way: {got}')

# either die alone, never both (the back checkers blocked, no bearing off with them out): the 6
b = pos({10: 1, 24: 14}, {18: 2, 19: 2, 1: 11})
got = plays(b, 1, 6, 5)
check(got == ['10/4'], f'the larger die when only one can be played: {got}')
b = pos({10: 1, 1: 14}, {4: 2, 5: 2, 24: 11})
got = plays(b, 1, 6, 1)
check(all(len(x.split()) == 2 for x in got), f'(both when the small one opens the way: {got})')

# the bar first; a closed board leaves no move
b = pos({13: 14}, {}, bar=(1, 0))
got = plays(b, 1, 6, 1)
check(all(x.startswith('bar/') for x in got) and len(got) >= 1, f'a checker on the bar comes in first: {got}')
b = pos({13: 14}, {19: 2, 20: 2, 21: 2, 22: 2, 23: 2, 24: 2}, bar=(1, 0))
got = plays(b, 1, 6, 1)
check(got == ['(no move)'], f'a closed board: no move ({got})')

# a hit sends the checker to the bar
b = pos({13: 15}, {10: 1, 24: 14})
tb = R.copy(b)
R.step(tb, 1, lt(13, 10, True, 3))
check(int(tb[10]) == 1 and int(tb[R.bar(-1)]) == 1, 'a hit: the blot goes to the bar')

# doubles: four moves
b = R.new()
got = plays(b, 1, 6, 6)
check(all(len(x.split()) == 4 for x in got), f'a double plays four moves: {got[:2]}')

# bearing off
b = pos({6: 1, 3: 2, 1: 2}, {24: 15}, off=(10, 0))
got = plays(b, 1, 6, 2)
check('6/off 3/1' in got or '3/1 6/off' in got, f'bearing off exactly: {got}')
b = pos({4: 1, 2: 1}, {24: 15}, off=(13, 0))
got = plays(b, 1, 6, 5)
check(got == ['4/off 2/off'], f'a higher die bears off from the highest point: {got}')
b = pos({7: 1, 4: 1}, {24: 15}, off=(13, 0))
got = plays(b, 1, 6, 1)
check(all('off' not in x.split()[0] for x in got), f'no bearing off with a checker outside the home board: {got}')

# results
b = pos({}, {1: 15}, off=(15, 0))
check(R.result(b, 1) == 3, 'a backgammon: the loser still in the winner\'s home board')
b = pos({}, {12: 15}, off=(15, 0))
check(R.result(b, 1) == 2, 'a gammon: the loser has borne off nothing')
b = pos({}, {20: 5}, off=(15, 10))
check(R.result(b, 1) == 1, 'a single game')

# ---------------------------------------------------------------- engine
b = R.new()
for (d1, d2), want in (((3, 1), '8/5 6/5'), ((4, 2), '8/4 6/4'), ((6, 1), '13/7 8/7')):
    m = str(R.text(E.think(b, 1, R.dice_list(d1, d2), 3)))
    check(sorted(m.split()) == sorted(want.split()), f'opening {d1}-{d2}: {m} (makes the point)')
race_ahead = pos({6: 5, 5: 5, 4: 5}, {19: 5, 20: 5, 21: 5})
check(E.evaluate(race_ahead, 1) > E.evaluate(pos({6: 15}, {22: 15}), 1) - 9999, 'a race is scored')
check(E.evaluate(pos({1: 15}, {19: 15}), 1) > E.evaluate(pos({6: 15}, {24: 15}), 1), 'fewer pips is better in a race')

L.execute('''
function sliced(level)
  local R, E = __TEST.api.R, __TEST.api.E
  local b = R.new()
  local t, yields = 0, 0
  local co = coroutine.create(function()
    return E.think(b, 1, R.dice_list(6, 6), level, { clock = function() t = t + 7; return t end, slice_ms = 200 })
  end)
  local ok, res = coroutine.resume(co)
  while coroutine.status(co) ~= 'dead' do yields = yields + 1; ok, res = coroutine.resume(co) end
  return yields, R.key(b) == R.key(R.new()), res
end
function selfplay(l1, l2, seed)
  local R, E = __TEST.api.R, __TEST.api.E
  math.randomseed(seed)
  local b, s, turns, bad = R.new(), 1, 0, false
  while true do
    local a, c = math.random(6), math.random(6)
    local mv = E.think(b, s, R.dice_list(a, c), s == 1 and l1 or l2, {})
    for _, m in ipairs(mv) do R.step(b, s, m) end
    for _, x in ipairs({ 1, -1 }) do
      local n = b[R.bar(x)] + b[R.off(x)]
      for i = 1, 24 do local v = b[R.idx(x, i)] * x; if v > 0 then n = n + v end end
      if n ~= 15 then bad = true end
    end
    if R.won(b, s) then return s, R.result(b, s), turns, bad end
    s = -s; turns = turns + 1
    if turns > 1500 then return 0, 0, turns, bad end
  end
end
''')
y, kept, res = L.eval('sliced')(4)
check(int(y) > 0 and kept and len(list(res.values())) == 4, f'Hard thinks in slices ({y} yields) and leaves the position as it was')

t0 = time.time()
wins, bad, lens = 0, False, []
for seed in range(1, 31):
    w, pts, turns, b_ = L.eval('selfplay')(3, 1, seed)
    wins += 1 if w == 1 else 0
    bad = bad or b_
    lens.append(int(turns))
check(wins >= 24 and not bad, f'Medium beats Beginner {wins} of 30 (15 checkers each throughout); turns {min(lens)}-{max(lens)}, {time.time() - t0:.1f} s')
t0 = time.time()
wins = 0
for seed in range(1, 9):
    w, pts, turns, b_ = L.eval('selfplay')(4, 3, 100 + seed)
    wins += 1 if w == 1 else 0
check(wins >= 3, f'Hard against Medium: {wins} of 8 ({time.time() - t0:.1f} s)')

# ---------------------------------------------------------------- the game by taps
run = lambda: int(L.eval('run_timers')())


def tap_point(p, deep=False):
    x, top = A().point_x(p)
    x = int(x) + 17
    y = (BT + 30 if top else BB - 30)
    g.tap(x, y)


def tap_tray():
    g.tap(464, BB - 60)


def targets():
    return sorted(int(k) for k in A().targets().keys())


A().new_match('ai', 3, 3, False)
A().rig(L.table_from([lt(3, 1)]))
g.tap_label('Roll')
check(A().phase() == 'move' and A().side() == 1 and list(A().left().values()) == [3, 1], 'the opening roll: you 3, the reader 1, you start with 3-1')
tap_point(8)
check(targets() == [4, 5, 7], f'a checker on 8 can reach 7, 5 and, with both dice, 4: {targets()}')
tap_point(5)
check(int(A().b()[5]) == 1 and int(A().b()[8]) == 2 and targets() == [], 'tap 8 then 5: a checker moves with the 3')
tap_point(6)
tap_point(5)
run()
check(A().side() == 1 and A().phase() == 'roll' and int(A().b()[5]) == 2, 'the 5 point made; the reader replies, then it is your roll')
key_after = key(A().b())
check(total(A().b(), 1) == 15 and total(A().b(), -1) == 15, 'still 15 checkers each')
reader_msg = str(A().msg())
check(reader_msg.startswith('The reader '), f'the reader\'s play is shown: {reader_msg}')
g.tap_label('Undo')
check(A().phase() == 'move' and key(A().b()) == key(R.new()) and list(A().left().values()) == [3, 1],
      'Undo: back to your 3-1 at the start')
tap_point(8); tap_point(5); tap_point(6); tap_point(5)
run()
check(key(A().b()) == key_after, 'the reader rolls the same dice again after Undo (the luck never changes)')

# taps that miss a little: the points are 34 px wide
def fresh(d1, d2):
    A().set(key(R.new()), 1, 'roll')
    A().rig(L.table_from([lt(d1, d2)]))
    g.tap_label('Roll')


def at(p):
    return int(A().b()[p])


fresh(3, 1)
tap_point(8)
x5, _y = A().slot(5, 0)
g.tap(int(x5) + 9, BB + 12)                       # under the board, a little right of 5's mark
check(at(5) == 1 and at(8) == 2, 'a tap just off a marked point plays it')
tap_point(6)
tap_point(6)
check(at(5) == 2 and at(6) == 4, 'the picked checker tapped again moves with the die left (6/5)')
run()
fresh(3, 1)
x13, _y = A().slot(13, 0)
g.tap(int(x13) + 6, BT - 6)                       # above the board, over 13's stack
check(A().sel() == 13, f'a tap just off a checker picks it: {A().sel()}')
g.tap(470, 30)                                    # far away: nothing picked
fresh(3, 1)
x, _t = A().point_x(5)
g.tap(int(x) + 17, BB - 16)
check(A().sel() is None and 'More than one' in str(A().msg()) and at(5) == 0, 'an empty point two checkers can reach: asks which')
x, _t = A().point_x(7)
g.tap(int(x) + 17, BB - 16)
check(at(7) == 1 and at(8) == 2, 'an empty point only one checker can reach: it moves there (8/7)')
x, _t = A().point_x(5)
g.tap(int(x) + 17, BB - 16)
check(at(5) == 1 and at(8) == 1, 'and with the 3 left only 8 reaches 5: 8/5')
run()

# the bar is picked by itself
A().set(key(pos({13: 14}, {19: 1, 24: 14}, bar=(1, 0))), 1, 'roll')
A().rig(L.table_from([lt(6, 2)]))
g.tap_label('Roll')
check(int(A().sel()) == 25 and 19 in targets() and 23 in targets(), f'a checker on the bar is picked by itself: {targets()}')
tap_point(19)
check(int(A().b()[R.bar(-1)]) == 1 and int(A().b()[19]) == 1, 'entering on 19 hits the blot there')

# no move: the turn passes
A().set(key(pos({13: 14}, {19: 2, 20: 2, 21: 2, 22: 2, 23: 2, 24: 2}, bar=(1, 0))), 1, 'roll')
A().rig(L.table_from([lt(6, 1), lt(2, 1)]))
g.tap_label('Roll')
check('no move' in str(A().msg()) and A().side() == -1, f'no move with 6-1 against a closed board, the turn passes: {A().msg()}')
run()

# bearing off to the end of a game: a gammon, the match score
A().new_match('ai', 2, 3, False)
A().set(key(pos({2: 1, 1: 1}, {12: 15}, off=(13, 0))), 1, 'roll')
A().rig(L.table_from([lt(2, 1)]))
g.tap_label('Roll')
tap_point(2)
check(0 in targets(), 'the tray is a target when a checker can bear off')
tap_tray()
tap_point(1); tap_tray()
sc = A().score()
check(A().phase() == 'over' and int(sc[1]) == 2 and 'Game over' in g.texts(), f'the last checker off: a gammon, 2 points ({int(sc[1])})')
g.tap_label('Next game')
check(A().phase() == 'opening', 'Next game')

# the cube: you double, the reader takes or passes; the Crawford game
A().new_match('ai', 3, 5, True)
A().set(key(R.new()), 1, 'roll')
check('Double' in g.texts(), 'with the cube on, Double is offered before the roll')
g.tap_label('Double')
c, o = A().cube()
check(int(c) == 2 and int(o) == -1 and 'Double' not in g.texts(), f'the reader takes an even position: cube {int(c)}, owned by the reader')
A().new_match('ai', 3, 5, True)
A().set(key(pos({1: 2}, {24: 15}, off=(13, 0))), 1, 'roll')
g.tap_label('Double')
check(A().phase() == 'over' and int(A().score()[1]) == 1, 'the reader passes a lost position: you win 1 point')
A().new_match('ai', 3, 3, True)
A().set(key(pos({1: 2}, {24: 15}, off=(13, 0))), 1, 'roll')
A().score()[1] = 1
g.tap_label('Double')            # passed: 2-0 in a match to 3
g.tap_label('Next game')
check('Crawford' in ' '.join(g.texts()) and 'Double' not in g.texts(), 'one point from the match: the Crawford game, no doubling')

# the game kept
A().new_match('ai', 2, 0, False)
A().rig(L.table_from([lt(5, 2)]))
g.tap_label('Roll')
k0, side0, left0 = key(A().b()), int(A().side()), list(A().left().values())
g.L.execute('on_leave(ctx)')
g.restart()
check(key(A().b()) == k0 and int(A().side()) == side0 and list(A().left().values()) == left0 and A().phase() == 'move',
      'the game is kept: board, dice left and whose move')

# Back: on the board the host may offer to exit; with a box open it closes the box
back = L.eval("function(ph) return on_input(ctx, { type = 'key', key = 'back', phase = ph }) end")
check(back('up') is False, 'Back on the board returns false (the host offers to exit)')
g.tap_label('Menu')
check(back('up') is True and 'How to play' not in g.texts(), 'Back closes a box')

# Hint, and the draw commands of a crowded board
A().set(key(R.new()), 1, 'roll')
A().rig(L.table_from([lt(6, 5)]))
g.tap_label('Roll')
g.tap_label('Hint')
run()
check(A().hint() is not None and str(A().msg()).startswith('Hint: '), f'Hint: {A().msg()}')
A().set(key(pos({6: 9, 5: 3}, {19: 9, 20: 2}, bar=(2, 2), off=(1, 2))), 1, 'roll')
n = g.commands()
check(n < 900, f'draw commands on a crowded board: {n}')

print('\n' + ('all passed' if not fails else f'{len(fails)} FAILED'))
sys.exit(1 if fails else 0)
