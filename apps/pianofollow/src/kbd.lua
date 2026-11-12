-- kbd: the Bluetooth MIDI keyboard (BLE central: scan, connect, subscribe, reconnect).
--   K.start(on_note, on_state)   on_note(ev) per parsed note (midi.lua); on_state() when the state changes
--   K.scan(), K.pick(i), K.forget(), K.devices() -> found list, K.state(), K.name(), K.last()
--   states: 'off' (no Bluetooth), 'none', 'scanning', 'connecting', 'connected', 'lost'
-- The keyboard is remembered in kbd.txt (address, address type, name, secure 0/1) and connected
-- straight away next time. A keyboard that refuses the subscription is tried again with pairing
-- (secure = true), which is then remembered. A lost keyboard is tried again every 5 s, 12 times.
local M = require('midi')
local K = {}
local SVC, CHR = '03b80e5a-ede8-4b33-a751-6ce34ec4c700', '7772e5db-3868-4112-a1a9-f2669d106bf3'
local RETRY_MS, RETRIES, FILE = 5000, 12, 'kbd.txt'

local state, dev, conn, found, last = 'none', nil, nil, {}, nil
local on_note, on_state = function() end, function() end
local tries, parser = 0, M.new()

local function set(s) if s ~= state then state = s; on_state() end end
local function ble() return ctx.ble end

local function remember(d)
  kit.write(FILE, table.concat({ d.address, d.address_type or 'public', d.name or '', d.secure and '1' or '0', '' }, '\n'))
end
local function recall()
  local s = kit.read(FILE)
  if not s or s == '' then return nil end
  local a, t, n, sec = s:match('^([^\n]*)\n([^\n]*)\n([^\n]*)\n?([01]?)')
  if not a or a == '' then return nil end
  return { address = a, address_type = t, name = n, secure = sec == '1' }
end

local connect

local function retry_later(ms, fn) ctx:after(ms, function() fn() end) end

local function lost()
  conn = nil
  if tries >= RETRIES then set('none'); return end
  tries = tries + 1
  set('lost')
  retry_later(RETRY_MS, function() if state == 'lost' and dev then connect() end end)
end

-- the connection in progress or open (K._mine); a new one first closes it, and the callbacks of an
-- older one do nothing (they would save the wrong keyboard or mark the new one lost)
local function drop_current()
  local m = K._mine
  K._mine = nil
  if m then
    m.closing = true
    if m.conn then pcall(function() m.conn:close() end) end
  end
  conn = nil
end

local busy_tries = 0
connect = function()
  if not dev or not ble() then return end
  drop_current()
  set(state == 'lost' and 'lost' or 'connecting')
  parser = M.new()
  local d = dev                                       -- the keyboard this connection is for
  local mine = { closing = false }
  local function current() return K._mine == mine and not mine.closing end
  local c, err = ble():connect({ address = d.address, address_type = d.address_type, timeout_ms = 10000, secure = d.secure or false }, {
    on_connect = function(_c, cn)
      if not current() then return end
      if not cn then lost(); return end
      cn:subscribe(CHR, true, function(_c2, cn2, e)
        if not current() then return end
        if e then
          mine.closing = true
          pcall(function() cn2:close() end)
          conn = nil
          if not d.secure then                              -- maybe it wants pairing: once more, secure
            d.secure = true
            retry_later(300, connect)
          else
            lost()
          end
          return
        end
        tries, busy_tries = 0, 0
        conn = cn2
        remember(d)
        set('connected')
      end)
    end,
    on_notify = function(_c, _cn, _h, data)
      if not current() then return end
      for _k, ev in ipairs(M.feed(parser, data)) do
        if ev.on then last = ev.note end
        pcall(on_note, ev)                              -- a fault in the score must not end the session
      end
    end,
    on_disconnect = function(_c, _cn, e)
      if not current() or e == nil then return end      -- an older connection, or our own close
      lost()
    end,
  })
  if not c then
    if err == 'busy' and busy_tries < 15 then busy_tries = busy_tries + 1; retry_later(200, connect)
    else busy_tries = 0; lost() end
    return
  end
  mine.conn = c
  K._mine = mine
end

-- search for BLE MIDI keyboards; the remembered one is connected as soon as it is seen, and if the
-- search ends without it, it is tried directly once
local function look()
  if not ble() then return end
  found = {}
  local s, err
  s, err = ble():scan({ duration_ms = 8000, services = { SVC } }, {
    on_device = function(_c, sc, d)
      found[#found + 1] = d
      if dev and not conn and state == 'scanning' and d.address == dev.address then
        dev.address_type = d.address_type or dev.address_type
        pcall(function() sc:stop() end)
        tries = 0
        connect()
      end
      on_state()
    end,
    on_done = function(_c, _s, _devs, _e)
      if state == 'scanning' then
        if dev and not conn then tries = 0; connect() else set(conn and 'connected' or 'none') end
      end
      on_state()
    end,
  })
  if s then set('scanning') elseif err then set('none') end
end

function K.start(note_fn, state_fn)
  on_note, on_state = note_fn or on_note, state_fn or on_state
  if not ble() then state = 'off'; return end
  dev = recall()
  if dev then look() else state = 'none' end
end

function K.scan() if state ~= 'connecting' then look() end end

-- the Keyboard screen opened: search unless connected or already at it
function K.auto()
  if ble() and state ~= 'connected' and state ~= 'connecting' and state ~= 'scanning' then look() end
end

function K.pick(i)
  local d = found[i]
  if not d or state == 'connecting' then return end      -- one connection at a time
  dev = { address = d.address, address_type = d.address_type, name = d.name or d.address, secure = false }
  tries = 0
  connect()
end

function K.forget()
  drop_current()
  dev = nil
  pcall(function() ctx.storage:remove(FILE) end)
  kit.write(FILE, '')
  set(ble() and 'none' or 'off')
end

function K.devices() return found end
function K.state() return state end
function K.name() return dev and dev.name or nil end
function K.last() return last end

return K
