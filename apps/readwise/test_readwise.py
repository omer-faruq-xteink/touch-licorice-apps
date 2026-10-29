"""Offline test of the API 2.9 Readwise Reader app under Lua 5.4 (lupa): a method-style ctx stub
whose net:request answers like Reader's API v3 (reads) and the Worker's relay (changes), and
records every call (method, URL, body, headers).

  python -I apps/readwise/test_readwise.py
"""
import base64, json, os, re
from urllib.parse import urlparse, parse_qs
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
L = lua54.LuaRuntime(unpack_returned_tuples=True)

calls = []          # (method, url, body, headers)
state = {'token_ok': True, 'worker': 'ok', 'throttle': False}


def doc(i, **kw):
    d = {'id': f'01doc{i:04d}', 'url': f'https://read.readwise.io/read/01doc{i:04d}', 'title': f'Story {i}',
         'author': 'Ann Writer', 'source_url': f'https://www.site{i % 3}.com/post/{i}', 'category': 'article',
         'location': 'new', 'tags': {}, 'site_name': f'Site {i % 3}', 'summary': f'Summary of story {i}.',
         'reading_progress': 0, 'first_opened_at': None, 'saved_at': '2026-10-28T11:00:13.194000+00:00',
         'parent_id': None, 'html_content': None}
    d.update(kw)
    return d


LONG = ''.join(f'<p>Paragraph {k} with some words\n that wrap   across source lines and say a little more.</p>' for k in range(60))
ARTICLE = ('<div><h2>A heading</h2><p>It&rsquo;s &ldquo;quoted&rdquo; &amp; fine.</p><script>var hidden = 1;</script>'
           '<ul><li>first item</li></ul>' + LONG + '</div>')
inbox = [doc(i, reading_progress=0.4 if i == 1 else 0,
             tags={'alpha': {'name': 'alpha', 'type': 'manual'}, 'Beta': {'name': 'Beta', 'type': 'manual'}} if i == 2 else {})
         for i in range(20)]
inbox.insert(3, doc(900, category='highlight', parent_id='01doc0003', title='a highlight'))
docs = {d['id']: d for d in inbox}
later = [doc(40, location='later', title='Later one')]
archive = [doc(50, location='archive', title='Archived one')]
tagged = [doc(60, title='Tagged one', location='later', tags={'Big Ideas': {'name': 'Big Ideas'}})]
for d in later + archive + tagged: docs[d['id']] = d
WORKER = 'https://rss.example.workers.dev'


def answer(method, url, body, headers):
    if url.startswith(WORKER):
        if state['worker'] == 'old':
            return 405, 'Method not allowed'
        if headers.get('Authorization') != 'Basic ' + base64.b64encode(b'me:pw').decode():
            return 401, ''
        m = re.fullmatch(WORKER + r'/readwise/update/(\w+)', url)
        if method != 'POST' or not m or headers.get('X-Readwise-Token') != 'rwTOKEN123456':
            return 400, '{"error":"bad relay call"}'
        json.loads(body)
        return 200, json.dumps({'id': m.group(1), 'url': 'https://read.readwise.io/read/' + m.group(1)})
    if url.startswith('https://images.weserv.nl/'):
        return 200, b'\xff\xd8' + b'x' * 50
    if headers.get('Authorization') != 'Token rwTOKEN123456' or not state['token_ok']:
        return 401, '{"detail":"Invalid token."}'
    if state['throttle']:
        return 429, '{"detail":"Request was throttled."}'
    u = urlparse(url)
    q = {k: v[0] for k, v in parse_qs(u.query).items()}
    if u.path == '/api/v3/tags/':
        return 200, json.dumps({'count': 2, 'nextPageCursor': None, 'results': [{'key': 'zeta', 'name': 'zeta'}, {'key': 'Big Ideas', 'name': 'Big Ideas'}]})
    if u.path == '/api/v3/list/':
        if 'id' in q:
            d = dict(docs[q['id']])
            d['html_content'] = ARTICLE if q.get('withHtmlContent') == 'true' else None
            return 200, json.dumps({'count': 1, 'nextPageCursor': None, 'results': [d]})
        assert q['limit'] == '12', q
        if q.get('tag') == 'Big Ideas':
            return 200, json.dumps({'count': 1, 'nextPageCursor': None, 'results': tagged})
        rows = {'new': inbox, 'later': later, 'archive': archive}.get(q.get('location'), [])
        start = 13 if q.get('pageCursor') == 'cur2' else 0
        if q.get('pageCursor') not in (None, 'cur2'):
            return 400, '{"detail":"bad cursor"}'
        page = rows[start:start + 13]
        return 200, json.dumps({'count': len(rows), 'nextPageCursor': 'cur2' if start == 0 and len(rows) > 13 else None, 'results': page})
    return 404, '{"detail":"Not found."}'


def fake_request(method, url, body, headers):
    h = dict(headers.items()) if headers else {}
    calls.append((method, url, body, h))
    return answer(method, url, body, h)


L.globals().py_request = fake_request
L.globals().py_json_decode = lambda s: L.table_from(json.loads(s), recursive=True)
L.globals().py_b64 = lambda s: base64.b64encode(s.encode()).decode()

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
pending, inputs, input_opts = {}, {}, {}
fake_ms = 1000
local function font(name, lh) local f = M({ measure = function(s) return #s * 10 end }); f.name = name; f.line_height = lh; return f end
ctx = {
  invalidate = function() end, state = {},
  storage = M({ write = function(n, d) store[n] = d; return true end, read = function(n) if store[n] then return store[n] end return nil, 'not_found' end,
                   remove = function(n) store[n] = nil; return true end,
                   list = function() local t = {} for k in pairs(store) do t[#t + 1] = k end return t end }),
  fonts = { small = font('small', 20), medium = font('medium', 24), large = font('large', 30) },
  input = M({ text = function(opts, fn) inputs[#inputs + 1] = fn; input_opts[#input_opts + 1] = opts end }),
  base64 = M({ encode = function(s) return py_b64(s) end }),
  clock = M({ millis = function() return fake_ms end }),
  qr = M({ encode = function(t) return setmetatable({}, { __index = { width = 33, height = 33, release = function() end } }) end }),
  net = M({ keep_wifi = function() end, request = function(opts, fn)
    local st, body = py_request(opts.method, opts.url, opts.body, opts.headers)
    pending[#pending + 1] = function() fn(ctx, { status = st, body = body, headers = {} }) end
    return M({ cancel = function() end })
  end }),
  json = M({ decode = function(s) return py_json_decode(s) end }),
  capabilities = { image_decode = true },
  image = M({ decode = function(b) return setmetatable({}, { __index = { width = 456, height = 304, release = function() end } }) end }),
}
function flush() for _ = 1, 50 do local p = pending; pending = {}; if #p == 0 then return end; for _, f in ipairs(p) do f() end end end
''')
SRC = os.path.join(HERE, 'index.lua').replace(os.sep, '/')
L.execute(f"dofile([[{SRC}]])")
g = L.globals()
tap = L.eval("function(x, y) on_input(ctx, {type='pointer', phase='down', x=x, y=y}); on_input(ctx, {type='pointer', phase='up', gesture='tap', x=x, y=y}) end")
long_press = L.eval("function(x, y) on_input(ctx, {type='pointer', phase='up', gesture='long', x=x, y=y}) end")
key = L.eval("function(k) fake_ms = fake_ms + 300; on_input(ctx, {type='key', key=k}) end")
draw = L.eval("function() drawn = {}; on_draw(ctx, gg); return drawn end")
texts = lambda: [str(v.s) for v in draw().values()]
def recs():
    return {str(r.s): (int(r.x), int(r.y)) for r in draw().values()}
def tap_label(label):
    x, y = recs()[label]
    tap(x + 5, y + 5)
TOP = 56
row_y = lambda i: TOP + 26 + i * 58 + 5
BAR = lambda i: (4 + i * 118 + 10, 20)
MENU = lambda i: (100, 100 + i * 70 + 10)
SET = lambda i: (100, TOP + 20 + i * 96 + 24 + 10)
def type_in(value):
    g.inputs[len(g.inputs)](g.ctx, value)
def writes():
    return [c for c in calls if c[1].startswith(WORKER)]
def page_ind():
    for x in texts():
        m = re.fullmatch(r'(\d+)/(\d+)', x)
        if m: return int(m.group(1)), int(m.group(2))
    raise AssertionError(texts())

# no token: Settings; the token typed in is saved; Back asks the tag list (Wi-Fi comes up with it)
g.on_load(g.ctx)
t = texts()
assert 'Access token (readwise.io/access_token)' in t and 'the app only reads.' in t, t
tap(*SET(0)); type_in('  rwTOKEN123456  ')
assert g.store['config.txt'] == 'token=rwTOKEN123456\nhost=\nauth=\nsize=default\nimages=0', g.store['config.txt']
assert 'rwTO...3456' in texts()
tap(*BAR(0))
assert calls[-1][:2] == ('GET', 'https://readwise.io/api/v3/tags/') and calls[-1][3]['Authorization'] == 'Token rwTOKEN123456', calls[-1]
g.flush()
t = texts()
assert all(x in t for x in ('Readwise Reader', 'Inbox', 'Later', 'Shortlist', 'Archive', 'Feed', 'Tags', 'Settings')), t
assert 'read-only: no Worker in Settings' in t, t

# Inbox: location=new, 12 rows (the highlight left out), site, day, progress, unseen
tap(*MENU(0)); g.flush()
assert calls[-1][1] == 'https://readwise.io/api/v3/list/?limit=12&location=new', calls[-1]
t = texts()
assert 'Story 0' in t and 'Story 11' in t and 'a highlight' not in t, t
assert 'Site 1  2026-10-28  40%  · unseen' in t, t
# Next past the last row: the next page by its cursor, appended
tap(*BAR(2)); g.flush()
assert calls[-1][1].endswith('&location=new&pageCursor=cur2'), calls[-1]
t = texts()
assert 'Story 12' in t and 'Story 19' in t and any('13-20 / 20' in x for x in t), t
tap(*BAR(1))

# preview: summary, tags; without a Worker the changes say where to set it and send nothing
long_press(100, row_y(2))
t = texts()
assert 'Summary of story 2.' in t and 'Tags: alpha, Beta' in t, t
assert all(x in t for x in ('Prev', 'Open', 'Archive', 'Next', 'Later', 'Tags')), t
tap_label('Archive')
assert not writes() and 'changes need the Worker: see Settings' in texts(), texts()
tap_label('Tags')
assert not writes() and 'tags need the Worker: see Settings' in texts() and len(g.inputs) == 1
key('back')

# opening without a Worker reads and keeps the position, sends nothing
tap(100, row_y(1)); g.flush()
assert calls[-1][1] == 'https://readwise.io/api/v3/list/?id=01doc0001&withHtmlContent=true', calls[-1]
now, total = page_ind()
assert total >= 4 and now == int(0.4 * total) + 1, (now, total)            # Reader's own progress
for _ in range(now - 1): key('left')
t = texts()
assert 'Site 1 Ann Writer 2026-10-28' in t and 'A heading' in t and not any('hidden' in x for x in t), t
assert not writes()
for _ in range(now): key('right')                                           # one page past where it opened
key('back')
assert str(g.store['pos.txt']).startswith('01doc0001 0.'), g.store['pos.txt']
pos_page = now + 1
tap(100, row_y(1)); g.flush()                                               # from the card, at the page kept
assert 'cached' in texts() and page_ind()[0] == pos_page, (page_ind(), pos_page)
key('back')

# the Worker in Settings: user:password shown masked
key('back'); tap(*MENU(6))
tap(*SET(1)); type_in('rss.example.workers.dev/')
tap(*SET(2)); type_in('me:pw')
assert 'me:****' in texts() and 'rss.example.workers.dev/' in texts(), texts()
assert 'host=rss.example.workers.dev/\nauth=me:pw' in str(g.store['config.txt'])
tap(*BAR(0)); g.flush()
assert 'changes go through your Worker' in texts()

# Archive from the preview: posted to the relay, the preview moves on, the row goes
tap(*MENU(0)); g.flush()
long_press(100, row_y(0))
tap_label('Archive'); g.flush()
m, url, body, h = writes()[-1]
assert (m, url) == ('POST', WORKER + '/readwise/update/01doc0000') and json.loads(body) == {'location': 'archive'}, writes()[-1]
assert h['X-Readwise-Token'] == 'rwTOKEN123456' and h['Authorization'].startswith('Basic ') and h['Content-Length'] == str(len(body)), h
assert 'Summary of story 1.' in texts(), texts()
# Later, from the second row
tap_label('Later'); g.flush()
assert json.loads(writes()[-1][2]) == {'location': 'later'} and writes()[-1][1].endswith('/01doc0001')
assert 'Summary of story 2.' in texts()
key('back')
t = texts()
assert 'Story 0' not in t and 'Story 1' not in t and 'Story 2' in t, t

# Tags: the keyboard opens with the current tags; the answer replaces them
long_press(100, row_y(0))
tap_label('Tags')
assert g.input_opts[len(g.input_opts)].text == 'alpha, Beta', g.input_opts[len(g.input_opts)].text
type_in(' Beta, say "hi" ,new,beta,, ')
g.flush()
assert json.loads(writes()[-1][2]) == {'tags': ['Beta', 'say "hi"', 'new']}, writes()[-1][2]
t = texts()
assert 'Tags: Beta, new, say "hi"' in t and 'tags: Beta, new, say "hi"' in t, t
tap_label('Tags'); type_in('')
g.flush()
assert json.loads(writes()[-1][2]) == {'tags': []} and 'tags removed' in texts()
key('back')

# opening an unseen document marks it seen (after it loaded); the end has the actions
n = len(writes())
tap(100, row_y(1)); g.flush()
assert json.loads(writes()[-1][2]) == {'seen': True} and writes()[-1][1].endswith('/01doc0003') and len(writes()) == n + 1, writes()[n:]
for _ in range(page_ind()[1]): key('right')
t = texts()
assert 'Source:' in t and 'Archive' in t and 'Later' in t and 'Tags' in t, t
tap_label('Archive'); g.flush()
assert json.loads(writes()[-1][2]) == {'location': 'archive'} and writes()[-1][1].endswith('/01doc0003')
t = texts()
assert 'Story 3' not in t and 'Back' in t, t                                 # back on the list, gone
assert 'a01doc0003.txt' not in str(g.store['cache_idx.txt']) and g.store['a01doc0003.txt'] is None
# a document opened again is not marked a second time
n = len(writes())
tap(100, row_y(0)); g.flush(); key('back'); tap(100, row_y(0)); g.flush(); key('back')
assert len(writes()) == n + 1, writes()[n:]

# the archive offers Inbox and Later; Later: the moves take it off the list
key('back'); tap(*MENU(3)); g.flush()
assert calls[-1][1].endswith('location=archive')
long_press(100, row_y(0))
t = texts()
assert 'Inbox' in t and 'Later' in t and 'Archive' not in t, t
tap_label('Inbox'); g.flush()
assert json.loads(writes()[-1][2]) == {'location': 'new'}
assert 'Archived one' not in texts()

# Later offers Archive and Inbox
key('back'); tap(*MENU(1)); g.flush()
long_press(100, row_y(0))
t = texts()
assert 'Archive' in t and 'Inbox' in t and 'Later' not in t, t
key('back')

# Tags: Reader's tag list, then the documents with that tag; a move keeps it in the tag's list
key('back'); tap(*MENU(5)); g.flush()
assert calls[-1][1] == 'https://readwise.io/api/v3/tags/'
t = texts()
assert t.index('Big Ideas') < t.index('zeta'), t
tap(100, row_y(0)); g.flush()
assert calls[-1][1] == 'https://readwise.io/api/v3/list/?limit=12&tag=Big%20Ideas', calls[-1]
long_press(100, row_y(0))
assert 'Tags: Big Ideas' in texts()
tap_label('Archive'); g.flush()
t = texts()
assert 'Tagged one' in t and 'Inbox' in t and 'Archive' not in t, t        # still here, now archived
key('back')
assert g.store['l_tag_Big_20Ideas_1.txt'] is not None

# errors: a wrong Worker password, an old Worker, Reader's rate limit, a rejected token
key('back'); tap(*MENU(1)); g.flush()
long_press(100, row_y(0))
state['worker'] = 'old'
tap_label('Archive'); g.flush()                    # the only row: the preview closes, the row stays
t = texts()
assert any('the Worker has no Readwise relay' in x for x in t) and 'Later one' in t, t
state['worker'] = 'ok'
key('back')
tap(*MENU(6)); tap(*SET(2)); type_in('me:wrong'); tap(*BAR(0)); g.flush()
tap(*MENU(1)); g.flush()
long_press(100, row_y(0)); tap_label('Archive'); g.flush()
assert any('Worker password rejected' in x for x in texts()), texts()
state['throttle'] = True
tap(*BAR(3)); g.flush()
assert any('too many requests' in x for x in texts()), texts()
state['throttle'] = False
state['token_ok'] = False
for k in list(g.store.keys()):
    if str(k).startswith('l_'): g.store[k] = None
key('back'); tap(*MENU(4)); g.flush()
t = texts()
assert 'Could not load this list.' in t and any('token rejected (401)' in x for x in t), t
state['token_ok'] = True

# a config.txt written on Windows (CR LF) still works
g.store['config.txt'] = 'token=rwTOKEN123456\r\nhost=rss.example.workers.dev\r\nauth=me:pw\r\n'
L.execute(f"dofile([[{SRC}]])")
g = L.globals()
g.pending = L.table()
g.on_load(g.ctx); g.flush()
assert calls[-1][3]['Authorization'] == 'Token rwTOKEN123456', calls[-1]
assert 'changes go through your Worker' in texts() and not any('ERR' in x for x in texts())
print('readwise tests passed')
