-- Port Wren: seeded random numbers. Park-Miller with Schrage's step (as in Delve): every value stays
-- under 2^31, so a seed gives the same numbers with 32- or 64-bit Lua integers, on the reader and in
-- the tests, and a saved case can be made again from its seed.

local R = {}
local M31 = 2147483647

local function seed31(x) return math.floor(math.abs(tonumber(x) or 1) % (M31 - 1)) + 1 end

local Rng = {}
Rng.__index = Rng

function Rng:next()
  local s = 16807 * (self.s % 127773) - 2836 * (self.s // 127773)
  if s <= 0 then s = s + M31 end
  self.s = s
  return s
end
function Rng:int(a, b) return a + self:next() % (b - a + 1) end
function Rng:chance(p) return self:next() % 1000 < math.floor(p * 1000) end
function Rng:pick(t) return t[self:int(1, #t)] end
function Rng:shuffle(t)
  for i = #t, 2, -1 do
    local j = self:int(1, i)
    t[i], t[j] = t[j], t[i]
  end
  return t
end

function R.new(seed) return setmetatable({ s = seed31(seed) }, Rng) end

-- a child seed: the same (a, b) always gives the same number
function R.mix(a, b)
  local r = R.new(a)
  r:next()
  r.s = seed31(r.s + seed31(b) % 1000003)
  r:next(); r:next()
  return r:next()
end

return R
