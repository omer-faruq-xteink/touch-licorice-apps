-- Hacker News' sleep screen (bundle.py puts tools/gamekit/gamekit.lua as `kit` and src/hn.lua as
-- `N` in front): the For you stories the app saved (list_foryou.txt, fetched at foryou_at.txt),
-- with the time they were fetched. When the interval chosen in the app (settings.txt lockevery,
-- minutes) has passed, the same one search is asked again while locked: API 2.26 (firmware
-- 26111201) gives the lock session ctx.net when the manifest's lockscreen block has "net": true.
-- No topics: nothing to fetch, no connection. The request goes out in on_load; a timer wake holds
-- its frame until the answer, the first session draws at once and again after it.
-- ctx.lock:done() ends the session once nothing is pending. Each session sets the next wake: the
-- interval itself, at most an hour (the reader aligns wakes to it; 3 and 6 hours wake hourly).

local W, H = 480, 800
local MAX_WAKE_S = 3600         -- ctx.lock:set_interval takes 30-3600 s
local SLACK_S = 120             -- a wake may come early (seen: up to a minute)
local pending = false           -- the request out in this session
-- store: cut (the store's API gives a lock screen no network; tools/store_export.py drops this)
local asked = false
local holding = false           -- an early wake waiting for the aligned time it was woken for
-- store: end

local function read(name)
  local ok, s = pcall(function() return ctx.storage:read(name) end)
  return (ok and type(s) == 'string') and s or nil
end
local function write(name, s) pcall(function() ctx.storage:write(name, s) end) end
local function clock()
  local ok, t = pcall(function() return ctx.clock:now() end)
  return (ok and type(t) == 'table') and t or {}
end
local function now_sec() return math.floor(tonumber(clock().epoch_sec) or 0) end
-- the wall clock's offset from UTC, seconds (whole quarter hours)
local function offset()
  local t = clock()
  if not tonumber(t.hour) then return 0 end
  local wall = t.hour * 3600 + (t.minute or 0) * 60 + (t.second or 0)
  local off = (wall - now_sec() % 86400) % 86400
  if off > 14 * 3600 then off = off - 86400 end
  return math.floor(off / 900 + 0.5) * 900
end

-- when the list was fetched, by the wall clock: "updated 14:05", "updated yesterday 22:10"
local function stamp(at)
  if not at then return nil end
  local off = offset()
  local days = (now_sec() + off) // 86400 - (at + off) // 86400
  local hm = string.format('%02d:%02d', (at + off) % 86400 // 3600, (at + off) % 3600 // 60)
  if days <= 0 then return 'updated ' .. hm end
  return days == 1 and ('updated yesterday ' .. hm) or ('updated ' .. days .. ' days ago')
end

local function saved_rows(fy)
  local rows = {}
  for line in (read('list_foryou.txt') or ''):gmatch('[^\n]+') do
    local r = N.row_parse(line)
    if r and not N.muted(r, fy) then rows[#rows + 1] = r end
  end
  return rows
end

-- store: cut
-- the wake log: one line a session and one an answer, the last 20, in wakes.txt (private storage:
-- XTApps/hackernews/files/ on the card), to see what the sleep screen did while nobody looked
local function wlog(s)
  pcall(function()
    local w = (now_sec() + offset()) % 86400
    local lines = {}
    for l in (read('wakes.txt') or ''):gmatch('[^\n]+') do lines[#lines + 1] = l end
    lines[#lines + 1] = string.format('%02d:%02d:%02d ', w // 3600, w % 3600 // 60, w % 60) .. s
    while #lines > 20 do table.remove(lines, 1) end
    ctx.storage:write('wakes.txt', table.concat(lines, '\n') .. '\n')
  end)
end

-- A timer wake comes up to a minute early; one that ends before the aligned time it was woken for
-- gets a second wake at that time. So an early session holds with ctx:after (it runs in a 2.26
-- lock session and keeps it open) until 2 s past it.
local function hold_if_early()
  if not (ctx.lock and ctx.lock.reason == 'timer') then return end
  local iv = tonumber(ctx.lock.interval_sec) or MAX_WAKE_S
  local rem = (iv - (now_sec() + offset()) % iv) % iv
  if rem == 0 or rem > SLACK_S then return end
  local ok, tm = pcall(function()
    return ctx:after((rem + 2) * 1000, function()
      holding = false
      pcall(function() ctx:invalidate() end)          -- draw again; that draw ends the session
    end)
  end)
  holding = ok and tm ~= nil
end

-- ask Algolia for the For you stories; -> what it did, for the log
local function try_refresh(fy)
  if asked then return 'fetch' end
  if not ctx.net then return 'no network on the lock screen' end
  asked = true
  local ok, job, err = pcall(function()
    return ctx.net:request({ url = N.foryou_url(fy.topics, now_sec(), 0), method = 'GET', timeout_ms = 30000,
                             headers = { ['User-Agent'] = 'XteinkLicoriceHN/1.3' } }, function(c, resp)
      pending = false
      local okw, what = pcall(function()
        if type(resp) ~= 'table' then return 'reply: none' end
        local code = tonumber(resp.status) or tonumber(resp.code)
        if type(resp.body) ~= 'string' or resp.ok == false then return 'reply failed: ' .. tostring(resp.err) end
        if code and code >= 400 then return 'reply HTTP ' .. code end
        local d = ctx.json:decode(resp.body)
        if type(d) ~= 'table' then return 'reply not JSON' end
        local out = {}
        for _k, h in ipairs(d.hits or {}) do out[#out + 1] = N.row_text(N.story(h)) end
        write('list_foryou.txt', table.concat(out, '\n'))
        write('foryou_at.txt', tostring(now_sec()))
        return 'reply ' .. #out .. ' stories'
      end)
      wlog(okw and what or ('reply error: ' .. tostring(what)))
      pcall(function() ctx:invalidate() end)            -- draw again (fresh or not); that draw ends the session
    end)
  end)
  pending = ok and job ~= nil
  if not pending then return 'fetch not sent: ' .. tostring(ok and err or job) end
  return 'fetch'
end
-- store: end

function on_draw(c, gg)
  if not gg then return end
  local ok, err = pcall(function()
    gg:clear(0)
    local t = clock()
    local fy = N.foryou_parse(read('foryou.txt'))
    if tonumber(t.year) then
      local wd = { 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday' }
      local days = (now_sec() + offset()) // 86400
      gg:text(24, 20, wd[(days + 4) % 7 + 1] .. string.format(', %02d:%02d', t.hour or 0, t.minute or 0), { font = kit.font('medium') })
    end
    gg:text(24, 56, 'Hacker News · For you', { font = kit.font('large') })
    gg:line(24, 100, W - 24, 100)
    gg:line(24, 101, W - 24, 101)
    if #fy.topics == 0 then
      local y = 140
      for _k, l in ipairs(N.wrap('Add topics in the Hacker News app (For you) to see their stories here.', 'medium', W - 48)) do
        gg:text(24, y, l, { font = kit.font('medium') }); y = y + 30
      end
      return
    end
    local rows = saved_rows(fy)
    local y, lh, sh = 116, kit.line_h('medium') + 2, kit.line_h('small') + 2
    for _k, r in ipairs(rows) do
      local tl = N.wrap(r.title, 'medium', W - 48)
      local n = math.min(2, #tl)
      if y + n * lh + sh + 10 > H - 44 then break end
      for i = 1, n do
        local s = tl[i]
        if i == 2 and #tl > 2 then s = kit.short(s, #s - 2) end
        gg:text(24, y, s, { font = kit.font('medium') }); y = y + lh
      end
      local tp = N.topics_in(r.title, fy.topics)
      local m = (#tp > 0 and (table.concat(tp, ', ') .. ' · ') or '') .. r.points .. ' pts · ' .. r.comments .. ' comments'
      local d = N.domain(r.url)
      if d then m = m .. ' · ' .. d end
      gg:text(24, y, kit.short(m, 48), { font = kit.font('small') })
      y = y + sh + 10
      gg:line(24, y - 6, W - 24, y - 6)
    end
    if #rows == 0 then gg:text(24, 140, 'No stories yet for your topics.', { font = kit.font('medium') }) end
    local s = stamp(tonumber(read('foryou_at.txt')))
    if s then gg:text(W - 24 - kit.width(kit.font('small'), s), H - 34, s, { font = kit.font('small') }) end
  end)
  if not ok then pcall(function() gg:text(10, 760, 'lock error: ' .. tostring(err):sub(1, 40)) end) end
  -- store: cut
  if not pending and not holding then pcall(function() ctx.lock:done() end) end   -- 2.26: nothing more to wait for
  -- store: end
end

function on_load()
  -- store: cut
  pcall(function()
    local every = (tonumber((read('settings.txt') or ''):match('lockevery=(%d+)')) or 60) * 60
    local fy = N.foryou_parse(read('foryou.txt'))
    local at = tonumber(read('foryou_at.txt'))
    local did = 'not due'
    if #fy.topics == 0 then did = 'no topics'
    elseif not at or now_sec() - at >= every - SLACK_S then did = try_refresh(fy) end
    hold_if_early()
    if holding then did = did .. '; early: held' end
    local nxt = math.min(every, MAX_WAKE_S)
    pcall(function() ctx.lock:set_interval(nxt) end)
    wlog(string.format('%s lock.net %s every %dm: %s; next %dm', ctx.lock and tostring(ctx.lock.reason) or '?',
      ctx.lock and tostring(ctx.lock.net) or '?', every // 60, did, nxt // 60))
  end)
  -- store: end
end
function on_tick() end
function on_input() return false end
