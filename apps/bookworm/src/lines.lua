-- What the bookworm says: short lines by situation, filled in with the book it is eating. pick()
-- takes a seed so a line stays put until something changes (a tap, a new day, a new book).
--
-- {title} the book (shortened), {pct} how far, {name} the bookworm, {min} minutes read today,
-- {trait} its character, {other} another name (the moth that left).

local L = {}

L.EGG = {
  'An egg. Something inside is waiting for a good book.',
  'The egg is warm. Ten minutes of reading should do it.',
  'It wobbled a little when you opened a book.',
}

L.FULL = {
  'Mmm. {title}. Crunchy.',
  '{pct}% of {title} eaten. Saving the ending for later.',
  'Today tasted of {title}. {min} minutes of it.',
  'I nibbled a semicolon. It was worth it.',
  'Full of {title}. Please do not shake the shelf.',
  'That chapter had a lovely aftertaste.',
  'I would rate today\'s pages a solid crunch.',
  'Do not tell me how it ends. I want to eat it myself.',
  'I am made of {min} minutes of reading today. Good minutes.',
  'Commas are my favourite crumbs.',
}

L.PECKISH = {
  'A page or two would be nice.',
  'Peckish. {title} smells good from here.',
  'Yesterday was quiet. Just saying.',
  'I could manage a paragraph. Or ten.',
}

L.HUNGRY = {
  'My tummy is growling in italics.',
  'Even a footnote would do.',
  'Is {title} still open somewhere? I can smell it.',
  'Hungry. Very hungry. Ask any caterpillar.',
  'I ate the margins. They were empty.',
}

L.SULKY = {
  'Hmph.',
  'Oh, you are back. I had not noticed. (I had.)',
  'I have been reading the back of the shampoo bottle. In my mind.',
  'I am not talking to people who do not read.',
  'Fine. I will chew the spine of the dictionary.',
  'Days without a page. Days.',
}

L.HIDING = {
  '(something rustles inside {title})',
  '(a tiny voice from between the pages: read me)',
  '(the bookworm is hiding until you read again)',
}

L.HATCHED = {
  'Hello! I hatched on {title}.',
  'Out of the egg and straight into {title}.',
}
L.GREW = {
  'I grew! I am a {other} now.',
  'Look at me: a {other}. All that reading.',
}
L.FINISHED = {
  'We finished {other}! Four crumbs out of five.',
  'The end of {other}. I licked the last full stop.',
  '{other}: done. I would read it again, slowly.',
  'Finished {other}. I need a nap and another book.',
}
L.MOTH = {
  '{other} spun a cocoon and flew off as a moth. I am the new one.',
  'My mother {other} left me this shelf. I will look after it.',
}

L.TRAIT = {
  owl = { 'Reading by moonlight again? Same.', 'The best pages are after ten.' },
  lark = { 'Morning reading. My favourite breakfast.', 'Up with the sun and straight into a book.' },
  marathon = { 'Such long sittings. I am mostly made of chapters.', 'One more chapter. Always one more.' },
  nibbler = { 'Little bites, every day. I like a light diet.', 'A page here, a page there. Delicious.' },
  steady = { 'Every day, without fail. You are my clock.', 'Another day, another page. I love routine.' },
  butterfly = { 'Three books at once? My tummy is a library.', 'A bit of this, a bit of that. A tasting menu.' },
  loyal = { 'Just {title}, day after day. I respect that.', 'We are very faithful to {title}.' },
  finisher = { 'You finish what you start. I admire that.', 'Another ending. You collect them.' },
  curious = { 'What shall we read next?', 'I wonder what the next book tastes like.' },
}

-- its taste, from what it has been eating (taste.lua)
L.TASTE = {
  horror = { 'Another haunted house? I am sleeping with the light on.', 'I checked under the bed. Twice.',
             'If that book has a cellar, I am not going down.', 'Every creak is a chapter now. Thanks.' },
  mystery = { 'The butler. It is always the butler.', 'I have a theory about page 212.',
              'Nobody leaves this bookshelf until I find the culprit.', 'Elementary. Mostly.' },
  romance = { 'Will they, won\'t they? They will. They always will.', 'I sighed so hard my glasses fogged up.',
              'Two people, one bed at the inn. I know how this goes.', 'My heart is mostly made of chapter twelve.' },
  fantasy = { 'I would like a dragon. A small one.', 'There is a map at the front. I ate it first.',
              'Book one of nine? Wonderful. Snacks for a year.', 'I am the chosen worm. Obviously.' },
  scifi = { 'I calculated the ship\'s orbit. It is fine. Probably.', 'Space is big. Books about it are bigger.',
            'If the robot is nice in chapter one, it is a trap.', 'Ready for lift-off. Page by page.' },
  adventure = { 'X marks the spot. I marked it with a crumb.', 'I packed a rope. Bookworms always pack a rope.',
                'A storm, a ship, a map. Perfect weather.', 'Onward! (Turn the page.)' },
  classic = { 'This one is older than the shelf. Delicious.', 'A thousand pages. I approve of the effort.',
              'One does not skim a classic. One chews.', 'Everyone in it is unhappy in their own way.' },
  nonfiction = { 'Did you know? I know. I ate the footnotes.', 'I am now an expert. On page 40 of it.',
                 'Facts are crunchy. Figures are chewy.', 'I underlined that. With my teeth.' },
}

-- a review when a book of that kind ends
L.REVIEW = {
  horror = { 'Finished {other}. I will never sleep again. Five crumbs.', '{other}: done. I am hiding behind the dictionary.' },
  mystery = { 'Finished {other}. I knew it all along. (I did not.)', '{other}: solved. Case closed, crumbs out of five: four.' },
  romance = { 'Finished {other}. They kissed! I cried into a margin.', '{other}: done. Happily ever after, my favourite flavour.' },
  fantasy = { 'Finished {other}. When is the next one? Now?', '{other}: done. The dragon was the best part.' },
  scifi = { 'Finished {other}. Back to Earth. It is so small.', '{other}: done. My antennae are still buzzing.' },
  adventure = { 'Finished {other}. Home at last, and covered in sand.', '{other}: done. I would sail with them again.' },
  classic = { 'Finished {other}. I feel taller and slightly sad.', '{other}: done. A classic for a reason.' },
  nonfiction = { 'Finished {other}. I am now unbearable at parties.', '{other}: done. Ask me anything. Anything in it.' },
}

-- the elder grumbles
L.ELDER = {
  'In my day, books had more pages.', 'My glasses need glasses.', 'I remember when this shelf was empty.',
  'Young worms these days. Audiobooks.', 'Back in my larva days, we chewed hardcovers.',
}

L.PET = {
  'Hehe. That tickles.',
  'Pat pat. More pages please.',
  'I purr. Bookworms can purr. Look it up.',
  'Mind the glasses.',
  'Again!',
}

L.DREAM = {
  'dreaming of {title}…',
  'dreaming of page {page}…',
  'dreaming of a library with no closing time…',
  'dreaming of the next chapter…',
}
L.DREAM_HUNGRY = { 'dreaming of snacks…', 'dreaming of a very long book…' }
L.DREAM_EGG = { 'an egg, resting' }

local function short(s, n)
  s = tostring(s or '')
  if utf8.len(s) and utf8.len(s) > n then
    local cut = utf8.offset(s, n) or (n + 1)
    return s:sub(1, cut - 1) .. '…'
  end
  return s
end
L.short = short

-- one line of list, by seed, with its fields filled in
function L.pick(list, seed, f)
  if not list or #list == 0 then return '' end
  local s = list[(seed % #list) + 1]
  f = f or {}
  return (s:gsub('{(%a+)}', function(k)
    local v = f[k]
    if v == nil or v == '' then
      if k == 'title' then return 'this book' end
      if k == 'pct' then return 'some' end
      return '…'
    end
    return tostring(v)
  end))
end

return L
