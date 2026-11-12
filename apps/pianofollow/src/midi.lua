-- midi: BLE MIDI packets (the notify value of the BLE MIDI characteristic) -> note events.
--   packet = header (bit 7 set, timestamp bits 12-7), then messages, each preceded by a timestamp
--   byte (bit 7 set, bits 6-0) or, with running status, by nothing; SysEx may span packets.
--   M.new() -> parser;  M.feed(parser, packet) -> { { on = bool, note, vel, ts }, ... }
-- Any channel; note-on with velocity 0 is a note-off; everything that is not a note is skipped.
local M = {}

function M.new() return { running = nil, sysex = false } end

local function data_len(s)
  local hi = s & 0xF0
  if hi == 0xC0 or hi == 0xD0 then return 1 end
  if s < 0xF0 then return 2 end
  if s == 0xF1 or s == 0xF3 then return 1 end
  if s == 0xF2 then return 2 end
  return 0
end

function M.feed(st, pkt)
  local out = {}
  local n = #pkt
  if n < 2 then return out end
  local hdr = pkt:byte(1)
  if hdr < 0x80 then return out end
  local hi, ts, i = hdr & 0x3F, 0, 2
  while i <= n do
    local b = pkt:byte(i)
    if st.sysex then
      -- inside SysEx: data bytes until (timestamp) F7; a timestamp before anything else ends it too
      if b < 0x80 then i = i + 1
      elseif b == 0xF7 then st.sysex = false; i = i + 1
      elseif pkt:byte(i + 1) == 0xF7 then st.sysex = false; i = i + 2
      elseif (pkt:byte(i + 1) or 0) >= 0xF8 then i = i + 2          -- realtime inside SysEx
      else st.sysex = false end
    else
      if b >= 0x80 then                                             -- timestamp byte
        ts = (hi << 7) | (b & 0x7F)
        i = i + 1
        b = pkt:byte(i)
        if not b then break end
        if b >= 0x80 then                                           -- a status byte
          i = i + 1
          if b == 0xF0 then st.sysex = true; st.running = nil; goto continue end
          if b >= 0xF8 then goto continue end                      -- realtime: running status stays
          if b >= 0xF0 then st.running = nil; i = i + data_len(b); goto continue end
          st.running = b
          b = pkt:byte(i)
          if not b or b >= 0x80 then goto continue end
        end
      end
      -- data bytes of the running status
      local s = st.running
      if not s then i = i + 1; goto continue end
      local need = data_len(s)
      local d1, d2 = pkt:byte(i), need == 2 and pkt:byte(i + 1) or 0
      if not d1 or d1 >= 0x80 or not d2 or d2 >= 0x80 then i = i + 1; goto continue end
      i = i + need
      local kind = s & 0xF0
      if kind == 0x90 then out[#out + 1] = { on = d2 > 0, note = d1, vel = d2, ts = ts }
      elseif kind == 0x80 then out[#out + 1] = { on = false, note = d1, vel = d2, ts = ts } end
    end
    ::continue::
  end
  return out
end

return M
