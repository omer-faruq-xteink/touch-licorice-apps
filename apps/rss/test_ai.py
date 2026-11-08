"""Offline test of RSS's optional AI questions (src/ai.lua and the screens in src/main.lua) under
Lua 5.4 (lupa): the requests built for Claude, OpenAI-compatible servers and Gemini, the answers
read back, Settings → AI, ai.txt, and that nothing of it shows while it is off.

  python -I apps/rss/test_ai.py
"""
import json, os, subprocess, sys
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
subprocess.run([sys.executable, '-I', os.path.join(HERE, 'bundle.py')], check=True, stdout=subprocess.DEVNULL)
L = lua54.LuaRuntime(unpack_returned_tuples=True)


def to_py(v):
    if lua54.lua_type(v) == 'table' and v == L.globals().NULL:
        return None
    if lua54.lua_type(v) != 'table':
        return v
    keys = list(v.keys())
    if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        return [to_py(v[k]) for k in range(1, len(keys) + 1)]
    return {k: to_py(v[k]) for k in keys}


sent = []          # (url, method, headers, body) of every request
answers = {}       # url part -> (status, body) for the next request that matches


def fake_request(url, method, headers, body):
    sent.append((url, method, to_py(headers) or {}, body))
    for k in list(answers):
        if k in url:
            st, b = answers[k]
            return st, b if isinstance(b, str) else json.dumps(b)
    if '/api/list' in url:
        return 200, json.dumps({'title': 'Unread', 'page': 1, 'has_more': False, 'items': [
            {'id': '7', 'title': 'Big story', 'feed': 'News', 'date': '2026-11-08', 'read': False, 'excerpt': 'x'}]})
    if '/api/article/7' in url:
        return 200, json.dumps({'id': '7', 'title': 'Big story', 'feed': 'News', 'date': '2026-11-08',
                                'url': 'https://example.com/big', 'text': 'First paragraph.\n\n[[img:1]]\n\nSecond paragraph.'})
    if url.split('?')[0].endswith('/api'):
        return 200, '{"title":"x"}'
    return 404, '{"error":"not found"}'


L.globals().py_request = fake_request
L.globals().py_encode = lambda t: json.dumps(to_py(t), ensure_ascii=False)
def _nulls(v):
    if v is None: return L.globals().NULL
    if isinstance(v, dict): return {k: _nulls(x) for k, x in v.items()}
    if isinstance(v, list): return [_nulls(x) for x in v]
    return v
L.globals().py_decode = lambda s: L.table_from(_nulls(json.loads(s)), recursive=True)

L.execute(r'''
drawn, store, files = {}, {}, {}
NULL = setmetatable({}, { __tostring = function() return 'null' end })
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
pending, inputs = {}, {}
local function font(name, lh) local f = M({ measure = function(s) return #s * 10 end }); f.name = name; f.line_height = lh; return f end
ctx = {
  invalidate = function() end, state = {},
  storage = M({ write = function(n, d) store[n] = d; return true end, read = function(n) if store[n] then return store[n] end return nil, 'not_found' end,
                remove = function(n) store[n] = nil; return true end,
                list = function() local t = {} for k in pairs(store) do t[#t + 1] = k end return t end }),
  files = M({ exists = function(n) return files[n] ~= nil end, read = function(n) return files[n] end,
              write = function(n, d) files[n] = d; return true end, remove = function(n) files[n] = nil; return true end,
              list = function() local t = {} for k, v in pairs(files) do t[#t + 1] = { name = k, size = #v } end return t end }),
  fonts = { small = font('small', 20), medium = font('medium', 24), large = font('large', 30) },
  input = M({ text = function(opts, fn) inputs[#inputs + 1] = { opts = opts, fn = fn } end }),
  net = M({ keep_wifi = function() end, request = function(opts, fn)
    assert(type(opts.url) == 'string' and type(fn) == 'function')
    assert(opts.method ~= 'GET' or opts.body == nil, 'GET with a body')
    assert(not opts.body or #opts.body <= 65536, 'body over 64 KB')
    local st, body = py_request(opts.url, opts.method or 'GET', opts.headers, opts.body)
    pending[#pending + 1] = function() fn(ctx, { ok = true, status = st, body = body, headers = {} }) end
    return M({ cancel = function() end })
  end }),
  json = M({ decode = function(s) return py_decode(s) end, encode = function(v) return py_encode(v) end }),
  capabilities = {},
  qr = M({ encode = function() error('no qr') end }),
  base64 = M({ encode = function(s) return s end }),
}
ctx.json.null = NULL
function flush() for _ = 1, 50 do local p = pending; pending = {}; if #p == 0 then return end; for _, f in ipairs(p) do f() end end end
function typed(s) local i = table.remove(inputs, 1); assert(i, 'no keyboard open'); i.fn(ctx, s) end
fake_ms = 1000
ctx.clock = M({ millis = function() return fake_ms end, now = function() return { offset_minutes = 0 } end })
''')

# ------------------------------------------------------------------ ai.lua on its own
A = L.execute(f"return dofile([[{os.path.join(HERE, '..', '..', 'tools', 'gamekit', 'ai.lua').replace(os.sep, '/')}]])")
_cfg = L.eval("function(t) local c = { aion = true, aiprov = 'claude', aiurl = '', aikey = 'k', aimodel = '', ailang = '', aiextra = '' } for k, v in pairs(t or {}) do c[k] = v end return c end")
cfg = lambda d: _cfg(L.table_from(d) if d else None)
_J = L.eval("function(extra) return { encode = function(v) return ctx.json:encode(v) end, extra = extra, null = NULL } end")
J = lambda extra=None: _J(L.table_from(_nulls(extra), recursive=True) if extra else None)
enc = J()
dec = L.eval("function(s) return ctx.json:decode(s) end")
art = L.table_from({'title': 'T', 'feed': 'F', 'url': 'https://e.com/a', 'text': 'Body text.\n\n[[img:3]]\n\nMore.'})
msgs = L.table_from([L.table_from({'role': 'user', 'text': 'Q1'}), L.table_from({'role': 'assistant', 'text': 'A1'}),
                     L.table_from({'role': 'user', 'text': 'Q2'})])

o = A.request(cfg(None), art, msgs, enc)
b = json.loads(o.body)
h = to_py(o.headers)
assert o.url == 'https://api.anthropic.com/v1/messages' and o.method == 'POST', o.url
assert h['x-api-key'] == 'k' and h['anthropic-version'] == '2023-06-01' and h['content-type'] == 'application/json', h
assert h['anthropic-beta'] == 'server-side-fallback-2026-07-01' and b['fallbacks'] == 'default', (h, b)
assert b['model'] == 'claude-opus-5-5' and b['output_config'] == {'effort': 'low'} and b['max_tokens'] == 4096, b
assert [m['role'] for m in b['messages']] == ['user', 'assistant', 'user'] and b['messages'][2]['content'] == 'Q2', b['messages']
assert 'Body text.' in b['system'] and 'More.' in b['system'] and '[[img' not in b['system'] and 'Link: https://e.com/a' in b['system'], b['system']
assert 'Answer in' not in b['system']

o = A.request(cfg({'aimodel': 'claude-haiku-4-5', 'ailang': 'Turkish'}), art, msgs, enc)
b = json.loads(o.body)
assert 'output_config' not in b and 'fallbacks' not in b and 'anthropic-beta' not in to_py(o.headers), b
assert 'Answer in Turkish.' in b['system']

o = A.request(cfg({'aiprov': 'openrouter', 'aimodel': 'x/y'}), art, msgs, enc)
b = json.loads(o.body)
assert o.url == 'https://openrouter.ai/api/v1/chat/completions' and to_py(o.headers)['Authorization'] == 'Bearer k', o.url
assert b['model'] == 'x/y' and [m['role'] for m in b['messages']] == ['system', 'user', 'assistant', 'user'], b
o = A.request(cfg({'aiprov': 'ollama', 'aiurl': 'http://192.168.1.5:11434/v1/', 'aikey': ''}), art, msgs, enc)
assert 'Authorization' not in to_py(o.headers) and o.url == 'http://192.168.1.5:11434/v1/chat/completions', o.url
assert json.loads(o.body)['model'] == 'llama3.2'
o = A.request(cfg({'aiprov': 'deepseek'}), art, msgs, enc)
assert o.url == 'https://api.deepseek.com/v1/chat/completions' and json.loads(o.body)['model'] == 'deepseek-flash', o.url

# ready: an address, and a key where the service needs one
assert A.ready(cfg(None)) and not A.ready(cfg({'aikey': ''})) and not A.ready(cfg({'aion': False}))
assert not A.ready(cfg({'aiprov': 'other', 'aikey': ''})) and A.ready(cfg({'aiprov': 'other', 'aikey': '', 'aiurl': 'https://x/v1'}))
assert not A.ready(cfg({'aiprov': 'ollama'})) and A.ready(cfg({'aiprov': 'ollama', 'aikey': '', 'aiurl': 'http://h:11434/v1'}))

# Extra parameters: merged into the body, nested objects merged, null removes a field
o = A.request(cfg(None), art, msgs, J({'max_tokens': 800, 'output_config': {'effort': 'medium'}, 'fallbacks': None}))
b = json.loads(o.body)
assert b['max_tokens'] == 800 and b['output_config'] == {'effort': 'medium'} and 'fallbacks' not in b, b
o = A.request(cfg({'aiprov': 'gemini'}), art, msgs, J({'generationConfig': {'thinkingConfig': {'thinkingBudget': 0}}}))
assert json.loads(o.body)['generationConfig'] == {'thinkingConfig': {'thinkingBudget': 0}}
o = A.request(cfg({'aiprov': 'deepseek'}), art, msgs, J({'temperature': 0.3}))
assert json.loads(o.body)['temperature'] == 0.3
def xres(sv):
    r = A.extra(sv, dec)
    return r if isinstance(r, tuple) else (r, None)
assert xres('') == (None, None) and xres('  ') == (None, None)
assert to_py(xres('{"a": {"b": 1}}')[0]) == {'a': {'b': 1}}
assert xres('[1, 2]')[1] == 'Extra parameters: a JSON object {...} is needed' and xres('nope')[1] == 'Extra parameters: not valid JSON'

o = A.request(cfg({'aiprov': 'gemini'}), art, msgs, enc)
b = json.loads(o.body)
assert o.url == 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent', o.url
assert to_py(o.headers)['x-goog-api-key'] == 'k' and 'Body text.' in b['systemInstruction']['parts'][0]['text'], b
assert [c['role'] for c in b['contents']] == ['user', 'model', 'user'] and b['contents'][2]['parts'][0]['text'] == 'Q2', b

# a long article and a long conversation still fit in one request; the first question stays
big = L.table_from({'title': 'T', 'text': 'ü' * 60000})
many = L.table_from([L.table_from({'role': 'user' if i % 2 == 0 else 'assistant', 'text': f'm{i} ' + 'x' * 4000}) for i in range(21)])
o = A.request(cfg(None), big, many, enc)
b = json.loads(o.body)
assert len(o.body.encode()) <= 60000 and b['messages'][0]['content'].startswith('m0 ') and b['messages'][-1]['content'].startswith('m20 '), len(o.body)
assert b['messages'][0]['role'] == 'user' and len(b['messages']) % 2 == 1, len(b['messages'])
assert 'only its beginning' in b['system']

def ans(c, st, body):
    r = A.answer(cfg(c), L.table_from({'status': st, 'body': json.dumps(body)}), dec)
    return r if isinstance(r, tuple) else (r, None)
assert ans(None, 200, {'content': [{'type': 'thinking', 'thinking': ''}, {'type': 'text', 'text': ' Hello '}], 'stop_reason': 'end_turn'})[0] == 'Hello'
assert ans(None, 200, {'content': [{'type': 'text', 'text': 'Cut'}], 'stop_reason': 'max_tokens'})[0] == 'Cut …'
assert ans(None, 200, {'content': [], 'stop_reason': 'refusal'}) == (None, 'the model declined to answer')
t, why = ans(None, 401, {'type': 'error', 'error': {'type': 'authentication_error', 'message': 'invalid x-api-key'}})
assert t is None and why == 'HTTP 401: the key was not accepted: invalid x-api-key', why
assert ans({'aiprov': 'openai'}, 200, {'choices': [{'message': {'role': 'assistant', 'content': 'Hi'}}]})[0] == 'Hi'
assert ans({'aiprov': 'gemini'}, 200, {'candidates': [{'content': {'parts': [{'text': 'thinking', 'thought': True}, {'text': 'Yo'}]}}]})[0] == 'Yo'
assert ans({'aiprov': 'gemini'}, 200, {'promptFeedback': {'blockReason': 'SAFETY'}}) == (None, 'blocked: SAFETY')
t, why = A.answer(cfg(None), L.table_from({'status': 502, 'body': '<html>bad gateway</html>'}), dec)
assert t is None and why.startswith('HTTP 502'), why

assert A.plain('## Head\n\n**Bold** and `code`\n- one\n* two\n\n\n\nend') == '# Head\n\nBold and code\n• one\n• two\n\nend', A.plain('## Head')
f = to_py(A.read_file('key = sk-1\r\nkind=OpenAI compatible\nurl=https://x/v1\nmodel=m\n# a comment\n'))
assert f == {'aikey': 'sk-1', 'aiprov': 'other', 'aiurl': 'https://x/v1', 'aimodel': 'm', 'aion': True}, f
f = to_py(A.read_file('service=DeepSeek\nkey=sk-d\nextra={"temperature":0.3}'))
assert f == {'aiprov': 'deepseek', 'aikey': 'sk-d', 'aiextra': '{"temperature":0.3}', 'aion': True}, f
assert to_py(A.read_file('kind=Anthropic\nkey=a'))['aiprov'] == 'claude' and to_py(A.read_file('url=http://h/v1'))['aiprov'] == 'other'
assert to_py(A.read_file('key=x\non=0'))['aion'] is False and A.read_file('nothing here') is None
# web search: offered where the service has it; each one's own way
def webj():
    j = J()
    j.web = True
    return j
assert A.web_ok(cfg(None)) and A.web_ok(cfg({'aiprov': 'deepseek'})) and A.web_ok(cfg({'aiprov': 'openrouter'}))
assert not A.web_ok(cfg({'aiprov': 'groq'})) and not A.web_ok(cfg({'aiprov': 'other', 'aiurl': 'https://x/v1'}))
assert list(A.chat_bar(cfg(None)).values()) == ['Back', 'Prev', 'Next', 'More']
b = json.loads(A.request(cfg(None), art, msgs, webj()).body)
assert b['tools'] == [{'type': 'web_search_20250305', 'name': 'web_search', 'max_uses': 2}], b.get('tools')
b = json.loads(A.request(cfg({'aiprov': 'openrouter'}), art, msgs, webj()).body)
assert b['tools'] == [{'type': 'openrouter:web_search', 'parameters': {'max_results': 5}}] and b['messages'][0]['role'] == 'system', b
o = A.request(cfg({'aiprov': 'gemini'}), art, msgs, webj())
b = json.loads(o.body)
assert b['tools'] == [{'google_search': {}}] and 'contents' in b, b.get('tools')
o = A.request(cfg({'aiprov': 'openai'}), art, msgs, webj())
b = json.loads(o.body)
assert o.url == 'https://api.openai.com/v1/responses' and b['tools'] == [{'type': 'web_search'}], o.url
assert 'Body text.' in b['instructions'] and [m['role'] for m in b['input']] == ['user', 'assistant', 'user'], b
b = json.loads(A.request(cfg({'aiprov': 'deepseek'}), art, msgs, webj()).body)
assert 'tools' not in b                                        # DeepSeek: the app searches first
assert A.web_first(cfg({'aiprov': 'deepseek'})) and not A.web_first(cfg(None))
# DeepSeek: the model writes the search query first: the answer's own request (the same system
# text with the whole article, the same conversation) with an instruction after the question
qo = A.query_request(cfg({'aiprov': 'deepseek'}), art, msgs, enc)
qb = json.loads(qo.body)
main = json.loads(A.request(cfg({'aiprov': 'deepseek'}), art, msgs, enc).body)
assert qo.url == 'https://api.deepseek.com/v1/chat/completions' and qb['model'] == 'deepseek-flash' and qb['max_tokens'] == 60, qo.url
assert qb['messages'][:-1] == main['messages'][:-1] and 'max_tokens' not in main, qb   # the same beginning: cached
assert qb['messages'][-1]['content'].startswith('Q2\n\n[Before answering: reply only with one web search query'), qb['messages'][-1]
qt = lambda content: A.query_text(cfg({'aiprov': 'deepseek'}), L.table_from({'status': 200, 'body': json.dumps({'choices': [{'message': {'content': content}}]})}), dec, art, 'What background helps?')
assert qt('"history of the Lisp language"') == 'history of the Lisp language'
assert qt('**lisp origins**\nbecause ...') == 'lisp origins', qt('**lisp origins**\nbecause ...')
assert qt('') == 'T What background helps?' and A.query_text(cfg({'aiprov': 'deepseek'}), None, dec, art, 'Q?') == 'T Q?'
# DeepSeek's search takes at most 128 characters: longer queries are cut after a whole word
long_q = 'what did the authors of this long essay about lisp say about macros and garbage collection in the nineteen seventies and later'
long_q = long_q + ' and what came after them'
assert len(long_q) > 128
sq = A.short_query(long_q)
assert len(sq) <= 128 and long_q.startswith(sq) and long_q[len(sq)] == ' ', sq
assert A.short_query('  a   b  ') == 'a b' and A.short_query('ğ' * 200) == 'ğ' * 128           # characters, not bytes
assert A.short_query('çok ' * 40) == ('çok ' * 32).strip()
assert len(qt(long_q + ' more words')) <= 128                               # the model's query, too long
ql = A.query_text(cfg({'aiprov': 'deepseek'}), None, dec, L.table_from({'title': 'A very long title ' * 10}), 'And the follow-up question?')
assert len(ql) <= 128, ql                                                   # the fallback, too long
sb = json.loads(A.search_request(cfg({'aiprov': 'deepseek'}), long_q * 3, enc.encode, 'And what about it? ' * 20).body)
assert len(sb['query']) <= 128 and len(sb['ori_question']) <= 128 and sb['ori_question'].startswith('And what about it?'), sb
o = A.search_request(cfg({'aiprov': 'deepseek'}), 'what is new?', enc.encode)
assert o.url == 'https://api.deepseek.com/v1/tools/search' and to_py(o.headers)['Authorization'] == 'Bearer k', o.url
assert json.loads(o.body) == {'query': 'what is new?', 'count': 5}, o.body
res = {'results': [{'title': 'News A', 'url': 'https://a.example/1', 'date': '2026-11-07', 'summary': 'Summary A.'},
                   {'title': 'News B', 'url': 'https://b.example/2', 'snippet': 'Snippet B.'}]}
t = A.search_text(L.table_from({'status': 200, 'body': json.dumps(res)}), dec)
assert t.startswith('Web search results') and '1. News A (https://a.example/1, 2026-11-07)\nSummary A.' in t and '2. News B (https://b.example/2)\nSnippet B.' in t, t
r = A.search_text(L.table_from({'status': 200, 'body': '{"results": []}'}), dec)
assert (r if isinstance(r, tuple) else (r,))[-1] == 'the search found nothing'
r = A.search_text(L.table_from({'status': 402, 'body': '{"error": {"message": "Insufficient Balance"}}'}), dec)
assert r[1] == 'search: HTTP 402: Insufficient Balance', r
assert ans({'aiprov': 'openai'}, 200, {'object': 'response', 'status': 'completed', 'output': [
    {'type': 'web_search_call', 'status': 'completed'},
    {'type': 'message', 'content': [{'type': 'output_text', 'text': 'Found it.', 'annotations': []}]}]})[0] == 'Found it.'
assert ans(None, 200, {'content': [{'type': 'server_tool_use'}], 'stop_reason': 'pause_turn'}) == (None, 'the search took too long: ask again')
assert ans(None, 200, {'content': [{'type': 'server_tool_use'}, {'type': 'web_search_tool_result'}, {'type': 'text', 'text': 'A'},
                                   {'type': 'text', 'text': 'B'}], 'stop_reason': 'end_turn'})[0] == 'AB'
c2 = _cfg(L.table_from({'aion': '1'}))
A.normalize(c2)
assert c2.aion is True

# your own buttons: "Label | question"; a line without | is its own label; # and blank lines left out
bs = A.parse_buttons('# mine\nSky | Why is the sky blue?\n\nA question with no label of its own at all here\nx|y\n' + 'L | q\n' * 9)
assert [(b.label, b.q) for b in bs.values()][:3] == [('Sky', 'Why is the sky blue?'), ('A question with no la…', 'A question with no label of its own at all here'), ('x', 'y')]
assert len(bs) == 6
items = [(str(i[1]), str(i[2])) for i in A['items'](cfg(None), False).values()]
assert items[0] == ('Web search: off', 'web') and items[-1] == ('Your question', 'own'), items
items = [str(i[1]) for i in A['items'](cfg(None), True, None, None, True).values()]
assert items[0] == 'Web search: on' and items[-1] == 'Start over', items
items = [str(i[1]) for i in A['items'](cfg({'aiprov': 'groq'}), True).values()]
assert not any(s.startswith('Web search') for s in items) and items[-1] == 'Start over', items
print('ai.lua: requests, answers, plain text, ai.txt OK')

# ------------------------------------------------------------------ the app
L.globals().store['config.txt'] = 'host=w.example\ntoken=t\nauth=\nfull=0\nsize=default\nimages=0\nscreen=portrait'
L.execute(f"dofile([[{os.path.join(HERE, 'index.lua').replace(os.sep, '/')}]])")
g = L.globals()
g.on_load(g.ctx); g.flush()
tap = L.eval("function(x, y) on_input(ctx, {type='pointer', phase='down', x=x, y=y}); on_input(ctx, {type='pointer', phase='up', gesture='tap', x=x, y=y}) end")
key = L.eval("function(k) fake_ms = fake_ms + 300; on_input(ctx, {type='key', key=k}) end")
draw = L.eval("function() drawn = {}; on_draw(ctx, gg); return drawn end")
def recs():
    return {str(r.s): (int(r.x), int(r.y)) for r in draw().values()}
texts = lambda: list(recs())
def tap_label(label):
    x, y = recs()[label]
    tap(x + 5, y + 5)
BAR5 = lambda i: (4 + (i - 1) * 94 + 30, 20)

def open_story():
    tap_label('CommaFeed'); tap_label('Unread'); g.flush()
    tap_label('Big story'); g.flush()

# off: no AI button in the article, Settings says off, nothing went to an AI service
open_story()
t = texts()
assert 'First paragraph.' in t and 'AI' not in t and 'Back' in t, t
key('back'); key('back'); key('back')
tap_label('Settings')
t = texts()
assert 'AI' in t and 'off' in t, t
assert str(g.store['config.txt']).endswith('screen=portrait'), g.store['config.txt']   # no AI lines while unused

# Settings → AI: switch on (needs a key), type a key, the Service cycles
x, y = recs()['AI']; tap(x + 5, y + 30)
t = texts()
assert 'Service' in t and 'Claude' in t and 'claude-opus-5-5' in t and '(none)' in t and 'Test the connection' in t, t
assert any('ai.txt' in s for s in t), t
tap_label('off')
assert 'aion=1' in str(g.store['config.txt']) and 'now add the key' in texts()
key('back')
assert 'not set up yet' in texts(), texts()
x, y = recs()['AI']; tap(x + 5, y + 30)
tap_label('(empty)')                                   # Key
g.typed('sk-ant-api03-abcdefghijklmnop-WXYZ ')
t = texts()
assert 'sk-ant…WXYZ  (34 characters)' in t, t
assert 'aikey=sk-ant-api03-abcdefghijklmnop-WXYZ\n' in str(g.store['config.txt']), g.store['config.txt']

# Service: the list of known services, Other last; choosing one gives its address and model
tap_label('Claude')
r = recs()
names = ['Claude (Anthropic)', 'OpenAI', 'Gemini (Google)', 'OpenRouter', 'Groq', 'Mistral', 'DeepSeek', 'Ollama (on your network)', 'Other (OpenAI-compatible)']
assert all(n in r for n in names) and r['Other (OpenAI-compatible)'][1] > r['DeepSeek'][1] and r['Other (OpenAI-compatible)'][1] + 40 < 774, r
tap_label('DeepSeek')
t = texts()
assert 'DeepSeek' in t and 'deepseek-flash' in t and 'api.deepseek.com/v1  (default)' in t and 'Key' in t, t
assert 'aiprov=deepseek' in str(g.store['config.txt'])
# Extra parameters: JSON only; a wrong one is not saved
tap_label('(none)'); g.typed('{"temperature": 0.3')
assert 'Extra parameters: not valid JSON (not saved)' in texts() and '(none)' in texts()
tap_label('(none)'); g.typed('{"temperature":0.3}')
assert '{"temperature":0.3}' in texts()
answers['api.deepseek.com'] = (200, {'choices': [{'message': {'role': 'assistant', 'content': 'OK'}}]})
tap_label('Test the connection'); g.flush()
assert 'works: "OK"' in texts() and json.loads(sent[-1][3])['temperature'] == 0.3 and sent[-1][0] == 'https://api.deepseek.com/v1/chat/completions', sent[-1]
# Other: its address is asked at once, with https:// to start from; the key may stay empty
tap_label('DeepSeek'); tap_label('Other (OpenAI-compatible)')
assert g.inputs[1].opts.text == 'https://' and '(none)' in texts()          # Extra cleared with the service
g.typed('https://llm.example.org/v1')
t = texts()
assert 'https://llm.example.org/v1' in t and '(server default)' in t and 'Other' in t, t
tap_label('Other'); tap_label('Claude (Anthropic)')
assert 'claude-opus-5-5' in texts() and 'api.anthropic.com/v1  (default)' in texts()

# the connection test answers in the status line
answers['/v1/messages'] = (200, {'content': [{'type': 'text', 'text': 'OK'}], 'stop_reason': 'end_turn'})
tap_label('Test the connection'); g.flush()
assert 'works: "OK"' in texts(), texts()
assert json.loads(sent[-1][3])['messages'][0]['content'] == 'Reply with the single word OK.'

# the article now has the AI button; it opens the ready questions
key('back'); key('back')
open_story()
assert 'AI' in texts(), texts()
tap(*BAR5(4))
t = texts()
assert 'Ask Claude' in t and 'Summarize' in t and 'Your question' in t and 'Translate' not in t and 'Start over' not in t, t

answers['/v1/messages'] = (200, {'content': [{'type': 'text', 'text': '## Gist\n\nThe story says **two** things:\n- one\n- two'}], 'stop_reason': 'end_turn'})
n = len(sent)
tap_label('Summarize')
assert 'Asking Claude…' in texts(), texts()
g.flush()
url, method, headers, body = sent[n]
b = json.loads(body)
assert url == 'https://api.anthropic.com/v1/messages' and method == 'POST' and headers['x-api-key'].startswith('sk-ant-'), (url, headers)
assert b['messages'] == [{'role': 'user', 'content': 'Summarize this article in a few short paragraphs.'}], b['messages']
assert 'First paragraph.' in b['system'] and 'Second paragraph.' in b['system'] and 'Title: Big story' in b['system'], b['system']
t = texts()
assert '» Summarize' in t and 'Gist' in t and 'The story says two things:' in t and '• one' in t, t
assert 'More' in t and 'Ask' not in t, t

# a follow-up question: the whole conversation goes along
answers['/v1/messages'] = (200, {'content': [{'type': 'text', 'text': 'Because of the second paragraph.'}], 'stop_reason': 'end_turn'})
tap_label('More'); tap_label('Your question')       # your own question: under More
g.typed('  Why?  ')
g.flush()
b = json.loads(sent[-1][3])
assert [m['role'] for m in b['messages']] == ['user', 'assistant', 'user'] and b['messages'][2]['content'] == 'Why?', b['messages']
t = texts()
assert '» Why?' in t and 'Because of the second paragraph.' in t, t

# a failed answer: the question goes, the reason shows, the conversation stays
answers['/v1/messages'] = (529, {'type': 'error', 'error': {'type': 'overloaded_error', 'message': 'Overloaded'}})
tap_label('More'); tap_label('Your question'); g.typed('And then?'); g.flush()
t = texts()
assert 'AI: HTTP 529: Overloaded' in t and '» And then?' not in t and '» Why?' in t, t

# More: the ready questions again, with Start over; Back returns to the conversation
tap(*BAR5(5))
assert 'Start over' in texts()
key('back')
assert '» Why?' in texts()
key('back')                                        # to the article; AI again opens the conversation
assert 'First paragraph.' in texts()
tap(*BAR5(4))
assert '» Why?' in texts()
tap(*BAR5(5)); tap_label('Start over')
assert 'Start over' not in texts() and 'Summarize' in texts()
key('back')
assert 'First paragraph.' in texts()

# an answer language adds Translate
key('back'); key('back'); key('back'); tap_label('Settings')
x, y = recs()['AI']; tap(x + 5, y + 30)
tap_label('(as asked)'); g.typed('Turkish')
key('back'); key('back')
open_story(); tap(*BAR5(4))
assert 'Translate' in texts()
answers['/v1/messages'] = (200, {'content': [{'type': 'text', 'text': 'Büyük haber.'}], 'stop_reason': 'end_turn'})
tap_label('Translate'); g.flush()
b = json.loads(sent[-1][3])
assert b['messages'][0]['content'] == 'Translate this article into Turkish.' and 'Answer in Turkish.' in b['system'], b
assert 'Büyük haber.' in texts()

# ai.txt (USB) is taken in when Settings → AI opens, and deleted
key('back'); key('back'); key('back'); key('back'); tap_label('Settings')
g.files['ai.txt'] = 'kind=gemini\nkey=AIza-secret-key-123456\nmodel=gemini-2.5-pro\n'
x, y = recs()['AI']; tap(x + 5, y + 30)
t = texts()
assert 'Gemini' in t and 'gemini-2.5-pro' in t and 'AIza-s…3456  (22 characters)' in t, t
assert g.files['ai.txt'] is None and 'aiprov=gemini' in str(g.store['config.txt']), g.files['ai.txt']
assert any('ai.txt' in s and 'deleted' in s for s in t), t

# switched off: the AI button is gone again
tap_label('on')
key('back'); key('back')
open_story()
assert 'AI' not in texts() and 'First paragraph.' in texts(), texts()
n = len(sent)
tap(*BAR5(4)); tap(326, 20)
assert len(sent) == n and 'Summarize' not in texts()

# landscape: the AI page and the ready questions fit 800 x 480
L.execute("ctx.screen = { width = 800, height = 480 }")
key('back'); key('back'); key('back'); tap_label('Settings')
x, y = recs()['AI']; tap(x + 5, y + 30)
tap_label('off')
assert all(y < 480 - 20 for _, y in recs().values()), recs()
key('back'); key('back')
open_story(); tap(*[4 + 3 * ((800 - 8) // 5) + 30, 20])     # the story's conversation is still there
assert 'Büyük haber.' in texts()
tap(4 + 4 * ((800 - 8) // 5) + 30, 20)                       # More
r = recs()
assert 'Summarize' in r and r['Your question'][1] + 42 < 480, r
print('rss AI tests passed')

# Back on the first menu is left to the host (it asks whether to leave the app); elsewhere it is the app's
back = L.eval("function() fake_ms = fake_ms + 300; return on_input(ctx, {type='key', key='back'}) end")
for _ in range(5):
    if 'Settings' in texts() and 'CommaFeed' in texts():
        break
    back()
assert 'CommaFeed' in texts() and back() is False, texts()
tap_label('CommaFeed')
assert back() is True and 'CommaFeed' in texts()
print('rss Back key OK')
