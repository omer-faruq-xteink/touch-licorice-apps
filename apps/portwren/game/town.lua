-- Port Wren: the town. Made once from a seed (24 people, 10 places, their relationships), it keeps
-- what happened: the dead and the jailed leave, families remember, newcomers move in when fewer than
-- 20 are left. Rank comes from reputation and opens the harder kinds of case.
--
--   local W = require('game.town')(T, R)

return function(T, R)
  local W = {}
  local MIN_ALIVE, START = 20, 24

  local function has(list, v)
    for _, x in ipairs(list) do if x == v then return true end end
    return false
  end

  local function pick_places(r)
    local rest = {}
    for _, k in ipairs(T.PLACE_KEYS) do if not has(T.ALWAYS, k) then rest[#rest + 1] = k end end
    r:shuffle(rest)
    local out = {}
    for _, k in ipairs(T.ALWAYS) do out[#out + 1] = k end
    for i = 1, 10 - #T.ALWAYS do out[#out + 1] = rest[i] end
    return out
  end

  local LIVES_AT_WORK = { inn = true, lighthouse = true, boarding = true, cottages = true }

  local function name_taken(town, name)
    for _, p in pairs(town.people) do if p.name == name then return true end end
    return false
  end

  -- a new person working at `work` (or at a place of the town picked at random)
  local function add_person(town, r, work)
    local sex = r:chance(0.5) and 'f' or 'm'
    local name
    repeat
      name = r:pick(sex == 'f' and T.FEMALE or T.MALE) .. ' ' .. r:pick(T.SURNAMES)
    until not name_taken(town, name)
    work = work or r:pick(town.places)
    local job = r:pick(T.PLACES[work].jobs)
    local home = work
    if not LIVES_AT_WORK[work] then
      home = (has(town.places, 'boarding') and r:chance(0.4)) and 'boarding' or 'cottages'
    end
    local t1 = r:pick(T.TRAITS)
    local t2
    repeat t2 = r:pick(T.TRAITS) until t2 ~= t1
    local p = { id = town.next_id, name = name, sex = sex, job = job, work = work, home = home, traits = { t1, t2 },
                trust = r:int(40, 60), status = 'alive', hist = {} }
    town.people[p.id] = p
    town.next_id = town.next_id + 1
    return p
  end

  function W.related(town, a, b)
    for _, rl in ipairs(town.rel) do
      if (rl.a == a and rl.b == b) or (rl.a == b and rl.b == a) then return rl.k end
    end
    return nil
  end

  local function spouse_of(town, pid)
    for _, rl in ipairs(town.rel) do
      if rl.k == 'spouse' and (rl.a == pid or rl.b == pid) then return rl.a == pid and rl.b or rl.a end
    end
    return nil
  end

  function W.family(town, pid)
    local out = {}
    for _, rl in ipairs(town.rel) do
      if (rl.k == 'spouse' or rl.k == 'sibling') and (rl.a == pid or rl.b == pid) then
        out[#out + 1] = rl.a == pid and rl.b or rl.a
      end
    end
    return out
  end

  local function relate(town, r, p)
    local others = W.living(town)
    for _ = 1, 6 do
      local q = town.people[r:pick(others)]
      local k = r:pick(T.REL_KINDS)
      local ok = q.id ~= p.id and not W.related(town, p.id, q.id)
      if ok and k == 'spouse' then ok = p.sex ~= q.sex and not spouse_of(town, p.id) and not spouse_of(town, q.id) end
      if ok and k == 'lover' then ok = p.sex ~= q.sex end
      if ok and k == 'employer' then ok = p.work == q.work end
      if ok then
        -- debtor: a owes b; employer: a employs b
        town.rel[#town.rel + 1] = { a = p.id, b = q.id, k = k }
        return
      end
    end
  end

  function W.make(seed, mode)
    local r = R.new(seed)
    local town = { v = 1, seed = seed, mode = mode or 'career', people = {}, rel = {}, places = pick_places(r),
                   rep = 0, rank = 1, solved = 0, partial = 0, lost = 0, case_no = 0, next_id = 1, size = 'short' }
    for i = 1, START do add_person(town, r, i <= #town.places and town.places[i] or nil) end
    for id = 1, START do
      relate(town, r, town.people[id])
      if r:chance(0.5) then relate(town, r, town.people[id]) end
    end
    return town
  end

  function W.living(town)
    local out = {}
    for id = 1, town.next_id - 1 do
      local p = town.people[id]
      if p and p.status == 'alive' then out[#out + 1] = id end
    end
    return out
  end

  function W.fill(town, r)
    while #W.living(town) < MIN_ALIVE do add_person(town, r) end
  end

  -- where a person is in each part of a day: at work in the morning and the afternoon, out in the
  -- evening (the inn, the chapel or home), home at night
  function W.schedule(town, pid, r)
    local p = town.people[pid]
    local evening = r:pick({ 'inn', 'inn', p.home, has(town.places, 'chapel') and 'chapel' or p.home })
    return { p.work, p.work, evening, p.home }
  end

  function W.trust(town, pid, delta)
    local p = town.people[pid]
    p.trust = math.max(0, math.min(100, p.trust + delta))
  end

  local function remember(town, pid, entry)
    local h = town.people[pid].hist
    h[#h + 1] = entry
  end

  -- after a case: the dead and the convicted leave, their families remember, newcomers arrive
  function W.after_case(town, case)
    local no = case.no or town.case_no
    local dead = { case.victim }
    if case.night2 then dead[#dead + 1] = case.night2.victim end
    for _, v in ipairs(dead) do
      town.people[v].status = 'dead'
      local sp = spouse_of(town, v)
      for _, f in ipairs(W.family(town, v)) do
        remember(town, f, { case = no, what = f == sp and 'widowed' or 'bereaved', who = v })
      end
    end
    if case.over == 'lost' and town.people[case.killer].status == 'alive' then
      -- the killer fled the town
      town.people[case.killer].status = 'gone'
      for _, f in ipairs(W.family(town, case.killer)) do
        remember(town, f, { case = no, what = 'fled', who = case.killer })
      end
    end
    if case.over == 'solved' or case.over == 'partial' then
      town.people[case.killer].status = 'jailed'
      for _, f in ipairs(W.family(town, case.killer)) do
        remember(town, f, { case = no, what = 'arrested', who = case.killer })
        W.trust(town, f, -15)
      end
    end
    W.fill(town, R.new(R.mix(town.seed, no * 7 + 1)))
    W.prune(town)
  end

  -- drop the dead, jailed and gone whom no one alive remembers, and the relationships they leave,
  -- so the saved town does not grow case after case
  function W.prune(town)
    local keep = {}
    for id = 1, town.next_id - 1 do
      local p = town.people[id]
      if p and p.status == 'alive' then
        keep[id] = true
        for _, h in ipairs(p.hist) do if h.who then keep[h.who] = true end end
      end
    end
    for id = 1, town.next_id - 1 do
      if town.people[id] and not keep[id] then town.people[id] = nil end
    end
    local rel = {}
    for _, rl in ipairs(town.rel) do
      if town.people[rl.a] and town.people[rl.b] then rel[#rel + 1] = rl end
    end
    town.rel = rel
  end

  local THRESHOLDS = { 0, 30, 80, 160 }
  function W.rank_of(rep)
    local rank = 1
    for k, v in ipairs(THRESHOLDS) do if rep >= v then rank = k end end
    return rank
  end

  -- the kinds of case open to the player: Classic first, False alibi and Timeline from Sergeant,
  -- Innocent liar from Inspector (Long cases only); single cases have them all
  function W.patterns(town, size)
    local rank = town.mode == 'single' and 4 or town.rank
    local out = { 'classic' }
    if rank >= 2 then out[#out + 1] = 'alibi'; out[#out + 1] = 'timeline' end
    if rank >= 3 and size == 'long' then out[#out + 1] = 'liar' end
    return out
  end

  return W
end
