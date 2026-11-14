-- Port Wren: the words of the game. The data (places, jobs, traits, names, motives, means, ranks and
-- the clock's times) and the templates every sentence is made from. Templates hold placeholders only;
-- names, places and times are filled in from the truth of the case, so the text cannot contradict it.

local T = {}

------------------------------------------------------------------ the town

-- places of the pool: a town has 10 of them (the inn, the cottages and the pier always)
T.PLACES = {
  inn = { name = 'the Anchor inn', short = 'Inn', jobs = { 'innkeeper', 'barmaid', 'potboy' }, means = { 'knife', 'poison' } },
  harbour_office = { name = 'the harbour office', short = 'Harbour', jobs = { 'harbourmaster', 'clerk' }, means = { 'blunt' } },
  pier = { name = 'the ferry pier', short = 'Pier', jobs = { 'ferry_master', 'deckhand' }, means = { 'drowning' } },
  fish_market = { name = 'the fish market', short = 'Market', jobs = { 'fishwife', 'fishmonger' }, means = { 'knife' } },
  warehouse = { name = 'the bonded warehouse', short = 'Warehse', jobs = { 'warehouseman', 'foreman' }, means = { 'blunt' } },
  chapel = { name = 'the seamen\'s chapel', short = 'Chapel', jobs = { 'chaplain', 'organist' }, means = {} },
  doctor = { name = 'the doctor\'s house', short = 'Doctor', jobs = { 'doctor', 'nurse' }, means = { 'poison' } },
  lighthouse = { name = 'the lighthouse', short = 'Light', jobs = { 'keeper' }, means = { 'drowning', 'blunt' } },
  boarding = { name = 'the boarding house', short = 'Lodging', jobs = { 'landlady', 'maid' }, means = { 'poison' } },
  bank = { name = 'the harbour bank', short = 'Bank', jobs = { 'bank_manager', 'teller' }, means = {} },
  chemist = { name = 'the chemist\'s shop', short = 'Chemist', jobs = { 'chemist', 'apprentice' }, means = { 'poison' } },
  boatyard = { name = 'the boatyard', short = 'Yard', jobs = { 'shipwright', 'caulker' }, means = { 'blunt', 'drowning' } },
  customs = { name = 'the customs house', short = 'Customs', jobs = { 'customs_officer', 'tide_waiter' }, means = { 'blunt' } },
  bakery = { name = 'the bakery on Gull Street', short = 'Bakery', jobs = { 'baker' }, means = { 'knife' } },
  school = { name = 'the schoolhouse', short = 'School', jobs = { 'teacher' }, means = {} },
  cottages = { name = 'the fishermen\'s cottages', short = 'Cottage', jobs = { 'fisherman', 'net_mender' }, means = { 'knife', 'drowning' } },
}
T.PLACE_KEYS = { 'inn', 'harbour_office', 'pier', 'fish_market', 'warehouse', 'chapel', 'doctor', 'lighthouse',
  'boarding', 'bank', 'chemist', 'boatyard', 'customs', 'bakery', 'school', 'cottages' }
T.ALWAYS = { 'inn', 'cottages', 'pier' }

T.JOBS = {
  innkeeper = { name = 'innkeeper', place = 'inn' }, barmaid = { name = 'barmaid', place = 'inn' },
  potboy = { name = 'potboy', place = 'inn' },
  harbourmaster = { name = 'harbourmaster', place = 'harbour_office' }, clerk = { name = 'harbour clerk', place = 'harbour_office' },
  ferry_master = { name = 'ferry master', place = 'pier' }, deckhand = { name = 'deckhand', place = 'pier' },
  fishwife = { name = 'fishwife', place = 'fish_market' }, fishmonger = { name = 'fishmonger', place = 'fish_market' },
  warehouseman = { name = 'warehouseman', place = 'warehouse' }, foreman = { name = 'foreman', place = 'warehouse' },
  chaplain = { name = 'chaplain', place = 'chapel' }, organist = { name = 'organist', place = 'chapel' },
  doctor = { name = 'doctor', place = 'doctor' }, nurse = { name = 'nurse', place = 'doctor' },
  keeper = { name = 'lighthouse keeper', place = 'lighthouse' },
  landlady = { name = 'landlady', place = 'boarding' }, maid = { name = 'maid', place = 'boarding' },
  bank_manager = { name = 'bank manager', place = 'bank' }, teller = { name = 'bank teller', place = 'bank' },
  chemist = { name = 'chemist', place = 'chemist' }, apprentice = { name = 'chemist\'s apprentice', place = 'chemist' },
  shipwright = { name = 'shipwright', place = 'boatyard' }, caulker = { name = 'caulker', place = 'boatyard' },
  customs_officer = { name = 'customs officer', place = 'customs' }, tide_waiter = { name = 'tide waiter', place = 'customs' },
  baker = { name = 'baker', place = 'bakery' },
  teacher = { name = 'schoolteacher', place = 'school' },
  fisherman = { name = 'fisherman', place = 'cottages' }, net_mender = { name = 'net-mender', place = 'cottages' },
}

T.TRAITS = { 'nervous', 'proud', 'honest', 'gossip', 'greedy', 'loyal', 'gruff', 'pious', 'sly', 'cheerful' }

T.FEMALE = { 'Agnes', 'Alice', 'Annie', 'Beatrice', 'Bertha', 'Clara', 'Constance', 'Dora', 'Edith', 'Effie',
  'Eleanor', 'Elsie', 'Ethel', 'Evelyn', 'Florence', 'Frances', 'Gertrude', 'Grace', 'Harriet', 'Hester',
  'Ida', 'Irene', 'Isobel', 'Jane', 'Josephine', 'Lavinia', 'Lilian', 'Lottie', 'Mabel', 'Margaret',
  'Martha', 'Maud', 'Millicent', 'Minnie', 'Nora', 'Olive', 'Peggy', 'Prudence', 'Ruth', 'Sarah',
  'Sybil', 'Theodora', 'Violet', 'Winifred' }
T.MALE = { 'Albert', 'Alfred', 'Ambrose', 'Archibald', 'Arthur', 'Barnaby', 'Bertram', 'Cecil', 'Clement', 'Cyril',
  'Edgar', 'Edmund', 'Ernest', 'Felix', 'Frederick', 'Gideon', 'Gilbert', 'Harold', 'Horace', 'Hubert',
  'Ivor', 'Jasper', 'Leonard', 'Lionel', 'Matthias', 'Montague', 'Ned', 'Norman', 'Oswald', 'Percy',
  'Reginald', 'Roland', 'Rufus', 'Septimus', 'Silas', 'Stanley', 'Thaddeus', 'Tobias', 'Walter', 'Wilfred',
  'Willard', 'Jonah' }
T.SURNAMES = { 'Abbott', 'Ashdown', 'Bellamy', 'Blackwood', 'Brand', 'Brook', 'Carver', 'Coombe', 'Crane', 'Dagger',
  'Deane', 'Drury', 'Ebbs', 'Fairweather', 'Fenn', 'Finch', 'Garrow', 'Gull', 'Hale', 'Harrow',
  'Hext', 'Holloway', 'Inch', 'Jory', 'Keel', 'Kemp', 'Lark', 'Lowe', 'Marsh', 'Merrow',
  'Nance', 'Noakes', 'Oakes', 'Pell', 'Penhale', 'Pike', 'Quill', 'Rook', 'Roe', 'Salt',
  'Sedge', 'Sheaf', 'Skerry', 'Starling', 'Swale', 'Tamsin', 'Thorne', 'Trask', 'Tulley', 'Underhill',
  'Vane', 'Venn', 'Wade', 'Wakeley', 'Whitlow', 'Wick', 'Winch', 'Wren', 'Yarrow', 'Yeo' }

T.REL_KINDS = { 'spouse', 'sibling', 'employer', 'debtor', 'rival', 'lover', 'grudge' }

------------------------------------------------------------------ the crime

T.MOTIVES = { 'debt', 'inheritance', 'jealousy', 'blackmail', 'revenge', 'secret' }
T.MOTIVE_NAME = { debt = 'Debt', inheritance = 'Inheritance', jealousy = 'Jealousy', blackmail = 'Blackmail',
  revenge = 'Revenge', secret = 'A secret kept', silencing = 'Silencing a witness' }
T.MEANS = { 'poison', 'blunt', 'knife', 'drowning' }
T.MEANS_NAME = { poison = 'Poison', blunt = 'A heavy blow', knife = 'A blade', drowning = 'Drowning' }
T.PATTERN_NAME = { classic = 'A classic case', alibi = 'A false alibi', timeline = 'A question of time',
  liar = 'An innocent liar' }
T.RANKS = { 'Constable', 'Sergeant', 'Inspector', 'Chief Inspector' }
T.PARTS = { 'morning', 'afternoon', 'evening', 'night' }

------------------------------------------------------------------ the clock

local HOURS = { 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve' }

-- minutes after midnight of a slot: 1..12 the evening of the crime from six, 13..18 the second
-- night from nine
function T.minutes(slot)
  if slot <= 12 then return 18 * 60 + (slot - 1) * 30 end
  return 21 * 60 + (slot - 13) * 30
end


-- a time of the evening in words: "half past eight", "nine o'clock", "midnight"
function T.clock(m)
  local h, half = (m // 60) % 12, m % 60 == 30
  if h == 0 then h = 12 end
  if half then return 'half past ' .. HOURS[h] end
  if h == 12 then return 'midnight' end
  return HOURS[h] .. ' o\'clock'
end
function T.time(slot) return T.clock(T.minutes(slot)) end

------------------------------------------------------------------ helpers

local function fill(s, v)
  return (s:gsub('{(%w+)}', function(k)
    local x = v[k]
    if x == nil then error('no value for {' .. k .. '} in: ' .. s) end
    return tostring(x)
  end))
end

-- a variant of a list: from r, or, without one, steadily from the case's seed and a number
local function pick(list, r, case, n)
  if r then return list[r:int(1, #list)] end
  return list[((case and case.seed or 0) + (n or 0) * 7) % #list + 1]
end

local function person(town, pid) return town.people[pid] end
local function name(town, pid) return town.people[pid].name end
local function first(town, pid) return (town.people[pid].name:match('^(%S+)')) end
local function he(town, pid) return town.people[pid].sex == 'f' and 'she' or 'he' end
local function him(town, pid) return town.people[pid].sex == 'f' and 'her' or 'him' end
local function his(town, pid) return town.people[pid].sex == 'f' and 'her' or 'his' end
local function job(town, pid) return T.JOBS[town.people[pid].job].name end
local function place(k) return T.PLACES[k].name end
local function cap(s) return (s:gsub('^%l', string.upper)) end

local function relation(town, a, b)
  for _, rl in ipairs(town.rel) do
    if (rl.a == a and rl.b == b) or (rl.a == b and rl.b == a) then return rl end
  end
  return nil
end

-- what b is to a, in a word ("wife", "brother", "employer")
local function kin_word(town, a, b)
  local rl = relation(town, a, b)
  if not rl then return nil end
  local f = town.people[b].sex == 'f'
  if rl.k == 'spouse' then return f and 'wife' or 'husband' end
  if rl.k == 'sibling' then return f and 'sister' or 'brother' end
  if rl.k == 'lover' then return 'sweetheart' end
  if rl.k == 'employer' then return rl.a == b and 'employer' or 'hired hand' end
  if rl.k == 'debtor' then return rl.a == a and 'creditor' or 'debtor' end
  if rl.k == 'rival' then return 'rival' end
  return 'old enemy'
end
T.kin_word = kin_word

------------------------------------------------------------------ the clues

local OBJECTS = {
  poison = { 'a twist of paper holding a bitter white powder', 'a stoppered brown bottle, nearly empty',
             'a teacup with a sharp, bitter smell', 'a small blue phial without a label' },
  blunt = { 'an iron belaying pin, wiped clean', 'a heavy brass weight off a scale', 'a length of lead pipe',
            'a ship\'s chock of solid oak' },
  knife = { 'a gutting knife with a worn handle', 'a thin-bladed knife, scrubbed clean', 'a cook\'s knife missing from its rack',
            'a sailmaker\'s blade' },
  drowning = { 'a coil of wet rope and marks of a struggle on the steps', 'a sodden coat caught on the ladder',
               'scuff marks at the water\'s edge and a lost shoe', 'an overturned dinghy pulled half ashore' },
}
local MEANS_GENERIC = { poison = 'poison', blunt = 'a heavy iron bar', knife = 'a blade', drowning = 'a boat on the harbour' }

local MOTIVE_TEXT = {
  debt = '{who} owed {victim} more money than {he} could ever pay',
  inheritance = '{who} stood to inherit from {victim}',
  jealousy = '{who} was eaten up with jealousy over {victim}',
  blackmail = '{victim} had been blackmailing {who}',
  revenge = '{who} had an old score to settle with {victim}',
  secret = '{victim} knew a secret that would have ruined {who}',
  silencing = '{who} feared {victim} would talk',
}

local SECRETS = {
  smuggling = 'unloading untaxed brandy off a fishing boat', affair = 'meeting someone {he} should not have been meeting',
  gambling = 'losing money at a card game in a back room', debt = 'begging a moneylender for more time',
}

local DETAILS = { 'salt-stiff trouser cuffs, still damp', 'a fresh scratch across the knuckles', 'sand from the slipway in the turn-ups',
  'a torn coat pocket, the missing piece nowhere in sight', 'a smear of tar on one sleeve', 'boots still wet through' }
local ITEMS = { 'a pipe with initials scratched in the bowl', 'a pocket-watch chain', 'a monogrammed handkerchief', 'a tobacco tin',
  'a coat button of an unusual pattern', 'a pawn ticket' }

local CLUE = {
  weapon = { 'Searching {place}, you find {obj}.', 'At {place}: {obj}. It tells you how it was done.',
             'Hidden at {place}, you turn up {obj}.', 'The search of {place} turns up {obj}.' },
  motive = { 'A letter in {victim}\'s hand: {motive}.', 'Talk in town, and a note to prove it: {motive}.',
             'Papers you are shown make it plain: {motive}.', 'An old account book says it clearly enough: {motive}.' },
  access_yes = { 'The register shows {who} could get {means} whenever {he} liked.', '{who} has a key to where {means} is kept.',
                 'Everyone knows {who} handles {means} as part of the day\'s work.', 'Nothing would stop {who} getting {means}.' },
  access_no = { '{who} could not have got {means}: {he} has no key and no reason to be near it.',
                'The register shows {who} never had {means} in reach.', '{who} has no way to {means}, the record shows.',
                'Whatever {who} did, {he} did not get {means}: the book proves it.' },
  seen = { '{witness}: "I saw {who} at {place} at {time}."', '{witness}: "{who}? At {place}, at {time}. I\'m sure of it."',
           '{witness}: "At {time} {who} was at {place}. I saw {him} plain as day."',
           '{witness} remembers {who} at {place} at {time}.' },
  record = { 'A chit at {place}: {who} paid there at {time}.', 'The book at {place}: {who} signed in at {time}.',
             'A dated slip from {place} shows {who} there at {time}.', 'Written down at {place}: {who}, {time}.' },
  faced = { 'Faced with it, {who} goes pale, and you notice {detail}. It puts {him} at {place} at {time}.',
            '{who} has no answer to that. But you notice {detail}: {he} was at {place} at {time}.',
            'Shown the paper, {who} fumbles, and you see {detail}. That only comes from {place}, around {time}.' },
  observed = { 'As {who} talks, you notice {detail}. It puts {him} at {place} at {time}.',
               'You see {detail} on {who}. That only comes from {place}, around {time}.',
               '{who} has {detail}: {he} was at {place} at {time}, whatever {he} says.' },
  dropped = { 'At {place} you find {item}. It is {who}\'s, dropped at {time}: the rain began then and it lies dry underneath.',
              'Under a bench at {place}: {item}, {who}\'s. The lamplighter swept there just before {time}.',
              'At {place}, {item}, plainly {who}\'s. It was not there when the watch went by just before {time}.' },
  handed = { '{witness} hands you {item}: {who}\'s, picked up at {place} just after {time}.',
             '{witness}: "This was lying at {place} at {time}. It\'s {who}\'s, isn\'t it?" It is {item}.',
             '{witness} kept {item}, found at {place} soon after {time}. It belongs to {who}.' },
  alibi = { '{witness}: "{who} was with me at {place} at {time}. I\'ll swear to it."',
            '{witness}: "At {time}? {who} was at {place} with me, the whole time."',
            '{witness} insists {who} was at {place} at {time}.' },
  denial = { '{witness}: "{who}, at {place} at {time}? No. I was there, and {he} was not."',
             '{witness}: "I was at {place} all through {time}. {who} never came."',
             '{witness} is certain {who} was not at {place} at {time}.' },
  secret = { 'A note found at {place}: at {time} {who} was there, {secret}.', 'At {place} you learn where {who} really was at {time}: {secret}.',
             'Someone at {place} admits it: at {time} {who} was with them, {secret}.' },
  last_seen = { '{witness}: "I saw {who} alive at {time}, right as rain."', '{witness} spoke to {who} at {time}, alive and well.',
                '{witness}: "{who} was alive at {time}. We passed the time of day."' },
  stopped = { 'At {place}, {who}\'s watch has stopped at {time}, its glass cracked in the fall.',
              'The clock at {place} was knocked over and stopped at {time}.',
              'At {place} {who}\'s wrist-watch stopped at {time} when {he} fell.' },
}

local function fact_of(c, t)
  for _, f in ipairs(c.facts) do if f.t == t then return f end end
  return c.facts[1]
end

function T.clue(case, town, c, r)
  local v = c.vars or {}
  local f = c.facts[1]
  local who = v.who or f.who or case.victim
  local vals = { victim = name(town, case.victim) }
  vals.who, vals.he, vals.him = name(town, who), he(town, who), him(town, who)
  if v.witness then vals.witness = name(town, v.witness) end
  local pl = v.place or f.place or c.gate.place
  if c.tpl == 'weapon' then pl = c.gate.place end
  if pl then vals.place = place(pl) end
  local slot = v.slot or f.slot
  if c.tpl == 'stopped' then slot = fact_of(c, 'window').hi end
  if c.tpl == 'last_seen' then slot = fact_of(c, 'window').lo end
  if slot then vals.time = T.time(slot) end
  local means = v.means or f.means
  if means then
    vals.means = MEANS_GENERIC[means]
    vals.obj = pick(OBJECTS[means], r, case, c.id)
  end
  if v.motive then
    vals.motive = fill(MOTIVE_TEXT[v.motive], { who = name(town, who), victim = name(town, case.victim), he = he(town, who) })
  end
  vals.detail = pick(DETAILS, r, case, c.id)
  vals.item = pick(ITEMS, r, case, c.id + 1)
  if v.what then vals.secret = fill(SECRETS[v.what], { he = he(town, who) }) end
  return cap(fill(pick(CLUE[c.tpl], r, case, c.id), vals))
end

------------------------------------------------------------------ people talking

-- their account of the evening (or of the second night): runs of the same place merged
function T.statement(case, town, pid, night)
  local a, b = 1, 12
  if night then a, b = 13, 18 end
  local says = case.says[pid]
  local lines = {}
  local t = a
  while t <= b do
    local at = says[t]
    local e = t
    while e + 1 <= b and says[e + 1] == at do e = e + 1 end
    if e == t then lines[#lines + 1] = 'At ' .. T.time(t) .. ' I was at ' .. place(at) .. '.'
    else lines[#lines + 1] = 'From ' .. T.time(t) .. ' until ' .. T.clock(T.minutes(e) + 30) .. ' I was at ' .. place(at) .. '.' end
    t = e + 1
  end
  return lines
end

local VOICE = {
  nervous = { 'Oh! You startled me.', 'I... yes? What is it?', 'Is this about the... the business?' },
  proud = { 'I hope this will not take long.', 'I have nothing to hide, detective.', 'Make it quick. I have a position here.' },
  honest = { 'Ask what you like. I\'ll answer straight.', 'Good day. How can I help?', 'I\'ll tell you what I know.' },
  gossip = { 'Ooh, the detective! Sit down, sit down.', 'I hear everything in this town, you know.', 'Have you heard what they\'re saying?' },
  greedy = { 'Time is money, you know.', 'What\'s in it for me?', 'Talking doesn\'t pay my bills.' },
  loyal = { 'If this is about my friends, I\'ll say nothing against them.', 'I stand by my people.', 'Ask. But I won\'t tell tales.' },
  gruff = { 'What.', 'Make it short.', 'Hm. You again.' },
  pious = { 'God keep you. What do you need?', 'A sad business. I pray for us all.', 'Peace be with you.' },
  sly = { 'Well, well. The law.', 'Ask away. I may even answer.', 'Everyone has secrets, detective.' },
  cheerful = { 'Morning! Lovely day for it, isn\'t it?', 'Hello there! What can I do for you?', 'Come in, come in!' },
}

local HIST = {
  accused = 'You accused me once, in case {n}. I have not forgotten.',
  arrested = 'You put my {kin} away, in case {n}.',
  widowed = 'I lost my {kin} in case {n}. Find whoever does these things.',
  bereaved = 'My {kin} died in case {n}. You never quite made it right.',
  helped = 'You were fair to me in case {n}.',
  fled = 'My {kin} had to leave town, after case {n}. Because of you.',
}

function T.greet(case, town, pid, r)
  local p = person(town, pid)
  local s = pick(VOICE[p.traits[1]], r, case, pid)
  local h = p.hist[#p.hist]
  if h then
    local kin = h.who and kin_word(town, pid, h.who) or nil
    s = s .. ' ' .. fill(HIST[h.what] or HIST.helped, { n = h.case, kin = kin or 'family' })
  end
  return s
end

function T.topics(case, town, pid)
  local out = { 'victim', 'evening' }
  for _, s in ipairs(case.suspects) do if s ~= pid then out[#out + 1] = 'p' .. s end end
  return out
end

-- a person's first name, or first name and initial when someone else of the case shares it
function T.short_name(case, town, pid)
  local f = first(town, pid)
  local list = { case.victim }
  if case.night2 then list[#list + 1] = case.night2.victim end
  for _, x in ipairs(case.suspects) do list[#list + 1] = x end
  for _, x in ipairs(case.witnesses) do list[#list + 1] = x end
  local function initial(x) return first(town, x) .. ' ' .. (town.people[x].name:match('(%S+)$')):sub(1, 1) .. '.' end
  local shared, same_initial = false, false
  for _, x in ipairs(list) do
    if x ~= pid and first(town, x) == f then
      shared = true
      if initial(x) == initial(pid) then same_initial = true end
    end
  end
  if same_initial then return town.people[pid].name end
  return shared and initial(pid) or f
end

function T.topic_label(case, town, topic)
  if topic == 'victim' then return T.short_name(case, town, case.victim) end
  if topic == 'evening' then return 'That evening' end
  return T.short_name(case, town, tonumber(topic:sub(2)))
end

local OPINION = {
  { 'Can\'t say I know {other} well.', 'I keep out of {other}\'s way.', '{other}? Pleasant enough.' },
  { 'My {kin}? Leave {them} out of this.', '{other} is my {kin}. That\'s all I\'ll say.', 'You know {other} is my {kin}. Go gently.' },
}

function T.answer(case, town, pid, topic, r)
  if topic == 'victim' then
    local kin = kin_word(town, pid, case.victim)
    if kin then return name(town, case.victim) .. ' was my ' .. kin .. '. I can hardly take it in.' end
    return pick({ 'I hardly knew ' .. name(town, case.victim) .. '. A shame, all the same.',
                  'A terrible thing. Nobody deserves that.', name(town, case.victim) .. '? Kept to ' .. him(town, case.victim)
                  .. 'self, mostly.' }, r, case, pid)
  end
  if topic == 'evening' then
    if not case.says[pid] then return 'I saw nothing that night, I told you.' end
    return 'As I said: ' .. T.statement(case, town, pid, false)[1]
  end
  local other = tonumber(topic:sub(2))
  local kin = kin_word(town, pid, other)
  local list = OPINION[kin and 2 or 1]
  return fill(pick(list, r, case, pid + other), { other = name(town, other), kin = kin or '', them = him(town, other) })
end

function T.react(case, town, pid, c, r)
  local about = false
  for _, f in ipairs(c.facts) do if f.who == pid then about = true end end
  if about then
    return pick({ 'That proves nothing, and you know it.', 'Where did you get that? It\'s not what it looks like.',
                  'I\'ve told you what I know. Ask someone else.', 'You think that means something? Think again.' }, r, case, pid)
  end
  return pick({ 'Can\'t help you with that.', 'Never seen it before.', 'Hm. Not mine to explain.',
                'I don\'t know anything about that.' }, r, case, pid + c.id)
end

------------------------------------------------------------------ the case's story

local function between(slot) return 'between ' .. T.time(slot) .. ' and ' .. T.clock(T.minutes(slot) + 30) end

function T.intro(case, town)
  local lines = {}
  local v = case.victim
  lines[#lines + 1] = cap(name(town, v) .. ', the ' .. job(town, v) .. ', was found dead at ' .. place(case.scene) .. '.')
  if case.window.lo == case.window.hi then
    lines[#lines + 1] = 'The doctor puts the death ' .. between(case.slot) .. '.'
  else
    lines[#lines + 1] = 'The doctor can only say it happened between ' .. T.time(case.window.lo) .. ' and '
      .. T.clock(T.minutes(case.window.hi) + 30) .. '.'
  end
  if case.night2 then
    local n2 = case.night2
    lines[#lines + 1] = 'Last night ' .. name(town, n2.victim) .. ' was found dead too, at ' .. place(n2.scene)
      .. ', ' .. between(n2.slot) .. '.'
  end
  return lines
end

function T.account(case, town)
  local k, v = case.killer, case.victim
  local lines = {}
  lines[#lines + 1] = name(town, k) .. ' killed ' .. name(town, v) .. ' at ' .. place(case.scene) .. ', '
    .. between(case.slot) .. ': ' .. T.MEANS_NAME[case.means]:lower() .. '.'
  lines[#lines + 1] = 'Why: ' .. fill(MOTIVE_TEXT[case.motive], { who = name(town, k), victim = name(town, v), he = he(town, k) }) .. '.'
  lines[#lines + 1] = cap(he(town, k)) .. ' claimed to be at ' .. place(case.says[k][case.slot]) .. ' at ' .. T.time(case.slot)
    .. ', but ' .. he(town, k) .. ' was at ' .. place(case.scene) .. '.'
  if case.cover then
    lines[#lines + 1] = name(town, case.cover) .. ' lied to cover for ' .. him(town, k) .. '.'
  end
  if case.secret then
    local sec = case.secret
    lines[#lines + 1] = name(town, sec.who) .. ' lied too, but only to hide ' .. his(town, sec.who) .. ' own secret: '
      .. fill(SECRETS[sec.what], { he = he(town, sec.who) }) .. '.'
  end
  if case.night2 then
    lines[#lines + 1] = 'Then ' .. he(town, k) .. ' killed ' .. name(town, case.night2.victim) .. ' to keep '
      .. him(town, case.night2.victim) .. ' quiet.'
  end
  local ids = {}
  for _, c in ipairs(case.clues) do if c.need then ids[#ids + 1] = tostring(c.id) end end
  lines[#lines + 1] = 'The clues that proved it: ' .. table.concat(ids, ', ') .. '.'
  return lines
end

local GOSSIP = {
  'They say the {job} at {place} has been seen at the pier after dark.', 'Word is {name} owes money all over town.',
  '{name} and the {job} at {place} aren\'t speaking, they say.', 'The ferry was late again. {name} blames the tide.',
  'Somebody saw {name} counting coins on the harbour wall.', 'Fog tonight, the fishermen say. Keep your lamp lit.',
}

function T.gossip(town, r)
  local alive = {}
  for id = 1, town.next_id - 1 do
    local p = town.people[id]
    if p and p.status == 'alive' then alive[#alive + 1] = id end
  end
  local a = alive[r:int(1, #alive)]
  local b = alive[r:int(1, #alive)]
  return fill(pick(GOSSIP, r), { name = name(town, a), job = job(town, b), place = place(town.people[b].work) })
end

return T
