"""Test of tools/gamekit/imgview.lua under Lua 5.4 (lupa): an article picture on the whole screen,
shared by the reading apps (RSS, Instapaper, Readwise, wallabag).

  python -I tools/gamekit/test_imgview.py
"""
import os
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
L = lua54.LuaRuntime(unpack_returned_tuples=True)
IV = L.execute(open(os.path.join(HERE, 'imgview.lua'), encoding='utf-8').read())

# ---------------------------------------------------------------- the original address
src = 'https://images.weserv.nl/?url=https%3A%2F%2Fexample.com%2Fa%20b.png%3Fx%3D1&w=456&h=300&fit=contain'
assert IV.source(src) == 'https://example.com/a b.png?x=1', IV.source(src)
assert IV.source('https://images.weserv.nl/?w=10') is None
assert IV.source('https://other.host/?url=abc') is None
assert IV.source(None) is None
assert IV.meta_url('https://example.com/a b.png') == 'https://images.weserv.nl/?url=https%3A%2F%2Fexample.com%2Fa%20b.png&output=json'

# ---------------------------------------------------------------- the full-screen copy
# a wide picture on a portrait screen is turned: the box's long side becomes its width
url, rot = IV.full_url('https://e.com/p.png', 577, 311, 480, 770)
assert rot is True, rot
assert '&w=770&h=480&' in url and '&fit=inside' in url and '&ro=90' in url and 'url=https%3A%2F%2Fe.com%2Fp.png' in url, url
# a tall one is not; nor any picture on a landscape screen
url, rot = IV.full_url('https://e.com/p.png', 300, 900, 480, 770)
assert rot is False and '&w=480&h=770&' in url and 'ro=' not in url, url
url, rot = IV.full_url('https://e.com/p.png', 577, 311, 800, 450)
assert rot is False and '&w=800&h=450&' in url and 'ro=' not in url, url

# ---------------------------------------------------------------- the view
L.execute(r'''
log, fails, refreshed, released = {}, {}, 0, 0
answers = {}            -- url part -> { body } or { nil, err }
waiting = {}
host = {
  get = function(url, accept, cb) log[#log + 1] = accept .. ' ' .. url; waiting[#waiting + 1] = function()
    for k, a in pairs(answers) do if url:find(k, 1, true) then return cb(a[1], a[2]) end end
    cb(nil, 'HTTP 404') end end,
  decode = function(bytes, mw, mh) decoded = { bytes, mw, mh }
    if bytes == 'BAD' then return nil, 'invalid_argument' end
    return setmetatable({}, { __index = { width = 420, height = 700, release = function() released = released + 1 end } }) end,
  json = function(s) local w, h = s:match('"width":(%d+),"height":(%d+)'); if not w then error('bad json') end
    return { width = tonumber(w), height = tonumber(h) } end,
  refresh = function() refreshed = refreshed + 1 end,
  fail = function(msg) fails[#fails + 1] = msg end,
}
function answer() local w = waiting; waiting = {}; for _, f in ipairs(w) do f() end end
texts, images = {}, {}
gg = setmetatable({}, { __index = function(_, k) return function(_, a, b, c, d)
  if k == 'text' then texts[#texts + 1] = c end
  if k == 'image' then images[#images + 1] = { a, b, c } end end end })
bar = {}
function draw(v) texts, images = {}, {}; v:draw(gg, 480, 800, { small = 'S', medium = 'M' }); bar = { v:bar_rect(480, 800) } end
''')
g = L.globals()
v = IV.new(g.host)
SRC = 'https://images.weserv.nl/?url=https%3A%2F%2Fe.com%2Fshot.png&w=456&h=300'
g.answers = L.table_from({'output=json': L.table_from(['{"width":1200,"height":700}']), 'ro=90': L.table_from(['JPEG'])})
assert not v.is_open(v)
assert v.open(v, SRC, 2, 5, 480, 800) is True
assert v.is_open(v)
assert list(g.log.values()) == ['application/json https://images.weserv.nl/?url=https%3A%2F%2Fe.com%2Fshot.png&output=json'], list(g.log.values())
L.eval('draw')(v)
t = list(g.texts.values())
assert 'Image 2 of 5' in t and any('Loading' in s for s in t) and len(g.images) == 0, t
g.answer()                                   # the size: a wide screenshot -> the turned copy is asked
last = list(g.log.values())[-1]
assert last.startswith('image/jpeg ') and '&w=720&h=480&' in last and '&ro=90' in last, last
g.answer()                                   # the picture: decoded to fit between the heading and the buttons
assert g.decoded[1] == 'JPEG' and g.decoded[2] == 480 and g.decoded[3] == 720, list(g.decoded.values())
L.eval('draw')(v)
t = list(g.texts.values())
assert len(g.images) == 1 and not any('Loading' in s for s in t), t
im = g.images[1]
assert im[2] == (480 - 420) // 2 and im[3] == 30 + (720 - 700) // 2, (im[2], im[3])
assert 'Zoom in' in t and 'Zoom out' in t, t
assert any('turned' in s for s in t) and any('Back' in s for s in t), t
assert g.refreshed >= 2

# ---------------------------------------------------------------- zoom
# the original is 1200 x 700, turned; the box in the original's orientation is 720 x 480, so the
# whole picture is at 0.6. A double tap at the shown picture's middle (it is drawn 420 x 700 at
# 30, 40) asks the part around the original's (600, 350) at twice that: 600 x 400 from (300, 150)
L.execute('''
function up(v, x, y, gesture, dx, dy) return v:pointer({ type = 'pointer', phase = 'up', x = x, y = y, gesture = gesture,
  down_x = dx or x, down_y = dy or y }) end
''')
up = L.eval('up')
g.answers = L.table_from({'precrop': L.table_from(['ZOOM'])})
up(v, 240, 390, 'tap')                       # the double tap's first tap: nothing
assert 'precrop' not in list(g.log.values())[-1]
up(v, 240, 390, 'double_tap')
last = list(g.log.values())[-1]
assert '&cx=300&cy=150&cw=600&ch=400&precrop&w=720&h=480&fit=inside&ro=90&' in last, last
L.eval('draw')(v)
t = list(g.texts.values())
assert any('Loading' in s for s in t) and len(g.images) == 1, t     # the whole one stays meanwhile
g.answer()
assert g.decoded[1] == 'ZOOM' and g.decoded[2] == 480 and g.decoded[3] == 720
L.eval('draw')(v)
t = list(g.texts.values())
assert any('2x' in s for s in t) and not any('Loading' in s for s in t) and len(g.images) == 1, t
# a drag moves the picture with the finger: 100 px to the right on the turned picture is 83 px
# further down the original (at 1.2), so the part now starts at y = 233
up(v, 340, 390, 'swipe_right', 240, 390)
last = list(g.log.values())[-1]
assert '&cx=300&cy=233&cw=600&ch=400&' in last, last
g.answer()
rel = g.released
# Zoom in (the button): 4x around the same middle, 300 x 200
by = int(g.bar[2])
up(v, 480 - 60, by + 20, 'tap')
last = list(g.log.values())[-1]
assert '&cx=450&cy=333&cw=300&ch=200&' in last, last
g.answer()
assert g.released == rel + 1                 # the part shown before is freed
n_log = len(g.log)
up(v, 480 - 60, by + 20, 'tap')              # no further than 4x
assert len(g.log) == n_log
# far drags stop at the picture's edge
up(v, 0, 390, 'swipe_left', 470, 390); g.answer()
up(v, 470, 390, 'swipe_right', 0, 390); g.answer()
up(v, 470, 390, 'swipe_right', 0, 390); g.answer()
assert '&cx=450&cy=500&cw=300&ch=200&' in list(g.log.values())[-1], list(g.log.values())[-1]
# keys move half a screen: up on the turned picture is to the original's left
assert v.key(v, 'up') is True
assert '&cx=300&cy=500&' in list(g.log.values())[-1], list(g.log.values())[-1]
g.answer()
# Zoom out (the button): 2x; Back: the whole picture, at once; Back again: not handled (the app closes)
up(v, 60, by + 20, 'tap')
assert '&cw=600&ch=400&' in list(g.log.values())[-1]
g.answer()
n_log = len(g.log)
assert v.key(v, 'back') is True and len(g.log) == n_log
L.eval('draw')(v)
assert not any('2x' in s for s in g.texts.values()) and len(g.images) == 1
assert v.key(v, 'back') is False and v.is_open(v)
# a part that cannot be had: the picture stays, with a word in the heading
g.answers = L.table_from({})
up(v, 240, 390, 'double_tap'); g.answer()
assert v.is_open(v)
L.eval('draw')(v)
t = list(g.texts.values())
assert any('Zoom failed' in s for s in t) and len(g.images) == 1, t
# Back while a part is loading drops it
g.answers = L.table_from({'precrop': L.table_from(['ZOOM'])})
up(v, 240, 390, 'double_tap')
assert v.key(v, 'back') is True
g.answer()
L.eval('draw')(v)
assert not any('2x' in s for s in g.texts.values())
v.close(v)
assert not v.is_open(v)

# a tall picture is not turned: the double tap's place maps straight onto the original (300 x 900,
# at 0.8; the top-left corner -> the part from (0, 0), 300 x 450 at 2x)
g.answers = L.table_from({'output=json': L.table_from(['{"width":300,"height":900}']), 'w=480': L.table_from(['JPEG']), 'precrop': L.table_from(['ZOOM'])})
v.open(v, SRC, 1, 1, 480, 800); g.answer(); g.answer()
up(v, 30, 40, 'double_tap')
last = list(g.log.values())[-1]
assert '&cx=0&cy=0&cw=300&ch=450&precrop&w=480&h=720&fit=inside&output' in last, last
v.close(v)

# a result arriving after the view was closed is dropped (and its picture freed)
v.open(v, SRC, 1, 1, 480, 800)
v.close(v)
g.answer(); g.answer()
assert not v.is_open(v) and len(g.waiting) == 0

# failures: not a resizer address, no size, no picture, a picture that does not decode
assert v.open(v, 'https://e.com/x.png', 1, 1, 480, 800) is False and not v.is_open(v)
assert 'cannot' in g.fails[len(g.fails)], list(g.fails.values())
g.answers = L.table_from({'output=json': L.table_from([None, 'net down'])})
v.open(v, SRC, 1, 1, 480, 800); g.answer()
assert not v.is_open(v) and 'net down' in g.fails[len(g.fails)], list(g.fails.values())
g.answers = L.table_from({'output=json': L.table_from(['{"width":300,"height":900}'])})
v.open(v, SRC, 1, 1, 480, 800); g.answer()
last = list(g.log.values())[-1]
assert '&w=480&h=720&' in last and 'ro=' not in last, last         # tall: not turned
g.answer()                                                           # no answer for it: HTTP 404
assert not v.is_open(v) and '404' in g.fails[len(g.fails)], list(g.fails.values())
g.answers = L.table_from({'output=json': L.table_from(['{"width":300,"height":900}']), 'w=480': L.table_from(['BAD'])})
v.open(v, SRC, 1, 1, 480, 800); g.answer(); g.answer()
assert not v.is_open(v) and 'invalid_argument' in g.fails[len(g.fails)], list(g.fails.values())
print('imgview: all tests passed')
