"""Word Ladder puzzles from 12dicts -> data/:

  data/puzzles.txt   one puzzle a line: a shortest ladder from the start word to the target,
                     "cold cord card ward warm" (the app shows the first and the last word; the
                     words between are the answer Hint follows)
  data/words4.txt    every word the app accepts as a step, one a line (four letters)
  data/words5.txt    the same, five letters

Steps may be any word of 2of12inf (12dicts with inflections, so plurals and verb forms count). The
start and target are common words: in both 2of12 (no inflections) and 3of6game (the list for word
games) and in 3esl (the list for learners of English, so everyday words), not ending in S, used at
most twice each. Each puzzle's shortest ladder is 4 to 6 steps,
and the stored one takes common words where it can. Every third puzzle has five letters. The order
is fixed by a seed: the app plays line N on day N (counted from 1 November 2026) and starts over
after the last one. The word filter is Word Hive's (apps/wordhive/make_puzzles.py).

Get 12dicts-6.0.2.zip from http://wordlist.aspell.net/12dicts/ and put American/2of12inf.txt,
American/2of12.txt, American/3esl.txt and International/3of6game.txt in one folder, then

  python -I apps/wordladder/make_puzzles.py FOLDER
"""
import collections, importlib.util, os, random, sys

HERE = os.path.dirname(os.path.abspath(__file__))
N_PUZZLES = 730
STEPS = (4, 5, 6)

spec = importlib.util.spec_from_file_location('wordhive', os.path.join(HERE, '..', 'wordhive', 'make_puzzles.py'))
wordhive = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wordhive)


def load(path):
    out = set()
    for line in open(path, encoding='latin-1'):
        s = line.strip()
        if not s:
            continue
        w = s.split()[0].rstrip('%!~=+^&')
        if w.isalpha() and w.isascii() and w.islower() and w not in wordhive.BLOCK and not w.startswith(wordhive.BLOCK_ROOTS):
            out.add(w)
    return out


def graph(words):
    s = set(words)
    return {w: [w[:i] + c + w[i + 1:] for i in range(len(w)) for c in 'abcdefghijklmnopqrstuvwxyz'
                if c != w[i] and w[:i] + c + w[i + 1:] in s] for w in words}


def bfs(adj, a):
    dist, q = {a: 0}, collections.deque([a])
    while q:
        x = q.popleft()
        for y in adj[x]:
            if y not in dist:
                dist[y] = dist[x] + 1
                q.append(y)
    return dist


def ladder(adj, dist_to_b, a, common, rnd):
    """A shortest ladder from a to b (dist_to_b: distances to b), common words first."""
    path = [a]
    while dist_to_b[path[-1]]:
        nxt = [y for y in adj[path[-1]] if dist_to_b.get(y, -1) == dist_to_b[path[-1]] - 1]
        best = [y for y in nxt if y in common] or nxt
        path.append(rnd.choice(sorted(best)))
    return path


def main(folder):
    valid = load(os.path.join(folder, '2of12inf.txt'))
    common = (load(os.path.join(folder, '2of12.txt')) & load(os.path.join(folder, '3of6game.txt'))
              & load(os.path.join(folder, '3esl.txt')))
    rnd = random.Random(20261101)
    os.makedirs(os.path.join(HERE, 'data'), exist_ok=True)
    pools = {}
    for n in (4, 5):
        words = sorted(w for w in valid if len(w) == n)
        with open(os.path.join(HERE, 'data', f'words{n}.txt'), 'w', encoding='ascii', newline='\n') as f:
            f.write('\n'.join(words) + '\n')
        adj = graph(words)
        ends = sorted(w for w in words if w in common and not w.endswith('s') and adj[w])
        pools[n] = (adj, ends)
        print(f'data/words{n}.txt: {len(words)} words, {len(ends)} could start or end a ladder')
    used, seen_pairs, out = collections.Counter(), set(), []
    while len(out) < N_PUZZLES:
        n = 5 if len(out) % 3 == 2 else 4
        steps = STEPS[len(out) // 3 % len(STEPS)] if n == 5 else rnd.choice(STEPS)
        adj, ends = pools[n]
        b = rnd.choice(ends)
        if used[b] >= 2:
            continue
        dist = bfs(adj, b)
        cands = [a for a in ends if dist.get(a) == steps and used[a] < 2 and (min(a, b), max(a, b)) not in seen_pairs]
        if not cands:
            continue
        a = rnd.choice(cands)
        path = ladder(adj, dist, a, common, rnd)
        assert len(path) == steps + 1 and path[-1] == b
        used[a] += 1
        used[b] += 1
        seen_pairs.add((min(a, b), max(a, b)))
        out.append(' '.join(path))
    with open(os.path.join(HERE, 'data', 'puzzles.txt'), 'w', encoding='ascii', newline='\n') as f:
        f.write('\n'.join(out) + '\n')
    by = collections.Counter((len(l.split()[0]), len(l.split()) - 1) for l in out)
    print(f'data/puzzles.txt: {len(out)} puzzles, (letters, steps): {dict(sorted(by.items()))}')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    main(sys.argv[1])
