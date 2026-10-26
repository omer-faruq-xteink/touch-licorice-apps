-- Slide Puzzle for XTOS Licorice, API 2.9: the device screen for the game in slidepuzzle_game.lua.
-- The rules and the translations come unchanged from slidepuzzle.koplugin (KOReader); bundle.py
-- puts them and this file into index.lua.
--
-- A square board (3x3 to 7x7) with the moves, time and best results above it and New / Size /
-- Stats / Settings below. Tap a tile next to the gap or swipe to slide; the side buttons slide
-- too. A tile already in its final place gets a second frame inside its border (the plugin
-- inverts it; see draw_board). Each size keeps its own puzzle and best results; everything is
-- saved after every move.
--
-- Time: the clock is not redrawn every second (an e-ink refresh each second); it advances with the
-- moves, counting each pause between two moves up to IDLE_CAP_S, so time away does not count.
-- Every ctx.* function is a method on this API: colon calls everywhere.

local W, H = 480, 800
local Game = require('slidepuzzle_game')
local I18n = require('slidepuzzle_i18n')
local T = require('ffi/util').template
local function _(s) return I18n.t(s) end

local IDLE_CAP_S = 60
local BOARD_X, BOARD_Y, BOARD_W = 12, 84, 456
local MSG_Y = BOARD_Y + BOARD_W + 14
local BTN_Y, BTN_H = 610, 60

local settings = { size = 4, lang = 'en', always_new = false }
local best = {}          -- size -> { time =, moves =, plays = }
local game
local last_ms = nil      -- the clock at the last move (for the playing time)
local msg = nil
local modal = nil        -- { title, lines = {..}, rows = { { {label, fn, enabled}, .. }, .. }, cancel }
local ERR = nil
local new_or_resume      -- defined with on_load

local function short(s, n) s = tostring(s); if #s > n then return s:sub(1, n - 1) .. '~' end return s end
local function refresh() pcall(function() ctx.invalidate() end) end
local function now_ms() local ok, t = pcall(function() return ctx.clock:millis() end); return ok and tonumber(t) or nil end

local function fmt_time(total)
  total = math.floor(tonumber(total) or 0)
  local h, m, s = total // 3600, (total % 3600) // 60, total % 60
  if h > 0 then return string.format('%d:%02d:%02d', h, m, s) end
  return string.format('%02d:%02d', m, s)
end

------------------------------------------------------------------ storage

local function read(name)
  local ok, s = pcall(function() return ctx.storage:read(name) end)
  return (ok and type(s) == 'string') and s or nil
end
local function write(name, s) pcall(function() ctx.storage:write(name, s) end) end
local function kv(s)
  local t = {}
  for k, v in (s or ''):gmatch('([%w_]+)=([^\n]*)') do t[k] = (v:gsub('%s+$', '')) end
  return t
end

local function save_settings()
  write('settings.txt', 'size=' .. settings.size .. '\nlang=' .. settings.lang .. '\nalways_new=' .. (settings.always_new and '1' or '0'))
end
local function save_best()
  local lines = {}
  for n, b in pairs(best) do
    lines[#lines + 1] = n .. '=' .. (b.time or '') .. ',' .. (b.moves or '') .. ',' .. (b.plays or 0)
  end
  table.sort(lines)
  write('best.txt', table.concat(lines, '\n'))
end
local function load_best()
  best = {}
  for n, v in pairs(kv(read('best.txt'))) do
    local t, m, p = v:match('^(%d*),(%d*),(%d*)$')
    if t then best[tonumber(n)] = { time = tonumber(t), moves = tonumber(m), plays = tonumber(p) or 0 } end
  end
end

-- one puzzle per size: "game<n>.txt" with the grid row by row, moves, time, started
local function save_game()
  if not game then return end
  local st = game:serialize()
  local rows = {}
  for r = 1, st.size do rows[r] = table.concat(st.grid[r], ',') end
  write('game' .. st.size .. '.txt', 'grid=' .. table.concat(rows, ';') .. '\nmoves=' .. st.moves ..
    '\nelapsed=' .. math.floor(st.elapsed) .. '\nstarted=' .. (st.started and '1' or '0'))
end
local function load_game(n)
  local t = kv(read('game' .. n .. '.txt'))
  if not t.grid or settings.always_new then
    local g = Game:new(n); g:shuffle(); return g
  end
  local grid = {}
  for row in (t.grid .. ';'):gmatch('([^;]*);') do
    local cells = {}
    for v in (row .. ','):gmatch('([^,]*),') do cells[#cells + 1] = tonumber(v) end
    grid[#grid + 1] = cells
  end
  local g = Game.deserialize({ size = n, grid = grid, moves = tonumber(t.moves), elapsed = tonumber(t.elapsed),
                               started = t.started == '1' }, n)
  if g:isWon() then g:shuffle() end                  -- a finished puzzle: start a new one
  return g
end

------------------------------------------------------------------ text

local function font(name) return ctx.fonts and ctx.fonts[name] end
local function width(f, s)
  local ok, w = pcall(function() return f:measure(s) end)
  return (ok and type(w) == 'number') and w or #s * 11
end
local function line_h(name)
  local ok, h = pcall(function() return font(name).line_height end)
  return (ok and tonumber(h)) or (name == 'large' and 30 or name == 'small' and 20 or 24)
end
local function drop_last(s) return (s:gsub('[%z\1-\127\192-\255][\128-\191]*$', '')) end
local function wrap(s, fname, maxw)
  local f, out = font(fname), {}
  for para in (tostring(s) .. '\n'):gmatch('([^\n]*)\n') do
    local line = ''
    for word in para:gmatch('[^ \t]+') do                -- ASCII spaces only: %s can split UTF-8
      local cand = line == '' and word or (line .. ' ' .. word)
      if line ~= '' and width(f, cand) > maxw then out[#out + 1] = line; line = word else line = cand end
    end
    out[#out + 1] = line
  end
  return out
end
------------------------------------------------------------------ boxes

local BOX_X, BOX_W, ROW_H, GAP = 20, W - 40, 56, 10

local function layout_modal(m)
  local lines = {}
  if m.title then for _k, l in ipairs(wrap(m.title, 'medium', BOX_W - 40)) do lines[#lines + 1] = { l, 'medium' } end end
  for _k, s in ipairs(m.lines or {}) do
    for _j, l in ipairs(wrap(s, 'small', BOX_W - 40)) do lines[#lines + 1] = { l, 'small' } end
  end
  local th = 0
  for _k, l in ipairs(lines) do th = th + line_h(l[2]) + 4 end
  local h = 20 + th + 14 + #m.rows * (ROW_H + GAP) + 10
  local y = math.max(60, math.floor((H - h) / 2))
  local btns, by = {}, y + 20 + th + 14
  for _k, row in ipairs(m.rows) do
    local n = #row
    local bw = math.floor((BOX_W - 40 - (n - 1) * GAP) / n)
    for k, btn in ipairs(row) do
      btns[#btns + 1] = { x = BOX_X + 20 + (k - 1) * (bw + GAP), y = by, w = bw, h = ROW_H, b = btn }
    end
    by = by + ROW_H + GAP
  end
  return lines, btns, y, h
end

local function draw_modal(gg)
  local lines, btns, y, h = layout_modal(modal)
  gg:rect(BOX_X, y, BOX_W, h)
  gg:rect(BOX_X + 3, y + 3, BOX_W - 6, h - 6)
  local ty = y + 20
  for _k, l in ipairs(lines) do gg:text(BOX_X + 20, ty, l[1], { font = font(l[2]) }); ty = ty + line_h(l[2]) + 4 end
  for _k, bt in ipairs(btns) do
    local enabled = bt.b[3] ~= false
    gg:rect(bt.x, bt.y, bt.w, bt.h, { line_width = enabled and 2 or 1 })
    local f = font('medium')
    local label = tostring(bt.b[1])
    while #label > 1 and width(f, label) > bt.w - 12 do label = drop_last(label) end
    if not enabled then label = '(' .. label .. ')' end
    gg:text(bt.x + math.floor((bt.w - width(f, label)) / 2), bt.y + 15, label, { font = f })
  end
end

local function show(m) modal = m end
local function close_modal() modal = nil end

------------------------------------------------------------------ game flow

-- playing time: the pause since the last move, at most IDLE_CAP_S
local function tick_time()
  local t = now_ms()
  if t and last_ms and game and game:hasStarted() and not game:isWon() then
    game:addElapsed(math.min(IDLE_CAP_S, math.max(0, (t - last_ms) / 1000)))
  end
  last_ms = t
end

local function new_puzzle(n)
  settings.size = n or settings.size
  save_settings()
  game = Game:new(settings.size)
  game:shuffle()
  last_ms = now_ms()
  msg = _('New puzzle — good luck!')
  save_game()
end

local function won()
  local n = game:getSize()
  local b = best[n] or { plays = 0 }
  b.plays = (b.plays or 0) + 1
  local secs = math.floor(game:getElapsed())
  if not b.time or secs < b.time then b.time = secs end
  if not b.moves or game:getMoves() < b.moves then b.moves = game:getMoves() end
  best[n] = b
  save_best()
  msg = T(_('Solved in %1 moves and %2.'), game:getMoves(), fmt_time(secs))
  show({
    lines = { T(_('You solved the %1x%1 puzzle!\nMoves: %2\nTime: %3'), n, game:getMoves(), fmt_time(secs)) },
    rows = { { { _('New'), function() close_modal(); new_puzzle() end }, { _('Close'), close_modal } } },
    cancel = close_modal,
  })
end

local function after_move(moved)
  if not moved then return end
  msg = nil
  save_game()
  if game:isWon() then won() end
end

local function move_at(r, c)
  if game:isWon() then return end
  tick_time()
  local moved = game:moveTileAt(r, c)
  if not moved then msg = _('Only tiles next to the gap can move.') end
  after_move(moved)
end

local function slide(dir)
  if game:isWon() then return end
  tick_time()
  after_move(game:slide(dir))
end

------------------------------------------------------------------ menus

local LANGS = {}
for _k, l in ipairs(I18n.LANGS) do if l.code ~= 'default' then LANGS[#LANGS + 1] = l end end
local function lang_name(code) for _k, l in ipairs(LANGS) do if l.code == code then return l.name end end return code end

local function size_box()
  local rows, row = {}, {}
  for n = Game.getMinSize(), Game.getMaxSize() do
    row[#row + 1] = { T(_('%1 × %1'), n), function() close_modal(); save_game(); new_or_resume(n) end }
    if #row == 3 then rows[#rows + 1] = row; row = {} end
  end
  if #row > 0 then rows[#rows + 1] = row end
  rows[#rows + 1] = { { _('Cancel'), close_modal } }
  show({ title = _('Select board size'), rows = rows, cancel = close_modal })
end

local function stats_box()
  local lines = {}
  for n = Game.getMinSize(), Game.getMaxSize() do
    local b = best[n]
    if b and (b.plays or 0) > 0 then
      lines[#lines + 1] = T(_('%1 × %1'), n) .. '    ' .. _('col_time') .. ' ' .. (b.time and fmt_time(b.time) or '--:--') ..
        '    ' .. _('col_moves') .. ' ' .. (b.moves or '-') .. '    ' .. _('col_plays') .. ' ' .. b.plays
    end
  end
  if #lines == 0 then lines[1] = _('No games played yet.') end
  show({ title = _('Records:'), lines = lines, rows = { { { _('Close'), close_modal } } }, cancel = close_modal })
end

local settings_box
settings_box = function()
  show({
    title = _('Settings'),
    rows = {
      { { _('Language') .. ': ' .. lang_name(settings.lang), function()
          local nxt = 1
          for k, l in ipairs(LANGS) do if l.code == settings.lang then nxt = k % #LANGS + 1 end end
          settings.lang = LANGS[nxt].code
          I18n.setActive(settings.lang)
          save_settings()
          settings_box()
        end } },
      { { (settings.always_new and '[x] ' or '[ ] ') .. _('Always start a new puzzle on open'), function()
          settings.always_new = not settings.always_new
          save_settings()
          settings_box()
        end } },
      { { _('Reset best results'), function()
          show({
            title = _('Reset all best results?'),
            rows = { { { _('Reset'), function() best = {}; save_best(); close_modal(); msg = _('Best results cleared.') end },
                       { _('Cancel'), close_modal } } },
            cancel = close_modal,
          })
        end } },
      { { _('Close'), close_modal } },
    },
    cancel = close_modal,
  })
end

------------------------------------------------------------------ drawing

local BUTTONS = { { 'New', function() new_puzzle() end }, { 'Size', size_box }, { 'Stats', stats_box }, { 'Settings', settings_box } }
local function button_rect(k)
  local bw = math.floor((W - 24 - 3 * 8) / 4)
  return 12 + (k - 1) * (bw + 8), BTN_Y, bw, BTN_H
end

local function draw_board(gg)
  local n = game:getSize()
  local tile = BOARD_W // n
  local grid = game:getGrid()
  local f = font('large')
  for r = 1, n do
    for c = 1, n do
      local v = grid[r][c]
      local x, y = BOARD_X + (c - 1) * tile, BOARD_Y + (r - 1) * tile
      if v ~= 0 then
        local home = v == (r - 1) * n + c
        gg:rect(x + 3, y + 3, tile - 6, tile - 6, { line_width = 3 })
        if home then
          -- in its final place: a second frame inside (the plugin inverts the tile, but a black
          -- tile ghosts on e-ink and this host ignores a white text colour). A sixth of the tile in
          -- from the edge, so it stands apart from the border; it still clears the number on 7x7.
          local inset = math.max(10, tile // 6)
          gg:rect(x + inset, y + inset, tile - 2 * inset, tile - 2 * inset, { line_width = 3 })
        end
        local s = tostring(v)
        local tx = x + math.floor((tile - width(f, s)) / 2)
        local ty = y + math.floor((tile - line_h('large')) / 2)
        local opts = { font = f }
        gg:text(tx, ty, s, opts)
        gg:text(tx + 1, ty, s, opts)                     -- bold: twice, one pixel apart
      end
    end
  end
  gg:rect(BOARD_X - 2, BOARD_Y - 2, tile * n + 4, tile * n + 4, { line_width = 2 })
end

local function draw_header(gg)
  local n = game:getSize()
  gg:text(12, 12, short(T(_('%1x%1 Puzzle    Moves: %2    Time: %3'), n, game:getMoves(), fmt_time(game:getElapsed())), 60),
    { font = font('small') })
  local b = best[n]
  local bs = (b and b.time) and T(_('Best: %1    Fewest moves: %2'), fmt_time(b.time), b.moves or '-') or _('Best: not set yet')
  gg:text(12, 40, short(bs, 60), { font = font('small') })
  gg:line(0, 72, W, 72)
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    gg:clear(0)
    draw_header(gg)
    if modal then draw_modal(gg); return end
    draw_board(gg)
    local m = msg or (game:isWon() and _('Solved! Tap "New" to play again.') or _('Tap a tile next to the gap, or swipe to slide.'))
    for i, l in ipairs(wrap(m, 'small', W - 24)) do
      if i <= 2 then gg:text(12, MSG_Y + (i - 1) * 22, l, { font = font('small') }) end
    end
    for k, b in ipairs(BUTTONS) do
      local x, y, bw, bh = button_rect(k)
      gg:rect(x, y, bw, bh, { line_width = 2 })
      local fm = font('medium')
      local label = _(b[1])
      while #label > 1 and width(fm, label) > bw - 10 do label = drop_last(label) end
      gg:text(x + math.floor((bw - width(fm, label)) / 2), y + 17, label, { font = fm })
    end
    if ERR then gg:text(12, H - 30, short('ERR ' .. ERR, 48), { font = font('small') }) end
  end)
  if not ok then pcall(function() gg:text(8, H - 60, short('draw ERR ' .. tostring(e), 46)) end) end
end

------------------------------------------------------------------ input

local KEY_GAP_MS = 250
local last_key, last_key_ms = nil, nil
local function key_accepted(ev)
  local ph = ev.phase or ev.action or ev.state
  if ph == 'up' or ph == 'release' or ph == 'released' or ev.pressed == false or ev.down == false then return false end
  local t = tonumber(ev.time_ms) or now_ms()
  if t and last_key == ev.key and last_key_ms and t - last_key_ms >= 0 and t - last_key_ms < KEY_GAP_MS then return false end
  last_key, last_key_ms = ev.key, t
  return true
end

local function tap(x, y)
  if modal then
    local _l, btns, my, mh = layout_modal(modal)
    for _k, bt in ipairs(btns) do
      if x >= bt.x and x < bt.x + bt.w and y >= bt.y and y < bt.y + bt.h then
        if bt.b[3] ~= false then bt.b[2]() end
        return
      end
    end
    if (y < my or y > my + mh) and modal.cancel then modal.cancel() end
    return
  end
  for k, b in ipairs(BUTTONS) do
    local bx, by, bw, bh = button_rect(k)
    if x >= bx and x < bx + bw and y >= by and y < by + bh then b[2](); return end
  end
  local n = game:getSize()
  local tile = BOARD_W // n
  if x >= BOARD_X and x < BOARD_X + tile * n and y >= BOARD_Y and y < BOARD_Y + tile * n then
    move_at((y - BOARD_Y) // tile + 1, (x - BOARD_X) // tile + 1)
  end
end

local SWIPES = { swipe_left = 'left', swipe_right = 'right', swipe_up = 'up', swipe_down = 'down' }

function on_input(c, ev)
  ERR = nil
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    if ev.type == 'pointer' and ev.phase == 'up' then
      if not modal and SWIPES[ev.gesture or ''] then slide(SWIPES[ev.gesture]) else tap(ev.x or 0, ev.y or 0) end
    elseif ev.type == 'key' and key_accepted(ev) then
      if modal then
        if ev.key == 'back' and modal.cancel then modal.cancel() end
      elseif ev.key == 'left' or ev.key == 'right' or ev.key == 'up' or ev.key == 'down' then
        slide(ev.key)
      end
    end
  end)
  if not ok then ERR = tostring(e) end
  refresh()
  return true
end

-- switch to size n: its saved puzzle, or a new one
new_or_resume = function(n)
  settings.size = n
  save_settings()
  game = load_game(n)
  last_ms = now_ms()
  msg = nil
  save_game()
end

function on_load(c)
  local s = kv(read('settings.txt'))
  settings.size = math.max(Game.getMinSize(), math.min(Game.getMaxSize(), tonumber(s.size) or 4))
  settings.lang = s.lang or 'en'
  settings.always_new = s.always_new == '1'
  I18n.setActive(settings.lang)
  load_best()
  math.randomseed(now_ms() or 1)
  new_or_resume(settings.size)
  save_game()
end

function on_leave()
  tick_time()
  save_game()
end
