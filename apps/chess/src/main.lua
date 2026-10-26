-- Chess puzzles for XTOS Licorice, API 2.9 (uses tools/gamekit).
--
-- Puzzles from the Lichess puzzle database (CC0), picked by make_banks.py into six banks in the
-- package's data section: Mate in 1, Mate in 2, Easy, Medium, Hard, Expert, each from easiest
-- to hardest. A line is "rating|FEN|moves|themes": the FEN is the position before the
-- opponent's move, the moves (UCI) are that move, then the solver's and the replies in turn.
--
-- The app checks the player's move against the solution, so it needs no move generator: it
-- only applies moves (castling, en passant and promotion included). Tap a piece, then its
-- square. Hint frames the piece, then the square; Show plays the move. The board turns so the
-- side to play is at the bottom. Pieces are drawn (the fonts may lack chess symbols): white
-- ones as outlines, black ones solid; dark squares have an inner frame.

local W, H = kit.W, kit.H
local SQ = 56
local BX, BY = (W - 8 * SQ) // 2, 150
local BTN_Y, BTN_H = 704, 60

local BANKS = {
  { file = 'mate1.txt', label = 'Mate in 1' }, { file = 'mate2.txt', label = 'Mate in 2' },
  { file = 'easy.txt', label = 'Easy' }, { file = 'medium.txt', label = 'Medium' },
  { file = 'hard.txt', label = 'Hard' }, { file = 'expert.txt', label = 'Expert' },
}

local PIECES = {
  k = { '.........##.........', '........####........', '.........##.........', '........####........', '.......######.......', '..####..####..####..', '.######.####.######.', '##################..', '####################', '####################', '.##################.', '..################..', '...##############...', '....############....', '....############....', '...##############...', '..################..', '..################..', '....................', '....................' },
  q = { '....................', '..##.....##.....##..', '..##....####....##..', '...#.....##.....#...', '...##....##....##...', '...###..####..###...', '...####.####.####...', '....############....', '....############....', '.....##########.....', '.....##########.....', '......########......', '.....##########.....', '....############....', '...##############...', '...##############...', '..################..', '..################..', '....................', '....................' },
  r = { '....................', '....................', '...###..####..###...', '...###..####..###...', '...##############...', '...##############...', '....############....', '.....##########.....', '.....##########.....', '.....##########.....', '.....##########.....', '.....##########.....', '.....##########.....', '....############....', '...##############...', '..################..', '..################..', '..################..', '....................', '....................' },
  b = { '....................', '.........##.........', '........####........', '........####........', '.......######.......', '......###.####......', '......##.#####......', '.....###.######.....', '.....##########.....', '.....##########.....', '......########......', '.......######.......', '......########......', '.......######.......', '......########......', '.....##########.....', '...##############...', '...##############...', '....................', '....................' },
  n = { '....................', '........##.##.......', '.......#######......', '......#########.....', '.....###.#######....', '....############....', '...##############...', '..######.#########..', '..#####...########..', '...###....########..', '..........#######...', '.........########...', '........########....', '.......#########....', '......##########....', '.....###########....', '....############....', '...##############...', '...##############...', '....................' },
  p = { '....................', '....................', '........####........', '.......######.......', '.......######.......', '.......######.......', '........####........', '......########......', '.......######.......', '........####........', '........####........', '.......######.......', '......########......', '.....##########.....', '....############....', '....############....', '...##############...', '...##############...', '....................', '....................' },
}

-- each piece as filled boxes { row, from, to, rows }: the runs of '#' in each row, a run that
-- repeats on the next rows becoming one taller box. Few boxes matter: the host draws about 1024
-- commands a screen and leaves out the rest.
local RUNS = {}
local function runs_of(rows)
  local out, open = {}, {}
  for r, row in ipairs(rows) do
    local here = {}
    local c = 1
    while c <= #row do
      if row:sub(c, c) == '#' then
        local e = c
        while e < #row and row:sub(e + 1, e + 1) == '#' do e = e + 1 end
        local key = c .. ':' .. e
        local box = open[key]
        if box and box[1] + box[4] == r then box[4] = box[4] + 1
        else box = { r, c, e, 1 }; out[#out + 1] = box end
        here[key] = box
        c = e + 1
      else
        c = c + 1
      end
    end
    open = here
  end
  return out
end
local function outline(rows)
  local h, w = #rows, #rows[1]
  local function on(r, c) return r >= 1 and r <= h and c >= 1 and c <= w and rows[r]:sub(c, c) == '#' end
  local out = {}
  for r = 1, h do
    local t = {}
    for c = 1, w do
      local edge = on(r, c) and not (on(r + 1, c) and on(r - 1, c) and on(r, c + 1) and on(r, c - 1))
      t[c] = edge and '#' or '.'
    end
    out[r] = table.concat(t)
  end
  return out
end
for k, rows in pairs(PIECES) do
  RUNS[k] = runs_of(rows)
  RUNS[k:upper()] = runs_of(outline(rows))
end

local bank = 1
local idx = {}                  -- bank -> puzzle number
local solved, clean = {}, {}    -- bank -> puzzles solved / solved without a mistake or Show
local count = {}                -- bank -> puzzles in it
local puzzle = nil              -- { rating, fen, moves = {}, themes }
local board, turn = {}, 'w'     -- board[1..64] (a1 = 1, h8 = 64): 'P', 'n', ... or nil
local ply = 1                   -- the next move of puzzle.moves to be made
local me = 'w'                  -- the side the player plays
local sel, last, hint = nil, nil, nil
local mistakes, shown = 0, false
local msg, ERR = nil, nil
local done = false

------------------------------------------------------------------ data

local function open_bank(file)
  local P = ctx.package
  if not P then return nil end
  local ok, r = pcall(function() return P:open_text(file, { max_bytes = 2000000, max_line_bytes = 512 }) end)
  if not ok or r == nil or type(r) == 'string' then return nil end
  return r
end

local function bank_count(k)
  if count[k] then return count[k] end
  local r = open_bank(BANKS[k].file)
  local n = 0
  if r then
    while true do
      local ok, l = pcall(function() return r:read_line() end)
      if not ok or l == nil then break end
      if l ~= '' then n = n + 1 end
    end
    pcall(function() r:close() end)
  end
  count[k] = n
  return n
end

local function read_puzzle(k, i)
  local r = open_bank(BANKS[k].file)
  if not r then return nil end
  local line
  for _j = 1, i do
    local ok, l = pcall(function() return r:read_line() end)
    if not ok or l == nil then line = nil; break end
    line = l
  end
  pcall(function() r:close() end)
  if not line then return nil end
  local rating, fen, moves, themes = line:match('^(%d+)|([^|]+)|([^|]+)|?(.*)$')
  if not rating then return nil end
  local p = { rating = tonumber(rating), fen = fen, moves = {}, themes = themes or '' }
  for m in moves:gmatch('%S+') do p.moves[#p.moves + 1] = m end
  return p
end

------------------------------------------------------------------ board

local FILES = 'abcdefgh'
local function sq(name) return (name:byte(2) - 49) * 8 + (name:byte(1) - 96) end    -- 'a1' -> 1
local function white(p) return p and p:upper() == p end

local function set_fen(fen)
  board = {}
  local rows, side = fen:match('^(%S+) (%a)')
  local r, f = 8, 1
  for ch in rows:gmatch('.') do
    if ch == '/' then r, f = r - 1, 1
    elseif ch:match('%d') then f = f + tonumber(ch)
    else board[(r - 1) * 8 + f] = ch; f = f + 1 end
  end
  turn = side
end

-- one UCI move: castling moves the rook too, en passant takes the pawn beside, promotion
local function apply(uci)
  local from, to = sq(uci:sub(1, 2)), sq(uci:sub(3, 4))
  local p = board[from]
  if not p then return end
  local df = (to - 1) % 8 - (from - 1) % 8
  if p:lower() == 'k' and math.abs(df) == 2 then
    local rook_from, rook_to = (df > 0) and (from + 3) or (from - 4), (df > 0) and (from + 1) or (from - 1)
    board[rook_to], board[rook_from] = board[rook_from], nil
  end
  if p:lower() == 'p' and df ~= 0 and not board[to] then
    board[to + (white(p) and -8 or 8)] = nil
  end
  board[to], board[from] = p, nil
  local promo = uci:sub(5, 5)
  if promo ~= '' then board[to] = white(p) and promo:upper() or promo:lower() end
  turn = turn == 'w' and 'b' or 'w'
  last = { from, to }
end

------------------------------------------------------------------ storage

local function save()
  local t = {}
  for k = 1, #BANKS do t[#t + 1] = k .. ':' .. (idx[k] or 1) .. ':' .. (solved[k] or 0) .. ':' .. (clean[k] or 0) end
  kit.write('state.txt', 'bank=' .. bank .. '\nbanks=' .. table.concat(t, ';') .. '\nply=' .. ply ..
    '\nmistakes=' .. mistakes .. '\nshown=' .. tostring(shown) .. '\ndone=' .. tostring(done))
end

local function start(k, i, keep_ply)
  bank = k
  local n = bank_count(k)
  if n == 0 then puzzle = nil; msg = 'No puzzles found in the package.'; return end
  i = ((i - 1) % n) + 1
  idx[k] = i
  puzzle = read_puzzle(k, i)
  if not puzzle then msg = 'Could not read puzzle ' .. i .. '.'; return end
  set_fen(puzzle.fen)
  me = turn == 'w' and 'b' or 'w'
  apply(puzzle.moves[1])
  ply, sel, hint, msg, mistakes, shown, done = 2, nil, nil, nil, 0, false, false
  -- a puzzle left half way: replay the moves made
  if keep_ply and keep_ply > 2 then
    while ply < keep_ply and puzzle.moves[ply] do apply(puzzle.moves[ply]); ply = ply + 1 end
  end
  save()
end

local function load()
  local t = kit.kv(kit.read('state.txt'))
  for ks, i, s, c in (t.banks or ''):gmatch('(%d+):(%d+):(%d+):(%d+)') do
    local k = tonumber(ks)
    if BANKS[k] then idx[k], solved[k], clean[k] = tonumber(i), tonumber(s), tonumber(c) end
  end
  local b = tonumber(t.bank) or 3
  if not BANKS[b] then b = 3 end
  start(b, idx[b] or 1, tonumber(t.ply))
  mistakes, shown = tonumber(t.mistakes) or 0, t.shown == 'true'
  done = t.done == 'true' and ply > #puzzle.moves
end

------------------------------------------------------------------ play

local function theme_words(s)
  local out = {}
  for th in s:gmatch('%S+') do
    out[#out + 1] = (th:gsub('(%l)(%u)', '%1 %2'):gsub('(%a)(%d)', '%1 %2'):lower())
  end
  return table.concat(out, ', ')
end

local function finish()
  done = true
  solved[bank] = (solved[bank] or 0) + 1
  if mistakes == 0 and not shown then clean[bank] = (clean[bank] or 0) + 1 end
  local how = shown and 'with help' or (mistakes == 0 and 'first try' or (mistakes .. ' wrong move' .. (mistakes > 1 and 's' or '')))
  msg = 'Solved (' .. how .. '). ' .. (puzzle.themes ~= '' and theme_words(puzzle.themes) or '')
  kit.moved()
end

-- the player's move matched (or was shown): play it, then the reply
local function play_mine()
  apply(puzzle.moves[ply])
  ply = ply + 1
  if puzzle.moves[ply] then apply(puzzle.moves[ply]); ply = ply + 1 end
  sel, hint = nil, nil
  if ply > #puzzle.moves then finish() else msg = 'Good. Your move again.' end
  save()
end

local function try_move(from, to)
  local want = puzzle.moves[ply]
  if want and from == sq(want:sub(1, 2)) and to == sq(want:sub(3, 4)) then
    play_mine()
  else
    mistakes = mistakes + 1
    sel = nil
    msg = 'Not the move. Try again.'
    save()
  end
end

local function show_hint()
  if done or not puzzle then return end
  local want = puzzle.moves[ply]
  if not hint then hint = { sq(want:sub(1, 2)) }; msg = 'Hint: move the framed piece.'
  else hint = { sq(want:sub(1, 2)), sq(want:sub(3, 4)) }; msg = 'Hint: from the framed square to the other.' end
end

------------------------------------------------------------------ drawing

local function square_xy(s)
  local f, r = (s - 1) % 8, (s - 1) // 8
  if me == 'b' then f, r = 7 - f, 7 - r end
  return BX + f * SQ, BY + (7 - r) * SQ
end

local function draw_piece(gg, p, x, y)
  for _k, run in ipairs(RUNS[p] or {}) do
    gg:rect(x + (run[2] - 1) * 2, y + (run[1] - 1) * 2, (run[3] - run[2] + 1) * 2, run[4] * 2, { fill = true })
  end
end

local function draw_board(gg)
  for s = 1, 64 do
    local x, y = square_xy(s)
    local f, r = (s - 1) % 8, (s - 1) // 8
    if (f + r) % 2 == 0 then gg:rect(x + 3, y + 3, SQ - 6, SQ - 6, { line_width = 1 }) end      -- a dark square
    local p = board[s]
    -- RUNS.k is the solid black king, RUNS.K its outline for the white one
    if p then draw_piece(gg, p, x + 8, y + 8) end
  end
  gg:rect(BX - 2, BY - 2, 8 * SQ + 4, 8 * SQ + 4, { line_width = 2 })
  local small = kit.font('small')
  for k = 1, 8 do
    local file = me == 'w' and k or 9 - k
    local rank = me == 'w' and (9 - k) or k
    gg:text(BX + (k - 1) * SQ + SQ // 2 - 4, BY + 8 * SQ + 4, FILES:sub(file, file), { font = small })
    gg:text(2, BY + (k - 1) * SQ + SQ // 2 - 10, tostring(rank), { font = small })
  end
  -- the last move: corner marks on its squares
  if last then
    for _k, s in ipairs(last) do
      local x, y = square_xy(s)
      local L, E = 14, SQ - 4
      for _j, c in ipairs({ { 0, 0, 0, 0 }, { SQ - L, 0, E, 0 }, { 0, E, 0, SQ - L }, { SQ - L, E, E, SQ - L } }) do
        gg:rect(x + c[1], y + c[2], L, 4, { fill = true })       -- the corner's level stroke
        gg:rect(x + c[3], y + c[4], 4, L, { fill = true })       -- and its upright one
      end
    end
  end
  if sel then local x, y = square_xy(sel); gg:rect(x + 1, y + 1, SQ - 2, SQ - 2, { line_width = 4 }) end
  if hint then
    for _k, s in ipairs(hint) do
      local x, y = square_xy(s)
      gg:rect(x + 1, y + 1, SQ - 2, SQ - 2, { line_width = 2 }); gg:rect(x + 6, y + 6, SQ - 12, SQ - 12, { line_width = 2 })
    end
  end
end

local BUTTONS = { 'Hint', 'Show', 'Next' }
local function button_rect(k)
  local bw = math.floor((W - 24 - 3 * 8) / 4)
  return 12 + (k - 1) * (bw + 8), BTN_Y, bw, BTN_H
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    gg:clear(0)
    gg:text(12, 12, 'Chess puzzles', { font = kit.font('large') })
    local n = bank_count(bank)
    gg:text(12, 52, kit.short(BANKS[bank].label .. '  ' .. (idx[bank] or 1) .. '/' .. n .. '    rating ' ..
      (puzzle and puzzle.rating or '-') .. '    solved ' .. (solved[bank] or 0), 48), { font = kit.font('small') })
    gg:line(0, 90, W, 90)
    if kit.modal() then kit.draw_modal(gg); return end
    if puzzle then
      local side = me == 'w' and 'White' or 'Black'
      gg:text(12, 106, done and 'Solved!' or (side .. ' to move: find the best move.'), { font = kit.font('medium') })
      draw_board(gg)
    end
    if msg then
      for k, l in ipairs(kit.wrap(msg, 'small', W - 24)) do
        if k > 2 then break end
        gg:text(12, BY + 8 * SQ + 30 + (k - 1) * 22, l, { font = kit.font('small') })
      end
    end
    for k, b in ipairs(BUTTONS) do
      local x, y, bw, bh = button_rect(k)
      kit.button(gg, x, y, bw, bh, b)
    end
    local x, y, bw, bh = button_rect(4)
    kit.button(gg, x, y, bw, bh, BANKS[bank].label, { font = 'small' })
    if ERR then gg:text(12, H - 30, kit.short('ERR ' .. ERR, 48), { font = kit.font('small') }) end
  end)
  if not ok then pcall(function() gg:text(8, H - 60, kit.short('draw ERR ' .. tostring(e), 46)) end) end
end

------------------------------------------------------------------ input

local function square_at(x, y)
  if x < BX or x >= BX + 8 * SQ or y < BY or y >= BY + 8 * SQ then return nil end
  local f, r = (x - BX) // SQ, 7 - (y - BY) // SQ
  if me == 'b' then f, r = 7 - f, 7 - r end
  return r * 8 + f + 1
end

local function tap(x, y)
  if kit.tap_modal(x, y) then return end
  for k = 1, 4 do
    local bx, by, bw, bh = button_rect(k)
    if x >= bx and x < bx + bw and y >= by and y < by + bh then
      if k == 1 then show_hint()
      elseif k == 2 then if not done and puzzle then shown = true; play_mine() end
      elseif k == 3 then start(bank, (idx[bank] or 1) + 1)
      else
        local rows = { {}, {} }
        for i, b in ipairs(BANKS) do
          local row = rows[i <= 3 and 1 or 2]
          row[#row + 1] = { b.label, function() kit.close(); save(); start(i, idx[i] or 1) end }
        end
        kit.show({ title = 'Puzzles', lines = { 'From the Lichess puzzle database, easiest first.' },
                   rows = { rows[1], rows[2], { { 'Cancel', kit.close } } }, cancel = kit.close })
      end
      return
    end
  end
  if done or not puzzle then return end
  local s = square_at(x, y)
  if not s then sel = nil; return end
  local p = board[s]
  if p and white(p) == (me == 'w') then
    sel = (sel == s) and nil or s
    msg = nil
  elseif sel then
    try_move(sel, s)
  end
end

function on_input(c, ev)
  ERR = nil
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    if ev.type == 'pointer' and ev.phase == 'up' then
      tap(ev.x or 0, ev.y or 0)
    elseif ev.type == 'key' and kit.key_accepted(ev) then
      if kit.modal() then
        if ev.key == 'back' and kit.modal().cancel then kit.modal().cancel() end
      elseif ev.key == 'down' or ev.key == 'right' then start(bank, (idx[bank] or 1) + 1)
      elseif ev.key == 'up' or ev.key == 'left' then start(bank, math.max(1, (idx[bank] or 1) - 1)) end
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
function on_leave() pcall(save) end

if rawget(_G, '__TEST') then
  __TEST.api = { board = function() return board end, puzzle = function() return puzzle end, ply = function() return ply end,
                 me = function() return me end, done = function() return done end, bank = function() return bank end,
                 idx = function() return idx end, sq = sq, square_xy = square_xy, set_fen = set_fen, apply = apply,
                 solved = function() return solved end, clean = function() return clean end, start = start,
                 hint = function() return hint end }
end
