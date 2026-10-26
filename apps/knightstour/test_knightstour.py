"""Offline test of Knight's Tour (gamekit harness): placing the knight, ringed jumps, wrong taps,
complete tours on 6x6 and 8x8 (found by a search here), a dead end with its box and Undo, the
Warnsdorff hint, sizes, save and reload.

  python -I apps/knightstour/test_knightstour.py
"""
import os, random, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

JUMPS = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]


def tour(n, start):
    """A full tour by Warnsdorff with backtracking."""
    seen = {start}
    path = [start]

    def nxt(p):
        return [(p[0] + a, p[1] + b) for a, b in JUMPS if 1 <= p[0] + a <= n and 1 <= p[1] + b <= n and (p[0] + a, p[1] + b) not in seen]

    def rec():
        if len(path) == n * n:
            return True
        for q in sorted(nxt(path[-1]), key=lambda q: len(nxt(q))):
            seen.add(q); path.append(q)
            if rec():
                return True
            seen.discard(q); path.pop()
        return False
    assert rec()
    return path


g = Game(HERE)
def geo(): return [int(v) for v in g.api.geometry()]
def sq(r, c):
    cell, gx, gy = geo()
    return gx + (c - 1) * cell + cell // 2, gy + (r - 1) * cell + cell // 2
def visited(): return int(g.api.path())

t = g.texts()
assert "Knight's Tour" in t and '8x8    Visited 0/64    Best 0    Tours 0' in t, t
assert 'Tap any square to place the knight.' in t
g.tap(*sq(1, 1))
assert visited() == 1 and '1' in g.texts()
assert len([c for c in g.circles()]) == 2 * 3                 # two jumps from a corner, three rings each
g.tap(*sq(1, 2))
assert 'A knight cannot jump there.' in g.texts()
g.tap(*sq(1, 1))
assert 'Already visited.' in g.texts()
g.tap_label('Hint')
assert g.api.hint() is not None and 'Hint: the framed square (fewest onward jumps).' in g.texts()
g.tap_label('New')
assert visited() == 0

# complete tours
for n in (8, 6):
    if int(g.api.size()) != n:
        g.tap_label(f'{int(g.api.size())}x{int(g.api.size())}')
    assert int(g.api.size()) == n
    p = tour(n, (1, 1))
    for (r, c) in p:
        g.tap(*sq(r, c))
    t = g.texts()
    assert 'Tour complete!' in t and f'The knight visited all {n * n} squares.' in t, t
    g.tap_label('New')

# a dead end: random jumps until stuck, then the box offers Undo
rnd = random.Random(3)
while True:
    g.tap_label('New')
    n = int(g.api.size())
    seen, path = set(), [(1, 1)]
    seen.add((1, 1))
    while True:
        r, c = path[-1]
        opts = [(r + a, c + b) for a, b in JUMPS if 1 <= r + a <= n and 1 <= c + b <= n and (r + a, c + b) not in seen]
        if not opts:
            break
        q = rnd.choice(opts); seen.add(q); path.append(q)
    if len(path) < n * n:
        break
for (r, c) in path:
    g.tap(*sq(r, c))
t = g.texts()
assert 'No more moves' in t and f'{len(path)} of {n * n} squares visited.' in t, t
g.tap_label('Undo')
assert visited() == len(path) - 1

# save and reload
before = visited()
g.restart()
assert visited() == before and int(g.api.size()) == n
assert f'Best {n * n}    Tours 1' in ' '.join(g.texts()), g.texts()       # the full tour earlier on this size
g.no_err()
print('knightstour tests passed')
