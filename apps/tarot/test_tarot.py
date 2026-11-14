"""Offline test of Tarot (gamekit harness; stand-ins for the package's data section, base64,
image decode, random bytes and the clock): the 78 cards and their order, seeking to any card's
picture line, the picture cache, today's card (drawn once, kept across a restart, a new one the
next day, the journal), the three-card reading, the deck with both meanings for every card, side
buttons, the reversed switch, and the draw-command count.

  python -I apps/tarot/test_tarot.py
"""
import datetime, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

DATA = os.path.join(HERE, 'data').replace(os.sep, '/') + '/'
DAY0 = (datetime.date(2026, 11, 1) - datetime.date(1970, 1, 1)).days
cards = [l.split('|') for l in open(os.path.join(HERE, 'data', 'cards.txt'), encoding='ascii').read().split('\n')[:-1]]
def art(size):
    out = []
    for k in (1, 2):
        out += [l.rstrip(' ') for l in open(os.path.join(HERE, 'data', f'art_{size}{k}.txt'), encoding='ascii').read().split('\n')[:-1]]
    assert len(out) == 78
    return out


art_l, art_s = art('l'), art('s')

g = Game(HERE)
g.L.execute(f'''
ctx.package = {{ open_text = function(self, name, opts)
  local f = io.open([[{DATA}]] .. name, 'rb')
  if not f then return nil end
  return {{ read_line = function(self) return f:read('l') end, seek = function(self, p) f:seek('set', p); return true end,
            close = function(self) f:close() end }}
end }}
ctx.capabilities = {{ image_decode = true, image_transform = true }}
decoded, released = 0, 0
ctx.base64 = {{ decode = function(self, s) return 'png' .. #s end }}
ctx.image = {{ decode = function(self, bytes, opts)
  decoded = decoded + 1
  return {{ width = opts.max_w, height = opts.max_h, src = bytes, release = function(self) released = released + 1 end }}
end }}
rnd_state = 12345
ctx.random = {{ bytes = function(self, n)
  local t = {{}}
  for k = 1, n do rnd_state = (rnd_state * 1103515245 + 12345) % 2147483648; t[k] = string.char(rnd_state // 65536 % 256) end
  return table.concat(t)
end }}
now_day = {DAY0}
ctx.clock = {{ millis = function(self) return fake_ms end,
  now = function(self) local e = now_day * 86400 + 7 * 3600; return {{ epoch_sec = e, hour = 9, minute = 0, second = 0 }} end }}
''')
g.restart()
A = lambda: g.api

# the cards: 78, majors then the four suits, Ace to King
cs = A().cards()
assert len(cs) == 78 and [str(cs[k + 1].key) for k in range(78)] == [c[0] for c in cards]
assert str(cs[1].name) == 'The Fool' and str(cs[78].name) == 'King of Pentacles'

# a picture line is a seek away, for any card and either file
for n in (1, 2, 39, 40, 41, 77, 78):
    assert str(A().art_line('l', n)) == art_l[n - 1], n
for n in (78, 1, 40, 33):
    assert str(A().art_line('s', n)) == art_s[n - 1], n
print('pictures: seeking works in both files')

# at most four decoded pictures; the oldest is released
for n in range(1, 8):
    A().picture('s', n)
assert int(A().cache_size()) == 4 and int(g.g.released) == 3, (A().cache_size(), g.g.released)
img = A().picture('s', 7)
assert int(img.width) == 144 and str(img.src) == 'png' + str(len(art_s[6]))
g.no_err()

# the store build: packaged images come first, with no decoding
g.L.execute("ctx.package.image = function(self, key) return { width = 1, height = 1, key = key, release = function() end } end")
before = int(g.g.decoded)
img = A().picture('l', 23)
assert str(img.key) == 'l_w01' and int(g.g.decoded) == before
g.L.execute("ctx.package.image = nil")

# today: face down until tapped, then kept for the day and across a restart
t = g.texts()
assert any("Tap the card to draw today's card" in x for x in t), t
cx, cy, cw, ch = (int(v) for v in A().CARD.values())
g.tap(cx + cw // 2, cy + ch // 2)
j = A().journal()[DAY0]
first = (int(j.n), bool(j.rev))
name = cards[first[0] - 1][1]
t = g.texts()
assert any(name in x for x in t), (name, t)
g.no_err()
g.tap(cx + cw // 2, cy + ch // 2)              # the drawn card opens as a page; Back returns
assert A().detail() is not None
g.tap_label('< Back')
assert A().detail() is None
g.restart()
j = A().journal()[DAY0]
assert (int(j.n), bool(j.rev)) == first
g.L.execute('now_day = now_day + 1')
g.restart()
assert int(A().today()) == DAY0 + 1 and A().journal()[DAY0 + 1] is None
g.tap(cx + cw // 2, cy + ch // 2)
assert A().journal()[DAY0 + 1] is not None
# the journal lists yesterday's card and opens it
g.tap_label('Journal: earlier days')
assert A().tab() == 'journal'
t = g.texts()
assert any(name in x for x in t), t
g.tap(100, 90)
d = A().detail()
assert int(d.n) == first[0] and str(d.label).startswith('Sun 1 Nov'), (d.n, d.label)
g.key('back')
g.key('back')
assert A().tab() == 'today' and A().detail() is None
print('today: drawn once a day, kept, journal')

# three cards: three different cards; a tap opens one with its position
g.tap_label('Reading')
assert A().tab() == 'three'
g.tap_label('New reading')
r = A().reading()
ns = [int(r[k].n) for k in (1, 2, 3)]
assert len(set(ns)) == 3, ns
sx, sy, sw, sh = A().SM[1], int(A().SM[2]), int(A().SM[3]), int(A().SM[4])
g.tap(int(sx[2]) + sw // 2, sy + sh // 2)
d = A().detail()
assert int(d.n) == ns[1] and str(d.label) == 'Obstacle'
g.no_err()
assert g.commands() < 1024, g.commands()
g.tap_label('< Back')
g.restart()
r = A().reading()
assert [int(r[k].n) for k in (1, 2, 3)] == ns
g.tap_label('Reading')
seen = set()
for _ in range(40):
    g.tap_label('New reading')
    r = A().reading()
    seen |= {bool(r[k].rev) for k in (1, 2, 3)}
assert seen == {True, False}
print('three cards: drawn, kept, opened')

# the deck: every suit, every card with both meanings in full
g.tap_label('Deck')
for k, (key, label, count) in enumerate((('m', 'Major', 22), ('w', 'Wands', 14), ('c', 'Cups', 14), ('s', 'Swords', 14), ('p', 'Pentacles', 14))):
    x, y, w, h = (int(v) for v in A().suit_rect(k + 1))
    g.tap(x + w // 2, y + h // 2)
    t = g.texts()
    assert sum(1 for c in cards if c[0][0] == key and c[1].replace('The ', '', 1) in t) == count, (key, t)
    assert g.commands() < 1024
x, y, w, h = (int(v) for v in A().suit_rect(1))
g.tap(x + w // 2, y + h // 2)
x, y, w, h = (int(v) for v in A().list_rect(1))
g.tap(x + w // 2, y + h // 2)
assert int(A().detail().n) == 1
for n in range(1, 79):
    assert int(A().detail().n) == n
    body = ' '.join(g.texts())
    c = cards[n - 1]
    for part in (c[3], c[5]):
        last = part.split()[-1]
        assert last in body, (c[1], 'cut off', last)
    assert g.commands() < 1024
    g.key('right')
assert int(A().detail().n) == 1
g.key('left')
assert int(A().detail().n) == 78
g.key('back')
g.no_err()
print('deck: 78 cards, both meanings fit')

# reversed off: every new draw upright
g.tap_label('Reversed: on')
assert not A().reversals()
g.tap_label('Reading')
for _ in range(20):
    g.tap_label('New reading')
    r = A().reading()
    assert not any(bool(r[k].rev) for k in (1, 2, 3))
g.restart()
assert not A().reversals()

# the side buttons step through the tabs
assert A().tab() == 'today'
g.key('right')
assert A().tab() == 'three'
g.key('left')
g.key('left')
assert A().tab() == 'deck'

# Back acts on its release (only the up event's answer counts): it leaves the journal; on a tab it is
# left to the host, which offers to exit
back = lambda phase: g.L.eval(f"on_input(ctx, {{type='key', key='back', phase='{phase}'}})")
assert back('down') is True and back('up') is False and A().tab() == 'deck'
g.key('right')
g.tap_label('Journal: earlier days')
assert A().tab() == 'journal'
assert back('down') is True and A().tab() == 'journal'
assert back('up') is True and A().tab() == 'today'
assert back('down') is True and back('up') is False and A().tab() == 'today'
g.no_err()
print('all good')
