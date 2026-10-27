-- Lock-screen entry for TBR Planner (API 2.9; bundle.py puts src/tbr.lua in front). Shows today's
-- books (planned for today, or late) with their progress from the reader, the next ones to start,
-- or the top of the wishlist when nothing is planned, and the reading streak.

local T = require('tbr')
local W, H = 480, 800
local M = 24

local function read(name)
  local ok, s = pcall(function() return ctx.storage:read(name) end)
  return (ok and type(s) == 'string') and s or nil
end
local function font(name) return ctx.fonts and ctx.fonts[name] end
local function width(f, s)
  local ok, w = pcall(function() return f:measure(s) end)
  return (ok and type(w) == 'number') and w or #s * 11
end
local function fit(fname, s, w)
  local f = font(fname)
  s = tostring(s)
  if width(f, s) <= w then return s end
  while #s > 1 and width(f, s .. '~') > w do s = s:gsub('[%z\1-\127\192-\255][\128-\191]*$', '') end
  return s .. '~'
end

function on_draw(c, gg)
  if not gg then return end
  local ok, err = pcall(function()
    gg:clear(0)
    local d = T.today()
    gg:text(M, 16, 'Reading plan', { font = font('large') })
    gg:text(M, 54, T.long_date(d), { font = font('medium') })
    gg:line(16, 92, W - 16, 92)
    gg:line(16, 93, W - 16, 93)
    local items = T.load(read('items.txt'))
    T.sync(items, T.reader_books(), d)
    local t = {}
    for k, v in (read('settings.txt') or ''):gmatch('([%w_]+)=([^\n]*)') do t[k] = v end
    local cfg = { minutes = tonumber(t.minutes) or 30, pages = tonumber(t.pages) or 20 }

    local now, soon, late = {}, {}, {}
    for _, it in ipairs(T.list(items, 'plan', 'date')) do
      local st = T.state(it, d)
      if st == 'today' then now[#now + 1] = it
      elseif st == 'late' then late[#late + 1] = it
      elseif st == 'soon' then soon[#soon + 1] = it end
    end
    for _, it in ipairs(late) do now[#now + 1] = it end

    local y, bottom = 108, H - 56
    local function book(it)
      if y + 58 > bottom then return false end
      gg:text(M, y, fit('medium', it.title, W - 2 * M), { font = font('medium') })
      local info = {}
      if it.author ~= '' then info[#info + 1] = it.author end
      local p = T.percent(it)
      if p and p > 0 then info[#info + 1] = p .. '%' end
      info[#info + 1] = T.when(it, d)
      local _n, left = T.left(it, cfg)
      if left then info[#info + 1] = left end
      gg:text(M, y + 28, fit('small', table.concat(info, ' · '), W - 2 * M), { font = font('small') })
      y = y + 62
      return true
    end
    if #now > 0 then
      gg:text(M, y, 'Today', { font = font('small') }); y = y + 26
      for _, it in ipairs(now) do if not book(it) then break end end
    else
      gg:text(M, y, 'Nothing planned for today.', { font = font('medium') }); y = y + 40
    end
    if #soon > 0 and y + 80 < bottom then
      y = y + 10
      gg:text(M, y, 'Coming up', { font = font('small') }); y = y + 26
      for k = 1, math.min(#soon, 4) do
        if y + 30 > bottom then break end
        local it = soon[k]
        gg:text(M, y, fit('medium', T.short_date(it.start or it['end']) .. '  ' .. it.title, W - 2 * M), { font = font('medium') })
        y = y + 32
      end
    end
    if #now == 0 and #soon == 0 then
      local wish = T.list(items, 'wish', 'priority')
      if #wish > 0 and y + 60 < bottom then
        y = y + 10
        gg:text(M, y, 'Next from your wishlist', { font = font('small') }); y = y + 26
        for k = 1, math.min(#wish, 3) do
          if y + 30 > bottom then break end
          gg:text(M, y, fit('medium', wish[k].title, W - 2 * M), { font = font('medium') })
          y = y + 32
        end
      end
    end
    local okr, s = pcall(function() return ctx.reader:summary() end)
    if okr and type(s) == 'table' then
      local parts = {}
      if tonumber(s.streak_days) then parts[#parts + 1] = 'streak ' .. T.plural(tonumber(s.streak_days), 'day', 'days') end
      if tonumber(s.today_sec) then parts[#parts + 1] = 'today ' .. T.duration(tonumber(s.today_sec)) end
      if #parts > 0 then gg:text(M, H - 32, 'Reading: ' .. table.concat(parts, ', '), { font = font('small') }) end
    end
  end)
  if not ok then pcall(function() gg:text(10, 760, 'lock error: ' .. tostring(err):sub(1, 40)) end) end
end

function on_load() end
function on_tick() end
function on_input() return false end
