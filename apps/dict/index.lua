-- Dictionary for XTOS Licorice, API 2.9. Looks words up in a StarDict dictionary that
-- tools/stardict2shards.py converted into sorted text shards, copied over USB into this app's
-- storage folder on the SD card (XTApps/dict/files/): info.txt, shards.tsv, d000.txt ...
--
-- Search screen: the firmware keyboard docked at the bottom (ctx.input:edit), suggestions above
-- it as you type; Done or a tap on a suggestion opens the entry, laid out and paged like RSS.
-- Every ctx.* function is a method on this API: colon calls everywhere.

local W, H, TOP = 480, 800, 56
local KB_H = 436                 -- the docked keyboard's height on this device
local MAX_SUGGEST = 7
local HISTORY_MAX = 30

local G, ERR = nil, nil
local screen = 'search'           -- search | entry | nodata
local status = ''
local dict = { name = '', words = 0, shards = {}, source = '' }   -- shards: { {file, lo, hi} ... }
local query, suggestions = '', {}
local editor = nil
local cache = { file = nil, text = nil }
local history = {}
local entry = { word = '', lines = {}, starts = { 1 }, page = 1, pages = 1 }
local measure_cache = {}

local function short(s, n) s = tostring(s); if #s > n then return s:sub(1, n - 1) .. '~' end return s end
local function note(s) status = tostring(s or '') end
local function refresh() pcall(function() ctx.invalidate() end) end
local function lower(s) return (s:gsub('%u', string.lower)) end   -- ASCII fold; the shard order is ASCII case-insensitive

------------------------------------------------------------------ data sources
-- Two places the converted dictionary can live:
--   storage: files copied over USB into XTApps/dict/files/ (whole-file reads, ctx.storage)
--   package: the data section of this .xtapp (built by build_dict.py), read line by line through
--            ctx.package:open_text, the seekable reader API 0.8 knows as ctx.data

local function storage_read(name)
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
  local ok, names = pcall(function() return ctx.storage:list() end)
  if ok and type(names) == 'table' then
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
  return #dict.shards > 0
end

local function next_dict()
  if #sets < 2 then return end
  set_index = set_index % #sets + 1
  load_dict()
  query, suggestions = '', {}
end
local read_file = storage_read

local function load_history()
  history = {}
  local s = read_file('history.txt')
  if s then for w in (s .. '\n'):gmatch('([^\n]*)\n') do if w ~= '' then history[#history + 1] = w end end end
end

local function remember(word)
  for i = #history, 1, -1 do if history[i] == word then table.remove(history, i) end end
  table.insert(history, 1, word)
  while #history > HISTORY_MAX do table.remove(history) end
  pcall(function() ctx.storage:write('history.txt', table.concat(history, '\n')) end)
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
  remember(w)
  close_editor()
  screen = 'entry'
  note('')
end

local function back_to_search()
  screen = 'search'
  suggestions = suggest(query)
  open_editor(query)
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

local function draw_search(gg)
  local F = ctx.fonts
  gg:text(12, 10, dict.name ~= '' and short(dict.name, 30) or 'Dictionary', { font = F and F.medium })
  if #sets > 1 then gg:rect(W - 110, 6, 98, 30); gg:text(W - 100, 12, 'dict ' .. set_index .. '/' .. #sets, { font = F and F.small }) end
  gg:text(12, 36, dict.words .. ' words (' .. dict.source .. ')' .. (status ~= '' and ('  ' .. status) or ''), { font = F and F.small })
  gg:rect(12, 62, W - 24, 40)
  gg:text(24, 70, query ~= '' and query or 'type a word…', { font = F and F.medium })
  local list = #suggestions > 0 and suggestions or (query == '' and history or {})
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

local function draw_nodata(gg)
  local F = ctx.fonts
  gg:text(12, 20, 'Dictionary', { font = F and F.large })
  local lines = {
    'No dictionary files yet.',
    '',
    'Put the reader in USB mode and copy a converted',
    'dictionary (a ready-made zip from the release, or',
    '  python stardict2shards.py <StarDict folder> out/ --prefix xx)',
    'into the SD card folder',
    '  XTApps/' .. (ctx.files and tostring(ctx.files.path or ''):match('([^/]+)$') or 'dict') .. '/files/',
    'then leave USB mode and open this app again.',
    'Do not uninstall the app: that deletes the folder.',
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

local function tap(x, y)
  if screen == 'nodata' then
    if discover_sets() and load_dict() then screen = 'search'; open_editor('') else note('still no shards.tsv') end
  elseif screen == 'search' then
    if y < 40 and x >= W - 110 and #sets > 1 then next_dict(); open_editor(''); return end
    if y >= 62 and y < 102 then open_editor(query); return end
    local list = #suggestions > 0 and suggestions or (query == '' and history or {})
    local i = math.floor((y - 132) / 32) + 1
    if y >= 132 and list[i] then show_entry(list[i]) end
  elseif screen == 'entry' then
    if y < 46 then
      local b = bar_hit(x, 4)
      if b == 1 then back_to_search() elseif b == 2 then page_entry(-1) elseif b == 3 then page_entry(1) end
      return
    end
    if x < W / 3 then page_entry(-1) else page_entry(1) end
  end
end

function on_input(c, ev)
  ERR = nil   -- a new interaction clears the last error; a new one sets it again
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    if ev.type == 'pointer' then
      if ev.phase ~= 'up' then return end
      local g = ev.gesture
      if screen == 'entry' and (g == 'swipe_left' or g == 'swipe_up') then page_entry(1)
      elseif screen == 'entry' and (g == 'swipe_right' or g == 'swipe_down') then page_entry(-1)
      elseif g == nil or g == 'tap' then tap(ev.x or 0, ev.y or 0) end
    elseif ev.type == 'key' then
      local k = ev.key
      if screen == 'entry' then
        if k == 'back' then back_to_search()
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
