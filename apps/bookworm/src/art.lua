-- The brood's pictures, drawn from circles, arcs and lines (no image files): an egg for each kind,
-- the creature at each stage (bigger as it grows; round glasses once grown; an elder's hat), its
-- face by mood, the book it sits on, a book it hides in, and its sleeping pose. The kinds:
--   worm    the bookworm: a row of segments, antennae, a scholar's cap when elder
--   ink     the ink octopus: a tall dome with ink spots, arms curling out below, a beret when elder
--   dragon  the shelf dragon: a body, folded wing, tail with a spade, horns and snout, a crown
-- Every function takes the canvas and where to draw; they serve the app and the sleep screen.

local A = {}

local WHITE = { fill = true, color = 0 }
local BLACK = { fill = true }

-- the size of each stage: the worm's segments (how many, their radius), the others' head radius
A.BODY = { hatchling = { 3, 13 }, young = { 4, 17 }, grown = { 5, 20 }, elder = { 6, 22 } }
A.INK = { hatchling = 24, young = 29, grown = 34, elder = 38 }
A.DRAGON = { hatchling = 16, young = 20, grown = 24, elder = 27 }

local function ring(gg, x, y, r, w) gg:circle(x, y, r, WHITE); gg:circle(x, y, r, { line_width = w or 3 }) end
local function shape(gg, pts, w) gg:polygon(pts, WHITE); gg:polygon(pts, { line_width = w or 3 }) end

-- the face on a head of radius r at (x, y): eyes, and a mouth by mood
local function face(gg, x, y, r, mood, glasses)
  local ex, ey, er = r * 4 // 10, y - r // 6, math.max(3, r // 5)
  if mood == 'asleep' then
    gg:arc(x - ex, ey, er, 20, 160, { line_width = 2 }); gg:arc(x + ex, ey, er, 20, 160, { line_width = 2 })
  else
    for _, s in ipairs({ -1, 1 }) do
      gg:circle(x + s * ex, ey, er + 2, WHITE); gg:circle(x + s * ex, ey, er + 2, { line_width = 2 })
      local look = (mood == 'sulky') and -2 or 1
      gg:circle(x + s * ex + look, ey + 1, math.max(2, er - 1), BLACK)
    end
  end
  if glasses then
    for _, s in ipairs({ -1, 1 }) do gg:circle(x + s * ex, ey, er + 5, { line_width = 2 }) end
    gg:line(x - ex + er + 5, ey, x + ex - er - 5, ey)
  end
  local my = y + r * 45 // 100
  if mood == 'full' or mood == 'pet' then gg:arc(x, my - r // 5, r // 3, 25, 155, { line_width = 3 })
  elseif mood == 'peckish' then gg:line(x - r // 5, my, x + r // 5, my)
  elseif mood == 'hungry' then gg:circle(x, my, math.max(3, r // 6), { line_width = 2 })
  elseif mood == 'sulky' then gg:arc(x, my + r // 4, r // 4, 205, 335, { line_width = 3 })
  elseif mood == 'asleep' then gg:circle(x + r // 6, my, 2, BLACK) end
end

-- what its taste makes it wear or carry, on a head of radius hr at (hx, hy); returns true for a
-- hat (no elder's hat then)
local function accessory(gg, taste, hx, hy, hr, side)
  local sx = hx + (side or 0)                        -- what it carries goes beside sx
  local top = hy - hr
  if taste == 'fantasy' then                         -- a wizard's hat with a star
    shape(gg, { hx - hr - 4, top + 6, hx + 6, top - 46, hx + hr + 4, top + 6 })
    gg:polygon({ hx - 2, top - 14, hx + 2, top - 22, hx + 6, top - 14, hx + 2, top - 8 }, BLACK)
    return true
  elseif taste == 'classic' then                     -- a top hat
    gg:rect(hx - hr + 4, top - 30, 2 * hr - 8, 30, BLACK)
    gg:rect(hx - hr - 6, top - 2, 2 * hr + 12, 6, BLACK)
    gg:rect(hx - hr + 4, top - 10, 2 * hr - 8, 4, WHITE)
    return true
  elseif taste == 'scifi' then                       -- a space helmet round the head
    gg:circle(hx, hy, hr + 9, { line_width = 2 })
    gg:arc(hx, hy, hr + 4, 200, 250, { line_width = 2 })
  elseif taste == 'mystery' then                     -- a magnifying glass
    local cx, cy = sx + hr + 22, hy + 4
    gg:circle(cx, cy, 13, WHITE); gg:circle(cx, cy, 13, { line_width = 3 })
    gg:polygon({ cx - 6, cy + 11, cx - 2, cy + 13, cx - 10, cy + 30, cx - 15, cy + 28 }, BLACK)
  elseif taste == 'horror' then                      -- a candle, its flame shaking
    local cx, cy = sx + hr + 22, hy + 6
    gg:rect(cx - 6, cy - 4, 12, 26, WHITE); gg:rect(cx - 6, cy - 4, 12, 26, { line_width = 2 })
    gg:polygon({ cx, cy - 24, cx + 6, cy - 10, cx, cy - 5, cx - 6, cy - 10 }, BLACK)
    gg:rect(cx - 12, cy + 22, 24, 4, BLACK)
  elseif taste == 'romance' then                     -- a heart floating up
    local cx, cy = sx + hr + 18, top - 4
    gg:circle(cx - 6, cy, 7, BLACK); gg:circle(cx + 6, cy, 7, BLACK)
    gg:polygon({ cx - 13, cy + 2, cx + 13, cy + 2, cx, cy + 17 }, BLACK)
  elseif taste == 'adventure' then                   -- an eyepatch
    local ex, ey = hx + hr * 4 // 10, hy - hr // 6
    gg:line(hx - hr + 4, ey - hr // 2, hx + hr - 2, ey + 2)
    gg:circle(ex, ey, hr // 5 + 4, BLACK)
  elseif taste == 'nonfiction' then                  -- a quill
    local cx, cy = sx + hr + 16, hy - 6
    shape(gg, { cx, cy + 28, cx + 4, cy + 22, cx + 16, cy - 18, cx + 8, cy - 22 }, 2)
    gg:line(cx + 2, cy + 25, cx + 12, cy - 20)
  end
  return false
end

-- a small storm cloud over a sulking head
local function storm(gg, hx, top)
  local cx, cy = hx - 40, top - 26
  for _, c in ipairs({ { -12, 2, 9 }, { 0, -4, 11 }, { 13, 2, 9 } }) do gg:circle(cx + c[1], cy + c[2], c[3], WHITE) end
  for _, c in ipairs({ { -12, 2, 9 }, { 0, -4, 11 }, { 13, 2, 9 } }) do gg:circle(cx + c[1], cy + c[2], c[3], { line_width = 2 }) end
  gg:rect(cx - 18, cy + 2, 38, 8, WHITE)
  gg:polygon({ cx - 2, cy + 10, cx + 4, cy + 10, cx, cy + 18, cx + 6, cy + 18, cx - 4, cy + 30, cx - 1, cy + 20, cx - 6, cy + 20 }, BLACK)
end

-- the bottom half of a shell (a hatchling's) at (tx, ty): a round cup, a jagged rim, two speckles
local function shell(gg, tx, ty, w, d)
  local pts = {}
  for i = 0, 12 do                                          -- the round bottom, right to left
    local a = i * math.pi / 12
    pts[#pts + 1] = tx + math.floor(math.cos(a) * w); pts[#pts + 1] = ty + math.floor(math.sin(a) * d)
  end
  for i = 1, 5 do                                           -- the broken rim, left to right
    pts[#pts + 1] = tx - w + i * 2 * w // 6; pts[#pts + 1] = ty - (i % 2 == 1 and 5 or 0)
  end
  shape(gg, pts)
  gg:circle(tx - 9, ty + 9, 3, BLACK); gg:circle(tx + 10, ty + 13, 2, BLACK)
end

------------------------------------------------------------------ the bookworm

local function worm(gg, stage, hx, hy, mood, phase, taste)
  local b = A.BODY[stage] or A.BODY.young
  local n, r = b[1], b[2]
  local pts = {}
  for i = n, 1, -1 do
    local x = hx - (i * r * 17) // 10
    local y = hy + r // 3 + math.floor(math.sin((i + phase) * 1.1) * r * 0.35)
    pts[#pts + 1] = { x, y, r - (i - 1) * r // (n * 2) }
  end
  -- little legs under the body
  for _, p in ipairs(pts) do
    gg:line(p[1] - 5, p[2] + p[3] - 2, p[1] - 8, p[2] + p[3] + 6)
    gg:line(p[1] + 5, p[2] + p[3] - 2, p[1] + 8, p[2] + p[3] + 6)
  end
  for k, p in ipairs(pts) do
    ring(gg, p[1], p[2], p[3])
    if k % 2 == 0 then gg:arc(p[1], p[2], p[3] - 6, 200, 340, { line_width = 2 }) end     -- a stripe
  end
  local hr = r * 13 // 10
  -- antennae
  gg:line(hx - hr // 3, hy - hr + 4, hx - hr // 2, hy - hr - 12); gg:circle(hx - hr // 2, hy - hr - 14, 3, BLACK)
  gg:line(hx + hr // 3, hy - hr + 4, hx + hr // 2, hy - hr - 12); gg:circle(hx + hr // 2, hy - hr - 14, 3, BLACK)
  ring(gg, hx, hy, hr, 3)
  face(gg, hx, hy, hr, mood, stage == 'grown' or stage == 'elder')
  local hat = stage ~= 'hatchling' and taste and accessory(gg, taste, hx, hy, hr)
  if mood == 'sulky' then storm(gg, hx, hy - hr) end
  if stage == 'elder' and not hat then
    -- a scholar's cap: a flat board and a tassel
    local top = hy - hr - 2
    gg:polygon({ hx - hr - 6, top - 8, hx, top - 18, hx + hr + 6, top - 8, hx, top + 2 }, BLACK)
    gg:rect(hx - hr // 2, top - 6, hr, 10, BLACK)
    gg:line(hx + hr + 4, top - 8, hx + hr + 6, top + 14); gg:circle(hx + hr + 6, top + 16, 3, BLACK)
  end
  if stage == 'hatchling' then shell(gg, pts[1][1], hy + 10, 26, 22) end
end

------------------------------------------------------------------ the ink octopus

-- how thick its arms are, and how far they reach below the dome's centre
local function ink_reach(R)
  local w = math.max(6, R * 30 // 100)
  return w, R * 14 // 10 + w // 2
end

-- one arm: down from under the dome, bending outwards along the ground, its tip curling up
local function ink_arm(tx, sy, gy, dir, r1, wig)
  local pts = { tx, sy }
  local cy = gy - r1
  if cy > sy then pts[#pts + 1] = tx + wig; pts[#pts + 1] = cy end
  local cx = tx + dir * r1
  for i = 1, 6 do                                     -- a quarter circle down to the ground
    local a = math.rad((dir == 1 and 180 or 0) + dir * -i * 15)
    pts[#pts + 1] = cx + math.floor(math.cos(a) * r1 + 0.5); pts[#pts + 1] = cy + math.floor(math.sin(a) * r1 + 0.5)
  end
  local r2 = r1 * 45 // 100
  for i = 1, 6 do                                     -- the tip, curling up and back
    local a = math.rad(90 - dir * i * 40)
    pts[#pts + 1] = cx + math.floor(math.cos(a) * r2 + 0.5); pts[#pts + 1] = gy - r2 + math.floor(math.sin(a) * r2 + 0.5)
  end
  return pts
end

local function ink(gg, stage, hx, hy, mood, phase, taste)
  local R = A.INK[stage]
  local w, reach = ink_reach(R)
  local gy = hy + reach - w // 2
  local n = stage == 'hatchling' and 4 or 5
  for i = 1, n do                                     -- the arms, behind the dome: a white tube, outlined
    local off = 2 * i - n - 1                         -- -4 .. 4 (or -3 .. 3)
    local dir = off < 0 and -1 or (off > 0 and 1 or (phase % 2 == 0 and 1 or -1))
    local r1 = R * (24 + 7 * math.abs(off)) // 100
    local pts = ink_arm(hx + off * R * 18 // 100, hy + R * 6 // 10, gy, dir, r1, math.floor(math.sin(i + phase) * 2))
    gg:polyline(pts, { line_width = w })
    if w >= 7 then gg:polyline(pts, { line_width = w - 4, color = 0 }) end
  end
  -- the dome: round below, taller above
  local pts = {}
  for i = 0, 23 do
    local a = i * math.pi * 2 / 24
    local s = math.sin(a)
    pts[#pts + 1] = hx + math.floor(math.cos(a) * R)
    pts[#pts + 1] = hy + math.floor(s * (s < 0 and R * 13 // 10 or R * 9 // 10))
  end
  shape(gg, pts)
  local top = hy - R * 13 // 10
  for _, s in ipairs({ { -4, -9, 3 }, { 2, -11, 2 }, { 5, -6, 2 } }) do         -- ink spots
    gg:circle(hx + s[1] * R // 10, hy + s[2] * R // 10, s[3], BLACK)
  end
  face(gg, hx, hy, R, mood, stage == 'grown' or stage == 'elder')
  local hat = stage ~= 'hatchling' and taste and accessory(gg, taste, hx, top + R, R)
  if mood == 'sulky' then storm(gg, hx, top) end
  if stage == 'elder' and not hat then
    -- a beret, tilted, with its little stalk
    local bp = {}
    for i = 0, 15 do
      local a = i * math.pi * 2 / 16
      bp[#bp + 1] = hx - R // 5 + math.floor(math.cos(a) * R * 8 // 10)
      bp[#bp + 1] = top + 3 + math.floor(math.sin(a) * R // 4)
    end
    gg:polygon(bp, BLACK)
    gg:rect(hx - R // 5 - 2, top - R // 4 - 6, 4, 8, BLACK)
  end
  if stage == 'hatchling' then shell(gg, hx, hy + R + 6, 26, 18) end
end

------------------------------------------------------------------ the shelf dragon

-- a thick stroke with a white inside, like the octopus's arms
local function tube(gg, pts, w)
  gg:polyline(pts, { line_width = w })
  if w >= 7 then gg:polyline(pts, { line_width = w - 4, color = 0 }) end
end

-- its body's centre and size, from the head's: the body sits behind and below the head
local function dragon_body(hr, hx, hy)
  local br = hr * 13 // 10
  return hx - hr * 20 // 10, hy + br * 13 // 10, br
end

local function dragon(gg, stage, hx, hy, mood, phase, taste)
  local hr = A.DRAGON[stage]
  local bx, by, br = dragon_body(hr, hx, hy)
  local rx = br * 12 // 10
  -- the wing, folded on its back, three fingers with a scalloped edge (behind the body)
  local f = { { 45, -75 }, { 0, -250 }, { -40, -150 }, { -95, -210 }, { -100, -120 }, { -150, -150 }, { -95, -55 } }
  local wing = {}
  for _, p in ipairs(f) do wing[#wing + 1] = bx + br * p[1] // 100; wing[#wing + 1] = by + br * p[2] // 100 end
  shape(gg, wing)
  local wx, wy = bx - br * 15 // 100, by - br * 70 // 100
  for _, k in ipairs({ 2, 4, 6 }) do
    gg:line(wx, wy, bx + br * f[k][1] // 100 + 2, by + br * f[k][2] // 100 + 4, { line_width = 2 })
  end
  -- the tail, out along the ground and up at its tip, with a spade
  local sx, sy, wig = bx - rx * 8 // 10, by + br * 4 // 10, (phase % 2 == 1) and br // 6 or 0
  local tail = {}
  for i = 0, 8 do
    local t = i / 8
    tail[#tail + 1] = sx - math.floor(t * br * 22 // 10)
    tail[#tail + 1] = sy + math.floor(math.sin(t * math.pi) * (br * 2 // 10 + wig) - t * t * br * 9 // 10)
  end
  local ex, ey = tail[#tail - 1], tail[#tail]
  gg:polygon({ ex + 4, ey + 2, ex - br * 4 // 10, ey - br * 3 // 10, ex - 2, ey - br * 45 // 100 }, BLACK)
  tube(gg, tail, math.max(6, br * 32 // 100))
  -- legs, the body with a striped belly, the neck
  local lw = math.max(4, br // 5)
  gg:line(bx - br // 2, by + br - 6, bx - br // 2 - 4, by + br + 8, { line_width = lw })
  gg:line(bx + br // 2, by + br - 6, bx + br // 2 + 4, by + br + 8, { line_width = lw })
  local body = {}
  for i = 0, 23 do
    local a = i * math.pi * 2 / 24
    body[#body + 1] = bx + math.floor(math.cos(a) * rx); body[#body + 1] = by + math.floor(math.sin(a) * br)
  end
  shape(gg, body)
  gg:arc(bx + br // 5, by + 2, br * 7 // 10, 30, 150, { line_width = 2 })
  gg:arc(bx + br // 5, by + 2, br * 45 // 100, 40, 140, { line_width = 2 })
  tube(gg, { bx + rx * 5 // 10, by - br * 5 // 10, hx - hr * 5 // 10, hy + hr * 5 // 10 }, math.max(10, hr))
  -- horns swept back, the head, a long muzzle in front of it
  local top = hy - hr
  shape(gg, { hx - hr * 6 // 10, top + hr * 4 // 10, hx - hr * 2 // 10, top + 2, hx - hr * 15 // 10, top - hr * 6 // 10 }, 2)
  shape(gg, { hx, top + 2, hx + hr * 4 // 10, top + hr * 3 // 10, hx - hr * 5 // 10, top - hr * 9 // 10 }, 2)
  ring(gg, hx, hy, hr, 3)
  local nw, nh = hr * 15 // 10, hr * 8 // 10
  local nx, ny = hx + hr * 3 // 10, hy + hr * 1 // 10
  gg:rect(nx, ny, nw, nh, { fill = true, color = 0 }); gg:rect(nx, ny, nw, nh, { line_width = 3, radius = nh // 2 })
  gg:circle(nx + nw - nh // 2, ny + nh // 3, 2, BLACK); gg:circle(nx + nw - nh // 5, ny + nh // 3, 2, BLACK)
  -- eyes above the muzzle, the mouth along it
  local fr = hr * 8 // 10
  face(gg, hx - hr * 1 // 10, hy - hr * 2 // 10, fr, mood, stage == 'grown' or stage == 'elder')
  local hat = stage ~= 'hatchling' and taste and accessory(gg, taste, hx - hr // 10, hy - hr * 2 // 10, fr, hr * 9 // 10)
  if mood == 'sulky' then storm(gg, hx, top) end
  if stage == 'elder' and not hat then
    -- a little crown between the horns
    local w = hr * 45 // 100
    gg:polygon({ hx - w, top + 3, hx - w, top - 12, hx - w // 2, top - 4, hx, top - 15, hx + w // 2, top - 4,
                 hx + w, top - 12, hx + w, top + 3 }, BLACK)
  end
  if stage == 'hatchling' then shell(gg, bx - rx // 2, by + br - 8, 24, 16) end
end

------------------------------------------------------------------ placing and drawing

-- where its head goes for a creature of kind sp at stage, centred on cx, standing on ground
function A.pose(sp, stage, cx, ground)
  if sp == 'ink' then
    local _rs, reach = ink_reach(A.INK[stage] or A.INK.young)
    return cx, ground - reach
  elseif sp == 'dragon' then
    local hr = A.DRAGON[stage] or A.DRAGON.young
    -- from the tail's spade to the snout: about 6.3 and 1.4 head radii either side of the head
    local _bx, by, br = dragon_body(hr, 0, 0)
    return cx + hr * 26 // 10, ground - 8 - br - by
  end
  local b = A.BODY[stage] or A.BODY.young
  local length = b[1] * b[2] * 17 // 10
  return cx + (length + b[2] * 13 // 10) // 2, ground - b[2] * 4 // 3 - 2
end

-- the creature, head at (hx, hy); phase shifts its wiggle (a pat); taste adds what it wears
function A.creature(gg, sp, stage, hx, hy, mood, phase, taste)
  phase = phase or 0
  if sp == 'ink' then ink(gg, stage, hx, hy, mood, phase, taste)
  elseif sp == 'dragon' then dragon(gg, stage, hx, hy, mood, phase, taste)
  else worm(gg, stage, hx, hy, mood, phase, taste) end
end

-- the egg of kind sp, standing on (x, y): an oval with speckles, swirls or scales; size in percent
function A.egg(gg, x, y, wobble, sp, size)
  size = size or 100
  local pts = {}
  local w, h = 46 * size // 100, 62 * size // 100
  for i = 0, 23 do
    local a = i * math.pi * 2 / 24
    local rx = w * (1 - 0.12 * math.sin(a))
    pts[#pts + 1] = x + math.floor(math.cos(a) * rx + (wobble or 0) * math.sin(a))
    pts[#pts + 1] = y - h + math.floor(math.sin(a) * h)
  end
  shape(gg, pts)
  local k = size
  if sp == 'locked' then
    gg:text_box(x - w, y - h - 18, 2 * w, 36, '?', { font = ctx.fonts and ctx.fonts.large, align = 'center' })
  elseif sp == 'ink' then                            -- inky swirls
    gg:arc(x - 6 * k // 100, y - 84 * k // 100, 16 * k // 100, 20, 200, { line_width = 3 })
    gg:arc(x + 8 * k // 100, y - 52 * k // 100, 20 * k // 100, 200, 380, { line_width = 3 })
    gg:circle(x - 18 * k // 100, y - 30 * k // 100, math.max(2, 5 * k // 100), BLACK)
  elseif sp == 'dragon' then                         -- rows of scales
    for row, dy in ipairs({ 92, 70, 48, 26 }) do
      local n = (row == 1 or row == 4) and 2 or 3
      for j = 1, n do
        local sx = x + (j - (n + 1) / 2) * 24 * k // 100
        gg:arc(math.floor(sx), y - dy * k // 100, 9 * k // 100, 20, 160, { line_width = 2 })
      end
    end
  else                                               -- the bookworm's speckles
    for _, s in ipairs({ { -16, -88, 6 }, { 14, -70, 5 }, { -6, -40, 4 }, { 22, -30, 4 }, { -24, -58, 3 } }) do
      gg:circle(x + s[1] * k // 100, y + s[2] * k // 100, math.max(2, s[3] * k // 100), BLACK)
    end
  end
end

-- a closed book lying flat, its top at y: what the creature sits on
function A.book(gg, x, y, w)
  gg:rect(x, y, w, 26, WHITE)
  gg:rect(x, y, w, 26, { line_width = 3, radius = 3 })
  for i = 1, 3 do gg:line(x + 10, y + 6 * i + 1, x + w - 18, y + 6 * i + 1) end      -- the pages' edge
  gg:rect(x + w - 14, y, 14, 26, BLACK)                                             -- the spine
end

-- an open book, the pages curving up from its middle at (x, y)
function A.open_book(gg, x, y, w)
  local h = 40
  for _, s in ipairs({ -1, 1 }) do
    shape(gg, { x, y, x + s * w // 2, y - 10, x + s * w // 2, y + h, x, y + h + 8 })
    for i = 1, 3 do gg:line(x + s * 14, y + 8 * i + 2, x + s * (w // 2 - 14), y + 8 * i - 4) end
  end
end

-- a book standing up with two eyes in the gap of its pages: the creature hiding (an octopus
-- leaves ink drops, a dragon's tail sticks out)
function A.hiding(gg, x, y, sp)
  gg:rect(x - 50, y - 130, 100, 130, WHITE)
  gg:rect(x - 50, y - 130, 100, 130, { line_width = 4, radius = 4 })
  gg:rect(x - 50, y - 130, 18, 130, BLACK)
  gg:rect(x + 10, y - 80, 30, 14, BLACK)
  gg:circle(x + 18, y - 73, 4, WHITE); gg:circle(x + 32, y - 73, 4, WHITE)
  if sp == 'ink' then
    gg:circle(x + 62, y - 6, 6, BLACK); gg:circle(x + 78, y - 3, 4, BLACK); gg:circle(x + 58, y - 22, 3, BLACK)
  elseif sp == 'dragon' then
    ring(gg, x + 58, y - 8, 7, 2); ring(gg, x + 72, y - 12, 5, 2)
    gg:polygon({ x + 76, y - 22, x + 92, y - 16, x + 78, y - 6 }, BLACK)
  end
end

-- a thought bubble with the dream in it, its little circles leading down to (tx, ty)
function A.dream(gg, x, y, w, h, tx, ty, text, font)
  gg:rect(x, y, w, h, WHITE)
  gg:rect(x, y, w, h, { line_width = 3, radius = 26 })
  for i, r in ipairs({ 9, 6, 4 }) do
    local cx, cy = tx - (tx - (x + w // 2)) * (3 - i) // 4, y + h + i * 18
    gg:circle(cx, cy, r, WHITE); gg:circle(cx, cy, r, { line_width = 2 })
  end
  -- centred by hand: one line or two (about 11 px a letter in the medium font)
  local lines = (utf8.len(text) or #text) * 11 > w - 36 and 2 or 1
  gg:text_box(x + 18, y + (h - lines * 26) // 2, w - 36, lines * 26 + 4, text, { font = font, align = 'center' })
end

-- asleep: curled up on an open book, with z's; returns the x of its head
function A.asleep(gg, sp, stage, x, y, taste)
  A.open_book(gg, x, y, 300)
  if stage == 'egg' then A.egg(gg, x, y + 4, 0, sp); return x end
  local hx, hy = A.pose(sp, stage, x, y - 4)
  A.creature(gg, sp, stage, hx, hy, 'asleep', 2, taste)
  -- the z's rise from its head (kept on the screen)
  local zx, zy = math.min(hx + 24, 400), math.min(y - 110, hy - 80)
  local small = ctx.fonts and ctx.fonts.medium
  gg:text(zx, zy, 'z', { font = small }); gg:text(zx + 16, zy - 26, 'z', { font = small })
  gg:text(zx + 36, zy - 56, 'Z', { font = ctx.fonts and ctx.fonts.large })
  return hx
end

return A
