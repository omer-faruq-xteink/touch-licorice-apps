-- Nonograms for XTOS Licorice, API 2.9 (uses tools/gamekit; puzzles in src/bank.lua).
--
-- Fill the cells so that each row and column shows its clue: the lengths of its runs of filled
-- cells, in order. Every puzzle is solvable line by line, with no guessing (see make_bank.py).
-- Sizes 5x5, 8x8, 10x10 and 12x12: the clue columns are capped so the cells stay large enough
-- to tap on the 480 px screen.
--
-- Tap a cell to fill it (or, in X mode, to mark it empty); tap again to clear it. A long press
-- always marks an X. The clues of the row and column last tapped are framed, and a line whose
-- cells match its clue has its clue struck through. Every fifth grid line is thicker. Filled cells
-- are squares a little smaller than the cell (less black: it ghosts on e-ink). Undo, Clear (asks),
-- Next, Size; the side buttons go to the previous / next puzzle. Saved after every move, and a
-- puzzle left half done keeps its cells (up to 40 per size).

local W, H = kit.W, kit.H
local BANK = require('bank')
local SIZES = { 5, 8, 10, 12 }
local CAP = { [5] = 3, [8] = 4, [10] = 4, [12] = 5 }       -- most clues a line has in the bank
local BTN_Y, BTN_H = 700, 58
local KEEP_GRIDS = 40      -- in-progress puzzles remembered per size

local size = 10
local idx = {}           -- size -> puzzle number
local solved = {}        -- size -> { [puzzle] = true }
local sol = {}           -- the solution: 1 / 0 per cell, row by row
local cells = {}         -- '#' filled, 'x' marked empty, '.' unknown
local history = {}       -- { i, old } for Undo
local mode = 'fill'
local last = nil         -- the cell last tapped
local msg = nil
local ERR = nil

------------------------------------------------------------------ puzzle

local function decode(hex, n)
  local bits = {}
  for ch in hex:gmatch('%x') do
    local v = tonumber(ch, 16)
    for b = 3, 0, -1 do bits[#bits + 1] = (v >> b) & 1 end
  end
  local out = {}
  for i = 1, n * n do out[i] = bits[i] or 0 end
  return out
end

local function clue_of(get, n)
  local out, run = {}, 0
  for k = 1, n do
    if get(k) then run = run + 1 elseif run > 0 then out[#out + 1] = run; run = 0 end
  end
  if run > 0 then out[#out + 1] = run end
  return out
end

local row_clues, col_clues = {}, {}

local function setup()
  local n = size
  local bank = BANK[n]
  idx[n] = ((idx[n] or 1) - 1) % #bank + 1
  sol = decode(bank[idx[n]], n)
  row_clues, col_clues = {}, {}
  for r = 1, n do row_clues[r] = clue_of(function(k) return sol[(r - 1) * n + k] == 1 end, n) end
  for c = 1, n do col_clues[c] = clue_of(function(k) return sol[(k - 1) * n + c] == 1 end, n) end
end

local function same(a, b)
  if #a ~= #b then return false end
  for k = 1, #a do if a[k] ~= b[k] then return false end end
  return true
end
local function row_done(r)
  local n = size
  return same(clue_of(function(k) return cells[(r - 1) * n + k] == '#' end, n), row_clues[r])
end
local function col_done(c)
  local n = size
  return same(clue_of(function(k) return cells[(k - 1) * n + c] == '#' end, n), col_clues[c])
end
local function is_solved()
  for i = 1, size * size do
    if (cells[i] == '#') ~= (sol[i] == 1) then return false end
  end
  return true
end

------------------------------------------------------------------ layout

local function geometry()
  local n, cap = size, CAP[size]
  local clue_w = cap * 24 + 6
  local clue_h = cap * 22 + 6
  local cell = math.floor(math.min((W - 12 - clue_w) / n, (BTN_Y - 30 - 96 - clue_h) / n))
  local gx = W - 6 - n * cell
  local gy = 96 + clue_h
  return cell, gx, gy, clue_w, clue_h
end

------------------------------------------------------------------ storage

local function save()
  local ix, sv = {}, {}
  for _k, n in ipairs(SIZES) do
    ix[#ix + 1] = n .. ':' .. (idx[n] or 1)
    local list = {}
    for p in pairs(solved[n] or {}) do list[#list + 1] = p end
    table.sort(list)
    sv[#sv + 1] = n .. ':' .. table.concat(list, ',')
  end
  kit.write('state.txt', 'size=' .. size .. '\nidx=' .. table.concat(ix, ';') .. '\nsolved=' .. table.concat(sv, ';') ..
    '\nmode=' .. mode)
  -- in-progress grids of this size, one "puzzle:cells" line each, the current one first; at most
  -- KEEP_GRIDS, solved and empty grids left out
  local cur = table.concat(cells)
  local lines, seen = {}, {}
  local done = solved[size] and solved[size][idx[size]]
  if cur:find('[#x]') and not done then lines[1] = idx[size] .. ':' .. cur end
  seen[idx[size]] = true
  for line in (kit.read('grid' .. size .. '.txt') or ''):gmatch('[^\n]+') do
    local q = tonumber(line:match('^(%d+):'))
    if q and not seen[q] and #lines < KEEP_GRIDS then seen[q] = true; lines[#lines + 1] = line end
  end
  kit.write('grid' .. size .. '.txt', table.concat(lines, '\n'))
end

local function load_grid()
  cells = {}
  for line in (kit.read('grid' .. size .. '.txt') or ''):gmatch('[^\n]+') do
    local q, saved = line:match('^(%d+):([#x%.]+)$')
    if tonumber(q) == idx[size] and #saved == size * size then
      for i = 1, #saved do cells[i] = saved:sub(i, i) end
    end
  end
  if #cells ~= size * size then
    cells = {}
    for i = 1, size * size do cells[i] = '.' end
  end
  history, last = {}, nil
end

local function open_puzzle()
  setup()
  load_grid()
end

------------------------------------------------------------------ actions

local function set_cell(i, v)
  if cells[i] == v then return end
  history[#history + 1] = { i, cells[i] }
  cells[i] = v
  kit.moved()
  msg = nil
  if is_solved() then
    solved[size] = solved[size] or {}
    solved[size][idx[size]] = true
    kit.show({
      title = 'Solved!',
      lines = { size .. 'x' .. size .. ' puzzle ' .. idx[size] .. ' of ' .. #BANK[size] },
      rows = { { { 'Next', function() kit.close(); idx[size] = idx[size] + 1; for k = 1, size * size do cells[k] = '.' end; open_puzzle(); save() end },
                 { 'Close', kit.close } } },
      cancel = kit.close,
    })
  end
  save()
end

local function tap_cell(i, long)
  last = i
  local want = (long or mode == 'x') and 'x' or '#'
  set_cell(i, cells[i] == want and '.' or want)
end

local function undo()
  local h = table.remove(history)
  if not h then msg = 'Nothing to undo.'; return end
  cells[h[1]] = h[2]
  save()
end

local function step(d)
  save()
  idx[size] = (idx[size] or 1) + d
  open_puzzle()
  save()
end

local BUTTONS = {
  { function() return mode == 'fill' and 'Fill' or 'X' end, function()
      mode = mode == 'fill' and 'x' or 'fill'
      msg = mode == 'fill' and 'Taps fill cells.' or 'Taps mark cells as empty (X).'
      save()
    end },
  { function() return 'Undo' end, undo },
  { function() return 'Clear' end, function()
      kit.show({ title = 'Clear this puzzle?', rows = { {
        { 'Clear', function() kit.close(); for k = 1, size * size do cells[k] = '.' end; history = {}; save() end },
        { 'Cancel', kit.close } } }, cancel = kit.close })
    end },
  { function() return 'Next' end, function() step(1) end },
  { function() return size .. 'x' .. size end, function()
      local rows, row = {}, {}
      for _k, n in ipairs(SIZES) do
        local done = 0
        for _p in pairs(solved[n] or {}) do done = done + 1 end
        row[#row + 1] = { n .. 'x' .. n, function() kit.close(); save(); size = n; open_puzzle(); save() end }
        if #row == 2 then rows[#rows + 1] = row; row = {} end
      end
      rows[#rows + 1] = { { 'Cancel', kit.close } }
      kit.show({ title = 'Board size', rows = rows, cancel = kit.close })
    end },
}
local function button_rect(k)
  local bw = math.floor((W - 24 - 4 * 6) / 5)
  return 12 + (k - 1) * (bw + 6), BTN_Y, bw, BTN_H
end

------------------------------------------------------------------ drawing

local function draw_grid(gg)
  local n = size
  local cell, gx, gy, clue_w, clue_h = geometry()
  local small = kit.font('small')
  local lr = last and ((last - 1) // n + 1)
  local lc = last and ((last - 1) % n + 1)
  -- row clues, right-aligned left of the grid; struck through when the row matches
  for r = 1, n do
    local s = table.concat(row_clues[r], ' ')
    local y = gy + (r - 1) * cell + math.floor((cell - kit.line_h('small')) / 2)
    local x = gx - 8 - kit.width(small, s)
    gg:text(x, y, s, { font = small })
    if row_done(r) then gg:line(x - 2, y + 10, gx - 6, y + 10) end
    if r == lr then gg:rect(gx - clue_w, gy + (r - 1) * cell + 1, clue_w - 3, cell - 2, { line_width = 2 }) end
  end
  -- column clues, stacked above the grid, the last one next to it
  for c = 1, n do
    local list = col_clues[c]
    local x0 = gx + (c - 1) * cell
    for k = 1, #list do
      local s = tostring(list[k])
      local y = gy - 6 - (#list - k + 1) * 22
      gg:text(x0 + math.floor((cell - kit.width(small, s)) / 2), y, s, { font = small })
    end
    if col_done(c) then
      local xm = x0 + cell // 2
      gg:line(xm, gy - 6 - #list * 22, xm, gy - 4)
    end
    if c == lc then gg:rect(x0 + 1, gy - clue_h, cell - 2, clue_h - 3, { line_width = 2 }) end
  end
  -- grid lines: every fifth thicker
  for k = 0, n do
    local w = (k % 5 == 0 or k == n) and 3 or 1
    for o = 0, w - 1 do
      gg:line(gx + k * cell + o, gy, gx + k * cell + o, gy + n * cell)
      gg:line(gx, gy + k * cell + o, gx + n * cell, gy + k * cell + o)
    end
  end
  -- cells
  local inset = math.max(3, cell // 6)
  for i = 1, n * n do
    local x, y = gx + ((i - 1) % n) * cell, gy + ((i - 1) // n) * cell
    if cells[i] == '#' then
      gg:rect(x + inset, y + inset, cell - 2 * inset, cell - 2 * inset, { fill = true })
    elseif cells[i] == 'x' then
      local a = inset + 2
      gg:line(x + a, y + a, x + cell - a, y + cell - a)
      gg:line(x + cell - a, y + a, x + a, y + cell - a)
    end
  end
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    gg:clear(0)
    local done = 0
    for _p in pairs(solved[size] or {}) do done = done + 1 end
    gg:text(12, 12, 'Nonograms', { font = kit.font('large') })
    gg:text(12, 52, size .. 'x' .. size .. '  ' .. idx[size] .. '/' .. #BANK[size] .. '    solved ' .. done ..
      (solved[size] and solved[size][idx[size]] and '  (this one too)' or ''), { font = kit.font('small') })
    gg:line(0, 84, W, 84)
    if kit.modal() then kit.draw_modal(gg); return end
    draw_grid(gg)
    local m = msg or 'Tap: fill / clear. Long press: X.'
    gg:text(12, BTN_Y - 30, kit.short(m, 48), { font = kit.font('small') })
    for k, b in ipairs(BUTTONS) do
      local x, y, bw, bh = button_rect(k)
      kit.button(gg, x, y, bw, bh, b[1]())
    end
    if ERR then gg:text(12, H - 30, kit.short('ERR ' .. ERR, 48), { font = kit.font('small') }) end
  end)
  if not ok then pcall(function() gg:text(8, H - 60, kit.short('draw ERR ' .. tostring(e), 46)) end) end
end

------------------------------------------------------------------ input

local suppress_up = false
local long_done = false     -- the long press of this touch has acted

local function cell_at(x, y)
  local cell, gx, gy = geometry()
  local n = size
  if x >= gx and x < gx + n * cell and y >= gy and y < gy + n * cell then
    return ((y - gy) // cell) * n + (x - gx) // cell + 1
  end
  return nil
end

function on_input(c, ev)
  ERR = nil
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    if ev.type == 'pointer' then
      local x, y = ev.x or 0, ev.y or 0
      if ev.phase == 'down' then long_done = false end
      if (ev.gesture == 'long' or ev.phase == 'hold') and not kit.modal() then
        -- the host repeats the hold event while the finger stays down: act once per touch
        if not long_done then
          local i = cell_at(x, y)
          if i then tap_cell(i, true) end
          long_done = true
        end
        suppress_up = ev.phase ~= 'up'
        if ev.phase == 'up' then long_done = false end
        return
      end
      if ev.phase ~= 'up' then return end
      long_done = false
      if suppress_up then suppress_up = false; return end
      if kit.tap_modal(x, y) then return end
      for k, b in ipairs(BUTTONS) do
        local bx, by, bw, bh = button_rect(k)
        if x >= bx and x < bx + bw and y >= by and y < by + bh then b[2](); return end
      end
      local i = cell_at(x, y)
      if i then tap_cell(i, false) end
    elseif ev.type == 'key' and kit.key_accepted(ev) then
      if kit.modal() then
        if ev.key == 'back' and kit.modal().cancel then kit.modal().cancel() end
      elseif ev.key == 'right' or ev.key == 'down' then step(1)
      elseif ev.key == 'left' or ev.key == 'up' then step(-1) end
    end
  end)
  if not ok then ERR = tostring(e) end
  kit.refresh()
  return true
end

function on_load(c)
  local t = kit.kv(kit.read('state.txt'))
  size = tonumber(t.size) or 10
  if not BANK[size] then size = 10 end
  for n, i in (t.idx or ''):gmatch('(%d+):(%d+)') do idx[tonumber(n)] = tonumber(i) end
  for n, list in (t.solved or ''):gmatch('(%d+):([%d,]*)') do
    solved[tonumber(n)] = {}
    for p in list:gmatch('%d+') do solved[tonumber(n)][tonumber(p)] = true end
  end
  mode = t.mode == 'x' and 'x' or 'fill'
  open_puzzle()
  save()
end

function on_leave() save() end

if rawget(_G, '__TEST') then
  __TEST.api = { geometry = geometry, sol = function() return sol end, cells = function() return cells end,
                 size = function() return size end, idx = function() return idx[size] end,
                 row_clues = function() return row_clues end, col_clues = function() return col_clues end }
end
