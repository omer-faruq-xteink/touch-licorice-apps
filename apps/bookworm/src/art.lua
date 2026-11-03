-- The bookworm's pictures, drawn from circles, arcs and lines (no image files): an egg, the worm
-- at each stage (more and bigger segments as it grows; round glasses once grown, a scholar's cap
-- for the elder), its face by mood, the book it sits on, a book it hides in, and its sleeping
-- pose. Every function takes the canvas and where to draw; they serve the app and the sleep screen.

local A = {}

local WHITE = { fill = true, color = 0 }
local BLACK = { fill = true }

-- the segments of each stage: how many, their radius
A.BODY = { hatchling = { 3, 13 }, young = { 4, 17 }, grown = { 5, 20 }, elder = { 6, 22 } }

local function ring(gg, x, y, r, w) gg:circle(x, y, r, WHITE); gg:circle(x, y, r, { line_width = w or 3 }) end

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

-- how far the worm reaches left of its head, and the x of a head that centres it on cx
function A.length(stage)
  local b = A.BODY[stage] or A.BODY.young
  return b[1] * b[2] * 17 // 10
end
function A.head_x(stage, cx)
  local b = A.BODY[stage] or A.BODY.young
  return cx + (A.length(stage) + b[2] * 13 // 10) // 2
end

-- what its taste makes it wear or carry, on a head of radius hr at (hx, hy); returns true for a
-- hat (no scholar's cap then)
local function accessory(gg, taste, hx, hy, hr)
  local top = hy - hr
  if taste == 'fantasy' then                         -- a wizard's hat with a star
    gg:polygon({ hx - hr - 4, top + 6, hx + 6, top - 46, hx + hr + 4, top + 6 }, WHITE)
    gg:polygon({ hx - hr - 4, top + 6, hx + 6, top - 46, hx + hr + 4, top + 6 }, { line_width = 3 })
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
    local cx, cy = hx + hr + 22, hy + 4
    gg:circle(cx, cy, 13, WHITE); gg:circle(cx, cy, 13, { line_width = 3 })
    gg:polygon({ cx - 6, cy + 11, cx - 2, cy + 13, cx - 10, cy + 30, cx - 15, cy + 28 }, BLACK)
  elseif taste == 'horror' then                      -- a candle, its flame shaking
    local cx, cy = hx + hr + 22, hy + 6
    gg:rect(cx - 6, cy - 4, 12, 26, WHITE); gg:rect(cx - 6, cy - 4, 12, 26, { line_width = 2 })
    gg:polygon({ cx, cy - 24, cx + 6, cy - 10, cx, cy - 5, cx - 6, cy - 10 }, BLACK)
    gg:rect(cx - 12, cy + 22, 24, 4, BLACK)
  elseif taste == 'romance' then                     -- a heart floating up
    local cx, cy = hx + hr + 18, top - 4
    gg:circle(cx - 6, cy, 7, BLACK); gg:circle(cx + 6, cy, 7, BLACK)
    gg:polygon({ cx - 13, cy + 2, cx + 13, cy + 2, cx, cy + 17 }, BLACK)
  elseif taste == 'adventure' then                   -- an eyepatch
    local ex, ey = hx + hr * 4 // 10, hy - hr // 6
    gg:line(hx - hr + 4, ey - hr // 2, hx + hr - 2, ey + 2)
    gg:circle(ex, ey, hr // 5 + 4, BLACK)
  elseif taste == 'nonfiction' then                  -- a quill
    local cx, cy = hx + hr + 16, hy - 6
    gg:polygon({ cx, cy + 28, cx + 4, cy + 22, cx + 16, cy - 18, cx + 8, cy - 22 }, WHITE)
    gg:polygon({ cx, cy + 28, cx + 4, cy + 22, cx + 16, cy - 18, cx + 8, cy - 22 }, { line_width = 2 })
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

-- the worm, head at (hx, hy) facing right, body trailing left along a gentle wave; phase shifts
-- the wave (a wiggle when it is petted); taste adds what it wears
function A.worm(gg, stage, hx, hy, mood, phase, taste)
  local b = A.BODY[stage] or A.BODY.young
  local n, r = b[1], b[2]
  phase = phase or 0
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
  if stage == 'hatchling' then
    -- the bottom half of its shell still around the tail
    local tx = pts[1][1]
    gg:polygon({ tx - 30, hy + 4, tx - 22, hy + 28, tx + 22, hy + 28, tx + 30, hy + 4, tx + 18, hy + 12, tx + 6, hy + 2,
                 tx - 6, hy + 12, tx - 18, hy + 2 }, WHITE)
    gg:polygon({ tx - 30, hy + 4, tx - 22, hy + 28, tx + 22, hy + 28, tx + 30, hy + 4, tx + 18, hy + 12, tx + 6, hy + 2,
                 tx - 6, hy + 12, tx - 18, hy + 2 }, { line_width = 3 })
  end
end

-- the egg, standing on (x, y): an oval with speckles
function A.egg(gg, x, y, wobble)
  local pts = {}
  local w, h = 46, 62
  for i = 0, 23 do
    local a = i * math.pi * 2 / 24
    local rx = w * (1 - 0.12 * math.sin(a))
    pts[#pts + 1] = x + math.floor(math.cos(a) * rx + (wobble or 0) * math.sin(a))
    pts[#pts + 1] = y - h + math.floor(math.sin(a) * h)
  end
  gg:polygon(pts, WHITE)
  gg:polygon(pts, { line_width = 3 })
  for _, s in ipairs({ { -16, -88, 6 }, { 14, -70, 5 }, { -6, -40, 4 }, { 22, -30, 4 }, { -24, -58, 3 } }) do
    gg:circle(x + s[1], y + s[2], s[3], BLACK)
  end
end

-- a closed book lying flat, its top at y: what the worm sits on
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
    local pts = { x, y, x + s * w // 2, y - 10, x + s * w // 2, y + h, x, y + h + 8 }
    gg:polygon(pts, WHITE)
    gg:polygon(pts, { line_width = 3 })
    for i = 1, 3 do gg:line(x + s * 14, y + 8 * i + 2, x + s * (w // 2 - 14), y + 8 * i - 4) end
  end
end

-- a book standing up with two eyes in the gap of its pages: the bookworm hiding
function A.hiding(gg, x, y)
  gg:rect(x - 50, y - 130, 100, 130, WHITE)
  gg:rect(x - 50, y - 130, 100, 130, { line_width = 4, radius = 4 })
  gg:rect(x - 50, y - 130, 18, 130, BLACK)
  gg:rect(x + 10, y - 80, 30, 14, BLACK)
  gg:circle(x + 18, y - 73, 4, WHITE); gg:circle(x + 32, y - 73, 4, WHITE)
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

-- asleep: curled up on an open book, with z's
function A.asleep(gg, stage, x, y, taste)
  A.open_book(gg, x, y, 300)
  if stage == 'egg' then A.egg(gg, x, y + 4); return end
  local hx = A.head_x(stage, x)
  A.worm(gg, stage, hx, y - 34, 'asleep', 2, taste)
  -- the z's rise from its head (kept on the screen)
  local zx = math.min(hx + 8, 400)
  local small = ctx.fonts and ctx.fonts.medium
  gg:text(zx, y - 110, 'z', { font = small }); gg:text(zx + 16, y - 136, 'z', { font = small })
  gg:text(zx + 36, y - 166, 'Z', { font = ctx.fonts and ctx.fonts.large })
end

return A
