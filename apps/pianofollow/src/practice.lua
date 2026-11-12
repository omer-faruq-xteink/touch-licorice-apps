-- practice: the score waits for the right notes (Practice mode).
--   P.new(map, hands, from_onset) -> st       hands 'r', 'l' or 'b' (both)
--   P.note_on(st, pitch, now_ms) -> 'advance' | 'wrong' | nil;  P.note_off(st, pitch)
--   st.pos (the onset waited for), st.wrong (count), st.done;  P.summary(st) -> { wrong, bars = { { bar, wrong } } }
-- An onset is played when each of its notes for the chosen hand(s) was pressed after it became the
-- one waited for and is still held or was pressed within the last second (a chord in any order).
-- Onsets with nothing for the chosen hand(s) are skipped. A note that is in none of the onsets from
-- the one before the last step to this one (the other hand's notes while this hand rests) is a mistake,
-- counted for the bar.
local P = {}
local CHORD_MS = 1000

local function required(st, i)
  local o = st.map.onsets[i]
  local t = {}
  if st.hands ~= 'l' then for _k, p in ipairs(o[6]) do t[#t + 1] = p end end
  if st.hands ~= 'r' then for _k, p in ipairs(o[7]) do t[#t + 1] = p end end
  return t
end

local function in_onset(st, i, p)
  local o = st.map.onsets[i]
  if not o then return false end
  for _k, q in ipairs(o[6]) do if q == p then return true end end
  for _k, q in ipairs(o[7]) do if q == p then return true end end
  return false
end

-- the first onset from i on with something to play for the chosen hand(s); `from` remembers where the
-- skipped onsets begin, so the other hand's notes in them are not mistakes
local function settle(st, i, now)
  st.from = i
  while i <= #st.map.onsets and #required(st, i) == 0 do i = i + 1 end
  st.pos = i
  st.start = now or st.start or 0
  st.done = i > #st.map.onsets
end

function P.new(map, hands, from_onset)
  local st = { map = map, hands = hands or 'b', wrong = 0, per_bar = {}, pressed = {}, held = {}, start = -math.huge }
  settle(st, from_onset or 1, -math.huge)
  return st
end

function P.note_off(st, pitch) st.held[pitch] = nil end

function P.note_on(st, pitch, now)
  st.pressed[pitch], st.held[pitch] = now, true
  if st.done then return nil end
  local excused = false
  for k = math.max(1, math.min(st.from or st.pos, st.pos) - 1), st.pos do
    if in_onset(st, k, pitch) then excused = true; break end
  end
  if not excused then
    st.wrong = st.wrong + 1
    local bar = st.map.onsets[st.pos][2]
    st.per_bar[bar] = (st.per_bar[bar] or 0) + 1
    return 'wrong'
  end
  for _k, p in ipairs(required(st, st.pos)) do
    local t = st.pressed[p]
    if not t or t < st.start or not (st.held[p] or now - t <= CHORD_MS) then return nil end
  end
  settle(st, st.pos + 1, now)
  return 'advance'
end

function P.summary(st)
  local bars = {}
  for bar, n in pairs(st.per_bar) do bars[#bars + 1] = { bar = bar, wrong = n } end
  table.sort(bars, function(a, b) return a.bar < b.bar end)
  return { wrong = st.wrong, bars = bars }
end

return P
