-- Wikipedia reader for XTOS Licorice, API 2.9 (uses tools/gamekit). Needs Wi-Fi.
--
-- Search, a random article, or one read before (kept for offline reading). Articles come as
-- plain text from the MediaWiki API of the chosen language's Wikipedia (the TextExtracts
-- "explaintext" extract: sections marked "== Heading =="), are laid out with the system fonts
-- and paged with taps, swipes or the side buttons; a long article in parts of about 20 KB
-- (Next past a part's last page fetches the next one). Languages: a list of common ones written in
-- Latin script (the reader's fonts may not carry other scripts) and any other code typed in.
--
-- Requests go one at a time (the host answers one at a time) and Wi-Fi is kept up while the app
-- is used, as in the RSS app.

local W, H = kit.W, kit.H
local TOP = 64
local TEXT_MAX = 20000                 -- an article is read in parts this big (the device has ~1 MB for Lua)
local DECODE_MAX = 100000              -- bigger answers are not given to the JSON decoder
local HISTORY_MAX = 30
local UA = 'XteinkLicoriceWikipedia/1.0 (https://github.com/omer-faruq/touch-licorice-apps)'
local LANGS = {
  { 'en', 'English' }, { 'simple', 'Simple English' }, { 'tr', 'Türkçe' }, { 'de', 'Deutsch' },
  { 'fr', 'Français' }, { 'es', 'Español' }, { 'it', 'Italiano' }, { 'nl', 'Nederlands' },
  { 'pt', 'Português' }, { 'pl', 'Polski' }, { 'sv', 'Svenska' },
}
local SIZES = {
  small = { head = 'medium', body = 'small' },
  medium = { head = 'large', body = 'medium' },
  large = { head = 'large', body = 'large' },
}
local SIZE_ORDER = { 'medium', 'large', 'small' }

local cfg = { lang = 'en', size = 'medium' }
local screen = 'home'                  -- home | results | article | history
local results, results_q, results_top = {}, '', 1
local art = { title = '', lines = {}, starts = { 1 }, page = 1, pages = 1 }
local history = {}                     -- { { title, lang, file } ... } newest first
local status, loading = nil, nil
local ERR = nil
local RESULT_ROWS = 8

local function short(s, n) return kit.short(tostring(s or ''), n) end
local function refresh() kit.refresh() end

------------------------------------------------------------------ settings and storage

local function load_cfg()
  local t = kit.kv(kit.read('settings.txt'))
  if t.lang and t.lang:match('^[a-z%-]+$') then cfg.lang = t.lang end
  if SIZES[t.size or ''] then cfg.size = t.size end
end
local function save_cfg() kit.write('settings.txt', 'lang=' .. cfg.lang .. '\nsize=' .. cfg.size) end
local function lang_name(code)
  for _k, l in ipairs(LANGS) do if l[1] == code then return l[2] end end
  return code
end

local function load_history()
  history = {}
  for line in ((kit.read('history.txt') or '') .. '\n'):gmatch('([^\n]*)\n') do
    local lang, file, title = line:match('^([^\t]+)\t([^\t]+)\t(.+)$')
    if lang then history[#history + 1] = { lang = lang, file = file, title = title } end
  end
end
local function save_history()
  local out = {}
  for _k, h in ipairs(history) do out[#out + 1] = h.lang .. '\t' .. h.file .. '\t' .. h.title end
  kit.write('history.txt', table.concat(out, '\n'))
end

-- a file name for an article: its language and a hash of its title
local function article_file(lang, title)
  local h = 5381
  for i = 1, #title do h = (h * 33 + title:byte(i)) % 4294967296 end
  return 'a_' .. lang:gsub('%-', '') .. '_' .. string.format('%08x', h) .. '.txt'
end

local function remember(lang, title, text)
  local file = article_file(lang, title)
  kit.write(file, title .. '\n' .. text)
  for k = #history, 1, -1 do if history[k].file == file then table.remove(history, k) end end
  table.insert(history, 1, { lang = lang, file = file, title = title })
  while #history > HISTORY_MAX do
    local old = table.remove(history)
    pcall(function() ctx.storage:remove(old.file) end)
  end
  save_history()
end

------------------------------------------------------------------ network (as in the RSS app)

local WIFI_KEEP_MS = 5 * 60 * 1000
local wifi_kept_at = nil
local function keep_wifi(force)
  local t = kit.now_ms()
  if not force and t and wifi_kept_at and t - wifi_kept_at < 30000 then return end
  wifi_kept_at = t
  pcall(function() ctx.net:keep_wifi(WIFI_KEEP_MS) end)
end

local net_queue, net_active = {}, nil
local net_pump
local function net_finish(job, resp, err)
  if job.done then return end
  job.done = true
  if net_active == job then net_active = nil end
  if not net_active and #net_queue == 0 then loading = nil end
  -- an error while handling the answer (memory, say) is shown instead of closing the app
  local ok, e = pcall(job.on_result, resp, err)
  if not ok then status = 'Error: ' .. short(e, 40) end
  net_pump()
  refresh()
end
net_pump = function()
  if net_active or #net_queue == 0 then return end
  local job = table.remove(net_queue, 1)
  net_active, job.since, loading = job, kit.now_ms(), job.label
  local ok, err = pcall(function()
    job.handle = ctx.net:request(job.opts, function(c, resp) net_finish(job, resp, nil) end)
  end)
  if not ok then net_finish(job, nil, short(err, 60)) end
end
local function busy()
  if net_active then
    local t = kit.now_ms()
    if t and net_active.since and t - net_active.since > net_active.timeout then
      if net_active.handle then pcall(function() net_active.handle:cancel() end) end
      net_finish(net_active, nil, 'no answer within ' .. net_active.timeout // 1000 .. ' s')
    end
  end
  return net_active ~= nil or #net_queue > 0
end

local function urlenc(s)
  return (tostring(s):gsub('[^%w%-%._~]', function(c) return string.format('%%%02X', c:byte()) end))
end

-- GET the API of the chosen Wikipedia with these parameters; on_done(data), or on_done(nil, err)
-- and the raw body when it came but did not decode (see part_from)
local function api(params, label, on_done)
  local q = { 'format=json', 'formatversion=2', 'utf8=1' }
  for k, v in pairs(params) do q[#q + 1] = k .. '=' .. urlenc(v) end
  table.sort(q)
  local url = 'https://' .. cfg.lang .. '.wikipedia.org/w/api.php?' .. table.concat(q, '&')
  keep_wifi()
  net_queue[#net_queue + 1] = {
    opts = { url = url, method = 'GET', headers = { ['User-Agent'] = UA, ['Api-User-Agent'] = UA }, timeout_ms = 30000 },
    label = label, timeout = 30000,
    on_result = function(resp, err)
      if err then on_done(nil, err); return end
      if type(resp) ~= 'table' then on_done(nil, 'no response'); return end
      local code = tonumber(resp.status) or tonumber(resp.code)
      if code and code >= 400 then on_done(nil, 'HTTP ' .. code); return end
      if type(resp.body) ~= 'string' then on_done(nil, tostring(resp.error or 'empty answer')); return end
      if #resp.body > DECODE_MAX then on_done(nil, 'too big to decode', resp.body); return end
      local ok, data = pcall(function() return ctx.json:decode(resp.body) end)
      if not ok or type(data) ~= 'table' then on_done(nil, 'not JSON: ' .. short(resp.body, 30), resp.body); return end
      if type(data.error) == 'table' then on_done(nil, tostring(data.error.info or data.error.code)); return end
      on_done(data)
    end,
  }
  net_pump()
end

------------------------------------------------------------------ article layout

-- word widths, remembered while one part is laid out (at most 800 words: memory)
local measure_cache, measure_n = {}, 0
local function measure(font, s)
  local w = measure_cache[s]
  if w then return w end
  w = kit.width(font, s)
  if measure_n > 800 then measure_cache, measure_n = {}, 0 end
  measure_cache[s], measure_n = w, measure_n + 1
  return w
end

local function wrap_para(out, para, fname, width)
  local font = kit.font(fname)
  local lh = kit.line_h(fname)
  local function push(s) out[#out + 1] = { s = s, f = fname, h = lh + 2 } end
  local line, lw = '', 0
  local space_w = measure(font, ' ')
  for word in para:gmatch('[^ \t]+') do
    local ww = measure(font, word)
    if ww > width then
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

local function layout(title, text)
  measure_cache, measure_n = {}, 0
  local S = SIZES[cfg.size]
  local out = {}
  local function gap(h) out[#out + 1] = { s = '', f = 'small', h = h } end
  wrap_para(out, title, 'large', W - 24)
  out[#out + 1] = { s = '', f = 'small', h = 10, rule = true }
  gap(6)
  for para in (text .. '\n'):gmatch('([^\n]*)\n') do
    local level, head = para:match('^(=+)%s*(.-)%s*=+$')
    if level then
      gap(8)
      wrap_para(out, head, #level <= 2 and S.head or S.body, W - 24)
      if #level > 2 then out[#out].bold = true end
      gap(4)
    elseif para:match('%S') then
      wrap_para(out, para, S.body, W - 24)
      gap(8)
    end
  end
  art.title, art.lines, art.starts = title, out, { 1 }
  local avail, used = H - TOP - 60, 0
  for i, ln in ipairs(out) do
    if used + ln.h > avail and used > 0 then art.starts[#art.starts + 1] = i; used = 0 end
    used = used + ln.h
  end
  art.pages, art.page = #art.starts, 1
end

local function show_article(title, text)
  layout(title, text)
  art.part, art.more, art.offs = 1, false, { 0 }
  screen, status = 'article', nil
end

------------------------------------------------------------------ actions

-- A JSON string value read straight from the text after `"key":"` (from position `from`),
-- unescaped: `skip` bytes are passed over, then at most `max` bytes are kept. For answers the
-- host's JSON decoder gives up on (a long article: tr "Mustafa Kemal Atatürk" is 172 KB) or that
-- arrived cut short. Returns the text and how it ended: 'end' (the closing quote), 'max' (more
-- follows) or 'cut' (the answer stops inside the string).
local function json_string(body, key, from, skip, max)
  local _s, e = body:find('"' .. key .. '"%s*:%s*"', from or 1)          -- keys are plain words
  if not e then return nil end
  skip, max = skip or 0, max or math.huge
  local out, pos, kept, i = {}, 0, 0, e + 1
  local function emit(seg)
    local n = #seg
    if pos + n > skip and kept < max then
      local piece = (pos < skip) and seg:sub(skip - pos + 1) or seg
      if kept + #piece > max then piece = piece:sub(1, max - kept) end     -- never more than max
      out[#out + 1] = piece
      kept = kept + #piece
    end
    pos = pos + n
  end
  while true do
    local j = body:find('[\\"]', i)
    if not j then emit(body:sub(i)); return table.concat(out), 'cut' end
    emit(body:sub(i, j - 1))
    if kept >= max then break end
    if body:byte(j) == 34 then return table.concat(out), 'end' end
    local x = body:sub(j + 1, j + 1)
    if x == 'n' then emit('\n')
    elseif x == 't' then emit(' ')
    elseif x == 'u' then
      local cp, adv = tonumber(body:sub(j + 2, j + 5), 16) or 63, 4
      if cp >= 0xD800 and cp <= 0xDBFF and body:sub(j + 6, j + 7) == '\\u' then
        local lo = tonumber(body:sub(j + 8, j + 11), 16)
        if lo then cp, adv = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00), 10 end
      end
      if cp < 0xD800 or cp > 0xDFFF then emit(utf8.char(cp)) end
      j = j + adv
    elseif x ~= 'r' then emit(x) end                      -- \" \\ \/
    i = j + 2
    if kept >= max then break end
  end
  return table.concat(out), 'max'
end

-- An article is read in parts of about TEXT_MAX bytes, each ending at a paragraph: a long one
-- would not fit the ~1 MB the reader gives Lua once laid out. `skip` is where the part starts in
-- the article's text. Returns the title, the part's text and whether more follows; the part
-- tells when the answer arrived cut short.
local function part_from(data, body, skip)
  local title, text, how
  if data then
    local p = data.query and data.query.pages and data.query.pages[1]
    if not p or p.missing or type(p.extract) ~= 'string' then return nil end
    title, text = p.title, p.extract:sub(skip + 1, skip + TEXT_MAX)
    how = (#p.extract > skip + TEXT_MAX) and 'max' or 'end'
  else
    if type(body) ~= 'string' then return nil end
    local at = body:find('"pages"%s*:%s*%[')
    if not at then return nil end
    title = json_string(body, 'title', at, 0, 300)
    text, how = json_string(body, 'extract', at, skip, TEXT_MAX)
    if not text then return nil end
  end
  if how == 'max' then
    -- end the part at a paragraph, else between words, else at least at a whole UTF-8 character
    local cut = text:match('^(.*\n)')
    if not cut or #cut <= TEXT_MAX // 2 then cut = text:match('^(.* )') end
    if cut and #cut > TEXT_MAX // 2 then text = cut
    else text = text:gsub('[\192-\255][\128-\191]*$', '') end
  end
  if how == 'cut' then text = text .. '\n\n(The rest of the article did not arrive.)' end
  return title, text, how == 'max'
end

local function tidy(t) return (t:gsub('\r', ''):gsub('\n\n\n+', '\n\n')) end

-- show part k of the current article (art.offs[k] is where it starts in the text)
local function show_part(title, text, k, more)
  local note
  if more then note = '\n\n(Part ' .. k .. '. Next: part ' .. (k + 1) .. '.)'
  elseif k > 1 then note = '\n\n(End of the article, part ' .. k .. '.)' end
  layout(title, tidy(text) .. (note or ''))
  art.part, art.more = k, more
  art.offs[k + 1] = more and (art.offs[k] + #text) or nil
  screen, status = 'article', nil
end

local function open_answer(data, err, body, fallback, keep)
  local t, text, more = part_from(data, body, 0)
  if not text then status = data and 'No such article.' or ('Could not load: ' .. tostring(err)); return end
  art.offs = { 0 }
  art.lang = cfg.lang
  if keep then remember(cfg.lang, t or fallback, tidy(text) .. (more and '\n\n(Only the first part is kept here.)' or '')) end
  show_part(t or fallback, text, 1, more)
end

local function open_title(title)
  api({ action = 'query', prop = 'extracts', explaintext = '1', exsectionformat = 'wiki', redirects = '1', titles = title },
      'Loading ' .. short(title, 30) .. '...', function(data, err, body) open_answer(data, err, body, title, true) end)
end

-- another part of the article on the screen; `last_page` shows its end (paging back)
local function load_part(k, last_page)
  local title, skip = art.title, art.offs and art.offs[k]
  if not skip then return end
  api({ action = 'query', prop = 'extracts', explaintext = '1', exsectionformat = 'wiki', redirects = '1', titles = title },
      'Loading part ' .. k .. '...', function(data, err, body)
    local t, text, more = part_from(data, body, skip)
    if not text then status = 'Could not load: ' .. tostring(err); return end
    show_part(t or title, text, k, more)
    if last_page then art.page = art.pages end
  end)
end

local function open_random()
  api({ action = 'query', generator = 'random', grnnamespace = '0', prop = 'extracts', explaintext = '1', exsectionformat = 'wiki' },
      'Finding an article...', function(data, err, body) open_answer(data, err, body, '?', true) end)
end

local function search(q)
  results_q = q
  api({ action = 'query', list = 'search', srsearch = q, srlimit = '24', srprop = 'snippet' },
      'Searching ' .. short(q, 24) .. '...', function(data, err)
    if not data then status = 'Search failed: ' .. tostring(err); return end
    results, results_top = {}, 1
    for _k, r in ipairs((data.query and data.query.search) or {}) do
      -- a snippet is a piece of wikitext: tags, entities and reference marks out
      local snip = tostring(r.snippet or ''):gsub('<[^>]+>', ''):gsub('&quot;', '"'):gsub('&amp;', '&'):gsub('&#039;', "'")
      snip = snip:gsub('%^', ''):gsub('%s+', ' '):gsub('^ ', '')
      results[#results + 1] = { title = tostring(r.title), snippet = snip }
    end
    screen, status = 'results', (#results == 0 and 'Nothing found.' or nil)
  end)
end

local function ask_search()
  ctx.input:text({ title = 'Search Wikipedia (' .. cfg.lang .. ')', value = results_q }, function(c, s)
    if s and s:match('%S') then search(s) end
    refresh()
  end)
end

local function open_history(h)
  local s = kit.read(h.file)
  if not s then status = 'That article is no longer saved.'; return end
  local title, text = s:match('^([^\n]*)\n(.*)$')
  show_article(title or h.title, text or '')
end

local function choose_language()
  local rows, row = {}, {}
  for _k, l in ipairs(LANGS) do
    row[#row + 1] = { l[1], function() kit.close(); cfg.lang = l[1]; save_cfg() end }
    if #row == 4 then rows[#rows + 1] = row; row = {} end
  end
  row[#row + 1] = { 'Other', function()
    kit.close()
    ctx.input:text({ title = 'Wikipedia language code (en, tr, ...)', value = cfg.lang }, function(c, s)
      s = (s or ''):lower():gsub('%s', '')
      if s:match('^[a-z][a-z%-]+$') and #s <= 12 then cfg.lang = s; save_cfg() end
      refresh()
    end)
  end }
  rows[#rows + 1] = row
  kit.show({ title = 'Language', lines = { 'Now: ' .. lang_name(cfg.lang) .. ' (' .. cfg.lang .. ').wikipedia.org' },
             rows = rows, cancel = kit.close })
end

------------------------------------------------------------------ screens

local HOME = {
  { function() return 'Search' end, function() ask_search() end },
  { function() return 'Random article' end, function() art.back = 'home'; open_random() end },
  { function() return 'Read before (' .. #history .. ')' end, function() screen = 'history'; results_top = 1 end },
  { function() return 'Language: ' .. lang_name(cfg.lang) end, choose_language },
  { function() return 'Text size: ' .. cfg.size end, function()
      local k = 1
      for i, s in ipairs(SIZE_ORDER) do if s == cfg.size then k = i end end
      cfg.size = SIZE_ORDER[k % #SIZE_ORDER + 1]
      save_cfg()
    end },
}
local function home_rect(k) return 24, 110 + (k - 1) * 96, W - 48, 76 end

local function bar(gg, labels)
  local n = #labels
  local bw = (W - 16 - (n - 1) * 6) // n
  for k, l in ipairs(labels) do kit.button(gg, 8 + (k - 1) * (bw + 6), 6, bw, 50, l, { font = 'medium' }) end
end
local function bar_hit(x, y, n)
  if y >= 60 then return nil end
  local bw = (W - 16 - (n - 1) * 6) // n
  local k = (x - 8) // (bw + 6) + 1
  if k >= 1 and k <= n then return k end
end

local function list_rows()
  if screen == 'results' then return results end
  local out = {}
  for _k, h in ipairs(history) do out[#out + 1] = { title = h.title, snippet = lang_name(h.lang), h = h } end
  return out
end
local ROW_H = 76

local function draw_list(gg)
  local rows = list_rows()
  bar(gg, { 'Back', 'Prev', 'Next', screen == 'results' and 'Search' or 'Clear' })
  for k = results_top, math.min(#rows, results_top + RESULT_ROWS - 1) do
    local r = rows[k]
    local y = TOP + 8 + (k - results_top) * ROW_H
    gg:text(16, y, short(r.title, 38), { font = kit.font('medium') })
    gg:text(16, y + 30, short(r.snippet, 52), { font = kit.font('small') })
    gg:line(16, y + ROW_H - 8, W - 16, y + ROW_H - 8)
  end
  if #rows == 0 then gg:text(16, TOP + 30, screen == 'results' and 'Nothing found.' or 'Nothing read yet.', { font = kit.font('medium') }) end
end

local function draw_article(gg)
  bar(gg, { 'Back', 'Prev', 'Next', art.page .. '/' .. art.pages })
  local first = art.starts[art.page] or 1
  local last = (art.starts[art.page + 1] or (#art.lines + 1)) - 1
  local y = TOP + 6
  for i = first, last do
    local ln = art.lines[i]
    if ln.rule then gg:line(12, y + 4, W - 12, y + 4); gg:line(12, y + 5, W - 12, y + 5)
    elseif ln.s ~= '' then
      gg:text(12, y, ln.s, { font = kit.font(ln.f) })
      if ln.bold then gg:text(13, y, ln.s, { font = kit.font(ln.f) }) end
    end
    y = y + ln.h
  end
end

local function draw_home(gg)
  gg:text(16, 16, 'Wikipedia', { font = kit.font('large') })
  gg:text(16, 56, cfg.lang .. '.wikipedia.org    needs Wi-Fi', { font = kit.font('small') })
  gg:line(0, 90, W, 90)
  for k, b in ipairs(HOME) do
    local x, y, w, h = home_rect(k)
    kit.button(gg, x, y, w, h, b[1](), { font = 'medium' })
  end
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    busy()
    gg:clear(0)
    if kit.modal() then
      gg:text(16, 16, 'Wikipedia', { font = kit.font('large') })
      gg:line(0, 90, W, 90)
      kit.draw_modal(gg)
      return
    end
    if screen == 'home' then draw_home(gg)
    elseif screen == 'article' then draw_article(gg)
    else draw_list(gg) end
    local line = loading or status or ERR
    if line then
      gg:rect(0, H - 40, W, 40, { line_width = 1 })
      gg:text(12, H - 32, short(line, 48), { font = kit.font('small') })
    end
  end)
  if not ok then pcall(function() gg:text(8, H - 60, short('draw ERR ' .. tostring(e), 46)) end) end
end

------------------------------------------------------------------ input

local function page(delta)
  if screen == 'article' then
    -- past the last page: the article's next part; before the first: the part before
    if delta > 0 and art.page >= art.pages and art.more then load_part(art.part + 1); return end
    if delta < 0 and art.page <= 1 and (art.part or 1) > 1 then load_part(art.part - 1, true); return end
    art.page = math.max(1, math.min(art.pages, art.page + delta))
  elseif screen == 'results' or screen == 'history' then
    local n = #list_rows()
    results_top = math.max(1, math.min(results_top + delta * RESULT_ROWS, math.max(1, n - (n - 1) % RESULT_ROWS)))
  end
end

local function tap(x, y)
  if kit.tap_modal(x, y) then return end
  if screen == 'home' then
    for k, b in ipairs(HOME) do
      local bx, by, bw, bh = home_rect(k)
      if x >= bx and x < bx + bw and y >= by and y < by + bh then status = nil; b[2](); return end
    end
    return
  end
  local k = bar_hit(x, y, 4)
  if k == 1 then
    -- an article goes back to where it was opened: the results, the list read before, home
    if screen == 'article' then screen = art.back or 'home' else screen = 'home' end
    status = nil
    return
  elseif k == 2 then page(-1); return
  elseif k == 3 then page(1); return
  elseif k == 4 then
    if screen == 'results' then ask_search()
    elseif screen == 'history' then
      kit.show({ title = 'Forget the articles read?', lines = { 'They are no longer kept for offline reading.' },
                 rows = { { { 'Forget', function()
                              kit.close()
                              for _i, h in ipairs(history) do pcall(function() ctx.storage:remove(h.file) end) end
                              history = {}; save_history()
                            end }, { 'Cancel', kit.close } } }, cancel = kit.close })
    end
    return
  end
  if screen == 'article' then
    page(x < W // 3 and -1 or 1)
  else
    local rows = list_rows()
    local i = results_top + (y - TOP - 8) // ROW_H
    local r = y > TOP and rows[i]
    if r then
      art.back = screen
      if r.h then open_history(r.h) else open_title(r.title) end
    end
  end
end

function on_input(c, ev)
  ERR = nil
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    keep_wifi()
    if ev.type == 'pointer' and ev.phase == 'up' then
      if ev.gesture == 'swipe_left' or ev.gesture == 'swipe_up' then page(1)
      elseif ev.gesture == 'swipe_right' or ev.gesture == 'swipe_down' then page(-1)
      else tap(ev.x or 0, ev.y or 0) end
    elseif ev.type == 'key' and kit.key_accepted(ev) then
      if kit.modal() then
        if ev.key == 'back' and kit.modal().cancel then kit.modal().cancel() end
      elseif ev.key == 'down' or ev.key == 'right' then page(1)
      elseif ev.key == 'up' or ev.key == 'left' then page(-1)
      elseif ev.key == 'back' and screen ~= 'home' then screen = 'home' end
    end
  end)
  if not ok then ERR = tostring(e) end
  refresh()
  return true
end

function on_load(c)
  load_cfg()
  load_history()
  keep_wifi(true)
end
function on_leave() pcall(function() ctx.net:keep_wifi(1) end) end

if rawget(_G, '__TEST') then
  __TEST.api = { screen = function() return screen end, art = function() return art end, cfg = cfg,
                 results = function() return results end, history = function() return history end,
                 status = function() return status end }
end
