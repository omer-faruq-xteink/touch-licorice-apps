-- The app: the sky for now (or tonight, by day), -1 h / +1 h to step through the night (the page
-- keys too), Now to go back, Place to pick a city or type coordinates and to make Sky Tonight the
-- lock screen. While open on the current time it redraws every ten minutes.

local BTN_Y, BTN_H = H - 62, 50
local screen = 'sky'                             -- 'sky' or 'place'
local place, base, label, step = nil, nil, nil, 0
local page = 1
local PER_PAGE, ROW_Y, ROW_H = 10, 92, 54
local timer = nil
local load_err = nil                             -- an error at start, shown instead of the sky
-- 1.1.0: zoomed in (nil: the whole sky): zx, zy the chart point at the window's centre, card the
-- constellation whose card shows; down: where the finger went down (a move over 20 px is a pan)
local zoom = nil
local down = nil
-- the card under the zoomed chart: shown, or hidden for a taller chart (Card button; kept in
-- view.txt, apart from settings.txt, which saving a place writes anew)
-- and from the ☰ menu: names (constellations, stars, objects), lines (the figures) and objects (the
-- deep-sky symbols of the zoomed chart: galaxy ovals, cluster circles, nebula squares)
local card_on, names_on, lines_on, objects_on = true, true, true, true
local menu_open = false
local function load_view()
  local ok, s = pcall(function() return ctx.storage:read('view.txt') end)
  s = (ok and type(s) == 'string') and s or ''
  card_on, names_on, lines_on = not s:match('card=0'), not s:match('names=0'), not s:match('lines=0')
  objects_on = not s:match('objects=0')
end
local function save_view()
  local b = function(v) return v and '1' or '0' end
  pcall(function() ctx.storage:write('view.txt', 'card=' .. b(card_on) .. '\nnames=' .. b(names_on) .. '\nlines=' .. b(lines_on) .. '\nobjects=' .. b(objects_on)) end)
end
-- the zoomed window's bottom: above the card, or down to the buttons
local function window_bottom() return card_on and WIN_Y1 or (BTN_Y - 8) end

local function refresh() pcall(function() ctx:invalidate() end) end
-- the host gives on_draw 1500 ms and on_load 2000 ms; the first frame opens five font sizes, and
-- with a user-chosen font that alone can take most of it (a German reader closed the app with
-- "App-Fehler, beendet" at 1520 ms into the frame, 2026-11-04): ask for 11 s each time
local function extend() pcall(function() ctx.budget:extend() end) end

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

-- the view the chart is drawn with (and taps are read back through)
local function sky_view()
  local t = clock_now()
  return { s = base + step * 3600, label = step == 0 and label or nil, place = place,
           off = (t and t.offset_minutes or 0) * 60, hour12 = t and t.hour12,
           zoom = zoom and ZOOM, zx = zoom and zoom.zx, zy = zoom and zoom.zy, card = zoom and zoom.card,
           win_y1 = (zoom and not card_on) and window_bottom() or nil, no_names = not names_on, no_lines = not lines_on,
           no_objects = not objects_on }
end

-- keep the window's centre on the sky (inside the horizon)
local function clamp()
  local dx, dy = zoom.zx - CX, zoom.zy - CY
  local d = math.sqrt(dx * dx + dy * dy)
  if d > R then zoom.zx, zoom.zy = CX + dx * R / d, CY + dy * R / d end
end

-- after a step in time: the window follows the card's constellation while it is up
local function follow()
  if not zoom then return end
  load_data()
  for _, cn in ipairs(CNAMES) do
    if cn[5] == zoom.card then
      local x, y, u = radec_to_screen(cn[1], cn[2], { s = base + step * 3600, place = place })
      if u > 0 then zoom.zx, zoom.zy = x, y end
      return
    end
  end
end

-- a tap on the chart: zoom in there (or, zoomed, pick the constellation there)
local function tap_sky(x, y)
  if not base then return false end
  if zoom and not card_on then return false end      -- the card hidden: a tap picks nothing
  if zoom and (y < WIN_Y0 or y > window_bottom()) then return false end
  if not zoom and (x - CX) * (x - CX) + (y - CY) * (y - CY) > R * R then return false end
  local ra, dec = chart_to_radec(x, y, sky_view())
  if not ra then return false end
  local ab = constellation_at(ra, dec)
  if not ab then return false end
  if zoom then zoom.card = ab else zoom = { zx = x, zy = y, card = ab } end
  return true
end

local function buttons()
  if screen == 'sky' and zoom then
    return {
      { word('zoom_out'), function() zoom = nil end },
      { '-1 h', function() step = step - 1; follow(); schedule() end },
      { '+1 h', function() step = step + 1; follow(); schedule() end },
      { word('card'), function() card_on = not card_on; save_view() end, card_on },   -- bold while it shows
    }
  end
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
  extend()
  local ok, e = xpcall(function()
    set_lang()
    load_view()
    dbg('start: lang ' .. LANG .. ', api ' .. tostring(ctx.api and ctx.api.minor)
        .. ', firmware ' .. tostring(ctx.device and ctx.device.firmware))
    local t = clock_now()
    dbg('clock: ' .. (t and (tostring(t.epoch_sec) .. ' off ' .. tostring(t.offset_minutes)) or 'not set'))
    place = load_place(t and t.offset_minutes)
    dbg('place: ' .. tostring(place and place.name) .. ' ' .. tostring(place and place.lat) .. ' ' .. tostring(place and place.lon))
    reset_view(false)
    dbg('view: ' .. tostring(base) .. ' ' .. tostring(label))
    schedule()
  end, trace)
  if not ok then load_err = tostring(e); dbg('ERROR ' .. load_err) end
end

function on_resume(c)
  extend()
  if screen == 'sky' and label == 'now' and step == 0 then reset_view(true) end
  refresh(); schedule()
end

-- the ☰ under the time (three lines: the reader's fonts may lack the sign), and its list (as the
-- Tool list in Notes): Names and Lines, each with a box ticked while on; open until a tap elsewhere
local HAM = { x = W - 64, y = 50, w = 60, h = 40 }
local MENU_X, MENU_Y, MENU_W, MENU_ROW = W - 228, 94, 220, 60
local function menu_items()
  return { { word('names'), function() names_on = not names_on end, names_on },
           { word('lines'), function() lines_on = not lines_on end, lines_on },
           { word('objects'), function() objects_on = not objects_on end, objects_on } }
end
local function draw_menu_button(g)
  local x = HAM.x + 16
  for k = 0, 2 do g:rect(x, HAM.y + 10 + k * 9, 28, 3, { fill = true }) end
end
local function draw_menu(g)
  local items = menu_items()
  g:rect(MENU_X, MENU_Y, MENU_W, #items * MENU_ROW + 8, { fill = true, color = 0 })
  g:rect(MENU_X, MENU_Y, MENU_W, #items * MENU_ROW + 8, { line_width = 2 })
  for i, it in ipairs(items) do
    local y = MENU_Y + 4 + (i - 1) * MENU_ROW
    g:rect(MENU_X + 4, y, MENU_W - 8, MENU_ROW - 6, { radius = 6 })
    g:rect(MENU_X + 16, y + 15, 24, 24, { line_width = 2 })
    if it[3] then g:rect(MENU_X + 21, y + 20, 14, 14, { fill = true }) end
    g:text(MENU_X + 54, y + (MENU_ROW - 6) // 2, it[1], { font = font_px(22), valign = 'middle' })
  end
end
local function in_rect(x, y, rx, ry, rw, rh) return x >= rx and x < rx + rw and y >= ry and y < ry + rh end

function on_draw(c, g)
  if not g then return end
  extend()
  if load_err then
    g:clear(0)
    draw_error(g, 'Sky Tonight could not start:', load_err)
    g:text(10, H - 60, 'Please send a photo of this screen.')
    return
  end
  dbg('draw ' .. screen)
  local ok, e = xpcall(function()
    g:clear(0)
    if screen == 'place' then
      draw_place(g)
    elseif not base then
      g:text(W // 2, H // 2 - 20, word('no_clock'), { font = font_px(26), align = 'center' })
      g:text(W // 2, H // 2 + 20, word('set_clock'), { font = font_px(20), align = 'center' })
    else
      draw_sky(g, sky_view(), BTN_Y)
    end
    local bs = buttons()
    local f = font_px(22)
    for k, b in ipairs(bs) do
      local x, y, bw, bh = button_rect(k, #bs)
      g:rect(x, y, bw, bh, { radius = 8, line_width = b[3] and 4 or nil })
      g:text(x + bw // 2, y + bh // 2, b[1], { font = f, align = 'center', valign = 'middle' })
    end
    if screen == 'sky' and base then
      draw_menu_button(g)
      if menu_open then draw_menu(g) end
    end
  end, trace)
  if not ok then
    dbg('DRAW ERROR ' .. tostring(e))
    g:clear(0)
    draw_error(g, 'draw error:', tostring(e))
  else dbg('draw done') end
end

function on_input(c, ev)
  if type(ev) ~= 'table' then return false end
  extend()
  if ev.type == 'pointer' and ev.phase == 'down' then
    down = { x = ev.x or 0, y = ev.y or 0 }
    return true
  elseif ev.type == 'pointer' and ev.phase == 'up' then
    local x, y = ev.x or 0, ev.y or 0
    local d = down
    down = nil
    -- the ☰ list open: a tap on an item switches it (the list stays), anywhere else closes it
    if menu_open then
      local hit = false
      for i, it in ipairs(menu_items()) do
        if in_rect(x, y, MENU_X, MENU_Y + 4 + (i - 1) * MENU_ROW, MENU_W, MENU_ROW) then it[2](); save_view(); hit = true end
      end
      if not hit then menu_open = false end
      refresh(); return true
    end
    if screen == 'sky' and base and in_rect(x, y, HAM.x, HAM.y, HAM.w, HAM.h) then
      menu_open = true
      refresh(); return true
    end
    -- zoomed, a move over 20 px from where the finger went down pans the chart
    if zoom and screen == 'sky' and d and d.y >= WIN_Y0 and d.y <= window_bottom()
        and (x - d.x) * (x - d.x) + (y - d.y) * (y - d.y) > 400 then
      zoom.zx, zoom.zy = zoom.zx - (x - d.x) / ZOOM, zoom.zy - (y - d.y) / ZOOM
      clamp()
      refresh(); return true
    end
    local bs = buttons()
    for k, b in ipairs(bs) do
      local bx, by, bw, bh = button_rect(k, #bs)
      if x >= bx and x < bx + bw and y >= by and y < by + bh then
        pcall(b[2]); refresh(); return true
      end
    end
    if screen == 'place' then
      if tap_place(x, y) then refresh() end
    elseif tap_sky(x, y) then
      refresh()
    end
    return true
  elseif ev.type == 'key' and ev.key == 'back' then
    -- on its release: zoomed, back to the whole sky; the Place page, back to the sky; else the host
    -- asks whether to leave
    if ev.phase ~= 'up' and ev.phase ~= nil then return true end
    if menu_open then menu_open = false; refresh(); return true end
    if screen == 'place' then screen = 'sky'; refresh(); return true end
    if zoom then zoom = nil; refresh(); return true end
    return false
  elseif ev.type == 'key' and ev.phase ~= 'up' then
    local k = ev.key
    if k == 'left' or k == 'up' or k == 'right' or k == 'down' then
      local d = (k == 'left' or k == 'up') and -1 or 1
      if screen == 'place' then page = (page - 1 + d) % pages() + 1
      elseif base then step = step + d; follow(); schedule() end
      refresh(); return true
    end
  end
  return false
end

function on_leave(c)
  pcall(function() if timer then timer:cancel() end end)
end

if rawget(_G, '__TEST') then
  __TEST.app = { zoom = function() return zoom end,
                 menu_row = function(i) return { MENU_X + 60, MENU_Y + 4 + (i - 1) * MENU_ROW + 20 } end }
end
