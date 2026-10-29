-- The app: the quote for the current minute, updated on each minute while open. Another (or a tap
-- on the quote) steps through the minute's quotes, 1/3 2/3 3/3 and round; the buttons turn the
-- digital time on or off and make (or stop making) the Literary Clock the lock screen.

local BTN_Y, BTN_H = H - 64, 50
local settings = { timeline = true }
local t, list, shift, quote = nil, {}, 0, nil
local key = nil                                  -- "HHMM" of the quotes loaded
local timer = nil

local function refresh() pcall(function() ctx:invalidate() end) end

local function load_minute()
  t = now()
  if not t then list, quote = {}, nil; return end
  local k = string.format('%02d%02d', t.hour, t.minute)
  if k ~= key then key, shift = k, 0; list = quotes_at(t.hour, t.minute) end
  quote = pick(list, t, shift)
end

local function is_lock()
  local ok, v = pcall(function() return ctx.lockscreen and ctx.lockscreen:is_default() end)
  return ok and v == true
end

-- wake on the next whole minute
local function schedule()
  pcall(function() if timer then timer:cancel() end end)
  local sec = (t and t.second) or 0
  local ok, tm = pcall(function()
    return ctx:after((60 - sec) * 1000 + 200, function() load_minute(); refresh(); schedule() end)
  end)
  timer = ok and tm or nil
end

-- "Another 2/3": which of the minute's quotes is shown, counted from the one shown first;
-- "(only one)" when the minute has a single quote, so a tap that changes nothing is expected
local function another_label()
  if #list < 2 then return '(only one)' end
  return 'Another ' .. (shift % #list + 1) .. '/' .. #list
end

local function next_quote()
  if #list < 2 then return end
  shift = shift + 1
  quote = pick(list, t, shift)
end

local function buttons()
  return {
    { another_label(), next_quote },
    { settings.timeline and 'Time: on' or 'Time: off', function()
        settings.timeline = not settings.timeline; save_settings(settings) end },
    { is_lock() and 'Lock: on' or 'Lock screen', function()
        if is_lock() then pcall(function() ctx.lockscreen:clear_default() end)
        else pcall(function() ctx.lockscreen:set_default() end) end
      end },
  }
end

local function button_rect(k, n)
  local gap = 10
  local bw = (W - 2 * 16 - (n - 1) * gap) // n
  return 16 + (k - 1) * (bw + gap), BTN_Y, bw, BTN_H
end

function on_load(c)
  settings = load_settings()
  load_minute()
  schedule()
end

function on_resume(c)
  load_minute(); refresh(); schedule()
end

function on_draw(c, g)
  if not g then return end
  local ok, e = pcall(function()
    g:clear(0)
    if not t then
      g:text(W // 2, H // 2 - 20, 'The clock is not set.', { font = font_px(26), align = 'center' })
      g:text(W // 2, H // 2 + 20, 'Set the time in the system settings.', { font = font_px(20), align = 'center' })
    else
      draw_quote(g, quote, t, settings.timeline, 30, BTN_Y - 40)
    end
    local bs = buttons()
    local f = font_px(22)
    for k, b in ipairs(bs) do
      local x, y, bw, bh = button_rect(k, #bs)
      g:rect(x, y, bw, bh)
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
    if y < BTN_Y - 10 then next_quote(); refresh() end
    return true
  elseif ev.type == 'key' and ev.phase ~= 'up' and (ev.key == 'down' or ev.key == 'right' or ev.key == 'up' or ev.key == 'left') then
    if #list >= 2 then
      shift = shift + ((ev.key == 'up' or ev.key == 'left') and -1 or 1)
      quote = pick(list, t, shift); refresh()
    end
    return true
  end
  return false
end

function on_leave(c)
  pcall(function() if timer then timer:cancel() end end)
end
