-- Riverstead: the words of the game. Names, skills and traits, months and seasons, and the templates of
-- every line the village tells. Templates hold placeholders only; names, places and months come from the
-- state.

local T = {}

T.FEMALE = { 'Ada', 'Agatha', 'Alys', 'Bess', 'Brida', 'Cecily', 'Clemence', 'Dorcas', 'Edda', 'Elin', 'Emmot', 'Fenna',
  'Gilda', 'Gwen', 'Hawise', 'Hild', 'Ida', 'Isolde', 'Jonet', 'Kendra', 'Lettice', 'Linnet', 'Mabyn', 'Mara',
  'Matilda', 'Meg', 'Morwen', 'Nell', 'Odile', 'Petra', 'Rhosyn', 'Rowan', 'Sabine', 'Sorrel', 'Tamsin', 'Tilda',
  'Una', 'Wenna', 'Wynne', 'Yselda', 'Briar', 'Hazel' }
T.MALE = { 'Abel', 'Aldo', 'Anselm', 'Bram', 'Cadoc', 'Colm', 'Dunstan', 'Eamon', 'Edric', 'Emrys', 'Fergal', 'Gareth',
  'Gil', 'Godric', 'Hal', 'Hamon', 'Ivo', 'Jory', 'Kester', 'Lewin', 'Lorcan', 'Madoc', 'Mylo', 'Nye', 'Osric',
  'Piran', 'Quill', 'Ralf', 'Rhys', 'Robin', 'Sayer', 'Selwyn', 'Talan', 'Tobin', 'Ulric', 'Wat', 'Wystan', 'Yorath',
  'Alder', 'Bede', 'Corin', 'Davy' }
T.SURNAMES = { 'Ashby', 'Barrow', 'Becket', 'Birch', 'Brook', 'Burdock', 'Carrow', 'Clay', 'Coppice', 'Croft', 'Dale',
  'Dewhurst', 'Elder', 'Fallow', 'Fenwick', 'Flint', 'Ford', 'Furrow', 'Gorse', 'Hatch', 'Hawthorn', 'Heath', 'Holt',
  'Ingle', 'Kettle', 'Lea', 'Linden', 'Marlow', 'Meadows', 'Mill', 'Moss', 'Nettle', 'Oakes', 'Orchard', 'Pennick',
  'Quarrie', 'Reed', 'Ridley', 'Rush', 'Sedgwick', 'Shaw', 'Sloe', 'Stone', 'Thatcher', 'Thorne', 'Tilley', 'Vale',
  'Wade', 'Warren', 'Weir', 'Westcott', 'Wheeler', 'Whin', 'Willow', 'Withy', 'Woodall', 'Wren', 'Yarrow', 'Yew', 'Bracken' }
T.VILLAGES = { 'Willowford', 'Ashwater', 'Hollin Bridge', 'Reedham', 'Thornbeck', 'Alderwick', 'Coldharbour', 'Fennick',
  'Brackenmere', 'Larkspur Holm', 'Sloeford', 'Mossley', 'Otterburn', 'Elderwell', 'Rushby', 'Whinmoor' }

T.SKILLS = { 'farming', 'wood', 'building', 'crafting', 'healing', 'trade' }
T.SKILL_NAME = { farming = 'farmer', wood = 'woodsman', building = 'builder', crafting = 'craftsman', healing = 'healer',
  trade = 'trader' }
T.TRAITS = { 'hardy', 'sickly', 'cheerful', 'lazy', 'greedy', 'devout', 'clever', 'quarrelsome' }
T.MONTHS = { 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October',
  'November', 'December' }

local function fill(s, v)
  return (s:gsub('{(%w+)}', function(k)
    local x = v[k]
    if x == nil then error('no value for {' .. k .. '} in: ' .. s) end
    return tostring(x)
  end))
end
T.fill = fill

local function pick(list, r) return list[r:int(1, #list)] end

T.LIFE = {
  married = { '{a} and {b} were married.', '{a} wed {b}; the whole village came.', '{a} and {b} are husband and wife now.' },
  born = { '{mother} and {father} have a {kind}, {child}.', 'A {kind}, {child}, born to {mother} {surname}.',
           '{child} was born to {mother} and {father}.' },
  died_old = { '{a} died, old and much loved.', '{a} passed away in the night, full of years.', 'The village buried {a}.' },
  died_sick = { '{a} did not recover.', 'Sickness took {a}.', '{a} died, weak from the hard months.' },
  left = { '{a} packed up and left the valley.', '{a} could not bear it any longer and went away.',
           '{a} left to find a better place.' },
  came = { '{a} came to live in the village.', '{a} settled among you.', '{a} arrived with a bundle and stayed.' },
}

function T.life(kind, vars, r) return fill(pick(T.LIFE[kind], r), vars) end

-- an event's story, one of its variants, filled from the event's cast
function T.event_text(def, vars, r) return fill(pick(def.text, r), vars) end

return T
