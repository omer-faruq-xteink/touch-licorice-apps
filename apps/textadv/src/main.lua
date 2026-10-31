-- Text adventures for XTOS Licorice, API 2.9 (uses tools/gamekit and src/zmachine.lua).
--
-- Plays Z-machine story files (.z3, .z5, .z8: Zork, Infocom's other games, most Inform games)
-- copied into the app's folder on the card (AppFiles/textadv/), and Zork I, built in (MIT licence;
-- the package's data section holds it as hex, data/zork1.txt). The library lists them; a game in
-- progress continues where it was left (an automatic save after every turn).
--
-- The game screen: the status line, then the transcript (each reply opens at its beginning; Prev
-- and Next or the side buttons page through), the command being built, and buttons: directions,
-- Look, Inventory, Wait and Again play at once; the word chips (verbs, then the game's own words
-- from the last reply) build a command, Send plays it; Keys opens the keyboard. The game's own
-- save and restore use one slot per game.

local Z = require('zmachine')
local W, H = kit.W, kit.H
local FOLDER = 'AppFiles/textadv'
local PACK_URL = 'https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/textadv/'
local TEXT_TOP, TEXT_BOTTOM = 52, 516
local CMD_Y = 520
local ROW_Y, ROW_H, ROW_GAP = 556, 42, 6
local SLICE_MS = 2500                   -- run the game this long in one callback, then go on in a timer

local screen = 'library'                -- 'library' | 'game'
local games = {}                        -- { {name, file} }
local game = nil                        -- { name, file, m, key }
local lines = {}                        -- the transcript, wrapped: { text }
local top = 1                           -- first transcript line on screen
local cmd = ''
local chips, chip_page = {}, 1
local state = nil                       -- the machine's last result: 'input' | 'char' | 'more' | 'quit' | 'error'
local msg, ERR = nil, nil
local size = 'medium'                   -- the transcript's font
local busy = false
local qr_img = nil                      -- the QR code of the pack's page (empty library)

local DIRS = { { 'N', 'north' }, { 'NE', 'northeast' }, { 'E', 'east' }, { 'SE', 'southeast' },
               { 'S', 'south' }, { 'SW', 'southwest' }, { 'W', 'west' }, { 'NW', 'northwest' } }
local ACTS = { { 'Up', 'up' }, { 'Down', 'down' }, { 'In', 'in' }, { 'Out', 'out' },
               { 'Look', 'look' }, { 'Inv', 'inventory' }, { 'Wait', 'wait' } }
local VERBS = { 'take', 'drop', 'examine', 'open', 'close', 'read', 'put', 'in', 'on', 'with', 'turn',
                'push', 'pull', 'give', 'attack', 'eat', 'drink', 'wear', 'unlock', 'light', 'climb', 'enter', 'all' }
local SKIP = { a = true, an = true, the = true, ['and'] = true, of = true, to = true, is = true, it = true,
               you = true, your = true, are = true, there = true, here = true, this = true, that = true,
               with = true, from = true, into = true, onto = true, some = true, ['for'] = true, but = true,
               what = true, which = true, where = true, who = true, why = true, how = true, can = true, does = true }

------------------------------------------------------------------ files

local function key_of(name)
  local h = 5381
  for i = 1, #name do h = ((h * 33) + name:byte(i)) & 0x7fffffff end
  return string.format('%08x', h)
end

local function list_games()
  games = {}
  local ok, t = pcall(function() return ctx.files:list() end)
  for _k, f in ipairs((ok and type(t) == 'table') and t or {}) do
    local n = type(f) == 'table' and f.name or f
    if type(n) == 'string' then
      local base, ext = n:match('^(.-)%.([zZ][34578])$')
      if base then games[#games + 1] = { name = base, file = n, ext = ext:lower() } end
    end
  end
  table.sort(games, function(a, b) return a.name:lower() < b.name:lower() end)
  -- Zork I, built in, unless the card has it too (its progress is the same either way)
  local have = false
  for _k, g in ipairs(games) do if g.name:lower() == 'zork i' then have = true end end
  if not have and ctx.package then
    table.insert(games, 1, { name = 'Zork I', file = 'Zork I.z3', ext = 'z3', builtin = 'zork1.txt' })
  end
  for _k, g in ipairs(games) do
    local a = kit.read('a_' .. key_of(g.file) .. '.bin')
    g.cont = a ~= nil and a ~= ''
  end
end

local function read_story(file)
  local parts, off = {}, 0
  for _k = 1, 16 do                                  -- up to 1 MB
    local ok, piece = pcall(function() return ctx.files:read(file, off, 65536) end)
    if not ok or type(piece) ~= 'string' or piece == '' then break end
    parts[#parts + 1] = piece
    off = off + #piece
    if #piece < 65536 then break end
  end
  return #parts > 0 and table.concat(parts) or nil
end

-- saves go to the private files as hex (the files are text)
local HEX32 = string.rep('%02x', 32)
local function hex(s)
  local out, n = {}, #s
  for i = 1, n - 31, 32 do out[#out + 1] = HEX32:format(s:byte(i, i + 31)) end
  for i = n - n % 32 + 1, n do out[#out + 1] = ('%02x'):format(s:byte(i)) end
  return table.concat(out)
end
local function unhex(s) return (s:gsub('%x%x', function(h) return string.char(tonumber(h, 16)) end)) end

-- a story file from the package's data section (hex text)
local function read_builtin(file)
  pcall(function() ctx.budget:extend() end)
  local ok, r = pcall(function() return ctx.package:open_text(file, { max_bytes = 2000000, max_line_bytes = 8192 }) end)
  if not ok or not r or type(r) == 'string' then return nil end
  local parts = {}
  while true do
    local ok2, l = pcall(function() return r:read_line() end)
    if not ok2 or l == nil then break end
    if l ~= '' then parts[#parts + 1] = unhex(l) end
  end
  pcall(function() r:close() end)
  return #parts > 0 and table.concat(parts) or nil
end

------------------------------------------------------------------ transcript

local function text_h() return kit.line_h(size) + 2 end
local function page_lines() return (TEXT_BOTTOM - TEXT_TOP) // text_h() end

-- the transcript's last line, when the output so far did not end with a new line (the prompt
-- '>' and the command typed after it share one line)
local open_line = false

local function add_text(s)
  s = s:gsub('\r', '')
  if s == '' then return end
  if open_line and #lines > 0 then s = table.remove(lines) .. s end
  open_line = s:sub(-1) ~= '\n'
  if not open_line then s = s:sub(1, -2) end
  for _k, l in ipairs(kit.wrap(s, size, W - 24)) do lines[#lines + 1] = l end
  while #lines > 400 do table.remove(lines, 1); top = math.max(1, top - 1) end
end

-- the words of the last reply that the game knows, for the chips: verbs first
-- the game's words of the last replies (the newest first, at most 24: a short reply such as
-- "What do you want to put?" keeps the room's words), then the verbs
local known = {}

local function make_chips(reply)
  local seen, fresh = {}, {}
  for _k, v in ipairs(VERBS) do seen[v] = true end
  local m = game and game.m
  if m then
    local dict = m:rw(0x08)
    for w in reply:lower():gmatch('%a+') do
      if #w >= 3 and not seen[w] and not SKIP[w] then
        seen[w] = true
        local ok, d = pcall(function() return m:lookup(w, dict) end)
        if ok and d ~= 0 then fresh[#fresh + 1] = w end
      end
    end
  end
  for _k, w in ipairs(known) do
    if not seen[w] and #fresh < 24 then seen[w] = true; fresh[#fresh + 1] = w end
  end
  known = fresh
  local words = {}
  for _k, w in ipairs(fresh) do words[#words + 1] = w end
  for _k, v in ipairs(VERBS) do words[#words + 1] = v end
  chips, chip_page = words, 1
end

local function save_auto()
  if not game or not game.m or state ~= 'input' and state ~= 'char' then return end
  local r = game.m.reading
  if not r then return end
  local snap = game.m:snapshot(r.start)
  local keep = {}
  for i = math.max(1, #lines - 60), #lines do keep[#keep + 1] = lines[i] end
  kit.write('a_' .. game.key .. '.bin', hex(snap))
  kit.write('t_' .. game.key .. '.txt', table.concat(keep, '\n'))
  kit.write('last.txt', game.file)
end

------------------------------------------------------------------ running the game


local refresh = function() kit.refresh() end

local function after_output()
  local m = game.m
  local out = m:take_output()
  local first_new = #lines + 1
  add_text(out)
  -- show the reply from its start (the player reads down), unless it fits with what is above
  local n = page_lines()
  if #lines - first_new + 1 >= n then top = first_new else top = math.max(1, #lines - n + 1) end
  -- the chips: the game's words in its reply, not in the command echoed above it
  make_chips(out:gsub('^[^\n]*\n', '', 1))
end

local continue_run
continue_run = function()
  if not game then busy = false; return end
  pcall(function() ctx.budget:extend() end)
  local m = game.m
  local t0 = kit.now_ms() or 0
  local r, err
  repeat
    r, err = m:run(3000)
  until r ~= 'more' or ((kit.now_ms() or 0) - t0) > SLICE_MS
  state = r
  after_output()
  if r == 'more' then
    msg = 'thinking...'
    pcall(function() ctx:after(1, function() continue_run(); refresh() end) end)
    return
  end
  busy = false
  msg = nil
  if r == 'error' then msg = 'Game error: ' .. tostring(err) end
  if r == 'quit' then msg = 'The game has ended. Menu: restart or another game.' end
  if r == 'input' or r == 'char' then save_auto() end
end

local function send(line)
  if not game or busy then return end
  local m = game.m
  if state == 'char' then
    m:send_char(line == '' and 13 or line:byte(1))
  elseif state == 'input' then
    m:send_line(line)
  else
    return
  end
  cmd = ''
  busy = true
  continue_run()
end

local function open_game(g)
  local story = g.builtin and read_builtin(g.builtin) or read_story(g.file)
  if not story then msg = 'Could not read ' .. g.file; return end
  local ok, m = pcall(Z.new, story)
  if not ok then msg = tostring(m):gsub('^.-:%d+: ', ''); return end
  game = { name = g.name, file = g.file, builtin = g.builtin, m = m, key = key_of(g.file) }
  m.on_save = function(s) kit.write('s_' .. game.key .. '.bin', hex(s)); return kit.read('s_' .. game.key .. '.bin') ~= nil end
  m.on_restore = function() local s = kit.read('s_' .. game.key .. '.bin'); return s and s ~= '' and unhex(s) or nil end
  lines, top, cmd, chips, state, open_line, known = {}, 1, '', {}, nil, false, {}
  screen = 'game'
  kit.write('last.txt', g.file)
  local snap = kit.read('a_' .. game.key .. '.bin')
  if snap and snap ~= '' and m:restore(unhex(snap)) then
    for l in ((kit.read('t_' .. game.key .. '.txt') or '') .. '\n'):gmatch('([^\n]*)\n') do lines[#lines + 1] = l end
    add_text('\n[Continued]\n>')
    make_chips(table.concat(lines, ' ', math.max(1, #lines - 30)))
  end
  busy = true
  continue_run()
end

local function restart_game()
  if not game then return end
  kit.write('a_' .. game.key .. '.bin', '')
  local g = { name = game.name, file = game.file, builtin = game.builtin }
  game = nil
  open_game(g)
end

------------------------------------------------------------------ drawing

local function status_line()
  local m = game.m
  if m.v <= 3 then
    local ok, left, right = pcall(function() return m:status() end)
    if ok then return left, right end
    return game.name, ''
  end
  local up = m:upper_lines()
  return (up[1] or ''):gsub('^%s+', ''):gsub('%s%s+', '   '), ''
end

-- the chips in two rows a page: this page's rects, and the number of pages
local function chip_rows()
  local f = kit.font('small')
  local rects, x, row, pg = {}, 8, 0, 1
  for _k, wd in ipairs(chips) do
    local w = kit.width(f, wd) + 20
    if x + w > W - 56 then
      row, x = row + 1, 8
      if row == 2 then pg, row = pg + 1, 0 end
    end
    if pg == chip_page then
      rects[#rects + 1] = { x = x, y = ROW_Y + (2 + row) * (ROW_H + ROW_GAP), w = w, h = ROW_H, word = wd }
    end
    x = x + w + 6
  end
  return rects, pg
end

local function bottom_buttons()
  local labels = { 'Keys', 'Del', 'Clear', 'Again', 'Send', 'Menu' }
  local bw = (W - 16 - 5 * 6) // 6
  local out = {}
  for k, l in ipairs(labels) do
    out[k] = { x = 8 + (k - 1) * (bw + 6), y = ROW_Y + 4 * (ROW_H + ROW_GAP), w = bw, h = ROW_H, label = l }
  end
  return out
end

-- a row of buttons across the screen, each as wide as its label needs, the rest shared out
local function row_buttons(list, r)
  local f = kit.font('small')
  local need, total = {}, 0
  for k, b in ipairs(list) do need[k] = kit.width(f, b[1]) + 14; total = total + need[k] end
  local spare = math.max(0, (W - 16 - (#list - 1) * 4) - total)
  local out, x = {}, 8
  for k, b in ipairs(list) do
    local bw = need[k] + spare // #list + ((k <= spare % #list) and 1 or 0)
    out[k] = { x = x, y = ROW_Y + r * (ROW_H + ROW_GAP), w = bw, h = ROW_H, label = b[1], cmd = b[2] }
    x = x + bw + 4
  end
  return out
end

local function draw_qr(gg, x, y, px)
  if qr_img == nil then
    local ok, img = pcall(function() return ctx.qr:encode(PACK_URL) end)
    qr_img = ok and img or false
  end
  if not qr_img then return end
  pcall(function()
    local w = tonumber(qr_img.width) or 33
    local sz = w * math.max(1, px // w)
    gg:image(qr_img, x + (px - sz) // 2, y, { w = sz, h = sz })
  end)
end

local function draw_library(gg)
  gg:text(12, 12, 'Text adventures', { font = kit.font('large') })
  gg:text(12, 52, kit.short(#games .. ' game' .. (#games == 1 and '' or 's') .. '; yours go in ' .. FOLDER .. '/', 48), { font = kit.font('small') })
  gg:line(0, 86, W, 86)
  local last = kit.read('last.txt')
  local y = 96
  for _k, g in ipairs(games) do
    if y > H - 70 then break end
    gg:rect(12, y, W - 24, 54)
    gg:text(24, y + 6, kit.short(g.name, 30), { font = kit.font('medium') })
    gg:text(24, y + 32, g.cont and 'in progress: tap to continue' or (g.builtin and 'built in' or (g.ext .. ' story file')),
      { font = kit.font('small') })
    if g.file == last then gg:rect(15, y + 3, W - 30, 48) end
    y = y + 62
  end
  if H - y >= 280 then
    y = y + 10
    for _k, l in ipairs(kit.wrap('More games: copy Z-machine story files (.z3, .z5, .z8) into ' .. FOLDER ..
        '/ on the card (USB mode). Zork II and III are free too: scan for the pack.', 'small', W - 24)) do
      gg:text(12, y, l, { font = kit.font('small') }); y = y + kit.line_h('small') + 2
    end
    draw_qr(gg, (W - 180) // 2, y + 12, 180)
  end
end

local function draw_game(gg)
  local left, right = status_line()
  gg:text(8, 6, kit.short(left or '', 30), { font = kit.font('small') })
  if right and right ~= '' then
    local f = kit.font('small')
    gg:text(W - 8 - kit.width(f, right), 6, right, { font = f })
  end
  gg:text(8, 26, kit.short(game.name, 24), { font = kit.font('small') })
  local n = page_lines()
  local pos = (#lines > n) and (' ' .. math.min(#lines, top + n - 1) .. '/' .. #lines) or ''
  if pos ~= '' then local f = kit.font('small'); gg:text(W - 8 - kit.width(f, pos), 26, pos, { font = f }) end
  gg:line(0, 48, W, 48)
  local y = TEXT_TOP
  for i = top, math.min(#lines, top + n - 1) do
    gg:text(12, y, lines[i], { font = kit.font(size) })
    y = y + text_h()
  end
  gg:line(0, CMD_Y - 2, W, CMD_Y - 2)
  if msg and (busy or state == 'quit' or state == 'error') then
    gg:text(8, CMD_Y + 6, kit.short(msg, 52), { font = kit.font('small') })
  else
    local prompt = state == 'char' and '[press Send to go on]' or ('> ' .. cmd .. '_')
    gg:text(8, CMD_Y + 4, kit.short(prompt, 44), { font = kit.font('medium') })
  end
  for _r, list in ipairs({ row_buttons(DIRS, 0), row_buttons(ACTS, 1) }) do
    for _k, b in ipairs(list) do kit.button(gg, b.x, b.y, b.w, b.h, b.label, { font = 'small' }) end
  end
  local rects, pages = chip_rows()
  for _k, c in ipairs(rects) do kit.button(gg, c.x, c.y, c.w, c.h, c.word, { font = 'small', line_width = 1 }) end
  if pages > 1 then kit.button(gg, W - 48, ROW_Y + 2 * (ROW_H + ROW_GAP), 40, ROW_H * 2 + ROW_GAP, '>', { font = 'small' }) end
  for _k, b in ipairs(bottom_buttons()) do kit.button(gg, b.x, b.y, b.w, b.h, b.label, { font = 'small' }) end
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    gg:clear(0)
    if screen == 'library' then draw_library(gg) else draw_game(gg) end
    if kit.modal() then kit.draw_modal(gg) end
    if msg and screen == 'library' then gg:text(12, H - 56, kit.short(msg, 48), { font = kit.font('small') }) end
    if ERR then gg:text(8, H - 30, kit.short('ERR ' .. ERR, 48), { font = kit.font('small') }) end
  end)
  if not ok then pcall(function() gg:text(8, H - 60, kit.short('draw ERR ' .. tostring(e), 46)) end) end
end

------------------------------------------------------------------ input

local function inside(b, x, y) return x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h end

local function page(delta)
  local n = page_lines()
  top = math.max(1, math.min(math.max(1, #lines - n + 1), top + delta * n))
end

local function keyboard()
  pcall(function()
    ctx.input:text({ title = 'Command', text = cmd, max_bytes = 120 }, function(c, v)
      if type(v) == 'string' then send(v) end
      kit.refresh()
    end)
  end)
end

local function show_menu()
  local rows = {
    { { 'Text size', function() size = size == 'medium' and 'small' or (size == 'small' and 'large' or 'medium'); kit.write('size.txt', size)
        local keep = table.concat(lines, '\n') .. '\n'; lines = {}; open_line = false; add_text(keep); top = math.max(1, #lines - page_lines() + 1); kit.close() end },
      { 'Restart', function() kit.close(); restart_game() end } },
    { { 'Games', function() kit.close(); save_auto(); game = nil; screen = 'library'; list_games() end },
      { 'Cancel', kit.close } },
  }
  kit.show({ title = game and game.name or 'Menu', lines = { 'The game is saved after every turn. In the game, SAVE and RESTORE keep one more slot.' },
             rows = rows, cancel = kit.close })
end

local function tap_game(x, y)
  if busy then return end
  if y >= TEXT_TOP and y < TEXT_BOTTOM then
    if x < W / 3 then page(-1) else page(1) end
    return
  end
  for _k, b in ipairs(row_buttons(DIRS, 0)) do if inside(b, x, y) then send(b.cmd); return end end
  for _k, b in ipairs(row_buttons(ACTS, 1)) do if inside(b, x, y) then send(b.cmd); return end end
  local rects, pages = chip_rows()
  for _k, c in ipairs(rects) do
    if inside(c, x, y) then cmd = (cmd == '' and c.word) or (cmd .. ' ' .. c.word); return end
  end
  if pages > 1 and inside({ x = W - 48, y = ROW_Y + 2 * (ROW_H + ROW_GAP), w = 40, h = ROW_H * 2 + ROW_GAP }, x, y) then
    chip_page = chip_page % pages + 1; return
  end
  for _k, b in ipairs(bottom_buttons()) do
    if inside(b, x, y) then
      if b.label == 'Keys' then keyboard()
      elseif b.label == 'Del' then cmd = cmd:gsub('%s*%S+$', '')
      elseif b.label == 'Clear' then cmd = ''
      elseif b.label == 'Again' then send('again')
      elseif b.label == 'Send' then if state == 'char' or cmd ~= '' then send(cmd) end
      else show_menu() end
      return
    end
  end
end

local function tap(x, y)
  if kit.tap_modal(x, y) then return end
  if screen == 'library' then
    for k, g in ipairs(games) do
      local yy = 96 + (k - 1) * 62
      if y >= yy and y < yy + 54 and yy <= H - 70 then msg = nil; open_game(g); return end
    end
    return
  end
  tap_game(x, y)
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
      elseif screen == 'game' then
        if ev.key == 'down' or ev.key == 'right' then page(1)
        elseif ev.key == 'up' or ev.key == 'left' then page(-1)
        elseif ev.key == 'back' then show_menu() end
      end
    end
  end)
  if not ok then ERR = tostring(e) end
  kit.refresh()
  return true
end

function on_load(c)
  local ok, e = pcall(function()
    size = kit.read('size.txt') or 'medium'
    if size ~= 'small' and size ~= 'medium' and size ~= 'large' then size = 'medium' end
    list_games()
    local last = kit.read('last.txt')
    for _k, g in ipairs(games) do
      if g.file == last then
        local cont = kit.read('a_' .. key_of(g.file) .. '.bin')
        if cont and cont ~= '' then open_game(g) end
      end
    end
  end)
  if not ok then ERR = tostring(e) end
end

function on_leave() pcall(save_auto) end

if rawget(_G, '__TEST') then
  __TEST.api = { game = function() return game end, lines = function() return lines end, top = function() return top end,
                 state = function() return state end, cmd = function() return cmd end, chips = function() return chips end,
                 send = send, screen = function() return screen end, row_buttons = row_buttons, chip_rows = chip_rows,
                 bottom_buttons = bottom_buttons, DIRS = DIRS, ACTS = ACTS, busy = function() return busy end }
end
