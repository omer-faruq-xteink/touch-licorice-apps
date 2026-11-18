-- Offline Map: map packs made on the site's Tools page (AppFiles/offlinemap/*.map), shown without a
-- connection. The map screen: a header (pack, zoom, scale bar), the map, and - + Search Menu.
local geo = require('geo')
local fold = require('fold')
local pack = require('pack')
local choose = require('choose')
local view = require('view')
local names = require('names')
local gpx = require('gpx')
local labels = require('labels')
local near = require('near')

local TOOLS_URL = 'https://omer-faruq-xteink.github.io/touch-licorice-apps/tools/offlinemap/'
local HEAD, BAR = 34, 52
local MOVE = 20                 -- a finger that moved more than this is a drag
local MSG_MS = 3000

local W, H = 480, 800
local screen = 'map'            -- map | start | search | menu | bookmarks | routes | packs | about | coords
local packs, broken = {}, {}
local found, found_err = {}, nil  -- the folder's files at the last look, or why it did not list (the first page shows them)
local V = nil                   -- the view
local can_in, can_out = false, false
local msg, msg_until = nil, 0
local down = nil                -- where the finger went down
local held = false              -- a long press answered on hold; its up is ignored
local qr = nil
local ERR = nil
local settings = { orient = 'portrait', names = 'on' }
local marker = nil              -- { lon7, lat7, pans }: a found place, until the map is moved twice
local results, query, rpage = {}, '', 1
local ROW_H = 64
local overlay                   -- defined with the drawing (below)
local route = nil               -- { name, points, len, thin = { [z] = points } }
local list = nil                -- the list screen: { title, items = { {label, sub, fn, long} }, page, top = {..} }
local VERSION = '1.1.1'

------------------------------------------------------------------ helpers

local function now() return kit.now_ms() or 0 end
local function say(s)
  msg, msg_until = s, now() + MSG_MS
  -- no tick runs: a timer redraws the header once the message is due to go
  pcall(function() ctx:after(MSG_MS + 50, function() kit.refresh() end) end)
end
local function map_h() return H - HEAD - BAR end

local function sync_screen()
  local okw, w = pcall(function() return tonumber(ctx.screen.width) end)
  local okh, h = pcall(function() return tonumber(ctx.screen.height) end)
  W, H = okw and w or 480, okh and h or 800
  kit.W, kit.H = W, H
end

local function load_settings()
  local t = kit.kv(kit.read('settings.txt'))
  if t.orient == 'landscape' then settings.orient = 'landscape' end
  if t.names == 'off' then settings.names = 'off' end
end
local function save_settings() kit.write('settings.txt', 'orient=' .. settings.orient .. '\nnames=' .. settings.names) end

local function save_view()
  if V then kit.write('view.txt', V.z .. ' ' .. V.cx .. ' ' .. V.cy) end
end

local function update_limits()
  if not V then return end
  can_in, can_out = choose.limits(packs, V.z, V.cx, V.cy)
end

-- the pack under the centre of the screen
local function centre_pack()
  if not V then return nil end
  return choose.pick(packs, V.z, V.cx >> 8, V.cy >> 8)
end

-- packnames.txt: file<TAB>name a line, the names given in Map packs (the card cannot rename a file,
-- and copying a pack of tens of MB on the reader would take minutes)
local function read_pack_names()
  local out = {}
  for l in (kit.read('packnames.txt') or ''):gmatch('[^\n]+') do
    local f, n = l:match('^(.-)\t(.+)$')
    if f then out[f] = n end
  end
  return out
end
local function write_pack_names(t)
  local lines = {}
  for f, n in pairs(t) do lines[#lines + 1] = f .. '\t' .. (n:gsub('[\t\n]', ' ')) end
  table.sort(lines)
  kit.write('packnames.txt', table.concat(lines, '\n') .. '\n')
end

local function load_packs()
  packs, broken = {}, {}
  local given = read_pack_names()
  found, found_err = {}, nil
  local ok, list, le = pcall(function() return ctx.files:list() end)
  if not ok or type(list) ~= 'table' then found_err = tostring(ok and (le or 'no list') or list); return end
  found = list
  for _, f in ipairs(list) do
    local n = tostring(f.name or '')
    if n:lower():match('%.map$') then
      local p, err = pack.open(n)
      if p then
        p.title = given[n] or tostring(p.meta.name or n)
        packs[#packs + 1] = p
      else
        broken[#broken + 1] = { name = n, err = err }
      end
    end
  end
  table.sort(packs, function(a, b) return a.area < b.area end)
end

-- a pack's view: its middle, at zoom 14 (or the nearest level it has); the first view is the
-- smallest pack's
local function first_view(p)
  p = p or packs[1]
  local b = p.meta.bounds or {}
  local lon = ((tonumber(b[1]) or 0) + (tonumber(b[3]) or 0)) / 2
  local lat = ((tonumber(b[2]) or 0) + (tonumber(b[4]) or 0)) / 2
  local z = math.max(p.zmin, math.min(p.zmax, 14))
  local x, y = geo.lonlat_px(z, math.floor(lon * 1e7), math.floor(lat * 1e7))
  return z, x, y
end

local function make_view(z, cx, cy)
  if V then V:release() end
  V = view.new(ctx, W, map_h())
  V.packs = packs
  V.overlay = overlay
  V:set(z, cx, cy)
  update_limits()
end

local function moved()
  update_limits()
  save_view()
end

-- the host turns the screen between callbacks, after set_orientation returns: whenever the screen's
-- size is not the one the view was made for, make the view again for it (map and buttons)
local resize_asked = false
local function size_changed()
  local okw, w = pcall(function() return tonumber(ctx.screen.width) end)
  local okh, h = pcall(function() return tonumber(ctx.screen.height) end)
  w, h = okw and w or W, okh and h or H
  return V ~= nil and (w ~= V.w or h - HEAD - BAR ~= V.h)
end
local function fit_screen()
  resize_asked = false
  sync_screen()
  if V and (V.w ~= W or V.h ~= map_h()) then make_view(V.z, V.cx, V.cy) end
end

-- what is drawn into the map layer over the tiles: the marker (and the route, in the menu's code)
-- the route's points as global pixels at zoom z, worked out once per zoom from fixed anchors (a new
-- one only past 1 degree), so every pan draws them at the same pixels as the tiles under them
local FAR = 10000000
local function route_px(z)
  local px = route.thin[z]
  if px then return px end
  px = {}
  local A
  for _, p in ipairs(gpx.thin(route.points, z)) do
    if not A or math.abs(p.lon7 - A.lon7) > FAR or math.abs(p.lat7 - A.lat7) > FAR then A = geo.anchor_ll(z, p.lon7, p.lat7) end
    local x, y = geo.to_px(A, p.lon7, p.lat7)
    px[#px + 1] = x; px[#px + 1] = y
  end
  route.thin[z] = px
  return px
end

-- the route as beads: a bead every STEP pixels along it from its start, as global pixels per zoom,
-- so a pan draws them at the same pixels (black on e-ink streets would hide a plain line; beads with
-- a white ring stand out). Distances use differences of integers only.
local STEP, CORE, RING = 10, 4, 6      -- close beads: the route stands out (the user, on the device)
local function route_dots(z)
  route.dots = route.dots or {}
  local d = route.dots[z]
  if d then return d end
  d = {}
  local px = route_px(z)
  local carry = 0                                  -- distance since the last bead
  if #px >= 2 then d[1] = px[1]; d[2] = px[2] end
  for i = 3, #px - 1, 2 do
    local x0, y0 = px[i - 2], px[i - 1]
    local dx, dy = px[i] - x0, px[i + 1] - y0
    local len = math.sqrt(dx * dx + dy * dy)
    local t = STEP - carry
    while t <= len do
      d[#d + 1] = x0 + math.floor(dx * t / len + 0.5); d[#d + 1] = y0 + math.floor(dy * t / len + 0.5)
      t = t + STEP
    end
    carry = len - (t - STEP)
  end
  route.dots[z] = d
  return d
end

local function draw_route(g, left, top)
  local d = route_dots(V.z)
  local vis = {}
  for i = 1, #d, 2 do
    local x, y = d[i] - left, d[i + 1] - top
    if x > -RING and x < V.w + RING and y > -RING and y < V.h + RING then vis[#vis + 1] = x; vis[#vis + 1] = y end
  end
  for i = 1, #vis, 2 do g:circle(vis[i], vis[i + 1], RING, { fill = true, color = 0 }) end    -- rings first,
  for i = 1, #vis, 2 do g:circle(vis[i], vis[i + 1], CORE, { fill = true, color = 15 }) end   -- then beads
end

-- the street names beside the route, level, each in a white box (Menu: Street names on or off)
local function draw_labels(g, left, top)
  if settings.names == 'off' or V.z < 15 or not route.labels or #route.labels == 0 then return end
  route.place = route.place or {}
  local f = kit.font('medium')
  local lh = kit.line_h('medium')
  local pl = route.place[V.z]
  if not pl then
    pl = labels.place(route_px(V.z), route.labels, V.z, function(s) return kit.width(f, s) end, lh)
    route.place[V.z] = pl
  end
  for _, p in ipairs(pl) do
    local x, y = p.x - left, p.y - top
    if x > -p.w and x < V.w and y > -p.h and y < V.h then
      g:rect(x, y, p.w, p.h, { fill = true, color = 0 })
      g:rect(x, y, p.w, p.h)
      g:text(x + 8, y + 2, route.labels[p.idx].name, { font = f, bold = true })
    end
  end
end

function overlay(g, left, top)
  if route then draw_route(g, left, top); draw_labels(g, left, top) end
  if not marker then return end
  local m = marker.px[V.z]
  if not m then local mx, my = geo.lonlat_px(V.z, marker.lon7, marker.lat7); m = { mx, my }; marker.px[V.z] = m end
  local x, y = m[1] - left, m[2] - top
  for d = -1, 1 do
    g:line(x - 14, y + d, x - 5, y + d); g:line(x + 5, y + d, x + 14, y + d)
    g:line(x + d, y - 14, x + d, y - 5); g:line(x + d, y + 5, x + d, y + 14)
  end
  g:rect(x - 3, y - 3, 7, 7)
end

local function after_pan()
  if marker then
    marker.pans = marker.pans + 1
    if marker.pans >= 2 then marker = nil; V:refresh() end
  end
end

-- go to a position at (about) zoom `want`: the nearest level some pack has there
local function jump(lon7, lat7, want, mark)
  local z = choose.nearest(packs, want, function(zz) return geo.lonlat_px(zz, lon7, lat7) end)
  if not z then say('Not in any map pack'); screen = 'map'; return false end
  marker = mark and { lon7 = lon7, lat7 = lat7, pans = 0, px = {} } or marker
  local x, y = geo.lonlat_px(z, lon7, lat7)
  screen = 'map'
  V:set(z, x, y)
  moved()
  return true
end

------------------------------------------------------------------ actions

local function zoom_in(px, py)
  if not can_in then say('No closer level here'); return end
  V:zoom(1, px, py)
  moved()
end
local function zoom_out(px, py)
  if not can_out then say('No wider level here'); return end
  V:zoom(-1, px, py)
  moved()
end

local function point_at(x, y)
  local A = geo.anchor(V.z, V.cx, V.cy)
  return geo.from_px(A, V:left() + x, V:top() + (y - HEAD))
end

local function ask(title, text, fn)
  pcall(function()
    ctx.input:text({ title = title, text = text or '', max_bytes = 120 }, function(c, s)
      if s then fn(s) end
      kit.refresh()
    end)
  end)
end

local function run_search(q)
  query = q
  results = names.search(packs, q, 60)
  rpage = 1
  screen = 'search'
end
local function open_search() ask('Search: a place, a street, a station', query, run_search) end

-- bookmarks.txt: name<TAB>lat7<TAB>lon7 a line
local function read_bookmarks()
  local out = {}
  for l in (kit.read('bookmarks.txt') or ''):gmatch('[^\n]+') do
    local n, la, lo = l:match('^(.-)\t(%-?%d+)\t(%-?%d+)$')
    if n then out[#out + 1] = { name = n, lat7 = tonumber(la), lon7 = tonumber(lo) } end
  end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end
local function write_bookmarks(bs)
  local t = {}
  for _, b in ipairs(bs) do t[#t + 1] = (b.name:gsub('[\t\n]', ' ')) .. '\t' .. b.lat7 .. '\t' .. b.lon7 end
  kit.write('bookmarks.txt', table.concat(t, '\n') .. '\n')
end
local function add_bookmark(lat7, lon7)
  local bs = read_bookmarks()
  ask('A name for this bookmark', 'Bookmark ' .. (#bs + 1), function(name)
    if name == '' then return end
    bs[#bs + 1] = { name = name, lat7 = lat7, lon7 = lon7 }
    write_bookmarks(bs)
    say('Bookmark added')
  end)
end

local function long_press(x, y)
  local lon7, lat7 = point_at(x, y)
  local lines = { geo.fmt(lat7, lon7) }
  for _, l in ipairs(near.lines(packs, lon7, lat7, V.z)) do lines[#lines + 1] = l end   -- what is held: a street, a peak, a lake
  kit.show({ title = 'This point', lines = lines,
    rows = { { { 'Add bookmark here', function() kit.close(); add_bookmark(lat7, lon7) end } }, { { 'Close', function() kit.close() end } } },
    cancel = function() kit.close() end })
end

------------------------------------------------------------------ the menu and its lists

local open_menu
local function show_list(title, items, top)
  list = { title = title, items = items, page = 1, top = top or {} }
  screen = 'list'
end

local function same_bm(a, b) return a.name == b.name and a.lat7 == b.lat7 and a.lon7 == b.lon7 end
local function open_bookmarks()
  local items = {}
  for _, b in ipairs(read_bookmarks()) do
    items[#items + 1] = { b.name, geo.fmt(b.lat7, b.lon7), function() jump(b.lon7, b.lat7, math.max(V.z, 16), true) end,
      function()
        kit.show({ title = b.name, rows = {
          { { 'Rename', function()
            kit.close()
            ask('A new name', b.name, function(n)
              if n == '' then return end
              local bs = read_bookmarks()
              for _, o in ipairs(bs) do if same_bm(o, b) then o.name = n end end
              write_bookmarks(bs); open_bookmarks()
            end)
          end }, { 'Delete', function()
            kit.close()
            local keep = {}
            for _, o in ipairs(read_bookmarks()) do if not same_bm(o, b) then keep[#keep + 1] = o end end
            write_bookmarks(keep); open_bookmarks()
          end } },
          { { 'Close', function() kit.close() end } } }, cancel = function() kit.close() end })
      end }
  end
  if #items == 0 then items[1] = { 'No bookmarks yet', 'Long press the map: Add bookmark here.', nil } end
  show_list('Bookmarks', items)
end

-- the deepest level the whole route fits on the screen (and some pack has at its middle);
-- false when no pack has it
local function fit_route()
  if not route then return false end
  local a = route.points[1]
  local w, s, e, n = a.lon7, a.lat7, a.lon7, a.lat7
  for _, p in ipairs(route.points) do
    if p.lon7 < w then w = p.lon7 end
    if p.lon7 > e then e = p.lon7 end
    if p.lat7 < s then s = p.lat7 end
    if p.lat7 > n then n = p.lat7 end
  end
  local mlon, mlat = w // 2 + e // 2, s // 2 + n // 2
  for z = 19, 8, -1 do
    local x0, y0 = geo.lonlat_px(z, w, n)
    local x1, y1 = geo.lonlat_px(z, e, s)
    if x1 - x0 <= V.w - 40 and y1 - y0 <= V.h - 40 then
      local cx, cy = geo.lonlat_px(z, mlon, mlat)
      if choose.pick(packs, z, cx >> 8, cy >> 8) then screen = 'map'; V:set(z, cx, cy); moved(); return true end
    end
  end
  screen = 'map'
  if choose.nearest(packs, 8, function(zz) return geo.lonlat_px(zz, mlon, mlat) end) then return jump(mlon, mlat, 8, false) end
  return false
end

local function open_route(name)
  pcall(function() ctx.budget:extend() end)        -- up to 1 MB read and parsed in this callback
  local okz, size = pcall(function() return ctx.files:size(name) end)
  size = okz and tonumber(size) or 0
  local text = size > 0 and pack.span(name, 0, math.min(size, 1048576)) or ''
  local r, why = gpx.parse(text)
  if not r then say(name .. ': ' .. tostring(why)); screen = 'map'; return end
  route = { name = r.name or name, points = r.points, len = gpx.length_m(r.points), thin = {}, labels = r.labels or {} }
  if #route.labels == 0 then route.labels = labels.from_index(packs, r.points, 12) end   -- another app's GPX
  screen = 'map'
  if fit_route() then                              -- go to it: all of it on the screen
    say(kit.short(route.name, 18) .. ': ' .. gpx.length_text(route.len))
  else
    V:refresh()
    say('No map pack has this route')
  end
end

local function open_routes()
  local items, top = {}, {}
  if route then
    top = { { 'Fit route', function() fit_route() end }, { 'Hide route', function()
      route = nil; screen = 'map'; V:refresh()
    end } }
  end
  local ok, files = pcall(function() return ctx.files:list() end)
  for _, f in ipairs(ok and type(files) == 'table' and files or {}) do
    local n = tostring(f.name or '')
    if n:lower():match('%.gpx$') then items[#items + 1] = { n, nil, function() open_route(n) end } end
  end
  if #items == 0 then items[1] = { 'No routes yet', 'Copy GPX files into AppFiles/offlinemap/.', nil } end
  show_list('Routes' .. (route and (': ' .. kit.short(route.name, 16) .. ', ' .. gpx.length_text(route.len)) or ''), items, top)
end

local function go_to_coords()
  ask('Coordinates, like 41.0082, 28.9784', '', function(s)
    local lat7, lon7 = geo.parse_coords(s)
    screen = 'map'
    if not lat7 then
      kit.show({ title = 'Go to coordinates', lines = { tostring(lon7), 'For example 41.0082, 28.9784' },
        rows = { { { 'Close', function() kit.close() end } } }, cancel = function() kit.close() end })
      return
    end
    jump(lon7, lat7, math.max(V.z, 15), true)
  end)
end

local function size_text(n) return n < 1048576 and (((n + 512) // 1024) .. ' KB') or string.format('%.1f MB', n / 1048576) end
local open_packs

-- file was deleted: it leaves the packs (the others are not opened again: in a tap's 1 s that is
-- too slow with many packs); the map keeps its place, or the start screen when none is left
local function pack_deleted(file)
  local function drop(t) for i = #t, 1, -1 do if t[i].name == file then table.remove(t, i) end end end
  drop(packs); drop(broken)
  if #packs == 0 then
    if V then V:release(); V = nil end
    screen = 'start'
    local okq, im = pcall(function() return ctx.qr:encode(TOOLS_URL, { size = 200 }) end)
    qr = okq and im or nil
    return
  end
  if V then V.packs = packs; update_limits(); V:refresh() end
  open_packs()
end

-- a long press on a pack in Map packs: Rename (the name in the app), Delete (the file, after asking)
local function pack_menu(file, title, can_rename)
  local function delete()
    kit.show({ title = 'Delete ' .. kit.short(title, 24) .. '?', lines = { 'The file ' .. file .. ' is removed from the card.' },
      rows = { { { 'Delete', function()
        kit.close()
        pcall(function() ctx.budget:extend() end)  -- removing a file of tens of MB can take longer than a tap's 1 s
        local ok, done, err = pcall(function() return ctx.files:remove(file) end)
        if not ok or not done then say('Not deleted: ' .. tostring(ok and err or done)); return end
        local given = read_pack_names()
        if given[file] then given[file] = nil; write_pack_names(given) end
        pack_deleted(file)
      end }, { 'Cancel', function() kit.close() end } } },
      cancel = function() kit.close() end })
  end
  local row = { { 'Delete', function() kit.close(); delete() end } }
  if can_rename then
    table.insert(row, 1, { 'Rename', function()
      kit.close()
      ask('A new name', title, function(n)
        n = n:gsub('^%s+', ''):gsub('%s+$', '')
        if n == '' then return end
        local given = read_pack_names()
        given[file] = n
        write_pack_names(given)
        for _, p in ipairs(packs) do if p.name == file then p.title = n end end
        open_packs()
      end)
    end })
  end
  kit.show({ title = title, lines = { file }, rows = { row, { { 'Close', function() kit.close() end } } }, cancel = function() kit.close() end })
end

function open_packs()
  local items = {}
  for _, p in ipairs(packs) do
    items[#items + 1] = { p.title, 'z' .. p.zmin .. '-' .. p.zmax .. ', ' .. size_text(p.file_size) .. ', ' .. p.made,
      function()                                   -- go to the pack
        local z, x, y = first_view(p)
        screen = 'map'
        V:set(z, x, y)
        moved()
      end,
      function() pack_menu(p.name, p.title, true) end }
  end
  for _, b in ipairs(broken) do items[#items + 1] = { b.name, tostring(b.err), nil, function() pack_menu(b.name, b.name, false) end } end
  show_list('Map packs', items)
end

local function turn_screen()
  settings.orient = settings.orient == 'portrait' and 'landscape' or 'portrait'
  save_settings()
  pcall(function() ctx.screen:set_orientation(settings.orient) end)
  screen = 'map'
  fit_screen()                                     -- if the host turned it at once; else the next callback
end

local function open_about()
  if not qr then
    local okq, im = pcall(function() return ctx.qr:encode(TOOLS_URL, { size = 160 }) end)
    qr = okq and im or nil
  end
  local seen, attr = {}, {}
  for _, p in ipairs(packs) do
    local a = tostring(p.meta.attribution or '')
    if a ~= '' and not seen[a] then seen[a] = true; attr[#attr + 1] = a end
  end
  list = { title = 'About Offline Map ' .. VERSION, items = {}, page = 1, top = {}, about = attr }
  screen = 'about'
end

function open_menu()
  show_list('Menu', {
    { 'Bookmarks', nil, open_bookmarks },
    { 'Routes', nil, open_routes },
    { 'Go to coordinates', nil, go_to_coords },
    { 'Map packs', nil, open_packs },
    { 'Screen: ' .. settings.orient, nil, turn_screen },
    { 'Street names: ' .. settings.names, 'beside a route', function()
      settings.names = settings.names == 'on' and 'off' or 'on'
      save_settings()
      screen = 'map'
      V:refresh()
    end },
    { 'About', nil, open_about },
  })
end

local function all_missing()
  if not V then return false end
  local cols = ((V:left() + V.w - 1) >> 8) - (V:left() >> 8) + 1
  local rows = ((V:top() + V.h - 1) >> 8) - (V:top() >> 8) + 1
  return V.missing >= cols * rows
end

------------------------------------------------------------------ drawing

local BTNS = { '-', '+', 'Search', 'Menu' }
local function bar_rect(i)
  local bw = (W - 8 * 5) // 4
  return 8 + (i - 1) * (bw + 8), H - BAR + 6, bw, BAR - 12
end
local function packs_btn() return W // 2 - 90, HEAD + map_h() // 2 - 30, 180, 60 end

local function draw_header(gg)
  local p = centre_pack()
  local title = (now() < msg_until and msg) or (V and V.edge and 'Edge of the map') or (p and p.title) or ''
  local f = kit.font('small')
  local zs = 'z' .. V.z
  local m, px = geo.scale_bar(V.z, select(2, geo.from_px(geo.anchor(V.z, V.cx, V.cy), V.cx, V.cy)))
  local label = m >= 1000 and ((m // 1000) .. ' km') or (m .. ' m')
  local sx = W - 8 - px
  gg:line(sx, 24, W - 8, 24); gg:line(sx, 18, sx, 28); gg:line(W - 8, 18, W - 8, 28)
  gg:text(sx + (px - kit.width(f, label)) // 2, 2, label, { font = f })
  gg:text(sx - 12 - kit.width(f, zs), 6, zs, { font = f })
  gg:text(8, 6, kit.short(title, 26), { font = f })
  gg:line(0, HEAD - 1, W, HEAD - 1)
end

local function draw_bar(gg)
  gg:line(0, H - BAR, W, H - BAR)
  for i, label in ipairs(BTNS) do
    local x, y, w, h = bar_rect(i)
    local faded = (i == 1 and not can_out) or (i == 2 and not can_in)
    kit.button(gg, x, y, w, h, faded and ('(' .. label .. ')') or label, { line_width = faded and 1 or 2 })
  end
end

local function draw_start(gg)
  gg:text(24, 30, 'Offline Map', { font = kit.font('large') })
  local y = 80
  local text = {
    'A map without a connection, like a folding paper map. It has no live position: find places by name, '
      .. 'or type coordinates read off a phone.',
    'Make a map pack on the Tools page (scan the code), then copy it to AppFiles/offlinemap/ on the card. '
      .. 'GPX routes go in the same folder.',
  }
  local function para(s, x)
    for _, l in ipairs(kit.wrap(s, 'small', W - 24 - x)) do
      if y < H - 30 then gg:text(x, y, l, { font = kit.font('small') }) end
      y = y + 24
    end
  end
  for _, p in ipairs(text) do para(p, 24); y = y + 10 end
  if qr then gg:image(qr, (W - (tonumber(qr.width) or 200)) // 2, y + 10); y = y + 10 + (tonumber(qr.height) or 200) + 16 end
  -- what the app found: a pack that does not open says why, so a user can tell what is wrong
  local path = (type(ctx.files.path) == 'string' and ctx.files.path ~= '') and ctx.files.path or '/AppFiles/offlinemap'
  para('In ' .. path .. ':', 24)
  local why = {}
  for _, b in ipairs(broken) do why[b.name] = b.err end
  if found_err then para('the folder does not list: ' .. found_err, 36)
  elseif #found == 0 then para('nothing yet.', 36) end
  for _, f in ipairs(found) do
    local n = tostring(f.name or '')
    local sz = tonumber(f.size) or 0
    para(n .. '  ' .. size_text(sz) .. (sz >= 1024 and (' (' .. sz .. ' bytes)') or ''), 36)
    if why[n] then para('does not open: ' .. tostring(why[n]), 52) end
  end
  para('Tap to look again.', 24)
end

local function per_page() return (H - 70 - 70) // ROW_H end
local function result_rect(i) return 12, 60 + (i - 1) * ROW_H, W - 24, ROW_H - 6 end
local function search_btns() return { { 'New search', 12 }, { 'Map', W // 2 + 6 } } end
local function draw_search(gg)
  gg:text(12, 14, kit.short('Search: ' .. query, 34), { font = kit.font('medium') })
  gg:line(0, 50, W, 50)
  if #results == 0 then gg:text(12, 70, 'Nothing found in the map packs.', { font = kit.font('small') }) end
  local n = per_page()
  for i = 1, n do
    local e = results[(rpage - 1) * n + i]
    if not e then break end
    local x, y = result_rect(i)
    gg:text(x, y, kit.short(e.name, 30), { font = kit.font('medium') })
    gg:text(x, y + 30, (names.KIND[e.kind] or 'place') .. ', ' .. kit.short(tostring(e.pack.title), 28), { font = kit.font('small') })
  end
  local pages = math.max(1, (#results + n - 1) // n)
  if pages > 1 then gg:text(W - 90, H - 100, rpage .. ' / ' .. pages, { font = kit.font('small') }) end
  for _, b in ipairs(search_btns()) do kit.button(gg, b[2], H - 60, W // 2 - 18, 48, b[1]) end
end

local function tap_search(x, y)
  if y >= H - 60 then
    if x < W // 2 then open_search() else screen = 'map' end
    return
  end
  local n = per_page()
  for i = 1, n do
    local e = results[(rpage - 1) * n + i]
    local rx, ry, rw, rh = result_rect(i)
    if e and x >= rx and x < rx + rw and y >= ry and y < ry + rh then
      jump(e.lon7, e.lat7, names.ZOOM[e.kind] or 15, true)
      return
    end
  end
end

local LROW = 58
local function list_per_page() return (H - 60 - 70 - #list.top * LROW) // LROW end
local function list_row(i) return 12, 60 + #list.top * LROW + (i - 1) * LROW end
local function draw_list(gg)
  gg:text(12, 14, kit.short(list.title, 34), { font = kit.font('medium') })
  gg:line(0, 50, W, 50)
  for i, b in ipairs(list.top) do kit.button(gg, 12 + (i - 1) * (W // 2 - 6), 56, W // 2 - 18, LROW - 10, b[1]) end
  local n = list_per_page()
  for i = 1, n do
    local it = list.items[(list.page - 1) * n + i]
    if not it then break end
    local x, y = list_row(i)
    gg:text(x, y + 4, kit.short(it[1], 32), { font = kit.font('medium') })
    if it[2] then gg:text(x, y + 32, kit.short(it[2], 44), { font = kit.font('small') }) end
    gg:line(x, y + LROW - 2, W - 12, y + LROW - 2)
  end
  local pages = math.max(1, (#list.items + n - 1) // n)
  if pages > 1 then gg:text(W - 90, H - 96, list.page .. ' / ' .. pages, { font = kit.font('small') }) end
  kit.button(gg, 12, H - 60, W - 24, 48, 'Map')
end
local function draw_about(gg)
  gg:text(12, 14, list.title, { font = kit.font('medium') })
  gg:line(0, 50, W, 50)
  local y = 64
  local paras = { 'Make a map pack on the Tools page (scan the code) and copy it to AppFiles/offlinemap/. '
    .. 'GPX routes go in the same folder. There is no live position.', 'Map data:' }
  for _, a in ipairs(list.about) do paras[#paras + 1] = a end
  if #list.about == 0 then paras[#paras + 1] = '© OpenStreetMap contributors' end
  for _, p in ipairs(paras) do
    for _, l in ipairs(kit.wrap(p, 'small', W - 24)) do gg:text(12, y, l, { font = kit.font('small') }); y = y + 22 end
    y = y + 6
  end
  if qr then gg:image(qr, (W - (tonumber(qr.width) or 160)) // 2, y + 6) end
  kit.button(gg, 12, H - 60, W - 24, 48, 'Map')
end

local function list_hit(x, y)
  for i, b in ipairs(list.top) do
    local bx = 12 + (i - 1) * (W // 2 - 6)
    if x >= bx and x < bx + W // 2 - 18 and y >= 56 and y < 56 + LROW - 10 then return { b[1], nil, b[2] } end
  end
  local n = list_per_page()
  for i = 1, n do
    local it = list.items[(list.page - 1) * n + i]
    local _, ry = list_row(i)
    if it and y >= ry and y < ry + LROW then return it end
  end
end
local function tap_list(x, y)
  if y >= H - 60 then screen = 'map'; return end
  if screen == 'about' then return end
  local it = list_hit(x, y)
  if it and it[3] then it[3]() end
end

------------------------------------------------------------------ callbacks

function on_load()
  local ok, e = pcall(function()
    sync_screen()
    load_settings()
    if (W > H) ~= (settings.orient == 'landscape') then
      pcall(function() ctx.screen:set_orientation(settings.orient) end)
      sync_screen()
    end
    load_packs()
    if #packs == 0 then
      screen = 'start'
      local okq, im = pcall(function() return ctx.qr:encode(TOOLS_URL, { size = 200 }) end)
      qr = okq and im or nil
      return
    end
    local z, cx, cy = (kit.read('view.txt') or ''):match('^(%d+) (%-?%d+) (%-?%d+)')
    z, cx, cy = tonumber(z), tonumber(cx), tonumber(cy)
    if not z or z < 8 or z > 19 then z, cx, cy = first_view() end
    make_view(z, cx, cy)
    screen = 'map'
  end)
  if not ok then ERR = tostring(e) end
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    gg:clear(0)
    if size_changed() then                         -- the screen turned: make the view in a timer (not here)
      sync_screen()
      if not resize_asked then
        local ok, t = pcall(function() return ctx:after(1, function() fit_screen(); kit.refresh() end) end)   -- 1 ms: 0 is refused
        resize_asked = ok and t ~= nil
      end
      gg:text(W // 2 - 40, H // 2, 'Turning...', { font = kit.font('medium') })
      return
    end
    if screen == 'start' then draw_start(gg)
    elseif screen == 'search' then draw_search(gg)
    elseif screen == 'list' then draw_list(gg)
    elseif screen == 'about' then draw_about(gg)
    elseif screen == 'map' and V then
      V:draw(gg, 0, HEAD)
      draw_header(gg)
      draw_bar(gg)
      if all_missing() then
        local x, y, w, h = packs_btn()
        kit.button(gg, x, y, w, h, 'Map packs')
      end
    end
    if kit.modal() then kit.draw_modal(gg) end
    if ERR then gg:text(8, H - 24, 'ERR ' .. kit.short(ERR, 40), { font = kit.font('small') }) end
  end)
  if not ok then pcall(function() gg:text(8, H - 24, 'ERR ' .. tostring(e):sub(1, 40)) end) end
end

-- the first page looks at the folder again: on a tap, and when the app comes back (a pack copied
-- while it was open)
local function look_again()
  load_packs()
  if #packs == 0 then return end
  if qr then pcall(function() qr:release() end); qr = nil end
  make_view(first_view())
  screen = 'map'
end

local function inside(x, y, rx, ry, rw, rh) return x >= rx and x < rx + rw and y >= ry and y < ry + rh end

local function pointer_up(ev)
  local x, y = tonumber(ev.x) or 0, tonumber(ev.y) or 0
  if kit.modal() then kit.tap_modal(x, y); return end
  if screen == 'start' then look_again(); return end
  if screen == 'search' then tap_search(x, y); return end
  if screen == 'list' or screen == 'about' then tap_list(x, y); return end
  if screen ~= 'map' or not V then return end
  if y >= H - BAR then
    for i = 1, #BTNS do
      if inside(x, y, bar_rect(i)) then
        if i == 1 then zoom_out(V.w // 2, V.h // 2)
        elseif i == 2 then zoom_in(V.w // 2, V.h // 2)
        elseif i == 3 then open_search()
        else open_menu() end
      end
    end
    return
  end
  if y < HEAD then return end
  local dx = x - (tonumber(ev.down_x) or (down and down.x) or x)
  local dy = y - (tonumber(ev.down_y) or (down and down.y) or y)
  if math.abs(dx) > MOVE or math.abs(dy) > MOVE then
    V:pan(-dx, -dy)
    moved()
    after_pan()
  elseif ev.gesture == 'double_tap' then
    zoom_in(x, y - HEAD)
  elseif all_missing() and inside(x, y, packs_btn()) then
    open_packs()
  end
end

local function key(k)
  if screen == 'search' then
    local n = per_page()
    local pages = math.max(1, (#results + n - 1) // n)
    if k == 'right' or k == 'down' then rpage = math.min(pages, rpage + 1) elseif k == 'left' or k == 'up' then rpage = math.max(1, rpage - 1) end
    return
  end
  if screen == 'list' then
    local n = list_per_page()
    local pages = math.max(1, (#list.items + n - 1) // n)
    if k == 'right' or k == 'down' then list.page = math.min(pages, list.page + 1) elseif k == 'left' or k == 'up' then list.page = math.max(1, list.page - 1) end
    return
  end
  if screen ~= 'map' or not V then return end
  local hw, hh = V.w // 2, V.h // 2
  if k == 'left' then V:pan(-hw, 0) elseif k == 'right' then V:pan(hw, 0)
  elseif k == 'up' then V:pan(0, -hh) elseif k == 'down' then V:pan(0, hh) else return end
  moved()
  after_pan()
end

function on_input(c, ev)
  local handled = true
  local ok, e = pcall(function()
    if size_changed() then fit_screen() end
    if type(ev) ~= 'table' then return end
    if ev.type == 'pointer' then
      if ev.phase == 'down' then down = { x = tonumber(ev.x) or 0, y = tonumber(ev.y) or 0 }; held = false
      elseif ev.phase == 'hold' and screen == 'list' and not kit.modal() then   -- the gesture comes only on up
        local it = list_hit(tonumber(ev.x) or 0, tonumber(ev.y) or 0)
        if it and it[4] then held = true; it[4]() end
      elseif ev.phase == 'hold' then
        if screen == 'map' and V and not kit.modal() and (tonumber(ev.y) or 0) >= HEAD and (tonumber(ev.y) or 0) < H - BAR then
          held = true
          long_press(tonumber(ev.x) or 0, tonumber(ev.y) or 0)
        end
      elseif ev.phase == 'up' then
        if held then held = false
        else pointer_up(ev) end
        down = nil
      end
    elseif ev.type == 'key' and ev.key == 'back' then
      -- Back acts on its release (the host reads only the up event's answer): close a box, leave a
      -- screen; on the map it is left to the host, which offers to exit
      if ev.phase ~= 'up' and ev.phase ~= nil then return end
      if kit.modal() then
        if kit.modal().cancel then kit.modal().cancel() else kit.close() end
      elseif screen ~= 'map' and screen ~= 'start' then screen = 'map'
      else handled = false end
    elseif ev.type == 'key' and kit.key_accepted(ev) then
      key(ev.key)
    end
  end)
  if not ok then ERR = tostring(e) end
  kit.refresh()
  return handled
end

function on_resume()
  local ok, e = pcall(function() if screen == 'start' then look_again() end end)
  if not ok then ERR = tostring(e) end
end

function on_tick()
  if msg and now() >= msg_until then msg = nil; kit.refresh() end
end

if rawget(_G, '__TEST') then
  __TEST.api = {
    fold = fold.fold,
    geo = geo, pack = pack, choose = choose, view = view, names = names, gpx = gpx, labels = labels, near = near,
    state = function() return { screen = screen, z = V and V.z, cx = V and V.cx, cy = V and V.cy, modal = kit.modal(), marker = marker, route = route, vw = V and V.w } end,
    packs = function() return packs end,
    layer_ops = function() return V and V.layer.ops or {} end,
    clear_ops = function() V.layer.ops = {}; V.spare.ops = {} end,     -- the test stub's record
  }
end
