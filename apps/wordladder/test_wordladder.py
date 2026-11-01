"""Offline test of Word Ladder (gamekit harness; stand-ins for the package's data section and the
clock): every stored ladder is a real ladder of listed words, the day's puzzle, playing a ladder by
taps, words that are not listed or already used, Undo, Hint on and off the stored ladder, a long
ladder on screen, progress kept across a restart, earlier days, and the draw-command count.

  python -I apps/wordladder/test_wordladder.py
"""
import collections, datetime, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

DATA = os.path.join(HERE, 'data')
lines = open(os.path.join(DATA, 'puzzles.txt'), encoding='ascii').read().split('\n')[:-1]
words = {n: set(open(os.path.join(DATA, f'words{n}.txt'), encoding='ascii').read().split()) for n in (4, 5)}

# every stored ladder: listed words, one letter apart, no repeats, 4 to 6 steps
for l in lines:
    p = l.split()
    n = len(p[0])
    assert n in (4, 5) and 4 <= len(p) - 1 <= 6 and len(set(p)) == len(p), l
    for a, b in zip(p, p[1:]):
        assert a in words[n] and b in words[n] and sum(x != y for x, y in zip(a, b)) == 1, (l, a, b)
print(f'{len(lines)} ladders check out')


def dist_to(target):
    n = len(target)
    adj = lambda w: [w[:i] + c + w[i + 1:] for i in range(n) for c in 'abcdefghijklmnopqrstuvwxyz'
                     if c != w[i] and w[:i] + c + w[i + 1:] in words[n]]
    d, q = {target: 0}, collections.deque([target])
    while q:
        x = q.popleft()
        for y in adj(x):
            if y not in d:
                d[y] = d[x] + 1
                q.append(y)
    return d


DAY0 = (datetime.date(2026, 11, 1) - datetime.date(1970, 1, 1)).days
g = Game(HERE)
g.L.execute(f'''
ctx.package = {{ open_text = function(self, name, opts)
  local f = io.open([[{DATA.replace(os.sep, '/')}/]] .. name, 'rb')
  if not f then return nil end
  return {{ read_line = function(self) return f:read('l') end, close = function(self) f:close() end }}
end }}
now_day = {DAY0 + 4}
ctx.clock = {{ millis = function(self) return fake_ms end,
  now = function(self) local e = now_day * 86400 + 7 * 3600; return {{ epoch_sec = e, hour = 9, minute = 0, second = 0 }} end }}
''')
g.restart()
A = lambda: g.api
assert int(A().count()) == len(lines)
p = A().puz()
path = lines[4].upper().split()
assert int(p.no) == 5 and str(p.start) == path[0] and str(p.target) == path[-1] and int(p.par) == len(path) - 1
g.no_err()
assert g.commands() < 1024, g.commands()


def key(ch):
    x, y, w, h = (int(v) for v in A().key_rect(ord(ch) - 64))
    g.tap(x + w // 2, y + h // 2)


def cell(i):
    x = int(A().cell_x(i))
    g.tap(x + 20, int(A().current_y()) + 20)


def step_to(w):
    cur = [str(s) for s in A().steps().values()] or [str(A().puz().start)]
    cur = cur[-1]
    i = next(k for k in range(len(w)) if w[k] != cur[k])
    cell(i + 1)
    key(w[i])


# play the stored ladder by taps
for w in path[1:]:
    step_to(w)
assert A().solved() and 'Solved in' in str(A().msg()), A().msg()
g.no_err()
print('a ladder played by taps')

# a word not in the list, a word already used, Undo
g.tap_label('Menu')
g.tap_label('Start over')
assert len(A().steps()) == 0 and not A().solved()
start = path[0]
bad = next(start[:i] + c + start[i + 1:] for i in range(len(start)) for c in 'QXZJVK'
           if (start[:i] + c + start[i + 1:]).lower() not in words[len(start)])
step_to(bad)
assert len(A().steps()) == 0 and 'not in the word list' in str(A().msg())
step_to(path[1])
step_to(path[0])
assert len(A().steps()) == 1 and 'already in the ladder' in str(A().msg())
g.tap_label('Undo')
assert len(A().steps()) == 0

# Hint on the stored ladder, then off it: always one step nearer
g.tap_label('Hint')
assert [str(s) for s in A().steps().values()] == [path[1]]
g.tap_label('Undo')
d = dist_to(path[-1].lower())
off = next(w for w in words[len(start)] if sum(x != y for x, y in zip(w, start.lower())) == 1
           and w.upper() not in path and w in d and d[w] >= d[start.lower()])
step_to(off.upper())
assert len(A().steps()) == 1
for _ in range(10):
    if A().solved():
        break
    before = str([*A().steps().values()][-1]).lower()
    g.tap_label('Hint')
    after = str([*A().steps().values()][-1]).lower()
    assert d[after] == d[before] - 1, (before, after)
assert A().solved()
g.no_err()
print('Hint follows a shortest ladder, on it and off it')

# a long ladder: the newest steps on screen, the rest counted
g.tap_label('Menu')
g.tap_label('Start over')
def walk(cur, used, n):
    """n more distinct words from cur, one letter apart, never the target (depth-first)."""
    if n == 0:
        return []
    for w in sorted(words[len(cur)]):
        if w not in used and w != path[-1].lower() and sum(x != y for x, y in zip(w, cur)) == 1:
            rest = walk(w, used | {w}, n - 1)
            if rest is not None:
                return [w] + rest
    return None


for w in walk(start.lower(), {start.lower()}, 12):
    step_to(w.upper())
assert len(A().steps()) == 12
t = g.texts()
assert any('more steps' in x for x in t), t
assert g.commands() < 1024, g.commands()
g.no_err()

# kept across a restart; earlier days keep their own ladder
g.restart()
assert len(A().steps()) == 12
g.tap_label('Menu')
g.tap_label('Earlier')
assert int(A().pday()) == DAY0 + 3 and len(A().steps()) == 0
assert str(A().puz().start) == lines[3].split()[0].upper()
g.tap_label('Menu')
g.tap_label('Today')
assert len(A().steps()) == 12

# every puzzle opens and draws
for k in range(0, len(lines), 37):
    A().open_day(DAY0 + k)
    assert g.commands() < 1024
    g.no_err()
print('all good')
