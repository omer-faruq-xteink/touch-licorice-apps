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


def fake_request(url):
    requests.append(url)
    for key, body in responses.items():
        if key in url:
            return 200, json.dumps(body)
    return 404, '{"error":"not found"}'


L.globals().py_request = fake_request
L.globals().py_json_decode = lambda s: L.table_from(json.loads(s), recursive=True)

L.execute(r'''
drawn, store = {}, {}
local gmt = {}
gmt.__index = function(_, k) return function(_, ...) if k == 'text' then local x, _, s, o = ...; drawn[#drawn + 1] = { s = s, x = x, f = (type(o) == 'table' and type(o.font) == 'table') and o.font.name or '?' } end end end
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
  invalidate = function() end, state = {},
  storage = M({ write = function(n, d) store[n] = d; return true end, read = function(n) if store[n] then return store[n] end return nil, 'not_found' end }),
  fonts = { small = font('small', 20), medium = font('medium', 24), large = font('large', 30) },
  input = M({ text = function(opts, fn) pending[#pending + 1] = fn end }),
  net = M({ keep_wifi = function() end, request = function(opts, fn)
    assert(type(opts.url) == 'string' and type(fn) == 'function')
    last_headers = opts.headers
    local st, body = py_request(opts.url)
    pending[#pending + 1] = function() fn(ctx, { status = st, body = body, headers = {} }) end
    return M({ cancel = function() end })
  end }),
  json = M({ decode = function(s) return py_json_decode(s) end }),
  base64 = M({ encode = function(s) return 'B64(' .. s .. ')' end }),
}
function flush() local p = pending; pending = {}; for _, f in ipairs(p) do f() end end
''')
L.execute(f"dofile([[{os.path.join(HERE, 'index.lua').replace(os.sep, '/')}]])")
g = L.globals()
tap = L.eval("function(x, y) on_input(ctx, {type='pointer', phase='down', x=x, y=y}); on_input(ctx, {type='pointer', phase='up', gesture='tap', x=x, y=y}) end")
key = L.eval("function(k) on_input(ctx, {type='key', key=k}) end")
draw = L.eval("function() drawn = {}; on_draw(ctx, gg); return drawn end")
texts = lambda: [str(v.s) for v in draw().values()]

responses['/api/list?kind=unread'] = {'title': 'Unread', 'page': 1, 'has_more': True,
                                      'items': [{'id': str(100 + i), 'title': f'Article {i}', 'feed': 'Feed', 'date': '2026-10-24 08:00', 'read': False, 'excerpt': 'x'} for i in range(12)]}
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
assert g.store['config.txt'] == 'host=rss.example.workers.dev\ntoken=secret\nauth=\nfull=0', g.store['config.txt']
tap(100, 20)                         # Back
assert 'RSS' in texts()

# Unread list
tap(100, 100 + 10)
g.flush()
assert requests[-1] == 'https://rss.example.workers.dev/k/secret/api/list?kind=unread&page=1&n=12', requests[-1]
t = texts()
assert 'Article 0' in t and 'Article 11' in t, t
# Next page then Prev
tap(4 + 2 * 118 + 10, 20); g.flush()
assert 'page=2' in requests[-1]
key('left'); g.flush()
assert 'page=1' in requests[-1]

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
g.pending = L.table()
tap(50, 20)

# offline: network fails, cached list used
responses.clear()
tap(4 + 3 * 118 + 10, 20); g.flush()  # Reload -> 404 -> cache
t = texts()
assert 'Article 7' in t and any('offline' in x for x in t), t

# feeds screen -> feed list
responses['/api/feeds'] = {'items': [{'id': '10', 'name': 'Feed A', 'unread': 3}]}
responses['/api/list?kind=feed'] = {'title': 'Feed A', 'page': 1, 'has_more': False, 'items': [{'id': '555', 'title': 'Only one', 'feed': 'Feed A', 'date': '', 'read': True, 'excerpt': ''}]}
key('back')
tap(100, 100 + 3 * 70 + 10); g.flush()
assert 'Feed A  (3)' in texts()
tap(100, 56 + 26 + 5); g.flush()
assert 'kind=feed&page=1&n=12&id=10' in requests[-1], requests[-1]
assert 'Only one' in texts()

# basic auth header and full-text switch
g.cfg_set = L.eval("function() end")
L.execute("screen_to_settings = function() end")
key('back'); key('back')
tap(100, 100 + 4 * 70 + 10)           # Settings
tap(100, 56 + 20 + 2 * 96 + 24 + 10)  # auth field
g.pending[1](g.ctx, 'me:pw')
g.pending = L.table()
tap(100, 56 + 20 + 3 * 96 + 24 + 10)  # full toggle
assert g.store['config.txt'].endswith('auth=me:pw\nfull=1')
tap(100, 20)
tap(100, 100 + 10); g.flush()
assert requests[-1].endswith('&full=1') and g.last_headers['Authorization'] == 'Basic B64(me:pw)', (requests[-1], dict(g.last_headers))
assert not any('ERR' in x for x in texts())
print('rss29 tests passed')
