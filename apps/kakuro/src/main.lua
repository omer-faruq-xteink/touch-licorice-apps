-- Kakuro (cross sums) for XTOS Licorice, API 2.0 (uses tools/gamekit).
--
-- Fill the white cells with digits 1 to 9: each run of white cells, across or down, adds up to
-- the clue at its start, and no digit is used twice in a run. The banks (make_bank.py) hold the
-- solution of each puzzle, one a line ('#' a block, '1'..'9' a white cell), every line of a bank
-- the same length, so puzzle N is a seek away; the clues are worked out from it. Each puzzle has
-- one solution, reached by reasoning about the runs.
--
-- Tap a cell, then a digit. The status line shows the selected cell's runs and the ways they can
-- be made ("16 in 2: 79"). A digit repeated in a run, or a run that is full and adds up wrong, is
-- crossed. Hint fills the selected cell (or the first open one). Clue cells are drawn with a
-- double border and a diagonal, not filled black: large black areas ghost on e-ink; empty
-- blocks open to the edge are left blank.

local W, H = kit.W, kit.H
local GRID_Y, GRID_W = 86, 456
local INFO_Y = 552
local PAD_Y, PAD_H, PAD_GAP = 612, 58, 5
local BTN_Y, BTN_H = 684, 52
local STATUS_Y = 748
local LEVELS = { ['6x6-easy'] = 'Easy 6x6', ['7x7-medium'] = 'Medium 7x7', ['8x8-hard'] = 'Hard 8x8' }

local banks = {}
local bank = nil
local idx = 1
local pz = nil           -- { n, sol = { [cell] = digit }, white = { cells }, across, down = { [cell] = run }, runs, clue = { [cell] = { a, d } } }
local entry = {}         -- cell -> digit entered
local hinted = {}        -- cell -> true
local sel = nil
local solved = false
local done, places = {}, {}
local msg = nil
local ERR = nil

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
  while true do
    local ok, line = pcall(function() return r:read_line() end)
    if not ok or line == nil then break end
    local file, count, stride, label = line:match('^([^\t]+)\t(%d+)\t(%d+)\t?([^\t]*)')
    if file and tonumber(count) > 0 then
      banks[#banks + 1] = { file = file, label = LEVELS[label] or label, count = tonumber(count), stride = tonumber(stride) }
    end
  end
  pcall(function() r:close() end)
  table.sort(banks, function(a, b) return (tonumber(a.file:match('^%d+')) or 0) < (tonumber(b.file:match('^%d+')) or 0) end)
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

-- a bank line -> the puzzle with its runs and clues
local function parse(line)
  if type(line) ~= 'string' then return nil end
  local n = math.floor(math.sqrt(#line) + 0.5)
  if n < 4 or n * n ~= #line or line:find('[^#1-9]') then return nil end
  local p = { n = n, sol = {}, white = {}, across = {}, down = {}, runs = {}, clue = {} }
  for i = 1, n * n do
    local ch = line:sub(i, i)
    if ch ~= '#' then p.sol[i] = tonumber(ch); p.white[#p.white + 1] = i end
  end
  for i = 1, n * n do
    if not p.sol[i] then
      local r, c = (i - 1) // n, (i - 1) % n
      for _d, dir in ipairs({ { 0, 1, 'across', 'a' }, { 1, 0, 'down', 'd' } }) do
        local cells, rr, cc = {}, r + dir[1], c + dir[2]
        while rr < n and cc < n and p.sol[rr * n + cc + 1] do
          cells[#cells + 1] = rr * n + cc + 1
          rr, cc = rr + dir[1], cc + dir[2]
        end
        if #cells >= 2 then
          local s = 0
          for _k, x in ipairs(cells) do s = s + p.sol[x] end
          local run = { cells = cells, sum = s, dir = dir[3] }
          p.runs[#p.runs + 1] = run
          for _k, x in ipairs(cells) do p[dir[3]][x] = run end
          p.clue[i] = p.clue[i] or {}
          p.clue[i][dir[4]] = s
        end
      end
    end
  end
  -- the empty blocks reached from the edge of the board through other empty blocks are not
  -- drawn, so the puzzle stands on blank paper; an enclosed one keeps its box, or it would look
  -- like a white cell to fill
  p.outside = {}
  local stack = {}
  for i = 1, n * n do
    local r, c = (i - 1) // n, (i - 1) % n
    if (r == 0 or c == 0 or r == n - 1 or c == n - 1) and not p.sol[i] and not p.clue[i] then
      p.outside[i] = true; stack[#stack + 1] = i
    end
  end
  while #stack > 0 do
    local i = table.remove(stack)
    local r, c = (i - 1) // n, (i - 1) % n
    for _k, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
      local rr, cc = r + d[1], c + d[2]
      local j = rr * n + cc + 1
      if rr >= 0 and rr < n and cc >= 0 and cc < n and not p.sol[j] and not p.clue[j] and not p.outside[j] then
        p.outside[j] = true; stack[#stack + 1] = j
      end
    end
  end
  return p
end

------------------------------------------------------------------ rules

-- the ways to make a run: digit strings like "79" for 16 in 2
local combo_cache = {}
local function combos(len, sum)
  local key = len .. ':' .. sum
  if combo_cache[key] then return combo_cache[key] end
  local out = {}
  local function rec(start, left, total, acc)
    if left == 0 then
      if total == sum then out[#out + 1] = acc end
      return
    end
    for d = start, 9 do
      if total + d > sum then break end
      rec(d + 1, left - 1, total + d, acc .. d)
    end
  end
  rec(1, len, 0, '')
  combo_cache[key] = out
  return out
end

-- cells that break a rule: a digit twice in a run, or a full run that adds up wrong
local function conflicts()
  local bad = {}
  for _k, run in ipairs(pz.runs) do
    local seen, total, full = {}, 0, true
    for _j, x in ipairs(run.cells) do
      local v = entry[x]
      if v then
        if seen[v] then bad[x] = true; bad[seen[v]] = true else seen[v] = x end
        total = total + v
      else
        full = false
      end
    end
    if (full and total ~= run.sum) or total > run.sum then
      for _j, x in ipairs(run.cells) do if entry[x] then bad[x] = true end end
    end
  end
  return bad
end

local function check_solved()
  for _k, x in ipairs(pz.white) do if entry[x] ~= pz.sol[x] then return false end end
  return true
end

------------------------------------------------------------------ storage

local function key_of(f) return (f:gsub('[^%w]', '_')) end

local function entry_string()
  local t = {}
  for i = 1, pz.n * pz.n do
    if not pz.sol[i] then t[i] = '#'
    else t[i] = entry[i] and (hinted[i] and string.char(96 + entry[i]) or tostring(entry[i])) or '0' end
  end
  return table.concat(t)
end

local function save()
  local t = { 'bank=' .. (bank and bank.file or ''), 'idx=' .. idx, 'cur=' .. (pz and entry_string() or '') }
  for f, set in pairs(done) do
    local l = {}
    for k in pairs(set) do l[#l + 1] = k end
    table.sort(l)
    t[#t + 1] = 'done_' .. key_of(f) .. '=' .. table.concat(l, ',')
  end
  for f, k in pairs(places) do t[#t + 1] = 'at_' .. key_of(f) .. '=' .. k end
  kit.write('kakuro.txt', table.concat(t, '\n'))
end

------------------------------------------------------------------ puzzles

local function first_open()
  for _k, x in ipairs(pz.white) do if not entry[x] then return x end end
  return pz.white[1]
end

local function open_puzzle(b, n, keep)
  if not b then return end
  n = (n - 1) % b.count + 1
  local p = parse(read_line(b, n))
  if not p then ERR = 'could not read puzzle ' .. n .. ' of ' .. b.file; return end
  bank, idx, pz = b, n, p
  places[b.file] = n
  entry, hinted, msg = {}, {}, nil
  if keep and #keep == p.n * p.n then
    for i = 1, #keep do
      local ch = keep:sub(i, i)
      if p.sol[i] and ch:match('%d') and ch ~= '0' then entry[i] = tonumber(ch)
      elseif p.sol[i] and ch:match('%l') then entry[i] = ch:byte() - 96; hinted[i] = true end
    end
  end
  solved = check_solved()
  sel = (not solved) and first_open() or nil
  if solved then msg = 'Solved!  Next for another.' end
  pcall(function() ctx:invalidate('full') end)
end

local function load_saved()
  local s = kit.kv(kit.read('kakuro.txt'))
  for _k, b in ipairs(banks) do
    local set = {}
    for k in (s['done_' .. key_of(b.file)] or ''):gmatch('%d+') do set[tonumber(k)] = true end
    done[b.file] = set
    places[b.file] = tonumber(s['at_' .. key_of(b.file)])
  end
  local b = banks[1]
  for _k, x in ipairs(banks) do if x.file == s.bank then b = x end end
  open_puzzle(b, tonumber(s.idx) or 1, s.cur)
end

------------------------------------------------------------------ play

local function finish()
  if check_solved() then
    solved, sel = true, nil
    done[bank.file][idx] = true
    local h = 0
    for _k in pairs(hinted) do h = h + 1 end
    msg = 'Solved!' .. (h > 0 and (' Hints ' .. h .. '.') or '') .. '  Next for another.'
  end
end

local function put(d)
  if solved or not sel then return end
  if hinted[sel] then msg = 'That digit came from a hint.'; return end
  entry[sel] = d
  msg = nil
  finish()
  kit.moved()
  save()
end

local function hint()
  if solved then return end
  local x = (sel and entry[sel] ~= pz.sol[sel]) and sel or nil
  if not x then
    for _k, c in ipairs(pz.white) do if entry[c] ~= pz.sol[c] then x = c; break end end
  end
  if not x then return end
  entry[x], hinted[x], sel = pz.sol[x], true, x
  msg = 'Hint: ' .. pz.sol[x]
  finish()
  save()
end

local function step_sel(d)
  if not sel then sel = first_open(); return end
  for k, x in ipairs(pz.white) do
    if x == sel then sel = pz.white[(k - 1 + d) % #pz.white + 1]; return end
  end
end

------------------------------------------------------------------ geometry and drawing

local function cell_px() return GRID_W // pz.n end
local function cell_xy(i)
  local C = cell_px()
  local x0 = (W - pz.n * C) // 2
  return x0 + ((i - 1) % pz.n) * C, GRID_Y + ((i - 1) // pz.n) * C
end

local function pad_rect(d)
  local kw = (W - 24 - 8 * PAD_GAP) // 9
  return 12 + (d - 1) * (kw + PAD_GAP), PAD_Y, kw, PAD_H
end
local BUTTONS = { 'Erase', 'Hint', 'Next', 'More' }
local function button_rect(k)
  local bw = (W - 24 - 3 * 8) // 4
  return 12 + (k - 1) * (bw + 8), BTN_Y, bw, BTN_H
end

local function run_info(run)
  if not run then return nil end
  local cs = combos(#run.cells, run.sum)
  local s = (run.dir == 'across' and 'Across ' or 'Down ') .. run.sum .. ' in ' .. #run.cells .. ': ' .. table.concat(cs, ' ')
  return s
end

local function draw_grid(gg)
  local C = cell_px()
  local n = pz.n
  local big, small = kit.font(C >= 60 and 'large' or 'medium'), kit.font('small')
  local bad = conflicts()
  for i = 1, n * n do
    local x, y = cell_xy(i)
    if pz.sol[i] then
      gg:rect(x, y, C + 1, C + 1, { line_width = 1 })
      if i == sel then gg:rect(x + 3, y + 3, C - 5, C - 5, { line_width = 3 }) end
      local v = entry[i]
      if v then
        local s = tostring(v)
        local fname = C >= 60 and 'large' or 'medium'
        gg:text(x + (C - kit.width(big, s)) // 2, y + (C - kit.line_h(fname)) // 2, s, { font = big })
        if hinted[i] then gg:line(x + C // 2 - 8, y + C - 9, x + C // 2 + 8, y + C - 9, { line_width = 1 }) end
        if bad[i] then
          gg:line(x + C - 16, y + 5, x + C - 6, y + 15, { line_width = 2 })
          gg:line(x + C - 6, y + 5, x + C - 16, y + 15, { line_width = 2 })
        end
      end
    elseif not pz.outside[i] then
      gg:rect(x, y, C + 1, C + 1, { line_width = 2 })
      gg:rect(x + 4, y + 4, C - 7, C - 7, { line_width = 1 })
      local cl = pz.clue[i]
      if cl then
        gg:line(x + 4, y + 4, x + C - 3, y + C - 3, { line_width = 1 })
        if cl.a then local s = tostring(cl.a); gg:text(x + C - 7 - kit.width(small, s), y + 7, s, { font = small }) end
        if cl.d then gg:text(x + 8, y + C - 8 - kit.line_h('small'), tostring(cl.d), { font = small }) end
      end
    end
  end
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    gg:clear(0)
    gg:text(12, 12, 'Kakuro', { font = kit.font('large') })
    if bank then
      local nd = 0
      for _k in pairs(done[bank.file] or {}) do nd = nd + 1 end
      gg:text(12, 52, kit.short(bank.label .. '   No. ' .. idx .. ' of ' .. bank.count .. '   solved ' .. nd, 46), { font = kit.font('small') })
    end
    if kit.modal() then kit.draw_modal(gg); return end
    if not pz then
      if ERR then gg:text(12, 120, kit.short(ERR, 46), { font = kit.font('small') }) end
      return
    end
    draw_grid(gg)
    local small = kit.font('small')
    if sel then
      local a, d = run_info(pz.across[sel]), run_info(pz.down[sel])
      if a then gg:text(12, INFO_Y, kit.short(a, 46), { font = small }) end
      if d then gg:text(12, INFO_Y + 26, kit.short(d, 46), { font = small }) end
    end
    local med = kit.font('large')
    for d = 1, 9 do
      local x, y, kw, kh = pad_rect(d)
      gg:rect(x, y, kw, kh, { line_width = 2 })
      gg:text(x + (kw - kit.width(med, tostring(d))) // 2, y + (kh - kit.line_h('large')) // 2, tostring(d), { font = med })
    end
    for k, b in ipairs(BUTTONS) do
      local x, y, bw, bh = button_rect(k)
      kit.button(gg, x, y, bw, bh, b)
    end
    if msg then gg:text(12, STATUS_Y, kit.short(msg, 46), { font = small }) end
    if ERR then gg:text(12, H - 24, kit.short('ERR ' .. ERR, 48), { font = small }) end
  end)
  if not ok then pcall(function() gg:text(8, H - 60, kit.short('draw ERR ' .. tostring(e), 46)) end) end
end

------------------------------------------------------------------ input

local function how_to()
  kit.show({ title = 'How to play', lines = {
    'Fill the white cells with digits 1 to 9. Each run of white cells, across or down, adds up to the clue at its start (across top right, down bottom left), with no digit twice.',
    'Tap a cell, then a digit. Below the grid are its runs and the ways to make them. Crossed digits break a rule. Hint fills a cell.',
  }, rows = { { { 'Close', kit.close } } }, cancel = kit.close })
end

local function restart()
  entry, hinted, solved, msg = {}, {}, false, nil
  sel = first_open()
  save()
end

local function more()
  local row = {}
  for _k, b in ipairs(banks) do
    row[#row + 1] = { b.label:match('^%S+'), function() kit.close(); save(); open_puzzle(b, places[b.file] or 1); save() end, b ~= bank }
  end
  kit.show({ title = 'Kakuro', lines = { (bank and bank.label or '') .. ': puzzle ' .. idx .. ' of ' .. (bank and bank.count or 0) .. '.' },
             rows = { row,
                      { { 'Previous', function() kit.close(); open_puzzle(bank, idx - 1); save() end },
                        { 'Start over', function() kit.close(); restart() end } },
                      { { 'How to play', how_to }, { 'Close', kit.close } } },
             cancel = kit.close })
end

local function in_rect(x, y, rx, ry, rw, rh) return x >= rx and x < rx + rw and y >= ry and y < ry + rh end

local function tap(x, y)
  if kit.tap_modal(x, y) then return end
  for k = 1, #BUTTONS do
    local bx, by, bw, bh = button_rect(k)
    if in_rect(x, y, bx, by, bw, bh) then
      if k == 1 then if sel and not hinted[sel] and not solved then entry[sel] = nil; msg = nil; save() end
      elseif k == 2 then hint()
      elseif k == 3 then open_puzzle(bank, idx + 1); save()
      else more() end
      return
    end
  end
  if not pz then return end
  for d = 1, 9 do
    if in_rect(x, y, pad_rect(d)) then
      if sel then put(d) else msg = 'Tap a cell first.' end
      return
    end
  end
  local C = cell_px()
  local x0 = (W - pz.n * C) // 2
  if x >= x0 and x < x0 + pz.n * C and y >= GRID_Y and y < GRID_Y + pz.n * C then
    local i = ((y - GRID_Y) // C) * pz.n + (x - x0) // C + 1
    if pz.sol[i] and not solved then sel = i; msg = nil end
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
      -- Back acts on its release (the host reads only the up event's answer): it closes a box;
      -- on the board it is left to the host, which offers to exit
      if ev.phase ~= 'up' and ev.phase ~= nil then return end
      if kit.modal() then
        if kit.modal().cancel then kit.modal().cancel() end
      else handled = false end
    elseif ev.type == 'key' and kit.key_accepted(ev) then
      if kit.modal() then
        -- other keys do nothing while a box is open
      elseif pz and ev.key == 'right' then step_sel(1)
      elseif pz and ev.key == 'left' then step_sel(-1)
      elseif ev.key == 'down' then open_puzzle(bank, idx + 1); save()
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
                 pz = function() return pz end, entry = function() return entry end, sel = function() return sel end,
                 solved = function() return solved end, msg = function() return msg end, cell_xy = cell_xy,
                 pad_rect = pad_rect, cell_px = cell_px, combos = combos, conflicts = conflicts, open_puzzle = open_puzzle,
                 done = function() return done end }
end
