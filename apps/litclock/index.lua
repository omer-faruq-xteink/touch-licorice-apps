-- built by bundle.py from src/common.lua and src/app.lua: edit those, not this file

-- Literary Clock: shared by the app (index.lua) and the lock screen (lockscreen.lua); bundle.py
-- puts this file in front of each. The time of day told by a sentence from a public-domain book:
-- data/hHH.txt holds the quotes of hour HH, one per line,
--   HHMM<TAB>flag<TAB>before<TAB>time phrase<TAB>after<TAB>title<TAB>author
-- (flag "e": the phrase names this minute; "n": none does, the nearest earlier quote stands in).
-- The phrase is drawn bold (each glyph twice, 1 px apart: works on any 2.x host).

local W, H = 480, 800
local M = 34                                     -- side margin
local SIZES = { 46, 42, 38, 35, 32, 29, 26, 24, 22, 20 }
local MONTHS = { 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
                 'September', 'October', 'November', 'December' }
local DAYS = { 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday' }

------------------------------------------------------------------ settings and time

local function sread(name)
  local ok, s = pcall(function() return ctx.storage:read(name) end)
  return (ok and type(s) == 'string') and s or nil
end
local function swrite(name, s) pcall(function() ctx.storage:write(name, s) end) end

-- settings.txt: "timeline=1" (show the digital time under the quote)
local function load_settings()
  local s = sread('settings.txt') or ''
  return { timeline = s:match('timeline=0') == nil }
end
local function save_settings(st)
  swrite('settings.txt', 'timeline=' .. (st.timeline and '1' or '0') .. '\n')
end

local function now()
  local ok, t = pcall(function() return ctx.clock:now() end)
  if ok and type(t) == 'table' and t.valid and t.hour then return t end
  return nil
end

local function time_line(t)
  if not t then return '' end
  local hh, mm = t.hour, t.minute
  local clock
  if t.hour12 then
    local h12 = hh % 12 == 0 and 12 or hh % 12
    clock = string.format('%d:%02d %s', h12, mm, hh < 12 and 'am' or 'pm')
  else
    clock = string.format('%02d:%02d', hh, mm)
  end
  local date = ''
  if t.weekday and t.day and t.month then
    date = '  ·  ' .. DAYS[t.weekday + 1] .. ' ' .. t.day .. ' ' .. MONTHS[t.month]
  end
  return clock .. date
end

------------------------------------------------------------------ quotes

-- the quotes for minute hh:mm: { {flag, before, phrase, after, title, author} ... }
local function quotes_at(hh, mm)
  local want = string.format('%02d%02d', hh, mm)
  local out = {}
  local ok, r = pcall(function()
    return ctx.package:open_text(string.format('h%02d.txt', hh), { max_line_bytes = 2048 })
  end)
  if not ok or r == nil or type(r) == 'string' then return out end
  pcall(function()
    for _ = 1, 2000 do
      local line = r:read_line()
      if line == nil then break end
      local key = line:sub(1, 4)
      if key == want then
        local f = {}
        for field in (line .. '\t'):gmatch('([^\t]*)\t') do f[#f + 1] = field end
        out[#out + 1] = { flag = f[2], before = f[3] or '', phrase = f[4] or '', after = f[5] or '',
                          title = f[6] or '', author = f[7] or '' }
      elseif key > want then
        break                                    -- the lines are in time order
      end
    end
  end)
  pcall(function() r:close() end)
  return out
end

-- one of the minute's quotes: a different one each day, `shift` steps on from it
local function pick(list, t, shift)
  if #list == 0 then return nil end
  local day = t and ((t.year or 0) * 372 + (t.month or 0) * 31 + (t.day or 0)) or 0
  return list[(day + (shift or 0)) % #list + 1]
end

------------------------------------------------------------------ layout

local font_cache = {}
local function font_px(px)
  if font_cache[px] then return font_cache[px] end
  local ok, f = pcall(function() return ctx.fonts:size(px) end)
  if not ok or not f then
    f = (px >= 34 and ctx.fonts.large) or (px >= 24 and ctx.fonts.medium) or ctx.fonts.small
  end
  font_cache[px] = f
  return f
end
local function measure(f, s)
  local ok, w = pcall(function() return f:measure(s) end)
  return (ok and type(w) == 'number') and w or #s * 10
end
local function line_h(f)
  local ok, h = pcall(function() return f.line_height end)
  return (ok and tonumber(h)) or 30
end

-- the quote as words split at the spaces of the whole sentence; a word is a list of pieces
-- { text, bold }, so "nine." is one word with a bold "nine" and a plain "."
local function words_of(q)
  local full = q.before .. q.phrase .. q.after
  local b0, b1 = #q.before + 1, #q.before + #q.phrase
  local out = {}
  for s, w in full:gmatch('()(%S+)') do
    local e = s + #w - 1
    local word = {}
    local function piece(i, j, bold)
      if i <= j then word[#word + 1] = { full:sub(i, j), bold } end
    end
    piece(s, math.min(e, b0 - 1), false)
    piece(math.max(s, b0), math.min(e, b1), true)
    piece(math.max(s, b1 + 1), e, false)
    out[#out + 1] = word
  end
  return out
end

local function word_w(f, word)
  local w = 0
  for _, p in ipairs(word) do w = w + measure(f, p[1]) + (p[2] and 1 or 0) end
  return w
end

-- lines of words that fit `maxw` in font f: { {words...}, ... }
local function wrap(words, f, maxw)
  local lines, cur, curw = {}, {}, 0
  local space = measure(f, ' ')
  for _, w in ipairs(words) do
    local ww = word_w(f, w)
    if #cur > 0 and curw + space + ww > maxw then
      lines[#lines + 1] = cur; cur, curw = {}, 0
    end
    curw = curw + (#cur > 0 and space or 0) + ww
    cur[#cur + 1] = w
  end
  if #cur > 0 then lines[#lines + 1] = cur end
  return lines
end

-- the largest size whose wrapped quote fits the box
local function fit(words, maxw, maxh)
  for _, px in ipairs(SIZES) do
    local f = font_px(px)
    local lines = wrap(words, f, maxw)
    local lh = line_h(f) + math.floor(px / 5)
    if #lines * lh <= maxh then return f, lines, lh end
  end
  local f = font_px(SIZES[#SIZES])
  return f, wrap(words, f, maxw), line_h(f) + 4
end

local function draw_words(g, x, y, line, f)
  local space = measure(f, ' ')
  for _, word in ipairs(line) do
    for _, p in ipairs(word) do
      g:text(x, y, p[1], { font = f })
      if p[2] then g:text(x + 1, y, p[1], { font = f }) end   -- bold: the glyphs again, 1 px right
      x = x + measure(f, p[1]) + (p[2] and 1 or 0)
    end
    x = x + space
  end
end

-- the quote and its source between y0 and y1, the time line (when shown) just below y1
local function draw_quote(g, q, t, show_time, y0, y1)
  if not q then
    local f = font_px(26)
    g:text(W // 2, (y0 + y1) // 2, 'No quote for this minute.', { font = f, align = 'center' })
    return
  end
  local small, smallb = font_px(20), font_px(22)
  local attr_h = line_h(smallb) + line_h(small) + 30
  local words = words_of(q)
  local f, lines, lh = fit(words, W - 2 * M, (y1 - y0) - attr_h - 20)
  local total = #lines * lh + attr_h
  local y = y0 + math.max(0, ((y1 - y0) - total) // 2)
  for _, line in ipairs(lines) do
    draw_words(g, M, y, line, f)
    y = y + lh
  end
  y = y + 18
  g:line(W - M - 150, y, W - M, y)
  g:line(W - M - 150, y + 1, W - M, y + 1)
  y = y + 14
  local title = q.title
  if measure(smallb, title) > W - 2 * M then
    while #title > 4 and measure(smallb, title .. '...') > W - 2 * M do title = title:sub(1, -2) end
    title = title .. '...'
  end
  g:text(W - M, y, title, { font = smallb, align = 'right' })
  g:text(W - M - 1, y, title, { font = smallb, align = 'right' })
  g:text(W - M, y + line_h(smallb) + 2, q.author, { font = small, align = 'right' })
  if show_time or q.flag == 'n' then
    g:text(M, y1 + 6, time_line(t), { font = small })      -- just under the quote's box
  end
end

-- The app: the quote for the current minute, updated on each minute while open. Another (or a tap
-- on the quote) steps through the minute's quotes, 1/3 2/3 3/3 and round; the buttons turn the
-- digital time on or off and make (or stop making) the Literary Clock the lock screen.

local BTN_Y, BTN_H = H - 64, 50
local settings = { timeline = true }
local t, list, shift, quote = nil, {}, 0, nil
local key = nil                                  -- "HHMM" of the quotes loaded
local timer = nil

local function refresh() pcall(function() ctx:invalidate() end) end

local function load_minute()
  t = now()
  if not t then list, quote = {}, nil; return end
  local k = string.format('%02d%02d', t.hour, t.minute)
  if k ~= key then key, shift = k, 0; list = quotes_at(t.hour, t.minute) end
  quote = pick(list, t, shift)
end

local function is_lock()
  local ok, v = pcall(function() return ctx.lockscreen and ctx.lockscreen:is_default() end)
  return ok and v == true
end

-- wake on the next whole minute
local function schedule()
  pcall(function() if timer then timer:cancel() end end)
  local sec = (t and t.second) or 0
  local ok, tm = pcall(function()
    return ctx:after((60 - sec) * 1000 + 200, function() load_minute(); refresh(); schedule() end)
  end)
  timer = ok and tm or nil
end

-- "Another 2/3": which of the minute's quotes is shown, counted from the one shown first;
-- "(only one)" when the minute has a single quote, so a tap that changes nothing is expected
local function another_label()
  if #list < 2 then return '(only one)' end
  return 'Another ' .. (shift % #list + 1) .. '/' .. #list
end

local function next_quote()
  if #list < 2 then return end
  shift = shift + 1
  quote = pick(list, t, shift)
end

local function buttons()
  return {
    { another_label(), next_quote },
    { settings.timeline and 'Time: on' or 'Time: off', function()
        settings.timeline = not settings.timeline; save_settings(settings) end },
    { is_lock() and 'Lock: on' or 'Lock screen', function()
        if is_lock() then pcall(function() ctx.lockscreen:clear_default() end)
        else pcall(function() ctx.lockscreen:set_default() end) end
      end },
  }
end

local function button_rect(k, n)
  local gap = 10
  local bw = (W - 2 * 16 - (n - 1) * gap) // n
  return 16 + (k - 1) * (bw + gap), BTN_Y, bw, BTN_H
end

function on_load(c)
  settings = load_settings()
  load_minute()
  schedule()
end

function on_resume(c)
  load_minute(); refresh(); schedule()
end

function on_draw(c, g)
  if not g then return end
  local ok, e = pcall(function()
    g:clear(0)
    if not t then
      g:text(W // 2, H // 2 - 20, 'The clock is not set.', { font = font_px(26), align = 'center' })
      g:text(W // 2, H // 2 + 20, 'Set the time in the system settings.', { font = font_px(20), align = 'center' })
    else
      draw_quote(g, quote, t, settings.timeline, 30, BTN_Y - 40)
    end
    local bs = buttons()
    local f = font_px(22)
    for k, b in ipairs(bs) do
      local x, y, bw, bh = button_rect(k, #bs)
      g:rect(x, y, bw, bh)
      g:text(x + bw // 2, y + bh // 2, b[1], { font = f, align = 'center', valign = 'middle' })
    end
  end)
  if not ok then pcall(function() g:text(10, H - 100, 'draw error: ' .. tostring(e):sub(1, 40)) end) end
end

function on_input(c, ev)
  if type(ev) ~= 'table' then return false end
  if ev.type == 'pointer' and ev.phase == 'up' then
    local x, y = ev.x or 0, ev.y or 0
    local bs = buttons()
    for k, b in ipairs(bs) do
      local bx, by, bw, bh = button_rect(k, #bs)
      if x >= bx and x < bx + bw and y >= by and y < by + bh then
        pcall(b[2]); refresh(); return true
      end
    end
    if y < BTN_Y - 10 then next_quote(); refresh() end
    return true
  elseif ev.type == 'key' and ev.phase ~= 'up' and (ev.key == 'down' or ev.key == 'right' or ev.key == 'up' or ev.key == 'left') then
    if #list >= 2 then
      shift = shift + ((ev.key == 'up' or ev.key == 'left') and -1 or 1)
      quote = pick(list, t, shift); refresh()
    end
    return true
  end
  return false
end

function on_leave(c)
  pcall(function() if timer then timer:cancel() end end)
end
