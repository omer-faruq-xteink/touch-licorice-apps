"""Offline test of sudoku/index.lua (API 2.9) under Lua 5.4 (lupa), with a ctx.package emulation
written from the firmware's reader code (open_text -> reader with read_line / seek / tell / close;
exists; read_text; size), fed the exact files xtpack.collect_data_files() will put into the
package; fonts that measure 13 px a character, storage, a clock.

  python -I sudoku/test_sudoku.py        (from the Xteink folder)
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, ROOT)
import xtpack  # noqa: E402
from lupa import lua54 as L  # noqa: E402

SRC = open(os.path.join(HERE, 'index.lua'), encoding='utf-8').read()
FILES = dict(xtpack.collect_data_files(HERE))
print('data files:', {k: len(v) for k, v in FILES.items()})

LUA_STUBS = r'''
cmds = 0; texts = {}; inval = 0; fills = 0; ms = 1000; store = {}
g = setmetatable({}, {__index = function(_, k) return function(self, ...)
  cmds = cmds + 1
  if k == 'text' then local x, y, s = ...; texts[#texts+1] = s end
  if k == 'rect' then local o = select(5, ...); if type(o) == 'table' and o.fill then fills = fills + 1 end end
end end})
local function font(lh) return { line_height = lh, measure = function(self, s) return 13 * #s end } end
ctx = { state = {}, invalidate = function() inval = inval + 1 end, package = {},
        fonts = { small = font(20), medium = font(24), large = font(30) },
        clock = { millis = function(self) ms = ms + 300; return ms end },
        storage = { write = function(self, n, d) store[n] = d; return true end,
                    read = function(self, n) if store[n] then return store[n] end return nil, 'not_found' end } }
__TEST = {}
'''


def make_rt(with_data=True):
    rt = L.LuaRuntime(unpack_returned_tuples=True)
    rt.execute(LUA_STUBS)
    store = FILES if with_data else {}
    data = rt.eval('ctx.package')

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
            if line.endswith(b'\r'):
                line = line[:-1]
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
    data['exists'] = lambda self, name: name in store
    data['read_text'] = lambda self, name: store[name].decode() if name in store else (None, 'not_found')
    data['size'] = lambda self, name: len(store[name]) if name in store else (None, 'not_found')
    rt.execute(SRC)
    return rt, rt.eval('__TEST.api')


def solve(s):
    grid = [int(c) for c in s]

    def ok(i, d):
        r, c = divmod(i, 9)
        for k in range(9):
            if grid[r * 9 + k] == d or grid[k * 9 + c] == d:
                return False
        br, bc = r - r % 3, c - c % 3
        for rr in range(br, br + 3):
            for cc in range(bc, bc + 3):
                if grid[rr * 9 + cc] == d:
                    return False
        return True

    def rec():
        try:
            i = grid.index(0)
        except ValueError:
            return True
        for d in range(1, 10):
            if ok(i, d):
                grid[i] = d
                if rec():
                    return True
                grid[i] = 0
        return False
    assert rec()
    return ''.join(map(str, grid))


rt, api = make_rt()
T = lambda **kw: rt.table_from(kw)  # noqa: E731
on_input = rt.eval('on_input')


def tap(x, y): on_input(None, T(type='pointer', phase='up', gesture='tap', x=x, y=y))
def tap_cell(i): r, c = divmod(i, 9); tap(15 + c * 50 + 25, 96 + r * 50 + 25)
def tap_digit(d): tap(17 + (d - 1) * 50 + 23, 572 + 28)
def tap_act(k): tap(15 + k * 115 + 52, 644 + 28)   # 0 erase, 1 check, 2 next, 3 bank
def texts(): return list(rt.eval('texts').values())


# parse_line: the three formats
ex = '0000183b305c 050703060007000800000816000000030000005000100730040086906000204840572093000409000  1.2'
p = api.parse_line(ex)
assert p and len(p) == 81 and p.startswith('0507030600'), p
assert api.parse_line('.' * 81) == '0' * 81
assert api.parse_line('1' * 81 + ',' + '2' * 81) == '1' * 81
assert api.parse_line('garbage') is None and api.parse_line('1' * 80) is None
print('parse_line OK')

# conflicts / is_solved
bad = api.conflicts('11' + '0' * 79); assert bad[1] and bad[2] and not bad[3]
bad = api.conflicts('1' + '0' * 8 + '1' + '0' * 71); assert bad[1] and bad[10]
bad = api.conflicts('1' + '0' * 9 + '1' + '0' * 70); assert bad[1] and bad[11]
sol = '534678912672195348198342567859761423426853791713924856961537284287419635345286179'
assert api.is_solved(sol) and not api.is_solved(sol[:-1] + '0') and not api.is_solved('1' * 81)
print('conflicts / is_solved OK')

# banks + seek reads
rt.eval('on_load')(rt.eval('ctx'))
banks = api.banks()
names = [banks[i]['name'] for i in range(1, len(banks) + 1)]
assert names == ['diabolical.txt', 'easy.txt', 'hard.txt', 'medium.txt', 'builtin'], names
assert api.data_ok() is True
for b in range(1, 5):
    bank = banks[b]
    assert bank['count'] == 600 and bank['stride'] == 100
    lines = FILES[bank['name']].decode().split('\n')
    for idx in (1, 2, 300, 600):
        assert api.read_puzzle(bank, idx) == lines[idx - 1][13:94], (bank['name'], idx)
assert api.read_puzzle(banks[5], 1) == api.builtin()[1] and len(api.builtin()) == 40
S = api.state()
assert S['bank'] == 'diabolical.txt' and S['idx'] == 1 and len(S['givens']) == 81 and S['cells'] == S['givens']
print('banks: 4 data banks + builtin; seek reads match the files OK')

# solve through taps
givens = S['givens']; solution = solve(givens)
i0 = givens.index('0'); tap_cell(i0)
# a wrong digit that a given in the same row, column or box already holds, so it is marked
r0, c0 = divmod(i0, 9)
peers = {r0 * 9 + k for k in range(9)} | {k * 9 + c0 for k in range(9)} | \
        {(r0 - r0 % 3 + a) * 9 + c0 - c0 % 3 + b for a in range(3) for b in range(3)}
wrong = next(d for d in '123456789' if d != solution[i0] and any(givens[j] == d for j in peers if j != i0))
tap_digit(int(wrong)); S = api.state()
assert S['cells'][i0] == wrong and api.conflicts(S['cells'])[i0 + 1]
tap_act(0); assert api.state()['cells'][i0] == '0'
for i, d in enumerate(solution):
    if givens[i] == '0':
        tap_cell(i); tap_digit(int(d))
S = api.state(); assert S['solved'] is True and S['cells'] == solution
rt.execute('texts = {}'); rt.eval('on_draw')(rt.eval('ctx'), rt.eval('g')); assert any('Solved' in t for t in texts())
gi = next(i for i, c in enumerate(givens) if c != '0'); tap_cell(gi); tap_digit(5)
assert api.state()['cells'] == solution
print('solve through taps OK (wrong digit marked, erase, solved message, givens locked)')

rt.execute('cmds = 0; fills = 0'); rt.eval('on_draw')(rt.eval('ctx'), rt.eval('g')); n = rt.eval('cmds')
assert rt.eval('fills') >= 40     # grid lines are solid bars: 2 px, boxes 4 px
print('draw commands (full board, check on):', n); assert n < 1024

# toggle / next / bank / side buttons
tap_act(1); assert api.state()['check'] is False
tap_act(1); assert api.state()['check'] is True
tap_act(2); S = api.state(); assert S['idx'] == 2 and S['bank'] == 'diabolical.txt' and not S['solved']
on_input(None, T(type='key', key='down', state='down')); assert api.state()['idx'] == 3
on_input(None, T(type='key', key='up', state='down')); assert api.state()['idx'] == 2
tap_act(3); S = api.state(); assert S['bank'] == 'easy.txt' and S['idx'] == 1
for _ in range(4):
    tap_act(3)
assert api.state()['bank'] == 'diabolical.txt', api.state()['bank']
on_input(None, T(type='key', key='up', state='down')); assert api.state()['idx'] == 600
print('toggle / next / bank cycle / side buttons OK')

# resume + garbage
api.adopt_state(rt.table_from({'bank': 'hard.txt', 'idx': 7, 'givens': givens,
                               'cells': solution[:40] + givens[40:], 'sel': 5, 'check': False}))
S = api.state(); assert S['bank'] == 'hard.txt' and S['idx'] == 7 and S['cells'][:40] == solution[:40] and S['sel'] == 5
api.adopt_state(rt.table_from({'bank': 'nope', 'cells': 'junk'}))
S = api.state(); assert S['bank'] == 'diabolical.txt' and S['idx'] == 1 and len(S['cells']) == 81
print('state resume + garbage OK')

# fallback without a data section
rt2, api2 = make_rt(with_data=False)
rt2.eval('on_load')(rt2.eval('ctx')); S2 = api2.state()
assert api2.data_ok() is False and S2['bank'] == 'builtin' and S2['givens'] == api2.builtin()[1]
rt2.execute('texts = {}'); rt2.eval('on_draw')(rt2.eval('ctx'), rt2.eval('g'))
assert any('built-in bank' in t for t in rt2.eval('texts').values())
print('fallback without data section OK')

# progress: state.txt is written on every move and read first; a 0.8 install's ctx.state still resumes
tap_act(2); idx_before, bank_before = api.state()['idx'], api.state()['bank']
tap_cell(80); cells_now = api.state()['cells']
saved = rt.eval('store')['state.txt']
assert f'idx={idx_before}' in saved and f'bank={bank_before}' in saved and f'cells={cells_now}' in saved, saved
rt3, api3 = make_rt()
rt3.eval('store')['state.txt'] = saved
rt3.eval('on_load')(rt3.eval('ctx'))
assert api3.state()['bank'] == bank_before and api3.state()['idx'] == idx_before and api3.state()['sel'] == 81
rt4, api4 = make_rt()
rt4.eval('ctx').state = rt4.table_from({'bank': 'easy.txt', 'idx': 42, 'givens': givens, 'cells': givens, 'check': True})
rt4.eval('on_load')(rt4.eval('ctx'))
assert api4.state()['bank'] == 'easy.txt' and api4.state()['idx'] == 42
print('progress in state.txt and from ctx.state OK')
print('ALL SUDOKU TESTS PASSED')
