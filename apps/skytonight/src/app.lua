-- The app: the sky for now (or tonight, by day), -1 h / +1 h to step through the night (the page
-- keys too), Now to go back, Place to pick a city or type coordinates and to make Sky Tonight the
-- lock screen. While open on the current time it redraws every ten minutes.

local BTN_Y, BTN_H = H - 62, 50
local screen = 'sky'                             -- 'sky' or 'place'
local place, base, label, step = nil, nil, nil, 0
local page = 1
local PER_PAGE, ROW_Y, ROW_H = 10, 92, 54
local timer = nil

local function refresh() pcall(function() ctx:invalidate() end) end

local function is_lock()
  local ok, v = pcall(function() return ctx.lockscreen and ctx.lockscreen:is_default() end)
  return ok and v == true
end

-- base: the moment the view starts from; step: whole hours added by the buttons
local function reset_view(now_only)
  local t = clock_now()
  if not t then base = nil; return end
  if now_only then base, label = A.secs(t.epoch_sec), 'now'
  else base, label = default_view(t, place) end
  step = 0
end

local function schedule()
  pcall(function() if timer then timer:cancel() end end)
  timer = nil
  if label ~= 'now' or step ~= 0 then return end
  local ok, tm = pcall(function()
    return ctx:after(600000, function() reset_view(true); refresh(); schedule() end)
  end)
  timer = ok and tm or nil
end

local function buttons()
  if screen == 'place' then
    return {
      { word('coords'), function()
          local cur = string.format('%.2f, %.2f', place.lat, place.lon)
          pcall(function()
            ctx.input:text({ title = word('coords_title'), text = cur, max_bytes = 40 }, function(c, s)
              local la, lo = (s or ''):match('^%s*([-+]?[%d.]+)[%s,;]+([-+]?[%d.]+)%s*$')
              la, lo = tonumber(la), tonumber(lo)
              if la and lo and la >= -90 and la <= 90 and lo >= -180 and lo <= 180 then
                place = { name = string.format('%.1f°%s %.1f°%s', math.abs(la), la >= 0 and 'N' or 'S', math.abs(lo), lo >= 0 and 'E' or 'W'),
                          lat = la, lon = lo }
                save_place(place)
                screen = 'sky'; reset_view(false); schedule()
              end
              refresh()
            end)
          end)
        end },
      { is_lock() and word('lock_on') or word('lock_off'), function()
          if is_lock() then pcall(function() ctx.lockscreen:clear_default() end)
          else pcall(function() ctx.lockscreen:set_default() end) end
        end },
      { word('back'), function() screen = 'sky' end },
    }
  end
  return {
    { '-1 h', function() step = step - 1; schedule() end },
    { (label == 'now' and step == 0) and word('tonight') or word('now'), function()
        if label == 'now' and step == 0 then reset_view(false) else reset_view(true) end
        schedule()
      end },
    { '+1 h', function() step = step + 1; schedule() end },
    { word('place'), function()
        screen = 'place'
        for i, p in ipairs(PLACES) do
          if p[1] == place.name then page = (i - 1) // PER_PAGE + 1 end
        end
      end },
  }
end

local function button_rect(k, n)
  local gap = 10
  local bw = (W - 2 * 16 - (n - 1) * gap) // n
  return 16 + (k - 1) * (bw + gap), BTN_Y, bw, BTN_H
end

local function pages() return (#PLACES + PER_PAGE - 1) // PER_PAGE end

local function draw_place(g)
  local f_big, f_row, f_small = font_px(30), font_px(24), font_px(16)
  g:text(20, 16, word('place'), { font = f_big })
  g:rect(W - 156, 14, 140, 44, { radius = 8 })
  g:text(W - 86, 36, LANG_NAMES[LANG], { font = font_px(20), align = 'center', valign = 'middle' })
  g:text(20, 62, string.format('%.2f, %.2f  ·  ', place.lat, place.lon) .. word('tz_note'), { font = f_small })
  for r = 1, PER_PAGE do
    local i = (page - 1) * PER_PAGE + r
    local p = PLACES[i]
    if not p then break end
    local y = ROW_Y + (r - 1) * ROW_H
    if p[1] == place.name then
      g:rect(16, y + 2, W - 32, ROW_H - 4, { fill = true, radius = 8 })
      g:text(32, y + ROW_H // 2, p[1], { font = f_row, valign = 'middle', color = 0 })
    else
      g:text(32, y + ROW_H // 2, p[1], { font = f_row, valign = 'middle' })
      g:line(32, y + ROW_H - 1, W - 32, y + ROW_H - 1)
    end
  end
  local py = ROW_Y + PER_PAGE * ROW_H + 14
  g:rect(16, py, 90, 46, { radius = 8 })
  g:text(61, py + 23, '<', { font = f_row, align = 'center', valign = 'middle' })
  g:rect(W - 106, py, 90, 46, { radius = 8 })
  g:text(W - 61, py + 23, '>', { font = f_row, align = 'center', valign = 'middle' })
  g:text(W // 2, py + 23, page .. ' / ' .. pages(), { font = f_small, align = 'center', valign = 'middle' })
end

local function tap_place(x, y)
  if x >= W - 156 and y >= 14 and y < 58 then next_lang(place); return true end
  local py = ROW_Y + PER_PAGE * ROW_H + 14
  if y >= py and y < py + 46 then
    if x < 120 then page = (page - 2) % pages() + 1 return true end
    if x > W - 120 then page = page % pages() + 1 return true end
  end
  if y >= ROW_Y and y < ROW_Y + PER_PAGE * ROW_H then
    local p = PLACES[(page - 1) * PER_PAGE + (y - ROW_Y) // ROW_H + 1]
    if p then
      place = find_place(p[1])
      save_place(place)
      screen = 'sky'; reset_view(false); schedule()
      return true
    end
  end
  return false
end

function on_load(c)
  set_lang()
  local t = clock_now()
  place = load_place(t and t.offset_minutes)
  reset_view(false)
  schedule()
end

function on_resume(c)
  if screen == 'sky' and label == 'now' and step == 0 then reset_view(true) end
  refresh(); schedule()
end

function on_draw(c, g)
  if not g then return end
  local ok, e = pcall(function()
    g:clear(0)
    if screen == 'place' then
      draw_place(g)
    elseif not base then
      g:text(W // 2, H // 2 - 20, word('no_clock'), { font = font_px(26), align = 'center' })
      g:text(W // 2, H // 2 + 20, word('set_clock'), { font = font_px(20), align = 'center' })
    else
      local t = clock_now()
      draw_sky(g, { s = base + step * 3600, label = step == 0 and label or nil, place = place,
                    off = (t and t.offset_minutes or 0) * 60, hour12 = t and t.hour12 }, BTN_Y)
    end
    local bs = buttons()
    local f = font_px(22)
    for k, b in ipairs(bs) do
      local x, y, bw, bh = button_rect(k, #bs)
      g:rect(x, y, bw, bh, { radius = 8 })
      g:text(x + bw // 2, y + bh // 2, b[1], { font = f, align = 'center', valign = 'middle' })
    end
  end)
  if not ok then pcall(function() g:text(10, H - 100, 'draw error: ' .. tostring(e):sub(1, 40)) end) end
end

function on_input(c, ev)
  if type(ev) ~= 'table' then return false end
  if ev.type == 'pointer' and ev.phase == 'up' then
    local x, y = ev.x or 0, ev.y or 0
    local bs = buttons()
    for k, b in ipairs(bs) do
      local bx, by, bw, bh = button_rect(k, #bs)
      if x >= bx and x < bx + bw and y >= by and y < by + bh then
        pcall(b[2]); refresh(); return true
      end
    end
    if screen == 'place' and tap_place(x, y) then refresh() end
    return true
  elseif ev.type == 'key' and ev.phase ~= 'up' then
    local k = ev.key
    if k == 'left' or k == 'up' or k == 'right' or k == 'down' then
      local d = (k == 'left' or k == 'up') and -1 or 1
      if screen == 'place' then page = (page - 1 + d) % pages() + 1
      elseif base then step = step + d; schedule() end
      refresh(); return true
    end
  end
  return false
end

function on_leave(c)
  pcall(function() if timer then timer:cancel() end end)
end
