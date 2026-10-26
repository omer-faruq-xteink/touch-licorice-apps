-- Knight's Tour for XTOS Licorice, API 2.9 (uses tools/gamekit).
--
-- Move a chess knight so that it visits every square of the board exactly once. The first tap
-- places it; after that the squares it can jump to (not visited yet) carry a small ring, and
-- visited squares show their move number. The knight's square is framed twice. Hint marks the
-- move Warnsdorff's rule suggests (the square with the fewest onward jumps). Undo, New, Size
-- (6x6 or 8x8: on 5x5 a full tour does not exist from every square). Saved after every move.

local W, H = kit.W, kit.H
local SIZES = { 6, 8 }
local BTN_Y, BTN_H = 690, 60
local JUMPS = { { 1, 2 }, { 2, 1 }, { 2, -1 }, { 1, -2 }, { -1, -2 }, { -2, -1 }, { -2, 1 }, { -1, 2 } }

local size = 8
local path = {}          -- squares in order: { r, c }
local order = {}         -- "r,c" -> move number
local hint = nil
local best = {}          -- size -> most squares visited
local tours = {}         -- size -> complete tours
local msg = nil
local ERR = nil
local undo               -- defined with the actions

local function key(r, c) return r .. ',' .. c end
local function geometry()
  local cell = math.floor(456 / size)
  return cell, (W - size * cell) // 2, 120
end

------------------------------------------------------------------ rules

local function moves_from(r, c)
  local out = {}
  for _k, d in ipairs(JUMPS) do
    local rr, cc = r + d[1], c + d[2]
    if rr >= 1 and rr <= size and cc >= 1 and cc <= size and not order[key(rr, cc)] then out[#out + 1] = { rr, cc } end
  end
  return out
end

local function here() return path[#path] end

------------------------------------------------------------------ storage

local function save()
  local p = {}
  for _k, s in ipairs(path) do p[#p + 1] = s[1] .. ',' .. s[2] end
  local b = {}
  for _k, n in ipairs(SIZES) do b[#b + 1] = n .. ':' .. (best[n] or 0) .. ':' .. (tours[n] or 0) end
  kit.write('game.txt', 'size=' .. size .. '\npath=' .. table.concat(p, ';') .. '\nbest=' .. table.concat(b, ';'))
end

local function reset()
  path, order, hint, msg = {}, {}, nil, nil
  save()
end

local function load()
  local t = kit.kv(kit.read('game.txt'))
  size = tonumber(t.size) or 8
  if size ~= 6 and size ~= 8 then size = 8 end
  for n, b, k in (t.best or ''):gmatch('(%d+):(%d+):(%d+)') do best[tonumber(n)] = tonumber(b); tours[tonumber(n)] = tonumber(k) end
  path, order = {}, {}
  for r, c in (t.path or ''):gmatch('(%d+),(%d+)') do
    path[#path + 1] = { tonumber(r), tonumber(c) }
    order[key(tonumber(r), tonumber(c))] = #path
  end
end

------------------------------------------------------------------ actions

local function finished()
  local n = #path
  if not best[size] or n > best[size] then best[size] = n end
  if n == size * size then
    tours[size] = (tours[size] or 0) + 1
    kit.show({
      title = 'Tour complete!',
      lines = { 'The knight visited all ' .. n .. ' squares.', 'Complete tours on ' .. size .. 'x' .. size .. ': ' .. tours[size] },
      rows = { { { 'New', function() kit.close(); reset() end }, { 'Close', kit.close } } },
      cancel = kit.close,
    })
  else
    kit.show({
      title = 'No more moves',
      lines = { n .. ' of ' .. size * size .. ' squares visited.', 'Best on ' .. size .. 'x' .. size .. ': ' .. best[size] },
      rows = { { { 'Undo', function() kit.close(); undo() end }, { 'New', function() kit.close(); reset() end } } },
      cancel = kit.close,
    })
  end
end

local function go(r, c)
  path[#path + 1] = { r, c }
  order[key(r, c)] = #path
  hint, msg = nil, nil
  kit.moved()
  if #moves_from(r, c) == 0 then finished() end
  save()
end

undo = function()
  local s = table.remove(path)
  if not s then msg = 'Nothing to undo.'; return end
  order[key(s[1], s[2])] = nil
  hint = nil
  save()
end

local function tap_square(r, c)
  local h = here()
  if not h then go(r, c); return end
  if order[key(r, c)] then msg = 'Already visited.'; return end
  for _k, m in ipairs(moves_from(h[1], h[2])) do
    if m[1] == r and m[2] == c then go(r, c); return end
  end
  msg = 'A knight cannot jump there.'
end

-- Warnsdorff: of the possible jumps, the one with the fewest onward jumps
local function show_hint()
  local h = here()
  if not h then msg = 'Tap any square to place the knight.'; return end
  local best_m, best_n = nil, 99
  for _k, m in ipairs(moves_from(h[1], h[2])) do
    order[key(m[1], m[2])] = -1
    local n = #moves_from(m[1], m[2])
    order[key(m[1], m[2])] = nil
    if n < best_n then best_m, best_n = m, n end
  end
  hint = best_m
  msg = best_m and 'Hint: the framed square (fewest onward jumps).' or nil
end

local BUTTONS = {
  { function() return 'Undo' end, function() undo() end },
  { function() return 'Hint' end, show_hint },
  { function() return 'New' end, function() reset() end },
  { function() return size .. 'x' .. size end, function()
      save()
      size = size == 8 and 6 or 8
      reset()
    end },
}
local function button_rect(k)
  local bw = math.floor((W - 24 - 3 * 8) / 4)
  return 12 + (k - 1) * (bw + 8), BTN_Y, bw, BTN_H
end

------------------------------------------------------------------ drawing

local function circle(gg, x, y, r) pcall(function() gg:circle(x, y, r) end) end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    gg:clear(0)
    gg:text(12, 12, "Knight's Tour", { font = kit.font('large') })
    gg:text(12, 52, size .. 'x' .. size .. '    Visited ' .. #path .. '/' .. size * size ..
      '    Best ' .. (best[size] or 0) .. '    Tours ' .. (tours[size] or 0), { font = kit.font('small') })
    gg:line(0, 90, W, 90)
    if kit.modal() then kit.draw_modal(gg); return end
    local cell, gx, gy = geometry()
    local h = here()
    local targets = {}
    if h then for _k, m in ipairs(moves_from(h[1], h[2])) do targets[key(m[1], m[2])] = true end end
    local small, medium = kit.font('small'), kit.font('medium')
    for r = 1, size do
      for cc = 1, size do
        local x, y = gx + (cc - 1) * cell, gy + (r - 1) * cell
        gg:rect(x, y, cell, cell, { line_width = 1 })
        local k = key(r, cc)
        if order[k] then
          local s = tostring(order[k])
          local f = (h and h[1] == r and h[2] == cc) and medium or small
          local lh = kit.line_h(f == medium and 'medium' or 'small')
          gg:text(x + math.floor((cell - kit.width(f, s)) / 2), y + math.floor((cell - lh) / 2), s, { font = f })
        elseif targets[k] then
          for o = 0, 2 do circle(gg, x + cell // 2, y + cell // 2, cell // 5 - o) end
        end
        if h and h[1] == r and h[2] == cc then
          gg:rect(x + 3, y + 3, cell - 6, cell - 6, { line_width = 3 })
          gg:rect(x + 9, y + 9, cell - 18, cell - 18, { line_width = 2 })
        end
        if hint and hint[1] == r and hint[2] == cc then
          gg:rect(x + 4, y + 4, cell - 8, cell - 8, { line_width = 3 })
        end
      end
    end
    gg:rect(gx - 2, gy - 2, size * cell + 4, size * cell + 4, { line_width = 2 })
    local m = msg or (h and 'Tap a ringed square to jump.' or 'Tap any square to place the knight.')
    gg:text(12, BTN_Y - 34, kit.short(m, 48), { font = kit.font('small') })
    for k, b in ipairs(BUTTONS) do
      local x, y, bw, bh = button_rect(k)
      kit.button(gg, x, y, bw, bh, b[1]())
    end
    if ERR then gg:text(12, H - 30, kit.short('ERR ' .. ERR, 48), { font = kit.font('small') }) end
  end)
  if not ok then pcall(function() gg:text(8, H - 60, kit.short('draw ERR ' .. tostring(e), 46)) end) end
end

function on_input(c, ev)
  ERR = nil
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    if ev.type == 'pointer' and ev.phase == 'up' then
      local x, y = ev.x or 0, ev.y or 0
      if kit.tap_modal(x, y) then return end
      for k, b in ipairs(BUTTONS) do
        local bx, by, bw, bh = button_rect(k)
        if x >= bx and x < bx + bw and y >= by and y < by + bh then b[2](); return end
      end
      local cell, gx, gy = geometry()
      if x >= gx and x < gx + size * cell and y >= gy and y < gy + size * cell then
        tap_square((y - gy) // cell + 1, (x - gx) // cell + 1)
      end
    elseif ev.type == 'key' and kit.key_accepted(ev) and ev.key == 'back' and kit.modal() and kit.modal().cancel then
      kit.modal().cancel()
    end
  end)
  if not ok then ERR = tostring(e) end
  kit.refresh()
  return true
end

function on_load(c) load() end
function on_leave() save() end

if rawget(_G, '__TEST') then
  __TEST.api = { geometry = geometry, moves_from = moves_from, size = function() return size end,
                 path = function() return #path end, hint = function() return hint end }
end
