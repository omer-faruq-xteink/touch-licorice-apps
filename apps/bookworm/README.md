# Bookworm — XTOS Licorice mini app (API 2.9)

A little bookworm that lives on your reading. It uses the reader's own reading statistics (the
`reader` permission): how long you read each day, the books, your streak. Nothing leaves the
reader, and it does not see the text of your books.

- **It eats what you read.** Every minute in a book on this reader is food; ten minutes hatch its
  egg. It grows as the hours add up: hatchling, young (2 h), grown with round glasses (10 h),
  elder with a scholar's cap (40 h). At 100 hours it spins a cocoon and flies off as a moth,
  leaving an egg: the next generation, listed under **Family**.
- **It gets hungry.** A day without reading makes it peckish, then hungry and sulky; after a week
  it hides in a book until you read again. Five dots show how full it is.
- **It takes after you.** Its character comes from how you read: a night owl or an early bird
  (from when the reader goes to sleep after reading), a marathon reader or a nibbler, a butterfly
  with three books at once or loyal to one, a creature of habit (a streak), a finisher.
- **It has a taste.** From the authors and titles it eats (English and Turkish), it guesses what
  you mostly read: horror, mystery, romance, fantasy, science fiction, adventure, classics or
  non-fiction. It then wears something to match (a candle, a magnifier, a wizard's hat, a space
  helmet...), jokes about it and reviews those books in kind.
- **It talks** about the book it is eating, your day's reading, books you finish (it reviews
  them), the stage it reached. Tap it to pet it.
- **Diary**: the last two weeks, a bar a day with the book you read most. **Awards**: twelve
  milestones (hatching, books finished, streaks, a long sitting, hours, night owl, three books in a
  week, a new generation). **More**: rename it, make it the sleep screen, how it works.
- **Sleep screen**: it sleeps on an open book, dreaming of your book in a thought bubble (or of snacks when hungry);
  it brings itself up to date with the reading done before the reader slept, and wakes once an
  hour (the longest the reader allows).

An original character and drawings (circles and arcs, no image files), lines written for it.
Files: `src/pet.lua` (its life: stages, hunger, character, awards, generations), `src/taste.lua` (guessing the kind of book), `src/lines.lua`
(what it says), `src/art.lua` (its pictures), `src/main.lua` (on `tools/gamekit`), `src/lock/lock.lua`
(the sleep screen), `bundle.py` (index.lua and lockscreen.lua), `test_bookworm.py`
(`python -I apps/bookworm/test_bookworm.py`, with a stand-in for the reading statistics).
