-- Gamebook: choose-your-own-adventure stories in the .story format (FORMAT.md). One story comes
-- in the package (data/); more are copied into the app's user folder (ctx.files, API 2.9:
-- AppFiles/<app_id>/ on the SD card), converted from Twine or Ink on the tools site.
--
-- Storage: set.txt (text size), g_<key>.txt (progress: "go=<passage>" and the state before it,
-- so reopening shows the same page without running its changes twice), i_<key>.txt (a user
-- story's passage index, rebuilt when the file's size changes).

local S = require('story')
local W, H = kit.W, kit.H

local SITE = 'https://omer-faruq-xteink.github.io/touch-licorice-apps/'
local BUILTIN = { { file = 'lighthouse.txt' } }

local WORDS = {
  en = {
    app = 'Gamebook', stories = 'Stories', none = 'Only the built-in story so far.',
    add = 'More stories', menu = 'Menu', back = 'Back', start = 'Start', resume = 'Continue',
    restart = 'Start over', undo = 'Undo', size = 'Text size', library = 'Library',
    the_end = 'The End', again = 'Play again', cont = 'Continue', by = 'by ',
    sure = 'Start over from the beginning?', yes = 'Yes', no = 'No', progress = 'in progress',
    finished = 'finished', builtin = 'built in', cancel = 'Close',
    help = {
      'Copy .story files into this folder on the SD card (USB mode):',
      '@path',
      'They show up here the next time you open the app.',
      'Story packs and a converter for Twine and Ink stories (made on a computer) are on the site:',
    },
    sizes = { 'small', 'medium', 'large' }, err = 'This story has a problem:',
  },
  tr = {
    app = 'Oyun Kitabı', stories = 'Hikâyeler', none = 'Şimdilik yalnızca hazır hikâye var.',
    add = 'Daha fazla hikâye', menu = 'Menü', back = 'Geri', start = 'Başla', resume = 'Devam et',
    restart = 'Baştan başla', undo = 'Geri al', size = 'Yazı boyu', library = 'Kitaplık',
    the_end = 'Son', again = 'Yeniden oyna', cont = 'Devam', by = '',
    sure = 'Hikâyeye baştan başlansın mı?', yes = 'Evet', no = 'Hayır', progress = 'devam ediyor',
    finished = 'bitti', builtin = 'hazır', cancel = 'Kapat',
    help = {
      '.story dosyalarını SD karttaki şu klasöre kopyalayın (USB modu):',
      '@path',
      'Uygulamayı bir sonraki açışınızda burada görünürler.',
      'Hikâye paketleri ve Twine / Ink hikâyeleri için dönüştürücü (bilgisayarda) sitede:',
    },
    sizes = { 'küçük', 'orta', 'büyük' }, err = 'Bu hikâyede bir sorun var:',
  },
  de = {
    app = 'Spielbuch', stories = 'Geschichten', none = 'Bisher nur die eingebaute Geschichte.',
    add = 'Mehr Geschichten', menu = 'Menü', back = 'Zurück', start = 'Beginnen', resume = 'Weiter',
    restart = 'Neu beginnen', undo = 'Rückgängig', size = 'Schriftgröße', library = 'Bibliothek',
    the_end = 'Ende', again = 'Noch einmal', cont = 'Weiter', by = 'von ',
    sure = 'Die Geschichte von vorn beginnen?', yes = 'Ja', no = 'Nein', progress = 'begonnen',
    finished = 'beendet', builtin = 'eingebaut', cancel = 'Schließen',
    help = {
      '.story-Dateien in diesen Ordner auf der SD-Karte kopieren (USB-Modus):',
      '@path',
      'Sie erscheinen hier beim nächsten Öffnen der App.',
      'Geschichten-Pakete und ein Umwandler für Twine- und Ink-Geschichten (am Computer) auf der Seite:',
    },
    sizes = { 'klein', 'mittel', 'groß' }, err = 'Diese Geschichte hat einen Fehler:',
  },
}
local LANG = 'en'
local function w(k) return WORDS[LANG][k] or WORDS.en[k] end

-- every letter outside ASCII a story may use: the system fonts lack some (such as the dash), and
-- ctx.fonts:size then picks a font that has them
local SAMPLE = 'İŞĞÜÖÇışğüöçÄäßÉéèêàâçñãõíóú—–“”‘’…«»'
local font_cache = {}
local function font_px(px)
  if font_cache[px] then return font_cache[px] end
  local ok, f = pcall(function() return ctx.fonts:size(px, SAMPLE) end)
  if not ok or not f then ok, f = pcall(function() return ctx.fonts:size(px) end) end
  if not ok or not f then
    -- only on a host without fonts:size (before 2.3)
    -- xtapp-ignore: font-small
    f = (px >= 28 and ctx.fonts.large) or (px >= 22 and ctx.fonts.medium) or ctx.fonts.small
  end
  font_cache[px] = f
  return f
end
local function line_h(f, px)
  local ok, h = pcall(function() return f.line_height end)
  return (ok and tonumber(h)) or math.floor(px * 1.35)
end

local SIZES = { 20, 24, 28 }
local size_k = 2

------------------------------------------------------------------ storage

local function sread(name)
  local ok, s = pcall(function() return ctx.storage:read(name) end)
  return (ok and type(s) == 'string') and s or nil
end
local function swrite(name, s) pcall(function() ctx.storage:write(name, s) end) end
local function sremove(name) pcall(function() ctx.storage:remove(name) end) end

local function folder()
  local F = ctx.files
  return (F and type(F.path) == 'string' and F.path ~= '') and F.path or '/AppFiles/gamebook'
end

local function save_settings() swrite('set.txt', 'size=' .. size_k .. '\n') end

------------------------------------------------------------------ the library

local stories = {}            -- { key, file, builtin, title, author }
local lib_page = 0
local ROWS = 7

local function key_of(prefix, name)
  return prefix .. (name:gsub('%.[^.]*$', ''):gsub('[^%w]', '_'):sub(1, 40))
end

-- a source for S: { size, read(off, len) }
local function package_source(file)
  local ok, s = pcall(function() return ctx.package:read(file) end)
  if not ok or type(s) ~= 'string' then return nil end
  return { size = #s, read = function(off, len) return s:sub(off + 1, off + len) end }
end
local function file_source(name)
  local F = ctx.files
  if not F then return nil end
  local ok, size = pcall(function() return F:size(name) end)
  if not ok or type(size) ~= 'number' then return nil end
  return { size = size, read = function(off, len)
    local okr, s = pcall(function() return F:read(name, off, math.min(len, 65536)) end)
    return okr and s or nil
  end }
end

local function head_value(s, k)
  local v = s:match('\n' .. k .. ':%s*([^\r\n]*)') or s:match('^' .. k .. ':%s*([^\r\n]*)')
  return v and v:match('^(.-)%s*$') or nil
end

local function discover()
  stories = {}
  for _, b in ipairs(BUILTIN) do
    local src = package_source(b.file)
    if src then
      local head = src.read(0, 2048)
      stories[#stories + 1] = { key = key_of('b_', b.file), file = b.file, builtin = true,
        title = head_value(head, 'title') or b.file, author = head_value(head, 'author') }
    end
  end
  local okf, files = pcall(function() return ctx.files:list() end)
  local user = {}
  for _, f in ipairs((okf and type(files) == 'table') and files or {}) do
    local n = type(f) == 'table' and f.name or f
    if type(n) == 'string' and (n:lower():match('%.story$') or n:lower():match('%.story%.txt$')) then
      local src = file_source(n)
      local head = src and src.read(0, 2048) or ''
      user[#user + 1] = { key = key_of('f_', n), file = n, title = head_value(head, 'title') or n,
        author = head_value(head, 'author') }
    end
  end
  table.sort(user, function(a, b) return a.title:lower() < b.title:lower() end)
  for _, s in ipairs(user) do stories[#stories + 1] = s end
end

local function status_of(s)
  local p = sread('g_' .. s.key .. '.txt')
  if not p then return nil end
  local go = p:match('^go=([^\n]*)')
  if go == 'END' then return w('finished') end
  return w('progress')
end

------------------------------------------------------------------ playing

local screen = 'library'      -- library / help / intro / play / error
local cur                     -- the open story entry
local story, st, view
local go_name, pre            -- the passage on screen and the state before it was entered
local history = {}            -- { pre, go } of earlier pages, for Undo
local pages, page = {}, 1
local ERR, story_err
local qr_img

local function open_story(s)
  cur, story, story_err = s, nil, nil
  local src = s.builtin and package_source(s.file) or file_source(s.file)
  if not src then story_err = s.file; return false end
  local ikey = 'i_' .. s.key .. '.txt'
  if not s.builtin then story = S.from_index(src, sread(ikey)) end
  if not story then
    local err
    story, err = S.index(src)
    if not story then story_err = err; return false end
    if not s.builtin then swrite(ikey, S.index_string(story)) end
  end
  return true
end

local function persist()
  if cur and pre and go_name then
    swrite('g_' .. cur.key .. '.txt', 'go=' .. ((view and view.ending) and 'END' or go_name) .. '\n' .. pre)
  end
end

local layout

-- show passage `name`, entered from the current state
local function go(name)
  pre = S.save(st)
  local v, err = S.enter(story, st, name)
  if not v then story_err = err; screen = 'error'; return end
  view, go_name = v, name
  page = 1
  layout()
  persist()
end

local function begin(fresh)
  history = {}
  local saved = not fresh and sread('g_' .. cur.key .. '.txt')
  if saved then
    local g, rest = saved:match('^go=([^\n]*)\n(.*)$')
    if g and g ~= 'END' and (story.idx[g]) then
      st = S.load(story, rest)
      screen = 'play'
      go(g)
      return
    end
  end
  st = S.new_state(story)
  screen = 'play'
  go(story.start)
end

local function undo()
  local h = table.remove(history)
  if not h then return end
  st = S.load(story, h[1])
  go(h[2])
end

local function pick(i)
  local saved = pre
  local nxt = S.choose(story, st, view, i)
  -- "-> BACK" (Twine's back links): the page before, as Undo does
  if nxt == 'BACK' then
    if #history > 0 then undo() else st = S.load(story, saved); go(go_name) end
    return
  end
  history[#history + 1] = { saved, go_name }
  if #history > 30 then table.remove(history, 1) end
  go(nxt or 'END')
end

------------------------------------------------------------------ layout of a page

local TOP, BOT = 70, H - 70
local MARGIN = 24

local function wrap(f, s, maxw)
  local out, line = {}, ''
  for word in s:gmatch('[^ ]+') do
    local cand = line == '' and word or (line .. ' ' .. word)
    if line ~= '' and kit.width(f, cand) > maxw then
      out[#out + 1] = line; line = word
    else
      line = cand
    end
    -- a word wider than the line: cut it
    while kit.width(f, line) > maxw and utf8.len(line) and utf8.len(line) > 1 do
      local head = line
      while kit.width(f, head) > maxw and #head > 1 do head = kit.drop_last(head) end
      out[#out + 1] = head
      line = line:sub(#head + 1)
    end
  end
  out[#out + 1] = line
  return out
end

-- blocks: { kind = 'text'|'gap'|'button'|'center', lines, h, act }
layout = function()
  local px = SIZES[size_k]
  local f = font_px(px)
  local lh = line_h(f, px)
  local maxw = W - 2 * MARGIN
  local blocks = {}
  for _, l in ipairs(view.lines) do
    if l == '' then blocks[#blocks + 1] = { kind = 'gap', h = lh // 2 }
    else
      for _, s in ipairs(wrap(f, l, maxw)) do blocks[#blocks + 1] = { kind = 'text', s = s, h = lh } end
      blocks[#blocks + 1] = { kind = 'gap', h = lh // 4 }
    end
  end
  blocks[#blocks + 1] = { kind = 'gap', h = 12 }
  local function button(label, act)
    local ls = wrap(f, label, maxw - 32)
    blocks[#blocks + 1] = { kind = 'button', lines = ls, h = #ls * lh + 22, act = act }
    blocks[#blocks + 1] = { kind = 'gap', h = 12 }
  end
  for i, c in ipairs(view.choices) do
    -- a way back is shown only when there is a page to go back to
    if c.target ~= 'BACK' or #history > 0 then button(c.label, function() pick(i) end) end
  end
  if #view.choices == 0 and view.cont then button(w('cont'), function() pick(0) end) end
  if view.ending then
    blocks[#blocks + 1] = { kind = 'center', s = '~ ' .. w('the_end') .. ' ~', h = lh + 16 }
    button(w('again'), function() begin(true) end)
    button(w('library'), function() screen = 'library' end)
  end
  pages = { {} }
  local y = TOP
  for _, blk in ipairs(blocks) do
    local b = blk
    local new_page = y + b.h > BOT and #pages[#pages] > 0
    if new_page then pages[#pages + 1] = {}; y = TOP end
    if not (new_page and b.kind == 'gap') then
      pages[#pages][#pages[#pages] + 1] = { b = b, y = y }
      y = y + b.h
    end
  end
  if page > #pages then page = #pages end
end

------------------------------------------------------------------ drawing

local function header(gg, title, right)
  local f = font_px(24)
  local maxw = W - 24 - (right and 130 or 0)
  local s = title
  if kit.width(f, s) > maxw then
    while #s > 1 and kit.width(f, s .. '…') > maxw do s = kit.drop_last(s) end
    s = s .. '…'
  end
  gg:text(14, 18, s, { font = f })
  if right then kit.button(gg, W - 120, 10, 108, 46, right) end
  gg:line(0, 64, W, 64)
end

local function draw_play(gg)
  header(gg, cur.title, w('menu'))
  local px = SIZES[size_k]
  local f = font_px(px)
  local lh = line_h(f, px)
  for _, e in ipairs(pages[page] or {}) do
    local b = e.b
    if b.kind == 'text' then
      gg:text(MARGIN, e.y, b.s, { font = f })
    elseif b.kind == 'center' then
      gg:text((W - kit.width(f, b.s)) // 2, e.y + 6, b.s, { font = f })
    elseif b.kind == 'button' then
      gg:rect(MARGIN, e.y, W - 2 * MARGIN, b.h - 10, { line_width = 2 })
      for k, s in ipairs(b.lines) do gg:text(MARGIN + 16, e.y + 6 + (k - 1) * lh, s, { font = f }) end
    end
  end
  if #pages > 1 then
    local sf = font_px(20)
    local label = page .. ' / ' .. #pages
    gg:text((W - kit.width(sf, label)) // 2, H - 48, label, { font = sf })
    if page > 1 then kit.button(gg, 14, H - 62, 110, 50, '<') end
    if page < #pages then kit.button(gg, W - 124, H - 62, 110, 50, '>') end
  end
end

local function draw_library(gg)
  header(gg, w('app'), nil)
  local f, sf = font_px(24), font_px(20)
  local first = lib_page * ROWS
  for i = 1, ROWS do
    local s = stories[first + i]
    if not s then break end
    local y = TOP + (i - 1) * 86
    gg:rect(MARGIN, y, W - 2 * MARGIN, 76, { line_width = 1 })
    local t = s.title
    while #t > 1 and kit.width(f, t) > W - 2 * MARGIN - 24 do t = kit.drop_last(t) end
    gg:text(MARGIN + 12, y + 8, t, { font = f })
    local sub = {}
    if s.author then sub[#sub + 1] = w('by') .. s.author end
    sub[#sub + 1] = status_of(s) or (s.builtin and w('builtin') or nil)
    local line = table.concat(sub, '  ·  ')
    while #line > 1 and kit.width(sf, line) > W - 2 * MARGIN - 24 do line = kit.drop_last(line) end
    gg:text(MARGIN + 12, y + 44, line, { font = sf })
  end
  local pages_n = math.max(1, math.ceil(#stories / ROWS))
  if #stories <= #BUILTIN then gg:text(MARGIN, TOP + 86 * #stories + 10, w('none'), { font = sf }) end
  if pages_n > 1 then
    kit.button(gg, 14, H - 130, 110, 50, '<')
    kit.button(gg, W - 124, H - 130, 110, 50, '>')
    local label = (lib_page + 1) .. ' / ' .. pages_n
    gg:text((W - kit.width(sf, label)) // 2, H - 116, label, { font = sf })
  end
  kit.button(gg, MARGIN, H - 70, W - 2 * MARGIN, 56, w('add'))
end

local function draw_help(gg)
  header(gg, w('add'), w('back'))
  local f = font_px(20)
  local y = TOP + 6
  for _, item in ipairs(w('help')) do
    local l = item == '@path' and (folder() .. '/') or item
    for _, s in ipairs(wrap(f, l, W - 2 * MARGIN)) do gg:text(MARGIN, y, s, { font = f }); y = y + line_h(f, 20) end
    y = y + 10
  end
  if not qr_img then
    local ok, img = pcall(function() return ctx.qr:encode(SITE, { size = 220 }) end)
    qr_img = ok and img or false
  end
  if qr_img then
    gg:image(qr_img, (W - 220) // 2, y + 6)
    y = y + 236
  end
  for _, s in ipairs(wrap(f, SITE, W - 2 * MARGIN)) do gg:text(MARGIN, y, s, { font = f }); y = y + line_h(f, 20) end
end

local function intro_buttons()
  local b, y = {}, H - 70 - 66 * 2
  local saved = sread('g_' .. cur.key .. '.txt')
  local resumable = saved and not saved:match('^go=END') and story
  if resumable then
    b[#b + 1] = { w('resume'), function() begin(false) end, y }
    b[#b + 1] = { w('restart'), function()
      kit.show({ title = w('sure'), rows = { { { w('yes'), function() kit.close(); begin(true) end }, { w('no'), kit.close } } }, cancel = kit.close })
    end, y + 66 }
  elseif story then
    b[#b + 1] = { w('start'), function() begin(true) end, y + 66 }
  end
  b[#b + 1] = { w('library'), function() screen = 'library' end, y + 132 }
  return b
end

local function draw_intro(gg)
  header(gg, w('app'), nil)
  local y = TOP + 10
  local tf = font_px(30)
  for _, s in ipairs(wrap(tf, cur.title, W - 2 * MARGIN)) do gg:text(MARGIN, y, s, { font = tf }); y = y + line_h(tf, 30) end
  y = y + 10
  local f = font_px(22)
  local m = story and story.meta or {}
  local lines = {}
  if m.author then lines[#lines + 1] = w('by') .. m.author end
  if m.about then lines[#lines + 1] = m.about end
  if m.licence or m.license then lines[#lines + 1] = m.licence or m.license end
  if story_err then lines[#lines + 1] = w('err') .. ' ' .. story_err end
  for _, l in ipairs(lines) do
    for _, s in ipairs(wrap(f, l, W - 2 * MARGIN)) do gg:text(MARGIN, y, s, { font = f }); y = y + line_h(f, 22) end
    y = y + 12
  end
  for _, b in ipairs(intro_buttons()) do kit.button(gg, MARGIN, b[3], W - 2 * MARGIN, 56, b[1]) end
end

local function draw_error(gg)
  header(gg, cur and cur.title or w('app'), w('back'))
  local f = font_px(22)
  local y = TOP + 10
  for _, l in ipairs({ w('err'), tostring(story_err) }) do
    for _, s in ipairs(wrap(f, l, W - 2 * MARGIN)) do gg:text(MARGIN, y, s, { font = f }); y = y + line_h(f, 22) end
  end
  if #history > 0 then kit.button(gg, MARGIN, H - 140, W - 2 * MARGIN, 56, w('undo')) end
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    gg:clear(0)
    if screen == 'play' then draw_play(gg)
    elseif screen == 'intro' then draw_intro(gg)
    elseif screen == 'help' then draw_help(gg)
    elseif screen == 'error' then draw_error(gg)
    else draw_library(gg) end
    if kit.modal() then kit.draw_modal(gg) end
    if ERR then gg:text(10, H - 24, 'ERR ' .. kit.short(ERR, 60), { font = font_px(20) }) end
  end)
  if not ok then pcall(function() gg:text(10, 100, 'ERR ' .. tostring(e), { font = font_px(20) }) end) end
end

------------------------------------------------------------------ input

local function menu()
  kit.show({ title = cur.title, cancel = kit.close, rows = {
    { { w('undo'), function() kit.close(); undo() end, #history > 0 } },
    { { w('size') .. ': ' .. w('sizes')[size_k], function()
        size_k = size_k % 3 + 1; save_settings(); layout(); kit.close(); menu()
      end } },
    { { w('restart'), function()
        kit.close()
        kit.show({ title = w('sure'), rows = { { { w('yes'), function() kit.close(); begin(true) end }, { w('no'), kit.close } } }, cancel = kit.close })
      end } },
    { { w('library'), function() kit.close(); screen = 'library' end } },
  } })
end

local function turn(d)
  if screen == 'play' then
    page = math.max(1, math.min(#pages, page + d))
  elseif screen == 'library' then
    local n = math.max(1, math.ceil(#stories / ROWS))
    lib_page = (lib_page + d) % n
  end
end

local function tap(x, y)
  if kit.modal() then kit.tap_modal(x, y); return end
  local in_btn = function(bx, by, bw, bh) return x >= bx and x < bx + bw and y >= by and y < by + bh end
  if screen == 'library' then
    if in_btn(MARGIN, H - 70, W - 2 * MARGIN, 56) then screen = 'help'; return end
    if #stories > ROWS then
      if in_btn(14, H - 130, 110, 50) then turn(-1); return end
      if in_btn(W - 124, H - 130, 110, 50) then turn(1); return end
    end
    local i = (y - TOP) // 86 + 1
    local s = stories[lib_page * ROWS + i]
    if y >= TOP and i >= 1 and i <= ROWS and s then
      open_story(s)
      screen = 'intro'
    end
  elseif screen == 'help' then
    if in_btn(W - 120, 10, 108, 46) then screen = 'library' end
  elseif screen == 'intro' then
    for _, b in ipairs(intro_buttons()) do
      if in_btn(MARGIN, b[3], W - 2 * MARGIN, 56) then b[2](); return end
    end
  elseif screen == 'error' then
    if in_btn(W - 120, 10, 108, 46) then screen = 'library'
    elseif #history > 0 and in_btn(MARGIN, H - 140, W - 2 * MARGIN, 56) then screen = 'play'; undo() end
  elseif screen == 'play' then
    if in_btn(W - 120, 10, 108, 46) then menu(); return end
    if #pages > 1 then
      if page > 1 and in_btn(14, H - 62, 110, 50) then turn(-1); return end
      if page < #pages and in_btn(W - 124, H - 62, 110, 50) then turn(1); return end
    end
    for _, e in ipairs(pages[page] or {}) do
      if e.b.kind == 'button' and in_btn(MARGIN, e.y, W - 2 * MARGIN, e.b.h - 10) then e.b.act(); return end
    end
    if y > TOP and y < BOT then
      if x > W * 2 // 3 then turn(1) elseif x < W // 3 then turn(-1) end
    end
  end
end

function on_input(c, ev)
  ERR = nil
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    if ev.type == 'pointer' then
      if ev.phase ~= 'up' then return end
      if ev.gesture == 'swipe_left' and not kit.modal() then turn(1); return end
      if ev.gesture == 'swipe_right' and not kit.modal() then turn(-1); return end
      tap(ev.x or 0, ev.y or 0)
    elseif ev.type == 'key' and kit.key_accepted(ev) then
      if kit.modal() then
        if ev.key == 'back' and kit.modal().cancel then kit.modal().cancel() end
      elseif ev.key == 'back' then
        if screen == 'play' then menu() elseif screen ~= 'library' then screen = 'library' end
      elseif ev.key == 'down' or ev.key == 'right' then turn(1)
      elseif ev.key == 'up' or ev.key == 'left' then turn(-1) end
    end
  end)
  if not ok then ERR = tostring(e) end
  kit.refresh()
  return true
end

function on_load(c)
  math.randomseed(kit.now_ms() or 1)
  local ok, e = pcall(function()
    local okl, loc = pcall(function() return ctx.i18n.locale end)
    loc = (okl and type(loc) == 'string') and loc:sub(1, 2) or 'en'
    LANG = WORDS[loc] and loc or 'en'
    size_k = tonumber((sread('set.txt') or ''):match('size=(%d)')) or 2
    if size_k < 1 or size_k > 3 then size_k = 2 end
    discover()
  end)
  if not ok then ERR = tostring(e) end
end

function on_leave()
  persist()
  if qr_img then pcall(function() qr_img:release() end); qr_img = nil end
end

if rawget(_G, '__TEST') then
  __TEST.api = {
    screen = function() return screen end, stories = function() return stories end,
    view = function() return view end, state = function() return st end, story = function() return story end,
    pages = function() return pages end, page = function() return page end, err = function() return story_err end,
    open = function(i) open_story(stories[i]); screen = 'intro' end, begin = begin, pick = pick, undo = undo,
    discover = discover, S = S,
  }
end
