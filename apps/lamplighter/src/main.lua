-- Lamplighter for XTOS Licorice, API 2.0 (uses tools/gamekit).
--
-- A grid of tiles, each a piece of wire from its centre to some of its sides; one tile is the
-- source, the tiles with one wire are lamps. Tap a tile to turn it a quarter clockwise. Power runs
-- from the source along wires that meet; a lit wire is drawn thick, a lit lamp filled. The puzzle
-- is solved when every tile is lit and no wire ends loose (so every lamp is lit too). Lock mode
-- marks tiles you are sure of, so a stray tap does not turn them.
--
-- The banks (make_bank.py) hold one puzzle a line, every line of a bank the same length: n, the
-- solution and the start as a hex digit a tile (1 north, 2 east, 4 south, 8 west), the source.

local W, H = kit.W, kit.H
local MARGIN = 12
local GRID_Y = 100
local BTN_Y, BTN_H = 742, 50
local INFO_Y = 700
local ORDER = { 'easy', 'medium', 'hard' }
local LABEL = { easy = 'Easy 5x5', medium = 'Medium 7x7', hard = 'Hard 9x9' }
local DIRS = { { 1, -1, 0, 4 }, { 2, 0, 1, 8 }, { 4, 1, 0, 1 }, { 8, 0, -1, 2 } }   -- bit, dr, dc, opposite

local banks = {}
local bank = nil
local idx = 1
local pz = nil            -- { n, sol = {masks}, src }
local tiles = {}          -- the current masks
local locked = {}         -- i -> true; 'h' from a hint
local lock_mode = false
local undo = {}
local moves = 0
local solved = false
local lit = {}            -- i -> true: reached from the source
local done, places = {}, {}
local msg = nil
local ERR = nil
local how_to

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
      found[label] = { file = file, name = label, label = LABEL[label] or label, count = tonumber(count), stride = tonumber(stride) }
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

local function parse(line)
  if type(line) ~= 'string' then return nil end
  local n = tonumber(line:sub(1, 1))
  if not n or n < 3 or #line < 3 + 2 * n * n then return nil end
  local p = { n = n, sol = {}, start = {} }
  for i = 1, n * n do
    p.sol[i] = tonumber(line:sub(1 + i, 1 + i), 16)
    p.start[i] = tonumber(line:sub(1 + n * n + i, 1 + n * n + i), 16)
    if not p.sol[i] or not p.start[i] then return nil end
  end
  p.src = tonumber(line:sub(2 + 2 * n * n, 3 + 2 * n * n)) + 1
  return p
end

------------------------------------------------------------------ rules

local function rot(m) return ((m << 1) | (m >> 3)) & 15 end

-- the tile beyond side bit of tile i, and the bit facing back (nil: the edge of the board)
local function beyond(i, d)
  local n = pz.n
  local r, c = (i - 1) // n, (i - 1) % n
  local rr, cc = r + d[2], c + d[3]
  if rr < 0 or rr >= n or cc < 0 or cc >= n then return nil end
  return rr * n + cc + 1
end

local function count_bits(m) local k = 0; while m > 0 do k = k + (m & 1); m = m >> 1 end; return k end

-- the tiles power reaches from the source, through wires that meet
local function light()
  lit = { [pz.src] = true }
  local queue, head = { pz.src }, 1
  while head <= #queue do
    local i = queue[head]; head = head + 1
    for _k, d in ipairs(DIRS) do
      if tiles[i] & d[1] ~= 0 then
        local j = beyond(i, d)
        if j and tiles[j] & d[4] ~= 0 and not lit[j] then lit[j] = true; queue[#queue + 1] = j end
      end
    end
  end
end

local function loose_ends()
  local k = 0
  for i = 1, pz.n * pz.n do
    for _k, d in ipairs(DIRS) do
      if tiles[i] & d[1] ~= 0 then
        local j = beyond(i, d)
        if not j or tiles[j] & d[4] == 0 then k = k + 1 end
      end
    end
  end
  return k
end

local function lamps()
  local on, all = 0, 0
  for i = 1, pz.n * pz.n do
    if count_bits(tiles[i]) == 1 and i ~= pz.src then
      all = all + 1
      if lit[i] then on = on + 1 end
    end
  end
  return on, all
end

local function check_solved()
  for i = 1, pz.n * pz.n do if not lit[i] then return false end end
  return loose_ends() == 0
end

------------------------------------------------------------------ storage

local function key_of(f) return (f:gsub('[^%w]', '_')) end
local HEX = '0123456789abcdef'

local function save()
  local t = { 'bank=' .. (bank and bank.name or ''), 'idx=' .. idx, 'moves=' .. moves }
  if pz then
    local s, l = {}, {}
    for i = 1, pz.n * pz.n do
      s[i] = HEX:sub(tiles[i] + 1, tiles[i] + 1)
      l[i] = locked[i] == 'h' and 'h' or (locked[i] and 'l' or '.')
    end
    t[#t + 1] = 'cur=' .. table.concat(s)
    t[#t + 1] = 'lock=' .. table.concat(l)
  end
  for f, set in pairs(done) do
    local l = {}
    for k in pairs(set) do l[#l + 1] = k end
    table.sort(l)
    t[#t + 1] = 'done_' .. key_of(f) .. '=' .. table.concat(l, ',')
  end
  for f, k in pairs(places) do t[#t + 1] = 'at_' .. key_of(f) .. '=' .. k end
  kit.write('lamplighter.txt', table.concat(t, '\n'))
end

------------------------------------------------------------------ puzzles

local function open_puzzle(b, n, keep, keep_lock, keep_moves)
  if not b then return end
  n = (n - 1) % b.count + 1
  local p = parse(read_line(b, n))
  if not p then ERR = 'could not read puzzle ' .. n .. ' of ' .. b.file; return end
  bank, idx, pz = b, n, p
  places[b.name] = n
  tiles, locked, undo, moves, msg, lock_mode = {}, {}, {}, 0, nil, false
  for i = 1, p.n * p.n do tiles[i] = p.start[i] end
  if keep and #keep == p.n * p.n then
    for i = 1, #keep do
      local m = tonumber(keep:sub(i, i), 16)
      -- only a turn of the tile itself: a saved state from another puzzle is not taken
      local ok = false
      local x = p.start[i]
      for _k = 1, 4 do if x == m then ok = true end; x = rot(x) end
      if m and ok then tiles[i] = m end
    end
    moves = tonumber(keep_moves) or 0
  end
  if keep_lock and #keep_lock == p.n * p.n then
    for i = 1, #keep_lock do
      local ch = keep_lock:sub(i, i)
      if ch == 'l' then locked[i] = true elseif ch == 'h' then locked[i] = 'h' end
    end
  end
  light()
  solved = check_solved()
  if solved then msg = 'All lit!  Next for another.' end
  pcall(function() ctx:invalidate('full') end)
end

local function load_saved()
  local saved = kit.read('lamplighter.txt')
  local s = kit.kv(saved)
  for _k, b in ipairs(banks) do
    local set = {}
    for k in (s['done_' .. key_of(b.name)] or ''):gmatch('%d+') do set[tonumber(k)] = true end
    done[b.name] = set
    places[b.name] = tonumber(s['at_' .. key_of(b.name)])
  end
  local b = banks[1]
  for _k, x in ipairs(banks) do if x.name == s.bank then b = x end end
  open_puzzle(b, tonumber(s.idx) or 1, s.cur, s.lock, s.moves)
  if not saved or saved == '' then how_to() end
end

------------------------------------------------------------------ play

local function finish()
  light()
  if check_solved() then
    solved = true
    lock_mode = false
    done[bank.name][idx] = true
    local h = 0
    for _i, v in pairs(locked) do if v == 'h' then h = h + 1 end end
    msg = 'All lit in ' .. moves .. ' moves!' .. (h > 0 and (' Hints ' .. h .. '.') or '')
  end
end

local function turn(i)
  if solved then msg = 'All lit!  Next for another.'; return end
  if lock_mode then
    if locked[i] == 'h' then msg = 'That tile came from a hint.'; return end
    locked[i] = (not locked[i]) or nil
    msg = nil
    save()
    return
  end
  if locked[i] then msg = 'Locked: turn Lock on to free it.'; return end
  if tiles[i] == 0 or tiles[i] == 15 then return end
  undo[#undo + 1] = { i, tiles[i] }
  if #undo > 500 then table.remove(undo, 1) end
  tiles[i] = rot(tiles[i])
  moves = moves + 1
  msg = nil
  finish()
  kit.moved()
  save()
end

local function take_back()
  if solved then return end
  local u = table.remove(undo)
  if not u then msg = 'Nothing to undo.'; return end
  tiles[u[1]] = u[2]
  moves = moves + 1
  msg = nil
  light()
  save()
end

-- a tile turned right and locked: next to the lit part if one is wrong there
local function hint()
  if solved then return end
  local n2 = pz.n * pz.n
  local best = nil
  for i = 1, n2 do
    if tiles[i] ~= pz.sol[i] and locked[i] ~= 'h' then
      local near = lit[i]
      if not near then
        for _k, d in ipairs(DIRS) do local j = beyond(i, d); if j and lit[j] then near = true end end
      end
      if near then best = i; break end
      best = best or i
    end
  end
  if not best then return end
  undo[#undo + 1] = { best, tiles[best] }
  tiles[best] = pz.sol[best]
  locked[best] = 'h'
  moves = moves + 1
  msg = 'Hint: that tile is right now (framed).'
  finish()
  save()
end

local function restart()
  for i = 1, pz.n * pz.n do tiles[i] = pz.start[i] end
  locked, undo, moves, solved, msg, lock_mode = {}, {}, 0, false, nil, false
  done[bank.name][idx] = nil
  light()
  save()
end

------------------------------------------------------------------ drawing

local function cell_px() return math.min(88, (W - 2 * MARGIN) // pz.n) end
local function grid_x0() return (W - pz.n * cell_px()) // 2 end
local function grid_y0() return GRID_Y + (INFO_Y - 10 - GRID_Y - pz.n * cell_px()) // 2 end
local function cell_xy(i)
  local C = cell_px()
  return grid_x0() + ((i - 1) % pz.n) * C, grid_y0() + ((i - 1) // pz.n) * C
end

local BUTTONS = { 'Undo', 'Hint', 'Lock', 'More' }
local function button_rect(k)
  local bw = (W - 2 * MARGIN - 3 * 8) // 4
  return MARGIN + (k - 1) * (bw + 8), BTN_Y, bw, BTN_H
end

local BLACK = { fill = true }
local WHITE = { fill = true, color = 0 }

local function draw_tile(gg, i)
  local C = cell_px()
  local x, y = cell_xy(i)
  local cx, cy = x + C // 2, y + C // 2
  local m = tiles[i]
  local on = lit[i]
  local thick = on and math.max(8, C // 7) or math.max(3, C // 22)
  local half = thick // 2
  -- the wires: a bar from the centre to each side that has one
  if m & 1 ~= 0 then gg:rect(cx - half, y, thick, C // 2 + half, BLACK) end
  if m & 4 ~= 0 then gg:rect(cx - half, cy - half, thick, C - C // 2 + half, BLACK) end
  if m & 8 ~= 0 then gg:rect(x, cy - half, C // 2 + half, thick, BLACK) end
  if m & 2 ~= 0 then gg:rect(cx - half, cy - half, C - C // 2 + half, thick, BLACK) end
  if i == pz.src then
    local s = C * 30 // 100
    gg:rect(cx - s, cy - s, 2 * s, 2 * s, BLACK)
    gg:rect(cx - s + 5, cy - s + 5, 2 * s - 10, 2 * s - 10, WHITE)
    gg:rect(cx - s + 9, cy - s + 9, 2 * s - 18, 2 * s - 18, BLACK)
  elseif count_bits(m) == 1 then
    local r = C * 22 // 100
    if on then
      gg:circle(cx, cy, r, BLACK)
    else
      gg:circle(cx, cy, r, WHITE)
      gg:circle(cx, cy, r, { line_width = 3 })
    end
  end
  if locked[i] then gg:rect(x + 4, y + 4, C - 8, C - 8, { line_width = locked[i] == 'h' and 3 or 2 }) end
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    gg:clear(0)
    gg:text(MARGIN, 10, 'Lamplighter', { font = kit.font('large') })
    if msg and not kit.modal() then
      gg:text(MARGIN, 48, kit.short(msg, 44), { font = kit.font('medium') })
    elseif bank then
      local nd = 0
      for _k in pairs(done[bank.name] or {}) do nd = nd + 1 end
      gg:text(MARGIN, 50, kit.short(bank.label .. '   No. ' .. idx .. ' of ' .. bank.count .. '   solved ' .. nd, 48), { font = kit.font('small') })
    end
    gg:line(MARGIN, 80, W - MARGIN, 80, { line_width = 1 })
    if kit.modal() then kit.draw_modal(gg); return end
    if not pz then
      if ERR then gg:text(MARGIN, 120, kit.short(ERR, 46), { font = kit.font('small') }) end
      return
    end
    local C, n = cell_px(), pz.n
    local x0, y0 = grid_x0(), grid_y0()
    -- a dot at each inner cell corner (the panel draws grey as white), and a frame
    for r = 1, n - 1 do
      for k = 1, n - 1 do gg:rect(x0 + k * C - 1, y0 + r * C - 1, 3, 3, BLACK) end
    end
    gg:rect(x0 - 2, y0 - 2, n * C + 4, n * C + 4, { line_width = 2 })
    for i = 1, n * n do draw_tile(gg, i) end
    local on, all = lamps()
    gg:text(MARGIN, INFO_Y, 'Lamps lit ' .. on .. ' of ' .. all .. '   Moves ' .. moves .. (lock_mode and '   LOCK MODE' or ''),
            { font = kit.font('medium') })
    for k, b in ipairs(BUTTONS) do
      local x, y, bw, bh = button_rect(k)
      local label = b
      if k == 3 then label = solved and 'Next' or (lock_mode and 'Lock on' or 'Lock') end
      kit.button(gg, x, y, bw, bh, label, { line_width = (k == 3 and lock_mode) and 4 or 2 })
    end
    if ERR then gg:text(MARGIN, H - 24, kit.short('ERR ' .. ERR, 48), { font = kit.font('small') }) end
  end)
  if not ok then pcall(function() gg:text(8, H - 60, kit.short('draw ERR ' .. tostring(e), 46)) end) end
end

------------------------------------------------------------------ input

function how_to()
  kit.show({ title = 'How to play', lines = {
    'Power runs from the source (the square) along wires that meet. Tap a tile to turn it a quarter clockwise.',
    'Turn the tiles so that every lamp (a round end) is lit: all the wires joined in one network, no loose ends, no loops, nothing running off the board. Lit wires are thick.',
    'Lock: while it is on, a tap frames a tile you are sure of, so it cannot be turned by mistake; tap again to free it.',
    'Every puzzle has one solution, found by reasoning: no guessing.',
  }, rows = { { { 'Close', kit.close } } }, cancel = kit.close })
end

local function next_puzzle() open_puzzle(bank, idx + 1); save() end

local function more()
  local function goto_bank(b) return function() kit.close(); save(); open_puzzle(b, places[b.name] or 1); save() end end
  local lrow = {}
  for _k, b in ipairs(banks) do lrow[#lrow + 1] = { (b.label:match('^%a+')), goto_bank(b), b ~= bank } end
  kit.show({ title = (bank and bank.label or '') .. ': puzzle ' .. idx .. ' of ' .. (bank and bank.count or 0),
             rows = { lrow,
               { { 'Previous', function() kit.close(); open_puzzle(bank, idx - 1); save() end },
                 { 'Next', function() kit.close(); next_puzzle() end } },
               { { 'Start over', function() kit.close(); restart() end }, { 'Rules', how_to } },
               { { 'Close', kit.close } } },
             cancel = kit.close })
end

local function in_rect(x, y, rx, ry, rw, rh) return x >= rx and x < rx + rw and y >= ry and y < ry + rh end

local function tap(x, y)
  if kit.tap_modal(x, y) then return end
  for k = 1, #BUTTONS do
    if in_rect(x, y, button_rect(k)) then
      if k == 1 then take_back()
      elseif k == 2 then hint()
      elseif k == 3 then
        if solved then next_puzzle()
        else lock_mode = not lock_mode; msg = lock_mode and 'Lock: tap tiles to frame them.' or nil end
      else more() end
      return
    end
  end
  if not pz then return end
  local C = cell_px()
  local x0, y0 = grid_x0(), grid_y0()
  if x >= x0 and x < x0 + pz.n * C and y >= y0 and y < y0 + pz.n * C then
    turn(((y - y0) // C) * pz.n + (x - x0) // C + 1)
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
      if ev.key == 'down' then next_puzzle()
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
                 pz = function() return pz end, tiles = function() return tiles end, locked = function() return locked end,
                 lit = function() return lit end, solved = function() return solved end, msg = function() return msg end,
                 moves = function() return moves end, lock_mode = function() return lock_mode end,
                 cell_xy = cell_xy, cell_px = cell_px, open_puzzle = open_puzzle, done = function() return done end,
                 lamps = lamps, loose_ends = loose_ends }
end
