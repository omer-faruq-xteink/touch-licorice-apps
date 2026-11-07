# Timekeeper — XTOS Licorice mini app

Timers, a focus timer (Pomodoro), a stopwatch, an interval timer, counters and a log of focus time
in one app, with a lock screen that shows what runs. Everything keeps running when you leave the
app, lock the reader or power it off: each running thing is kept as the moment it ends (or
started), not as the time left.

## The tabs

- **Timer**: up to six named timers (Tea, Eggs and Nap to start with). The buttons under the list
  change the chosen timer's length (-5, -1, +1, +5, +30 minutes); **Edit** does too, and takes a
  typed length (`12` or `1:30`), a new name, or deletes the timer. Start, Pause, Resume, Reset;
  when one runs out it says *time's up!* and offers **Again**.
- **Focus**: work and breaks in turn (25 minutes of focus, 5 minutes of break, a long break of 15
  after every 4; all of it can be changed while it is not running). The next part can start by
  itself. **Skip** ends the current part (a skipped focus is not logged).
- **Watch**: a stopwatch with laps.
- **Sets**: rounds of work and rest for exercise (8 rounds of 40 s work and 20 s rest to start
  with); it shows the seconds while it runs.
- **Count**: up to six named tally counters. The large **+1** (or the number itself) adds one; on
  this tab the side buttons count too (down +1, up -1); -1, +10, Reset, New, Edit below.
- **Log**: today's focus and the last seven days as bars.

The time of day is in the top bar (More turns it off).

## Light on power

E-ink uses power with every refresh, so a running timer shows **whole minutes** and the app wakes
only when that number changes, when something ends, or for the clock's minute. A **tap on the big
digits** shows the seconds once (*at 14:17:11, tap again*), until the minute changes. More sets
when the seconds tick by themselves: never, in a countdown's **last minute** (the default), or
always (a refresh every second). Sets always shows its seconds while it runs.

## When time is up

The reader has no sound or vibration, so an end is shown:

- with the app open, the screen **flashes** four times (a dark page with the message, then the
  normal one); a tap stops it. More turns this off.
- **Stay awake while running** (More, on by default; firmware 26110201 or later): while something
  runs the reader does not go to sleep on its own, so the end is seen. It sleeps as usual once
  nothing runs. This uses more battery.
- on the **lock screen** (More → Lock screen; the reader asks to make it the lock screen): the
  minutes left of the first running thing in large digits with the time it ends, the others below,
  and today's focus. Around an end it wakes every 30 seconds instead of every minute, and for 3
  minutes after it every other wake is a dark *Time's up!* page: a slow blink, since the lock
  screen draws one frame each time the reader wakes it.

## Files

`src/main.lua` (on `tools/gamekit`), `lockscreen.lua`, `bundle.py` (builds `index.lua`),
`test_timekeeper.py` (`python -I apps/timekeeper/test_timekeeper.py`: the tabs by taps with a
stand-in clock and timers, the wakes, a restart, lock.txt and the lock screen's blink).
The app keeps its state in `timekeeper.txt` and writes `lock.txt` for the lock screen.
