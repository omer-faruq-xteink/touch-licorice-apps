-- Case Files for XTOS Licorice, API 2.0 (uses tools/gamekit): logic-grid mysteries.
--
-- A case: some people, and for each of them one item of every group (a floor, an arrival time, a
-- lost item...). The clues settle who has what; the grids, one for each pair of groups, are where
-- the player works it out: a tap puts a cross (not these two), a second a tick (these two go
-- together), a third clears the cell. A tick dots the rest of its row and column. The case is
-- closed when every person has the right tick in each of the people's grids.
--
-- The banks (make_bank.py) hold one case a line, every line of a bank the same length, so case N
-- is a seek away; src/case.lua reads a line and words its clues, src/themes.lua holds the themes.

local Case = require('case')

local W, H = kit.W, kit.H
local MARGIN = 12
local CLUE_Y = 76
local TAB_H = 48
local BTN_Y, BTN_H = 748, 46
local GRID_BOTTOM = 736
local function cell_size(n) return n == 5 and 52 or 58 end
local HEAD_H, HEAD_H2 = 30, 48   -- the column heads: one row, or two when they do not fit a cell
local ORDER = { 'easy', 'medium', 'hard' }
local LABEL = { easy = 'Easy', medium = 'Medium', hard = 'Hard' }

local banks = {}
local bank = nil
local idx = 1
local pz = nil            -- the case (Case.parse)
local pairs_ = {}         -- the grids: { g, h }
local tab = 1
local marks = {}          -- marks[pair][cell] = 'x' (cross), 'v' (tick) or 'h' (a tick from a hint)
local struck = {}         -- clue i -> true: crossed out by the player
local page = 1
local undo = {}
local solved = false
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

------------------------------------------------------------------ marks and rules

local function cell(a, b) return (a - 1) * pz.n + b end

local function mark_at(pi, a, b) return marks[pi][cell(a, b)] end
local function is_tick(v) return v == 'v' or v == 'h' end

-- is cell (a, b) of grid pi right as a tick?
local function belongs(pi, a, b)
  local g, h = pairs_[pi][1], pairs_[pi][2]
  return Case.same(pz, g, a, h, b)
end

-- ticks two to a row or column, and why
local function conflicts(pi)
  local bad, why = {}, nil
  local n = pz.n
  for a = 1, n do
    local c = 0
    for b = 1, n do if is_tick(mark_at(pi, a, b)) then c = c + 1 end end
    if c > 1 then
      for b = 1, n do if is_tick(mark_at(pi, a, b)) then bad[cell(a, b)] = true end end
      why = why or 'Two ticks in one row.'
    end
  end
  for b = 1, n do
    local c = 0
    for a = 1, n do if is_tick(mark_at(pi, a, b)) then c = c + 1 end end
    if c > 1 then
      for a = 1, n do if is_tick(mark_at(pi, a, b)) then bad[cell(a, b)] = true end end
      why = why or 'Two ticks in one column.'
    end
  end
  return bad, why
end

-- the open cells a tick in their row or column rules out
local function ruled_out(pi)
  local out, n = {}, pz.n
  for a = 1, n do
    for b = 1, n do
      if is_tick(mark_at(pi, a, b)) then
        for j = 1, n do out[cell(a, j)] = true; out[cell(j, b)] = true end
      end
    end
  end
  return out
end

local function wrong_marks()
  local list = {}
  for pi = 1, #pairs_ do
    for a = 1, pz.n do
      for b = 1, pz.n do
        local v = mark_at(pi, a, b)
        if v and is_tick(v) ~= belongs(pi, a, b) then list[#list + 1] = { pi, a, b, v } end
      end
    end
  end
  return list
end

local function check_solved()
  for pi, pr in ipairs(pairs_) do
    if pr[1] == 1 then
      local ticks = 0
      for a = 1, pz.n do
        for b = 1, pz.n do
          if is_tick(mark_at(pi, a, b)) then
            if not belongs(pi, a, b) then return false end
            ticks = ticks + 1
          end
        end
      end
      if ticks ~= pz.n then return false end
    end
  end
  return true
end

------------------------------------------------------------------ storage

local function key_of(f) return (f:gsub('[^%w]', '_')) end

local function marks_string()
  local t = {}
  for pi = 1, #pairs_ do
    local s = {}
    for i = 1, pz.n * pz.n do s[i] = marks[pi][i] or '.' end
    t[pi] = table.concat(s)
  end
  return table.concat(t, '/')
end

local function save()
  local st = {}
  for i in pairs(struck) do st[#st + 1] = i end
  table.sort(st)
  local t = { 'bank=' .. (bank and bank.name or ''), 'idx=' .. idx, 'tab=' .. tab,
              'cur=' .. (pz and marks_string() or ''), 'struck=' .. table.concat(st, ',') }
  for f, set in pairs(done) do
    local l = {}
    for k in pairs(set) do l[#l + 1] = k end
    table.sort(l)
    t[#t + 1] = 'done_' .. key_of(f) .. '=' .. table.concat(l, ',')
  end
  for f, k in pairs(places) do t[#t + 1] = 'at_' .. key_of(f) .. '=' .. k end
  kit.write('casefiles.txt', table.concat(t, '\n'))
end

------------------------------------------------------------------ cases

local function open_case(b, n, keep, keep_struck, keep_tab)
  if not b then return end
  n = (n - 1) % b.count + 1
  local p = Case.parse(read_line(b, n))
  if not p then ERR = 'could not read case ' .. n .. ' of ' .. b.file; return end
  bank, idx, pz = b, n, p
  places[b.name] = n
  pairs_ = Case.pairs(p)
  -- column heads too wide for a cell (measured in the reader's font) go on two rows
  for g = 2, p.k do
    for _k, s in ipairs(p.groups[g].short) do
      if kit.width(kit.font('small'), s) > cell_size(p.n) - 6 then p.stagger = true end
    end
  end
  marks, struck, undo, msg, page, tab = {}, {}, {}, nil, 1, 1
  for pi = 1, #pairs_ do marks[pi] = {} end
  if keep then
    local pi = 0
    for s in (keep .. '/'):gmatch('([^/]*)/') do
      pi = pi + 1
      if marks[pi] and #s == p.n * p.n then
        for i = 1, #s do
          local ch = s:sub(i, i)
          if ch == 'x' or ch == 'v' or ch == 'h' then marks[pi][i] = ch end
        end
      end
    end
  end
  for i in (keep_struck or ''):gmatch('%d+') do struck[tonumber(i)] = true end
  keep_tab = tonumber(keep_tab)
  if keep_tab and keep_tab >= 1 and keep_tab <= #pairs_ then tab = keep_tab end
  solved = check_solved()
  if solved then msg = 'Case closed.  Next for another.' end
  pcall(function() ctx:invalidate('full') end)
end

local function load_saved()
  local saved = kit.read('casefiles.txt')
  local s = kit.kv(saved)
  for _k, b in ipairs(banks) do
    local set = {}
    for k in (s['done_' .. key_of(b.name)] or ''):gmatch('%d+') do set[tonumber(k)] = true end
    done[b.name] = set
    places[b.name] = tonumber(s['at_' .. key_of(b.name)])
  end
  local b = banks[1]
  for _k, x in ipairs(banks) do if x.name == s.bank then b = x end end
  open_case(b, tonumber(s.idx) or 1, s.cur, s.struck, s.tab)
  if not saved or saved == '' then how_to() end
end

------------------------------------------------------------------ play

local function summary_lines()
  local lines = {}
  for person = 1, pz.n do
    local t = {}
    for g = 2, pz.k do t[#t + 1] = pz.groups[g].items[pz.slot[g][person]] end
    lines[#lines + 1] = pz.groups[1].items[person] .. ': ' .. table.concat(t, ', ')
  end
  return lines
end

local function next_case() open_case(bank, idx + 1); save() end

local function closed_box()
  kit.show({ title = 'Case closed', lines = summary_lines(),
             rows = { { { 'Next case', function() kit.close(); next_case() end }, { 'Close', kit.close } } },
             cancel = kit.close })
end

local function finish()
  if check_solved() then
    solved = true
    done[bank.name][idx] = true
    local h = 0
    for pi = 1, #pairs_ do for _i, v in pairs(marks[pi]) do if v == 'h' then h = h + 1 end end end
    msg = 'Case closed!' .. (h > 0 and (' Hints ' .. h .. '.') or '') .. '  Next for another.'
    closed_box()
  end
end

local function set_mark(pi, i, v)
  undo[#undo + 1] = { pi, i, marks[pi][i] }
  if #undo > 400 then table.remove(undo, 1) end
  marks[pi][i] = v
end

-- a tap on a cell: nothing -> cross -> tick -> nothing
local function cycle(a, b)
  if solved then msg = 'Case closed.  Next for another.'; return end
  local i = cell(a, b)
  local v = marks[tab][i]
  if v == 'h' then msg = 'That tick came from a hint.'; return end
  set_mark(tab, i, (v == nil and 'x') or (v == 'x' and 'v') or nil)
  local _bad, why = conflicts(tab)
  msg = why
  finish()
  kit.moved()
  save()
end

local function take_back()
  if solved then return end
  local u = table.remove(undo)
  if not u then msg = 'Nothing to undo.'; return end
  marks[u[1]][u[2]] = u[3]
  tab = u[1]
  msg = nil
  save()
end

local function hint()
  if solved then return end
  local wrong = wrong_marks()
  table.sort(wrong, function(x, y) return (x[1] == tab and 0 or 1) < (y[1] == tab and 0 or 1) end)
  if #wrong > 0 then
    local w = wrong[1]
    tab = w[1]
    set_mark(w[1], cell(w[2], w[3]), nil)
    msg = is_tick(w[4]) and 'Hint: that tick was wrong.' or 'Hint: that cross was wrong.'
    save()
    return
  end
  -- a right tick: in this grid if it needs one, else in the first people's grid that does
  local order = { tab }
  for pi = 1, #pairs_ do if pi ~= tab then order[#order + 1] = pi end end
  for _k, pi in ipairs(order) do
    if pairs_[pi][1] == 1 or pi == tab then
      for a = 1, pz.n do
        for b = 1, pz.n do
          if belongs(pi, a, b) and not is_tick(mark_at(pi, a, b)) then
            tab = pi
            set_mark(pi, cell(a, b), 'h')
            msg = 'Hint: a tick (underlined).'
            finish()
            save()
            return
          end
        end
      end
    end
  end
end

local function check()
  if solved then next_case(); return end
  local n = #wrong_marks()
  if n == 0 then msg = 'No mistakes so far.'
  else msg = n == 1 and 'One mark is wrong.' or (n .. ' marks are wrong.') end
end

local function restart()
  for pi = 1, #pairs_ do marks[pi] = {} end
  struck, undo, solved, msg, page, tab = {}, {}, false, nil, 1, 1
  done[bank.name][idx] = nil
  save()
end

------------------------------------------------------------------ layout

local function cell_px() return cell_size(pz.n) end
local function head_h() return pz.stagger and HEAD_H2 or HEAD_H end
local function grid_top() return GRID_BOTTOM - pz.n * cell_px() - head_h() end
local function grid_x0() return W - MARGIN - pz.n * cell_px() end
local function tab_y() return grid_top() - TAB_H - 8 end

local function tab_rect(k)
  local n = #pairs_
  local gap = 4
  local tw = (W - 2 * MARGIN - (n - 1) * gap) // n
  return MARGIN + (k - 1) * (tw + gap), tab_y(), tw, TAB_H
end

local BUTTONS = { 'Undo', 'Hint', 'Check', 'More' }
local function button_rect(k)
  local bw = (W - 2 * MARGIN - 3 * 8) // 4
  return MARGIN + (k - 1) * (bw + 8), BTN_Y, bw, BTN_H
end

local function clue_lh() return kit.line_h('small') + 2 end

-- the clue area's pages: { { lines = { { s, x, clue } }, more = bool } }; clue 0 is the goal
local function clue_pages()
  local lh = clue_lh()
  local cap = (tab_y() - 10 - CLUE_Y) // lh
  local maxw = W - 2 * MARGIN
  local items = {}
  local goal = {}
  for _k, l in ipairs(kit.wrap(Case.goal(pz), 'small', maxw)) do goal[#goal + 1] = { l, MARGIN, 0 } end
  for i, c in ipairs(pz.clues) do
    local prefix = i .. '. '
    local indent = kit.width(kit.font('small'), '00. ')
    local ls = kit.wrap(Case.text(pz, c), 'small', maxw - indent)
    local block = {}
    for j, l in ipairs(ls) do
      block[#block + 1] = { l, MARGIN + indent, i }
    end
    block[1].prefix = prefix
    items[#items + 1] = block
  end
  local total = #goal
  for _k, block in ipairs(items) do total = total + #block end
  -- all on one page, or pages that keep their last line for "tap here for the next"
  local room = total <= cap and cap or cap - 1
  local pages, cur = {}, { lines = {} }
  local function add(block) for _k, l in ipairs(block) do cur.lines[#cur.lines + 1] = l end end
  add(goal)
  for _k, block in ipairs(items) do
    if #cur.lines > 0 and #cur.lines + #block > room then
      pages[#pages + 1] = cur
      cur = { lines = {} }
    end
    add(block)
  end
  pages[#pages + 1] = cur
  if #pages > 1 then for _k, pg in ipairs(pages) do pg.more = true end end
  return pages, cap
end

------------------------------------------------------------------ drawing

local BLACK = { fill = true }

local function draw_tick(gg, cx, cy, s)
  gg:line(cx - s, cy, cx - s // 3, cy + s * 2 // 3, { line_width = 4 })
  gg:line(cx - s // 3, cy + s * 2 // 3, cx + s, cy - s * 2 // 3, { line_width = 4 })
end

local function draw_cross(gg, cx, cy, s)
  gg:line(cx - s, cy - s, cx + s, cy + s, { line_width = 2 })
  gg:line(cx + s, cy - s, cx - s, cy + s, { line_width = 2 })
end

local function draw_clues(gg)
  local pages = clue_pages()
  if page > #pages then page = 1 end
  local pg = pages[page]
  local small = kit.font('small')
  local lh = clue_lh()
  local y = CLUE_Y
  for _k, l in ipairs(pg.lines) do
    if l.prefix then gg:text(MARGIN, y, l.prefix, { font = small }) end
    gg:text(l[2], y, l[1], { font = small })
    if l[3] > 0 and struck[l[3]] then
      local w = kit.width(small, l[1])
      gg:line(l[2], y + lh // 2, l[2] + w, y + lh // 2, { line_width = 2 })
    end
    y = y + lh
  end
  if pg.more then
    local s = 'Clues ' .. page .. ' of ' .. #pages .. ': tap here for the ' .. (page < #pages and 'next' or 'first')
    gg:text(MARGIN, tab_y() - 10 - lh, s, { font = small })
  end
end

local function draw_tabs(gg)
  local small = kit.font('small')
  for k, pr in ipairs(pairs_) do
    local x, y, w, h = tab_rect(k)
    gg:rect(x, y, w, h, { line_width = k == tab and 3 or 1 })
    local function fit(s) while #s > 1 and kit.width(small, s) > w - 6 do s = kit.drop_last(s) end return s end
    local a, b = fit(pz.groups[pr[1]].key), fit(pz.groups[pr[2]].key)
    if #pairs_ <= 3 then
      local s = a .. ' / ' .. b
      gg:text(x + (w - kit.width(small, s)) // 2, y + (h - kit.line_h('small')) // 2 - 2, s, { font = small })
    else
      gg:text(x + (w - kit.width(small, a)) // 2, y + 3, a, { font = small })
      gg:text(x + (w - kit.width(small, b)) // 2, y + 3 + kit.line_h('small'), b, { font = small })
    end
  end
end

local function draw_grid(gg)
  local n, C = pz.n, cell_px()
  local g, h = pairs_[tab][1], pairs_[tab][2]
  local G, Hh = pz.groups[g], pz.groups[h]
  local x0, top = grid_x0(), grid_top()
  local y0 = top + head_h()
  local small = kit.font('small')
  local medium = kit.font('medium')
  -- column heads, row heads
  for b = 1, n do
    local s = Hh.short[b]
    local hy = top + 6
    if pz.stagger then hy = top + 3 + ((b - 1) % 2) * (kit.line_h('small') + 1) end
    gg:text(x0 + (b - 1) * C + (C - kit.width(small, s)) // 2, hy, s, { font = small })
  end
  for a = 1, n do
    gg:text(MARGIN, y0 + (a - 1) * C + (C - kit.line_h('medium')) // 2, kit.short(G.short[a], 12), { font = medium })
  end
  -- lines
  for k = 0, n do
    local lw = (k == 0 or k == n) and 3 or 1
    gg:line(x0 + k * C, y0, x0 + k * C, y0 + n * C, { line_width = lw })
    gg:line(x0, y0 + k * C, x0 + n * C, y0 + k * C, { line_width = lw })
  end
  -- marks
  local bad = conflicts(tab)
  local out = ruled_out(tab)
  local s = C // 4
  for a = 1, n do
    for b = 1, n do
      local i = cell(a, b)
      local v = marks[tab][i]
      local cx, cy = x0 + (b - 1) * C + C // 2, y0 + (a - 1) * C + C // 2
      if is_tick(v) then
        draw_tick(gg, cx, cy, s)
        if v == 'h' then gg:rect(cx - s, cy + C // 2 - 9, 2 * s, 2, BLACK) end
        if bad[i] then gg:circle(cx, cy, C * 42 // 100, { line_width = 3 }) end
      elseif v == 'x' then
        draw_cross(gg, cx, cy, C // 7)
      elseif out[i] then
        gg:circle(cx, cy, 3, BLACK)
      end
    end
  end
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    gg:clear(0)
    local title = pz and pz.theme.title or 'Case Files'
    gg:text(MARGIN, 10, kit.short(title, 30), { font = kit.font('large') })
    -- the second line: a message while there is one, else the level and the case
    if msg and not kit.modal() then
      gg:text(MARGIN, 44, kit.short(msg, 46), { font = kit.font('medium') })
    elseif bank then
      local nd = 0
      for _k in pairs(done[bank.name] or {}) do nd = nd + 1 end
      gg:text(MARGIN, 46, kit.short('Case Files   ' .. bank.label .. '   No. ' .. idx .. ' of ' .. bank.count .. '   closed ' .. nd, 48),
              { font = kit.font('small') })
    end
    gg:line(MARGIN, 70, W - MARGIN, 70, { line_width = 1 })
    if kit.modal() then kit.draw_modal(gg); return end
    if not pz then
      if ERR then gg:text(MARGIN, 120, kit.short(ERR, 46), { font = kit.font('small') }) end
      return
    end
    draw_clues(gg)
    draw_tabs(gg)
    draw_grid(gg)
    for k, b in ipairs(BUTTONS) do
      local x, y, bw, bh = button_rect(k)
      kit.button(gg, x, y, bw, bh, (k == 3 and solved) and 'Next' or b)
    end
    if ERR then gg:text(MARGIN, H - 24, kit.short('ERR ' .. ERR, 48), { font = kit.font('small') }) end
  end)
  if not ok then pcall(function() gg:text(8, H - 60, kit.short('draw ERR ' .. tostring(e), 46)) end) end
end

------------------------------------------------------------------ input

function how_to()
  kit.show({ title = 'How to play', lines = {
    'Each person has one item of every group: one floor, one time, one lost item, no two alike. The clues tell you who has what.',
    'Each grid pairs two groups. Tap a cell once for a cross (these two do not go together), twice for a tick (they do), a third time to clear it. A tick dots the rest of its row and column.',
    'Use the other grids too: if Ada stayed on the 2nd floor and the 2nd floor guest lost the key, Ada lost the key. "Either ... or" means exactly one of the two. Tap a clue to cross it out.',
    'The case is closed when every person has the right tick in each of the first grids.',
  }, rows = { { { 'Close', kit.close } } }, cancel = kit.close })
end

local function more()
  local function goto_bank(b) return function() kit.close(); save(); open_case(b, places[b.name] or 1); save() end end
  local lrow = {}
  for _k, b in ipairs(banks) do lrow[#lrow + 1] = { b.label, goto_bank(b), b ~= bank } end
  local rows = { lrow,
    { { 'Previous', function() kit.close(); open_case(bank, idx - 1); save() end },
      { 'Next', function() kit.close(); next_case() end } },
    { { 'Start over', function() kit.close(); restart() end }, { 'Rules', how_to } },
    { { 'Close', kit.close } } }
  local lines = { pz and pz.theme.story or '' }
  if solved then rows[3][#rows[3] + 1] = { 'Answer', function() kit.close(); closed_box() end } end
  kit.show({ title = (bank and bank.label or '') .. ' case ' .. idx .. ' of ' .. (bank and bank.count or 0), lines = lines,
             rows = rows, cancel = kit.close })
end

local function in_rect(x, y, rx, ry, rw, rh) return x >= rx and x < rx + rw and y >= ry and y < ry + rh end

local function tap_clues(x, y)
  local pages = clue_pages()
  local pg = pages[page] or pages[1]
  local lh = clue_lh()
  if pg.more and y >= tab_y() - 10 - lh and y < tab_y() - 4 then
    page = page % #pages + 1
    return true
  end
  local ly = CLUE_Y
  for _k, l in ipairs(pg.lines) do
    if y >= ly and y < ly + lh then
      if l[3] > 0 then struck[l[3]] = not struck[l[3]] or nil; save() end
      return true
    end
    ly = ly + lh
  end
  return false
end

local function tap(x, y)
  if kit.tap_modal(x, y) then return end
  for k = 1, #BUTTONS do
    local bx, by, bw, bh = button_rect(k)
    if in_rect(x, y, bx, by, bw, bh) then
      if k == 1 then take_back()
      elseif k == 2 then hint()
      elseif k == 3 then check()
      else more() end
      return
    end
  end
  if not pz then return end
  for k = 1, #pairs_ do
    if in_rect(x, y, tab_rect(k)) then tab = k; msg = nil; save(); return end
  end
  local C = cell_px()
  local x0, y0 = grid_x0(), grid_top() + head_h()
  if x >= x0 and x < x0 + pz.n * C and y >= y0 and y < y0 + pz.n * C then
    cycle((y - y0) // C + 1, (x - x0) // C + 1)
    return
  end
  if y >= CLUE_Y and y < tab_y() then tap_clues(x, y) end
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
    elseif ev.type == 'key' and kit.key_accepted(ev) and not kit.modal() and pz then
      if ev.key == 'down' then tab = tab % #pairs_ + 1; save()
      elseif ev.key == 'up' then tab = (tab - 2) % #pairs_ + 1; save() end
    end
  end)
  if not ok then ERR = tostring(e) end
  kit.refresh()
  return handled
end

function on_load(c)
  local ok, e = pcall(function()
    load_banks()
    if #banks == 0 then ERR = 'no cases in the package'; return end
    load_saved()
  end)
  if not ok then ERR = tostring(e) end
end
function on_leave() pcall(save) end

if rawget(_G, '__TEST') then
  __TEST.api = { banks = function() return banks end, bank = function() return bank end, idx = function() return idx end,
                 pz = function() return pz end, marks = function() return marks end, pairs = function() return pairs_ end,
                 tab = function() return tab end, solved = function() return solved end, msg = function() return msg end,
                 struck = function() return struck end, page = function() return page end,
                 cell_px = cell_px, grid_x0 = grid_x0, grid_top = grid_top, head_h = head_h, clue_pages = clue_pages,
                 tab_rect = tab_rect, clue_y = CLUE_Y, open_case = open_case, done = function() return done end,
                 text = function(i) return Case.text(pz, pz.clues[i]) end }
end
