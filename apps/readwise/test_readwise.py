"""Offline test of the API 2.18 Readwise Reader app under Lua 5.4 (lupa): a method-style ctx stub
whose net:request answers like Reader's API v3 (reads, and changes PATCHed to its update
endpoint), and records every call (method, URL, body, headers).

  python -I apps/readwise/test_readwise.py
"""
import base64, json, os, re
from urllib.parse import urlparse, parse_qs
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
import subprocess as _sp, sys as _sys                          # src/ -> index.lua first
_sp.run([_sys.executable, '-I', os.path.join(HERE, 'bundle.py')], check=True, stdout=_sp.DEVNULL)
L = lua54.LuaRuntime(unpack_returned_tuples=True)

calls = []          # (method, url, body, headers)
state = {'token_ok': True, 'throttle': False}


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


def answer(method, url, body, headers):
    m = re.fullmatch(r'https://readwise\.io/api/v3/update/(\w+)/', url)
    if m:                                                 # Reader's own update endpoint (API 2.18)
        if method != 'PATCH' or headers.get('Authorization') != 'Token rwTOKEN123456':
            return 405, '{"detail":"Method not allowed."}'
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
            if q['id'] not in docs:
                return 200, json.dumps({'count': 0, 'nextPageCursor': None, 'results': []})
            d = dict(docs[q['id']])
            html = d.pop('_html', ARTICLE)
            d['html_content'] = html if q.get('withHtmlContent') == 'true' else None
            return 200, json.dumps({'count': 1, 'nextPageCursor': None, 'results': [d]}, ensure_ascii=d.pop('_ascii', False))
        n = int(q['limit'])                                # the rows that fit: 12, or 6 in landscape
        if q.get('tag') == 'Big Ideas':
            return 200, json.dumps({'count': 1, 'nextPageCursor': None, 'results': tagged})
        rows = {'new': inbox, 'later': later, 'archive': archive}.get(q.get('location'), [])
        start = n + 1 if q.get('pageCursor') == 'cur2' else 0
        if q.get('pageCursor') not in (None, 'cur2'):
            return 400, '{"detail":"bad cursor"}'
        page = [{k: v for k, v in d.items() if not k.startswith('_')} for d in rows[start:start + n + 1]]
        return 200, json.dumps({'count': len(rows), 'nextPageCursor': 'cur2' if start == 0 and len(rows) > n + 1 else None, 'results': page})
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
files, extends, saved_sizes = {}, 0, {}       -- AppFiles (API 2.18 save), budget:extend calls
fake_ms = 1000
local function font(name, lh) local f = M({ measure = function(s) return #s * 10 end }); f.name = name; f.line_height = lh; return f end
ctx = {
  invalidate = function() end, state = {}, api = { major = 2, minor = 18 },
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
    local res = { ok = true, status = st, body = body, headers = {}, bytes = #body }
    if opts.save and st >= 200 and st < 300 then                 -- the body goes to the file, whole
      assert(opts.save.to == 'files', 'save to files expected')
      files[opts.save.name] = body; saved_sizes[#saved_sizes + 1] = #body; res.body = ''; res.saved = true
    elseif #body > 131072 then res.body = body:sub(1, 131072); res.err = 'limit_exceeded' end
    pending[#pending + 1] = function() fn(ctx, res) end
    return M({ cancel = function() end })
  end }),
  json = M({ decode = function(s) return py_json_decode(s) end }),
  budget = M({ extend = function() extends = extends + 1; return true end }),
  files = M({ path = '/AppFiles/readwise',
              exists = function(n) return files[n] ~= nil end,
              read = function(n, off, len) local s = files[n]; if not s then return nil, 'not_found' end
                                           off = off or 0; return s:sub(off + 1, len and off + len or #s) end,
              write = function(n, d) files[n] = d; return true end,
              remove = function(n) files[n] = nil; return true end,
              list = function() local t = {} for k, v in pairs(files) do t[#t + 1] = { name = k, size = #v } end return t end }),
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
    return [c for c in calls if '/api/v3/update/' in c[1]]
def page_ind():
    for x in texts():
        m = re.fullmatch(r'(\d+)/(\d+)', x)
        if m: return int(m.group(1)), int(m.group(2))
    raise AssertionError(texts())

# no token: Settings; the token typed in is saved; Back asks the tag list (Wi-Fi comes up with it)
g.on_load(g.ctx)
t = texts()
assert 'Access token (readwise.io/access_token)' in t and 'config.txt over USB.' in t, t
tap(*SET(0)); type_in('  rwTOKEN123456  ')
assert g.store['config.txt'] == 'token=rwTOKEN123456\nsize=default\nimages=0\nscreen=portrait', g.store['config.txt']
assert 'rwTO...3456' in texts()
tap(*BAR(0))
assert calls[-1][:2] == ('GET', 'https://readwise.io/api/v3/tags/') and calls[-1][3]['Authorization'] == 'Token rwTOKEN123456', calls[-1]
g.flush()
t = texts()
assert all(x in t for x in ('Readwise Reader', 'Inbox', 'Later', 'Shortlist', 'Archive', 'Feed', 'Tags', 'Settings')), t
assert 'changes go straight to Readwise' in t, t

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

# preview: summary, tags, the actions
long_press(100, row_y(2))
t = texts()
assert 'Summary of story 2.' in t and 'Tags: alpha, Beta' in t, t
assert all(x in t for x in ('Prev', 'Open', 'Archive', 'Next', 'Later', 'Tags')), t
key('back')

# opening reads and keeps the position (and marks it seen)
tap(100, row_y(1)); g.flush()
assert [c[1] for c in calls[-2:]] == ['https://readwise.io/api/v3/list/?id=01doc0001&withHtmlContent=true', 'https://readwise.io/api/v3/update/01doc0001/'], calls[-2:]
now, total = page_ind()
assert total >= 4 and now == int(0.4 * total) + 1, (now, total)            # Reader's own progress
for _ in range(now - 1): key('left')
t = texts()
assert 'Site 1 Ann Writer 2026-10-28' in t and 'A heading' in t and not any('hidden' in x for x in t), t
assert [json.loads(w[2]) for w in writes()] == [{'seen': True}] and writes()[-1][1].endswith('/01doc0001/'), writes()
for _ in range(now): key('right')                                           # one page past where it opened
key('back')
assert str(g.store['pos.txt']).startswith('01doc0001 0.'), g.store['pos.txt']
pos_page = now + 1
tap(100, row_y(1)); g.flush()                                               # from the card, at the page kept
assert 'cached' in texts() and page_ind()[0] == pos_page, (page_ind(), pos_page)
key('back')

key('back'); g.flush()
assert 'changes go straight to Readwise' in texts()

# Archive from the preview: PATCHed to Reader, the preview moves on, the row goes
tap(*MENU(0)); g.flush()
long_press(100, row_y(0))
tap_label('Archive'); g.flush()
m, url, body, h = writes()[-1]
assert (m, url) == ('PATCH', 'https://readwise.io/api/v3/update/01doc0000/') and json.loads(body) == {'location': 'archive'}, writes()[-1]
assert h['Authorization'] == 'Token rwTOKEN123456' and h['Content-Type'] == 'application/json', h
assert 'Summary of story 1.' in texts(), texts()
# Later, from the second row
tap_label('Later'); g.flush()
assert json.loads(writes()[-1][2]) == {'location': 'later'} and writes()[-1][1].endswith('/01doc0001/')
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
assert json.loads(writes()[-1][2]) == {'seen': True} and writes()[-1][1].endswith('/01doc0003/') and len(writes()) == n + 1, writes()[n:]
for _ in range(page_ind()[1]): key('right')
t = texts()
assert 'Source:' in t and 'Archive' in t and 'Later' in t and 'Tags' in t, t
tap_label('Archive'); g.flush()
assert json.loads(writes()[-1][2]) == {'location': 'archive'} and writes()[-1][1].endswith('/01doc0003/')
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

# big documents (an EPUB is a whole book, a PDF too): the answer is saved to a file (it may be
# megabytes; a body is cut at 128 KB) and read in parts of about 45 KB of HTML, each ending after a
# closing tag, with \uXXXX escapes, surrogate pairs and escapes across the 32 KB reads. Next on
# the last page (or the Next part button) opens the next part from the kept file, Prev on the
# first page the end of the one before; the part is kept with the position; a missing file is
# fetched again. A PDF without text shows its summary.
para = lambda k: f'<p>Para {k}: Ünïcödé “quoted” \\ back 😀 tab\tend{k}.</p>\n'
N_PARAS = 30000
BOOK = ''.join(para(k) for k in range(N_PARAS))                         # about 2 MB as JSON
book = doc(70, title='A long book', category='epub', location='later', _html=BOOK, _ascii=True)
pdf = doc(71, title='A scanned PDF', category='pdf', location='later', _html=None, summary='What the PDF is about.')
gone = doc(72, title='Deleted meanwhile', location='later')
later.extend([book, pdf, gone])
docs.update({d['id']: d for d in (book, pdf)})                          # 72 is not in Reader any more
for k in list(g.store.keys()):
    if str(k).startswith('l_later'): g.store[k] = None
copy_text = lambda name: str(g.store[name]).split('\n', 7)[7]
copy_part = lambda name: str(g.store[name]).split('\n', 7)[5]
def paras(text):
    # the paragraphs of a part, each checked whole
    found = [int(m) for m in __import__('re').findall(r'Para (\d+): ', text)]
    for k in found:
        assert f'Para {k}: Ünïcödé “quoted” \\ back 😀 tab end{k}.' in text, (k, text[:300])
    return found
key('back'); tap(*MENU(1)); g.flush()
assert 'A long book' in texts(), texts()
before, n_calls = int(g.extends), len(calls)
tap(100, row_y(1)); g.flush()
assert calls[-1][1] == 'https://readwise.io/api/v3/update/01doc0070/' and '01doc0070&withHtmlContent=true' in calls[-2][1], calls[-2:]
assert int(g.saved_sizes[len(g.saved_sizes)]) > 1500000
assert g.files['doc_01doc0070.json'] is not None and str(g.store['books.txt']) == '01doc0070', g.store['books.txt']
assert int(g.extends) > before                                         # the long work got its time
first = paras(copy_text('a01doc0070.txt'))
assert first == list(range(len(first))) and 300 < len(first) < 900, (len(first), first[:3])
assert copy_part('a01doc0070.txt').startswith('1 ') and '\ufffd' not in copy_text('a01doc0070.txt')
assert any('part 1' in x for x in texts()), texts()
seen, part, downloads = list(first), 1, len([c for c in calls if 'withHtmlContent' in c[1]])
while True:                                             # Next past each part's last page: the next part
    now, total = page_ind()
    for _ in range(total - now): key('right')
    t = texts()
    if part == 1: assert 'Next part (2)  >' in t, t
    if 'Next part (%d)  >' % (part + 1) not in t:
        break
    key('right'); g.flush()
    part += 1
    name = f'a01doc0070p{part}.txt'
    got = paras(copy_text(name))
    assert got and got[0] == seen[-1] + 1, (part, seen[-1], got[:2])   # nothing lost, nothing twice
    seen += got
    part_first = got[0]
    assert page_ind()[0] == 1 and any(f'part {part}' in x for x in texts()), texts()
assert seen == list(range(N_PARAS)) and part > 30, (part, len(seen))
assert len([c for c in calls if 'withHtmlContent' in c[1]]) == downloads    # all from the kept file
assert copy_part(f'a01doc0070p{part}.txt') == f'{part} -'                  # the last part
# Prev on the first page of a part: the end of the part before
for _ in range(page_ind()[0] - 1): key('left')
key('left'); g.flush()
assert page_ind()[0] == page_ind()[1] and 'Next part (%d)  >' % part in texts(), texts()
key('right'); g.flush()                                                     # and on again
assert page_ind()[0] == 1 and any(f'part {part}' in x for x in texts())
key('right')
key('back')
assert str(g.store['pos.txt']).splitlines()[-1].startswith('01doc0070 0.') and str(g.store['pos.txt']).endswith(f' {part}'), g.store['pos.txt']
# opened again: the part read last, at its page
tap(100, row_y(1)); g.flush()
on_page = [int(m) for x in texts() for m in __import__('re').findall(r'^Para (\d+):', x)]
assert page_ind()[0] == 2 and on_page and min(on_page) >= part_first, (page_ind(), on_page[:3])
key('back')
# the kept file gone (and the offline copy of part 3): fetched again, the same part
g.files['doc_01doc0070.json'] = None
g.store['a01doc0070p3.txt'] = None
old3 = None
g.store['pos.txt'] = str(g.store['pos.txt']).rsplit('\n', 1)[0] + '\n01doc0070 0.0000 3'
tap(100, row_y(1)); g.flush()
assert len([c for c in calls if 'withHtmlContent' in c[1]]) == downloads + 1
got = paras(copy_text('a01doc0070p3.txt'))
assert got and any('part 3' in x for x in texts()), texts()
key('back')
tap(100, row_y(2)); g.flush()
text = copy_text('a01doc0071.txt')
assert text == 'What the PDF is about.\n\n(Readwise sends no text for this PDF. Open it in Readwise Reader.)', text
assert 'What the PDF is about.' in texts() and g.files['doc_01doc0071.json'] is None, texts()
key('back')
tap(100, row_y(3)); g.flush()
assert any('not found in Reader' in x for x in texts()) and g.store['a01doc0072.txt'] is None, texts()
key('back')
# deleting the offline copies (Settings, two taps) removes the kept files too, also a stray one
g.files['doc_01docstray.json'] = '{"a": 1}'
assert g.files['doc_01doc0070.json'] is not None
key('back'); key('back'); tap(*MENU(6))
x, y = recs()[[v for v in texts() if v.startswith('Articles saved offline')][0]]
tap(x + 5, y + 30); tap(x + 5, y + 30)
assert g.files['doc_01doc0070.json'] is None and g.files['doc_01docstray.json'] is None and str(g.store['books.txt']) == ''
assert not [k for k in g.store.keys() if str(k).startswith('a01doc') and g.store[k] is not None]
key('back'); tap(*MENU(1)); g.flush()
tap(100, row_y(1)); g.flush()                                               # opens again: fetched anew
assert g.files['doc_01doc0070.json'] is not None
key('back')
# archiving the book removes every part's offline copy and its file
long_press(100, row_y(1)); tap_label('Archive'); g.flush()
assert not [k for k in g.store.keys() if str(k).startswith('a01doc0070') and g.store[k] is not None]
assert g.files['doc_01doc0070.json'] is None and str(g.store['books.txt']) == ''
key('back')
del later[1:]
for k in list(g.store.keys()):
    if str(k).startswith('l_later'): g.store[k] = None

# errors: Reader's rate limit, a rejected token
key('back'); tap(*MENU(1)); g.flush()
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
g.store['config.txt'] = 'token=rwTOKEN123456\r\nhost=rss.example.workers.dev\r\nsize=default\r\n'   # an old host= line is ignored
L.execute(f"dofile([[{SRC}]])")
g = L.globals()
g.pending = L.table()
g.on_load(g.ctx); g.flush()
assert calls[-1][3]['Authorization'] == 'Token rwTOKEN123456', calls[-1]
assert 'changes go straight to Readwise' in texts() and not any('ERR' in x for x in texts())

# Settings: the token, text size, images, offline copies; no Worker fields any more
key('back'); tap(*MENU(6))
t = texts()
assert 'Access token (readwise.io/access_token)' in t and 'Text size (articles and previews)' in t, t
assert not any('Worker' in x for x in t), t
key('back')
# landscape (API 2.18): Settings offers Screen; turning gives 800 x 480, two menu columns, 6 rows
# a list page (Reader is asked for 6), and an open article laid out again at the same place
L.execute("""
ctx.screen = { width = 480, height = 800, orientation = 'portrait' }
function ctx.screen.set_orientation(self, o)
  assert(self == ctx.screen)
  if o == 'landscape' then self.width, self.height, self.orientation = 800, 480, 'landscape'
  else self.width, self.height, self.orientation = 480, 800, 'portrait' end
  return true
end
""")
L.execute(f"dofile([[{SRC}]])")
g = L.globals()
g.pending = L.table()
g.on_load(g.ctx); g.flush()
key('back') if 'Settings' not in texts() else None
tap(*MENU(6))
assert 'Screen (turns the app)' in texts() and 'portrait   (tap to change)' in texts(), texts()
x, y = recs()['portrait   (tap to change)']
tap(x + 5, y + 5)
assert 'screen=landscape' in str(g.store['config.txt']) and int(g.ctx.screen.width) == 800
t = texts()
assert 'landscape   (tap to change)' in t and 'no Worker is needed.' not in t, t      # two columns, no note
def overflow():
    """texts that run past the right edge, or into the next column (10 px a character here)"""
    return [(str(r.s), int(r.x)) for r in draw().values() if int(r.x) + 10 * len(str(r.s)) > (400 if int(r.x) < 400 else 800) - 8]
assert not overflow(), overflow()
key('back')
# the menu in two columns: Later is the second cell of the first row
mx, my = recs()['Later']
assert mx > 400 and my < 200, (mx, my)
tap(mx + 5, my + 5); g.flush()
assert 'limit=6&location=later' in calls[-1][1], calls[-1]
key('back')
x, y = recs()['Inbox']; tap(x + 5, y + 5); g.flush()
assert calls[-1][1].startswith('https://readwise.io/api/v3/list/?limit=6&location=new'), calls[-1]
t = texts()
assert 'Story 5' in t and 'Story 6' not in t and any('1-6 / ' in v for v in t), t
assert not [(str(r.s), int(r.x)) for r in draw().values() if int(r.x) + 10 * len(str(r.s)) > 800], texts()
tap(100, TOP + 26 + 2 * 58 + 5); g.flush()                                  # row 3: an article
now, total = page_ind()
key('right'); key('right')
share = (page_ind()[0] - 1) / page_ind()[1]
# back to portrait from Settings: the article is laid out again at about the same share
key('back'); key('back'); tap_label('Settings')
x, y = recs()['landscape   (tap to change)']; tap(x + 5, y + 5)
assert int(g.ctx.screen.width) == 480 and 'screen=portrait' in str(g.store['config.txt'])
assert not any('ERR' in v for v in texts()), texts()
# a restart in landscape turns the app in on_load
g.store['config.txt'] = str(g.store['config.txt']).replace('screen=portrait', 'screen=landscape')
L.execute(f"dofile([[{SRC}]])")
g = L.globals()
g.pending = L.table()
g.on_load(g.ctx); g.flush()
assert int(g.ctx.screen.width) == 800 and not any('ERR' in v for v in texts()), texts()

# the optional AI questions (tools/gamekit/ai.lua, aiui.lua)
_sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
import ai_reader_test  # noqa: E402
ai_reader_test.run(globals(), 'Inbox', 'readwise')
print('readwise tests passed')
