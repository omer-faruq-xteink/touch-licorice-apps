-- Solve for the Calculator (loaded only when opened): an equation Left = Right in X, and every
-- solution between From and To. The difference is sampled at 1000 points; each change of sign
-- is narrowed by bisection (a pole changes sign too, so a point is kept only where the two
-- sides really meet), and a curve that only touches zero is found as a minimum of |Left - Right|.
-- Floats: solutions are shown to the digits a float carries. Tap one to keep it as Ans.

return function(api)
  local kit, D, W = api.kit, api.D, api.W
  local U = require('modes.ui')(api)
  local F = require('modes.fexpr')(api)
  local finite = F.finite
  local M = {}

  local left, right = {}, { { t = 'num', s = '0' } }
  local lo, hi = -10, 10
  local roots, msg = nil, nil
  local loaded_state = false
  local N = 1000

  local function save()
    api.write('solve.txt', 'left=' .. U.pack_tokens(left) .. '\nright=' .. U.pack_tokens(right) ..
      string.format('\nrange=%.9g,%.9g', lo, hi))
  end

  local function load()
    local s = api.read('solve.txt')
    if not s then return end
    left = U.unpack_tokens(s:match('left=([^\n]*)'))
    local r = U.unpack_tokens(s:match('right=([^\n]*)'))
    if #r > 0 then right = r end
    local a, b = (s:match('range=([^\n]*)') or ''):match('^([^,]+),([^,]+)$')
    if tonumber(a) and tonumber(b) and tonumber(a) < tonumber(b) then lo, hi = tonumber(a), tonumber(b) end
  end

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

  local function golden(g, a, b)
    local phi = (math.sqrt(5) - 1) / 2
    for _j = 1, 60 do
      local m1, m2 = b - phi * (b - a), a + phi * (b - a)
      if g(m1) < g(m2) then b = m2 else a = m1 end
    end
    return (a + b) / 2
  end

  -- the solutions of lf(x) = rf(x) in [a, b], at most `max`
  local function solve_all(lf, rf, a, b, max)
    local f = function(x) return lf(x) - rf(x) end
    local scale = function(x) return 1 + math.abs(lf(x)) + math.abs(rf(x)) end
    local out = {}
    local step = (b - a) / N
    local function add(r)
      for _k, x in ipairs(out) do if math.abs(x - r) <= 2 * step then return end end
      out[#out + 1] = r
    end
    local xs, ys = {}, {}
    for i = 0, N do xs[i] = a + i * step; ys[i] = f(xs[i]) end
    for i = 0, N do
      local y = ys[i]
      if finite(y) then
        if y == 0 then add(xs[i])
        elseif i > 0 and finite(ys[i - 1]) and ys[i - 1] ~= 0 and (ys[i - 1] < 0) ~= (y < 0) then
          local r = bisect(f, xs[i - 1], xs[i])
          local fr = f(r)
          if finite(fr) and math.abs(fr) <= 1e-3 * (math.abs(ys[i - 1]) + math.abs(y)) + 1e-9 then add(r) end
        end
        -- touching zero: a small minimum of |f| without a change of sign
        if i > 0 and i < N and finite(ys[i - 1]) and finite(ys[i + 1]) then
          local p, q = math.abs(ys[i - 1]), math.abs(ys[i + 1])
          local m = math.abs(y)
          if m <= p and m <= q and (ys[i - 1] < 0) == (ys[i + 1] < 0) and (y < 0) == (ys[i - 1] < 0) then
            local r = golden(function(x) return math.abs(f(x)) end, xs[i - 1], xs[i + 1])
            if math.abs(f(r)) <= 1e-5 * scale(r) then add(r) end
          end
        end
      end
      if #out >= max then break end
    end
    table.sort(out)
    return out
  end

  local function run()
    roots, msg = nil, nil
    if #left == 0 then msg = 'Type the left side first'; return end
    local lf, e1 = F.compile(left)
    if not lf then msg = 'Left: ' .. e1; return end
    local rf, e2 = F.compile(#right > 0 and right or { { t = 'num', s = '0' } })
    if not rf then msg = 'Right: ' .. e2; return end
    pcall(function() ctx.budget:extend() end)
    roots = solve_all(lf, rf, lo, hi, 10)
    if #roots == 0 then msg = 'No solution between ' .. U.fmt(lo) .. ' and ' .. U.fmt(hi) end
  end

  local function rows()
    return {
      { x = 12, y = 72, w = W - 24, h = 56, key = 'left', label = 'Left' },
      { x = 12, y = 136, w = W - 24, h = 56, key = 'right', label = 'Right' },
      { x = 12, y = 200, w = (W - 32) // 2, h = 56, key = 'lo', label = 'From' },
      { x = 20 + (W - 32) // 2, y = 200, w = (W - 32) // 2, h = 56, key = 'hi', label = 'To' },
    }
  end
  local SOLVE_BTN = { x = 12, y = 272, w = W - 24, h = 56, label = 'Solve' }

  function M.open()
    if not loaded_state then load(); loaded_state = true end
  end

  function M.draw(gg)
    U.header(gg, 'Solve', nil)
    for _k, r in ipairs(rows()) do
      gg:rect(r.x, r.y, r.w, r.h, { line_width = 2 })
      U.text(gg, r.x + 12, r.y + 16, r.label, 'small')
      local s
      if r.key == 'left' then s = #left > 0 and api.text_of(left) or '(tap to type, with X)'
      elseif r.key == 'right' then s = api.text_of(right)
      elseif r.key == 'lo' then s = U.fmt(lo) else s = U.fmt(hi) end
      local f = kit.font('medium')
      local room = r.w - 80
      while #s > 1 and kit.width(f, s) > room do s = kit.drop_last(s) end
      U.rtext(gg, r.x + r.w - 12, r.y + 14, s, 'medium')
    end
    kit.button(gg, SOLVE_BTN.x, SOLVE_BTN.y, SOLVE_BTN.w, SOLVE_BTN.h, 'Solve', { font = 'medium', line_width = 3 })
    if roots then
      for k, r in ipairs(roots) do
        U.text(gg, 20, 344 + (k - 1) * 36, 'X = ' .. U.fmt(r), 'medium')
      end
    end
    local note = msg or (roots and 'Tap a solution to keep it as Ans.') or 'Left = Right is solved for X between From and To.'
    U.note(gg, 720, note)
  end

  function M.tap(x, y)
    if U.header_hit(x, y, nil) == 'calc' then api.close(); return end
    if U.inside(SOLVE_BTN, x, y) then run(); return end
    if roots and y >= 336 and y < 336 + #roots * 36 then
      local r = roots[(y - 336) // 36 + 1]
      local v = r and D.from_number(r, api.FLOAT_DIGITS)
      if v then api.set_ans(v); msg = 'Ans = ' .. U.fmt(r) end
      return
    end
    local r = U.hit(rows(), x, y)
    if not r then return end
    if r.key == 'left' or r.key == 'right' then
      api.edit({ title = r.label, x = true, empty = r.key == 'right', tokens = r.key == 'left' and left or right,
                 on_done = function(toks)
                   if r.key == 'left' then left = toks or {} else right = toks or { { t = 'num', s = '0' } } end
                   roots, msg = nil, nil
                   save()
                 end })
    else
      U.ask_value(r.label, function(v)
        local n = D.to_number(v)
        if r.key == 'lo' then
          if n < hi then lo = n else msg = 'From must be below To' end
        elseif n > lo then hi = n else msg = 'To must be above From' end
        roots = nil
        save()
      end)
    end
  end

  function M.back() return false end

  if rawget(_G, '__TEST') then
    M.test = { roots = function() return roots end, msg = function() return msg end, solve_all = solve_all, F = F }
  end
  return M
end
