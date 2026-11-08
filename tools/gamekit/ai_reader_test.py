"""The optional AI questions, checked in a reading app built like RSS (Instapaper, Readwise,
wallabag): each app's test calls run(globals(), '<menu label>') at its end, with its own harness
(L, g, tap, tap_label, texts, key, row_y and a py_request(method, url, body, ...) stand-in).

Checks: Settings shows an AI cell and opens the AI page; with AI on (DeepSeek, from config.txt)
an article gets an AI button, Summarize sends the article to the service and the answer shows;
Back returns to the article; your own question with the Web on / Web off button (DeepSeek's
search first, its results with the question); your own buttons from ai_buttons.txt and from My
buttons; switched off, no AI button; Back on the first menu is left to the host (it asks whether
to leave the app).
"""
import json, os
from lupa import lua54

ANSWER = '## Gist\n\nThe article says two things:\n- one\n- two'


def run(ns, menu_label, app):
    L = ns['L']
    tap, texts, key = ns['tap'], ns['texts'], ns['key']
    row_y = ns['row_y']
    here = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'apps', app)
    src = os.path.join(here, 'index.lua').replace(os.sep, '/')
    sent = []
    plain = L.globals().py_request

    def ai_request(method, url, body, *rest):
        if str(url) == 'https://api.deepseek.com/v1/tools/search':
            sent.append((str(method), str(url), str(body)))
            return 200, json.dumps({'results': [{'title': 'Fresh news', 'url': 'https://news.example/1', 'summary': 'It happened today.'}]})
        if str(url).startswith('https://api.deepseek.com/'):
            sent.append((str(method), str(url), str(body)))
            if 'reply only with one web search query' in str(body):   # the model writes the search query
                return 200, json.dumps({'choices': [{'message': {'content': '"fresh news about it"'}}]})
            return 200, json.dumps({'choices': [{'message': {'content': ANSWER}}]})
        return plain(method, url, body, *rest)

    def to_py(v):
        if lua54.lua_type(v) != 'table':
            return v
        keys = list(v.keys())
        if keys and all(isinstance(k, int) for k in keys):
            return [to_py(v[k]) for k in sorted(keys)]
        return {k: to_py(v[k]) for k in keys}

    L.globals().py_request = ai_request
    L.globals().py_json_encode = lambda t: json.dumps(to_py(t), ensure_ascii=False)
    L.execute("ctx.json.encode = function(self, v) return py_json_encode(v) end")
    # the app's folder on the card (ai_buttons.txt), when the harness has none
    L.execute("if not ctx.files then aifiles = {}; ctx.files = { path = '/AppFiles/test', "
              "exists = function(self, n) return aifiles[n] ~= nil end, read = function(self, n) return aifiles[n] end, "
              "write = function(self, n, d) aifiles[n] = d; return true end, remove = function(self, n) aifiles[n] = nil; return true end } "
              "else aifiles = nil end")
    typed = L.eval("function(s) local i = inputs[#inputs]; inputs[#inputs] = nil; if type(i) == 'table' then i = i.fn end; i(ctx, s) end")
    L.execute("if ctx.screen and ctx.screen.set_orientation then ctx.screen:set_orientation('portrait') end")
    base = str(ns['g'].store['config.txt']).replace('screen=landscape', 'screen=portrait')
    assert 'aion' not in base, base
    on_input = L.eval("function(k) fake_ms = fake_ms + 300; return on_input(ctx, {type='key', key=k}) end")

    def restart(cfg):
        L.globals().store['config.txt'] = cfg
        L.execute(f"dofile([[{src}]])")
        g = L.globals()
        g.pending = L.table()
        g.on_load(g.ctx)
        g.flush()
        ns['g'] = g
        return g

    def tap_label(label):
        r = {str(v.s): (int(v.x), int(v.y)) for v in ns['draw']().values()}
        assert label in r, (label, list(r))
        x, y = r[label]
        tap(x + 5, y + 5)

    def open_article():
        tap_label(menu_label)
        ns['g'].flush()
        tap(100, row_y(0))
        ns['g'].flush()

    # off: Settings has an AI cell saying so; no AI button on an article
    g = restart(base)
    open_article()
    t = texts()
    assert 'AI' not in t and 'Back' in t, t
    for _ in range(4):
        key('back')
    assert on_input('back') is False, texts()               # the first menu: the host asks whether to leave
    tap_label('Settings')
    t = texts()
    assert 'AI' in t and 'off' in t, t
    assert all(int(v.y) <= 800 - 48 for v in ns['draw']().values()), [(str(v.s), int(v.y)) for v in ns['draw']().values()]
    r = {str(v.s): (int(v.x), int(v.y)) for v in ns['draw']().values()}
    x, y = r['AI']
    tap(x + 5, y + 30)
    t = texts()
    assert 'Service' in t and 'Claude' in t and 'Test the connection' in t, t
    assert all(int(v.y) <= 800 - 48 for v in ns['draw']().values()), [(str(v.s), int(v.y)) for v in ns['draw']().values()]
    key('back')
    assert 'AI' in texts()

    # on (DeepSeek): the article's AI button, Summarize with the article, the answer
    g = restart(base + '\naion=1\naiprov=deepseek\naikey=sk-test-1234567890')
    open_article()
    t = texts()
    assert 'AI' in t, t
    longest = max((s for s in t if ' ' in s), key=len)          # a line of the article
    tap_label('AI')
    t = texts()
    assert 'Ask DeepSeek' in t and 'Summarize' in t and 'Your question' in t, t
    tap_label('Summarize')
    g.flush()
    method, url, body = sent[-1]
    b = json.loads(body)
    assert method == 'POST' and url == 'https://api.deepseek.com/v1/chat/completions' and b['model'] == 'deepseek-flash', (method, url)
    sysm = b['messages'][0]['content']
    assert longest in sysm and 'Title: ' in sysm, (longest, sysm[:400])
    t = texts()
    assert '» Summarize' in t and 'Gist' in t and '• one' in t and 'More' in t and 'Ask' not in t, t
    key('back')
    t = texts()
    assert 'AI' in t and longest in t, t
    tap_label('AI')
    assert '» Summarize' in texts()                         # the conversation is kept

    # the web search switch at the top of the ready questions (More): on for the next questions,
    # ready ones and your own, first and follow-ups; DeepSeek's search first
    t = texts()
    assert t[:4] == ['Back', 'Prev', 'Next', 'More'] or ('More' in t and 'Ask' not in t and 'Web' not in t), t
    tap_label('More')
    t = texts()
    assert 'Web search: off' in t and 'Your question' in t and 'Ask + web search' not in t, t
    tap_label('Web search: off')
    assert 'Web search: on' in texts()
    n0 = len(sent)
    tap_label('Your question'); typed('What is new about it?'); ns['g'].flush()
    assert [x[1] for x in sent[n0:]] == ['https://api.deepseek.com/v1/chat/completions', 'https://api.deepseek.com/v1/tools/search',
                                         'https://api.deepseek.com/v1/chat/completions'], sent[n0:]
    qm, am = json.loads(sent[n0][2])['messages'], json.loads(sent[n0 + 2][2])['messages']
    assert qm[0] == am[0] and longest in qm[0]['content'], qm[0]['content'][:300]     # the whole article, the same system text
    assert qm[-1]['content'].startswith('What is new about it?\n\n[Before answering'), qm[-1]
    assert json.loads(sent[n0 + 1][2]) == {'query': 'fresh news about it', 'ori_question': 'What is new about it?', 'count': 5}
    q = json.loads(sent[-1][2])['messages'][-1]['content']
    assert q.startswith('What is new about it?\n\nWeb search results') and 'Fresh news (https://news.example/1)' in q, q
    assert '» What is new about it? (web search)' in texts(), texts()
    tap_label('More')                                       # still on: a ready question searches too
    assert 'Web search: on' in texts()
    n0 = len(sent)
    tap_label('Background'); ns['g'].flush()
    assert [x[1].rsplit('/', 1)[-1] for x in sent[n0:]] == ['completions', 'search', 'completions'], sent[n0:]
    assert json.loads(sent[n0][2])['messages'][-1]['content'].startswith('What background or context')
    assert '» Background (web search)' in texts(), texts()
    tap_label('More'); tap_label('Web search: on')          # off: the next one only asks
    n0 = len(sent)
    tap_label('Your question'); typed('And without?'); ns['g'].flush()
    assert [x[1] for x in sent[n0:]] == ['https://api.deepseek.com/v1/chat/completions'], sent[n0:]
    key('back')

    # your own buttons: ai_buttons.txt in the app's folder, and edited under Settings → AI → My buttons
    files = L.globals().aifiles if L.globals().aifiles is not None else L.globals().files
    if files is not None:
        files['ai_buttons.txt'] = '# mine\nSky | Why is the sky blue?\n'
        tap_label('AI'); tap_label('More')                     # the conversation is open: More for the questions
        assert 'Sky' in texts(), texts()
        tap_label('Sky'); ns['g'].flush()
        assert json.loads(sent[-1][2])['messages'][-1]['content'] == 'Why is the sky blue?'
        assert '» Sky' in texts()
        key('back')
        for _ in range(4):
            key('back')
        tap_label('Settings')
        r = {str(v.s): (int(v.x), int(v.y)) for v in ns['draw']().values()}
        x, y = r['AI']
        tap(x + 5, y + 30)
        assert '1 of 6' in texts(), texts()
        tap_label('1 of 6')
        t = texts()
        assert 'My buttons' in t and 'Sky' in t and 'Add a button' in t, t
        tap_label('Add a button'); typed('Short | Say it in one sentence.')
        tap_label('Sky'); typed('')                            # emptied: deleted
        t = texts()
        assert 'Short' in t and 'Sky' not in t, t
        assert str(files['ai_buttons.txt']).endswith('Short | Say it in one sentence.\n'), files['ai_buttons.txt']
        assert all(int(v.y) <= 800 - 48 for v in ns['draw']().values())
        key('back'); key('back')
    print(f'{app}: AI questions OK')
