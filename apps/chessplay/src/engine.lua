-- The reader's chess player: alpha-beta search with iterative deepening, a quiescence search over
-- captures and promotions, the best move of the last depth tried first, captures by most valuable
-- victim / least valuable attacker, two killer moves a ply. The evaluation is material and
-- piece-square tables (pos.score, kept up to date by make), the king going to the middle in the
-- endgame, and a little noise per level so games differ.
--
-- think(pos, level, opts) is meant to run in a coroutine: every 200 nodes it asks opts.clock() and
-- calls coroutine.yield() once the slice (opts.slice_ms) is used up, so the host's callback limits
-- are kept and the screen stays responsive; past opts.limit_ms it stops and plays the best move of
-- the last depth it finished. Outside a coroutine (tests) it never yields.

local R = require('rules')
local E = {}

local MATE = 100000
local INF = 1000000

-- the levels: how deep, how long, how much noise (centipawns) at the root
E.LEVELS = {
  { name = 'Beginner', depth = 1, ms = 500, noise = 220, quiesce = false },
  { name = 'Easy', depth = 2, ms = 1500, noise = 80, quiesce = true },
  { name = 'Medium', depth = 4, ms = 3500, noise = 20, quiesce = true },
  { name = 'Hard', depth = 6, ms = 8000, noise = 6, quiesce = true },
}

local VALUE = R.VALUE
local KING_END = R.KING_END
local pst_index = R.pst_index
local gen, make, unmake, attacked, needs_check = R.gen, R.make, R.unmake, R.attacked, R.needs_check

-- the score for the side to move
local function evaluate(pos)
  local s = pos.score
  if pos.npm <= 1300 then
    -- the endgame: the kings come out (the middle-game table keeps them home)
    local wk, bk = pos.king[1], pos.king[-1]
    s = s + KING_END[pst_index(wk, 1)] - KING_END[pst_index(bk, -1)]
  end
  return s * pos.side
end
E.evaluate = evaluate

local Search = {}
Search.__index = Search

local function new_search(opts)
  local o = setmetatable({}, Search)
  o.clock = opts.clock or function() return 0 end
  o.slice = opts.slice_ms or 200
  o.limit = opts.limit_ms
  o.yield = opts.yield ~= false and coroutine.isyieldable()
  o.nodes = 0
  o.killers = {}
  o.start = o.clock()
  o.slice_start = o.start
  o.stopped = false
  o.use_q = opts.quiesce ~= false
  -- a move list and its order keys per ply, kept between nodes: no tables made while searching
  o.lists, o.keys = {}, {}
  return o
end

function Search:tick()
  self.nodes = self.nodes + 1
  if self.nodes % 200 ~= 0 then return end
  local now = self.clock()
  if self.limit and now - self.start >= self.limit then self.stopped = true; return end
  if self.yield and now - self.slice_start >= self.slice then
    coroutine.yield()
    self.slice_start = self.clock()
  end
end

function Search:buffers(ply)
  local l = self.lists[ply]
  if not l then l = {}; self.lists[ply] = l; self.keys[ply] = {} end
  return l, self.keys[ply]
end

-- order keys: the move to try first, captures (most valuable victim, least valuable attacker),
-- promotions, killers, the rest
local function score_moves(pos, list, keys, n, first, killers)
  local b = pos.b
  local k1, k2 = killers and killers[1], killers and killers[2]
  for i = 1, n do
    local m = list[i]
    local k
    if m == first then k = 1000000
    else
      local victim = b[(m // 128) % 128]
      if victim ~= 0 then
        if victim < 0 then victim = -victim end
        local att = b[m % 128]
        if att < 0 then att = -att end
        k = 100000 + victim * 100 - att
      elseif (m // 16384) % 8 ~= 0 then k = 90000 + (m // 16384) % 8
      elseif m == k1 or m == k2 then k = 80000
      else k = 0 end
    end
    keys[i] = k
  end
end

-- the next move in order: the best of i..n brought to i (a cut-off often comes after a few)
local function pick(list, keys, i, n)
  local bi, bk = i, keys[i]
  for j = i + 1, n do
    if keys[j] > bk then bi, bk = j, keys[j] end
  end
  if bi ~= i then
    list[i], list[bi] = list[bi], list[i]
    keys[i], keys[bi] = keys[bi], keys[i]
  end
  return list[i]
end

-- the whole list in order (the root, sorted once per depth)
local function order(pos, list, n, first, killers)
  local keys = {}
  score_moves(pos, list, keys, n, first, killers)
  for i = 1, n - 1 do pick(list, keys, i, n) end
end

function Search:quiesce(pos, alpha, beta, ply)
  self:tick()
  if self.stopped then return 0 end
  local stand = evaluate(pos)
  if stand >= beta then return stand end
  if stand > alpha then alpha = stand end
  if ply > 40 then return stand end
  local list, keys = self:buffers(ply)
  local n = gen(pos, list, 0, true)
  score_moves(pos, list, keys, n, nil, nil)
  local side, b = pos.side, pos.b
  local king = pos.king[side]
  local chk = n > 0 and attacked(pos, king, -side)
  for i = 1, n do
    local m = pick(list, keys, i, n)
    -- a capture that cannot bring the score up to alpha even when it wins the piece: skip it
    local victim = b[(m // 128) % 128]
    if victim < 0 then victim = -victim end
    local gain = victim ~= 0 and VALUE[victim] or 100
    if (m // 16384) % 8 == 0 and stand + gain + 200 < alpha then goto continue end
    do
      local u = make(pos, m)
      if not needs_check(m, king, chk) or not attacked(pos, pos.king[side], -side) then
        local v = -self:quiesce(pos, -beta, -alpha, ply + 1)
        unmake(pos, m, u)
        if self.stopped then return 0 end
        if v >= beta then return v end
        if v > alpha then alpha = v end
      else
        unmake(pos, m, u)
      end
    end
    ::continue::
  end
  return alpha
end

function Search:alphabeta(pos, depth, alpha, beta, ply, null_ok)
  self:tick()
  if self.stopped then return 0 end
  local side = pos.side
  local check = attacked(pos, pos.king[side], -side)
  if check and ply < 24 then depth = depth + 1 end    -- look one ply further out of a check
  if depth <= 0 then
    if self.use_q then return self:quiesce(pos, alpha, beta, ply) end
    return evaluate(pos)
  end
  if pos.half >= 100 then return 0 end
  -- the null move: even after passing, the side to move stays above beta, so this position will
  -- not be allowed; not in check, nor in the endgame, where passing can be the better move
  if null_ok and not check and depth >= 3 and pos.npm > 1300 and evaluate(pos) >= beta then
    local ep = pos.ep
    pos.ep, pos.side = 0, -side
    local v = -self:alphabeta(pos, depth - 3, -beta, -beta + 1, ply + 1, false)
    pos.ep, pos.side = ep, side
    if self.stopped then return 0 end
    if v >= beta then return beta end
  end
  local list, keys = self:buffers(ply)
  local n = gen(pos, list, 0, false)
  local killers = self.killers[ply]
  score_moves(pos, list, keys, n, nil, killers)
  local legal, best = 0, -INF
  local king = pos.king[side]
  for i = 1, n do
    local m = pick(list, keys, i, n)
    local u = make(pos, m)
    if not needs_check(m, king, check) or not attacked(pos, pos.king[side], -side) then
      legal = legal + 1
      local v = -self:alphabeta(pos, depth - 1, -beta, -alpha, ply + 1, true)
      unmake(pos, m, u)
      if self.stopped then return 0 end
      if v > best then best = v end
      if v > alpha then alpha = v end
      if alpha >= beta then
        if pos.b[(m // 128) % 128] == 0 then          -- a quiet move that cut: remember it
          killers = killers or {}
          if killers[1] ~= m then killers[2] = killers[1]; killers[1] = m end
          self.killers[ply] = killers
        end
        break
      end
    else
      unmake(pos, m, u)
    end
  end
  if legal == 0 then return check and -(MATE - ply) or 0 end
  return best
end

-- the best move for the side to move, with its score, the depth reached and the nodes searched.
-- opts: clock, slice_ms, limit_ms (else the level's), random (a function returning 0..1)
function E.think(pos, level, opts)
  opts = opts or {}
  local L = E.LEVELS[level] or E.LEVELS[3]
  local s = new_search({ clock = opts.clock, slice_ms = opts.slice_ms, limit_ms = opts.limit_ms or L.ms,
                         yield = opts.yield, quiesce = L.quiesce })
  local random = opts.random or math.random
  local root = R.legal(pos)
  if #root == 0 then return nil end
  -- a little noise per root move, fixed for the whole search, so the reader does not always play the same
  local noise = {}
  for _, m in ipairs(root) do noise[m] = math.floor((random() - 0.5) * 2 * L.noise) end
  local best, best_score, reached = root[1], -INF, 0
  for depth = 1, L.depth do
    local alpha, beta = -INF, INF
    local this_best, this_score = nil, -INF
    order(pos, root, #root, best, nil)
    for _, m in ipairs(root) do
      local u = make(pos, m)
      local v = -s:alphabeta(pos, depth - 1, -beta, -alpha + L.noise, 1, true)
      unmake(pos, m, u)
      if s.stopped then break end
      local score = v + (math.abs(v) < MATE - 1000 and noise[m] or 0)
      if score > this_score then this_best, this_score = m, score end
      if score > alpha then alpha = score end
    end
    if s.stopped then
      -- a part of this depth: its best is still good when it beat the last depth's choice
      if this_best and this_score > best_score then best, best_score = this_best, this_score end
      break
    end
    best, best_score, reached = this_best, this_score, depth
    if math.abs(this_score) >= MATE - 1000 then break end    -- a forced mate found: no need to look further
  end
  return best, best_score, reached, s.nodes
end

E.MATE = MATE
return E
