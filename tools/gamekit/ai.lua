-- Asking an AI about the article on screen, shared by RSS and Hacker News (their bundle.py puts
-- it in as require('ai')): the services and the three kinds of interface they speak (Claude, any
-- OpenAI-compatible server, Gemini), the request each one takes and the answer each one gives,
-- and the logic of the Settings → AI page. Nothing here draws or touches the network: the app
-- sends what A.request builds and shows what A.value gives.
--
-- The settings live in the app's cfg: aion (boolean), aiprov, aiurl, aikey, aimodel, ailang,
-- aiextra (strings).
--
-- A conversation is a list of { role = 'user' | 'assistant', text = ... }. The article goes into
-- the system prompt, so every follow-up question still sees it.

local A = {}

-- The services offered in Settings → AI, in the list's order: each speaks one of the three kinds
-- of interface (claude, openai, gemini), with its own address and a model to start with (the
-- Model setting replaces it). Ollama and Other have no address of their own: it is asked when
-- they are chosen, and a key is optional there (local servers need none).
A.PROVIDERS = {
  { id = 'claude', label = 'Claude (Anthropic)', name = 'Claude', kind = 'claude', url = 'https://api.anthropic.com/v1', model = 'claude-opus-5-5' },
  { id = 'openai', label = 'OpenAI', name = 'OpenAI', kind = 'openai', url = 'https://api.openai.com/v1', model = 'gpt-5-mini' },
  { id = 'gemini', label = 'Gemini (Google)', name = 'Gemini', kind = 'gemini', url = 'https://generativelanguage.googleapis.com/v1beta', model = 'gemini-2.5-flash' },
  { id = 'openrouter', label = 'OpenRouter', name = 'OpenRouter', kind = 'openai', url = 'https://openrouter.ai/api/v1', model = 'openrouter/auto' },
  { id = 'groq', label = 'Groq', name = 'Groq', kind = 'openai', url = 'https://api.groq.com/openai/v1', model = 'llama-3.3-70b-versatile' },
  { id = 'mistral', label = 'Mistral', name = 'Mistral', kind = 'openai', url = 'https://api.mistral.ai/v1', model = 'mistral-small-latest' },
  { id = 'deepseek', label = 'DeepSeek', name = 'DeepSeek', kind = 'openai', url = 'https://api.deepseek.com/v1', model = 'deepseek-flash' },
  { id = 'ollama', label = 'Ollama (on your network)', name = 'Ollama', kind = 'openai', url = '', model = 'llama3.2', keyless = true,
    hint = 'http://192.168.1.' },
  { id = 'other', label = 'Other (OpenAI-compatible)', name = 'AI', short = 'Other', kind = 'openai', url = '', model = '', keyless = true,
    hint = 'https://' },
}
A.PROV = {}
for _, p in ipairs(A.PROVIDERS) do A.PROV[p.id] = p end

-- the ready questions: the button's name and what is asked
A.PRESETS = {
  { 'Summarize', 'Summarize this article in a few short paragraphs.' },
  { 'Key points', 'List the key points of this article.' },
  { 'Explain simply', 'Explain this article simply, for someone new to the subject.' },
  { 'Background', 'What background or context helps to understand this article?' },
  { 'What is missing?', 'What might this article leave out, and which of its claims are weak or one-sided?' },
}

-- more ready questions when a discussion goes along (Hacker News comments)
A.DISCUSSION = {
  { 'The discussion', 'Summarize the discussion in the comments: the main points of view and the most useful answers.' },
  { 'Disagreements', 'Where do the commenters disagree, and what are the strongest arguments on each side?' },
}

local ARTICLE_MAX = 24000      -- bytes of article text sent along
local BODY_MAX = 60000         -- the reader sends at most 65536 bytes
local COMMENTS_ROOM = 52000    -- article text and comments together, at most

-- s cut to at most n bytes, on a whole UTF-8 character
local function cut(s, n)
  if #s <= n then return s end
  local i = n
  while i > 0 and s:byte(i + 1) and s:byte(i + 1) >= 0x80 and s:byte(i + 1) < 0xC0 do i = i - 1 end
  return s:sub(1, i)
end
A.cut = cut

function A.prov(cfg) return A.PROV[cfg.aiprov] or A.PROV.claude end
function A.kind(cfg) return A.prov(cfg).kind end
function A.url(cfg) return ((cfg.aiurl ~= '' and cfg.aiurl or A.prov(cfg).url):gsub('/+$', '')) end
function A.model(cfg) return cfg.aimodel ~= '' and cfg.aimodel or A.prov(cfg).model end

-- switched on and able to ask: an address, and a key where the service needs one
function A.ready(cfg)
  if not cfg.aion or A.url(cfg) == '' then return false end
  return cfg.aikey ~= '' or A.prov(cfg).keyless == true
end

-- Extra parameters (Settings → AI): a JSON object merged into every request body, nested objects
-- into nested objects; null removes a field (e.g. {"fallbacks":null}). Returns the table, or nil
-- and why. decode is ctx.json's decode.
function A.extra(s, decode)
  if not s or not s:match('%S') then return nil end
  local ok, t = pcall(decode, s)
  if not ok or type(t) ~= 'table' then return nil, 'Extra parameters: not valid JSON' end
  if t[1] ~= nil then return nil, 'Extra parameters: a JSON object {...} is needed' end
  return t
end

local function merge(dst, src, null)
  for k, v in pairs(src) do
    if null ~= nil and v == null then dst[k] = nil
    elseif type(v) == 'table' and type(dst[k]) == 'table' and v[1] == nil then merge(dst[k], v, null)
    else dst[k] = v end
  end
end

-- the system prompt: how to answer on this screen, then the article
-- art: { title, feed, date, url, text, comments, what }. text is the article (may be empty: then
-- only its link is given); comments a discussion already written out as text (Hacker News);
-- what names the thing read ('an article' by default).
function A.system(cfg, art)
  local text = (art.text or ''):gsub('%[%[img:%d+%]%]', ''):gsub('\n\n\n+', '\n\n')
  local short = #text > ARTICLE_MAX
  text = cut(text, ARTICLE_MAX)
  local lines = {
    'You help someone who is reading ' .. (art.what or 'an article') .. ' on a small black-and-white e-reader.',
    'Reply in plain text: short paragraphs, "- " for list items, no tables, no code blocks, no links to follow.',
    'Be concise unless asked for more. If the text below seems to be only a summary, say so when it matters.',
  }
  if (cfg.ailang or '') ~= '' then lines[#lines + 1] = 'Answer in ' .. cfg.ailang .. '.' end
  lines[#lines + 1] = ''
  lines[#lines + 1] = 'Title: ' .. (art.title or '')
  if (art.feed or '') ~= '' then lines[#lines + 1] = 'Source: ' .. art.feed end
  if (art.date or '') ~= '' then lines[#lines + 1] = 'Date: ' .. art.date end
  if (art.url or '') ~= '' then lines[#lines + 1] = 'Link: ' .. art.url end
  lines[#lines + 1] = ''
  if text:match('%S') then
    lines[#lines + 1] = text .. (short and '\n\n[The article goes on; only its beginning is given here.]' or '')
  elseif (art.url or '') ~= '' then
    lines[#lines + 1] = '[Only the link of the article is given here, not its text: say so when it matters.]'
  end
  if art.comments and art.comments:match('%S') then
    local room = math.max(8000, COMMENTS_ROOM - #text)
    local c = art.comments
    if #c > room then c = cut(c, room) .. '\n[More comments follow; they are left out here.]' end
    lines[#lines + 1] = ''
    lines[#lines + 1] = 'The discussion (each comment as "author: text"; a reply is indented under the comment it answers):'
    lines[#lines + 1] = c
  end
  return table.concat(lines, '\n')
end

-- Claude's newest models take a few extras: low effort (quick answers) on the 5 family, and the
-- server-side fallback to another model where a model declines
local function claude_extras(model, body, headers)
  if model:match('^claude%-%a+%-5') then body.output_config = { effort = 'low' } end
  if model == 'claude-opus-5-5' or model == 'claude-opus-5' or model == 'claude-fable-5-1' or model == 'claude-sonnet-5-5' then
    body.fallbacks = 'default'
    headers['anthropic-beta'] = 'server-side-fallback-2026-07-01'
  end
end

local function body_for(kind, model, sys, msgs)
  if kind == 'claude' then
    local m = {}
    for _, x in ipairs(msgs) do m[#m + 1] = { role = x.role, content = x.text } end
    return { model = model, max_tokens = 4096, system = sys, messages = m }
  elseif kind == 'gemini' then
    local c = {}
    for _, x in ipairs(msgs) do c[#c + 1] = { role = x.role == 'assistant' and 'model' or 'user', parts = { { text = x.text } } } end
    return { systemInstruction = { parts = { { text = sys } } }, contents = c }
  end
  local m = { { role = 'system', content = sys } }
  for _, x in ipairs(msgs) do m[#m + 1] = { role = x.role, content = x.text } end
  return { model = model, messages = m }
end

local function message_of(d)
  if type(d) ~= 'table' then return nil end
  local e = d.error
  if type(e) == 'table' and e.message then return tostring(e.message) end
  if type(e) == 'string' then return e end
  return nil
end

-- Web search: a switch at the top of the ready questions (Web search: on / off), for every
-- question asked while it is on, the ready ones too; off again for each new article. Where the service
-- has it: Claude, Gemini and OpenRouter as a tool the model calls itself, OpenAI through its
-- Responses API, DeepSeek as a separate search the app makes first (A.search_request); the
-- others (Groq, Mistral, Ollama, Other) do not offer it here.
A.WEB = { claude = 'tool', gemini = 'tool', openrouter = 'tool', openai = 'responses', deepseek = 'search' }
function A.web_ok(cfg) return A.WEB[A.prov(cfg).id] ~= nil end
function A.web_first(cfg) return A.WEB[A.prov(cfg).id] == 'search' end

-- What DeepSeek's search looks for is written by the model first: a short query from the whole
-- article, the conversation and the question (a ready question such as "What background ...?"
-- says nothing of the article by itself). The request is the answer's own (the same system text
-- with the article, the same conversation) with an instruction after the question, so the answer
-- that follows starts the same way and DeepSeek serves that part from its cache. When it fails,
-- the article's title and the question are searched.
local QUERY_ASK = '[Before answering: reply only with one web search query (at most 12 words and under 100 characters) that finds what is'
  .. ' needed to answer this, using the article and the conversation above. No quotes, no explanation.]'
function A.query_request(cfg, art, msgs, J)
  local list = {}
  for i, m in ipairs(msgs) do list[i] = m end
  local last = list[#list]
  if not last or last.role ~= 'user' then return nil, 'no question' end
  list[#list] = { role = 'user', text = last.text .. '\n\n' .. QUERY_ASK }
  return A.request(cfg, art, list, { encode = J.encode, extra = J.extra, null = J.null, max_tokens = 60 })
end
-- the query from that answer, or the title and the question when there is none
function A.query_text(cfg, resp, decode, art, question)
  local text = resp and A.answer(cfg, resp, decode)
  local q = text and text:match('[^\n]*%S[^\n]*')
  if q then q = q:gsub('[%*`]', ''):gsub('^%s*[#>%-]*%s*', ''):gsub('^["\']+', ''):gsub('["\']+%s*$', ''):gsub('%s+$', '') end
  if not q or q == '' or #q > 200 then q = ((art.title or '') .. ' ' .. question):gsub('^%s+', '') end
  return A.short_query(q)
end

-- DeepSeek's search takes a query (and ori_question) of 1 to 128 Unicode characters: longer ones
-- are cut after a whole word
A.QUERY_MAX = 128
function A.short_query(q)
  q = tostring(q or ''):gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', '')
  local n = utf8.len(q)
  if not n then q = cut(q, A.QUERY_MAX); n = utf8.len(q) or #q end   -- not valid UTF-8: bytes
  if n <= A.QUERY_MAX then return q end
  local c = q:sub(1, (utf8.offset(q, A.QUERY_MAX + 1) or #q + 1) - 1)
  if q:sub(#c + 1, #c + 1) == ' ' then return c end              -- the cut fell between words
  return c:match('^(.*%S)%s+%S*$') or c
end

-- DeepSeek's search (POST /v1/tools/search, the same key): the request for a query, with the
-- question it serves (ori_question, which DeepSeek uses to rank the results)
function A.search_request(cfg, query, encode, question)
  local q = A.short_query(query)
  if q == '' then q = 'news' end
  local oq = question and A.short_query(question) or ''
  local body = encode(oq ~= '' and { query = q, ori_question = oq, count = 5 } or { query = q, count = 5 })
  if type(body) ~= 'string' then return nil, 'could not encode the search' end
  return { url = A.url(cfg) .. '/tools/search', method = 'POST', body = body,
           headers = { ['content-type'] = 'application/json', ['Authorization'] = 'Bearer ' .. (cfg.aikey or '') } }
end

-- its results as text to go with the question (at most about 6 KB), or nil and why
function A.search_text(resp, decode)
  if type(resp) ~= 'table' or type(resp.body) ~= 'string' then return nil, 'the search gave no answer' end
  local st = tonumber(resp.status)
  local ok, d = pcall(decode, resp.body)
  if st and st >= 400 then local m = ok and message_of(d); return nil, 'search: HTTP ' .. st .. (m and (': ' .. m) or '') end
  if not ok or type(d) ~= 'table' or type(d.results) ~= 'table' or #d.results == 0 then return nil, 'the search found nothing' end
  local out = { 'Web search results (use them when they help, and name the source):' }
  for k, r in ipairs(d.results) do
    if type(r) == 'table' then
      local head = k .. '. ' .. tostring(r.title or '') .. ' (' .. tostring(r.url or '') .. (r.date and r.date ~= '' and (', ' .. tostring(r.date)) or '') .. ')'
      out[#out + 1] = head .. '\n' .. cut(tostring(r.summary or r.snippet or ''), 1100)
    end
  end
  return cut(table.concat(out, '\n\n'), 6000)
end

-- the request for the conversation so far: opts for ctx.net:request, or nil and why.
-- J: { encode = ctx.json's encode, extra = A.extra's table or nil, null = ctx.json.null,
-- web = true for a web search where the service runs it itself }. A conversation too long for
-- one request loses its oldest exchanges (the first question stays); the article is shortened last.
function A.request(cfg, art, msgs, J)
  local kind, model, base = A.kind(cfg), A.model(cfg), A.url(cfg)
  local key = cfg.aikey or ''
  local headers = { ['content-type'] = 'application/json' }
  local url
  if kind == 'claude' then
    url = base .. '/messages'
    headers['x-api-key'] = key
    headers['anthropic-version'] = '2023-06-01'
  elseif kind == 'gemini' then
    url = base .. '/models/' .. model .. ':generateContent'
    headers['x-goog-api-key'] = key
  else
    url = base .. '/chat/completions'
    if key ~= '' then headers['Authorization'] = 'Bearer ' .. key end
  end
  local web = J.web and A.WEB[A.prov(cfg).id] or nil
  if web == 'responses' then url = base .. '/responses' end
  local sys = A.system(cfg, art)
  local list = {}
  for i, x in ipairs(msgs) do list[i] = x end
  for _ = 1, 40 do
    local body = body_for(kind, model, sys, list)
    if kind == 'claude' then claude_extras(model, body, headers) end
    if J.max_tokens and kind == 'openai' then body.max_tokens = J.max_tokens end   -- a short answer (the search query)
    if web == 'responses' then                       -- OpenAI: the Responses API with its web_search tool
      local input = {}
      for _, x in ipairs(list) do input[#input + 1] = { role = x.role, content = x.text } end
      body = { model = model, instructions = sys, input = input, tools = { { type = 'web_search' } } }
    elseif web == 'tool' and kind == 'claude' then   -- the basic web search: quick enough for the reader's 60 s
      body.tools = { { type = 'web_search_20250305', name = 'web_search', max_uses = 2 } }
    elseif web == 'tool' and kind == 'openai' then   -- OpenRouter's server tool
      body.tools = { { type = 'openrouter:web_search', parameters = { max_results = 5 } } }
    end
    if type(J.extra) == 'table' then merge(body, J.extra, J.null) end
    local s = J.encode(body)
    if type(s) ~= 'string' then return nil, 'could not encode the question' end
    -- Gemini's tool is an empty object, which ctx.json writes only as [] (an empty table)
    if web == 'tool' and kind == 'gemini' then s = s:sub(1, -2) .. ',"tools":[{"google_search":{}}]}' end
    if #s <= BODY_MAX then return { url = url, method = 'POST', headers = headers, body = s } end
    if #list > 3 then
      table.remove(list, 2); table.remove(list, 2)          -- the oldest answer and question after the first
    else
      sys = cut(sys, math.max(2000, #sys - (#s - BODY_MAX) - 500))
    end
  end
  return nil, 'the question is too long'
end

-- the answer's text from the reply (resp from ctx.net:request, decode = ctx.json's decode), or nil
-- and a short reason
function A.answer(cfg, resp, decode)
  if type(resp) ~= 'table' then return nil, 'no answer' end
  local st, body = tonumber(resp.status), resp.body
  if type(body) ~= 'string' or body == '' then
    return nil, (resp.err and tostring(resp.err)) or (st and ('HTTP ' .. st)) or 'no answer'
  end
  local ok, d = pcall(decode, body)
  if not ok or type(d) ~= 'table' then return nil, (st and st >= 400 and ('HTTP ' .. st .. ' ') or 'not JSON: ') .. body:sub(1, 60) end
  if st and st >= 400 then
    local m = message_of(d)
    if st == 401 or st == 403 then m = 'the key was not accepted' .. (m and (': ' .. m) or '') end
    return nil, 'HTTP ' .. st .. (m and (': ' .. m) or '')
  end
  local kind, parts = A.kind(cfg), {}
  if kind == 'claude' then
    if d.stop_reason == 'refusal' then return nil, 'the model declined to answer' end
    for _, b in ipairs(type(d.content) == 'table' and d.content or {}) do
      if type(b) == 'table' and b.type == 'text' and type(b.text) == 'string' then parts[#parts + 1] = b.text end
    end
    if d.stop_reason == 'max_tokens' then parts[#parts + 1] = ' …' end
    if #parts == 0 and d.stop_reason == 'pause_turn' then return nil, 'the search took too long: ask again' end
  elseif kind == 'gemini' then
    local c = type(d.candidates) == 'table' and d.candidates[1]
    local content = type(c) == 'table' and c.content
    for _, p in ipairs(type(content) == 'table' and type(content.parts) == 'table' and content.parts or {}) do
      if type(p) == 'table' and type(p.text) == 'string' and not p.thought then parts[#parts + 1] = p.text end
    end
    if #parts == 0 and type(d.promptFeedback) == 'table' and d.promptFeedback.blockReason then
      return nil, 'blocked: ' .. tostring(d.promptFeedback.blockReason)
    end
  elseif type(d.output) == 'table' then             -- OpenAI's Responses API (web search)
    for _, item in ipairs(d.output) do
      if type(item) == 'table' and item.type == 'message' and type(item.content) == 'table' then
        for _, c in ipairs(item.content) do
          if type(c) == 'table' and c.type == 'output_text' and type(c.text) == 'string' then parts[#parts + 1] = c.text end
        end
      end
    end
    if d.status == 'incomplete' then parts[#parts + 1] = ' …' end
  else
    local c = type(d.choices) == 'table' and d.choices[1]
    local m = type(c) == 'table' and c.message
    if type(m) == 'table' and type(m.content) == 'string' then parts[1] = m.content end
  end
  local text = table.concat(parts):gsub('^%s+', ''):gsub('%s+$', '')
  if text == '' then return nil, message_of(d) or 'an empty answer' end
  return text
end

-- Markdown as this screen shows it: headings as "# ", list items as "• ", no bold or code marks.
-- Single line breaks stay (each line is laid out on its own), blank lines part paragraphs.
function A.plain(s)
  local out = {}
  for line in (s:gsub('\r', '') .. '\n'):gmatch('([^\n]*)\n') do
    local t = line:gsub('^%s+', '')
    local head = t:match('^#+%s+(.*)$')
    if head then t = '# ' .. head
    elseif t:match('^[%-%*%+]%s+') then t = '• ' .. t:gsub('^[%-%*%+]%s+', '')
    elseif t:match('^```') or t:match('^%-%-%-+$') or t:match('^%*%*%*+$') then t = '' end
    t = t:gsub('%*%*(.-)%*%*', '%1'):gsub('__(.-)__', '%1'):gsub('`', '')
    out[#out + 1] = t
  end
  return (table.concat(out, '\n'):gsub('\n\n\n+', '\n\n'))
end

-- ai.txt in the app's folder: service= (or kind=), url=, key=, model=, lang=, extra= (and on=0 to
-- keep it off); returns the settings it holds (keys as in cfg) or nil
function A.read_file(s)
  if type(s) ~= 'string' then return nil end
  local map = { kind = 'aiprov', service = 'aiprov', provider = 'aiprov', url = 'aiurl', address = 'aiurl', key = 'aikey',
                model = 'aimodel', lang = 'ailang', extra = 'aiextra', on = 'aion' }
  local out, n = {}, 0
  for line in (s:gsub('\r', '') .. '\n'):gmatch('([^\n]*)\n') do
    local k, v = line:match('^%s*(%a+)%s*=%s*(.-)%s*$')
    k = k and map[k:lower()]
    if k then out[k] = v; n = n + 1 end
  end
  if n == 0 then return nil end
  if out.aiprov then
    local k = out.aiprov:lower()
    if not A.PROV[k] then
      local found = (k:find('compat') or k:find('other')) and 'other' or k:find('anthropic') and 'claude' or k:find('google') and 'gemini' or nil
      if not found then for _, p in ipairs(A.PROVIDERS) do if k:find(p.id, 1, true) then found = p.id; break end end end
      k = found or 'other'
    end
    out.aiprov = k
  elseif out.aiurl then
    out.aiprov = 'other'
  end
  if out.aion then out.aion = not (out.aion == '0' or out.aion:lower() == 'off')
  else out.aion = true end
  return out
end

------------------------------------------------------------------ the Settings → AI page

A.SET = { { 'aion', 'AI' }, { 'aiprov', 'Service' }, { 'aiurl', 'Address' }, { 'aikey', 'Key' },
          { 'aimodel', 'Model' }, { 'ailang', 'Answer in' }, { 'aiextra', 'Extra parameters (JSON)' },
          { 'aibtn', 'My buttons' }, { 'aitest', 'Connection' } }
A.HALF = { aion = true, aiprov = true, aimodel = true, ailang = true, aibtn = true, aitest = true }   -- half a row in portrait
A.DEFAULTS = { aion = false, aiprov = 'claude', aiurl = '', aikey = '', aimodel = '', ailang = '', aiextra = '' }
-- aion comes from config.txt as '1' / '0'
function A.normalize(cfg) cfg.aion = cfg.aion == true or cfg.aion == '1' end

-- anything of it set (the app saves its AI lines only then)
function A.used(cfg)
  for k, v in pairs(A.DEFAULTS) do if cfg[k] ~= v then return true end end
  return false
end

-- the AI lines of the app's config.txt ("\naion=1\naiprov=..."), or '' while nothing is set
function A.cfg_lines(cfg)
  if not A.used(cfg) then return '' end
  return '\naion=' .. (cfg.aion and '1' or '0') .. '\naiprov=' .. cfg.aiprov .. '\naiurl=' .. cfg.aiurl .. '\naikey=' .. cfg.aikey
    .. '\naimodel=' .. cfg.aimodel .. '\nailang=' .. cfg.ailang .. '\naiextra=' .. cfg.aiextra
end

-- a field's value as the page shows it (the key only as its ends)
function A.value(cfg, k)
  local P = A.prov(cfg)
  if k == 'aion' then return cfg.aion and 'on' or 'off' end
  if k == 'aiprov' then return P.short or P.name end
  if k == 'aiurl' then return cfg.aiurl ~= '' and cfg.aiurl or (P.url ~= '' and (P.url:gsub('^https://', '') .. '  (default)') or '(needed)') end
  if k == 'aikey' then
    local key = cfg.aikey
    if key == '' then return P.keyless and '(none needed)' or '(empty)' end
    return (#key > 12 and (key:sub(1, 6) .. '…' .. key:sub(-4)) or '****') .. '  (' .. #key .. ' characters)'
  end
  if k == 'aimodel' then return cfg.aimodel ~= '' and cfg.aimodel or (P.model ~= '' and P.model or '(server default)') end
  if k == 'aiextra' then return cfg.aiextra ~= '' and cfg.aiextra or '(none)' end
  if k == 'ailang' then return cfg.ailang ~= '' and cfg.ailang or '(as asked)' end
  if k == 'aibtn' then return #A.buttons() .. ' of ' .. A.BUTTONS_MAX end
  return 'Test the connection'
end

-- Your own ready questions: ai_buttons.txt in the app's folder, one "Label | question" a line (a
-- line without "|" is its own label, cut short); lines starting with # are left out. Edited on the
-- reader (Settings → AI → My buttons) or over USB. At most BUTTONS_MAX.
A.BUTTONS_FILE, A.BUTTONS_MAX = 'ai_buttons.txt', 6
function A.parse_button(line)
  line = tostring(line or ''):gsub('\r', ''):gsub('^%s+', ''):gsub('%s+$', '')
  if line == '' or line:sub(1, 1) == '#' then return nil end
  local label, q = line:match('^(.-)%s*|%s*(.+)$')
  if not label or label == '' then
    q = q or line
    label = q:gsub('%s*|%s*', ' ')
    if #label > 22 then label = cut(label, 21) .. '…' end
  end
  return { label = label, q = q }
end
function A.parse_buttons(s)
  local out = {}
  for line in (tostring(s or '') .. '\n'):gmatch('([^\n]*)\n') do
    local b = A.parse_button(line)
    if b and #out < A.BUTTONS_MAX then out[#out + 1] = b end
  end
  return out
end
local buttons_cache = nil
-- the buttons, read from the card when asked to (reload) or the first time
function A.buttons(reload)
  if reload or not buttons_cache then
    local ok, s = pcall(function()
      if not (ctx.files and ctx.files:exists(A.BUTTONS_FILE)) then return '' end
      return ctx.files:read(A.BUTTONS_FILE, 0, 8192)
    end)
    buttons_cache = A.parse_buttons(ok and s or '')
  end
  return buttons_cache
end
-- the buttons written back (after an edit on the reader)
function A.save_buttons(list)
  local t = { '# Your own AI buttons: one "Label | question" a line, at most ' .. A.BUTTONS_MAX .. '.' }
  for _, b in ipairs(list) do t[#t + 1] = b.label .. ' | ' .. b.q end
  buttons_cache = list
  return pcall(function() return ctx.files:write(A.BUTTONS_FILE, table.concat(t, '\n') .. '\n') end)
end

-- the keyboard for a text field: its title and starting text
function A.field(cfg, k)
  local P = A.prov(cfg)
  local titles = { aiurl = P.url ~= '' and ('Address (empty: ' .. P.url .. ')') or 'Address, e.g. http://192.168.1.5:11434/v1',
                   aikey = 'API key', aimodel = P.model ~= '' and ('Model (empty: ' .. P.model .. ')') or 'Model',
                   ailang = 'Answer in (e.g. Turkish; empty: as asked)',
                   aiextra = 'Extra parameters (JSON), e.g. {"max_tokens":800}' }
  local start = cfg[k] or ''
  if k == 'aiurl' and start == '' and P.hint then start = P.hint end
  return titles[k] or k, start
end

-- what was typed into field k: kept in cfg, or nil and why not (the caller saves)
function A.store(cfg, k, v, decode)
  v = v:gsub('^%s+', ''):gsub('%s+$', '')
  if k == 'aiurl' and v == A.prov(cfg).hint then v = '' end
  if k == 'aiextra' then
    local _, err = A.extra(v, decode)
    if err then return nil, err .. ' (not saved)' end
  end
  cfg[k] = v
  return true
end

-- AI on / off; on without what it needs says what is missing
function A.toggle(cfg)
  cfg.aion = not cfg.aion
  if cfg.aion and not A.ready(cfg) then return A.url(cfg) == '' and 'now set the address' or 'now add the key' end
  return nil
end

-- a service from the list: its own address and model, and no Extra parameters (they differ from
-- service to service); true when its address must be typed now (Ollama, Other)
function A.choose(cfg, id)
  local P = A.PROV[id]
  if not P then return false end
  if cfg.aiprov ~= id then cfg.aiprov, cfg.aiurl, cfg.aimodel, cfg.aiextra = id, '', '', '' end
  return P.url == '' and cfg.aiurl == ''
end

-- ai.txt's text taken into cfg; true when it held settings (the caller saves and deletes the file)
function A.take(cfg, s)
  local got = A.read_file(s)
  if not got then return false end
  for k, v in pairs(got) do cfg[k] = v end
  return true
end

-- the conversation's buttons: More leads to the ready questions, your own question and the web
-- search switch
function A.chat_bar(cfg) return { 'Back', 'Prev', 'Next', 'More' } end

-- the connection test: a one-word question
A.TEST_ART = { title = 'Test', text = 'This is a connection test.' }
A.TEST_MSGS = { { role = 'user', text = 'Reply with the single word OK.' } }

-- the ready questions' rows { label, 'web' } | { label, 'ask', question } | { label, 'own' } |
-- { label, 'new' }: the web search switch where the service has a web search, the presets (and
-- more for a discussion), your own buttons, Translate when an answer language is set, your own
-- question, and Start over once there is a conversation
-- (no_article: only the discussion is sent, so the article's questions are left out; web: the
-- web search switch's state, shown first where the service has a web search)
function A.items(cfg, has_chat, more, no_article, web)
  local t = {}
  if A.web_ok(cfg) then t[#t + 1] = { 'Web search: ' .. (web and 'on' or 'off'), 'web' } end
  if not no_article then for _, p in ipairs(A.PRESETS) do t[#t + 1] = { p[1], 'ask', p[2] } end end
  for _, p in ipairs(more or {}) do t[#t + 1] = { p[1], 'ask', p[2] } end
  for _, b in ipairs(A.buttons()) do t[#t + 1] = { b.label, 'ask', b.q } end
  if cfg.ailang ~= '' and not no_article then t[#t + 1] = { 'Translate', 'ask', 'Translate this article into ' .. cfg.ailang .. '.' } end
  t[#t + 1] = { 'Your question', 'own' }
  if has_chat then t[#t + 1] = { 'Start over', 'new' } end
  return t
end

return A
