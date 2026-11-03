"""Offline test of Queens (gamekit harness; a stand-in for the package's data section): every bank
puzzle is settled by reasoning alone at its level (so its solution is the only one), the harder
banks not by the first level; the app reads the banks in order, plays a puzzle by taps (cross,
piece, clear), rings touching pieces and too many in a row, dots the cells ruled out, Undo, Hint,
keeps its place and marks across a restart, switches to Star Battle, leaves Back on its main
screen to the host, and stays under the draw-command limit on the largest board.

  python -I apps/queens/test_queens.py
"""
import importlib.util, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

spec = importlib.util.spec_from_file_location('make_bank', os.path.join(HERE, 'make_bank.py'))
mb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mb)

DATA = os.path.join(HERE, 'data')
banks = []
for name, n, k, level, harder, _seed in mb.BANKS:
    lines = open(os.path.join(DATA, name + '.txt'), encoding='ascii').read().split('\n')[:-1]
    assert len({len(l) for l in lines}) == 1 and len(lines[0]) == n * n and len(set(lines)) == len(lines), name
    for line in lines:
        assert sum(ch.isupper() for ch in line) == n * k, (name, line)
        assert mb.solved_by_reasoning(line, level), (name, line)
    if harder:
        for line in lines[::10]:
            B, kk, regs, _stars = mb.parse(line)
            assert mb.solve(B, kk, regs, 1) > 0, (name, line)
    banks.append((name, n, k, lines))
print('banks: every puzzle settled by reasoning at its level')

tsv = ''.join(f'{name}.txt\t{len(lines)}\t{n * n + 1}\t{name}\\n' for name, n, k, lines in reversed(banks))
g = Game(HERE)
g.L.execute(f'''
local function text_reader(s)
  local pos = 1
  return {{ read_line = function(self) if pos > #s then return nil end local e = s:find('\\n', pos, true) or #s + 1
            local l = s:sub(pos, e - 1); pos = e + 1; return l end, close = function(self) end }}
end
ctx.package = {{ open_text = function(self, name, opts)
  if name == 'banks.tsv' then return text_reader("{tsv}") end
  local f = io.open([[{DATA.replace(os.sep, '/')}/]] .. name, 'rb')
  if not f then return nil end
  return {{ read_line = function(self) return f:read('l') end, seek = function(self, p) f:seek('set', p); return true end,
            close = function(self) f:close() end }}
end }}
''')
g.restart()
A = lambda: g.api
# the first run opens with the rules
assert 'How to play' in g.texts(), g.texts()
g.tap_label('Close')
assert [str(b.name) for b in A().banks().values()] == [b[0] for b in banks]
assert str(A().bank().name) == 'queens-6x6' and int(A().idx()) == 1
g.no_err()

name, n, k, lines = banks[0]
line = lines[0]
pz = A().pz()
assert int(pz.n) == n and int(pz.k) == 1
assert all(bool(pz.sol[i + 1]) == ch.isupper() for i, ch in enumerate(line))
assert all(int(pz.region[i + 1]) == ord(ch.lower()) - 96 for i, ch in enumerate(line))
assert 'Queens' in g.texts() and 'None touch.   0 of 6 queens placed' in g.texts(), g.texts()
mark = lambda i: A().mark()[i]


def tap_cell(i):
    x, y = (int(v) for v in A().cell_xy(i))
    C = int(A().cell_px())
    g.tap(x + C // 2, y + C // 2)


def piece(i):
    """tap a cell until it holds a piece"""
    for _ in range(3):
        if mark(i) == 'q':
            return
        tap_cell(i)
    assert mark(i) == 'q'


def clear(i):
    for _ in range(3):
        if mark(i) is None:
            return
        tap_cell(i)
    assert mark(i) is None


# a tap: cross, piece, nothing
tap_cell(1)
assert mark(1) == 'x'
tap_cell(1)
assert mark(1) == 'q' and 'None touch.   1 of 6 queens placed' in g.texts()
# the cells it rules out are dotted: around it, its row, column and region
out = A().ruled_out()
assert out[2] and out[n + 1] and out[n + 2] and out[n * (n - 1) + 1] and out[n]
tap_cell(1)
assert mark(1) is None

# two queens touching are ringed; two in a row too
piece(1); piece(n + 2)
bad = A().conflicts()[0]
assert bad[1] and bad[n + 2] and 'touch' in str(A().msg()), A().msg()
assert len(g.circles()) >= 2
clear(n + 2)
piece(3)
bad = A().conflicts()[0]
assert bad[1] and bad[3] and 'Too many queens in a row' in str(A().msg()), A().msg()
# Undo takes back the taps one by one
before = dict(A().mark())
g.tap_label('Undo')
assert mark(3) == 'x'
clear(3); clear(1)
assert not any(v for v in A().mark().values())

# Hint removes a wrong queen, then places a right one
wrong = next(i + 1 for i, ch in enumerate(line) if not ch.isupper())
piece(wrong)
g.tap_label('Hint')
assert mark(wrong) is None and 'wrong' in str(A().msg())
g.tap_label('Hint')
hinted = [i for i in range(1, n * n + 1) if mark(i) == 'q']
assert len(hinted) == 1 and line[hinted[0] - 1].isupper()
tap_cell(hinted[0])
assert mark(hinted[0]) == 'q' and 'hint' in str(A().msg())

# solved by taps
for i, ch in enumerate(line):
    if ch.isupper():
        piece(i + 1)
assert A().solved() and 'Solved' in str(A().msg()) and 'Hints 1' in str(A().msg()), A().msg()
assert A().done()['queens-6x6'][1]
g.no_err()
print('queens 6x6 no. 1 solved by taps')

# Next; a cross and a queen kept across a restart
g.tap_label('Next')
assert int(A().idx()) == 2 and not A().solved()
line2 = lines[1]
q = line2.index(next(ch for ch in line2 if ch.isupper())) + 1
piece(q)
tap_cell(1 if q != 1 else 2)                  # a cross
saved = {int(i): str(v) for i, v in A().mark().items() if v}
g.restart()
assert int(A().idx()) == 2 and {int(i): str(v) for i, v in A().mark().items() if v} == saved
assert A().done()['queens-6x6'][1]

# Back: closes the box; on the main screen it is left to the host
back = lambda phase: g.L.eval(f"on_input(ctx, {{type='key', key='back', phase='{phase}'}})")
g.tap_label('More')
back('down')
assert back('up') is True and g.api.dots() is not None
assert 'Previous' not in g.texts()
back('down')
assert back('up') is False, 'Back on the main screen leaves it to the host'

# dots can be turned off
g.tap_label('More')
g.tap_label('Dots: on')
assert A().dots() is False
g.restart()
assert A().dots() is False

# Star Battle 10x10: two stars; the largest board under the draw-command limit with every cell marked
g.tap_label('More')
g.tap_label('Stars 10x10')
assert str(A().bank().name) == 'stars-10x10' and int(A().pz().k) == 2
assert 'Star Battle' in g.texts() and 'None touch.   0 of 20 stars placed' in g.texts() and 'Two stars per row, column, region.' in g.texts(), g.texts()
sname, sn, sk, slines = banks[-1]
sline = slines[int(A().idx()) - 1]
for i, ch in enumerate(sline):
    if not ch.isupper():
        tap_cell(i + 1)                      # a cross everywhere else
assert g.commands() < 1024, g.commands()
for i, ch in enumerate(sline):
    if ch.isupper():
        piece(i + 1)
assert A().solved(), A().msg()
assert g.commands() < 1024, g.commands()
g.no_err()
# with dots and nothing marked yet, still under the limit
g.tap_label('Next')
g.tap_label('More')
g.tap_label('Dots: off')
for i, ch in enumerate(slines[int(A().idx()) - 1]):
    if ch.isupper():
        piece(i + 1)
assert g.commands() < 1024, g.commands()
g.tap_label('More')
g.tap_label('6x6')
assert str(A().bank().name) == 'queens-6x6' and int(A().idx()) == 2
print('all good')
