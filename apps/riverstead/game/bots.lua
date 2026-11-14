-- Riverstead: automated players, used by the balance tests only (never by the game). Each acts on the
-- state for one month: builds, assigns work and trades. Events are answered by the test (first choice).
--
--   sensible: feeds the village with fields on the best land, keeps houses ahead of the people, wood
--             and stone coming, a storehouse and a well early, tools, then follows a way (the one given,
--             or the valley's best);
--   idle:     does nothing at all;
--   fixed:    builds one fixed list in order, wherever it first fits (the "no plan wins everywhere" test).
--
--   local B = require('game.bots')(R, P, S, V)

return function(R, P, S, V)
  local B = {}
  local WAYS = {
    trade = { 'market', 'tradingpost', 'wharf' },
    grain = { 'mill', 'barn', 'bakery' },
    craft = { 'smithy', 'pottery', 'weaving' },
    faith = { 'shrine', 'temple', 'hostel' },
  }

  local function building_sites(state)
    local n = 0
    for _, b in pairs(state.b) do if b.left > 0 then n = n + 1 end end
    return n
  end

  -- the best tile for a kind: the most output for producers, else the open tile nearest the camp,
  -- keeping fertile soil for fields
  local function best_tile(state, kind)
    local v = state.valley
    local cx, cy = V.xy(v.camp)
    local best, score = nil, nil
    for i = 1, 121 do
      if R.can_place(state, kind, i) then
        local s
        local y = R.yield_preview(state, kind, i)
        local out = (y.food or 0) + (y.wood or 0) + (y.stone or 0)
        local x, yy = V.xy(i)
        local dist = math.abs(x - cx) + math.abs(yy - cy)
        if out > 0 then s = out * 10 - dist
        else s = -dist - (v.t[i] == 'fertile' and 20 or 0) end
        if kind == 'field' and V.riverside(v, i) and R.count(state, 'levee') == 0 then s = s - 150 end
        if not score or s > score then best, score = i, s end
      end
    end
    return best
  end

  local function build(state, kind)
    local i = best_tile(state, kind)
    if i then R.place(state, kind, i); return true end
    return false
  end

  local function food_per_year(state)
    local n = 0
    for i, b in pairs(state.b) do
      if b.kind == 'field' or b.kind == 'fisher' then
        local y = R.yield_preview(state, b.kind, i)
        n = n + (y.food or 0)
      end
    end
    return n
  end

  local function eaters(state)
    local n = 0
    for _, p in pairs(state.people) do
      if p.alive and not p.gone then n = n + (p.age < 144 and 6 or 12) end
    end
    return n
  end

  local function best_way(state)
    local v = state.valley
    if v.special then return 'faith' end
    if v.char == 'river' then return 'trade' end
    if v.char == 'hills' or v.char == 'marsh' then return 'craft' end
    return 'grain'
  end

  function B.sensible(state, r, way)
    way = way or state.bot_way or best_way(state)
    state.bot_way = way
    local year = R.year(state.month)
    local pop = R.population(state)
    local houses = R.count(state, 'house')
    for _, b in pairs(state.b) do if b.kind == 'house' and b.left > 0 then houses = houses + 1 end end
    local sites = building_sites(state)
    local function try(kind) if sites < 3 and build(state, kind) then sites = sites + 1; return true end end
    -- the way's next building, once the village stands (it waits for nothing else)
    local function next_way()
      for _, k in ipairs(WAYS[way]) do
        if not R.has(state, k) then
          for _, b in pairs(state.b) do if b.kind == k then return end end
          if build(state, k) then sites = sites + 1 end
          return
        end
      end
    end
    -- food first, with a margin
    if food_per_year(state) < eaters(state) * 16 // 10 + 10 then
      -- food comes before the limit on building sites
      if build(state, 'field') or build(state, 'fisher') then sites = sites + 1 end
    end
    if year >= 2 then next_way() end
    if pop + 2 > houses * 4 then try('house') end
    local wc = R.count(state, 'woodcutter')
    if wc < (year >= 3 and 2 or 1) or (state.res.wood < 20 and wc < 3) then try('woodcutter') end
    if R.count(state, 'quarry') < 1 and state.res.wood >= 15 then try('quarry') end
    if year >= 1 and R.count(state, 'storehouse') < 1 and state.month > 4 then try('storehouse') end
    if year >= 2 and R.count(state, 'well') < 1 then try('well') end
    if state.res.tools * 4 < pop and R.count(state, 'toolmaker') < 1 + pop // 25 and year >= 2 then try('toolmaker') end
    if year >= 2 and R.count(state, 'levee') < 1 then
      for i, b in pairs(state.b) do
        if b.kind == 'field' and V.riverside(state.valley, i) then try('levee'); break end
      end
    end

    if year >= 3 and R.count(state, 'chapel') < 1 then try('chapel') end
    if year >= 3 and R.count(state, 'herbalist') < 1 then try('herbalist') end
    -- trade: buy food when short, sell spare wood
    if R.trade_prices(state) then
      if R.food_months(state) < 3 then R.trade(state, 'food', 10) end
      if state.res.wood > 150 then R.trade(state, 'wood', -20) end
    end
    P.auto_assign(state)
  end

  -- the first choice on offer that keeps four months of food at worst, else the one that risks least food
  function B.answer(state, r)
    if not state.event then return end
    local offered = S.offered(state)
    local need = math.max(1, state.res.food // math.max(1, R.food_months(state)))
    -- the worst case of a choice: its food cost if it works, or if it fails
    local function cost(c) return math.max(-((c.ok and c.ok.food) or 0), -((c.fail and c.fail.food) or 0)) end
    local pick, least = 1, nil
    for n, c in ipairs(offered) do
      if not least or cost(c) < least then pick, least = n, cost(c) end
    end
    for n, c in ipairs(offered) do
      if cost(c) <= 0 or state.res.food - cost(c) >= need * 4 then pick = n; break end
    end
    S.answer(state, pick, r)
  end

  function B.idle(state, r) end

  function B.fixed(state, r, order)
    state.bot_step = state.bot_step or 1
    local kind = order[state.bot_step]
    if kind and building_sites(state) < 2 then
      for i = 1, 121 do
        if R.can_place(state, kind, i) then
          R.place(state, kind, i)
          state.bot_step = state.bot_step + 1
          break
        end
      end
    end
    P.auto_assign(state)
  end

  return B
end
