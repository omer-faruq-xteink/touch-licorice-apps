-- Icebound: the region. An 11 x 28 polar map made from a seed: flat ice with patches of sastrugi,
-- pressure ridges, crevasse fields, glacier slopes, open-water leads and nunataks, weighted by the
-- region's character; caches left by earlier parties; and the mission's start, goal and targets. A
-- region that fails the checks (a target walled off) is made again from the next child seed.
--
--   local G = require('game.region')(Rng)
--
-- Tiles are numbered i = (y-1)*11 + x; y = 1 is the far north (the top of the map), the start is in
-- the bottom rows.

return function(Rng)
  local G = {}
  local W, H = 11, 28
  G.W, G.H = W, H
  G.CHARS = { 'coast', 'plateau', 'glacier', 'pack' }
  G.MISSIONS = { 'crossing', 'pole', 'lost', 'survey' }

  local function idx(x, y) return (y - 1) * W + x end
  local function inside(x, y) return x >= 1 and x <= W and y >= 1 and y <= H end
  G.idx = idx
  function G.xy(i) return (i - 1) % W + 1, (i - 1) // W + 1 end

  function G.around(i)
    local x, y = G.xy(i)
    local out = {}
    for dy = -1, 1 do for dx = -1, 1 do
      if (dx ~= 0 or dy ~= 0) and inside(x + dx, y + dy) then out[#out + 1] = idx(x + dx, y + dy) end
    end end
    return out
  end

  -- water bars the way unless frozen; rock (a nunatak) always does
  function G.passable(reg, frozen, i)
    local t = reg.t[i]
    if t == 'rock' then return false end
    if t == 'water' then return (frozen and frozen[i]) and true or false end
    return t ~= nil
  end

  ------------------------------------------------------------------ the cheapest path

  -- a small binary heap of { cost, i }
  local function push(h, c, i)
    h[#h + 1] = { c, i }
    local k = #h
    while k > 1 do
      local p = k // 2
      if h[p][1] <= h[k][1] then break end
      h[p], h[k] = h[k], h[p]
      k = p
    end
  end
  local function pop(h)
    local top = h[1]
    local last = table.remove(h)
    if #h > 0 then
      h[1] = last
      local k = 1
      while true do
        local l, r, s = 2 * k, 2 * k + 1, k
        if l <= #h and h[l][1] < h[s][1] then s = l end
        if r <= #h and h[r][1] < h[s][1] then s = r end
        if s == k then break end
        h[s], h[k] = h[k], h[s]
        k = s
      end
    end
    return top
  end

  -- the cheapest path from `from` to `to` (both included), stepping in 8 directions; cost_fn(i) gives
  -- the points to enter tile i, or nil when it can't be entered; with `known`, only known tiles (the
  -- goal included) are used. nil when there is none.
  function G.path(reg, from, to, cost_fn, known)
    if from == to then return { from } end
    local dist, prev = { [from] = 0 }, {}
    local h = {}
    push(h, 0, from)
    while #h > 0 do
      local top = pop(h)
      local c, i = top[1], top[2]
      if i == to then break end
      if c <= dist[i] then
        local ix, iy = (i - 1) % W + 1, (i - 1) // W + 1
        for _, j in ipairs(G.around(i)) do
          if not known or known[j] then
            local step = cost_fn(j)
            if step then
              -- costs in sixteenths, a diagonal step one sixteenth dearer: of equal ways the straightest wins
              local jx, jy = (j - 1) % W + 1, (j - 1) // W + 1
              local nc = c + step * 16 + ((ix ~= jx and iy ~= jy) and 1 or 0)
              if dist[j] == nil or nc < dist[j] then dist[j], prev[j] = nc, i; push(h, nc, j) end
            end
          end
        end
      end
    end
    if dist[to] == nil then return nil end
    local out, i = {}, to
    while i do table.insert(out, 1, i); i = prev[i] end
    return out
  end

  ------------------------------------------------------------------ making a region

  -- patch counts and sizes per character: { terrain, patches, size }
  local MIX = {
    coast = { { 'water', 6, 7 }, { 'sastrugi', 2, 6 }, { 'ridge', 2, 4 }, { 'crevasse', 1, 4 }, { 'slope', 1, 4 }, { 'rock', 2, 2 } },
    plateau = { { 'sastrugi', 7, 9 }, { 'slope', 2, 6 }, { 'crevasse', 1, 4 }, { 'ridge', 1, 3 }, { 'rock', 2, 2 } },
    glacier = { { 'crevasse', 6, 8 }, { 'slope', 3, 6 }, { 'sastrugi', 2, 5 }, { 'ridge', 1, 3 }, { 'rock', 3, 2 } },
    pack = { { 'ridge', 7, 8 }, { 'water', 3, 4 }, { 'sastrugi', 2, 5 }, { 'crevasse', 1, 3 }, { 'rock', 1, 2 } },
  }

  local function grow(reg, r, terrain, size)
    local i = r:int(1, W * H)
    for _ = 1, size do
      reg.t[i] = terrain
      local nb = G.around(i)
      i = nb[r:int(1, #nb)]
    end
  end

  -- a lead of open water: a streak across part of the map
  local function lead(reg, r, len)
    local x, y = r:int(1, W), r:int(4, H - 4)
    for _ = 1, len do
      reg.t[idx(x, y)] = 'water'
      x = x + (r:chance(0.5) and 1 or -1)
      if r:chance(0.3) then y = y + (r:chance(0.5) and 1 or -1) end
      if not inside(x, y) then break end
    end
  end

  local function flat_at(reg, i) reg.t[i] = 'flat'; reg.up[i] = nil end

  local function random_free(reg, r, y0, y1, x0, x1)
    for _ = 1, 200 do
      local i = idx(r:int(x0 or 1, x1 or W), r:int(y0, y1))
      if G.passable(reg, nil, i) and i ~= reg.start and i ~= reg.goal then return i end
    end
    return idx(x0 or 1, y0)
  end

  local function walk_cost(reg) return function(i) if G.passable(reg, nil, i) then return 1 end end end

  local function build(seed, mission)
    local r = Rng.new(seed)
    local reg = { seed = seed, mission = mission, w = W, h = H, t = {}, up = {}, targets = {}, cairns = {}, caches = {} }
    reg.char = G.CHARS[r:int(1, #G.CHARS)]
    for i = 1, W * H do reg.t[i] = 'flat' end
    for _, m in ipairs(MIX[reg.char]) do
      for _p = 1, m[2] do grow(reg, r, m[1], r:int(math.max(1, m[3] - 2), m[3] + 2)) end
    end
    if reg.char == 'coast' then for _ = 1, 3 do lead(reg, r, r:int(4, 8)) end
    elseif reg.char == 'pack' then for _ = 1, 2 do lead(reg, r, r:int(3, 6)) end end
    for i = 1, W * H do if reg.t[i] == 'slope' and r:chance(0.7) then reg.up[i] = true end end
    -- the start and the goal
    reg.start = idx(r:int(3, W - 2), H)
    flat_at(reg, reg.start)
    if mission == 'crossing' then
      reg.goal = idx(r:int(2, W - 1), 1)
    elseif mission == 'pole' then
      reg.goal = idx(r:int(3, W - 2), r:int(8, 12))
    elseif mission == 'lost' then
      -- the camp is mostly off the straight line north; the pick-up on the far side from it
      local sx = G.xy(reg.start)
      local xs = {}
      for x = 1, W do if math.abs(x - sx) >= 3 or r:chance(0.15) then xs[#xs + 1] = x end end
      local cx = xs[r:int(1, #xs)]
      local camp = idx(cx, r:int(3, 14))
      flat_at(reg, camp)
      reg.targets = { camp }
      reg.goal = idx(cx <= 6 and W or 1, r:int(14, 24))
    else
      local side = r:chance(0.5) and 1 or W
      local xs = side == 1 and { 1, 2 } or { W - 1, W }
      for k = 1, 4 do
        local y = 4 + (k - 1) * 5 + r:int(0, 3)
        local t = idx(xs[r:int(1, 2)], y)
        flat_at(reg, t)
        reg.targets[#reg.targets + 1] = t
      end
      reg.goal = idx(side, r:int(1, 2))
    end
    flat_at(reg, reg.goal)
    -- the lost party's cairns: their way wandered from the camp by another place to the start; a cairn
    -- every 4-6 tiles, and one of them (when there are four or more) buried by the snow
    if mission == 'lost' then
      local _, cy = G.xy(reg.targets[1])
      local via = idx(r:int(1, W), r:int(math.min(H - 4, cy + 3), H - 4))
      local p1 = G.passable(reg, nil, via) and G.path(reg, reg.targets[1], via, walk_cost(reg), nil)
      local p2 = p1 and G.path(reg, via, reg.start, walk_cost(reg), nil)
      local p
      if p1 and p2 then
        p = p1
        for k = 2, #p2 do p[#p + 1] = p2[k] end
      else
        p = G.path(reg, reg.targets[1], reg.start, walk_cost(reg), nil)
      end
      if p then
        local seen = {}
        local k = r:int(3, 5)
        while k < #p - 1 do
          if not seen[p[k]] then reg.cairns[#reg.cairns + 1] = p[k]; seen[p[k]] = true end
          k = k + r:int(3, 5)
        end
        if #reg.cairns >= 4 then table.remove(reg.cairns, r:int(2, #reg.cairns - 1)) end
      end
    end
    -- caches of earlier parties; some are empty
    for _ = 1, r:int(2, 4) do
      local i = random_free(reg, r, 5, H - 4)
      if r:chance(0.3) then reg.caches[i] = {}
      else reg.caches[i] = { food = r:int(3, 8) * 5, fuel = r:int(1, 4) * 2, dogfood = r:int(2, 6) * 5 } end
    end
    return reg
  end

  -- a path exists from the start to the goal and to every target (and back for pole and lost); no
  -- target stands on impassable ice
  function G.check(reg)
    local c = walk_cost(reg)
    for _, t in ipairs(reg.targets) do
      if not G.passable(reg, nil, t) then return false, 'a target on impassable ice' end
      if not G.path(reg, reg.start, t, c, nil) then return false, 'a target out of reach' end
    end
    if not G.passable(reg, nil, reg.goal) or not G.passable(reg, nil, reg.start) then return false, 'the start or goal blocked' end
    if not G.path(reg, reg.start, reg.goal, c, nil) then return false, 'no way to the goal' end
    if reg.mission == 'lost' and #reg.cairns < 2 then return false, 'too few cairns' end
    return true, ''
  end

  function G.make(seed, mission)
    for k = 0, 50 do
      local reg = build(k == 0 and seed or Rng.mix(seed, k), mission)
      if G.check(reg) then reg.seed = seed; return reg end
    end
    error('no region for seed ' .. tostring(seed))
  end

  return G
end
