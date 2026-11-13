-- Hacker News pieces that need no screen: the addresses of the two public APIs, HN's comment
-- HTML as plain text, ages and domains, and word wrap that also breaks words too long for a line
-- (addresses).
--
-- A list is HN's own ranking (Firebase: topstories.json ... a few KB of ids), its stories' titles
-- and counts come 24 at a time from one Algolia search for exactly those ids (tags
-- "(story_1,story_2,...)", about 7 KB). A story and each comment come from Firebase's item/<id>.json,
-- whose "kids" are the replies in HN's order.

local N = {}

N.FIREBASE = 'https://hacker-news.firebaseio.com/v0/'
N.ALGOLIA = 'https://hn.algolia.com/api/v1/'
N.PER_PAGE = 24
local FIELDS = '&attributesToRetrieve=title,url,points,num_comments,author,created_at_i&attributesToHighlight=%5B%5D'
N.LISTS = { top = 'topstories', new = 'newstories', best = 'beststories', ask = 'askstories', show = 'showstories' }

-- percent-encoding without %w (which follows the C locale and may take bytes of UTF-8 letters)
function N.enc(s)
  return (tostring(s):gsub('[^A-Za-z0-9%-%._~]', function(c) return string.format('%%%02X', c:byte()) end))
end

function N.ids_url(tab) return N.FIREBASE .. N.LISTS[tab] .. '.json' end
function N.item_url(id) return N.FIREBASE .. 'item/' .. id .. '.json' end
-- the stories with these ids, in any order
function N.stories_url(ids)
  local tags = {}
  for k, id in ipairs(ids) do tags[k] = 'story_' .. id end
  return N.ALGOLIA .. 'search?tags=' .. N.enc('(' .. table.concat(tags, ',') .. ')') .. '&hitsPerPage=' .. #ids .. FIELDS
end
-- a search: stories by relevance, page from 0
function N.search_url(q, page)
  return N.ALGOLIA .. 'search?tags=story&query=' .. N.enc(q) .. '&hitsPerPage=' .. N.PER_PAGE .. '&page=' .. page .. FIELDS
end

-- ids as strings, read from the raw JSON: a list of ids (topstories.json), or an item's "kids"
-- (the reader's Lua may have 32-bit numbers, where a decoded id could come back rounded)
function N.ids(body)
  local t = {}
  for id in tostring(body or ''):gmatch('%d+') do t[#t + 1] = id end
  return t
end
function N.kids(body)
  return N.ids(tostring(body or ''):match('"kids"%s*:%s*%[([%d,%s]*)%]'))
end

-- an Algolia hit -> a story row
function N.story(h)
  return { id = tostring(h.objectID), title = tostring(h.title or '(untitled)'), url = h.url and tostring(h.url) or nil,
           points = tonumber(h.points) or 0, comments = tonumber(h.num_comments) or 0,
           by = tostring(h.author or ''), time = tonumber(h.created_at_i) or 0 }
end
-- one list row as a line of text, and back (list_<tab>.txt keeps the last list for opening offline)
function N.row_text(s)
  return table.concat({ s.id, (s.title:gsub('[\t\n]', ' ')), s.url or '', s.points, s.comments, s.by, s.time }, '\t')
end
function N.row_parse(line)
  local id, title, url, points, comments, by, time = line:match('^(%d+)\t([^\t]*)\t([^\t]*)\t(%d*)\t(%d*)\t([^\t]*)\t(%d*)$')
  if not id then return nil end
  return { id = id, title = title, url = url ~= '' and url or nil, points = tonumber(points) or 0,
           comments = tonumber(comments) or 0, by = by, time = tonumber(time) or 0 }
end

function N.domain(url)
  local d = url and url:match('^%a+://([^/:?#]+)')
  return d and (d:gsub('^www%.', '')) or nil
end

------------------------------------------------------------------ For you (1.3.0)
-- foryou.txt, one entry a line: "rust" a topic, "-crypto" a muted word, "-site:medium.com" a
-- muted site. Lower case (ASCII), trimmed, each once.

local function trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end
-- lower case for A-Z only (string.lower and %w follow the C locale and may change UTF-8 bytes)
local function lower(s) return (s:gsub('[A-Z]', function(c) return string.char(c:byte() + 32) end)) end
local function add_once(list, v)
  for _k, x in ipairs(list) do if x == v then return false end end
  list[#list + 1] = v
  return true
end

function N.foryou_parse(text)
  local fy = { topics = {}, words = {}, sites = {} }
  for line in (tostring(text or '') .. '\n'):gmatch('([^\n]*)\n') do
    local s = lower(trim((line:gsub('\r', ''))))
    local site = s:match('^%-%s*site:%s*(%S+)$')
    if site then add_once(fy.sites, (site:gsub('^www%.', '')))
    elseif s:sub(1, 1) == '-' then
      local w = trim(s:sub(2))
      if w ~= '' then add_once(fy.words, w) end
    elseif s ~= '' then
      add_once(fy.topics, (s:gsub('%s+', ' ')))
    end
  end
  return fy
end

function N.foryou_text(fy)
  local out = {}
  for _k, t in ipairs(fy.topics) do out[#out + 1] = t end
  for _k, w in ipairs(fy.words) do out[#out + 1] = '-' .. w end
  for _k, s in ipairs(fy.sites) do out[#out + 1] = '-site:' .. s end
  return table.concat(out, '\n')
end

-- one search for all the topics: each optional (a story matching more of them ranks higher, then
-- by points), a topic of several words a phrase; the last two days, 10 points or more; 40 a page,
-- so that some are left after the mutes
function N.foryou_url(topics, now, page)
  local q = {}
  for _k, topic in ipairs(topics) do
    local t = topic:gsub('"', '')
    q[#q + 1] = t:find(' ', 1, true) and ('"' .. t .. '"') or t
  end
  local query = N.enc(table.concat(q, ' '))
  return N.ALGOLIA .. 'search?tags=story&query=' .. query .. '&optionalWords=' .. query .. '&advancedSyntax=true'
    .. '&numericFilters=' .. N.enc('created_at_i>' .. ((now or 0) - 172800) .. ',points>=10')
    .. '&hitsPerPage=40&page=' .. (page or 0) .. FIELDS
end

-- the title's words, lower case (letters, digits and the like; whole UTF-8 characters)
local function words_of(title)
  local out = {}
  for w in lower(tostring(title or '')):gmatch("[A-Za-z0-9\128-\255][A-Za-z0-9\128-\255'%+#%.%-]*") do
    out[#out + 1] = (w:gsub("[%.%-']+$", ''))
  end
  return out
end
local function has_words(title_words, phrase)
  local set = {}
  for _k, w in ipairs(title_words) do set[w] = true end
  for w in phrase:gmatch('%S+') do if not set[w] then return false end end
  return true
end

function N.muted(row, fy)
  local tw = words_of(row.title)
  for _k, w in ipairs(fy.words) do if has_words(tw, w) then return true end end
  local d = N.domain(row.url)
  if d then
    d = lower(d)
    for _k, s in ipairs(fy.sites) do
      if d == s or d:sub(-(#s + 1)) == '.' .. s then return true end
    end
  end
  return false
end

function N.topics_in(title, topics)
  local tw, out = words_of(title), {}
  for _k, t in ipairs(topics) do if has_words(tw, t) then out[#out + 1] = t end end
  return out
end

local STOP = {}
for w in ('the and for with from that this what how why who are was were has have had not you your our its'
    .. ' into over about after than then when will can just new now all any via using use one two out'
    .. ' show ask tell more most some his her they them their there here been being but get got')
    :gmatch('%S+') do STOP[w] = true end
-- the words of a title that could be a topic (More like this): 3 letters or more, not a stop word
function N.title_words(title)
  local out = {}
  for _k, w in ipairs(words_of(title)) do
    -- a dash or an ellipsis on its own (U+2000-U+206F, 3 bytes in UTF-8) is not a word
    local bare = w:gsub('\226[\128\129][\128-\191]', '')
    if #w >= 3 and bare ~= '' and not STOP[w] and not w:match('^%d+$') then add_once(out, w) end
  end
  return out
end

function N.ago(t, now)
  if not t or t <= 0 or not now or now <= 0 then return '' end
  local s = math.max(0, now - t)
  local function n(d) return math.floor(s / d) end       -- an integer also when t came as a float
  if s < 3600 then return math.max(1, n(60)) .. ' min ago' end
  if s < 86400 then return n(3600) .. ' h ago' end
  if s < 86400 * 365 then return n(86400) .. ' d ago' end
  return n(86400 * 365) .. ' y ago'
end

-- HN's HTML (comments, Ask HN texts): <p> paragraphs, <i>, <a>, <pre><code>, entities
local ENT = { amp = '&', lt = '<', gt = '>', quot = '"', apos = "'", nbsp = ' ', hellip = '...', mdash = '-', ndash = '-' }
local function entity(e)
  local n = e:match('^#[xX](%x+)$')
  n = n and tonumber(n, 16) or tonumber(e:match('^#(%d+)$') or '')
  if n then return (n > 0 and n < 0x110000) and utf8.char(n) or '' end
  return ENT[e] or ('&' .. e .. ';')
end
function N.text(html)
  local s = tostring(html or '')
  s = s:gsub('\r', ''):gsub('<pre><code>(.-)</code></pre>', function(code) return '\n\n' .. code:gsub('\n+$', '') .. '\n\n' end)
  s = s:gsub('<[pP]>', '\n\n'):gsub('<br%s*/?>', '\n'):gsub('<[^>]*>', '')
  s = s:gsub('&(#?%w+);', entity)
  s = s:gsub('\n\n\n+', '\n\n'):gsub('^%s+', ''):gsub('%s+$', '')
  return s
end

-- A story's comments all at once, for the AI (Algolia's search, flat, with their parents): about
-- 35 KB per 100 comments, so a page of `per` stays under the reader's 128 KB an answer.
function N.comments_url(story_id, page, per)
  return N.ALGOLIA .. 'search?tags=comment,story_' .. story_id .. '&hitsPerPage=' .. per .. '&page=' .. page
    .. '&attributesToRetrieve=comment_text,author,parent_id,created_at_i&attributesToHighlight=%5B%5D'
end

local function idstr(v)
  if type(v) == 'number' then return string.format('%d', math.floor(v)) end
  return tostring(v or '')
end

-- a page of Algolia comment hits, kept small: { id, parent, by, t, text } each. The parents are
-- read from the raw JSON in order (a decoded number above 2^24 may come back rounded); objectID
-- is a string already.
function N.comment_hits(d, body)
  local parents = {}
  for p in tostring(body or ''):gmatch('"parent_id"%s*:%s*(%d+)') do parents[#parents + 1] = p end
  local hits = type(d) == 'table' and type(d.hits) == 'table' and d.hits or {}
  local use_raw = #parents == #hits
  local out = {}
  for k, h in ipairs(hits) do
    out[#out + 1] = { id = idstr(h.objectID), parent = use_raw and parents[k] or idstr(h.parent_id), by = tostring(h.author or '?'),
                      t = tonumber(h.created_at_i) or 0, text = N.text(h.comment_text) }
  end
  return out
end

-- The comments as one text for the AI: "author: text", a reply indented two spaces under the
-- comment it answers; the first level in HN's order (order: the story's kids), replies oldest
-- first (HN's own order of replies is not in the data). At most budget bytes, whole comments;
-- returns the text and how many comments it holds.
function N.thread_text(hits, story_id, order, budget)
  local kids, known = {}, {}
  for _k, c in ipairs(hits) do known[c.id] = true end
  for _k, c in ipairs(hits) do
    local p = (c.parent ~= '' and known[c.parent]) and c.parent or tostring(story_id)   -- a lost parent: first level
    kids[p] = kids[p] or {}
    kids[p][#kids[p] + 1] = c
  end
  for _p, list in pairs(kids) do table.sort(list, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.id < b.id end) end
  local rank = {}
  for k, id in ipairs(order or {}) do rank[tostring(id)] = k end
  local top = kids[tostring(story_id)] or {}
  table.sort(top, function(a, b)
    local ra, rb = rank[a.id] or math.huge, rank[b.id] or math.huge
    if ra ~= rb then return ra < rb end
    if a.t ~= b.t then return a.t < b.t end
    return a.id < b.id
  end)
  local out, used, n, full = {}, 0, 0, false
  local function walk(list, depth)
    for _k, c in ipairs(list) do
      if full then return end
      local line = string.rep('  ', depth) .. c.by .. ': ' .. c.text:gsub('%s*\n+%s*', ' ')
      if used + #line + 1 > budget then full = true; return end
      out[#out + 1] = line
      used, n = used + #line + 1, n + 1
      if kids[c.id] then walk(kids[c.id], depth + 1) end
    end
  end
  walk(top, 0)
  if full then out[#out + 1] = '[' .. (#hits - n) .. ' more comments are left out here.]' end
  return table.concat(out, '\n'), n
end

-- the bytes of s that fit in width w (whole UTF-8 characters, at least one)
local function fit(f, s, w)
  local best = nil
  pcall(function()
    for p in utf8.codes(s) do
      if p > 1 then
        if kit.width(f, s:sub(1, p - 1)) > w then break end
        best = p - 1
      end
    end
  end)
  return best or math.max(1, math.min(#s, w // 12))
end

-- word wrap in the given font: lines no wider than w; a word wider than a line is broken
function N.wrap(s, fname, w)
  local f, out = kit.font(fname), {}
  for para in (tostring(s) .. '\n'):gmatch('([^\n]*)\n') do
    local line = ''
    for word in para:gmatch('[^ \t]+') do
      local cand = line == '' and word or (line .. ' ' .. word)
      if kit.width(f, cand) <= w then line = cand
      else
        if line ~= '' then out[#out + 1] = line end
        line = word
        while kit.width(f, line) > w do
          local n = fit(f, line, w)
          out[#out + 1] = line:sub(1, n)
          line = line:sub(n + 1)
        end
      end
    end
    out[#out + 1] = line
  end
  return out
end

return N
