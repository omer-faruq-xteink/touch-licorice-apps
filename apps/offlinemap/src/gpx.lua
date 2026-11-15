-- GPX routes (from a phone app, Komoot, Strava, a hiking site): track and route points read without
-- an XML library, thinned per zoom so a long track still draws fast, and measured.
local geo = require('geo')

local X = {}

-- text -> { name, points = { {lat7, lon7}, ... } } | nil, reason
function X.parse(text)
  text = tostring(text or '')
  local pts = {}
  for tag in text:gmatch('<%s*[%w:]*[rt][rt][ke]pt%s([^>]*)>') do
    local lat = tag:match('lat%s*=%s*["\']([^"\']+)["\']')
    local lon = tag:match('lon%s*=%s*["\']([^"\']+)["\']')
    local la, lo = lat and geo.dec7(lat), lon and geo.dec7(lon)
    if la and lo then pts[#pts + 1] = { lat7 = la, lon7 = lo } end
  end
  if #pts == 0 then return nil, 'no track or route points in this file' end
  -- street names to write beside the route (our tool's GPX): <wpt ...><name>..</name><type>street</type></wpt>
  local labels = {}
  for attrs, body in text:gmatch('<%s*[%w:]*wpt%s([^>]*)>(.-)</%s*[%w:]*wpt%s*>') do
    local ty = body:match('<%s*type%s*>%s*([^<]-)%s*</')
    local nm = body:match('<%s*name%s*>%s*([^<]-)%s*</')
    local lat = attrs:match('lat%s*=%s*["\']([^"\']+)')
    local lon = attrs:match('lon%s*=%s*["\']([^"\']+)')
    local la, lo = lat and geo.dec7(lat), lon and geo.dec7(lon)
    if ty == 'street' and nm and nm ~= '' and la and lo then labels[#labels + 1] = { name = X.unescape(nm), lat7 = la, lon7 = lo } end
  end
  -- the route's own name: the metadata's or the track's, not a waypoint's
  local body = text:gsub('<%s*[%w:]*wpt%s.-</%s*[%w:]*wpt%s*>', '')
  local name = body:match('<%s*name%s*>%s*([^<]-)%s*</%s*name%s*>')
  if name then name = X.unescape((name:gsub('<!%[CDATA%[(.-)%]%]>', '%1'))) end
  return { name = name ~= '' and name or nil, points = pts, labels = labels }
end

function X.unescape(s)
  return (s:gsub('&lt;', '<'):gsub('&gt;', '>'):gsub('&quot;', '"'):gsub('&#39;', "'"):gsub('&amp;', '&'))
end

-- the points at least 2 px apart at zoom z (the first and the last kept)
function X.thin(points, z)
  local step = 2 * 3600000000 / geo.tile_px(z)      -- 2 px in 1e-7 degrees (of longitude)
  local out = {}
  local last
  for i, p in ipairs(points) do
    if not last or i == #points or math.abs(p.lon7 - last.lon7) >= step or math.abs(p.lat7 - last.lat7) >= step then
      out[#out + 1] = p
      last = p
    end
  end
  return out
end

-- metres along the points (haversine, step by step)
function X.length_m(points)
  local R = math.pi / 180 / 1e7
  local m = 0
  for i = 2, #points do
    local a, b = points[i - 1], points[i]
    local p1, p2 = a.lat7 * R, b.lat7 * R
    local dp, dl = (b.lat7 - a.lat7) * R, (b.lon7 - a.lon7) * R
    local h = math.sin(dp / 2) ^ 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ^ 2
    m = m + 2 * 6371000 * math.asin(math.min(1, math.sqrt(h)))
  end
  return math.floor(m + 0.5)
end

function X.length_text(m)
  if m < 1000 then return m .. ' m' end
  local d = (m + 50) // 100
  return (d // 10) .. '.' .. (d % 10) .. ' km'
end

return X
