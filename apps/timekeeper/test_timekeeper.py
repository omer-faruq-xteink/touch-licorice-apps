"""Offline test of Timekeeper (gamekit harness, with a stand-in clock and ctx:after): timers start,
pause, run out while the app sleeps and say so; the focus timer logs a focus and starts the break
by itself; the stopwatch keeps laps; the interval timer runs its rounds; counters count; the app
wakes only when the shown minute changes, something ends, or seconds are wanted (last minute, a
tap on the digits); everything survives a restart; lock.txt and the lock screen show what runs;
Back on the main screen is left to the host; every tab stays under the draw-command limit.

  python -I apps/timekeeper/test_timekeeper.py
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

g = Game(HERE)
L = g.L
L.execute('''
EPOCH = 1794000000            -- 2026-11-06 ~ 22:40 UTC
OFFSET = 3 * 3600             -- the reader's wall clock: UTC+3
waker = nil
local function M(t)
  local out = {}
  for k, f in pairs(t) do out[k] = function(self, ...) return f(...) end end
  return out
end
ctx.clock = M({
  now = function()
    local w = (EPOCH + OFFSET) % 86400
    return { epoch_sec = EPOCH, hour = w // 3600, minute = w // 60 % 60, second = w % 60, valid = true }
  end,
  millis = function() return EPOCH * 1000 end,
})
pending = {}
ctx.after = function(self, ms, fn)
  local w = { due = EPOCH * 1000 + ms, ms = ms, fn = fn }
  w.cancel = function(me) for i, x in ipairs(pending) do if x == me then table.remove(pending, i); return end end end
  pending[#pending + 1] = w
  return w
end
lock_default = false
awake_calls = {}
ctx.device = M({ keep_awake = function(ms) awake_calls[#awake_calls + 1] = ms end })
ctx.lockscreen = M({ is_default = function() return lock_default end, set_default = function() lock_default = true end,
                     clear_default = function() lock_default = false end })
-- move the clock on; pending wakes fire in order when their time has come
function advance(s)
  local target = (EPOCH + s) * 1000
  while true do
    local best, bi = nil, nil
    for i, x in ipairs(pending) do
      local d = x.ms >= 1000 and x.due // 1000 * 1000 or x.due     -- wakes land on the second; the flash's steps do not
      if d <= target and (not best or x.due < best.due) then best, bi = x, i end
    end
    if not best then break end
    table.remove(pending, bi)
    EPOCH = best.due // 1000
    best.fn(ctx)
  end
  EPOCH = target // 1000
end
waker = nil
function wake_in()
  local best = nil
  for _, x in ipairs(pending) do local d = (x.due - EPOCH * 1000) // 1000; if not best or d < best then best = d end end
  return best
end
for k in pairs(store) do store[k] = nil end
''')
g.restart()
A = lambda: g.api
advance = L.eval('advance')
wake_in = lambda: L.eval('wake_in')()


def calm():
    """a tap ends the flashing that follows an end"""
    if int(A().flash()) > 0:
        g.tap(5, 5)
        assert int(A().flash()) == 0


assert 'Timekeeper' in g.texts()
assert 'no sound' in ' '.join(g.texts()), 'the first run explains'
g.tap_label('Close')
assert [str(t.name) for t in A().timers().values()] == ['Tea', 'Eggs', 'Nap']
g.no_err()
# the clock in the header: the time, and a wake on the next minute; off for the rest of the test
assert '00:20' in g.texts(), g.texts()                 # 21:20 UTC at UTC+3
assert wake_in() == 60, wake_in()
g.tap_label('More')
g.tap_label('Clock: on')
g.tap_label('Close')
assert '00:20' not in g.texts()
assert wake_in() is None, 'nothing runs: no wake'

# ---- Timer: Tea (4 min) runs; whole minutes; it ends while nobody looks
assert int(A().awake()) == 0
g.tap_label('Start')
assert int(A().awake()) == (60 + 120) * 1000, A().awake()     # awake until a little after the next wake
tea = A().timers()[1]
assert int(tea.ends) == int(A().now()) + 240
assert wake_in() == 60, wake_in()           # 4 min shown until 3:00 left
secs, countdown, running = A().shown()
assert int(secs) == 240 and countdown and running
assert any('Tea' in t and 'ends at' in t for t in g.texts()), g.texts()
advance(60)
assert int(A().shown()[0]) == 180 and wake_in() == 60
advance(120)                                 # 1:00 left: the last minute shows seconds
assert int(A().shown()[0]) == 60 and wake_in() == 1, wake_in()
advance(60)
assert A().timers()[1].ready and "Tea: time's up!" == str(A().msg()), A().msg()
assert int(A().awake()) == 0 and int(L.eval('awake_calls[#awake_calls]')) == 0, 'nothing runs: sleep as usual'
assert int(A().flash()) > 0, 'time is up with the app open: the screen flashes'
assert len(g.rects()) >= 2 and g.rects()[0].fill, 'a dark frame'
advance(10)
assert int(A().flash()) == 0, 'the flashing ends by itself'
assert any("time's up" in t for t in g.texts())
assert wake_in() is None
g.tap_label('Again')
assert not A().timers()[1].ready and int(A().timers()[1].ends) == int(A().now()) + 240
g.tap_label('Pause')
assert int(A().timers()[1].left) == 240 and A().timers()[1].ends is None
g.tap_label('Reset')
assert A().timers()[1].left is None
# the length of a timer
g.tap_label('+5')
assert int(A().timers()[1].dur) == 540
g.tap_label('-1')
assert int(A().timers()[1].dur) == 480
# a tap on the digits shows the seconds until the next minute
g.tap_label('Start')
advance(10)
assert A().exact() is None
g.draw()
g.tap(240, 200)
assert int(A().exact()) == int(A().now()) + 50 and wake_in() == 50, wake_in()   # one refresh, frozen
assert any(' at ' in t and 'tap again' in t for t in g.texts()), g.texts()
advance(50)
assert A().exact() is None and wake_in() == 60
g.tap_label('Reset')
# Edit: the length by steps and typed (minutes or h:mm), and the name
g.tap_label('Edit')
assert any(t.startswith('Tea: 8:00') for t in g.texts()), g.texts()
g.tap_label('+5')
assert int(A().timers()[1].dur) == 780 and any(t.startswith('Tea: 13:00') for t in g.texts())
g.tap_label('Type it')
L.eval('inputs[#inputs]')(L.eval('ctx'), '1:30')
assert int(A().timers()[1].dur) == 5400
g.tap_label('Edit')
g.tap_label('Type it')
L.eval('inputs[#inputs]')(L.eval('ctx'), '8')
assert int(A().timers()[1].dur) == 480
g.tap_label('Edit')
g.tap_label('Rename')
L.eval('inputs[#inputs]')(L.eval('ctx'), 'Green tea')
assert str(A().timers()[1].name) == 'Green tea'
A().timers()[1].name = 'Tea'
print('timer: whole minutes, the last minute in seconds, ends while away, Again, Pause, Reset')

# ---- Focus: 25 minutes, logged, the break starts by itself
g.tap_label('Focus')
assert int(A().tab()) == 2
g.tap_label('Start')
f = A().focus()
assert int(f.ends) == int(A().now()) + 1500
advance(1500)
calm()
f = A().focus()
assert str(f.phase) == 'short' and int(f.ends) == int(A().now()) + 300, (f.phase, f.ends)
day = int(A().today())
assert int(A().log()[day][1]) == 25 and int(A().log()[day][2]) == 1
assert 'break' in str(A().msg())
advance(300)
calm()
assert str(A().focus().phase) == 'work' and int(A().focus().round) == 2
g.tap_label('Skip')
assert str(A().focus().phase) == 'short' and int(A().log()[day][2]) == 1, 'a skipped focus is not logged'
g.tap_label('Reset')
assert str(A().focus().phase) == 'work' and int(A().focus().round) == 1 and A().focus().ends is None
# lengths change while it is not running
before = int(A().focus().work)
g.draw()                                     # the reader redraws after every input
g.tap(436, 364)                              # the + of the focus length
assert int(A().focus().work) == before + 5, A().focus().work
print('focus: logged, the break by itself, Skip, Reset, lengths')

# ---- Watch: laps, keeps running
g.tap_label('Watch')
g.tap_label('Start')
advance(125)
g.tap_label('Lap')
advance(35)
g.tap_label('Stop')
w = A().watch()
assert [int(x) for x in w.laps.values()] == [125] and int(w.acc) == 160 and w.start is None
assert int(A().shown()[0]) == 160
assert 'Lap 1' in g.texts() and '2:05' in g.texts(), g.texts()
g.tap_label('Reset')
assert int(A().watch().acc) == 0
g.tap_label('Start')
assert wake_in() == 60, wake_in()           # whole minutes while running
advance(30)
print('watch: laps, stop, reset')

# ---- Rounds: 2 rounds of 10 s work, 5 s rest
g.tap_label('Sets')
r = A().rounds()
r.work, r.rest, r.count = 10, 5, 2
g.tap_label('Start')
assert wake_in() == 1, 'seconds while it runs'
advance(12)
assert any('Rest' in t and 'round 1 of 2' in t for t in g.texts()), g.texts()
advance(20)
calm()
assert 'Rounds done' in str(A().msg()) and A().rounds().start is None
print('rounds: work, rest, done')

# ---- Count
g.tap_label('Count')
g.draw()
g.tap(240, 200)
g.draw()
g.tap(240, 200)
g.tap_label('+10')
g.tap_label('-1')
assert int(A().counters()[1].n) == 11
g.tap(240, 380)                                   # the big +1
assert int(A().counters()[1].n) == 12
g.key('down'); advance(1); g.key('down'); advance(1); g.key('up')   # on Count the side buttons count (a press each second)
assert int(A().counters()[1].n) == 13 and int(A().tab()) == 5
g.tap_label('-1'); g.tap_label('-1')

# ---- restart: all kept; the stopwatch still runs, the tab is kept
g.tap_label('Timer')
g.tap_label('Start')
ends = int(A().timers()[1].ends)
L.execute('pending = {}')
g.restart()
assert int(A().timers()[1].ends) == ends and A().watch().start is not None and int(A().counters()[1].n) == 11
assert int(A().log()[day][1]) == 25
assert wake_in() is not None
print('restart: everything kept')

# ---- lock.txt and the lock screen
lock = str(g.store['lock.txt'])
assert lock.startswith('end|Tea|') and '\nfrom|Stopwatch|' in lock and lock.endswith('today|25|1'), lock
L.execute(f"dofile([[{os.path.join(HERE, 'lockscreen.lua').replace(os.sep, '/')}]])")
texts = g.texts()
assert any(t.startswith('min left · until ') for t in texts), texts
assert 'Tea' in texts and 'Stopwatch' in texts and any(t.startswith('Today: 1 focus, 25 min') for t in texts), texts
assert g.commands() < 1024
lock_iv = []
L.globals().ctx.lock = L.eval("{ set_interval = function(self, n) lock_iv[#lock_iv + 1] = n end }")
L.execute('lock_iv = {}')
g.texts()
assert int(L.eval('lock_iv[#lock_iv]')) == 60, 'far from any end: once a minute'
ends = int(A().timers()[1].ends)
L.execute(f'EPOCH = {ends} - 60')
g.texts()
assert int(L.eval('lock_iv[#lock_iv]')) == 30, 'near an end: every 30 s'
L.execute(f'EPOCH = {ends} + 5')
dark = lambda: (lambda rs: bool(rs) and bool(rs[0].fill) and int(rs[0].w) == 480)(g.rects())
assert dark() and "Time's up!" in g.texts(), 'just ended: the dark frame'
L.execute(f'EPOCH = {ends} + 35')
assert not dark() and "time's up!" in g.texts(), 'then the light one'
L.execute(f'EPOCH = {ends} + 65')
assert dark(), 'dark again'
L.execute(f'EPOCH = {ends} + 400')
g.texts()
assert not dark() and int(L.eval('lock_iv[#lock_iv]')) == 60, 'after 3 minutes: still, once a minute'
texts = g.texts()
assert "time's up!" in texts, texts
g.restart()

# More: lock screen and seconds
g.tap_label('More')
g.tap_label('Lock screen: off')
assert L.eval('lock_default') is True
g.tap_label('More')
g.tap_label('Seconds: last minute')
assert str(A().seconds()) == 'on'
g.tap_label('Stay awake while running: on')
assert 'Stay awake while running: off' in g.texts()
g.tap_label('Close')

# Back: closes a box; on the main screen it is left to the host
back = lambda phase: L.eval(f"on_input(ctx, {{type='key', key='back', phase='{phase}'}})")
g.tap_label('More')
back('down')
assert back('up') is True
back('down')
assert back('up') is False

# every tab, full: under the draw-command limit
for name in ('Timer', 'Focus', 'Watch', 'Sets', 'Count', 'Log'):
    g.tap_label(name)
    assert g.commands() < 1024, (name, g.commands())
g.tap_label('Log')
assert any('25 min' in t for t in g.texts()) and 'Today' in g.texts()
g.no_err()
print('all good')
