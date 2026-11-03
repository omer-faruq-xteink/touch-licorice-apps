"""Queens and Star Battle banks -> data/<name>.txt, one puzzle a line: the n*n board, a letter a
cell naming its region ('a', 'b', ...), upper case where the one solution has a piece. Every line
of a bank has the same length, so the app seeks straight to puzzle N.

The rules: k pieces (queens: 1, Star Battle: 2) in every row, every column and every region, and
no two pieces touch, not even diagonally.

Our own generator, no third-party puzzles. A solution is placed at random; regions are grown
around it, none over twice the board's width (k pieces each: for two, small regions grown from
every piece are paired with a neighbour); then the regions are reshaped, a cell at a time, while that leaves fewer cells the
reasoning below cannot settle. A puzzle is kept when reasoning alone settles every cell, which
also proves its solution is the only one. The levels add techniques:

    1  a piece rules out its row, column and region once they are full, and the cells around it;
       a row, column or region with only as many cells left as pieces it still needs takes them
       all; a region whose cells left lie in one row (or column) rules out the rest of that row,
       and a row whose cells left lie in one region rules out the rest of that region
    2  the same for groups: two or three regions whose cells left lie in as many rows (or
       columns) rule out the rest of those rows, and the other way round
    3  a cell is ruled out when a piece there would, by level 1 alone, leave some row, column or
       region without room for its pieces

  python -I apps/queens/make_bank.py [COUNT]     # default 200 a bank
"""
import itertools, os, random, sys

HERE = os.path.dirname(os.path.abspath(__file__))
BANKS = [  # file, size, pieces per row/column/region, techniques allowed, not solved by level 1, seed
    ('queens-6x6', 6, 1, 1, False, 6201),
    ('queens-7x7', 7, 1, 2, False, 7202),
    ('queens-8x8', 8, 1, 3, True, 8203),
    ('queens-9x9', 9, 1, 3, True, 9204),
    ('stars-9x9', 9, 2, 3, False, 9205),          # 8x8 has only two two-star solutions
    ('stars-10x10', 10, 2, 3, True, 10206),
]


class Board:
    """Masks for an n*n board: bit i is cell i = r * n + c."""

    def __init__(self, n):
        self.n = n
        self.full = (1 << (n * n)) - 1
        self.rows = [sum(1 << (r * n + c) for c in range(n)) for r in range(n)]
        self.cols = [sum(1 << (r * n + c) for r in range(n)) for c in range(n)]
        self.around = []
        self.side = []
        for i in range(n * n):
            r, c = divmod(i, n)
            m = s = 0
            for dr in (-1, 0, 1):
                for dc in (-1, 0, 1):
                    rr, cc = r + dr, c + dc
                    if (dr or dc) and 0 <= rr < n and 0 <= cc < n:
                        m |= 1 << (rr * n + cc)
                        if not (dr and dc):
                            s |= 1 << (rr * n + cc)
            self.around.append(m)
            self.side.append(s)


def bits(m):
    while m:
        low = m & -m
        yield low.bit_length() - 1
        m ^= low


# ------------------------------------------------------------------ reasoning

def basic(B, k, units, stars, empty):
    """Level 1 without the line/region step: (stars, empty), or None on a contradiction."""
    while True:
        before = (stars, empty)
        for i in bits(stars):
            if B.around[i] & stars:
                return None
            empty |= B.around[i]
        if stars & empty:
            return None
        for u in units:
            s = (stars & u).bit_count()
            unk = u & ~(stars | empty)
            nu = unk.bit_count()
            if s > k or s + nu < k:
                return None
            if unk and s == k:
                empty |= unk
            elif unk and s + nu == k:
                stars |= unk
        if (stars, empty) == before:
            return stars, empty


def groups(B, k, regions, stars, empty, sizes):
    """Groups of m units of one kind whose cells left lie in m units of another kind: the rest of
    those is ruled out. Returns the new empty mask, or None on a contradiction."""
    kinds = (B.rows, B.cols, regions)
    for a in range(3):
        for b in range(3):
            if a == b:
                continue
            A, C = kinds[a], kinds[b]
            left = [u & ~empty for u in A]
            for m in sizes:
                for combo in itertools.combinations(range(len(A)), m):
                    cells = 0
                    for x in combo:
                        cells |= left[x]
                    cover, cm = 0, 0
                    for u in C:
                        if u & cells:
                            cover += 1
                            cm |= u
                            if cover > m:
                                break
                    if cover != m:
                        continue
                    inside = 0
                    for x in combo:
                        inside |= A[x]
                    out = cm & ~inside & ~empty
                    if out:
                        if out & stars:
                            return None
                        empty |= out
    return empty


def solve(B, k, regions, level, stars=0, empty=0):
    """How many cells reasoning up to level leaves open (0: solved, so the solution is unique),
    or -1 on a contradiction."""
    units = B.rows + B.cols + regions
    while True:
        r = basic(B, k, units, stars, empty)
        if r is None:
            return -1
        stars, empty = r
        open_ = B.full & ~(stars | empty)
        if not open_:
            return 0
        e2 = groups(B, k, regions, stars, empty, (1,))
        if e2 is None:
            return -1
        if e2 != empty:
            empty = e2
            continue
        if level >= 2:
            e2 = groups(B, k, regions, stars, empty, (2, 3))
            if e2 is None:
                return -1
            if e2 != empty:
                empty = e2
                continue
        if level >= 3:
            out = 0
            for i in bits(open_):
                if basic(B, k, units, stars | (1 << i), empty) is None:
                    out |= 1 << i
            if out:
                empty |= out
                continue
        return open_.bit_count()


# ------------------------------------------------------------------ making one

def place(B, k, rnd):
    """k pieces in every row and column, none touching: a mask, or None."""
    n = B.n
    rows_ok = [c for c in itertools.combinations(range(n), k) if all(b - a > 1 for a, b in zip(c, c[1:]))]
    count = [0] * n
    out = []

    def rec(r, prev):
        if r == n:
            return True
        opts = rows_ok[:]
        rnd.shuffle(opts)
        for c in opts:
            if any(count[x] >= k for x in c) or any(abs(x - p) <= 1 for x in c for p in prev):
                continue
            for x in c:
                count[x] += 1
            # the columns still need what the rows left can give
            if all(k - count[x] <= n - r - 1 for x in range(n)):
                out.append(c)
                if rec(r + 1, c):
                    return True
                out.pop()
            for x in c:
                count[x] -= 1
        return False

    if not rec(0, ()):
        return None
    return sum(1 << (r * n + c) for r, cs in enumerate(out) for c in cs)


def grow(B, seeds, rnd, cap):
    """Regions grown at random from the seed cells, none over cap cells: a list of masks."""
    n = B.n
    owner = [-1] * (n * n)
    size = [1] * len(seeds)
    for g, i in enumerate(seeds):
        owner[i] = g
    left = n * n - len(seeds)
    while left:
        i = rnd.randrange(n * n)
        if owner[i] >= 0:
            continue
        near = [owner[j] for j in bits(B.side[i]) if owner[j] >= 0]
        near = [g for g in near if size[g] < cap] or near
        if near:
            g = rnd.choice(near)
            owner[i] = g
            size[g] += 1
            left -= 1
    regs = [0] * len(seeds)
    for i, g in enumerate(owner):
        regs[g] |= 1 << i
    return regs


def connected(B, m):
    if not m:
        return False
    start = m & -m
    seen, todo = start, start
    while todo:
        i = (todo & -todo).bit_length() - 1
        todo &= todo - 1
        nxt = B.side[i] & m & ~seen
        seen |= nxt
        todo |= nxt
    return seen == m


def regions_for(B, k, stars, rnd):
    seeds = list(bits(stars))
    small = grow(B, seeds, rnd, B.n * 2 // k)
    if k == 1:
        return small
    # pair each small region with a neighbour (a random perfect matching)
    touch = [[j for j in range(len(small)) if j != i and any(B.side[x] & small[j] for x in bits(small[i]))] for i in range(len(small))]
    pair = {}

    def rec():
        free = [i for i in range(len(small)) if i not in pair]
        if not free:
            return True
        i = min(free, key=lambda x: sum(1 for j in touch[x] if j not in pair))
        opts = [j for j in touch[i] if j not in pair]
        rnd.shuffle(opts)
        for j in opts:
            pair[i], pair[j] = j, i
            if rec():
                return True
            del pair[i], pair[j]
        return False

    if not rec():
        return None
    return [small[i] | small[j] for i, j in pair.items() if i < j]


def make(n, k, level, harder, rnd, steps=400):
    B = Board(n)
    while True:
        stars = place(B, k, rnd)
        if stars is None:
            continue
        regs = regions_for(B, k, stars, rnd)
        if regs is None:
            continue
        score = solve(B, k, regs, level)
        owner = [0] * (n * n)
        for g, m in enumerate(regs):
            for i in bits(m):
                owner[i] = g
        for _ in range(steps):
            if score == 0:
                break
            i = rnd.randrange(n * n)
            if stars >> i & 1:
                continue
            near = list({owner[j] for j in bits(B.side[i])} - {owner[i]})
            if not near:
                continue
            g, h = owner[i], rnd.choice(near)
            if regs[h].bit_count() >= 2 * n or not connected(B, regs[g] & ~(1 << i)):
                continue
            regs[g] &= ~(1 << i)
            regs[h] |= 1 << i
            owner[i] = h
            sc = solve(B, k, regs, level)
            if 0 <= sc <= score:
                score = sc
            else:
                regs[h] &= ~(1 << i)
                regs[g] |= 1 << i
                owner[i] = g
        if score != 0 or (harder and solve(B, k, regs, 1) == 0):
            continue
        # name the regions in reading order, so equal puzzles give equal lines
        names = {}
        for i in range(n * n):
            names.setdefault(owner[i], len(names))
        return ''.join((chr(65 + names[owner[i]]) if stars >> i & 1 else chr(97 + names[owner[i]])) for i in range(n * n))


def parse(line):
    """For the test: (n, k, region masks, solution mask) of a bank line."""
    n = int(round(len(line) ** 0.5))
    B = Board(n)
    regs = [0] * n
    stars = 0
    for i, ch in enumerate(line):
        regs[ord(ch.lower()) - 97] |= 1 << i
        if ch.isupper():
            stars |= 1 << i
    return B, stars.bit_count() // n, regs, stars


def solved_by_reasoning(line, level=3):
    """For the test: reasoning settles every cell, and the pieces it finds are the line's."""
    B, k, regs, stars = parse(line)
    units = B.rows + B.cols + regs
    if any(not connected(B, m) for m in regs) or any((stars & u).bit_count() != k for u in units):
        return False
    if any(B.around[i] & stars for i in bits(stars)):
        return False
    return solve(B, k, regs, level) == 0


def _one(job):
    name, n, k, level, harder, seed = job
    return make(n, k, level, harder, random.Random(seed))


def main(count):
    import multiprocessing
    os.makedirs(os.path.join(HERE, 'data'), exist_ok=True)
    with multiprocessing.Pool() as pool:
        for name, n, k, level, harder, seed in BANKS:
            seen, out, extra = set(), [], 0
            while len(out) < count:
                jobs = [(name, n, k, level, harder, seed * 100000 + extra + j) for j in range(count - len(out))]
                extra += len(jobs)
                for s in pool.map(_one, jobs):
                    if s not in seen and len(out) < count:
                        seen.add(s)
                        out.append(s)
            with open(os.path.join(HERE, 'data', name + '.txt'), 'w', encoding='ascii', newline='\n') as f:
                f.write('\n'.join(out) + '\n')
            print(f'data/{name}.txt: {len(out)} puzzles', flush=True)


if __name__ == '__main__':
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 200)
