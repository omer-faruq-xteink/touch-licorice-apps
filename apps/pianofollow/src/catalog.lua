-- catalog: the free pieces, read from the repository's raw files (catalog/piano/ on GitHub), so new
-- pieces appear when they are pushed. The list is kept in catalog.json in the app's folder and still
-- shows offline; pieces are downloaded straight into the folder (request `save`).
--   C.refresh(done)        done(ok, err)
--   C.levels() -> { { level, label, count } }   C.composers(level) -> { name }   C.pieces(level, composer)
--   C.search(text) -> entries;  C.get(id);  C.download(id, done) done(ok, err);  C.installed(id)
local S = require('score')
local C = {}
C.BASE = 'https://raw.githubusercontent.com/omer-faruq-xteink/touch-licorice-apps/main/catalog/piano/'
local LEVELS = { 'beginner', 'easy', 'intermediate', 'advanced' }
local LABEL = { beginner = 'Beginner', easy = 'Easy', intermediate = 'Intermediate', advanced = 'Advanced' }
local data = nil

local function load_cached()
  local ok, s = pcall(function() return ctx.files:read('catalog.json', 0, 65536) end)
  if not ok or type(s) ~= 'string' or s == '' then return false end
  -- a catalog longer than one read
  local parts, off = { s }, #s
  while #parts[#parts] == 65536 do
    local more = ctx.files:read('catalog.json', off, 65536)
    if not more or more == '' then break end
    parts[#parts + 1] = more
    off = off + #more
  end
  local ok2, d = pcall(function() return ctx.json:decode(table.concat(parts)) end)
  if ok2 and type(d) == 'table' and type(d.pieces) == 'table' then data = d; return true end
  return false
end

function C.refresh(done)
  C.rescan()
  local job, err = ctx.net:request({ url = C.BASE .. 'catalog.json', save = { to = 'files', name = 'catalog.json' } }, function(_c, res)
    local fresh = res.ok and res.status == 200 and res.saved and load_cached()
    if fresh then done(true) return end
    load_cached()
    done(false, (not res.ok) and (res.err == 'no_network' and 'No connection' or tostring(res.err or 'error'))
      or ('the catalog answered ' .. tostring(res.status)))
  end)
  if not job then load_cached(); done(false, err == 'busy' and 'busy, try again' or tostring(err)) end
end

function C.loaded() return data ~= nil end

function C.levels()
  local out = {}
  if not data then return out end
  for _k, lv in ipairs(LEVELS) do
    local n = 0
    for _j, p in ipairs(data.pieces) do if p.level == lv then n = n + 1 end end
    if n > 0 then out[#out + 1] = { level = lv, label = LABEL[lv], count = n } end
  end
  return out
end

function C.composers(level)
  local seen, out = {}, {}
  for _k, p in ipairs(data and data.pieces or {}) do
    if p.level == level and not seen[p.composer] then seen[p.composer] = true; out[#out + 1] = p.composer end
  end
  table.sort(out, function(a, b) return a:lower() < b:lower() end)
  return out
end

local function by_title(t) table.sort(t, function(a, b) return a.title:lower() < b.title:lower() end) return t end

function C.pieces(level, composer)
  local out = {}
  for _k, p in ipairs(data and data.pieces or {}) do
    if p.level == level and p.composer == composer then out[#out + 1] = p end
  end
  return by_title(out)
end

function C.search(text)
  local q, out = (text or ''):lower(), {}
  if q == '' then return out end
  for _k, p in ipairs(data and data.pieces or {}) do
    if p.title:lower():find(q, 1, true) or (p.composer or ''):lower():find(q, 1, true) then out[#out + 1] = p end
  end
  return by_title(out)
end

function C.get(id)
  for _k, p in ipairs(data and data.pieces or {}) do if p.id == id then return p end end
  return nil
end

local function file_of(id) return id .. '.xtscore' end
-- which pieces are on the reader: one listing of the folder, not a card read per catalog entry
local have = nil
function C.rescan()
  have = {}
  local ok, files = pcall(function() return ctx.files:list() end)
  if ok and type(files) == 'table' then for _k, f in ipairs(files) do have[f.name:lower()] = true end end
end
function C.installed(id)
  if not have then C.rescan() end
  return have[file_of(id):lower()] == true
end
function C.file(id) return file_of(id) end

function C.download(id, done)
  local name = file_of(id)
  local job, err = ctx.net:request({ url = C.BASE .. 'pieces/' .. name, save = { to = 'files', name = name } }, function(_c, res)
    if not (res.ok and res.status == 200 and res.saved) then
      done(false, (not res.ok) and (res.err == 'no_network' and 'No connection' or tostring(res.err)) or ('download failed (' .. tostring(res.status) .. ')'))
      return
    end
    if not S.open(name) then
      pcall(function() ctx.files:remove(name) end)
      done(false, 'the download is damaged, try again later')
      return
    end
    C.rescan()
    done(true)
  end)
  if not job then done(false, err == 'busy' and 'busy, try again' or tostring(err)) end
end

return C
