-- Riverstead: the villagers. The founding families, and every month of their lives: growing older, health
-- (hunger, a crowded winter, a well and a herbalist), happiness (food, a home, the chapel and market, work
-- that fits, their trait), marriage, children (when there is room), death, and leaving after months of
-- unhappiness. Work: Auto-assign fills each building by skill, keeping builders while anything is built.
--
--   local P = require('game.people')(Rng, R, T)

return function(Rng, R, T)
  local P = {}
  local Y = 12                       -- months a year

  local function alive(p) return p.alive and not p.gone end

  function P.living(state)
    local out = {}
    for id = 1, state.next_id - 1 do
      local p = state.people[id]
      if p and alive(p) then out[#out + 1] = id end
    end
    return out
  end

  function P.workers(state)
    local out = {}
    for _, id in ipairs(P.living(state)) do
      if state.people[id].age >= 12 * Y then out[#out + 1] = id end
    end
    return out
  end

  local function name_taken(state, name)
    for _, p in pairs(state.people) do if p.name == name then return true end end
    return false
  end

  local function add(state, r, o)
    local first
    repeat
      first = r:pick(o.sex == 'f' and T.FEMALE or T.MALE)
    until not name_taken(state, first .. ' ' .. o.surname)
    local p = { id = state.next_id, name = first .. ' ' .. o.surname, sex = o.sex, age = o.age, skill = o.skill or r:pick(T.SKILLS),
                lv = o.lv or 1, trait = r:pick(T.TRAITS), health = r:int(70, 95), happy = r:int(50, 70), alive = true,
                story = {}, came = state.month, mother = o.mother, father = o.father, served = 0, sad = 0, last_birth = -99 }
    state.people[p.id] = p
    state.next_id = state.next_id + 1
    return p
  end
  P.add = add

  local function surname_free(state, r)
    local s
    repeat
      s = r:pick(T.SURNAMES)
      local used = false
      for _, p in pairs(state.people) do if p.name:match('(%S+)$') == s then used = true end end
    until not used
    return s
  end

  -- 3 or 4 families, 10-14 people, with at least a farmer, a woodsman and a builder among the adults
  function P.founders(state, r)
    local need = { 'farming', 'wood', 'building' }
    local families = r:int(3, 4)
    local total = 0
    for f = 1, families do
      local surname = surname_free(state, r)
      local dad = add(state, r, { sex = 'm', surname = surname, age = r:int(25, 45) * Y + r:int(0, 11),
                                  skill = need[f * 2 - 1] or nil, lv = r:int(1, 3) })
      local mum = add(state, r, { sex = 'f', surname = surname, age = r:int(22, 40) * Y + r:int(0, 11),
                                  skill = need[f * 2] or nil, lv = r:int(1, 3) })
      dad.spouse, mum.spouse = mum.id, dad.id
      total = total + 2
      local kids = r:int(0, 3)
      for _ = 1, kids do
        if total < 14 - 2 * (families - f) then
          local kid = add(state, r, { sex = r:chance(0.5) and 'f' or 'm', surname = surname, age = r:int(1, 15) * Y,
                                      skill = r:chance(0.5) and dad.skill or mum.skill, mother = mum.id, father = dad.id })
          total = total + 1
          if kid.age < 0 then kid.age = 0 end
        end
      end
    end
    -- often an elder comes too: a grandparent of the first family
    if total < 14 and r:chance(0.6) then
      local first = state.people[1]
      add(state, r, { sex = r:chance(0.5) and 'f' or 'm', surname = first.name:match('(%S+)$'), age = r:int(55, 68) * Y,
                      lv = r:int(2, 4) })
      total = total + 1
    end
    while total < 10 do
      add(state, r, { sex = r:chance(0.5) and 'f' or 'm', surname = surname_free(state, r), age = r:int(18, 35) * Y, lv = 1 })
      total = total + 1
    end
  end

  function P.newcomers(state, r, n, reason)
    local out = {}
    local surname = surname_free(state, r)
    for k = 1, n do
      local p = add(state, r, { sex = r:chance(0.5) and 'f' or 'm', surname = surname,
                                age = (k <= 2 and r:int(18, 40) or r:int(2, 14)) * Y, lv = r:int(1, 2) })
      p.story[#p.story + 1] = 'came in year ' .. R.year(state.month) .. (reason and (', ' .. reason) or '')
      out[#out + 1] = p.id
    end
    return out
  end

  local function siblings(a, b) return a.mother and a.mother == b.mother end

  local function line(rep, s) if rep and rep.lines then rep.lines[#rep.lines + 1] = s end end

  local function job_fits(state, p)
    if type(p.job) ~= 'number' then return p.job == 'build' and p.skill == 'building' end
    local b = state.b[p.job]
    if not b then return false end
    local d = R.BUILD[b.kind]
    return (d.skill and d.skill == p.skill) or (d.trait and d.trait == p.trait) or false
  end

  local function die(state, p, kind, rep, r)
    p.alive = false
    p.job = nil
    p.story[#p.story + 1] = 'died in year ' .. R.year(state.month)
    if p.spouse and state.people[p.spouse] then state.people[p.spouse].spouse = nil end
    line(rep, T.life(kind, { a = p.name }, r))
  end

  -- one month of everyone's lives
  function P.month(state, r, rep)
    local houses = R.count(state, 'house')
    local pop = R.population(state)
    local crowded = pop > houses * 4
    local winter = R.season(state.month) == 'winter'
    local hungry = (rep and rep.hunger or 0) > 0
    local well, herbal = R.has(state, 'well'), false
    for i, b in pairs(state.b) do
      if b.kind == 'herbalist' and b.left == 0 and #R.workers_of(state, i) > 0 then herbal = true end
    end
    local chapel = R.has(state, 'chapel') or R.has(state, 'temple') or R.has(state, 'shrine')
    local market = R.has(state, 'market')
    for _, id in ipairs(P.living(state)) do
      local p = state.people[id]
      p.age = p.age + 1
      -- health
      local loss = 0
      if hungry then loss = loss + 15 end
      if winter and crowded then loss = loss + 5 end
      if p.trait == 'sickly' then loss = loss * 3 // 2 elseif p.trait == 'hardy' then loss = loss // 2 end
      local gain = (not hungry and not (winter and crowded)) and 2 or 0
      if well then gain = gain + 2 end
      if herbal then gain = gain + 3 end
      if p.age > 60 * Y then gain = gain // 2 end
      p.health = math.max(0, math.min(100, p.health - loss + gain))
      -- death: weakness, then age
      local chance = 0
      if p.health < 30 then chance = (30 - p.health) * 60 end            -- per ten thousand
      local years = p.age // Y
      if years >= 60 then chance = chance + (years - 59) * 40 end
      if p.age < 3 * Y and p.health < 40 then chance = chance + 50 end
      if chance > 0 and r:int(1, 10000) <= chance then
        die(state, p, (p.health < 30 and 'died_sick') or 'died_old', rep, r)
      else
        -- happiness drifts a quarter of the way to where life puts it
        local target = 50
        target = target + (hungry and -25 or 8)
        if crowded then target = target - 15 end
        if chapel then target = target + 8 end
        if market then target = target + 5 end
        if job_fits(state, p) then target = target + 6 end
        if p.trait == 'cheerful' then target = target + 10 elseif p.trait == 'quarrelsome' then target = target - 6 end
        if p.trait == 'greedy' and state.res.coin >= 50 then target = target + 6 end
        if p.trait == 'devout' and chapel then target = target + 8 end
        if p.trait == 'lazy' and type(p.job) == 'number' then target = target - 4 end
        target = target + (p.mood or 0)
        target = math.max(0, math.min(100, target))
        p.happy = p.happy + (target - p.happy) // 4
        if p.happy < 25 then p.sad = (p.sad or 0) + 1 else p.sad = 0 end
        if p.sad >= 4 and p.age >= 16 * Y then
          p.gone = true
          p.job = nil
          p.story[#p.story + 1] = 'left in year ' .. R.year(state.month)
          line(rep, T.life('left', { a = p.name }, r))
        end
        -- skill grows with years of fitting work
        if job_fits(state, p) then
          p.served = (p.served or 0) + 1
          if p.served >= 24 and p.lv < 5 then p.lv, p.served = p.lv + 1, 0 end
        end
      end
    end
    -- marriage: an unmarried woman of 18-45 and an unmarried man of 18-50, not siblings
    for _, id in ipairs(P.living(state)) do
      local a = state.people[id]
      if a.sex == 'f' and not a.spouse and a.age >= 18 * Y and a.age <= 45 * Y and r:int(1, 100) <= 4 then
        local best
        for _, id2 in ipairs(P.living(state)) do
          local b = state.people[id2]
          if b.sex == 'm' and not b.spouse and b.age >= 18 * Y and b.age <= 50 * Y and not siblings(a, b) then best = b; break end
        end
        if best then
          a.spouse, best.spouse = best.id, a.id
          a.story[#a.story + 1] = 'married ' .. best.name .. ' in year ' .. R.year(state.month)
          best.story[#best.story + 1] = 'married ' .. a.name .. ' in year ' .. R.year(state.month)
          line(rep, T.life('married', { a = a.name, b = best.name }, r))
        end
      end
    end
    -- children, while the houses have room
    pop = R.population(state)
    for _, id in ipairs(P.living(state)) do
      local m = state.people[id]
      local f = m.spouse and state.people[m.spouse]
      if m.sex == 'f' and f and alive(f) and m.age >= 18 * Y and m.age <= 42 * Y and pop < houses * 4
        and state.month - (m.last_birth or -99) >= 12 and not hungry and r:int(1, 100) <= 7 then
        local surname = f.name:match('(%S+)$')
        local kid = add(state, r, { sex = r:chance(0.5) and 'f' or 'm', surname = surname, age = 0,
                                    skill = r:chance(0.5) and f.skill or m.skill, mother = m.id, father = f.id })
        kid.story[#kid.story + 1] = 'born in year ' .. R.year(state.month)
        m.last_birth = state.month
        pop = pop + 1
        line(rep, T.life('born', { mother = m.name, father = f.name, child = kid.name, surname = surname,
                                   kind = kid.sex == 'f' and 'daughter' or 'son' }, r))
      end
    end
  end

  ------------------------------------------------------------------ work

  function P.assign(state, id, job) state.people[id].job = job end

  -- a building just finished: its places go to the idle and, when nothing is left to build, to the
  -- builders; the best fit first
  function P.fill_slots(state, i)
    local b = state.b[i]
    if not b or b.left > 0 then return end
    local d = R.BUILD[b.kind]
    local free = d.slots - #R.workers_of(state, i)
    if free <= 0 then return end
    local building = false
    for _, x in pairs(state.b) do if x.left > 0 then building = true end end
    local cands = {}
    for _, id in ipairs(P.living(state)) do
      local p = state.people[id]
      if p.age >= 12 * Y and (p.job == nil or (p.job == 'build' and not building)) then cands[#cands + 1] = p end
    end
    local function fits(p) return (d.skill and p.skill == d.skill) or (d.trait and p.trait == d.trait) end
    table.sort(cands, function(x, y)
      local fx, fy = fits(x) and 1 or 0, fits(y) and 1 or 0
      if fx ~= fy then return fx > fy end
      if (x.job == nil) ~= (y.job == nil) then return x.job == nil end
      if x.lv ~= y.lv then return x.lv > y.lv end
      return x.id < y.id
    end)
    for k = 1, math.min(free, #cands) do cands[k].job = i end
  end

  local PRIORITY = { 'field', 'fisher', 'woodcutter', 'quarry', 'toolmaker', 'mill', 'barn', 'bakery', 'herbalist',
                     'market', 'tradingpost', 'wharf', 'smithy', 'pottery', 'weaving', 'chapel', 'temple', 'hostel' }

  -- everyone of working age to the place that fits them best; two builders while anything is being built
  function P.auto_assign(state)
    local free = {}
    for _, id in ipairs(P.living(state)) do
      local p = state.people[id]
      p.job = nil
      if p.age >= 12 * Y then free[#free + 1] = p end
    end
    local function take(test)
      local best, bk
      for k, p in ipairs(free) do
        if test(p) and (not best or p.lv > best.lv) then best, bk = p, k end
      end
      if best then table.remove(free, bk) end
      return best
    end
    local building = false
    for _, b in pairs(state.b) do if b.left > 0 then building = true end end
    if building then
      for _ = 1, 2 do
        local p = take(function(q) return q.skill == 'building' end)
          or take(function(q) return q.skill ~= 'farming' and q.skill ~= 'wood' end) or take(function() return true end)
        if p then p.job = 'build' end
      end
    end
    for _, kind in ipairs(PRIORITY) do
      local d = R.BUILD[kind]
      for i = 1, 121 do
        local b = state.b[i]
        if b and b.kind == kind and b.left == 0 then
          for _s = 1, d.slots do
            local p = take(function(q) return (d.skill and q.skill == d.skill) or (d.trait and q.trait == d.trait) end)
              or take(function() return true end)
            if p then p.job = i end
          end
        end
      end
    end
    -- anyone left helps build
    if building then for _, p in ipairs(free) do p.job = 'build' end end
  end

  return P
end
