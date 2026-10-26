-- Lights Out for XTOS Licorice, API 2.9 (uses tools/gamekit).
--
-- A 5x5 board of lights. Tapping a square switches it and its four neighbours; switch all of them
-- off. A lit square is a thick ring (no black fill: it ghosts on e-ink). Puzzles are made by
-- pressing random squares from the dark board, so every one can be solved; a solver over GF(2)
-- (Gaussian elimination on 25-bit masks, then the four solutions of the 2-dimensional null space)
-- gives the fewest presses, shown as the target, and drives Hint, which frames one square of an
-- optimal solution from the current position. Undo takes presses back. Saved after every press.

local W, H = kit.W, kit.H
local N = 5
local CELL, GX, GY = 84, 30, 150
local BTN_Y, BTN_H = 676, 60      -- below the board and two lines of text
local LEVELS = { { 'Easy', 4, 3 }, { 'Normal', 8, 6 }, { 'Hard', 13, 10 } }   -- name, presses, fewest at least

local board = 0          -- bit i (0-based, row-major) set = light i on
local moves, par = 0, 0
local history = {}       -- pressed squares, for Undo
local level = 2
local hint = nil         -- square to frame, or nil
local solved_count = 0
local msg = nil
local ERR = nil

------------------------------------------------------------------ rules

local function press_mask(i)
  local r, c = i // N, i % N
  local m = 1 << i
  if r > 0 then m = m | (1 << (i - N)) end
  if r < N - 1 then m = m | (1 << (i + N)) end
  if c > 0 then m = m | (1 << (i - 1)) end
  if c < N - 1 then m = m | (1 << (i + 1)) end
  return m
end

local function popcount(x)
  local n = 0
  while x ~= 0 do x = x & (x - 1); n = n + 1 end
  return n
end

-- the fewest presses that switch every light of b off (a bit mask of squares), or nil
local function solve(b)
  local rows = {}
  for j = 0, N * N - 1 do rows[j + 1] = { a = press_mask(j), b = (b >> j) & 1 } end   -- the press matrix is symmetric
  local piv, r = {}, 1
  for col = 0, N * N - 1 do
    local p
    for k = r, N * N do if (rows[k].a >> col) & 1 == 1 then p = k; break end end
    if p then
      rows[r], rows[p] = rows[p], rows[r]
      for k = 1, N * N do
        if k ~= r and (rows[k].a >> col) & 1 == 1 then
          rows[k].a = rows[k].a ~ rows[r].a
          rows[k].b = rows[k].b ~ rows[r].b
        end
      end
      piv[r] = col
      r = r + 1
    end
  end
  for k = r, N * N do if rows[k].a == 0 and rows[k].b == 1 then return nil end end
  local is_piv = {}
  for k = 1, r - 1 do is_piv[piv[k]] = true end
  local free = {}
  for col = 0, N * N - 1 do if not is_piv[col] then free[#free + 1] = col end end
  local best = nil
  for combo = 0, (1 << #free) - 1 do
    local x = 0
    for f = 1, #free do if (combo >> (f - 1)) & 1 == 1 then x = x | (1 << free[f]) end end
    for k = 1, r - 1 do
      local v = rows[k].b ~ (popcount(rows[k].a & ~(1 << piv[k]) & x) & 1)
      if v == 1 then x = x | (1 << piv[k]) end
    end
    if not best or popcount(x) < popcount(best) then best = x end
  end
  return best
end

------------------------------------------------------------------ storage

local function save()
  kit.write('game.txt', 'board=' .. board .. '\nmoves=' .. moves .. '\npar=' .. par .. '\nlevel=' .. level ..
    '\nsolved=' .. solved_count .. '\nhistory=' .. table.concat(history, ','))
end

local function new_puzzle()
  local lv = LEVELS[level]
  repeat
    local b, pressed = 0, {}
    while #pressed < lv[2] do
      local i = math.random(0, N * N - 1)
      if not pressed[i] then pressed[i] = true; pressed[#pressed + 1] = i; b = b ~ press_mask(i) end
    end
    board = b
    par = popcount(solve(board) or 0)
  until par >= lv[3]
  moves, history, hint, msg = 0, {}, nil, nil
  save()
end

local function load()
  local t = kit.kv(kit.read('game.txt'))
  level = math.max(1, math.min(#LEVELS, tonumber(t.level) or 2))
  solved_count = tonumber(t.solved) or 0
  if not t.board then new_puzzle(); return end
  board, moves, par = tonumber(t.board) or 0, tonumber(t.moves) or 0, tonumber(t.par) or 0
  history = {}
  for v in (t.history or ''):gmatch('%d+') do history[#history + 1] = tonumber(v) end
  if board == 0 then new_puzzle() end
end

------------------------------------------------------------------ actions

local function press(i)
  if board == 0 then return end
  board = board ~ press_mask(i)
  moves = moves + 1
  history[#history + 1] = i
  hint, msg = nil, nil
  kit.moved()
  if board == 0 then
    solved_count = solved_count + 1
    local at = moves <= par
    kit.show({
      title = 'All lights are off!',
      lines = { 'Moves: ' .. moves .. '    Target: ' .. par, at and 'You matched the fewest presses.' or 'It can be done in ' .. par .. '.' },
      rows = { { { 'New', function() kit.close(); new_puzzle() end }, { 'Close', kit.close } } },
      cancel = kit.close,
    })
  end
  save()
end

local function undo()
  local i = table.remove(history)
  if not i then msg = 'Nothing to undo.'; return end
  board = board ~ press_mask(i)
  moves = math.max(0, moves - 1)     -- the press is taken back
  hint = nil
  save()
end

local function show_hint()
  if board == 0 then return end
  local x = solve(board)
  if not x or x == 0 then return end
  for i = 0, N * N - 1 do if (x >> i) & 1 == 1 then hint = i; break end end
  msg = 'Hint: press the framed square.'
end

------------------------------------------------------------------ drawing

local BUTTONS = {
  { function() return 'New' end, function() new_puzzle() end },
  { function() return 'Undo' end, undo },
  { function() return 'Hint' end, show_hint },
  { function() return LEVELS[level][1] end, function()
      level = level % #LEVELS + 1
      msg = LEVELS[level][1] .. ': from the next New puzzle.'
      save()
    end },
}
local function button_rect(k)
  local bw = math.floor((W - 24 - 3 * 8) / 4)
  return 12 + (k - 1) * (bw + 8), BTN_Y, bw, BTN_H
end

local function ring(gg, cx, cy, r)
  for o = 0, 3 do pcall(function() gg:circle(cx, cy, r - o) end) end
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    gg:clear(0)
    gg:text(16, 14, 'Lights Out', { font = kit.font('large') })
    gg:text(16, 58, 'Moves ' .. moves .. '    Target ' .. par .. '    ' .. LEVELS[level][1], { font = kit.font('medium') })
    gg:text(16, 92, 'Solved: ' .. solved_count, { font = kit.font('small') })
    gg:line(0, 130, W, 130)
    if kit.modal() then kit.draw_modal(gg); return end
    for i = 0, N * N - 1 do
      local x, y = GX + (i % N) * CELL, GY + (i // N) * CELL
      gg:rect(x + 3, y + 3, CELL - 6, CELL - 6, { line_width = 2 })
      if (board >> i) & 1 == 1 then
        ring(gg, x + CELL // 2, y + CELL // 2, 28)
        ring(gg, x + CELL // 2, y + CELL // 2, 12)
      end
      if hint == i then                       -- corner brackets
        for _k, d in ipairs({ { 8, 8, 1, 1 }, { CELL - 8, 8, -1, 1 }, { 8, CELL - 8, 1, -1 }, { CELL - 8, CELL - 8, -1, -1 } }) do
          for o = 0, 2 do
            gg:line(x + d[1], y + d[2] + o * d[4], x + d[1] + 16 * d[3], y + d[2] + o * d[4])
            gg:line(x + d[1] + o * d[3], y + d[2], x + d[1] + o * d[3], y + d[2] + 16 * d[4])
          end
        end
      end
    end
    local m = msg or 'Tap a square: it and its neighbours switch. Switch them all off.'
    local lh = kit.line_h('small') + 4
    for k, l in ipairs(kit.wrap(m, 'small', W - 32)) do
      if k <= 2 then gg:text(16, GY + N * CELL + 14 + (k - 1) * lh, l, { font = kit.font('small') }) end
    end
    for k, b in ipairs(BUTTONS) do
      local x, y, bw, bh = button_rect(k)
      kit.button(gg, x, y, bw, bh, b[1]())
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
      for k, b in ipairs(BUTTONS) do
        local bx, by, bw, bh = button_rect(k)
        if x >= bx and x < bx + bw and y >= by and y < by + bh then b[2](); return end
      end
      if x >= GX and x < GX + N * CELL and y >= GY and y < GY + N * CELL then
        press(((y - GY) // CELL) * N + (x - GX) // CELL)
      end
    elseif ev.type == 'key' and kit.key_accepted(ev) and ev.key == 'back' and kit.modal() and kit.modal().cancel then
      kit.modal().cancel()
    end
  end)
  if not ok then ERR = tostring(e) end
  kit.refresh()
  return true
end

function on_load(c)
  math.randomseed(kit.now_ms() or 1)
  load()
end

function on_leave() save() end

if rawget(_G, '__TEST') then
  __TEST.api = { solve = solve, press_mask = press_mask, popcount = popcount,
                 state = function() return board, moves, par, level end,
                 set = function(b, p) board, par, moves, history = b, p, 0, {} end }
end
