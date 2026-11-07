-- Lock-screen entry for Timekeeper: what runs, from lock.txt (the app writes it), computed from
-- the end moments, so it is right whenever the reader wakes it (once a minute):
--   end|<label>|<epoch it ends>      from|<label>|<epoch it started>      today|<focus min>|<focuses>
-- The first running timer gets big digits (minutes left, rounded up); "Time's up" once it ends.

local W, H = 480, 800
local M = 24
local BLINK_SECS = 180               -- after an end, the lock screen blinks this long

local function read(name)
  local ok, s = pcall(function() return ctx.storage:read(name) end)
  return (ok and type(s) == 'string') and s or nil
end
local function font(name) return ctx.fonts and ctx.fonts[name] end
local function width(f, s)
  local ok, w = pcall(function() return f:measure(s) end)
  return (ok and type(w) == 'number') and w or #s * 11
end

local SEG = { ['0'] = 'abcdef', ['1'] = 'bc', ['2'] = 'abged', ['3'] = 'abgcd', ['4'] = 'fgbc', ['5'] = 'afgcd',
              ['6'] = 'afgedc', ['7'] = 'abc', ['8'] = 'abcdefg', ['9'] = 'abcdfg' }
local BLACK = { fill = true }

local function seg_width(s, h)
  local w = 0
  for ch in s:gmatch('.') do w = w + (ch == ':' and h * 22 // 100 or h * 55 // 100) + h * 14 // 100 end
  return w - h * 14 // 100
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
      if has('f') then gg:rect(x, y + t // 2, t, mid - y, BLACK) end
      if has('b') then gg:rect(x + dw - t, y + t // 2, t, mid - y, BLACK) end
      if has('e') then gg:rect(x, mid - t // 2, t, y + h - mid, BLACK) end
      if has('c') then gg:rect(x + dw - t, mid - t // 2, t, y + h - mid, BLACK) end
      x = x + dw + gap
    end
  end
end

local function minutes_text(m)
  if m >= 60 then return string.format('%d:%02d', m // 60, m % 60) end
  return tostring(m)
end

function on_draw(c, gg)
  if not gg then return end
  local ok, err = pcall(function()
    gg:clear(0)
    local okn, t = pcall(function() return ctx.clock:now() end)
    local now = okn and type(t) == 'table' and tonumber(t.epoch_sec)
    if okn and type(t) == 'table' and tonumber(t.hour) then
      gg:text(M, 24, string.format('%02d:%02d', t.hour, t.minute or 0), { font = font('large') })
    end
    gg:text(W - M - width(font('medium'), 'Timekeeper'), 28, 'Timekeeper', { font = font('medium') })
    gg:line(M, 70, W - M, 70)
    local items, today = {}, nil
    for line in ((read('lock.txt') or '') .. '\n'):gmatch('([^\n]*)\n') do
      local kind, label, v = line:match('^(%a+)|([^|]*)|(.*)$')
      if kind == 'today' then
        today = { tonumber(label) or 0, tonumber(v) or 0 }
      elseif kind and tonumber(v) then items[#items + 1] = { kind, label, tonumber(v) } end
    end
    -- around an end, wake every 30 s (the shortest the reader allows) instead of every minute; for
    -- 3 minutes after it, every other wake is a dark frame: a slow blink, since one session draws
    -- one frame and nothing more
    if now then
      local near, blink = false, nil
      for _k, it in ipairs(items) do
        if it[1] == 'end' then
          local left = it[3] - now
          if left <= 90 and left > -BLINK_SECS then near = true end
          if left <= 0 and left > -BLINK_SECS and not blink then blink = it end
        end
      end
      pcall(function() if ctx.lock then ctx.lock:set_interval(near and 30 or 60) end end)
      if blink then
        pcall(function() ctx:invalidate('full') end)       -- no ghost of the dark frame on the light one
        if ((now - blink[3]) // 30) % 2 == 0 then
          gg:rect(0, 0, W, H, BLACK)
          gg:rect(40, 300, W - 80, 200, { fill = true, color = 0 })
          local lf = font('large')
          local s1, s2 = 'Time\'s up!', blink[2]
          gg:text((W - width(lf, s1)) // 2, 340, s1, { font = lf })
          gg:text((W - width(lf, s2)) // 2, 400, s2, { font = lf })
          return
        end
      end
    end
    local y = 100
    local first = true
    for _k, it in ipairs(items) do
      local text
      if not now then text = 'running'
      elseif it[1] == 'end' then
        local left = it[3] - now
        if left <= 0 then text = 'time\'s up!'
        else
          local m = (left + 59) // 60
          text = m == 1 and '1 min left' or (minutes_text(m) .. (m >= 60 and ' h left' or ' min left'))
          if first then
            gg:text(M, y, it[2], { font = font('large') })
            seg_text(gg, minutes_text(m), W // 2, y + 50, 150)
            local cap = (m >= 60 and 'h:min left' or 'min left')
            if tonumber(t.hour) then
              local wall = (tonumber(t.hour) * 3600 + (tonumber(t.minute) or 0) * 60 + (tonumber(t.second) or 0) + left) % 86400
              cap = cap .. string.format(' · until %02d:%02d', wall // 3600, wall // 60 % 60)
            end
            local f = font('medium')
            gg:text((W - width(f, cap)) // 2, y + 214, cap, { font = f })
            y = y + 270
            first = false
            text = nil
          end
        end
      else
        local m = math.max(0, now - it[3]) // 60
        text = 'running ' .. minutes_text(m) .. (m >= 60 and ' h' or ' min')
      end
      if text then
        gg:text(M, y, it[2], { font = font('medium') })
        local f = font('medium')
        gg:text(W - M - width(f, text), y, text, { font = f })
        y = y + 44
      end
      if y > H - 120 then break end
    end
    if #items == 0 then gg:text(M, y, 'Nothing running.', { font = font('large') }); y = y + 60 end
    if today then
      local s = 'Today: ' .. today[2] .. (today[2] == 1 and ' focus, ' or ' focuses, ') .. today[1] .. ' min'
      gg:line(M, H - 80, W - M, H - 80)
      gg:text(M, H - 64, s, { font = font('medium') })
    end
  end)
  if not ok then pcall(function() gg:text(24, H - 40, 'Timekeeper: ' .. tostring(err)) end) end
end
