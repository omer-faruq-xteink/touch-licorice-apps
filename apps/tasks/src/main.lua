-- Tasks for XTOS Licorice, API 2.9 (uses tools/gamekit).
--
-- Lists of things to do, ticked off with a tap. Everything lives in one plain text file in the
-- app's storage, lists.txt, which can also be edited on a computer (XTApps/tasks/files/):
--
--   # Shopping
--   [ ] bread
--   [x] milk
--
-- A list can be the lock screen (lockscreen.lua): its open items in the large font, with the date.
-- The app writes lock.txt (the list's name and open items) whenever that list changes.

local W, H = kit.W, kit.H
local TOP = 96
local ROW_H = 64
local ROWS = 9
local BTN_Y, BTN_H = 704, 64

local lists = {}                -- { { name, items = { { text, done } } } }
local screen = 'lists'          -- lists | list
local cur = 1                   -- the open list
local top = 1                   -- first row shown
local lock_name = nil           -- the list on the lock screen
local msg, ERR = nil, nil

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
        items[#items + 1] = { text = t, done = mark ~= ' ' }
      end
    end
  end
  return out
end

local function serialize()
  local out = {}
  for _k, l in ipairs(lists) do
    out[#out + 1] = '# ' .. l.name
    for _j, it in ipairs(l.items) do out[#out + 1] = (it.done and '[x] ' or '[ ] ') .. it.text end
    out[#out + 1] = ''
  end
  return table.concat(out, '\n')
end

local function write_lock()
  if not lock_name then return end
  for _k, l in ipairs(lists) do
    if l.name == lock_name then
      local open = {}
      for _j, it in ipairs(l.items) do if not it.done then open[#open + 1] = it.text end end
      kit.write('lock.txt', l.name .. '\n' .. table.concat(open, '\n'))
      return
    end
  end
end

local function save()
  kit.write('lists.txt', serialize())
  kit.write('settings.txt', 'lock=' .. (lock_name or '') .. '\nopen=' .. cur)
  write_lock()
end

local function load()
  lists = parse(kit.read('lists.txt'))
  if #lists == 0 then lists = { { name = 'To do', items = {} } } end
  local t = kit.kv(kit.read('settings.txt'))
  lock_name = (t.lock and t.lock ~= '') and t.lock or nil
  cur = math.max(1, math.min(#lists, tonumber(t.open) or 1))
end

------------------------------------------------------------------ actions

local function ask(title, value, fn)
  ctx.input:text({ title = title, text = value or '' }, function(c, s)
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
  if lock_name == l.name then
    lock_name = nil
    pcall(function() ctx.storage:remove('lock.txt') end)
    local okd, isdef = pcall(function() return L:is_default() end)
    if L and okd and isdef == true then pcall(function() L:clear_default() end) end
    msg = 'Lock screen: off.'
    save()
    return
  end
  lock_name = l.name
  save()
  if not L then msg = 'This firmware has no app lock screen.'; return end
  local okd, isdef = pcall(function() return L:is_default() end)
  if not (okd and isdef == true) then pcall(function() L:set_default() end) end
  msg = 'Lock screen: ' .. l.name .. '.'
end

local function item_menu(i)
  local l = lists[cur]
  local it = l.items[i]
  kit.show({ title = kit.short(it.text, 40), lines = {},
             rows = { { { 'Edit', function() kit.close(); ask('Edit', it.text, function(s) it.text = s end) end },
                        { 'Delete', function() kit.close(); table.remove(l.items, i); save() end } },
                      { { 'Up', function() kit.close(); if i > 1 then l.items[i], l.items[i - 1] = l.items[i - 1], it; save() end end, i > 1 },
                        { 'Down', function() kit.close(); if i < #l.items then l.items[i], l.items[i + 1] = l.items[i + 1], it; save() end end, i < #l.items } },
                      { { 'Close', kit.close } } },
             cancel = kit.close })
end

local function list_menu(k)
  local l = lists[k]
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
                                                    table.remove(lists, k)
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

------------------------------------------------------------------ screens

local function buttons()
  if screen == 'lists' then return { 'New list', 'Help' } end
  return { 'Back', 'Add', 'Clear done', 'List' }
end
-- in a list "Clear done" gets the widest button; on the list of lists the two share the width
local LIST_WIDTHS = { 92, 92, 168, 92 }
local function button_rect(k, n)
  if n == 4 then
    local x = 12
    for i = 1, k - 1 do x = x + LIST_WIDTHS[i] + 8 end
    return x, BTN_Y, LIST_WIDTHS[k], BTN_H
  end
  local bw = math.floor((W - 24 - (n - 1) * 8) / n)
  return 12 + (k - 1) * (bw + 8), BTN_Y, bw, BTN_H
end

local function rows()
  if screen == 'lists' then return lists end
  return lists[cur].items
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
      gg:text(12, 12, 'Tasks', { font = kit.font('large') })
      gg:text(12, 52, #lists .. ' list' .. (#lists == 1 and '' or 's') .. '    long-press a list for more', { font = kit.font('small') })
    else
      local l = lists[cur]
      local open, done = counts(l)
      gg:text(12, 12, kit.short(l.name, 26), { font = kit.font('large') })
      gg:text(12, 52, open .. ' to do, ' .. done .. ' done' .. (lock_name == l.name and '    on the lock screen' or ''), { font = kit.font('small') })
    end
    gg:line(0, 88, W, 88)
    if kit.modal() then kit.draw_modal(gg); return end
    local rs = rows()
    for k = top, math.min(#rs, top + ROWS - 1) do
      local y = TOP + (k - top) * ROW_H
      local r = rs[k]
      if screen == 'lists' then
        local open, done = counts(r)
        gg:text(20, y + 8, kit.short(r.name, 30), { font = kit.font('medium') })
        gg:text(20, y + 36, open .. ' to do, ' .. done .. ' done' .. (lock_name == r.name and ', lock screen' or ''), { font = kit.font('small') })
      else
        draw_checkbox(gg, 16, y + 14, r.done)
        local f = kit.font('medium')
        local lines_ = kit.wrap(r.text, 'medium', W - 90)
        gg:text(64, y + (#lines_ > 1 and 6 or 18), lines_[1], { font = f })
        if lines_[2] then gg:text(64, y + 32, kit.short(lines_[2], 34), { font = f }) end
        if r.done then gg:line(64, y + 30, 64 + math.min(W - 90, kit.width(f, lines_[1])), y + 30) end
      end
      gg:line(12, y + ROW_H - 2, W - 12, y + ROW_H - 2)
    end
    if #rs == 0 then gg:text(20, TOP + 20, screen == 'lists' and 'No lists.' or 'Nothing to do. Add something.', { font = kit.font('medium') }) end
    if #rs > ROWS then gg:text(W - 140, BTN_Y - 30, 'swipe: ' .. top .. '-' .. math.min(#rs, top + ROWS - 1) .. ' of ' .. #rs, { font = kit.font('small') }) end
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
    ask('New list', '', function(s) lists[#lists + 1] = { name = s, items = {} }; cur = #lists; screen = 'list'; top = 1 end)
  elseif b == 'Help' then
    kit.show({ title = 'Tasks', lines = { 'Tap a list to open it; long-press it to rename, delete or put it on the lock screen.',
                                          'In a list: tap the box to tick an item, tap its text (or long-press) to edit, move or delete it.',
                                          'The lists are the file lists.txt in XTApps/tasks/files/: "# name" and "[ ] item" lines.' },
               rows = { { { 'Close', kit.close } } }, cancel = kit.close })
  elseif b == 'Back' then screen, top = 'lists', 1
  elseif b == 'Add' then
    ask('New item', '', function(s) local items = lists[cur].items; items[#items + 1] = { text = s, done = false } end)
  elseif b == 'Clear done' then
    -- the ticked (struck-through) items go, after asking: there is no undo
    local items, keep = lists[cur].items, {}
    for _k, it in ipairs(items) do if not it.done then keep[#keep + 1] = it end end
    local n = #items - #keep
    if n == 0 then msg = 'Nothing is ticked.'; return end
    kit.show({ title = 'Clear ' .. n .. ' done item' .. (n == 1 and '' or 's') .. '?', lines = { 'The ticked items are removed from ' .. lists[cur].name .. '.' },
               rows = { { { 'Clear', function() kit.close(); lists[cur].items = keep; msg = n .. ' cleared.'; save() end },
                          { 'Cancel', kit.close } } },
               cancel = kit.close })
  elseif b == 'List' then list_menu(cur) end
end

local function row_at(y)
  if y < TOP or y >= TOP + ROWS * ROW_H then return nil end
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
  local k = row_at(y)
  if not k then return end
  msg = nil
  if screen == 'lists' then
    if long then list_menu(k) else cur, screen, top = k, 'list', 1; save() end
  else
    local it = lists[cur].items[k]
    if x < 60 and not long then it.done = not it.done; save()
    else item_menu(k) end
  end
end

local long_done, suppress_up = false, false
function on_input(c, ev)
  ERR = nil
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    if ev.type == 'pointer' then
      local x, y = ev.x or 0, ev.y or 0
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
      local n = #rows()
      if ev.gesture == 'swipe_up' and top + ROWS <= n then top = top + ROWS; return end
      if ev.gesture == 'swipe_down' and top > 1 then top = math.max(1, top - ROWS); return end
      tap(x, y, false)
    elseif ev.type == 'key' and kit.key_accepted(ev) then
      if kit.modal() then
        if ev.key == 'back' and kit.modal().cancel then kit.modal().cancel() end
      elseif ev.key == 'down' or ev.key == 'right' then if top + ROWS <= #rows() then top = top + ROWS end
      elseif ev.key == 'up' or ev.key == 'left' then top = math.max(1, top - ROWS)
      elseif ev.key == 'back' and screen == 'list' then screen, top = 'lists', 1 end
    end
  end)
  if not ok then ERR = tostring(e) end
  kit.refresh()
  return true
end

function on_load(c)
  local ok, e = pcall(load)
  if not ok then ERR = tostring(e) end
end
function on_leave() pcall(save) end

if rawget(_G, '__TEST') then
  __TEST.api = { lists = function() return lists end, screen = function() return screen end, cur = function() return cur end,
                 parse = parse, serialize = serialize, lock = function() return lock_name end }
end
