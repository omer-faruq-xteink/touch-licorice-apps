-- Notes for XTOS Licorice mini apps (Lua API 0.8, 480 x 800 portrait, 1 bpp).
--
-- The host delivers touch as taps and swipes only, so there is no freehand drawing. A page holds
-- typed text (an on-screen keyboard) and shapes placed with two taps: a line (two ends), a box (two
-- corners) or a circle (centre, then a point on the rim). Pages live in ctx.state, which the host
-- saves on leave. "Lock" chooses the current page for the lock screen and tries the host's
-- lock-screen calls; "Info" lists what the host exposes for that, because on firmware 7.6.8 the
-- route was a dead end and on Licorice nobody has exercised it yet (see README).
--
-- Modes: view (toolbar: Type Draw Pages Lock Info), type (keyboard), draw (Line Box Circle Undo
-- Done), pages (list: New Delete Back), info (host lock API dump).

-- page model + rendering (also copied into lockscreen.lua; no require: the code-section module
-- searcher has not been exercised on this firmware build)
local P = {}

P.CANVAS = { x = 15, y = 62, w = 450, h = 498 }     -- the page area in view / draw mode
P.CHARS = 34                                        -- ~13 px per glyph in the ~24 px system font
P.LINE = 26

-- Word-wraps text into lines of at most `width` characters; explicit newlines are kept.
function P.wrap(text, width)
  width = width or P.CHARS
  local out = {}
  for para in (tostring(text or '') .. '\n'):gmatch('([^\n]*)\n') do
    local line = ''
    for word in para:gmatch('%S+') do
      if line == '' then
        line = word
      elseif #line + 1 + #word <= width then
        line = line .. ' ' .. word
      else
        out[#out + 1] = line; line = word
      end
      while #line > width do out[#out + 1] = line:sub(1, width); line = line:sub(width + 1) end
    end
    out[#out + 1] = line
  end
  return out
end

-- Draws the text of a page into the canvas; `last` shows the tail instead of the head (typing).
-- Returns the number of lines drawn.
function P.draw_text(page, g, max_lines, last, caret)
  local lines = P.wrap(page.text or '')
  if caret then lines[#lines] = (lines[#lines] or '') .. '_' end
  local first = 1
  if last and #lines > max_lines then first = #lines - max_lines + 1 end
  local y, n = P.CANVAS.y + 6, 0
  for i = first, math.min(#lines, first + max_lines - 1) do
    g:text(P.CANVAS.x + 4, y, lines[i])
    y = y + P.LINE; n = n + 1
  end
  return n
end

function P.draw_shapes(page, g)
  for _, s in ipairs(page.shapes or {}) do
    if s.k == 'l' then g:line(s[1], s[2], s[3], s[4])
    elseif s.k == 'r' then g:rect(s[1], s[2], s[3], s[4])
    elseif s.k == 'c' then g:circle(s[1], s[2], s[3]) end
  end
end

-- A full page as the lock screen shows it: text, shapes, and the clock in the corner.
function P.draw_lock(page, g, clock)
  g:clear(0)
  if clock then g:text(15, 14, clock) end
  P.draw_text(page, g, 19, false, false)
  P.draw_shapes(page, g)
end

local CV = P.CANVAS
local BTN_Y, BTN_H, BTN_W, BTN_GAP, BTN_X = 580, 56, 86, 5, 15          -- 5 x 86 + 4 x 5 = 450
local LIST_Y0, LIST_ROW, LIST_ROWS = 70, 40, 12
local MAX_PAGES, MAX_TEXT, MAX_SHAPES = 12, 2000, 120

-- keyboard: rows of keys; a key is a string (types itself) or {label, units, action}
local KEY_W, KEY_H, KEY_X0, KEY_Y0, KEY_GAP = 46, 48, 1, 500, 2           -- 10 units of 48 px
local DIGITS = { '1', '2', '3', '4', '5', '6', '7', '8', '9', '0' }
local SYMBOLS = { '!', '?', ':', ';', "'", '"', '(', ')', '+', '/' }
local ROWS = {
  nil,                                                                          -- digits or symbols
  { 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p' },
  { 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', { '<-', 1, 'bs' } },
  { { 'Sh', 1, 'shift' }, 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.' },
  { { '?!', 1, 'sym' }, '-', { 'space', 5, 'space' }, { 'Ent', 1, 'enter' }, { 'Done', 2, 'done' } },
}

local S                      -- ctx.state: pages, cur, lock, shift, sym
local mode = 'view'
local tool = 'l'             -- draw tool: l / r / c
local pending = nil          -- first tap of a shape {x, y}
local page_list_page = 1
local msg = nil
local info_lines = nil
local ERR = nil

------------------------------------------------------------------ state

local function new_page() return { text = '', shapes = {} } end

local function page() return S.pages[S.cur] end

local function adopt_state(state)
  S = state
  if type(S.pages) ~= 'table' or #S.pages == 0 then S.pages = { new_page() } end
  for i, p in ipairs(S.pages) do
    if type(p) ~= 'table' then S.pages[i] = new_page() end
    if type(S.pages[i].text) ~= 'string' then S.pages[i].text = '' end
    if type(S.pages[i].shapes) ~= 'table' then S.pages[i].shapes = {} end
  end
  if math.type(S.cur) ~= 'integer' or S.cur < 1 or S.cur > #S.pages then S.cur = 1 end
  if S.lock ~= nil and (math.type(S.lock) ~= 'integer' or S.lock < 1 or S.lock > #S.pages) then S.lock = nil end
  S.shift = S.shift == true
  S.sym = S.sym == true
end

------------------------------------------------------------------ helpers

local function text_w(s)
  local ok, w = pcall(function() return g:measure_text(s) end)
  if ok and type(w) == 'number' and w > 0 then return w end
  return 13 * #s
end
local function ctext(cx, cy, s) g:text(cx - text_w(s) // 2, cy - 12, s) end
local function rtext(right, y, s) g:text(right - text_w(s), y, s) end
local function short(s, n) s = tostring(s); if #s > n then return s:sub(1, n - 1) .. '~' end return s end
local function in_canvas(x, y) return x >= CV.x and x < CV.x + CV.w and y >= CV.y and y < CV.y + CV.h end

local function title_of(p, i)
  local first = (p.text or ''):match('^[^\n]*')
  first = first:gsub('^%s+', ''):gsub('%s+$', '')
  if first == '' then return 'Page ' .. i .. (#(p.shapes or {}) > 0 and '  (drawing)' or '  (empty)') end
  return short(first, 28)
end

local function full_refresh() pcall(function() ctx.display:full_refresh() end) end

------------------------------------------------------------------ keyboard

local function key_rows()
  local rows = {}
  rows[1] = S.sym and SYMBOLS or DIGITS
  for i = 2, 5 do rows[i] = ROWS[i] end
  return rows
end

-- Walks the keyboard; calls fn(key, x, y, w, h) for every key.
local function each_key(fn)
  for r, row in ipairs(key_rows()) do
    local x = KEY_X0
    local y = KEY_Y0 + (r - 1) * (KEY_H + 4)
    for _, k in ipairs(row) do
      local units = type(k) == 'table' and k[2] or 1
      local w = units * (KEY_W + KEY_GAP) - KEY_GAP
      fn(k, x, y, w, KEY_H)
      x = x + w + KEY_GAP
    end
  end
end

local function key_label(k)
  if type(k) == 'table' then return k[1] end
  if S.shift and k:match('%l') then return k:upper() end
  return k
end

local function type_key(k)
  local p = page()
  local act = type(k) == 'table' and k[3] or 'char'
  if act == 'char' then
    if #p.text < MAX_TEXT then p.text = p.text .. key_label(k) end
    if S.shift then S.shift = false end
  elseif act == 'bs' then p.text = p.text:sub(1, -2)
  elseif act == 'space' then if #p.text < MAX_TEXT then p.text = p.text .. ' ' end
  elseif act == 'enter' then if #p.text < MAX_TEXT then p.text = p.text .. '\n' end
  elseif act == 'shift' then S.shift = not S.shift
  elseif act == 'sym' then S.sym = not S.sym
  elseif act == 'done' then mode = 'view'; full_refresh() end
end

local function tap_keyboard(x, y)
  local hit = nil
  each_key(function(k, kx, ky, w, h)
    if x >= kx and x < kx + w and y >= ky and y < ky + h then hit = k end
  end)
  if hit then type_key(hit) end
end

------------------------------------------------------------------ drawing shapes by taps

local function add_shape(x, y)
  local p = page()
  if not pending then pending = { x, y }; msg = 'tap the second point'; return end
  local a = pending; pending = nil
  if #p.shapes >= MAX_SHAPES then msg = 'shape limit reached'; return end
  if tool == 'l' then
    p.shapes[#p.shapes + 1] = { k = 'l', a[1], a[2], x, y }
  elseif tool == 'r' then
    local x0, y0 = math.min(a[1], x), math.min(a[2], y)
    local w, h = math.abs(x - a[1]), math.abs(y - a[2])
    if w >= 3 and h >= 3 then p.shapes[#p.shapes + 1] = { k = 'r', x0, y0, w, h } end
  else
    local r = math.floor(math.sqrt((x - a[1]) ^ 2 + (y - a[2]) ^ 2) + 0.5)
    if r >= 2 then p.shapes[#p.shapes + 1] = { k = 'c', a[1], a[2], r } end
  end
  msg = nil
end

------------------------------------------------------------------ lock screen (probe + action)

local function describe(t)
  local out = {}
  if type(t) ~= 'table' then return { '  ' .. type(t) } end
  local ks = {}
  pcall(function() for k in pairs(t) do ks[#ks + 1] = tostring(k) end end)
  table.sort(ks)
  for _, k in ipairs(ks) do
    local v = t[k]
    local tv = type(v)
    out[#out + 1] = '  ' .. short(k, 22) .. '  ' .. ((tv == 'function') and 'fn' or (tv:sub(1, 4) .. ' ' .. short(tostring(v), 10)))
  end
  if #out == 0 then out[1] = '  (empty)' end
  return out
end

local function build_info()
  info_lines = { 'ctx.lock:' }
  for _, l in ipairs(describe(ctx.lock)) do info_lines[#info_lines + 1] = l end
  info_lines[#info_lines + 1] = 'ctx.system:'
  for _, l in ipairs(describe(ctx.system)) do info_lines[#info_lines + 1] = l end
  info_lines[#info_lines + 1] = 'ctx.display:'
  for _, l in ipairs(describe(ctx.display)) do info_lines[#info_lines + 1] = l end
  info_lines[#info_lines + 1] = 'layers: ' .. (ctx.layers and 'yes' or 'no') .. '   lock page: ' .. tostring(S.lock)
end

-- Tries the host's lock-screen call(s); the result goes to the message line.
local function set_lock()
  S.lock = S.cur
  local results = {}
  local f = ctx.system and ctx.system.set_as_lockscreen_app
  if type(f) == 'function' then
    local ok, a, b = pcall(f)
    if not ok and tostring(a):find('self') then ok, a, b = pcall(f, ctx.system) end
    results[#results + 1] = 'set_as_lockscreen_app: ' .. (ok and (tostring(a) .. (b and (', ' .. tostring(b)) or '')) or ('error ' .. short(tostring(a), 40)))
  else
    results[#results + 1] = 'no set_as_lockscreen_app'
  end
  -- a wallpaper setter, if this host exposes one: render the page into a layer and offer it
  local setter = (ctx.lock and ctx.lock.set_wallpaper) or (ctx.system and ctx.system.set_wallpaper)
  if type(setter) == 'function' and ctx.layers then
    local ok, res = pcall(function()
      local L = ctx.layers:create(480, 800)
      L:draw_with(function(gg) P.draw_lock(page(), gg, nil) end)
      local r1, r2 = setter(L)
      if r1 == nil then r1, r2 = setter(ctx.lock or ctx.system, L) end
      return tostring(r1) .. (r2 and (' ' .. tostring(r2)) or '')
    end)
    results[#results + 1] = 'set_wallpaper: ' .. (ok and res or ('error ' .. short(tostring(res), 40)))
  end
  msg = table.concat(results, ' | ')
  info_lines = nil
end

------------------------------------------------------------------ drawing the screen

local function draw_toolbar(labels)
  local n = #labels
  local w = (450 - (n - 1) * BTN_GAP) // n
  for k, label in ipairs(labels) do
    local x = BTN_X + (k - 1) * (w + BTN_GAP)
    g:rect(x, BTN_Y, w, BTN_H)
    ctext(x + w // 2, BTN_Y + BTN_H // 2, label)
  end
  return w
end

local function toolbar_hit(x, y, n)
  if y < BTN_Y or y >= BTN_Y + BTN_H then return nil end
  local w = (450 - (n - 1) * BTN_GAP) // n
  local k = (x - BTN_X) // (w + BTN_GAP)
  if k < 0 or k >= n or x - BTN_X - k * (w + BTN_GAP) >= w then return nil end
  return k + 1
end

local function draw_header(right)
  g:text(15, 14, 'Notes  ' .. S.cur .. '/' .. #S.pages .. (S.lock == S.cur and '  *lock*' or ''))
  if right then rtext(465, 14, right) end
  g:line(15, 56, 465, 56)
end

local function draw_view()
  draw_header(nil)
  g:rect(CV.x, CV.y, CV.w, CV.h)
  P.draw_text(page(), g, 19, false, false)
  P.draw_shapes(page(), g)
  draw_toolbar({ 'Type', 'Draw', 'Pages', 'Lock', 'Info' })
  if msg then ctext(240, 668, short(msg, 36)) end
  g:line(15, 752, 465, 752)
  ctext(240, 776, 'Type to write, Draw to place shapes')
end

local function draw_type()
  draw_header((S.shift and 'SHIFT ' or '') .. (S.sym and 'SYM' or ''))
  P.draw_text(page(), g, 16, true, true)
  g:line(15, KEY_Y0 - 6, 465, KEY_Y0 - 6)
  each_key(function(k, x, y, w, h)
    g:rect(x, y, w, h)
    ctext(x + w // 2, y + h // 2, key_label(k))
  end)
end

local function draw_draw()
  draw_header(tool == 'l' and 'line' or (tool == 'r' and 'box' or 'circle'))
  g:rect(CV.x, CV.y, CV.w, CV.h)
  P.draw_text(page(), g, 19, false, false)
  P.draw_shapes(page(), g)
  if pending then
    g:line(pending[1] - 6, pending[2], pending[1] + 6, pending[2]); g:line(pending[1], pending[2] - 6, pending[1], pending[2] + 6)
  end
  draw_toolbar({ 'Line', 'Box', 'Circle', 'Undo', 'Done' })
  ctext(240, 668, msg or 'tap two points on the page')
end

local function pages_count() return math.max(1, math.ceil(#S.pages / LIST_ROWS)) end

local function draw_pages()
  g:text(15, 14, 'Pages'); rtext(465, 14, 'page ' .. page_list_page .. '/' .. pages_count())
  g:line(15, 56, 465, 56)
  local first = (page_list_page - 1) * LIST_ROWS
  for i = 1, LIST_ROWS do
    local p = S.pages[first + i]
    if not p then break end
    local y = LIST_Y0 + (i - 1) * LIST_ROW
    local mark = (first + i == S.cur) and '> ' or '  '
    g:text(25, y + 8, mark .. title_of(p, first + i))
    if first + i == S.lock then rtext(455, y + 8, 'lock') end
    g:line(15, y + LIST_ROW - 1, 465, y + LIST_ROW - 1)
  end
  draw_toolbar({ 'New', 'Delete', 'Back' })
  if msg then ctext(240, 668, short(msg, 36)) end
end

local function draw_info()
  if not info_lines then build_info() end
  g:text(15, 14, 'Lock-screen API on this host'); g:line(15, 56, 465, 56)
  local y = 66
  for i = 1, math.min(#info_lines, 19) do g:text(15, y, short(info_lines[i], 36)); y = y + 26 end
  draw_toolbar({ 'Back' })
  if msg then ctext(240, 668, short(msg, 36)) end
end

local function draw_impl()
  g:clear(0)
  if mode == 'type' then draw_type()
  elseif mode == 'draw' then draw_draw()
  elseif mode == 'pages' then draw_pages()
  elseif mode == 'info' then draw_info()
  else draw_view() end
end

------------------------------------------------------------------ input

local function tap(x, y)
  if mode == 'view' then
    local k = toolbar_hit(x, y, 5)
    if k == 1 then mode = 'type'; msg = nil
    elseif k == 2 then mode = 'draw'; pending = nil; msg = nil
    elseif k == 3 then mode = 'pages'; page_list_page = (S.cur - 1) // LIST_ROWS + 1; msg = nil
    elseif k == 4 then set_lock()
    elseif k == 5 then mode = 'info'; info_lines = nil end
  elseif mode == 'type' then
    if y >= KEY_Y0 - 4 then tap_keyboard(x, y) end
  elseif mode == 'draw' then
    local k = toolbar_hit(x, y, 5)
    if k == 1 then tool = 'l'; pending = nil
    elseif k == 2 then tool = 'r'; pending = nil
    elseif k == 3 then tool = 'c'; pending = nil
    elseif k == 4 then
      local p = page()
      if pending then pending = nil elseif #p.shapes > 0 then table.remove(p.shapes) end
      msg = nil
    elseif k == 5 then mode = 'view'; pending = nil; msg = nil; full_refresh()
    elseif in_canvas(x, y) then add_shape(x, y) end
  elseif mode == 'pages' then
    local k = toolbar_hit(x, y, 3)
    if k == 1 then
      if #S.pages >= MAX_PAGES then msg = 'page limit reached'
      else S.pages[#S.pages + 1] = new_page(); S.cur = #S.pages; mode = 'type'; msg = nil end
    elseif k == 2 then
      if #S.pages > 1 then
        table.remove(S.pages, S.cur)
        if S.lock then if S.lock == S.cur then S.lock = nil elseif S.lock > S.cur then S.lock = S.lock - 1 end end
        if S.cur > #S.pages then S.cur = #S.pages end
        msg = 'page deleted'
      else
        S.pages[1] = new_page(); msg = 'page cleared'
      end
    elseif k == 3 then mode = 'view'; msg = nil; full_refresh()
    elseif y >= LIST_Y0 and y < LIST_Y0 + LIST_ROWS * LIST_ROW then
      local i = (page_list_page - 1) * LIST_ROWS + (y - LIST_Y0) // LIST_ROW + 1
      if S.pages[i] then S.cur = i; mode = 'view'; msg = nil; full_refresh() end
    end
  elseif mode == 'info' then
    if toolbar_hit(x, y, 1) then mode = 'view'; msg = nil end
  end
end

local function input_impl(ev)
  if type(ev) ~= 'table' then return false end
  if ev.type == 'key' then
    if ev.state ~= nil and ev.state ~= 'down' then return true end
    if mode == 'view' or mode == 'draw' then
      if ev.key == 'up' and S.cur > 1 then S.cur = S.cur - 1; pending = nil; full_refresh()
      elseif ev.key == 'down' and S.cur < #S.pages then S.cur = S.cur + 1; pending = nil; full_refresh() end
    elseif mode == 'pages' then
      if ev.key == 'up' then page_list_page = math.max(1, page_list_page - 1)
      elseif ev.key == 'down' then page_list_page = math.min(pages_count(), page_list_page + 1) end
    end
    pcall(ctx.invalidate)
    return true
  end
  if ev.type == 'touch' then
    if ev.gesture == 'tap' then tap(ev.x or 0, ev.y or 0)
    elseif mode == 'view' and ev.gesture == 'swipe_left' and S.cur < #S.pages then S.cur = S.cur + 1; full_refresh()
    elseif mode == 'view' and ev.gesture == 'swipe_right' and S.cur > 1 then S.cur = S.cur - 1; full_refresh() end
    pcall(ctx.invalidate)
    return true
  end
  return false
end

local function load_impl(c)
  c = c or ctx
  if type(c.state) ~= 'table' then c.state = {} end
  adopt_state(c.state)
end

------------------------------------------------------------------ error reporting (the host only says "App error, closed")

local function show_error(where, err) ERR = where .. ': ' .. tostring(err) end

local function draw_error()
  g:clear(0)
  g:text(15, 20, 'Notes: Lua error'); g:line(15, 52, 465, 52)
  local y, s = 70, ERR
  while #s > 0 and y < 740 do g:text(15, y, s:sub(1, 36)); s = s:sub(37); y = y + 26 end
  g:text(15, 770, 'Home pad leaves the app')
end

function on_load(c)
  local ok, err = pcall(load_impl, c)
  if not ok then show_error('on_load', err) end
end

function on_draw()
  if ERR then draw_error(); return end
  local ok, err = pcall(draw_impl)
  if not ok then show_error('on_draw', err); pcall(draw_error) end
end

function on_input(_, ev)
  if ERR then return true end
  local ok, res = pcall(input_impl, ev)
  if not ok then show_error('on_input', res); pcall(ctx.invalidate); return true end
  return res
end

function on_leave() end     -- the host saves ctx.state itself

if rawget(_G, '__TEST') then
  __TEST.api = { state = function() return S end, mode = function() return mode end, page = page,
                 wrap = P.wrap, each_key = each_key, set_mode = function(m) mode = m end,
                 err = function() return ERR end, msg = function() return msg end,
                 info = function() if not info_lines then build_info() end return info_lines end }
end
