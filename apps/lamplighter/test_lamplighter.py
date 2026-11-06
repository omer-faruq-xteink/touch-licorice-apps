"""Offline test of Lamplighter (gamekit harness; a stand-in for the package's data section): every
bank puzzle is a spanning tree that reasoning alone settles (so its solution is the only one), the
medium and hard ones not by the first rule alone, and none starts solved; the app reads the banks,
turns tiles by taps, lights what the source reaches, counts lamps and moves, Lock, Undo, Hint,
solves a puzzle by taps, keeps its place and tiles across a restart, switches level, leaves Back
on its main screen to the host, and stays under the draw-command limit.

  python -I apps/lamplighter/test_lamplighter.py
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
for name, n, harder, _seed in mb.LEVELS:
    lines = open(os.path.join(DATA, name + '.txt'), encoding='ascii').read().split('\n')[:-1]
    assert len({len(l) for l in lines}) == 1 and len(set(lines)) == len(lines), name
    for line in lines:
        nn, sol, start, src = mb.decode(line)
        assert nn == n and 0 <= src < n * n
        # a tree: n*n - 1 wires, every wire met, none off the board
        wires = 0
        for i, m in enumerate(sol):
            r, c = divmod(i, n)
            for b, dr, dc, o in mb.DIRS:
                if m & b:
                    rr, cc = r + dr, c + dc
                    assert 0 <= rr < n and 0 <= cc < n and sol[rr * n + cc] & o, line
                    wires += 1
        assert wires == 2 * (n * n - 1), line
        assert all(s in mb.turns(m) for s, m in zip(start, sol)), line
        assert start != sol
        assert mb.solved_by_reasoning(n, sol), line
        if harder:
            assert not mb.solved_by_reasoning(n, sol, False), line
    banks.append((name, n, lines))
print('banks: trees, settled by reasoning, the harder ones not by the first rule alone')

tsv = ''.join(f'{name}.txt\t{len(lines)}\t{len(lines[0]) + 1}\t{name}\\n' for name, n, lines in reversed(banks))
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
assert 'How to play' in g.texts(), g.texts()
g.tap_label('Close')
assert [str(b.name) for b in A().banks().values()] == ['easy', 'medium', 'hard']
g.no_err()

name, n, lines = banks[0]
nn, sol, start, src = mb.decode(lines[0])
tiles = lambda: [int(A().tiles()[i + 1]) for i in range(n * n)]
assert tiles() == start and int(A().pz().src) == src + 1
assert any(t.startswith('Lamps lit ') for t in g.texts()), g.texts()


def tap_tile(i):
    x, y = (int(v) for v in A().cell_xy(i + 1))
    C = int(A().cell_px())
    g.tap(x + C // 2, y + C // 2)


# a tap turns a tile a quarter clockwise and counts a move; Undo takes it back
i = next(k for k in range(n * n) if start[k] not in (0, 15) and len(mb.turns(start[k])) == 4)
tap_tile(i)
assert tiles()[i] == mb.rot(start[i]) and int(A().moves()) == 1
g.tap_label('Undo')
assert tiles()[i] == start[i]

# Lock: a framed tile does not turn
g.tap_label('Lock')
assert A().lock_mode()
tap_tile(i)
assert A().locked()[i + 1]
g.tap_label('Lock on')
tap_tile(i)
assert tiles()[i] == start[i] and 'Locked' in str(A().msg())
g.tap_label('Lock'); tap_tile(i); g.tap_label('Lock on')
assert not A().locked()[i + 1]

# Hint turns a tile right and frames it
g.tap_label('Hint')
hinted = [k for k in range(n * n) if A().locked()[k + 1] == 'h']
assert len(hinted) == 1 and tiles()[hinted[0]] == sol[hinted[0]], hinted

# solved by taps: every tile turned to the solution
for k in range(n * n):
    for _ in range(4):
        if tiles()[k] == sol[k]:
            break
        tap_tile(k)
    assert tiles()[k] == sol[k], k
assert A().solved() and 'All lit in' in str(A().msg()) and 'Hints 1' in str(A().msg()), A().msg()
assert int(A().loose_ends()) == 0 and all(A().lit()[k + 1] for k in range(n * n))
on, total = A().lamps()
assert on == total == sum(1 for k, m in enumerate(sol) if bin(m).count('1') == 1 and k != src)
assert A().done()['easy'][1]
g.no_err()
print('easy no. 1 solved by taps')

# Next (the third button once solved); a turned tile and a lock kept across a restart
g.tap_label('Next')
assert int(A().idx()) == 2 and not A().solved()
nn, sol2, start2, src2 = mb.decode(lines[1])
j = next(k for k in range(n * n) if len(mb.turns(start2[k])) > 1)
tap_tile(j)
g.tap_label('Lock'); tap_tile(0); g.tap_label('Lock on')
saved = tiles()
g.restart()
assert int(A().idx()) == 2 and tiles() == saved and A().locked()[1] and int(A().moves()) == 1

# Back: closes a box; on the main screen it is left to the host
back = lambda phase: g.L.eval(f"on_input(ctx, {{type='key', key='back', phase='{phase}'}})")
g.tap_label('More')
back('down')
assert back('up') is True and 'Previous' not in g.texts()
back('down')
assert back('up') is False, 'Back on the main screen leaves it to the host'

# Hard 9x9: under the draw-command limit unlit, solved, and with every tile locked
g.tap_label('More')
g.tap_label('Hard')
assert str(A().bank().name) == 'hard' and int(A().pz().n) == 9
assert g.commands() < 1024, g.commands()
nn, solh, starth, srch = mb.decode(banks[2][2][int(A().idx()) - 1])
for k in range(81):
    for _ in range(4):
        if int(A().tiles()[k + 1]) == solh[k]:
            break
        x, y = (int(v) for v in A().cell_xy(k + 1)); C = int(A().cell_px()); g.tap(x + C // 2, y + C // 2)
assert A().solved(), A().msg()
assert g.commands() < 1024, g.commands()
g.tap_label('Next')
g.tap_label('Lock')
for k in range(81):
    x, y = (int(v) for v in A().cell_xy(k + 1)); C = int(A().cell_px()); g.tap(x + C // 2, y + C // 2)
assert g.commands() < 1024, g.commands()
g.no_err()
print('all good')
