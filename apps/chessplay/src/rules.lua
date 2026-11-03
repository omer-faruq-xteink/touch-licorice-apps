-- The rules of chess, with no screen: positions, legal moves, check, mate, the draws, and moves
-- as UCI ("e2e4", "e7e8q") and SAN ("Nf3", "exd5", "O-O", "e8=Q+").
--
-- The board is a 10 x 12 mailbox (b[0..119]): a1 is 21, h1 28, a8 91, h8 98; the squares around
-- are OFF, so a knight or a slider stops there without bounds checks. Pieces are numbers: 1 pawn,
-- 2 knight, 3 bishop, 4 rook, 5 queen, 6 king, positive for White, negative for Black, 0 empty.
-- A move is one integer: from + to * 128 + promotion * 16384 + flag * 131072 (flag 1 en passant,
-- 2 castling, 4 a pawn's double step), so lists of moves are plain arrays of numbers.
--
-- make(pos, m) changes the position and unmake(pos, m) puts it back, the last move made first:
-- what unmake needs goes on a stack in the position (pos.st), so no table is made per move. Both
-- keep the squares of each side's pieces (pos.pl[side], counted in pos.pn[side], with pos.pi
-- giving each square's place in its list) so move generation visits only those, a material and
-- piece-square score (pos.score, White's view) and the material other than pawns (pos.npm).

local R = {}

local OFF = 7
R.OFF = OFF
local N_DIRS = { -21, -19, -12, -8, 8, 12, 19, 21 }
local B_DIRS = { -11, -9, 9, 11 }
local R_DIRS = { -10, -1, 1, 10 }
local K_DIRS = { -11, -10, -9, -1, 1, 9, 10, 11 }
R.VALUE = { 100, 320, 330, 500, 900, 0 }
local VALUE = R.VALUE
local CHARS = 'pnbrqk'

-- piece-square tables (the "simplified evaluation function"), a8 first as printed, White's view
local PST = {
  { 0, 0, 0, 0, 0, 0, 0, 0, 50, 50, 50, 50, 50, 50, 50, 50, 10, 10, 20, 30, 30, 20, 10, 10, 5, 5, 10, 25, 25, 10, 5, 5,
    0, 0, 0, 20, 20, 0, 0, 0, 5, -5, -10, 0, 0, -10, -5, 5, 5, 10, 10, -20, -20, 10, 10, 5, 0, 0, 0, 0, 0, 0, 0, 0 },
  { -50, -40, -30, -30, -30, -30, -40, -50, -40, -20, 0, 0, 0, 0, -20, -40, -30, 0, 10, 15, 15, 10, 0, -30,
    -30, 5, 15, 20, 20, 15, 5, -30, -30, 0, 15, 20, 20, 15, 0, -30, -30, 5, 10, 15, 15, 10, 5, -30,
    -40, -20, 0, 5, 5, 0, -20, -40, -50, -40, -30, -30, -30, -30, -40, -50 },
  { -20, -10, -10, -10, -10, -10, -10, -20, -10, 0, 0, 0, 0, 0, 0, -10, -10, 0, 5, 10, 10, 5, 0, -10,
    -10, 5, 5, 10, 10, 5, 5, -10, -10, 0, 10, 10, 10, 10, 0, -10, -10, 10, 10, 10, 10, 10, 10, -10,
    -10, 5, 0, 0, 0, 0, 5, -10, -20, -10, -10, -10, -10, -10, -10, -20 },
  { 0, 0, 0, 0, 0, 0, 0, 0, 5, 10, 10, 10, 10, 10, 10, 5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5,
    -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, 0, 0, 0, 5, 5, 0, 0, 0 },
  { -20, -10, -10, -5, -5, -10, -10, -20, -10, 0, 0, 0, 0, 0, 0, -10, -10, 0, 5, 5, 5, 5, 0, -10, -5, 0, 5, 5, 5, 5, 0, -5,
    0, 0, 5, 5, 5, 5, 0, -5, -10, 5, 5, 5, 5, 5, 0, -10, -10, 0, 5, 0, 0, 0, 0, -10, -20, -10, -10, -5, -5, -10, -10, -20 },
  { -30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30,
    -30, -40, -40, -50, -50, -40, -40, -30, -20, -30, -30, -40, -40, -30, -30, -20, -10, -20, -20, -20, -20, -20, -20, -10,
    20, 20, 0, 0, 0, 0, 20, 20, 20, 30, 10, 0, 0, 10, 30, 20 },
}
-- the king in the endgame: to the middle
R.KING_END = { -50, -40, -30, -20, -20, -30, -40, -50, -30, -20, -10, 0, 0, -10, -20, -30, -30, -10, 20, 30, 30, 20, -10, -30,
  -30, -10, 30, 40, 40, 30, -10, -30, -30, -10, 30, 40, 40, 30, -10, -30, -30, -10, 20, 30, 30, 20, -10, -30,
  -30, -30, 0, 0, 0, 0, -30, -30, -50, -30, -30, -30, -30, -30, -30, -50 }

-- the table index of a square for a side: 1..64, a8 first for White, mirrored for Black
local function pst_index(s, side)
  local f, r = (s - 21) % 10, (s - 21) // 10
  if side > 0 then return (7 - r) * 8 + f + 1 end
  return r * 8 + f + 1
end
R.pst_index = pst_index

-- the score a piece adds where it stands (White's view)
local function worth(p, s)
  if p > 0 then return VALUE[p] + PST[p][pst_index(s, 1)] end
  return -(VALUE[-p] + PST[-p][pst_index(s, -1)])
end

function R.square(name)                  -- 'e4' -> 55
  return 21 + (name:byte(2) - 49) * 10 + (name:byte(1) - 97)
end
function R.name(s)                       -- 55 -> 'e4'
  local f, r = (s - 21) % 10, (s - 21) // 10
  return string.char(97 + f, 49 + r)
end
function R.file(s) return (s - 21) % 10 end
function R.rank(s) return (s - 21) // 10 end

function R.move_from(m) return m % 128 end
function R.move_to(m) return (m // 128) % 128 end
function R.move_promo(m) return (m // 16384) % 8 end
function R.move_flag(m) return m // 131072 end
local function mv(from, to, promo, flag) return from + to * 128 + (promo or 0) * 16384 + (flag or 0) * 131072 end
R.mv = mv

------------------------------------------------------------------ positions

local START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
R.START = START

local function rescore(pos)
  local score, npm = 0, 0
  local pl, pn, pi = { [1] = {}, [-1] = {} }, { [1] = 0, [-1] = 0 }, {}
  for s = 21, 98 do
    local p = pos.b[s]
    if p ~= 0 and p ~= OFF then
      score = score + worth(p, s)
      local a = p > 0 and p or -p
      local side = p > 0 and 1 or -1
      if a ~= 1 and a ~= 6 then npm = npm + VALUE[a] end
      if a == 6 then pos.king[side] = s end
      pn[side] = pn[side] + 1
      pl[side][pn[side]] = s
      pi[s] = pn[side]
    end
  end
  pos.score, pos.npm = score, npm
  pos.pl, pos.pn, pos.pi = pl, pn, pi
  pos.st, pos.sp = {}, 0
end

function R.from_fen(fen)
  local rows, side, castle, ep, half, full = fen:match('^(%S+)%s+(%a)%s+(%S+)%s+(%S+)%s*(%d*)%s*(%d*)')
  if not rows then return nil end
  local b = {}
  for s = 0, 119 do b[s] = OFF end
  local r, f = 7, 0
  for ch in rows:gmatch('.') do
    if ch == '/' then r, f = r - 1, 0
    elseif ch:match('%d') then
      for _ = 1, tonumber(ch) do b[21 + r * 10 + f] = 0; f = f + 1 end
    else
      local k = CHARS:find(ch:lower(), 1, true)
      if not k then return nil end
      b[21 + r * 10 + f] = ch:lower() == ch and -k or k
      f = f + 1
    end
  end
  local c = 0
  if castle:find('K', 1, true) then c = c | 1 end
  if castle:find('Q', 1, true) then c = c | 2 end
  if castle:find('k', 1, true) then c = c | 4 end
  if castle:find('q', 1, true) then c = c | 8 end
  local pos = { b = b, side = side == 'b' and -1 or 1, castle = c, ep = ep ~= '-' and R.square(ep) or 0,
                half = tonumber(half) or 0, full = tonumber(full) or 1, king = {} }
  rescore(pos)
  return pos
end

function R.to_fen(pos)
  local rows = {}
  for r = 7, 0, -1 do
    local row, empty = {}, 0
    for f = 0, 7 do
      local p = pos.b[21 + r * 10 + f]
      if p == 0 then empty = empty + 1
      else
        if empty > 0 then row[#row + 1] = tostring(empty); empty = 0 end
        local ch = CHARS:sub(p > 0 and p or -p, p > 0 and p or -p)
        row[#row + 1] = p > 0 and ch:upper() or ch
      end
    end
    if empty > 0 then row[#row + 1] = tostring(empty) end
    rows[#rows + 1] = table.concat(row)
  end
  local c = pos.castle
  local cs = ((c & 1 ~= 0) and 'K' or '') .. ((c & 2 ~= 0) and 'Q' or '') .. ((c & 4 ~= 0) and 'k' or '') .. ((c & 8 ~= 0) and 'q' or '')
  return table.concat(rows, '/') .. ' ' .. (pos.side > 0 and 'w' or 'b') .. ' ' .. (cs ~= '' and cs or '-') .. ' ' ..
    (pos.ep ~= 0 and R.name(pos.ep) or '-') .. ' ' .. pos.half .. ' ' .. pos.full
end

-- what makes positions the same for the repetition rule: pieces, side, castling, en passant
function R.key(pos) return (R.to_fen(pos):match('^(%S+ %S+ %S+ %S+)')) end

------------------------------------------------------------------ attacks and moves

-- is square s attacked by side `by` (1 White, -1 Black)?
local function attacked(pos, s, by)
  local b = pos.b
  -- pawns: a white pawn attacks up the board (from s - 9 and s - 11)
  if by > 0 then
    if b[s - 9] == 1 or b[s - 11] == 1 then return true end
  else
    if b[s + 9] == -1 or b[s + 11] == -1 then return true end
  end
  local kn, ki, bi, ro, qu = 2 * by, 6 * by, 3 * by, 4 * by, 5 * by
  for i = 1, 8 do
    if b[s + N_DIRS[i]] == kn then return true end
    if b[s + K_DIRS[i]] == ki then return true end
  end
  for i = 1, 4 do
    local d = B_DIRS[i]
    local t = s + d
    local p = b[t]
    while p == 0 do t = t + d; p = b[t] end
    if p == bi or p == qu then return true end
    d = R_DIRS[i]
    t = s + d
    p = b[t]
    while p == 0 do t = t + d; p = b[t] end
    if p == ro or p == qu then return true end
  end
  return false
end
R.attacked = attacked

-- can move m leave its own king (on square king) in check? Only a king move, en passant, a move
-- made while in check, or a move of a piece on a line (rank, file or diagonal) with its king can:
-- for every other move the test after making it is skipped, which is most of the work saved
local function needs_check(m, king, in_check)
  if in_check then return true end
  local from = m % 128
  if from == king or m // 131072 == 1 then return true end
  local df = (from - 21) % 10 - (king - 21) % 10
  local dr = (from - 21) // 10 - (king - 21) // 10
  return df == 0 or dr == 0 or df == dr or df == -dr
end
R.needs_check = needs_check

function R.in_check(pos, side)
  side = side or pos.side
  return attacked(pos, pos.king[side], -side)
end

-- pseudo-legal moves (the king may be left in check) into list from n + 1; captures_only for the
-- quiescence search (promotions count as captures). Returns the new count.
local function gen(pos, list, n, captures_only)
  local b, side = pos.b, pos.side
  local fwd, start_rank, last_rank = side > 0 and 10 or -10, side > 0 and 1 or 6, side > 0 and 7 or 0
  local pl = pos.pl[side]
  for i = 1, pos.pn[side] do
    local s = pl[i]
    local p = b[s] * side
    do
      if p == 1 then
        local t = s + fwd
        local promo = (t - 21) // 10 == last_rank
        if b[t] == 0 then
          if promo then
            for q = 5, 2, -1 do n = n + 1; list[n] = s + t * 128 + q * 16384 end
          elseif not captures_only then
            n = n + 1; list[n] = s + t * 128
            if (s - 21) // 10 == start_rank and b[t + fwd] == 0 then n = n + 1; list[n] = s + (t + fwd) * 128 + 4 * 131072 end
          end
        end
        -- the two captures (no table for the directions: this runs for every pawn of every position)
        for k = 1, 2 do
          local c = k == 1 and t - 1 or t + 1
          local q = b[c]
          if q ~= OFF and q * side < 0 then
            if promo then
              for pr = 5, 2, -1 do n = n + 1; list[n] = s + c * 128 + pr * 16384 end
            else n = n + 1; list[n] = s + c * 128 end
          elseif c == pos.ep and q == 0 then
            n = n + 1; list[n] = s + c * 128 + 131072
          end
        end
      elseif p == 2 or p == 6 then
        local dirs = p == 2 and N_DIRS or K_DIRS
        for i = 1, 8 do
          local t = s + dirs[i]
          local q = b[t]
          if q ~= OFF and (q == 0 and not captures_only or q * side < 0) then n = n + 1; list[n] = s + t * 128 end
        end
        if p == 6 and not captures_only then
          -- castling: the rights, the squares between empty, the king not in, through or into check
          local k_bit, q_bit = side > 0 and 1 or 4, side > 0 and 2 or 8
          if pos.castle & k_bit ~= 0 and b[s + 1] == 0 and b[s + 2] == 0 and b[s + 3] == 4 * side and
              not attacked(pos, s, -side) and not attacked(pos, s + 1, -side) and not attacked(pos, s + 2, -side) then
            n = n + 1; list[n] = mv(s, s + 2, 0, 2)
          end
          if pos.castle & q_bit ~= 0 and b[s - 1] == 0 and b[s - 2] == 0 and b[s - 3] == 0 and b[s - 4] == 4 * side and
              not attacked(pos, s, -side) and not attacked(pos, s - 1, -side) and not attacked(pos, s - 2, -side) then
            n = n + 1; list[n] = mv(s, s - 2, 0, 2)
          end
        end
      else
        local dirs = p == 3 and B_DIRS or p == 4 and R_DIRS or K_DIRS
        for i = 1, #dirs do
          local d = dirs[i]
          local t = s + d
          local q = b[t]
          while q == 0 do
            if not captures_only then n = n + 1; list[n] = s + t * 128 end
            t = t + d; q = b[t]
          end
          if q ~= OFF and q * side < 0 then n = n + 1; list[n] = s + t * 128 end
        end
      end
    end
  end
  return n
end
R.gen = gen

-- castling rights lost when a piece leaves or reaches a square
local KEEP = {}
for s = 0, 119 do KEEP[s] = 15 end
KEEP[25], KEEP[28], KEEP[21] = 15 - 3, 15 - 1, 15 - 2       -- e1, h1, a1
KEEP[95], KEEP[98], KEEP[91] = 15 - 12, 15 - 4, 15 - 8      -- e8, h8, a8

-- the piece lists: a piece taken leaves its side's list (the last one takes its place), and comes
-- back at the end on unmake; a piece moving keeps its place
local function list_remove(pos, side, s)
  local pl, pi = pos.pl[side], pos.pi
  local n = pos.pn[side]
  local i = pi[s]
  local last = pl[n]
  pl[i], pi[last] = last, i
  pl[n], pi[s] = nil, nil
  pos.pn[side] = n - 1
end
local function list_add(pos, side, s)
  local n = pos.pn[side] + 1
  pos.pl[side][n], pos.pi[s], pos.pn[side] = s, n, n
end
local function list_move(pos, side, from, to)
  local i = pos.pi[from]
  pos.pl[side][i], pos.pi[to], pos.pi[from] = to, i, nil
end

function R.make(pos, m)
  local b = pos.b
  local from, to = m % 128, (m // 128) % 128
  local promo, flag = (m // 16384) % 8, m // 131072
  local p, side = b[from], pos.side
  local captured = b[to]
  local st, sp = pos.st, pos.sp
  st[sp + 1], st[sp + 2], st[sp + 3], st[sp + 4], st[sp + 5], st[sp + 6] = captured, pos.castle, pos.ep, pos.half, pos.score, pos.npm
  pos.sp = sp + 6
  local score = pos.score - worth(p, from)
  if captured ~= 0 then
    score = score - worth(captured, to)
    local a = captured > 0 and captured or -captured
    if a ~= 1 then pos.npm = pos.npm - VALUE[a] end
    list_remove(pos, -side, to)
  end
  b[from] = 0
  if flag == 1 then                                    -- en passant: the pawn beside goes
    local c = to - 10 * side
    score = score - worth(b[c], c)
    b[c] = 0
    list_remove(pos, -side, c)
  elseif flag == 2 then                                -- castling: the rook too
    local rf, rt = to > from and from + 3 or from - 4, to > from and from + 1 or from - 1
    score = score - worth(b[rf], rf) + worth(b[rf], rt)
    b[rt], b[rf] = b[rf], 0
    list_move(pos, side, rf, rt)
  end
  local pi = pos.pi
  local i = pi[from]
  pos.pl[side][i], pi[to], pi[from] = to, i, nil
  if promo ~= 0 then
    p = promo * side
    pos.npm = pos.npm + VALUE[promo]
  end
  b[to] = p
  score = score + worth(p, to)
  if p == 6 or p == -6 then pos.king[side] = to end
  pos.castle = pos.castle & KEEP[from] & KEEP[to]
  pos.ep = flag == 4 and (from + to) // 2 or 0
  pos.half = (p == 1 or p == -1 or captured ~= 0) and 0 or pos.half + 1
  if side < 0 then pos.full = pos.full + 1 end
  pos.side = -side
  pos.score = score
end

function R.unmake(pos, m)
  local b = pos.b
  local from, to = m % 128, (m // 128) % 128
  local promo, flag = (m // 16384) % 8, m // 131072
  local side = -pos.side
  pos.side = side
  local st, sp = pos.st, pos.sp - 6
  pos.sp = sp
  local captured = st[sp + 1]
  local p = b[to]
  if promo ~= 0 then p = side end
  b[from], b[to] = p, captured
  local pi = pos.pi
  local i = pi[to]
  pos.pl[side][i], pi[from], pi[to] = from, i, nil
  if captured ~= 0 then list_add(pos, -side, to) end
  if p == 6 or p == -6 then pos.king[side] = from end
  if flag == 1 then
    local c = to - 10 * side
    b[c] = -side
    list_add(pos, -side, c)
  elseif flag == 2 then
    local rf, rt = to > from and from + 3 or from - 4, to > from and from + 1 or from - 1
    b[rf], b[rt] = b[rt], 0
    list_move(pos, side, rt, rf)
  end
  if side < 0 then pos.full = pos.full - 1 end
  pos.castle, pos.ep, pos.half, pos.score, pos.npm = st[sp + 2], st[sp + 3], st[sp + 4], st[sp + 5], st[sp + 6]
end

-- the legal moves of the side to move
function R.legal(pos)
  local list = {}
  local n = gen(pos, list, 0, false)
  local out = {}
  local side = pos.side
  local king = pos.king[side]
  local chk = attacked(pos, king, -side)
  for i = 1, n do
    local m = list[i]
    local u = R.make(pos, m)
    if not needs_check(m, king, chk) or not attacked(pos, pos.king[side], -side) then out[#out + 1] = m end
    R.unmake(pos, m, u)
  end
  return out
end

------------------------------------------------------------------ notation

function R.uci(m)
  local promo = (m // 16384) % 8
  return R.name(m % 128) .. R.name((m // 128) % 128) .. (promo ~= 0 and CHARS:sub(promo, promo) or '')
end

-- the legal move a UCI string names, or nil
function R.from_uci(pos, s)
  if type(s) ~= 'string' or #s < 4 then return nil end
  for _, m in ipairs(R.legal(pos)) do
    if R.uci(m) == s or (R.move_promo(m) == 0 and R.uci(m) == s:sub(1, 4) and #s == 4) then return m end
  end
  return nil
end

-- SAN, with + or # (needs the position before the move)
function R.san(pos, m)
  local b = pos.b
  local from, to, promo, flag = m % 128, (m // 128) % 128, (m // 16384) % 8, m // 131072
  local p = b[from]
  local a = p > 0 and p or -p
  local s
  if flag == 2 then
    s = to > from and 'O-O' or 'O-O-O'
  elseif a == 1 then
    s = (b[to] ~= 0 or flag == 1) and (R.name(from):sub(1, 1) .. 'x' .. R.name(to)) or R.name(to)
    if promo ~= 0 then s = s .. '=' .. CHARS:sub(promo, promo):upper() end
  else
    -- another piece of the same kind that can go to the same square: name the file, the rank or both
    local same_file, same_rank, other = false, false, false
    for _, o in ipairs(R.legal(pos)) do
      local of = o % 128
      if of ~= from and (o // 128) % 128 == to and b[of] == p then
        other = true
        if R.file(of) == R.file(from) then same_file = true end
        if R.rank(of) == R.rank(from) then same_rank = true end
      end
    end
    local dis = ''
    if other then
      local n = R.name(from)
      if not same_file then dis = n:sub(1, 1)
      elseif not same_rank then dis = n:sub(2, 2)
      else dis = n end
    end
    s = CHARS:sub(a, a):upper() .. dis .. (b[to] ~= 0 and 'x' or '') .. R.name(to)
  end
  local u = R.make(pos, m)
  if R.in_check(pos) then s = s .. (#R.legal(pos) == 0 and '#' or '+') end
  R.unmake(pos, m, u)
  return s
end

------------------------------------------------------------------ the end of a game

-- too little to mate: kings alone, or one minor piece, or bishops all on one colour
function R.insufficient(pos)
  local minors, bishops_colour = 0, {}
  for s = 21, 98 do
    local p = pos.b[s]
    if p ~= 0 and p ~= OFF then
      local a = p > 0 and p or -p
      if a == 1 or a == 4 or a == 5 then return false end
      if a == 2 then minors = minors + 1 end
      if a == 3 then minors = minors + 1; bishops_colour[(R.file(s) + R.rank(s)) % 2] = true end
    end
  end
  if minors <= 1 then return true end
  -- only bishops, all on squares of one colour
  local knights = false
  for s = 21, 98 do local p = pos.b[s]; if p == 2 or p == -2 then knights = true end end
  return not knights and not (bishops_colour[0] and bishops_colour[1])
end

-- nil while the game goes on, else (result, why): result 1 White wins, -1 Black wins, 0 a draw.
-- keys: the R.key of every position so far (for the repetition rule), the current one last.
function R.outcome(pos, keys)
  if #R.legal(pos) == 0 then
    if R.in_check(pos) then return -pos.side, 'checkmate' end
    return 0, 'stalemate'
  end
  if pos.half >= 100 then return 0, 'the 50-move rule' end
  if R.insufficient(pos) then return 0, 'too little material' end
  if keys and #keys > 0 then
    local now, seen = keys[#keys], 0
    for i = 1, #keys do if keys[i] == now then seen = seen + 1 end end
    if seen >= 3 then return 0, 'threefold repetition' end
  end
  return nil
end

-- perft: the number of positions after `depth` plies (the standard check of a move generator)
function R.perft(pos, depth)
  if depth == 0 then return 1 end
  local list = {}
  local n = gen(pos, list, 0, false)
  local total, side = 0, pos.side
  local king = pos.king[side]
  local chk = attacked(pos, king, -side)
  for i = 1, n do
    local m = list[i]
    local u = R.make(pos, m)
    if not needs_check(m, king, chk) or not attacked(pos, pos.king[side], -side) then total = total + R.perft(pos, depth - 1) end
    R.unmake(pos, m, u)
  end
  return total
end

return R
