-- built by bundle.py from src/grids.lua, src/clock.lua and src/app.lua: edit those, not this file

-- built by make_grids.py: edit that, not this file

local GRIDS = {
  en = {
    rows = {
      { 'I', 'T', 'L', 'I', 'S', 'A', 'S', 'A', 'M', 'P', 'M' },
      { 'A', 'C', 'Q', 'U', 'A', 'R', 'T', 'E', 'R', 'D', 'C' },
      { 'T', 'W', 'E', 'N', 'T', 'Y', 'F', 'I', 'V', 'E', 'X' },
      { 'H', 'A', 'L', 'F', 'S', 'T', 'E', 'N', 'F', 'T', 'O' },
      { 'P', 'A', 'S', 'T', 'E', 'R', 'U', 'N', 'I', 'N', 'E' },
      { 'O', 'N', 'E', 'S', 'I', 'X', 'T', 'H', 'R', 'E', 'E' },
      { 'F', 'O', 'U', 'R', 'F', 'I', 'V', 'E', 'T', 'W', 'O' },
      { 'E', 'I', 'G', 'H', 'T', 'E', 'L', 'E', 'V', 'E', 'N' },
      { 'S', 'E', 'V', 'E', 'N', 'T', 'W', 'E', 'L', 'V', 'E' },
      { 'T', 'E', 'N', 'S', 'E', 'O', 'C', 'L', 'O', 'C', 'K' },
    },
    words = {
      ['IT'] = { 1, 1, 2 },
      ['IS'] = { 1, 4, 2 },
      ['A'] = { 2, 1, 1 },
      ['QUARTER'] = { 2, 3, 7 },
      ['TWENTY'] = { 3, 1, 6 },
      ['FIVE_M'] = { 3, 7, 4 },
      ['HALF'] = { 4, 1, 4 },
      ['TEN_M'] = { 4, 6, 3 },
      ['TO'] = { 4, 10, 2 },
      ['PAST'] = { 5, 1, 4 },
      ['9'] = { 5, 8, 4 },
      ['1'] = { 6, 1, 3 },
      ['6'] = { 6, 4, 3 },
      ['3'] = { 6, 7, 5 },
      ['4'] = { 7, 1, 4 },
      ['5'] = { 7, 5, 4 },
      ['2'] = { 7, 9, 3 },
      ['8'] = { 8, 1, 5 },
      ['11'] = { 8, 6, 6 },
      ['7'] = { 9, 1, 5 },
      ['12'] = { 9, 6, 6 },
      ['10'] = { 10, 1, 3 },
      ['OCLOCK'] = { 10, 6, 6 },
    },
  },
  de = {
    rows = {
      { 'E', 'S', 'K', 'I', 'S', 'T', 'A', 'F', 'Ü', 'N', 'F' },
      { 'Z', 'E', 'H', 'N', 'Z', 'W', 'A', 'N', 'Z', 'I', 'G' },
      { 'D', 'R', 'E', 'I', 'V', 'I', 'E', 'R', 'T', 'E', 'L' },
      { 'V', 'O', 'R', 'F', 'U', 'N', 'K', 'N', 'A', 'C', 'H' },
      { 'H', 'A', 'L', 'B', 'A', 'E', 'L', 'F', 'Ü', 'N', 'F' },
      { 'E', 'I', 'N', 'S', 'X', 'A', 'M', 'Z', 'W', 'E', 'I' },
      { 'D', 'R', 'E', 'I', 'P', 'M', 'J', 'V', 'I', 'E', 'R' },
      { 'S', 'E', 'C', 'H', 'S', 'N', 'L', 'A', 'C', 'H', 'T' },
      { 'S', 'I', 'E', 'B', 'E', 'N', 'Z', 'W', 'Ö', 'L', 'F' },
      { 'Z', 'E', 'H', 'N', 'E', 'U', 'N', 'K', 'U', 'H', 'R' },
    },
    words = {
      ['ES'] = { 1, 1, 2 },
      ['IST'] = { 1, 4, 3 },
      ['FÜNF_M'] = { 1, 8, 4 },
      ['ZEHN_M'] = { 2, 1, 4 },
      ['ZWANZIG'] = { 2, 5, 7 },
      ['VIERTEL'] = { 3, 5, 7 },
      ['VOR'] = { 4, 1, 3 },
      ['NACH'] = { 4, 8, 4 },
      ['HALB'] = { 5, 1, 4 },
      ['11'] = { 5, 6, 3 },
      ['5'] = { 5, 8, 4 },
      ['1'] = { 6, 1, 4 },
      ['EIN'] = { 6, 1, 3 },
      ['2'] = { 6, 8, 4 },
      ['3'] = { 7, 1, 4 },
      ['4'] = { 7, 8, 4 },
      ['6'] = { 8, 1, 5 },
      ['8'] = { 8, 8, 4 },
      ['7'] = { 9, 1, 6 },
      ['12'] = { 9, 7, 5 },
      ['10'] = { 10, 1, 4 },
      ['9'] = { 10, 4, 4 },
      ['UHR'] = { 10, 9, 3 },
    },
  },
  tr = {
    rows = {
      { 'S', 'A', 'A', 'T', 'S', 'O', 'N', 'U', 'E', 'O', 'N', 'A' },
      { 'B', 'İ', 'R', 'İ', 'Z', 'B', 'İ', 'R', 'E', 'T', 'N', 'A' },
      { 'İ', 'K', 'İ', 'Y', 'İ', 'A', 'İ', 'K', 'İ', 'Y', 'E', 'U' },
      { 'Ü', 'Ç', 'Ü', 'K', 'Ü', 'Ç', 'E', 'S', 'D', 'Ö', 'R', 'T' },
      { 'D', 'Ö', 'R', 'D', 'Ü', 'H', 'D', 'Ö', 'R', 'D', 'E', 'E' },
      { 'B', 'E', 'Ş', 'İ', 'R', 'B', 'E', 'Ş', 'E', 'L', 'M', 'R' },
      { 'A', 'L', 'T', 'I', 'Y', 'I', 'A', 'L', 'T', 'I', 'Y', 'A' },
      { 'Y', 'E', 'D', 'İ', 'Y', 'İ', 'Y', 'E', 'D', 'İ', 'Y', 'E' },
      { 'S', 'E', 'K', 'İ', 'Z', 'İ', 'S', 'E', 'K', 'İ', 'Z', 'E' },
      { 'D', 'O', 'K', 'U', 'Z', 'U', 'D', 'O', 'K', 'U', 'Z', 'A' },
      { 'Y', 'A', 'R', 'I', 'M', 'R', 'B', 'U', 'Ç', 'U', 'K', 'M' },
      { 'Y', 'İ', 'R', 'M', 'İ', 'U', 'B', 'E', 'Ş', 'M', 'O', 'N' },
      { 'Ç', 'E', 'Y', 'R', 'E', 'K', 'K', 'L', 'M', 'R', 'S', 'T' },
      { 'G', 'E', 'Ç', 'İ', 'Y', 'O', 'R', 'M', 'V', 'A', 'R', 'T' },
    },
    words = {
      ['SAAT'] = { 1, 1, 4 },
      ['ONU'] = { 1, 6, 3 },
      ['ONA'] = { 1, 10, 3 },
      ['BİRİ'] = { 2, 1, 4 },
      ['BİRE'] = { 2, 6, 4 },
      ['İKİYİ'] = { 3, 1, 5 },
      ['İKİYE'] = { 3, 7, 5 },
      ['ÜÇÜ'] = { 4, 1, 3 },
      ['ÜÇE'] = { 4, 5, 3 },
      ['DÖRT'] = { 4, 9, 4 },
      ['DÖRDÜ'] = { 5, 1, 5 },
      ['DÖRDE'] = { 5, 7, 5 },
      ['BEŞİ'] = { 6, 1, 4 },
      ['BEŞE'] = { 6, 6, 4 },
      ['ALTIYI'] = { 7, 1, 6 },
      ['ALTIYA'] = { 7, 7, 6 },
      ['YEDİYİ'] = { 8, 1, 6 },
      ['YEDİYE'] = { 8, 7, 6 },
      ['SEKİZİ'] = { 9, 1, 6 },
      ['SEKİZE'] = { 9, 7, 6 },
      ['DOKUZU'] = { 10, 1, 6 },
      ['DOKUZA'] = { 10, 7, 6 },
      ['YARIM'] = { 11, 1, 5 },
      ['BUÇUK'] = { 11, 7, 5 },
      ['YİRMİ'] = { 12, 1, 5 },
      ['BEŞ'] = { 12, 7, 3 },
      ['ON'] = { 12, 11, 2 },
      ['ÇEYREK'] = { 13, 1, 6 },
      ['GEÇİYOR'] = { 14, 1, 7 },
      ['VAR'] = { 14, 9, 3 },
      ['BİR'] = { 2, 1, 3 },
      ['İKİ'] = { 3, 1, 3 },
      ['ÜÇ'] = { 4, 1, 2 },
      ['BEŞ_H'] = { 6, 1, 3 },
      ['ALTI'] = { 7, 1, 4 },
      ['YEDİ'] = { 8, 1, 4 },
      ['SEKİZ'] = { 9, 1, 5 },
      ['DOKUZ'] = { 10, 1, 5 },
      ['ON_H'] = { 1, 6, 2 },
    },
  },
}

-- Word Clock: shared by the app (index.lua) and the lock screen (lockscreen.lua); bundle.py puts
-- grids.lua and this file in front of each. The time in words on a grid of letters, in five-
-- minute steps ("IT IS HALF PAST TEN"), dots under the grid for the minutes between. The words
-- of the time are black blocks with white letters, the rest small plain letters: the lock screen
-- shows only black and white, so unlit letters cannot be gray.

local W, H = 480, 800
local LANGS = { 'en', 'tr', 'de' }
local LANG_NAMES = { en = 'English', tr = 'Türkçe', de = 'Deutsch' }

------------------------------------------------------------------ the sentence

-- hour 0..23 -> 1..12
local function h12(h) local x = h % 12; return x == 0 and 12 or x end

local EN_MIN = { [5] = { 'FIVE_M' }, [10] = { 'TEN_M' }, [15] = { 'A', 'QUARTER' }, [20] = { 'TWENTY' },
                 [25] = { 'TWENTY', 'FIVE_M' }, [30] = { 'HALF' } }
local DE_MIN = { [5] = 'FÜNF_M', [10] = 'ZEHN_M', [15] = 'VIERTEL', [20] = 'ZWANZIG' }
local TR_MIN = { [5] = { 'BEŞ' }, [10] = { 'ON' }, [15] = { 'ÇEYREK' }, [20] = { 'YİRMİ' }, [25] = { 'YİRMİ', 'BEŞ' } }
-- Turkish hours: the bare form (on the hour, "buçuk"), the object form (past) and the dative (to)
local TR_BARE = { 'BİR', 'İKİ', 'ÜÇ', 'DÖRT', 'BEŞ_H', 'ALTI', 'YEDİ', 'SEKİZ', 'DOKUZ', 'ON_H' }
local TR_ACC = { 'BİRİ', 'İKİYİ', 'ÜÇÜ', 'DÖRDÜ', 'BEŞİ', 'ALTIYI', 'YEDİYİ', 'SEKİZİ', 'DOKUZU', 'ONU' }
local TR_DAT = { 'BİRE', 'İKİYE', 'ÜÇE', 'DÖRDE', 'BEŞE', 'ALTIYA', 'YEDİYE', 'SEKİZE', 'DOKUZA', 'ONA' }

local function tr_hour(forms, n)                 -- 11 and 12 are "ON" + the form of 1 / 2
  if n <= 10 then return { forms[n] } end
  return { 'ON_H', forms[n - 10] }
end

local function append(t, more) for _, w in ipairs(more) do t[#t + 1] = w end; return t end

-- the words lit at hh:mm (minutes rounded down to five)
local function sentence(lang, hh, mm)
  local m5 = mm - mm % 5
  local here, nxt = h12(hh), h12(hh + 1)
  if lang == 'de' then
    local w = { 'ES', 'IST' }
    if m5 == 0 then return append(w, { here == 1 and 'EIN' or tostring(here), 'UHR' }) end
    if m5 <= 20 then return append(w, { DE_MIN[m5], 'NACH', tostring(here) }) end
    if m5 == 25 then return append(w, { 'FÜNF_M', 'VOR', 'HALB', tostring(nxt) }) end
    if m5 == 30 then return append(w, { 'HALB', tostring(nxt) }) end
    if m5 == 35 then return append(w, { 'FÜNF_M', 'NACH', 'HALB', tostring(nxt) }) end
    return append(w, { DE_MIN[60 - m5], 'VOR', tostring(nxt) })
  elseif lang == 'tr' then
    local w = { 'SAAT' }
    if m5 == 0 then return append(w, tr_hour(TR_BARE, here)) end
    if m5 == 30 then
      if here == 12 then return append(w, { 'YARIM' }) end      -- 12:30 and 0:30: "saat yarım"
      return append(append(w, tr_hour(TR_BARE, here)), { 'BUÇUK' })
    end
    if m5 < 30 then return append(append(append(w, tr_hour(TR_ACC, here)), TR_MIN[m5]), { 'GEÇİYOR' }) end
    return append(append(append(w, tr_hour(TR_DAT, nxt)), TR_MIN[60 - m5]), { 'VAR' })
  end
  local w = { 'IT', 'IS' }
  if m5 == 0 then return append(w, { tostring(here), 'OCLOCK' }) end
  if m5 <= 30 then return append(append(w, EN_MIN[m5]), { 'PAST', tostring(here) }) end
  return append(append(w, EN_MIN[60 - m5]), { 'TO', tostring(nxt) })
end

------------------------------------------------------------------ settings and time

local function sread(name)
  local ok, s = pcall(function() return ctx.storage:read(name) end)
  return (ok and type(s) == 'string') and s or nil
end
local function swrite(name, s) pcall(function() ctx.storage:write(name, s) end) end

-- the language: settings.txt "lang=tr", else the system language when it is one of ours
local function load_lang()
  local l = (sread('settings.txt') or ''):match('lang=(%a+)')
  if l and GRIDS[l] then return l end
  local ok, loc = pcall(function() return ctx.i18n.locale end)
  loc = (ok and type(loc) == 'string') and loc:sub(1, 2) or 'en'
  return GRIDS[loc] and loc or 'en'
end
local function save_lang(l) swrite('settings.txt', 'lang=' .. l .. '\n') end

local function now()
  local ok, t = pcall(function() return ctx.clock:now() end)
  if ok and type(t) == 'table' and t.valid and t.hour then return t end
  return nil
end

------------------------------------------------------------------ drawing

-- a font of px pixels that has every letter of `sample` (2.3.1): the user's font may lack İ or Ş
-- (MiSans does), and the host then picks one that has them
local font_cache = {}
local function font_px(px, sample)
  local key = px .. ':' .. (sample or '')
  if font_cache[key] then return font_cache[key] end
  local ok, f = pcall(function() return ctx.fonts:size(px, sample) end)
  if not ok or not f then ok, f = pcall(function() return ctx.fonts:size(px) end) end
  if not ok or not f then
    -- only on a host without fonts:size (before 2.3)
    -- xtapp-ignore: font-small
    f = (px >= 30 and ctx.fonts.large) or (px >= 22 and ctx.fonts.medium) or ctx.fonts.small
  end
  font_cache[key] = f
  return f
end

-- the grid's letters outside ASCII ("İŞÇÖÜ"), once per language
local sample_cache = {}
local function grid_sample(lang)
  if sample_cache[lang] then return sample_cache[lang] end
  local seen, out = {}, {}
  for _, row in ipairs(GRIDS[lang].rows) do
    for _, ch in ipairs(row) do
      if #ch > 1 and not seen[ch] then seen[ch] = true; out[#out + 1] = ch end
    end
  end
  sample_cache[lang] = table.concat(out)
  return sample_cache[lang]
end

-- the grid between y0 and y1 with the words of hh:mm lit; the minute dots below it
local function draw_clock(g, lang, hh, mm, y0, y1)
  local grid = GRIDS[lang]
  local rows, cols = #grid.rows, #grid.rows[1]
  local cw = (W - 24) // cols
  local ch = math.min(math.floor(cw * 1.3), (y1 - y0 - 50) // rows)
  local gx = (W - cw * cols) // 2
  local gy = y0 + ((y1 - y0 - 50) - ch * rows) // 2
  local lit = {}
  for _, key in ipairs(sentence(lang, hh, mm)) do
    local w = grid.words[key]
    if w then
      for c = w[2], w[2] + w[3] - 1 do lit[(w[1] - 1) * cols + c] = true end
      g:rect(gx + (w[2] - 1) * cw + 1, gy + (w[1] - 1) * ch + 3, w[3] * cw - 2, ch - 6, { fill = true, radius = 6 })
    end
  end
  local sample = grid_sample(lang)
  local small = font_px(math.max(16, math.floor(cw * 0.48)), sample)
  local big = font_px(math.max(18, math.floor(cw * 0.7)), sample)
  for r = 1, rows do
    for c = 1, cols do
      local x, y = gx + (c - 1) * cw + cw // 2, gy + (r - 1) * ch + ch // 2
      local letter = grid.rows[r][c]
      if lit[(r - 1) * cols + c] then
        g:text(x, y, letter, { font = big, align = 'center', valign = 'middle', color = 0 })
        g:text(x + 1, y, letter, { font = big, align = 'center', valign = 'middle', color = 0 })
      else
        g:text(x, y, letter, { font = small, align = 'center', valign = 'middle' })
      end
    end
  end
  local dy = gy + ch * rows + 30
  for k = 1, 4 do
    local cx = W // 2 - 51 + (k - 1) * 34
    g:circle(cx, dy, 7, { fill = k <= mm % 5, line_width = 2 })
  end
end

if rawget(_G, '__TEST') then __TEST.GRIDS, __TEST.sentence = GRIDS, sentence end


-- The app: the word clock for the current time, redrawn on each minute while open. The language
-- button cycles English / Türkçe / Deutsch (saved; the lock screen follows it), Lock screen
-- makes the Word Clock the lock screen or gives it back.

local BTN_Y, BTN_H = H - 64, 50
local t, lang = nil, 'en'
local timer = nil

local function refresh() pcall(function() ctx:invalidate() end) end

local function is_lock()
  local ok, v = pcall(function() return ctx.lockscreen and ctx.lockscreen:is_default() end)
  return ok and v == true
end

-- wake on the next whole minute
local function schedule()
  pcall(function() if timer then timer:cancel() end end)
  local sec = (t and t.second) or 0
  local ok, tm = pcall(function()
    return ctx:after((60 - sec) * 1000 + 200, function() t = now(); refresh(); schedule() end)
  end)
  timer = ok and tm or nil
end

local function buttons()
  return {
    { LANG_NAMES[lang], function()
        for i, l in ipairs(LANGS) do
          if l == lang then lang = LANGS[i % #LANGS + 1]; break end
        end
        save_lang(lang)
      end },
    { is_lock() and 'Lock: on' or 'Lock screen', function()
        if is_lock() then pcall(function() ctx.lockscreen:clear_default() end)
        else pcall(function() ctx.lockscreen:set_default() end) end
      end },
  }
end

local function button_rect(k, n)
  local gap = 12
  local bw = (W - 2 * 16 - (n - 1) * gap) // n
  return 16 + (k - 1) * (bw + gap), BTN_Y, bw, BTN_H
end

function on_load(c)
  lang = load_lang()
  t = now()
  schedule()
end

function on_resume(c)
  t = now(); refresh(); schedule()
end

function on_draw(c, g)
  if not g then return end
  local ok, e = pcall(function()
    g:clear(0)
    if not t then
      g:text(W // 2, H // 2 - 20, 'The clock is not set.', { font = font_px(26), align = 'center' })
      g:text(W // 2, H // 2 + 20, 'Set the time in the system settings.', { font = font_px(20), align = 'center' })
    else
      draw_clock(g, lang, t.hour, t.minute, 20, BTN_Y - 10)
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
    return true
  end
  return false
end

function on_leave(c)
  pcall(function() if timer then timer:cancel() end end)
end
