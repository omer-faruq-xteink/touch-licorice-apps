-- The rules of two draughts games, with no screen: English checkers and Turkish draughts (Dama).
--
-- The board is b[1..64], square = row * 8 + col + 1 with row 0 the first side's back row (at the
-- bottom for it) and col 0 its left. Pieces: 1 a man and 2 a king of the side that moves first
-- (side 1), -1 and -2 the other side's (side -1). Side 1 starts on rows 0-2 (checkers) or 1-2
-- (Dama) and moves up the board.
--
-- English checkers: 12 men each on the dark squares; men move one square diagonally forward and
-- capture by jumping an adjacent piece diagonally forward; kings move and jump one square in any
-- diagonal direction. Capturing is compulsory and a capture goes on while the piece can jump
-- again (any such line may be chosen); the pieces taken stay on the board until the move ends and
-- cannot be jumped twice. A man reaching the far row is crowned, and that ends the move.
--
-- Dama: 16 men each on the second and third rows; men move one square forward or sideways and
-- capture the same way; kings move any distance along a row or column and capture a piece any
-- distance away, landing on any empty square beyond it. Pieces taken leave the board at once, so
-- their squares can be crossed later in the same move; a king may not turn back (180 degrees)
-- between two captures. The line that takes the most pieces must be played (men and kings count
-- the same). A man that reaches the far row during a capture finishes it as a man and is crowned
-- when the move ends.
--
-- A move is a table { from, to, caps = { squares }, cv = { pieces taken }, path = { squares
-- landed on }, promo = true when it crowns }; make and unmake change b in place. The side to move
-- with no legal move has lost.

local R = {}

R.CHECKERS, R.DAMA = 'checkers', 'dama'

local function sq(row, col) return row * 8 + col + 1 end
local function row_of(s) return (s - 1) // 8 end
local function col_of(s) return (s - 1) % 8 end
R.sq, R.row, R.col = sq, row_of, col_of

function R.name(s) return string.char(97 + col_of(s), 49 + row_of(s)) end
function R.square(n) return sq(n:byte(2) - 49, n:byte(1) - 97) end

-- a dark square of checkers (a1 is dark, as on a chess board)
function R.dark(s) return (row_of(s) + col_of(s)) % 2 == 0 end

------------------------------------------------------------------ positions

function R.new(variant)
  local b = {}
  for s = 1, 64 do b[s] = 0 end
  for s = 1, 64 do
    local r = row_of(s)
    if variant == R.DAMA then
      if r == 1 or r == 2 then b[s] = 1 elseif r == 5 or r == 6 then b[s] = -1 end
    elseif R.dark(s) then
      if r <= 2 then b[s] = 1 elseif r >= 5 then b[s] = -1 end
    end
  end
  return { b = b, side = 1, variant = variant, quiet = 0 }
end

-- the position as text: the variant, the side to move and the 64 squares (o O x X .)
local CH = { [1] = 'o', [2] = 'O', [-1] = 'x', [-2] = 'X', [0] = '.' }
function R.key(pos)
  local t = {}
  for s = 1, 64 do t[s] = CH[pos.b[s]] end
  return (pos.side > 0 and '1' or '2') .. table.concat(t)
end

function R.from_key(variant, k, quiet)
  local b = {}
  local back = { o = 1, O = 2, x = -1, X = -2 }
  for s = 1, 64 do b[s] = back[k:sub(s + 1, s + 1)] or 0 end
  return { b = b, side = k:sub(1, 1) == '1' and 1 or -1, variant = variant, quiet = quiet or 0 }
end

function R.copy(pos)
  local b = {}
  for s = 1, 64 do b[s] = pos.b[s] end
  return { b = b, side = pos.side, variant = pos.variant, quiet = pos.quiet }
end

------------------------------------------------------------------ moves

local DIAG = { { 1, -1 }, { 1, 1 }, { -1, -1 }, { -1, 1 } }
local ORTHO = { { 1, 0 }, { 0, -1 }, { 0, 1 }, { -1, 0 } }

-- the directions a piece may go, made once: a man only forward (and, in Dama, sideways)
local DIRS = {
  [R.CHECKERS] = { [1] = { DIAG[1], DIAG[2] }, [-1] = { DIAG[3], DIAG[4] }, [2] = DIAG, [-2] = DIAG },
  [R.DAMA] = { [1] = { { 1, 0 }, { 0, -1 }, { 0, 1 } }, [-1] = { { -1, 0 }, { 0, -1 }, { 0, 1 } }, [2] = ORTHO, [-2] = ORTHO },
}
-- the square one step from s in direction d (a table of { dr, dc }), or 0 off the board
local STEP = {}
for _, list in ipairs({ DIAG, ORTHO }) do
  for _, d in ipairs(list) do
    local t = {}
    for s = 1, 64 do
      local r, c = (s - 1) // 8 + d[1], (s - 1) % 8 + d[2]
      t[s] = (r >= 0 and r < 8 and c >= 0 and c < 8) and (r * 8 + c + 1) or 0
    end
    STEP[d] = t
  end
end
for _, v in pairs(DIRS) do
  for _, list in pairs(v) do
    for _, d in ipairs(list) do
      if not STEP[d] then
        for _, o in ipairs({ DIAG, ORTHO }) do
          for _, e in ipairs(o) do if e[1] == d[1] and e[2] == d[2] then STEP[d] = STEP[e] end end
        end
      end
    end
  end
end
local OPP = {}                                       -- the direction straight back
for _, list in ipairs({ DIAG, ORTHO }) do
  for _, d in ipairs(list) do
    for _, e in ipairs(list) do if e[1] == -d[1] and e[2] == -d[2] then OPP[d] = e end end
  end
end
for _, v in pairs(DIRS) do
  for _, list in pairs(v) do
    for _, d in ipairs(list) do
      if not OPP[d] then
        for _, e in ipairs(ORTHO) do if e[1] == -d[1] and e[2] == -d[2] then OPP[d] = e end end
      end
    end
  end
end

local NONE = {}                                      -- the caps and cv of a plain move
local function last_row(side) return side > 0 and 7 or 0 end

local function copy(t) local o = {}; for i = 1, #t do o[i] = t[i] end; return o end

-- English checkers: the jumps from s, the taken pieces staying on the board (marked in taken)
local function checkers_jumps(b, s, p, side, caps, cv, path, taken, out)
  local more = false
  local ds = DIRS[R.CHECKERS][p]
  for i = 1, #ds do
    local step = STEP[ds[i]]
    local over = step[s]
    local to = over ~= 0 and step[over] or 0
    if to ~= 0 and b[over] * side < 0 and not taken[over] and b[to] == 0 then
      more = true
      local n = #caps + 1
      caps[n], cv[n], path[n] = over, b[over], to
      taken[over] = true
      if (p == 1 or p == -1) and (to - 1) // 8 == last_row(side) then
        out[#out + 1] = { caps = copy(caps), cv = copy(cv), path = copy(path), promo = true }   -- crowned: it stops
      else
        checkers_jumps(b, to, p, side, caps, cv, path, taken, out)
      end
      taken[over] = nil
      caps[n], cv[n], path[n] = nil, nil, nil
    end
  end
  if not more and #caps > 0 then out[#out + 1] = { caps = copy(caps), cv = copy(cv), path = copy(path) } end
end

-- Dama: the jumps from s, a taken piece leaving the board at once; last: the direction of the
-- previous jump (a king may not go straight back)
local function dama_jumps(b, s, p, side, caps, cv, path, last, out)
  local king = p == 2 or p == -2
  local more = false
  local ds = DIRS[R.DAMA][p]
  for i = 1, #ds do
    local d = ds[i]
    if not (king and last and OPP[last] == d) then
      local step = STEP[d]
      local over = step[s]
      if king then while over ~= 0 and b[over] == 0 do over = step[over] end end
      if over ~= 0 and b[over] * side < 0 then
        local to = step[over]
        while to ~= 0 and b[to] == 0 do
          more = true
          local victim = b[over]
          b[over] = 0
          local n = #caps + 1
          caps[n], cv[n], path[n] = over, victim, to
          dama_jumps(b, to, p, side, caps, cv, path, d, out)
          caps[n], cv[n], path[n] = nil, nil, nil
          b[over] = victim
          if not king then break end                      -- a man lands just beyond
          to = step[to]
        end
      end
    end
  end
  if not more and #caps > 0 then out[#out + 1] = { caps = copy(caps), cv = copy(cv), path = copy(path) } end
end

-- can the side to move capture? (the end of a search asks this at every position: no tables made)
function R.has_capture(pos)
  local b, side = pos.b, pos.side
  local dirs = DIRS[pos.variant]
  local dama = pos.variant == R.DAMA
  for s = 1, 64 do
    local p = b[s]
    if p * side > 0 then
      local flying = dama and (p == 2 or p == -2)
      local ds = dirs[p]
      for i = 1, #ds do
        local step = STEP[ds[i]]
        local over = step[s]
        if flying then while over ~= 0 and b[over] == 0 do over = step[over] end end
        if over ~= 0 and b[over] * side < 0 then
          local to = step[over]
          if to ~= 0 and b[to] == 0 then return true end
        end
      end
    end
  end
  return false
end

-- every legal move of the side to move
function R.moves(pos)
  local b, side, variant = pos.b, pos.side, pos.variant
  local dirs = DIRS[variant]
  local dama = variant == R.DAMA
  local jumps = {}
  local caps, cv, path, taken = {}, {}, {}, {}
  for s = 1, 64 do
    local p = b[s]
    if p * side > 0 then
      local n0 = #jumps
      b[s] = 0                                          -- lifted: it may cross its own square
      if dama then dama_jumps(b, s, p, side, caps, cv, path, nil, jumps)
      else checkers_jumps(b, s, p, side, caps, cv, path, taken, jumps) end
      b[s] = p
      for i = n0 + 1, #jumps do
        local j = jumps[i]
        j.from, j.to, j.piece = s, j.path[#j.path], p
      end
    end
  end
  local list
  if #jumps > 0 then
    list = jumps
    if dama then
      -- the line taking the most must be played
      local most = 0
      for i = 1, #jumps do if #jumps[i].caps > most then most = #jumps[i].caps end end
      list = {}
      for i = 1, #jumps do if #jumps[i].caps == most then list[#list + 1] = jumps[i] end end
    end
  else
    list = {}
    for s = 1, 64 do
      local p = b[s]
      if p * side > 0 then
        local slide = dama and (p == 2 or p == -2)
        local ds = dirs[p]
        for i = 1, #ds do
          local step = STEP[ds[i]]
          local t = step[s]
          while t ~= 0 and b[t] == 0 do
            list[#list + 1] = { from = s, to = t, caps = NONE, cv = NONE, piece = p }
            if not slide then break end
            t = step[t]
          end
        end
      end
    end
  end
  local back = last_row(side)
  for i = 1, #list do
    local m = list[i]
    if (m.piece == 1 or m.piece == -1) and (m.to - 1) // 8 == back then m.promo = true end
  end
  return list
end

function R.make(pos, m)
  local b = pos.b
  b[m.from] = 0
  for _, s in ipairs(m.caps) do b[s] = 0 end
  b[m.to] = m.promo and 2 * pos.side or m.piece
  m.quiet = pos.quiet
  -- the draw count: moves of kings only, without a capture
  pos.quiet = (#m.caps > 0 or m.piece == 1 or m.piece == -1) and 0 or pos.quiet + 1
  pos.side = -pos.side
end

function R.unmake(pos, m)
  local b = pos.b
  pos.side = -pos.side
  b[m.to] = 0
  for i, s in ipairs(m.caps) do b[s] = m.cv[i] end
  b[m.from] = m.piece
  pos.quiet = m.quiet
end

-- "c3-d4", or "c3xe5xc7" for a capture
function R.text(m)
  if #m.caps == 0 then return R.name(m.from) .. '-' .. R.name(m.to) end   -- a plain move has no path
  local t = { R.name(m.from) }
  for _, s in ipairs(m.path) do t[#t + 1] = R.name(s) end
  return table.concat(t, 'x')
end

-- the legal move that R.text names, or nil
function R.find(pos, text)
  for _, m in ipairs(R.moves(pos)) do if R.text(m) == text then return m end end
  return nil
end

function R.count(pos)
  local n = { [1] = 0, [-1] = 0 }
  for s = 1, 64 do local p = pos.b[s]; if p > 0 then n[1] = n[1] + 1 elseif p < 0 then n[-1] = n[-1] + 1 end end
  return n
end

-- nil while the game goes on, else (result, why): 1 or -1 the side that won, 0 a draw. keys: the
-- R.key of every position so far, the current one last (the repetition rule).
R.QUIET_PLIES = 80
function R.outcome(pos, keys)
  if #R.moves(pos) == 0 then
    local n = R.count(pos)
    return -pos.side, n[pos.side] == 0 and 'no pieces left' or 'no move left'
  end
  if pos.quiet >= R.QUIET_PLIES then return 0, '40 moves without a capture' end
  if keys and #keys > 0 then
    local now, seen = keys[#keys], 0
    for i = 1, #keys do if keys[i] == now then seen = seen + 1 end end
    if seen >= 3 then return 0, 'threefold repetition' end
  end
  return nil
end

-- perft: the number of positions after `depth` moves (a move being a whole capture line)
function R.perft(pos, depth)
  if depth == 0 then return 1 end
  local total = 0
  for _, m in ipairs(R.moves(pos)) do
    R.make(pos, m)
    total = total + R.perft(pos, depth - 1)
    R.unmake(pos, m)
  end
  return total
end

return R
