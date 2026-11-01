-- Word Hive for XTOS Licorice, API 2.0 (uses tools/gamekit).
--
-- A new hive of seven letters every day: make words of four letters or more that use the middle
-- letter; letters may repeat. A four-letter word scores 1, a longer one a point a letter, a
-- pangram (all seven letters) 7 more. The puzzles come from make_puzzles.py (one a line in the
-- package's data section: the middle letter, the six others, then the answers); day N from
-- 1 November 2026 plays line N, and the list starts over after the last one. Earlier days can be
-- played too; the words found are kept per day. Hints counts the words still to find by first
-- letter and length; Yesterday shows the answers of the day before.

local W, H = kit.W, kit.H
local HX, HY, R = 240, 380, 62                  -- hive centre, hexagon radius
local NB = math.floor(R * math.sqrt(3) + 10)     -- distance between neighbouring hexagons
local BTN_Y, BTN_H = 584, 56
local FOUND_Y = 652
local BOT_Y, BOT_H = 742, 50
local MIN_LEN = 4

local RANKS = {
  { 0, 'Beginner' }, { 0.02, 'Started' }, { 0.05, 'Moving up' }, { 0.08, 'Good' }, { 0.15, 'Solid' },
  { 0.25, 'Nice' }, { 0.40, 'Great' }, { 0.50, 'Amazing' }, { 0.70, 'Brilliant' }, { 1, 'Queen bee' },
}

local today, pday = 0, 0            -- today's day number; the day whose puzzle is open
local puz = nil                     -- { no, centre, outer = {6}, answers = {list}, set, max }
local found_by_day = {}             -- day -> { words in the order found }
local word = ''                     -- the letters tapped so far
local msg = nil
local view = 'play'                 -- 'play' | 'list' | 'hints'
local list_rows, list_title, list_page = {}, '', 1
local ERR = nil

------------------------------------------------------------------ days

local function days_from_civil(y, m, d)
  y = m <= 2 and y - 1 or y
  local era = (y >= 0 and y or y - 399) // 400
  local yoe = y - era * 400
  local doy = (153 * (m > 2 and m - 3 or m + 9) + 2) // 5 + d - 1
  local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
  return era * 146097 + doe - 719468
end
local START = days_from_civil(2026, 11, 1)

local function civil(z)
  z = z + 719468
  local era = (z >= 0 and z or z - 146096) // 146097
  local doe = z - era * 146097
  local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
  local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
  local mp = (5 * doy + 2) // 153
  local d = doy - (153 * mp + 2) // 5 + 1
  local m = mp < 10 and mp + 3 or mp - 9
  return yoe + era * 400 + (m <= 2 and 1 or 0), m, d
end

local MONTHS = { 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' }
local WDAYS = { 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat' }
local function date_label(day)
  local _y, m, d = civil(day)
  return WDAYS[(day + 4) % 7 + 1] .. ' ' .. d .. ' ' .. MONTHS[m]
end

-- today's number in local time: the offset from the wall clock, rounded to a quarter hour
local function local_day()
  local ok, t = pcall(function() return ctx.clock:now() end)
  if not ok or type(t) ~= 'table' or not tonumber(t.epoch_sec) then return START end
  local e = math.floor(tonumber(t.epoch_sec))
  if tonumber(t.hour) then
    local wall = tonumber(t.hour) * 3600 + (tonumber(t.minute) or 0) * 60 + (tonumber(t.second) or 0)
    local off = (wall - e % 86400) % 86400
    if off > 14 * 3600 then off = off - 86400 end
    off = math.floor(off / 900 + 0.5) * 900
    return (e + off) // 86400
  end
  return e // 86400
end

------------------------------------------------------------------ puzzles

local count = nil
local function open_data()
  local P = ctx.package
  if not P then return nil end
  local ok, r = pcall(function() return P:open_text('puzzles.txt', { max_bytes = 2000000, max_line_bytes = 1024 }) end)
  if not ok or r == nil or type(r) == 'string' then return nil end
  return r
end

local function read_line(n)          -- n from 1; also counts the lines once
  local r = open_data()
  if not r then return nil end
  local line, k = nil, 0
  while true do
    local ok, l = pcall(function() return r:read_line() end)
    if not ok or l == nil then break end
    if l:match('^%l%l%l%l%l%l%l ') then
      k = k + 1
      if k == n then line = l; if count then break end end
    end
  end
  pcall(function() r:close() end)
  if not count or k > count then count = math.max(count or 0, k) end
  return line
end

local function score_of(w, p)
  if #w == MIN_LEN then return 1 end
  local s = #w
  local seen, n = {}, 0
  for ch in w:gmatch('.') do if not seen[ch] then seen[ch] = true; n = n + 1 end end
  if n == 7 then s = s + 7 end
  return s
end

local function is_pangram(w)
  local seen, n = {}, 0
  for ch in w:gmatch('.') do if not seen[ch] then seen[ch] = true; n = n + 1 end end
  return n == 7
end

local function puzzle_no(day)
  if not count then read_line(1) end
  if not count or count == 0 then return nil end
  return (day - START) % count + 1
end

local function load_puzzle(day)
  local no = puzzle_no(day)
  local line = no and read_line(no)
  if not line then return nil end
  local p = { no = no, centre = line:sub(1, 1), outer = {}, answers = {}, set = {}, max = 0, day = day }
  for k = 2, 7 do p.outer[#p.outer + 1] = line:sub(k, k) end
  for w in line:sub(9):gmatch('%l+') do
    p.answers[#p.answers + 1] = w
    p.set[w] = true
    p.max = p.max + score_of(w, p)
  end
  return p
end

local function found()
  local f = found_by_day[pday]
  if not f then f = {}; found_by_day[pday] = f end
  return f
end

local function score()
  local s = 0
  for _k, w in ipairs(found()) do s = s + score_of(w, puz) end
  return s
end

local function rank_index(s)
  local k = 1
  for i, r in ipairs(RANKS) do
    if puz.max > 0 and s >= math.ceil(r[1] * puz.max) then k = i end
  end
  return k
end

------------------------------------------------------------------ storage

local function save()
  local t, days = {}, {}
  for d, ws in pairs(found_by_day) do if #ws > 0 then days[#days + 1] = d end end
  table.sort(days)
  for k = math.max(1, #days - 400), #days do t[#t + 1] = days[k] .. '\t' .. table.concat(found_by_day[days[k]], ' ') end
  kit.write('found.txt', table.concat(t, '\n'))
end

local function load_found()
  for d, ws in (kit.read('found.txt') or ''):gmatch('(%-?%d+)\t([^\n]*)') do
    local t = {}
    for w in ws:gmatch('%l+') do t[#t + 1] = w end
    found_by_day[tonumber(d)] = t
  end
end

------------------------------------------------------------------ play

local seed = 12345
local function rnd(n)
  seed = (seed * 1103515245 + 12345) % 2147483648
  return seed // 65536 % n + 1
end

local function shuffle()
  local o = puz.outer
  for k = #o, 2, -1 do
    local j = rnd(k)
    o[k], o[j] = o[j], o[k]
  end
end

local function open_day(day)
  local p = load_puzzle(day)
  if not p then ERR = 'no puzzles in the package'; return end
  puz, pday, word, msg, view = p, day, '', nil, 'play'
  seed = (day * 7919) % 2147483648 + 1
  shuffle()
end

local function submit()
  local w = word
  word = ''
  if #w == 0 then return end
  if #w < MIN_LEN then msg = 'Too short'; return end
  if not w:find(puz.centre, 1, true) then msg = 'Must use the middle letter ' .. puz.centre:upper(); return end
  for _k, f in ipairs(found()) do if f == w then msg = 'Already found'; return end end
  if not puz.set[w] then msg = 'Not in the word list'; return end
  local before = rank_index(score())
  local t = found()
  t[#t + 1] = w
  local pts = score_of(w, puz)
  local after = rank_index(score())
  if is_pangram(w) then msg = 'Pangram! +' .. pts
  elseif #w >= 7 then msg = 'Excellent! +' .. pts
  elseif #w >= 5 then msg = 'Nice! +' .. pts
  else msg = 'Good! +' .. pts end
  if #t == #puz.answers then msg = 'Every word found!' elseif after > before then msg = msg .. '   Now: ' .. RANKS[after][2] end
  kit.moved()
  save()
end

local function hex_centres()
  local t = { { HX, HY } }
  for k = 0, 5 do
    local a = math.rad(-90 + 60 * k)
    t[#t + 1] = { HX + math.floor(NB * math.cos(a) + 0.5), HY + math.floor(NB * math.sin(a) + 0.5) }
  end
  return t
end
local CENTRES = hex_centres()

local function letter_at(i) return i == 1 and puz.centre or puz.outer[i - 1] end

------------------------------------------------------------------ lists

local function sorted(t)
  local s = {}
  for k, v in ipairs(t) do s[k] = v end
  table.sort(s)
  return s
end

-- rows of a list page: a header string, or up to three words
local function add_words(rows, words)
  local row = {}
  for _k, w in ipairs(words) do
    row[#row + 1] = is_pangram(w) and (w .. ' *') or w
    if #row == 3 then rows[#rows + 1] = row; row = {} end
  end
  if #row > 0 then rows[#rows + 1] = row end
end

local function show_found()
  list_rows = {}
  add_words(list_rows, sorted(found()))
  if #found() == 0 then list_rows[1] = 'No words yet.' end
  list_title, list_page, view = 'Found ' .. #found() .. ' of ' .. #puz.answers, 1, 'list'
end

local function show_yesterday()
  local p = load_puzzle(pday - 1)
  if not p then return end
  local mine = {}
  for _k, w in ipairs(found_by_day[pday - 1] or {}) do mine[w] = true end
  local got, missed = {}, {}
  for _k, w in ipairs(p.answers) do if mine[w] then got[#got + 1] = w else missed[#missed + 1] = w end end
  list_rows = { 'Letters ' .. p.centre:upper() .. ' + ' .. table.concat(p.outer):upper() .. '   (* = pangram)' }
  list_rows[#list_rows + 1] = 'You found ' .. #got
  add_words(list_rows, got)
  list_rows[#list_rows + 1] = 'Missed ' .. #missed
  add_words(list_rows, missed)
  list_title, list_page, view = 'Answers for ' .. date_label(pday - 1), 1, 'list'
end

local ROWS_PER_PAGE = 20
local function pages() return math.max(1, (#list_rows + ROWS_PER_PAGE - 1) // ROWS_PER_PAGE) end

------------------------------------------------------------------ hints

-- words still to find: by first letter and length, and by their first two letters
local function hint_data()
  local mine = {}
  for _k, w in ipairs(found()) do mine[w] = true end
  local grid, lens, twos, left, pts, pang = {}, {}, {}, 0, 0, 0
  for _k, w in ipairs(puz.answers) do
    if not mine[w] then
      local f, n = w:sub(1, 1), math.min(#w, 10)
      grid[f] = grid[f] or {}
      grid[f][n] = (grid[f][n] or 0) + 1
      lens[n] = true
      local two = w:sub(1, 2)
      twos[two] = (twos[two] or 0) + 1
      left = left + 1
      pts = pts + score_of(w, puz)
      if is_pangram(w) then pang = pang + 1 end
    end
  end
  return grid, lens, twos, left, pts, pang
end

------------------------------------------------------------------ drawing

local function hexagon(gg, cx, cy, r, lw)
  local pts = {}
  for k = 0, 6 do
    local a = math.rad(60 * k)
    pts[#pts + 1] = { cx + math.floor(r * math.cos(a) + 0.5), cy + math.floor(r * math.sin(a) + 0.5) }
  end
  for k = 1, 6 do gg:line(pts[k][1], pts[k][2], pts[k + 1][1], pts[k + 1][2], { line_width = lw }) end
end

-- larger letters for the hive where the host has sized fonts (API 2.3), else the large system font
local function big_font()
  local ok, f = pcall(function() return ctx.fonts:size(40, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ') end)
  if ok and type(f) == 'table' and f.line_height then return f, tonumber(f.line_height) end
  return kit.font('large'), kit.line_h('large')
end

local function header(gg, title)
  gg:text(12, 12, title, { font = kit.font('large') })
  gg:line(0, 90, W, 90)
end

local function draw_play(gg)
  local s = score()
  local rk = rank_index(s)
  local info = date_label(pday) .. (pday == today and '' or ' (earlier)') .. '   ' .. RANKS[rk][2] .. '  ' .. s .. ' pts'
  gg:text(12, 52, kit.short(info, 46), { font = kit.font('small') })
  -- the ranks as a row of marks, the reached ones filled
  local x0, x1, y = 24, W - 24, 112
  gg:line(x0, y, x1, y)
  for i = 1, #RANKS do
    local x = x0 + (i - 1) * (x1 - x0) // (#RANKS - 1)
    if i <= rk then gg:circle(x, y, 7, { fill = true }) else gg:circle(x, y, 7, { fill = true, color = 0 }); gg:circle(x, y, 7) end
  end
  local big, big_h = big_font()
  local shown = word:upper()
  local tw = kit.width(big, shown)
  gg:text((W - tw) // 2, 170 - big_h, shown, { font = big })
  gg:line(W // 2 - 90, 172, W // 2 + 90, 172)
  if msg then
    local f = kit.font('small')
    gg:text((W - kit.width(f, msg)) // 2, 180, msg, { font = f })
  end
  for i, c in ipairs(CENTRES) do
    hexagon(gg, c[1], c[2], R, i == 1 and 5 or 2)
    local l = letter_at(i):upper()
    gg:text(c[1] - kit.width(big, l) // 2, c[2] - big_h // 2, l, { font = big })
  end
  local labels = { 'Delete', 'Shuffle', 'Enter' }
  local bw = (W - 24 - 2 * 10) // 3
  for k, l in ipairs(labels) do kit.button(gg, 12 + (k - 1) * (bw + 10), BTN_Y, bw, BTN_H, l) end
  local f = found()
  local small = kit.font('small')
  gg:text(12, FOUND_Y, 'Found ' .. #f .. ' of ' .. #puz.answers .. '  (tap for the list)', { font = small })
  local words = sorted(f)
  local lines = kit.wrap(#words > 0 and table.concat(words, ', ') or 'Tap letters, then Enter.', 'small', W - 24)
  for k = 1, math.min(3, #lines) do
    local l = lines[k]
    if k == 3 and #lines > 3 then l = kit.short(l, 40) .. ' ...' end
    gg:text(12, FOUND_Y + k * 22, l, { font = small })
  end
  local bl = { 'Hints', 'Yesterday', 'Menu' }
  for k, l in ipairs(bl) do kit.button(gg, 12 + (k - 1) * (bw + 10), BOT_Y, bw, BOT_H, l) end
end

local function draw_list(gg)
  gg:text(12, 52, kit.short(list_title .. (pages() > 1 and ('   page ' .. list_page .. '/' .. pages()) or ''), 46), { font = kit.font('small') })
  local f, y = kit.font('medium'), 104
  local first = (list_page - 1) * ROWS_PER_PAGE + 1
  for k = first, math.min(#list_rows, first + ROWS_PER_PAGE - 1) do
    local r = list_rows[k]
    if type(r) == 'string' then
      gg:text(12, y, kit.short(r, 40), { font = kit.font('small') })
      gg:line(12, y + 24, W - 12, y + 24)
    else
      for j, w in ipairs(r) do gg:text(12 + (j - 1) * 156, y, kit.short(w, 14), { font = f }) end
    end
    y = y + 30
  end
  local bw = (W - 24 - 2 * 10) // 3
  kit.button(gg, 12, BOT_Y, bw, BOT_H, 'Back')
  if pages() > 1 then
    kit.button(gg, 12 + bw + 10, BOT_Y, bw, BOT_H, 'Prev')
    kit.button(gg, 12 + 2 * (bw + 10), BOT_Y, bw, BOT_H, 'Next')
  end
end

local function draw_hints(gg)
  local grid, lens, twos, left, pts, pang = hint_data()
  local small, med = kit.font('small'), kit.font('medium')
  gg:text(12, 52, 'Still to find: ' .. left .. ' words, ' .. pts .. ' pts, ' .. pang .. ' pangram' .. (pang == 1 and '' or 's'), { font = small })
  local cols = {}
  for n = MIN_LEN, 10 do if lens[n] then cols[#cols + 1] = n end end
  local cw = math.min(54, (W - 70) // math.max(1, #cols + 1))
  local y = 110
  gg:text(12, y, 'Words by first letter and length', { font = small })
  y = y + 32
  for j, n in ipairs(cols) do gg:text(60 + (j - 1) * cw, y, n == 10 and '10+' or tostring(n), { font = med }) end
  gg:text(60 + #cols * cw, y, 'all', { font = med })
  gg:line(12, y + 28, W - 12, y + 28)
  y = y + 36
  local letters = { puz.centre }
  for _k, l in ipairs(puz.outer) do letters[#letters + 1] = l end
  table.sort(letters)
  for _k, l in ipairs(letters) do
    if grid[l] then
      gg:text(16, y, l:upper(), { font = med })
      local all = 0
      for j, n in ipairs(cols) do
        local v = grid[l][n]
        if v then all = all + v end
        gg:text(60 + (j - 1) * cw, y, v and tostring(v) or '-', { font = med })
      end
      gg:text(60 + #cols * cw, y, tostring(all), { font = med })
      y = y + 32
    end
  end
  y = y + 16
  gg:text(12, y, 'First two letters', { font = small })
  y = y + 28
  local keys = {}
  for k in pairs(twos) do keys[#keys + 1] = k end
  table.sort(keys)
  local parts = {}
  for _k, k in ipairs(keys) do parts[#parts + 1] = k:upper() .. '-' .. twos[k] end
  for _k, l in ipairs(kit.wrap(table.concat(parts, '   '), 'medium', W - 24)) do
    if y > BOT_Y - 34 then break end
    gg:text(12, y, l, { font = med })
    y = y + 30
  end
  local bw = (W - 24 - 2 * 10) // 3
  kit.button(gg, 12, BOT_Y, bw, BOT_H, 'Back')
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    gg:clear(0)
    header(gg, view == 'hints' and 'Hints' or 'Word Hive')
    if kit.modal() then kit.draw_modal(gg); return end
    if puz then
      if view == 'list' then draw_list(gg) elseif view == 'hints' then draw_hints(gg) else draw_play(gg) end
    end
    if ERR then gg:text(12, H - 30, kit.short('ERR ' .. ERR, 48), { font = kit.font('small') }) end
  end)
  if not ok then pcall(function() gg:text(8, H - 60, kit.short('draw ERR ' .. tostring(e), 46)) end) end
end

------------------------------------------------------------------ input

local function how_to()
  kit.show({ title = 'How to play', lines = {
    'Make words of four letters or more from the hive. Every word uses the middle letter; letters may be used more than once.',
    'A four-letter word scores 1 point, a longer word 1 point a letter. A pangram uses all seven letters and scores 7 more.',
    'A new hive every day. Hints counts the words still to find; Yesterday shows the answers of the day before.',
  }, rows = { { { 'Close', kit.close } } }, cancel = kit.close })
end

local function menu()
  local rows = {
    { { 'Today', function() kit.close(); open_day(today) end, pday ~= today },
      { 'Earlier', function() kit.close(); open_day(pday - 1) end } },
    { { 'Later', function() kit.close(); open_day(pday + 1) end, pday < today },
      { 'Found words', function() kit.close(); show_found() end } },
    { { 'How to play', how_to }, { 'Close', kit.close } },
  }
  kit.show({ title = 'Word Hive', lines = { date_label(pday) .. ', puzzle ' .. puz.no .. ' of ' .. (count or 0) ..
    '. Words: 12dicts (Alan Beale).' }, rows = rows, cancel = kit.close })
end

local function in_rect(x, y, rx, ry, rw, rh) return x >= rx and x < rx + rw and y >= ry and y < ry + rh end

local function tap(x, y)
  if kit.tap_modal(x, y) then return end
  local bw = (W - 24 - 2 * 10) // 3
  local function col(yy, hh)
    for k = 1, 3 do if in_rect(x, y, 12 + (k - 1) * (bw + 10), yy, bw, hh) then return k end end
  end
  if view == 'list' then
    local k = col(BOT_Y, BOT_H)
    if k == 1 then view = 'play'
    elseif k == 2 and pages() > 1 then list_page = math.max(1, list_page - 1)
    elseif k == 3 and pages() > 1 then list_page = math.min(pages(), list_page + 1)
    elseif y < BOT_Y and pages() > 1 then list_page = list_page % pages() + 1 end
    return
  end
  if view == 'hints' then
    if col(BOT_Y, BOT_H) == 1 or y < BOT_Y then view = 'play' end
    return
  end
  local k = col(BTN_Y, BTN_H)
  if k == 1 then word = kit.drop_last(word); msg = nil; return
  elseif k == 2 then shuffle(); return
  elseif k == 3 then submit(); return end
  k = col(BOT_Y, BOT_H)
  if k == 1 then view = 'hints'; return
  elseif k == 2 then show_yesterday(); return
  elseif k == 3 then menu(); return end
  if y >= FOUND_Y and y < BOT_Y then show_found(); return end
  for i, c in ipairs(CENTRES) do
    local dx, dy = x - c[1], y - c[2]
    if dx * dx + dy * dy <= (R - 2) * (R - 2) then
      if #word < 19 then word = word .. letter_at(i) end
      msg = nil
      return
    end
  end
end

function on_input(c, ev)
  ERR = nil
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    if ev.type == 'pointer' and ev.phase == 'up' then
      tap(ev.x or 0, ev.y or 0)
    elseif ev.type == 'key' and kit.key_accepted(ev) then
      if kit.modal() then
        if ev.key == 'back' and kit.modal().cancel then kit.modal().cancel() end
      elseif view == 'list' then
        if ev.key == 'down' or ev.key == 'right' then list_page = math.min(pages(), list_page + 1)
        elseif ev.key == 'up' or ev.key == 'left' then list_page = math.max(1, list_page - 1)
        elseif ev.key == 'back' then view = 'play' end
      elseif view == 'hints' then
        if ev.key == 'back' then view = 'play' end
      end
    end
  end)
  if not ok then ERR = tostring(e) end
  kit.refresh()
  return true
end

function on_load(c)
  local ok, e = pcall(function()
    load_found()
    today = local_day()
    open_day(today)
  end)
  if not ok then ERR = tostring(e) end
end
function on_leave() pcall(save) end

if rawget(_G, '__TEST') then
  __TEST.api = { puz = function() return puz end, word = function() return word end, msg = function() return msg end,
                 found = found, score = score, rank = function() return RANKS[rank_index(score())][2] end,
                 centres = CENTRES, letter_at = letter_at, open_day = open_day, view = function() return view end,
                 pday = function() return pday end, today = function() return today end, START = START,
                 days_from_civil = days_from_civil, civil = civil, date_label = date_label, count = function() return count end }
end
