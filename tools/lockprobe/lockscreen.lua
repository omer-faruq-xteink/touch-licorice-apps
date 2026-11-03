-- Lock Probe's sleep screen. Every wake is one session: it notes the time, why it woke ("first" when
-- the device locks, "timer" after that), the seconds since the previous wake and the interval in
-- force, then calls ctx.lock:set_interval with the value chosen in the app (ctx.state.want; nil: no
-- call) and reads the interval back. Each wake is appended to AppFiles/lockprobe/wakes.txt, which
-- can be read over USB, and the last ones are drawn.
local KEEP = 16

local function clock(ctx)
  local ok, t = pcall(function() return ctx.clock:now() end)
  if ok and type(t) == 'table' and t.valid then
    return string.format('%02d:%02d:%02d', t.hour or 0, t.minute or 0, t.second or 0)
  end
  return 'no clock'
end

local line = ''

function on_load(ctx)
  local s = ctx.state
  local L = ctx.lock
  s.n = (s.n or 0) + 1
  local before = L and L.interval_sec
  local result = 'no call'
  if L and s.want then
    local ok, a, b = pcall(function() return L:set_interval(s.want) end)
    if not ok then result = 'set ' .. tostring(s.want) .. ': error ' .. tostring(a)
    else result = 'set ' .. tostring(s.want) .. (b and (': ' .. tostring(a) .. ' ' .. tostring(b)) or '') end
  end
  line = string.format('#%d %s %s elapsed=%s interval=%s -> %s; %s', s.n, clock(ctx), tostring(L and L.reason),
    tostring(L and L.elapsed_sec), tostring(before), tostring(L and L.interval_sec), result)
  pcall(function() ctx.files:append('wakes.txt', line .. '\n') end)
  s.log = s.log or {}
  s.log[#s.log + 1] = line
  while #s.log > KEEP do table.remove(s.log, 1) end
  pcall(function() ctx:save_state() end)
end

function on_draw(ctx, g)
  g:clear(0)
  g:text(16, 20, 'Lock Probe: sleep screen')
  g:text(16, 50, 'wants: ' .. (ctx.state.want and (ctx.state.want .. ' s') or 'no set_interval call'))
  g:rect(16, 80, 448, 2, { fill = true })
  local y = 96
  local log = ctx.state.log or {}
  for i = #log, math.max(1, #log - KEEP + 1), -1 do
    g:text_box(16, y, 448, 44, log[i], { font = ctx.fonts.small })
    y = y + 44
    if y > 760 then break end
  end
end
