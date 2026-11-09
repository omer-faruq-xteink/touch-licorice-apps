-- Float functions of X for Graph, Table and Solve: the calculator's tokens compiled once into Lua
-- closures, so a curve of a few hundred points costs a few hundred calls, not a few hundred
-- parses. Same grammar and precedence as main.lua's evaluate, but in floats (the reader's are
-- 32-bit: about 7 digits, plenty for a picture and shown to 6 digits). A value that does not
-- exist (sqrt of a negative, a pole) comes out as nan or infinity; callers check.
-- require('modes.fexpr')(api) -> F;  F.compile(tokens) -> fn(x) | nil, error

return function(api)
  local F = {}
  local D = api.D
  local NAN = 0 / 0

  local function fact(n)
    if n < 0 or n ~= math.floor(n) or n > 170 then return NAN end
    local r = 1
    for k = 2, n do r = r * k end
    return r
  end

  local function root(v, n)
    if n == 0 then return NAN end
    if v < 0 then
      if n == math.floor(n) and n % 2 == 1 then return -((-v) ^ (1 / n)) end
      return NAN
    end
    return v ^ (1 / n)
  end

  local function gcd(a, b)
    if a ~= math.floor(a) or b ~= math.floor(b) then return NAN end
    a, b = math.abs(a), math.abs(b)
    while b ~= 0 do a, b = b, a % b end
    return a
  end

  local function perm(n, r, choose)
    if n ~= math.floor(n) or r ~= math.floor(r) or n < 0 or r < 0 then return NAN end
    if r > n then return 0 end
    if choose and r > n - r then r = n - r end
    local out = 1
    for i = 0, r - 1 do
      out = out * (n - i)
      if choose then out = out / (i + 1) end
    end
    return out
  end

  -- one-argument functions; angles follow Deg / Rad at the time of the call
  local function trig_in(x) return api.deg() and x * math.pi / 180 or x end
  local function trig_out(x) return api.deg() and x * 180 / math.pi or x end
  local ONE = {
    sin = function(x) return math.sin(trig_in(x)) end,
    cos = function(x) return math.cos(trig_in(x)) end,
    tan = function(x) return math.tan(trig_in(x)) end,
    asin = function(x) if x < -1 or x > 1 then return NAN end return trig_out(math.asin(x)) end,
    acos = function(x) if x < -1 or x > 1 then return NAN end return trig_out(math.acos(x)) end,
    atan = function(x) return trig_out(math.atan(x)) end,
    ln = function(x) if x <= 0 then return NAN end return math.log(x) end,
    log = function(x) if x <= 0 then return NAN end return math.log(x, 10) end,
    sqrt = function(x) if x < 0 then return NAN end return math.sqrt(x) end,
    cbrt = function(x) return root(x, 3) end,
    abs = math.abs,
    int = math.floor,
    exp = math.exp,
    tenpow = function(x) return 10 ^ x end,
  }

  function F.compile(toks)
    local pos = 1
    local function peek() return toks[pos] end
    local function take() pos = pos + 1; return toks[pos - 1] end
    local function bad(msg) error({ calc = msg }, 0) end
    local expr

    local function starts_primary(t)
      return t and (t.t == 'num' or t.t == 'const' or t.t == 'func' or t.t == 'lp' or t.t == 'var')
    end

    local function primary()
      local t = take()
      if not t then bad('incomplete') end
      if t.t == 'num' then
        local v = tonumber((t.s:gsub('E', 'e')))
        if not v then bad('bad number ' .. t.s) end
        return function() return v end
      elseif t.t == 'const' then
        if t.s == 'x' then return function(x) return x end end
        if t.s == 'rand' then return function() return math.random() end end
        local v = t.s == 'pi' and math.pi or t.s == 'e' and math.exp(1) or D.to_number(api.ans())
        return function() return v end
      elseif t.t == 'var' then
        local d = api.var(t.s)
        local v = d and D.to_number(d) or 0
        return function() return v end
      elseif t.t == 'lp' or t.t == 'func' then
        local args = { expr() }
        while peek() and peek().t == 'sep' do take(); args[#args + 1] = expr() end
        if peek() and peek().t == 'rp' then take() end
        if t.t == 'lp' then
          if #args > 1 then bad('a comma outside a function') end
          return args[1]
        end
        local a, b = args[1], args[2]
        local two = (t.s == 'gcd' or t.s == 'lcm' or t.s == 'root')
        if two and not b then bad(t.s .. ' takes two values, with a comma') end
        if t.s == 'round' then
          if b then return function(x) local m = 10 ^ math.floor(b(x)); local v = a(x) * m
            return (v < 0 and -math.floor(-v + 0.5) or math.floor(v + 0.5)) / m end end
          return function(x) local v = a(x); return v < 0 and -math.floor(-v + 0.5) or math.floor(v + 0.5) end
        end
        if not two and b then bad(t.s .. ' takes one value') end
        if t.s == 'root' then return function(x) return root(a(x), b(x)) end end
        if t.s == 'gcd' then return function(x) return gcd(a(x), b(x)) end end
        if t.s == 'lcm' then return function(x)
          local p, q = a(x), b(x)
          local g = gcd(p, q)
          if g ~= g then return NAN end
          if g == 0 then return 0 end
          return math.abs(p // g * q)
        end end
        local f = ONE[t.s]
        if not f then bad('unknown ' .. t.s) end
        return function(x) return f(a(x)) end
      end
      bad('unexpected ' .. t.s)
    end

    local function postfix()
      local v = primary()
      while peek() and peek().t == 'post' do
        local p = take().s
        local inner = v
        if p == '!' then v = function(x) return fact(inner(x)) end
        elseif p == '%' then v = function(x) return inner(x) / 100 end
        elseif p == '²' then v = function(x) local a = inner(x); return a * a end
        elseif p == '³' then v = function(x) local a = inner(x); return a * a * a end
        elseif p == '^-1' then v = function(x) return 1 / inner(x) end
        end
      end
      return v
    end

    local function unary()
      local t = peek()
      if t and t.t == 'op' and (t.s == '-' or t.s == '+') then
        take()
        local v = unary()
        if t.s == '-' then return function(x) return -v(x) end end
        return v
      end
      local v = postfix()
      if peek() and peek().t == 'op' and peek().s == '^' then
        take()
        local base, ex = v, unary()
        v = function(x)
          local a, b = base(x), ex(x)
          if a < 0 and b ~= math.floor(b) then return NAN end
          return a ^ b
        end
      end
      return v
    end

    local function term()
      local v = unary()
      while true do
        local t = peek()
        local l = v
        if t and t.t == 'op' and (t.s == '×' or t.s == '÷' or t.s == 'mod' or t.s == 'nPr' or t.s == 'nCr') then
          take()
          local r = unary()
          if t.s == '×' then v = function(x) return l(x) * r(x) end
          elseif t.s == '÷' then v = function(x) return l(x) / r(x) end
          elseif t.s == 'mod' then v = function(x) local b = r(x); if b == 0 then return NAN end return l(x) % b end
          else
            local choose = t.s == 'nCr'
            v = function(x) return perm(l(x), r(x), choose) end
          end
        elseif starts_primary(t) then
          local r = unary()
          v = function(x) return l(x) * r(x) end          -- 2X, 3(X+1)
        else
          return v
        end
      end
    end

    expr = function()
      local v = term()
      while peek() and peek().t == 'op' and (peek().s == '+' or peek().s == '-') do
        local op = take().s
        local l, r = v, term()
        if op == '+' then v = function(x) return l(x) + r(x) end
        else v = function(x) return l(x) - r(x) end end
      end
      return v
    end

    if #toks == 0 then return nil, 'empty' end
    local ok, fn = pcall(function()
      local f = expr()
      if pos <= #toks then bad('unexpected ' .. toks[pos].s) end
      return f
    end)
    if not ok then return nil, type(fn) == 'table' and fn.calc or tostring(fn) end
    -- a call that raises (a Lua error deep inside) counts as undefined
    return function(x)
      local ok2, y = pcall(fn, x)
      if ok2 and type(y) == 'number' then return y end
      return NAN
    end
  end

  function F.finite(y) return y == y and y ~= math.huge and y ~= -math.huge end

  return F
end
