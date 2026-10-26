"""Offline test of Peg Solitaire (gamekit harness): selection and marked targets, jumps, undo, a full
game to one peg in the centre of the English board and to one peg on the triangle (sequences found
by a small search here), the end box and best results, board switching, save and reload.

  python -I apps/pegsolitaire/test_pegsolitaire.py
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

ENGLISH = [(r, c) for r in range(1, 8) for c in range(1, 8) if 3 <= r <= 5 or 3 <= c <= 5]
TRIANGLE = [(r, c) for r in range(1, 6) for c in range(1, r + 1)]
DIRS = {'english': [(0, 1), (0, -1), (1, 0), (-1, 0)],
        'triangle': [(0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (-1, -1)]}


def solve(cells, dirs, start, goal=None):
    """A jump sequence to one peg (on goal, if given), by depth-first search with failed states memo."""
    cells_set = set(cells)
    pegs = frozenset(c for c in cells if c != start)
    dead = set()

    def rec(p, path):
        if len(p) == 1:
            return path if (goal is None or goal in p) else None
        if p in dead:
            return None
        for (r, c) in sorted(p):
            for dr, dc in dirs:
                o, t = (r + dr, c + dc), (r + 2 * dr, c + 2 * dc)
                if t in cells_set and o in p and t not in p:
                    res = rec((p - {(r, c), o}) | {t}, path + [((r, c), t)])
                    if res:
                        return res
        dead.add(p)
        return None
    return rec(pegs, [])


g = Game(HERE)
def xy(r, c):
    x, y = g.api.cell_xy(r, c)
    return int(x), int(y)
def count(): return int(g.api.count())

t = g.texts()
assert 'Peg Solitaire' in t and any(x.startswith('English    Pegs 32    Jumps 0') for x in t), t
assert not any(r.fill for r in g.rects())

# a peg that cannot jump says so; one that can is framed and its target holes are marked
g.tap(*xy(1, 3))
assert 'That peg cannot jump.' in g.texts()
g.tap(*xy(2, 4))
assert 'Tap a marked hole to jump.' in g.texts()
marks = [c for c in g.circles() if int(c.r) in (14, 13, 12)]
assert len(marks) == 3 and {(int(c.x), int(c.y)) for c in marks} == {xy(4, 4)}, marks     # one hole, three rings
g.tap(*xy(4, 4))
assert count() == 31 and any(x.startswith('English    Pegs 31    Jumps 1') for x in g.texts())
g.tap(*xy(5, 4))                                       # can jump into (3, 4)
g.tap(*xy(2, 4))                                       # an empty hole that is not its target
assert 'Pick one of the marked holes.' in g.texts()
g.tap(*xy(5, 4))                                       # tapping the selected peg lets it go
assert 'Tap a peg, then the hole to jump to.' in g.texts()
g.tap_label('Undo')
assert count() == 32

# a whole game to one peg in the centre
seq = solve(ENGLISH, DIRS['english'], (4, 4), goal=(4, 4))
assert seq and len(seq) == 31
for (fr, to) in seq:
    g.tap(*xy(*fr)); g.tap(*xy(*to))
t = g.texts()
assert 'No more jumps' in t and 'Perfect: one peg, in the centre!' in t and 'Best on this board: 1 peg' in t, t
assert 'best=english:1' in g.store['game.txt']
g.tap_label('Undo')                                    # back one jump from the end box
assert count() == 2
g.tap_label('New')
assert count() == 32

# the triangle: 14 pegs, six directions; a game to one peg
g.tap_label('English')
t = g.texts()
assert any(x.startswith('Triangle    Pegs 14') for x in t), t
seq = solve(TRIANGLE, DIRS['triangle'], (1, 1))
assert seq and len(seq) == 13
for (fr, to) in seq:
    g.tap(*xy(*fr)); g.tap(*xy(*to))
t = g.texts()
assert 'Excellent: one peg left!' in t, t
g.tap_label('New')

# save and reload mid-game, then Undo still works
g.tap(*xy(3, 1)); g.tap(*xy(1, 1))
assert count() == 13
g.restart()
assert any(x.startswith('Triangle    Pegs 13    Jumps 1    Best 1') for x in g.texts()), g.texts()
g.tap_label('Undo')
assert count() == 14
g.no_err()
print('pegsolitaire tests passed')
