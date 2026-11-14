-- Riverstead: the valley. An 11 x 11 map made from a seed: a river winding from one edge to the other
-- (wide in places in "river" valleys), patches of fertile soil, forest, rock and marsh grown from seed
-- points weighted by the valley's character, one or two fords, sometimes a special spot (a spring or a
-- standing stone), and the camp near the middle. Valleys that fail the checks are made again from the
-- next child seed.
--
--   local V = require('game.valley')(Rng)

return function(Rng)
  local V = {}
  local N = 11
  V.N = N
  V.CHARS = { 'plain', 'hills', 'river', 'marsh' }

  local function idx(x, y) return (y - 1) * N + x end
  function V.xy(i) return (i - 1) % N + 1, (i - 1) // N + 1 end
  V.idx = idx

  local function inside(x, y) return x >= 1 and x <= N and y >= 1 and y <= N end

  -- the (up to 8) tiles around tile i
  function V.around(i)
    local x, y = V.xy(i)
    local out = {}
    for dy = -1, 1 do for dx = -1, 1 do
      if (dx ~= 0 or dy ~= 0) and inside(x + dx, y + dy) then out[#out + 1] = idx(x + dx, y + dy) end
    end end
    return out
  end

  function V.riverside(v, i)
    if v.t[i] == 'river' then return false end
    local x, y = V.xy(i)
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local nx, ny = x + d[1], y + d[2]
      if inside(nx, ny) and v.t[idx(nx, ny)] == 'river' then return true end
    end
    return false
  end

  -- tiles of a terrain within `dist` (Chebyshev) of i, not counting i
  function V.near(v, i, terrain, dist)
    local x, y = V.xy(i)
    local n = 0
    for dy = -dist, dist do
      for dx = -dist, dist do
        if (dx ~= 0 or dy ~= 0) and inside(x + dx, y + dy) and v.t[idx(x + dx, y + dy)] == terrain then n = n + 1 end
      end
    end
    return n
  end

  local function count(v, terrain)
    local n = 0
    for i = 1, N * N do if v.t[i] == terrain then n = n + 1 end end
    return n
  end

  -- patch counts and sizes per character: { terrain, patches, size }
  local MIX = {
    plain = { { 'fertile', 3, 7 }, { 'forest', 2, 7 }, { 'rock', 1, 4 }, { 'marsh', 1, 3 } },
    hills = { { 'fertile', 1, 5 }, { 'forest', 3, 7 }, { 'rock', 3, 7 }, { 'marsh', 1, 2 } },
    river = { { 'fertile', 2, 6 }, { 'forest', 2, 7 }, { 'rock', 1, 5 }, { 'marsh', 2, 4 } },
    marsh = { { 'fertile', 2, 5 }, { 'forest', 2, 6 }, { 'rock', 1, 4 }, { 'marsh', 3, 7 } },
  }

  local function river(v, r)
    local vertical = r:chance(0.5)
    local wide_rows = 0
    local max_wide = v.char == 'river' and 4 or (r:chance(0.25) and 2 or 0)
    local pos = r:int(3, N - 2)
    local function mark(a, b, wide)
      local x, y = a, b
      if not vertical then x, y = b, a end
      local i = idx(x, y)
      v.t[i] = 'river'
      if wide then v.wide[i] = true end
    end
    local widening = false
    for step = 1, N do
      local old = pos
      if step > 1 then
        local d = r:int(-1, 1)
        pos = math.max(2, math.min(N - 2, pos + d))
      end
      if pos ~= old then mark(old, step, false) end
      if not widening and wide_rows < max_wide and step > 2 and step < N - 1 and r:chance(0.3) then widening = true end
      if widening and wide_rows < max_wide then
        mark(pos, step, true)
        mark(pos + 1, step, true)
        wide_rows = wide_rows + 1
        if wide_rows >= max_wide or r:chance(0.3) then widening = false end
      else
        mark(pos, step, false)
        widening = false
      end
    end
  end

  local function grow(v, r, terrain, size, prefer)
    local starts = {}
    for i = 1, N * N do
      if v.t[i] == 'meadow' and (not prefer or prefer(i)) then starts[#starts + 1] = i end
    end
    if #starts == 0 then return end
    local front = { r:pick(starts) }
    local placed = 0
    while #front > 0 and placed < size do
      local k = r:int(1, #front)
      local i = front[k]
      table.remove(front, k)
      if v.t[i] == 'meadow' then
        v.t[i] = terrain
        placed = placed + 1
        local x, y = V.xy(i)
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
          if inside(x + d[1], y + d[2]) then front[#front + 1] = idx(x + d[1], y + d[2]) end
        end
      end
    end
  end

  local function build(seed)
    local r = Rng.new(seed)
    local v = { seed = seed, w = N, h = N, t = {}, wide = {}, ford = {} }
    v.char = r:pick(V.CHARS)
    for i = 1, N * N do v.t[i] = 'meadow' end
    river(v, r)
    for _, m in ipairs(MIX[v.char]) do
      for _k = 1, m[2] do
        local prefer = nil
        if m[1] == 'fertile' and v.char ~= 'hills' then
          prefer = function(i) return V.riverside(v, i) or V.near(v, i, 'river', 2) > 0 end
        end
        grow(v, r, m[1], m[3], prefer)
      end
    end
    -- fords: river tiles, narrow ones first
    local narrow, any = {}, {}
    for i = 1, N * N do
      if v.t[i] == 'river' then
        any[#any + 1] = i
        if not v.wide[i] then narrow[#narrow + 1] = i end
      end
    end
    local pool = #narrow > 0 and narrow or any
    v.ford[1] = r:pick(pool)
    if r:chance(0.4) then
      local f2 = r:pick(pool)
      if f2 ~= v.ford[1] then v.ford[2] = f2 end
    end
    -- the special spot, in about 40% of valleys
    if r:chance(0.4) then
      local spots = {}
      for i = 1, N * N do
        if v.t[i] == 'meadow' and not V.riverside(v, i) then spots[#spots + 1] = i end
      end
      if #spots > 0 then
        v.special = r:pick(spots)
        v.special_kind = r:chance(0.5) and 'spring' or 'stone'
      end
    end
    -- the camp: the meadow tile nearest the middle with room around it and forest in reach
    local best, bd = nil, 99
    for i = 1, N * N do
      if v.t[i] == 'meadow' and i ~= v.special then
        local room = V.near(v, i, 'meadow', 2) + V.near(v, i, 'fertile', 2)
        if room >= 6 and V.near(v, i, 'forest', 4) > 0 then
          local x, y = V.xy(i)
          local d = math.abs(x - 6) + math.abs(y - 6)
          if d < bd then best, bd = i, d end
        end
      end
    end
    v.camp = best
    return v
  end

  function V.check(v)
    if not v.camp then return false, 'no camp' end
    if count(v, 'meadow') + count(v, 'fertile') < 12 then return false, 'too little open land' end
    if count(v, 'forest') < 6 then return false, 'too little forest' end
    if count(v, 'rock') < 3 then return false, 'too little rock' end
    if #v.ford < 1 then return false, 'no ford' end
    if V.near(v, v.camp, 'forest', 4) == 0 then return false, 'no forest near the camp' end
    -- a woodcutter and a quarry must have somewhere to stand: open land next to forest and to rock
    local wood_ok, stone_ok = false, false
    for i = 1, N * N do
      if (v.t[i] == 'meadow' or v.t[i] == 'fertile') and i ~= v.special then
        if V.near(v, i, 'forest', 1) > 0 then wood_ok = true end
        if V.near(v, i, 'rock', 1) > 0 then stone_ok = true end
      end
      if v.t[i] == 'rock' then stone_ok = true end
    end
    if not wood_ok then return false, 'no open land by the forest' end
    if not stone_ok then return false, 'no way to the rock' end
    return true, 'ok'
  end

  function V.make(seed)
    for k = 1, 100 do
      local v = build(Rng.mix(seed, k))
      if V.check(v) then v.seed = seed; return v end
    end
    error('no valley could be made')
  end

  return V
end
