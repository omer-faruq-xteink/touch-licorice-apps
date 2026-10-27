-- Klondike rules. Cards as in tools/gamekit/cards.lua (1..52). A position:
--   stock, waste: cards, the top last; home[0..3]: the top rank on each foundation;
--   cols[1..7] = { cards = { ... bottom first }, down = how many of them lie face down }.
-- A move: { from = 'w' | 'c' | 'h', fi = column or suit, to = 'c' | 'h', ti = column or suit, n = cards }.

local C = require('cards')
local K = {}

-- the Park-Miller generator, computed so no step leaves 31 bits (the same deals with 32-bit or
-- 64-bit numbers)
local function lcg(seed)
  seed = 16807 * (seed % 127773) - 2836 * (seed // 127773)
  if seed <= 0 then seed = seed + 2147483647 end
  return seed
end

function K.deal(n)
  local deck = {}
  for c = 1, 52 do deck[c] = c end
  local seed = n % 2147483646 + 1
  for i = 52, 2, -1 do
    seed = lcg(seed)
    local j = seed % i + 1
    deck[i], deck[j] = deck[j], deck[i]
  end
  local p = { stock = {}, waste = {}, home = { [0] = 0, 0, 0, 0 }, cols = {} }
  local k = 1
  for col = 1, 7 do
    local cards = {}
    for _i = 1, col do cards[#cards + 1] = deck[k]; k = k + 1 end
    p.cols[col] = { cards = cards, down = col - 1 }
  end
  for i = 52, k, -1 do p.stock[#p.stock + 1] = deck[i] end
  return p
end

function K.copy(p)
  local q = { stock = {}, waste = {}, home = { [0] = p.home[0], p.home[1], p.home[2], p.home[3] }, cols = {} }
  for i, c in ipairs(p.stock) do q.stock[i] = c end
  for i, c in ipairs(p.waste) do q.waste[i] = c end
  for k = 1, 7 do
    local cards = {}
    for i, c in ipairs(p.cols[k].cards) do cards[i] = c end
    q.cols[k] = { cards = cards, down = p.cols[k].down }
  end
  return q
end

local function chars(t)
  local out = {}
  for i, c in ipairs(t) do out[i] = string.char(64 + c) end
  return table.concat(out)
end
local function unchars(s)
  local t = {}
  for i = 1, #s do t[i] = s:byte(i) - 64 end
  return t
end

-- "stock|waste|h0,h1,h2,h3|down:cards|..." for saving and undo
function K.encode(p)
  local parts = { chars(p.stock), chars(p.waste), p.home[0] .. ',' .. p.home[1] .. ',' .. p.home[2] .. ',' .. p.home[3] }
  for k = 1, 7 do parts[#parts + 1] = p.cols[k].down .. ':' .. chars(p.cols[k].cards) end
  return table.concat(parts, '|')
end
function K.decode(s)
  local parts = {}
  for part in (s .. '|'):gmatch('([^|]*)|') do parts[#parts + 1] = part end
  if #parts ~= 10 then return nil end
  local h0, h1, h2, h3 = parts[3]:match('^(%d+),(%d+),(%d+),(%d+)$')
  if not h0 then return nil end
  local p = { stock = unchars(parts[1]), waste = unchars(parts[2]),
              home = { [0] = tonumber(h0), tonumber(h1), tonumber(h2), tonumber(h3) }, cols = {} }
  for k = 1, 7 do
    local down, cards = parts[3 + k]:match('^(%d+):(.*)$')
    if not down then return nil end
    p.cols[k] = { cards = unchars(cards), down = tonumber(down) }
  end
  return p
end

function K.won(p) return p.home[0] + p.home[1] + p.home[2] + p.home[3] == 52 end

local function fits(c, onto) return C.rank(onto) == C.rank(c) + 1 and C.red(onto) ~= C.red(c) end
local function home_ok(p, c) return p.home[C.suit(c)] == C.rank(c) - 1 end
K.home_ok = home_ok

-- the cards a move takes, bottom first, or nil
local function moving(p, m)
  if m.from == 'w' then
    local c = p.waste[#p.waste]
    return c and m.n == 1 and { c } or nil
  elseif m.from == 'h' then
    local r = p.home[m.fi]
    return r > 0 and m.n == 1 and { m.fi * 13 + r } or nil
  end
  local col = p.cols[m.fi]
  local n = #col.cards
  if m.n < 1 or m.n > n - col.down then return nil end
  local out = {}
  for i = n - m.n + 1, n do out[#out + 1] = col.cards[i] end
  return out
end

function K.legal(p, m)
  local cards = moving(p, m)
  if not cards then return false end
  local c = cards[1]
  if m.to == 'h' then
    return m.n == 1 and m.from ~= 'h' and C.suit(c) == m.ti and home_ok(p, c)
  end
  if m.from == 'c' and m.fi == m.ti then return false end
  local dest = p.cols[m.ti].cards
  if #dest == 0 then return C.rank(c) == 13 end
  return fits(c, dest[#dest])
end

-- make a legal move; a column left with only face-down cards turns its top one up
function K.apply(p, m)
  local cards = moving(p, m)
  if m.from == 'w' then p.waste[#p.waste] = nil
  elseif m.from == 'h' then p.home[m.fi] = p.home[m.fi] - 1
  else
    local col = p.cols[m.fi]
    for _i = 1, m.n do col.cards[#col.cards] = nil end
    if col.down > 0 and col.down >= #col.cards then col.down = #col.cards - 1 end
  end
  if m.to == 'h' then p.home[m.ti] = C.rank(cards[1])
  else
    local dest = p.cols[m.ti].cards
    for _k, c in ipairs(cards) do dest[#dest + 1] = c end
  end
end

-- the stock onto the waste (`draw` cards), or the waste back into the stock when it is empty
function K.draw(p, draw)
  if #p.stock == 0 then
    for i = #p.waste, 1, -1 do p.stock[#p.stock + 1] = p.waste[i] end
    p.waste = {}
    return 'recycled'
  end
  for _i = 1, math.min(draw, #p.stock) do
    p.waste[#p.waste + 1] = table.remove(p.stock)
  end
  return 'drew'
end

-- nothing hidden and nothing left to draw: every card can go home in turn
function K.can_finish(p)
  if #p.stock > 0 or #p.waste > 0 then return false end
  for k = 1, 7 do if p.cols[k].down > 0 then return false end end
  return not K.won(p)
end
function K.finish(p)
  local moved = true
  while moved do
    moved = false
    for k = 1, 7 do
      local col = p.cols[k].cards
      local c = col[#col]
      if c and home_ok(p, c) then K.apply(p, { from = 'c', fi = k, to = 'h', ti = C.suit(c), n = 1 }); moved = true end
    end
  end
end

-- A useful move, in this order: a card home; a move that turns up a hidden card (or brings a
-- king to an empty column); a waste card onto a column; else 'draw' when the stock or the waste
-- has cards; nil when nothing is left.
function K.hint(p)
  local wc = p.waste[#p.waste]
  if wc and home_ok(p, wc) then return { from = 'w', n = 1, to = 'h', ti = C.suit(wc) } end
  for k = 1, 7 do
    local col = p.cols[k].cards
    local c = col[#col]
    if c and home_ok(p, c) then return { from = 'c', fi = k, n = 1, to = 'h', ti = C.suit(c) } end
  end
  for k = 1, 7 do
    local col = p.cols[k]
    local up = #col.cards - col.down
    if up > 0 and (col.down > 0 or C.rank(col.cards[col.down + 1]) ~= 13) then
      for t = 1, 7 do
        local m = { from = 'c', fi = k, n = up, to = 'c', ti = t }
        -- a king to an empty column only when it uncovers something
        if K.legal(p, m) and (col.down > 0 or #p.cols[t].cards > 0) then return m end
      end
    end
  end
  if wc then
    for t = 1, 7 do
      local m = { from = 'w', n = 1, to = 'c', ti = t }
      if K.legal(p, m) then return m end
    end
  end
  if #p.stock > 0 or #p.waste > 0 then return 'draw' end
  return nil
end

return K
