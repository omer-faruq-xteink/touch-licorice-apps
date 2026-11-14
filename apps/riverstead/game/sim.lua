-- Riverstead: the game as a whole. A new game (the valley, the founders, two houses at the camp, the
-- starting stock), the month (the event, production, people, floods, renown and coin from the four
-- ways' buildings), the end after the tenth winter or when no one is left, and the score and ending.
--
--   local S = require('game.sim')(Rng, V, R, P, E, T, EL)

return function(Rng, V, R, P, E, T, EL)
  local S = {}
  S.MONTHS = 120

  function S.new(seed, diff)
    local valley = V.make(seed)
    local st = R.new_state(valley)
    st.diff = diff or 'normal'
    local r = Rng.new(Rng.mix(seed, 7))
    st.name = r:pick(T.VILLAGES)
    st.res = { food = 130, wood = 50, stone = 10, tools = 4, coin = 0 }
    P.founders(st, r)
    -- two houses at the camp, built
    local placed = 0
    local camp = valley.camp
    local cx, cy = V.xy(camp)
    for d = 0, 3 do
      for y = cy - d, cy + d do
        for x = cx - d, cx + d do
          if placed < 2 and x >= 1 and x <= 11 and y >= 1 and y <= 11 then
            local i = V.idx(x, y)
            if not st.b[i] and R.BUILD.house.place(valley, st, i) then
              st.b[i] = { kind = 'house', left = 0 }
              placed = placed + 1
            end
          end
        end
      end
    end
    st.famine, st.someone_left = false, false
    P.auto_assign(st)
    return st
  end

  ------------------------------------------------------------------ events

  function S.begin_month(state, r)
    if state.over or state.event then return end
    local ev, vars = E.pick(EL.defs, state, r, EL.ctx)
    if ev then state.event = { id = ev.id, vars = vars } end
  end

  function S.event_def(state)
    if not state.event then return nil end
    for _, d in ipairs(EL.defs) do if d.id == state.event.id then return d end end
    return nil
  end

  -- the choices on offer for the open event, in order
  function S.offered(state)
    local def = S.event_def(state)
    if not def then return {} end
    local out = {}
    for _, k in ipairs(E.choices(def, state, state.event.vars, EL.ctx)) do out[#out + 1] = def.choices[k] end
    return out
  end

  -- the place on offer of the safe answer the Back key gives, or nil when the event waits for a choice
  function S.back_choice(state)
    for k, c in ipairs(S.offered(state)) do if c.back then return k end end
    return nil
  end

  -- the n-th choice on offer; returns the result text
  function S.answer(state, n, r)
    local def = S.event_def(state)
    if not def then state.event = nil; return '' end
    local vars = state.event.vars
    local offered = E.choices(def, state, vars, EL.ctx)
    local k = offered[n] or offered[1]
    local text = E.apply(def, k, state, vars, r, EL.ctx)
    state.event = nil
    return T.fill(text or '', vars)
  end

  ------------------------------------------------------------------ the ways

  local COIN = { market = 1, tradingpost = 2, wharf = 4, mill = 1, barn = 2, bakery = 4, pottery = 3, weaving = 6,
                 shrine = 1, temple = 2, hostel = 5 }

  local function renown_and_coin(state, rep)
    local v = state.valley
    for i = 1, 121 do
      local b = state.b[i]
      if b and b.left == 0 then
        local d = R.BUILD[b.kind]
        local staffed = d.slots == 0 or #R.workers_of(state, i) > 0
        if d.way and staffed then
          local pts = ({ 1, 3, 6 })[d.tier]
          local x10 = 10
          if b.kind == 'tradingpost' then
            for _, f in ipairs(v.ford) do
              local ax, ay = V.xy(i)
              local fx, fy = V.xy(f)
              if math.max(math.abs(ax - fx), math.abs(ay - fy)) <= 2 then x10 = 15 end
            end
          elseif b.kind == 'wharf' then
            if V.near(v, i, 'river', 1) > 0 then
              local x, y = V.xy(i)
              for dy = -1, 1 do for dx = -1, 1 do
                local j = (y + dy >= 1 and y + dy <= 11 and x + dx >= 1 and x + dx <= 11) and V.idx(x + dx, y + dy)
                if j and v.wide[j] then x10 = 15 end
              end end
            end
          elseif b.kind == 'pottery' then
            if V.near(v, i, 'marsh', 2) > 0 then x10 = 15 end
          end
          state.renown[d.way] = state.renown[d.way] + pts * x10 // 10
        end
        local c = COIN[b.kind]
        if c and staffed then
          local n = c
          if b.kind == 'pottery' and V.near(v, i, 'marsh', 2) > 0 then n = n * 3 // 2 end
          state.res.coin = state.res.coin + n
          rep.delta.coin = (rep.delta.coin or 0) + n
        end
      end
    end
  end

  -- the leading way: the one with the most renown among those with a building, else the most renown
  function S.way(state)
    local built = {}
    for _, b in pairs(state.b) do
      local d = R.BUILD[b.kind]
      if b.left == 0 and d.way then built[d.way] = true end
    end
    local best, bn = nil, -1
    for _, w in ipairs({ 'trade', 'grain', 'craft', 'faith' }) do
      if built[w] and state.renown[w] > bn then best, bn = w, state.renown[w] end
    end
    if not best then
      for _, w in ipairs({ 'trade', 'grain', 'craft', 'faith' }) do
        if state.renown[w] > bn then best, bn = w, state.renown[w] end
      end
    end
    local tier = 0
    for _, b in pairs(state.b) do
      local d = R.BUILD[b.kind]
      if b.left == 0 and d.way == best and d.tier > tier then tier = d.tier end
    end
    return best, tier
  end

  ------------------------------------------------------------------ the month

  function S.next_month(state, r)
    if state.over then return state.report or { lines = {} } end
    local month = state.month
    local dif = R.DIFF[state.diff or 'normal']
    local flooded = {}
    local moy = R.moy(month)
    -- a flood comes at most once a spring, never in the first year
    local yr = R.year(month)
    if yr >= 2 and moy >= 4 and moy <= 6 and state.flags.flood_year ~= yr and state.flags.noflood ~= month
      and r:int(1, 1000) <= math.floor(dif.flood * 1000) then
      flooded = R.flood(state, r)
      state.flags.flood_year = yr
    end
    local rep = R.produce(state, r)
    rep.flooded = flooded
    for _, i in ipairs(rep.built_at or {}) do P.fill_slots(state, i) end
    if #flooded > 0 then rep.lines[#rep.lines + 1] = 'The river burst its banks.' end
    P.month(state, r, rep)
    renown_and_coin(state, rep)
    if rep.hunger > 0 then state.famine = true end
    for _, p in pairs(state.people) do if p.gone then state.someone_left = true end end
    rep.month = month
    state.report = rep
    state.month = month + 1
    if R.population(state) == 0 then
      state.over = 'dead'
      state.pending = {}
      state.event = nil
    elseif state.month > S.MONTHS then
      state.over = 'end'
      state.pending = {}
      state.event = nil
    end
    return rep
  end

  ------------------------------------------------------------------ the end

  function S.score(state)
    local pop, happy = 0, 0
    for _, p in pairs(state.people) do
      if p.alive and not p.gone then pop = pop + 1; happy = happy + p.happy end
    end
    local avg = pop > 0 and happy // pop or 0
    local stock = state.res.food + state.res.wood + state.res.stone + state.res.tools
    local buildings = 0
    for _, b in pairs(state.b) do if b.left == 0 then buildings = buildings + 1 end end
    local way, tier = S.way(state)
    -- renown counts: a way that suits the valley earns more of it, so the valley shapes the best ending
    local s = pop * 10 + avg + stock // 20 + state.res.coin // 5 + tier * 50 + buildings * 5 + state.renown[way] // 5
    if not state.famine then s = s + 30 end
    if not state.someone_left then s = s + 20 end
    return s
  end

  local TITLES = {
    trade = { 'A great market town', 'A busy market village', 'A crossroads stall' },
    grain = { 'The granary of the valley', 'A village of mills and fields', 'A farming hamlet' },
    craft = { 'A craftsmen\'s town', 'A village of workshops', 'A hamlet with a forge' },
    faith = { 'A famous place of pilgrimage', 'A pilgrims\' rest', 'A wayside shrine' },
  }
  local WAY_LINE = {
    trade = 'Traders come from up and down the river to {village}.',
    grain = 'The mills of {village} feed the whole valley.',
    craft = 'The workshops of {village} are known for miles.',
    faith = 'Pilgrims walk for days to reach {village}.',
  }
  S.LEVELS = { 1400, 1100 }

  function S.ending(state)
    local score = S.score(state)
    if state.over == 'dead' then
      return { way = 'dead', title = 'Abandoned', score = score, level = nil,
               lines = { T.fill('No one is left in {village}. Grass grows over the paths.', { village = state.name }),
                         'It lasted ' .. (state.month - 1) .. ' months.' } }
    end
    local way, tier = S.way(state)
    local level = score >= S.LEVELS[1] and 1 or (score >= S.LEVELS[2] and 2 or 3)
    local pop = R.population(state)
    if tier < 2 then
      return { way = 'hamlet', title = 'A quiet hamlet', score = score, level = level,
               lines = { T.fill('{village} stays a quiet hamlet by the river.', { village = state.name }),
                         pop .. ' people live there now.' } }
    end
    return { way = way, title = TITLES[way][level], score = score, level = level,
             lines = { T.fill(WAY_LINE[way], { village = state.name }), pop .. ' people live there now.' } }
  end

  return S
end
