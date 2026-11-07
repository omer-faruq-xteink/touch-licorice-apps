-- Timekeeper for XTOS Licorice (uses tools/gamekit): timers, a focus timer (Pomodoro), a
-- stopwatch, an interval timer, counters and a log of focus time, with a lock screen.
--
-- Every running thing is kept as the moment it ends (or started), never as what is left, so it is
-- right after leaving the app, locking or a power-off (the clock's epoch). The reader has no sound:
-- a finished timer shows on the screen and on the lock screen.
--
-- E-ink costs power with every refresh, so the screen does not tick every second: a running timer
-- shows whole minutes and the app wakes when that number changes, when something ends, and when
-- the seconds are wanted (Seconds: last minute, the default, or always; a tap on the big digits
-- shows them until the next minute). The interval timer shows seconds while it runs.
--
-- The app writes lock.txt for lockscreen.lua: one line a running thing, with its end moment.

local W, H = kit.W, kit.H
local M = 12
local TAB_Y, TAB_H = 84, 46
local BIG_Y, BIG_H = 150, 120          -- the big digits
local CAP_Y = 290                      -- the line under them
local BODY_Y = 340
local BTN_Y, BTN_H = 742, 50
local TABS = { 'Timer', 'Focus', 'Watch', 'Sets', 'Count', 'Log' }

local tab = 1
local msg, ERR = nil, nil
local seconds_mode = 'last'            -- off | last | on
local stay_awake = true                -- while something runs, the reader does not go to sleep
local flash_on_end = true              -- time's up while the app is open: the screen flashes
local clock_on = true                  -- the time in the header (a refresh a minute while open)
local flash = 0                        -- frames of the flash still to show (odd: dark)
local flash_timer = nil
local awake_ms = 0                     -- the last keep_awake asked for
local exact_until = nil                -- a tap on the digits: seconds shown until this moment
local exact_secs, exact_at = nil, nil  -- what they showed, and when
local timers = {}                      -- { name, dur (s), ends, left (paused), ready }
local tsel = 1
local focus = { work = 25, short = 5, long = 15, every = 4, auto = true, phase = 'work', round = 1 }
local watch = { acc = 0, laps = {} }   -- start: the moment it was started; acc: seconds before
local rounds = { work = 40, rest = 20, count = 8, acc = 0 }
local counters = {}
local csel = 1
local log = {}                         -- day -> { focus minutes, pomodoros }
local wake = nil
local clock_ok = true
local session_base = nil

------------------------------------------------------------------ time

local function now_t()
  local ok, t = pcall(function() return ctx.clock:now() end)
  if ok and type(t) == 'table' then return t end
  return {}
end

-- seconds since 1970 (UTC); without a set clock, seconds since the app opened (lost on leaving)
local function now()
  local e = tonumber(now_t().epoch_sec)
  if e then clock_ok = true; return math.floor(e) end
  clock_ok = false
  local ms = kit.now_ms() or 0
  session_base = session_base or ms
  return (ms - session_base) // 1000 + 1000000
end

-- the wall clock's offset from UTC, in seconds (the clock's own hour decides it)
local function utc_offset()
  local t = now_t()
  local e = tonumber(t.epoch_sec)
  if not e or not tonumber(t.hour) then return 0 end
  local wall = tonumber(t.hour) * 3600 + (tonumber(t.minute) or 0) * 60 + (tonumber(t.second) or 0)
  local off = (wall - math.floor(e) % 86400) % 86400
  if off > 14 * 3600 then off = off - 86400 end
  return math.floor(off / 900 + 0.5) * 900
end

local function day_of(sec) return (sec + utc_offset()) // 86400 end
local function today() return day_of(now()) end

-- "14:37": the wall time of a moment
local function hm(sec)
  if not clock_ok then return '' end
  local s = (sec + utc_offset()) % 86400
  return string.format('%02d:%02d', s // 3600, s // 60 % 60)
end

local function hms(sec)
  if not clock_ok or not sec then return '' end
  local s = (sec + utc_offset()) % 86400
  return string.format('%02d:%02d:%02d', s // 3600, s // 60 % 60, s % 60)
end

local function mmss(s)
  s = math.max(0, math.floor(s))
  if s >= 3600 then return string.format('%d:%02d:%02d', s // 3600, s // 60 % 60, s % 60) end
  return string.format('%d:%02d', s // 60, s % 60)
end

-- whole minutes as digits: "24", or "1:05" from an hour on
local function minutes_text(m)
  if m >= 60 then return string.format('%d:%02d', m // 60, m % 60) end
  return tostring(m)
end

local function plural(n, one, many) return n .. ' ' .. (n == 1 and one or many) end

------------------------------------------------------------------ the things that run

local function timer_left(t)
  if t.ends then return math.max(0, t.ends - now()) end
  if t.left then return t.left end
  return t.dur
end

local function focus_dur(phase)
  return (phase == 'work' and focus.work or phase == 'short' and focus.short or focus.long) * 60
end
local PHASE = { work = 'Focus', short = 'Short break', long = 'Long break' }

local function focus_left()
  if focus.ends then return math.max(0, focus.ends - now()) end
  if focus.left then return focus.left end
  return focus_dur(focus.phase)
end

local function add_log(day, mins, poms)
  local l = log[day] or { 0, 0 }
  l[1], l[2] = l[1] + mins, l[2] + poms
  log[day] = l
end

-- a phase that ended: log a focus, go on to the next (started at once when auto is on)
local function focus_advance()
  local changed = false
  while focus.ends and now() >= focus.ends do
    local ended = focus.ends
    changed = true
    if focus.phase == 'work' then
      add_log(day_of(ended), focus.work, 1)
      focus.phase = (focus.round % focus.every == 0) and 'long' or 'short'
      msg = 'Focus done: time for a ' .. (focus.phase == 'long' and 'long break.' or 'break.')
    else
      focus.round = focus.phase == 'long' and 1 or focus.round + 1
      focus.phase = 'work'
      msg = 'Break over: back to focus.'
    end
    focus.ends = focus.auto and (ended + focus_dur(focus.phase)) or nil
    focus.left = nil
  end
  return changed
end

local function watch_elapsed()
  return watch.acc + (watch.start and math.max(0, now() - watch.start) or 0)
end

-- the interval timer at elapsed e: phase ('work', 'rest', 'done'), round, seconds left in it
local function rounds_at(e)
  local cycle = rounds.work + rounds.rest
  local total = rounds.count * cycle - rounds.rest
  if e >= total then return 'done', rounds.count, 0 end
  local k, within = e // cycle, e % cycle
  if within < rounds.work then return 'work', k + 1, rounds.work - within end
  return 'rest', k + 1, cycle - within
end
local function rounds_elapsed() return rounds.acc + (rounds.start and math.max(0, now() - rounds.start) or 0) end

local function timers_ready()
  local changed = false
  for _k, t in ipairs(timers) do
    if t.ends and not t.ready and now() >= t.ends then
      t.ready = true; changed = true
      msg = t.name .. ': time\'s up!'
    end
  end
  return changed
end

------------------------------------------------------------------ storage

local function clean(s) return (tostring(s):gsub('[|\n\r]', ' ')) end

local function lock_write()
  local t = {}
  for _k, x in ipairs(timers) do
    if x.ends then t[#t + 1] = 'end|' .. clean(x.name) .. '|' .. x.ends end
  end
  if focus.ends then
    t[#t + 1] = 'end|' .. PHASE[focus.phase] .. (focus.phase == 'work' and (' ' .. focus.round .. ' of ' .. focus.every) or '') .. '|' .. focus.ends
  end
  if watch.start then t[#t + 1] = 'from|Stopwatch|' .. (watch.start - watch.acc) end
  if rounds.start then
    local cycle = rounds.work + rounds.rest
    t[#t + 1] = 'end|Rounds|' .. (rounds.start - rounds.acc + rounds.count * cycle - rounds.rest)
  end
  local l = log[today()]
  t[#t + 1] = 'today|' .. (l and l[1] or 0) .. '|' .. (l and l[2] or 0)
  kit.write('lock.txt', table.concat(t, '\n'))
end

local function save()
  local t = { 'tab=' .. tab, 'seconds=' .. seconds_mode, 'awake=' .. (stay_awake and 1 or 0), 'flash=' .. (flash_on_end and 1 or 0), 'clock=' .. (clock_on and 1 or 0), 'tsel=' .. tsel, 'csel=' .. csel }
  for _k, x in ipairs(timers) do
    t[#t + 1] = 'timer=' .. clean(x.name) .. '|' .. x.dur .. '|' .. (x.ends or '') .. '|' .. (x.left or '') .. '|' .. (x.ready and 1 or 0)
  end
  t[#t + 1] = 'focus=' .. table.concat({ focus.work, focus.short, focus.long, focus.every, focus.auto and 1 or 0,
    focus.phase, focus.round, focus.ends or '', focus.left or '' }, '|')
  local laps = {}
  for _k, l in ipairs(watch.laps) do laps[#laps + 1] = l end
  t[#t + 1] = 'watch=' .. (watch.start or '') .. '|' .. watch.acc .. '|' .. table.concat(laps, ',')
  t[#t + 1] = 'rounds=' .. table.concat({ rounds.work, rounds.rest, rounds.count, rounds.start or '', rounds.acc }, '|')
  for _k, c in ipairs(counters) do t[#t + 1] = 'counter=' .. clean(c.name) .. '|' .. c.n end
  local days = {}
  for d in pairs(log) do days[#days + 1] = d end
  table.sort(days)
  for k = math.max(1, #days - 59), #days do
    local d = days[k]
    t[#t + 1] = 'log=' .. d .. '|' .. log[d][1] .. '|' .. log[d][2]
  end
  kit.write('timekeeper.txt', table.concat(t, '\n'))
  lock_write()
end

local function fields(v)
  local f = {}
  for x in (v .. '|'):gmatch('([^|]*)|') do f[#f + 1] = x end
  return f
end

local function load()
  local s = kit.read('timekeeper.txt')
  timers, counters, log = {}, {}, {}
  if not s then
    timers = { { name = 'Tea', dur = 4 * 60 }, { name = 'Eggs', dur = 8 * 60 }, { name = 'Nap', dur = 20 * 60 } }
    counters = { { name = 'Counter', n = 0 } }
    return false
  end
  for k, v in s:gmatch('([%w_]+)=([^\n]*)') do
    local f = fields(v)
    if k == 'tab' then tab = math.max(1, math.min(#TABS, tonumber(v) or 1))
    elseif k == 'seconds' and (v == 'off' or v == 'last' or v == 'on') then seconds_mode = v
    elseif k == 'awake' then stay_awake = v ~= '0'
    elseif k == 'flash' then flash_on_end = v ~= '0'
    elseif k == 'clock' then clock_on = v ~= '0'
    elseif k == 'tsel' then tsel = tonumber(v) or 1
    elseif k == 'csel' then csel = tonumber(v) or 1
    elseif k == 'timer' and tonumber(f[2]) then
      timers[#timers + 1] = { name = f[1], dur = tonumber(f[2]), ends = tonumber(f[3]), left = tonumber(f[4]), ready = f[5] == '1' }
    elseif k == 'focus' and #f >= 9 then
      focus.work, focus.short, focus.long, focus.every = tonumber(f[1]) or 25, tonumber(f[2]) or 5, tonumber(f[3]) or 15, tonumber(f[4]) or 4
      focus.auto = f[5] ~= '0'
      focus.phase = PHASE[f[6]] and f[6] or 'work'
      focus.round = tonumber(f[7]) or 1
      focus.ends, focus.left = tonumber(f[8]), tonumber(f[9])
    elseif k == 'watch' then
      watch.start, watch.acc, watch.laps = tonumber(f[1]), tonumber(f[2]) or 0, {}
      for x in (f[3] or ''):gmatch('%d+') do watch.laps[#watch.laps + 1] = tonumber(x) end
    elseif k == 'rounds' and #f >= 5 then
      rounds.work, rounds.rest, rounds.count = tonumber(f[1]) or 40, tonumber(f[2]) or 20, tonumber(f[3]) or 8
      rounds.start, rounds.acc = tonumber(f[4]), tonumber(f[5]) or 0
    elseif k == 'counter' and tonumber(f[2]) then counters[#counters + 1] = { name = f[1], n = tonumber(f[2]) }
    elseif k == 'log' and tonumber(f[1]) then log[tonumber(f[1])] = { tonumber(f[2]) or 0, tonumber(f[3]) or 0 } end
  end
  if #timers == 0 then timers = { { name = 'Timer', dur = 5 * 60 } } end
  if #counters == 0 then counters = { { name = 'Counter', n = 0 } } end
  tsel = math.max(1, math.min(#timers, tsel))
  csel = math.max(1, math.min(#counters, csel))
  return true
end

------------------------------------------------------------------ what the big digits show

-- the shown tab's value: { secs, countdown (true) or elapsed, running, label }
local function shown()
  if tab == 1 then
    local t = timers[tsel]
    return timer_left(t), true, t.ends ~= nil and not t.ready
  elseif tab == 2 then
    return focus_left(), true, focus.ends ~= nil
  elseif tab == 3 then
    return watch_elapsed(), false, watch.start ~= nil
  elseif tab == 4 then
    if rounds.start or rounds.acc > 0 then
      local _p, _r, left = rounds_at(rounds_elapsed())
      return left, true, rounds.start ~= nil
    end
    return rounds.work, true, false
  end
  return nil
end

-- seconds that tick by themselves (a refresh a second)
local function live_seconds(secs, countdown, running)
  if not running then return true end
  if tab == 4 then return true end
  if seconds_mode == 'on' then return true end
  return seconds_mode == 'last' and countdown and secs <= 60
end

-- a tap on the digits: the seconds once, as they were then, until the shown minute changes
local function tapped()
  return exact_until ~= nil and now() < exact_until
end

local function want_seconds(secs, countdown, running)
  return live_seconds(secs, countdown, running) or tapped()
end

------------------------------------------------------------------ waking

-- seconds until the next moment the screen must change
local function next_wake()
  local best = nil
  local function at(s) if s and s > 0 and (not best or s < best) then best = s end end
  local n = now()
  for _k, t in ipairs(timers) do if t.ends and not t.ready then at(t.ends - n) end end
  if focus.ends then at(focus.ends - n) end
  if exact_until and exact_until > n then at(exact_until - n) end
  if clock_on and clock_ok then at(60 - (n + utc_offset()) % 60) end      -- the clock's next minute
  local secs, countdown, running = shown()
  if running then
    if live_seconds(secs, countdown, running) then at(1)
    elseif countdown then
      at(((secs - 1) % 60) + 1)                         -- the shown minutes change
      if seconds_mode == 'last' then at(secs - 60) end  -- the last minute starts
    else at(60 - secs % 60) end
  end
  if rounds.start then
    local e = rounds_elapsed()
    local p, _r, left = rounds_at(e)
    if p ~= 'done' then at(left) end
  end
  return best
end

local on_wake

local function running_any()
  for _k, t in ipairs(timers) do if t.ends and not t.ready then return true end end
  return focus.ends ~= nil or watch.start ~= nil or rounds.start ~= nil
end

-- while something runs (and Stay awake is on), put off the reader's sleep until a little after the
-- next wake, which asks again (ctx.device:keep_awake, firmware 26110201 on; 4 hours at most)
local function awake_update(next_s)
  local D = ctx.device
  if not D or not D.keep_awake then return end
  local ms = 0
  if stay_awake and running_any() then ms = math.min(14400000, ((next_s or 600) + 120) * 1000) end
  if ms == 0 and awake_ms == 0 then return end
  pcall(function() D:keep_awake(ms) end)
  awake_ms = ms
end

local function schedule()
  if wake then pcall(function() wake:cancel() end); wake = nil end
  local s = next_wake()
  awake_update(s)
  if not s then return end
  local ok, w = pcall(function() return ctx:after(s * 1000 + 150, function() on_wake() end) end)
  if ok then wake = w end
end

local function tick()
  local changed = focus_advance()
  changed = timers_ready() or changed
  if rounds.start then
    local p = rounds_at(rounds_elapsed())
    if p == 'done' then
      rounds.acc, rounds.start = rounds_elapsed(), nil
      msg = 'Rounds done!'
      changed = true
    end
  end
  if exact_until and now() >= exact_until then exact_until = nil end
  if changed then save() end
  return changed
end

-- time's up with the app open: dark, light, dark... six frames, each kept long enough for the panel
-- to show it (a partial refresh takes about 0.65 s), then a full refresh to clear any ghost
local function flash_step()
  flash = flash - 1
  if flash > 0 then
    pcall(function() flash_timer = ctx:after(900, function() flash_step() end) end)
    kit.refresh()
  else
    flash_timer = nil
    pcall(function() ctx:invalidate('full') end)
  end
end

local function start_flash()
  if not flash_on_end then return end
  if flash_timer then pcall(function() flash_timer:cancel() end) end
  flash = 8                     -- 7 dark, 6 light ... 1 dark, then the normal screen
  flash_step()
end

local function stop_flash()
  if flash <= 0 then return end
  if flash_timer then pcall(function() flash_timer:cancel() end); flash_timer = nil end
  flash = 0
  pcall(function() ctx:invalidate('full') end)
end

on_wake = function()
  local ok, e = pcall(tick)
  if not ok then ERR = tostring(e) end
  if ok and e then start_flash() end
  kit.refresh()
  schedule()
end

------------------------------------------------------------------ seven-segment digits

local SEG = { ['0'] = 'abcdef', ['1'] = 'bc', ['2'] = 'abged', ['3'] = 'abgcd', ['4'] = 'fgbc', ['5'] = 'afgcd',
              ['6'] = 'afgedc', ['7'] = 'abc', ['8'] = 'abcdefg', ['9'] = 'abcdfg', ['-'] = 'g' }
local BLACK = { fill = true }

local function seg_width(s, h)
  local dw, gap = h * 55 // 100, h * 14 // 100
  local w = 0
  for ch in s:gmatch('.') do w = w + (ch == ':' and h * 22 // 100 or dw) + gap end
  return w - gap
end

local function seg_text(gg, s, cx, y, h)
  local dw, gap, t = h * 55 // 100, h * 14 // 100, math.max(4, h * 11 // 100)
  local x = cx - seg_width(s, h) // 2
  local mid = y + h // 2
  for ch in s:gmatch('.') do
    if ch == ':' then
      local cw = h * 22 // 100
      gg:rect(x + (cw - t) // 2, y + h * 28 // 100, t, t, BLACK)
      gg:rect(x + (cw - t) // 2, y + h * 66 // 100, t, t, BLACK)
      x = x + cw + gap
    else
      local on = SEG[ch] or ''
      local function has(c) return on:find(c, 1, true) end
      if has('a') then gg:rect(x + t // 2, y, dw - t, t, BLACK) end
      if has('g') then gg:rect(x + t // 2, mid - t // 2, dw - t, t, BLACK) end
      if has('d') then gg:rect(x + t // 2, y + h - t, dw - t, t, BLACK) end
      if has('f') then gg:rect(x, y + t // 2, t, mid - y - t // 2 + t // 2, BLACK) end
      if has('b') then gg:rect(x + dw - t, y + t // 2, t, mid - y - t // 2 + t // 2, BLACK) end
      if has('e') then gg:rect(x, mid - t // 2, t, y + h - mid - t // 2 + t // 2, BLACK) end
      if has('c') then gg:rect(x + dw - t, mid - t // 2, t, y + h - mid - t // 2 + t // 2, BLACK) end
      x = x + dw + gap
    end
  end
end

-- the digits fitted to the width
local function big(gg, s, y, h)
  h = h or BIG_H
  while seg_width(s, h) > W - 2 * M and h > 30 do h = h - 6 end
  seg_text(gg, s, W // 2, y + (BIG_H - h) // 2, h)
end

------------------------------------------------------------------ drawing

local function center(gg, s, y, fname)
  local f = kit.font(fname or 'medium')
  gg:text((W - kit.width(f, s)) // 2, y, s, { font = f })
end

-- buttons laid out in a row: { {label, fn, enabled}, ... }
local function row_rects(n, y, h)
  local gap = n > 4 and 4 or 8
  local bw = (W - 2 * M - (n - 1) * gap) // n
  local out = {}
  for k = 1, n do out[k] = { M + (k - 1) * (bw + gap), y, bw, h } end
  return out
end

local hits = {}                 -- the tappable areas of the last frame: { x, y, w, h, fn }
local function hit(x, y, w, h, fn) hits[#hits + 1] = { x, y, w, h, fn } end

local function buttons(gg, list, y, h, font)
  local rs = row_rects(#list, y, h)
  for k, b in ipairs(list) do
    local r = rs[k]
    if b[1] then
      local enabled = b[3] ~= false
      kit.button(gg, r[1], r[2], r[3], r[4], enabled and b[1] or ('(' .. b[1] .. ')'), { line_width = enabled and 2 or 1, font = font })
      if enabled then hit(r[1], r[2], r[3], r[4], b[2]) end
    end
  end
end

-- a setting with - and + : "Focus   25 min   [-] [+]"
local function stepper(gg, y, label, value, minus, plus)
  local f = kit.font('medium')
  gg:text(M, y + 12, label, { font = f })
  gg:text(236, y + 12, value, { font = f })
  local bx = W - M - 2 * 64 - 8
  kit.button(gg, bx, y, 64, 48, '-')
  kit.button(gg, bx + 72, y, 64, 48, '+')
  hit(bx, y, 64, 48, minus)
  hit(bx + 72, y, 64, 48, plus)
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function draw_digits(gg)
  local secs, countdown, running = shown()
  local exact = want_seconds(secs, countdown, running)
  local frozen = exact and not live_seconds(secs, countdown, running)
  if frozen and exact_secs then secs = exact_secs end
  local text
  if exact then text = mmss(secs)
  elseif countdown then text = minutes_text((secs + 59) // 60)
  else text = minutes_text(secs // 60) end
  big(gg, text, BIG_Y)
  -- a tap on the digits shows the seconds until the next minute
  hit(0, BIG_Y - 10, W, BIG_H + 20, function()
    local s2, cd2, run2 = shown()                     -- as it is now, not as it was drawn
    if run2 and not want_seconds(s2, cd2, run2) then
      exact_until = now() + (cd2 and (((s2 - 1) % 60) + 1) or (60 - s2 % 60))
      exact_secs, exact_at = s2, now()
    end
  end)
  return exact, running, countdown, frozen
end

local function confirm(title, fn)
  kit.show({ title = title, rows = { { { 'Yes', function() kit.close(); fn() end }, { 'No', kit.close } } }, cancel = kit.close })
end

local function ask(title, value, maxb, fn)
  local I = ctx.input
  if not I or not I.text then msg = 'This reader has no keyboard for apps.'; return end
  I:text({ title = title, text = value or '', max_bytes = maxb or 24 }, function(c, s)
    s = (s or ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('[\n|]', ' ')
    if s ~= '' then pcall(fn, s); save() end
    kit.refresh()
  end)
end

------------------------------------------------------------------ tabs

-- a timer's box: its length (by steps, or typed as minutes or h:mm), name, delete
local function edit_timer(t)
  local function adj(d) return function() t.dur = clamp(t.dur + d, 60, 24 * 3600 - 60); save(); edit_timer(t) end end
  kit.show({ title = t.name .. ': ' .. mmss(t.dur), lines = { t.ends and 'A new length counts from the next start.' or 'The length, in minutes:' }, rows = {
    { { '-5', adj(-300) }, { '-1', adj(-60) }, { '+1', adj(60) }, { '+5', adj(300) } },
    { { '+30', adj(1800) }, { 'Type it', function()
        kit.close()
        ask('Minutes (or h:mm) for ' .. t.name, tostring(t.dur // 60), 8, function(s)
          local h, m = s:match('^(%d+):(%d%d?)$')
          local mins = h and (tonumber(h) * 60 + tonumber(m)) or tonumber(s:match('^(%d+)$'))
          if not mins or mins < 1 then msg = 'A length is minutes, like 12, or h:mm, like 1:30.'; return end
          t.dur = clamp(mins * 60, 60, 24 * 3600 - 60)
        end)
      end } },
    { { 'Rename', function() kit.close(); ask('Name of the timer', t.name, 24, function(s) t.name = s end) end },
      { 'Delete', function() kit.close()
          if #timers == 1 then msg = 'One timer stays.'; return end
          confirm('Delete ' .. t.name .. '?', function() table.remove(timers, tsel); tsel = math.min(tsel, #timers); save() end)
        end } },
    { { 'Close', kit.close } } }, cancel = kit.close })
end

local function draw_timer(gg)
  local t = timers[tsel]
  local exact, running, _cd, frozen = draw_digits(gg)
  local cap
  if t.ready then cap = t.name .. ': time\'s up! (ended ' .. hm(t.ends) .. ')'
  elseif t.ends then cap = t.name .. ' · ends at ' .. hm(t.ends)
  elseif t.left then cap = t.name .. ' · paused'
  else cap = t.name .. ' · ' .. mmss(t.dur) end
  if running and not exact then cap = cap .. ' · min left' end
  if frozen then cap = t.name .. ' · at ' .. hms(exact_at) .. ', tap again' end
  center(gg, kit.short(cap, 40), CAP_Y)
  -- the timers
  local y = BODY_Y
  for k, x in ipairs(timers) do
    local state
    if x.ready then state = 'time\'s up!'
    elseif x.ends then state = plural((timer_left(x) + 59) // 60, 'min', 'min') .. ' left'
    elseif x.left then state = 'paused ' .. mmss(x.left)
    else state = mmss(x.dur) end
    gg:rect(M, y, W - 2 * M, 48, { line_width = k == tsel and 3 or 1 })
    gg:text(M + 12, y + 11, kit.short(x.name, 18), { font = kit.font('medium') })
    local f = kit.font('medium')
    gg:text(W - M - 12 - kit.width(f, state), y + 11, state, { font = f })
    hit(M, y, W - 2 * M, 48, function() tsel = k; exact_until = nil end)
    y = y + 54
  end
  -- the length of the chosen timer, while it is not running (also under Edit)
  if not t.ends and not t.left then
    local adj = function(d) return function() t.dur = clamp(t.dur + d, 60, 24 * 3600 - 60); save() end end
    gg:text(M, 650, 'Length of ' .. kit.short(t.name, 16) .. ' (minutes):', { font = kit.font('small') })
    buttons(gg, { { '-5', adj(-300) }, { '-1', adj(-60) }, { '+1', adj(60) }, { '+5', adj(300) }, { '+30', adj(1800) } }, 680, 50)
  end
  local start_label = t.ready and 'Again' or (t.ends and 'Pause' or (t.left and 'Resume' or 'Start'))
  buttons(gg, {
    { start_label, function()
        local n = now()
        if t.ready then t.ends, t.left, t.ready = n + t.dur, nil, false
        elseif t.ends then t.left, t.ends = math.max(0, t.ends - n), nil
        elseif t.left then t.ends, t.left = n + t.left, nil
        else t.ends, t.left, t.ready = n + t.dur, nil, false end
        save()
      end },
    { 'Reset', function() t.ends, t.left, t.ready = nil, nil, false; save() end, t.ends ~= nil or t.left ~= nil },
    { 'New', function()
        if #timers >= 6 then msg = 'Six timers at most.'; return end
        ask('Name of the new timer', '', 24, function(s) timers[#timers + 1] = { name = s, dur = 5 * 60 }; tsel = #timers end)
      end },
    { 'Edit', function() edit_timer(t) end },
  }, BTN_Y, BTN_H)
end

local function draw_focus(gg)
  local exact, running, _cd, frozen = draw_digits(gg)
  local cap = PHASE[focus.phase]
  if focus.phase == 'work' then cap = cap .. ' ' .. focus.round .. ' of ' .. focus.every end
  if focus.ends then cap = cap .. ' · until ' .. hm(focus.ends)
  elseif focus.left then cap = cap .. ' · paused'
  else cap = cap .. ' · ready' end
  if running and not exact then cap = cap .. ' · min left' end
  if frozen then cap = PHASE[focus.phase] .. ' · at ' .. hms(exact_at) .. ', tap again' end
  center(gg, cap, CAP_Y)
  local idle = not focus.ends and not focus.left
  local function step(field, d, lo, hi)
    return function()
      if not idle then msg = 'Reset first to change the lengths.'; return end
      focus[field] = clamp(focus[field] + d, lo, hi); save()
    end
  end
  stepper(gg, BODY_Y, 'Focus', focus.work .. ' min', step('work', -5, 5, 120), step('work', 5, 5, 120))
  stepper(gg, BODY_Y + 58, 'Short break', focus.short .. ' min', step('short', -1, 1, 30), step('short', 1, 1, 30))
  stepper(gg, BODY_Y + 116, 'Long break', focus.long .. ' min', step('long', -5, 5, 60), step('long', 5, 5, 60))
  stepper(gg, BODY_Y + 174, 'Long break after', tostring(focus.every), step('every', -1, 2, 8), step('every', 1, 2, 8))
  local f = kit.font('medium')
  gg:text(M, BODY_Y + 244, 'Next starts by itself', { font = f })
  kit.button(gg, W - M - 136, BODY_Y + 232, 136, 48, focus.auto and 'On' or 'Off', { line_width = focus.auto and 3 or 1 })
  hit(W - M - 136, BODY_Y + 232, 136, 48, function() focus.auto = not focus.auto; save() end)
  local l = log[today()] or { 0, 0 }
  gg:text(M, BODY_Y + 310, 'Today: ' .. plural(l[2], 'focus', 'focuses') .. ', ' .. minutes_text(l[1]) .. (l[1] >= 60 and ' h' or ' min'),
          { font = f })
  buttons(gg, {
    { focus.ends and 'Pause' or (focus.left and 'Resume' or 'Start'), function()
        local n = now()
        if focus.ends then focus.left, focus.ends = math.max(0, focus.ends - n), nil
        else focus.ends, focus.left = n + (focus.left or focus_dur(focus.phase)), nil end
        save()
      end },
    { 'Skip', function()
        -- the phase ends now, without logging a focus not done
        local was = focus.phase
        if was == 'work' then focus.phase = (focus.round % focus.every == 0) and 'long' or 'short'
        else focus.round = was == 'long' and 1 or focus.round + 1; focus.phase = 'work' end
        local run = focus.ends ~= nil
        focus.left = nil
        focus.ends = run and (now() + focus_dur(focus.phase)) or nil
        msg = 'Skipped: ' .. PHASE[focus.phase] .. ' next.'
        save()
      end },
    { 'Reset', function() focus.ends, focus.left, focus.phase, focus.round = nil, nil, 'work', 1; save() end, not idle or focus.phase ~= 'work' or focus.round ~= 1 },
  }, BTN_Y, BTN_H)
end

local function draw_watch(gg)
  local exact, running, _cd, frozen = draw_digits(gg)
  local e = watch_elapsed()
  local cap
  if running then cap = 'Running since ' .. hm(watch.start - watch.acc) .. (frozen and (' · at ' .. hms(exact_at)) or (exact and '' or ' · minutes'))
  elseif e > 0 then cap = 'Stopped' else cap = 'Tap Start' end
  center(gg, cap, CAP_Y)
  -- laps, newest first
  local f = kit.font('medium')
  local y = BODY_Y
  local n = #watch.laps
  for k = n, math.max(1, n - 6), -1 do
    local prev = k > 1 and watch.laps[k - 1] or 0
    gg:text(M, y, 'Lap ' .. k, { font = f })
    gg:text(170, y, mmss(watch.laps[k] - prev), { font = f })
    local tot = mmss(watch.laps[k])
    gg:text(W - M - kit.width(f, tot), y, tot, { font = f })
    y = y + 40
  end
  if n == 0 then gg:text(M, y, running and 'Lap marks a time and goes on.' or '', { font = kit.font('small') }) end
  buttons(gg, {
    { running and 'Stop' or (e > 0 and 'Go on' or 'Start'), function()
        local t = now()
        if watch.start then watch.acc, watch.start = watch.acc + math.max(0, t - watch.start), nil
        else watch.start = t end
        save()
      end },
    { running and 'Lap' or 'Reset', function()
        if running then
          if #watch.laps >= 99 then table.remove(watch.laps, 1) end
          watch.laps[#watch.laps + 1] = watch_elapsed()
        else watch.acc, watch.laps = 0, {} end
        save()
      end, running or e > 0 },
  }, BTN_Y, BTN_H)
end

local function draw_rounds(gg)
  draw_digits(gg)
  local e = rounds_elapsed()
  local active = rounds.start or rounds.acc > 0
  local p, r = rounds_at(e)
  local cap
  if not active then cap = plural(rounds.count, 'round', 'rounds') .. ': ' .. rounds.work .. ' s work, ' .. rounds.rest .. ' s rest'
  elseif p == 'done' then cap = 'Done: ' .. plural(rounds.count, 'round', 'rounds')
  else cap = (p == 'work' and 'Work' or 'Rest') .. ' · round ' .. r .. ' of ' .. rounds.count .. (rounds.start and '' or ' · paused') end
  center(gg, cap, CAP_Y)
  local function step(field, d, lo, hi)
    return function()
      if active then msg = 'Reset first to change the rounds.'; return end
      rounds[field] = clamp(rounds[field] + d, lo, hi); save()
    end
  end
  stepper(gg, BODY_Y, 'Work', rounds.work .. ' s', step('work', -5, 5, 600), step('work', 5, 5, 600))
  stepper(gg, BODY_Y + 58, 'Rest', rounds.rest .. ' s', step('rest', -5, 0, 600), step('rest', 5, 0, 600))
  stepper(gg, BODY_Y + 116, 'Rounds', tostring(rounds.count), step('count', -1, 1, 50), step('count', 1, 1, 50))
  local total = rounds.count * (rounds.work + rounds.rest) - rounds.rest
  gg:text(M, BODY_Y + 190, 'All of it: ' .. mmss(total), { font = kit.font('medium') })
  gg:text(M, BODY_Y + 230, 'The seconds show while it runs.', { font = kit.font('small') })
  buttons(gg, {
    { rounds.start and 'Pause' or ((active and p ~= 'done') and 'Resume' or 'Start'), function()
        local t = now()
        if rounds.start then rounds.acc, rounds.start = rounds_elapsed(), nil
        else
          if p == 'done' then rounds.acc = 0 end
          rounds.start = t
        end
        save()
      end },
    { 'Reset', function() rounds.start, rounds.acc = nil, 0; save() end, active },
  }, BTN_Y, BTN_H)
end

local function draw_count(gg)
  local c = counters[csel]
  big(gg, tostring(c.n), BIG_Y)
  hit(0, BIG_Y - 10, W, BIG_H + 20, function() c.n = c.n + 1; save() end)
  center(gg, kit.short(c.name, 24) .. ' · the side buttons count too', CAP_Y)
  -- +1 as large as there is room for: the number above it counts too
  gg:rect(M, 324, W - 2 * M, 110, { line_width = 4 })
  local ph, pt = 64, 12                              -- a large +1: a plus of two bars, a segment 1
  gg:rect(W // 2 - 70, 379 - pt // 2, ph, pt, BLACK)
  gg:rect(W // 2 - 70 + ph // 2 - pt // 2, 379 - ph // 2, pt, ph, BLACK)
  seg_text(gg, '1', W // 2 + 6, 337, 84)
  hit(M, 324, W - 2 * M, 110, function() c.n = c.n + 1; save() end)
  local y = 448
  for k, x in ipairs(counters) do
    gg:rect(M, y, W - 2 * M, 40, { line_width = k == csel and 3 or 1 })
    gg:text(M + 12, y + 8, kit.short(x.name, 24), { font = kit.font('medium') })
    local f = kit.font('medium')
    local v = tostring(x.n)
    gg:text(W - M - 12 - kit.width(f, v), y + 8, v, { font = f })
    hit(M, y, W - 2 * M, 40, function() csel = k end)
    y = y + 46
  end
  buttons(gg, {
    { '-1', function() c.n = c.n - 1; save() end },
    { '+10', function() c.n = c.n + 10; save() end },
    { 'Reset', function() confirm('Set ' .. c.name .. ' to 0?', function() c.n = 0; save() end) end, c.n ~= 0 },
    { 'New', function()
        if #counters >= 6 then msg = 'Six counters at most.'; return end
        ask('Name of the new counter', '', 24, function(s) counters[#counters + 1] = { name = s, n = 0 }; csel = #counters end)
      end },
    { 'Edit', function()
        kit.show({ title = c.name, rows = {
          { { 'Rename', function() kit.close(); ask('Name of the counter', c.name, 24, function(s) c.name = s end) end },
            { 'Delete', function() kit.close()
                if #counters == 1 then msg = 'One counter stays.'; return end
                confirm('Delete ' .. c.name .. '?', function() table.remove(counters, csel); csel = math.min(csel, #counters); save() end)
              end } },
          { { 'Close', kit.close } } }, cancel = kit.close })
      end },
  }, BTN_Y, BTN_H)
end

local WD = { 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun' }

local function draw_log(gg)
  local d0 = today()
  local l = log[d0] or { 0, 0 }
  local f = kit.font('medium')
  gg:text(M, 100 + 40, 'Today', { font = kit.font('large') })
  gg:text(M, 182, plural(l[2], 'focus', 'focuses') .. ' · ' .. l[1] .. ' min of focus', { font = f })
  -- the last seven days as bars
  local week, most, total, poms = {}, 30, 0, 0
  for k = 6, 0, -1 do
    local x = log[d0 - k] or { 0, 0 }
    week[#week + 1] = { d0 - k, x[1] }
    most = math.max(most, x[1]); total = total + x[1]; poms = poms + x[2]
  end
  gg:text(M, 236, 'The last 7 days: ' .. total .. ' min, ' .. plural(poms, 'focus', 'focuses'), { font = f })
  local top, base = 290, 620
  local bw = (W - 2 * M) // 7
  for k, wd in ipairs(week) do
    local x = M + (k - 1) * bw
    local h = (base - top) * wd[2] // most
    if wd[2] > 0 then
      gg:rect(x + 10, base - h, bw - 20, h, BLACK)
      local s = tostring(wd[2])
      local sf = kit.font('small')
      gg:text(x + (bw - kit.width(sf, s)) // 2, base - h - 24, s, { font = sf })
    end
    local name = WD[(wd[1] + 3) % 7 + 1]
    local sf = kit.font('small')
    gg:text(x + (bw - kit.width(sf, name)) // 2, base + 8, k == 7 and 'Today' or name, { font = sf })
  end
  gg:line(M, base, W - M, base, { line_width = 2 })
  gg:text(M, 666, 'Minutes of focus a day (the Focus tab).', { font = kit.font('small') })
  buttons(gg, { { 'Clear the log', function() confirm('Clear the whole log?', function() log = {}; save() end) end, next(log) ~= nil } },
          BTN_Y, BTN_H)
end

local more

local DRAW = { draw_timer, draw_focus, draw_watch, draw_rounds, draw_count, draw_log }

function on_draw(c, gg)
  if not gg then return end
  hits = {}
  local ok, e = pcall(function()
    gg:clear(0)
    if flash > 0 and flash % 2 == 1 then
      -- the dark frame: black all over, the message in a paper box (text is always drawn black)
      gg:rect(0, 0, W, H, BLACK)
      gg:rect(40, 330, W - 80, 140, { fill = true, color = 0 })
      local f = kit.font('large')
      local s = kit.short(msg or "Time's up!", 26)
      gg:text((W - kit.width(f, s)) // 2, 385, s, { font = f })
      return
    end
    gg:text(M, 10, 'Timekeeper', { font = kit.font('large') })
    local more_w = 96
    if clock_on and clock_ok then
      local lf = kit.font('large')
      local s = hm(now())
      gg:text(W - M - more_w - 16 - kit.width(lf, s), 14, s, { font = lf })
    end
    kit.button(gg, W - M - more_w, 10, more_w, 44, 'More')
    hit(W - M - more_w, 10, more_w, 44, function() more() end)
    if msg and not kit.modal() then gg:text(M, 52, kit.short(msg, 44), { font = kit.font('small') })
    elseif not clock_ok then gg:text(M, 52, 'The clock is not set: timers stop on leaving.', { font = kit.font('small') }) end
    -- tabs
    local rs = row_rects(#TABS, TAB_Y, TAB_H)
    local sf = kit.font('small')
    for k, name in ipairs(TABS) do
      local r = rs[k]
      gg:rect(r[1], r[2], r[3], r[4], { line_width = k == tab and 4 or 1 })
      local label = name
      while #label > 1 and kit.width(sf, label) > r[3] - 4 do label = kit.drop_last(label) end
      gg:text(r[1] + (r[3] - kit.width(sf, label)) // 2, r[2] + (r[4] - kit.line_h('small')) // 2, label, { font = sf })
      hit(r[1], r[2], r[3], r[4], function() tab = k; exact_until = nil; msg = nil end)
    end
    if kit.modal() then hits = {}; kit.draw_modal(gg); return end
    DRAW[tab](gg)
    if ERR then gg:text(M, H - 24, kit.short('ERR ' .. ERR, 48), { font = kit.font('small') }) end
  end)
  if not ok then pcall(function() gg:text(8, H - 60, kit.short('draw ERR ' .. tostring(e), 46)) end) end
end

------------------------------------------------------------------ more, input

local function set_lock()
  local L = ctx.lockscreen
  if not L then msg = 'This firmware has no app lock screen.'; return end
  local okd, isdef = pcall(function() return L:is_default() end)
  if okd and isdef == true then
    pcall(function() L:clear_default() end)
    msg = 'Lock screen: off.'
  else
    pcall(function() L:set_default() end)
    msg = 'Lock screen: running timers, and today\'s focus.'
  end
end

local function how_to()
  kit.show({ title = 'Timekeeper', lines = {
    'Timer: up to six named timers. Focus: work and breaks in turn (Pomodoro), logged by day. Watch: a stopwatch with laps. Sets: rounds of work and rest for exercise. Count: tally counters. Log: your focus time.',
    'The reader has no sound: a finished timer shows here and on the lock screen. To save power, running timers show whole minutes; tap the big digits for the seconds.',
    'Everything keeps running when you leave the app. While something runs, the reader stays awake (More turns that off).',
  }, rows = { { { 'Close', kit.close } } }, cancel = kit.close })
end

more = function()
  local L = ctx.lockscreen
  local okd, isdef = pcall(function() return L and L:is_default() end)
  local lock_on = okd and isdef == true
  local sec_label = { off = 'Seconds: never', last = 'Seconds: last minute', on = 'Seconds: always' }
  kit.show({ title = 'Timekeeper', lines = { 'Seconds: when running timers show them (always costs more power). Stay awake: the reader does not sleep while something runs, so you see it end (uses more battery).' }, rows = {
    { { sec_label[seconds_mode], function()
        seconds_mode = seconds_mode == 'off' and 'last' or (seconds_mode == 'last' and 'on' or 'off')
        save(); more()
      end } },
    { { stay_awake and 'Stay awake while running: on' or 'Stay awake while running: off', function()
        if not (ctx.device and ctx.device.keep_awake) then msg = 'Staying awake needs firmware 26110201.'; kit.close(); return end
        stay_awake = not stay_awake
        save(); schedule(); more()
      end } },
    { { clock_on and 'Clock: on' or 'Clock: off', function() clock_on = not clock_on; save(); schedule(); more() end } },
    { { flash_on_end and 'Flash when time is up: on' or 'Flash when time is up: off', function()
        flash_on_end = not flash_on_end; save(); more()
      end } },
    { { lock_on and 'Lock screen: on' or 'Lock screen: off', function() kit.close(); set_lock() end } },
    { { 'How it works', how_to }, { 'Close', kit.close } } }, cancel = kit.close })
end

local function tap(x, y)
  if kit.tap_modal(x, y) then return end
  for k = #hits, 1, -1 do
    local h = hits[k]
    if x >= h[1] and x < h[1] + h[3] and y >= h[2] and y < h[2] + h[4] then
      msg = nil
      h[5]()
      return
    end
  end
end

function on_input(c, ev)
  ERR = nil
  local handled = true
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    if ev.type == 'pointer' and ev.phase == 'up' then
      if flash > 0 then stop_flash(); return end      -- a tap ends the flashing
      tick()
      tap(ev.x or 0, ev.y or 0)
    elseif ev.type == 'key' and ev.key == 'back' then
      if ev.phase ~= 'up' and ev.phase ~= nil then return end
      if kit.modal() then
        if kit.modal().cancel then kit.modal().cancel() end
      else handled = false end
    elseif ev.type == 'key' and kit.key_accepted(ev) and not kit.modal() then
      if tab == 5 and (ev.key == 'down' or ev.key == 'up') then      -- on Count, the side buttons count
        local c = counters[csel]
        c.n = c.n + (ev.key == 'down' and 1 or -1)
        save()
      elseif ev.key == 'down' then tab = tab % #TABS + 1; exact_until = nil; msg = nil; save()
      elseif ev.key == 'up' then tab = (tab - 2) % #TABS + 1; exact_until = nil; msg = nil; save() end
    end
  end)
  if not ok then ERR = tostring(e) end
  kit.refresh()
  schedule()
  return handled
end

function on_load(c)
  local ok, e = pcall(function()
    local had = load()
    tick()
    save()
    if not had then how_to() end
  end)
  if not ok then ERR = tostring(e) end
  schedule()
end

function on_resume(c)
  pcall(tick)
  kit.refresh()
  schedule()
end

function on_leave()
  pcall(save)
  pcall(function() if awake_ms > 0 and ctx.device then ctx.device:keep_awake(0) end end)
  awake_ms = 0
end

if rawget(_G, '__TEST') then
  __TEST.api = { tab = function() return tab end, timers = function() return timers end, focus = function() return focus end,
                 watch = function() return watch end, rounds = function() return rounds end, counters = function() return counters end,
                 log = function() return log end, msg = function() return msg end, now = now, today = today,
                 next_wake = next_wake, shown = shown, seconds = function() return seconds_mode end,
                 exact = function() return exact_until end, tick = tick, hm = hm, awake = function() return awake_ms end,
                 flash = function() return flash end }
end
