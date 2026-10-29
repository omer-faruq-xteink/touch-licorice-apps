"""Offline test of Merchant (API 2.9) under Lua 5.4 (lupa): bundles src/ into index.lua, then
plays through the device screen with a method-style ctx stub: trading, travel and its events,
lender, bank, typed amounts, save and reload, every language, a theme change, a full 30 days.

  python -I apps/merchant/test_merchant.py
"""
import os, re, subprocess, sys
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
subprocess.run([sys.executable, '-I', os.path.join(HERE, 'bundle.py')], check=True)
L = lua54.LuaRuntime(unpack_returned_tuples=True)
L.execute(r'''
drawn, store, inputs = {}, {}, {}
fake_ms = 12345
local gmt = {}
gmt.__index = function(_, k) return function(_, ...) if k == 'text' then local x, y, s = ...; drawn[#drawn + 1] = { s = s, x = x, y = y } end end end
gg = setmetatable({}, gmt)
local function M(t)
  local out = {}
  for k, f in pairs(t) do
    if type(f) == 'function' then out[k] = function(self, ...) assert(self == out, 'method call expected for ' .. k); return f(...) end
    else out[k] = f end
  end
  return out
end
local function font(name, lh) local f = M({ measure = function(s) return utf8.len(s) and utf8.len(s) * 10 or #s * 10 end }); f.line_height = lh; return f end
ctx = {
  invalidate = function() end,
  storage = M({ write = function(n, d) store[n] = d; return true end, read = function(n) if store[n] then return store[n] end return nil, 'not_found' end }),
  fonts = { small = font('small', 20), medium = font('medium', 24), large = font('large', 30) },
  input = M({ text = function(opts, fn) inputs[#inputs + 1] = fn end }),
  clock = M({ millis = function() return fake_ms end }),
}
''')
INDEX = os.path.join(HERE, 'index.lua').replace(os.sep, '/')


def start():
    L.execute(f"dofile([[{INDEX}]])")
    gl = L.globals()
    gl.on_load(gl.ctx)
    return gl


g = start()
tap_ = L.eval("function(x, y) on_input(ctx, {type='pointer', phase='down', x=x, y=y}); on_input(ctx, {type='pointer', phase='up', x=x, y=y}) end")
key = L.eval("function(k) fake_ms = fake_ms + 300; on_input(ctx, {type='key', key=k}) end")
draw = L.eval(r"function() drawn = {}; on_draw(ctx, gg); for _, d in ipairs(drawn) do if not utf8.len(d.s) then error('invalid UTF-8 drawn: ' .. d.s:gsub('[\128-\255]', function(c) return string.format('<%02X>', c:byte()) end)) end end; return drawn end")


def texts():
    return [str(v.s) for v in draw().values()]


def recs():
    out = {}
    for r in draw().values():
        out[str(r.s)] = (int(r.x), int(r.y))          # the last one drawn: a button over a title
    return out


def tap_label(label):
    r = recs()
    assert label in r, (label, list(r))
    x, y = r[label]
    tap_(x + 3, y + 5)


def no_err():
    t = texts()
    assert not any('ERR' in x for x in t), t


def num(s):
    return int(re.sub(r'[^\d]', '', s))


MARKET_Y, ROW = 186, 72
t = texts()
assert 'Constantinople' in t and 'Day 1 / 30' in t and 'Cash 2,000 silver' in t, t
assert 'Bazaar - buy low, sell high:' in t and 'Travel' in t and 'Moneylender' in t and 'Guild bank' in t, t
assert 'game.txt' in g.store

# buy the cheapest good there is a price for, as many as possible
def goods_rows():
    rows = {}
    for r in draw().values():
        s, y = str(r.s), int(r.y)
        if MARKET_Y <= y < MARKET_Y + 6 * ROW and int(r.x) == 16 and not s.startswith('you hold'):
            rows[(y - MARKET_Y) // ROW] = s
    return rows

priced = None
for i in range(5, -1, -1):
    tap_(100, MARKET_Y + i * ROW + 20)
    t = texts()
    if any('each' in x for x in t) and '(Buy)' not in t:
        priced = i
        break
    tap_label('Cancel')
assert priced is not None, 'no good to buy on day 1'
tap_label('Buy')
assert any(x.startswith('Up to ') for x in texts())
tap_label('Max')
tap_label('Buy')
no_err()
t = texts()
assert any(x.startswith('you hold ') for x in t), t
held = num([x for x in t if x.startswith('you hold ')][0])
assert held > 0
assert re.search(r'inventory=[\d,]*[1-9]', g.store['game.txt']), g.store['game.txt']
# sell a typed amount: 1
tap_(100, MARKET_Y + priced * ROW + 20)
tap_label('Sell')
tap_label('Type')
g.inputs[1](g.ctx, '1')
g.inputs = L.table()
assert '1' in texts()
tap_label('Sell')
assert any(x == f'you hold {held - 1}' for x in texts()), texts()

# bank: deposit half, withdraw; lender: pay back some, borrow
cash0 = num([x for x in texts() if x.startswith('Cash ')][0])
tap_label('Guild bank'); tap_label('Deposit'); tap_label('1/2'); tap_label('Deposit')
t = texts()
assert any(x.startswith('Bank ') and not x.startswith('Bank 0 ') for x in t), t
tap_label('Guild bank'); tap_label('Withdraw'); tap_label('Max'); tap_label('Withdraw')
assert num([x for x in texts() if x.startswith('Cash ')][0]) == cash0
tap_label('Moneylender'); tap_label('Borrow'); tap_label('-1,000'); tap_label('Borrow')
assert num([x for x in texts() if x.startswith('Cash ')][0]) > cash0
tap_label('Moneylender'); tap_label('Pay back'); tap_label('Max'); tap_label('Pay back')
no_err()

# languages: every one loads; Turkish shows Turkish, the game carries over; back to English
day_line = [x for x in texts() if x.startswith('Day ')][0]
tap_label('Settings')
seen = []
for _ in range(7):
    lang = [x for x in texts() if x.startswith('Language: ') or x.startswith('Dil: ') or ': ' in x and x.split(': ')[0] in
            ('Sprache', 'Idioma', 'Langue', 'Lingua')]
    tap_label([x for x in texts() if re.match(r'^[^:]+: (English|Deutsch|Español|Français|Italiano|Português|Türkçe)$', x)][0])
    seen.append([x for x in texts() if re.match(r'^[^:]+: (English|Deutsch|Español|Français|Italiano|Português|Türkçe)$', x)][0])
    no_err()
    if seen[-1].endswith('Türkçe'):
        t = texts()
        assert any(x.startswith('Gün ') for x in t) and any(x.startswith('Nakit ') for x in t), t
        assert 'Dil: Türkçe' in t, t
assert seen[-1] == 'Language: English', seen
assert len(set(seen)) == 7, seen
key('back')
assert [x for x in texts() if x.startswith('Day ')][0] == day_line

# travel: a day passes; events and offers are answered by the first enabled button
def settle():
    # answer event boxes with their last button (OK, No thanks, or the theme's Flee), until the
    # board is back or the game is over
    for _ in range(30):
        tx = texts()
        if 'Travel' in tx or 'Warp' in tx or any('Final net worth' in x for x in tx):
            return
        assert not tx[-1].startswith('('), tx
        tap_label(tx[-1])
        no_err()
    raise AssertionError(texts())


def travel_once():
    tap_label('Travel')
    t = texts()
    dests = [x for x in t if x != t[0] and x in ('Constantinople', 'Baghdad', 'Samarkand', 'Bukhara', 'Kashgar', "Chang'an")]
    tap_label(dests[-1])
    settle()

travel_once()
assert 'Day 2 / 30' in texts(), texts()
no_err()

# save and reload: the same day, cash and goods
before = g.store['game.txt']
g = start()
assert g.store['game.txt'] == before
assert 'Day 2 / 30' in texts()

# theme: the new one starts with the next new game
tap_label('Settings'); tap_label('Theme: Silk Road caravan')
assert 'Theme: Star trader' in texts()
tap_label('Close')
assert 'Bazaar - buy low, sell high:' in texts()                  # the run keeps its theme
tap_label('New game'); tap_label('New game')
t = texts()
assert 'Trade terminal - buy low, sell high:' in t and 'Terra Station' in t and 'Day 1 / 30' in t, t

# play to the end: 30 days, then the final score and a best score for the theme
for _ in range(80):
    t = texts()
    if any('Final net worth' in x for x in t):
        break
    if 'Warp' in t:
        tap_label('Warp')
        here = texts()[0]                                  # the place, at the top
        dests = [x for x in texts() if x != here and x in ('Terra Station', 'Luna Port', 'Mars Colony', 'Ceres Belt', 'Europa Dock', 'Titan Refinery')]
        tap_label(dests[0])
    settle()
t = texts()
assert any('Final net worth' in x for x in t) and any('Best ever' in x for x in t), t
assert 'space=' in g.store['scores.txt'], g.store.get('scores.txt')
tap_label('New game')
assert 'Day 1 / 30' in texts()
tap_label('Scores')
assert any(x.startswith('Star trader: ') and 'cr' in x for x in texts()), texts()
assert any(x.startswith('Silk Road caravan: ') for x in texts())
no_err()
print('merchant tests passed')
