"""Generate the Suguru (Tectonic) puzzle banks in apps/suguru/data/.

  python apps/suguru/make_bank.py [--count 200] [--builtin-only]

Rules: the grid is split into regions of 1..5 cells; a region of n cells holds 1..n once each;
touching cells, diagonals included, never hold the same number.

Each puzzle: regions grown at random (mostly 4 and 5 cells, few singletons), a random full
solution found by backtracking, then givens taken away one by one as long as the puzzle stays
solvable BY LOGIC with the bank's techniques, as published Suguru are: one solution, reached
without guessing (a puzzle that logic solves has only that solution). The grader:

  Techniques, cheapest first, with PZL's scores (pzl.org.uk/suguru.html):
    basic (exclusion in the region, forbidden neighbour of a placed digit, naked single)  0
    hidden single          3   level 1
    naked pair             5   level 2
    hidden pair            6   level 2
    naked triple           7   level 2
    hidden triple          8   level 2
    forbidden neighbour    9   level 3   (every place left for a digit in a region touches one
                                           outside cell: that cell cannot hold the digit; PZL's
                                           forbidden pairs / triples are cases of it)
  Like PZL's solver, the cheapest technique that makes progress is used each step; the score adds
  the technique's score for every cell it changes.

Banks: easy uses singles only; medium, hard and expert use every technique above and must need
more than the basic steps; hard and expert keep the highest-scoring half of what is generated.
Each bank is sorted by score, easiest first. The generator is seeded per bank, so a run gives the
same files again.

One puzzle per line, all lines of a bank the same length (the packer turns that into a record file
the app seeks in): n*n region letters, then n*n digits (0 = empty), row by row. Region letters are
A-Z a-z 0-9 in order of first appearance.
"""
import argparse, itertools, os, random, time

HERE = os.path.dirname(os.path.abspath(__file__))
ALPHA = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
# file name (the app shows it as the bank's label), size, hardest technique level allowed, easiest
# level a puzzle must need, how many candidates per kept puzzle (the highest scores are kept)
BANKS = [('5x5-easy', 5, 1, 0, 1), ('6x6-medium', 6, 3, 1, 1), ('7x7-hard', 7, 3, 1, 2), ('8x8-expert', 8, 3, 1, 2)]


def neighbours8(n):
    out = []
    for r in range(n):
        for c in range(n):
            out.append([(r + dr) * n + c + dc for dr in (-1, 0, 1) for dc in (-1, 0, 1)
                        if (dr or dc) and 0 <= r + dr < n and 0 <= c + dc < n])
    return out


def orth(n, i):
    r, c = divmod(i, n)
    return [(r + dr) * n + c + dc for dr, dc in ((-1, 0), (1, 0), (0, -1), (0, 1)) if 0 <= r + dr < n and 0 <= c + dc < n]


def make_regions(n, rnd):
    """Grow regions of 1..5 cells; returns region index per cell."""
    reg = [-1] * (n * n)
    order = list(range(n * n))
    rnd.shuffle(order)
    k = 0
    for start in order:
        if reg[start] >= 0:
            continue
        target = rnd.choices([1, 2, 3, 4, 5], weights=[1, 3, 6, 10, 12])[0]
        cells = [start]
        reg[start] = k
        while len(cells) < target:
            frontier = [j for c in cells for j in orth(n, c) if reg[j] < 0]
            if not frontier:
                break
            j = rnd.choice(frontier)
            reg[j] = k
            cells.append(j)
        k += 1
    # merge singletons into a neighbour region when it stays at most 5 cells (keeps few 1-cell regions)
    sizes = {}
    for x in reg:
        sizes[x] = sizes.get(x, 0) + 1
    for i in range(n * n):
        if sizes[reg[i]] == 1 and rnd.random() < 0.8:
            opts = [reg[j] for j in orth(n, i) if sizes[reg[j]] < 5]
            if opts:
                t = rnd.choice(opts)
                sizes[reg[i]] -= 1
                reg[i] = t
                sizes[t] += 1
    return reg


class Puzzle:
    def __init__(self, n, reg):
        self.n, self.reg = n, reg
        self.nb = neighbours8(n)
        self.members = {}
        for i, r in enumerate(reg):
            self.members.setdefault(r, []).append(i)
        self.size = [len(self.members[r]) for r in reg]

    def cand_mask(self, grid, i):
        used = 0
        for j in self.nb[i]:
            used |= 1 << grid[j]
        for j in self.members[self.reg[i]]:
            used |= 1 << grid[j]
        return ((1 << (self.size[i] + 1)) - 2) & ~used

    def solve(self, grid, limit, rnd=None, budget=4000):
        """Count solutions up to limit; returns (count, first solution). Raises TooHard past budget nodes."""
        self.nodes, self.budget = 0, budget
        return self._solve(list(grid), limit, rnd)

    def _solve(self, grid, limit, rnd):
        self.nodes += 1
        if self.nodes > self.budget:
            raise TooHard()
        # propagate: a cell with one candidate takes it; a value with one place in its region goes there
        changed = True
        while changed:
            changed = False
            for i, v in enumerate(grid):
                if v == 0:
                    m = self.cand_mask(grid, i)
                    if m == 0:
                        return 0, None
                    if m & (m - 1) == 0:
                        grid[i] = m.bit_length() - 1
                        changed = True
            for r, cells in self.members.items():
                have = 0
                for i in cells:
                    have |= 1 << grid[i]
                for v in range(1, len(cells) + 1):
                    if have >> v & 1:
                        continue
                    places = [i for i in cells if grid[i] == 0 and self.cand_mask(grid, i) >> v & 1]
                    if not places:
                        return 0, None
                    if len(places) == 1:
                        grid[places[0]] = v
                        have |= 1 << v
                        changed = True
        best, best_m = None, None
        for i, v in enumerate(grid):
            if v == 0:
                m = self.cand_mask(grid, i)
                if best is None or bin(m).count('1') < bin(best_m).count('1'):
                    best, best_m = i, m
        if best is None:
            return 1, list(grid)
        vals = [v for v in range(1, 6) if best_m >> v & 1]
        if rnd:
            rnd.shuffle(vals)
        total, first = 0, None
        for v in vals:
            g2 = list(grid)
            g2[best] = v
            k, sol = self._solve(g2, limit - total, rnd)
            if k and first is None:
                first = sol
            total += k
            if total >= limit:
                break
        return total, first


class TooHard(Exception):
    pass


TECHNIQUES = [  # name, level, score
    ('hidden single', 1, 3),
    ('naked pair', 2, 5), ('hidden pair', 2, 6), ('naked triple', 2, 7), ('hidden triple', 2, 8),
    ('forbidden neighbour', 3, 9),
]


def grade(p, givens, max_level=3):
    """Solve by logic only. Returns (solved, hardest level used, score)."""
    n2 = len(givens)
    nb = [set(x) for x in p.nb]
    regions = [list(c) for c in p.members.values()]
    region_of = {}
    for k, cells in enumerate(regions):
        for i in cells:
            region_of[i] = k
    cand = [{givens[i]} if givens[i] else set(range(1, p.size[i] + 1)) for i in range(n2)]
    done = [False] * n2
    used_level, score = 0, 0

    def basic():
        changed = True
        while changed:
            changed = False
            for i in range(n2):
                if not done[i] and len(cand[i]) == 1:
                    done[i] = True
                    v = next(iter(cand[i]))
                    for j in nb[i] | set(regions[region_of[i]]):
                        if j != i and v in cand[j]:
                            cand[j].discard(v)
                            if not cand[j]:
                                return False
                            changed = True
        return True

    def hidden_single():
        hit = 0
        for cells in regions:
            for v in range(1, len(cells) + 1):
                pl = [i for i in cells if v in cand[i]]
                if len(pl) == 1 and len(cand[pl[0]]) > 1:
                    cand[pl[0]] = {v}
                    hit += 1
        return hit

    def naked(k):
        hit = 0
        for cells in regions:
            open_ = [i for i in cells if len(cand[i]) > 1]
            for combo in itertools.combinations(open_, k):
                union = set().union(*[cand[i] for i in combo])
                if len(union) == k:
                    for j in open_:
                        if j not in combo and cand[j] & union:
                            cand[j] -= union
                            hit += 1
            if hit:
                return hit
        return hit

    def hidden(k):
        hit = 0
        for cells in regions:
            open_ = [i for i in cells if len(cand[i]) > 1]
            vals = [v for v in range(1, len(cells) + 1) if any(v in cand[i] for i in open_)
                    and not any(cand[i] == {v} for i in cells)]
            for combo in itertools.combinations(vals, k):
                places = {i for i in open_ for v in combo if v in cand[i]}
                if len(places) == k:
                    for i in places:
                        if cand[i] - set(combo):
                            cand[i] &= set(combo)
                            hit += 1
            if hit:
                return hit
        return hit

    def forbidden_neighbour():
        hit = 0
        for cells in regions:
            cs = set(cells)
            for v in range(1, len(cells) + 1):
                pl = [i for i in cells if v in cand[i]]
                if len(pl) < 2:
                    continue
                for j in set.intersection(*[nb[i] for i in pl]) - cs:
                    if v in cand[j]:
                        cand[j].discard(v)
                        hit += 1
        return hit

    steps = [(hidden_single, 1, 3), (lambda: naked(2), 2, 5), (lambda: hidden(2), 2, 6),
             (lambda: naked(3), 2, 7), (lambda: hidden(3), 2, 8), (forbidden_neighbour, 3, 9)]
    while True:
        if not basic() or any(not c for c in cand):
            return False, used_level, score
        if all(done):
            return True, used_level, score
        progressed = False
        for fn, level, pts in steps:
            if level > max_level:
                break                                   # techniques above this bank's level
            hit = fn()
            if hit:
                used_level = max(used_level, level)
                score += pts * hit
                progressed = True
                break
        if not progressed:
            return False, used_level, score             # stuck: logic at this level cannot finish


def generate(n, max_level, min_level, rnd):
    """One puzzle line and its grade (level, score), solvable by logic up to max_level."""
    while True:
        p = Puzzle(n, make_regions(n, rnd))
        try:
            k, sol = p.solve([0] * (n * n), 1, rnd)
        except TooHard:
            continue                                   # a layout that is slow to fill: try another
        if not k:
            continue
        givens = list(sol)
        order = list(range(n * n))
        rnd.shuffle(order)
        for i in order:
            keep = givens[i]
            givens[i] = 0
            if not grade(p, givens, max_level)[0]:
                givens[i] = keep                       # logic can no longer finish: keep the given
        ok, level, score = grade(p, givens, max_level)
        assert ok
        if level < min_level:
            continue                                   # too easy for this bank
        names, letters = {}, []
        for r in p.reg:
            if r not in names:
                names[r] = ALPHA[len(names)]
            letters.append(names[r])
        return ''.join(letters) + ''.join(map(str, givens)), level, score


def update_builtin(per_bank=3):
    """Copy the first puzzles of the 5x5 and 6x6 banks into index.lua's fallback bank."""
    picks = []
    for name in ('5x5-easy', '6x6-medium'):
        with open(os.path.join(HERE, 'data', name + '.txt'), encoding='ascii') as f:
            picks += [l.strip() for l in f.readlines()[:per_bank]]
    path = os.path.join(HERE, 'index.lua')
    src = open(path, encoding='utf-8').read()
    a = src.index('local BUILTIN_PUZZLES = {')
    b = src.index('-- BUILTIN-END')
    nl = chr(10)
    block = 'local BUILTIN_PUZZLES = {' + nl + ''.join(f"  '{p}'," + nl for p in picks) + '}' + nl
    open(path, 'w', encoding='utf-8', newline=nl).write(src[:a] + block + src[b:])
    print(f'index.lua: {len(picks)} built-in puzzles')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--count', type=int, default=200)
    ap.add_argument('--builtin-only', action='store_true', help='only refresh the fallback bank in index.lua')
    a = ap.parse_args()
    if a.builtin_only:
        update_builtin()
        return
    out_dir = os.path.join(HERE, 'data')
    os.makedirs(out_dir, exist_ok=True)
    for name, n, max_level, min_level, pool in BANKS:
        rnd = random.Random('suguru-' + name)
        t0 = time.time()
        found, seen = [], set()
        while len(found) < a.count * pool:
            line, level, score = generate(n, max_level, min_level, rnd)
            if line not in seen:
                seen.add(line)
                found.append((score, line, level))
        found.sort(reverse=True)
        kept = sorted(found[:a.count])                 # the hardest a.count, then easiest first
        nl = chr(10)
        with open(os.path.join(out_dir, name + '.txt'), 'w', encoding='ascii', newline=nl) as f:
            f.write(nl.join(l for _, l, _ in kept) + nl)
        empty = sum(l[n * n:].count('0') for _, l, _ in kept) / len(kept)
        levels = {lv: sum(1 for *_, x in kept if x == lv) for lv in (0, 1, 2, 3)}
        print(f'{name}: {len(kept)} puzzles, {empty:.1f} empty cells on average, score {kept[0][0]}..{kept[-1][0]}, '
              f'hardest technique levels {levels}, {time.time() - t0:.1f} s')
    update_builtin()


if __name__ == '__main__':
    main()
