-- FSRS 4.5, the open spaced-repetition scheduler Anki uses, with its default parameters, for any
-- app that reviews cards (Dictionary's looked-up words; Anki keeps its own copy in its main.lua).
-- A card has a stability S (days until recall drops to 90 %) and a difficulty D (1..10). Recall
-- after t days: R = (1 + 19/81 * t / S) ^ -0.5, so at 90 % retention the next interval is S days.
-- New and forgotten cards first go through steps of minutes in the same session (as in Anki).
--
-- A record: { due, s, d, reps, lapses, last (time of the last review), state 'l' (learning steps)
-- or 'r' (review) }; a card never reviewed has no record. Times are epoch seconds.

local F = {}

local FW = { 0.4872, 1.4003, 3.7145, 13.8206, 5.1618, 1.2298, 0.8975, 0.031, 1.6474, 0.1367, 1.0461,
             2.1072, 0.0793, 0.3246, 1.587, 0.2272, 2.8755 }
local function w(i) return FW[i + 1] end
local DECAY, FACTOR, RETENTION = -0.5, 19 / 81, 0.9
-- the longest interval, in days: now + days * 86400 stays a 32-bit number, which the reader's Lua may use
F.MAX_IVL = 1000

local function clamp_d(x) return math.max(1, math.min(10, x)) end
local function init_d(g) return clamp_d(w(4) - w(5) * (g - 3)) end
local function next_d(d, g) return clamp_d(w(7) * w(4) + (1 - w(7)) * (d - w(6) * (g - 3))) end
local function recall(days, s) return (1 + FACTOR * days / s) ^ DECAY end
-- days until recall drops to RETENTION
local function interval(s)
  local i = s / FACTOR * (RETENTION ^ (1 / DECAY) - 1)
  return math.max(1, math.min(F.MAX_IVL, math.floor(i + 0.5)))
end
local function recall_s(d, s, r, g)
  local hard = g == 2 and w(15) or 1
  local easy = g == 4 and w(16) or 1
  return s * (1 + math.exp(w(8)) * (11 - d) * s ^ (-w(9)) * (math.exp(w(10) * (1 - r)) - 1) * hard * easy)
end
local function forget_s(d, s, r)
  return math.min(s, w(11) * d ^ (-w(12)) * ((s + 1) ^ w(13) - 1) * math.exp(w(14) * (1 - r)))
end

-- the record after rating g (1 Again, 2 Hard, 3 Good, 4 Easy) at time now; rec may be nil (new)
function F.schedule(rec, g, now)
  rec = rec or {}
  local s, d, state = rec.s, rec.d, rec.state
  local reps, lapses = (rec.reps or 0) + 1, rec.lapses or 0
  local due
  if not s then                                 -- a new card
    s, d = w(g - 1), init_d(g)
    if g == 4 then state, due = 'r', now + interval(s) * 86400
    else state, due = 'l', now + ({ 60, 6 * 60, 10 * 60 })[g] end
  elseif state == 'l' then                      -- in the steps: stability stays, then graduates
    d = next_d(d, g)
    if g == 1 then due = now + (lapses > 0 and 10 * 60 or 60)
    elseif g == 2 then due = now + 6 * 60
    else
      if g == 4 then s = s * w(16) end
      state, due = 'r', now + interval(s) * 86400
    end
  else                                          -- a review
    local r = recall(math.max(0, now - (rec.last or now)) / 86400, s)
    if g == 1 then
      lapses = lapses + 1
      s, d, state, due = forget_s(d, s, r), next_d(d, 1), 'l', now + 10 * 60
    else
      s, d = recall_s(d, s, r, g), next_d(d, g)
      due = now + interval(s) * 86400
    end
  end
  return { due = due, s = s, d = d, reps = reps, lapses = lapses, last = now, state = state }
end

local function fmt(x) return (string.format('%.2f', x):gsub('%.?0+$', '')) end

-- a time span as the grade buttons show it: 1m, 6m, 3h, 4d, 2mo, 1.5y
function F.span(sec)
  if sec < 3600 then return math.max(1, sec // 60) .. 'm' end
  local days = sec / 86400
  if days < 1 then return (sec // 3600) .. 'h' end
  if days < 31 then return math.floor(days + 0.5) .. 'd' end
  if days < 365 then return math.floor(days / 30 + 0.5) .. 'mo' end
  return fmt(math.floor(days / 36.5 + 0.5) / 10) .. 'y'
end

-- a record as text ("due S D reps lapses last state") and back
function F.format(r)
  return r.due .. ' ' .. fmt(r.s) .. ' ' .. fmt(r.d) .. ' ' .. r.reps .. ' ' .. r.lapses .. ' ' .. r.last .. ' ' .. r.state
end
function F.parse(s)
  local due, a, b, reps, lapses, last, state = tostring(s or ''):match('^(%-?%d+) ([%d%.]+) ([%d%.]+) (%d+) (%d+) (%-?%d+) ([lr])$')
  if not due then return nil end
  return { due = tonumber(due), s = tonumber(a), d = tonumber(b), reps = tonumber(reps), lapses = tonumber(lapses),
           last = tonumber(last), state = state }
end

return F
