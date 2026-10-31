-- library.lua: feeds on the reader. Collections are OPML files in the app's folder on the card
-- (ctx.files: AppFiles/<app_id>/, "My feeds.opml" first); each feed's articles are kept in the
-- app's private files. Fetching goes through main.lua's request queue (init).
--
--   L.init{ submit, worker, has_worker }   submit(opts, label, timeout, cb); worker(path, cb, label)
--   L.collections()                  -> { {file, title} }, "My feeds" first
--   L.collection(file)               -> { file, title, feeds = { {title, url, site, path} } }
--   L.add_feed(url, title, site, file) -> true | nil, 'already' (default: into My feeds)
--   L.remove_feed(coll, url), L.save_collection(file, title, feeds)
--   L.items(coll, kind, url)         -> rows for a list (kind: unread / all / starred / feed)
--   L.info(url) -> { u = unread, e = failed last time }   from one index file, no per-feed reads
--   L.mark(row, field, value), L.content(row) -> HTML or nil
--   L.refresh(coll, force, on_feed, on_done)   fetches feeds older than FRESH_SEC one by one
-- A collection can hold hundreds of feeds (an OPML exported from another reader), so nothing
-- here reads every feed's file at once: lists are per feed, and only a few feeds stay in memory.
--   L.probe(address, cb)             cb(kind, data): 'feed' {url, title} | 'opml' {title, text} | nil, why

local F = require('feeds')
local L = {}

local KEEP_ITEMS = 40          -- articles kept per feed (starred ones are kept as well)
local KEEP_HTML = 12           -- of them, the newest with text keep their HTML for reading offline
local HTML_BYTES = 200000      -- a feed's HTML file stays under the 256 KB file limit
local FRESH_SEC = 30 * 60      -- a feed checked less than this long ago is not asked again
local EXCERPT = 300
local MY = 'My feeds.opml'

local env = {}
function L.init(e) env = e end
function L.has_worker() return env.has_worker ~= nil and env.has_worker() end

local function now_s()
  local ok, t = pcall(function() return ctx.clock:now() end)
  if ok and type(t) == 'table' and t.valid ~= false and tonumber(t.epoch_sec) then return tonumber(t.epoch_sec) end
  return 0
end

local function sread(name)
  local ok, s = pcall(function() return ctx.storage:read(name) end)
  return (ok and type(s) == 'string') and s or nil
end
local function swrite(name, s) pcall(function() ctx.storage:write(name, s) end) end
local function sremove(name) pcall(function() ctx.storage:remove(name) end) end
local function decode(s)
  if not s then return nil end
  local ok, d = pcall(function() return ctx.json:decode(s) end)
  return (ok and type(d) == 'table') and d or nil
end
local function encode(t)
  local ok, s = pcall(function() return ctx.json:encode(t) end)
  return ok and s or nil
end

------------------------------------------------------------------ collections (OPML files)

local function files_list()
  local ok, t = pcall(function() return ctx.files:list() end)
  local out = {}
  for _, f in ipairs((ok and type(t) == 'table') and t or {}) do
    local n = type(f) == 'table' and f.name or f
    if type(n) == 'string' and n:lower():match('%.opml$') then out[#out + 1] = n end
  end
  return out
end

local function file_read(name)
  local F2 = ctx.files
  if not F2 then return nil end
  local ok, t = pcall(function()
    local parts, off = {}, 0
    for _ = 1, 8 do
      local piece = F2:read(name, off, 65536)
      if type(piece) ~= 'string' or piece == '' then break end
      parts[#parts + 1] = piece
      off = off + #piece
      if #piece < 65536 then break end
    end
    return table.concat(parts)
  end)
  return (ok and type(t) == 'string' and t ~= '') and t or nil
end

local colls = {}               -- file -> parsed collection

-- My feeds is always there, empty until a feed is added (its file is written then)
function L.collections()
  local out, mine = {}, false
  for _, n in ipairs(files_list()) do
    local c = L.collection(n)
    if c then out[#out + 1] = { file = n, title = c.title }; mine = mine or n == MY end
  end
  if not mine then out[#out + 1] = { file = MY, title = L.collection(MY).title } end
  table.sort(out, function(a, b)
    if (a.file == MY) ~= (b.file == MY) then return a.file == MY end
    return a.title:lower() < b.title:lower()
  end)
  return out
end

function L.collection(file)
  local c = colls[file]
  if c then return c end
  local text = file_read(file)
  if not text then
    if file ~= MY then return nil end
    c = { file = MY, title = 'My feeds', feeds = {} }
    colls[file] = c
    return c
  end
  local o = F.parse_opml(text)
  local title = o.title ~= '' and o.title or file:gsub('%.[Oo][Pp][Mm][Ll]$', '')
  c = { file = file, title = title, feeds = o.feeds }
  colls[file] = c
  return c
end

function L.forget() colls = {} end

function L.save_collection(file, title, feeds)
  local ok, err = pcall(function() return ctx.files:write(file, F.write_opml(title, feeds)) end)
  colls[file] = nil
  return ok and err ~= nil, (not ok) and err or nil
end

-- a name the card accepts for a collection's file
function L.file_name(title)
  local n = tostring(title or ''):gsub('[%c/\\:%*%?"<>|~]', ' '):gsub('%s+', ' '):gsub('^[%s%.]+', ''):gsub('[%s%.]+$', '')
  if n == '' then n = 'Feeds' end
  return n:sub(1, 60) .. '.opml'
end

-- into the collection file (default My feeds)
function L.add_feed(url, title, site, file)
  file = file or MY
  local c = L.collection(file)
  if not c then return nil, 'no collection' end
  for _, f in ipairs(c.feeds) do if f.url == url then return nil, 'already' end end
  local feeds = {}
  for _, f in ipairs(c.feeds) do feeds[#feeds + 1] = f end
  feeds[#feeds + 1] = { title = title ~= '' and title or url, url = url, site = site }
  L.save_collection(file, c.title, feeds)
  return true
end

function L.has_feed(url, file)
  local c = L.collection(file or MY)
  for _, f in ipairs(c and c.feeds or {}) do if f.url == url then return true end end
  return false
end

function L.remove_feed(coll, url)
  local feeds = {}
  for _, f in ipairs(coll.feeds) do if f.url ~= url then feeds[#feeds + 1] = f end end
  L.save_collection(coll.file, coll.title, feeds)
end

------------------------------------------------------------------ a feed's articles

-- f_<hash>.txt: { url, title, etag, lastmod, checked, items = { {id, t, l, d, x, r, s, c, w} } }
-- t title, l link, d date (s since 1970), x excerpt, r read, s starred, c has text to read,
-- w came through the Worker. h_<hash>.txt: { [id] = HTML } for the newest ones with text.
local CACHED = 6               -- feed records kept in memory, the most recently used
local cache, used = {}, {}     -- url -> feed record; urls, the most recent last

local function fname(url) return 'f_' .. F.hash(url) .. '.txt' end
local function hname(url) return 'h_' .. F.hash(url) .. '.txt' end

local function touch(url)
  for i, u in ipairs(used) do if u == url then table.remove(used, i); break end end
  used[#used + 1] = url
  while #used > CACHED do cache[table.remove(used, 1)] = nil end
end

function L.feed(url)
  local r = cache[url]
  if not r then
    r = decode(sread(fname(url)))
    if not r or r.url ~= url then r = { url = url, items = {} } end
    r.items = r.items or {}
    cache[url] = r
  end
  touch(url)
  return r
end

-- idx.txt: { [url] = { u = unread articles, e = 1 when the last fetch failed } }, for the feeds screen
local idx = nil
local function index()
  if not idx then idx = decode(sread('idx.txt')) or {} end
  return idx
end
function L.info(url) return index()[url] or {} end

local function note(r)
  local n = 0
  for _, it in ipairs(r.items) do if not it.r then n = n + 1 end end
  local e = r.error and 1 or nil
  local old = index()[r.url]
  if old and old.u == n and old.e == e then return end
  idx[r.url] = { u = n, e = e }
  local s = encode(idx)
  if s then swrite('idx.txt', s) end
end

local function save_feed(r)
  local s = encode(r)
  if s then swrite(fname(r.url), s) end
  note(r)
end

-- the newest first; undated articles keep the feed's order after the dated ones they came with
local function by_date(a, b) return (a.d or 0) > (b.d or 0) end

-- a parsed feed into the record: read and starred marks kept, the newest KEEP_ITEMS (and every
-- starred one) kept, the HTML of the newest with text stored for reading
local function merge(r, feed, via_worker)
  local old = {}
  for _, it in ipairs(r.items) do old[it.id] = it end
  local now = now_s()
  local seen, items, html = {}, {}, {}
  for k, it in ipairs(feed.items) do
    local id = tostring(it.id)
    if not seen[id] then
      seen[id] = true
      local prev = old[id]
      local text = it.content and it.content ~= '' and it.content or nil
      local summary = it.summary or ''
      if not text and #summary > 1500 then text = summary end     -- a long summary is the article
      local row = {
        id = id, t = it.title ~= '' and it.title or (it.link or ''), l = it.link,
        d = it.date or (prev and prev.d) or (now - k), x = it.excerpt or F.excerpt((summary ~= '' and summary or (text or '')):sub(1, 4000), EXCERPT),
        r = prev and prev.r or false, s = prev and prev.s or false,
        c = (text ~= nil) or (it.has_content and true or false), w = via_worker or nil,
      }
      items[#items + 1] = row
      if text then html[id] = text end
    end
  end
  for _, it in ipairs(r.items) do                 -- starred ones the feed no longer lists stay
    if it.s and not seen[it.id] then items[#items + 1] = it end
  end
  table.sort(items, by_date)
  local kept = {}
  for _, it in ipairs(items) do
    if #kept < KEEP_ITEMS or it.s then kept[#kept + 1] = it end
  end
  r.items = kept
  r.title = (feed.title and feed.title ~= '') and feed.title or r.title
  r.site = feed.link or r.site
  -- the HTML file: what was stored before, then the new texts, newest first, within the budget
  local store = decode(sread(hname(r.url))) or {}
  for id, h in pairs(html) do store[id] = h end
  local keep, size, n = {}, 0, 0
  for _, it in ipairs(kept) do
    local h = store[it.id]
    if h and n < KEEP_HTML and size + #h <= HTML_BYTES then keep[it.id] = h; size = size + #h; n = n + 1 end
  end
  local s = encode(keep)
  if s then swrite(hname(r.url), s) end
  save_feed(r)
end

function L.content(row)
  local store = decode(sread(hname(row.feed_url)))
  return store and store[row.id] or nil
end

function L.mark(row, field, value)
  local r = L.feed(row.feed_url)
  for _, it in ipairs(r.items) do
    if it.id == row.id then it[field] = value end
  end
  row[field == 'r' and 'read' or 'starred'] = value
  save_feed(r)
end


-- list rows in the shape the screens use (title, feed, read, starred, excerpt ...)
function L.items(coll, kind, url)
  local rows = {}
  for _, f in ipairs(coll.feeds) do
    if kind ~= 'feed' or f.url == url then
      local r = L.feed(f.url)
      local name = (f.title and f.title ~= '' and f.title ~= f.url) and f.title or (r.title or f.url)
      for _, it in ipairs(r.items) do
        if kind == 'all' or kind == 'feed' or (kind == 'unread' and not it.r) or (kind == 'starred' and it.s) then
          rows[#rows + 1] = { id = it.id, title = it.t, feed = name, d = it.d, read = it.r, starred = it.s,
            excerpt = it.x, url = it.l, has_text = it.c, via_worker = it.w, feed_url = f.url, ['local'] = true }
        end
      end
    end
  end
  table.sort(rows, by_date)
  return rows
end

------------------------------------------------------------------ fetching

local FEED_ACCEPT = 'application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.9, */*;q=0.5'
local UA = 'Mozilla/5.0 (Xteink RSS mini app)'
local LIMIT = 131072

local gz_ok = nil
local function gunzip(b)
  local z = ctx.zlib
  if not z then return nil end
  local ok, t = pcall(function() return z:decompress(b, { format = 'gzip' }) end)
  return (ok and type(t) == 'string') and t or nil
end
local function gzip_works()
  if gz_ok == nil then
    gz_ok = ctx.zlib ~= nil and gunzip('\31\139\8\0\0\0\0\0\0\3\203\72\205\201\201\7\0\134\166\16\54\5\0\0\0') == 'hello'
  end
  return gz_ok
end

local function extend() pcall(function() ctx.budget:extend() end) end

-- one GET, redirects followed (the host leaves them to the app): cb(resp, final_url) or cb(nil, why)
local function get(url, headers, label, cb, hops)
  hops = hops or 0
  env.submit({ url = url, method = 'GET', headers = headers }, label, 30000, function(resp, err)
    if err then cb(nil, err); return end
    if type(resp) ~= 'table' then cb(nil, 'no response'); return end
    local st = tonumber(resp.status) or tonumber(resp.code) or 0
    local h = type(resp.headers) == 'table' and resp.headers or {}
    if st >= 300 and st < 400 and st ~= 304 and h.location and hops < 4 then
      local nxt = F.absolute(h.location, url)
      if nxt then get(nxt, headers, label, cb, hops + 1); return end
    end
    cb(resp, url)
  end)
end

local function body_of(resp)
  local b = type(resp.body) == 'string' and resp.body or ''
  local cut = (tonumber(resp.bytes) or #b) > #b or resp.error == 'limit_exceeded' or resp.err == 'limit_exceeded'
  if b:sub(1, 2) == '\31\139' then
    if cut then return nil, true, true end           -- a gzip answer cut short cannot be unpacked
    local t = gunzip(b)
    if not t then return nil, false, true end
    return t, false
  end
  return b, cut
end

-- the feed through the Worker (/api/feed): the newest articles of a feed of any size
local function via_worker(r, label, cb)
  if not L.has_worker() then cb(nil, 'feed too large for the reader'); return end
  env.worker('/api/feed?n=' .. KEEP_ITEMS .. '&url=' .. F.url_encode(r.url), function(data, err)
    if not data then cb(nil, err); return end
    local feed = { title = data.title, link = data.link, items = {} }
    for _, it in ipairs(type(data.items) == 'table' and data.items or {}) do
      feed.items[#feed.items + 1] = { id = it.id, title = it.title or '', link = it.link, date = tonumber(it.date) or F.date(it.date),
        excerpt = it.excerpt, has_content = it.has_content }
    end
    extend()
    merge(r, feed, true)
    cb(true)
  end, label)
end

-- the rest of a feed cut short, by byte ranges where the server allows them (up to 4 pieces)
local function more_by_range(url, text, label, cb, n)
  n = n or 1
  if n > 3 then cb(text); return end
  local from = #text
  get(url, { ['Accept'] = FEED_ACCEPT, ['User-Agent'] = UA, ['Range'] = 'bytes=' .. from .. '-' .. (from + LIMIT - 1) }, label, function(resp)
    if not resp or tonumber(resp.status) ~= 206 or type(resp.body) ~= 'string' or resp.body == '' then cb(text); return end
    local piece = resp.body
    local cut = (tonumber(resp.bytes) or #piece) > #piece
    text = text .. piece
    local h = type(resp.headers) == 'table' and resp.headers or {}
    local total = tonumber(tostring(h['content-range'] or ''):match('/(%d+)$'))
    if total and #text >= total then cb(text); return end
    if cut or #piece >= LIMIT then more_by_range(url, text, label, cb, n + 1) else cb(text) end
  end)
end

-- one feed: cb(true) changed, cb('same') not changed, cb(nil, why)
local function fetch_feed(r, label, cb)
  local h = { ['Accept'] = FEED_ACCEPT, ['User-Agent'] = UA }
  local gz = gzip_works()
  if gz then h['Accept-Encoding'] = 'gzip' end
  if r.etag then h['If-None-Match'] = r.etag end
  if r.lastmod then h['If-Modified-Since'] = r.lastmod end
  get(r.url, h, label, function(resp, final)
    extend()
    if not resp then cb(nil, final); return end
    local st = tonumber(resp.status) or tonumber(resp.code) or 0
    r.checked = now_s()
    if st == 304 then save_feed(r); cb('same'); return end
    if st >= 400 or st == 0 then save_feed(r); cb(nil, 'HTTP ' .. st); return end
    local hh = type(resp.headers) == 'table' and resp.headers or {}
    local text, cut, gzbad = body_of(resp)
    local function finish(t)
      extend()
      local feed = F.parse_feed(t or '')
      if not feed then save_feed(r); cb(nil, 'not a feed'); return end
      r.etag, r.lastmod = hh.etag, hh['last-modified']
      merge(r, feed)
      cb(true)
    end
    if text and not cut then finish(text); return end
    -- too large: the Worker if there is one, else as much as the reader can take
    if L.has_worker() then via_worker(r, label, cb); return end
    if gzbad then
      get(final, { ['Accept'] = FEED_ACCEPT, ['User-Agent'] = UA }, label, function(resp2)
        if not resp2 or type(resp2.body) ~= 'string' then cb(nil, 'feed too large'); return end
        local t2 = resp2.body
        local h2 = type(resp2.headers) == 'table' and resp2.headers or {}
        if (tonumber(resp2.bytes) or #t2) > #t2 and tostring(h2['accept-ranges'] or ''):find('bytes', 1, true) then
          more_by_range(final, t2, label, finish)
        else
          finish(t2)
        end
      end)
      return
    end
    if tostring(hh['accept-ranges'] or ''):find('bytes', 1, true) then more_by_range(final, text, label, finish) else finish(text) end
  end)
end

-- the collection's feeds, one after another (the reader carries one request at a time)
function L.refresh(coll, force, on_feed, on_done)
  local todo = {}
  local now = now_s()
  for _, f in ipairs(coll.feeds) do
    local r = L.feed(f.url)
    if force or not r.checked or now - r.checked > FRESH_SEC or now == 0 then todo[#todo + 1] = r end
  end
  local i, changed, failed = 0, 0, 0
  local function step()
    i = i + 1
    local r = todo[i]
    if not r then if on_done then on_done(changed, failed, #todo) end; return end
    fetch_feed(r, 'updating ' .. i .. '/' .. #todo, function(ok, why)
      if ok == true then changed = changed + 1 elseif not ok then failed = failed + 1; r.error = why end
      if ok then r.error = nil end
      note(r)
      if on_feed then on_feed(r, i, #todo) end
      step()
    end)
  end
  step()
end

------------------------------------------------------------------ an address typed in

local function looks_html(b) return b:sub(1, 2048):lower():find('<html', 1, true) ~= nil end

-- a site or a feed or an OPML: cb('feed', {url, title}) | cb('opml', {title, text}) | cb(nil, why)
function L.probe(address, cb)
  local url = tostring(address or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if url == '' then cb(nil, 'no address'); return end
  if not url:match('^https?://') then url = 'https://' .. url end
  local h = { ['Accept'] = FEED_ACCEPT .. ', text/html;q=0.8, text/x-opml', ['User-Agent'] = UA }
  if gzip_works() then h['Accept-Encoding'] = 'gzip' end
  local tried = {}
  local function try_guess(base, list, k)
    k = k or 1
    local path = list[k]
    if not path then cb(nil, 'no feed found on this site'); return end
    local u = F.absolute(path, base)
    if not u or tried[u] then try_guess(base, list, k + 1); return end
    tried[u] = true
    get(u, h, 'looking for a feed', function(resp, final)
      local b = resp and body_of(resp)
      if b and F.is_feed(b) then
        local feed = F.parse_feed(b)
        cb('feed', { url = final, title = feed and feed.title or '' })
      else
        try_guess(base, list, k + 1)
      end
    end)
  end
  get(url, h, 'looking at the address', function(resp, final)
    if not resp then cb(nil, final); return end
    local st = tonumber(resp.status) or 0
    if st >= 400 then cb(nil, 'HTTP ' .. st); return end
    local b = body_of(resp) or ''
    extend()
    if F.is_opml(b) then cb('opml', { title = F.parse_opml(b).title, text = b }); return end
    if F.is_feed(b) then
      local feed = F.parse_feed(b)
      cb('feed', { url = final, title = feed and feed.title or '' })
      return
    end
    local found = looks_html(b) and F.discover(b, final) or {}
    local guesses = {}
    for _, d in ipairs(found) do guesses[#guesses + 1] = d.url end
    for _, p in ipairs({ '/feed', '/rss', '/feed.xml', '/atom.xml', '/index.xml', '/rss.xml' }) do guesses[#guesses + 1] = p end
    try_guess(final, guesses)
  end)
end

L.MY = MY
return L
