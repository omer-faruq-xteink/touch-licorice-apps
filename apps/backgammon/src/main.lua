-- Backgammon for XTOS Licorice (uses tools/gamekit): against the reader at four levels, or two
-- players on one reader. Single games or a match to 3, 5 or 7 points; a gammon counts 2, a
-- backgammon 3; the doubling cube is optional (off it plays like Turkish tavla), with the Crawford
-- rule in a match.
--
-- You are White, at the bottom, and move counter-clockwise: from 24 (top right) along the top,
-- down the left and along the bottom into your home board (bottom right), then off into the tray
-- on the right. Tap Roll; tap a checker (the bar first when you have one there), the points it
-- can reach with one die or several are marked; tap one. The turn ends when the dice are played.
-- Undo takes back a checker, or the whole last turn with the same dice (the dice that followed
-- come again, so undoing never changes the luck).
--
-- rules.lua: the rules and the plays of a roll; engine.lua: the reader's player, thinking in a
-- coroutine resumed from ctx:after timers in slices of about 200 ms as in Checkers and Chess.
-- The game is kept in game.txt as a snapshot of the board, the dice and the score.

local R = require('rules')
local E = require('engine')

local W, H = kit.W, kit.H
local PW = 34                                  -- a point's width
local LX, RX, BARX, BARW = 4, 244, 208, 36     -- left half, right half, the bar
local TRAYX, TRAYW = 450, 28
local BT, BB = 136, 616                        -- the board's top and bottom
local MID = (BT + BB) // 2
local TRI = 200                                -- a point's length
local CR, STEP = 15, 30                        -- a checker's radius, the stack step
local BTN_Y, BTN_H = 700, 60
local SLICE_MS = 200

-- the game
local b = R.new()
local side = 1                                 -- whose turn: 1 White (you), -1 Black
local phase = 'opening'                        -- opening, roll, move, over
local left, done, turn_moves = {}, {}, {}      -- dice left; steps of this turn (undo); its moves
local memo = {}                                -- R.most's memo for this turn
local shown = nil                              -- { d1, d2, side } the dice on the board
local rolls, replay, snaps = {}, {}, {}        -- rolls so far; rolls to come again after Undo; turn starts
-- the match
local mode, level, me = 'ai', 2, 1
local match_len, cube_on = 0, false            -- 0: single games
local score = { [1] = 0, [-1] = 0 }
local cube, owner = 1, 0
local crawford_game, crawford_used, crawford_next = false, false, false
local match_over = false
-- the screen
local sel, targets = nil, {}                   -- the own point picked (25 the bar) and { [to] = path }
local hint, last = nil, nil                    -- a play framed; { side, moves } the last play
local result = nil                             -- { w, pts, why } once a game is over
local think = nil
local msg, ERR = nil, nil

------------------------------------------------------------------ names and texts

local function name(s)
  if mode == 'ai' then return s == me and 'You' or 'The reader' end
  return s == 1 and 'White' or 'Black'
end

-- moves in the board's numbering (the numbers drawn along the edges)
local function mtext(moves, s)
  local t = {}
  for i, m in ipairs(moves) do
    local f = m[1] == 25 and 'bar' or tostring(R.point(s, m[1]))
    local to = m[2] == 0 and 'off' or tostring(R.point(s, m[2]))
    t[i] = f .. '/' .. to .. (m[3] and '*' or '')
  end
  return #t > 0 and table.concat(t, ' ') or 'no move'
end

local function human(s) return mode == 'two' or s == me end

------------------------------------------------------------------ keeping the game

local function save()
  local t = {
    'mode=' .. mode, 'level=' .. level, 'match=' .. match_len, 'cubeon=' .. (cube_on and 1 or 0),
    's1=' .. score[1], 's2=' .. score[-1], 'cube=' .. cube, 'owner=' .. owner,
    'crawford=' .. (crawford_game and 1 or 0) .. (crawford_used and 1 or 0) .. (crawford_next and 1 or 0),
    'over=' .. (match_over and 1 or 0), 'side=' .. side, 'phase=' .. phase, 'board=' .. R.key(b),
    'dice=' .. (shown and (shown[1] .. shown[2] .. (shown[3] == 1 and 'w' or 'b')) or ''),
    'left=' .. table.concat(left),
  }
  if result then t[#t + 1] = 'result=' .. result.w .. ',' .. result.pts .. ',' .. result.why end
  kit.write('game.txt', table.concat(t, '\n'))
end

------------------------------------------------------------------ dice and the cube

local function roll()
  local r
  if #replay > 0 then r = table.remove(replay, 1) else r = { math.random(6), math.random(6) } end
  rolls[#rolls + 1] = r
  return r[1], r[2]
end

local function can_double(s)
  return cube_on and phase == 'roll' and side == s and not crawford_game and cube < 64 and (owner == 0 or owner == s)
end

------------------------------------------------------------------ the turn

local start_thinking, end_game, reader_turn, menu, target_xy, source_xy

-- where the checker on own point `from` can go this turn: { [to] = path }, with one die or
-- several (the shortest path, then the one hitting most)
local function reach(from)
  local res = {}
  local function rec(cb, ds, from, path, start)
    local legal = R.legal(cb, side, ds, memo, start)
    for _k, m in ipairs(legal) do
      if m[1] == from then
        local p2 = table.move(path, 1, #path, 1, {})
        p2[#p2 + 1] = m
        local old = res[m[2]]
        local hits = 0
        for _j, x in ipairs(p2) do if x[3] then hits = hits + 1 end end
        if not old or #p2 < #old.path or (#p2 == #old.path and hits > old.hits) then res[m[2]] = { path = p2, hits = hits } end
        if m[2] ~= 0 then
          local c = R.copy(cb)
          R.step(c, side, m)
          local rest, gone = {}, false
          for _j, d in ipairs(ds) do if d == m[4] and not gone then gone = true else rest[#rest + 1] = d end end
          rec(c, rest, m[2], p2, false)
        end
      end
    end
  end
  rec(b, left, from, {}, #done == 0)
  local out = {}
  for to, v in pairs(res) do out[to] = v.path end
  return out
end

local function refresh_targets()
  targets = sel and reach(sel) or {}
end

local function any_target() return next(targets) ~= nil end

-- the own points (25 the bar) with a checker that can move now
local function sources()
  local out, seen = {}, {}
  for _k, m in ipairs(R.legal(b, side, left, memo, #done == 0)) do
    if not seen[m[1]] then seen[m[1]] = true; out[#out + 1] = m[1] end
  end
  return out
end

-- the start of a move phase: the dice are thrown
local function begin_move(d1, d2, keep_snap)
  shown = { d1, d2, side }
  left = R.dice_list(d1, d2)
  done, turn_moves, memo = {}, {}, {}
  sel, targets, hint = nil, {}, nil
  phase = 'move'
  if human(side) and not keep_snap then
    snaps[#snaps + 1] = { b = R.copy(b), side = side, d1 = d1, d2 = d2, cube = cube, owner = owner, nrolls = #rolls, last = last }
  end
end

local function end_turn()
  local s = side
  last = { side = s, moves = turn_moves }
  sel, targets, hint = nil, {}, nil
  if R.won(b, s) then
    end_game(s, R.result(b, s) * cube, R.result(b, s))
    return
  end
  side = -s
  phase = 'roll'
  left = {}
  save()
  if mode == 'ai' and side ~= me then reader_turn() end
end

-- after a step of a human turn: select the bar if a checker waits there, end the turn when done
local function after_step()
  if #left == 0 or R.most(b, side, left, memo) == 0 then
    msg = name(side) .. ' ' .. shown[1] .. '-' .. shown[2] .. ': ' .. mtext(turn_moves, side)
    end_turn()
    return
  end
  sel = nil
  if R.at(b, side, 25) > 0 then sel = 25 end
  refresh_targets()
  if sel and not any_target() then sel = nil end
end

local function human_rolled(d1, d2, keep_snap)
  begin_move(d1, d2, keep_snap)
  if R.most(b, side, left, memo) == 0 then
    msg = name(side) .. ' rolled ' .. d1 .. '-' .. d2 .. ': no move.'
    end_turn()
    return
  end
  msg = nil
  after_step()
end

local function play_path(path)
  done[#done + 1] = { b = R.copy(b), left = table.move(left, 1, #left, 1, {}), n = #turn_moves }
  for _k, m in ipairs(path) do
    R.step(b, side, m)
    turn_moves[#turn_moves + 1] = m
    for i, d in ipairs(left) do if d == m[4] then table.remove(left, i); break end end
  end
  hint = nil
  kit.moved()
  after_step()
end

------------------------------------------------------------------ the reader

local function reader_roll()
  local d1, d2 = roll()
  begin_move(d1, d2)
  if R.most(b, side, left, memo) == 0 then
    msg = 'The reader rolled ' .. d1 .. '-' .. d2 .. ': no move.'
    end_turn()
    return
  end
  start_thinking('move')
end

local function you_answer_double(s)
  -- side s doubled; the other side (a person) takes or passes
  local o = -s
  kit.show({ title = name(s) .. ' doubles to ' .. cube * 2,
             lines = { 'Take: play on for ' .. cube * 2 .. ' points (the cube is then ' .. (mode == 'ai' and 'yours' or 'with ' .. name(o)) .. ').',
                       'Pass: ' .. name(s) .. ' wins ' .. cube .. (cube == 1 and ' point' or ' points') .. ' now.' },
             rows = { { { 'Take', function()
                          kit.close()
                          cube, owner = cube * 2, o
                          msg = name(o) .. ' took: the cube is on ' .. cube .. '.'
                          save()
                          if mode == 'ai' and s ~= me then reader_roll() end
                        end },
                        { 'Pass', function() kit.close(); end_game(s, cube, 0) end } } } })
end

reader_turn = function()
  if phase ~= 'roll' or human(side) then return end
  if can_double(side) and E.should_double(b, side) then
    you_answer_double(side)
    return
  end
  reader_roll()
end

-- a callback may take 1 s; listing the plays of a double can take most of that on the reader
local function extend() pcall(function() ctx.budget:extend() end) end

local function step_think(c)
  local th = think
  if not th then return end
  extend()
  local ok, best = coroutine.resume(th.co)
  if think ~= th then return end
  if not ok then think = nil; ERR = tostring(best); kit.refresh(); return end
  if coroutine.status(th.co) ~= 'dead' then
    pcall(function() ctx:after(1, step_think) end)
    return
  end
  think = nil
  if th.kind == 'move' then
    for _k, m in ipairs(best or {}) do
      R.step(b, side, m)
      turn_moves[#turn_moves + 1] = m
    end
    left = {}
    msg = 'The reader ' .. shown[1] .. '-' .. shown[2] .. ': ' .. mtext(turn_moves, side)
    end_turn()
  else
    hint = best
    msg = 'Hint: ' .. mtext(best or {}, side)
  end
  kit.refresh()
end

start_thinking = function(kind)
  local copy = R.copy(b)
  local ds = table.move(left, 1, #left, 1, {})
  local lv = kind == 'hint' and 4 or level
  local limit = kind == 'hint' and 3000 or nil
  local s, start = side, #done == 0
  local co = coroutine.create(function()
    return E.think(copy, s, ds, lv, { clock = function() return kit.now_ms() or 0 end, slice_ms = SLICE_MS, limit_ms = limit, start = start })
  end)
  think = { co = co, kind = kind }
  pcall(function() ctx:after(30, step_think) end)
end

------------------------------------------------------------------ games and the match

local function fresh_game()
  b = R.new()
  side, phase = 1, 'opening'
  left, done, turn_moves, memo = {}, {}, {}, {}
  shown, rolls, replay, snaps = nil, {}, {}, {}
  cube, owner = 1, 0
  sel, targets, hint, last, result, think = nil, {}, nil, nil, nil, nil
  crawford_game = crawford_next
  if crawford_next then crawford_used = true end
  crawford_next = false
end

local function score_line()
  if mode == 'ai' then return 'You ' .. score[me] .. ', the reader ' .. score[-me] end
  return 'White ' .. score[1] .. ', Black ' .. score[-1]
end

local function next_game()
  kit.close()
  if match_over then
    score[1], score[-1], match_over, crawford_used, crawford_next = 0, 0, false, false, false
  end
  fresh_game()
  msg = (crawford_game and 'Crawford game: no doubling. ' or '') .. 'Tap Roll: the higher die starts.'
  save()
end

end_game = function(w, pts, kind)
  think = nil
  score[w] = score[w] + pts
  phase = 'over'
  local why = kind == 0 and 'the double was passed' or kind == 3 and 'a backgammon' or kind == 2 and 'a gammon' or 'a single game'
  result = { w = w, pts = pts, why = kind }
  local who = (mode == 'ai' and w == me) and 'You win' or (name(w) .. ' wins')
  local lines = { who .. ' ' .. pts .. (pts == 1 and ' point' or ' points') .. ' (' .. why .. (cube > 1 and ', cube ' .. cube or '') .. ').' }
  if match_len > 0 then
    if score[w] >= match_len then
      match_over = true
      lines[#lines + 1] = (mode == 'ai' and w == me and 'You win the match' or name(w) .. ' wins the match') .. ', ' .. score[w] .. '-' .. score[-w] .. '.'
    else
      if cube_on and not crawford_used and score[w] == match_len - 1 then crawford_next = true end
      lines[#lines + 1] = 'Match to ' .. match_len .. ': ' .. score_line() .. '.'
    end
  else
    lines[#lines + 1] = 'Points: ' .. score_line() .. '.'
  end
  msg = lines[1]
  save()
  kit.show({ title = 'Game over', lines = lines,
             rows = { { { match_over and 'New match' or 'Next game', next_game } }, { { 'Look at the board', kit.close } } },
             cancel = kit.close })
end

local function new_match(m, lv, len, cb)
  mode, level, match_len, cube_on = m, lv or level, len, cb
  score[1], score[-1] = 0, 0
  match_over, crawford_used, crawford_next = false, false, false
  me = 1
  fresh_game()
  msg = (match_len > 0 and ('Match to ' .. match_len .. '. ') or 'Single games. ') .. (cube_on and 'Doubling cube on. ' or '') ..
        'Tap Roll: the higher die starts.'
  save()
end

local function roll_opening()
  local a, c
  repeat a, c = roll() until a ~= c
  rolls = {}
  side = a > c and 1 or -1
  local first = a > c and a or c
  local second = a > c and c or a
  local m0
  if mode == 'ai' then
    m0 = 'Opening roll: you ' .. a .. ', the reader ' .. c .. '. ' .. (side == me and 'You start.' or 'The reader starts.')
  else
    m0 = 'Opening roll: White ' .. a .. ', Black ' .. c .. '. ' .. name(side) .. ' starts.'
  end
  if human(side) then
    human_rolled(first, second)
    if phase == 'move' then msg = m0 end
  else
    begin_move(first, second)
    start_thinking('move')
    msg = m0
  end
  save()
end

local function roll_turn()
  local d1, d2 = roll()
  human_rolled(d1, d2)
  save()
end

local function offer_double()
  if not can_double(side) then return end
  if mode == 'ai' then
    local take = E.should_take(b, -side)
    if take then
      cube, owner = cube * 2, -side
      msg = 'The reader takes: the cube is on ' .. cube .. '. Roll.'
      save()
    else
      msg = 'The reader passes.'
      end_game(side, cube, 0)
    end
  else
    you_answer_double(side)
  end
end

-- back to the start of the last turn a person played, with the same dice
local function restore(sn)
  local back = {}
  for i = sn.nrolls + 1, #rolls do back[#back + 1] = rolls[i] end
  for i = #rolls, sn.nrolls + 1, -1 do rolls[i] = nil end
  for i = #back, 1, -1 do table.insert(replay, 1, back[i]) end
  think = nil
  kit.close()
  b, side, cube, owner, last, result = R.copy(sn.b), sn.side, sn.cube, sn.owner, sn.last, nil
  human_rolled(sn.d1, sn.d2, true)
  msg = 'Turn taken back: the same dice again.'
end

local function undo()
  if phase == 'over' then return end
  if phase == 'move' and human(side) and #done > 0 then
    local d = table.remove(done)
    b, left = d.b, d.left
    for i = #turn_moves, d.n + 1, -1 do turn_moves[i] = nil end
    hint = nil
    msg = 'Move taken back.'
    after_step()
    return
  end
  if phase == 'move' and human(side) then
    if #snaps <= 1 then msg = 'Nothing to take back.'; return end
    table.remove(snaps)
  end
  local sn = snaps[#snaps]
  if not sn then msg = 'Nothing to take back.'; return end
  restore(sn)
  save()
end

------------------------------------------------------------------ loading

local function load()
  local t = kit.kv(kit.read('game.txt'))
  if not t.mode or not t.board or #t.board ~= 28 then new_match('ai', 2, 0, false); return end
  mode = t.mode == 'two' and 'two' or 'ai'
  level = E.LEVELS[tonumber(t.level) or 0] and tonumber(t.level) or 2
  match_len = tonumber(t.match) or 0
  cube_on = t.cubeon == '1'
  score[1], score[-1] = tonumber(t.s1) or 0, tonumber(t.s2) or 0
  cube, owner = tonumber(t.cube) or 1, tonumber(t.owner) or 0
  local cr = t.crawford or '000'
  crawford_game, crawford_used, crawford_next = cr:sub(1, 1) == '1', cr:sub(2, 2) == '1', cr:sub(3, 3) == '1'
  match_over = t.over == '1'
  side = tonumber(t.side) == -1 and -1 or 1
  phase = t.phase or 'roll'
  b = R.from_key(t.board)
  local d = t.dice or ''
  shown = #d == 3 and { tonumber(d:sub(1, 1)), tonumber(d:sub(2, 2)), d:sub(3, 3) == 'w' and 1 or -1 } or nil
  left = {}
  for ch in (t.left or ''):gmatch('%d') do left[#left + 1] = tonumber(ch) end
  done, turn_moves, memo, rolls, replay, snaps = {}, {}, {}, {}, {}, {}
  if t.result then
    local w, p, k = t.result:match('(-?%d+),(%d+),(%d+)')
    result = w and { w = tonumber(w), pts = tonumber(p), why = tonumber(k) } or nil
  end
  if phase == 'move' then
    if not shown or #left == 0 then phase = 'roll'
    elseif human(side) then
      sel = R.at(b, side, 25) > 0 and 25 or nil
      refresh_targets()
    else start_thinking('move') end
  end
  if phase == 'roll' and mode == 'ai' and side ~= me then reader_turn() end
end

------------------------------------------------------------------ drawing

-- a point's column (x of its left edge) and whether it is on the top row, by its board number
local function point_x(p)
  if p >= 19 then return RX + (p - 19) * PW, true end
  if p >= 13 then return LX + (p - 13) * PW, true end
  if p >= 7 then return LX + (12 - p) * PW, false end
  return RX + (6 - p) * PW, false
end

local function slot(p, k)
  local x, top = point_x(p)
  if k > 5 then k = 5 end
  return x + PW // 2, top and (BT + CR + 1 + k * STEP) or (BB - CR - 1 - k * STEP)
end

-- where a mark goes: the next free place on a point the mover can reach (the tray: its half), and
-- the top checker of a point (or the bar) it moves from
target_xy = function(to)
  if to == 0 then return TRAYX + TRAYW // 2, side == 1 and (MID + BB) // 2 or (BT + MID) // 2 end
  local p = R.point(side, to)
  local v = b[p]
  return slot(p, (v ~= 0 and (v > 0) == (side > 0)) and math.abs(v) or 0)
end
source_xy = function(f)
  if f == 25 then return BARX + BARW // 2, side == 1 and MID + 60 or MID - 60 end
  local p = R.point(side, f)
  return slot(p, math.max(math.min(math.abs(b[p]), 5) - 1, 0))
end

local function checker(gg, s, cx, cy)
  if s == 1 then
    gg:circle(cx, cy, CR, { fill = true, color = 0 })
    gg:circle(cx, cy, CR, { line_width = 2 })
    gg:circle(cx, cy, CR - 5, { line_width = 1 })
  else
    gg:circle(cx, cy, CR, { fill = true })
    gg:circle(cx, cy, CR - 5, { line_width = 1, color = 0 })
  end
end

local function draw_points(gg)
  local small = kit.font('small')
  for p = 1, 24 do
    local x, top = point_x(p)
    local y0, y1 = top and BT or BB, top and BT + TRI or BB - TRI
    gg:polygon({ x + 1, y0, x + PW - 1, y0, x + PW // 2, y1 }, { line_width = 1 })
    if p % 2 == 0 then gg:polygon({ x + 7, y0, x + PW - 7, y0, x + PW // 2, top and y1 - 40 or y1 + 40 }, { line_width = 1 }) end
    local label = tostring(p)
    gg:text(x + (PW - kit.width(small, label)) // 2, top and BT - 20 or BB + 2, label, { font = small })
  end
  gg:rect(LX - 2, BT, RX + 6 * PW - LX + 4, BB - BT, { line_width = 2 })
  gg:rect(BARX, BT, BARW, BB - BT, { line_width = 2 })
  gg:rect(TRAYX, BT, TRAYW, BB - BT, { line_width = 2 })
  gg:line(TRAYX, MID, TRAYX + TRAYW, MID)
end

local function draw_checkers(gg)
  local small = kit.font('small')
  for p = 1, 24 do
    local v = b[p]
    if v ~= 0 then
      local s, n = v > 0 and 1 or -1, math.abs(v)
      for k = 0, math.min(n, 5) - 1 do
        local cx, cy = slot(p, k)
        checker(gg, s, cx, cy)
      end
      if n > 5 then
        local cx, cy = slot(p, 5)
        local label = tostring(n)
        gg:text(cx - kit.width(small, label) // 2, cy - 10, label, { font = small })
      end
    end
  end
  -- the bar: White's below the middle, Black's above
  for _k, s in ipairs({ 1, -1 }) do
    local n = b[R.bar(s)]
    for k = 0, math.min(n, 3) - 1 do
      checker(gg, s, BARX + BARW // 2, s == 1 and (MID + 60 + k * STEP) or (MID - 60 - k * STEP))
    end
    if n > 3 then
      local label = tostring(n)
      gg:text(BARX + (BARW - kit.width(small, label)) // 2, s == 1 and MID + 60 + 3 * STEP - 10 or MID - 60 - 3 * STEP - 10, label, { font = small })
    end
  end
  -- borne off: thin bars in the tray, White's at the bottom
  for _k, s in ipairs({ 1, -1 }) do
    local n = b[R.off(s)]
    for k = 0, n - 1 do
      local y = s == 1 and (BB - 4 - (k + 1) * 9) or (BT + 4 + k * 9)
      if s == 1 then gg:rect(TRAYX + 3, y, TRAYW - 6, 7, { line_width = 1 })
      else gg:rect(TRAYX + 3, y, TRAYW - 6, 7, { fill = true }) end
    end
  end
end

local PIPS = { { 0 }, { -1, 1 }, { -1, 0, 1 }, { -1, -1, 1, 1 }, { -1, -1, 0, 1, 1 }, { -1, -1, -1, 1, 1, 1 } }
local PIPXY = {
  [1] = { { 0, 0 } }, [2] = { { -1, -1 }, { 1, 1 } }, [3] = { { -1, -1 }, { 0, 0 }, { 1, 1 } },
  [4] = { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }, [5] = { { -1, -1 }, { 1, -1 }, { 0, 0 }, { -1, 1 }, { 1, 1 } },
  [6] = { { -1, -1 }, { 1, -1 }, { -1, 0 }, { 1, 0 }, { -1, 1 }, { 1, 1 } },
}
-- a die; used: played already this turn (thin, small pips, struck through); past: the dice of
-- the turn before, plain
local function die(gg, x, y, n, used, past)
  local S = 44
  gg:rect(x, y, S, S, { radius = 6, line_width = (used or past) and 1 or 3 })
  local cx, cy = x + S // 2, y + S // 2
  for _k, p in ipairs(PIPXY[n]) do gg:circle(cx + p[1] * 11, cy + p[2] * 11, used and 3 or 5, { fill = true }) end
  if used then gg:line(x + 4, y + S - 4, x + S - 4, y + 4) end
end

local function draw_dice(gg)
  if not shown then return end
  local d1, d2, s = shown[1], shown[2], shown[3]
  local x0 = s == 1 and RX + 50 or LX + 50
  local y = MID - 22
  if phase ~= 'move' or side ~= s then
    die(gg, x0, y, d1, false, true)
    die(gg, x0 + 56, y, d2, false, true)
    return
  end
  local n_left = #left
  if d1 == d2 then
    die(gg, x0, y, d1, n_left < 3)
    die(gg, x0 + 56, y, d2, n_left < 1)
    if n_left > 0 then gg:text(x0 + 112, y + 10, 'x' .. n_left, { font = kit.font('small') }) end
  else
    local u1, u2 = true, true
    for _k, d in ipairs(left) do
      if d == d1 and u1 then u1 = false elseif d == d2 then u2 = false end
    end
    die(gg, x0, y, d1, u1)
    die(gg, x0 + 56, y, d2, u2)
  end
end

local function draw_cube(gg)
  if not cube_on then return end
  -- in the middle of the bar, or moved toward the side that owns it
  local y = owner == 0 and MID - 16 or owner == 1 and MID + 4 or MID - 36
  gg:rect(BARX + 3, y, BARW - 6, 32, { line_width = 2, radius = 4 })
  local label = tostring(cube == 1 and 64 or cube)
  local f = kit.font('small')
  gg:text(BARX + (BARW - kit.width(f, label)) // 2, y + 6, label, { font = f })
end

local function draw_marks(gg)
  -- the last play: a dot in each checker that moved
  if last and last.moves then
    for _k, m in ipairs(last.moves) do
      if m[2] ~= 0 then
        local p = R.point(last.side, m[2])
        local n = math.abs(b[p])
        if n > 0 and (b[p] > 0) == (last.side > 0) then
          local cx, cy = slot(p, math.min(n, 5) - 1)
          gg:circle(cx, cy, 4, { fill = true, color = last.side == 1 and 15 or 0 })
        end
      end
    end
  end
  -- the checker picked and where it can go
  if sel then
    local cx, cy = source_xy(sel)
    gg:circle(cx, cy, CR + 3, { line_width = 3 })
    for to, _path in pairs(targets) do
      if to == 0 then
        local y = side == 1 and MID + 4 or BT + 4
        gg:rect(TRAYX + 2, y, TRAYW - 4, MID - BT - 8, { line_width = 3 })
      else
        -- a square, so a mark is never taken for a checker
        local tx, ty = target_xy(to)
        gg:rect(tx - 12, ty - 12, 24, 24, { line_width = 3 })
        gg:rect(tx - 4, ty - 4, 8, 8, { fill = true })
      end
    end
  end
  -- a hint: rings on the points it moves from and to
  if hint then
    for _k, m in ipairs(hint) do
      for _j, i in ipairs({ m[1], m[2] }) do
        if i ~= 0 and i ~= 25 then
          local p = R.point(side, i)
          local x, top = point_x(p)
          gg:rect(x + 2, top and BT + 2 or BB - TRI - 2, PW - 4, TRI, { line_width = 2 })
        end
      end
    end
  end
end

local function buttons()
  local t = {}
  if phase == 'opening' then
    t = { { 'Roll', roll_opening } }
  elseif phase == 'roll' and human(side) then
    t = { { 'Roll', roll_turn } }
    if can_double(side) then t[#t + 1] = { 'Double', offer_double } end
    if #snaps > 0 then t[#t + 1] = { 'Undo', undo } end
  elseif phase == 'move' and human(side) and not think then
    t = { { 'Undo', undo }, { 'Hint', function() msg = 'Looking for a good play…'; hint = nil; start_thinking('hint') end } }
  elseif phase == 'over' then
    t = { { match_over and 'New match' or 'Next game', next_game } }
  end
  t[#t + 1] = { 'Menu', function() menu() end }
  return t
end

local function button_rect(k, n)
  local bw = (W - 24 - (n - 1) * 8) // n
  return 12 + (k - 1) * (bw + 8), BTN_Y, bw, BTN_H
end

local function status()
  if think and think.kind == 'move' then return 'The reader is thinking…' end
  if phase == 'opening' then return 'Roll to see who starts' end
  if phase == 'over' then return match_over and 'Match over' or 'Game over' end
  local who = (mode == 'ai' and side == me) and 'Your' or (name(side) .. "'s")
  if phase == 'roll' then return who .. ' turn: roll' .. (can_double(side) and ' or double' or '') end
  if shown then return who .. ' move: ' .. shown[1] .. '-' .. shown[2] end
  return who .. ' move'
end

-- the second line: the score, the pips and the cube, shortened to fit (the pips go first)
local function header(f)
  local sc = mode == 'ai' and ('You ' .. score[me] .. ', reader ' .. score[-me]) or ('White ' .. score[1] .. ', Black ' .. score[-1])
  local head = match_len > 0 and ('To ' .. match_len .. (crawford_game and ' (Crawford)' or '') .. ': ' .. sc) or sc
  local cube_t = (cube_on and cube > 1) and ('   cube ' .. cube) or ''
  local full = head .. '   pips ' .. R.pips(b, 1) .. '-' .. R.pips(b, -1) .. cube_t
  if kit.width(f, full) <= W - 24 then return full end
  return kit.short(head .. cube_t, 46)
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    gg:clear(0)
    gg:text(12, 8, 'Backgammon', { font = kit.font('large') })
    local lvl = mode == 'ai' and E.LEVELS[level].name or 'Two players'
    local f = kit.font('small')
    gg:text(W - 12 - kit.width(f, lvl), 18, lvl, { font = f })
    gg:text(12, 48, header(f), { font = f })
    gg:line(0, 78, W, 78)
    if kit.modal() then kit.draw_modal(gg); return end
    gg:text(12, 84, status(), { font = kit.font('medium') })
    draw_points(gg)
    draw_checkers(gg)
    draw_dice(gg)
    draw_cube(gg)
    draw_marks(gg)
    if msg then
      for k, l in ipairs(kit.wrap(msg, 'small', W - 24)) do
        if k > 2 then break end
        gg:text(12, 642 + (k - 1) * 24, l, { font = f })
      end
    end
    local bs = buttons()
    for k, bt in ipairs(bs) do
      local x, y, bw, bh = button_rect(k, #bs)
      kit.button(gg, x, y, bw, bh, bt[1])
    end
    if ERR then gg:text(12, H - 30, kit.short('ERR ' .. ERR, 48), { font = f }) end
  end)
  if not ok then pcall(function() gg:text(8, H - 60, kit.short('draw ERR ' .. tostring(e), 46)) end) end
end

------------------------------------------------------------------ menus

local LEVEL_NOTE = 'Beginner often plays at random; Easy and Medium pick the best-looking play; Hard also looks at every roll you could answer with (a few seconds).'

local function choose_cube(m, lv, len)
  kit.show({ title = 'Doubling cube', lines = { 'Without the cube it plays like Turkish tavla. With it, a side may double the stakes before its roll; the other side takes or passes.' },
             rows = { { { 'No cube', function() kit.close(); new_match(m, lv, len, false) end },
                        { 'Cube', function() kit.close(); new_match(m, lv, len, true) end } },
                      { { 'Cancel', kit.close } } },
             cancel = kit.close })
end

local function choose_length(m, lv)
  local function opt(label, n) return { label, function() kit.close(); choose_cube(m, lv, n) end } end
  kit.show({ title = 'Points', lines = { 'Single games keep a running score; a match ends when a side reaches its points. A gammon counts 2, a backgammon 3.' },
             rows = { { opt('Single games', 0), opt('3 points', 3) }, { opt('5 points', 5), opt('7 points', 7) },
                      { { 'Cancel', kit.close } } },
             cancel = kit.close })
end

local function new_game_menu()
  local function lv(i) return { E.LEVELS[i].name, function() kit.close(); choose_length('ai', i) end } end
  kit.show({ title = 'New match', lines = { LEVEL_NOTE },
             rows = { { lv(1), lv(2) }, { lv(3), lv(4) },
                      { { 'Two players', function() kit.close(); choose_length('two', level) end } },
                      { { 'Cancel', kit.close } } },
             cancel = kit.close })
end

local function help()
  kit.show({ title = 'How to play',
             lines = { 'You are White and move counter-clockwise: along the top from 24, down the left, along the bottom into your home board (1-6, bottom right), then off into the tray on the right.',
                       'Tap Roll, then a checker: the points it can reach are marked. A hit checker goes to the bar and must come in first.',
                       'Bear off once all 15 are home. Undo takes back a checker, or your last turn with the same dice.' },
             rows = { { { 'Close', kit.close } } }, cancel = kit.close })
end

menu = function()
  kit.show({ title = 'Backgammon', rows = { { { 'New match', function() kit.close(); new_game_menu() end } },
                                           { { 'How to play', function() kit.close(); help() end } },
                                           { { 'Close', kit.close } } }, cancel = kit.close })
end

------------------------------------------------------------------ input

local function spot_at(x, y)
  if y < BT or y >= BB then return nil end
  if x >= TRAYX then return 0 end
  if x >= BARX and x < BARX + BARW then return 25 end
  local top = y < MID
  local k, right
  if x >= LX and x < LX + 6 * PW then k, right = (x - LX) // PW, false
  elseif x >= RX and x < RX + 6 * PW then k, right = (x - RX) // PW, true
  else return nil end
  local p
  if top then p = right and 19 + k or 13 + k else p = right and 6 - k or 12 - k end
  return 26 + p                                        -- board points come back as 27..50
end

-- Taps forgive a near miss, as the points are narrow (34 px): with a checker picked, a tap on a
-- marked point, or within SNAP_T of its mark, plays it; a tap on a checker that can move, or
-- within SNAP_S of one of its checkers, picks it; a point only one checker can reach takes it
-- there; the picked checker tapped again moves with the higher die.
local SNAP_T, SNAP_S = 56, 26              -- the next point's checkers are 34 px away

local function nearest(list, xy, x, y, limit)
  local best, bd = nil, limit * limit
  for _k, key in ipairs(list) do
    local cx, cy = xy(key)
    local d = (cx - x) * (cx - x) + (cy - y) * (cy - y)
    if d <= bd then best, bd = key, d end
  end
  return best
end

-- how far a tap is from a stack: from its nearest checker (the bar: its first checker)
local function stack_dist(f, x, y)
  local tx, ty = source_xy(f)
  if f == 25 then return math.sqrt((tx - x) * (tx - x) + (ty - y) * (ty - y)) end
  local bx, by = slot(R.point(side, f), 0)
  local lo, hi = math.min(by, ty), math.max(by, ty)
  local cy = y < lo and lo or y > hi and hi or y
  return math.sqrt((tx - x) * (tx - x) + (cy - y) * (cy - y))
end

local function nearest_source(src, x, y)
  local best, bd = nil, SNAP_S
  for _k, f in ipairs(src) do
    local d = stack_dist(f, x, y)
    if d <= bd then best, bd = f, d end
  end
  return best
end

local function keys(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = k end
  table.sort(out)
  return out
end

local function pick(own)
  sel = own
  refresh_targets()
  msg = nil
end

local function play_now(path)
  sel, targets = nil, {}
  play_path(path)
end

local function tap_board(x, y)
  if phase ~= 'move' or not human(side) or think then return end
  local sp = spot_at(x, y)
  local own                                            -- the mover's own number of that spot
  if sp then own = (sp == 0 or sp == 25) and sp or R.point(side, sp - 26) end
  local src = sources()
  local is_src = {}
  for _k, f in ipairs(src) do is_src[f] = true end
  if sel then
    if own and own ~= sel and targets[own] then play_now(targets[own]); return end
    if own == sel then
      local best
      for _to, path in pairs(targets) do
        if #path == 1 and (not best or path[1][4] > best[1][4]) then best = path end
      end
      if best then play_now(best) else sel, targets = nil, {} end
      return
    end
    if own and is_src[own] then pick(own); return end
    local to = nearest(keys(targets), target_xy, x, y, SNAP_T)
    if to then play_now(targets[to]); return end
  end
  if own and is_src[own] then pick(own); return end
  local near = nearest_source(src, x, y)
  if near then pick(near); return end
  if own then
    local path, n = nil, 0
    for _k, f in ipairs(src) do
      local r = reach(f)
      if r[own] then n = n + 1; path = r[own] end
    end
    if n == 1 then play_now(path); return end
    if n > 1 then
      sel, targets = nil, {}
      msg = 'More than one checker can go there: tap the one to move.'
      return
    end
  end
  sel, targets = nil, {}
  if own and own ~= 0 and R.at(b, side, own) > 0 then
    msg = R.at(b, side, 25) > 0 and 'A checker on the bar must come in first.' or 'That checker cannot move with these dice.'
  end
end

local function tap(x, y)
  if kit.tap_modal(x, y) then return end
  if y >= BTN_Y and y < BTN_Y + BTN_H then
    local bs = buttons()
    for k, bt in ipairs(bs) do
      local bx, by, bw, bh = button_rect(k, #bs)
      if x >= bx and x < bx + bw then bt[2](); return end
    end
    return
  end
  tap_board(x, y)
end

function on_input(c, ev)
  ERR = nil
  extend()
  local handled = true
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    if ev.type == 'pointer' and ev.phase == 'up' then
      tap(ev.x or 0, ev.y or 0)
    elseif ev.type == 'key' and ev.key == 'back' then
      if ev.phase ~= nil and ev.phase ~= 'up' then return end
      if kit.modal() then
        if kit.modal().cancel then kit.modal().cancel() else kit.close() end
      elseif sel then sel, targets = nil, {}
      else handled = false end
    end
  end)
  if not ok then ERR = tostring(e) end
  kit.refresh()
  return handled
end

function on_load(c)
  extend()
  local ok, e = pcall(load)
  if not ok then ERR = tostring(e) end
end
function on_leave() pcall(save) end

if rawget(_G, '__TEST') then
  __TEST.api = { R = R, E = E, b = function() return b end, side = function() return side end, phase = function() return phase end,
                 left = function() return left end, sel = function() return sel end, targets = function() return targets end,
                 score = function() return score end, cube = function() return cube, owner end, slot = slot, point_x = point_x,
                 thinking = function() return think end, hint = function() return hint end, result = function() return result end,
                 msg = function() return msg end, snaps = function() return snaps end,
                 set = function(key, s, ph)                       -- a test position
                   think = nil; kit.close()
                   b = R.from_key(key); side = s or 1; phase = ph or 'roll'
                   left, done, turn_moves, memo, sel, targets, hint, result = {}, {}, {}, {}, nil, {}, nil, nil
                 end,
                 rig = function(list) replay = list end,          -- the next rolls, { {d1, d2}, ... }
                 new_match = new_match, mode = function() return mode end }
end
