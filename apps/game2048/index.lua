-- 2048 for XTOS Licorice mini apps (Lua API 0.8, 480 x 800 portrait, 1 bpp).
--
-- Rules follow CPR-vCodex's Game2048: slide every tile toward the chosen edge, merge each adjacent
-- equal pair once per move (nearest the edge first), add merged values to the score, then spawn a 2
-- (90%) or a 4 (10%) in a random empty cell. Game over when the board is full and no neighbours are
-- equal; reaching 2048 shows a message once and play continues.
--
-- Controls: swipe in any direction, or the side buttons for up / down. Tap "New game" to restart
-- (asks first). The Home pad leaves the app; the host saves ctx.state on leave, so the board, the
-- score and the best score come back on the next start.
--
-- Host facts this file relies on (docs in ../netprobe/README.md and x4pro-emu/docs/lua-apps.md):
-- g:text draws the ~24 px system font with y at the TOP of the line box; there is no filled shape,
-- so tile weight is shown with nested outlines; a frame keeps its first 1024 drawing commands
-- (this app uses well under 200); ctx.state is a persisted table the host hands back before on_load.

local SIZE = 4
local CELL, GAP = 105, 10
local BW = SIZE * CELL + (SIZE - 1) * GAP            -- 450
local BX = (480 - BW) // 2                           -- 15
local BY = 150
local BTN = { x = 140, y = 640, w = 200, h = 56 }    -- "New game"
local DLG = { x = 40, y = 300, w = 400, h = 220 }    -- confirm box (drawn instead of the board)
local YES = { x = 70, y = 440, w = 150, h = 56 }
local NO  = { x = 260, y = 440, w = 150, h = 56 }
local FULL_EVERY = 6                                 -- full e-ink refresh every N moves (ghosting)

local S                      -- ctx.state: board (16 ints, row-major, 0 = empty), score, best, won, over
local msg = nil              -- transient status line
local confirm = false        -- "Start a new game?" dialog is up
local moves_since_full = 0

------------------------------------------------------------------ rules (pure, no g / ctx)

-- Compacts a 4-cell line toward index 1 and merges each adjacent equal pair once.
-- Returns the new line, the points gained, and whether anything changed.
local function slide_line(line)
  local compact = {}
  for i = 1, SIZE do if line[i] ~= 0 then compact[#compact + 1] = line[i] end end
  local result, gained, i = {}, 0, 1
  while i <= #compact do
    if compact[i + 1] == compact[i] then
      local merged = compact[i] * 2
      result[#result + 1] = merged
      gained = gained + merged
      i = i + 2
    else
      result[#result + 1] = compact[i]
      i = i + 1
    end
  end
  for k = #result + 1, SIZE do result[k] = 0 end
  local changed = false
  for k = 1, SIZE do if result[k] ~= line[k] then changed = true end end
  return result, gained, changed
end

-- Slides the whole board toward (dr, dc), exactly one of them non-zero. Mutates board.
-- Returns changed, gained.
local function move(board, dr, dc)
  local changed, gained = false, 0
  for k = 0, SIZE - 1 do
    local idx = {}
    for i = 0, SIZE - 1 do                           -- i = 0 is the cell nearest the target edge
      local r, c
      if dc ~= 0 then r = k; c = (dc < 0) and i or (SIZE - 1 - i)
      else c = k; r = (dr < 0) and i or (SIZE - 1 - i) end
      idx[i + 1] = r * SIZE + c + 1
    end
    local line = {}
    for i = 1, SIZE do line[i] = board[idx[i]] end
    local res, got, ch = slide_line(line)
    if ch then
      changed = true
      for i = 1, SIZE do board[idx[i]] = res[i] end
    end
    gained = gained + got
  end
  return changed, gained
end

-- Puts a 2 (90%) or a 4 (10%) into a random empty cell; nothing when the board is full.
local function spawn(board)
  local empty = {}
  for i = 1, SIZE * SIZE do if board[i] == 0 then empty[#empty + 1] = i end end
  if #empty == 0 then return false end
  local at = empty[math.random(#empty)]
  board[at] = (math.random(10) == 1) and 4 or 2
  return true
end

local function game_over(board)
  for i = 1, SIZE * SIZE do if board[i] == 0 then return false end end
  for r = 0, SIZE - 1 do
    for c = 0, SIZE - 1 do
      local v = board[r * SIZE + c + 1]
      if c + 1 < SIZE and board[r * SIZE + c + 2] == v then return false end
      if r + 1 < SIZE and board[(r + 1) * SIZE + c + 1] == v then return false end
    end
  end
  return true
end

local function has_won(board)
  for i = 1, SIZE * SIZE do if board[i] >= 2048 then return true end end
  return false
end

------------------------------------------------------------------ game state

local function new_game()
  S.board = {}
  for i = 1, SIZE * SIZE do S.board[i] = 0 end
  S.score = 0
  S.won = false
  S.over = false
  spawn(S.board); spawn(S.board)
  msg = 'New game'
  confirm = false
end

-- Accepts whatever the host handed back in ctx.state; starts fresh when it is not a board.
local function adopt_state(state)
  S = state
  if type(S.best) ~= 'number' then S.best = 0 end
  local ok = type(S.board) == 'table' and #S.board == SIZE * SIZE
  if ok then
    for i = 1, SIZE * SIZE do
      if math.type(S.board[i]) ~= 'integer' or S.board[i] < 0 then ok = false end
    end
  end
  if not ok or type(S.score) ~= 'number' then new_game() else msg = nil end
  if S.over then msg = 'Game over' end
end

local function do_move(dr, dc)
  if confirm or S.over then return end
  local changed, gained = move(S.board, dr, dc)
  if not changed then return end
  S.score = S.score + gained
  if S.score > S.best then S.best = S.score end
  spawn(S.board)
  msg = nil
  if not S.won and has_won(S.board) then S.won = true; msg = 'You reached 2048!' end
  if game_over(S.board) then S.over = true; msg = 'Game over' end
  moves_since_full = moves_since_full + 1
  if moves_since_full >= FULL_EVERY then
    moves_since_full = 0
    pcall(function() ctx:invalidate('full') end)
  end
  pcall(function() ctx:invalidate() end)
end

------------------------------------------------------------------ drawing

local function text_w(s)
  local ok, w = pcall(function() return ctx.fonts.medium:measure(s) end)   -- g:text's default font
  if ok and type(w) == 'number' and w > 0 then return w end
  return 13 * #s                                      -- the system font is about 13 px per glyph
end

-- Text centred on (cx, cy): the font's line box is ~24 px, y is its top.
local function ctext(cx, cy, s)
  g:text(cx - text_w(s) // 2, cy - 12, s)
end

local function rtext(right, y, s)
  g:text(right - text_w(s), y, s)
end

-- Outline thickness by tile value, kept light for e-ink (heavy black leaves ghosting): 1 to 3
-- nested outlines, plus a small corner mark from 128 up.
local function thickness(v)
  if v >= 32 then return 3 end
  if v >= 8 then return 2 end
  return 1
end

local function inside(b, x, y)
  return x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h
end

local function draw_board()
  for r = 0, SIZE - 1 do
    for c = 0, SIZE - 1 do
      local x = BX + c * (CELL + GAP)
      local y = BY + r * (CELL + GAP)
      local v = S.board[r * SIZE + c + 1]
      if v == 0 then
        g:rect(x, y, CELL, CELL)
      else
        for i = 0, thickness(v) - 1 do g:rect(x + i, y + i, CELL - 2 * i, CELL - 2 * i) end
        if v >= 128 then g:rect(x + 8, y + 8, 10, 10) end
        if v >= 1024 then g:rect(x + CELL - 18, y + 8, 10, 10) end
        ctext(x + CELL // 2, y + CELL // 2, tostring(v))
      end
    end
  end
end

local function draw_confirm()
  g:rect(DLG.x, DLG.y, DLG.w, DLG.h)
  g:rect(DLG.x + 2, DLG.y + 2, DLG.w - 4, DLG.h - 4)
  ctext(240, DLG.y + 50, 'Start a new game?')
  ctext(240, DLG.y + 90, 'Current progress will be lost.')
  g:rect(YES.x, YES.y, YES.w, YES.h); ctext(YES.x + YES.w // 2, YES.y + YES.h // 2, 'Yes')
  g:rect(NO.x, NO.y, NO.w, NO.h);     ctext(NO.x + NO.w // 2, NO.y + NO.h // 2, 'No')
end

-- the canvas comes as on_draw's second argument (API 2.x); the helpers draw on g
function on_draw(_, canvas)
  if canvas then g = canvas end
  g:clear(0)                                          -- own the whole frame, white
  g:text(BX, 36, '2048')
  rtext(480 - BX, 36, 'Score ' .. tostring(S.score))
  rtext(480 - BX, 72, 'Best ' .. tostring(S.best))
  g:line(BX, 112, 480 - BX, 112)

  if confirm then draw_confirm() else draw_board() end

  g:rect(BTN.x, BTN.y, BTN.w, BTN.h)
  ctext(BTN.x + BTN.w // 2, BTN.y + BTN.h // 2, 'New game')
  if msg then ctext(240, 722, msg) end
  g:line(BX, 752, 480 - BX, 752)
  ctext(240, 776, 'swipe or side buttons to move')
end

------------------------------------------------------------------ input and lifecycle

local function handle_tap(x, y)
  if confirm then
    if inside(YES, x, y) then new_game()
    elseif inside(NO, x, y) then confirm = false
    else return end
    pcall(function() ctx:invalidate('full') end)
    pcall(function() ctx:invalidate() end)
    return
  end
  if inside(BTN, x, y) then
    confirm = true
    pcall(function() ctx:invalidate() end)
  end
end

-- API 2.x sends pointer events (down / move / hold / up, the gesture on up); the older host sent
-- one touch event per gesture. Both become that touch event; nil for a pointer phase to skip
local function as_touch(ev)
  if ev.type ~= 'pointer' then return ev end
  if ev.phase ~= 'up' then return nil end
  local gs = ev.gesture
  if gs == 'double_tap' then gs = 'tap' end            -- the second of two quick taps
  return { type = 'touch', gesture = gs, x = ev.x, y = ev.y }
end

function on_input(_, ev)
  if type(ev) ~= 'table' then return false end
  ev = as_touch(ev)
  if not ev then return true end
  if ev.type == 'key' then
    local st = ev.phase or ev.state                    -- phase on API 2.x, state on the older host
    if st ~= nil and st ~= 'down' then return true end
    if ev.key == 'up' then do_move(-1, 0) elseif ev.key == 'down' then do_move(1, 0) end
    return true
  end
  if ev.type == 'touch' then
    local gs = ev.gesture
    if gs ~= 'tap' and ev.x == 0 and ev.y == 0 then return true end   -- a 7.6.8 glitch: tap as swipe_up at (0,0)
    if gs == 'swipe_left' then do_move(0, -1)
    elseif gs == 'swipe_right' then do_move(0, 1)
    elseif gs == 'swipe_up' then do_move(-1, 0)
    elseif gs == 'swipe_down' then do_move(1, 0)
    elseif gs == 'tap' then handle_tap(ev.x or 0, ev.y or 0)
    end
    return true
  end
  return false
end

function on_load(c)
  c = c or ctx
  pcall(function() math.randomseed(ctx.clock:millis() + ctx.clock:now().epoch_sec) end)
  if type(c.state) ~= 'table' then c.state = {} end
  adopt_state(c.state)
end

function on_leave()
  -- ctx.state is saved by the host on leave; S is that table, nothing to copy.
end

-- Test hook (LuaJIT smoke test on the PC): never set on the device.
if rawget(_G, '__TEST') then
  __TEST.api = { slide_line = slide_line, move = move, spawn = spawn, game_over = game_over,
                 has_won = has_won, new_game = new_game, state = function() return S end,
                 adopt_state = adopt_state }
end
