-- FreeCell for XTOS Licorice, API 2.9 (uses tools/gamekit and src/rules.lua).
--
-- Microsoft's numbered deals (1 to 32000); the cards that no other card can need go home by
-- themselves. Tap a card to pick it up with the cards above it (as many as the free cells and
-- empty columns allow), then tap where it goes: a column, a free cell, its foundation. Tap a
-- picked card again to send it home or to the first place it fits.
--
-- Hint: deals 1 to 1000 come with a solution (data/sol00.txt ..., made by make_solutions.py with
-- these rules), so Hint shows a move of a winning line; the line is recognised again after moves
-- made in another order. Off the line, Hint offers to undo back to it.
--
-- Cards are drawn, not printed (the fonts may lack the suit signs): clubs and spades solid,
-- diamonds and hearts hollow, each sign a polyline and a few boxes (the host draws at most
-- about 1024 commands a screen).

local R = require('rules')
local W, H = kit.W, kit.H
local CW, CH, GAP = 54, 76, 4
local X0 = (W - (8 * CW + 7 * GAP)) // 2
local SLOT_Y, TAB_Y = 100, 190
local BTN_Y, BTN_H = 704, 60
local TAB_BOTTOM = BTN_Y - 40
local SOLVED_DEALS = 1000

local deal = 1
local pos = nil
local history = {}
local moves = 0
local sel = nil                  -- { from = 'c' | 'f', i, n }
local hint = nil                 -- { move }
local msg = nil
local stats = { played = 0, won = 0 }
local line = nil                 -- { deal, moves = {...}, map = key -> step }
local ERR = nil

------------------------------------------------------------------ suits

-- A suit sign is one polyline outline in a 0..10 box; clubs and spades also get a few filled
-- boxes so they read solid. Few draw commands matter: the host draws at most about 1024 per
-- screen (the rest of the screen is simply left out), and 52 cards each carry a sign.
local SUITS = {
  [0] = { { 5, 0, 6.8, 0.6, 7.4, 2.4, 6.6, 4.2, 8.6, 3.6, 10, 4.8, 10, 6.6, 8.6, 7.8, 6.4, 7.2, 6.8, 10, 3.2, 10, 3.6, 7.2,
            1.4, 7.8, 0, 6.6, 0, 4.8, 1.4, 3.6, 3.4, 4.2, 2.6, 2.4, 3.2, 0.6, 5, 0 },
          { { 3.6, 0.8, 6.4, 3.8 }, { 1.0, 4.6, 3.8, 7.0 }, { 6.2, 4.6, 9.0, 7.0 }, { 4.4, 3.8, 5.6, 9.8 } } },     -- clubs
  [1] = { { 5, 0, 9, 5, 5, 10, 1, 5, 5, 0 }, {} },                                                                -- diamonds
  [2] = { { 5, 2.5, 3.8, 0.6, 2, 0, 0.4, 1, 0, 3, 0.8, 5.2, 5, 10, 9.2, 5.2, 10, 3, 9.6, 1, 8, 0, 6.2, 0.6, 5, 2.5 }, {} },  -- hearts
  [3] = { { 5, 0, 8.6, 3.6, 10, 5.6, 9.6, 7.4, 8, 8.2, 6.2, 7.4, 6.6, 10, 3.4, 10, 3.8, 7.4, 2, 8.2, 0.4, 7.4, 0, 5.6,
            1.4, 3.6, 5, 0 },
          { { 3.8, 1.6, 6.2, 3.0 }, { 2.6, 3.0, 7.4, 4.6 }, { 1.2, 4.6, 8.8, 7.2 }, { 4.2, 7, 5.8, 9.8 } } },     -- spades
}

local function suit(gg, s, x, y, scale)
  local shape = SUITS[s]
  local pts = {}
  for i, v in ipairs(shape[1]) do pts[i] = math.floor((i % 2 == 1 and x or y) + v * scale + 0.5) end
  gg:polyline(pts)
  for _k, b in ipairs(shape[2]) do
    local x1, y1 = math.floor(x + b[1] * scale + 0.5), math.floor(y + b[2] * scale + 0.5)
    gg:rect(x1, y1, math.floor(x + b[3] * scale + 0.5) - x1, math.floor(y + b[4] * scale + 0.5) - y1, { fill = true })
  end
end

local RANKS = { 'A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K' }

------------------------------------------------------------------ geometry

local function slot_x(k) return X0 + (k - 1) * (CW + GAP) end
local function col_offset(n)
  if n <= 1 then return 32 end
  return math.max(12, math.min(32, (TAB_BOTTOM - TAB_Y - CH) // (n - 1)))
end
local function card_y(k, i) return TAB_Y + (i - 1) * col_offset(#pos.cols[k]) end

------------------------------------------------------------------ storage

local function save()
  kit.write('game.txt', 'deal=' .. deal .. '\npos=' .. R.encode(pos) .. '\nmoves=' .. moves ..
    '\nplayed=' .. stats.played .. '\nwon=' .. stats.won)
end

local function start(d)
  deal = d
  pos = R.deal(d)
  R.autoplay(pos)
  history, moves, sel, hint, msg, line = {}, 0, nil, nil, nil, nil
  stats.played = stats.played + 1
  save()
end

local function load()
  local t = kit.kv(kit.read('game.txt'))
  stats.played, stats.won = tonumber(t.played) or 0, tonumber(t.won) or 0
  local p = t.pos and R.decode(t.pos)
  if p then
    deal, pos, moves = tonumber(t.deal) or 1, p, tonumber(t.moves) or 0
  else
    start(1)
  end
end

------------------------------------------------------------------ the winning line

local function read_solution(d)
  if d < 1 or d > SOLVED_DEALS then return nil end
  local P = ctx.package
  if not P then return nil end
  local name = string.format('sol%02d.txt', (d - 1) // 100)
  local ok, r = pcall(function() return P:open_text(name, { max_bytes = 2000000, max_line_bytes = 4096 }) end)
  if not ok or r == nil or type(r) == 'string' then return nil end
  local found
  for _i = 1, 100 do
    local okl, l = pcall(function() return r:read_line() end)
    if not okl or l == nil then break end
    local n, rest = l:match('^(%d+) (.*)$')
    if tonumber(n) == d then found = rest; break end
  end
  pcall(function() r:close() end)
  return found
end

-- the positions of the deal's solution, by key, with the move made from each
local function load_line()
  if line and line.deal == deal then return line end
  line = nil
  local text = read_solution(deal)
  if not text or text == '-' then return nil end
  local p = R.deal(deal)
  R.autoplay(p)
  local l = { deal = deal, steps = {}, map = {} }
  for s in text:gmatch('%S+') do
    local m = R.move_parse(p, s)
    if not m or not R.legal(p, m) then return nil end
    l.steps[#l.steps + 1] = { enc = R.encode(p), m = m }
    l.map[R.key(p)] = #l.steps
    R.apply(p, m)
    R.autoplay(p)
  end
  line = l
  return l
end

-- the line's move from its own position, for the cards where they lie now
local function translate(step)
  local lp = R.decode(step.enc)
  local m = step.m
  local card
  if m.from == 'c' then
    local col = lp.cols[m.fi]
    card = col[#col - m.n + 1]
  else
    card = lp.free[m.fi]
  end
  local out = { n = m.n, to = m.to }
  for k = 1, 8 do
    local col = pos.cols[k]
    if #col >= m.n and col[#col - m.n + 1] == card then out.from, out.fi = 'c', k end
  end
  for i = 1, 4 do if pos.free[i] == card then out.from, out.fi = 'f', i end end
  if not out.from then return nil end
  if m.to == 'h' then out.ti = R.suit(card)
  elseif m.to == 'f' then for i = 1, 4 do if pos.free[i] == 0 then out.ti = i; break end end
  else
    local dest = lp.cols[m.ti]
    if #dest > 0 then
      for k = 1, 8 do local c = pos.cols[k]; if #c > 0 and c[#c] == dest[#dest] then out.ti = k end end
    else
      for k = 1, 8 do if #pos.cols[k] == 0 and not out.ti then out.ti = k end end
    end
  end
  if not out.ti or not R.legal(pos, out) then return nil end
  return out
end

------------------------------------------------------------------ play

local function do_move(m)
  history[#history + 1] = R.encode(pos)
  if #history > 400 then table.remove(history, 1) end
  R.apply(pos, m)
  R.autoplay(pos)
  moves = moves + 1
  sel, hint, msg = nil, nil, nil
  kit.moved()
  if R.won(pos) then
    stats.won = stats.won + 1
    kit.show({ title = 'Deal ' .. deal .. ' won!', lines = { moves .. ' moves.', 'Won ' .. stats.won .. ' of ' .. stats.played .. ' deals.' },
               rows = { { { 'Next deal', function() kit.close(); start(deal % 32000 + 1) end }, { 'Close', kit.close } } },
               cancel = kit.close })
  end
  save()
end

local function undo()
  local e = table.remove(history)
  if not e then msg = 'Nothing to undo.'; return end
  pos = R.decode(e)
  moves = math.max(0, moves - 1)
  sel, hint, msg = nil, nil, nil
  save()
end

local function show_hint()
  sel, hint = nil, nil
  if R.won(pos) then return end
  local l = load_line()
  if not l then msg = deal > SOLVED_DEALS and 'Hints are there for deals 1 to 1000.' or 'No hint for this deal.'; return end
  local k = l.map[R.key(pos)]
  local m = k and translate(l.steps[k])
  if m then hint = m; msg = 'Hint: the framed card(s), to the framed place.'; return end
  -- off the line: how far back is a position on it?
  local back
  for i = #history, 1, -1 do
    local p = R.decode(history[i])
    if p and l.map[R.key(p)] then back = #history - i + 1; break end
  end
  kit.show({ title = 'Off the winning line',
             lines = { 'This position is not on the solution Hint knows. It may still be winnable.',
                       back and ('Undo ' .. back .. ' move' .. (back > 1 and 's' or '') .. ' to get back on it.') or 'Restart to get back on it.' },
             rows = { { { back and 'Back to it' or 'Restart', function()
                            kit.close()
                            if back then for _i = 1, back do undo() end
                            else pos = R.deal(deal); R.autoplay(pos); history, moves = {}, 0; save() end
                            show_hint()
                          end },
                        { 'Keep going', kit.close } } },
             cancel = kit.close })
end

-- the first place a picked card or run fits: home, a column with cards, an empty column, a free cell
local function auto_target(s)
  local tries = {}
  if s.n == 1 then
    local c = s.from == 'c' and pos.cols[s.i][#pos.cols[s.i]] or pos.free[s.i]
    tries[#tries + 1] = { to = 'h', ti = R.suit(c) }
  end
  for k = 1, 8 do if #pos.cols[k] > 0 then tries[#tries + 1] = { to = 'c', ti = k } end end
  for k = 1, 8 do if #pos.cols[k] == 0 then tries[#tries + 1] = { to = 'c', ti = k } end end
  if s.n == 1 then for i = 1, 4 do if pos.free[i] == 0 then tries[#tries + 1] = { to = 'f', ti = i }; break end end end
  for _k, t in ipairs(tries) do
    local m = { from = s.from, fi = s.i, n = s.n, to = t.to, ti = t.ti }
    if R.legal(pos, m) then return m end
  end
  return nil
end

local function try_move(to, ti)
  local m = { from = sel.from, fi = sel.i, n = sel.n, to = to, ti = ti }
  if R.legal(pos, m) then do_move(m); return true end
  if to == 'c' and sel.n > 1 then
    -- fewer cards may fit: the part of the run that goes onto that column
    for n = sel.n - 1, 1, -1 do
      m.n = n
      if R.legal(pos, m) then do_move(m); return true end
    end
  end
  return false
end

------------------------------------------------------------------ input

local function tap(x, y)
  if kit.tap_modal(x, y) then return end
  for k, b in ipairs({ 'Undo', 'Hint', 'Restart', 'New' }) do
    local bw = math.floor((W - 24 - 3 * 8) / 4)
    local bx = 12 + (k - 1) * (bw + 8)
    if x >= bx and x < bx + bw and y >= BTN_Y and y < BTN_Y + BTN_H then
      if b == 'Undo' then undo()
      elseif b == 'Hint' then show_hint()
      elseif b == 'Restart' then
        kit.show({ title = 'Restart deal ' .. deal .. '?', lines = {},
                   rows = { { { 'Restart', function()
                                  kit.close(); pos = R.deal(deal); R.autoplay(pos); history, moves, sel, hint = {}, 0, nil, nil; save()
                                end }, { 'Cancel', kit.close } } }, cancel = kit.close })
      else
        kit.show({ title = 'New deal', lines = { 'Deal ' .. deal .. ' now. Hints for deals 1 to 1000.' },
                   rows = { { { 'Next (' .. (deal % 32000 + 1) .. ')', function() kit.close(); start(deal % 32000 + 1) end },
                              { 'Random', function() kit.close(); start(math.random(1, SOLVED_DEALS)) end } },
                            { { 'Number...', function()
                                  kit.close()
                                  ctx.input:text({ title = 'Deal number (1-32000)', value = tostring(deal) }, function(c, s)
                                    local n = tonumber(s)
                                    if n and n >= 1 and n <= 32000 then start(math.floor(n)) end
                                    kit.refresh()
                                  end)
                                end },
                              { 'Cancel', kit.close } } },
                   cancel = kit.close })
      end
      return
    end
  end
  -- which slot or column
  local k = (x - X0) // (CW + GAP) + 1
  if k < 1 or k > 8 or x - slot_x(k) >= CW then sel = nil; return end
  if y >= SLOT_Y and y < SLOT_Y + CH then
    if k <= 4 then
      if sel then
        if not try_move('f', k) then msg = 'Only one card fits in a free cell.' end
      elseif pos.free[k] ~= 0 then sel = { from = 'f', i = k, n = 1 }; hint = nil end
    else
      if sel then
        local c = sel.from == 'c' and pos.cols[sel.i][#pos.cols[sel.i]] or pos.free[sel.i]
        if sel.n ~= 1 or not try_move('h', R.suit(c)) then msg = 'That card cannot go home yet.' end
      end
    end
    return
  end
  if y >= TAB_Y and y < TAB_BOTTOM + CH then
    local col = pos.cols[k]
    if sel then
      if sel.from == 'c' and sel.i == k then
        local m = auto_target(sel)
        if m then do_move(m) else sel = nil; msg = 'No place for it.' end
        return
      end
      if try_move('c', k) then return end
      if sel.from == 'f' or #col == 0 then msg = 'It does not fit there.'; sel = nil; return end
    end
    if #col == 0 then sel = nil; return end
    -- the tapped card, and the cards above it
    local off = col_offset(#col)
    local i = math.min(#col, math.max(1, (y - TAB_Y) // off + 1))
    local n = #col - i + 1
    if n > R.run(pos, k) then
      n = R.run(pos, k)
      msg = n > 1 and 'Picked the cards that move together.' or nil
    end
    sel, hint = { from = 'c', i = k, n = n }, nil
    return
  end
  sel = nil
end

------------------------------------------------------------------ drawing

-- a card's face: rank and a small sign at its top, a large sign when the whole card shows
local function face(gg, c, x, y, whole)
  gg:text(x + 4, y + 2, RANKS[R.rank(c)], { font = kit.font('medium') })
  suit(gg, R.suit(c), x + CW - 24, y + 4, 2)
  if whole then suit(gg, R.suit(c), x + (CW - 32) // 2, y + CH - 40, 3.2) end
end

local function draw_card(gg, c, x, y)
  gg:rect(x, y, CW, CH, { line_width = 1 })
  face(gg, c, x, y, true)
end

-- a column: one frame round the stack and a line where each card starts, so the edges of the
-- cards underneath never cross the faces above them
local function draw_column(gg, k)
  local col, x = pos.cols[k], slot_x(k)
  if #col == 0 then gg:rect(x + 4, TAB_Y + 4, CW - 8, CH - 8, { line_width = 1 }); return end
  local bottom = card_y(k, #col) + CH
  gg:rect(x, TAB_Y, CW, bottom - TAB_Y, { line_width = 1 })
  for i, c in ipairs(col) do
    local y = card_y(k, i)
    if i > 1 then gg:line(x, y, x + CW - 1, y) end
    face(gg, c, x, y, i == #col)
  end
end

local function frame(gg, x, y, w, h, lw) gg:rect(x - 3, y - 3, w + 6, h + 6, { line_width = lw or 3 }) end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    gg:clear(0)
    gg:text(12, 12, 'FreeCell  ' .. deal, { font = kit.font('large') })
    gg:text(12, 52, 'Moves ' .. moves .. '    Won ' .. stats.won .. '/' .. stats.played, { font = kit.font('small') })
    gg:line(0, 90, W, 90)
    if kit.modal() then kit.draw_modal(gg); return end
    -- free cells and foundations
    for k = 1, 8 do
      local x = slot_x(k)
      if k <= 4 then
        local cc = pos.free[k]
        if cc ~= 0 then draw_card(gg, cc, x, SLOT_Y)
        else gg:rect(x + 4, SLOT_Y + 4, CW - 8, CH - 8, { line_width = 1 }) end
      else
        local s = k - 5
        if pos.home[s] > 0 then draw_card(gg, s * 13 + pos.home[s], x, SLOT_Y)
        else
          gg:rect(x, SLOT_Y, CW, CH, { line_width = 2 })
          suit(gg, s, x + (CW - 32) // 2, SLOT_Y + (CH - 32) // 2, 3.2)
        end
      end
    end
    -- the tableau
    for k = 1, 8 do draw_column(gg, k) end
    -- the picked cards and the hint
    local function mark(from, i, n, lw)
      if from == 'f' then frame(gg, slot_x(i), SLOT_Y, CW, CH, lw); return end
      local col = pos.cols[i]
      local top = card_y(i, #col - n + 1)
      frame(gg, slot_x(i), top, CW, card_y(i, #col) + CH - top, lw)
    end
    if sel then mark(sel.from, sel.i, sel.n, 4) end
    if hint then
      mark(hint.from, hint.fi, hint.n, 3)
      if hint.to == 'h' then frame(gg, slot_x(hint.ti + 5), SLOT_Y, CW, CH, 2)
      elseif hint.to == 'f' then frame(gg, slot_x(hint.ti), SLOT_Y, CW, CH, 2)
      else
        local col = pos.cols[hint.ti]
        local y = #col > 0 and card_y(hint.ti, #col) or TAB_Y
        frame(gg, slot_x(hint.ti), y, CW, CH, 2)
      end
    end
    local m = msg or (sel and 'Tap where it goes (tap it again: auto).' or 'Tap a card to pick it up.')
    gg:text(12, BTN_Y - 30, kit.short(m, 48), { font = kit.font('small') })
    for k, b in ipairs({ 'Undo', 'Hint', 'Restart', 'New' }) do
      local bw = math.floor((W - 24 - 3 * 8) / 4)
      kit.button(gg, 12 + (k - 1) * (bw + 8), BTN_Y, bw, BTN_H, b)
    end
    if ERR then gg:text(12, H - 30, kit.short('ERR ' .. ERR, 48), { font = kit.font('small') }) end
  end)
  if not ok then pcall(function() gg:text(8, H - 60, kit.short('draw ERR ' .. tostring(e), 46)) end) end
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
      elseif ev.key == 'up' or ev.key == 'left' then undo()
      elseif ev.key == 'down' or ev.key == 'right' then show_hint() end
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
  __TEST.api = { pos = function() return pos end, R = R, deal = function() return deal end, sel = function() return sel end,
                 hint = function() return hint end, moves = function() return moves end, start = start,
                 geometry = function() return X0, CW, GAP, SLOT_Y, TAB_Y, CH end, card_y = card_y }
end
