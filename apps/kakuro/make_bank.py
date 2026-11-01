"""Kakuro (cross sums) banks -> data/<size>-<level>.txt, one puzzle a line: the n*n board with '#'
for a block and '1'..'9' for a white cell's digit in the one solution. The app works the clues out
of it (the sum of each run of white cells, across and down). Every line of a bank has the same
length, so the app seeks straight to puzzle N. The first row and column are always blocks.

Our own generator, no third-party puzzles. A layout is made symmetric under a half turn, every
white cell in an across and a down run of 2 or more, all white cells joined. It is filled with
digits at random (none twice in a run), then repaired: while reasoning leaves some cell open, the
digit of an open cell that closes the most is changed and the sums worked out again. A puzzle is
kept when this reasoning alone fills every cell:

    run reasoning: a run of L cells adding up to S, with no digit twice, can only be filled in
    certain ways (16 in 2 is 7+9 or 9+7); a cell keeps the digits that some filling of each of
    its runs, within the digits its cells can still take, gives it.

That also proves the solution is the only one. The levels differ by board size (and run length).

  python -I apps/kakuro/make_bank.py [COUNT]     # default 200 a bank
"""
import itertools, os, random, sys

HERE = os.path.dirname(os.path.abspath(__file__))
BANKS = [  # file, board size (with the clue row and column), white share, longest run, seed
    ('6x6-easy', 6, 0.70, 4, 6101),
    ('7x7-medium', 7, 0.66, 5, 7102),
    ('8x8-hard', 8, 0.66, 5, 8103),
]
COMBOS = {}
for L in range(2, 10):
    for c in itertools.combinations(range(1, 10), L):
        COMBOS.setdefault((L, sum(c)), []).append(c)
PERMS = {}


def perms(L, s):
    k = (L, s)
    if k not in PERMS:
        PERMS[k] = [p for c in COMBOS.get(k, []) for p in itertools.permutations(c)]
    return PERMS[k]


# ------------------------------------------------------------------ layout and fill

def runs_of(white, n):
    """Every across and down run of two or more white cells, as a tuple of cells."""
    out = []
    for horiz in (True, False):
        for a in range(n):
            run = []
            for b in range(n + 1):
                cell = (a, b) if horiz else (b, a)
                if b < n and white.get(cell):
                    run.append(cell)
                else:
                    if len(run) >= 2:
                        out.append(tuple(run))
                    run = []
    return out


def run_len(white, r, c, dr, dc):
    k = 1
    for s in (1, -1):
        rr, cc = r + dr * s, c + dc * s
        while white.get((rr, cc)):
            k += 1
            rr, cc = rr + dr * s, cc + dc * s
    return k


def layout(n, share, max_run, rnd):
    while True:
        white = {(r, c): r > 0 and c > 0 for r in range(n) for c in range(n)}
        def black(r, c):
            white[(r, c)] = False
            white[(n - r, n - c)] = False          # the half turn of an inner cell is inner too
        for _ in range(int((n - 1) ** 2 * (1 - share) / 2)):
            black(rnd.randrange(1, n), rnd.randrange(1, n))
        for _ in range(100):
            changed = False
            for r in range(1, n):
                for c in range(1, n):
                    if white[(r, c)] and (run_len(white, r, c, 0, 1) < 2 or run_len(white, r, c, 1, 0) < 2):
                        black(r, c)
                        changed = True
            for run in runs_of(white, n):
                if len(run) > max_run:
                    black(*run[rnd.randrange(1, len(run) - 1)])
                    changed = True
            if not changed:
                break
        cells = [p for p, w in white.items() if w]
        if len(cells) < (n - 1) ** 2 * share * 0.85:
            continue
        seen, stack = {cells[0]}, [cells[0]]
        while stack:
            r, c = stack.pop()
            for q in ((r + 1, c), (r - 1, c), (r, c + 1), (r, c - 1)):
                if white.get(q) and q not in seen:
                    seen.add(q)
                    stack.append(q)
        if len(seen) == len(cells):
            return white


def fill(white, n, rnd):
    cells = sorted(p for p, w in white.items() if w)
    runs = runs_of(white, n)
    of = {p: [r for r in runs if p in r] for p in cells}
    val = {}
    def rec(k):
        if k == len(cells):
            return True
        p = cells[k]
        used = {val[q] for r in of[p] for q in r if q in val}
        digits = [d for d in range(1, 10) if d not in used]
        rnd.shuffle(digits)
        for d in digits:
            val[p] = d
            if rec(k + 1):
                return True
            del val[p]
        return False
    return val if rec(0) else None


# ------------------------------------------------------------------ reasoning

def propagate(runs, cand):
    """Run reasoning until nothing changes; False on a contradiction. runs: [(cells, sum)]."""
    changed = True
    while changed:
        changed = False
        for cells, s in runs:
            cs = [cand[p] for p in cells]
            al = [set() for _ in cells]
            for perm in perms(len(cells), s):
                if all(perm[i] in cs[i] for i in range(len(cells))):
                    for i in range(len(cells)):
                        al[i].add(perm[i])
            for i, p in enumerate(cells):
                if not al[i]:
                    return False
                if len(al[i]) != len(cs[i]):
                    cand[p] = frozenset(al[i])
                    changed = True
    return True


def open_count(val, run_cells):
    runs = [(r, sum(val[p] for p in r)) for r in run_cells]
    cand = {p: frozenset(range(1, 10)) for p in val}
    propagate(runs, cand)
    return sum(len(v) - 1 for v in cand.values()), cand


def solved_by_reasoning(line, n):
    """For the test: a bank line is filled by run reasoning alone, to its own digits."""
    white = {(i // n, i % n): ch != '#' for i, ch in enumerate(line)}
    val = {(i // n, i % n): int(ch) for i, ch in enumerate(line) if ch != '#'}
    score, cand = open_count(val, runs_of(white, n))
    return score == 0 and all(cand[p] == {v} for p, v in val.items())


def make(n, share, max_run, rnd, iters=80):
    while True:
        white = layout(n, share, max_run, rnd)
        val = fill(white, n, rnd)
        if not val:
            continue
        run_cells = runs_of(white, n)
        of = {p: [r for r in run_cells if p in r] for p in val}
        score, cand = open_count(val, run_cells)
        for _ in range(iters):
            if score == 0:
                return ''.join(str(val[(r, c)]) if white[(r, c)] else '#' for r in range(n) for c in range(n))
            p = rnd.choice([q for q in val if len(cand[q]) > 1])
            used = {val[q] for r in of[p] for q in r if q != p}
            best, old = None, val[p]
            for d in range(1, 10):
                if d in used or d == old:
                    continue
                val[p] = d
                sc, c2 = open_count(val, run_cells)
                if best is None or sc < best[0]:
                    best = (sc, d, c2)
            if best and best[0] < score:
                val[p] = best[1]
                score, cand = best[0], best[2]
            else:
                val[p] = old


def main(count):
    os.makedirs(os.path.join(HERE, 'data'), exist_ok=True)
    for name, n, share, max_run, seed in BANKS:
        rnd = random.Random(seed)
        seen, out = set(), []
        while len(out) < count:
            s = make(n, share, max_run, rnd)
            if s not in seen:
                seen.add(s)
                out.append(s)
        with open(os.path.join(HERE, 'data', name + '.txt'), 'w', encoding='ascii', newline='\n') as f:
            f.write('\n'.join(out) + '\n')
        print(f'data/{name}.txt: {len(out)} puzzles, {sum(sum(ch != "#" for ch in s) for s in out) / len(out):.1f} white cells each', flush=True)


if __name__ == '__main__':
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 200)
