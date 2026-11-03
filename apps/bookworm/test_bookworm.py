"""Offline test of Bookworm (gamekit harness and a stand-in for the reader's statistics): the egg
laid and hatched by ten minutes of reading, growing up, a finished book, hunger and hiding, the
night-owl character, a moth leaving an egg for the next generation, the awards; the screens
(Diary, Awards, Family, How it works, More, renaming, the sleep screen switch), Back, a pat; a
reader without statistics; and the sleep screen in a session of its own.

  python -I apps/bookworm/test_bookworm.py
"""
import os, sys
from lupa import lua54
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game, STUBS  # noqa: E402

READER = r'''
R = { total = 5000, today = 0, streak = 0, best = 0, books = {}, current = nil, daysec = {}, bookdays = {} }
NOW = { valid = true, year = 2026, month = 11, day = 3, hour = 21, minute = 30, second = 0 }
ctx.clock.now = function(self) return NOW end
ctx.state = {}
saves = 0
ctx.save_state = function(self) saves = saves + 1; return true end
ctx.reader = {
  summary = function(self) return { total_sec = R.total, today_sec = R.today, streak_days = R.streak, best_streak_days = R.best } end,
  books = function(self) return R.books end,
  current = function(self) return R.current end,
  days = function(self, from, to)
    local out = {}
    for d, s in pairs(R.daysec) do if d >= from and d <= to then out[#out + 1] = { date = d, sec = s } end end
    table.sort(out, function(a, b) return a.date < b.date end)
    return out
  end,
  book_days = function(self, from, to)
    local out = {}
    for _, r in ipairs(R.bookdays) do if r.date >= from and r.date <= to then out[#out + 1] = r end end
    return out
  end,
}
lock_default, inputs_done = false, {}
ctx.lockscreen = { is_default = function(self) return lock_default end, set_default = function(self) lock_default = true end,
                   clear_default = function(self) lock_default = false end }
'''

g = Game(HERE)
L = g.L
L.execute(READER)
g.restart()
A = lambda: g.api
P = g.api.P


def date(day_offset):
    return P.date(P.days_from_civil(2026, 11, 3) + day_offset)


def read(minutes, day=0, hour=23, title='Dune', book='b1', finished=False, pct=40):
    """minutes of reading on day (offset from 3 Nov), the clock then at that day and hour"""
    y, m, d = P.civil(P.days_from_civil(2026, 11, 3) + day)
    L.execute(f'NOW = {{ valid = true, year = {y}, month = {m}, day = {d}, hour = {hour}, minute = 30, second = 0 }}')
    dt = date(day)
    L.execute(f'''
      R.total = R.total + {minutes * 60}
      R.daysec["{dt}"] = (R.daysec["{dt}"] or 0) + {minutes * 60}
      R.today = R.daysec["{dt}"]
      R.current = {{ id = "{book}", title = "{title}", percent = {pct}, page = 120, total_pages = 300, finished = {str(finished).lower()} }}
      local found = false
      for _, b in ipairs(R.books) do if b.id == "{book}" then b.finished = {str(finished).lower()}; found = true end end
      if not found then R.books[#R.books + 1] = {{ id = "{book}", title = "{title}", finished = {str(finished).lower()} }} end
      R.bookdays[#R.bookdays + 1] = {{ date = "{dt}", id = "{book}", title = "{title}", sec = {minutes * 60} }}
    ''')
    L.execute('on_resume(ctx)')


def day(n, hour=12):
    """a day passes without reading"""
    y, m, d = P.civil(P.days_from_civil(2026, 11, 3) + n)
    L.execute(f'NOW = {{ valid = true, year = {y}, month = {m}, day = {d}, hour = {hour}, minute = 0, second = 0 }}; R.today = 0')
    L.execute('on_resume(ctx)')


S = lambda: A().state()
V = lambda: A().view()
texts = lambda: ' '.join(g.texts())

# an egg, laid with the reading already done: it does not count as food
assert not S().hatched and S().gen == 1 and S().base == 5000, (S().hatched, S().base)
assert 'Hatches after 10 min' in texts(), texts()
assert any(x in A().line() for x in ('egg', 'Ten minutes', 'wobbled')), A().line()
assert g.commands() < 900, g.commands()

# ten minutes hatch it, and it says so
read(11)
assert S().hatched and V().stage_key == 'hatchling', V().stage_key
assert 'Dune' in A().line() or 'hatched' in A().line().lower(), A().line()
assert S().awards['hatch'] and 'Award: Hatched' in texts(), texts()
g.no_err()

# two hours: young; ten: grown, with its glasses; it tells
read(110, day=1)
assert V().stage_key == 'young', V().stage_key
assert 'young bookworm' in A().line(), A().line()
for k in range(2, 9):
    read(80, day=k)
assert V().stage_key == 'grown' and 'Fed 10 h' in texts() or V().stage_key == 'grown', (V().stage_key, texts())

# a book finished
read(30, day=9, finished=True, pct=100)
assert S().finished == 1 and S().awards['book1'], S().finished
assert 'Dune' in A().line(), A().line()

# read at night: a night owl
assert V().trait == 'owl' and S().awards['owl'], (V().trait, dict(S().tod))
assert 'night owl' in texts(), texts()

# hunger: a day without reading, three, eight (it hides)
day(10)
assert V().hunger == 'peckish', V().hunger
day(12)
assert V().hunger == 'hungry', V().hunger
day(17)
assert V().hunger == 'hiding' and ('rustles' in A().line() or 'hiding' in A().line() or 'tiny voice' in A().line()), A().line()
read(20, day=17)
assert V().hunger == 'full', V().hunger

# its taste: guessed from author and title, English and Turkish; read horror and it takes after it
T = L.eval(f"dofile([[{os.path.join(HERE, 'src', 'taste.lua').replace(os.sep, '/')}]])")
for title, author, kind in [('The Shining', 'Stephen King', 'horror'), ('It', 'King, Stephen', 'horror'),
                            ('Murder on the Orient Express', 'Agatha Christie', 'mystery'), ('The Hobbit', 'J.R.R. Tolkien', 'fantasy'),
                            ('Foundation', '', 'scifi'), ('Kürk Mantolu Madonna', 'Sabahattin Ali', 'classic'),
                            ('İstanbul Hatırası', 'Ahmet Ümit', 'mystery'), ('Ejderha Mızrağı', '', 'fantasy'),
                            ('Atomic Habits', 'James Clear', 'nonfiction'), ('Ask Again, Yes', 'Mary Beth Keane', None)]:
    assert T.guess(title, author) == kind, (title, author, T.guess(title, author))
for k in range(18, 26):
    read(150, day=k, title='Dracula', book='b2', pct=50)
L.execute('for _, b in ipairs(R.books) do if b.id == "b2" then b.author = "Bram Stoker" end end')
read(150, day=26, title='Dracula', book='b2', pct=90)
assert V().taste == 'horror' and 'a horror fan' in texts(), (V().taste, dict(S().taste))
read(10, day=26, title='Dracula', book='b2', pct=100, finished=True)
assert any(w in A().line() for w in ('never sleep', 'hiding behind')), A().line()
assert g.commands() < 900, g.commands()

# a pat
pets = S().pets
g.tap(240, 260)
assert S().pets == pets + 1 and A().line() in [s for s in A().L.PET.values()], A().line()

# the screens
g.tap_label('Diary')
assert A().screen() == 'diary' and 'Diary' in texts() and 'Dracula' in texts(), texts()
assert g.commands() < 900
L.execute("on_input(ctx, {type='key', key='back', phase='down'})")
back_home = L.eval("on_input(ctx, {type='key', key='back', phase='up'})")
assert A().screen() == 'home' and back_home is True
assert L.eval("on_input(ctx, {type='key', key='back', phase='up'})") is False, 'Back on the home screen leaves it to the host'
g.tap_label('Awards')
assert 'Hatched' in texts() and 'A new generation' in texts(), texts()
g.tap_label('Back')
g.tap_label('Family')
assert 'generation 1 (now)' in texts(), texts()
g.tap_label('Back')
g.tap_label('More')
assert 'Use as sleep screen' in texts()
g.tap_label('Use as sleep screen')
assert L.eval('lock_default') is True
g.tap_label('More')
assert 'Stop sleep screen' in texts()
g.tap_label('Close')
g.tap_label('More'); g.tap_label('Rename')
L.execute('inputs[#inputs](ctx, "Professor Crumb")')
assert S().name == 'Professor Crumb' and 'Professor Crumb' in texts(), S().name
g.tap_label('More'); g.tap_label('How it works')
assert 'How it works' in texts() and A().screen() == 'help'
g.tap_label('Back')

# a hundred hours: a moth flies off and leaves an egg
L.execute('R.total = R.total + 100 * 3600')
read(5, day=28)
assert S().gen == 2 and not S().hatched and len(S().lineage) == 1 and S().awards['moth'], (S().gen, len(S().lineage))
assert S().lineage[1].name == 'Professor Crumb' and 'Professor Crumb' in A().line(), A().line()
g.tap_label('Family')
assert 'Professor Crumb, generation 1' in texts(), texts()
g.tap_label('Back')
# kept over a restart (the host keeps ctx.state)
g.restart()
assert S().gen == 2 and len(S().lineage) == 1

# the sleep screen: its own entry (lockscreen.lua) loaded over the app, with the same saved state
# and the reading done since; it sets the hourly wake, draws the bookworm and saves the state
lock = L
lock.execute('intervals = {}; saves = 0; ctx.lock = { reason = "first", set_interval = function(self, s) intervals[#intervals + 1] = s end }')
lock.execute(f"dofile([[{os.path.join(HERE, 'lockscreen.lua').replace(os.sep, '/')}]])")
lock.execute('R.total = R.total + 11 * 60; R.today = 11 * 60')
lock.execute('''
  said = {}
  rec = setmetatable({}, { __index = function(_, k) return function(_, ...)
    local a = { ... }
    if k == 'text' then said[#said + 1] = a[3] elseif k == 'text_box' then said[#said + 1] = a[5] end
    return gg[k](gg, ...)
  end end })
  drawn, commands = {}, 0; on_load(ctx); on_draw(ctx, rec)
''')
assert list(lock.eval('intervals').values()) == [3600]
drawn = [str(v) for v in lock.eval('said').values()]
assert any(S().name in s for s in drawn) and any('dreaming' in s or 'resting' in s for s in drawn), drawn
assert S().hatched, 'the reading before sleep hatched the new egg'
assert int(lock.eval('saves')) == 1 and int(lock.eval('commands')) < 900, (lock.eval('saves'), lock.eval('commands'))
# a book not paginated yet has no page number: no dream of "page …"
lock.execute('R.current.page = nil; for h = 0, 23 do NOW.hour = h; said = {}; on_draw(ctx, rec) ; for _, s in ipairs(said) do assert(not tostring(s):find("page"), s) end end')

# a reader that keeps its statistics to itself
L.execute('ctx.reader = nil; ctx.state = {}')
g.restart()
assert 'does not share its reading statistics' in texts(), texts()
print(f'bookworm: all tests passed')
