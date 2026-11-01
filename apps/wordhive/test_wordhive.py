"""Offline test of Word Hive (gamekit harness; a stand-in for the package's data section and the
clock): every puzzle line well formed, the day's puzzle, words made by tapping the hive, the
messages for a short word, a word without the middle letter, an unknown word and a repeat,
score and rank, a pangram, Shuffle, Delete, Hints, Yesterday, Found words, earlier days, progress
kept across a restart, and the draw-command count of every screen.

  python -I apps/wordhive/test_wordhive.py
"""
import datetime, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

PUZ = os.path.join(HERE, 'data', 'puzzles.txt')
lines = open(PUZ, encoding='ascii').read().split('\n')[:-1]
for l in lines:
    letters, *ans = l.split(' ')
    assert len(letters) == 7 and len(set(letters)) == 7 and 's' not in letters, l
    assert 20 <= len(ans) <= 50 and ans == sorted(ans) and len(set(ans)) == len(ans), l[:40]
    assert all(len(w) >= 4 and letters[0] in w and set(w) <= set(letters) for w in ans), l[:40]
    assert any(set(w) == set(letters) for w in ans), l[:40]
print(f'{len(lines)} puzzles well formed')

DATA = os.path.join(HERE, 'data').replace(os.sep, '/') + '/'
DAY0 = (datetime.date(2026, 11, 1) - datetime.date(1970, 1, 1)).days
g = Game(HERE)
STUB = f'''
ctx.package = {{ open_text = function(self, name, opts)
  local f = io.open([[{DATA}]] .. name, 'rb')
  if not f then return nil end
  return {{ read_line = function(self) return f:read('l') end, close = function(self) f:close() end }}
end }}
now_day = {DAY0 + 2}
ctx.clock = {{ millis = function(self) return fake_ms end,
  now = function(self) local e = now_day * 86400 + 7 * 3600; return {{ epoch_sec = e, hour = 9, minute = 0, second = 0 }} end }}
'''
g.L.execute(STUB)
g.restart()
A = lambda: g.api

assert int(A().START) == DAY0, (A().START, DAY0)
for d in (DAY0, DAY0 + 59, DAY0 + 400, 0, 19000):
    y, m, dd = A().civil(d)
    assert datetime.date(1970, 1, 1) + datetime.timedelta(days=d) == datetime.date(y, m, dd)
    assert int(A().days_from_civil(y, m, dd)) == d
assert str(A().date_label(DAY0)) == 'Sun 1 Nov', A().date_label(DAY0)

p = A().puz()
assert int(p.no) == 3 and int(A().count()) == len(lines), (p.no, A().count())
letters, *answers = lines[2].split(' ')
assert str(p.centre) == letters[0]
assert sorted(str(p.outer[k]) for k in range(1, 7)) == sorted(letters[1:])
g.no_err()


def tap_letter(ch):
    for i in range(1, 8):
        if str(A().letter_at(i)) == ch:
            c = A().centres[i]
            g.tap(int(c[1]), int(c[2]) + 10)
            return
    raise AssertionError(ch)


def enter(word):
    for ch in word:
        tap_letter(ch)
    assert str(A().word()) == word, (A().word(), word)
    g.tap_label('Enter')
    return str(A().msg())


centre = letters[0]
outer = [l for l in letters[1:]]
assert enter(outer[0] * 2 + centre) == 'Too short'
assert enter(outer[0] * 4).startswith('Must use the middle letter')
assert enter(centre * 5) == 'Not in the word list'
four = next(w for w in answers if len(w) == 4)
longer = next(w for w in answers if len(w) == 6 and len(set(w)) < 7)
pangram = next(w for w in answers if len(set(w)) == 7)
assert enter(four) == 'Good! +1'
assert enter(four) == 'Already found'
assert enter(longer).startswith('Nice! +6')
m = enter(pangram)
assert m.startswith(f'Pangram! +{len(pangram) + 7}'), m
assert int(A().score()) == 1 + 6 + len(pangram) + 7
assert [str(w) for w in A().found().values()] == [four, longer, pangram]
t = ' '.join(g.texts())
assert 'Found 3 of %d' % len(answers) in t and pangram in t, t

# Delete and Shuffle
tap_letter(centre); tap_letter(outer[1])
g.tap_label('Delete')
assert str(A().word()) == centre
before = sorted(str(A().puz().outer[k]) for k in range(1, 7))
g.tap_label('Shuffle')
assert sorted(str(A().puz().outer[k]) for k in range(1, 7)) == before
g.tap_label('Delete')
assert str(A().word()) == ''

# Hints: words still to find
g.tap_label('Hints')
t = g.texts()
assert any(x.startswith(f'Still to find: {len(answers) - 3} words') for x in t), t
assert g.commands() < 1024
g.tap_label('Back')
assert str(A().view()) == 'play'

# Yesterday's answers: all missed
g.tap_label('Yesterday')
t = g.texts()
y_ans = lines[1].split(' ')[1:]
assert 'You found 0' in t and f'Missed {len(y_ans)}' in t, t
assert g.commands() < 1024
g.tap_label('Back')

# Found words list
g.tap(20, 680)
assert str(A().view()) == 'list' and 'Found 3 of %d' % len(answers) in g.texts()
g.tap_label('Back')

# Menu: Earlier, then the found word of that day is kept apart, Today again
g.tap_label('Menu')
g.tap_label('Earlier')
assert int(A().pday()) == DAY0 + 1 and int(A().puz().no) == 2
assert len(A().found()) == 0
y_four = next(w for w in y_ans if len(w) == 4)
c0 = lines[1][0]
assert enter(y_four) == 'Good! +1', y_four
g.tap_label('Menu')
g.tap_label('Today')
assert int(A().pday()) == DAY0 + 2 and len(A().found()) == 3
g.tap_label('Yesterday')
assert 'You found 1' in g.texts()
g.tap_label('Back')

# progress kept across a restart; a new day opens a new puzzle
g.restart()
assert len(A().found()) == 3 and int(A().score()) == 1 + 6 + len(pangram) + 7
g.L.execute('now_day = now_day + 1')
g.restart()
assert int(A().puz().no) == 4 and len(A().found()) == 0
# past the last puzzle the list starts over
g.L.execute(f'now_day = {DAY0 + len(lines)}')
g.restart()
assert int(A().puz().no) == 1
assert g.commands() < 1024, g.commands()
g.no_err()

# every word of one puzzle: the last rank
g.L.execute(f'now_day = {DAY0 + 5}')
g.restart()
for w in lines[5].split(' ')[1:]:
    enter(w)
assert str(A().msg()) == 'Every word found!' and str(A().rank()) == 'Queen bee', (A().msg(), A().rank())
print('Word Hive: all tests passed')
