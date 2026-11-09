-- Base for the Calculator (loaded only when opened): a programmer's calculator on 32-bit whole
-- numbers, shown in hex, decimal (signed), octal and binary at once. Type in the base chosen by
-- tapping its line; + - × ÷ (truncating) mod, AND OR XOR NOT, << >> (logical) work left to
-- right as on a desk calculator, and every result wraps to 32 bits. Ans and Keep move a value
-- between here and the calculator.
--
-- The reader's Lua has 32-bit integers and the tests' Lua 64-bit ones: wrap() maps both to the
-- same signed 32-bit value, and the unsigned views mask with 0xFFFFFFFF (which is -1, a no-op,
-- on 32 bits).

return function(api)
  local kit, D, W = api.kit, api.D, api.W
  local U = require('modes.ui')(api)
  local M = {}

  local MASK, SIGN = 0xFFFFFFFF, 0x80000000
  local function wrap(v) return ((v + SIGN) & MASK) - SIGN end
  local function unsigned(v) return v & MASK end

  local BASES = { { 'HEX', 16, 8 }, { 'DEC', 10, 10 }, { 'OCT', 8, 11 }, { 'BIN', 2, 32 } }
  local base = 2                       -- index into BASES
  local value = 0                      -- the shown value
  local entry = nil                    -- digits being typed, in the chosen base
  local acc, op = nil, nil             -- the left side and the operator waiting for a right side
  local fresh = false
  local msg = nil
  local loaded_state = false

  local function save()
    api.write('base.txt', 'base=' .. base .. '\nvalue=' .. tostring(value))
  end
  local function load()
    local s = api.read('base.txt') or ''
    base = math.max(1, math.min(4, tonumber(s:match('base=(%d)')) or 2))
    value = wrap(math.tointeger(tonumber(s:match('value=(%-?%d+)')) or 0) or 0)
  end

  -- 32 bits in groups of 4; split = the high and the low 16 bits apart
  local function bin(v, split)
    local u = unsigned(v)
    local out = {}
    for i = 31, 0, -1 do
      out[#out + 1] = tostring((u >> i) & 1)
      if i == 16 and split then out[#out + 1] = '\n'
      elseif i % 4 == 0 and i > 0 then out[#out + 1] = ' ' end
    end
    return table.concat(out)
  end
  local function show(v, b)
    if b == 1 then return string.format('%X', unsigned(v))
    elseif b == 2 then return tostring(wrap(v))
    elseif b == 3 then return string.format('%o', unsigned(v))
    end
    return bin(v)
  end

  local function current()
    if entry then return wrap(math.tointeger(tonumber(entry, BASES[base][2])) or 0) end
    return value
  end

  local function apply(a, o, b)
    if o == '+' then return wrap(a + b)
    elseif o == '-' then return wrap(a - b)
    elseif o == '×' then return wrap(a * b)
    elseif o == '÷' or o == 'mod' then
      if b == 0 then error({ calc = 'division by zero' }, 0) end
      local q = a // b
      if a % b ~= 0 and ((a < 0) ~= (b < 0)) then q = q + 1 end
      if o == '÷' then return wrap(q) end
      return wrap(a - q * b)
    elseif o == 'AND' then return wrap(a & b)
    elseif o == 'OR' then return wrap(a | b)
    elseif o == 'XOR' then return wrap(a ~ b)
    elseif o == '<<' then
      if b < 0 or b > 31 then return 0 end
      return wrap(a << b)
    elseif o == '>>' then
      if b < 0 or b > 31 then return 0 end
      return wrap(unsigned(a) >> b)
    end
    return b
  end

  local function settle()
    local v = current()
    entry = nil
    if acc and op then
      local ok, r = pcall(apply, acc, op, v)
      if not ok then msg = type(r) == 'table' and r.calc or tostring(r); acc, op = nil, nil; return false end
      v = r
    end
    value, acc, op = v, nil, nil
    return true
  end

  local KEYS = {
    { 'A', 'B', 'C', 'D', 'E', 'F' },
    { '7', '8', '9', 'AND', 'OR', 'XOR' },
    { '4', '5', '6', 'NOT', '<<', '>>' },
    { '1', '2', '3', '×', '÷', 'mod' },
    { '0', '±', 'Del', '+', '-', '=' },
    { 'Clr', 'Ans', 'Keep' },
  }
  local KEY_Y, KEY_H = 290, 62
  local function key_rows()
    local out = {}
    for r, labels in ipairs(KEYS) do out[r] = U.row(KEY_Y + (r - 1) * (KEY_H + 8), labels, KEY_H) end
    return out
  end
  local ROWS = key_rows()
  local function digit_of(l)
    if #l ~= 1 then return nil end
    return tonumber(l, 16)
  end

  local function press(l)
    msg = nil
    local dg = digit_of(l)
    local b = BASES[base]
    if dg then
      if dg >= b[2] then return end
      if fresh then fresh = false end
      local s = entry or ''
      if s == '0' then s = '' end
      if #s >= b[3] then return end
      local t = s .. l
      if b[2] == 10 and tonumber(t) > 4294967295 then return end
      entry = t
    elseif l == 'Del' then
      if entry then entry = #entry > 1 and entry:sub(1, -2) or nil end
    elseif l == 'Clr' then entry, acc, op, value = nil, nil, nil, 0
    elseif l == '±' then
      local v = wrap(-current())
      entry = nil
      value = v
    elseif l == 'NOT' then
      local v = wrap(~current())
      entry = nil
      value = v
    elseif l == '=' then
      if settle() then fresh = true end
    elseif l == 'Ans' then
      local a = api.ans()
      local n = D.small_int(D.trunc(a), 2147483647)
      if not n then msg = 'Ans is not a 32-bit whole number'; return end
      entry, value = nil, wrap(n)
    elseif l == 'Keep' then
      if entry then settle() end
      api.set_ans(D.parse(tostring(value)))
      msg = 'Ans = ' .. tostring(value)
    else
      -- an operator: work out what is waiting, then wait for the right side
      if entry or not acc then
        if not settle() then return end
      end
      acc, op = value, l
    end
    save()
  end

  local function line_y(b) return 70 + (b - 1) * 44 end

  function M.open()
    if not loaded_state then load(); loaded_state = true end
  end

  function M.draw(gg)
    U.header(gg, 'Base', nil)
    local v = current()
    for b, info in ipairs(BASES) do
      local y = line_y(b)
      U.text(gg, 20, y + 8, info[1], b == base and 'medium' or 'small')
      if b == base then gg:rect(12, y, W - 24, b == 4 and 48 or 40, { line_width = 2 }) end
      local s = (b == base and entry) and entry:upper() or (b == 4 and bin(v, true)) or show(v, b)
      if b == 4 and not (b == base and entry) then
        local hi, lo = s:match('^(.-)\n(.*)$')
        U.rtext(gg, W - 24, y + 2, hi, 'small')
        U.rtext(gg, W - 24, y + 24, lo, 'small')
      else
        U.rtext(gg, W - 24, y + 8, s, b == 4 and 'small' or 'medium')
      end
    end
    local pending = acc and (show(acc, base) .. ' ' .. op) or ''
    U.note(gg, 262, msg or pending, 1)
    for _r, row in ipairs(ROWS) do
      for _k, bt in ipairs(row) do
        local dg = digit_of(bt.label)
        local off = dg and dg >= BASES[base][2]
        kit.button(gg, bt.x, bt.y, bt.w, bt.h, bt.label,
                   { font = (#bt.label > 2) and 'medium' or 'large', line_width = off and 1 or (bt.label == '=' and 3 or 2) })
      end
    end
  end

  function M.tap(x, y)
    if U.header_hit(x, y, nil) == 'calc' then api.close(); return end
    for b = 1, 4 do
      local ly = line_y(b)
      if y >= ly and y < ly + (b == 4 and 48 or 40) then
        if entry then settle() end
        base = b
        save()
        return
      end
    end
    for _r, row in ipairs(ROWS) do
      local bt = U.hit(row, x, y)
      if bt then press(bt.label); return end
    end
  end

  function M.back() return false end

  if rawget(_G, '__TEST') then
    M.test = { press = press, value = function() return value end, current = current, show = show, wrap = wrap,
               set_base = function(b) base = b end, msg = function() return msg end }
  end
  return M
end
