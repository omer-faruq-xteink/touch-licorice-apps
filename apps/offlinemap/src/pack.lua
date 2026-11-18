-- Reading a map pack (format v1, written by site/tools/offlinemap/pack.js) with offset reads of at
-- most 64 KB: the header, the meta, the zoom table and the name directory at open; a row's index and
-- its tiles (stored together) on demand.
local P = {}
P.__index = P

local MAX = 65536

-- len bytes at off, in reads of at most 64 KB; nil and why when a read fails
local function span(name, off, len)
  if len <= 0 then return '' end
  local parts = {}
  local done = 0
  while done < len do
    local n = math.min(MAX, len - done)
    local ok, b, e = pcall(function() return ctx.files:read(name, off + done, n) end)
    if not ok then return nil, tostring(b) end
    if type(b) ~= 'string' then return nil, tostring(e or 'no data') end
    if #b == 0 then return nil, 'the file ends at ' .. (off + done) .. ' bytes' end
    parts[#parts + 1] = b
    done = done + #b
  end
  return table.concat(parts)
end
P.span = span

local u16 = function(s, i) return string.unpack('<I2', s, i) end
local u32 = function(s, i) return string.unpack('<I4', s, i) end

-- -> the pack, or nil and a reason
function P.open(name)
  local h, he = span(name, 0, 64)
  if not h then return nil, 'cannot read it: ' .. tostring(he) end
  if #h < 64 then return nil, 'a damaged map pack: only ' .. #h .. ' bytes' end
  if h:sub(1, 8) ~= 'XTMAP1\0\0' then return nil, 'not a map pack: it starts ' .. string.format('%q', h:sub(1, 8)) end
  if u16(h, 9) ~= 1 then return nil, 'not a map pack: version ' .. u16(h, 9) end
  if h:byte(12) ~= 2 or u16(h, 13) ~= 256 then return nil, 'an unknown tile format' end
  local nlev = h:byte(11)
  local meta_off, meta_len, zoom_off = u32(h, 17), u32(h, 21), u32(h, 25)
  local names_off, names_len = u32(h, 29), u32(h, 33)
  local mj, me = span(name, meta_off, meta_len)
  if not mj then return nil, 'a damaged map pack: its details (' .. meta_len .. ' bytes at ' .. meta_off .. '): ' .. tostring(me) end
  local okj, meta = pcall(function() return ctx.json:decode(mj) end)
  if not okj or type(meta) ~= 'table' then return nil, 'a damaged map pack: its details do not read: ' .. tostring(meta) end
  local zt, ze = span(name, zoom_off, 20 * nlev)
  if not zt then return nil, 'a damaged map pack: its zoom table: ' .. tostring(ze) end
  local self = setmetatable({ name = name, meta = meta, levels = {}, zmin = 99, zmax = -1,
    near_off = u32(h, 37), near_len = u32(h, 41) }, P)   -- the nearest-name section (src/near.lua), 0 in old packs
  local deepest
  for i = 0, nlev - 1 do
    local o = 1 + 20 * i
    local z = zt:byte(o)
    local l = { z = z, x0 = u32(zt, o + 4), y0 = u32(zt, o + 8), nx = u16(zt, o + 12), ny = u16(zt, o + 14), index = u32(zt, o + 16) }
    self.levels[z] = l
    if z < self.zmin then self.zmin = z end
    if z > self.zmax then self.zmax = z; deepest = l end
  end
  -- size of the area, as tiles at zoom 19 (a float: only compared): the smallest pack is the most detailed
  self.area = deepest and deepest.nx * deepest.ny * (4.0 ^ (19 - deepest.z)) or 0
  self.made = tostring(meta.made or '')
  local oks, sz = pcall(function() return ctx.files:size(name) end)
  self.file_size = oks and tonumber(sz) or 0
  -- the name directory: { off (absolute), len, count, first }
  self.dir = {}
  if names_len > 0 then
    local d = span(name, names_off, math.min(names_len, MAX))
    if d and #d >= 4 then
      local nb = u32(d, 1)
      local p = 5
      for _ = 1, nb do
        if p + 8 > #d then break end
        local klen = d:byte(p + 8)
        self.dir[#self.dir + 1] = { off = names_off + u32(d, p), len = u16(d, p + 4), count = u16(d, p + 6), first = d:sub(p + 9, p + 8 + klen) }
        p = p + 9 + klen
      end
    end
  end
  return self
end

-- does this pack have level z, and tile (x, y) inside its range?
function P:has(z, x, y)
  local l = self.levels[z]
  return l ~= nil and x >= l.x0 and y >= l.y0 and x < l.x0 + l.nx and y < l.y0 + l.ny
end

-- tiles xa..xb of row y at level z -> { [x] = zlib bytes | false (empty paper) }; tiles outside the
-- range are left out
function P:read_row(z, y, xa, xb)
  local l = self.levels[z]
  local out = {}
  if not l or y < l.y0 or y >= l.y0 + l.ny then return out end
  xa, xb = math.max(xa, l.x0), math.min(xb, l.x0 + l.nx - 1)
  if xa > xb then return out end
  local n = xb - xa + 1
  local idx = span(self.name, l.index + 8 * ((y - l.y0) * l.nx + (xa - l.x0)), 8 * n)
  if not idx then return out end
  local first, last
  local ents = {}
  for i = 0, n - 1 do
    local off, len = u32(idx, 1 + 8 * i), u32(idx, 5 + 8 * i)
    ents[i] = { off, len }
    if len > 0 then
      if not first or off < first then first = off end
      if not last or off + len > last then last = off + len end
    end
  end
  local data = first and span(self.name, first, last - first)
  for i = 0, n - 1 do
    local off, len = ents[i][1], ents[i][2]
    if len == 0 or not data then out[xa + i] = false
    else out[xa + i] = data:sub(off - first + 1, off - first + len) end
  end
  return out
end

return P
