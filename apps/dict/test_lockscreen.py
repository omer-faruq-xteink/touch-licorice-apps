"""Offline test of the Dictionary's Word of the Day lock screen (lockscreen.lua) under Lua 5.4
(lupa): a WordNet-like fake dictionary, the day's pick and its cache, the layout, the dictionary
chosen in the app; then 60 days of the real WordNet set when the release zip is at hand.

  python -I apps/dict/test_lockscreen.py [path/to/dict-wordnet-en.zip]
"""
import glob, os, sys, zipfile
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

WN = {
    'wn_info.txt': 'name=WordNet\nwords=7\nshards=2\n',
    'wn_shards.tsv': 'wn_d000.txt\tAbel\tbanana\nwn_d001.txt\tBanff\tzoo\n',
    'wn_d000.txt': ('Abel\tn : son of Adam [syn: {Abel}]\n'
                    'a cappella\tadv : without instrumental accompaniment\n'
                    'abandon\tv 1: forsake, leave behind; "We abandoned the old car in the empty parking lot" [syn: {give up}]'
                    '\\n2: stop maintaining or insisting on; "He abandoned the thought of asking for her hand"\\n'
                    'n : the trait of lacking restraint or control; "the wild abandon of the dancers"\n'
                    'ab\tn : a short word\n'
                    'banana\tn 1: any of several tropical and subtropical treelike herbs\\n2: elongated crescent-shaped yellow fruit\n'),
    'wn_d001.txt': ('Banff\tn : a town in Alberta\n'
                    'quietly\tadv : with little or no activity or no agitation; "her hands rested quietly in her lap"\n'
                    'zoo\tn : the facility where wild animals are housed for exhibition [syn: {menagerie}, {zoological garden}]\n'),
    'tr_info.txt': 'name=Test Tr-En\nwords=1\nshards=1\n',
    'tr_shards.tsv': 'tr_d000.txt\tçiçek\tçiçek\n',
    'tr_d000.txt': 'çiçek\tnoun flower\\n“Bahçede çiçek var.”\n',
}
GOOD = {'abandon', 'banana', 'quietly'}

L = lua54.LuaRuntime(unpack_returned_tuples=True)
TR = {k: WN.pop(k) for k in ['tr_info.txt', 'tr_shards.tsv', 'tr_d000.txt']}   # added later: it sorts first
store = dict(WN)
L.globals().py_store = store
L.execute(r'''
drawn, commands = {}, 0
local gmt = {}
gmt.__index = function(_, k) return function(_, ...)
  commands = commands + 1
  if k == 'text' then local x, y, s, o = ...; drawn[#drawn + 1] = { s = s, x = x, y = y, f = (type(o) == 'table' and type(o.font) == 'table') and o.font.name or '?' } end
end end
gg = setmetatable({}, gmt)
local function M(t)
  local out = {}
  for k, f in pairs(t) do
    if type(f) == 'function' then out[k] = function(self, ...) assert(self == out, 'method call expected for ' .. k); return f(...) end
    else out[k] = f end
  end
  return out
end
local function font(name, lh) local f = M({ measure = function(s) return (utf8.len(s) or #s) * 10 end }); f.name = name; f.line_height = lh; return f end
reads = 0
now = { epoch_sec = 1793091600, hour = 14, minute = 0, second = 0 }    -- 2026-10-27 11:00 UTC, 14:00 at UTC+3
ctx = {
  storage = M({ write = function(n, d) py_store[n] = d; return true end,
    read = function(n) reads = reads + 1; local v = py_store[n]; if v ~= nil then return v end return nil, 'not_found' end,
    list = function() local t = {}; for k in python.iter(py_store) do t[#t + 1] = k end return t end }),
  fonts = { small = font('small', 20), medium = font('medium', 24), large = font('large', 30) },
  clock = M({ now = function() return now end }),
}
''')
L.execute(f"dofile([[{os.path.join(HERE, 'lockscreen.lua').replace(os.sep, '/')}]])")
g = L.globals()
draw = L.eval("function() drawn, commands = {}, 0; on_draw(ctx, gg); return drawn end")
def recs(): return [(str(r.s), str(r.f), int(r.x), int(r.y)) for r in draw().values()]
def texts(): return [r[0] for r in recs()]
def set_day(d): L.execute(f"now.epoch_sec = 1793091600 + {d} * 86400")

t = texts()
assert t[:2] == ['Word of the Day', 'Tuesday 27 October 2026'], t
word = t[2]
assert word in GOOD, t                                # no capitals, phrases or short words
assert str(store['wotd.txt']).startswith(f'24:20753\twn_\t{word}\t'), store['wotd.txt']
assert t[-1] == 'WordNet' and not any('error' in x for x in t), t
# the same day draws from wotd.txt: no shard is read
store.pop('wn_d000.txt'); store.pop('wn_d001.txt')
assert texts()[2] == word
store.update(WN)

# WordNet layout: part of speech, numbered senses, examples and synonyms indented
store['wotd.txt'] = '24:20753\twn_\tabandon\t' + WN['wn_d000.txt'].split('\n')[2].split('\t', 1)[1]
r = recs()
t = [x[0] for x in r]
assert t[2] == 'abandon' and r[2][1] == 'large', r[:3]
i = t.index('verb')
assert t[i + 1] == '1. forsake, leave behind' and r[i + 1][1] == 'medium', t[i:]
assert r[i + 2][2] == 20 + 22 and r[i + 2][0].startswith('"We abandoned') and r[i + 2][1] == 'small', r[i + 2]
assert 'also: give up' in t and any(x.startswith('2. stop maintaining') for x in t), t
assert t.index('noun') > t.index('also: give up') and 'the trait of lacking restraint or' in ' '.join(t), t
assert all(x[3] < 800 - 40 for x in r[:-1]) and g.commands < 900

# another day, another pick; the next draw caches it
set_day(1)
t = texts()
assert t[1] == 'Wednesday 28 October 2026' and t[2] in GOOD, t
assert str(store['wotd.txt']).startswith('24:20754\t'), store['wotd.txt']
# a long entry stops at the bottom with "..."
store['wotd.txt'] = '24:20754\twn_\tbanana\tn 1: ' + ' '.join(['word'] * 600)
r = recs()
assert r[-2][0] == '...' and max(x[3] for x in r[:-1]) < 800 - 48, r[-3:]

# the dictionary chosen in the app (lock_dict.txt); other dictionaries line by line
set_day(2)
store.update(TR)
store['lock_dict.txt'] = 'wn_'
assert texts()[-1] == 'WordNet'
store['lock_dict.txt'] = 'tr_'                       # switched in the app: the same day picks again
t = texts()
assert t[2] == 'çiçek' and 'noun flower' in t and '“Bahçede çiçek var.”' in t and t[-1] == 'Test Tr-En', t
# a new word every 6 hours: the same one from 12:00 to 17:59, another at 18:00
def set_time(day, hour): L.execute(f"now.epoch_sec = 1793091600 + {day} * 86400 + ({hour} - 14) * 3600; now.hour = {hour}")
store['lock_dict.txt'] = 'wn_'
store['wotd_every.txt'] = '6'
set_time(5, 12)
w12 = texts()[2]
assert str(store['wotd.txt']).startswith('6:%d\t' % ((20753 + 5) * 4 + 2)), store['wotd.txt']
set_time(5, 17)
assert texts()[2] == w12
set_time(5, 18)
assert texts()[2] in GOOD and str(store['wotd.txt']).startswith('6:%d\t' % ((20753 + 5) * 4 + 3)), store['wotd.txt']
store['wotd_every.txt'] = '5'                          # not one of the choices: once a day
texts()
assert str(store['wotd.txt']).startswith('24:20758\t'), store['wotd.txt']
L.execute("now.hour = 14")

# no dictionary at all
for k in list(store): store.pop(k)
set_day(4)
t = texts()
assert 'Dictionary: copy a dictionary' in t and not any('error' in x for x in t), t

# 60 days of the real WordNet set: plain words, a few lines that fit
zips = sys.argv[1:] or sorted(glob.glob(os.path.join(ROOT, 'release', '*', 'dict-wordnet-en.zip')))[-1:]
if zips:
    z = zipfile.ZipFile(zips[0])
    store.update({n: z.read(n).decode('utf-8') for n in z.namelist() if n.endswith(('.txt', '.tsv'))})
    words = []
    for d in range(60):
        set_day(10 + d)
        r = recs()
        words.append(r[2][0])
        assert r[2][0].isalpha() and r[2][0].islower() and len(r) > 4, r[:4]
        assert max(x[3] for x in r[:-1]) < 800 - 48 and g.commands < 900, (r[2][0], g.commands)
    assert len(set(words)) == 60, words
    print('WordNet days:', ', '.join(words[:8]), '...')
print('dict lock screen tests passed')
