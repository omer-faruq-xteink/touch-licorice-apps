-- Weather for XTOS Licorice, API 2.9 (uses tools/gamekit and src/wx.lua). Needs Wi-Fi.
--
-- The forecast from Open-Meteo (free, no key): now, the next 12 hours and 4 days, for a place
-- found by name (Open-Meteo's geocoding). Kept in forecast.txt, so it opens at once and the lock
-- screen (lockscreen.lua, built by bundle.py from src/lock/lock.lua and wx.lua) can show it. The app
-- fetches again when the forecast is over 30 minutes old, or on Refresh.

local X = require('wx')
local W, H = kit.W, kit.H
local BTN_Y, BTN_H = 704, 64
local STALE_S = 30 * 60
local UA = 'XteinkLicoriceWeather/1.0 (https://github.com/omer-faruq/touch-licorice-apps)'

local cfg = { name = nil, lat = nil, lon = nil, unit = 'C', lock = false }
local fc = nil                  -- the forecast (X.parse_cache)
local screen = 'main'           -- main | places
local places = {}
local status, busy_label, ERR = nil, nil, nil

local function now_sec()
  local ok, t = pcall(function() return ctx.clock:now() end)
  return (ok and type(t) == 'table' and tonumber(t.epoch_sec)) and math.floor(tonumber(t.epoch_sec)) or 0
end
local function hhmm(epoch)
  local ok, t = pcall(function() return ctx.clock:now() end)
  if not epoch or not ok or type(t) ~= 'table' or not tonumber(t.hour) then return '' end
  -- the wall clock now, moved back by the age of the forecast
  local wall = tonumber(t.hour) * 3600 + (tonumber(t.minute) or 0) * 60 - (now_sec() - epoch)
  wall = wall % 86400
  return string.format('%02d:%02d', wall // 3600, (wall % 3600) // 60)
end

------------------------------------------------------------------ storage

local function save_cfg()
  kit.write('settings.txt', 'name=' .. (cfg.name or '') .. '\nlat=' .. (cfg.lat or '') .. '\nlon=' .. (cfg.lon or '') ..
    '\nunit=' .. cfg.unit .. '\nlock=' .. tostring(cfg.lock))
end
local function load_cfg()
  local t = kit.kv(kit.read('settings.txt'))
  cfg.name = (t.name and t.name ~= '') and t.name or nil
  cfg.lat, cfg.lon = tonumber(t.lat), tonumber(t.lon)
  cfg.unit = t.unit == 'F' and 'F' or 'C'
  cfg.lock = t.lock == 'true'
  fc = X.parse_cache(kit.read('forecast.txt'))
end

------------------------------------------------------------------ network

local function keep_wifi() pcall(function() ctx.net:keep_wifi(5 * 60 * 1000) end) end

local pending = nil
local function get(url, label, on_done)
  if pending then return end
  keep_wifi()
  busy_label, pending = label, { since = kit.now_ms() }
  local job = pending
  local ok, err = pcall(function()
    ctx.net:request({ url = url, method = 'GET', headers = { ['User-Agent'] = UA }, timeout_ms = 30000 }, function(c, resp)
      if pending ~= job then return end
      pending, busy_label = nil, nil
      local okh, e = pcall(function()
        if type(resp) ~= 'table' or type(resp.body) ~= 'string' then on_done(nil, 'no answer'); return end
        local code = tonumber(resp.status) or tonumber(resp.code)
        if code and code >= 400 then on_done(nil, 'HTTP ' .. code); return end
        local okj, data = pcall(function() return ctx.json:decode(resp.body) end)
        if not okj or type(data) ~= 'table' then on_done(nil, 'not JSON'); return end
        on_done(data)
      end)
      if not okh then status = 'Error: ' .. kit.short(tostring(e), 40) end
      kit.refresh()
    end)
  end)
  if not ok then pending, busy_label, status = nil, nil, 'Could not ask: ' .. kit.short(tostring(err), 30) end
end

local function refresh_forecast()
  if not cfg.lat then status = 'Choose a place first.'; return end
  get(X.forecast_url(cfg.lat, cfg.lon, cfg.unit), 'Getting the forecast...', function(d, err)
    if not d then status = 'Forecast failed: ' .. tostring(err); return end
    local text = X.cache_text(d, cfg.name, cfg.unit, now_sec())
    kit.write('forecast.txt', text)
    fc = X.parse_cache(text)
    status = nil
  end)
end

local function find_place(q)
  get('https://geocoding-api.open-meteo.com/v1/search?count=8&language=en&format=json&name=' ..
      q:gsub('[^A-Za-z0-9%-%._~]', function(c) return string.format('%%%02X', c:byte()) end),
      'Looking for ' .. kit.short(q, 20) .. '...', function(d, err)
    if not d then status = 'Search failed: ' .. tostring(err); return end
    places = {}
    for _k, p in ipairs(d.results or {}) do
      local where = {}
      if p.admin1 then where[#where + 1] = tostring(p.admin1) end
      if p.country then where[#where + 1] = tostring(p.country) end
      places[#places + 1] = { name = tostring(p.name), lat = tonumber(p.latitude), lon = tonumber(p.longitude),
                              where = table.concat(where, ', ') }
    end
    screen, status = 'places', (#places == 0 and 'No place by that name.' or nil)
  end)
end

local function ask_place()
  ctx.input:text({ title = 'Place (city or town)', value = '' }, function(c, s)
    if s and s:match('%S') then find_place(s) end
    kit.refresh()
  end)
end

------------------------------------------------------------------ lock screen

local function toggle_lock()
  local L = ctx.lockscreen
  cfg.lock = not cfg.lock
  save_cfg()
  if not L then status = 'This firmware has no app lock screen.'; return end
  local okd, isdef = pcall(function() return L:is_default() end)
  if cfg.lock then
    if not (okd and isdef == true) then pcall(function() L:set_default() end) end
    status = 'Lock screen: the forecast.'
  else
    if okd and isdef == true then pcall(function() L:clear_default() end) end
    status = 'Lock screen: off.'
  end
end

------------------------------------------------------------------ drawing

local function deg(v) return v and (tostring(v) .. '°') or '-' end

local function draw_main(gg)
  if not fc then
    gg:text(16, 16, 'Weather', { font = kit.font('large') })
    gg:text(16, 140, cfg.lat and 'Tap Refresh for the forecast.' or 'Tap Place to choose where.', { font = kit.font('medium') })
    return
  end
  gg:text(16, 12, kit.short(fc.place, 24), { font = kit.font('large') })
  gg:text(16, 50, 'updated ' .. hhmm(fc.updated) .. (now_sec() - (fc.updated or 0) > STALE_S and '  (old)' or ''), { font = kit.font('small') })
  gg:line(0, 80, W, 80)
  -- now: a big temperature, the icon and the details
  local kind, text = X.kind(fc.now_code)
  local temp = fc.now_t and tostring(fc.now_t) or '-'
  local x = X.big_number(gg, temp, 24, 104, 96)
  gg:text(x + 2, 100, '°' .. fc.unit, { font = kit.font('large') })
  X.icon(gg, kind, W - 140, 92, 120)
  gg:text(24, 212, text, { font = kit.font('large') })
  gg:text(24, 250, 'feels ' .. deg(fc.now_feel) .. '   humidity ' .. (fc.now_hum or '-') .. '%   wind ' .. (fc.now_wind or '-') .. ' km/h',
          { font = kit.font('small') })
  gg:line(0, 282, W, 282)
  -- the next 12 hours, every second hour
  local col = W // 6
  for k = 1, 6 do
    local h = fc.hours[(k - 1) * 2 + 1]
    if h then
      local cx = (k - 1) * col
      gg:text(cx + 10, 292, h.time, { font = kit.font('small') })
      X.icon(gg, (X.kind(h.code)), cx + 14, 316, 48)
      gg:text(cx + 14, 370, deg(h.temp), { font = kit.font('medium') })
      gg:text(cx + 14, 398, (h.rain or 0) .. '%', { font = kit.font('small') })
    end
  end
  gg:line(0, 428, W, 428)
  -- the days
  for k, d in ipairs(fc.days) do
    local y = 440 + (k - 1) * 62
    gg:text(16, y + 16, k == 1 and 'Today' or X.weekday(d.date), { font = kit.font('medium') })
    X.icon(gg, (X.kind(d.code)), 110, y + 4, 52)
    gg:text(180, y + 16, deg(d.lo) .. ' / ' .. deg(d.hi), { font = kit.font('medium') })
    gg:text(340, y + 18, 'rain ' .. (d.rain or 0) .. '%', { font = kit.font('small') })
  end
end

local function draw_places(gg)
  gg:text(16, 16, 'Choose the place', { font = kit.font('large') })
  gg:line(0, 80, W, 80)
  for k, p in ipairs(places) do
    local y = 90 + (k - 1) * 74
    gg:text(20, y + 6, kit.short(p.name, 30), { font = kit.font('medium') })
    gg:text(20, y + 36, kit.short(p.where, 46), { font = kit.font('small') })
    gg:line(16, y + 68, W - 16, y + 68)
  end
end

local function buttons()
  if screen == 'places' then return { 'Back', 'Search again' } end
  return { 'Refresh', 'Place', '°' .. (cfg.unit == 'C' and 'F' or 'C'), cfg.lock and 'Lock off' or 'Lock' }
end
local function button_rect(k, n)
  local bw = math.floor((W - 24 - (n - 1) * 8) / n)
  return 12 + (k - 1) * (bw + 8), BTN_Y, bw, BTN_H
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    gg:clear(0)
    if kit.modal() then kit.draw_modal(gg); return end
    if screen == 'places' then draw_places(gg) else draw_main(gg) end
    local line = busy_label or status or ERR
    if line then gg:text(12, BTN_Y - 30, kit.short(line, 48), { font = kit.font('small') }) end
    local bs = buttons()
    for k, b in ipairs(bs) do
      local x, y, bw, bh = button_rect(k, #bs)
      kit.button(gg, x, y, bw, bh, b, { font = 'medium' })
    end
  end)
  if not ok then pcall(function() gg:text(8, H - 60, kit.short('draw ERR ' .. tostring(e), 46)) end) end
end

------------------------------------------------------------------ input

local function tap(x, y)
  if kit.tap_modal(x, y) then return end
  local bs = buttons()
  for k, b in ipairs(bs) do
    local bx, by, bw, bh = button_rect(k, #bs)
    if x >= bx and x < bx + bw and y >= by and y < by + bh then
      status = nil
      if b == 'Refresh' then refresh_forecast()
      elseif b == 'Place' or b == 'Search again' then ask_place()
      elseif b == 'Back' then screen = 'main'
      elseif b == 'Lock' or b == 'Lock off' then toggle_lock()
      else
        cfg.unit = cfg.unit == 'C' and 'F' or 'C'
        save_cfg()
        refresh_forecast()
      end
      return
    end
  end
  if screen == 'places' and y >= 90 then
    local p = places[(y - 90) // 74 + 1]
    if p then
      cfg.name, cfg.lat, cfg.lon = p.name, p.lat, p.lon
      save_cfg()
      screen = 'main'
      refresh_forecast()
    end
  end
end

function on_input(c, ev)
  ERR = nil
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    if ev.type == 'pointer' and ev.phase == 'up' then tap(ev.x or 0, ev.y or 0)
    elseif ev.type == 'key' and kit.key_accepted(ev) then
      if kit.modal() then
        if ev.key == 'back' and kit.modal().cancel then kit.modal().cancel() end
      elseif ev.key == 'back' and screen == 'places' then screen = 'main' end
    end
  end)
  if not ok then ERR = tostring(e) end
  kit.refresh()
  return true
end

function on_load(c)
  local ok, e = pcall(load_cfg)
  if not ok then ERR = tostring(e) end
  -- an old forecast (or none) is fetched again at once
  if cfg.lat and (not fc or now_sec() - (fc.updated or 0) > STALE_S) then refresh_forecast() end
end
function on_leave() pcall(function() ctx.net:keep_wifi(1) end) end

if rawget(_G, '__TEST') then
  __TEST.api = { X = X, fc = function() return fc end, cfg = cfg, screen = function() return screen end,
                 places = function() return places end, status = function() return status end }
end
