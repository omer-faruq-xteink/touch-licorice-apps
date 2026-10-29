-- TBR Planner for XTOS Licorice, API 2.9 (uses tools/gamekit and src/tbr.lua). A port of
-- KOReader's tbrplanner.koplugin: plan your to-be-read books. Wishlist (no dates yet), Planned
-- (with dates) and Done lists, a month Calendar, and a lock screen with today's books.
--
-- Books come from the reader (every book opened at least once: its progress, reading time and
-- finished state follow the reader) or are typed in. Dates are set with -7 / -1 / +1 / +7 buttons;
-- "Keep duration" moves the end with the start; the daily goal (minutes, or pages for a typed
-- book) gives an end date.

local T = require('tbr')
local W, H = kit.W, kit.H
local TAB_H = 52
local LIST_Y, ROW_H, ROWS = 90, 68, 8
local BTN_Y, BTN_H = 716, 64
local TABS = { 'wish', 'plan', 'cal', 'done' }
local TAB_LABEL = { wish = 'Wishlist', plan = 'Planned', cal = 'Calendar', done = 'Done' }
local MINUTES = { 10, 15, 20, 30, 45, 60, 90, 120 }
local PAGES = { 5, 10, 20, 30, 50, 75, 100 }
local SORT_LABEL = { priority = 'by priority', title = 'by title', newest = 'newest first',
                     oldest = 'oldest first', date = 'by date' }

local cfg = { tab = 'plan', minutes = 30, pages = 20, ws = 1, sort = { wish = 'priority', plan = 'date', done = 'newest' } }
local items, next_id = {}, 1
local rb = {}                          -- the reader's books (T.reader_books)
local filter = ''
local screen = 'main'                  -- main | item | pick | settings
local page = { wish = 1, plan = 1, done = 1 }
local month = 0                        -- the first day of the month shown in Calendar
local cur, keep = nil, true            -- the book being edited; Keep duration
local pick = { page = 1, link = false, start = nil }
local hits = {}
local status, ERR = nil, nil
local go_back                          -- the back key and the Back buttons (input, below)

local function today() return T.today() end
local function save() kit.write('items.txt', T.text(items)) end
local function save_cfg()
  kit.write('settings.txt', 'tab=' .. cfg.tab .. '\nminutes=' .. cfg.minutes .. '\npages=' .. cfg.pages ..
    '\nws=' .. cfg.ws .. '\nsort_wish=' .. cfg.sort.wish .. '\nsort_plan=' .. cfg.sort.plan .. '\nsort_done=' .. cfg.sort.done)
end
local function load_all()
  local t = kit.kv(kit.read('settings.txt'))
  for _, v in ipairs(TABS) do if t.tab == v then cfg.tab = v end end
  cfg.minutes = tonumber(t.minutes) or cfg.minutes
  cfg.pages = tonumber(t.pages) or cfg.pages
  cfg.ws = t.ws == '0' and 0 or 1
  for tab, list in pairs(T.SORTS) do
    for _, s in ipairs(list) do if t['sort_' .. tab] == s then cfg.sort[tab] = s end end
  end
  items, next_id = T.load(kit.read('items.txt'))
end
local function refresh_reader()
  rb = T.reader_books()
  if T.sync(items, rb, today()) then save() end
end
local function month_of(day) local y, m = T.civil(day); return T.days(y, m, 1) end

local function ask_text(title, value, fn)
  ctx.input:text({ title = title, text = value or '', max_chars = 200, max_bytes = 256 }, function(c, s)
    local ok, e = pcall(fn, s)
    if not ok then ERR = tostring(e) end
    kit.refresh()
  end)
end
local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end

------------------------------------------------------------------ books

local function open_item(it) cur, screen, keep = it, 'item', true end

-- a new book for the tab in use: planned ones start today (or on the calendar's day)
local function add_item(title, author, book, start)
  local d = today()
  local it = { id = next_id, status = 'wish', title = title, author = author or '', book = book or '',
               prio = 0, tags = '', added = d, auto = 1 }
  next_id = next_id + 1
  if start then
    it.start = start
    local r = book and rb[book]
    if r then it.pct, it.sec = r.pct, r.sec end
    it['end'] = T.end_from_goal(it, cfg, d) or (start + 13)
    if it['end'] < start then it['end'] = start end
  end
  T.settle(it)
  items[#items + 1] = it
  save()
  open_item(it)
end

local function linked(id)
  for _, it in ipairs(items) do if it.book == id then return it end end
  return nil
end

-- the reader's books, the last read first
local function reader_list()
  local out = {}
  for _, r in pairs(rb) do out[#out + 1] = r end
  table.sort(out, function(a, b)
    local x, y = a.last or 0, b.last or 0
    if x ~= y then return x > y end
    return a.title < b.title
  end)
  return out
end

local function start_for_tab()
  if cfg.tab == 'plan' then return today() end
  if cfg.tab == 'cal' then return math.max(today(), month) end
  return nil
end

local function new_box(start)
  kit.show({ title = 'Add a book', cancel = kit.close,
    lines = { 'From the reader: a book you opened on this reader at least once. Or type its title.' },
    rows = {
      { { 'From the reader', function() kit.close(); pick = { page = 1, link = false, start = start }; screen = 'pick' end } },
      { { 'Type the title', function()
          kit.close()
          ask_text('Title', '', function(s)
            s = trim(s)
            if s ~= '' then add_item(s, '', '', start) end
          end)
        end } },
      { { 'Cancel', kit.close } } } })
end

local function delete_item(it)
  kit.show({ title = 'Delete "' .. kit.short(it.title, 40) .. '"?', lines = { 'Only the planner forgets it; the book stays on the reader.' },
    cancel = kit.close, rows = { { { 'Delete', function()
      for k, x in ipairs(items) do if x == it then table.remove(items, k); break end end
      save(); kit.close(); screen = 'main'; cur = nil
    end }, { 'Cancel', kit.close } } } })
end

local function set_done(it, done)
  if done then it.status, it.done = 'done', today()
  else
    it.status, it.done = 'wish', nil
    if it.book ~= '' then it.auto = 0 end      -- the reader's "finished" no longer marks it done
    T.settle(it)
  end
  save()
end

local function to_wishlist(it)
  it.status, it.start, it['end'], it.done = 'wish', nil, nil, nil
  T.settle(it)
  save()
end
local function plan(it)
  local d = today()
  it.status = 'wish'
  it.start = it.start or d
  it['end'] = it['end'] or T.end_from_goal(it, cfg, d) or (it.start + 13)
  T.settle(it)
  save()
end

-- move a date: Keep duration moves the end with the start
local function shift(it, which, n)
  local d = today()
  if which == 'start' then
    if not it.start then it.start = it['end'] and math.min(it['end'], d) or d
    else
      it.start = it.start + n
      if keep and it['end'] then it['end'] = it['end'] + n end
    end
    if it['end'] and it['end'] < it.start then it['end'] = it.start end
  else
    if not it['end'] then it['end'] = it.start or d
    else it['end'] = it['end'] + n end
    if it.start and it['end'] < it.start then it['end'] = it.start end
  end
  if it.status == 'done' then it.status = 'plan' end
  T.settle(it)
  save()
end

local function date_box(it, which)
  kit.show({ title = (which == 'start' and 'Start' or 'End') .. ' date', cancel = kit.close,
    lines = { it[which] and T.long_date(it[which]) or 'none' },
    rows = {
      { { 'Today', function() it[which] = today(); if it.status == 'done' then it.status = 'plan' end
          if which == 'start' and it['end'] and it['end'] < it.start then it['end'] = it.start end
          if which == 'end' and it.start and it['end'] < it.start then it.start = it['end'] end
          T.settle(it); save(); kit.close() end },
        { 'Type it', function()
          kit.close()
          ask_text('Date (YYYY-MM-DD)', it[which] and T.iso(it[which]) or T.iso(today()), function(s)
            local d = T.parse_iso(s)
            if not d then status = 'Not a date: use YYYY-MM-DD.'; return end
            it[which] = d
            if it.status == 'done' then it.status = 'plan' end
            if which == 'start' and it['end'] and it['end'] < d then it['end'] = d end
            if which == 'end' and it.start and d < it.start then it.start = d end
            T.settle(it); save()
          end)
        end } },
      { { 'No date', function() it[which] = nil; T.settle(it); save(); kit.close() end }, { 'Close', kit.close } } } })
end

local function link_box(it)
  local r = rb[it.book]
  kit.show({ title = 'Book on the reader', cancel = kit.close,
    lines = { r and r.title or 'This book is not in the reader\'s list any more.' },
    rows = { { { 'Change', function() kit.close(); pick = { page = 1, link = true }; screen = 'pick' end },
               { 'Unlink', function() it.book, it.pct, it.sec, it.pct0, it.sec0, it.auto = '', nil, nil, nil, nil, 1; save(); kit.close() end } },
             { { 'Close', kit.close } } } })
end

------------------------------------------------------------------ drawing helpers

local function hit(x, y, w, h, fn) hits[#hits + 1] = { x = x, y = y, w = w, h = h, fn = fn } end
local function fit(fname, s, w)
  local f = kit.font(fname)
  s = tostring(s)
  if kit.width(f, s) <= w then return s end
  while #s > 1 and kit.width(f, s .. '~') > w do s = kit.drop_last(s) end
  return s .. '~'
end
local function arrow(b) return b == '<' or b == '>' end
local ARROW_W = 64
local function button_rect(k, bs)
  local n, narrow = #bs, 0
  for _, b in ipairs(bs) do if arrow(b) then narrow = narrow + 1 end end
  local bw = math.floor((W - 24 - (n - 1) * 8 - narrow * ARROW_W) / math.max(1, n - narrow))
  local x = 12
  for i = 1, k - 1 do x = x + (arrow(bs[i]) and ARROW_W or bw) + 8 end
  return x, BTN_Y, arrow(bs[k]) and ARROW_W or bw, BTN_H
end

local function buttons()
  if screen == 'item' then
    local it = cur
    return { it.status == 'plan' and 'To wishlist' or 'Plan', it.status == 'done' and 'Mark unread' or 'Mark as read' }
  elseif screen == 'pick' then return pick.link and { '<', '>' } or { '<', '>', 'Type it' }
  elseif screen == 'settings' then return { 'Back' } end
  if cfg.tab == 'cal' then return { '<', 'Today', '>', '+ New', 'More' } end
  return { '<', '>', '+ New', 'Sort', 'More' }
end

local function top_bar(gg, title, right)
  kit.button(gg, 8, 6, 100, 40, 'Back', { font = 'medium' })
  hit(8, 6, 100, 40, function() go_back() end)
  gg:text(124, 14, fit('medium', title, right and 220 or 340), { font = kit.font('medium') })
  if right then
    kit.button(gg, W - 108, 6, 100, 40, right[1], { font = 'medium' })
    hit(W - 108, 6, 100, 40, right[2])
  end
  gg:line(0, 52, W, 52)
end

------------------------------------------------------------------ lists

-- "Stephen King · 27 Oct - 3 Nov · 82% · 3 days left · ★2 · #crime"
local function row_info(it, d)
  local parts = {}
  if it.author ~= '' then parts[#parts + 1] = it.author end
  if it.status == 'plan' then parts[#parts + 1] = T.span(it) end
  if it.status == 'done' and it.done then parts[#parts + 1] = 'done ' .. T.short_date(it.done) end
  local p = T.percent(it)
  if p and it.status ~= 'done' and p > 0 then parts[#parts + 1] = p .. '%' end
  local st = T.state(it, d)
  if st == 'today' or st == 'late' then parts[#parts + 1] = T.when(it, d) end   -- a later one: its dates say it
  if it.prio ~= 0 then parts[#parts + 1] = 'prio ' .. it.prio end
  if it.tags ~= '' then
    local tg = {}
    for raw in it.tags:gmatch('[^,]+') do
      local t = trim(raw)
      if t ~= '' then tg[#tg + 1] = '#' .. t end
    end
    parts[#parts + 1] = table.concat(tg, ' ')
  end
  return table.concat(parts, ' · ')
end

local function draw_list(gg)
  local tab, d = cfg.tab, today()
  local list = T.list(items, tab, cfg.sort[tab], filter)
  local pages = math.max(1, (#list + ROWS - 1) // ROWS)
  if page[tab] > pages then page[tab] = pages end
  local head = T.plural(#list, 'book', 'books') .. ', ' .. SORT_LABEL[cfg.sort[tab]] .. (filter ~= '' and (', filter "' .. filter .. '"') or '')
  gg:text(12, 60, fit('small', head, W - 90), { font = kit.font('small') })
  gg:text(W - 60, 60, page[tab] .. '/' .. pages, { font = kit.font('small') })
  if #list == 0 then
    local msg = tab == 'wish' and 'No books on the wishlist yet: tap + New.'
      or tab == 'plan' and 'Nothing planned yet: tap + New, or Plan a wishlist book.'
      or 'No finished books yet.'
    for k, l in ipairs(kit.wrap(msg, 'medium', W - 40)) do gg:text(16, LIST_Y + 20 + (k - 1) * 30, l, { font = kit.font('medium') }) end
    return
  end
  for i = 1, ROWS do
    local it = list[(page[tab] - 1) * ROWS + i]
    if not it then break end
    local y = LIST_Y + (i - 1) * ROW_H
    local st = T.state(it, d)
    if st == 'today' then gg:rect(4, y, W - 8, ROW_H - 6, { line_width = 3 })
    else gg:line(12, y + ROW_H - 4, W - 12, y + ROW_H - 4) end
    gg:text(14, y + 8, fit('medium', (st == 'late' and '! ' or '') .. it.title, W - 28), { font = kit.font('medium') })
    gg:text(14, y + 38, fit('small', row_info(it, d), W - 28), { font = kit.font('small') })
    hit(4, y, W - 8, ROW_H - 4, function() open_item(it) end)
  end
end

------------------------------------------------------------------ calendar

local function day_box(day)
  local rows = {}
  local on = T.on_day(items, day)
  for k = 1, math.min(#on, 5) do
    local it = on[k]
    rows[#rows + 1] = { { kit.short(it.title, 30), function() kit.close(); open_item(it) end } }
  end
  rows[#rows + 1] = { { '+ New from this day', function() kit.close(); new_box(day) end } }
  rows[#rows + 1] = { { 'Close', kit.close } }
  kit.show({ title = T.long_date(day), cancel = kit.close,
             lines = { #on == 0 and 'Nothing planned.' or (#on > 5 and (#on .. ' books; the first 5:') or T.plural(#on, 'book', 'books')) },
             rows = rows })
end

local function draw_calendar(gg)
  local d = today()
  local y0, m0 = T.civil(month)
  gg:text(12, 58, T.MONTH[m0] .. ' ' .. y0, { font = kit.font('medium') })
  local lead = (T.wday(month) - cfg.ws) % 7
  local first = month - lead
  local n = T.month_len(y0, m0)
  local weeks = (lead + n + 6) // 7
  local GY, GB = 112, BTN_Y - 34
  local cw, ch = W // 7, (GB - GY) // weeks
  local x0 = (W - 7 * cw) // 2
  for k = 0, 6 do
    gg:text(x0 + k * cw + 6, 88, T.WDAY[(k + cfg.ws) % 7 + 1], { font = kit.font('small') })
  end
  for r = 0, weeks do gg:line(x0, GY + r * ch, x0 + 7 * cw, GY + r * ch) end
  for k = 0, 7 do gg:line(x0 + k * cw, GY, x0 + k * cw, GY + weeks * ch) end
  local lanes = math.max(1, (ch - 26) // 22)
  for r = 0, weeks - 1 do
    local w0 = first + r * 7
    local cy = GY + r * ch
    for k = 0, 6 do
      local day = w0 + k
      local cx = x0 + k * cw
      if day >= month and day < month + n then
        local _y, _m, dd = T.civil(day)
        gg:text(cx + 5, cy + 3, tostring(dd), { font = kit.font('small') })
        if day == d then gg:rect(cx + 2, cy + 2, cw - 3, ch - 3, { line_width = 3 }) end
      end
      hit(cx, cy, cw, ch, function() day_box(day) end)
    end
    -- the books of this week as bars, one lane each; what does not fit counts as "+n" per day
    local week = {}
    for _, it in ipairs(items) do
      if it.status == 'plan' then
        local s, e = it.start or it['end'], it['end'] or it.start
        if s <= w0 + 6 and e >= w0 then week[#week + 1] = { it = it, s = math.max(s, w0), e = math.min(e, w0 + 6) } end
      end
    end
    table.sort(week, function(a, b) if a.s ~= b.s then return a.s < b.s end return a.it.id < b.it.id end)
    local lane_end, more = {}, {}
    for _, b in ipairs(week) do
      local lane = nil
      for l = 1, lanes do if not lane_end[l] or lane_end[l] < b.s then lane = l; break end end
      if lane then
        lane_end[lane] = b.e
        local bx = x0 + (b.s - w0) * cw + 3
        local bw = (b.e - b.s + 1) * cw - 6
        local by = cy + 24 + (lane - 1) * 22
        gg:rect(bx, by, bw, 20)
        gg:text(bx + 3, by, fit('small', b.it.title, bw - 6), { font = kit.font('small') })
      else
        for day = b.s, b.e do more[day] = (more[day] or 0) + 1 end
      end
    end
    for day, c in pairs(more) do
      gg:text(x0 + (day - w0) * cw + cw - 30, cy + ch - 22, '+' .. c, { font = kit.font('small') })
    end
  end
end

------------------------------------------------------------------ the book screen

local IY, IH = 60, 56
local function draw_item(gg)
  local it, d = cur, today()
  top_bar(gg, it.status == 'wish' and 'Wishlist' or it.status == 'plan' and 'Planned' or 'Done',
    { 'Delete', function() delete_item(it) end })
  local function row(k, label, value, w, fn)
    local y = IY + (k - 1) * IH
    gg:text(16, y + 4, label, { font = kit.font('small') })
    gg:text(16, y + 24, fit('medium', value, w or (W - 32)), { font = kit.font('medium') })
    gg:line(12, y + IH - 3, W - 12, y + IH - 3)
    if fn then hit(0, y, w and (w + 16) or W, IH - 2, fn) end
    return y
  end
  local function small_buttons(y, labels, fns)
    local bw, gap = 50, 6
    local x = W - 12 - #labels * bw - (#labels - 1) * gap
    for k, l in ipairs(labels) do
      kit.button(gg, x, y + 6, bw, IH - 14, l, { font = 'small' })
      hit(x, y + 2, bw, IH - 6, fns[k])
      x = x + bw + gap
    end
  end
  row(1, 'Title', it.title, nil, function()
    ask_text('Title', it.title, function(s) s = trim(s); if s ~= '' then it.title = s; save() end end)
  end)
  row(2, 'Author', it.author ~= '' and it.author or '(none)', nil, function()
    ask_text('Author', it.author, function(s) it.author = trim(s); save() end)
  end)
  local r = it.book ~= '' and rb[it.book]
  row(3, 'On the reader', it.book == '' and 'not linked (tap to pick)' or (r and r.title or 'not in its list now'), nil, function()
    if it.book == '' then pick = { page = 1, link = true }; screen = 'pick' else link_box(it) end
  end)
  local y = row(4, 'Priority', tostring(it.prio), 200)
  small_buttons(y, { '-', '+' }, { function() it.prio = it.prio - 1; save() end, function() it.prio = it.prio + 1; save() end })
  row(5, 'Tags (comma-separated)', it.tags ~= '' and it.tags or '(none)', nil, function()
    ask_text('Tags (comma-separated)', it.tags, function(s) it.tags = trim(s); save() end)
  end)
  local BW = 4 * 50 + 3 * 6 + 16
  y = row(6, 'Start', it.start and T.date(it.start) or 'none', W - 32 - BW, function() date_box(it, 'start') end)
  small_buttons(y, { '-7', '-1', '+1', '+7' }, { function() shift(it, 'start', -7) end, function() shift(it, 'start', -1) end,
                                              function() shift(it, 'start', 1) end, function() shift(it, 'start', 7) end })
  y = row(7, 'End', it['end'] and T.date(it['end']) or 'none', W - 32 - BW, function() date_box(it, 'end') end)
  small_buttons(y, { '-7', '-1', '+1', '+7' }, { function() shift(it, 'end', -7) end, function() shift(it, 'end', -1) end,
                                              function() shift(it, 'end', 1) end, function() shift(it, 'end', 7) end })
  local days = (it.start and it['end']) and (it['end'] - it.start + 1) or nil
  row(8, 'Keep duration (Start moves End too)', (keep and 'on' or 'off') .. (days and ('   ' .. T.plural(days, 'day', 'days')) or ''), nil,
    function() keep = not keep end)
  -- progress: the reader's, or pages typed in
  local p = T.percent(it)
  if it.book ~= '' then
    -- the reader's percent may include pages read elsewhere: pages typed in give the pages left
    local info = (p and p > 0) and (p .. '%' .. (T.by_pages(it) and (' of ' .. it.pages .. ' pages') or ' read')) or 'not started'
    if it.sec and it.sec > 0 then info = info .. ', ' .. T.duration(it.sec) end
    local _d, left = T.left(it, cfg)
    if left then info = info .. ', ' .. left end
    row(9, 'Progress (from the reader; tap: total pages)', info, nil, function()
      ask_text('Total pages (empty: none)', T.by_pages(it) and tostring(it.pages) or '', function(s)
        local n = tonumber(tostring(s or ''):match('^%s*(%d+)%s*$'))
        if trim(s) ~= '' and not n then status = 'Type the number of pages.'; return end
        it.pages = (n and n > 0) and n or nil
        save()
      end)
    end)
  else
    local info = (it.pages or 0) > 0 and ((it.read or 0) .. ' of ' .. it.pages .. ' pages' .. (p and ('  (' .. p .. '%)') or '')) or 'pages: tap to set'
    row(9, 'Progress (pages read / total)', info, nil, function()
      ask_text('Pages read / total, like 40/320', (it.pages or 0) > 0 and ((it.read or 0) .. '/' .. it.pages) or '', function(s)
        local a, b = tostring(s or ''):match('(%d+)%s*/%s*(%d+)')
        if not a then b = tostring(s or ''):match('^%s*(%d+)%s*$'); a = b and (it.read or 0) end
        if not b then status = 'Type pages as read/total, like 40/320.'; return end
        it.read, it.pages = math.min(tonumber(a), tonumber(b)), tonumber(b)
        save()
      end)
    end)
  end
  -- the end date the daily goal gives
  local goal = (it.book ~= '' and not T.by_pages(it)) and (cfg.minutes .. ' min a day') or (cfg.pages .. ' pages a day')
  local e = T.end_from_goal(it, cfg, d)
  y = IY + 9 * IH
  gg:text(16, y + 4, 'At ' .. goal .. ' (the goal is in More)', { font = kit.font('small') })
  if it.status == 'done' then
    gg:text(16, y + 26, 'Read' .. (it.done and (', finished ' .. T.date(it.done)) or '') .. '.', { font = kit.font('medium') })
  elseif e then
    local n = select(1, T.left(it, cfg))
    gg:text(16, y + 26, fit('medium', T.plural(n, 'day', 'days') .. ', ends ' .. T.date(e), W - 160), { font = kit.font('medium') })
    kit.button(gg, W - 140, y + 12, 128, 44, 'Set end', { font = 'medium' })
    hit(W - 140, y + 8, 128, 52, function()
      it.start = it.start or d
      it['end'] = e
      if it.status == 'done' then it.status = 'plan' end
      T.settle(it); save(); status = 'End set to ' .. T.date(e) .. '.'
    end)
  else
    local why = it.book ~= '' and 'Read more here, or set the pages above.' or 'No estimate: set the pages.'
    gg:text(16, y + 26, fit('small', why, W - 32), { font = kit.font('small') })
  end
end

------------------------------------------------------------------ picking a reader book

local PICK_Y, PICK_H = 60, 64
local PICK_N = (BTN_Y - 30 - PICK_Y) // PICK_H
local function choose(r)
  if pick.link and cur then
    cur.book, cur.pct, cur.sec, cur.pct0, cur.sec0, cur.auto = r.id, r.pct, r.sec, nil, nil, 1   -- T.sync starts the pace
    if cur.author == '' then cur.author = r.author or '' end
    save()
    screen = 'item'
    T.sync(items, rb, today()); save()
    return
  end
  local have = linked(r.id)
  if have then status = 'Already in the planner.'; open_item(have); return end
  add_item(r.title, r.author, r.id, pick.start)
  T.sync(items, rb, today()); save()
end

local function draw_pick(gg)
  top_bar(gg, 'Books on the reader')
  local list = reader_list()
  local pages = math.max(1, (#list + PICK_N - 1) // PICK_N)
  if pick.page > pages then pick.page = pages end
  if #list == 0 then
    for k, l in ipairs(kit.wrap('The reader lists a book here once you have opened it. Tap Type it to add one by its title.', 'medium', W - 40)) do
      gg:text(16, PICK_Y + 20 + (k - 1) * 30, l, { font = kit.font('medium') })
    end
    return
  end
  gg:text(W - 60, BTN_Y - 26, pick.page .. '/' .. pages, { font = kit.font('small') })
  for i = 1, PICK_N do
    local r = list[(pick.page - 1) * PICK_N + i]
    if not r then break end
    local y = PICK_Y + (i - 1) * PICK_H
    local info = {}
    if linked(r.id) then info[#info + 1] = 'in the planner' end
    if r.author ~= '' then info[#info + 1] = r.author end
    if r.finished then info[#info + 1] = 'finished' elseif r.pct then info[#info + 1] = r.pct .. '%' end
    if r.last then info[#info + 1] = 'read ' .. T.short_date(r.last) end
    gg:text(14, y + 6, fit('medium', r.title, W - 28), { font = kit.font('medium') })
    gg:text(14, y + 36, fit('small', table.concat(info, ' · '), W - 28), { font = kit.font('small') })
    gg:line(12, y + PICK_H - 4, W - 12, y + PICK_H - 4)
    hit(4, y, W - 8, PICK_H - 4, function() choose(r) end)
  end
end

------------------------------------------------------------------ settings

local function lock_on()
  local ok, v = pcall(function() return ctx.lockscreen:is_default() end)
  return ok and v == true
end
local function cycle(list, v)
  for k, x in ipairs(list) do if x == v then return list[k % #list + 1] end end
  return list[1]
end
local function draw_settings(gg)
  gg:text(16, 12, 'Settings', { font = kit.font('large') })
  local rows = {
    { 'Daily reading goal: ' .. cfg.minutes .. ' min', function() cfg.minutes = cycle(MINUTES, cfg.minutes); save_cfg() end },
    { 'Pages a day: ' .. cfg.pages, function() cfg.pages = cycle(PAGES, cfg.pages); save_cfg() end },
    { 'Week starts on ' .. (cfg.ws == 1 and 'Monday' or 'Sunday'), function() cfg.ws = 1 - cfg.ws; save_cfg() end },
    { 'Filter: ' .. (filter ~= '' and ('"' .. filter .. '"') or 'none (tap to set)'), function()
        ask_text('Show books whose title, author or tags contain', filter, function(s) filter = trim(s); page = { wish = 1, plan = 1, done = 1 } end)
      end },
  }
  if ctx.lockscreen then
    rows[#rows + 1] = { 'Lock screen: ' .. (lock_on() and 'on' or 'off'), function()
      local L = ctx.lockscreen
      if lock_on() then pcall(function() L:clear_default() end); status = 'Lock screen off.'
      else pcall(function() L:set_default() end); status = 'Lock screen: today\'s books.' end
    end }
  end
  for k, r in ipairs(rows) do
    local y = 64 + (k - 1) * 60
    gg:rect(12, y, W - 24, 52)
    gg:text(24, y + 14, fit('medium', r[1], W - 48), { font = kit.font('medium') })
    hit(12, y, W - 24, 52, r[2])
  end
  local y = 64 + #rows * 60 + 10
  local help = 'The goals give a book\'s end date: pages a day for a book with its total pages, ' ..
    'minutes a day for a reader book without them (from your pace on this reader). ' ..
    'The reader marks a linked book done when you finish it.'
  for k, l in ipairs(kit.wrap(help, 'small', W - 32)) do gg:text(16, y + (k - 1) * 24, l, { font = kit.font('small') }) end
end

------------------------------------------------------------------ drawing

-- A box has no fill (a fill draws black), but an image draws its white: a 1x1 white JPEG
-- stretched over the box hides the screen under it (as in Calendar).
local WHITE_JPG = ('ffd8ffe000104a46494600010100000100010000ffdb0043000101010101010101010101010101010101010101010101' ..
  '0101010101010101010101010101010101010101010101010101010101010101010101010101010101ffc0000b080001' ..
  '000101011100ffc4001f0000010501010101010100000000000000000102030405060708090a0bffc400b51000020103' ..
  '03020403050504040000017d01020300041105122131410613516107227114328191a1082342b1c11552d1f024336272' ..
  '82090a161718191a25262728292a3435363738393a434445464748494a535455565758595a636465666768696a737475' ..
  '767778797a838485868788898a92939495969798999aa2a3a4a5a6a7a8a9aab2b3b4b5b6b7b8b9bac2c3c4c5c6c7c8c9' ..
  'cad2d3d4d5d6d7d8d9dae1e2e3e4e5e6e7e8e9eaf1f2f3f4f5f6f7f8f9faffda0008010100003f00fefe2bffd9')
local white = nil
local function white_image()
  if white == nil then
    -- image_decode is an optional capability: without it the box stays transparent
    local ok, img = false, nil
    if ctx.capabilities and ctx.capabilities.image_decode then
      ok, img = pcall(function()
        return ctx.image:decode((WHITE_JPG:gsub('..', function(h) return string.char(tonumber(h, 16)) end)))
      end)
    end
    white = (ok and img) or false
  end
  return white
end
local function modal_rect()
  local r = nil
  kit.draw_modal(setmetatable({}, { __index = function(_, k)
    return function(_, x, y, w, h) if k == 'rect' and not r then r = { x, y, w, h } end end
  end }))
  return r
end

local function draw_main(gg)
  local tw = W // 4
  for k, t in ipairs(TABS) do
    kit.button(gg, (k - 1) * tw + 4, 4, tw - 8, TAB_H - 8, TAB_LABEL[t], { line_width = t == cfg.tab and 4 or 1 })
    hit((k - 1) * tw, 0, tw, TAB_H, function() cfg.tab = t; save_cfg() end)
  end
  if cfg.tab == 'cal' then draw_calendar(gg) else draw_list(gg) end
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    hits = {}
    gg:clear(0)
    if kit.modal() and not white_image() then kit.draw_modal(gg); return end
    if screen == 'item' and cur then draw_item(gg)
    elseif screen == 'pick' then draw_pick(gg)
    elseif screen == 'settings' then draw_settings(gg)
    else screen = 'main'; draw_main(gg) end
    local line = ERR or status
    if line then gg:text(12, BTN_Y - 26, fit('small', line, W - 90), { font = kit.font('small') }) end
    local bs = buttons()
    for k, b in ipairs(bs) do
      local x, y, bw, bh = button_rect(k, bs)
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

local function step(dir)
  if screen == 'pick' then pick.page = math.max(1, pick.page + dir); return end
  if screen ~= 'main' then return end
  if cfg.tab == 'cal' then
    local y, m = T.civil(month)
    m = m + dir
    if m < 1 then y, m = y - 1, 12 elseif m > 12 then y, m = y + 1, 1 end
    month = T.days(y, m, 1)
  else
    page[cfg.tab] = math.max(1, page[cfg.tab] + dir)
  end
end

local function press(b)
  status = nil
  if b == '<' then step(-1)
  elseif b == '>' then step(1)
  elseif b == 'Today' then month = month_of(today())
  elseif b == '+ New' then new_box(start_for_tab())
  elseif b == 'Sort' then
    local tab = cfg.tab
    cfg.sort[tab] = cycle(T.SORTS[tab], cfg.sort[tab]); save_cfg()
    page[tab] = 1
  elseif b == 'More' then screen = 'settings'
  elseif b == 'Back' then go_back()
  elseif b == 'Type it' then
    ask_text('Title', '', function(s)
      s = trim(s)
      if s ~= '' then add_item(s, '', '', pick.start) end
    end)
  elseif b == 'Plan' then plan(cur)
  elseif b == 'To wishlist' then to_wishlist(cur)
  elseif b == 'Mark as read' then set_done(cur, true)
  elseif b == 'Mark unread' then set_done(cur, false) end
end

local function tap(x, y)
  if kit.tap_modal(x, y) then return end
  local bs = buttons()
  for k, b in ipairs(bs) do
    local bx, by, bw, bh = button_rect(k, bs)
    if x >= bx and x < bx + bw and y >= by and y < by + bh then press(b); return end
  end
  for i = #hits, 1, -1 do                 -- the last drawn first: small buttons over their row
    local h = hits[i]
    if x >= h.x and x < h.x + h.w and y >= h.y and y < h.y + h.h then status = nil; h.fn(); return end
  end
end

go_back = function()
  if kit.modal() then
    if kit.modal().cancel then kit.modal().cancel() end
  elseif screen == 'pick' then screen = (pick.link and cur) and 'item' or 'main'
  elseif screen ~= 'main' then screen = 'main'; cur = nil end
end

function on_input(c, ev)
  ERR = nil
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    if ev.type == 'pointer' and ev.phase == 'up' then
      local g = ev.gesture
      if not kit.modal() and (g == 'swipe_left' or g == 'swipe_right') then step(g == 'swipe_left' and 1 or -1)
      elseif g == nil or g == 'tap' then tap(ev.x or 0, ev.y or 0) end
    elseif ev.type == 'key' and kit.key_accepted(ev) then
      if ev.key == 'back' then go_back()
      elseif not kit.modal() then
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
    refresh_reader()
    month = month_of(today())
  end)
  if not ok then ERR = tostring(e) end
end
function on_tick() end

if rawget(_G, '__TEST') then
  __TEST.api = { T = T, books = function() return items end, cfg = cfg, screen = function() return screen end,
                 cur = function() return cur end, rb = function() return rb end, status = function() return status end,
                 month = function() return month end }
end
