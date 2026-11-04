-- The reader's backgammon player.
--
-- evaluate(b, s) scores a position for side s just after s has played (the other side to roll),
-- in units where 350 is one step of the logistic: win chance = 1 / (1 + exp(-score / 350)).
-- Once contact is broken it is a race, scored from the pip counts. With contact: the pips, the
-- points made (the 5, 4 and 6 points most, then the bar point; anchors in the other home board),
-- primes, the chance a blot is hit (the shots from every enemy checker behind it, the cost of
-- going back), checkers on the bar against a strong home board, stacks and checkers off.
--
-- Levels: Beginner plays a random play half the time; Easy and Medium pick the best play by the
-- evaluation (Easy with noise); Hard looks one roll ahead: for its best few plays it averages,
-- over the 21 rolls, the other side's best reply. think() runs in a coroutine as in Checkers and
-- Chess: it asks opts.clock() every few positions and yields once a slice is used up; past
-- opts.limit_ms it keeps the best play found so far. Outside a coroutine (tests) it never yields.

local R = require('rules')
local E = {}

E.LEVELS = {
  { name = 'Beginner', random = 0.5, noise = 150 },
  { name = 'Easy', noise = 60 },
  { name = 'Medium', noise = 0 },
  { name = 'Hard', noise = 0, ahead = 4, ms = 8000 },
}
E.SCALE = 350
local WIN = 5000

-- rolls hitting a blot this far away (direct and combined shots, ignoring blocks)
local SHOTS = { 11, 12, 14, 15, 15, 17, 6, 6, 5, 3, 2, 3, 0, 0, 1, 1, 0, 1, 0, 1, 0, 0, 0, 1 }
-- a point made, by its number for its owner
local POINT = { 10, 20, 32, 46, 56, 50, 40, 26, 14, 10, 6, 6, 3, 3, 3, 3, 3, 3, 6, 30, 26, 16, 10, 6 }

local exp, sqrt = math.exp, math.sqrt

local function counts(b, s)
  local t = {}
  for i = 1, 24 do
    local v = b[R.idx(s, i)] * s
    t[i] = v > 0 and v or 0
  end
  t[25] = b[R.bar(s)]
  return t
end

local function home_points(t)
  local n = 0
  for i = 1, 6 do if t[i] >= 2 then n = n + 1 end end
  return n
end

function E.evaluate(b, s)
  local o = -s
  local offm, offo = b[R.off(s)], b[R.off(o)]
  if offm == R.CHECKERS then return WIN end
  if offo == R.CHECKERS then return -WIN end
  local me, op = counts(b, s), counts(b, o)
  local pm, po = 0, 0
  local backm, backo = 0, 0
  for i = 25, 1, -1 do
    pm = pm + i * me[i]; po = po + i * op[i]
    if backm == 0 and me[i] > 0 then backm = i end
    if backo == 0 and op[i] > 0 then backo = i end
  end
  -- the other side's rearmost checker is on my point 25 - backo: no contact once I am past it
  if backm + backo <= 25 then
    -- a race with the other side on roll (worth about 4 pips)
    local z = (po - pm - 4) / (0.12 * pm + 4)
    local spread = 0
    for i = 1, 6 do if me[i] > 0 then spread = spread + 1 end end
    return 630 * z + (offm - offo) * 6 + spread * 3
  end
  local pipw = 630 / (0.12 * pm + 4) * 0.4
  local s_ = (po - pm) * pipw + (offm - offo) * 15
  -- points made and primes
  local run, best_run = 0, 0
  for i = 1, 24 do
    if me[i] >= 2 then
      s_ = s_ + POINT[i]
      run = run + 1
      if run > best_run then best_run = run end
      if me[i] > 3 and i <= 12 then s_ = s_ - (me[i] - 3) * 6 end
    else
      run = 0
    end
    if op[i] >= 2 then s_ = s_ - POINT[i] end
  end
  if best_run >= 3 then s_ = s_ + (best_run - 2) * (best_run - 2) * 25 end
  -- the bar
  local hm, ho = home_points(me), home_points(op)
  s_ = s_ - me[25] * (ho * ho * 8 + 20) + op[25] * (hm * hm * 8 + 20)
  -- my blots: the shots at each from the enemy checkers behind it
  local worst, total = 0, 0
  for i = 1, 24 do
    if me[i] == 1 then
      local shots = 0
      for q = 0, i - 1 do
        -- an enemy checker on my point q (its own point 25 - q; q = 0 is its bar)
        local n = q == 0 and op[25] or op[25 - q]
        if n > 0 then shots = shots + SHOTS[i - q] end
      end
      if shots > 0 then
        if shots > 36 then shots = 36 end
        local cost = shots / 36 * ((25 - i) * pipw + 60 + ho * 25)
        total = total + cost
        if cost > worst then worst = cost end
      end
    end
  end
  s_ = s_ - worst - (total - worst) * 0.5
  return s_
end

function E.win_chance(score) return 1 / (1 + exp(-score / E.SCALE)) end

-- the 21 rolls and how often each comes (out of 36)
local ROLLS = {}
for a = 1, 6 do for c = a, 6 do ROLLS[#ROLLS + 1] = { a, c, a == c and 1 or 2 } end end
E.ROLLS = ROLLS

local Search = {}
Search.__index = Search

function Search:tick()
  self.n = self.n + 1
  if self.n % 20 ~= 0 then return end
  local now = self.clock()
  if self.limit and now - self.start >= self.limit then self.stopped = true; return end
  if self.yield and now - self.slice_start >= self.slice then
    coroutine.yield()
    self.slice_start = self.clock()
  end
end

-- the best reply of side s to roll (a, c) from b, by the evaluation: its score for s
function Search:reply(b, s, a, c)
  local plays = R.plays(b, s, a, c)
  local best = -math.huge
  for _k, p in ipairs(plays) do
    local v = E.evaluate(p.b, s)
    if v > best then best = v end
    self:tick()
    if self.stopped then break end
  end
  return best
end

-- think(b, s, ds, level, opts) -> the play (moves) side s should make with the dice ds (a list:
-- two dice, four for a double, or what is left of a turn; opts.start: none played yet)
function E.think(b, s, ds, level, opts)
  opts = opts or {}
  local lv = E.LEVELS[level] or E.LEVELS[2]
  local plays = R.plays_ds(b, s, ds, opts.start ~= false)
  if #plays == 1 then return plays[1].moves end
  if lv.random and math.random() < lv.random then return plays[math.random(#plays)].moves end
  local rank = {}
  for k, pl in ipairs(plays) do
    local v = E.evaluate(pl.b, s)
    if lv.noise and lv.noise > 0 then v = v + (math.random() * 2 - 1) * lv.noise end
    rank[k] = { p = pl, v = v }
  end
  table.sort(rank, function(x, y) return x.v > y.v end)
  if not lv.ahead then return rank[1].p.moves end
  local clock = opts.clock or function() return 0 end
  local S = setmetatable({ n = 0, clock = clock, start = clock(), slice_start = clock(), slice = opts.slice_ms or 200,
                           limit = opts.limit_ms or lv.ms, yield = coroutine.isyieldable() }, Search)
  local best, best_v = rank[1].p.moves, -math.huge
  for k = 1, math.min(lv.ahead, #rank) do
    local p = rank[k].p
    local sum = 0
    for _j, r in ipairs(ROLLS) do
      sum = sum - S:reply(p.b, -s, r[1], r[2]) * r[3]
      if S.stopped then break end
    end
    if S.stopped then break end
    local v = sum / 36
    if v > best_v then best, best_v = p.moves, v end
  end
  return best
end

-- the reader's chance to win with side s on roll (before it rolls)
function E.on_roll_chance(b, s) return 1 - E.win_chance(E.evaluate(b, -s)) end

-- should side s, on roll, double?
function E.should_double(b, s)
  local p = E.on_roll_chance(b, s)
  return p >= 0.70, p
end

-- should side s take a double from the other side (who is on roll)?
function E.should_take(b, s)
  local p = 1 - E.on_roll_chance(b, -s)
  return p >= 0.25, p
end

return E
