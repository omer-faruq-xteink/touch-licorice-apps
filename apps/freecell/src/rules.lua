-- FreeCell rules and solver, shared by the game and by the offline tools (make_solutions.py).
--
-- A card is 1..52: rank (c - 1) % 13 + 1 (1 = ace .. 13 = king), suit (c - 1) // 13 (0 clubs,
-- 1 diamonds, 2 hearts, 3 spades; diamonds and hearts are red). A position: cols[1..8] (bottom
-- first), free[1..4] (0 = empty), home[0..3] (the top rank on each foundation).
-- A move: { from = 'c' | 'f', fi = index, to = 'c' | 'f' | 'h', ti = index (suit for 'h'), n = cards }.

local R = {}

function R.rank(c) return (c - 1) % 13 + 1 end
function R.suit(c) return (c - 1) // 13 end
function R.red(c) local s = (c - 1) // 13; return s == 1 or s == 2 end

-- Microsoft FreeCell deal number n (the classic generator: deal 1 starts JD 2D 9H JC ...)
function R.deal(n)
  local deck = {}
  for i = 0, 51 do deck[i + 1] = i end
  local seed, out = n, {}
  for i = 0, 51 do
    seed = (seed * 214013 + 2531011) & 0xffffffff
    local r = (seed >> 16) & 0x7fff
    local j = r % (52 - i) + 1
    deck[j], deck[52 - i] = deck[52 - i], deck[j]
    out[#out + 1] = deck[52 - i]
  end
  local cols = {}
  for k = 1, 8 do cols[k] = {} end
  local SUIT = { [0] = 0, [1] = 1, [2] = 2, [3] = 3 }      -- MS order is clubs, diamonds, hearts, spades too
  for k, x in ipairs(out) do
    local rank, suit = x // 4 + 1, SUIT[x % 4]
    local col = cols[(k - 1) % 8 + 1]
    col[#col + 1] = suit * 13 + rank
  end
  return { cols = cols, free = { 0, 0, 0, 0 }, home = { [0] = 0, 0, 0, 0 } }
end

function R.copy(p)
  local cols = {}
  for k = 1, 8 do local c = {}; for i, v in ipairs(p.cols[k]) do c[i] = v end; cols[k] = c end
  return { cols = cols, free = { p.free[1], p.free[2], p.free[3], p.free[4] },
           home = { [0] = p.home[0], p.home[1], p.home[2], p.home[3] } }
end

-- a compact string for a position (saving, undo) and back
function R.encode(p)
  local parts = {}
  for k = 1, 8 do
    local t = {}
    for i, v in ipairs(p.cols[k]) do t[i] = string.char(64 + v) end
    parts[k] = table.concat(t)
  end
  local f = {}
  for i = 1, 4 do f[i] = string.char(64 + p.free[i]) end
  return table.concat(parts, '|') .. '|' .. table.concat(f) .. '|' .. p.home[0] .. ',' .. p.home[1] .. ',' .. p.home[2] .. ',' .. p.home[3]
end
function R.decode(s)
  local parts = {}
  for part in (s .. '|'):gmatch('([^|]*)|') do parts[#parts + 1] = part end
  if #parts ~= 10 then return nil end
  local p = { cols = {}, free = {}, home = {} }
  for k = 1, 8 do
    local c = {}
    for i = 1, #parts[k] do c[i] = parts[k]:byte(i) - 64 end
    p.cols[k] = c
  end
  for i = 1, 4 do p.free[i] = (parts[9]:byte(i) or 64) - 64 end
  local h0, h1, h2, h3 = parts[10]:match('^(%d+),(%d+),(%d+),(%d+)$')
  if not h0 then return nil end
  p.home = { [0] = tonumber(h0), tonumber(h1), tonumber(h2), tonumber(h3) }
  return p
end

-- the same position whatever the order of the free cells and of the columns
function R.key(p)
  local cols = {}
  for k = 1, 8 do
    local t = {}
    for i, v in ipairs(p.cols[k]) do t[i] = string.char(64 + v) end
    cols[k] = table.concat(t)
  end
  table.sort(cols)
  local f = { p.free[1], p.free[2], p.free[3], p.free[4] }
  table.sort(f)
  return table.concat(cols, '|') .. '#' .. f[1] .. ',' .. f[2] .. ',' .. f[3] .. ',' .. f[4]
end

function R.won(p) return p.home[0] + p.home[1] + p.home[2] + p.home[3] == 52 end

local function fits(c, onto) return R.rank(onto) == R.rank(c) + 1 and R.red(onto) ~= R.red(c) end
R.fits = fits

-- cards that can move as one from the top of column k: the alternating descending run
function R.run(p, k)
  local col = p.cols[k]
  local n = #col
  if n == 0 then return 0 end
  local len = 1
  while len < n and fits(col[n - len + 1], col[n - len]) do len = len + 1 end
  return len
end

-- how many cards may move at once onto column `to` (free cells and empty columns as storage)
function R.capacity(p, to)
  local free, empty = 0, 0
  for i = 1, 4 do if p.free[i] == 0 then free = free + 1 end end
  for k = 1, 8 do if #p.cols[k] == 0 and k ~= to then empty = empty + 1 end end
  return (free + 1) * (1 << empty)
end

function R.to_home_ok(p, c) return p.home[R.suit(c)] == R.rank(c) - 1 end

-- is the move legal? (n cards from the top of a column; one card from a free cell)
function R.legal(p, m)
  local c
  if m.from == 'c' then
    local col = p.cols[m.fi]
    if #col < m.n or m.n < 1 then return false end
    if m.n > R.run(p, m.fi) then return false end
    c = col[#col - m.n + 1]
  else
    c = p.free[m.fi]
    if c == 0 or m.n ~= 1 then return false end
  end
  if m.to == 'h' then
    if m.n ~= 1 then return false end
    local top = m.from == 'c' and p.cols[m.fi][#p.cols[m.fi]] or c
    return R.to_home_ok(p, top) and R.suit(top) == m.ti
  elseif m.to == 'f' then
    return m.n == 1 and p.free[m.ti] == 0
  else
    if m.from == 'c' and m.ti == m.fi then return false end
    local dest = p.cols[m.ti]
    if #dest > 0 and not fits(c, dest[#dest]) then return false end
    return m.n <= R.capacity(p, m.ti)
  end
end

function R.apply(p, m)
  local cards = {}
  if m.from == 'c' then
    local col = p.cols[m.fi]
    for i = #col - m.n + 1, #col do cards[#cards + 1] = col[i] end
    for _i = 1, m.n do col[#col] = nil end
  else
    cards[1] = p.free[m.fi]; p.free[m.fi] = 0
  end
  if m.to == 'h' then p.home[R.suit(cards[1])] = R.rank(cards[1])
  elseif m.to == 'f' then p.free[m.ti] = cards[1]
  else
    local dest = p.cols[m.ti]
    for _i, c in ipairs(cards) do dest[#dest + 1] = c end
  end
end

-- cards no other card could ever need go home by themselves: an ace or two, or a card whose
-- rank is at most one above both foundations of the other colour. Returns the moves made.
function R.autoplay(p)
  local made = {}
  local moved = true
  while moved do
    moved = false
    for k = 1, 12 do
      local c, m
      if k <= 8 then
        local col = p.cols[k]
        c = col[#col]
        m = { from = 'c', fi = k, n = 1 }
      else
        c = p.free[k - 8]
        if c == 0 then c = nil end
        m = { from = 'f', fi = k - 8, n = 1 }
      end
      if c and R.to_home_ok(p, c) then
        local r = R.rank(c)
        local o1, o2
        if R.red(c) then o1, o2 = p.home[0], p.home[3] else o1, o2 = p.home[1], p.home[2] end
        if r <= 2 or (o1 >= r - 1 and o2 >= r - 1) then
          m.to, m.ti = 'h', R.suit(c)
          R.apply(p, m)
          made[#made + 1] = m
          moved = true
        end
      end
    end
  end
  return made
end

-- every legal move (one free cell stands for all empty ones, one empty column for all)
function R.moves(p)
  local out = {}
  local free_slot
  for i = 1, 4 do if p.free[i] == 0 then free_slot = free_slot or i end end
  local empty_col
  for k = 1, 8 do if #p.cols[k] == 0 then empty_col = empty_col or k end end
  -- sources: column tops (runs) and free cells
  for k = 1, 8 do
    local col = p.cols[k]
    if #col > 0 then
      local top = col[#col]
      if R.to_home_ok(p, top) then out[#out + 1] = { from = 'c', fi = k, to = 'h', ti = R.suit(top), n = 1 } end
      local run = R.run(p, k)
      for t = 1, 8 do
        if t ~= k then
          local dest = p.cols[t]
          if #dest > 0 then
            local need = R.rank(dest[#dest]) - R.rank(top)        -- cards to move so the bottom one fits
            if need >= 1 and need <= run and fits(col[#col - need + 1], dest[#dest]) and need <= R.capacity(p, t) then
              out[#out + 1] = { from = 'c', fi = k, to = 'c', ti = t, n = need }
            end
          elseif t == empty_col then
            -- into an empty column: the whole run if it fits, and a single card
            local cap = R.capacity(p, t)
            local n = math.min(run, cap)
            if n < #col then out[#out + 1] = { from = 'c', fi = k, to = 'c', ti = t, n = n } end
            if n > 1 and run < #col then out[#out + 1] = { from = 'c', fi = k, to = 'c', ti = t, n = 1 } end
          end
        end
      end
      if free_slot then out[#out + 1] = { from = 'c', fi = k, to = 'f', ti = free_slot, n = 1 } end
    end
  end
  for i = 1, 4 do
    local c = p.free[i]
    if c ~= 0 then
      if R.to_home_ok(p, c) then out[#out + 1] = { from = 'f', fi = i, to = 'h', ti = R.suit(c), n = 1 } end
      for t = 1, 8 do
        local dest = p.cols[t]
        if (#dest > 0 and fits(c, dest[#dest])) or (#dest == 0 and t == empty_col) then
          out[#out + 1] = { from = 'f', fi = i, to = 'c', ti = t, n = 1 }
        end
      end
    end
  end
  return out
end

-- how far from won: cards not home, plus the cards lying on top of each suit's next card,
-- plus occupied free cells
local function score(p)
  local left = 52 - (p.home[0] + p.home[1] + p.home[2] + p.home[3])
  local cover = 0
  for k = 1, 8 do
    local col = p.cols[k]
    local need = {}
    for i = #col, 1, -1 do
      local c = col[i]
      if R.rank(c) == p.home[R.suit(c)] + 1 then cover = cover + (#col - i) end
    end
  end
  local used = 0
  for i = 1, 4 do if p.free[i] ~= 0 then used = used + 1 end end
  local empty = 0
  for k = 1, 8 do if #p.cols[k] == 0 then empty = empty + 1 end end
  return left * 3 + cover * 2 + used - empty * 2
end

-- a heap of { prio, node }
local function push(h, prio, node)
  h[#h + 1] = { prio, node }
  local i = #h
  while i > 1 do
    local j = i // 2
    if h[j][1] <= h[i][1] then break end
    h[i], h[j] = h[j], h[i]
    i = j
  end
end
local function pop(h)
  local top = h[1]
  local last = table.remove(h)
  if #h > 0 then
    h[1] = last
    local i = 1
    while true do
      local l, r, m = i * 2, i * 2 + 1, i
      if l <= #h and h[l][1] < h[m][1] then m = l end
      if r <= #h and h[r][1] < h[m][1] then m = r end
      if m == i then break end
      h[i], h[m] = h[m], h[i]
      i = m
    end
  end
  return top and top[2]
end

-- Best-first search for a win from p (after autoplay). Returns the list of moves the player
-- makes (each followed by autoplay), or nil and whether the budget ran out. `budget` limits the
-- positions expanded; `deadline` (optional) is a function returning true when time is up.
function R.solve(p, budget, deadline)
  local start = R.copy(p)
  R.autoplay(start)
  if R.won(start) then return {} end
  local seen = { [R.key(start)] = true }
  local heap, n = {}, 0
  push(heap, score(start), { enc = R.encode(start), parent = nil, move = nil, depth = 0 })
  while #heap > 0 do
    local node = pop(heap)
    n = n + 1
    if n > budget or (deadline and n % 50 == 0 and deadline()) then return nil, true end
    local q = R.decode(node.enc)
    for _k, m in ipairs(R.moves(q)) do
      local r = R.copy(q)
      R.apply(r, m)
      R.autoplay(r)
      local key = R.key(r)
      if not seen[key] then
        seen[key] = true
        local child = { enc = R.encode(r), parent = node, move = m, depth = node.depth + 1 }
        if R.won(r) then
          local path = {}
          local x = child
          while x.parent do table.insert(path, 1, x.move); x = x.parent end
          return path
        end
        push(heap, score(r) + child.depth * 0.5, child)
      end
    end
  end
  return nil, false
end

-- moves as text, for the solution banks: "c3c5x2" (column 3 to column 5, 2 cards), "c1f", "f2h", "c4h"
function R.move_str(m)
  local s = m.from .. (m.fi or '') .. m.to
  if m.to == 'c' then s = s .. m.ti end
  if m.n > 1 then s = s .. 'x' .. m.n end
  return s
end
function R.move_parse(p, s)
  local from, fi, to, ti, n = s:match('^([cf])(%d)([cfh])(%d?)x?(%d*)$')
  if not from then return nil end
  local m = { from = from, fi = tonumber(fi), to = to, n = tonumber(n) or 1 }
  if to == 'c' then m.ti = tonumber(ti)
  elseif to == 'f' then for i = 1, 4 do if p.free[i] == 0 then m.ti = i; break end end
  else
    local c = from == 'c' and p.cols[m.fi][#p.cols[m.fi]] or p.free[m.fi]
    m.ti = c and R.suit(c)
  end
  return m
end

return R
