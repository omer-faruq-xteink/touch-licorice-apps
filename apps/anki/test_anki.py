"""Offline test of the Anki app (gamekit harness, with a stand-in for the package's data section,
a clock that can be moved on and storage list / remove): the deck list, a study session with the
built-in deck, ratings and their intervals, learning cards coming back, Undo, the daily new-card
limit, reviews after days, deleting and adding cards, converted decks and a plain .tsv list, long
cards that scroll; and apkg2cards.py on a word list, with --update keeping places.

  python -I apps/anki/test_anki.py
"""
import os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

DATA = os.path.join(HERE, 'data').replace(os.sep, '/') + '/'
EXTRA = r'''
ctx.storage.list = function(self) local t = {} for k in pairs(store) do t[#t + 1] = k end return t end
ctx.storage.remove = function(self, n) store[n] = nil end
fake_epoch = 1761480000 + 9 * 3600         -- a morning, UTC
ctx.clock.now = function(self)
  local d = fake_epoch % 86400
  return { epoch_sec = fake_epoch, hour = d // 3600, minute = (d % 3600) // 60, second = d % 60 }
end
ctx.package = { open_text = function(self, name, opts)
  local f = io.open(DATA .. name, 'rb')
  if not f then return nil end
  return { read_line = function(self) return f:read('l') end, close = function(self) f:close() end }
end }
'''
g = Game(HERE)
g.L.execute(f'DATA = [[{DATA}]]')
g.L.execute(EXTRA)
g.restart()
A = lambda: g.api
BW = (480 - 24 - 24) // 4


def rate(k):
    g.tap(12 + (k - 1) * (BW + 8) + BW // 2, 704 + 30)


def front():
    c = A().card()
    return str(c.f) if c else None


def queue_len():
    return len(list(A().queue().values()))


def advance_days(n):
    g.L.execute(f'fake_epoch = fake_epoch + {int(n * 86400)}')


def deck_row(name):
    r = g.recs()
    assert name in r, (name, list(r))
    return r[name]


# the deck list: the built-in English deck and My cards
t = g.texts()
assert 'Anki' in t and 'English words B2-C1' in t and 'My cards' in t, t
assert '1438 cards    due 0    new 15' in t, t
assert 'New/day 15' in t and 'Help' in t

# study the built-in deck: 15 new cards, the first word of the deck
g.tap(*deck_row('English words B2-C1'))
assert str(A().screen()) == 'study' and queue_len() == 15
assert 'English words B2-C1' in g.texts()
first = front()
assert first.startswith('contribution\n(noun)'), first
t = g.texts()
assert 'contribution' in t and '(noun)' in t and 'Show answer' in t and 'New 15    Review 0    Done 0' in t, t
g.tap(240, 300)                                   # tap the card: the answer
assert A().shown()
t = g.texts()
assert any('common endeavor' in s for s in t) and 'Again' in t and 'Easy' in t, t
assert '1m' in t and '6m' in t and '10m' in t and '14d' in t, t     # a new card's intervals (FSRS)

# Good: a learning step of 10 minutes, so the card comes back in this session (4th place)
rate(3)
assert front() != first and str(A().state().next) == '1' and int(A().state().new) == 1
assert 'en_p000.txt' in g.store and re.match(r'^0 \d+ 3\.71 5\.16 1 0 \d+ l\n$', g.store['en_p000.txt']), g.store['en_p000.txt']
assert 'next=1' in g.store['en_st.txt'] and 'new=1' in g.store['en_st.txt']
# Undo puts it back
g.tap(400, 30); g.tap_label('Undo')
assert front() == first and int(A().state().new) == 0 and 'en_p000.txt' not in g.store

# Easy on every card: out of the session; the daily limit then holds
seen = set()
for _ in range(40):
    if str(A().screen()) != 'study':
        break
    seen.add(front())
    g.tap(240, 300); rate(4)
assert str(A().screen()) == 'done' and len(seen) == 15 and 'Done for now!' in g.texts()
assert any(s.startswith('New cards come back') for s in g.texts()) and 'are due.' in ' '.join(g.texts())   # wrapped, not cut
g.tap(240, 730)                                   # Decks
assert '1438 cards    due 0    new 0' in g.texts(), g.texts()
g.tap(*deck_row('English words B2-C1'))
assert str(A().screen()) == 'done'

# fifteen days on: the 15 cards are due (Easy on a new card: 14 days) and 15 new ones come
g.tap(240, 730)
advance_days(15)
g.restart()
assert '1438 cards    due 15    new 15' in g.texts(), g.texts()
g.tap(*deck_row('English words B2-C1'))
assert queue_len() == 30 and 'New 15    Review 15    Done 0' in g.texts()
c0 = front()
assert c0 in seen                                 # reviews first
g.tap(240, 300)
t = g.texts()
assert '10m' in t and any(re.fullmatch(r'\d+d', s) for s in t), t   # Again: 10 minutes; others in days
rate(3)                                           # Good: 4 days * ease
assert front() != c0                              # due in days: not again today

# delete a card: it leaves the queue and the deck
before = queue_len()
d = front()
g.tap(400, 30); g.tap_label('Delete card'); g.tap_label('Delete')
assert queue_len() == before - 1 and front() != d and 'en_del.txt' in g.store

# add a card: front and back through the keyboard; it joins this session
g.tap(400, 30); g.tap_label('Add card')
g.L.eval('inputs[#inputs]')(g.L.globals().ctx, 'serendipity')
g.L.eval('inputs[#inputs]')(g.L.globals().ctx, 'finding good things by chance')
assert 'en_own.txt' in g.store and 'serendipity\tfinding good things by chance' in g.store['en_own.txt']
assert queue_len() == before

# a long card scrolls
g.L.execute(r'''store['en_own.txt'] = 'olong\tlong card\t' .. string.rep('line of text\\n', 60) .. '\n' ''')
g.tap(400, 30); g.tap_label('Decks')
g.tap(*deck_row('English words B2-C1'))
while front() != 'long card':
    g.tap(240, 300); rate(4)
g.tap(240, 300)
assert 'more: swipe up' in g.texts()
g.L.eval("function() on_input(ctx, {type='pointer', phase='up', gesture='swipe_up', x=240, y=400}) end")()
assert 'swipe down: top' in g.texts()

# My cards: empty, long press offers Add card
g.tap(400, 30); g.tap_label('Decks')
assert any('long-press: add a card' in s for s in g.texts())

# converted decks and a plain .tsv list in storage
tmp = tempfile.mkdtemp()
try:
    words = os.path.join(tmp, 'words.tsv')
    open(words, 'w', encoding='utf-8').write('# my list\nalpha\tfirst letter\nbeta\tsecond letter\ngamma\tthird letter\n')
    conv = os.path.join(HERE, 'apkg2cards.py')
    out = os.path.join(tmp, 'out')
    subprocess.run([sys.executable, '-I', conv, words, out, '--name', 'Greek letters', '--prefix', 'greek'], check=True, capture_output=True)
    lines = open(os.path.join(out, 'greek_c000.txt'), encoding='utf-8').read().split('\n')
    assert lines[0].startswith('L2\talpha\t') and lines[2].startswith('L4\tgamma\t'), lines
    # --update: a changed text keeps its place, a removed card leaves a blank place, a new one goes last
    open(words, 'w', encoding='utf-8').write('# my list\nalpha\tthe first letter\nGAMMA\tthird\ngamma\tthird letter\ndelta\tfourth\n')
    r = subprocess.run([sys.executable, '-I', conv, words, out, '--name', 'Greek letters', '--prefix', 'greek', '--update'],
                       check=True, capture_output=True, text=True)
    lines = open(os.path.join(out, 'greek_c000.txt'), encoding='utf-8').read().split('\n')
    assert lines[0] == 'L2\talpha\tthe first letter', lines
    assert lines[1] == 'L3\tGAMMA\tthird' and lines[2] == 'L4\tgamma\tthird letter' and lines[3] == 'L5\tdelta\tfourth', lines
    for fn in os.listdir(out):
        g.store[fn] = open(os.path.join(out, fn), encoding='utf-8').read()
    g.store['vocab.tsv'] = 'cat\tkedi\ndog\tköpek\n'
finally:
    shutil.rmtree(tmp)
g.restart()
t = g.texts()
assert 'Greek letters' in t and 'vocab' in t, t
assert '4 cards    due 0    new 4' in t and '2 cards    due 0    new 2' in t, t
g.tap(*deck_row('Greek letters'))
assert front() == 'alpha' and queue_len() == 4
assert 'Greek letters' in g.texts()                                            # a short name stays whole
g.tap(240, 300)
assert 'the first letter' in g.texts()
g.tap(400, 30); g.tap_label('Decks')
g.tap(*deck_row('vocab'))
assert front() == 'cat'
g.tap(240, 300); rate(4)
assert front() == 'dog' and 'tvocab_p000.txt' in g.store

# the scheduler: FSRS 4.5 with its default parameters, against a separate Python version
import math
FW = [0.4872, 1.4003, 3.7145, 13.8206, 5.1618, 1.2298, 0.8975, 0.031, 1.6474, 0.1367, 1.0461,
      2.1072, 0.0793, 0.3246, 1.587, 0.2272, 2.8755]
clamp = lambda x: max(1, min(10, x))
nd = lambda d, g: clamp(FW[7] * FW[4] + (1 - FW[7]) * (d - FW[6] * (g - 3)))
ivl = lambda s: max(1, min(1000, math.floor(s / (19 / 81) * (0.9 ** (1 / -0.5) - 1) + 0.5)))
R = lambda t, s: (1 + 19 / 81 * t / s) ** -0.5


def py_review(s, d, t, g):
    r = R(t, s)
    if g == 1:
        return min(s, FW[11] * d ** -FW[12] * ((s + 1) ** FW[13] - 1) * math.exp(FW[14] * (1 - r))), nd(d, 1)
    k = (FW[15] if g == 2 else 1) * (FW[16] if g == 4 else 1)
    return s * (1 + math.exp(FW[8]) * (11 - d) * s ** -FW[9] * (math.exp(FW[10] * (1 - r)) - 1) * k), nd(d, g)


s = A().schedule
r = s(g.L.table_from({}), 3, 0)
assert r.due == 600 and r.state == 'l' and abs(r.s - FW[2]) < 1e-9 and abs(r.d - FW[4]) < 1e-9
r2 = s(r, 3, 600)                                   # Good in the steps: graduates, S days
assert r2.state == 'r' and r2.due == 600 + ivl(FW[2]) * 86400 == 600 + 4 * 86400
ps, pd, now = r2.s, r2.d, r2.due
for g_ in (3, 2, 3, 4, 1, 3):                       # reviews on their due day (Again: a lapse)
    want_s, want_d = py_review(ps, pd, (now - r2.last) / 86400, g_)
    r2 = s(r2, g_, now)
    assert abs(r2.s - want_s) < 1e-6 and abs(r2.d - want_d) < 1e-9, (g_, r2.s, want_s)
    if g_ == 1:
        assert r2.state == 'l' and r2.due == now + 600 and r2.lapses == 1
        r2 = s(r2, 3, now + 600)                    # relearned
        assert r2.state == 'r'
    else:
        assert r2.due == now + ivl(want_s) * 86400, (g_, r2.due - now)
    ps, pd, now = r2.s, r2.d, r2.due
assert s(g.L.table_from({}), 4, 0).due == 14 * 86400 and s(g.L.table_from({}), 1, 0).due == 60
big = s(g.L.table_from({'s': 5000, 'd': 1, 'state': 'r', 'last': 0, 'reps': 9, 'lapses': 0}), 4, 0)
assert big.due == 1000 * 86400                      # at most 1000 days (32-bit numbers)

# progress saved by the SM-2 scheduler (v0.10 and before) is read as FSRS
g.store['en_p001.txt'] = '3 1761800000 6 2.5 3 0\n5 1761000000 0 1.3 1 1\n'
p1 = A().prog('en', 1)
assert p1[3].state == 'r' and p1[3].s == 6 and abs(p1[3].d - 5.2) < 1e-9 and p1[3].last == 1761800000 - 6 * 86400
assert p1[5].state == 'l' and p1[5].s == 1 and p1[5].d == 10
assert str(A().span(90)) == '1m' and str(A().span(3 * 86400)) == '3d' and str(A().span(90 * 86400)) == '3mo'

# the lock screen: long-press a deck, Lock screen -> lock_cards.txt and the firmware's own question
g.L.execute("lock_calls = {}; ctx.lockscreen = { is_default = function(self) return lock_is end, "
            "set_default = function(self) lock_calls[#lock_calls + 1] = 'set'; lock_is = true end, "
            "clear_default = function(self) lock_calls[#lock_calls + 1] = 'clear'; lock_is = false end }")
hold = g.L.eval("function(x, y) on_input(ctx, {type='pointer', phase='down', x=x, y=y}); "
                "on_input(ctx, {type='pointer', phase='hold', gesture='long', x=x, y=y}); "
                "on_input(ctx, {type='pointer', phase='up', x=x, y=y}) end")
if str(A().screen()) != 'decks':
    g.tap(400, 30); g.tap_label('Decks')
hold(*deck_row('English words B2-C1'))
g.tap_label('Lock screen')
lc = g.store['lock_cards.txt'].split('\n')
assert lc[0] == 'English words B2-C1' and len([l for l in lc[1:] if l]) == 30, lc[:3]
assert all('\t' in l for l in lc[1:] if l) and list(g.L.eval('lock_calls').values()) == ['set']
assert 'lock_deck=en' in g.store['settings.txt'] and 'Lock screen: cards from English words B2-C1.' in g.texts()
hold(*deck_row('English words B2-C1'))
assert 'Lock screen off' in g.texts()
g.tap_label('Close')

# lockscreen.lua draws one of those cards, a different one each half hour
from lupa import lua54
from harness import STUBS
L2 = lua54.LuaRuntime(unpack_returned_tuples=True)
L2.execute(STUBS)
L2.globals().store['lock_cards.txt'] = g.store['lock_cards.txt']
L2.execute("fake_epoch = 1800 * 1000; ctx.clock.now = function(self) return { epoch_sec = fake_epoch } end")
L2.execute(open(os.path.join(HERE, 'lockscreen.lua'), encoding='utf-8').read())
draw = L2.eval("function() drawn = {}; on_draw(ctx, gg); local t = {} for _, d in ipairs(drawn) do t[#t + 1] = d.s end return t end")
t1 = list(draw().values())
assert 'card 11 of 30, a new one every 30 minutes' in t1 and any('English words' in x for x in t1), t1
L2.execute('fake_epoch = fake_epoch + 1800')
t2 = list(draw().values())
assert 'card 12 of 30, a new one every 30 minutes' in t2 and t2 != t1
assert not any('error' in x for x in t1 + t2)

# off again: clears the firmware's choice and the card list
hold(*deck_row('English words B2-C1'))
g.tap_label('Lock screen off')
assert 'lock_cards.txt' not in g.store and list(g.L.eval('lock_calls').values()) == ['set', 'clear']
g.no_err()
print('anki tests passed')
