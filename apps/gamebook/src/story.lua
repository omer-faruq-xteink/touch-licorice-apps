-- story.lua: reads the .story format (see FORMAT.md) and plays it. No drawing here.
--
--   S.index(src)                 -> story or nil, err   src = { size = n, read = function(off, len) }
--   S.index_string(story), S.from_index(src, s)        the index kept in storage
--   S.new_state(story), S.save(st), S.load(story, s)
--   S.enter(story, st, name)     -> view { name, lines, choices = { {label, k} }, cont, ending }
--   S.choose(story, st, view, i) -> the next passage name

local S = {}

------------------------------------------------------------------ index

local NAME = '[%a_][%w_%.]*'

local function parse_value(v)
  v = v:match('^%s*(.-)%s*$')
  if v == 'true' then return true elseif v == 'false' then return false end
  local q = v:match('^"(.*)"$') or v:match("^'(.*)'$")
  if q then return (q:gsub('\\(.)', '%1')) end
  return math.tointeger(tonumber(v)) or tonumber(v) or 0
end

local function parse_header(story, lines)
  for _, l in ipairs(lines) do
    local k, v = l:match('^%s*([%a_]+)%s*:%s*(.-)%s*$')
    if k == 'var' then
      local n, val = v:match('^(' .. NAME .. ')%s*=%s*(.*)$')
      if n then story.vars[n] = parse_value(val); story.var_order[#story.var_order + 1] = n end
    elseif k and l:sub(1, 2) ~= '//' then
      story.meta[k:lower()] = v
    end
  end
end

local function new_story(src)
  return { src = src, meta = {}, vars = {}, var_order = {}, idx = {}, order = {}, cache = {} }
end

-- one pass over the file, 64 KB at a time: the header lines and where each passage starts
function S.index(src)
  local story, head = new_story(src), {}
  local idx, order, cur = story.idx, story.order, nil
  local function line(l, at)
    if l:sub(1, 2) == '==' then
      local name = l:match('^==+%s*(' .. NAME .. ')')
      if name then
        if cur then idx[cur][2] = at - idx[cur][1] end
        if idx[name] then cur = nil; return end           -- a second passage of a name is skipped
        order[#order + 1] = name
        idx[name] = { at, 0 }
        cur = name
        return
      end
    end
    if #order == 0 then head[#head + 1] = l end
  end
  local off, carry, carry_off = 0, '', 0
  while off < src.size do
    local chunk = src.read(off, 65536)
    if type(chunk) ~= 'string' or chunk == '' then break end
    local buf, pos = carry .. chunk, 1
    while true do
      local nl = buf:find('\n', pos, true)
      if not nl then break end
      line((buf:sub(pos, nl - 1):gsub('\r$', '')), carry_off + pos - 1)
      pos = nl + 1
    end
    carry_off = carry_off + pos - 1
    carry = buf:sub(pos)
    off = off + #chunk
  end
  if carry ~= '' then line((carry:gsub('\r$', '')), carry_off) end
  if cur then idx[cur][2] = src.size - idx[cur][1] end
  if #order == 0 then return nil, 'no passages (lines starting with "==")' end
  parse_header(story, head)
  story.head = table.concat(head, '\n')
  return S.finish(story)
end

function S.finish(story)
  local m = story.meta
  story.title = (m.title and m.title ~= '') and m.title or nil
  story.start = (m.start and story.idx[m.start]) and m.start or story.order[1]
  return story
end

-- the index as text: the header, then "name off len" per passage
function S.index_string(story)
  local out = { 'size ' .. story.src.size, story.head, '\1' }
  for _, n in ipairs(story.order) do
    local e = story.idx[n]
    out[#out + 1] = n .. ' ' .. e[1] .. ' ' .. e[2]
  end
  return table.concat(out, '\n')
end

function S.from_index(src, s)
  if type(s) ~= 'string' then return nil end
  local size, head, rest = s:match('^size (%d+)\n(.-)\n\1\n(.*)$')
  if not size or tonumber(size) ~= src.size then return nil end
  local story = new_story(src)
  for n, a, b in rest:gmatch('(%S+) (%d+) (%d+)') do
    story.order[#story.order + 1] = n
    story.idx[n] = { tonumber(a), tonumber(b) }
  end
  if #story.order == 0 then return nil end
  local lines = {}
  for l in (head .. '\n'):gmatch('([^\n]*)\n') do lines[#lines + 1] = l end
  parse_header(story, lines)
  story.head = head
  return S.finish(story)
end

------------------------------------------------------------------ expressions

local function tokens(s)
  local t, i, n = {}, 1, #s
  while i <= n do
    local c = s:sub(i, i)
    if c:match('%s') then i = i + 1
    elseif c:match('%d') then
      local num = s:match('^%d+%.?%d*', i)
      t[#t + 1] = { 'n', math.tointeger(tonumber(num)) or tonumber(num) }; i = i + #num
    elseif c:match('[%a_]') then
      local w = s:match('^[%w_%.]+', i)
      i = i + #w
      if w == 'true' or w == 'false' then t[#t + 1] = { 'n', w == 'true' }
      elseif w == 'and' or w == 'or' or w == 'not' then t[#t + 1] = { w }
      else t[#t + 1] = { 'id', w } end
    elseif c == '"' or c == "'" then
      local j, buf = i + 1, {}
      while j <= n and s:sub(j, j) ~= c do
        if s:sub(j, j) == '\\' then j = j + 1 end
        buf[#buf + 1] = s:sub(j, j); j = j + 1
      end
      t[#t + 1] = { 'n', table.concat(buf) }; i = j + 1
    else
      local two = s:sub(i, i + 1)
      if two == '==' or two == '!=' or two == '<=' or two == '>=' or two == '&&' or two == '||'
         or two == '+=' or two == '-=' then
        t[#t + 1] = { two == '&&' and 'and' or two == '||' and 'or' or two }; i = i + 2
      else
        t[#t + 1] = { c == '!' and 'not' or c }; i = i + 1
      end
    end
  end
  return t
end

local function truthy(v) return not (v == nil or v == false or v == 0 or v == '') end
S.truthy = truthy

local function num(v)
  if type(v) == 'number' then return v end
  if v == true then return 1 end
  return tonumber(v) or 0
end

local function show(v)
  if type(v) == 'number' then
    local i = math.tointeger(v)
    if i then return tostring(i) end
    return (string.format('%.2f', v):gsub('0+$', ''):gsub('%.$', ''))
  end
  if v == nil then return '' end
  return tostring(v)
end
S.show = show

-- a tree: { op, a, b } / { 'n', value } / { 'id', name } / { 'call', name, args }
local function parse_expr(t)
  local p = 1
  local function peek() return t[p] and t[p][1] end
  local expr
  local function primary()
    local tk = t[p]
    if not tk then return { 'n', 0 } end
    p = p + 1
    if tk[1] == 'n' then return tk end
    if tk[1] == '(' then
      local e = expr()
      if peek() == ')' then p = p + 1 end
      return e
    end
    if tk[1] == 'id' then
      if peek() == '(' then
        p = p + 1
        local args = {}
        while peek() and peek() ~= ')' do
          args[#args + 1] = expr()
          if peek() == ',' then p = p + 1 end
        end
        p = p + 1
        return { 'call', tk[2], args }
      end
      return tk
    end
    if tk[1] == '-' then return { 'neg', primary() } end
    if tk[1] == 'not' then return { 'not', primary() } end
    return { 'n', 0 }
  end
  local function binary(next_level, ops)
    return function()
      local a = next_level()
      while ops[peek() or ''] do
        local op = peek(); p = p + 1
        a = { op, a, next_level() }
      end
      return a
    end
  end
  local mul = binary(primary, { ['*'] = true, ['/'] = true, ['%'] = true })
  local add = binary(mul, { ['+'] = true, ['-'] = true })
  local cmp = binary(add, { ['=='] = true, ['!='] = true, ['<'] = true, ['>'] = true, ['<='] = true, ['>='] = true })
  local function unary_not()
    if peek() == 'not' then p = p + 1; return { 'not', unary_not() } end
    return cmp()
  end
  local conj = binary(unary_not, { ['and'] = true })
  expr = binary(conj, { ['or'] = true })
  return expr()
end

local ast_cache, ast_count = {}, 0
local function compile(s)
  local a = ast_cache[s]
  if a then return a end
  if ast_count > 400 then ast_cache, ast_count = {}, 0 end
  a = parse_expr(tokens(s))
  ast_cache[s] = a; ast_count = ast_count + 1
  return a
end

local function lookup(story, st, name)
  local v = st.vars[name]
  if v ~= nil then return v end
  if story.idx[name] then return st.visits[name] or 0 end
  return 0
end

local function idiv(a, b)
  if b == 0 then return 0 end
  if math.type(a) == 'integer' and math.type(b) == 'integer' then
    local q = a // b
    if a % b ~= 0 and (a < 0) ~= (b < 0) then q = q + 1 end
    return q
  end
  return a / b
end

local function eval(story, st, e)
  local op = e[1]
  if op == 'n' then return e[2] end
  if op == 'id' then return lookup(story, st, e[2]) end
  if op == 'not' then return not truthy(eval(story, st, e[2])) end
  if op == 'neg' then return -num(eval(story, st, e[2])) end
  if op == 'and' then return truthy(eval(story, st, e[2])) and truthy(eval(story, st, e[3])) end
  if op == 'or' then return truthy(eval(story, st, e[2])) or truthy(eval(story, st, e[3])) end
  if op == 'call' then
    local a = {}
    for k, x in ipairs(e[3]) do a[k] = num(eval(story, st, x)) end
    local f = e[2]
    if f == 'random' then
      local lo, hi = math.floor(a[1] or 1), math.floor(a[2] or a[1] or 1)
      if hi < lo then lo, hi = hi, lo end
      return math.random(lo, hi)
    elseif f == 'min' then return math.min(a[1] or 0, a[2] or a[1] or 0)
    elseif f == 'max' then return math.max(a[1] or 0, a[2] or a[1] or 0)
    elseif f == 'abs' then return math.abs(a[1] or 0)
    elseif f == 'visited' or f == 'visits' then
      return e[3][1] and e[3][1][1] == 'id' and (st.visits[e[3][1][2]] or 0) or 0
    end
    return 0
  end
  local a, b = eval(story, st, e[2]), eval(story, st, e[3])
  if op == '==' then
    if type(a) == 'boolean' or type(b) == 'boolean' then return truthy(a) == truthy(b) end
    return a == b
  end
  if op == '!=' then
    if type(a) == 'boolean' or type(b) == 'boolean' then return truthy(a) ~= truthy(b) end
    return a ~= b
  end
  if op == '+' then
    if type(a) == 'string' or type(b) == 'string' then return show(a) .. show(b) end
    return num(a) + num(b)
  end
  if type(a) == 'string' and type(b) == 'string' then
    if op == '<' then return a < b elseif op == '>' then return a > b
    elseif op == '<=' then return a <= b elseif op == '>=' then return a >= b end
  end
  a, b = num(a), num(b)
  if op == '-' then return a - b
  elseif op == '*' then return a * b
  elseif op == '/' then return idiv(a, b)
  elseif op == '%' then return b == 0 and 0 or math.fmod(a, b)
  elseif op == '<' then return a < b
  elseif op == '>' then return a > b
  elseif op == '<=' then return a <= b
  elseif op == '>=' then return a >= b end
  return 0
end

function S.eval(story, st, s) return eval(story, st, compile(s)) end

-- "x = 1; y += 2"
local function run(story, st, stmts)
  for part in (stmts .. ';'):gmatch('([^;]*);') do
    local n, op, rhs = part:match('^%s*(' .. NAME .. ')%s*([%+%-]?=)%s*(.-)%s*$')
    if n and rhs ~= '' then
      local v = S.eval(story, st, rhs)
      if op == '+=' then
        local old = lookup(story, st, n)
        v = (type(old) == 'string' or type(v) == 'string') and (show(old) .. show(v)) or num(old) + num(v)
      elseif op == '-=' then v = num(lookup(story, st, n)) - num(v) end
      st.vars[n] = v
    end
  end
end

------------------------------------------------------------------ text

-- the end of a {...} starting at i (the index of "}"), skipping escapes, quotes and nested braces
local function close_brace(s, i)
  local depth, q = 0, nil
  while i <= #s do
    local c = s:sub(i, i)
    if c == '\\' then i = i + 1
    elseif q then if c == q then q = nil end
    elseif c == '{' then depth = depth + 1
    elseif c == '}' then depth = depth - 1; if depth == 0 then return i end
    end
    i = i + 1
  end
  return nil
end

-- the top-level positions of ch in s (not inside braces, quotes, or after "\")
local function split_top(s, ch, max)
  local parts, depth, start, i, q = {}, 0, 1, 1, nil
  while i <= #s do
    local c = s:sub(i, i)
    if c == '\\' then i = i + 1
    elseif q then if c == q then q = nil end
    elseif (c == '"') and ch == ':' and depth == 0 then q = c
    elseif c == '{' then depth = depth + 1
    elseif c == '}' then depth = depth - 1
    elseif c == ch and depth == 0 and (not max or #parts < max - 1) then
      parts[#parts + 1] = s:sub(start, i - 1); start = i + 1
    end
    i = i + 1
  end
  parts[#parts + 1] = s:sub(start)
  return parts
end

local render
local function inner(story, st, body)
  local mode = body:sub(1, 1)
  if mode == '&' or mode == '~' then
    local items = split_top(body:sub(2), '|')
    local v = st.visits[st.at] or 1
    if mode == '&' then return render(story, st, items[(v - 1) % #items + 1]) end
    return render(story, st, items[math.random(1, #items)])
  end
  local cond = split_top(body, ':', 2)
  if #cond == 2 then
    local branches = split_top(cond[2], '|', 2)
    if truthy(S.eval(story, st, cond[1])) then return render(story, st, (branches[1]:gsub('^ ', ''))) end
    return render(story, st, branches[2] or '')
  end
  local items = split_top(body, '|')
  if #items > 1 then
    local v = st.visits[st.at] or 1
    return render(story, st, items[math.min(v, #items)])
  end
  return show(S.eval(story, st, body))
end

render = function(story, st, s)
  if not s:find('[{\\]') then return s end
  local out, i = {}, 1
  while i <= #s do
    local c = s:sub(i, i)
    if c == '\\' then
      out[#out + 1] = s:sub(i + 1, i + 1); i = i + 2
    elseif c == '{' then
      local j = close_brace(s, i)
      if not j then out[#out + 1] = s:sub(i); break end
      out[#out + 1] = inner(story, st, s:sub(i + 1, j - 1))
      i = j + 1
    else
      local j = s:find('[{\\]', i) or (#s + 1)
      out[#out + 1] = s:sub(i, j - 1); i = j
    end
  end
  return table.concat(out)
end
S.render = render

------------------------------------------------------------------ passages

-- "{cond} rest" -> cond, rest
local function lead_cond(s)
  if s:sub(1, 1) ~= '{' then return nil, s end
  local j = close_brace(s, 1)
  if not j then return nil, s end
  return s:sub(2, j - 1), (s:sub(j + 1):gsub('^%s+', ''))
end

-- the first " ~" not after "\"
local function split_effects(s)
  local i = 1
  while true do
    local j = s:find('~', i, true)
    if not j then return s, nil end
    if s:sub(j - 1, j - 1) ~= '\\' and (j == 1 or s:sub(j - 1, j - 1):match('%s')) then
      return (s:sub(1, j - 1):gsub('%s+$', '')), s:sub(j + 1)
    end
    i = j + 1
  end
end

local function parse_passage(text)
  local P = { items = {}, choices = {}, effects = {}, diverts = {} }
  local first = true
  for raw in (text .. '\n'):gmatch('([^\n]*)\n') do
    local l = raw:gsub('\r$', '')
    if first then first = false                              -- the "== name" line
    else
      local t = l:match('^%s*(.-)%s*$')
      local c1, c2 = t:sub(1, 1), t:sub(1, 2)
      if c2 == '//' then
      elseif c1 == '*' then
        local rest = t:sub(2):gsub('^%s+', '')
        local once = false
        if rest:sub(1, 6) == '[once]' then once = true; rest = rest:sub(7):gsub('^%s+', '') end
        local cond
        cond, rest = lead_cond(rest)
        local body, target = rest:match('^(.-)%s*%->%s*(' .. NAME .. ')%s*$')
        if not body then body = rest end
        local label, eff = split_effects(body)
        P.choices[#P.choices + 1] = { label = label, target = target, cond = cond, once = once, eff = eff }
      elseif c2 == '->' then
        local cond, rest = lead_cond((t:sub(3):gsub('^%s+', '')))
        local target = rest:match('^(' .. NAME .. ')')
        if target then P.diverts[#P.diverts + 1] = { target = target, cond = cond } end
      elseif c1 == '~' then
        local cond, rest = lead_cond((t:sub(2):gsub('^%s+', '')))
        P.effects[#P.effects + 1] = { cond = cond, stmts = rest }
      else
        if t:match('^\\[%*%-~=]') then t = t:sub(2) end
        P.items[#P.items + 1] = t
      end
    end
  end
  return P
end

function S.passage(story, name)
  local P = story.cache[name]
  if P then return P end
  local e = story.idx[name]
  if not e then return nil end
  local parts, off, left = {}, e[1], e[2]
  while left > 0 do
    local piece = story.src.read(off, math.min(left, 65536))
    if type(piece) ~= 'string' or piece == '' then break end
    parts[#parts + 1] = piece
    off, left = off + #piece, left - #piece
  end
  P = parse_passage(table.concat(parts))
  local n = 0
  for _ in pairs(story.cache) do n = n + 1 end
  if n >= 12 then story.cache = {} end
  story.cache[name] = P
  return P
end

------------------------------------------------------------------ playing

function S.new_state(story)
  local v = {}
  for k, x in pairs(story.vars) do v[k] = x end
  return { at = nil, vars = v, visits = {}, once = {}, ended = false }
end

local function is_end(n) return n == nil or n == 'END' or n == 'DONE' end

function S.enter(story, st, name)
  for _ = 1, 20 do
    if is_end(name) then
      st.ended = true
      return { name = 'END', lines = {}, choices = {}, ending = true }
    end
    local P = S.passage(story, name)
    if not P then return nil, 'no passage "' .. tostring(name) .. '"' end
    st.at, st.ended = name, false
    st.visits[name] = (st.visits[name] or 0) + 1
    for _, e in ipairs(P.effects) do
      if not e.cond or truthy(S.eval(story, st, e.cond)) then run(story, st, e.stmts) end
    end
    local lines, any = {}, false
    for _, it in ipairs(P.items) do
      if it == '' then
        if #lines > 0 and lines[#lines] ~= '' then lines[#lines + 1] = '' end
      else
        local s = render(story, st, it)
        if s:match('%S') then lines[#lines + 1] = s; any = true end
      end
    end
    while lines[#lines] == '' do lines[#lines] = nil end
    local choices = {}
    for ci, c in ipairs(P.choices) do
      if (not c.once or not st.once[name .. '#' .. ci]) and (not c.cond or truthy(S.eval(story, st, c.cond))) then
        choices[#choices + 1] = { label = render(story, st, c.label), k = ci, target = c.target }
      end
    end
    local cont
    if #choices == 0 then
      for _, d in ipairs(P.diverts) do
        if not d.cond or truthy(S.eval(story, st, d.cond)) then cont = d.target; break end
      end
    end
    if cont and not any then
      name = cont
    else
      local ending = #choices == 0 and (cont == nil or is_end(cont))
      if ending then st.ended = true end
      return { name = name, lines = lines, choices = choices, cont = (not is_end(cont)) and cont or nil, ending = ending }
    end
  end
  return nil, 'too many passages in a row without text'
end

function S.choose(story, st, view, i)
  local c = view.choices[i]
  if not c then return view.cont end
  local P = S.passage(story, view.name)
  local ch = P.choices[c.k]
  if ch.once then st.once[view.name .. '#' .. c.k] = true end
  if ch.eff then run(story, st, ch.eff) end
  return ch.target or 'END'
end

------------------------------------------------------------------ saving

local function esc(s) return (s:gsub('\\', '\\\\'):gsub('\n', '\\n')) end
local function unesc(s) return (s:gsub('\\(.)', function(c) return c == 'n' and '\n' or c end)) end

function S.save(st)
  local out = { 'at=' .. (st.ended and 'END' or (st.at or '')) }
  for k, v in pairs(st.vars) do
    local t = type(v) == 'number' and 'n' or type(v) == 'boolean' and 'b' or 's'
    out[#out + 1] = 'v:' .. k .. '=' .. t .. esc(show(v))
  end
  for k, v in pairs(st.visits) do out[#out + 1] = 'n:' .. k .. '=' .. v end
  for k in pairs(st.once) do out[#out + 1] = 'o:' .. k .. '=1' end
  return table.concat(out, '\n') .. '\n'
end

function S.load(story, s)
  local st = S.new_state(story)
  for line in (s or ''):gmatch('[^\n]+') do
    local kind, k, v = line:match('^(%a):([^=]+)=(.*)$')
    if kind == 'v' then
      local t, x = v:sub(1, 1), unesc(v:sub(2))
      st.vars[k] = t == 'n' and (math.tointeger(tonumber(x)) or tonumber(x) or 0) or t == 'b' and x == 'true' or x
    elseif kind == 'n' then st.visits[k] = tonumber(v) or 0
    elseif kind == 'o' then st.once[k] = true
    else
      local at = line:match('^at=(.*)$')
      if at then st.at = at ~= '' and at or nil end
    end
  end
  if st.at == 'END' then st.at, st.ended = nil, true end
  if st.at and not story.idx[st.at] then st.at = nil end
  return st
end

return S
