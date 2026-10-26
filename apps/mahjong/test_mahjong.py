"""Offline test of Mahjong Solitaire (gamekit harness): the deal (100 tiles, four of each kind, the
pyramid of stacks), free and blocked tiles, selecting and matching, Undo, Hint, Shuffle (same tiles,
same stacks), the stuck box, whole games played from hints, save and reload.

  python -I apps/mahjong/test_mahjong.py
"""
import collections, os, random, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

LAYOUT = [[1, 1, 1, 1, 1, 1, 1], [1, 2, 2, 2, 2, 2, 1], [1, 2, 3, 3, 3, 2, 1], [1, 2, 3, 4, 3, 2, 1],
          [1, 2, 3, 4, 3, 2, 1], [1, 2, 3, 3, 3, 2, 1], [1, 2, 2, 2, 2, 2, 1], [1, 1, 1, 1, 1, 1, 1]]
g = Game(HERE)
A = lambda: g.api


def xy(i):
    gx, gy, cw, ch = (int(v) for v in A().cell())
    return gx + ((i - 1) % 7) * cw + cw // 2, gy + ((i - 1) // 7) * ch + ch // 2


def board():
    return str(A().board()).split('.')


def kinds():
    return collections.Counter(ch for s in board() for ch in s)


MAX_CMDS = [0]


def play_by_hints(limit=400):
    """take hinted pairs; shuffle when stuck; returns the shuffles used"""
    for _ in range(limit):
        MAX_CMDS[0] = max(MAX_CMDS[0], g.commands())
        if int(A().tiles()) == 0:
            return int(A().shuffles())
        if 'No free pairs left' in g.texts():
            g.tap_label('Shuffle'); continue
        g.tap_label('Hint')
        a, b = A().hint()
        assert a and b and A().top(a) == A().top(b) and A().free(a) and A().free(b), (a, b, g.texts(), int(A().tiles()))
        assert "Hint: the two framed tiles match." in g.texts(), g.texts()
        g.tap(*xy(int(a))); g.tap(*xy(int(b)))
    raise AssertionError('not cleared')


# the deal: 100 tiles in the pyramid, four of each of 25 kinds
assert int(A().tiles()) == 100
assert [len(s) for s in board()] == [h for row in LAYOUT for h in row]
assert sorted(kinds().values()) == [4] * 25
t = g.texts()
assert 'Mahjong' in t and 'Undo' in t and 'Hint' in t and 'Shuffle' in t and 'New' in t, t

# free and blocked: row ends and the peak are free; the first row's middle and a flat step are blocked
assert A().free(1) and A().free(7) and A().free(25) and not A().free(4) and not A().free(10)
g.tap(*xy(4))
assert 'Blocked: a tile beside it on both sides.' in g.texts()

# select, deselect, match
g.tap_label('Hint')
a, b = (int(v) for v in A().hint())
g.tap(*xy(a)); assert int(A().sel()) == a
g.tap(*xy(a)); assert A().sel() is None
before = board()
g.tap(*xy(a)); g.tap(*xy(b))
assert int(A().tiles()) == 98 and A().sel() is None
g.tap_label('Undo')
assert board() == before

# Shuffle keeps the tiles and the stack heights
k0, h0 = kinds(), [len(s) for s in board()]
g.tap_label('Shuffle')
assert kinds() == k0 and [len(s) for s in board()] == h0 and int(A().shuffles()) == 1
g.tap_label('Undo')
assert board() == before and int(A().shuffles()) == 0

# save and reload
g.tap(*xy(a)); g.tap(*xy(b))
mid = board()
g.restart()
assert board() == mid

# whole games from hints: every one is cleared (with a shuffle now and then)
used, t0 = [], time.perf_counter()
for k in range(30):
    if k:
        g.tap_label('New'); g.tap_label('New game')
        assert int(A().tiles()) == 100
    used.append(play_by_hints())
    assert 'Board cleared!' in g.texts(), g.texts()
    g.tap_label('Close')
print('games cleared from hints, shuffles used:', collections.Counter(used), '%.0f ms per game' % ((time.perf_counter() - t0) * 1000 / 30))
assert set(used) == {0}, used

# games with random moves first: the plan follows the player (a kept plan clears without a
# shuffle); a lost one is found again or proved gone, quickly
def free_pairs():
    by = collections.defaultdict(list)
    for i in range(1, 57):
        if A().free(i): by[str(A().top(i))].append(i)
    return [(l[x], l[y]) for l in by.values() for x in range(len(l)) for y in range(x + 1, len(l))]


random.seed(7)
kept = 0
for k in range(20):
    if 'Close' in g.texts(): g.tap_label('Close')
    g.tap_label('New'); g.tap_label('New game')
    for _ in range(random.choice([5, 15, 30])):
        p = free_pairs()
        if not p: break
        a, b = random.choice(p); g.tap(*xy(a)); g.tap(*xy(b))
    if 'No free pairs left' in g.texts():
        g.tap_label('Undo')
    if A().has_plan():
        kept += 1
        assert A().plan_ok()
        assert play_by_hints() == 0
    else:
        t0 = time.perf_counter(); g.tap_label('Hint')
        assert time.perf_counter() - t0 < 0.5
        assert any(x in g.texts() for x in ('Hint: the two framed tiles match.', 'No way to clear from here: Undo or Shuffle.', 'No free pairs left'))
assert kept >= 12, kept
assert 0 < MAX_CMDS[0] < 900, MAX_CMDS      # the host draws about 1024 commands a screen
print(f'draw commands, most on a screen: {MAX_CMDS[0]}')
g.no_err()
print('mahjong tests passed')
