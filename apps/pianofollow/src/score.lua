-- score: reading .xtscore files from the app's folder (AppFiles/pianofollow/).
--   "XTSCORE1", uint32 LE header length N, N bytes of JSON header, then zlib streams
--   (pages of 760 rows x 60 bytes, and the note map as JSON). See site/tools/piano/convert.mjs.
--
--   S.open(name) -> piece | nil, 'not_found' | 'bad_file'     piece = { name, header, size }
--   S.page_bits(piece, i) -> h * w/8 bytes (header w, h) | nil, err
--   S.load_map(piece) -> map | nil, err                        (kept in piece.map)
--   S.list() -> { { name, title, composer, level, size, bad } } sorted by title
local S = {}
local MAGIC, CHUNK = 'XTSCORE1', 65536

local function read(name, off, len)
  local ok, d, e = pcall(function() return ctx.files:read(name, off, len) end)
  if not ok then return nil, 'bad_file' end
  return d, e
end

-- a range longer than one read (the note map of a long piece)
local function read_all(name, off, len)
  local parts, got = {}, 0
  while got < len do
    local d = read(name, off + got, math.min(CHUNK, len - got))
    if not d or #d == 0 then return nil end
    parts[#parts + 1] = d
    got = got + #d
  end
  return table.concat(parts)
end

local function valid_range(r, size)
  return type(r) == 'table' and type(r[1]) == 'number' and type(r[2]) == 'number'
    and r[1] >= 12 and r[2] > 0 and r[1] + r[2] <= size
end

function S.open(name)
  local head, err = read(name, 0, 12)
  if not head then return nil, err == 'not_found' and 'not_found' or 'bad_file' end
  if #head < 12 or head:sub(1, 8) ~= MAGIC then return nil, 'bad_file' end
  local n = string.unpack('<I4', head, 9)
  if n < 2 or n > CHUNK then return nil, 'bad_file' end
  local hj = read(name, 12, n)
  if not hj or #hj < n then return nil, 'bad_file' end
  local ok, h = pcall(function() return ctx.json:decode(hj) end)
  if not ok or type(h) ~= 'table' or type(h.pages) ~= 'table' or #h.pages == 0 then return nil, 'bad_file' end
  local size = ctx.files:size(name) or 0
  for _k, r in ipairs(h.pages) do if not valid_range(r, size) or r[2] >= CHUNK then return nil, 'bad_file' end end
  if not valid_range(h.map, size) then return nil, 'bad_file' end
  -- the page size: 480 x 760 upright, 800 x 440 turned
  if math.type(h.w) ~= 'integer' or math.type(h.h) ~= 'integer' or h.w % 8 ~= 0 or h.w < 8 or h.h < 8 or h.w > 800 or h.h > 800 then return nil, 'bad_file' end
  if type(h.title) ~= 'string' or h.title == '' then h.title = name:gsub('%.[^.]*$', '') end
  return { name = name, header = h, size = size }
end

function S.page_bits(p, i)
  local r = p.header.pages[i]
  if not r then return nil, 'invalid_argument' end
  local z = read(p.name, r[1], r[2])
  if not z or #z < r[2] then return nil, 'bad_file' end
  pcall(function() ctx.budget:extend() end)
  local ok, bits = pcall(function() return ctx.zlib:decompress(z, { format = 'zlib' }) end)
  if not ok or type(bits) ~= 'string' or #bits ~= p.header.h * (p.header.w // 8) then return nil, 'bad_file' end
  return bits
end

function S.load_map(p)
  if p.map then return p.map end
  pcall(function() ctx.budget:extend() end)
  local r = p.header.map
  local z = read_all(p.name, r[1], r[2])
  if not z then return nil, 'bad_file' end
  local ok, js = pcall(function() return ctx.zlib:decompress(z, { format = 'zlib' }) end)
  if not ok or type(js) ~= 'string' then return nil, 'bad_file' end
  local ok2, m = pcall(function() return ctx.json:decode(js) end)
  if not ok2 or type(m) ~= 'table' or type(m.onsets) ~= 'table' or type(m.bars) ~= 'table' or type(m.turn) ~= 'table' then
    return nil, 'bad_file'
  end
  p.map = m
  return m
end

-- My pieces. Opening every file on each visit would cost three card reads a piece (the callback limit
-- is 1000 ms), so a private index keeps name, size, title, composer and level; only new or changed files
-- are opened.
local INDEX = 'pieces.txt'
local function clean(v) return (tostring(v or ''):gsub('[%c]', ' ')) end   -- no tabs or line breaks in the index

function S.list()
  pcall(function() ctx.budget:extend() end)
  local ok, files = pcall(function() return ctx.files:list() end)
  local out = {}
  if not ok or type(files) ~= 'table' then return out end
  local cache = {}
  for line in (kit.read(INDEX) or ''):gmatch('[^\n]+') do
    local name, size, title, composer, level, bad = line:match('^([^\t]*)\t(%d+)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([01])$')
    if name then cache[name] = { name = name, size = tonumber(size), title = title, composer = composer, level = level, bad = bad == '1' or nil } end
  end
  local changed, opened = false, 0
  for _k, f in ipairs(files) do
    if f.name:lower():match('%.xtscore$') then
      local row = cache[f.name]
      if not row or row.size ~= f.size then
        opened = opened + 1
        if opened % 5 == 0 then pcall(function() ctx.budget:extend() end) end
        local p = S.open(f.name)
        if p then
          row = { name = f.name, title = clean(p.header.title), composer = clean(p.header.composer), level = clean(p.header.level), size = f.size }
        else
          row = { name = f.name, title = clean(f.name), composer = '', level = '', size = f.size, bad = true }
        end
        changed = true
      end
      out[#out + 1] = row
    end
  end
  if changed or #out ~= (function() local n = 0 for _ in pairs(cache) do n = n + 1 end return n end)() then
    local lines = {}
    for _k, r in ipairs(out) do
      lines[#lines + 1] = table.concat({ r.name, r.size, r.title, r.composer, r.level, r.bad and '1' or '0' }, '\t')
    end
    kit.write(INDEX, table.concat(lines, '\n'))
  end
  table.sort(out, function(a, b) return a.title:lower() < b.title:lower() end)
  return out
end

return S
