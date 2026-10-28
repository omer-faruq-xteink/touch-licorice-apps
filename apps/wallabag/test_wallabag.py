"""Offline test of the wallabag app under Lua 5.4 (lupa): a method-style ctx stub whose net:request
answers like a wallabag server (OAuth token endpoint and API v2) and records every call.
Covers signing in from Settings (password grant), the refresh grant when the hour is up and the
password again when the refresh token is gone, a 401 that signs in once more, the lists (unread,
starred, archive, a tag) and paging, an article and its position kept on the reader, Star / unstar
and Archive (PATCH), a long article that falls back to the plain-text export, the offline copies.

  python -I apps/wallabag/test_wallabag.py
"""
import json, os
from urllib.parse import parse_qs, urlsplit
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
L = lua54.LuaRuntime(unpack_returned_tuples=True)
BASE = 'https://wb.example.org'
NOW = 1793091600

calls = []                       # (method, url, body, authorization)
state = {'access': 'A1', 'refresh': 'R1', 'refresh_ok': True, 'reject_access': None, 'down': False, 'n': 1}
starred, archived = set(), set()

ARTICLE = ('<h2>A heading</h2><p>It&rsquo;s &ldquo;quoted&rdquo; &amp; fine.</p>' +
           ''.join(f'<p>Paragraph {k} with some words that wrap across lines and say a little more.</p>' for k in range(70)))


def entry(i, **kw):
    e = {'id': 1000 + i, 'title': f'Story {i}', 'url': f'https://www.site{i % 3}.com/post/{i}',
         'domain_name': f'site{i % 3}.com', 'created_at': f'2026-10-{10 + i % 18:02d}T08:00:00+0000',
         'reading_time': 5 + i, 'is_starred': 1 if (1000 + i) in starred else 0,
         'is_archived': 1 if (1000 + i) in archived else 0, 'tags': [{'id': 1, 'label': 'Tech', 'slug': 'tech'}] if i % 2 else []}
    e.update(kw)
    return e


def entries(q):
    page, per = int(q.get('page', ['1'])[0]), int(q.get('perPage', ['30'])[0])
    if 'tags' in q:
        pool = [entry(i) for i in range(1, 31) if i % 2 and q['tags'][0] == 'Tech']
    elif q.get('starred') == ['1']:
        pool = [entry(i) for i in range(1, 31) if 1000 + i in starred]
    elif q.get('archive') == ['1']:
        pool = [entry(i) for i in range(1, 31) if 1000 + i in archived]
    else:
        pool = [entry(i) for i in range(1, 31) if 1000 + i not in archived]
    pages = max(1, (len(pool) + per - 1) // per)
    items = pool[(page - 1) * per: page * per]
    return {'page': page, 'limit': per, 'pages': pages, 'total': len(pool), '_embedded': {'items': items}}


def fake_request(method, url, body, auth):
    calls.append((method, url, body, auth))
    if state['down']:
        return 0, None
    if url.startswith('https://images.weserv.nl/'):
        return 200, b'\xff\xd8' + b'x' * 50
    parts = urlsplit(url)
    path, q = parts.path, parse_qs(parts.query)
    if path == '/oauth/v2/token':
        f = parse_qs(body or '')
        if f.get('client_id') != ['cid'] or f.get('client_secret') != ['sec']:
            return 400, json.dumps({'error': 'invalid_client', 'error_description': 'The client credentials are invalid'})
        if f['grant_type'] == ['password']:
            if f.get('username') != ['tester'] or f.get('password') != ['pw']:
                return 400, json.dumps({'error': 'invalid_grant', 'error_description': 'Invalid username and password combination'})
        elif f['grant_type'] == ['refresh_token']:
            if not state['refresh_ok'] or f.get('refresh_token') != [state['refresh']]:
                return 400, json.dumps({'error': 'invalid_grant', 'error_description': 'Invalid refresh token'})
        state['n'] += 1
        state['access'], state['refresh'] = f"A{state['n']}", f"R{state['n']}"
        return 200, json.dumps({'access_token': state['access'], 'expires_in': 3600, 'token_type': 'bearer',
                                'scope': None, 'refresh_token': state['refresh']})
    if auth != 'Bearer ' + state['access'] or auth == 'Bearer ' + str(state['reject_access']):
        return 401, json.dumps({'error': 'invalid_grant', 'error_description': 'The access token provided has expired.'})
    if path == '/api/tags.json':
        return 200, json.dumps([{'id': 1, 'label': 'Tech', 'slug': 'tech'}, {'id': 2, 'label': 'books', 'slug': 'books'}])
    if path == '/api/entries.json':
        assert q.get('detail') == ['metadata'] and q.get('sort') == ['created'] and q.get('perPage') in (['12'], ['3']), q
        d = entries(q)
        if state.get('old'):                            # ignores detail=metadata: the texts come too
            for e in d['_embedded']['items']: e['content'] = 'y' * 30000
        return 200, json.dumps(d)[:131072]              # the reader keeps the first 128 KB
    if path == '/api/entries/1005.json':                  # too long: the reader gets the first 128 KB
        return 200, ('{"id":1005,"content":"' + 'x' * 140000)[:131072]
    if path == '/api/entries/1005/export.txt':
        return 200, 'Story 5\r\n\r\nFirst line of the long story.\r\nSecond line of it.\r\n'
    if path.startswith('/api/entries/') and path.endswith('.json'):
        i = int(path.split('/')[3].split('.')[0])
        if method == 'PATCH' and state.get('patch_as_get'):
            method = 'GET'                              # the reader's PATCH arrived as a plain read
        if method == 'POST' and parse_qs(body or '').get('_method') == ['PATCH'] and not state.get('no_override'):
            method = 'PATCH'                            # Symfony's method override
        elif method == 'POST':
            return 405, '{"code":405,"message":"No route found: Method Not Allowed (Allow: GET, PATCH, DELETE)"}'
        if method == 'PATCH':
            f = parse_qs(body or '')
            if f.get('archive') == ['1']: archived.add(i)
            if f.get('starred') == ['1']: starred.add(i)
            if f.get('starred') == ['0']: starred.discard(i)
            return 200, json.dumps(entry(i - 1000))
        e = entry(i - 1000)
        e['content'] = ARTICLE
        e['published_by'] = ['Ann Writer']
        return 200, json.dumps(e)
    return 404, '{"code":404,"message":"Not found"}'


L.globals().py_request = fake_request
L.globals().py_json_decode = lambda s: L.table_from(json.loads(s), recursive=True)
L.execute(r'''
drawn, store = {}, {}
local gmt = {}
gmt.__index = function(_, k) return function(_, ...) if k == 'text' then local x, y, s, o = ...; drawn[#drawn + 1] = { s = s, x = x, y = y } end end end
gg = setmetatable({}, gmt)
local function M(t)
  local out = {}
  for k, f in pairs(t) do
    if type(f) == 'function' then out[k] = function(self, ...) assert(self == out, 'method call expected for ' .. k); return f(...) end
    else out[k] = f end
  end
  return out
end
pending, inputs = {}, {}
fake_ms, now_sec = 1000, ''' + str(NOW) + r'''
local function font(name, lh) local f = M({ measure = function(s) return #s * 10 end }); f.name = name; f.line_height = lh; return f end
ctx = {
  invalidate = function() end, state = {},
  storage = M({ write = function(n, d) store[n] = d; return true end, read = function(n) if store[n] then return store[n] end return nil, 'not_found' end,
                remove = function(n) store[n] = nil; return true end,
                list = function() local t = {} for k in pairs(store) do t[#t + 1] = k end return t end }),
  fonts = { small = font('small', 20), medium = font('medium', 24), large = font('large', 30) },
  input = M({ text = function(opts, fn) inputs[#inputs + 1] = fn end }),
  clock = M({ millis = function() return fake_ms end, now = function() return { epoch_sec = now_sec, hour = 11, minute = 0, second = 0 } end }),
  qr = M({ encode = function(t) return setmetatable({}, { __index = { width = 33, height = 33, release = function() end } }) end }),
  net = M({ keep_wifi = function() end, request = function(opts, fn)
    local st, body = py_request(opts.method, opts.url, opts.body, opts.headers and opts.headers['Authorization'])
    pending[#pending + 1] = function() fn(ctx, { status = st, body = body, headers = {} }) end
    return M({ cancel = function() end })
  end }),
  json = M({ decode = function(s) return py_json_decode(s) end }),
}
function flush() for _ = 1, 50 do local p = pending; pending = {}; if #p == 0 then return end; for _, f in ipairs(p) do f() end end end
''')


def load():
    L.execute(f"dofile([[{os.path.join(HERE, 'index.lua').replace(os.sep, '/')}]])")
    gl = L.globals()
    gl.pending = L.table()
    gl.on_load(gl.ctx)
    gl.flush()
    return gl


g = load()
tap = L.eval("function(x, y) on_input(ctx, {type='pointer', phase='down', x=x, y=y}); on_input(ctx, {type='pointer', phase='up', gesture='tap', x=x, y=y}) end")
long_press = L.eval("function(x, y) on_input(ctx, {type='pointer', phase='up', gesture='long', x=x, y=y}) end")
key = L.eval("function(k) fake_ms = fake_ms + 300; on_input(ctx, {type='key', key=k}) end")
draw = L.eval("function() drawn = {}; on_draw(ctx, gg); return drawn end")
typed = lambda s: (L.eval('inputs[#inputs]')(g.ctx, s), g.flush())
texts = lambda: [str(v.s) for v in draw().values()]
def has(s): return any(s in t for t in texts())
def recs(): return {str(r.s): (int(r.x), int(r.y)) for r in draw().values()}
def tap_label(label):
    x, y = recs()[label]
    tap(x + 5, y + 5); g.flush()
TOP = 56
row_y = lambda i: TOP + 26 + i * 58 + 5
BAR = lambda i: (4 + i * 118 + 10, 20)
MENU = lambda i: (100, 100 + i * 70 + 10)
SET = lambda i: (100, TOP + 14 + i * 74 + 22 + 10)
store = g.store

# ---- no settings: the app opens on Settings; typing them in, then Back signs in
t = texts()
assert 'Server (e.g. app.wallabag.it or https://your.server)' in t and 'Client ID' in t and len(calls) == 0, t
for i, v in enumerate(['wb.example.org/', 'cid', 'secret-wrong', 'tester', 'pw']):
    tap(*SET(i)); typed(v)
assert 'host=wb.example.org/\nclient_id=cid\nclient_secret=secret-wrong\nusername=tester\npassword=pw' in store['config.txt'], store['config.txt']
assert '************' not in texts() and '**' in texts()                   # the password is hidden
tap(*BAR(0)); g.flush()                                                # Back: signs in -> refused
assert calls[-1][0] == 'POST' and calls[-1][1] == BASE + '/oauth/v2/token', calls[-1]
assert has('sign-in refused: The client credentials are inva'), texts()
tap(*MENU(4)); tap(*SET(2)); typed('sec')
n = len(calls)
tap(*BAR(0)); g.flush()
m, url, body, _ = calls[n]
assert m == 'POST' and parse_qs(body) == {'grant_type': ['password'], 'client_id': ['cid'], 'client_secret': ['sec'],
                                          'username': ['tester'], 'password': ['pw']}, body
assert calls[n + 1][1] == BASE + '/api/tags.json' and calls[n + 1][3] == 'Bearer A2', calls[n + 1]
assert 'access=A2\nrefresh=R2\nexpires=' + str(NOW + 3600) == store['token.txt'], store['token.txt']
t = texts()
assert 'wallabag' in t and 'tester at wb.example.org' in t and 'Tags' in t, t

# ---- Unread: 12 a page, the next page appended
tap(*MENU(0)); g.flush()
assert calls[-1][1].startswith(BASE + '/api/entries.json?') and 'archive=0' in calls[-1][1] and 'page=1' in calls[-1][1]
t = texts()
assert 'Story 1' in t and 'Story 12' in t and any(s.startswith('site1.com  2026-10-11  6 min') for s in t), t
assert any('1-12 / 12+' in s for s in t), t
tap(*BAR(2)); g.flush()
assert 'page=2' in calls[-1][1] and has('Story 13')
tap(*BAR(1))

# ---- an article: laid out, the position kept on the reader and resumed
tap(100, row_y(0)); g.flush()
assert calls[-1][1] == BASE + '/api/entries/1001.json', calls[-1]
t = texts()
assert 'Story 1' in t and 'site1.com Ann Writer 2026-10-11' in t and 'A heading' in t, t
pages = int([s for s in t if '/' in s and s.split('/')[0].isdigit()][0].split('/')[1])
assert pages >= 4, pages
key('right'); key('right')
key('back')
assert store['pos.txt'].startswith('1001 0.'), store['pos.txt']
assert any('%' in s for s in texts())                         # the row shows how far
n = len(calls)
tap(100, row_y(0)); g.flush()
assert len(calls) == n and has('cached') and has(f'3/{pages}'), texts()   # offline copy, page 3
# Star, then unstar, on the last page
for _ in range(pages): key('right')
tap_label('Star')
assert calls[-1][0] == 'PATCH' and calls[-1][1] == BASE + '/api/entries/1001.json' and calls[-1][2] == 'starred=1', calls[-1]
tap_label('Starred')
assert calls[-1][2] == 'starred=0' and 1001 not in starred
tap_label('Star')
key('back')

# ---- Archive from the preview: PATCH archive=1, the story leaves Unread, its copy goes
assert 'a1001.txt' in store
long_press(100, row_y(0))
assert has('6 min read · Tags: Tech'), texts()
tap_label('Archive')
assert calls[-1][0] == 'PATCH' and calls[-1][2] == 'archive=1' and 1001 in archived
key('back')
assert 'Story 1' not in texts() and store['a1001.txt'] is None
key('back')

# ---- Starred, Archive, Tags
tap(*MENU(1)); g.flush()
assert 'starred=1' in calls[-1][1] and 'Story 1' in texts()
key('back')
tap(*MENU(2)); g.flush()
assert 'archive=1' in calls[-1][1] and 'Story 1' in texts()
key('back')
tap(*MENU(3)); g.flush()
t = texts()
assert t.index('books') < t.index('Tech'), t                  # by name
tap(100, TOP + 26 + 1 * 58 + 5); g.flush()                    # Tech
assert 'tags=Tech' in calls[-1][1] and 'Story 3' in texts() and 'Story 2' not in texts(), calls[-1]
key('back'); key('back')

# ---- a long article: the reader cuts it at 128 KB, so it comes as plain text
tap(*MENU(0)); g.flush()
r = [i for i, s in enumerate(texts()) if s == 'Story 5']
assert r
row = [k for k in range(12) if any(str(v.s) == 'Story 5' and int(v.y) == TOP + 26 + k * 58 for v in draw().values())][0]
tap(100, row_y(row)); g.flush()
assert calls[-2][1] == BASE + '/api/entries/1005.json' and calls[-1][1] == BASE + '/api/entries/1005/export.txt', calls[-2:]
t = texts()
assert 'long article: text only' in t and 'First line of the long story.' in t and 'Second line of it.' in t, t
key('back'); key('back')

# ---- the hour is up: the refresh token; then without it, the password again
L.execute(f'now_sec = {NOW + 4000}')
n = len(calls)
tap(*MENU(1)); g.flush()
assert parse_qs(calls[n][2])['grant_type'] == ['refresh_token'] and parse_qs(calls[n][2])['refresh_token'] == ['R2'], calls[n]
assert calls[n + 1][3] == 'Bearer A3', calls[n + 1]
key('back')
L.execute(f'now_sec = {NOW + 8000}')
state['refresh_ok'] = False
n = len(calls)
tap(*MENU(1)); g.flush()
grants = [parse_qs(c[2])['grant_type'][0] for c in calls[n:] if c[1].endswith('/oauth/v2/token')]
assert grants == ['refresh_token', 'password'] and calls[-1][3] == 'Bearer A4', (grants, calls[-1])
state['refresh_ok'] = True
key('back')
# a 401 with a token that should still be good: signs in once more and asks again
state['reject_access'] = 'A4'
state['access'] = 'other'
n = len(calls)
tap(*MENU(1)); g.flush()
assert [c[1].split('?')[0] for c in calls[n:]] == [BASE + '/api/entries.json', BASE + '/oauth/v2/token', BASE + '/api/entries.json'], calls[n:]
state['reject_access'] = None
key('back')

# ---- without the password a gone refresh token asks for it; offline lists from the cache
store['config.txt'] = store['config.txt'].replace('password=pw', 'password=')
store['token.txt'] = 'access=\nrefresh=\nexpires=0'
g = load()
assert has('sign in again: enter the password in Settings'), texts()
store['config.txt'] = store['config.txt'].replace('password=', 'password=pw')
g = load()
state['down'] = True
tap(*MENU(0)); g.flush()
t = texts()
assert any('(offline)' in s for s in t) and 'Story 2' in t, t
state['down'] = False

# ---- a PATCH that arrives as a read: the server sends the entry unchanged, so the same goes as a
# POST asking to be taken as a PATCH; when that fails too, the line says so and nothing moves
state['patch_as_get'] = True
g = load()
n0 = len(calls)
tap(*MENU(0)); g.flush()
n = len(calls)
long_press(100, row_y(0))
tap_label('Archive')
assert [(c[0], c[2]) for c in calls[n:]] == [('PATCH', 'archive=1'), ('POST', '_method=PATCH&archive=1')], calls[n:]
assert 1002 in archived, (calls[n:], sorted(archived))
key('back')
assert 'Story 2' not in texts()
state['no_override'] = True
n = len(calls)
long_press(100, row_y(0))
tap_label('Archive')
assert [c[0] for c in calls[n:]] == ['PATCH', 'POST'] and 1003 not in archived
key('back')
assert 'Story 3' in texts() and any(s.startswith('archive: sign-in refused') or s.startswith('archive: HTTP 405') for s in texts()), texts()
state['patch_as_get'] = state['no_override'] = False
key('back')

# ---- a server that sends the texts with the list: asked 3 at a time
state['old'] = True
g = load()
n = len(calls)
tap(*MENU(0)); g.flush()
asked = [c[1] for c in calls[n:] if '/api/entries.json' in c[1]]
assert 'perPage=12' in asked[0] and 'perPage=3' in asked[-1], asked
t = texts()
assert 'Story 3' in t and 'Story 5' in t and 'Story 6' not in t and any('1-3 / 3+' in s for s in t), t   # Story 2: archived above
tap(*BAR(2)); g.flush()
assert 'perPage=3&page=2' in calls[-1][1] and 'Story 6' in texts()
state['old'] = False
print('wallabag tests passed')
