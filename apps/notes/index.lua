-- Notes for XTOS Licorice, API 2.9. Freehand drawing and typed text on up to 8 pages, kept in
-- ctx.storage; the chosen page becomes the lock screen (lockscreen.lua draws it with a clock).
--
-- Toolbar: Draw | Erase | Text (tap again to cycle S/M/L) | Undo | Page | Lock | Clear
-- Erase cuts strokes where the finger passes (the rest stays) and removes text it touches;
-- Undo after an erase brings back what it took.
-- Pointer phases down/move/up give the strokes; each stroke is one g:polyline per 60-point chunk.
-- Every ctx.* function is a method on this API: call them colon-style.

local W, H, TOP = 480, 800, 56
local NPAGES, MAXPTS = 8, 60
local MIN_STEP = 3
local ERASE_R = 14        -- eraser radius in px

local G, ERR = nil, nil
local page = 1
local items = {}          -- current page: {k='s', pts={x1,y1,...}} | {k='t', x=,y=,f=,text=}
local cur = nil           -- stroke being drawn
local tool = 'draw'
local fsize = 2           -- 1 small 2 medium 3 large
local FNAMES = { 'small', 'medium', 'large' }
local SIZE_TAG = { 'S', 'M', 'L' }
local status = ''
local erase_snap = nil    -- the items before the erase gesture in progress changed anything
local erase_undo = {}     -- { {before = list, after = list, n = count} }, newest last
local eraser_at = nil     -- {x, y} while erasing, to show the eraser

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
  erase_undo, erase_snap = {}, nil
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

local BTNS = { 'Draw', 'Erase', 'Text', 'Undo', 'Page', 'Lock', 'Clear' }
local BW = 66

-- An in-app question (the firmware's dialog:confirm is not reliable on this host): a box with a
-- title, a few lines and buttons; { title, lines = {..}, buttons = { {label, fn}, .. } }.
local modal = nil
local MODAL_X, MODAL_Y, MODAL_W = 30, 180, W - 60
local MODAL_BTN_H = 52

local function modal_buttons()
  local m = modal
  local y = MODAL_Y + 60 + #m.lines * 26 + 10
  local out = {}
  for i, b in ipairs(m.buttons) do
    out[i] = { x = MODAL_X + 20, y = y + (i - 1) * (MODAL_BTN_H + 10), w = MODAL_W - 40, h = MODAL_BTN_H, label = b[1], fn = b[2] }
  end
  return out, y + #m.buttons * (MODAL_BTN_H + 10) + 10 - MODAL_Y
end

local function draw_modal(gg, F)
  local btns, h = modal_buttons()
  gg:rect(MODAL_X, MODAL_Y, MODAL_W, h)
  gg:rect(MODAL_X + 3, MODAL_Y + 3, MODAL_W - 6, h - 6)
  gg:text(MODAL_X + 20, MODAL_Y + 18, modal.title, { font = F and F.large })
  for i, line in ipairs(modal.lines) do
    gg:text(MODAL_X + 20, MODAL_Y + 60 + (i - 1) * 26, line, { font = F and F.small })
  end
  for _, b in ipairs(btns) do
    gg:rect(b.x, b.y, b.w, b.h)
    gg:text(b.x + 16, b.y + 14, b.label, { font = F and F.medium })
  end
end

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
    if (name == 'Draw' and tool == 'draw') or (name == 'Erase' and tool == 'erase') or (name == 'Text' and tool == 'text') then gg:line(x + 4, 38, x + BW - 4, 38) end
  end
  gg:text(6, 46, 'page ' .. page .. '/' .. NPAGES .. '  ' .. #items .. ' items  ' .. status, { font = small })
  gg:line(0, TOP + 8, W, TOP + 8)
  if modal then draw_modal(gg, F); return end
  draw_items(gg, items, F)
  if cur then draw_stroke(gg, cur.pts) end
  if eraser_at then pcall(function() gg:circle(eraser_at[1], eraser_at[2], ERASE_R) end) end
  if ERR then gg:text(6, H - 30, short('ERR ' .. ERR, 46), { font = small }) end
end

function on_draw(c, gg)
  G = gg or G
  if not G then return end
  local ok, e = pcall(draw_impl, G)
  if not ok then pcall(function() G:text(6, H - 60, short('draw ERR ' .. tostring(e), 46)) end) end   -- this frame only
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

-- eraser: strokes are cut where they pass within ERASE_R of (x, y), points and segments alike;
-- pieces of a single point are dropped. Text touched inside its box is removed whole.
local function text_box(it)
  local f = ctx.fonts and ctx.fonts[FNAMES[it.f] or 'medium']
  local ok, w = pcall(function() return f:measure(it.text) end)
  w = (ok and type(w) == 'number') and w or (#it.text * 12)
  local okh, h = pcall(function() return f.line_height end)
  h = (okh and tonumber(h)) or 24
  return it.x, it.y, w, h
end

local function near_segment(px, py, x1, y1, x2, y2, r2)
  local dx, dy = x2 - x1, y2 - y1
  local len2 = dx * dx + dy * dy
  local t = len2 > 0 and ((px - x1) * dx + (py - y1) * dy) / len2 or 0
  t = math.max(0, math.min(1, t))
  local qx, qy = x1 + t * dx - px, y1 + t * dy - py
  return qx * qx + qy * qy <= r2
end

local function erase_at(x, y)
  local r2 = ERASE_R * ERASE_R
  local out, changed = {}, false
  for _, it in ipairs(items) do
    if it.k == 't' then
      local bx, by, bw, bh = text_box(it)
      if x >= bx - 4 and x <= bx + bw + 4 and y >= by - 4 and y <= by + bh + 4 then changed = true
      else out[#out + 1] = it end
    elseif it.k == 's' then
      local pts = it.pts
      local function gone(i) local dx, dy = pts[i] - x, pts[i + 1] - y; return dx * dx + dy * dy <= r2 end
      local piece, pieces, hit = {}, {}, false
      for i = 1, #pts - 1, 2 do
        if gone(i) then
          hit = true
          if #piece >= 4 then pieces[#pieces + 1] = piece end
          piece = {}
        else
          local n = #piece
          if n >= 2 and near_segment(x, y, piece[n - 1], piece[n], pts[i], pts[i + 1], r2) then
            hit = true                                  -- the eraser crossed between two points
            if n >= 4 then pieces[#pieces + 1] = piece end
            piece = {}
          end
          piece[#piece + 1] = pts[i]; piece[#piece + 1] = pts[i + 1]
        end
      end
      if not hit then out[#out + 1] = it
      else
        changed = true
        if #piece >= 4 then pieces[#pieces + 1] = piece end
        for _, pc in ipairs(pieces) do out[#out + 1] = { k = 's', pts = pc } end
      end
    else
      out[#out + 1] = it
    end
  end
  if changed then
    if not erase_snap then erase_snap = items end
    items = out
  end
end

local function erase_done()
  eraser_at = nil
  if not erase_snap then return end
  erase_undo[#erase_undo + 1] = { before = erase_snap, after = items, n = #items }
  if #erase_undo > 10 then table.remove(erase_undo, 1) end
  erase_snap = nil
  save_page()
end

local function do_lock()
  local L = ctx.lockscreen
  if not L then note('no ctx.lockscreen'); return end
  local function finish(with_clock)
    modal = nil
    pcall(function() ctx.storage:write('lock.txt', page .. '\n' .. (with_clock and 'clock' or 'noclock')) end)
    pcall(function() ctx.state = ctx.state or {}; ctx.state.lock_page = page; ctx.state.lock_clock = with_clock end)
    -- the firmware asks "Set as lock screen" itself; once Notes is the lock screen, changing the
    -- page or the clock only needs lock.txt, which the lock entry reads every time
    local okd, is_default = pcall(function() return L:is_default() end)
    local ok, a = true, nil
    if not (okd and is_default == true) then ok, a = pcall(function() return L:set_default() end) end
    note(ok and ('lock page ' .. page .. (with_clock and ' +clock' or ' no clock')) or ('lock ! ' .. short(a, 24)))
    refresh()
  end
  modal = {
    title = 'Lock screen',
    lines = { 'Show page ' .. page .. ' when the device locks.', 'With the clock, the lock screen is', 'redrawn every minute.' },
    buttons = { { 'With clock', function() finish(true) end }, { 'No clock', function() finish(false) end }, { 'Cancel', function() modal = nil end } },
  }
end

local function do_clear()
  modal = {
    title = 'Clear page ' .. page,
    lines = { 'Erase everything on this page?' },
    buttons = { { 'Erase', function() modal = nil; items = {}; erase_undo = {}; save_page() end }, { 'Cancel', function() modal = nil end } },
  }
end

local function button(i)
  local name = BTNS[i]
  if name == 'Draw' then tool = 'draw'
  elseif name == 'Erase' then tool = 'erase'
  elseif name == 'Text' then
    if tool == 'text' then fsize = fsize % 3 + 1 else tool = 'text' end
  elseif name == 'Undo' then
    -- the last erase is undone once everything drawn after it has been undone
    local top = erase_undo[#erase_undo]
    if top and top.after == items and #items == top.n then
      items = top.before; table.remove(erase_undo); save_page()
    elseif #items > 0 then table.remove(items); save_page() end
  elseif name == 'Page' then
    load_page(page % NPAGES + 1)
  elseif name == 'Lock' then do_lock()
  elseif name == 'Clear' then do_clear() end
end

function on_input(c, ev)
  ERR = nil   -- a new interaction clears the last error; a new one sets it again
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    if ev.type == 'key' then
      if modal and ev.key == 'back' then modal = nil end
      return
    end
    if ev.type ~= 'pointer' then return end
    local x, y, ph = ev.x or 0, ev.y or 0, ev.phase
    if modal then
      if ph == 'up' then
        local btns, h = modal_buttons()
        for _, b in ipairs(btns) do
          if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then b.fn(); return end
        end
        if y < MODAL_Y or y > MODAL_Y + h then modal = nil end   -- a tap outside the box cancels
      end
      return
    end
    if tool == 'erase' and (eraser_at or (ph == 'down' and y > TOP + 8)) then
      if ph == 'up' then erase_done(); return end
      if y > TOP + 8 then
        -- follow the finger's path: fast swipes move more than the eraser's width per event
        local px, py = x, y
        if eraser_at then px, py = eraser_at[1], eraser_at[2] end
        local steps = math.max(1, math.ceil(math.sqrt((x - px) ^ 2 + (y - py) ^ 2) / (ERASE_R / 2)))
        for k = 1, steps do erase_at(math.floor(px + (x - px) * k / steps), math.floor(py + (y - py) * k / steps)) end
        eraser_at = { x, y }
      end
      return
    end
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
