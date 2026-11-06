"""Offline test of Case Files (gamekit harness; a stand-in for the package's data section): every
bank case has true clues that reasoning alone settles (so its answer is the only one), and none of
its clues can go; the app reads every case and words every clue; it plays a case by taps (cross,
tick, clear), dots and rings, Undo, Hint, Check, crossing out clues, the clue pages, closes the
case, keeps its place and marks across a restart, switches level, leaves Back on its main screen
to the host, and stays under the draw-command limit.

  python -I apps/casefiles/test_casefiles.py
"""
import importlib.util, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

spec = importlib.util.spec_from_file_location('make_bank', os.path.join(HERE, 'make_bank.py'))
mb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mb)

DATA = os.path.join(HERE, 'data')
themes = mb.load_themes()

# the grid's labels fit a cell (at most 5 characters), the tab names a tab (6)
from lupa import lua54  # noqa: E402
T = lua54.LuaRuntime().execute(open(os.path.join(HERE, 'src', 'themes.lua'), encoding='utf-8').read())
for th in T.values():
    assert len(th.names) == 6 and all(len(x) <= 6 for x in th.names.values()), th.title
    for G in th.groups.values():
        short = G.short or G['items']
        assert len(G['items']) == 6 and all(len(x) <= 5 for x in short.values()), (th.title, G.key)
        assert len(G.key) <= 6 and '%s' in G.np and '%s' in G.pred and '%s' in G.neg, G.key
        if G.less:
            assert '%s' in G.after and len(G.unit) == 2, G.key
banks = []
for name, k, n, most, _seed in mb.LEVELS:
    lines = open(os.path.join(DATA, name + '.txt'), encoding='ascii').read().split('\n')[:-1]
    assert len({len(l) for l in lines}) == 1 and len(set(lines)) == len(lines), name
    for line in lines:
        case, clues = mb.decode(line, themes)
        assert (case.k, case.n) == (k, n) and len(clues) <= most, (name, line)
        assert mb.encode(case, clues) == line.rstrip('.'), line
        assert all(case.true(c) for c in clues), line
        assert mb.solve(case, clues)[0] == 'solved', line
        assert any(c[0] in '<+' for c in clues), line
    for line in lines[::25]:
        case, clues = mb.decode(line, themes)
        for c in clues:
            assert mb.solve(case, [x for x in clues if x is not c])[0] != 'solved', ('a clue to spare', line, c)
    banks.append((name, k, n, lines))
print('banks: true clues, every case settled by reasoning, no clue to spare')

tsv = ''.join(f'{name}.txt\t{len(lines)}\t{len(lines[0]) + 1}\t{name}\\n' for name, k, n, lines in reversed(banks))
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

# every case of every bank: read, the same answer as the generator's, and every clue in words
longest = ''
for bi, (name, k, n, lines) in enumerate(banks):
    b = A().banks()[bi + 1]
    for i, line in enumerate(lines):
        A().open_case(b, i + 1)
        pz = A().pz()
        case, clues = mb.decode(line, themes)
        assert int(pz.k) == k and int(pz.n) == n and len(pz.clues) == len(clues), line
        for gi in range(k):
            for p in range(n):
                assert int(pz.slot[gi + 1][p + 1]) == case.perm[gi][p] + 1, line
        for ci in range(len(clues)):
            s = str(A().text(ci + 1))
            assert s.endswith('.') and '%' not in s and 'nil' not in s and s[0].isupper(), s
            longest = max(longest, s, key=len)
print('every case read and worded; the longest clue:', longest)
g.no_err()

# back to the first easy case
A().open_case(A().banks()[1], 1)
pz = A().pz()
name, k, n, lines = banks[0]
case, clues = mb.decode(lines[0], themes)
assert len(A().pairs()) == 3 and int(A().tab()) == 1
texts = g.texts()
assert any(t.startswith('Find each ') for t in texts) and '1. ' in texts, texts
assert str(pz.theme.title) in texts, texts


def cell_xy(a, b):
    C = int(A().cell_px())
    return int(A().grid_x0()) + (b - 1) * C + C // 2, int(A().grid_top()) + int(A().head_h()) + (a - 1) * C + C // 2


def tap_cell(a, b):
    g.tap(*cell_xy(a, b))


def mark(pi, a, b):
    v = A().marks()[pi][(a - 1) * n + b]
    return None if v is None else str(v)


def tab(k):
    x, y, w, h = (int(v) for v in A().tab_rect(k))
    g.tap(x + w // 2, y + h // 2)
    assert int(A().tab()) == k


def tick(a, b):
    pi = int(A().tab())
    for _ in range(3):
        if mark(pi, a, b) in ('v', 'h'):
            return
        tap_cell(a, b)
    assert mark(pi, a, b) in ('v', 'h')


def clear(a, b):
    pi = int(A().tab())
    for _ in range(3):
        if mark(pi, a, b) is None:
            return
        tap_cell(a, b)
    assert mark(pi, a, b) is None


# a tap: cross, tick, nothing; a tick dots its row and column
tap_cell(1, 1)
assert mark(1, 1, 1) == 'x'
tap_cell(1, 1)
assert mark(1, 1, 1) == 'v'
before = len(g.circles())
assert before >= 2 * (n - 1), before         # the dots
tap_cell(1, 1)
assert mark(1, 1, 1) is None

# two ticks in a row are ringed
tick(1, 1); tick(1, 2)
assert 'Two ticks in one row' in str(A().msg()), A().msg()
g.tap_label('Undo')
assert mark(1, 1, 2) == 'x'
clear(1, 2); clear(1, 1)

# Check counts the wrong marks; Hint takes one away, then gives a right tick
h = case.gids  # noqa
wrong_b = next(b for b in range(1, n + 1) if case.perm[1][0] + 1 != b)
tick(1, wrong_b)
g.tap_label('Check')
assert str(A().msg()) == 'One mark is wrong.', A().msg()
g.tap_label('Hint')
assert mark(1, 1, wrong_b) is None and 'wrong' in str(A().msg())
g.tap_label('Check')
assert str(A().msg()) == 'No mistakes so far.'
g.tap_label('Hint')
hinted = [(a, b) for a in range(1, n + 1) for b in range(1, n + 1) if mark(1, a, b) == 'h']
assert len(hinted) == 1 and case.perm[1][hinted[0][0] - 1] + 1 == hinted[0][1], hinted
assert len([r for r in g.rects() if r.fill and int(r.h) == 2]) >= 1     # the underline

# a clue crossed out, and back
y0 = int(A().clue_y)
pages = A().clue_pages()[0]
first = next(i for i, l in enumerate(pages[1].lines.values()) if int(l[3]) == 1)
lh = 22
g.tap(100, y0 + first * lh + 5)
assert A().struck()[1], 'clue 1 struck'
g.tap(100, y0 + first * lh + 5)
assert not A().struck()[1]

# a cross and a tick kept across a restart, with the tab
tab(2)
tap_cell(2, 2)
saved = [[str(v) for v in A().marks()[pi].values()] for pi in (1, 2, 3)]
g.restart()
assert int(A().tab()) == 2 and [[str(v) for v in A().marks()[pi].values()] for pi in (1, 2, 3)] == saved

# closed by ticks in the people's grids
for pi in (1, 2):
    tab(pi)
    hh = int(A().pairs()[pi][2])
    for a in range(1, n + 1):
        b = case.perm[hh - 1][a - 1] + 1
        for bb in range(1, n + 1):
            if bb != b and mark(pi, a, bb) in ('v', 'h', 'x'):
                clear(a, bb)
        tick(a, b)
assert A().solved(), A().msg()
assert 'Case closed' in g.texts(), g.texts()
assert A().done()['easy'][1]
g.tap_label('Close')
assert 'Case closed! Hints 1.  Next for another.' == str(A().msg()), A().msg()
g.no_err()
print('easy no. 1 closed by taps')

# Next (the third button once closed), Back: closes a box; on the main screen it is left to the host
g.tap_label('Next')
assert int(A().idx()) == 2 and not A().solved()
back = lambda phase: g.L.eval(f"on_input(ctx, {{type='key', key='back', phase='{phase}'}})")
g.tap_label('More')
back('down')
assert back('up') is True and 'Previous' not in g.texts()
back('down')
assert back('up') is False, 'Back on the main screen leaves it to the host'

# side buttons step through the grids
g.key('down')
assert int(A().tab()) == 2
g.key('up'); g.key('up')
assert int(A().tab()) == 3

# Hard: six grids, the clue pages, under the draw-command limit with every cell marked
g.tap_label('More')
g.tap_label('Hard')
assert str(A().bank().name) == 'hard' and len(A().pairs()) == 6
n = 5
most_pages = 0
for i in range(1, len(banks[2][3]) + 1, 7):
    A().open_case(A().banks()[3], i)
    pages = A().clue_pages()[0]
    most_pages = max(most_pages, len(pages))
    if len(pages) > 1:
        assert all(p.more for p in pages.values())
        cap = (int(A().tab_rect(1)[1]) - 10 - y0) // lh
        for p in pages.values():
            assert len(p.lines) <= cap - 1
print('hard: clue pages at most', most_pages)
A().open_case(A().banks()[3], 1)
for k in range(1, 7):
    tab(k)
    for a in range(1, 6):
        for b in range(1, 6):
            tap_cell(a, b)
    assert g.commands() < 1024, g.commands()
    tab(k)
    for a in range(1, 6):
        tap_cell(a, a)
    assert g.commands() < 1024, g.commands()
g.no_err()
print('all good')
