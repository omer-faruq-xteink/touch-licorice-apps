-- Dates for the Calculator (loaded only when opened): two dates, typed as YYYYMMDD with the
-- calculator keys or set to today, with each one's weekday, day of the year and ISO week; the
-- days between them (and the same in weeks, and in years, months and days); and a date plus or
-- minus a number of days. Days are counted on the proleptic Gregorian calendar.

return function(api)
  local kit, D, W = api.kit, api.D, api.W
  local U = require('modes.ui')(api)
  local M = {}

  local function days_from_civil(y, m, d)
    y = m <= 2 and y - 1 or y
    local era = (y >= 0 and y or y - 399) // 400
    local yoe = y - era * 400
    local doy = (153 * (m > 2 and m - 3 or m + 9) + 2) // 5 + d - 1
    local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
    return era * 146097 + doe - 719468
  end

  local function civil(z)
    z = z + 719468
    local era = (z >= 0 and z or z - 146096) // 146097
    local doe = z - era * 146097
    local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
    local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
    local mp = (5 * doy + 2) // 153
    local d = doy - (153 * mp + 2) // 5 + 1
    local m = mp < 10 and mp + 3 or mp - 9
    return yoe + era * 400 + (m <= 2 and 1 or 0), m, d
  end

  local function leap(y) return (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0 end
  local MDAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
  local function month_days(y, m) return (m == 2 and leap(y)) and 29 or MDAYS[m] end

  local MONTHS = { 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September',
                   'October', 'November', 'December' }
  local WDAYS = { 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday' }
  local function weekday(day) return (day + 3) % 7 + 1 end          -- 1 = Monday (day 0 = Thu 1 Jan 1970)

  local function iso_week(day)
    local y = civil(day)
    local wd = weekday(day)
    local thursday = day - wd + 4
    local ty = civil(thursday)
    return (thursday - days_from_civil(ty, 1, 1)) // 7 + 1, ty ~= y and ty or nil
  end

  local function today()
    local ok, t = pcall(function() return ctx.clock:now() end)
    if not ok or type(t) ~= 'table' or not tonumber(t.epoch_sec) then return days_from_civil(2026, 11, 9) end
    local e = math.floor(tonumber(t.epoch_sec))
    if tonumber(t.hour) then
      local wall = tonumber(t.hour) * 3600 + (tonumber(t.minute) or 0) * 60 + (tonumber(t.second) or 0)
      local off = (wall - e % 86400) % 86400
      if off > 14 * 3600 then off = off - 86400 end
      off = math.floor(off / 900 + 0.5) * 900
      return (e + off) // 86400
    end
    return e // 86400
  end

  local function label(day)
    local y, m, d = civil(day)
    return WDAYS[weekday(day)]:sub(1, 3) .. ' ' .. d .. ' ' .. MONTHS[m]:sub(1, 3) .. ' ' .. y
  end

  local function ymd(day)
    local y, m, d = civil(day)
    return string.format('%04d%02d%02d', y, m, d)
  end

  -- a day plus n calendar months (31 Jan + 1 month = the last day of February)
  local function add_months(day, n)
    local y, m, d = civil(day)
    local t = y * 12 + (m - 1) + n
    local ny, nm = t // 12, t % 12 + 1
    return days_from_civil(ny, nm, math.min(d, month_days(ny, nm)))
  end

  -- years, months and days from a to b (a <= b): the most whole months that fit, then days
  local function span(a, b)
    local y1, m1 = civil(a)
    local y2, m2 = civil(b)
    local months = (y2 - y1) * 12 + (m2 - m1)
    if add_months(a, months) > b then months = months - 1 end
    return months // 12, months % 12, b - add_months(a, months)
  end

  local function plural(n, w) return n .. ' ' .. w .. (n == 1 and '' or 's') end

  local d1, d2 = nil, nil
  local add = 30
  local msg = nil
  local loaded_state = false

  local function save()
    api.write('dates.txt', 'd1=' .. d1 .. '\nd2=' .. d2 .. '\nadd=' .. add)
  end
  local function load()
    local s = api.read('dates.txt') or ''
    local t = today()
    d1 = math.tointeger(tonumber(s:match('d1=(%-?%d+)'))) or t
    d2 = math.tointeger(tonumber(s:match('d2=(%-?%d+)'))) or (t + 100)
    add = math.tointeger(tonumber(s:match('add=(%-?%d+)'))) or 30
  end

  local function parse_date(v)
    local n = D.small_int(v, 99991231)
    if not n or n < 10101 then return nil end
    local y, m, dd = n // 10000, n // 100 % 100, n % 100
    if m < 1 or m > 12 or dd < 1 or dd > month_days(y, m) then return nil end
    return days_from_civil(y, m, dd)
  end

  local function rows()
    local bw = 120
    return {
      { x = 12, y = 70, w = W - 36 - bw, h = 56, key = 'd1' }, { x = W - 12 - bw, y = 70, w = bw, h = 56, key = 'today1' },
      { x = 12, y = 202, w = W - 36 - bw, h = 56, key = 'd2' }, { x = W - 12 - bw, y = 202, w = bw, h = 56, key = 'today2' },
      { x = 12, y = 500, w = W - 24, h = 56, key = 'add' },
    }
  end

  local function info_lines(day)
    local wk, wy = iso_week(day)
    local y = civil(day)
    return WDAYS[weekday(day)] .. ', day ' .. (day - days_from_civil(y, 1, 1) + 1) .. ' of the year, ISO week ' .. wk .. (wy and (' of ' .. wy) or '')
  end

  function M.open()
    if not loaded_state then load(); loaded_state = true end
  end

  function M.draw(gg)
    U.header(gg, 'Dates', nil)
    for _k, r in ipairs(rows()) do
      if r.key == 'today1' or r.key == 'today2' then
        kit.button(gg, r.x, r.y, r.w, r.h, 'Today', { font = 'medium' })
      else
        gg:rect(r.x, r.y, r.w, r.h, { line_width = 2 })
        local s = r.key == 'add' and ('Days to add: ' .. add) or label(r.key == 'd1' and d1 or d2)
        U.text(gg, r.x + 12, r.y + 16, kit.short(s, 30), 'medium')
      end
    end
    U.note(gg, 134, info_lines(d1))
    U.note(gg, 266, info_lines(d2))
    local a, b = math.min(d1, d2), math.max(d1, d2)
    local n = d2 - d1
    U.text(gg, 16, 316, 'From the first to the second:', 'medium')
    U.text(gg, 16, 350, plural(n, 'day') .. (math.abs(n) >= 7 and ('  =  ' .. plural(math.abs(n) // 7, 'week') ..
           (math.abs(n) % 7 > 0 and (' ' .. plural(math.abs(n) % 7, 'day')) or '')) or ''), 'medium')
    local y, m, d = span(a, b)
    local parts = {}
    if y > 0 then parts[#parts + 1] = plural(y, 'year') end
    if m > 0 then parts[#parts + 1] = plural(m, 'month') end
    if d > 0 or #parts == 0 then parts[#parts + 1] = plural(d, 'day') end
    U.text(gg, 16, 384, (n < 0 and '- ' or '') .. table.concat(parts, ', '), 'medium')
    U.text(gg, 16, 418, 'Counting both days: ' .. plural(math.abs(n) + 1, 'day'))
    U.text(gg, 16, 572, 'First + ' .. add .. ':  ' .. label(d1 + add), 'medium')
    U.text(gg, 16, 606, 'First - ' .. add .. ':  ' .. label(d1 - add), 'medium')
    U.note(gg, 740, msg or 'Tap a date to type it as YYYYMMDD.')
  end

  function M.tap(x, y)
    if U.header_hit(x, y, nil) == 'calc' then api.close(); return end
    local r = U.hit(rows(), x, y)
    if not r then return end
    msg = nil
    if r.key == 'today1' then d1 = today(); save()
    elseif r.key == 'today2' then d2 = today(); save()
    elseif r.key == 'add' then
      U.ask_value('Days to add', function(v)
        local n = D.small_int(v, 3000000)
        if n then add = n; save() else msg = 'a whole number of days, please' end
      end)
    else
      local which = r.key
      U.ask_value('Date (YYYYMMDD)', function(v)
        local day = parse_date(v)
        if not day then msg = 'not a date: type it as YYYYMMDD, like 20261109'; return end
        if which == 'd1' then d1 = day else d2 = day end
        save()
      end, { tokens = { { t = 'num', s = ymd(which == 'd1' and d1 or d2) } } })
    end
  end

  function M.back() return false end

  if rawget(_G, '__TEST') then
    M.test = { span = span, iso_week = iso_week, days_from_civil = days_from_civil, label = label, parse_date = parse_date,
               set = function(a, b) d1, d2 = a, b end }
  end
  return M
end
