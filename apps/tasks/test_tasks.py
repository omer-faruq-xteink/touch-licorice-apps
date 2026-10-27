"""Offline test of Tasks (gamekit harness): lists.txt read and written as plain text, lists and
items added, ticked, edited, moved and deleted, Clear done (after asking), the lock screen
(lock.txt and the firmware's question), lockscreen.lua drawing the open items, and the
draw-command count.

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
assert 'Nothing is ticked.' in g.texts()

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
print('tasks tests passed')
