-- Icebound's events, and the small functions that read their conditions and effects. Each event is data
-- for game/events.lua (a copy of Riverstead's engine): when it can come, who it is about (roles), its
-- texts (three or more), and its choices with their effects.
--
--   cond:    weather = kind | {kinds}, temp_below, day_at_least, ahead (a terrain within 2 tiles on the
--            route), on ('cairn' | 'target'), near (a terrain next to the party), has_role, tense (a tense
--            pair exists), mood_below (someone's), sup_at_least = {..}, cond (someone has a condition:
--            a kind or true), hard (weighted by difficulty), phase, mission
--   roles:   a role name (the living person with it), who, who2 (tense with who when the event is
--            `tense`), sick (someone with a condition)
--   effects: food, fuel, dogfood, dogs (+/-), mood (all), cond = {role, kind, stages}, heal = role,
--            rel = {a, b, n}, mem = {role, text}, route = 'around', camp = true, reveal = n,
--            freeze = true, break_sledge = true, skill_up = role, extras = {samples, plates}.
--            Never a death: a fall or the cold adds a condition, and only a condition kills (warned).
--   choices: back = true marks the safe answer the Back key gives; when = {sup_at_least, together =
--            {roleA, roleB}} hides a choice (together: not while those two are at odds)
--
--   local EL = require('game.event_list')(Rng, R, TM, T, G)  -> { defs = {...}, ctx = {...} }

return function(Rng, R, TM, T, G)
  local defs = {
    -- the route ahead
    { id = 'crevasses_ahead', weight = 12, cond = { ahead = 'crevasse' }, roles = { 'surveyor' },
      text = { '{surveyor} sees blue cracks across the route. Going round costs time; {surveyor} thinks there is a snow bridge.',
               'The ice ahead is split by crevasses. {surveyor} wants to try a crossing.',
               'A field of crevasses opens ahead, half hidden by drift.' },
      choices = { { label = 'Go round', ok = { route = 'around' }, ok_text = 'You turn aside and pick a longer, safer way.' },
                  { label = 'Trust {surveyor}', chance = { base = 55, role = 'surveyor' }, ok = { mood = 2 },
                    ok_text = '{surveyor} finds the bridge. Everyone crosses roped, holding their breath.',
                    fail = { cond = { role = 'surveyor', kind = 'injury', stages = 2 } },
                    fail_text = 'The bridge gives way under {surveyor}, who is hauled out bruised and bleeding.' },
                  { back = true, label = 'Camp and wait', ok = { camp = true }, ok_text = 'You pitch the tents and wait for better light.' } } },
    { id = 'snow_bridge', weight = 7, cond = { ahead = 'crevasse' }, roles = { 'driver' },
      text = { 'The dogs balk at a white ridge across the trail: a snow bridge.', '{driver} stops the team at the lip of a crevasse.',
               'A thin arch of snow is the only way over the crack.' },
      choices = { { label = 'Drive them across', chance = { base = 50, role = 'driver' }, ok = {}, ok_text = 'The dogs fly across before the snow can think about it.',
                    fail = { dogs = -2 }, fail_text = 'The bridge breaks. Two dogs are lost in the dark below.' },
                  { back = true, label = 'Go round', ok = { route = 'around' }, ok_text = 'You lead the dogs the long way round.' } } },
    { id = 'thin_ice', weight = 8, cond = { ahead = 'water' }, roles = { 'surveyor' },
      text = { 'The ice ahead is grey and thin, open water showing in the cracks.', 'A lead of black water cuts across the way.',
               '{surveyor} taps the ice with a pole. It sounds hollow.' },
      choices = { { label = 'Wait for the cold', ok = { camp = true }, ok_text = 'You camp and watch the lead, hoping it freezes.', ['then'] = { id = 'lead_freezes', after = 1 } },
                  { back = true, label = 'Find another way', ok = { route = 'around' }, ok_text = 'You turn along the lead to look for a way round.' } } },
    { id = 'lead_freezes', followup = true, weight = 0, cond = {},
      text = { 'In the night the cold deepened.', 'The lead is quiet this morning.', 'A crust has formed on the water overnight.' },
      choices = { { label = 'Test the new ice', chance = { base = 60, role = 'surveyor' }, ok = { freeze = true },
                    ok_text = 'It holds. The lead is frozen hard enough to cross.', fail = {}, fail_text = 'It is still too thin to trust.' } } },
    { id = 'pressure_ridge', weight = 9, cond = { ahead = 'ridge' }, roles = { 'mechanic' },
      text = { 'A wall of broken ice blocks rises ahead, higher than a man.', 'Pressure ridges, one after another, as far as you can see.',
               'The ice has buckled into ridges. The sledges will have to be lifted over.' },
      choices = { { label = 'Cut a way through', chance = { base = 55, role = 'mechanic' }, ok = { mood = -2 }, ok_text = 'Hours with the axes, but a way is cut.',
                    fail = { break_sledge = true }, fail_text = 'A sledge runner snaps on the ice blocks.' },
                  { back = true, label = 'Look for a way round', ok = { route = 'around' }, ok_text = 'You follow the ridge, looking for a gap.' } } },
    { id = 'sastrugi_field', weight = 6, cond = { ahead = 'sastrugi' }, roles = { 'driver' },
      text = { 'Hard ridges of wind-carved snow run across the way like frozen waves.', 'The sastrugi ahead are knee high and iron hard.',
               'The surface ahead is a sea of hard, wind-cut ridges.' },
      choices = { { label = 'Go slowly', ok = { mood = -1 }, ok_text = 'Slow going, but nothing breaks.' },
                  { label = 'Push on hard', chance = { base = 55, role = 'driver' }, ok = {}, ok_text = 'The sledges bang and lurch, but hold.',
                    fail = { break_sledge = true }, fail_text = 'A sledge cracks against a ridge.' } } },
    -- the weather
    { id = 'blizzard_tent', weight = 8, cond = { weather = 'blizzard' }, roles = { 'mechanic' },
      text = { 'The wind tears at the tent all night; a seam is splitting.', 'In the howling dark, a tent pole bends.',
               'The blizzard is ripping the tent canvas.' },
      choices = { { label = 'Mend it now', chance = { base = 60, role = 'mechanic' }, ok = {}, ok_text = 'Frozen fingers, but the seam holds.',
                    fail = { cond = { role = 'mechanic', kind = 'frostbite', stages = 1 }, fuel = -2 }, fail_text = 'The tent holds, but the mender\'s hands are frostbitten.' },
                  { back = true, label = 'Hold on till morning', ok = { mood = -4, fuel = -1 }, ok_text = 'A long, cold, sleepless night.' } } },
    { id = 'whiteout_lost', weight = 7, cond = { weather = 'whiteout' }, roles = { 'navigator' },
      text = { 'Ground and sky are the same white. {navigator} cannot tell up from down.', 'A whiteout: no horizon, no shadows, no direction.',
               'Everything is white. Even the dogs seem lost.' },
      choices = { { label = 'Follow {navigator}\'s compass', chance = { base = 50, role = 'navigator' }, ok = {}, ok_text = '{navigator} keeps you on course.',
                    fail = { route = 'around', mood = -3 }, fail_text = 'When the white lifts, you are not where you thought.', ['then'] = { id = 'whiteout_after', after = 1, on = 'fail' } },
                  { back = true, label = 'Stop and wait', ok = { camp = true }, ok_text = 'You stop where you are.' } } },
    { id = 'whiteout_after', followup = true, weight = 0, cond = {}, roles = { 'navigator' },
      text = { '{navigator} takes a sun sight to find where you are.', 'The sky clears enough for {navigator} to take a bearing.',
               '{navigator} works the figures twice.' },
      choices = { { label = 'Trust the bearing', ok = { reveal = 3, mood = 2 }, ok_text = 'You know where you are again.' } } },
    { id = 'storm_coming', weight = 5, cond = { weather = { 'wind', 'overcast' }, has_role = 'navigator' }, roles = { 'navigator' },
      text = { '{navigator} watches a dark bank of cloud on the horizon.', 'The barometer is falling fast.', 'The wind is shifting; {navigator} smells a storm.' },
      choices = { { label = 'Build snow walls', ok = { fuel = 1, mood = 1 }, ok_text = 'Walls around the tents: whatever comes, you are ready.' },
                  { back = true, label = 'Ignore it', ok = {}, ok_text = 'Perhaps it will pass you by.' } } },
    { id = 'snow_cave', weight = 5, cond = { weather = 'blizzard' }, roles = { 'who' },
      text = { '{who} suggests digging a snow cave instead of fighting the tents.', 'The drift beside camp is deep and hard; {who} says it would make a cave.',
               '{who} has heard that a snow cave is warmer than any tent.' },
      choices = { { label = 'Dig in', ok = { camp = true, fuel = 2, mood = 3 }, ok_text = 'Snug in the cave, the storm sounds far away.' },
                  { back = true, label = 'Stay in the tents', ok = {}, ok_text = 'You stay in the tents.' } } },
    { id = 'cold_snap', weight = 6, cond = { temp_below = -35, near = 'water' },
      text = { 'The cold tonight is like nothing before.', 'Breath freezes in the air with a crackle.', 'The thermometer has stopped making sense.' },
      choices = { { label = 'Huddle together', ok = { fuel = -2, freeze = true }, ok_text = 'A bitter night; by morning the nearby leads are frozen hard.' } } },
    { id = 'warm_wind', weight = 4, cond = { weather = 'wind', temp_above = -22 },
      text = { 'A strange warm wind blows from the north.', 'The air turns soft and damp.', 'For a day the cold loosens its grip.' },
      choices = { { label = 'Dry the gear', ok = { mood = 4, fuel = 1 }, ok_text = 'Sleeping bags and socks dry at last.' } } },
    { id = 'mirage', weight = 5, cond = { weather = 'clear' }, roles = { 'navigator' },
      text = { 'Mountains appear on the horizon, floating upside down.', 'A city of ice towers shimmers in the distance.',
               'The horizon lifts and bends: a mirage.' },
      choices = { { label = 'Ask {navigator}', chance = { base = 60, role = 'navigator' }, ok = { reveal = 3 }, ok_text = '{navigator} reads the mirage and sees what lies beyond.',
                    fail = { mood = -2 }, fail_text = 'It fades, and leaves everyone uneasy.' },
                  { back = true, label = 'Look away', ok = {}, ok_text = 'You march on.' } } },
    { id = 'aurora', once = true, weight = 5, cond = { weather = 'clear', temp_below = -25 },
      text = { 'Curtains of green light ripple across the night sky.', 'The aurora burns over the camp.', 'The sky is alive with light.' },
      choices = { { label = 'Wake everyone', ok = { mood = 8 }, ok_text = 'Nobody speaks for a long time.' } } },
    { id = 'sun_glare', weight = 6, cond = { weather = 'clear' }, roles = { 'who' },
      text = { 'The sun on the snow is blinding.', '{who} squints and rubs their eyes.', 'Every surface glitters painfully.' },
      choices = { { label = 'Goggles on, everyone', ok = { mood = -1 }, ok_text = 'Hot and fogged, but the eyes are safe.' },
                  { label = 'Press on', ok = { cond = { role = 'who', kind = 'snowblind', stages = 1 } }, ok_text = '{who}\'s eyes are red and streaming by evening.' } } },
    -- the sledges and the dogs
    { id = 'sledge_cracks', weight = 6, cond = { sup_at_least = { sledges = 2 } }, roles = { 'mechanic' },
      text = { 'A loud crack: a sledge runner is split.', 'One sledge is dragging; a crossbar has broken.', 'A sledge lurches and lists.' },
      choices = { { label = '{mechanic} repairs it', chance = { base = 60, role = 'mechanic' }, ok = {}, ok_text = 'Lashings and a spare plank: it will hold.',
                    fail = { break_sledge = true }, fail_text = 'It is beyond repair for now.' },
                  { back = true, label = 'Redistribute the load', ok = { break_sledge = true, mood = -2 }, ok_text = 'You leave the broken sledge and share out what it carried.' } } },
    { id = 'dogs_fight', weight = 7, cond = { sup_at_least = { dogs = 4 } }, roles = { 'driver' },
      text = { 'A savage fight breaks out among the dogs.', 'Two dogs fly at each other in the traces.', 'The dogs are snarling and snapping.' },
      choices = { { label = '{driver} separates them', chance = { base = 55, role = 'driver' }, ok = {}, ok_text = '{driver} wades in and sorts them out.',
                    fail = { dogs = -1, cond = { role = 'driver', kind = 'injury', stages = 1 } }, fail_text = 'A dog is killed and {driver} is bitten.' },
                  { back = true, label = 'Let them settle it', ok = { dogs = -1 }, ok_text = 'One dog limps away and does not get up.' } } },
    { id = 'dog_runs', weight = 5, cond = { sup_at_least = { dogs = 3 } }, roles = { 'driver' },
      text = { 'In the night a dog slipped its harness and ran.', 'One of the lead dogs is gone.', 'A dog bolted into the snow.' },
      choices = { { label = 'Search for it', ok = { camp = true }, ok_text = 'You spend the day searching.', ['then'] = { id = 'dog_returns', after = 2 } },
                  { back = true, label = 'Leave it', ok = { dogs = -1 }, ok_text = 'There is no time to look.' } } },
    { id = 'dog_returns', followup = true, weight = 0, cond = {},
      text = { 'A dog trots into camp, tail wagging.', 'The runaway is back, thin and pleased with itself.', 'Barking at dawn: the lost dog has found you.' },
      choices = { { label = 'Welcome it back', ok = { mood = 4 }, ok_text = 'Everyone is ridiculously happy.' } } },
    { id = 'puppies', once = true, weight = 4, cond = { sup_at_least = { dogs = 6, dogfood = 30 } }, roles = { 'driver' },
      text = { 'One of the bitches has had puppies in the night.', '{driver} finds four pups curled in the snow.', 'Squeaking from the dog lines: puppies!' },
      choices = { { label = 'Keep them', ok = { mood = 6, dogfood = -10 }, ok_text = 'They ride on the sledges in a crate.' } } },
    { id = 'dog_crevasse', weight = 6, cond = { ahead = 'crevasse', sup_at_least = { dogs = 3 } }, roles = { 'driver' },
      text = { 'A dog has fallen into a crevasse and hangs by its harness.', 'Howling from below: a dog is down a crack.',
               'The traces go taut: a dog has broken through.' },
      choices = { { label = 'Lower {driver} on a rope', chance = { base = 55, role = 'driver' }, ok = { mood = 5 }, ok_text = '{driver} brings it up, shivering and licking faces.',
                    fail = { dogs = -1, cond = { role = 'driver', kind = 'frostbite', stages = 1 } }, fail_text = 'The dog is lost, and {driver} comes up numb.' },
                  { back = true, label = 'Cut it loose', ok = { dogs = -1, mood = -4 }, ok_text = 'Nobody looks at the crack as you move on.' } } },
    { id = 'hungry_dogs', weight = 6, cond = { sup_at_least = { dogs = 4 }, dog_hungry = true },
      text = { 'The dogs are getting thin. Their food will not last.', 'The dog food is running out.', 'The dogs gnaw at their harnesses.' },
      choices = { { label = 'Kill the weakest dog', ok = { dogs = -1, dogfood = 20, mood = -6 }, ok_text = 'It is done quickly. The others eat.' },
                  { back = true, label = 'Not yet', ok = {}, ok_text = 'You put it off another day.' } } },
    -- the people
    { id = 'frostbite_toes', weight = 8, cond = { temp_below = -28 }, roles = { 'who', 'doctor' },
      text = { '{who}\'s toes have gone white and hard.', '{who} cannot feel their feet.', '{who} shows {doctor} a white patch on their cheek.' },
      choices = { { label = '{doctor} treats it', ok = { heal = 'who', fuel = -1 }, ok_text = '{doctor} warms the feet slowly by the stove.' },
                  { label = 'Keep moving', ok = { cond = { role = 'who', kind = 'frostbite', stages = 1 } }, ok_text = '{who} limps on.' } } },
    { id = 'fever', weight = 6, cond = { hard = true }, roles = { 'who', 'doctor' },
      text = { '{who} is hot with fever.', '{who} is shivering and coughing.', 'In the night {who} talks in their sleep, burning hot.' },
      choices = { { label = 'Rest a day', ok = { camp = true, heal = 'who' }, ok_text = 'A day in the bag, and {who} is better.' },
                  { label = 'Let {doctor} decide', chance = { base = 50, role = 'doctor' }, ok = { heal = 'who' }, ok_text = '{doctor}\'s powders work.',
                    fail = { cond = { role = 'who', kind = 'sickness', stages = 2 } }, fail_text = 'The fever deepens.' } } },
    { id = 'sprain', weight = 6, cond = {}, roles = { 'who' },
      text = { '{who} turns an ankle on a hidden ridge.', '{who} slips and lands badly.', '{who} twists a knee hauling a sledge.' },
      choices = { { label = 'Bind it and ride', ok = { cond = { role = 'who', kind = 'injury', stages = 1 } }, ok_text = '{who} rides on the sledge, grumbling.' },
                  { back = true, label = 'Rest a day', ok = { camp = true }, ok_text = 'A day to let it settle.' } } },
    { id = 'lost_mitten', weight = 5, cond = { temp_below = -20 }, roles = { 'who' },
      text = { 'The wind snatches {who}\'s mitten away.', '{who}\'s outer mitten is gone, blown into the white.', '{who} realises a mitten was left at the last camp.' },
      choices = { { label = 'Share a spare', ok = { mood = 2 }, ok_text = 'A spare pair turns up in the doctor\'s bag.' },
                  { label = 'Run after it', chance = { base = 50 }, ok = {}, ok_text = '{who} catches it on a ridge.',
                    fail = { cond = { role = 'who', kind = 'frostbite', stages = 1 } }, fail_text = '{who} comes back without it, fingers white.' } } },
    { id = 'quarrel', weight = 8, cond = { tense = true }, roles = { 'who', 'who2' },
      text = { '{who} and {who2} are shouting at each other over a spilled pot.', '{who} accuses {who2} of taking more than their share.',
               'A silence between {who} and {who2} that everyone can feel.' },
      choices = { { label = 'Side with {who}', ok = { rel = { 'who', 'who2', -1 }, mem = { 'who2', 'was overruled in favour of {who}', -3 } },
                    ok_text = '{who} is pleased. {who2} goes quiet.' },
                  { label = 'Make them share a tent', chance = { base = 40 }, ok = { rel = { 'who', 'who2', 1 } }, ok_text = 'By morning they are laughing at the same joke.',
                    fail = { mood = -3 }, fail_text = 'Nobody in that tent slept.' },
                  { back = true, label = 'Let it blow over', ok = { mood = -1 }, ok_text = 'It simmers.' } } },
    { id = 'bad_dream', weight = 5, cond = {}, roles = { 'who' },
      text = { '{who} wakes screaming from a dream of falling.', '{who} dreamt of home and cannot shake it.', '{who} says the ice spoke in the night.' },
      choices = { { label = 'Sit with them', ok = { mood = 2 }, ok_text = 'A mug of cocoa and a quiet talk.' } } },
    { id = 'homesick', weight = 5, cond = { mood_below = 40 }, roles = { 'who' },
      text = { '{who} keeps looking at an old photograph.', '{who} has stopped talking at meals.', '{who} asks how many days are left, again.' },
      choices = { { label = 'Extra ration tonight', when = { sup_at_least = { food = 20 } }, ok = { food = -6, mood = 4 }, ok_text = 'A full belly helps.' },
                  { back = true, label = 'Give them time', ok = {}, ok_text = 'You let them be.' } } },
    { id = 'birthday', once = true, weight = 5, cond = { day_at_least = 4 }, roles = { 'who' },
      text = { 'It is {who}\'s birthday today.', 'Someone remembers: {who} was born on this day.', '{who} admits, a little shyly, that it is their birthday.' },
      choices = { { label = 'A small party', when = { sup_at_least = { food = 15 } }, ok = { food = -4, mood = 7 }, ok_text = 'A candle in a frozen cake. Singing in the tent.' },
                  { back = true, label = 'A handshake', ok = { mood = 1 }, ok_text = 'Warm wishes all round.' } } },
    { id = 'song_night', weight = 5, cond = { mood_below = 55 }, roles = { 'who' },
      text = { '{who} starts singing in the tent.', '{who} has a mouth organ, it turns out.', '{who} tells a long, ridiculous story.' },
      choices = { { label = 'Join in', ok = { mood = 4 }, ok_text = 'The tent shakes with laughter.' } } },
    { id = 'navigator_doubts', weight = 5, cond = { mood_below = 35, has_role = 'navigator' }, roles = { 'navigator' },
      text = { '{navigator} is no longer sure of the position.', '{navigator} rechecks the figures three times.', '{navigator} says quietly that something is off.' },
      choices = { { label = 'Back {navigator} up', ok = { mem = { 'navigator', 'was trusted when unsure', 3 }, mood = 2 }, ok_text = '{navigator} squares their shoulders.' },
                  { label = 'Check it yourself', chance = { base = 50 }, ok = {}, ok_text = 'The position checks out.', fail = { route = 'around' }, fail_text = 'You were off. The route must change.' } } },
    { id = 'two_ropes', weight = 5, cond = { ahead = 'crevasse' }, roles = { 'surveyor', 'driver' },
      text = { '{surveyor} wants {driver} on the other end of the rope across the crevasses.', 'Two people must rope up to scout the cracks ahead.',
               'The crevasses need a roped pair to probe a way.' },
      choices = { { label = '{surveyor} and {driver} rope up', when = { together = { 'surveyor', 'driver' } }, ok = { reveal = 2, rel = { 'surveyor', 'driver', 1 } },
                    ok_text = 'They probe a safe line together.' },
                  { back = true, label = 'Go round instead', ok = { route = 'around' }, ok_text = 'You take the long way.' } } },
    -- finds and wonders
    { id = 'old_cairn', weight = 9, cond = { on = 'cairn' }, roles = { 'navigator' },
      text = { 'A cairn of stacked snow blocks, old and weathered.', 'A cairn stands here, with a tin at its foot.', 'Someone built this cairn long ago.' },
      choices = { { label = 'Open the tin', ok = { reveal = 4, mood = 3 }, ok_text = 'A note, and a rough sketch of the way they went.' } } },
    { id = 'seals', weight = 7, cond = { near = 'water' }, roles = { 'hunter' },
      text = { 'Seals are basking at the edge of the open water.', '{hunter} spots a seal by a breathing hole.', 'Dark shapes on the ice: seals.' },
      choices = { { label = 'Send {hunter}', chance = { base = 60, role = 'hunter' }, ok = { food = 15, dogfood = 25 }, ok_text = 'Fresh meat for everyone, dogs included.',
                    fail = {}, fail_text = 'They slide into the water.' },
                  { back = true, label = 'Leave them', ok = {}, ok_text = 'You watch them a while.' } } },
    { id = 'rival_flag', once = true, weight = 5, cond = { day_at_least = 10 },
      text = { 'A flag on a bamboo pole: another expedition passed this way.', 'Sledge tracks, not yours, cross the route.', 'A tin can with a foreign label lies in the snow.' },
      choices = { { label = 'Push harder', ok = { mood = 3 }, ok_text = 'Everyone walks a little faster.' },
                  { back = true, label = 'Let it be', ok = {}, ok_text = 'There is room on the ice for everyone.' } } },
    { id = 'radio', weight = 5, cond = { day_at_least = 5 },
      text = { 'The radio crackles: voices from base.', 'For a minute the radio picks up a signal.', 'Faint music from the radio, then a weather report.' },
      choices = { { label = 'Listen', ok = { mood = 4 }, ok_text = 'News from home. Everyone is quiet afterwards.' } } },
    { id = 'nunatak_rock', weight = 6, cond = { near = 'rock', has_role = 'geologist' }, roles = { 'geologist' },
      text = { '{geologist} is staring at the dark rock of a nunatak.', 'Rock! {geologist} wants a closer look.', '{geologist} thinks the nunatak holds fossils.' },
      choices = { { label = 'Give {geologist} an hour', ok = { extras = { samples = 1 }, mood = 2 }, ok_text = '{geologist} comes back with a heavy bag of rocks, delighted.' },
                  { back = true, label = 'No time', ok = { mood = -1 }, ok_text = '{geologist} looks back at it for a long time.' } } },
    { id = 'photograph', weight = 5, cond = { weather = 'clear', has_role = 'photographer' }, roles = { 'photographer' },
      text = { 'The light is perfect, says {photographer}.', '{photographer} wants the team lined up by the sledges.', 'Ice and sky, and {photographer}\'s camera.' },
      choices = { { label = 'Take the picture', ok = { extras = { plates = 1 }, mood = 2 }, ok_text = 'Frozen grins for the plate.' },
                  { back = true, label = 'Another time', ok = {}, ok_text = 'The camera goes back in its box.' } } },
    { id = 'cook_feast', weight = 5, cond = { has_role = 'cook', sup_at_least = { food = 60 } }, roles = { 'cook' },
      text = { '{cook} promises something special tonight.', '{cook} has been saving a tin of plum pudding.', 'A smell of frying comes from {cook}\'s tent.' },
      choices = { { label = 'Feast', ok = { food = -8, mood = 8 }, ok_text = 'The best meal in weeks.' },
                  { back = true, label = 'Save it', ok = {}, ok_text = 'Maybe next week.' } } },
    { id = 'fuel_leak', weight = 5, cond = { sup_at_least = { fuel = 6 } }, roles = { 'mechanic' },
      text = { 'A fuel tin has split; paraffin is soaking the snow.', 'The cold has cracked a fuel can.', 'The smell of paraffin: a can is leaking.' },
      choices = { { label = '{mechanic} solders it', chance = { base = 60, role = 'mechanic' }, ok = { fuel = -1 }, ok_text = 'Most of it saved.',
                    fail = { fuel = -4 }, fail_text = 'Most of it is lost.' },
                  { back = true, label = 'Save what you can', ok = { fuel = -3 }, ok_text = 'You pour what is left into the other cans.' } } },
    { id = 'stove_fails', weight = 5, cond = { temp_below = -25 }, roles = { 'mechanic' },
      text = { 'The primus stove sputters and dies.', 'The stove will not light.', 'A blocked jet: no stove, no water.' },
      choices = { { label = '{mechanic} takes it apart', chance = { base = 65, role = 'mechanic' }, ok = {}, ok_text = 'A pin, a curse, and it roars again.',
                    fail = { fuel = -2, mood = -3 }, fail_text = 'A cold evening before it works again.' } } },
    { id = 'skua', weight = 4, cond = { day_at_least = 2 },
      text = { 'A skua circles overhead, far from any sea.', 'A bird, here! It flies on north.', 'A lone gull follows the sledges for an hour.' },
      choices = { { label = 'Watch it', ok = { mood = 2 }, ok_text = 'A strange comfort, a living thing.' } } },
    { id = 'ice_quake', weight = 4, cond = { hard = true, near = 'water' },
      text = { 'The ice booms and shudders beneath the tents.', 'A crack races past the camp with a sound like a gun.', 'The floe groans all night.' },
      choices = { { label = 'Move camp', ok = { mood = -2, fuel = -1 }, ok_text = 'You strike camp in the dark and move to firmer ice.' },
                  { back = true, label = 'Stay put', chance = { base = 70 }, ok = {}, ok_text = 'It settles by morning.',
                    fail = { food = -10, dogfood = -10 }, fail_text = 'A crack opens under the stores; some are lost.' } } },
    { id = 'snow_blind_team', weight = 5, cond = { cond = 'snowblind' }, roles = { 'sick', 'doctor' },
      text = { '{sick}\'s eyes are swollen shut.', '{sick} cannot see and is led by a rope.', '{sick} is weeping with the pain in their eyes.' },
      choices = { { label = '{doctor} bandages the eyes', ok = { heal = 'sick' }, ok_text = 'A day in the dark, and the pain eases.' },
                  { back = true, label = 'Lead them on', ok = { mood = -2 }, ok_text = '{sick} stumbles along on the rope.' } } },
    { id = 'tend_the_sick', weight = 6, cond = { cond = true }, roles = { 'sick', 'doctor' },
      text = { '{doctor} asks for a day to tend to {sick}.', '{sick} is getting worse, says {doctor}.', '{doctor} looks worried about {sick}.' },
      choices = { { label = 'Give {doctor} the day', ok = { camp = true, heal = 'sick' }, ok_text = 'A day of rest and care.' },
                  { back = true, label = 'Keep going', ok = { mood = -1 }, ok_text = '{doctor} does what can be done on the march.' } } },
  }

  ------------------------------------------------------------------ roles: who an event is about

  local function living(state) return TM.living(state) end

  local function pick_person(state, r, test)
    local out = {}
    for _, id in ipairs(living(state)) do if not test or test(state.team[id]) then out[#out + 1] = id end end
    if #out == 0 then return nil end
    return out[r:int(1, #out)]
  end

  local function has_cond(p, kind)
    if kind == true or kind == nil then
      for _, k in ipairs(T.CONDS) do if p.cond[k] > 0 then return true end end
      return false
    end
    return p.cond[kind] > 0
  end

  local function cast(def, state, r)
    local vars = { name = state.name or 'the expedition' }
    local c = def.cond or {}
    for _, role in ipairs(def.roles or {}) do
      if role == 'who' then
        if c.tense then
          local pairs_ = {}
          for _, id in ipairs(living(state)) do
            for qid, v in pairs(state.team[id].rel) do
              if v == -1 and state.team[qid] and state.team[qid].alive and id < qid then pairs_[#pairs_ + 1] = { id, qid } end
            end
          end
          if #pairs_ == 0 then return nil end
          local pr = pairs_[r:int(1, #pairs_)]
          vars.who_id, vars.who2_id = pr[1], pr[2]
        else
          vars.who_id = pick_person(state, r, c.mood_below and function(p) return p.mood < c.mood_below end or nil)
          if not vars.who_id then return nil end
        end
      elseif role == 'who2' then
        if not vars.who2_id then
          vars.who2_id = pick_person(state, r, function(p) return p.id ~= vars.who_id end)
          if not vars.who2_id then return nil end
        end
      elseif role == 'sick' then
        vars.sick_id = pick_person(state, r, function(p) return has_cond(p, c.cond) end)
        if not vars.sick_id then return nil end
      else
        local p = R.role(state, role)
        if not p then return nil end
        vars[role .. '_id'] = p.id
      end
    end
    -- names for every cast id (collected first: adding keys while traversing with pairs is undefined)
    local ids = {}
    for k, v in pairs(vars) do
      if type(k) == 'string' and k:sub(-3) == '_id' then ids[#ids + 1] = { k:sub(1, -4), v } end
    end
    for _, kv in ipairs(ids) do vars[kv[1]] = state.team[kv[2]].name end
    return vars
  end

  ------------------------------------------------------------------ conditions

  local function sup_ok(state, need)
    for k, n in pairs(need) do if (state.sup[k] or 0) < n then return false end end
    return true
  end

  local function near(state, terrain)
    for _, j in ipairs(G.around(state.pos)) do
      if state.region.t[j] == terrain and not (terrain == 'water' and state.frozen[j]) then return true end
    end
    return false
  end

  -- a terrain on the next two tiles of the route; open water also counts beside them (a route never
  -- goes onto open water, but it can run along a lead)
  local function ahead(state, terrain)
    local function is(j) return state.region.t[j] == terrain and not (terrain == 'water' and state.frozen[j]) end
    for k = 1, math.min(2, #(state.route or {})) do
      local j = state.route[k]
      if is(j) then return true end
      if terrain == 'water' then for _, n in ipairs(G.around(j)) do if is(n) then return true end end end
    end
    return false
  end

  local function on(state, what)
    local list = what == 'cairn' and state.region.cairns or state.region.targets
    for _, j in ipairs(list) do if j == state.pos then return true end end
    return false
  end

  local function cond(def, state)
    local c = def.cond or {}
    local w = state.weather or {}
    if c.weather then
      if type(c.weather) == 'table' then
        local ok = false
        for _, k in ipairs(c.weather) do if w.kind == k then ok = true end end
        if not ok then return false end
      elseif w.kind ~= c.weather then return false end
    end
    if c.temp_below and (w.temp or 0) >= c.temp_below then return false end
    if c.temp_above and (w.temp or 0) <= c.temp_above then return false end
    -- an event does not come back within eight days
    if not def.followup and state.recent and state.recent[def.id] and state.day - state.recent[def.id] < 8 then return false end
    if c.day_at_least and state.day < c.day_at_least then return false end
    if c.ahead and not ahead(state, c.ahead) then return false end
    if c.near and not near(state, c.near) then return false end
    if c.on and not on(state, c.on) then return false end
    if c.has_role and not R.role(state, c.has_role) then return false end
    if c.sup_at_least and not sup_ok(state, c.sup_at_least) then return false end
    if c.dog_hungry and R.days_left(state).dogfood > 4 then return false end
    if c.phase and state.phase ~= c.phase then return false end
    if c.mission and state.mission ~= c.mission then return false end
    if c.tense then
      local any = false
      for _, id in ipairs(living(state)) do
        for qid, v in pairs(state.team[id].rel) do if v == -1 and state.team[qid] and state.team[qid].alive then any = true end end
      end
      if not any then return false end
    end
    if c.mood_below then
      local any = false
      for _, id in ipairs(living(state)) do if state.team[id].mood < c.mood_below then any = true end end
      if not any then return false end
    end
    if c.cond ~= nil then
      local any = false
      for _, id in ipairs(living(state)) do if has_cond(state.team[id], c.cond) then any = true end end
      if not any then return false end
    end
    return true
  end

  local function weight(def, state)
    local w = def.weight or 10
    if def.cond and def.cond.hard then w = w * ({ easy = 70, normal = 100, hard = 140 })[state.diff or 'normal'] // 100 end
    return w
  end

  local function when(choice, state, vars)
    local w = choice.when
    if w.sup_at_least and not sup_ok(state, w.sup_at_least) then return false end
    if w.together then
      local a, b = vars[w.together[1] .. '_id'], vars[w.together[2] .. '_id']
      if a and b and state.team[a].rel[b] == -1 then return false end
    end
    return true
  end

  -- a skilled person adds 8 points a level, unless they refuse; a brave or careful trait 10
  local function bonus(chance, state, vars)
    local b = 0
    if chance.role then
      local p = R.role(state, chance.role)
      if p and not TM.refuses(p) then b = b + 8 * p.lv end
      if p and (p.trait == 'brave' or p.trait == 'careful') then b = b + 10 end
    end
    return b
  end

  ------------------------------------------------------------------ effects

  local function note(state, k, n)
    local rep = state.report
    if not rep or n == 0 then return end
    rep.delta = rep.delta or {}
    rep.delta[k] = (rep.delta[k] or 0) + n
  end

  local function fx(e, state, vars, r)
    for _, k in ipairs({ 'food', 'fuel', 'dogfood', 'dogs' }) do
      if e[k] then
        local before = state.sup[k]
        state.sup[k] = math.max(0, before + e[k])
        note(state, k, state.sup[k] - before)
      end
    end
    local function role(name) local id = vars[name .. '_id']; return id and state.team[id] end
    if e.mood then
      for _, id in ipairs(living(state)) do local p = state.team[id]; p.mood = math.max(0, math.min(100, p.mood + e.mood)) end
    end
    if e.cond then
      local p = role(e.cond.role)
      if p and p.alive then p.cond[e.cond.kind] = math.min(3, p.cond[e.cond.kind] + (e.cond.stages or 1)) end
    end
    if e.heal then
      local p = role(e.heal)
      if p and p.alive then for _, k in ipairs(T.CONDS) do if p.cond[k] > 0 then p.cond[k] = p.cond[k] - 1 end end end
    end
    if e.rel then
      local a, b = role(e.rel[1]), role(e.rel[2])
      if a and b then
        local v = math.max(-1, math.min(1, (a.rel[b.id] or 0) + e.rel[3]))
        a.rel[b.id], b.rel[a.id] = v, v
      end
    end
    if e.mem then
      local p = role(e.mem[1])
      if p then
        p.mem[#p.mem + 1] = T.fill(e.mem[2], vars)
        -- a memory that stays with them: sore (-) or proud (+), on their mood from now on
        if e.mem[3] then p.memmood = math.max(-9, math.min(9, (p.memmood or 0) + e.mem[3])) end
      end
    end
    if e.skill_up then local p = role(e.skill_up); if p and p.lv < 5 then p.lv = p.lv + 1 end end
    if e.extras then
      state.extras = state.extras or { samples = 0, plates = 0 }
      for k, n in pairs(e.extras) do state.extras[k] = (state.extras[k] or 0) + n end
    end
    if e.break_sledge and state.sup.sledges > 0 then R.break_sledge(state, state.report) end
    if e.freeze then
      local x, y = G.xy(state.pos)
      for dy = -2, 2 do for dx = -2, 2 do
        local nx, ny = x + dx, y + dy
        if nx >= 1 and nx <= G.W and ny >= 1 and ny <= G.H then
          local j = G.idx(nx, ny)
          if state.region.t[j] == 'water' then state.frozen[j] = true end
        end
      end end
    end
    if e.reveal then R.reveal(state, e.reveal) end
    if e.camp then state.camp_day = state.day end
    if e.route == 'around' then
      -- a new way to the route's end that keeps off the next two tiles' kind of danger
      local goal = state.route and state.route[#state.route]
      local avoid = {}
      for k = 1, math.min(2, #(state.route or {})) do
        local j = state.route[k]
        if j ~= goal and state.region.t[j] ~= 'flat' then avoid[j] = true end
      end
      if goal and state.region.t[goal] ~= 'flat' and #state.route <= 2 then avoid[state.route[1]] = state.route[1] ~= goal or nil end
      local p = goal and G.path(state.region, state.pos, goal, function(j)
        if avoid[j] then return nil end
        return R.cost(state, j)
      end, state.seen)
      if p then table.remove(p, 1); state.route = p else state.route = {} end
      state.progress = 0
    end
  end

  return { defs = defs, ctx = { cond = cond, weight = weight, cast = cast, when = when, bonus = bonus, fx = fx } }
end
