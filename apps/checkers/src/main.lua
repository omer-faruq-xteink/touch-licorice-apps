-- Checkers for XTOS Licorice, API 2.0 (uses tools/gamekit): English checkers or Turkish draughts
-- (Dama), against the reader at four levels or two players on one reader. Tap a piece (its moves
-- are marked), then where it goes; a capture goes the whole way in one tap, and when two lines end
-- on the same square the longer one is played. Undo takes back your last move (and the reply),
-- Hint frames a good move, New game picks the rules, the opponent and your side.
--
-- rules.lua holds both rule sets, engine.lua the reader's player; as in Chess it thinks in a
-- coroutine resumed from ctx:after timers in slices of about 200 ms, on a copy of the position.
-- The game is kept as its moves in game.txt and replayed on the next start.

local R = require('rules')
local E = require('engine')

local W, H = kit.W, kit.H
local SQ = 56
local BX, BY = (W - 8 * SQ) // 2, 150
local BTN_Y, BTN_H = 704, 60
local SLICE_MS = 200

local variant = R.CHECKERS
local pos = R.new(variant)
local history = {}              -- { m, text } per move played
local keys = {}                 -- R.key of every position so far (the repetition rule)
local mode, level, me = 'ai', 2, 1   -- 'ai' or 'two'; E.LEVELS index; your side (1 moves first)
local sel, targets = nil, {}    -- the square picked and its legal moves
local hint, last = nil, nil     -- the move framed, the last move played
local result = nil              -- { r, why } once the game is over
local think = nil               -- { co, kind = 'move' or 'hint' } while the reader thinks
local msg, ERR = nil, nil

local RULES = { [R.CHECKERS] = 'Checkers', [R.DAMA] = 'Dama' }

------------------------------------------------------------------ the game

-- in checkers the dark men move first ("Black"); in Dama White does
local function side_name(s)
  if variant == R.CHECKERS then return s > 0 and 'Black' or 'White' end
  return s > 0 and 'White' or 'Black'
end

local function save()
  local t = {}
  for i, h in ipairs(history) do t[i] = h.text end
  kit.write('game.txt', 'variant=' .. variant .. '\nmode=' .. mode .. '\nlevel=' .. level .. '\nme=' .. me ..
    '\nmoves=' .. table.concat(t, ' '))
end

local function check_end()
  local r, why = R.outcome(pos, keys)
  result = r and { r = r, why = why } or nil
  if not result then return end
  if r == 0 then msg = 'Draw: ' .. why .. '.'
  elseif mode == 'ai' then msg = (r == me and 'You win!' or 'The reader wins.') .. ' (' .. why .. ')'
  else msg = side_name(r) .. ' wins (' .. why .. ').' end
end

local function play(m)
  R.make(pos, m)
  history[#history + 1] = { m = m, text = R.text(m) }
  keys[#keys + 1] = R.key(pos)
  last = m
  sel, targets, hint, msg = nil, {}, nil, nil
  check_end()
  kit.moved()
end

local start_thinking

local function after_move()
  save()
  if mode == 'ai' and not result and pos.side ~= me then start_thinking('move') end
end

local function new_game(v, m, lv, side)
  think = nil
  variant, mode, level, me = v, m, lv or level, side or 1
  pos = R.new(variant)
  history, keys = {}, { R.key(pos) }
  sel, targets, hint, last, result = nil, {}, nil, nil, nil
  if mode == 'ai' then
    msg = RULES[variant] .. ': you play ' .. side_name(me) .. ' against the reader (' .. E.LEVELS[level].name .. ').'
  else
    msg = RULES[variant] .. ', two players: ' .. side_name(1) .. ' starts.'
  end
  after_move()
end

local function undo()
  think = nil
  if #history == 0 then return end
  repeat
    local h = table.remove(history)
    R.unmake(pos, h.m)
    table.remove(keys)
  until #history == 0 or mode ~= 'ai' or pos.side == me
  last = history[#history] and history[#history].m or nil
  sel, targets, hint, result = nil, {}, nil, nil
  msg = 'Move taken back.'
  check_end()
  save()
  if mode == 'ai' and pos.side ~= me then start_thinking('move') end
end

local function load()
  local t = kit.kv(kit.read('game.txt'))
  if not t.mode then new_game(R.CHECKERS, 'ai', 2, 1); return end
  think = nil
  variant = t.variant == R.DAMA and R.DAMA or R.CHECKERS
  mode = t.mode == 'two' and 'two' or 'ai'
  level = E.LEVELS[tonumber(t.level) or 0] and tonumber(t.level) or 2
  me = tonumber(t.me) == -1 and -1 or 1
  pos = R.new(variant)
  history, keys = {}, { R.key(pos) }
  for s in (t.moves or ''):gmatch('%S+') do
    local m = R.find(pos, s)
    if not m then break end
    play(m)
  end
  sel, targets, hint = nil, {}, nil
  check_end()
  if not result then msg = nil end
  if mode == 'ai' and not result and pos.side ~= me then start_thinking('move') end
end

------------------------------------------------------------------ the reader thinking

local function step(c)
  local th = think
  if not th then return end
  local ok, best = coroutine.resume(th.co)
  if think ~= th then return end                     -- Undo or New game while it thought
  if not ok then think = nil; ERR = tostring(best); kit.refresh(); return end
  if coroutine.status(th.co) ~= 'dead' then
    pcall(function() ctx:after(1, step) end)
    return
  end
  think = nil
  if not best then kit.refresh(); return end
  -- best is a move of the copy: the same one in the real position, found by its text
  local m = R.find(pos, R.text(best))
  if not m then kit.refresh(); return end
  if th.kind == 'move' then
    play(m)
    save()
  else
    hint = m
    msg = 'Hint: ' .. R.text(m) .. '.'
  end
  kit.refresh()
end

start_thinking = function(kind)
  local copy = R.copy(pos)
  local lv = kind == 'hint' and 3 or level
  local limit = kind == 'hint' and 2000 or nil
  local co = coroutine.create(function()
    return E.think(copy, lv, { clock = function() return kit.now_ms() or 0 end, slice_ms = SLICE_MS, limit_ms = limit })
  end)
  think = { co = co, kind = kind }
  pcall(function() ctx:after(30, step) end)
end

------------------------------------------------------------------ drawing

local function flip() return mode == 'ai' and me < 0 end

local function square_xy(s)
  local r, c = R.row(s), R.col(s)
  if flip() then r, c = 7 - r, 7 - c end
  return BX + c * SQ, BY + (7 - r) * SQ
end

-- a man: White an outlined disc, Black a solid one; a king has a crown ring inside
local function draw_piece(gg, p, x, y)
  local cx, cy = x + SQ // 2, y + SQ // 2
  local white = (variant == R.CHECKERS) == (p < 0)
  if white then
    gg:circle(cx, cy, 21, { fill = true, color = 0 })
    gg:circle(cx, cy, 21, { line_width = 3 })
    gg:circle(cx, cy, 15, { line_width = 1 })
    if p == 2 or p == -2 then gg:circle(cx, cy, 8, { fill = true }) end
  else
    gg:circle(cx, cy, 21, { fill = true })
    if p == 2 or p == -2 then
      gg:circle(cx, cy, 11, { fill = true, color = 0 })
      gg:circle(cx, cy, 6, { fill = true })
    else
      gg:circle(cx, cy, 15, { line_width = 2, color = 0 })
    end
  end
end

local function corners(gg, s)
  local x, y = square_xy(s)
  local L, E2 = 14, SQ - 4
  for _j, c in ipairs({ { 0, 0, 0, 0 }, { SQ - L, 0, E2, 0 }, { 0, E2, 0, SQ - L }, { SQ - L, E2, E2, SQ - L } }) do
    gg:rect(x + c[1], y + c[2], L, 4, { fill = true })
    gg:rect(x + c[3], y + c[4], 4, L, { fill = true })
  end
end

local function draw_board(gg)
  for s = 1, 64 do
    local x, y = square_xy(s)
    if variant == R.CHECKERS then
      if R.dark(s) then gg:rect(x + 3, y + 3, SQ - 6, SQ - 6, { line_width = 1 }) end
    else
      gg:rect(x, y, SQ, SQ, { line_width = 1 })                -- Dama uses every square
    end
  end
  gg:rect(BX - 2, BY - 2, 8 * SQ + 4, 8 * SQ + 4, { line_width = 2 })
  if last then
    corners(gg, last.from); corners(gg, last.to)
    -- where the pieces were taken: a small cross
    for _k, s in ipairs(last.caps) do
      local x, y = square_xy(s)
      gg:line(x + 20, y + 20, x + SQ - 20, y + SQ - 20); gg:line(x + SQ - 20, y + 20, x + 20, y + SQ - 20)
    end
  end
  for s = 1, 64 do
    local p = pos.b[s]
    if p ~= 0 then local x, y = square_xy(s); draw_piece(gg, p, x, y) end
  end
  local small = kit.font('small')
  for k = 1, 8 do
    local file = flip() and 9 - k or k
    local rank = flip() and k or 9 - k
    gg:text(BX + (k - 1) * SQ + SQ // 2 - 4, BY + 8 * SQ + 4, ('abcdefgh'):sub(file, file), { font = small })
    gg:text(2, BY + (k - 1) * SQ + SQ // 2 - 10, tostring(rank), { font = small })
  end
  if sel then
    local x, y = square_xy(sel)
    gg:rect(x + 1, y + 1, SQ - 2, SQ - 2, { line_width = 4 })
    local seen = {}
    for _k, m in ipairs(targets) do
      if not seen[m.to] then
        seen[m.to] = true
        local tx, ty = square_xy(m.to)
        if #m.caps > 0 then gg:circle(tx + SQ // 2, ty + SQ // 2, 10, { line_width = 3 })
        else gg:circle(tx + SQ // 2, ty + SQ // 2, 7, { fill = true }) end
      end
    end
  end
  if hint then
    for _k, s in ipairs({ hint.from, hint.to }) do
      local x, y = square_xy(s)
      gg:rect(x + 1, y + 1, SQ - 2, SQ - 2, { line_width = 2 }); gg:rect(x + 6, y + 6, SQ - 12, SQ - 12, { line_width = 2 })
    end
  end
end

local function recent()
  local out = {}
  for i = math.max(1, #history - 3), #history do
    out[#out + 1] = ((i + 1) // 2) .. (i % 2 == 1 and '. ' or '... ') .. history[i].text
  end
  return table.concat(out, '   ')
end

local BUTTONS = { 'Undo', 'Hint', 'New game' }
local function button_rect(k)
  local bw = math.floor((W - 24 - 2 * 8) / 3)
  return 12 + (k - 1) * (bw + 8), BTN_Y, bw, BTN_H
end

local function status()
  if result then return result.r == 0 and 'Draw' or 'Game over' end
  local must = R.has_capture(pos) and ' (a capture)' or ''
  if mode == 'ai' then
    if think and think.kind == 'move' then return 'The reader is thinking…' end
    if pos.side == me then return 'Your move' .. must end
  end
  return side_name(pos.side) .. ' to move' .. must
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    gg:clear(0)
    gg:text(12, 12, RULES[variant], { font = kit.font('large') })
    local n = R.count(pos)
    local who = mode == 'ai' and ('You: ' .. side_name(me) .. '   reader: ' .. E.LEVELS[level].name) or 'Two players'
    gg:text(12, 52, kit.short(who .. '   pieces ' .. n[1] .. '-' .. n[-1], 48), { font = kit.font('small') })
    gg:line(0, 90, W, 90)
    if kit.modal() then kit.draw_modal(gg); return end
    gg:text(12, 106, status(), { font = kit.font('medium') })
    draw_board(gg)
    local lines = {}
    if #history > 0 then lines[#lines + 1] = recent() end
    if msg then for _k, l in ipairs(kit.wrap(msg, 'small', W - 24)) do lines[#lines + 1] = l end end
    for k, l in ipairs(lines) do
      if k > 3 then break end
      gg:text(12, BY + 8 * SQ + 30 + (k - 1) * 22, kit.short(l, 52), { font = kit.font('small') })
    end
    for k, b in ipairs(BUTTONS) do
      local x, y, bw, bh = button_rect(k)
      kit.button(gg, x, y, bw, bh, b)
    end
    if ERR then gg:text(12, H - 30, kit.short('ERR ' .. ERR, 48), { font = kit.font('small') }) end
  end)
  if not ok then pcall(function() gg:text(8, H - 60, kit.short('draw ERR ' .. tostring(e), 46)) end) end
end

------------------------------------------------------------------ input

local function square_at(x, y)
  if x < BX or x >= BX + 8 * SQ or y < BY or y >= BY + 8 * SQ then return nil end
  local c, r = (x - BX) // SQ, 7 - (y - BY) // SQ
  if flip() then r, c = 7 - r, 7 - c end
  return R.sq(r, c)
end

local function choose_side(v, lv)
  local first, second = (v == R.CHECKERS) and 'Black' or 'White', (v == R.CHECKERS) and 'White' or 'Black'
  kit.show({ title = 'Play as', lines = { RULES[v] .. ' against the reader, ' .. E.LEVELS[lv].name .. '. ' .. first .. ' moves first.' },
             rows = { { { first, function() kit.close(); new_game(v, 'ai', lv, 1) end },
                        { second, function() kit.close(); new_game(v, 'ai', lv, -1) end } },
                      { { 'Either', function() kit.close(); new_game(v, 'ai', lv, math.random(2) == 1 and 1 or -1) end } },
                      { { 'Cancel', kit.close } } },
             cancel = kit.close })
end

local function choose_opponent(v)
  local function lv(i) return { E.LEVELS[i].name, function() kit.close(); choose_side(v, i) end } end
  kit.show({ title = RULES[v], lines = { 'Play against the reader, or two players on one reader.' },
             rows = { { lv(1), lv(2) }, { lv(3), lv(4) },
                      { { 'Two players', function() kit.close(); new_game(v, 'two', level, 1) end } },
                      { { 'Cancel', kit.close } } },
             cancel = kit.close })
end

local function new_game_menu()
  kit.show({ title = 'New game', lines = { 'Checkers: diagonal moves on the dark squares. Dama (Turkish draughts): moves forward and sideways, the longest capture must be taken.' },
             rows = { { { 'Checkers', function() kit.close(); choose_opponent(R.CHECKERS) end },
                        { 'Dama', function() kit.close(); choose_opponent(R.DAMA) end } },
                      { { 'Cancel', kit.close } } },
             cancel = kit.close })
end

local function my_turn()
  if result or think then return false end
  return mode == 'two' or pos.side == me
end

local function tap(x, y)
  if kit.tap_modal(x, y) then return end
  for k = 1, 3 do
    local bx, by, bw, bh = button_rect(k)
    if x >= bx and x < bx + bw and y >= by and y < by + bh then
      if k == 1 then undo()
      elseif k == 2 then
        if my_turn() then msg = 'Looking for a good move…'; hint = nil; start_thinking('hint') end
      else new_game_menu() end
      return
    end
  end
  if not my_turn() then return end
  local s = square_at(x, y)
  if not s then sel, targets = nil, {}; return end
  local p = pos.b[s]
  if p ~= 0 and (p > 0) == (pos.side > 0) then
    if sel == s then sel, targets = nil, {}; return end
    local all = R.moves(pos)
    sel, targets = s, {}
    for _k, m in ipairs(all) do if m.from == s then targets[#targets + 1] = m end end
    if #targets == 0 then
      sel = nil
      msg = (#all > 0 and #all[1].caps > 0) and 'A capture must be made: pick a piece that can take.' or 'That piece cannot move.'
    else msg = nil end
  elseif sel then
    -- the move ending on that square; of several, the one taking the most
    local best
    for _k, m in ipairs(targets) do
      if m.to == s and (not best or #m.caps > #best.caps) then best = m end
    end
    if not best then sel, targets = nil, {}; return end
    play(best)
    after_move()
  end
end

function on_input(c, ev)
  ERR = nil
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    if ev.type == 'pointer' and ev.phase == 'up' then
      tap(ev.x or 0, ev.y or 0)
    elseif ev.type == 'key' and kit.key_accepted(ev) then
      if kit.modal() and ev.key == 'back' and kit.modal().cancel then kit.modal().cancel() end
    end
  end)
  if not ok then ERR = tostring(e) end
  kit.refresh()
  return true
end

function on_load(c)
  local ok, e = pcall(load)
  if not ok then ERR = tostring(e) end
end
function on_leave() think = nil; pcall(save) end

if rawget(_G, '__TEST') then
  __TEST.api = { pos = function() return pos end, R = R, E = E, square_xy = square_xy, history = function() return history end,
                 result = function() return result end, thinking = function() return think end,
                 mode = function() return mode end, me = function() return me end, level = function() return level end,
                 variant = function() return variant end, sel = function() return sel end, hint = function() return hint end,
                 set_position = function(v, key)
                   think = nil
                   variant = v
                   pos = R.from_key(v, key); history, keys = {}, { R.key(pos) }
                   sel, targets, hint, last, result, msg = nil, {}, nil, nil, nil, nil
                 end }
end
