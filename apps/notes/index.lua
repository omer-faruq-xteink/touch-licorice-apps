-- Notes for XTOS Licorice, API 2.9. Freehand drawing and typed text on up to 8 pages, kept in
-- ctx.storage; the chosen page becomes the lock screen (lockscreen.lua draws it with a clock).
--
-- Toolbar: Draw | Text (tap again to cycle S/M/L) | Undo | Page | Lock | Clear
-- Pointer phases down/move/up give the strokes; each stroke is one g:polyline per 60-point chunk.
-- Every ctx.* function is a method on this API: call them colon-style.

local W, H, TOP = 480, 800, 56
local NPAGES, MAXPTS = 8, 60
local MIN_STEP = 3

local G, ERR = nil, nil
local page = 1
local items = {}          -- current page: {k='s', pts={x1,y1,...}} | {k='t', x=,y=,f=,text=}
local cur = nil           -- stroke being drawn
local tool = 'draw'
local fsize = 2           -- 1 small 2 medium 3 large
local FNAMES = { 'small', 'medium', 'large' }
local SIZE_TAG = { 'S', 'M', 'L' }
local status = ''

local function short(s, n) s = tostring(s); if #s > n then return s:sub(1, n - 1) .. '~' end return s end
local function note(s) status = tostring(s) end

------------------------------------------------------------------ storage

local function page_name(p) return 'page' .. p .. '.txt' end

local function serialize(list)
  local out = {}
  for _, it in ipairs(list) do
    if it.k == 's' then
      local parts = {}
      for i = 1, #it.pts - 1, 2 do parts[#parts + 1] = it.pts[i] .. ',' .. it.pts[i + 1] end
      out[#out + 1] = 'S ' .. table.concat(parts, ' ')
    elseif it.k == 't' then
      local clean = it.text:gsub('[\r\n]', ' ')
      out[#out + 1] = 'T ' .. it.x .. ' ' .. it.y .. ' ' .. it.f .. ' ' .. clean
    end
  end
  return table.concat(out, '\n')
end

local function parse(s)
  local list = {}
  for line in (s .. '\n'):gmatch('([^\n]*)\n') do
    local kind = line:sub(1, 1)
    if kind == 'S' then
      local pts = {}
      for x, y in line:gmatch('(%-?%d+),(%-?%d+)') do pts[#pts + 1] = tonumber(x); pts[#pts + 1] = tonumber(y) end
      if #pts >= 2 then list[#list + 1] = { k = 's', pts = pts } end
    elseif kind == 'T' then
      local x, y, f, text = line:match('^T (%-?%d+) (%-?%d+) (%d) (.*)$')
      if x then list[#list + 1] = { k = 't', x = tonumber(x), y = tonumber(y), f = tonumber(f), text = text } end
    end
  end
  return list
end

local function save_page()
  local ok, err = pcall(function() return ctx.storage:write(page_name(page), serialize(items)) end)
  if not ok then note('save ! ' .. short(err, 30)) end
end

local function load_page(p)
  page = p
  items = {}
  local ok, data = pcall(function() return ctx.storage:read(page_name(p)) end)
  if ok and type(data) == 'string' then items = parse(data) end
  pcall(function() ctx.state = ctx.state or {}; ctx.state.page = p end)
end

------------------------------------------------------------------ drawing

local function draw_stroke(gg, pts)
  local n = #pts
  if n == 2 then gg:circle(pts[1], pts[2], 1); return end
  -- g:polyline takes a flat {x1, y1, x2, y2, ...} list; chunk long strokes to stay under its
  -- point limit, repeating the joint so the pieces connect
  local i = 1
  while i < n - 1 do
    local j = math.min(n, i + MAXPTS * 2 - 1)
    local chunk = {}
    for k = i, j do chunk[#chunk + 1] = pts[k] end
    gg:polyline(chunk)
    i = j - 1
  end
end

local function draw_items(gg, list, fonts)
  for _, it in ipairs(list) do
    if it.k == 's' then draw_stroke(gg, it.pts)
    elseif it.k == 't' then
      local f = fonts and fonts[FNAMES[it.f] or 'medium']
      if f then gg:text(it.x, it.y, it.text, { font = f }) else gg:text(it.x, it.y, it.text) end
    end
  end
end

local BTNS = { 'Draw', 'Text', 'Undo', 'Page', 'Lock', 'Clear' }
local BW = 78

local function draw_impl(gg)
  gg:clear(0)
  local F = ctx.fonts
  local small = F and F.small
  for i, name in ipairs(BTNS) do
    local x = 4 + (i - 1) * (BW + 1)
    gg:rect(x, 6, BW, 36)
    local label = name
    if name == 'Text' then label = 'Text ' .. SIZE_TAG[fsize] end
    gg:text(x + 6, 13, label, { font = small })
    if (name == 'Draw' and tool == 'draw') or (name == 'Text' and tool == 'text') then gg:line(x + 4, 38, x + BW - 4, 38) end
  end
  gg:text(6, 46, 'page ' .. page .. '/' .. NPAGES .. '  ' .. #items .. ' items  ' .. status, { font = small })
  gg:line(0, TOP + 8, W, TOP + 8)
  draw_items(gg, items, F)
  if cur then draw_stroke(gg, cur.pts) end
  if ERR then gg:text(6, H - 30, short('ERR ' .. ERR, 46), { font = small }) end
end

function on_draw(c, gg)
  G = gg or G
  if not G then return end
  local ok, e = pcall(draw_impl, G)
  if not ok then ERR = tostring(e); pcall(function() G:text(6, H - 60, short('draw ERR ' .. ERR, 46)) end) end
end

local function refresh() pcall(function() ctx.invalidate() end) end

------------------------------------------------------------------ actions

local function add_text_at(x, y)
  local ok, err = pcall(function()
    ctx.input:text({ title = 'Text for page ' .. page, value = '' }, function(c, s)
      if type(s) == 'string' and #s > 0 then
        items[#items + 1] = { k = 't', x = x, y = y, f = fsize, text = s }
        save_page()
      end
      refresh()
    end)
  end)
  if not ok then note('text ! ' .. short(err, 30)) end
end

local function do_lock()
  local L = ctx.lockscreen
  if not L then note('no ctx.lockscreen'); return end
  local function finish(with_clock)
    pcall(function() ctx.storage:write('lock.txt', page .. '\n' .. (with_clock and 'clock' or 'noclock')) end)
    pcall(function() ctx.state = ctx.state or {}; ctx.state.lock_page = page; ctx.state.lock_clock = with_clock end)
    local ok, a = pcall(function() return L:set_default() end)
    note(ok and ('lock page ' .. page .. (with_clock and ' +clock' or '')) or ('lock ! ' .. short(a, 24)))
    refresh()
  end
  local ok = pcall(function()
    ctx.dialog:confirm({ title = 'Lock screen', text = 'Show page ' .. page .. ' when the device locks. Draw a clock on it too?' },
      function(c, yes) finish(yes and true or false) end)
  end)
  if not ok then finish(true) end
end

local function do_clear()
  local ok = pcall(function()
    ctx.dialog:confirm({ title = 'Clear page ' .. page, text = 'Erase everything on this page?' }, function(c, yes)
      if yes then items = {}; save_page() end
      refresh()
    end)
  end)
  if not ok then items = {}; save_page() end
end

local function button(i)
  local name = BTNS[i]
  if name == 'Draw' then tool = 'draw'
  elseif name == 'Text' then
    if tool == 'text' then fsize = fsize % 3 + 1 else tool = 'text' end
  elseif name == 'Undo' then
    if #items > 0 then table.remove(items); save_page() end
  elseif name == 'Page' then
    load_page(page % NPAGES + 1)
  elseif name == 'Lock' then do_lock()
  elseif name == 'Clear' then do_clear() end
end

function on_input(c, ev)
  local ok, e = pcall(function()
    if type(ev) ~= 'table' or ev.type ~= 'pointer' then return end
    local x, y, ph = ev.x or 0, ev.y or 0, ev.phase
    if ph == 'down' then
      if y > TOP + 8 and tool == 'draw' then cur = { k = 's', pts = { x, y } } end
    elseif ph == 'move' then
      if cur then
        local n = #cur.pts
        local dx, dy = x - cur.pts[n - 1], y - cur.pts[n]
        if dx * dx + dy * dy >= MIN_STEP * MIN_STEP then cur.pts[n + 1] = x; cur.pts[n + 2] = y end
      end
    elseif ph == 'up' then
      if cur then
        local n = #cur.pts
        if x ~= cur.pts[n - 1] or y ~= cur.pts[n] then cur.pts[n + 1] = x; cur.pts[n + 2] = y end
        items[#items + 1] = cur; cur = nil
        save_page()
      elseif y < 46 then
        local i = math.floor((x - 4) / (BW + 1)) + 1
        if i >= 1 and i <= #BTNS then button(i) end
      elseif y > TOP + 8 and tool == 'text' then
        add_text_at(x, y)
      end
    end
  end)
  if not ok then ERR = tostring(e) end
  refresh()
  return true
end

function on_load(c)
  local p = 1
  pcall(function() p = tonumber(ctx.state and ctx.state.page) or 1 end)
  if p < 1 or p > NPAGES then p = 1 end
  load_page(p)
end

function on_leave() save_page() end
