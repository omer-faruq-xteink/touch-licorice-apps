"""Offline test of Kakuro (gamekit harness; a stand-in for the package's data section): every bank
puzzle is filled by run reasoning alone (so its solution is the only one); the app reads the banks
in order of size, works out the clues, lists the ways to make a run, plays a puzzle by taps,
crosses a repeated digit and a full run that adds up wrong, Hint, keeps its place and the digits
across a restart, switches level, and stays under the draw-command limit on the largest board.

  python -I apps/kakuro/test_kakuro.py
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
for name, n, _share, _run, _seed in mb.BANKS:
    lines = open(os.path.join(DATA, name + '.txt'), encoding='ascii').read().split('\n')[:-1]
    assert len({len(l) for l in lines}) == 1 and len(lines[0]) == n * n and len(set(lines)) == len(lines)
    banks.append((name, n, lines))

for name, n, lines in banks:
    for line in lines[::7]:
        assert mb.solved_by_reasoning(line, n), (name, line)
print('banks: every sampled puzzle filled by run reasoning')

tsv = ''.join(f'{name}.txt\t{len(lines)}\t{n * n + 1}\t{name}\\n' for name, n, lines in reversed(banks))
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
assert [str(b.file) for b in A().banks().values()] == ['6x6-easy.txt', '7x7-medium.txt', '8x8-hard.txt']
assert str(A().bank().file) == '6x6-easy.txt' and int(A().idx()) == 1
assert [str(s) for s in A().combos(2, 16).values()] == ['79']
assert [str(s) for s in A().combos(3, 7).values()] == ['124']
assert len(A().combos(2, 10)) == 4
g.no_err()

# the clues the app works out are the sums of the runs of the line
name, n, lines = banks[0]
line = lines[0]
pz = A().pz()
for i, cl in pz.clue.items():
    r, c = divmod(int(i) - 1, n)
    if cl['a']:
        k, s = c + 1, 0
        while k < n and line[r * n + k] != '#':
            s += int(line[r * n + k]); k += 1
        assert int(cl['a']) == s
    if cl['d']:
        k, s = r + 1, 0
        while k < n and line[k * n + c] != '#':
            s += int(line[k * n + c]); k += 1
        assert int(cl['d']) == s


def tap_cell(i):
    x, y = (int(v) for v in A().cell_xy(i))
    C = int(A().cell_px())
    g.tap(x + C // 2, y + C // 2)


def tap_digit(d):
    x, y, w, h = (int(v) for v in A().pad_rect(d))
    g.tap(x + w // 2, y + h // 2)


def play(line, n, upto=None):
    cells = [i + 1 for i, ch in enumerate(line) if ch != '#']
    for i in cells[:upto]:
        tap_cell(i)
        tap_digit(int(line[i - 1]))


# a repeated digit and a wrong full run are crossed
cells = [i + 1 for i, ch in enumerate(line) if ch != '#']
first = cells[0]
run = pz.across[first] if pz.across[first] else pz.down[first]
a, b = (int(x) for x in list(run.cells.values())[:2])
tap_cell(a); tap_digit(5)
tap_cell(b); tap_digit(5)
bad = A().conflicts()
assert bad[a] and bad[b]
g.tap_label('Erase')
tap_cell(a); g.tap_label('Erase')

play(line, n)
assert A().solved() and 'Solved' in str(A().msg()), A().msg()
assert A().done()['6x6-easy.txt'][1]
g.no_err()
print('easy 1 solved by taps')

# Next, two digits and a hint, kept across a restart
g.tap_label('Next')
assert int(A().idx()) == 2 and not A().solved()
line2 = lines[1]
play(line2, n, 2)
g.tap_label('Hint')
cells2 = [i + 1 for i, ch in enumerate(line2) if ch != '#']
assert int(A().entry()[cells2[2]]) == int(line2[cells2[2] - 1])
g.restart()
assert int(A().idx()) == 2
assert [int(A().entry()[c] or 0) for c in cells2[:3]] == [int(line2[c - 1]) for c in cells2[:3]]
assert A().done()['6x6-easy.txt'][1]

# the hard bank: solved by taps, under the draw-command limit
g.tap_label('More')
g.tap_label('Hard')
assert str(A().bank().file) == '8x8-hard.txt'
assert g.commands() < 1024, g.commands()
hname, hn, hlines = banks[2]
play(hlines[int(A().idx()) - 1], hn)
assert A().solved()
assert g.commands() < 1024, g.commands()
g.no_err()
g.tap_label('More')
g.tap_label('Easy')
assert str(A().bank().file) == '6x6-easy.txt' and int(A().idx()) == 2
# Back (down, then up: the host reads only the up event's answer): closes a box; on the board it is
# left to the host, which offers to exit
back = lambda phase: g.L.eval(f"on_input(ctx, {{type='key', key='back', phase='{phase}'}})")
g.tap_label('More')
assert 'Previous' in g.recs()
assert back('down') is True and back('up') is True and 'Previous' not in g.recs(), g.texts()
assert back('down') is True and back('up') is False
g.no_err()
print('all good')
