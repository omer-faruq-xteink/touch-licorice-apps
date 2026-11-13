-- xkcd for XTOS Licorice, API 2.26 (uses tools/gamekit and src/xk.lua). Needs Wi-Fi for comics not
-- saved yet.
--
-- Opens on the latest comic. Its JSON (xkcd.com/info.0.json, or xkcd.com/<n>/info.0.json) gives the
-- title, the alt text and the picture's address; the picture is saved straight to a private file
-- (save = { to = "storage" }, up to 256 KB) and decoded from there. A picture wider or taller than
-- the 1024 px the reader decodes, or over 256 KB, comes once more through images.weserv.nl,
-- reduced. A wide comic turns the screen to landscape, a tall one back to portrait. The last 20
-- comics stay saved (cache.txt and their pictures), so they open without Wi-Fi.

local X = require('xk')

local W, H = kit.W, kit.H      -- the screen now (sync_screen)
local BTN_H, HEAD_H = 60, 62
local MSG_H = 26                -- a row above the buttons for messages, kept free

local KEEP = 20                 -- comics kept for reading offline
local UA = 'XteinkLicoriceXKCD/1.0 (https://github.com/omer-faruq/touch-licorice-apps)'

local cfg = { last = nil, lockevery = '6' }
local screen = 'comic'          -- comic | alt | favs | settings
local cur = nil                 -- the comic shown: { c, img, file, kind, reduced }
local latest = nil              -- the latest number, once known
local loading, status, ERR = nil, nil, nil
local offline = false           -- the last fetch failed for want of a network, with nothing to show
local job = nil                 -- the request out
local qr = nil                  -- { url, img } the QR code drawn
local zoom = nil                -- the comic at full size: { img, sx, sy, vw, vh } (the part shown)
local down = nil                -- where the finger went down (a move over 20 px is a drag)
local fav_page = 1

------------------------------------------------------------------ settings and saved comics

local function load_cfg()
  local t = kit.kv(kit.read('settings.txt'))
  cfg.last = tonumber(t.last)
  if t.lockevery == '0' or t.lockevery == '3' or t.lockevery == '6' or t.lockevery == '12' then cfg.lockevery = t.lockevery end
end
local function save_cfg()
  kit.write('settings.txt', 'last=' .. tostring(cfg.last or '') .. '\nlockevery=' .. cfg.lockevery)
end

-- cache.txt: one comic a line, newest viewed first: "<kind>[:<w>x<h>]\t<X.line>"; kind png (the
-- picture as shown, made by the resizer), none (interactive: no picture); w x h the original's size
local function cache_list()
  local out = {}
  for line in (kit.read('cache.txt') or ''):gmatch('[^\n]+') do
    local head, rest = line:match('^([^\t]+)\t(.*)$')
    local c = rest and X.parse_line(rest)
    local sw, sh, kind
    if head then sw, sh = head:match(':(%d+)x(%d+)'); kind = head:match('^%a+') end
    -- a picture saved before the resizer (no size noted: "png", "jpg", "rjpg") is fetched again
    if c and (kind == 'none' or sw) then
      out[#out + 1] = { kind = kind, c = c, sw = tonumber(sw), sh = tonumber(sh) }
    end
  end
  return out
end
local function pic_name(n, kind)
  if kind == 'none' then return nil end
  return 'c_' .. n .. (kind == 'png' and '.png' or '.jpg')
end
local function cache_get(n)
  for _k, e in ipairs(cache_list()) do if e.c.num == n then return e end end
  return nil
end
local function cache_head(kind, sw, sh) return kind .. ((sw and sh) and (':' .. sw .. 'x' .. sh) or '') end
-- this comic first; the ones past KEEP dropped with their pictures
local function cache_put(c, kind, sw, sh)
  local list, keep = cache_list(), {}
  keep[1] = cache_head(kind, sw, sh) .. '\t' .. X.line(c)
  for _k, e in ipairs(list) do
    if e.c.num ~= c.num then
      if #keep < KEEP then keep[#keep + 1] = cache_head(e.kind, e.sw, e.sh) .. '\t' .. X.line(e.c)
      else
        local f = pic_name(e.c.num, e.kind)
        if f then pcall(function() ctx.storage:remove(f) end) end
      end
    end
  end
  kit.write('cache.txt', table.concat(keep, '\n'))
end

-- favourites.txt: "n<TAB>title" lines, in the order added
local function favs()
  local out = {}
  for n, t in (kit.read('favourites.txt') or ''):gmatch('(%d+)\t([^\n]*)') do out[#out + 1] = { n = tonumber(n), title = t } end
  return out
end
local function is_fav(n)
  for _k, f in ipairs(favs()) do if f.n == n then return true end end
  return false
end
local function toggle_fav(c)
  local out, found = {}, false
  for _k, f in ipairs(favs()) do
    if f.n == c.num then found = true else out[#out + 1] = f.n .. '\t' .. f.title end
  end
  if not found then out[#out + 1] = c.num .. '\t' .. (c.title:gsub('[\t\n]', ' ')) end
  kit.write('favourites.txt', table.concat(out, '\n'))
end

------------------------------------------------------------------ screen

local function sync_screen()
  local okw, w = pcall(function() return tonumber(ctx.screen.width) end)
  local okh, h = pcall(function() return tonumber(ctx.screen.height) end)
  W, H = okw and w or 480, okh and h or 800
  kit.W, kit.H = W, H
end
local function turn(landscape)
  local want = landscape and 'landscape' or 'portrait'
  if (W > H) ~= landscape then
    pcall(function() ctx.screen:set_orientation(want) end)
    sync_screen()
  end
end
local function btn_y() return H - BTN_H - 8 end

-- the alt text under a portrait comic: at most 6 lines, the last one cut
local ALT_LINES = 6
local function alt_lines(c)
  local lines = kit.wrap(c.alt, 'small', W - 24)
  if #lines > ALT_LINES then
    lines[ALT_LINES] = kit.short(lines[ALT_LINES], math.max(4, #lines[ALT_LINES] - 3)) .. '..'
    for k = #lines, ALT_LINES + 1, -1 do lines[k] = nil end
  end
  return lines
end
-- where the comic goes: x, y, w, h
local function comic_area(c)
  c = c or (cur and cur.c)
  local top, bottom = HEAD_H, btn_y() - 8 - MSG_H
  if W <= H and c then bottom = bottom - #alt_lines(c) * (kit.line_h('small') + 2) - 8 end
  return 0, top, W, math.max(40, bottom - top)
end

------------------------------------------------------------------ network

local function drop()
  if job then pcall(function() job:cancel() end) end
  job, loading = nil, nil
end
-- res as one of: ok (2xx), 'net' (no network or no answer), or an error text
local function failed(res)
  if type(res) ~= 'table' then return 'net' end
  if res.ok == false then return 'net' end
  local code = tonumber(res.status) or 0
  if code >= 400 then return 'HTTP ' .. code end
  return nil
end
local function get(url, save, label, fn, headers)
  drop()
  loading = label
  local req = { url = url, method = 'GET', timeout_ms = 30000, headers = { ['User-Agent'] = UA } }
  for k, v in pairs(headers or {}) do req.headers[k] = v end
  if save then req.save = { to = 'storage', name = save } end
  local ok, j = pcall(function()
    return ctx.net:request(req, function(c, res)
      job, loading = nil, nil
      local okc, e = pcall(fn, res)
      if not okc then ERR = tostring(e) end
      kit.refresh()
    end)
  end)
  if ok and j then job = j; return end
  loading = nil
  local okc, e = pcall(fn, nil)
  if not okc then ERR = tostring(e) end
end

------------------------------------------------------------------ showing a comic

local function unzoom()
  if zoom and zoom.img then pcall(function() zoom.img:release() end) end
  zoom = nil
end
local function release()
  unzoom()
  if cur and cur.img then pcall(function() cur.img:release() end) end
end

local LOCK_W, LOCK_H = 464, 680  -- the sleep screen's picture (src/lock/lock.lua draws it in this box)
local function now_sec()
  local now = 0
  pcall(function() now = math.floor(tonumber(ctx.clock:now().epoch_sec) or 0) end)
  return now
end
-- the latest comic, also kept for the sleep screen (lock.txt, lock.png), made for its size: the
-- store's build gives the sleep screen no network, so this is what it shows there
local function keep_for_lock(c, kind, sw, sh)
  local s = kit.read('lock.txt') or ''
  if s:match('^%a+\t' .. c.num .. '\t') then return end           -- has it already
  if kind == 'none' then kit.write('lock.txt', 'none\t' .. X.line(c) .. '\nat=' .. now_sec()); return end
  get(X.weserv_url(c.img, LOCK_W, LOCK_H, sw, sh), 'lock.png', nil, function(res)
    if failed(res) or not res.saved then return end
    pcall(function() ctx.storage:remove('lock.jpg') end)
    kit.write('lock.txt', 'png\t' .. X.line(c) .. '\nat=' .. now_sec())
  end)
end

-- show comic c from its saved picture (kind png; none: no picture), the screen turned for its shape
local function display(c, kind, sw, sh)
  release()
  status, offline, screen = nil, false, 'comic'
  cfg.last = c.num
  save_cfg()
  if kind == 'none' then
    turn(false)
    cur = { c = c, kind = 'none' }
    cache_put(c, 'none')
    if latest and c.num >= latest then keep_for_lock(c, 'none') end
    return
  end
  local file = pic_name(c.num, kind)
  local b = kit.read(file)
  local w, h = X.png_size(b or '')
  if b and not w then                             -- an older saved JPEG: its size from a decode
    local ok, im = pcall(function() return ctx.image:decode(b, { max_w = X.MAX_SIDE, max_h = X.MAX_SIDE }) end)
    if ok and im then w, h = tonumber(im.width), tonumber(im.height); pcall(function() im:release() end) end
  end
  if not w then
    turn(false)
    cur = { c = c, kind = 'none', err = 'the saved picture is gone' }
    return
  end
  turn(X.landscape(w, h))
  cur = { c = c, file = file, kind = kind, sw = sw, sh = sh,
          reduced = (sw or 0) > X.MAX_SIDE or (sh or 0) > X.MAX_SIDE }
  local _x, _y, aw, ah = comic_area()
  pcall(function() ctx.budget:extend() end)
  local ok, im, err = pcall(function() return ctx.image:decode(b, { max_w = aw, max_h = ah }) end)
  if ok and im then cur.img = im else cur.kind, cur.err = 'none', tostring(ok and err or im) end
  cache_put(c, kind, sw, sh)
  if latest and c.num >= latest then keep_for_lock(c, kind, sw, sh) end
end

-- the picture of c: first the original's size (its first 64 bytes: a PNG says it there), to turn
-- the screen for its shape; then the resizer makes it for exactly the space it gets (X.weserv_url)
local function fetch_picture(c)
  local function fail(f)
    cur = cur and cur.c and cur.c.num == c.num and cur or { c = c, kind = 'none' }
    status = f == 'net' and 'Picture: no network.' or ('Picture failed: ' .. tostring(f))
  end
  get(c.img, nil, 'Loading the picture...', function(res)
    local f = failed(res)
    if f == 'net' then fail(f); return end
    local sw, sh
    if not f and type(res.body) == 'string' then sw, sh = X.png_size(res.body) end
    turn(sw and X.landscape(sw, sh) or false)
    local _x, _y, aw, ah = comic_area(c)
    local file = pic_name(c.num, 'png')
    get(X.weserv_url(c.img, aw, ah, sw, sh), file, 'Loading the picture...', function(r2)
      local f2 = failed(r2)
      if f2 then fail(f2)
      elseif r2.saved then display(c, 'png', sw, sh)
      else fail(r2.err) end
    end)
  end, { Range = 'bytes=0-63' })
end

-- the comic n (nil: the latest): a saved one at once, else its JSON, then its picture
local show
local function newest_saved()
  local e = cfg.last and cache_get(cfg.last)
  if e then return e end
  local best = nil
  for _k, x in ipairs(cache_list()) do if not best or x.c.num > best.c.num then best = x end end
  return best
end
show = function(n)
  drop()
  status = nil
  if n then
    local e = cache_get(n)
    if e then display(e.c, e.kind, e.sw, e.sh); return end
  end
  get(X.json_url(n), nil, n and ('Loading comic ' .. n .. '...') or 'Loading the latest comic...', function(res)
    local f = failed(res)
    if f then
      if not cur then
        local e = newest_saved()
        if e then display(e.c, e.kind, e.sw, e.sh); if not n then status = 'No network: a saved comic.' end; return end
        offline = true
        return
      end
      status = (f == 'net') and 'Not saved on the reader: needs Wi-Fi.' or ('Comic not found (' .. f .. ').')
      return
    end
    local okd, d = pcall(function() return ctx.json:decode(res.body) end)
    local c = okd and X.comic(d)
    if not c then status = 'Not a comic.'; return end
    if not n then latest = c.num end
    local e = cache_get(c.num)
    if e then display(e.c, e.kind, e.sw, e.sh)
    elseif c.interactive then display(c, 'none')
    else fetch_picture(c) end
  end)
end

local function step(d)
  if not cur then return end
  unzoom()
  local n = cur.c.num + d
  if n == 404 then n = n + d end
  if n < 1 then status = 'This is the first.'; return end
  if d > 0 and latest and n > latest then status = 'This is the latest.'; return end
  show(n)
end

------------------------------------------------------------------ drawing

local function buttons()
  if screen == 'alt' then return { 'Close' } end
  if screen == 'settings' then return { 'Back' } end
  if screen == 'favs' then return { 'Back', 'Prev', 'Next' } end
  if not cur then return { 'Reload' } end
  return { 'Prev', 'Random', 'Alt', 'More', 'Next' }
end
local function button_rects()
  local bs, out = buttons(), {}
  local n = #bs
  local bw = (W - 24 - (n - 1) * 8) // n
  for k, b in ipairs(bs) do out[k] = { x = 12 + (k - 1) * (bw + 8), y = btn_y(), w = bw, h = BTN_H, b = b } end
  return out
end

local function draw_qr(gg, url, y, size)
  if not qr or qr.url ~= url then
    if qr and qr.img then pcall(function() qr.img:release() end) end
    local ok, img = pcall(function() return ctx.qr:encode(url) end)
    qr = { url = url, img = ok and img or nil }
  end
  if qr.img then
    pcall(function()
      local w = tonumber(qr.img.width) or 0
      local s = w > 0 and w * math.max(1, size // w) or size
      gg:image(qr.img, (W - s) // 2, y, { w = s, h = s })
    end)
  end
end

-- the star at the top right: filled for a favourite
local function star_rect() return { x = W - 60, y = 4, w = 52, h = 52 } end
local function draw_star(gg, on)
  local r = star_rect()
  local cx, cy = r.x + 26, r.y + 26
  local pts = {}
  for k = 0, 9 do
    local a = -math.pi / 2 + k * math.pi / 5
    local rr = (k % 2 == 0) and 20 or 8
    pts[#pts + 1] = math.floor(cx + rr * math.cos(a) + 0.5)
    pts[#pts + 1] = math.floor(cy + rr * math.sin(a) + 0.5)
  end
  if on then gg:polygon(pts, { fill = true })
  else
    pts[#pts + 1], pts[#pts + 2] = pts[1], pts[2]
    gg:polyline(pts, { line_width = 2 })
  end
end

local function draw_header(gg, c)
  local title = c.num .. ': ' .. c.title
  local f = kit.font('medium')
  while #title > 4 and kit.width(f, title) > W - 84 do title = kit.drop_last(title) end
  gg:text(12, 8, title, { font = f })
  local sub = c.date .. (cur.reduced and '   (reduced)' or '') .. (zoom and '   (zoomed: drag, tap to fit)' or '')
  gg:text(12, 36, sub, { font = kit.font('small') })
  draw_star(gg, is_fav(c.num))
end

------------------------------------------------------------------ zoom

-- the space a zoomed comic has: all between the header and the buttons
local function zoom_area() return 0, HEAD_H, W, btn_y() - 8 - MSG_H - HEAD_H end
-- any comic shown can be zoomed
local function can_zoom() return cur and cur.img ~= nil end
local function clamp(v, hi) return math.floor(math.max(0, math.min(v, hi))) end
-- the comic twice as large as it is shown (the original, when that is larger), at most 1024 px a
-- side, made by the resizer like the one shown (zoom.png, asked each time: it needs Wi-Fi): a small
-- original's lettering grows too. The part around (x, y) of the fitted one is shown.
local function zoom_in(x, y)
  local c = cur.c
  local iw, ih = tonumber(cur.img.width) or 1, tonumber(cur.img.height) or 1
  local fw0, fh0 = X.fit(math.max(cur.sw or 0, 2 * iw), math.max(cur.sh or 0, 2 * ih), X.MAX_SIDE, X.MAX_SIDE)
  get(X.weserv_url(c.img, fw0, fh0), 'zoom.png', 'Loading it full size...', function(res)
    if not (cur and cur.c.num == c.num and cur.img) then return end
    local f = failed(res)
    if f or not res.saved then status = (f == 'net') and 'Zoom needs Wi-Fi.' or ('Zoom failed: ' .. tostring(f or res.err)); return end
    local b = kit.read('zoom.png')
    pcall(function() ctx.budget:extend() end)
    local ok, im = pcall(function() return b and ctx.image:decode(b, { max_w = X.MAX_SIDE, max_h = X.MAX_SIDE }) end)
    if not ok or not im then status = 'This one cannot be zoomed.'; return end
    local fw, fh = tonumber(im.width), tonumber(im.height)
    local _zx, _zy, zw, zh = zoom_area()
    local vw, vh = math.min(zw, fw), math.min(zh, fh)
    local ax, ay, aw, ah = comic_area()
    local iw, ih = tonumber(cur.img.width), tonumber(cur.img.height)
    local dx, dy = ax + (aw - iw) // 2, ay + (ah - ih) // 2
    local fx, fy = (x - dx) / iw * fw, (y - dy) / ih * fh
    zoom = { img = im, fw = fw, fh = fh, vw = vw, vh = vh }
    zoom.sx, zoom.sy = clamp(fx - vw / 2, fw - vw), clamp(fy - vh / 2, fh - vh)
  end)
end
local function pan(dx, dy)
  zoom.sx = clamp(zoom.sx - dx, zoom.fw - zoom.vw)
  zoom.sy = clamp(zoom.sy - dy, zoom.fh - zoom.vh)
end

local function draw_comic(gg)
  local c = cur.c
  draw_header(gg, c)
  if zoom then
    local zx, zy, zw, zh = zoom_area()
    gg:image(zoom.img, zx + (zw - zoom.vw) // 2, zy + (zh - zoom.vh) // 2,
             { src = { x = zoom.sx, y = zoom.sy, w = zoom.vw, h = zoom.vh } })
    return
  end
  local ax, ay, aw, ah = comic_area()
  if cur.img then
    local iw, ih = tonumber(cur.img.width) or aw, tonumber(cur.img.height) or ah
    -- made for this space by the resizer: drawn as it is (the reader's own scaling only adds dots)
    gg:image(cur.img, ax + (aw - iw) // 2, ay + (ah - ih) // 2)
  else
    local y = ay + 10
    local msg = cur.err and ('The picture could not be shown (' .. cur.err .. ').') or 'An interactive comic: open it on another device.'
    for _k, l in ipairs(kit.wrap(msg, 'medium', W - 24)) do gg:text(12, y, l, { font = kit.font('medium') }); y = y + 28 end
    draw_qr(gg, X.page_url(c.num), y + 8, math.min(200, ah - (y - ay) - 30))
  end
  if W <= H then
    local y = ay + ah + 8
    for _k, l in ipairs(alt_lines(c)) do
      gg:text(12, y, l, { font = kit.font('small') })
      y = y + kit.line_h('small') + 2
    end
  end
end

-- the alt text in full; a reduced comic adds a QR code for the full size elsewhere
local function draw_alt(gg)
  local c = cur.c
  gg:text(12, 12, kit.short(c.num .. ': ' .. c.title, 40), { font = kit.font('medium') })
  local y, lh = 52, kit.line_h('medium') + 4
  local room = btn_y() - (cur.reduced and 230 or 20)
  for _k, l in ipairs(kit.wrap(c.alt, 'medium', W - 24)) do
    if y + lh > room then break end
    gg:text(12, y, l, { font = kit.font('medium') })
    y = y + lh
  end
  if cur.reduced then
    gg:text(12, room + 8, 'Reduced here; full size:', { font = kit.font('small') })
    draw_qr(gg, X.page_url(c.num), room + 32, 180)
  end
end

local function draw_offline(gg)
  local y = 200
  for _k, l in ipairs(kit.wrap('xkcd needs Wi-Fi to fetch comics, and none is saved on the reader yet. Turn Wi-Fi on and tap Reload.',
      'medium', W - 32)) do
    gg:text(16, y, l, { font = kit.font('medium') }); y = y + 30
  end
end

------------------------------------------------------------------ favourites and settings

local FAV_TOP, FAV_ROW = 70, 56
local function fav_per() return math.max(1, (btn_y() - 16 - FAV_TOP) // FAV_ROW) end
local function fav_pages() return math.max(1, (#favs() + fav_per() - 1) // fav_per()) end
local function draw_favs(gg)
  gg:text(12, 14, 'Favourites', { font = kit.font('large') })
  local list = favs()
  fav_page = math.min(fav_page, fav_pages())
  if #list == 0 then
    for k, l in ipairs(kit.wrap('No favourites yet: tap the star by a comic.', 'medium', W - 24)) do
      gg:text(12, FAV_TOP + 10 + (k - 1) * 30, l, { font = kit.font('medium') })
    end
    return
  end
  local first = (fav_page - 1) * fav_per()
  for k = 1, fav_per() do
    local f = list[first + k]
    if not f then break end
    local y = FAV_TOP + (k - 1) * FAV_ROW
    gg:text(12, y + 14, kit.short(f.n .. ': ' .. f.title, 40), { font = kit.font('medium') })
    gg:line(12, y + FAV_ROW - 1, W - 12, y + FAV_ROW - 1)
  end
  if fav_pages() > 1 then gg:text(W - 90, btn_y() - 26, fav_page .. ' / ' .. fav_pages(), { font = kit.font('small') }) end
end

local EVERY = { { '0', 'Off' }, { '3', 'Every 3 hours' }, { '6', 'Every 6 hours' }, { '12', 'Every 12 hours' } }
local function lock_is_on()
  local ok, v = pcall(function() return ctx.lockscreen:is_default() end)
  return ok and v == true
end
local function lock_label()
  if not lock_is_on() then return 'Sleep screen: off' end
  return 'Sleep screen: every ' .. cfg.lockevery .. ' hours'
end
local function lock_rect() return { x = 12, y = 80, w = W - 24, h = 64 } end
local function draw_settings(gg)
  gg:text(12, 14, 'Settings', { font = kit.font('large') })
  local r = lock_rect()
  kit.button(gg, r.x, r.y, r.w, r.h, lock_label(), { font = 'medium' })
  local y = r.y + r.h + 10
  for _k, l in ipairs(kit.wrap('The latest comic on the sleep screen, looked for again while locked when that much time '
      .. 'has passed (the picture only when a new comic is out).', 'small', W - 24)) do
    gg:text(12, y, l, { font = kit.font('small') }); y = y + 22
  end
  y = y + 24
  gg:text(12, y, 'xkcd by Randall Munroe · xkcd.com · CC BY-NC 2.5', { font = kit.font('small') })
  y = y + 30
  for _k, l in ipairs(kit.wrap('This app is not affiliated with xkcd. Comics come from xkcd.com; the few too big for the '
      .. 'reader are reduced through images.weserv.nl. The last ' .. KEEP .. ' comics seen are kept to read offline.',
      'small', W - 24)) do
    gg:text(12, y, l, { font = kit.font('small') }); y = y + 22
  end
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    sync_screen()
    gg:clear(0)
    if kit.modal() then kit.draw_modal(gg); return end
    if screen == 'favs' then draw_favs(gg)
    elseif screen == 'settings' then draw_settings(gg)
    elseif screen == 'alt' and cur then draw_alt(gg)
    elseif cur then draw_comic(gg)
    elseif offline then draw_offline(gg)
    else gg:text(16, 200, 'xkcd', { font = kit.font('large') }) end
    local line = loading or status or ERR
    for _k, r in ipairs(button_rects()) do kit.button(gg, r.x, r.y, r.w, r.h, r.b, { font = 'medium' }) end
    if line then gg:text(12, btn_y() - MSG_H + 2, kit.short(line, 60), { font = kit.font('small') }) end
  end)
  if not ok then pcall(function() gg:text(8, H - 40, kit.short('draw ERR ' .. tostring(e), 46)) end) end
end

------------------------------------------------------------------ input

local function ask_number()
  pcall(function()
    ctx.input:text({ title = 'Go to comic number', text = '', max_bytes = 8 }, function(c, s)
      if type(s) ~= 'string' then return end
      local n = tonumber((s:gsub('^%s+', ''):gsub('%s+$', '')))
      if not n or n ~= math.floor(n) then status = 'Type a comic number.'
      elseif n < 1 or n == 404 or (latest and n > latest) then status = 'No comic ' .. math.floor(n) .. '.'
      else unzoom(); show(math.floor(n)) end
      kit.refresh()
    end)
  end)
end

local function random_comic()
  unzoom()
  if latest then show(X.random(latest, math.random())); return end
  local list = cache_list()                         -- offline: one of the saved ones
  if #list == 0 then return end
  local e = list[math.random(1, #list)]
  display(e.c, e.kind, e.sw, e.sh)
end

local function more_menu()
  kit.show({ title = 'xkcd', rows = {
    { { 'Go to #', function() kit.close(); ask_number() end },
      { 'Latest', function() kit.close(); unzoom(); show(nil) end } },
    { { 'Favourites', function() kit.close(); fav_page = 1; screen = 'favs' end },
      { 'Settings', function() kit.close(); screen = 'settings' end } },
    { { 'Close', function() kit.close() end } } }, cancel = function() kit.close() end })
end

local function lock_menu()
  local rows = {}
  for _k, e in ipairs(EVERY) do
    rows[#rows + 1] = { { e[2], function()
      kit.close()
      if e[1] == '0' then pcall(function() ctx.lockscreen:clear_default() end)
      else
        cfg.lockevery = e[1]
        save_cfg()
        if not lock_is_on() then pcall(function() ctx.lockscreen:set_default() end) end
      end
    end } }
  end
  kit.show({ title = 'Sleep screen: the latest comic', rows = rows, cancel = function() kit.close() end })
end

local function press(b)
  status = nil
  if screen == 'favs' then
    if b == 'Back' then screen = 'comic'
    elseif b == 'Prev' then fav_page = math.max(1, fav_page - 1)
    elseif b == 'Next' then fav_page = math.min(fav_pages(), fav_page + 1) end
    return
  end
  if b == 'Prev' then step(-1)
  elseif b == 'Next' then step(1)
  elseif b == 'Random' then random_comic()
  elseif b == 'Alt' then unzoom(); screen = 'alt'
  elseif b == 'More' then more_menu()
  elseif b == 'Close' or b == 'Back' then screen = 'comic'
  elseif b == 'Reload' then offline = false; show(nil) end
end

local function inside(x, y, r) return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h end

local function tap(x, y)
  if kit.tap_modal(x, y) then return end
  for _k, r in ipairs(button_rects()) do
    if inside(x, y, r) then press(r.b); return end
  end
  if screen == 'favs' then
    if y < FAV_TOP or y >= FAV_TOP + fav_per() * FAV_ROW then return end
    local f = favs()[(fav_page - 1) * fav_per() + (y - FAV_TOP) // FAV_ROW + 1]
    if f then screen = 'comic'; unzoom(); show(f.n) end
  elseif screen == 'settings' then
    if inside(x, y, lock_rect()) then lock_menu() end
  elseif screen == 'comic' and cur then
    if inside(x, y, star_rect()) then toggle_fav(cur.c); return end
    local _zx, zy, _zw, zh = zoom_area()
    if y < zy or y > zy + zh then return end
    if zoom then unzoom()
    elseif can_zoom() then zoom_in(x, y) end
  end
end

function on_input(c, ev)
  ERR = nil
  local handled = true
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    sync_screen()
    pcall(function() ctx.budget:extend() end)
    if ev.type == 'key' and ev.key == 'back' then
      if ev.phase ~= 'up' and ev.phase ~= nil then return end
      if kit.modal() then kit.close()
      elseif zoom then unzoom()
      elseif screen ~= 'comic' then screen = 'comic'
      else handled = false end
      return
    end
    if ev.type == 'pointer' and ev.phase == 'down' then
      down = { x = ev.x or 0, y = ev.y or 0 }
    elseif ev.type == 'pointer' and ev.phase == 'up' then
      local x, y, d = ev.x or 0, ev.y or 0, down
      down = nil
      -- zoomed: a move over 20 px from where the finger went down moves the comic with it
      if zoom and screen == 'comic' and not kit.modal() and d and (x - d.x) ^ 2 + (y - d.y) ^ 2 > 400 then
        pan(x - d.x, y - d.y)
        return
      end
      local g = ev.gesture
      if not zoom and screen == 'comic' and g == 'swipe_left' then step(1)
      elseif not zoom and screen == 'comic' and g == 'swipe_right' then step(-1)
      else tap(x, y) end
    elseif ev.type == 'key' and kit.key_accepted(ev) then
      if ev.key == 'right' or ev.key == 'down' then step(1)
      elseif ev.key == 'left' or ev.key == 'up' then step(-1) end
    end
  end)
  if not ok then ERR = tostring(e) end
  kit.refresh()
  return handled
end

function on_load(c)
  local ok, e = pcall(function()
    sync_screen()
    load_cfg()
    show(nil)
  end)
  if not ok then ERR = tostring(e) end
end
function on_resume() kit.refresh() end
function on_leave()
  drop()
  release()
  if qr and qr.img then pcall(function() qr.img:release() end) end
end

if rawget(_G, '__TEST') then
  __TEST.api = { cur = function() return cur end, screen = function() return screen end, cfg = cfg,
                 zoom = function() return zoom end, is_fav = is_fav, star_rect = star_rect }
end
