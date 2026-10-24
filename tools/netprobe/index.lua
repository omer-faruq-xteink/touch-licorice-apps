-- Net Probe -- does the XTOS Licorice Lua host expose HTTP / networking to a mini app?
--
-- The screen is the only output channel (no print, no io, ctx.log goes nowhere), so this app
-- enumerates the host and paints the result, one page per tap. Nothing here changes device
-- state: functions are only *called* when their name is not on the DANGER list, and then with no
-- arguments, inside pcall, so the error message ("bad argument #1 ... string expected") documents
-- the signature without doing anything.
--
--   page 1      Lua version, globals, ctx top-level keys
--   page 2..    ctx.api / ctx.capabilities / ctx.system / ctx.sys / ctx.ui / ctx.data / ctx.longtask
--               / ctx.watchdog, each member with its type; tables one level deeper; functions
--               called with no args, the result or error shown
--   then        require() probe: which module names resolve
--   then        name hunt: every key anywhere in ctx (depth 3) matching http|net|url|fetch|
--               request|socket|wifi|json|download|write|save|open
--   last        the on_input event table (taps forward the pages)

local VARIANT = 'base'   -- build.py replaces this per manifest variant

local PER   = 33
local LH    = 22
local TOP   = 52
local X     = 10
local WIDE  = 46

local lines = {}
local built = false
local page  = 1
local taps  = 0

local function add(s) lines[#lines + 1] = s end

local function short(s, n)
  s = tostring(s); n = n or WIDE
  if #s > n then return s:sub(1, n - 1) .. '~' end
  return s
end

local function keys_of(t)
  if type(t) ~= 'table' then return nil end
  local ks = {}
  local ok = pcall(function() for k in pairs(t) do ks[#ks + 1] = k end end)
  if not ok then return nil end
  table.sort(ks, function(a, b) return tostring(a) < tostring(b) end)
  return ks
end

local function val(v, n)
  local t = type(v)
  if t == 'string' then return '"' .. short(v, n or 26) .. '"' end
  if t == 'number' or t == 'boolean' or t == 'nil' then return tostring(v) end
  if t == 'table' then
    local ks = keys_of(v)
    if not ks then return 'table(?)' end
    local parts = {}
    for _, k in ipairs(ks) do
      local sv = v[k]; local st = type(sv)
      if st == 'string' or st == 'number' or st == 'boolean' then
        parts[#parts + 1] = tostring(k) .. '=' .. tostring(sv)
      else
        parts[#parts + 1] = tostring(k) .. ':' .. st:sub(1, 3)
      end
    end
    return '{' .. short(table.concat(parts, ' '), n or 34) .. '}'
  end
  return t
end

local function wrap(prefix, s)
  s = tostring(s)
  local n = WIDE - #prefix
  while #s > n do add(prefix .. s:sub(1, n)); s = s:sub(n + 1); prefix = '    ' end
  if #s > 0 then add(prefix .. s) end
end

local function row_list(items, indent)
  indent = indent or '  '
  local row = ''
  for _, item in ipairs(items) do
    local n = tostring(item)
    if #row + #n + 1 > WIDE - #indent then add(indent .. row); row = n
    else row = (row == '' and n or row .. ' ' .. n) end
  end
  if row ~= '' then add(indent .. row) end
end

-- never call a function whose name smells like it could act
local DANGER = {'quit', 'exit', 'reboot', 'restart', 'reset', 'sleep', 'shutdown', 'power',
                'erase', 'delete', 'remove', 'format', 'uninstall', 'install', 'write', 'save',
                'set_', 'clear', 'lock', 'unlock', 'start', 'stop', 'connect', 'disconnect',
                'enable', 'disable', 'toggle', 'open', 'launch', 'run', 'post', 'put', 'send',
                'download', 'upload', 'flush', 'commit', 'update', 'ota', 'keep_awake', 'feed'}
local function dangerous(name)
  name = tostring(name):lower()
  for _, d in ipairs(DANGER) do if name:find(d, 1, true) then return true end end
  return false
end

local function probe_call(label, f, self)
  if dangerous(label) then add('  ' .. short(label, 24) .. '() skipped (name)'); return end
  local r
  if self ~= nil then r = table.pack(pcall(f, self)) else r = table.pack(pcall(f)) end
  if r[1] then
    local out = {}
    for i = 2, r.n do out[#out + 1] = val(r[i], 22) end
    wrap('  ' .. short(label, 22) .. '() = ', #out > 0 and table.concat(out, ', ') or '(no value)')
  else
    wrap('  ' .. short(label, 22) .. '() ! ', tostring(r[2]):gsub('%[string "[^"]*"%]:%d+: ', ''))
  end
end

-- a userdata (or a table whose pairs is blocked) answers only to names: try a wide list, read only
local NAMES = {'get', 'post', 'put', 'request', 'fetch', 'http', 'https', 'download', 'url', 'open',
               'read', 'write', 'read_text', 'write_text', 'append', 'remove', 'list', 'exists',
               'size', 'connect', 'send', 'recv', 'close', 'start', 'cancel', 'poll', 'wait',
               'is_done', 'done', 'status', 'code', 'body', 'headers', 'result', 'error', 'json',
               'parse', 'encode', 'decode', 'stringify', 'websocket', 'ws', 'reader', 'open_book',
               'books', 'book', 'stats', 'progress', 'epub', 'txt', 'net', 'network', 'wifi',
               'online', 'connected', 'state', 'ssid', 'ip', 'rssi', 'battery', 'charging',
               'version', 'api_version', 'name', 'id', 'model', 'firmware', 'caps', 'has',
               'query', 'can', 'timer', 'after', 'every', 'canvas', 'font', 'image', 'layer',
               'edit', 'rep', 'text_box', 'rect', 'size', 'measure'}
local function probe_names(label, u)
  local hits = {}
  for _, n in ipairs(NAMES) do
    local ok, v = pcall(function() return u[n] end)
    if ok and v ~= nil then hits[#hits + 1] = n .. ':' .. type(v):sub(1, 3) end
  end
  local mt = getmetatable(u)
  add('  ' .. label .. ' metatable: ' .. tostring(type(mt) == 'table' and 'table' or mt))
  if type(mt) == 'table' then
    local mks = keys_of(mt)
    if mks then row_list(mks, '    mt: ') end
    local idx = mt.__index
    if type(idx) == 'table' then local iks = keys_of(idx); if iks then row_list(iks, '    idx: ') end end
  end
  if #hits == 0 then add('  ' .. label .. ' name probe: nothing') else row_list(hits, '  ') end
end

-- dump a table: members with types; sub-tables one level deeper; functions called (safely)
local function dump_table(label, t, call_fns, depth)
  depth = depth or 0
  if type(t) == 'function' then
    add(label .. ' = function')
    probe_call(label, t)
    return
  end
  if type(t) == 'userdata' then
    add(label .. ' = userdata ' .. short(tostring(t), 24))
    probe_names(label, t)
    return
  end
  if type(t) ~= 'table' then add(label .. ' = ' .. type(t) .. ' ' .. val(t, 24)); return end
  local ks = keys_of(t)
  if not ks then add(label .. ' = table (pairs blocked)'); probe_names(label, t); return end
  if #ks == 0 then add(label .. ' = {}  (empty)'); probe_names(label, t); return end
  add(label .. '  (' .. #ks .. ')')
  for _, k in ipairs(ks) do
    local v = t[k]; local tv = type(v)
    if tv == 'function' then
      add('  ' .. short(tostring(k), 20) .. '  fn')
      if call_fns then probe_call(tostring(k), v, t) end
    elseif tv == 'userdata' then
      add('  ' .. short(tostring(k), 20) .. '  userdata')
      probe_names(tostring(k), v)
    elseif tv == 'table' and depth < 1 then
      local sub = keys_of(v)
      add('  ' .. short(tostring(k), 20) .. '  table(' .. (sub and #sub or '?') .. ')')
      if not sub or #sub == 0 then
        probe_names(tostring(k), v)          -- protected or empty: ask by name
      else
        for _, sk in ipairs(sub) do
          local sv = v[sk]
          add('    .' .. short(tostring(sk), 18) .. '  ' .. type(sv):sub(1, 4) ..
              (type(sv) == 'function' and '' or ' ' .. val(sv, 16)))
          if type(sv) == 'function' and call_fns then probe_call(tostring(k) .. '.' .. tostring(sk), sv, v) end
        end
      end
    else
      add('  ' .. short(tostring(k), 18) .. '  ' .. tv:sub(1, 4) .. ' ' .. val(v, 20))
    end
  end
end

-- one line that answers the question for this variant: api version, g type, which gated tables exist
local function summary()
  local api = ''
  pcall(function() api = tostring(ctx.api.major) .. '.' .. tostring(ctx.api.minor) end)
  local have = {}
  for _, n in ipairs({'net', 'storage', 'secret', 'radios', 'ui', 'json', 'reader', 'http', 'dialog', 'toast'}) do
    local ok, v = pcall(function() return ctx[n] end)
    if ok and v ~= nil then have[#have + 1] = n end
  end
  add('VARIANT ' .. VARIANT .. '  api=' .. api .. '  g=' .. type(g))
  add('gated tables: ' .. (#have > 0 and table.concat(have, ' ') or 'NONE'))
  add('')
end

local function dump_globals()
  add('_VERSION = ' .. tostring(_VERSION))
  local ks = keys_of(_G)
  if ks then
    add('globals (' .. #ks .. '):')
    row_list(ks)
  else
    add('globals: _G not walkable')
  end
  -- names that would mean a network library is simply global
  local hits = {}
  for _, n in ipairs({'net', 'http', 'https', 'socket', 'json', 'cjson', 'wifi', 'fetch', 'url',
                      'io', 'os', 'print', 'ui', 'app', 'sys', 'storage', 'fs', 'file'}) do
    local ok, v = pcall(function() return _G[n] end)
    if ok and v ~= nil then hits[#hits + 1] = n .. ':' .. type(v):sub(1, 3) end
  end
  add('global name probe: ' .. (#hits > 0 and table.concat(hits, ' ') or 'none'))
end

local function dump_g()
  add('')
  add('== g (' .. type(g) .. ') ==')
  local ks = keys_of(g)
  if ks then row_list(ks) end
  probe_names('g', g)
end

local function dump_ctx_top()
  add('')
  add('== ctx (' .. type(ctx) .. ') ==')
  local ks = keys_of(ctx)
  if not ks then add('ctx not walkable'); probe_names('ctx', ctx); return end
  local items = {}
  for _, k in ipairs(ks) do items[#items + 1] = tostring(k) .. ':' .. type(ctx[k]):sub(1, 3) end
  row_list(items)
end

local function dump_targets()
  for _, n in ipairs({'api', 'capabilities', 'net', 'storage', 'secret', 'radios', 'ui', 'json',
                      'reader', 'http', 'system', 'sys', 'data', 'longtask', 'watchdog', 'state',
                      'input'}) do
    add('')
    add('== ctx.' .. n .. ' ==')
    local ok, v = pcall(function() return ctx[n] end)
    if not ok then add('  error reading: ' .. short(tostring(v), 40))
    elseif v == nil then add('  nil')
    else pcall(dump_table, 'ctx.' .. n, v, true) end
  end
end

local function dump_require()
  add('')
  add('== require() probe ==')
  for _, m in ipairs({'@public/ui', '@public/net', '@public/http', '@public/json', '@public/util',
                      'xtapp.json', 'xtapp.net_job', 'xtapp.websocket', 'xtapp.reader',
                      'net', 'http', 'https', 'json', 'cjson', 'socket', 'socket.http', 'ssl',
                      'wifi', 'storage', 'fs', 'io', 'os', 'ui', 'api'}) do
    local ok, r = pcall(require, m)
    if ok then
      local ks = type(r) == 'table' and keys_of(r) or nil
      wrap('  ' .. m .. ' OK ' .. type(r) .. ' ', ks and table.concat(ks, ' ') or val(r, 20))
    else
      add('  ' .. short(m, 16) .. ' - ' .. short(tostring(r):gsub('^.-: ', ''), WIDE - 22))
    end
  end
end

-- walk ctx to depth 3 and list every key matching a network-ish pattern
local function hunt()
  add('')
  add('== name hunt in ctx (depth 3) ==')
  local pats = {'http', 'net', 'url', 'fetch', 'request', 'socket', 'wifi', 'json', 'download',
                'write', 'save', 'open', 'file', 'stor', 'reader', 'book', 'epub'}
  local seen, hits = {}, {}
  local function walk(t, path, depth)
    if depth > 3 or type(t) ~= 'table' or seen[t] then return end
    seen[t] = true
    local ks = keys_of(t); if not ks then return end
    for _, k in ipairs(ks) do
      local name = tostring(k):lower()
      for _, p in ipairs(pats) do
        if name:find(p, 1, true) then hits[#hits + 1] = path .. '.' .. tostring(k) .. ':' .. type(t[k]):sub(1, 3); break end
      end
      if type(t[k]) == 'table' then walk(t[k], path .. '.' .. tostring(k), depth + 1) end
    end
  end
  walk(ctx, 'ctx', 0)
  if #hits == 0 then add('  nothing matched') else for _, h in ipairs(hits) do add('  ' .. short(h, WIDE - 2)) end end
end

local function build()
  built = true
  pcall(summary)
  pcall(dump_globals)
  pcall(dump_g)
  pcall(dump_ctx_top)
  pcall(dump_targets)
  pcall(dump_require)
  pcall(hunt)
end

local ev = {}
function on_input(...)
  taps = taps + 1
  local a = table.pack(...)
  local evt = a[a.n]; if a.n > 1 then evt = a[2] end
  ev = {}
  if type(evt) == 'table' then
    local ks = keys_of(evt)
    if ks then for _, k in ipairs(ks) do ev[#ev + 1] = '  ' .. tostring(k) .. ' = ' .. val(evt[k], 24) end end
  end
  page = page + 1
  pcall(function() if ctx.invalidate then ctx.invalidate() end end)
  return true
end

function on_draw()
  if not built then pcall(build) end
  g:clear(0)
  local body = math.max(1, math.ceil(#lines / PER))
  local total = body + 1
  if page < 1 then page = 1 end
  if page > total then page = 1 end
  g:text(X, 26, 'NET PROBE   page ' .. page .. '/' .. total .. '   tap = next')
  g:line(0, 34, 480, 34)
  if page <= body then
    local first = (page - 1) * PER + 1
    for i = 0, PER - 1 do
      local s = lines[first + i]; if not s then break end
      g:text(X, TOP + i * LH, short(s, WIDE))
    end
  else
    g:text(X, TOP, 'on_input EVENT   (taps: ' .. taps .. ')')
    for i, s in ipairs(ev) do if i > PER - 2 then break end g:text(X, TOP + (i + 1) * LH, short(s, WIDE)) end
  end
  g:line(0, 780, 480, 780)
  g:text(X, 796, 'lines: ' .. #lines .. '   photograph every page')
end
