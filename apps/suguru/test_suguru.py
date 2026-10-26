"""Offline test of suguru/index.lua under Lua 5.4 (lupa), with the same ctx.data emulation as the
Sudoku test (open_text -> reader with read_line / seek / tell / close), fed the exact files
xtpack.collect_data_files() puts into the package. Also checks that bank puzzles have exactly one
solution, with make_bank.py's solver.

  python -I apps/suguru/test_suguru.py
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, ROOT)
sys.path.insert(0, HERE)
import xtpack  # noqa: E402
import make_bank  # noqa: E402
from lupa import lua54 as L  # noqa: E402

SRC = open(os.path.join(HERE, 'index.lua'), encoding='utf-8').read()
FILES = dict(xtpack.collect_data_files(HERE))
print('data files:', {k: len(v) for k, v in FILES.items()})

LUA_STUBS = r'''
cmds = 0; texts = {}; inval = 0
g = setmetatable({}, {__index = function(_, k) return function(self, ...)
  cmds = cmds + 1
  if k == 'text' then local x, y, s = ...; texts[#texts+1] = s end
  if k == 'measure_text' then local s = ...; return 13 * #s, 24 end
end end})
ctx = { state = {}, invalidate = function() inval = inval + 1 end, display = { full_refresh = function() end },
        sys = { millis = function() return 1 end, epoch_sec = function() return 2 end }, data = {} }
__TEST = {}
'''


def make_rt(with_data=True):
    rt = L.LuaRuntime(unpack_returned_tuples=True)
    rt.execute(LUA_STUBS)
    store = FILES if with_data else {}
    data = rt.eval('ctx.data')

    def open_text(self, name, opts=None):
        if name not in store:
            return (None, 'not_found')
        blob = store[name]
        st = {'pos': 0, 'closed': False}

        def read_line(self):
            if st['closed'] or st['pos'] >= len(blob):
                return None
            i = blob.find(b'\n', st['pos'])
            end = len(blob) if i < 0 else i
            line = blob[st['pos']:end]
            st['pos'] = end + 1 if i >= 0 else len(blob)
            if len(line) > 512:
                st['closed'] = True
                return (None, 'line_too_long')
            return line.decode()

        def seek(self, pos):
            if st['closed'] or pos < 0 or pos > len(blob):
                return False
            st['pos'] = pos
            return True

        return rt.table_from({'read_line': read_line, 'seek': seek, 'tell': lambda self: st['pos'],
                              'close': lambda self: st.__setitem__('closed', True)})

    data['open_text'] = open_text
    rt.execute(SRC)
    return rt, rt.eval('__TEST.api')


def solve(n, regions, givens):
    """The unique solution of a puzzle line (asserts uniqueness)."""
    letters = {}
    reg = [letters.setdefault(ch, len(letters)) for ch in regions]
    p = make_bank.Puzzle(n, reg)
    count, sol = p.solve([int(c) for c in givens], 2, budget=10 ** 7)
    assert count == 1, (n, regions, givens, count)
    return ''.join(map(str, sol))


rt, api = make_rt()
T = lambda **kw: rt.table_from(kw)  # noqa: E731
on_input = rt.eval('on_input')


def tap(x, y): on_input(None, T(type='touch', gesture='tap', x=x, y=y))
def tap_cell(n, i): C = 450 // n; r, c = divmod(i, n); tap(15 + c * C + C // 2, 90 + r * C + C // 2)
def tap_num(d): tap(15 + (d - 1) * 92 + 41, 572 + 30)
def tap_act(k): tap(15 + k * 115 + 52, 644 + 28)   # 0 erase, 1 check, 2 next, 3 bank
def texts(): return list(rt.eval('texts').values())


# parse_line
n, reg, giv = api.parse_line('A' * 25 + '0' * 25)
assert n == 5 and reg == 'A' * 25 and giv == '0' * 25
assert api.parse_line('A' * 25 + '6' + '0' * 24) is None          # 6 never fits a region
assert api.parse_line('garbage') is None and api.parse_line('A' * 9 + '0' * 9) is None
print('parse_line OK')

# conflicts: a number bigger than its region, a repeat in a region, touching cells (diagonals too)
R5 = 'AAAAA' + 'BBBBB' + 'CCCCC' + 'DDDDD' + 'EEEEE'
bad = api.conflicts(5, 'F' + R5[1:], '2' + '0' * 24); assert bad[1]                   # region of 1 cell
bad = api.conflicts(5, R5, '1010' + '0' * 21); assert bad[1] and bad[3]              # same region
bad = api.conflicts(5, R5, '1' + '0' * 5 + '1' + '0' * 18); assert bad[1] and bad[7]  # diagonal
bad = api.conflicts(5, R5, '1' + '0' * 11 + '1' + '0' * 12); assert not bad[1] and not bad[13]
print('conflicts OK')

# banks + seek reads + unique solutions
rt.eval('on_load')(rt.eval('ctx'))
banks = api.banks()
names = [banks[i]['name'] for i in range(1, len(banks) + 1)]
assert names == ['5x5-easy.txt', '6x6-medium.txt', '7x7-hard.txt', '8x8-expert.txt', 'builtin'], names
assert api.data_ok() is True
LEVELS = {name + '.txt': mx for name, _n, mx, _mn, _pool in make_bank.BANKS}
for b, size in zip(range(1, 5), (5, 6, 7, 8)):
    bank = banks[b]
    # every puzzle is solvable by logic with its bank's techniques: no guessing (and so unique)
    for line in FILES[bank['name']].decode().split():
        half = len(line) // 2
        letters = {}
        reg = [letters.setdefault(ch, len(letters)) for ch in line[:half]]
        ok, _lv, _sc = make_bank.grade(make_bank.Puzzle(size, reg), [int(c) for c in line[half:]], LEVELS[bank['name']])
        assert ok, (bank['name'], line)
    assert bank['count'] == 200 and bank['stride'] == 2 * size * size + 1, (bank['name'], bank['count'], bank['stride'])
    lines = FILES[bank['name']].decode().split('\n')
    for idx in (1, 2, 100, 200):
        n, reg, giv = api.read_puzzle(bank, idx)
        assert n == size and reg + giv == lines[idx - 1], (bank['name'], idx)
        solve(n, reg, giv)
assert len(api.builtin()) >= 6
for k in range(1, len(api.builtin()) + 1):
    solve(*api.parse_line(api.builtin()[k]))
S = api.state()
assert S['bank'] == '5x5-easy.txt' and S['idx'] == 1 and S['n'] == 5 and S['cells'] == S['givens']
print('banks: 4 data banks + builtin; seek reads match; every puzzle solvable by logic, one solution OK')


def play(n):
    """Solve the current puzzle through taps: a wrong number is marked, erased, then all filled."""
    S = api.state()
    givens, regions = S['givens'], S['regions']
    sol = solve(n, regions, givens)
    i0 = givens.index('0')
    tap_cell(n, i0)
    wrong = next(d for d in '12345' if d != sol[i0])
    tap_num(int(wrong))
    assert api.state()['cells'][i0] == wrong
    tap_act(0); assert api.state()['cells'][i0] == '0'
    for i, d in enumerate(sol):
        if givens[i] == '0':
            tap_cell(n, i); tap_num(int(d))
    S = api.state(); assert S['solved'] is True and S['cells'] == sol
    rt.execute('texts = {}'); rt.eval('on_draw')(); assert any('Solved' in t for t in texts())
    gi = next(i for i, c in enumerate(givens) if c != '0'); tap_cell(n, gi); tap_num(1 if sol[gi] != '1' else 2)
    assert api.state()['cells'] == sol
    return sol


play(5)
print('5x5 solved through taps OK (wrong number, erase, solved message, givens locked)')
# a wrong number that breaks a rule is crossed
tap_act(2)
S = api.state()
i0 = S['givens'].index('0')
tap_cell(5, i0)
row_vals = [S['givens'][j] for j in range(25) if j != i0 and S['regions'][j] == S['regions'][i0] and S['givens'][j] != '0']
if row_vals:
    tap_num(int(row_vals[0]))
    assert api.conflicts(5, S['regions'], api.state()['cells'])[i0 + 1]
    tap_act(0)
for _ in range(3):
    tap_act(3)
assert api.state()['bank'] == '8x8-expert.txt' and api.state()['n'] == 8
play(8)
print('8x8 solved through taps OK')

rt.execute('cmds = 0'); rt.eval('on_draw')(); n_cmds = rt.eval('cmds')
print('draw commands (8x8, check on):', n_cmds); assert n_cmds < 1500

# toggle / next / bank cycle / side buttons
tap_act(1); assert api.state()['check'] is False
tap_act(1); assert api.state()['check'] is True
tap_act(2); S = api.state(); assert S['idx'] == 2 and not S['solved']
on_input(None, T(type='key', key='down', state='down')); assert api.state()['idx'] == 3
on_input(None, T(type='key', key='up', state='down')); assert api.state()['idx'] == 2
tap_act(3); assert api.state()['bank'] == 'builtin'
tap_act(3); S = api.state(); assert S['bank'] == '5x5-easy.txt' and S['idx'] == 1
on_input(None, T(type='key', key='up', state='down')); assert api.state()['idx'] == 200
print('toggle / next / bank cycle / side buttons OK')

# resume + garbage
S = api.state()
api.adopt_state(rt.table_from({'bank': '6x6-medium.txt', 'idx': 7, 'n': 5, 'regions': S['regions'], 'givens': S['givens'],
                               'cells': S['givens'], 'sel': 5, 'check': False}))
S2 = api.state(); assert S2['bank'] == '6x6-medium.txt' and S2['idx'] == 7 and S2['sel'] == 5 and S2['n'] == 5
api.adopt_state(rt.table_from({'bank': 'nope', 'cells': 'junk'}))
S3 = api.state(); assert S3['bank'] == '5x5-easy.txt' and S3['idx'] == 1 and len(S3['cells']) == 25
print('state resume + garbage OK')

# fallback without a data section
rt2, api2 = make_rt(with_data=False)
rt2.eval('on_load')(rt2.eval('ctx')); S4 = api2.state()
assert api2.data_ok() is False and S4['bank'] == 'builtin'
rt2.execute('texts = {}'); rt2.eval('on_draw')()
assert any('built-in bank' in t for t in rt2.eval('texts').values())
print('fallback without data section OK')
print('ALL SUGURU TESTS PASSED')
