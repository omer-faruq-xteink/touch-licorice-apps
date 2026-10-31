-- zmachine.lua: a Z-machine interpreter (versions 3, 4, 5, 7 and 8) for text adventures, after the
-- Z-Machine Standards Document 1.1. No screen here: the app gives a small io table and reads
-- what the machine printed.
--
--   local m = Z.new(story)              story: the whole story file as a string
--   m:run(limit) -> 'input' | 'char' | 'more' | 'quit' | 'error', msg
--                                       runs at most `limit` instructions; 'more' when it ran out
--   m:send_line(text), m:send_char(c)   answers a read; then m:run again
--   m.lower                             text printed to the main window since take_output()
--   m:take_output() -> string           and clears it
--   m.upper                             the upper window's lines (the status line), m.upper_h
--   m:status() -> left, right           v3 status line: location, "score/moves" or the time
--   m:snapshot() / m:restore(s)         the whole state as a string (autosave, save / restore)
--   m.on_save(state) -> ok, m.on_restore() -> state or nil   the game's own save and restore
--
-- Memory: the story stays one Lua string (read-only); the dynamic part (writable, up to 64 KB) is
-- copied into integers of 4 bytes each, a quarter of the table a byte per entry would take: the
-- reader has about 2 MB of heap.

local Z = {}
Z.__index = Z

local UNI = { 0xe4, 0xf6, 0xfc, 0xc4, 0xd6, 0xdc, 0xdf, 0xbb, 0xab, 0xeb, 0xef, 0xff, 0xcb, 0xcf, 0xe1, 0xe9,
  0xed, 0xf3, 0xfa, 0xfd, 0xc1, 0xc9, 0xcd, 0xd3, 0xda, 0xdd, 0xe0, 0xe8, 0xec, 0xf2, 0xf9, 0xc0, 0xc8, 0xcc,
  0xd2, 0xd9, 0xe2, 0xea, 0xee, 0xf4, 0xfb, 0xc2, 0xca, 0xce, 0xd4, 0xdb, 0xe5, 0xc5, 0xf8, 0xd8, 0xe3, 0xf1,
  0xf5, 0xc3, 0xd1, 0xd5, 0xe6, 0xc6, 0xe7, 0xc7, 0xfe, 0xf0, 0xde, 0xd0, 0xa3, 0x153, 0x152, 0xa1, 0xbf }

local A0 = 'abcdefghijklmnopqrstuvwxyz'
local A1 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
local A2 = ' \n0123456789.,!?_#\'"/\\-:()'

function Z.new(story)
  local m = setmetatable({}, Z)
  m.S = story
  local v = story:byte(1)
  if v ~= 3 and v ~= 4 and v ~= 5 and v ~= 7 and v ~= 8 then error('story version ' .. tostring(v) .. ' is not supported') end
  m.v = v
  m:reset()
  return m
end

function Z:reset()
  local S = self.S
  local function w(a) return S:byte(a + 1) * 256 + S:byte(a + 2) end
  self.static_base = w(0x0E)
  local dyn = {}
  local n = self.static_base
  for i = 0, (n + 3) // 4 - 1 do
    local a = i * 4
    dyn[i + 1] = ((S:byte(a + 1) or 0) << 24) | ((S:byte(a + 2) or 0) << 16) | ((S:byte(a + 3) or 0) << 8) | (S:byte(a + 4) or 0)
  end
  self.dyn = dyn
  self.pc = w(0x06)
  self.stack, self.sp = {}, 0
  self.frames = {}
  self.lower, self.out3 = {}, {}
  self.upper, self.upper_h, self.window, self.cur_row, self.cur_col = {}, 0, 0, 1, 1
  self.cols, self.rows = 40, 25
  self.rng = nil
  self.done = false
  self:set_header()
end

------------------------------------------------------------------ memory

function Z:rb(a)
  if a < self.static_base then
    local x = self.dyn[(a >> 2) + 1]
    return (x >> (24 - (a & 3) * 8)) & 0xFF
  end
  return self.S:byte(a + 1) or 0
end
function Z:rw(a) return (self:rb(a) << 8) | self:rb(a + 1) end
function Z:wb(a, val)
  if a >= self.static_base then error(string.format('write to static memory at %x', a)) end
  local i = (a >> 2) + 1
  local sh = 24 - (a & 3) * 8
  self.dyn[i] = (self.dyn[i] & ~(0xFF << sh)) | ((val & 0xFF) << sh)
end
function Z:ww(a, val) self:wb(a, val >> 8); self:wb(a + 1, val) end

local function signed(x) x = x & 0xFFFF; if x >= 0x8000 then return x - 0x10000 end return x end

function Z:set_header()
  local v = self.v
  local f1 = self:rb(1)
  if v <= 3 then
    f1 = (f1 & ~0x70) | 0x20                         -- status line available, split screen available
  else
    f1 = f1 & ~0xFF                                  -- no colours, styles, timed input
  end
  self:wb(1, f1)
  self:wb(0x10, self:rb(0x10) & ~0x01)              -- flags 2: no transcript
  if v >= 4 then
    self:wb(0x1E, 6); self:wb(0x1F, string.byte('A'))
    self:wb(0x20, self.rows); self:wb(0x21, self.cols)
  end
  if v >= 5 then
    self:ww(0x22, self.cols); self:ww(0x24, self.rows)
    self:wb(0x26, 1); self:wb(0x27, 1)
    self:wb(0x2C, 9); self:wb(0x2D, 2)                -- background white, text black
  end
  self:wb(0x32, 1); self:wb(0x33, 1)
end

function Z:unpack(p)
  if self.v <= 3 then return 2 * p elseif self.v <= 5 then return 4 * p end
  return 8 * p
end

------------------------------------------------------------------ text

local function utf8_of(z)
  if z >= 155 and z <= 223 then return utf8.char(UNI[z - 154]) end
  if z == 13 then return '\n' end
  if z >= 32 and z <= 126 then return string.char(z) end
  return ''
end

function Z:alphabet(n, i)                            -- the ZSCII code of z-char i (6..31) in alphabet n
  local t = self.v >= 5 and self:rw(0x34) or 0
  if t ~= 0 then return self:rb(t + n * 26 + i - 6) end
  local s = n == 0 and A0 or (n == 1 and A1 or A2)
  if n == 2 and i == 7 then return 13 end
  return s:byte(i - 5)
end

-- the z-string at a; returns the text and the address after it
function Z:decode(a, no_abbrev)
  local out, alpha, shift_once = {}, 0, nil
  local abbrev, zh, zl = nil, nil, nil
  while true do
    local word = self:rw(a)
    a = a + 2
    for k = 2, 0, -1 do
      local c = (word >> (k * 5)) & 31
      local cur = shift_once or alpha
      shift_once = nil
      if zh == -1 then zh = c
      elseif zh then
        out[#out + 1] = utf8_of((zh << 5) | c); zh = nil
      elseif abbrev then
        local idx = 32 * (abbrev - 1) + c
        local addr = self:rw(self:rw(0x18) + 2 * idx) * 2
        out[#out + 1] = (self:decode(addr, true))
        abbrev = nil
      elseif c == 0 then out[#out + 1] = ' '
      elseif c >= 1 and c <= 3 then
        if not no_abbrev then abbrev = c end
      elseif c == 4 then shift_once = 1
      elseif c == 5 then shift_once = 2
      elseif cur == 2 and c == 6 then zh = -1
      else
        out[#out + 1] = utf8_of(self:alphabet(cur, c))
      end
    end
    if word & 0x8000 ~= 0 then break end
  end
  return table.concat(out), a
end

-- the dictionary form of a word: 6 (v3) or 9 z-chars, packed into 2 or 3 words
function Z:encode(word)
  local n = self.v <= 3 and 6 or 9
  local zs = {}
  for i = 1, #word do
    local ch = word:byte(i)
    local found = false
    for alpha = 0, 2 do
      for zc = 6, 31 do
        if not (alpha == 2 and (zc == 6 or zc == 7)) and self:alphabet(alpha, zc) == ch then
          if alpha > 0 then zs[#zs + 1] = alpha + 3 end
          zs[#zs + 1] = zc; found = true; break
        end
      end
      if found then break end
    end
    if not found then
      zs[#zs + 1] = 5; zs[#zs + 1] = 6; zs[#zs + 1] = (ch >> 5) & 31; zs[#zs + 1] = ch & 31
    end
    if #zs >= n then break end
  end
  while #zs < n do zs[#zs + 1] = 5 end
  local words = {}
  for i = 1, n, 3 do
    words[#words + 1] = (zs[i] << 10) | (zs[i + 1] << 5) | zs[i + 2]
  end
  words[#words] = words[#words] | 0x8000
  return words
end

------------------------------------------------------------------ output

function Z:print(s)
  if s == '' then return end
  if #self.out3 > 0 then
    local t = self.out3[#self.out3]
    for _p, cp in utf8.codes(s) do
      local z = cp
      if cp == 10 then z = 13
      elseif cp > 126 then
        z = 63
        for k, u in ipairs(UNI) do if u == cp then z = 154 + k; break end end
      end
      self:wb(t.addr + 2 + t.n, z); t.n = t.n + 1
    end
    return
  end
  if self.window == 1 then
    for _p, cp in utf8.codes(s) do
      if cp == 10 then self.cur_row, self.cur_col = self.cur_row + 1, 1
      else
        local row = self.upper[self.cur_row]
        if row and self.cur_col <= self.cols then
          local chars = row
          chars[self.cur_col] = utf8.char(cp)
        end
        self.cur_col = self.cur_col + 1
      end
    end
    return
  end
  self.lower[#self.lower + 1] = s
end

function Z:take_output()
  local s = table.concat(self.lower)
  self.lower = {}
  return s
end

function Z:upper_lines()
  local out = {}
  for r = 1, self.upper_h do
    local row = self.upper[r]
    out[r] = row and (table.concat(row):gsub('%s+$', '')) or ''
  end
  return out
end

function Z:split(n)
  self.upper_h = n
  for r = 1, n do
    if not self.upper[r] then
      local row = {}
      for c = 1, self.cols do row[c] = ' ' end
      self.upper[r] = row
    end
  end
  if self.v == 3 then for r = 1, n do for c = 1, self.cols do self.upper[r][c] = ' ' end end end
end

function Z:erase_upper()
  for r = 1, #self.upper do for c = 1, self.cols do self.upper[r][c] = ' ' end end
end

-- objects
function Z:obj_addr(o)
  if self.v <= 3 then return self:rw(0x0A) + 62 + (o - 1) * 9 end
  return self:rw(0x0A) + 126 + (o - 1) * 14
end
function Z:parent(o) local a = self:obj_addr(o); if self.v <= 3 then return self:rb(a + 4) end return self:rw(a + 6) end
function Z:sibling(o) local a = self:obj_addr(o); if self.v <= 3 then return self:rb(a + 5) end return self:rw(a + 8) end
function Z:child(o) local a = self:obj_addr(o); if self.v <= 3 then return self:rb(a + 6) end return self:rw(a + 10) end
function Z:set_link(o, which, val)
  local a = self:obj_addr(o)
  if self.v <= 3 then self:wb(a + 3 + which, val) else self:ww(a + 4 + which * 2, val) end
end
function Z:props(o) local a = self:obj_addr(o); return self:rw(a + (self.v <= 3 and 7 or 12)) end

function Z:obj_name(o)
  if o == 0 then return '' end
  local p = self:props(o)
  if self:rb(p) == 0 then return '' end
  return (self:decode(p + 1))
end

function Z:attr(o, n)
  local a = self:obj_addr(o) + (n >> 3)
  return self:rb(a) & (0x80 >> (n & 7)) ~= 0
end
function Z:set_attr(o, n, on)
  local a = self:obj_addr(o) + (n >> 3)
  local b = self:rb(a)
  if on then b = b | (0x80 >> (n & 7)) else b = b & ~(0x80 >> (n & 7)) end
  self:wb(a, b)
end

function Z:remove(o)
  local p = self:parent(o)
  if p == 0 then return end
  local first = self:child(p)
  if first == o then
    self:set_link(p, 3, self:sibling(o))
  else
    local x = first
    while x ~= 0 do
      local s = self:sibling(x)
      if s == o then self:set_link(x, 2, self:sibling(o)); break end
      x = s
    end
  end
  self:set_link(o, 1, 0); self:set_link(o, 2, 0)
end

function Z:insert(o, d)
  self:remove(o)
  self:set_link(o, 2, self:child(d))
  self:set_link(d, 3, o)
  self:set_link(o, 1, d)
end

-- the first property entry of o: address of its size byte
function Z:first_prop(o)
  local p = self:props(o)
  return p + 1 + 2 * self:rb(p)
end
-- number, data address, length of the property entry at a (number 0: the end)
function Z:prop_at(a)
  local b = self:rb(a)
  if self.v <= 3 then
    if b == 0 then return 0 end
    return b & 31, a + 1, (b >> 5) + 1
  end
  if b & 0x80 ~= 0 then
    local len = self:rb(a + 1) & 63
    if len == 0 then len = 64 end
    return b & 63, a + 2, len
  end
  if b == 0 then return 0 end
  return b & 63, a + 1, (b & 0x40 ~= 0) and 2 or 1
end
function Z:find_prop(o, n)
  local a = self:first_prop(o)
  while true do
    local num, data, len = self:prop_at(a)
    if num == 0 then return nil end
    if num == n then return data, len end
    if num < n then return nil end
    a = data + len
  end
end
function Z:prop_len(data)
  if data == 0 then return 0 end
  local b = self:rb(data - 1)
  if self.v <= 3 then return (b >> 5) + 1 end
  if b & 0x80 ~= 0 then local l = b & 63; return l == 0 and 64 or l end
  return (b & 0x40 ~= 0) and 2 or 1
end

------------------------------------------------------------------ variables and calls

function Z:push(x) self.sp = self.sp + 1; self.stack[self.sp] = x & 0xFFFF end
function Z:pop()
  local f = self.frames[#self.frames]
  if self.sp <= (f and f.base or 0) then error('stack underflow') end
  local x = self.stack[self.sp]; self.sp = self.sp - 1; return x
end

function Z:getvar(n, peek)
  if n == 0 then
    if peek then return self.stack[self.sp] end
    return self:pop()
  elseif n < 16 then
    return self.frames[#self.frames].locals[n] or 0
  end
  return self:rw(self:rw(0x0C) + 2 * (n - 16))
end
function Z:setvar(n, x, in_place)
  x = x & 0xFFFF
  if n == 0 then
    if in_place then self.stack[self.sp] = x else self:push(x) end
  elseif n < 16 then
    self.frames[#self.frames].locals[n] = x
  else
    self:ww(self:rw(0x0C) + 2 * (n - 16), x)
  end
end

function Z:call(addr, args, store)          -- store: a variable number, or nil to throw the result away
  if addr == 0 then
    if store then self:setvar(store, 0) end
    return
  end
  local a = self:unpack(addr)
  local nl = self:rb(a)
  a = a + 1
  local locals = {}
  for i = 1, nl do
    if self.v <= 4 then locals[i] = self:rw(a); a = a + 2 else locals[i] = 0 end
  end
  for i = 1, math.min(#args, nl) do locals[i] = args[i] end
  self.frames[#self.frames + 1] = { ret = self.pc, store = store, locals = locals, nargs = #args, base = self.sp }
  self.pc = a
end

function Z:ret(x)
  local f = table.remove(self.frames)
  self.sp = f.base
  self.pc = f.ret
  if f.store then self:setvar(f.store, x) end
end

function Z:branch(cond)
  local b = self:rb(self.pc)
  self.pc = self.pc + 1
  local on = b & 0x80 ~= 0
  local off
  if b & 0x40 ~= 0 then off = b & 63
  else
    off = ((b & 63) << 8) | self:rb(self.pc)
    self.pc = self.pc + 1
    if off >= 0x2000 then off = off - 0x4000 end
  end
  if cond == on then
    if off == 0 then self:ret(0) elseif off == 1 then self:ret(1) else self.pc = self.pc + off - 2 end
  end
end

function Z:store(x)
  local n = self:rb(self.pc)
  self.pc = self.pc + 1
  self:setvar(n, x)
end

------------------------------------------------------------------ input

-- the words of a line, as the dictionary splits them: { {text, start} }
function Z:split_words(text, dict)
  local nsep = self:rb(dict)
  local seps = {}
  for i = 1, nsep do seps[self:rb(dict + i)] = true end
  local out, i = {}, 1
  while i <= #text do
    local ch = text:byte(i)
    if ch == 32 then i = i + 1
    elseif seps[ch] then out[#out + 1] = { text:sub(i, i), i }; i = i + 1
    else
      local j = i
      while j <= #text and text:byte(j) ~= 32 and not seps[text:byte(j)] do j = j + 1 end
      out[#out + 1] = { text:sub(i, j - 1), i }
      i = j
    end
  end
  return out
end

function Z:lookup(word, dict)
  local nsep = self:rb(dict)
  local base = dict + 1 + nsep
  local elen = self:rb(base)
  local count = signed(self:rw(base + 1))
  local first = base + 3
  local enc = self:encode(word)
  local function cmp(e)
    for k = 1, #enc do
      local w = self:rw(e + 2 * (k - 1))
      if w ~= enc[k] then return w < enc[k] and -1 or 1 end
    end
    return 0
  end
  if count < 0 then
    for i = 0, -count - 1 do if cmp(first + i * elen) == 0 then return first + i * elen end end
    return 0
  end
  local lo, hi = 0, count - 1
  while lo <= hi do
    local mid = (lo + hi) // 2
    local c = cmp(first + mid * elen)
    if c == 0 then return first + mid * elen end
    if c < 0 then lo = mid + 1 else hi = mid - 1 end
  end
  return 0
end

function Z:tokenise(text_addr, parse, dict, flag)
  dict = (dict and dict ~= 0) and dict or self:rw(0x08)
  local text, off
  if self.v <= 4 then
    local t = {}
    local i = 1
    while true do local c = self:rb(text_addr + i); if c == 0 then break end; t[#t + 1] = string.char(c); i = i + 1 end
    text, off = table.concat(t), 0
  else
    local n = self:rb(text_addr + 1)
    local t = {}
    for i = 0, n - 1 do t[#t + 1] = string.char(self:rb(text_addr + 2 + i)) end
    text, off = table.concat(t), 1
  end
  local words = self:split_words(text, dict)
  local max = self:rb(parse)
  local count = math.min(#words, max)
  self:wb(parse + 1, count)
  for k = 1, count do
    local w = words[k]
    local d = self:lookup(w[1], dict)
    local e = parse + 2 + (k - 1) * 4
    if not (flag and flag ~= 0 and d == 0) then
      self:ww(e, d)
      self:wb(e + 2, #w[1])
      self:wb(e + 3, w[2] + off)
    end
  end
end

-- the line typed, into the text buffer of the pending read, then tokenised
function Z:send_line(line)
  local r = self.reading
  if not r or r.char then return end
  self.reading = nil
  line = line:lower():gsub('[^\32-\126]', ''):gsub('^%s+', ''):gsub('%s+$', '')
  local maxlen = self:rb(r.text)
  if self.v <= 4 then
    maxlen = maxlen - 1
    line = line:sub(1, math.max(0, maxlen))
    for i = 1, #line do self:wb(r.text + i, line:byte(i)) end
    self:wb(r.text + #line + 1, 0)
  else
    line = line:sub(1, maxlen)
    for i = 1, #line do self:wb(r.text + 1 + i, line:byte(i)) end
    self:wb(r.text + 1, #line)
  end
  self.lower[#self.lower + 1] = line .. '\n'
  if r.parse ~= 0 then self:tokenise(r.text, r.parse) end
  if self.v >= 5 then self:store(13) end
end

function Z:send_char(c)
  local r = self.reading
  if not r or not r.char then return end
  self.reading = nil
  self:store(c)
end

------------------------------------------------------------------ status line (v3)

function Z:status()
  local g = self:rw(0x0C)
  local loc = self:obj_name(self:rw(g))
  local a, b = signed(self:rw(g + 2)), self:rw(g + 4)
  if self:rb(1) & 0x02 ~= 0 then
    return loc, string.format('%d:%02d', a, b)
  end
  return loc, 'Score: ' .. a .. '  Moves: ' .. b
end

------------------------------------------------------------------ save / restore

-- dynamic memory, stack and frames, as one string
function Z:snapshot(pc)
  local parts = { string.pack('>I4I4I4I2', 0x5A4D0001, pc or self.pc, self.sp, #self.frames) }
  for i = 1, self.sp do parts[#parts + 1] = string.pack('>I2', self.stack[i]) end
  for _k, f in ipairs(self.frames) do
    parts[#parts + 1] = string.pack('>I4i2I2I4B', f.ret, f.store or -1, f.nargs, f.base, #f.locals)
    for i = 1, #f.locals do parts[#parts + 1] = string.pack('>I2', f.locals[i]) end
  end
  local mem = {}
  for i = 1, #self.dyn do mem[i] = string.pack('>I4', self.dyn[i]) end
  parts[#parts + 1] = string.pack('>I4', self.static_base) .. table.concat(mem):sub(1, self.static_base)
  parts[#parts + 1] = string.pack('>I2', self.upper_h)
  return table.concat(parts)
end

function Z:restore(s)
  local ok, err = pcall(function()
    local magic, pc, sp, nf, p = string.unpack('>I4I4I4I2', s)
    if magic ~= 0x5A4D0001 then error('not a saved game') end
    local stack = {}
    for i = 1, sp do stack[i], p = string.unpack('>I2', s, p) end
    local frames = {}
    for _k = 1, nf do
      local f = {}
      local store, nl
      f.ret, store, f.nargs, f.base, nl, p = string.unpack('>I4i2I2I4B', s, p)
      f.store = store >= 0 and store or nil
      f.locals = {}
      for i = 1, nl do f.locals[i], p = string.unpack('>I2', s, p) end
      frames[#frames + 1] = f
    end
    local n
    n, p = string.unpack('>I4', s, p)
    if n ~= self.static_base then error('saved from another game') end
    local mem = s:sub(p, p + n - 1)
    p = p + n
    -- the header's flags 2 and the interpreter's own fields stay as they are now
    local keep = { [0x10] = self:rb(0x10), [0x11] = self:rb(0x11) }
    local dyn = {}
    for i = 0, (n + 3) // 4 - 1 do
      local a = i * 4
      dyn[i + 1] = ((mem:byte(a + 1) or 0) << 24) | ((mem:byte(a + 2) or 0) << 16) | ((mem:byte(a + 3) or 0) << 8) | (mem:byte(a + 4) or 0)
    end
    self.dyn = dyn
    for a, b in pairs(keep) do self:wb(a, b) end
    self:set_header()
    self.pc, self.sp, self.stack, self.frames = pc, sp, stack, frames
    if p <= #s then
      local uh = string.unpack('>I2', s, p)
      self:split(uh)
    end
    self.reading = nil
  end)
  return ok, err
end

------------------------------------------------------------------ instructions

local OP2, OP1, OP0, VAR, EXT = {}, {}, {}, {}, {}

OP2[1] = function(m, a) local x = a[1]; for i = 2, #a do if a[i] == x then return m:branch(true) end end m:branch(false) end
OP2[2] = function(m, a) m:branch(signed(a[1]) < signed(a[2])) end
OP2[3] = function(m, a) m:branch(signed(a[1]) > signed(a[2])) end
OP2[4] = function(m, a) local v = signed(m:getvar(a[1], true) - 1); m:setvar(a[1], v, true); m:branch(v < signed(a[2])) end
OP2[5] = function(m, a) local v = signed(m:getvar(a[1], true) + 1); m:setvar(a[1], v, true); m:branch(v > signed(a[2])) end
OP2[6] = function(m, a) m:branch(m:parent(a[1]) == a[2]) end
OP2[7] = function(m, a) m:branch(a[1] & a[2] == a[2]) end
OP2[8] = function(m, a) m:store(a[1] | a[2]) end
OP2[9] = function(m, a) m:store(a[1] & a[2]) end
OP2[10] = function(m, a) m:branch(a[1] ~= 0 and m:attr(a[1], a[2])) end
OP2[11] = function(m, a) if a[1] ~= 0 then m:set_attr(a[1], a[2], true) end end
OP2[12] = function(m, a) if a[1] ~= 0 then m:set_attr(a[1], a[2], false) end end
OP2[13] = function(m, a) m:setvar(a[1], a[2], true) end
OP2[14] = function(m, a) if a[1] ~= 0 and a[2] ~= 0 then m:insert(a[1], a[2]) end end
OP2[15] = function(m, a) m:store(m:rw((a[1] + 2 * signed(a[2])) & 0xFFFF)) end
OP2[16] = function(m, a) m:store(m:rb((a[1] + signed(a[2])) & 0xFFFF)) end
OP2[17] = function(m, a)
  local data, len = m:find_prop(a[1], a[2])
  if not data then m:store(m:rw(m:rw(0x0A) + 2 * (a[2] - 1)))
  elseif len == 1 then m:store(m:rb(data))
  else m:store(m:rw(data)) end
end
OP2[18] = function(m, a) local data = a[1] ~= 0 and m:find_prop(a[1], a[2]); m:store(data or 0) end
OP2[19] = function(m, a)
  local o, n = a[1], a[2]
  local p = m:first_prop(o)
  if n ~= 0 then
    while true do
      local num, data, len = m:prop_at(p)
      if num == 0 then error('get_next_prop: no property ' .. n) end
      p = data + len
      if num == n then break end
    end
  end
  m:store((m:prop_at(p)))
end
OP2[20] = function(m, a) m:store(signed(a[1]) + signed(a[2])) end
OP2[21] = function(m, a) m:store(signed(a[1]) - signed(a[2])) end
OP2[22] = function(m, a) m:store(signed(a[1]) * signed(a[2])) end
local function zdiv(x, y) local q = math.abs(x) // math.abs(y); if (x < 0) ~= (y < 0) then q = -q end return q end
OP2[23] = function(m, a) if a[2] == 0 then error('division by zero') end m:store(zdiv(signed(a[1]), signed(a[2]))) end
OP2[24] = function(m, a)
  if a[2] == 0 then error('division by zero') end
  local x, y = signed(a[1]), signed(a[2])
  m:store(x - zdiv(x, y) * y)
end
OP2[25] = function(m, a) local s = m:rb(m.pc); m.pc = m.pc + 1; m:call(a[1], { a[2] }, s) end
OP2[26] = function(m, a) m:call(a[1], { a[2] }, nil) end
OP2[27] = function(m, a) end
OP2[28] = function(m, a)
  while #m.frames > a[2] do table.remove(m.frames) end
  m:ret(a[1])
end

OP1[0] = function(m, a) m:branch(a[1] == 0) end
OP1[1] = function(m, a) local s = a[1] ~= 0 and m:sibling(a[1]) or 0; m:store(s); m:branch(s ~= 0) end
OP1[2] = function(m, a) local c = a[1] ~= 0 and m:child(a[1]) or 0; m:store(c); m:branch(c ~= 0) end
OP1[3] = function(m, a) m:store(a[1] ~= 0 and m:parent(a[1]) or 0) end
OP1[4] = function(m, a) m:store(m:prop_len(a[1])) end
OP1[5] = function(m, a) m:setvar(a[1], signed(m:getvar(a[1], true)) + 1, true) end
OP1[6] = function(m, a) m:setvar(a[1], signed(m:getvar(a[1], true)) - 1, true) end
OP1[7] = function(m, a) m:print((m:decode(a[1]))) end
OP1[8] = function(m, a) local s = m:rb(m.pc); m.pc = m.pc + 1; m:call(a[1], {}, s) end
OP1[9] = function(m, a) if a[1] ~= 0 then m:remove(a[1]) end end
OP1[10] = function(m, a) m:print(m:obj_name(a[1])) end
OP1[11] = function(m, a) m:ret(a[1]) end
OP1[12] = function(m, a) m.pc = m.pc + signed(a[1]) - 2 end
OP1[13] = function(m, a) m:print((m:decode(m:unpack(a[1])))) end
OP1[14] = function(m, a) m:store(m:getvar(a[1], true)) end
OP1[15] = function(m, a)
  if m.v <= 4 then m:store(~a[1]) else m:call(a[1], {}, nil) end
end

OP0[0] = function(m) m:ret(1) end
OP0[1] = function(m) m:ret(0) end
OP0[2] = function(m) local s; s, m.pc = m:decode(m.pc); m:print(s) end
OP0[3] = function(m) local s; s, m.pc = m:decode(m.pc); m:print(s .. '\n'); m:ret(1) end
OP0[4] = function(m) end
local function do_save(m, start)
  local ok = false
  if m.on_save then
    local state = m:snapshot(m.pc)
    ok = m.on_save(state) and true or false
  end
  if m.v <= 3 then m:branch(ok) else m:store(ok and 1 or 0) end
end
local function do_restore(m)
  local s = m.on_restore and m.on_restore()
  if s and m:restore(s) then
    if m.v <= 3 then m:branch(true) else m:store(2) end
    return
  end
  if m.v <= 3 then m:branch(false) else m:store(0) end
end
OP0[5] = function(m, a, start) do_save(m, start) end
OP0[6] = function(m) do_restore(m) end
OP0[7] = function(m) m:reset() end
OP0[8] = function(m) m:ret(m:pop()) end
OP0[9] = function(m) if m.v <= 4 then m:pop() else m:store(#m.frames) end end
OP0[10] = function(m) m.done = true end
OP0[11] = function(m) m:print('\n') end
OP0[12] = function(m) end
OP0[13] = function(m) m:branch(true) end
OP0[15] = function(m) m:branch(true) end

VAR[0] = function(m, a) local s = m:rb(m.pc); m.pc = m.pc + 1; m:call(a[1], { table.unpack(a, 2) }, s) end
VAR[1] = function(m, a) m:ww((a[1] + 2 * signed(a[2])) & 0xFFFF, a[3]) end
VAR[2] = function(m, a) m:wb((a[1] + signed(a[2])) & 0xFFFF, a[3]) end
VAR[3] = function(m, a)
  local data, len = m:find_prop(a[1], a[2])
  if not data then error('put_prop: object ' .. a[1] .. ' has no property ' .. a[2]) end
  if len == 1 then m:wb(data, a[3]) else m:ww(data, a[3]) end
end
VAR[4] = function(m, a, start)
  m.reading = { text = a[1], parse = a[2] or 0, start = start }
  return 'input'
end
VAR[5] = function(m, a) if a[1] ~= 0 then m:print(utf8_of(a[1])) end end
VAR[6] = function(m, a) m:print(tostring(signed(a[1]))) end
VAR[7] = function(m, a)
  local r = signed(a[1])
  if r < 0 then m.rng = { seed = -r, n = 0 }; m:store(0)
  elseif r == 0 then m.rng = nil; m:store(0)
  elseif m.rng and m.rng.seed < 1000 then
    m.rng.n = m.rng.n % m.rng.seed + 1; m:store((m.rng.n - 1) % r + 1)
  else
    if m.rng then m.rng.x = ((m.rng.x or m.rng.seed) * 1103515245 + 12345) & 0x7FFFFFFF; m:store(m.rng.x % r + 1)
    else m:store(math.random(r)) end
  end
end
VAR[8] = function(m, a) m:push(a[1]) end
VAR[9] = function(m, a) local x = m:pop(); m:setvar(a[1], x, true) end
VAR[10] = function(m, a) m:split(a[1]) end
VAR[11] = function(m, a) m.window = a[1]; if a[1] == 1 then m.cur_row, m.cur_col = 1, 1 end end
VAR[12] = VAR[0]
VAR[13] = function(m, a)
  local w = signed(a[1])
  if w == -1 then m:split(0); m:erase_upper(); m.window = 0
  elseif w == -2 then m:erase_upper()
  elseif w == 1 then m:erase_upper() end
end
VAR[14] = function(m, a) end
VAR[15] = function(m, a) if m.window == 1 then m.cur_row, m.cur_col = a[1], a[2] end end
VAR[16] = function(m, a) m:ww(a[1], m.cur_row); m:ww(a[1] + 2, m.cur_col) end
VAR[17] = function(m, a) end
VAR[18] = function(m, a) end
VAR[19] = function(m, a)
  local n = signed(a[1])
  if n == 3 then m.out3[#m.out3 + 1] = { addr = a[2], n = 0 }
  elseif n == -3 then
    local t = table.remove(m.out3)
    if t then m:ww(t.addr, t.n) end
  end
end
VAR[20] = function(m, a) end
VAR[21] = function(m, a) end
VAR[22] = function(m, a, start)
  m.reading = { char = true, start = start }
  return 'char'
end
VAR[23] = function(m, a)
  local x, t, len = a[1], a[2], a[3]
  local form = a[4] or 0x82
  local size, words = form & 0x7F, form & 0x80 ~= 0
  for i = 0, len - 1 do
    local e = t + i * size
    local v = words and m:rw(e) or m:rb(e)
    if v == x then m:store(e); m:branch(true); return end
  end
  m:store(0); m:branch(false)
end
VAR[24] = function(m, a) m:store(~a[1]) end
VAR[25] = function(m, a) m:call(a[1], { table.unpack(a, 2) }, nil) end
VAR[26] = VAR[25]
VAR[27] = function(m, a) m:tokenise(a[1], a[2], a[3], a[4]) end
VAR[28] = function(m, a)
  local t = {}
  for i = 0, a[2] - 1 do t[#t + 1] = string.char(m:rb(a[1] + a[3] + i)) end
  local enc = m:encode(table.concat(t))
  for k, w in ipairs(enc) do m:ww(a[4] + 2 * (k - 1), w) end
end
VAR[29] = function(m, a)
  local from, to, size = a[1], a[2], signed(a[3])
  if to == 0 then for i = 0, math.abs(size) - 1 do m:wb(from + i, 0) end
  elseif size < 0 or from > to then for i = 0, math.abs(size) - 1 do m:wb(to + i, m:rb(from + i)) end
  else for i = size - 1, 0, -1 do m:wb(to + i, m:rb(from + i)) end end
end
VAR[30] = function(m, a)
  local addr, w, h, skip = a[1], a[2], a[3] or 1, a[4] or 0
  for r = 0, h - 1 do
    local t = {}
    for c = 0, w - 1 do t[#t + 1] = utf8_of(m:rb(addr + r * (w + skip) + c)) end
    m:print(table.concat(t) .. (r < h - 1 and '\n' or ''))
  end
end
VAR[31] = function(m, a) m:branch(a[1] <= m.frames[#m.frames].nargs) end

EXT[0] = function(m, a, start) do_save(m, start) end
EXT[1] = function(m) do_restore(m) end
EXT[2] = function(m, a)
  local s = signed(a[2])
  if s >= 0 then m:store(a[1] << s) else m:store(a[1] >> (-s)) end
end
EXT[3] = function(m, a)
  local s = signed(a[2])
  if s >= 0 then m:store(a[1] << s) else m:store(signed(a[1]) >> (-s) | ((a[1] & 0x8000 ~= 0) and (0xFFFF << (16 + s)) or 0)) end
end
EXT[4] = function(m, a) m:store(a[1] == 1 and 1 or 0) end
EXT[9] = function(m) m:store(0xFFFF) end                -- save_undo: not available (-1)
EXT[10] = function(m) m:store(0) end
EXT[11] = function(m, a) m:print(utf8.char(a[1])) end
EXT[12] = function(m, a) m:store((a[1] >= 32 and a[1] <= 126) and 3 or 0) end
EXT[13] = function(m) end

local function operand(m, t)
  local pc = m.pc
  if t == 0 then m.pc = pc + 2; return m:rw(pc)
  elseif t == 1 then m.pc = pc + 1; return m:rb(pc)
  else m.pc = pc + 1; return m:getvar(m:rb(pc)) end
end
local function var_operands(m, bytes)
  local a = {}
  local types = {}
  for k = 1, bytes do types[k] = m:rb(m.pc); m.pc = m.pc + 1 end
  for k = 1, bytes do
    local b = types[k]
    for s = 6, 0, -2 do
      local t = (b >> s) & 3
      if t == 3 then return a end
      a[#a + 1] = operand(m, t)
    end
  end
  return a
end

-- one instruction
function Z:step()
  local start = self.pc
  local op = self:rb(start)
  self.pc = start + 1
  local a, fn
  if op == 0xBE and self.v >= 5 then
    local n = self:rb(self.pc); self.pc = self.pc + 1
    a = var_operands(self, 1)
    fn = EXT[n]
    if not fn then error(string.format('unknown extended opcode %d at %x', n, start)) end
  elseif op >= 0xC0 then
    local n = op & 0x1F
    local two = op >= 0xE0 and (n == 12 or n == 26)
    a = var_operands(self, two and 2 or 1)
    if op < 0xE0 then fn = OP2[n] else fn = VAR[n] end
  elseif op >= 0x80 then
    local t = (op >> 4) & 3
    local n = op & 0x0F
    if t == 3 then a = {}; fn = OP0[n]
    else a = { operand(self, t) }; fn = OP1[n] end
  else
    local n = op & 0x1F
    a = { operand(self, (op & 0x40) ~= 0 and 2 or 1), operand(self, (op & 0x20) ~= 0 and 2 or 1) }
    fn = OP2[n]
  end
  if not fn then error(string.format('unknown opcode %02x at %x', op, start)) end
  return fn(self, a, start)
end

function Z:run(limit)
  if self.done then return 'quit' end
  if self.reading then return self.reading.char and 'char' or 'input' end
  local ok, res = pcall(function()
    for _i = 1, limit do
      local r = self:step()
      if r then
        if self.v <= 3 and r == 'input' then self.status_due = true end
        return r
      end
      if self.done then return 'quit' end
    end
    return 'more'
  end)
  if not ok then return 'error', tostring(res) end
  return res
end

return Z
