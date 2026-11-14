-- Port Wren: the solver. It reasons only from what the player can know (the facts of the clues found,
-- the suspects' statements, the doctor's window and the scene) by the rules the help screen gives:
--
--   * physical evidence and documents are certain;
--   * a witness is believed until a certain fact contradicts them; then nothing they say counts;
--   * a suspect's own statement never clears them; it matters only when it is contradicted;
--   * cleared: no way to the means, or a believed source puts them elsewhere at the crime slot;
--   * proven guilty: not cleared, had the means and a motive, and their account of the crime slot is
--     shown to be a lie, or they are placed at the scene at that slot.
--
-- V.check accepts a case only when all that can be reached proves exactly one culprit, motive and
-- means, the case has the shape of its pattern, and the needed clues fit in 60% of its time.

local V = {}

local function facts_of(case, known)
  local out = {}
  for _, c in ipairs(case.clues) do
    if known[c.id] then
      for _, f in ipairs(c.facts) do out[#out + 1] = { f = f, src = c.src, clue = c.id } end
    end
  end
  return out
end

-- the crime slots still possible: the doctor's window narrowed by time clues
local function slots_of(case, facts)
  local lo, hi = case.window.lo, case.window.hi
  for _, x in ipairs(facts) do
    if x.f.t == 'window' then lo, hi = math.max(lo, x.f.lo), math.min(hi, x.f.hi) end
  end
  local out = {}
  for s = lo, hi do out[#out + 1] = s end
  return out
end

function V.solve(case, known)
  local facts = facts_of(case, known)
  local res = { slots = slots_of(case, facts), cleared = {}, liars = {}, guilty = {}, motive = {}, means = nil }
  local slot = #res.slots == 1 and res.slots[1] or nil
  local night2 = case.night2 and case.night2.slot or nil
  for _, x in ipairs(facts) do
    if x.f.t == 'weapon' then res.means = x.f.means end
    if x.f.t == 'motive' and not res.motive[x.f.who] then res.motive[x.f.who] = x.f.motive end
  end

  -- witnesses caught by a certain fact are not believed any more (repeat: one caught may free another)
  local lying_witness, changed = {}, true
  local function believed(x) return x.src == 'cert' or not lying_witness[x.src] end
  while changed do
    changed = false
    for _, a in ipairs(facts) do
      if a.f.t == 'at' and a.src ~= 'cert' and not lying_witness[a.src] then
        for _, b in ipairs(facts) do
          if b.src == 'cert' and (b.f.t == 'at' or b.f.t == 'secret') and b.f.who == a.f.who and b.f.slot == a.f.slot and b.f.place ~= a.f.place then
            lying_witness[a.src] = true
            changed = true
            break
          end
        end
      end
    end
  end
  res.lying_witnesses = lying_witness

  -- believed places: who was where at which slot (a secret found is a certain place); believed
  -- denials: who was not where they said
  local where, denied = {}, {}
  for _, x in ipairs(facts) do
    if x.f.t == 'not_at' and believed(x) then
      denied[x.f.who .. ':' .. x.f.slot .. ':' .. x.f.place] = true
    end
    if (x.f.t == 'at' or x.f.t == 'secret') and believed(x) then
      where[x.f.who] = where[x.f.who] or {}
      where[x.f.who][x.f.slot] = where[x.f.who][x.f.slot] or {}
      where[x.f.who][x.f.slot][x.f.place] = true
    end
  end
  local function placed(pid, s, place)
    return where[pid] and where[pid][s] and where[pid][s][place] or false
  end
  local function elsewhere(pid, s, place)
    if not (where[pid] and where[pid][s]) then return false end
    for p in pairs(where[pid][s]) do if p ~= place then return true end end
    return false
  end
  -- a statement contradicted by a believed place
  local function lied(pid, s)
    local said = case.says[pid] and case.says[pid][s]
    return said ~= nil and (elsewhere(pid, s, said) or denied[pid .. ':' .. s .. ':' .. said] == true)
  end
  for _, pid in ipairs(case.suspects) do
    for s in pairs(case.says[pid] or {}) do if lied(pid, s) then res.liars[pid] = true end end
  end

  local access = {}
  for _, x in ipairs(facts) do
    if x.f.t == 'access' then
      access[x.f.who] = access[x.f.who] or {}
      access[x.f.who][x.f.means] = x.f.yes
    end
  end

  for _, pid in ipairs(case.suspects) do
    local cleared = false
    if res.means and access[pid] and access[pid][res.means] == false then cleared = true end
    if slot and elsewhere(pid, slot, case.scene) and not placed(pid, slot, case.scene) then cleared = true end
    res.cleared[pid] = cleared or nil
    if not cleared and res.means and access[pid] and access[pid][res.means] == true and res.motive[pid] then
      local proof = false
      if slot and (lied(pid, slot) or placed(pid, slot, case.scene)) then proof = true end
      if night2 and (lied(pid, night2) or placed(pid, night2, case.night2.scene)) then proof = true end
      if proof then res.guilty[#res.guilty + 1] = pid end
    end
  end
  return res
end

local function not_cleared(case, res)
  local n, has_killer = 0, false
  for _, pid in ipairs(case.suspects) do
    if not res.cleared[pid] then n = n + 1; if pid == case.killer then has_killer = true end end
  end
  return n, has_killer
end

-- the clues that catch the killer's own account (or put them at the scene) at the crime slot
local function decisive(case, c)
  for _, f in ipairs(c.facts) do
    if f.t == 'at' and f.who == case.killer and f.slot == case.slot and f.place ~= case.says[case.killer][case.slot] then
      return true
    end
  end
  return false
end
V.decisive = decisive

-- the shape of each pattern beyond Classic, on all the reachable clues
local function timed(c)
  for _, f in ipairs(c.facts) do if f.t == 'window' then return true end end
  return false
end
V.shape = {
  alibi = function(case, reach, by_id, minus, not_cleared)
    local cover
    for id in pairs(reach) do
      local c = by_id[id]
      if c.src ~= 'cert' then
        for _, f in ipairs(c.facts) do
          if f.t == 'at' and f.who == case.killer and f.slot == case.slot and f.place ~= case.scene then cover = c end
        end
      end
    end
    if not cover then return false, 'alibi: no witness covers the killer' end
    local before = V.solve(case, minus(reach, function(id) return by_id[id].src == 'cert' and decisive(case, by_id[id]) end))
    if not before.cleared[case.killer] then return false, 'alibi: the alibi does not hold' end
    local after = V.solve(case, reach)
    if after.cleared[case.killer] or not after.lying_witnesses[cover.src] then return false, 'alibi: the witness is not caught' end
    return true
  end,
  timeline = function(case, reach, by_id, minus, not_cleared)
    local any = false
    for id in pairs(reach) do
      if timed(by_id[id]) then
        any = true
        if #V.solve(case, minus(reach, function(x) return x == id end)).slots < 2 then
          return false, 'timeline: a time clue is not needed'
        end
      end
    end
    if not any then return false, 'timeline: no time clue' end
    local before = V.solve(case, minus(reach, function(id) return timed(by_id[id]) end))
    if #before.slots < 2 or not_cleared(case, before) < 2 then return false, 'timeline: the time decides nothing' end
    return true
  end,
  liar = function(case, reach, by_id, minus, not_cleared)
    local sec = case.secret
    if not sec then return false, 'liar: no secret' end
    local sid
    for id in pairs(reach) do
      for _, f in ipairs(by_id[id].facts) do if f.t == 'secret' and f.who == sec.who then sid = id end end
    end
    if not sid then return false, 'liar: the secret cannot be found' end
    local before = V.solve(case, minus(reach, function(id) return id == sid end))
    if not before.liars[sec.who] or before.cleared[sec.who] then return false, 'liar: the lie is not caught first' end
    if not V.solve(case, reach).cleared[sec.who] then return false, 'liar: the secret does not clear' end
    return true
  end,
}

local function minus(known, drop)
  local out = {}
  for id in pairs(known) do if not drop(id) then out[id] = true end end
  return out
end

-- true, or false and why
function V.check(case, town, G)
  local reach = G.reachable(case, town)
  for _, c in ipairs(case.clues) do
    if c.need and not reach[c.id] then return false, 'a needed clue cannot be reached' end
  end
  local res = V.solve(case, reach)
  if #res.guilty ~= 1 or res.guilty[1] ~= case.killer then return false, 'not exactly the killer proven' end
  if res.motive[case.killer] ~= case.motive or res.means ~= case.means then return false, 'motive or means not known' end

  local by_id = {}
  for _, c in ipairs(case.clues) do by_id[c.id] = c end
  local pat = case.pattern
  if pat == 'classic' then
    local before = V.solve(case, minus(reach, function(id) return decisive(case, by_id[id]) end))
    local n, k = not_cleared(case, before)
    if n ~= 2 or not k then return false, 'classic: elimination does not leave two' end
  elseif V.shape and V.shape[pat] then
    local ok, why = V.shape[pat](case, reach, by_id, minus, not_cleared)
    if not ok then return false, why end
  end
  local cost = G.cost(case, town)
  if cost > math.floor(0.6 * G.TOTAL[case.size]) then return false, 'too many actions: ' .. cost end
  return true
end

return V
