-- Calendar pieces shared by the app (src/main.lua) and the lock screen (lockscreen.lua, which
-- carries its own copy: lock entries load alone): dates without `os`, an iCalendar (RFC 5545
-- subset) reader that keeps only what is near today, recurrence, the per-calendar cache and the
-- calendar list. A port of KOReader's calendar.koplugin (calendar_ics/recur/store).
--
-- Times are "wall seconds": local wall-clock time counted from 1970-01-01 as if it were UTC, so a
-- day is always 86400 and the date of t is t // 86400. ICS times with Z are moved by the device's
-- UTC offset; times with a TZID are taken as they are written (right when the calendar's zone is
-- the reader's). Numbers may be 32-bit on the device, so nothing goes past 2037.
--
-- calendars.txt: one calendar a line, "Name|address|on" (or just the address; "off" hides it).
-- c<hash>.txt:   a calendar's cache, "#cal<TAB>updated<TAB>offset<TAB>bytes" then one event a line,
--                start, end, all-day, RRULE, EXDATEs, UID, title, place, notes (tab-separated).

local C = {}

C.MAXT = 2145916799                 -- 2037-12-31 23:59:59
local DAY = 86400
local KEEP_BACK, KEEP_AHEAD = 62 * DAY, 400 * DAY
local MAX_EVENTS = 600

C.WDAY = { 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat' }
C.WDAY_LONG = { 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday' }
C.MON = { 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' }
C.MONTH = { 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September',
            'October', 'November', 'December' }

------------------------------------------------------------------ dates

-- days since 1970-01-01 (H. Hinnant's civil algorithms; // floors, as they need)
function C.days(y, m, d)
  if m <= 2 then y = y - 1 end
  local era = y // 400
  local yoe = y - era * 400
  local doy = (153 * (m + (m > 2 and -3 or 9)) + 2) // 5 + d - 1
  return era * 146097 + yoe * 365 + yoe // 4 - yoe // 100 + doy - 719468
end
function C.civil(z)
  z = z + 719468
  local era = z // 146097
  local doe = z - era * 146097
  local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
  local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
  local mp = (5 * doy + 2) // 153
  local d = doy - (153 * mp + 2) // 5 + 1
  local m = mp < 10 and mp + 3 or mp - 9
  return yoe + era * 400 + (m <= 2 and 1 or 0), m, d
end
function C.month_len(y, m)
  if m == 12 then return 31 end
  return C.days(y, m + 1, 1) - C.days(y, m, 1)
end
function C.ts(y, m, d, h, mi, s)
  if y > 2037 then return C.MAXT end
  return C.days(y, m, d) * DAY + (h or 0) * 3600 + (mi or 0) * 60 + (s or 0)
end
function C.wday(day) return (day + 4) % 7 end            -- 0 = Sunday

-- the clock: UTC seconds and the UTC offset (from the wall hour the device reports)
function C.clock()
  local ok, t = pcall(function() return ctx.clock:now() end)
  if not ok or type(t) ~= 'table' or not tonumber(t.epoch_sec) then return 0, 0 end
  local e = math.floor(tonumber(t.epoch_sec))
  local h = tonumber(t.hour)
  if not h then
    local l = tonumber(t.local_sec)                -- the local time as seconds since 1970
    if l and math.abs(l - e) <= 14 * 3600 then return e, ((math.floor(l) - e + 450) // 900) * 900 end
    return e, 0
  end
  local off = math.floor(h) * 3600 + math.floor(tonumber(t.minute) or 0) * 60 + math.floor(tonumber(t.second) or 0) - e % DAY
  if off > 14 * 3600 then off = off - DAY elseif off < -12 * 3600 then off = off + DAY end
  return e, ((off + 450) // 900) * 900
end

function C.hm(t)
  local s = t % DAY
  return string.format('%02d:%02d', s // 3600, s % 3600 // 60)
end
-- "Tue 27 Oct" / "Tuesday 27 October 2026"
function C.date(day, long)
  local y, m, d = C.civil(day)
  if long then return C.WDAY_LONG[C.wday(day) + 1] .. ' ' .. d .. ' ' .. C.MONTH[m] .. ' ' .. y end
  return C.WDAY[C.wday(day) + 1] .. ' ' .. d .. ' ' .. C.MON[m]
end
-- when an event happens, in words
function C.when(it)
  local d0 = it.s // DAY
  if it.ad then
    local last = (it.e - 1) // DAY
    if last <= d0 then return C.date(d0) .. ', all day' end
    return C.date(d0) .. ' - ' .. C.date(last) .. ', all day'
  end
  local d1 = it.e // DAY
  if it.e == it.s then return C.date(d0) .. ', ' .. C.hm(it.s) end
  if d1 == d0 or (d1 == d0 + 1 and it.e % DAY == 0) then return C.date(d0) .. ', ' .. C.hm(it.s) .. ' - ' .. C.hm(it.e) end
  return C.date(d0) .. ' ' .. C.hm(it.s) .. ' - ' .. C.date(d1) .. ' ' .. C.hm(it.e)
end

------------------------------------------------------------------ text

function C.width(f, s)
  local ok, w = pcall(function() return f:measure(s) end)
  return (ok and type(w) == 'number') and w or #s * 10
end
local function drop_last(s) return (s:gsub('[%z\1-\127\192-\255][\128-\191]*$', '')) end
-- s cut with an ellipsis to fit maxw
function C.fit(f, s, maxw)
  s = tostring(s or '')
  if C.width(f, s) <= maxw then return s end
  local t = s:sub(1, math.max(1, maxw // 4))
  while #t > 0 and not utf8.len(t) do t = t:sub(1, -2) end      -- not inside a letter
  while #t > 0 and C.width(f, t .. '…') > maxw do t = drop_last(t) end
  return t .. '…'
end
-- word wrap (ASCII spaces only); a word wider than the line is broken
function C.wrap(f, s, maxw)
  local out = {}
  for para in (tostring(s or '') .. '\n'):gmatch('([^\n]*)\n') do
    local line = ''
    for word in para:gmatch('[^ \t]+') do
      local cand = line == '' and word or (line .. ' ' .. word)
      if C.width(f, cand) <= maxw then
        line = cand
      else
        if line ~= '' then out[#out + 1] = line end
        local w = word
        while C.width(f, w) > maxw do
          local cut = w
          while #cut > 1 and C.width(f, cut) > maxw do cut = drop_last(cut) end
          out[#out + 1] = cut
          w = w:sub(#cut + 1)
        end
        line = w
      end
    end
    out[#out + 1] = line
  end
  return out
end
local function cut(s, n)
  if #s <= n then return s end
  return drop_last(s:sub(1, n)) .. '…'
end

------------------------------------------------------------------ the calendar list

-- a short name for a cache file: two Adler-style sums (stays far below 2^31)
function C.hash(s)
  local a, b = 1, 0
  for k = 1, #s do a = (a + s:byte(k)) % 65521; b = (b + a) % 65521 end
  return string.format('%04x%04x', b, a)
end
function C.cache_name(url) return 'c' .. C.hash(url) .. '.txt' end

function C.fix_url(u)
  u = u:gsub('^[ \t]+', ''):gsub('[ \t\r]+$', '')
  return (u:gsub('^webcals?://', 'https://'))
end

------------------------------------------------------------------ fetching

local UA = 'XteinkLicoriceCalendar/1.0 (https://github.com/omer-faruq/touch-licorice-apps)'

-- the request for a calendar. gz asks for the file compressed: Google's iCal file holds a
-- calendar's whole history, and the reader takes in only 128 KB of an answer (gzip makes it
-- about a quarter).
function C.request(url, gz)
  local headers = { ['User-Agent'] = UA, ['Accept'] = 'text/calendar, */*' }
  if gz then headers['Accept-Encoding'] = 'gzip' end
  return { url = url, method = 'GET', timeout_ms = 45000, headers = headers }
end

-- where a sync is, in sync_step.txt: when the reader closes the app mid-way (a callback that runs
-- too long is closed without a Lua error), the next start knows the step
function C.step(s) pcall(function() ctx.storage:write('sync_step.txt', s) end) end
-- give memory back now (the host has no collectgarbage; ctx.gc's calls are not documented)
local FREE = { function() ctx.gc:collect() end, function() ctx.gc('collect') end, function() ctx.gc:full() end,
               function() ctx.gc:step() end, function() ctx.gc.collect() end }
local free_k = nil                    -- the call that worked; false: none does
function C.free()
  if free_k == false then return end
  if free_k then pcall(FREE[free_k]); return end
  for k, f in ipairs(FREE) do
    if pcall(f) then free_k = k; return end
  end
  free_k = false
end

-- gzip -> text with the firmware's zlib (which call it takes is not documented: each is tried)
function C.gunzip(b, log)
  local z = ctx.zlib
  if not z then return nil end
  local tries = {
    function() return z:decompress(b) end,
    function() return z:decompress(b, 'gzip') end,
    function() return z:decompress(b, { format = 'gzip' }) end,
    function() return z:decompress(b, { gzip = true }) end,
    function() return z:gunzip(b) end,
    function() return z:inflate(b) end,
  }
  for k, f in ipairs(tries) do
    if log then C.step('unpack ' .. k .. ', ' .. (#b // 1024) .. ' KB packed') end
    local ok, out = pcall(f)
    if ok and type(out) == 'string' and out:find('BEGIN:VCALENDAR', 1, true) then return out end
  end
  return nil
end

-- does the firmware's zlib unpack gzip at all (a tiny calendar, packed)
local SAMPLE = '\31\139\8\0\0\0\0\0\2\10\115\114\117\247\244\179\10\115\118\244\113\245\115\113\12\226\229\2\82\200\92\0\242\161\89\152\32\0\0\0'
local gz_ok = nil
function C.gunzip_works()
  if gz_ok == nil then gz_ok = C.gunzip(SAMPLE) ~= nil end
  return gz_ok
end

-- the answer -> the calendar text, or nil, why and what went wrong ('gzip': it came compressed
-- and could not be unpacked; 'cut': it ended early). A cut-off file is never used: events would
-- be missing at random, as Google sends them in a different order each time.
function C.answer(resp, log)
  if type(resp) ~= 'table' or type(resp.body) ~= 'string' then return nil, 'no answer' end
  local body = resp.body
  resp.body = nil                                -- one copy less while it is unpacked and read
  local code = tonumber(resp.status) or tonumber(resp.code)
  if code and code >= 400 then return nil, 'HTTP ' .. code end
  local packed = 0
  if body:sub(1, 2) == '\31\139' then
    packed = #body
    C.free()
    local text = C.gunzip(body, log)
    if not text then
      if C.gunzip_works() then                   -- it unpacks, so this answer ended early
        return nil, 'cut off after ' .. (#body // 1024) .. ' KB packed: too big for the reader', 'cut'
      end
      return nil, 'could not unpack', 'gzip'
    end
    body, text = text, nil
    C.free()
  end
  if not body:find('BEGIN:VCALENDAR', 1, true) then return nil, 'not an iCal address' end
  if not body:find('END:VCALENDAR', 1, true) then
    return nil, 'cut off after ' .. ((packed > 0 and packed or #body) // 1024) .. ' KB: too big for the reader', 'cut'
  end
  return body, nil, nil, packed
end

function C.parse_list(text)
  local out = {}
  for ln in (text or ''):gmatch('[^\n]+') do
    local l = ln:gsub('\r', ''):gsub('^[ \t]+', '')
    if l ~= '' and l:sub(1, 1) ~= '#' then
      local parts = {}
      for p in (l .. '|'):gmatch('([^|]*)|') do parts[#parts + 1] = p end
      local name, url, on
      if parts[1]:match('^%a+://') then url, on = parts[1], parts[2] else name, url, on = parts[1], parts[2], parts[3] end
      if url and url:match('^%a+://') then
        url = C.fix_url(url)
        if not name or not name:match('%S') then name = url:match('^https?://([^/]+)') or 'Calendar' end
        out[#out + 1] = { name = (name:gsub('^[ \t]+', ''):gsub('[ \t]+$', '')), url = url,
                          on = not (on and on:lower():match('^%s*off')) }
      end
    end
  end
  return out
end
function C.list_text(list)
  local out = { '# Calendar: one calendar a line, Name|address|on (or off). The address is the',
                '# calendar\'s secret iCal address (Google: Settings > the calendar > Integrate calendar).' }
  for _k, c in ipairs(list) do out[#out + 1] = c.name:gsub('|', '/') .. '|' .. c.url .. '|' .. (c.on and 'on' or 'off') end
  return table.concat(out, '\n') .. '\n'
end

------------------------------------------------------------------ reading iCalendar

-- "20261027" (all day), "20261027T090000" (wall), "20261027T060000Z" (UTC, moved by off)
function C.parse_dt(v, off)
  local y, m, d, rest = v:match('^(%d%d%d%d)(%d%d)(%d%d)(.*)$')
  if not y then return nil end
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  local H, M, S, z = rest:match('^T(%d%d)(%d%d)(%d%d)(Z?)')
  if not H then return C.ts(y, m, d), true end
  local t = C.ts(y, m, d, tonumber(H), tonumber(M), tonumber(S))
  if z == 'Z' and t < C.MAXT then t = t + (off or 0) end
  return t, false
end
-- "PT1H30M", "P2D", "-P1W" -> seconds
function C.parse_dur(v)
  local sign, body = v:match('^([+%-]?)P(.*)$')
  if not body then return nil end
  local dp, tp = body:match('^([^T]*)T?(.*)$')
  local s = 0
  local w = dp:match('(%d+)W'); if w then s = s + tonumber(w) * 7 * DAY end
  local d = dp:match('(%d+)D'); if d then s = s + tonumber(d) * DAY end
  local h = tp:match('(%d+)H'); if h then s = s + tonumber(h) * 3600 end
  local mi = tp:match('(%d+)M'); if mi then s = s + tonumber(mi) * 60 end
  local se = tp:match('(%d+)S'); if se then s = s + tonumber(se) end
  return sign == '-' and -s or s
end

local ENT = { nbsp = ' ', lt = '<', gt = '>', quot = '"', amp = '&', apos = "'", ['#39'] = "'" }
local function text_value(v, max)
  v = v:gsub('\\([nN,;\\])', function(c) if c == 'n' or c == 'N' then return '\n' end return c end)
  if v:find('<', 1, true) then              -- Google sends some notes as HTML
    v = v:gsub('<[Bb][Rr][^>]*>', '\n'):gsub('</?[Pp][^>]*>', '\n'):gsub('</?[Ll][Ii][^>]*>', '\n'):gsub('<[^>]*>', '')
    v = v:gsub('&(#?%w+);', function(e) return ENT[e] end)
  end
  v = v:gsub('\r', ''):gsub('[ \t]+\n', '\n'):gsub('\n\n\n+', '\n\n'):gsub('^[ \t\n]+', ''):gsub('[ \t\n]+$', '')
  return cut(v, max)
end

-- the property name, its parameters and the value (a ':' inside a quoted parameter is skipped)
local function split_prop(l)
  local name, rest = l:match('^([%w%-]+)(.*)$')
  if not name then return nil end
  local c = rest:find(':', 1, true)
  if not c then return nil end
  local q = rest:find('"', 1, true)
  if q and q < c then
    local inq = false
    c = nil
    for k = 1, #rest do
      local ch = rest:byte(k)
      if ch == 34 then inq = not inq elseif ch == 58 and not inq then c = k; break end
    end
    if not c then return nil end
  end
  return name:upper(), rest:sub(1, c - 1), rest:sub(c + 1)
end

local WD = { SU = 0, MO = 1, TU = 2, WE = 3, TH = 4, FR = 5, SA = 6 }
-- an RRULE's parts; `till` is its UNTIL in wall seconds
function C.rule(rr, off)
  local r = { freq = 'DAILY', interval = 1 }
  for k, v in rr:gmatch('([^=;]+)=([^;]*)') do
    local key = k:upper()
    if key == 'FREQ' then r.freq = v:upper()
    elseif key == 'INTERVAL' then r.interval = math.max(1, tonumber(v) or 1)
    elseif key == 'COUNT' then r.count = tonumber(v)
    elseif key == 'UNTIL' then
      local t, ad = C.parse_dt(v, off)
      if t then r.till = ad and t + DAY - 1 or t end
    elseif key == 'BYDAY' then
      r.byday = {}
      for part in v:gmatch('[^,]+') do
        local n, wd = part:upper():match('^([+%-]?%d*)(%a%a)$')
        if wd and WD[wd] then r.byday[#r.byday + 1] = { n = tonumber(n), wd = WD[wd] } end
      end
    elseif key == 'BYMONTHDAY' then
      r.bymd = {}
      for part in v:gmatch('[^,]+') do if tonumber(part) then r.bymd[#r.bymd + 1] = tonumber(part) end end
    elseif key == 'BYMONTH' then
      r.bymonth = {}
      for part in v:gmatch('[^,]+') do if tonumber(part) then r.bymonth[tonumber(part)] = true end end
    end
  end
  return r
end

-- the properties read, and how much of a long one is kept (raw, before cleaning)
local WANT = { SUMMARY = true, DTSTART = true, DTEND = true, DURATION = true, LOCATION = true, DESCRIPTION = true,
               UID = true, RRULE = true, ['RECURRENCE-ID'] = true, STATUS = true, EXDATE = true }
local TEXT_MAX = { DESCRIPTION = 1600, SUMMARY = 500, LOCATION = 400 }

-- iCalendar text -> events near `today` (a day number): those within two months back and
-- 400 days ahead, and every repeating one that has not ended. Notes are cut to keep memory low.
-- C.parser reads it in pieces: p.step(bytes) reads about that many and is true when done, then
-- p.events (p.pos of p.size tells how far it is). The host closes an app whose callback runs too
-- long ("callback exceeded its time budget"), and reading 200 KB at once did on the device.
function C.parser(body, off, today)
  local w0, w1 = today * DAY - KEEP_BACK, today * DAY + KEEP_AHEAD
  local events, moved = {}, {}
  local cur, depth = nil, 0

  local function finish(ev)
    if not ev.s then return end
    if not ev.e then ev.e = ev.dur and ev.s + ev.dur or (ev.ad and ev.s + DAY or ev.s) end
    if ev.e < ev.s then ev.e = ev.s end
    if ev.rid then
      ev.rr = nil                               -- one changed (or cancelled) instance of a series
      if ev.uid then
        local l = moved[ev.uid] or {}
        l[#l + 1] = ev.rid
        moved[ev.uid] = l
      end
    end
    if ev.cancel then return end
    if ev.rr then
      local r = C.rule(ev.rr, off)
      if r.till and r.till < w0 then return end
    elseif ev.e < w0 or ev.s > w1 then
      return
    end
    if ev.desc then ev.desc = text_value(ev.desc, 400) end    -- only for the events kept
    events[#events + 1] = ev
  end

  local function prop(l)
    local name, params, v = split_prop(l)
    if not name then return end
    if name == 'BEGIN' then
      if v == 'VEVENT' then cur, depth = { ex = {}, sum = '' }, 0 elseif cur then depth = depth + 1 end
    elseif name == 'END' then
      if v == 'VEVENT' then
        if cur then finish(cur) end
        cur = nil
      elseif cur and depth > 0 then depth = depth - 1 end
    elseif cur and depth == 0 then           -- an alarm's own SUMMARY must not replace the title
      if name == 'SUMMARY' then cur.sum = text_value(v, 120)
      elseif name == 'DTSTART' then cur.s, cur.ad = C.parse_dt(v, off)
      elseif name == 'DTEND' then cur.e = C.parse_dt(v, off)
      elseif name == 'DURATION' then cur.dur = C.parse_dur(v)
      elseif name == 'LOCATION' then cur.loc = text_value(v, 100)
      elseif name == 'DESCRIPTION' then cur.desc = v                 -- cleaned in finish, if kept
      elseif name == 'UID' then cur.uid = v:sub(1, 80)
      elseif name == 'RRULE' then cur.rr = v
      elseif name == 'RECURRENCE-ID' then cur.rid = C.parse_dt(v, off)
      elseif name == 'STATUS' then cur.cancel = v:upper() == 'CANCELLED'
      elseif name == 'EXDATE' then
        for part in v:gmatch('[^,]+') do
          local t = C.parse_dt(part, off)
          if t then cur.ex[#cur.ex + 1] = t end
        end
      end
    end
  end

  -- Unfold as we go (a line starting with a space or tab continues the one before), copying out
  -- only the properties used: the reader has about 1 MB for everything, the unpacked calendar
  -- takes a fifth of it, and the garbage of copying every line ran it out on the device.
  -- A property's pieces are joined once, and only up to what is kept of it.
  local pos, n = 1, #body
  local parts, plen, pmax = nil, 0, 0
  local count = 0
  local p = { pos = 1, size = n }
  function p.step(budget)
    if p.events then return true end
    local stop = math.min(n + 1, pos + budget)
    while pos <= n and pos < stop do
      local e = body:find('\n', pos, true) or n + 1
      local last = e - 1
      if last >= pos and body:byte(last) == 13 then last = last - 1 end
      local c1 = body:byte(pos)
      if c1 == 32 or c1 == 9 then
        if parts and plen < pmax and last > pos then
          local piece = body:sub(pos + 1, math.min(last, pos + pmax - plen))
          parts[#parts + 1] = piece
          plen = plen + #piece
        end
      else
        if parts then prop(#parts == 1 and parts[1] or table.concat(parts)); parts = nil end
        local name = body:match('^[%w%-]+', pos)
        if name then
          name = name:upper()
          -- outside an event and inside its alarms only BEGIN and END matter
          if name == 'BEGIN' or name == 'END' or (cur and depth == 0 and WANT[name]) then
            pmax = TEXT_MAX[name] or 3000
            parts = { body:sub(pos, math.min(last, pos + pmax - 1)) }
            plen = #parts[1]
          end
        end
        count = count + 1
        if count % 400 == 0 then C.free() end
      end
      pos = e + 1
    end
    p.pos = pos
    if pos <= n then return false end
    if parts then prop(#parts == 1 and parts[1] or table.concat(parts)); parts = nil end

    for _k, ev in ipairs(events) do
      local m = ev.rr and ev.uid and moved[ev.uid]
      if m then for _j, t in ipairs(m) do ev.ex[#ev.ex + 1] = t end end
    end
    -- far too many: keep the repeating ones and those nearest today
    if #events > MAX_EVENTS then
      local now = today * DAY
      table.sort(events, function(a, b)
        local da = a.rr and -1 or math.abs(a.s - now)
        local db = b.rr and -1 or math.abs(b.s - now)
        return da < db
      end)
      for k = #events, MAX_EVENTS + 1, -1 do events[k] = nil end
    end
    p.events, body = events, nil
    return true
  end
  return p
end

function C.parse_ics(body, off, today)
  local p = C.parser(body, off, today)
  while not p.step(1000000000) do end
  return p.events
end

------------------------------------------------------------------ the cache

local ESC = { ['\\'] = '\\\\', ['\t'] = '\\t', ['\n'] = '\\n' }
local UNESC = { t = '\t', n = '\n', ['\\'] = '\\' }
local function esc(s) return (tostring(s or ''):gsub('[\\\t\n]', ESC)) end
local function unesc(s) return (s:gsub('\\(.)', UNESC)) end
local function fields(l)
  local out, pos = {}, 1
  while true do
    local i = l:find('\t', pos, true)
    if not i then out[#out + 1] = l:sub(pos); return out end
    out[#out + 1] = l:sub(pos, i - 1)
    pos = i + 1
  end
end

function C.cache_text(events, updated, off, bytes, packed)
  local out = { '#cal\t' .. updated .. '\t' .. off .. '\t' .. (bytes or 0) .. '\t' .. (packed or 0) }
  for _k, ev in ipairs(events) do
    out[#out + 1] = table.concat({ ev.s, ev.e, ev.ad and 1 or 0, esc(ev.rr), table.concat(ev.ex or {}, ','),
                                   esc(ev.uid), esc(ev.sum), esc(ev.loc), esc(ev.desc) }, '\t')
  end
  return table.concat(out, '\n')
end
-- -> events, updated (UTC seconds), bytes, packed bytes (0: not gzip); nil when there is no cache
function C.load_cache(text)
  if not text or text:sub(1, 4) ~= '#cal' then return nil end
  local events, updated, bytes, packed = {}, 0, 0, 0
  for l in text:gmatch('[^\n]+') do
    local f = fields(l)
    if f[1] == '#cal' then
      updated, bytes, packed = tonumber(f[2]) or 0, tonumber(f[4]) or 0, tonumber(f[5]) or 0
    elseif #f >= 9 and tonumber(f[1]) then
      local ex = {}
      for t in f[5]:gmatch('[^,]+') do ex[#ex + 1] = tonumber(t) end
      local d = unesc(f[9])
      events[#events + 1] = { s = tonumber(f[1]), e = tonumber(f[2]), ad = f[3] == '1', rr = f[4] ~= '' and unesc(f[4]) or nil,
                              ex = ex, uid = f[6] ~= '' and unesc(f[6]) or nil, sum = unesc(f[7]),
                              loc = f[8] ~= '' and unesc(f[8]) or nil, desc = d ~= '' and d or nil }
    end
  end
  return events, updated, bytes, packed
end

------------------------------------------------------------------ recurrence

local MAX_PERIODS = 3000

local function overlaps(s, e, w0, w1) return s < w1 and (e > w0 or (e == s and s >= w0)) end
local function instance(ev, s, e, cal)
  return { s = s, e = e, ad = ev.ad, sum = ev.sum, loc = ev.loc, desc = ev.desc, uid = ev.uid, cal = cal }
end

-- the days of a month that a MONTHLY/YEARLY rule picks
local function month_days(r, y, m, d0)
  local len = C.month_len(y, m)
  local first = C.days(y, m, 1)
  local out = {}
  if r.bymd then
    for _k, md in ipairs(r.bymd) do
      local d = md > 0 and md or len + md + 1
      if d >= 1 and d <= len then out[#out + 1] = first + d - 1 end
    end
  elseif r.byday then
    for _k, b in ipairs(r.byday) do
      local f = first + (b.wd - C.wday(first)) % 7            -- the first such weekday
      if b.n and b.n > 0 then
        local d = f + (b.n - 1) * 7
        if d < first + len then out[#out + 1] = d end
      elseif b.n and b.n < 0 then
        local last = f + ((first + len - 1 - f) // 7) * 7
        local d = last + (b.n + 1) * 7
        if d >= first then out[#out + 1] = d end
      else
        local d = f
        while d < first + len do out[#out + 1] = d; d = d + 7 end
      end
    end
  elseif d0 <= len then
    out[1] = first + d0 - 1
  end
  table.sort(out)
  return out
end

-- every instance of `ev` that overlaps [w0, w1), appended to out
function C.expand(ev, w0, w1, out, cal, off)
  if not ev.rr then
    if overlaps(ev.s, ev.e, w0, w1) then out[#out + 1] = instance(ev, ev.s, ev.e, cal) end
    return
  end
  local r = ev.rule
  if not r then r = C.rule(ev.rr, off); ev.rule = r end
  local ex = ev.exset
  if not ex then
    ex = {}
    for _k, t in ipairs(ev.ex or {}) do ex[t] = true end
    ev.exset = ex
  end
  local dur = ev.e - ev.s
  local sd, tod = ev.s // DAY, ev.s % DAY
  local y0, m0, d0 = C.civil(sd)
  local count, done = 0, false
  local wd0 = w0 // DAY

  local function take(day)
    local t = day * DAY + tod
    if t < ev.s then return end
    if (r.till and t > r.till) or t >= w1 or t > C.MAXT - dur then done = true; return end
    count = count + 1
    if not ex[t] and overlaps(t, t + dur, w0, w1) then out[#out + 1] = instance(ev, t, t + dur, cal) end
    if r.count and count >= r.count then done = true end
  end
  local function month_ok(day)
    if not r.bymonth then return true end
    local _y, m = C.civil(day)
    return r.bymonth[m] == true
  end
  local function wday_ok(day)
    if not r.byday then return true end
    local w = C.wday(day)
    for _k, b in ipairs(r.byday) do if b.wd == w then return true end end
    return false
  end

  if r.freq == 'DAILY' then
    local step, p = r.interval, sd
    if not r.count and p < wd0 - 1 then p = p + ((wd0 - 1 - p) // step) * step end
    for _i = 1, MAX_PERIODS * 4 do
      if p * DAY + tod >= w1 then break end
      if month_ok(p) and wday_ok(p) then take(p) end
      if done then break end
      p = p + step
    end
  elseif r.freq == 'WEEKLY' then
    local step = 7 * r.interval
    local ws = sd - (C.wday(sd) + 6) % 7                       -- the Monday of the first week
    local offs = {}
    if r.byday then
      for _k, b in ipairs(r.byday) do offs[#offs + 1] = (b.wd + 6) % 7 end
      table.sort(offs)
    else
      offs[1] = (C.wday(sd) + 6) % 7
    end
    if not r.count and ws < wd0 - 7 then ws = ws + ((wd0 - 7 - ws) // step) * step end
    for _i = 1, MAX_PERIODS do
      if ws * DAY >= w1 then break end
      for _k, o in ipairs(offs) do
        if month_ok(ws + o) then take(ws + o) end
        if done then break end
      end
      if done then break end
      ws = ws + step
    end
  elseif r.freq == 'MONTHLY' or r.freq == 'YEARLY' then
    local yearly = r.freq == 'YEARLY'
    local mi = y0 * 12 + (m0 - 1)                               -- months counted from year 0
    local step = yearly and 12 * r.interval or r.interval
    if not r.count then
      local wy, wm = C.civil(wd0)
      local target = wy * 12 + wm - 1 - 12
      if mi < target then mi = mi + ((target - mi) // step) * step end
    end
    for _i = 1, MAX_PERIODS do
      local y, m = mi // 12, mi % 12 + 1
      if C.days(y, m, 1) * DAY >= w1 or y > 2037 then break end
      if yearly then
        local months = {}
        if r.bymonth then for k = 1, 12 do if r.bymonth[k] then months[#months + 1] = k end end else months[1] = m0 end
        for _k, mm in ipairs(months) do
          for _j, d in ipairs(month_days(r, y, mm, d0)) do take(d); if done then break end end
          if done then break end
        end
      elseif month_ok(C.days(y, m, 1)) then
        for _j, d in ipairs(month_days(r, y, m, d0)) do take(d); if done then break end end
      end
      if done then break end
      mi = mi + step
    end
  else
    if overlaps(ev.s, ev.e, w0, w1) then out[#out + 1] = instance(ev, ev.s, ev.e, cal) end
  end
end

-- the instances of every calendar shown in [w0, w1), sorted (all-day first on a day), one per
-- UID and start (an event shared between two calendars shows once)
function C.between(cals, w0, w1, off)
  local out, seen, list = {}, {}, {}
  for _k, cal in ipairs(cals) do
    if cal.on and cal.events then
      for _j, ev in ipairs(cal.events) do C.expand(ev, w0, w1, list, cal, off) end
    end
  end
  for _k, it in ipairs(list) do
    local key = it.uid and (it.uid .. '@' .. it.s)
    if not key or not seen[key] then
      if key then seen[key] = true end
      out[#out + 1] = it
    end
  end
  table.sort(out, function(a, b)
    local da, db = a.s // DAY, b.s // DAY
    if da ~= db then return da < db end
    if a.ad ~= b.ad then return a.ad == true end
    if a.s ~= b.s then return a.s < b.s end
    return (a.sum or '') < (b.sum or '')
  end)
  return out
end

-- does an instance show on `day`
function C.on_day(it, day)
  local d0, d1 = day * DAY, (day + 1) * DAY
  return it.s < d1 and (it.e > d0 or (it.e == it.s and it.s >= d0))
end
-- instances by day: { [day] = { it, ... } } for days in [first, first + n)
function C.by_day(insts, first, n)
  local t = {}
  for _k, it in ipairs(insts) do
    local a = math.max(first, it.s // DAY)
    local b = math.min(first + n - 1, (it.e > it.s and (it.e - 1) or it.e) // DAY)
    for d = a, b do
      local l = t[d]
      if not l then l = {}; t[d] = l end
      l[#l + 1] = it
    end
  end
  return t
end

return C
