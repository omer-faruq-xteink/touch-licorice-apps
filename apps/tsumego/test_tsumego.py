"""Offline test of the Go problems app (gamekit harness; stand-ins for the package's data section
and for the app's folder on the card): the first problem, solving by taps, a move that is not in
the tree, a wrong move with its refutation and Retry, Hint twice, Next, captures, the player's own
SGF files (a collection file, single files, RIGHT / Correct / no marks, escaped brackets), progress
kept across a restart; then every built-in problem solved by taps along its first correct line.

  python -I apps/tsumego/test_tsumego.py
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

DATA = os.path.join(HERE, 'data').replace(os.sep, '/') + '/'
g = Game(HERE)
STUB = f'''
ctx.package = {{ open_text = function(self, name, opts)
  local f = io.open([[{DATA}]] .. name, 'rb')
  if not f then return nil end
  return {{ read_line = function(self) return f:read('l') end, close = function(self) f:close() end }}
end }}
files = files or {{}}
ctx.files = {{
  list = function(self) local t = {{}} for k, v in pairs(files) do t[#t + 1] = {{ name = k, size = #v }} end return t end,
  read = function(self, n, off, len) local s = files[n]; if not s then return nil, 'not_found' end return s:sub((off or 0) + 1, (off or 0) + (len or 65536)) end,
}}
'''
g.L.execute(STUB)
g.restart()
A = lambda: g.api


def tap_pt(sgf):
    c, r = ord(sgf[0]) - 97, ord(sgf[1]) - 97
    x, y = (int(v) for v in A().xy(r * 19 + c))
    g.tap(x, y)


def stone(sgf):
    c, r = ord(sgf[0]) - 97, ord(sgf[1]) - 97
    v = A().board()[r * 19 + c]
    return None if v is None else str(v)


def kids(n):
    return [n.kids[i] for i in range(1, len(n.kids) + 1)]


def good_line_move():
    """the player's next correct move at the current node"""
    k = A().first_good(A().node(), A().prob().player)
    assert k is not None, 'no correct move here'
    return str(k.props['B' if str(A().prob().player) == 'B' else 'W'][1])


def solve_current():
    for _ in range(20):
        if str(A().state()) == 'solved':
            return
        tap_pt(good_line_move())
    raise AssertionError('not solved')


BUT = lambda k: (12 + (k - 1) * ((480 - 48) // 4 + 8) + 20, 704 + 30)

# the first Beginner problem: a corner, the task, Black to play
t = g.texts()
assert 'Go problems' in t and any(s.startswith('Easy  1/') for s in t), t
assert any(s.startswith('Black to') for s in t), t
g.no_err()
assert g.commands() < 900, g.commands()
p = A().prob()
assert str(p.player) == 'B'

# a point not in the tree: no stone, a message
root = A().node()
in_tree = {str(k.props['B'][1]) for k in kids(root) if k.props['B']}
v = A().view()
free = None
for r in range(int(v.r0), int(v.r1) + 1):
    for c in range(int(v.c0), int(v.c1) + 1):
        s = chr(97 + c) + chr(97 + r)
        if s not in in_tree and stone(s) is None:
            free = s; break
    if free: break
tap_pt(free)
assert stone(free) is None and 'Not the move. Try again.' in g.texts()

# a wrong move: it stays, no answer shown until Why; then Retry
wrong = [k for k in kids(root) if not k.good]
assert wrong, 'generated problems carry their refutations'
wm = str(wrong[0].props['B'][1])
tap_pt(wm)
assert stone(wm) == 'B' and str(A().state()) == 'wrong'
t = g.texts()
assert 'Why' in t and 'Hint' not in t and any(s.startswith('Wrong. Tap Why') for s in t), t
n_white = sum(1 for v in A().board().values() if str(v) == 'W')
g.tap(*BUT(1))                                   # Why: the refutation
assert sum(1 for v in A().board().values() if str(v) == 'W') == n_white + 1, 'the answer is played'
assert any(('White captures' in s or "White's answer" in s) for s in g.texts()), g.texts()
g.tap(*BUT(2))                                   # Retry
assert str(A().state()) == 'play' and stone(wm) is None and 'Hint' in g.texts()

# Hint marks the point, a second Hint plays it
g.tap(*BUT(1))
assert A().hint() is not None and 'Hint again plays the marked point.' in g.texts()
g.tap(*BUT(1))
solve_current()
assert 'Solved!' in g.texts() and any('with help' in s for s in g.texts()), g.texts()
assert str(A().solved()['beginner.txt']).startswith('1')

# Next, and solving without help
g.tap(*BUT(3))
assert any(s.startswith('Easy  2/') for s in g.texts())
solve_current()
assert any('first try' in s for s in g.texts()), g.texts()

# progress kept across a restart
g.restart()
assert any(s.startswith('Easy  2/') and 'solved 2' in s for s in g.texts()), g.texts()

# the player's own files: a collection with three problems (RIGHT, Correct, no marks), a single
# file, escaped brackets in a comment; captures
COLL = r'''(;GM[1]SZ[19]C[Black to capture \[two\] stones]AB[ba][bb]AW[ca][cb][da]AB[db][ea]
(;B[cc]C[RIGHT])(;B[dc]C[WRONG]))
(;GM[1]SZ[19]AB[aa]AW[ab][ba](;B[bb];W[ac];B[ca]C[Correct!]))
(;GM[1]SZ[19]AW[cc]AB[bc][dc][cb](;B[cd]))'''
SINGLE = '(;GM[1]FF[4]SZ[9]PL[W]AB[ee]AW[de][fe][ed](;W[ef]C[right]))'
g.L.execute('files = {}')
g.g.files['Mine.sgf'] = COLL
g.g.files['one.SGF'] = SINGLE
g.g.files['notes.txt'] = 'ignored'
g.tap(*BUT(4))                                    # the collections
t = g.texts()
assert 'Mine' in t and 'Single files' in t and 'Easy' in t, t
g.tap_label('Mine')
t = g.texts()
assert any(s.startswith('Mine  1/3') for s in t) and 'Black to capture [two] stones' in t, t
assert stone('ca') == 'W' and stone('cb') == 'W'
tap_pt('cc')                                      # captures the two white stones
assert str(A().state()) == 'solved' and stone('ca') is None and stone('cb') is None
g.key('down')
assert any(s.startswith('Mine  2/3') for s in g.texts())
tap_pt('bb'); assert stone('ac') == 'W' and str(A().state()) == 'play'
tap_pt('ca'); assert str(A().state()) == 'solved'
g.key('down')
tap_pt('cd'); assert str(A().state()) == 'solved'  # no marks at all: the line is correct
assert stone('cc') is None                         # captured
g.tap(*BUT(4)); g.tap_label('Single files')
t = g.texts()
assert 'White to play' in t, t                     # PL[W], no task comment
assert int(A().view().r1) == 8 and int(A().view().c1) == 8   # a 9 x 9 board, its edges in view
tap_pt('ef'); assert str(A().state()) == 'solved'
g.restart()                                        # the chosen file collection comes back
assert any(s.startswith('Single files  1/1') for s in g.texts()), g.texts()
g.tap(*BUT(4)); g.tap_label('Easy')

# every built-in problem: solvable by taps along the first correct line, small enough to draw
tot = 0
for k, name in ((1, 'beginner'), (2, 'intermediate'), (3, 'advanced')):
    n = sum(1 for l in open(os.path.join(HERE, 'data', name + '.txt'), encoding='utf-8') if l.strip())
    assert n > 0, name
    for i in range(1, n + 1):
        A().start(k, i)
        assert A().prob() is not None, (name, i)
        solve_current()
        tot += 1
        if i % 50 == 1:
            assert g.commands() < 900, (name, i, g.commands())
            g.no_err()
print(f'tsumego: {tot} built-in problems solved by taps; own SGF files, captures, hint, retry OK')
print('tsumego tests passed')
