"""Generate the built-in life-and-death problems of the Go problems app.

  python -I apps/tsumego/make_problems.py [COUNT_PER_LEVEL] [SEED]

Each problem is a corner position made here (no collection's problems are copied): an eye space
along the edge, the defender's stones around it, the attacker's wall around those, and a few
random weaknesses (a gap, a cutting stone, a stone inside). goboard.py reads it out. A position
is kept when its status depends on who plays first and exactly one first move works; it becomes
"Black to kill" or "Black to live". The solution tree holds every correct move of the player,
the strongest reply of the other side, and for each wrong first move the reply that refutes it.
A line ends when the position is settled: the group dead (or alive) even if the other side got
two moves in a row.

Output: data/<level>.txt, one SGF game tree per line (the app reads these and the player's own
SGF files the same way). Levels by the number of moves the player makes on the main line.
"""
import os, random, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from goboard import Board, Problem, EMPTY, ATT, DEF  # noqa: E402
N = 9
BOARD = Board(N)
LEVELS = [('beginner', 1, 1), ('intermediate', 2, 2), ('advanced', 3, 9)]   # name, user moves on the main line
MAX_TREE = 80          # nodes in a solution tree
LETTERS = 'abcdefghijklmnopqrs'


def idx(r, c): return r * N + c


def grow_shape(rng, k):
    """a connected eye space of k points along the top edge, near the corner"""
    start = (0, rng.randint(0, 2))
    S = {start}
    while len(S) < k:
        frontier = []
        for (r, c) in S:
            for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                rr, cc = r + dr, c + dc
                if 0 <= rr <= 2 and 0 <= cc <= 5 and (rr, cc) not in S:
                    frontier.append((rr, cc))
        if not frontier:
            break
        weights = [4 if r == 0 else (2 if r == 1 else 1) for (r, c) in frontier]
        S.add(rng.choices(frontier, weights)[0])
    return S


def neighbours(cells, diagonal=False):
    steps = ((1, 0), (-1, 0), (0, 1), (0, -1)) + (((1, 1), (1, -1), (-1, 1), (-1, -1)) if diagonal else ())
    out = set()
    for (r, c) in cells:
        for dr, dc in steps:
            rr, cc = r + dr, c + dc
            if 0 <= rr < N and 0 <= cc < N and (rr, cc) not in cells:
                out.add((rr, cc))
    return out


def target_of(b):
    """a stone of the largest defender chain, and its size"""
    best, target, seen = 0, None, set()
    for i in range(N * N):
        if b[i] == DEF and i not in seen:
            stones, _l = BOARD.chain(b, i)
            seen |= stones
            if len(stones) > best:
                best, target = len(stones), min(stones)
    return target, best


def sound(b, region, wall):
    """every stone inside the region has a liberty (nothing left that should have been captured)"""
    for i in region:
        if b[i] != EMPTY:
            stones, libs = BOARD.chain(b, i)
            if not libs and not (stones & wall):
                return False
    return True


def base_position(rng, k):
    """an eye space S along the edge, a solid defender wall D around it, the attacker's wall A"""
    S = grow_shape(rng, k)
    if rng.random() < 0.5:                                    # along the left edge instead
        S = {(c, r) for (r, c) in S}
    D = neighbours(S, diagonal=True)                          # diagonal corners too: one solid chain
    A = neighbours(S | D)
    if any(r >= N - 1 or c >= N - 1 for (r, c) in A):
        return None
    b = [EMPTY] * (N * N)
    for p in D: b[idx(*p)] = DEF
    for p in A: b[idx(*p)] = ATT
    return b, {idx(*p) for p in A}, {idx(*p) for p in S | D}, sorted(idx(*p) for p in S), sorted(idx(*p) for p in D)


def weaken(rng, b, S, D):
    op = rng.random()
    if op < 0.35:                                             # a gap in the defender's wall at the edge
        cand = [i for i in D if b[i] == DEF and (i < N or i % N == 0)]
        if cand: b[rng.choice(cand)] = EMPTY; return True
    elif op < 0.55:                                           # an attacker's stone in the wall
        cand = [i for i in D if b[i] == DEF]
        if cand: b[rng.choice(cand)] = ATT; return True
    else:                                                     # an attacker's stone inside
        cand = [i for i in S if b[i] == EMPTY]
        if cand: b[rng.choice(cand)] = ATT; return True
    return False


def strengthen(rng, b, S, D):
    op = rng.random()
    if op < 0.4:                                              # an attacker's stone taken away
        cand = [i for i in S + D if b[i] == ATT]
        if cand: b[rng.choice(cand)] = EMPTY if rng.random() < 0.5 or rng.choice(cand) in S else DEF; return True
    elif op < 0.7:                                            # a gap filled
        cand = [i for i in D if b[i] == EMPTY]
        if cand: b[rng.choice(cand)] = DEF; return True
    cand = [i for i in S if b[i] == EMPTY]                    # a defender's stone inside
    if cand: b[rng.choice(cand)] = DEF; return True
    return False


def make_position(rng, k):
    """a position near the boundary between life and death: weakened while the group lives
    whoever plays first, strengthened while it dies whoever plays first"""
    base = base_position(rng, k)
    if not base:
        return None
    b, wall, region, S, D = base
    for _step in range(10):
        target, size = target_of(b)
        if size < 3 or not sound(b, region, wall):
            return None
        P = Problem(BOARD, b, wall, region, target)
        a, d = P.solve(b, ATT), P.solve(b, DEF)
        if P.uncertain:
            return None
        if a and not d:
            return b, wall, region, target
        if not a:
            weaken(rng, b, S, D)
        else:
            strengthen(rng, b, S, D)
    return None


class Tree:
    """the solution tree for the player (user) colour: ATT to kill, DEF to live"""

    def __init__(self, P, user):
        self.P, self.user = P, user
        self.opp = DEF if user == ATT else ATT
        self.nodes = 0
        self.work = 0
        self.has_ko = False
        self.cache = {}

    def user_wins(self, b, ko, to_move):
        att = self.P.solve(b, to_move, ko)
        return att if self.user == ATT else not att

    def settled(self, b, ko):
        """after the user's move: still won if the other side got two moves in a row"""
        P = self.P
        if self.user == ATT and b[P.target] != DEF:
            return True
        if self.user == DEF and P.alive(b):
            return True
        for m1, b1, k1, _c in P.children(b, self.opp, ko):
            for m2, b2, k2, _c2 in P.children(b1, self.opp, None):
                if not self.user_wins(b2, k2, self.user):
                    return False
        return True

    def build_user(self, b, ko, depth):
        """{move: (comment, child)}: every winning move of the user here"""
        if depth > 8:
            raise ValueError('too deep')
        key = (bytes(b), ko)
        if key in self.cache:
            return self.cache[key]
        self.work += 1
        if self.work > 400:
            raise ValueError('too much work')
        out = {}
        for m, nb, nko, _c in self.P.children(b, self.user, ko):
            if m is None:
                continue
            if self.user_wins(nb, nko, self.opp):
                if nko is not None:
                    self.has_ko = True
                self.nodes += 1
                if self.nodes > MAX_TREE:
                    raise ValueError('tree too big')
                if self.settled(nb, nko):
                    out[m] = ('RIGHT', None)
                else:
                    out[m] = (None, self.build_opp(nb, nko, depth + 1))
        self.cache[key] = out
        return out

    def build_opp(self, b, ko, depth):
        """(reply, subtree): a real move rather than a pass, then the one that holds out longest"""
        best = None
        for m, nb, nko, _c in self.P.children(b, self.opp, ko):
            saved = self.nodes
            sub = self.build_user(nb, nko, depth)
            d = depth_of(sub)
            key = (m is not None, d)
            if best is None or key > best[0]:
                if best is not None:
                    self.nodes -= best[3]
                best = (key, m, sub, self.nodes - saved)
            else:
                self.nodes = saved
            if nko is not None and best[1] == m:
                self.has_ko = True
        return best[1], best[2]


def depth_of(user_node):
    """user moves on the longest line"""
    d = 0
    for _m, (_c, child) in user_node.items():
        d = max(d, 1 + (depth_of(child[1]) if child else 0))
    return d


def first_line(user_node):
    d = 0
    node = user_node
    while node:
        m = next(iter(node))
        d += 1
        c, child = node[m]
        node = child[1] if child else None
    return d


# -- SGF
def coord(i, flip):
    r, c = divmod(i, N)
    if flip & 1: c = 18 - c
    if flip & 2: r = 18 - r
    return LETTERS[c] + LETTERS[r]


def sgf_user(node, colours, flip):
    """variations of the user's moves at this node"""
    parts = []
    for m, (comment, child) in node.items():
        s = ';' + colours[0] + '[' + coord(m, flip) + ']'
        if comment:
            s += 'C[' + comment + ']'
        if child:
            reply, sub = child
            s += ';' + colours[1] + '[' + ('' if reply is None else coord(reply, flip)) + ']'
            s += sgf_user(sub, colours, flip)
        parts.append(s)
    if len(parts) == 1:
        return parts[0]
    return ''.join('(' + p + ')' for p in parts)


def to_sgf(P, b, user, node, wrong, flip, name):
    black = user                                       # the player is Black
    ab = [i for i in range(N * N) if b[i] == black]
    aw = [i for i in range(N * N) if b[i] != EMPTY and b[i] != black]
    task = 'Black to kill' if user == ATT else 'Black to live'
    head = '(;GM[1]FF[4]SZ[19]PL[B]GN[' + name + ']C[' + task + ']'
    head += 'AB' + ''.join('[' + coord(i, flip) + ']' for i in ab)
    head += 'AW' + ''.join('[' + coord(i, flip) + ']' for i in aw)
    vars_ = []
    right = sgf_user(node, ('B', 'W'), flip)
    vars_.append(right)
    for m, reply in wrong:
        vars_.append(';B[' + coord(m, flip) + ']C[WRONG];W[' + ('' if reply is None else coord(reply, flip)) + ']')
    return head + ''.join('(' + v + ')' for v in vars_) + ')'


def canonical(b, region):
    """the position up to the corner's mirror (rows and columns swapped)"""
    a = ''.join(str(b[i]) for i in range(N * N))
    t = ''.join(str(b[c * N + r]) for r in range(N) for c in range(N))
    return min(a, t)


def attempt(rng, k):
    pos = make_position(rng, k)
    if not pos:
        return None
    b, wall, region, target = pos
    P = Problem(BOARD, b, wall, region, target)
    att_first = P.solve(b, ATT)
    def_first = P.solve(b, DEF)
    if P.uncertain or not att_first or def_first:
        return None                                          # settled already, or unclear
    user = ATT if rng.random() < 0.6 else DEF               # kill problems a little more often
    T = Tree(P, user)
    wins = [m for m, nb, nko, _c in P.children(b, user, None)
            if m is not None and T.user_wins(nb, nko, T.opp)]
    if len(wins) != 1:
        return None
    try:
        node = T.build_user(b, None, 0)
    except (ValueError, RecursionError):
        return None
    if T.has_ko or P.uncertain or not node:
        return None
    wrong = []
    for m, nb, nko, _c in P.children(b, user, None):
        if m is None or m in node:
            continue
        for r, b2, k2, _c2 in P.children(nb, T.opp, nko):
            if not T.user_wins(b2, k2, user):
                wrong.append((m, r))
                break
    return P, b, user, node, wrong


TARGETS = {'beginner': 300, 'intermediate': 200, 'advanced': 120}


def worker(seed):
    """one process: problems found with this seed, as (level, key, user moves, region size, SGF)"""
    rng = random.Random(seed)
    out = []
    for _try in range(60):
        k = rng.choice((3, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9))
        got = attempt(rng, k)
        if not got:
            continue
        P, b, user, node, wrong = got
        d = first_line(node)
        level = next((name for name, lo, hi in LEVELS if lo <= d <= hi), None)
        if level:
            out.append((level, canonical(b, P.region) + str(user), d, len(P.region),
                        to_sgf(P, b, user, node, wrong, rng.randrange(4), '')))
    return out


def main():
    scale = float(sys.argv[1]) if len(sys.argv) > 1 else 1.0
    base_seed = int(sys.argv[2]) if len(sys.argv) > 2 else 19
    targets = {k: max(1, int(v * scale)) for k, v in TARGETS.items()}
    banks = {name: [] for name, _a, _b in LEVELS}
    seen = set()
    t0 = time.time()
    import multiprocessing as mp
    with mp.Pool(max(1, (os.cpu_count() or 2) - 1)) as pool:
        for found in pool.imap_unordered(worker, range(base_seed * 100000, base_seed * 100000 + 100000)):
            for level, key, d, size, sgf in found:
                if key in seen or len(banks[level]) >= targets[level]:
                    continue
                seen.add(key)
                banks[level].append((d, size, sgf))
            print(' '.join(f'{n}={len(v)}/{targets[n]}' for n, v in banks.items()), f'{time.time() - t0:.0f}s', flush=True)
            if all(len(banks[n]) >= targets[n] for n in banks):
                pool.terminate()
                break
    os.makedirs(os.path.join(HERE, 'data'), exist_ok=True)
    for name, items in banks.items():
        items.sort(key=lambda t: (t[0], t[1], t[2]))            # easier first: shorter, smaller
        with open(os.path.join(HERE, 'data', name + '.txt'), 'w', encoding='utf-8', newline='\n') as f:
            for n, (_d, _r, sgf) in enumerate(items, 1):
                f.write(sgf.replace('GN[]', 'GN[' + name.capitalize() + ' ' + str(n) + ']') + '\n')
        print(name, len(items))


if __name__ == '__main__':
    main()
