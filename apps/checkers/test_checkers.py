"""Offline test of Checkers (gamekit harness, ctx:after timers run by hand): both rule sets (perft
of English checkers from the start; Dama's longest capture, flying kings, no turning back, pieces
taken at once, crowning at the end; checkers' crowning ending a move), the end of a game, the
engine (a free piece taken, the position left as it was, thinking in slices), and the game by taps:
a move and the reply, a wrong piece while a capture is due, Undo, Dama for two players, playing
the second side, Hint, the game kept, and the draw commands.

  python -I apps/checkers/test_checkers.py
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

g = Game(HERE)
L = g.L
L.execute('''
timers = {}
ctx.after = function(self, ms, fn) assert(self == ctx); timers[#timers + 1] = fn; return true end
function run_timers()
  local n = 0
  while #timers > 0 do local f = table.remove(timers, 1); f(ctx); n = n + 1 end
  return n
end
''')
g.restart()
A = lambda: g.api
R = g.api.R
E = g.api.E
SQ = 56


def run():
    return L.eval('run_timers')()


def key(side, pieces):
    """'1' or '2' and 64 squares from {'d4': 'o', ...}: o O a man / king of side 1, x X of side -1"""
    b = ['.'] * 64
    for name, ch in pieces.items():
        b[(int(name[1]) - 1) * 8 + (ord(name[0]) - 97)] = ch
    return ('1' if side > 0 else '2') + ''.join(b)


def moves(variant, side, pieces):
    p = R.from_key(variant, key(side, pieces))
    return sorted(R.text(m) for m in R.moves(p).values()), p


def tap_sq(name):
    x, y = (int(v) for v in A().square_xy(R.square(name)))
    g.tap(x + SQ // 2, y + SQ // 2)


def move(a, b):
    tap_sq(a)
    tap_sq(b)


# ---------------------------------------------------------------- rules
p = R.new(R.CHECKERS)
assert [R.perft(p, d) for d in range(1, 6)] == [7, 49, 302, 1469, 7361]
p = R.new(R.DAMA)
assert [R.perft(p, d) for d in range(1, 4)] == [8, 64, 708]
assert sum(1 for v in R.new(R.DAMA)['b'].values() if v != 0) == 32
assert sum(1 for v in R.new(R.CHECKERS)['b'].values() if v != 0) == 24

# Dama: the line taking more must be played (sideways twice beats forward once)
got, _ = moves(R.DAMA, 1, {'c3': 'o', 'c4': 'x', 'd3': 'x', 'e4': 'x'})
assert got == ['c3xe3xe5'], got
# Dama: a king takes from a distance and lands on any empty square beyond
got, _ = moves(R.DAMA, 1, {'a1': 'O', 'a5': 'x', 'h8': 'x'})
assert got == ['a1xa6', 'a1xa7', 'a1xa8'], got
# Dama: no turning back: having taken d6 upward, the king may not come down for d2
got, _ = moves(R.DAMA, 1, {'d4': 'O', 'd6': 'x', 'd2': 'x'})
assert got == ['d4xd1', 'd4xd7', 'd4xd8'], got
# Dama: a king's line goes on round corners, three pieces in one move
got, _ = moves(R.DAMA, 1, {'a1': 'O', 'a3': 'x', 'c5': 'x', 'f5': 'x', 'f2': 'x'})
assert got and all(len(t.split('x')) == 4 for t in got), got
# Dama: a man reaching the far row while taking finishes as a man, crowned at the end
got, pp = moves(R.DAMA, 1, {'a6': 'o', 'a7': 'x', 'b8': 'x'})
assert got == ['a6xa8xc8'], got
m = R.moves(pp)[1]
assert m.promo, 'crowned when the line ends'
R.make(pp, m)
assert pp.b[R.square('c8')] == 2 and pp.b[R.square('b8')] == 0
# Dama: men move forward and sideways, never back
got, _ = moves(R.DAMA, 1, {'d4': 'o', 'h8': 'x'})
assert got == ['d4-c4', 'd4-d5', 'd4-e4'], got
# checkers: a man crowned by a jump stops, even with another jump in reach
got, _ = moves(R.CHECKERS, 1, {'c6': 'o', 'd7': 'x', 'f7': 'x'})
assert got == ['c6xe8'], got
# checkers: a capture goes on while it can; captures are compulsory
got, _ = moves(R.CHECKERS, 1, {'c3': 'o', 'd4': 'x', 'f6': 'x', 'a3': 'o'})
assert got == ['c3xe5xg7'], got
# checkers: a king moves one square in any diagonal
got, _ = moves(R.CHECKERS, 1, {'d4': 'O', 'a7': 'x'})
assert got == ['d4-c3', 'd4-c5', 'd4-e3', 'd4-e5'], got
# the end: no move left loses; no pieces left loses
# a white man on a1 (side -1 moves down) cannot move: White has lost
assert R.outcome(R.from_key(R.CHECKERS, key(-1, {'a1': 'x', 'h8': 'o'})), None) == (1, 'no move left')
assert R.outcome(R.from_key(R.DAMA, key(-1, {'d4': 'o'})), None) == (1, 'no pieces left')

# ---------------------------------------------------------------- engine
L.execute('half = function() return 0.5 end')
def best(variant, side, pieces, level=3):
    p = R.from_key(variant, key(side, pieces))
    before = R.key(p)
    m, score, depth, nodes = E.think(p, level, L.table_from({'random': L.eval('half'), 'limit_ms': 5000}))
    assert R.key(p) == before, 'the search must leave the position as it was'
    return R.text(m)
# a man that would be taken steps aside... and a free piece is taken (forced anyway)
assert best(R.CHECKERS, 1, {'c3': 'o', 'd4': 'x', 'h8': 'x'}) == 'c3xe5'
# checkers: crown rather than wander
assert best(R.CHECKERS, 1, {'b6': 'o', 'h2': 'x', 'g1': 'O'}, 3) in ('b6-a7', 'b6-c7')
L.execute('''
tclock = 0
function tick_clock() tclock = tclock + 5; return tclock end
function slices(variant)
  tclock = 0
  local p = A_R.new(variant)
  local co = coroutine.create(function() return A_E.think(p, 4, { clock = tick_clock, slice_ms = 200, limit_ms = 3000 }) end)
  local n, ok, m = 0
  repeat ok, m = coroutine.resume(co); assert(ok, m); n = n + 1 until coroutine.status(co) == 'dead'
  return n, m ~= nil, tclock
end
''')
L.globals().A_R, L.globals().A_E = R, E
for v in (R.CHECKERS, R.DAMA):
    n, found, spent = L.eval('slices')(v)
    assert n > 3 and found and spent <= 3500, (v, n, found, spent)

# ---------------------------------------------------------------- the game by taps
t = g.texts()
assert 'Checkers' in t and 'Your move' in t and A().variant() == R.CHECKERS and A().me() == 1, t
tap_sq('c3')
assert A().sel() == R.square('c3') and len(g.circles()) >= 2
tap_sq('d4')
assert len(A().history()) == 1 and A().thinking()
assert 'The reader is thinking…' in g.texts()
run()
assert len(A().history()) == 2 and A().pos().side == 1
assert 'moves=c3-d4' in g.store['game.txt'], g.store['game.txt']
g.no_err()

# Undo: back to your move
g.tap_label('Undo')
assert len(A().history()) == 0 and A().pos().side == 1

# a capture is due: another piece cannot be picked
A().set_position(R.CHECKERS, key(1, {'c3': 'o', 'd4': 'x', 'a1': 'o', 'h8': 'x'}))
tap_sq('a1')
assert A().sel() is None and any('capture must be made' in s for s in g.texts()), g.texts()
move('c3', 'e5')
assert A().pos().b[R.square('d4')] == 0 and A().pos().b[R.square('e5')] == 1
run()

# Dama for two players by taps, kept over a restart
g.tap_label('New game'); g.tap_label('Dama'); g.tap_label('Two players')
assert A().variant() == R.DAMA and A().mode() == 'two'
move('d3', 'd4'); move('e6', 'e5')
assert len(A().history()) == 2, len(A().history())
before = R.key(A().pos())
g.restart()
assert R.key(A().pos()) == before and A().variant() == R.DAMA and len(A().history()) == 2

# the second side against the reader: the reader opens, the board is turned
g.tap_label('New game'); g.tap_label('Checkers'); g.tap_label('Medium'); g.tap_label('White')
assert A().me() == -1 and A().thinking()
run()
assert len(A().history()) == 1 and A().pos().side == -1
x, y = (int(v) for v in A().square_xy(R.square('a1')))
assert x > 400 and y < 200, (x, y)

# Hint
g.tap_label('Hint'); run()
assert A().hint() and any(s.startswith('Hint:') for s in g.texts()), g.texts()

# a full Dama board under the host's ~1024 draw commands, a piece picked
g.tap_label('New game'); g.tap_label('Dama'); g.tap_label('Two players')
tap_sq('d3')
n = g.commands()
assert n < 900, n
g.no_err()
print(f'checkers: all tests passed ({n} draw commands on a full Dama board)')
