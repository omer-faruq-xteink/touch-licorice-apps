-- Lock-screen entry for Weather (bundle.py puts src/wx.lua in front as `X`). Shows the forecast the
-- app saved in forecast.txt: the temperature large, the sky, today's low and high and the next days.
-- When the forecast is as old as the app's "every" setting (15 minutes to 6 hours; 0: never), or a new
-- day has begun, it asks Open-Meteo again while locked: API 2.26 (firmware 26111201) gives the lock
-- session ctx.net when the manifest's lockscreen block has "net": true. The request goes out in
-- on_load; a timer wake holds its frame until the answer, the first session draws at once and again
-- after it. ctx.lock:done() ends the session once nothing is pending. Each session sets the next wake
-- for when the next fetch is due (at most an hour away, the longest the host allows).

local W, H = 480, 800
local MAX_WAKE_S = 3600        -- ctx.lock:set_interval takes 30-3600 s
local SLACK_S = 120             -- a wake may come early (seen: up to a minute before the quarter hour)
local pending = false           -- a request out in this session
-- store: cut (the store's API gives a lock screen no network; tools/store_export.py drops this)
local asked = false
local holding = false           -- an early wake waiting for the aligned time it was woken for
-- store: end

local function read(name)
  local ok, s = pcall(function() return ctx.storage:read(name) end)
  return (ok and type(s) == 'string') and s or nil
end
local function font(name) return ctx.fonts and ctx.fonts[name] end
local function now_sec()
  local ok, t = pcall(function() return ctx.clock:now() end)
  return (ok and type(t) == 'table' and tonumber(t.epoch_sec)) and math.floor(tonumber(t.epoch_sec)) or 0
end

-- when the forecast was fetched, by the wall clock: "updated 14:05", "updated yesterday 22:10" or
-- "updated 3 days ago" (a time, not an age, so the screen stays the same between fetches)
local function stamp(age)
  local ok, t = pcall(function() return ctx.clock:now() end)
  if not ok or type(t) ~= 'table' or not tonumber(t.hour) then return '' end
  local wall = tonumber(t.hour) * 3600 + (tonumber(t.minute) or 0) * 60 + (tonumber(t.second) or 0) - age
  local days = -(wall // 86400)                       -- 0: today, 1: yesterday
  local hm = string.format('%02d:%02d', wall % 86400 // 3600, wall % 3600 // 60)
  if days <= 0 then return 'updated ' .. hm end
  return days == 1 and ('updated yesterday ' .. hm) or ('updated ' .. days .. ' days ago')
end

-- store: cut
-- the wake log: one line a session and one an answer, the last 20, in wakes.txt (private storage:
-- XTApps/weather/files/ on the card), to see what the lock screen did while nobody looked
local function hm_now()
  local ok, t = pcall(function() return ctx.clock:now() end)
  if not ok or type(t) ~= 'table' or not tonumber(t.hour) then return '--:--' end
  return string.format('%02d:%02d', t.hour, tonumber(t.minute) or 0)
end
local function wlog(s)
  pcall(function()
    local lines = {}
    for l in (read('wakes.txt') or ''):gmatch('[^\n]+') do lines[#lines + 1] = l end
    lines[#lines + 1] = hm_now() .. ' ' .. s
    while #lines > 20 do table.remove(lines, 1) end
    ctx.storage:write('wakes.txt', table.concat(lines, '\n') .. '\n')
  end)
end
-- A timer wake comes up to a minute early; one that ends before the aligned time it was woken for
-- gets a second wake at that time (Calendar: 14:59:37 then 15:00:01). So an early session holds with
-- ctx:after (it runs in a 2.26 lock session and keeps it open: Lock Probe 1.9) until 2 s past it.
-- The intervals (15 min to an hour) divide the day, so the wall clock's seconds of the day will do.
local function hold_if_early()
  if not (ctx.lock and ctx.lock.reason == 'timer') then return end
  local ok, t = pcall(function() return ctx.clock:now() end)
  if not ok or type(t) ~= 'table' or not tonumber(t.hour) then return end
  local iv = tonumber(ctx.lock.interval_sec) or MAX_WAKE_S
  local w = tonumber(t.hour) * 3600 + (tonumber(t.minute) or 0) * 60 + (tonumber(t.second) or 0)
  local rem = (iv - w % iv) % iv
  if rem == 0 or rem > SLACK_S then return end
  local okt, tm = pcall(function()
    return ctx:after((rem + 2) * 1000, function()
      holding = false
      pcall(function() ctx:invalidate() end)          -- draw again; that draw ends the session
    end)
  end)
  holding = okt and tm ~= nil
end
local function mins(s) return s >= 3600 and string.format('%dh%02dm', s // 3600, s % 3600 // 60) or ((s // 60) .. 'm') end

-- ask Open-Meteo; what it did: 'fetch', 'fetch not sent: ...', 'no network on the lock screen', 'no place'
local function try_refresh(fc)
  if asked then return 'fetch' end
  if not ctx.net then return 'no network on the lock screen' end
  local t = {}
  for k, v in (read('settings.txt') or ''):gmatch('([%w_]+)=([^\n]*)') do t[k] = v end
  local lat, lon = tonumber(t.lat), tonumber(t.lon)
  if not lat then return 'no place' end
  asked = true
  local unit = t.unit == 'F' and 'F' or 'C'
  local ok, job, err = pcall(function()
    return ctx.net:request({ url = X.forecast_url(lat, lon, unit), method = 'GET', timeout_ms = 30000 }, function(c, resp)
      pending = false
      local okw, what = pcall(function()
        if type(resp) ~= 'table' then return 'reply: none' end
        local code = tonumber(resp.status) or tonumber(resp.code)
        if type(resp.body) ~= 'string' or resp.ok == false then return 'reply failed: ' .. tostring(resp.err) end
        if code and code >= 400 then return 'reply HTTP ' .. code end
        local d = ctx.json:decode(resp.body)
        if type(d) ~= 'table' then return 'reply not JSON' end
        ctx.storage:write('forecast.txt', X.cache_text(d, t.name or fc.place, unit, now_sec()))
        return 'reply ' .. tostring(code or 200)
      end)
      wlog(okw and what or ('reply error: ' .. tostring(what)))
      pcall(function() ctx:invalidate() end)            -- draw again (fresh or not); that draw ends the session
    end)
  end)
  pending = ok and job ~= nil
  if not pending then return 'fetch not sent: ' .. tostring(ok and err or job) end
  return 'fetch'
end
-- store: end

function on_draw(c, gg)
  if not gg then return end
  local ok, err = pcall(function()
    gg:clear(0)
    local fc = X.parse_cache(read('forecast.txt'))
    if not fc then
      gg:text(24, 380, 'Weather: open the app once to choose a place.', { font = font('medium') })
      return
    end
    local age = now_sec() - (fc.updated or 0)
    gg:text(24, 24, fc.place, { font = font('large') })
    local kind, text = X.kind(fc.now_code)
    local temp = fc.now_t and tostring(fc.now_t) or '-'
    local x = X.big_number(gg, temp, 24, 90, 150)
    gg:text(x + 4, 86, '°' .. fc.unit, { font = font('large') })
    X.icon(gg, kind, W - 190, 80, 170)
    gg:text(24, 262, text, { font = font('large') })
    local d1 = fc.days[1]
    if d1 then gg:text(24, 302, 'Today ' .. (d1.lo or '-') .. '° / ' .. (d1.hi or '-') .. '°   rain ' .. (d1.rain or 0) .. '%', { font = font('medium') }) end
    gg:line(24, 346, W - 24, 346)
    for k = 2, math.min(4, #fc.days) do
      local d = fc.days[k]
      local y = 366 + (k - 2) * 110
      gg:text(24, y + 30, X.weekday(d.date), { font = font('large') })
      X.icon(gg, (X.kind(d.code)), 140, y, 90)
      gg:text(260, y + 30, (d.lo or '-') .. '° / ' .. (d.hi or '-') .. '°', { font = font('large') })
      gg:text(260, y + 66, 'rain ' .. (d.rain or 0) .. '%', { font = font('small') })
    end
    gg:text(24, H - 40, stamp(age), { font = font('small') })
  end)
  if not ok then pcall(function() gg:text(10, 760, 'lock error: ' .. tostring(err):sub(1, 40)) end) end
  -- store: cut
  if not pending and not holding then pcall(function() ctx.lock:done() end) end   -- 2.26: nothing more to wait for
  -- store: end
end

function on_load()
  -- store: cut
  pcall(function()
    local fc = X.parse_cache(read('forecast.txt'))
    local every = (tonumber((read('settings.txt') or ''):match('every=(%d+)')) or 60) * 60
    local age = fc and (now_sec() - (fc.updated or 0)) or 0
    local okc, t = pcall(function() return ctx.clock:now() end)
    local clock_ok = okc and type(t) == 'table' and t.valid and tonumber(t.year) ~= nil
    local did = not fc and 'no forecast' or every == 0 and 'never' or 'not due'
    if fc and every > 0 then
      -- due (a wake may come a few seconds early), or a new day: the forecast's "Today" is yesterday
      if age >= every - SLACK_S then did = try_refresh(fc) end
      if clock_ok and fc.days[1] and fc.days[1].date < string.format('%04d-%02d-%02d', t.year, t.month, t.day) then
        did = try_refresh(fc) .. ' (new day)'
      end
    end
    -- the next wake: the chosen interval itself, at most an hour. The reader aligns wakes to multiples
    -- of the interval (15 min: :00 :15 :30 :45; an hour: on the hour, so one comes at midnight); a
    -- computed rest of the interval only brought early wakes. The host goes back to the manifest's
    -- 900 at every lock, so each session sets it.
    local nxt = (fc and every > 0) and math.min(every, MAX_WAKE_S) or MAX_WAKE_S
    hold_if_early()
    if holding then did = did .. '; early: held' end
    local oks, sa, sb = pcall(function() return ctx.lock:set_interval(nxt) end)
    local reason = ctx.lock and (tostring(ctx.lock.reason) .. ' lock.net ' .. tostring(ctx.lock.net)) or '?'
    wlog(string.format('%s age %s every %s: %s; next %s%s', reason, mins(math.max(0, age)), every > 0 and mins(every) or '-',
      did, mins(nxt), (oks and sb) and (' (set_interval: ' .. tostring(sa) .. ' ' .. tostring(sb) .. ')') or (not oks and ' (set_interval error)' or '')))
  end)
  -- store: end
end
function on_tick() end
function on_input() return false end
