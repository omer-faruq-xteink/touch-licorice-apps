# Backgammon — XTOS Licorice mini app (API 2.0)

Backgammon (tavla) against the reader at four levels, or two players on one reader.

- **The board**: you are White, at the bottom, and move counter-clockwise: from 24 (top right)
  along the top, down the left side and along the bottom into your home board (1 to 6, bottom
  right), then off into the tray on the right. The reader (Black) moves the other way. The
  numbers along the edges are White's; the reader's plays are written in them too.
- **A turn**: tap **Roll**, then a checker: the points it can reach are marked, with one die or
  several (a combined move goes in one tap, through a point where it may land). The tray is
  marked when it can bear off. A checker on the bar is picked by itself, as it must come in
  first. The turn ends once the dice are played; with no move it passes.
- **Taps forgive a near miss** (the points are 34 px wide): a tap close to a marked point plays
  it, a tap just off a checker picks it, tapping an empty point that only one checker can reach
  moves that checker there (when two can, the app asks you to tap the one), and the picked
  checker tapped again moves with the higher die.
- **Rules**: both dice must be played when they can be, the larger one when only one of them
  can; doubles are played four times; a single checker hit goes to the bar; bearing off once all
  fifteen are home, a higher die from the highest point. A game counts 1, a **gammon** 2 (the
  loser has borne off nothing), a **backgammon** 3 (and still has a checker on the bar or in the
  winner's home board).
- **New match** (Menu): the reader at Beginner, Easy, Medium or Hard, or two players; single
  games with a running score, or a match to 3, 5 or 7 points; with or without the **doubling
  cube**. Without it the game plays like Turkish tavla. With it, Double is offered before your
  roll: the other side takes (the cube doubles and goes to it) or passes (and loses the points
  on the cube). In a match the game after a side reaches one point from winning is the
  **Crawford game**, without doubling.
- **Undo** takes back the last checker, or your whole last turn and the reader's reply. The same
  dice come again (the rolls that followed are kept for the replay), so taking back never changes
  the luck. **Hint** frames a good play. The game is kept when you leave.

## The reader

`src/engine.lua` scores a position after a play: once the sides are past each other it is a race
counted in pips; with contact, the pips, the points made (the 5, 4 and 6 points most, then the bar
point; anchors in the other home board), primes, the shots at each blot from every enemy checker
behind it and what being hit would cost, checkers on the bar against a strong home board, stacks
and checkers off. Beginner plays at random half the time, Easy picks the best-looking play with
some noise, Medium the best-looking one, and Hard looks one roll ahead: for its four best plays
it averages the reader's position over all 21 replies (each the other side's best play), within
about 8 seconds, thinking in slices between frames as Chess and Checkers do. It doubles at about
a 70 % chance to win and takes a double with at least 25 %. In self-play Medium beats Beginner 29
games of 30, and Hard wins most games against Medium.

## Files

`src/rules.lua` (the moves, the plays of a roll one per resulting position, the results),
`src/engine.lua`, `src/main.lua` (on `tools/gamekit`), `bundle.py`, `test_backgammon.py`
(`python -I apps/backgammon/test_backgammon.py`: the rules, the engine against known openings and
in self-play, and games by taps: Undo with the same dice, the bar, no move, the cube and the
Crawford game, the end of a game and a match, the game kept, Back and Hint).
