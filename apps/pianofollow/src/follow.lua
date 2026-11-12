-- follow: where the player is in the piece, from the notes they play (Page turn and Follow modes).
--   F.new(map, page, turn_at) -> st      turn_at 'end' (the page's last note, the default), 'bar' (its last
--                                        bar) or 'system' (its last system)
--   F.note(st, pitch, now_ms) -> 'turn' | 'bar' | nil    ('turn' has already set st.page)
--   F.goto_page(st, page)                a page turned by hand
--   st.pos = the next expected onset (1-based), st.bar = the bar of the last matched onset, st.page
-- A note of the expected onset moves on. Any other note asks where the last notes played fit best in
-- the bars around the position (the same chord or the onset before, note by note): the position moves
-- only when at least three notes fit, and on a tie back wins over ahead, since a player who repeats a
-- bar must not be taken for one who is ahead. After four notes that fit nowhere near, the whole piece is
-- searched. A page turns only after two expected onsets in a row at its turn point: a late turn is fine,
-- an early one is not.
local F = {}
local LOST, RECENT, NEAR_BACK, NEAR_AHEAD = 4, 5, 16, 8
-- a chord's notes come within a few ms of each other: one that belongs to the onset just completed is
-- part of that chord
local CHORD_MS = 100

local function has(o, p)
  for _k, q in ipairs(o[6]) do if q == p then return true end end
  for _k, q in ipairs(o[7]) do if q == p then return true end end
  return false
end
local function size(o) return #o[6] + #o[7] end

-- the onset where a visit to `page` starts: the visit nearest `near` (ahead preferred), so that a page
-- turned by hand during a written repeat keeps the player in the pass they are in
local function start_of_page(map, page, near)
  local best, bestd
  for i, o in ipairs(map.onsets) do
    if o[3] == page and (i == 1 or map.onsets[i - 1][3] ~= page) then
      local d = i - (near or 1)
      d = d >= 0 and d or -3 * d
      if not best or d < bestd then best, bestd = i, d end
    end
  end
  if best then return best end
  for i, o in ipairs(map.onsets) do if o[3] >= page then return i end end
  return #map.onsets + 1
end

function F.new(map, page, turn_at)
  local st = { map = map, n = #map.onsets, page = page or 1, turn_at = turn_at or 'end', run = 0, miss = 0,
               hits = {}, recent = {}, bar = nil }
  st.pos = start_of_page(map, st.page, 1)
  return st
end

function F.goto_page(st, page)
  st.page = math.max(1, math.min(#st.map.turn, page))
  st.pos = start_of_page(st.map, st.page, st.pos)
  st.run, st.miss, st.hits, st.exit = 0, 0, {}, nil
end

-- where the playing (repeats unfolded) next leaves the shown page: the first onset after i on another
-- page; the page turns in the bar before that (the page's last bar, or the bar before a repeat), to the
-- page the music continues on (back a page at a repeat)
local function exit_after(st, i)
  for j = i + 1, st.n do if st.map.onsets[j][3] ~= st.page then return j end end
  return nil
end

-- after an expected onset: a turn when confidently at the turn point, else a new bar
local function after_advance(st)
  local i = st.pos - 1
  local o = st.map.onsets[i]
  if st.exit and i >= st.exit then st.exit = nil end  -- past the onset the early turn was for
  if st.run >= 2 and not st.exit then
    if o[3] ~= st.page then                          -- the music is on another page: show it
      st.page, st.bar = o[3], o[2]
      return 'turn'
    end
    local j = exit_after(st, i)
    if j then
      local tb = st.map.onsets[j - 1][2]              -- the last bar played on this page
      local t = st.map.turn[st.page]
      if st.turn_at == 'system' and t and st.map.onsets[t[1]] and st.map.onsets[t[2]] and tb >= st.map.onsets[t[2]][2] then
        tb = st.map.onsets[t[1]][2]                   -- leaving at the page's end: from its last system
      end
      local at = st.turn_at == 'end' and i >= j - 1 or st.turn_at ~= 'end' and o[2] >= tb
      if at then                                      -- turned while the bar is still played: finish it here
        st.page, st.bar, st.exit = st.map.onsets[j][3], o[2], j
        return 'turn'
      end
    end
  end
  if o[2] ~= st.bar then st.bar = o[2]; return 'bar' end
  return nil
end

-- the last notes played, walking back from onset j: each earlier note must be in the same onset (a
-- chord) or the one before
local function fits(st, j)
  local k, count, span = j, 0, 1
  for r = #st.recent, 1, -1 do
    local p = st.recent[r]
    local o = st.map.onsets[k]
    if o and has(o, p) then count = count + 1
    elseif k > 1 and has(st.map.onsets[k - 1], p) then k = k - 1; span = span + 1; count = count + 1
    else break end
  end
  return count >= 3 and span >= 2, count
end

-- the best fit for the recent notes among onsets lo..hi: near the position, most notes first, then the
-- smallest move (a move back counting as smaller than the same move ahead); in the whole piece
-- (`nearest`), the smallest move that fits, since an exact repeat far away fits as well as the truth.
-- Never on an earlier page: written repeats come from the playing order, and a player who goes back a
-- page on purpose turns it by hand (an exact repeat elsewhere would otherwise turn the page back).
local function best_fit(st, lo, hi, nearest)
  local best, bestc, bestd
  for j = math.max(2, lo), math.min(st.n, hi) do
    local ok, c = fits(st, j)
    if nearest and c < 4 then ok = false end          -- the whole piece: four notes, not three
    if ok and st.map.onsets[j][3] < st.page then ok = false end   -- never back a page by guessing
    if ok then
      local d = j + 1 - st.pos
      d = d >= 0 and d * 2 or -d
      local better = not best or (nearest and d < bestd) or (not nearest and (c > bestc or (c == bestc and d < bestd)))
      if better then best, bestc, bestd = j, c, d end
    end
  end
  return best
end

-- the position moves to just after onset j (never an earlier page, see best_fit); a later page is shown
-- only after expected onsets confirm it
local function move_to(st, j)
  -- ahead, three notes in order are as good as two clean onsets; back (a repeat) starts from nothing
  local ahead = j + 1 > st.pos
  st.pos, st.run, st.miss, st.hits, st.exit = j + 1, ahead and 2 or 0, 0, {}, nil
  st.bar = st.map.onsets[j][2]
  local pg = st.map.onsets[j][3]
  return pg == st.page and 'bar' or nil
end

function F.note(st, pitch, now_ms)
  st.recent[#st.recent + 1] = pitch
  if #st.recent > RECENT then table.remove(st.recent, 1) end
  local last = st.map.onsets[st.pos - 1]
  if last and st.done_t and now_ms and now_ms - st.done_t <= CHORD_MS and has(last, pitch) then
    return nil                                       -- the rest of the chord just played
  end
  local cur = st.map.onsets[st.pos]
  if cur and has(cur, pitch) then                    -- the expected onset
    st.miss = 0
    local h = st.hits[st.pos] or {}
    h[pitch] = true
    st.hits[st.pos] = h
    local n = 0
    for _p in pairs(h) do n = n + 1 end
    if n < math.ceil(size(cur) / 2) then return nil end
    st.run = st.run + 1
    st.pos, st.done_t = st.pos + 1, now_ms
    st.hits[st.pos] = nil
    return after_advance(st)
  end
  -- not the expected onset: where do the last notes fit nearby?
  local j = best_fit(st, st.pos - NEAR_BACK, st.pos + NEAR_AHEAD)
  if j and j + 1 == st.pos then st.miss = 0; return nil end   -- explained where we are (a rolled chord)
  if not j and st.pos > 1 and has(st.map.onsets[st.pos - 1], pitch) then return nil end   -- the last onset again
  if j then return move_to(st, j) end
  st.run = 0                                         -- a slip: the next turn waits for two clean onsets
  st.miss = st.miss + 1
  if st.miss >= LOST then                            -- nothing near fits: the whole piece
    local g = best_fit(st, 2, st.n, true)
    st.miss = 0
    if g and g + 1 ~= st.pos then return move_to(st, g) end
  end
  return nil
end

return F
