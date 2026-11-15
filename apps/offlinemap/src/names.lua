-- Search by name: each pack's name index is sorted by a folded key (src/fold.lua, the tool's rule)
-- in blocks of at most 4 KB, with a directory read at open; a prefix search costs a binary search of
-- the directory and one or two block reads per pack.
local fold = require('fold').fold
local pack = require('pack')

local N = {}

N.ZOOM = { 12, 13, 14, 14, 15, 17, 16, 15, 15, 13, 17 }   -- by kind: city .. POI
N.KIND = { 'city', 'town', 'village', 'district', 'place', 'street', 'station', 'peak', 'park', 'water', 'place' }

local function starts(s, q) return s:sub(1, #q) == q end

function N.entries(p, bl)
  local out = {}
  local b = pack.span(p.name, bl.off, bl.len)
  if not b then return out end
  local i = 1
  for _ = 1, bl.count do
    local kl = b:byte(i); if not kl then break end
    local key = b:sub(i + 1, i + kl); i = i + 1 + kl
    local nl = b:byte(i)
    local name = b:sub(i + 1, i + nl); i = i + 1 + nl
    local kind = b:byte(i); i = i + 1
    local lon7, lat7 = string.unpack('<i4i4', b, i); i = i + 8
    out[#out + 1] = { key = key, name = name, kind = kind, lon7 = lon7, lat7 = lat7, pack = p }
  end
  return out
end

-- the matches of the folded prefix q in one pack
local function in_pack(p, q, limit, out)
  local dir = p.dir
  if not dir or #dir == 0 then return end
  local lo, hi, at = 1, #dir, 1
  while lo <= hi do                                -- the last block whose first key is < q: a run of
    local m = (lo + hi) // 2                       -- keys equal to q may start in it
    if dir[m].first < q then at = m; lo = m + 1 else hi = m - 1 end
  end
  local n = 0
  for b = at, #dir do                              -- on while blocks can still hold matches
    if b > at and not starts(dir[b].first, q) then break end
    for _, e in ipairs(N.entries(p, dir[b])) do
      if starts(e.key, q) then out[#out + 1] = e; n = n + 1; if n >= limit then return end end
    end
  end
end

-- -> matches from every pack, sorted by name; the same place in two packs once
function N.search(packs, query, limit)
  limit = limit or 30
  local q = fold(query)
  local all = {}
  if q == '' then return all end
  for _, p in ipairs(packs) do in_pack(p, q, limit, all) end
  table.sort(all, function(a, b) if a.key ~= b.key then return a.key < b.key end return a.pack.area < b.pack.area end)
  local out = {}
  for _, e in ipairs(all) do
    local dup = false
    for _, o in ipairs(out) do
      if o.name == e.name and o.kind == e.kind and math.abs(o.lon7 - e.lon7) < 30000 and math.abs(o.lat7 - e.lat7) < 30000 then dup = true; break end
    end
    if not dup then out[#out + 1] = e end
    if #out >= limit then break end
  end
  return out
end

return N
