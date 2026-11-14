"""Offline test of Cryptogram (gamekit harness; a stand-in for the package's data section and the
clock): every quote fits the screen, the cipher (no letter in place, the same every time), the
day's quote, guessing by taps, a key moved from another letter, Erase, Check, Hint, solving,
earlier days, progress kept across a restart, and the draw-command count.

  python -I apps/cryptogram/test_cryptogram.py
"""
import datetime, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

lines = open(os.path.join(HERE, 'data', 'quotes.txt'), encoding='ascii').read().split('\n')[:-1]
DATA = os.path.join(HERE, 'data').replace(os.sep, '/') + '/'
DAY0 = (datetime.date(2026, 11, 1) - datetime.date(1970, 1, 1)).days
g = Game(HERE)
g.L.execute(f'''
ctx.package = {{ open_text = function(self, name, opts)
  local f = io.open([[{DATA}]] .. name, 'rb')
  if not f then return nil end
  return {{ read_line = function(self) return f:read('l') end, close = function(self) f:close() end }}
end }}
now_day = {DAY0 + 2}
ctx.clock = {{ millis = function(self) return fake_ms end,
  now = function(self) local e = now_day * 86400 + 7 * 3600; return {{ epoch_sec = e, hour = 9, minute = 0, second = 0 }} end }}
''')
g.restart()
A = lambda: g.api
assert int(A().count()) == len(lines)

# every quote fits above the status line
for k in range(len(lines)):
    A().open_day(DAY0 + k)
    p = A().puz()
    assert int(p.bottom) <= 572, (k, lines[k], p.bottom)
print(f'{len(lines)} quotes fit')

# the cipher: a derangement, the same for the same day
for d in (DAY0, DAY0 + 1, DAY0 + 77):
    enc, dec = A().make_cipher(d)
    m = {str(k): str(v) for k, v in enc.items()}
    assert sorted(m.values()) == [chr(65 + i) for i in range(26)] and all(k != v for k, v in m.items())
    enc2, _ = A().make_cipher(d)
    assert m == {str(k): str(v) for k, v in enc2.items()}

A().open_day(DAY0 + 2)
p = A().puz()
author, quote = lines[2].split('|')
assert str(p.quote) == quote.upper() and int(p.no) == 3
g.no_err()
assert g.commands() < 1024, g.commands()


def key(ch):
    x, y, w, h = (int(v) for v in A().key_rect(ord(ch) - 64))
    g.tap(x + w // 2, y + h // 2)


def tap_cell(i):
    c = A().cells()[i]
    g.tap(int(c.x) + 5, int(c.y) + 10)


def cells():
    return [(str(c.ch), None if c.c is None else str(c.c)) for c in A().cells().values()]


cs = cells()
first = next(i for i, (ch, c) in enumerate(cs, 1) if c)
plain, ciph = cs[first - 1]
assert int(A().cursor()) == first
t = g.texts()
assert any(x.startswith(f'{ciph} appears ') for x in t), t
# a wrong guess, then the same key on another letter moves it
wrong_p = next(ch for ch in 'ZQXJKVBP' if ch != plain)
key(wrong_p)
assert str(A().guess()[ciph]) == wrong_p
other = next(i for i, (ch, c) in enumerate(cs, 1) if c and c != ciph)
tap_cell(other)
other_c = cs[other - 1][1]
key(wrong_p)
assert A().guess()[ciph] is None and str(A().guess()[other_c]) == wrong_p
# Check strikes it out (unless it happens to be right)
g.tap_label('Check')
right = str(A().puz().plain[other_c]) == wrong_p
assert (A().wrong()[other_c] is None) == right
# Erase
tap_cell(other)
g.tap_label('Erase')
assert A().guess()[other_c] is None
# Hint on the selected letter
tap_cell(first)
g.tap_label('Hint')
assert str(A().guess()[ciph]) == plain and A().hinted()[ciph]
assert str(A().msg()) == f'{ciph} stands for {plain}'
key('A' if plain != 'A' else 'B')         # a hinted letter keeps its key
assert str(A().guess()[ciph]) == plain

# solve by taps: select each open letter and press its key
for _ in range(60):
    if A().solved():
        break
    cur = A().cursor()
    c = str(A().cells()[cur].c)
    key(str(A().puz().plain[c]))
assert A().solved() and str(A().msg()).startswith('Solved!'), A().msg()
g.no_err()

# kept across a restart; the next day is a new quote; an earlier day keeps its own guesses
g.restart()
assert A().solved()
g.tap_label('Menu')
g.tap_label('Earlier')
assert int(A().pday()) == DAY0 + 1 and not A().solved() and len(list(A().guess().keys())) == 0
key('E')
g.tap_label('Menu')
g.tap_label('Today')
assert A().solved()
g.L.execute('now_day = now_day + 1')
g.restart()
assert int(A().puz().no) == 4 and not A().solved()
g.L.execute(f'now_day = {DAY0 + 1}')
g.restart()
assert len(list(A().guess().keys())) == 1
# a proverb shows its author as text
k = next(i for i, l in enumerate(lines) if l.startswith('Proverb|'))
A().open_day(DAY0 + k)
assert '- Proverb' in g.texts()
# Back (down, then up: the host reads only the up event's answer): closes a box; on the board it is
# left to the host, which offers to exit
back = lambda phase: g.L.eval(f"on_input(ctx, {{type='key', key='back', phase='{phase}'}})")
g.tap_label('Menu')
assert 'Earlier' in g.recs()
assert back('down') is True and back('up') is True and 'Earlier' not in g.recs(), g.texts()
assert back('down') is True and back('up') is False
g.no_err()
print('Cryptogram: all tests passed')
