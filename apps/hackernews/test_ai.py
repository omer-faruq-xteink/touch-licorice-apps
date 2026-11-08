"""Offline test of Hacker News's optional AI questions (tools/gamekit/ai.lua with src/main.lua and
src/hn.lua) in the gamekit harness: nothing shows while AI is off; Settings → AI; the AI button on
a story and on its comments; what is sent by Send (Article + comments, Article, Comments, Link +
comments), the comments fetched once from Algolia (with a page that comes cut), their layout as
text, the conversation with follow-ups, and Back.

  python -I apps/hackernews/test_ai.py
"""
import json, os, re, sys, urllib.parse
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

NOW = 1793070000
BIG = 50242939
sent = []                     # (url, method, headers, body)
ai_answers = []               # bodies the AI service gives, in turn
cut_next = {'n': 0}           # comment pages that come cut (not JSON) first

STORY = {'by': 'pg', 'descendants': 5, 'id': BIG, 'kids': [50300203, 50300201], 'score': 512, 'time': NOW - 3 * 3600,
         'title': 'An essay about Lisp', 'type': 'story', 'url': 'https://www.example.com/lisp?x=1'}
COMMENTS = [  # Algolia's flat hits; the first level in HN's order is 203, then 201 (from the story's kids)
    {'objectID': '50300201', 'author': 'alice', 'parent_id': BIG, 'created_at_i': NOW - 3600, 'comment_text': 'It&#x27;s good.<p>Really.'},
    {'objectID': '50300301', 'author': 'carol', 'parent_id': 50300201, 'created_at_i': NOW - 1000, 'comment_text': 'Agreed.'},
    {'objectID': '50300302', 'author': 'dave', 'parent_id': 50300201, 'created_at_i': NOW - 2000, 'comment_text': 'Not <i>quite</i>.'},
    {'objectID': '50300203', 'author': 'bob', 'parent_id': BIG, 'created_at_i': NOW - 120, 'comment_text': 'Lisp forever.'},
    {'objectID': '50300999', 'author': 'eve', 'parent_id': 50300888, 'created_at_i': NOW - 50, 'comment_text': 'An orphan.'},
]


def answer(url, method, body):
    u = urllib.parse.urlsplit(url)
    q = dict(urllib.parse.parse_qsl(u.query))
    if method == 'POST' and 'reply only with one web search query' in (body or ''):   # the model writes the search query
        return {'ok': True, 'status': 200, 'body': json.dumps({'choices': [{'message': {'content': 'lisp essay news'}}]})}
    if method == 'POST' and url.endswith('/tools/search'):           # DeepSeek's web search
        return {'ok': True, 'status': 200, 'body': json.dumps({'results': [{'title': 'Fresh news', 'url': 'https://news.example/1', 'summary': 'Today.'}]})}
    if method == 'POST':
        return {'ok': True, 'status': 200, 'body': ai_answers.pop(0) if ai_answers else json.dumps({'choices': [{'message': {'content': 'OK'}}]})}
    if u.netloc == 'hacker-news.firebaseio.com':
        if u.path.endswith('stories.json'):
            return {'status': 200, 'body': json.dumps([BIG])}
        return {'status': 200, 'body': json.dumps(STORY)}
    if u.netloc == 'hn.algolia.com':
        if q['tags'].startswith('comment,'):
            assert q['tags'] == f'comment,story_{BIG}' and 'parent_id' in q['attributesToRetrieve'], q
            if cut_next['n'] > 0:
                cut_next['n'] -= 1
                return {'ok': True, 'status': 200, 'body': '{"hits":[{"author":"x","comment_text":"cut off her', 'err': 'limit_exceeded'}
            per, page = int(q['hitsPerPage']), int(q['page'])
            hits = COMMENTS[page * per:(page + 1) * per]
            return {'status': 200, 'body': json.dumps({'hits': hits, 'nbPages': (len(COMMENTS) + per - 1) // per, 'page': page})}
        return {'status': 200, 'body': json.dumps({'hits': [{'objectID': str(BIG), 'title': STORY['title'], 'url': STORY['url'],
                                                             'points': 512, 'num_comments': 5, 'author': 'pg', 'created_at_i': NOW - 3 * 3600}]})}
    if u.netloc == 'w.example':
        return {'status': 200, 'body': json.dumps({'text': '# The essay\n\nLisp is a family of languages.\n\nMore text.'})}
    raise AssertionError(url)


g = Game(HERE)
L = g.L
ctx = L.globals().ctx


def to_lua(v):
    if isinstance(v, dict):
        return L.table_from({k: to_lua(x) for k, x in v.items()})
    if isinstance(v, list):
        return L.table_from([to_lua(x) for x in v])
    return v


def to_py(v):
    if L.eval('function(v) return type(v) end')(v) != 'table':
        return v
    keys = list(v.keys())
    if keys and all(isinstance(k, int) for k in keys):
        return [to_py(v[k]) for k in sorted(keys)]
    return {k: to_py(v[k]) for k in keys}


def request(self, opts, fn):
    o = to_py(opts)
    sent.append((o['url'], o.get('method', 'GET'), o.get('headers') or {}, o.get('body')))
    assert o.get('method', 'GET') != 'GET' or o.get('body') is None
    assert o.get('body') is None or len(o['body'].encode()) <= 65536
    L.globals().pending_resp = to_lua(answer(o['url'], o.get('method', 'GET'), o.get('body')))
    L.globals().pending_fn = fn
    return L.table_from({'cancel': lambda self: None})


def decode(self, s):
    def rnd(x, key=None):           # as on the reader: numbers above 2^24 may come back rounded
        if isinstance(x, dict):
            return {k: rnd(y, k) for k, y in x.items()}
        if isinstance(x, list):
            return [rnd(y, key) for y in x]
        if isinstance(x, int) and x > 2 ** 24 and key in ('id', 'kids', 'parent', 'parent_id'):
            return float(x) + 3
        return x
    return to_lua(rnd(json.loads(s)))


ctx.net = L.table_from({'request': request, 'keep_wifi': lambda self, ms: None})
ctx.json = L.table_from({'decode': decode, 'encode': lambda self, v: json.dumps(to_py(v), ensure_ascii=False)})
L.execute("files = {}; ctx.files = { path = '/AppFiles/hackernews', exists = function(self, n) return files[n] ~= nil end, "
          "read = function(self, n) return files[n] end, remove = function(self, n) files[n] = nil; return true end, "
          "write = function(self, n, d) files[n] = d; return true end }")
L.execute(f"ctx.clock.now = function(self) return {{ epoch_sec = {NOW} }} end")
answer_one = L.eval('function() local f, r = pending_fn, pending_resp; pending_fn = nil; if f then f(ctx, r); return true end return false end')
back_key = L.eval("function() fake_ms = fake_ms + 300; return on_input(ctx, {type='key', key='back'}) end")
A = lambda: g.api


def answer_all(limit=100):
    n = 0
    while answer_one() and n < limit:
        n += 1
    return n


def typed(s): L.eval('inputs[#inputs]')(ctx, s)
def screen(): return str(A().screen())
def page_text(): return ' '.join(g.texts())
def last_ai(): return [x for x in sent if x[1] == 'POST'][-1]


g.store['settings.txt'] = 'host=w.example\ntoken=tok\nauth=\nsize=medium\nimages=off\nscreen=portrait'
g.restart(); answer_all()

# ------------------------------------------------------------------ hn.lua: the comments as text
N = A().N
hits = N.comment_hits(to_lua({'hits': COMMENTS}), json.dumps({'hits': COMMENTS}))
assert str(hits[2].parent) == '50300201' and str(hits[1].parent) == str(BIG), (hits[2].parent, hits[1].parent)
text, n = N.thread_text(hits, str(BIG), to_lua(['50300203', '50300201']), 52000)
assert text == ('bob: Lisp forever.\nalice: It\'s good. Really.\n  dave: Not quite.\n  carol: Agreed.\neve: An orphan.'), text
assert n == 5
text, n = N.thread_text(hits, str(BIG), to_lua(['50300203', '50300201']), 45)
assert text == 'bob: Lisp forever.\nalice: It\'s good. Really.\n[3 more comments are left out here.]' and n == 2, text

# ------------------------------------------------------------------ off: no AI anywhere
g.tap(100, 64 + 20); answer_all()
assert screen() == 'story' and 'AI' not in g.texts() and 'Lisp is a family of languages.' in page_text(), g.texts()
g.tap_label('5 comments'); answer_all()
assert screen() == 'thread' and 'AI' not in g.texts()
g.key('back'); g.key('back')
assert screen() == 'list'
assert back_key() is False and screen() == 'list'      # Back on the list: the host asks whether to leave

# ------------------------------------------------------------------ Settings → AI
g.tap_label('Settings')
t = g.texts()
assert 'AI' in t and 'off' in t, t
g.tap_label('off')
assert screen() == 'aiset' and 'AI (optional)' in g.texts() and 'Tap to test' in g.texts(), g.texts()
g.tap_label('off')                                          # on
assert A().cfg.aion and 'now add the key' in g.texts()
g.tap_label('Claude')
assert screen() == 'aiprov' and 'Other (OpenAI-compatible)' in g.texts()
g.tap_label('DeepSeek')
assert screen() == 'aiset' and 'deepseek-flash' in g.texts()
g.tap_label('(empty)'); typed('sk-deepseek-1234567890')
assert 'sk-dee…7890  (22 characters)' in g.texts(), g.texts()
assert 'aiprov=deepseek' in g.store['settings.txt'] and 'aikey=sk-deepseek-1234567890' in g.store['settings.txt']
g.tap_label('Tap to test'); answer_all()
assert 'Works: "OK"' in g.texts() and last_ai()[0] == 'https://api.deepseek.com/v1/chat/completions', (g.texts(), last_ai()[0])
assert last_ai()[2]['Authorization'] == 'Bearer sk-deepseek-1234567890'
g.key('back'); g.key('back')
assert screen() == 'list'

# ------------------------------------------------------------------ a story: AI, Send: Article + comments
g.tap(100, 64 + 20); answer_all()
assert 'AI' in g.texts() and '5 comments' in g.texts(), g.texts()
g.tap_label('AI')
t = g.texts()
assert screen() == 'aimenu' and 'Ask DeepSeek' in t and 'Send: Article + comments' in t, t
assert 'Summarize' in t and 'The discussion' in t and 'Disagreements' in t and 'Your question' in t and 'Start over' not in t, t
assert all(int(r.y) + 54 < 704 for r in g.draw() if str(r.s) not in ('Back',)), [(str(r.s), int(r.y)) for r in g.draw()]

ai_answers.append(json.dumps({'choices': [{'message': {'content': '**Gist**: Lisp.\n- one\n- two'}}]}))
cut_next['n'] = 1                                           # the first page of comments comes cut: asked again, 100 a page
n0 = len(sent)
g.tap_label('The discussion')
assert screen() == 'chat' and 'Getting the comments...' in g.texts(), g.texts()
answer_all()
asked = [x[0] for x in sent[n0:]]
assert 'hitsPerPage=200&page=0' in asked[0] and 'hitsPerPage=100&page=0' in asked[1] and asked[2].endswith('/chat/completions'), asked
b = json.loads(last_ai()[3])
sysm = b['messages'][0]['content']
assert b['model'] == 'deepseek-flash' and b['messages'][1]['content'].startswith('Summarize the discussion'), b
assert 'a Hacker News story and its comments' in sysm and 'Lisp is a family of languages.' in sysm and 'Link: https://www.example.com/lisp?x=1' in sysm, sysm
assert 'bob: Lisp forever.\nalice: It\'s good. Really.\n  dave: Not quite.\n  carol: Agreed.\neve: An orphan.' in sysm, sysm
t = g.texts()
assert '» The discussion' in t and 'Gist: Lisp.' in t and '• one' in t and 'More' in t and 'Ask' not in t, t

# a follow-up: no second fetch of the comments, the whole conversation goes along
ai_answers.append(json.dumps({'choices': [{'message': {'content': 'Because.'}}]}))
n0 = len(sent)
g.tap_label('More'); g.tap_label('Your question'); typed('  Why?  '); answer_all()
assert len(sent) == n0 + 1, sent[n0:]
b = json.loads(last_ai()[3])
assert [m['role'] for m in b['messages']] == ['system', 'user', 'assistant', 'user'] and b['messages'][3]['content'] == 'Why?', b['messages']
assert '» Why?' in g.texts() and 'Because.' in g.texts()

# a failed answer: the question goes, the reason shows
ai_answers.append(json.dumps({'error': {'message': 'Insufficient Balance'}}))
L.execute('x = 1')
g.tap_label('More'); g.tap_label('Your question'); typed('And?')
answer_one()
# the service's 402 comes as a body with an error; here with status 200 it is "an empty answer" or its message
t = g.texts()
assert any(s.startswith('AI: ') for s in t) and '» And?' not in t and '» Why?' in t, t

# Send: Article - no comments, no discussion questions
g.tap_label('More')
assert 'Start over' in g.texts()
g.tap_label('Send: Article + comments')
t = g.texts()
assert 'Send: Article' in t and 'The discussion' not in t and 'Summarize' in t, t
assert 'aisend=article' in g.store['settings.txt']
ai_answers.append(json.dumps({'choices': [{'message': {'content': 'Points.'}}]}))
g.tap_label('Key points'); answer_all()
sysm = json.loads(last_ai()[3])['messages'][0]['content']
assert 'Lisp is a family' in sysm and 'discussion' not in sysm and 'a Hacker News story on' in sysm, sysm

# Send: Comments - no article, no link, no article questions
g.tap_label('More'); g.tap_label('Send: Article')
t = g.texts()
assert 'Send: Comments' in t and 'Summarize' not in t and 'The discussion' in t, t
ai_answers.append(json.dumps({'choices': [{'message': {'content': 'Views.'}}]}))
g.tap_label('Disagreements'); answer_all()
sysm = json.loads(last_ai()[3])['messages'][0]['content']
assert 'Lisp is a family' not in sysm and 'Link:' not in sysm and 'bob: Lisp forever.' in sysm, sysm

# Send: Link + comments - the link, not the text
g.tap_label('More'); g.tap_label('Send: Comments')
assert 'Send: Link + comments' in g.texts()
ai_answers.append(json.dumps({'choices': [{'message': {'content': 'Guess.'}}]}))
g.tap_label('Summarize'); answer_all()
sysm = json.loads(last_ai()[3])['messages'][0]['content']
assert 'Link: https://www.example.com/lisp?x=1' in sysm and 'Only the link' in sysm and 'Lisp is a family' not in sysm and 'bob:' in sysm, sysm

# the web search switch at the top of the ready questions (More): on for the next questions
# (DeepSeek: its search first, after the comments); off again: they only ask
t = g.texts()
assert 'More' in t and 'Ask' not in t and 'Web' not in t, t
g.tap_label('More'); g.tap_label('Web search: off')
assert 'Web search: on' in g.texts()
ai_answers.append(json.dumps({'choices': [{'message': {'content': 'Searched.'}}]}))
n0 = len(sent)
g.tap_label('Your question'); typed('What happened today?'); answer_all()
assert [x[0].rsplit('/', 1)[-1] for x in sent[n0:]] == ['completions', 'search', 'completions'], sent[n0:]
qm, am = json.loads(sent[n0][3])['messages'], json.loads(sent[n0 + 2][3])['messages']
assert qm[0] == am[0] and 'bob: Lisp forever.' in qm[0]['content'], qm[0]['content'][:300]     # the article and comments: the same system text
assert qm[-1]['content'].startswith('What happened today?\n\n[Before answering'), qm[-1]
assert json.loads(sent[n0 + 1][3]) == {'query': 'lisp essay news', 'ori_question': 'What happened today?', 'count': 5}
q = json.loads(last_ai()[3])['messages'][-1]['content']
assert q.startswith('What happened today?\n\nWeb search results') and 'Fresh news' in q, q
assert '» What happened today? (web search)' in g.texts() and 'Searched.' in g.texts(), g.texts()
g.tap_label('More'); g.tap_label('Web search: on')
ai_answers.append(json.dumps({'choices': [{'message': {'content': 'Plain.'}}]}))
n0 = len(sent)
g.tap_label('Your question'); typed('And now?'); answer_all()
assert [x[0] for x in sent[n0:]] == ['https://api.deepseek.com/v1/chat/completions'], sent[n0:]

# your own buttons: ai_buttons.txt, after the ready questions
L.globals().files['ai_buttons.txt'] = 'Sky | Why is the sky blue?\n'
g.key('back')
assert screen() == 'story', screen()
g.tap_label('AI')
assert screen() == 'chat', screen()
g.tap_label('More')
t = g.texts()
assert 'Sky' in t and 'Web search: off' in t and 'Your question' in t, t
assert all(int(r.y) + 54 < 704 for r in g.draw() if str(r.s) != 'Back'), [(str(r.s), int(r.y)) for r in g.draw()]
ai_answers.append(json.dumps({'choices': [{'message': {'content': 'Rayleigh.'}}]}))
g.tap_label('Sky'); answer_all()
assert json.loads(last_ai()[3])['messages'][-1]['content'] == 'Why is the sky blue?', json.loads(last_ai()[3])['messages'][-1]
assert '» Sky' in g.texts()                         # the answer opens at its question
if 'Rayleigh.' not in g.texts(): g.tap_label('Next')
assert 'Rayleigh.' in g.texts(), g.texts()

# Start over; Back to the story; the comments' screen has AI too and comes back to them
g.tap_label('More'); g.tap_label('Start over')
assert 'Start over' not in g.texts() and screen() == 'aimenu'
g.key('back')
assert screen() == 'story'
g.tap_label('5 comments'); answer_all()
assert screen() == 'thread' and 'AI' in g.texts()
g.tap_label('AI')
assert screen() == 'aimenu'
g.key('back')
assert screen() == 'thread'

# ai.txt is taken in when Settings → AI opens, and deleted
g.key('back'); g.key('back'); g.key('back')
assert screen() == 'list', screen()
g.tap_label('Settings')
# My buttons, edited on the reader: added and deleted, written back to ai_buttons.txt
g.tap_label('DeepSeek')
g.tap_label('1 of 6')
assert screen() == 'aibtns' and 'Sky' in g.texts() and 'Add a button' in g.texts(), g.texts()
g.tap_label('Add a button'); typed('Short | In one sentence.')
g.tap_label('Sky'); typed('')
t = g.texts()
assert 'Short' in t and 'Sky' not in t and str(L.globals().files['ai_buttons.txt']).endswith('Short | In one sentence.\n'), t
g.key('back'); g.key('back')
assert screen() == 'settings'
L.globals().files['ai.txt'] = 'service=gemini\nkey=AIza-0123456789abcdef\n'
g.tap_label('DeepSeek')
assert 'Gemini' in g.texts() and L.globals().files['ai.txt'] is None and 'aiprov=gemini' in g.store['settings.txt'], g.texts()

# off again: the AI button is gone
g.tap_label('on')
g.key('back'); g.key('back')
g.tap(100, 64 + 20); answer_all()
assert 'AI' not in g.texts()
g.no_err()

# landscape (800 x 480, buttons from y 384): the AI page, the Service list and the ready questions fit
L.execute("ctx.screen = { width = 800, height = 480 }")
g.key('back'); g.tap_label('Settings'); g.tap_label('off')
def above_buttons():
    return [(str(r.s), int(r.x), int(r.y)) for r in g.draw() if str(r.s) != 'Back' and (int(r.y) + 22 > 384 or int(r.x) + 10 * len(str(r.s)) > 800)]
assert screen() == 'aiset' and not above_buttons(), above_buttons()
g.tap_label('Gemini')
assert screen() == 'aiprov' and not above_buttons(), above_buttons()
g.key('back'); g.tap_label('off'); g.key('back'); g.key('back')
g.tap(100, 64 + 20); answer_all(); g.tap_label('AI')
assert screen() == 'aimenu' and not above_buttons() and 'Your question' in g.texts(), above_buttons()
print('hackernews AI tests passed')
