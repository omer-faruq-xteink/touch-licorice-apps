-- Peg Solitaire for XTOS Licorice, API 2.9 (uses tools/gamekit).
--
-- Jump a peg over a neighbour into an empty hole; the jumped peg is removed. End with as few pegs
-- as possible: one is a win, one in the centre of the English board is the classic perfect game.
-- Boards: English (33 holes, the centre empty at the start, moves along rows and columns) and
-- Triangle (15 holes, the top empty, moves in the six directions of the triangle grid).
--
-- Tap a peg to select it (framed); the holes it can jump to get a small mark; tap one of them to
-- jump. Tapping the selected peg again lets it go, tapping another peg selects that one. Undo takes
-- jumps back, New starts the board again, Board switches English / Triangle. Pegs are thick rings,
-- holes small circles: nothing is filled black (it ghosts on e-ink). Saved after every jump.

local W, H = kit.W, kit.H
local BTN_Y, BTN_H = 680, 60

-- a board: cells (list of {r, c} with screen x, y), directions (jump vectors), start hole
local BOARDS = {}

do -- English: a 7x7 cross
  local cells, xy = {}, {}
  local S, X0, Y0 = 62, 23, 150
  for r = 1, 7 do
    for c = 1, 7 do
      local in_cross = (r >= 3 and r <= 5) or (c >= 3 and c <= 5)
      if in_cross then cells[#cells + 1] = { r = r, c = c, x = X0 + (c - 1) * S + S // 2, y = Y0 + (r - 1) * S + S // 2 } end
    end
  end
  BOARDS[1] = { id = 'english', name = 'English', cells = cells, dirs = { { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } },
                start = { 4, 4 }, centre = { 4, 4 }, peg_r = 20, hit = S // 2 }
end

do -- Triangle: 5 rows, row r has r holes; neighbours along the row and the two diagonals
  local cells = {}
  local S, Y0 = 86, 170
  for r = 1, 5 do
    for c = 1, r do
      cells[#cells + 1] = { r = r, c = c, x = W // 2 + (c - 1) * S - (r - 1) * S // 2, y = Y0 + (r - 1) * 80 }
    end
  end
  BOARDS[2] = { id = 'triangle', name = 'Triangle', cells = cells,
                dirs = { { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 }, { 1, 1 }, { -1, -1 } },
                start = { 1, 1 }, peg_r = 24, hit = 40 }
end

local bi = 1             -- the board in play
local pegs = {}          -- "r,c" -> true
local history = {}       -- jumps { from = "r,c", over = "r,c", to = "r,c" }
local sel = nil          -- selected peg key
local best = {}          -- board id -> fewest pegs left
local msg = nil
local ERR = nil
local undo_jump          -- defined with the actions

local function key(r, c) return r .. ',' .. c end
local function board() return BOARDS[bi] end
local function exists(r, c)
  for _k, cell in ipairs(board().cells) do if cell.r == r and cell.c == c then return true end end
  return false
end

------------------------------------------------------------------ rules

-- the jumps the peg at (r, c) can make: { {to_r, to_c, over_r, over_c}, .. }
local function jumps_from(r, c)
  local out = {}
  if not pegs[key(r, c)] then return out end
  for _k, d in ipairs(board().dirs) do
    local orr, oc, tr, tc = r + d[1], c + d[2], r + 2 * d[1], c + 2 * d[2]
    if exists(tr, tc) and pegs[key(orr, oc)] and not pegs[key(tr, tc)] then out[#out + 1] = { tr, tc, orr, oc } end
  end
  return out
end

local function any_move()
  for _k, cell in ipairs(board().cells) do
    if #jumps_from(cell.r, cell.c) > 0 then return true end
  end
  return false
end

local function count()
  local n = 0
  for _k in pairs(pegs) do n = n + 1 end
  return n
end

------------------------------------------------------------------ storage

local function save()
  local list, hist = {}, {}
  for k in pairs(pegs) do list[#list + 1] = k end
  table.sort(list)
  for _k, j in ipairs(history) do hist[#hist + 1] = j.from .. '>' .. j.over .. '>' .. j.to end
  local b = {}
  for id, v in pairs(best) do b[#b + 1] = id .. ':' .. v end
  table.sort(b)
  kit.write('game.txt', 'board=' .. board().id .. '\npegs=' .. table.concat(list, ';') ..
    '\nhistory=' .. table.concat(hist, ';') .. '\nbest=' .. table.concat(b, ';'))
end

local function reset()
  pegs, history, sel, msg = {}, {}, nil, nil
  local b = board()
  for _k, cell in ipairs(b.cells) do
    if not (cell.r == b.start[1] and cell.c == b.start[2]) then pegs[key(cell.r, cell.c)] = true end
  end
  save()
end

local function load()
  local t = kit.kv(kit.read('game.txt'))
  for id, v in (t.best or ''):gmatch('([%a]+):(%d+)') do best[id] = tonumber(v) end
  for k, b in ipairs(BOARDS) do if b.id == t.board then bi = k end end
  if not t.pegs then reset(); return end
  pegs, history = {}, {}
  for k in t.pegs:gmatch('[^;]+') do pegs[k] = true end
  for f, o, to in (t.history or ''):gmatch('([%d,]+)>([%d,]+)>([%d,]+)') do history[#history + 1] = { from = f, over = o, to = to } end
  if count() == 0 then reset() end
end

------------------------------------------------------------------ actions

local function rating(n, centre)
  if n == 1 and centre then return 'Perfect: one peg, in the centre!' end
  if n == 1 then return 'Excellent: one peg left!' end
  if n == 2 then return 'Very good: two pegs left.' end
  if n <= 4 then return 'Good: ' .. n .. ' pegs left.' end
  return n .. ' pegs left. Try again!'
end

local function game_over()
  local n = count()
  local b = board()
  local centre = b.centre and pegs[key(b.centre[1], b.centre[2])] or false
  if not best[b.id] or n < best[b.id] then best[b.id] = n end
  save()
  kit.show({
    title = 'No more jumps',
    lines = { rating(n, n == 1 and centre), 'Best on this board: ' .. best[b.id] .. (best[b.id] == 1 and ' peg' or ' pegs') },
    rows = { { { 'New', function() kit.close(); reset() end }, { 'Undo', function() kit.close(); undo_jump() end } } },
    cancel = kit.close,
  })
end

local function jump(fr, fc, to_r, to_c, over_r, over_c)
  pegs[key(fr, fc)] = nil
  pegs[key(over_r, over_c)] = nil
  pegs[key(to_r, to_c)] = true
  history[#history + 1] = { from = key(fr, fc), over = key(over_r, over_c), to = key(to_r, to_c) }
  sel, msg = nil, nil
  kit.moved()
  save()
  if not any_move() then game_over() end
end

undo_jump = function()
  local j = table.remove(history)
  if not j then msg = 'Nothing to undo.'; return end
  pegs[j.to] = nil
  pegs[j.over] = true
  pegs[j.from] = true
  sel = nil
  save()
end

local function cell_at(x, y)
  local b = board()
  for _k, cell in ipairs(b.cells) do
    if math.abs(x - cell.x) < b.hit and math.abs(y - cell.y) < b.hit then return cell end
  end
  return nil
end

local function tap_cell(cell)
  local k = key(cell.r, cell.c)
  if pegs[k] then
    if sel == k then sel, msg = nil, nil
    elseif #jumps_from(cell.r, cell.c) == 0 then sel = nil; msg = 'That peg cannot jump.'
    else sel = k; msg = nil end
    return
  end
  if sel then
    local sr, sc = sel:match('(%d+),(%d+)')
    for _k, j in ipairs(jumps_from(tonumber(sr), tonumber(sc))) do
      if j[1] == cell.r and j[2] == cell.c then jump(tonumber(sr), tonumber(sc), j[1], j[2], j[3], j[4]); return end
    end
    msg = 'Pick one of the marked holes.'
  end
end

------------------------------------------------------------------ drawing

local BUTTONS = {
  { function() return 'Undo' end, function() undo_jump() end },
  { function() return 'New' end, function() reset() end },
  { function() return board().name end, function()
      save()
      bi = bi % #BOARDS + 1
      reset()
    end },
}
local function button_rect(k)
  local bw = math.floor((W - 24 - 2 * 8) / 3)
  return 12 + (k - 1) * (bw + 8), BTN_Y, bw, BTN_H
end

local function circle(gg, x, y, r) pcall(function() gg:circle(x, y, r) end) end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    gg:clear(0)
    local b = board()
    gg:text(16, 14, 'Peg Solitaire', { font = kit.font('large') })
    local best_s = best[b.id] and ('    Best ' .. best[b.id]) or ''
    gg:text(16, 58, b.name .. '    Pegs ' .. count() .. '    Jumps ' .. #history .. best_s, { font = kit.font('medium') })
    gg:line(0, 100, W, 100)
    if kit.modal() then kit.draw_modal(gg); return end
    local targets = {}
    if sel then
      local sr, sc = sel:match('(%d+),(%d+)')
      for _k, j in ipairs(jumps_from(tonumber(sr), tonumber(sc))) do targets[key(j[1], j[2])] = true end
    end
    for _k, cell in ipairs(b.cells) do
      local k = key(cell.r, cell.c)
      if pegs[k] then
        for o = 0, 3 do circle(gg, cell.x, cell.y, b.peg_r - o) end   -- a thick ring
        circle(gg, cell.x, cell.y, 5)
        if sel == k then
          local s = b.peg_r + 7
          gg:rect(cell.x - s, cell.y - s, 2 * s, 2 * s, { line_width = 3 })
        end
      else
        circle(gg, cell.x, cell.y, 6)                              -- an empty hole
        if targets[k] then for o = 0, 2 do circle(gg, cell.x, cell.y, 14 - o) end end
      end
    end
    local m = msg or (sel and 'Tap a marked hole to jump.' or 'Tap a peg, then the hole to jump to.')
    gg:text(16, BTN_Y - 40, kit.short(m, 48), { font = kit.font('small') })
    for k, bt in ipairs(BUTTONS) do
      local x, y, bw, bh = button_rect(k)
      kit.button(gg, x, y, bw, bh, bt[1]())
    end
    if ERR then gg:text(16, H - 30, kit.short('ERR ' .. ERR, 48), { font = kit.font('small') }) end
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
      for k, bt in ipairs(BUTTONS) do
        local bx, by, bw, bh = button_rect(k)
        if x >= bx and x < bx + bw and y >= by and y < by + bh then bt[2](); return end
      end
      local cell = cell_at(x, y)
      if cell then tap_cell(cell) else sel = nil end
    elseif ev.type == 'key' and kit.key_accepted(ev) then
      if ev.key == 'back' and kit.modal() and kit.modal().cancel then kit.modal().cancel()
      elseif ev.key == 'back' then sel = nil end
    end
  end)
  if not ok then ERR = tostring(e) end
  kit.refresh()
  return true
end

function on_load(c) load() end
function on_leave() save() end

if rawget(_G, '__TEST') then
  __TEST.api = { jumps_from = jumps_from, count = count, any_move = any_move, board = board,
                 pegs = function() return pegs end, cell_xy = function(r, c)
                   for _k, cell in ipairs(board().cells) do if cell.r == r and cell.c == c then return cell.x, cell.y end end
                 end }
end
