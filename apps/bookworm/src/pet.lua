-- The bookworm's life, with no screen: it lives on the reading the reader records (ctx.reader,
-- section 22), kept in ctx.state.bw (shared with the sleep screen, which saves it itself).
--
-- An egg is laid with the reading total of that moment; everything read after it is food. Ten
-- minutes of reading hatch it; it grows from hatchling to young, grown and elder as the hours add
-- up, and at 100 hours it spins a cocoon and flies off as a moth, leaving an egg: the next
-- generation, and an entry in the family line. Days without reading make it peckish, hungry,
-- sulky, and after a week it hides in a book until you read again. Its character comes from how
-- you read: at night or in the morning, long sittings or nibbles, many books or one, every day,
-- finishing books. Awards mark the milestones.
--
-- update(st, data) takes what read_data() gathered and returns what the screens show.

local T = require('taste')
local P = {}

P.HATCH_SEC = 10 * 60
P.STAGES = {                 -- the hours of food each stage starts at
  { key = 'egg', name = 'egg', hours = 0 },
  { key = 'hatchling', name = 'hatchling', hours = 0 },
  { key = 'young', name = 'young bookworm', hours = 2 },
  { key = 'grown', name = 'grown bookworm', hours = 10 },
  { key = 'elder', name = 'elder bookworm', hours = 40 },
}
P.COCOON_HOURS = 100
P.MAX_LINEAGE = 24

local NAMES = { 'Pip', 'Moss', 'Quill', 'Biscuit', 'Inky', 'Nib', 'Fern', 'Waffle', 'Pico', 'Bramble', 'Tuck',
                'Juniper', 'Dot', 'Margo', 'Comma', 'Pebble', 'Toffee', 'Wren', 'Orla', 'Basil', 'Clover', 'Mango',
                'Ziggy', 'Noodle', 'Hazel', 'Otto', 'Sprout', 'Twig', 'Lumen', 'Folio' }

-- the kinds of creature (the brood): one awake at a time, the others asleep in ctx.state.brood.
-- The bookworm comes first; the others' eggs come with an award (unlock) of any of them.
P.SPECIES = {
  { key = 'worm', name = 'Bookworm', kind = 'bookworm', names = NAMES,
    stages = { 'egg', 'hatchling', 'young bookworm', 'grown bookworm', 'elder bookworm' },
    leave = 'cocoon', left = 'flew off as a moth',
    ends = 'spins a cocoon and flies off as a moth' },
  { key = 'ink', name = 'Ink octopus', kind = 'ink octopus', unlock = 'hatch', hint = 'comes with the first hatching',
    card = 'Egg after the first hatch',
    names = { 'Inka', 'Squiggle', 'Blot', 'Sepia', 'Marlow', 'Octavia', 'Smudge', 'Ripple', 'Nautilus', 'Cuttle',
              'Splotch', 'Wisp', 'Coral', 'Doodle', 'Indigo', 'Quilla', 'Drift', 'Murex' },
    stages = { 'egg', 'hatchling', 'young ink octopus', 'grown ink octopus', 'elder ink octopus' },
    leave = 'the sea', left = 'swam off to sea',
    ends = 'slips off into the sea of stories' },
  { key = 'dragon', name = 'Shelf dragon', kind = 'shelf dragon', unlock = 'book1', hint = 'comes with the first finished book',
    card = 'Egg after a finished book',
    names = { 'Ember', 'Cinder', 'Gilda', 'Tinder', 'Flint', 'Scorch', 'Brass', 'Penny', 'Bellows', 'Rumble',
              'Sizzle', 'Ducat', 'Marigold', 'Sootling', 'Copper', 'Garnet', 'Nugget', 'Smolder' },
    stages = { 'egg', 'hatchling', 'young shelf dragon', 'grown shelf dragon', 'elder shelf dragon' },
    leave = 'its own hoard', left = 'flew off to its own hoard',
    ends = 'flies off to start a hoard of its own' },
}
P.SP = {}
for _, sp in ipairs(P.SPECIES) do P.SP[sp.key] = sp end
function P.species_of(st)
  local k = st and st.species or 'worm'
  return P.SP[k] and k or 'worm'
end

------------------------------------------------------------------ dates

-- days since 1970-01-01 <-> a civil date (Howard Hinnant's algorithms)
local function days_from_civil(y, m, d)
  y = m <= 2 and y - 1 or y
  local era = (y >= 0 and y or y - 399) // 400
  local yoe = y - era * 400
  local mp = (m + 9) % 12
  local doy = (153 * mp + 2) // 5 + d - 1
  local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
  return era * 146097 + doe - 719468
end
local function civil(z)
  z = z + 719468
  local era = (z >= 0 and z or z - 146096) // 146097
  local doe = z - era * 146097
  local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
  local y = yoe + era * 400
  local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
  local mp = (5 * doy + 2) // 153
  local d = doy - (153 * mp + 2) // 5 + 1
  local m = mp < 10 and mp + 3 or mp - 9
  return m <= 2 and y + 1 or y, m, d
end
P.days_from_civil, P.civil = days_from_civil, civil

function P.date(day)
  local y, m, d = civil(day)
  return string.format('%04d-%02d-%02d', y, m, d)
end
function P.day_of(date)
  local y, m, d = date:match('^(%d+)-(%d+)-(%d+)')
  return y and days_from_civil(tonumber(y), tonumber(m), tonumber(d)) or nil
end
local WEEKDAYS = { 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat' }
local MONTHS = { 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' }
function P.label(day)                -- 'Tue 3 Nov'
  local _y, m, d = civil(day)
  return WEEKDAYS[(day + 4) % 7 + 1] .. ' ' .. d .. ' ' .. MONTHS[m]
end

------------------------------------------------------------------ reading data

-- everything update() needs from the reader, read once; reader may be nil (no permission or an
-- older host) and every call may fail: what is missing stays empty
function P.read_data(reader, now)
  local data = { today = nil, hour = nil, total = 0, today_sec = 0, streak = 0, best_streak = 0, books = {},
                 current = nil, days = {}, book_days = {}, ok = false }
  if now and now.valid and now.year then
    data.today = days_from_civil(now.year, now.month, now.day)
    data.hour = now.hour
  end
  if not reader then return data end
  local ok, sum = pcall(function() return reader:summary() end)
  if ok and type(sum) == 'table' then
    data.ok = true
    data.total = tonumber(sum.total_sec) or 0
    data.today_sec = tonumber(sum.today_sec) or 0
    data.streak = tonumber(sum.streak_days) or 0
    data.best_streak = tonumber(sum.best_streak_days) or 0
  end
  local okb, books = pcall(function() return reader:books() end)
  if okb and type(books) == 'table' then data.books = books end
  local okc, cur = pcall(function() return reader:current() end)
  if okc and type(cur) == 'table' then data.current = cur end
  if data.today then
    local okd, days = pcall(function() return reader:days(P.date(data.today - 13), P.date(data.today)) end)
    if okd and type(days) == 'table' then data.days = days end
    local okk, rows = pcall(function() return reader:book_days(P.date(data.today - 13), P.date(data.today)) end)
    if okk and type(rows) == 'table' then data.book_days = rows end
  end
  return data
end

------------------------------------------------------------------ the bookworm

local function new_egg(st, data, random)
  random = random or math.random
  local names = P.SP[P.species_of(st)].names
  st.name = names[random(#names)]
  st.gen = (st.gen or 0) + 1
  st.born = data.today
  st.base = data.total
  st.hatched = false
  st.stage = 1
  st.gen_finished = 0
  st.pets = 0
  st.taste = {}                    -- seconds read per taste, this generation
end

-- a fresh state: the first egg, the books already finished not counting as food
function P.new(data, random, species)
  local st = { v = 1, species = species or 'worm', awards = {}, lineage = {}, seen = {}, finished = 0, tod = { night = 0, morning = 0, day = 0, evening = 0 },
               first_total = data.total, last_total = data.total, events = {}, tasted = {} }
  for _, b in ipairs(data.books) do if b.finished and b.id then st.seen[b.id] = true end end
  new_egg(st, data, random)
  return st
end

local function stage_of(st, food)
  if not st.hatched then return 1 end
  local h = food / 3600
  local s = 2
  for i = 3, #P.STAGES do if h >= P.STAGES[i].hours then s = i end end
  return s
end

local function bucket(hour)
  if hour >= 22 or hour < 5 then return 'night' end
  if hour < 11 then return 'morning' end
  if hour < 17 then return 'day' end
  return 'evening'
end

-- days since the last day with reading (0: read today), from the last 14 days; nil if none
local function days_since(data)
  local last
  for _, d in ipairs(data.days) do
    if (tonumber(d.sec) or 0) > 0 then
      local day = P.day_of(d.date or '')
      if day and (not last or day > last) then last = day end
    end
  end
  if not last or not data.today then return nil end
  return data.today - last
end

P.HUNGER = { [0] = 'full', 'peckish', 'hungry', 'hungry', 'sulky', 'sulky', 'sulky' }
local function hunger(st, data)
  if not st.hatched then return 'egg' end
  local n = days_since(data)
  if (data.today_sec or 0) > 0 then n = 0 end
  if not n then n = 14 end
  return n >= 7 and 'hiding' or P.HUNGER[n]
end

-- its character: the first that fits, from how you have been reading
P.TRAITS = {
  owl = 'a night owl', lark = 'an early bird', marathon = 'a marathon reader', nibbler = 'a nibbler',
  steady = 'a creature of habit', butterfly = 'a butterfly', loyal = 'loyal to one book', finisher = 'a finisher',
  curious = 'curious about everything',
}
local function trait(st, data)
  local tod = st.tod
  local all = tod.night + tod.morning + tod.day + tod.evening
  if all >= 2 * 3600 then
    if tod.night / all >= 0.35 then return 'owl' end
    if tod.morning / all >= 0.35 then return 'lark' end
  end
  local days, secs = 0, 0
  for _, d in ipairs(data.days) do
    local s = tonumber(d.sec) or 0
    if s > 0 then days, secs = days + 1, secs + s end
  end
  if days >= 3 and secs / days >= 75 * 60 then return 'marathon' end
  local titles, ndays = {}, {}
  local week = data.today and P.date(data.today - 6) or ''
  for _, r in ipairs(data.book_days) do
    if (r.date or '') < week then goto skip end
    if r.id then titles[r.id] = true end
    if r.date then ndays[r.date] = true end
    ::skip::
  end
  local nbooks, nd = 0, 0
  for _ in pairs(titles) do nbooks = nbooks + 1 end
  for _ in pairs(ndays) do nd = nd + 1 end
  if nbooks >= 3 then return 'butterfly' end
  if (data.streak or 0) >= 7 then return 'steady' end
  if (st.gen_finished or 0) >= 3 then return 'finisher' end
  if nbooks == 1 and nd >= 3 then return 'loyal' end
  if days >= 4 and secs / days < 15 * 60 then return 'nibbler' end
  return 'curious'
end

-- the awards: an id, its name, what it takes
P.AWARDS = {
  { id = 'hatch', name = 'Hatched', text = 'Read until the egg hatched.' },
  { id = 'book1', name = 'First book', text = 'Finished a book together.' },
  { id = 'book5', name = 'Five books', text = 'Finished five books together.' },
  { id = 'book20', name = 'Twenty books', text = 'Finished twenty books together.' },
  { id = 'streak7', name = 'A week in a row', text = 'Read seven days in a row.' },
  { id = 'streak30', name = 'A month in a row', text = 'Read thirty days in a row.' },
  { id = 'long', name = 'A long sitting', text = 'Read three hours in one day.' },
  { id = 'h10', name = 'Ten hours', text = 'Fed ten hours of reading.' },
  { id = 'h100', name = 'A hundred hours', text = 'Fed a hundred hours of reading.' },
  { id = 'owl', name = 'Night owl', text = 'Read mostly at night.' },
  { id = 'shelf', name = 'Three at once', text = 'Read three books in one week.' },
  { id = 'moth', name = 'A new generation', text = 'Grew up, left at ' .. P.COCOON_HOURS .. ' hours and laid an egg.' },
}

-- its taste: the reading of each book on each day (book_days), by the book's guessed kind, added
-- once (today's figure grows through the day: only what is new counts); from the day the egg was
-- laid. One kind is its taste once it has an hour and 40 % of what was read.
local function add_taste(st, data)
  st.taste, st.tasted = st.taste or {}, st.tasted or {}
  local authors = {}
  for _, b in ipairs(data.books) do if b.id then authors[b.id] = b.author end end
  if data.current and data.current.id then authors[data.current.id] = data.current.author end
  for _, r in ipairs(data.book_days) do
    local day = P.day_of(r.date or '')
    -- the last week only: older days are forgotten below and would count again
    if day and (not st.born or day >= st.born) and (not data.today or day >= data.today - 6) then
      local key = r.date .. '|' .. tostring(r.id or r.title or '')
      local sec, before = tonumber(r.sec) or 0, st.tasted[key] or 0
      if sec > before then
        local kind = T.guess(r.title, authors[r.id])
        if kind then st.taste[kind] = (st.taste[kind] or 0) + (sec - before) end
        st.tasted[key] = sec
      end
    end
  end
  -- forget the days the reader no longer reports
  if data.today then
    local oldest = P.date(data.today - 8)
    for key in pairs(st.tasted) do if key:sub(1, 10) < oldest then st.tasted[key] = nil end end
  end
end

function P.taste_of(st)
  local all, best, bk = 0, 0, nil
  for k, v in pairs(st.taste or {}) do
    all = all + v
    if v > best then best, bk = v, k end
  end
  if all >= 3600 and best / all >= 0.4 then return bk end
  return nil
end

local function earn(st, id, today, out)
  if not st.awards[id] then st.awards[id] = today or 0; out[#out + 1] = id end
end

local function event(st, kind, text, today)
  st.events[#st.events + 1] = { kind = kind, text = text, day = today }
  while #st.events > 6 do table.remove(st.events, 1) end
end

-- the whole update: food, hatching, growing, the cocoon, books finished, the time of day of the
-- reading since last time, hunger, character, awards. Returns the view for the screens.
function P.update(st, data, random)
  local today = data.today
  local earned = {}
  -- the reading since last time, by the hour it ended: the time of day the reader reads
  if data.ok and data.hour and data.total > (st.last_total or 0) then
    local b = bucket(data.hour)
    st.tod[b] = st.tod[b] + (data.total - st.last_total)
  end
  if data.ok then st.last_total = math.max(st.last_total or 0, data.total) end
  -- books finished since last time (with their kind, for its review)
  for _, b in ipairs(data.books) do
    if b.finished and b.id and not st.seen[b.id] then
      st.seen[b.id] = true
      st.finished = st.finished + 1
      st.gen_finished = (st.gen_finished or 0) + 1
      event(st, 'finished', b.title or '', today)
      st.events[#st.events].taste = T.guess(b.title, b.author)
    end
  end
  add_taste(st, data)
  local food = math.max(0, data.total - (st.base or 0))
  if not st.hatched and food >= P.HATCH_SEC then
    st.hatched = true
    st.hatched_day = today
    event(st, 'hatched', nil, today)
    earn(st, 'hatch', today, earned)
  end
  -- the cocoon: a moth flies off and leaves an egg
  if st.hatched and food >= P.COCOON_HOURS * 3600 then
    st.lineage[#st.lineage + 1] = { name = st.name, gen = st.gen, born = st.born, left = today,
                                     hours = math.floor(food / 3600), books = st.gen_finished or 0,
                                     trait = trait(st, data), taste = P.taste_of(st) }
    while #st.lineage > P.MAX_LINEAGE do table.remove(st.lineage, 1) end
    local old = st.name
    new_egg(st, data, random)
    event(st, 'moth', old, today)
    earn(st, 'moth', today, earned)
    food = 0
  end
  local stage = stage_of(st, food)
  if stage > (st.stage or 1) and stage > 2 then
    local nm = P.SP[P.species_of(st)].stages[stage]             -- "a young …", "an elder …"
    event(st, 'grew', (nm:match('^[aeiou]') and 'an ' or 'a ') .. nm, today)
  end
  st.stage = stage
  -- awards
  if st.finished >= 1 then earn(st, 'book1', today, earned) end
  if st.finished >= 5 then earn(st, 'book5', today, earned) end
  if st.finished >= 20 then earn(st, 'book20', today, earned) end
  if (data.streak or 0) >= 7 then earn(st, 'streak7', today, earned) end
  if (data.streak or 0) >= 30 then earn(st, 'streak30', today, earned) end
  if (data.today_sec or 0) >= 3 * 3600 then earn(st, 'long', today, earned) end
  local all_food = math.max(0, data.total - (st.first_total or data.total))
  if all_food >= 10 * 3600 then earn(st, 'h10', today, earned) end
  if all_food >= 100 * 3600 then earn(st, 'h100', today, earned) end
  local tr = st.hatched and trait(st, data) or nil
  if tr == 'owl' then earn(st, 'owl', today, earned) end
  if tr == 'butterfly' then earn(st, 'shelf', today, earned) end
  local taste = st.hatched and P.taste_of(st) or nil
  local stg, sp = P.STAGES[stage], P.SP[P.species_of(st)]
  local nexth = P.STAGES[stage + 1] and P.STAGES[stage + 1].hours or P.COCOON_HOURS
  return {
    stage = stage, stage_key = stg.key, stage_name = sp.stages[stage], food = food, species = sp.key,
    to_next = st.hatched and math.max(0, nexth * 3600 - food) or math.max(0, P.HATCH_SEC - food),
    next_name = st.hatched and (P.STAGES[stage + 1] and P.STAGES[stage + 1].key or sp.leave) or 'hatch',
    hunger = hunger(st, data), trait = tr, trait_name = tr and P.TRAITS[tr] or nil,
    taste = taste, taste_name = taste and T.NAMES[taste] or nil,
    book = data.current, today_sec = data.today_sec, streak = data.streak, earned = earned,
    reading = data.ok,
  }
end

------------------------------------------------------------------ the brood

-- an award of any creature of the brood (the other kinds' eggs come with one)
function P.has_award(root, id)
  if root.bw and root.bw.awards and root.bw.awards[id] then return true end
  for _, c in pairs(root.brood or {}) do if c.awards and c.awards[id] then return true end end
  return false
end

-- each kind: { sp, state = 'awake' | 'asleep' | 'egg' (ready to hatch) | 'locked', st }
function P.brood(root)
  local out, awake = {}, P.species_of(root.bw)
  for _, kind in ipairs(P.SPECIES) do
    local c = (root.brood or {})[kind.key]
    local state
    if kind.key == awake then state, c = 'awake', root.bw
    elseif c then state = 'asleep'
    elseif not kind.unlock or P.has_award(root, kind.unlock) then state = 'egg'
    else state = 'locked' end
    out[#out + 1] = { sp = kind, state = state, st = c }
  end
  return out
end

-- a creature waking: what was read while it slept is not its food, nor its time of day, taste or
-- finished books; it says it woke. A sleeping one does not eat, grow or get older.
function P.wake(st, data)
  local shift = math.max(0, data.total - (st.slept_total or data.total))
  st.base = (st.base or 0) + shift
  st.first_total = (st.first_total or 0) + shift
  st.last_total = data.total
  st.slept_total = nil
  st.seen = st.seen or {}
  for _, b in ipairs(data.books) do if b.finished and b.id then st.seen[b.id] = true end end
  st.tasted = {}
  for _, r in ipairs(data.book_days) do
    if r.date then st.tasted[r.date .. '|' .. tostring(r.id or r.title or '')] = tonumber(r.sec) or 0 end
  end
  event(st, 'woke', nil, data.today)
end

-- the creature of kind key wakes (or hatches from a new egg) and the awake one goes to sleep
function P.switch(root, key, data, random)
  root.brood = root.brood or {}
  local cur = root.bw
  local ck = P.species_of(cur)
  if ck == key or not P.SP[key] then return cur end
  cur.slept_total = data.total
  root.brood[ck] = cur
  local nxt = root.brood[key]
  root.brood[key] = nil
  if nxt then P.wake(nxt, data) else nxt = P.new(data, random, key) end
  root.bw = nxt
  return nxt
end

-- the reading days of the last two weeks, newest first: { day, sec, title }
function P.diary(data)
  local top = {}
  for _, r in ipairs(data.book_days) do
    if r.date and not top[r.date] then top[r.date] = r.title end
  end
  local out = {}
  for i = #data.days, 1, -1 do
    local d = data.days[i]
    local day = P.day_of(d.date or '')
    if day then out[#out + 1] = { day = day, sec = tonumber(d.sec) or 0, title = top[d.date] } end
  end
  return out
end

return P
