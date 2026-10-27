-- Decimal numbers for the calculator: a value is { neg, m, e } = (-1)^neg * m * 10^e with m a
-- string of digits (no leading zeros; "0" for zero). + - * / are exact up to PREC significant
-- digits (so 0.1 + 0.2 - 0.3 is 0). The reader's Lua may have 32-bit numbers (floats with about
-- 7 digits), so the digit work uses small integers only: limbs of 4 digits.

local D = {}
local PREC = 22                 -- significant digits kept; the display shows at most 16
D.PREC = PREC
local BASE, BW = 10000, 4

local function strip(m)
  m = m:gsub('^0+', '')
  return m == '' and '0' or m
end

local function make(neg, m, e)
  m = strip(m)
  if m == '0' then return { neg = false, m = '0', e = 0 } end
  -- trailing zeros into the exponent
  local z = #m:match('0*$')
  if z > 0 then m, e = m:sub(1, #m - z), e + z end
  -- round to PREC significant digits, half up
  if #m > PREC then
    local cut = #m - PREC
    local keep, nxt = m:sub(1, PREC), tonumber(m:sub(PREC + 1, PREC + 1))
    e = e + cut
    if nxt >= 5 then
      -- add one to keep
      local digits, carry = {}, 1
      for i = #keep, 1, -1 do
        local v = keep:byte(i) - 48 + carry
        carry = v // 10
        digits[i] = string.char(48 + v % 10)
      end
      keep = table.concat(digits)
      if carry > 0 then keep = '1' .. keep end
    end
    return make(neg, keep, e)
  end
  return { neg = neg, m = m, e = e }
end
D.make = make

function D.zero() return make(false, '0', 0) end
function D.is_zero(a) return a.m == '0' end

-- "12.5", "-0.03", "1e5", "2.5e-3"
function D.parse(s)
  local sign, int, frac, ex = s:match('^%s*([%-+]?)(%d*)%.?(%d*)[eE]?([%-+]?%d*)%s*$')
  if not sign or (int == '' and frac == '') then return nil end
  return make(sign == '-', int .. frac, (tonumber(ex) or 0) - #frac)
end

------------------------------------------------------------------ integers as limbs

local function to_limbs(m)          -- little-endian limbs of BW digits
  local t, i = {}, #m
  while i >= 1 do
    local j = math.max(1, i - BW + 1)
    t[#t + 1] = tonumber(m:sub(j, i))
    i = j - 1
  end
  return t
end
local function from_limbs(t)
  local n = #t
  while n > 1 and t[n] == 0 do t[n] = nil; n = n - 1 end
  local parts = { tostring(t[n]) }
  for i = n - 1, 1, -1 do parts[#parts + 1] = string.format('%04d', t[i]) end
  return table.concat(parts)
end
local function cmp_m(a, b)            -- digit strings without leading zeros
  if #a ~= #b then return #a < #b and -1 or 1 end
  if a == b then return 0 end
  return a < b and -1 or 1
end
local function add_m(a, b)
  local x, y, out, carry = to_limbs(a), to_limbs(b), {}, 0
  for i = 1, math.max(#x, #y) do
    local v = (x[i] or 0) + (y[i] or 0) + carry
    out[i], carry = v % BASE, v // BASE
  end
  if carry > 0 then out[#out + 1] = carry end
  return from_limbs(out)
end
local function sub_m(a, b)            -- a >= b
  local x, y, out, borrow = to_limbs(a), to_limbs(b), {}, 0
  for i = 1, #x do
    local v = x[i] - (y[i] or 0) - borrow
    if v < 0 then v, borrow = v + BASE, 1 else borrow = 0 end
    out[i] = v
  end
  return from_limbs(out)
end
local function mul_m(a, b)
  local x, y, out = to_limbs(a), to_limbs(b), {}
  for i = 1, #x + #y do out[i] = 0 end
  for i = 1, #x do
    local carry = 0
    for j = 1, #y do
      local v = out[i + j - 1] + x[i] * y[j] + carry      -- < 10^8 + 10^4: fits 32 bits
      out[i + j - 1], carry = v % BASE, v // BASE
    end
    local k = i + #y
    while carry > 0 do
      local v = out[k] + carry
      out[k], carry = v % BASE, v // BASE
      k = k + 1
    end
  end
  return from_limbs(out)
end

------------------------------------------------------------------ arithmetic

local function align(a, b)            -- digit strings at the smaller exponent
  local e = math.min(a.e, b.e)
  return a.m .. string.rep('0', a.e - e), b.m .. string.rep('0', b.e - e), e
end

function D.neg(a) if a.m == '0' then return a end return make(not a.neg, a.m, a.e) end

function D.add(a, b)
  if a.m == '0' then return b end
  if b.m == '0' then return a end
  -- far apart: the smaller one is below the precision
  local top_a, top_b = #a.m + a.e, #b.m + b.e
  if top_a - top_b > PREC + 2 then return a end
  if top_b - top_a > PREC + 2 then return b end
  local x, y, e = align(a, b)
  if a.neg == b.neg then return make(a.neg, add_m(x, y), e) end
  local c = cmp_m(strip(x), strip(y))
  if c == 0 then return D.zero() end
  if c > 0 then return make(a.neg, sub_m(strip(x), strip(y)), e) end
  return make(b.neg, sub_m(strip(y), strip(x)), e)
end
function D.sub(a, b) return D.add(a, D.neg(b)) end

function D.mul(a, b)
  if a.m == '0' or b.m == '0' then return D.zero() end
  return make(a.neg ~= b.neg, mul_m(a.m, b.m), a.e + b.e)
end

-- a / b to PREC + 2 digits by long division; nil when b is 0
function D.div(a, b)
  if b.m == '0' then return nil end
  if a.m == '0' then return D.zero() end
  local want = PREC + 2
  -- scale the dividend so the quotient has `want` digits
  local shift = want + #b.m - #a.m
  if shift < 0 then shift = 0 end
  local num = a.m .. string.rep('0', shift)
  local q, rem = {}, '0'
  for i = 1, #num do
    rem = strip(rem .. num:sub(i, i))
    local d = 0
    while cmp_m(rem, b.m) >= 0 do rem = sub_m(rem, b.m); d = d + 1 end
    q[#q + 1] = string.char(48 + d)
  end
  return make(a.neg ~= b.neg, table.concat(q), a.e - b.e - shift)
end

function D.cmp(a, b)
  local d = D.sub(a, b)
  if d.m == '0' then return 0 end
  return d.neg and -1 or 1
end

-- an integer value as a number (nil when it is not a small whole number)
function D.small_int(a, limit)
  if a.m == '0' then return 0 end
  if a.e < 0 then return nil end
  local digits = #a.m + a.e
  if digits > 9 then return nil end
  local v = tonumber(a.m .. string.rep('0', a.e))
  if v > (limit or 100000000) then return nil end
  return a.neg and -v or v
end

-- a ^ n for a whole n (exact within the precision); nil for 0 ^ negative
function D.pow_int(a, n)
  if n == 0 then return make(false, '1', 0) end
  if n < 0 then
    local p = D.pow_int(a, -n)
    return p and D.div(make(false, '1', 0), p)
  end
  local result, base = make(false, '1', 0), a
  while n > 0 do
    if n % 2 == 1 then result = D.mul(result, base) end
    n = n // 2
    if n > 0 then base = D.mul(base, base) end
  end
  return result
end

-- to and from Lua numbers (for the functions a float computes: sin, ln, ...), rounded to the
-- digits the float can carry
function D.to_number(a) return tonumber((a.neg and '-' or '') .. a.m .. 'e' .. a.e) end
function D.from_number(x, digits)
  if x ~= x or x == math.huge or x == -math.huge then return nil end
  if x == 0 then return D.zero() end
  local s = string.format('%.' .. (digits - 1) .. 'e', x)
  return D.parse(s)
end

-- for the display: at most `sig` significant digits, plain when it fits, else "1.234e+20"
function D.format(a, sig)
  sig = sig or 16
  if a.m == '0' then return '0' end
  local r = a
  if #r.m > sig then
    -- round to sig digits
    local saved = PREC
    PREC = sig
    r = make(a.neg, a.m, a.e)
    PREC = saved
  end
  local m, e = r.m, r.e
  local point = #m + e                    -- digits before the decimal point
  local s
  if point > sig or point < -5 then
    local mant = m:sub(1, 1) .. (#m > 1 and ('.' .. m:sub(2)) or '')
    s = mant .. 'e' .. (point - 1 >= 0 and '+' or '') .. (point - 1)
  elseif e >= 0 then
    s = m .. string.rep('0', e)
  elseif point > 0 then
    s = m:sub(1, point) .. '.' .. m:sub(point + 1)
  else
    s = '0.' .. string.rep('0', -point) .. m
  end
  return (r.neg and '-' or '') .. s
end

return D
