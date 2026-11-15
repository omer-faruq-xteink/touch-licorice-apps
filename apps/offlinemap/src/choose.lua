-- Which pack draws a tile: of the packs that have that level at that place, the smallest area wins
-- (the most detailed), then the newest. And whether the view can zoom in or out at its centre.
local C = {}

function C.pick(packs, z, x, y)
  local best
  for _, p in ipairs(packs) do
    if p:has(z, x, y) then
      if not best or p.area < best.area or (p.area == best.area and p.made > best.made) then best = p end
    end
  end
  return best
end

-- centre (cx, cy) in global pixels at z -> can_in, can_out
function C.limits(packs, z, cx, cy)
  local can_in, can_out = false, false
  for _, p in ipairs(packs) do
    if z < 19 and p:has(z + 1, (cx * 2) >> 8, (cy * 2) >> 8) then can_in = true end
    if z > 8 and p:has(z - 1, (cx // 2) >> 8, (cy // 2) >> 8) then can_out = true end
  end
  return can_in, can_out
end

-- the zoom levels some pack has at this centre (for a jump to the nearest available level)
function C.nearest(packs, want, lon_px_at)
  local best, bd
  for z = 8, 19 do
    local x, y = lon_px_at(z)
    for _, p in ipairs(packs) do
      if p:has(z, x >> 8, y >> 8) then
        local d = math.abs(z - want)
        if not bd or d < bd or (d == bd and z > best) then best, bd = z, d end
      end
    end
  end
  return best
end

return C
