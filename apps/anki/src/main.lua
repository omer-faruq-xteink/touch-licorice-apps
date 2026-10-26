-- Anki flashcards for XTOS Licorice, API 2.9 (uses tools/gamekit).
--
-- Decks: the built-in English deck (this package's data section: en_info.txt, en_c000.txt ...),
-- "My cards", and every deck converted on a computer with apkg2cards.py and copied into
-- XTApps/anki/files/ (<prefix>_info.txt, <prefix>_c000.txt ...); a plain "front<TAB>back" .tsv
-- list copied there is a deck too. A card file line is "id<TAB>front<TAB>back" ("\n" for a line
-- break); every card file of a deck holds `per` cards, so a card is known by its place:
-- shard s, line l.
--
-- The device reads whole files only and has about 1 MB for Lua, so nothing big is held: a study
-- session reads the card file of the card it shows, and the progress of the cards of one card
-- file lives in a small file of its own (<key>_p000.txt: "line due interval ease reps lapses"),
-- so a rating rewrites a few kilobytes. <key>_st.txt keeps the next new card, today's new-card
-- count and the earliest due time of every progress file, so only the files with cards due are
-- read. Own cards: <key>_own.txt and <key>_pown.txt (by id); deleted cards: <key>_del.txt.
--
-- Scheduling is the KOReader Anki Viewer's (SM-2 like): Again / Hard / Good / Easy, an ease
-- factor from 2.5 (at least 1.3), learning steps of minutes for new and lapsed cards (they come
-- back in the same session), then intervals in days.

local W, H = kit.W, kit.H
local BTN_Y, BTN_H = 704, 72
local TOP = 100
local LEARN_S = 20 * 60                -- due again within this: shown again in this session
local MAX_REVIEWS = 300                -- reviews taken into one session
local MAX_TSV = 300000                 -- a plain .tsv list is read whole
local NEW_CHOICES = { 5, 10, 15, 20, 30, 50 }
local ROW_H, ROWS = 84, 7

local settings = { new_per_day = 15 }
local decks = {}                       -- { key, name, source = 'package' | 'storage' | 'tsv' | 'own', file, cards, per, shards }
local screen = 'decks'                 -- decks | study | done
local deck, st = nil, nil              -- the open deck and its state
local own, own_prog = {}, {}           -- own cards { id, f, b } and their progress by id
local dels = {}                        -- "s:l" -> true
local queue = {}                       -- { s, l, new } (s = 'own', l = id for own cards)
local shown, scroll, max_scroll = false, 0, 0
local last = nil                       -- the last rating, for Undo
local page = 0
local suppress_up = false
local long_done = false
local msg, ERR = nil, nil
local session = { done = 0 }

------------------------------------------------------------------ files

local function sread(name)
  local ok, s = pcall(function() return ctx.storage:read(name) end)
  return (ok and type(s) == 'string') and s or nil
end
local function swrite(name, s) pcall(function() ctx.storage:write(name, s) end) end
local function sremove(name) pcall(function() ctx.storage:remove(name) end) end
local function slist()
  local ok, t = pcall(function() return ctx.storage:list() end)
  return (ok and type(t) == 'table') and t or {}
end

-- a data-section file as one string (the package reader goes line by line)
local function pread(name)
  local P = ctx.package
  if not P then return nil end
  local ok, r = pcall(function() return P:open_text(name, { max_bytes = 2000000, max_line_bytes = 16384 }) end)
  if not ok or r == nil or type(r) == 'string' then return nil end
  local parts = {}
  while true do
    local okl, line = pcall(function() return r:read_line() end)
    if not okl or line == nil then break end
    parts[#parts + 1] = line
  end
  pcall(function() r:close() end)
  if #parts == 0 then return nil end
  return table.concat(parts, '\n') .. '\n'
end

local function kv(s) return kit.kv(s) end
local function unesc(s)
  return (s:gsub('\\(.)', function(ch) if ch == 'n' then return '\n' elseif ch == 't' then return '\t' end return ch end))
end
local function lines(text)
  if text:sub(-1) ~= '\n' then text = text .. '\n' end
  return text:gmatch('([^\n]*)\n')
end

------------------------------------------------------------------ time

local function now_sec()
  local ok, t = pcall(function() return ctx.clock:now() end)
  if ok and type(t) == 'table' and tonumber(t.epoch_sec) then return math.floor(tonumber(t.epoch_sec)) end
  local okm, ms = pcall(function() return ctx.clock:millis() end)
  return (okm and tonumber(ms)) and math.floor(tonumber(ms) / 1000) or 0
end

-- today's number in local time: the offset from the wall clock, rounded to a quarter hour
local function today()
  local ok, t = pcall(function() return ctx.clock:now() end)
  local e = now_sec()
  if ok and type(t) == 'table' and tonumber(t.hour) then
    local wall = tonumber(t.hour) * 3600 + (tonumber(t.minute) or 0) * 60 + (tonumber(t.second) or 0)
    local off = (wall - e % 86400) % 86400
    if off > 14 * 3600 then off = off - 86400 end
    off = math.floor(off / 900 + 0.5) * 900
    return (e + off) // 86400
  end
  return e // 86400
end

------------------------------------------------------------------ decks

local function load_settings()
  local t = kv(sread('settings.txt'))
  settings.new_per_day = tonumber(t.new_per_day) or 15
end
local function save_settings() swrite('settings.txt', 'new_per_day=' .. settings.new_per_day) end

local function discover()
  decks = {}
  local info = pread('en_info.txt')
  if info then
    local t = kv(info)
    decks[#decks + 1] = { key = 'en', name = t.name or 'English', source = 'package',
                          cards = tonumber(t.cards) or 0, per = tonumber(t.per) or 200, shards = tonumber(t.shards) or 0 }
  end
  decks[#decks + 1] = { key = 'my', name = 'My cards', source = 'own', cards = 0, per = 1, shards = 0 }
  local names = slist()
  table.sort(names)
  for _k, n in ipairs(names) do
    local pre = n:match('^([%w]+)_info%.txt$')
    if pre and pre ~= 'en' and pre ~= 'my' then
      local t = kv(sread(n))
      decks[#decks + 1] = { key = pre, name = t.name or pre, source = 'storage',
                            cards = tonumber(t.cards) or 0, per = tonumber(t.per) or 100, shards = tonumber(t.shards) or 0 }
    end
    local tsv = n:match('^([%w%-]+)%.tsv$')
    if tsv then
      local text, count = sread(n) or '', 0
      for l in lines(text) do if l ~= '' and l:sub(1, 1) ~= '#' then count = count + 1 end end
      decks[#decks + 1] = { key = 't' .. tsv:gsub('%-', ''), name = tsv, source = 'tsv', file = n, cards = count, per = 1000000, shards = 1 }
    end
  end
end

-- the cards of shard s: { { id, f, b } ... } (one shard cached)
local cache = { key = nil, rows = nil }
local function shard(d, s)
  local ck = d.key .. ':' .. s
  if cache.key == ck then return cache.rows end
  cache.key, cache.rows = nil, nil
  local text
  if d.source == 'package' then text = pread(string.format('%s_c%03d.txt', d.key, s))
  elseif d.source == 'storage' then text = sread(string.format('%s_c%03d.txt', d.key, s))
  elseif d.source == 'tsv' then
    text = sread(d.file)
    if text and #text > MAX_TSV then msg = d.file .. ' is too big: convert it with apkg2cards.py.'; text = nil end
  end
  local rows = {}
  for line in lines(text or '') do
    if d.source == 'tsv' then
      local f, b = line:match('^([^\t]*)\t?(.*)$')
      if f:sub(1, 1) == '#' then f = '' end
      rows[#rows + 1] = { id = 'L' .. (#rows + 1), f = unesc(f), b = unesc(b) }
    else
      local id, f, b = line:match('^([^\t]*)\t([^\t]*)\t?(.*)$')
      rows[#rows + 1] = { id = id or '', f = f and unesc(f) or '', b = b and unesc(b) or '' }
    end
  end
  cache.key, cache.rows = ck, rows
  if d.source == 'tsv' then d.cards = #rows end
  return rows
end

local function slots(d)
  if d.source == 'tsv' then return #shard(d, 0) end
  if d.source == 'own' then return 0 end
  return d.shards * d.per
end

------------------------------------------------------------------ progress

local function pname(d, s) return s == 'own' and (d.key .. '_pown.txt') or string.format('%s_p%03d.txt', d.key, s) end

local function load_prog(d, s)
  local t = {}
  for line in lines(sread(pname(d, s)) or '') do
    local k, due, ivl, ease, reps, lapses = line:match('^(%S+) (%-?%d+) ([%d%.]+) ([%d%.]+) (%d+) (%d+)$')
    if k then
      if s ~= 'own' then k = tonumber(k) end
      t[k] = { due = tonumber(due), ivl = tonumber(ivl), ease = tonumber(ease), reps = tonumber(reps), lapses = tonumber(lapses) }
    end
  end
  return t
end

local function fmt(x) return (string.format('%.2f', x):gsub('%.?0+$', '')) end

local function save_prog(d, s, t)
  local out, min = {}, nil
  for k, r in pairs(t) do
    out[#out + 1] = k .. ' ' .. r.due .. ' ' .. fmt(r.ivl) .. ' ' .. fmt(r.ease) .. ' ' .. r.reps .. ' ' .. r.lapses
    if not min or r.due < min then min = r.due end
  end
  if #out == 0 then sremove(pname(d, s)) else swrite(pname(d, s), table.concat(out, '\n') .. '\n') end
  st.mins[s] = min
end

local function load_state(d)
  local t = kv(sread(d.key .. '_st.txt'))
  local s = { next = tonumber(t.next) or 0, day = tonumber(t.day) or 0, new = tonumber(t.new) or 0, mins = {} }
  for k, m in (t.mins or ''):gmatch('([%w]+):(%-?%d+)') do s.mins[k == 'own' and 'own' or tonumber(k)] = tonumber(m) end
  local td = today()
  if s.day ~= td then s.day, s.new = td, 0 end
  return s
end

local function save_state(d)
  local m = {}
  for k, v in pairs(st.mins) do m[#m + 1] = k .. ':' .. v end
  table.sort(m)
  swrite(d.key .. '_st.txt', 'next=' .. st.next .. '\nday=' .. st.day .. '\nnew=' .. st.new .. '\nmins=' .. table.concat(m, ','))
end

local function load_own(d)
  own = {}
  for line in lines(sread(d.key .. '_own.txt') or '') do
    local id, f, b = line:match('^([^\t]+)\t([^\t]*)\t?(.*)$')
    if id then own[#own + 1] = { id = id, f = unesc(f), b = unesc(b) } end
  end
  own_prog = load_prog(d, 'own')
end

local function esc(s) return (s:gsub('\\', '\\\\'):gsub('\t', ' '):gsub('\r', ''):gsub('\n', '\\n')) end
local function save_own(d)
  local out = {}
  for _k, c in ipairs(own) do out[#out + 1] = c.id .. '\t' .. esc(c.f) .. '\t' .. esc(c.b) end
  if #out == 0 then sremove(d.key .. '_own.txt') else swrite(d.key .. '_own.txt', table.concat(out, '\n') .. '\n') end
end

local function load_dels(d)
  dels = {}
  for line in lines(sread(d.key .. '_del.txt') or '') do if line ~= '' then dels[line] = true end end
end
local function save_dels(d)
  local out = {}
  for k in pairs(dels) do out[#out + 1] = k end
  table.sort(out)
  if #out == 0 then sremove(d.key .. '_del.txt') else swrite(d.key .. '_del.txt', table.concat(out, '\n') .. '\n') end
end

------------------------------------------------------------------ scheduling

-- the KOReader Anki Viewer's rules; r = 1 Again, 2 Hard, 3 Good, 4 Easy
local function schedule(rec, r, now)
  local ease, ivl, reps, lapses = rec.ease or 2.5, rec.ivl or 0, rec.reps or 0, rec.lapses or 0
  local due
  if ivl == 0 and reps == 0 then
    if r == 1 then ease = math.max(1.3, ease - 0.2); due = now + 60
    elseif r == 2 then ease = math.max(1.3, ease - 0.15); due = now + 6 * 60
    elseif r == 3 then due = now + 10 * 60
    else ease = ease + 0.15; ivl = 4; due = now + ivl * 86400 end
  else
    if r == 1 then
      lapses = lapses + 1; ease = math.max(1.3, ease - 0.2); ivl = 0; due = now + 10 * 60
    elseif r == 2 then
      ease = math.max(1.3, ease - 0.15); ivl = math.max(ivl, 1) * 1.2; due = now + math.floor(ivl * 86400)
    elseif r == 3 then
      ivl = ivl == 0 and 1 or ivl * ease; due = now + math.floor(ivl * 86400)
    else
      ease = ease + 0.15; ivl = ivl == 0 and 3 or ivl * ease * 1.3; due = now + math.floor(ivl * 86400)
    end
  end
  return { due = due, ivl = ivl, ease = ease, reps = reps + 1, lapses = lapses }
end

local function span(sec)
  if sec < 3600 then return math.max(1, sec // 60) .. 'm' end
  local d = sec / 86400
  if d < 1 then return (sec // 3600) .. 'h' end
  if d < 31 then return math.floor(d + 0.5) .. 'd' end
  if d < 365 then return math.floor(d / 30 + 0.5) .. 'mo' end
  return fmt(math.floor(d / 36.5 + 0.5) / 10) .. 'y'
end

------------------------------------------------------------------ the queue

local function card_of(e)
  if e.s == 'own' then
    for _k, c in ipairs(own) do if c.id == e.l then return c end end
    return nil
  end
  local rows = shard(deck, e.s)
  local c = rows[e.l + 1]
  if c and c.f ~= '' then return c end
  return nil
end

local function rec_of(e)
  if e.s == 'own' then return own_prog[e.l] end
  return load_prog(deck, e.s)[e.l]
end

-- cards due now (reviews and learning), then new cards up to today's limit
local function build_queue()
  queue = {}
  local now = now_sec()
  local due = {}
  for s, m in pairs(st.mins) do
    if m <= now then
      local t = s == 'own' and own_prog or load_prog(deck, s)
      for k, r in pairs(t) do if r.due <= now then due[#due + 1] = { s = s, l = k, due = r.due } end end
    end
  end
  table.sort(due, function(a, b) return a.due < b.due end)
  for k = 1, math.min(#due, MAX_REVIEWS) do queue[#queue + 1] = due[k] end
  -- own cards not studied yet first, then the deck's next cards
  local want = settings.new_per_day - st.new
  for _k, c in ipairs(own) do
    if not own_prog[c.id] then queue[#queue + 1] = { s = 'own', l = c.id, new = true }; want = want - 1 end
  end
  if deck.source ~= 'own' then
    local k, total = st.next, slots(deck)
    while want > 0 and k < total do
      local s, l = k // deck.per, k % deck.per
      if not dels[s .. ':' .. l] then
        local rows = shard(deck, s)
        if #rows == 0 or l >= #rows then break end
        if rows[l + 1].f ~= '' then queue[#queue + 1] = { s = s, l = l, new = true, k = k }; want = want - 1 end
      end
      k = k + 1
    end
  end
end

local function counts()
  local n, r = 0, 0
  for _k, e in ipairs(queue) do if e.new then n = n + 1 else r = r + 1 end end
  return n, r
end

------------------------------------------------------------------ opening a deck

local function open_deck(d)
  deck = d
  st = load_state(d)
  load_own(d); load_dels(d)
  build_queue()
  screen, shown, scroll, last, session.done, msg = 'study', false, 0, nil, 0, nil
  if #queue == 0 then screen = 'done' end
  save_state(d)
end

-- due and new counts for the deck list, without opening the deck
local function summary(d)
  local s = load_state(d)
  local now, due = now_sec(), 0
  for k, m in pairs(s.mins) do
    if m <= now then
      local t = k == 'own' and load_prog(d, 'own') or load_prog(d, k)
      for _j, r in pairs(t) do if r.due <= now then due = due + 1 end end
    end
  end
  local left = d.source == 'own' and 0 or math.max(0, d.cards - s.next)
  return due, math.min(math.max(0, settings.new_per_day - s.new), left)
end

-- the deck list's numbers, worked out when the list is shown, not on every redraw
local function refresh_summaries()
  for _k, d in ipairs(decks) do
    d.due, d.new = summary(d)
    if d.source == 'own' then
      d.cards = 0
      for l in lines(sread('my_own.txt') or '') do if l ~= '' then d.cards = d.cards + 1 end end
    end
  end
end
local function show_decks()
  screen, deck = 'decks', nil
  refresh_summaries()
end

------------------------------------------------------------------ actions

local function rate(r)
  local e = queue[1]
  if not e then return end
  local now = now_sec()
  local before = rec_of(e)
  local rec = schedule(before or {}, r, now)
  last = { e = e, before = before, next = st.next, new = st.new, queue = { table.unpack(queue) } }
  if e.s == 'own' then
    own_prog[e.l] = rec
    save_prog(deck, 'own', own_prog)
  else
    local t = load_prog(deck, e.s)
    t[e.l] = rec
    save_prog(deck, e.s, t)
  end
  if e.new then
    st.new = st.new + 1
    if e.k then st.next = math.max(st.next, e.k + 1) end
  end
  save_state(deck)
  table.remove(queue, 1)
  if rec.due < now + LEARN_S then table.insert(queue, math.min(#queue + 1, 4), { s = e.s, l = e.l }) end
  session.done = session.done + 1
  shown, scroll, msg = false, 0, nil
  kit.moved()
  if #queue == 0 then screen = 'done' end
end

local function undo()
  if not last then msg = 'Nothing to undo.'; return end
  local e = last.e
  if e.s == 'own' then
    own_prog[e.l] = last.before
    save_prog(deck, 'own', own_prog)
  else
    local t = load_prog(deck, e.s)
    t[e.l] = last.before
    save_prog(deck, e.s, t)
  end
  st.next, st.new, queue = last.next, last.new, last.queue
  save_state(deck)
  session.done = math.max(0, session.done - 1)
  last, shown, scroll, screen, msg = nil, false, 0, 'study', nil
end

local function delete_current()
  local e = queue[1]
  if not e then return end
  if e.s == 'own' then
    for k, c in ipairs(own) do if c.id == e.l then table.remove(own, k); break end end
    save_own(deck)
    own_prog[e.l] = nil
    save_prog(deck, 'own', own_prog)
  else
    dels[e.s .. ':' .. e.l] = true
    save_dels(deck)
    local t = load_prog(deck, e.s)
    if t[e.l] then t[e.l] = nil; save_prog(deck, e.s, t) end
    if e.new and e.k then st.next = math.max(st.next, e.k + 1) end
  end
  save_state(deck)
  for k = #queue, 1, -1 do
    if queue[k].s == e.s and queue[k].l == e.l then table.remove(queue, k) end
  end
  last, shown, scroll, msg = nil, false, 0, 'Card deleted.'
  if #queue == 0 then screen = 'done' end
end

local function add_card(d)
  local function ask(title, value, fn)
    ctx.input:text({ title = title, value = value or '' }, function(c, s) pcall(fn, s) ; kit.refresh() end)
  end
  ask('New card: front', '', function(front)
    if not front or front == '' then return end
    ask('New card: back', '', function(back)
      if not back or back == '' then return end
      if deck ~= d then deck = d; st = load_state(d); load_own(d); load_dels(d) end
      local id = 'o' .. now_sec() .. math.random(10, 99)
      own[#own + 1] = { id = id, f = front, b = back }
      save_own(d)
      if screen == 'study' or screen == 'done' then
        queue[#queue + 1] = { s = 'own', l = id, new = true }
        if screen == 'done' then screen = 'study'; shown = false end
      end
      msg = 'Card added.'
      if screen == 'decks' then refresh_summaries() end
    end)
  end)
end

------------------------------------------------------------------ drawing

-- the card as rows of text: { text, font name, centred } and a divider (false) before the back
local function card_rows(c, with_back)
  local rows, maxw = {}, W - 40
  local first = true
  for para in (c.f .. '\n'):gmatch('([^\n]*)\n') do
    local fname = first and 'large' or 'medium'
    for _k, l in ipairs(kit.wrap(para, fname, maxw)) do rows[#rows + 1] = { l, fname, true } end
    first = false
  end
  if with_back then
    rows[#rows + 1] = false
    for para in (c.b .. '\n'):gmatch('([^\n]*)\n') do
      for _k, l in ipairs(kit.wrap(para, 'medium', maxw)) do rows[#rows + 1] = { l, 'medium' } end
    end
  end
  return rows
end

local function row_h(r) return r and (kit.line_h(r[2]) + 4) or 22 end

local function draw_study(gg)
  local e = queue[1]
  local c = e and card_of(e)
  if not c then
    -- a card that went missing (its file changed): skip it
    table.remove(queue, 1)
    if #queue == 0 then screen = 'done' end
    return
  end
  local rows = card_rows(c, shown)
  local area = BTN_Y - 16 - TOP
  local total = 0
  for _k, r in ipairs(rows) do total = total + row_h(r) end
  max_scroll = 0
  -- skip whole rows from the top while scrolled
  local first, skipped = 1, 0
  while first <= #rows and skipped < scroll and total - skipped > area do
    skipped = skipped + row_h(rows[first]); first = first + 1
  end
  local y = TOP + 8
  for k = first, #rows do
    local r = rows[k]
    if y + row_h(r) > TOP + area then max_scroll = scroll + 1; break end
    if r then
      local f = kit.font(r[2])
      local x = r[3] and (W - kit.width(f, r[1])) // 2 or 20
      gg:text(x, y, r[1], { font = f })
    else
      gg:line(20, y + 10, W - 20, y + 10)
    end
    y = y + row_h(r)
  end
  if max_scroll > scroll then gg:text(W - 120, BTN_Y - 30, 'more: swipe up', { font = kit.font('small') }) end
  if scroll > 0 then gg:text(W - 120, TOP + 2, 'swipe down: top', { font = kit.font('small') }) end
  if not shown then
    kit.button(gg, 12, BTN_Y, W - 24, BTN_H, 'Show answer', { font = 'large' })
  else
    local now = now_sec()
    local rec = rec_of(e) or {}
    local bw = math.floor((W - 24 - 3 * 8) / 4)
    for k, label in ipairs({ 'Again', 'Hard', 'Good', 'Easy' }) do
      local x = 12 + (k - 1) * (bw + 8)
      gg:rect(x, BTN_Y, bw, BTN_H, { line_width = 2 })
      local f, s = kit.font('medium'), kit.font('small')
      gg:text(x + (bw - kit.width(f, label)) // 2, BTN_Y + 10, label, { font = f })
      local t = span(schedule(rec, k, now).due - now)
      gg:text(x + (bw - kit.width(s, t)) // 2, BTN_Y + 40, t, { font = s })
    end
  end
end

local function draw_decks(gg)
  local first = page * ROWS + 1
  for k = first, math.min(#decks, first + ROWS - 1) do
    local d = decks[k]
    local y = TOP + (k - first) * ROW_H
    gg:rect(12, y + 4, W - 24, ROW_H - 8, { line_width = 2 })
    gg:text(24, y + 12, kit.short(d.name, 34), { font = kit.font('medium') })
    local info
    if d.source == 'own' then
      info = d.cards .. ' cards    due ' .. (d.due or 0) .. (d.cards == 0 and '    long-press: add a card' or '')
    else
      info = d.cards .. ' cards    due ' .. (d.due or 0) .. '    new ' .. (d.new or 0)
    end
    gg:text(24, y + 44, kit.short(info, 44), { font = kit.font('small') })
  end
end

local DECK_BUTTONS = {
  { function() return 'New/day ' .. settings.new_per_day end, function()
      local k = 1
      for i, v in ipairs(NEW_CHOICES) do if v == settings.new_per_day then k = i end end
      settings.new_per_day = NEW_CHOICES[k % #NEW_CHOICES + 1]
      save_settings()
      refresh_summaries()
    end },
  { function() return 'Help' end, function()
      kit.show({ title = 'Anki',
                 lines = { 'Tap a deck to study it; long-press it to add a card.',
                           'More decks: convert an Anki .apkg (e.g. from ankiweb.net/shared/decks) on a computer with apkg2cards.py and copy the files into XTApps/anki/files/ in USB mode. A "front<TAB>back" .tsv list there works too.',
                           'While studying, Menu has Undo, Add card and Delete card.' },
                 rows = { { { 'Close', kit.close } } }, cancel = kit.close })
    end },
  { function() return 'Page ' .. (page + 1) .. '/' .. math.max(1, math.ceil(#decks / ROWS)) end, function()
      page = (page + 1) % math.max(1, math.ceil(#decks / ROWS))
    end },
}

local function menu()
  kit.show({ title = deck.name, lines = { session.done .. ' cards studied in this session.' },
             rows = { { { 'Undo', function() kit.close(); undo() end, last ~= nil },
                        { 'Add card', function() kit.close(); add_card(deck) end } },
                      { { 'Delete card', function()
                            kit.show({ title = 'Delete this card?', lines = { 'It will not come back in this deck.' },
                                       rows = { { { 'Delete', function() kit.close(); delete_current() end }, { 'Cancel', kit.close } } },
                                       cancel = kit.close })
                          end, screen == 'study' },
                        { 'Decks', function() kit.close(); show_decks() end } } },
             cancel = kit.close })
end

local function deck_buttons_rect(k)
  local bw = math.floor((W - 24 - 2 * 8) / 3)
  return 12 + (k - 1) * (bw + 8), BTN_Y, bw, BTN_H
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    gg:clear(0)
    if screen == 'decks' then
      gg:text(12, 12, 'Anki', { font = kit.font('large') })
      gg:text(12, 52, 'Decks    new cards a day: ' .. settings.new_per_day, { font = kit.font('small') })
    else
      gg:text(12, 12, kit.short(deck.name, 26), { font = kit.font('large') })
      local n, r = counts()
      gg:text(12, 52, 'New ' .. n .. '    Review ' .. r .. '    Done ' .. session.done, { font = kit.font('small') })
      kit.button(gg, W - 112, 10, 100, 44, 'Menu', { font = 'medium' })
    end
    gg:line(0, 90, W, 90)
    if kit.modal() then kit.draw_modal(gg); return end
    if screen == 'decks' then
      draw_decks(gg)
      for k, b in ipairs(DECK_BUTTONS) do
        local x, y, bw, bh = deck_buttons_rect(k)
        kit.button(gg, x, y, bw, bh, b[1](), { font = 'small' })
      end
    elseif screen == 'study' then
      draw_study(gg)
    else
      gg:text(24, TOP + 40, 'Done for now!', { font = kit.font('large') })
      local lines_ = { session.done .. ' cards studied in this session.',
                       'New cards come back tomorrow; reviews when they are due.',
                       'Menu: Undo, Add card, back to the decks.' }
      for k, s in ipairs(lines_) do gg:text(24, TOP + 90 + (k - 1) * 30, s, { font = kit.font('small') }) end
      kit.button(gg, 12, BTN_Y, W - 24, BTN_H, 'Decks', { font = 'large' })
    end
    if msg then gg:text(12, BTN_Y - 30, kit.short(msg, 34), { font = kit.font('small') }) end
    if ERR then gg:text(12, H - 24, kit.short('ERR ' .. ERR, 48), { font = kit.font('small') }) end
  end)
  if not ok then pcall(function() gg:text(8, H - 60, kit.short('draw ERR ' .. tostring(e), 46)) end) end
end

local function in_rect(x, y, rx, ry, rw, rh) return x >= rx and x < rx + rw and y >= ry and y < ry + rh end

local function deck_at(x, y)
  if y < TOP or y >= TOP + ROWS * ROW_H then return nil end
  return decks[page * ROWS + (y - TOP) // ROW_H + 1]
end

local function deck_menu(d)
  kit.show({ title = d.name, lines = {},
             rows = { { { 'Study', function() kit.close(); open_deck(d) end },
                        { 'Add card', function() kit.close(); add_card(d) end } },
                      { { 'Close', kit.close } } },
             cancel = kit.close })
end

local function tap(x, y)
  if kit.tap_modal(x, y) then return end
  if screen == 'decks' then
    for k, b in ipairs(DECK_BUTTONS) do
      if in_rect(x, y, deck_buttons_rect(k)) then b[2](); return end
    end
    local d = deck_at(x, y)
    if d then
      if d.source == 'own' and not sread('my_own.txt') then deck_menu(d) else open_deck(d) end
    end
    return
  end
  if in_rect(x, y, W - 112, 10, 100, 44) then menu(); return end
  if screen == 'done' then
    if y >= BTN_Y then show_decks() end
    return
  end
  if not shown then
    if y >= TOP then shown, scroll = true, 0 end
    return
  end
  if y >= BTN_Y then
    local bw = math.floor((W - 24 - 3 * 8) / 4)
    local k = (x - 12) // (bw + 8) + 1
    if k >= 1 and k <= 4 then rate(k) end
  end
end

function on_input(c, ev)
  ERR = nil
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    if ev.type == 'pointer' then
      local x, y = ev.x or 0, ev.y or 0
      if ev.phase == 'down' then long_done = false end
      if (ev.gesture == 'long' or ev.phase == 'hold') and not kit.modal() then
        if not long_done and screen == 'decks' then
          local d = deck_at(x, y)
          if d then deck_menu(d) end
        end
        long_done = true
        suppress_up = ev.phase ~= 'up'
        if ev.phase == 'up' then long_done = false end
        return
      end
      if ev.phase ~= 'up' then return end
      long_done = false
      if suppress_up then suppress_up = false; return end
      if ev.gesture == 'swipe_up' and screen == 'study' and not kit.modal() then
        if max_scroll > scroll then scroll = scroll + 200 end
        return
      elseif ev.gesture == 'swipe_down' and screen == 'study' and not kit.modal() then
        scroll = 0
        return
      end
      tap(x, y)
    elseif ev.type == 'key' and kit.key_accepted(ev) then
      if kit.modal() then
        if ev.key == 'back' and kit.modal().cancel then kit.modal().cancel() end
      elseif screen == 'study' then
        if ev.key == 'down' or ev.key == 'right' then
          if not shown then shown = true elseif max_scroll > scroll then scroll = scroll + 200 end
        elseif ev.key == 'up' or ev.key == 'left' then scroll = 0 end
      elseif screen == 'decks' and (ev.key == 'down' or ev.key == 'right') then
        page = (page + 1) % math.max(1, math.ceil(#decks / ROWS))
      end
    end
  end)
  if not ok then ERR = tostring(e) end
  kit.refresh()
  return true
end

function on_load(c)
  math.randomseed(kit.now_ms() or 1)
  local ok, e = pcall(function() load_settings(); discover(); refresh_summaries() end)
  if not ok then ERR = tostring(e) end
end
function on_leave() end

if rawget(_G, '__TEST') then
  __TEST.api = {
    screen = function() return screen end, decks = function() return decks end, deck = function() return deck end,
    queue = function() return queue end, state = function() return st end, shown = function() return shown end,
    schedule = schedule, span = span, open = function(k) for _i, d in ipairs(decks) do if d.key == k then open_deck(d) end end end,
    card = function() return queue[1] and card_of(queue[1]) end, today = today, own = function() return own end,
  }
end
