-- Case Files' themes: the people and the things a case asks about, and how its clues are worded.
-- make_bank.py reads this file too (pool sizes, which groups are ordered), so a case in the banks
-- names its theme and groups by their place here: add at the end, never reorder.
--
-- A theme: title, story (the case's first line), who / whos (one person, several), names (the
-- people, at most 6 characters each: they head the grid), groups (three, each a pool of 6):
--   key    the tab name (at most 6 characters)      goal   what the case asks for
--   items  the full labels, as in a clue            short  the grid's labels (at most 5 characters)
--   np     "the guest who arrived at %s"            pred / neg   "arrived at %s" / "did not ..."
-- An ordered group (its items in order, one step apart) also has:
--   less   "arrived earlier than"                   after  "arrived %s after" (%s: "two hours")
--   unit   { 'hour', 'hours' }

return {
  {
    title = 'The Seaview Hotel', who = 'guest', whos = 'guests',
    story = 'Last night at the Seaview Hotel, every guest lost something.',
    names = { 'Ada', 'Bruno', 'Clara', 'Deniz', 'Elif', 'Farid' },
    groups = {
      { key = 'Floor', goal = 'floor', items = { '1st floor', '2nd floor', '3rd floor', '4th floor', '5th floor', '6th floor' },
        short = { '1st', '2nd', '3rd', '4th', '5th', '6th' },
        np = 'the guest on the %s', pred = 'stayed on the %s', neg = 'did not stay on the %s',
        less = 'stayed on a lower floor than', after = 'stayed %s above', unit = { 'floor', 'floors' } },
      { key = 'Time', goal = 'arrival time', items = { '6 pm', '7 pm', '8 pm', '9 pm', '10 pm', '11 pm' },
        np = 'the guest who arrived at %s', pred = 'arrived at %s', neg = 'did not arrive at %s',
        less = 'arrived earlier than', after = 'arrived %s after', unit = { 'hour', 'hours' } },
      { key = 'Lost', goal = 'lost item', items = { 'scarf', 'watch', 'ring', 'glove', 'key', 'hat' },
        np = 'the guest who lost the %s', pred = 'lost the %s', neg = 'did not lose the %s' },
    },
  },
  {
    title = 'The Night Train', who = 'passenger', whos = 'passengers',
    story = 'On the night train, the conductor has lost the passenger list.',
    names = { 'Anton', 'Bea', 'Cem', 'Dora', 'Emil', 'Fay' },
    groups = {
      { key = 'Car', goal = 'car', items = { 'car 1', 'car 2', 'car 3', 'car 4', 'car 5', 'car 6' },
        short = { 'Car 1', 'Car 2', 'Car 3', 'Car 4', 'Car 5', 'Car 6' },
        np = 'the passenger in %s', pred = 'rode in %s', neg = 'did not ride in %s',
        less = 'rode further forward than', after = 'rode %s further back than', unit = { 'car', 'cars' } },
      { key = 'City', goal = 'destination', items = { 'Graz', 'Sofia', 'Split', 'Brno', 'Lyon', 'Turin' },
        np = 'the passenger going to %s', pred = 'was going to %s', neg = 'was not going to %s' },
      { key = 'Drink', goal = 'drink', items = { 'tea', 'soda', 'cocoa', 'juice', 'water', 'milk' },
        np = 'the passenger who ordered %s', pred = 'ordered %s', neg = 'did not order %s' },
    },
  },
  {
    title = 'The Village Bake-off', who = 'baker', whos = 'bakers',
    story = 'The judges at the village bake-off have mixed up their notes.',
    names = { 'Alba', 'Ben', 'Cora', 'Dilek', 'Ezra', 'Flora' },
    groups = {
      { key = 'Place', goal = 'place', items = { '1st', '2nd', '3rd', '4th', '5th', '6th' },
        np = 'the baker who came %s', pred = 'came %s', neg = 'did not come %s',
        less = 'finished ahead of', after = 'finished %s behind', unit = { 'place', 'places' } },
      { key = 'Cake', goal = 'cake', items = { 'lemon', 'plum', 'fig', 'apple', 'pear', 'honey' },
        np = 'the baker of the %s cake', pred = 'baked the %s cake', neg = 'did not bake the %s cake' },
      { key = 'Home', goal = 'village', items = { 'Ashby', 'Brook', 'Elmby', 'Fenly', 'Oxton', 'Wick' },
        np = 'the baker from %s', pred = 'lives in %s', neg = 'does not live in %s' },
    },
  },
  {
    title = 'The Old Library', who = 'reader', whos = 'readers',
    story = 'The librarian is piecing together who came in last week.',
    names = { 'Arda', 'Bella', 'Can', 'Dana', 'Eva', 'Finn' },
    groups = {
      { key = 'Day', goal = 'day', items = { 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday' },
        short = { 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat' },
        np = 'the reader who came on %s', pred = 'came on %s', neg = 'did not come on %s',
        less = 'came earlier in the week than', after = 'came %s after', unit = { 'day', 'days' } },
      { key = 'Book', goal = 'book', items = { 'atlas', 'diary', 'poems', 'novel', 'play', 'tales' },
        np = 'the reader who borrowed the %s', pred = 'borrowed the %s', neg = 'did not borrow the %s' },
      { key = 'Desk', goal = 'desk', items = { 'desk 1', 'desk 2', 'desk 3', 'desk 4', 'desk 5', 'desk 6' },
        short = { '1', '2', '3', '4', '5', '6' },
        np = 'the reader at %s', pred = 'sat at %s', neg = 'did not sit at %s',
        less = 'sat nearer the door than', after = 'sat %s further from the door than', unit = { 'desk', 'desks' } },
    },
  },
  {
    title = 'Harbour Morning', who = 'sailor', whos = 'sailors',
    story = 'The harbour master is writing up the morning catch.',
    names = { 'Aras', 'Bo', 'Cleo', 'Duru', 'Esme', 'Fen' },
    groups = {
      { key = 'Boat', goal = 'boat', items = { 'Gull', 'Swift', 'Pearl', 'Otter', 'Comet', 'Wren' },
        np = 'the sailor of the %s', pred = 'sailed the %s', neg = 'did not sail the %s' },
      { key = 'Catch', goal = 'catch', items = { 'cod', 'crab', 'squid', 'eel', 'hake', 'tuna' },
        np = 'the sailor who caught %s', pred = 'caught %s', neg = 'did not catch %s' },
      { key = 'Back', goal = 'return time', items = { '5 am', '6 am', '7 am', '8 am', '9 am', '10 am' },
        np = 'the sailor back at %s', pred = 'came back at %s', neg = 'did not come back at %s',
        less = 'came back earlier than', after = 'came back %s after', unit = { 'hour', 'hours' } },
    },
  },
  {
    title = 'Museum Night', who = 'guard', whos = 'guards',
    story = 'Something moved in the museum last night, and the guards\' reports are muddled.',
    names = { 'Asli', 'Boris', 'Ceren', 'Dario', 'Eda', 'Felix' },
    groups = {
      { key = 'Hall', goal = 'hall', items = { 'Egypt', 'Rome', 'Nubia', 'China', 'Maya', 'Inca' },
        np = 'the guard of the %s hall', pred = 'watched the %s hall', neg = 'did not watch the %s hall' },
      { key = 'Round', goal = 'round', items = { '9 pm', '10 pm', '11 pm', 'midnight', '1 am', '2 am' },
        short = { '9 pm', '10 pm', '11 pm', '12 am', '1 am', '2 am' },
        np = 'the guard on the %s round', pred = 'made a round at %s', neg = 'did not make a round at %s',
        less = 'made a round earlier than', after = 'made a round %s after', unit = { 'hour', 'hours' } },
      { key = 'Saw', goal = 'what they noticed', items = { 'a noise', 'a light', 'a draft', 'a footstep', 'an echo', 'a smell' },
        short = { 'noise', 'light', 'draft', 'step', 'echo', 'smell' },
        np = 'the guard who noticed %s', pred = 'noticed %s', neg = 'did not notice %s' },
    },
  },
}
