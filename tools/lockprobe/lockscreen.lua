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

local function note(ctx, text)
  local s = ctx.state
  pcall(function() ctx.files:append('wakes.txt', text .. '\n') end)
  s.log = s.log or {}
  s.log[#s.log + 1] = text
  while #s.log > KEEP do table.remove(s.log, 1) end
  pcall(function() ctx:save_state() end)
end

local function millis(ctx)
  local ok, v = pcall(function() return ctx.clock:millis() end)
  return ok and v or 0
end

-- 1.9: can a lock session be held past the aligned time it was woken for? A wake that comes early and
-- ends before that time gets a second wake at it (Calendar: 14:59:37 then 15:00:01). Odd wakes hold
-- with ctx:after (until 3 s past the boundary when early, else 8 s) and set_tick(1000), and call
-- done() only when the timer fires; even wakes are the control (done() in the first draw). No
-- network in 1.9. The docs (2.21) say after and set_tick have no effect in a lock session.
local function wall_s(ctx)
  local ok, t = pcall(function() return ctx.clock:now() end)
  if ok and type(t) == 'table' and t.valid then return (t.hour or 0) * 3600 + (t.minute or 0) * 60 + (t.second or 0) end
  return nil
end

local holding, fired, ticks, t_hold = false, false, 0, 0

local function res(ok, a, b) return ok and (tostring(a) .. ' ' .. tostring(b)) or ('error ' .. tostring(a)) end

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
  note(ctx, line)
  if not L then return end
  local want = tonumber(L.interval_sec) or s.want or 60
  local w = wall_s(ctx)
  local rem = w and (want - w % want) % want
  local early = rem and rem > 0 and rem < 90
  holding = s.n % 2 == 1
  note(ctx, string.format('  next boundary in %s s (%s); %s', tostring(rem), early and 'early' or 'on time',
    holding and 'hold' or 'no hold (control)'))
  if not holding then return end
  local ms = early and (rem + 3) * 1000 or 8000
  t_hold = millis(ctx)
  local ok, a, b = pcall(function()
    return ctx:after(ms, function()
      fired = true
      note(ctx, string.format('  after(%d) fired at +%d ms, %s, ticks %d', ms, millis(ctx) - t_hold, clock(ctx), ticks))
      pcall(function() ctx:set_tick(0) end)
      pcall(function() ctx:invalidate() end)
    end)
  end)
  note(ctx, string.format('  after(%d) -> %s', ms, res(ok, a, b)))
  local okt, ta, tb = pcall(function() return ctx:set_tick(1000) end)
  note(ctx, '  set_tick(1000) -> ' .. res(okt, ta, tb))
end

function on_tick(ctx, dt)
  ticks = ticks + 1
  if ticks <= 2 or ticks % 10 == 0 then
    note(ctx, string.format('  tick %d dt %s at +%d ms %s', ticks, tostring(dt), millis(ctx) - t_hold, clock(ctx)))
  end
end

local draws, t_load, done_sent = 0, nil, false

function on_draw(ctx, g)
  draws = draws + 1
  t_load = t_load or millis(ctx)
  if draws > 1 then note(ctx, string.format('  draw %d at +%d ms', draws, millis(ctx) - t_load)) end
  g:clear(0)
  g:text(16, 20, 'Lock Probe 1.9: hold test')
  g:text(16, 50, 'wants: ' .. (ctx.state.want and (ctx.state.want .. ' s') or 'no set_interval call'))
  g:rect(16, 80, 448, 2, { fill = true })
  local y = 96
  local log = ctx.state.log or {}
  for i = #log, math.max(1, #log - KEEP + 1), -1 do
    g:text_box(16, y, 448, 44, log[i], { font = ctx.fonts.small })
    y = y + 44
    if y > 760 then break end
  end
  if done_sent then return end
  if holding and not fired then
    note(ctx, string.format('  draw %d: holding, no done()', draws))
    return
  end
  done_sent = true
  local okd, da, db = pcall(function() return ctx.lock:done() end)
  note(ctx, string.format('  done() in draw %d -> %s', draws, res(okd, da, db)))
end
