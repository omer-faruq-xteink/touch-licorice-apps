-- Lock-screen entry for the round-5 probe. Shows the time and a draw counter so we can tell
-- whether the host redraws the lock entry on `interval_sec`, and which callbacks it calls.
local draws, ticks, loads = 0, 0, 0
local function now_str()
  local ok, t = pcall(function() return ctx.clock:now() end)
  if ok and type(t) == 'table' then
    return string.format('%02d:%02d:%02d', tonumber(t.hour) or 0, tonumber(t.minute) or 0, tonumber(t.second) or 0)
  end
  return tostring(ok and t or 'now err')
end
function on_draw(c, gg)
  if not gg then return end
  draws = draws + 1
  pcall(function()
    gg:clear(0)
    gg:text(15, 20, 'probe 2.9 lock entry  r5')
    gg:rect(15, 60, 450, 200)
    gg:text(30, 90, 'api ' .. tostring(ctx and ctx.api and ctx.api.major) .. '.' .. tostring(ctx and ctx.api and ctx.api.minor))
    gg:text(30, 120, 'time ' .. now_str())
    gg:text(30, 150, 'draws ' .. draws .. '  ticks ' .. ticks .. '  loads ' .. loads)
    local bat = select(2, pcall(function() return ctx.device:battery() end))
    gg:text(30, 180, 'battery ' .. tostring(type(bat) == 'table' and (bat.percent or bat.level) or bat))
  end)
end
function on_load() loads = loads + 1 end
function on_tick() ticks = ticks + 1 end
function on_input() return false end
