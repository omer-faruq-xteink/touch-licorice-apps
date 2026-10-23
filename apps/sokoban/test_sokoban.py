"""Offline test of sokoban/index.lua under Lua 5.4 (lupa) with a ctx.data emulation written from the
firmware's reader code (read_text; open_text -> read_line / seek / tell / close over bytes), fed the
exact files xtpack.collect_data_files() packs: the packs and their .idx.tsv indexes.

  python -I sokoban/test_sokoban.py        (from the Xteink folder)
"""
import os, sys
from collections import deque
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(os.path.dirname(HERE)))
import xtpack  # noqa: E402
from lupa import lua54 as L  # noqa: E402

SRC = open(os.path.join(HERE, 'index.lua'), encoding='utf-8').read()
FILES = dict(xtpack.collect_data_files(HERE))
print('data files:', {k: len(v) for k, v in FILES.items()})
for fn in os.listdir(os.path.join(HERE, 'data')):
    if fn.endswith('.txt'):
        assert FILES[fn] == open(os.path.join(HERE, 'data', fn), 'rb').read(), fn + ' must be packed unchanged'

LUA_STUBS = r'''
cmds = 0; texts = {}
g = setmetatable({}, {__index = function(_, k) return function(self, ...)
  cmds = cmds + 1
  if k == 'text' then local x, y, s = ...; texts[#texts+1] = s end
  if k == 'measure_text' then local s = ...; return 13 * #s, 24 end
end end})
ctx = { state = {}, invalidate = function() end, display = { full_refresh = function() end },
        sys = { millis = function() return 1 end, epoch_sec = function() return 2 end }, data = {} }
__TEST = {}
'''


def make_rt(with_data=True, reads=None):
    rt = L.LuaRuntime(unpack_returned_tuples=True)
    rt.execute(LUA_STUBS)
    store = FILES if with_data else {}
    data = rt.eval('ctx.data')

    def read_text(self, name, opts=None):
        if reads is not None: reads.append(('read_text', name))
        return store[name].decode() if name in store else (None, 'not_found')

    def open_text(self, name, opts=None):
        if name not in store:
            return (None, 'not_found')
        if reads is not None: reads.append(('open_text', name))
        blob = store[name]; st = {'pos': 0, 'closed': False}

        def read_line(self):
            if st['closed'] or st['pos'] >= len(blob):
                return None
            i = blob.find(b'\n', st['pos']); end = len(blob) if i < 0 else i
            line = blob[st['pos']:end]; st['pos'] = end + 1 if i >= 0 else len(blob)
            if line.endswith(b'\r'): line = line[:-1]
            return line.decode()

        def seek(self, pos):
            if st['closed'] or pos < 0 or pos > len(blob):
                return False
            st['pos'] = pos; return True
        return rt.table_from({'read_line': read_line, 'seek': seek, 'tell': lambda self: st['pos'],
                              'close': lambda self: st.__setitem__('closed', True)})
    data['read_text'] = read_text
    data['open_text'] = open_text
    data['exists'] = lambda self, name: name in store
    rt.execute(SRC)
    return rt, rt.eval('__TEST.api')


def grid_of(lv):
    return ([''.join(lv['grid'][r][c] for c in range(1, lv['cols'] + 1)) for r in range(1, lv['rows'] + 1)],
            (lv['pr'], lv['pc'], lv['moves'], lv['pushes']))


def bfs_solve(rows):
    H, W = len(rows), max(len(r) for r in rows); rows = [r.ljust(W) for r in rows]
    walls = {(r, c) for r in range(H) for c in range(W) if rows[r][c] == '#'}
    goals = frozenset((r, c) for r in range(H) for c in range(W) if rows[r][c] in '.*+')
    boxes = frozenset((r, c) for r in range(H) for c in range(W) if rows[r][c] in '$*')
    player = next((r, c) for r in range(H) for c in range(W) if rows[r][c] in '@+')
    D = {'l': (0, -1), 'r': (0, 1), 'u': (-1, 0), 'd': (1, 0)}
    start = (player, boxes); seen = {start}; q = deque([(start, '')])
    while q:
        (p, bx), path = q.popleft()
        if bx == goals: return path
        for k, (dr, dc) in D.items():
            n = (p[0] + dr, p[1] + dc)
            if n in walls: continue
            nb = bx
            if n in bx:
                b2 = (n[0] + dr, n[1] + dc)
                if b2 in walls or b2 in bx: continue
                nb = (bx - {n}) | {b2}
            st = (n, nb)
            if st not in seen: seen.add(st); q.append((st, path + k))
    raise AssertionError('unsolvable')


reads = []
rt, api = make_rt(reads=reads)
T = lambda **kw: rt.table_from(kw)  # noqa: E731
on_input = rt.eval('on_input')
def tap(x, y): on_input(None, T(type='touch', gesture='tap', x=x, y=y))
def swipe(k): on_input(None, T(type='touch', gesture={'l': 'swipe_left', 'r': 'swipe_right', 'u': 'swipe_up', 'd': 'swipe_down'}[k], x=100, y=300))
def btn(k): tap(15 + k * 91 + 43, 622 + 28)          # play: 0 undo, 1 reset, 2 prev, 3 next, 4 set
def pbtn(k): tap(15 + k * 152 + 70, 622 + 28)        # sets: 0 page up, 1 page down, 2 back
def texts(): return list(rt.eval('texts').values())
def lua_rows(def_): return [def_['rows'][i] for i in range(1, len(def_['rows']) + 1)]

# whole-pack parse of every pack equals the index-based reads
rt.eval('on_load')(rt.eval('ctx'))
assert api.data_ok() is True
sets = api.sets(); names = [sets[i]['name'] for i in range(1, len(sets) + 1)]
print('sets:', names)
assert names[-1] == 'builtin' and 'microban.txt' in names and 'loma.txt' in names and not any(n.endswith('.idx.tsv') for n in names)
for i in range(1, len(sets)):
    s = sets[i]
    whole = api.parse_pack(FILES[s['name']].decode())
    assert s['count'] == len(whole) and s['count'] > 0, (s['name'], s['count'], len(whole))
    for n in [1, 2, len(whole) // 2, len(whole)]:
        a, b = api.get_level(s, n), whole[n]
        assert lua_rows(a) == lua_rows(b) and a['title'] == b['title'], (s['name'], n)
    print(f"  {s['name']}: {s['count']} levels, index reads match the whole-pack parse")
mb = api.set_by_name('microban.txt')[0]
t1, t155 = str(api.get_level(mb, 1)['title']), str(api.get_level(mb, 155)['title'])
assert mb['count'] == 155 and t1 in ('Level 1', 'Microban 1') and t155.startswith(('Level 155', '155', 'Microban 155')), (t1, t155)
assert not any(k == 'read_text' and n == 'microban.txt' for k, n in reads), 'an indexed pack must never be read whole'
print('index-based loading OK (packs never read whole)')

# step / unstep
l1 = api.get_level(mb, 1); rows1 = lua_rows(l1)
assert rows1 == ['####', '# .#', '#  ###', '#*@  #', '#  $ #', '#  ###', '####']
lv = api.build_level(l1); before = grid_of(lv)
assert api.step(lv, 'u') == 'u' and api.step(lv, 'u') == 'u' and api.step(lv, 'u') is None   # floor, goal, wall
api.unstep(lv, 'u'); api.unstep(lv, 'u'); assert grid_of(lv) == before
assert api.step(lv, 'd') == 'd' and api.step(lv, 'r') == 'R' and lv['pushes'] == 1 and lv['grid'][5][5] == '$'
api.unstep(lv, 'R'); api.unstep(lv, 'd'); assert grid_of(lv) == before
print('step / unstep OK')

# fresh state starts at the first set, level 1; solve it by swipes
S = api.state(); assert S['set'] == names[0] and S['idx'] == 1 and S['hist'] == ''
first = api.set_by_name(names[0])[0]; rows = lua_rows(api.get_level(first, 1))
sol = bfs_solve(rows); print(f'{names[0]} level 1 BFS solution: {sol}')
for k in sol: swipe(k)
assert api.level()['solved'] is True and api.state()['best'][names[0] + '/1'] == len(sol)
rt.execute('texts = {}'); rt.eval('on_draw')(); assert any('Solved' in t for t in texts())
swipe('l'); assert len(api.state()['hist']) == len(sol)
on_input(None, T(type='key', key='down', state='down')); assert api.state()['idx'] == 2 and api.state()['pos'][names[0]] == 2
print('solve, best, next-by-side-button, per-set position OK')

# undo / reset / prev / next
swipe('u'); swipe('d'); h = api.state()['hist']; btn(0); assert api.state()['hist'] == h[:-1]
btn(1); assert api.confirm() is True; tap(335, 448); assert api.confirm() is False
btn(1); tap(145, 448); assert api.state()['hist'] == '' and api.level()['moves'] == 0
btn(3); assert api.state()['idx'] == 3; btn(2); assert api.state()['idx'] == 2
btn(2); btn(2); assert api.state()['idx'] == first['count']
print('undo / reset dialog / prev / next OK')

# the set picker: open, page, pick, back; position per set remembered
btn(4); assert api.mode() == 'sets' and api.page() == 1
rt.execute('texts = {}'); rt.eval('on_draw')(); assert any('Level sets' in t for t in texts())
pbtn(1); assert api.page() == 1 or len(names) > 12              # one page unless many sets
other = 'microban.txt' if names[0] == 'loma.txt' else 'loma.txt'
i_other, i_first = names.index(other), names.index(names[0])
tap(240, 92 + i_other * 40 + 20); S = api.state()
assert api.mode() == 'play' and S['set'] == other and S['idx'] == 1 and S['hist'] == ''
swipe('u'); swipe('d'); btn(3); assert api.state()['idx'] == 2
btn(4); tap(240, 92 + i_first * 40 + 20); assert api.state()['set'] == names[0] and api.state()['idx'] == first['count']
btn(4); tap(240, 92 + i_other * 40 + 20); assert api.state()['set'] == other and api.state()['idx'] == 2
btn(4); pbtn(2); assert api.mode() == 'play' and api.state()['set'] == other
btn(4); tap(240, 92 + i_other * 40 + 20); assert api.mode() == 'play' and api.state()['idx'] == 2   # same set: just closes
btn(4); tap(240, 92 + (len(names) - 1) * 40 + 20); assert api.state()['set'] == 'builtin' and api.set_by_name('builtin')[0]['count'] == 12
print('set picker: pick, remembered positions, back, built-in OK')

# tap beside the player
api.adopt_state(rt.table_from({'set': 'microban.txt', 'idx': 1, 'hist': '', 'best': {}, 'pos': {}}))
Lv = api.level(); cs = min(50, 450 // Lv['cols'], (606 - 82) // Lv['rows'])
x0 = (480 - cs * Lv['cols']) // 2; y0 = 82 + ((606 - 82) - cs * Lv['rows']) // 2
px, py = x0 + (Lv['pc'] - 1) * cs + cs // 2, y0 + (Lv['pr'] - 1) * cs + cs // 2
tap(px, py); assert api.level()['moves'] == 0
tap(px + cs, py); assert api.state()['hist'] == 'r'
tap(px, py); assert api.state()['hist'] == 'rl'                 # left of the player's NEW cell (below it a box sits against a wall)
print('tap-beside-player OK')

# resume: history replays, impossible tail dropped, garbage state
api.adopt_state(rt.table_from({'set': 'microban.txt', 'idx': 1, 'hist': 'dR', 'best': {}, 'pos': {}}))
assert api.level()['moves'] == 2 and api.level()['pushes'] == 1 and api.state()['hist'] == 'dR'
api.adopt_state(rt.table_from({'set': 'microban.txt', 'idx': 1, 'hist': 'uuuu'})); assert api.state()['hist'] == 'uu'   # floor, goal, then the wall stops the replay
api.adopt_state(rt.table_from({'set': 'nope', 'idx': 'x'})); assert api.state()['set'] == names[0] and api.state()['idx'] == 1
print('state resume + garbage OK')

# draw budget over every level of every pack
worst = (0, '')
for i in range(1, len(sets)):
    s = sets[i]
    for n in range(1, s['count'] + 1):
        api.adopt_state(rt.table_from({'set': s['name'], 'idx': n, 'hist': '', 'best': {}, 'pos': {}}))
        rt.execute('cmds = 0'); rt.eval('on_draw')(); c = rt.eval('cmds')
        if c > worst[0]: worst = (c, f"{s['name']} #{n}")
print('draw commands, worst level:', worst); assert worst[0] < 1024

# fallback without data
rt2, api2 = make_rt(with_data=False)
rt2.eval('on_load')(rt2.eval('ctx'))
assert api2.data_ok() is False and api2.state()['set'] == 'builtin' and api2.set_by_name('builtin')[0]['count'] == 12
print('fallback without data section OK')
print('ALL SOKOBAN TESTS PASSED')
