"""Offline test of Hashi (gamekit harness; a stand-in for the package's data section): every bank
puzzle has one solution, reached by the bank's reasoning; the app reads the banks in order of
size, finds the same edges as the generator, plays a solution by taps on the water, refuses a
crossing bridge, Undo, island-to-island taps, keeps its place and the bridges across a restart,
switches level, and stays under the draw-command limit on the largest grid.

  python -I apps/hashi/test_hashi.py
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
for name, n, _isl, level, _seed in mb.BANKS:
    lines = open(os.path.join(DATA, name + '.txt'), encoding='ascii').read().split('\n')[:-1]
    assert len({len(l) for l in lines}) == 1 and len(lines[0]) == n * n
    banks.append((name, n, level, lines))

# every puzzle: one solution, and the bank's reasoning reaches it (a sample of each bank)
for name, n, level, lines in banks:
    for line in lines[::10]:
        num = {(i // n, i % n): int(ch) for i, ch in enumerate(line) if ch != '.'}
        P = mb.Puzzle(n, num)
        assert mb.count_solutions(P) == 1, (name, line)
        assert mb.solve_logic(P, level), (name, line)
print('banks: one solution each, solved by reasoning')

tsv = ''.join(f'{name}.txt\t{len(lines)}\t{n * n + 1}\t{name}\\n' for name, n, _l, lines in reversed(banks))
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
assert [str(b.file) for b in A().banks().values()] == ['7x7-easy.txt', '9x9-medium.txt', '11x11-hard.txt']
assert str(A().bank().file) == '7x7-easy.txt' and int(A().idx()) == 1
g.no_err()


def edges():
    return list(A().grid().edges.values())


def tap_edge(e):
    """a tap on the water of edge e, a quarter cell off a cell centre along the bridge (a crossing
    edge's line runs through the centre)"""
    ed = edges()[e]
    ax, ay = (int(v) for v in A().center(ed.a))
    bx, by = (int(v) for v in A().center(ed.b))
    C = (bx - ax) if ed.h else (by - ay)
    n = A().grid().n
    step = 456 // int(n) // 4
    if ed.h:
        g.tap(ax + 456 // int(n) + step, ay)
    else:
        g.tap(ax, ay + 456 // int(n) + step)


def play(name, n, k):
    line = dict((b[0], b[3]) for b in banks)[name][k - 1]
    P, sol = mb.solution(line, n)
    assert len(edges()) == len(P.edges)
    for e, ed in enumerate(edges()):            # the same edges as the generator, in order
        a, b = P.isl[P.edges[e][0]], P.isl[P.edges[e][1]]
        assert (int(ed.a), int(ed.b)) == (a[0] * n + a[1] + 1, b[0] * n + b[1] + 1)
    for e, v in enumerate(sol):
        for _ in range(v):
            tap_edge(e)
    return sol


sol = play('7x7-easy', 7, 1)
assert A().solved() and 'Solved' in str(A().msg()), A().msg()
assert A().done()['7x7-easy.txt'][1]
g.no_err()
print('easy 1 solved by taps')

# Next, then a crossing bridge refused, Undo, and an island-to-island tap
g.tap_label('Next')
assert int(A().idx()) == 2 and not A().solved()
grid = A().grid()
pair = None
for e in range(len(edges())):
    cr = list(grid.cross[e + 1].values())
    if cr:
        pair = (e, int(cr[0]) - 1)
        break
if pair:
    tap_edge(pair[0])
    tap_edge(pair[1])
    assert int(A().bridges()[pair[1] + 1] or 0) == 0 and 'cross' in str(A().msg())
    g.tap_label('Undo')
    assert int(A().bridges()[pair[0] + 1] or 0) == 0
ed = edges()[0]
for i in (ed.a, ed.b):
    x, y = (int(v) for v in A().center(i))
    g.tap(x, y)
assert int(A().bridges()[1]) == 1
g.tap_label('Restart')
assert all(int(v) == 0 for v in A().bridges().values()) if len(A().bridges()) else True

# kept across a restart: the place and the bridges
tap_edge(0)
g.restart()
assert int(A().idx()) == 2 and int(A().bridges()[1]) == 1
assert A().done()['7x7-easy.txt'][1]

# levels: the hard bank, solved, under the draw-command limit
g.tap_label('More')
g.tap_label('Hard')
assert str(A().bank().file) == '11x11-hard.txt'
assert g.commands() < 1024, g.commands()
play('11x11-hard', 11, int(A().idx()))
assert A().solved()
assert g.commands() < 1024, g.commands()
g.no_err()
g.tap_label('More')
g.tap_label('Easy')
assert str(A().bank().file) == '7x7-easy.txt' and int(A().idx()) == 2
print('all good')
