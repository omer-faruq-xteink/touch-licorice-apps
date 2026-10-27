-- Calculator for XTOS Licorice, API 2.9 (uses tools/gamekit and src/decimal.lua).
--
-- Basic: digits, + - x /, %, +/-, backspace, clear. Sci adds sin cos tan (and their inverses, in
-- degrees or radians), ln log, square root, x^2, x^y, n!, 1/x, pi, e, brackets, EE and Ans.
-- The expression is typed as on paper and worked out with the usual precedence; brackets left
-- open close at the end, "2pi" and "3(4)" multiply. Labels keep to ASCII and Latin-1 (x ÷ ± ²):
-- the reader's font may not have the minus sign, root or pi signs.
--
-- Arithmetic is exact in decimal (src/decimal.lua, 22 digits, shown to 16): 0.1 + 0.2 - 0.3 is 0.
-- Square roots are refined in decimal too. Functions like sin or ln go through Lua's floats; how
-- many digits those carry is measured at start (the reader's Lua may have 32-bit numbers), and a
-- result that went through them is shown to that many digits and marked "~". The last results
-- stay above the display (tap one to use it); everything is kept between visits.

local D = require('decimal')
local W, H = kit.W, kit.H

-- digits a float carries here: 15 with 64-bit floats, about 6 with 32-bit ones
local FLOAT_DIGITS = (1 + 2 ^ -40 ~= 1) and 15 or 6
local PI = D.parse('3.1415926535897932384626')
local E = D.parse('2.7182818284590452353603')

local mode = 'basic'               -- basic | sci
local deg = true
local tokens = {}                  -- the expression: { t = kind, s = text }
local result, approx, err = nil, false, nil
local fresh = false                -- the result is showing: a digit starts anew, an operator goes on from it
local ans = D.zero()
local history = {}                 -- { expr, value } newest last
local HISTORY_MAX = 20
local ERR = nil

------------------------------------------------------------------ evaluation

local FUNCS = { sin = true, cos = true, tan = true, asin = true, acos = true, atan = true,
                ln = true, log = true, sqrt = true }
local LABEL = { sqrt = 'sqrt', asin = 'asin', acos = 'acos', atan = 'atan' }

local function fail(msg) error({ calc = msg }, 0) end

local function to_rad(x) return deg and x * math.pi / 180 or x end
local function from_rad(x) return deg and x * 180 / math.pi or x end

local function float_fn(name, v)
  approx = true
  local x = D.to_number(v)
  local y
  if name == 'sin' then y = math.sin(to_rad(x))
  elseif name == 'cos' then y = math.cos(to_rad(x))
  elseif name == 'tan' then
    if deg and math.abs((x - 90) % 180) < 1e-9 then fail('tan of ' .. D.format(v, 8) .. ' is undefined') end
    y = math.tan(to_rad(x))
  elseif name == 'asin' or name == 'acos' then
    if x < -1 or x > 1 then fail(name .. ' needs -1 to 1') end
    y = from_rad(name == 'asin' and math.asin(x) or math.acos(x))
  elseif name == 'atan' then y = from_rad(math.atan(x))
  elseif name == 'ln' or name == 'log' then
    if x <= 0 then fail(name .. ' needs a number above 0') end
    y = name == 'ln' and math.log(x) or math.log(x, 10)
  end
  -- values that are whole in degrees: sin 30 = 0.5, cos 90 = 0
  if deg and (name == 'sin' or name == 'cos' or name == 'tan') and math.abs(y) < 1e-12 then y = 0 end
  local r = D.from_number(y, FLOAT_DIGITS)
  if not r then fail('out of range') end
  return r
end

local function sqrt(v)
  if v.neg then fail('square root of a negative number') end
  if D.is_zero(v) then return v end
  -- a float's guess, then Newton in decimal: x = (x + v / x) / 2
  local x = D.from_number(math.sqrt(D.to_number(v)), FLOAT_DIGITS)
  if not x or D.is_zero(x) then approx = true; return D.from_number(math.sqrt(D.to_number(v)), FLOAT_DIGITS) end
  local half = D.parse('0.5')
  for _i = 1, 4 do x = D.mul(D.add(x, D.div(v, x)), half) end
  return x
end

local function factorial(v)
  local n = D.small_int(v, 1000)
  if not n or n < 0 then fail('n! needs a whole number from 0') end
  local r = D.parse('1')
  for k = 2, n do r = D.mul(r, D.parse(tostring(k))) end
  return r
end

local function power(a, b)
  local n = D.small_int(b, 10000)
  if n then
    local r = D.pow_int(a, n)
    if not r then fail('0 to a negative power') end
    return r
  end
  if a.neg then fail('a negative number to a fraction') end
  approx = true
  local r = D.from_number(D.to_number(a) ^ D.to_number(b), FLOAT_DIGITS)
  if not r then fail('out of range') end
  return r
end

-- recursive descent over the tokens
local function evaluate(toks)
  local pos = 1
  local function peek() return toks[pos] end
  local function take() pos = pos + 1; return toks[pos - 1] end
  local expr
  local function starts_primary(t)
    return t and (t.t == 'num' or t.t == 'const' or t.t == 'func' or t.t == 'lp')
  end
  local function primary()
    local t = take()
    if not t then fail('incomplete') end
    if t.t == 'num' then
      local v = D.parse((t.s:gsub('E', 'e')))
      if not v then fail('bad number ' .. t.s) end
      return v
    elseif t.t == 'const' then
      return t.s == 'pi' and PI or t.s == 'e' and E or ans
    elseif t.t == 'lp' or t.t == 'func' then
      local v = expr()
      if peek() and peek().t == 'rp' then take() end
      if t.t == 'func' then
        if t.s == 'sqrt' then return sqrt(v) end
        return float_fn(t.s, v)
      end
      return v
    end
    fail('unexpected ' .. t.s)
  end
  local function postfix()
    local v = primary()
    while peek() and peek().t == 'post' do
      local p = take().s
      if p == '!' then v = factorial(v)
      elseif p == '%' then v = D.div(v, D.parse('100'))
      elseif p == '²' then v = D.mul(v, v)
      elseif p == '^-1' then
        v = D.div(D.parse('1'), v)
        if not v then fail('1/0') end
      end
    end
    return v
  end
  local function unary()
    local t = peek()
    if t and t.t == 'op' and (t.s == '-' or t.s == '+') then
      take()
      local v = unary()
      return t.s == '-' and D.neg(v) or v
    end
    local v = postfix()
    if peek() and peek().t == 'op' and peek().s == '^' then
      take()
      v = power(v, unary())
    end
    return v
  end
  local function term()
    local v = unary()
    while true do
      local t = peek()
      if t and t.t == 'op' and (t.s == '×' or t.s == '÷') then
        take()
        local r = unary()
        if t.s == '×' then v = D.mul(v, r)
        else
          v = D.div(v, r)
          if not v then fail('division by zero') end
        end
      elseif starts_primary(t) then
        v = D.mul(v, unary())                  -- 2pi, 3(4)
      else
        return v
      end
    end
  end
  expr = function()
    local v = term()
    while peek() and peek().t == 'op' and (peek().s == '+' or peek().s == '-') do
      local op = take().s
      local r = term()
      v = op == '+' and D.add(v, r) or D.sub(v, r)
    end
    return v
  end
  local v = expr()
  if pos <= #toks then fail('unexpected ' .. toks[pos].s) end
  return v
end

------------------------------------------------------------------ the expression

local function text_of(toks)
  local out = {}
  for _k, t in ipairs(toks) do
    if t.t == 'func' then out[#out + 1] = (LABEL[t.s] or t.s) .. '('
    elseif t.t == 'op' then out[#out + 1] = (t.s == '^') and '^' or (' ' .. t.s .. ' ')
    else out[#out + 1] = t.s end
  end
  return table.concat(out)
end

local function save()
  local h = {}
  for _k, e in ipairs(history) do h[#h + 1] = e[1] .. '\t' .. e[2] end
  kit.write('calc.txt', 'mode=' .. mode .. '\ndeg=' .. tostring(deg) .. '\nans=' .. D.format(ans, 22) ..
    '\n--\n' .. table.concat(h, '\n'))
end

local function load()
  local s = kit.read('calc.txt') or ''
  local t = kit.kv(s:match('^(.-)\n%-%-\n') or s)
  mode = t.mode == 'sci' and 'sci' or 'basic'
  deg = t.deg ~= 'false'
  ans = (t.ans and D.parse(t.ans)) or D.zero()
  history = {}
  for line in ((s:match('\n%-%-\n(.*)$') or '') .. '\n'):gmatch('([^\n]*)\n') do
    local e, v = line:match('^(.-)\t(.+)$')
    if e then history[#history + 1] = { e, v } end
  end
end

local function last() return tokens[#tokens] end

local function begin_from_result(keep)
  -- after "=": an operator goes on from the answer, anything else starts afresh
  if not fresh then return end
  fresh, result, err = false, nil, nil
  tokens = keep and { { t = 'const', s = 'Ans' } } or {}
end

local function press_digit(ch)
  begin_from_result(false)
  local t = last()
  if t and t.t == 'num' then
    if ch == '.' and (t.s:find('%.') or t.s:find('E')) then return end
    if #t.s >= 20 then return end
    t.s = t.s .. ch
  else
    tokens[#tokens + 1] = { t = 'num', s = ch == '.' and '0.' or ch }
  end
end

local function press_op(op)
  begin_from_result(true)
  local t = last()
  if t and t.t == 'op' and op ~= '-' then t.s = op; return end
  tokens[#tokens + 1] = { t = 'op', s = op }
end

local function press(kind, s)
  begin_from_result(kind == 'post')
  tokens[#tokens + 1] = { t = kind, s = s }
end

local function backspace()
  if fresh then fresh, result, err = false, nil, nil; return end
  local t = last()
  if not t then return end
  if t.t == 'num' and #t.s > 1 then t.s = t.s:sub(1, -2) else table.remove(tokens) end
end

local function negate()
  begin_from_result(true)
  local t = last()
  if t and t.t == 'num' then
    local prev = tokens[#tokens - 1]
    if prev and prev.t == 'op' and prev.s == '-' and (#tokens == 2 or tokens[#tokens - 2].t == 'op' or tokens[#tokens - 2].t == 'lp') then
      table.remove(tokens, #tokens - 1)          -- "-5" back to "5"
    else
      table.insert(tokens, #tokens, { t = 'op', s = '-' })
    end
  else
    tokens[#tokens + 1] = { t = 'op', s = '-' }
  end
end

local function equals()
  if #tokens == 0 or fresh then return end
  approx, err = false, nil
  local ok, v = pcall(evaluate, tokens)
  if not ok then
    err = type(v) == 'table' and v.calc or 'cannot work that out'
    return
  end
  result, ans, fresh = v, v, true
  local shown = D.format(v, approx and FLOAT_DIGITS or 16)
  history[#history + 1] = { text_of(tokens), (approx and '~' or '') .. shown }
  while #history > HISTORY_MAX do table.remove(history, 1) end
  save()
end

------------------------------------------------------------------ keys

local BASIC = {
  { 'C', 'clear' }, { 'Del', 'back' }, { '%', 'post', '%' }, { '÷', 'op', '÷' },
  { '7', 'd' }, { '8', 'd' }, { '9', 'd' }, { '×', 'op', '×' },
  { '4', 'd' }, { '5', 'd' }, { '6', 'd' }, { '-', 'op', '-' },
  { '1', 'd' }, { '2', 'd' }, { '3', 'd' }, { '+', 'op', '+' },
  { '±', 'neg' }, { '0', 'd' }, { '.', 'd' }, { '=', 'eq' },
}
local SCI = {
  { 'sin', 'func', 'sin' }, { 'cos', 'func', 'cos' }, { 'tan', 'func', 'tan' }, { 'pi', 'const', 'pi' }, { 'e', 'const', 'e' },
  { 'asin', 'func', 'asin' }, { 'acos', 'func', 'acos' }, { 'atan', 'func', 'atan' }, { 'ln', 'func', 'ln' }, { 'log', 'func', 'log' },
  { 'sqrt', 'func', 'sqrt' }, { 'x²', 'post', '²' }, { 'x^y', 'op', '^' }, { '(', 'lp', '(' }, { ')', 'rp', ')' },
  { 'n!', 'post', '!' }, { '1/x', 'post', '^-1' }, { 'EE', 'ee' }, { 'Deg', 'deg' }, { 'Ans', 'const', 'Ans' },
}

local function key_action(k)
  local kind = k[2]
  err = nil
  if kind == 'd' then press_digit(k[1])
  elseif kind == 'op' then press_op(k[3])
  elseif kind == 'clear' then tokens, result, err, fresh = {}, nil, nil, false
  elseif kind == 'back' then backspace()
  elseif kind == 'neg' then negate()
  elseif kind == 'eq' then equals()
  elseif kind == 'post' then press('post', k[3])
  elseif kind == 'func' then press('func', k[3])
  elseif kind == 'lp' or kind == 'rp' then press(kind, k[3])
  elseif kind == 'const' then
    begin_from_result(false)
    tokens[#tokens + 1] = { t = 'const', s = k[3] }
  elseif kind == 'ee' then
    local t = last()
    if t and t.t == 'num' and not t.s:find('E') then t.s = t.s .. 'E' end
  elseif kind == 'deg' then deg = not deg; save() end
end

-- the key grid: Sci keys above the basic pad
local PAD_TOP = 230
local function layout()
  local keys = {}
  local top = PAD_TOP
  if mode == 'sci' then
    local kw, kh = (W - 24 - 4 * 6) // 5, 56
    for i, def in ipairs(SCI) do
      local r, c = (i - 1) // 5, (i - 1) % 5
      keys[#keys + 1] = { x = 12 + c * (kw + 6), y = top + r * (kh + 6), w = kw, h = kh, k = def, small = true }
    end
    top = top + 4 * (kh + 6) + 6
  end
  local rows = 5
  local kh = (H - 10 - top - (rows - 1) * 8) // rows
  local kw = (W - 24 - 3 * 8) // 4
  for i, def in ipairs(BASIC) do
    local r, c = (i - 1) // 4, (i - 1) % 4
    keys[#keys + 1] = { x = 12 + c * (kw + 8), y = top + r * (kh + 8), w = kw, h = kh, k = def }
  end
  return keys
end

local MODE_BTN = { x = W - 112, y = 8, w = 100, h = 44 }

------------------------------------------------------------------ drawing

local function rtext(gg, s, y, fname)
  local f = kit.font(fname)
  while #s > 1 and kit.width(f, s) > W - 32 do s = kit.drop_last(s) end
  gg:text(W - 16 - kit.width(f, s), y, s, { font = f })
end

function on_draw(c, gg)
  if not gg then return end
  local ok, e = pcall(function()
    gg:clear(0)
    -- the last two results, tap one to use it
    for k = 1, 2 do
      local h = history[#history - 2 + k]
      if h then gg:text(16, 8 + (k - 1) * 26, kit.short(h[1] .. ' = ' .. h[2], 34), { font = kit.font('small') }) end
    end
    kit.button(gg, MODE_BTN.x, MODE_BTN.y, MODE_BTN.w, MODE_BTN.h, mode == 'basic' and 'Sci' or 'Basic', { font = 'medium' })
    if mode == 'sci' then gg:text(W - 112, 60, deg and 'degrees' or 'radians', { font = kit.font('small') }) end
    -- the expression (wrapped from the right) and the result
    local expr = text_of(tokens)
    local f = kit.font('medium')
    local lines_ = kit.wrap(expr, 'medium', W - 32)
    local y = 88
    for k = math.max(1, #lines_ - 1), #lines_ do rtext(gg, lines_[k], y, 'medium'); y = y + 28 end
    if err then rtext(gg, 'Error: ' .. err, 160, 'small')
    elseif result then rtext(gg, (approx and '~ ' or '= ') .. D.format(result, approx and FLOAT_DIGITS or 16), 150, 'large')
    elseif #tokens == 0 then rtext(gg, '0', 150, 'large') end
    gg:line(12, PAD_TOP - 14, W - 12, PAD_TOP - 14)
    for _k, key in ipairs(layout()) do
      local label = key.k[1]
      if key.k[2] == 'deg' then label = deg and 'Deg' or 'Rad' end
      kit.button(gg, key.x, key.y, key.w, key.h, label, { font = key.small and 'medium' or 'large',
                                                        line_width = key.k[2] == 'eq' and 3 or 2 })
    end
    if ERR then gg:text(12, H - 24, kit.short('ERR ' .. ERR, 48), { font = kit.font('small') }) end
  end)
  if not ok then pcall(function() gg:text(8, H - 60, kit.short('draw ERR ' .. tostring(e), 46)) end) end
end

------------------------------------------------------------------ input

local function tap(x, y)
  if x >= MODE_BTN.x and x < MODE_BTN.x + MODE_BTN.w and y >= MODE_BTN.y and y < MODE_BTN.y + MODE_BTN.h then
    mode = mode == 'basic' and 'sci' or 'basic'
    save()
    return
  end
  if y < 60 and x < MODE_BTN.x then
    -- a result from the list: its value goes into the expression
    local k = y < 34 and 1 or 2
    local h = history[#history - 2 + k]
    if h then
      begin_from_result(false)
      local v = h[2]:gsub('^~', '')
      tokens[#tokens + 1] = { t = 'num', s = (v:gsub('e%+?', 'E')) }
    end
    return
  end
  for _k, key in ipairs(layout()) do
    if x >= key.x and x < key.x + key.w and y >= key.y and y < key.y + key.h then key_action(key.k); return end
  end
end

function on_input(c, ev)
  ERR = nil
  local ok, e = pcall(function()
    if type(ev) ~= 'table' then return end
    if ev.type == 'pointer' and ev.phase == 'up' then tap(ev.x or 0, ev.y or 0) end
  end)
  if not ok then ERR = tostring(e) end
  kit.refresh()
  return true
end

function on_load(c)
  local ok, e = pcall(load)
  if not ok then ERR = tostring(e) end
end
function on_leave() pcall(save) end

if rawget(_G, '__TEST') then
  __TEST.api = { D = D, evaluate = function(toks) approx = false; return evaluate(toks), approx end,
                 result = function() return result and D.format(result, approx and FLOAT_DIGITS or 16) end,
                 err = function() return err end, expr = function() return text_of(tokens) end,
                 mode = function() return mode end, layout = layout, history = function() return history end,
                 FLOAT_DIGITS = FLOAT_DIGITS }
end
