-- RSS reader for XTOS Licorice, API 2.9. Talks to a commafeed-opds Worker's JSON API over
-- HTTPS (ctx.net), decodes with ctx.json and keeps a small offline cache in ctx.storage.
--
-- Screens: menu (Unread / Starred / All / Feeds / Settings), list (paged, tap an item), article
-- (word-wrapped text, paged), feeds, settings (host, path token, user:pass, full text).
-- Every ctx.* function is a method on this API: colon calls everywhere.

local W, H, TOP = 480, 800, 56
local LIST_N = 12
local LIST_MAX_ITEMS = 240    -- list rows kept in memory across "Load more"
local TEXT_MAX = 20000

local G, ERR = nil, nil
local screen = 'menu'
local status = ''
local loading = nil           -- text shown while a request is in flight
local cfg = { host = '', token = '', auth = '', full = false }

-- list screen
local list = { kind = 'unread', id = nil, title = '', page = 1, items = {}, has_more = false, cached = false }
-- long-press preview over the list: { item, lines, box = {x, y, w, h}, open = {..}, close = {..} }
local preview = nil
local suppress_up = false     -- the release that ends a long press must not also act as a tap
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
      if k == 'full' then cfg.full = (v == '1') else cfg[k] = v end
    end
  end
end

local function save_cfg()
  pcall(function()
    ctx.storage:write('config.txt', 'host=' .. cfg.host .. '\ntoken=' .. cfg.token .. '\nauth=' .. cfg.auth .. '\nfull=' .. (cfg.full and '1' or '0'))
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

local function request(path, on_done)
  local base = base_url()
  if not base then note('set the host in Settings'); on_done(nil, 'no host'); return end
  local url = base .. path
  if cfg.full then url = url .. (url:find('?', 1, true) and '&' or '?') .. 'full=1' end
  local headers = { ['Accept'] = 'application/json' }
  if cfg.auth ~= '' then
    local ok, b64 = pcall(function() return ctx.base64:encode(cfg.auth) end)
    if ok and b64 then headers['Authorization'] = 'Basic ' .. b64 end
  end
  pcall(function() ctx.net:keep_wifi(120) end)
  loading = 'loading ' .. short(path, 30)
  refresh()
  local ok, err = pcall(function()
    return ctx.net:request({ url = url, method = 'GET', headers = headers, timeout_ms = 40000 }, function(c, resp)
      loading = nil
      if type(resp) ~= 'table' then on_done(nil, 'no response'); refresh(); return end
      local st = tonumber(resp.status) or tonumber(resp.code)
      local body = resp.body
      if resp.error and not body then on_done(nil, tostring(resp.error)); refresh(); return end
      if st and st >= 400 then on_done(nil, 'HTTP ' .. st .. ' ' .. short(body or '', 40)); refresh(); return end
      if type(body) ~= 'string' then on_done(nil, 'empty body'); refresh(); return end
      local okj, data = pcall(function() return ctx.json:decode(body) end)
      if not okj or type(data) ~= 'table' then on_done(nil, 'bad json: ' .. short(body, 40)); refresh(); return end
      if data.error then on_done(nil, tostring(data.error)); refresh(); return end
      on_done(data, nil, body)
      refresh()
    end)
  end)
  if not ok then loading = nil; on_done(nil, short(err, 60)) end
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
  wrap_para(out, data.title or '', 'large', W - 24, 0)
  local meta = ((data.feed or '') ~= '' and (data.feed .. '  ') or '') .. (data.date or '') .. ((data.source or 'feed') ~= 'feed' and ('  [' .. data.source .. ']') or '')
  if meta ~= '' then wrap_para(out, meta, 'small', W - 24, 0) end
  gap(14)
  local text = data.text or ''
  for raw_para in (text .. '\n\n'):gmatch('(.-)\n\n') do
    local para = raw_para:gsub('^\n+', ''):gsub('\n+$', '')  -- Lua 5.5: loop variables are const
    if para ~= '' then
      for line in (para .. '\n'):gmatch('([^\n]*)\n') do
        if line:sub(1, 2) == '# ' then wrap_para(out, line:sub(3), 'large', W - 24, 0)
        elseif line:sub(1, 2) == '> ' then wrap_para(out, line:sub(3), 'medium', W - 48, 24)
        elseif line:sub(1, 4) == '• ' then wrap_para(out, line, 'medium', W - 40, 16)  -- the bullet is 3 UTF-8 bytes
        elseif line ~= '' then wrap_para(out, line, 'medium', W - 24, 0) end
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
-- After the last item comes a "Load more" row while the Worker says there is more; tapping it
-- (or Next at the end) fetches the following page and appends it.

local function list_cache_name(page)
  return 'l_' .. list.kind .. '_' .. (list.id or '0') .. '_' .. page .. '.txt'
end

-- rows on the list screen: the items, then the Load more row when there is more
local function list_rows() return #list.items + (list.has_more and 1 or 0) end
local function is_more_row(i) return list.has_more and i == #list.items + 1 end

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

local function fetch_page(page, append)
  local path = '/api/list?kind=' .. list.kind .. '&page=' .. page .. '&n=' .. LIST_N
  if list.id then path = path .. '&id=' .. list.id end
  request(path, function(data, err, raw)
    if data then
      apply_page(page, data, append)
      list.title = data.title or list.title
      list.cached = false
      note('')
      if raw then cache_write(list_cache_name(page), raw) end
    else
      local raw = cache_read(list_cache_name(page))
      local okj, data2 = pcall(function() return ctx.json:decode(raw) end)
      if raw and okj and type(data2) == 'table' then
        apply_page(page, data2, append)
        list.cached = true
        note('offline: ' .. short(err, 30))
      else
        note(short(err, 44))
      end
    end
  end)
end

local function fetch_list() fetch_page(1, false) end            -- first page, or Reload
local function load_more()
  if list.has_more and not loading then fetch_page(list.page + 1, true) end
end

local function open_article(item)
  art.id, art.title, art.feed, art.date = tostring(item.id), item.title or '', item.feed or '', item.date or ''
  art.lines, art.starts, art.page, art.pages, art.cached = {}, { 1 }, 1, 1, false
  screen = 'article'
  local cached = cache_read('a' .. art.id .. '.txt')
  if cached then
    local okj, data = pcall(function() return ctx.json:decode(cached) end)
    if okj and type(data) == 'table' then layout_article(data); art.cached = true; note('cached'); return end
  end
  request('/api/article/' .. art.id .. '?max=' .. TEXT_MAX .. '&mark=1', function(data, err, raw)
    if data then
      layout_article(data); note('')
      if raw then cache_write('a' .. art.id .. '.txt', raw) end
      item.read = true
    else
      note(short(err, 44))
    end
  end)
end

local function fetch_feeds()
  screen = 'feeds'
  feeds.items, feeds.top = {}, 1
  request('/api/feeds', function(data, err, raw)
    if data then feeds.items = data.items or {}; note(''); if raw then cache_write('feeds.txt', raw) end
    else
      local raw2 = cache_read('feeds.txt')
      local okj, d2 = pcall(function() return ctx.json:decode(raw2) end)
      if raw2 and okj and type(d2) == 'table' then feeds.items = d2.items or {}; note('offline: ' .. short(err, 30)) else note(short(err, 44)) end
    end
  end)
end

------------------------------------------------------------------ drawing

local MENU = { { 'Unread', 'unread' }, { 'Starred', 'starred' }, { 'All', 'all' }, { 'Feeds', 'feeds' }, { 'Settings', 'settings' } }
local SETTINGS = { { 'host', 'Host (e.g. rss.example.workers.dev)' }, { 'token', 'Path token (after /k/), or empty' }, { 'auth', 'user:password for Basic auth, or empty' }, { 'full', 'Full text' } }

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

local function draw_status(gg)
  local F = ctx.fonts
  local s = loading or status
  if s ~= '' then gg:text(8, H - 26, short(s, 52), { font = F and F.small }) end
  if ERR then gg:text(8, H - 48, short('ERR ' .. ERR, 52), { font = F and F.small }) end
end

local function draw_menu(gg)
  local F = ctx.fonts
  gg:text(16, 20, 'RSS', { font = F and F.large })
  gg:text(16, 54, (cfg.host ~= '' and cfg.host or 'no host set: open Settings'), { font = F and F.small })
  for i, m in ipairs(MENU) do
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
  for _, btn in ipairs({ preview.open, preview.close }) do
    gg:rect(btn.x, btn.y, btn.w, btn.h)
    local f = F and F.medium
    local okm, tw = pcall(function() return f:measure(btn.label) end)
    tw = (okm and type(tw) == 'number') and tw or #btn.label * 12
    gg:text(btn.x + math.floor((btn.w - tw) / 2), btn.y + 10, btn.label, { font = f })
  end
end

local function draw_list(gg)
  local F = ctx.fonts
  bar(gg, { 'Back', 'Prev', 'Next', 'Reload' })
  local last = math.min(#list.items, list.top + LIST_N - 1)
  local range = #list.items > 0 and ('  ' .. list.top .. '-' .. last .. ' / ' .. #list.items .. (list.has_more and '+' or '')) or ''
  gg:text(8, TOP + 2, short(list.title .. range .. (list.cached and '  (offline)' or ''), 44), { font = F and F.small })
  if preview then draw_preview(gg); draw_status(gg); return end
  local y = TOP + 26
  if #list.items == 0 and not loading then gg:text(16, y + 20, 'nothing here', { font = F and F.medium }) end
  for i = list.top, math.min(list_rows(), list.top + LIST_N - 1) do
    if is_more_row(i) then
      local label = loading and 'Loading…' or 'Load more'
      local f = F and F.medium
      local okm, tw = pcall(function() return f:measure(label) end)
      tw = (okm and type(tw) == 'number') and tw or #label * 12
      gg:rect(16, y - 4, W - 32, 50)
      gg:text(math.floor((W - tw) / 2), y + 10, label, { font = f })
      break
    end
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
  if #feeds.items == 0 and not loading then gg:text(16, y + 20, 'no feeds', { font = F and F.medium }) end
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
    if ln.s ~= '' then gg:text(12 + ln.x, y, ln.s, { font = F and F[ln.f] }) end
    y = y + ln.h
  end
  if #art.lines == 0 and not loading then gg:text(16, TOP + 30, short(art.title, 42), { font = F and F.medium }) end
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
    if s[1] == 'auth' and v ~= '' then v = v:gsub(':.*$', ':****') end
    gg:text(28, y + 36, short(v ~= '' and v or '(empty)', 40), { font = F and F.medium })
  end
  gg:text(16, TOP + 20 + 4 * 96, 'tap a field to edit; the host is your Worker', { font = F and F.small })
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
  local ok, err = pcall(function()
    ctx.input:text({ title = s[2], value = cfg[s[1]] }, function(c, v)
      if type(v) == 'string' then cfg[s[1]] = v:gsub('^%s+', ''):gsub('%s+$', ''); save_cfg() end
      refresh()
    end)
  end)
  if not ok then note('edit ! ' .. short(err, 30)) end
end

-- Prev / Next scroll the rows already loaded. When the next screen would hold nothing but the
-- Load more row, or the Load more row is already on screen, Next loads the following page.
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
  if p >= 1 and p <= art.pages then art.page = p end
end

local function page_feeds(delta)
  local t = feeds.top + delta * LIST_N
  if t >= 1 and t <= #feeds.items then feeds.top = t end
end

local function tap(x, y)
  if screen == 'menu' then
    for i, m in ipairs(MENU) do
      local y0 = 100 + (i - 1) * 70
      if x >= 16 and x < W - 16 and y >= y0 and y < y0 + 58 then
        if m[2] == 'settings' then screen = 'settings'
        elseif m[2] == 'feeds' then fetch_feeds()
        else open_list(m[2], nil, m[1]); fetch_list() end
        return
      end
    end
  elseif screen == 'settings' then
    if y < 46 then screen = 'menu'; return end
    for i = 1, #SETTINGS do
      local y0 = TOP + 20 + (i - 1) * 96 + 24
      if y >= y0 and y < y0 + 48 then edit_setting(i); return end
    end
  elseif screen == 'list' then
    if y < 46 then
      local b = bar_hit(x, 4)
      if b == 1 then screen = 'menu' elseif b == 2 then page_list(-1) elseif b == 3 then page_list(1) elseif b == 4 then fetch_list() end
      return
    end
    local r = math.floor((y - (TOP + 26)) / 58) + 1
    local i = list.top + r - 1
    if y >= TOP + 26 and r >= 1 and r <= LIST_N and i <= list_rows() then
      if is_more_row(i) then load_more() else open_article(list.items[i]) end
    end
  elseif screen == 'feeds' then
    if y < 46 then
      local b = bar_hit(x, 4)
      if b == 1 then screen = 'menu' elseif b == 2 then page_feeds(-1) elseif b == 3 then page_feeds(1) elseif b == 4 then fetch_feeds() end
      return
    end
    local i = math.floor((y - (TOP + 26)) / 58) + feeds.top
    local it = feeds.items[i]
    if it and y >= TOP + 26 then open_list('feed', tostring(it.id), it.name); fetch_list() end
  elseif screen == 'article' then
    if y < 46 then
      local b = bar_hit(x, 4)
      if b == 1 then screen = 'list' elseif b == 2 then page_article(-1) elseif b == 3 then page_article(1) end
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
  return nil   -- includes the Load more row
end

-- full title, feed and date, and the feed's summary in a box over the list, with Open / Close.
-- The box never reaches the bottom of the screen, so there is always room to tap outside it.
local function open_preview(item)
  measure_cache = {}
  local x, y, w = 16, TOP + 26, W - 32
  local inner = w - 32
  local lines = {}
  wrap_para(lines, item.title or '', 'large', inner, 0)
  local meta = ((item.feed or '') ~= '' and (item.feed .. '  ') or '') .. (item.date or '') .. (item.read and '' or '  · unread')
  if meta ~= '' then wrap_para(lines, meta, 'small', inner, 0) end
  lines[#lines + 1] = { s = '', f = 'small', h = 10, x = 0 }
  local ex = item.excerpt or ''
  if ex ~= '' then wrap_para(lines, ex, 'medium', inner, 0) else wrap_para(lines, '(no summary in the feed)', 'small', inner, 0) end
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
  local bw = math.floor((w - 3 * pad) / 2)
  local by = y + h - pad - btn_h
  preview = {
    item = item, lines = kept, box = { x = x, y = y, w = w, h = h },
    open = { x = x + pad, y = by, w = bw, h = btn_h, label = 'Open' },
    close = { x = x + 2 * pad + bw, y = by, w = bw, h = btn_h, label = 'Close' },
  }
end

local function inside(r, x, y) return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h end

local function preview_tap(x, y)
  if inside(preview.open, x, y) then
    local it = preview.item
    preview = nil
    open_article(it)
  elseif inside(preview.close, x, y) or not inside(preview.box, x, y) then
    preview = nil
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
      if preview then preview_tap(ev.x or 0, ev.y or 0); return end
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
        if k == 'back' then preview = nil end
        return
      end
      if k == 'back' then
        if screen == 'article' then screen = 'list' elseif screen ~= 'menu' then screen = 'menu' end
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

function on_load(c)
  load_cfg()
  if cfg.host == '' then screen = 'settings' end
  pcall(function() ctx.net:keep_wifi(180) end)
end

function on_leave() end
