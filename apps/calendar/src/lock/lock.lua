-- Lock-screen entry for Calendar (bundle.py puts src/cal.lua and src/views.lua in front).
-- Shows today's date and the view chosen in the app's Settings (Agenda, Day from the current hour
-- on as far as the screen goes, Week or Month) from the calendars the app saved, and when they were
-- synced. Calendars that are switched on, on the internet (not My calendar) and older than the
-- app's sync interval are fetched again while locked: API 2.26 (firmware 26111201) gives the lock
-- session ctx.net when the manifest's lockscreen block has "net": true. With none to fetch it does
-- not connect. The requests go out in on_load; a timer wake holds its frame until the answers, the
-- first session draws at once and again after them. ctx.lock:done() ends the session once nothing
-- is pending. Each session sets the next wake an hour away; the reader aligns wakes to it, so they
-- come on the hour (the Day view's next hour, midnight). The manifest's interval_sec (3600) also
-- bounds how often the lock screen gets the network.

local C = require('cal')
local V = require('views')
local W, H = 480, 800
local DAY = 86400
local MAX_WAKE_S = 3600         -- ctx.lock:set_interval takes 30-3600 s
local SLACK_S = 120             -- a wake may come early (seen: up to a minute)
local pending = false           -- requests out in this session
-- store: cut (the store's API gives a lock screen no network; tools/store_export.py drops this)
local asked = false
local holding = false           -- an early wake waiting for the aligned time it was woken for

-- A timer wake comes up to a minute early; one that ends before the aligned time it was woken for
-- gets a second wake at that time (seen: 14:59:37 then 15:00:01). So an early session holds with
-- ctx:after (it runs in a 2.26 lock session and keeps it open: Lock Probe 1.9) until 2 s past it.
local function hold_if_early(e, off)
  if not (ctx.lock and ctx.lock.reason == 'timer') then return end
  local iv = tonumber(ctx.lock.interval_sec) or MAX_WAKE_S
  local rem = (iv - (e + off) % iv) % iv
  if rem == 0 or rem > SLACK_S then return end
  local ok, tm = pcall(function()
    return ctx:after((rem + 2) * 1000, function()
      holding = false
      pcall(function() ctx:invalidate() end)          -- draw again; that draw ends the session
    end)
  end)
  holding = ok and tm ~= nil
end
-- store: end

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

-- the calendars with their caches; oldest: the oldest sync of those that are fetched (nil: none)
local function load_cals()
  local cals = C.parse_list(read('calendars.txt'))
  local oldest = nil
  for _k, cal in ipairs(cals) do
    local events, updated = C.load_cache(read(C.cache_name(cal.url)))
    cal.events, cal.updated = events, events and updated or nil
    -- My calendar is on the reader: it is never synced
    if cal.on and not C.is_local(cal.url) and (not oldest or (cal.updated or 0) < oldest) then oldest = cal.updated or 0 end
  end
  return cals, oldest
end

-- when the calendars were synced, by the wall clock ("synced 14:05", "synced yesterday 19:00"):
-- a time, not an age, so the screen does not change between syncs
local function synced(oldest, e, off)
  if oldest == 0 then return 'not synced yet' end
  local wall, at = e + off, oldest + off
  local days = wall // DAY - at // DAY
  local hm = string.format('%02d:%02d', at % DAY // 3600, at % 3600 // 60)
  if days <= 0 then return 'synced ' .. hm end
  return days == 1 and ('synced yesterday ' .. hm) or ('synced ' .. days .. ' days ago')
end

-- store: cut
-- the wake log: one line a session and one a calendar, the last 20, in wakes.txt (private storage:
-- XTApps/calendar/files/ on the card), to see what the lock screen did while nobody looked
local function wlog(s)
  pcall(function()
    local _e, _off = C.clock()
    local w = (_e + _off) % DAY
    local lines = {}
    for l in (read('wakes.txt') or ''):gmatch('[^\n]+') do lines[#lines + 1] = l end
    lines[#lines + 1] = string.format('%02d:%02d:%02d ', w // 3600, w % 3600 // 60, w % 60) .. s
    while #lines > 20 do table.remove(lines, 1) end
    ctx.storage:write('wakes.txt', table.concat(lines, '\n') .. '\n')
  end)
end
local function ms() local ok, v = pcall(function() return ctx.clock:millis() end); return ok and tonumber(v) or 0 end
local READ_MS = 700             -- reading a calendar stops here (a callback has about a second)
local BIG = 65536               -- above this, only the events the lock screen needs are read

-- read one calendar's answer and save it; -> what happened, for the log
local function take(c, resp)
  local body, why = C.answer(resp)                  -- nil when cut off: the old copy stays
  if not body then return c.name .. ': ' .. tostring(why) end
  local t0, size = ms(), #body
  local e2, off2 = C.clock()
  local today = (e2 + off2) // DAY
  if size > BIG then
    -- a big one (years of history): only what matters from the parser's window on (62 days back)
    body = C.trim_ics(body, today - 63)
    C.free()
  end
  local p = C.parser(body, off2, today)
  local done = false
  while not done do
    done = p.step(16384)
    if not done and ms() - t0 > READ_MS then
      return c.name .. ': ' .. (size // 1024) .. ' KB, gave up after ' .. (ms() - t0) .. ' ms (the old copy stays)'
    end
  end
  ctx.storage:write(C.cache_name(c.url), C.cache_text(p.events, e2, off2, size))
  return string.format('%s: %d KB -> %d KB, %d events, %d ms', c.name, size // 1024, #body // 1024, #p.events, ms() - t0)
end

-- -> what it did, for the log: 'fetch N', 'nothing due', 'no network on the lock screen'
local function try_refresh(cals, every, e, t)
  if asked then return 'fetch' end
  local q = {}
  for _k, c in ipairs(cals) do
    if c.on and not C.is_local(c.url) and (not c.updated or e - c.updated >= every - SLACK_S) then q[#q + 1] = c end
  end
  if #q == 0 then return 'nothing due' end
  if not ctx.net then return 'no network on the lock screen' end
  asked, pending = true, true
  local n = #q
  local function nxt()
    local c = table.remove(q, 1)
    if not c then
      pending = false
      pcall(function() ctx:invalidate() end)          -- draw again; that draw ends the session
      return
    end
    local ok = pcall(function()
      C.fetch(c.url, t.plain ~= '1' and t.gz == 'ok', function(resp)    -- redirects followed
        local okt, what = pcall(take, c, resp)
        wlog(okt and what or (c.name .. ': error ' .. tostring(what)))
        C.free()
        nxt()
      end)
    end)
    if not ok then wlog(c.name .. ': could not ask'); nxt() end
  end
  nxt()
  return 'fetch ' .. n
end
-- store: end

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
    local cals, oldest = load_cals()

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
    if oldest then gg:text(24, H - 32, synced(oldest, e, off), { font = font('small') }) end
  end)
  if not ok then pcall(function() gg:text(10, 760, 'lock error: ' .. tostring(err):sub(1, 40)) end) end
  -- store: cut
  if not pending and not holding then pcall(function() ctx.lock:done() end) end   -- 2.26: nothing more to wait for
  -- store: end
end

function on_load()
  -- store: cut
  pcall(function()
    local e, off = C.clock()
    local t = kv(read('settings.txt'))
    local every = (tonumber(t.every) or 6) * 3600
    local cals, oldest = load_cals()
    local did = oldest and try_refresh(cals, every, e, t) or 'nothing to fetch'
    hold_if_early(e, off)
    if holding then did = did .. '; early: held past the hour' end
    -- elapsed and interval as the host reports them: to see why a wake comes (two an hour were seen)
    wlog(string.format('%s elapsed %s interval %s lock.net %s: %s', ctx.lock and tostring(ctx.lock.reason) or '?',
      ctx.lock and tostring(ctx.lock.elapsed_sec) or '?', ctx.lock and tostring(ctx.lock.interval_sec) or '?',
      ctx.lock and tostring(ctx.lock.net) or '?', did))
    -- the next wake: an hour (the shortest sync interval, and the longest wake the host allows). The
    -- reader aligns wakes to the interval, so they come on the hour: the Day view's next hour and
    -- midnight come by themselves; a computed rest of the interval only brought early wakes. The host
    -- goes back to the manifest's at every lock, so each session sets it.
    pcall(function() ctx.lock:set_interval(MAX_WAKE_S) end)
  end)
  -- store: end
end
function on_tick() end
function on_input() return false end
