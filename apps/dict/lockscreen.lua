-- Word of the Day: the Dictionary's lock-screen entry (API 2.9). Picks one word a day (or every
-- 12, 6, 3 or 1 hours: wotd_every.txt) from the dictionary chosen in the app (lock_dict.txt; else
-- the first one in storage), shows it with its senses, examples and synonyms, and keeps the pick
-- in wotd.txt so a redraw reads no shard.
-- A pick: a shard and a byte offset from the period's number, then the first plain word after it
-- (lower-case letters only, a real definition); WordNet's "n 1: ...\n2: ..." is laid out by sense.

local W, H = 480, 800
local DAY = 86400
local M = 20                         -- side margin

-- a file from the app's user folder (ctx.files, API 2.9: AppFiles/<app_id>, where the user
-- copies dictionaries), read 64 KB at a time; a host that hands back the whole file is fine too
local function files_read(name)
  local F = ctx.files
  if not F then return nil end
  local ok, t = pcall(function()
    if not F:exists(name) then return nil end
    local parts, off = {}, 0
    for _i = 1, 64 do
      local piece = F:read(name, off, 65536)
      if type(piece) ~= 'string' or piece == '' then break end
      parts[#parts + 1] = piece
      off = off + #piece
      if #piece ~= 65536 then break end
    end
    return table.concat(parts)
  end)
  return (ok and type(t) == 'string' and t ~= '') and t or nil
end
-- names in the user folder and in the private files (dictionaries copied the older way)
local function copied_names()
  local seen, out = {}, {}
  local okf, files = pcall(function() return ctx.files:list() end)
  for _, f in ipairs((okf and type(files) == 'table') and files or {}) do
    local n = type(f) == 'table' and f.name or f
    if type(n) == 'string' and not seen[n] then seen[n] = true; out[#out + 1] = n end
  end
  local oks, names = pcall(function() return ctx.storage:list() end)
  for _, n in ipairs((oks and type(names) == 'table') and names or {}) do
    if type(n) == 'string' and not seen[n] then seen[n] = true; out[#out + 1] = n end
  end
  return out
end
local function read(name)
  local f = files_read(name)
  if f then return f end
  local ok, s = pcall(function() return ctx.storage:read(name) end)
  return (ok and type(s) == 'string') and s or nil
end
local function font(name) return ctx.fonts and ctx.fonts[name] end
local function lh(name)
  local ok, h = pcall(function() return font(name).line_height end)
  return (ok and tonumber(h)) or (name == 'large' and 30 or name == 'small' and 20 or 24)
end
local function width(f, s)
  local ok, w = pcall(function() return f:measure(s) end)
  return (ok and type(w) == 'number') and w or #s * 11
end

------------------------------------------------------------------ the day

-- local wall time as seconds since 1970 (the UTC offset from the clock's hour against epoch_sec)
local function wall_now()
  local ok, t = pcall(function() return ctx.clock:now() end)
  if not ok or type(t) ~= 'table' then return nil end
  local e = tonumber(t.epoch_sec)
  if e and t.hour then
    local off = ((t.hour * 3600 + (t.minute or 0) * 60 + (t.second or 0)) - e % DAY) % DAY
    if off > 14 * 3600 then off = off - DAY end
    return e + off
  end
  return tonumber(t.local_sec)
end

-- days since 1970-01-01 -> year, month, day (H. Hinnant's civil_from_days)
local function civil(z)
  z = z + 719468
  local era = (z >= 0 and z or z - 146096) // 146097
  local doe = z - era * 146097
  local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
  local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
  local mp = (5 * doy + 2) // 153
  local d = doy - (153 * mp + 2) // 5 + 1
  local m = mp < 10 and mp + 3 or mp - 9
  return yoe + era * 400 + (m <= 2 and 1 or 0), m, d
end
local MONTH = { 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
                'September', 'October', 'November', 'December' }
local WDAY = { 'Thursday', 'Friday', 'Saturday', 'Sunday', 'Monday', 'Tuesday', 'Wednesday' }

------------------------------------------------------------------ the pick

local function dict_prefix()
  local want = (read('lock_dict.txt') or ''):match('^([^\n]*)')
  if want and read(want .. 'shards.tsv') then return want end
  local names = copied_names()
  if #names == 0 then return nil end
  table.sort(names)
  for _, n in ipairs(names) do
    local pre = n:match('^(.*)shards%.tsv$')
    if pre then return pre end
  end
  return nil
end

local function good(word, def)
  return #word >= 4 and #word <= 16 and word:match('^[%l\128-\255]+$') ~= nil and #def >= 24
end

-- the word for `seed` (a number per period) from dictionary `pre`: returns word, definition
local function pick(pre, seed)
  local files = {}
  for f in (read(pre .. 'shards.tsv') or ''):gmatch('([^\t\n]+)\t[^\n]*\n?') do files[#files + 1] = f end
  if #files == 0 then return nil end
  -- 31 bits, the same on the reader and a computer: the reader's integers are 32-bit (they wrap,
  -- keeping the low bits) and its floats single precision; 2654435761 and a 2^32 modulus made the
  -- hash a float there, which always picked the first shard ("aalii")
  local h = (seed * 1103515245 + 12345) & 0x7fffffff
  for k = 0, 2 do                                   -- a shard without a plain word: the next one
    local text = read(files[(h + k) % #files + 1])
    if text and #text > 0 then
      local at = text:find('\n', (h // #files) % #text + 1, true) or 0
      for _pass = 1, 2 do                          -- to the end of the shard, then from its start
        for w, def in text:sub(at + 1):gmatch('([^\t\n]+)\t([^\n]*)') do
          if good(w, def) then return w, def end
        end
        at = 0
      end
    end
  end
  return nil
end

-- a new word every EVERY hours (wotd_every.txt, set in the app: 24, 12, 6, 3 or 1); a day's
-- periods start at midnight
local EVERY = { [24] = true, [12] = true, [6] = true, [3] = true, [1] = true }
local function every()
  local n = tonumber((read('wotd_every.txt') or ''):match('%d+'))
  return EVERY[n] and n or 24
end

-- the word of the period that `wall` falls in; the pick is kept in wotd.txt under "hours:period"
local function current_word(wall)
  local pre = dict_prefix()
  if not pre then return nil end
  local hours = every()
  local k = wall // (hours * 3600)
  local key = hours .. ':' .. k
  local s = read('wotd.txt')
  if s then
    local kk, p, w, def = s:match('^([%d:]+)\t([^\t]*)\t([^\t]+)\t([^\n]*)')
    if kk == key and p == pre then return w, def, pre end   -- another dictionary or interval: pick again
  end
  local w, def = pick(pre, hours == 24 and k or (k * 7 + hours))
  if w then pcall(function() ctx.storage:write('wotd.txt', key .. '\t' .. pre .. '\t' .. w .. '\t' .. def) end) end
  return w, def, pre
end

------------------------------------------------------------------ the layout

local POS = { n = 'noun', v = 'verb', adj = 'adjective', adv = 'adverb', s = 'adjective' }

-- the definition as paragraphs { s, font, indent }: a part of speech, each sense (with WordNet's
-- number) and up to two examples, "also:" with the synonyms; other dictionaries line by line
local function paragraphs(def)
  local out = {}
  local text = def:gsub('\\(.)', function(c) return c == 'n' and '\n' or c end)
  for raw in (text .. '\n'):gmatch('([^\n]*)\n') do
    local line = raw
    local pos, num, rest = line:match('^(%a+)%s*(%d*):%s*(.*)$')
    if pos and POS[pos] then
      out[#out + 1] = { POS[pos], 'small', 0 }
      line = rest
    else
      num, rest = line:match('^(%d+):%s*(.*)$')
      if num then line = rest else num = '' end
    end
    local syn = line:match('%[syn:%s*(.-)%]')
    line = line:gsub('%s*%[syn:.-%]', '')
    local sense, examples = line:match('^(.-);%s*(".*)$')
    sense = sense or line
    if sense:match('%S') then out[#out + 1] = { (num ~= '' and (num .. '. ') or '') .. sense, 'medium', 0 } end
    local shown = 0
    for ex in (examples or ''):gmatch('"([^"]+)"') do
      if shown < 2 then out[#out + 1] = { '"' .. ex .. '"', 'small', 22 }; shown = shown + 1 end
    end
    if syn then out[#out + 1] = { 'also: ' .. syn:gsub('[{}]', ''), 'small', 22 } end
  end
  return out
end

local function wrap(s, f, w)
  local lines, cur = {}, ''
  for word in s:gmatch('%S+') do
    local t = cur == '' and word or (cur .. ' ' .. word)
    if cur ~= '' and width(f, t) > w then lines[#lines + 1] = cur; cur = word else cur = t end
  end
  if cur ~= '' then lines[#lines + 1] = cur end
  return lines
end

function on_draw(c, gg)
  if not gg then return end
  local ok, err = pcall(function()
    gg:clear(0)
    local wall = wall_now() or 0
    local day = wall // DAY
    local y, m, d = civil(day)
    gg:text(M, 16, 'Word of the Day', { font = font('large') })
    gg:text(M, 54, WDAY[day % 7 + 1] .. ' ' .. d .. ' ' .. MONTH[m] .. ' ' .. y, { font = font('medium') })
    gg:line(16, 92, W - 16, 92)
    gg:line(16, 93, W - 16, 93)
    local word, def, pre = current_word(wall)
    if not word then
      gg:text(M, 380, 'Dictionary: copy a dictionary', { font = font('medium') })
      gg:text(M, 410, 'into the app first.', { font = font('medium') })
      return
    end
    gg:text(M, 116, word, { font = font('large') })
    -- the text stops a small line above the footer, room for the "..." of a cut definition
    local top, bottom = 116 + lh('large') + 16, H - 48 - lh('small')
    local yy = top
    for _, p in ipairs(paragraphs(def)) do
      local f, fh = font(p[2]), lh(p[2])
      if p[2] == 'small' and p[3] == 0 and yy > top then yy = yy + 6 end      -- a new part of speech
      for _, l in ipairs(wrap(p[1], f, W - 2 * M - p[3])) do
        if yy + fh > bottom then
          gg:text(M, yy - 4, '...', { font = font('small') })
          yy = H; break
        end
        gg:text(M + p[3], yy, l, { font = f })
        yy = yy + fh + 2
      end
      if yy >= H then break end
      yy = yy + 6
    end
    local info = read((pre or '') .. 'info.txt') or ''
    local name = info:match('name=([^\n]*)') or ''
    if name ~= '' then gg:text(M, H - 32, name, { font = font('small') }) end
  end)
  if not ok then pcall(function() gg:text(10, 760, 'lock error: ' .. tostring(err):sub(1, 40)) end) end
end

function on_load() end
function on_tick() end
function on_input() return false end
