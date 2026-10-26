-- Minesweeper for XTOS Licorice, API 2.9 (uses tools/gamekit).
--
-- Open every cell that holds no mine; a number tells how many of the eight neighbours hold one.
-- No guessing is ever needed: the mines are laid after the first tap (which always opens an empty
-- area) and a board is kept only if logic alone, from that first opening, clears it. A tap opens a
-- cell; a long press, or a tap in Flag mode, sets or removes a flag; a tap on a number whose mines
-- are all flagged opens its other neighbours. Hint frames a cell that logic proves safe (or a
-- wrong flag). Easy 8x10, Normal 9x11 and Hard 10x13 fill the screen with cells a finger can hit.

local W, H = kit.W, kit.H
local LEVELS = {
  { name = 'Easy', cols = 8, rows = 10, mines = 10 },
  { name = 'Normal', cols = 9, rows = 11, mines = 17 },
  { name = 'Hard', cols = 10, rows = 13, mines = 27 },
}
local GY, BTN_Y, BTN_H = 100, 704, 60
local TRIES = 300            -- boards tried for one that logic clears
local TRY_MS = 2000          -- and for at most this long
local IDLE_MS = 30000        -- longer pauses between moves do not count as play time

local level = 2
local cols, rows, n, total = 0, 0, 0, 0
local nbrs = {}              -- cell -> neighbour cells
local mine = {}              -- cell -> true
local count = {}             -- cell -> mines around it
local cell = {}              -- cell -> 'h' hidden, 'f' flagged, 'o' open
local state = 'fresh'        -- fresh, play, won, lost
local boom = nil             -- the mine that went off
local elapsed, last_ms = 0, nil
local stats = {}             -- level -> { played, won, best seconds }
local mode = 'dig'
local hint, msg = nil, nil
local history = {}
local suppress_up = false
local long_done = false     -- the long press of this touch has acted
local ERR = nil
local LOGIC = true           -- false only when no board in TRIES could be cleared by logic

------------------------------------------------------------------ board

local function setup(lv)
  level = lv
  local L = LEVELS[lv]
  cols, rows, total = L.cols, L.rows, L.mines
  n = cols * rows
  nbrs = {}
  for i = 1, n do
    local r, c = (i - 1) // cols, (i - 1) % cols
    local list = {}
    for dr = -1, 1 do
      for dc = -1, 1 do
        local rr, cc = r + dr, c + dc
        if (dr ~= 0 or dc ~= 0) and rr >= 0 and rr < rows and cc >= 0 and cc < cols then list[#list + 1] = rr * cols + cc + 1 end
      end
    end
    nbrs[i] = list
  end
  mine, count, cell = {}, {}, {}
  for i = 1, n do cell[i] = 'h'; count[i] = 0 end
  state, boom, elapsed, last_ms, hint, msg, history = 'fresh', nil, 0, nil, nil, nil, {}
end

local function set_mines(m)
  mine = m
  for i = 1, n do
    local k = 0
    for _k, j in ipairs(nbrs[i]) do if m[j] then k = k + 1 end end
    count[i] = k
  end
end

-- open i in T (a cell table) and the empty area around it; flagged ('f') and known-mine ('m')
-- cells stay shut
local function flood(T, i)
  local stack = { i }
  while #stack > 0 do
    local j = table.remove(stack)
    if T[j] ~= 'o' and T[j] ~= 'f' and T[j] ~= 'm' then
      T[j] = 'o'
      if count[j] == 0 then
        for _k, x in ipairs(nbrs[j]) do if T[x] ~= 'o' then stack[#stack + 1] = x end end
      end
    end
  end
end

------------------------------------------------------------------ logic

-- One round of deduction on K (cell -> 'o' open, 'm' known mine, anything else unknown): the
-- single-number rules, then pairs of numbers (if b needs as many more mines than a as b has
-- cells of its own, those are mines and a's own cells are safe), then the mine count.
-- Returns the cells found safe and the cells found to be mines.
local function deduce(K)
  local cs = {}
  for i = 1, n do
    if K[i] == 'o' and count[i] > 0 then
      local u, s, k = {}, {}, 0
      for _k, j in ipairs(nbrs[i]) do
        if K[j] == 'm' then k = k + 1 elseif K[j] ~= 'o' then u[#u + 1] = j; s[j] = true end
      end
      if #u > 0 then cs[#cs + 1] = { i = i, u = u, s = s, need = count[i] - k } end
    end
  end
  local safe, mines, seen = {}, {}, {}
  local function add(list, into) for _k, j in ipairs(list) do if not seen[j] then seen[j] = true; into[#into + 1] = j end end end
  for _k, c in ipairs(cs) do
    if c.need == 0 then add(c.u, safe) elseif c.need == #c.u then add(c.u, mines) end
  end
  if #safe + #mines > 0 then return safe, mines end
  for _k, a in ipairs(cs) do
    local ar, ac = (a.i - 1) // cols, (a.i - 1) % cols
    for _j, b in ipairs(cs) do
      local br, bc = (b.i - 1) // cols, (b.i - 1) % cols
      if a ~= b and math.abs(ar - br) <= 2 and math.abs(ac - bc) <= 2 then
        local only_a, only_b, shared = {}, {}, 0
        for _x, j in ipairs(a.u) do if b.s[j] then shared = shared + 1 else only_a[#only_a + 1] = j end end
        if shared > 0 then
          for _x, j in ipairs(b.u) do if not a.s[j] then only_b[#only_b + 1] = j end end
          if b.need - a.need == #only_b then add(only_b, mines); add(only_a, safe) end
        end
      end
    end
  end
  if #safe + #mines > 0 then return safe, mines end
  local unknown, known = {}, 0
  for i = 1, n do if K[i] == 'm' then known = known + 1 elseif K[i] ~= 'o' then unknown[#unknown + 1] = i end end
  if total - known == 0 then add(unknown, safe) elseif total - known == #unknown then add(unknown, mines) end
  return safe, mines
end

-- logic alone, from the cells open in K, until it is stuck; true when every safe cell is open
local function clears(K)
  while true do
    local safe, mines = deduce(K)
    if #safe + #mines == 0 then break end
    for _k, j in ipairs(mines) do K[j] = 'm' end
    for _k, j in ipairs(safe) do flood(K, j) end
  end
  for i = 1, n do if not mine[i] and K[i] ~= 'o' then return false end end
  return true
end

local function lay_mines(first)
  local banned = { [first] = true }
  for _k, j in ipairs(nbrs[first]) do banned[j] = true end
  local pool = {}
  for i = 1, n do if not banned[i] then pool[#pool + 1] = i end end
  local t0 = kit.now_ms()
  for _t = 1, TRIES do
    local now = kit.now_ms()
    if t0 and now and now - t0 > TRY_MS then break end
    local m = {}
    for k = 1, total do
      local r = math.random(k, #pool)
      pool[k], pool[r] = pool[r], pool[k]
      m[pool[k]] = true
    end
    set_mines(m)
    local K = {}
    flood(K, first)
    if clears(K) then LOGIC = true; return end
  end
  LOGIC = false        -- keep the last board: it still starts with an empty area
end

------------------------------------------------------------------ storage

local function save()
  local m = {}
  for i = 1, n do if mine[i] then m[#m + 1] = i end end
  local s = {}
  for k = 1, #LEVELS do
    local t = stats[k] or {}
    s[#s + 1] = k .. ':' .. (t.played or 0) .. ':' .. (t.won or 0) .. ':' .. (t.best or 0)
  end
  kit.write('game.txt', 'level=' .. level .. '\nstate=' .. state .. '\nmines=' .. table.concat(m, ',') ..
    '\ncells=' .. table.concat(cell) .. '\nboom=' .. (boom or 0) .. '\nelapsed=' .. elapsed ..
    '\nmode=' .. mode .. '\nstats=' .. table.concat(s, ';'))
end

local function load()
  local t = kit.kv(kit.read('game.txt'))
  for k, p, w, b in (t.stats or ''):gmatch('(%d+):(%d+):(%d+):(%d+)') do
    stats[tonumber(k)] = { played = tonumber(p), won = tonumber(w), best = tonumber(b) }
  end
  local lv = tonumber(t.level) or 2
  setup(LEVELS[lv] and lv or 2)
  mode = t.mode == 'flag' and 'flag' or 'dig'
  local cs = t.cells or ''
  if (t.state == 'play' or t.state == 'won' or t.state == 'lost') and #cs == n and cs:match('^[hfo]+$') then
    local m = {}
    for i in (t.mines or ''):gmatch('%d+') do m[tonumber(i)] = true end
    set_mines(m)
    for i = 1, n do cell[i] = cs:sub(i, i) end
    state = t.state
    boom = tonumber(t.boom) ~= 0 and tonumber(t.boom) or nil
    elapsed = tonumber(t.elapsed) or 0
  end
end

------------------------------------------------------------------ play

local function stat() stats[level] = stats[level] or { played = 0, won = 0, best = 0 }; return stats[level] end
local function seconds() return elapsed // 1000 end
local function clock(s) return string.format('%d:%02d', s // 60, s % 60) end

local function snapshot()
  history[#history + 1] = { table.concat(cell), state, boom }
  if #history > 60 then table.remove(history, 1) end
end

local function tick()
  local now = kit.now_ms()
  if state == 'play' and now and last_ms and now > last_ms then elapsed = elapsed + math.min(now - last_ms, IDLE_MS) end
  last_ms = now
end

local function new_game()
  setup(level)
  save()
end

local function check_win()
  for i = 1, n do if not mine[i] and cell[i] ~= 'o' then return end end
  state = 'won'
  for i = 1, n do if mine[i] then cell[i] = 'f' end end
  local s, t = stat(), seconds()
  s.won = s.won + 1
  local record = s.best == 0 or t < s.best
  if record then s.best = t end
  kit.show({
    title = 'Cleared!',
    lines = { LEVELS[level].name .. ' in ' .. clock(t) .. (record and ' (best time)' or ', best ' .. clock(s.best)),
              'Won ' .. s.won .. ' of ' .. s.played },
    rows = { { { 'New', function() kit.close(); new_game() end }, { 'Close', kit.close } } },
    cancel = kit.close,
  })
end

local undo
local function lose(i)
  state, boom = 'lost', i
  kit.show({
    title = 'Boom!',
    lines = { 'That cell held a mine.', 'Undo takes the move back; the board needs no guessing.' },
    rows = { { { 'Undo', function() kit.close(); undo() end }, { 'New', function() kit.close(); new_game() end } } },
    cancel = kit.close,
  })
end

local function open(i)
  if mine[i] then cell[i] = 'h'; lose(i); return end
  flood(cell, i)
end

local function start(first)
  lay_mines(first)
  state = 'play'
  local s = stat()
  s.played = s.played + 1
  last_ms = kit.now_ms()
  flood(cell, first)
end

undo = function()
  local h = table.remove(history)
  if not h then msg = 'Nothing to undo.'; return end
  for i = 1, n do cell[i] = h[1]:sub(i, i) end
  state, boom, hint = h[2], h[3], nil
  save()
end

local function flag(i)
  if cell[i] == 'o' then return end
  snapshot()
  cell[i] = cell[i] == 'f' and 'h' or 'f'
end

-- the open number's other neighbours, when its flags match it
local function chord(i)
  local flags, shut = 0, {}
  for _k, j in ipairs(nbrs[i]) do
    if cell[j] == 'f' then flags = flags + 1 elseif cell[j] == 'h' then shut[#shut + 1] = j end
  end
  if #shut == 0 then return end
  if flags ~= count[i] then msg = 'Flag ' .. count[i] .. ' mines around it first.'; return end
  snapshot()
  for _k, j in ipairs(shut) do
    if mine[j] then open(j); return end
    flood(cell, j)
  end
end

local function tap_cell(i, long)
  hint, msg = nil, nil
  if state == 'won' or state == 'lost' then return end
  if state == 'fresh' then
    snapshot(); start(i)
  elseif cell[i] == 'o' then
    chord(i)
  elseif long or mode == 'flag' then
    flag(i)
  elseif cell[i] == 'f' then
    msg = 'Flagged: long-press to remove the flag.'
  else
    snapshot(); open(i)
  end
  kit.moved()
  if state == 'play' then check_win() end
  save()
end

local function show_hint()
  hint = nil
  if state ~= 'play' then msg = state == 'fresh' and 'Tap any cell to start.' or nil; return end
  for i = 1, n do
    if cell[i] == 'f' and not mine[i] then hint, msg = i, 'Hint: this flag is wrong.'; return end
  end
  local K = {}
  for i = 1, n do if cell[i] == 'o' then K[i] = 'o' end end
  while true do
    local safe, mines = deduce(K)
    if #safe + #mines == 0 then break end
    for _k, j in ipairs(safe) do
      if cell[j] == 'h' then hint, msg = j, 'Hint: the framed cell is safe.'; return end
    end
    for _k, j in ipairs(mines) do K[j] = 'm' end
    for _k, j in ipairs(safe) do flood(K, j) end
  end
  for i = 1, n do
    if mine[i] and cell[i] ~= 'f' then hint, msg = i, 'Hint: the framed cell is a mine.'; return end
  end
  msg = 'No sure move found.'
end

local BUTTONS = {
  { function() return 'Undo' end, function() hint = nil; undo() end },
  { function() return 'Hint' end, show_hint },
  { function() return mode == 'dig' and 'Dig' or 'Flag' end, function()
      mode = mode == 'dig' and 'flag' or 'dig'
      msg = mode == 'flag' and 'A tap now sets or removes a flag.' or 'A tap now opens a cell.'
      save()
    end },
  { function() return 'New' end, function() new_game() end },
  { function() return LEVELS[level].name end, function()
      setup(level % #LEVELS + 1)
      save()
    end },
}
local function button_rect(k)
  local bw = math.floor((W - 24 - 4 * 8) / 5)
  return 12 + (k - 1) * (bw + 8), BTN_Y, bw, BTN_H
end

------------------------------------------------------------------ drawing

local function geometry()
  local cs = math.min(456 // cols, 560 // rows)
  return cs, (W - cols * cs) // 2, GY
end

local function circle(gg, x, y, r) pcall(function() gg:circle(x, y, r) end) end

local function draw_flag(gg, x, y, cs)
  local cx = x + cs // 2 + cs // 10
  gg:line(cx, y + cs * 22 // 100, cx, y + cs * 76 // 100)
  gg:line(cx - 1, y + cs * 22 // 100, cx - 1, y + cs * 76 // 100)
  gg:rect(cx - cs * 30 // 100, y + cs * 22 // 100, cs * 30 // 100, cs * 20 // 100, { fill = true })
  gg:line(cx - cs // 5, y + cs * 76 // 100, cx + cs // 6, y + cs * 76 // 100)
  gg:line(cx - cs // 5, y + cs * 76 // 100 - 1, cx + cs // 6, y + cs * 76 // 100 - 1)
end

local function draw_mine(gg, x, y, cs)
  local cx, cy, r = x + cs // 2, y + cs // 2, cs // 5
  gg:rect(cx - r * 6 // 10, cy - r * 6 // 10, r * 12 // 10, r * 12 // 10, { fill = true })
  circle(gg, cx, cy, r); circle(gg, cx, cy, r - 1)
  gg:line(cx - r - 4, cy, cx + r + 4, cy)
  gg:line(cx, cy - r - 4, cx, cy + r + 4)
  gg:line(cx - r, cy - r, cx + r, cy + r)
  gg:line(cx - r, cy + r, cx + r, cy - r)
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    gg:clear(0)
    gg:text(12, 12, 'Minesweeper', { font = kit.font('large') })
    local flags = 0
    for i = 1, n do if cell[i] == 'f' then flags = flags + 1 end end
    local s = stat()
    gg:text(12, 52, kit.short(cols .. 'x' .. rows .. '    Mines ' .. (total - flags) .. '    Time ' .. clock(seconds()) ..
      '    Won ' .. s.won .. '/' .. s.played, 48), { font = kit.font('small') })
    gg:line(0, 90, W, 90)
    if kit.modal() then kit.draw_modal(gg); return end
    local cs, gx, gy = geometry()
    local big = kit.font(cs >= 44 and 'large' or 'medium')
    local lh = kit.line_h(cs >= 44 and 'large' or 'medium')
    for i = 1, n do
      local x, y = gx + ((i - 1) % cols) * cs, gy + ((i - 1) // cols) * cs
      gg:rect(x, y, cs, cs, { line_width = 1 })
      local v = cell[i]
      if v == 'o' then
        if count[i] > 0 then
          local t = tostring(count[i])
          gg:text(x + (cs - kit.width(big, t)) // 2, y + (cs - lh) // 2, t, { font = big })
        end
      else
        gg:rect(x + 4, y + 4, cs - 8, cs - 8, { line_width = 2 })
        if state == 'lost' and mine[i] and v ~= 'f' then
          draw_mine(gg, x, y, cs)
        elseif v == 'f' then
          draw_flag(gg, x, y, cs)
          if state == 'lost' and not mine[i] then
            gg:line(x + 6, y + 6, x + cs - 6, y + cs - 6); gg:line(x + 6, y + cs - 6, x + cs - 6, y + 6)
          end
        end
      end
      if boom == i then gg:rect(x + 1, y + 1, cs - 2, cs - 2, { line_width = 4 }) end
      if hint == i then gg:rect(x - 2, y - 2, cs + 4, cs + 4, { line_width = 4 }) end
    end
    gg:rect(gx - 2, gy - 2, cols * cs + 4, rows * cs + 4, { line_width = 2 })
    local m = msg
    if not m then
      if state == 'fresh' then m = 'Tap any cell to start.'
      elseif state == 'won' then m = 'Cleared! New starts another board.'
      elseif state == 'lost' then m = 'Boom! Undo takes the move back.'
      elseif not LOGIC then m = 'This board may need a guess.'
      else m = mode == 'flag' and 'Flag mode: a tap sets a flag.' or 'Long-press a cell to flag it.' end
    end
    gg:text(12, BTN_Y - 34, kit.short(m, 48), { font = kit.font('small') })
    for k, b in ipairs(BUTTONS) do
      local x, y, bw, bh = button_rect(k)
      kit.button(gg, x, y, bw, bh, b[1](), { font = 'small' })
    end
    if ERR then gg:text(12, H - 30, kit.short('ERR ' .. ERR, 48), { font = kit.font('small') }) end
  end)
  if not ok then pcall(function() gg:text(8, H - 60, kit.short('draw ERR ' .. tostring(e), 46)) end) end
end

local function cell_at(x, y)
  local cs, gx, gy = geometry()
  if x >= gx and x < gx + cols * cs and y >= gy and y < gy + rows * cs then
    return ((y - gy) // cs) * cols + (x - gx) // cs + 1
  end
  return nil
end

function on_input(c, ev)
  ERR = nil
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    tick()
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
  local ok, e = pcall(load)
  if not ok then ERR = tostring(e); setup(2) end
end
function on_leave() pcall(function() tick(); last_ms = nil; save() end) end

if rawget(_G, '__TEST') then
  __TEST.api = {
    geometry = geometry, state = function() return state end, level = function() return level end,
    cell = function(i) return cell[i] end, mine = function(i) return mine[i] == true end,
    count = function(i) return count[i] end, n = function() return n end, cols = function() return cols end,
    hint = function() return hint end, logic = function() return LOGIC end, elapsed = function() return elapsed end,
    lay_mines = function(first) setup(level); lay_mines(first); local K = {}; flood(K, first); return clears(K) end,
  }
end
