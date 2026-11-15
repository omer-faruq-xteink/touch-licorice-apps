-- The map view, put together in an offscreen layer: tiles are read a row at a time, unzipped,
-- decoded at most 6 at a time and drawn in one layer:draw, and freed only after that draw returns
-- (a picture freed inside the draw is drawn blank on the device). A pan copies the old layer shifted
-- into the spare one and draws only the tiles that came into view. on_draw only shows the layer.
local choose = require('choose')

local V = {}
V.__index = V

local BATCH = 6
local T = 256

function V.new(c, w, h)
  local self = setmetatable({ w = w, h = h, z = 14, cx = 0, cy = 0, packs = {}, edge = false, missing = 0,
    overlay = nil }, V)
  self.layer = c.layers:create(w, h)
  self.spare = c.layers:create(w, h)
  return self
end

function V:left() return self.cx - self.w // 2 end
function V:top() return self.cy - self.h // 2 end

-- the tiles touching the rectangle (global pixels) x0..x1, y0..y1
local function tiles_in(x0, y0, x1, y1)
  return x0 >> 8, y0 >> 8, x1 >> 8, y1 >> 8
end

local function extend() pcall(function() ctx.budget:extend() end) end

-- draw the tiles of the rectangles (global pixels) into `target`; `first` runs at the start of the
-- first layer:draw (clear, or the shifted old layer)
function V:paint(target, rects, first)
  extend()                                         -- before the reads, too
  local z, left, top = self.z, self:left(), self:top()
  local seen, jobs, frames = {}, {}, {}
  for _, r in ipairs(rects) do
    local tx0, ty0, tx1, ty1 = tiles_in(r[1], r[2], r[3], r[4])
    for ty = ty0, ty1 do
      -- per pack, the run of tiles it draws in this row: one read of the index, one of the pictures
      local runs = {}
      for tx = tx0, tx1 do
        local key = tx .. ',' .. ty
        if not seen[key] then
          seen[key] = true
          local p = choose.pick(self.packs, z, tx, ty)
          if p then
            local run = runs[p]
            if not run then run = { p = p, a = tx, b = tx, want = {} }; runs[p] = run end
            if tx < run.a then run.a = tx end
            if tx > run.b then run.b = tx end
            run.want[#run.want + 1] = tx
          else
            frames[#frames + 1] = { tx * T - left, ty * T - top }
          end
        end
      end
      for _, run in pairs(runs) do
        local row = run.p:read_row(z, ty, run.a, run.b)
        for _, tx in ipairs(run.want) do
          local b = row[tx]
          if b then jobs[#jobs + 1] = { b, tx * T - left, ty * T - top } end
        end
      end
    end
  end
  extend()
  local i, started = 1, false
  repeat
    local batch = {}
    while #batch < BATCH and i <= #jobs do
      local j = jobs[i]
      i = i + 1
      local okz, bmp = pcall(function() return ctx.zlib:decompress(j[1]) end)
      local okd, im = false, nil
      if okz and bmp then okd, im = pcall(function() return ctx.image:decode(bmp) end) end
      if okd and im then batch[#batch + 1] = { im, j[2], j[3] } end
    end
    local last = i > #jobs
    target:draw(function(g)
      if not started and first then first(g) end
      for _, b in ipairs(batch) do g:image(b[1], b[2], b[3]) end
      if last then
        for _, f in ipairs(frames) do                 -- no pack here: a faint dotted frame
          for k = 0, T - 8, 8 do
            g:line(f[1] + k, f[2], f[1] + k + 3, f[2]); g:line(f[1] + k, f[2] + T - 1, f[1] + k + 3, f[2] + T - 1)
            g:line(f[1], f[2] + k, f[1], f[2] + k + 3); g:line(f[1] + T - 1, f[2] + k, f[1] + T - 1, f[2] + k + 3)
          end
        end
        if self.overlay then self.overlay(g, left, top) end
      end
    end)
    started = true
    for _, b in ipairs(batch) do pcall(function() b[1]:release() end) end   -- after the draw returned
  until last
end

-- how many visible tiles no pack has
function V:count_missing()
  local left, top = self:left(), self:top()
  local tx0, ty0, tx1, ty1 = tiles_in(left, top, left + self.w - 1, top + self.h - 1)
  local n = 0
  for ty = ty0, ty1 do
    for tx = tx0, tx1 do
      if not choose.pick(self.packs, self.z, tx, ty) then n = n + 1 end
    end
  end
  self.missing = n
  self.edge = n > 0
end

function V:set(z, cx, cy)
  self.z, self.cx, self.cy = z, cx, cy
  local left, top = self:left(), self:top()
  self:paint(self.layer, { { left, top, left + self.w - 1, top + self.h - 1 } }, function(g) g:clear(0) end)
  self:count_missing()
end

-- the redraw of the current view (after the overlay changed)
function V:refresh() self:set(self.z, self.cx, self.cy) end

function V:pan(dx, dy)
  if math.abs(dx) >= self.w or math.abs(dy) >= self.h then return self:set(self.z, self.cx + dx, self.cy + dy) end
  self.cx, self.cy = self.cx + dx, self.cy + dy
  local left, top = self:left(), self:top()
  local r = {}
  local x1, y1 = left + self.w - 1, top + self.h - 1
  if dx > 0 then r[#r + 1] = { x1 - dx + 1, top, x1, y1 } elseif dx < 0 then r[#r + 1] = { left, top, left - dx - 1, y1 } end
  if dy > 0 then r[#r + 1] = { left, y1 - dy + 1, x1, y1 } elseif dy < 0 then r[#r + 1] = { left, top, x1, top - dy - 1 } end
  local old = self.layer
  self:paint(self.spare, r, function(g) g:clear(0); g:image(old, -dx, -dy) end)
  self.layer, self.spare = self.spare, old
  self:count_missing()
end

-- one level in (dir 1) or out (-1), keeping the screen point (px, py) where it is
function V:zoom(dir, px, py)
  local gx, gy = self:left() + px, self:top() + py
  if dir > 0 then gx, gy = gx * 2, gy * 2 else gx, gy = gx // 2, gy // 2 end
  self:set(self.z + dir, gx - px + self.w // 2, gy - py + self.h // 2)
end

function V:draw(g, x, y) g:image(self.layer, x, y) end

function V:release()
  pcall(function() self.layer:release() end)
  pcall(function() self.spare:release() end)
end

return V
