"""Offline test of Tasks (gamekit harness): lists.txt read and written as plain text, lists and
items added, ticked, edited, moved and deleted, Clear done (after asking), the lock screen
(lock.txt and the firmware's question), lockscreen.lua drawing the open items, repeating items
(set from the menu, ticked, back when due, kept by Clear done, on the lock screen from their day)
and the draw-command count.

  python -I apps/tasks/test_tasks.py
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game, STUBS  # noqa: E402
from lupa import lua54  # noqa: E402

g = Game(HERE)
A = lambda: g.api
TOP, ROW_H = 96, 64
g.L.execute("lock_calls = {}; ctx.lockscreen = { is_default = function(self) return lock_is end, "
            "set_default = function(self) lock_calls[#lock_calls + 1] = 'set'; lock_is = true end, "
            "clear_default = function(self) lock_calls[#lock_calls + 1] = 'clear'; lock_is = false end }")
ctx = g.L.globals().ctx
ctx.storage.remove = lambda self, n: g.store.__setitem__(n, None)
hold = g.L.eval("function(x, y) on_input(ctx, {type='pointer', phase='down', x=x, y=y}); "
                "for k = 1, 3 do on_input(ctx, {type='pointer', phase='hold', gesture='long', x=x, y=y}) end; "
                "on_input(ctx, {type='pointer', phase='up', x=x, y=y}) end")


def typed(s): g.L.eval('inputs[#inputs]')(ctx, s)
def row(k): return TOP + (k - 1) * ROW_H + 30
def items(): return [(str(it.text), bool(it.done)) for it in A().lists()[A().cur()]['items'].values()]


# the plain-text file: read, and written back the same way
g.store['lists.txt'] = '# Shopping\n[ ] bread\n[x] milk\n\n# Work\n[ ] mail Ayşe\n'
g.restart()
t = g.texts()
assert 'Tasks' in t and 'Shopping' in t and 'Work' in t and '1 to do, 1 done' in t, t
assert A().serialize() == '# Shopping\n[ ] bread\n[x] milk\n\n# Work\n[ ] mail Ayşe\n'

# open a list, tick, add, edit, move, delete
g.tap(200, row(1))
assert str(A().screen()) == 'list' and items() == [('bread', False), ('milk', True)]
g.tap(30, row(1))                                         # the box
assert items()[0] == ('bread', True)
g.tap(30, row(1))
g.tap_label('Add'); typed('eggs')
assert items()[-1] == ('eggs', False) and '[ ] eggs' in g.store['lists.txt']
g.tap(200, row(3)); g.tap_label('Edit'); typed('eggs (6)')
assert items()[-1] == ('eggs (6)', False)
g.tap(200, row(3)); g.tap_label('Up')
assert [i[0] for i in items()] == ['bread', 'eggs (6)', 'milk']
hold(200, row(1)); g.tap_label('Delete')                  # a long press opens the same menu
assert [i[0] for i in items()] == ['eggs (6)', 'milk']

# Clear done asks first; nothing ticked: says so
g.tap_label('Clear done')
assert 'Clear 1 done item?' in g.texts()
g.tap_label('Cancel')
assert len(items()) == 2
g.tap_label('Clear done'); g.tap_label('Clear')
assert items() == [('eggs (6)', False)] and '1 cleared.' in g.texts()
g.tap_label('Clear done')
assert 'Nothing to clear.' in g.texts()

# the lock screen: this list's open items, the firmware asked once
g.tap_label('List'); g.tap_label('Lock screen')
assert list(g.L.eval('lock_calls').values()) == ['set']
assert g.store['lock.txt'] == 'Shopping\neggs (6)'
g.tap_label('Add'); typed('apples')
assert g.store['lock.txt'] == 'Shopping\neggs (6)\napples'          # follows the list
g.tap(30, row(1))
assert g.store['lock.txt'] == 'Shopping\napples'                    # ticked items leave it

L2 = lua54.LuaRuntime(unpack_returned_tuples=True)
L2.execute(STUBS)
L2.globals().store['lock.txt'] = g.store['lock.txt']
L2.execute("ctx.clock.now = function(self) return { epoch_sec = 1761566400, hour = 12, minute = 0, second = 0 } end")
L2.execute(open(os.path.join(HERE, 'lockscreen.lua'), encoding='utf-8').read())
drawn = list(L2.eval("function() drawn = {}; on_draw(ctx, gg); local t = {} for _, d in ipairs(drawn) do t[#t + 1] = d.s end return t end")().values())
assert 'Shopping' in drawn and 'apples' in drawn and 'Monday, 27 October' in drawn, drawn

# lists: a new one, rename, delete; the lock list renamed follows
g.tap_label('Back')
g.tap_label('New list'); typed('Books')
assert str(A().screen()) == 'list' and str(A().lists()[A().cur()].name) == 'Books'
g.tap_label('Back')
hold(200, row(1)); g.tap_label('Rename'); typed('Market')
assert str(A().lock()) == 'Market' and g.store['lock.txt'].startswith('Market\n')
hold(200, row(3)); g.tap_label('Delete'); g.tap_label('Delete')
assert [str(l.name) for l in A().lists().values()] == ['Market', 'Work']
hold(200, row(1)); g.tap_label('Lock screen off')
assert 'lock.txt' not in g.store and list(g.L.eval('lock_calls').values()) == ['set', 'clear']

# kept between visits; draw commands
g.restart()
assert [str(l.name) for l in A().lists().values()] == ['Market', 'Work']
g.tap(200, row(1))
for k in range(30):
    g.tap_label('Add'); typed(f'item number {k} with a longer text that wraps onto a second line')
assert g.commands() < 400, g.commands()
g.no_err()

# repeating items: the clock is a day number we move
g.L.execute("fake_day = 20393; ctx.clock.now = function(self) return { epoch_sec = fake_day * 86400 + 43200, hour = 12, minute = 0, second = 0 } end")
def set_day(y, m, d): g.L.execute(f'fake_day = {int(A().days(y, m, d))}')
set_day(2026, 11, 1)
assert int(A().today()) == int(A().days(2026, 11, 1))
pe = lambda s: A().parse_every(s)
assert pe('3 days').n == 3 and pe('3 days').unit == 'day' and pe('every week').n == 1 and pe('6 Months').unit == 'month'
assert pe('2 w').unit == 'week' and pe('soon') is None and pe('0 days') is None

# the file: the tail is read and written back the same way
txt = '# Home\n[x] Water plants {every 4 days, done 2026-11-01}\n[ ] Filter {every 3 months}\n[ ] plain {not a repeat}\n'
L = A().parse(txt)
its = L[1]['items']
assert str(its[1].text) == 'Water plants' and its[1].every.n == 4 and int(its[1].last) == int(A().days(2026, 11, 1))
assert str(its[2].text) == 'Filter' and its[2].last is None and str(its[3].text) == 'plain {not a repeat}'
# months are calendar months, cut to the month's length
mon = g.L.eval('function(y, m, d, n) return { every = { n = n, unit = "month" }, last = __TEST.api.days(y, m, d) } end')
assert int(A().due(mon(2027, 1, 31, 1))) == int(A().days(2027, 2, 28))
assert int(A().due(mon(2028, 1, 31, 1))) == int(A().days(2028, 2, 29))
assert int(A().due(mon(2026, 11, 15, 3))) == int(A().days(2027, 2, 15))
assert int(A().due(mon(2026, 12, 5, 1))) == int(A().days(2027, 1, 5))

g.store['lists.txt'] = '# Home\n[ ] Water plants\n[ ] Dishes\n'
g.store['lock.txt'] = None
g.restart()
g.tap(200, row(1))
g.tap(200, row(1)); g.tap_label('Repeat'); g.tap_label('Other'); typed('4 days')
assert '[ ] Water plants {every 4 days}' in g.store['lists.txt']
assert 'every 4 days' in g.texts()
g.tap(200, row(2)); g.tap_label('Repeat'); g.tap_label('Other'); typed('soon')
assert 'Not understood: soon' in g.texts() and '{' not in g.store['lists.txt'].split('\n')[2]
g.tap(200, row(2)); g.tap_label('Repeat'); g.tap_label('Every 2 weeks')
assert '[ ] Dishes {every 2 weeks}' in g.store['lists.txt']
g.tap(30, row(1))                                         # ticked today
assert '[x] Water plants {every 4 days, done 2026-11-01}' in g.store['lists.txt']
assert 'every 4 days, next Thu 5 Nov' in g.texts(), g.texts()

# Clear done leaves it; the lock screen gets it with its day
g.tap_label('Clear done')
assert 'Nothing to clear.' in g.texts()
g.tap_label('List'); g.tap_label('Lock screen')
due_day = int(A().days(2026, 11, 5))
assert g.store['lock.txt'] == f'Home\n{due_day}\tWater plants\nDishes', g.store['lock.txt']

def lock_drawn(day):
    L2 = lua54.LuaRuntime(unpack_returned_tuples=True)
    L2.execute(STUBS)
    L2.globals().store['lock.txt'] = g.store['lock.txt']
    L2.execute(f"ctx.clock.now = function(self) return {{ epoch_sec = {day} * 86400 + 43200, hour = 12, minute = 0, second = 0 }} end")
    L2.execute(open(os.path.join(HERE, 'lockscreen.lua'), encoding='utf-8').read())
    return list(L2.eval("function() drawn = {}; on_draw(ctx, gg); local t = {} for _, d in ipairs(drawn) do t[#t + 1] = d.s end return t end")().values())
d = lock_drawn(due_day - 1)
assert 'Dishes' in d and 'Water plants' not in d, d
d = lock_drawn(due_day)
assert 'Dishes' in d and 'Water plants' in d and 'Thursday, 5 November' in d, d

# the day comes: open again (on the next tap or start), then late
set_day(2026, 11, 7)
g.restart()
g.tap(200, row(1))                                        # open Home
assert '[ ] Water plants {every 4 days, done 2026-11-01}' in g.store['lists.txt']
assert 'every 4 days, late 2 days' in g.texts(), g.texts()
assert g.store['lock.txt'] == 'Home\nWater plants\nDishes'
g.tap(30, row(1))
assert 'done 2026-11-07' in g.store['lists.txt'] and 'every 4 days, next Wed 11 Nov' in g.texts(), (g.store['lists.txt'], g.texts())
g.tap(30, row(1))                                         # un-ticked by hand: due from the last time
assert 'every 4 days, due Wed 11 Nov' in g.texts()
set_day(2026, 11, 11); g.tap_label('List'); g.tap_label('Close')
assert 'every 4 days, due today' in g.texts()
g.tap(200, row(1)); g.tap_label('Repeat'); g.tap_label('Off')
assert '[ ] Water plants\n' in g.store['lists.txt'] and 'every 4 days' not in g.texts()
g.tap(30, row(2)); g.tap_label('Clear done')
assert 'Nothing to clear.' in g.texts()
g.tap(30, row(1)); g.tap_label('Clear done'); g.tap_label('Clear')
assert [i[0] for i in items()] == ['Dishes']
g.tap_label('List'); g.tap_label('Lock screen off')
for k in range(12):
    g.tap_label('Add'); typed(f'chore number {k} with a long name that does not fit on one line')
    if k < 7:                                             # the rows on the first page
        g.tap(200, row(k + 2)); g.tap_label('Repeat'); g.tap_label('Every month')
        g.tap(30, row(k + 2))
assert g.texts().count('every month, next Fri 11 Dec') == 7
assert g.commands() < 400, g.commands()

# many lists: Prev and Next under 8 rows; a swipe turns the page and never opens a list
g.store['lists.txt'] = ''.join(f'# List {k}\n[ ] item\n\n' for k in range(1, 15))
g.restart()
swipe = g.L.eval("function(gst) on_input(ctx, {type='pointer', phase='down', x=200, y=200}); "
                 "on_input(ctx, {type='pointer', phase='up', gesture=gst, x=200, y=200}) end")
t = g.texts()
assert 'Prev' in t and 'Next' in t and '1-8 of 14' in t and 'List 8' in t and 'List 9' not in t, t
swipe('swipe_down')                                       # nothing before page 1: stays, opens nothing
assert str(A().screen()) == 'lists' and '1-8 of 14' in g.texts()
g.tap_label('Next')
assert '9-14 of 14' in g.texts() and 'List 14' in g.texts()
g.tap_label('Next')                                       # the last page: Next does nothing
assert '9-14 of 14' in g.texts()
swipe('swipe_down')
assert '1-8 of 14' in g.texts()
swipe('swipe_up')
assert '9-14 of 14' in g.texts() and str(A().screen()) == 'lists'
g.tap_label('Prev')
assert '1-8 of 14' in g.texts()
g.tap(200, row(8))                                        # the last row of the page still opens its list
assert str(A().screen()) == 'list' and str(A().lists()[A().cur()]['name']) == 'List 8'
g.no_err()
print('tasks tests passed')
