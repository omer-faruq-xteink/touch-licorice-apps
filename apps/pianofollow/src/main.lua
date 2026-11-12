-- Piano Follow: sheet music that follows your playing (see apps/pianofollow/README.md).
-- Screens: home (My pieces), score (one page at a time, three modes), summary (after practice).
-- Modules: score (files), midi (BLE MIDI packets), follow (Page turn / Follow), practice.
local S = require('score')
local M = require('midi')
local F = require('follow')
local P = require('practice')
local K = require('kbd')
local C = require('catalog')
-- the whole app runs in landscape (manifest display.orientation): 800 x 480, pages of 800 x 440
kit.W, kit.H = 800, 480
local W, H = kit.W, kit.H
local BAR_H = 40
local function SW() return W end
local ERR = nil

local screen = 'home'
local pieces = {}            -- home list (S.list rows)
local cur = nil              -- the open piece: { p, name, page, pages, map, mode, hands, fst, pst }
local layer, layer_page = nil, nil
local settings = { turn_at = 'end' }   -- 'end': on the page's last note; 'bar' / 'system': earlier
local home_page = 1           -- the page of the My pieces list
local go_home                -- defined with the pieces below

local MODE_NAME = { turn = 'Page turn', follow = 'Follow', practice = 'Practice' }
local HAND_NAME = { r = 'right', l = 'left', b = 'both' }

local function small() return kit.font('small') end
local function medium() return kit.font('medium') end
local function now() return kit.now_ms() or 0 end

------------------------------------------------------------------ redraws

-- e-ink frames cost about half a second: markers are redrawn at most every `delay` ms
local last_ref, timer = -math.huge, nil
local function refresh_now()
  if timer then timer:cancel(); timer = nil end
  last_ref = now()
  kit.refresh()
end
local function request(delay)
  if timer then return end
  local wait = delay - (now() - last_ref)
  if wait <= 0 then refresh_now(); return end
  timer = ctx:after(wait, function() timer = nil; last_ref = now(); kit.refresh() end)
end

------------------------------------------------------------------ pieces and pages

-- the private file of a piece's mode, hands and page: private names allow only [a-z0-9._-] (64 bytes),
-- so it is named after a hash of the piece's file name
local function piece_key(name)
  local h = 5381
  for i = 1, #name do h = (h * 33 + name:byte(i)) & 0x7fffffff end
  return string.format('p-%08x.txt', h)
end

local function save_piece()
  if not cur then return end
  kit.write(piece_key(cur.name), 'mode=' .. cur.mode .. '\nhands=' .. cur.hands .. '\npage=' .. cur.page .. '\n')
end

-- the page goes into one offscreen layer, written from the file's bitmap
local function show_page(n)
  if not cur then return end
  n = math.max(1, math.min(cur.pages, n))
  cur.page = n
  if layer_page == n then return end
  local hw, hh = cur.p.header.w, cur.p.header.h
  if layer and (layer.width ~= hw or layer.height ~= hh) then layer:release(); layer = nil end
  if not layer then layer = ctx.layers:create(hw, hh) end
  local bits, err = S.page_bits(cur.p, n)
  if not bits then ERR = 'page ' .. n .. ': ' .. tostring(err); return end
  layer:set_bits(bits, 0)
  layer_page = n
end

local function first_onset_of(field, value)
  for i, o in ipairs(cur.map.onsets) do if o[field] >= value then return i end end
  return #cur.map.onsets
end

-- (re)start the follower or the practice for the current mode, from the shown page (or an onset)
local function start_mode(from_onset)
  cur.fst, cur.pst = nil, nil
  if not cur.map then return end
  if cur.mode == 'practice' then
    cur.pst = P.new(cur.map, cur.hands, from_onset or first_onset_of(3, cur.page))
    local o = cur.map.onsets[cur.pst.pos]
    if o then show_page(o[3]) end
  else
    cur.fst = F.new(cur.map, cur.page, settings.turn_at)
  end
end

local function msg_box(title, line)
  kit.show({ title = title, lines = { line }, rows = { { { 'OK', kit.close } } }, cancel = kit.close })
end

local function open_piece(row)
  if row.bad then msg_box("Can't open this file", row.name .. ': it is not a Piano Follow score, or it is damaged.'); return end
  local p, err = S.open(row.name)
  if not p then msg_box("Can't open this file", row.name .. ': ' .. tostring(err)); return end
  if p.header.w > W or p.header.h > H - BAR_H then
    msg_box("Can't open this file", row.name .. ' was made for an upright screen by an older converter: convert it again.')
    return
  end
  local kv = kit.kv(kit.read(piece_key(row.name)))
  cur = { p = p, name = row.name, page = 1, pages = #p.header.pages,
          mode = MODE_NAME[kv.mode or ''] and kv.mode or 'turn', hands = HAND_NAME[kv.hands or ''] and kv.hands or 'b' }
  local map = S.load_map(p)
  if map then cur.map = map else ERR = 'no note map: page turning by hand only' end
  layer_page = nil
  screen = 'score'
  show_page(tonumber(kv.page) or 1)
  start_mode()
end

go_home = function()
  if cur then save_piece() end
  screen, cur, layer_page = 'home', nil, nil
  pieces = S.list()
  local per = 2 * ((H - 80 - 110) // 56)                -- as PER_PAGE below
  home_page = math.min(home_page, math.max(1, (#pieces + per - 1) // per))
end

local function turn_by_hand(n)
  local before = cur.page
  show_page(n)
  if cur.page ~= before then
    if cur.fst then F.goto_page(cur.fst, cur.page) end
    save_piece()
  end
end

------------------------------------------------------------------ notes from the keyboard

-- one parsed note event { on, note, vel, ts } (kbd.lua calls this)
function on_midi(ev)
  if screen ~= 'score' or not cur or not cur.map then return end
  if cur.mode == 'practice' then
    local st = cur.pst
    if not ev.on then P.note_off(st, ev.note); return end
    local r = P.note_on(st, ev.note, now())
    if r == 'advance' then
      if st.done then screen = 'summary'; refresh_now(); return end
      local pg = cur.map.onsets[st.pos][3]
      if pg ~= cur.page then show_page(pg); save_piece(); refresh_now(); return end
      request(300)
    elseif r == 'wrong' then
      request(300)
    end
    return
  end
  if not ev.on then return end
  local e = F.note(cur.fst, ev.note, now())
  if e == 'turn' then
    show_page(cur.fst.page)
    save_piece()
    refresh_now()
  elseif e == 'bar' and cur.mode == 'follow' then
    request(1000)
  end
end

------------------------------------------------------------------ menus

local function mode_label()
  if not cur then return nil end
  if cur.mode == 'practice' then return 'Practice: ' .. HAND_NAME[cur.hands] end
  return MODE_NAME[cur.mode]
end
local MODE_W = 160
local function MODE_X() return math.floor((SW() - MODE_W) / 2) end

local function set_mode(m, hands)
  kit.close()
  cur.mode = m
  if hands then cur.hands = hands end
  start_mode()
  save_piece()
end

local function delete_piece()
  kit.show({ title = 'Delete this piece?', lines = { cur.p.header.title }, rows = { {
    { 'Delete', function()
        kit.close()
        local name = cur.name
        pcall(function() ctx.files:remove(name) end)
        C.rescan()
        pcall(function() ctx.storage:remove(piece_key(name)) end)
        cur = nil
        go_home()
      end },
    { 'Cancel', kit.close } } }, cancel = kit.close })
end

local function mode_menu()
  if not cur.map then
    kit.show({ title = 'No note map', lines = { 'This file only has its pages: turn them by hand.' },
               rows = { { { 'OK', kit.close } }, { { 'Delete this piece', delete_piece } } }, cancel = kit.close })
    return
  end
  kit.show({ title = 'Mode', rows = {
    { { 'Delete this piece', delete_piece } },
    { { 'Page turn', function() set_mode('turn') end } },
    { { 'Follow', function() set_mode('follow') end } },
    { { 'Practice', function()
        kit.show({ title = 'Practice with', rows = {
          { { 'Right hand', function() set_mode('practice', 'r') end } },
          { { 'Left hand', function() set_mode('practice', 'l') end } },
          { { 'Both hands', function() set_mode('practice', 'b') end } } }, cancel = kit.close })
      end } } }, cancel = kit.close })
end

------------------------------------------------------------------ drawing

local ROW_Y, ROW_H = 110, 56
-- lists: two columns of rows, a page at a time, Prev / Next at the bottom right
local LIST_ROWS = math.floor((H - 80 - ROW_Y) / ROW_H)
local COL_W = math.floor((W - 48) / 2)
local PER_PAGE = 2 * LIST_ROWS
local function list_cell(k)
  return 16 + ((k - 1) // LIST_ROWS) * (COL_W + 16), ROW_Y + ((k - 1) % LIST_ROWS) * ROW_H
end
local function draw_list(gg, rows, page)
  local first = (page - 1) * PER_PAGE
  for k = 1, PER_PAGE do
    local r = rows[first + k]
    if not r then break end
    local x, y = list_cell(k)
    gg:text(x, y + 4, kit.short(r.label, 30), { font = kit.font('medium') })
    if r.sub and r.sub ~= '' then gg:text(x, y + 30, kit.short(r.sub, 36), { font = kit.font('small') }) end
    gg:rect(x, y + ROW_H - 2, COL_W, 1)
  end
end
local function list_hit(rows, page, x, y)
  if y < ROW_Y then return nil end
  local row = (y - ROW_Y) // ROW_H
  if row >= LIST_ROWS then return nil end
  local col = x < 16 + COL_W + 8 and 0 or 1
  return rows[(page - 1) * PER_PAGE + col * LIST_ROWS + row + 1]
end
local function page_buttons(btns, page, n, set_page)
  if page > 1 then btns[#btns + 1] = { x = W - 236, y = H - 66, w = 100, h = 50, label = 'Prev', fn = function() set_page(page - 1) end } end
  if page * PER_PAGE < n then btns[#btns + 1] = { x = W - 116, y = H - 66, w = 100, h = 50, label = 'Next', fn = function() set_page(page + 1) end } end
end
local function join(...)
  local t = {}
  for _k, s in ipairs({ ... }) do if s and s ~= '' then t[#t + 1] = s end end
  return table.concat(t, ' · ')
end

------------------------------------------------------------------ catalog screens

-- cat.view: 'levels' | 'composers' | 'pieces' | 'search' | 'piece'
local cat = { view = 'levels', page = 1 }

local function cat_msg(s) cat.msg = s; refresh_now() end

local function open_catalog()
  screen, cat = 'catalog', { view = 'levels', page = 1, msg = 'Loading the catalog …' }
  C.refresh(function(ok, err)
    cat.msg = (not ok) and (err .. (C.loaded() and ' (showing the list from last time)' or '')) or nil
    refresh_now()
  end)
end

local function show_card(entry)
  cat.back, cat.view, cat.id, cat.msg = { view = cat.view, page = cat.page }, 'piece', entry.id, nil
end

-- the rows of the current list view: { label, sub, fn }
local function cat_rows()
  local rows = {}
  if cat.view == 'levels' then
    for _k, l in ipairs(C.levels()) do
      rows[#rows + 1] = { label = l.label .. ' (' .. l.count .. ')', fn = function() cat.view, cat.level, cat.page = 'composers', l.level, 1 end }
    end
  elseif cat.view == 'composers' then
    for _k, c in ipairs(C.composers(cat.level)) do
      rows[#rows + 1] = { label = c, fn = function() cat.view, cat.composer, cat.page = 'pieces', c, 1 end }
    end
  elseif cat.view == 'pieces' or cat.view == 'search' then
    local list = cat.view == 'pieces' and C.pieces(cat.level, cat.composer) or C.search(cat.query)
    for _k, p in ipairs(list) do
      rows[#rows + 1] = { label = p.title, sub = join(cat.view == 'search' and p.composer or nil, C.installed(p.id) and 'downloaded' or nil),
                          fn = function() show_card(p) end }
    end
  end
  return rows
end

local function search()
  ctx.input:text({ title = 'Search the catalog (title or composer)' }, function(_c, text)
    if text and text ~= '' then cat.view, cat.query, cat.page = 'search', text, 1 end
    refresh_now()
  end)
end

local function cat_buttons()
  local btns, y = {}, H - 66
  if cat.view == 'piece' then
    local e = C.get(cat.id)
    if not e then return btns end
    if C.installed(e.id) then
      btns[#btns + 1] = { x = 16, y = 330, w = 214, h = 50, label = 'Open', fn = function() open_piece({ name = C.file(e.id) }) end }
    else
      btns[#btns + 1] = { x = 16, y = 330, w = 214, h = 50, label = 'Download', fn = function()
        cat_msg('Downloading …')
        C.download(e.id, function(ok, err) cat_msg(ok and 'Downloaded.' or err) end)
      end }
    end
    return btns
  end
  if cat.view == 'levels' then btns[#btns + 1] = { x = 16, y = y, w = 214, h = 50, label = 'Search', fn = search } end
  page_buttons(btns, cat.page, #cat_rows(), function(p) cat.page = p end)
  return btns
end

local TITLES = { levels = 'Catalog', composers = 'Composers', pieces = 'Pieces', search = 'Search' }

local function draw_catalog(gg)
  if cat.view == 'piece' then
    local e = C.get(cat.id)
    if e then
      local y = 20
      for _k, l in ipairs(kit.wrap(e.title, 'large', W - 32)) do gg:text(16, y, l, { font = kit.font('large') }); y = y + 36 end
      local lines = {}
      local function add(l) if l and l ~= '' then lines[#lines + 1] = l end end
      add(e.composer)
      if e.arranger and e.arranger ~= '' then add('arranged by ' .. e.arranger) end
      add(join(e.level, e.pages and (e.pages .. ' pages') or nil, e.size and (math.ceil(e.size / 1024) .. ' KB') or nil))
      if e.license then add('License: ' .. e.license) end
      if e.source then add('Source: ' .. e.source) end
      for _k, l in ipairs(lines) do
        for _j, w in ipairs(kit.wrap(l, 'small', W - 32)) do gg:text(16, y + 6, w, { font = small() }); y = y + 26 end
      end
    end
  else
    local title = TITLES[cat.view]
    if cat.view == 'composers' then title = cat.level and (cat.level:sub(1, 1):upper() .. cat.level:sub(2)) or '' end
    if cat.view == 'pieces' then title = cat.composer end
    if cat.view == 'search' then title = 'Search: ' .. (cat.query or '') end
    gg:text(16, 20, kit.short(title or '', 30), { font = kit.font('large') })
    local rows = cat_rows()
    draw_list(gg, rows, cat.page)
    if #rows == 0 and not cat.msg then gg:text(16, ROW_Y, cat.view == 'search' and 'Nothing found.' or 'Nothing here yet.', { font = small() }) end
  end
  if cat.msg then for k, l in ipairs(kit.wrap(cat.msg, 'small', W - 32)) do gg:text(16, (cat.view == 'piece' and 400 or 70) + (k - 1) * 22, l, { font = small() }) end end
  for _k, b in ipairs(cat_buttons()) do kit.button(gg, b.x, b.y, b.w, b.h, b.label) end
end

local function tap_catalog(x, y)
  for _k, b in ipairs(cat_buttons()) do
    if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then b.fn(); return end
  end
  if cat.view == 'piece' then return end
  local r = list_hit(cat_rows(), cat.page, x, y)
  if r then cat.msg = nil; r.fn() end
end

local function back_catalog()
  if cat.view == 'piece' then cat.view, cat.page = cat.back.view, cat.back.page; cat.msg = nil
  elseif cat.view == 'pieces' then cat.view, cat.page = 'composers', 1
  elseif cat.view == 'composers' or cat.view == 'search' then cat.view, cat.page = 'levels', 1
  else go_home() end
end

local function home_rows()
  local rows = {}
  for _k, row in ipairs(pieces) do
    rows[#rows + 1] = { label = row.title, sub = row.bad and 'cannot be opened' or join(row.composer, row.level), fn = function() open_piece(row) end }
  end
  return rows
end
local function home_buttons()
  local btns = { { x = 16, y = H - 66, w = 214, h = 50, label = 'Catalog', fn = open_catalog },
                 { x = 250, y = H - 66, w = 214, h = 50, label = 'Keyboard', fn = function() screen = 'keyboard'; K.auto() end } }
  page_buttons(btns, home_page, #pieces, function(p) home_page = p end)
  return btns
end

local NAMES = { 'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B' }
local function note_name(n) return NAMES[n % 12 + 1] .. (n // 12 - 1) end

-- the keyboard screen: state, Search / Forget, the keyboards found
local function keyboard_buttons()
  local btns = {}
  if ctx.ble then
    btns[#btns + 1] = { x = 16, y = 150, w = 214, h = 48, label = 'Search', fn = K.scan }
    btns[#btns + 1] = { x = 250, y = 150, w = 214, h = 48, label = 'Forget', fn = K.forget }
    for k, d in ipairs(K.devices()) do                     -- two columns of three
      if k > 6 then break end
      btns[#btns + 1] = { x = 16 + ((k - 1) // 3) * (COL_W + 16), y = 250 + ((k - 1) % 3) * 56, w = COL_W, h = 48,
                          label = d.name or d.address, fn = function() K.pick(k) end }
    end
  end
  return btns
end

local KB_TEXT = { off = 'This reader has no Bluetooth: turn the pages by hand.', none = 'Not connected. Turn the keyboard on and search.',
                  scanning = 'Searching for Bluetooth MIDI keyboards …', connecting = 'Connecting …', lost = 'Keyboard lost: trying again …' }

local function draw_keyboard(gg)
  gg:text(16, 20, 'Keyboard', { font = kit.font('large') })
  local st = K.state()
  local line = st == 'connected' and ('Connected: ' .. (K.name() or 'keyboard')) or KB_TEXT[st] or st
  for k, l in ipairs(kit.wrap(line, 'medium', W - 32)) do gg:text(16, 66 + (k - 1) * 28, l, { font = medium() }) end
  if K.last() then gg:text(16, 214, 'Last note: ' .. note_name(K.last()), { font = small() }) end
  for _k, b in ipairs(keyboard_buttons()) do kit.button(gg, b.x, b.y, b.w, b.h, b.label, { font = 'medium' }) end
end

local function draw_home(gg)
  gg:text(16, 14, 'Piano Follow', { font = kit.font('large') })
  gg:text(16, 70, 'My pieces', { font = medium() })
  if #pieces == 0 then
    for k, l in ipairs(kit.wrap('No pieces yet. Download some from the catalog, or convert your own on the website and copy them to ' .. ctx.files.path .. '.', 'small', W - 32)) do
      gg:text(16, ROW_Y + (k - 1) * 24, l, { font = small() })
    end
  end
  draw_list(gg, home_rows(), home_page)
  for _k, b in ipairs(home_buttons()) do kit.button(gg, b.x, b.y, b.w, b.h, b.label) end
end

local function draw_markers(gg)
  if cur.mode == 'follow' and cur.fst and cur.fst.bar then
    local b = cur.map.bars[cur.fst.bar]
    if b and b[1] == cur.page then
      -- dashed and a little apart, so it does not read as a staff or ledger line
      local y = BAR_H + b[3] + 12
      for x = b[2], b[2] + b[4] - 8, 14 do gg:rect(x, y, 8, 3, { fill = true }) end
    end
  elseif cur.mode == 'practice' and cur.pst and not cur.pst.done then
    local o = cur.map.onsets[cur.pst.pos]
    -- under the system the note is in, at the height of Follow's line: never inside the music
    local b = o and cur.map.bars[o[2]]
    if o and b and o[3] == cur.page then gg:rect(o[4] - 6, BAR_H + b[3] + 10, 12, 5, { fill = true }) end
  end
end

local function draw_score(gg)
  gg:text(8, 8, K.state() == 'lost' and 'Keyboard lost' or kit.short(cur.p.header.title, 28), { font = small() })
  local ml = mode_label()
  if ml then gg:text(MODE_X() + math.floor((MODE_W - kit.width(small(), ml)) / 2), 8, ml, { font = small() }); gg:rect(MODE_X(), 3, MODE_W, BAR_H - 8) end
  local right = cur.page .. '/' .. cur.pages
  if cur.mode == 'practice' and cur.pst and cur.pst.wrong > 0 then right = 'Wrong ' .. cur.pst.wrong .. '  ' .. right end
  gg:text(SW() - 8 - kit.width(small(), right), 8, right, { font = small() })
  gg:rect(0, BAR_H - 2, SW(), 1)
  if layer then gg:image(layer, 0, BAR_H) end
  draw_markers(gg)
end

-- the practice summary: buttons laid out once for drawing and tapping
local function summary_buttons()
  local s = P.summary(cur.pst)
  local btns, rows = {}, 3                                  -- two columns of three bars on the wide screen
  for k, b in ipairs(s.bars) do
    if k > 2 * rows then break end
    local x, y = 16 + ((k - 1) // rows) * (COL_W + 16), 150 + ((k - 1) % rows) * 56
    btns[#btns + 1] = { x = x + 150, y = y, w = COL_W - 150, h = 44, label = 'Practice from bar ' .. b.bar, text = 'Bar ' .. b.bar .. ': ' .. b.wrong .. ' wrong',
                        tx = x, fn = function() start_mode(first_onset_of(2, b.bar)); screen = 'score' end }
  end
  local y = 150 + rows * 56 + 20
  btns[#btns + 1] = { x = 16, y = y, w = 214, h = 48, label = 'Again', fn = function() start_mode(1); screen = 'score' end }
  btns[#btns + 1] = { x = 250, y = y, w = 214, h = 48, label = 'Back to the score', fn = function() screen = 'score' end }
  return s, btns, math.max(0, #s.bars - 2 * rows)
end

local function draw_summary(gg)
  local s, btns, more = summary_buttons()
  gg:text(16, 20, 'Practice done', { font = kit.font('large') })
  gg:text(16, 70, s.wrong == 0 and 'No wrong notes.' or ('Wrong notes: ' .. s.wrong), { font = medium() })
  if #s.bars > 0 then gg:text(16, 110, 'Bars to practise:', { font = small() }) end
  if more > 0 then gg:text(500, 110, '+' .. more .. ' more bars', { font = small() }) end
  for _k, b in ipairs(btns) do
    if b.text then gg:text(b.tx, b.y + 10, b.text, { font = small() }) end
    kit.button(gg, b.x, b.y, b.w, b.h, b.label, { font = 'small' })
  end
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    gg:clear(0)
    if screen == 'score' and cur then draw_score(gg)
    elseif screen == 'summary' and cur then draw_summary(gg)
    elseif screen == 'keyboard' then draw_keyboard(gg)
    elseif screen == 'catalog' then draw_catalog(gg)
    else draw_home(gg) end
    if kit.modal() then kit.draw_modal(gg) end
    if ERR then gg:text(12, H - 24, kit.short('ERR ' .. ERR, 48), { font = small() }) end
  end)
  if not ok then pcall(function() gg:text(8, H - 60, kit.short('draw ERR ' .. tostring(e), 46)) end) end
end

------------------------------------------------------------------ input

local function inside(b, x, y) return x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h end

local function tap_home(x, y)
  for _k, b in ipairs(home_buttons()) do if inside(b, x, y) then b.fn(); return end end
  local r = list_hit(home_rows(), home_page, x, y)
  if r then r.fn() end
end

local function tap_keyboard(x, y)
  for _k, b in ipairs(keyboard_buttons()) do if inside(b, x, y) then b.fn(); return end end
end

local function tap_score(x, y)
  if y < BAR_H then
    if x >= MODE_X() and x < MODE_X() + MODE_W then mode_menu() end
    return
  end
  if x < SW() / 3 then turn_by_hand(cur.page - 1)
  elseif x > SW() * 2 / 3 then turn_by_hand(cur.page + 1) end
end

local function tap_summary(x, y)
  local _s, btns = summary_buttons()
  for _k, b in ipairs(btns) do if inside(b, x, y) then b.fn(); return end end
end

local function key_score(k)
  if k == 'left' or k == 'up' then turn_by_hand(cur.page - 1); return true end
  if k == 'right' or k == 'down' then turn_by_hand(cur.page + 1); return true end
  return false
end

function on_input(c, ev)
  local handled, redraw = true, false
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    if ev.type == 'pointer' then
      if ev.phase == 'up' then
        ERR = nil
        redraw = true
        local x, y = ev.x or 0, ev.y or 0
        if kit.modal() then kit.tap_modal(x, y)
        elseif screen == 'score' then tap_score(x, y)
        elseif screen == 'summary' then tap_summary(x, y)
        elseif screen == 'keyboard' then tap_keyboard(x, y)
        elseif screen == 'catalog' then tap_catalog(x, y)
        else tap_home(x, y) end
      end
    elseif ev.type == 'key' and ev.phase ~= 'down' then
      redraw = true
      if ev.key == 'back' then
        if kit.modal() then kit.close()
        elseif screen == 'summary' then screen = 'score'
        elseif screen == 'catalog' then back_catalog()
        elseif screen == 'score' or screen == 'keyboard' then go_home()
        else handled, redraw = false, false end            -- the host asks whether to leave
      elseif screen == 'score' and not kit.modal() then
        redraw = key_score(ev.key)
      else
        redraw = false
      end
    end
  end)
  if not ok then ERR = tostring(e); redraw = true end
  if redraw then refresh_now() end
  return handled
end

function on_load(c)
  local ok, e = pcall(function()
    local kv = kit.kv(kit.read('settings.txt'))
    if kv.turn_at == 'system' or kv.turn_at == 'bar' then settings.turn_at = kv.turn_at end
    go_home()
    K.start(on_midi, function() request(300) end)
  end)
  if not ok then ERR = tostring(e) end
end
function on_leave() pcall(save_piece) end

if rawget(_G, '__TEST') then
  go_home_for_test = function() go_home() end
  piece_key_for_test = piece_key
  __TEST.api = { pieces = function() return pieces end, S = S, M = M, F = F, P = P, screen = function() return screen end, cur = function() return cur end,
                 mode_label = mode_label, practice = function() return cur and cur.pst end }
end
