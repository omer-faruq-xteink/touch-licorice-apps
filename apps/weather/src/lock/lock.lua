-- Lock-screen entry for Weather (API 2.9; bundle.py puts src/wx.lua in front as `X`). Shows the
-- forecast the app saved in forecast.txt: the temperature large, the sky, today's low and high and
-- the next days. When the forecast is over an hour old it asks Open-Meteo again, if the reader
-- lets a locked app use the network (if not, it says how old the forecast is).

local W, H = 480, 800
local STALE_S = 60 * 60
-- store: cut (the store's API gives a lock screen no network; tools/store_export.py drops this)
local asked_at = nil
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

-- store: cut
local function try_refresh(fc)
  local t = {}
  for k, v in (read('settings.txt') or ''):gmatch('([%w_]+)=([^\n]*)') do t[k] = v end
  local lat, lon = tonumber(t.lat), tonumber(t.lon)
  if not lat or (asked_at and now_sec() - asked_at < 15 * 60) then return end
  asked_at = now_sec()
  pcall(function()
    ctx.net:request({ url = X.forecast_url(lat, lon, t.unit == 'F' and 'F' or 'C'), method = 'GET', timeout_ms = 30000 }, function(c, resp)
      pcall(function()
        if type(resp) ~= 'table' or type(resp.body) ~= 'string' then return end
        local d = ctx.json:decode(resp.body)
        if type(d) ~= 'table' then return end
        ctx.storage:write('forecast.txt', X.cache_text(d, t.name or fc.place, t.unit == 'F' and 'F' or 'C', now_sec()))
        pcall(function() ctx:invalidate() end)
      end)
    end)
  end)
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
    -- store: cut
    if age > STALE_S then try_refresh(fc) end
    -- store: end
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
    local mins = age // 60
    gg:text(24, H - 40, mins < 90 and ('updated ' .. mins .. ' min ago') or ('updated ' .. (mins // 60) .. ' h ago'), { font = font('small') })
  end)
  if not ok then pcall(function() gg:text(10, 760, 'lock error: ' .. tostring(err):sub(1, 40)) end) end
end

function on_load() end
function on_tick() end
function on_input() return false end
