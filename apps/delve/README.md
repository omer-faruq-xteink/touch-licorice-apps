# Delve — XTOS Licorice mini app (API 2.0)

A small roguelike: go down ten depths of rooms, corridors and monsters and take the Amulet from
the dragon on the last one. Every run is a new dungeon; **Today's dungeon** is the same for
everyone on a day. Death ends the run.

## Playing

- The screen shows 10 x 12 tiles of the 15 x 19 depth, 48 px each; the view moves to keep the
  hero away from its edges.
- Every step or blow is a turn, and the monsters move after it.
- **A tap near the hero** (within two tiles) steps that way: one of eight directions, so the
  finger need not hit the tile. It opens a closed door, or hits a monster standing there.
- **A tap further away** walks there over the tiles you have seen; the walk stops when a monster
  comes into view, or when you pick something up.
- **A tap on the hero** waits a turn, or goes down when you stand on the stairs.
- **A tap on a monster further away** (or holding one) shows its card: its HP, how hard it hits,
  your chance and damage, about how many blows a fight takes, and its habits. A small z means it
  has not noticed you yet.
- **Bag**: weapon, armour, level and the things you carry; tap one to drink, read, wield, wear or
  drop it. **Rest** waits until you are healed, up to 40 turns, unless a monster is in sight.
  **Down** / **To stairs** goes down, or walks to the stairs once you have seen them. **Menu**:
  How to play, Give up, Title.

## The dungeon

- **The torch** burns a point a turn and lights 5 tiles around the hero, 3 once it is below
  100, 1 when it is out; in the dark you do not heal. Torches lie on every depth (+200).
- **Potions and scrolls** are unknown until tried: their colours and labels change every run.
  Potions: healing, extra healing, strength, life, poison. Scrolls: teleport, enchant weapon,
  enchant armour, light, map, sleep.
- **Weapons** (dagger to great sword) and **armour** (leather to plate) turn up deeper down.
- **Monsters**: rat, bat, snake, goblin, skeleton, orc, troll, wraith, and the dragon on depth 10.
  A monster that has not noticed you wanders now and then; one that has may still ignore you
  (rats, bats, snakes, goblins). Out of sight it follows your trail for a few turns and then gives
  up: rats and bats soon, skeletons and wraiths hardly ever. Rats and goblins run off when badly
  hurt; goblins steal gold, trolls heal, wraiths eat your torch.
- You level up on experience: more HP, and more damage every second level.

The run is saved on every new depth, every 10 turns and when you leave; **Continue** goes on with
it. The title shows runs, wins, the deepest depth and today's best.

## How it is made

- `src/sprites.lua`: the pictures, 16 x 16 pixel art written as text (`#` ink), drawn at 3x as
  runs of rects. The icon is the hero (`tools/make_icons.py`).
- `src/main.lua`: rooms placed at random and joined by corridors, doors where a corridor goes
  straight through a wall; field of view by lines to every tile in the torch's radius; monsters
  move down a distance map to the hero. The dice are Park-Miller (every value under 2^31), so the
  dungeons are the same with the reader's 32-bit Lua integers as with 64-bit ones, and today's
  dungeon is everyone's.
- The map's still part is drawn into an off-screen layer after each turn, in calls of at most 600
  drawing commands (the reader drops what one call draws past about 1024); the monsters and the
  hero are drawn over it every frame.

## Files

| file | content |
|---|---|
| `run.txt` | the run in progress (`key=value` lines: the hero, the bag, the map, the monsters) |
| `stats.txt` | runs, wins, deepest depth, today's best |

## Test

    python -I apps/delve/test_delve.py
