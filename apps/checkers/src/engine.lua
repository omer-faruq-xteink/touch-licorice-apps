-- The reader's draughts player: alpha-beta with iterative deepening; at the end of the depth it
-- goes on while a capture is on the board (captures are compulsory, so a quiet score in the middle
-- of an exchange would be wrong); the best move of the last depth first, then the longest
-- captures, then killer moves. The evaluation: men and kings, men further up the board, the back
-- row kept, the middle of the board, and a little noise per level so games differ.
--
-- think(pos, level, opts) runs in a coroutine as Chess does: every 100 nodes it asks
-- opts.clock() and yields once the slice (opts.slice_ms) is used up; past opts.limit_ms it plays
-- the best move of the last depth it finished. Outside a coroutine (tests) it never yields.

local R = require('rules')
local E = {}

local WIN = 100000
local INF = 1000000

E.LEVELS = {
  { name = 'Beginner', depth = 2, ms = 500, noise = 120 },
  { name = 'Easy', depth = 4, ms = 1500, noise = 40 },
  { name = 'Medium', depth = 8, ms = 3500, noise = 10 },
  { name = 'Hard', depth = 14, ms = 8000, noise = 3 },
}

local MAN, KING = 100, { [R.CHECKERS] = 300, [R.DAMA] = 350 }

-- the score for the side to move
local function evaluate(pos)
  local b, v = pos.b, pos.variant
  local king = KING[v]
  local s = 0
  for i = 1, 64 do
    local p = b[i]
    if p ~= 0 then
      local r, c = (i - 1) // 8, (i - 1) % 8
      local mid = (c >= 2 and c <= 5) and 4 or 0
      if p == 1 then s = s + MAN + r * 6 + mid + ((r == 0 and v == R.CHECKERS) and 8 or 0)
      elseif p == -1 then s = s - MAN - (7 - r) * 6 - mid - ((r == 7 and v == R.CHECKERS) and 8 or 0)
      elseif p == 2 then s = s + king + mid
      else s = s - king - mid end
    end
  end
  return s * pos.side
end
E.evaluate = evaluate

local Search = {}
Search.__index = Search

function Search:tick()
  self.nodes = self.nodes + 1
  if self.nodes % 100 ~= 0 then return end
  local now = self.clock()
  if self.limit and now - self.start >= self.limit then self.stopped = true; return end
  if self.yield and now - self.slice_start >= self.slice then
    coroutine.yield()
    self.slice_start = self.clock()
  end
end

local function kkey(m) return m.from * 64 + m.to end

-- order: the move to try first, longer captures, killers
local function order(list, first, killers)
  local keys = {}
  for i, m in ipairs(list) do
    local k = #m.caps * 1000
    if first and kkey(m) == kkey(first) and #m.caps == #first.caps then k = k + 100000 end
    if killers and (killers[1] == kkey(m) or killers[2] == kkey(m)) then k = k + 500 end
    if m.promo then k = k + 300 end
    keys[i] = k
  end
  -- insertion sort by key, the lists are short
  for i = 2, #list do
    local m, k = list[i], keys[i]
    local j = i - 1
    while j >= 1 and keys[j] < k do list[j + 1], keys[j + 1] = list[j], keys[j]; j = j - 1 end
    list[j + 1], keys[j + 1] = m, k
  end
end

function Search:search(pos, depth, alpha, beta, ply)
  self:tick()
  if self.stopped then return 0 end
  if pos.quiet >= R.QUIET_PLIES then return 0 end
  -- at the end of the depth: a quiet position is scored as it stands; with a capture on the board
  -- the search goes on (captures are compulsory). A side with no move at all is found one ply on.
  if depth <= 0 and not R.has_capture(pos) then return evaluate(pos) end
  local list = R.moves(pos)
  if #list == 0 then return -(WIN - ply) end
  if ply > 60 then return evaluate(pos) end
  local killers = self.killers[ply]
  order(list, nil, killers)
  local best = -INF
  for _, m in ipairs(list) do
    R.make(pos, m)
    local v = -self:search(pos, depth - 1, -beta, -alpha, ply + 1)
    R.unmake(pos, m)
    if self.stopped then return 0 end
    if v > best then best = v end
    if v > alpha then alpha = v end
    if alpha >= beta then
      if #m.caps == 0 then
        killers = killers or {}
        if killers[1] ~= kkey(m) then killers[2] = killers[1]; killers[1] = kkey(m) end
        self.killers[ply] = killers
      end
      break
    end
  end
  return best
end

-- the best move for the side to move, its score, the depth reached and the nodes searched
function E.think(pos, level, opts)
  opts = opts or {}
  local L = E.LEVELS[level] or E.LEVELS[3]
  local s = setmetatable({ clock = opts.clock or function() return 0 end, slice = opts.slice_ms or 200,
                           limit = opts.limit_ms or L.ms, nodes = 0, killers = {}, stopped = false }, Search)
  s.yield = opts.yield ~= false and coroutine.isyieldable()
  s.start = s.clock()
  s.slice_start = s.start
  local random = opts.random or math.random
  local root = R.moves(pos)
  if #root == 0 then return nil end
  if #root == 1 then return root[1], 0, 0, 0 end            -- a forced move: no need to think
  local noise = {}
  for i = 1, #root do noise[root[i]] = math.floor((random() - 0.5) * 2 * L.noise) end
  local best, best_score, reached = root[1], -INF, 0
  for depth = 1, L.depth do
    local alpha = -INF
    local this_best, this_score = nil, -INF
    order(root, best, nil)
    for _, m in ipairs(root) do
      R.make(pos, m)
      local v = -s:search(pos, depth - 1, -INF, -alpha + L.noise, 1)
      R.unmake(pos, m)
      if s.stopped then break end
      local score = v + (math.abs(v) < WIN - 1000 and noise[m] or 0)
      if score > this_score then this_best, this_score = m, score end
      if score > alpha then alpha = score end
    end
    if s.stopped then
      if this_best and this_score > best_score then best, best_score = this_best, this_score end
      break
    end
    best, best_score, reached = this_best, this_score, depth
    if math.abs(this_score) >= WIN - 1000 then break end
  end
  return best, best_score, reached, s.nodes
end

E.WIN = WIN
return E
