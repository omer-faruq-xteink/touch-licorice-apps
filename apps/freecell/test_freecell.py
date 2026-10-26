"""Offline test of FreeCell (gamekit harness, a stand-in for the package's data section): deal 1
as Microsoft deals it, picking and placing cards by taps, runs limited by free cells, autoplay,
Undo, Restart, whole deals won by following Hint, the way back to the winning line, save and
reload; and the solution files replay to a win.

  python -I apps/freecell/test_freecell.py
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

DATA = os.path.join(HERE, 'data').replace(os.sep, '/') + '/'
g = Game(HERE)
g.L.execute(f'''
ctx.package = {{ open_text = function(self, name, opts)
  local f = io.open([[{DATA}]] .. name, 'rb')
  if not f then return nil end
  return {{ read_line = function(self) return f:read('l') end, close = function(self) f:close() end }}
end }}
''')
g.restart()
A = lambda: g.api
R = A().R
X0, CW, GAP, SLOT_Y, TAB_Y, CH = (int(v) for v in A().geometry())
NAMES = 'CDHS'


def name(c):
    c = int(c)
    return 'A23456789TJQK'[(c - 1) % 13] + NAMES[(c - 1) // 13]


def col(k):
    return [name(c) for c in A().pos().cols[k].values()]


def sx(k): return X0 + (k - 1) * (CW + GAP) + CW // 2


def tap_card(k, i):            # column k, card i (1 = bottom)
    g.tap(sx(k), int(A().card_y(k, i)) + 6)


def tap_slot(k):               # 1..4 free cells, 5..8 foundations
    g.tap(sx(k), SLOT_Y + 30)


def tap_col(k):
    n = len(A().pos().cols[k])
    g.tap(sx(k), int(A().card_y(k, max(1, n))) + 6 if n else TAB_Y + 20)


def follow(m):
    """make the hinted move by taps"""
    p = A().pos()
    if m['from'] == 'c':
        n = len(p.cols[m['fi']])
        tap_card(int(m['fi']), n - int(m['n']) + 1)
    else:
        tap_slot(int(m['fi']))
    if m['to'] == 'c':
        tap_col(int(m['ti']))
    elif m['to'] == 'f':
        tap_slot(int(m['ti']))
    else:
        tap_slot(int(m['ti']) + 5)


MAX_CMDS = [0]


def win_by_hints(limit=200):
    for _ in range(limit):
        MAX_CMDS[0] = max(MAX_CMDS[0], g.commands())
        if R.won(A().pos()):
            return True
        g.tap_label('Hint')
        h = A().hint()
        assert h is not None, g.texts()
        before = R.encode(A().pos())
        follow(h)
        assert R.encode(A().pos()) != before, ('the hinted move did not happen', dict(h))
    return False


# deal 1, as Microsoft deals it (aces already home: AH goes home at once? no: it is covered)
assert col(1) == ['JD', 'KD', '2S', '4C', '3S', '6D', '6S'] and col(8) == ['5H', '3H', '3C', '7S', '7D', 'TC']
t = g.texts()
assert 'FreeCell  1' in t and 'Undo' in t and 'Hint' in t and 'Restart' in t and 'New' in t, t

# pick a card and put it in a free cell, then back; a wrong column is refused
tap_card(1, 7)                               # 6S
assert dict(A().sel()) == {'from': 'c', 'i': 1, 'n': 1}
tap_slot(1)
assert name(A().pos().free[1]) == '6S' and int(A().moves()) == 1
tap_slot(1); tap_col(3)                      # 6S onto 6H? no: not one lower
assert name(A().pos().free[1]) == '6S' and 'It does not fit there.' in g.texts()
g.tap_label('Undo')
assert col(1)[-1] == '6S' and int(A().moves()) == 0

# whole deals won by following Hint, the win box, counted
for d in (1, 2, 3, 37, 100):
    A().start(d)
    assert win_by_hints(), d
    assert f'Deal {d} won!' in g.texts(), g.texts()
    g.tap_label('Close')
assert 'won=5' in g.store['game.txt']

# off the line: a move the solution does not make; Hint offers the way back
A().start(5)
g.tap_label('Hint')
h = dict(A().hint())
p = A().pos()
key = lambda m: (m['from'], int(m['fi']), m['to'], int(m['ti'] or 0), int(m['n']))
other = next((m for m in R.moves(p).values() if dict(m)['to'] == 'f' and key(dict(m)) != key(h)), None)
assert other is not None
follow(dict(other))
follow(dict(next(m for m in R.moves(A().pos()).values() if dict(m)['to'] == 'f')))
g.tap_label('Hint')
t = g.texts()
if 'Off the winning line' in t:
    assert 'Back to it' in t
    g.tap_label('Back to it')
    assert A().hint() is not None
assert win_by_hints(), 'back on the line, the deal is won'
g.tap_label('Close')

# no hints past deal 1000; Restart; save and reload
A().start(5000)
g.tap_label('Hint')
assert 'Hints are there for deals 1 to 1000.' in g.texts()
tap_card(1, len(A().pos().cols[1])); tap_slot(2)
moved = R.encode(A().pos())
g.restart()
assert R.encode(A().pos()) == moved and int(A().deal()) == 5000
g.tap_label('Restart'); g.tap_label('Restart')
assert int(A().moves()) == 0 and R.encode(A().pos()) != moved

# every solution file replays to a win (a sample of each file)
check = g.L.eval('''function(R, d, line)
  local p = R.deal(d); R.autoplay(p)
  for s in line:gmatch('%S+') do
    local m = R.move_parse(p, s)
    if not m or not R.legal(p, m) then return false end
    R.apply(p, m); R.autoplay(p)
  end
  return R.won(p)
end''')
files = sorted(f for f in os.listdir(os.path.join(HERE, 'data')) if f.startswith('sol'))
assert files
for fn in files:
    lines = open(os.path.join(HERE, 'data', fn), encoding='utf-8').read().split('\n')
    lines = [l for l in lines if l]
    assert len(lines) == 100, (fn, len(lines))
    for l in lines[::9]:
        d, rest = l.split(' ', 1)
        assert check(R, int(d), rest), (fn, d)
assert 0 < MAX_CMDS[0] < 900, MAX_CMDS      # the host draws about 1024 commands a screen
g.no_err()
print(f'draw commands, most on a screen: {MAX_CMDS[0]}')
print(f'freecell tests passed ({len(files)} solution files)')
