-- Stats and Distributions for the Calculator (loaded only when one of them is opened).
--
-- Stats: two lists, L1 and L2 (up to 200 values each), typed with the calculator keys: tap a
-- cell to change it, a cell past the end to add one, Done with nothing typed to delete one.
-- 1-Var: n, mean, sums, sample and population standard deviation, min, Q1, median, Q3, max,
-- exact in decimal (quartiles as on the TI: medians of the lower and upper halves, without the
-- middle value). 2-Var: LinReg (y = ax + b, r, r²) and QuadReg exact in decimal, ExpReg
-- (y = a·b^x, through ln y) in floats; Plot sends the points and the fit to Graph. Tap a result
-- to keep it as Ans.
--
-- Distributions: normal (pdf, cdf, inverse), Student's t (cdf, inverse), chi² cdf, binomial,
-- Poisson and geometric (pdf, cdf). Floats, shown to the digits they carry. Tails are worked out
-- as tails (from the incomplete gamma and beta functions' continued fractions), so a tiny
-- probability does not come out as 1 - 0.9999999.

return function(api)
  local kit, D, W = api.kit, api.D, api.W
  local U = require('modes.ui')(api)
  local M = {}
  local MAX = 200

  local L = { {}, {} }               -- decimal values
  local view, opened = 'lists', 'lists'
  local first = 0                    -- the list row at the top of the screen
  local res = nil                    -- results: { title, lines = { {label, value(decimal|float), approx} }, two }
  local reg = 'LinReg'
  local msg = nil
  local loaded_state = false

  local function save()
    local out = {}
    for k = 1, 2 do
      local v = {}
      for _i, d in ipairs(L[k]) do v[#v + 1] = D.format(d, 22) end
      out[#out + 1] = 'L' .. k .. '=' .. table.concat(v, ',')
    end
    api.write('stats.txt', table.concat(out, '\n'))
  end

  local function load()
    local s = api.read('stats.txt') or ''
    for k = 1, 2 do
      L[k] = {}
      local line = s:match('L' .. k .. '=([^\n]*)') or ''
      for p in line:gmatch('[^,]+') do
        local d = D.parse(p)
        if d then L[k][#L[k] + 1] = d end
      end
    end
  end

  ------------------------------------------------------------------ statistics in decimal

  local function dec(n) return D.parse(tostring(n)) end

  local function sorted(xs)
    local c = {}
    for k, v in ipairs(xs) do c[k] = v end
    table.sort(c, function(a, b) return D.cmp(a, b) < 0 end)
    return c
  end

  local function median(s, a, b)          -- of s[a..b]
    local n = b - a + 1
    if n <= 0 then return nil end
    local m = a + n // 2
    if n % 2 == 1 then return s[m] end
    return D.div(D.add(s[m - 1], s[m]), dec(2))
  end

  local function sums(xs)
    local s, s2 = D.zero(), D.zero()
    for _k, v in ipairs(xs) do s = D.add(s, v); s2 = D.add(s2, D.mul(v, v)) end
    return s, s2
  end

  local function one_var(xs, name)
    local n = #xs
    if n == 0 then msg = name .. ' is empty'; return nil end
    pcall(function() ctx.budget:extend() end)
    local nd = dec(n)
    local s, s2 = sums(xs)
    local mean = D.div(s, nd)
    local ss = D.zero()
    for _k, v in ipairs(xs) do local d = D.sub(v, mean); ss = D.add(ss, D.mul(d, d)) end
    local lines = { { 'n', nd }, { 'mean', mean }, { 'sum', s }, { 'sum of squares', s2 } }
    if n > 1 then
      local sx, a1 = api.sqrt(D.div(ss, dec(n - 1)))
      lines[#lines + 1] = { 'SD (sample)', sx, a1 }
    end
    local px, a2 = api.sqrt(D.div(ss, nd))
    lines[#lines + 1] = { 'SD (population)', px, a2 }
    local st = sorted(xs)
    local h = n // 2
    lines[#lines + 1] = { 'min', st[1] }
    if n > 1 then lines[#lines + 1] = { 'Q1', median(st, 1, h) } end
    lines[#lines + 1] = { 'median', median(st, 1, n) }
    if n > 1 then lines[#lines + 1] = { 'Q3', median(st, n - h + 1, n) } end
    lines[#lines + 1] = { 'max', st[n] }
    return { title = '1-Var ' .. name, lines = lines }
  end

  local function absd(v) return v.neg and D.neg(v) or v end

  -- a small linear system in decimal (Gaussian elimination, largest pivot)
  local function solve(A, b)
    local n = #b
    for c = 1, n do
      local p = c
      for r = c + 1, n do
        if D.cmp(absd(A[r][c]), absd(A[p][c])) > 0 then p = r end
      end
      if D.is_zero(A[p][c]) then return nil end
      A[c], A[p], b[c], b[p] = A[p], A[c], b[p], b[c]
      for r = c + 1, n do
        local f = D.div(A[r][c], A[c][c])
        for k = c, n do A[r][k] = D.sub(A[r][k], D.mul(f, A[c][k])) end
        b[r] = D.sub(b[r], D.mul(f, b[c]))
      end
    end
    local x = {}
    for r = n, 1, -1 do
      local s = b[r]
      for k = r + 1, n do s = D.sub(s, D.mul(A[r][k], x[k])) end
      x[r] = D.div(s, A[r][r])
    end
    return x
  end

  local function pairs_of()
    local n = math.min(#L[1], #L[2])
    return n
  end

  local function two_var()
    local n = pairs_of()
    if n < 2 then msg = '2-Var needs at least 2 pairs in L1 and L2'; return nil end
    pcall(function() ctx.budget:extend() end)
    local xs, ys = {}, {}
    for k = 1, n do xs[k], ys[k] = L[1][k], L[2][k] end
    local nd = dec(n)
    local sx, sx2 = sums(xs)
    local sy, sy2 = sums(ys)
    local sxy = D.zero()
    for k = 1, n do sxy = D.add(sxy, D.mul(xs[k], ys[k])) end
    local mx, my = D.div(sx, nd), D.div(sy, nd)
    local Sxx = D.sub(sx2, D.div(D.mul(sx, sx), nd))
    local Syy = D.sub(sy2, D.div(D.mul(sy, sy), nd))
    local Sxy = D.sub(sxy, D.div(D.mul(sx, sy), nd))
    local lines = { { 'n', nd }, { 'mean x', mx }, { 'mean y', my }, { 'sum x', sx }, { 'sum y', sy }, { 'sum xy', sxy } }
    local fit, label
    if reg == 'LinReg' then
      if D.is_zero(Sxx) then msg = 'all x are the same'; return nil end
      local a = D.div(Sxy, Sxx)
      local b = D.sub(my, D.mul(a, mx))
      lines[#lines + 1] = { 'y = ax + b:  a', a }
      lines[#lines + 1] = { 'b', b }
      if not D.is_zero(Syy) then
        local root, ap = api.sqrt(D.mul(Sxx, Syy))
        if root and not D.is_zero(root) then
          local r = D.div(Sxy, root)
          lines[#lines + 1] = { 'r', r, ap }
          lines[#lines + 1] = { 'r²', D.mul(r, r), ap }
        end
      end
      local fa, fb = D.to_number(a), D.to_number(b)
      fit, label = function(x) return fa * x + fb end, 'LinReg'
    elseif reg == 'QuadReg' then
      if n < 3 then msg = 'QuadReg needs at least 3 pairs'; return nil end
      local s = {}
      for p = 0, 4 do s[p] = D.zero() end
      local t = { [0] = D.zero(), D.zero(), D.zero() }
      for k = 1, n do
        local x, xp = xs[k], dec(1)
        for p = 0, 4 do
          s[p] = D.add(s[p], xp)
          if p <= 2 then t[p] = D.add(t[p], D.mul(xp, ys[k])) end
          xp = D.mul(xp, x)
        end
      end
      local c = solve({ { s[4], s[3], s[2] }, { s[3], s[2], s[1] }, { s[2], s[1], s[0] } }, { t[2], t[1], t[0] })
      if not c then msg = 'QuadReg: the x values do not fix a parabola'; return nil end
      lines[#lines + 1] = { 'y = ax²+bx+c:  a', c[1] }
      lines[#lines + 1] = { 'b', c[2] }
      lines[#lines + 1] = { 'c', c[3] }
      local ssr = D.zero()
      for k = 1, n do
        local x = xs[k]
        local fx = D.add(D.add(D.mul(c[1], D.mul(x, x)), D.mul(c[2], x)), c[3])
        local d = D.sub(ys[k], fx)
        ssr = D.add(ssr, D.mul(d, d))
      end
      if not D.is_zero(Syy) then lines[#lines + 1] = { 'R²', D.sub(dec(1), D.div(ssr, Syy)) } end
      local a, b, cc = D.to_number(c[1]), D.to_number(c[2]), D.to_number(c[3])
      fit, label = function(x) return (a * x + b) * x + cc end, 'QuadReg'
    else
      -- y = a * b^x: a line through (x, ln y)
      local fx, fy = {}, {}
      for k = 1, n do
        local y = D.to_number(ys[k])
        if y <= 0 then msg = 'ExpReg needs every y above 0'; return nil end
        fx[k], fy[k] = D.to_number(xs[k]), math.log(y)
      end
      local mxf, myf = 0, 0
      for k = 1, n do mxf, myf = mxf + fx[k], myf + fy[k] end
      mxf, myf = mxf / n, myf / n
      local sxx, sxyf, syy = 0, 0, 0
      for k = 1, n do
        local dx, dy = fx[k] - mxf, fy[k] - myf
        sxx, sxyf, syy = sxx + dx * dx, sxyf + dx * dy, syy + dy * dy
      end
      if sxx == 0 then msg = 'all x are the same'; return nil end
      local slope = sxyf / sxx
      local a, b = math.exp(myf - slope * mxf), math.exp(slope)
      lines[#lines + 1] = { 'y = a·b^x:  a', a, true }
      lines[#lines + 1] = { 'b', b, true }
      if syy > 0 then
        local r = sxyf / math.sqrt(sxx * syy)
        lines[#lines + 1] = { 'r (of ln y)', r, true }
        lines[#lines + 1] = { 'r²', r * r, true }
      end
      fit, label = function(x) return a * b ^ x end, 'ExpReg'
    end
    local fxs, fys = {}, {}
    for k = 1, n do fxs[k], fys[k] = D.to_number(xs[k]), D.to_number(ys[k]) end
    return { title = '2-Var ' .. reg, lines = lines, two = true, plot = { xs = fxs, ys = fys, fit = fit, label = label } }
  end

  local function plot()
    local r = two_var()
    if r then api.open('Graph', { stat = r.plot }) end
  end

  ------------------------------------------------------------------ distributions (floats)

  local function lfact(n)                 -- ln n!
    local s = 0
    for i = 2, n do s = s + math.log(i) end
    return s
  end
  local function lgamma_half(m)          -- ln Gamma(m / 2) for a whole m >= 1
    if m % 2 == 0 then return lfact(m // 2 - 1) end
    local s = 0.5 * math.log(math.pi)
    for j = 1, (m - 1) // 2 do s = s + math.log(j - 0.5) end
    return s
  end

  -- regularized incomplete gamma: P(a, x) by its series, Q(a, x) by its continued fraction
  local function gamma_pq(a, x, lga)
    if x <= 0 then return 0, 1 end
    if x == math.huge then return 1, 0 end
    local front = math.exp(a * math.log(x) - x - lga)
    if x < a + 1 then
      local term, sum = 1 / a, 1 / a
      for n = 1, 500 do
        term = term * x / (a + n)
        sum = sum + term
        if math.abs(term) < math.abs(sum) * 1e-9 then break end
      end
      local p = sum * front
      return p, 1 - p
    end
    local tiny = 1e-30
    local b = x + 1 - a
    local c, d = 1 / tiny, 1 / b
    local h = d
    for i = 1, 500 do
      local an = -i * (i - a)
      b = b + 2
      d = an * d + b
      if math.abs(d) < tiny then d = tiny end
      c = b + an / c
      if math.abs(c) < tiny then c = tiny end
      d = 1 / d
      local del = d * c
      h = h * del
      if math.abs(del - 1) < 1e-9 then break end
    end
    local q = front * h
    return 1 - q, q
  end

  -- regularized incomplete beta I_x(a, b) by its continued fraction
  local function beta_cf(a, b, x)
    local tiny = 1e-30
    local qab, qap, qam = a + b, a + 1, a - 1
    local c, d = 1, 1 - qab * x / qap
    if math.abs(d) < tiny then d = tiny end
    d = 1 / d
    local h = d
    for m = 1, 500 do
      local m2 = 2 * m
      local aa = m * (b - m) * x / ((qam + m2) * (a + m2))
      d = 1 + aa * d; if math.abs(d) < tiny then d = tiny end
      c = 1 + aa / c; if math.abs(c) < tiny then c = tiny end
      d = 1 / d
      h = h * d * c
      aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
      d = 1 + aa * d; if math.abs(d) < tiny then d = tiny end
      c = 1 + aa / c; if math.abs(c) < tiny then c = tiny end
      d = 1 / d
      local del = d * c
      h = h * del
      if math.abs(del - 1) < 1e-9 then break end
    end
    return h
  end
  local function ibeta(a, b, x, lbeta)
    if x <= 0 then return 0 end
    if x >= 1 then return 1 end
    local front = math.exp(a * math.log(x) + b * math.log(1 - x) - lbeta)
    if x < (a + 1) / (a + b + 2) then return front * beta_cf(a, b, x) / a end
    return 1 - front * beta_cf(b, a, 1 - x) / b
  end

  -- upper tails: P(Z > z) and P(T > t) for z, t >= 0
  local LG_HALF = 0.5 * math.log(math.pi)
  local function norm_upper(z)
    if z == math.huge then return 0 end
    local _p, q = gamma_pq(0.5, z * z / 2, LG_HALF)
    return 0.5 * q
  end
  local function norm_between(lo, hi)
    if lo >= hi then return 0 end
    if lo >= 0 then return norm_upper(lo) - norm_upper(hi) end
    if hi <= 0 then return norm_upper(-hi) - norm_upper(-lo) end
    return 1 - norm_upper(-lo) - norm_upper(hi)
  end
  local function t_upper(t, df)
    if t == math.huge then return 0 end
    local lb = lgamma_half(df) + LG_HALF - lgamma_half(df + 1)
    return 0.5 * ibeta(df / 2, 0.5, df / (df + t * t), lb)
  end
  local function t_between(lo, hi, df)
    if lo >= hi then return 0 end
    if lo >= 0 then return t_upper(lo, df) - t_upper(hi, df) end
    if hi <= 0 then return t_upper(-hi, df) - t_upper(-lo, df) end
    return 1 - t_upper(-lo, df) - t_upper(hi, df)
  end

  local function invert(cdf, p)
    local a, b = -1e4, 1e4
    for _i = 1, 100 do
      local m = (a + b) / 2
      if cdf(m) < p then a = m else b = m end
    end
    return (a + b) / 2
  end

  local function whole(v, nm, lo)
    if v ~= math.floor(v) or v < (lo or 0) or v > 1e6 then error({ calc = nm .. ' must be a whole number' .. (lo == 1 and ' from 1' or ' from 0') }, 0) end
    return math.floor(v)
  end
  local function prob(p)
    if not (p >= 0 and p <= 1) then error({ calc = 'p must be from 0 to 1' }, 0) end
  end
  local function positive(v, nm)
    if not (v > 0) then error({ calc = nm .. ' must be above 0' }, 0) end
  end

  local INF = math.huge
  -- name, fields { label, default }, fn(values) -> number
  local DISTR = {
    { 'normalpdf', { { 'x', 0 }, { 'mean', 0 }, { 'sd', 1 } }, function(v)
      positive(v[3], 'sd')
      local z = (v[1] - v[2]) / v[3]
      return math.exp(-z * z / 2) / (v[3] * math.sqrt(2 * math.pi))
    end },
    { 'normalcdf', { { 'lower', -INF }, { 'upper', INF }, { 'mean', 0 }, { 'sd', 1 } }, function(v)
      positive(v[4], 'sd')
      return norm_between((v[1] - v[3]) / v[4], (v[2] - v[3]) / v[4])
    end },
    { 'invNorm', { { 'area', 0.5 }, { 'mean', 0 }, { 'sd', 1 } }, function(v)
      positive(v[3], 'sd')
      if not (v[1] > 0 and v[1] < 1) then error({ calc = 'area must be between 0 and 1' }, 0) end
      return v[2] + v[3] * invert(function(z) return norm_between(-INF, z) end, v[1])
    end },
    { 'tcdf', { { 'lower', -INF }, { 'upper', INF }, { 'df', 10 } }, function(v)
      local df = whole(v[3], 'df', 1)
      return t_between(v[1], v[2], df)
    end },
    { 'invT', { { 'area', 0.5 }, { 'df', 10 } }, function(v)
      local df = whole(v[2], 'df', 1)
      if not (v[1] > 0 and v[1] < 1) then error({ calc = 'area must be between 0 and 1' }, 0) end
      return invert(function(t) return t_between(-INF, t, df) end, v[1])
    end },
    { 'chi²cdf', { { 'lower', 0 }, { 'upper', INF }, { 'df', 1 } }, function(v)
      local df = whole(v[3], 'df', 1)
      local lg = lgamma_half(df)
      local lo, hi = math.max(0, v[1]), v[2]
      if lo >= hi then return 0 end
      local _a, qlo = gamma_pq(df / 2, lo / 2, lg)
      local _b, qhi = gamma_pq(df / 2, hi / 2, lg)
      return qlo - qhi
    end },
    { 'binompdf', { { 'n', 10 }, { 'p', 0.5 }, { 'k', 5 } }, function(v)
      local n, k = whole(v[1], 'n'), whole(v[3], 'k')
      prob(v[2])
      if k > n then return 0 end
      local p = v[2]
      if p == 0 then return k == 0 and 1 or 0 end
      if p == 1 then return k == n and 1 or 0 end
      local lc = lfact(n) - lfact(k) - lfact(n - k)
      return math.exp(lc + k * math.log(p) + (n - k) * math.log(1 - p))
    end },
    { 'binomcdf', { { 'n', 10 }, { 'p', 0.5 }, { 'k', 5 } }, function(v)
      local n, kk = whole(v[1], 'n'), whole(v[3], 'k')
      prob(v[2])
      local p = v[2]
      if kk >= n then return 1 end
      if p == 0 then return 1 end
      if p == 1 then return 0 end
      local lp, lq = math.log(p), math.log(1 - p)
      local lc, s = 0, 0
      for k = 0, kk do
        if k > 0 then lc = lc + math.log((n - k + 1) / k) end
        s = s + math.exp(lc + k * lp + (n - k) * lq)
      end
      return math.min(1, s)
    end },
    { 'poissonpdf', { { 'mean', 1 }, { 'k', 1 } }, function(v)
      positive(v[1], 'mean')
      local k = whole(v[2], 'k')
      return math.exp(k * math.log(v[1]) - v[1] - lfact(k))
    end },
    { 'poissoncdf', { { 'mean', 1 }, { 'k', 1 } }, function(v)
      positive(v[1], 'mean')
      local kk = whole(v[2], 'k')
      local s, lt = 0, -v[1]
      for k = 0, kk do
        if k > 0 then lt = lt + math.log(v[1] / k) end
        s = s + math.exp(lt)
      end
      return math.min(1, s)
    end },
    { 'geometpdf', { { 'p', 0.5 }, { 'k', 1 } }, function(v)
      prob(v[1])
      local k = whole(v[2], 'k', 1)
      return (1 - v[1]) ^ (k - 1) * v[1]
    end },
    { 'geometcdf', { { 'p', 0.5 }, { 'k', 1 } }, function(v)
      prob(v[1])
      local k = whole(v[2], 'k', 1)
      return 1 - (1 - v[1]) ^ k
    end },
  }
  local form = nil            -- { d = DISTR entry, values = {}, result, err }

  local function fmt_field(v)
    if v == INF then return 'infinity' elseif v == -INF then return '-infinity' end
    return U.fmt(v)
  end

  ------------------------------------------------------------------ screens

  local LIST_ROWS = 12
  local LIST_BTNS = {
    U.row(566, { 'Up', 'Down', 'Clear L1', 'Clear L2' }),
    U.row(626, { '1-Var L1', '1-Var L2', '2-Var', 'Plot' }),
  }

  local function cell_rect(r, c)
    local cw = (W - 24 - 70) // 2
    return { x = 12 + 70 + (c - 1) * cw, y = 104 + r * 36, w = cw, h = 36 }
  end

  local function draw_lists(gg)
    U.header(gg, 'Stats', { 'Distr' })
    U.text(gg, 20, 72, '#', 'medium')
    for c = 1, 2 do
      local r0 = cell_rect(0, c)
      U.rtext(gg, r0.x + r0.w - 10, 72, 'L' .. c .. ' (' .. #L[c] .. ')', 'medium')
      gg:line(r0.x, 66, r0.x, 104 + LIST_ROWS * 36)
    end
    gg:line(12, 100, W - 12, 100)
    for r = 0, LIST_ROWS - 1 do
      local i = first + r + 1
      U.text(gg, 20, 112 + r * 36, tostring(i))
      for c = 1, 2 do
        local rc = cell_rect(r, c)
        local v = L[c][i]
        local s = v and D.format(v, 12) or (i == #L[c] + 1 and '+' or '')
        U.rtext(gg, rc.x + rc.w - 10, 112 + r * 36, s)
      end
    end
    if msg then U.note(gg, 534, msg, 1) end
    for _k, r in ipairs(LIST_BTNS) do U.draw_buttons(gg, r) end
    U.note(gg, 690, 'Tap a cell to change it, + to add one. Done with nothing typed deletes the value.', 3)
  end

  local function edit_cell(c, i)
    local list = L[c]
    if i > #list + 1 then i = #list + 1 end
    if i > MAX then msg = 'a list holds ' .. MAX .. ' values'; return end
    local toks = list[i] and { { t = 'num', s = (D.format(list[i], 22):gsub('e%+?', 'E')) } } or nil
    U.ask_value('L' .. c .. '(' .. i .. ')', function(v)
      if v then list[i] = v elseif list[i] then table.remove(list, i) end
      save()
    end, { empty = true, tokens = toks })
  end

  local function tap_lists(x, y)
    for r = 0, LIST_ROWS - 1 do
      for c = 1, 2 do
        if U.inside(cell_rect(r, c), x, y) then msg = nil; edit_cell(c, first + r + 1); return end
      end
    end
    local b
    for _k, row in ipairs(LIST_BTNS) do b = b or U.hit(row, x, y) end
    if not b then return end
    msg = nil
    local l = b.label
    if l == 'Up' then first = math.max(0, first - LIST_ROWS)
    elseif l == 'Down' then first = math.min(first + LIST_ROWS, MAX - LIST_ROWS)
    elseif l == 'Clear L1' or l == 'Clear L2' then
      local c = l == 'Clear L1' and 1 or 2
      U.pick('Delete all of L' .. c .. '?', { 'Delete' }, function() L[c] = {}; save() end, 1)
    elseif l == '1-Var L1' or l == '1-Var L2' then
      local c = l == '1-Var L1' and 1 or 2
      res = one_var(L[c], 'L' .. c)
      if res then view = 'results' end
    elseif l == '2-Var' then
      res = two_var()
      if res then view = 'results' end
    elseif l == 'Plot' then plot() end
  end

  local REG_BTNS = U.row(686, { 'LinReg', 'QuadReg', 'ExpReg', 'Plot' })

  local function draw_results(gg)
    U.header(gg, res.title, { 'Lists' })
    for k, line in ipairs(res.lines) do
      local y = 72 + (k - 1) * 40
      U.text(gg, 20, y, line[1], 'medium')
      local v = line[2]
      local s = U.fit(v, W - 230, 'medium', line[3] and api.FLOAT_DIGITS or 16)
      U.rtext(gg, W - 20, y, ((line[3]) and '~' or '') .. s, 'medium')
    end
    if res.two then U.draw_buttons(gg, REG_BTNS, { bold = function(b) return b.label == reg end }) end
    U.note(gg, res.two and 748 or 690, msg or 'Tap a result to keep it as Ans.')
  end

  local function tap_results(x, y)
    if res.two then
      local b = U.hit(REG_BTNS, x, y)
      if b then
        if b.label == 'Plot' then plot(); return end
        reg = b.label
        msg = nil
        local r = two_var()
        if r then res = r end
        return
      end
    end
    local k = (y - 64) // 40 + 1
    local line = res.lines[k]
    if line and y >= 64 then
      local v = line[2]
      if type(v) == 'number' then v = D.from_number(v, api.FLOAT_DIGITS) end
      if v then api.set_ans(v); msg = 'Ans = ' .. line[1] end
    end
  end

  local function distr_btns()
    local out = {}
    for idx, d in ipairs(DISTR) do
      local r, c = (idx - 1) // 2, (idx - 1) % 2
      local bw = (W - 32) // 2
      out[#out + 1] = { x = 12 + c * (bw + 8), y = 72 + r * 62, w = bw, h = 54, label = d[1], k = idx }
    end
    return out
  end

  local function draw_distr(gg)
    U.header(gg, 'Distributions', opened == 'lists' and { 'Lists' } or nil)
    U.draw_buttons(gg, distr_btns())
  end

  local function form_rows()
    local out = {}
    for idx, f in ipairs(form.d[2]) do
      out[#out + 1] = { x = 12, y = 72 + (idx - 1) * 64, w = W - 24, h = 56, k = idx, label = f[1] }
    end
    return out
  end
  local FORM_BTN = { x = 12, y = 352, w = W - 24, h = 56, label = 'Work it out' }

  local function compute_form()
    form.result, form.err = nil, nil
    local ok, v = pcall(form.d[3], form.values)
    if ok then form.result = v else form.err = type(v) == 'table' and v.calc or tostring(v) end
  end

  local function draw_form(gg)
    U.header(gg, form.d[1], nil)
    for _k, r in ipairs(form_rows()) do
      gg:rect(r.x, r.y, r.w, r.h, { line_width = 2 })
      U.text(gg, r.x + 14, r.y + 14, r.label, 'medium')
      U.rtext(gg, r.x + r.w - 14, r.y + 14, fmt_field(form.values[r.k]), 'medium')
    end
    kit.button(gg, FORM_BTN.x, FORM_BTN.y, FORM_BTN.w, FORM_BTN.h, FORM_BTN.label, { font = 'medium', line_width = 3 })
    if form.err then U.note(gg, 430, 'Error: ' .. form.err)
    elseif form.result then
      U.text(gg, 16, 430, '~ ' .. U.fmt(form.result), 'large')
      U.note(gg, 480, msg or 'Tap the result to keep it as Ans.')
    end
    U.note(gg, 520, 'Tap a value to change it; EE 99 or more is infinity.')
  end

  local function tap_form(x, y)
    if U.inside(FORM_BTN, x, y) then msg = nil; compute_form(); return end
    if form.result and y >= 420 and y < 470 then
      local v = D.from_number(form.result, api.FLOAT_DIGITS)
      if v then api.set_ans(v); msg = 'Kept as Ans' end
      return
    end
    local r = U.hit(form_rows(), x, y)
    if r then
      U.ask_value(r.label, function(v)
        local n = D.to_number(v)
        if math.abs(n) >= 1e38 then n = n < 0 and -INF or INF end
        form.values[r.k] = n
        form.result, form.err, msg = nil, nil, nil
      end)
    end
  end

  ------------------------------------------------------------------ the mode

  local stack = {}
  local function go(v) stack[#stack + 1] = view; view = v end

  function M.open(v)
    if not loaded_state then load(); loaded_state = true end
    view, opened, stack, msg = v, v, {}, nil
  end

  function M.draw(gg)
    if view == 'lists' then draw_lists(gg)
    elseif view == 'results' then draw_results(gg)
    elseif view == 'distr' then draw_distr(gg)
    else draw_form(gg) end
  end

  function M.tap(x, y)
    local right = (view == 'lists' and { 'Distr' }) or (view == 'results' and { 'Lists' })
                  or (view == 'distr' and opened == 'lists' and { 'Lists' }) or nil
    local h = U.header_hit(x, y, right)
    if h == 'calc' then api.close(); return end
    if h == 'Distr' then go('distr'); return end
    if h == 'Lists' then view, stack = 'lists', {}; return end
    if view == 'lists' then tap_lists(x, y)
    elseif view == 'results' then tap_results(x, y)
    elseif view == 'distr' then
      local b = U.hit(distr_btns(), x, y)
      if b then
        local d = DISTR[b.k]
        local vals = {}
        for k, f in ipairs(d[2]) do vals[k] = f[2] end
        form = { d = d, values = vals }
        msg = nil
        go('form')
      end
    else tap_form(x, y) end
  end

  function M.back()
    if view == 'results' then view = 'lists'; return true end
    if #stack == 0 then return false end
    view = table.remove(stack)
    return true
  end

  if rawget(_G, '__TEST') then
    M.test = { L = L, res = function() return res end, form = function() return form end, msg = function() return msg end,
               DISTR = DISTR, view = function() return view end, set_reg = function(r) reg = r end,
               one_var = one_var, two_var = two_var }
  end
  return M
end
