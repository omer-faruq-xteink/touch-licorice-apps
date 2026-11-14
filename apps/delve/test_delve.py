"""Offline test of Delve (gamekit harness): the dungeon (every floor tile reachable, stairs or the
Amulet in the far room, nothing on a wall), today's dungeon the same on every start, steps, doors,
fights, the monster card, items picked up and tried, the torch's light, walking that stops for a
monster, save and Continue, death, the win, and the draw-command count (the map is drawn into a
layer, stubbed here).

  python -I apps/delve/test_delve.py
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), 'tools', 'gamekit'))
from harness import Game  # noqa: E402

g = Game(HERE)
A = lambda: g.api
g.L.execute("""
layer_cmds, layer_max = 0, 0          -- commands of the last rebuild, the most in one draw call
ctx.layers = { create = function(self, w, h)
  local L = { width = w, height = h }
  function L.draw(self, fn)
    local n = 0
    fn(setmetatable({}, { __index = function(_, k) return function()
      if k == 'clear' then layer_cmds, layer_max = 0, 0 end
      n = n + 1; layer_cmds = layer_cmds + 1
    end end }))
    if n > layer_max then layer_max = n end
  end
  return L
end }
""")
G = lambda: A().G()
T, MAP_Y, COLS, ROWS = int(A().T), int(A().MAP_Y), int(A().COLS), int(A().ROWS)
idx = lambda x, y: y * COLS + x + 1
def tile_xy(x, y):
    cx, cy = A().cam()
    return (x - int(cx)) * T + T // 2, MAP_Y + (y - int(cy)) * T + T // 2
def tap_tile(x, y): g.tap(*tile_xy(x, y))
def msgs(): return [str(m) for m in A().msgs().values()]
def floor_tiles():
    return [(x, y) for y in range(ROWS) for x in range(COLS) if int(G().map[idx(x, y)]) != 0]

# the dice stay under 2^31 (32-bit Lua integers on Studio and the reader) and repeat from a seed
r = A().rng(12345)
vals = [int(r.next()) for _ in range(2000)]
assert all(0 < v < 2**31 - 1 for v in vals) and len(set(vals)) == 2000
r2 = A().rng(12345)
assert [int(r2.next()) for _ in range(5)] == vals[:5]
assert int(A().rng(0).next()) == 16807                    # the minimal standard (seed 0 -> 1)
assert all(0 < int(A().mix(a, b)) < 2**31 - 1 for a in (1, 20393, 2**31 - 2, 1.7e12) for b in (1, 10, 777, 4242))

# the title
t = g.texts()
assert 'Delve' in t and 'New run' in t and "Today's dungeon (Sun 1 Nov)" in t and 'Continue' not in t, t

# dungeons: every floor tile reachable from the hero, the stairs in the far room, nothing on a wall
for seed in range(1, 41):
    A().new_run(seed * 7919, None)
    for depth in (1, 4, 7, 10):
        A().enter_level(depth)
        gm = G()
        d = A().distances(gm.map, gm.x, gm.y)
        fl = floor_tiles()
        assert all(d[idx(x, y)] is not None for x, y in fl), (seed, depth)
        stairs = [p for p in fl if int(gm.map[idx(*p)]) == 4]
        items = [(int(it.x), int(it.y), str(it.k)) for it in gm['items'].values()]
        mons = [(int(m.x), int(m.y), str(m.kind)) for m in gm.mons.values()]
        if depth < 10:
            assert len(stairs) == 1, (seed, depth, stairs)
        else:
            assert not stairs and any(k == 'amulet' for *_xy, k in items) and any(k == 'dragon' for *_xy, k in mons), (seed, items, mons)
        spots = [(x, y) for x, y, _k in items] + [(x, y) for x, y, _k in mons] + [(int(gm.x), int(gm.y))]
        assert len(spots) == len(set(spots)), (seed, depth, spots)
        assert all(int(gm.map[idx(x, y)]) in (1, 4) for x, y in spots), (seed, depth)
        assert len(mons) >= 3 and sum(1 for i in items if i[2] == 'torch') >= 1
        if depth < 10:
            assert all(int(gm.map[idx(x, y)]) != 4 for x, y, _k in items)

# today's dungeon: the same map from the same day
g.restart()
g.tap_label("Today's dungeon (Sun 1 Nov)")
assert str(A().screen()) == 'game' and int(G().daily) > 0
m1 = [int(v) for v in G().map.values()]
g.restart()
g.tap_label('Continue'); g.tap_label('Menu'); g.tap_label('Title')
g.tap_label("Today's dungeon (Sun 1 Nov)"); g.tap_label('Start')
assert [int(v) for v in G().map.values()] == m1

# a clean test level: clear monsters and items, the hero in an open spot
g.tap_label('Menu'); g.tap_label('Give up'); g.tap_label('Give up')
assert str(A().screen()) == 'end' and 'Gave up' in g.texts()
g.tap_label('New run')
assert str(A().screen()) == 'game'
gm = G()
def clear_level():
    gm = G()
    for i in range(len(gm.mons), 0, -1): gm.mons[i] = None
    for i in range(len(gm['items']), 0, -1): gm['items'][i] = None
def open_spot():
    """a floor tile with floor all around, and the hero put there"""
    gm = G()
    for x, y in floor_tiles():
        if all(int(gm.map[idx(x + a, y + b)]) == 1 for a in (-1, 0, 1) for b in (-1, 0, 1)
               if 0 <= x + a < COLS and 0 <= y + b < ROWS) and 0 < x < COLS - 1 and 0 < y < ROWS - 1:
            gm.x, gm.y = x, y
            A().fov()
            return x, y
    raise AssertionError('no open spot')
clear_level()
x, y = open_spot()

# a step: a turn, the torch burns
t0, torch0 = int(gm.turns), int(gm.torch)
tap_tile(x + 1, y)
assert (int(gm.x), int(gm.y)) == (x + 1, y) and int(gm.turns) == t0 + 1 and int(gm.torch) == torch0 - 1
tap_tile(x, y)
tap_tile(x, y)                                            # the hero: wait
assert 'You wait.' in msgs() and int(gm.turns) == t0 + 3

# taps near the hero pick a direction: off the tile's middle, or two tiles out, still one step
hx, hy = tile_xy(x, y)
g.tap(hx + T - 18, hy + 8)                                # the right-hand tile, low and to the left
assert (int(gm.x), int(gm.y)) == (x + 1, y), (int(gm.x), int(gm.y))
hx, hy = tile_xy(int(gm.x), int(gm.y))
g.tap(hx - 2 * T, hy)                                     # two tiles to the left: one step left
assert (int(gm.x), int(gm.y)) == (x, y)
# the view: 10 x 12 tiles of the 15 x 19 level, the hero kept off its edges
cx, cy = A().cam()
assert 0 <= int(cx) <= COLS - int(A().VCOLS) and 0 <= int(cy) <= ROWS - int(A().VROWS)
for px, py in [(1, 1), (COLS - 2, ROWS - 2), (7, 9)]:
    gm.x, gm.y = px, py
    A().fov()
    cx, cy = A().cam()
    assert int(cx) <= px < int(cx) + int(A().VCOLS) and int(cy) <= py < int(cy) + int(A().VROWS), (px, py, cx, cy)
gm.x, gm.y = x, y
A().fov()

# the torch's light
assert int(A().radius()) == 5
gm.torch = 60; assert int(A().radius()) == 3
gm.torch = 0; assert int(A().radius()) == 1
gm.torch = 300

# a fight: a rat next to the hero, hit until it dies
A().add_monster('rat', x + 1, y)
A().fov()
rat = A().monster_at(x + 1, y)
gm.hp, gm.max = 99, 99
for _k in range(30):
    if A().monster_at(x + 1, y) is None: break
    tap_tile(x + 1, y)
assert A().monster_at(x + 1, y) is None and int(gm.kills) == 1 and int(gm.xp) == 2, msgs()

# the monster card: a distant monster shows what a fight costs
A().add_monster('orc', x + 2, y)
A().fov()
tap_tile(x + 2, y)
t = g.texts()
assert 'Orc' in t and any(s.startswith('You hit ') for s in t) and any('HP 18 of 18' in s for s in t), t
g.tap_label('Close')
assert A().monster_at(x + 2, y) is not None
G().mons[1] = None

# items: stepped on, picked up, tried (the name is then known)
gm['items'][1] = g.L.eval('function(x, y) return { x = x, y = y, k = "potion", t = 3 } end')(x + 1, y)
gm.str = 0
nb = len(gm.bag)
tap_tile(x + 1, y)
assert len(gm.bag) == nb + 1 and 'You pick up: ' in msgs()[0], msgs()
name = str(A().item_name(gm.bag[nb + 1]))
assert name.endswith(' potion'), name
g.tap_label('Bag')
assert str(A().screen()) == 'bag' and name in g.texts()
# Back acts on its release (only the up event's answer counts): the bag closes; in the game it is
# left to the host (after a save), which offers to exit
back = lambda phase: g.L.eval(f"on_input(ctx, {{type='key', key='back', phase='{phase}'}})")
assert back('down') is True and back('up') is True and str(A().screen()) == 'game'
assert back('down') is True and back('up') is False and str(A().screen()) == 'game'
g.tap_label('Bag')
g.tap(100, 196 + nb * 42 + 20)
g.tap_label('Drink')
assert str(A().screen()) == 'game' and int(gm.str) == 1 and 'It was a potion of strength.' in msgs(), msgs()
assert str(A().item_name(g.L.eval('{ k = "potion", t = 3 }'))) == 'Potion of strength'
# a weapon: wielded, the old one goes in the bag
gm.bag[len(gm.bag) + 1] = g.L.eval('{ k = "weapon", t = 4, plus = 1 }')
A().use_item(len(gm.bag))
assert int(gm.weapon.t) == 4 and int(gm.weapon.plus) == 1 and str(A().item_name(gm.bag[len(gm.bag)])) == 'Dagger'
# gold and torches go straight to use
gm['items'][1] = g.L.eval('function(x, y) return { x = x, y = y, k = "torch" } end')(x, y)
gm.torch = 100
tap_tile(x, y)
assert int(gm.torch) == 299 and 'You light a fresh torch.' in msgs()

# a door: opened by walking into it, a turn
gm.map[idx(x + 1, y)] = 2
tap_tile(x + 1, y)
assert int(gm.map[idx(x + 1, y)]) == 3 and (int(gm.x), int(gm.y)) == (x, y) and 'The door opens.' in msgs()
tap_tile(x + 1, y)
assert (int(gm.x), int(gm.y)) == (x + 1, y)
gm.map[idx(x + 1, y)] = 1

# walking: far away, stops when a monster comes into view
clear_level()
gm.x, gm.y = x, y
for i in range(1, COLS * ROWS + 1): gm.seen[i] = True
fl = [p for p in floor_tiles() if int(gm.map[idx(*p)]) == 1]
far = max(fl, key=lambda p: (A().distances(gm.map, x, y)[idx(*p)] or 0))
A().walk_to(*far)
assert (int(gm.x), int(gm.y)) == far, ((int(gm.x), int(gm.y)), far)
A().add_monster('snake', x, y)                            # waiting where we started
G().mons[len(G().mons)].sleep = 99                        # asleep: it stays put
A().walk_to(x, y)
assert (int(gm.x), int(gm.y)) != (x, y) and int(A().monster_at(x, y) is not None)
assert abs(int(gm.x) - x) + abs(int(gm.y) - y) >= 2      # stopped once it came into view

# monsters out of sight give up after a while; a hurt rat runs off
clear_level()
x, y = open_spot()
for i in range(1, COLS * ROWS + 1): gm.vis[i] = None
A().add_monster('rat', x + 1, y)
far = max(((fx, fy) for fx, fy in floor_tiles() if int(gm.map[idx(fx, fy)]) == 1),
          key=lambda p: A().distances(gm.map, x + 1, y)[idx(*p)] or 0)
gm.x, gm.y = far
A().fov()
rat = G().mons[1]
rat.awake = True
assert not G().vis[idx(x + 1, y)]
for _k in range(6):
    A().end_turn()
assert not rat.awake, 'the rat should have given up'
gm.x, gm.y = x, y
rat.x, rat.y, rat.hp, rat.awake = x + 1, y, 1, True
A().fov()
gm.hp = 99
d0 = abs(int(rat.x) - x) + abs(int(rat.y) - y)
A().end_turn()
assert abs(int(rat.x) - x) + abs(int(rat.y) - y) > d0 or G().hp < 99, 'a hurt rat runs off (or bites when cornered)'
G().mons[1] = None

# save and Continue: the same run back
gm.hp = 37
A().save()
saved = (int(gm.x), int(gm.y), int(gm.depth), int(gm.turns), [int(v) for v in gm.map.values()],
         len(gm.bag), len(gm.mons), int(gm.weapon.t), int(gm.str), int(G().known_p[3] and 1 or 0))
g.restart()
assert 'Continue' in g.texts()
g.tap_label('Continue')
gm = G()
again = (int(gm.x), int(gm.y), int(gm.depth), int(gm.turns), [int(v) for v in gm.map.values()],
         len(gm.bag), len(gm.mons), int(gm.weapon.t), int(gm.str), int(gm.known_p[3] and 1 or 0))
assert again == saved and int(gm.hp) == 37

# stairs: down a depth
for i, v in gm.map.items():
    if int(v) == 4: gm.x, gm.y = (i - 1) % COLS, (i - 1) // COLS
A().fov()
assert 'Down' in g.texts()
g.tap_label('Down')
assert int(gm.depth) == 2 and 'You go down to depth 2.' in msgs()

# draw commands: the map is one image from the layer
g.tap(*tile_xy(int(gm.x), int(gm.y)))
assert A().layer() and g.commands() < 200, g.commands()
lc = int(g.L.eval('layer_cmds'))
for i in range(1, COLS * ROWS + 1): gm.seen[i] = True
gm.torch = 300
A().fov(); A().rebuild()
assert int(g.L.eval('layer_cmds')) > lc and int(g.L.eval('layer_cmds')) < 2500, int(g.L.eval('layer_cmds'))
assert int(g.L.eval('layer_max')) <= 600, int(g.L.eval('layer_max'))     # each call under the reader's cap
# the hero and the monsters are drawn every frame, over the layer
before = g.commands()
spot = next((int(gm.x) + a, int(gm.y) + b) for a, b in ((1, 0), (-1, 0), (0, 1), (0, -1))
            if int(gm.map[idx(int(gm.x) + a, int(gm.y) + b)]) == 1 and A().monster_at(int(gm.x) + a, int(gm.y) + b) is None)
A().add_monster('orc', *spot)
A().fov()
assert g.commands() > before and g.commands() < 400, (before, g.commands())
g.no_err()

# death: the run ends, the save goes, the stats count it
runs = int(A().stats().runs)
clear_level()
x, y = open_spot()
A().add_monster('troll', x + 1, y)
G().mons[1].awake = True
gm.hp = 1
for _k in range(40):
    if str(A().screen()) == 'end': break
    tap_tile(x, y)
assert str(A().screen()) == 'end' and any(s.startswith('You died on depth') for s in g.texts()) and 'Killed by a troll' in g.texts(), g.texts()
assert 'seed=' not in (g.store['run.txt'] or '') and int(A().stats().runs) == runs
g.tap_label('Title')
assert 'Continue' not in g.texts()

# the win: depth 10, the Amulet
g.tap_label('New run')
A().enter_level(10)
gm = G()
amu = [it for it in gm['items'].values() if str(it.k) == 'amulet'][0]
ax, ay = int(amu.x), int(amu.y)
gm.mons[1] = None
for a, b in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1), (-1, 1), (1, -1)):
    if int(gm.map[idx(ax + a, ay + b)]) == 1 and A().monster_at(ax + a, ay + b) is None:
        gm.x, gm.y = ax + a, ay + b
        break
A().fov()
wins = int(A().stats().wins)
tap_tile(ax, ay)
assert str(A().screen()) == 'end' and 'You won!' in g.texts() and int(A().stats().wins) == wins + 1, g.texts()
# Back on the end screen: to the title; there it is left to the host
assert back('down') is True and back('up') is True and str(A().screen()) == 'title'
assert back('down') is True and back('up') is False and str(A().screen()) == 'title'
g.no_err()
print('delve tests passed')
