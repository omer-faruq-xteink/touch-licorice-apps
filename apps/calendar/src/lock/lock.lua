-- Lock-screen entry for Calendar (API 2.9; bundle.py puts src/cal.lua and src/views.lua in front).
-- Shows today's date and the view chosen in the app's Settings (Agenda, Day from the current hour
-- on as far as the screen goes, Week or Month) from
-- the calendars the app saved. When they are older than the sync interval it fetches them again,
-- at most once an hour, if the reader lets a locked app use the network.

local C = require('cal')
local V = require('views')
local W, H = 480, 800
local DAY = 86400
local asked_at = nil

local function read(name)
  local ok, s = pcall(function() return ctx.storage:read(name) end)
  return (ok and type(s) == 'string') and s or nil
end
local function font(name) return ctx.fonts and ctx.fonts[name] end
local function lh(name)
  local ok, h = pcall(function() return font(name).line_height end)
  return (ok and tonumber(h)) or (name == 'large' and 30 or name == 'small' and 20 or 24)
end
local function kv(s)
  local t = {}
  for k, v in (s or ''):gmatch('([%w_]+)=([^\n]*)') do t[k] = v end
  return t
end

local function try_refresh(cals, every, e, t)
  if asked_at and e - asked_at < 3600 then return end
  local q = {}
  for _k, c in ipairs(cals) do
    if c.on and (not c.updated or e - c.updated > every) then q[#q + 1] = c end
  end
  if #q == 0 then return end
  asked_at = e
  local function nxt()
    local c = table.remove(q, 1)
    if not c then
      pcall(function() ctx.invalidate() end)
      return
    end
    local ok = pcall(function()
      local opts, via = C.request(c.url, { host = t.host, auth = t.auth }, t.plain ~= '1')
      ctx.net:request(opts, function(cc, resp)
        pcall(function()
          local body = C.answer(resp, via)                 -- nil when cut off: the old copy stays
          if not body then return end
          local e2, off2 = C.clock()
          local events = C.parse_ics(body, off2, (e2 + off2) // DAY)
          ctx.storage:write(C.cache_name(c.url), C.cache_text(events, e2, off2, #body))
        end)
        nxt()
      end)
    end)
    if not ok then nxt() end
  end
  nxt()
end

function on_draw(c, gg)
  if not gg then return end
  local ok, err = pcall(function()
    gg:clear(0)
    local e, off = C.clock()
    local wall = e + off
    local today = wall // DAY
    local t = kv(read('settings.txt'))
    local mode = (t.lock == 'day' or t.lock == 'week' or t.lock == 'month') and t.lock or 'agenda'
    local ws = t.ws == '0' and 0 or 1
    local cals = C.parse_list(read('calendars.txt'))
    local oldest = nil
    for _k, cal in ipairs(cals) do
      local events, updated = C.load_cache(read(C.cache_name(cal.url)))
      cal.events, cal.updated = events, events and updated or nil
      if cal.on and (not oldest or (cal.updated or 0) < oldest) then oldest = cal.updated or 0 end
    end

    local y, m, d = C.civil(today)
    gg:text(24, 16, C.WDAY_LONG[C.wday(today) + 1], { font = font('large') })
    gg:text(24, 54, d .. ' ' .. C.MONTH[m] .. ' ' .. y, { font = font('medium') })
    if mode == 'week' or mode == 'month' then
      local s = V.title(mode, today, ws)
      gg:text(W - 24 - C.width(font('small'), s), 60, s, { font = font('small') })
    end
    gg:line(16, 92, W - 16, 92)
    gg:line(16, 93, W - 16, 93)
    if #cals == 0 then
      gg:text(24, 380, 'Calendar: open the app to add one.', { font = font('medium') })
      return
    end
    if oldest then try_refresh(cals, (tonumber(t.every) or 6) * 3600, e, t) end

    local top, bh = 104, H - 104 - 40
    local first, n = V.window(mode, today, ws)
    if mode == 'day' then n = 2 end              -- from this hour on, into tomorrow while it fits
    local env = { font = font, lh = lh, today = today, now = wall, ws = ws,
                  insts = C.between(cals, first * DAY, (first + n) * DAY, off) }
    if mode == 'month' then V.month(gg, env, today, 2, top, W - 4, bh)
    elseif mode == 'week' then V.week(gg, env, today, 4, top, W - 8, bh)
    elseif mode == 'day' then V.day(gg, env, today, 4, top, W - 8, bh, { from = wall % DAY // 3600, ph = 44 })
    else
      local rows = V.agenda_rows(env, today, n)
      V.agenda(gg, env, rows, 1, 4, top, W - 8, bh)
      if #rows == 0 then gg:text(24, top + 40, 'No events in the next 60 days.', { font = font('medium') }) end
    end
    if oldest then
      local mins = math.max(0, e - oldest) // 60
      local s = oldest == 0 and 'not synced yet' or mins < 90 and ('synced ' .. mins .. ' min ago') or
        mins < 2880 and ('synced ' .. (mins // 60) .. ' h ago') or ('synced ' .. (mins // 1440) .. ' days ago')
      gg:text(24, H - 32, s, { font = font('small') })
    end
  end)
  if not ok then pcall(function() gg:text(10, 760, 'lock error: ' .. tostring(err):sub(1, 40)) end) end
end

function on_load() end
function on_tick() end
function on_input() return false end
