-- Calendar views for a 480 px wide screen, shared by the app and the lock screen: a month grid,
-- a week of day rows, a day's timeline and an agenda list. Each draws into a box and returns the
-- places a tap can land on ({ x, y, w, h, day = } or { ..., it = }). `env` carries
--   font(name), lh(name), today (day number), now (wall seconds), ws (0 Sunday, 1 Monday first)
-- and insts (C.between for the view's window, see V.window).
-- Lines and frames only: large black areas ghost on e-ink. The host draws ~1024 commands a screen.

local C = require('cal')
local V = {}
local DAY = 86400

-- the days a view covers: first day, number of days
function V.window(mode, day, ws)
  if mode == 'month' then
    local y, m = C.civil(day)
    local first = C.days(y, m, 1)
    local lead = (C.wday(first) - ws) % 7
    return first - lead, 42
  elseif mode == 'week' then
    return day - (C.wday(day) - ws) % 7, 7
  elseif mode == 'agenda' then
    return day, 60
  end
  return day, 1
end

function V.title(mode, day, ws)
  local y, m, d = C.civil(day)
  if mode == 'month' then return C.MONTH[m] .. ' ' .. y end
  if mode == 'week' then
    local a = V.window('week', day, ws)
    local y1, m1, d1 = C.civil(a)
    local y2, m2, d2 = C.civil(a + 6)
    if m1 == m2 then return d1 .. ' - ' .. d2 .. ' ' .. C.MON[m2] .. ' ' .. y2 end
    return d1 .. ' ' .. C.MON[m1] .. (y1 ~= y2 and (' ' .. y1) or '') .. ' - ' .. d2 .. ' ' .. C.MON[m2] .. ' ' .. y2
  end
  if mode == 'agenda' then return 'From ' .. C.date(day) .. ' ' .. y end
  return C.WDAY_LONG[C.wday(day) + 1] .. ' ' .. d .. ' ' .. C.MONTH[m] .. ' ' .. y
end

local function text(gg, x, y, s, f) gg:text(x, y, s, { font = f }) end

------------------------------------------------------------------ month

function V.month(gg, env, day, x, y, w, h)
  local hits = {}
  local yy, mm = C.civil(day)
  local first = C.days(yy, mm, 1)
  local len = C.month_len(yy, mm)
  local g0 = V.window('month', day, env.ws)
  local rows = (first - g0 + len + 6) // 7
  local cw = w // 7
  local fs, fm = env.font('small'), env.font('medium')
  local lh = env.lh('small')
  for k = 0, 6 do
    local s = C.WDAY[(env.ws + k) % 7 + 1]:sub(1, 2)
    text(gg, x + k * cw + (cw - C.width(fs, s)) // 2, y, s, fs)
  end
  local top = y + lh + 4
  local ch = (h - lh - 4) // rows
  for r = 0, rows do gg:line(x, top + r * ch, x + 7 * cw, top + r * ch) end
  for k = 0, 7 do gg:line(x + k * cw, top, x + k * cw, top + rows * ch) end
  local by = C.by_day(env.insts, g0, rows * 7)
  local maxl = (ch - 28) // lh
  for i = 0, rows * 7 - 1 do
    local d = g0 + i
    local cx, cy = x + (i % 7) * cw, top + (i // 7) * ch
    local _y, _m, dn = C.civil(d)
    local inside = d >= first and d < first + len
    text(gg, cx + 5, cy + 3, tostring(dn), inside and fm or fs)
    if d == env.today then
      gg:rect(cx + 2, cy + 2, cw - 3, ch - 3, { line_width = 3 })
    end
    local list = by[d] or {}
    local ly = cy + 28
    for k, it in ipairs(list) do
      if k > maxl then break end
      if k == maxl and #list > maxl then
        text(gg, cx + 4, ly, '+' .. (#list - k + 1), fs)
        break
      end
      text(gg, cx + 4, ly, C.fit(fs, it.sum, cw - 7), fs)
      ly = ly + lh
    end
    hits[#hits + 1] = { x = cx, y = cy, w = cw, h = ch, day = d }
  end
  return hits
end

------------------------------------------------------------------ week

local function short_line(it, day)
  if it.ad or it.s < day * DAY then return it.sum end
  return C.hm(it.s) .. ' ' .. it.sum
end

function V.week(gg, env, day, x, y, w, h)
  local hits = {}
  local start = V.window('week', day, env.ws)
  local rh = h // 7
  local fs, fm, fl = env.font('small'), env.font('medium'), env.font('large')
  local lm = env.lh('medium')
  local by = C.by_day(env.insts, start, 7)
  local lw = 70
  for k = 0, 6 do
    local d = start + k
    local ry = y + k * rh
    local _y, m, dn = C.civil(d)
    text(gg, x + 6, ry + 6, C.WDAY[C.wday(d) + 1], fs)
    text(gg, x + 6, ry + 28, tostring(dn), fl)
    if dn == 1 or k == 0 then text(gg, x + 6 + C.width(fl, tostring(dn)) + 4, ry + 36, C.MON[m], fs) end
    if d == env.today then
      gg:rect(x + 1, ry + 2, w - 2, rh - 3, { line_width = 3 })
    end
    if k > 0 then gg:line(x, ry, x + w, ry) end
    local list = by[d] or {}
    local maxl = math.max(1, (rh - 8) // lm)
    local ly = ry + 5
    for j, it in ipairs(list) do
      if j > maxl then break end
      local s = short_line(it, d)
      if j == maxl and #list > maxl then s = '+' .. (#list - j + 1) .. ' more' end
      text(gg, x + lw + 6, ly, C.fit(fm, s, w - lw - 14), fm)
      ly = ly + lm
    end
    hits[#hits + 1] = { x = x, y = ry, w = w, h = rh, day = d }
  end
  return hits
end

------------------------------------------------------------------ day

-- a line from x1 to x2 at y in dashes of `dash` px with `gap` between, left out where it would
-- cross an event's box
local function hour_line(gg, x1, x2, y, boxes, dash, gap)
  local sx = x1
  while sx < x2 do
    local ex = math.min(sx + dash, x2)
    local cut = false
    for _k, b in ipairs(boxes) do
      if y >= b[2] - 1 and y <= b[2] + b[4] + 1 and ex >= b[1] - 3 and sx <= b[1] + b[3] + 3 then cut = true; break end
    end
    if not cut then gg:line(sx, y, ex, y) end
    sx = ex + gap
  end
end

-- opts.from: start at that hour and show as many hours of opts.ph px as fit, past midnight into the
-- next day (the lock screen: "from now on"; env.insts must then cover two days)
function V.day(gg, env, day, x, y, w, h, opts)
  opts = opts or {}
  local hits = {}
  local fs, fm = env.font('small'), env.font('medium')
  local ls, lm = env.lh('small'), env.lh('medium')
  local base = day * DAY
  local allday, timed, earlier = {}, {}, {}
  for _k, it in ipairs(env.insts) do
    local whole = it.ad or (it.s <= base and it.e >= base + DAY)
    if whole then
      if C.on_day(it, day) then allday[#allday + 1] = it end
    elseif opts.from then
      local from = base + opts.from * 3600
      if it.s < base + 48 * 3600 and (it.e > from or (it.e == it.s and it.s >= from)) then
        timed[#timed + 1] = it
      elseif it.s >= base and it.s < from then
        earlier[#earlier + 1] = it                 -- over already: one line above the hours
      end
    elseif C.on_day(it, day) then
      timed[#timed + 1] = it
    end
  end
  -- all-day events on top
  local ty = y
  for k, ev in ipairs(allday) do
    if k > 3 then
      text(gg, x + 8, ty, '+' .. (#allday - 3) .. ' more all day', fs)
      ty = ty + ls + 2
      break
    end
    gg:rect(x + 4, ty, w - 8, lm + 6)
    text(gg, x + 10, ty + 3, C.fit(fm, ev.sum, w - 24), fm)
    hits[#hits + 1] = { x = x + 4, y = ty, w = w - 8, h = lm + 6, it = ev }
    ty = ty + lm + 10
  end
  if #earlier > 0 then
    local parts = {}
    for _k, it in ipairs(earlier) do parts[#parts + 1] = C.hm(it.s) .. ' ' .. it.sum end
    text(gg, x + 6, ty, C.fit(fs, 'Earlier: ' .. table.concat(parts, ', '), w - 12), fs)
    ty = ty + ls + 4
  end
  local top = ty + 4
  local h0, h1, ph
  local later = {}                      -- today's events that start below the last hour shown
  if opts.from then
    ph = opts.ph or 52
    h0 = opts.from
    local room = y + h - top - 4
    h1 = h0 + math.max(1, room // ph)
    local function hidden()
      later = {}
      for _k, it in ipairs(timed) do
        if it.s >= base + h1 * 3600 and it.s < base + DAY then later[#later + 1] = it end
      end
    end
    hidden()
    -- they get a line at the bottom: give up an hour for it when the hours fill the box
    if #later > 0 and room - (h1 - h0) * ph < ls + 8 and h1 - h0 > 1 then
      h1 = h1 - 1
      hidden()
    end
  else
    -- the hours: 7 to 21, widened to the day's events
    h0, h1 = 7, 21
    for _k, it in ipairs(timed) do
      local a = math.max(0, (it.s - base) // 3600)
      local b = math.min(24, (math.min(it.e, base + DAY) - base + 3599) // 3600)
      if a < h0 then h0 = a end
      if b > h1 then h1 = b end
    end
    ph = (y + h - top - 4) // (h1 - h0)
  end
  local gx = x + 50
  for hr = h0, h1 - 1 do text(gg, x + 6, top + (hr - h0) * ph + 2, string.format('%02d', hr % 24), fs) end
  local function ypos(t)
    local s = math.max(h0 * 3600, math.min(t - base, h1 * 3600)) - h0 * 3600
    return top + s * ph // 3600
  end
  if opts.from then                     -- only what shows between the first and last hour
    local keep = {}
    for _k, it in ipairs(timed) do if it.s < base + h1 * 3600 then keep[#keep + 1] = it end end
    timed = keep
  end
  -- side by side when they overlap: greedy columns inside each group of overlapping events
  local boxes = {}
  local i = 1
  while i <= #timed do
    local group, ends, j = {}, timed[i].e, i
    while j <= #timed and (j == i or timed[j].s < ends) do
      group[#group + 1] = timed[j]
      if timed[j].e > ends then ends = timed[j].e end
      j = j + 1
    end
    local colend, col = {}, {}
    for k, it in ipairs(group) do
      local c = 1
      while colend[c] and colend[c] > it.s do c = c + 1 end
      colend[c], col[k] = math.max(it.e, it.s + 1800), c
    end
    local ncol = #colend
    local cw = (x + w - gx - 2) // ncol
    for k, ev in ipairs(group) do
      local by = ypos(ev.s)
      local bh = math.max(ls + 6, ypos(math.max(ev.e, ev.s + 1800)) - by - 2)
      local bx = gx + (col[k] - 1) * cw
      gg:rect(bx, by + 1, cw - 3, bh)
      boxes[#boxes + 1] = { bx, by + 1, cw - 3, bh }
      local inner = cw - 13
      if bh >= ls + lm + 6 then
        text(gg, bx + 5, by + 3, C.hm(ev.s) .. (ev.e > ev.s and (' - ' .. C.hm(ev.e)) or ''), fs)
        local lines = C.wrap(fm, ev.sum, inner)
        local maxl = math.max(1, (bh - ls - 6) // lm)
        for n = 1, math.min(maxl, #lines) do
          local s = lines[n]
          if n == maxl and #lines > maxl then s = C.fit(fm, s .. ' …', inner) end
          text(gg, bx + 5, by + 3 + ls + (n - 1) * lm, s, fm)
        end
      else
        text(gg, bx + 5, by + 3, C.fit(fs, C.hm(ev.s) .. ' ' .. ev.sum, inner), fs)
      end
      hits[#hits + 1] = { x = bx, y = by, w = cw - 3, h = bh, it = ev }
    end
    i = j
  end
  -- the hours: dashed, and left out where they would cross an event (midnight: a double line)
  for hr = h0, h1 do
    local ly = top + (hr - h0) * ph
    hour_line(gg, gx - 4, x + w, ly, boxes, 12, 8)
    if hr == 24 and hr > h0 then
      hour_line(gg, gx - 4, x + w, ly + 1, boxes, 40, 2)
      hour_line(gg, gx - 4, x + w, ly + 2, boxes, 40, 2)
      text(gg, gx + 4, ly + 3, C.date(day + 1), fs)
    end
  end
  -- now
  if day == env.today then
    local ny = ypos(env.now)
    if ny > top and ny < top + (h1 - h0) * ph then
      gg:line(gx - 10, ny, x + w, ny)
      gg:line(gx - 10, ny + 1, x + w, ny + 1)
    end
  end
  if #later > 0 then
    local parts = {}
    for _k, it in ipairs(later) do parts[#parts + 1] = C.hm(it.s) .. ' ' .. it.sum end
    local s = '+' .. #later .. ' later today: ' .. table.concat(parts, ', ')
    text(gg, x + 6, top + (h1 - h0) * ph + 6, C.fit(fs, s, w - 12), fs)
  end
  if #allday == 0 and #timed == 0 and #later == 0 and #earlier == 0 then
    text(gg, gx + 10, top + ph * 2 + 4, 'No events', fm)
  end
  return hits
end

------------------------------------------------------------------ agenda

local function day_label(env, d)
  local _y, m, dn = C.civil(d)
  local s = C.WDAY_LONG[C.wday(d) + 1] .. ' ' .. dn .. ' ' .. C.MONTH[m]
  if d == env.today then return 'Today, ' .. s end
  if d == env.today + 1 then return 'Tomorrow, ' .. s end
  return s
end

-- the agenda as rows: { day = d } headings and { it = , day = d } events, days with events only
function V.agenda_rows(env, first, n)
  local rows = {}
  local by = C.by_day(env.insts, first, n)
  for d = first, first + n - 1 do
    local list = by[d]
    if list then
      rows[#rows + 1] = { day = d }
      for _k, it in ipairs(list) do rows[#rows + 1] = { it = it, day = d } end
    end
  end
  return rows
end

local HEAD_H, ROW1_H, ROW2_H = 38, 34, 56

local function row_h(r) return r.it and ((r.it.loc and r.it.loc ~= '') and ROW2_H or ROW1_H) or HEAD_H end

-- an event's time on its day, on one line: "10:30 - 11:30", "all day", "... - 09:00" when it began
-- the day before, "22:00 - ..." when it goes on past midnight
local function span(it, day)
  if it.ad then return 'all day' end
  local a = it.s < day * DAY and '...' or C.hm(it.s)
  if it.e == it.s then return a end
  return a .. ' - ' .. (it.e > (day + 1) * DAY and '...' or C.hm(it.e))
end

-- draws rows from `from` while they fit (gg nil: only measures); -> hits, the first row not drawn
function V.agenda(gg, env, rows, from, x, y, w, h)
  local hits = {}
  local fs, fm = env.font('small'), env.font('medium')
  local tw = C.width(fs, '00:00 - 00:00') + 16           -- the time column
  local ty, k = y, from
  while k <= #rows do
    local r = rows[k]
    local rh = row_h(r)
    -- a heading needs its first event under it
    local need = rh + ((not r.it and rows[k + 1]) and row_h(rows[k + 1]) or 0)
    if ty + need > y + h then break end
    if gg then
      if r.it then
        local it = r.it
        text(gg, x + 6, ty + 6, C.fit(fs, span(it, r.day), tw - 10), fs)
        text(gg, x + tw, ty + 3, C.fit(fm, it.sum, w - tw - 8), fm)
        if it.loc and it.loc ~= '' then text(gg, x + tw, ty + 30, C.fit(fs, it.loc, w - tw - 8), fs) end
        -- a dashed line to the next event of the same day
        local nxt = rows[k + 1]
        if nxt and nxt.it and ty + rh + row_h(nxt) <= y + h then hour_line(gg, x + 4, x + w, ty + rh - 1, {}, 12, 8) end
      else
        text(gg, x + 4, ty + 8, day_label(env, r.day), fm)
        gg:line(x, ty + HEAD_H - 4, x + w, ty + HEAD_H - 4)
        if r.day == env.today then gg:line(x, ty + HEAD_H - 3, x + w, ty + HEAD_H - 3) end
      end
    end
    if r.it then hits[#hits + 1] = { x = x, y = ty, w = w, h = rh, it = r.it } end
    ty = ty + rh
    k = k + 1
  end
  return hits, k
end

return V
