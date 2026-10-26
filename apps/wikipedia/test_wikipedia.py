"""Offline test of the Wikipedia app (gamekit harness with a stand-in network that answers like
the MediaWiki API, and ctx.json): search, results, an article laid out in pages with headings,
paging, a random article, the language choice in the request, the articles kept for offline
reading, long articles cut, errors shown.

  python -I apps/wikipedia/test_wikipedia.py
"""
import json, os, re, sys, urllib.parse
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

g = Game(HERE)
L = g.L
requests = []
ARTICLE = ('Istanbul is the largest city in Turkey.\n\n== History ==\nByzantium was founded by Greek colonists.\n\n'
           '=== Ottoman period ===\nThe city became the Ottoman capital in 1453.\n\n' +
           '\n\n'.join(f'Paragraph {k}: ' + 'word ' * 60 for k in range(30)))
mode = {'fail': False, 'long': False}


def to_lua(v):
    if isinstance(v, dict):
        return L.table_from({k: to_lua(x) for k, x in v.items()})
    if isinstance(v, list):
        return L.table_from([to_lua(x) for x in v])
    return v


def answer(url):
    q = dict(urllib.parse.parse_qsl(urllib.parse.urlsplit(url).query))
    host = urllib.parse.urlsplit(url).netloc
    if mode['fail']:
        return {'status': 503, 'body': 'busy'}
    if q.get('list') == 'search':
        body = {'query': {'search': [{'title': 'Istanbul', 'snippet': 'the largest <span class="searchmatch">city</span> &amp; port'},
                                     {'title': 'Istanbul Airport', 'snippet': 'airport'}]}}
    elif q.get('generator') == 'random':
        body = {'query': {'pages': [{'title': 'Random Topic', 'extract': 'A random article.\n\n== Part ==\nText.'}]}}
    else:
        text = ARTICLE if not mode['long'] else 'x ' * 40000
        body = {'query': {'pages': [{'title': q.get('titles', '?'), 'extract': text}]}}
    return {'status': 200, 'body': json.dumps(body), 'host': host}


def request(self, opts, fn):
    url = opts['url']
    requests.append((url, dict(opts['headers'])))
    resp = answer(url)
    L.globals().pending_resp = to_lua(resp)
    L.globals().pending_fn = fn
    return L.table_from({'cancel': lambda self: None})


net = L.table_from({'request': request, 'keep_wifi': lambda self, ms: None})
L.globals().ctx.net = net
L.globals().ctx.json = L.table_from({'decode': lambda self, s: to_lua(json.loads(s))})
L.globals().ctx.storage.remove = lambda self, n: L.globals().store.__setitem__(n, None)
answer_now = L.eval('function() local f, r = pending_fn, pending_resp; pending_fn = nil; if f then f(ctx, r) end end')
A = lambda: g.api


def type_text(s):
    L.eval('inputs[#inputs]')(L.globals().ctx, s)


def bar(k):           # 1 Back, 2 Prev, 3 Next, 4 Search / Clear
    bw = (480 - 16 - 18) // 4
    g.tap(8 + (k - 1) * (bw + 6) + bw // 2, 30)


t = g.texts()
assert 'Wikipedia' in t and 'Search' in t and 'Random article' in t and 'Read before (0)' in t and 'Language: English' in t, t

# search: the keyboard, the request (language, User-Agent), the results without HTML
g.tap_label('Search')
type_text('istanbul')
answer_now()
url, headers = requests[-1]
assert url.startswith('https://en.wikipedia.org/w/api.php?') and 'list=search' in url and 'srsearch=istanbul' in url, url
assert 'XteinkLicoriceWikipedia' in headers['User-Agent']
assert str(A().screen()) == 'results'
t = g.texts()
assert 'Istanbul' in t and 'the largest city & port' in t, t

# open a result: plain-text extract, headings, several pages
g.tap(100, 64 + 8 + 10)
answer_now()
assert 'titles=Istanbul' in requests[-1][0] and 'explaintext=1' in requests[-1][0]
assert str(A().screen()) == 'article'
art = A().art()
assert int(art.pages) >= 3, art.pages
t = g.texts()
assert 'Istanbul' in t and 'History' in t and 'Ottoman period' in t, t
assert '1/' + str(art.pages) in t
bar(3); assert int(A().art().page) == 2
g.tap(400, 400); assert int(A().art().page) == 3          # tap the right part: next page
g.tap(40, 400); assert int(A().art().page) == 2           # the left third: back
bar(1); assert str(A().screen()) == 'results'
bar(1); assert str(A().screen()) == 'home'

# kept for offline reading
assert 'Read before (1)' in g.texts()
files = [k for k in g.store.keys() if str(k).startswith('a_en_')]
assert len(files) == 1 and str(g.store[files[0]]).startswith('Istanbul\n')
mode['fail'] = True
g.tap_label('Read before (1)')
g.tap(100, 64 + 8 + 10)
assert str(A().screen()) == 'article' and 'Istanbul' in g.texts()      # no network needed
bar(1); bar(1)
mode['fail'] = False

# random article; a language from the list, then one typed in
g.tap_label('Random article')
answer_now()
assert 'generator=random' in requests[-1][0] and 'Random Topic' in g.texts()
bar(1)
g.tap_label('Language: English')
g.tap_label('tr')
assert 'Language: Türkçe' in g.texts() and 'lang=tr' in g.store['settings.txt']
g.tap_label('Search'); type_text('kedi'); answer_now()
assert requests[-1][0].startswith('https://tr.wikipedia.org/'), requests[-1][0]
bar(1)
g.tap_label('Language: Türkçe'); g.tap_label('Other'); type_text('EO ')
assert 'Language: eo' in g.texts()
g.tap_label('Text size: medium')
assert 'Text size: large' in g.texts()

# a failing request is reported; a long article is cut
mode['fail'] = True
g.tap_label('Random article'); answer_now()
assert any('HTTP 503' in s for s in g.texts()), g.texts()
mode['fail'] = False
mode['long'] = True
g.tap_label('Search'); type_text('long'); answer_now()
g.tap(100, 64 + 8 + 10); answer_now()
assert any('The article is longer' in str(ln.s) for ln in A().art().lines.values())
g.restart()
assert 'Read before (3)' in g.texts() and 'Language: eo' in g.texts()
g.no_err()
print('wikipedia tests passed')
