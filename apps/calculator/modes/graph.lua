-- Graph and Table for the Calculator (loaded only when one of them is opened from Modes).
--
-- Y1-Y4 are functions of X typed with the calculator keys (X takes Ans's place on the keypad),
-- each on or off, drawn as a line, a thick line or dashes so they can be told apart in black and
-- white. Window sets the ranges, Zoom offers Standard, Trig, In, Out, Square, Fit (and Stat for a
-- plot sent from Stats). Trace: < > move along the curve (<< >> 15 pixels), Next Y changes
-- function, a tap on the plot jumps there. Calc: value, zero, minimum, maximum, intersection,
-- dy/dx and the integral between two values, worked out from the formula (bisection, golden
-- section, Simpson), not from the pixels. Table lists X and the Y's from Start by Step.
--
-- A curve is worked out once per change (about 230 points a function) in the input callback,
-- and drawn as a few polylines; a step of the trace draws the same picture with the cursor moved.

return function(api)
  local kit, D, W = api.kit, api.D, api.W
  local U = require('modes.ui')(api)
  local F = require('modes.fexpr')(api)
  local finite = F.finite
  local M = {}

  local PX, PY, PW, PH = 12, 66, 456, 440
  local STYLES = { 'line', 'thick', 'dashes' }
  local Y = {}
  for k = 1, 4 do Y[k] = { toks = {}, on = true, style = k == 2 and 2 or (k == 3 and 3 or 1) } end
  local win = { xmin = -10, xmax = 10, xscl = 1, ymin = -10, ymax = 10, yscl = 1 }
  local tbl = { start = 0, step = 1, first = 0 }
  local fns, errs = {}, {}
  local curves = {}             -- per function: list of flat point lists
  local trace = { x = 0, f = 1 }
  local info = nil              -- a Calc result: { text, ... }
  local shade = nil             -- { a, b, f } after Integral
  local stat = nil              -- { xs, ys, fit, label } from Stats
  local view, stack = 'graph', {}
  local loaded_state = false

  ------------------------------------------------------------------ state

  local function num(s, d) local v = tonumber(s); if v and v == v then return v end return d end

  local function save()
    local lines = {}
    for k = 1, 4 do
      lines[#lines + 1] = 'y' .. k .. '=' .. (Y[k].on and '1' or '0') .. '|' .. Y[k].style .. '|' .. U.pack_tokens(Y[k].toks)
    end
    lines[#lines + 1] = string.format('win=%.9g,%.9g,%.9g,%.9g,%.9g,%.9g', win.xmin, win.xmax, win.xscl, win.ymin, win.ymax, win.yscl)
    lines[#lines + 1] = string.format('tbl=%.9g,%.9g', tbl.start, tbl.step)
    api.write('graph.txt', table.concat(lines, '\n'))
  end

  local function load()
    local s = api.read('graph.txt') or ''
    for line in s:gmatch('[^\n]+') do
      local key, v = line:match('^(%w+)=(.*)$')
      local k = key and tonumber(key:match('^y(%d)$'))
      if k and Y[k] then
        local on, style, toks = v:match('^(%d)|(%d)|(.*)$')
        if on then Y[k] = { on = on == '1', style = math.max(1, math.min(3, tonumber(style))), toks = U.unpack_tokens(toks) } end
      elseif key == 'win' then
        local t = {}
        for p in v:gmatch('[^,]+') do t[#t + 1] = tonumber(p) end
        if #t == 6 and t[1] < t[2] and t[4] < t[5] then
          win = { xmin = t[1], xmax = t[2], xscl = t[3], ymin = t[4], ymax = t[5], yscl = t[6] }
        end
      elseif key == 'tbl' then
        local a, b = v:match('^([^,]+),([^,]+)$')
        tbl.start, tbl.step = num(a, 0), num(b, 1)
      end
    end
  end

  ------------------------------------------------------------------ the picture

  local function x_at(i) return win.xmin + i * (win.xmax - win.xmin) / (PW - 1) end
  local function col_of(x) return (x - win.xmin) / (win.xmax - win.xmin) * (PW - 1) end
  local function to_py(y) return PY + (win.ymax - y) / (win.ymax - win.ymin) * (PH - 1) end
  local function round(v) return math.floor(v + 0.5) end

  local function compile()
    for k = 1, 4 do
      fns[k], errs[k] = nil, nil
      if #Y[k].toks > 0 then fns[k], errs[k] = F.compile(Y[k].toks) end
    end
  end

  local function active(k) return Y[k].on and fns[k] ~= nil end

  -- the curve of fn as polylines inside the plot: gaps where it does not exist, a break at a pole
  local function curve(fn)
    local top, bot = PY, PY + PH - 1
    local lines, cur = {}, nil
    local pa, ya = nil, nil
    local function add(x0, y0, x1, y1, fresh)
      if fresh or not cur or #cur >= 254 then
        cur = { round(x0), round(y0) }
        lines[#lines + 1] = cur
      end
      cur[#cur + 1] = round(x1)
      cur[#cur + 1] = round(y1)
    end
    local i = 0
    while true do
      local y = fn(x_at(i))
      local px = PX + i
      if finite(y) then
        local py = to_py(y)
        if pa and finite(ya) then
          local above = ya < top and py < top
          local below = ya > bot and py > bot
          local pole = (ya < top and py > bot) or (ya > bot and py < top)
          if above or below or pole then
            cur = nil
          else
            local x0, y0, x1, y1 = pa, ya, px, py
            local clipped = false
            if y0 < top then x0 = x0 + (x1 - x0) * (top - y0) / (y1 - y0); y0 = top; clipped = true
            elseif y0 > bot then x0 = x0 + (x1 - x0) * (bot - y0) / (y1 - y0); y0 = bot; clipped = true end
            local cut_end = false
            if y1 < top then x1 = x0 + (x1 - x0) * (top - y0) / (y1 - y0); y1 = top; cut_end = true
            elseif y1 > bot then x1 = x0 + (x1 - x0) * (bot - y0) / (y1 - y0); y1 = bot; cut_end = true end
            add(x0, y0, x1, y1, clipped)
            if cut_end then cur = nil end
          end
        end
        pa, ya = px, py
      else
        pa, ya, cur = nil, nil, nil
      end
      if i >= PW - 1 then break end
      i = math.min(i + 2, PW - 1)
    end
    return lines
  end

  local function compute()
    pcall(function() ctx.budget:extend() end)
    compile()
    curves = {}
    for k = 1, 4 do if active(k) then curves[k] = curve(fns[k]) end end
    if not active(trace.f) then
      for k = 1, 4 do if active(k) then trace.f = k; break end end
    end
  end

  local function draw_axes(gg)
    gg:rect(PX - 1, PY - 1, PW + 2, PH + 2)
    local top, bot = PY, PY + PH - 1
    local ay = to_py(0)
    local ax = PX + col_of(0)
    if ay >= top and ay <= bot then
      gg:line(PX, round(ay), PX + PW - 1, round(ay))
      local n = (win.xmax - win.xmin) / win.xscl
      if win.xscl > 0 and n <= 60 then
        local k = math.ceil(win.xmin / win.xscl)
        while k * win.xscl <= win.xmax do
          local tx = round(PX + col_of(k * win.xscl))
          gg:line(tx, round(ay) - 4, tx, round(ay) + 4)
          k = k + 1
        end
      end
    end
    if ax >= PX and ax <= PX + PW - 1 then
      gg:line(round(ax), top, round(ax), bot)
      local n = (win.ymax - win.ymin) / win.yscl
      if win.yscl > 0 and n <= 60 then
        local k = math.ceil(win.ymin / win.yscl)
        while k * win.yscl <= win.ymax do
          local ty = round(to_py(k * win.yscl))
          gg:line(round(ax) - 4, ty, round(ax) + 4, ty)
          k = k + 1
        end
      end
    end
  end

  local function draw_curve(gg, lines, style)
    local width = style == 2 and 4 or 2
    if style == 3 then
      -- dashes: every other piece of about 6 pixels
      for _k, l in ipairs(lines) do
        local n = #l // 2
        local j = 1
        while j < n do
          local e = math.min(j + 2, n)
          if e > j then
            local pts = {}
            for p = j, e do pts[#pts + 1] = l[2 * p - 1]; pts[#pts + 1] = l[2 * p] end
            gg:polyline(pts, { line_width = width })
          end
          j = j + 6
        end
      end
      return
    end
    for _k, l in ipairs(lines) do
      -- at most 128 points a call
      local n = #l // 2
      local s = 1
      while s < n do
        local e = math.min(s + 127, n)
        local pts = {}
        for p = s, e do pts[#pts + 1] = l[2 * p - 1]; pts[#pts + 1] = l[2 * p] end
        gg:polyline(pts, { line_width = width })
        s = e
      end
    end
  end

  local function draw_shade(gg)
    if not shade or not fns[shade.f] then return end
    local fn = fns[shade.f]
    local ay = math.max(PY, math.min(PY + PH - 1, to_py(0)))
    local c0, c1 = math.max(0, math.ceil(col_of(shade.a))), math.min(PW - 1, math.floor(col_of(shade.b)))
    local c = c0
    while c <= c1 do
      local y = fn(x_at(c))
      if finite(y) then
        local py = math.max(PY, math.min(PY + PH - 1, to_py(y)))
        gg:line(PX + c, round(ay), PX + c, round(py))
      end
      c = c + 6
    end
  end

  local function draw_stat(gg)
    if not stat then return end
    for k = 1, math.min(#stat.xs, 200) do
      local px, py = PX + col_of(stat.xs[k]), to_py(stat.ys[k])
      if px >= PX and px <= PX + PW - 4 and py >= PY and py <= PY + PH - 4 then
        gg:rect(round(px) - 2, round(py) - 2, 5, 5)
      end
    end
    if stat.curve then draw_curve(gg, stat.curve, 1) end
  end

  ------------------------------------------------------------------ Calc

  local function bisect(f, a, b)
    local fa = f(a)
    for _i = 1, 60 do
      local m = (a + b) / 2
      local fm = f(m)
      if fm == 0 then return m end
      if (fa < 0) == (fm < 0) then a, fa = m, fm else b = m end
    end
    return (a + b) / 2
  end

  -- the zero of f nearest x0 in the window: a sign change between samples, then bisection
  local function zero_near(f, x0)
    local best, bestd = nil, math.huge
    local n = PW - 1
    local prevx, prevy = nil, nil
    for i = 0, n do
      local x = x_at(i)
      local y = f(x)
      if finite(y) then
        if y == 0 and math.abs(x - x0) < bestd then best, bestd = x, math.abs(x - x0)
        elseif prevx and finite(prevy) and (prevy < 0) ~= (y < 0) and prevy ~= 0 then
          local r = bisect(f, prevx, x)
          local fr = f(r)
          -- a pole changes sign too: keep only points where f is near 0
          if finite(fr) and math.abs(fr) <= 1e-3 * (math.abs(prevy) + math.abs(y)) + 1e-9 and math.abs(r - x0) < bestd then
            best, bestd = r, math.abs(r - x0)
          end
        end
      end
      prevx, prevy = x, y
    end
    return best
  end

  -- the local minimum (sign 1) or maximum (sign -1) nearest x0: samples, then golden section
  local function extremum_near(f, x0, sign)
    local g = function(x) return sign * f(x) end
    local best, bestd = nil, math.huge
    local n = PW - 1
    local ys = {}
    for i = 0, n do ys[i] = g(x_at(i)) end
    for i = 1, n - 1 do
      local a, b, c = ys[i - 1], ys[i], ys[i + 1]
      if finite(a) and finite(b) and finite(c) and b <= a and b <= c and (b < a or b < c) then
        local lo, hi = x_at(i - 1), x_at(i + 1)
        local phi = (math.sqrt(5) - 1) / 2
        for _j = 1, 50 do
          local m1, m2 = hi - phi * (hi - lo), lo + phi * (hi - lo)
          if g(m1) < g(m2) then hi = m2 else lo = m1 end
        end
        local x = (lo + hi) / 2
        if math.abs(x - x0) < bestd then best, bestd = x, math.abs(x - x0) end
      end
    end
    return best
  end

  local function simpson(f, a, b)
    local n = 200
    local h = (b - a) / n
    local s = f(a) + f(b)
    for i = 1, n - 1 do s = s + (i % 2 == 1 and 4 or 2) * f(a + i * h) end
    return s * h / 3
  end

  local function next_active(k)
    for j = 1, 4 do
      local c = (k + j - 1) % 4 + 1
      if c ~= k and active(c) then return c end
    end
    return nil
  end

  local function name(k) return 'Y' .. k end

  local function set_x(x)
    trace.x = x
    if x >= win.xmin and x <= win.xmax then return end
    -- outside the window: centre it there
    local half = (win.xmax - win.xmin) / 2
    win.xmin, win.xmax = x - half, x + half
    compute()
  end

  -- a result within a millionth of the window from 0 is 0 (bisection stops near, not at, 0)
  local function snap(x)
    if math.abs(x) < (win.xmax - win.xmin) * 1e-6 then return 0 end
    return x
  end

  local function calc(which)
    local f = fns[trace.f]
    if not f then info = { 'Type a function in Y= first' }; return end
    pcall(function() ctx.budget:extend() end)
    local nm = name(trace.f)
    if which == 1 then
      U.ask_value('X =', function(v)
        local x = D.to_number(v)
        set_x(x)
        info = { nm .. '(' .. U.fmt(x) .. ') = ' .. U.fmt(f(x)) }
      end)
    elseif which == 2 then
      local r = zero_near(f, trace.x)
      r = r and snap(r)
      if r then set_x(r); info = { 'Zero of ' .. nm .. ': X = ' .. U.fmt(r) }
      else info = { 'No zero of ' .. nm .. ' in the window' } end
    elseif which == 3 or which == 4 then
      local r = extremum_near(f, trace.x, which == 3 and 1 or -1)
      local word = which == 3 and 'Minimum' or 'Maximum'
      r = r and snap(r)
      if r then set_x(r); info = { word .. ' of ' .. nm, 'X = ' .. U.fmt(r) .. '   Y = ' .. U.fmt(f(r)) }
      else info = { 'No ' .. word:lower() .. ' of ' .. nm .. ' in the window' } end
    elseif which == 5 then
      local other = next_active(trace.f)
      if not other then info = { 'Intersect needs two functions on' }; return end
      local g = fns[other]
      local r = zero_near(function(x) return f(x) - g(x) end, trace.x)
      r = r and snap(r)
      if r then set_x(r); info = { nm .. ' meets ' .. name(other), 'X = ' .. U.fmt(r) .. '   Y = ' .. U.fmt(f(r)) }
      else info = { nm .. ' and ' .. name(other) .. ' do not meet in the window' } end
    elseif which == 6 then
      local x = trace.x
      local h = 1e-3 * math.max(1, math.abs(x))
      local d = (f(x + h) - f(x - h)) / (2 * h)
      info = { 'dy/dx of ' .. nm .. ' at X = ' .. U.fmt(x), '~ ' .. U.fmt(d, 5) }
    elseif which == 7 then
      U.ask_value('Integral from', function(a)
        U.ask_value('Integral to', function(b)
          local x0, x1 = D.to_number(a), D.to_number(b)
          local v = simpson(f, x0, x1)
          shade = { a = math.min(x0, x1), b = math.max(x0, x1), f = trace.f }
          info = { 'Integral of ' .. nm .. ' from ' .. U.fmt(x0) .. ' to ' .. U.fmt(x1), '~ ' .. U.fmt(v) }
        end)
      end)
    end
  end

  local function zoom(which)
    local cx = (trace.x >= win.xmin and trace.x <= win.xmax) and trace.x or (win.xmin + win.xmax) / 2
    local cy = (win.ymin + win.ymax) / 2
    if which == 'Standard' then win = { xmin = -10, xmax = 10, xscl = 1, ymin = -10, ymax = 10, yscl = 1 }
    elseif which == 'Trig' then
      local r = api.deg() and 360 or 2 * math.pi
      win = { xmin = -r, xmax = r, xscl = api.deg() and 90 or math.pi / 2, ymin = -4, ymax = 4, yscl = 1 }
    elseif which == 'In' or which == 'Out' then
      local s = which == 'In' and 0.5 or 2
      local hx, hy = (win.xmax - win.xmin) / 2 * s, (win.ymax - win.ymin) / 2 * s
      win.xmin, win.xmax, win.ymin, win.ymax = cx - hx, cx + hx, cy - hy, cy + hy
    elseif which == 'Square' then
      -- the plot is PW x PH: the same units per pixel both ways
      local ux, uy = (win.xmax - win.xmin) / PW, (win.ymax - win.ymin) / PH
      local u = math.max(ux, uy)
      local mx = (win.xmin + win.xmax) / 2
      win.xmin, win.xmax = mx - u * PW / 2, mx + u * PW / 2
      win.ymin, win.ymax = cy - u * PH / 2, cy + u * PH / 2
    elseif which == 'Fit' then
      local lo, hi = math.huge, -math.huge
      for k = 1, 4 do
        if active(k) then
          for i = 0, PW - 1, 3 do
            local y = fns[k](x_at(i))
            if finite(y) then lo, hi = math.min(lo, y), math.max(hi, y) end
          end
        end
      end
      if lo < hi then
        local pad = (hi - lo) * 0.05
        win.ymin, win.ymax = lo - pad, hi + pad
      elseif lo == hi then win.ymin, win.ymax = lo - 1, hi + 1 end
    elseif which == 'Stat' and stat then
      local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
      for k = 1, #stat.xs do
        x0, x1 = math.min(x0, stat.xs[k]), math.max(x1, stat.xs[k])
        y0, y1 = math.min(y0, stat.ys[k]), math.max(y1, stat.ys[k])
      end
      if x0 == x1 then x0, x1 = x0 - 1, x1 + 1 end
      if y0 == y1 then y0, y1 = y0 - 1, y1 + 1 end
      local px, py = (x1 - x0) * 0.1, (y1 - y0) * 0.1
      win.xmin, win.xmax, win.ymin, win.ymax = x0 - px, x1 + px, y0 - py, y1 + py
    end
    -- tick marks: about 10 a way
    local function scl(span)
      local raw = span / 10
      local p = 10 ^ math.floor(math.log(raw, 10))
      for _k, m in ipairs({ 1, 2, 5, 10 }) do if raw <= m * p then return m * p end end
      return 10 * p
    end
    if which ~= 'Standard' and which ~= 'Trig' then
      win.xscl, win.yscl = scl(win.xmax - win.xmin), scl(win.ymax - win.ymin)
    end
    save()
    compute()
    if stat and stat.fit then stat.curve = curve(stat.fit) end
  end

  ------------------------------------------------------------------ screens

  local function go(v) stack[#stack + 1] = view; view = v end

  local GRAPH_ROWS = {
    U.row(566, { 'Y=', 'Window', 'Zoom', 'Calc' }),
    U.row(626, { '<<', '<', '>', '>>' }),
    U.row(686, { 'Next Y', 'Table', 'Clear' }),
  }

  local function draw_graph(gg)
    U.header(gg, 'Graph', nil)
    draw_axes(gg)
    draw_shade(gg)
    for k = 1, 4 do if curves[k] then draw_curve(gg, curves[k], Y[k].style) end end
    draw_stat(gg)
    local f = fns[trace.f]
    local lines = {}
    if f and active(trace.f) then
      local y = f(trace.x)
      local px = PX + col_of(trace.x)
      if finite(y) then
        local py = to_py(y)
        if px >= PX and px < PX + PW and py >= PY and py < PY + PH then
          gg:circle(round(px), round(py), 7, { line_width = 2 })
        end
      end
      lines[1] = name(trace.f) .. '   X = ' .. U.fmt(trace.x) .. '   Y = ' .. U.fmt(y)
    else
      lines[1] = 'Y= : type a function of X'
    end
    if info then lines[1] = info[1]; lines[2] = info[2] end
    for k, s in ipairs(lines) do
      local f, t = kit.font('small'), s
      while #t > 1 and kit.width(f, t) > W - 32 do t = kit.drop_last(t) end
      U.text(gg, 16, 512 + (k - 1) * 24, t)
    end
    for _k, r in ipairs(GRAPH_ROWS) do U.draw_buttons(gg, r) end
  end

  local function tap_graph(x, y)
    if x >= PX and x < PX + PW and y >= PY and y < PY + PH then
      trace.x = x_at(x - PX)
      info = nil
      -- the function drawn nearest to the tap
      local best, bd = nil, 40
      for k = 1, 4 do
        if active(k) then
          local v = fns[k](trace.x)
          if finite(v) and math.abs(to_py(v) - y) < bd then best, bd = k, math.abs(to_py(v) - y) end
        end
      end
      if best then trace.f = best end
      return
    end
    local b
    for _k, r in ipairs(GRAPH_ROWS) do b = b or U.hit(r, x, y) end
    if not b then return end
    local l = b.label
    if l == 'Y=' then go('y')
    elseif l == 'Window' then go('window')
    elseif l == 'Table' then go('table')
    elseif l == 'Zoom' then
      local opts = { 'Standard', 'Trig', 'In', 'Out', 'Square', 'Fit' }
      if stat then opts[#opts + 1] = 'Stat' end
      U.pick('Zoom', opts, function(k) info = nil; zoom(opts[k]) end)
    elseif l == 'Calc' then
      U.pick('Calc ' .. name(trace.f), { 'Value', 'Zero', 'Minimum', 'Maximum', 'Intersect', 'dy/dx', 'Integral' },
             function(k) shade = nil; calc(k) end)
    elseif l == 'Clear' then info, shade, stat = nil, nil, nil
    elseif l == 'Next Y' then trace.f = next_active(trace.f) or trace.f; info = nil
    else
      local step = (l == '<<' and -15) or (l == '<' and -1) or (l == '>' and 1) or 15
      local c = round(col_of(trace.x)) + step
      c = math.max(0, math.min(PW - 1, c))
      trace.x = x_at(c)
      info = nil
    end
  end

  -- Y=
  local function y_block(k) return 70 + (k - 1) * 112 end
  local function y_buttons(k)
    local top = y_block(k) + 48
    return U.row(top, { 'Edit', Y[k].on and 'On' or 'Off', STYLES[Y[k].style], 'Clear' }, 46)
  end

  local function draw_y(gg)
    U.header(gg, 'Y=', { 'Graph' })
    for k = 1, 4 do
      local top = y_block(k)
      local s = name(k) .. ' = ' .. (#Y[k].toks > 0 and api.text_of(Y[k].toks) or '')
      U.text(gg, 16, top + 8, kit.short(s, 34), 'medium')
      if errs[k] then U.note(gg, top + 30, 'Error: ' .. errs[k], 1) end
      U.draw_buttons(gg, y_buttons(k), { bold = function(b) return b.label == 'On' end })
    end
    U.note(gg, 528, 'X takes Ans\'s place on the keypad while you type.')
  end

  local function edit_y(k)
    api.edit({ title = name(k) .. ' =', x = true, empty = true, tokens = Y[k].toks, on_done = function(toks)
      Y[k].toks = toks or {}
      save()
      compute()
    end })
  end

  local function tap_y(x, y)
    for k = 1, 4 do
      local top = y_block(k)
      if y >= top and y < top + 44 then edit_y(k); return end
      local b = U.hit(y_buttons(k), x, y)
      if b then
        if b.label == 'Edit' then edit_y(k); return
        elseif b.label == 'On' or b.label == 'Off' then Y[k].on = not Y[k].on
        elseif b.label == 'Clear' then Y[k].toks = {}
        else Y[k].style = Y[k].style % 3 + 1 end
        save()
        compute()
        return
      end
    end
  end

  -- Window
  local FIELDS = { 'xmin', 'xmax', 'xscl', 'ymin', 'ymax', 'yscl' }
  local FIELD_LABEL = { xmin = 'Xmin', xmax = 'Xmax', xscl = 'Xscl', ymin = 'Ymin', ymax = 'Ymax', yscl = 'Yscl' }
  local function field_rows()
    local out = {}
    for k, f in ipairs(FIELDS) do
      out[#out + 1] = { x = 12, y = 72 + (k - 1) * 66, w = W - 24, h = 56, label = f }
    end
    return out
  end
  local window_msg = nil

  local function draw_window(gg)
    U.header(gg, 'Window', { 'Graph' })
    for _k, r in ipairs(field_rows()) do
      gg:rect(r.x, r.y, r.w, r.h, { line_width = 2 })
      U.text(gg, r.x + 14, r.y + 14, FIELD_LABEL[r.label], 'medium')
      U.rtext(gg, r.x + r.w - 14, r.y + 14, U.fmt(win[r.label]), 'medium')
    end
    if window_msg then U.note(gg, 480, window_msg, 1) end
    U.note(gg, 510, 'Tap a value to change it. Xscl and Yscl space the tick marks.')
  end

  local function tap_window(x, y)
    local r = U.hit(field_rows(), x, y)
    if not r then return end
    local key = r.label
    U.ask_value(FIELD_LABEL[key], function(v)
      local old = win[key]
      win[key] = D.to_number(v)
      window_msg = nil
      if win.xmin >= win.xmax or win.ymin >= win.ymax then
        win[key] = old
        window_msg = 'Xmin must be below Xmax, Ymin below Ymax'
      elseif (key == 'xscl' or key == 'yscl') and win[key] < 0 then
        win[key] = old
        window_msg = 'Scl must be 0 or more'
      end
      save()
      compute()
    end)
  end

  -- Table
  local ROWS = 13
  local TABLE_BTNS = U.row(566, { 'Start', 'Step', 'Up', 'Down' })

  local function fit(gg, v, w)
    local f = kit.font('small')
    for d = api.FLOAT_DIGITS, 2, -1 do
      local s = U.fmt(v, d)
      if kit.width(f, s) <= w then return s end
    end
    return U.fmt(v, 2)
  end

  local function draw_table(gg)
    U.header(gg, 'Table', { 'Graph' })
    local cols = { 0 }
    for k = 1, 4 do if active(k) then cols[#cols + 1] = k end end
    local cw = (W - 24) // #cols
    for c, k in ipairs(cols) do
      local x = 12 + (c - 1) * cw
      U.rtext(gg, x + cw - 8, 70, k == 0 and 'X' or name(k), 'medium')
      if c > 1 then gg:line(x, 66, x, 66 + (ROWS + 1) * 34) end
    end
    gg:line(12, 100, W - 12, 100)
    for r = 0, ROWS - 1 do
      local xv = tbl.start + (tbl.first + r) * tbl.step
      for c, k in ipairs(cols) do
        local v = k == 0 and xv or fns[k](xv)
        local x = 12 + (c - 1) * cw
        U.rtext(gg, x + cw - 8, 108 + r * 34, fit(gg, v, cw - 12))
      end
    end
    if #cols == 1 then U.note(gg, 540, 'Type a function in Graph, Y= to see its values.') end
    U.draw_buttons(gg, TABLE_BTNS)
    U.text(gg, 16, 630, 'Start ' .. U.fmt(tbl.start) .. ',  Step ' .. U.fmt(tbl.step))
  end

  local function tap_table(x, y)
    local b = U.hit(TABLE_BTNS, x, y)
    if not b then return end
    if b.label == 'Up' then tbl.first = tbl.first - ROWS
    elseif b.label == 'Down' then tbl.first = tbl.first + ROWS
    else
      local key = b.label == 'Start' and 'start' or 'step'
      U.ask_value(b.label, function(v)
        local n = D.to_number(v)
        if key == 'step' and n == 0 then return end
        tbl[key] = n
        tbl.first = 0
        save()
      end)
    end
  end

  ------------------------------------------------------------------ the mode

  function M.open(v, arg)
    if not loaded_state then load(); loaded_state = true end
    view, stack = v == 'table' and 'table' or 'graph', {}
    tbl.first = 0
    if arg and arg.stat then
      stat = arg.stat
      zoom('Stat')
      return
    end
    compute()
    if trace.x < win.xmin or trace.x > win.xmax then trace.x = (win.xmin + win.xmax) / 2 end
  end

  function M.draw(gg)
    if view == 'graph' then draw_graph(gg)
    elseif view == 'y' then draw_y(gg)
    elseif view == 'window' then draw_window(gg)
    else draw_table(gg) end
  end

  function M.tap(x, y)
    local right = (view == 'graph') and nil or { 'Graph' }
    local h = U.header_hit(x, y, right)
    if h == 'calc' then api.close(); return end
    if h == 'Graph' then
      if view == 'table' and #stack == 0 then go('graph') else view = 'graph'; stack = {} end
      return
    end
    if view == 'graph' then tap_graph(x, y)
    elseif view == 'y' then tap_y(x, y)
    elseif view == 'window' then tap_window(x, y)
    else tap_table(x, y) end
  end

  function M.back()
    if #stack == 0 then return false end
    view = table.remove(stack)
    return true
  end

  function M.key(k)
    if view ~= 'graph' then return false end
    if k == 'left' or k == 'right' then
      local c = round(col_of(trace.x)) + (k == 'left' and -1 or 1)
      trace.x = x_at(math.max(0, math.min(PW - 1, c)))
      info = nil
      return true
    end
    return false
  end

  if rawget(_G, '__TEST') then
    M.test = { win = function() return win end, trace = trace, fns = fns, curves = function() return curves end,
               info = function() return info end, view = function() return view end, Y = Y, tbl = tbl,
               zero_near = zero_near, extremum_near = extremum_near, simpson = simpson }
  end
  return M
end
