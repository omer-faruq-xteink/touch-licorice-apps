-- Lock-screen entry for Tasks (API 2.9): the open items of the list chosen in the app, from
-- lock.txt (first line: the list's name; then one item a line), with today's date.

local W, H = 480, 800

local function read(name)
  local ok, s = pcall(function() return ctx.storage:read(name) end)
  return (ok and type(s) == 'string') and s or nil
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
local function wrap(s, f, maxw)
  local out, line = {}, ''
  for word in s:gmatch('[^ \t]+') do
    local cand = line == '' and word or (line .. ' ' .. word)
    if line ~= '' and width(f, cand) > maxw then out[#out + 1] = line; line = word else line = cand end
  end
  out[#out + 1] = line
  return out
end

local DAYS = { 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday' }
local MONTHS = { 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December' }

-- the date from the clock: local days since 1970 -> weekday, day, month (civil-from-days)
local function today()
  local ok, t = pcall(function() return ctx.clock:now() end)
  if not ok or type(t) ~= 'table' or not tonumber(t.epoch_sec) then return '' end
  local e = math.floor(tonumber(t.epoch_sec))
  if tonumber(t.hour) then
    local wall = tonumber(t.hour) * 3600 + (tonumber(t.minute) or 0) * 60 + (tonumber(t.second) or 0)
    local off = (wall - e % 86400) % 86400
    if off > 14 * 3600 then off = off - 86400 end
    e = e + math.floor(off / 900 + 0.5) * 900
  end
  local z = e // 86400
  local weekday = (z + 4) % 7 + 1
  z = z + 719468
  local era = z // 146097
  local doe = z - era * 146097
  local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
  local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
  local mp = (5 * doy + 2) // 153
  local d = doy - (153 * mp + 2) // 5 + 1
  local m = mp < 10 and mp + 3 or mp - 9
  return DAYS[weekday] .. ', ' .. d .. ' ' .. MONTHS[m]
end

function on_draw(c, gg)
  if not gg then return end
  local ok, err = pcall(function()
    gg:clear(0)
    local text = read('lock.txt') or ''
    local name, rest = text:match('^([^\n]*)\n?(.*)$')
    gg:text(24, 24, today(), { font = font('medium') })
    gg:text(24, 64, name or 'Tasks', { font = font('large') })
    gg:line(24, 104, W - 24, 104)
    local y, n, shown = 124, 0, 0
    local items = {}
    for line in ((rest or '') .. '\n'):gmatch('([^\n]*)\n') do if line:match('%S') then items[#items + 1] = line end end
    local f = font('large')
    for _k, it in ipairs(items) do
      local lines_ = wrap(it, f, W - 96)
      local h = #lines_ * (line_h('large') + 4) + 14
      if y + h > H - 50 then break end
      gg:rect(28, y + 4, 26, 26, { line_width = 3 })
      for j, l in ipairs(lines_) do gg:text(70, y + (j - 1) * (line_h('large') + 4), l, { font = f }) end
      y = y + h
      shown = shown + 1
    end
    if #items == 0 then gg:text(24, 140, 'Nothing to do.', { font = font('large') }) end
    if shown < #items then gg:text(24, H - 40, '+ ' .. (#items - shown) .. ' more', { font = font('medium') }) end
  end)
  if not ok then pcall(function() gg:text(10, 760, 'lock error: ' .. tostring(err):sub(1, 40)) end) end
end

function on_load() end
function on_tick() end
function on_input() return false end
