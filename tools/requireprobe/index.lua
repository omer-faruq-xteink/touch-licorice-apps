-- Require Probe: does require() load another .lua file of this package on the device, and how
-- long does compiling a large one take? Everything runs once in on_load; tap to run it again
-- (the second run shows the cached result, so it should take about 0 ms).

local lines = {}
local function add(s) lines[#lines + 1] = tostring(s) end
local function ms() local ok, v = pcall(function() return ctx.clock:millis() end); return ok and v or 0 end

local function try(name)
  local t0 = ms()
  local ok, v = pcall(require, name)
  local dt = ms() - t0
  if ok then
    local what = type(v)
    if type(v) == 'table' then what = 'table answer=' .. tostring(v.answer) .. ' runs=' .. tostring(v.runs) end
    add(name .. ': ok, ' .. what .. ', ' .. dt .. ' ms')
  else
    add(name .. ': ERROR ' .. tostring(v) .. ' (' .. dt .. ' ms)')
  end
end

local function run()
  pcall(function() ctx.budget:extend() end)
  local api = ctx.api and (tostring(ctx.api.major) .. '.' .. tostring(ctx.api.minor)) or '?'
  local fw = ctx.device and ctx.device.firmware or '?'
  add('API ' .. api .. '  firmware ' .. tostring(fw))
  add('require is ' .. type(require))
  try('lib.mod')
  try('lib.mod')
  try('lib.big')
  try('lib.big')
  try('lib.missing')
end

function on_load(c) run() end

function on_draw(c, g)
  if not g then return end
  g:clear(0)
  local f = ctx.fonts and ctx.fonts.small
  local y = 20
  for _k, line in ipairs(lines) do
    local s = line
    while #s > 0 do
      local part = s:sub(1, 40)
      s = s:sub(41)
      g:text(12, y, part, { font = f })
      y = y + 26
    end
  end
  g:text(12, 760, 'Tap to run again', { font = f })
end

function on_input(c, ev)
  if type(ev) == 'table' and ev.type == 'pointer' and ev.phase == 'up' then
    add('--')
    run()
    ctx:invalidate()
  end
  return true
end
