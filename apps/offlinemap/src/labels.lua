-- Street names beside a route: which names (a GPX's street waypoints, or the street entries of the
-- packs' name index near the route), and where at a zoom (on the route, turned along it, moved to one
-- side, not too close to another).
local names = require('names')
local geo = require('geo')

local L = {}

local M7 = 0.011132                 -- metres per 1e-7 degree of latitude

-- the direction (dx, dy) in screen pixels -> degrees clockwise, turned to read left to right
function L.angle(dx, dy)
  local d = math.atan(dy, dx) * 180 / math.pi
  if d > 90 then d = d - 180 elseif d < -90 then d = d + 180 end
  return math.floor(d + 0.5)
end

-- metres from point p to the segment a-b (all {lat7, lon7}, near each other), cos = cos(latitude)
local function dist_m(p, a, b, cos)
  local ax, ay = (a.lon7 - p.lon7) * M7 * cos, (a.lat7 - p.lat7) * M7
  local bx, by = (b.lon7 - p.lon7) * M7 * cos, (b.lat7 - p.lat7) * M7
  local dx, dy = bx - ax, by - ay
  local l2 = dx * dx + dy * dy
  local t = l2 > 0 and math.max(0, math.min(1, -(ax * dx + ay * dy) / l2)) or 0
  local x, y = ax + t * dx, ay + t * dy
  return math.sqrt(x * x + y * y)
end

-- the street entries (kind 6) of the packs the route crosses, within max_m metres of it; a name once
-- per 300 m. Reads each such pack's whole name index once (when a route opens).
function L.from_index(packs, points, max_m)
  if #points < 2 then return {} end
  local w, s, e, n = points[1].lon7, points[1].lat7, points[1].lon7, points[1].lat7
  for _, p in ipairs(points) do
    if p.lon7 < w then w = p.lon7 end
    if p.lon7 > e then e = p.lon7 end
    if p.lat7 < s then s = p.lat7 end
    if p.lat7 > n then n = p.lat7 end
  end
  local cos = math.cos((s / 2 + n / 2) / 1e7 * math.pi / 180)
  local my = math.floor(max_m / M7) + 1
  local mx = math.floor(max_m / M7 / cos) + 1
  local out = {}
  for _, pk in ipairs(packs) do
    local b = pk.meta.bounds or {}
    local bw, bs, be, bn = (tonumber(b[1]) or -180) * 1e7, (tonumber(b[2]) or -90) * 1e7, (tonumber(b[3]) or 180) * 1e7, (tonumber(b[4]) or 90) * 1e7
    if not (be < w - mx or bw > e + mx or bn < s - my or bs > n + my) then
      for _, bl in ipairs(pk.dir or {}) do
        for _, en in ipairs(names.entries(pk, bl)) do
          if en.kind == 6 and en.lon7 >= w - mx and en.lon7 <= e + mx and en.lat7 >= s - my and en.lat7 <= n + my then
            local best = math.huge
            for i = 2, #points do
              local d = dist_m(en, points[i - 1], points[i], cos)
              if d < best then best = d end
            end
            if best <= max_m then
              local dup = false
              for _, o in ipairs(out) do
                if o.name == en.name and dist_m(o, en, en, cos) < 300 then dup = true; break end
              end
              if not dup then out[#out + 1] = { name = en.name, lat7 = en.lat7, lon7 = en.lon7 } end
            end
          end
        end
      end
    end
  end
  return out
end

-- labels at zoom z on the route's global pixels px {x1, y1, ...}: level boxes beside the route (the
-- reader turns no pictures): { {idx, x, y, w, h} }, x and y the box's top left in global pixels. Beside
-- a north-south piece the box is to its right; beside an east-west piece, above it. A box that would
-- overlap one already placed is left out, and so is a name already placed within SAME px. measure(name) -> width; lh: the line height.
local PAD, SIDE = 8, 12
local SAME = 700                  -- the same name at most once in this many pixels (about a screen)
function L.place(px, labels, z, measure, lh)
  local out = {}
  local n = #px // 2
  if n < 2 then return out end
  for li, lb in ipairs(labels) do
    local lx, ly = geo.lonlat_px(z, lb.lon7, lb.lat7)
    -- the nearest piece and where on it; only differences go through floats
    local best, bt, bax, bay, bdx, bdy
    for k = 1, n - 1 do
      local ax, ay = px[2 * k - 1], px[2 * k]
      local dx, dy = px[2 * k + 1] - ax, px[2 * k + 2] - ay
      local l2 = dx * dx + dy * dy
      if l2 > 0 then
        local ox, oy = lx - ax, ly - ay
        local t = math.max(0, math.min(1, (ox * dx + oy * dy) / l2))
        local d = (t * dx - ox) ^ 2 + (t * dy - oy) ^ 2
        if not best or d < best then best, bt, bax, bay, bdx, bdy = d, t, ax, ay, dx, dy end
      end
    end
    if best then
      local qx, qy = bax + math.floor(bt * bdx + 0.5), bay + math.floor(bt * bdy + 0.5)
      local w, h = measure(lb.name) + 2 * PAD, lh + 4
      local x, y
      if math.abs(bdx) >= math.abs(bdy) then x, y = qx - w // 2, qy - SIDE - h     -- above
      else x, y = qx + SIDE, qy - h // 2 end                                       -- to the right
      local clash = false
      for _, o in ipairs(out) do
        if x < o.x + o.w + 10 and o.x < x + w + 10 and y < o.y + o.h + 10 and o.y < y + h + 10 then clash = true; break end
        if labels[o.idx].name == lb.name and math.abs(o.x - x) < SAME and math.abs(o.y - y) < SAME then clash = true; break end
      end
      if not clash then out[#out + 1] = { idx = li, x = x, y = y, w = w, h = h } end
    end
  end
  return out
end

return L
