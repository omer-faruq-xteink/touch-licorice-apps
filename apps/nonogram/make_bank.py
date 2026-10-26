"""Generate the Nonogram puzzles in apps/nonogram/src/bank.lua.

  python apps/nonogram/make_bank.py [--count 150]

Each puzzle is a picture: a random grid made blobby by a few smoothing steps, so it has shapes
rather than noise. A puzzle is kept only when a line solver finishes it, the way people solve
Nonograms: each row or column is solved on its own from its clue and the cells already known,
again and again, with no guessing. A puzzle that line solving finishes has exactly one solution.
Lines are also limited in how many clues they have, so the clue columns fit the 480 px screen
(see SIZES). The generator is seeded per size, so a run gives the same bank again.

bank.lua returns { [n] = { "<hex>", ... }, ... }: each puzzle's cells row by row, 1 = filled,
as hexadecimal, padded to whole digits.
"""
import argparse, os, random, time
from functools import lru_cache

HERE = os.path.dirname(os.path.abspath(__file__))
# size, most clues a row or column may have, fill share
SIZES = [(5, 3, 0.58), (8, 4, 0.56), (10, 4, 0.56), (12, 5, 0.56)]


def clues(line):
    out, run = [], 0
    for v in line:
        if v:
            run += 1
        elif run:
            out.append(run)
            run = 0
    if run:
        out.append(run)
    return tuple(out)


@lru_cache(maxsize=None)
def placements(n, clue):
    """All ways to lay clue out in a line of n cells, as tuples of 0/1."""
    if not clue:
        return (tuple([0] * n),)
    out = []
    first, rest = clue[0], clue[1:]
    need_rest = sum(rest) + len(rest)
    for start in range(0, n - first - need_rest + 1):
        head = [0] * start + [1] * first
        if rest:
            head.append(0)
            for tail in placements(n - len(head), rest):
                out.append(tuple(head) + tail)
        else:
            out.append(tuple(head + [0] * (n - len(head))))
    return tuple(out)


def solve_line(n, clue, known):
    """known: tuple of -1 / 0 / 1. Returns the new known tuple, or None when no placement fits."""
    fits = [p for p in placements(n, clue) if all(k < 0 or k == v for k, v in zip(known, p))]
    if not fits:
        return None
    out = list(known)
    for i in range(n):
        if out[i] < 0:
            vals = {p[i] for p in fits}
            if len(vals) == 1:
                out[i] = vals.pop()
    return tuple(out)


def line_solvable(n, rows, cols):
    grid = [[-1] * n for _ in range(n)]
    changed = True
    while changed:
        changed = False
        for r in range(n):
            new = solve_line(n, rows[r], tuple(grid[r]))
            if new is None:
                return False
            if list(new) != grid[r]:
                grid[r] = list(new)
                changed = True
        for c in range(n):
            col = tuple(grid[r][c] for r in range(n))
            new = solve_line(n, cols[c], col)
            if new is None:
                return False
            if new != col:
                for r in range(n):
                    grid[r][c] = new[r]
                changed = True
    return all(v >= 0 for row in grid for v in row)


def picture(n, fill, rnd):
    g = [[1 if rnd.random() < fill else 0 for _ in range(n)] for _ in range(n)]
    for _ in range(2):                                   # smoothing: a cell follows its neighbourhood
        h = [[0] * n for _ in range(n)]
        for r in range(n):
            for c in range(n):
                s = sum(g[rr][cc] for rr in range(max(0, r - 1), min(n, r + 2)) for cc in range(max(0, c - 1), min(n, c + 2)))
                cnt = (min(n, r + 2) - max(0, r - 1)) * (min(n, c + 2) - max(0, c - 1))
                h[r][c] = 1 if s * 2 > cnt or (s * 2 == cnt and rnd.random() < 0.5) else 0
        g = h
    return g


def make(n, max_clues, fill, rnd):
    while True:
        g = picture(n, fill, rnd)
        filled = sum(map(sum, g))
        if filled < n * n * 0.35 or filled > n * n * 0.75:
            continue
        rows = [clues(g[r]) for r in range(n)]
        cols = [clues([g[r][c] for r in range(n)]) for c in range(n)]
        if any(len(x) > max_clues for x in rows + cols) or any(not x for x in rows + cols):
            continue                                     # too many clues for the screen, or an empty line
        if line_solvable(n, rows, cols):
            bits = ''.join(str(v) for row in g for v in row)
            bits += '0' * (-len(bits) % 4)
            return '%0*x' % (len(bits) // 4, int(bits, 2))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--count', type=int, default=150)
    a = ap.parse_args()
    banks = {}
    for n, max_clues, fill in SIZES:
        rnd = random.Random(f'nonogram-{n}')
        t0 = time.time()
        seen, out = set(), []
        while len(out) < a.count:
            h = make(n, max_clues, fill, rnd)
            if h not in seen:
                seen.add(h)
                out.append(h)
        banks[n] = out
        print(f'{n}x{n}: {len(out)} puzzles, {time.time() - t0:.1f} s')
    lines = ['-- GENERATED by apps/nonogram/make_bank.py: line-solvable pictures, cells row by row as hex.',
             'return {']
    for n, items in banks.items():
        lines.append(f'  [{n}] = {{')
        for i in range(0, len(items), 6):
            lines.append('    ' + ' '.join(f"'{h}'," for h in items[i:i + 6]))
        lines.append('  },')
    lines.append('}')
    os.makedirs(os.path.join(HERE, 'src'), exist_ok=True)
    with open(os.path.join(HERE, 'src', 'bank.lua'), 'w', encoding='ascii', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')


if __name__ == '__main__':
    main()
