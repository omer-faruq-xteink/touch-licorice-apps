-- Icebound: the team. Six people with a role and a level, a trait, health and five conditions that
-- worsen or heal day by day, a mood, relations to each other and memories. A person dies only after a
-- condition has been grave (and warned of) for two days.
--
--   local TM = require('game.team')(Rng, R, T)

return function(Rng, R, T)
  local TM = {}
  local FIXED = { 'navigator', 'doctor', 'driver' }
  local OTHERS = { 'cook', 'mechanic', 'surveyor', 'hunter', 'geologist', 'photographer' }

  local function alive(p) return p and p.alive end

  function TM.living(state)
    local out = {}
    for id = 1, state.next_id - 1 do
      local p = state.team[id]
      if alive(p) then out[#out + 1] = id end
    end
    return out
  end

  function TM.with_role(state, role) return R.role(state, role) end

  local function fresh_cond() return { frostbite = 0, snowblind = 0, exhaustion = 0, injury = 0, sickness = 0 } end

  local function add(state, o)
    local p = { id = state.next_id, name = o.name, role = o.role, lv = o.lv, trait = o.trait, health = o.health,
                cond = fresh_cond(), mood = o.mood, rel = {}, mem = o.mem or {}, alive = true, veteran = o.veteran }
    state.team[p.id] = p
    state.next_id = state.next_id + 1
    return p
  end

  local function set_rel(a, b, v) a.rel[b.id], b.rel[a.id] = v, v end

  -- six people: a navigator, a doctor and a dog driver, then three of the other roles; one tense pair
  -- and one friendly pair. A veteran (a survivor of the last expedition) keeps their role, one level up.
  function TM.make(state, r, veteran)
    local roles = { FIXED[1], FIXED[2], FIXED[3] }
    local others = {}
    for _, x in ipairs(OTHERS) do others[#others + 1] = x end
    r:shuffle(others)
    if veteran then
      local fixed = false
      for _, x in ipairs(FIXED) do if x == veteran.role then fixed = true end end
      if not fixed then
        for k, x in ipairs(others) do if x == veteran.role then table.remove(others, k); break end end
        table.insert(others, 1, veteran.role)
      end
    end
    for k = 1, 3 do roles[#roles + 1] = others[k] end
    local names = {}
    for _, n in ipairs(T.NAMES) do if not veteran or n ~= veteran.name then names[#names + 1] = n end end
    r:shuffle(names)
    local vet_used = false
    for k, rl in ipairs(roles) do
      if veteran and not vet_used and rl == veteran.role then
        vet_used = true
        local mem = {}
        for _, m in ipairs(veteran.mem or {}) do mem[#mem + 1] = m end
        add(state, { name = veteran.name, role = rl, lv = math.min(5, (veteran.lv or 2) + 1), trait = veteran.trait or r:pick(T.TRAITS),
                     health = r:int(80, 95), mood = r:int(60, 75), mem = mem, veteran = true })
      else
        add(state, { name = names[k], role = rl, lv = r:int(1, 3), trait = r:pick(T.TRAITS), health = r:int(80, 95), mood = r:int(55, 75) })
      end
    end
    local ids = TM.living(state)
    r:shuffle(ids)
    set_rel(state.team[ids[1]], state.team[ids[2]], -1)
    set_rel(state.team[ids[3]], state.team[ids[4]], 1)
  end

  ------------------------------------------------------------------ a day

  local function line(rep, s) if rep and rep.lines then rep.lines[#rep.lines + 1] = s end end

  local function worst_case(state)
    local best, bs
    for _, id in ipairs(TM.living(state)) do
      local p = state.team[id]
      local s = 0
      for _, k in ipairs(T.CONDS) do s = s + p.cond[k] * p.cond[k] end
      if s > 0 and (not best or s > bs) then best, bs = p, s end
    end
    return best
  end

  local function grave(p)
    for _, k in ipairs(T.CONDS) do if p.cond[k] >= 3 then return k end end
    return nil
  end

  -- everyone's mood drops at a loss, friends' most
  function TM.mourn(state, dead)
    for _, id in ipairs(TM.living(state)) do
      local p = state.team[id]
      local drop = (p.rel[dead.id] == 1) and 20 or 10
      p.mood = math.max(0, p.mood - drop)
      if p.rel[dead.id] == 1 then p.mem[#p.mem + 1] = 'lost a friend in ' .. dead.name end
    end
  end

  local function die(state, p, rep, r)
    p.alive = false
    line(rep, T.life('died', { a = p.name }, r))
    rep.people = rep.people or {}
    rep.people.died = (rep.people.died or 0) + 1
    TM.mourn(state, p)
  end

  function TM.day(state, r, rep)
    local w = state.weather or { kind = 'overcast', temp = -20 }
    local temp = w.temp or -20
    local resting = state.pace == 'rest'
    local hard = state.pace == 'hard'
    local marching = not resting and (rep.moved or 0) > 0
    local doctor = R.role(state, 'doctor')
    local chosen = state.treat and state.team[state.treat]
    local chosen_sick = false
    if alive(chosen) then for _, k in ipairs(T.CONDS) do if chosen.cond[k] > 0 then chosen_sick = true end end end
    local patient = doctor and ((chosen_sick and chosen) or worst_case(state))
    -- a fall: someone on the rope is hurt
    for _ = 1, #(rep.falls or {}) do
      local ids = TM.living(state)
      if #ids > 0 then
        local p = state.team[r:pick(ids)]
        p.cond.injury = math.min(3, p.cond.injury + 2)
        line(rep, T.life('worse', { a = p.name, cond = T.COND_NAME.injury }, r))
      end
    end
    local cheer = 0
    for _, id in ipairs(TM.living(state)) do if state.team[id].trait == 'cheerful' then cheer = cheer + 1 end end
    for _, id in ipairs(TM.living(state)) do
      local p = state.team[id]
      local c = p.cond
      local careful = (p.trait == 'careful') and 5 or 0
      local function worsen(kind, pct)
        if pct > 0 and r:int(1, 100) <= pct then
          c[kind] = math.min(3, c[kind] + 1)
          if c[kind] >= 2 then line(rep, T.life('worse', { a = p.name, cond = T.COND_NAME[kind] }, r)) end
          return true
        end
        return false
      end
      local function heal(kind, pct)
        if c[kind] > 0 and r:int(1, 100) <= pct then c[kind] = c[kind] - 1 end
      end
      local treated = (patient == p) and (25 + 8 * doctor.lv) or 0
      -- frostbite: deep cold, no fuel, a hard pace, marching in a storm
      local fb = math.max(0, -temp - 30) * 2 + (rep.cold and 25 or 0) + (hard and 8 or 0)
        + ((marching and (w.kind == 'blizzard' or w.kind == 'wind')) and 10 or 0) - careful
      if p.trait == 'reckless' then fb = fb + 5 end
      if resting then fb = fb // 2 end                -- in the tent, out of the wind
      if not worsen('frostbite', fb) and fb < 15 then heal('frostbite', (resting and 30 or 10) + treated) end
      -- snow blindness: marching in bright sun
      if not (marching and w.kind == 'clear' and worsen('snowblind', 6 - careful // 2)) then heal('snowblind', (resting and 50 or 20) + treated) end
      -- exhaustion: the hard pace, short rations
      -- days on the march without a rest wear people down
      local ex = (hard and 30 or 0) + ((state.ration == 'short' and not resting) and 8 or 0)
        + (resting and 0 or 6 * math.max(0, (state.streak or 0) - 5))
      if not worsen('exhaustion', ex) then heal('exhaustion', (resting and 70 or 15) + treated // 2) end
      -- injuries heal slowly
      heal('injury', (resting and 20 or 5) + treated)
      -- sickness: hunger and cold
      local sk = (rep.hunger and 15 or 0) + (rep.cold and 5 or 0)
      if not worsen('sickness', sk) then heal('sickness', (state.ration == 'full' and 25 or 10) + treated) end
      -- health follows the conditions
      local load = 0
      for _, k in ipairs(T.CONDS) do load = load + c[k] * c[k] end
      local target = math.max(5, 100 - 9 * load - (rep.hunger and 15 or 0))
      p.health = math.max(0, math.min(100, p.health + (target - p.health) // 3))
      -- warnings and death: only after two days of a grave condition
      if grave(p) then
        p.warned = p.warned or state.day
        if state.day - p.warned >= 3 and r:int(1, 100) <= 15 + (40 - math.min(40, p.health)) then die(state, p, rep, r) end
      else
        p.warned = nil
      end
    end
    -- moods
    for _, id in ipairs(TM.living(state)) do
      local p = state.team[id]
      local target = 60
      target = target + ({ short = -12, normal = 0, full = 8 })[state.ration or 'normal']
      target = target + (hard and -6 or (resting and 4 or 0))
      if rep.hunger then target = target - 15 end
      if rep.cold then target = target - 10 end
      if p.trait == 'cheerful' then target = target + 8 elseif p.trait == 'sulky' then target = target - 8
      elseif p.trait == 'nervous' and (w.kind == 'blizzard' or w.kind == 'whiteout') then target = target - 6 end
      local others = cheer - ((p.trait == 'cheerful') and 1 or 0)
      target = target + 4 * others
      target = target - 4 * math.min(3, (function() local n = 0; for _, k in ipairs(T.CONDS) do n = n + p.cond[k] end; return n end)())
      target = target + (p.memmood or 0)
      p.mood = p.mood + (target - p.mood) // 4
      for qid, v in pairs(p.rel) do
        local q = state.team[qid]
        if v == -1 and alive(q) and p.mood < 40 and q.mood < 40 then p.mood = p.mood - 3 end
      end
      p.mood = math.max(0, math.min(100, p.mood))
    end
  end

  -- someone fed up will not march hard and lends no skill to an event
  function TM.refuses(p) return p.alive and p.mood < 25 end

  -- one line per grave condition, every day it lasts
  function TM.warnings(state)
    local out = {}
    for _, id in ipairs(TM.living(state)) do
      local p = state.team[id]
      for _, k in ipairs(T.CONDS) do
        if p.cond[k] >= 3 then out[#out + 1] = T.warning(k, p.name); break end
      end
    end
    return out
  end

  return TM
end
