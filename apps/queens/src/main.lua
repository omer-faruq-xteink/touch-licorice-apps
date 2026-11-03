-- Queens and Star Battle for XTOS Licorice, API 2.0 (uses tools/gamekit).
--
-- The board is split into regions (thick borders). Place one queen (Queens) or two stars (Star
-- Battle) in every row, every column and every region; no two may touch, not even diagonally.
-- The banks (make_bank.py) hold one puzzle a line: a letter a cell naming its region, upper case
-- where the one solution has a piece; every line of a bank the same length, so puzzle N is a seek
-- away. Each puzzle is solved by reasoning, no guessing.
--
-- Tap a cell once for a cross (no piece here), again for a piece, again to clear it. With Dots on,
-- the cells the pieces already rule out get a dot, so they need no crosses. Pieces that break a
-- rule are ringed. Hint removes a wrong piece or cross, else places a right piece. Regions are told
-- apart by borders, not colours: the panel has none.

local W, H = kit.W, kit.H
local GRID_Y, GRID_W = 92, 456
local INFO_Y = 562
local BTN_Y, BTN_H = 684, 52
local COUNT_Y, STATUS_Y = 590, 632
local BORDER = 5                 -- region borders, px
local ORDER = { 'queens-6x6', 'queens-7x7', 'queens-8x8', 'queens-9x9', 'stars-9x9', 'stars-10x10' }
local LEVELS = { ['queens-6x6'] = 'Queens 6x6', ['queens-7x7'] = 'Queens 7x7', ['queens-8x8'] = 'Queens 8x8',
                 ['queens-9x9'] = 'Queens 9x9', ['stars-9x9'] = 'Star Battle 9x9', ['stars-10x10'] = 'Star Battle 10x10' }

local banks = {}
local bank = nil
local idx = 1
local pz = nil           -- { n, k, region = { [cell] = r }, sol = { [cell] = true }, units = { {cells} } }
local mark = {}          -- cell -> 'x' (a cross) or 'q' (a piece)
local hinted = {}        -- cell -> true: a piece from a hint, kept
local undo = {}
local solved = false
local dots = true
local done, places = {}, {}
local msg = nil
local ERR = nil
local how_to             -- the rules box, shown on the first run

------------------------------------------------------------------ data

local function open_text(name)
  local P = ctx.package
  if not P then return nil end
  local ok, r = pcall(function() return P:open_text(name, { max_line_bytes = 512 }) end)
  if ok and r ~= nil and type(r) ~= 'string' then return r end
  return nil
end

local function load_banks()
  banks = {}
  local r = open_text('banks.tsv')
  if not r then return end
  local found = {}
  while true do
    local ok, line = pcall(function() return r:read_line() end)
    if not ok or line == nil then break end
    local file, count, stride, label = line:match('^([^\t]+)\t(%d+)\t(%d+)\t?([^\t]*)')
    if file and tonumber(count) > 0 then
      found[label] = { file = file, name = label, label = LEVELS[label] or label, count = tonumber(count), stride = tonumber(stride) }
    end
  end
  pcall(function() r:close() end)
  for _k, name in ipairs(ORDER) do if found[name] then banks[#banks + 1] = found[name] end end
end

local function read_line(b, n)
  local r = open_text(b.file)
  if not r then return nil end
  local line
  pcall(function()
    if b.stride > 0 then r:seek((n - 1) * b.stride); line = r:read_line()
    else for _k = 1, n do line = r:read_line() end end
  end)
  pcall(function() r:close() end)
  return line
end

-- a bank line -> the puzzle: its regions, solution and units (rows, columns, regions)
local function parse(line)
  if type(line) ~= 'string' then return nil end
  local n = math.floor(math.sqrt(#line) + 0.5)
  if n < 4 or n * n ~= #line or line:find('[^a-zA-Z]') then return nil end
  local p = { n = n, region = {}, sol = {}, units = {} }
  local pieces = 0
  for i = 1, n * n do
    local ch = line:sub(i, i)
    p.region[i] = ch:lower():byte() - 96
    if ch:match('%u') then p.sol[i] = true; pieces = pieces + 1 end
  end
  p.k = pieces // n
  for r = 0, n - 1 do
    local row, col = {}, {}
    for c = 0, n - 1 do row[#row + 1] = r * n + c + 1; col[#col + 1] = c * n + r + 1 end
    p.units[#p.units + 1] = { cells = row, kind = 'row' }
    p.units[#p.units + 1] = { cells = col, kind = 'column' }
  end
  local regs = {}
  for i = 1, n * n do
    local g = p.region[i]
    if not regs[g] then regs[g] = { cells = {}, kind = 'region' }; p.units[#p.units + 1] = regs[g] end
    local cells = regs[g].cells
    cells[#cells + 1] = i
  end
  return p
end

------------------------------------------------------------------ rules

local function piece_word(plural)
  if pz.k == 1 then return plural and 'queens' or 'queen' end
  return plural and 'stars' or 'star'
end

local function around(i, fn)
  local n = pz.n
  local r, c = (i - 1) // n, (i - 1) % n
  for dr = -1, 1 do
    for dc = -1, 1 do
      local rr, cc = r + dr, c + dc
      if (dr ~= 0 or dc ~= 0) and rr >= 0 and rr < n and cc >= 0 and cc < n then fn(rr * n + cc + 1) end
    end
  end
end

-- pieces that break a rule (touching, or too many in a row, column or region), and why
local function conflicts()
  local bad, why = {}, nil
  for i = 1, pz.n * pz.n do
    if mark[i] == 'q' then
      around(i, function(j)
        if mark[j] == 'q' then bad[i] = true; why = why or ('Two ' .. piece_word(true) .. ' touch.') end
      end)
    end
  end
  for _k, u in ipairs(pz.units) do
    local count = 0
    for _j, x in ipairs(u.cells) do if mark[x] == 'q' then count = count + 1 end end
    if count > pz.k then
      for _j, x in ipairs(u.cells) do if mark[x] == 'q' then bad[x] = true end end
      why = why or ('Too many ' .. piece_word(true) .. ' in a ' .. u.kind .. '.')
    end
  end
  return bad, why
end

-- the cells the pieces already rule out: around a piece, or in a full row, column or region
local function ruled_out()
  local out = {}
  for i = 1, pz.n * pz.n do
    if mark[i] == 'q' then around(i, function(j) out[j] = true end) end
  end
  for _k, u in ipairs(pz.units) do
    local count = 0
    for _j, x in ipairs(u.cells) do if mark[x] == 'q' then count = count + 1 end end
    if count >= pz.k then for _j, x in ipairs(u.cells) do out[x] = true end end
  end
  return out
end

local function placed()
  local q = 0
  for i = 1, pz.n * pz.n do if mark[i] == 'q' then q = q + 1 end end
  return q
end

local function check_solved()
  for i = 1, pz.n * pz.n do
    if (mark[i] == 'q') ~= (pz.sol[i] == true) then return false end
  end
  return true
end

------------------------------------------------------------------ storage

local function key_of(f) return (f:gsub('[^%w]', '_')) end

local function mark_string()
  local t = {}
  for i = 1, pz.n * pz.n do
    t[i] = hinted[i] and 'h' or (mark[i] or '.')
  end
  return table.concat(t)
end

local function save()
  local t = { 'bank=' .. (bank and bank.name or ''), 'idx=' .. idx, 'cur=' .. (pz and mark_string() or ''), 'dots=' .. (dots and 1 or 0) }
  for f, set in pairs(done) do
    local l = {}
    for k in pairs(set) do l[#l + 1] = k end
    table.sort(l)
    t[#t + 1] = 'done_' .. key_of(f) .. '=' .. table.concat(l, ',')
  end
  for f, k in pairs(places) do t[#t + 1] = 'at_' .. key_of(f) .. '=' .. k end
  kit.write('queens.txt', table.concat(t, '\n'))
end

------------------------------------------------------------------ puzzles

local function open_puzzle(b, n, keep)
  if not b then return end
  n = (n - 1) % b.count + 1
  local p = parse(read_line(b, n))
  if not p then ERR = 'could not read puzzle ' .. n .. ' of ' .. b.file; return end
  bank, idx, pz = b, n, p
  places[b.name] = n
  mark, hinted, undo, msg = {}, {}, {}, nil
  if keep and #keep == p.n * p.n then
    for i = 1, #keep do
      local ch = keep:sub(i, i)
      if ch == 'x' or ch == 'q' then mark[i] = ch
      elseif ch == 'h' then mark[i] = 'q'; hinted[i] = true end
    end
  end
  solved = check_solved()
  if solved then msg = 'Solved!  Next for another.' end
  pcall(function() ctx:invalidate('full') end)
end

local function load_saved()
  local saved = kit.read('queens.txt')
  local s = kit.kv(saved)
  dots = s.dots ~= '0'
  for _k, b in ipairs(banks) do
    local set = {}
    for k in (s['done_' .. key_of(b.name)] or ''):gmatch('%d+') do set[tonumber(k)] = true end
    done[b.name] = set
    places[b.name] = tonumber(s['at_' .. key_of(b.name)])
  end
  local b = banks[1]
  for _k, x in ipairs(banks) do if x.name == s.bank then b = x end end
  open_puzzle(b, tonumber(s.idx) or 1, s.cur)
  if not saved or saved == '' then how_to() end
end

------------------------------------------------------------------ play

local function finish()
  if check_solved() then
    solved = true
    done[bank.name][idx] = true
    local h = 0
    for _k in pairs(hinted) do h = h + 1 end
    msg = 'Solved!' .. (h > 0 and (' Hints ' .. h .. '.') or '') .. '  Next for another.'
  end
end

local function set_mark(i, v)
  undo[#undo + 1] = { i, mark[i] }
  if #undo > 300 then table.remove(undo, 1) end
  mark[i] = v
end

-- a tap on a cell: nothing -> cross -> piece -> nothing
local function cycle(i)
  if solved then return end
  if hinted[i] then msg = 'That ' .. piece_word() .. ' came from a hint.'; return end
  local v = mark[i]
  set_mark(i, (v == nil and 'x') or (v == 'x' and 'q') or nil)
  local _bad, why = conflicts()
  msg = why
  finish()
  kit.moved()
  save()
end

local function take_back()
  local u = table.remove(undo)
  if not u or solved then msg = solved and msg or 'Nothing to undo.'; return end
  mark[u[1]] = u[2]
  msg = nil
  save()
end

local function hint()
  if solved then return end
  local n2 = pz.n * pz.n
  for i = 1, n2 do
    if mark[i] == 'q' and not pz.sol[i] then
      set_mark(i, nil); msg = 'Hint: that ' .. piece_word() .. ' was wrong.'; save(); return
    end
  end
  for i = 1, n2 do
    if mark[i] == 'x' and pz.sol[i] then
      set_mark(i, nil); msg = 'Hint: a ' .. piece_word() .. ' belongs where that cross was.'; save(); return
    end
  end
  -- a right piece, in the region with the fewest cells still open
  local best, best_open = nil, nil
  local out = ruled_out()
  for _k, u in ipairs(pz.units) do
    if u.kind == 'region' then
      local open_, missing = 0, nil
      for _j, x in ipairs(u.cells) do
        if mark[x] == nil and not out[x] then open_ = open_ + 1 end
        if pz.sol[x] and mark[x] ~= 'q' then missing = missing or x end
      end
      if missing and (not best_open or open_ < best_open) then best, best_open = missing, open_ end
    end
  end
  if not best then return end
  set_mark(best, 'q'); hinted[best] = true
  msg = 'Hint: a ' .. piece_word() .. '.'
  finish()
  save()
end

local function restart()
  mark, hinted, undo, solved, msg = {}, {}, {}, false, nil
  save()
end

------------------------------------------------------------------ geometry and drawing

local function cell_px() return GRID_W // pz.n end
local function grid_x0() return (W - pz.n * cell_px()) // 2 end
local function cell_xy(i)
  local C = cell_px()
  return grid_x0() + ((i - 1) % pz.n) * C, GRID_Y + ((i - 1) // pz.n) * C
end

local BUTTONS = { 'Undo', 'Hint', 'Next', 'More' }
local function button_rect(k)
  local bw = (W - 24 - 3 * 8) // 4
  return 12 + (k - 1) * (bw + 8), BTN_Y, bw, BTN_H
end

local BLACK = { fill = true }

-- a crown: a band and three points
local function queen(gg, cx, cy, s)
  gg:polygon({ cx - s, cy + s * 6 // 10, cx - s, cy - s * 5 // 10, cx - s // 2, cy, cx, cy - s * 8 // 10,
               cx + s // 2, cy, cx + s, cy - s * 5 // 10, cx + s, cy + s * 6 // 10 }, BLACK)
end

-- a five-pointed star
local STAR = {}
for k = 0, 9 do
  local a = -math.pi / 2 + k * math.pi / 5
  local r = (k % 2 == 0) and 1.0 or 0.42
  STAR[#STAR + 1] = { math.cos(a) * r, math.sin(a) * r }
end
local function star(gg, cx, cy, s)
  local pts = {}
  for _k, p in ipairs(STAR) do
    pts[#pts + 1] = cx + math.floor(p[1] * s + 0.5)
    pts[#pts + 1] = cy + math.floor(p[2] * s + 0.5)
  end
  gg:polygon(pts, BLACK)
end

local function draw_grid(gg)
  local n, C = pz.n, cell_px()
  local x0, y0 = grid_x0(), GRID_Y
  local side = n * C
  -- thin cell lines
  for k = 1, n - 1 do
    gg:line(x0 + k * C, y0, x0 + k * C, y0 + side, { line_width = 1 })
    gg:line(x0, y0 + k * C, x0 + side, y0 + k * C, { line_width = 1 })
  end
  -- region borders, joined into runs: the edge below a row of cells, then right of a column
  local half = BORDER // 2
  for r = 0, n - 2 do
    local start = nil
    for c = 0, n do
      local diff = c < n and pz.region[r * n + c + 1] ~= pz.region[(r + 1) * n + c + 1]
      if diff and not start then start = c end
      if not diff and start then
        gg:rect(x0 + start * C - half, y0 + (r + 1) * C - half, (c - start) * C + BORDER, BORDER, BLACK)
        start = nil
      end
    end
  end
  for c = 0, n - 2 do
    local start = nil
    for r = 0, n do
      local diff = r < n and pz.region[r * n + c + 1] ~= pz.region[r * n + c + 2]
      if diff and not start then start = r end
      if not diff and start then
        gg:rect(x0 + (c + 1) * C - half, y0 + start * C - half, BORDER, (r - start) * C + BORDER, BLACK)
        start = nil
      end
    end
  end
  gg:rect(x0 - half, y0 - half, side + BORDER, side + BORDER, { line_width = BORDER })
  -- the marks
  local bad = conflicts()
  local out = dots and ruled_out() or {}
  local s = C * 32 // 100
  for i = 1, n * n do
    local x, y = cell_xy(i)
    local cx, cy = x + C // 2, y + C // 2
    if mark[i] == 'q' then
      if pz.k == 1 then queen(gg, cx, cy + s // 10, s) else star(gg, cx, cy, s + 2) end
      if hinted[i] then gg:rect(cx - s, y + C - 9, 2 * s, 2, BLACK) end
      if bad[i] then gg:circle(cx, cy, C * 44 // 100, { line_width = 3 }) end
    elseif mark[i] == 'x' then
      local d = C // 6
      gg:line(cx - d, cy - d, cx + d, cy + d, { line_width = 2 })
      gg:line(cx + d, cy - d, cx - d, cy + d, { line_width = 2 })
    elseif out[i] then
      gg:circle(cx, cy, math.max(2, C // 16), BLACK)
    end
  end
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    gg:clear(0)
    gg:text(12, 12, (bank and bank.name:match('^stars')) and 'Star Battle' or 'Queens', { font = kit.font('large') })
    if bank then
      local nd = 0
      for _k in pairs(done[bank.name] or {}) do nd = nd + 1 end
      gg:text(12, 52, kit.short(bank.label .. '   No. ' .. idx .. ' of ' .. bank.count .. '   solved ' .. nd, 46), { font = kit.font('small') })
    end
    if kit.modal() then kit.draw_modal(gg); return end
    if not pz then
      if ERR then gg:text(12, 120, kit.short(ERR, 46), { font = kit.font('small') }) end
      return
    end
    draw_grid(gg)
    local small = kit.font('small')
    local rule = pz.k == 1 and 'One queen' or 'Two stars'
    gg:text(12, INFO_Y, rule .. ' per row, column, region.', { font = small })
    gg:text(12, COUNT_Y, 'None touch.   ' .. placed() .. ' of ' .. pz.n * pz.k .. ' ' .. piece_word(true) .. ' placed', { font = small })
    for k, b in ipairs(BUTTONS) do
      local x, y, bw, bh = button_rect(k)
      kit.button(gg, x, y, bw, bh, b)
    end
    if msg then gg:text(12, STATUS_Y, kit.short(msg, 46), { font = kit.font('medium') }) end
    if ERR then gg:text(12, H - 24, kit.short('ERR ' .. ERR, 48), { font = small }) end
  end)
  if not ok then pcall(function() gg:text(8, H - 60, kit.short('draw ERR ' .. tostring(e), 46)) end) end
end

------------------------------------------------------------------ input

function how_to()
  kit.show({ title = 'How to play', lines = {
    'Put one queen in every row, every column and every region (the areas inside the thick borders). Star Battle: two stars in each. No two may touch, not even diagonally.',
    'Tap a cell once for a cross (nothing here), twice for a queen or star, a third time to clear it. With Dots on, cells already ruled out get a dot. A ringed piece breaks a rule.',
    'Every puzzle has one solution, found by reasoning: no guessing.',
  }, rows = { { { 'Close', kit.close } } }, cancel = kit.close })
end

local function more()
  local function goto_bank(b) return function() kit.close(); save(); open_puzzle(b, places[b.name] or 1); save() end end
  local qrow, srow = {}, {}
  for _k, b in ipairs(banks) do
    local size = b.name:match('%d+x%d+') or b.label
    if b.name:match('^stars') then srow[#srow + 1] = { 'Stars ' .. size, goto_bank(b), b ~= bank }
    else qrow[#qrow + 1] = { size, goto_bank(b), b ~= bank } end
  end
  local rows = {}
  if #qrow > 0 then rows[#rows + 1] = qrow end
  if #srow > 0 then rows[#rows + 1] = srow end
  rows[#rows + 1] = { { 'Previous', function() kit.close(); open_puzzle(bank, idx - 1); save() end },
                      { 'Start over', function() kit.close(); restart() end } }
  rows[#rows + 1] = { { dots and 'Dots: on' or 'Dots: off', function() dots = not dots; kit.close(); save() end },
                      { 'Rules', how_to }, { 'Close', kit.close } }
  kit.show({ title = 'Queens', lines = { 'Queens sizes, then Star Battle (two stars). ' .. (bank and bank.label or '') .. ': puzzle ' .. idx .. ' of ' .. (bank and bank.count or 0) .. '.' },
             rows = rows, cancel = kit.close })
end

local function in_rect(x, y, rx, ry, rw, rh) return x >= rx and x < rx + rw and y >= ry and y < ry + rh end

local function tap(x, y)
  if kit.tap_modal(x, y) then return end
  for k = 1, #BUTTONS do
    local bx, by, bw, bh = button_rect(k)
    if in_rect(x, y, bx, by, bw, bh) then
      if k == 1 then take_back()
      elseif k == 2 then hint()
      elseif k == 3 then open_puzzle(bank, idx + 1); save()
      else more() end
      return
    end
  end
  if not pz then return end
  local C = cell_px()
  local x0 = grid_x0()
  if x >= x0 and x < x0 + pz.n * C and y >= GRID_Y and y < GRID_Y + pz.n * C then
    cycle(((y - GRID_Y) // C) * pz.n + (x - x0) // C + 1)
  end
end

function on_input(c, ev)
  ERR = nil
  local handled = true
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    if ev.type == 'pointer' and ev.phase == 'up' then
      tap(ev.x or 0, ev.y or 0)
    elseif ev.type == 'key' and ev.key == 'back' then
      -- Back acts on its release: closes a box, else leaves it to the host (which offers to exit)
      if ev.phase ~= 'up' and ev.phase ~= nil then return end
      if kit.modal() then
        if kit.modal().cancel then kit.modal().cancel() end
      else handled = false end
    elseif ev.type == 'key' and kit.key_accepted(ev) and not kit.modal() then
      if ev.key == 'down' then open_puzzle(bank, idx + 1); save()
      elseif ev.key == 'up' then open_puzzle(bank, idx - 1); save() end
    end
  end)
  if not ok then ERR = tostring(e) end
  kit.refresh()
  return handled
end

function on_load(c)
  local ok, e = pcall(function()
    load_banks()
    if #banks == 0 then ERR = 'no puzzles in the package'; return end
    load_saved()
  end)
  if not ok then ERR = tostring(e) end
end
function on_leave() pcall(save) end

if rawget(_G, '__TEST') then
  __TEST.api = { banks = function() return banks end, bank = function() return bank end, idx = function() return idx end,
                 pz = function() return pz end, mark = function() return mark end, solved = function() return solved end,
                 msg = function() return msg end, dots = function() return dots end, cell_xy = cell_xy, cell_px = cell_px,
                 conflicts = conflicts, ruled_out = ruled_out, open_puzzle = open_puzzle, done = function() return done end }
end
