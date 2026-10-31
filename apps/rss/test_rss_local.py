"""Offline test of feeds on the reader in the RSS app (lupa): a fake network that answers like real
servers (gzip, 304 Not Modified, redirects, byte ranges, the reader's 128 KB cut), the app's folder
on the card (ctx.files) and its private files. Adding a site by its address and from the list,
reading, read and starred marks, removing a feed, an OPML that becomes a collection, CommaFeed and
collections side by side, full text through the Worker, the screen without one, large feeds.

  python -I apps/rss/test_rss_local.py
"""
import gzip, json, os, subprocess, sys
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
subprocess.run([sys.executable, '-I', os.path.join(HERE, 'bundle.py')], check=True)
L = lua54.LuaRuntime(unpack_returned_tuples=True)
LIMIT = 131072


def rss(title, items, link='https://site.example/'):
    body = ''.join(f'<item><title>{t}</title><link>{l}</link><guid>{g}</guid><pubDate>{d}</pubDate>'
                   f'<description>{s}</description>{c}</item>' for t, l, g, d, s, c in items)
    return f'<?xml version="1.0"?><rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/"><channel><title>{title}</title><link>{link}</link>{body}</channel></rss>'


SITE_FEED = rss('Site News', [
    ('Newest story', 'https://site.example/3', 's3', 'Fri, 30 Oct 2026 12:00:00 GMT', 'Summary three',
     '<content:encoded><![CDATA[<p>Full text of story three with <b>words</b>.</p>]]></content:encoded>'),
    ('Middle story', 'https://site.example/2', 's2', 'Thu, 29 Oct 2026 12:00:00 GMT', 'Summary two only', ''),
    ('Old story', 'https://site.example/1', 's1', 'Wed, 28 Oct 2026 12:00:00 GMT', 'Summary one', ''),
])
BIG_ITEMS = [(f'Big {i}', f'https://big.example/{i}', f'b{i}', f'Fri, 30 Oct 2026 {i % 24:02d}:00:00 GMT', 'S',
              '<content:encoded><![CDATA[<p>' + ('x' * 30000) + '</p>]]></content:encoded>') for i in range(12)]
BIG_FEED = rss('Big Feed', BIG_ITEMS, 'https://big.example/')
CATALOG = {'categories': [{'name': 'Tech', 'feeds': [{'title': 'Tech One', 'url': 'https://tech.example/feed'}]}]}
OPML = '''<?xml version="1.0"?><opml version="2.0"><head><title>Work</title></head><body>
<outline text="Teams"><outline text="Work feed" xmlUrl="https://work.example/rss"/></outline></body></opml>'''

requests = []           # (url, headers)
etag_hits = {}


def respond(url, headers):
    h = {k.lower(): v for k, v in (headers or {}).items()}
    requests.append((url, h))
    gz = 'gzip' in h.get('accept-encoding', '')
    def out(status, body, extra=None, allow_gzip=True):
        hd = dict(extra or {})
        raw = body.encode() if isinstance(body, str) else body
        if gz and allow_gzip and status == 200:
            raw = gzip.compress(raw); hd['content-encoding'] = 'gzip'
        total = len(raw)
        return status, raw[:LIMIT], hd, total
    if url == 'https://example.com':
        return out(301, '', {'location': 'https://www.example.com/'})
    if url == 'https://www.example.com/':
        return out(200, '<html><head><link rel="alternate" type="application/rss+xml" href="/news.xml"></head></html>')
    if url == 'https://www.example.com/news.xml':
        if h.get('if-none-match') == '"v1"':
            etag_hits[url] = etag_hits.get(url, 0) + 1
            return 304, b'', {}, 0
        return out(200, SITE_FEED, {'etag': '"v1"'})
    if url == 'https://tech.example/feed':
        return out(200, rss('Tech One', [('Tech story', 'https://tech.example/a', 't1', 'Fri, 30 Oct 2026 09:00:00 GMT', 'Tech summary', '')]))
    if url == 'https://work.example/rss':
        return out(200, rss('Work feed', [('Work story', 'https://work.example/a', 'w1', 'Fri, 30 Oct 2026 08:00:00 GMT', 'Work summary', '')]))
    if url == 'https://opml.example/list.opml':
        return out(200, OPML)
    if url == 'https://big.example/feed':          # too large even packed; byte ranges allowed
        raw = BIG_FEED.encode()
        rng = h.get('range')
        if rng:
            a, b = (int(x) for x in rng.split('=')[1].split('-'))
            piece = raw[a:b + 1]
            return 206, piece[:LIMIT], {'content-range': f'bytes {a}-{a + len(piece) - 1}/{len(raw)}', 'accept-ranges': 'bytes'}, len(piece)
        if gz:
            packed = os.urandom(200000)          # stands for a gzip answer over 128 KB
            return 200, b'\x1f\x8b' + packed[:LIMIT - 2], {'content-encoding': 'gzip', 'accept-ranges': 'bytes'}, len(packed)
        return 200, raw[:LIMIT], {'accept-ranges': 'bytes'}, len(raw)
    if url.startswith('https://omer-faruq-xteink.github.io/touch-licorice-apps/rss/catalog.json'):
        return 200, json.dumps(CATALOG).encode(), {}, 0
    if '/api/read?' in url:
        return 200, json.dumps({'url': 'x', 'source': 'instaparser', 'text': 'The whole middle story, from the Worker.'}).encode(), {}, 0
    if '/api/feed?' in url and 'id=' in url:
        return 200, json.dumps({'text': 'Big article text from the Worker.'}).encode(), {}, 0
    if '/api/feed?' in url:
        return 200, json.dumps({'title': 'Big Feed', 'items': [{'id': f'b{i}', 'title': f'Big {i}', 'link': f'https://big.example/{i}',
                                'date': 1793000000 + i, 'excerpt': 'from the Worker', 'has_content': True} for i in range(20)]}).encode(), {}, 0
    if url.split('?')[0].endswith('/api'):
        info = {'title': 'CommaFeed', 'accounts': [{'id': '1', 'label': 'Account 1'}]}
        if '//fullonly.' in url:
            info['commafeed'] = False
        return 200, json.dumps(info).encode(), {}, 0
    return 404, b'not found', {}, 0


def py_respond(url, headers):
    st, body, hd, total = respond(url, dict(headers.items()) if headers else {})
    return st, body, L.table_from(hd), total


L.globals().py_respond = py_respond
L.globals().py_gunzip = lambda hexs: gzip.decompress(bytes.fromhex(hexs))
L.globals().py_json_decode = lambda s: L.table_from(json.loads(s), recursive=True)


def lua_to_py(v):
    if L.eval('function(t) return type(t) end')(v) != 'table':
        return v
    keys = list(v.keys())
    if keys and all(isinstance(k, int) for k in keys):
        return [lua_to_py(v[i]) for i in range(1, len(keys) + 1)]
    return {str(k): lua_to_py(v[k]) for k in keys}


L.globals().py_json_encode = lambda t: json.dumps(lua_to_py(t) if L.eval('function(t) return type(t) end')(t) == 'table' else t, ensure_ascii=False)
L.execute(r'''
drawn, store, files = {}, {}, {}
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
pending = {}
local function font(name, lh) local f = M({ measure = function(s) return #s * 10 end }); f.name = name; f.line_height = lh; return f end
ctx = {
  invalidate = function() end, state = {},
  storage = M({ write = function(n, d) assert(#d <= 262144, 'file over 256 KB: ' .. n); store[n] = d; return true end,
                read = function(n) if store[n] then return store[n] end return nil, 'not_found' end,
                remove = function(n) store[n] = nil; return true end,
                list = function() local t = {} for k in pairs(store) do t[#t + 1] = k end table.sort(t) return t end }),
  files = M({ list = function() local t = {} for k, v in pairs(files) do t[#t + 1] = { name = k, size = #v } end return t end,
              read = function(n, off, len) local s = files[n]; if not s then return nil, 'not_found' end; return s:sub((off or 0) + 1, (off or 0) + (len or 65536)) end,
              write = function(n, d) files[n] = d; return true end, remove = function(n) files[n] = nil; return true end,
              exists = function(n) return files[n] ~= nil end }),
  fonts = { small = font('small', 20), medium = font('medium', 24), large = font('large', 30) },
  input = M({ text = function(opts, fn) input_opts = opts; pending[#pending + 1] = fn end }),
  net = M({ keep_wifi = function() end, request = function(opts, fn)
    local st, body, headers, total = py_respond(opts.url, opts.headers)
    pending[#pending + 1] = function() fn(ctx, { ok = true, status = st, body = body, headers = headers, bytes = (total > 0 and total or #body) }) end
    return M({ cancel = function() end })
  end }),
  json = M({ decode = function(s) return py_json_decode(s) end, encode = function(t) return py_json_encode(t) end }),
  zlib = M({ decompress = function(b, o) local ok, r = pcall(py_gunzip, (b:gsub('.', function(c) return string.format('%02x', c:byte()) end))); if ok then return r end return nil, 'io_error' end }),
  capabilities = { image_decode = true },
  image = M({ decode = function(b) return setmetatable({}, { __index = { width = 456, height = 300, release = function() end } }) end }),
  qr = M({ encode = function(t) qr_made = t; return setmetatable({}, { __index = { width = 33, height = 33, release = function() end } }) end }),
  base64 = M({ encode = function(s) return 'B64(' .. s .. ')' end }),
  budget = M({ extend = function() return true end }),
}
ctx.files.path = '/AppFiles/rss'
fake_ms = 1000
fake_now = 1793400000
ctx.clock = M({ millis = function() return fake_ms end, now = function() return { epoch_sec = fake_now, offset_minutes = 180, valid = true } end })
function flush() for _ = 1, 200 do local p = pending; pending = {}; if #p == 0 then return end; for _, f in ipairs(p) do f() end end end
''')
L.execute(f"dofile([[{os.path.join(HERE, 'index.lua').replace(os.sep, '/')}]])")
g = L.globals()
tap = L.eval("function(x, y) on_input(ctx, {type='pointer', phase='down', x=x, y=y}); on_input(ctx, {type='pointer', phase='up', gesture='tap', x=x, y=y}) end")
hold = L.eval("function(x, y) on_input(ctx, {type='pointer', phase='hold', x=x, y=y}); on_input(ctx, {type='pointer', phase='up', gesture='long', x=x, y=y}) end")
key = L.eval("function(k) fake_ms = fake_ms + 300; on_input(ctx, {type='key', key=k}) end")
draw = L.eval("function() drawn = {}; on_draw(ctx, gg); return drawn end")


def texts():
    return [str(v.s) for v in draw().values()]


def recs():
    return {str(r.s): (int(r.x), int(r.y)) for r in draw().values()}


def tap_label(label):
    r = recs()
    assert label in r, (label, list(r))
    x, y = r[label]
    tap(x + 5, y + 5)


def answer_input(text):
    fn = g.pending[len(g.pending)]
    g.pending[len(g.pending)] = None
    fn(g.ctx, text)
    g.flush()


def menu_row(i):
    tap(100, 100 + (i - 1) * 70 + 10)


row_y = lambda i: 56 + 26 + i * 58 + 5

def tap_prefix(prefix):
    r = recs()
    hits = [k for k in r if k.startswith(prefix)]
    assert hits, (prefix, list(r))
    x, y = r[hits[0]]
    tap(x + 5, y + 5)


def hold_prefix(prefix):
    r = recs()
    hits = [k for k in r if k.startswith(prefix)]
    assert hits, (prefix, list(r))
    x, y = r[hits[0]]
    hold(x + 5, y + 5)


# start: nothing set up -> the sources (My feeds, Settings), what to do and a QR code
g.on_load(g.ctx)
t = texts()
assert t[2:] == ['My feeds', 'Settings', 'Open My feeds, then Add feed: a site, or one', 'from the list. CommaFeed, or full text, needs a',
                 'Worker of your own: scan to set one up.'] and 'No feeds yet.' in t, t

# a collection opens on its feeds; Add feed is the first row
tap_label('My feeds')
assert texts()[3:] == ['My feeds', 'Add feed'], texts()

# Add feed -> Type an address: a site that redirects and names its feed
tap_label('Add feed')
assert 'Choose from a list' in texts() and 'Type an address' in texts() and 'Feeds you add go into My feeds.' in texts()
tap_label('Type an address')
answer_input('example.com')
assert 'My feeds.opml' in dict(g.files.items()), list(g.files.keys())
assert 'https://www.example.com/news.xml' in str(g.files['My feeds.opml'])
assert any('added: Site News' in s for s in texts()), texts()
key('back')                                          # Add -> the collection's feeds
t = texts()
assert t[3:5] == ['My feeds', 'Add feed'] and 'Site News' in t, t

# a feed's articles: fetched when it opens, newest first, gzip asked for
tap_label('Site News')
g.flush()
t = texts()
assert t.index('Newest story') < t.index('Middle story') < t.index('Old story'), t
assert any('Site News  2026-10-30 15:00' in s for s in t), t           # the reader's time zone (+3 h)
gz_asked = [h.get('accept-encoding') for u, h in requests if u.endswith('/news.xml')]
assert gz_asked and gz_asked[-1] == 'gzip', gz_asked

# an article with its text in the feed
tap(100, row_y(0))
t = texts()
assert 'Full text of story three with words.' in t, t
key('back')

# a summary-only article without a Worker: the summary and how to get more
tap(100, row_y(1))
t = ' '.join(texts())
assert 'Summary two only' in t and 'Only a summary is in this feed.' in t, t
key('back')

# preview: the summary with Prev / Open / Close / Next only (no Star, read or Tags buttons)
hold(100, row_y(2))
r = recs()
assert 'Open' in r and 'Close' in r and not ({'Star', 'Mark read', 'Mark unread', 'Tags'} & set(r)), list(r)
assert 'Summary one' in r, list(r)
key('back')
key('back')                                          # the list -> the feeds: one unread left
assert 'Site News  (1)' in texts(), texts()
assert json.loads(g.store['idx.txt'])['https://www.example.com/news.xml']['u'] == 1

# opened again an hour later: the feed answers 304 Not Modified, read marks kept
g.fake_now = g.fake_now + 3600
tap_prefix('Site News')
g.flush()
assert etag_hits.get('https://www.example.com/news.xml') == 1, etag_hits
t = texts()
assert 'Site News  2026-10-30 15:00' in t and '* Site News  2026-10-28 15:00' in t, t   # * = unread
key('back')

# Add feed -> Choose from a list (from the site), add and remove with taps
tap_label('Add feed')
tap_label('Choose from a list')
g.flush()
assert any(s.startswith('Tech') for s in texts()), texts()
tap(100, row_y(0))
assert '[ ] Tech One' in texts()
tap(100, row_y(0))
assert '[x] Tech One' in texts() and 'https://tech.example/feed' in str(g.files['My feeds.opml'])
tap(100, row_y(0))
assert '[ ] Tech One' in texts() and 'https://tech.example/feed' not in str(g.files['My feeds.opml'])
tap(100, row_y(0))                                  # back in for the rest of the test
key('back'); key('back'); key('back')
assert 'Tech One' in texts() and 'Site News  (1)' in texts(), texts()

# an OPML address becomes a collection of its own, with its folders
tap_label('Add feed')
tap_label('Type an address')
answer_input('https://opml.example/list.opml')
assert 'Work.opml' in dict(g.files.items()), list(g.files.keys())
key('back'); key('back')                            # Add -> My feeds -> the sources
t = texts()
assert t[2:5] == ['My feeds', 'Work', 'Settings'], t
tap_label('Work')
tap_label('Teams/  (1 feed)')
assert texts()[3] == 'Work / Teams', texts()
tap_label('Work feed')
g.flush()
assert 'Work story' in texts(), texts()
key('back')                                         # the list -> the Teams folder
assert texts()[3] == 'Work / Teams', texts()
key('back')                                         # -> Work: Add feed adds to Work
tap_label('Add feed')
assert 'Feeds you add go into Work.' in texts(), texts()
tap_label('Choose from a list')
g.flush()
tap(100, row_y(0))                                  # Tech
assert '[ ] Tech One' in texts()                    # in My feeds, not in Work
tap(100, row_y(0))
assert 'https://tech.example/feed' in str(g.files['Work.opml']) and '[x] Tech One' in texts()
tap(100, row_y(0))                                  # and out again
assert 'https://tech.example/feed' not in str(g.files['Work.opml']) and 'https://tech.example/feed' in str(g.files['My feeds.opml'])
assert '<outline text="Teams" title="Teams">' in str(g.files['Work.opml']), g.files['Work.opml']   # the folder written back
key('back'); key('back'); key('back')
key('back')                                         # Work -> the sources

# remove a feed: long-press it, confirm
tap_label('My feeds')
hold_prefix('Tech One')
assert 'Remove this feed?' in texts(), texts()
tap(60, 280)                                        # Remove
assert 'https://tech.example/feed' not in str(g.files['My feeds.opml'])
assert texts()[3] == 'My feeds' and not any(s.startswith('Tech One') for s in texts()), texts()
hold(100, row_y(0))                                 # Add feed: nothing to remove
assert 'Remove this feed?' not in texts()
key('back')

# Full text without a Worker: the screen with the guide's QR code
tap_label('Settings')
tap(100, 56 + 20 + 3 * 96 + 24 + 10)              # Full text
t = texts()
assert 'Full text' in t and g.qr_made == 'https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/worker/?for=rss-local', (t, g.qr_made)
key('back')

# with a Worker: CommaFeed joins the sources, and a summary-only article comes in full
tap(100, 56 + 20 + 24 + 10)
answer_input('w.example.dev')
tap(100, 20)                                       # Back
g.flush()
t = texts()
assert t[2:6] == ['CommaFeed', 'My feeds', 'Work', 'Settings'], t
tap_label('My feeds')
tap_prefix('Site News')
g.flush()
tap_label('Middle story')
g.flush()
t = ' '.join(texts())
assert 'The whole middle story, from the Worker.' in t, t
assert any('/api/read?' in u and 'url=https%3A%2F%2Fsite.example%2F2' in u for u, h in requests), requests[-3:]
key('back'); key('back'); key('back')

# a feed too large for the reader: with a Worker it comes through /api/feed ...
g.files['My feeds.opml'] = g.files['My feeds.opml'].replace('</body>', '<outline text="Big" xmlUrl="https://big.example/feed"/></body>')
tap_label('Settings'); tap(100, 20)                 # Back from Settings reloads the collections
tap_label('My feeds')
tap_label('Big')
g.flush()
t = texts()
assert 'Big 19' in t, t
assert any('/api/feed?n=40&url=https%3A%2F%2Fbig.example%2Ffeed' in u for u, h in requests), [u for u, h in requests][-5:]
key('back'); key('back')

# ... and without one, in byte ranges as far as the reader goes
tap_label('Settings')
tap(100, 56 + 20 + 24 + 10)
answer_input('')
tap(100, 20)
g.flush()
g.fake_now = g.fake_now + 7200                     # the feed is due again
tap_label('My feeds')
tap_prefix('Big')
g.flush()
t = texts()
ranges = [h.get('range') for u, h in requests if u == 'https://big.example/feed' and h.get('range')]
assert ranges and ranges[0] == 'bytes=131072-262143', ranges
assert sum(1 for s in t if s.startswith('Big ')) >= 8, t
sizes = {str(k): len(str(v)) for k, v in g.store.items()}
assert max(sizes.values()) <= 262144, sizes
key('back'); key('back')

# a large collection (an OPML exported from another reader): folders, and no feed's file read
# to show them
big = ''.join(f'<outline text="Group {k}">' + ''.join(f'<outline type="rss" text="Feed {k}-{i}" xmlUrl="https://f{k}.example/{i}"/>' for i in range(60))
              + '</outline>' for k in range(7))
g.files['Export.opml'] = f'<?xml version="1.0"?><opml version="2.0"><head><title>Export</title></head><body>{big}</body></opml>'
tap_label('Settings'); tap(100, 20)
L.execute('reads = 0; local sr = ctx.storage.read; ctx.storage.read = function(self, n) reads = reads + 1; return sr(self, n) end')
tap_label('Export')
assert texts()[3:6] == ['Export', 'Add feed', 'Group 0/  (60 feeds)'], texts()
tap_label('Group 3/  (60 feeds)')
assert texts()[3].startswith('Export / Group 3  1-12 / 60'), texts()
tap(300, 20)                                       # Next
assert 'Feed 3-12' in texts()
assert g.reads == 0, g.reads
key('back')
assert 'Group 3/  (60 feeds)' in texts()
key('back'); key('back')

# a Worker set up only for full text: no CommaFeed among the sources
tap_label('Settings')
tap(100, 56 + 20 + 24 + 10)
answer_input('fullonly.example.dev')
tap(100, 20)
g.flush()
t = texts()
assert 'CommaFeed' not in t and 'My feeds' in t and 'Work' in t, t
print('rss local: add by address and list, a feed, preview, remove, OPML collections and folders, full text, large feeds and collections OK')
print('rss local tests passed')
