"""Offline test of Gamebook (gamekit harness): the story engine (expressions, text, choices,
redirects, the index read in small pieces and kept in storage, saving), the built-in story played
to each of its endings, Continue and Undo, user stories from the app's folder, pages.

  python -I apps/gamebook/test_gamebook.py
"""
import json, os, shutil, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

DATA = os.path.join(HERE, 'data').replace(os.sep, '/') + '/'
EXTRA = r'''
ctx.storage.list = function(self) local t = {} for k in pairs(store) do t[#t + 1] = k end return t end
ctx.storage.remove = function(self, n) store[n] = nil end
ctx.i18n = { locale = 'en_US' }
ctx.fonts.size = function(self, px, sample)
  return { measure = function(self, s) return (utf8.len(s) or #s) * (px // 2) end, line_height = px + 8 }
end
ctx.qr = { encode = function(self, text, o) qr_made = text; return { release = function() end } end }
ctx.package = { read = function(self, name)
  local f = io.open(DATA .. name, 'rb')
  if not f then return nil, 'not_found' end
  local s = f:read('a'); f:close(); return s
end }
user_files = {}
reads = 0
ctx.files = { path = '/AppFiles/gamebook',
  list = function(self) local t = {} for k, v in pairs(user_files) do t[#t + 1] = { name = k, size = #v } end return t end,
  size = function(self, n) if user_files[n] then return #user_files[n] end return nil, 'not_found' end,
  read = function(self, n, off, len)
    reads = reads + 1
    local s = user_files[n]; if not s then return nil, 'not_found' end
    return s:sub(off + 1, off + math.min(len or 65536, 65536))
  end,
  exists = function(self, n) return user_files[n] ~= nil end }
-- a source that hands back at most 7 bytes a read, to test the index across pieces
function tiny_source(s) return { size = #s, read = function(off, len) return s:sub(off + 1, off + math.min(len, 7)) end } end
function whole_source(s) return { size = #s, read = function(off, len) return s:sub(off + 1, off + len) end } end
'''
g = Game(HERE)
g.L.execute(f'DATA = [[{DATA}]]')
g.L.execute(EXTRA)
g.restart()
A = lambda: g.api
L = g.L


def lua_str(s):
    return '[==[' + s + ']==]'


def engine(text, tiny=True):
    src = ('tiny_source' if tiny else 'whole_source') + '(' + lua_str(text) + ')'
    L.execute(f'_story = assert(__TEST.api.S.index({src})); _st = __TEST.api.S.new_state(_story)')


def enter(name):
    L.execute(f'_view, _err = __TEST.api.S.enter(_story, _st, {lua_str(name)})')
    v = L.eval('_view')
    assert v is not None, L.eval('_err')
    return v


def lines(v):
    return [str(x) for x in v.lines.values()]


def labels(v):
    return [str(c.label) for c in v.choices.values()]


def choose(i):
    return str(L.eval(f'__TEST.api.S.choose(_story, _st, _view, {i})'))


def ev(expr):
    return L.eval(f'__TEST.api.S.eval(_story, _st, {lua_str(expr)})')


def var(n):
    return L.eval(f'_st.vars[ {lua_str(n)} ]')


# ------------------------------------------------------------------ the engine

engine('''title: T
var: a = 5
var: name = "Ann"
var: flag = false

== one
Hello {name}, a is {a}.
{a > 3: big|small} and {flag: on|off}.
{a > 3: outer {a > 4: inner yes|inner no}|outer no}
Braces \\{kept\\} and a bar \\| too.
\\* a starred line
{first|second|third}
{&odd|even}
// a comment

~ a += 1
* Go two -> two
* {a > 100} Hidden -> two
* [once] Once only -> one
* Set ~ flag = true; a = a * 2 -> two

== two
-> {flag} three
-> one

== three
Three, a={a}.
''')
assert ev('1 + 2 * 3') == 7 and ev('(1 + 2) * 3') == 9 and ev('7 / 2') == 3 and ev('-7 / 2') == -3
assert ev('7 % 3') == 1 and ev('5 / 0') == 0 and ev('not 0') is True and ev('!true') is False
assert ev('1 < 2 and 2 < 3') is True and ev('1 > 2 or 0') is False and ev('a == 5') is True
assert ev('name == "Ann"') is True and ev('"x" + 1') == 'x1' and ev('min(3, 9) + max(3, 9)') == 12
assert ev('one') == 0 and ev('nothing') == 0 and ev('flag == false') is True and ev('a >= 5 && a <= 5') is True
for _ in range(20):
    assert 1 <= ev('random(1, 6)') <= 6
v = enter('one')
assert lines(v) == ['Hello Ann, a is 6.', 'big and off.', 'outer inner yes', 'Braces {kept} and a bar | too.',
                    '* a starred line', 'first', 'odd'], lines(v)
assert labels(v) == ['Go two', 'Once only', 'Set'], labels(v)
assert ev('one') == 1
assert choose(2) == 'one'
v = enter('one')
assert labels(v) == ['Go two', 'Set'] and lines(v)[5:] == ['second', 'even'], (labels(v), lines(v))
assert choose(1) == 'two'
v = enter('two')                         # no text, flag false: a silent redirect to one
assert str(v.name) == 'one' and lines(v)[5] == 'third' and var('a') == 8
assert choose(2) == 'two' and var('flag') is True and var('a') == 16
v = enter('two')
assert str(v.name) == 'three' and lines(v) == ['Three, a=16.'] and v.ending and not v.cont
# saving and loading keep variables, visits and once-only choices
L.execute('_saved = __TEST.api.S.save(_st); _st = __TEST.api.S.load(_story, _saved)')
assert var('a') == 16 and var('flag') is True and var('name') == 'Ann' and ev('one') == 3
v = enter('one')
assert 'Once only' not in labels(v)
# the index read 7 bytes at a time equals the one read whole, and survives storage
L.execute('_a = __TEST.api.S.index_string(_story)')
L.execute('''_src = _story.src
_b = __TEST.api.S.from_index(_src, _a)
assert(_b and _b.start == 'one' and _b.idx.three[1] == _story.idx.three[1])
assert(__TEST.api.S.from_index({ size = _src.size + 1 }, _a) == nil)''')
# a passage name that is missing, and a story with no passages
engine('== a\n* go -> nowhere\n')
enter('a')
assert choose(1) == 'nowhere'
L.execute('_v, _e = __TEST.api.S.enter(_story, _st, "nowhere")')
assert 'nowhere' in str(L.eval('_e'))
assert L.eval('(__TEST.api.S.index(whole_source("title: x\\nno passages")))') is None
# CRLF files and an "=== name ===" header work too
engine('title: W\r\n\r\n=== start ===\r\nLine one.\r\n* Next -> END\r\n')
v = enter('start')
assert lines(v) == ['Line one.'] and labels(v) == ['Next'] and choose(1) == 'END'
assert enter('END').ending

# ------------------------------------------------------------------ the app: the built-in story

assert A().screen() == 'library'
t = g.texts()
assert 'The Dark Lighthouse' in t and any('Only the built-in story' in x for x in t), t
g.tap_label('The Dark Lighthouse')
assert A().screen() == 'intro' and 'Start' in g.texts() and 'Continue' not in g.texts()
g.tap_label('Start')
assert A().screen() == 'play'
t = g.texts()
assert any('relief keeper' in x for x in t) and 'Look out to sea' in t, t
assert g.commands() < 1024


def play(*labels_):
    for lab in labels_:
        t = g.texts()
        while lab not in ' '.join(t) and A().page() < len(list(A().pages().values())):
            g.key('down'); t = g.texts()
        if lab not in t:
            lab = next(x for x in t if x and lab.startswith(x))
        g.tap_label(lab)
        assert A().screen() == 'play', (lab, A().err())


def page_text():
    out = []
    n = len(list(A().pages().values()))
    for _ in range(n):
        out += g.texts()
        g.key('down')
    for _ in range(n):
        g.key('up')
    return ' '.join(out)


play('Look out to sea', 'Continue')
assert 'Look out to sea' not in g.texts()
play('Walk up to the keeper\'s cottage', 'Take the lantern', 'Search the dresser drawers', 'Continue',
     'Look on the mantelpiece', 'Continue', 'Go to the tower')
assert 'The key from the dresser is heavy in your pocket.' in page_text()
play('Unlock the door', 'Try the door to the store room', 'Continue')
# Undo goes back a page, with the variables as they were there
st_oil = lambda: A().state().vars.oil
assert st_oil() == 3
g.tap_label('Menu'); g.tap_label('Undo')
assert any('Drums of paraffin' in x for x in g.texts())
g.tap_label('Menu'); g.tap_label('Undo')
assert st_oil() == 0 and 'Try the door to the store room' in g.texts()
play('Try the door to the store room', 'Continue')
# leave and come back: the same page, nothing run twice
moves = A().state().vars.moves
g.L.execute('on_leave()')
g.restart()
assert any('in progress' in x for x in g.texts())
g.tap_label('The Dark Lighthouse'); g.tap_label('Continue')
assert A().state().vars.moves == moves and A().state().vars.oil == 3, (A().state().vars.moves, moves)
play('Climb on to the lamp room')
assert 'Fill the tank and light the burner' in ' '.join(g.texts()), g.texts()
play('Fill the tank and light the burner', 'Look for Tom at the fog bell', 'Continue')
t = page_text()
assert 'new keeper will do' in t and '~ The End ~' in t, t
g.L.execute('on_leave()')
g.restart()
assert any('finished' in x for x in g.texts())
g.tap_label('The Dark Lighthouse')
assert 'Start' in g.texts() and 'Continue' not in g.texts()

# the slow way: too late
g.tap_label('Start')
play('Go straight to the tower', 'Break the little window beside it', 'Continue')
for _ in range(20):
    t = ' '.join(g.texts())
    if 'go out on the reef' in page_text():
        break
    if 'Climb on to the lamp room' in t:
        assert ('Sit down for a moment' in t) == (A().state().vars.bruises >= 3)
        play('Climb on to the lamp room')
    else:
        play('Go down for paraffin')
t = page_text()
assert 'go out on the reef' in t and '~ The End ~' in t, t
play('Play again')
assert any('relief keeper' in x for x in g.texts())

# text size: three sizes, kept
g.tap_label('Menu'); g.tap_label('Text size: medium')
assert 'size=3' in g.store['set.txt']
g.tap_label('Text size: large'); g.key('back')

# ------------------------------------------------------------------ user stories

long = '\n'.join(f'Paragraph {k} of a long first page, with enough words to wrap over two lines.' for k in range(40))
user = f'''title: A Long Tale
author: Someone
about: For the test.

== start
{long}
* The only way -> end

== end
Fin.
'''
L.execute(f'user_files["Long Tale.story"] = {lua_str(user)}; user_files["notes.txt"] = "x"')
g.tap_label('Menu'); g.tap_label('Library')
L.execute('__TEST.api.discover()')
assert A().screen() == 'library'
t = g.texts()
assert 'A Long Tale' in t and 'notes.txt' not in ' '.join(t) and not any('Only the built-in' in x for x in t), t
g.tap_label('A Long Tale')
assert 'by Someone' in g.texts() and 'For the test.' in g.texts()
assert 'i_f_Long_Tale.txt' in g.store
g.tap_label('Start')
n = len(list(A().pages().values()))
assert n >= 3 and 'The only way' not in g.texts() and '>' in g.texts(), n
for _ in range(n - 1):
    g.tap(470 - 50, 800 - 40)
assert 'The only way' in g.texts() and '<' in g.texts()
play('The only way')
assert any('Fin.' in x for x in g.texts())
# the index is read from storage the next time, unless the file changed
L.execute('reads = 0')
g.restart()
g.tap_label('A Long Tale')
assert L.eval('reads') <= 3, L.eval('reads')
L.execute(f'user_files["Long Tale.story"] = {lua_str(user.replace("Fin.", "The end, longer now."))}')
g.restart()
g.tap_label('A Long Tale'); g.tap_label('Start')
g.L.execute('__TEST.api.pick(1)')
assert any('longer now' in x for x in g.texts())
# a broken story says what is wrong
L.execute(f'user_files["broken.story"] = {lua_str("title: Broken" + chr(10) + "== a" + chr(10) + "* Go -> missing" + chr(10))}')
g.restart()
g.tap_label('Broken'); g.tap_label('Start'); g.tap_label('Go')
assert A().screen() == 'error' and any('missing' in x for x in g.texts())
g.tap_label('Undo')
assert A().screen() == 'play'

# the help page: the folder and the site's QR code
g.restart()
g.tap_label('More stories')
t = ' '.join(g.texts())
assert '/AppFiles/gamebook/' in t and 'github.io' in t and L.eval('qr_made')
g.tap_label('Back')
assert A().screen() == 'library'
# ------------------------------------------------------------------ converted stories (Node)

import shutil, subprocess
SITE = os.path.join(os.path.dirname(os.path.dirname(HERE)), 'site')
if shutil.which('node'):
    def converted(fixture):
        r = subprocess.run(['node', os.path.join(SITE, 'tools', 'gamebook', 'cli.mjs'), os.path.join(SITE, 'test', 'fixtures', fixture)],
                           capture_output=True, text=True, encoding='utf-8', check=True)
        engine(r.stdout, tiny=False)
        return L.eval('_story.start')

    def go(name):
        return enter(name)

    def pick_label(v, label):
        k = labels(v).index(label) + 1
        nxt = choose(k)
        return enter(nxt)

    v = go(converted('harlowe.html'))
    assert lines(v) == ['You stand at the mouth of a cave.', 'You have 3 coins.'] and labels(v) == ['Go in', 'Buy a torch'], (lines(v), labels(v))
    v = pick_label(v, 'Go in')
    assert lines(v)[0] == 'It is too dark. You go back.' and labels(v) == ['Out'], lines(v)
    v = pick_label(v, 'Out')
    v = pick_label(v, 'Buy a torch')
    assert lines(v) == ['You buy a torch.'] and var('gold') == 1 and var('torch') is True
    v = pick_label(pick_label(v, 'Back'), 'Go in')
    assert 'Your torch shows a door.' in lines(v) and 'You remember the shop.' in lines(v) and labels(v) == ['Open the door'], lines(v)
    v = pick_label(v, 'Open the door')
    assert lines(v) == ['Gold everywhere! 101 coins.'] and labels(v) == ['Take it']
    v = pick_label(v, 'Take it')
    assert lines(v) == ['You leave with 101 coins. The end.'] and v.ending

    v = go(converted('sugar.twee'))
    assert lines(v) == ['Hello Ann, you have 10 hp.', 'You feel strong.'] and labels(v) == ['Fight', 'Rest'], (lines(v), labels(v))
    v = pick_label(v, 'Fight')
    assert lines(v) == ['You fight. HP: 6.']
    v = pick_label(v, 'Again')
    v = pick_label(v, 'Again')            # hp -2: the passage leaves at once, for End
    assert str(v.name) == 'End' and lines(v) == ['The end.'] and v.ending, (str(v.name), lines(v))

    v = go(converted('story.ink'))
    assert lines(v) == ['Once upon a time.'] and str(v.cont) == 'village'
    v = enter('village')
    assert lines(v) == ['You are in the village. You have 2 coins.', 'The bell rings.'] and labels(v) == ['Talk to the smith', 'Buy bread', 'Wait'], (lines(v), labels(v))
    v = pick_label(v, 'Talk to the smith')
    assert lines(v) == ['"Hello," says the smith.'] and var('met') is True and labels(v) == ['Ask about swords', 'Haggle']
    v = pick_label(v, 'Haggle')
    assert lines(v) == ['You haggle. It works.'] and var('coins') == 1
    v = enter(str(v.cont)); assert lines(v) == ['You leave the forge.']
    v = enter(str(v.cont)); assert lines(v) == ['Back in the square.']
    v = enter(str(v.cont))
    assert lines(v) == ["The smith's words ring in your ears.", 'You haggled once.'] and labels(v) == ['Go home', 'Go back'], lines(v)
    v = pick_label(v, 'Go back')
    assert labels(v) == ['Wait'] and lines(v)[1] == 'A dog barks.', (labels(v), lines(v))
    v = pick_label(v, 'Wait'); assert lines(v) == ['Time passes.']
    v = enter(str(v.cont)); assert lines(v)[1] == 'The bell rings.'
    v = pick_label(go('forest'), 'Go home')
    assert lines(v) == ['You reach the door.'] and v.ending
else:
    print('node not found: converted stories not tested')

# ------------------------------------------------------------------ the built-in story and the pack: random playthroughs

import glob, random
STORIES = [os.path.join(HERE, 'data', 'lighthouse.txt')] + sorted(glob.glob(os.path.join(HERE, 'stories', '*', '*.story')))
rng = random.Random(7)
for path in STORIES:
    text = open(path, encoding='utf-8').read()
    engine(text, tiny=False)
    start = str(L.eval('_story.start'))
    names = set(str(n) for n in L.eval('_story.order').values())
    endings, seen = set(), set()
    for run_ in range(600):
        L.execute('_st = __TEST.api.S.new_state(_story)')
        v = enter(start)
        for step in range(300):
            seen.add(str(v.name))
            for l in lines(v):
                assert '{' not in l and '}' not in l, (path, str(v.name), l)
            if v.ending:
                endings.add(str(v.name)); break
            if len(list(v.choices.values())):
                nxt = choose(rng.randint(1, len(list(v.choices.values()))))
            else:
                nxt = str(v.cont)
            v = enter(nxt)
        else:
            raise AssertionError(f'{path}: no ending after 300 steps')
        seen.update(str(k) for k in L.eval('_st.visits').keys())   # silent redirects too
    unseen = names - seen
    assert not unseen, (os.path.basename(path), sorted(unseen))
    print(f'{os.path.basename(path)}: {len(names)} passages, all reached; endings {sorted(endings)}')
    if shutil.which('node'):
        r = subprocess.run(['node', '--input-type=module', '-e',
                            f"import {{ check }} from 'file:///{os.path.join(SITE, 'tools', 'gamebook', 'convert.js').replace(os.sep, '/')}'; "
                            "import { readFileSync } from 'node:fs'; const r = check(readFileSync(process.argv[1], 'utf8')); "
                            "console.log(JSON.stringify(r))", path], capture_output=True, text=True, encoding='utf-8', check=True)
        c = json.loads(r.stdout)
        assert not c['errors'] and not c['warnings'], (path, c)

g.no_err()
print('gamebook: all tests passed')
