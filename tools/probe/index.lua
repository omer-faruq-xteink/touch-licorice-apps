-- API 2.9 experiment probe (round 6). Rounds 4/5 fixed the calling convention (methods, colon) and
-- showed `net:request(opts, fn)` and `input:text(opts, fn)` take a callback as the SECOND argument.
-- This round reads what those callbacks deliver, what the `input:edit{}` editor object offers,
-- whether `lockscreen:set_wallpaper(layer)` works colon-style, and how images (qr, layers,
-- image:decode) are drawn with g:image. Actions sit on the top bar so results stay readable.
--
-- Screens: Net (buttons Get / Https / Post), Keyboard (Text / Edit), Lock (Wall / Clear),
-- Image (QR / Layer), Reader (Books / Current), Misc (fonts:size mapping, clock, perf, device).
-- Swipe up/down to scroll results.

local VARIANT = 'probe'
local URL_HTTP, URL_HTTPS = 'http://example.com/', 'https://example.com/'
local URL_POST = 'http://httpbin.org/post'

local G = nil
local screen = 'menu'
local results = {}
local view_top = nil
local LINES = 32
local ERR = nil
local ticks = 0
local job = nil
local cb_log = {}
local kb_result, kb_events = nil, {}
local editor = nil
local qr_img, layer_img, decoded_img = nil, nil, nil
local draw_notes = {}

local function short(s, n) s = tostring(s); if #s > n then return s:sub(1, n - 1) .. '~' end return s end
local function add(s) results[#results + 1] = tostring(s) end
local function wrap_add(prefix, s)
  s = tostring(s); local n = 46 - #prefix
  while #s > n do add(prefix .. s:sub(1, n)); s = s:sub(n + 1); prefix = '    ' end
  add(prefix .. s)
end

local function val(v, n)
  n = n or 40
  local t = type(v)
  if t == 'string' then return '"' .. short(v:gsub('%s+', ' '), n) .. '"' end
  if t == 'table' then
    local parts, ks, orig = {}, {}, {}
    pcall(function() for k in pairs(v) do local s = tostring(k); ks[#ks + 1] = s; orig[s] = k end end)
    table.sort(ks)
    for _, k in ipairs(ks) do
      local sv = v[orig[k]]; local st = type(sv)
      parts[#parts + 1] = k .. '=' .. ((st == 'string' or st == 'number' or st == 'boolean') and short(tostring(sv), 24) or st:sub(1, 3))
    end
    return '{' .. short(table.concat(parts, ' '), n) .. '}'
  end
  if t == 'userdata' then return 'userdata' end
  return short(tostring(v), n)
end

local function try(label, f, ...)
  if type(f) ~= 'function' then add(label .. ': not a function (' .. type(f) .. ')'); return nil end
  local r = table.pack(pcall(f, ...))
  if r[1] then
    local out = {}
    for i = 2, r.n do out[#out + 1] = val(r[i], 120) end
    wrap_add(label .. ' = ', #out > 0 and table.concat(out, ', ') or '(nothing)')
    return r[2], r[3]
  else
    wrap_add(label .. ' ! ', tostring(r[2]):gsub('^%[string "[^"]*"%]:%d+: ', ''))
    return nil
  end
end

local function tryc(label, obj, name, ...)
  local f = obj and obj[name]
  if type(f) ~= 'function' then add(label .. ': not a function (' .. type(f) .. ')'); return nil end
  local args = table.pack(...)
  return try(label, function() return f(obj, table.unpack(args, 1, args.n)) end)
end

local NAMES = { 'ok', 'status', 'code', 'headers', 'body', 'bytes', 'err', 'error', 'done', 'is_done', 'poll',
  'wait', 'result', 'cancel', 'read', 'text', 'json', 'url', 'method', 'close', 'send', 'recv', 'set_text',
  'get_text', 'value', 'get_value', 'set_value', 'max_chars', 'multiline', 'on_change', 'on_end', 'on_done',
  'measure', 'size', 'height', 'width', 'ascent', 'line_height', 'name', 'focus', 'blur', 'open', 'show', 'hide',
  'draw', 'render', 'handle', 'handle_input', 'input', 'is_open', 'visible', 'cursor', 'insert', 'backspace',
  'clear', 'dispose', 'free', 'destroy', 'release', 'draw_with', 'blit', 'pixels', 'to_png', 'export', 'save',
  'encode', 'decode', 'scale', 'crop', 'rotate', 'invert', 'fill', 'rect', 'line', 'image', 'get', 'set',
  'module', 'modules', 'version', 'title', 'author', 'progress', 'page', 'pages', 'path', 'id', 'cover' }

local function names_of(label, u)
  if type(u) == 'table' then
    local ks = {}
    if pcall(function() for k in pairs(u) do ks[#ks + 1] = tostring(k) .. ':' .. type(u[k]):sub(1, 3) end end) and #ks > 0 then
      table.sort(ks); wrap_add(label .. ' ', table.concat(ks, ' ')); return
    end
  end
  local hits = {}
  for _, n in ipairs(NAMES) do
    local ok, v = pcall(function() return u[n] end)
    if ok and v ~= nil then hits[#hits + 1] = n .. ':' .. type(v):sub(1, 3) .. ((type(v) == 'number' or type(v) == 'string' or type(v) == 'boolean') and ('=' .. short(tostring(v), 10)) or '') end
  end
  local mt = getmetatable(u)
  local idx = (type(mt) == 'table' and type(mt.__index) == 'table') and mt.__index or nil
  if idx then
    local ks = {}
    pcall(function() for k in pairs(idx) do ks[#ks + 1] = tostring(k) end end)
    table.sort(ks); wrap_add(label .. ' idx: ', table.concat(ks, ' '))
  end
  if type(mt) == 'table' then
    local ks = {}
    pcall(function() for k in pairs(mt) do ks[#ks + 1] = tostring(k) end end)
    table.sort(ks); wrap_add(label .. ' mt: ', table.concat(ks, ' '))
  end
  wrap_add(label .. ' ' .. type(u) .. ': ', #hits > 0 and table.concat(hits, ' ') or 'no known names')
end

local function refresh() pcall(function() ctx.invalidate() end) end

-- a callback that logs every argument in detail
local function logger(tag)
  return function(...)
    local a = table.pack(...)
    cb_log[#cb_log + 1] = tag .. ' cb: ' .. a.n .. ' args'
    for i = 1, a.n do
      local v = a[i]
      cb_log[#cb_log + 1] = '  [' .. i .. '] ' .. type(v) .. ' ' .. val(v, 160)
      if type(v) == 'table' then
        for _, k in ipairs({ 'body', 'text', 'data', 'headers', 'error', 'err' }) do
          local x = v[k]
          if type(x) == 'string' then cb_log[#cb_log + 1] = '    .' .. k .. ' ' .. #x .. ' bytes: ' .. val(x, 200)
          elseif type(x) == 'table' then cb_log[#cb_log + 1] = '    .' .. k .. ' ' .. val(x, 200) end
        end
      elseif type(v) == 'userdata' then
        local hits = {}
        for _, k in ipairs({ 'status', 'body', 'text', 'headers', 'ok', 'error' }) do
          local okk, x = pcall(function() return v[k] end)
          if okk and x ~= nil then hits[#hits + 1] = k .. ':' .. type(x):sub(1, 3) end
        end
        cb_log[#cb_log + 1] = '    ud members: ' .. table.concat(hits, ' ')
      end
      if type(v) == 'string' then kb_result = kb_result or v end
    end
    refresh()
  end
end

------------------------------------------------------------------ experiments

local function run_net()
  results = {}; view_top = nil; cb_log = {}
  add('== net ==  Get / Https / Post on the top bar')
  local net = ctx.net
  if not net then add('ctx.net is nil'); return end
  tryc('net:keep_wifi(120)', net, 'keep_wifi', 120)
  tryc("net:request({}, fn)", net, 'request', {}, logger('empty'))
  tryc("net:request({url='x'}, fn)", net, 'request', { url = 'x' }, logger('badurl'))
  add('results of the callbacks appear below as they arrive')
end

local function net_get(url, tag)
  local net = ctx.net; if not net then return end
  add('-- ' .. tag .. ' ' .. url .. ' (tick ' .. ticks .. ')')
  local a = tryc('net:request({url,method}, fn)', net, 'request', { url = url, method = 'GET', timeout_ms = 15000 }, logger(tag))
  if a ~= nil then job = a; names_of('job', a) end
end

local function net_post()
  local net = ctx.net; if not net then return end
  add('-- POST (tick ' .. ticks .. ')')
  local a = tryc('net:request({url,POST,body,headers}, fn)', net, 'request',
    { url = URL_POST, method = 'POST', body = '{"probe":1}', headers = { ['Content-Type'] = 'application/json' } }, logger('post'))
  if a ~= nil then job = a; names_of('job', a) end
end

local function run_keyboard()
  results = {}; view_top = nil; cb_log = {}
  add('== keyboard ==  Text / Edit on the top bar')
  add('kb result: ' .. val(kb_result, 40))
  if editor ~= nil then
    names_of('editor', editor)
    for _, n in ipairs({ 'get_text', 'text', 'value', 'get_value', 'is_open', 'visible' }) do
      local ok, f = pcall(function() return editor[n] end)
      if ok and f ~= nil then
        if type(f) == 'function' then tryc('editor:' .. n .. '()', editor, n) else add('  editor.' .. n .. ' = ' .. val(f, 40)) end
      end
    end
  end
  for _, s in ipairs(kb_events) do wrap_add('  ', s) end
end

local function kb_text()
  local inp = ctx.input; if not inp then return end
  add('-- input:text (tick ' .. ticks .. ')')
  tryc("input:text({title,value}, fn)", inp, 'text', { title = 'Probe title', value = 'abc', placeholder = 'type here', max_chars = 60 }, logger('text'))
end

local function kb_edit()
  local inp = ctx.input; if not inp then return end
  add('-- input:edit (tick ' .. ticks .. ')')
  if editor ~= nil then
    for _, n in ipairs({ 'close', 'hide', 'dispose' }) do
      if type(editor[n]) == 'function' then tryc('old editor:' .. n .. '()', editor, n); break end
    end
  end
  editor = tryc("input:edit({text,on_change,on_done})", inp, 'edit',
    { text = 'init', value = 'init', title = 'Edit probe', multiline = false, on_change = logger('edit.on_change'), on_done = logger('edit.on_done'), on_end = logger('edit.on_end'), on_submit = logger('edit.on_submit') })
  if editor ~= nil then names_of('editor', editor) end
end

local function run_lock()
  results = {}; view_top = nil
  add('== lock ==  Wall / Clear on the top bar')
  local L = ctx.lockscreen
  if L == nil then add('ctx.lockscreen is nil'); return end
  names_of('lockscreen', L)
  tryc('lockscreen:is_default()', L, 'is_default')
  tryc('lockscreen:is_wallpaper()', L, 'is_wallpaper')
  names_of('layers', ctx.layers)
  tryc('layers:create()', ctx.layers, 'create')
  tryc('layers:create(10)', ctx.layers, 'create', 10)
end

local function make_layer()
  local Ly = ctx.layers; if not Ly then add('ctx.layers nil'); return nil end
  local layer = tryc('layers:create(480,800)', Ly, 'create', 480, 800)
  if layer == nil then return nil end
  names_of('layer', layer)
  tryc('layer:draw_with(fn)', layer, 'draw_with', function(gg)
    gg:clear(0); gg:text(20, 40, 'probe wallpaper 2.9 r6'); gg:rect(20, 80, 440, 300); gg:circle(240, 500, 100)
  end)
  return layer
end

local function lock_wall()
  local L = ctx.lockscreen; if not L then return end
  add('-- set_wallpaper (tick ' .. ticks .. ')')
  local layer = make_layer()
  if layer ~= nil then
    layer_img = layer
    tryc('lockscreen:set_wallpaper(layer)', L, 'set_wallpaper', layer)
    tryc('lockscreen:set_wallpaper(layer, {})', L, 'set_wallpaper', layer, {})
  end
  tryc('lockscreen:set_wallpaper(fn)', L, 'set_wallpaper', function(gg) gg:clear(0); gg:text(20, 40, 'wallpaper fn') end)
  if qr_img then tryc('lockscreen:set_wallpaper(qr)', L, 'set_wallpaper', qr_img) end
  tryc('lockscreen:is_wallpaper()', L, 'is_wallpaper')
  tryc('lockscreen:is_default()', L, 'is_default')
end

local function lock_clear()
  local L = ctx.lockscreen; if not L then return end
  add('-- clear (tick ' .. ticks .. ')')
  tryc('lockscreen:clear_wallpaper()', L, 'clear_wallpaper')
  tryc('lockscreen:is_wallpaper()', L, 'is_wallpaper')
end

local function run_image()
  results = {}; view_top = nil; draw_notes = {}
  add('== image ==  QR / Layer on the top bar; drawings at the bottom')
  names_of('image', ctx.image)
  names_of('qr', ctx.qr)
  tryc("image:decode()", ctx.image, 'decode')
  tryc("image:decode('x')", ctx.image, 'decode', 'x')
  tryc("image:decode('x', {})", ctx.image, 'decode', 'x', {})
  tryc("image:decode('x', 10, 10)", ctx.image, 'decode', 'x', 10, 10)
  local gm = G and getmetatable(G)
  if type(gm) == 'table' and type(gm.__index) == 'table' then
    local ks = {}
    for k in pairs(gm.__index) do ks[#ks + 1] = tostring(k) end
    table.sort(ks); wrap_add('g methods: ', table.concat(ks, ' '))
  end
end

local function image_qr()
  add('-- qr (tick ' .. ticks .. ')')
  qr_img = tryc("qr:encode('https://example.com')", ctx.qr, 'encode', 'https://example.com')
  if qr_img ~= nil then
    names_of('qr img', qr_img)
    for _, n in ipairs({ 'width', 'height', 'size', 'modules', 'w', 'h' }) do
      local ok, v = pcall(function() return qr_img[n] end)
      if ok and v ~= nil then add('  qr.' .. n .. ' = ' .. val(type(v) == 'function' and select(2, pcall(v, qr_img)) or v, 30)) end
    end
  end
  tryc("qr:encode('x', {size=200})", ctx.qr, 'encode', 'x', { size = 200, scale = 4, module = 4 })
  tryc("qr:encode('x', 200)", ctx.qr, 'encode', 'x', 200)
end

local function image_layer()
  add('-- layer (tick ' .. ticks .. ')')
  layer_img = make_layer()
  if layer_img then
    for _, n in ipairs({ 'width', 'height', 'size', 'w', 'h' }) do
      local ok, v = pcall(function() return layer_img[n] end)
      if ok and v ~= nil then add('  layer.' .. n .. ' = ' .. val(type(v) == 'function' and select(2, pcall(v, layer_img)) or v, 30)) end
    end
    tryc('layer:to_png()', layer_img, 'to_png')
    tryc('layer:export()', layer_img, 'export')
    tryc('layer:pixels()', layer_img, 'pixels')
    tryc("layer:save('wall.bmp')", layer_img, 'save', 'wall.bmp')
    tryc("storage:write('layer.bin', layer)", ctx.storage, 'write', 'layer.bin', layer_img)
    tryc("image:encode(layer)", ctx.image, 'encode', layer_img)
    tryc("image:decode(storage:read('probe.txt'))", ctx.image, 'decode', select(2, pcall(function() return ctx.storage:read('probe.txt') end)))
  end
end

local function draw_image_samples(gg)
  local y = 560
  local function note(s) draw_notes[#draw_notes + 1] = s end
  draw_notes = {}
  if qr_img then
    local ok, e = pcall(function() gg:image(10, y, qr_img) end); note('g:image(x,y,qr) ' .. (ok and 'ok' or short(tostring(e), 30)))
    if not ok then ok, e = pcall(function() gg:image(qr_img, 10, y) end); note('g:image(qr,x,y) ' .. (ok and 'ok' or short(tostring(e), 30))) end
    if not ok then ok, e = pcall(function() gg:image(10, y, 150, 150, qr_img) end); note('g:image(x,y,w,h,qr) ' .. (ok and 'ok' or short(tostring(e), 30))) end
  end
  if layer_img then
    local ok, e = pcall(function() gg:image(240, y, layer_img) end); note('g:image(x,y,layer) ' .. (ok and 'ok' or short(tostring(e), 30)))
    if not ok then ok, e = pcall(function() gg:layer(240, y, layer_img) end); note('g:layer(x,y,layer) ' .. (ok and 'ok' or short(tostring(e), 30))) end
    if not ok then ok, e = pcall(function() gg:blit(layer_img, 240, y) end); note('g:blit ' .. (ok and 'ok' or short(tostring(e), 30))) end
  end
  local ok, e = pcall(function() gg:pattern(10, 740, 100, 40, 1) end); note('g:pattern(x,y,w,h,1) ' .. (ok and 'ok' or short(tostring(e), 30)))
  ok, e = pcall(function() gg:polygon({ 130, 740, 180, 780, 230, 740 }) end); note('g:polygon{...} ' .. (ok and 'ok' or short(tostring(e), 30)))
  ok, e = pcall(function() gg:arc(300, 760, 20, 0, 180) end); note('g:arc ' .. (ok and 'ok' or short(tostring(e), 30)))
  local yy = 300
  for _, s in ipairs(draw_notes) do pcall(function() gg:text(10, yy, s) end); yy = yy + 22 end
end

local function run_reader()
  results = {}; view_top = nil
  add('== reader ==  Books / Current on the top bar')
  local R = ctx.reader
  if not R then add('ctx.reader is nil (permission reader?)'); return end
  names_of('reader', R)
  tryc('reader:summary()', R, 'summary')
  tryc('reader:days()', R, 'days')
  tryc('reader:days(7)', R, 'days', 7)
end

local function reader_books()
  local R = ctx.reader; if not R then return end
  add('-- books (tick ' .. ticks .. ')')
  local b = tryc('reader:books()', R, 'books')
  if b == nil then b = tryc('reader:books(5)', R, 'books', 5) end
  if type(b) == 'table' and b[1] ~= nil then
    add('  books[1] = ' .. val(b[1], 200))
    local id = b[1].id or b[1].path or b[1].book_id
    if id ~= nil then
      tryc('reader:book_days(id)', R, 'book_days', id)
      tryc('reader:cover(id)', R, 'cover', id)
    end
  end
  tryc('reader:all_books()', R, 'all_books')
end

local function reader_current()
  local R = ctx.reader; if not R then return end
  add('-- current (tick ' .. ticks .. ')')
  local c = tryc('reader:current()', R, 'current')
  if type(c) == 'table' then add('  current = ' .. val(c, 300)) end
end

local function run_misc()
  results = {}; view_top = nil
  add('== misc ==  ticks ' .. ticks)
  local F = ctx.fonts
  if F then
    for _, n in ipairs({ 8, 12, 16, 20, 24, 28, 32, 36, 48, 64 }) do
      local f = select(2, pcall(function() return F:size(n) end))
      if type(f) == 'userdata' then
        add('  size(' .. n .. '): ' .. tostring(f.name) .. ' lh ' .. tostring(f.line_height) .. ' asc ' .. tostring(f.ascent) .. ' Hello=' .. tostring(select(2, pcall(function() return f:measure('Hello') end))))
      else add('  size(' .. n .. ') -> ' .. val(f, 30)) end
    end
  end
  tryc('clock:now()', ctx.clock, 'now')
  tryc('perf:info()', ctx.perf, 'info')
  tryc('device:battery()', ctx.device, 'battery')
  tryc('device:os()', ctx.device, 'os')
  add('device.firmware = ' .. val(ctx.device and ctx.device.firmware, 40) .. '  name ' .. val(ctx.device and ctx.device.name, 20))
  add('device.id_for_app = ' .. val(ctx.device and (ctx.device.id_for_app or ctx.device.id_for_this_app), 40) .. ' lock_timer ' .. tostring(ctx.device and ctx.device.lock_timer))
  add('budget = ' .. val(ctx.budget, 90))
  add('package = ' .. val(ctx.package, 90))
  add('api = ' .. val(ctx.api, 90))
  add('screen = ' .. val(ctx.screen, 90))
  tryc("i18n:t('cancel')", ctx.i18n, 't', 'cancel')
  add('i18n.locale = ' .. val(ctx.i18n and ctx.i18n.locale, 20))
  tryc("dialog:confirm({title,text}, fn)", ctx.dialog, 'confirm', { title = 'Probe', text = 'Confirm works?', message = 'Confirm works?', ok = 'Yes', cancel = 'No' }, logger('confirm'))
  add('state: ' .. val(ctx.state, 60))
  pcall(function() ctx.state = ctx.state or {}; ctx.state.runs = (ctx.state.runs or 0) + 1 end)
  try('save_state()', ctx.save_state)
  tryc('gc()', ctx, 'gc')
  tryc("log('probe')", ctx, 'log', 'probe r6')
  tryc('defer_full_refresh()', ctx, 'defer_full_refresh')
end

------------------------------------------------------------------ screens

local MENU = { 'net', 'keyboard', 'lock', 'image', 'reader', 'misc' }
local BTN_W, BTN_H = 220, 56

local function menu_rect(i)
  local col, row = (i - 1) % 2, (i - 1) // 2
  return 15 + col * (BTN_W + 10), 90 + row * (BTN_H + 12), BTN_W, BTN_H
end

local ACTIONS = {
  net = { { 'Get', function() net_get(URL_HTTP, 'http') end }, { 'Https', function() net_get(URL_HTTPS, 'https') end }, { 'Post', net_post } },
  keyboard = { { 'Text', kb_text }, { 'Edit', kb_edit }, { 'Redo', nil } },
  lock = { { 'Wall', lock_wall }, { 'Clear', lock_clear }, { 'Redo', nil } },
  image = { { 'QR', image_qr }, { 'Layer', image_layer }, { 'Redo', nil } },
  reader = { { 'Books', reader_books }, { 'Current', reader_current }, { 'Redo', nil } },
  misc = { { 'Redo', nil }, { '', nil }, { '', nil } },
}

local function open(name)
  screen = name
  if name == 'net' then run_net() elseif name == 'keyboard' then run_keyboard()
  elseif name == 'lock' then run_lock() elseif name == 'image' then run_image()
  elseif name == 'reader' then run_reader() elseif name == 'misc' then run_misc() end
end

local function first_line()
  local tail = math.max(1, #results - LINES + 1)
  if view_top == nil then return tail end
  if view_top > tail then view_top = tail end
  if view_top < 1 then view_top = 1 end
  return view_top
end

local function draw_impl(gg)
  pcall(function() gg:clear(0) end)
  if screen == 'menu' then
    gg:text(15, 20, 'API 2.9 probe r6  v' .. VARIANT .. '  ticks ' .. ticks)
    gg:text(15, 46, 'tap an experiment')
    for i, n in ipairs(MENU) do
      local x, y, w, h = menu_rect(i)
      gg:rect(x, y, w, h); gg:text(x + 16, y + 16, n)
    end
    gg:text(15, 400, 'kb: ' .. val(kb_result, 40))
    gg:text(15, 426, 'job: ' .. (job and type(job) or 'none') .. '  cb lines: ' .. #cb_log .. '  state.runs ' .. tostring(ctx.state and ctx.state.runs))
    local y = 460
    for i = math.max(1, #cb_log - 12), #cb_log do gg:text(15, y, short(cb_log[i], 46)); y = y + 22 end
    if ERR then gg:text(15, 770, short('ERR ' .. ERR, 46)) end
    return
  end
  local acts = ACTIONS[screen] or {}
  gg:rect(10, 8, 100, 40); gg:text(22, 16, 'Back')
  for i = 1, 3 do
    local a = acts[i]
    if a and a[1] ~= '' then gg:rect(10 + i * 120, 8, 100, 40); gg:text(22 + i * 120, 16, a[1]) end
  end
  gg:line(0, 54, 480, 54)
  local y = 62
  local lines = {}
  for _, s in ipairs(results) do lines[#lines + 1] = s end
  for _, s in ipairs(cb_log) do lines[#lines + 1] = s end
  local tail = math.max(1, #lines - LINES + 1)
  local first = view_top or tail
  if first > tail then first = tail end
  if first < 1 then first = 1 end
  local last = math.min(#lines, first + LINES - 1)
  if screen == 'image' then last = math.min(last, first + 9) end
  for i = first, last do gg:text(10, y, short(lines[i], 46)); y = y + 22 end
  if first > 1 or last < #lines then gg:text(380, 770, first .. '-' .. last .. '/' .. #lines) end
  if screen == 'image' then draw_image_samples(gg) end
  if ERR then gg:text(10, 770, short('ERR ' .. ERR, 46)) end
end

function on_draw(c, gg)
  G = gg or G
  if not G then return end
  local ok, err = pcall(draw_impl, G)
  if not ok then ERR = tostring(err); pcall(function() G:text(10, 740, short('draw ERR ' .. ERR, 46)) end) end
end

local function scroll(delta)
  local total = #results + #cb_log
  local tail = math.max(1, total - LINES + 1)
  local cur = view_top or tail
  view_top = math.max(1, math.min(tail, cur + delta))
end

local function tap(x, y)
  if screen == 'menu' then
    for i, n in ipairs(MENU) do
      local bx, by, bw, bh = menu_rect(i)
      if x >= bx and x < bx + bw and y >= by and y < by + bh then open(n); return end
    end
    return
  end
  if y < 50 then
    if x >= 10 and x < 110 then screen = 'menu'; return end
    local acts = ACTIONS[screen] or {}
    for i = 1, 3 do
      if x >= 10 + i * 120 and x < 110 + i * 120 then
        local a = acts[i]
        if a and a[1] == 'Redo' then open(screen)
        elseif a and a[2] then view_top = nil; local ok, e = pcall(a[2]); if not ok then add('action ! ' .. short(tostring(e), 60)) end end
        return
      end
    end
  end
end

function on_input(c, ev)
  local ok, err = pcall(function()
    if type(ev) ~= 'table' then return end
    if ev.type == 'pointer' then
      if ev.phase == 'up' then
        if ev.gesture == 'swipe_up' then scroll(LINES - 4)
        elseif ev.gesture == 'swipe_down' then scroll(-(LINES - 4))
        elseif ev.gesture == nil or ev.gesture == 'tap' then tap(ev.x or 0, ev.y or 0) end
      end
    elseif ev.type == 'key' then
      if screen ~= 'menu' and (ev.key == 'back') then screen = 'menu' end
    else
      kb_events[#kb_events + 1] = 'event ' .. val(ev, 120)
      if type(ev.text) == 'string' then kb_result = ev.text end
    end
  end)
  if not ok then ERR = tostring(err) end
  refresh()
  return true
end

function on_tick(c, n)
  ticks = ticks + 1
end

function on_load(c)
  pcall(function() ctx.set_tick(200) end)
end

function on_leave() end
