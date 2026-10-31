-- RSS reader for XTOS Licorice, API 2.9. Two kinds of sources, side by side in one menu:
-- CommaFeed accounts through a commafeed-opds Worker's JSON API, and feeds the reader fetches
-- itself, kept in collections (OPML files in the app's folder on the card; library.lua, feeds.lua).
-- The Worker, when set, also gives those feeds full text (/api/read) and fetches the very large
-- ones (/api/feed). Decodes with ctx.json and keeps an offline cache in ctx.storage.
--
-- Screens: menu (sources, then Unread / Starred / All / Feeds / Tags or Add feed / Settings), list
-- (paged, tap an item), article (word-wrapped text, paged), feeds, tags, add, catalog, settings.
-- Every ctx.* function is a method on this API: colon calls everywhere.

local F = require('feeds')
local Lib = require('library')
local SITE = 'https://omer-faruq-xteink.github.io/touch-licorice-apps/'
local GUIDE = SITE .. 'tools/worker/?for=rss-local'
local CATALOG = SITE .. 'rss/catalog.json'

local W, H, TOP = 480, 800, 56
local QR_PX = 200             -- the source QR code at the end of an article, at most this wide
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

-- Wi-Fi: ctx.net:keep_wifi(n) takes MILLISECONDS (probe round 11: keep_wifi(300) let Wi-Fi drop
-- within 10 s, keep_wifi(300000) kept it up). The app once passed 120 meaning seconds, so with
-- Wi-Fi off in the settings every request paid ~7 s for Wi-Fi to come up again. Now: kept up for
-- 5 minutes from the last tap or request while the app is open, released when it is left.
local WIFI_KEEP_MS = 5 * 60 * 1000
local wifi_kept_at = nil
local function keep_wifi(force)
  local t = now_ms()
  if not force and t and wifi_kept_at and t - wifi_kept_at < 30000 then return end
  wifi_kept_at = t
  pcall(function() ctx.net:keep_wifi(WIFI_KEEP_MS) end)
end

-- Network queue. The host appears to carry one request at a time: a second one started while
-- another is in flight never got an answer (the feeds list stayed on "loading"). So requests
-- run one after the other, images included. A request with no answer within its timeout is
-- cancelled and reported as failed, and the next one starts.
local function short(s, n) s = tostring(s); if #s > n then return s:sub(1, n - 1) .. '~' end return s end
local net_queue, net_active = {}, nil
local net_pump

local function net_finish(job, resp, err)
  if job.done then return end                 -- a late answer after a timeout is ignored
  job.done = true
  if net_active == job then net_active = nil end
  if not net_active and #net_queue == 0 then loading = nil end
  job.on_result(resp, err)
  net_pump()
  pcall(function() ctx:invalidate() end)
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

-- still waiting for an answer? Also enforces the timeouts (checked on every draw and input).
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
local has_cf = true           -- false when /api says the Worker has no CommaFeed account (full text only)
local function multi() return #accounts > 1 end
local read_accounts, load_accounts, note_accounts   -- defined in the accounts section
-- The account list is asked (/api, a tiny answer) as soon as the app starts: that request also
-- brings Wi-Fi up (~7 s with Wi-Fi off in the settings), which the first list needs anyway, so a
-- list opened meanwhile waits only for the rest. Lists and feed answers carry the account list
-- too and keep it current; an older Worker without that is asked /api once more after Settings.
-- No timer: timeouts are checked on draw and input.
local accounts_fresh = false
-- feeds on the reader: the collections (OPML files) and where the menu is: nil (the sources, or
-- the only source), 'cf' (a CommaFeed account; acct when there are several) or 'local' (coll)
local coll_list = {}
local where, coll = nil, nil
local load_page_images, release_images, draw_image_line   -- defined in the images section
local draw_source_line                                    -- the source QR block, images section
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
-- feeds and tags screens: the same rows, one name each (a tag's opens its articles)
local feeds = { items = {}, top = 1, path = {} }   -- path: the folder open in a collection's feeds
local tags = { items = {}, top = 1 }
local function names() return screen == 'tags' and tags or feeds end
local function on_names() return screen == 'feeds' or screen == 'tags' end
-- article screen
local art = { id = nil, title = '', feed = '', date = '', lines = {}, starts = { 1 }, page = 1, pages = 1, cached = false }
local measure_cache = {}

local function note(s) status = tostring(s or '') end
local function urlenc(s)
  return (tostring(s):gsub('[^%w%-%._~]', function(ch) return string.format('%%%02X', ch:byte()) end))
end
-- an article's tags as one line ("a, b"), from the list item. The Worker sends them as the
-- string tag_line too: the preview showed no tags while the Worker sent them as an array.
local function tag_text(item)
  if type(item.tag_line) == 'string' then return item.tag_line end
  local t = {}
  for _, name in ipairs(type(item.tags) == 'table' and item.tags or {}) do t[#t + 1] = tostring(name) end
  return table.concat(t, ', ')
end

local function refresh() pcall(function() ctx:invalidate() end) end

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

local function request(path, on_done, label)
  local url, headers = request_target(path)
  if not url then note('set the host in Settings'); on_done(nil, 'no host'); return end
  keep_wifi()
  -- articles may wait for the Worker's full-text services; lists answer quickly
  local timeout = path:find('/api/article/', 1, true) and 60000 or 30000
  net_submit({ url = url, method = 'GET', headers = headers }, label or ('loading ' .. short(path, 30)), timeout, function(resp, err)
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

-- Offline copies of articles: the CACHE_KEEP most recently opened stay, older ones are removed.
-- cache_idx.txt lists them, oldest first; copies made before that list existed go in front.
local CACHE_KEEP, CACHE_IDX = 100, 'cache_idx.txt'
local cache_names = nil
local clear_armed = false            -- Settings: the first tap on the offline row asks for a second
local function is_copy(n) return n:match('^a%d+i?%.txt$') or n:match('^x%d+_a%d+i?%.txt$') or n:match('^b%x+i?%.txt$') end
local function copies()
  if cache_names then return cache_names end
  cache_names = {}
  local raw = cache_read(CACHE_IDX)
  if raw then
    for n in raw:gmatch('[^\n]+') do cache_names[#cache_names + 1] = n end
  else
    local ok, t = pcall(function() return ctx.storage:list() end)
    for _, e in ipairs((ok and type(t) == 'table') and t or {}) do
      local n = type(e) == 'table' and e.name or e
      if type(n) == 'string' and is_copy(n) then cache_names[#cache_names + 1] = n end
    end
    table.sort(cache_names)
  end
  return cache_names
end
local function cache_remove(name) pcall(function() ctx.storage:remove(name) end) end
local function cache_save()
  cache_write(CACHE_IDX, table.concat(cache_names, '\n'))
end
-- name was just read or written: it moves to the end, the oldest beyond CACHE_KEEP go
local function cache_touch(name)
  local out = {}
  for _, n in ipairs(copies()) do if n ~= name then out[#out + 1] = n end end
  out[#out + 1] = name
  while #out > CACHE_KEEP do cache_remove(table.remove(out, 1)) end
  cache_names = out
  cache_save()
end
local function cache_clear()
  for _, n in ipairs(copies()) do cache_remove(n) end
  cache_names = {}
  cache_save()
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
-- an address (no spaces) cut into lines that fit width in the small font, preferably after
-- / . - ? & =; at most max_lines, the last one ending in "~" when the address is longer
local function wrap_address(s, width, max_lines)
  local font = ctx.fonts and ctx.fonts.small
  local function wd(t)
    local ok, m = pcall(function() return font:measure(t) end)
    return (ok and type(m) == 'number') and m or (#t * 11)
  end
  local lines = {}
  while #s > 0 and #lines < max_lines do
    if wd(s) <= width then lines[#lines + 1] = s; return lines end
    local n = 1
    while n < #s and wd(s:sub(1, n + 1)) <= width do n = n + 1 end
    if #lines == max_lines - 1 then lines[#lines + 1] = s:sub(1, math.max(1, n - 1)) .. '~'; return lines end
    local cut = n
    for i = n, math.max(1, n - 12), -1 do
      if s:sub(i, i):match('[/%.%-%?&=]') then cut = i; break end
    end
    lines[#lines + 1] = s:sub(1, cut)
    s = s:sub(cut + 1)
  end
  return lines
end

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
  -- the article's link as a QR code under a rule (drawn by draw_source_line; just the address
  -- when no QR can be made)
  local url = type(data.url) == 'string' and data.url or ''
  if url:match('^https?://') then
    local addr = wrap_address(url:gsub('^https?://', ''):gsub('^www%.', ''), W - 24, 3)
    gap(6)
    out[#out + 1] = { s = '', f = 'small', h = 6, x = 0, rule = true }
    out[#out + 1] = { s = '', f = 'small', h = 30 + QR_PX + 12 + #addr * 22, x = 0, source = url, addr = addr }
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
  -- a tag name may hold any character: hex for anything but letters and digits
  local id = tostring(list.id or '0'):gsub('[^%w]', function(ch) return string.format('_%02x', ch:byte()) end)
  return cpre() .. 'l_' .. list.kind .. '_' .. id .. '_' .. page .. '.txt'
end


local function open_list(kind, id, title)
  list.kind, list.id, list.title, list.page = kind, id, title or kind, 0
  list.items, list.has_more, list.cached, list.top = {}, false, false, 1
  list['local'] = nil
  preview = nil
  screen = 'list'
end

-- Each row's tag_line, read from the answer's text rather than the decoded table: on the reader
-- the preview showed no tags while list items carried them as an array, so the decoded table
-- is not trusted with them. The Worker writes "id" first in every item and "tag_line" after it.
local function raw_tag_lines(items, raw)
  if type(raw) ~= 'string' then return end
  local found = {}
  for id, line in raw:gmatch('"id":"(%d+)",[^{}]-"tag_line":"(.-)"[,}]') do
    found[id] = line
  end
  for _, it in ipairs(items) do
    local line = found[tostring(it.id)]
    if line then it.tag_line = (line:gsub('\\(.)', '%1')) end
  end
end

local function apply_page(page, data, append, raw)
  local items = data.items or {}
  raw_tag_lines(items, raw)
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
  if list.id then path = path .. '&id=' .. urlenc(list.id) end
  if not append then list.err = nil end
  request(path, function(data, err, raw)
    local ok = false
    if not data and not retried then          -- a hiccup (Wi-Fi waking up, a slow server): once more
      fetch_page(page, append, after, true)
      return
    end
    if data then
      apply_page(page, data, append, raw)
      list.title = data.title or list.title
      list.cached = false
      note('')
      if raw then cache_write(list_cache_name(page), raw) end
      ok = true
    else
      local raw = cache_read(list_cache_name(page))
      local okj, data2 = pcall(function() return ctx.json:decode(raw) end)
      if raw and okj and type(data2) == 'table' then
        apply_page(page, data2, append, raw)
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

------------------------------------------------------------------ sources and feeds on the reader

local function tz()
  local ok, t = pcall(function() return ctx.clock:now() end)
  return (ok and type(t) == 'table' and tonumber(t.offset_minutes)) or 0
end

local function reload_colls()
  Lib.forget()
  coll_list = Lib.collections()
  if coll then coll = Lib.collection(coll.file) end
end

-- the menu's sources: CommaFeed (one entry per account) when a Worker is set, then the collections
local function sources()
  local out = {}
  if cfg.host ~= '' and has_cf then
    if multi() then
      for _, a in ipairs(accounts) do out[#out + 1] = { kind = 'cf', id = a.id, label = a.label } end
    else
      out[#out + 1] = { kind = 'cf', label = 'CommaFeed' }
    end
  end
  for _, c in ipairs(coll_list) do out[#out + 1] = { kind = 'local', file = c.file, label = c.title } end
  return out
end

-- the collection open (its feeds screen, a feed's articles), or nil
local function cur_coll()
  if where == 'local' then return coll end
  return nil
end

local LIST_KIND = { unread = 'unread', starred = 'starred', all = 'all', feed = 'feed' }

local function show_local_rows(keep_top)
  local c = cur_coll()
  local rows = c and Lib.items(c, LIST_KIND[list.kind] or 'all', list.id) or {}
  local off = tz()
  local kept = {}
  for i, r in ipairs(rows) do
    if i > LIST_MAX_ITEMS then break end
    r.date = F.format_date(r.d, off)
    kept[#kept + 1] = r
  end
  list.items, list.has_more, list.cached = kept, false, false
  if not keep_top or list.top > #kept then list.top = 1 end
end

local fill_local_feeds        -- defined with the feeds screen

-- the feed whose articles are open; the list follows when it comes in
local function refresh_local(force)
  if not cur_coll() or not list.id then return end
  keep_wifi()
  Lib.refresh({ feeds = { { url = list.id } } }, force, function()
    if screen == 'list' and list['local'] and not preview then show_local_rows(true) end
    if screen == 'feeds' and feeds['local'] then fill_local_feeds() end
    refresh()
  end, function(changed, failed, n)
    if n == 0 then note('up to date')
    elseif failed > 0 then note('the feed could not be loaded')
    else note('') end
    refresh()
  end)
end

local function open_local_list(kind, id, title)
  list.kind, list.id, list.title, list.page = kind, id, title or kind, 1
  list.items, list.has_more, list.cached, list.top, list.err = {}, false, false, 1, nil
  list['local'] = true
  preview = nil
  screen = 'list'
  show_local_rows(false)
  refresh_local(false)
end

local function fetch_list() list['local'] = nil; fetch_page(1, false) end   -- first page, or Reload
local function load_more(after)
  if list.has_more and not busy() then fetch_page(list.page + 1, true, after); return true end
  return false
end

local open_local_article      -- feeds on the reader: below

local function open_article(item)
  if item['local'] then open_local_article(item); return end
  art.id, art.title, art.feed, art.date = tostring(item.id), item.title or '', item.feed or '', item.date or ''
  art.lines, art.starts, art.page, art.pages, art.cached = {}, { 1 }, 1, 1, false
  art.from_preview = nil
  screen = 'article'
  release_images()
  local cname = cpre() .. 'a' .. art.id .. (cfg.images and 'i' or '') .. '.txt'
  local cached = cache_read(cname)
  if cached then
    local okj, data = pcall(function() return ctx.json:decode(cached) end)
    if okj and type(data) == 'table' then
      layout_article(data); art.cached = true; note('cached'); cache_touch(cname); load_page_images()
      -- the copy is from an earlier visit: mark it read again if it is unread now (offline: no matter)
      if not item.read then item.read = true; request('/api/mark/' .. art.id .. '?read=1', function() end, 'marking read') end
      return
    end
  end
  request('/api/article/' .. art.id .. '?max=' .. TEXT_MAX .. '&mark=1' .. (cfg.images and '&images=1' or ''), function(data, err, raw)
    if data then
      layout_article(data); note('')
      load_page_images()
      if raw then cache_write(cname, raw); cache_touch(cname) end
      item.read = true
    else
      note(short(err, 44))
    end
  end)
end

-- An article of a feed on the reader: its own text when the feed carries it, else the full text
-- through the Worker (when Full text is on), else the summary, saying how to get more.
open_local_article = function(item)
  art.id = 'l' .. F.hash(item.feed_url .. '|' .. item.id)
  art.title, art.feed, art.date = item.title or '', item.feed or '', item.date or ''
  art.lines, art.starts, art.page, art.pages, art.cached = {}, { 1 }, 1, 1, false
  art.from_preview = nil
  screen = 'article'
  release_images()
  if not item.read then Lib.mark(item, 'r', true) end
  local function show(text, imgs, source)
    layout_article({ title = item.title, feed = item.feed, date = item.date, url = item.url, text = text, images = imgs, source = source })
    load_page_images()
  end
  local summary = (item.excerpt and item.excerpt ~= '') and item.excerpt or '(no summary in the feed)'
  local html = item.has_text and not item.via_worker and Lib.content(item) or nil
  if html and not cfg.full then
    local imgs = cfg.images and {} or nil
    show(F.html_to_text(html, TEXT_MAX, imgs, item.url), imgs)
    return
  end
  local worker = base_url() ~= nil
  if worker and item.url and (cfg.full or item.via_worker) then
    local path = cfg.full and ('/api/read?max=' .. TEXT_MAX .. '&url=' .. urlenc(item.url))
      or ('/api/feed?url=' .. urlenc(item.feed_url) .. '&id=' .. urlenc(item.id) .. '&max=' .. TEXT_MAX)
    if cfg.images then path = path .. '&images=1' end
    local cname = 'b' .. F.hash(path) .. (cfg.images and 'i' or '') .. '.txt'
    local cached = cache_read(cname)
    local okj, data = false, nil
    if cached then okj, data = pcall(function() return ctx.json:decode(cached) end) end
    if okj and type(data) == 'table' then
      data.title, data.feed, data.date, data.url = item.title, item.feed, item.date, item.url
      layout_article(data); art.cached = true; note('cached'); cache_touch(cname); load_page_images()
      return
    end
    local id = art.id
    request(path, function(d, err, raw)
      if art.id ~= id then return end
      if d and type(d.text) == 'string' and d.text ~= '' then
        d.title, d.feed, d.date, d.url = item.title, item.feed, item.date, item.url
        layout_article(d); note('')
        load_page_images()
        if raw then cache_write(cname, raw); cache_touch(cname) end
      elseif html then                                -- the feed's own text, when the service fails
        local imgs = cfg.images and {} or nil
        show(F.html_to_text(html, TEXT_MAX, imgs, item.url), imgs)
        note('full text: ' .. short(err or 'nothing found', 30))
      else
        show(summary .. '\n\n(The full text could not be loaded: ' .. short(err or 'nothing found', 40) .. '.)')
      end
    end, cfg.full and 'loading the full text' or 'loading the article')
    return
  end
  if html then
    local imgs = cfg.images and {} or nil
    show(F.html_to_text(html, TEXT_MAX, imgs, item.url), imgs)
    return
  end
  if cfg.full then
    show(summary .. '\n\nOnly a summary is in this feed. The whole article needs a Worker: see Settings, Full text.')
  else
    show(summary .. '\n\nOnly a summary is in this feed.' .. (worker and ' Full text in Settings fetches the whole article through your Worker.' or ''))
  end
end

local function fetch_feeds(retried)
  feeds['local'] = nil
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

-- a collection's feeds screen: Add feed, then the folders of the open folder (feeds.path) and its
-- feeds, each with its unread count (from the index: no feed's file is read here); a feed that
-- could not be loaded last time says so
local function under(f, path)
  local p = f.path or {}
  if #p < #path then return false end
  for i, n in ipairs(path) do if p[i] ~= n then return false end end
  return true
end

fill_local_feeds = function()
  local c = cur_coll()
  local path = feeds.path
  local items, folders, seen = {}, {}, {}
  if #path == 0 then items[1] = { kind = 'add', name = 'Add feed' } end
  local list_feeds = {}
  for _, f in ipairs(c and c.feeds or {}) do
    if under(f, path) then
      local p = f.path or {}
      if #p == #path then list_feeds[#list_feeds + 1] = f
      else
        local name = p[#path + 1]
        if not seen[name] then seen[name] = { kind = 'folder', folder = name, n = 0 }; folders[#folders + 1] = seen[name] end
        seen[name].n = seen[name].n + 1
      end
    end
  end
  for _, d in ipairs(folders) do
    d.name = d.folder .. '/  (' .. d.n .. (d.n == 1 and ' feed)' or ' feeds)')
    items[#items + 1] = d
  end
  for _, f in ipairs(list_feeds) do
    local info = Lib.info(f.url)
    local name = (f.title and f.title ~= '' and f.title ~= f.url) and f.title or f.url
    items[#items + 1] = { id = f.url, name = name .. (info.e and '  (!)' or ''), unread = info.u or 0, ['local'] = true }
  end
  feeds.items = items
  if feeds.top > #items then feeds.top = 1 end
end

-- keep: back from a feed's articles, to the same folder and screen of rows
local function open_local_feeds(keep)
  screen = 'feeds'
  feeds['local'] = true
  feeds.err = nil
  if not keep then feeds.items, feeds.top, feeds.path = {}, 1, {} end
  fill_local_feeds()
end

-- Back in a collection's feeds: up one folder, then to the menu
local function local_feeds_back()
  if #feeds.path > 0 then
    local name = table.remove(feeds.path)
    feeds.top = 1
    fill_local_feeds()
    for i, it in ipairs(feeds.items) do
      if it.kind == 'folder' and it.folder == name then feeds.top = math.floor((i - 1) / LIST_N) * LIST_N + 1 end
    end
  else
    screen, where, coll = 'menu', nil, nil
  end
end

-- Add feed: a list of feeds to tick (from the site, or the few below without a network), or an
-- address typed in (a site, a feed or an OPML). Feeds go into the current collection; an OPML becomes one.
local BUILTIN_CATALOG = {
  { name = 'World news', feeds = {
    { title = 'BBC News', url = 'https://feeds.bbci.co.uk/news/rss.xml' },
    { title = 'The Guardian: World', url = 'https://www.theguardian.com/world/rss' },
    { title = 'NYT: Top Stories', url = 'https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml' } } },
  { name = 'Technology', feeds = {
    { title = 'Ars Technica', url = 'https://feeds.arstechnica.com/arstechnica/index' },
    { title = 'The Verge', url = 'https://www.theverge.com/rss/index.xml' },
    { title = 'Hacker News: Front Page', url = 'https://hnrss.org/frontpage' } } },
  { name = 'Science', feeds = {
    { title = 'NASA', url = 'https://www.nasa.gov/feed/' } } },
  { name = 'Culture and comics', feeds = {
    { title = 'kottke.org', url = 'https://feeds.kottke.org/main' },
    { title = 'xkcd', url = 'https://xkcd.com/rss.xml' } } },
}
local catalog = { cats = nil, cat = nil, top = 1, loading = false }
local ADD_ROWS = { { 'Choose from a list', 'list' }, { 'Type an address', 'type' } }

local function open_add() screen = 'add' end
-- Back from Add feed: to the collection's feeds it was opened from
local function add_back()
  if cur_coll() then open_local_feeds(true) else screen = 'menu' end
end

local function catalog_rows()
  if catalog.cat then return catalog.cat.feeds or {} end
  return catalog.cats or {}
end

local function open_catalog()
  screen = 'catalog'
  catalog.cat, catalog.top = nil, 1
  if catalog.cats then return end
  catalog.cats = BUILTIN_CATALOG
  catalog.loading = true
  keep_wifi()
  net_submit({ url = CATALOG, method = 'GET', headers = { ['Accept'] = 'application/json' } }, 'loading the list', 30000, function(resp)
    catalog.loading = false
    local body = type(resp) == 'table' and resp.body or nil
    local okj, d = false, nil
    if type(body) == 'string' then okj, d = pcall(function() return ctx.json:decode(body) end) end
    if okj and type(d) == 'table' and type(d.categories) == 'table' and #d.categories > 0 then
      catalog.cats = d.categories
      if catalog.cat then catalog.cat = nil; catalog.top = 1 end
    end
    refresh()
  end)
end

local function after_add(msg)
  reload_colls()
  note(msg)
end

-- Add feed puts feeds into the collection it was opened from (My feeds when there is no other)
local function add_target() return cur_coll() or Lib.collection(Lib.MY) end

local function catalog_toggle(f)
  local into = add_target()
  if Lib.has_feed(f.url, into.file) then
    Lib.remove_feed(into, f.url)
    after_add('removed: ' .. short(f.title, 34))
  else
    Lib.add_feed(f.url, f.title or '', f.site, into.file)
    after_add('added: ' .. short(f.title, 36))
  end
end

local function add_by_address()
  local ok, e = pcall(function()
    ctx.input:text({ title = 'Site, feed or OPML address', text = '', max_bytes = 256 }, function(c, v)
      if type(v) ~= 'string' or not v:match('%S') then refresh(); return end
      keep_wifi()
      Lib.probe(v, function(kind, d)
        if kind == 'feed' then
          local into = add_target()
          local added = Lib.add_feed(d.url, d.title or '', nil, into.file)
          after_add(added and ('added: ' .. short(d.title ~= '' and d.title or d.url, 36)) or ('already in ' .. short(into.title, 30)))
        elseif kind == 'opml' then
          local o = F.parse_opml(d.text)
          local name = (o.title ~= '' and o.title) or 'Imported feeds'
          Lib.save_collection(Lib.file_name(name), name, o.feeds)
          after_add('new collection: ' .. short(name, 24) .. ' (' .. #o.feeds .. ' feeds)')
        else
          note(short(d or 'nothing found', 44))
        end
        refresh()
      end)
      refresh()
    end)
  end)
  if not ok then note('edit ! ' .. short(e, 30)) end
end

-- Remove a feed: long-press it in Feeds
local removing = nil

-- the tag list is asked only when Tags is opened
local function fetch_tags(retried)
  screen = 'tags'
  tags.items, tags.top, tags.err = {}, 1, nil
  request('/api/tags', function(data, err, raw)
    if not data and not retried then fetch_tags(true); return end
    if data then tags.items = data.items or {}; note(''); if raw then cache_write(cpre() .. 'tags.txt', raw) end
    else
      local raw2 = cache_read(cpre() .. 'tags.txt')
      local okj, d2 = pcall(function() return ctx.json:decode(raw2) end)
      if raw2 and okj and type(d2) == 'table' then tags.items = d2.items or {}; note('offline: ' .. short(err, 30))
      else note(short(err, 44)); tags.err = err end
    end
  end, 'loading tags')
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

local source_qr = nil         -- { url, img } | { url, failed = true } for the open article

release_images = function()
  for _, d in pairs(img_mem) do
    if d.img then pcall(function() d.img:release() end) end
  end
  img_mem, img_bytes, img_busy = {}, {}, false
  if source_qr and source_qr.img then pcall(function() source_qr.img:release() end) end
  source_qr = nil
end

-- "Source:" with the article's link as a QR code (the firmware's own encoder, scaled up by whole
-- steps so the modules stay sharp). Anything going wrong leaves just the address as text: the
-- article itself never depends on it.
draw_source_line = function(gg, ln, y)
  local F = ctx.fonts
  gg:text(12, y + 4, 'Source:', { font = F and F.small })
  if not source_qr or source_qr.url ~= ln.source then
    if source_qr and source_qr.img then pcall(function() source_qr.img:release() end) end
    local ok, img = pcall(function() return ctx.qr:encode(ln.source) end)
    source_qr = (ok and img) and { url = ln.source, img = img } or { url = ln.source, failed = true }
  end
  local drawn = false
  if source_qr.img then
    local ok = pcall(function()
      local w = tonumber(source_qr.img.width) or 0
      local size = QR_PX
      if w > 0 then size = w * math.max(1, math.floor(QR_PX / w)) end
      gg:image(source_qr.img, math.floor((W - size) / 2), y + 30, { w = size, h = size })
    end)
    drawn = ok
    if not ok then source_qr.failed = true end
  end
  local ay = drawn and (y + 30 + QR_PX + 8) or (y + 30)
  for _, a in ipairs(ln.addr or {}) do gg:text(12, ay, a, { font = F and F.small }); ay = ay + 22 end
end

local function decode(n, bytes)
  if type(bytes) ~= 'string' or bytes:sub(1, 2) ~= '\255\216' then img_mem[n] = { failed = true }; return end
  -- image_decode is an optional capability: without it the picture stays a box
  if not (ctx.capabilities and ctx.capabilities.image_decode) then img_mem[n] = { failed = true }; return end
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
  if data.commafeed ~= nil then has_cf = data.commafeed ~= false end
  local known = false
  for _, a in ipairs(accounts) do if a.id == acct then known = true end end
  if not known then acct = nil end
end

-- ask the Worker which accounts it serves; an older Worker answers without a list (one account)
load_accounts = function(label)
  if cfg.host == '' then return end
  accounts_fresh = true                        -- asked; note_accounts stores the answer
  local keep = acct
  acct = nil                                   -- the account list itself is not per account
  request('/api', function(data, err, raw) end, label)
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
    local cf_changed = path == '/api' and data.commafeed ~= nil and (data.commafeed ~= false) ~= has_cf
    if cf_changed or accounts_sig(data.accounts) ~= accounts_sig(accounts) then
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

local MENU = { { 'Unread', 'unread' }, { 'Starred', 'starred' }, { 'All', 'all' }, { 'Feeds', 'feeds' }, { 'Tags', 'tags' }, { 'Settings', 'settings' } }
local SETTINGS = { { 'host', 'Host (e.g. rss.example.workers.dev)' }, { 'token', 'Path token (after /k/), or empty' }, { 'auth', 'user:password for Basic auth, or empty' }, { 'full', 'Full text' }, { 'size', 'Text size (articles and previews)' }, { 'images', 'Images in articles' },
                   { 'cache', 'Articles saved offline (the latest ' .. CACHE_KEEP .. ' stay)' } }

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

-- the menu's rows: the sources (CommaFeed accounts and collections), the chosen one's menu, or
-- with a single source its menu at once; with none, a way to start
-- The sources: CommaFeed (a folder per account), My feeds (always, so feeds are added inside the
-- collection they go into) and the other collections, then Settings. A collection opens on its
-- feeds; CommaFeed on its own menu.
local function menu_items()
  local settings = { 'Settings', 'settings' }
  if where == 'cf' then
    local t = {}
    for i = 1, 5 do t[#t + 1] = MENU[i] end
    t[#t + 1] = settings
    t[#t + 1] = { 'Back', 'sources' }
    return t
  end
  local items = {}
  for _, src in ipairs(sources()) do items[#items + 1] = { src.label, 'src', src } end
  items[#items + 1] = settings
  return items
end

-- nothing set up yet: no Worker and an empty My feeds alone
local function first_run()
  return cfg.host == '' and #coll_list == 1 and #Lib.collection(Lib.MY).feeds == 0
end

-- a QR code of url, its modules scaled up by whole steps (kept until the screen changes)
local qr_img = nil
local function draw_qr(gg, url, x, y, px)
  if not qr_img or qr_img.url ~= url then
    if qr_img and qr_img.img then pcall(function() qr_img.img:release() end) end
    local ok, img = pcall(function() return ctx.qr:encode(url) end)
    qr_img = { url = url, img = ok and img or nil }
  end
  if not qr_img.img then return false end
  local ok = pcall(function()
    local w = tonumber(qr_img.img.width) or 0
    local size = px
    if w > 0 then size = w * math.max(1, px // w) end
    gg:image(qr_img.img, x + (px - size) // 2, y, { w = size, h = size })
  end)
  return ok
end

local function draw_menu(gg)
  local F = ctx.fonts
  local title = (where == 'cf' and multi() and acct) and ('RSS · ' .. acct_label()) or 'RSS'
  gg:text(16, 20, title, { font = F and F.large })
  local sub = first_run() and 'No feeds yet.' or (cfg.host ~= '' and cfg.host) or ''
  gg:text(16, 54, short(sub, 50), { font = F and F.small })
  local items = menu_items()
  for i, m in ipairs(items) do
    local y = 100 + (i - 1) * 70
    gg:rect(16, y, W - 32, 58)
    gg:text(36, y + 16, short(m[1], 36), { font = F and F.medium })
  end
  if first_run() then
    local y = 100 + #items * 70 + 20
    gg:text(16, y, 'Open My feeds, then Add feed: a site, or one', { font = F and F.small })
    gg:text(16, y + 22, 'from the list. CommaFeed, or full text, needs a', { font = F and F.small })
    gg:text(16, y + 44, 'Worker of your own: scan to set one up.', { font = F and F.small })
    draw_qr(gg, SITE .. 'tools/worker/', (W - 200) // 2, y + 76, 200)
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
  local btns = {}
  for _, k in ipairs({ 'star', 'read', 'tags', 'prev', 'open', 'close', 'next' }) do
    if preview[k] then btns[#btns + 1] = preview[k] end
  end
  for _, btn in ipairs(btns) do
    local shown = (btn ~= preview.prev or preview_can(-1)) and (btn ~= preview.next or preview_can(1))
    if shown then
    gg:rect(btn.x, btn.y, btn.w, btn.h)
    local f = F and (btn.small and F.small or F.medium)
    local okm, tw = pcall(function() return f:measure(btn.label) end)
    tw = (okm and type(tw) == 'number') and tw or #btn.label * 12
    gg:text(btn.x + math.floor((btn.w - tw) / 2), btn.y + 10, btn.label, { font = f })
    end
  end
end

local function draw_list(gg)
  local F = ctx.fonts
  if preview then draw_preview(gg); draw_status(gg); return end   -- the box alone, nothing above it
  bar(gg, { 'Back', 'Prev', 'Next', 'Reload' })
  local last = math.min(#list.items, list.top + LIST_N - 1)
  local range = #list.items > 0 and ('  ' .. list.top .. '-' .. last .. ' / ' .. #list.items .. (list.has_more and '+' or '')) or ''
  local who = (multi() and acct) and (acct_label() .. ' · ') or ''
  gg:text(8, TOP + 2, short(who .. list.title .. range .. (list.cached and '  (offline)' or ''), 44), { font = F and F.small })
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
  local feeds = names()
  local is_local = feeds['local'] and screen == 'feeds'
  bar(gg, is_local and { 'Back', 'Prev', 'Next' } or { 'Back', 'Prev', 'Next', 'Reload' })
  if is_local then
    local c = cur_coll()
    local head = (c and c.title or '') .. (#feeds.path > 0 and (' / ' .. table.concat(feeds.path, ' / ')) or '')
    if #feeds.items > LIST_N then head = head .. '  ' .. feeds.top .. '-' .. math.min(#feeds.items, feeds.top + LIST_N - 1) .. ' / ' .. #feeds.items end
    gg:text(8, TOP + 2, short(head, 46), { font = F and F.small })
  end
  local y = TOP + 26
  for i = feeds.top, math.min(#feeds.items, feeds.top + LIST_N - 1) do
    local it = feeds.items[i]
    gg:text(16, y, short((it.name or '?') .. ((it.unread or 0) > 0 and ('  (' .. it.unread .. ')') or ''), 42), { font = F and F.medium })
    gg:line(16, y + 54, W - 16, y + 54)
    y = y + 58
  end
  if #feeds.items == 0 and not busy() then draw_empty(gg, y, feeds.err, screen == 'tags' and 'no tags yet' or (feeds['local'] and 'no feeds: Add feed in the menu' or 'no feeds')) end
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
    elseif ln.source then pcall(draw_source_line, gg, ln, y)
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
    if s[1] == 'cache' then v = clear_armed and ('Tap again to delete ' .. #copies()) or (#copies() .. '   (tap to delete)') end
    if s[1] == 'auth' and v ~= '' then v = v:gsub(':.*$', ':****') end
    gg:text(28, y + 36, short(v ~= '' and v or '(empty)', 40), { font = F and F.medium })
  end
  gg:text(16, TOP + 20 + #SETTINGS * 96, 'tap a field to edit; the host is your Worker', { font = F and F.small })
  draw_status(gg)
end

local function draw_rows(gg, rows, top, label_of)
  local F = ctx.fonts
  local y = TOP + 26
  for i = top, math.min(#rows, top + LIST_N - 1) do
    gg:text(16, y, short(label_of(rows[i]), 42), { font = F and F.medium })
    gg:line(16, y + 54, W - 16, y + 54)
    y = y + 58
  end
end

local function draw_add(gg)
  local F = ctx.fonts
  bar(gg, { 'Back' })
  gg:text(16, TOP + 10, 'Add feed', { font = F and F.large })
  for i, r in ipairs(ADD_ROWS) do
    local y = TOP + 60 + (i - 1) * 70
    gg:rect(16, y, W - 32, 58)
    gg:text(36, y + 16, r[1], { font = F and F.medium })
  end
  local path = (ctx.files and type(ctx.files.path) == 'string' and ctx.files.path ~= '') and ctx.files.path or 'AppFiles/rss'
  local y = TOP + 60 + #ADD_ROWS * 70 + 16
  for _, l in ipairs({ short('Feeds you add go into ' .. add_target().title .. '.', 48), 'A site address finds its feed; an OPML address',
    'becomes a collection of its own. OPML files', 'copied into ' .. path .. '/', 'are collections too (USB mode).' }) do
    gg:text(16, y, l, { font = F and F.small }); y = y + 22
  end
  draw_status(gg)
end

local function draw_catalog(gg)
  local F = ctx.fonts
  bar(gg, { 'Back', 'Prev', 'Next' })
  gg:text(8, TOP + 2, short(catalog.cat and (catalog.cat.name .. ': tap to add or remove') or 'Choose a topic', 46), { font = F and F.small })
  local rows = catalog_rows()
  if catalog.cat then
    draw_rows(gg, rows, catalog.top, function(f) return (Lib.has_feed(f.url, add_target().file) and '[x] ' or '[ ] ') .. (f.title or f.url) end)
  else
    draw_rows(gg, rows, catalog.top, function(cat) return (cat.name or '?') .. '  (' .. #(cat.feeds or {}) .. ')' end)
  end
  draw_status(gg)
end

local function draw_confirm(gg)
  local F = ctx.fonts
  gg:text(16, 120, 'Remove this feed?', { font = F and F.large })
  gg:text(16, 170, short(removing and removing.name or '', 44), { font = F and F.medium })
  gg:text(16, 206, 'Its articles go too.', { font = F and F.small })
  gg:rect(16, 260, (W - 48) // 2, 58); gg:text(40, 276, 'Remove', { font = F and F.medium })
  gg:rect(32 + (W - 48) // 2, 260, (W - 48) // 2, 58); gg:text(56 + (W - 48) // 2, 276, 'Cancel', { font = F and F.medium })
end

local function draw_needworker(gg)
  local F = ctx.fonts
  bar(gg, { 'Back' })
  gg:text(16, TOP + 10, 'Full text', { font = F and F.large })
  local y = TOP + 56
  for _, l in ipairs({ 'Many feeds carry only a summary. The whole', 'article comes through a small server of your', 'own (free, about 10 minutes). Scan to set it', 'up, then enter it in Settings:' }) do
    gg:text(16, y, l, { font = F and F.small }); y = y + 22
  end
  draw_qr(gg, GUIDE, (W - 220) // 2, y + 16, 220)
  y = y + 16 + 220 + 24
  gg:rect(16, y, W - 32, 58); gg:text(36, y + 16, 'Enter the Worker in Settings', { font = F and F.medium })
  draw_status(gg)
end

local function draw_impl(gg)
  gg:clear(0)
  if screen == 'menu' then draw_menu(gg)
  elseif screen == 'list' then draw_list(gg)
  elseif on_names() then draw_feeds(gg)
  elseif screen == 'article' then draw_article(gg)
  elseif screen == 'settings' then draw_settings(gg)
  elseif screen == 'add' then draw_add(gg)
  elseif screen == 'catalog' then draw_catalog(gg)
  elseif screen == 'confirm' then draw_confirm(gg)
  elseif screen == 'needworker' then draw_needworker(gg) end
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
  if s[1] == 'cache' then
    if #copies() == 0 then clear_armed = false; note('nothing saved offline'); return end
    if not clear_armed then clear_armed = true; return end
    cache_clear(); clear_armed = false; note('offline copies deleted')
    return
  end
  clear_armed = false
  if s[1] == 'full' then
    cfg.full = not cfg.full
    save_cfg()
    if cfg.full and cfg.host == '' then screen = 'needworker' end   -- how to get one
    return
  end
  if s[1] == 'images' then cfg.images = not cfg.images; save_cfg(); return end
  if s[1] == 'size' then
    local nxt = 1
    for k, name in ipairs(SIZE_ORDER) do if name == cfg.size then nxt = k % #SIZE_ORDER + 1 end end
    cfg.size = SIZE_ORDER[nxt]
    save_cfg()
    return
  end
  local ok, err = pcall(function()
    ctx.input:text({ title = s[2], text = cfg[s[1]], max_bytes = 256 }, function(c, v)
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

-- Back from a feed's or a tag's articles: to the feeds or tags they were picked from
local function list_back()
  if list['local'] and list.kind == 'feed' then open_local_feeds(true); return end
  if list.kind == 'feed' and #feeds.items > 0 then screen = 'feeds'
  elseif list.kind == 'tag' and #tags.items > 0 then screen = 'tags'
  else screen = 'menu' end
end

local function page_article(delta)
  local p = art.page + delta
  if p >= 1 and p <= art.pages then art.page = p; load_page_images() end
end

local function page_feeds(delta)
  local feeds = names()
  local t = feeds.top + delta * LIST_N
  if t >= 1 and t <= #feeds.items then feeds.top = t end
end

local function tap(x, y)
  if screen == 'menu' then
    for i, m in ipairs(menu_items()) do
      local y0 = 100 + (i - 1) * 70
      if x >= 16 and x < W - 16 and y >= y0 and y < y0 + 58 then
        if m[2] == 'src' then
          if m[3].kind == 'cf' then where, acct, coll = 'cf', m[3].id, nil
          else where, acct, coll = 'local', nil, Lib.collection(m[3].file); open_local_feeds() end
        elseif m[2] == 'sources' then where, acct, coll = nil, nil, nil
        elseif m[2] == 'settings' then screen = 'settings'
        elseif m[2] == 'add' then open_add()
        elseif m[2] == 'feeds' then fetch_feeds()
        elseif m[2] == 'tags' then fetch_tags()
        else open_list(m[2], nil, m[1]); fetch_list() end
        return
      end
    end
  elseif screen == 'settings' then
    if y < 46 then screen = 'menu'; clear_armed = false; load_accounts(); reload_colls(); return end
    for i = 1, #SETTINGS do
      local y0 = TOP + 20 + (i - 1) * 96 + 24
      if y >= y0 and y < y0 + 48 then edit_setting(i); return end
    end
  elseif screen == 'list' then
    if y < 46 then
      local b = bar_hit(x, 4)
      if b == 1 then list_back() elseif b == 2 then page_list(-1) elseif b == 3 then page_list(1)
      elseif b == 4 then net_unstick(); if list['local'] then refresh_local(true) else fetch_list() end end
      return
    end
    local r = math.floor((y - (TOP + 26)) / 58) + 1
    local i = list.top + r - 1
    if y >= TOP + 26 and r >= 1 and r <= LIST_N and i <= #list.items then open_article(list.items[i]) end
  elseif on_names() then
    local is_tags = screen == 'tags'
    if y < 46 then
      local b = bar_hit(x, 4)
      local is_local = feeds['local'] and not is_tags
      if b == 1 then if is_local then local_feeds_back() else screen = 'menu' end
      elseif b == 2 then page_feeds(-1) elseif b == 3 then page_feeds(1)
      elseif b == 4 and not is_local then net_unstick(); if is_tags then fetch_tags() else fetch_feeds() end end
      return
    end
    local i = math.floor((y - (TOP + 26)) / 58) + names().top
    local it = names().items[i]
    if it and y >= TOP + 26 then
      if it.kind == 'add' then open_add(); return end
      if it.kind == 'folder' then feeds.path[#feeds.path + 1] = it.folder; feeds.top = 1; fill_local_feeds(); return end
      if it['local'] then open_local_list('feed', it.id, (it.name:gsub('  %(!%)$', ''))); return end
      if is_tags then open_list('tag', tostring(it.name), tostring(it.name)) else open_list('feed', tostring(it.id), it.name) end
      fetch_list()
    end
  elseif screen == 'article' then
    if y < 46 then
      local b = bar_hit(x, 4)
      if b == 1 then article_back() elseif b == 2 then page_article(-1) elseif b == 3 then page_article(1) end
      return
    end
    if x < W / 3 then page_article(-1) else page_article(1) end
  elseif screen == 'add' then
    if y < 46 then add_back(); return end
    for i, r in ipairs(ADD_ROWS) do
      local y0 = TOP + 60 + (i - 1) * 70
      if y >= y0 and y < y0 + 58 then
        if r[2] == 'list' then open_catalog() else add_by_address() end
        return
      end
    end
  elseif screen == 'catalog' then
    local rows = catalog_rows()
    if y < 46 then
      local b = bar_hit(x, 3)
      if b == 1 then
        if catalog.cat then catalog.cat, catalog.top = nil, 1 else screen = 'add' end
      elseif b == 2 then catalog.top = math.max(1, catalog.top - LIST_N)
      elseif b == 3 and catalog.top + LIST_N <= #rows then catalog.top = catalog.top + LIST_N end
      return
    end
    local i = math.floor((y - (TOP + 26)) / 58) + catalog.top
    local r = rows[i]
    if r and y >= TOP + 26 then
      if catalog.cat then catalog_toggle(r) else catalog.cat, catalog.top = r, 1 end
    end
  elseif screen == 'confirm' then
    if y >= 260 and y < 318 then
      if x < W // 2 and removing then
        local c = cur_coll()
        if c then Lib.remove_feed(c, removing.id) end
        reload_colls()
        note('removed: ' .. short(removing.name, 34))
      end
      removing = nil
      open_local_feeds(true)
    end
  elseif screen == 'needworker' then
    if y < 46 then screen = 'settings'; return end
    if y > TOP + 56 + 88 + 16 + 220 + 24 then screen = 'settings'; edit_setting(1) end
  end
end

------------------------------------------------------------------ long-press preview

local function row_item(y)
  local r = math.floor((y - (TOP + 26)) / 58) + 1
  local i = list.top + r - 1
  if y >= TOP + 26 and r >= 1 and r <= LIST_N and i <= #list.items then return list.items[i] end
  return nil
end

-- full title, feed and date, and the feed's summary in a box over the list, with Prev / Open /
-- Close / Next. The box always has the same size, from near the top to 64 px above the bottom
-- (room to tap outside it); the list's bar and header are hidden meanwhile. A longer summary is
-- cut with an ellipsis.
local PREVIEW_Y, PREVIEW_BOTTOM = 16, H - 64   -- fixed box: the list's bar and header are hidden

local function open_preview(item)
  measure_cache = {}
  local x, y, w = 16, PREVIEW_Y, W - 32
  local inner = w - 32
  local lines = {}
  local S = st()
  wrap_para(lines, item.title or '', S.title, inner, 0)
  local meta = ((item.feed or '') ~= '' and (item.feed .. '  ') or '') .. (item.date or '') .. (item.read and '' or '  · unread') .. (item.starred and '  · starred' or '')
  if meta ~= '' then wrap_para(lines, meta, S.meta, inner, 0) end
  local tt = tag_text(item)
  if tt ~= '' then wrap_para(lines, 'Tags: ' .. tt, S.meta, inner, 0) end
  lines[#lines + 1] = { s = '', f = 'small', h = 10, x = 0 }
  local ex = item.excerpt or ''
  if ex ~= '' then wrap_para(lines, ex, S.body, inner, 0) else wrap_para(lines, '(no summary in the feed)', 'small', inner, 0) end
  local btn_h, pad = 44, 16
  -- one size for every article: as tall as the screen allows, with room below it to tap outside
  local h = PREVIEW_BOTTOM - y
  -- feeds on the reader have no row above (opening an article marks it read; no starred list)
  local max_content = h - pad - pad - btn_h - pad - (item['local'] and 0 or (btn_h + pad))
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
  local bw = math.floor((w - 5 * pad) / 4)
  local by = y + h - pad - btn_h
  local function btn(n, label) return { x = x + pad + (n - 1) * (bw + pad), y = by, w = bw, h = btn_h, label = label } end
  -- a row above: Star, Mark unread / read and Tags, in three wider buttons
  local bw3 = math.floor((w - 4 * pad) / 3)
  local function btn3(n, label) return { x = x + pad + (n - 1) * (bw3 + pad), y = by - pad - btn_h, w = bw3, h = btn_h, label = label, small = true } end
  preview = {
    item = item, lines = kept, box = { x = x, y = y, w = w, h = h },
    prev = btn(1, 'Prev'), open = btn(2, 'Open'), close = btn(3, 'Close'), next = btn(4, 'Next'),
    star = (not item['local']) and btn3(1, item.starred and 'Unstar' or 'Star') or nil,
    read = (not item['local']) and btn3(2, item.read and 'Mark unread' or 'Mark read') or nil,
    tags = (not item['local']) and btn3(3, 'Tags') or nil,
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

-- Star, read / unread and tags change the article in CommaFeed; the preview shows the result
local function after_change(item, ok, done_note, err)
  if ok then note(done_note) else note(short(err, 44)) end
  if preview and preview.item == item then open_preview(item) end
end

local function toggle_star(item)
  local on = not item.starred
  local feed = tostring(item.feed_id or '')
  request('/api/star/' .. urlenc(item.id) .. '?on=' .. (on and '1' or '0') .. (feed:match('^%d+$') and ('&feed=' .. feed) or ''), function(data, err)
    if data then item.starred = on end
    after_change(item, data, on and 'starred' or 'star removed', err)
  end, on and 'starring' or 'removing the star')
end

local function toggle_read(item)
  local read = not item.read
  request('/api/mark/' .. urlenc(item.id) .. '?read=' .. (read and '1' or '0'), function(data, err)
    if data then item.read = read end
    after_change(item, data, read and 'marked read' or 'marked unread', err)
  end, read and 'marking read' or 'marking unread')
end

-- the firmware keyboard edits the tags as one line, comma-separated; the line replaces them
local function edit_tags(item)
  -- saving replaces every tag, so only edit tags the list really brought (an older Worker or an
  -- offline copy of the list has no tag_line)
  if type(item.tag_line) ~= 'string' then note('Reload the list (and update the Worker) first'); return end
  local ok, e = pcall(function()
    ctx.input:text({ title = 'Tags, separated by commas', text = tag_text(item), max_bytes = 256 }, function(c, v)
      if type(v) ~= 'string' then refresh(); return end
      request('/api/tag/' .. urlenc(item.id) .. '?tags=' .. urlenc(v), function(data, err)
        if data then item.tag_line = type(data.tag_line) == 'string' and data.tag_line or v end
        if err and tostring(err):find('HTTP 501', 1, true) then err = 'Worker: tags need the CommaFeed password' end
        after_change(item, data, 'tags saved', err)
      end, 'saving tags')
    end)
  end)
  if not ok then note('edit ! ' .. short(e, 30)) end
end

local function preview_tap(x, y)
  if preview.star and inside(preview.star, x, y) then toggle_star(preview.item)
  elseif preview.read and inside(preview.read, x, y) then toggle_read(preview.item)
  elseif preview.tags and inside(preview.tags, x, y) then edit_tags(preview.item)
  elseif inside(preview.prev, x, y) then preview_step(-1)
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
  keep_wifi()   -- still in use: Wi-Fi stays up (at most one call per 30 s)
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    if ev.type == 'pointer' then
      -- a long press (the host reports a "hold" phase and / or a "long" gesture) opens the preview
      if ev.gesture == 'long' or ev.phase == 'hold' then
        if screen == 'list' and not preview then
          local it = row_item(ev.y or 0)
          if it then open_preview(it) end
        elseif screen == 'feeds' and feeds['local'] and (ev.y or 0) >= TOP + 26 and not suppress_up then
          local it = feeds.items[math.floor(((ev.y or 0) - (TOP + 26)) / 58) + feeds.top]
          if it and it['local'] then removing = { id = it.id, name = (it.name:gsub('  %(!%)$', '')) }; screen = 'confirm' end
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
        if screen == 'article' then page_article(1) elseif screen == 'list' then page_list(1) elseif on_names() then page_feeds(1) end
      elseif g == 'swipe_right' or g == 'swipe_down' then
        if screen == 'article' then page_article(-1) elseif screen == 'list' then page_list(-1) elseif on_names() then page_feeds(-1) end
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
        elseif screen == 'settings' then screen = 'menu'; clear_armed = false; load_accounts()
        elseif screen == 'list' then list_back()
        elseif screen == 'catalog' then if catalog.cat then catalog.cat, catalog.top = nil, 1 else screen = 'add' end
        elseif screen == 'confirm' then removing = nil; open_local_feeds(true)
        elseif screen == 'feeds' and feeds['local'] then local_feeds_back()
        elseif screen == 'needworker' then screen = 'settings'
        elseif screen == 'add' then add_back()
        elseif screen ~= 'menu' then screen = 'menu'
        elseif where then where, acct, coll = nil, nil, nil end
      elseif k == 'right' or k == 'down' then
        if screen == 'article' then page_article(1) elseif screen == 'list' then page_list(1) elseif on_names() then page_feeds(1) end
      elseif k == 'left' or k == 'up' then
        if screen == 'article' then page_article(-1) elseif screen == 'list' then page_list(-1) elseif on_names() then page_feeds(-1) end
      end
    end
  end)
  if not ok then ERR = tostring(e) end
  refresh()
  return true
end

function on_load(c)
  load_cfg()
  read_accounts(cache_read('accounts.txt'))   -- the saved list draws the folders at once
  Lib.init({ submit = net_submit, worker = function(path, cb, label) request(path, cb, label) end,
             has_worker = function() return base_url() ~= nil end })
  reload_colls()
  keep_wifi(true)
  -- ask the account list right away: it also brings Wi-Fi up for whatever is opened next
  if cfg.host ~= '' then load_accounts('connecting Wi-Fi...') end
  keep_wifi(true)
end

function on_leave()
  -- release: a very short keep lets Wi-Fi go down soon after the app is left
  pcall(function() ctx.net:keep_wifi(1) end)
  if qr_img and qr_img.img then pcall(function() qr_img.img:release() end) end
end
