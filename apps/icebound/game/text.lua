-- Icebound: the words of the game. Names, roles and traits, conditions and their warnings, memories,
-- the missions and the regions, and the templates every line is filled from. Templates hold
-- placeholders only; names and places come from the state.

local T = {}

T.NAMES = { 'Ruth', 'Tomas', 'Ilse', 'Moss', 'Arvid', 'June', 'Agnes', 'Bjorn', 'Clara', 'Dag', 'Edith', 'Finn',
  'Greta', 'Hugo', 'Ines', 'Jonas', 'Karin', 'Leif', 'Maud', 'Nils', 'Olga', 'Per', 'Rosa', 'Sven', 'Thea', 'Ulf',
  'Vera', 'Walt', 'Astrid', 'Bram', 'Cora', 'Eske', 'Frida', 'Gunnar', 'Hedda', 'Ivar', 'Jorun', 'Knut', 'Lise',
  'Magnus', 'Nora', 'Oskar', 'Petra', 'Rune', 'Signe', 'Tor', 'Unni', 'Viggo', 'Wilma', 'Halvard', 'Elof', 'Sigrid' }

T.ROLES = { 'navigator', 'doctor', 'driver', 'cook', 'mechanic', 'surveyor', 'hunter', 'geologist', 'photographer' }
T.ROLE_NAME = { navigator = 'navigator', doctor = 'doctor', driver = 'dog driver', cook = 'cook', mechanic = 'mechanic',
  surveyor = 'surveyor', hunter = 'hunter', geologist = 'geologist', photographer = 'photographer' }
T.TRAITS = { 'steady', 'cheerful', 'sulky', 'brave', 'reckless', 'careful', 'proud', 'nervous' }
T.CONDS = { 'frostbite', 'snowblind', 'exhaustion', 'injury', 'sickness' }
T.COND_NAME = { frostbite = 'frostbite', snowblind = 'snow blindness', exhaustion = 'exhaustion', injury = 'an injury',
  sickness = 'sickness' }
T.STAGE = { 'mild', 'bad', 'grave' }

local function fill(s, v)
  return (s:gsub('{(%w+)}', function(k)
    local x = v[k]
    if x == nil then error('no value for {' .. k .. '} in: ' .. s) end
    return tostring(x)
  end))
end
T.fill = fill

local function pick(list, r) return list[r:int(1, #list)] end
T.pick = pick

-- the warning a grave condition gives, every day it lasts
T.WARN = {
  frostbite = "{a}'s feet are freezing",
  snowblind = '{a} can barely see',
  exhaustion = '{a} is close to collapse',
  injury = "{a}'s wound is getting worse",
  sickness = '{a} is gravely ill',
}
function T.warning(kind, name) return fill(T.WARN[kind], { a = name }) end

T.LIFE = {
  died = { '{a} did not wake this morning.', 'The team lost {a} in the night.', '{a} died in the tent, the others close by.' },
  worse = { "{a}'s {cond} is getting worse.", '{a} is suffering from {cond}.', '{cond} has hold of {a}.' },
  better = { '{a} is feeling better.', "{a}'s {cond} is easing.", '{a} is on the mend.' },
}
function T.life(kind, vars, r) return fill(pick(T.LIFE[kind], r), vars) end

-- one word for the hub's team rows
function T.state_word(p)
  if not p.alive then return 'lost' end
  local worst, stage = nil, 0
  for _, k in ipairs(T.CONDS) do if p.cond[k] > stage then worst, stage = k, p.cond[k] end end
  if worst and stage >= 2 then return ({ frostbite = 'frostbite', snowblind = 'snowblind', exhaustion = 'exhausted',
    injury = 'injured', sickness = 'sick' })[worst] end
  if p.mood < 25 then return 'sulking' end
  if worst then return 'tired' end
  if p.mood >= 70 then return 'cheerful' end
  return 'steady'
end

-- an event's story, one of its variants, filled from the event's cast
function T.event_text(def, vars, r) return fill(pick(def.text, r), vars) end

return T
