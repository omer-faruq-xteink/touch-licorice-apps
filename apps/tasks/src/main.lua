-- Tasks for XTOS Licorice, API 2.9 (uses tools/gamekit).
--
-- Lists of things to do, ticked off with a tap. Everything lives in one plain text file in the
-- app's storage, lists.txt, which can also be edited on a computer (XTApps/tasks/files/):
--
--   # Shopping
--   [ ] bread
--   [x] milk
--
-- An item can repeat: ticking it keeps the date, and it un-ticks itself when it is due again,
-- counted from that date ("[x] Water plants {every 4 days, done 2026-11-01}"; days, weeks, months).
--
-- A list can be the lock screen (lockscreen.lua): its open items in the large font, with the date.
-- The app writes lock.txt (the list's name and open items) whenever that list changes; a ticked
-- repeating item goes in as "<day it is due>\t<text>", for the lock screen to show from that day.
--
-- Todoist and Google Tasks (lib/remote.lua, loaded only once one is set up): their lists come
-- after the local ones, each marked with the service; an item can be ticked, unticked and added
-- on the reader, the rest is done in the service's own apps.

local W, H = kit.W, kit.H
local TOP = 96
local ROW_H = 64
local ROWS = 9                  -- rows on a page; 8 when there are more, with Prev and Next under them
local BTN_Y, BTN_H = 704, 64

local lists = {}                -- { { name, items = { { text, done, every = { n, unit }, last } } } }
local screen = 'lists'          -- lists | list
local cur = 1                   -- the open list (in all(): the local lists, then the services')
local top = 1                   -- first row shown
local lock_name = nil           -- the list on the lock screen: its name, or "<service>:<id>"
-- how often the lock screen syncs a service's list while locked, in minutes (0: never)
local lock_every = 60
local EVERY = { { 15, 'Every 15 min' }, { 30, 'Every 30 min' }, { 60, 'Every hour' }, { 180, 'Every 3 hours' },
                { 360, 'Every 6 hours' }, { 0, 'Never' } }
local function every_text(m)
  if m == 0 then return 'not synced while locked' end
  return 'synced every ' .. (m < 60 and (m .. ' min') or (m == 60 and 'hour' or ((m // 60) .. ' hours')))
end
local msg, ERR = nil, nil
local R = nil                   -- lib/remote.lua once loaded

-- every list on the screen: the local ones, then Todoist's and Google's
local function all()
  if not R then return lists end
  local out = {}
  for _k, l in ipairs(lists) do out[#out + 1] = l end
  for _k, l in ipairs(R.lists()) do out[#out + 1] = l end
  return out
end
local function key_of(l) return l.src and ((l.acc or l.src) .. ':' .. tostring(l.rid)) or l.name end
local function current() return all()[cur] or lists[1] end

------------------------------------------------------------------ days

local function days_from_civil(y, m, d)
  y = m <= 2 and y - 1 or y
  local era = (y >= 0 and y or y - 399) // 400
  local yoe = y - era * 400
  local doy = (153 * (m > 2 and m - 3 or m + 9) + 2) // 5 + d - 1
  local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
  return era * 146097 + doe - 719468
end

local function civil(z)
  z = z + 719468
  local era = (z >= 0 and z or z - 146096) // 146097
  local doe = z - era * 146097
  local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
  local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
  local mp = (5 * doy + 2) // 153
  local d = doy - (153 * mp + 2) // 5 + 1
  local m = mp < 10 and mp + 3 or mp - 9
  return yoe + era * 400 + (m <= 2 and 1 or 0), m, d
end

local MONTHS = { 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' }
local WDAYS = { 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat' }
local function date_label(day)
  local _y, m, d = civil(day)
  return WDAYS[(day + 4) % 7 + 1] .. ' ' .. d .. ' ' .. MONTHS[m]
end

-- local days since 1970 (the clock's wall time decides the time zone)
local function local_day()
  local ok, t = pcall(function() return ctx.clock:now() end)
  if not ok or type(t) ~= 'table' or not tonumber(t.epoch_sec) then return days_from_civil(2026, 11, 1) end
  local e = math.floor(tonumber(t.epoch_sec))
  if tonumber(t.hour) then
    local wall = tonumber(t.hour) * 3600 + (tonumber(t.minute) or 0) * 60 + (tonumber(t.second) or 0)
    local off = (wall - e % 86400) % 86400
    if off > 14 * 3600 then off = off - 86400 end
    off = math.floor(off / 900 + 0.5) * 900
    return (e + off) // 86400
  end
  return e // 86400
end

------------------------------------------------------------------ repeating

local UNITS = { d = 'day', day = 'day', days = 'day', w = 'week', week = 'week', weeks = 'week',
                m = 'month', month = 'month', months = 'month' }

-- "3 days", "every 2 weeks", "month" -> { n, unit } or nil
local function parse_every(s)
  local n, u = s:lower():gsub('^%s*every%s*', ''):match('^%s*(%d*)%s*(%a+)%s*$')
  u = u and UNITS[u]
  n = tonumber(n ~= '' and n or 1)
  if not u or not n or n < 1 or n > 999 then return nil end
  return { n = n, unit = u }
end

local function every_label(ev)
  if ev.n == 1 then return 'every ' .. ev.unit end
  return 'every ' .. ev.n .. ' ' .. ev.unit .. 's'
end

-- the day a repeating item is due again: its last done day plus the interval (months are
-- calendar months, the day cut to the month's length: 31 Jan + 1 month = 28 or 29 Feb)
local function due(it)
  if not (it.every and it.last) then return nil end
  local ev = it.every
  if ev.unit == 'day' then return it.last + ev.n end
  if ev.unit == 'week' then return it.last + 7 * ev.n end
  local y, m, d = civil(it.last)
  m = m - 1 + ev.n
  y, m = y + m // 12, m % 12 + 1
  local len = days_from_civil(m == 12 and y + 1 or y, m == 12 and 1 or m + 1, 1) - days_from_civil(y, m, 1)
  return days_from_civil(y, m, math.min(d, len))
end

local function iso(day)
  local y, m, d = civil(day)
  return string.format('%04d-%02d-%02d', y, m, d)
end

------------------------------------------------------------------ storage

local function parse(text)
  local out = {}
  for raw in ((text or '') .. '\n'):gmatch('([^\n]*)\n') do
    local line = raw:gsub('\r', '')                -- Lua 5.5: a loop variable is const
    local name = line:match('^#%s*(.-)%s*$')
    if name and name ~= '' then
      out[#out + 1] = { name = name, items = {} }
    else
      local mark, t = line:match('^%[([ xX])%]%s?(.*)$')
      if mark and t:match('%S') then
        if #out == 0 then out[1] = { name = 'Tasks', items = {} } end
        local items = out[#out].items
        local it = { text = t, done = mark ~= ' ' }
        local body, tail = t:match('^(.-)%s*{([^{}]*)}%s*$')
        local every = tail and parse_every(tail:match('^%s*([^,]*)') or '')
        if every and body:match('%S') then
          it.text, it.every = body, every
          local y, m, d = tail:match('done%s+(%d%d%d%d)%-(%d%d?)%-(%d%d?)')
          if y then it.last = days_from_civil(tonumber(y), tonumber(m), tonumber(d)) end
        end
        items[#items + 1] = it
      end
    end
  end
  return out
end

local function serialize()
  local out = {}
  for _k, l in ipairs(lists) do
    out[#out + 1] = '# ' .. l.name
    for _j, it in ipairs(l.items) do
      local tail = ''
      if it.every then tail = ' {' .. every_label(it.every) .. (it.last and ', done ' .. iso(it.last) or '') .. '}' end
      out[#out + 1] = (it.done and '[x] ' or '[ ] ') .. it.text .. tail
    end
    out[#out + 1] = ''
  end
  return table.concat(out, '\n')
end

local function write_lock()
  if not lock_name then return end
  for _k, l in ipairs(all()) do
    if key_of(l) == lock_name then
      local open = {}
      for _j, it in ipairs(l.items) do
        if not it.done then open[#open + 1] = it.text
        elseif due(it) then open[#open + 1] = due(it) .. '\t' .. it.text end
      end
      kit.write('lock.txt', l.name .. '\n' .. table.concat(open, '\n'))
      return
    end
  end
end

local function save()
  kit.write('lists.txt', serialize())
  kit.write('settings.txt', 'lock=' .. (lock_name or '') .. '\nopen=' .. cur .. '\nevery=' .. lock_every)
  write_lock()
end

-- the services' code, loaded the first time it is needed
local open_key = nil
local function remote()
  if R then return R end
  R = _G.require('lib.remote')({ kit = kit, changed = function()
    -- after a sync the services' lists are new tables: keep the open one open
    if open_key then
      for k, l in ipairs(all()) do if key_of(l) == open_key then cur = k end end
      if cur > #all() then cur, screen = 1, 'lists' end
    end
    write_lock()
  end })
  R.load()
  return R
end

local function load()
  lists = parse(kit.read('lists.txt'))
  if #lists == 0 then lists = { { name = 'To do', items = {} } } end
  local t = kit.kv(kit.read('settings.txt'))
  lock_name = (t.lock and t.lock ~= '') and t.lock or nil
  lock_every = tonumber(t.every) or 60
  cur = math.max(1, math.min(#lists, tonumber(t.open) or 1))
end

-- a ticked repeating item whose day has come is open again
local function refresh_due()
  local today, changed = local_day(), false
  for _k, l in ipairs(lists) do
    for _j, it in ipairs(l.items) do
      if it.done and due(it) and today >= due(it) then it.done = false; changed = true end
    end
  end
  if changed then save() end
end

local function tick(it)
  local l = current()
  if l.src then remote().tick(l, it); write_lock(); return end
  it.done = not it.done
  if it.done and it.every then it.last = local_day() end
  save()
end

-- "due today", "late 2 days", "due Tue 12 Nov" for a service's item with a date
local function due_status(it)
  local y, m, d = (it.due or ''):match('^(%d%d%d%d)%-(%d%d)%-(%d%d)')
  local s = it.rec and it.rec or nil
  if not y then return s end
  local day = days_from_civil(tonumber(y), tonumber(m), tonumber(d))
  local late = local_day() - day
  local when
  if late > 0 then when = 'late ' .. late .. (late == 1 and ' day' or ' days')
  elseif late == 0 then when = 'due today'
  else when = 'due ' .. date_label(day) end
  return s and (s .. ', ' .. when) or when
end

-- the small line under a repeating item
local function repeat_status(it)
  local s, d = every_label(it.every), due(it)
  if not d then return s end
  if it.done then return s .. ', next ' .. date_label(d) end
  local late = local_day() - d
  if late > 0 then return s .. ', late ' .. late .. (late == 1 and ' day' or ' days') end
  if late == 0 then return s .. ', due today' end
  return s .. ', due ' .. date_label(d)
end

------------------------------------------------------------------ actions

local function ask(title, value, fn)
  ctx.input:text({ title = title, text = value or '', max_bytes = 256 }, function(c, s)
    s = (s or ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('\n', ' ')
    if s ~= '' then pcall(fn, s); save() end
    kit.refresh()
  end)
end

local function counts(l)
  local open, done = 0, 0
  for _k, it in ipairs(l.items) do if it.done then done = done + 1 else open = open + 1 end end
  return open, done
end

local function set_lock(l)
  local L = ctx.lockscreen
  if lock_name == key_of(l) then
    lock_name = nil
    pcall(function() ctx.storage:remove('lock.txt') end)
    local okd, isdef = pcall(function() return L:is_default() end)
    if L and okd and isdef == true then pcall(function() L:clear_default() end) end
    msg = 'Lock screen: off.'
    save()
    return
  end
  lock_name = key_of(l)
  save()
  if not L then msg = 'This firmware has no app lock screen.'; return end
  local okd, isdef = pcall(function() return L:is_default() end)
  if not (okd and isdef == true) then pcall(function() L:set_default() end) end
  msg = 'Lock screen: ' .. l.name .. '.'
end

local item_menu

local function repeat_menu(i)
  local it = current().items[i]
  local function set(ev)
    return function()
      kit.close()
      it.every = ev
      if ev and not it.last and it.done then it.last = local_day() end
      save()
    end
  end
  kit.show({ title = 'Repeat ' .. kit.short(it.text, 30),
             lines = { 'Ticked, it comes back when it is due again, counted from the day you ticked it.',
                       it.every and ('Now: ' .. every_label(it.every) .. '.') or 'Now: does not repeat.' },
             rows = { { { 'Every day', set({ n = 1, unit = 'day' }) }, { 'Every week', set({ n = 1, unit = 'week' }) } },
                      { { 'Every 2 weeks', set({ n = 2, unit = 'week' }) }, { 'Every month', set({ n = 1, unit = 'month' }) } },
                      { { 'Other', function()
                            kit.close()
                            ask('Repeat every (3 days, 2 weeks, 6 months)', it.every and every_label(it.every):gsub('^every ', '') or '', function(s)
                              local ev = parse_every(s)
                              if not ev then msg = 'Not understood: ' .. s; return end
                              set(ev)()
                            end)
                          end },
                        { 'Off', set(nil), it.every ~= nil } },
                      { { 'Back', function() item_menu(i) end } } },
             cancel = kit.close })
end

function item_menu(i)
  local l = current()
  local it = l.items[i]
  if l.src then
    local st = due_status(it)
    kit.show({ title = kit.short(it.text, 40),
               lines = { st or '', 'From ' .. remote().label(l) .. ': tick it here; edit, move or delete it there.' },
               rows = { { { 'Close', kit.close } } }, cancel = kit.close })
    return
  end
  kit.show({ title = kit.short(it.text, 40), lines = it.every and { repeat_status(it) } or {},
             rows = { { { 'Edit', function() kit.close(); ask('Edit', it.text, function(s) it.text = s end) end },
                        { 'Delete', function() kit.close(); table.remove(l.items, i); save() end } },
                      { { 'Up', function() kit.close(); if i > 1 then l.items[i], l.items[i - 1] = l.items[i - 1], it; save() end end, i > 1 },
                        { 'Down', function() kit.close(); if i < #l.items then l.items[i], l.items[i + 1] = l.items[i + 1], it; save() end end, i < #l.items } },
                      { { 'Repeat', function() repeat_menu(i) end }, { 'Close', kit.close } } },
             cancel = kit.close })
end

-- a service's list on the lock screen: how often it is synced while the reader is locked
local function lock_every_menu(l)
  local rows = {}
  for k = 1, #EVERY, 2 do
    local row = {}
    for j = k, math.min(k + 1, #EVERY) do
      local m = EVERY[j][1]
      row[#row + 1] = { EVERY[j][2], function() kit.close(); lock_every = m; set_lock(l) end }
    end
    rows[#rows + 1] = row
  end
  kit.show({ title = 'Lock screen: ' .. l.name, lines = { 'Its open items when the reader locks, synced with ' .. remote().label(l) ..
             ' while it is locked (Wi-Fi on for a few seconds):' }, rows = rows, cancel = kit.close })
end

local function list_menu(k)
  local l = all()[k]
  if l.src then
    kit.show({ title = l.name, lines = { 'A list in ' .. remote().label(l) .. ': rename or delete it there.',
                                         lock_name == key_of(l) and ('This list is on the lock screen, ' .. every_text(lock_every) .. '.')
                                           or 'Lock screen: its open items when the reader locks.' },
               rows = { { { lock_name == key_of(l) and 'Lock screen off' or 'Lock screen',
                            function() kit.close(); if lock_name == key_of(l) then set_lock(l) else lock_every_menu(l) end end },
                          { 'Close', kit.close } } },
               cancel = kit.close })
    return
  end
  kit.show({ title = l.name, lines = { lock_name == l.name and 'This list is on the lock screen.' or 'Lock screen: its open items when the reader locks.' },
             rows = { { { 'Rename', function()
                            kit.close()
                            ask('Rename list', l.name, function(s)
                              if lock_name == l.name then lock_name = s end
                              l.name = s
                            end)
                          end },
                        { 'Delete', function()
                            kit.close()
                            kit.show({ title = 'Delete ' .. l.name .. '?', lines = { #l.items .. ' items go with it.' },
                                       rows = { { { 'Delete', function()
                                                    kit.close()
                                                    if lock_name == l.name then set_lock(l) end
                                                    for i, x in ipairs(lists) do if x == l then table.remove(lists, i); break end end
                                                    if #lists == 0 then lists = { { name = 'To do', items = {} } } end
                                                    cur = 1
                                                    save()
                                                  end }, { 'Cancel', kit.close } } },
                                       cancel = kit.close })
                          end } },
                      { { lock_name == l.name and 'Lock screen off' or 'Lock screen', function() kit.close(); set_lock(l) end },
                        { 'Close', kit.close } } },
             cancel = kit.close })
end

local function sources()
  local Rm = remote()
  local said = Rm.import_files()
  -- one line an account (with what went wrong in the last sync), how to add one when there is none
  local lines = { said or 'Their lists show after yours; tick and add items here, the rest in their apps.' }
  local has = { todoist = false, google = false, ticktick = false }
  for _k, a in ipairs(Rm.accounts()) do
    has[a.src] = true
    local e = Rm.error(a.id)
    lines[#lines + 1] = Rm.label(a) .. ': ' .. (e or (Rm.ready(a) and 'set up.') or ('sign-in needed: put a new ' .. a.id .. '.txt in AppFiles/tasks.'))
  end
  if not has.todoist then
    lines[#lines + 1] = 'Todoist: type your API token (Settings, Integrations, Developer), or put it in todoist.txt in AppFiles/tasks.'
  end
  if not has.google then
    lines[#lines + 1] = 'Google Tasks: put google.txt (client_id, client_secret, refresh_token) in AppFiles/tasks; the README shows how.'
  end
  if not has.ticktick then
    lines[#lines + 1] = 'TickTick: put ticktick.txt (access_token, or client_id, client_secret and code) in AppFiles/tasks; see the README.'
  end
  lines[#lines + 1] = 'More accounts: todoist-NAME.txt, google-NAME.txt, ticktick-NAME.txt.'
  local function remove_menu()
    local rows = {}
    for k, a in ipairs(Rm.accounts()) do
      local r = rows[(k - 1) // 2 + 1] or {}
      rows[(k - 1) // 2 + 1] = r
      r[#r + 1] = { Rm.label(a), function() kit.close(); local n = Rm.label(a); Rm.remove(a.id); msg = n .. ' removed.' end }
    end
    rows[#rows + 1] = { { 'Cancel', kit.close } }
    kit.show({ title = 'Remove which account?', lines = { 'Its lists leave the reader; nothing changes in the service.' },
               rows = rows, cancel = kit.close })
  end
  kit.show({ title = 'Todoist, Google Tasks, TickTick', lines = lines,
             rows = { { { 'Todoist token', function()
                          kit.close()
                          ctx.input:text({ title = 'Todoist API token', text = '', max_bytes = 128, secret = true }, function(c, t)
                            t = (t or ''):gsub('%s', '')
                            if t ~= '' then Rm.set_todoist(t); msg = 'Todoist: syncing...'; Rm.sync() end
                            kit.refresh()
                          end)
                        end },
                        { 'Read files', function()
                          kit.close()
                          msg = Rm.import_files() or 'No account file in AppFiles/tasks.'
                          if Rm.configured() then Rm.sync() end
                        end } },
                      { { 'Remove', function() remove_menu() end, #Rm.accounts() > 0 }, { 'Close', kit.close } } },
             cancel = kit.close })
  if said and Rm.configured() then Rm.sync() end
end

------------------------------------------------------------------ screens

local function buttons()
  if screen == 'lists' then return { 'New list', 'Sync', 'Sources', 'Help' } end
  return { 'Back', 'Add', 'Clear done', 'List' }
end
-- in a list "Clear done" gets the widest button; on the list of lists the two share the width
local LIST_WIDTHS = { 92, 92, 168, 92 }
local function button_rect(k, n)
  if n == 4 and screen == 'list' then
    local x = 12
    for i = 1, k - 1 do x = x + LIST_WIDTHS[i] + 8 end
    return x, BTN_Y, LIST_WIDTHS[k], BTN_H
  end
  local bw = math.floor((W - 24 - (n - 1) * 8) / n)
  return 12 + (k - 1) * (bw + 8), BTN_Y, bw, BTN_H
end

local function rows()
  if screen == 'lists' then return all() end
  return current().items
end

-- more than one page: a row gives way to Prev, Next and "10-16 of 16"
local function per_page() return #rows() > ROWS and ROWS - 1 or ROWS end
local PAGE_Y = TOP + (ROWS - 1) * ROW_H + 6
local PREV_BTN = { x = W - 12 - 2 * 100 - 8, y = PAGE_Y, w = 100, h = 50 }
local NEXT_BTN = { x = W - 12 - 100, y = PAGE_Y, w = 100, h = 50 }
local function in_rect(b, x, y) return x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h end
local function page(dir)
  local n, pp = #rows(), per_page()
  if dir > 0 and top + pp <= n then top = top + pp
  elseif dir < 0 and top > 1 then top = math.max(1, top - pp) end
end

local function draw_checkbox(gg, x, y, done)
  gg:rect(x, y, 34, 34, { line_width = 3 })
  if done then
    for o = 0, 2 do
      gg:line(x + 6, y + 17 + o, x + 14, y + 26 + o)
      gg:line(x + 14, y + 26 + o, x + 29, y + 8 + o)
    end
  end
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    gg:clear(0)
    if screen == 'lists' then
      local n = #all()
      gg:text(12, 12, 'Tasks', { font = kit.font('large') })
      -- the services' state (Synced 10:42, No Wi-Fi, an error) in place of the hint
      local line = (R and R.status()) or (n .. ' list' .. (n == 1 and '' or 's') .. '    long-press a list for more')
      gg:text(12, 52, kit.short(line, 44), { font = kit.font('small') })
    else
      local l = current()
      local open, done = counts(l)
      gg:text(12, 12, kit.short(l.name, 26), { font = kit.font('large') })
      gg:text(12, 52, open .. ' to do, ' .. done .. ' done' .. (l.src and ('    ' .. R.label(l)) or '') ..
              (lock_name == key_of(l) and '    on the lock screen' or ''), { font = kit.font('small') })
    end
    gg:line(0, 88, W, 88)
    if kit.modal() then kit.draw_modal(gg); return end
    local rs = rows()
    local pp = per_page()
    for k = top, math.min(#rs, top + pp - 1) do
      local y = TOP + (k - top) * ROW_H
      local r = rs[k]
      if screen == 'lists' then
        local open, done = counts(r)
        gg:text(20, y + 8, kit.short(r.name, 30), { font = kit.font('medium') })
        gg:text(20, y + 36, (r.src and (R.label(r) .. ', ') or '') .. open .. ' to do, ' .. done .. ' done' ..
                (lock_name == key_of(r) and ', lock screen' or ''), { font = kit.font('small') })
      else
        -- a service's sub-item is drawn further in
        local ind = 24 * (r.depth or 0)
        draw_checkbox(gg, 16 + ind, y + 14, r.done)
        local f = kit.font('medium')
        local tx, tw = 64 + ind, W - 90 - ind
        local status = r.every and repeat_status(r) or ((r.due or r.rec) and due_status(r)) or nil
        if status then
          -- one line of text, the repeat or the date under it
          local s = r.text
          while #s > 1 and kit.width(f, s) > tw do s = kit.drop_last(s) end
          if s ~= r.text then s = kit.drop_last(kit.drop_last(s)) .. '..' end
          gg:text(tx, y + 4, s, { font = f })
          gg:text(tx, y + 36, status, { font = kit.font('small') })
          if r.done then gg:line(tx, y + 16, tx + math.min(tw, kit.width(f, s)), y + 16) end
        else
          local lines_ = kit.wrap(r.text, 'medium', tw)
          gg:text(tx, y + (#lines_ > 1 and 6 or 18), lines_[1], { font = f })
          if lines_[2] then gg:text(tx, y + 32, kit.short(lines_[2], 34), { font = f }) end
          if r.done then gg:line(tx, y + 30, tx + math.min(tw, kit.width(f, lines_[1])), y + 30) end
        end
      end
      gg:line(12, y + ROW_H - 2, W - 12, y + ROW_H - 2)
    end
    if #rs == 0 then gg:text(20, TOP + 20, screen == 'lists' and 'No lists.' or 'Nothing to do. Add something.', { font = kit.font('medium') }) end
    if pp < ROWS then
      gg:text(20, PAGE_Y + 14, top .. '-' .. math.min(#rs, top + pp - 1) .. ' of ' .. #rs, { font = kit.font('medium') })
      kit.button(gg, PREV_BTN.x, PREV_BTN.y, PREV_BTN.w, PREV_BTN.h, 'Prev', { font = 'medium', line_width = top > 1 and 2 or 1 })
      kit.button(gg, NEXT_BTN.x, NEXT_BTN.y, NEXT_BTN.w, NEXT_BTN.h, 'Next', { font = 'medium', line_width = top + pp <= #rs and 2 or 1 })
    end
    if msg then gg:text(12, BTN_Y - 30, kit.short(msg, 30), { font = kit.font('small') }) end
    local bs = buttons()
    for k, b in ipairs(bs) do
      local x, y, bw, bh = button_rect(k, #bs)
      kit.button(gg, x, y, bw, bh, b, { font = 'medium' })
    end
    if ERR then gg:text(12, H - 24, kit.short('ERR ' .. ERR, 48), { font = kit.font('small') }) end
  end)
  if not ok then pcall(function() gg:text(8, H - 60, kit.short('draw ERR ' .. tostring(e), 46)) end) end
end

------------------------------------------------------------------ input

local function press(b)
  msg = nil
  if b == 'New list' then
    ask('New list', '', function(s) lists[#lists + 1] = { name = s, items = {} }; cur = #lists; screen = 'list'; top = 1; open_key = s end)
  elseif b == 'Sync' then
    local Rm = remote()
    if Rm.configured() then Rm.sync() else sources() end
  elseif b == 'Sources' then sources()
  elseif b == 'Help' then
    kit.show({ title = 'Tasks', lines = { 'Tap a list to open it; long-press it to rename, delete or put it on the lock screen.',
                                          'In a list: tap the box to tick an item, tap its text (or long-press) to edit, move or delete it.',
                                          'Repeat (in that menu): a ticked item comes back when it is due again, such as every week or every 3 months.',
                                          'The lists are the file lists.txt in XTApps/tasks/files/: "# name" and "[ ] item" lines.',
                                          'Sources: your Todoist and Google Tasks lists after these; tick and add items here, Sync fetches them again.' },
               rows = { { { 'Close', kit.close } } }, cancel = kit.close })
  elseif b == 'Back' then screen, top, open_key = 'lists', 1, nil
  elseif b == 'Add' then
    local l = current()
    ask('New item', '', function(s)
      if l.src then remote().add(l, s); return end
      local items = l.items; items[#items + 1] = { text = s, done = false }
    end)
  elseif b == 'Clear done' then
    if current().src then msg = 'Done items leave ' .. R.label(current()) .. ' lists there.'; return end
    -- the ticked (struck-through) items go, after asking: there is no undo; repeating ones stay
    local items, keep = current().items, {}
    for _k, it in ipairs(items) do if not it.done or it.every then keep[#keep + 1] = it end end
    local n = #items - #keep
    if n == 0 then msg = 'Nothing to clear.'; return end
    kit.show({ title = 'Clear ' .. n .. ' done item' .. (n == 1 and '' or 's') .. '?', lines = { 'The ticked items are removed from ' .. current().name .. '.' },
               rows = { { { 'Clear', function() kit.close(); current().items = keep; msg = n .. ' cleared.'; save() end },
                          { 'Cancel', kit.close } } },
               cancel = kit.close })
  elseif b == 'List' then list_menu(cur) end
end

local function row_at(y)
  if y < TOP or y >= TOP + per_page() * ROW_H then return nil end
  local k = top + (y - TOP) // ROW_H
  return rows()[k] and k or nil
end

local function tap(x, y, long)
  if kit.tap_modal(x, y) then return end
  local bs = buttons()
  for k, b in ipairs(bs) do
    local bx, by, bw, bh = button_rect(k, #bs)
    if x >= bx and x < bx + bw and y >= by and y < by + bh then press(b); return end
  end
  if per_page() < ROWS and (in_rect(PREV_BTN, x, y) or in_rect(NEXT_BTN, x, y)) then
    page(in_rect(NEXT_BTN, x, y) and 1 or -1)
    return
  end
  local k = row_at(y)
  if not k then return end
  msg = nil
  if screen == 'lists' then
    if long then list_menu(k) else cur, screen, top = k, 'list', 1; open_key = key_of(all()[k]); save() end
  else
    local it = current().items[k]
    if x < 60 and not long then tick(it)
    else item_menu(k) end
  end
end

local long_done, suppress_up = false, false
-- one frame for a tap: the finger going down draws nothing
function on_input(c, ev)
  local handled, redraw = true, true
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    refresh_due()
    if ev.type == 'pointer' then
      local x, y = ev.x or 0, ev.y or 0
      if ev.phase == 'down' or ev.phase == 'move' then redraw = false end
      if ev.phase == 'up' then ERR = nil end
      if ev.phase == 'down' then long_done = false end
      if (ev.gesture == 'long' or ev.phase == 'hold') and not kit.modal() then
        if not long_done then tap(x, y, true) end
        long_done = true
        suppress_up = ev.phase ~= 'up'
        if ev.phase == 'up' then long_done = false end
        return
      end
      if ev.phase ~= 'up' then return end
      long_done = false
      if suppress_up then suppress_up = false; return end
      -- a swipe turns the page (up or left: on), and is never taken for a tap on a row
      local gst = ev.gesture or ''
      if gst:find('^swipe') then
        if not kit.modal() then page((gst == 'swipe_up' or gst == 'swipe_left') and 1 or -1) end
        return
      end
      tap(x, y, false)
    elseif ev.type == 'key' then
      -- Back on the list of lists: the host asks whether to leave
      if ev.key == 'back' and screen == 'lists' and not kit.modal() then
        handled, redraw = false, false
        return
      end
      if not kit.key_accepted(ev) then redraw = false; return end
      if kit.modal() then
        if ev.key == 'back' and kit.modal().cancel then kit.modal().cancel() end
      elseif ev.key == 'down' or ev.key == 'right' then page(1)
      elseif ev.key == 'up' or ev.key == 'left' then page(-1)
      elseif ev.key == 'back' and screen == 'list' then screen, top, open_key = 'lists', 1, nil end
    end
  end)
  if not ok then ERR = tostring(e); redraw = true end
  if redraw then kit.refresh() end
  return handled
end

function on_load(c)
  local ok, e = pcall(function()
    load()
    refresh_due()
    -- the services' code only when one is set up (or its file was just put on the card)
    -- an account file just put in AppFiles/tasks: todoist.txt, google-work.txt, ...
    local function card()
      local ok2, l = pcall(function() return ctx.files and ctx.files:list() end)
      for _k, f in ipairs(ok2 and type(l) == 'table' and l or {}) do
        local n = type(f) == 'table' and type(f.name) == 'string' and f.name:lower() or ''
        if n:match('^todoist.*%.txt$') or n:match('^google.*%.txt$') or n:match('^ticktick.*%.txt$') then return true end
      end
      return false
    end
    if (kit.read('remote_accounts.json') or '') ~= '' or card() then
      local Rm = remote()
      msg = Rm.import_files()
      if Rm.configured() then Rm.sync() end
    end
  end)
  if not ok then ERR = tostring(e) end
end
function on_leave() pcall(save) end

if rawget(_G, '__TEST') then
  __TEST.api = { lists = function() return all() end, screen = function() return screen end, cur = function() return cur end,
                 remote = function() return R end, sources = sources,
                 parse = parse, serialize = serialize, lock = function() return lock_name end,
                 due = due, parse_every = parse_every, days = days_from_civil, today = local_day }
end
