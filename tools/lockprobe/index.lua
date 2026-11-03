-- Lock Probe: a developer tool for the sleep screen's refresh. Pick the interval the sleep screen
-- passes to ctx.lock:set_interval on every wake (or no call), make the app the sleep screen, lock the
-- reader and wait. lockscreen.lua logs each wake; this screen shows the log, which is also in
-- AppFiles/lockprobe/wakes.txt for reading over USB. Values outside 30-3600 are there on purpose,
-- to see what the firmware does with them.
local W = 480
local CHOICES = { false, 0, 20, 30, 60, 120, 300, 900, 3600, 7200 }
local COLS, BW, BH, GAP = 5, 84, 56, 8
local GRID_Y = 140
local ACT_Y = GRID_Y + 2 * (BH + GAP) + 16
local LOG_Y = ACT_Y + BH + 24
local msg = ''

local function label(v)
  if v == false then return 'none' end
  if v >= 60 and v % 60 == 0 then return (v // 60) .. ' min' end
  return v .. ' s'
end

local function cell(i)
  local r, c = (i - 1) // COLS, (i - 1) % COLS
  return 16 + c * (BW + GAP), GRID_Y + r * (BH + GAP)
end

local function is_lock(ctx)
  local ok, v = pcall(function() return ctx.lockscreen:is_default() end)
  return ok and v
end

local function button(g, x, y, w, h, text, on)
  g:rect(x, y, w, h, { fill = on, radius = 8 })
  if not on then g:rect(x, y, w, h, { radius = 8, line_width = 2 }) end
  g:text_box(x, y, w, h, text, { align = 'center', valign = 'middle', color = on and 0 or 15 })
end

function on_draw(ctx, g)
  local s = ctx.state
  g:clear(0)
  g:text(16, 20, 'Lock Probe', { font = ctx.fonts.large })
  g:text(16, 66, 'Sleep screen: ' .. (is_lock(ctx) and 'this app' or 'another'))
  g:text(16, 96, 'On each wake call set_interval with:')
  for i, v in ipairs(CHOICES) do
    local x, y = cell(i)
    local want = v or nil
    button(g, x, y, BW, BH, label(v), s.want == want)
  end
  button(g, 16, ACT_Y, 220, BH, is_lock(ctx) and 'Stop using' or 'Use as sleep screen', false)
  button(g, 244, ACT_Y, 220, BH, 'Clear the log', false)
  g:text(16, LOG_Y - 4, msg ~= '' and msg or 'Last wakes, newest first:', { font = ctx.fonts.small })
  local y = LOG_Y + 22
  local log = s.log or {}
  for i = #log, 1, -1 do
    g:text_box(16, y, 448, 44, log[i], { font = ctx.fonts.small })
    y = y + 44
    if y > 760 then break end
  end
end

local function tap(ctx, x, y)
  for i, v in ipairs(CHOICES) do
    local cx, cy = cell(i)
    if x >= cx and x < cx + BW and y >= cy and y < cy + BH then
      ctx.state.want = v or nil
      ctx:save_state()
      msg = 'The sleep screen will ' .. (v and ('set ' .. label(v)) or 'not call set_interval') .. '. Lock to test.'
      return
    end
  end
  if y >= ACT_Y and y < ACT_Y + BH then
    if x < 240 then
      if is_lock(ctx) then ctx.lockscreen:clear_default(); msg = 'No longer the sleep screen.'
      else ctx.lockscreen:set_default() end
    else
      ctx.state.log, ctx.state.n = {}, 0
      pcall(function() ctx.files:remove('wakes.txt') end)
      ctx:save_state()
      msg = 'Log cleared.'
    end
  end
end

function on_input(ctx, ev)
  if ev.type == 'pointer' and ev.phase == 'up' and (ev.gesture == nil or ev.gesture == 'tap') then
    tap(ctx, ev.x or 0, ev.y or 0)
    ctx:invalidate()
    return true
  end
  return false
end

function on_resume(ctx) ctx:invalidate() end

function on_load(ctx) ctx:invalidate() end
