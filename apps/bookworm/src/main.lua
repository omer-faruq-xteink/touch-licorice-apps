-- Bookworm for XTOS Licorice, API 2.9 (uses tools/gamekit): a pet that lives on your reading.
-- It reads the reader's statistics (ctx.reader, the `reader` permission): the books, today's and
-- each day's reading time, the streak; nothing is sent anywhere. pet.lua holds its life (stages,
-- hunger, character, awards, the family line), lines.lua what it says, art.lua its pictures; the
-- sleep screen (lockscreen.lua) shows it asleep and dreaming of your book.
--
-- Home: the bookworm on its book, what it says, today's reading and how far to its next stage.
-- Tap it to pet it. Diary: the last two weeks; Awards; Family: the bookworms before it; More:
-- rename it, make it the sleep screen, how it works.

local P = require('pet')
local L = require('lines')
local A = require('art')

local W, H = kit.W, kit.H
local BTN_Y, BTN_H = 704, 60
local BOOK_Y = 330

local screen = 'home'
local data, view = nil, nil
local line = ''
local mood_override = nil
local phase = 0
local msg, ERR = nil, nil

local function st() return ctx.state.bw end

------------------------------------------------------------------ the state

local function seed()
  local s = st()
  return (data.today or 0) + (s.pets or 0) * 7 + #s.events
end

local function fields()
  local b = view.book
  return { title = b and L.short(b.title, 28) or nil, pct = b and b.percent, page = b and b.page,
           name = st().name, min = (view.today_sec or 0) // 60, trait = view.trait_name }
end

-- what it says now: news first (hatched, grew, a book finished, a new generation), then by mood
local function choose_line()
  local s, f = st(), fields()
  local ev = s.events[#s.events]
  if ev and not ev.told then
    ev.told = true
    local list = ({ hatched = L.HATCHED, grew = L.GREW, finished = L.FINISHED, moth = L.MOTH })[ev.kind]
    if ev.kind == 'finished' and ev.taste and L.REVIEW[ev.taste] then list = L.REVIEW[ev.taste] end
    f.other = ev.kind == 'finished' and L.short(ev.text, 26) or ev.text
    if list then return L.pick(list, seed(), f) end
  end
  local h = view.hunger
  if h == 'egg' then return L.pick(L.EGG, seed(), f) end
  if h == 'full' then
    -- in turn: its taste, its character, an elder's grumble, the plain pleasure of eating
    local turn = seed() % 4
    if turn == 1 and view.taste then return L.pick(L.TASTE[view.taste], seed() // 4, f) end
    if turn == 2 and view.trait then return L.pick(L.TRAIT[view.trait], seed() // 4, f) end
    if turn == 3 and view.stage_key == 'elder' then return L.pick(L.ELDER, seed() // 4, f) end
  end
  local list = ({ full = L.FULL, peckish = L.PECKISH, hungry = L.HUNGRY, sulky = L.SULKY, hiding = L.HIDING })[h]
  return L.pick(list or L.FULL, seed(), f)
end

local function refresh_data()
  local now
  pcall(function() now = ctx.clock:now() end)
  data = P.read_data(ctx.reader, now)
  if not ctx.state.bw then ctx.state.bw = P.new(data) end
  view = P.update(st(), data)
  if #view.earned > 0 then
    for _, a in ipairs(P.AWARDS) do
      if a.id == view.earned[#view.earned] then msg = 'Award: ' .. a.name .. '. ' .. a.text end
    end
  end
  line = choose_line()
end

------------------------------------------------------------------ drawing

local function hm(sec)
  sec = math.max(0, sec or 0)
  local h, m = sec // 3600, (sec % 3600) // 60
  if h > 0 then return h .. ' h ' .. m .. ' min' end
  return m .. ' min'
end

local function header(gg, title, sub)
  gg:text(12, 12, title, { font = kit.font('large') })
  if sub then gg:text(12, 52, kit.short(sub, 50), { font = kit.font('small') }) end
  gg:line(0, 90, W, 90)
end

-- the speech bubble, its tail pointing up at tx (the bookworm's head)
local function bubble(gg, text, tx)
  local x, y, w, h = 24, 372, W - 48, 104
  tx = math.max(x + 30, math.min(x + w - 30, tx or 300))
  gg:rect(x, y, w, h, { fill = true, color = 0 })
  gg:rect(x, y, w, h, { line_width = 3, radius = 14 })
  gg:polygon({ tx, y - 18, tx - 14, y + 2, tx + 18, y + 2 }, { fill = true, color = 0 })
  gg:line(tx, y - 18, tx - 14, y + 1); gg:line(tx, y - 18, tx + 18, y + 1)
  for k, l in ipairs(kit.wrap(text, 'medium', w - 32)) do
    if k > 3 then break end
    gg:text(x + 16, y + 14 + (k - 1) * 28, l, { font = kit.font('medium') })
  end
end

-- the bookworm on its book; returns the x of its head (for the bubble's tail)
local function draw_pet(gg)
  local s = st()
  local mood = mood_override or view.hunger
  A.book(gg, 90, BOOK_Y, 300)
  if view.hunger == 'hiding' then A.hiding(gg, 240, BOOK_Y); return 260 end
  if not s.hatched then A.egg(gg, 240, BOOK_Y, phase % 2 == 1 and 4 or 0); return 240 end
  local r = A.BODY[view.stage_key][2]
  local hx = A.head_x(view.stage_key, 240)
  A.worm(gg, view.stage_key, hx, BOOK_Y - r * 4 // 3 - 2, mood, phase, view.taste)
  return hx
end

-- "a young bookworm", "an elder bookworm", "an egg"
local function a(s) return (s:match('^[aeiou]') and 'an ' or 'a ') .. s end

local function stats(gg)
  local small, medium = kit.font('small'), kit.font('medium')
  local y = 500
  if not view.reading then
    for k, l in ipairs(kit.wrap('The reader does not share its reading statistics with this app, so the bookworm cannot eat. ' ..
        'It needs firmware with reading data (API 2.1 or later).', 'small', W - 24)) do
      gg:text(12, y + (k - 1) * 22, l, { font = small })
    end
    return
  end
  gg:text(12, y, 'Today ' .. hm(view.today_sec) .. '    streak ' .. (view.streak or 0) .. ' day' .. ((view.streak == 1) and '' or 's'), { font = medium })
  local b = view.book
  if b then
    gg:text(12, y + 36, kit.short('Eating: ' .. (b.title or '?') .. ((b.percent and not b.finished) and ('  ' .. b.percent .. '%') or ''), 46), { font = small })
  end
  local s = st()
  local next_line
  if not s.hatched then next_line = 'Hatches after ' .. hm(view.to_next) .. ' more reading.'
  else next_line = 'Fed ' .. hm(view.food) .. '  ·  ' .. hm(view.to_next) .. ' to ' .. view.next_name end
  gg:text(12, y + 64, kit.short(next_line, 50), { font = small })
  -- how full it is: five dots
  local fill = ({ full = 5, peckish = 4, hungry = 3, sulky = 1, hiding = 0, egg = 5 })[view.hunger] or 3
  gg:text(12, y + 98, 'Full', { font = small })
  for i = 1, 5 do
    local cx = 80 + (i - 1) * 26
    if i <= fill then gg:circle(cx, y + 108, 8, { fill = true }) else gg:circle(cx, y + 108, 8, { line_width = 2 }) end
  end
  -- its character, beside
  if view.trait_name then gg:text(232, y + 98, kit.short(view.trait_name, 24), { font = small }) end
  if msg then
    for k, l in ipairs(kit.wrap(msg, 'small', W - 24)) do
      if k > 2 then break end
      gg:text(12, y + 134 + (k - 1) * 22, l, { font = small })
    end
  end
end

local HOME_BUTTONS = { 'Diary', 'Awards', 'Family', 'More' }
local function button_rect(k, n)
  local bw = math.floor((W - 24 - (n - 1) * 8) / n)
  return 12 + (k - 1) * (bw + 8), BTN_Y, bw, BTN_H
end

local function draw_home(gg)
  local s = st()
  local sub = (s.hatched and a(view.stage_name) or 'an egg') .. (view.taste_name and ('  ·  ' .. view.taste_name) or '')
  header(gg, s.name, sub)
  local small = kit.font('small')
  local gen = 'generation ' .. s.gen
  gg:text(W - 12 - kit.width(small, gen), 22, gen, { font = small })
  local hx = draw_pet(gg)
  bubble(gg, line, hx)
  stats(gg)
  for k, b in ipairs(HOME_BUTTONS) do
    local x, y, bw, bh = button_rect(k, 4)
    kit.button(gg, x, y, bw, bh, b)
  end
end

local function back_button(gg)
  local x, y, bw, bh = button_rect(1, 1)
  kit.button(gg, x, y, bw, bh, 'Back')
end

local function draw_diary(gg)
  header(gg, 'Diary', 'What ' .. st().name .. ' ate, the last two weeks')
  local small = kit.font('small')
  local y = 104
  local rows = P.diary(data)
  if #rows == 0 then gg:text(12, y, 'Nothing yet: open a book.', { font = kit.font('medium') }) end
  for _, r in ipairs(rows) do
    gg:text(12, y, P.label(r.day), { font = small })
    if r.sec > 0 then
      local w = math.max(4, math.min(140, r.sec * 140 // 7200))     -- two hours fill the bar
      gg:rect(140, y + 3, w, 14, { fill = true })
      gg:text(296, y, hm(r.sec), { font = small })
      if r.title then gg:text(140, y + 20, kit.short(r.title, 36), { font = small }) end
    else
      gg:text(140, y, '(a hungry day)', { font = small })
    end
    y = y + 42
    if y > BTN_Y - 30 then break end
  end
  back_button(gg)
end

local function draw_awards(gg)
  local s = st()
  local n = 0
  for _ in pairs(s.awards) do n = n + 1 end
  header(gg, 'Awards', n .. ' of ' .. #P.AWARDS)
  local small, medium = kit.font('small'), kit.font('medium')
  local y = 102
  for _, a in ipairs(P.AWARDS) do
    local got = s.awards[a.id]
    if got then gg:rect(12, y + 4, 20, 20, { fill = true }) else gg:rect(12, y + 4, 20, 20, { line_width = 2 }) end
    gg:text(44, y, a.name, { font = medium })
    gg:text(44, y + 26, (got and got > 0) and (a.text .. '  ' .. P.label(got)) or a.text, { font = small })
    y = y + 50
  end
  back_button(gg)
end

local function draw_family(gg)
  local s = st()
  header(gg, 'Family', 'The bookworms of this reader')
  local small, medium = kit.font('small'), kit.font('medium')
  local y = 104
  gg:text(12, y, s.name .. ', generation ' .. s.gen .. ' (now)', { font = medium })
  gg:text(12, y + 28, (s.hatched and a(view.stage_name) or 'still an egg') .. (s.born and (', laid ' .. P.label(s.born)) or ''), { font = small })
  y = y + 64
  if #s.lineage == 0 then
    for k, l in ipairs(kit.wrap('At ' .. P.COCOON_HOURS .. ' hours of reading a bookworm spins a cocoon and flies off as a moth, leaving an egg. ' ..
        'The ones before will be listed here.', 'small', W - 24)) do
      gg:text(12, y + (k - 1) * 22, l, { font = small })
    end
  end
  for i = #s.lineage, 1, -1 do
    local e = s.lineage[i]
    gg:text(12, y, e.name .. ', generation ' .. e.gen, { font = medium })
    gg:text(12, y + 28, kit.short(e.hours .. ' h, ' .. e.books .. ' books, ' .. (P.TRAITS[e.trait] or '') ..
      (e.left and ('; flew off ' .. P.label(e.left)) or ''), 52), { font = small })
    y = y + 60
    if y > BTN_Y - 60 then break end
  end
  back_button(gg)
end

local HELP = {
  'Bookworm eats what you read: every minute you spend in a book on this reader is food. Ten minutes hatch its egg.',
  'It grows as the hours add up: hatchling, young, grown (with glasses), elder (with a cap). At ' .. P.COCOON_HOURS ..
    ' hours it spins a cocoon, flies off as a moth and leaves an egg: the next generation.',
  'Days without reading make it peckish, hungry, then sulky; after a week it hides in a book until you read again.',
  'Its character comes from how you read: at night, in the morning, long sittings, little bites, many books or one.',
  'Make it the sleep screen (More) to see it asleep, dreaming of your book. It wakes once an hour.',
  'It only reads the reader\'s own reading statistics; nothing leaves the reader.',
}

local function draw_help(gg)
  header(gg, 'How it works', nil)
  local small = kit.font('small')
  local y = 104
  for _, p in ipairs(HELP) do
    for _, l in ipairs(kit.wrap(p, 'small', W - 24)) do gg:text(12, y, l, { font = small }); y = y + 22 end
    y = y + 10
  end
  back_button(gg)
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    gg:clear(0)
    if not view then return end
    if kit.modal() then header(gg, st().name, nil); kit.draw_modal(gg); return end
    if screen == 'diary' then draw_diary(gg)
    elseif screen == 'awards' then draw_awards(gg)
    elseif screen == 'family' then draw_family(gg)
    elseif screen == 'help' then draw_help(gg)
    else draw_home(gg) end
    if ERR then gg:text(12, H - 30, kit.short('ERR ' .. ERR, 48), { font = kit.font('small') }) end
  end)
  if not ok then pcall(function() gg:text(8, H - 60, kit.short('draw ERR ' .. tostring(e), 46)) end) end
end

------------------------------------------------------------------ input

local function is_lock()
  local ok, v = pcall(function() return ctx.lockscreen:is_default() end)
  return ok and v
end

local function rename()
  pcall(function()
    ctx.input:text({ title = 'Name your bookworm', text = st().name, max_bytes = 24 }, function(c, text)
      if text and text:match('%S') then st().name = text:gsub('^%s+', ''):gsub('%s+$', ''); line = 'Hello! I am ' .. st().name .. '.' end
      kit.refresh()
    end)
  end)
end

local function more()
  local lock = is_lock()
  kit.show({ title = 'More', rows = {
    { { 'Rename', function() kit.close(); rename() end } },
    { { lock and 'Stop sleep screen' or 'Use as sleep screen', function()
        kit.close()
        if lock then pcall(function() ctx.lockscreen:clear_default() end); msg = 'The sleep screen is back to your own.'
        else pcall(function() ctx.lockscreen:set_default() end) end
      end } },
    { { 'How it works', function() kit.close(); screen = 'help' end } },
    { { 'Close', kit.close } } }, cancel = kit.close })
end

local function tap(x, y)
  if kit.tap_modal(x, y) then return end
  if screen ~= 'home' then
    local bx, by, bw, bh = button_rect(1, 1)
    if y >= by and y < by + bh then screen = 'home' end
    return
  end
  for k = 1, 4 do
    local bx, by, bw, bh = button_rect(k, 4)
    if x >= bx and x < bx + bw and y >= by and y < by + bh then
      if k == 1 then screen = 'diary' elseif k == 2 then screen = 'awards' elseif k == 3 then screen = 'family' else more() end
      return
    end
  end
  -- the bookworm (or its egg): a pat
  if y >= 140 and y < BOOK_Y + 30 and x >= 60 and x < W - 40 then
    local s = st()
    s.pets = (s.pets or 0) + 1
    phase = phase + 1
    msg = nil
    if not s.hatched then line = L.pick(L.EGG, seed(), fields())
    elseif view.hunger == 'hiding' then line = L.pick(L.HIDING, seed(), fields())
    else mood_override = 'pet'; line = L.pick(L.PET, seed(), fields()) end
  end
end

-- Back closes a box or goes back to the home screen; on the home screen it is left to the host,
-- which asks whether to leave the app (section 4: only a `true` keeps it)
function on_input(c, ev)
  ERR = nil
  local handled = true
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    if ev.type == 'pointer' and ev.phase == 'up' then
      mood_override = nil
      tap(ev.x or 0, ev.y or 0)
    elseif ev.type == 'key' and ev.key == 'back' then
      if ev.phase ~= 'up' and ev.phase ~= nil then return end
      if kit.modal() then
        if kit.modal().cancel then kit.modal().cancel() end
      elseif screen ~= 'home' then screen = 'home'
      else handled = false end
    end
  end)
  if not ok then ERR = tostring(e) end
  kit.refresh()
  return handled
end

function on_load(c)
  local ok, e = pcall(refresh_data)
  if not ok then ERR = tostring(e) end
end

-- back from the sleep screen or another app: the reading may have moved on
function on_resume(c)
  local ok, e = pcall(refresh_data)
  if not ok then ERR = tostring(e) end
  kit.refresh()
end

if rawget(_G, '__TEST') then
  __TEST.api = { P = P, L = L, state = function() return ctx.state.bw end, view = function() return view end,
                 line = function() return line end, screen = function() return screen end, refresh = refresh_data }
end
