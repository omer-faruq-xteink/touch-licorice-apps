-- Port Wren for XTOS Licorice (uses tools/gamekit): a detective game in a 1920s harbour town.
-- Every case is a murder made new from a seed: the truth first (who, why, how, when, and where
-- everyone was), then the clues and the lies drawn from it, and a solver proves that the clues the
-- player can reach lead to one culprit, motive and means before the case is shown.
--
-- The game logic lives in package files under game/ (loaded with _G.require, since the bundle's
-- local require shadows the host's): rng and save always, text and town on start, gen and solver
-- only when a case is made. town.txt keeps the career's town, case.txt the open case (and a single
-- case's own town), prefs.txt the settings.

local W, H = kit.W, kit.H
local BTN_Y, BTN_H = 724, 60
local SLICE_MS = 250
local ACTIONS = 3                -- actions in a part of a day

local function mod(name) return (_G.require('game.' .. name)) end
local Rn, S = mod('rng'), mod('save')
local T, Town, G
local function text() T = T or mod('text'); return T end
local function townmod() Town = Town or mod('town')(text(), Rn); return Town end
local function gen() G = G or mod('gen')(text(), Rn, townmod()); return G end

local screen = 'title'
local ERR = nil
local hits = {}                  -- tap regions of the last frame: { x, y, w, h, fn }
local town, case = nil, nil
local prefs = { size = 'short', mode = 'career' }
local prep = nil                 -- a case being made: { opts, co }
local here, who = nil, nil       -- the place shown, the person talked to
local log = {}                   -- the conversation on the talk screen
local page = 1                   -- the page of a list screen
local guess = {}                 -- the accusation being picked
local crowd = 1                  -- the page of the people at a place
local from = 'title'             -- where Settings and Career go back to

------------------------------------------------------------------ drawing helpers

local function hit(x, y, w, h, fn) hits[#hits + 1] = { x = x, y = y, w = w, h = h, fn = fn } end

local function button(gg, x, y, w, h, label, fn, opts)
  kit.button(gg, x, y, w, h, label, opts)
  hit(x, y, w, h, fn)
end

-- a row of buttons across the bottom: { {label, fn}, ... }
local function bottom_row(gg, list)
  local n, gap = #list, 8
  local bw = (W - 32 - gap * (n - 1)) // n
  for k, b in ipairs(list) do button(gg, 16 + (k - 1) * (bw + gap), BTN_Y, bw, BTN_H, b[1], b[2]) end
end

local function header(gg, title, sub, maxw)
  local f = kit.font('large')
  local t = tostring(title)
  if kit.width(f, t) > (maxw or W - 32) then
    while #t > 1 and kit.width(f, t .. '…') > (maxw or W - 32) do t = kit.drop_last(t) end
    t = t .. '…'
  end
  gg:text(16, 10, t, { font = f })
  if sub then gg:text(16, 50, kit.short(sub, 44), { font = kit.font('small') }) end
  gg:line(16, 80, W - 16, 80)
end

-- wrapped lines of small text from y, at most to y_max; returns the next y
local function para(gg, s, x, y, y_max, fname)
  fname = fname or 'small'
  local lh = kit.line_h(fname) + 2
  for _, l in ipairs(kit.wrap(s, fname, W - x - 16)) do
    if y + lh > y_max then return y end
    gg:text(x, y, l, { font = kit.font(fname) })
    y = y + lh
  end
  return y
end

local function box(title, lines, rows)
  kit.show({ title = title, lines = lines, rows = rows, cancel = kit.close })
end

------------------------------------------------------------------ saving

local function save()
  kit.write('prefs.txt', S.encode(prefs))
  if town and town.mode == 'career' then kit.write('town.txt', S.encode(town)) end
  local rec = {}
  if prep then rec.prep = prep.opts elseif case then rec.case = case end
  if town and town.mode == 'single' then rec.town = town end
  kit.write('case.txt', (rec.prep or rec.case) and S.encode(rec) or '')
end

local function career_saved() return S.decode(kit.read('town.txt')) ~= nil end
local function has_game() return case ~= nil or career_saved() end

------------------------------------------------------------------ the clock

local function act_left()
  local c = case.clock
  return (case.days - c.day) * 4 * ACTIONS + (4 - c.part) * ACTIONS + (ACTIONS - c.used)
end

local function part_of() return case.clock.part end

-- the people of the case who can be met: suspects and witnesses, alive
local function people()
  local out, seen = {}, {}
  local function add(pid)
    if not seen[pid] and gen().meetable(case, town, pid) then seen[pid] = true; out[#out + 1] = pid end
  end
  for _, pid in ipairs(case.suspects) do add(pid) end
  for _, pid in ipairs(case.witnesses) do add(pid) end
  return out
end

local function place_of(pid) return case.sched[pid] and case.sched[pid][part_of()] end

local function people_at(place)
  local out = {}
  for _, pid in ipairs(people()) do if place_of(pid) == place then out[#out + 1] = pid end end
  return out
end

local function name(pid) return town.people[pid].name end
local function first(pid) return (town.people[pid].name:match('^(%S+)')) end
local function surname(pid) return (town.people[pid].name:match('(%S+)$')) end

local after_strike                -- set below

local strike                      -- set with the accusation code below

local function spend(n)
  local c = case.clock
  c.used = c.used + n
  while c.used >= ACTIONS do
    c.used = c.used - ACTIONS
    c.part = c.part + 1
    if c.part > 4 then c.part, c.day = 1, c.day + 1 end
  end
  if c.day > case.days then strike(nil) end
end

------------------------------------------------------------------ making a case

local function new_seed()
  local s = rawget(_G, 'portwren_seed')
  if s then return s end
  -- the reader has no os library; math.random is seeded anew every session
  return ((kit.now_ms() or 1) * 7919 + math.random(1, 2147483000)) % 2147483000 + 1
end

local function schedule(fn)
  local ok = pcall(function() ctx:after(1, fn) end)
  return ok
end

local SCREENS = {}
local step

local function finish(c)
  c.heard, c.heard2, c.searched = {}, {}, {}
  guess = {}
  case = c
  prep = nil
  save()
  screen = 'case'
  kit.refresh()
end

step = function()
  if not prep then return end
  pcall(function() ctx.budget:extend() end)
  local t0 = kit.now_ms() or 0
  while true do
    local ok, res = coroutine.resume(prep.co)
    if not ok then
      ERR = tostring(res)
      prep = nil
      screen = 'title'
      kit.refresh()
      return
    end
    if coroutine.status(prep.co) == 'dead' then finish(res); return end
    if (kit.now_ms() or 0) - t0 > SLICE_MS then break end
  end
  if not schedule(step) then step() end
  kit.refresh()
end

local function begin(opts)
  prep = { opts = opts }
  prep.co = coroutine.create(function() return gen().new_case(town, opts) end)
  screen = 'preparing'
  save()
  if not schedule(step) then step() end
end

-- the next case for the town in use: its number, seed, size and a pattern rank allows
local function next_case()
  case = nil
  town.case_no = town.case_no + 1
  local seed = Rn.mix(town.seed, town.case_no * 31 + 5)
  local r = Rn.new(seed)
  local open = townmod().patterns(town, prefs.size)
  local weighted = {}
  for _, p in ipairs(open) do
    weighted[#weighted + 1] = p
    if p == 'classic' then weighted[#weighted + 1] = p end
  end
  begin({ seed = seed, size = prefs.size, pattern = r:pick(weighted), no = town.case_no })
end

local function new_town(mode)
  town = townmod().make(new_seed(), mode)
  prefs.mode = mode
  next_case()
end

local function cancel_prep()
  prep = nil
  case = nil
  if town then town.case_no = math.max(0, town.case_no - 1) end
  if town and town.mode == 'career' and town.case_no == 0 then
    -- a career that never got its first case is not kept
    kit.write('town.txt', '')
    town = nil
  elseif town and town.mode == 'single' then town = S.decode(kit.read('town.txt')) end
  save()
  screen = 'title'
end

------------------------------------------------------------------ clues

local function found(c) return case.found[c.id] == true end

local function reveal(c)
  case.found[c.id] = true
  case.newest = c.id
  log[#log + 1] = { 'New clue: ' .. text().clue(case, town, c), true }
end

local function clues_where(test)
  local out = {}
  for _, c in ipairs(case.clues) do if test(c) then out[#out + 1] = c end end
  return out
end

------------------------------------------------------------------ screens

local HOW = {
  'Every case is a murder in Port Wren. Search places, question people, show them what you found, '
    .. 'and name the culprit, the motive and the means.',
  'Physical evidence and documents are certain. A witness is believed until caught in a lie; '
    .. 'after that, nothing they say counts.',
  'A suspect\'s own account never clears them. Someone is cleared when they could not get the means, '
    .. 'or when a believed witness or evidence puts them elsewhere at the time of the crime.',
  'The culprit had the means and the motive, and their account of that time is shown to be a lie.',
  'Searching a place or talking to someone takes an action; a day has four parts of three. '
    .. 'A wrong accusation, or running out of time, lets the killer strike again. A second one, and the killer flees.',
}

local function how_to_play()
  box('How to play', HOW, { { { 'Close', kit.close } } })
end

local function continue()
  if case then screen = case.over and 'end' or 'case'
  elseif town or career_saved() then
    town = town or S.decode(kit.read('town.txt'))
    next_case()
  end
end

SCREENS.title = {
  draw = function(gg)
    gg:text(16, 60, 'Port Wren', { font = kit.font('large') })
    gg:text(16, 104, 'A detective in a harbour town, 1920s', { font = kit.font('small') })
    gg:line(16, 140, W - 16, 140)
    local list = {}
    if has_game() then list[#list + 1] = { 'Continue', continue } end
    list[#list + 1] = { 'New career', function()
      if career_saved() then
        box('A new career?', { 'Your career so far, its town and its cases, will be lost.' },
          { { { 'Start again', function() kit.close(); new_town('career') end }, { 'Cancel', kit.close } } })
      else new_town('career') end
    end }
    list[#list + 1] = { 'Single cases', function()
      if case and not case.over and town and town.mode == 'career' then
        -- the open career case would be left behind: giving it up counts as lost
        box('Give up the open case?', { 'The killer flees and the case counts as lost in your career.' },
          { { { 'Give up', function()
                kit.close()
                case.over = 'lost'
                town.lost = town.lost + 1
                town.rep = town.rep - math.min(5, town.rep)
                townmod().after_case(town, case)
                kit.write('town.txt', S.encode(town))
                case = nil
                new_town('single')
              end }, { 'Cancel', kit.close } } })
      else new_town('single') end
    end }
    list[#list + 1] = { 'Settings', function() from = 'title'; screen = 'settings' end }
    list[#list + 1] = { 'How to play', how_to_play }
    for k, b in ipairs(list) do button(gg, 60, 180 + (k - 1) * 84, W - 120, 64, b[1], b[2]) end
  end,
  back = function() return false end,
}

SCREENS.preparing = {
  draw = function(gg)
    header(gg, 'Port Wren', town and ('Case ' .. town.case_no) or nil)
    gg:text(16, 140, 'Preparing a new case…', { font = kit.font('medium') })
    if town then
      local r = Rn.new(Rn.mix(town.seed, town.case_no))
      para(gg, text().gossip(town, r), 16, 200, 400)
    end
  end,
  back = function() cancel_prep(); return true end,
}

local function case_title() return 'The ' .. surname(case.victim) .. ' affair' end

local function status_line()
  return 'Day ' .. case.clock.day .. '/' .. case.days .. ' ' .. text().PARTS[case.clock.part]
    .. ' · ' .. act_left() .. ' left · ' .. case.strikes .. '/2'
end

SCREENS.case = {
  draw = function(gg)
    header(gg, case_title(), status_line(), W - 200)
    -- waiting passes the rest of this part of the day (people move about between parts)
    button(gg, W - 100, 8, 84, 36, 'Wait', function()
      local function wait() kit.close(); spend(ACTIONS - case.clock.used); save() end
      if case.clock.day == case.days and case.clock.part == 4 then
        box('Wait until morning?', { 'Your time is up after tonight: the killer will strike again'
          .. (case.strikes > 0 and ', and this time flee.' or '.') },
          { { { 'Wait anyway', wait }, { 'Cancel', kit.close } } })
      else wait() end
    end, { font = 'small' })
    button(gg, W - 192, 8, 84, 36, 'Menu', function()
      box('Port Wren', nil, { { { 'Career', function() kit.close(); page = 1; from = 'case'; screen = 'career' end },
                                { 'Settings', function() kit.close(); from = 'case'; screen = 'settings' end } },
                              { { 'How to play', function() kit.close(); how_to_play() end },
                                { 'Close', kit.close } } })
    end, { font = 'small' })
    local y = 92
    for _, l in ipairs(text().intro(case, town)) do y = para(gg, l, 16, y, 300) + 4 end
    y = y + 6
    -- the rows share what is left above the buttons
    local rh = math.max(44, math.min(60, (BTN_Y - 10 - y) // #case.places - 6))
    for _, k in ipairs(case.places) do
      local names = {}
      for _, pid in ipairs(people_at(k)) do names[#names + 1] = text().short_name(case, town, pid) end
      kit.button(gg, 16, y, W - 32, rh, '', {})
      gg:text(28, y + 2, kit.short(text().PLACES[k].name, 40), { font = kit.font('medium') })
      gg:text(28, y + rh - kit.line_h('small') - 2, kit.short(#names > 0 and table.concat(names, ', ') or 'nobody here now', 42),
        { font = kit.font('small') })
      local key = k
      hit(16, y, W - 32, rh, function() here = key; crowd = 1; screen = 'place' end)
      y = y + rh + 6
    end
    bottom_row(gg, { { 'Notebook', function() page = 1; screen = 'notebook' end },
                     { 'Board', function() screen = 'board' end },
                     { 'Accuse', function() guess = {}; screen = 'accuse' end } })
  end,
  back = function() screen = 'title'; return true end,
}

local function can_search(place)
  local s = case.searched[place]
  return s == nil or s < case.strikes
end

local function search(place)
  case.searched[place] = case.strikes
  for _, c in ipairs(case.clues) do
    if not found(c) and c.gate.k == 'search' and c.gate.place == place then
      case.found[c.id] = true
      case.newest = c.id
    end
  end
  save()
  spend(1)
  save()
end

SCREENS.place = {
  draw = function(gg)
    header(gg, text().PLACES[here].name, status_line())
    local y = 96
    if can_search(here) then
      button(gg, 16, y, 200, 56, 'Search', function() search(here) end)
      gg:text(232, y + 18, 'one action', { font = kit.font('small') })
    else
      gg:text(16, y + 16, 'Searched.', { font = kit.font('medium') })
    end
    y = y + 72
    gg:text(16, y, 'People here now', { font = kit.font('small') })
    y = y + 26
    local all = people_at(here)
    local per = 5
    local pages = math.max(1, (#all + per - 1) // per)
    if crowd > pages then crowd = 1 end
    local shown = {}
    for i = (crowd - 1) * per + 1, math.min(#all, crowd * per) do shown[#shown + 1] = all[i] end
    if #all == 0 then gg:text(16, y, 'Nobody.', { font = kit.font('small') }); y = y + 26 end
    for _, pid in ipairs(shown) do
      local p = pid
      button(gg, 16, y, W - 32, 52, name(pid), function()
        who = p
        log = {}
        local cost = 1
        if (case.talked[p] or 0) == 0 and town.people[p].trust < 30 then cost = 2 end
        case.talked[p] = (case.talked[p] or 0) + 1
        local r = Rn.new(Rn.mix(case.seed, p * 13 + case.talked[p]))
        log[#log + 1] = { text().greet(case, town, p, r) }
        local is_suspect = false
        for _, s in ipairs(case.suspects) do if s == p then is_suspect = true end end
        if is_suspect and not case.heard[p] then
          case.heard[p] = true
          for _, l in ipairs(text().statement(case, town, p, false)) do log[#log + 1] = { l } end
        end
        if is_suspect and case.night2 and not case.heard2[p] then
          case.heard2[p] = true
          log[#log + 1] = { 'And last night:' }
          for _, l in ipairs(text().statement(case, town, p, true)) do log[#log + 1] = { l } end
        end
        for _, c in ipairs(case.clues) do
          if not found(c) and c.gate.k == 'talk' and c.gate.who == p then reveal(c) end
        end
        screen = 'talk'
        save()
        spend(cost)
        save()
      end)
      y = y + 60
    end
    if pages > 1 then
      button(gg, 16, y, W - 32, 44, 'More people', function() crowd = crowd % pages + 1 end, { font = 'small' })
      y = y + 52
    end
    y = y + 8
    for _, c in ipairs(clues_where(function(c) return found(c) and c.gate.k == 'search' and c.gate.place == here end)) do
      y = para(gg, (c.id == case.newest and '» ' or '') .. text().clue(case, town, c), 16, y, BTN_Y - 8) + 6
    end
    bottom_row(gg, { { 'Back', function() screen = 'case' end } })
  end,
  back = function() screen = 'case'; return true end,
}

local function ask(topic)
  local any = false
  for _, c in ipairs(case.clues) do
    if not found(c) and c.gate.k == 'ask' and c.gate.who == who and c.gate.topic == topic then
      reveal(c)
      any = true
    end
  end
  if any then save(); return end
  local r = Rn.new(Rn.mix(case.seed, who * 17 + #log))
  log[#log + 1] = { text().answer(case, town, who, topic, r) }
end

SCREENS.talk = {
  draw = function(gg)
    local p = town.people[who]
    header(gg, p.name, text().JOBS[p.job].name)
    gg:text(300, 50, 'trust', { font = kit.font('small') })
    gg:rect(350, 56, 110, 12)
    gg:rect(350, 56, math.max(1, math.floor(110 * p.trust / 100)), 12, { fill = true })
    -- the conversation: its last lines that fit
    local lh = kit.line_h('small') + 2
    local lines = {}
    for _, e in ipairs(log) do
      for k, l in ipairs(kit.wrap(e[1], 'small', W - 48)) do lines[#lines + 1] = { l, e[2], k == 1 } end
      lines[#lines + 1] = { '', false }
    end
    local top, bottom = 92, 560
    local fit = (bottom - top) // lh
    local from = math.max(1, #lines - fit + 1)
    local y = top
    for i = from, #lines do
      local l = lines[i]
      if l[2] and l[3] then gg:rect(16, y - 2, 4, lh * 2) end
      gg:text(l[2] and 26 or 16, y, l[1], { font = kit.font('small') })
      y = y + lh
    end
    -- topics
    gg:line(16, 568, W - 16, 568)
    local x, ty = 16, 578
    local f = kit.font('small')
    for _, topic in ipairs(text().topics(case, town, who)) do
      local label = text().topic_label(case, town, topic)
      local w = kit.width(f, label) + 24
      if x + w > W - 16 then x, ty = 16, ty + 46 end
      if ty + 40 > BTN_Y - 4 then break end
      local tp = topic
      button(gg, x, ty, w, 40, label, function() ask(tp) end, { font = 'small' })
      x = x + w + 8
    end
    bottom_row(gg, { { 'Show clue', function() page = 1; screen = 'show' end },
                     { 'Leave', function() screen = 'place' end } })
  end,
  back = function() screen = 'place'; return true end,
}

-- a page of found clues to pick from: each row as tall as its text, as many as fit
local function clue_list(gg, list, y0, on_pick)
  local lh = kit.line_h('small')
  local bottom = BTN_Y - 8
  local pages, cur, used = { {} }, 1, y0
  local rows = {}
  for i, c in ipairs(list) do
    local lines = kit.wrap(c.id .. '. ' .. text().clue(case, town, c), 'small', W - 56)
    local h = #lines * lh + 12
    rows[i] = { clue = c, lines = lines, h = h }
    if used + h > bottom and #pages[cur] > 0 then cur = cur + 1; pages[cur] = {}; used = y0 end
    pages[cur][#pages[cur] + 1] = i
    used = used + h + 6
  end
  page = math.max(1, math.min(page, #pages))
  local y = y0
  for _, i in ipairs(pages[page]) do
    local row = rows[i]
    kit.button(gg, 16, y, W - 32, row.h, '', {})
    local ly = y + 6
    for _, l in ipairs(row.lines) do
      gg:text(28, ly, l, { font = kit.font('small') })
      ly = ly + lh
    end
    local c = row.clue
    if on_pick then hit(16, y, W - 32, row.h, function() on_pick(c) end) end
    y = y + row.h + 6
  end
  return #pages
end

SCREENS.show = {
  draw = function(gg)
    header(gg, 'Show ' .. first(who) .. '…', 'Pick a clue to show')
    local list = clues_where(found)
    local pages = clue_list(gg, list, 92, function(c)
      local opened = false
      for _, x in ipairs(case.clues) do
        if not found(x) and x.gate.k == 'show' and x.gate.who == who and x.gate.clue == c.id then
          reveal(x)
          opened = true
        end
      end
      if not opened then
        local r = Rn.new(Rn.mix(case.seed, who * 19 + c.id))
        log[#log + 1] = { 'You show the clue. ' .. text().react(case, town, who, c, r) }
      end
      save()
      screen = 'talk'
    end)
    bottom_row(gg, { { 'Prev', function() page = page - 1 end }, { page .. '/' .. pages, function() end },
                     { 'Next', function() page = page + 1 end }, { 'Back', function() screen = 'talk' end } })
  end,
  back = function() screen = 'talk'; return true end,
}

-- a string cut until it fits w pixels in font f
local function fit(s, f, w)
  s = tostring(s)
  while #s > 1 and kit.width(f, s) > w do s = kit.drop_last(s) end
  return s
end

local KIND_ORDER = { document = 1, physical = 2, observation = 3, testimony = 4 }

SCREENS.notebook = {
  draw = function(gg)
    header(gg, 'Notebook', case_title())
    local list = clues_where(found)
    table.sort(list, function(a, b)
      local ka, kb = KIND_ORDER[a.kind] or 9, KIND_ORDER[b.kind] or 9
      if ka ~= kb then return ka < kb end
      return a.id < b.id
    end)
    if #list == 0 then gg:text(16, 100, 'Nothing found yet.', { font = kit.font('medium') }) end
    local pages = clue_list(gg, list, 92, nil)
    button(gg, 16, BTN_Y, 176, BTN_H, 'Statements', function() page = 1; screen = 'statements' end)
    button(gg, 200, BTN_Y, 80, BTN_H, '<', function() page = page - 1 end)
    button(gg, 288, BTN_Y, 80, BTN_H, '>', function() page = page + 1 end)
    button(gg, 376, BTN_Y, 88, BTN_H, 'Back', function() screen = 'case' end)
    gg:text(W - 80, 52, page .. '/' .. pages, { font = kit.font('small') })
  end,
  back = function() screen = 'case'; return true end,
}

-- the cells of the Statements table a found clue contradicts: [pid][slot] = true
local function contradicted()
  local out = {}
  for _, c in ipairs(case.clues) do
    if found(c) then
      for _, f in ipairs(c.facts) do
        local said = f.who and case.says[f.who] and case.says[f.who][f.slot]
        if said and ((f.t == 'at' and f.place ~= said) or (f.t == 'not_at' and f.place == said)) then
          out[f.who] = out[f.who] or {}
          out[f.who][f.slot] = true
        end
      end
    end
  end
  return out
end

local night_tab = false
SCREENS.statements = {
  draw = function(gg)
    header(gg, 'Statements', 'Where each suspect says they were')
    local y0 = 92
    if case.night2 then
      button(gg, 16, y0, 140, 40, 'Evening', function() night_tab = false end, { font = 'small', line_width = night_tab and 1 or 3 })
      button(gg, 164, y0, 140, 40, 'Night 2', function() night_tab = true end, { font = 'small', line_width = night_tab and 3 or 1 })
      y0 = y0 + 50
    else night_tab = false end
    local a, b = 1, 12
    if night_tab then a, b = 13, 18 end
    local sus = case.suspects
    local f = kit.font('small')
    local tw = 64
    local cw = (W - 32 - tw) // math.max(1, #sus)
    local rh = math.min(40, (BTN_Y - 16 - y0 - 30) // (b - a + 1))
    for k, pid in ipairs(sus) do
      gg:text(16 + tw + (k - 1) * cw + 2, y0, fit(text().short_name(case, town, pid), f, cw - 4), { font = f })
    end
    local bad = contradicted()
    local y = y0 + 28
    for t = a, b do
      local m = text().minutes(t)
      gg:text(16, y + 4, string.format('%d:%02d', (m // 60) - 12, m % 60), { font = f })
      for k, pid in ipairs(sus) do
        local x = 16 + tw + (k - 1) * cw
        local heard = (night_tab and case.heard2 or case.heard)[pid]
        local cell = heard and text().PLACES[case.says[pid][t]].short or '?'
        gg:text(x + 4, y + 4, fit(cell, f, cw - 8), { font = f })
        if heard and bad[pid] and bad[pid][t] then
          gg:rect(x, y, cw - 2, rh - 2, { line_width = 3 })
        end
      end
      y = y + rh
    end
    bottom_row(gg, { { 'Back', function() screen = 'notebook' end } })
  end,
  back = function() screen = 'notebook'; return true end,
}

local picked = nil               -- the clue picked on the board
local function tied(clue_id, pid)
  for k, t in ipairs(case.board) do if t.clue == clue_id and t.who == pid then return k end end
  return nil
end

SCREENS.board = {
  draw = function(gg)
    header(gg, 'Board', 'Tap a clue number, then a suspect')
    local sus = case.suspects
    local cards = {}
    local cw, ch = (W - 40) // 2, 96
    for k, pid in ipairs(sus) do
      local x = 16 + ((k - 1) % 2) * (cw + 8)
      local y = 92 + ((k - 1) // 2) * (ch + 10)
      cards[pid] = { x + cw // 2, y + ch }
      kit.button(gg, x, y, cw, ch, '', {})
      gg:text(x + 10, y + 8, fit(text().short_name(case, town, pid), kit.font('medium'), cw - 20), { font = kit.font('medium') })
      gg:text(x + 10, y + 40, fit(text().JOBS[town.people[pid].job].name, kit.font('small'), cw - 20), { font = kit.font('small') })
      local ids = {}
      for _, t in ipairs(case.board) do if t.who == pid then ids[#ids + 1] = tostring(t.clue) end end
      if #ids > 0 then gg:text(x + 10, y + 66, fit('clues ' .. table.concat(ids, ', '), kit.font('small'), cw - 20), { font = kit.font('small') }) end
      local p = pid
      hit(x, y, cw, ch, function()
        if not picked then return end
        local k2 = tied(picked, p)
        if k2 then table.remove(case.board, k2) else case.board[#case.board + 1] = { clue = picked, who = p } end
        picked = nil
        save()
      end)
    end
    -- the found clues, as numbered chips
    local y = 92 + ((#sus + 1) // 2) * (ch + 10) + 6
    local x = 16
    for _, c in ipairs(clues_where(found)) do
      if x + 40 > W - 16 then x, y = 16, y + 44 end
      local id = c.id
      button(gg, x, y, 40, 38, tostring(id), function() picked = (picked == id) and nil or id end,
        { font = 'small', line_width = picked == id and 4 or 1 })
      x = x + 44
    end
    y = y + 50
    if picked then para(gg, picked .. '. ' .. text().clue(case, town, case.clues[picked]), 16, y, BTN_Y - 8) end
    bottom_row(gg, { { 'Back', function() picked = nil; screen = 'case' end } })
  end,
  back = function() picked = nil; screen = 'case'; return true end,
}

------------------------------------------------------------------ accusing

local function lose()
  case.over = 'lost'
  if town.mode == 'career' then
    town.lost = town.lost + 1
    case.rep = -math.min(5, town.rep)
    town.rep = town.rep + case.rep
  end
  save()
  screen = 'end'
end

strike = function(accused)
  if case.strikes >= 1 then lose(); return end
  pcall(function() ctx.budget:extend() end)
  guess = {}
  gen().strike(town, case, Rn.mix(case.seed, 97 + case.clock.day), accused)
  save()
  after_strike()
end

local function decide()
  local who, motive, means = guess.who, guess.motive, guess.means
  guess = {}
  case.guess = { who = who, motive = motive, means = means }
  if who == case.killer then
    local full = motive == case.motive and means == case.means
    case.over = full and 'solved' or 'partial'
    if town.mode == 'career' then
      local long = case.size == 'long'
      case.rep = full and (long and 30 or 20) or (long and 15 or 10)
      town.rep = town.rep + case.rep
      if full then town.solved = town.solved + 1 else town.partial = town.partial + 1 end
      local before = town.rank
      town.rank = townmod().rank_of(town.rep)
      case.promoted = town.rank > before or nil
    end
    save()
    screen = 'end'
    return
  end
  townmod().trust(town, who, -40)
  for _, f in ipairs(townmod().family(town, who)) do townmod().trust(town, f, -10) end
  local h = town.people[who].hist
  h[#h + 1] = { case = case.no, what = 'accused' }
  screen = 'case'
  strike(who)
  save()
end

SCREENS.accuse = {
  draw = function(gg)
    header(gg, 'Accuse', 'Who did it, why, and how?')
    local y = 92
    gg:text(16, y, 'Who', { font = kit.font('small') })
    y = y + 24
    local bw = (W - 40) // 2
    for k, pid in ipairs(case.suspects) do
      local x = 16 + ((k - 1) % 2) * (bw + 8)
      local p = pid
      button(gg, x, y + ((k - 1) // 2) * 54, bw, 48, name(pid), function() guess.who = p end,
        { font = 'small', line_width = guess.who == pid and 4 or 1 })
    end
    y = y + ((#case.suspects + 1) // 2) * 54 + 6
    gg:text(16, y, 'Why', { font = kit.font('small') })
    y = y + 24
    local mw = (W - 48) // 3
    for k, m in ipairs(text().MOTIVES) do
      local x = 16 + ((k - 1) % 3) * (mw + 8)
      local mm = m
      button(gg, x, y + ((k - 1) // 3) * 50, mw, 44, text().MOTIVE_NAME[m], function() guess.motive = mm end,
        { font = 'small', line_width = guess.motive == m and 4 or 1 })
    end
    y = y + 2 * 50 + 6
    gg:text(16, y, 'How', { font = kit.font('small') })
    y = y + 24
    for k, m in ipairs(text().MEANS) do
      local x = 16 + ((k - 1) % 2) * (bw + 8)
      local mm = m
      button(gg, x, y + ((k - 1) // 2) * 50, bw, 44, text().MEANS_NAME[m], function() guess.means = mm end,
        { font = 'small', line_width = guess.means == m and 4 or 1 })
    end
    local ready = guess.who and guess.motive and guess.means
    bottom_row(gg, { { 'Confirm', function()
                       if not ready then return end
                       box('Accuse ' .. name(guess.who) .. '?',
                         { 'A wrong accusation lets the killer strike again' .. (case.strikes > 0 and ', and this time flee.' or '.') },
                         { { { 'Accuse', function() kit.close(); decide() end }, { 'Cancel', kit.close } } })
                     end },
                     { 'Back', function() screen = 'case' end } })
  end,
  back = function() screen = 'case'; return true end,
}

------------------------------------------------------------------ the end of a case, the career

local END_TITLE = { solved = 'Case solved', partial = 'Solved, partly', lost = 'The killer fled' }

local function next_after_end()
  if town.mode == 'career' then
    townmod().after_case(town, case)
    kit.write('town.txt', S.encode(town))     -- kept before a single case takes its place
  end
  case = nil
  if prefs.mode == 'single' then new_town('single')
  else
    if town.mode ~= 'career' then town = S.decode(kit.read('town.txt')) end
    if town then next_case() else new_town('career') end
  end
end

SCREENS['end'] = {
  draw = function(gg)
    header(gg, END_TITLE[case.over] or 'The end', case_title())
    local y = 92
    local g = case.guess
    if case.over == 'lost' then
      y = para(gg, name(case.killer) .. ' has fled Port Wren.', 16, y, 600, 'medium') + 6
    elseif g then
      y = para(gg, 'You named ' .. name(g.who) .. '.', 16, y, 600, 'medium') + 6
      if case.over == 'partial' then
        local miss = {}
        if g.motive ~= case.motive then miss[#miss + 1] = 'the motive' end
        if g.means ~= case.means then miss[#miss + 1] = 'the means' end
        y = para(gg, 'But you had ' .. table.concat(miss, ' and ') .. ' wrong.', 16, y, 600) + 6
      end
    end
    y = para(gg, text().PATTERN_NAME[case.pattern] .. '.', 16, y, 600) + 4
    for _, l in ipairs(text().account(case, town)) do y = para(gg, l, 16, y, 640) + 4 end
    if town.mode == 'career' and case.rep then
      local s = 'Reputation ' .. (case.rep >= 0 and '+' or '') .. case.rep .. ', now ' .. town.rep .. '.'
      if case.promoted then s = s .. ' Promoted to ' .. text().RANKS[town.rank] .. '!' end
      para(gg, s, 16, math.max(y + 6, 600), BTN_Y - 4)
    end
    bottom_row(gg, { { 'Next case', next_after_end }, { 'Title', function() screen = 'title' end } })
  end,
  back = function() screen = 'title'; return true end,
}

local STATUS = { alive = 'in town', dead = 'dead', jailed = 'in jail', gone = 'moved away' }
local WHAT = { accused = 'you accused them', arrested = 'family arrested', widowed = 'widowed', bereaved = 'bereaved',
               fled = 'family fled',
               helped = 'you helped them' }

SCREENS.career = {
  draw = function(gg)
    if town.mode ~= 'career' then
      header(gg, 'Single cases', 'No career: every case is a new town')
      bottom_row(gg, { { 'Back', function() screen = (from == 'case' and case) and 'case' or 'title' end } })
      return
    end
    header(gg, text().RANKS[town.rank], 'Rep ' .. town.rep .. ' · solved ' .. town.solved .. ' · partly '
      .. town.partial .. ' · lost ' .. town.lost)
    local ids = {}
    for id = 1, town.next_id - 1 do if town.people[id] then ids[#ids + 1] = id end end
    local per = 12
    local pages = math.max(1, (#ids + per - 1) // per)
    page = math.max(1, math.min(page, pages))
    local f = kit.font('small')
    local y = 92
    for i = (page - 1) * per + 1, math.min(#ids, page * per) do
      local p = town.people[ids[i]]
      gg:text(16, y, fit(p.name .. ', ' .. text().JOBS[p.job].name, f, W - 32), { font = f })
      local h = p.hist[#p.hist]
      local s = STATUS[p.status] .. ' · trust ' .. p.trust .. (h and (' · ' .. (WHAT[h.what] or h.what) .. ', case ' .. h.case) or '')
      gg:text(28, y + 22, fit(s, f, W - 44), { font = f })
      y = y + 50
    end
    bottom_row(gg, { { 'Prev', function() page = page - 1 end }, { page .. '/' .. pages, function() end },
                     { 'Next', function() page = page + 1 end },
                     { 'Back', function() screen = (from == 'case' and case) and 'case' or 'title' end } })
  end,
  back = function() screen = (from == 'case' and case) and 'case' or 'title'; return true end,
}

------------------------------------------------------------------ settings

local function reset_career()
  kit.write('town.txt', '')
  kit.write('case.txt', '')
  town, case, prep = nil, nil, nil
  prefs.mode = 'career'
  save()
  screen = 'title'
end

SCREENS.settings = {
  draw = function(gg)
    header(gg, 'Settings', 'They apply from the next case')
    local y = 100
    gg:text(16, y, 'Case length', { font = kit.font('medium') })
    y = y + 34
    button(gg, 16, y, 200, 52, 'Short', function() prefs.size = 'short'; save() end, { line_width = prefs.size == 'short' and 4 or 1 })
    button(gg, 232, y, 200, 52, 'Long', function() prefs.size = 'long'; save() end, { line_width = prefs.size == 'long' and 4 or 1 })
    y = y + 60
    para(gg, 'Short: 4 suspects, about 25 minutes. Long: 6 suspects and false trails, about an hour.', 16, y, y + 50)
    y = y + 70
    gg:text(16, y, 'Play', { font = kit.font('medium') })
    y = y + 34
    button(gg, 16, y, 200, 52, 'Career', function() prefs.mode = 'career'; save() end, { line_width = prefs.mode == 'career' and 4 or 1 })
    button(gg, 232, y, 200, 52, 'Single cases', function() prefs.mode = 'single'; save() end,
      { line_width = prefs.mode == 'single' and 4 or 1 })
    y = y + 60
    para(gg, 'Career: one town that remembers, and rank. Single cases: a new town every time.', 16, y, y + 50)
    y = y + 90
    button(gg, 16, y, W - 32, 52, 'Reset career', function()
      box('Reset the career?', { 'The town, its people and your rank will be lost. This cannot be undone.' },
        { { { 'Reset', function() kit.close(); reset_career() end }, { 'Cancel', kit.close } } })
    end)
    bottom_row(gg, { { 'Back', function() screen = (from == 'case' and case) and 'case' or 'title' end } })
  end,
  back = function() screen = (from == 'case' and case) and 'case' or 'title'; return true end,
}

after_strike = function()
  local intro = text().intro(case, town)
  local function go() kit.close(); screen = 'case' end
  kit.show({ title = 'The killer strikes again', lines = { intro[#intro], 'You have one more day.' },
             rows = { { { 'Go on', go } } }, cancel = go })
end

------------------------------------------------------------------ host callbacks

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    gg:clear(0)
    hits = {}
    SCREENS[screen].draw(gg)
    if kit.modal() then hits = {}; kit.draw_modal(gg) end
    if ERR then gg:text(12, H - 28, kit.short('ERR ' .. ERR, 48), { font = kit.font('small') }) end
  end)
  if not ok then pcall(function() gg:text(12, H - 28, kit.short('ERR ' .. tostring(e), 48), { font = kit.font('small') }) end) end
end

local function tap(x, y)
  if kit.tap_modal(x, y) then return end
  for k = #hits, 1, -1 do
    local h = hits[k]
    if x >= h.x and x < h.x + h.w and y >= h.y and y < h.y + h.h then h.fn(); return end
  end
end

function on_input(c, ev)
  ERR = nil
  local handled = true
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    if ev.type == 'pointer' and ev.phase == 'up' then
      tap(ev.x or 0, ev.y or 0)
      kit.refresh()
    elseif ev.type == 'key' and ev.key == 'back' then
      -- Back acts on its release (the host reads only the up event's answer): it closes a box or
      -- goes back a screen; on the title it is left to the host, which offers to exit
      if ev.phase ~= 'up' and ev.phase ~= nil then return end
      if kit.modal() then
        if kit.modal().cancel then kit.modal().cancel() end
      else
        handled = SCREENS[screen].back() ~= false
      end
      kit.refresh()
    end
  end)
  if not ok then ERR = tostring(e); kit.refresh() end
  return handled
end

local function load()
  prefs = S.decode(kit.read('prefs.txt')) or { size = 'short', mode = 'career' }
  local rec = S.decode(kit.read('case.txt'))
  town = (rec and rec.town) or S.decode(kit.read('town.txt'))
  case, prep, screen = nil, nil, 'title'
  if rec and rec.prep and town then begin(rec.prep)
  elseif rec and rec.case and town then case = rec.case end
end

function on_load(c)
  local ok, e = pcall(load)
  if not ok then ERR = tostring(e) end
end

function on_leave() pcall(save) end

if rawget(_G, '__TEST') then
  __TEST.api = {
    screen = function() return screen end,
    town = function() return town end,
    case = function() return case end,
    mod = mod,
    act_left = function() return act_left() end,
    place_of = function(pid) return place_of(pid) end,
    prefs = function() return prefs end,
  }
end
