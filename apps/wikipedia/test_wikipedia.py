"""Offline test of the Wikipedia app (gamekit harness with a stand-in network that answers like
the MediaWiki API, and ctx.json): search, results, an article laid out in pages with headings,
paging, a random article, the language choice in the request, the articles kept for offline
reading, long articles in parts (also when the JSON decoder gives up on them), errors shown.

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
mode = {'fail': False, 'long': False, 'huge': False, 'cut': False, 'ascii': False}


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
        if mode['huge']:
            text = 'Mustafa Kemal Atatürk "Gazi" \\ ilk cumhurbaşkanı. 😀\n\n== Hayatı ==\n' + 'Selanik’te doğdu. ' * 12000
        body = {'normalized': [{'from': 'x', 'to': 'Mustafa Kemal Atatürk', 'title': 'wrong one'}],
                'query': {'pages': [{'pageid': 1, 'title': q.get('titles', '?'), 'extract': text}]}}
    raw = json.dumps(body, ensure_ascii=mode['ascii'])
    if mode['cut']:
        raw = raw[:15000]
    return {'status': 200, 'body': raw, 'host': host}


def request(self, opts, fn):
    url = opts['url']
    requests.append((url, dict(opts['headers'])))
    resp = answer(url)
    L.globals().pending_resp = to_lua(resp)
    L.globals().pending_fn = fn
    return L.table_from({'cancel': lambda self: None})


net = L.table_from({'request': request, 'keep_wifi': lambda self, ms: None})
L.globals().ctx.net = net
def decode(self, s):
    if len(s) > 100000:
        raise ValueError('too big for the decoder')        # as the reader's decoder gave up
    return to_lua(json.loads(s))


L.globals().ctx.json = L.table_from({'decode': decode})
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
assert any('Part 1. Next: part 2.' in str(ln.s) for ln in A().art().lines.values())
mode['long'] = False
bar(1); bar(1)

# a reply too big for the JSON decoder: read straight from the text (UTF-8, quotes, \\, emoji)
for ascii_ in (False, True):
    mode['huge'], mode['ascii'] = True, ascii_
    g.tap_label('Search'); type_text('ataturk'); answer_now()
    g.tap(100, 64 + 8 + 10); answer_now()
    assert str(A().screen()) == 'article', (ascii_, A().status())
    lines = [str(ln.s) for ln in A().art().lines.values()]
    assert 'Atatürk "Gazi" \\ ilk cumhurbaşkanı. 😀' in ' '.join(lines), lines[:6]
    assert 'Hayatı' in lines and any('Part 1. Next: part 2.' in l for l in lines)
    # past the last page: part 2 is fetched and starts where part 1 ended; back again
    first_part = ' '.join(lines)
    pages = int(A().art().pages)
    for _ in range(pages):
        bar(3)
    answer_now()
    assert int(A().art().part) == 2 and int(A().art().page) == 1
    second = ' '.join(str(ln.s) for ln in A().art().lines.values())
    assert 'Selanik’te doğdu.' in second and 'Gazi' not in second, second[:300]
    assert 'Part 2. Next: part 3.' in second
    bar(2); answer_now()
    assert int(A().art().part) == 1 and int(A().art().page) == int(A().art().pages)
    bar(1); bar(1)
# a reply cut short: what came is shown, and said so
mode['cut'] = True
g.tap_label('Search'); type_text('ataturk'); answer_now()
g.tap(100, 64 + 8 + 10); answer_now()
lines = [str(ln.s) for ln in A().art().lines.values()]
assert str(A().screen()) == 'article' and any('did not arrive' in l for l in lines), lines[-3:]
mode['cut'] = mode['huge'] = mode['ascii'] = False
bar(1); bar(1)
g.restart()
assert 'Read before (3)' in g.texts() and 'Language: eo' in g.texts(), g.texts()    # Istanbul in en and in eo (kept once each), Random Topic

# offline packs: a small pack in wiki2pack.py's format, three files sorted by title
titles = sorted([f'Article {k:03d}' for k in range(300)] + ['Ankara', 'Apple', 'Zebra', 'Éclair'],
                key=lambda t: t.encode('utf-8').lower())
files, index = {}, []
for k in range(3):
    part = titles[k * 102:(k + 1) * 102]
    files[f'wen_a{k:03d}.txt'] = ''.join(f'{t}\t{t} is an article.\\nSecond line.\n' for t in part)
    index.append(f'wen_a{k:03d}.txt\t{part[0]}\t{part[-1]}\t{len(part)}')
for fn, text in files.items():
    g.store[fn] = text
g.store['wen_shards.tsv'] = '\n'.join(index) + '\n'
g.store['wen_info.txt'] = 'name=Test pack\nlang=en\narticles=304\nshards=3\n'
g.L.globals().ctx.storage.list = lambda self: g.L.table_from([k for k in g.store.keys()])
g.store['source.txt'] = None
g.restart()
assert str(A().screen()) == 'sources', A().screen()
t = g.texts()
assert 'Test pack' in t and any('304 articles' in x for x in t) and any(x.startswith('Online') for x in t), t
g.tap(100, 64 + 8 + 76 + 10)                       # the pack
assert str(A().screen()) == 'home' and A().source() is not None
assert any('Test pack' in x and 'offline' in x for x in g.texts())
# search by the start of a title, across a file boundary, letters folded
g.tap_label('Search'); type_text('article 10')
assert str(A().screen()) == 'results'
found = [str(r.title) for r in A().results().values()]
assert found == [f'Article {k}' for k in range(100, 110)], found
assert not requests or 'article 10' not in requests[-1][0]                # no network
g.tap(100, 64 + 8 + 10)
assert str(A().screen()) == 'article' and 'Article 100' in g.texts() and 'Article 100 is an article.' in g.texts()
bar(1); bar(1)
g.tap_label('Search'); type_text('ap')
assert [str(r.title) for r in A().results().values()] == ['Apple']
bar(1)
g.tap_label('Search'); type_text('zz')
assert len(list(A().results().values())) == 0 and 'No title starts with that.' in g.texts()
bar(1)
# random, then read before: from the pack, and Forget leaves the pack alone
g.tap_label('Random article')
assert str(A().screen()) == 'article'
bar(1)
before = [k for k in g.store.keys() if str(k).startswith('wen_')]
g.tap_label('Read before (5)')
assert 'Test pack' in g.texts()
bar(4); g.tap_label('Forget')
assert [k for k in g.store.keys() if str(k).startswith('wen_')] == before
bar(1)
# back to the sources: online again, remembered after a restart
g.tap_label('Online and other packs')
assert str(A().screen()) == 'sources'
g.tap(100, 64 + 8 + 10)
assert A().source() is None and any('wikipedia.org' in x for x in g.texts())
g.restart()
assert str(A().screen()) == 'home' and A().source() is None
g.no_err()
print('wikipedia tests passed')
