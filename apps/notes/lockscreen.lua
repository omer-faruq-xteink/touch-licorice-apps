-- Lock-screen entry for Notes (API 2.9). Draws the page chosen with the Lock button, read back
-- from ctx.storage, plus a clock and the battery level when the user asked for them.
local FNAMES = { 'small', 'medium', 'large' }
local MAXPTS = 60

local function parse(s)
  local list = {}
  for line in (s .. '\n'):gmatch('([^\n]*)\n') do
    local kind = line:sub(1, 1)
    if kind == 'S' then
      local pts = {}
      for x, y in line:gmatch('(%-?%d+),(%-?%d+)') do pts[#pts + 1] = tonumber(x); pts[#pts + 1] = tonumber(y) end
      -- "S2 ..." / "S3 ...": pen 2 or 3; plain "S ..." (older pages too) is the thin pen
      local w = tonumber(line:match('^S(%d) ')) or 1
      if #pts >= 2 then list[#list + 1] = { k = 's', pts = pts, w = math.max(1, math.min(3, w)) } end
    elseif kind == 'T' then
      local x, y, f, text = line:match('^T (%-?%d+) (%-?%d+) (%d) (.*)$')
      if x then list[#list + 1] = { k = 't', x = tonumber(x), y = tonumber(y), f = tonumber(f), text = text } end
    end
  end
  return list
end

-- pens: thin (1 px), medium (~3 px), thick (~5 px), drawn as the same line shifted by these offsets
local PEN_OFFSETS = {
  { { 0, 0 } },
  { { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } },
  { { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 },
    { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 } },
}

local function draw_stroke(gg, pts, w)
  local n = #pts
  w = w or 1
  if n == 2 then gg:circle(pts[1], pts[2], w == 1 and 1 or w); return end
  -- g:polyline takes a flat {x1, y1, x2, y2, ...} list; chunk long strokes to stay under its
  -- point limit, repeating the joint so the pieces connect
  local i = 1
  while i < n - 1 do
    local j = math.min(n, i + MAXPTS * 2 - 1)
    for _, o in ipairs(PEN_OFFSETS[w] or PEN_OFFSETS[1]) do
      local chunk = {}
      for k = i, j, 2 do chunk[#chunk + 1] = pts[k] + o[1]; chunk[#chunk + 1] = pts[k + 1] + o[2] end
      gg:polyline(chunk)
    end
    i = j - 1
  end
end

local function read(name)
  local ok, s = pcall(function() return ctx.storage:read(name) end)
  if ok and type(s) == 'string' then return s end
  return nil
end

function on_draw(c, gg)
  if not gg then return end
  local ok, err = pcall(function()
    gg:clear(0)
    local F = ctx.fonts
    local lock = read('lock.txt') or '1\nclock'
    local p, flag = lock:match('^(%d+)\n?(%a*)')
    p = tonumber(p) or 1
    local data = read('page' .. p .. '.txt')
    if data then
      for _, it in ipairs(parse(data)) do
        if it.k == 's' then draw_stroke(gg, it.pts, it.w)
        else
          local f = F and F[FNAMES[it.f] or 'medium']
          if f then gg:text(it.x, it.y, it.text, { font = f }) else gg:text(it.x, it.y, it.text) end
        end
      end
    else
      gg:text(20, 380, 'Notes: page ' .. p .. ' is empty', { font = F and F.medium })
    end
    if flag ~= 'noclock' then
      local okc, t = pcall(function() return ctx.clock:now() end)
      local when = (okc and type(t) == 'table') and string.format('%02d:%02d', tonumber(t.hour) or 0, tonumber(t.minute) or 0) or ''
      local okb, b = pcall(function() return ctx.device:battery() end)
      local bat = (okb and type(b) == 'table' and b.percent) and (tostring(b.percent) .. '%') or ''
      local f = F and F.large
      local w = #when * 14
      if f then local okm, m = pcall(function() return f:measure(when) end); if okm and type(m) == 'number' then w = m end end
      gg:text(480 - 16 - w, 12, when, { font = f })
      gg:text(16, 16, bat, { font = F and F.small })
    end
  end)
  if not ok then pcall(function() gg:text(10, 760, 'lock error: ' .. tostring(err):sub(1, 40)) end) end
end

-- Without the clock nothing changes on the lock screen, so try to switch the periodic redraw
-- (manifest interval_sec) off. The host's lock-timer API is not documented for API 2.9: each
-- call is tried and ignored when it is missing.
function on_load()
  local lock = read('lock.txt') or ''
  if not lock:find('noclock', 1, true) then return end
  for _, t in ipairs({ ctx.lockscreen, ctx.lock }) do
    if t then
      pcall(function() t:set_interval(0) end)
      pcall(function() t:set_interval(86400) end)
    end
  end
end
function on_tick() end
function on_input() return false end
