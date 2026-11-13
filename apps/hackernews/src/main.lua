-- Hacker News for XTOS Licorice, API 2.18 (uses tools/gamekit and src/hn.lua). Needs Wi-Fi.
--
-- Top, New, Best, Ask and Show in HN's own order, and search (Algolia). A story opens with its
-- text (Ask HN), or the linked article as text through the user's rss-opds Worker (/api/read, the
-- same full-text services RSS uses), else its address as a QR code. Comments open level by level:
-- a page shows the replies to one story or comment in HN's order, loaded one by one while you
-- read; tap a comment's "replies" to go down, Back to come up. Settings: the Worker, text size,
-- pictures, and the screen (API 2.18, which the manifest asks for): portrait (480 x 800) or landscape (800 x 480);
-- the layout follows ctx.screen's size (sync_screen), and an open page is laid out again in place.
--
-- One request at a time (a queue); leaving a screen drops what it still waited for.

local N = require('hn')
local A = require('ai')         -- the optional AI questions (tools/gamekit/ai.lua)
local W, H = kit.W, kit.H      -- the screen now (sync_screen); the rest follow it
local BTN_Y, BTN_H = 704, 64
local LIST_TOP, ROW_H, ROWS = 64, 78, 8
local DOC_TOP, DOC_BOTTOM = 14, BTN_Y - 30
local QR_PX = 200
local MAX_ROWS = 240
local UA = 'XteinkLicoriceHN/1.0 (https://github.com/omer-faruq/touch-licorice-apps)'
local TABS = { { 'For you', 'foryou', 'You' }, { 'Top', 'top' }, { 'New', 'new' }, { 'Best', 'best' }, { 'Ask', 'ask' }, { 'Show', 'show' },
               { 'Find', 'find' } }
local SIZES = { small = 'medium', medium = 'large', large = 'small' }      -- the next one

local cfg = { host = '', token = '', auth = '', size = 'medium', images = 'on', screen = 'portrait', aisend = 'both',
              lockevery = '60' }
for k, v in pairs(A.DEFAULTS) do cfg[k] = v end
local screen = 'list'           -- list | story | thread | settings | aimenu | chat | aiset | aiprov | aibtns
local L = nil                   -- the list: { tab, query, rows, top, ids, next, page, more, stale }
local S = nil                   -- the open story: { row, item, article, article_err, lines, pages, page }
local levels = {}               -- comment levels, deepest last: { parent, kids, got, next, page, lines, pages }
local thread_from = 'list'
local chat = { msgs = {}, lines = {}, pages = { 1 }, page = 1 }   -- the AI conversation of the open story
local status, ERR = nil, nil
-- For you (1.3.0): the topics and mutes of foryou.txt (N.foryou_parse)
local fy = N.foryou_parse(nil)
local function load_foryou() fy = N.foryou_parse(kit.read('foryou.txt')) end
local function save_foryou() kit.write('foryou.txt', N.foryou_text(fy)) end
-- add an entry as foryou.txt would hold it ("rust", "-crypto", "-site:x"): read again, so it is
-- trimmed, lower-cased and kept once
local fy_changed = false        -- the For you list is fetched again on the way back to it
local function add_foryou(line)
  fy = N.foryou_parse(N.foryou_text(fy) .. '\n' .. line)
  save_foryou()
  fy_changed = true
end
-- drop one line of foryou.txt ("rust", "-crypto", "-site:x")
local function drop_foryou(line)
  local keep = {}
  for l in (N.foryou_text(fy) .. '\n'):gmatch('([^\n]*)\n') do if l ~= line and l ~= '' then keep[#keep + 1] = l end end
  fy = N.foryou_parse(table.concat(keep, '\n'))
  save_foryou()
  fy_changed = true
end

-- a character limit set for the 480 px portrait width, scaled to the screen's width now
local function wide(n) return math.max(8, n * W // 480) end
-- s cut to fit maxw pixels in font fname, whole UTF-8 characters, with "~" where it was cut
local function fit(s, fname, maxw)
  s = tostring(s)
  local f = kit.font(fname)
  if kit.width(f, s) <= maxw then return s end
  while s ~= '' and kit.width(f, s .. '~') > maxw do s = kit.drop_last(s) end
  return s .. '~'
end

local function now_sec()
  local ok, t = pcall(function() return ctx.clock:now() end)
  return (ok and type(t) == 'table' and tonumber(t.epoch_sec)) and math.floor(tonumber(t.epoch_sec)) or 0
end

------------------------------------------------------------------ settings

local function load_cfg()
  local t = kit.kv(kit.read('settings.txt'))
  for k in pairs(cfg) do if t[k] then cfg[k] = t[k] end end
  if not SIZES[cfg.size] then cfg.size = 'medium' end
  if cfg.images ~= 'off' then cfg.images = 'on' end
  if cfg.screen ~= 'landscape' then cfg.screen = 'portrait' end
  A.normalize(cfg)                 -- aion: a boolean
  if cfg.aisend ~= 'article' and cfg.aisend ~= 'comments' and cfg.aisend ~= 'link' then cfg.aisend = 'both' end
  if not ({ ['30'] = true, ['60'] = true, ['180'] = true, ['360'] = true })[cfg.lockevery] then cfg.lockevery = '60' end
end
local function save_cfg()
  local s = 'host=' .. cfg.host .. '\ntoken=' .. cfg.token .. '\nauth=' .. cfg.auth .. '\nsize=' .. cfg.size .. '\nimages=' .. cfg.images .. '\nscreen=' .. cfg.screen
  -- the AI lines only once something of it is set
  s = s .. A.cfg_lines(cfg)
  if cfg.aisend ~= 'both' then s = s .. '\naisend=' .. cfg.aisend end
  s = s .. '\nlockevery=' .. cfg.lockevery           -- the sleep screen's refresh, minutes (lockscreen.lua)
  kit.write('settings.txt', s)
end
local function worker_url(path)
  local host = cfg.host:gsub('^https?://', ''):gsub('/+$', '')
  if host == '' then return nil end
  return 'https://' .. host .. (cfg.token ~= '' and ('/k/' .. cfg.token) or '') .. path
end

------------------------------------------------------------------ network: a queue, one at a time

local queue, inflight = {}, nil

local function keep_wifi() pcall(function() ctx.net:keep_wifi(5 * 60 * 1000) end) end

local function finish(job, resp)
  if job.whole then job.on_done(resp); return end            -- the AI: status, body and error as they came
  if type(resp) ~= 'table' or type(resp.body) ~= 'string' then
    job.on_done(nil, type(resp) == 'table' and resp.error and tostring(resp.error) or 'no answer'); return
  end
  local code = tonumber(resp.status) or tonumber(resp.code)
  if job.raw then
    if code and code >= 400 then job.on_done(nil, 'HTTP ' .. code, code) else job.on_done(resp.body) end
    return
  end
  local okj, data = pcall(function() return ctx.json:decode(resp.body) end)
  if not okj then data = nil end
  if code and code >= 400 then
    job.on_done(nil, (type(data) == 'table' and data.error) and tostring(data.error) or ('HTTP ' .. code), code); return
  end
  if data == nil then job.on_done(nil, 'not JSON'); return end
  job.on_done(data, nil, code, resp.body)
end

local pump
pump = function()
  if inflight and kit.now_ms() and inflight.since and kit.now_ms() - inflight.since > inflight.timeout + 10000 then
    inflight = nil                                         -- never answered
  end
  if inflight or #queue == 0 then return end
  local job = table.remove(queue, 1)
  inflight, job.since = job, kit.now_ms()
  keep_wifi()
  local ok, err = pcall(function()
    ctx.net:request({ url = job.url, method = job.method or 'GET', headers = job.headers, body = job.body, timeout_ms = job.timeout }, function(c, resp)
      if inflight ~= job then return end
      inflight = nil
      if not job.dropped then
        local okh, e = pcall(finish, job, resp)
        if not okh then status = 'Error: ' .. tostring(e) end
      end
      pump()
      kit.refresh()
    end)
  end)
  if not ok then
    inflight = nil
    pcall(job.on_done, nil, 'could not ask: ' .. tostring(err))
    pump()
  end
end

local function get(url, label, on_done, headers, timeout, raw)
  queue[#queue + 1] = { url = url, label = label, on_done = on_done, timeout = timeout or 30000, raw = raw,
                        headers = headers or { ['User-Agent'] = UA, ['Accept'] = 'application/json' } }
  local job = queue[#queue]
  pump()
  return job
end
-- a POST (the AI): opts from A.request; on_done(resp) gets the answer as it came
local function post(opts, label, on_done)
  queue[#queue + 1] = { url = opts.url, method = 'POST', body = opts.body, headers = opts.headers, label = label,
                        on_done = on_done, timeout = 60000, whole = true }
  local job = queue[#queue]
  pump()
  return job
end
local function drop_all()
  for _k, j in ipairs(queue) do j.dropped = true end
  queue = {}
  if inflight then inflight.dropped = true end
end
local function busy_label() return inflight and not inflight.dropped and inflight.label or nil end

------------------------------------------------------------------ lists

local function save_list()
  if L.tab == 'find' then return end
  local out = {}
  for k = 1, math.min(#L.rows, N.PER_PAGE) do out[k] = N.row_text(L.rows[k]) end
  kit.write('list_' .. L.tab .. '.txt', table.concat(out, '\n'))
end

local function add_rows(rows)
  if L.stale then L.rows, L.stale, L.top = {}, false, 1 end
  for _k, r in ipairs(rows) do if #L.rows < MAX_ROWS then L.rows[#L.rows + 1] = r end end
  if #L.rows >= MAX_ROWS then L.more = false end
end

local load_more
local function fetch_rows(list)
  local ids = {}
  for k = list.next, math.min(#list.ids, list.next + N.PER_PAGE - 1) do ids[#ids + 1] = list.ids[k] end
  if #ids == 0 then list.more = false; return end
  get(N.stories_url(ids), 'Loading stories...', function(d, err)
    if L ~= list then return end
    if not d then status = 'Stories failed: ' .. err; return end
    local by_id = {}
    for _k, h in ipairs(d.hits or {}) do by_id[tostring(h.objectID)] = N.story(h) end
    local rows = {}
    for _k, id in ipairs(ids) do if by_id[id] then rows[#rows + 1] = by_id[id] end end
    local first = list.next == 1
    list.next = list.next + #ids
    list.more = list.next <= #list.ids
    add_rows(rows)
    if first then save_list() end
    if list.want and list.want <= #L.rows then list.top, list.want = list.want, nil end
  end)
end

load_more = function()
  local list = L
  if list.loading_ids or not list.more then return end
  if list.tab == 'foryou' then
    -- one search for all the topics (N.foryou_url); the muted words and sites left out here
    if #fy.topics == 0 then list.more = false; return end
    get(N.foryou_url(fy.topics, now_sec(), list.page), 'Loading stories for you...', function(d, err)
      if L ~= list then return end
      if not d then status = 'For you failed: ' .. err; return end
      local rows, hits = {}, d.hits or {}
      for _k, h in ipairs(hits) do
        local r = N.story(h)
        if not N.muted(r, fy) then rows[#rows + 1] = r end
      end
      list.page = list.page + 1
      list.more = list.page < (tonumber(d.nbPages) or 0) and #hits > 0
      add_rows(rows)
      if list.page == 1 then
        save_list()
        kit.write('foryou_at.txt', tostring(now_sec()))   -- when: the sleep screen shows it, and fetches after
      end
      if list.want and list.want <= #L.rows then list.top, list.want = list.want, nil end
    end)
  elseif list.tab == 'find' then
    get(N.search_url(list.query, list.page), 'Searching...', function(d, err)
      if L ~= list then return end
      if not d then status = 'Search failed: ' .. err; return end
      local rows = {}
      for _k, h in ipairs(d.hits or {}) do rows[#rows + 1] = N.story(h) end
      list.page = list.page + 1
      list.more = list.page < (tonumber(d.nbPages) or 0) and #rows > 0
      add_rows(rows)
      if #L.rows == 0 then status = 'Nothing found.' end
      if list.want and list.want <= #L.rows then list.top, list.want = list.want, nil end
    end)
  elseif not list.ids then
    list.loading_ids = true
    get(N.ids_url(list.tab), 'Loading ' .. list.tab .. ' stories...', function(d, err, code, body)
      list.loading_ids = false
      if L ~= list then return end
      if not d then status = 'List failed: ' .. err; return end
      list.ids, list.next = N.ids(body), 1
      fetch_rows(list)
    end)
  else
    fetch_rows(list)
  end
end

local function open_tab(tab, query)
  drop_all()
  L = { tab = tab, query = query, rows = {}, top = 1, page = 0, more = true }
  if tab ~= 'find' then
    for line in (kit.read('list_' .. tab .. '.txt') or ''):gmatch('[^\n]+') do
      local r = N.row_parse(line)
      if r then L.rows[#L.rows + 1] = r end
    end
    L.stale = #L.rows > 0                                    -- shown until the new list comes
  end
  screen, status = 'list', nil
  load_more()
end

local function list_page(delta)
  if delta > 0 then
    if L.top + ROWS <= #L.rows then L.top = L.top + ROWS
    elseif L.more then L.want = L.top + ROWS; load_more() end
  else
    L.top = math.max(1, L.top - ROWS)
  end
end

------------------------------------------------------------------ documents (story, comments)

local function body_font() return cfg.size end

-- text with paragraphs (and the Worker's "# " headings, "> " quotes) as document lines; quotes
-- are indented (an article's lose the marker, a comment's keep the ">" its writer typed)
local function add_text(out, text, cidx, article, images)
  local f = body_font()
  for para in (tostring(text) .. '\n'):gmatch('([^\n]*)\n') do
    local imgn = tonumber(para:match('^%[%[img:(%d+)%]%]$') or '')
    if imgn then
      -- an article picture (Settings: Images): a box of its size, drawn once loaded
      local im = images and images[imgn]
      local room = DOC_BOTTOM - DOC_TOP - 12            -- a picture fits on one page (landscape: smaller)
      if im and im.h > room then
        local w = math.max(16, im.w * room // im.h)
        im = { n = im.n, w = w, h = room, src = (im.src:gsub('([?&]w=)%d+', '%1' .. w):gsub('([?&]h=)%d+', '%1' .. room)) }
      end
      if im then out[#out + 1] = { s = '', f = 'small', x = 0, h = im.h + 12, img = im } end
    elseif para:match('%S') then
      local font, x, s = f, 16, para
      if para:sub(1, 2) == '# ' then font, s = 'large', para:sub(3)
      elseif para:sub(1, 1) == '>' then x = 40; if article then s = para:gsub('^>%s*', '') end end
      for _k, l in ipairs(N.wrap(s, font, W - 16 - x)) do
        out[#out + 1] = { s = l, f = font, x = x, h = kit.line_h(font) + 2, cidx = cidx }
      end
      out[#out + 1] = { s = '', f = 'small', x = 0, h = 8, cidx = cidx }
    end
  end
end
local function add_lines(out, s, font, x, cidx, extra)
  for _k, l in ipairs(N.wrap(s, font, W - 16 - (x or 16))) do
    local ln = { s = l, f = font, x = x or 16, h = kit.line_h(font) + 4, cidx = cidx }
    if extra then for k, v in pairs(extra) do ln[k] = v end end
    out[#out + 1] = ln
  end
end

local function paginate(lines)
  local pages, y = { 1 }, 0
  for k, ln in ipairs(lines) do
    if y + ln.h > DOC_BOTTOM - DOC_TOP and y > 0 then pages[#pages + 1] = k; y = 0 end
    y = y + ln.h
  end
  return pages
end

------------------------------------------------------------------ article pictures
-- Greyscale JPEGs of exactly the size the Worker announced, from the resizer address it gave
-- (another host: no Worker credentials go with them). Only the page on screen has its pictures
-- fetched and decoded, one at a time; the others are released.

local pics = {}                 -- src -> { img } | { failed = true } | { job } while loading

local function page_range(doc)
  return doc.pages[doc.page] or 1, (doc.pages[doc.page + 1] or (#doc.lines + 1)) - 1
end

local function release_pics(keep)
  for src, p in pairs(pics) do
    if not (keep and keep[src]) then
      if p.img then pcall(function() p.img:release() end) end
      pics[src] = nil
    end
  end
end

local load_pics
load_pics = function()
  if screen ~= 'story' or not S or not S.lines then release_pics(); return end
  local first, last = page_range(S)
  local on_page, todo = {}, nil
  for k = first, last do
    local im = S.lines[k].img
    if im then
      on_page[im.src] = true
      local p = pics[im.src]
      if p and p.job and p.job.dropped then pics[im.src], p = nil, nil end
      if not p and not todo then todo = im end
    end
  end
  release_pics(on_page)
  if not todo then return end
  -- image_decode is an optional capability: without it the pictures stay boxes, nothing is fetched
  if not (ctx.capabilities and ctx.capabilities.image_decode) then
    for src in pairs(on_page) do pics[src] = pics[src] or { failed = true } end
    return
  end
  for _src, p in pairs(pics) do if p.job then return end end   -- one at a time
  local story, slot = S, {}
  pics[todo.src] = slot
  slot.job = get(todo.src, 'Loading picture...', function(body)
    if pics[todo.src] ~= slot then return end
    slot.job = nil
    local ok, img = false, nil
    if type(body) == 'string' and body:sub(1, 2) == '\255\216' then
      ok, img = pcall(function() return ctx.image:decode(body) end)
    end
    if ok and img then slot.img = img else slot.failed = true end
    if S == story then load_pics() end
  end, { ['Accept'] = 'image/jpeg', ['User-Agent'] = UA }, 30000, true)
end

local function draw_pic(gg, im, y)
  local x = math.max(0, (W - im.w) // 2)
  local p = pics[im.src]
  if p and p.img and pcall(function() gg:image(p.img, x, y + 6) end) then return end
  if p and (p.img or p.failed) then gg:text(16, y + 6, '[picture]', { font = kit.font('small') }); return end
  gg:rect(x, y + 6, im.w, im.h)
  gg:text(x + 10, y + 16, 'picture...', { font = kit.font('small') })
end

local function meta(r)
  local parts = { r.points .. ' points', 'by ' .. r.by }
  local ago = N.ago(r.time, now_sec())
  if ago ~= '' then parts[#parts + 1] = ago end
  return table.concat(parts, ' · ')
end

local function build_story()
  pcall(function() ctx.budget:extend() end)   -- a long article takes more than a callback's 1000 ms
  local r, out = S.row, {}
  add_lines(out, r.title, 'large', 16)
  add_lines(out, meta(r), 'small', 16)
  if r.url then add_lines(out, N.domain(r.url) or r.url, 'small', 16) end
  out[#out + 1] = { s = '', f = 'small', x = 0, h = 62, likes = true }    -- More like this / Less like this
  out[#out + 1] = { s = '', f = 'small', x = 0, h = 14, rule = true }
  if S.item and S.item.text then add_text(out, N.text(S.item.text)) end
  if r.url then
    if S.article then add_text(out, S.article, nil, true, S.images)
    elseif S.article_err then add_lines(out, 'No article text: ' .. S.article_err .. '.', 'small', 16)
    elseif S.reading then add_lines(out, 'Getting the article...', 'small', 16)
    elseif not worker_url('') then
      add_lines(out, 'To read articles here, enter your rss-opds Worker in Settings. The address:', 'small', 16)
    end
    out[#out + 1] = { s = '', f = 'small', x = 0, h = 30 + QR_PX + 8, qr = r.url }
    add_lines(out, r.url, 'small', 16)
  end
  S.lines = out
  S.pages = paginate(out)
  S.page = math.min(S.page or 1, #S.pages)
  load_pics()
end

local function open_story(row)
  drop_all()
  screen, status = 'story', nil
  S = { row = row, page = 1 }
  build_story()
  local story = S
  get(N.item_url(row.id), 'Opening the story...', function(d, err, code, body)
    if S ~= story then return end
    if not d then status = 'Story failed: ' .. err; return end
    d.kids = N.kids(body)
    story.item = d
    if d.score then row.points = tonumber(d.score) or row.points end
    if d.descendants then row.comments = tonumber(d.descendants) or row.comments end
    build_story()
  end)
  local url = row.url and worker_url('/api/read?max=20000' .. (cfg.images == 'on' and '&images=1' or '') .. '&url=' .. N.enc(row.url))
  if url then
    story.reading = true
    local headers = { ['Accept'] = 'application/json' }
    if cfg.auth ~= '' then
      local ok, b64 = pcall(function() return ctx.base64:encode(cfg.auth) end)
      if ok and b64 then headers['Authorization'] = 'Basic ' .. b64 end
    end
    get(url, 'Getting the article...', function(d, err, code)
      if S ~= story then return end
      story.reading = false
      if d and type(d.text) == 'string' and d.text:match('%S') then
        story.article, story.images = d.text, {}
        for _k, im in ipairs(type(d.images) == 'table' and d.images or {}) do
          local n, w, h = tonumber(im.n), tonumber(im.w), tonumber(im.h)
          if n and w and h and type(im.src) == 'string' then story.images[n] = { n = n, w = w, h = h, src = im.src } end
        end
      else
        story.article_err = code == 501 and 'the Worker has no full-text service'
          or (code == 404 and err == 'not found') and 'the Worker is older than /api/read; update it'
          or tostring(err or 'empty')
      end
      build_story()
    end, headers, 60000)
    build_story()
  end
end

-- comments: one level = the replies to one story or comment
local function level() return levels[#levels] end

local function build_thread(lv)
  pcall(function() ctx.budget:extend() end)   -- a long article takes more than a callback's 1000 ms
  local out, now = {}, now_sec()
  local p = lv.parent
  if p.type == 'story' or #levels == 1 then
    add_lines(out, tostring(p.title or S and S.row.title or ''), 'medium', 16)
    add_lines(out, (tonumber(p.descendants) or 0) .. ' comments', 'small', 16)
  else
    add_lines(out, 'Replies to ' .. tostring(p.by or '?'), 'medium', 16)
    local first = N.wrap(N.text(p.text), 'small', W - 48)
    for k = 1, math.min(3, #first) do
      out[#out + 1] = { s = (k == 3 and #first > 3) and kit.short(first[k], 40) or first[k], f = 'small', x = 32, h = 22 }
    end
  end
  out[#out + 1] = { s = '', f = 'small', x = 0, h = 14, rule = true }
  for k, cm in ipairs(lv.got) do
    -- each comment is wrapped once (per text size), not again whenever another one arrives
    if cm.block_size ~= cfg.size .. W then
      local b = {}
      local ago = N.ago(cm.time, now)
      add_lines(b, cm.by .. (ago ~= '' and (' · ' .. ago) or ''), 'small', 16, k, { head = true })
      add_text(b, cm.text, k)
      if #cm.kids > 0 then
        add_lines(b, #cm.kids .. (#cm.kids == 1 and ' reply' or ' replies') .. ' >', 'medium', 260, k, { link = true })
      end
      b[#b + 1] = { s = '', f = 'small', x = 0, h = 14, rule = true }
      cm.block, cm.block_size = b, cfg.size .. W
    end
    for _j, ln in ipairs(cm.block) do out[#out + 1] = ln end
  end
  if lv.next <= #lv.kids then add_lines(out, 'Loading comments...', 'small', 16)
  elseif #lv.got == 0 then add_lines(out, 'No comments yet.', 'small', 16)
  else add_lines(out, '- end of ' .. (#levels == 1 and 'comments' or 'replies') .. ' -', 'small', 16) end
  lv.lines = out
  lv.pages = paginate(out)
  lv.page = math.min(lv.page, #lv.pages)
end

-- load the next comment while fewer than two pages are ready after the one shown
local function thread_pump()
  local lv = level()
  if not lv or lv.loading or lv.next > #lv.kids or #lv.pages - lv.page >= 2 then return end
  lv.loading = true
  get(N.item_url(lv.kids[lv.next]), 'Loading comments...', function(d, err, code, body)
    lv.loading = false
    if level() ~= lv then return end
    lv.next = lv.next + 1                                  -- a comment that failed is left out
    if not d then status = 'A comment failed: ' .. err end
    if type(d) == 'table' and not d.deleted and not d.dead and d.text then
      lv.got[#lv.got + 1] = { by = tostring(d.by or '?'), time = tonumber(d.time) or 0,
                              text = N.text(d.text), kids = N.kids(body) }
    end
    build_thread(lv)
    thread_pump()
  end)
end

local function push_level(parent, kids)
  local lv = { parent = parent, kids = kids or {}, got = {}, next = 1, page = 1 }
  levels[#levels + 1] = lv
  build_thread(lv)
  thread_pump()
end

local function open_thread(row)
  drop_all()
  thread_from = screen == 'story' and 'story' or 'list'
  if not S or S.row ~= row then S = { row = row, page = 1 }; build_story() end
  screen, status, levels = 'thread', nil, {}
  if S.item and S.item.kids then push_level(S.item, S.item.kids); return end
  local story = S
  levels[1] = { parent = { type = 'story', title = row.title, descendants = row.comments }, kids = {}, got = {}, next = 1, page = 1, loading = true }
  build_thread(levels[1])
  get(N.item_url(row.id), 'Loading comments...', function(d, err, code, body)
    if S ~= story or screen ~= 'thread' then return end
    levels = {}
    if not d then status = 'Comments failed: ' .. err; d = { type = 'story', title = row.title } end
    d.kids = N.kids(body)
    story.item = d
    push_level(d, d.kids)
  end)
end

local function doc_page(delta)
  local doc = (screen == 'thread' and level()) or (screen == 'chat' and chat) or (screen == 'story' and S) or nil
  if not doc then return end
  doc.page = math.max(1, math.min(#doc.pages, doc.page + delta))
  if screen == 'thread' then thread_pump() else load_pics() end
end

------------------------------------------------------------------ AI (optional; Settings → AI)
-- Off (or not set up), nothing of it shows. On, a story and its comments get an AI button: the
-- ready questions with what to send (Send: Article + comments, Article, Comments, Link +
-- comments), then the conversation (chat), where Ask types a follow-up and More goes back to the
-- ready questions. One conversation per story, kept while it is the open story. The comments
-- come all at once from Algolia's search (N.comments_url), only when they are to be sent.

local AI = {}
local SEND = { { 'both', 'Article + comments' }, { 'article', 'Article' }, { 'comments', 'Comments' }, { 'link', 'Link + comments' } }
local COMMENTS_MAX, COMMENTS_PER, COMMENTS_ROOM = 600, 200, 52000
local ai_from = 'story'         -- where Back from the AI goes: story | thread

function AI.on() return A.ready(cfg) end
function AI.dec(s) return ctx.json:decode(s) end
function AI.J()
  local extra, err = A.extra(cfg.aiextra, AI.dec)
  if err then return nil, err end
  return { encode = function(v) return ctx.json:encode(v) end, extra = extra, null = ctx.json.null }
end
function AI.send_label()
  for _k, m in ipairs(SEND) do if m[1] == cfg.aisend then return m[2] end end
  return SEND[1][2]
end

function AI.layout(to_last)
  local out, last_at = {}, 1
  for _k, m in ipairs(chat.msgs) do
    if m.role == 'user' then
      last_at = #out + 1                           -- a new answer opens at its question
      add_lines(out, '» ' .. (m.label or m.text), 'small', 32)
      out[#out + 1] = { s = '', f = 'small', x = 0, h = 8 }
    else
      add_text(out, A.plain(m.text))
      out[#out + 1] = { s = '', f = 'small', x = 0, h = 14, rule = true }
    end
  end
  if chat.waiting then add_lines(out, chat.waiting, 'small', 16) end
  chat.lines, chat.pages = out, paginate(out)
  -- a last page holding only an answer's closing rule and gaps is dropped (it showed empty)
  while #chat.pages > 1 do
    local blank = true
    for i = chat.pages[#chat.pages], #out do if out[i].s ~= '' then blank = false; break end end
    if not blank then break end
    for i = #out, chat.pages[#chat.pages], -1 do out[i] = nil end   -- its lines go too
    chat.pages[#chat.pages] = nil
  end
  if to_last then
    chat.page = 1
    for pg, first in ipairs(chat.pages) do if first <= last_at then chat.page = pg end end
  end
  chat.page = math.max(1, math.min(chat.page, #chat.pages))
end

-- a question whose request was dropped (the screen was left meanwhile) can be asked again
function AI.check()
  if chat.waiting and (not chat.job or chat.job.dropped) then
    chat.waiting, chat.job = nil, nil
    if #chat.msgs > 0 and chat.msgs[#chat.msgs].role == 'user' then table.remove(chat.msgs) end
  end
end

function AI.open()
  if not S then return end
  if chat.id ~= S.row.id then chat = { id = S.row.id, msgs = {}, lines = {}, pages = { 1 }, page = 1 } end
  AI.check()
  if screen == 'story' or screen == 'thread' then ai_from = screen end
  A.buttons(true)                                  -- ai_buttons.txt may have changed over USB
  status = nil
  if #chat.msgs > 0 then AI.layout(false); screen = 'chat' else screen = 'aimenu' end
end

-- what goes with the questions, by Send
function AI.content(mode)
  local r = S.row
  local text = S.article or (S.item and S.item.text and N.text(S.item.text)) or ''
  local art = { title = r.title, what = mode == 'article' and 'a Hacker News story' or 'a Hacker News story and its comments' }
  if mode == 'both' or mode == 'article' then art.text, art.url = text, r.url end
  if mode == 'link' then art.url = r.url; if not r.url then art.text = text end end   -- Ask HN: the post is its text
  if mode ~= 'article' and S.ai_comments then art.comments = S.ai_comments.text end
  return art
end

-- all of the story's comments, 200 a request (100 when an answer comes cut), at most 600
function AI.fetch_comments(story, done)
  if story.ai_comments or (tonumber(story.row.comments) or 0) == 0 then done(); return end
  local hits, per = {}, COMMENTS_PER
  local function page(pg)
    chat.job = get(N.comments_url(story.row.id, pg, per), 'Getting comments ' .. #hits .. ' / ' .. story.row.comments .. '...', function(d, err, code, body)
      if S ~= story then return end
      if not d and err == 'not JSON' and per > 50 then per = per // 2; page(pg * 2); return end
      if not d then done(err); return end
      for _k, h in ipairs(N.comment_hits(d, body)) do hits[#hits + 1] = h end
      if pg + 1 < (tonumber(d.nbPages) or 0) and #hits < COMMENTS_MAX and #(d.hits or {}) > 0 then page(pg + 1); return end
      local text, n = N.thread_text(hits, story.row.id, story.item and story.item.kids, COMMENTS_ROOM)
      story.ai_comments = { text = text, n = n }
      done()
    end)
  end
  page(0)
end

-- a question: a ready one (label), or your own; with a web search while the switch is on, where
-- the service has one (DeepSeek's is made first and goes along with the question)
function AI.ask(prompt, label)
  AI.check()
  if chat.waiting then status = 'Still waiting for the answer.'; return end
  local J, jerr = AI.J()
  if not J then status = jerr; return end
  local web = chat.web and A.web_ok(cfg)
  J.web = web and not A.web_first(cfg)
  local story, c, mode = S, chat, cfg.aisend
  c.msgs[#c.msgs + 1] = { role = 'user', text = prompt, label = (label or prompt) .. (web and ' (web search)' or '') }
  screen = 'chat'
  local function fail(why)
    c.waiting, c.job = nil, nil
    if #c.msgs > 0 and c.msgs[#c.msgs].role == 'user' then table.remove(c.msgs) end   -- it can be asked again
    status = 'AI: ' .. kit.short(tostring(why or 'no answer'), 70)
    if c ~= chat then return end
    if #c.msgs == 0 and screen == 'chat' then screen = 'aimenu' end
    AI.layout(false)
  end
  local function send(err)
    if err then fail(err); return end
    if S ~= story or c ~= chat then return end
    local opts, rerr = A.request(cfg, AI.content(mode), c.msgs, J)
    if not opts then fail(rerr); return end
    local name = A.prov(cfg).name
    c.waiting = 'Asking ' .. name .. (J.web and ', searching the web...' or '...')
    AI.layout(true)
    c.job = post(opts, 'Asking ' .. name .. '...', function(resp)
      c.job = nil
      local text, why = A.answer(cfg, resp, AI.dec)
      if not text then fail(why); return end
      c.waiting = nil
      c.msgs[#c.msgs + 1] = { role = 'assistant', text = text }
      status = nil
      if c == chat then AI.layout(true) end
    end)
  end
  -- DeepSeek: the model writes the search query, the app searches, the results go with the question
  local function search(err)
    if err then fail(err); return end
    if not (web and A.web_first(cfg)) then send(); return end
    if S ~= story or c ~= chat then return end
    local art = AI.content(mode)
    local function run(query)
      if S ~= story or c ~= chat then return end
      local opts, serr = A.search_request(cfg, query, J.encode, prompt)
      if not opts then fail(serr); return end
      c.waiting = 'Searching the web...'
      AI.layout(true)
      c.job = post(opts, 'Searching the web...', function(resp)
        c.job = nil
        local found, why = A.search_text(resp, AI.dec)
        if not found then fail(why); return end
        c.msgs[#c.msgs].text = prompt .. '\n\n' .. found
        send()
      end)
    end
    local qopts = A.query_request(cfg, art, c.msgs, J)
    if not qopts then run(A.query_text(cfg, nil, AI.dec, art, prompt)); return end
    c.waiting = 'Choosing what to search...'
    AI.layout(true)
    c.job = post(qopts, 'Choosing what to search...', function(resp)
      c.job = nil
      run(A.query_text(cfg, resp, AI.dec, art, prompt))
    end)
  end
  c.waiting = 'Getting the comments...'
  AI.layout(true)
  if mode ~= 'article' then AI.fetch_comments(story, search) else search() end
end

-- your own question
function AI.ask_own()
  local web = chat.web and A.web_ok(cfg)
  local title = (#chat.msgs > 0 and 'Ask more' or 'Ask about this story') .. (web and ' (with a web search)' or '')
  ctx.input:text({ title = title, text = '', max_bytes = 256 }, function(c, v)
    if type(v) == 'string' and v:match('%S') then
      local ok, e = pcall(AI.ask, (v:gsub('^%s+', ''):gsub('%s+$', '')))
      if not ok then ERR = tostring(e) end
    end
    kit.refresh()
  end)
end

-- the ready questions: Send first, then the questions (the article's unless only comments go,
-- the discussion's when comments go), your own question and Start over
function AI.items()
  local t = { { 'Send: ' .. AI.send_label(), 'send' } }
  local more = cfg.aisend ~= 'article' and A.DISCUSSION or nil
  for _k, it in ipairs(A.items(cfg, #chat.msgs > 0, more, cfg.aisend == 'comments', chat.web)) do t[#t + 1] = it end
  return t
end
-- their cells: Send across, the questions two (landscape three) a row, then your question, the web
-- search switch and Start over in a new row of the same cells
function AI.menu_cells()
  local items, out = AI.items(), {}
  local n = W > H and 3 or 2
  local rh = W > H and 46 or 58
  local y, col, prev = W > H and 52 or 84, 0, nil
  local cw = (W - 32 - (n - 1) * 12) // n
  local web_row = false
  for _k, it in ipairs(items) do if it[2] == 'web' then web_row = W > H end end
  local sw = web_row and (W - 32 - 12) * 3 // 5 or W - 32      -- landscape: Send and the web switch share the top row
  for _k, it in ipairs(items) do
    if it[2] == 'send' then
      out[#out + 1] = { x = 16, y = y, w = sw, h = rh - 10, item = it }
      if not web_row then y = y + rh end
    elseif it[2] == 'web' and web_row then
      out[#out + 1] = { x = 16 + sw + 12, y = y, w = W - 32 - sw - 12, h = rh - 10, item = it }; y = y + rh
    elseif it[2] == 'web' then
      out[#out + 1] = { x = 16, y = y, w = W - 32, h = rh - 10, item = it }; y = y + rh
    else
      local group = it[2] == 'ask' and 'ask' or 'tail'
      if prev and group ~= prev and col > 0 then col, y = 0, y + rh end
      out[#out + 1] = { x = 16 + col * (cw + 12), y = y, w = cw, h = rh - 10, item = it }
      col = col + 1
      if col == n then col, y = 0, y + rh end
      prev = group
    end
  end
  return out
end

-- My buttons (ai_buttons.txt): a tap edits one as "Label | question" (emptied: deleted); the
-- last row adds one
function AI.btn_rect(i)
  local n = W > H and 3 or 1                       -- (cols() is defined further down)
  local cw = (W - 32 - (n - 1) * 16) // n
  return 16 + ((i - 1) % n) * (cw + 16), 70 + ((i - 1) // n) * 70, cw, 60
end
function AI.edit_button(i)
  local list = {}
  for k, b in ipairs(A.buttons()) do list[k] = b end
  local cur = list[i]
  ctx.input:text({ title = cur and 'Label | question (empty: delete)' or 'New button: Label | question',
                   text = cur and (cur.label .. ' | ' .. cur.q) or '', max_bytes = 256 }, function(c, v)
    if type(v) == 'string' then
      local b = A.parse_button(v)
      if cur and not b then table.remove(list, i)
      elseif b and cur then list[i] = b
      elseif b and #list < A.BUTTONS_MAX then list[#list + 1] = b end
      if (b or cur) and not A.save_buttons(list) then status = 'could not write ' .. A.BUTTONS_FILE end
    end
    kit.refresh()
  end)
end

function AI.test()
  local J, jerr = AI.J()
  if not J then status = jerr; return end
  local opts, err = A.request(cfg, A.TEST_ART, A.TEST_MSGS, J)
  if not opts then status = 'AI: ' .. tostring(err); return end
  post(opts, 'Testing ' .. A.prov(cfg).name .. '...', function(resp)
    local text, why = A.answer(cfg, resp, AI.dec)
    status = text and ('Works: "' .. kit.short(text, 30) .. '"') or ('AI: ' .. kit.short(tostring(why or 'no answer'), 70))
  end)
end

-- ai.txt in AppFiles/hackernews/ (USB): taken in, then deleted
function AI.import()
  local ok, s = pcall(function()
    if not (ctx.files and ctx.files:exists('ai.txt')) then return nil end
    return ctx.files:read('ai.txt', 0, 4096)
  end)
  if not (ok and A.take(cfg, s)) then return false end
  save_cfg()
  pcall(function() ctx.files:remove('ai.txt') end)
  status = 'AI settings taken from ai.txt (file deleted)'
  return true
end

function AI.edit(i)
  local k = A.SET[i] and A.SET[i][1]
  if not k then return end
  if k == 'aion' then local m = A.toggle(cfg); save_cfg(); status = m; return end
  if k == 'aiprov' then screen = 'aiprov'; return end
  if k == 'aitest' then AI.test(); return end
  if k == 'aibtn' then A.buttons(true); screen = 'aibtns'; return end
  local title, start = A.field(cfg, k)
  ctx.input:text({ title = title, text = start, max_bytes = 256 }, function(c, v)
    if type(v) == 'string' then
      local stored, why = A.store(cfg, k, v, AI.dec)
      if stored then save_cfg() else status = why end
    end
    kit.refresh()
  end)
end

function AI.choose(id)
  local need = A.choose(cfg, id)
  save_cfg()
  screen = 'aiset'
  if need then for i, s in ipairs(A.SET) do if s[1] == 'aiurl' then AI.edit(i) end end end
end

------------------------------------------------------------------ drawing

local qr = nil                  -- { url, img } | { url, failed = true }
local function draw_qr(gg, url, y)
  if not qr or qr.url ~= url then
    if qr and qr.img then pcall(function() qr.img:release() end) end
    local ok, img = pcall(function() return ctx.qr:encode(url) end)
    qr = (ok and img) and { url = url, img = img } or { url = url, failed = true }
  end
  if qr.img then
    local ok = pcall(function()
      local w = tonumber(qr.img.width) or 0
      local size = w > 0 and w * math.max(1, QR_PX // w) or QR_PX
      gg:image(qr.img, (W - size) // 2, y + 20, { w = size, h = size })
    end)
    if not ok then qr.failed = true end
  end
end

local function draw_doc(gg, doc)
  local y = DOC_TOP
  local last = (doc.pages[doc.page + 1] or (#doc.lines + 1)) - 1
  for k = doc.pages[doc.page] or 1, last do
    local ln = doc.lines[k]
    if ln.rule then gg:line(16, y + ln.h // 2, W - 16, y + ln.h // 2)
    elseif ln.likes then
      local bw = (W - 48) // 2
      kit.button(gg, 16, y + 6, bw, 48, 'More like this', { font = 'small' })
      kit.button(gg, 32 + bw, y + 6, bw, 48, 'Less like this', { font = 'small' })
    elseif ln.qr then draw_qr(gg, ln.qr, y)
    elseif ln.img then draw_pic(gg, ln.img, y)
    elseif ln.s ~= '' then gg:text(ln.x, y, ln.s, { font = kit.font(ln.f) }) end
    y = y + ln.h
  end
  if #doc.pages > 1 then gg:text(W - 90, BTN_Y - 26, doc.page .. ' / ' .. #doc.pages, { font = kit.font('small') }) end
end

local add_rect = nil             -- the For you tab's "Add a topic" button, while it shows
local function draw_list(gg)
  local tw = (W - 8) // #TABS
  for k, t in ipairs(TABS) do
    -- "For you" takes the small font where the medium one does not fit, then its short name "You"
    local label, font = t[1], 'medium'
    if t[3] and kit.width(kit.font(font), label) > tw - 12 then font = 'small' end
    if t[3] and kit.width(kit.font(font), label) > tw - 12 then label, font = t[3], 'medium' end
    kit.button(gg, 4 + (k - 1) * tw, 4, tw - 4, 48, label, { font = font, line_width = L.tab == t[2] and 5 or 1 })
  end
  add_rect = nil
  if L.tab == 'foryou' and #fy.topics == 0 then
    local y = 120
    for _k, l in ipairs(N.wrap('For you: the stories of the last two days on the topics you choose. Add one here, or open a '
        .. 'story and tap More like this.', 'medium', W - 32)) do
      gg:text(16, y, l, { font = kit.font('medium') })
      y = y + 30
    end
    add_rect = { x = 16, y = y + 20, w = W - 32, h = 64 }
    kit.button(gg, add_rect.x, add_rect.y, add_rect.w, add_rect.h, 'Add a topic', { font = 'medium' })
    return
  end
  if L.tab == 'find' and L.query then gg:text(16, LIST_TOP - 4, kit.short('"' .. L.query .. '"', wide(40)), { font = kit.font('small') }) end
  local now = now_sec()
  for k = 0, ROWS - 1 do
    local r = L.rows[L.top + k]
    if not r then break end
    local y = LIST_TOP + k * ROW_H
    local t = N.wrap(r.title, 'medium', W - 32)
    gg:text(16, y + 6, t[1] or '', { font = kit.font('medium') })
    if t[2] then gg:text(16, y + 30, #t > 2 and kit.short(t[2], #t[2] - 2) or t[2], { font = kit.font('medium') }) end
    local m = r.points .. ' pts · ' .. r.comments .. ' comm.'
    if L.tab == 'foryou' then                       -- the topics it was found for
      local tp = N.topics_in(r.title, fy.topics)
      if #tp > 0 then m = table.concat(tp, ', ') .. ' · ' .. m end
    end
    local d = N.domain(r.url)
    if d then m = m .. ' · ' .. d end
    local ago = N.ago(r.time, now)
    if ago ~= '' then m = m .. ' · ' .. ago end
    -- the meta line follows the title (no gap after a one-line title) and a double rule ends the story
    gg:text(16, t[2] and y + 56 or y + 32, fit(m, 'small', W - 32), { font = kit.font('small') })
    gg:line(16, y + ROW_H - 2, W - 16, y + ROW_H - 2)
    gg:line(16, y + ROW_H - 1, W - 16, y + ROW_H - 1)
  end
  if #L.rows == 0 and not busy_label() and not status then
    if L.tab == 'foryou' then
      gg:text(16, 200, 'Nothing for your topics in the last 2 days.', { font = kit.font('medium') })
      gg:text(16, 236, fit('Topics: ' .. table.concat(fy.topics, ', '), 'small', W - 32), { font = kit.font('small') })
    else
      gg:text(16, 200, L.tab == 'find' and 'Tap Find to search.' or 'Nothing here yet: Reload.', { font = kit.font('medium') })
    end
  end
end

-- { key, label, shorter label for landscape's three columns }
local SETTINGS = { { 'host', 'Worker host, e.g. rss-opds.you.workers.dev', 'Worker host' }, { 'token', 'Path token (after /k/), or empty', 'Token (after /k/)' },
                   { 'auth', 'user:password for Basic auth, or empty', 'Login (user:password)' }, { 'size', 'Text size' },
                   { 'images', 'Pictures in articles' } }
-- landscape needs ctx.screen:set_orientation (API 2.18; Studio's preview has none): Settings offers it only then
local function can_rotate()
  local ok, f = pcall(function() return ctx.screen and ctx.screen.set_orientation end)
  return ok and type(f) == 'function'
end
local function apply_orientation()
  if can_rotate() then pcall(function() ctx.screen:set_orientation(cfg.screen) end) end
end
local function settings_list()
  local t = {}
  for k, v in ipairs(SETTINGS) do t[k] = v end
  if can_rotate() then t[#t + 1] = { 'screen', 'Screen' } end
  t[#t + 1] = { 'ai', 'AI' }
  t[#t + 1] = { 'foryou', 'For you' }
  return t
end
-- one column in portrait, three in landscape
local function cols() return W > H and 3 or 1 end
local setting_rect
-- Settings' (and the AI page's) cells: in portrait a short one shares its row with the next short
-- one; in landscape every cell is a third. grid_rows() gives { x, row, w } per cell and the rows used
local HALF = { size = true, images = true, screen = true, ai = true, foryou = true }
local function grid_rows(items, half)
  local out, row, col = {}, 0, 0
  local n = cols() > 1 and 3 or 2
  local cw = (W - 32 - (n - 1) * 16) // n
  for i, s in ipairs(items) do
    if cols() > 1 or half[s[1]] then
      if col == n then row, col = row + 1, 0 end
      out[i] = { 16 + col * (cw + 16), row, cw }
      col = col + 1
    else
      if col > 0 then row, col = row + 1, 0 end
      out[i] = { 16, row, W - 32 }
      row = row + 1
    end
  end
  return out, row + (col > 0 and 1 or 0)
end
local function setting_rows() return grid_rows(settings_list(), HALF) end
setting_rect = function(i)
  local r = setting_rows()[i]
  return r[1], 70 + r[2] * 86, r[3], 86
end
function AI.rect(i)
  local r = grid_rows(A.SET, A.HALF)[i]
  return r[1], 70 + r[2] * 86, r[3], 86
end
-- the Service list: one column (three in landscape)
function AI.prov_rect(i)
  local n = cols()
  local cw = (W - 32 - (n - 1) * 16) // n
  return 16 + ((i - 1) % n) * (cw + 16), 70 + ((i - 1) // n) * 66, cw, 56
end
local function draw_settings(gg)
  gg:text(16, 16, 'Settings', { font = kit.font('large') })
  local list = settings_list()
  for k, s in ipairs(list) do
    local x, y, w = setting_rect(k)
    local v = cfg[s[1]]
    if s[1] == 'token' and v ~= '' then v = string.rep('*', math.min(#v, 12)) end
    if s[1] == 'auth' and v ~= '' then v = (v:match('^[^:]*') or '') .. ':***' end
    if s[1] == 'ai' then v = AI.on() and A.prov(cfg).name or (cfg.aion and 'not set up yet' or 'off') end
    if s[1] == 'foryou' then v = #fy.topics .. (#fy.topics == 1 and ' topic' or ' topics') end
    gg:text(x, y + 8, fit((cols() > 1 and s[3]) or s[2], 'small', w), { font = kit.font('small') })
    gg:text(x, y + 36, v ~= '' and fit(v, 'medium', w) or '(empty)', { font = kit.font('medium') })
    gg:line(x, y + 78, x + w, y + 78)
  end
  if cols() > 1 then return end                    -- landscape: no room for the note
  local _, rows = setting_rows()
  local y = 70 + rows * 86 + 8
  for _k, l in ipairs(N.wrap('Stories open as text, with their pictures if you like, through your rss-opds Worker (the one RSS '
      .. 'uses, with the same host and login; it needs /api/read, so update it once). Without a Worker a story ends with its '
      .. 'address as a QR code. Tap the left third of a page to go back, elsewhere to go on.', 'small', W - 32)) do
    if y + 22 > BTN_Y then break end               -- what does not fit above the buttons is left out
    gg:text(16, y, l, { font = kit.font('small') }); y = y + 22
  end
end

------------------------------------------------------------------ the For you page (Settings)
-- every topic, muted word and muted site, a page at a time; a tap offers Edit / Remove / Cancel;
-- Add a topic, Mute a word, and how often the sleep screen fetches For you again
local FY_TOP, FY_ROW = 232, 52
local fy_page = 1
-- the store's build: its sleep screen cannot fetch (the store's API gives it no network), so it is
-- only on or off there; this build fetches while locked (API 2.26) and asks how often
local LOCK_NET = false
-- store: cut
LOCK_NET = true
-- store: end
local EVERY = { { '0', 'Off' }, { '30', 'Every 30 min' }, { '60', 'Every hour' }, { '180', 'Every 3 hours' }, { '360', 'Every 6 hours' } }
local function fy_per() return math.max(1, (BTN_Y - 12 - FY_TOP) // FY_ROW) end
local function fy_entries()
  local e = {}
  for _k, t in ipairs(fy.topics) do e[#e + 1] = { label = t, line = t, value = t, prefix = '' } end
  for _k, w in ipairs(fy.words) do e[#e + 1] = { label = 'muted: ' .. w, line = '-' .. w, value = w, prefix = '-' } end
  for _k, s in ipairs(fy.sites) do e[#e + 1] = { label = 'muted site: ' .. s, line = '-site:' .. s, value = s, prefix = '-site:' } end
  return e
end
local function fy_pages() return math.max(1, (#fy_entries() + fy_per() - 1) // fy_per()) end
local function lock_is_on()
  local ok, v = pcall(function() return ctx.lockscreen:is_default() end)
  return ok and v == true
end
local function lock_label()
  if not lock_is_on() then return 'Sleep screen: off' end
  if not LOCK_NET then return 'Sleep screen: on' end
  for _k, e in ipairs(EVERY) do if e[1] == cfg.lockevery then return 'Sleep screen: ' .. e[2]:lower() end end
  return 'Sleep screen: on'
end
local function fy_rects()
  local hw = (W - 48) // 2
  return { add = { 16, 70, hw, 64 }, mute = { 32 + hw, 70, hw, 64 }, lock = { 16, 146, W - 32, 64 } }
end
local function draw_fyset(gg)
  gg:text(16, 16, 'For you', { font = kit.font('large') })
  local r = fy_rects()
  kit.button(gg, r.add[1], r.add[2], r.add[3], r.add[4], 'Add a topic', { font = 'medium' })
  kit.button(gg, r.mute[1], r.mute[2], r.mute[3], r.mute[4], 'Mute a word', { font = 'medium' })
  kit.button(gg, r.lock[1], r.lock[2], r.lock[3], r.lock[4], lock_label(), { font = 'medium' })
  local e = fy_entries()
  fy_page = math.min(fy_page, fy_pages())
  if #e == 0 then
    gg:text(16, FY_TOP + 10, 'No topics yet.', { font = kit.font('medium') })
    return
  end
  local first = (fy_page - 1) * fy_per()
  for k = 1, fy_per() do
    local it = e[first + k]
    if not it then break end
    local y = FY_TOP + (k - 1) * FY_ROW
    gg:text(16, y + 12, fit(it.label, 'medium', W - 32), { font = kit.font('medium') })
    gg:line(16, y + FY_ROW - 1, W - 16, y + FY_ROW - 1)
  end
  if fy_pages() > 1 then gg:text(W - 90, BTN_Y - 26, fy_page .. ' / ' .. fy_pages(), { font = kit.font('small') }) end
end

function AI.draw_set(gg)
  gg:text(16, 16, 'AI (optional)', { font = kit.font('large') })
  for k, s in ipairs(A.SET) do
    local x, y, w = AI.rect(k)
    gg:text(x, y + 8, fit(s[2], 'small', w), { font = kit.font('small') })
    gg:text(x, y + 36, fit(A.value(cfg, s[1]), 'medium', w), { font = kit.font('medium') })
    gg:line(x, y + 78, x + w, y + 78)
  end
  if cols() > 1 then return end
  local _, rows = grid_rows(A.SET, A.HALF)
  local y = 70 + rows * 86 + 8
  for _k, l in ipairs(N.wrap('Off: no AI button anywhere. On: one on stories and comments. A long key: put ai.txt in '
      .. ((ctx.files and type(ctx.files.path) == 'string' and ctx.files.path ~= '') and ctx.files.path or 'AppFiles/hackernews')
      .. '/ with lines service=deepseek, key=..., model=...; the app takes it in and deletes the file.', 'small', W - 32)) do
    gg:text(16, y, l, { font = kit.font('small') }); y = y + 22
  end
end

function AI.draw_prov(gg)
  gg:text(16, 16, 'Service', { font = kit.font('large') })
  local cur = A.prov(cfg).id
  for i, P in ipairs(A.PROVIDERS) do
    local x, y, w, h = AI.prov_rect(i)
    kit.button(gg, x, y, w, h, P.label, { font = 'medium', line_width = P.id == cur and 5 or 1 })
  end
end

function AI.draw_btns(gg)
  gg:text(16, 16, 'My buttons', { font = kit.font('large') })
  local list = A.buttons()
  local n = #list + (#list < A.BUTTONS_MAX and 1 or 0)
  for i = 1, n do
    local x, y, w, h = AI.btn_rect(i)
    gg:rect(x, y, w, h)
    local b = list[i]
    if b then
      gg:text(x + 12, y + 6, fit(b.label, 'medium', w - 24), { font = kit.font('medium') })
      gg:text(x + 12, y + 34, fit(b.q, 'small', w - 24), { font = kit.font('small') })
    else
      gg:text(x + 12, y + 18, 'Add a button', { font = kit.font('medium') })
    end
  end
  if cols() > 1 then return end
  local _x, y = AI.btn_rect(n + 1)
  for _k, l in ipairs(N.wrap('They come after the ready questions. Tap one to change it; empty it to delete it. Also in '
      .. ((ctx.files and type(ctx.files.path) == 'string' and ctx.files.path ~= '') and ctx.files.path or 'AppFiles/hackernews')
      .. '/' .. A.BUTTONS_FILE .. ' (USB): one "Label | question" a line.', 'small', W - 32)) do
    gg:text(16, y + 4, l, { font = kit.font('small') }); y = y + 22
  end
end

function AI.draw_menu(gg)
  gg:text(16, 12, 'Ask ' .. A.prov(cfg).name, { font = kit.font('large') })
  if W <= H then gg:text(16, 50, fit(S and S.row.title or '', 'small', W - 32), { font = kit.font('small') }) end
  for _k, c in ipairs(AI.menu_cells()) do
    kit.button(gg, c.x, c.y, c.w, c.h, c.item[1], { font = 'medium',
      line_width = (c.item[2] == 'send' or (c.item[2] == 'web' and chat.web)) and 3 or 1 })
  end
end

local function buttons()
  if screen == 'list' then return { 'Prev', 'Next', 'Reload', 'Settings' } end
  if screen == 'story' then
    if AI.on() then
      -- "AI" is narrow, so Back / Prev / Next keep room for their words (Back was cut at 66 px)
      local b, ai = 76 * W // 480, 50 * W // 480
      return { 'Back', 'Prev', 'Next', 'AI', S.row.comments .. ' comments' }, { b, b, b, ai, W - 56 - 3 * b - ai }
    end
    local b = 84 * W // 480
    return { 'Back', 'Prev', 'Next', S.row.comments .. ' comments' }, { b, b, b, W - 48 - 3 * b }
  end
  if screen == 'thread' then
    local t = { 'Back', 'Prev', 'Next', #levels == 1 and 'Story' or 'Top' }
    if AI.on() then t[#t + 1] = 'AI' end
    return t
  end
  if screen == 'chat' then
    return A.chat_bar(cfg)
  end
  if screen == 'fyset' then return { 'Back', 'Prev', 'Next' } end
  return { 'Back' }
end
local function button_rects()
  local bs, widths = buttons()
  local out, x = {}, 12
  local n = #bs
  for k, label in ipairs(bs) do
    local bw = widths and widths[k] or math.floor((W - 24 - (n - 1) * 8) / n)
    out[k] = { x = x, y = BTN_Y, w = bw, h = BTN_H, b = label }
    x = x + bw + 8
  end
  return out
end

-- the screen's size, read at every callback: after the app turns (Settings), the buttons sit at
-- the bottom, the list shows the rows that fit, and the story and comment pages are laid out
-- again at the same share of their pages
local function sync_screen()
  local okw, w = pcall(function() return tonumber(ctx.screen.width) end)
  local okh, h = pcall(function() return tonumber(ctx.screen.height) end)
  w, h = okw and w or 480, okh and h or 800
  if w == W and h == H then return end
  W, H = w, h
  BTN_Y = H - 96
  DOC_BOTTOM = BTN_Y - 30
  ROWS = math.max(3, (BTN_Y - 8 - LIST_TOP) // ROW_H)
  local function again(doc, build)
    if not doc or not doc.pages then return end
    local share = (doc.page - 1) / math.max(1, #doc.pages)
    build()
    doc.page = math.min(#doc.pages, math.floor(share * #doc.pages + 0.5) + 1)
  end
  if S and S.lines then again(S, build_story); load_pics() end
  for _k, lv in ipairs(levels) do again(lv, function() build_thread(lv) end) end
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    sync_screen()
    gg:clear(0)
    if kit.modal() then kit.draw_modal(gg); return end
    if screen == 'list' then draw_list(gg)
    elseif screen == 'story' then draw_doc(gg, S)
    elseif screen == 'thread' then draw_doc(gg, level())
    elseif screen == 'chat' then draw_doc(gg, chat)
    elseif screen == 'aimenu' then AI.draw_menu(gg)
    elseif screen == 'aiset' then AI.draw_set(gg)
    elseif screen == 'aiprov' then AI.draw_prov(gg)
    elseif screen == 'aibtns' then AI.draw_btns(gg)
    elseif screen == 'fyset' then draw_fyset(gg)
    else draw_settings(gg) end
    local line = busy_label() or status or ERR
    -- under the buttons: above them it overlapped the last list row
    if line then gg:text(12, BTN_Y + BTN_H + 6, fit(line, 'small', W - 24), { font = kit.font('small') }) end
    for _k, r in ipairs(button_rects()) do kit.button(gg, r.x, r.y, r.w, r.h, r.b, { font = 'medium' }) end
  end)
  if not ok then pcall(function() gg:text(8, H - 60, kit.short('draw ERR ' .. tostring(e), wide(46))) end) end
end

------------------------------------------------------------------ input

local function ask(title, value, fn)
  ctx.input:text({ title = title, text = value or '', max_bytes = 256 }, function(c, s)
    local ok, e = pcall(fn, s)
    if not ok then ERR = tostring(e) end
    kit.refresh()
  end)
end

local function back()
  if screen == 'chat' then screen = ai_from
  elseif screen == 'aimenu' then screen = #chat.msgs > 0 and 'chat' or ai_from
  elseif screen == 'aiset' or screen == 'fyset' then screen = 'settings'
  elseif screen == 'aiprov' or screen == 'aibtns' then screen = 'aiset'
  elseif screen == 'thread' and #levels > 1 then
    drop_all(); levels[#levels] = nil; build_thread(level()); thread_pump()
  elseif screen == 'thread' then
    drop_all(); screen = thread_from == 'story' and 'story' or 'list'
    if screen == 'story' and (not S.item or S.reading) then open_story(S.row) end
  elseif screen == 'story' or screen == 'settings' then
    drop_all(); screen, L.loading_ids = 'list', false
    if fy_changed and L.tab == 'foryou' then
      fy_changed = false
      open_tab('foryou')                           -- topics or mutes changed: asked again
    elseif L.more and (#L.rows == 0 or L.stale) then load_more() end
  end
  status = nil
end

local function doc_line_at(doc, y)
  local yy = DOC_TOP
  local last = (doc.pages[doc.page + 1] or (#doc.lines + 1)) - 1
  for k = doc.pages[doc.page] or 1, last do
    local ln = doc.lines[k]
    if y >= yy and y < yy + ln.h then return ln end
    yy = yy + ln.h
  end
end

-- More like this (a word of the title becomes a topic) / Less like this (a word or the site muted)
local function like_menu(more)
  local opts = {}
  for _k, w in ipairs(N.title_words(S.row.title)) do opts[#opts + 1] = { w, (more and '' or '-') .. w } end
  local d = N.domain(S.row.url)
  if not more and d then opts[#opts + 1] = { 'site:' .. d, '-site:' .. d } end
  local rows, row_ = {}, nil
  for k, o in ipairs(opts) do
    if k % 2 == 1 then row_ = {}; rows[#rows + 1] = row_ end
    row_[#row_ + 1] = { o[1], function()
      kit.close()
      add_foryou(o[2])
      status = (more and 'Topic added: ' or 'Muted: ') .. o[1]
    end }
  end
  rows[#rows + 1] = { { 'Cancel', function() kit.close() end } }
  kit.show({ title = more and 'More like this: follow a word' or 'Less like this: mute a word or the site',
             lines = { #opts == 0 and 'No word here to pick.' or nil }, rows = rows, cancel = function() kit.close() end })
end

-- a tap on the For you page
local function tap_fyset(x, y)
  local function hit(r) return x >= r[1] and x < r[1] + r[3] and y >= r[2] and y < r[2] + r[4] end
  local r = fy_rects()
  if hit(r.add) then
    ask('Add a topic', '', function(s) if s and s:match('%S') then add_foryou(s) end end)
  elseif hit(r.mute) then
    ask('Mute a word', '', function(s) if s and s:match('%S') then add_foryou('-' .. s:gsub('^%s*%-+', '')) end end)
  elseif hit(r.lock) and not LOCK_NET then                      -- the store's build: on or off
    if lock_is_on() then pcall(function() ctx.lockscreen:clear_default() end)
    else pcall(function() ctx.lockscreen:set_default() end) end
  elseif hit(r.lock) then
    local rows = {}
    for _k, e in ipairs(EVERY) do
      rows[#rows + 1] = { { e[2], function()
        kit.close()
        if e[1] == '0' then
          pcall(function() ctx.lockscreen:clear_default() end)
        else
          cfg.lockevery = e[1]
          save_cfg()
          if not lock_is_on() then pcall(function() ctx.lockscreen:set_default() end) end
        end
      end } }
    end
    kit.show({ title = 'Sleep screen: the For you stories, fetched again', rows = rows, cancel = function() kit.close() end })
  elseif y >= FY_TOP then
    local it = fy_entries()[(fy_page - 1) * fy_per() + (y - FY_TOP) // FY_ROW + 1]
    if not it or y >= FY_TOP + fy_per() * FY_ROW then return end
    kit.show({ title = it.label, rows = { {
      { 'Edit', function()
        kit.close()
        ask('Edit', it.value, function(s)
          if type(s) ~= 'string' then return end
          drop_foryou(it.line)
          if s:match('%S') then add_foryou(it.prefix .. s) end
        end)
      end },
      { 'Remove', function() kit.close(); drop_foryou(it.line) end },
      { 'Cancel', function() kit.close() end } } }, cancel = function() kit.close() end })
  end
end

local function tap(x, y, long)
  if kit.tap_modal(x, y) then return end
  for _k, r in ipairs(button_rects()) do
    if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then
      local b = r.b
      status = nil
      if b == 'Prev' and screen == 'fyset' then fy_page = math.max(1, fy_page - 1)
      elseif b == 'Next' and screen == 'fyset' then fy_page = math.min(fy_pages(), fy_page + 1)
      elseif b == 'Prev' then if screen == 'list' then list_page(-1) else doc_page(-1) end
      elseif b == 'Next' then if screen == 'list' then list_page(1) else doc_page(1) end
      elseif b == 'Reload' then open_tab(L.tab, L.query)
      elseif b == 'Settings' then drop_all(); screen = 'settings'
      elseif b == 'Back' then back()
      elseif b == 'Story' then drop_all(); screen = 'story'; if not S.item or S.reading then open_story(S.row) end
      elseif b == 'Top' then
        drop_all(); while #levels > 1 do levels[#levels] = nil end
        build_thread(level()); thread_pump()
      elseif b == 'AI' then AI.open()
      elseif b == 'Ask' then AI.ask_own()
      elseif b == 'More' then screen = 'aimenu'
      else open_thread(S.row) end
      return
    end
  end
  if screen == 'list' then
    if add_rect and x >= add_rect.x and x < add_rect.x + add_rect.w and y >= add_rect.y and y < add_rect.y + add_rect.h then
      ask('Add a topic', '', function(s)
        if s and s:match('%S') then add_foryou(s); open_tab('foryou') end
      end)
      return
    end
    if y < LIST_TOP - 8 then
      local t = TABS[math.max(1, math.min(#TABS, (x - 4) // ((W - 8) // #TABS) + 1))]
      if t[2] == 'find' then
        ask('Search Hacker News', L.tab == 'find' and L.query or '', function(s) if s and s:match('%S') then open_tab('find', s) end end)
      else open_tab(t[2]) end
      return
    end
    local r = L.rows[L.top + (y - LIST_TOP) // ROW_H]
    if r and y >= LIST_TOP and y < LIST_TOP + ROWS * ROW_H then
      if long then open_thread(r) else open_story(r) end
    end
  elseif screen == 'story' then
    local ln = y < DOC_BOTTOM and doc_line_at(S, y)
    if ln and ln.likes then like_menu(x < W // 2)
    elseif y < DOC_BOTTOM then doc_page(x < W // 3 and -1 or 1) end        -- left third back, else on
  elseif screen == 'fyset' then
    tap_fyset(x, y)
  elseif screen == 'thread' then
    if y >= DOC_BOTTOM then return end
    local lv = level()
    local ln = doc_line_at(lv, y)
    local cm = ln and ln.link and lv.got[ln.cidx]
    if cm then
      drop_all()
      lv.loading = false
      push_level({ type = 'comment', by = cm.by, text = cm.text }, cm.kids)
    else
      doc_page(x < W // 3 and -1 or 1)
    end
  elseif screen == 'chat' then
    if y < DOC_BOTTOM then doc_page(x < W // 3 and -1 or 1) end
  elseif screen == 'aimenu' then
    for _k, cell in ipairs(AI.menu_cells()) do
      if x >= cell.x and x < cell.x + cell.w and y >= cell.y and y < cell.y + cell.h then
        local it = cell.item
        if it[2] == 'send' then
          for j, m in ipairs(SEND) do if m[1] == cfg.aisend then cfg.aisend = SEND[j % #SEND + 1][1]; break end end
          save_cfg()
        elseif it[2] == 'ask' then AI.ask(it[3], it[1])
        elseif it[2] == 'own' then AI.ask_own()
        elseif it[2] == 'web' then
          chat.web = not chat.web
          status = chat.web and 'Web search on for the next questions' or 'Web search off'
        elseif it[2] == 'new' then
          AI.check()
          if chat.waiting then status = 'Still waiting for the answer.' else chat.msgs = {}; AI.layout(false) end
        end
        return
      end
    end
  elseif screen == 'aiset' then
    for k = 1, #A.SET do
      local sx, sy, sw, sh = AI.rect(k)
      if x >= sx and x < sx + sw and y >= sy and y < sy + sh then AI.edit(k); return end
    end
  elseif screen == 'aibtns' then
    local list = A.buttons()
    for i = 1, #list + (#list < A.BUTTONS_MAX and 1 or 0) do
      local bx, by, bw, bh = AI.btn_rect(i)
      if x >= bx and x < bx + bw and y >= by and y < by + bh then AI.edit_button(i); return end
    end
  elseif screen == 'aiprov' then
    for i, P in ipairs(A.PROVIDERS) do
      local px, py, pw, ph = AI.prov_rect(i)
      if x >= px and x < px + pw and y >= py and y < py + ph then AI.choose(P.id); return end
    end
  elseif screen == 'settings' then
    for k, s in ipairs(settings_list()) do
      local sx, sy, sw, sh = setting_rect(k)
      if x >= sx and x < sx + sw and y >= sy and y < sy + sh then
        if s[1] == 'ai' then AI.import(); screen = 'aiset'
        elseif s[1] == 'foryou' then load_foryou(); fy_page = 1; screen = 'fyset'
        elseif s[1] == 'size' then cfg.size = SIZES[cfg.size]; save_cfg()
        elseif s[1] == 'images' then cfg.images = cfg.images == 'on' and 'off' or 'on'; save_cfg()
        elseif s[1] == 'screen' then
          cfg.screen = cfg.screen == 'landscape' and 'portrait' or 'landscape'
          save_cfg()
          apply_orientation()                        -- the next callback sees the new size
        else ask(s[2], cfg[s[1]], function(v) if type(v) == 'string' then cfg[s[1]] = (v:gsub('^%s+', ''):gsub('%s+$', '')); save_cfg() end end) end
        return
      end
    end
  end
end

local long_done, suppress_up = false, false
function on_input(c, ev)
  ERR = nil
  local left = false
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    sync_screen()
    pump()
    if ev.type == 'pointer' then
      local x, y = ev.x or 0, ev.y or 0
      if ev.phase == 'down' then long_done = false end
      if (ev.gesture == 'long' or ev.phase == 'hold') and not kit.modal() then
        if not long_done then tap(x, y, true) end
        long_done, suppress_up = true, ev.phase ~= 'up'
        if ev.phase == 'up' then long_done = false end
        return
      end
      if ev.phase ~= 'up' then return end
      long_done = false
      if suppress_up then suppress_up = false; return end
      if kit.modal() then tap(x, y, false); return end
      local delta = ev.gesture == 'swipe_up' and 1 or ev.gesture == 'swipe_down' and -1 or nil
      if delta and (screen == 'list' or screen == 'story' or screen == 'thread' or screen == 'chat') then
        if screen == 'list' then list_page(delta) else doc_page(delta) end
        return
      end
      tap(x, y, false)
    elseif ev.type == 'key' and kit.key_accepted(ev) then
      if kit.modal() then
        if ev.key == 'back' and kit.modal().cancel then kit.modal().cancel() end
      elseif ev.key == 'back' and screen == 'list' then
        left = true                                -- not handled: the host asks whether to leave
      elseif ev.key == 'back' then back()
      else
        local delta = (ev.key == 'down' or ev.key == 'right') and 1 or (ev.key == 'up' or ev.key == 'left') and -1 or nil
        if delta and screen == 'list' then list_page(delta) elseif delta then doc_page(delta) end
      end
    end
  end)
  if not ok then ERR = tostring(e) end
  if screen ~= 'story' then release_pics() end
  kit.refresh()
  return not left
end

function on_load(c)
  local ok, e = pcall(function()
    load_cfg()
    AI.import()
    load_foryou()
    if cfg.screen == 'landscape' then apply_orientation() end   -- the first frame is already turned
    open_tab(#fy.topics > 0 and 'foryou' or 'top')            -- with topics, For you first
  end)
  if not ok then ERR = tostring(e) end
end
function on_leave()
  drop_all()
  release_pics()
  if qr and qr.img then pcall(function() qr.img:release() end) end
  pcall(function() ctx.net:keep_wifi(1) end)
end

if rawget(_G, '__TEST') then
  __TEST.api = { N = N, L = function() return L end, S = function() return S end, screen = function() return screen end,
                 levels = function() return levels end, level = level, cfg = cfg, status = function() return status end,
                 queue = function() return #queue + (inflight and 1 or 0) end, pics = function() return pics end,
                 chat = function() return chat end, A = A }
end
