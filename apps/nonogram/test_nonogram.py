"""Offline test of Nonograms (gamekit harness): every bank puzzle is line-solvable and decodes the
same in the app, the layout fits every size, solving through taps, X marks (mode and long press),
undo, clear, next / previous, sizes, save and reload.

  python -I apps/nonogram/test_nonogram.py
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
sys.path.insert(0, HERE)
from harness import Game  # noqa: E402
import make_bank  # noqa: E402

# the bank: line-solvable (so one solution), clue counts within the cap, no empty lines
src = open(os.path.join(HERE, 'src', 'bank.lua'), encoding='ascii').read()
caps = {n: cap for n, cap, _f in make_bank.SIZES}
banks = {}
for n, body in re.findall(r'\[(\d+)\] = \{(.*?)\n  \}', src, re.S):
    banks[int(n)] = re.findall(r"'([0-9a-f]+)'", body)
assert sorted(banks) == [5, 8, 10, 12] and all(len(v) == 150 for v in banks.values()), {k: len(v) for k, v in banks.items()}
for n, items in banks.items():
    for h in items:
        bits = bin(int(h, 16))[2:].zfill(len(h) * 4)[:n * n]
        g = [[int(bits[r * n + c]) for c in range(n)] for r in range(n)]
        rows = [make_bank.clues(g[r]) for r in range(n)]
        cols = [make_bank.clues([g[r][c] for r in range(n)]) for c in range(n)]
        assert all(0 < len(x) <= caps[n] for x in rows + cols), (n, h)
        assert make_bank.line_solvable(n, rows, cols), (n, h)
print('bank: 600 puzzles, all line-solvable, clues within the caps')

g = Game(HERE)
def geo(): return [int(v) for v in g.api.geometry()]
def size(): return int(g.api.size())
def sol(): return [int(v) for v in g.api.sol().values()]
def cells(): return [str(v) for v in g.api.cells().values()]
def cell_xy(i):
    cell, gx, gy, _w, _h = geo()
    n = size()
    return gx + (i % n) * cell + cell // 2, gy + (i // n) * cell + cell // 2
long_press = g.L.eval("function(x, y) on_input(ctx, {type='pointer', phase='up', gesture='long', x=x, y=y}) end")
# the device repeats the hold event while the finger stays down
long_hold = g.L.eval("function(x, y) on_input(ctx, {type='pointer', phase='down', x=x, y=y}); "
                     "for k = 1, 4 do on_input(ctx, {type='pointer', phase='hold', gesture='long', x=x, y=y}) end; "
                     "on_input(ctx, {type='pointer', phase='up', x=x, y=y}) end")

# the app decodes the first 10x10 puzzle like the bank says
h = banks[10][0]
bits = bin(int(h, 16))[2:].zfill(len(h) * 4)[:100]
assert sol() == [int(b) for b in bits]
t = g.texts()
assert 'Nonograms' in t and '10x10  1/150    solved 0' in t, t

# layout: every size fits above the buttons, cells large enough to tap
for label, n, min_cell in (('5x5', 5, 70), ('8x8', 8, 44), ('12x12', 12, 28), ('10x10', 10, 34)):
    g.tap_label(f'{size()}x{size()}')
    g.tap_label(label)
    cell, gx, gy, cw, ch = geo()
    assert size() == n and cell >= min_cell and gx - cw >= 0 and gy + n * cell <= 700 - 30, (n, cell, gx, gy, cw, ch)

# fill, X by mode and by long press, clear by a second tap, undo
g.tap(*cell_xy(0))
assert cells()[0] == '#'
g.tap(*cell_xy(0))
assert cells()[0] == '.'
g.tap_label('Fill')                                     # mode: X
g.tap(*cell_xy(1))
assert cells()[1] == 'x'
g.tap_label('X')                                        # back to Fill
long_press(*cell_xy(2))
assert cells()[2] == 'x'
long_hold(*cell_xy(3))
assert cells()[3] == 'x'                                # one X, however long the press
long_hold(*cell_xy(3))
assert cells()[3] == '.'
g.tap_label('Undo'); g.tap_label('Undo'); g.tap_label('Undo'); g.tap_label('Undo')
assert cells()[1] == '.' and cells()[2] == '.' and cells()[3] == '.'
assert not any(r.fill for r in g.rects())               # nothing filled yet
g.tap(*cell_xy(5))
fills = [r for r in g.rects() if r.fill]
cell = geo()[0]
assert len(fills) == 1 and int(fills[0].w) == cell - 2 * max(3, cell // 6)   # a smaller square, not the cell
g.tap_label('Undo')

# solve it by taps: the solved box, Next
for i, v in enumerate(sol()):
    if v:
        g.tap(*cell_xy(i))
t = g.texts()
assert 'Solved!' in t and '10x10 puzzle 1 of 150' in t, t
assert 'solved=' in g.store['state.txt'] and '10:1' in g.store['state.txt']
g.tap_label('Next')
assert int(g.api.idx()) == 2 and cells().count('.') == 100

# progress is kept per puzzle; side buttons step; restart resumes
g.tap(*cell_xy(0)); g.tap(*cell_xy(99))
g.key('right')
assert int(g.api.idx()) == 3
g.key('left')
assert int(g.api.idx()) == 2 and cells()[0] == '#' and cells()[99] == '#'
g.restart()
assert size() == 10 and int(g.api.idx()) == 2 and cells()[0] == '#'
assert '10x10  2/150    solved 1' in g.texts()

# clear asks first
g.tap_label('Clear')
assert 'Clear this puzzle?' in g.texts()
g.tap_label('Cancel')
assert cells()[0] == '#'
g.tap_label('Clear'); g.tap_label('Clear')
assert cells().count('.') == 100
g.no_err()
print('nonogram tests passed')
