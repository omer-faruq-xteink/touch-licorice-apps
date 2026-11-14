-- Icebound: automated players, for the balance tests only. Each acts for one day (route, pace, rations,
-- treatment, actions) before S.march.
--
--   local B = require('game.bots')(G, R, TM, S)

return function(G, R, TM, S)
  local B = {}

  -- the cheapest way towards `target`, over known ice where it can; unknown ice is guessed passable at
  -- twice the flat cost. Only the known part is kept: tomorrow shows more.
  local function plan(state, target, straight)
    if not target or target == state.pos then state.route = {}; return end
    local function cost(i)
      if state.seen[i] then
        local c = R.cost(state, i)
        if not c then return nil end
        return straight and 1 or c
      end
      return straight and 1 or 2 * R.COST.flat
    end
    local p = G.path(state.region, state.pos, target, cost, nil)
    if not p then state.route = {}; return end
    local out = {}
    for k = 2, #p do
      if not state.seen[p[k]] then break end
      out[#out + 1] = p[k]
    end
    if out[1] ~= (state.route or {})[1] then state.progress = 0 end   -- keep the way made into the same tile
    state.route = out
  end

  local function worst(state)
    local best, bs = nil, 0
    for _, id in ipairs(TM.living(state)) do
      local p = state.team[id]
      local s = 0
      for _, v in pairs(p.cond) do s = s + v * v end
      if s > bs then best, bs = p, s end
    end
    return best, bs
  end

  local function tiles_from_start(state)
    local p = G.path(state.region, state.region.start, state.pos, function(i) return R.cost(state, i) or nil end, nil)
    return p and #p - 1 or 0
  end

  -- a cache or depot within 2 known tiles, worth the detour
  local function nearby_cache(state)
    local x, y = G.xy(state.pos)
    local sources = { state.region.caches }
    if state.phase == 'back' or state.turned then sources[2] = state.depots end
    for _, src in ipairs(sources) do
      for i, c in pairs(src) do
        local cx, cy = G.xy(i)
        if i ~= state.pos and state.seen[i] and math.max(math.abs(cx - x), math.abs(cy - y)) <= 2 and next(c) ~= nil then return i end
      end
    end
    return nil
  end

  function B.sensible(state, r)
    if state.event then B.answer(state, r) end
    local left = R.days_left(state)
    local need = math.max(1, (S.tiles_left(state) + 1) // 2)
    -- turn back when the goal is out of reach and home is not; call for help when neither is
    if not state.turned and state.radio == 'unused' and left.food < need then
      local home = math.max(1, (tiles_from_start(state) + 1) // 2)
      if left.food >= home and state.mission ~= 'pole' then S.turn_back(state)
      elseif left.food < 4 then S.call_rescue(state) end
    end
    -- a depot at half-way to the pole
    if state.mission == 'pole' and state.phase == 'out' and not state.flags.bot_depot then
      local back = tiles_from_start(state)
      local to_pole = S.tiles_left(state) - back
      if back >= to_pole and back > 2 then S.leave_depot(state); state.flags.bot_depot = true end
    end
    if left.dogfood <= 2 and state.sup.dogs > 3 then S.kill_dog(state) end
    -- the route
    local target = nearby_cache(state) or S.target(state)
    plan(state, target, false)
    -- pace: rest through storms and grave illness, push when the season runs short
    local w = state.weather.kind
    local _, ws = worst(state)
    local tired = 0
    for _, id in ipairs(TM.living(state)) do if state.team[id].cond.exhaustion >= 2 then tired = tired + 1 end end
    local season_left = state.days - state.day + 1
    local tight = left.food < need + 4 or need > season_left - 4
    if w == 'whiteout' or (w == 'blizzard' and not tight) or ws >= 9 or tired >= 2 then state.pace = 'rest'
    elseif need > season_left - 3 and tired == 0 then state.pace = 'hard'
    else state.pace = 'steady' end
    -- rations by what is left
    if left.food < need + 2 then state.ration = 'short'
    elseif left.food > need * 3 then state.ration = 'full'
    else state.ration = 'normal' end
    local p = worst(state)
    state.treat = p and p.id or nil
  end

  function B.reckless(state, r)
    if state.event then
      local offered = S.offered(state)
      S.answer(state, #offered > 0 and 1 or 1, r)
    end
    plan(state, S.target(state), true)
    state.pace, state.ration = 'hard', 'full'
  end

  function B.fixed(state, r)
    if state.event then B.answer(state, r) end
    plan(state, S.target(state), true)
    state.pace, state.ration = 'steady', 'normal'
  end

  -- the safe answer when there is one, else the first choice
  function B.answer(state, r)
    if not state.event then return end
    S.answer(state, S.back_choice(state) or 1, r)
  end

  return B
end
