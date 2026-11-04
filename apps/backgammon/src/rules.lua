-- Backgammon rules. A position is a flat array b[1..28]:
--   b[1..24]  the points, numbered as side 1 sees them (side 1 moves 24 -> 1 and bears off from
--             1..6; side -1 moves 1 -> 24 and bears off from 19..24): +n checkers of side 1,
--             -n of side -1
--   b[25] b[26]  checkers on the bar of side 1 and side -1
--   b[27] b[28]  checkers borne off by side 1 and side -1
-- Moves are in the mover's own numbering: from 24 (its farthest point) to 1, 25 is the bar and
-- 0 is off. A single move is { from, to, hit, die }; a play is the list of single moves of a
-- turn. A play must use as many dice as possible, and when only one of two different dice can be
-- played, the larger one if it can.

local R = {}

R.CHECKERS = 15

local function idx(s, i) if s == 1 then return i end return 25 - i end
local function bar(s) return s == 1 and 25 or 26 end
local function off(s) return s == 1 and 27 or 28 end
R.idx, R.bar, R.off = idx, bar, off

local function copy(b) return table.move(b, 1, 28, 1, {}) end
R.copy = copy

function R.new()
  local b = {}
  for i = 1, 28 do b[i] = 0 end
  for _k, s in ipairs({ 1, -1 }) do
    b[idx(s, 24)] = 2 * s; b[idx(s, 13)] = 5 * s; b[idx(s, 8)] = 3 * s; b[idx(s, 6)] = 5 * s
  end
  return b
end

-- the checkers of side s on its own point i (1..24), on the bar (25) or off (0)
function R.at(b, s, i)
  if i == 25 then return b[bar(s)] end
  if i == 0 then return b[off(s)] end
  local v = b[idx(s, i)] * s
  return v > 0 and v or 0
end

local KEYCH = {}
for v = -15, 31 do KEYCH[v] = string.char(v + 64) end
function R.key(b)
  local t = {}
  for i = 1, 28 do t[i] = KEYCH[b[i]] end
  return table.concat(t)
end

function R.from_key(k)
  local b = {}
  for i = 1, 28 do b[i] = k:byte(i) - 64 end
  return b
end

-- every single move of side s with die d, appended to out
function R.singles(b, s, d, out)
  out = out or {}
  if b[bar(s)] > 0 then
    local t = 25 - d
    local v = b[idx(s, t)] * s
    if v >= -1 then out[#out + 1] = { 25, t, v == -1, d } end
    return out
  end
  local high = 0
  for i = 24, 1, -1 do
    if b[idx(s, i)] * s > 0 then high = i; break end
  end
  local home = high <= 6
  for i = high, 1, -1 do
    if b[idx(s, i)] * s > 0 then
      local t = i - d
      if t >= 1 then
        local v = b[idx(s, t)] * s
        if v >= -1 then out[#out + 1] = { i, t, v == -1, d } end
      elseif home and (t == 0 or i == high) then
        out[#out + 1] = { i, 0, false, d }
      end
    end
  end
  return out
end

-- play one single move (changes b)
function R.step(b, s, m)
  local f, t = m[1], m[2]
  if f == 25 then b[bar(s)] = b[bar(s)] - 1 else local j = idx(s, f); b[j] = b[j] - s end
  if t == 0 then
    b[off(s)] = b[off(s)] + 1
  else
    local j = idx(s, t)
    if b[j] == -s then b[j] = 0; b[bar(-s)] = b[bar(-s)] + 1 end
    b[j] = b[j] + s
  end
end

function R.dice_list(d1, d2)
  if d1 == d2 then return { d1, d1, d1, d1 } end
  return { d1, d2 }
end

local function without(ds, k)
  local r = {}
  for j = 1, #ds do if j ~= k then r[#r + 1] = ds[j] end end
  return r
end

-- the most of the dice ds side s can still play from b (memo: a table kept for one turn)
local function most(b, s, ds, memo)
  if #ds == 0 then return 0 end
  local k = R.key(b) .. table.concat(ds)
  local v = memo[k]
  if v then return v end
  local best, tried = 0, {}
  for i = 1, #ds do
    local d = ds[i]
    if not tried[d] then
      tried[d] = true
      local rest = without(ds, i)
      for _k, m in ipairs(R.singles(b, s, d)) do
        local c = copy(b)
        R.step(c, s, m)
        local u = 1 + most(c, s, rest, memo)
        if u > best then best = u end
        if best == #ds then break end
      end
    end
    if best == #ds then break end
  end
  memo[k] = best
  return best
end
R.most = most

-- the single moves that may be played next with the dice left (ds); start: the turn's first
-- move with two different dice, where the larger-die rule applies
function R.legal(b, s, ds, memo, start)
  memo = memo or {}
  local need = most(b, s, ds, memo)
  local out = {}
  if need == 0 then return out, 0 end
  local tried = {}
  for i = 1, #ds do
    local d = ds[i]
    if not tried[d] then
      tried[d] = true
      local rest = without(ds, i)
      for _k, m in ipairs(R.singles(b, s, d)) do
        local c = copy(b)
        R.step(c, s, m)
        if 1 + most(c, s, rest, memo) == need then out[#out + 1] = m end
      end
    end
  end
  if start and need == 1 and #ds == 2 and ds[1] ~= ds[2] then
    local big = math.max(ds[1], ds[2])
    local f = {}
    for _k, m in ipairs(out) do if m[4] == big then f[#f + 1] = m end end
    if #f > 0 then out = f end
  end
  return out, need
end

-- every play of a roll, one per resulting position: { moves = {...}, b = position after }
function R.plays(b, s, d1, d2)
  return R.plays_ds(b, s, R.dice_list(d1, d2), d1 ~= d2)
end

-- the same for the dice left in a turn (ds); start: two different dice not yet played, where the
-- larger-die rule applies
function R.plays_ds(b, s, ds, start)
  local memo, seen, visited, out = {}, {}, {}, {}
  local need = most(b, s, ds, memo)
  if need == 0 then return { { moves = {}, b = copy(b) } }, 0 end
  local function rec(cb, rest, seq, used)
    if used == need then
      local k = R.key(cb)
      if not seen[k] then seen[k] = true; out[#out + 1] = { moves = seq, b = cb } end
      return
    end
    local tried = {}
    for i = 1, #rest do
      local d = rest[i]
      if not tried[d] then
        tried[d] = true
        local r2 = without(rest, i)
        for _k, m in ipairs(R.singles(cb, s, d)) do
          local c = copy(cb)
          R.step(c, s, m)
          local vk = R.key(c) .. table.concat(r2)
          if not visited[vk] and used + 1 + most(c, s, r2, memo) == need then
            visited[vk] = true
            local seq2 = table.move(seq, 1, #seq, 1, {})
            seq2[#seq2 + 1] = m
            rec(c, r2, seq2, used + 1)
          end
        end
      end
    end
  end
  rec(b, ds, {}, 0)
  if start and need == 1 and #ds == 2 and ds[1] ~= ds[2] then
    local big = math.max(ds[1], ds[2])
    local f = {}
    for _k, p in ipairs(out) do if p.moves[1][4] == big then f[#f + 1] = p end end
    if #f > 0 then out = f end
  end
  return out, need
end

function R.pips(b, s)
  local n = 25 * b[bar(s)]
  for i = 1, 24 do
    local v = b[idx(s, i)] * s
    if v > 0 then n = n + i * v end
  end
  return n
end

function R.won(b, s) return b[off(s)] == R.CHECKERS end

-- the points a game won by `winner` is worth before the cube: 1, a gammon 2 (the loser has borne
-- off nothing), a backgammon 3 (and still has a checker on the bar or in the winner's home)
function R.result(b, winner)
  local l = -winner
  if b[off(l)] > 0 then return 1 end
  if b[bar(l)] > 0 then return 3 end
  for i = 19, 24 do
    if b[idx(l, i)] * l > 0 then return 3 end
  end
  return 2
end

-- "24/18 13/11*", "bar/22", "6/off"
function R.text(moves)
  local t = {}
  for i, m in ipairs(moves) do
    t[i] = (m[1] == 25 and 'bar' or tostring(m[1])) .. '/' .. (m[2] == 0 and 'off' or tostring(m[2])) .. (m[3] and '*' or '')
  end
  return #t > 0 and table.concat(t, ' ') or '(no move)'
end

-- the side-1 point number of side s's own point i
function R.point(s, i) return idx(s, i) end

-- test helper: perft-like count of distinct positions after one roll
function R.count_plays(b, s, d1, d2) local p = R.plays(b, s, d1, d2); return #p end

return R
