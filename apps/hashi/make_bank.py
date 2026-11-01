"""Hashi (Bridges) banks -> data/<size>-<level>.txt, one puzzle a line: n*n characters, '.' for
water and '1'..'8' for an island (its number of bridges). Every line of a bank has the same length,
so the app seeks straight to puzzle N.

Our own generator, no third-party puzzles. Islands are grown from one: an existing island sends a
bridge of one or two lines in a free direction to a new island, never crossing a bridge or touching
another island. The numbers are the bridge counts of that layout. A puzzle is kept when

- it has exactly one solution (a full search with propagation counts up to two), and
- it can be solved by reasoning alone, the way a person solves it:
    level 1  bounds: an island needs N more bridges and its neighbours can take at most so many,
             so some bridges are certain (and none can cross a placed bridge);
    level 2  isolation: a bridge that would close off a finished group of islands from the rest
             cannot be there (1-1, 2=2 and larger groups);
    level 3  one step of trial: a value that leads to a contradiction under levels 1-2 is out.
  Easy banks need level 1 at most, medium needs level 2, hard needs level 3.

  python -I apps/hashi/make_bank.py [COUNT]     # default 200 a bank
"""
import os, random, sys

HERE = os.path.dirname(os.path.abspath(__file__))
BANKS = [  # file, size, islands (min, max), required level, seed
    ('7x7-easy', 7, (10, 14), 1, 7001),
    ('9x9-medium', 9, (16, 22), 2, 9002),
    ('11x11-hard', 11, (24, 32), 3, 11003),
]
DIRS = ((0, 1), (1, 0), (0, -1), (-1, 0))


# ------------------------------------------------------------------ generating a layout

def grow(n, target, rnd):
    """A connected layout: {(r, c): number}, edges {(a, b): 1 or 2}; None when it gets stuck."""
    occ = {}                      # (r, c) -> 'I' island or 'H' / 'V' bridge
    start = (rnd.randrange(n), rnd.randrange(n))
    occ[start] = 'I'
    islands, edges = [start], {}
    tries = 0
    while len(islands) < target and tries < 4000:
        tries += 1
        a = rnd.choice(islands)
        dr, dc = rnd.choice(DIRS)
        length = rnd.randint(2, max(2, n // 2))
        r, c = a
        path, ok = [], True
        for k in range(1, length + 1):
            rr, cc = r + dr * k, c + dc * k
            if not (0 <= rr < n and 0 <= cc < n) or (rr, cc) in occ:
                ok = False
                break
            path.append((rr, cc))
        if not ok:
            continue
        b = path[-1]
        # the new island never touches another island side by side (keeps puzzles readable)
        if any(occ.get((b[0] + x, b[1] + y)) == 'I' for x, y in DIRS):
            continue
        for p in path[:-1]:
            occ[p] = 'H' if dr == 0 else 'V'
        occ[b] = 'I'
        islands.append(b)
        edges[(a, b)] = rnd.choice((1, 1, 2))
    if len(islands) < target:
        return None
    num = {i: 0 for i in islands}
    for (a, b), m in edges.items():
        num[a] += m
        num[b] += m
    return num


# ------------------------------------------------------------------ the puzzle as a graph

class Puzzle:
    def __init__(self, n, num):
        self.n, self.num = n, num
        self.isl = sorted(num)
        self.idx = {p: i for i, p in enumerate(self.isl)}
        self.edges = []           # (i, j, cells between)
        for p in self.isl:
            for dr, dc in ((0, 1), (1, 0)):
                r, c = p[0] + dr, p[1] + dc
                between = []
                while 0 <= r < n and 0 <= c < n and (r, c) not in num:
                    between.append((r, c))
                    r, c = r + dr, c + dc
                if 0 <= r < n and 0 <= c < n and between:
                    self.edges.append((self.idx[p], self.idx[(r, c)], frozenset(between)))
        self.cross = [[k for k, e in enumerate(self.edges) if k != j and e[2] & self.edges[j][2]]
                      for j in range(len(self.edges))]
        self.inc = [[k for k, e in enumerate(self.edges) if i in e[:2]] for i in range(len(self.isl))]
        self.need = [num[p] for p in self.isl]

    def line(self):
        g = ['.'] * (self.n * self.n)
        for (r, c), v in self.num.items():
            g[r * self.n + c] = str(v)
        return ''.join(g)


def propagate(P, lo, hi, level):
    """Narrow [lo, hi] per edge in place; False on a contradiction."""
    changed = True
    while changed:
        changed = False
        for k in range(len(P.edges)):
            if lo[k] > hi[k]:
                return False
            if lo[k] > 0:
                for x in P.cross[k]:
                    if hi[x] > 0:
                        if lo[x] > 0:
                            return False
                        hi[x] = 0
                        changed = True
        for i, ks in enumerate(P.inc):
            need = P.need[i]
            slo, shi = sum(lo[k] for k in ks), sum(hi[k] for k in ks)
            if slo > need or shi < need:
                return False
            for k in ks:
                nl = max(lo[k], need - (shi - hi[k]))
                nh = min(hi[k], need - (slo - lo[k]))
                if nl != lo[k] or nh != hi[k]:
                    lo[k], hi[k] = nl, nh
                    changed = True
                    if nl > nh:
                        return False
        if level >= 2 and not changed:
            changed = isolation(P, lo, hi)
            if changed is None:
                return False
    return True


def isolation(P, lo, hi):
    """Raise no bridge that would close off a finished group. Returns True when it narrowed
    something, False when not, None on a contradiction (a closed group already)."""
    m = len(P.isl)
    # groups joined by certain bridges
    parent = list(range(m))
    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    for k, (i, j, _b) in enumerate(P.edges):
        if lo[k] > 0:
            parent[find(i)] = find(j)
    groups = {}
    for i in range(m):
        groups.setdefault(find(i), []).append(i)
    if len(groups) == 1:
        return False
    # a group with no open capacity left and not everything: contradiction
    for g in groups.values():
        if all(sum(lo[k] for k in P.inc[i]) == P.need[i] for i in g):
            return None
    changed = False
    for k, (i, j, _b) in enumerate(P.edges):
        if hi[k] <= lo[k] or find(i) == find(j):
            continue
        gi, gj = groups[find(i)], groups[find(j)]
        # raising this edge to v closes the union when every island in it is then full
        for v in range(hi[k], lo[k], -1):
            if v <= lo[k]:
                break
            room = 0
            for g in (gi, gj):
                for x in g:
                    room += P.need[x] - sum(lo[q] for q in P.inc[x])
            if room == 2 * (v - lo[k]) and len(gi) + len(gj) < m:
                hi[k] = v - 1
                changed = True
            else:
                break
    return changed


def solve_logic(P, level):
    """True when reasoning up to `level` finishes the puzzle."""
    lo, hi = [0] * len(P.edges), [2] * len(P.edges)
    if not propagate(P, lo, hi, min(level, 2)):
        return False
    while level >= 3 and lo != hi:
        progress = False
        for k in range(len(P.edges)):
            if lo[k] == hi[k]:
                continue
            for v in range(lo[k], hi[k] + 1):
                tl, th = lo[:], hi[:]
                tl[k] = th[k] = v
                if not propagate(P, tl, th, 2):
                    if v == lo[k]:
                        lo[k] += 1
                    elif v == hi[k]:
                        hi[k] -= 1
                    else:
                        continue
                    progress = True
                    if not propagate(P, lo, hi, 2):
                        return False
                    break
        if not progress:
            break
    return lo == hi and connected(P, lo)


def connected(P, val):
    m = len(P.isl)
    adj = [[] for _ in range(m)]
    for k, (i, j, _b) in enumerate(P.edges):
        if val[k]:
            adj[i].append(j)
            adj[j].append(i)
    seen, stack = {0}, [0]
    while stack:
        x = stack.pop()
        for y in adj[x]:
            if y not in seen:
                seen.add(y)
                stack.append(y)
    return len(seen) == m


def count_solutions(P, limit=2):
    found = [0]
    def rec(lo, hi):
        if found[0] >= limit:
            return
        if not propagate(P, lo, hi, 1):
            return
        open_k = [k for k in range(len(P.edges)) if lo[k] != hi[k]]
        if not open_k:
            if connected(P, lo):
                found[0] += 1
            return
        k = min(open_k, key=lambda q: hi[q] - lo[q])
        for v in range(lo[k], hi[k] + 1):
            tl, th = lo[:], hi[:]
            tl[k] = th[k] = v
            rec(tl, th)
    rec([0] * len(P.edges), [2] * len(P.edges))
    return found[0]


def solution(line, n):
    """The bridges of a bank line's one solution, in the app's edge order (islands by cell, each
    island's edge to the right, then down)."""
    num = {(i // n, i % n): int(ch) for i, ch in enumerate(line) if ch != '.'}
    P = Puzzle(n, num)
    out = []
    def rec(lo, hi):
        if out or not propagate(P, lo, hi, 1):
            return
        open_k = [k for k in range(len(P.edges)) if lo[k] != hi[k]]
        if not open_k:
            if connected(P, lo):
                out.append(lo[:])
            return
        k = open_k[0]
        for v in range(lo[k], hi[k] + 1):
            tl, th = lo[:], hi[:]
            tl[k] = th[k] = v
            rec(tl, th)
    rec([0] * len(P.edges), [2] * len(P.edges))
    return P, out[0]


def make(n, isl_range, level, rnd):
    while True:
        num = grow(n, rnd.randint(*isl_range), rnd)
        if not num:
            continue
        P = Puzzle(n, num)
        if count_solutions(P) != 1:
            continue
        if not solve_logic(P, level):
            continue
        if level > 1 and solve_logic(P, level - 1):
            continue                      # too easy for this bank
        return P


def main(count):
    os.makedirs(os.path.join(HERE, 'data'), exist_ok=True)
    for name, n, isl, level, seed in BANKS:
        rnd = random.Random(seed)
        seen, out = set(), []
        while len(out) < count:
            P = make(n, isl, level, rnd)
            s = P.line()
            if s not in seen:
                seen.add(s)
                out.append(s)
        with open(os.path.join(HERE, 'data', name + '.txt'), 'w', encoding='ascii', newline='\n') as f:
            f.write('\n'.join(out) + '\n')
        print(f'data/{name}.txt: {len(out)} puzzles, {sum(sum(ch != "." for ch in s) for s in out) / len(out):.1f} islands each')


if __name__ == '__main__':
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 200)
