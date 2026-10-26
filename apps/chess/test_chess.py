"""Offline test of the Chess puzzles app (gamekit harness, a stand-in for the package's data
section): the first puzzle, solving by taps, a wrong move, Hint, Show, Next, the banks, resuming a
puzzle half way; castling, en passant and promotion; and every puzzle of every bank solved by
taps with the board turned the right way.

  python -I apps/chess/test_chess.py
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

DATA = os.path.join(HERE, 'data').replace(os.sep, '/') + '/'
g = Game(HERE)
g.L.execute(f'''
ctx.package = {{ open_text = function(self, name, opts)
  local f = io.open([[{DATA}]] .. name, 'rb')
  if not f then return nil end
  return {{ read_line = function(self) return f:read('l') end, close = function(self) f:close() end }}
end }}
''')
g.restart()
A = lambda: g.api
SQ = 56


def tap_sq(name):
    x, y = (int(v) for v in A().square_xy(A().sq(name)))
    g.tap(x + SQ // 2, y + SQ // 2)


def moves():
    return list(A().puzzle().moves.values())


def solve_by_taps():
    while not A().done():
        m = moves()[int(A().ply()) - 1]
        tap_sq(m[0:2]); tap_sq(m[2:4])


def bw(k):
    w = (480 - 24 - 24) // 4
    return 12 + (k - 1) * (w + 8) + w // 2, 704 + 30


def board():
    b = A().board()
    return {i: str(b[i]) for i in range(1, 65) if b[i] is not None}


# the first Easy puzzle: the opponent's move made, the solver's side at the bottom
assert int(A().bank()) == 3 and int(A().ply()) == 2
p = A().puzzle()
side = str(p.fen).split()[1]
assert str(A().me()) == ('b' if side == 'w' else 'w')
t = g.texts()
assert 'Chess puzzles' in t and any('to move: find the best move.' in s for s in t), t
assert 'Hint' in t and 'Show' in t and 'Next' in t and 'Easy' in t

# a wrong move: told, nothing moves
before = board()
m = moves()[1]
mine = str(A().me()) == 'w'
dest = int(A().sq(m[2:4]))
names = [f + r for f in 'abcdefgh' for r in '12345678']
wrong = next(n for n in names if int(A().sq(n)) != dest and (int(A().sq(n)) not in before or before[int(A().sq(n))].isupper() != mine))
tap_sq(m[0:2]); tap_sq(wrong)
assert board() == before and 'Not the move. Try again.' in g.texts(), g.texts()

# Hint twice, then Show plays the move
g.tap(*bw(1))
assert list(A().hint().values()) == [A().sq(m[0:2])]
g.tap(*bw(1))
assert list(A().hint().values()) == [A().sq(m[0:2]), A().sq(m[2:4])]
g.tap(*bw(2))
solve_by_taps()
t = ' '.join(g.texts())
assert 'Solved' in t, t

# Next; a puzzle solved first try is counted clean
g.tap(*bw(3))
assert int(A().idx()[3]) == 2 and not A().done()
solve_by_taps()
assert 'Solved (first try)' in ' '.join(g.texts())
assert int(A().solved()[3]) == 2 and int(A().clean()[3]) == 1

# the bank menu: Mate in 2; resume half way after a restart
g.tap(*bw(4)); g.tap_label('Mate in 2')
assert int(A().bank()) == 2
m = moves()
tap_sq(m[1][0:2]); tap_sq(m[1][2:4])
assert int(A().ply()) == 4
g.restart()
assert int(A().bank()) == 2 and int(A().ply()) == 4 and not A().done()
solve_by_taps()
assert A().done()

# castling, en passant, promotion
g.api.set_fen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1')
g.api.apply('e1g1'); g.api.apply('e8c8')
b = board()
assert b[7] == 'K' and b[6] == 'R' and 8 not in b and b[59] == 'k' and b[60] == 'r' and 57 not in b, b
g.api.set_fen('8/8/8/3pP3/8/8/8/k6K w - d6 0 1')
g.api.apply('e5d6')
b = board()
assert b[44] == 'P' and 36 not in b and 37 not in b, b
g.api.set_fen('8/4P3/8/8/8/8/8/k6K w - - 0 1')
g.api.apply('e7e8n')
assert board()[61] == 'N'

# every puzzle of every bank, solved by taps on the board as it is shown
total = 0
for k in range(1, 7):
    A().start(k, 1)
    n = 0
    while True:
        solve_by_taps()
        n += 1
        if n >= 400 or int(A().idx()[k]) >= 400:
            break
        before = int(A().idx()[k])
        A().start(k, before + 1)
        if int(A().idx()[k]) != before + 1:
            break
    total += n
assert total >= 2390, total
g.no_err()
print(f'chess tests passed ({total} puzzles solved by taps)')
