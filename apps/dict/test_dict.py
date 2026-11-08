"""Offline test of the Dictionary app under Lua 5.4 (lupa) with a method-style ctx stub and a
tiny converted dictionary in the fake storage.

  python test_dict29.py [SHARD_DIR]   (SHARD_DIR: real converter output to test against too)
"""
import os, sys
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
import subprocess as _sp                                                 # src/ -> index.lua first
_sp.run([sys.executable, '-I', os.path.join(HERE, 'bundle.py')], check=True, stdout=_sp.DEVNULL)
L = lua54.LuaRuntime(unpack_returned_tuples=True)

store = {
    'info.txt': 'name=Test En-Tr\nwords=9\nshards=2\n',
    'shards.tsv': "d000.txt\t'-fuge\tapple\nd001.txt\tapplet\tzoo\n",
    'd000.txt': "'-fuge\tsuffix\nabandon\tverb terk etmek\\n“He abandoned the car.”\\n→ Arabayı terk etti.\nApple\tnoun elma (brand)\napple\tnoun elma\n",
    'd001.txt': "applet\tnoun küçük uygulama\napply\tverb uygulamak\nzoo\tnoun hayvanat bahçesi\n",
    'tren_info.txt': 'name=Test Tr-En\nwords=2\nshards=1\n',
    'tren_shards.tsv': "tren_d000.txt\telma\tzürafa\n",
    'tren_d000.txt': "elma\tnoun apple\nzürafa\tnoun giraffe\n",
}
if len(sys.argv) > 1:
    store = {fn: open(os.path.join(sys.argv[1], fn), encoding='utf-8').read() for fn in os.listdir(sys.argv[1]) if fn.endswith(('.txt', '.tsv'))}

L.globals().py_store = store
L.execute(r'''
drawn = {}
local gmt = {}
gmt.__index = function(_, k) return function(_, ...) if k == 'text' then local x, y, s, o = ...; drawn[#drawn + 1] = { s = s, x = x, y = y, f = (type(o) == 'table' and type(o.font) == 'table') and o.font.name or '?' } end end end
gg = setmetatable({}, gmt)
local function M(t)
  local out = {}
  for k, f in pairs(t) do
    if type(f) == 'function' then out[k] = function(self, ...) assert(self == out, 'method call expected for ' .. k); return f(...) end
    else out[k] = f end
  end
  return out
end
local function font(name, lh) local f = M({ measure = function(s) return #s * 10 end }); f.name = name; f.line_height = lh; return f end
edits, lock_def, lock_calls = {}, false, ''
ctx = {
  invalidate = function() end, state = {},
  storage = M({ write = function(n, d) py_store[n] = d; return true end, read = function(n) local v = py_store[n]; if v ~= nil then return v end return nil, 'not_found' end,
    list = function() local t = {}; for k in python.iter(py_store) do if not k:find('^pkg:') then t[#t + 1] = k end end return t end }),
  fonts = { small = font('small', 20), medium = font('medium', 24), large = font('large', 30) },
  lockscreen = M({ is_default = function() return lock_def end,
    set_default = function() lock_def = true; lock_calls = lock_calls == '' and 'set' or lock_calls .. ',set' end,
    clear_default = function() lock_def = false; lock_calls = lock_calls .. ',clear' end }),
  input = M({ edit = function(opts) local ed = M({ close = function() end }); ed.opts = opts; edits[#edits + 1] = ed; return ed end }),
  package = M({ open_text = function(name, opts)
    local text = py_store['pkg:' .. name]
    if text == nil then return nil, 'not_found' end
    assert(type(opts) == 'table' and opts.max_line_bytes >= 4096, 'long lines need max_line_bytes')
    local pos = 1
    return M({ read_line = function()
      if pos > #text then return nil end
      local e = text:find('\n', pos, true) or (#text + 1)
      local line = text:sub(pos, e - 1); pos = e + 1
      return line
    end, close = function() end })
  end }),
}
''')
L.execute(f"dofile([[{os.path.join(HERE, 'index.lua').replace(os.sep, '/')}]])")
g = L.globals()
draw = L.eval("function() drawn = {}; on_draw(ctx, gg); return drawn end")
texts = lambda: [str(v.s) for v in draw().values()]
tap = L.eval("function(x, y) on_input(ctx, {type='pointer', phase='down', x=x, y=y}); on_input(ctx, {type='pointer', phase='up', gesture='tap', x=x, y=y}) end")
key = L.eval("function(k) on_input(ctx, {type='key', key=k}) end")

g.on_load(g.ctx)
assert len(g.edits) == 1, 'editor opened on load'
ed = g.edits[1]
if len(sys.argv) > 1:
    ed.opts.on_change(g.ctx, 'aband')
    t = texts()
    assert any(x.startswith('aband') for x in t), t
    ed.opts.on_end(g.ctx, 'abandon', 'enter')
    t = texts()
    assert 'abandon' in t and len(t) > 6 and not any('not found' in x for x in t), t[:8]
    print('real-shard lookup ok:', [x for x in t if x][:6])
    sys.exit(0)

t = texts()
assert 'Test En-Tr' in t and '9 words (storage)' in t and 'Settings' in t, t
assert str(g.py_store['lock_dict.txt']) == ''                 # the lock screen's dictionary
# Settings: the second dictionary, then back to the search
SET_ROW = lambda i: 56 + 40 + i * 56 + 10
tap(430, 20)
t = texts()
assert 'Test En-Tr  (in use)' in t and 'Test Tr-En' in t and 'off   (tap to turn on)' in t, t
tap(100, SET_ROW(1))
assert 'Test Tr-En  (in use)' in texts() and str(g.ctx.state.dict) == 'tren_'
assert str(g.py_store['lock_dict.txt']) == ''              # the lock screen keeps its own
key('back')
assert 'Test Tr-En' in texts()
g.edits[len(g.edits)].opts.on_end(g.ctx, 'elma', 'enter')
assert 'noun apple' in texts()
tap(30, 20)
tap(430, 20)
tap(100, SET_ROW(0))
# the lock screen: on and off through the firmware
LOCK_ROW = 56 + 40 + 2 * 56 + 40 + 10
tap(100, LOCK_ROW)
assert g.lock_calls == 'set' and 'on   (tap to turn off)' in texts(), texts()
tap(100, LOCK_ROW)
assert g.lock_calls == 'set,clear' and 'off   (tap to turn on)' in texts()
# the lock screen's dictionary: its own row cycles through them
assert 'from Test En-Tr   (tap to change)' in texts(), texts()
tap(100, LOCK_ROW + 56)
assert 'from Test Tr-En   (tap to change)' in texts() and str(g.py_store['lock_dict.txt']) == 'tren_'
tap(100, LOCK_ROW + 56)
assert str(g.py_store['lock_dict.txt']) == ''
# how often a new word comes: day, 12, 6, 3, 1 hours, then a day again
assert 'a new word every day' in texts(), texts()
seen = []
for _ in range(5):
    tap(100, LOCK_ROW + 2 * 56)
    seen.append(str(g.py_store['wotd_every.txt']))
assert seen == ['12', '6', '3', '1', '24'] and 'a new word every day' in texts(), seen
tap(100, LOCK_ROW + 2 * 56)
assert 'a new word every 12 hours' in texts()
tap(30, 20)
assert 'Test En-Tr' in texts()
ed = g.edits[len(g.edits)]
# typing "ap" suggests apple, Apple, applet, apply in shard order
ed.opts.on_change(g.ctx, 'ap')
t = texts()
assert t[t.index('ap') + 1:t.index('ap') + 5] == ['Apple', 'apple', 'applet', 'apply'], t
# Done with "apple" opens the entry (case-insensitive exact match wins)
ed.opts.on_end(g.ctx, 'apple', 'enter')
t = texts()
assert t[0] == 'Back' and 'apple' in t and 'noun elma' in t, t
assert str(g.py_store['history.txt']).split('\n')[0].split('\t')[0] == 'apple'
# Back reopens the editor with the query
tap(30, 20)
last = lambda: g.edits[len(g.edits)]
assert str(last().opts.text) == 'apple'
# multi-line definition with quote indent
last().opts.on_end(g.ctx, 'abandon', 'enter')
recs = list(draw().values())
by = {str(r.s): (str(r.f), int(r.x)) for r in recs}
assert by['abandon'] == ('large', 12) and by['verb terk etmek'][0] == 'medium', by
assert by['“He abandoned the car.”'][1] == 36 and by['→ Arabayı terk etti.'][1] == 36, by
# unknown word -> first suggestion fallback, else not found
tap(30, 20)
last().opts.on_end(g.ctx, 'zo', 'enter')
assert 'zoo' in texts()
tap(30, 20)
last().opts.on_end(g.ctx, 'qqq', 'enter')
assert any('not found' in x for x in texts())
# history shows when the query is empty
last().opts.on_change(g.ctx, '')
t = texts()
assert 'recent' in t and t[t.index('recent') + 1] == 'zoo', t
# My words: every word looked up, newest first, with how often; Review on the FSRS schedule
L.execute("fake_now = 1794000000; ctx.clock = { now = function(self) return { epoch_sec = fake_now } end }")
last().opts.on_end(g.ctx, 'apple', 'enter')               # apple a second time
tap(30, 20)
assert str(g.py_store['history.txt']).split('\n')[0].startswith('apple\t2\t1794000000'), g.py_store['history.txt']
recs_ = lambda: {str(r.s): (int(r.x), int(r.y)) for r in draw().values()}
tap(300, 20)                                              # My words (left of Settings)
t = texts()
assert t[:4] == ['Back', 'Prev', 'Next', 'Review 4'] and '4 words' in t, t
assert t[t.index('4 words') + 1] == 'apple' and 'looked up 2 times · new' in t and 'Clear history' in t, t
# a word opens its entry; Back returns to My words
x, y = recs_()['abandon']; tap(x + 5, y + 5)
assert 'verb terk etmek' in texts()
tap(30, 20)
assert 'Clear history' in texts()
# its x: once asks, again removes it (from the reviews too)
x, y = recs_()['zoo']
tap(480 - 36, y + 20)
assert 'tap x again to remove it' in texts() and 'zoo' in texts()
tap(480 - 36, y + 20)
t = texts()
assert 'zoo' not in t and '3 words' in t and 'removed: zoo' in t, t
assert 'zoo' not in str(g.py_store['history.txt'])
# Review: oldest look-up first; the word, then its entry and the four grades with their intervals
tap(4 + 3 * 118 + 10, 20)
t = texts()
assert 'Show' in t and '3 left' in t and 'elma' in t, t                 # elma: looked up in the other dictionary
tap(240, 800 - 90)
t = texts()
assert '(not in Test En-Tr)' in t and t[-8:] == ['Again', '1m', 'Hard', '6m', 'Good', '10m', 'Easy', '14d'], t
tap(12 + 2 * 120 + 20, 800 - 90)                                         # Good
assert str(g.py_store['cards.txt']).startswith('elma\t1794000600 '), g.py_store['cards.txt']
t = texts()
assert 'abandon' in t and '2 left' in t, t
tap(240, 800 - 90); assert 'verb terk etmek' in texts()
tap(12 + 3 * 120 + 20, 800 - 90)                                         # Easy: days away
tap(240, 800 - 90); tap(12 + 0 * 120 + 20, 800 - 90)                     # apple: Again, back in a minute
t = texts()
assert 'Nothing to review now.' in t and 'The next word comes in 1m.' in t, t
assert str(g.py_store['review_day.txt']) == str(1794000000 // 86400) + ' 3'
L.execute("fake_now = fake_now + 120")
tap(30, 20)                                                              # Back: My words
assert 'Review 1' in texts(), texts()
key('back'); assert 'Clear history' not in texts()                       # Back: the search
assert L.eval("function() return on_input(ctx, {type='key', key='back'}) end")() is False   # the first screen: the host asks
tap(300, 20)
# Clear history: once asks, again removes every word and every card
x, y = recs_()['Clear history']
tap(x + 5, y + 5)
assert any(s.startswith('Tap again to remove all 3 words') for s in texts()), texts()
tap(x + 5, y + 5)
t = texts()
assert 'No words yet: look some up.' in t and 'history cleared' in t, t
assert str(g.py_store['history.txt']) == '' and str(g.py_store['cards.txt']) == ''
tap(4 + 3 * 118 + 10, 20)
assert 'Nothing to review now.' in texts() and 'Words you look up come here.' in texts()
tap(30, 20); key('back')
# user folder (ctx.files, AppFiles/<app_id>): the same files there instead of the private files
user = {}
for k in [k for k in list(store) if str(k) not in ('history.txt', 'lock_dict.txt', 'wotd_every.txt') and not str(k).startswith('pkg:')]:
    user[str(k)] = store.pop(k)
reads = []
def f_read(self, name, off=0, ln=65536):
    reads.append((str(name), off))
    t = user.get(str(name))
    return None if t is None else t.encode('utf-8')[off:off + min(ln, 65536)].decode('utf-8', 'ignore')
g.ctx.files = L.table_from({'exists': lambda self, n: str(n) in user, 'read': f_read,
                            'list': lambda self: L.table_from([L.table_from({'name': n, 'size': len(t)}) for n, t in user.items()]),
                            'path': '/AppFiles/u-1234abcd'})
L.execute(f"dofile([[{os.path.join(HERE, 'index.lua').replace(os.sep, '/')}]])")
g = L.globals(); g.on_load(g.ctx)
assert '9 words (storage)' in texts() and reads, (texts(), reads[:3])
tap(30, 20)
last().opts.on_end(g.ctx, 'abandon', 'enter')
assert 'verb terk etmek' in texts(), texts()
# nothing anywhere: the empty screen names the user folder
saved = dict(user); user.clear()
L.execute(f"dofile([[{os.path.join(HERE, 'index.lua').replace(os.sep, '/')}]])")
g = L.globals(); g.on_load(g.ctx)
assert '  /AppFiles/u-1234abcd' in texts(), texts()
for k, v in saved.items():
    store[k] = v
g.ctx.files = None
L.execute(f"dofile([[{os.path.join(HERE, 'index.lua').replace(os.sep, '/')}]])")
g = L.globals(); g.on_load(g.ctx)
# package backend: move the files behind the package reader
for k in [k for k in store if k != 'history.txt' and not k.startswith('pkg:')]:
    store['pkg:' + k] = store.pop(k)
L.execute(f"dofile([[{os.path.join(HERE, 'index.lua').replace(os.sep, '/')}]])")
g = L.globals(); g.on_load(g.ctx)
assert '9 words (package)' in texts(), texts()
ed = g.edits[len(g.edits)]
ed.opts.on_change(g.ctx, 'ap')
t = texts()
assert t[t.index('ap') + 1:t.index('ap') + 5] == ['Apple', 'apple', 'applet', 'apply'], t
ed.opts.on_end(g.ctx, 'abandon', 'enter')
assert 'verb terk etmek' in texts(), texts()
# no data screen
store.pop('pkg:shards.tsv')
L.execute(f"dofile([[{os.path.join(HERE, 'index.lua').replace(os.sep, '/')}]])")
g.on_load(g.ctx)
assert any('No dictionary files' in x for x in texts()), texts()
print('dict29 tests passed')
