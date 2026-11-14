-- Riverstead: the rules. What every building costs, where it may stand, how many work there and what it
-- makes; the calendar and its seasons; one month of production, construction, eating, spoilage and
-- storage; floods on the riverside and the levees that hold them back.
--
-- A building's output is its base times the terrain, its workers (each 0.5 + 0.1 per skill level, +0.2
-- when the skill fits), tools (x1.25 with a tool for every four people) and the season.
--
--   local R = require('game.rules')(Rng, V)

return function(Rng, V)
  local R = {}
  R.TERRAIN = { 'meadow', 'fertile', 'forest', 'rock', 'marsh', 'river' }
  R.RES = { 'food', 'wood', 'stone', 'tools', 'coin' }

  ------------------------------------------------------------------ calendar

  -- month 1 is March of year 1
  function R.moy(month) return (month + 1) % 12 + 1 end
  function R.year(month) return (month - 1) // 12 + 1 end
  function R.season(month)
    local m = R.moy(month)
    if m >= 3 and m <= 5 then return 'spring' end
    if m >= 6 and m <= 8 then return 'summer' end
    if m >= 9 and m <= 11 then return 'autumn' end
    return 'winter'
  end
  local function sowing(month) local m = R.moy(month); return m >= 3 and m <= 5 end
  local function harvest_month(month) local m = R.moy(month); return m == 9 or m == 10 end

  ------------------------------------------------------------------ placing

  local function land(v, i) return (v.t[i] == 'meadow' or v.t[i] == 'fertile') and i ~= v.special end
  local function anywhere(v, s, i) return land(v, i) end
  local function riverside(v, s, i) return land(v, i) and V.riverside(v, i) end

  R.BUILD = {
    house = { name = 'House', cost = { wood = 12, stone = 2 }, months = 2, slots = 0, place = anywhere },
    field = { name = 'Field', cost = { wood = 4 }, months = 1, slots = 2, place = anywhere, skill = 'farming' },
    fisher = { name = 'Fisher\'s hut', cost = { wood = 6 }, months = 1, slots = 1, place = riverside, skill = 'farming' },
    -- the woodcutter costs nothing, so a village that has run out of wood can always get it back
    woodcutter = { name = 'Woodcutter', cost = {}, months = 1, slots = 2, skill = 'wood',
                   place = function(v, s, i) return land(v, i) and V.near(v, i, 'forest', 1) > 0 end },
    quarry = { name = 'Quarry', cost = { wood = 8 }, months = 1, slots = 2, skill = 'building',
               place = function(v, s, i) return (v.t[i] == 'rock') or (land(v, i) and V.near(v, i, 'rock', 1) > 0) end },
    toolmaker = { name = 'Toolmaker', cost = { wood = 10, stone = 6 }, months = 2, slots = 1, place = anywhere, skill = 'crafting' },
    storehouse = { name = 'Storehouse', cost = { wood = 15, stone = 8 }, months = 2, slots = 0, place = anywhere },
    well = { name = 'Well', cost = { stone = 8 }, months = 1, slots = 0, place = anywhere },
    herbalist = { name = 'Herbalist', cost = { wood = 8, stone = 4 }, months = 1, slots = 1, place = anywhere, skill = 'healing' },
    chapel = { name = 'Chapel', cost = { wood = 12, stone = 10 }, months = 3, slots = 1, place = anywhere, trait = 'devout' },
    levee = { name = 'Levee', cost = { stone = 6 }, months = 1, slots = 0, place = riverside },
    -- the four ways
    market = { name = 'Market', cost = { wood = 15, stone = 10 }, months = 2, slots = 1, place = anywhere, skill = 'trade',
               way = 'trade', tier = 1 },
    tradingpost = { name = 'Trading post', cost = { wood = 30, stone = 25, tools = 8, coin = 15 }, months = 3, slots = 2, place = anywhere,
                    skill = 'trade', way = 'trade', tier = 2, needs = 'market' },
    wharf = { name = 'Wharf', cost = { wood = 60, stone = 50, tools = 15, coin = 60 }, months = 5, slots = 2, place = riverside,
              skill = 'trade', way = 'trade', tier = 3, needs = 'tradingpost' },
    mill = { name = 'Mill', cost = { wood = 15, stone = 10 }, months = 2, slots = 1, skill = 'farming', way = 'grain', tier = 1,
             place = function(v, s, i) return v.t[i] == 'river' end },
    barn = { name = 'Great barn', cost = { wood = 30, stone = 25, tools = 6, coin = 15 }, months = 3, slots = 1, place = anywhere, skill = 'farming',
             way = 'grain', tier = 2, needs = 'mill' },
    bakery = { name = 'Bakery', cost = { wood = 50, stone = 50, tools = 15, coin = 60 }, months = 5, slots = 1, place = anywhere,
               skill = 'farming', way = 'grain', tier = 3, needs = 'barn' },
    smithy = { name = 'Smithy', cost = { wood = 10, stone = 12 }, months = 2, slots = 1, place = anywhere, skill = 'crafting',
               way = 'craft', tier = 1 },
    pottery = { name = 'Pottery', cost = { wood = 30, stone = 25, tools = 6, coin = 15 }, months = 3, slots = 1, place = anywhere, skill = 'crafting',
                way = 'craft', tier = 2, needs = 'smithy' },
    weaving = { name = 'Weaving shed', cost = { wood = 60, stone = 40, tools = 15, coin = 60 }, months = 5, slots = 2,
                place = anywhere, skill = 'crafting', way = 'craft', tier = 3, needs = 'pottery' },
    shrine = { name = 'Shrine', cost = { stone = 10 }, months = 2, slots = 0, way = 'faith', tier = 1,
               place = function(v, s, i) return i == v.special end },
    temple = { name = 'Temple', cost = { wood = 25, stone = 40, tools = 6, coin = 15 }, months = 4, slots = 1, place = anywhere, trait = 'devout',
               way = 'faith', tier = 2, needs = 'shrine' },
    hostel = { name = 'Pilgrims\' hostel', cost = { wood = 60, stone = 50, tools = 15, coin = 60 }, months = 5, slots = 1,
               place = anywhere, skill = 'trade', way = 'faith', tier = 3, needs = 'temple' },
  }
  R.ORDER = { 'house', 'field', 'fisher', 'woodcutter', 'quarry', 'toolmaker', 'storehouse', 'well', 'herbalist', 'chapel',
              'levee', 'market', 'tradingpost', 'wharf', 'mill', 'barn', 'bakery', 'smithy', 'pottery', 'weaving',
              'shrine', 'temple', 'hostel' }

  -- base outputs: per harvest month (fields) or per month at a full crew of power 1 per slot
  R.BASE = { field = 48, fisher = 6, woodcutter = 8, quarry = 5 }
  R.DIFF = {
    gentle = { swing = 10, winter = 4, hard = 0.7, flood = 0.10, yield = 115 },
    normal = { swing = 20, winter = 4, hard = 1.0, flood = 0.15, yield = 100 },
    harsh = { swing = 30, winter = 5, hard = 1.4, flood = 0.22, yield = 80 },
  }

  function R.new_state(valley)
    return { v = 1, seed = valley.seed, valley = valley, month = 1, b = {}, res = { food = 0, wood = 0, stone = 0, tools = 0, coin = 0 },
             people = {}, next_id = 1, renown = { trade = 0, grain = 0, craft = 0, faith = 0 }, flags = {}, pending = {},
             diff = 'normal' }
  end

  function R.has(state, kind)
    for _, b in pairs(state.b) do if b.kind == kind and b.left == 0 then return true end end
    return false
  end
  function R.count(state, kind)
    local n = 0
    for _, b in pairs(state.b) do if b.kind == kind and b.left == 0 then n = n + 1 end end
    return n
  end

  function R.can_place(state, kind, i)
    local d = R.BUILD[kind]
    if not d then return false, 'no such building' end
    if state.b[i] then return false, 'the tile is taken' end
    if not d.place(state.valley, state, i) then return false, 'it can\'t stand here' end
    if d.needs and not R.has(state, d.needs) then return false, 'needs a ' .. R.BUILD[d.needs].name:lower() end
    for _, k in ipairs(R.RES) do
      if (d.cost[k] or 0) > state.res[k] then return false, 'not enough ' .. k end
    end
    return true, ''
  end

  function R.place(state, kind, i)
    local d = R.BUILD[kind]
    for _, k in ipairs(R.RES) do state.res[k] = state.res[k] - (d.cost[k] or 0) end
    state.b[i] = { kind = kind, left = d.months * 2, sown = false }
  end

  function R.demolish(state, i)
    state.b[i] = nil
    for _, p in pairs(state.people) do if p.job == i then p.job = nil end end
  end

  -- houses with a tile around them (the 8 next to it) that passes test
  local function houses_where(state, test)
    local n = 0
    for i, b in pairs(state.b) do
      if b.kind == 'house' and b.left == 0 then
        local x, y = V.xy(i)
        local hit = false
        for dy = -1, 1 do for dx = -1, 1 do
          local nx, ny = x + dx, y + dy
          if (dx ~= 0 or dy ~= 0) and nx >= 1 and nx <= 11 and ny >= 1 and ny <= 11 and test(V.idx(nx, ny)) then hit = true end
        end end
        if hit then n = n + 1 end
      end
    end
    return n
  end
  -- houses next to a terrain (the marsh: fevers)
  function R.houses_near(state, terrain)
    return houses_where(state, function(j) return state.valley.t[j] == terrain end)
  end
  -- houses next to a smithy or a quarry: noisy
  R.NOISY = { smithy = true, quarry = true }
  function R.houses_by_noise(state)
    return houses_where(state, function(j) local b = state.b[j]; return (b and b.left == 0 and R.NOISY[b.kind]) or false end)
  end

  ------------------------------------------------------------------ people at work

  local function alive(p) return p.alive and not p.gone end

  -- the people at work on tile i, in id order
  function R.workers_of(state, i)
    local out = {}
    for id = 1, state.next_id - 1 do
      local p = state.people[id]
      if p and alive(p) and p.job == i then out[#out + 1] = p end
    end
    return out
  end

  function R.population(state)
    local n = 0
    for _, p in pairs(state.people) do if alive(p) then n = n + 1 end end
    return n
  end

  -- a crew's strength in tenths: each worker 5 + level (+2 when the skill or trait fits)
  local function power10(state, i)
    local d = R.BUILD[state.b[i].kind]
    local n = 0
    for _, p in ipairs(R.workers_of(state, i)) do
      local f = 5 + p.lv
      if (d.skill and p.skill == d.skill) or (d.trait and p.trait == d.trait) then f = f + 2 end
      n = n + f
    end
    return n
  end
  R.power10 = power10

  -- terrain in percent
  local function terrain_pct(state, kind, i)
    local v = state.valley
    if kind == 'field' then
      local pct = v.t[i] == 'fertile' and 150 or 100
      if V.riverside(v, i) then pct = pct * 13 // 10 end
      return pct
    elseif kind == 'woodcutter' then return 100 + 10 * V.near(v, i, 'forest', 2)
    elseif kind == 'quarry' then return 100 + 10 * V.near(v, i, 'rock', 1) + (v.t[i] == 'rock' and 20 or 0)
    end
    return 100
  end

  local function tools_pct(state)
    local pop = R.population(state)
    if pop > 0 and state.res.tools * 4 >= pop then return 125 end
    return 100
  end

  function R.capacity(state) return 200 + 300 * R.count(state, 'storehouse') end

  -- a building's output at full crew of matched level-1 workers, for the build panel: a year's worth
  function R.yield_preview(state, kind, i)
    local d = R.BUILD[kind]
    local base = R.BASE[kind]
    if not base then return {} end
    local p10 = (5 + 1 + 2) * d.slots
    local per = base * terrain_pct(state, kind, i) * p10 // (100 * 10 * d.slots)
    if kind == 'field' then return { food = per * 2 } end
    if kind == 'fisher' then return { food = per * 9 + per * 3 // 2 } end
    if kind == 'woodcutter' then return { wood = per * 12 } end
    if kind == 'quarry' then return { stone = per * 12 } end
    return {}
  end

  ------------------------------------------------------------------ one month

  -- what really changed goes into the report (stock never falls below zero)
  local function add(state, k, n, rep)
    local before = state.res[k]
    state.res[k] = math.max(0, state.res[k] + n)
    rep.delta[k] = (rep.delta[k] or 0) + state.res[k] - before
  end

  -- production, construction, eating, spoilage and storage for one month
  function R.produce(state, r)
    local rep = { delta = {}, harvest = 0, hunger = 0, built = {}, built_at = {}, lines = {} }
    local month = state.month
    local season = R.season(month)
    local tp = tools_pct(state)
    local dif = R.DIFF[state.diff or 'normal']
    local field_bonus = 100 + 15 * math.min(2, R.count(state, 'mill')) + 15 * R.count(state, 'barn')
    if R.has(state, 'bakery') then field_bonus = field_bonus + 10 end
    -- a harvest swing for the year, the same for every field
    local swing = 100
    if harvest_month(month) then
      local yr = R.year(month)
      local rr = Rng.new(Rng.mix(state.seed, 1000 + yr))
      swing = 100 + rr:int(-dif.swing, dif.swing)
    end
    local workers_total = 0
    -- buildings, in tile order
    for i = 1, 121 do
      local b = state.b[i]
      if b and b.left == 0 then
        local d = R.BUILD[b.kind]
        local p10 = d.slots > 0 and power10(state, i) or 0
        workers_total = workers_total + #R.workers_of(state, i)
        local tpct = terrain_pct(state, b.kind, i)
        if b.kind == 'field' then
          if sowing(month) and p10 > 0 then b.sown = true end
          if harvest_month(month) and b.sown and p10 > 0 then
            local n = R.BASE.field * tpct // 100 * p10 // (10 * d.slots) * tp // 100 * field_bonus // 100 * swing // 100
            if b.flooded then n = n // 2 end                -- a flooded field gives half
            n = n * dif.yield // 100
            add(state, 'food', n, rep)
            rep.harvest = rep.harvest + n
          end
          if R.moy(month) == 11 then b.sown, b.flooded = false, nil end
        elseif b.kind == 'fisher' and p10 > 0 then
          local n = R.BASE.fisher * p10 // (10 * d.slots) * tp // 100
          if season == 'winter' then n = n // 2 end
          add(state, 'food', n * dif.yield // 100, rep)
        elseif (b.kind == 'woodcutter' or b.kind == 'quarry') and p10 > 0 then
          local n = R.BASE[b.kind] * tpct // 100 * p10 // (10 * d.slots) * tp // 100
          if season == 'winter' then n = n * 7 // 10 end
          add(state, b.kind == 'woodcutter' and 'wood' or 'stone', n, rep)
        elseif b.kind == 'toolmaker' and p10 > 0 then
          local n = math.max(1, 3 * p10 // 10)
          n = math.min(n, state.res.wood // 2, state.res.stone)
          if n > 0 then add(state, 'wood', -2 * n, rep); add(state, 'stone', -n, rep); add(state, 'tools', n, rep) end
        elseif b.kind == 'smithy' and p10 > 0 then
          if state.res.stone >= 1 then add(state, 'stone', -1, rep); add(state, 'tools', 1, rep) end
          add(state, 'coin', 1, rep)
        end
      end
    end
    -- tools wear with use: one a month for every twenty at work
    if workers_total >= 20 then add(state, 'tools', -(workers_total // 20), rep) end
    -- construction: builders work on the oldest site first (tile order), each 2 half-months, 3 when skilled
    local power = 0
    for id = 1, state.next_id - 1 do
      local p = state.people[id]
      if p and alive(p) and p.job == 'build' then power = power + (p.skill == 'building' and 3 or 2) end
    end
    for i = 1, 121 do
      local b = state.b[i]
      if b and b.left > 0 and power > 0 then
        local used = math.min(power, b.left)
        b.left = b.left - used
        power = power - used
        if b.left == 0 then rep.built[#rep.built + 1] = b.kind; rep.built_at[#rep.built_at + 1] = i end
      end
    end
    -- eating: adults 2 halves, children 1, a hard winter 5/4 of that
    local halves = 0
    for _, p in pairs(state.people) do
      if alive(p) then halves = halves + (p.age < 144 and 1 or 2) end
    end
    if season == 'winter' then halves = halves * dif.winter // 4 end
    local need = (halves + 1) // 2
    if state.res.food >= need then add(state, 'food', -need, rep)
    else
      rep.hunger = need - state.res.food
      add(state, 'food', -state.res.food, rep)
    end
    -- spoilage and storage
    local spoil = state.res.food * (R.has(state, 'storehouse') and 1 or 3) // 100
    if spoil > 0 then add(state, 'food', -spoil, rep) end
    local cap = R.capacity(state)
    for _, k in ipairs(R.RES) do
      if k ~= 'coin' and state.res[k] > cap then add(state, k, cap - state.res[k], rep) end
    end
    return rep
  end

  -- months of food left in store at the present eating (the coming harvest is not counted)
  function R.food_months(state)
    local halves = 0
    for _, p in pairs(state.people) do
      if alive(p) then halves = halves + (p.age < 144 and 1 or 2) end
    end
    local need = math.max(1, (halves + 1) // 2)
    return state.res.food // need
  end

  -- months until the next harvest month (September); 0 in September and October
  function R.months_to_harvest(month)
    local m = R.moy(month)
    if m == 9 or m == 10 then return 0 end
    return (9 - m) % 12
  end

  -- the warning the village screen shows: food for three months or less, or too little to be sure of
  -- reaching a harvest that is at most five months away (a month's margin, for spoilage and bad luck)
  function R.food_warning(state)
    local fm, mth = R.food_months(state), R.months_to_harvest(state.month)
    return fm <= 3 or (mth > 0 and mth <= 5 and fm <= mth + 1)
  end

  ------------------------------------------------------------------ trade

  -- coin for 10 units (food, wood, stone) or 1 unit (tools); nil before there is a market. Food is dear
  -- in late winter and cheap after the harvest; a trading post buys cheaper and sells dearer
  function R.trade_prices(state)
    if not R.has(state, 'market') then return nil end
    local m = R.moy(state.month)
    local food = 100
    if m >= 1 and m <= 3 then food = 150 elseif m == 10 or m == 11 then food = 70 end
    local post = R.has(state, 'tradingpost')
    local function p(buy, sell, pct)
      buy, sell = buy * pct // 100, sell * pct // 100
      if post then buy, sell = buy * 8 // 10, sell * 12 // 10 end
      return { buy = math.max(1, buy), sell = math.max(1, math.min(sell, math.max(1, buy) - 1)) }
    end
    return { food = p(8, 4, food), wood = p(6, 3, 100), stone = p(8, 4, 100), tools = p(4, 2, 100) }
  end

  R.TRADE_UNIT = { food = 10, wood = 10, stone = 10, tools = 1 }

  -- buy (amount > 0) or sell (amount < 0); true, or false and why
  function R.trade(state, k, amount)
    local pr = R.trade_prices(state)
    if not pr then return false, 'there is no market' end
    local unit = R.TRADE_UNIT[k]
    if not unit or amount == 0 or amount % unit ~= 0 then return false, 'not a trade' end
    local lots = math.abs(amount) // unit
    if amount > 0 then
      local cost = pr[k].buy * lots
      if state.res.coin < cost then return false, 'not enough coin' end
      if state.res[k] + amount > R.capacity(state) then return false, 'no room in storage' end
      state.res.coin = state.res.coin - cost
      state.res[k] = math.min(R.capacity(state), state.res[k] + amount)
    else
      if state.res[k] < -amount then return false, 'not enough ' .. k end
      state.res[k] = state.res[k] + amount
      state.res.coin = state.res.coin + pr[k].sell * lots
    end
    return true, ''
  end

  ------------------------------------------------------------------ floods

  -- the riverside tiles a flood hits (fields lose their harvest); a levee shields what is within 2 of it
  function R.flood(state, r)
    local v = state.valley
    local levees = {}
    for i, b in pairs(state.b) do if b.kind == 'levee' and b.left == 0 then levees[#levees + 1] = i end end
    local hit = {}
    for i = 1, 121 do
      if V.riverside(v, i) then
        local x, y = V.xy(i)
        local safe = false
        for _, l in ipairs(levees) do
          local lx, ly = V.xy(l)
          if math.max(math.abs(x - lx), math.abs(y - ly)) <= 2 then safe = true end
        end
        if not safe and r:chance(0.6) then
          hit[#hit + 1] = i
          local b = state.b[i]
          if b and b.kind == 'field' then b.flooded = true end
        end
      end
    end
    return hit
  end

  return R
end
