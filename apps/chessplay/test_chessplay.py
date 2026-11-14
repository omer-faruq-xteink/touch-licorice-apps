"""Offline test of Chess (gamekit harness, with ctx:after timers run by hand): the rules (perft of
standard positions, mate, stalemate, the draws, SAN), the engine (mates and free pieces found, the
position left as it was, thinking in slices within its time), and the game by taps: a move and the
reply, Undo, a wrong tap, promotion, checkmate, playing Black, Hint, the game kept over a restart,
and the draw commands of a busy screen.

  python -I apps/chessplay/test_chessplay.py
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
ctx.budget = { extend = function() return true end }
steps = 0
function run_timers(max)
  local n = 0
  while #timers > 0 and n < (max or 100000) do
    local f = table.remove(timers, 1); f(ctx); n = n + 1
  end
  steps = n
  return n
end
''')
g.restart()
A = lambda: g.api
R = lambda: g.api.R
SQ = 56


def run():
    return L.eval('run_timers')()


def tap_sq(name):
    x, y = (int(v) for v in A().square_xy(R().square(name)))
    g.tap(x + SQ // 2, y + SQ // 2)


def move(a, b):
    tap_sq(a)
    tap_sq(b)


def fen():
    return R().to_fen(A().pos())


# ---------------------------------------------------------------- rules
P = R()
for f, want in [(P.START, [20, 400, 8902]),
                ('r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1', [48, 2039]),
                ('8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1', [14, 191, 2812]),
                ('r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1', [6, 264]),
                ('rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8', [44, 1486])]:
    p = P.from_fen(f)
    got = [P.perft(p, d) for d in range(1, len(want) + 1)]
    assert got == want, (f, got, want)
    assert P.to_fen(p) == f, (P.to_fen(p), f)

outcome = lambda f: P.outcome(P.from_fen(f), None)
assert outcome('rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3') == (-1, 'checkmate')
assert outcome('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1') == (0, 'stalemate')
assert outcome('8/8/4k3/8/8/2K5/8/8 w - - 0 1') == (0, 'too little material')
assert outcome('8/8/4k3/8/8/2KN4/8/8 w - - 0 1') == (0, 'too little material')
assert outcome('8/8/4k3/8/8/2KR4/8/8 w - - 0 1') is None
assert outcome('8/8/4k3/8/8/2KR4/8/8 w - - 100 80') == (0, 'the 50-move rule')

san = lambda f, u: P.san(P.from_fen(f), P.from_uci(P.from_fen(f), u))
assert san(P.START, 'g1f3') == 'Nf3'
assert san('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1', 'e1g1') == 'O-O'
assert san('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1', 'e1c1') == 'O-O-O'
assert san('4k3/P7/8/8/8/8/8/4K3 w - - 0 1', 'a7a8q') == 'a8=Q+'
assert san('k7/8/8/8/8/8/4K3/R6R w - - 0 1', 'a1d1') == 'Rad1'        # two rooks can reach d1
assert san('k7/8/8/8/8/8/8/R3K2R w - - 0 1', 'a1d1') == 'Rd1'          # the king blocks the other
assert san('rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq - 0 2', 'd8h4') == 'Qh4#'
assert san('rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3', 'e5f6') == 'exf6'

# ---------------------------------------------------------------- engine
E = A().E
L.execute('fixed_half = function() return 0.5 end')
def best(f, level, limit=3000):
    p = P.from_fen(f)
    t = L.table_from({'limit_ms': limit, 'random': L.eval('fixed_half')})
    m, score, depth, nodes = E.think(p, level, t)
    assert P.to_fen(p) == f, 'the search must leave the position as it was'
    return P.uci(m), score, depth
for lv in (2, 3, 4):
    assert best('r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4', lv)[0] == 'h5f7'      # Qxf7#
    assert best('6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1', lv)[0] == 'd1d8'                                 # back rank
    assert best('rnb1kbnr/pppp1ppp/8/4p1q1/3P4/2N5/PPP1PPPP/R1BQKBNR w KQkq - 0 1', lv)[0] == 'c1g5'       # the free queen
    m, sc, _d = best('6k1/5ppp/8/8/8/8/5PPP/3R2K1 b - - 0 1', lv)                                         # escape: no blunder
    assert sc > -E.MATE + 1000, (lv, m, sc)
assert best('7k/8/8/8/8/8/8/K7 w - - 0 1', 3) is not None

# thinking in slices: a clock that moves 5 ms a call makes the search yield and stop on time
L.execute('''
tclock = 0
function tick_clock() tclock = tclock + 5; return tclock end
function slices(level, limit)
  local p = A_R.from_fen(A_R.START)
  local co = coroutine.create(function() return A_E.think(p, level, { clock = tick_clock, slice_ms = 200, limit_ms = limit }) end)
  local n, ok, m = 0
  repeat ok, m = coroutine.resume(co); assert(ok, m); n = n + 1 until coroutine.status(co) == 'dead'
  return n, m, tclock
end
''')
L.globals().A_R, L.globals().A_E = P, E
n, m, spent = L.eval('slices')(4, 3000)
assert n > 5 and m and spent <= 3000 + 400, (n, m, spent)

# ---------------------------------------------------------------- the game by taps
t = g.texts()
assert 'Chess' in t and 'Your move' in t and A().mode() == 'ai' and A().me() == 1, t
tap_sq('e2')
assert A().sel() == P.square('e2')
assert g.circles() and len(g.circles()) == 2, g.circles()                 # e3 and e4 marked
tap_sq('e4')
assert len(A().history()) == 1 and A().thinking(), 'the reader thinks after your move'
assert 'The reader is thinking…' in g.texts()
run()
assert len(A().history()) == 2 and not A().thinking() and A().pos().side == 1, len(A().history())
assert g.store['game.txt'].count(' ') >= 1 and 'e2e4' in g.store['game.txt'], g.store['game.txt']
g.no_err()

# a wrong tap: a square the piece cannot reach drops the selection
move('d2', 'd5')
assert len(A().history()) == 2 and A().sel() is None

# Undo: back to your move (your move and the reply)
g.tap_label('Undo')
assert len(A().history()) == 0 and A().pos().side == 1 and fen() == P.START

# the game kept over a restart
move('d2', 'd4'); run()
before = fen()
g.restart()
assert fen() == before and len(A().history()) == 2, (fen(), before)

# promotion: the pawn asks what it becomes
A().set_position('8/P6k/8/8/8/8/8/K7 w - - 0 1')
move('a7', 'a8')
assert 'Promote to' in g.texts(), g.texts()
g.tap_label('Knight')
assert A().pos().b[P.square('a8')] == 2, A().pos().b[P.square('a8')]
run()

# two players: fool's mate by taps
g.tap_label('New game'); g.tap_label('Two players')
assert A().mode() == 'two' and fen() == P.START
for a, b in [('f2', 'f3'), ('e7', 'e5'), ('g2', 'g4'), ('d8', 'h4')]:
    move(a, b)
assert A().result() and A().result().r == -1 and A().result().why == 'checkmate'
t = g.texts()
assert 'Checkmate' in t and any('Black wins' in x for x in t), t
move('e2', 'e4')
assert len(A().history()) == 4, 'no moves after the end'
g.tap_label('Undo')
assert len(A().history()) == 3 and not A().result()

# playing Black: the reader opens, the board is turned (a1 top right)
g.tap_label('New game'); g.tap_label('Medium'); g.tap_label('Black')
assert A().me() == -1 and A().level() == 3 and A().thinking()
run()
assert len(A().history()) == 1 and A().pos().side == -1
x, y = (int(v) for v in A().square_xy(P.square('a1')))
assert x > 400 and y < 200, (x, y)

# Hint: a good move framed
g.tap_label('Hint')
run()
assert A().hint() and any(s.startswith('Hint:') for s in g.texts()), g.texts()

# New game, Cancel: nothing changes
h = len(A().history())
g.tap_label('New game'); g.tap_label('Cancel')
assert len(A().history()) == h

# a busy screen: a queen picked in an open middle game, under the host's ~1024 draw commands
A().set_position('r1b1k2r/ppp2ppp/2n2q2/2bpp3/3PP3/2N2Q2/PPP2PPP/R1B1KB1R w KQkq - 0 1')
L.execute('__TEST.api.new_game = nil')
tap_sq('f3')
n = g.commands()
assert n < 900, n
g.no_err()
# Back (down, then up: the host reads only the up event's answer): closes a box; on the board it is
# left to the host, which offers to exit
back = lambda phase: g.L.eval(f"on_input(ctx, {{type='key', key='back', phase='{phase}'}})")
g.tap_label('New game')
assert 'Two players' in g.recs()
assert back('down') is True and back('up') is True and 'Two players' not in g.recs(), g.texts()
assert back('down') is True and back('up') is False
g.no_err()
print(f'chessplay: all tests passed ({n} draw commands on a busy screen, {spent} ms of slices)')
