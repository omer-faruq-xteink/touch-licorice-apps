-- Klondike for XTOS Licorice, API 2.9 (uses tools/gamekit with its cards module, src/rules.lua).
--
-- The classic solitaire: build the four foundations up by suit from the aces; in the seven
-- columns cards go down in alternating colours, an empty column takes a king. Tap the stock to
-- turn cards (one or three at a time: Draw 1 / Draw 3, from the next deal on), and to turn the
-- waste over when the stock is empty. Tap a card to pick it up with the cards above it, then tap
-- where it goes; tap a picked card again to send it home or to the first place it fits. A column
-- left with face-down cards only turns its top one up. When nothing is hidden any more, Finish
-- sends every card home.
--
-- Hint shows a useful move (a card home, a move that turns up a hidden card, a waste card onto
-- a column), else the stock. Klondike deals hide cards, so this is advice, not a winning line.
-- Deals are numbered and reproducible. Cards: tools/gamekit/cards.lua (black suits solid, red
-- ones hollow); the columns are drawn as one frame each (the host draws ~1024 commands a screen).

local K = require('rules')
local C = require('cards')
local W, H = kit.W, kit.H
local CW, CH, GAP = 62, 84, 4
local X0 = (W - (7 * CW + 6 * GAP)) // 2
local SLOT_Y, TAB_Y = 100, 200
local BTN_Y, BTN_H = 704, 60
local TAB_BOTTOM = BTN_Y - 40
local DOWN_OFF = 10                    -- a face-down card's strip

local deal, draw_n, next_draw = 1, 1, 1
local pos = nil
local history = {}
local moves, draws_idle = 0, 0         -- draws since the last real move (Hint: going round in vain)
local sel, hint, msg = nil, nil, nil   -- sel = { from, fi, n }; hint = a move or 'draw'
local stats = { played = 0, won = 0 }
local ERR = nil

local function slot_x(k) return X0 + (k - 1) * (CW + GAP) end

-- how far apart a column's cards are, face down and face up, so the column fits
local function offsets(col)
  local n, down = #col.cards, col.down
  local up = n - down
  local avail = TAB_BOTTOM - TAB_Y - CH
  local upoff = 30
  if up > 1 then upoff = math.max(14, math.min(30, (avail - down * DOWN_OFF) // (up - 1))) end
  return DOWN_OFF, upoff
end
local function card_y(k, i)
  local col = pos.cols[k]
  local doff, uoff = offsets(col)
  if i <= col.down then return TAB_Y + (i - 1) * doff end
  return TAB_Y + col.down * doff + (i - col.down - 1) * uoff
end

------------------------------------------------------------------ storage

local function save()
  kit.write('game.txt', 'deal=' .. deal .. '\ndraw=' .. draw_n .. '\nnext_draw=' .. next_draw .. '\npos=' .. K.encode(pos) ..
    '\nmoves=' .. moves .. '\nplayed=' .. stats.played .. '\nwon=' .. stats.won)
end

local function start(d)
  deal, draw_n = d, next_draw
  pos = K.deal(d)
  history, moves, draws_idle, sel, hint, msg = {}, 0, 0, nil, nil, nil
  stats.played = stats.played + 1
  save()
end

local function load()
  local t = kit.kv(kit.read('game.txt'))
  stats.played, stats.won = tonumber(t.played) or 0, tonumber(t.won) or 0
  next_draw = tonumber(t.next_draw) == 3 and 3 or 1
  local p = t.pos and K.decode(t.pos)
  if p then
    deal, pos, moves = tonumber(t.deal) or 1, p, tonumber(t.moves) or 0
    draw_n = tonumber(t.draw) == 3 and 3 or 1
  else
    start(math.random(1, 1000000))
  end
end

------------------------------------------------------------------ play

local function snapshot()
  history[#history + 1] = K.encode(pos)
  if #history > 300 then table.remove(history, 1) end
end

local function won_box()
  stats.won = stats.won + 1
  kit.show({ title = 'Deal ' .. deal .. ' won!', lines = { moves .. ' moves.', 'Won ' .. stats.won .. ' of ' .. stats.played .. ' deals.' },
             rows = { { { 'New deal', function() kit.close(); start(math.random(1, 1000000)) end }, { 'Close', kit.close } } },
             cancel = kit.close })
end

local function do_move(m)
  snapshot()
  K.apply(pos, m)
  moves, draws_idle = moves + 1, 0
  sel, hint, msg = nil, nil, nil
  kit.moved()
  if K.won(pos) then won_box() end
  save()
end

local function do_draw()
  if #pos.stock == 0 and #pos.waste == 0 then msg = 'The stock is empty.'; return end
  snapshot()
  local what = K.draw(pos, draw_n)
  draws_idle = draws_idle + 1
  sel, hint, msg = nil, nil, (what == 'recycled') and 'The waste is the stock again.' or nil
  save()
end

local function undo()
  local e = table.remove(history)
  if not e then msg = 'Nothing to undo.'; return end
  pos = K.decode(e)
  moves = math.max(0, moves - 1)
  sel, hint, msg = nil, nil, nil
  save()
end

local function show_hint()
  sel = nil
  local h = K.hint(pos)
  -- drawing more than a full turn of the stock without a move in between: nothing helps any more
  local turn = (#pos.stock + #pos.waste) // draw_n + 2
  if h == 'draw' and draws_idle > turn then h = nil end
  hint = h
  if h == nil then msg = 'No useful move left: Undo or a new deal.'
  elseif h == 'draw' then msg = 'Hint: turn cards from the stock.'
  else msg = 'Hint: the framed card(s), to the framed place.' end
end

local function try_move(to, ti)
  local m = { from = sel.from, fi = sel.fi, n = sel.n, to = to, ti = ti }
  if K.legal(pos, m) then do_move(m); return true end
  return false
end

-- a picked card tapped again: home, else the first column it fits
local function auto_move()
  local c
  if sel.from == 'w' then c = pos.waste[#pos.waste]
  elseif sel.from == 'c' then local col = pos.cols[sel.fi].cards; c = col[#col - sel.n + 1] end
  if c and sel.n == 1 and sel.from ~= 'h' and try_move('h', C.suit(c)) then return end
  for t = 1, 7 do if #pos.cols[t].cards > 0 and try_move('c', t) then return end end
  for t = 1, 7 do if try_move('c', t) then return end end
  sel, msg = nil, 'No place for it.'
end

------------------------------------------------------------------ input

local BUTTONS = { 'Undo', 'Hint', 'New', 'Draw' }
local function button_rect(k)
  local bw = math.floor((W - 24 - 3 * 8) / 4)
  return 12 + (k - 1) * (bw + 8), BTN_Y, bw, BTN_H
end

local function press_button(k)
  if k == 1 then undo()
  elseif k == 2 then
    if K.can_finish(pos) then snapshot(); K.finish(pos); moves = moves + 1; if K.won(pos) then won_box() end; save()
    else show_hint() end
  elseif k == 3 then
    kit.show({ title = 'New deal', lines = { 'Deal ' .. deal .. ' now; Draw ' .. next_draw .. ' for the next one.' },
               rows = { { { 'Random', function() kit.close(); start(math.random(1, 1000000)) end },
                          { 'Restart', function() kit.close(); pos = K.deal(deal); draw_n = next_draw; history, moves, draws_idle, sel, hint = {}, 0, 0, nil, nil; save() end } },
                        { { 'Number...', function()
                              kit.close()
                              ctx.input:text({ title = 'Deal number (1-1000000)', value = tostring(deal) }, function(c, s)
                                local n = tonumber(s)
                                if n and n >= 1 and n <= 1000000 then start(math.floor(n)) end
                                kit.refresh()
                              end)
                            end },
                          { 'Cancel', kit.close } } },
               cancel = kit.close })
  else
    next_draw = next_draw == 1 and 3 or 1
    msg = 'Draw ' .. next_draw .. ' from the next deal (New).'
    save()
  end
end

local function tap(x, y)
  if kit.tap_modal(x, y) then return end
  for k = 1, 4 do
    local bx, by, bw, bh = button_rect(k)
    if x >= bx and x < bx + bw and y >= by and y < by + bh then press_button(k); return end
  end
  local k = (x - X0) // (CW + GAP) + 1
  if k < 1 or k > 7 then sel = nil; return end
  if y >= SLOT_Y and y < SLOT_Y + CH then
    if k == 1 then do_draw(); return end
    if k == 2 or k == 3 then
      if sel and sel.from == 'w' then auto_move()
      elseif #pos.waste > 0 then sel, hint, msg = { from = 'w', n = 1 }, nil, nil end
      return
    end
    local s = k - 4                                         -- a foundation
    if sel then
      if not try_move('h', s) then sel, msg = nil, 'That card cannot go home yet.' end
    elseif pos.home[s] > 0 then
      sel, hint, msg = { from = 'h', fi = s, n = 1 }, nil, nil
    end
    return
  end
  if y >= TAB_Y and y < H - 100 then
    local col = pos.cols[k]
    if sel then
      if sel.from == 'c' and sel.fi == k then auto_move(); return end
      if try_move('c', k) then return end
      sel, msg = nil, 'It does not fit there.'
      return
    end
    if #col.cards == 0 then return end
    -- the tapped card: the last one whose top is above the tap
    local i = #col.cards
    while i > 1 and card_y(k, i) > y do i = i - 1 end
    if i <= col.down then msg = 'That card is face down.'; return end
    sel, hint, msg = { from = 'c', fi = k, n = #col.cards - i + 1 }, nil, nil
  end
end

------------------------------------------------------------------ drawing

local function draw_card(gg, c, x, y)
  gg:rect(x, y, CW, CH, { line_width = 1 })
  C.face(gg, c, x, y, CW, CH, true, kit.font('medium'))
end
local function draw_back(gg, x, y)
  gg:rect(x, y, CW, CH, { line_width = 2 })
  gg:rect(x + 6, y + 6, CW - 12, CH - 12, { line_width = 1 })
end
local function frame(gg, x, y, w, h, lw) gg:rect(x - 3, y - 3, w + 6, h + 6, { line_width = lw or 3 }) end

local function draw_column(gg, k)
  local col, x = pos.cols[k], slot_x(k)
  local n = #col.cards
  if n == 0 then gg:rect(x + 4, TAB_Y + 4, CW - 8, CH - 8, { line_width = 1 }); return end
  gg:rect(x, TAB_Y, CW, card_y(k, n) + CH - TAB_Y, { line_width = 1 })
  for i, c in ipairs(col.cards) do
    local y = card_y(k, i)
    if i > 1 then gg:line(x, y, x + CW - 1, y) end
    if i <= col.down then gg:rect(x + 6, y + 3, CW - 12, DOWN_OFF - 6, { fill = true })
    else C.face(gg, c, x, y, CW, CH, i == n, kit.font('medium')) end
  end
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    gg:clear(0)
    gg:text(12, 12, 'Klondike  ' .. deal, { font = kit.font('large') })
    gg:text(12, 52, 'Moves ' .. moves .. '    Won ' .. stats.won .. '/' .. stats.played .. '    Draw ' .. draw_n, { font = kit.font('small') })
    gg:line(0, 90, W, 90)
    if kit.modal() then kit.draw_modal(gg); return end
    -- stock, waste, foundations
    local sx = slot_x(1)
    if #pos.stock > 0 then
      draw_back(gg, sx, SLOT_Y)
      gg:text(sx + 10, SLOT_Y + CH // 2 - 10, tostring(#pos.stock), { font = kit.font('small') })
    else
      gg:rect(sx + 4, SLOT_Y + 4, CW - 8, CH - 8, { line_width = 1 })
      if #pos.waste > 0 then pcall(function() gg:circle(sx + CW // 2, SLOT_Y + CH // 2, 14) end) end
    end
    local shown = math.min(#pos.waste, draw_n)
    for i = 1, shown do
      local cc = pos.waste[#pos.waste - shown + i]
      local x = slot_x(2) + (i - 1) * 22
      if i < shown then
        gg:rect(x, SLOT_Y, 22, CH, { line_width = 1 })
        gg:text(x + 3, SLOT_Y + 2, C.RANKS[C.rank(cc)], { font = kit.font('small') })
        C.suit_sign(gg, C.suit(cc), x + 3, SLOT_Y + 26, 1.6)
      else
        draw_card(gg, cc, x, SLOT_Y)
      end
    end
    for s = 0, 3 do
      local x = slot_x(s + 4)
      if pos.home[s] > 0 then draw_card(gg, s * 13 + pos.home[s], x, SLOT_Y)
      else
        gg:rect(x, SLOT_Y, CW, CH, { line_width = 2 })
        C.suit_sign(gg, s, x + (CW - 32) // 2, SLOT_Y + (CH - 32) // 2, 3.2)
      end
    end
    for k = 1, 7 do draw_column(gg, k) end
    -- the picked cards, the hint
    local function mark(from, fi, n, lw)
      if from == 'w' then frame(gg, slot_x(2) + (math.min(#pos.waste, draw_n) - 1) * 22, SLOT_Y, CW, CH, lw)
      elseif from == 'h' then frame(gg, slot_x(fi + 4), SLOT_Y, CW, CH, lw)
      else
        local col = pos.cols[fi]
        local top = card_y(fi, #col.cards - n + 1)
        frame(gg, slot_x(fi), top, CW, card_y(fi, #col.cards) + CH - top, lw)
      end
    end
    if sel then mark(sel.from, sel.fi, sel.n, 4) end
    if hint == 'draw' then frame(gg, slot_x(1), SLOT_Y, CW, CH, 3)
    elseif hint then
      mark(hint.from, hint.fi, hint.n, 3)
      if hint.to == 'h' then frame(gg, slot_x(hint.ti + 4), SLOT_Y, CW, CH, 2)
      else
        local col = pos.cols[hint.ti]
        frame(gg, slot_x(hint.ti), #col.cards > 0 and card_y(hint.ti, #col.cards) or TAB_Y, CW, CH, 2)
      end
    end
    local m = msg or (sel and 'Tap where it goes (tap it again: auto).' or 'Tap the stock, or a card to pick it up.')
    gg:text(12, BTN_Y - 30, kit.short(m, 48), { font = kit.font('small') })
    for k, b in ipairs(BUTTONS) do
      local x, y, bw, bh = button_rect(k)
      local label = b
      if k == 2 and K.can_finish(pos) then label = 'Finish' end
      if k == 4 then label = 'Draw ' .. next_draw end
      kit.button(gg, x, y, bw, bh, label)
    end
    if ERR then gg:text(12, H - 30, kit.short('ERR ' .. ERR, 48), { font = kit.font('small') }) end
  end)
  if not ok then pcall(function() gg:text(8, H - 60, kit.short('draw ERR ' .. tostring(e), 46)) end) end
end

function on_input(c, ev)
  ERR = nil
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    if ev.type == 'pointer' and ev.phase == 'up' then tap(ev.x or 0, ev.y or 0)
    elseif ev.type == 'key' and kit.key_accepted(ev) then
      if kit.modal() then
        if ev.key == 'back' and kit.modal().cancel then kit.modal().cancel() end
      elseif ev.key == 'up' or ev.key == 'left' then undo()
      elseif ev.key == 'down' or ev.key == 'right' then do_draw() end
    end
  end)
  if not ok then ERR = tostring(e) end
  kit.refresh()
  return true
end

function on_load(c)
  math.randomseed(kit.now_ms() or 1)
  local ok, e = pcall(load)
  if not ok then ERR = tostring(e); start(1) end
end
function on_leave() pcall(save) end

if rawget(_G, '__TEST') then
  __TEST.api = { pos = function() return pos end, K = K, C = C, deal = function() return deal end, start = start,
                 sel = function() return sel end, hint = function() return hint end, moves = function() return moves end,
                 card_y = card_y, geometry = function() return X0, CW, GAP, SLOT_Y, TAB_Y, CH end,
                 draw_n = function() return draw_n end }
end
