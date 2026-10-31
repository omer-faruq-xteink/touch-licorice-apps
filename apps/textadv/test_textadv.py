"""Offline test of the Text adventures app (gamekit harness, a stand-in for the app's folder on the
card): the empty library, a game listed and opened, the status line, playing by the direction
buttons, by word chips and Send, by the keyboard, paging the transcript, the game's own save and
restore, continuing after the app is closed, the text size, the menu. Plays Zork I from games/:

  python -I apps/textadv/test_textadv.py [PATH/zork1.z3]

and runs the interpreter checks (CZECH, Praxix) when their files sit beside the story file
(czech/czech.z5, czech/czech.out5, praxix/praxix.z5; from the IF Archive's interpreter tools).
"""
import os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

ZORK = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'games', 'Zork I.z3')
ZDIR = os.path.dirname(os.path.abspath(ZORK))

# -- the interpreter against the test programs
czech = os.path.join(ZDIR, 'czech', 'czech.z5')
if os.path.exists(czech):
    out = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'zrun.py'), czech], capture_output=True).stdout.decode('utf-8', 'replace')
    want = open(os.path.join(ZDIR, 'czech', 'czech.out5'), encoding='utf-8', errors='replace').read()
    body = lambda t: [l for l in t.replace('\r', '').split('\n') if l.strip() and not l.startswith(('    ', '[quit]', 'Header'))]
    got, exp = body(out), body(want)
    assert got[:len(exp)] == exp, [(a, b) for a, b in zip(got, exp) if a != b][:3]
    print('CZECH: same output as the reference')
praxix = os.path.join(ZDIR, 'praxix', 'praxix.z5')
if os.path.exists(praxix):
    out = subprocess.run([sys.executable, '-I', os.path.join(HERE, 'zrun.py'), praxix, '-c', 'all'], capture_output=True).stdout.decode('utf-8', 'replace')
    assert 'All tests passed.' in out, out[-600:]
    print('Praxix: all tests passed')

g = Game(HERE)
g.L.execute('''
files = {}
ctx.files = {
  list = function(self) local t = {} for k, v in pairs(files) do t[#t + 1] = { name = k, size = #v } end return t end,
  read = function(self, n, off, len) local s = files[n]; if not s then return nil, 'not_found' end return s:sub((off or 0) + 1, (off or 0) + (len or 65536)) end,
}
timers = {}
ctx.after = function(self, ms, fn) timers[#timers + 1] = fn end
ctx.budget = { extend = function(self) return true end }
function run_timers() for _ = 1, 50 do local t = timers; timers = {}; if #t == 0 then return end; for _, f in ipairs(t) do f() end end end
''')
g.restart()
A = lambda: g.api


def text():
    return ' '.join(g.texts())


def screen_lines():
    return [str(x) for x in g.texts()]


def last_reply():
    ls = [str(A().lines()[i]) for i in range(1, len(A().lines()) + 1)]
    return '\n'.join(ls[-12:])


def press(label):
    for name, row in (('DIRS', 0), ('ACTS', 1)):
        bs = A().row_buttons(getattr(A(), name), row)
        for i in range(1, len(bs) + 1):
            if str(bs[i].label) == label:
                g.tap(int(bs[i].x) + 5, int(bs[i].y) + 5); g.L.execute('run_timers()'); return
    bs = A().bottom_buttons()
    for i in range(1, len(bs) + 1):
        if str(bs[i].label) == label:
            g.tap(int(bs[i].x) + 5, int(bs[i].y) + 5); g.L.execute('run_timers()'); return
    raise AssertionError(label)


def chip(word):
    for _ in range(6):
        rects, pages = A().chip_rows()
        for i in range(1, len(rects) + 1):
            if str(rects[i].word) == word:
                g.tap(int(rects[i].x) + 5, int(rects[i].y) + 5); return
        g.tap(480 - 40, 556 + 2 * 48 + 10)          # next page of chips
    raise AssertionError(('chip', word, [str(A().chips()[i]) for i in range(1, len(A().chips()) + 1)]))


# no package data (a stand-in without it) and no games: where to get them
t = text()
assert 'Text adventures' in t and '0 games' in t and 'More games:' in t, t

# Zork I built in (the package's data section)
DATA = os.path.join(HERE, 'data').replace(os.sep, '/') + '/'
g.L.execute(f'''
ctx.package = {{ open_text = function(self, name, opts)
  local f = io.open([[{DATA}]] .. name, 'rb')
  if not f then return nil end
  return {{ read_line = function(self) return f:read('l') end, close = function(self) f:close() end }}
end }}
''')
g.restart()
t = g.texts()
assert 'Zork I' in t and 'built in' in t, t

# a game copied in: listed beside it; the built-in one opened
g.g.files['Zork1.z3'] = open(ZORK, 'rb').read()
g.restart()
assert 'Zork1' in g.texts() and 'Zork I' in g.texts(), g.texts()
g.tap(100, 96 + 10)
g.L.execute('run_timers()')
assert str(A().game().name) == 'Zork I' and A().game().builtin
assert str(A().screen()) == 'game' and str(A().state()) == 'input', (A().screen(), A().state())
t = text()
assert 'West of House' in t and 'Score: 0  Moves: 0' in t, t
assert 'mailbox' in last_reply()
g.no_err()
assert g.commands() < 1000, g.commands()

# a direction button plays at once
press('N')
assert 'North of House' in last_reply() and 'Moves: 1' in text(), last_reply()
press('S')                                      # (south of the house: back around)
press('W') if 'West of House' not in last_reply() else None

# word chips build a command; Send plays it
A().send('west') if 'West of House' not in last_reply() else None
g.L.execute('run_timers()')
assert 'West of House' in last_reply(), last_reply()
chip('open'); chip('mailbox')
assert str(A().cmd()) == 'open mailbox', A().cmd()
press('Send')
assert 'leaflet' in last_reply(), last_reply()
assert str(A().cmd()) == ''

# Del and Clear
chip('take'); chip('leaflet'); press('Del')
assert str(A().cmd()) == 'take'
press('Clear')
assert str(A().cmd()) == ''

# the keyboard
press('Keys')
fn = g.g.inputs[len(g.g.inputs)]
fn(g.g.ctx, 'take leaflet')
g.L.execute('run_timers()')
assert 'Taken.' in last_reply(), last_reply()

# Inv and Look
press('Inv')
assert 'leaflet' in last_reply()
press('Look')
assert 'West of House' in last_reply()

# the game's own save and restore
A().send('save'); g.L.execute('run_timers()')
assert 'Ok.' in last_reply(), last_reply()
assert any(str(k).startswith('s_') for k in g.store.keys())
A().send('drop leaflet'); g.L.execute('run_timers()')
A().send('restore'); g.L.execute('run_timers()')
assert 'Ok.' in last_reply(), last_reply()
press('Inv')
assert 'leaflet' in last_reply(), last_reply()

# paging the transcript: the side buttons
for c in ('north', 'east', 'open window', 'enter', 'west', 'look'):
    A().send(c); g.L.execute('run_timers()')
top = int(A().top())
g.key('up')
assert int(A().top()) < top
g.key('down'); g.key('down')

# closed and opened again: the game continues where it was
moves = [s for s in screen_lines() if 'Moves:' in s]
g.restart()
g.L.execute('run_timers()')
assert str(A().screen()) == 'game', A().screen()
t = text()
assert '[Continued]' in t or 'Living Room' in t, t
VERBS = {'take', 'drop', 'examine', 'open', 'close', 'read', 'put', 'in', 'on', 'with', 'turn', 'push', 'pull',
         'give', 'attack', 'eat', 'drink', 'wear', 'unlock', 'light', 'climb', 'enter', 'all'}
chips_now = [str(A().chips()[i]) for i in range(1, len(A().chips()) + 1)]
assert [c for c in chips_now if c not in VERBS], chips_now          # the game's words, from the transcript kept
press('Inv')
assert 'leaflet' in last_reply(), last_reply()
assert any(str(A().lines()[i]) == '>inventory' for i in range(1, len(A().lines()) + 1))   # the prompt kept
# a short reply keeps the words of the replies before it
A().send('put'); g.L.execute('run_timers()')
assert 'What do you want to put?' in last_reply(), last_reply()
chips_now = [str(A().chips()[i]) for i in range(1, len(A().chips()) + 1)]
assert 'leaflet' in chips_now, chips_now
A().send('leaflet'); g.L.execute('run_timers()')
assert 'Living Room' in text()

# the menu: text size, back to the games
press('Menu')
assert 'Text size' in g.texts() and 'Games' in g.texts()
g.tap_label('Text size')
assert g.store['size.txt'] == 'small'
press('Menu'); g.tap_label('Games')
assert str(A().screen()) == 'library'
assert any('in progress' in s for s in screen_lines()), screen_lines()
g.no_err()
print('textadv: library, Zork I by buttons, chips, keyboard, save/restore, continue, menu OK')
print('textadv tests passed')
