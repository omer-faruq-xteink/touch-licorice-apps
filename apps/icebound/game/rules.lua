-- Icebound: the rules. Travel (terrain costs points; a day gives points by pace, weather, dogs and
-- sledges), eating and fuel, sight and the fog, weather in spells with a deepening cold, depots and
-- caches, climbing a nunatak, and what each role does along the way.
--
--   local R = require('game.rules')(Rng, G)

return function(Rng, G)
  local R = {}
  R.TERRAIN = { 'flat', 'sastrugi', 'ridge', 'crevasse', 'water', 'rock', 'slope' }
  R.COST = { flat = 4, sastrugi = 7, ridge = 12, crevasse = 5, slope = 8 }     -- points to enter a tile
  R.SLOPE_DOWN, R.SLOPE_FLAT = 3, 6
  R.PACE = { rest = 0, steady = 10, hard = 14 }                                -- points a day
  R.RATION = { short = 1, normal = 2, full = 3 }                               -- halves of food a person a day
  R.WEATHER = { 'clear', 'overcast', 'wind', 'blizzard', 'whiteout' }
  R.SEASON_TEMP = { early = -14, late = -24 }
  R.DIFF = {
    easy = { storm = 70, cold = 0 },
    normal = { storm = 120, cold = 5 },
    hard = { storm = 135, cold = 7 },
  }
  R.FALL = 14                                                                  -- percent per crevasse tile
  R.BREAK = { ridge = 10, sastrugi = 4 }                                       -- percent: a sledge breaks

  local function alive(p) return p and p.alive end

  -- the living person with a role (the best level), or nil
  function R.role(state, role)
    local best
    for _, p in pairs(state.team) do
      if alive(p) and p.role == role and (not best or p.lv > best.lv) then best = p end
    end
    return best
  end

  function R.living_count(state)
    local n = 0
    for _, p in pairs(state.team) do if alive(p) then n = n + 1 end end
    return n
  end

  ------------------------------------------------------------------ travel

  -- points to enter tile i from where the party stands, or nil when it can't be entered
  function R.cost(state, i, from)
    local reg = state.region
    if not G.passable(reg, state.frozen, i) then return nil end
    local t = reg.t[i]
    if t == 'water' then return R.COST.flat end                                -- a frozen lead
    if t == 'slope' then
      if not reg.up[i] then return R.SLOPE_FLAT end
      local _, fy = G.xy(from or state.pos)
      local _, ty = G.xy(i)
      if ty < fy then return R.COST.slope end                                 -- uphill, northwards
      if ty > fy then return R.SLOPE_DOWN end
      return R.SLOPE_FLAT
    end
    return R.COST[t]
  end

  -- today's points: pace x weather x dogs and sledges x the driver
  function R.power(state)
    local p = R.PACE[state.pace or 'steady'] or 0
    if p == 0 then return 0 end
    local k = state.weather and state.weather.kind
    if k == 'whiteout' then return 0 end
    if k == 'blizzard' then p = p // 3 elseif k == 'wind' then p = p * 3 // 4 end
    local s = state.sup
    if s.dogs == 0 or s.sledges == 0 then p = p // 2                        -- man-hauling
    elseif s.dogs < 6 then p = p * 2 // 3 end
    if (state.broken or 0) > 0 and s.sledges > 0 then p = p * 3 // 4 end    -- overloaded until the sledge is mended
    local driver = R.role(state, 'driver')
    if driver and s.dogs > 0 then p = p * (100 + 5 * driver.lv) // 100 end
    return math.max(1, p)
  end

  ------------------------------------------------------------------ sight

  function R.sight(state)
    if state.climbed == state.day then
      local nav = R.role(state, 'navigator')
      return (nav and nav.lv >= 3) and 5 or 4
    end
    local k = state.weather and state.weather.kind
    if k == 'blizzard' or k == 'whiteout' then return 1 end
    local s = k == 'clear' and 3 or 2
    local nav = R.role(state, 'navigator')
    if nav and nav.lv >= 3 then s = s + 1 end
    return s
  end

  function R.reveal(state, radius)
    radius = radius or R.sight(state)
    local x, y = G.xy(state.pos)
    for dy = -radius, radius do
      for dx = -radius, radius do
        local nx, ny = x + dx, y + dy
        if nx >= 1 and nx <= G.W and ny >= 1 and ny <= G.H then state.seen[G.idx(nx, ny)] = true end
      end
    end
  end

  -- a day climbing a nunatak next to the party: no march, and far sight from the top
  function R.climb(state)
    local next_to = false
    for _, j in ipairs(G.around(state.pos)) do if state.region.t[j] == 'rock' then next_to = true end end
    if not next_to then return false, 'there is no nunatak to climb here' end
    state.climbed = state.day
    R.reveal(state)
    -- a nunatak gives its sample and its plate once
    state.climbed_rocks = state.climbed_rocks or {}
    local new = false
    for _, j in ipairs(G.around(state.pos)) do
      if state.region.t[j] == 'rock' then
        if not state.climbed_rocks[j] then new = true end
        state.climbed_rocks[j] = true
      end
    end
    if new and R.role(state, 'geologist') then state.extras.samples = state.extras.samples + 1 end
    if new and R.role(state, 'photographer') then state.extras.plates = state.extras.plates + 1 end
    return true, ''
  end

  ------------------------------------------------------------------ weather

  local function draw_kind(state, r)
    local storm = R.DIFF[state.diff or 'normal'].storm
    local w = { clear = 32, overcast = 32, wind = 20, blizzard = 11 * storm // 100, whiteout = 4 * storm // 100 }
    local total = 0
    for _, k in ipairs(R.WEATHER) do total = total + w[k] end
    local x = r:int(1, total)
    for _, k in ipairs(R.WEATHER) do
      x = x - w[k]
      if x <= 0 then return k end
    end
    return 'overcast'
  end

  local function temp_for(state, kind, r)
    local base = R.SEASON_TEMP[state.season or 'early'] - R.DIFF[state.diff or 'normal'].cold - (state.day or 1) // 3
    local adj = ({ clear = -6, overcast = 0, wind = -3, blizzard = -2, whiteout = 2 })[kind] or 0
    return base + adj + r:int(-3, 3)
  end

  -- the next day's weather: the spell goes on, or a new one starts (2-5 days); a navigator of level 2+
  -- names a blizzard or whiteout coming tomorrow
  function R.weather_next(state, r)
    local w = state.weather
    if not w or not w.kind then
      w = { kind = draw_kind(state, r), left = r:int(2, 5) }
      w.next = draw_kind(state, r)
    elseif w.left > 1 then
      w.left = w.left - 1
    else
      w.kind = w.next or draw_kind(state, r)
      local storm = w.kind == 'blizzard' or w.kind == 'whiteout'
      w.left = storm and r:int(2, 3) or r:int(2, 5)
      -- a storm is followed by calmer weather, never by another storm
      repeat w.next = draw_kind(state, r) until not storm or (w.next ~= 'blizzard' and w.next ~= 'whiteout')
      if w.next == w.kind and r:chance(0.5) then w.next = draw_kind(state, r) end
    end
    w.temp = temp_for(state, w.kind, r)
    w.wind = ({ clear = 5, overcast = 10, wind = 30, blizzard = 45, whiteout = 25 })[w.kind] + r:int(0, 9)
    state.weather = w
    state.forecast = nil
    local nav = R.role(state, 'navigator')
    if w.left == 1 and nav and nav.lv >= 2 and (w.next == 'blizzard' or w.next == 'whiteout') then state.forecast = w.next end
  end

  ------------------------------------------------------------------ supplies

  local function add(state, k, n, rep)
    local before = state.sup[k]
    state.sup[k] = math.max(0, before + n)
    rep.delta[k] = (rep.delta[k] or 0) + state.sup[k] - before
    return state.sup[k] - before
  end

  -- what a day costs at the present rations and cold
  function R.needs(state)
    local halves = 0
    for _, p in pairs(state.team) do if alive(p) then halves = halves + (R.RATION[state.ration or 'normal'] or 2) end end
    local food = (halves + 1) // 2
    if R.role(state, 'cook') then food = food - food // 6 end
    local temp = state.weather and state.weather.temp or -20
    local fuel = 1 + math.max(0, (-temp - 20) // 10)
    return { food = food, fuel = fuel, dogfood = state.sup.dogs }
  end

  function R.days_left(state)
    local n = R.needs(state)
    local function d(have, need) if need <= 0 then return 99 end return have // need end
    return { food = d(state.sup.food, n.food), fuel = d(state.sup.fuel, n.fuel), dogfood = d(state.sup.dogfood, n.dogfood) }
  end

  function R.leave_depot(state, amounts)
    local d = state.depots[state.pos] or { food = 0, fuel = 0, dogfood = 0 }
    for _, k in ipairs({ 'food', 'fuel', 'dogfood' }) do
      local n = math.min(amounts[k] or 0, state.sup[k])
      state.sup[k] = state.sup[k] - n
      d[k] = (d[k] or 0) + n
    end
    state.depots[state.pos] = d
  end

  -- take a depot or a cache on tile i; returns a line saying what was found, or nil when there was none
  function R.take(state, i)
    local said
    for n, src in ipairs({ state.depots, state.region.caches }) do
      local c = src[i]
      if c then
        local parts = {}
        for _, k in ipairs({ 'food', 'fuel', 'dogfood' }) do
          if (c[k] or 0) > 0 then
            state.sup[k] = state.sup[k] + c[k]
            parts[#parts + 1] = c[k] .. ' ' .. (k == 'dogfood' and 'dog food' or k)
          end
        end
        src[i] = nil
        if n == 1 then said = 'You pick up your depot: ' .. table.concat(parts, ', ') .. '.'
        elseif #parts > 0 then said = 'An old cache: ' .. table.concat(parts, ', ') .. '.'
        else said = said or 'The cache is empty.' end
      end
    end
    return said
  end

  -- a sledge breaks: with a mechanic it is kept, load and all, to be mended on a camp day; without one
  -- it is left behind with its share of the load
  function R.break_sledge(state, rep)
    local s = state.sup
    if s.sledges <= 0 then return end
    local n = s.sledges
    s.sledges = n - 1
    local line
    if R.role(state, 'mechanic') then
      state.broken = (state.broken or 0) + 1
      line = 'A sledge is broken; the mechanic can mend it on a camp day.'
    else
      for _, k in ipairs({ 'food', 'fuel', 'dogfood' }) do
        local lose = s[k] // n
        s[k] = s[k] - lose
        if rep and rep.delta then rep.delta[k] = (rep.delta[k] or 0) - lose end
      end
      line = 'A sledge is broken beyond repair; its load is left behind.'
    end
    if rep then
      if rep.delta then rep.delta.sledges = (rep.delta.sledges or 0) - 1 end
      rep.lines = rep.lines or {}
      rep.lines[#rep.lines + 1] = line
    end
  end

  ------------------------------------------------------------------ the day

  -- one day: move along the route, eat, burn fuel, the roles' work, the weather; returns the report.
  -- arrive(i, rep), when given, is told of every tile entered; when it returns true the march stops there.
  function R.step(state, r, arrive)
    local rep = { delta = {}, moved = 0, lines = {}, falls = {}, hunger = false, cold = false, found = {} }
    local power = R.power(state)
    local surveyor = R.role(state, 'surveyor')
    local photographer = R.role(state, 'photographer')
    while power > 0 and state.route and #state.route > 0 do
      local nxt = state.route[1]
      local c = R.cost(state, nxt)
      if not c then
        local t = state.region.t[nxt]
        rep.lines[#rep.lines + 1] = (t == 'water') and 'Open water blocks the way; the route ends here.'
          or 'Rock bars the way; the route ends here.'
        state.route = {}
        state.progress = 0
        break
      end
      if (state.progress or 0) + power >= c then
        power = power - (c - (state.progress or 0))
        state.progress = 0
        state.pos = nxt
        table.remove(state.route, 1)
        rep.moved = rep.moved + 1
        R.reveal(state)
        if state.region.t[nxt] == 'crevasse' then
          local risk = R.FALL
          if surveyor then risk = risk // 2 end
          if state.pace == 'hard' then risk = risk + 3 end
          if r:int(1, 100) <= risk then rep.falls[#rep.falls + 1] = nxt end
        end
        local br = R.BREAK[state.region.t[nxt]]
        if br and state.sup.sledges > 0 then
          if state.pace == 'hard' then br = br * 3 // 2 end
          if r:int(1, 100) <= br then R.break_sledge(state, rep) end
        end
        if photographer and not state.photo[nxt] then
          for _, list in ipairs({ state.region.cairns, state.region.targets }) do
            for _, j in ipairs(list) do
              if j == nxt then state.photo[nxt] = true; state.extras.plates = state.extras.plates + 1 end
            end
          end
        end
        local said = R.take(state, nxt)
        if said then rep.found[#rep.found + 1] = nxt; rep.lines[#rep.lines + 1] = said end
        if arrive and arrive(nxt, rep) then
          state.route = {}
          state.progress = 0
          break
        end
      else
        state.progress = (state.progress or 0) + power
        power = 0
      end
    end
    -- a camp day: the hunter by open water, the mechanic at a broken sledge
    if state.pace == 'rest' then
      local hunter = R.role(state, 'hunter')
      if hunter then
        local water = false
        for _, j in ipairs(G.around(state.pos)) do if state.region.t[j] == 'water' and not state.frozen[j] then water = true end end
        if water then
          add(state, 'food', 6 + 2 * hunter.lv, rep); add(state, 'dogfood', 8 + 2 * hunter.lv, rep)
          rep.lines[#rep.lines + 1] = 'The hunter brings in seal meat.'
        end
      end
      if (state.broken or 0) > 0 and R.role(state, 'mechanic') then
        state.broken = state.broken - 1
        add(state, 'sledges', 1, rep)
        rep.lines[#rep.lines + 1] = 'The broken sledge is mended.'
      end
    end
    -- eating and fuel
    local n = R.needs(state)
    if state.sup.food < n.food then rep.hunger = true end
    add(state, 'food', -n.food, rep)
    if state.sup.fuel < n.fuel then rep.cold = true end
    add(state, 'fuel', -n.fuel, rep)
    if state.sup.dogfood < n.dogfood and state.sup.dogs > 0 then
      add(state, 'dogs', -1, rep)
      rep.lines[#rep.lines + 1] = 'A starving dog has died.'
    end
    add(state, 'dogfood', -n.dogfood, rep)
    R.weather_next(state, r)
    R.reveal(state)
    return rep
  end

  return R
end
