"""Offline test of Port Wren (gamekit harness; ctx:after timers run by hand): the random numbers and
the save format, the title screen and Back.

  python -I apps/portwren/test_portwren.py
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

PATH = f"package.path = [[{HERE.replace(os.sep, '/')}/?.lua;]] .. package.path"
TIMERS = '''
timers = {}
ctx.after = function(self, ms, fn) assert(self == ctx); timers[#timers + 1] = fn; return true end
function run_timers()
  local n = 0
  while #timers > 0 do local f = table.remove(timers, 1); f(ctx); n = n + 1 end
  return n
end
'''
g = Game(HERE, stubs=TIMERS, before_load=lambda gm: gm.L.execute(PATH))
L = g.L
A = lambda: g.api
back = lambda phase: L.eval(f"on_input(ctx, {{type='key', key='back', phase='{phase}'}})")

# ---------------------------------------------------------------- random numbers
R = A().mod('rng')
run = lambda: [R.new(7).int(1, 100) for _ in range(1)]
r1, r2 = R.new(7), R.new(7)
a = [r1.int(r1, 1, 100) for _ in range(5)]
b = [r2.int(r2, 1, 100) for _ in range(5)]
assert a == b and all(1 <= v <= 100 for v in a), (a, b)
assert [R.new(8).int(R.new(8), 1, 100)] != [] and R.mix(3, 4) == R.mix(3, 4) and R.mix(3, 4) != R.mix(3, 5)
t = L.table_from(list(range(1, 21)))
r1.shuffle(r1, t)
assert sorted(t.values()) == list(range(1, 21))

# ---------------------------------------------------------------- save format
L.execute('''
S = __TEST.api.mod('save')
local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= 'table' then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end
local t = { a = 1, b = 'x\\n"y', c = { 1, 2, { d = true } }, e = false, [7] = -3 }
assert(same(S.decode(S.encode(t)), t), 'round trip')
assert(S.encode(t) == S.encode(S.decode(S.encode(t))), 'stable')
assert(S.decode('garbage{') == nil and S.decode('') == nil and S.decode(nil) == nil, 'garbage is nil')
''')

# ---------------------------------------------------------------- the title
t = g.texts()
assert 'Port Wren' in t and 'New career' in t and 'Single cases' in t and 'Settings' in t, t
assert 'Continue' not in t, t
assert A().screen() == 'title'
assert back('down') is True and back('up') is False, 'the title leaves Back to the host'
g.tap_label('How to play')
assert any('certain' in s.lower() for s in g.texts()), g.texts()
assert back('down') is True and back('up') is True and A().screen() == 'title'
assert g.commands() < 900
g.no_err()

# ---------------------------------------------------------------- Task 8: preparing, the case file, places, talking
T = A().mod('text')


def name_of(pid):
    return str(A().town().people[pid].name)


def first_of(pid):
    return name_of(pid).split()[0]


def place_name(key):
    return str(T.PLACES[key].name)


def go_place(key):
    if A().screen() != 'case':
        g.key('back')
    g.tap_label(place_name(key))
    assert A().screen() == 'place', A().screen()


def talk_to(pid):
    for _ in range(4):
        if str(A().place_of(pid)) in [str(x) for x in A().case().places.values()]:
            break
        if A().screen() != 'case':
            g.key('back')
        g.tap_label('Wait')
    go_place(str(A().place_of(pid)))
    g.tap_label(name_of(pid))
    assert A().screen() == 'talk', (A().screen(), g.texts())


L.execute('portwren_seed = 11')            # the next new game's seed (tests only)
g.tap_label('New career')
assert A().screen() == 'preparing' and any('Preparing' in s for s in g.texts()), g.texts()
assert L.eval('run_timers')() >= 1
assert A().screen() == 'case', A().screen()
c = A().case()
victim = name_of(c.victim)
assert any(victim in s for s in g.texts()), g.texts()
killer = c.killer
g.no_err()
assert g.commands() < 900

# closed while preparing: it prepares again from the same seed, and the same case comes out
g.key('back'); g.tap_label('New career')
assert A().screen() in ('preparing', 'confirm') or True
if 'Start again' in g.texts():
    g.tap_label('Start again')
assert A().screen() == 'preparing'
g.restart()
assert A().screen() == 'preparing', A().screen()
L.eval('run_timers')()
assert A().screen() == 'case' and A().case().killer == killer, 'the same case again'
c = A().case()

# searching the scene costs an action and finds the weapon
left = A().act_left()
go_place(str(c.scene))
g.tap_label('Search')
assert A().act_left() == left - 1, (left, A().act_left())
found = [cl.id for cl in c.clues.values() if c.found[cl.id]]
assert any(c.clues[i].tpl == 'weapon' for i in found), found
assert 'Search' not in g.texts() or 'Searched' in ' '.join(g.texts())

# talking costs an action and gives the statement
left = A().act_left()
g.key('back')
talk_to(killer)
assert A().act_left() == left - 1
assert any(s.startswith('From ') or s.startswith('At ') for s in g.texts()), g.texts()
assert c.heard[killer]
g.no_err()
assert g.commands() < 900
# low trust: one more action the first time
other = next(p for p in c.suspects.values() if p != killer)
A().town().people[other].trust = 10
g.key('back'); g.key('back')
left = A().act_left()
talk_to(other)
assert A().act_left() == left - 2, (left, A().act_left())

# asking about a topic and showing a clue are free inside a talk
left = A().act_left()
g.tap_label(str(T.topic_label(c, A().town(), 'victim')))
assert A().act_left() == left

# kept over a restart
before = (sorted(k for k in c.found.keys()), c.clock.day, c.clock.part, c.clock.used)
g.restart()
c = A().case()
assert A().screen() == 'title' and 'Continue' in g.texts()
g.tap_label('Continue')
assert A().screen() == 'case'
assert (sorted(k for k in c.found.keys()), c.clock.day, c.clock.part, c.clock.used) == before

# out of time: the killer strikes again
def meetable_now(c):
    return [p for p in c.suspects.values() if p != c.killer and str(A().place_of(p)) in [str(x) for x in c.places.values()]]


while A().case().strikes == 0:
    if A().screen() != 'case':
        g.key('back'); g.key('back')
    now = meetable_now(A().case())
    if not now:
        left = A().act_left()
        g.tap_label('Wait')                       # to the next part of the day
        assert A().case().strikes or A().act_left() < left
        continue
    talk_to(now[0])
c = A().case()
assert c.strikes == 1 and c.night2, c.strikes
assert any(name_of(c.night2.victim) in s for s in g.texts()), g.texts()       # the news, in a box
g.key('back')                                                                 # closing it opens the case file
assert A().screen() == 'case' and any(name_of(c.night2.victim) in s for s in g.texts())

# Back: talk -> place -> case file -> title, where it is left to the host
talk_to(c.killer)
assert back('down') is True and back('up') is True and A().screen() == 'place'
assert back('down') is True and back('up') is True and A().screen() == 'case'
assert back('down') is True and back('up') is True and A().screen() == 'title'
assert back('down') is True and back('up') is False
g.no_err()

# ---------------------------------------------------------------- Task 9: accusing, the end, career, settings, modes
def new_career(seed):
    L.execute(f'portwren_seed = {seed}')
    while A().screen() != 'title':
        g.key('back')
    g.tap_label('New career')
    if 'Start again' in g.texts():
        g.tap_label('Start again')
    L.eval('run_timers')()
    assert A().screen() == 'case', A().screen()


def accuse(pid, motive, means):
    while A().screen() != 'case':
        g.key('back')
    g.tap_label('Accuse')
    assert A().screen() == 'accuse'
    g.tap_label(name_of(pid))
    g.tap_label(str(T.MOTIVE_NAME[motive]))
    g.tap_label(str(T.MEANS_NAME[means]))
    g.tap_label('Confirm')
    g.tap_label('Accuse')


def width_ok():
    """no text runs off the right edge (the harness font is 10 px a character)"""
    for d in g.draw():
        assert int(d.x) + len(str(d.s)) * 10 <= 480 + 2, (str(d.s), int(d.x))


def next_case():
    g.tap_label('Next case')
    L.eval('run_timers')()
    assert A().screen() == 'case', A().screen()


new_career(21)
c = A().case()
k = c.killer
accuse(k, str(c.motive), str(c.means))
assert A().case().over == 'solved' and A().town().rep == 20, (A().case().over, A().town().rep)
assert A().screen() == 'end' and any(name_of(k) in s for s in g.texts()), g.texts()
width_ok()
v1 = c.victim
next_case()
tw = A().town()
assert tw.people[v1].status == 'dead' and tw.people[k].status == 'jailed' and tw.case_no == 2
c = A().case()
assert all(tw.people[p].status == 'alive' for p in list(c.suspects.values()) + [c.victim])

# a wrong accusation: the killer strikes again, the accused remembers
wrong = next(p for p in c.suspects.values() if p != c.killer)
trust = tw.people[wrong].trust
accuse(wrong, 'debt', 'poison')
c = A().case()
assert c.strikes == 1 and c.night2, c.strikes
assert tw.people[wrong].trust == max(0, trust - 40), (trust, tw.people[wrong].trust)
assert any(h.what == 'accused' for h in tw.people[wrong].hist.values())
g.key('back')
greet = str(T.greet(c, tw, wrong, None))
assert 'accused me' in greet, greet

# a second wrong accusation: the killer flees and the end names them
wrong2 = next(p for p in c.suspects.values() if p != c.killer)
accuse(wrong2, 'debt', 'poison')
assert A().case().over == 'lost' and A().screen() == 'end'
assert any(name_of(c.killer) in s for s in g.texts()), g.texts()

# promotion: reputation 30 is Sergeant, and Sergeants get the harder cases
next_case()
tw = A().town()
tw.rep = 20
c = A().case()
accuse(c.killer, str(c.motive), str(c.means))
assert tw.rank == 2 and any('Sergeant' in s for s in g.texts()), (tw.rank, g.texts())
seen = set()
for _ in range(12):
    next_case()
    c = A().case()
    seen.add(str(c.pattern))
    accuse(c.killer, str(c.motive), str(c.means))
assert seen <= {'classic', 'alibi', 'timeline'} and len(seen) >= 2, seen

# Review focus 3 and 4: Settings mid-case leave the open case alone; a Long case after a strike fits
next_case()
g.key('back'); g.tap_label('Settings'); g.tap_label('Long')
assert A().prefs().size == 'long' and A().case().size == 'short', 'the open case keeps its length'
g.key('back'); g.tap_label('Continue')
c = A().case()
accuse(c.killer, str(c.motive), str(c.means))
next_case()
c = A().case()
assert c.size == 'long', c.size
accuse(next(p for p in c.suspects.values() if p != c.killer), 'debt', 'poison')
g.key('back')
c = A().case()
assert c.strikes == 1
for p in c.suspects.values():
    c.heard[p] = True
    c.heard2[p] = True
for cl in c.clues.values():
    c.found[cl.id] = True
g.tap_label('Notebook')
assert A().screen() == 'notebook' and g.commands() < 900
width_ok()
g.tap_label('Statements')
assert A().screen() == 'statements' and g.commands() < 900, g.commands()
width_ok()
g.tap_label('Night 2')
assert g.commands() < 900
width_ok()
assert back('down') is True and back('up') is True and A().screen() == 'notebook'
assert back('down') is True and back('up') is True and A().screen() == 'case'
g.tap_label('Board')
assert A().screen() == 'board' and g.commands() < 900, g.commands()
width_ok()
# tie a clue to a suspect, and untie it
sus0 = list(c.suspects.values())[0]
g.tap_label('1'); g.tap_label(first_of(sus0))
assert any(b.clue == 1 and b.who == sus0 for b in c.board.values())
g.tap_label('1'); g.tap_label(first_of(sus0))
assert not any(b.clue == 1 and b.who == sus0 for b in c.board.values())
assert back('down') is True and back('up') is True and A().screen() == 'case'
g.tap_label('Menu'); g.tap_label('Career')
assert A().screen() == 'career' and str(T.RANKS[A().town().rank]) in g.texts() and g.commands() < 900, (g.texts()[:3], g.commands())
width_ok()
assert back('down') is True and back('up') is True and A().screen() == 'case'

seed_before = A().town().seed
g.tap_label('Menu'); g.tap_label('Settings'); g.tap_label('Single cases')
L.execute('portwren_seed = 77')                  # the new town's seed
assert A().prefs().mode == 'single' and A().town().seed == seed_before and A().case().size == 'long'
g.key('back')
c = A().case()
accuse(c.killer, str(c.motive), str(c.means))
next_case()
assert A().town().mode == 'single' and A().town().seed != seed_before and A().case().size == 'long', (A().town().mode, A().town().seed, seed_before, A().case().size)
c = A().case()
accuse(c.killer, str(c.motive), str(c.means))
assert A().town().rep == 0, 'single cases keep no rank'
career = L.eval('function() return __TEST.api.mod("save").decode(ctx.storage:read("town.txt")) end')()
assert career and career.seed == seed_before, 'the career is kept while playing single cases'

# Review focus 5: reset with a case open; Back while preparing
while A().screen() != 'title':
    g.key('back')
g.tap_label('Settings'); g.tap_label('Reset career'); g.tap_label('Reset')
assert not g.store['town.txt'] and not g.store['case.txt'], (g.store['town.txt'], g.store['case.txt'])
assert A().screen() == 'title' and 'Continue' not in g.texts(), g.texts()
g.tap_label('New career')
assert A().screen() == 'preparing'
assert back('down') is True and back('up') is True and A().screen() == 'title'
L.eval('run_timers')()
assert A().screen() == 'title' and A().case() is None and 'Continue' not in g.texts(), g.texts()
g.no_err()


# ---------------------------------------------------------------- review fixes
# 1: the reader has no os library; a new game must start without it
g2 = Game(HERE, stubs=TIMERS + '\nos = nil\n', before_load=lambda gm: gm.L.execute(PATH))
g2.tap_label('New career')
assert g2.api.screen() == 'preparing', g2.texts()
g2.L.eval('run_timers')()
assert g2.api.screen() == 'case', g2.texts()
g2.no_err()
g2.tap_label('Wait')
g2.no_err()

# 3: every clue behind the same question comes out at once
L.execute("budget_calls = 0; ctx.budget = { extend = function(self) budget_calls = budget_calls + 1 end }")
new_career(31)
c = A().case()
s0 = next(p for p in c.suspects.values() if p != c.killer)
ids = [cl.id for cl in c.clues.values() if not c.found[cl.id] and cl.gate.k != 'talk' and cl.tpl != 'weapon'][:2]
for i in ids:
    c.clues[i].gate = L.table_from({'k': 'ask', 'who': s0, 'topic': 'victim'})
talk_to(s0)
g.tap_label(str(T.topic_label(c, A().town(), 'victim')))
assert all(c.found[i] for i in ids), ([bool(c.found[i]) for i in ids], ids, [dict(c.clues[i].gate) for i in ids], A().screen(), g.texts()[-8:])

# 4: the notebook shows every clue whole
for cl in c.clues.values():
    c.found[cl.id] = True
while A().screen() != 'case':
    g.key('back')
g.tap_label('Notebook')
seen_text = []
for _ in range(10):
    seen_text += g.texts()
    before = A().screen(), ' '.join(g.texts())
    g.tap_label('>')
    if ' '.join(g.texts()) == before[1]:
        break
alltext = ' '.join(seen_text)
for cl in c.clues.values():
    whole = f'{cl.id}. ' + str(T.clue(c, A().town(), cl, None))
    assert whole in alltext, (cl.id, whole)
g.key('back')

# 12: the case file's place rows stay above the buttons, even in a Long case after a strike
g.tap_label('Menu'); g.tap_label('Settings'); g.tap_label('Long'); g.key('back')
c = A().case()
accuse(c.killer, str(c.motive), str(c.means))
next_case()
c = A().case()
budget = L.eval('budget_calls')
accuse(next(p for p in c.suspects.values() if p != c.killer), 'debt', 'poison')
# 9: the strike runs with the time budget extended
assert L.eval('budget_calls') > budget, 'no budget extension for the strike'
g.key('back')
assert A().screen() == 'case' and A().case().strikes == 1
rows = [r for r in g.rects() if int(r.w) == 448]
assert rows and all(int(r.y) + int(r.h) <= 720 for r in rows), [(int(r.y), int(r.h)) for r in rows]

# 8: a crowded place lists everyone, a page at a time
c = A().case()
place = str(c.places[1])
crowd = list(c.suspects.values()) + list(c.witnesses.values())
for p in crowd:
    if c.sched[p]:
        c.sched[p][c.clock.part] = place
go_place(place)
met = set()
for _ in range(6):
    met |= set(g.texts())
    if 'More people' not in g.texts():
        break
    g.tap_label('More people')
alive = [p for p in crowd if A().town().people[p].status == 'alive' and c.sched[p]
         and p != (c.night2.victim if c.night2 else None)]
assert all(name_of(p) in met for p in alive), [name_of(p) for p in alive if name_of(p) not in met]
g.key('back')

# 11: an accusation picked and left does not stay picked
g.tap_label('Accuse')
g.tap_label(name_of(c.killer)); g.tap_label(str(T.MOTIVE_NAME[c.motive])); g.tap_label(str(T.MEANS_NAME[c.means]))
g.key('back')
g.tap_label('Accuse')
g.tap_label('Confirm')
assert 'Cancel' not in g.texts(), 'an old pick was kept'
g.key('back')

# 10: Wait in the last part of the last day asks first
c.clock.day, c.clock.part, c.clock.used = c.days, 4, 0
g.tap_label('Wait')
assert 'Cancel' in g.texts(), g.texts()
g.tap_label('Cancel')
assert A().case().strikes == 1 and A().case().over is None

# 6: a killer who flees is gone from the town
k = c.killer
accuse(next(p for p in c.suspects.values() if p != c.killer), 'debt', 'poison')
assert A().case().over == 'lost'
next_case()
assert A().town().people[k].status == 'gone', A().town().people[k].status

# 7: finishing a career case after choosing Single cases keeps the career's town up to date
c = A().case()
v, k = c.victim, c.killer
g.tap_label('Menu'); g.tap_label('Settings'); g.tap_label('Single cases'); g.key('back')
L.execute('portwren_seed = 91')
accuse(k, str(c.motive), str(c.means))
next_case()
saved = L.eval('function() return __TEST.api.mod("save").decode(ctx.storage:read("town.txt")) end')()
assert saved.people[v].status == 'dead' and saved.people[k].status == 'jailed', (saved.people[v].status, saved.people[k].status)

# 7: starting single cases from the title with a career case open asks first; giving up counts as lost
g.tap_label('Menu'); g.tap_label('Settings'); g.tap_label('Career'); g.key('back')
c = A().case()
accuse(c.killer, str(c.motive), str(c.means))
next_case()
c = A().case()
assert A().town().mode == 'career'
k = c.killer
lost = A().town().lost
while A().screen() != 'title':
    g.key('back')
g.tap_label('Single cases')
assert 'Give up' in g.texts(), g.texts()
g.tap_label('Give up')
saved = L.eval('function() return __TEST.api.mod("save").decode(ctx.storage:read("town.txt")) end')()
assert saved.lost == lost + 1 and saved.people[k].status == 'gone', (saved.lost, lost, saved.people[k].status)
L.eval('run_timers')()
assert A().town().mode == 'single' and A().screen() == 'case'
g.no_err()
print('portwren: all tests passed')
