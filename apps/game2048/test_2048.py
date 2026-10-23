"""Offline test of game2048/index.lua under Lua 5.4 (lupa).  python -I apps/game2048/test_2048.py"""
import lupa, sys
from lupa import lua54 as L
rt = L.LuaRuntime(unpack_returned_tuples=True)
import os
src = open(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), 'index.lua'), encoding='utf-8').read()
rt.execute(r'''
cmds = 0; texts = {}; refreshes = {full=0, inval=0}
g = setmetatable({}, {__index = function(_, k)
  return function(self, ...)
    cmds = cmds + 1
    if k == 'text' then local x, y, s = ...; texts[#texts+1] = s end
    if k == 'size' then return 480, 800 end
    if k == 'measure_text' then local s = ...; return 13 * #s, 24 end
  end end})
ctx = { state = {}, sys = { millis = function() return 12345 end, epoch_sec = function() return 1792773521 end },
        invalidate = function() refreshes.inval = refreshes.inval + 1 end,
        display = { full_refresh = function() refreshes.full = refreshes.full + 1 end } }
__TEST = {}
''')
rt.execute(src)
api = rt.eval('__TEST.api')
def lt(xs): return rt.table(*xs)
def pyl(t): return [t[i] for i in range(1, len(t)+1)]
# --- slide_line cases
cases = [([2,2,0,0],[4,0,0,0],4,True), ([2,2,2,2],[4,4,0,0],8,True), ([2,0,2,4],[4,4,0,0],4,True),
         ([4,2,2,0],[4,4,0,0],4,True), ([2,4,8,16],[2,4,8,16],0,False), ([0,0,0,2],[2,0,0,0],0,True),
         ([2,2,4,4],[4,8,0,0],12,True), ([0,0,0,0],[0,0,0,0],0,False), ([4,4,4,0],[8,4,0,0],8,True)]
for line, exp, gexp, cexp in cases:
    res, gained, changed = api.slide_line(lt(line))
    assert pyl(res) == exp and gained == gexp and changed == cexp, (line, pyl(res), gained, changed)
print('slide_line: 9 cases OK')
# --- move on a known board: left/right/up/down
b = lt([2,2,0,0, 0,4,4,0, 2,0,0,2, 0,0,0,0])
ch, gn = api.move(b, 0, -1); assert pyl(b) == [4,0,0,0, 8,0,0,0, 4,0,0,0, 0,0,0,0] and gn == 16 and ch, pyl(b)
b = lt([2,2,0,0, 0,4,4,0, 2,0,0,2, 0,0,0,0])
ch, gn = api.move(b, 0, 1);  assert pyl(b) == [0,0,0,4, 0,0,0,8, 0,0,0,4] + [0,0,0,0] and gn == 16, pyl(b)
b = lt([2,0,0,0, 2,0,0,0, 4,0,0,0, 4,0,0,0])
ch, gn = api.move(b, -1, 0); assert pyl(b) == [4,0,0,0, 8,0,0,0, 0,0,0,0, 0,0,0,0] and gn == 12, pyl(b)
b = lt([2,0,0,0, 2,0,0,0, 4,0,0,0, 4,0,0,0])
ch, gn = api.move(b, 1, 0);  assert pyl(b) == [0,0,0,0, 0,0,0,0, 4,0,0,0, 8,0,0,0] and gn == 12, pyl(b)
b = lt([2,4,2,4, 4,2,4,2, 2,4,2,4, 4,2,4,2])
ch, gn = api.move(b, 0, -1); assert not ch and gn == 0
print('move: 4 directions + no-op OK')
# --- game_over / has_won
assert api.game_over(lt([2,4,2,4, 4,2,4,2, 2,4,2,4, 4,2,4,2])) == True
assert api.game_over(lt([2,4,2,4, 4,2,4,2, 2,4,2,4, 4,2,4,4])) == False
assert api.game_over(lt([2,4,2,4, 4,2,4,2, 2,4,2,4, 4,2,4,0])) == False
assert api.has_won(lt([0]*15 + [2048])) == True and api.has_won(lt([1024]*16)) == False
print('game_over / has_won OK')
# --- lifecycle: on_load with empty state -> new game with two tiles
rt.eval('on_load')(rt.eval('ctx'))
S = api.state()
board = pyl(S['board']); assert sum(1 for v in board if v) == 2 and all(v in (0,2,4) for v in board) and S['score'] == 0 and S['best'] == 0
rt.eval('on_draw')(); n = rt.eval('cmds'); print('draw commands (fresh board):', n); assert n < 1024
# --- random playthrough via on_input swipes; invariants
import random
on_input = rt.eval('on_input'); random.seed(1)
gest = ['swipe_left','swipe_right','swipe_up','swipe_down']
last_score = 0; keys = 0
for i in range(2000):
    if i % 7 == 0: on_input(None, rt.table_from({'type':'key','key':random.choice(['up','down']),'state':'down'})); keys += 1
    else: on_input(None, rt.table_from({'type':'touch','gesture':random.choice(gest),'x':100,'y':300}))
    S = api.state(); board = pyl(S['board'])
    assert all(v == 0 or (v & (v-1)) == 0 for v in board), board
    assert S['score'] >= last_score and S['best'] >= S['score']; last_score = S['score']
    if S['over']: break
print(f'playthrough: {i+1} inputs ({keys} key events), score {S["score"]}, best {S["best"]}, over={S["over"]}, max tile {max(board)}')
assert S['over'], 'random play should end in game over'
# worst-case draw: full board of 2048-ish tiles (max thickness) + message
S['board'] = lt([2048,1024,512,256, 128,64,32,16, 8,4,2,2048, 1024,512,256,128]); rt.execute('cmds = 0'); rt.eval('on_draw')()
n = rt.eval('cmds'); print('draw commands (worst-case board):', n); assert n < 1024
# --- confirm dialog: tap New game -> dialog; tap No -> back; tap Yes -> new game
on_input(None, rt.table_from({'type':'touch','gesture':'tap','x':240,'y':668}))
rt.execute('cmds = 0; texts = {}'); rt.eval('on_draw')(); assert any('Start a new game' in t for t in pyl(rt.eval('texts')))
on_input(None, rt.table_from({'type':'touch','gesture':'tap','x':335,'y':468}))  # No
rt.execute('texts = {}'); rt.eval('on_draw')(); assert not any('Start a new game' in t for t in pyl(rt.eval('texts')))
on_input(None, rt.table_from({'type':'touch','gesture':'tap','x':240,'y':668}))
on_input(None, rt.table_from({'type':'touch','gesture':'tap','x':145,'y':468}))  # Yes
S = api.state(); assert S['score'] == 0 and sum(1 for v in pyl(S['board']) if v) == 2 and S['best'] > 0 and not S['over']
print('confirm dialog OK; best kept after new game:', S['best'])
# --- persistence: a saved state table comes back; garbage -> new game
api.adopt_state(rt.table_from({'board': lt([2,4,8,16, 0,0,0,0, 0,0,0,0, 0,0,0,2]), 'score': 77, 'best': 500, 'won': False, 'over': False}))
S = api.state(); assert S['score'] == 77 and pyl(S['board'])[0] == 2
api.adopt_state(rt.table_from({'board': 'junk', 'best': 9}))
S = api.state(); assert S['score'] == 0 and S['best'] == 9 and sum(1 for v in pyl(S['board']) if v) == 2
# glitch guard: swipe_up at (0,0) must not move
b0 = pyl(api.state()['board']); on_input(None, rt.table_from({'type':'touch','gesture':'swipe_up','x':0,'y':0})); assert pyl(api.state()['board']) == b0
print('persistence + glitch guard OK')
print('refreshes:', dict(rt.eval('refreshes').items()))
print('ALL TESTS PASSED')
