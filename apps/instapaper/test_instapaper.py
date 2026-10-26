"""Offline test of the API 2.9 Instapaper app under Lua 5.4 (lupa): a method-style ctx stub whose
net:request answers like the Instapaper API v2 and records every call (method, URL, body, token).

  python instapaper29/test_instapaper29.py
"""
import json, os
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
L = lua54.LuaRuntime(unpack_returned_tuples=True)

calls = []          # (method, url, body, authorization)
state = {'token_ok': True}


def bm(i, **kw):
    b = {'id': 1000 + i, 'title': f'Story {i}', 'url': f'https://www.site{i % 3}.com/post/{i}',
         'description': f'Description of story {i}.', 'time': 1761300000 + i, 'liked': False,
         'progress': {'percentage': 0, 'timestamp': 0}}
    b.update(kw)
    return b


LONG = ''.join(f'<p>Paragraph {k} with some words\n that wrap   across source lines and say a little more.</p>' for k in range(60))
ARTICLE = ('<div><h2>A heading</h2><p>It&rsquo;s &ldquo;quoted&rdquo; &amp; fine&#8230; caf&#233;&nbsp;bar.</p>'
           '<script>var hidden = 1;</script><style>p{}</style><!-- a comment -->'
           '<ul><li>first item</li><li>second item</li></ul><blockquote>A quote here.</blockquote>'
           '<p></p><h3></h3>' + LONG + '</div>')
PICS = ('<p>Before the pictures.</p>'
        '<img src="https://cdn.example.com/a.jpg" width="1200" height="800" alt="big">'
        '<img src="data:image/gif;base64,R0lG" data-src="//cdn.example.com/lazy.png">'
        '<img src="/icons/star.png" width="16" height="16">'
        '<img src="https://t.example.com/p.gif" width="1" height="1">'
        '<p>Between.</p><figure><img src="img/rel.jpg"></figure><p>After.</p>')
pages = {
    'section=home&limit=12&offset=0': {'bookmarks': [bm(i, progress={'percentage': 0.4 if i == 1 else 0},
                                                       **({'description': 'Long description. ' * 120} if i == 7 else {}))
                                                    for i in range(12)], 'total': 20},
    'section=home&limit=12&offset=12': {'bookmarks': [bm(i) for i in range(12, 20)], 'total': 20},
    'section=folder&limit=12&offset=0&folder_id=77': {'bookmarks': [bm(50, title='In a folder')], 'total': 1},
}


def fake_request(method, url, body, auth):
    calls.append((method, url, body, auth))
    if not state['token_ok']:
        return 401, json.dumps({'error': {'code': 401, 'message': 'Invalid token'}})
    if url.startswith('https://images.weserv.nl/'):
        return (404, 'no') if 'lazy.png' in url else (200, b'\xff\xd8' + b'x' * 50)
    path = url.split('/api/2', 1)[1]
    if path == '/folders':
        return 200, json.dumps({'folders': [{'id': 77, 'title': 'Tech'}]})
    if path.startswith('/bookmarks?'):
        q = path.split('?', 1)[1]
        return (200, json.dumps(pages[q])) if q in pages else (404, '{"error":{"message":"no page"}}')
    if path.endswith('/1006/parse'):
        return 200, json.dumps({'content': {'body': PICS}, 'metadata': {}})
    if path.endswith('/1005/parse'):                    # longer than the app keeps
        return 200, json.dumps({'content': {'body': '<p>' + 'çağ öğün ' * 6000 + '</p>'}, 'metadata': {}})
    if path.endswith('/parse'):
        return 200, json.dumps({'content': {'body': ARTICLE, 'direction': 'ltr'}, 'metadata': {'title': 'Parsed', 'author': {'name': 'Ann Writer'}}})
    if method == 'POST':
        return 200, '{}'
    return 404, '{}'


L.globals().py_request = fake_request
L.globals().py_json_decode = lambda s: L.table_from(json.loads(s), recursive=True)

L.execute(r'''
drawn, store = {}, {}
local gmt = {}
images_drawn = 0
gmt.__index = function(_, k) return function(_, ...) if k == 'image' then images_drawn = images_drawn + 1 end if k == 'text' then local x, y, s, o = ...; drawn[#drawn + 1] = { s = s, x = x, y = y } end end end
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
fake_ms = 1000
local function font(name, lh) local f = M({ measure = function(s) return #s * 10 end }); f.name = name; f.line_height = lh; return f end
ctx = {
  invalidate = function() end, state = {},
  storage = M({ write = function(n, d) store[n] = d; return true end, read = function(n) if store[n] then return store[n] end return nil, 'not_found' end }),
  fonts = { small = font('small', 20), medium = font('medium', 24), large = font('large', 30) },
  input = M({ text = function(opts, fn) inputs[#inputs + 1] = fn end }),
  clock = M({ millis = function() return fake_ms end, epoch = function() return 1761400000 end }),
  qr = M({ encode = function(t) return setmetatable({}, { __index = { width = 33, height = 33, release = function() end } }) end }),
  net = M({ keep_wifi = function() end, request = function(opts, fn)
    local st, body = py_request(opts.method, opts.url, opts.body, opts.headers and opts.headers['Authorization'])
    pending[#pending + 1] = function() fn(ctx, { status = st, body = body, headers = {} }) end
    return M({ cancel = function() end })
  end }),
  json = M({ decode = function(s) return py_json_decode(s) end }),
  image = M({ decode = function(b) decoded = (decoded or 0) + 1; return setmetatable({}, { __index = { width = 456, height = 304, release = function() end } }) end }),
}
function flush() for _ = 1, 50 do local p = pending; pending = {}; if #p == 0 then return end; for _, f in ipairs(p) do f() end end end
''')
L.execute(f"dofile([[{os.path.join(HERE, 'index.lua').replace(os.sep, '/')}]])")
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

# no token -> settings; the token typed in the firmware keyboard is saved
g.on_load(g.ctx)
t = texts()
assert 'Access token (instapaper.com/developers)' in t and 'on the SD card over USB.' in t, t
tap(100, TOP + 20 + 24 + 10)
g.inputs[1](g.ctx, '  tok123456789  ')
g.inputs = L.table()
assert g.store['config.txt'] == 'token=tok123456789\nsize=default\nimages=0', g.store['config.txt']
assert 'tok1...6789' in texts()
tap(*BAR(0))                                             # Back: menu; the folder list is asked
assert calls[-1][:2] == ('GET', 'https://www.instapaper.com/api/2/folders') and calls[-1][3] == 'Bearer tok123456789', calls[-1]
g.flush()
t = texts()
assert 'Instapaper' in t and 'Archive' in t and 'Folders' in t and 'signed in with an access token' in t, t

# Unread: section=home, 12 rows with site, day saved and progress
tap(*MENU(0)); g.flush()
assert calls[-1][1].endswith('/bookmarks?section=home&limit=12&offset=0'), calls[-1]
t = texts()
assert 'Story 0' in t and 'Story 11' in t, t
assert any(x.startswith('site1.com  2025-10-24  40%') for x in t), t       # 1761300001 s = 2025-10-24
# Next past the last row: offset 12 is appended
tap(*BAR(2)); g.flush()
assert calls[-1][1].endswith('offset=12'), calls[-1]
t = texts()
assert 'Story 12' in t and 'Story 19' in t and any('13-20 / 20' in x for x in t), t
tap(*BAR(1))                                             # back to the first screen

# long press: the description, and Prev / Open / Archive / Next
long_press(100, row_y(2))
t = texts()
assert 'Description of story 2.' in t and 'Archive' in t and 'Open' in t and 'Close' not in t, t
assert 'Back' not in t and 'Reload' not in t and not any(x.startswith('Unread  ') for x in t), t   # bar hidden
open_y = recs()['Open'][1]
key('back')
long_press(100, row_y(7))                                 # a very long description: same box, cut with "…"
t = texts()
assert recs()['Open'][1] == open_y and any(x.endswith(' …') for x in t), t
key('back')
assert 'Story 0' in texts()

# open the article with 40 % progress: HTML turned into styled text, resumed mid-article
n = len(calls)
tap(100, row_y(1)); g.flush()
assert calls[-1][1].endswith('/bookmarks/1001/parse') and len(calls) == n + 1, calls[n:]
import re
def page_ind():
    for x in texts():
        m = re.fullmatch(r'(\d+)/(\d+)', x)
        if m: return int(m.group(1)), int(m.group(2))
    raise AssertionError(texts())
page_now, pages_total = page_ind()
assert pages_total >= 4, pages_total
assert page_now == int(0.4 * pages_total) + 1, (page_now, pages_total)
BAR_LABELS = {'Back', 'Prev', 'Next'}
def article_lines():
    for _ in range(pages_total): key('left')
    out = []
    for k in range(pages_total):
        out += [x for x in texts() if x not in BAR_LABELS and not re.fullmatch(r'\d+/\d+', x)]
        if k < pages_total - 1: key('right')
    return out
lines = article_lines()
text = chr(10).join(lines)
assert 'A heading' in lines and 'site1.com Ann Writer 2025-10-24' in lines, lines[:8]
assert '• first item' in lines and '• second item' in lines, lines[:20]
assert 'It’s “quoted” & fine… café bar.' in lines, lines[:20]
assert 'hidden' not in text and 'p{}' not in text and 'comment' not in text and 'A quote here.' in lines
assert 'Paragraph 3 with some words that wrap across source' in text.replace(chr(10), ' '), 'source line breaks must be spaces'
assert '#' not in text
# Back after paging on (now on the last page): the progress goes to Instapaper
key('back'); g.flush()
m, url, body, auth = calls[-1]
assert m == 'POST' and url.endswith('/bookmarks/1001') and '"percentage":' in body and '"timestamp":1761400000' in body, calls[-1]
p_sent = json.loads(body)['progress']['percentage']
assert 0.4 < p_sent <= 1, p_sent
# opened again: from the cache, no request; Back without paging sends nothing
n = len(calls)
tap(100, row_y(1)); g.flush()
assert len(calls) == n and 'cached' in texts(), calls[n:]
key('back'); g.flush()
assert len(calls) == n

# the end of the article: Source QR, then Star and Archive
tap(100, row_y(3)); g.flush()
for _ in range(page_ind()[1]): key('right')
t = texts()
assert 'Source:' in t and 'Archive' in t and 'Star' in t, t
tap_label('Star'); g.flush()
assert calls[-1][0] == 'POST' and calls[-1][1].endswith('/bookmarks/1003/like'), calls[-1]
assert 'Starred' in texts()
tap_label('Archive'); g.flush()
assert any(c[0] == 'POST' and c[1].endswith('/bookmarks/1003/move') and c[2] == '{"section":"archive"}' for c in calls[-2:]), calls[-2:]
t = texts()
assert 'Story 3' not in t and 'Story 4' in t and 'Back' in t, t                          # back on the list, gone
assert not any(c[1].endswith('/bookmarks/1003') for c in calls[-2:]), 'archived: no progress to send'

# archive from the preview: it moves on to the next story, the archived one leaves the list
long_press(100, row_y(0))
assert 'Description of story 0.' in texts()
tap_label('Archive'); g.flush()
assert calls[-1][1].endswith('/bookmarks/1000/move'), calls[-1]
assert 'Description of story 1.' in texts(), texts()
key('back')
assert 'Story 0' not in texts() and 'Story 1' in texts()

# folders: the list of folders, then a folder's bookmarks
key('back')
tap(*MENU(3)); g.flush()
assert calls[-1][1].endswith('/folders') and 'Tech' in texts(), texts()
tap(100, row_y(0)); g.flush()
assert calls[-1][1].endswith('/bookmarks?section=folder&limit=12&offset=0&folder_id=77'), calls[-1]
assert 'In a folder' in texts()

# a wrong token: the list says why
state['token_ok'] = False
tap(*BAR(3)); g.flush()
t = texts()
assert 'In a folder' in t and any(x.startswith('offline: token rejected (401)') for x in t), t   # the saved copy
for k in list(g.store.keys()):
    if str(k).startswith('l_'): g.store[k] = None
tap(*BAR(3)); g.flush()
t = texts()
assert 'In a folder' in t and 'token rejected (401): see Settings' in t, t     # rows stay, the status says why
# a list never loaded and nothing saved: the screen says why
key('back'); tap(*MENU(1)); g.flush()
t = texts()
assert 'Could not load this list.' in t and any('token rejected (401)' in x for x in t), t
state['token_ok'] = True

# a config.txt written on Windows (CR LF) still gives the right token
g.store['config.txt'] = 'token=winTOKEN\r\nsize=large\r\n'
L.execute(f"dofile([[{os.path.join(HERE, 'index.lua').replace(os.sep, '/')}]])")
g = L.globals()
g.pending = L.table()
g.on_load(g.ctx)
assert calls[-1][3] == 'Bearer winTOKEN', calls[-1]
assert not any('ERR' in x for x in texts())
# a very long article is cut at a word, never inside a UTF-8 character, and ends with an ellipsis
state['token_ok'] = True
for k in list(g.store.keys()):
    if str(k).startswith('l_'): g.store[k] = None
g.on_load(g.ctx); g.flush()
tap(*MENU(0)); g.flush()
tap(100, row_y(5)); g.flush()
total = page_ind()[1]
for _ in range(total): key('right')
body_lines = [x for x in texts() if x not in BAR_LABELS and not re.fullmatch(r'[0-9]+/[0-9]+', x)]
key('left')                                              # the text ends on the page before the source
body_lines = [x for x in texts() if x not in BAR_LABELS and not re.fullmatch(r'[0-9]+/[0-9]+', x)] + body_lines
last = [x for x in body_lines if 'ğ' in x or '…' in x][-1]
assert last.endswith('…') and 'ğ' in last, last
last.encode('utf-8')
# pictures: off by default (no markers, no resizer requests); on, they load for the page on screen
state['token_ok'] = True
n = len(calls)
key('back'); tap(100, row_y(6)); g.flush()
assert not any('weserv' in c[1] for c in calls[n:]), calls[n:]
assert 'Before the pictures.' in texts() and not any('[[img' in x for x in texts()), texts()
key('back'); key('back')
tap(*MENU(4))                                            # Settings -> Images in articles
tap(100, TOP + 20 + 2 * 96 + 24 + 10)
assert g.store['config.txt'].endswith('images=1'), g.store['config.txt']
tap(*BAR(0)); g.flush()
tap(*MENU(0)); g.flush()
n = len(calls)
tap(100, row_y(6)); g.flush()
seen_image_text = False
for _ in range(page_ind()[1]):                         # pictures load page by page
    seen_image_text = seen_image_text or '[image]' in texts()
    key('right'); g.flush()
pics = [c[1] for c in calls[n:] if 'weserv' in c[1]]
assert len(pics) == 3, pics                               # big, lazy, relative; no icon, no pixel
assert pics[0] == ('https://images.weserv.nl/?url=https%3A%2F%2Fcdn.example.com%2Fa.jpg&w=456&h=304'
                   '&fit=contain&cbg=white&output=jpg&q=70&filt=greyscale'), pics[0]
assert 'url=https%3A%2F%2Fcdn.example.com%2Flazy.png&w=456&h=342' in pics[1], pics[1]
assert 'url=https%3A%2F%2Fwww.site0.com%2Fpost%2Fimg%2Frel.jpg' in pics[2], pics[2]
assert not any('star.png' in c[1] or 'p.gif' in c[1] for c in calls[n:])
assert seen_image_text, 'the lazy picture failed: [image] in its place'
assert g.images_drawn >= 1
# opened again: from the cache with its pictures
n = len(calls)
key('back'); tap(100, row_y(6)); g.flush()
for _ in range(4): key('left'); g.flush()
assert not any('/parse' in c[1] for c in calls[n:]) and any('weserv' in c[1] for c in calls[n:]), calls[n:]
assert 'Before the pictures.' in texts()
# progress that could not be sent waits on the card and goes out at the next start
def restart():
    L.execute(f"dofile([[{os.path.join(HERE, 'index.lua').replace(os.sep, '/')}]])")
    gl = L.globals()
    gl.pending = L.table()
    gl.on_load(gl.ctx)
    return gl

state['token_ok'] = True
g.store['progress.txt'] = None
g = restart(); g.flush()
key('back')                                                  # out of whatever screen we were on
tap(*MENU(0)); g.flush()
tap(100, row_y(2)); g.flush()                                # Story 2, from the start
key('right'); key('right')
n = len(calls)
L.execute("on_leave()")                                      # the app is left from inside the article
assert len(calls) == n, calls[n:]                            # nothing sent on the way out
saved = str(g.store['progress.txt'])
assert saved.startswith('1002 0.') and saved.endswith(' 1761400000'), saved
L.execute("ctx.clock = nil")                                 # a later start: the old timestamp must stay
g = restart()
assert calls[-1][1].endswith('/folders'), calls[-1]          # Wi-Fi comes up with the folder request ...
g.flush()
m, url, body, _ = calls[-1]
assert m == 'POST' and url.endswith('/bookmarks/1002') and '"timestamp":1761400000' in body, calls[-1]
assert '"percentage":' + saved.split()[1] in body, (body, saved)
assert str(g.store['progress.txt']) == '', g.store['progress.txt']          # sent: nothing left
L.execute("ctx.clock = { millis = function() return fake_ms end, epoch = function() return 1761400000 end }")
L.execute("for k, f in pairs(ctx.clock) do local fn = f; ctx.clock[k] = function(self, ...) return fn(...) end end")

# a request that fails on Back keeps the position for the next start
tap(*MENU(0)); g.flush()
tap(100, row_y(3)); g.flush()
key('right')
state['token_ok'] = False
key('back'); g.flush()
assert str(g.store['progress.txt']).startswith('1003 '), g.store['progress.txt']
assert 'progress kept, sent next time' in texts(), texts()
state['token_ok'] = True
g = restart(); g.flush()
assert any(c[0] == 'POST' and c[1].endswith('/bookmarks/1003') for c in calls[-3:]), calls[-3:]
assert str(g.store['progress.txt']) == ''
print('instapaper29 tests passed')
