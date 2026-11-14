-- Port Wren: a small text format for the saved town and case (no `load`, so a damaged file can do
-- nothing but fail to read). Values: integers `i12;`, other numbers `n0.5;`, booleans `t` `f`,
-- strings `s5:hello` (length first, so any byte may follow), tables `{` key value ... `}` with the
-- keys sorted, so the same table always gives the same text.

local S = {}

local function key_less(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then return ta == 'number' end
  return a < b
end

local function enc(v, out)
  local t = type(v)
  if t == 'number' then
    if math.type(v) == 'integer' then out[#out + 1] = 'i' .. string.format('%d', v) .. ';'
    else out[#out + 1] = 'n' .. string.format('%.17g', v) .. ';' end
  elseif t == 'boolean' then out[#out + 1] = v and 't' or 'f'
  elseif t == 'string' then out[#out + 1] = 's' .. #v .. ':' .. v
  elseif t == 'table' then
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, key_less)
    out[#out + 1] = '{'
    for _, k in ipairs(keys) do enc(k, out); enc(v[k], out) end
    out[#out + 1] = '}'
  else error('cannot save a ' .. t) end
end

function S.encode(v)
  local out = {}
  enc(v, out)
  return table.concat(out)
end

local function dec(s, p)
  local c = s:sub(p, p)
  if c == 'i' or c == 'n' then
    local e = s:find(';', p, true)
    if not e then error('bad number') end
    local v = c == 'i' and math.tointeger(tonumber(s:sub(p + 1, e - 1))) or tonumber(s:sub(p + 1, e - 1))
    if v == nil then error('bad number') end
    return v, e + 1
  elseif c == 't' then return true, p + 1
  elseif c == 'f' then return false, p + 1
  elseif c == 's' then
    local colon = s:find(':', p, true)
    local n = colon and tonumber(s:sub(p + 1, colon - 1))
    if not n or colon + n > #s then error('bad string') end
    return s:sub(colon + 1, colon + n), colon + n + 1
  elseif c == '{' then
    local t = {}
    p = p + 1
    while true do
      if p > #s then error('unclosed table') end
      if s:sub(p, p) == '}' then return t, p + 1 end
      local k, v
      k, p = dec(s, p)
      v, p = dec(s, p)
      t[k] = v
    end
  end
  error('bad value at ' .. p)
end

-- the value, or nil when s is not a whole, well-formed value
function S.decode(s)
  if type(s) ~= 'string' or s == '' then return nil end
  local ok, v, p = pcall(dec, s, 1)
  if not ok or p ~= #s + 1 then return nil end
  return v
end

return S
