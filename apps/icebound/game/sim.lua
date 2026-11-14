-- Icebound: the expedition as a whole. A new expedition (the mission, never the last one; the region;
-- the season; the team, with a veteran; the supplies), the morning's event, the day's march with the
-- mission's progress, the actions (a depot, a dog, the radio, turning back, a climb), the warnings, and
-- the end with its score.
--
--   local S = require('game.sim')(Rng, G, R, TM, E, T, EL)

return function(Rng, G, R, TM, E, T, EL)
  local S = {}
  S.DAYS = { easy = 68, normal = 56, hard = 50 }
  S.SUPPLIES = {
    easy = { food = 300, fuel = 75, dogfood = 520, dogs = 12, sledges = 3 },
    normal = { food = 236, fuel = 58, dogfood = 430, dogs = 12, sledges = 3 },
    hard = { food = 210, fuel = 52, dogfood = 380, dogs = 11, sledges = 3 },
  }
  S.KM = 10                          -- a tile

  local MISSION_NAME = { crossing = 'the crossing', pole = 'the pole', lost = 'the lost expedition', survey = 'the survey' }
  S.MISSION_NAME = MISSION_NAME

  function S.new(seed, diff, opts)
    opts = opts or {}
    diff = diff or 'normal'
    local r = Rng.new(Rng.mix(seed, 7))
    local choices = {}
    for _, m in ipairs(G.MISSIONS) do if m ~= opts.last_mission then choices[#choices + 1] = m end end
    local mission = choices[r:int(1, #choices)]
    local region = G.make(Rng.mix(seed, 11), mission)
    local sup = {}
    for k, v in pairs(S.SUPPLIES[diff]) do sup[k] = v end
    local st = { v = 1, seed = seed, diff = diff, mission = mission, season = r:chance(0.5) and 'early' or 'late',
                 day = 1, month = 1, days = S.DAYS[diff], region = region, pos = region.start, route = {}, seen = {},
                 frozen = {}, pace = 'steady', ration = 'normal', progress = 0, sup = sup, radio = 'unused', depots = {},
                 phase = 'out', found = {}, team = {}, next_id = 1, flags = {}, pending = {}, extras = { samples = 0, plates = 0 },
                 broken = 0, photo = {}, start_team = 6, recent = {}, cairns_seen = {} }
    st.start_dogs = st.sup.dogs
    TM.make(st, r, opts.veteran)
    st.weather = nil
    R.weather_next(st, r)
    R.reveal(st)
    st.par = S.par(st)
    st.total_left = S.tiles_left(st)
    st.best_left = st.total_left
    S.morning(st, Rng.new(Rng.mix(seed, 3)))
    return st
  end

  -- the days a good expedition needs: the cheapest way's points at a steady pace, plus a week of storms
  function S.par(state)
    local reg = state.region
    local function pts(a, b)
      if a == b then return 0 end
      local p = G.path(reg, a, b, function(i) return R.cost(state, i) end, nil)
      if not p then return 0 end
      local n = 0
      for k = 2, #p do n = n + (R.cost(state, p[k], p[k - 1]) or 0) end
      return n
    end
    local n = pts(reg.start, reg.goal)
    if state.mission == 'pole' then n = n * 2
    elseif state.mission == 'lost' then n = pts(reg.start, reg.targets[1]) + pts(reg.targets[1], reg.goal)
    elseif state.mission == 'survey' then
      local at = reg.start
      n = 0
      for _, t in ipairs(reg.targets) do n = n + pts(at, t); at = t end
      n = n + pts(at, reg.goal)
    end
    return n // R.PACE.steady + 7
  end

  ------------------------------------------------------------------ events

  function S.morning(state, r)
    if state.over or state.event then return end
    local ev, vars = E.pick(EL.defs, state, r, EL.ctx)
    -- a follow-up keeps its first cast; it does not come once one of them is gone
    if ev and ev.followup then
      for k, v in pairs(vars or {}) do
        if type(k) == 'string' and k:sub(-3) == '_id' and not (state.team[v] and state.team[v].alive) then ev = nil; break end
      end
    end
    if ev then state.event = { id = ev.id, vars = vars } end
  end

  function S.event_def(state)
    if not state.event then return nil end
    for _, d in ipairs(EL.defs) do if d.id == state.event.id then return d end end
    return nil
  end

  function S.offered(state)
    local def = S.event_def(state)
    if not def then return {} end
    local out = {}
    for _, k in ipairs(E.choices(def, state, state.event.vars, EL.ctx)) do out[#out + 1] = def.choices[k] end
    return out
  end

  -- the safe answer, or the only answer when there is one and it is no gamble
  function S.back_choice(state)
    local offered = S.offered(state)
    for k, c in ipairs(offered) do if c.back then return k end end
    if #offered == 1 and not offered[1].chance then return 1 end
    return nil
  end

  function S.answer(state, n, r)
    local def = S.event_def(state)
    if not def then state.event = nil; return '' end
    local vars = state.event.vars
    local offered = E.choices(def, state, vars, EL.ctx)
    local k = offered[n] or offered[1]
    local text = E.apply(def, k, state, vars, r, EL.ctx)
    if not def.followup then state.recent = state.recent or {}; state.recent[def.id] = state.day end
    state.event = nil
    return T.fill(text or '', vars)
  end

  ------------------------------------------------------------------ where to go

  -- the tile the expedition is heading for now
  function S.target(state)
    local reg = state.region
    if state.turned then return reg.start end
    if state.mission == 'pole' then return state.phase == 'back' and reg.start or reg.goal end
    if state.mission == 'lost' then
      if not state.found[reg.targets[1]] then return reg.targets[1] end
      return reg.goal
    end
    if state.mission == 'survey' then
      local best, bd
      local x, y = G.xy(state.pos)
      for _, t in ipairs(reg.targets) do
        if not state.found[t] then
          local tx, ty = G.xy(t)
          local d = math.max(math.abs(tx - x), math.abs(ty - y))
          if not best or d < bd then best, bd = t, d end
        end
      end
      return best or reg.goal
    end
    return reg.goal
  end

  local function walk_cost(state) return function(i) return R.cost(state, i) end end

  -- tiles left to the end of the mission (by the cheapest paths over all passable ice): to the target,
  -- then on through the targets still to find (nearest first) and to the goal, or back from the pole
  -- legs between fixed tiles (targets, goal, start) are kept: the ice only changes when a lead freezes
  local legs = { key = nil, t = {} }
  function S.tiles_left(state)
    local reg = state.region
    local c = walk_cost(state)
    local nf = 0
    for _ in pairs(state.frozen) do nf = nf + 1 end
    local key = tostring(state.seed) .. ':' .. state.mission .. ':' .. nf
    if legs.key ~= key then legs.key, legs.t = key, {} end
    local function leg(a, b)
      if a == b then return 0 end
      local fixed = a ~= state.pos
      if fixed and legs.t[a * 1000 + b] then return legs.t[a * 1000 + b] end
      local p = G.path(reg, a, b, c, nil)
      local n = p and (#p - 1) or 0
      if fixed then legs.t[a * 1000 + b] = n end
      return n
    end
    if state.turned then return leg(state.pos, reg.start) end
    if state.mission == 'crossing' then return leg(state.pos, reg.goal) end
    if state.mission == 'pole' then
      if state.phase == 'back' then return leg(state.pos, reg.start) end
      return leg(state.pos, reg.goal) + leg(reg.goal, reg.start)
    end
    local todo = {}
    for _, t in ipairs(reg.targets) do if not state.found[t] then todo[#todo + 1] = t end end
    local at, n = state.pos, 0
    while #todo > 0 do
      local best, bk, bd
      local x, y = G.xy(at)
      for k, t in ipairs(todo) do
        local tx, ty = G.xy(t)
        local d = math.max(math.abs(tx - x), math.abs(ty - y))
        if not best or d < bd then best, bk, bd = t, k, d end
      end
      n = n + leg(at, best)
      at = best
      table.remove(todo, bk)
    end
    return n + leg(at, reg.goal)
  end

  function S.set_route(state, path)
    local prev = state.pos
    for _, i in ipairs(path) do
      local px, py = G.xy(prev)
      local x, y = G.xy(i)
      if math.max(math.abs(px - x), math.abs(py - y)) ~= 1 then return false, 'the route must go tile by tile' end
      if not state.seen[i] then return false, 'you can only plan over ice you have seen' end
      if not R.cost(state, i, prev) then return false, 'that ice cannot be crossed' end
      prev = i
    end
    local out = {}
    for k, i in ipairs(path) do out[k] = i end
    if out[1] ~= (state.route or {})[1] then state.progress = 0 end   -- the way made into the same tile is kept
    state.route = out
    return true, ''
  end

  ------------------------------------------------------------------ actions

  function S.leave_depot(state)
    if state.mission ~= 'pole' or state.phase ~= 'out' or state.turned then return false, 'depots are left on the way to the pole' end
    if state.depots[state.pos] then return false, 'there is a depot here already' end
    R.leave_depot(state, { food = state.sup.food // 3, fuel = state.sup.fuel // 3, dogfood = state.sup.dogfood // 3 })
    return true, ''
  end

  function S.kill_dog(state)
    if state.sup.dogs <= 0 then return false, 'there are no dogs left' end
    state.sup.dogs = state.sup.dogs - 1
    state.sup.dogfood = state.sup.dogfood + 20
    state.sup.food = state.sup.food + 4
    for _, id in ipairs(TM.living(state)) do local p = state.team[id]; p.mood = math.max(0, p.mood - 6) end
    return true, ''
  end

  function S.call_rescue(state)
    if state.radio ~= 'unused' then return false, 'the radio has been used' end
    local r = Rng.new(Rng.mix(state.seed, 500 + state.day))
    state.radio = 'called'
    state.rescue_at = state.day + r:int(3, 6)
    state.route = {}
    return true, ''
  end

  function S.turn_back(state)
    if state.turned then return false, 'you are already heading back' end
    if state.mission == 'pole' and state.phase == 'back' then return false, 'you are on the way home already' end
    state.turned = true
    state.route = {}
    state.progress = 0
    return true, ''
  end

  function S.climb(state)
    local ok, why = R.climb(state)
    if ok then state.camp_day = state.day end
    return ok, why
  end

  ------------------------------------------------------------------ the day

  local function finish(state, kind)
    state.over = kind
    state.pending = {}
    state.event = nil
    state.route = {}
  end

  local function goal_reached(state)
    local reg = state.region
    if state.mission == 'crossing' then return state.pos == reg.goal end
    if state.mission == 'pole' then return state.phase == 'back' and state.pos == reg.start end
    for _, t in ipairs(reg.targets) do if not state.found[t] then return false end end
    return state.pos == reg.goal
  end

  function S.march(state, r)
    if state.over then return state.report or { lines = {} } end
    local pace = state.pace
    local eff = pace
    if state.camp_day == state.day or state.radio == 'called' then eff = 'rest' end
    if eff == 'hard' then
      for _, id in ipairs(TM.living(state)) do
        if TM.refuses(state.team[id]) then eff = 'steady' end
      end
    end
    state.pace = eff
    local reg = state.region
    -- every tile entered: a target found, the pole reached (home now), or the end of the journey
    local function arrive(i, rp)
      for _, t in ipairs(reg.targets) do
        if i == t and not state.found[t] then
          state.found[t] = true
          rp.lines[#rp.lines + 1] = state.mission == 'lost' and 'You have found the lost party\'s last camp, and its journal. Now make for the pick-up point.'
            or 'A survey point is fixed.'
        end
      end
      -- a cairn of the lost party: a note says which way they went, and the way ahead shows
      for _, c in ipairs(reg.cairns) do
        if i == c and not (state.cairns_seen or {})[c] then
          state.cairns_seen = state.cairns_seen or {}
          state.cairns_seen[c] = true
          local camp = reg.targets[1]
          local cx, cy = G.xy(c)
          local tx, ty = G.xy(camp)
          local ns = ty < cy and 'north' or (ty > cy and 'south' or '')
          local ew = tx > cx and 'east' or (tx < cx and 'west' or '')
          local dir = (ns ~= '' and ew ~= '' and math.abs(tx - cx) * 2 >= math.abs(ty - cy)) and (ns .. '-' .. ew) or (ns ~= '' and ns or ew)
          rp.lines[#rp.lines + 1] = 'A cairn of the lost party. A note in a tin says they went on ' .. dir .. '.'
          -- the next stretch of their way comes into sight
          local nx = cx + (tx > cx and 2 or (tx < cx and -2 or 0))
          local ny = cy + (ty > cy and 2 or (ty < cy and -2 or 0))
          nx, ny = math.max(1, math.min(G.W, nx)), math.max(1, math.min(G.H, ny))
          local save = state.pos
          state.pos = G.idx(nx, ny); R.reveal(state, 1); state.pos = save
        end
      end
      if state.mission == 'pole' and state.phase == 'out' and not state.turned and i == reg.goal then
        state.phase = 'back'
        rp.lines[#rp.lines + 1] = 'You have reached the pole. Now for home.'
        return true
      end
      if state.turned then return i == reg.start end
      return goal_reached(state)
    end
    local rep = R.step(state, r, arrive)
    state.pace = pace
    if eff ~= pace and pace == 'hard' and eff == 'steady' then rep.lines[#rep.lines + 1] = 'Someone refused to march hard today.' end
    rep.month = state.day
    TM.day(state, r, rep)
    if not state.turned then
      state.tiles_now = S.tiles_left(state)
      state.best_left = math.min(state.best_left or 999, state.tiles_now)
    end
    state.report = rep
    state.day = state.day + 1
    state.month = state.day
    -- the end
    if #TM.living(state) == 0 then finish(state, 'lost')
    elseif goal_reached(state) and not state.turned then finish(state, 'goal')
    elseif state.turned and state.pos == reg.start then finish(state, 'back')
    elseif state.radio == 'called' and state.day >= (state.rescue_at or 0) then finish(state, 'rescued')
    elseif state.day > state.days then
      finish(state, (state.radio == 'unused' or state.radio == 'called') and 'rescued' or 'lost')
    end
    return rep
  end

  ------------------------------------------------------------------ warnings

  function S.warnings(state, tiles)
    local out = {}
    local left = R.days_left(state)
    local need_days = math.max(1, ((tiles or S.tiles_left(state)) + 1) // 2)
    if left.food <= 3 or left.food < need_days then out[#out + 1] = 'Food for ' .. left.food .. ' day' .. (left.food == 1 and '' or 's') end
    if left.fuel <= 3 or left.fuel < need_days then out[#out + 1] = 'Fuel for ' .. left.fuel .. ' day' .. (left.fuel == 1 and '' or 's') end
    if state.sup.dogs > 0 and (left.dogfood <= 3) then out[#out + 1] = 'Dog food for ' .. left.dogfood .. ' day' .. (left.dogfood == 1 and '' or 's') end
    for _, w in ipairs(TM.warnings(state)) do out[#out + 1] = w end
    local season = state.days - state.day + 1
    if season <= 10 then out[#out + 1] = season .. ' day' .. (season == 1 and '' or 's') .. ' of the season left' end
    if state.sup.dogs == 1 then out[#out + 1] = 'One dog left' end
    if state.sup.sledges == 1 then out[#out + 1] = 'One sledge left' end
    if state.forecast then out[#out + 1] = 'A ' .. state.forecast .. ' is coming' end
    if state.radio == 'called' then
      local n = math.max(0, (state.rescue_at or 0) - state.day)
      out[#out + 1] = 'Rescue in ' .. n .. ' day' .. (n == 1 and '' or 's')
    end
    return out
  end

  ------------------------------------------------------------------ the end

  local function survivors(state) return #TM.living(state) end

  local function lost_names(state)
    local out = {}
    for id = 1, state.next_id - 1 do local p = state.team[id]; if p and not p.alive then out[#out + 1] = p.name end end
    return out
  end

  local function level(state)
    local s = survivors(state)
    if s == (state.start_team or 6) and state.day - 1 <= (state.par or state.days) then return 1 end
    if s >= 4 then return 2 end
    return 3
  end

  -- how far the expedition got, 0..100 (by the fewest tiles it ever had left)
  local function progress(state)
    local total = state.total_left or 0
    if total <= 0 then return 0 end
    return math.max(0, math.min(100, (total - (state.best_left or total)) * 100 // total))
  end

  function S.score(state)
    local s = survivors(state) * (state.over == 'goal' and 100 or 40)
    local found = 0
    for _ in pairs(state.found) do found = found + 1 end
    s = s + found * 30 + (state.extras.samples or 0) * 20 + (state.extras.plates or 0) * 10
    s = s + (state.sup.food + state.sup.fuel + state.sup.dogfood) // 20
    if state.over == 'goal' then s = s + 400 + math.max(0, state.days - state.day) * 8
    elseif state.over == 'back' then s = s + 3 * progress(state) end
    if survivors(state) == (state.start_team or 6) then s = s + (state.over == 'goal' and 100 or progress(state)) end
    return s
  end

  local TITLES = {
    crossing = { 'The great crossing', 'Across the ice', 'A hard-won crossing' },
    pole = { 'To the pole and home again', 'The pole and back', 'The pole, at a cost' },
    lost = { 'The lost found', 'The lost party\'s journal', 'Found, at a cost' },
    survey = { 'The coast is charted', 'The survey is done', 'A survey, at a cost' },
  }

  function S.ending(state)
    local score = S.score(state)
    local lost = lost_names(state)
    local lines = {}
    local kind, lv, title = state.over, nil, nil
    if kind == 'goal' then
      lv = level(state)
      title = TITLES[state.mission][lv]
      lines[#lines + 1] = 'The expedition reached its goal on day ' .. (state.day - 1) .. '.'
    elseif kind == 'back' then
      title = 'Turned back'
      lines[#lines + 1] = #lost > 0 and 'The goal was not reached; you brought the survivors home.'
        or 'The goal was not reached, but you brought the team home.'
    elseif kind == 'rescued' then
      title = 'Rescued'
      lines[#lines + 1] = 'A plane found the camp and flew everyone out. The expedition is over.'
    else
      title = 'Lost on the ice'
      lines[#lines + 1] = 'The ice kept them.'
    end
    if #lost > 0 then lines[#lines + 1] = 'Lost: ' .. table.concat(lost, ', ') .. '.'
    elseif kind ~= 'lost' then lines[#lines + 1] = 'Nobody was lost.' end
    -- what the mission came to
    if state.mission == 'lost' then
      lines[#lines + 1] = state.found[state.region.targets[1]] and 'The lost party\'s camp was found, and its journal.' or 'The lost party\'s camp was never found.'
    elseif state.mission == 'survey' then
      local n = 0
      for _ in pairs(state.found) do n = n + 1 end
      lines[#lines + 1] = n .. ' of ' .. #state.region.targets .. ' survey points were fixed.'
    elseif state.mission == 'pole' and kind ~= 'goal' then
      lines[#lines + 1] = state.phase == 'back' and 'The pole was reached.' or 'The pole was not reached.'
    end
    local sa, pl = state.extras.samples or 0, state.extras.plates or 0
    local brought = {}
    if sa > 0 then brought[#brought + 1] = sa .. ' rock sample' .. (sa == 1 and '' or 's') end
    if pl > 0 then brought[#brought + 1] = pl .. ' photograph' .. (pl == 1 and '' or 's') end
    if #brought > 0 then lines[#lines + 1] = ('Brought back: ' .. table.concat(brought, ', ') .. '.') end
    return { kind = kind, level = lv, title = title, lines = lines, score = score }
  end

  function S.chronicle_entry(state)
    local e = S.ending(state)
    return { mission = state.mission, char = state.region.char, kind = e.kind, level = e.level, title = e.title, score = e.score,
             days = state.day - 1, survivors = survivors(state), diff = state.diff, seed = state.seed }
  end

  -- a survivor to come again on the next expedition (the most skilled), or nil
  function S.veteran(state, r)
    local best
    for _, id in ipairs(TM.living(state)) do
      local p = state.team[id]
      if not best or p.lv > best.lv then best = p end
    end
    if not best or state.over == 'lost' then return nil end
    local mem = { 'came back from ' .. MISSION_NAME[state.mission] }
    if best.mem[#best.mem] then mem[2] = best.mem[#best.mem] end
    return { name = best.name, role = best.role, lv = best.lv, trait = best.trait, mem = mem }
  end

  return S
end
