"""Offline test of Hacker News (gamekit harness with a stand-in network that answers like HN's
Firebase API, Algolia's search and the rss-opds Worker's /api/read, and ctx.json): lists in HN's
order with titles from one Algolia search, paging that loads more, the last list kept, a story
with its text or the article through the Worker (and the Worker's errors), comments level by
level loaded while reading, replies and back, search, settings, ids read from the raw JSON, and
the draw-command count.

  python -I apps/hackernews/test_hackernews.py
"""
import json, os, re, sys, urllib.parse
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

NOW = 1793070000
BIG = 50242939                         # an id above 2^24: must not go through a float
requests = []
mode = {'worker': 'ok'}

TOP = [BIG] + list(range(50000101, 50000160))            # 60 ids; 50000105 is a job Algolia leaves out
ITEMS = {
    BIG: {'by': 'pg', 'descendants': 5, 'id': BIG, 'kids': [201, 202, 203], 'score': 512, 'time': NOW - 3 * 3600,
          'title': 'An essay about Lisp', 'type': 'story', 'url': 'https://www.example.com/lisp?x=1'},
    50000101: {'by': 'dang', 'descendants': 0, 'id': 50000101, 'score': 50, 'time': NOW - 600, 'type': 'story',
               'title': 'Ask HN: What are you reading?', 'text': 'Books <i>and</i> papers.<p>Second &#x27;para&#x27;.'},
    50000102: {'by': 'x', 'descendants': 40, 'id': 50000102, 'kids': list(range(400, 440)), 'score': 9, 'time': NOW - 86400 * 2,
               'title': 'A long thread', 'type': 'story', 'url': 'https://long.example/'},
    201: {'by': 'alice', 'id': 201, 'kids': [301, 302], 'parent': BIG, 'time': NOW - 3600, 'type': 'comment',
          'text': 'It&#x27;s good.<p>See <a href="https:&#x2F;&#x2F;e.example&#x2F;a">https:&#x2F;&#x2F;e.example&#x2F;a</a> &gt; here'
                  '<p>&gt; quoted text<p><pre><code>  code line 1\n  code line 2\n</code></pre>'},
    202: {'deleted': True, 'id': 202, 'parent': BIG, 'time': NOW - 3000, 'type': 'comment'},
    203: {'by': 'bob', 'id': 203, 'parent': BIG, 'time': NOW - 120, 'type': 'comment',
          'text': 'A link without spaces: https://very.long.example/' + 'path/' * 30},
    301: {'by': 'carol', 'id': 301, 'parent': 201, 'time': NOW - 1000, 'type': 'comment', 'text': 'Agreed.'},
    302: {'by': 'dave', 'id': 302, 'parent': 201, 'time': NOW - 900, 'type': 'comment', 'text': 'Not quite.', 'dead': True},
}
for k in range(400, 440):
    ITEMS[k] = {'by': f'user{k}', 'id': k, 'time': NOW - 500, 'type': 'comment', 'text': f'Comment {k}. ' + 'Words go on here. ' * 12}


def hit(i):
    it = ITEMS.get(i, {})
    return {'objectID': str(i), 'title': it.get('title', f'Story number {i} with a title long enough to need two lines here'),
            'url': it.get('url', None if i == 50000101 else f'https://site{i % 7}.example/post'), 'points': it.get('score', i % 300),
            'num_comments': it.get('descendants', i % 50), 'author': it.get('by', 'someone'), 'created_at_i': it.get('time', NOW - 7200)}


def answer(url):
    u = urllib.parse.urlsplit(url)
    q = dict(urllib.parse.parse_qsl(u.query))
    if u.netloc == 'hacker-news.firebaseio.com':
        if u.path.endswith('stories.json'):
            return {'status': 200, 'body': json.dumps(TOP)}
        i = int(re.search(r'item/(\d+)\.json', u.path).group(1))
        return {'status': 200, 'body': json.dumps(ITEMS.get(i))}
    if u.netloc == 'hn.algolia.com':
        assert q['attributesToHighlight'] == '[]'
        if 'query' in q:
            page = int(q['page'])
            hits = [hit(70000000 + page * 24 + k) for k in range(24)]
            return {'status': 200, 'body': json.dumps({'hits': hits, 'nbPages': 2, 'page': page})}
        ids = [int(x) for x in re.findall(r'story_(\d+)', q['tags'])]
        hits = [hit(i) for i in reversed(ids) if i != 50000105]
        return {'status': 200, 'body': json.dumps({'hits': hits})}
    if u.netloc == 'w.example':
        assert u.path == '/k/tok/api/read', u.path
        if mode['worker'] == 'old':
            return {'status': 404, 'body': json.dumps({'error': 'not found'})}
        if mode['worker'] == 'none':
            return {'status': 501, 'body': json.dumps({'error': 'no full-text service configured'})}
        body = {'url': q['url'], 'source': 'diffbot',
                'text': '# The essay\n\nLisp is a family of languages.\n\n> A quote.\n\n' + ('[[img:1]]\n\n' if 'images' in q else '')
                        + 'More text. ' * 300 + ('\n\n[[img:2]]\n\nThe end.' if 'images' in q else '')}
        if 'images' in q:
            body['images'] = [{'n': 1, 'w': 456, 'h': 304, 'src': 'https://img.example/r?u=1'},
                              {'n': 2, 'w': 300, 'h': 200, 'src': 'https://img.example/r?u=2'}]
        return {'status': 200, 'body': json.dumps(body)}
    if u.netloc == 'img.example':
        if q['u'] == '2':
            return {'status': 404, 'body': 'gone'}
        return {'status': 200, 'body': b'\xff\xd8\xff\xe0 fake jpeg'}
    raise AssertionError(url)


g = Game(HERE)
L = g.L


def to_lua(v):
    if isinstance(v, dict):
        return L.table_from({k: to_lua(x) for k, x in v.items()})
    if isinstance(v, list):
        return L.table_from([to_lua(x) for x in v])
    return v


def request(self, opts, fn):
    requests.append(opts['url'])
    L.globals().pending_resp = to_lua(answer(opts['url']))
    L.globals().pending_fn = fn
    return L.table_from({'cancel': lambda self: None})


def decode(self, s):
    v = json.loads(s)
    if isinstance(v, (dict, list)):
        # numbers as the reader's 32-bit Lua may give them: large ids rounded like a float32 would
        def rnd(x, key=None):
            if isinstance(x, dict):
                return {k: (rnd(y, k) if k in ('id', 'kids', 'parent') else float(y) if k == 'time' else y) for k, y in x.items()}
            if isinstance(x, list):
                return [rnd(y, key) for y in x]
            if isinstance(x, int) and x > 2 ** 24:
                return float(x) + 3
            return x
        return to_lua(rnd(v))
    return v


ctx = L.globals().ctx
ctx.net = L.table_from({'request': request, 'keep_wifi': lambda self, ms: None})
ctx.json = L.table_from({'decode': decode})
L.execute("decoded, released = 0, 0; ctx.capabilities = { image_decode = true }; ctx.image = { decode = function(self, b) decoded = decoded + 1; "
          "return { width = 456, release = function() released = released + 1 end } end }")
L.execute(f"ctx.clock.now = function(self) return {{ epoch_sec = {NOW}, hour = 12, minute = 0, second = 0 }} end")
answer_one = L.eval('function() local f, r = pending_fn, pending_resp; pending_fn = nil; if f then f(ctx, r); return true end return false end')
hold = L.eval("function(x, y) on_input(ctx, {type='pointer', phase='down', x=x, y=y}); "
              "for k = 1, 3 do on_input(ctx, {type='pointer', phase='hold', gesture='long', x=x, y=y}) end; "
              "on_input(ctx, {type='pointer', phase='up', x=x, y=y}) end")
swipe = L.eval("function(g) on_input(ctx, {type='pointer', phase='up', gesture=g, x=200, y=400}) end")
A = lambda: g.api
g.restart()                                               # on_load again, with the network in place


def answer_all(limit=100):
    n = 0
    while answer_one() and n < limit:
        n += 1
    return n


def typed(s): L.eval('inputs[#inputs]')(ctx, s)
def row(k): return 64 + (k - 1) * 78 + 20
def lst(): return A().L()
def titles(): return [str(r.title) for r in lst().rows.values()]
def screen(): return str(A().screen())
def page_text(): return ' '.join(g.texts())


# the list: HN's order from Firebase, titles from one Algolia search (a job left out)
assert requests[-1].endswith('/v0/topstories.json') and 'Loading top stories...' in g.texts()
answer_one()
assert 'story_50242939%2Cstory_50000101' in requests[-1] and 'hitsPerPage=24' in requests[-1]
answer_one()
t = titles()
assert t[0] == 'An essay about Lisp' and t[1] == 'Ask HN: What are you reading?' and len(t) == 23, t
assert str(lst().rows[1].id) == str(BIG)
assert 'list_top.txt' in g.store and g.store['list_top.txt'].startswith(f'{BIG}\tAn essay about Lisp\thttps://www.example.com/lisp?x=1\t512\t5\tpg\t')
texts = g.texts()
assert 'An essay about Lisp' in texts and '512 pts · 5 comm. · example.com · 3 h ago' in texts, texts

# paging: Next past the loaded rows loads the next 24
g.tap_label('Next'); g.tap_label('Next')
assert lst().top == 17
g.tap_label('Next')
assert lst().top == 17 and 'story_50000124' in requests[-1]
answer_one()
assert lst().top == 25 and len(titles()) == 47
swipe('swipe_down')
assert lst().top == 17

# kept: the last list shows at once, then the new one replaces it
g.restart()
assert titles()[0] == 'An essay about Lisp' and len(titles()) == 23 and lst().stale
answer_all()
assert not lst().stale and len(titles()) == 23

# a story without a Worker: its address and how to read it here
g.tap(100, row(1))
assert screen() == 'story' and requests[-1].endswith(f'/item/{BIG}.json')
answer_all()
t = page_text()
assert 'An essay about Lisp' in t and '512 points · by pg · 3 h ago' in t and 'example.com' in t, t
assert 'rss-opds Worker in Settings' in ' '.join(g.texts()) and 'https://www.example.com/lisp?x=1' in ''.join(g.texts()), t
assert '5 comments' in g.texts()

# comments, loaded one by one; a deleted one left out; HTML as text; the ids exact
g.tap_label('5 comments')
assert screen() == 'thread' and requests[-1].endswith('/item/201.json')
answer_all()
assert requests[-3:] == [f'https://hacker-news.firebaseio.com/v0/item/{i}.json' for i in (201, 202, 203)], requests[-3:]
t = page_text()
for s in ['An essay about Lisp', '5 comments', 'alice · 1 h ago', "It's good.", 'See https://e.example/a > here', '> quoted text',
          'code line 1', 'code line 2', '2 replies >', 'bob · 2 min ago']:
    assert s in t, (s, t)
lines = [str(x) for x in g.texts()]
assert all(len(x) * 10 <= 480 for x in lines), [x for x in lines if len(x) * 10 > 480]     # long words broken
assert '- end of comments -' in page_text() or len(A().level().pages) > 1

# replies: a level down and back; a dead one left out
ys = {str(d.s): int(d.y) for d in g.draw()}
g.tap(300, ys['2 replies >'] + 5)
assert len(A().levels()) == 2 and requests[-1].endswith('/item/301.json')
answer_all()
t = page_text()
assert 'Replies to alice' in t and "It's good." in t and 'carol · 16 min ago' in t and 'Agreed.' in t and 'dave' not in t, t
assert '- end of replies -' in t
g.tap_label('Back')
assert len(A().levels()) == 1 and 'alice · 1 h ago' in g.texts()
g.tap_label('Back')
assert screen() == 'story'
g.tap_label('Back')
assert screen() == 'list'

# Ask HN: the text; a long press opens the comments at once
g.tap(100, row(2)); answer_all()
t = page_text()
assert 'Books and papers.' in t and "Second 'para'." in t and 'Worker' not in t, t
g.tap_label('Back')
hold(100, row(2))
assert screen() == 'thread'
answer_all()
assert 'No comments yet.' in g.texts()
g.tap_label('Story')
assert screen() == 'story'
g.tap_label('Back')

# a long thread: loaded while reading, not all at once
g.tap(100, row(3)); answer_all()
g.tap_label('40 comments')
answer_all()
lv = A().level()
got = len(list(lv.got.values()))
assert 4 <= got < 40 and len(lv.pages) - lv.page >= 2, (got, len(lv.pages))
g.tap(300, 300)                                            # a tap on the text turns the page
assert A().level().page == 2 and len(A().levels()) == 1
answer_all()
g.tap(50, 300)
assert A().level().page == 1
assert g.commands() < 900, g.commands()
for k in range(30):
    g.tap_label('Next'); answer_all()
assert len(list(A().level().got.values())) == 40 and '- end of comments -' in g.texts()
g.tap_label('Back'); g.tap_label('Back')

# the Worker: articles as text; its errors explained
g.tap_label('Settings')
g.tap(100, 70 + 40); typed(' https://w.example/ ')
g.tap(100, 70 + 86 + 40); typed('tok')
assert 'host=https://w.example/\ntoken=tok\n' in g.store['settings.txt']
assert '***' in page_text()
g.tap(100, 70 + 3 * 86 + 40)
assert A().cfg.size == 'large'
g.tap(100, 70 + 3 * 86 + 40); g.tap(100, 70 + 3 * 86 + 40)
assert A().cfg.size == 'medium'
g.tap_label('Back')
g.tap(100, row(1))
answer_all()
assert any(r.startswith('https://w.example/k/tok/api/read?max=20000&images=1&url=https%3A%2F%2Fwww.example.com%2Flisp%3Fx%3D1') for r in requests), requests[-3:]
# the picture on the first page loaded and decoded; the one further on not yet
assert requests[-1] == 'https://img.example/r?u=1' and L.globals().decoded == 1, requests[-3:]
assert A().pics()['https://img.example/r?u=1'].img and 'picture...' not in g.texts()
t = page_text()
assert 'The essay' in t and 'Lisp is a family of languages.' in t and 'A quote.' in t and 'enter your' not in t, t
d = {str(x.s): x for x in g.draw()}
assert int(d['A quote.'].x) == 40
assert len(A().S().pages) > 3
assert g.commands() < 900
# a tap turns the page: the left third back, elsewhere on; the picture left behind is released
g.tap(300, 400)
assert A().S().page == 2 and L.globals().released == 1
g.tap(50, 400)
assert A().S().page == 1
answer_all()
assert L.globals().decoded == 2                            # fetched again: pages keep no bytes
for k in range(20):
    g.tap(300, 400); answer_all()
assert 'https://img.example/r?u=2' in requests and '[picture]' in g.texts() and 'The end.' in page_text()
g.tap_label('Back')
assert L.globals().released == 2 and len(list(A().pics().keys())) == 0
# pictures off
g.tap_label('Settings'); g.tap(100, 70 + 4 * 86 + 40)
assert A().cfg.images == 'off' and 'images=off' in g.store['settings.txt']
g.tap_label('Back'); g.tap(100, row(1)); answer_all()
assert not any('images=1' in r for r in requests[-2:]) and 'picture' not in page_text()
g.tap_label('Back'); g.tap_label('Settings'); g.tap(100, 70 + 4 * 86 + 40); g.tap_label('Back'); g.tap(100, row(1)); answer_all()
mode['worker'] = 'old'
g.tap_label('Back'); g.tap(100, row(1)); answer_all()
assert 'the Worker is older than /api/read; update it' in page_text()
mode['worker'] = 'none'
g.tap_label('Back'); g.tap(100, row(1)); answer_all()
assert 'the Worker has no full-text service' in page_text()
g.tap_label('Back')

# tabs and search
g.tap(30 + 79 * 2, 30)                                    # Best
assert lst().tab == 'best' and requests[-1].endswith('/v0/beststories.json')
answer_all()
g.tap(30 + 79 * 5, 30)                                    # Find
typed('lisp machines')
assert 'search?tags=story&query=lisp%20machines&hitsPerPage=24&page=0' in requests[-1]
answer_all()
assert len(titles()) == 24 and '"lisp machines"' in g.texts()
g.tap_label('Next'); g.tap_label('Next'); g.tap_label('Next')
assert 'page=1' in requests[-1]
answer_all()
assert len(titles()) == 48 and lst().top == 25 and not lst().more
assert g.commands() < 900, g.commands()

# leaving a screen drops what it waited for
g.tap(100, row(1))
assert A().queue() >= 1
g.tap_label('Back')
answer_all()
assert screen() == 'list'
g.no_err()
print('hackernews tests passed')
