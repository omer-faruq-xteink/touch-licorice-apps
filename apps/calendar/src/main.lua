-- Calendar for XTOS Licorice, API 2.9 (uses tools/gamekit, src/cal.lua and src/views.lua). A port of
-- KOReader's calendar.koplugin: read-only Google (or any iCal) calendars through their secret iCal
-- address, in Month, Week, Day and Agenda views, and on the lock screen.
--
-- Calendars come from calendars.txt ("Name|address|on" lines; added in Settings or copied over USB
-- into XTApps/calendar/files/). Each is fetched over Wi-Fi when older than the sync interval (or
-- on Sync), read on the device and kept as c<hash>.txt: only events near today and the repeating
-- ones, so the views and the lock screen (lockscreen.lua) work offline.

local C = require('cal')
local V = require('views')
local W, H = kit.W, kit.H
local DAY = 86400
local TAB_H, TOP, BODY_H = 52, 104, 584
local BTN_Y, BTN_H = 716, 64
local MODES = { 'day', 'week', 'month', 'agenda' }
local MODE_LABEL = { day = 'Day', week = 'Week', month = 'Month', agenda = 'Agenda' }
local LOCKS = { 'off', 'agenda', 'day', 'week', 'month' }
local EVERY = { 1, 3, 6, 12, 24 }

local cfg = { ws = 1, every = 6, lock = 'off', mode = 'week' }
local cals = {}
local mode, anchor, back_mode = 'week', 0, nil
local ag = { first = 0, starts = { 1 }, page = 1 }
local screen = 'main'                 -- main | settings
local hits = {}
local status, ERR = nil, nil
local OFF = 0                          -- the UTC offset
local data_ver = 0

local function clock()
  local e, off = C.clock()
  OFF = off
  return e, e + off, (e + off) // DAY       -- UTC, wall seconds, today
end

------------------------------------------------------------------ storage

local function save_cfg()
  kit.write('settings.txt', 'ws=' .. cfg.ws .. '\nevery=' .. cfg.every .. '\nlock=' .. cfg.lock .. '\nmode=' .. mode ..
    '\nplain=' .. (cfg.plain and '1' or '0') ..
    '\ngz=' .. (cfg.gz and 'ok' or ''))
end
local function save_list() kit.write('calendars.txt', C.list_text(cals)) end

local function load_cal(c)
  local events, updated, bytes, packed = C.load_cache(kit.read(C.cache_name(c.url)))
  c.events, c.updated, c.bytes, c.packed = events, events and updated or nil, bytes, packed
end
local function load_all()
  local t = kit.kv(kit.read('settings.txt'))
  cfg.ws = t.ws == '0' and 0 or 1
  cfg.every = tonumber(t.every) or 6
  cfg.plain = t.plain == '1'           -- this reader could not unpack gzip: ask for the file as it is
  cfg.gz = t.gz == 'ok'                -- gzip has worked here (the lock screen asks for it only then)
  for _k, l in ipairs(LOCKS) do if t.lock == l then cfg.lock = l end end
  for _k, m in ipairs(MODES) do if t.mode == m then mode = m end end
  cals = C.parse_list(kit.read('calendars.txt'))
  for _k, c in ipairs(cals) do load_cal(c) end
  data_ver = data_ver + 1
end

------------------------------------------------------------------ syncing

local sync_q, sync_cur, sync_since, sync_done = nil, nil, nil, 0
local reading = nil                    -- { c, p = C.parser, e, bytes, packed }: being read
local sync_next                        -- the next calendar (below)
local function stale(c, now)
  return not c.updated or now - c.updated > cfg.every * 3600
end
local function syncing() return sync_cur ~= nil end

local function after_sync()
  local bad = {}
  for _k, c in ipairs(cals) do if c.on and c.err then bad[#bad + 1] = c.name .. ': ' .. c.err end end
  status = #bad > 0 and table.concat(bad, '; ') or (sync_done > 0 and 'Synced.' or nil)
  data_ver = data_ver + 1
end

-- -> 'again' when the calendar should be asked once more, as it is (gzip could not be unpacked)
local function take_body(c, resp)
  local body, why, what, packed = C.answer(resp, true)
  if what == 'gzip' and not cfg.plain then
    cfg.plain = true
    save_cfg()
    return 'again'
  end
  if not body then c.err = why; return end      -- the last whole copy stays
  if (packed or 0) > 0 and not cfg.gz then cfg.gz = true; save_cfg() end
  C.step('read ' .. (#body // 1024) .. ' KB')
  local e, _wall, today = clock()
  reading = { c = c, p = C.parser(body, OFF, today), e = e, bytes = #body, packed = packed }
  return 'reading'
end

-- read the calendar a piece at a time (a tick or a draw each): the host closes an app whose
-- callback runs too long, and reading 200 KB in one did
local READ_CHUNK = 16384
local function pump()
  local r = reading
  if not r then return end
  local ok, done = pcall(r.p.step, READ_CHUNK)
  if ok and not done then kit.refresh(); return end
  reading = nil
  if not ok then
    r.c.err = kit.short(tostring(done), 60)
  else
    C.step('save')
    kit.write(C.cache_name(r.c.url), C.cache_text(r.p.events, r.e, OFF, r.bytes, r.packed))
    r.c.events, r.c.updated, r.c.bytes, r.c.packed, r.c.err = r.p.events, r.e, r.bytes, r.packed, nil
    sync_done = sync_done + 1
  end
  r.p = nil
  C.free()
  sync_cur = nil
  sync_next()
  kit.refresh()
end

sync_next = function()
  local c = sync_q and table.remove(sync_q, 1)
  if not c then
    sync_q, sync_cur = nil, nil
    C.step('done')
    after_sync()
    return
  end
  sync_cur, sync_since = c, kit.now_ms()
  C.step('download ' .. c.name .. (cfg.plain and '' or ' (gzip)'))
  pcall(function() ctx.net:keep_wifi(5 * 60 * 1000) end)
  local ok, err = pcall(function()
    local opts = C.request(c.url, not cfg.plain)
    ctx.net:request(opts, function(cc, resp)
      if sync_cur ~= c then return end
      local okb, e = pcall(take_body, c, resp)
      if not okb then c.err = kit.short(tostring(e), 60) end
      if okb and e == 'reading' then
        pcall(function() ctx:set_tick(50) end)
        kit.refresh()
        return
      end
      if okb and e == 'again' then table.insert(sync_q, 1, c) end
      sync_cur = nil
      sync_next()
      kit.refresh()
    end)
  end)
  if not ok then
    c.err = 'could not ask: ' .. kit.short(tostring(err), 30)
    sync_cur = nil
    sync_next()
  end
end

-- fetch the shown calendars that are old (all of them when forced, or just `only`)
local function sync(force, only)
  if sync_cur then return end
  local e = clock()
  local q = {}
  for _k, c in ipairs(cals) do
    if c.on and ((only and c == only) or (not only and (force or stale(c, e)))) then q[#q + 1] = c end
  end
  if #q == 0 then
    if force then status = #cals == 0 and 'No calendars: add one in Settings.' or 'No calendar is shown.' end
    return
  end
  for _k, c in ipairs(q) do c.err = nil end
  sync_q, sync_done, status = q, 0, nil
  sync_next()
end

-- a request that never answers is given up after 90 s
local function watchdog()
  if sync_cur and not reading and sync_since and (kit.now_ms() or 0) - sync_since > 90000 then
    sync_cur.err = 'no answer'
    sync_cur = nil
    sync_next()
  end
end

------------------------------------------------------------------ the shown period

local vkey, vinsts = nil, {}
local function insts(first, n)
  local key = first .. ':' .. n .. ':' .. data_ver .. ':' .. OFF
  if key ~= vkey then
    vkey = key
    vinsts = C.between(cals, first * DAY, (first + n) * DAY, OFF)
  end
  return vinsts
end
local function env_for(first, n)
  local _e, wall, today = clock()
  return { font = kit.font, lh = kit.line_h, today = today, now = wall, ws = cfg.ws, insts = insts(first, n) }
end

local function agenda_env()
  local env = env_for(ag.first, 60)
  return env, V.agenda_rows(env, ag.first, 60)
end
-- the start row of every agenda page
local function agenda_pages(env, rows)
  local starts, k = { 1 }, 1
  while true do
    local _h, nxt = V.agenda(nil, env, rows, k, 0, TOP, W, BODY_H)
    if nxt > #rows or nxt <= k then break end
    starts[#starts + 1] = nxt
    k = nxt
  end
  return starts
end

local function step(dir)
  if mode == 'day' then anchor = anchor + dir
  elseif mode == 'week' then anchor = anchor + 7 * dir
  elseif mode == 'month' then
    local y, m, d = C.civil(anchor)
    m = m + dir
    if m < 1 then y, m = y - 1, 12 elseif m > 12 then y, m = y + 1, 1 end
    anchor = C.days(y, m, math.min(d, C.month_len(y, m)))
  else
    local env, rows = agenda_env()
    ag.starts = agenda_pages(env, rows)
    if dir > 0 then
      if ag.page < #ag.starts then ag.page = ag.page + 1
      else ag.first, ag.page = ag.first + 60, 1 end
    else
      if ag.page > 1 then ag.page = ag.page - 1
      else
        ag.first = ag.first - 60
        local env2, rows2 = agenda_env()
        ag.starts = agenda_pages(env2, rows2)
        ag.page = #ag.starts
      end
    end
  end
end
local function go_today()
  local _e, _w, today = clock()
  anchor, back_mode = today, nil
  ag.first, ag.page = today, 1
end
local function set_mode(m)
  if m == 'agenda' and mode ~= 'agenda' then ag.first, ag.page = anchor, 1 end
  mode, back_mode = m, nil
  save_cfg()
end

------------------------------------------------------------------ boxes

local function show_event(it)
  local lines = { C.when(it) }
  if it.loc and it.loc ~= '' then lines[#lines + 1] = 'At ' .. it.loc end
  if it.cal and #cals > 1 then lines[#lines + 1] = 'Calendar: ' .. it.cal.name end
  if it.desc and it.desc ~= '' then
    local wrapped = kit.wrap(it.desc, 'small', W - 80)
    local keep = {}
    for k = 1, math.min(#wrapped, 16) do keep[#keep + 1] = wrapped[k] end
    if #wrapped > 16 then keep[#keep] = keep[#keep] .. ' …' end
    lines[#lines + 1] = ''
    lines[#lines + 1] = table.concat(keep, '\n')
  end
  kit.show({ title = it.sum ~= '' and it.sum or '(no title)', lines = lines, rows = { { { 'Close', kit.close } } }, cancel = kit.close })
end

local function host_of(url) return url:match('^%a+://([^/]+)') or url end

local function ask_text(title, value, fn)
  ctx.input:text({ title = title, value = value or '', max_chars = 400 }, function(c, s)
    local ok, e = pcall(fn, s)
    if not ok then ERR = tostring(e) end
    kit.refresh()
  end)
end

local function add_calendar()
  ask_text('Secret iCal address (https://...)', '', function(s)
    if not s or not s:match('%S') then return end
    local url = C.fix_url(s)
    if not url:match('^https?://') then status = 'The address must start with https://'; return end
    for _k, c in ipairs(cals) do if c.url == url then status = 'That calendar is already here.'; return end end
    local guess = host_of(url):find('google', 1, true) and 'Google' or host_of(url)
    ask_text('Name for this calendar', guess, function(name)
      local c = { name = (name and name:match('%S')) and kit.short(name:gsub('|', '/'), 40) or guess, url = url, on = true }
      cals[#cals + 1] = c
      save_list()
      sync(false, c)
    end)
  end)
end

local function calendar_box(c)
  local info = { kit.short(host_of(c.url), 40) .. '/...' }
  if c.err then info[#info + 1] = 'Last sync: ' .. c.err end
  kit.show({
    title = c.name, lines = info, cancel = kit.close,
    rows = {
      { { c.on and 'Hide' or 'Show', function()
          c.on = not c.on; save_list(); data_ver = data_ver + 1; kit.close()
          if c.on and not c.events then sync(false, c) end
        end },
        { 'Rename', function()
          kit.close()
          ask_text('Name for this calendar', c.name, function(s)
            if s and s:match('%S') then c.name = kit.short(s:gsub('|', '/'), 40); save_list() end
          end)
        end } },
      { { 'Delete', function()
          kit.show({ title = 'Delete "' .. c.name .. '"?', lines = { 'Only this list forgets it; the calendar itself is not touched.' },
                     cancel = kit.close, rows = { { { 'Delete', function()
                       for k, x in ipairs(cals) do if x == c then table.remove(cals, k); break end end
                       pcall(function() ctx.storage:remove(C.cache_name(c.url)) end)
                       save_list(); data_ver = data_ver + 1; kit.close()
                     end }, { 'Cancel', kit.close } } } })
        end },
        { 'Close', kit.close } },
    } })
end

------------------------------------------------------------------ lock screen

local function set_lock(l)
  local L = ctx.lockscreen
  cfg.lock = l
  save_cfg()
  if not L then status = 'This firmware has no app lock screen.'; return end
  local okd, isdef = pcall(function() return L:is_default() end)
  if l ~= 'off' then
    if not (okd and isdef == true) then pcall(function() L:set_default() end) end
    status = 'Lock screen: the ' .. MODE_LABEL[l]:lower() .. ' view.'
  else
    if okd and isdef == true then pcall(function() L:clear_default() end) end
    status = 'Lock screen: off.'
  end
end

------------------------------------------------------------------ drawing

local function ago(e, now)
  local m = math.max(0, now - e) // 60
  if m < 2 then return 'just now' end
  if m < 90 then return m .. ' min ago' end
  if m < 48 * 60 then return (m // 60) .. ' h ago' end
  return (m // 1440) .. ' days ago'
end

local function main_buttons() return { '<', 'Today', '>', syncing() and 'Wait' or 'Sync', 'More' } end
local function settings_buttons() return { 'Back', 'Add', syncing() and 'Wait' or 'Sync now' } end
local function button_rect(k, n)
  local bw = math.floor((W - 24 - (n - 1) * 8) / n)
  return 12 + (k - 1) * (bw + 8), BTN_Y, bw, BTN_H
end

local function draw_main(gg)
  local tw = W // 4
  for k, m in ipairs(MODES) do
    kit.button(gg, (k - 1) * tw + 4, 4, tw - 8, TAB_H - 8, MODE_LABEL[m], { line_width = m == mode and 4 or 1 })
  end
  if #cals == 0 then
    gg:text(16, 70, 'Calendar', { font = kit.font('large') })
    local y = 130
    for _k, l in ipairs(kit.wrap('No calendars yet. Tap More, then Add, and type the calendar\'s secret iCal address '
        .. '(Google Calendar on the web: Settings > your calendar > Integrate calendar > Secret address in iCal format). '
        .. 'Or copy a calendars.txt with "Name|address" lines into XTApps/calendar/files/ over USB.', 'medium', W - 32)) do
      gg:text(16, y, l, { font = kit.font('medium') })
      y = y + kit.line_h('medium') + 2
    end
    hits = {}
    return
  end
  local title = V.title(mode, mode == 'agenda' and ag.first or anchor, cfg.ws)
  gg:text(12, 62, kit.short(title, 34), { font = kit.font('large') })
  local first, n = V.window(mode, mode == 'agenda' and ag.first or anchor, cfg.ws)
  local env = env_for(first, n)
  if mode == 'month' then hits = V.month(gg, env, anchor, 2, TOP, W - 4, BODY_H)
  elseif mode == 'week' then hits = V.week(gg, env, anchor, 4, TOP, W - 8, BODY_H)
  elseif mode == 'day' then hits = V.day(gg, env, anchor, 4, TOP, W - 8, BODY_H)
  else
    local rows = V.agenda_rows(env, ag.first, 60)
    ag.starts = agenda_pages(env, rows)
    if ag.page > #ag.starts then ag.page = #ag.starts end
    hits = V.agenda(gg, env, rows, ag.starts[ag.page], 4, TOP, W - 8, BODY_H)
    if #rows == 0 then gg:text(16, TOP + 20, 'No events in these 60 days.', { font = kit.font('medium') }) end
    gg:text(W - 70, 70, ag.page .. '/' .. #ag.starts, { font = kit.font('small') })
  end
end

local function setting_rows()
  return {
    { 'Week starts on: ' .. (cfg.ws == 1 and 'Monday' or 'Sunday'), 'ws' },
    { 'Sync when older than: ' .. cfg.every .. ' h', 'every' },
    { 'Lock screen: ' .. (cfg.lock == 'off' and 'off' or MODE_LABEL[cfg.lock]), 'lock' },
  }
end
local CAL_Y, CAL_H, MAX_CALS, OPT_Y, OPT_H = 100, 66, 5, 466, 54

local function draw_settings(gg)
  gg:text(16, 12, 'Settings', { font = kit.font('large') })
  gg:text(16, 64, 'Calendars (tap one to hide, rename or delete)', { font = kit.font('small') })
  local e = clock()
  for k, c in ipairs(cals) do
    if k > MAX_CALS then
      gg:text(16, CAL_Y + (k - 1) * CAL_H + 6, '+' .. (#cals - MAX_CALS) .. ' more: edit calendars.txt over USB', { font = kit.font('small') })
      break
    end
    local y = CAL_Y + (k - 1) * CAL_H
    gg:text(20, y + 6, kit.short(c.name, 30) .. (c.on and '' or '  (hidden)'), { font = kit.font('medium') })
    local info
    if sync_cur == c then info = 'syncing...'
    elseif c.err then info = 'error: ' .. c.err
    elseif c.updated then
      info = #(c.events or {}) .. ' events, ' .. ((c.bytes or 0) // 1024) .. ' KB' ..
        ((c.packed or 0) > 0 and (' (' .. (c.packed // 1024) .. ' KB gzip)') or '') .. ', synced ' .. ago(c.updated, e)
    else info = 'not synced yet' end
    gg:text(20, y + 36, kit.short(info, 46), { font = kit.font('small') })
    gg:line(16, y + CAL_H - 2, W - 16, y + CAL_H - 2)
  end
  if #cals == 0 then gg:text(20, CAL_Y + 10, 'None yet: tap Add.', { font = kit.font('medium') }) end
  local _e, wall = clock()
  local zone = string.format('UTC%s%d', OFF < 0 and '-' or '+', math.abs(OFF) // 3600) .. (OFF % 3600 ~= 0 and string.format(':%02d', math.abs(OFF) % 3600 // 60) or '')
  gg:text(16, OPT_Y - 30, 'Clock: ' .. C.date(wall // DAY) .. ' ' .. C.hm(wall) .. ', ' .. zone, { font = kit.font('small') })
  for k, r in ipairs(setting_rows()) do
    local y = OPT_Y + (k - 1) * OPT_H
    gg:rect(12, y, W - 24, OPT_H - 8)
    gg:text(24, y + 12, r[1], { font = kit.font('medium') })
  end
end

-- A box has no fill (a fill draws black), but an image draws its white: a 1x1 white JPEG
-- stretched over the box hides the view under it. Without the image the box gets a clean screen.
local WHITE_JPG = ('ffd8ffe000104a46494600010100000100010000ffdb0043000101010101010101010101010101010101010101010101' ..
  '0101010101010101010101010101010101010101010101010101010101010101010101010101010101ffc0000b080001' ..
  '000101011100ffc4001f0000010501010101010100000000000000000102030405060708090a0bffc400b51000020103' ..
  '03020403050504040000017d01020300041105122131410613516107227114328191a1082342b1c11552d1f024336272' ..
  '82090a161718191a25262728292a3435363738393a434445464748494a535455565758595a636465666768696a737475' ..
  '767778797a838485868788898a92939495969798999aa2a3a4a5a6a7a8a9aab2b3b4b5b6b7b8b9bac2c3c4c5c6c7c8c9' ..
  'cad2d3d4d5d6d7d8d9dae1e2e3e4e5e6e7e8e9eaf1f2f3f4f5f6f7f8f9faffda0008010100003f00fefe2bffd9')
local white = nil                    -- the decoded image; false when the reader cannot decode it

local function white_image()
  if white == nil then
    local ok, img = pcall(function()
      return ctx.image:decode((WHITE_JPG:gsub('..', function(h) return string.char(tonumber(h, 16)) end)))
    end)
    white = (ok and img) or false
  end
  return white
end

-- the box's frame, taken from a dry run of kit.draw_modal (its first rect)
local function modal_rect()
  local r = nil
  kit.draw_modal(setmetatable({}, { __index = function(_, k)
    return function(_, x, y, w, h) if k == 'rect' and not r then r = { x, y, w, h } end end
  end }))
  return r
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    pump()
    gg:clear(0)
    if kit.modal() and not white_image() then kit.draw_modal(gg); return end
    if screen == 'settings' then draw_settings(gg) else draw_main(gg) end
    local line = (reading and ('Reading ' .. kit.short(reading.c.name, 20) .. '... ' ..
                    (reading.p.pos * 100 // math.max(1, reading.p.size)) .. '%'))
      or (sync_cur and ('Syncing ' .. kit.short(sync_cur.name, 24) .. '...')) or status or ERR
    if line then gg:text(12, BTN_Y - 26, kit.short(line, 48), { font = kit.font('small') }) end
    local bs = screen == 'settings' and settings_buttons() or main_buttons()
    for k, b in ipairs(bs) do
      local x, y, bw, bh = button_rect(k, #bs)
      kit.button(gg, x, y, bw, bh, b, { font = 'medium' })
    end
    if kit.modal() then
      local r = modal_rect()
      if not (r and pcall(function() gg:image(white, r[1], r[2], { w = r[3], h = r[4] }) end)) then gg:clear(0) end
      kit.draw_modal(gg)
    end
  end)
  if not ok then pcall(function() gg:text(8, H - 40, kit.short('draw ERR ' .. tostring(e), 46)) end) end
end

------------------------------------------------------------------ input

local function tap_settings(x, y)
  if y >= CAL_Y and y < CAL_Y + MAX_CALS * CAL_H then
    local c = cals[(y - CAL_Y) // CAL_H + 1]
    if c then calendar_box(c) end
    return
  end
  for k, r in ipairs(setting_rows()) do
    local ry = OPT_Y + (k - 1) * OPT_H
    if y >= ry and y < ry + OPT_H - 8 then
      if r[2] == 'ws' then cfg.ws = 1 - cfg.ws; save_cfg()
      elseif r[2] == 'every' then
        local nxt = EVERY[1]
        for i, v in ipairs(EVERY) do if v == cfg.every then nxt = EVERY[i % #EVERY + 1] end end
        cfg.every = nxt
        save_cfg()
      else
        local nxt = LOCKS[1]
        for i, v in ipairs(LOCKS) do if v == cfg.lock then nxt = LOCKS[i % #LOCKS + 1] end end
        set_lock(nxt)
      end
      return
    end
  end
end

local function tap(x, y)
  if kit.tap_modal(x, y) then return end
  local bs = screen == 'settings' and settings_buttons() or main_buttons()
  for k, b in ipairs(bs) do
    local bx, by, bw, bh = button_rect(k, #bs)
    if x >= bx and x < bx + bw and y >= by and y < by + bh then
      status = nil
      if b == '<' then step(-1)
      elseif b == '>' then step(1)
      elseif b == 'Today' then go_today()
      elseif b == 'Sync' or b == 'Sync now' then sync(true)
      elseif b == 'More' then screen = 'settings'
      elseif b == 'Back' then screen = 'main'
      elseif b == 'Add' then add_calendar() end
      return
    end
  end
  if screen == 'settings' then tap_settings(x, y); return end
  if y < TAB_H then
    local m = MODES[x // (W // 4) + 1]
    if m then set_mode(m) end
    return
  end
  for _k, h in ipairs(hits) do
    if x >= h.x and x < h.x + h.w and y >= h.y and y < h.y + h.h then
      if h.it then show_event(h.it)
      elseif h.day then
        local from = mode
        anchor = h.day
        set_mode('day')
        back_mode = from
      end
      return
    end
  end
end

local function go_back()
  if kit.modal() then
    if kit.modal().cancel then kit.modal().cancel() end
  elseif screen == 'settings' then screen = 'main'
  elseif back_mode then
    local m = back_mode
    set_mode(m)
  end
end

function on_input(c, ev)
  ERR = nil
  local ok, e = pcall(function()
    watchdog()
    if type(ev) ~= 'table' then return end
    if ev.type == 'pointer' and ev.phase == 'up' then
      local g = ev.gesture
      if not kit.modal() and screen == 'main' and (g == 'swipe_left' or g == 'swipe_right') then
        step(g == 'swipe_left' and 1 or -1)
      elseif g == nil or g == 'tap' then
        tap(ev.x or 0, ev.y or 0)
      end
    elseif ev.type == 'key' and kit.key_accepted(ev) then
      if ev.key == 'back' then go_back()
      elseif not kit.modal() and screen == 'main' then
        if ev.key == 'left' or ev.key == 'up' then step(-1)
        elseif ev.key == 'right' or ev.key == 'down' then step(1) end
      end
    end
  end)
  if not ok then ERR = tostring(e) end
  kit.refresh()
  return true
end

function on_load(c)
  local ok, e = pcall(function()
    load_all()
    go_today()
    -- the reader closed the app during the last sync: say where, don't start one at once, and
    -- when it was unpacking, ask for the file as it is from now on
    local last = kit.read('sync_step.txt')
    if last and last ~= '' and last ~= 'done' then
      status = 'The last sync stopped at: ' .. last .. '.'
      if last:match('^unpack') then
        cfg.plain = true
        save_cfg()
        status = status .. ' Now without gzip.'
      end
      C.step('done')
      return
    end
    sync(false)
  end)
  if not ok then ERR = tostring(e) end
end
function on_tick(c)
  local ok, e = pcall(pump)
  if not ok then ERR = tostring(e) end
end
function on_leave() pcall(function() ctx.net:keep_wifi(1) end) end

if rawget(_G, '__TEST') then
  __TEST.api = { C = C, V = V, cals = function() return cals end, cfg = cfg, mode = function() return mode end,
                 anchor = function() return anchor end, ag = ag, screen = function() return screen end,
                 status = function() return status end, hits = function() return hits end }
end
