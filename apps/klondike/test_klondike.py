"""Offline test of Klondike (gamekit harness): reproducible deals, the stock and the waste (draw 1
and 3, turning the waste over), picking and placing by taps, face-down cards turned up, Undo,
Finish, whole deals played by following Hint (every card kept, columns valid), save and reload,
and the draw-command count.

  python -I apps/klondike/test_klondike.py
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

g = Game(HERE)
A = lambda: g.api
K, C = A().K, A().C
X0, CW, GAP, SLOT_Y, TAB_Y, CH = (int(v) for v in A().geometry())


def lst(t): return [int(v) for v in t.values()] if t else []


def all_cards(p):
    cards = lst(p.stock) + lst(p.waste)
    for k in range(1, 8):
        cards += lst(p.cols[k].cards)
    for s in range(4):
        cards += [s * 13 + r for r in range(1, int(p.home[s]) + 1)]
    return sorted(cards)


def check(p):
    assert all_cards(p) == list(range(1, 53)), 'a card was lost or doubled'
    for k in range(1, 8):
        col = p.cols[k]
        cards, down = lst(col.cards), int(col.down)
        assert 0 <= down < max(1, len(cards)) or (down == 0 and not cards), (k, down, cards)
        up = cards[down:]
        for a, b in zip(up, up[1:]):
            assert int(C.rank(a)) == int(C.rank(b)) + 1 and bool(C.red(a)) != bool(C.red(b)), (k, up)


def sx(k): return X0 + (k - 1) * (CW + GAP) + CW // 2


def tap_slot(k): g.tap(sx(k), SLOT_Y + 40)


def tap_card(k, i): g.tap(sx(k), int(A().card_y(k, i)) + 5)


def tap_col(k):
    n = len(lst(A().pos().cols[k].cards))
    g.tap(sx(k), int(A().card_y(k, n)) + 5 if n else TAB_Y + 20)


def follow(h):
    p = A().pos()
    if h['from'] == 'w':
        tap_slot(2)
    elif h['from'] == 'h':
        tap_slot(int(h['fi']) + 4)
    else:
        n = len(lst(p.cols[int(h['fi'])].cards))
        tap_card(int(h['fi']), n - int(h['n']) + 1)
    if h['to'] == 'h':
        tap_slot(int(h['ti']) + 4)
    else:
        tap_col(int(h['ti']))


# deals: seven columns of 1..7 with all but the top face down, 24 in the stock, reproducible
A().start(1)
p = A().pos()
assert [len(lst(p.cols[k].cards)) for k in range(1, 8)] == [1, 2, 3, 4, 5, 6, 7]
assert [int(p.cols[k].down) for k in range(1, 8)] == [0, 1, 2, 3, 4, 5, 6] and len(lst(p.stock)) == 24
check(p)
first = K.encode(p)
A().start(1)
assert K.encode(A().pos()) == first and K.encode(K.deal(2)) != first
t = g.texts()
assert 'Klondike  1' in t and 'Undo' in t and 'Hint' in t and 'New' in t and 'Draw 1' in t, t

# the stock: one card at a time, then the waste turned over
for _ in range(24):
    tap_slot(1)
p = A().pos()
assert len(lst(p.stock)) == 0 and len(lst(p.waste)) == 24
tap_slot(1)
assert len(lst(A().pos().stock)) == 24 and 'The waste is the stock again.' in g.texts()
g.tap_label('Undo')
assert len(lst(A().pos().waste)) == 24

# Draw 3 from the next deal on
g.tap_label('Draw 1')
assert 'Draw 3' in g.texts() and int(A().draw_n()) == 1
g.tap_label('New'); g.tap_label('Restart')
assert int(A().draw_n()) == 3
tap_slot(1)
assert len(lst(A().pos().waste)) == 3
g.tap_label('Draw 3')                                      # back to 1 for what follows

# a picked card that fits nowhere is let go; a face-down card cannot be picked
A().start(1)
tap_card(7, 1)
assert A().sel() is None and 'That card is face down.' in g.texts()

# Finish: nothing hidden, nothing to draw
won0 = int(g.store['game.txt'].split('won=')[1]) if 'won=' in g.store['game.txt'] else 0
fin = K.deal(1)
cards = list(range(1, 53))
fin.stock, fin.waste = g.L.table_from([]), g.L.table_from([])
for k in range(1, 8):
    fin.cols[k] = g.L.table_from({'cards': g.L.table_from([]), 'down': 0})
for s in range(4):                                         # each suit down from K in its own column
    fin.cols[s + 1] = g.L.table_from({'cards': g.L.table_from([s * 13 + r for r in range(13, 0, -1)]), 'down': 0})
g.L.globals().__fin = fin
assert K.can_finish(fin)
K.finish(fin)
assert K.won(fin)

# whole deals by Hint, through taps: every card kept, columns valid, the screen in budget
wins, worst = 0, 0
for d in range(1, 61):
    A().start(d)
    for _ in range(600):
        p = A().pos()
        check(p)
        if K.won(p):
            break
        worst = max(worst, g.commands())
        if K.can_finish(p):
            g.tap_label('Finish')
            continue
        g.tap_label('Hint')
        h = A().hint()
        if h is None:
            break
        if h == 'draw':
            tap_slot(1)
            continue
        before = K.encode(A().pos())
        follow(dict(h))
        assert K.encode(A().pos()) != before, ('the hinted move did not happen', dict(h))
    if K.won(A().pos()):
        wins += 1
        assert any('won!' in s for s in g.texts())
        g.tap_label('Close')
print(f'Hint alone won {wins} of 60 deals; most draw commands on a screen: {worst}')
assert wins >= 5 and worst < 900

# save and reload
A().start(77)
tap_slot(1); tap_slot(1)
mid = K.encode(A().pos())
g.restart()
assert K.encode(A().pos()) == mid and int(A().deal()) == 77
g.no_err()
print('klondike tests passed')
