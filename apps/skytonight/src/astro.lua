-- Sky Tonight: the astronomy, shared by the app and the lock screen (bundle.py puts it first).
-- Time is s, whole seconds since J2000.0 (2000-01-01 12:00 UTC): an integer that fits the
-- reader's 32-bit integers until 2068. The reader's floats are single precision (about 7 digits),
-- so the slow motions (sun, moon, planets) use t = s in days, about 10^4 and good to a minute or
-- two, while the sidereal time, a turn a day, splits s into whole days and seconds of the day.
-- Angles in degrees unless a name says rad. Accuracy: the sun about 0.01 degrees, the moon about
-- 0.3, the planets (JPL's approximate elements, 1800-2050) a few arcminutes: plenty for a chart
-- and rise and set times to a minute or two.

local A = {}
local rad, deg = math.pi / 180, 180 / math.pi
local sin, cos, tan, asin, acos, atan, sqrt, floor = math.sin, math.cos, math.tan, math.asin, math.acos, math.atan, math.sqrt, math.floor

local function rev(x) return x - floor(x / 360) * 360 end
local function dsin(x) return sin(x * rad) end
local function dcos(x) return cos(x * rad) end
local function atan2d(y, x) return atan(y, x) * deg end
A.rev = rev

A.J2000 = 946728000                              -- 2000-01-01 12:00:00 UTC in epoch seconds

-- seconds since J2000 from the clock's epoch seconds
function A.secs(epoch_sec) return epoch_sec - A.J2000 end

-- days since J2000 (whole days first, then the rest: a float keeps both)
local function days(s)
  local d = s // 86400
  return d + (s - d * 86400) / 86400
end
A.days = days

-- Greenwich mean sidereal time, degrees: whole days times the daily drift, plus the seconds of
-- the day at the sidereal rate (no big product to lose digits in)
function A.gmst(s)
  local d = s // 86400
  return rev(280.46061837 + 0.98564736629 * d + 360.98564736629 * ((s - d * 86400) / 86400))
end

local function obliquity(t) return 23.439 - 0.0000004 * t end

-- ecliptic (lon, lat) -> equatorial (ra, dec)
function A.ecl_to_equ(lon, lat, t)
  local e = obliquity(t)
  local ra = atan2d(dsin(lon) * dcos(e) - tan(lat * rad) * dsin(e), dcos(lon))
  local dec = asin(dsin(lat) * dcos(e) + dcos(lat) * dsin(e) * dsin(lon)) * deg
  return rev(ra), dec
end

-- equatorial -> horizontal: altitude, azimuth (0 north, 90 east), for the local sidereal time
function A.horizon(ra, dec, lst, lat)
  local h = (lst - ra) * rad
  local d, p = dec * rad, lat * rad
  local salt = sin(d) * sin(p) + cos(d) * cos(p) * cos(h)
  if salt > 1 then salt = 1 elseif salt < -1 then salt = -1 end
  local alt = asin(salt)
  local az = atan(-cos(d) * sin(h), sin(d) * cos(p) - cos(d) * sin(p) * cos(h))
  return alt * deg, rev(az * deg)
end

-- the sun: ecliptic longitude, ra, dec
function A.sun(s)
  local t = days(s)
  local L = rev(280.460 + 0.9856474 * t)
  local g = rev(357.528 + 0.9856003 * t)
  local lon = rev(L + 1.915 * dsin(g) + 0.020 * dsin(2 * g))
  local ra, dec = A.ecl_to_equ(lon, 0, t)
  return lon, ra, dec
end

-- the moon (the Astronomical Almanac's low-precision series): ecliptic lon, lat, ra, dec,
-- horizontal parallax
function A.moon(s)
  local t = days(s)
  local lon = 218.32 + 13.176396 * t + 6.29 * dsin(134.9 + 13.064993 * t) - 1.27 * dsin(259.2 - 11.316505 * t)
    + 0.66 * dsin(235.7 + 24.381499 * t) + 0.21 * dsin(269.9 + 26.129987 * t) - 0.19 * dsin(357.5 + 0.985600 * t)
    - 0.11 * dsin(186.6 + 26.458700 * t)
  local lat = 5.13 * dsin(93.3 + 13.229350 * t) + 0.28 * dsin(228.2 + 26.294343 * t) - 0.28 * dsin(318.3 + 0.164357 * t)
    - 0.17 * dsin(217.6 - 11.152148 * t)
  local par = 0.9508 + 0.0518 * dcos(134.9 + 13.064993 * t) + 0.0095 * dcos(259.2 - 11.316505 * t)
    + 0.0078 * dcos(235.7 + 24.381499 * t) + 0.0028 * dcos(269.9 + 26.129987 * t)
  lon = rev(lon)
  local ra, dec = A.ecl_to_equ(lon, lat, t)
  return lon, lat, ra, dec, par
end

-- the moon's phase: fraction lit 0..1, waxing?, age in days (0 new .. 29.5)
function A.phase(s)
  local slon = A.sun(s)
  local mlon, mlat = A.moon(s)
  local e = rev(mlon - slon)
  local cospsi = dcos(mlat) * dcos(e)
  return (1 - cospsi) / 2, e < 180, e / 360 * 29.530589
end

-- planets: JPL's approximate Keplerian elements (Standish), J2000 ecliptic, valid 1800-2050:
-- a, e, I, L, perihelion longitude, node, and their rates per Julian century
local ELEM = {
  mercury = { 0.38709927, 0.00000037, 0.20563593, 0.00001906, 7.00497902, -0.00594749, 252.25032350, 149472.67411175, 77.45779628, 0.16047689, 48.33076593, -0.12534081 },
  venus = { 0.72333566, 0.00000390, 0.00677672, -0.00004107, 3.39467605, -0.00078890, 181.97909950, 58517.81538729, 131.60246718, 0.00268329, 76.67984255, -0.27769418 },
  earth = { 1.00000261, 0.00000562, 0.01671123, -0.00004392, -0.00001531, -0.01294668, 100.46457166, 35999.37244981, 102.93768193, 0.32327364, 0, 0 },
  mars = { 1.52371034, 0.00001847, 0.09339410, 0.00007882, 1.84969142, -0.00813131, -4.55343205, 19140.30268499, -23.94362959, 0.44441088, 49.55953891, -0.29257343 },
  jupiter = { 5.20288700, -0.00011607, 0.04838624, -0.00013253, 1.30439695, -0.00183714, 34.39644051, 3034.74612775, 14.72847983, 0.21252668, 100.47390909, 0.20469106 },
  saturn = { 9.53667594, -0.00125060, 0.05386179, -0.00050991, 2.48599187, 0.00193609, 49.95424423, 1222.49362201, 92.59887831, -0.41897216, 113.66242448, -0.28867794 },
}
A.PLANETS = { 'mercury', 'venus', 'mars', 'jupiter', 'saturn' }

-- heliocentric ecliptic x, y, z (AU)
local function helio(name, t)
  local el, T = ELEM[name], t / 36525
  local a, e, I = el[1] + el[2] * T, el[3] + el[4] * T, el[5] + el[6] * T
  local L, wbar, node = el[7] + el[8] * T, el[9] + el[10] * T, el[11] + el[12] * T
  local M = rev(L - wbar)
  if M > 180 then M = M - 360 end
  local Mr = M * rad
  local E = Mr + e * sin(Mr)
  for _ = 1, 6 do E = E - (E - e * sin(E) - Mr) / (1 - e * cos(E)) end
  local xp, yp = a * (cos(E) - e), a * sqrt(1 - e * e) * sin(E)
  local w = (wbar - node) * rad
  local O, i = node * rad, I * rad
  local cw, sw, cO, sO, ci, si = cos(w), sin(w), cos(O), sin(O), cos(i), sin(i)
  local x = (cw * cO - sw * sO * ci) * xp + (-sw * cO - cw * sO * ci) * yp
  local y = (cw * sO + sw * cO * ci) * xp + (-sw * sO + cw * cO * ci) * yp
  local z = (sw * si) * xp + (cw * si) * yp
  return x, y, z
end

-- a planet seen from the earth: ecliptic lon, lat, ra, dec, distance (AU)
function A.planet(name, s)
  local t = days(s)
  local x, y, z = helio(name, t)
  local ex, ey, ez = helio('earth', t)
  local dx, dy, dz = x - ex, y - ey, z - ez
  local lon = rev(atan2d(dy, dx))
  local lat = atan2d(dz, sqrt(dx * dx + dy * dy))
  local ra, dec = A.ecl_to_equ(lon, lat, t)
  return lon, lat, ra, dec, sqrt(dx * dx + dy * dy + dz * dz)
end

-- angle between a planet and the sun, degrees (0..180)
function A.elongation(name, s)
  local plon, plat = A.planet(name, s)
  local slon = A.sun(s)
  return acos(dcos(plat) * dcos(plon - slon)) * deg
end

------------------------------------------------------------------ rise and set

-- altitude of a body at s: kind 'sun' or 'moon' (the moon's from the observer, parallax off)
local function body_alt(kind, s, lat, lon)
  local lst = A.gmst(s) + lon
  if kind == 'sun' then
    local _, ra, dec = A.sun(s)
    return (A.horizon(ra, dec, lst, lat))
  end
  local _, _, ra, dec, par = A.moon(s)
  local alt = A.horizon(ra, dec, lst, lat)
  return alt - par * dcos(alt)
end

-- the times (s) the body crosses altitude h0 in [s0, s0 + hours): a list of { s, true when
-- rising }. Half-hour steps, then two secant steps inside each step that changes sign (well
-- under a minute off; the half-hour scan keeps the lock screen inside its two seconds).
function A.events(kind, s0, lat, lon, h0, hours)
  local out = {}
  local function f(s) return body_alt(kind, s, lat, lon) - h0 end
  local prev = f(s0)
  for k = 1, (hours or 24) * 2 do
    local a, b = s0 + (k - 1) * 1800, s0 + k * 1800
    local fa, fb = prev, f(b)
    prev = fb
    if (fa < 0) ~= (fb < 0) then
      local rising = fa < 0
      for _ = 1, 2 do
        local m = a + floor((b - a) * fa / (fa - fb) + 0.5)
        if m <= a or m >= b then break end
        local fm = f(m)
        if (fm < 0) == (fa < 0) then a, fa = m, fm else b, fb = m, fm end
      end
      out[#out + 1] = { a + floor((b - a) * fa / (fa - fb) + 0.5), rising }
    end
  end
  return out
end

-- the first rise and the first set in [s0, s0 + 1 day); nil when it does not
function A.crossings(kind, s0, lat, lon, h0)
  local rise, set = nil, nil
  for _, e in ipairs(A.events(kind, s0, lat, lon, h0, 24)) do
    if e[2] and not rise then rise = e[1] elseif not e[2] and not set then set = e[1] end
  end
  return rise, set
end
A.body_alt = body_alt

if rawget(_G, '__TEST') then __TEST.A = A end
