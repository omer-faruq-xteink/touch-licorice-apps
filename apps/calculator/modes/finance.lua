-- Finance for the Calculator (loaded only when opened).
--
-- TVM, the time value of money: N payments, I% a year, PV now, PMT each period, FV at the end,
-- P/Y payments a year, paid at the End or the Beginning of each period. Fill four, tap Solve on
-- the fifth. Money you receive is positive and money you pay is negative, as on a financial
-- calculator: a loan of 200000 has PV = 200000 and a negative PMT. PV, PMT and FV are worked out
-- exactly in decimal when N is whole; N and I% come from floats (shown to their digits).
-- Schedule: each period's interest, principal and balance, with the total interest.
-- Percent: the change from Old to New, and a percentage of a value, added or taken off.

return function(api)
  local kit, D, W = api.kit, api.D, api.W
  local U = require('modes.ui')(api)
  local M = {}

  local function d(s) return D.parse(s) end
  local ONE, HUNDRED = d('1'), d('100')
  local KEYS = { 'n', 'i', 'pv', 'pmt', 'fv', 'py' }
  local LABEL = { n = 'N', i = 'I% (a year)', pv = 'PV', pmt = 'PMT', fv = 'FV', py = 'P/Y' }
  local tvm = { n = d('360'), i = d('5'), pv = d('200000'), pmt = d('0'), fv = d('0'), py = d('12') }
  local approx = {}
  local begin = false
  local pct = { old = d('80'), new = d('100'), value = d('250'), percent = d('15') }
  local view, msg = 'tvm', nil
  local sched, sched_first, sched_total = nil, 0, nil
  local loaded_state = false

  local function save()
    local out = {}
    for _k, k in ipairs(KEYS) do out[#out + 1] = k .. '=' .. D.format(tvm[k], 22) end
    out[#out + 1] = 'begin=' .. tostring(begin)
    for _k, k in ipairs({ 'old', 'new', 'value', 'percent' }) do out[#out + 1] = 'p_' .. k .. '=' .. D.format(pct[k], 22) end
    api.write('finance.txt', table.concat(out, '\n'))
  end
  local function load()
    local s = api.read('finance.txt') or ''
    for k, v in s:gmatch('(%w+)=([^\n]+)') do
      if tvm[k] and d(v) then tvm[k] = d(v)
      elseif k == 'begin' then begin = v == 'true' end
    end
    for k, v in s:gmatch('p_(%w+)=([^\n]+)') do if pct[k] and d(v) then pct[k] = d(v) end end
  end

  ------------------------------------------------------------------ TVM

  local function rate()             -- the rate a period, decimal
    if D.is_zero(tvm.py) then return nil end
    return D.div(D.div(tvm.i, HUNDRED), tvm.py)
  end

  local function fail(m) error({ calc = m }, 0) end

  -- (1 + i)^N exactly when N is whole, else nil
  local function growth(i)
    local n = D.small_int(tvm.n, 100000)
    if not n then return nil end
    return D.pow_int(D.add(ONE, i), n)
  end

  local function solve_money(which)
    local i = rate()
    if not i then fail('P/Y must not be 0') end
    local g = begin and D.add(ONE, i) or ONE
    if D.is_zero(i) then
      -- PV + PMT N + FV = 0
      if which == 'pv' then return D.neg(D.add(D.mul(tvm.pmt, tvm.n), tvm.fv)) end
      if which == 'fv' then return D.neg(D.add(D.mul(tvm.pmt, tvm.n), tvm.pv)) end
      if D.is_zero(tvm.n) then fail('N must not be 0') end
      return D.neg(D.div(D.add(tvm.pv, tvm.fv), tvm.n))
    end
    local p = growth(i)
    if not p then
      -- N is not whole: floats
      approx[which] = true
      local fi, fn = D.to_number(i), D.to_number(tvm.n)
      p = D.from_number((1 + fi) ^ fn, api.FLOAT_DIGITS)
      if not p then fail('out of range') end
    end
    local annuity = D.mul(g, D.div(D.sub(p, ONE), i))      -- PV p + PMT annuity + FV = 0
    if which == 'pv' then return D.neg(D.div(D.add(D.mul(tvm.pmt, annuity), tvm.fv), p)) end
    if which == 'fv' then return D.neg(D.add(D.mul(tvm.pv, p), D.mul(tvm.pmt, annuity))) end
    if D.is_zero(annuity) then fail('N must not be 0') end
    return D.neg(D.div(D.add(D.mul(tvm.pv, p), tvm.fv), annuity))
  end

  local function f_of(i, n, pv, pmt, fv)
    if math.abs(i) < 1e-12 then return pv + pmt * n + fv end
    local p = (1 + i) ^ n
    return pv * p + pmt * (begin and (1 + i) or 1) * (p - 1) / i + fv
  end

  local function solve_n()
    local i = D.to_number(rate() or fail('P/Y must not be 0'))
    local pv, pmt, fv = D.to_number(tvm.pv), D.to_number(tvm.pmt), D.to_number(tvm.fv)
    if math.abs(i) < 1e-12 then
      if pmt == 0 then fail('PMT must not be 0') end
      return -(pv + fv) / pmt
    end
    local g = begin and (1 + i) or 1
    local a, b = pmt * g - fv * i, pmt * g + pv * i
    if b == 0 or a / b <= 0 then fail('no N fits these values') end
    return math.log(a / b) / math.log(1 + i)
  end

  local function solve_i()
    local n = D.to_number(tvm.n)
    local py = D.to_number(tvm.py)
    if py == 0 then fail('P/Y must not be 0') end
    local pv, pmt, fv = D.to_number(tvm.pv), D.to_number(tvm.pmt), D.to_number(tvm.fv)
    local f = function(i) return f_of(i, n, pv, pmt, fv) end
    -- a change of sign between -99% and +1000% a period, then bisection
    local lo, flo = -0.99, f(-0.99)
    local found = false
    local step = 0.0005
    local x = lo + step
    while x < 10 do
      local fx = f(x)
      if fx == fx and flo == flo and (fx < 0) ~= (flo < 0) then found = true; break end
      lo, flo = x, fx
      x = x + step
      step = step * 1.05
    end
    if not found then fail('no interest rate fits these values') end
    local a, b = lo, x
    for _k = 1, 80 do
      local m = (a + b) / 2
      local fm = f(m)
      if (fm < 0) == (flo < 0) then a, flo = m, fm else b = m end
    end
    return (a + b) / 2 * 100 * py
  end

  local function solve(which)
    msg = nil
    approx[which] = nil
    pcall(function() ctx.budget:extend() end)
    local ok, v = pcall(function()
      if which == 'n' then approx.n = true; return D.from_number(solve_n(), api.FLOAT_DIGITS) end
      if which == 'i' then approx.i = true; return D.from_number(solve_i(), api.FLOAT_DIGITS) end
      return solve_money(which)
    end)
    if not ok then msg = type(v) == 'table' and v.calc or tostring(v); return end
    if not v then msg = 'out of range'; return end
    tvm[which] = v
    save()
  end

  local function schedule()
    local i = rate()
    local n = D.small_int(tvm.n, 1200)
    if not i or not n or n < 1 then msg = 'Schedule needs a whole N from 1 to 1200'; return false end
    pcall(function() ctx.budget:extend() end)
    local rows, bal, total = {}, tvm.pv, D.zero()
    for k = 1, n do
      if begin then bal = D.add(bal, tvm.pmt) end
      local int = D.mul(bal, i)
      if begin then
        bal = D.add(bal, int)
        rows[k] = { int, D.neg(D.add(tvm.pmt, int)), bal }
      else
        bal = D.add(D.add(bal, int), tvm.pmt)
        rows[k] = { int, D.neg(D.add(tvm.pmt, int)), bal }
      end
      total = D.add(total, int)
    end
    sched, sched_first, sched_total = rows, 0, total
    return true
  end

  ------------------------------------------------------------------ screens

  local ROW_H = 60
  local function tvm_rows()
    local out = {}
    for k, name in ipairs(KEYS) do
      local y = 70 + (k - 1) * (ROW_H + 6)
      out[#out + 1] = { x = 12, y = y, w = W - 24 - 112, h = ROW_H, key = name }
      if name ~= 'py' then out[#out + 1] = { x = W - 12 - 104, y = y, w = 104, h = ROW_H, key = name, solve = true } end
    end
    return out
  end
  local TVM_BTNS = U.row(478, { 'End', 'Schedule', 'Percent' })

  local function draw_tvm(gg)
    U.header(gg, 'Finance', nil)
    for _k, r in ipairs(tvm_rows()) do
      if r.solve then
        kit.button(gg, r.x, r.y, r.w, r.h, 'Solve', { font = 'medium' })
      else
        gg:rect(r.x, r.y, r.w, r.h, { line_width = 2 })
        U.text(gg, r.x + 12, r.y + 18, LABEL[r.key], 'medium')
        U.rtext(gg, r.x + r.w - 12, r.y + 18, (approx[r.key] and '~' or '') .. U.fit(tvm[r.key], r.w - 160, 'medium'), 'medium')
      end
    end
    TVM_BTNS[1].label = begin and 'Begin' or 'End'
    U.draw_buttons(gg, TVM_BTNS)
    U.note(gg, 548, msg or 'Money in is positive, money out negative.')
    U.note(gg, 600, 'End / Begin: when in each period a payment is made.')
  end

  local function tap_tvm(x, y)
    local r = U.hit(tvm_rows(), x, y)
    if r then
      if r.solve then solve(r.key); return end
      U.ask_value(LABEL[r.key], function(v) tvm[r.key] = v; approx[r.key] = nil; msg = nil; save() end,
                  { tokens = { { t = 'num', s = (D.format(tvm[r.key], 22):gsub('e%+?', 'E')) } } })
      return
    end
    local b = U.hit(TVM_BTNS, x, y)
    if not b then return end
    msg = nil
    if b.label == 'End' or b.label == 'Begin' then begin = not begin; save()
    elseif b.label == 'Schedule' then if schedule() then view = 'schedule' end
    else view = 'percent' end
  end

  local SCHED_ROWS = 14
  local SCHED_BTNS = U.row(700, { 'Up', 'Down' })

  local function draw_schedule(gg)
    U.header(gg, 'Schedule', { 'TVM' })
    local cols = { '#', 'Interest', 'Principal', 'Balance' }
    local xs = { 60, 190, 320, W - 16 }
    for c, l in ipairs(cols) do U.rtext(gg, xs[c], 70, l, 'small') end
    gg:line(12, 96, W - 12, 96)
    for r = 0, SCHED_ROWS - 1 do
      local k = sched_first + r + 1
      local row = sched[k]
      if not row then break end
      local y = 104 + r * 32
      U.rtext(gg, xs[1], y, tostring(k))
      for c = 1, 3 do U.rtext(gg, xs[c + 1], y, D.format(row[c], 9)) end
    end
    U.text(gg, 16, 560, 'Total interest: ' .. D.format(sched_total, 12), 'medium')
    U.draw_buttons(gg, SCHED_BTNS)
  end

  local PCT_FIELDS = { { 'old', 'Old' }, { 'new', 'New' }, { 'value', 'Value' }, { 'percent', 'Percent' } }
  local function pct_rows()
    local out = {}
    for k, f in ipairs(PCT_FIELDS) do
      local y = k <= 2 and (70 + (k - 1) * 64) or (300 + (k - 3) * 64)
      out[#out + 1] = { x = 12, y = y, w = W - 24, h = 56, key = f[1], label = f[2] }
    end
    return out
  end

  local function draw_percent(gg)
    U.header(gg, 'Percent', { 'TVM' })
    for _k, r in ipairs(pct_rows()) do
      gg:rect(r.x, r.y, r.w, r.h, { line_width = 2 })
      U.text(gg, r.x + 12, r.y + 16, r.label, 'medium')
      U.rtext(gg, r.x + r.w - 12, r.y + 16, D.format(pct[r.key], 14), 'medium')
    end
    if D.is_zero(pct.old) then U.text(gg, 16, 210, 'Change: Old must not be 0', 'medium')
    else
      local ch = D.mul(D.div(D.sub(pct.new, pct.old), pct.old), HUNDRED)
      U.text(gg, 16, 210, 'Change: ' .. (ch.neg and '' or '+') .. D.format(ch, 10) .. ' %', 'medium')
    end
    local part = D.div(D.mul(pct.value, pct.percent), HUNDRED)
    U.text(gg, 16, 440, D.format(pct.percent, 10) .. ' % of the value: ' .. D.format(part, 12), 'medium')
    U.text(gg, 16, 476, 'Value + ' .. D.format(pct.percent, 10) .. ' %: ' .. D.format(D.add(pct.value, part), 12), 'medium')
    U.text(gg, 16, 512, 'Value - ' .. D.format(pct.percent, 10) .. ' %: ' .. D.format(D.sub(pct.value, part), 12), 'medium')
  end

  function M.open()
    if not loaded_state then load(); loaded_state = true end
    view, msg = 'tvm', nil
  end

  function M.draw(gg)
    if view == 'schedule' then draw_schedule(gg)
    elseif view == 'percent' then draw_percent(gg)
    else draw_tvm(gg) end
  end

  function M.tap(x, y)
    local right = view ~= 'tvm' and { 'TVM' } or nil
    local h = U.header_hit(x, y, right)
    if h == 'calc' then api.close(); return end
    if h == 'TVM' then view = 'tvm'; return end
    if view == 'tvm' then tap_tvm(x, y)
    elseif view == 'schedule' then
      local b = U.hit(SCHED_BTNS, x, y)
      if b and b.label == 'Up' then sched_first = math.max(0, sched_first - SCHED_ROWS)
      elseif b then sched_first = math.min(sched_first + SCHED_ROWS, math.max(0, #sched - SCHED_ROWS)) end
    else
      local r = U.hit(pct_rows(), x, y)
      if r then U.ask_value(r.label, function(v) pct[r.key] = v; save() end) end
    end
  end

  function M.back()
    if view ~= 'tvm' then view = 'tvm'; return true end
    return false
  end

  if rawget(_G, '__TEST') then
    M.test = { tvm = tvm, solve = solve, msg = function() return msg end, set_begin = function(b) begin = b end,
               schedule = schedule, sched = function() return sched, sched_total end, pct = pct }
  end
  return M
end
