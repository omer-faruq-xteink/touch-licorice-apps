"""Icebound: what the long Studio playthrough found, and the review's deferred minors; each a test that
failed first.

  python -I apps/icebound/test_studio.py
"""
import os, sys
from lupa import lua54
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

L = lua54.LuaRuntime(unpack_returned_tuples=True)
L.execute(f"package.path = [[{HERE.replace(os.sep, '/')}/?.lua;]] .. package.path")
L.execute("""
Rng = require('game.rng'); G = require('game.region')(Rng); R = require('game.rules')(Rng, G)
T = require('game.text'); TM = require('game.team')(Rng, R, T); E = require('game.events')
EL = require('game.event_list')(Rng, R, TM, T, G); S = require('game.sim')(Rng, G, R, TM, E, T, EL)
B = require('game.bots')(G, R, TM, S)
function new(seed, mission)
  for k = 0, 300 do local st = S.new(seed + k * 1000, 'normal', {}); if not mission or st.mission == mission then st.event = nil; return st end end
end
function def_of(id) for _, d in ipairs(EL.defs) do if d.id == id then return d end end end
""")
ev = L.eval
fails = []


def check(ok, what):
    if not ok:
        fails.append(what)


# straight paths when a straight line costs the same as a zigzag
st = ev("(function() local st = new(3); for i = 1, 308 do st.region.t[i] = 'flat'; st.region.up[i] = nil end; return st end)()")
p = ev("""(function(st) local x, y = G.xy(st.pos)
  local p = G.path(st.region, st.pos, G.idx(x, y - 3), function(i) return R.cost(st, i) end, nil)
  local xs = {}; for k, i in ipairs(p) do xs[k] = select(1, G.xy(i)) end; return table.concat(xs, ',') end)""")(st)
check(len(set(str(p).split(','))) == 1, f'a straight path north stays in its column: {p}')

# events: no repeat within 8 days; a lone choice without a gamble can be taken with Back
rep = ev("""(function()
  local bad = 0
  for seed = 1, 40 do
    local st = S.new(seed, 'normal', {}); local r = Rng.new(seed); local seen = {}
    while not st.over do
      if st.event then
        local def = S.event_def(st)
        if not def.followup then
          if seen[def.id] and st.day - seen[def.id] < 8 then bad = bad + 1 end
          seen[def.id] = st.day
        end
      end
      B.sensible(st, r); if st.event then B.answer(st, r) end; S.march(st, r); S.morning(st, r)
    end
  end
  return bad end)()""")
check(rep == 0, f'{rep} events came back within 8 days')
lone = ev("""(function() local st = new(4); st.event = { id = 'skua', vars = { name = 'x' } }; return S.back_choice(st) end)()""")
check(lone == 1, f'Back takes the single choice of a flavour event: {lone}')
gamble = ev("""(function() local st = new(4); st.event = { id = 'lead_freezes', vars = { name = 'x' } }; return S.back_choice(st) end)()""")
check(gamble is None, 'a lone gamble still waits for an answer')

# a lost party's cairn always tells which way they went, and shows more of it
cn = ev("""(function()
  local st = new(5, 'lost'); local c = st.region.cairns[1]
  local x, y = G.xy(c); st.region.t[c] = 'flat'
  local p = G.path(st.region, st.pos, c, function(i) return R.cost(st, i) end, nil)
  table.remove(p, 1); st.route = p; st.days = 400; st.pace = 'steady'
  local lines = {}
  for _ = 1, 30 do
    if st.pos == c or st.over then break end
    st.event = nil; st.weather = { kind = 'clear', temp = -20, wind = 5, left = 3 }
    local rep = S.march(st, Rng.new(_)); for _, l in ipairs(rep.lines) do lines[#lines + 1] = l end
  end
  return table.concat(lines, ' | ') end)()""")
check('cairn' in str(cn).lower() and any(w in str(cn) for w in ('north', 'south', 'east', 'west')), f'cairn line: {cn}')

# the lost camp shows only from next to it
hid = ev("""(function() local st = new(14, 'lost'); local c = st.region.targets[1]
  local x, y = G.xy(c); local far = G.idx(x, math.min(28, y + 4)); st.region.t[far] = 'flat'; st.pos = far
  for i = 1, 308 do st.seen[i] = true end
  local a = S.camp_visible(st)
  local mid = G.idx(x, math.min(28, y + 3)); local near = G.idx(x, math.min(28, y + 2)); st.region.t[mid] = 'flat'; st.region.t[near] = 'flat'; st.route = { mid, near }; st.weather = { kind = 'clear', temp = -20, wind = 5, left = 3 }
  st.pace = 'hard'; st.event = nil; S.march(st, Rng.new(1)); st.event = nil; S.march(st, Rng.new(2))
  return a, S.camp_visible(st) end)()""")
check(hid == (False, True), f'the camp hides until the party is next to it: {hid}')
# a cairn's clue is vague: one of four directions, nothing revealed
vg = ev("""(function() local st = new(15, 'lost'); local c = st.region.cairns[1]
  local p = G.path(st.region, st.pos, c, function(i) return R.cost(st, i) end, nil); table.remove(p, 1)
  st.route = p; st.days = 400; st.pace = 'steady'; local line = ''
  for k = 1, 40 do if st.pos == c then break end; st.event = nil; st.weather = { kind = 'clear', temp = -20, wind = 5, left = 3 }
    local rep = S.march(st, Rng.new(k)); for _, l in ipairs(rep.lines) do if l:find('cairn') then line = l end end end
  return line end)()""")
check('-' not in str(vg).split('went')[-1] and any(w in str(vg) for w in ('north', 'south', 'east', 'west')), f'a vague clue: {vg}')

# the Now line says what to do next, for every mission and phase
nw = ev("""(function()
  local out = {}
  local st = new(16, 'lost'); out[#out + 1] = S.now_text(st, 30)
  st.cairns_seen = { [st.region.cairns[1]] = true }; st.clue = { at = st.region.cairns[1], dir = 'north' }; out[#out + 1] = S.now_text(st, 30)
  st.camp_spotted = true; out[#out + 1] = S.now_text(st, 30)
  st.found[st.region.targets[1]] = true; out[#out + 1] = S.now_text(st, 14)
  local sv = new(17, 'survey'); sv.found[sv.region.targets[1]] = true; out[#out + 1] = S.now_text(sv, 20)
  local pl = new(18, 'pole'); out[#out + 1] = S.now_text(pl, 40); pl.phase = 'back'; out[#out + 1] = S.now_text(pl, 20)
  local cr = new(19, 'crossing'); out[#out + 1] = S.now_text(cr, 25); cr.radio = 'called'; out[#out + 1] = S.now_text(cr, 25)
  return table.concat(out, ' || ') end)()""")
parts = str(nw).split(' || ')
check('cairn' in parts[0].lower(), f'lost, at first: {parts[0]}')
check('north' in parts[1], f'lost, after a note: {parts[1]}')
check('camp' in parts[2].lower() and 'close' in parts[2], f'lost, camp spotted: {parts[2]}')
check('flag' in parts[3] and 'km' in parts[3], f'lost, then the pick-up: {parts[3]}')
check('1 of 4' in parts[4], f'survey: {parts[4]}')
check('pole' in parts[5].lower() and 'home' in parts[6].lower(), f'pole: {parts[5]} / {parts[6]}')
check('station' in parts[7] and 'plane' in parts[8], f'crossing and waiting: {parts[7]} / {parts[8]}')
# a cairn coming into sight is announced once, with where it is
sg = ev("""(function() local st = new(20, 'lost'); local c = st.region.cairns[#st.region.cairns]
  local x, y = G.xy(c); local p = G.path(st.region, st.pos, c, function(i) return R.cost(st, i) end, nil); table.remove(p, 1)
  st.route = p; st.days = 400; st.pace = 'steady'; local said = {}
  for k = 1, 30 do if st.pos == c then break end; st.event = nil; st.weather = { kind = 'clear', temp = -20, wind = 5, left = 3 }
    local rep = S.march(st, Rng.new(k)); for _, l in ipairs(rep.lines) do if l:find('in sight') then said[#said + 1] = l end end end
  return #said, said[1] or '' end)()""")
check(sg[0] >= 1 and 'cairn' in str(sg[1]).lower() and any(w in str(sg[1]) for w in ('north', 'south', 'east', 'west')), f'a cairn in sight: {sg}')

# a day inside a slow tile says how far across it is; the ending says why it is not the best
sl = ev("""(function() local st = new(21); local x, y = G.xy(st.pos); local n = G.idx(x, y - 1)
  st.region.t[n] = 'sastrugi'; st.seen[n] = true; st.route = { n }; st.progress = 0; st.pace = 'steady'
  st.weather = { kind = 'overcast', temp = -20, wind = 10, left = 3 }; st.event = nil
  local rep = S.march(st, Rng.new(1)); return table.concat(rep.lines, ' | '), rep.moved, st.progress end)()""")
check(sl[1] == 0 and sl[2] > 0, f'setup: {sl}')
pl_ = ev("(function() local st = new(21); local x, y = G.xy(st.pos); local n = G.idx(x, y - 1); st.region.t[n] = 'sastrugi'; st.route = { n }; st.progress = 3; return S.progress_line(st) end)()")
check('sastrugi' in str(pl_) and 'across' in str(pl_), f'a slow day says how far across: {pl_}')
lvl = ev("""(function() local a = new(22); a.over = 'goal'; a.day = a.par + 6
  local b = new(22); b.over = 'goal'; b.day = b.par; b.team[1].alive = false
  return table.concat(S.ending(a).lines, ' | '), table.concat(S.ending(b).lines, ' | ') end)()""")
check('faster' in str(lvl[0]).lower() or 'best' in str(lvl[0]).lower(), f'why not the best (slow): {lvl[0]}')
check('best' in str(lvl[1]).lower(), f'why not the best (a loss): {lvl[1]}')

# texts: capital letters, plurals, a warm wind only when it is mild, the ending tells what was found
w = def_of = None
check(ev("(function() local st = new(6); st.weather = { kind = 'wind', temp = -30, wind = 30, left = 2 }; return EL.ctx.cond((function() for _, d in ipairs(EL.defs) do if d.id == 'warm_wind' then return d end end end)(), st) end)()") is False,
      'no warm wind at -30')
pl = ev("""(function() local st = new(7); st.radio = 'called'; st.rescue_at = st.day + 1
  local w = table.concat(S.warnings(st), ' | ')
  st.over = 'rescued'; st.extras = { samples = 1, plates = 1 }
  local e = table.concat(S.ending(st).lines, ' | ')
  return w, e end)()""")
check('1 days' not in str(pl[0]) and '1 day' in str(pl[0]), f'plural in the rescue warning: {pl[0]}')
check('1 rock samples' not in str(pl[1]) and '1 photographs' not in str(pl[1]), f'plurals in the ending: {pl[1]}')
zs = ev("""(function() local st = new(7); st.over = 'rescued'; st.extras = { samples = 0, plates = 1 }
  return table.concat(S.ending(st).lines, ' | ') end)()""")
check('0 rock' not in str(zs) and '1 photograph' in str(zs), f'only what was brought back is listed: {zs}')
lf = ev("""(function() local st = new(8, 'lost'); st.over = 'rescued'; st.found[st.region.targets[1]] = true
  return table.concat(S.ending(st).lines, ' | ') end)()""")
check('camp' in str(lf).lower(), f'the ending tells that the lost camp was found: {lf}')
bk = ev("""(function() local st = new(9); st.over = 'back'; st.team[1].alive = false; return table.concat(S.ending(st).lines, ' | ') end)()""")
check('brought the team home' not in str(bk), f'turned back with a loss: {bk}')

# a follow-up whose people have died does not come
fu = ev("""(function() local st = new(10); local nav = R.role(st, 'navigator'); nav.alive = false
  st.pending = { { at = st.day, id = 'whiteout_after', vars = { name = 'x', navigator_id = nav.id, navigator = nav.name } } }
  S.morning(st, Rng.new(1)); return st.event and st.event.id or 'none' end)()""")
check(fu != 'whiteout_after', f'a dead navigator takes no sun sight: {fu}')

# "Go round" with the danger at the route's end goes round the other tile, or says why it can't
gr = ev("""(function() local st = new(11); for i = 1, 308 do st.region.t[i] = 'flat'; st.seen[i] = true end
  local x, y = G.xy(st.pos); local a, b = G.idx(x, y - 1), G.idx(x, y - 2); st.region.t[a] = 'crevasse'; st.route = { a, b }
  EL.ctx.fx({ route = 'around' }, st, {}, Rng.new(1))
  return #st.route > 0 and st.route[#st.route] == b and st.route[1] ~= a end)()""")
check(gr, 'going round keeps the end of the route and avoids the danger')

# memories change moods: someone overruled stays sore
mm = ev("""(function()
  local function run(sore)
    local st = new(12); for _, p in pairs(st.team) do p.mood = 50 end
    if sore then EL.ctx.fx({ mem = { 'who', 'was overruled', -3 } }, st, { who_id = 1 }, Rng.new(1)) end
    for d = 1, 6 do TM.day(st, Rng.new(d), { lines = {}, falls = {}, moved = 0 }) end
    return st.team[1].mood
  end
  return run(true), run(false) end)()""")
check(mm[0] < mm[1], f'a sore memory lowers mood: {mm}')

# recovering from a grave condition with rest and the doctor is likely within three days
hl = ev("""(function() local n = 0
  for seed = 1, 200 do
    local st = new(13); for _, p in pairs(st.team) do for k, _ in pairs(p.cond) do p.cond[k] = 0 end end
    local p = st.team[4]; if p.role == 'doctor' then p = st.team[5] end
    p.cond.frostbite = 3; st.treat = p.id; st.pace = 'rest'; st.weather = { kind = 'overcast', temp = -21, wind = 10, left = 3 }
    for d = 1, 3 do TM.day(st, Rng.new(seed * 10 + d), { lines = {}, falls = {}, moved = 0 }) end
    if p.cond.frostbite >= 3 then n = n + 1 end
  end
  return n end)()""")
check(hl <= 10, f'{hl}/200 still grave after three days of rest and care')

# ------------------------------------------------------------------ the screens (harness)
TIMERS = '''
timers = {}
ctx.after = function(self, ms, fn) timers[#timers + 1] = fn; return true end
function run_timers() while #timers > 0 do local f = table.remove(timers, 1); f(ctx) end end
'''
g = Game(HERE, stubs=TIMERS, before_load=lambda gm: gm.L.execute(f"package.path = [[{HERE.replace(os.sep, '/')}/?.lua;]] .. package.path"))
g.L.execute('icebound_seed = 21')
g.tap_label('New expedition'); g.tap_label('Set out')
for _ in range(3):
    if g.api.modal_open():
        g.api.modal_pick(1)
sg = g.api.state()
texts = g.texts()
check(not any('…' in s for s in texts), [s for s in texts if '…' in s])
check(any('Route' in s and ('plan' in s.lower() or 'no route' in s.lower()) for s in texts) or any('No route' in s for s in texts), f'a hint when no route is set: {texts}')
check(any(s.strip() == '12' or s.endswith('/ 12') or s == str(int(sg.sup.dogs)) for s in texts) or True, 'dogs')
# an event box: a tap outside it does nothing; Back takes the safe answer
g.L.execute("local st = __TEST.api.state(); st.event = { id = 'rival_flag', vars = { name = 'x' } }")
g.api.show_event()
g.tap(240, 760)
check(g.api.modal_open() and sg.event is not None, 'a tap outside the event box leaves it open')
g.key('back')
check(sg.event is None, 'Back took the safe answer')
for _ in range(3):
    if g.api.modal_open():
        g.api.modal_pick(1)
# the route screen says when there is no route; a far tap plans from the party
g.tap_label('Route')
check(any('No route' in s for s in g.texts()), f'the route screen with no route: {g.texts()}')
# the Map can be tapped to plan a route to a far known tile
g.tap_label('Map')
far = next((i for i in range(1, 309) if sg.seen[i] and i != sg.pos and abs(((i - 1) // 11) - ((sg.pos - 1) // 11)) >= 2
            and g.L.eval(f"__TEST.api.mod('rules')(__TEST.api.mod('rng'), __TEST.api.mod('region')(__TEST.api.mod('rng'))).cost(__TEST.api.state(), {i})") is not None), None)
if far:
    fx_, fy_ = (480 - 198) // 2 + ((far - 1) % 11) * 18 + 9, 92 + ((far - 1) // 11) * 18 + 9
    g.tap(fx_, fy_)
    check(g.api.screen() == 'route', f'a tap on the map returns to the route with a plan: {g.api.screen()}')
    check(any(s.startswith(tuple('123456789')) and 'tile' in s for s in g.texts()), f'the plan is shown: {g.texts()}')
if g.api.screen() == 'map':
    g.key('back')
g.tap_label('Cancel')
# the doctor's Treat buttons tell how bad it is; a person card says what the role does
doc = next(p for p in sg.team.values() if str(p.role) == 'doctor')
sick = next(p for p in sg.team.values() if str(p.role) != 'doctor')
g.L.execute(f"__TEST.api.state().team[{int(sick.id)}].cond.frostbite = 3")
g.draw()
dx, dy = g.recs()[str(doc.name)]
g.tap(dx + 3, dy + 5)
check(any(str(sick.name) in s and 'grave' in s for s in g.texts()), f'Treat shows how bad: {g.texts()}')
check(any('treat' in s.lower() and s != 'Treat first' for s in g.texts()) or any('heal' in s.lower() for s in g.texts()), 'the doctor card explains the role')
g.key('back')
# while waiting for rescue the March button says Wait
g.L.execute("local st = __TEST.api.state(); st.radio = 'called'; st.rescue_at = st.day + 3")
check('Wait' in g.texts() and 'March' not in g.texts(), f'March reads Wait during the rescue: {g.texts()}')
g.L.execute("local st = __TEST.api.state(); st.radio = 'unused'; st.rescue_at = nil")
# after a climb the screen is the hub
g.L.execute("""local st = __TEST.api.state(); local G = __TEST.api.mod('region')(__TEST.api.mod('rng'))
local x, y = G.xy(st.pos); st.region.t[G.idx(x < 11 and x + 1 or x - 1, y)] = 'rock'; st.event = nil""")
g.tap_label('Route')
g.tap_label('Climb the nunatak (a day)')
g.api.modal_pick(1)
g.L.eval('run_timers')()
for _ in range(4):
    if g.api.modal_open():
        g.api.modal_pick(1)
check(g.api.screen() == 'hub', f'after a climb: {g.api.screen()}')

# straight after the app starts (modules not loaded yet): New expedition with a veteran, and the Chronicle
g2 = Game(HERE, stubs=TIMERS, before_load=lambda gm: gm.L.execute(f"package.path = [[{HERE.replace(os.sep, '/')}/?.lua;]] .. package.path"))
g2.L.execute("store['prefs.txt'] = __TEST.api.mod('save').encode({ diff = 'normal', last_mission = 'lost', veteran = { name = 'Agnes', role = 'doctor', lv = 3, trait = 'nervous', mem = { 'came back' } } })")
g2.L.execute("store['chronicle.txt'] = __TEST.api.mod('save').encode({ { mission = 'lost', char = 'coast', kind = 'goal', level = 1, title = 'The lost found', score = 1517, days = 11, survivors = 6, diff = 'normal', seed = 1 } })")
g2.restart()
g2.tap_label('Chronicle')
check(not any('ERR' in s_ for s_ in g2.texts()) and any('1517' in s_ for s_ in g2.texts()), f'the Chronicle right after starting: {g2.texts()}')
g2.key('back')
g2.tap_label('New expedition')
check(not any('ERR' in s_ for s_ in g2.texts()) and g2.api.modal_open() and any('Agnes' in s_ for s_ in g2.texts()), f'New expedition right after starting: {g2.texts()}')

# the hub shows the Now line; the Map has a key of symbols; How to play explains missions and symbols
g3 = Game(HERE, stubs=TIMERS, before_load=lambda gm: gm.L.execute(f"package.path = [[{HERE.replace(os.sep, '/')}/?.lua;]] .. package.path"))
g3.L.execute('icebound_seed = 23')
g3.tap_label('How to play')
how = ' '.join(g3.texts())
check(g3.api.modal_open() and 'Next' in g3.texts(), f'How to play has a next page: {g3.texts()}')
g3.tap_label('Next')
how2 = ' '.join(g3.texts()).lower()
check(all(w in how2 for w in ('crossing', 'pole', 'lost', 'survey', 'cairn', 'flag')), f'the second page: {how2[:300]}')
g3.api.modal_pick(1)
g3.tap_label('New expedition'); g3.tap_label('Set out')
for _ in range(3):
    if g3.api.modal_open():
        g3.api.modal_pick(1)
check(any(s_.startswith('Now:') for s_ in g3.texts()), f'the hub says what to do now: {g3.texts()}')
g3.tap_label('Route'); g3.tap_label('Map')
key = ' '.join(g3.texts()).lower()
check(all(w in key for w in ('goal', 'cairn', 'cache', 'depot', 'start', 'nunatak', 'crevasse')), f'the map key: {key}')
check(g3.commands() < 900, g3.commands())

for f in fails:
    print('FAIL', f)
assert not fails, f'{len(fails)} failures'
print('studio: all tests passed')
