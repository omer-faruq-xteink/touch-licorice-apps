"""Lamplighter banks -> data/<level>.txt, one puzzle a line (all lines of a bank the same length,
so the app seeks straight to puzzle N).

A puzzle: an n x n grid of tiles, each a piece of wire joining its centre to some of its four
sides; one tile is the source, the tiles with one wire are lamps. Turned the right way, the wires
make one network: every tile joined, no loose ends, no loops, nothing leading off the board. The
tiles start turned at random; the player turns them back.

The line:  n, then n*n hex digits (the solution: bit 1 north, 2 east, 4 south, 8 west), then n*n
hex digits (the start), then the source's index (2 digits, 0-based, row by row).

Our own generator, no third-party puzzles. A random spanning tree of the grid is the solution
(Wilson's algorithm, so every tree is as likely); it is kept when reasoning alone (Solver) settles
every tile, which also proves that it is the only solution:
  - a wire cannot lead off the board, and two neighbours agree on the wire between them
  - a turn that would close a loop with the wires already settled is ruled out
  - a turn that would close off a group of tiles from the rest (no wire left that could join it
    to anything) is ruled out, unless the group is the whole board

    easy 5 x 5        medium 7 x 7        hard 9 x 9
The medium and hard puzzles need the loop and closed-group rules: the first alone does not
settle them.

  python -I apps/lamplighter/make_bank.py [COUNT]     # default 200 a level
"""
import os, random, sys

HERE = os.path.dirname(os.path.abspath(__file__))
LEVELS = [  # name, size, needs the loop and closed-group rules, seed
    ('easy', 5, False, 6101), ('medium', 7, True, 7102), ('hard', 9, True, 9103)]
N, E, S, W = 1, 2, 4, 8
DIRS = [(N, -1, 0, S), (E, 0, 1, W), (S, 1, 0, N), (W, 0, -1, E)]   # bit, dr, dc, opposite


def rot(m):
    """a quarter turn clockwise"""
    return ((m << 1) | (m >> 3)) & 15


def turns(m):
    out = []
    for _ in range(4):
        if m not in out:
            out.append(m)
        m = rot(m)
    return out


def spanning_tree(rng, n):
    """Wilson's algorithm: a uniform random spanning tree, as a wire mask per cell"""
    cells = n * n
    in_tree = [False] * cells
    nxt = [None] * cells
    mask = [0] * cells
    in_tree[rng.randrange(cells)] = True
    for start in range(cells):
        u = start
        while not in_tree[u]:
            r, c = divmod(u, n)
            opts = [(b, (r + dr) * n + c + dc) for b, dr, dc, _o in DIRS if 0 <= r + dr < n and 0 <= c + dc < n]
            nxt[u] = rng.choice(opts)
            u = nxt[u][1]
        u = start
        while not in_tree[u]:
            b, v = nxt[u]
            mask[u] |= b
            mask[v] |= {N: S, S: N, E: W, W: E}[b]
            in_tree[u] = True
            u = v
    return mask


class Solver:
    """cands[i]: the turns tile i may still have"""

    def __init__(self, n, tiles):
        self.n = n
        self.cands = [turns(m) for m in tiles]

    def nbr(self, i, b):
        r, c = divmod(i, self.n)
        for bb, dr, dc, o in DIRS:
            if bb == b:
                rr, cc = r + dr, c + dc
                if 0 <= rr < self.n and 0 <= cc < self.n:
                    return rr * self.n + cc, o
                return None, o

    def edge(self, i, b):
        """1 a wire, 0 none, None not yet known"""
        vals = {bool(m & b) for m in self.cands[i]}
        return vals.pop() if len(vals) == 1 else None

    def keep(self, i, ok):
        new = [m for m in self.cands[i] if ok(m)]
        if not new:
            raise ValueError('no turn left')
        if len(new) != len(self.cands[i]):
            self.cands[i] = new
            return True
        return False

    def local(self):
        changed = False
        for i in range(self.n * self.n):
            for b, _dr, _dc, _o in DIRS:
                j, o = self.nbr(i, b)
                if j is None:
                    changed |= self.keep(i, lambda m: not m & b)
                    continue
                e = self.edge(j, o)
                if e is not None:
                    changed |= self.keep(i, lambda m: bool(m & b) == e)
        return changed

    def known_wires(self):
        out = []
        for i in range(self.n * self.n):
            for b in (E, S):
                j, _o = self.nbr(i, b)
                if j is not None and self.edge(i, b) == 1 and self.edge(j, {E: W, S: N}[b]) == 1:
                    out.append((i, j))
        return out

    def global_(self):
        n2 = self.n * self.n
        wires = self.known_wires()
        changed = False
        for i in range(n2):
            if len(self.cands[i]) < 2:
                continue

            def ok(m):
                parent = list(range(n2))

                def find(x):
                    while parent[x] != x:
                        parent[x] = parent[parent[x]]
                        x = parent[x]
                    return x
                for a, b in wires:
                    if a == i or b == i:
                        continue
                    ra, rb = find(a), find(b)
                    if ra == rb:
                        return True        # a loop already: not this tile's doing
                    parent[ra] = rb
                for b, _dr, _dc, _o in DIRS:
                    if m & b:
                        j, _ = self.nbr(i, b)
                        if j is None:
                            return False
                        ri, rj = find(i), find(j)
                        if ri == rj:
                            return False   # closes a loop
                        parent[ri] = rj
                # the group i is in: can any of its tiles still reach out?
                root = find(i)
                group = [x for x in range(n2) if find(x) == root]
                if len(group) == n2:
                    return True
                for x in group:
                    for b, _dr, _dc, _o in DIRS:
                        j, o = self.nbr(x, b)
                        if j is None or find(j) == root:
                            continue
                        mine = (m & b) != 0 if x == i else self.edge(x, b)
                        if mine is None or mine:
                            return True
                return False
            changed |= self.keep(i, ok)
        return changed

    def run(self, use_global=True):
        try:
            while True:
                if self.local():
                    continue
                if not use_global or not self.global_():
                    break
        except ValueError:
            return 'contradiction'
        return 'solved' if all(len(c) == 1 for c in self.cands) else 'stuck'


def solved_by_reasoning(n, sol, use_global=True):
    s = Solver(n, sol)
    return s.run(use_global) == 'solved' and [c[0] for c in s.cands] == sol


def make(rng, n, harder):
    while True:
        sol = spanning_tree(rng, n)
        if not solved_by_reasoning(n, sol):
            continue
        if harder and solved_by_reasoning(n, sol, False):
            continue
        start = []
        for m in sol:
            for _ in range(rng.randrange(4)):
                m = rot(m)
            start.append(m)
        if sum(a != b for a, b in zip(start, sol)) < n * n // 2:
            continue                                    # too much right from the start
        # the source: a tile of three or four wires as near the middle as there is
        mid = (n - 1) / 2
        hubs = sorted(range(n * n), key=lambda i: (bin(sol[i]).count('1') < 3, abs(i // n - mid) + abs(i % n - mid)))
        return sol, start, hubs[0]


def encode(n, sol, start, src):
    hx = '0123456789abcdef'
    return str(n) + ''.join(hx[m] for m in sol) + ''.join(hx[m] for m in start) + f'{src:02d}'


def decode(line):
    n = int(line[0])
    sol = [int(ch, 16) for ch in line[1:1 + n * n]]
    start = [int(ch, 16) for ch in line[1 + n * n:1 + 2 * n * n]]
    return n, sol, start, int(line[1 + 2 * n * n:3 + 2 * n * n])


def main():
    count = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    os.makedirs(os.path.join(HERE, 'data'), exist_ok=True)
    for name, n, harder, seed in LEVELS:
        rng = random.Random(seed)
        lines, seen = [], set()
        while len(lines) < count:
            line = encode(n, *make(rng, n, harder))
            if line[1:1 + n * n] in seen:
                continue
            seen.add(line[1:1 + n * n])
            lines.append(line)
        with open(os.path.join(HERE, 'data', name + '.txt'), 'w', encoding='ascii', newline='\n') as f:
            f.write('\n'.join(lines) + '\n')
        print(f'{name}: {len(lines)} puzzles, {n}x{n}')


if __name__ == '__main__':
    main()
