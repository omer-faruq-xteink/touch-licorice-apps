"""A small Go board for life-and-death problems in one corner, and a solver that reads them out.

The problem sits in a corner of an N x N window (N = 9 by default, the corner at row 0, column 0).
The defender's group and its eye space form the *region*; the attacker's surrounding wall stands
outside it and cannot be captured (the usual tsumego convention: the outside is strong). Both
sides play only inside the region, and may pass.

solve() answers whether the attacker can capture the target stone (a stone of the defender's main
group) with best play. The defender wins by making the group unconditionally alive (Benson's
algorithm), by a seki (both pass, the group still on the board), or when the attacker runs out of
moves. Simple ko is forbidden; the generator throws away problems whose lines contain a ko.
A position that comes back on the line being read (a throw-in captured, then played again) counts
as a failure for the attacker: it made no progress.
"""
EMPTY, ATT, DEF = 0, 1, 2


class Board:
    def __init__(self, n=9):
        self.n = n
        self.size = n * n
        self.nb = []
        for i in range(self.size):
            r, c = divmod(i, n)
            out = []
            if r > 0: out.append(i - n)
            if r < n - 1: out.append(i + n)
            if c > 0: out.append(i - 1)
            if c < n - 1: out.append(i + 1)
            self.nb.append(tuple(out))

    def chain(self, b, i):
        """stones of i's chain and its liberties"""
        col = b[i]
        stack, seen, libs = [i], {i}, set()
        while stack:
            j = stack.pop()
            for k in self.nb[j]:
                v = b[k]
                if v == col:
                    if k not in seen:
                        seen.add(k); stack.append(k)
                elif v == EMPTY:
                    libs.add(k)
        return seen, libs


class Problem:
    """a position: b (list of 0/1/2), wall (immortal attacker stones), region (playable points),
    target (a point of the defender's main group)"""

    def __init__(self, board, b, wall, region, target, max_ply=60, max_nodes=30000):
        self.B = board
        self.b = list(b)
        self.wall = frozenset(wall)
        self.region = tuple(sorted(region))
        self.target = target
        self.memo = {}
        self.path = set()
        self.max_ply, self.max_nodes = max_ply, max_nodes
        self.uncertain = False
        self.nodes = 0

    # -- rules
    def play(self, b, i, col, ko):
        """the board after col plays at i, and the new ko point; None when illegal"""
        if b[i] != EMPTY or i == ko:
            return None
        nb = list(b)
        nb[i] = col
        opp = ATT if col == DEF else DEF
        captured = []
        for k in self.B.nb[i]:
            if nb[k] == opp:
                stones, libs = self.B.chain(nb, k)
                if not libs and not (stones & self.wall):
                    for s in stones:
                        nb[s] = EMPTY
                    captured.extend(stones)
        stones, libs = self.B.chain(nb, i)
        if not libs:
            return None                               # suicide
        newko = None
        if len(captured) == 1 and len(stones) == 1 and len(libs) == 1:
            newko = captured[0]
        return nb, newko, len(captured)

    # -- Benson: is the target's chain unconditionally alive?
    def alive(self, b):
        B = self.B
        if b[self.target] != DEF:
            return False
        chains, cid = [], {}
        for i in range(B.size):
            if b[i] == DEF and i not in cid:
                stones, libs = B.chain(b, i)
                for s in stones:
                    cid[s] = len(chains)
                chains.append((stones, libs))
        regions, rid = [], {}
        for i in range(B.size):
            if b[i] != DEF and i not in rid:
                stack, pts = [i], {i}
                rid[i] = len(regions)
                while stack:
                    j = stack.pop()
                    for k in B.nb[j]:
                        if b[k] != DEF and k not in pts:
                            pts.add(k); rid[k] = len(regions); stack.append(k)
                regions.append(pts)
        # a region is vital to a chain when every empty point in it is a liberty of the chain;
        # only regions enclosed by defender stones (no wall, no window edge beyond the board edge) count
        reg_chains = []
        for pts in regions:
            around = set()
            enclosed = True
            for p in pts:
                if p in self.wall:
                    enclosed = False
                for k in B.nb[p]:
                    if b[k] == DEF:
                        around.add(cid[k])
            if len(pts) > 12:
                enclosed = False
            reg_chains.append((pts, around, enclosed))
        live = set(range(len(chains)))
        live_regions = set(r for r, (_p, _a, e) in enumerate(reg_chains) if e)
        while True:
            changed = False
            for c in list(live):
                stones, libs = chains[c]
                vital = 0
                for r in live_regions:
                    pts, around, _e = reg_chains[r]
                    if c in around and all((b[p] != EMPTY) or (p in libs) for p in pts):
                        vital += 1
                if vital < 2:
                    live.discard(c); changed = True
            for r in list(live_regions):
                if not reg_chains[r][1] <= live:
                    live_regions.discard(r); changed = True
            if not changed:
                break
        return cid[self.target] in live

    # -- search: True when the attacker captures the target with best play
    def moves(self, b, col):
        out = [i for i in self.region if b[i] == EMPTY]
        # points with more empty neighbours first (vital points, eye shapes)
        out.sort(key=lambda i: -sum(1 for k in self.B.nb[i] if b[k] == EMPTY))
        return out

    def solve(self, b, to_move, ko=None, passes=0, ply=0):
        if b[self.target] != DEF:
            return True
        if passes >= 2:
            return False
        key = (bytes(b), to_move, ko, passes)
        m = self.memo.get(key)
        if m is not None:
            return m
        if self.alive(b):
            self.memo[key] = False
            return False
        if key in self.path:
            return False                               # a repetition: no progress for the attacker
        if ply > self.max_ply or self.nodes > self.max_nodes:
            self.uncertain = True
            return False
        self.nodes += 1
        self.path.add(key)
        other = DEF if to_move == ATT else ATT
        if to_move == ATT:
            res = False
            for i in self.moves(b, ATT):
                r = self.play(b, i, ATT, ko)
                if r and self.solve(r[0], other, r[1], 0, ply + 1):
                    res = True
                    break
            if not res:
                res = self.solve(b, other, None, passes + 1, ply + 1)
        else:
            res = True
            for i in self.moves(b, DEF):
                r = self.play(b, i, DEF, ko)
                if r and not self.solve(r[0], other, r[1], 0, ply + 1):
                    res = False
                    break
            if res:
                res = self.solve(b, other, None, passes + 1, ply + 1)
        self.path.discard(key)
        self.memo[key] = res
        return res

    def children(self, b, col, ko):
        """(move, board, ko, captured) for every legal move; move None is a pass"""
        out = []
        for i in self.moves(b, col):
            r = self.play(b, i, col, ko)
            if r:
                out.append((i, r[0], r[1], r[2]))
        out.append((None, b, None, 0))
        return out
