-- A case from a bank line (make_bank.py writes them; its docstring has the format) and its clues
-- in words.

local themes = require('themes')

local C = {}
local B36 = '0123456789abcdefghijklmnopqrstuvwxyz'
local function b36(ch) return (B36:find(ch, 1, true) or 0) - 1 end
local WORDS = { 'one', 'two', 'three', 'four', 'five' }

-- the case: theme, k groups of n; groups[g] = { key, goal, items = { labels }, short = { .. },
-- tg = the theme group (nil for the people) }, owner[g][slot] = person, slot[g][person] = slot,
-- clues = { { t = '=', e = { {g, s}, .. }, g = ordered group, d = steps } }  (all 1-based)
function C.parse(line)
  if type(line) ~= 'string' then return nil end
  line = line:gsub('%.+$', '')
  local head, cl = line:match('^([%w]+):([%w=!<+,]+)$')
  if not head then return nil end
  local th = themes[b36(head:sub(1, 1)) + 1]
  local k, n = tonumber(head:sub(2, 2)), tonumber(head:sub(3, 3))
  if not th or not k or not n or k < 2 or n < 2 then return nil end
  local p = { theme = th, k = k, n = n, groups = {}, owner = {}, slot = {}, clues = {} }
  local pos = 4
  for g = 1, k do
    local gid = tonumber(head:sub(pos, pos)); pos = pos + 1
    local tg = gid > 0 and th.groups[gid] or nil
    local pool = tg and tg.items or th.names
    local short = tg and (tg.short or tg.items) or th.names
    local G = { tg = tg, key = tg and tg.key or 'Name', goal = tg and tg.goal, items = {}, short = {} }
    for s = 1, n do
      local i = b36(head:sub(pos, pos)) + 1; pos = pos + 1
      if not pool[i] then return nil end
      G.items[s], G.short[s] = pool[i], short[i]
    end
    p.groups[g] = G
    p.owner[g], p.slot[g] = {}, {}
    for person = 1, n do
      local s = person
      if g > 1 then s = tonumber(head:sub(pos, pos)) + 1; pos = pos + 1 end
      p.slot[g][person], p.owner[g][s] = s, person
    end
  end
  for code in cl:gmatch('[^,]+') do
    local t = code:sub(1, 1)
    local counts = { ['='] = 2, ['!'] = 2, e = 3, o = 4, ['<'] = 2, ['+'] = 2 }
    local m = counts[t]
    if not m then return nil end
    local c = { t = t, e = {} }
    for i = 1, m do
      local g, s = tonumber(code:sub(2 * i, 2 * i)), tonumber(code:sub(2 * i + 1, 2 * i + 1))
      if not g or not s or g >= k or s >= n then return nil end
      c.e[i] = { g + 1, s + 1 }
    end
    if t == '<' or t == '+' then c.g = tonumber(code:sub(2 * m + 2, 2 * m + 2)) + 1 end
    if t == '+' then c.d = tonumber(code:sub(2 * m + 3, 2 * m + 3)) end
    p.clues[#p.clues + 1] = c
  end
  return p
end

-- the person an entity {g, s} belongs to
function C.who(p, e) return p.owner[e[1]][e[2]] end

local function fill(tpl, s) return (tpl:gsub('%%s', function() return s end)) end

local function np(p, e)
  local G = p.groups[e[1]]
  if not G.tg then return G.items[e[2]] end
  return fill(G.tg.np, G.items[e[2]])
end

local function pred(p, e, label)
  local G = p.groups[e[1]]
  label = label or G.items[e[2]]
  if not G.tg then return 'is ' .. label end
  return fill(G.tg.pred, label)
end

local function neg(p, e)
  local G = p.groups[e[1]]
  if not G.tg then return 'is not ' .. G.items[e[2]] end
  return fill(G.tg.neg, G.items[e[2]])
end

local function cap(s) return (s:gsub('^%l', string.upper)) end

-- a clue in words
function C.text(p, c)
  local e = c.e
  local s
  if c.t == '=' or c.t == '!' then
    local a, b = e[1], e[2]
    if b[1] == 1 then a, b = b, a end            -- the person first: "Ada lost the key"
    s = np(p, a) .. ' ' .. (c.t == '=' and pred(p, b) or neg(p, b))
  elseif c.t == 'e' then
    local a, x, y = e[1], e[2], e[3]
    if x[1] == y[1] then
      local G = p.groups[x[1]]
      if not G.tg then
        s = np(p, a) .. ' is either ' .. G.items[x[2]] .. ' or ' .. G.items[y[2]]
      else
        s = np(p, a) .. ' ' .. pred(p, x, G.items[x[2]] .. ' or ' .. G.items[y[2]])
      end
    elseif x[1] == 1 or y[1] == 1 then           -- "is either Eda or the guard who ..."
      if y[1] == 1 then x, y = y, x end
      s = np(p, a) .. ' is either ' .. np(p, x) .. ' or ' .. np(p, y)
    else
      s = np(p, a) .. ' either ' .. pred(p, x) .. ' or ' .. pred(p, y)
    end
  elseif c.t == 'o' then
    s = 'Of ' .. np(p, e[1]) .. ' and ' .. np(p, e[2]) .. ', one ' .. pred(p, e[3]) .. ' and the other ' .. pred(p, e[4])
  elseif c.t == '<' then
    s = np(p, e[1]) .. ' ' .. p.groups[c.g].tg.less .. ' ' .. np(p, e[2])
  elseif c.t == '+' then
    local tg = p.groups[c.g].tg
    local amount = (WORDS[c.d] or tostring(c.d)) .. ' ' .. (c.d == 1 and tg.unit[1] or tg.unit[2])
    s = np(p, e[1]) .. ' ' .. fill(tg.after, amount) .. ' ' .. np(p, e[2])
  end
  return cap(s) .. '.'
end

-- what the case asks: "Find each guest's floor, arrival time and lost item."
function C.goal(p)
  local t = {}
  for g = 2, p.k do t[#t + 1] = p.groups[g].goal end
  local list = #t > 1 and (table.concat(t, ', ', 1, #t - 1) .. ' and ' .. t[#t]) or t[1]
  return 'Find each ' .. p.theme.who .. '\'s ' .. list .. '.'
end

-- the grids: every pair of groups, the people's first
function C.pairs(p)
  local out = {}
  for g = 1, p.k do for h = g + 1, p.k do out[#out + 1] = { g, h } end end
  return out
end

-- is item a of group g the same person as item b of group h?
function C.same(p, g, a, h, b) return p.owner[g][a] == p.owner[h][b] end

return C
