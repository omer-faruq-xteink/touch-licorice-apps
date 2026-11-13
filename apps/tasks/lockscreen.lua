-- Lock-screen entry for Tasks: the open items of the list chosen in the app, from lock.txt (first
-- line: the list's name; then one item a line), with today's date. A ticked repeating item is
-- "<day it is due>\t<text>" (days since 1970) and shows from that day on.
-- A service's list (Todoist, Google Tasks, TickTick: settings.txt lock=<account>:<id>) is synced
-- while locked when the app's interval (every=, minutes; 0: never) has passed since the last sync
-- (remote_synced.txt): API 2.26 (firmware 26111201) gives the lock session ctx.net when the
-- manifest's lockscreen block has "net": true. Only then is lib/remote.lua loaded, and only that
-- list's account is synced; a local list never connects. The sync starts in on_load; a timer wake
-- holds its frame until it ends, the first session draws at once and again after it.
-- ctx.lock:done() ends the session once nothing is pending. Each session sets the next wake: the
-- chosen interval for a service's list, else an hour (aligned by the reader, so midnight comes too).

local W, H = 480, 800
local DAY = 86400
local MAX_WAKE_S = 3600         -- ctx.lock:set_interval takes 30-3600 s
local SLACK_S = 120             -- a wake may come early (seen: up to a minute)
local pending = false           -- a sync running in this session

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

-- the clock: UTC seconds and the UTC offset (its wall time decides the time zone); nil without one
local function clock()
  local ok, t = pcall(function() return ctx.clock:now() end)
  if not ok or type(t) ~= 'table' or not tonumber(t.epoch_sec) then return nil, 0 end
  local e = math.floor(tonumber(t.epoch_sec))
  local off = 0
  if tonumber(t.hour) then
    local wall = tonumber(t.hour) * 3600 + (tonumber(t.minute) or 0) * 60 + (tonumber(t.second) or 0)
    off = (wall - e % 86400) % 86400
    if off > 14 * 3600 then off = off - 86400 end
    off = math.floor(off / 900 + 0.5) * 900
  end
  return e, off
end

-- local days since 1970, nil without a clock
local function local_day()
  local e, off = clock()
  return e and (e + off) // DAY or nil
end

local function kv(s)
  local t = {}
  for k, v in (s or ''):gmatch('([%w_]+)=([^\n]*)') do t[k] = v end
  return t
end

-- when the list was synced, by the wall clock ("synced 14:05", "synced yesterday 19:00"): a time,
-- not an age, so the screen does not change between syncs
local function synced_text(at)
  local e, off = clock()
  if not e or not at then return nil end
  local days = (e + off) // DAY - (at + off) // DAY
  local hm = string.format('%02d:%02d', (at + off) % DAY // 3600, (at + off) % 3600 // 60)
  if days <= 0 then return 'synced ' .. hm end
  return days == 1 and ('synced yesterday ' .. hm) or ('synced ' .. days .. ' days ago')
end

-- store: cut (the store's API gives a lock screen no network; tools/store_export.py drops this)
local holding = false           -- an early wake waiting for the aligned time it was woken for
-- a service's list on the lock screen: sync its account when due, then write lock.txt again
local function try_sync(key, every)
  if not ctx.net or not key:find(':', 1, true) then return end
  local e = clock()
  local at = tonumber(read('remote_synced.txt'))
  if not e or every <= 0 or (at and e - at < every - SLACK_S) then return end
  local env = {}
  env.kit = {
    read = read,
    write = function(name, s) pcall(function() ctx.storage:write(name, s) end) end,
    refresh = function() end,
  }
  local R
  local function write_lock()
    for _k, l in ipairs(R.lists()) do
      if ((l.acc or l.src) .. ':' .. tostring(l.rid)) == key then
        local open = {}
        for _j, it in ipairs(l.items) do if not it.done then open[#open + 1] = it.text end end
        env.kit.write('lock.txt', l.name .. '\n' .. table.concat(open, '\n'))
      end
    end
  end
  env.changed = function()
    if not pending then return end
    if R.busy() then return end                       -- a sync step, not its end
    pending = false
    pcall(write_lock)
    pcall(function() ctx:invalidate() end)            -- draw again; that draw ends the session
  end
  local ok = pcall(function()
    R = require('lib.remote')(env)
    R.load()
  end)
  if not ok or not R.configured() then return end
  local acc = key:match('^(.-):')
  pending = true
  pcall(function() R.sync(acc) end)
  if not R.busy() then pending = false end            -- nothing went out
end

-- A timer wake comes up to a minute early; one that ends before the aligned time it was woken for
-- gets a second wake at that time (Calendar: 14:59:37 then 15:00:01). So an early session holds with
-- ctx:after (it runs in a 2.26 lock session and keeps it open: Lock Probe 1.9) until 2 s past it.
local function hold_if_early()
  if not (ctx.lock and ctx.lock.reason == 'timer') then return end
  local e, off = clock()
  if not e then return end
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

-- the date: weekday, day, month (civil-from-days)
local function today()
  local z = local_day()
  if not z then return '' end
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
    local day = local_day()
    for line in ((rest or '') .. '\n'):gmatch('([^\n]*)\n') do
      local d, t = line:match('^(%d+)\t(.*)$')
      if d then
        if day and day >= tonumber(d) and t:match('%S') then items[#items + 1] = t end
      elseif line:match('%S') then items[#items + 1] = line end
    end
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
    -- a service's list: when it was synced
    local key = kv(read('settings.txt')).lock or ''
    local s = key:find(':', 1, true) and synced_text(tonumber(read('remote_synced.txt')))
    if s then gg:text(W - 24 - width(font('small'), s), H - 32, s, { font = font('small') }) end
  end)
  if not ok then pcall(function() gg:text(10, 760, 'lock error: ' .. tostring(err):sub(1, 40)) end) end
  -- store: cut
  if not pending and not holding then pcall(function() ctx.lock:done() end) end   -- 2.26: nothing more to wait for
  -- store: end
end

function on_load()
  -- store: cut
  pcall(function()
    local t = kv(read('settings.txt'))
    local key, every = t.lock or '', (tonumber(t.every) or 60) * 60
    local remote = key:find(':', 1, true) ~= nil
    try_sync(key, every)
    hold_if_early()
    -- the next wake: a service's list, the chosen interval itself; otherwise an hour (repeating items
    -- come back by day). At most an hour. The reader aligns wakes to the interval (15 min: :00 :15 :30
    -- :45; an hour: on the hour, so one comes at midnight); a computed rest of it only brought early
    -- wakes. The host goes back to the manifest's at every lock, so each session sets it.
    local nxt = (remote and every > 0) and math.min(every, MAX_WAKE_S) or MAX_WAKE_S
    pcall(function() ctx.lock:set_interval(nxt) end)
  end)
  -- store: end
end
function on_tick() end
function on_input() return false end
