-- Dictionary for XTOS Licorice, API 2.9. Looks words up in a StarDict dictionary that
-- tools/stardict2shards.py converted into sorted text shards, copied over USB into this app's
-- storage folder on the SD card (XTApps/dict/files/): info.txt, shards.tsv, d000.txt ...
--
-- Search screen: the firmware keyboard docked at the bottom (ctx.input:edit), suggestions above
-- it as you type; Done or a tap on a suggestion opens the entry, laid out and paged like RSS.
-- My words: every word looked up, newest first (how often, and when it comes up for review);
-- one can be removed, or all of them. Review: the words come back as cards (the word, then its
-- entry) on the FSRS schedule Anki uses (tools/gamekit/fsrs.lua): Again / Hard / Good / Easy.
-- Every ctx.* function is a method on this API: colon calls everywhere.

local FS = require('fsrs')
local W, H, TOP = 480, 800, 56
local KB_H = 436                 -- the docked keyboard's height on this device
local MAX_SUGGEST = 7
local HISTORY_MAX = 500          -- words kept in My words (the search screen shows the latest)
local NEW_PER_DAY = 10           -- words that come up for their first review in a day

local G, ERR = nil, nil
local screen = 'search'           -- search | entry | settings | nodata | words | review
local status = ''
local dict = { name = '', words = 0, shards = {}, source = '' }   -- shards: { {file, lo, hi} ... }
local query, suggestions = '', {}
local editor = nil
local cache = { file = nil, text = nil }
local history = {}                -- { {w, n (times looked up), t (last time)} ... }, newest first
local cards = {}                  -- word -> its review record (fsrs.lua); a word without one is new
local entry = { word = '', lines = {}, starts = { 1 }, page = 1, pages = 1, from = 'search' }
local measure_cache = {}

local function short(s, n) s = tostring(s); if #s > n then return s:sub(1, n - 1) .. '~' end return s end
local function note(s) status = tostring(s or '') end
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
local function lower(s) return (s:gsub('%u', string.lower)) end   -- ASCII fold; the shard order is ASCII case-insensitive

------------------------------------------------------------------ data sources
-- Two places the converted dictionary can live:
--   storage: files copied over USB into XTApps/dict/files/ (whole-file reads, ctx.storage)
--   package: the data section of this .xtapp (built by build_dict.py), read line by line through
--            ctx.package:open_text, the package's seekable line reader

-- a file from the app's user folder (ctx.files, API 2.9: AppFiles/<app_id>, where the user
-- copies dictionaries), read 64 KB at a time; a host that hands back the whole file is fine too
local function files_read(name)
  local F = ctx.files
  if not F then return nil end
  local ok, t = pcall(function()
    if not F:exists(name) then return nil end
    local parts, off = {}, 0
    for _i = 1, 64 do
      local piece = F:read(name, off, 65536)
      if type(piece) ~= 'string' or piece == '' then break end
      parts[#parts + 1] = piece
      off = off + #piece
      if #piece ~= 65536 then break end
    end
    return table.concat(parts)
  end)
  return (ok and type(t) == 'string' and t ~= '') and t or nil
end
-- names in the user folder and in the private files (dictionaries copied the older way)
local function copied_names()
  local seen, out = {}, {}
  local okf, files = pcall(function() return ctx.files:list() end)
  for _, f in ipairs((okf and type(files) == 'table') and files or {}) do
    local n = type(f) == 'table' and f.name or f
    if type(n) == 'string' and not seen[n] then seen[n] = true; out[#out + 1] = n end
  end
  local oks, names = pcall(function() return ctx.storage:list() end)
  for _, n in ipairs((oks and type(names) == 'table') and names or {}) do
    if type(n) == 'string' and not seen[n] then seen[n] = true; out[#out + 1] = n end
  end
  return out
end
local function storage_read(name)
  local f = files_read(name)
  if f then return f end
  local ok, s = pcall(function() return ctx.storage:read(name) end)
  if ok and type(s) == 'string' then return s end
  return nil
end

local function package_read(name)
  local P = ctx.package
  if not P then return nil end
  local ok, r = pcall(function() return P:open_text(name, { max_bytes = 2000000, max_line_bytes = 8192 }) end)
  if not ok or r == nil then return nil end
  local parts = {}
  while true do
    local okl, line = pcall(function() return r:read_line() end)
    if not okl or line == nil then break end
    parts[#parts + 1] = line
  end
  pcall(function() r:close() end)
  if #parts == 0 then return nil end
  return table.concat(parts, '\n') .. '\n'
end

-- iterate "word<TAB>definition" lines of a shard without holding the whole file when it comes
-- from the package; fn(word, def) returns true to stop
local function each_line(name, fn)
  if dict.source == 'storage' then
    if cache.file ~= name then cache.text = storage_read(name); cache.file = cache.text and name or nil end
    if not cache.text then return end
    for w, def in cache.text:gmatch('([^\t\n]+)\t([^\n]*)\n') do
      if fn(w, def) then return end
    end
    return
  end
  local P = ctx.package
  if not P then return end
  local ok, r = pcall(function() return P:open_text(name, { max_bytes = 2000000, max_line_bytes = 8192 }) end)
  if not ok or r == nil then return end
  while true do
    local okl, line = pcall(function() return r:read_line() end)
    if not okl or line == nil then break end
    local w, def = line:match('^([^\t]+)\t(.*)$')
    if w and fn(w, def) then break end
  end
  pcall(function() r:close() end)
end

-- every "<prefix>_shards.tsv" (or a bare shards.tsv) in storage is one dictionary; the package
-- data section may hold one more (bare names)
local sets = {}            -- { {prefix = 'entr_', source = 'storage', name = ...} ... }
local set_index = 1

local function discover_sets()
  sets = {}
  local names = copied_names()
  if #names > 0 then
    table.sort(names)
    for _, n in ipairs(names) do
      local pre = n:match('^(.*)shards%.tsv$')
      if pre then sets[#sets + 1] = { prefix = pre, source = 'storage' } end
    end
  end
  if package_read('shards.tsv') then sets[#sets + 1] = { prefix = '', source = 'package' } end
  for _, s in ipairs(sets) do
    local read = s.source == 'storage' and storage_read or package_read
    local info = read(s.prefix .. 'info.txt')
    s.name = s.prefix:gsub('_$', '')
    if info then
      local nm = info:match('name=([^\n]*)')
      if nm and nm ~= '' then s.name = nm end
    end
  end
  return #sets > 0
end

local function load_dict()
  dict = { name = '', words = 0, shards = {}, source = '' }
  local s = sets[set_index]
  if not s then return false end
  local read = s.source == 'storage' and storage_read or package_read
  dict.source = s.source
  dict.name = s.name or ''
  local info = read(s.prefix .. 'info.txt')
  if info then
    for k, v in info:gmatch('(%w+)=([^\n]*)') do
      if k == 'words' then dict.words = tonumber(v) or 0 end
    end
  end
  local tsv = read(s.prefix .. 'shards.tsv')
  if not tsv then return false end
  for line in tsv:gmatch('([^\n]*)\n') do
    local file, lo, hi = line:match('^([^\t]+)\t([^\t]*)\t([^\t]*)$')
    if file then dict.shards[#dict.shards + 1] = { file = file, lo = lower(lo), hi = lower(hi) } end
  end
  cache = { file = nil, text = nil }
  pcall(function() ctx.state = ctx.state or {}; ctx.state.dict = s.prefix end)
  if s.source == 'storage' and not storage_read('lock_dict.txt') then   -- Word of the Day's, until chosen in Settings
    pcall(function() ctx.storage:write('lock_dict.txt', s.prefix) end)
  end
  return #dict.shards > 0
end

local function select_dict(i)
  if not sets[i] or i == set_index then return end
  set_index = i
  load_dict()
  query, suggestions = '', {}
end
local read_file = storage_read

local function now_sec()
  local ok, t = pcall(function() return ctx.clock:now() end)
  if ok and type(t) == 'table' and tonumber(t.epoch_sec) then return math.floor(tonumber(t.epoch_sec)) end
  return 0
end

-- history.txt: "word<TAB>times<TAB>last time" a line, newest first (an older one: words alone);
-- cards.txt: "word<TAB>record" for the words reviewed at least once
local function load_history()
  history = {}
  local s = read_file('history.txt')
  for line in ((s or '') .. '\n'):gmatch('([^\n]*)\n') do
    local w, n, t = line:match('^([^\t]+)\t(%d+)\t(%d+)$')
    if w then history[#history + 1] = { w = w, n = tonumber(n), t = tonumber(t) }
    elseif line ~= '' and not line:find('\t') then history[#history + 1] = { w = line, n = 1, t = 0 } end
  end
  cards = {}
  for line in ((read_file('cards.txt') or '') .. '\n'):gmatch('([^\n]*)\n') do
    local w, r = line:match('^([^\t]+)\t(.+)$')
    local rec = w and FS.parse(r)
    if rec then cards[w] = rec end
  end
end
local function save_history()
  local out = {}
  for _, h in ipairs(history) do out[#out + 1] = h.w .. '\t' .. h.n .. '\t' .. h.t end
  pcall(function() ctx.storage:write('history.txt', table.concat(out, '\n')) end)
end
local function save_cards()
  local out = {}
  for _, h in ipairs(history) do if cards[h.w] then out[#out + 1] = h.w .. '\t' .. FS.format(cards[h.w]) end end
  pcall(function() ctx.storage:write('cards.txt', table.concat(out, '\n')) end)
end
local function hist_words()
  local t = {}
  for i, h in ipairs(history) do t[i] = h.w end
  return t
end

local function remember(word)
  local n = 0
  for i = #history, 1, -1 do if history[i].w == word then n = history[i].n; table.remove(history, i) end end
  table.insert(history, 1, { w = word, n = n + 1, t = now_sec() })
  while #history > HISTORY_MAX do cards[table.remove(history).w] = nil end
  save_history()
end

-- one word out of My words (and out of the reviews), or all of them
local function forget_word(word)
  for i = #history, 1, -1 do if history[i].w == word then table.remove(history, i) end end
  cards[word] = nil
  save_history(); save_cards()
end
local function clear_history()
  history, cards = {}, {}
  save_history(); save_cards()
end

-- the review queue: words due (soonest first), then new ones (oldest look-up first) up to
-- NEW_PER_DAY a day (review_day.txt: the day and how many new ones it has had)
local function review_day()
  local day = now_sec() // 86400
  local d, n = (read_file('review_day.txt') or ''):match('^(%d+) (%d+)')
  if tonumber(d) ~= day then return day, 0 end
  return day, tonumber(n)
end
local function review_queue()
  local now, due, fresh = now_sec(), {}, {}
  for _, h in ipairs(history) do
    local r = cards[h.w]
    if r and r.due <= now then due[#due + 1] = h.w elseif not r then table.insert(fresh, 1, h.w) end
  end
  table.sort(due, function(a, b) return cards[a].due < cards[b].due end)
  local _, used = review_day()
  for k = 1, math.min(#fresh, math.max(0, NEW_PER_DAY - used)) do due[#due + 1] = fresh[k] end
  return due
end
-- when the next word comes up, or nil
local function next_due()
  local m = nil
  for _, h in ipairs(history) do local r = cards[h.w]; if r and (not m or r.due < m) then m = r.due end end
  return m
end

-- index of the shard whose range may contain `key` (lower-cased): the last shard with lo <= key
local function shard_for(key)
  local shards = dict.shards
  local lo, hi = 1, #shards
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if shards[mid].lo <= key then lo = mid else hi = mid - 1 end
  end
  return lo
end

local function unescape(s)
  return (s:gsub('\\(.)', function(c) if c == 'n' then return '\n' end return c end))
end

-- words starting with `prefix` (case-insensitive), from the shard that covers it and the next
local function suggest(prefix)
  local out = {}
  if prefix == '' or #dict.shards == 0 then return out end
  local key = lower(prefix)
  local i = shard_for(key)
  local done = false
  for k = i, math.min(#dict.shards, i + 1) do
    if done then break end
    each_line(dict.shards[k].file, function(word)
      if lower(word:sub(1, #key)) == key then
        out[#out + 1] = word
        if #out >= MAX_SUGGEST then done = true; return true end
      elseif #out > 0 then
        done = true; return true   -- past the prefix block
      end
      return false
    end)
  end
  return out
end

-- definition of `word`: exact spelling first, else the first case-insensitive match; or nil
local function define(word)
  if #dict.shards == 0 then return nil end
  local key = lower(word)
  local found_w, found_def = nil, nil
  local i = shard_for(key)
  for k = i, math.min(#dict.shards, i + 1) do
    if found_w and found_w == word then break end
    each_line(dict.shards[k].file, function(w, def)
      if w == word then found_w, found_def = w, def; return true end
      if lower(w) == key then
        if not found_w then found_w, found_def = w, def end
      elseif found_w then
        return true   -- past the block of case variants
      end
      return false
    end)
  end
  if found_w then return found_w, unescape(found_def) end
  return nil
end

------------------------------------------------------------------ layout (as in the RSS app)

local function measure(font, s)
  local w = measure_cache[s]
  if w then return w end
  local ok, m = pcall(function() return font:measure(s) end)
  w = (ok and type(m) == 'number') and m or (#s * 11)
  measure_cache[s] = w
  return w
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

local function layout_entry(word, def)
  measure_cache = {}
  local out = {}
  wrap_para(out, word, 'large', W - 24, 0)
  out[#out + 1] = { s = '', f = 'small', h = 10, x = 0 }
  for line in (def .. '\n'):gmatch('([^\n]*)\n') do
    if line:sub(1, 4) == '• ' then wrap_para(out, line, 'medium', W - 40, 16)
    elseif line:sub(1, 4) == '→ ' or line:sub(1, 3) == '“' then wrap_para(out, line, 'medium', W - 48, 24)  -- 3-byte UTF-8 marks
    elseif line ~= '' then wrap_para(out, line, 'medium', W - 24, 0)
    else out[#out + 1] = { s = '', f = 'small', h = 8, x = 0 } end
  end
  entry.word, entry.lines, entry.starts = word, out, { 1 }
  local avail, used = H - TOP - 40, 0
  for i, ln in ipairs(out) do
    if used + ln.h > avail and used > 0 then entry.starts[#entry.starts + 1] = i; used = 0 end
    used = used + ln.h
  end
  entry.pages, entry.page = #entry.starts, 1
end

------------------------------------------------------------------ actions

local function close_editor()
  if editor then pcall(function() editor:close() end); editor = nil end
end

local function open_editor(initial)
  close_editor()
  local inp = ctx.input
  if not inp then note('no ctx.input'); return end
  local ok, ed = pcall(function()
    return inp:edit({
      text = initial or '', title = 'Search',
      on_change = function(c, s) query = s or ''; suggestions = suggest(query); refresh() end,
      on_end = function(c, s, how)
        query = s or ''
        editor = nil
        if (how == 'enter' or how == nil) and query ~= '' then show_entry(query) end   -- define() prefers the exact spelling
        refresh()
      end,
    })
  end)
  if ok and ed ~= nil then editor = ed else note('edit ! ' .. short(ed, 40)) end
end

function show_entry(word)
  local w, def = define(word)
  if not w then
    -- fall back to the first suggestion for the typed text
    local s = suggest(word)
    if s[1] then w, def = define(s[1]) end
  end
  if not w then note('not found: ' .. short(word, 30)); return end
  layout_entry(w, def)
  if screen ~= 'words' then remember(w) end      -- read again from My words: not a new look-up
  close_editor()
  entry.from = screen == 'words' and 'words' or 'search'
  screen = 'entry'
  note('')
end

local function back_to_search()
  screen = 'search'
  suggestions = suggest(query)
  open_editor(query)
end

------------------------------------------------------------------ My words and Review

local words = { top = 1, armed = nil, clear_armed = false }   -- armed: the word whose x was tapped once
local ROW_H = 58
local function words_rows() return math.max(3, (H - TOP - 26 - 70) // ROW_H) end
local rv = nil                    -- the card on screen: { word, lines, shown, queue }

local function open_words()
  close_editor()
  words.armed, words.clear_armed = nil, false
  if words.top > #history then words.top = 1 end
  screen = 'words'
  note('')
end

local function next_card()
  local q = review_queue()
  if #q == 0 then rv = { queue = 0 }; return end
  local word = q[1]
  local w, def = define(word)
  local lines = {}
  measure_cache = {}
  if w then
    for line in (def .. '\n'):gmatch('([^\n]*)\n') do
      if line ~= '' then wrap_para(lines, line, 'medium', W - 24, (line:sub(1, 4) == '• ') and 16 or 0) end
    end
  else
    wrap_para(lines, '(not in ' .. (dict.name ~= '' and dict.name or 'this dictionary') .. ')', 'small', W - 24, 0)
  end
  rv = { word = word, lines = lines, shown = false, queue = #q }
end

local function open_review()
  close_editor()
  screen = 'review'
  next_card()
  note('')
end

-- the four grades at the bottom of a shown card
local GRADES = { 'Again', 'Hard', 'Good', 'Easy' }
local function grade_rect(g)
  local bw = (W - 24 - 3 * 8) // 4
  return 12 + (g - 1) * (bw + 8), H - 120, bw, 70
end

local function grade(g)
  if not rv or not rv.word then return end
  local now = now_sec()
  local was_new = cards[rv.word] == nil
  cards[rv.word] = FS.schedule(cards[rv.word], g, now)
  save_cards()
  if was_new then
    local day, used = review_day()
    pcall(function() ctx.storage:write('review_day.txt', day .. ' ' .. (used + 1)) end)
  end
  next_card()
end

local function word_status(h)
  local r = cards[h.w]
  local s = (h.n > 1 and ('looked up ' .. h.n .. ' times') or 'looked up once')
  if not r then return s .. ' · new' end
  local left = r.due - now_sec()
  return s .. (left <= 0 and ' · due now' or (' · next in ' .. FS.span(left)))
end

------------------------------------------------------------------ drawing

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
end

local function bar_hit(x, n)
  local bw = math.floor((W - 8) / n) - 2
  local i = math.floor((x - 4) / (bw + 2)) + 1
  if i >= 1 and i <= n then return i end
  return nil
end

-- Settings (the box at the top right): which dictionary, and Word of the Day as the lock screen
local SET_Y, SET_H, MAX_SETS = TOP + 40, 56, 6
local function lock_y() return SET_Y + math.min(#sets, MAX_SETS) * SET_H + 40 end
local function lock_on()
  local ok, v = pcall(function() return ctx.lockscreen:is_default() end)
  return ok and v == true
end
local function toggle_lock()
  local L = ctx.lockscreen
  if not L then note('no app lock screen here'); return end
  if lock_on() then pcall(function() L:clear_default() end); note('lock screen off')
  else pcall(function() L:set_default() end); note('lock screen: word of the day') end
end
-- the dictionaries the lock screen can use (those in the app's folder) and the one it uses
local function lock_sets()
  local out = {}
  for _, s in ipairs(sets) do if s.source == 'storage' then out[#out + 1] = s end end
  return out
end
local function lock_set()
  local want, list = (storage_read('lock_dict.txt') or ''):match('^([^\n]*)'), lock_sets()
  for k, s in ipairs(list) do if s.prefix == want then return s, k, list end end
  return list[1], 1, list
end
-- how often the lock screen shows a new word, in hours (wotd_every.txt)
local EVERY = { 24, 12, 6, 3, 1 }
local function lock_every()
  local n = tonumber((storage_read('wotd_every.txt') or ''):match('%d+'))
  for k, h in ipairs(EVERY) do if h == n then return h, k end end
  return 24, 1
end
local function every_label(h) return h == 24 and 'a new word every day' or h == 1 and 'a new word every hour' or ('a new word every ' .. h .. ' hours') end
local function next_every()
  local _h, k = lock_every()
  local nxt = EVERY[k % #EVERY + 1]
  pcall(function() ctx.storage:write('wotd_every.txt', tostring(nxt)) end)
  note(every_label(nxt))
end
local function next_lock_set()
  local _s, k, list = lock_set()
  local nxt = list[k % math.max(1, #list) + 1]
  if nxt then pcall(function() ctx.storage:write('lock_dict.txt', nxt.prefix) end); note('word of the day from ' .. (nxt.name or '')) end
end

local function draw_search(gg)
  local F = ctx.fonts
  gg:text(12, 10, dict.name ~= '' and short(dict.name, 16) or 'Dictionary', { font = F and F.medium })
  gg:rect(W - 220, 6, 102, 30); gg:text(W - 206, 12, 'My words', { font = F and F.small })
  gg:rect(W - 110, 6, 98, 30); gg:text(W - 96, 12, 'Settings', { font = F and F.small })
  gg:text(12, 36, dict.words .. ' words (' .. dict.source .. ')' .. (status ~= '' and ('  ' .. status) or ''), { font = F and F.small })
  gg:rect(12, 62, W - 24, 40)
  gg:text(24, 70, query ~= '' and query or 'type a word…', { font = F and F.medium })
  local list = #suggestions > 0 and suggestions or (query == '' and hist_words() or {})
  local label = #suggestions > 0 and '' or (query == '' and #history > 0 and 'recent' or (query ~= '' and 'no match' or ''))
  if label ~= '' then gg:text(12, 110, label, { font = F and F.small }) end
  local y = 132
  local limit = editor and math.floor((H - KB_H - y) / 32) or 16
  for i = 1, math.min(#list, limit) do
    gg:text(24, y, short(list[i], 36), { font = F and F.medium })
    y = y + 32
  end
  if not editor then gg:text(12, H - 30, 'tap the box to type', { font = F and F.small }) end
end

local function draw_settings(gg)
  local F = ctx.fonts
  bar(gg, { 'Back' })
  gg:text(12, TOP + 12, 'Dictionary', { font = F and F.small })
  for i = 1, math.min(#sets, MAX_SETS) do
    local y = SET_Y + (i - 1) * SET_H
    gg:rect(12, y, W - 24, SET_H - 8, { line_width = i == set_index and 3 or 1 })
    gg:text(24, y + 12, short(sets[i].name or '', 34) .. (i == set_index and '  (in use)' or ''), { font = F and F.medium })
  end
  local y = lock_y()
  gg:text(12, y - 28, 'Word of the Day on the lock screen', { font = F and F.small })
  if not ctx.lockscreen then
    gg:text(12, y, 'This firmware has no app lock screen.', { font = F and F.small })
  else
    gg:rect(12, y, W - 24, SET_H - 8, { line_width = lock_on() and 3 or 1 })
    gg:text(24, y + 12, lock_on() and 'on   (tap to turn off)' or 'off   (tap to turn on)', { font = F and F.medium })
    local ls, _k, list = lock_set()
    if ls then
      gg:rect(12, y + SET_H, W - 24, SET_H - 8)
      gg:text(24, y + SET_H + 12, 'from ' .. short(ls.name or '', 22) .. (#list > 1 and '   (tap to change)' or ''), { font = F and F.medium })
      gg:rect(12, y + 2 * SET_H, W - 24, SET_H - 8)
      gg:text(24, y + 2 * SET_H + 12, every_label(lock_every()), { font = F and F.medium })
      gg:text(12, y + 3 * SET_H, 'Tap a row to change it.', { font = F and F.small })
    else
      gg:text(12, y + SET_H, 'It uses dictionaries copied into the app folder.', { font = F and F.small })
    end
  end
  if status ~= '' then gg:text(12, H - 30, short(status, 46), { font = F and F.small }) end
end

local function draw_entry(gg)
  local F = ctx.fonts
  bar(gg, { 'Back', 'Prev', 'Next', entry.page .. '/' .. entry.pages })
  local first = entry.starts[entry.page] or 1
  local last = entry.starts[entry.page + 1] and (entry.starts[entry.page + 1] - 1) or #entry.lines
  local y = TOP + 4
  for i = first, last do
    local ln = entry.lines[i]
    if ln.s ~= '' then gg:text(12 + ln.x, y, ln.s, { font = F and F[ln.f] }) end
    y = y + ln.h
  end
end

local function draw_words(gg)
  local F = ctx.fonts
  local n = #review_queue()
  bar(gg, { 'Back', 'Prev', 'Next', n > 0 and ('Review ' .. n) or 'Review' })
  local rows = words_rows()
  local head = #history == 0 and 'No words yet: look some up.'
    or (#history .. (#history == 1 and ' word' or ' words') .. (#history > rows and ('  ' .. words.top .. '-' .. math.min(#history, words.top + rows - 1)) or ''))
  gg:text(8, TOP + 2, head, { font = F and F.small })
  local y = TOP + 26
  for i = words.top, math.min(#history, words.top + rows - 1) do
    local h = history[i]
    gg:text(16, y, short(h.w, 30), { font = F and F.medium })
    gg:text(16, y + 28, words.armed == h.w and 'tap x again to remove it' or word_status(h), { font = F and F.small })
    gg:rect(W - 56, y + 6, 40, 40, { line_width = words.armed == h.w and 3 or 1 })
    gg:text(W - 42, y + 14, 'x', { font = F and F.medium })
    gg:line(16, y + ROW_H - 4, W - 16, y + ROW_H - 4)
    y = y + ROW_H
  end
  if #history > 0 then
    gg:rect(12, H - 66, W - 24, 44, { line_width = words.clear_armed and 3 or 1 })
    gg:text(24, H - 56, words.clear_armed and ('Tap again to remove all ' .. #history .. ' words') or 'Clear history', { font = F and F.medium })
  end
  if status ~= '' then gg:text(12, H - 18, short(status, 46), { font = F and F.small }) end
end

local function draw_review(gg)
  local F = ctx.fonts
  bar(gg, { 'Back' })
  if not rv or not rv.word then
    local nd = next_due()
    gg:text(16, TOP + 40, 'Nothing to review now.', { font = F and F.large })
    local why = #history == 0 and 'Words you look up come here.'
      or nd and ('The next word comes in ' .. FS.span(math.max(60, nd - now_sec())) .. '.')
      or ('New words: up to ' .. NEW_PER_DAY .. ' a day; more tomorrow.')
    gg:text(16, TOP + 84, why, { font = F and F.medium })
    return
  end
  gg:text(W - 140, 14, rv.queue .. ' left', { font = F and F.small })
  gg:text(16, TOP + 24, short(rv.word, 26), { font = F and F.large })
  if not rv.shown then
    gg:rect(12, H - 120, W - 24, 70)
    gg:text(W // 2 - 30, H - 98, 'Show', { font = F and F.medium })
    gg:text(16, TOP + 70, 'Do you remember what it means?', { font = F and F.small })
    return
  end
  local y = TOP + 70
  for _, ln in ipairs(rv.lines) do
    if y + ln.h > H - 130 then gg:text(16, y, '…', { font = F and F.small }); break end
    gg:text(16 + ln.x, y, ln.s, { font = F and F[ln.f] })
    y = y + ln.h
  end
  local now = now_sec()
  for g, label in ipairs(GRADES) do
    local x, gy, bw, bh = grade_rect(g)
    gg:rect(x, gy, bw, bh)
    gg:text(x + 10, gy + 10, label, { font = F and F.medium })
    gg:text(x + 10, gy + 40, FS.span(math.max(60, FS.schedule(cards[rv.word], g, now).due - now)), { font = F and F.small })
  end
end

local function draw_nodata(gg)
  local F = ctx.fonts
  gg:text(12, 20, 'Dictionary', { font = F and F.large })
  local lines = {
    'No dictionary files yet.',
    '',
    'Put the reader in USB mode and copy a converted',
    'dictionary (a ready-made zip from the release, or',
    '  python stardict2shards.py <StarDict folder> out/ --prefix xx)',
    'into the app\'s folder on the SD card:',
    '  ' .. ((ctx.files and type(ctx.files.path) == 'string' and ctx.files.path ~= '') and ctx.files.path or 'XTApps/dict/files'),
    'then leave USB mode and open this app again.',
    '',
    'Tap to re-check.',
  }
  local y = 70
  for _, s in ipairs(lines) do gg:text(12, y, s, { font = F and F.small }); y = y + 24 end
  if status ~= '' then gg:text(12, y + 10, status, { font = F and F.small }) end
end

local function draw_impl(gg)
  gg:clear(0)
  if screen == 'search' then draw_search(gg)
  elseif screen == 'entry' then draw_entry(gg)
  elseif screen == 'settings' then draw_settings(gg)
  elseif screen == 'words' then draw_words(gg)
  elseif screen == 'review' then draw_review(gg)
  else draw_nodata(gg) end
  if ERR then gg:text(6, H - 60, short('ERR ' .. ERR, 46), { font = ctx.fonts and ctx.fonts.small }) end
end

function on_draw(c, gg)
  G = gg or G
  if not G then return end
  local ok, e = pcall(draw_impl, G)
  if not ok then pcall(function() G:text(6, H - 90, short('draw ERR ' .. tostring(e), 46)) end) end   -- this frame only
end

------------------------------------------------------------------ input

local function page_entry(delta)
  local p = entry.page + delta
  if p >= 1 and p <= entry.pages then entry.page = p end
end
local function page_words(delta)
  local t = words.top + delta * words_rows()
  if t >= 1 and t <= #history then words.top = t end
  words.armed, words.clear_armed = nil, false
end
local function entry_back() if entry.from == 'words' then screen = 'words' else back_to_search() end end

local function tap(x, y)
  if screen == 'nodata' then
    if discover_sets() and load_dict() then screen = 'search'; open_editor('') else note('still no shards.tsv') end
  elseif screen == 'search' then
    if y < 40 and x >= W - 110 then close_editor(); note(''); screen = 'settings'; return end
    if y < 40 and x >= W - 220 then open_words(); return end
    if y >= 62 and y < 102 then open_editor(query); return end
    local list = #suggestions > 0 and suggestions or (query == '' and hist_words() or {})
    local i = math.floor((y - 132) / 32) + 1
    if y >= 132 and list[i] then show_entry(list[i]) end
  elseif screen == 'settings' then
    if y < 46 then back_to_search(); return end
    local i = math.floor((y - SET_Y) / SET_H) + 1
    if y >= SET_Y and i <= math.min(#sets, MAX_SETS) then select_dict(i); return end
    if y >= lock_y() and y < lock_y() + SET_H - 8 then toggle_lock()
    elseif y >= lock_y() + SET_H and y < lock_y() + 2 * SET_H - 8 and ctx.lockscreen then next_lock_set()
    elseif y >= lock_y() + 2 * SET_H and y < lock_y() + 3 * SET_H - 8 and ctx.lockscreen and lock_set() then next_every() end
  elseif screen == 'entry' then
    if y < 46 then
      local b = bar_hit(x, 4)
      if b == 1 then entry_back() elseif b == 2 then page_entry(-1) elseif b == 3 then page_entry(1) end
      return
    end
    if x < W / 3 then page_entry(-1) else page_entry(1) end
  elseif screen == 'words' then
    if y < 46 then
      local b = bar_hit(x, 4)
      if b == 1 then back_to_search() elseif b == 2 then page_words(-1) elseif b == 3 then page_words(1)
      elseif b == 4 then open_review() end
      return
    end
    if #history > 0 and y >= H - 66 and y < H - 22 then
      if words.clear_armed then clear_history(); words.clear_armed, words.top = false, 1; note('history cleared')
      else words.clear_armed, words.armed = true, nil end
      return
    end
    words.clear_armed = false
    local i = words.top + (y - (TOP + 26)) // ROW_H
    local h = y >= TOP + 26 and i < words.top + words_rows() and history[i]
    if not h then words.armed = nil; return end
    if x >= W - 64 then                            -- its x: once arms, again removes
      if words.armed == h.w then forget_word(h.w); words.armed = nil; note('removed: ' .. short(h.w, 30))
        if words.top > #history then words.top = math.max(1, words.top - words_rows()) end
      else words.armed = h.w end
      return
    end
    words.armed = nil
    show_entry(h.w)
  elseif screen == 'review' then
    if y < 46 then screen = 'words'; return end
    if not rv or not rv.word then return end
    if not rv.shown then
      if y >= H - 120 and y < H - 50 then rv.shown = true end
      return
    end
    for g = 1, 4 do
      local gx, gy, bw, bh = grade_rect(g)
      if x >= gx and x < gx + bw and y >= gy and y < gy + bh then grade(g); return end
    end
  end
end

function on_input(c, ev)
  ERR = nil   -- a new interaction clears the last error; a new one sets it again
  if type(ev) == 'table' and ev.type == 'key' and ev.key == 'back' and (screen == 'search' or screen == 'nodata') then
    return false                                   -- not handled: the host asks whether to leave the app
  end
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    if ev.type == 'pointer' then
      if ev.phase ~= 'up' then return end
      local g = ev.gesture
      if screen == 'entry' and (g == 'swipe_left' or g == 'swipe_up') then page_entry(1)
      elseif screen == 'entry' and (g == 'swipe_right' or g == 'swipe_down') then page_entry(-1)
      elseif screen == 'words' and (g == 'swipe_left' or g == 'swipe_up') then page_words(1)
      elseif screen == 'words' and (g == 'swipe_right' or g == 'swipe_down') then page_words(-1)
      elseif g == nil or g == 'tap' then tap(ev.x or 0, ev.y or 0) end
    elseif ev.type == 'key' and key_accepted(ev) then
      local k = ev.key
      if screen == 'settings' and k == 'back' then back_to_search()
      elseif screen == 'words' then
        if k == 'back' then back_to_search()
        elseif k == 'right' or k == 'down' then page_words(1)
        elseif k == 'left' or k == 'up' then page_words(-1) end
      elseif screen == 'review' then
        if k == 'back' then screen = 'words' end
      elseif screen == 'entry' then
        if k == 'back' then entry_back()
        elseif k == 'right' or k == 'down' then page_entry(1)
        elseif k == 'left' or k == 'up' then page_entry(-1) end
      end
    end
  end)
  if not ok then ERR = tostring(e) end
  refresh()
  return true
end

function on_load(c)
  load_history()
  if discover_sets() then
    local want = ctx.state and ctx.state.dict
    for i, s in ipairs(sets) do if s.prefix == want then set_index = i end end
  end
  if #sets > 0 and load_dict() then screen = 'search'; open_editor('') else screen = 'nodata' end
end

function on_leave() close_editor() end
