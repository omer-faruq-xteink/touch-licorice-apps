-- Port Wren: making a case. The truth comes first: a victim, a killer with a motive and a means they
-- could get, a scene and a half-hour slot of the evening, and where every suspect really was from six
-- until midnight. The clues are drawn from that truth, each behind a gate (search a place, talk to
-- someone, ask them about a topic, show them an earlier clue), and the suspects' statements copy their
-- real evening except for the lies the case's pattern calls for. G.new_case then lets the solver
-- accept the case or throws it away and tries the next seed.
--
--   local G = require('game.gen')(T, R, W)

return function(T, R, W)
  local G = {}
  G.SIZES = {
    short = { suspects = 4, places = 5, clues = { 8, 12 }, days = 2 },
    long = { suspects = 6, places = 7, clues = { 13, 19 }, days = 3, trails = 2 },
  }
  G.TOTAL = { short = 24, long = 36 }
  G.ACTIONS_PER_DAY = 12

  ------------------------------------------------------------------ helpers

  local function has(list, v)
    for _, x in ipairs(list) do if x == v then return true end end
    return false
  end
  local function add(list, v) if not has(list, v) then list[#list + 1] = v end end
  local function without(list, drop)
    local out = {}
    for _, x in ipairs(list) do if not has(drop, x) then out[#out + 1] = x end end
    return out
  end

  -- the means a person could get: what their work place and their home hold (in T.MEANS's order)
  function G.access_of(town, pid)
    local p, out = town.people[pid], {}
    for _, m in ipairs(T.MEANS) do
      if has(T.PLACES[p.work].means, m) or has(T.PLACES[p.home].means, m) then out[#out + 1] = m end
    end
    return out
  end

  local REL_MOTIVES = { debtor = { 'debt' }, spouse = { 'jealousy', 'inheritance' }, lover = { 'jealousy', 'secret' },
    sibling = { 'inheritance', 'revenge' }, employer = { 'blackmail', 'secret' }, rival = { 'revenge', 'jealousy' },
    grudge = { 'revenge' } }

  local function motive_from(town, r, a, b)
    local k = W.related(town, a, b)
    return k and r:pick(REL_MOTIVES[k]) or nil
  end

  local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
  end

  -- where a witness's own testimony puts them at a slot: seeing someone at a place, or being at a
  -- place where someone was not, means they were there (held: places promised before the clue exists)
  local function implied(case, held, w, slot)
    if held and held[w .. ':' .. slot] then return held[w .. ':' .. slot] end
    for _, c in ipairs(case.clues) do
      if c.src == w then
        for _, f in ipairs(c.facts) do
          if (f.t == 'at' or f.t == 'not_at') and f.slot == slot then return f.place end
        end
      end
    end
    return nil
  end
  -- a witness who can have been at `place` at `slot` without contradicting what they say elsewhere
  local function witness_at(case, held, r, pool, slot, place)
    local ok = {}
    for _, w in ipairs(pool) do
      local p = implied(case, held, w, slot)
      if p == nil or p == place then ok[#ok + 1] = w end
    end
    if #ok == 0 then return nil end
    return r:pick(ok)
  end

  local function first_name(town, pid) return (town.people[pid].name:match('^(%S+)')) end

  -- a suspect's evening: at work, then out (the inn, the chapel, another place of the case), then
  -- home; `at_s` is where they are at the crime slot
  local function evening(r, town, pid, places, s, at_s)
    local p = town.people[pid]
    local out_at = r:int(2, 5)
    local home_at = r:int(9, 12)
    local mid = r:pick(places)
    local mv = {}
    for t = 1, 12 do
      if t < out_at then mv[t] = p.work
      elseif t < home_at then mv[t] = mid
      else mv[t] = p.home end
    end
    mv[s] = at_s
    return mv
  end

  ------------------------------------------------------------------ the case

  -- one attempt at a case, or nil when this seed's picks do not fit (the caller tries the next)
  function G.build(town, opts)
    local r = R.new(opts.seed)
    local Z = G.SIZES[opts.size]
    local living = W.living(town)
    if #living < Z.suspects + 3 then return nil end
    local pattern = opts.pattern or 'classic'

    -- the victim, and a killer: someone the victim had dealings with, most often
    local victim = r:pick(living)
    local others = without(living, { victim })
    local related, any = {}, {}
    for _, pid in ipairs(others) do
      if #G.access_of(town, pid) > 0 then
        any[#any + 1] = pid
        if W.related(town, pid, victim) then related[#related + 1] = pid end
      end
    end
    if #any == 0 then return nil end
    local killer = (#related > 0 and not r:chance(0.25)) and r:pick(related) or r:pick(any)
    local motive = motive_from(town, r, killer, victim) or r:pick({ 'blackmail', 'secret', 'debt' })
    local means = r:pick(G.access_of(town, killer))
    local scenes = {}
    for _, k in ipairs(town.places) do
      if means ~= 'drowning' or has(T.PLACES[k].means, 'drowning') then scenes[#scenes + 1] = k end
    end
    local scene = r:pick(scenes)
    local s = r:int(3, 10)

    -- the suspects: a finalist who could have done it too, and innocents each cleared one way
    local places = { scene }
    add(places, town.people[killer].work)
    local pool = r:shuffle(without(others, { killer }))
    local names = { [first_name(town, killer)] = true }
    local function fits(pid)
      return not names[first_name(town, pid)] and (#places < Z.places or has(places, town.people[pid].work))
    end
    local finalist
    for _, pid in ipairs(pool) do
      if has(G.access_of(town, pid), means) and fits(pid) then finalist = pid; break end
    end
    if not finalist then return nil end
    names[first_name(town, finalist)] = true
    add(places, town.people[finalist].work)
    local innocents = { finalist }
    for _, pid in ipairs(pool) do
      if #innocents == Z.suspects - 1 then break end
      if pid ~= finalist and fits(pid) then
        innocents[#innocents + 1] = pid
        names[first_name(town, pid)] = true
        add(places, town.people[pid].work)
      end
    end
    if #innocents < Z.suspects - 1 then return nil end
    local suspects = { killer }
    for _, pid in ipairs(innocents) do suspects[#suspects + 1] = pid end

    -- witnesses: people of the case's places who are not suspects
    local wpool = {}
    for _, pid in ipairs(others) do
      if not has(suspects, pid) and has(places, town.people[pid].work) then wpool[#wpool + 1] = pid end
    end
    if #wpool == 0 then return nil end

    -- the rest of the case's places, from the town
    for _, k in ipairs(r:shuffle(copy(town.places))) do
      if #places >= Z.places then break end
      add(places, k)
    end

    local case = {
      v = 1, seed = opts.seed, no = opts.no or 1, pattern = pattern, size = opts.size,
      victim = victim, killer = killer, suspects = suspects, witnesses = {}, motive = motive, means = means,
      scene = scene, slot = s, window = { lo = s, hi = s }, places = places, secret = nil,
      moves = {}, says = {}, sched = {}, access = {}, motives = { [killer] = motive },
      clues = {}, strikes = 0, found = {}, talked = {}, board = {}, extra = {},
      clock = { day = 1, part = 1, used = 0 }, days = Z.days,
    }
    if pattern == 'timeline' then
      -- the doctor can only say "between ... and ...": 3 or 4 slots around the true one
      local span = r:int(3, 4)
      local lo = r:int(math.max(1, s + 2 - span), s - 1)
      case.window = { lo = lo, hi = math.min(12, lo + span - 1) }
      if case.window.hi <= s then return nil end
    end
    for _, pid in ipairs(suspects) do
      local set = {}
      for _, m in ipairs(G.access_of(town, pid)) do set[m] = true end
      case.access[pid] = set
    end

    local function clue(kind, src, facts, gate, need, tpl, vars)
      local c = { id = #case.clues + 1, kind = kind, src = src, facts = facts, gate = gate, need = need,
                  trail = false, tpl = tpl, vars = vars or {} }
      case.clues[#case.clues + 1] = c
      if src ~= 'cert' then add(case.witnesses, src) end
      if gate.who and gate.who ~= killer and not has(suspects, gate.who) then add(case.witnesses, gate.who) end
      return c
    end
    local function person_gate(who, topic)
      if topic and r:chance(0.6) then return { k = 'ask', who = who, topic = topic } end
      return { k = 'talk', who = who }
    end
    -- a gate for something kept at `place` (searched there), or told by someone who works there
    local function place_gate(place)
      if has(places, place) then return { k = 'search', place = place } end
      return person_gate(r:pick(wpool), 'victim')
    end
    local function topic_of(pid) return 'p' .. pid end

    -- the evening of each suspect
    local claim, cover_at
    do
      local mv = evening(r, town, killer, places, s, scene)
      case.moves[killer] = mv
      local says = copy(mv)
      claim = (mv[s - 1] ~= scene and mv[s - 1]) or (mv[s + 1] ~= scene and mv[s + 1]) or
        (town.people[killer].home ~= scene and town.people[killer].home) or 'inn'
      if claim == scene then claim = scene == 'inn' and 'cottages' or 'inn' end
      if pattern == 'alibi' then
        -- a witness will swear the killer was with them: most often someone close to the killer
        local close = {}
        for _, w in ipairs(wpool) do if W.related(town, w, killer) then close[#close + 1] = w end end
        case.cover = (#close > 0 and r:chance(0.7)) and r:pick(close) or r:pick(wpool)
        claim = town.people[case.cover].work
        if claim == scene then return nil end
        cover_at = claim
      end
      says[s] = claim
      case.says[killer] = says
    end

    -- how each innocent but the finalist is cleared: no way to the means, or seen elsewhere
    local how = {}
    for k = 2, #innocents do
      local pid = innocents[k]
      if not has(G.access_of(town, pid), means) and r:chance(0.6) then how[pid] = 'means'
      else how[pid] = r:chance(0.6) and 'seen' or 'cert' end
    end
    if pattern == 'liar' then
      if #innocents < 3 then return nil end
      how[innocents[2]] = 'liar'
    end
    local seen_by, held = {}, {}
    if case.cover then held[case.cover .. ':' .. s] = cover_at end
    for _, pid in ipairs(innocents) do
      local at_s
      if how[pid] == 'seen' then
        local ok = {}
        for _, w in ipairs(wpool) do
          local wk = town.people[w].work
          local p = implied(case, held, w, s)
          if wk ~= scene and (p == nil or p == wk) then ok[#ok + 1] = w end
        end
        if #ok > 0 then
          local w = r:pick(ok)
          seen_by[pid] = w
          at_s = town.people[w].work
          held[w .. ':' .. s] = at_s
        else how[pid] = 'cert' end
      end
      if not at_s then
        local choices = without(places, { scene })
        at_s = r:pick(choices)
      end
      local mv = evening(r, town, pid, places, s, at_s)
      if mv[s] == scene then mv[s] = 'inn' end
      case.moves[pid] = mv
      case.says[pid] = copy(mv)
      if how[pid] == 'liar' then
        -- where they really were is their secret; they claim somewhere else
        local said = r:pick(without(places, { scene, mv[s] }))
        case.says[pid][s] = said
        case.secret = { who = pid, slot = s, place = mv[s], said = said,
                        what = r:pick({ 'smuggling', 'affair', 'gambling', 'debt' }) }
      end
    end

    -- the clues the solution needs
    clue('physical', 'cert', { { t = 'weapon', means = means } }, { k = 'search', place = scene }, true, 'weapon',
      { means = means, place = scene })
    local kmotive = clue('document', 'cert', { { t = 'motive', who = killer, motive = motive } },
      place_gate(town.people[victim].home), true, 'motive', { who = killer, motive = motive })
    clue('physical', 'cert', { { t = 'access', who = killer, means = means, yes = true } },
      place_gate(town.people[killer].work), true, 'access_yes', { who = killer, means = means })
    local fin_motive = motive_from(town, r, finalist, victim) or r:pick(T.MOTIVES)
    case.motives[finalist] = fin_motive
    clue('physical', 'cert', { { t = 'access', who = finalist, means = means, yes = true } },
      place_gate(town.people[finalist].work), true, 'access_yes', { who = finalist, means = means })
    clue('document', 'cert', { { t = 'motive', who = finalist, motive = fin_motive } },
      person_gate(r:pick(wpool), topic_of(finalist)), true, 'motive', { who = finalist, motive = fin_motive })
    for k = 2, #innocents do
      local pid = innocents[k]
      if how[pid] == 'means' then
        clue('document', 'cert', { { t = 'access', who = pid, means = means, yes = false } },
          place_gate(town.people[pid].work), true, 'access_no', { who = pid, means = means })
      elseif how[pid] == 'seen' then
        local w = seen_by[pid]
        clue('testimony', w, { { t = 'at', who = pid, place = case.moves[pid][s], slot = s } }, person_gate(w, topic_of(pid)),
          true, 'seen', { who = pid, witness = w, place = case.moves[pid][s], slot = s })
      elseif how[pid] ~= 'liar' then
        local at = case.moves[pid][s]
        clue('physical', 'cert', { { t = 'at', who = pid, place = at, slot = s } }, place_gate(at), true, 'record',
          { who = pid, place = at, slot = s })
      end
    end
    if case.secret then
      local sec = case.secret
      local w = witness_at(case, held, r, wpool, s, sec.said)
      if not w then return nil end
      clue('testimony', w, { { t = 'not_at', who = sec.who, place = sec.said, slot = s } }, person_gate(w, topic_of(sec.who)),
        true, 'denial', { who = sec.who, witness = w, place = sec.said, slot = s })
      clue('document', 'cert', { { t = 'secret', who = sec.who, slot = s, place = sec.place } }, place_gate(sec.place), true,
        'secret', { who = sec.who, place = sec.place, slot = s, what = sec.what })
    end
    if case.cover then
      clue('testimony', case.cover, { { t = 'at', who = killer, place = claim, slot = s } }, person_gate(case.cover, topic_of(killer)),
        true, 'alibi', { who = killer, witness = case.cover, place = claim, slot = s })
    end
    if pattern == 'timeline' then
      local w = r:pick(wpool)
      clue('testimony', w, { { t = 'window', lo = s, hi = case.window.hi } }, person_gate(w, 'victim'), true, 'last_seen',
        { who = victim, witness = w, slot = s })
      clue('physical', 'cert', { { t = 'window', lo = case.window.lo, hi = s } }, { k = 'search', place = scene }, true,
        'stopped', { who = victim, place = scene, slot = s })
    end
    -- false trails (Long cases): true facts that point at innocents
    for _ = 1, Z.trails or 0 do
      local pid = r:pick(innocents)
      local kind = r:int(1, 3)
      local t = r:int(1, 12)
      if kind == 1 and pid ~= finalist and not case.motives[pid] then
        local m = r:pick(T.MOTIVES)
        case.motives[pid] = m
        clue('document', 'cert', { { t = 'motive', who = pid, motive = m } }, place_gate(town.people[pid].work), false, 'motive',
          { who = pid, motive = m }).trail = true
      elseif kind == 2 and t ~= s and how[pid] ~= 'liar' and witness_at(case, held, r, wpool, t, scene) then
        case.moves[pid][t] = scene
        case.says[pid][t] = scene
        local w = witness_at(case, held, r, wpool, t, scene)
        clue('testimony', w, { { t = 'at', who = pid, place = scene, slot = t } }, person_gate(w, topic_of(pid)), false, 'seen',
          { who = pid, witness = w, place = scene, slot = t }).trail = true
      else
        local m = case.access[pid][means] and means or nil
        if not m then
          for _, x in ipairs(T.MEANS) do if case.access[pid][x] then m = x end end
        end
        if m then
          clue('document', 'cert', { { t = 'access', who = pid, means = m, yes = true } }, place_gate(town.people[pid].work), false,
            'access_yes', { who = pid, means = m }).trail = true
        else
          local m2 = r:pick(T.MOTIVES)
          if not case.motives[pid] and pid ~= finalist then
            case.motives[pid] = m2
            clue('document', 'cert', { { t = 'motive', who = pid, motive = m2 } }, place_gate(town.people[pid].work), false,
              'motive', { who = pid, motive = m2 }).trail = true
          end
        end
      end
    end
    -- the decisive one: something certain that puts the killer at the scene at the slot (in a false
    -- alibi it must be certain, to catch the witness)
    local way = r:int(1, pattern == 'alibi' and 2 or 3)
    local dw = way == 3 and witness_at(case, held, r, wpool, s, scene) or nil
    if way == 3 and not dw then way = 2 end
    local fact = { { t = 'at', who = killer, place = scene, slot = s } }
    -- in a question of time it names only the doctor's window: the time clues must fix the slot
    local span = pattern == 'timeline' and { lo = case.window.lo, hi = case.window.hi } or nil
    if span then
      for t = span.lo, span.hi do case.says[killer][t] = claim end
    end
    -- none of them comes for free: the killer gives themself away only when faced with their motive,
    -- and what they dropped was picked up by someone who must be asked about them
    if way == 1 then
      clue('observation', 'cert', fact, { k = 'show', who = killer, clue = kmotive.id }, true, 'faced',
        { who = killer, place = scene, slot = s, span = span })
    elseif way == 2 then
      local w = r:pick(wpool)
      clue('physical', 'cert', fact, { k = 'ask', who = w, topic = topic_of(killer) }, true, 'handed',
        { who = killer, witness = w, place = scene, slot = s, span = span })
    else
      clue('testimony', dw, fact, person_gate(dw, topic_of(killer)), true, 'seen',
        { who = killer, witness = dw, place = scene, slot = s, span = span })
    end

    -- the rest: true details that decide nothing, up to the size's number of clues
    local want = r:int(Z.clues[1], Z.clues[2])
    local guard = 0
    while #case.clues < want and guard < 60 do
      guard = guard + 1
      local pid = r:pick(suspects)
      local kind = r:int(1, 3)
      if kind == 1 then
        local t = r:int(1, 12)
        local w = witness_at(case, held, r, wpool, t, case.moves[pid][t])
        if w and t ~= s and not (pid == killer and case.says[pid][t] ~= case.moves[pid][t]) then
          clue('testimony', w, { { t = 'at', who = pid, place = case.moves[pid][t], slot = t } }, person_gate(w, topic_of(pid)),
            false, 'seen', { who = pid, witness = w, place = case.moves[pid][t], slot = t })
        end
      elseif kind == 2 then
        local m = r:pick(T.MEANS)
        if m ~= means then
          local yes = case.access[pid][m] == true
          clue('document', 'cert', { { t = 'access', who = pid, means = m, yes = yes } }, place_gate(town.people[pid].work),
            false, yes and 'access_yes' or 'access_no', { who = pid, means = m })
        end
      else
        local prev = case.clues[r:int(1, #case.clues)]
        local t = r:int(1, 12)
        local w = witness_at(case, held, r, wpool, t, case.moves[pid][t])
        if w and t ~= s and pid ~= killer then
          clue('testimony', w, { { t = 'at', who = pid, place = case.moves[pid][t], slot = t } },
            { k = 'show', who = w, clue = prev.id }, false, 'seen', { who = pid, witness = w, place = case.moves[pid][t], slot = t })
        end
      end
    end
    if #case.clues < Z.clues[1] or #case.clues > Z.clues[2] then return nil end
    local trails = 0
    for _, c in ipairs(case.clues) do if c.trail then trails = trails + 1 end end
    if trails ~= (Z.trails or 0) then return nil end

    for _, pid in ipairs(suspects) do case.sched[pid] = W.schedule(town, pid, r) end
    for _, pid in ipairs(case.witnesses) do case.sched[pid] = W.schedule(town, pid, r) end
    return case
  end

  ------------------------------------------------------------------ reaching the clues

  local function meetable(case, town, pid)
    local p = town.people[pid]
    if not p or p.status ~= 'alive' or pid == case.victim or (case.night2 and pid == case.night2.victim) then return false end
    local sc = case.sched[pid]
    if not sc then return false end
    for part = 1, 4 do if has(case.places, sc[part]) then return true end end
    return false
  end
  G.meetable = meetable

  local function gate_open(case, town, gate, got)
    if gate.k == 'search' then return has(case.places, gate.place) end
    if not meetable(case, town, gate.who) then return false end
    if gate.k == 'show' then return got[gate.clue] == true end
    return true
  end

  function G.reachable(case, town)
    local got, more = {}, true
    while more do
      more = false
      for _, c in ipairs(case.clues) do
        if not got[c.id] and gate_open(case, town, c.gate, got) then got[c.id] = true; more = true end
      end
    end
    return got
  end

  -- the actions needed for every clue the solution needs (and the clues shown to open them): a
  -- search per place, a talk per person, one more for each person who trusts the detective little
  function G.cost(case, town, which)
    local need = {}
    for _, c in ipairs(case.clues) do
      if (which and which(c)) or (not which and c.need) then need[c.id] = true end
    end
    local changed = true
    while changed do
      changed = false
      for _, c in ipairs(case.clues) do
        if need[c.id] and c.gate.k == 'show' and not need[c.gate.clue] then need[c.gate.clue] = true; changed = true end
      end
    end
    -- the killer's account is always needed: it is the one the decisive clue catches
    local searched, people, n = {}, { [case.killer] = true }, 1
    if town.people[case.killer].trust < 30 then n = n + 1 end
    for _, c in ipairs(case.clues) do
      if need[c.id] then
        local g = c.gate
        if g.k == 'search' then
          if not searched[g.place] then searched[g.place] = true; n = n + 1 end
        elseif not people[g.who] then
          people[g.who] = true
          n = n + 1
          if town.people[g.who].trust < 30 then n = n + 1 end
        end
      end
    end
    return n
  end

  -- the talks with people who can only be met by day (at work, mornings and afternoons): they must
  -- fit in 60% of the daytime actions, so a town that trusts little still leaves slack
  function G.day_cost(case, town)
    local need = {}
    for _, c in ipairs(case.clues) do if c.need then need[c.id] = true end end
    local changed = true
    while changed do
      changed = false
      for _, c in ipairs(case.clues) do
        if need[c.id] and c.gate.k == 'show' and not need[c.gate.clue] then need[c.gate.clue] = true; changed = true end
      end
    end
    local people = { [case.killer] = true }
    for _, c in ipairs(case.clues) do
      if need[c.id] and c.gate.k ~= 'search' then people[c.gate.who] = true end
    end
    local n = 0
    for pid in pairs(people) do
      local sc = case.sched[pid]
      if sc and not has(case.places, sc[3]) and not has(case.places, sc[4]) then
        n = n + 1
        if town.people[pid].trust < 30 then n = n + 1 end
      end
    end
    return n
  end
  G.DAY_SHARE = 0.6

  ------------------------------------------------------------------ the killer strikes again

  local function deep(t)
    if type(t) ~= 'table' then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = deep(v) end
    return out
  end

  -- one attempt at the second crime on a copy of the case, or nil
  local function second(town, case, seed, accused)
    local r = R.new(seed)
    local c = deep(case)
    local gates = {}
    for _, cl in ipairs(c.clues) do if cl.gate.who and cl.need then gates[cl.gate.who] = true end end
    -- the victim: a suspect or witness the solution does not need to talk to
    local cands = {}
    local function consider(pid)
      if pid ~= c.killer and pid ~= accused and not gates[pid] and town.people[pid].status == 'alive' then
        cands[#cands + 1] = pid
      end
    end
    for _, pid in ipairs(c.suspects) do consider(pid) end
    for _, pid in ipairs(c.witnesses) do consider(pid) end
    if #cands == 0 then return nil end
    local v2 = r:pick(cands)
    c.suspects = without(c.suspects, { v2 })
    c.witnesses = without(c.witnesses, { v2 })
    c.moves[v2], c.says[v2] = nil, nil
    local ns = r:int(13, 18)
    local scene2 = r:pick(c.places)
    c.night2 = { victim = v2, scene = scene2, slot = ns }

    -- the second night: home, or the inn until late; the killer goes out to the scene
    for _, pid in ipairs(c.suspects) do
      local p = town.people[pid]
      local late = r:int(13, 17)
      for t = 13, 18 do
        local at = t < late and 'inn' or p.home
        if pid ~= c.killer and at == scene2 and t == ns then at = scene2 == 'inn' and p.home or 'inn' end
        if pid ~= c.killer and at == scene2 and t == ns then at = 'cottages' end
        c.moves[pid][t], c.says[pid][t] = at, at
      end
    end
    local claim = c.moves[c.killer][ns]
    c.moves[c.killer][ns] = scene2
    if claim == scene2 then claim = scene2 == 'inn' and 'cottages' or 'inn' end
    c.says[c.killer][ns] = claim
    if c.says[c.killer][ns] == scene2 then return nil end

    local wpool = {}
    for _, pid in ipairs(c.witnesses) do
      if town.people[pid].status == 'alive' and has(c.places, town.people[pid].work) then wpool[#wpool + 1] = pid end
    end
    local function clue(kind, src, facts, gate, need, tpl, vars)
      local cl = { id = #c.clues + 1, kind = kind, src = src, facts = facts, gate = gate, need = need, trail = false,
                   tpl = tpl, vars = vars or {}, night = true }
      c.clues[#c.clues + 1] = cl
      return cl
    end
    local fact = { { t = 'at', who = c.killer, place = scene2, slot = ns } }
    if r:chance(0.5) then
      clue('physical', 'cert', fact, { k = 'search', place = scene2 }, true, 'dropped', { who = c.killer, place = scene2, slot = ns })
    else
      clue('observation', 'cert', fact, { k = 'talk', who = c.killer }, true, 'observed', { who = c.killer, place = scene2, slot = ns })
    end
    -- what the night looked like to others: true sightings, deciding nothing
    for _ = 1, r:int(1, 2) do
      if #wpool > 0 then
        local pid = r:pick(c.suspects)
        local t = r:int(13, 18)
        local w = witness_at(c, nil, r, wpool, t, c.moves[pid][t])
        if w and c.says[pid][t] == c.moves[pid][t] then
          clue('testimony', w, { { t = 'at', who = pid, place = c.moves[pid][t], slot = t } }, { k = 'talk', who = w }, false,
            'seen', { who = pid, witness = w, place = c.moves[pid][t], slot = t })
        end
      end
    end
    for _, pid in ipairs(c.suspects) do
      if not c.sched[pid] then c.sched[pid] = W.schedule(town, pid, r) end
    end
    c.strikes = c.strikes + 1
    c.days = c.days + 1
    return c
  end

  -- the killer strikes again (after a wrong accusation of `accused`, or when time ran out: nil):
  -- a second victim that night, the night's movements and statements, new clues and one more day.
  -- Returns the case changed in place.
  function G.strike(town, case, seed, accused)
    local V = require('game.solver')
    for k = 1, 60 do
      local c = second(town, case, R.mix(seed, k), accused)
      if c then
        local reach = G.reachable(c, town)
        local ok = true
        for _, cl in ipairs(c.clues) do if cl.need and not reach[cl.id] then ok = false end end
        local res = ok and V.solve(c, reach)
        if ok and #res.guilty == 1 and res.guilty[1] == c.killer and res.motive[c.killer] == c.motive
          and res.means == c.means then
          for key in pairs(case) do case[key] = nil end
          for key, v in pairs(c) do case[key] = v end
          return case
        end
      end
    end
    error('no second crime could be made')
  end

  ------------------------------------------------------------------ a whole case

  G.TRIES, G.FALLBACK_TRIES = 50, 100

  -- a case the solver accepts. Run it in a coroutine: it yields after every attempt, so the caller
  -- can spread the work over timer slices. The pattern asked for gets G.TRIES attempts, then
  -- Classic gets the rest; case.pattern says what came out.
  function G.new_case(town, opts)
    local V = require('game.solver')
    if opts.pattern == 'liar' and opts.size ~= 'long' then error('innocent liar cases are long cases') end
    for k = 1, G.TRIES + G.FALLBACK_TRIES do
      local pattern = k <= G.TRIES and (opts.pattern or 'classic') or 'classic'
      local case = G.build(town, { seed = R.mix(opts.seed, k), size = opts.size, pattern = pattern, no = opts.no })
      if case and V.check(case, town, G) then
        case.from = opts.seed
        case.tries = k
        return case
      end
      if coroutine.isyieldable() then coroutine.yield(k) end
    end
    error('no case could be made')
  end

  return G
end
