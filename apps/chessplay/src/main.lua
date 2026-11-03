-- Chess for XTOS Licorice, API 2.9 (uses tools/gamekit): a whole game against the reader at four
-- levels, or two players on one reader. Tap a piece (its moves are marked), then a square; a pawn
-- reaching the last rank asks what it becomes. Undo takes back your last move (and the reply),
-- Hint frames a good move, New game picks the opponent and your side.
--
-- rules.lua holds the rules (legal moves, check, mate and the draws); engine.lua the reader's
-- player. It thinks in a coroutine resumed from ctx:after timers in slices of about 200 ms, on a
-- copy of the position, so callbacks stay under the host's limits and taps (Undo, New game) still
-- come through; nothing runs while it is your move. The game is kept as its moves in game.txt and
-- replayed on the next start.

local R = require('rules')
local E = require('engine')
local RUNS = require('pieces')

local W, H = kit.W, kit.H
local SQ = 56
local BX, BY = (W - 8 * SQ) // 2, 150
local BTN_Y, BTN_H = 704, 60
local SLICE_MS = 200

local pos = R.from_fen(R.START)
local history = {}              -- { m, u, san } per move played
local keys = {}                 -- R.key of every position so far (the repetition rule)
local mode, level, me = 'ai', 2, 1   -- 'ai' or 'two'; E.LEVELS index; your side (1 White, -1 Black)
local sel, targets = nil, {}    -- the square picked and its legal moves
local hint, last = nil, nil     -- { from, to } squares
local result = nil              -- { r, why } once the game is over
local think = nil               -- { co, kind = 'move' or 'hint' } while the reader thinks
local msg, ERR = nil, nil

local LETTER = { 'p', 'n', 'b', 'r', 'q', 'k' }

------------------------------------------------------------------ the game

local function save()
  local t = {}
  for i, h in ipairs(history) do t[i] = R.uci(h.m) end
  kit.write('game.txt', 'mode=' .. mode .. '\nlevel=' .. level .. '\nme=' .. me .. '\nmoves=' .. table.concat(t, ' '))
end

local function side_name(s) return s > 0 and 'White' or 'Black' end

local function check_end()
  local r, why = R.outcome(pos, keys)
  result = r and { r = r, why = why } or nil
  if not result then return end
  if r == 0 then msg = 'Draw: ' .. why .. '.'
  elseif mode == 'ai' then msg = (r == me and 'Checkmate. You win!' or 'Checkmate. The reader wins.')
  else msg = 'Checkmate. ' .. side_name(r) .. ' wins.' end
end

local function play(m)
  local san = R.san(pos, m)
  local u = R.make(pos, m)
  history[#history + 1] = { m = m, u = u, san = san }
  keys[#keys + 1] = R.key(pos)
  last = { R.move_from(m), R.move_to(m) }
  sel, targets, hint = nil, {}, nil
  msg = nil
  check_end()
  kit.moved()
end

local start_thinking

-- the reader's turn: start thinking once the frame with your move is up
local function after_move()
  save()
  if mode == 'ai' and not result and pos.side ~= me then start_thinking('move') end
end

local function new_game(m, lv, side)
  think = nil
  mode, level, me = m, lv or level, side or 1
  pos = R.from_fen(R.START)
  history, keys = {}, { R.key(pos) }
  sel, targets, hint, last, result, msg = nil, {}, nil, nil, nil, nil
  if mode == 'ai' then
    msg = 'You play ' .. side_name(me) .. ' against the reader (' .. E.LEVELS[level].name .. ').'
  else
    msg = 'Two players: White starts.'
  end
  after_move()
end

local function undo()
  think = nil
  if #history == 0 then return end
  -- against the reader: back to your move (your move and its reply); two players: one move
  repeat
    local h = table.remove(history)
    R.unmake(pos, h.m, h.u)
    table.remove(keys)
  until #history == 0 or mode ~= 'ai' or pos.side == me
  local h = history[#history]
  last = h and { R.move_from(h.m), R.move_to(h.m) } or nil
  sel, targets, hint, result = nil, {}, nil, nil
  msg = 'Move taken back.'
  check_end()
  save()
  if mode == 'ai' and pos.side ~= me then start_thinking('move') end
end

local function load()
  local t = kit.kv(kit.read('game.txt'))
  local m = t.mode == 'two' and 'two' or 'ai'
  local lv = tonumber(t.level)
  if not E.LEVELS[lv or 0] then lv = 2 end
  local side = tonumber(t.me) == -1 and -1 or 1
  if not t.mode then new_game('ai', 2, 1); return end
  think = nil
  mode, level, me = m, lv, side
  pos = R.from_fen(R.START)
  history, keys = {}, { R.key(pos) }
  for s in (t.moves or ''):gmatch('%S+') do
    local mv = R.from_uci(pos, s)
    if not mv then break end
    play(mv)
  end
  sel, targets, hint = nil, {}, nil
  check_end()
  if not result then msg = nil end
  if mode == 'ai' and not result and pos.side ~= me then start_thinking('move') end
end

------------------------------------------------------------------ the reader thinking

-- how deep the reader got and how long it took, the last 40 times: think.txt in the app's private
-- folder (XTApps/chessplay/files/ on the card), to tune the levels to the reader's speed
local function note_think(th, best, score, depth, nodes)
  local ms = (kit.now_ms() or 0) - th.started
  local line = string.format('%s level=%d depth=%s nodes=%s ms=%d score=%s move=%s', th.kind, th.level,
    tostring(depth), tostring(nodes), ms, tostring(score), best and R.uci(best) or '-')
  local old = kit.read('think.txt') or ''
  local lines = {}
  for l in old:gmatch('[^\n]+') do lines[#lines + 1] = l end
  lines[#lines + 1] = line
  while #lines > 40 do table.remove(lines, 1) end
  kit.write('think.txt', table.concat(lines, '\n') .. '\n')
end

local function step(c)
  local th = think
  if not th then return end
  local ok, best, score, depth, nodes = coroutine.resume(th.co)
  if think ~= th then return end                     -- Undo or New game while it thought
  if not ok then think = nil; ERR = tostring(best); kit.refresh(); return end
  if coroutine.status(th.co) ~= 'dead' then
    pcall(function() ctx:after(1, step) end)
    return
  end
  think = nil
  pcall(note_think, th, best, score, depth, nodes)
  if not best then kit.refresh(); return end
  -- best is a move of the copy: the same number in the real position
  if th.kind == 'move' then
    play(best)
    save()
  else
    hint = { R.move_from(best), R.move_to(best) }
    msg = 'Hint: ' .. R.san(pos, best) .. '.'
  end
  kit.refresh()
end

start_thinking = function(kind)
  local copy = R.from_fen(R.to_fen(pos))
  local lv = kind == 'hint' and 3 or level
  local limit = kind == 'hint' and 2000 or nil
  local co = coroutine.create(function()
    return E.think(copy, lv, { clock = function() return kit.now_ms() or 0 end, slice_ms = SLICE_MS, limit_ms = limit })
  end)
  think = { co = co, kind = kind, level = lv, started = kit.now_ms() or 0 }
  pcall(function() ctx:after(30, step) end)
end

------------------------------------------------------------------ drawing

local function square_xy(s)
  local f, r = R.file(s), R.rank(s)
  local flip = (mode == 'ai' and me < 0)
  if flip then f, r = 7 - f, 7 - r end
  return BX + f * SQ, BY + (7 - r) * SQ
end

local function draw_piece(gg, p, x, y)
  local key = LETTER[p > 0 and p or -p]
  if p > 0 then key = key:upper() end
  for _k, run in ipairs(RUNS[key] or {}) do
    gg:rect(x + (run[2] - 1) * 2, y + (run[1] - 1) * 2, (run[3] - run[2] + 1) * 2, run[4] * 2, { fill = true })
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
  for r = 0, 7 do
    for f = 0, 7 do
      local s = 21 + r * 10 + f
      local x, y = square_xy(s)
      if (f + r) % 2 == 0 then gg:rect(x + 3, y + 3, SQ - 6, SQ - 6, { line_width = 1 }) end      -- a dark square
      local p = pos.b[s]
      if p ~= 0 then draw_piece(gg, p, x + 8, y + 8) end
    end
  end
  gg:rect(BX - 2, BY - 2, 8 * SQ + 4, 8 * SQ + 4, { line_width = 2 })
  local small = kit.font('small')
  local flip = (mode == 'ai' and me < 0)
  for k = 1, 8 do
    local file = flip and 9 - k or k
    local rank = flip and k or 9 - k
    gg:text(BX + (k - 1) * SQ + SQ // 2 - 4, BY + 8 * SQ + 4, ('abcdefgh'):sub(file, file), { font = small })
    gg:text(2, BY + (k - 1) * SQ + SQ // 2 - 10, tostring(rank), { font = small })
  end
  if last then for _k, s in ipairs(last) do corners(gg, s) end end
  -- a king in check: a double frame
  if not result or result.why == 'checkmate' then
    if R.in_check(pos) then
      local x, y = square_xy(pos.king[pos.side])
      gg:rect(x + 1, y + 1, SQ - 2, SQ - 2, { line_width = 3 }); gg:rect(x + 7, y + 7, SQ - 14, SQ - 14, { line_width = 2 })
    end
  end
  if sel then
    local x, y = square_xy(sel)
    gg:rect(x + 1, y + 1, SQ - 2, SQ - 2, { line_width = 4 })
    -- where it can go: a dot on an empty square, a ring round a piece it takes
    local seen = {}
    for _k, m in ipairs(targets) do
      local t = R.move_to(m)
      if not seen[t] then
        seen[t] = true
        local tx, ty = square_xy(t)
        if pos.b[t] ~= 0 then gg:circle(tx + SQ // 2, ty + SQ // 2, SQ // 2 - 3, { line_width = 3 })
        else gg:circle(tx + SQ // 2, ty + SQ // 2, 7, { fill = true }) end
      end
    end
  end
  if hint then
    for _k, s in ipairs(hint) do
      local x, y = square_xy(s)
      gg:rect(x + 1, y + 1, SQ - 2, SQ - 2, { line_width = 2 }); gg:rect(x + 6, y + 6, SQ - 12, SQ - 12, { line_width = 2 })
    end
  end
end

-- the last moves, numbered: "11. Nf3 Nc6  12. Bb5"
local function recent()
  local out = {}
  local first = math.max(1, #history - 3)
  -- start on a White move when there is one before
  for i = first, #history do
    local n = (i + 1) // 2
    if i % 2 == 1 then out[#out + 1] = n .. '. ' .. history[i].san
    elseif i == first then out[#out + 1] = n .. '... ' .. history[i].san
    else out[#out] = out[#out] .. ' ' .. history[i].san end
  end
  return table.concat(out, '   ')
end

local BUTTONS = { 'Undo', 'Hint', 'New game' }
local function button_rect(k)
  local bw = math.floor((W - 24 - 2 * 8) / 3)
  return 12 + (k - 1) * (bw + 8), BTN_Y, bw, BTN_H
end

local function status()
  if result then return result.r == 0 and 'Draw' or 'Checkmate' end
  local check = R.in_check(pos) and ' (check)' or ''
  if mode == 'ai' then
    if think and think.kind == 'move' then return 'The reader is thinking…' end
    if pos.side == me then return 'Your move' .. check end
    return side_name(pos.side) .. ' to move' .. check
  end
  return side_name(pos.side) .. ' to move' .. check
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    gg:clear(0)
    gg:text(12, 12, 'Chess', { font = kit.font('large') })
    local who = mode == 'ai' and ('You: ' .. side_name(me) .. '   reader: ' .. E.LEVELS[level].name) or 'Two players'
    gg:text(12, 52, kit.short(who .. '   move ' .. pos.full, 48), { font = kit.font('small') })
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
  local f, r = (x - BX) // SQ, 7 - (y - BY) // SQ
  if mode == 'ai' and me < 0 then f, r = 7 - f, 7 - r end
  return 21 + r * 10 + f
end

local function choose_side(lv)
  kit.show({ title = 'Play as', lines = { 'Against the reader, ' .. E.LEVELS[lv].name .. '.' },
             rows = { { { 'White', function() kit.close(); new_game('ai', lv, 1) end },
                        { 'Black', function() kit.close(); new_game('ai', lv, -1) end } },
                      { { 'Either', function() kit.close(); new_game('ai', lv, math.random(2) == 1 and 1 or -1) end } },
                      { { 'Cancel', kit.close } } },
             cancel = kit.close })
end

local function new_game_menu()
  local function lv(i) return { E.LEVELS[i].name, function() kit.close(); choose_side(i) end } end
  kit.show({ title = 'New game', lines = { 'Play against the reader, or two players on one reader.' },
             rows = { { lv(1), lv(2) }, { lv(3), lv(4) },
                      { { 'Two players', function() kit.close(); new_game('two', level, 1) end } },
                      { { 'Cancel', kit.close } } },
             cancel = kit.close })
end

-- a pawn on the last rank: what it becomes
local function choose_promotion(list)
  local function pick(promo, label)
    return { label, function()
      kit.close()
      for _k, m in ipairs(list) do
        if R.move_promo(m) == promo then play(m); after_move(); return end
      end
    end }
  end
  kit.show({ title = 'Promote to', rows = { { pick(5, 'Queen'), pick(4, 'Rook') }, { pick(3, 'Bishop'), pick(2, 'Knight') },
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
    if sel == s then sel, targets = nil, {}
    else
      sel, targets = s, {}
      for _k, m in ipairs(R.legal(pos)) do if R.move_from(m) == s then targets[#targets + 1] = m end end
      msg = #targets == 0 and 'That piece cannot move.' or nil
    end
  elseif sel then
    local list = {}
    for _k, m in ipairs(targets) do if R.move_to(m) == s then list[#list + 1] = m end end
    if #list == 0 then sel, targets = nil, {}; return end
    if #list > 1 then choose_promotion(list); return end
    play(list[1])
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
                 result = function() return result end, thinking = function() return think end, step = step,
                 mode = function() return mode end, me = function() return me end, level = function() return level end,
                 new_game = new_game, sel = function() return sel end, hint = function() return hint end,
                 set_position = function(fen)
                   think = nil
                   pos = R.from_fen(fen); history, keys = {}, { R.key(pos) }
                   sel, targets, hint, last, result, msg = nil, {}, nil, nil, nil, nil
                 end }
end
