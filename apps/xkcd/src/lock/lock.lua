-- xkcd's sleep screen (bundle.py puts tools/gamekit/gamekit.lua as `kit` and src/xk.lua as `X` in
-- front): the latest comic, kept in its own files (lock.txt: "<kind>\t<X.line>" and "at=<when
-- looked>"; lock.png, or lock.jpg when reduced), with the time it was looked for. When the interval
-- chosen in the app (settings.txt lockevery, hours) has passed, xkcd.com/info.0.json is asked again
-- while locked (API 2.26: ctx.net in a lock session whose manifest block has "net": true), and the
-- picture only when the number is new. Requests go out in on_load; a timer wake holds its frame
-- until the answers, the first session draws at once and again after them. ctx.lock:done() ends
-- the session once nothing is pending. Each session sets the next wake an hour away (the longest
-- the host allows; the reader aligns it to the hour).
-- Random (settings.txt lockpick=random): each time the reader goes to sleep, the comic fetched at the
-- last lock (lock_next.txt, lock_next.png) comes on the screen at once, and the next random one is
-- fetched quietly for the next lock, so the screen is drawn only once. Timer wakes do nothing.

local W, H = 480, 800
local MAX_WAKE_S = 3600         -- ctx.lock:set_interval takes 30-3600 s
local SLACK_S = 120             -- a wake may come early (seen: up to a minute)
local pending = false           -- requests out in this session
local drawn_once = false        -- on_draw ran in this session
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
local function offset()
  local t = clock()
  if not tonumber(t.hour) then return 0 end
  local wall = t.hour * 3600 + (t.minute or 0) * 60 + (t.second or 0)
  local off = (wall - now_sec() % 86400) % 86400
  if off > 14 * 3600 then off = off - 86400 end
  return math.floor(off / 900 + 0.5) * 900
end
local function stamp(at)
  if not at then return nil end
  local off = offset()
  local days = (now_sec() + off) // 86400 - (at + off) // 86400
  local hm = string.format('%02d:%02d', (at + off) % 86400 // 3600, (at + off) % 3600 // 60)
  if days <= 0 then return 'updated ' .. hm end
  return days == 1 and ('updated yesterday ' .. hm) or ('updated ' .. days .. ' days ago')
end

-- lock.txt: the comic, its kind (png, jpg, rjpg reduced, none) and when it was looked for
local function saved()
  local s = read('lock.txt')
  if not s then return nil end
  local kind, rest = s:match('^(%a+)\t([^\n]*)')
  local c = rest and X.parse_line(rest)
  if not c then return nil end
  return { kind = kind, c = c, at = tonumber(s:match('\nat=(%d+)')) }
end
local function save(kind, c, at, name) write(name or 'lock.txt', kind .. '\t' .. X.line(c) .. '\nat=' .. at) end
local function pic(kind) return (kind == 'png') and 'lock.png' or 'lock.jpg' end

-- store: cut
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

-- an early timer wake ending before the aligned time it was woken for gets a second wake at that
-- time: hold the session with ctx:after (it runs in a 2.26 lock session) until 2 s past it
local function hold_if_early()
  if not (ctx.lock and ctx.lock.reason == 'timer') then return end
  local iv = tonumber(ctx.lock.interval_sec) or MAX_WAKE_S
  local rem = (iv - (now_sec() + offset()) % iv) % iv
  if rem == 0 or rem > SLACK_S then return end
  local ok, tm = pcall(function()
    return ctx:after((rem + 2) * 1000, function()
      holding = false
      pcall(function() ctx:invalidate() end)
    end)
  end)
  holding = ok and tm ~= nil
end

local quiet = false             -- random: the fetch is for the next lock; the screen stays as it is
local function finish(what)
  pending = false
  wlog(what)
  if quiet then
    if drawn_once then pcall(function() ctx.lock:done() end) end
    return
  end
  pcall(function() ctx:invalidate() end)              -- draw again; that draw ends the session
end
local function request(url, save_name, fn, range)
  local req = { url = url, method = 'GET', timeout_ms = 30000, headers = { ['User-Agent'] = 'XteinkLicoriceXKCD/1.0' } }
  if save_name then req.save = { to = 'storage', name = save_name } end
  if range then req.headers.Range = range end
  local ok, job = pcall(function()
    return ctx.net:request(req, function(c, res)
      local okc, e = pcall(fn, res)
      if not okc then finish('error: ' .. tostring(e)) end
    end)
  end)
  return ok and job ~= nil
end
local function bad(res)
  if type(res) ~= 'table' or res.ok == false then return 'no network' end
  local code = tonumber(res.status) or 0
  if code >= 400 then return 'HTTP ' .. code end
  return nil
end

-- the picture of a new comic, made for the sleep screen as the app's are: its size from its first
-- 64 bytes, then the resizer makes it for the box below the title (at most twice its size),
-- greyscale at full contrast (X.weserv_url)
local BOX_W, BOX_H = W - 16, H - 50 - 70
local function fetch_pic(c, to)
  to = to or { pic = 'lock.png', txt = 'lock.txt' }
  local sent = request(c.img, nil, function(res)
    local b = bad(res)
    if b == 'no network' then finish('picture: ' .. b); return end
    local sw, sh
    if not b and type(res.body) == 'string' then sw, sh = X.png_size(res.body) end
    local sent2 = request(X.weserv_url(c.img, BOX_W, BOX_H, sw, sh, X.turn_for(sw, sh, BOX_W, BOX_H)), to.pic, function(r2)
      local b2 = bad(r2)
      if b2 then finish('picture: ' .. b2); return end
      if not r2.saved then finish('picture not saved: ' .. tostring(r2.err)); return end
      if to.pic == 'lock.png' then pcall(function() ctx.storage:remove('lock.jpg') end) end
      save('png', c, now_sec(), to.txt)
      finish('new comic ' .. c.num)
    end)
    if not sent2 then finish('picture not sent') end
  end, 'bytes=0-63')
  if not sent then finish('picture not sent') end
end

-- -> what it did, for the log
local function try_refresh(s)
  if asked then return 'asking' end
  if not ctx.net then return 'no network on the lock screen' end
  asked = true
  pending = true
  local sent = request(X.json_url(nil), nil, function(res)
    local b = bad(res)
    if b then finish('latest: ' .. b); return end
    local okd, d = pcall(function() return ctx.json:decode(res.body) end)
    local c = okd and X.comic(d)
    if not c then finish('latest: not a comic'); return end
    if s and s.c.num >= c.num then
      save(s.kind, s.c, now_sec())
      finish('no new comic (' .. c.num .. ')')
    elseif c.interactive then
      save('none', c, now_sec())
      finish('new comic ' .. c.num .. ' (interactive)')
    else
      fetch_pic(c)
    end
  end)
  if not sent then pending = false; return 'not sent' end
  return 'asking'
end

-- random: the latest number, then a random comic (an interactive one is passed over once), then its
-- picture into `to`
local function fetch_random(to, tries)
  local sent = request(X.json_url(nil), nil, function(res)
    local b = bad(res)
    if b then finish('latest: ' .. b); return end
    local okd, d = pcall(function() return ctx.json:decode(res.body) end)
    local latest = okd and X.comic(d)
    if not latest then finish('latest: not a comic'); return end
    local n = X.random(latest.num, math.random())
    local sent2 = request(X.json_url(n), nil, function(r2)
      local b2 = bad(r2)
      if b2 then finish('random ' .. n .. ': ' .. b2); return end
      local okc, d2 = pcall(function() return ctx.json:decode(r2.body) end)
      local c = okc and X.comic(d2)
      if not c then finish('random ' .. n .. ': not a comic'); return end
      if c.interactive and (tries or 0) < 1 then fetch_random(to, (tries or 0) + 1); return end
      if c.interactive then save('none', c, now_sec(), to.txt); finish('random ' .. n .. ' (interactive)'); return end
      fetch_pic(c, to)
    end)
    if not sent2 then finish('random not sent') end
  end)
  if not sent then finish('not sent') end
  return sent
end

-- a lock in random mode: the one kept at the last lock on the screen, then the next one fetched
local function random_lock()
  if not ctx.net then return 'no network on the lock screen' end
  local nxt = read('lock_next.txt')
  if nxt then
    local ok = true
    if nxt:match('^png\t') then
      local b = read('lock_next.png')
      ok = b ~= nil and pcall(function() ctx.storage:write('lock.png', b) end)
      if ok then pcall(function() ctx.storage:remove('lock.jpg') end) end
    end
    if ok then write('lock.txt', (nxt:gsub('\nat=%d+', '')) .. '\nat=' .. now_sec()) end
    pcall(function() ctx.storage:remove('lock_next.txt') end)
    pcall(function() ctx.storage:remove('lock_next.png') end)
  end
  pending = true
  asked = true
  local to = { pic = 'lock.png', txt = 'lock.txt' }
  if saved() then quiet = true; to = { pic = 'lock_next.png', txt = 'lock_next.txt' } end
  if fetch_random(to) then return quiet and 'random: next asked' or 'random: asked for the screen' end
  pending = false
  return 'random: not sent'
end
-- store: end

-- the picture drawn last: kept until the next draw, since the host shows a frame after on_draw and
-- a picture freed in it draws nothing (the blank sleep screen of 2026-11-15)
local shown = nil

function on_draw(c, gg)
  if not gg then return end
  drawn_once = true
  if shown then pcall(function() shown:release() end); shown = nil end
  local ok, err = pcall(function()
    gg:clear(0)
    local s = saved()
    if not s then
      local y = 300
      for _k, l in ipairs(kit.wrap('xkcd: open the app once (with Wi-Fi) to show the latest comic here.', 'medium', W - 48)) do
        gg:text(24, y, l, { font = kit.font('medium') }); y = y + 32
      end
      return
    end
    local title = 'xkcd ' .. s.c.num .. ': ' .. s.c.title
    gg:text(24, 20, kit.short(title, 34), { font = kit.font('medium') })
    gg:line(24, 58, W - 24, 58)
    local top, bottom = 70, H - 50
    if s.kind ~= 'none' then
      local b = read(pic(s.kind))
      local okd, im, derr = pcall(function()
        if not b then return nil, 'no picture saved' end
        return ctx.image:decode(b, { max_w = W - 16, max_h = bottom - top })
      end)
      local drew = false
      if okd and im then
        local iw, ih = tonumber(im.width) or 0, tonumber(im.height) or 0
        -- made for this box by the resizer: drawn as it is (the reader's own scaling only adds dots)
        local okg, gr, gerr = pcall(function() return gg:image(im, (W - iw) // 2, top + (bottom - top - ih) // 2) end)
        drew = okg and not (gr == nil and gerr ~= nil)              -- nil, "invalid_handle" and the like
        if not drew then derr = 'draw: ' .. tostring(okg and gerr or gr) end
        shown = im
      elseif not okd then derr = im end
      if not drew then
        -- a blank page tells nothing: say why (seen on the device 2026-11-15, comic 3324)
        local why = 'picture: ' .. tostring(derr or 'not decoded') .. ' (' .. (b and #b or 0) .. ' bytes)'
        gg:text(24, 300, kit.short(why, 40), { font = kit.font('small') })
        -- store: cut
        wlog(why)
        -- store: end
      end
    else
      gg:text(24, 300, 'An interactive comic: open it in the app.', { font = kit.font('medium') })
    end
    local st = stamp(s.at)
    if st then gg:text(W - 24 - kit.width(kit.font('small'), st), H - 34, st, { font = kit.font('small') }) end
  end)
  if not ok then pcall(function() gg:text(10, 760, 'lock error: ' .. tostring(err):sub(1, 40)) end) end
  -- store: cut
  if not pending and not holding then pcall(function() ctx.lock:done() end) end   -- 2.26: nothing more to wait for
  -- store: end
end

function on_load()
  -- store: cut
  pcall(function()
    local hours = tonumber((read('settings.txt') or ''):match('lockevery=(%d+)')) or 6
    if hours <= 0 then hours = 6 end
    local every = hours * 3600
    local s = saved()
    local did = 'not due'
    local random = (read('settings.txt') or ''):match('lockpick=random') ~= nil
    if random then
      if not (ctx.lock and ctx.lock.reason == 'timer') then did = random_lock() end
    elseif not s or not s.at or now_sec() - s.at >= every - SLACK_S then did = try_refresh(s) end
    if not random then hold_if_early() end
    if holding then did = did .. '; early: held' end
    pcall(function() ctx.lock:set_interval(MAX_WAKE_S) end)
    wlog(string.format('%s lock.net %s every %dh: %s', ctx.lock and tostring(ctx.lock.reason) or '?',
      ctx.lock and tostring(ctx.lock.net) or '?', hours, did))
  end)
  -- store: end
end
function on_tick() end
function on_input() return false end
