"""Offline test of TBR Planner (gamekit harness with a stand-in reader): dates, adding a book from
the reader and by its title, the date buttons and Keep duration, the end date from the daily goal
(reading time for reader books, pages for typed ones), the lists and their sorting, Wishlist /
Planned / Done moves, the reader marking a book done, the calendar, Settings, saving, the lock
screen and the draw-command count.

  python -I apps/tbr/test_tbr.py
"""
import calendar as pycal, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game, STUBS  # noqa: E402
from lupa import lua54  # noqa: E402

OFF = 3 * 3600                                     # the reader is at UTC+3
NOW = pycal.timegm((2026, 10, 27, 9, 0, 0))        # 2026-10-27 12:00 local, a Tuesday
TODAY = NOW // 86400

READER = r'''
rb_all = {
  { id = 'e2_kirik', title = 'Kırık Ayna', first_date = '2026-10-23', last_date = '2026-10-27', sec = 406, finished = false },
  { id = 'e2_never', title = 'Never Flinch', first_date = '2026-10-22', last_date = '2026-10-26', sec = 6661, finished = false },
  { id = 'e2_bc', title = 'Business Central API', first_date = '2026-10-23', last_date = '2026-10-25', sec = 247, finished = true },
}
rb_cur = {
  { id = 'e2_never', title = 'Never Flinch', author = 'Stephen King', percent = 82, read_sec = 6661, finished = false, format = 'epub' },
  { id = 'e2_kirik', title = 'Kırık Ayna', author = 'Agatha Christie', percent = 0, read_sec = 406, finished = false, format = 'epub' },
}
ctx.reader = {
  all_books = function(self) return rb_all end,
  books = function(self) return rb_cur end,
  summary = function(self) return { streak_days = 4, today_sec = 720, total_sec = 8236 } end,
}
'''


def setup(L):
    L.execute(f"now_sec = {NOW}; ctx.clock.now = function(self) local w = now_sec + {OFF}; "
              "return { epoch_sec = now_sec, hour = w % 86400 // 3600, minute = w % 3600 // 60, second = w % 60 } end")
    L.execute("lock_calls = {}; ctx.lockscreen = { is_default = function(self) return lock_is end, "
              "set_default = function(self) lock_calls[#lock_calls + 1] = 'set'; lock_is = true end, "
              "clear_default = function(self) lock_calls[#lock_calls + 1] = 'clear'; lock_is = false end }")
    L.execute(READER)


g = Game(HERE)
setup(g.L)
g.restart()
ctx = g.L.globals().ctx
store = g.store
A = lambda: g.api
T = A().T
def typed(s): g.L.eval('inputs[#inputs]')(ctx, s)
def texts(): return g.texts()
def has(s): return any(s in t for t in texts())
def item(): return A().cur()

# ---- dates against Python's
for y, m, d in ((1970, 1, 1), (2000, 2, 29), (2026, 10, 27), (2037, 12, 31), (1969, 12, 31)):
    days = T.days(y, m, d)
    assert days == pycal.timegm((y, m, d, 0, 0, 0)) // 86400 and tuple(T.civil(days)) == (y, m, d)
    assert T.wday(days) == (pycal.weekday(y, m, d) + 1) % 7
assert T.today() == TODAY and T.long_date(TODAY) == 'Tuesday 27 October 2026' and T.iso(TODAY) == '2026-10-27'
assert T.parse_iso('2026/11/03') == TODAY + 7 and T.parse_iso('2026-02-30') is None and T.parse_iso('x') is None
assert T.duration(6661) == '1 h 51 min' and T.duration(1462) == '24 min'

# ---- the reader's books, merged
rb = A().rb()
assert rb['e2_never'].author == 'Stephen King' and rb['e2_never'].pct == 82 and rb['e2_never'].sec == 6661
assert rb['e2_bc'].finished and rb['e2_bc'].pct == 100 and rb['e2_kirik'].last == TODAY

# ---- empty: Planned is the first tab shown
t = texts()
assert 'Planned' in t and any('Nothing planned yet' in s for s in t), t
assert g.commands() < 900

# ---- a book from the reader: planned from today, the end from the 30-minute goal
g.tap_label('+ New')
assert has('Add a book')
g.tap_label('From the reader')
t = texts()
assert t.index('Kırık Ayna') < t.index('Never Flinch') < t.index('Business Central API'), t   # the last read first
assert any('Stephen King · 82% · read 26 Oct' in s for s in t) and any('finished' in s for s in t), t
g.tap_label('Never Flinch')
it = item()
assert A().screen() == 'item' and it.status == 'plan' and it.book == 'e2_never' and it.author == 'Stephen King'
assert it.start == TODAY and it['end'] == TODAY, (it.start, it['end'])     # 24 min left: one day at 30 min
t = texts()
assert '82% read, 1 h 51 min, ~24 min left' in t and 'Tue 27 Oct' in t, t
assert any(s.startswith('1 day, ends Tue 27 Oct') for s in t), t
# the date buttons (Start's row comes before End's); Keep duration moves the end with the start
def press(label, n=1):
    r = [x for x in g.draw() if str(x.s) == label][n - 1]
    g.tap(int(r.x) + 3, int(r.y) + 5)
press('+7')
assert (it.start, it['end']) == (TODAY + 7, TODAY + 7)
g.tap_label('Keep duration (Start moves End too)')
assert has('off   1 day')
press('-1')                                       # Keep duration off: the end stays
assert (it.start, it['end']) == (TODAY + 6, TODAY + 7), (it.start, it['end'])
press('+1', 2)                                    # End +1
assert it['end'] == TODAY + 8 and has('on   3 days') is False
g.tap_label('Keep duration (Start moves End too)')
press('-7', 2)                                    # End before Start: it stops at Start
assert it['end'] == TODAY + 6
g.tap_label('Set end')                            # what the goal gives from the start
assert it['end'] == TODAY + 6 and has('End set to Mon 2 Nov.')
# priority, tags
press('+'); press('+')
assert it.prio == 2
row = [r for r in g.draw() if str(r.s) == 'Tags (comma-separated)'][0]
g.tap(100, int(row.y) + 30)
typed(' horror, king ')
assert it.tags == 'horror, king'
g.key('back')
assert A().screen() == 'main'
t = texts()
assert 'Never Flinch' in t and any(s.startswith('Stephen King · 2 Nov · 82% · prio 2 · #ho') for s in t), t

# ---- a typed book: pages and the pages-a-day goal
g.tap_label('+ New')
g.tap_label('Type the title')
typed('Dune')
it2 = item()
assert it2.title == 'Dune' and it2.status == 'plan' and it2.start == TODAY and it2['end'] == TODAY + 13 and it2.book == ''
assert has('pages: tap to set') and has('No estimate: set the pages.')
g.tap_label('pages: tap to set')
typed('40/400')
assert it2.read == 40 and it2.pages == 400 and has('40 of 400 pages  (10%)')
g.tap_label('Set end')                            # 360 pages at 20 a day: 18 days
assert it2['end'] == TODAY + 17, it2['end']
# to the wishlist and back
g.tap_label('To wishlist')
assert it2.status == 'wish' and it2.start is None and it2['end'] is None
g.tap_label('Plan')
assert it2.status == 'plan' and it2.start == TODAY and it2['end'] == TODAY + 17
g.tap_label('Done')
assert it2.status == 'done' and it2.done == TODAY
g.key('back')

# ---- lists: Planned holds Never Flinch, Done holds Dune; a wishlist book typed in
g.tap_label('Done')
assert has('Dune') and any('done 27 Oct' in s for s in texts())
g.tap_label('Wishlist')
for title in ('Zorba', 'Anna Karenina'):
    g.tap_label('+ New')
    g.tap_label('Type the title')
    typed(title)
    assert item().status == 'wish'
    g.key('back')
z = [x for x in A().books().values() if x.title == 'Zorba'][0]
z.prio = 5
t = texts()
assert t.index('Zorba') < t.index('Anna Karenina'), t          # by priority
g.tap_label('Sort')
t = texts()
assert t.index('Anna Karenina') < t.index('Zorba') and any('by title' in s for s in t), t
assert 'sort_wish=title' in store['settings.txt']

# ---- the reader finishes a book: it moves to Done; "Not done" keeps it out
g.tap_label('+ New')
g.tap_label('From the reader')
g.tap_label('Kırık Ayna')
k = item()
assert k.status == 'wish' and k.author == 'Agatha Christie' and has('not started, 7 min'), (k.status, k.author, texts())
g.key('back')
g.L.execute("rb_all[1].finished = true; rb_cur[2].finished = true; rb_cur[2].percent = 100")
g.restart()
k = [x for x in A().books().values() if x.title == 'Kırık Ayna'][0]
assert k.status == 'done' and k.done == TODAY
g.tap_label('Done')
g.tap_label('Kırık Ayna')
g.tap_label('Not done')
assert k.status == 'wish' and k.auto == 0
g.restart()
k = [x for x in A().books().values() if x.title == 'Kırık Ayna'][0]
assert k.status == 'wish', k.status
g.L.execute("rb_all[1].finished = false; rb_cur[2].finished = false; rb_cur[2].percent = 0")
# picking a book already in the planner opens it
g.tap_label('Planned')
g.tap_label('+ New')
g.tap_label('From the reader')
assert any('in the planner' in s for s in texts())
g.tap_label('Never Flinch')
assert item().title == 'Never Flinch' and sum(1 for x in A().books().values() if x.book == 'e2_never') == 1
g.key('back')

# ---- the calendar: October, the bar, a day's box, the next month
g.tap_label('Calendar')
t = texts()
assert 'October 2026' in t and 'Mon' in t and 'Never Flinch' not in t, t     # 2 November: next month
g.tap_label('>')
t = texts()
assert 'November 2026' in t and 'Neve~' in t, t                # a one-day bar: one cell wide
assert g.commands() < 900, g.commands()
r = [x for x in g.draw() if str(x.s) == '2'][0]
g.tap(int(r.x) + 10, int(r.y) + 40)
t = texts()
assert 'Monday 2 November 2026' in t and 'Never Flinch' in t and '+ New from this day' in t, t
g.tap_label('+ New from this day')
g.tap_label('Type the title')
typed('Solaris')
s = item()
assert s.start == TODAY + 6 and s.status == 'plan'
g.key('back')
assert has('November 2026') and A().month() == TODAY + 5 and has('Solaris')
g.tap_label('Today')
assert A().month() == TODAY - 26

# ---- settings: the goal, the lock screen
g.tap_label('More')
g.tap_label('Daily reading goal: 30 min')
assert A().cfg.minutes == 45 and 'minutes=45' in store['settings.txt']
g.tap_label('Lock screen: off')
assert list(g.L.eval('lock_calls').values()) == ['set'] and has('Lock screen: on')
g.tap_label('Filter: none (tap to set)')
typed('king')
g.tap_label('Back')
g.tap_label('Planned')
t = texts()
assert 'Never Flinch' in t and 'Solaris' not in t and any('filter "king"' in s for s in t), t
g.tap_label('More')
g.tap_label('Filter: "king"')
typed('')
g.tap_label('Back')

# ---- saved: a restart brings everything back
n = len(A().books())
g.restart()
assert len(A().books()) == n and any(x.title == 'Never Flinch' and x.prio == 2 and x.tags == 'horror, king' for x in A().books().values())
g.no_err()


# ---- the lock screen
def lock_texts(extra=''):
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    L.execute(STUBS)
    for k2, v in store.items():
        L.globals().store[k2] = v
    setup(L)
    L.execute(extra)
    L.execute(f"dofile([[{os.path.join(HERE, 'lockscreen.lua').replace(os.sep, '/')}]])")
    L.execute('drawn, commands = {}, 0; on_draw(ctx, gg)')
    return [str(d.s) for d in L.globals().drawn.values()], int(L.globals().commands)


t, n = lock_texts()
assert t[:2] == ['Reading plan', 'Tuesday 27 October 2026'] and not any('lock error' in s for s in t), t
assert 'Nothing planned for today.' in t and 'Coming up' in t and '2 Nov  Never Flinch' in t, t
assert 'Reading: streak 4 days, today 12 min' in t and n < 900, t
# moved to today: it is today's book, with its progress
t, n = lock_texts(f"now_sec = {NOW + 6 * 86400}")
assert 'Today' in t and 'Never Flinch' in t, t
assert any(s.startswith('Stephen King · 82% · ends today · ~24 min') for s in t), t
# later still: late
t, n = lock_texts(f"now_sec = {NOW + 9 * 86400}")
assert any('3 days late' in s for s in t), t
print('tbr tests passed')
