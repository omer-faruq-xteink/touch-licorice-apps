-- Instapaper for XTOS Licorice, API 2.9. Talks to the Instapaper API v2 directly over HTTPS
-- (ctx.net) with a personal access token, turns the article HTML into styled text on the device
-- and keeps an offline cache in ctx.storage. Built from the RSS app: same list, preview and
-- article screens, plus reading progress (resumed and sent back), Archive and Star.
--
-- Screens: menu (Unread / Starred / Archive / Folders / Settings), list (paged, long-press for a
-- preview), article (paged, ends with the source QR code, Archive and Star), folders, settings.
-- Every ctx.* function is a method on this API: colon calls everywhere.

local W, H, TOP = 480, 800, 56
local QR_PX = 200             -- the source QR code at the end of an article, at most this wide
local LIST_N = 12
local LIST_MAX_ITEMS = 240    -- list rows kept in memory as pages are appended
local TEXT_MAX = 40000         -- article text kept (characters), cut at a word

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
local function multi() return #accounts > 1 end
local read_accounts, load_accounts, note_accounts   -- defined in the accounts section
-- The account list is asked (/api, a tiny answer) as soon as the app starts: that request also
-- brings Wi-Fi up (~7 s with Wi-Fi off in the settings), which the first list needs anyway, so a
-- list opened meanwhile waits only for the rest. Lists and feed answers carry the account list
-- too and keep it current; an older Worker without that is asked /api once more after Settings.
-- No timer: timeouts are checked on draw and input.
local accounts_fresh = false
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
      else cfg[k] = (v:gsub('%s+$', '')) end   -- a config.txt written on Windows ends lines in CR
    end
  end
end

local function save_cfg()
  pcall(function() ctx.storage:write('config.txt', 'token=' .. cfg.token .. '\nsize=' .. cfg.size) end)
end

local function base_url()
  local host = cfg.host:gsub('^https?://', ''):gsub('/+$', '')
  if host == '' then return nil end
  local u = 'https://' .. host
  if cfg.token ~= '' then u = u .. '/k/' .. cfg.token end
  return u
end

------------------------------------------------------------------ network

local API = 'https://www.instapaper.com/api/2'

local function request_target(path)
  if cfg.token == '' then return nil end
  return API .. path, { ['Accept'] = 'application/json', ['Authorization'] = 'Bearer ' .. cfg.token }
end

-- Instapaper errors come as {"error": {"code": .., "message": ".."}}
local function api_error(st, body)
  local okj, d = pcall(function() return ctx.json:decode(body) end)
  local e = okj and type(d) == 'table' and d.error
  local msg = type(e) == 'table' and e.message or (type(e) == 'string' and e or nil)
  if st == 401 or st == 403 then return 'token rejected (' .. st .. '): see Settings' end
  return 'HTTP ' .. tostring(st) .. (msg and (' ' .. tostring(msg)) or (' ' .. short(body or '', 40)))
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

-- method defaults to GET; json_body (a JSON string) goes with POST. on_done(data, err, raw)
local function request(path, on_done, label, method, json_body)
  local url, headers = request_target(path)
  if not url then note('set the access token in Settings'); on_done(nil, 'no access token'); return end
  keep_wifi()
  method = method or 'GET'
  local opts = { url = url, method = method, headers = headers }
  if method ~= 'GET' then
    headers['Content-Type'] = 'application/json'
    opts.body = json_body or ''
    headers['Content-Length'] = tostring(#opts.body)
  end
  -- the article text call parses the page on Instapaper's side; lists answer quickly
  local timeout = path:find('/parse', 1, true) and 60000 or 30000
  net_submit(opts, label or ('loading ' .. short(path:gsub('%?.*$', ''), 30)), timeout, function(resp, err)
    if err then on_done(nil, err); return end
    if type(resp) ~= 'table' then on_done(nil, 'no response'); return end
    local st = tonumber(resp.status) or tonumber(resp.code)
    local body = resp.body
    if resp.error and not body then on_done(nil, tostring(resp.error)); return end
    if st and st >= 400 then on_done(nil, api_error(st, body)); return end
    if method ~= 'GET' and (type(body) ~= 'string' or body == '') then on_done({}, nil, ''); return end
    if type(body) ~= 'string' then on_done(nil, 'empty body'); return end
    local okj, data = pcall(function() return ctx.json:decode(body) end)
    if not okj or type(data) ~= 'table' then on_done(nil, 'bad json: ' .. short(body, 40)); return end
    if data.error then on_done(nil, api_error(st, body)); return end
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
  -- Archive and Star under it
  out[#out + 1] = { s = '', f = 'small', h = 76, x = 0, actions = true }
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

------------------------------------------------------------------ Instapaper data

local function str(v) if type(v) == 'string' and v ~= '' then return v end return nil end
local function int_id(v)
  local n = tonumber(v)
  if not n then return nil end
  return string.format('%d', math.floor(n))
end
local function host_of(url)
  local h = tostring(url or ''):match('^%a+://([^/:?#]+)') or ''
  return (h:gsub('^www%.', ''))
end

-- epoch seconds -> "YYYY-MM-DD" (UTC), without os.date
local function date_of(t)
  t = tonumber(t)
  if not t then return '' end
  local z = math.floor(t / 86400) + 719468
  local era = (z >= 0 and z or z - 146096) // 146097
  local doe = z - era * 146097
  local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
  local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
  local mp = (5 * doy + 2) // 153
  local d = doy - (153 * mp + 2) // 5 + 1
  local m = mp < 10 and mp + 3 or mp - 9
  local y = yoe + era * 400 + (m <= 2 and 1 or 0)
  return string.format('%04d-%02d-%02d', y, m, d)
end

-- seconds since 1970 for the progress timestamp, from whatever clock the host offers
local function epoch_now()
  for _, f in ipairs({
    function() return ctx.clock:epoch() end,
    function() return ctx.clock:epoch_sec() end,
    function() local t = ctx.clock:now(); return type(t) == 'table' and (t.epoch or t.epoch_sec or t.unix) or nil end,
    function() return os.time() end,
  }) do
    local ok, v = pcall(f)
    if ok and tonumber(v) and tonumber(v) > 1000000000 then return math.floor(tonumber(v)) end
  end
  return nil
end

local SECTIONS = { unread = 'home', starred = 'liked', archive = 'archive' }

local function list_path(page)
  local p = '/bookmarks?section=' .. (list.id and 'folder' or (SECTIONS[list.kind] or 'home'))
    .. '&limit=' .. LIST_N .. '&offset=' .. ((page - 1) * LIST_N)
  if list.id then p = p .. '&folder_id=' .. list.id end
  return p
end

-- the list row's second line: site, date saved, progress and a star
local function row_meta(it)
  local pct = math.floor((it.progress or 0) * 100 + 0.5)
  return it.day .. (pct > 0 and ('  ' .. pct .. '%') or '') .. (it.liked and '  *' or '')
end

-- GET /bookmarks -> the list shape the screens use; has_more from total (or a full page)
local function to_list(d, page)
  local items = {}
  for _, b in ipairs(type(d) == 'table' and type(d.bookmarks) == 'table' and d.bookmarks or {}) do
    local id = type(b) == 'table' and int_id(b.id)
    if id then
      local pr = type(b.progress) == 'table' and tonumber(b.progress.percentage) or 0
      local it = {
        id = id, url = str(b.url), title = str(b.title) or str(b.url) or '(untitled)',
        host = host_of(b.url), day = date_of(b.time), excerpt = str(b.description) or '',
        progress = pr or 0, liked = (b.liked == true), read = true,
      }
      it.feed, it.date = it.host, row_meta(it)
      items[#items + 1] = it
    end
  end
  local count = #items + ((type(d) == 'table' and type(d.deleted_ids) == 'table') and #d.deleted_ids or 0)
  local total = type(d) == 'table' and tonumber(d.total) or nil
  local offset = ((page or 1) - 1) * LIST_N
  return { items = items, has_more = total and (offset + count < total) or (count >= LIST_N) }
end

-- GET /folders -> { {id, name} ... }
local function to_folders(d)
  local out = {}
  for _, f in ipairs(type(d) == 'table' and type(d.folders) == 'table' and d.folders or {}) do
    local id = type(f) == 'table' and int_id(f.id)
    if id then out[#out + 1] = { id = id, name = str(f.title) or str(f.slug) or id } end
  end
  return out
end

-- HTML -> text with the markers the layout styles: paragraphs split by a blank line, "# "
-- headings, "> " quotes, "• " list items. Source line breaks are spaces, as in a browser.
local DROP = { script = true, style = true, svg = true, iframe = true, noscript = true, template = true, head = true }
local BLOCK_END = { p = true, div = true, li = true, blockquote = true, pre = true, tr = true, figure = true,
  figcaption = true, dd = true, dt = true, section = true, article = true, header = true, footer = true,
  table = true, ul = true, ol = true, h1 = true, h2 = true, h3 = true, h4 = true, h5 = true, h6 = true }
local NAMED = { amp = '&', lt = '<', gt = '>', quot = '"', apos = "'", nbsp = ' ', ensp = ' ', emsp = ' ',
  thinsp = ' ', mdash = '\226\128\148', ndash = '\226\128\147', hellip = '\226\128\166',
  lsquo = '\226\128\152', rsquo = '\226\128\153', ldquo = '\226\128\156', rdquo = '\226\128\157',
  laquo = '\194\171', raquo = '\194\187', copy = '\194\169', reg = '\194\174', trade = '\226\132\162',
  middot = '\194\183', bull = '\226\128\162', euro = '\226\130\172', pound = '\194\163', deg = '\194\176',
  times = '\195\151', shy = '', zwj = '', zwnj = '' }

local function decode_entities(t)
  return (t:gsub('&(#?[%w]+);', function(b)
    if b:sub(1, 1) == '#' then
      local hex = b:sub(2, 2) == 'x' or b:sub(2, 2) == 'X'
      local code = hex and tonumber(b:sub(3), 16) or tonumber(b:sub(2))
      if not code or code <= 0 or code > 0x10FFFF or (code >= 0xD800 and code <= 0xDFFF) then return '' end
      if code < 0x20 and code ~= 9 and code ~= 10 and code ~= 13 then return '' end
      if code == 0xA0 then return ' ' end
      local ok, ch = pcall(utf8.char, code)
      return ok and ch or ''
    end
    return NAMED[b] or NAMED[b:lower()]
  end))
end

local function html_to_text(html, max)
  local src = tostring(html or ''):gsub('<!%-%-.-%-%->', ' ')
  local out, i, n, skip = {}, 1, #src, nil
  while i <= n do
    local a = src:find('<', i, true)
    if not a then
      if not skip then out[#out + 1] = (src:sub(i):gsub('[\r\n\t]', ' ')) end
      break
    end
    if not skip and a > i then out[#out + 1] = (src:sub(i, a - 1):gsub('[\r\n\t]', ' ')) end
    local b = src:find('>', a, true)
    if not b then break end
    local tag = src:sub(a + 1, b - 1)
    local close, name = tag:match('^(/?)%s*([%a][%w]*)')
    name = name and name:lower()
    if skip then
      if close == '/' and name == skip then skip = nil end
    elseif name then
      if close == '' and DROP[name] and not tag:match('/%s*$') then skip = name
      elseif name == 'br' then out[#out + 1] = '\n'
      elseif close == '' and name:match('^h[1-6]$') then out[#out + 1] = '\n\n# '
      elseif close == '' and name == 'blockquote' then out[#out + 1] = '\n\n> '
      elseif close == '' and name == 'hr' then out[#out + 1] = '\n\n* * *\n\n'
      elseif close == '' and name == 'li' then out[#out + 1] = '\n\226\128\162 '
      elseif close == '' and (name == 'p' or name == 'div') then out[#out + 1] = '\n\n'
      elseif close == '/' and BLOCK_END[name] then out[#out + 1] = '\n\n' end
    end
    i = b + 1
  end
  local t = decode_entities(table.concat(out))
  t = t:gsub('\194\160', ' '):gsub('[ \t\f\v]+', ' '):gsub(' *\n *', '\n')
  -- markers left without text (an empty heading or list item) go
  for _ = 1, 2 do t = t:gsub('\n# *\n', '\n'):gsub('\n> *\n', '\n'):gsub('\n\226\128\162 *\n', '\n') end
  t = t:gsub('\n\n\n+', '\n\n'):gsub('^%s+', ''):gsub('%s+$', '')
  max = max or TEXT_MAX
  if #t > max then
    local cut = t:sub(1, max)
    local sp = cut:match('^.*() ')
    if sp and sp > max * 0.8 then cut = cut:sub(1, sp - 1) end
    -- never end inside a UTF-8 character
    cut = cut:gsub('[\192-\255][\128-\191]*$', '')
    t = cut .. '\226\128\166'
  end
  return t
end

-- GET /bookmarks/<id>/parse -> the article shape the layout uses
local function to_article(d, item)
  local content = type(d) == 'table' and type(d.content) == 'table' and d.content or {}
  local meta = type(d) == 'table' and type(d.metadata) == 'table' and d.metadata or {}
  local author = type(meta.author) == 'table' and str(meta.author.name) or nil
  local url = (item and item.url) or str(meta.url) or ''
  local host = (item and item.host) or host_of(url)
  return {
    title = (item and item.title) or str(meta.title) or '',
    feed = host .. (author and ('  ' .. author) or ''),
    date = (item and item.day) or '',
    url = url,
    text = html_to_text(content.body or '', TEXT_MAX),
  }
end

-- the converted article as a small text file: header lines, then the text
local function art_encode(a)
  local function one(v) return (tostring(v or ''):gsub('\n', ' ')) end
  return 'IPA1\n' .. one(a.title) .. '\n' .. one(a.feed) .. '\n' .. one(a.date) .. '\n' .. one(a.url) .. '\n' .. (a.text or '')
end
local function art_decode(raw)
  if type(raw) ~= 'string' or raw:sub(1, 5) ~= 'IPA1\n' then return nil end
  local title, feed, date, url, text = raw:match('^IPA1\n([^\n]*)\n([^\n]*)\n([^\n]*)\n([^\n]*)\n(.*)$')
  if not title then return nil end
  return { title = title, feed = feed, date = date, url = url, text = text }
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
  local path = list_path(page)
  if not append then list.err = nil end
  request(path, function(data, err, raw)
    local ok = false
    if not data and not retried then          -- a hiccup (Wi-Fi waking up, a slow server): once more
      fetch_page(page, append, after, true)
      return
    end
    if data then
      apply_page(page, to_list(data, page), append)
      list.cached = false
      note('')
      if raw then cache_write(list_cache_name(page), raw) end
      ok = true
    else
      local raw = cache_read(list_cache_name(page))
      local okj, data2 = pcall(function() return ctx.json:decode(raw) end)
      if raw and okj and type(data2) == 'table' then
        apply_page(page, to_list(data2, page), append)
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

-- Reading progress: an article opens on the page its Instapaper progress points at, and leaving
-- it sends the page reached back (POST /bookmarks/<id>), so other readers continue there too.
local function resume_page()
  local p = art.item and tonumber(art.item.progress) or 0
  if p > 0 and art.pages > 1 then art.page = math.max(1, math.min(art.pages, math.floor(p * art.pages) + 1)) end
  art.start_page = art.page
end

local function send_progress()
  local it, id = art.item, art.id
  -- nothing to send for an article that never loaded, or when the page did not change
  if not it or not id or not art.start_page or art.page == art.start_page then return end
  local p = art.page >= art.pages and 1 or (art.page - 1) / art.pages
  it.progress = p
  it.date = row_meta(it)
  local ts = epoch_now()
  local body = string.format('{"progress":{"percentage":%.4f%s}}', p, ts and (',"timestamp":' .. ts) or '')
  request('/bookmarks/' .. id, function(data, err) if err then note('progress not saved: ' .. short(err, 26)) end end,
    'saving progress', 'POST', body)
end

local function open_article(item)
  art.id, art.title, art.feed, art.date = tostring(item.id), item.title or '', item.feed or '', item.date or ''
  art.lines, art.starts, art.page, art.pages, art.cached = {}, { 1 }, 1, 1, false
  art.from_preview = nil
  art.item, art.start_page = item, nil
  screen = 'article'
  release_images()
  local cname = 'a' .. art.id .. '.txt'
  local cached = art_decode(cache_read(cname))
  if cached then layout_article(cached); resume_page(); art.cached = true; note('cached'); return end
  local id = art.id
  request('/bookmarks/' .. id .. '/parse', function(data, err)
    if art.id ~= id then return end               -- another article by now
    if data then
      local a = to_article(data, item)
      layout_article(a); resume_page(); note('')
      cache_write(cname, art_encode(a))
    else
      note(short(err, 44))
    end
  end, 'loading article')
end

-- Archive (moves the bookmark out of Unread) and Star, from the preview or the article's end
local function remove_from_list(id)
  for i, x in ipairs(list.items) do
    if tostring(x.id) == id then table.remove(list.items, i); break end
  end
  if list.top > #list.items and list.top > 1 then list.top = math.max(1, list.top - LIST_N) end
end

local function bookmark_action(act, item)
  if not item then return end
  local id = tostring(item.id)
  if act == 'archive' then
    request('/bookmarks/' .. id .. '/move', function(data, err)
      if err then note('archive: ' .. short(err, 36)); return end
      note('archived: ' .. short(item.title or '', 30))
      if list.kind ~= 'archive' then remove_from_list(id) end
    end, 'archiving', 'POST', '{"section":"archive"}')
  elseif act == 'star' then
    if item.liked then return end
    request('/bookmarks/' .. id .. '/like', function(data, err)
      if err then note('star: ' .. short(err, 36)); return end
      item.liked = true
      item.date = row_meta(item)
      note('starred')
    end, 'starring', 'POST', '')
  end
end

local function fetch_feeds(retried)
  screen = 'feeds'
  feeds.items, feeds.top, feeds.err = {}, 1, nil
  request('/folders', function(data, err, raw)
    if not data and not retried then fetch_feeds(true); return end   -- once more before giving up
    if data then feeds.items = to_folders(data); note(''); if raw then cache_write('folders.txt', raw) end
    else
      local raw2 = cache_read('folders.txt')
      local okj, d2 = pcall(function() return ctx.json:decode(raw2) end)
      if raw2 and okj and type(d2) == 'table' then feeds.items = to_folders(d2); note('offline: ' .. short(err, 30))
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
-- one account (the token's); at start the folder list is asked right away: a small request that
-- also brings Wi-Fi up for whatever is opened next, and keeps the Folders screen ready offline
load_accounts = function(label)
  if cfg.token == '' then return end
  accounts_fresh = true
  request('/folders', function(data, err, raw) if data and raw then cache_write('folders.txt', raw) end end, label)
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
  if true then return end                      -- Instapaper: one account per token
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

local MENU = { { 'Unread', 'unread' }, { 'Starred', 'starred' }, { 'Archive', 'archive' }, { 'Folders', 'feeds' }, { 'Settings', 'settings' } }
local SETTINGS = { { 'token', 'Access token (instapaper.com/developers)' }, { 'size', 'Text size (articles and previews)' } }

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
  gg:text(16, 20, 'Instapaper', { font = F and F.large })
  gg:text(16, 54, (cfg.token ~= '' and 'signed in with an access token' or 'no access token: open Settings'), { font = F and F.small })
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
    gg:text(16, y + 26, short((it.feed or '') .. '  ' .. (it.date or ''), 50), { font = F and F.small })
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
  if #feeds.items == 0 and not busy() then draw_empty(gg, y, feeds.err, 'no folders') end
  draw_status(gg)
end

local function draw_actions(gg, y)
  local F = ctx.fonts
  local it = art.item
  local labels = {}
  if not (list.kind == 'archive' and not list.id) then labels[#labels + 1] = { 'Archive', 'archive' } end
  labels[#labels + 1] = { (it and it.liked) and 'Starred' or 'Star', 'star' }
  local bw = math.floor((W - 24 - 16) / 2)
  art.btns = {}
  for k, l in ipairs(labels) do
    local b = { x = 12 + (k - 1) * (bw + 16), y = y + 14, w = bw, h = 52, act = l[2] }
    gg:rect(b.x, b.y, b.w, b.h)
    gg:text(b.x + 20, b.y + 14, l[1], { font = F and F.medium })
    art.btns[#art.btns + 1] = b
  end
end

local function draw_article(gg)
  local F = ctx.fonts
  art.btns = nil
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
    elseif ln.actions then draw_actions(gg, y)
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
    if s[1] == 'token' and #v > 10 then v = v:sub(1, 4) .. '...' .. v:sub(-4) end
    gg:text(28, y + 36, short(v ~= '' and v or '(empty)', 40), { font = F and F.medium })
  end
  local y = TOP + 20 + #SETTINGS * 96
  for _, l in ipairs({ 'Create an application at instapaper.com/developers', 'and generate an access token for it. Or put a line',
                       'token=... in XTApps/instapaper/files/config.txt', 'on the SD card over USB.' }) do
    gg:text(16, y, l, { font = F and F.small }); y = y + 24
  end
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
    for _, b in ipairs(art.btns or {}) do
      if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then
        local it = art.item
        if b.act == 'archive' then
          bookmark_action('archive', it)
          art.page = art.start_page or art.page   -- finished: no progress to send
          article_back()
        else
          bookmark_action('star', it)
        end
        return
      end
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

-- full title, site and date, and the saved description in a box over the list, with Prev /
-- Open / Archive / Next. A tap outside the box or Back closes it; the box never reaches the
-- bottom of the screen, so there is always room to tap outside it.
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
  if ex ~= '' then wrap_para(lines, ex, S.body, inner, 0) else wrap_para(lines, '(no description saved)', 'small', inner, 0) end
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
    prev = btn(1, 'Prev'), open = btn(2, 'Open'), close = btn(3, 'Archive'), next = btn(4, 'Next'),
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
  send_progress()
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
  elseif inside(preview.close, x, y) then
    -- Archive: the bookmark leaves Unread; the preview moves on to the next one
    local it = preview.item
    local i = index_of(it)
    local nxt = i and (list.items[i + 1] or list.items[i - 1])
    bookmark_action('archive', it)               -- leaves the list once Instapaper confirms
    if nxt and nxt ~= it then open_preview(nxt) else preview = nil end
  elseif not inside(preview.box, x, y) then
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

function on_load(c)
  load_cfg()
  read_accounts(cache_read('accounts.txt'))   -- the saved list draws the folders at once
  keep_wifi(true)
  -- ask the account list right away: it also brings Wi-Fi up for whatever is opened next
  if cfg.token == '' then screen = 'settings' else load_accounts('connecting Wi-Fi...') end
  keep_wifi(true)
end

function on_leave()
  -- release: a very short keep lets Wi-Fi go down soon after the app is left
  pcall(function() ctx.net:keep_wifi(1) end)
end
