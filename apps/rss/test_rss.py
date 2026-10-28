"""Offline test of the API 2.9 RSS app under Lua 5.4 (lupa): a method-style ctx stub whose
net:request answers from canned JSON (list, article, feeds) and records the URLs it was given.

  python rss29/test_rss29.py
"""
import json, os
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
L = lua54.LuaRuntime(unpack_returned_tuples=True)

responses = {}
requests = []


fail_next = {}          # key -> how many times a matching request fails with HTTP 502 first


def fake_request(url):
    requests.append(url)
    for key in list(fail_next):
        if key in url and fail_next[key] > 0:
            fail_next[key] -= 1
            return 502, 'Error: CommaFeed /category/get failed: HTTP 503'
    if url.startswith('https://images.weserv.nl/'):              # article images: raw JPEG bytes
        return (200, b'\xff\xd8' + b'x' * 100) if 'url=AAA' in url else (404, 'not found')
    if url.split('?')[0].endswith('/api'):                      # the Worker's root: account list
        return (200, json.dumps(responses['__root__'])) if '__root__' in responses else (404, '{"error":"not found"}')
    for key, body in sorted(responses.items(), key=lambda kv: -len(kv[0])):   # most specific first
        if key in url:
            return body if isinstance(body, tuple) else (200, json.dumps(body, separators=(',', ':'), ensure_ascii=False))
    return 404, '{"error":"not found"}'


L.globals().py_request = fake_request
def device_decode(s):
    # as on the reader: the tags of list items come through empty, whatever the Worker sent
    d = json.loads(s)
    for it in (d.get('items') or []) if isinstance(d, dict) else []:
        if isinstance(it, dict) and 'tag_line' in it:
            it['tag_line'] = ''
    return L.table_from(d, recursive=True)
L.globals().py_json_decode = device_decode

L.execute(r'''
drawn, store = {}, {}
local gmt = {}
images_drawn = 0
gmt.__index = function(_, k) return function(_, ...) if k == 'image' then images_drawn = images_drawn + 1 end if k == 'text' then local x, y, s, o = ...; drawn[#drawn + 1] = { s = s, x = x, y = y, f = (type(o) == 'table' and type(o.font) == 'table') and o.font.name or '?' } end end end
gg = setmetatable({}, gmt)
local function M(t)
  local out = {}
  for k, f in pairs(t) do
    if type(f) == 'function' then out[k] = function(self, ...) assert(self == out, 'method call expected for ' .. k); return f(...) end
    else out[k] = f end
  end
  return out
end
pending = {}
local function font(name, lh) local f = M({ measure = function(s) return #s * 10 end }); f.name = name; f.line_height = lh; return f end
ctx = {
  set_tick = function() error('no timer: redraws slow the network down') end,
  invalidate = function() end, state = {},
  storage = M({ write = function(n, d) store[n] = d; return true end, read = function(n) if store[n] then return store[n] end return nil, 'not_found' end,
                   remove = function(n) store[n] = nil; return true end,
                   list = function() local t = {} for k in pairs(store) do t[#t + 1] = k end return t end }),
  fonts = { small = font('small', 20), medium = font('medium', 24), large = font('large', 30) },
  input = M({ text = function(opts, fn) input_opts = opts; pending[#pending + 1] = fn end }),
  net = M({ keep_wifi = function(ms) kept = kept or {}; kept[#kept + 1] = ms end, request = function(opts, fn)
    assert(type(opts.url) == 'string' and type(fn) == 'function')
    last_headers = opts.headers
    local st, body = py_request(opts.url)
    pending[#pending + 1] = function() fn(ctx, { status = st, body = body, headers = {} }) end
    return M({ cancel = function() cancelled = (cancelled or 0) + 1 end })
  end }),
  json = M({ decode = function(s) return py_json_decode(s) end }),
  image = M({ decode = function(b) decoded = (decoded or 0) + 1; return setmetatable({}, { __index = { width = 456, height = 300, release = function() released = (released or 0) + 1 end } }) end }),
  qr = M({ encode = function(t) if qr_fail then error('qr too long') end; qr_made = t; return setmetatable({}, { __index = { width = 33, height = 33, release = function() qr_released = (qr_released or 0) + 1 end } }) end }),
  base64 = M({ encode = function(s) return 'B64(' .. s .. ')' end }),
}
-- answers arrive one at a time; an answer may start the next queued request, so keep going
function step() local p = pending; pending = {}; for _, f in ipairs(p) do f() end end
function flush() for _ = 1, 50 do local p = pending; pending = {}; if #p == 0 then return end; for _, f in ipairs(p) do f() end end end
fake_ms = 1000
ctx.clock = M({ millis = function() return fake_ms end })
''')
L.execute(f"dofile([[{os.path.join(HERE, 'index.lua').replace(os.sep, '/')}]])")
g = L.globals()
tap = L.eval("function(x, y) on_input(ctx, {type='pointer', phase='down', x=x, y=y}); on_input(ctx, {type='pointer', phase='up', gesture='tap', x=x, y=y}) end")
key = L.eval("function(k) fake_ms = fake_ms + 300; on_input(ctx, {type='key', key=k}) end")
draw = L.eval("function() drawn = {}; on_draw(ctx, gg); return drawn end")
texts = lambda: [str(v.s) for v in draw().values()]

responses['/api/list?kind=unread'] = {'title': 'Unread', 'page': 1, 'has_more': True,
                                      'items': [{'id': str(100 + i), 'title': f'Article {i}', 'feed': 'Feed', 'date': '2026-10-24 08:00', 'read': False, 'excerpt': 'x'} for i in range(12)]}
_items = responses['/api/list?kind=unread']['items']
_items[2]['title'] = 'A very long article title that does not fit on one line of the list at all, with more words'
_items[2]['excerpt'] = 'Summary sentence. ' * 30
_items[4]['excerpt'] = 'Endless summary text. ' * 120
responses['/api/article/103'] = {'id': '103', 'title': 'Article 3', 'feed': 'Feed', 'date': '2026-10-24 08:00',
                                 'text': '# Heading here\n\nFirst paragraph with several words in it.\n\n> a quote\n\n• item one\n• item two\n\n' + ('word ' * 1200)}
responses['/api/feeds'] = {'items': [{'id': '10', 'name': 'Feed A', 'unread': 3}, {'id': '11', 'name': 'Feed B', 'unread': 0}]}
responses['/api/list?kind=feed'] = {'title': 'Feed A', 'page': 1, 'has_more': False, 'items': [{'id': '555', 'title': 'Only one', 'feed': 'Feed A', 'date': '', 'read': True, 'excerpt': ''}]}

# no host yet -> settings screen; fill host and token through the editor callbacks
g.on_load(g.ctx)
assert 'Host (e.g. rss.example.workers.dev)' in texts()
tap(100, 56 + 20 + 24 + 10)          # host field
g.pending[1](g.ctx, 'rss.example.workers.dev ')
g.pending = L.table()
tap(100, 56 + 20 + 96 + 24 + 10)     # token field
g.pending[1](g.ctx, 'secret')
g.pending = L.table()
assert g.store['config.txt'] == 'host=rss.example.workers.dev\ntoken=secret\nauth=\nfull=0\nsize=default\nimages=0', g.store['config.txt']
tap(100, 20)                         # Back
assert 'RSS' in texts()

# Unread list
tap(100, 100 + 10)
g.flush()
assert requests[-1] == 'https://rss.example.workers.dev/k/secret/api/list?kind=unread&page=1&n=12', requests[-1]
t = texts()
assert 'Article 0' in t and 'Article 11' in t, t

# long press -> preview with the full title and the summary; never opens the article itself
long_ev = L.eval("function(x, y, ph, g) on_input(ctx, {type='pointer', phase=ph, gesture=g, x=x, y=y}) end")
row_y = lambda i: 56 + 26 + i * 58 + 5
def recs():
    return {str(r.s): (int(r.x), int(r.y)) for r in draw().values()}
def tap_label(label):
    x, y = recs()[label]
    tap(x + 5, y + 5)
n_req = len(requests)
long_ev(100, row_y(2), 'hold', None); long_ev(100, row_y(2), 'up', 'long')     # hold, then release
r = recs()
assert len(requests) == n_req, 'a long press must not fetch the article'
assert 'Open' in r and 'Close' in r and 'Article 0' not in r, list(r)
assert 'more words' in r and any(s.startswith('Summary sentence.') for s in r), list(r)
assert r['Open'][1] < 740, r['Open']                                                  # room left below the box
assert 'Back' not in r and 'Reload' not in r and not any(k.startswith('Unread  ') for k in r), list(r)  # bar hidden
open_y = r['Open'][1]                                                                  # the box's size is fixed
tap_label('Close')
assert 'Article 0' in texts() and 'Open' not in texts()
long_ev(100, row_y(2), 'up', 'long')                                                  # release-only variant
assert 'Close' in texts()
tap(240, 790)                                                                         # outside the box closes
assert 'Article 0' in texts()
long_ev(100, row_y(4), 'up', 'long')                                                  # very long summary: cut with "…"
t = texts()
assert any(s.endswith(' …') for s in t) and recs()['Open'][1] == open_y, t
key('back')
assert 'Article 0' in texts()
long_ev(100, row_y(2), 'up', 'long')
tap_label('Open'); g.flush()
assert requests[-1].endswith('/api/article/102?max=20000&mark=1'), requests[-1]
tap(50, 20)                                                                           # Back: to the same preview
t = texts()
assert 'Close' in t and 'more words' in t and 'Article 0' not in t, t
key('back')                                                                           # Back again: the list
assert 'Article 0' in texts() and 'Close' not in texts(), (texts(), requests[-3:])
long_ev(100, row_y(2), 'up', 'long')
tap_label('Open'); g.flush()
key('back')                                                                           # the Back key does the same
assert 'Close' in texts() and 'more words' in texts()
key('back')
tap(100, row_y(2)); g.flush()                                                         # opened straight from the list:
tap(50, 20)                                                                           # Back goes to the list
assert 'Article 0' in texts() and 'Close' not in texts(), texts()

# Next scrolls inside the loaded rows and, past the last one, loads and appends the next page
responses['/api/list?kind=unread&page=2'] = {'title': 'Unread', 'page': 2, 'has_more': True,
    'items': [{'id': str(112 + i), 'title': f'Article {12 + i}', 'feed': 'Feed', 'date': '', 'read': False, 'excerpt': ''} for i in range(10)]}
responses['/api/list?kind=unread&page=3'] = {'title': 'Unread', 'page': 3, 'has_more': False,
    'items': [{'id': '121', 'title': 'Article 21', 'feed': 'Feed', 'date': '', 'read': False, 'excerpt': ''},      # duplicate of page 2
              {'id': '122', 'title': 'Article 22', 'feed': 'Feed', 'date': '', 'read': False, 'excerpt': ''},
              {'id': '123', 'title': 'Article 23', 'feed': 'Feed', 'date': '', 'read': False, 'excerpt': ''}]}
NEXT, RELOAD = (4 + 2 * 118 + 10, 20), (4 + 3 * 118 + 10, 20)
assert 'Unread  1-12 / 12+' in texts(), texts()
tap(*NEXT); g.flush()                                 # past the last row -> page 2, new rows on screen
assert requests[-1].endswith('kind=unread&page=2&n=12'), requests[-1]
t = texts()
assert 'Unread  13-22 / 22+' in t and 'Article 12' in t and 'Article 21' in t and 'Load more' not in t, t
n_req = len(requests)
long_ev(100, row_y(10), 'up', 'long'); tap(100, row_y(10))   # empty row below the last item: nothing happens
assert 'Close' not in texts() and len(requests) == n_req
tap(*NEXT); g.flush()                                 # screen not full, more on the server -> page 3 appended
assert requests[-1].endswith('kind=unread&page=3&n=12'), requests[-1]
t = texts()
assert 'Unread  13-24 / 24' in t and 'Article 22' in t and 'Article 23' in t and 'Load more' not in t, t
assert t.count('Article 21') == 1, t
n_req = len(requests)
key('left')                                           # back to the first rows, nothing fetched
t = texts()
assert 'Article 0' in t and 'Unread  1-12 / 24' in t and len(requests) == n_req, t
tap(*NEXT); tap(*NEXT); tap(*NEXT)                    # at the end without more: Next stays put
assert 'Unread  13-24 / 24' in texts() and len(requests) == n_req, texts()
tap(*RELOAD); g.flush()                               # Reload starts over at page 1
assert requests[-1].endswith('kind=unread&page=1&n=12') and 'Unread  1-12 / 12+' in texts(), texts()

# preview Prev / Next: buttons, side buttons and swipes walk the list
kev = L.eval("function(k, t) on_input(ctx, {type='key', key=k, phase='down', time_ms=t}) end")
header = lambda: [x for x in texts() if x.startswith('Unread')][0]
long_ev(100, row_y(2), 'up', 'long')
tap_label('Next')
assert 'Article 3' in texts() and 'Close' in texts(), texts()
kev('right', 10000)
assert 'Article 4' in texts()
kev('left', 11000)
assert 'Article 3' in texts()
long_ev(240, 300, 'up', 'swipe_left')
assert 'Article 4' in texts() and 'Close' in texts()
tap_label('Close')
assert 'Article 0' in texts() and header() == 'Unread  1-12 / 12+'
long_ev(100, row_y(0), 'up', 'long')                  # first article: no Prev button, Prev does nothing
t = texts()
assert t.count('Prev') == 0 and t.count('Next') == 1, t   # the bar is hidden; the box has only Next
kev('left', 12000)
assert 'Article 0' in texts() and 'Close' in texts()
key('back')
assert 'Close' not in texts()

# Next on the last loaded article loads the next page and shows its first article
n_req = len(requests)
long_ev(100, row_y(11), 'up', 'long')
assert texts().count('Next') == 1 and texts().count('Prev') == 1      # more on the server: Next offered
tap_label('Next')
assert len(requests) == n_req + 1 and requests[-1].endswith('kind=unread&page=2&n=12'), requests[-1]
assert 'Article 11' in texts()                        # still the same article until the page arrives
g.flush()
assert 'Article 12' in texts() and 'Close' in texts(), texts()
tap_label('Close')                                    # the list follows to that page
assert header() == 'Unread  13-22 / 22+', header()

# closing while that page is still loading: the list ends up on the new page anyway
tap(*RELOAD); g.flush()
assert header() == 'Unread  1-12 / 12+'
long_ev(100, row_y(11), 'up', 'long')
tap_label('Next')
tap_label('Close')
assert header() == 'Unread  1-12 / 12+'
g.flush()
assert header() == 'Unread  13-22 / 22+' and 'Close' not in texts(), texts()

# Open from a preview, Back to the preview, Close: the list is on that article's screen
long_ev(100, row_y(0), 'up', 'long')                  # first row of this screen = Article 12
assert 'Article 12' in texts()
tap_label('Open'); g.flush()
tap(50, 20)
assert 'Article 12' in texts() and 'Close' in texts(), texts()
tap_label('Close')
assert header() == 'Unread  13-22 / 22+', header()
tap(*RELOAD); g.flush()
assert header() == 'Unread  1-12 / 12+'

# open article 3 -> text wrapped and paged, mark=1 sent
tap(100, 56 + 26 + 3 * 58 + 5)
g.flush()
assert requests[-1].endswith('/api/article/103?max=20000&mark=1'), requests[-1]
t = texts()
assert t[0] == 'Back' and 'Article 3' in t and any(x.startswith('1/') for x in t), t
pages = int([x for x in t if '/' in x and x[0].isdigit()][0].split('/')[1])
assert pages >= 2, pages
assert all(len(x) <= 46 for x in t if 'word' in x), [x for x in t if 'word' in x][:3]
assert 'Heading here' in t and 'a quote' in t and '• item one' in t, t
styles = {str(r.s): (str(r.f), int(r.x) - 12) for r in draw().values()}
assert styles['Article 3'][0] == 'large' and styles['Heading here'][0] == 'large'
assert styles['a quote'] == ('medium', 24) and styles['• item one'] == ('medium', 16), {k: v for k, v in styles.items() if 'quote' in k or 'item' in k}
assert styles['Feed 2026-10-24 08:00'][0] == 'small', [k for k in styles if 'Feed' in k]
tap(400, 400)                         # right side -> next page
assert any(x.startswith('2/') for x in texts())
# side buttons: one press may arrive as press + release, or as a quick repeat -> one page each
key_ev = L.eval("function(k, ph, t) on_input(ctx, {type='key', key=k, phase=ph, time_ms=t}) end")
page_of = lambda: [x for x in texts() if '/' in x and x[0].isdigit()][0].split('/')[0]
key_ev('right', 'down', 1000); key_ev('right', 'up', 1040)
assert page_of() == '3', page_of()
key_ev('right', 'down', 2000); key_ev('right', 'down', 2080)
assert page_of() == '4', page_of()
key_ev('left', 'down', 3000); key_ev('left', 'up', 3030)
assert page_of() == '3', page_of()
key_ev('left', 'down', 3500)
assert page_of() == '2', page_of()
assert 'a103.txt' in g.store
# Back to list keeps items; list is cached too
tap(50, 20)
assert 'Article 5' in texts()
assert 'l_unread_0_1.txt' in g.store
# regression: open another article while its request is still in flight -> the frame must not
# index the previous article's page table (was "attempt to index a nil value" at the bottom)
tap(100, 56 + 26 + 5 * 58 + 5)
t = texts()
assert not any('ERR' in x for x in t), t
g.flush()                                   # let that request finish (an answer the host always gives)
tap(50, 20)

# Text size: Settings cycles default -> large -> small; articles and previews follow it
def fonts_of(word):
    return {str(r.f) for r in draw().values() if word in str(r.s)}
key('back')                                            # list -> menu
tap(100, 100 + 5 * 70 + 10)                            # Settings
SIZE_ROW = 56 + 20 + 4 * 96 + 24 + 10
assert any(x.startswith('default') for x in texts()), texts()
tap(100, SIZE_ROW)
assert any(x.startswith('large') for x in texts()) and g.store['config.txt'].endswith('size=large\nimages=0'), g.store['config.txt']
tap(100, 20)                                           # back to the menu
tap(100, 100 + 10); g.flush()                          # Unread
tap(100, 56 + 26 + 3 * 58 + 5)                         # Article 3 again (cached): laid out with large text
assert fonts_of('First paragraph') == {'large'} and fonts_of('Article 3') == {'large'}, (fonts_of('First paragraph'), fonts_of('Article 3'))
assert fonts_of('2026-10-24') == {'medium'}            # feed / date line one step up
tap(50, 20)                                            # back to the list
long_ev(100, row_y(2), 'up', 'long')                   # the preview follows the setting too
assert fonts_of('Summary sentence.') == {'large'}, fonts_of('Summary sentence.')
tap_label('Close')
key('back')
tap(100, 100 + 5 * 70 + 10)
tap(100, SIZE_ROW)                                     # large -> small
assert g.store['config.txt'].endswith('size=small\nimages=0')
tap(100, 20)
tap(100, 100 + 10); g.flush()
tap(100, 56 + 26 + 3 * 58 + 5)
assert fonts_of('First paragraph') == {'small'} and fonts_of('Article 3') == {'medium'}, (fonts_of('First paragraph'), fonts_of('Article 3'))
tap(50, 20)
key('back')
tap(100, 100 + 5 * 70 + 10)
tap(100, SIZE_ROW)                                     # small -> default again
assert g.store['config.txt'].endswith('size=default\nimages=0')
tap(100, 20)
tap(100, 100 + 10); g.flush()
tap(100, 56 + 26 + 3 * 58 + 5)
assert fonts_of('First paragraph') == {'medium'} and fonts_of('Article 3') == {'large'}
tap(50, 20)

# Images: off by default; on, articles are asked with images=1 and their images load per page
responses['/api/article/104'] = {'id': '104', 'title': 'Article 4', 'feed': 'Feed', 'date': '',
    'text': 'Before\n\n[[img:1]]\n\nAfter\n\n[[img:2]]\n\nEnd', 'images': [
        {'n': 1, 'w': 456, 'h': 300, 'src': 'https://images.weserv.nl/?url=AAA&w=456&h=300'},
        {'n': 2, 'w': 200, 'h': 100, 'src': 'https://images.weserv.nl/?url=BBB&w=200&h=100'}]}
IMAGES_ROW = 56 + 20 + 5 * 96 + 24 + 10
key('back')
tap(100, 100 + 5 * 70 + 10)                            # Settings
assert 'off' in texts()
tap(100, IMAGES_ROW)
assert g.store['config.txt'].endswith('images=1'), g.store['config.txt']
tap(100, 20)
tap(100, 100 + 10); g.flush()                          # Unread
n_req = len(requests)
tap(100, 56 + 26 + 4 * 58 + 5)                         # Article 4
assert requests[-1].endswith('/api/article/104?max=20000&mark=1&images=1'), requests[-1]
g.step()                                               # article text; the first image is requested
assert requests[-1] == 'https://images.weserv.nl/?url=AAA&w=456&h=300', requests[-1]
assert 'Authorization' not in dict(g.last_headers), dict(g.last_headers)   # no Worker credentials to the resizer
t = texts()
assert 'Before' in t and 'After' in t and 'image…' in t and g.images_drawn == 0, t
g.step()                                               # image 1 arrives, image 2 is requested
assert g.decoded == 1 and requests[-1] == 'https://images.weserv.nl/?url=BBB&w=200&h=100', requests[-1]
g.step()                                               # image 2 fails
t = texts()
assert g.images_drawn == 1 and '[image]' in t and 'image…' not in t, (g.images_drawn, t)
assert 'a104i.txt' in g.store and 'a104.txt' not in g.store
tap(50, 20)                                            # back to the list, open it again from the cache
tap(100, 56 + 26 + 4 * 58 + 5)
assert (g.released or 0) >= 1                          # the previous images were released
g.flush()
texts()                                                # draw the page: the image is on it again
assert g.images_drawn >= 2, g.images_drawn
tap(50, 20)
key('back')
tap(100, 100 + 5 * 70 + 10)
tap(100, IMAGES_ROW)                                   # images off again
assert g.store['config.txt'].endswith('images=0')
tap(100, 20)
tap(100, 100 + 10); g.flush()

# offline: network fails, tried once more, then the cached list is used
responses.clear()
n_req = len(requests)
tap(4 + 3 * 118 + 10, 20); g.step()   # Reload -> 404
assert len(requests) == n_req + 2 and requests[-1] == requests[-2], requests[-2:]   # the automatic retry
t = texts()
assert any(x.startswith('loading') for x in t), t                                  # still loading meanwhile
g.flush()                             # retry -> 404 -> cache
t = texts()
assert 'Article 7' in t and any('offline' in x for x in t), t

# feeds: a failure is retried once; if that fails too and nothing is cached, the screen says why
key('back')
n_req = len(requests)
tap(100, 100 + 3 * 70 + 10); g.flush(); g.flush()
t = texts()
assert len(requests) == n_req + 2 and 'no feeds' not in t and 'Could not load this list.' in t and any('HTTP 404' in x for x in t), t
# a hiccup on the first try only: the retry fills the list, nothing about an error
responses['/api/feeds'] = {'items': [{'id': '10', 'name': 'Feed A', 'unread': 3}]}
responses['/api/list?kind=feed'] = {'title': 'Feed A', 'page': 1, 'has_more': False, 'items': [{'id': '555', 'title': 'Only one', 'feed': 'Feed A', 'date': '', 'read': True, 'excerpt': ''}]}
fail_next['/api/feeds'] = 1
tap(4 + 3 * 118 + 10, 20); g.flush(); g.flush()          # Reload on the feeds screen
t = texts()
assert 'Feed A  (3)' in t and 'Could not load this list.' not in t, t
# one request at a time: a second one waits in the queue until the first is answered
n_req = len(requests)
tap(4 + 3 * 118 + 10, 20); tap(4 + 3 * 118 + 10, 20)   # Reload twice on the feeds screen
assert len(g.pending) == 1 and len(requests) == n_req + 1, (len(g.pending), requests[n_req:])
g.step()                                                  # the first answers, the second starts
assert len(requests) == n_req + 2 and any(x.startswith('loading') for x in texts()), texts()
g.flush()
t = texts()
assert 'Feed A  (3)' in t and not any(x.startswith('loading') for x in t), t
# the host never answers: Reload after a few seconds gives that request up and asks again
n_req = len(requests)
tap(4 + 3 * 118 + 10, 20)
g.pending = L.table()                                     # the answer is lost
assert any(x.startswith('loading') for x in texts()), texts()
L.execute("fake_ms = fake_ms + 5000")
tap(4 + 3 * 118 + 10, 20)                                 # Reload
assert len(requests) >= n_req + 2, requests[n_req:]
g.flush()
t = texts()
assert 'Feed A  (3)' in t and not any(x.startswith('loading') for x in t), t
# ... and without Reload, the timeout cancels it; the automatic retry then fills the list
cancels = L.eval("function() return cancelled or 0 end")
c0 = cancels()
tap(4 + 3 * 118 + 10, 20)
g.pending = L.table()
L.execute("fake_ms = fake_ms + 31000")
texts()                                                   # the next draw notices the timeout
assert cancels() == c0 + 1, cancels()
g.flush()
t = texts()
assert 'Feed A  (3)' in t and not any(x.startswith('loading') for x in t), t
tap(100, 56 + 26 + 5); g.flush()
assert 'kind=feed&page=1&n=12&id=10' in requests[-1], requests[-1]
assert 'Only one' in texts()

# Back from a feed's articles goes to the feeds, then to the menu
key('back')
assert 'Feed A  (3)' in texts(), texts()
key('back')
assert 'Tags' in texts() and 'Settings' in texts(), texts()
# Tags: the tag list is asked only when the row is tapped; a tag opens its articles
assert not any('/api/tags' in r for r in requests)
responses['/api/tags'] = {'items': [{'name': 'to read'}, {'name': 'work'}], 'editable': True}
responses['/api/list?kind=tag'] = {'title': 'to read', 'page': 1, 'has_more': False, 'items': [
    {'id': '700', 'title': 'Tagged story', 'feed': 'Feed A', 'feed_id': '10', 'date': '', 'read': True, 'starred': False,
     'tag_line': 'to read', 'excerpt': 'tagged {braces} "quoted", fine'},
    {'id': '701', 'title': 'Old list row', 'feed': 'Feed A', 'feed_id': '10', 'date': '', 'read': True, 'starred': False,
     'tags': ['kept'], 'excerpt': 'from an older Worker'}]}
tap(100, 100 + 4 * 70 + 10); g.flush()
assert requests[-1].endswith('/api/tags'), requests[-1]
t = texts()
assert 'to read' in t and 'work' in t, t
tap(100, 56 + 26 + 5); g.flush()
assert requests[-1].endswith('kind=tag&page=1&n=12&id=to%20read'), requests[-1]
assert 'Tagged story' in texts() and 'l_tag_to_20read_1.txt' in g.store
# the preview shows the tags, and Star / Mark unread / Tags
long_ev(100, row_y(0), 'up', 'long')
t = texts()
assert 'Tags: to read' in t and 'Star' in t and 'Mark unread' in t and 'Tags' in t and 'Open' in t, t
assert recs()['Star'][1] < recs()['Open'][1], recs()
responses['/api/star/700'] = {'ok': True}
tap_label('Star'); g.flush()
assert requests[-1].endswith('/api/star/700?on=1&feed=10'), requests[-1]
t = texts()
assert 'Unstar' in t and any(x.endswith('· starred') for x in t) and 'starred' in t, t
tap_label('Unstar'); g.flush()
assert requests[-1].endswith('/api/star/700?on=0&feed=10') and 'Star' in texts(), requests[-1]
responses['/api/mark/700'] = {'ok': True}
tap_label('Mark unread'); g.flush()
assert requests[-1].endswith('/api/mark/700?read=0'), requests[-1]
t = texts()
assert 'Mark read' in t and any(x.endswith('· unread') for x in t), t
# Tags: the keyboard starts with the current ones; the line replaces them
responses['/api/tag/700'] = {'ok': True, 'tags': ['to read', 'later'], 'tag_line': 'to read, later'}
g.pending = L.table()
tap_label('Tags')
assert g.input_opts.value == 'to read', g.input_opts.value
fn = g.pending[1]; g.pending = L.table()
fn(g.ctx, 'to read, later'); g.flush()
assert requests[-1].endswith('/api/tag/700?tags=to%20read%2C%20later'), requests[-1]
t = texts()
assert 'Tags: to read, later' in t and 'tags saved' in t, t
# a Worker signed in with the API key cannot change tags: say what it needs
responses['/api/tag/700'] = (501, '{"error":"editing tags needs the CommaFeed username and password on the Worker"}')
tap_label('Tags')
fn = g.pending[1]; g.pending = L.table()
fn(g.ctx, 'x'); g.flush()
t = texts()
assert 'Worker: tags need the CommaFeed password' in t and 'Tags: to read, later' in t, t
# a row without tag_line (older Worker): its tags show, but they are not edited blindly
tap_label('Next')
t = texts()
assert 'Old list row' in t and 'Tags: kept' in t, t
g.pending = L.table(); n_req = len(requests)
tap_label('Tags')
assert len(g.pending) == 0 and len(requests) == n_req and 'Reload the list (and update the Worker) first' in texts(), texts()
tap_label('Prev')
# open it (marked read), mark it unread, open again from the offline copy: marked read again
responses['/api/article/700'] = {'id': '700', 'title': 'Tagged story', 'feed': 'Feed A', 'date': '', 'text': 'Tagged text.'}
tap_label('Open'); g.flush()
assert requests[-1].endswith('/api/article/700?max=20000&mark=1&full=1') or requests[-1].endswith('/api/article/700?max=20000&mark=1'), requests[-1]
key('back')
tap_label('Mark unread'); g.flush()
tap_label('Open'); g.flush()
assert requests[-1].endswith('/api/mark/700?read=1') and 'Tagged text.' in texts(), requests[-1]
n_req = len(requests)
key('back'); tap_label('Open'); g.flush()                # already read: nothing sent
assert len(requests) == n_req
key('back'); key('back')                                 # article -> preview -> list
key('back')                                              # list -> the tags
t = texts()
assert 'to read' in t and 'work' in t, t
key('back')
assert 'Settings' in texts()

# basic auth header and full-text switch
g.cfg_set = L.eval("function() end")
L.execute("screen_to_settings = function() end")
key('back'); key('back')
tap(100, 100 + 5 * 70 + 10)           # Settings
tap(100, 56 + 20 + 2 * 96 + 24 + 10)  # auth field
g.pending[1](g.ctx, 'me:pw')
g.pending = L.table()
tap(100, 56 + 20 + 3 * 96 + 24 + 10)  # full toggle
assert g.store['config.txt'].endswith('auth=me:pw\nfull=1\nsize=default\nimages=0'), g.store['config.txt']
tap(100, 20)
tap(100, 100 + 10); g.flush()
assert requests[-1].endswith('&full=1') and g.last_headers['Authorization'] == 'Basic B64(me:pw)', (requests[-1], dict(g.last_headers))
assert not any('ERR' in x for x in texts())

# ---- two CommaFeed accounts: folders in the menu, ?acct= on requests, separate caches
responses.clear()
responses['__root__'] = {'title': 'CommaFeed', 'accounts': [{'id': '1', 'label': 'Work'}, {'id': '2', 'label': 'Personal'}]}
responses['kind=unread&page=1&n=12&acct=2'] = {'title': 'Unread', 'page': 1, 'has_more': False,
    'items': [{'id': '900', 'title': 'Personal story', 'feed': 'Blog', 'date': '', 'read': False, 'excerpt': 'p'}]}
responses['kind=unread&page=1&n=12&acct=1'] = {'title': 'Unread', 'page': 1, 'has_more': False,
    'items': [{'id': '800', 'title': 'Work story', 'feed': 'News', 'date': '', 'read': False, 'excerpt': 'w'}]}
responses['/api/article/900'] = {'id': '900', 'title': 'Personal story', 'feed': 'Blog', 'date': '', 'text': 'hello'}
L.execute(f"dofile([[{os.path.join(HERE, 'index.lua').replace(os.sep, '/')}]])")
g = L.globals()
g.pending = L.table()
g.on_load(g.ctx)
assert requests[-1].split('?')[0].endswith('/api') and 'acct=' not in requests[-1], requests[-1]
g.flush()
t = texts()
assert 'Work' in t and 'Personal' in t and 'Settings' in t and 'Unread' not in t, t
assert 'accounts.txt' in g.store
tap(100, 100 + 1 * 70 + 10)                            # Personal
t = texts()
assert 'RSS · Personal' in t and 'Unread' in t and 'Accounts' in t, t
tap(100, 100 + 10); g.flush()                          # Unread of Personal
assert 'acct=2' in requests[-1], requests[-1]
t = texts()
assert 'Personal story' in t and any(x.startswith('Personal · Unread') for x in t), t
assert 'x2_l_unread_0_1.txt' in g.store
tap(100, 56 + 26 + 5); g.flush()                       # its article: cached under the account
assert '/api/article/900' in requests[-1] and 'acct=2' in requests[-1], requests[-1]
assert 'x2_a900.txt' in g.store
key('back'); key('back')                               # article -> list -> account menu
assert 'RSS · Personal' in texts()
key('back')                                            # account menu -> account folders
t = texts()
assert 'Work' in t and 'Personal' in t and 'Unread' not in t, t
tap(100, 100 + 10)                                     # Work
g.store['l_unread_0_1.txt'] = None
tap(100, 100 + 10); g.flush()
assert 'acct=1' in requests[-1] and 'Work story' in texts(), (requests[-1], texts())
assert 'Work story' in str(g.store['l_unread_0_1.txt'])   # the first account keeps the old cache names
key('back')
tap(100, 100 + 5 * 70 + 10)                            # Accounts row goes up as well
assert 'Personal' in texts() and 'Unread' not in texts(), texts()
# offline start: the cached account list still gives the folders
L.execute(f"dofile([[{os.path.join(HERE, 'index.lua').replace(os.sep, '/')}]])")
g = L.globals()
responses.clear()
g.pending = L.table()
g.on_load(g.ctx)
g.flush()
t = texts()
assert 'Work' in t and 'Personal' in t, t
assert not any('ERR' in x for x in texts())

# restart: /api is asked at once (it also wakes Wi-Fi); a list opened meanwhile queues behind it;
# a third account added meanwhile shows up in the folders and the saved copy
three = [{'id': '1', 'label': 'Work'}, {'id': '2', 'label': 'Personal'}, {'id': '3', 'label': 'Club'}]
responses['__root__'] = {'title': 'CommaFeed', 'accounts': three}
responses['kind=unread&page=1&n=12&acct=1'] = {'title': 'Unread', 'page': 1, 'has_more': False, 'accounts': three,
    'items': [{'id': '800', 'title': 'Work story', 'feed': 'News', 'date': '', 'read': False, 'excerpt': 'w'}]}
def restart():
    L.execute(f"dofile([[{os.path.join(HERE, 'index.lua').replace(os.sep, '/')}]])")
    gl = L.globals()
    gl.pending = L.table()
    gl.on_load(gl.ctx)
    return gl
n_req = len(requests)
g = restart()
assert len(requests) == n_req + 1 and requests[-1].split('?')[0].endswith('/api'), requests[n_req:]
assert 'connecting Wi-Fi...' in texts(), texts()
tap(100, 100 + 10); tap(100, 100 + 10); g.flush()                # Work -> Unread, after /api
assert len(requests) == n_req + 2 and 'kind=unread' in requests[-1], requests[n_req:]
assert 'Work story' in texts()
key('back'); key('back')
t = texts()
assert 'Club' in t and 'Personal' in t, t
assert 'Club' in str(g.store['accounts.txt'])
L.execute("fake_ms = fake_ms + 5000"); texts()
assert len(requests) == n_req + 2, requests[n_req:]             # no further /api
# an older Worker sends lists without accounts: the /api asked at start is enough, no second one
del responses['kind=unread&page=1&n=12&acct=1']['accounts']
n_req = len(requests)
g = restart()
tap(100, 100 + 10); tap(100, 100 + 10); g.flush()
assert len(requests) == n_req + 2 and requests[-2].split('?')[0].endswith('/api') and 'kind=unread' in requests[-1], requests[n_req:]
assert 'Work story' in texts()
# Wi-Fi: keep_wifi takes milliseconds; kept for minutes while in use, released when left
kept = [g.kept[i] for i in range(1, len(g.kept) + 1)]
assert kept and all(k >= 60000 for k in kept), kept
L.execute("on_leave()")
assert g.kept[len(g.kept)] < 1000, g.kept[len(g.kept)]
# the article's link as a QR code at the end, under a rule; if the QR fails, just the address
responses['/api/article/800'] = {'id': '800', 'title': 'Work story', 'feed': 'News', 'date': '',
    'url': 'https://www.example.com/a/b', 'text': 'Short text.'}
n_img = g.images_drawn
tap(100, 56 + 26 + 5); g.flush()
t = texts()
assert 'Short text.' in t and 'Source:' in t and 'example.com/a/b' in t, t
assert g.qr_made == 'https://www.example.com/a/b' and g.images_drawn > n_img, (g.qr_made, g.images_drawn)
tap(50, 20)
g.qr_fail = True
n_img = g.images_drawn
tap(100, 56 + 26 + 5); g.flush()                        # opening an article releases the last QR
assert (g.qr_released or 0) >= 1
t = texts()
assert 'Short text.' in t and 'Source:' in t and 'example.com/a/b' in t and not any('ERR' in x for x in t), t
assert g.images_drawn == n_img
g.qr_fail = False
tap(50, 20)
responses['/api/article/800'] = {'id': '800', 'title': 'Work story', 'feed': 'News', 'date': '', 'text': 'No link.'}
g.store['a800.txt'] = None
tap(100, 56 + 26 + 5); g.flush()
t = texts()
assert 'No link.' in t and 'Source:' not in t, t
# a long address wraps into lines that fit (stub font: 10 px per byte, 456 px -> 45 bytes), at a / or .
tap(50, 20)
slug = 'techspheredynamics.com/2026/10/23/evaluate-business-central-mcp-answers'
responses['/api/article/800'] = {'id': '800', 'title': 'Work story', 'feed': 'News', 'date': '', 'text': 'Long link.', 'url': 'https://' + slug}
g.store['a800.txt'] = None
tap(100, 56 + 26 + 5); g.flush()
t = texts()
i = t.index('Source:')
addr_lines = [x for x in t[i + 1:] if x and x[0].isalnum()][:3]
assert ''.join(addr_lines) == slug and len(addr_lines) == 2 and all(len(x) <= 45 for x in addr_lines), addr_lines
assert addr_lines[0][-1] in '/.-', addr_lines
# a very long one stops after three lines with "~"
tap(50, 20)
responses['/api/article/800']['url'] = 'https://' + slug + '/' + 'x' * 200
g.store['a800.txt'] = None
tap(100, 56 + 26 + 5); g.flush()
t = texts()
i = t.index('Source:')
addr_lines = [x for x in t[i + 1:] if x and x[0].isalnum()][:4]
assert len(addr_lines) == 3 and addr_lines[2].endswith('~') and all(len(x) <= 45 for x in addr_lines), addr_lines
# offline copies: listed as they are opened; Settings deletes them all after a second tap
idx = str(g.store['cache_idx.txt']).split(chr(10))
assert 'a103.txt' in idx and idx[-1] == 'a800.txt', idx
g = restart(); g.flush()
tap_label('Settings')
CACHE_ROW = 56 + 20 + 6 * 96 + 24 + 10
n = len(idx)
assert any(x.startswith('%d ' % n) for x in texts()), texts()
tap(100, CACHE_ROW)
assert 'Tap again to delete %d' % n in texts() and g.store['a103.txt'] is not None
tap(100, CACHE_ROW)
assert any(x.startswith('0 ') for x in texts()) and 'offline copies deleted' in texts(), texts()
assert g.store['a103.txt'] is None and g.store['x2_a900.txt'] is None and str(g.store['cache_idx.txt']) == ''
assert g.store['l_unread_0_1.txt'] is not None and g.store['config.txt'] is not None
print('rss29 tests passed')
