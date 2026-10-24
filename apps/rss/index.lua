-- RSS reader for XTOS Licorice, API 2.9. Talks to a commafeed-opds Worker's JSON API over
-- HTTPS (ctx.net), decodes with ctx.json and keeps a small offline cache in ctx.storage.
--
-- Screens: menu (Unread / Starred / All / Feeds / Settings), list (paged, tap an item), article
-- (word-wrapped text, paged), feeds, settings (host, path token, user:pass, full text).
-- Every ctx.* function is a method on this API: colon calls everywhere.

local W, H, TOP = 480, 800, 56
local LIST_N = 12
local LIST_MAX_ITEMS = 240    -- list rows kept in memory as pages are appended
local TEXT_MAX = 20000

local G, ERR = nil, nil
local screen = 'menu'
local status = ''
local loading = nil           -- text shown while a request is in flight
local function now_ms()
  local ok, t = pcall(function() return ctx.clock:millis() end)
  return ok and tonumber(t) or nil
end

-- Network queue. The host appears to carry one request at a time: a second one started while
-- another is in flight never got an answer (the feeds list stayed on "loading"). So requests
-- run one after the other, images included. A request with no answer within its timeout is
-- cancelled and reported as failed, and the next one starts.
local net_queue, net_active = {}, nil
local net_pump

local function net_finish(job, resp, err)
  if job.done then return end                 -- a late answer after a timeout is ignored
  job.done = true
  if net_active == job then net_active = nil end
  if not net_active and #net_queue == 0 then loading = nil end
  job.on_result(resp, err)
  net_pump()
  pcall(function() ctx.invalidate() end)
end

net_pump = function()
  if net_active or #net_queue == 0 then return end
  local job = table.remove(net_queue, 1)
  net_active = job
  job.since = now_ms()
  loading = job.label
  local ok, err = pcall(function()
    job.handle = ctx.net:request(job.opts, function(c, resp) net_finish(job, resp, nil) end)
  end)
  if not ok then net_finish(job, nil, short(err, 60)) end
end

-- drop the request in flight: cancel it in the host and report it as failed
local function net_abandon(reason)
  local job = net_active
  if not job then return end
  if job.handle then pcall(function() job.handle:cancel() end) end
  net_finish(job, nil, reason)
end

-- still waiting for an answer? Also enforces the timeouts (checked on every draw and tick).
local function busy()
  if net_active then
    local t = now_ms()
    if t and net_active.since and t - net_active.since > net_active.timeout then
      net_abandon('no answer within ' .. math.floor(net_active.timeout / 1000) .. ' s')
    end
  end
  return net_active ~= nil or #net_queue > 0
end

-- Reload: a request that has been waiting a while is given up at once instead of after its timeout
local function net_unstick()
  local t = now_ms()
  if net_active and (not t or not net_active.since or t - net_active.since > 3000) then
    net_abandon('given up (Reload)')
  end
end

local function net_submit(opts, label, timeout, on_result)
  opts.timeout_ms = timeout
  net_queue[#net_queue + 1] = { opts = opts, label = label, timeout = timeout, on_result = on_result }
  net_pump()
end
local cfg = { host = '', token = '', auth = '', full = false, size = 'default', images = false }
-- Text size for articles and the preview. The firmware has three fonts (ttf is off), so the
-- sizes shift which of them the body, the headings and the feed / date line use.
local SIZES = {
  small = { title = 'medium', head = 'medium', body = 'small', meta = 'small' },
  default = { title = 'large', head = 'large', body = 'medium', meta = 'small' },
  large = { title = 'large', head = 'large', body = 'large', meta = 'medium', rule = true },
}
local SIZE_ORDER = { 'default', 'large', 'small' }
local function st() return SIZES[cfg.size] or SIZES.default end
-- CommaFeed accounts the Worker serves ({ {id, label} ... }, from /api). With more than one the
-- menu starts with a folder per account and every request carries ?acct=<id>.
local accounts = {}
local acct = nil              -- the chosen account's id while several exist
local function multi() return #accounts > 1 end
local read_accounts, load_accounts, note_accounts   -- defined in the accounts section
-- The account list is refreshed once per app start: the Worker sends it with every list and feed
-- answer, so the first one after start brings it. Asking /api separately before the first list
-- made that list wait for two round trips; /api is asked only with nothing saved yet, after
-- Settings, when the user has opened nothing a few seconds after start, or for an older Worker.
local accounts_fresh = false
local started_ms = nil
local load_page_images, release_images, draw_image_line   -- defined in the images section
local function acct_label()
  for _, a in ipairs(accounts) do if a.id == acct then return a.label end end
  return ''
end
-- cache files of accounts other than the first get their own prefix, so nothing mixes
local function cpre() return (multi() and acct and acct ~= '1') and ('x' .. acct .. '_') or '' end

-- list screen
local list = { kind = 'unread', id = nil, title = '', page = 1, items = {}, has_more = false, cached = false }
-- long-press preview over the list: { item, lines, box = {x, y, w, h}, open = {..}, close = {..} }
local preview = nil
local suppress_up = false     -- the release that ends a long press must not also act as a tap
local preview_can             -- defined with the preview navigation; draw_preview needs it
local article_back            -- Back from an article: to its preview if it was opened there
-- feeds screen
local feeds = { items = {}, top = 1 }
-- article screen
local art = { id = nil, title = '', feed = '', date = '', lines = {}, starts = { 1 }, page = 1, pages = 1, cached = false }
local measure_cache = {}

local function short(s, n) s = tostring(s); if #s > n then return s:sub(1, n - 1) .. '~' end return s end
local function note(s) status = tostring(s or '') end

local function refresh() pcall(function() ctx.invalidate() end) end

-- A side button arrives as more than one key event on API 2.9 (press and release, or a repeat),
-- which turned one press into two pages. Ignore release events and the same key again within
-- KEY_GAP_MS, whatever the host calls its fields.
local KEY_GAP_MS = 250
local last_key, last_key_ms = nil, nil
local function key_accepted(ev)
  local ph = ev.phase or ev.action or ev.state
  if ph == 'up' or ph == 'release' or ph == 'released' or ev.pressed == false or ev.down == false then return false end
  local now = tonumber(ev.time_ms)
  if not now then
    local ok, m = pcall(function() return ctx.clock:millis() end)
    now = ok and tonumber(m) or nil
  end
  if now and last_key == ev.key and last_key_ms and now - last_key_ms >= 0 and now - last_key_ms < KEY_GAP_MS then return false end
  last_key, last_key_ms = ev.key, now
  return true
end

------------------------------------------------------------------ config

local function load_cfg()
  local ok, s = pcall(function() return ctx.storage:read('config.txt') end)
  if ok and type(s) == 'string' then
    for k, v in s:gmatch('(%w+)=([^\n]*)') do
      if k == 'full' then cfg.full = (v == '1')
      elseif k == 'images' then cfg.images = (v == '1')
      elseif k == 'size' then cfg.size = SIZES[v] and v or 'default'
      else cfg[k] = v end
    end
  end
end

local function save_cfg()
  pcall(function()
    ctx.storage:write('config.txt', 'host=' .. cfg.host .. '\ntoken=' .. cfg.token .. '\nauth=' .. cfg.auth .. '\nfull=' .. (cfg.full and '1' or '0') .. '\nsize=' .. cfg.size .. '\nimages=' .. (cfg.images and '1' or '0'))
  end)
end

local function base_url()
  local host = cfg.host:gsub('^https?://', ''):gsub('/+$', '')
  if host == '' then return nil end
  local u = 'https://' .. host
  if cfg.token ~= '' then u = u .. '/k/' .. cfg.token end
  return u
end

------------------------------------------------------------------ network

local function request_target(path, accept)
  local base = base_url()
  if not base then return nil end
  local url = base .. path
  if multi() and acct then url = url .. (url:find('?', 1, true) and '&' or '?') .. 'acct=' .. acct end
  if cfg.full then url = url .. (url:find('?', 1, true) and '&' or '?') .. 'full=1' end
  local headers = { ['Accept'] = accept or 'application/json' }
  if cfg.auth ~= '' then
    local ok, b64 = pcall(function() return ctx.base64:encode(cfg.auth) end)
    if ok and b64 then headers['Authorization'] = 'Basic ' .. b64 end
  end
  return url, headers
end

-- the bytes of an article image, straight from the resizer URL the Worker gave (another host:
-- no Worker credentials go with it); on_done(body) or on_done(nil, err)
local function fetch_image(url, on_done)
  local headers = { ['Accept'] = 'image/jpeg', ['User-Agent'] = 'Mozilla/5.0 (Xteink RSS mini app)' }
  net_submit({ url = url, method = 'GET', headers = headers }, loading or 'loading image', 30000, function(resp, err)
    if err then on_done(nil, err); return end
    local st = type(resp) == 'table' and (tonumber(resp.status) or tonumber(resp.code)) or nil
    local body = type(resp) == 'table' and resp.body or nil
    if type(body) ~= 'string' or (st and st >= 400) then on_done(nil, 'HTTP ' .. tostring(st)); return end
    on_done(body)
  end)
end

local function request(path, on_done)
  local url, headers = request_target(path)
  if not url then note('set the host in Settings'); on_done(nil, 'no host'); return end
  pcall(function() ctx.net:keep_wifi(120) end)
  -- articles may wait for the Worker's full-text services; lists answer quickly
  local timeout = path:find('/api/article/', 1, true) and 60000 or 30000
  net_submit({ url = url, method = 'GET', headers = headers }, 'loading ' .. short(path, 30), timeout, function(resp, err)
    if err then on_done(nil, err); return end
    if type(resp) ~= 'table' then on_done(nil, 'no response'); return end
    local st = tonumber(resp.status) or tonumber(resp.code)
    local body = resp.body
    if resp.error and not body then on_done(nil, tostring(resp.error)); return end
    if st and st >= 400 then on_done(nil, 'HTTP ' .. st .. ' ' .. short(body or '', 40)); return end
    if type(body) ~= 'string' then on_done(nil, 'empty body'); return end
    local okj, data = pcall(function() return ctx.json:decode(body) end)
    if not okj or type(data) ~= 'table' then on_done(nil, 'bad json: ' .. short(body, 40)); return end
    if data.error then on_done(nil, tostring(data.error)); return end
    note_accounts(data, body, path)
    on_done(data, nil, body)
  end)
  refresh()
end

local function cache_write(name, s) pcall(function() ctx.storage:write(name, s) end) end
local function cache_read(name)
  local ok, s = pcall(function() return ctx.storage:read(name) end)
  if ok and type(s) == 'string' then return s end
  return nil
end

------------------------------------------------------------------ text layout

local function measure(font, s)
  local key = s
  local w = measure_cache[key]
  if w then return w end
  local ok, m = pcall(function() return font:measure(s) end)
  w = (ok and type(m) == 'number') and m or (#s * 11)
  measure_cache[key] = w
  return w
end

-- wrap one paragraph into lines no wider than width using the font's measure;
-- each line is appended to out as { s = text, f = fname, h = line height, x = indent }
local function wrap_para(out, para, fname, width, indent)
  local F = ctx.fonts
  local font = F and F[fname]
  local okl, lh = pcall(function() return font.line_height end)
  lh = (okl and tonumber(lh)) or (fname == 'large' and 30 or fname == 'small' and 20 or 24)
  local function push(s) out[#out + 1] = { s = s, f = fname, h = lh, x = indent } end
  if not font then push(para); return end
  local line, lw = '', 0
  local space_w = measure(font, ' ')
  for word in para:gmatch('%S+') do
    local ww = measure(font, word)
    if ww > width then
      -- long word: flush and split by characters
      if line ~= '' then push(line); line, lw = '', 0 end
      local piece = ''
      for ch in word:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
        if measure(font, piece .. ch) > width then push(piece); piece = ch else piece = piece .. ch end
      end
      line, lw = piece, measure(font, piece)
    elseif line == '' then line, lw = word, ww
    elseif lw + space_w + ww <= width then line, lw = line .. ' ' .. word, lw + space_w + ww
    else push(line); line, lw = word, ww end
  end
  if line ~= '' then push(line) end
end

-- paragraphs come separated by blank lines; "# " marks a heading, "> " a quote, "• " a list item
local function layout_article(data)
  measure_cache = {}
  local out = {}
  local function gap(h) out[#out + 1] = { s = '', f = 'small', h = h, x = 0 } end
  local S = st()
  wrap_para(out, data.title or '', S.title, W - 24, 0)
  local meta = ((data.feed or '') ~= '' and (data.feed .. '  ') or '') .. (data.date or '') .. ((data.source or 'feed') ~= 'feed' and ('  [' .. data.source .. ']') or '')
  if meta ~= '' then wrap_para(out, meta, S.meta, W - 24, 0) end
  -- when the title is no bigger than the text, a rule under it keeps it apart
  if S.rule then gap(8); out[#out + 1] = { s = '', f = 'small', h = 6, x = 0, rule = true } end
  gap(14)
  local text = data.text or ''
  local info = {}
  for _, im in ipairs(type(data.images) == 'table' and data.images or {}) do
    if type(im) == 'table' and im.n then info[tonumber(im.n)] = im end
  end
  for raw_para in (text .. '\n\n'):gmatch('(.-)\n\n') do
    local para = raw_para:gsub('^\n+', ''):gsub('\n+$', '')  -- Lua 5.5: loop variables are const
    local imgn = tonumber(para:match('^%[%[img:(%d+)%]%]$'))
    if imgn then
      local im = info[imgn]
      if im and tonumber(im.w) and tonumber(im.h) then
        out[#out + 1] = { s = '', f = 'small', h = tonumber(im.h) + 12, x = 0, img = imgn, iw = tonumber(im.w), ih = tonumber(im.h), src = tostring(im.src or '') }
      end
    elseif para ~= '' then
      for line in (para .. '\n'):gmatch('([^\n]*)\n') do
        if line:sub(1, 2) == '# ' then wrap_para(out, line:sub(3), S.head, W - 24, 0)
        elseif line:sub(1, 2) == '> ' then wrap_para(out, line:sub(3), S.body, W - 48, 24)
        elseif line:sub(1, 4) == '• ' then wrap_para(out, line, S.body, W - 40, 16)  -- the bullet is 3 UTF-8 bytes
        elseif line ~= '' then wrap_para(out, line, S.body, W - 24, 0) end
      end
      gap(10)
    end
  end
  -- paginate by height
  art.lines = out
  art.starts = { 1 }
  local avail, used = H - TOP - 40, 0
  for i, ln in ipairs(out) do
    if used + ln.h > avail and used > 0 then art.starts[#art.starts + 1] = i; used = 0 end
    used = used + ln.h
  end
  art.pages = #art.starts
  art.page = 1
  art.title = data.title or ''
end

------------------------------------------------------------------ loaders

-- The list keeps every page fetched so far in list.items and shows LIST_N rows from list.top.
-- Next (button, side key or swipe) on the last screen fetches the following page while the
-- Worker says there is more, and appends it; the new rows start on the next screen.

local function list_cache_name(page)
  return cpre() .. 'l_' .. list.kind .. '_' .. (list.id or '0') .. '_' .. page .. '.txt'
end


local function open_list(kind, id, title)
  list.kind, list.id, list.title, list.page = kind, id, title or kind, 0
  list.items, list.has_more, list.cached, list.top = {}, false, false, 1
  preview = nil
  screen = 'list'
end

local function apply_page(page, data, append)
  local items = data.items or {}
  if append then
    local seen = {}
    for _, it in ipairs(list.items) do seen[tostring(it.id)] = true end
    for _, it in ipairs(items) do
      if not seen[tostring(it.id)] then list.items[#list.items + 1] = it end
    end
  else
    list.items, list.top = items, 1
  end
  -- keep the heap in check on very long sessions: drop the oldest rows, keep the view in place
  local extra = #list.items - LIST_MAX_ITEMS
  if extra > 0 then
    for _ = 1, extra do table.remove(list.items, 1) end
    list.top = math.max(1, list.top - extra)
  end
  list.page = page
  list.has_more = data.has_more and true or false
end

-- after(ok) runs once the page is in list.items (from the network or the offline cache)
local function fetch_page(page, append, after, retried)
  local path = '/api/list?kind=' .. list.kind .. '&page=' .. page .. '&n=' .. LIST_N
  if list.id then path = path .. '&id=' .. list.id end
  if not append then list.err = nil end
  request(path, function(data, err, raw)
    local ok = false
    if not data and not retried then          -- a hiccup (Wi-Fi waking up, a slow server): once more
      fetch_page(page, append, after, true)
      return
    end
    if data then
      apply_page(page, data, append)
      list.title = data.title or list.title
      list.cached = false
      note('')
      if raw then cache_write(list_cache_name(page), raw) end
      ok = true
    else
      local raw = cache_read(list_cache_name(page))
      local okj, data2 = pcall(function() return ctx.json:decode(raw) end)
      if raw and okj and type(data2) == 'table' then
        apply_page(page, data2, append)
        list.cached = true
        note('offline: ' .. short(err, 30))
        ok = true
      else
        note(short(err, 44))
        if not append then list.err = err end
      end
    end
    if after then after(ok) end
  end)
end

local function fetch_list() fetch_page(1, false) end            -- first page, or Reload
local function load_more(after)
  if list.has_more and not busy() then fetch_page(list.page + 1, true, after); return true end
  return false
end

local function open_article(item)
  art.id, art.title, art.feed, art.date = tostring(item.id), item.title or '', item.feed or '', item.date or ''
  art.lines, art.starts, art.page, art.pages, art.cached = {}, { 1 }, 1, 1, false
  art.from_preview = nil
  screen = 'article'
  release_images()
  local cname = cpre() .. 'a' .. art.id .. (cfg.images and 'i' or '') .. '.txt'
  local cached = cache_read(cname)
  if cached then
    local okj, data = pcall(function() return ctx.json:decode(cached) end)
    if okj and type(data) == 'table' then layout_article(data); art.cached = true; note('cached'); load_page_images(); return end
  end
  request('/api/article/' .. art.id .. '?max=' .. TEXT_MAX .. '&mark=1' .. (cfg.images and '&images=1' or ''), function(data, err, raw)
    if data then
      layout_article(data); note('')
      load_page_images()
      if raw then cache_write(cname, raw) end
      item.read = true
    else
      note(short(err, 44))
    end
  end)
end

local function fetch_feeds(retried)
  screen = 'feeds'
  feeds.items, feeds.top, feeds.err = {}, 1, nil
  request('/api/feeds', function(data, err, raw)
    if not data and not retried then fetch_feeds(true); return end   -- once more before giving up
    if data then feeds.items = data.items or {}; note(''); if raw then cache_write(cpre() .. 'feeds.txt', raw) end
    else
      local raw2 = cache_read(cpre() .. 'feeds.txt')
      local okj, d2 = pcall(function() return ctx.json:decode(raw2) end)
      if raw2 and okj and type(d2) == 'table' then feeds.items = d2.items or {}; note('offline: ' .. short(err, 30))
      else note(short(err, 44)); feeds.err = err end
    end
  end)
end

------------------------------------------------------------------ images
-- Article images come from the resizer URL the Worker gives (src), as greyscale JPEGs of the
-- size it announced, at most 456 px wide, so they are drawn at their own size. Only the images of the page on screen are fetched and decoded, one
-- at a time; leaving the page or the article releases them. A failed image shows "[image]".

local img_mem = {}            -- n -> { img = decoded } | { failed = true }
local img_bytes = {}          -- n -> JPEG bytes, so paging back does not download again
local img_busy = false

local function page_lines()
  local first = art.starts and art.starts[art.page] or 1
  local last = (art.starts and art.starts[art.page + 1]) and (art.starts[art.page + 1] - 1) or #art.lines
  return first, last
end

release_images = function()
  for _, d in pairs(img_mem) do
    if d.img then pcall(function() d.img:release() end) end
  end
  img_mem, img_bytes, img_busy = {}, {}, false
end

local function decode(n, bytes)
  if type(bytes) ~= 'string' or bytes:sub(1, 2) ~= '\255\216' then img_mem[n] = { failed = true }; return end
  local ok, img = pcall(function() return ctx.image:decode(bytes) end)
  if ok and img then img_mem[n] = { img = img } else img_mem[n] = { failed = true } end
end

load_page_images = function()
  if screen ~= 'article' then return end
  local first, last = page_lines()
  local on_page = {}
  for i = first, last do
    local ln = art.lines[i]
    if ln and ln.img then on_page[ln.img] = ln end
  end
  -- keep only this page's decoded images
  for n, d in pairs(img_mem) do
    if not on_page[n] then
      if d.img then pcall(function() d.img:release() end) end
      img_mem[n] = nil
    end
  end
  if img_busy then return end
  for i = first, last do
    local ln = art.lines[i]
    if ln and ln.img and not img_mem[ln.img] then
      local n, id = ln.img, art.id
      if img_bytes[n] then decode(n, img_bytes[n]); refresh(); return load_page_images() end
      img_busy = true
      fetch_image(ln.src, function(body, err)
        img_busy = false
        if art.id ~= id then return end          -- another article by now
        img_bytes[n] = body
        decode(n, body)
        refresh()
        load_page_images()
      end)
      return
    end
  end
end

draw_image_line = function(gg, ln, y)
  local F = ctx.fonts
  local x = 12 + math.max(0, math.floor((W - 24 - ln.iw) / 2))
  local d = img_mem[ln.img]
  if d and d.img then
    local ok = pcall(function() gg:image(d.img, x, y + 6) end)
    if ok then return end
    d.failed = true
  end
  if d and d.failed then
    gg:text(12, y + 6, '[image]', { font = F and F.small })
  else
    gg:rect(x, y + 6, ln.iw, ln.ih)
    gg:text(x + 10, y + 16, 'image…', { font = F and F.small })
  end
end

------------------------------------------------------------------ accounts

read_accounts = function(raw)
  if type(raw) ~= 'string' then return end
  local okj, data = pcall(function() return ctx.json:decode(raw) end)
  if not okj or type(data) ~= 'table' then return end
  local found = {}
  for _, a in ipairs(type(data.accounts) == 'table' and data.accounts or {}) do
    if type(a) == 'table' and a.id ~= nil then
      found[#found + 1] = { id = tostring(a.id), label = tostring(a.label or ('Account ' .. tostring(a.id))) }
    end
  end
  accounts = found
  local known = false
  for _, a in ipairs(accounts) do if a.id == acct then known = true end end
  if not known then acct = nil end
end

-- ask the Worker which accounts it serves; an older Worker answers without a list (one account)
load_accounts = function()
  if cfg.host == '' then return end
  accounts_fresh = true                        -- asked; note_accounts stores the answer
  local keep = acct
  acct = nil                                   -- the account list itself is not per account
  request('/api', function(data, err, raw) end)
  acct = keep
end

local function accounts_sig(list)
  local t = {}
  for _, a in ipairs(type(list) == 'table' and list or {}) do
    if type(a) == 'table' then t[#t + 1] = tostring(a.id) .. '=' .. tostring(a.label) end
  end
  return table.concat(t, '|')
end

-- every Worker answer passes here: one that carries the account list keeps it current (saved
-- only when it changed); the first one without it (an older Worker) makes the app ask /api once
note_accounts = function(data, raw, path)
  if type(data.accounts) == 'table' then
    accounts_fresh = true
    if accounts_sig(data.accounts) ~= accounts_sig(accounts) then
      read_accounts(raw)
      cache_write('accounts.txt', raw)
    end
  elseif path ~= '/api' and not accounts_fresh then
    load_accounts()
  elseif path == '/api' then
    accounts_fresh = true
    read_accounts(raw)
    cache_write('accounts.txt', raw)
  end
end

------------------------------------------------------------------ drawing

local MENU = { { 'Unread', 'unread' }, { 'Starred', 'starred' }, { 'All', 'all' }, { 'Feeds', 'feeds' }, { 'Settings', 'settings' } }
local SETTINGS = { { 'host', 'Host (e.g. rss.example.workers.dev)' }, { 'token', 'Path token (after /k/), or empty' }, { 'auth', 'user:password for Basic auth, or empty' }, { 'full', 'Full text' }, { 'size', 'Text size (articles and previews)' }, { 'images', 'Images in articles' } }

local function bar(gg, labels)
  local F = ctx.fonts
  local n = #labels
  local bw = math.floor((W - 8) / n) - 2
  for i, l in ipairs(labels) do
    local x = 4 + (i - 1) * (bw + 2)
    gg:rect(x, 6, bw, 36)
    gg:text(x + 8, 13, l, { font = F and F.small })
  end
  gg:line(0, TOP - 4, W, TOP - 4)
  return bw
end

local function bar_hit(x, n)
  local bw = math.floor((W - 8) / n) - 2
  local i = math.floor((x - 4) / (bw + 2)) + 1
  if i >= 1 and i <= n then return i end
  return nil
end

-- an empty list: either really empty, or it could not be loaded (then say why and what to do)
local function draw_empty(gg, y, err, empty_text)
  local F = ctx.fonts
  if not err then gg:text(16, y + 20, empty_text, { font = F and F.medium }); return end
  gg:text(16, y + 20, 'Could not load this list.', { font = F and F.medium })
  gg:text(16, y + 54, short(err, 46), { font = F and F.small })
  gg:text(16, y + 80, 'Check Wi-Fi, then tap Reload.', { font = F and F.small })
end

local function draw_status(gg)
  local F = ctx.fonts
  local s = (busy() and loading) or status
  if s ~= '' then gg:text(8, H - 26, short(s, 52), { font = F and F.small }) end
  if ERR then gg:text(8, H - 48, short('ERR ' .. ERR, 52), { font = F and F.small }) end
end

-- the menu's rows: account folders, the chosen account's menu, or the single-account menu
local function menu_items()
  if not multi() then return MENU end
  if not acct then
    local items = {}
    for _, a in ipairs(accounts) do items[#items + 1] = { a.label, 'acct', a.id } end
    items[#items + 1] = { 'Settings', 'settings' }
    return items
  end
  return { MENU[1], MENU[2], MENU[3], MENU[4], { 'Accounts', 'accounts' } }
end

local function draw_menu(gg)
  local F = ctx.fonts
  gg:text(16, 20, (multi() and acct) and ('RSS · ' .. acct_label()) or 'RSS', { font = F and F.large })
  gg:text(16, 54, (cfg.host ~= '' and cfg.host or 'no host set: open Settings'), { font = F and F.small })
  for i, m in ipairs(menu_items()) do
    local y = 100 + (i - 1) * 70
    gg:rect(16, y, W - 32, 58)
    gg:text(36, y + 16, m[1], { font = F and F.medium })
  end
  draw_status(gg)
end

local function draw_preview(gg)
  local F = ctx.fonts
  local b = preview.box
  gg:rect(b.x, b.y, b.w, b.h)
  gg:rect(b.x + 3, b.y + 3, b.w - 6, b.h - 6)
  local y = b.y + 16
  for _, ln in ipairs(preview.lines) do
    if ln.s ~= '' then gg:text(b.x + 16 + ln.x, y, ln.s, { font = F and F[ln.f] }) end
    y = y + ln.h
  end
  for _, btn in ipairs({ preview.prev, preview.open, preview.close, preview.next }) do
    local shown = (btn ~= preview.prev or preview_can(-1)) and (btn ~= preview.next or preview_can(1))
    if shown then
    gg:rect(btn.x, btn.y, btn.w, btn.h)
    local f = F and F.medium
    local okm, tw = pcall(function() return f:measure(btn.label) end)
    tw = (okm and type(tw) == 'number') and tw or #btn.label * 12
    gg:text(btn.x + math.floor((btn.w - tw) / 2), btn.y + 10, btn.label, { font = f })
    end
  end
end

local function draw_list(gg)
  local F = ctx.fonts
  bar(gg, { 'Back', 'Prev', 'Next', 'Reload' })
  local last = math.min(#list.items, list.top + LIST_N - 1)
  local range = #list.items > 0 and ('  ' .. list.top .. '-' .. last .. ' / ' .. #list.items .. (list.has_more and '+' or '')) or ''
  local who = (multi() and acct) and (acct_label() .. ' · ') or ''
  gg:text(8, TOP + 2, short(who .. list.title .. range .. (list.cached and '  (offline)' or ''), 44), { font = F and F.small })
  if preview then draw_preview(gg); draw_status(gg); return end
  local y = TOP + 26
  if #list.items == 0 and not busy() then draw_empty(gg, y, list.err, 'nothing here') end
  for i = list.top, math.min(#list.items, list.top + LIST_N - 1) do
    local it = list.items[i]
    gg:text(16, y, short(it.title or '', 42), { font = F and F.medium })
    gg:text(16, y + 26, short((it.read and '' or '* ') .. (it.feed or '') .. '  ' .. (it.date or ''), 50), { font = F and F.small })
    gg:line(16, y + 54, W - 16, y + 54)
    y = y + 58
  end
  draw_status(gg)
end

local function draw_feeds(gg)
  local F = ctx.fonts
  bar(gg, { 'Back', 'Prev', 'Next', 'Reload' })
  local y = TOP + 26
  for i = feeds.top, math.min(#feeds.items, feeds.top + LIST_N - 1) do
    local it = feeds.items[i]
    gg:text(16, y, short((it.name or '?') .. ((it.unread or 0) > 0 and ('  (' .. it.unread .. ')') or ''), 42), { font = F and F.medium })
    gg:line(16, y + 54, W - 16, y + 54)
    y = y + 58
  end
  if #feeds.items == 0 and not busy() then draw_empty(gg, y, feeds.err, 'no feeds') end
  draw_status(gg)
end

local function draw_article(gg)
  local F = ctx.fonts
  bar(gg, { 'Back', 'Prev', 'Next', art.page .. '/' .. art.pages })
  local first = art.starts and art.starts[art.page] or 1
  local last = (art.starts and art.starts[art.page + 1]) and (art.starts[art.page + 1] - 1) or #art.lines
  local y = TOP + 4
  for i = first, last do
    local ln = art.lines[i]
    if not ln then break end
    if ln.rule then gg:line(12, y + 2, W - 12, y + 2)
    elseif ln.img then draw_image_line(gg, ln, y)
    elseif ln.s ~= '' then gg:text(12 + ln.x, y, ln.s, { font = F and F[ln.f] }) end
    y = y + ln.h
  end
  if #art.lines == 0 and not busy() then gg:text(16, TOP + 30, short(art.title, 42), { font = F and F.medium }) end
  draw_status(gg)
end

local function draw_settings(gg)
  local F = ctx.fonts
  bar(gg, { 'Back' })
  for i, s in ipairs(SETTINGS) do
    local y = TOP + 20 + (i - 1) * 96
    gg:text(16, y, s[2], { font = F and F.small })
    gg:rect(16, y + 24, W - 32, 48)
    local v = s[1] == 'full' and (cfg.full and 'on' or 'off') or cfg[s[1]]
    if s[1] == 'images' then v = cfg.images and 'on' or 'off' end
    if s[1] == 'size' then v = cfg.size .. '   (tap to change)' end
    if s[1] == 'auth' and v ~= '' then v = v:gsub(':.*$', ':****') end
    gg:text(28, y + 36, short(v ~= '' and v or '(empty)', 40), { font = F and F.medium })
  end
  gg:text(16, TOP + 20 + #SETTINGS * 96, 'tap a field to edit; the host is your Worker', { font = F and F.small })
  draw_status(gg)
end

local function draw_impl(gg)
  gg:clear(0)
  if screen == 'menu' then draw_menu(gg)
  elseif screen == 'list' then draw_list(gg)
  elseif screen == 'feeds' then draw_feeds(gg)
  elseif screen == 'article' then draw_article(gg)
  elseif screen == 'settings' then draw_settings(gg) end
end

function on_draw(c, gg)
  G = gg or G
  if not G then return end
  local ok, e = pcall(draw_impl, G)
  -- a drawing error is painted for this frame only; the next good frame no longer shows it
  if not ok then pcall(function() G:text(6, H - 70, short('draw ERR ' .. tostring(e), 46)) end) end
end

------------------------------------------------------------------ input

local function edit_setting(i)
  local s = SETTINGS[i]
  if not s then return end
  if s[1] == 'full' then cfg.full = not cfg.full; save_cfg(); return end
  if s[1] == 'images' then cfg.images = not cfg.images; save_cfg(); return end
  if s[1] == 'size' then
    local nxt = 1
    for k, name in ipairs(SIZE_ORDER) do if name == cfg.size then nxt = k % #SIZE_ORDER + 1 end end
    cfg.size = SIZE_ORDER[nxt]
    save_cfg()
    return
  end
  local ok, err = pcall(function()
    ctx.input:text({ title = s[2], value = cfg[s[1]] }, function(c, v)
      if type(v) == 'string' then cfg[s[1]] = v:gsub('^%s+', ''):gsub('%s+$', ''); save_cfg() end
      refresh()
    end)
  end)
  if not ok then note('edit ! ' .. short(err, 30)) end
end

-- Prev / Next scroll the rows already loaded; Next past the last loaded row loads the next page.
local function page_list(delta)
  local top = list.top + delta * LIST_N
  if delta < 0 then list.top = math.max(1, top); return end
  if top <= #list.items then list.top = top
  elseif list.has_more then
    if top == #list.items + 1 then list.top = top end
    load_more()
  end
end

local function page_article(delta)
  local p = art.page + delta
  if p >= 1 and p <= art.pages then art.page = p; load_page_images() end
end

local function page_feeds(delta)
  local t = feeds.top + delta * LIST_N
  if t >= 1 and t <= #feeds.items then feeds.top = t end
end

local function tap(x, y)
  if screen == 'menu' then
    for i, m in ipairs(menu_items()) do
      local y0 = 100 + (i - 1) * 70
      if x >= 16 and x < W - 16 and y >= y0 and y < y0 + 58 then
        if m[2] == 'acct' then acct = m[3]
        elseif m[2] == 'accounts' then acct = nil
        elseif m[2] == 'settings' then screen = 'settings'
        elseif m[2] == 'feeds' then fetch_feeds()
        else open_list(m[2], nil, m[1]); fetch_list() end
        return
      end
    end
  elseif screen == 'settings' then
    if y < 46 then screen = 'menu'; load_accounts(); return end
    for i = 1, #SETTINGS do
      local y0 = TOP + 20 + (i - 1) * 96 + 24
      if y >= y0 and y < y0 + 48 then edit_setting(i); return end
    end
  elseif screen == 'list' then
    if y < 46 then
      local b = bar_hit(x, 4)
      if b == 1 then screen = 'menu' elseif b == 2 then page_list(-1) elseif b == 3 then page_list(1) elseif b == 4 then net_unstick(); fetch_list() end
      return
    end
    local r = math.floor((y - (TOP + 26)) / 58) + 1
    local i = list.top + r - 1
    if y >= TOP + 26 and r >= 1 and r <= LIST_N and i <= #list.items then open_article(list.items[i]) end
  elseif screen == 'feeds' then
    if y < 46 then
      local b = bar_hit(x, 4)
      if b == 1 then screen = 'menu' elseif b == 2 then page_feeds(-1) elseif b == 3 then page_feeds(1) elseif b == 4 then net_unstick(); fetch_feeds() end
      return
    end
    local i = math.floor((y - (TOP + 26)) / 58) + feeds.top
    local it = feeds.items[i]
    if it and y >= TOP + 26 then open_list('feed', tostring(it.id), it.name); fetch_list() end
  elseif screen == 'article' then
    if y < 46 then
      local b = bar_hit(x, 4)
      if b == 1 then article_back() elseif b == 2 then page_article(-1) elseif b == 3 then page_article(1) end
      return
    end
    if x < W / 3 then page_article(-1) else page_article(1) end
  end
end

------------------------------------------------------------------ long-press preview

local function row_item(y)
  local r = math.floor((y - (TOP + 26)) / 58) + 1
  local i = list.top + r - 1
  if y >= TOP + 26 and r >= 1 and r <= LIST_N and i <= #list.items then return list.items[i] end
  return nil
end

-- full title, feed and date, and the feed's summary in a box over the list, with Open / Close.
-- The box never reaches the bottom of the screen, so there is always room to tap outside it.
local function open_preview(item)
  measure_cache = {}
  local x, y, w = 16, TOP + 26, W - 32
  local inner = w - 32
  local lines = {}
  local S = st()
  wrap_para(lines, item.title or '', S.title, inner, 0)
  local meta = ((item.feed or '') ~= '' and (item.feed .. '  ') or '') .. (item.date or '') .. (item.read and '' or '  · unread')
  if meta ~= '' then wrap_para(lines, meta, S.meta, inner, 0) end
  lines[#lines + 1] = { s = '', f = 'small', h = 10, x = 0 }
  local ex = item.excerpt or ''
  if ex ~= '' then wrap_para(lines, ex, S.body, inner, 0) else wrap_para(lines, '(no summary in the feed)', 'small', inner, 0) end
  local btn_h, pad = 44, 16
  local max_content = (H - 60) - y - pad - pad - btn_h - pad
  local kept, used = {}, 0
  for _, ln in ipairs(lines) do
    if used + ln.h > max_content then
      local last = kept[#kept]
      if last and last.s ~= '' then last.s = last.s .. ' …' end
      break
    end
    kept[#kept + 1] = ln
    used = used + ln.h
  end
  local h = pad + used + pad + btn_h + pad
  local bw = math.floor((w - 5 * pad) / 4)
  local by = y + h - pad - btn_h
  local function btn(n, label) return { x = x + pad + (n - 1) * (bw + pad), y = by, w = bw, h = btn_h, label = label } end
  preview = {
    item = item, lines = kept, box = { x = x, y = y, w = w, h = h },
    prev = btn(1, 'Prev'), open = btn(2, 'Open'), close = btn(3, 'Close'), next = btn(4, 'Next'),
  }
end

local function inside(r, x, y) return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h end

local function index_of(item)
  for i, it in ipairs(list.items) do if it == item then return i end end
  return nil
end
local function window_of(i) return math.floor((i - 1) / LIST_N) * LIST_N + 1 end

-- closing leaves the list on the screen of the article last previewed
local function close_preview()
  local i = preview and index_of(preview.item)
  if i then list.top = window_of(i) end
  preview = nil
end

preview_can = function(delta)
  local i = preview and index_of(preview.item)
  if not i then return false end
  if delta < 0 then return i > 1 end
  return i < #list.items or list.has_more
end

-- Prev / Next walk the list; Next past the last loaded article loads the next page and shows
-- its first article. If the preview is closed meanwhile, the list moves to that page instead.
local function preview_step(delta)
  local i = preview and index_of(preview.item)
  if not i then return end
  local target = list.items[i + delta]
  if target then open_preview(target); return end
  if delta < 0 then return end
  local anchor = preview.item
  load_more(function(ok)
    local a = index_of(anchor)
    local nxt = ok and a and list.items[a + 1]
    if not nxt or screen ~= 'list' then return end
    if preview and preview.item == anchor then open_preview(nxt)
    elseif not preview then list.top = window_of(a + 1) end
  end)
end

-- an article opened from the preview goes back to that preview (now marked read); one opened
-- straight from the list goes back to the list
article_back = function()
  screen = 'list'
  local it = art.from_preview
  art.from_preview = nil
  if it and index_of(it) then open_preview(it) end
end

local function preview_tap(x, y)
  if inside(preview.prev, x, y) then preview_step(-1)
  elseif inside(preview.next, x, y) then preview_step(1)
  elseif inside(preview.open, x, y) then
    local it = preview.item
    close_preview()
    open_article(it)
    art.from_preview = it
  elseif inside(preview.close, x, y) or not inside(preview.box, x, y) then
    close_preview()
  end
end

function on_input(c, ev)
  ERR = nil   -- a new interaction clears the last error; a new one sets it again
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    if ev.type == 'pointer' then
      -- a long press (the host reports a "hold" phase and / or a "long" gesture) opens the preview
      if ev.gesture == 'long' or ev.phase == 'hold' then
        if screen == 'list' and not preview then
          local it = row_item(ev.y or 0)
          if it then open_preview(it) end
        end
        suppress_up = (ev.phase ~= 'up')
        return
      end
      if ev.phase ~= 'up' then return end
      if suppress_up then suppress_up = false; return end
      if preview then
        local pg = ev.gesture
        if pg == 'swipe_left' or pg == 'swipe_up' then preview_step(1)
        elseif pg == 'swipe_right' or pg == 'swipe_down' then preview_step(-1)
        else preview_tap(ev.x or 0, ev.y or 0) end
        return
      end
      local g = ev.gesture
      if g == 'swipe_left' or g == 'swipe_up' then
        if screen == 'article' then page_article(1) elseif screen == 'list' then page_list(1) elseif screen == 'feeds' then page_feeds(1) end
      elseif g == 'swipe_right' or g == 'swipe_down' then
        if screen == 'article' then page_article(-1) elseif screen == 'list' then page_list(-1) elseif screen == 'feeds' then page_feeds(-1) end
      else
        tap(ev.x or 0, ev.y or 0)
      end
    elseif ev.type == 'key' and key_accepted(ev) then
      local k = ev.key
      if preview then
        if k == 'back' then close_preview()
        elseif k == 'right' or k == 'down' then preview_step(1)
        elseif k == 'left' or k == 'up' then preview_step(-1) end
        return
      end
      if k == 'back' then
        if screen == 'article' then article_back()
        elseif screen == 'settings' then screen = 'menu'; load_accounts()
        elseif screen ~= 'menu' then screen = 'menu'
        elseif multi() and acct then acct = nil end
      elseif k == 'right' or k == 'down' then
        if screen == 'article' then page_article(1) elseif screen == 'list' then page_list(1) elseif screen == 'feeds' then page_feeds(1) end
      elseif k == 'left' or k == 'up' then
        if screen == 'article' then page_article(-1) elseif screen == 'list' then page_list(-1) elseif screen == 'feeds' then page_feeds(-1) end
      end
    end
  end)
  if not ok then ERR = tostring(e) end
  refresh()
  return true
end

function on_tick(c)
  if net_active then busy(); pcall(function() ctx.invalidate() end) end
  -- nothing opened a few seconds after start: refresh the account list now
  if not accounts_fresh and cfg.host ~= '' and not busy() then
    local t = now_ms()
    if t and started_ms and t - started_ms > 3000 then load_accounts(); refresh() end
  end
end

function on_load(c)
  pcall(function() ctx:set_tick(1000) end)
  load_cfg()
  started_ms = now_ms()
  local saved = cache_read('accounts.txt')
  read_accounts(saved)
  -- with a saved list the first answer refreshes it (see note_accounts); without one, ask now
  if cfg.host == '' then screen = 'settings' elseif not saved then load_accounts() end
  pcall(function() ctx.net:keep_wifi(180) end)
end

function on_leave() end
