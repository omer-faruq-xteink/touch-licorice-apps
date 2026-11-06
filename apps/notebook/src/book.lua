-- Notebook's notes: one plain text file per note in the app's folder on the card
-- (AppFiles/notebook/, ctx.files), so they can be read and written on a computer too:
--
--   Shopping list                 the title
--   folder: Home                  optional
--   tags: weekly, market          optional
--   edited: 2026-11-06 14:30      written by the app
--   created: 2026-11-06 14:02     written by the app
--                                 a blank line, then the paragraphs, one blank line between them
--   First paragraph...
--
-- A file without these lines works too: its first line is the title, the rest the text. The
-- folder cannot have subfolders (ctx.files), so a note's folder is the "folder:" line.
--
-- The list needs each note's title, folder, tags and dates without reading every file at each
-- start: an index (index.txt in ctx.storage) keeps them by file name and size, and only files
-- that are new or changed in size are read again.

local B = {}

B.MAX_PARA = 512                  -- characters per paragraph (the docked keyboard's limit)
B.MAX_FILE = 200000               -- bytes a note may grow to (a write takes at most 262144)
local HEAD_BYTES = 4096

------------------------------------------------------------------ files

local function files() return ctx.files end

function B.list_files()
  local ok, list = pcall(function() return files():list() end)
  if not ok or type(list) ~= 'table' then return {} end
  local out = {}
  for _k, f in ipairs(list) do
    if type(f.name) == 'string' and f.name:lower():match('%.txt$') then out[#out + 1] = { name = f.name, size = f.size or 0 } end
  end
  return out
end

function B.read(name, len)
  local parts, pos = {}, 0
  while true do
    local ok, chunk = pcall(function() return files():read(name, pos, 65536) end)
    if not ok or type(chunk) ~= 'string' then return #parts > 0 and table.concat(parts) or nil end
    parts[#parts + 1] = chunk
    pos = pos + #chunk
    if #chunk < 65536 or (len and pos >= len) or pos >= B.MAX_FILE then break end
  end
  return table.concat(parts)
end

function B.write(name, s)
  local ok, r, err = pcall(function() return files():write(name, s) end)
  if not ok then return nil, tostring(r) end
  if not r then return nil, tostring(err) end
  return true
end

function B.remove(name) pcall(function() files():remove(name) end) end

function B.exists(name)
  local ok, r = pcall(function() return files():exists(name) end)
  return ok and r == true
end

------------------------------------------------------------------ text

-- lower case for search, Turkish and other accented capitals too; I, İ and ı all become i, so
-- "istanbul" finds "İstanbul" and "ISTANBUL" alike
local FOLD = {
  ['İ'] = 'i', ['I'] = 'i', ['ı'] = 'i', ['Ç'] = 'ç', ['Ğ'] = 'ğ', ['Ö'] = 'ö', ['Ş'] = 'ş', ['Ü'] = 'ü',
  ['Ä'] = 'ä', ['Â'] = 'â', ['Á'] = 'á', ['À'] = 'à', ['É'] = 'é', ['È'] = 'è', ['Ê'] = 'ê', ['Í'] = 'í',
  ['Î'] = 'î', ['Ó'] = 'ó', ['Ô'] = 'ô', ['Ú'] = 'ú', ['Û'] = 'û', ['Ñ'] = 'ñ', ['Å'] = 'å', ['Ø'] = 'ø',
}
-- (only A-Z by hand: string.lower follows the C locale and may change bytes of UTF-8 letters)
function B.fold(s)
  s = s:gsub('[%z\1-\127\194-\244][\128-\191]*', function(c) return FOLD[c] end)
  return (s:gsub('[A-Z]', function(c) return string.char(c:byte() + 32) end))
end

local function trim(s) return (s:gsub('^%s+', ''):gsub('%s+$', '')) end
B.trim = trim

-- a paragraph longer than the keyboard takes is cut at a line break or a space before the limit
local function cut(p, out)
  while utf8.len(p) and utf8.len(p) > B.MAX_PARA do
    local stop = utf8.offset(p, B.MAX_PARA + 1) - 1
    local head = p:sub(1, stop)
    local at = head:match('^.*()\n') or head:match('^.*() ')
    if not at or at < stop // 2 then at = stop + 1 end
    out[#out + 1] = trim(p:sub(1, at - 1))
    p = trim(p:sub(at))
  end
  if p ~= '' then out[#out + 1] = p end
end

-- the paragraphs of a text: blank lines part them
function B.paragraphs(text)
  local out = {}
  text = (text or ''):gsub('\r', '')
  for raw in (text .. '\n\n'):gmatch('(.-)\n%s*\n') do
    local p = trim(raw)
    if p ~= '' then cut(p, out) end
  end
  return out
end

-- a note from a file's text
function B.parse(s)
  s = (s or ''):gsub('\r', ''):gsub('^\239\187\191', '')
  local n = { title = '', folder = '', tags = {}, edited = '', created = '', paras = {} }
  local first, rest = s:match('^([^\n]*)\n?(.*)$')
  n.title = trim(first or '')
  rest = rest or ''
  while true do
    local line, after = rest:match('^([^\n]*)\n?(.*)$')
    if not line then break end
    local k, v = line:match('^(%a+):%s*(.-)%s*$')
    if k == 'folder' then n.folder = v
    elseif k == 'tags' then n.tags = B.split_tags(v)
    elseif k == 'edited' then n.edited = v
    elseif k == 'created' then n.created = v
    else break end
    rest = after
  end
  n.paras = B.paragraphs(rest)
  if n.title == '' then n.title = 'Untitled' end
  return n
end

function B.split_tags(s)
  local out, seen = {}, {}
  for raw in (s or ''):gmatch('[^,]+') do
    local t = trim(raw)
    if t ~= '' and not seen[B.fold(t)] then seen[B.fold(t)] = true; out[#out + 1] = t end
  end
  return out
end

function B.format(n)
  local t = { n.title }
  if n.folder ~= '' then t[#t + 1] = 'folder: ' .. n.folder end
  if #n.tags > 0 then t[#t + 1] = 'tags: ' .. table.concat(n.tags, ', ') end
  if n.edited ~= '' then t[#t + 1] = 'edited: ' .. n.edited end
  if n.created ~= '' then t[#t + 1] = 'created: ' .. n.created end
  return table.concat(t, '\n') .. '\n\n' .. table.concat(n.paras, '\n\n') .. '\n'
end

------------------------------------------------------------------ file names

local RESERVED = { con = 1, prn = 1, aux = 1, nul = 1 }
for i = 1, 9 do RESERVED['com' .. i] = 1; RESERVED['lpt' .. i] = 1 end

-- a file name for a title: what the card allows, at most 60 bytes, not taken by another note
function B.file_name(title, taken)
  local s = title:gsub('[%c/\\:%*%?"<>|~]', ' '):gsub('%s+', ' ')
  s = trim(s):gsub('^%.+', '')
  while #s > 60 do s = s:gsub('[%z\1-\127\194-\244][\128-\191]*$', '') end
  s = s:gsub('[%. ]+$', '')
  if s == '' then s = 'Note' end
  if RESERVED[s:lower()] then s = s .. '_' end
  local name, k = s .. '.txt', 2
  while taken(name) do name = s .. ' ' .. k .. '.txt'; k = k + 1 end
  return name
end

------------------------------------------------------------------ the index

local SEP = '\t'
local function clean(s) return (tostring(s or ''):gsub('[\t\n\r]', ' ')) end

-- a list entry from a note: what the list shows and filters on
function B.entry(name, size, n)
  local snip = (n.paras[1] or ''):gsub('%s+', ' ')
  if #snip > 120 then snip = snip:sub(1, 120):gsub('[%z\1-\127\194-\244][\128-\191]*$', '') end
  return { name = name, size = size, title = n.title, folder = n.folder, tags = n.tags,
           edited = n.edited, created = n.created, snip = snip }
end

function B.load_index()
  local ok, s = pcall(function() return ctx.storage:read('index.txt') end)
  local out = {}
  if not ok or type(s) ~= 'string' then return out end
  for line in s:gmatch('[^\n]+') do
    local f = {}
    for v in (line .. SEP):gmatch('([^\t]*)\t') do f[#f + 1] = v end
    if #f >= 8 then
      out[f[1]] = { name = f[1], size = tonumber(f[2]) or -1, title = f[3], folder = f[4], tags = B.split_tags(f[5]),
                    edited = f[6], created = f[7], snip = f[8] }
    end
  end
  return out
end

function B.save_index(entries)
  local t = {}
  for _k, e in ipairs(entries) do
    t[#t + 1] = table.concat({ clean(e.name), e.size, clean(e.title), clean(e.folder), clean(table.concat(e.tags, ', ')),
                               clean(e.edited), clean(e.created), clean(e.snip) }, SEP)
  end
  pcall(function() ctx.storage:write('index.txt', table.concat(t, '\n')) end)
end

-- the list's entries: the index where a file's size is the same, else read again (step(k, n)
-- is called after each file read, for progress and to give the host time)
function B.scan(step)
  local idx = B.load_index()
  local out, changed = {}, false
  local fl = B.list_files()
  for k, f in ipairs(fl) do
    local e = idx[f.name]
    if not e or e.size ~= f.size then
      local n = B.parse(B.read(f.name, HEAD_BYTES) or '')
      e = B.entry(f.name, f.size, n)
      changed = true
      if step then step(k, #fl) end
    end
    out[#out + 1] = e
  end
  if changed or #out ~= (function() local c = 0; for _ in pairs(idx) do c = c + 1 end; return c end)() then B.save_index(out) end
  return out
end

-- the line of a note that holds the folded query, shortened around it (nil: not found)
function B.find(text, q)
  for raw in (text .. '\n'):gmatch('([^\n]*)\n') do
    local line = raw
    local f = B.fold(line)
    local at = f:find(q, 1, true)
    if at then
      line = trim(line)
      if #line > 90 then
        local start = math.max(1, at - 30)
        while start > 1 and line:byte(start) >= 128 and line:byte(start) < 192 do start = start - 1 end
        line = (start > 1 and '…' or '') .. line:sub(start, start + 89):gsub('[%z\1-\127\194-\244][\128-\191]*$', '')
      end
      return line
    end
  end
  return nil
end

return B
