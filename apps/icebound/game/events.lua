-- Events: a small engine for story events with choices, made to be shared between games (Riverstead
-- now, the expedition game later). It knows nothing of any game: the game hands it the event
-- definitions and a context of callbacks.
--
--   def = { id, once, followup, weight, cond, roles, text = { variants }, choices = { choice, ... } }
--   choice = { label, when, chance = { base, skill, trait }, ok = effects, fail = effects,
--              ok_text, fail_text, flag, ['then'] = { id, after, on = 'ok' | 'fail' | nil } }
--   ctx = { cond(def, state), weight(def, state), cast(def, state, r) -> vars | nil,
--           when(choice, state, vars), bonus(chance, state, vars) -> points, fx(effects, state, vars, r) }
--
-- The state carries what the engine needs between months: last_event, flags (once-only events and
-- choices' flags) and pending follow-ups { at = month, id, vars }.

local E = {}

local function by_id(defs, id)
  for _, d in ipairs(defs) do if d.id == id then return d end end
  return nil
end

function E.fill(def, state, r, ctx)
  return ctx.cast(def, state, r)
end

-- the event of this month: a follow-up that is due, else one drawn by weight from those whose
-- condition holds (never the last one, never a once-only event already seen); nil for a quiet month
function E.pick(defs, state, r, ctx)
  state.pending = state.pending or {}
  state.flags = state.flags or {}
  for k, p in ipairs(state.pending) do
    if p.at <= state.month then
      table.remove(state.pending, k)
      local d = by_id(defs, p.id)
      if d then return d, p.vars or {} end
    end
  end
  local cands, total = {}, 0
  for _, d in ipairs(defs) do
    if not d.followup and d.id ~= state.last_event and not (d.once and state.flags['once:' .. d.id]) and ctx.cond(d, state) then
      local w = ctx.weight(d, state)
      if w > 0 then cands[#cands + 1] = { d, w }; total = total + w end
    end
  end
  if total == 0 then return nil end
  for _ = 1, 4 do
    local x = r:int(1, total)
    for _, c in ipairs(cands) do
      x = x - c[2]
      if x <= 0 then
        local vars = ctx.cast(c[1], state, r)
        if vars then return c[1], vars end
        break
      end
    end
  end
  return nil
end

-- the choices on offer (index list), those whose condition holds
function E.choices(def, state, vars, ctx)
  local out = {}
  for k, c in ipairs(def.choices) do
    if not c.when or ctx.when(c, state, vars) then out[#out + 1] = k end
  end
  return out
end

-- take a choice: roll its chance, apply its effects, set flags, schedule its follow-up.
-- Returns the result text and 'ok' or 'fail'.
function E.apply(def, k, state, vars, r, ctx)
  local c = def.choices[k]
  local outcome = 'ok'
  if c.chance then
    local p = (c.chance.base or 50) + (ctx.bonus(c.chance, state, vars) or 0)
    p = math.max(5, math.min(95, p))
    if r:int(1, 100) > p then outcome = 'fail' end
  end
  local fx = outcome == 'ok' and c.ok or c.fail
  if fx then ctx.fx(fx, state, vars, r) end
  state.flags = state.flags or {}
  if def.once then state.flags['once:' .. def.id] = true end
  if c.flag then state.flags[c.flag] = true end
  local nxt = c['then']
  if nxt and (not nxt.on or nxt.on == outcome) then
    state.pending = state.pending or {}
    state.pending[#state.pending + 1] = { at = state.month + (nxt.after or 1), id = nxt.id, vars = vars }
  end
  state.last_event = def.id
  local text = outcome == 'ok' and c.ok_text or c.fail_text
  return text or '', outcome
end

return E
