-- Geography on 32-bit numbers: positions are global pixels at a zoom (integers; 256 << 19 still fits),
-- degrees are integers in 1e-7 degrees, and floats (single precision on the device) only ever scale
-- small differences from an anchor, so nothing drifts at zoom 19.
local G = {}

local R = math.pi / 180

function G.tile_px(z) return 256 << z end

local function make_anchor(z, cx, cy, lon7, lat7)
  local W = G.tile_px(z)
  local lat = lat7 / 1e7
  local c = math.cos(lat * R)
  local k = W / 3600000000                     -- pixels per 1e-7 degree of longitude
  return {
    z = z, cx = cx, cy = cy, lon7 = lon7, lat7 = lat7,
    kx = k, ky = k / c,
    ky2 = k / c * math.tan(lat * R) * R * 1e-7 / 2,   -- the second-order term per (1e-7 degree)^2
  }
end

-- the view's anchor: its global pixel and its position, with the scale for differences around it
-- (second order in latitude, so a point 2 km away is still within a pixel at zoom 19). Its lon7 and
-- lat7 come from single-precision maths: fine for showing a point's coordinates, not for placing
-- things on the map (use anchor_ll for those, once per zoom).
function G.anchor(z, cx, cy)
  local W = G.tile_px(z)
  local lon = cx / W * 360 - 180
  local lat = (2 * math.atan(math.exp(math.pi * (1 - 2 * cy / W))) - math.pi / 2) / R   -- Lua has no sinh
  return make_anchor(z, cx, cy, math.floor(lon * 1e7 + 0.5), math.floor(lat * 1e7 + 0.5))
end

-- an anchor at a known position (a route's first point, a marker): its pixel from lonlat_px, so the
-- points around it land where the tiles are, and the same on every pan
function G.anchor_ll(z, lon7, lat7)
  local x, y = G.lonlat_px(z, lon7, lat7)
  return make_anchor(z, x, y, lon7, lat7)
end

-- -> global pixels (integers) of a point near the anchor. The offsets are rounded first and added as
-- integers: a float sum near 2^27 would snap to 8 px on the device.
function G.to_px(A, lon7, lat7)
  local dl = lat7 - A.lat7
  local dx = math.floor((lon7 - A.lon7) * A.kx + 0.5)
  local dy = math.floor(dl * A.ky + dl * A.ky2 * dl + 0.5)     -- dl * dl would wrap in 32 bits
  return A.cx + dx, A.cy - dy
end

-- -> lon7, lat7 of a global pixel near the anchor
function G.from_px(A, x, y)
  local lon7 = A.lon7 + math.floor((x - A.cx) / A.kx + 0.5)
  local d = (A.cy - y) / A.ky                    -- first guess, then one Newton step for the square term
  d = d - (d * A.ky + d * A.ky2 * d - (A.cy - y)) / (A.ky + 2 * d * A.ky2)
  return lon7, A.lat7 + math.floor(d + 0.5)
end

-- -> metres, pixels: the round length (1, 2 or 5 x 10^n) whose bar is nearest 90 px long
function G.scale_bar(z, lat7)
  local mpp = 156543.03392 * math.cos(lat7 / 1e7 * R) / (1 << z)
  local bm, bp
  for e = 0, 7 do
    for _, f in ipairs({ 1, 2, 5 }) do
      local m = f * 10 ^ e
      local px = m / mpp
      if not bp or math.abs(px - 90) < math.abs(bp - 90) then bm, bp = m, px end
    end
  end
  return math.floor(bm + 0.5), math.floor(bp + 0.5)
end

-- "12.345" -> 123450000 (1e-7 degrees), exactly, from the digits
local function dec7(s)
  local sign, int, frac = s:match('^%s*([%-+]?)(%d*)%.?(%d*)%s*$')
  if not sign or (int == '' and frac == '') then return nil end
  frac = (frac .. '0000000'):sub(1, 7)
  local v = (tonumber(int) or 0) * 10000000 + tonumber(frac)
  return sign == '-' and -v or v
end
G.dec7 = dec7
-- 41°0'29.5"N -> 1e-7 degrees
local function dms7(s)
  local d, m, sec, h = s:match('^%s*(%d+)%s*°%s*(%d*)%s*[\'′]?%s*([%d%.]*)%s*["″]?%s*([NSEWnsew]?)%s*$')
  if not d then return nil end
  local secm = 0
  if sec ~= '' then
    local si, sf = sec:match('^(%d*)%.?(%d*)$')
    if not si then return nil end
    secm = (tonumber(si) or 0) * 1000 + tonumber(((sf or '') .. '000'):sub(1, 3))
  end
  local v = tonumber(d) * 10000000 + ((tonumber(m) or 0) * 60000 + secm) * 25 // 9
  h = h:upper()
  return (h == 'S' or h == 'W') and -v or v, h
end

-- "41.0082, 28.9784", "41.0082 28.9784" or 41°0'29.5"N 28°58'42.2"E -> lat7, lon7 | nil, reason
function G.parse_coords(s)
  s = tostring(s or '')
  local a, b = s:match('^%s*([%-+]?[%d%.]+)%s*[,;%s]%s*([%-+]?[%d%.]+)%s*$')
  local lat, lon
  if a then
    lat, lon = dec7(a), dec7(b)
  else
    local p, q = s:match('^(.-[NSns])[%s,;]+(.-[EWew])%s*$')
    if p then lat, lon = dms7(p), dms7(q) end
  end
  if not lat or not lon then return nil, 'Type a position like 41.0082, 28.9784' end
  if lat < -900000000 or lat > 900000000 or lon < -1800000000 or lon > 1800000000 then
    return nil, 'Latitude goes to 90 and longitude to 180'
  end
  return lat, lon
end

-- global pixel of a position at zoom z (for a jump: the new view's anchor comes from here)
-- x exactly, by long division on 32-bit integers (q in 4e-7 degrees, 0 .. 9e8: 2 * q still fits);
-- y in single precision (a few pixels off at zoom 19, the same for everything placed with it)
local MAXLAT7 = 850511287
function G.lonlat_px(z, lon7, lat7)
  local D = 900000000
  local q = lon7 // 4 + 450000000
  local x, r = q // D, q % D
  for _ = 1, z + 8 do
    r = r * 2
    x = x * 2
    if r >= D then x = x + 1; r = r - D end
  end
  lat7 = math.max(-MAXLAT7, math.min(MAXLAT7, lat7))   -- the poles are outside Web Mercator
  local lat = lat7 / 1e7 * R
  local y = (1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2 * G.tile_px(z)
  return x, math.floor(y)
end

-- a decimal position for showing: 41.00820, 28.97840
function G.fmt(lat7, lon7)
  local function f(v)
    local s = v < 0 and '-' or ''
    local u = (math.abs(v) + 50) // 100            -- 1e-5 degrees, rounded
    return string.format('%s%d.%05d', s, u // 100000, u % 100000)
  end
  return f(lat7) .. ', ' .. f(lon7)
end

return G
