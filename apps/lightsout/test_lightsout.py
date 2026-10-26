"""Offline test of Lights Out (gamekit harness): puzzles are solvable with their target, presses,
undo, hint, levels, the win box, rings for lit squares, save and reload.

  python -I apps/lightsout/test_lightsout.py
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

g = Game(HERE)
CELL, GX, GY = 84, 30, 150
def cell_xy(i): return GX + (i % 5) * CELL + CELL // 2, GY + (i // 5) * CELL + CELL // 2
def state(): return tuple(int(v) for v in g.api.state())   # g.api: the running chunk's
def bits(x): return [i for i in range(25) if (x >> i) & 1]

board, moves, par, level = state()
assert board != 0 and moves == 0 and par >= 6 and level == 2, state()            # Normal: target at least 6
t = g.texts()
assert 'Lights Out' in t and f'Moves 0    Target {par}    Normal' in t, t
assert 'New' in t and 'Undo' in t and 'Hint' in t and 'Normal' in t
lit = len(bits(board))
assert len(g.circles()) == lit * 8, (len(g.circles()), lit)                       # two thick rings per light
assert not any(r.fill for r in g.rects())                                         # nothing filled black

# a press switches the square and its neighbours; Undo takes it back
g.tap(*cell_xy(12))
b2, m2, _, _ = state()
assert b2 == board ^ int(g.api.press_mask(12)) and m2 == 1
g.tap_label('Undo')
assert state()[:2] == (board, 0)

# hint: the framed square is part of a fewest-press solution
g.tap_label('Hint')
assert 'Hint: press the framed square.' in g.texts()
x = int(g.api.solve(board))
first = bits(x)[0]
g.tap(*cell_xy(first))
assert bin(int(g.api.solve(state()[0]))).count('1') == par - 1

# solve with the fewest presses from here: the win box says so
for i in bits(int(g.api.solve(state()[0]))):
    g.tap(*cell_xy(i))
t = g.texts()
assert 'All lights are off!' in t and 'You matched the fewest presses.' in t, t
assert re.search(r'solved=1', g.store['game.txt'])
g.tap_label('New')
assert state()[0] != 0 and state()[1] == 0

# levels: Hard from the next New puzzle
g.tap_label('Normal')
assert 'Hard: from the next New puzzle.' in g.texts()
g.tap_label('New')
assert state()[2] >= 10 and state()[3] == 3, state()
g.tap_label('Hard'); g.tap_label('New')
assert state()[3] == 1 and state()[2] >= 3

# save and reload: the same board, moves and history (Undo still works)
g.tap(*cell_xy(0)); g.tap(*cell_xy(24))
before = state()
g.restart()
assert state() == before
g.tap_label('Undo')
assert state()[1] == before[1] - 1

# a few hundred puzzles: each has a solution no longer than the presses that made it
for _ in range(200):
    g.tap_label('New')
    b, _, p, _ = state()
    sol = int(g.api.solve(b))
    assert sol is not None and bin(sol).count('1') == p
g.no_err()
print('lightsout tests passed')
