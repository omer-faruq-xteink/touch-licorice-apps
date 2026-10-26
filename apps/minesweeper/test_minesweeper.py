"""Offline test of Minesweeper (gamekit harness): a safe first tap, boards that logic clears, flags
by long press and by Flag mode, chords, the Boom box and Undo, hints that win whole games, levels,
best times, save and reload.

  python -I apps/minesweeper/test_minesweeper.py
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

g = Game(HERE)
long_press = g.L.eval("function(x, y) on_input(ctx, {type='pointer', phase='down', x=x, y=y}); "
                      "on_input(ctx, {type='pointer', phase='hold', gesture='long', x=x, y=y}); "
                      "on_input(ctx, {type='pointer', phase='up', x=x, y=y}) end")
# the device repeats the hold event while the finger stays down
long_hold = g.L.eval("function(x, y) on_input(ctx, {type='pointer', phase='down', x=x, y=y}); "
                     "for k = 1, 4 do on_input(ctx, {type='pointer', phase='hold', gesture='long', x=x, y=y}) end; "
                     "on_input(ctx, {type='pointer', phase='up', x=x, y=y}) end")
A = lambda: g.api


def xy(i):
    cs, gx, gy = (int(v) for v in A().geometry())
    cols = int(A().cols())
    return gx + ((i - 1) % cols) * cs + cs // 2, gy + ((i - 1) // cols) * cs + cs // 2


def cells():
    return [str(A().cell(i)) for i in range(1, int(A().n()) + 1)]


def play_by_hints(limit=500):
    """win the running game from hints alone: open safe cells, flag mines"""
    for _ in range(limit):
        if str(A().state()) != 'play':
            return
        g.tap_label('Hint')
        h = A().hint()
        assert h is not None, g.texts()
        h = int(h)
        t = g.texts()
        if any('is a mine' in s for s in t):
            assert A().mine(h)
            long_press(*xy(h))
        else:
            assert any('is safe' in s for s in t), t
            assert not A().mine(h) and str(A().cell(h)) == 'h'
            g.tap(*xy(h))
    raise AssertionError('hints did not finish the game')


# fresh Normal board: 9x11, the first tap opens an empty area and never a mine
assert str(A().state()) == 'fresh' and int(A().level()) == 2 and int(A().n()) == 99
t = g.texts()
assert 'Minesweeper' in t and 'Tap any cell to start.' in t and 'Normal' in t and 'Dig' in t, t
g.tap(*xy(50))
assert str(A().state()) == 'play' and A().logic()
assert str(A().cell(50)) == 'o' and int(A().count(50)) == 0 and not A().mine(50)
assert sum(1 for i in range(1, 100) if A().mine(i)) == 17
opened = cells().count('o')
assert opened >= 9

# long press flags a hidden cell, long press again removes it; a tap on a flag does nothing
hidden = [i for i in range(1, 100) if str(A().cell(i)) == 'h']
h0 = hidden[0]
long_press(*xy(h0)); assert str(A().cell(h0)) == 'f'
assert 'Mines 16' in ' '.join(g.texts())
g.tap(*xy(h0)); assert str(A().cell(h0)) == 'f'
long_press(*xy(h0)); assert str(A().cell(h0)) == 'h'
long_hold(*xy(h0)); assert str(A().cell(h0)) == 'f'      # one flag, however long the press
long_hold(*xy(h0)); assert str(A().cell(h0)) == 'h'

# Flag mode: a tap flags; back to Dig
g.tap_label('Dig'); g.tap(*xy(h0)); assert str(A().cell(h0)) == 'f'
g.tap_label('Flag'); g.tap(*xy(h0)); assert str(A().cell(h0)) == 'f'      # Dig: a flag stays
long_press(*xy(h0)); assert str(A().cell(h0)) == 'h'

# a mine: Boom box, Undo takes it back
m = next(i for i in range(1, 100) if A().mine(i) and str(A().cell(i)) == 'h')
before = cells()
g.tap(*xy(m))
assert str(A().state()) == 'lost' and 'Boom!' in g.texts()
g.tap_label('Undo')
assert str(A().state()) == 'play' and cells() == before

# chord: a number with all its mines flagged opens its other neighbours
nb = None
for i in range(1, 100):
    if str(A().cell(i)) == 'o' and int(A().count(i)) > 0:
        r, c = (i - 1) // 9, (i - 1) % 9
        around = [rr * 9 + cc + 1 for rr in range(r - 1, r + 2) for cc in range(c - 1, c + 2)
                  if 0 <= rr < 11 and 0 <= cc < 9 and (rr, cc) != (r, c)]
        shut = [j for j in around if str(A().cell(j)) == 'h']
        if any(not A().mine(j) for j in shut):
            nb = (i, around, shut); break
assert nb
i, around, shut = nb
g.tap(*xy(i))
assert 'Flag' in ' '.join(g.texts()) and all(str(A().cell(j)) == 'h' for j in shut)     # flags first
for j in shut:
    if A().mine(j): long_press(*xy(j))
g.tap(*xy(i))
assert all(str(A().cell(j)) in ('o', 'f') for j in around)

# hints alone finish the game: the Cleared box, a best time, a win counted
g.advance(5000)
play_by_hints()
assert str(A().state()) == 'won' and 'Cleared!' in g.texts(), g.texts()
assert 'Won 1 of 1' in g.texts()
assert 'stats=1:0:0:0;2:1:1:' in g.store['game.txt']

# a wrong flag is the first hint
g.tap_label('New')
g.tap(*xy(1))
w = next(i for i in range(1, 100) if not A().mine(i) and str(A().cell(i)) == 'h')
long_press(*xy(w))
g.tap_label('Hint')
assert int(A().hint()) == w and 'Hint: this flag is wrong.' in g.texts()
long_press(*xy(w))

# save and reload mid-game
before = cells()
g.restart()
assert str(A().state()) == 'play' and cells() == before

# levels: Hard 10x13 / 27 mines, then Easy 8x10 / 10; cells stay big enough for a finger
g.tap_label('Normal')
assert int(A().level()) == 3 and int(A().n()) == 130 and str(A().state()) == 'fresh'
assert int(A().geometry()[0]) >= 43
g.tap_label('Hard')
assert int(A().level()) == 1 and int(A().n()) == 80 and int(A().geometry()[0]) == 56

# many games per level: logic clears each, and hints win each
for lv, name in ((1, 'Easy'), (2, 'Normal'), (3, 'Hard')):
    while int(A().level()) != lv:
        g.tap_label(['Easy', 'Normal', 'Hard'][int(A().level()) - 1])
    for k in range(25):
        g.tap_label('New')
        first = 1 + (k * 37) % int(A().n())
        g.tap(*xy(first))
        assert A().logic() and int(A().count(first)) == 0
        play_by_hints()
        assert str(A().state()) == 'won'
        g.tap_label('Close')
    cs, gx, gy = (int(v) for v in A().geometry())
    rows = int(A().n()) // int(A().cols())
    assert gy + rows * cs <= 704 - 34, (name, gy + rows * cs)                 # above the message line
g.no_err()
print('minesweeper tests passed')
