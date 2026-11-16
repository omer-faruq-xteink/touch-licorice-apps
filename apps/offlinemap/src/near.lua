-- The name of what is held on the map, for the long press box: a street whose thin line is hard to
-- hold exactly, a peak, a lake. A pack's nearest-name section (site/tools/offlinemap/near.js) holds
-- its named lines (streets, paths, rivers), points (places, stations, peaks) and areas (lakes, parks)
-- in buckets of one tile at zoom zb, as pixels at zoom zb + 5 from the bucket's corner, each with the
-- zoom the map first draws it at: only what the map shows at the view's zoom is named.
--   nearest: a point under the finger (HIT px) if any, else, where the map draws streets, the nearest
--            line, else the nearest point, up to MAX_PX away on the screen. Rings of buckets are read
--            outwards until nothing unread can be nearer. Only the packs that hold the point are asked:
--            a pack without the section (an old one) is not filled in from another pack's names.
--   area:    the area the point is inside.
local pack = require('pack')
local geo = require('geo')

local M = {}

local UNIT = 8192
local MAX_READS = 60            -- bucket reads a long press may make (an empty corner of a big pack)
M.HIT = 32                      -- pixels: a point (a peak, a station, a place label) this near is the one held
M.LINES_FROM = 12               -- the zoom from which the map draws streets
M.MAX_PX = 240                  -- pixels at the view's zoom: anything farther is not near (half the screen's width)

local u16 = function(s, i) return (string.unpack('<I2', s, i)) end
local u32 = function(s, i) return (string.unpack('<I4', s, i)) end

-- the section's head, read once a pack; false when the pack has none (made before 2026-11-16)
local function head(p)
  if p.near ~= nil then return p.near end
  p.near = false
  if (p.near_len or 0) > 16 then
    local h = pack.span(p.name, p.near_off, 16)
    if h and #h == 16 then
      p.near = { zb = h:byte(1), x0 = u32(h, 5), y0 = u32(h, 9), nx = u16(h, 13), ny = u16(h, 15), rows = {} }
    end
  end
  return p.near
end

-- the bytes of bucket (bx, by), or nil when it is empty or outside; a row of the index is read once
local function bucket(p, h, bx, by)
  if bx < h.x0 or by < h.y0 or bx >= h.x0 + h.nx or by >= h.y0 + h.ny then return nil end
  local row = h.rows[by]
  if row == nil then
    row = pack.span(p.name, p.near_off + 16 + 8 * (by - h.y0) * h.nx, 8 * h.nx) or false
    h.rows[by] = row
  end
  if not row then return nil end
  local i = 1 + 8 * (bx - h.x0)
  local off, len = u32(row, i), u32(row, i + 4)
  if len == 0 then return nil end
  return pack.span(p.name, p.near_off + off, len)
end

-- each record of bucket b drawn at z: fn(shape, kind, name, p0 (the first point's index in b), n)
local function records(b, z, fn)
  local i, n = 1, #b
  while i + 5 <= n do
    local kind, from, shape, nl = b:byte(i, i + 3)
    local np = u16(b, i + 4 + nl)
    local p0 = i + 6 + nl
    if z >= from and np > 0 then fn(shape, kind, b:sub(i + 4, i + 3 + nl), p0, np) end
    i = p0 + 4 * np
  end
end

-- the records of bucket b drawn at z, measured from (qx, qy) (units from the bucket's corner): the
-- nearest line in near.line, the nearest point in near.point, as { d (squared units), name, kind }
local function scan(b, qx, qy, z, near)
  records(b, z, function(shape, kind, name, p0, np)
    if shape == 2 then return end
    local ax, ay = string.unpack('<i2i2', b, p0)
    local d = (ax - qx) ^ 2 + (ay - qy) ^ 2
    for k = 1, np - 1 do
      local bx, by = string.unpack('<i2i2', b, p0 + 4 * k)
      local dx, dy = bx - ax, by - ay
      local l2 = dx * dx + dy * dy
      if l2 > 0 then
        local t = math.max(0, math.min(1, ((qx - ax) * dx + (qy - ay) * dy) / l2))
        local e = (ax + t * dx - qx) ^ 2 + (ay + t * dy - qy) ^ 2
        if e < d then d = e end
      end
      ax, ay = bx, by
    end
    local best = shape == 1 and near.line or near.point
    if not best.d or d < best.d then best.d, best.name, best.kind = d, name, kind end
  end)
end

-- the packs with the section that hold the point, with the point in each one's units
local function places(packs, lon7, lat7)
  local todo = {}
  for _, pk in ipairs(packs) do
    local h = head(pk)
    local zz = h and h.zb + 5
    local x, y = 0, 0
    if h then x, y = geo.lonlat_px(zz, lon7, lat7) end
    local cx, cy = x // UNIT, y // UNIT
    if h and cx >= h.x0 and cy >= h.y0 and cx < h.x0 + h.nx and cy < h.y0 + h.ny then
      local x1, y1 = h.x0 + h.nx - 1, h.y0 + h.ny - 1
      todo[#todo + 1] = {
        p = pk, h = h, x = x, y = y, cx = cx, cy = cy, zz = zz,
        mpu = 40075016.686 * math.cos(lat7 / 1e7 * math.pi / 180) / (256 << zz),   -- metres a unit
        edge = math.min(x - cx * UNIT, (cx + 1) * UNIT - x, y - cy * UNIT, (cy + 1) * UNIT - y),
        r1 = math.max(cx - h.x0, x1 - cx, cy - h.y0, y1 - cy),                     -- the last ring in the grid
      }
    end
  end
  return todo
end

-- -> { name, kind, m (metres) } of what is held at zoom z, or nil
function M.nearest(packs, lon7, lat7, z)
  pcall(function() ctx.budget:extend() end)
  local lines = z >= M.LINES_FROM
  local line, point, reads = nil, nil, 0
  for _, t in ipairs(places(packs, lon7, lat7)) do
    local h, found = t.h, { line = {}, point = {} }
    local hit_u = M.HIT * (2.0 ^ (t.zz - z))       -- HIT pixels at z, in units
    local max_u = M.MAX_PX * (2.0 ^ (t.zz - z))    -- MAX_PX pixels at z
    for r = 0, t.r1 do
      -- what lies only in ring r or beyond is at least this far
      local least = r > 0 and t.edge + (r - 1) * UNIT or 0
      local want = lines and found.line.d or found.point.d
      if want and want <= least * least and least >= hit_u then break end
      local sofar = lines and line or point
      if sofar and least * t.mpu >= sofar.m and least >= hit_u then break end
      if reads >= MAX_READS or least > max_u then break end
      for by = math.max(h.y0, t.cy - r), math.min(h.y0 + h.ny - 1, t.cy + r) do
        local all = by == t.cy - r or by == t.cy + r
        local bx = math.max(h.x0, t.cx - r)
        local last = math.min(h.x0 + h.nx - 1, t.cx + r)
        while bx <= last do
          if all or bx == t.cx - r or bx == t.cx + r then
            local b = bucket(t.p, h, bx, by)
            if b then
              reads = reads + 1
              scan(b, t.x - bx * UNIT, t.y - by * UNIT, z, found)
            end
          end
          if all or bx == t.cx + r then bx = bx + 1 else bx = math.max(bx + 1, t.cx + r) end
        end
      end
    end
    local function keep(f, cur)
      if not f.d or f.d > max_u * max_u then return cur end
      local m = math.sqrt(f.d) * t.mpu
      if not cur or m < cur.m then return { name = f.name, kind = f.kind, m = m, hit = math.sqrt(f.d) <= hit_u } end
      return cur
    end
    line, point = keep(found.line, line), keep(found.point, point)
  end
  if point and point.hit then return point end
  if lines and line then return line end
  return point or line
end

-- -> the name of the area (a lake, a park) the point is inside at zoom z, or nil; the smallest one
function M.area(packs, lon7, lat7, z)
  local best, size
  for _, t in ipairs(places(packs, lon7, lat7)) do
    local b = bucket(t.p, t.h, t.cx, t.cy)
    if b then
      local qx, qy = t.x - t.cx * UNIT, t.y - t.cy * UNIT
      records(b, z, function(shape, _kind, name, p0, np)
        if shape ~= 2 or np < 3 then return end
        local inside, x0, y0, x1, y1 = false, math.huge, math.huge, -math.huge, -math.huge
        local jx, jy = string.unpack('<i2i2', b, p0 + 4 * (np - 1))
        for k = 0, np - 1 do
          local ix, iy = string.unpack('<i2i2', b, p0 + 4 * k)
          if (iy > qy) ~= (jy > qy) and qx < (jx - ix) * (qy - iy) / (jy - iy) + ix then inside = not inside end
          if ix < x0 then x0 = ix end
          if ix > x1 then x1 = ix end
          if iy < y0 then y0 = iy end
          if iy > y1 then y1 = iy end
          jx, jy = ix, iy
        end
        local s = (x1 - x0) * (y1 - y0) * t.mpu * t.mpu
        if inside and (not size or s < size) then best, size = name, s end
      end)
    end
  end
  return best
end

local function dist(m)
  return m < 1000 and string.format('%d m', math.floor(m + 0.5))
    or m < 10000 and string.format('%.1f km', m / 1000)
    or string.format('%d km', math.floor(m / 1000 + 0.5))
end

-- the box's line: Nearest: Moda Caddesi, 40 m
function M.text(r) return 'Nearest: ' .. r.name .. ', ' .. dist(r.m) end

-- the box's lines for a point at zoom z: In: <area>, Nearest: <name>, <distance>. Inside an area,
-- a nearest name farther than AREA_NEAR pixels is left out: the area is what was held.
M.AREA_NEAR = 3 * M.HIT
function M.lines(packs, lon7, lat7, z)
  local out = {}
  local ok, a = pcall(M.area, packs, lon7, lat7, z)
  if ok and a then out[#out + 1] = 'In: ' .. a end
  local ok2, r = pcall(M.nearest, packs, lon7, lat7, z)
  if ok2 and r then
    local mpp = 156543.03392 * math.cos(lat7 / 1e7 * math.pi / 180) / (1 << z)   -- metres a pixel at z
    if not (ok and a) or r.m <= M.AREA_NEAR * mpp then out[#out + 1] = M.text(r) end
  end
  return out
end

return M
