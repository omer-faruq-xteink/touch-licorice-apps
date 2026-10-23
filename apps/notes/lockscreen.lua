-- Notes: the lock-screen entry (manifest "lockscreen.entry"). If the host runs it, it paints the
-- page chosen with Lock in the app, from the same ctx.state, with the time in the corner.
-- Nothing here is verified on a device yet: on firmware 7.6.8 the host never reached this entry.

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

local ok_page = true

local function clock_text()
  local ok, c = pcall(function() return ctx.sys.clock() end)
  if ok and type(c) == 'userdata' or ok and type(c) == 'table' then
    local h, m = tonumber(c.hour), tonumber(c.minute)
    if h and m then return string.format('%02d:%02d', h, m) end
  end
  return nil
end

local function lock_page()
  local S = ctx.state
  if type(S) ~= 'table' or type(S.pages) ~= 'table' then return nil end
  return S.pages[S.lock or S.cur or 1] or S.pages[1]
end

function on_draw()
  local page = lock_page()
  if not ok_page or not page then
    g:clear(0)
    g:text(15, 40, 'Notes lock screen')
    g:text(15, 80, ok_page and 'no page chosen yet' or 'page module missing')
    return
  end
  P.draw_lock(page, g, clock_text())
end

function on_load() end
function on_input() return false end
