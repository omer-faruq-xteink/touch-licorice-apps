-- Riverstead's events, and the small functions that read their conditions and effects. Each event is data
-- for game/events.lua: when it can come, who it is about (roles), its texts (three or more), and its
-- choices with their effects. Conditions and effects are tables read by ctx below:
--
--   cond:    season, moy = {..}, year_at_least, pop_at_least, pop_below, has, has_all, not_has, special,
--            riverside_field, flag, not_flag, res_at_least = {..}, food_months_at_least, unhappy,
--            hard (weighted by difficulty)
--   effects: food, wood, stone, tools, coin (+/-), happy, health (everyone), sick = n, hurt = role,
--            kill = role, leave = role, newcomers = n, renown = {way = n}, destroy = kind, skill_up = role,
--            noflood (this month), mood = n (lasting, everyone), baby = 1 (a foundling, taken in by a
--            couple); newcomers = 'n' takes the cast's {n}
--   choices: back = true marks the safe answer the Back key gives
--
--   local EL = require('game.event_list')(Rng, R, P, T)  -> { defs = {...}, ctx = {...} }

return function(Rng, R, P, T)
  local defs = {
    { id = 'pedlar', weight = 10, cond = { pop_at_least = 4 },
      text = { 'A pedlar with a lame mule stops in {village}, his packs full of iron.',
               'A travelling pedlar spreads his wares on a blanket by the camp.',
               'A pedlar comes over the hill, rattling with pots and tools.' },
      choices = { { label = 'Buy tools for food', when = { res_at_least = { food = 25 } }, ok = { food = -25, tools = 4 },
                    ok_text = 'You trade sacks of grain for good iron tools.' },
                  { label = 'Sell him wood', when = { res_at_least = { wood = 20 } }, ok = { wood = -20, coin = 10 },
                    ok_text = 'He pays in silver for a cartload of timber.' },
                  { back = true, label = 'Send him on', ok = {}, ok_text = 'He shrugs and goes on his way.' } } },
    { id = 'family', weight = 8, cond = { pop_below = 40, year_at_least = 1, res_at_least = { food = 30 }, food_months_at_least = 6 },
      text = { 'A family of {n} walks in from the hills and asks to settle in {village}.',
               '{n} weary travellers ask if there is room for them by the river.',
               'A cart stops at the edge of {village}: {n} people looking for a new home.' },
      roles = { 'n' },
      choices = { { label = 'Welcome them', ok = { newcomers = 'n', food = -10 }, ok_text = 'They unload their cart. {village} grows.' },
                  { back = true, label = 'Turn them away', ok = { happy = -3 }, ok_text = 'They leave. Some of your people look ashamed.' } } },
    { id = 'lost_child', weight = 5, cond = { pop_at_least = 6 }, roles = { 'kid', 'woodsman' },
      text = { '{kid} has not come home from the forest, and dusk is falling.',
               'Night is coming and {kid} is still out among the trees.',
               'Nobody has seen {kid} since noon, out by the forest edge.' },
      choices = { { label = 'Send {woodsman} to search', chance = { base = 45, skill = 'wood' },
                    ok = { happy = 5 }, ok_text = '{woodsman} carries {kid} home on a shoulder, cold but laughing.',
                    fail = {}, fail_text = '{woodsman} comes back alone, torch burnt out.',
                    ['then'] = { id = 'lost_child_end', after = 1, on = 'fail' } },
                  { label = 'Wait for morning', chance = { base = 30 }, ok = {}, ok_text = 'At first light {kid} walks in, hungry and proud.',
                    fail = {}, fail_text = 'Morning comes and {kid} has not.', ['then'] = { id = 'lost_child_end', after = 1, on = 'fail' } } } },
    { id = 'lost_child_end', followup = true, weight = 0, cond = {}, roles = { 'kid', 'woodsman' },
      text = { 'The whole village searches the forest for {kid}.', 'A second day of searching for {kid}.',
               'Every hand in {village} combs the woods for {kid}.' },
      choices = { { label = 'Keep searching', chance = { base = 55, skill = 'wood' }, ok = { happy = 8 },
                    ok_text = '{kid} is found asleep in a hollow tree. The village weeps with relief.',
                    fail = { kill = 'kid', happy = -12 }, fail_text = '{kid} is never found. {village} mourns.' } } },
    { id = 'wolves', weight = 6, cond = { season = 'winter', hard = true }, roles = { 'woodsman' },
      text = { 'Wolves howl close to {village} in the long nights.', 'Tracks in the snow: wolves, many of them, circling the huts.',
               'A wolf was seen by the woodpile at dawn.' },
      choices = { { label = 'Keep fires burning', when = { res_at_least = { wood = 15 } }, ok = { wood = -15 },
                    ok_text = 'The fires keep them off. The woodpile shrinks.' },
                  { label = 'Hunt them with {woodsman}', chance = { base = 45, skill = 'wood' }, ok = { food = 15, happy = 4 },
                    ok_text = 'The hunters come back with pelts and meat.', fail = { hurt = 'woodsman' },
                    fail_text = '{woodsman} is bitten and limps home.' } } },
    { id = 'fire', weight = 5, cond = { has = 'house', year_at_least = 2, hard = true }, roles = { 'builder' },
      text = { 'A spark in the thatch: a house in {village} is burning!', 'Smoke over the roofs: fire!',
               'Someone shouts fire, and {village} runs for buckets.' },
      choices = { { label = 'Fight it, {builder} leading', chance = { base = 55, skill = 'building' }, ok = { happy = 3 },
                    ok_text = 'The bucket chain beats the flames.', fail = { destroy = 'house', happy = -5 },
                    fail_text = 'The house burns to the ground.' },
                  { label = 'Save what you can', ok = { destroy = 'house', wood = -5 }, ok_text = 'The house is lost, but nobody is hurt.' } } },
    { id = 'wedding_feast', weight = 5, cond = { pop_at_least = 8, res_at_least = { food = 40 } },
      text = { 'A wedding in {village}! The families want a feast.', 'Two young people are to be wed, and everyone wants a party.',
               'Wedding bells - or at least a borrowed pot to bang - in {village}.' },
      choices = { { label = 'A real feast', ok = { food = -20, happy = 10 }, ok_text = 'They dance until the moon sets.' },
                  { back = true, label = 'Keep it simple', ok = { happy = 2 }, ok_text = 'A quiet, happy day.' } } },
    { id = 'quarrel', weight = 6, cond = { pop_at_least = 8 }, roles = { 'who', 'who2' },
      text = { '{who} and {who2} are shouting over where one field ends and the next begins.',
               '{who} accuses {who2} of moving a boundary stone.', 'A quarrel: {who} and {who2} will not speak to each other.' },
      choices = { { label = 'Side with {who}', ok = { mood = -1 }, ok_text = '{who} is pleased. {who2} sulks for weeks.' },
                  { label = 'Make them share', ok = { happy = -1 }, ok_text = 'Neither is happy, but it is settled.' } } },
    { id = 'rich_harvest', weight = 6, cond = { moy = { 9 }, has = 'field' },
      text = { 'The ears are heavy this year; the fields bow under them.', 'A rich harvest is coming in!',
               'The old farmers say they have never seen grain like it.' },
      choices = { { label = 'Bring it in', ok = { food = 30, happy = 4 }, ok_text = 'The store fills up.' } } },
    { id = 'blight', weight = 4, cond = { moy = { 7, 8 }, has = 'field', hard = true, year_at_least = 2 },
      text = { 'Black spots on the grain: blight.', 'The farmers find rot spreading through a field.',
               'A blight creeps across the fields.' },
      choices = { { label = 'Burn the sick field', ok = { food = -15 }, ok_text = 'You lose some grain, but the rest is safe.' },
                  { label = 'Leave it and hope', chance = { base = 50 }, ok = {}, ok_text = 'The weather turns and the blight dies off.',
                    fail = { food = -35 }, fail_text = 'The blight spreads. Half the harvest is lost.' } } },
    { id = 'fever', weight = 5, cond = { pop_at_least = 10, hard = true }, roles = { 'healer' },
      text = { 'A fever goes round {village}.', 'Several people are coughing and hot to the touch.',
               'Sickness: the children first, then their parents.' },
      choices = { { label = 'Keep the sick apart', ok = { sick = 1, happy = -4 }, ok_text = 'It is hard, but the fever does not spread far.' },
                  { label = 'Let {healer} tend them', chance = { base = 50, skill = 'healing' }, ok = { health = 3 },
                    ok_text = '{healer} works day and night, and they all pull through.', fail = { sick = 2 },
                    fail_text = 'The fever is stronger than the herbs.' },
                  { label = 'Pray it passes', chance = { base = 35 }, ok = { happy = 2 }, ok_text = 'It passes.',
                    fail = { sick = 2 }, fail_text = 'It does not pass.', ['then'] = { id = 'fever_worse', after = 1, on = 'fail' } } } },
    { id = 'fever_worse', followup = true, weight = 0, cond = {},
      text = { 'The fever has come back worse.', 'More are sick this month.', 'The fever lingers in {village}.' },
      choices = { { label = 'Do what you can', ok = { sick = 2, happy = -5 }, ok_text = 'Slowly, the village recovers.' } } },
    { id = 'river_rising', weight = 6, cond = { moy = { 4, 5 }, riverside_field = true },
      text = { 'The river is rising fast after the spring rain.', 'Brown water laps at the riverside fields.',
               'The river roars; the old men say a flood is coming.' },
      choices = { { label = 'Shore up the banks', when = { res_at_least = { wood = 10 } }, ok = { wood = -10, noflood = true },
                    ok_text = 'Sandbags and stakes hold the water back.' },
                  { back = true, label = 'Hope it holds', ok = {}, ok_text = 'You watch the water and wait.' } } },
    { id = 'skilled_stranger', weight = 6, cond = { pop_below = 50, res_at_least = { food = 30 } }, roles = { 'skill' },
      text = { 'A skilled {skill} asks if {village} has work.', 'A {skill} with good hands wants to settle here.',
               'A stranger, a {skill} by trade, offers to stay.' },
      choices = { { label = 'Take them in', ok = { newcomers = 1, food = -5 }, ok_text = 'The {skill} unpacks their tools.' },
                  { back = true, label = 'No room', ok = {}, ok_text = 'They walk on.' } } },
    { id = 'pilgrims', way = 'faith', weight = 6, cond = { special = true },
      text = { 'Pilgrims rest by the {spot} on their way north.', 'A band of pilgrims kneels at the {spot}.',
               'Travellers in grey stop to pray at the {spot}.' },
      choices = { { label = 'Give them bread', when = { res_at_least = { food = 10 } }, ok = { food = -10, coin = 4, renown = { faith = 5 } },
                    ok_text = 'They bless {village} and leave a few coins.' },
                  { back = true, label = 'Let them pass', ok = {}, ok_text = 'They move on.' } } },
    { id = 'tithe', once = true, weight = 6, cond = { year_at_least = 3 },
      text = { 'A steward from the lord of the land demands a tithe from {village}.', 'Riders come: the lord wants his share.',
               'A man with a ledger and two guards asks for the lord\'s due.' },
      choices = { { label = 'Pay in coin', when = { res_at_least = { coin = 20 } }, ok = { coin = -20 }, ok_text = 'He counts it twice and leaves.' },
                  { label = 'Pay in grain', when = { res_at_least = { food = 40 } }, ok = { food = -40 }, ok_text = 'The carts roll away full.' },
                  { label = 'Refuse', chance = { base = 50 }, ok = { happy = 5 }, ok_text = 'He grumbles, but never comes back.',
                    fail = { happy = -10, tools = -3 }, fail_text = 'His guards take tools instead, and laugh about it.' } } },
    { id = 'good_spring', weight = 5, cond = { moy = { 4 } },
      text = { 'Blossom on the hawthorn and lambs in the meadow: a good spring.', 'Warm rain and sun: spring is kind this year.',
               'Birdsong at dawn and green everywhere.' },
      choices = { { label = 'Enjoy it', ok = { happy = 5 }, ok_text = 'Spirits are high.' } } },
    { id = 'journeyman', way = 'craft', weight = 6, cond = { has = 'smithy' }, roles = { 'who' },
      text = { 'A journeyman smith offers to teach {who} the trade.', 'A smith on the road will teach {who} for a fee.',
               'A travelling craftsman could take {who} on as an apprentice.' },
      choices = { { label = 'Pay him', when = { res_at_least = { coin = 10 } }, ok = { coin = -10, skill_up = 'who', renown = { craft = 4 } },
                    ok_text = '{who} learns quickly.' },
                  { back = true, label = 'Not now', ok = {}, ok_text = 'He moves on.' } } },
    { id = 'market_day', way = 'trade', weight = 8, cond = { has = 'market' },
      text = { 'Market day in {village}: people from the farms around come to buy and sell.', 'The market is busy today.',
               'Stalls and shouting: it is market day.' },
      choices = { { label = 'Open the stalls', ok = { coin = 8, happy = 4, renown = { trade = 3 } }, ok_text = 'A good day\'s trade.' } } },
    { id = 'barge', way = 'trade', weight = 6, cond = { has = 'tradingpost' },
      text = { 'A barge ties up at the ford with a load of iron.', 'Bargemen at the ford want to trade.',
               'A long boat stops by the ford, heavy with goods.' },
      choices = { { label = 'Trade stone for tools', when = { res_at_least = { stone = 20 } }, ok = { stone = -20, tools = 6, renown = { trade = 3 } },
                    ok_text = 'A fair trade.' },
                  { label = 'Sell them grain', when = { res_at_least = { food = 30 } }, ok = { food = -30, coin = 15 }, ok_text = 'They pay well.' },
                  { back = true, label = 'Wave them on', ok = {}, ok_text = 'They pole away downriver.' } } },
    { id = 'charter', way = 'trade', once = true, weight = 6, cond = { has = 'tradingpost', year_at_least = 3 },
      text = { 'A merchant guild offers {village} a market charter.', 'Guild men bring a sealed charter for {village}\'s market.',
               'The guild of the river towns invites {village} to join.' },
      choices = { { label = 'Buy the charter', when = { res_at_least = { coin = 30 } }, ok = { coin = -30 }, ok_text = 'The charter is signed.',
                    ['then'] = { id = 'charter_paid', after = 6 } },
                  { back = true, label = 'Decline', ok = {}, ok_text = 'They leave politely.' } } },
    { id = 'charter_paid', followup = true, weight = 0, cond = {},
      text = { 'The charter pays off: traders come from far away.', 'Thanks to the charter, the market doubles.',
               'Guild traders now stop in {village} every month.' },
      choices = { { label = 'Welcome them', ok = { coin = 40, renown = { trade = 15 } }, ok_text = '{village} is on the map now.' } } },
    { id = 'wharf_boat', way = 'trade', weight = 6, cond = { has = 'wharf' },
      text = { 'A river boat calls at the wharf.', 'Sails on the river: a boat makes for the wharf.',
               'The wharf is busy with a boat from the coast.' },
      choices = { { label = 'Load and unload', ok = { coin = 25, renown = { trade = 8 } }, ok_text = 'Coin changes hands all day.' } } },
    { id = 'neighbours_grain', way = 'grain', weight = 7, cond = { has = 'mill' },
      text = { 'Farmers from upriver bring their grain to your mill.', 'Carts queue at the mill.',
               'Neighbouring farms want their grain milled.' },
      choices = { { label = 'Mill it for a share', ok = { food = 10, coin = 4, renown = { grain = 3 } }, ok_text = 'The millstones turn all week.' } } },
    { id = 'barn_mice', way = 'grain', weight = 5, cond = { has = 'barn' },
      text = { 'Mice in the great barn!', 'Something has been eating the stored grain.', 'The barn cats are not keeping up.' },
      choices = { { label = 'Get more cats', when = { res_at_least = { food = 5 } }, ok = { food = -5 }, ok_text = 'The mice retreat.' },
                  { label = 'Ignore it', ok = { food = -20 }, ok_text = 'The mice feast.' } } },
    { id = 'bread_fame', way = 'grain', once = true, weight = 6, cond = { has = 'bakery' },
      text = { 'Travellers talk of {village} bread in every inn along the road.', 'Your bakery\'s loaves are famous now.',
               'A lord\'s cook comes to buy {village} bread.' },
      choices = { { label = 'Bake more', ok = { coin = 15, renown = { grain = 15 } }, ok_text = '{village} is known for its bread.' } } },
    { id = 'clay', way = 'craft', weight = 5, cond = { has = 'pottery' },
      text = { 'Fine red clay found by the marsh.', 'The potters dig up a seam of excellent clay.', 'Clay like butter, the potter says.' },
      choices = { { label = 'Fire a kiln-full', ok = { coin = 10, renown = { craft = 4 } }, ok_text = 'The pots sell well.' } } },
    { id = 'cloth_order', way = 'craft', weight = 5, cond = { has = 'weaving' }, roles = { 'who' },
      text = { 'A town draper orders a bolt of fine cloth.', 'A merchant wants twenty yards of your best weave.',
               'An order for cloth comes from the town.' },
      choices = { { label = 'Weave the order', chance = { base = 55, skill = 'crafting' }, ok = { coin = 20, renown = { craft = 6 } },
                    ok_text = 'The cloth is perfect.', fail = { coin = 5 }, fail_text = 'The weave is uneven; he pays less.' } } },
    { id = 'tools_order', way = 'craft', weight = 5, cond = { has = 'smithy' },
      text = { 'A farmer from upriver wants new tools.', 'Someone needs a plough share and three sickles.',
               'An order for iron tools.' },
      choices = { { label = 'Sell three tools', when = { res_at_least = { tools = 3 } }, ok = { tools = -3, coin = 12, renown = { craft = 2 } },
                    ok_text = 'He pays gladly.' },
                  { back = true, label = 'We need them', ok = {}, ok_text = 'He goes elsewhere.' } } },
    { id = 'temple_gift', way = 'faith', weight = 5, cond = { has = 'temple' },
      text = { 'A rich pilgrim leaves a gift at the temple.', 'A purse of silver is left on the temple altar.',
               'A widow from the town gives the temple her late husband\'s savings.' },
      choices = { { label = 'Accept it', ok = { coin = 15, renown = { faith = 5 } }, ok_text = 'The temple is blessed.' } } },
    { id = 'relic', way = 'faith', once = true, weight = 6, cond = { special = true, year_at_least = 2 },
      text = { 'Digging near the {spot}, someone finds an old carved figure.', 'An ancient relic turns up by the {spot}.',
               'A bronze bell is dug out of the ground near the {spot}.' },
      choices = { { label = 'Honour it', ok = { happy = 5, renown = { faith = 10 } }, ok_text = 'Word spreads; people come to see it.' },
                  { label = 'Sell it', ok = { coin = 25 }, ok_text = 'A collector pays well. Some grumble.' } } },
    { id = 'hostel_full', way = 'faith', weight = 6, cond = { has = 'hostel' },
      text = { 'The pilgrims\' hostel is full this month.', 'Every bed in the hostel is taken.', 'Pilgrims sleep in the hostel yard.' },
      choices = { { label = 'Feed them', when = { res_at_least = { food = 15 } }, ok = { food = -15, coin = 15, renown = { faith = 10 } },
                    ok_text = 'They leave blessings and coin.' },
                  { label = 'Charge them', ok = { coin = 8, renown = { faith = 3 } }, ok_text = 'They pay, a little less warmly.' } } },
    { id = 'stories', weight = 5, cond = { pop_at_least = 6 }, roles = { 'elder' },
      text = { '{elder} tells the old stories by the fire.', 'The children gather round {elder} for a tale.',
               '{elder} remembers the valley as it was.' },
      choices = { { label = 'Listen', ok = { happy = 5 }, ok_text = 'Even the grown-ups stay up late.' } } },
    { id = 'foundling', once = true, weight = 4, cond = { pop_at_least = 6, res_at_least = { food = 20 } },
      text = { 'A baby is found in a basket at the edge of {village}.', 'Someone left an infant by the well.',
               'A foundling, wrapped in a shawl, cries at a doorstep.' },
      choices = { { label = 'Take the child in', ok = { baby = 1, happy = 3 }, ok_text = 'A family takes the baby as their own.' },
                  { label = 'Send to the town', ok = { happy = -4 }, ok_text = 'A carter takes the baby to the town.' } } },
    { id = 'thief', weight = 4, cond = { year_at_least = 2, hard = true },
      text = { 'A thief came in the night.', 'Things are missing from the store.', 'Someone broke into the storehouse.' },
      choices = { { label = 'Count the loss', ok = { coin = -8, tools = -2 }, ok_text = 'Coin and tools are gone.' } } },
    { id = 'storm', weight = 5, cond = { season = 'autumn', has = 'house', hard = true },
      text = { 'An autumn storm tears at the roofs.', 'Wind and rain all night; thatch flies.', 'A storm hits {village}.' },
      choices = { { label = 'Repair at once', when = { res_at_least = { wood = 12 } }, ok = { wood = -12 }, ok_text = 'The roofs are whole again.' },
                  { label = 'Make do', ok = { happy = -6, health = -3 }, ok_text = 'Wet beds for weeks.' } } },
    { id = 'bees', weight = 4, cond = { moy = { 4, 5 } },
      text = { 'A swarm of bees settles in an old oak.', 'Wild bees in the hollow willow.', 'Honey bees have found {village}.' },
      choices = { { label = 'Keep them', ok = { food = 8, happy = 2 }, ok_text = 'Honey by summer.' } } },
    { id = 'herbs', weight = 5, cond = { pop_at_least = 6 }, roles = { 'healer' },
      text = { '{healer} finds a patch of rare herbs.', '{healer} comes back from the marsh with a basket of herbs.',
               'Healing herbs, found by {healer}.' },
      choices = { { label = 'Dry them', ok = { health = 5 }, ok_text = 'Remedies for the winter.' } } },
    { id = 'wants_to_leave', weight = 6, cond = { unhappy = true }, roles = { 'unhappy' },
      text = { '{unhappy} says they want to leave {village}.', '{unhappy} is packing a bundle.', '{unhappy} has had enough.' },
      choices = { { label = 'Persuade them', chance = { base = 50 }, ok = { mood = 1 }, ok_text = '{unhappy} agrees to stay.',
                    fail = { leave = 'unhappy' }, fail_text = '{unhappy} goes anyway.' },
                  { label = 'Let them go', ok = { leave = 'unhappy' }, ok_text = '{unhappy} leaves at dawn.' } } },
    { id = 'harvest_festival', weight = 7, cond = { moy = { 10 }, res_at_least = { food = 40 } },
      text = { 'The harvest is in: time for the festival!', 'Garlands and music: harvest festival.', 'The last sheaf is in.' },
      choices = { { label = 'Feast!', ok = { food = -15, happy = 10 }, ok_text = 'A night to remember.' },
                  { back = true, label = 'Save the food', ok = { happy = -2 }, ok_text = 'A quiet evening.' } } },
    { id = 'midwinter', weight = 7, cond = { moy = { 12 } },
      text = { 'Midwinter: the longest night.', 'The village gathers for the midwinter fire.', 'Midwinter, and snow on the hills.' },
      choices = { { label = 'A great fire', when = { res_at_least = { wood = 10 } }, ok = { wood = -10, happy = 6 }, ok_text = 'Songs until dawn.' },
                  { back = true, label = 'Stay in', ok = {}, ok_text = 'Everyone stays by their own hearth.' } } },
    { id = 'cartwright', once = true, weight = 5, cond = { year_at_least = 2 },
      text = { 'A cartwright passes with spare wheels and axles.', 'A wheelwright offers his wares.', 'A cart-maker stops for the night.' },
      choices = { { label = 'Buy his tools', when = { res_at_least = { coin = 5 } }, ok = { coin = -5, tools = 3 }, ok_text = 'Good iron.' },
                  { back = true, label = 'No thanks', ok = {}, ok_text = 'He moves on.' } } },
  }

  ------------------------------------------------------------------ roles: who an event is about

  local Y = 12
  local function living(state) return P.living(state) end
  local function adults(state, test)
    local out = {}
    for _, id in ipairs(living(state)) do
      local p = state.people[id]
      if p.age >= 16 * Y and (not test or test(p)) then out[#out + 1] = id end
    end
    return out
  end
  local function best_with(state, skill)
    local best
    for _, id in ipairs(adults(state)) do
      local p = state.people[id]
      if not best or (p.skill == skill and (state.people[best].skill ~= skill or p.lv > state.people[best].lv)) then best = id end
    end
    return best
  end

  local function cast(def, state, r)
    local vars = { village = state.name or 'the village' }
    local v = state.valley
    vars.spot = (v.special_kind == 'spring' and 'old spring') or 'standing stone'
    for _, role in ipairs(def.roles or {}) do
      if role == 'who' then
        local a = adults(state); if #a == 0 then return nil end
        vars.who_id = r:pick(a)
      elseif role == 'who2' then
        local a = adults(state, function(p) return p.id ~= vars.who_id end); if #a == 0 then return nil end
        vars.who2_id = r:pick(a)
      elseif role == 'kid' then
        local k = {}
        for _, id in ipairs(living(state)) do
          local p = state.people[id]
          if p.age >= 4 * Y and p.age < 14 * Y then k[#k + 1] = id end
        end
        if #k == 0 then return nil end
        vars.kid_id = r:pick(k)
      elseif role == 'elder' then
        local e = adults(state, function(p) return p.age >= 50 * Y end); if #e == 0 then return nil end
        vars.elder_id = r:pick(e)
      elseif role == 'unhappy' then
        local u = adults(state, function(p) return p.happy < 30 end); if #u == 0 then return nil end
        vars.unhappy_id = r:pick(u)
      elseif role == 'woodsman' or role == 'healer' or role == 'builder' then
        local skill = ({ woodsman = 'wood', healer = 'healing', builder = 'building' })[role]
        local b = best_with(state, skill); if not b then return nil end
        vars[role .. '_id'] = b
      elseif role == 'n' then vars.n = r:int(3, 5)
      elseif role == 'skill' then
        vars.skill_key = r:pick(T.SKILLS)
        vars.skill = T.SKILL_NAME[vars.skill_key]
      end
    end
    for _, k in ipairs({ 'who', 'who2', 'kid', 'elder', 'unhappy', 'woodsman', 'healer', 'builder' }) do
      local id = vars[k .. '_id']
      if id then vars[k] = state.people[id].name end
    end
    if vars.n == nil then vars.n = 3 end
    return vars
  end

  ------------------------------------------------------------------ conditions

  local function riverside(v, i)
    if v.t[i] == 'river' then return false end
    local x, y = (i - 1) % 11 + 1, (i - 1) // 11 + 1
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local nx, ny = x + d[1], y + d[2]
      if nx >= 1 and nx <= 11 and ny >= 1 and ny <= 11 and v.t[(ny - 1) * 11 + nx] == 'river' then return true end
    end
    return false
  end

  local function res_ok(state, need)
    for k, n in pairs(need) do if (state.res[k] or 0) < n then return false end end
    return true
  end

  local function cond(def, state)
    local c = def.cond or {}
    local month = state.month
    if c.season and R.season(month) ~= c.season then return false end
    if c.moy then
      local ok = false
      for _, m in ipairs(c.moy) do if R.moy(month) == m then ok = true end end
      if not ok then return false end
    end
    if c.year_at_least and R.year(month) < c.year_at_least then return false end
    local pop = R.population(state)
    if c.pop_at_least and pop < c.pop_at_least then return false end
    if c.pop_below and pop >= c.pop_below then return false end
    if c.has and not R.has(state, c.has) then return false end
    if c.not_has and R.has(state, c.not_has) then return false end
    if c.special and not state.valley.special then return false end
    if c.flag and not (state.flags or {})[c.flag] then return false end
    if c.not_flag and (state.flags or {})[c.not_flag] then return false end
    if c.res_at_least and not res_ok(state, c.res_at_least) then return false end
    if c.food_months_at_least and R.food_months(state) < c.food_months_at_least then return false end
    if c.riverside_field then
      local any = false
      for i = 1, 121 do
        local b = state.b[i]
        if b and b.kind == 'field' and riverside(state.valley, i) then any = true end
      end
      if not any then return false end
    end
    if c.unhappy then
      local any = false
      for _, id in ipairs(living(state)) do if state.people[id].happy < 30 and state.people[id].age >= 16 * Y then any = true end end
      if not any then return false end
    end
    return true
  end

  local function weight(def, state)
    local w = def.weight or 10
    if def.cond and def.cond.hard then w = w * R.DIFF[state.diff or 'normal'].hard end
    return math.floor(w + 0.5)
  end

  local function when(choice, state, vars)
    local w = choice.when
    if w.res_at_least and not res_ok(state, w.res_at_least) then return false end
    return true
  end

  -- a skilled person adds 8 points a level; a fitting trait 15
  local function bonus(chance, state, vars)
    local b = 0
    if chance.skill then
      local id = best_with(state, chance.skill)
      local p = id and state.people[id]
      if p and p.skill == chance.skill then b = b + 8 * p.lv end
    end
    if chance.trait and vars.who_id and state.people[vars.who_id].trait == chance.trait then b = b + 15 end
    return b
  end

  ------------------------------------------------------------------ effects

  local function each_alive(state, fn)
    for _, id in ipairs(living(state)) do fn(state.people[id]) end
  end

  -- the month's report, so an event's effects show in last month's figures and the ledger
  local function note(state, k, n)
    local rep = state.report
    if not rep or n == 0 then return end
    rep.delta = rep.delta or {}
    rep.delta[k] = (rep.delta[k] or 0) + n
  end
  local function count(state, k, n)
    local rep = state.report
    if not rep or n == 0 then return end
    rep.people = rep.people or {}
    rep.people[k] = (rep.people[k] or 0) + n
  end

  local function fx(e, state, vars, r)
    for _, k in ipairs(R.RES) do
      if e[k] then
        local before = state.res[k]
        state.res[k] = math.max(0, state.res[k] + e[k])
        note(state, k, state.res[k] - before)
      end
    end
    if e.happy then each_alive(state, function(p) p.happy = math.max(0, math.min(100, p.happy + e.happy)) end) end
    if e.health then each_alive(state, function(p) p.health = math.max(0, math.min(100, p.health + e.health)) end) end
    if e.mood then each_alive(state, function(p) p.mood = math.max(-10, math.min(10, (p.mood or 0) + e.mood * 3)) end) end
    if e.sick then
      local ids = living(state)
      for _ = 1, e.sick do
        if #ids > 0 then
          local p = state.people[r:pick(ids)]
          p.health = math.max(0, p.health - 30)
        end
      end
    end
    local function role(name) local id = vars[name .. '_id']; return id and state.people[id] end
    if e.hurt then local p = role(e.hurt); if p then p.health = math.max(0, p.health - 30) end end
    if e.kill then
      local p = role(e.kill)
      if p and p.alive then
        p.alive, p.job = false, nil
        p.story[#p.story + 1] = 'lost in year ' .. R.year(state.month)
        if p.spouse and state.people[p.spouse] then state.people[p.spouse].spouse = nil end
        count(state, 'died', 1)
      end
    end
    if e.leave then
      local p = role(e.leave)
      if p and p.alive and not p.gone then P.leave(state, p); count(state, 'left', 1) end
    end
    if e.newcomers then
      local n = e.newcomers == 'n' and (vars.n or 3) or e.newcomers
      local ids = P.newcomers(state, r, n, 'by invitation')
      if vars.skill_key then for _, id in ipairs(ids) do state.people[id].skill = vars.skill_key end end
      count(state, 'came', #ids)
    end
    if e.baby and P.foundling(state, r) then count(state, 'came', 1) end
    if e.renown then
      for way, n in pairs(e.renown) do state.renown[way] = (state.renown[way] or 0) + n end
    end
    if e.destroy then
      for i = 1, 121 do
        local b = state.b[i]
        if b and b.kind == e.destroy then R.demolish(state, i); break end
      end
    end
    if e.skill_up then local p = role(e.skill_up); if p and p.lv < 5 then p.lv = p.lv + 1 end end
    if e.noflood then state.flags.noflood = state.month end
  end

  return { defs = defs, ctx = { cond = cond, weight = weight, cast = cast, when = when, bonus = bonus, fx = fx } }
end
