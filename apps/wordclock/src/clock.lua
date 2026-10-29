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

local font_cache = {}
local function font_px(px)
  if font_cache[px] then return font_cache[px] end
  local ok, f = pcall(function() return ctx.fonts:size(px) end)
  if not ok or not f then
    -- only on a host without fonts:size (before 2.3)
    -- xtapp-ignore: font-small
    f = (px >= 30 and ctx.fonts.large) or (px >= 22 and ctx.fonts.medium) or ctx.fonts.small
  end
  font_cache[px] = f
  return f
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
  local small = font_px(math.max(16, math.floor(cw * 0.48)))
  local big = font_px(math.max(18, math.floor(cw * 0.7)))
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
