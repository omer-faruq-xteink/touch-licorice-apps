"""Generate the Suguru (Tectonic) puzzle banks in apps/suguru/data/.

  python apps/suguru/make_bank.py [--count 200] [--builtin-only]

Rules: the grid is split into regions of 1..5 cells; a region of n cells holds 1..n once each;
touching cells, diagonals included, never hold the same number.

Each puzzle: regions grown at random (mostly 4 and 5 cells, few singletons), a random full
solution found by backtracking, then givens taken away one by one as long as the solution stays
unique (checked by counting solutions up to two, with naked and hidden singles propagated;
a check that runs too long keeps the given). Easier banks get some givens back. The generator
is seeded per bank, so a run gives the same files again.

One puzzle per line, all lines of a bank the same length (the packer turns that into a record file
the app seeks in): n*n region letters, then n*n digits (0 = empty), row by row. Region letters are
A-Z a-z 0-9 in order of first appearance.
"""
import argparse, os, random, time

HERE = os.path.dirname(os.path.abspath(__file__))
ALPHA = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
# file name (the app shows it as the bank's label), size, share of the empty cells given back
BANKS = [('5x5-easy', 5, 0.30), ('6x6-medium', 6, 0.12), ('7x7-hard', 7, 0.0), ('8x8-expert', 8, 0.0)]


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


def generate(n, give_back, rnd):
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
            try:
                count, _ = p.solve(givens, 2)
            except TooHard:
                count = 2                              # not proven unique in time: keep the given
            if count != 1:
                givens[i] = keep
        empty = [i for i in range(n * n) if givens[i] == 0]
        for i in rnd.sample(empty, int(len(empty) * give_back)):
            givens[i] = sol[i]
        # region letters in order of first appearance
        names, letters = {}, []
        for r in p.reg:
            if r not in names:
                names[r] = ALPHA[len(names)]
            letters.append(names[r])
        return ''.join(letters) + ''.join(map(str, givens)), sol


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
    for name, n, give_back in BANKS:
        rnd = random.Random('suguru-' + name)
        t0 = time.time()
        lines, seen = [], set()
        while len(lines) < a.count:
            line, _ = generate(n, give_back, rnd)
            if line not in seen:
                seen.add(line)
                lines.append(line)
        with open(os.path.join(out_dir, name + '.txt'), 'w', encoding='ascii', newline='\n') as f:
            f.write('\n'.join(lines) + '\n')
        empty = sum(l[n * n:].count('0') for l in lines) / len(lines)
        print(f'{name}: {len(lines)} puzzles, {empty:.1f} empty cells on average, {time.time() - t0:.1f} s')
    update_builtin()


if __name__ == '__main__':
    main()
