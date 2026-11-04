-- Lock-screen entry for Anki (API 2.9). Draws one card of lock_cards.txt, which the app writes
-- (first line: the deck's name; then "front<TAB>back" per card, "\n" for a line break): the lock
-- deck's cards due within a day, then its next new cards. A different card every half hour (the
-- manifest's interval_sec redraws it); front and answer together, to learn by looking. Right-to-
-- left text comes as pictures: a line "\1k,h,w,a" of a side is that side's k-th picture, from the
-- two more fields of the card (1-bit PNGs in base64, comma separated; see main.lua, "pictures").

local W, H = 480, 800
local EVERY = 1800

local function read(name)
  local ok, s = pcall(function() return ctx.storage:read(name) end)
  return (ok and type(s) == 'string') and s or nil
end
local function unesc(s)
  return (s:gsub('\\(.)', function(ch) if ch == 'n' then return '\n' elseif ch == 't' then return '\t' end return ch end))
end
local function font(name) return ctx.fonts and ctx.fonts[name] end
local function line_h(name)
  local ok, h = pcall(function() return font(name).line_height end)
  return (ok and tonumber(h)) or (name == 'large' and 30 or name == 'small' and 20 or 24)
end
local function width(f, s)
  local ok, w = pcall(function() return f:measure(s) end)
  return (ok and type(w) == 'number') and w or #s * 11
end
-- word wrap on ASCII spaces only (%s may also match a byte inside a UTF-8 letter)
local function wrap(s, f, maxw)
  local out = {}
  for para in (s .. '\n'):gmatch('([^\n]*)\n') do
    local line = ''
    for word in para:gmatch('[^ \t]+') do
      local cand = line == '' and word or (line .. ' ' .. word)
      if line ~= '' and width(f, cand) > maxw then out[#out + 1] = line; line = word else line = cand end
    end
    out[#out + 1] = line
  end
  return out
end

local function pic_mark(l)
  local k, h, w, a = l:match('^\1(%d+),(%d+),(%d+),([lr])$')
  if k then return { k = tonumber(k), h = tonumber(h), w = tonumber(w), a = a } end
end
local function nth(list, k)
  local i = 0
  for b64 in (list or ''):gmatch('[^,]+') do
    i = i + 1
    if i == k then return b64 end
  end
end
local decoded = 0                  -- the host holds 8 decoded pictures at a time
local function decode(b64)
  if not (b64 and b64 ~= '' and ctx.image and ctx.base64) or decoded >= 8 then return nil end
  decoded = decoded + 1
  local ok, im = pcall(function()
    local bytes = ctx.base64:decode(b64)
    return bytes and ctx.image:decode(bytes, { max_w = 480, max_h = 1024 })
  end)
  return ok and im or nil
end
-- a drawn line: centred, or by its side's alignment; false when it does not fit above `bottom`
local function draw_pic(gg, im, m, y, centred, bottom)
  if y + m.h > bottom then return false end
  local x = centred and (W - m.w) // 2 or (m.a == 'r' and W - 20 - m.w or 20)
  if im then gg:image(im, x, y) end
  return true
end

local function epoch()
  local ok, t = pcall(function() return ctx.clock:now() end)
  if ok and type(t) == 'table' and tonumber(t.epoch_sec) then return math.floor(tonumber(t.epoch_sec)) end
  return 0
end

function on_draw(c, gg)
  if not gg then return end
  local ok, err = pcall(function()
    gg:clear(0)
    local text = read('lock_cards.txt')
    local name, cards = nil, {}
    for line in (text or ''):gmatch('([^\n]*)\n') do
      if not name then name = line
      else
        local f, b, fs, bs = line:match('^([^\t]*)\t([^\t]*)\t?([^\t]*)\t?([^\t]*)')
        if f and f ~= '' then cards[#cards + 1] = { unesc(f), unesc(b), fs, bs } end
      end
    end
    if #cards == 0 then
      gg:text(24, 380, 'Anki: no cards for the lock screen', { font = font('medium') })
      return
    end
    local i = (epoch() // EVERY) % #cards + 1
    local card = cards[i]
    gg:text(20, 16, 'Anki  ' .. (name or ''), { font = font('small') })
    local y, first = 140, true
    for para in (card[1] .. '\n'):gmatch('([^\n]*)\n') do
      local fname = first and 'large' or 'medium'
      local f = font(fname)
      local m = pic_mark(para)
      if m then
        if draw_pic(gg, decode(nth(card[3], m.k)), m, y, true, H / 2) then y = y + m.h end
      else
        for _k, l in ipairs(wrap(para, f, W - 40)) do
          gg:text((W - width(f, l)) // 2, y, l, { font = f })
          y = y + line_h(fname) + 6
        end
      end
      first = false
    end
    y = y + 12
    gg:line(40, y, W - 40, y)
    y = y + 24
    local f = font('medium')
    for para in (card[2] .. '\n'):gmatch('([^\n]*)\n') do
      local m = pic_mark(para)
      if m then
        if not draw_pic(gg, decode(nth(card[4], m.k)), m, y, false, H - 60) then break end
        y = y + m.h
      else
        local full = false
        for _k, l in ipairs(wrap(para, f, W - 40)) do
          if y + line_h('medium') > H - 60 then full = true; break end
          gg:text(20, y, l, { font = f })
          y = y + line_h('medium') + 4
        end
        if full then break end
      end
    end
    gg:text(20, H - 36, 'card ' .. i .. ' of ' .. #cards .. ', a new one every 30 minutes', { font = font('small') })
  end)
  if not ok then pcall(function() gg:text(10, 760, 'lock error: ' .. tostring(err):sub(1, 40)) end) end
end

function on_load() end
function on_tick() end
function on_input() return false end
