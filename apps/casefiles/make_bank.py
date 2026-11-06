"""Case Files banks -> data/<level>.txt, one case a line (all lines of a bank the same length, so
the app seeks straight to case N).

A case: a theme from src/themes.lua, its people and k - 1 of its groups, n of each; a secret
solution (who has what); and clues that settle the solution by reasoning alone, the reasoning a
player does on the grid. Our own generator and themes, no third-party puzzles.

    easy    3 groups of 4        medium  4 groups of 4        hard    4 groups of 5

The line:  T k n  then per group: g (its place in the theme, 0 = the people) and n pool letters
(the items picked, in their order), and for groups after the people n digits: the slot each
person has (person i is the i-th name); then ':' and the clues, ',' between them, padded with
'.' to the bank's width. An entity is 2 digits: group, slot (0-based, in the line's order).

    =AB     A and B are the same person          !AB     they are not
    eAXY    A is X or Y, exactly one of them
    oABXY   of A and B (one group), one is X and the other Y
    <ABg    A comes before B in ordered group g  +ABgd   A comes d steps after B in g

The reasoning (Solver): a grid cell is yes, no or open for every pair of items of two groups.
  - a yes rules out the rest of its row and column; a row or column with one open cell left and
    no yes takes it
  - across grids: a yes with a yes (or a no) gives a yes (or a no); and an item none of whose
    possible partners in a third group goes with Z does not go with Z
  - each clue rules out what it can given what is known (for order clues: the values each side
    can still have)
A case is kept when this settles every cell: its solution is then the only one. Clues are added
at random until it does, then each is dropped that is not needed.

  python -I apps/casefiles/make_bank.py [COUNT]     # default 200 a level
"""
import os, random, sys

from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
LEVELS = [  # name, groups, items per group, most clues, seed
    ('easy', 3, 4, 8, 3401),
    ('medium', 4, 4, 10, 4402),
    ('hard', 4, 5, 12, 5403),
]
B36 = '0123456789abcdefghijklmnopqrstuvwxyz'


def load_themes():
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    src = open(os.path.join(HERE, 'src', 'themes.lua'), encoding='utf-8').read()
    T = L.execute(src)
    out = []
    for i in range(1, len(T) + 1):
        th = T[i]
        groups = [{'size': len(th.names), 'ordered': False}]
        for j in range(1, len(th.groups) + 1):
            g = th.groups[j]
            groups.append({'size': len(g['items']), 'ordered': g.less is not None})
        out.append(groups)
    return out


class Contra(Exception):
    pass


class Case:
    """theme, k, n, gids (theme group of each group), pools (picked pool indices), perm[g][p] = slot"""

    def __init__(self, theme, k, n, gids, pools, perm, ordered):
        self.theme, self.k, self.n, self.gids, self.pools, self.perm, self.ordered = theme, k, n, gids, pools, perm, ordered
        self.owner = [[0] * n for _ in range(k)]
        for g in range(k):
            for p in range(n):
                self.owner[g][perm[g][p]] = p

    def who(self, e):
        return self.owner[e[0]][e[1]]

    def true(self, c):
        t, who = c[0], self.who
        if t == '=':
            return who(c[1]) == who(c[2])
        if t == '!':
            return who(c[1]) != who(c[2])
        if t == 'e':
            return (who(c[1]) == who(c[2])) != (who(c[1]) == who(c[3]))
        if t == 'o':
            a, b, x, y = (who(e) for e in c[1:5])
            return a != b and x != y and {a, b} == {x, y}
        if t == '<':
            g = c[3]
            return self.perm[g][who(c[1])] < self.perm[g][who(c[2])]
        if t == '+':
            g, d = c[3], c[4]
            return self.perm[g][who(c[1])] - self.perm[g][who(c[2])] == d
        raise ValueError(t)


class Solver:
    def __init__(self, k, n):
        self.k, self.n = k, n
        self.v = {}
        for g in range(k):
            for h in range(g + 1, k):
                for a in range(n):
                    for b in range(n):
                        self.v[(g, a, h, b)] = 0
        self.changed = False

    def copy(self):
        s = Solver.__new__(Solver)
        s.k, s.n, s.v, s.changed = self.k, self.n, dict(self.v), False
        return s

    def key(self, e1, e2):
        if e1[0] > e2[0]:
            e1, e2 = e2, e1
        return (e1[0], e1[1], e2[0], e2[1])

    def get(self, e1, e2):
        if e1[0] == e2[0]:
            return 1 if e1[1] == e2[1] else -1
        return self.v[self.key(e1, e2)]

    def set(self, e1, e2, val):
        if e1[0] == e2[0]:
            if (e1[1] == e2[1]) != (val == 1):
                raise Contra()
            return
        kk = self.key(e1, e2)
        cur = self.v[kk]
        if cur == val:
            return
        if cur != 0:
            raise Contra()
        self.v[kk] = val
        self.changed = True

    def done(self):
        return all(x != 0 for x in self.v.values())

    def poss(self, e, g):
        """the slots of ordered group g entity e may still have"""
        if e[0] == g:
            return {e[1]}
        return {o for o in range(self.n) if self.get(e, (g, o)) != -1}

    def lines(self):
        n, k = self.n, self.k
        for g in range(k):
            for h in range(g + 1, k):
                for a in range(n):
                    row = [self.v[(g, a, h, b)] for b in range(n)]
                    self.line_rule([(g, a)], [(h, b) for b in range(n)], row)
                for b in range(n):
                    col = [self.v[(g, a, h, b)] for a in range(n)]
                    self.line_rule([(h, b)], [(g, a) for a in range(n)], col)

    def line_rule(self, one, others, vals):
        e = one[0]
        ys = [i for i, x in enumerate(vals) if x == 1]
        if len(ys) > 1:
            raise Contra()
        if ys:
            for i, x in enumerate(vals):
                if i != ys[0] and x == 0:
                    self.set(e, others[i], -1)
            return
        opens = [i for i, x in enumerate(vals) if x == 0]
        if not opens:
            raise Contra()
        if len(opens) == 1:
            self.set(e, others[opens[0]], 1)

    def across(self):
        n, k = self.n, self.k
        for g in range(k):
            for h in range(k):
                if h == g:
                    continue
                for j in range(k):
                    if j == g or j == h:
                        continue
                    for a in range(n):
                        A = (g, a)
                        cands = [(h, b) for b in range(n) if self.get(A, (h, b)) != -1]
                        for c in range(n):
                            C = (j, c)
                            cur = self.get(A, C)
                            if cur != 0:
                                continue
                            if all(self.get(B, C) == -1 for B in cands):
                                self.set(A, C, -1)
                            elif any(self.get(A, B) == 1 and self.get(B, C) == 1 for B in cands):
                                self.set(A, C, 1)

    def clue(self, c):
        t, get, set_ = c[0], self.get, self.set
        if t == '=':
            set_(c[1], c[2], 1)
        elif t == '!':
            set_(c[1], c[2], -1)
        elif t == 'e':
            A, X, Y = c[1], c[2], c[3]
            if X[0] == Y[0]:
                for o in range(self.n):
                    if o != X[1] and o != Y[1]:
                        set_(A, (X[0], o), -1)
            else:
                set_(X, Y, -1)
            ax, ay = get(A, X), get(A, Y)
            if ax == -1:
                set_(A, Y, 1)
            if ay == -1:
                set_(A, X, 1)
            if ax == 1:
                set_(A, Y, -1)
            if ay == 1:
                set_(A, X, -1)
        elif t == 'o':
            A, B, X, Y = c[1:5]
            set_(A, B, -1)
            set_(X, Y, -1)
            for o in range(self.n):                         # the others of A's group are neither
                C = (A[0], o)
                if o != A[1] and o != B[1]:
                    set_(C, X, -1)
                    set_(C, Y, -1)
            for P, Q in ((A, B), (B, A)):
                for U, V in ((X, Y), (Y, X)):
                    if get(P, U) == -1:                      # P is V, Q is U
                        set_(P, V, 1)
                        set_(Q, U, 1)
                    if get(P, U) == 1:
                        set_(Q, V, 1)
        elif t in '<+':
            A, B, g = c[1], c[2], c[3]
            d = c[4] if t == '+' else None
            set_(A, B, -1)
            pa, pb = self.poss(A, g), self.poss(B, g)
            for o in pa:
                ok = (o - d in pb) if d else any(o2 > o for o2 in pb)
                if not ok:
                    set_(A, (g, o), -1)
            pa = self.poss(A, g)
            for o in pb:
                ok = (o + d in pa) if d else any(o1 < o for o1 in pa)
                if not ok:
                    set_(B, (g, o), -1)

    def run(self, clues):
        """reason until nothing changes: 'solved', 'stuck' or 'contradiction'"""
        try:
            while True:
                self.changed = False
                for c in clues:
                    self.clue(c)
                self.lines()
                if not self.changed:
                    self.across()
                if not self.changed:
                    break
        except Contra:
            return 'contradiction'
        return 'solved' if self.done() else 'stuck'


def solve(case, clues):
    s = Solver(case.k, case.n)
    return s.run(clues), s


def random_clue(rng, case, eq_ok):
    k, n, perm = case.k, case.n, case.perm
    ent = lambda g, p: (g, perm[g][p])
    ordered = [g for g in range(k) if case.ordered[g]]
    kinds = ['!', '!', 'e', 'e', 'o']
    if eq_ok:
        kinds.append('=')
    if ordered:
        kinds += ['<', '<', '+']
    t = rng.choice(kinds)
    if t == '=':
        p = rng.randrange(n)
        g, h = rng.sample(range(k), 2)
        return ('=', ent(g, p), ent(h, p))
    if t == '!':
        p, q = rng.sample(range(n), 2)
        g, h = rng.sample(range(k), 2)
        return ('!', ent(g, p), ent(h, q))
    if t == 'e':
        p, q = rng.sample(range(n), 2)
        gA = rng.randrange(k)
        others = [g for g in range(k) if g != gA]
        gX, gY = rng.choice(others), rng.choice(others)
        X, Y = ent(gX, p), ent(gY, q)
        if rng.random() < 0.5:
            X, Y = Y, X
        return ('e', ent(gA, p), X, Y)
    if t == 'o':
        p, q = rng.sample(range(n), 2)
        gA = rng.randrange(k)
        others = [g for g in range(k) if g != gA]
        gX, gY = rng.choice(others), rng.choice(others)
        X, Y = ent(gX, p), ent(gY, q)
        if rng.random() < 0.5:
            X, Y = Y, X
        A, B = ent(gA, p), ent(gA, q)
        if A[1] > B[1]:
            A, B = B, A
        return ('o', A, B, X, Y)
    g = rng.choice(ordered)
    p, q = rng.sample(range(n), 2)
    if perm[g][p] > perm[g][q]:
        p, q = q, p                                         # p before q
    others = [h for h in range(k) if h != g]
    A, B = ent(rng.choice(others), p), ent(rng.choice(others), q)
    if t == '<':
        return ('<', A, B, g)
    return ('+', B, A, g, perm[g][q] - perm[g][p])


def make_case(rng, themes, k, n, most):
    while True:
        ti = rng.randrange(len(themes))
        th = themes[ti]
        gids = [0] + sorted(rng.sample(range(1, len(th)), k - 1))
        ordered = [th[g]['ordered'] for g in gids]
        if not any(ordered):
            continue
        pools = []
        for g in gids:
            size = th[g]['size']
            if th[g]['ordered']:
                start = rng.randrange(size - n + 1)
                pools.append(list(range(start, start + n)))
            else:
                pools.append(sorted(rng.sample(range(size), n)))
        perm = [list(range(n))] + [rng.sample(range(n), n) for _ in range(k - 1)]
        case = Case(ti, k, n, gids, pools, perm, ordered)
        clues, s = [], Solver(k, n)
        eqs = 0
        tries = 0
        while not s.done() and tries < 400:
            tries += 1
            c = random_clue(rng, case, eqs < 1)
            if c in clues:
                continue
            assert case.true(c), c
            t = s.copy()
            r = t.run(clues + [c])
            assert r != 'contradiction', (c, clues)
            if t.v != s.v:
                clues.append(c)
                s = t
                eqs += c[0] == '='
        if not s.done():
            continue
        rng.shuffle(clues)
        for c in list(clues):
            rest = [x for x in clues if x is not c]
            if solve(case, rest)[0] == 'solved':
                clues = rest
        if len(clues) > most:
            continue
        if any(ordered) and not any(c[0] in '<+' for c in clues):
            continue
        # a sorted order reads better: = and ! first, then the rest as drawn
        rank = {'=': 0, '!': 1}
        clues.sort(key=lambda c: rank.get(c[0], 2))
        return case, clues


def ent_code(e):
    return f'{e[0]}{e[1]}'


def encode(case, clues):
    s = [B36[case.theme], str(case.k), str(case.n)]
    for g in range(case.k):
        s.append(str(case.gids[g]))
        s.append(''.join(B36[i] for i in case.pools[g]))
        if g > 0:
            s.append(''.join(str(x) for x in case.perm[g]))
    out = []
    for c in clues:
        t = c[0]
        if t in '=!':
            out.append(t + ent_code(c[1]) + ent_code(c[2]))
        elif t == 'e':
            out.append(t + ''.join(ent_code(e) for e in c[1:4]))
        elif t == 'o':
            out.append(t + ''.join(ent_code(e) for e in c[1:5]))
        elif t == '<':
            out.append(t + ent_code(c[1]) + ent_code(c[2]) + str(c[3]))
        else:
            out.append(t + ent_code(c[1]) + ent_code(c[2]) + str(c[3]) + str(c[4]))
    return ''.join(s) + ':' + ','.join(out)


def decode(line, themes):
    line = line.rstrip('.')
    head, cl = line.split(':')
    ti, k, n = B36.index(head[0]), int(head[1]), int(head[2])
    pos, gids, pools, perm = 3, [], [], []
    for g in range(k):
        gids.append(int(head[pos])); pos += 1
        pools.append([B36.index(ch) for ch in head[pos:pos + n]]); pos += n
        if g > 0:
            perm.append([int(ch) for ch in head[pos:pos + n]]); pos += n
        else:
            perm.append(list(range(n)))
    ordered = [themes[ti][g]['ordered'] for g in gids]
    case = Case(ti, k, n, gids, pools, perm, ordered)
    clues = []
    for code in cl.split(','):
        t = code[0]
        ents = lambda s, m: [(int(s[2 * i]), int(s[2 * i + 1])) for i in range(m)]
        if t in '=!':
            clues.append((t, *ents(code[1:], 2)))
        elif t == 'e':
            clues.append((t, *ents(code[1:], 3)))
        elif t == 'o':
            clues.append((t, *ents(code[1:], 4)))
        elif t == '<':
            clues.append((t, *ents(code[1:], 2), int(code[5])))
        else:
            clues.append((t, *ents(code[1:], 2), int(code[5]), int(code[6])))
    return case, clues


def main():
    count = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    themes = load_themes()
    os.makedirs(os.path.join(HERE, 'data'), exist_ok=True)
    for name, k, n, most, seed in LEVELS:
        rng = random.Random(seed)
        lines, seen = [], set()
        while len(lines) < count:
            case, clues = make_case(rng, themes, k, n, most)
            line = encode(case, clues)
            if line in seen:
                continue
            seen.add(line)
            lines.append(line)
        width = max(len(l) for l in lines)
        with open(os.path.join(HERE, 'data', name + '.txt'), 'w', encoding='ascii', newline='\n') as f:
            for l in lines:
                f.write(l.ljust(width, '.') + '\n')
        counts = [l.count(',') + 1 for l in lines]
        print(f'{name}: {len(lines)} cases, width {width}, clues {min(counts)}-{max(counts)} '
              f'(mean {sum(counts) / len(counts):.1f})')


if __name__ == '__main__':
    main()
