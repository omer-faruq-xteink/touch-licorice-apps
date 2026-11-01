# Hashi (Bridges) — XTOS Licorice mini app (API 2.0)

Connect the islands with bridges. Each island's number is how many bridges end there; two islands
share one or two bridges at most; bridges run straight across the water and never cross; in the
end every island is reached from every other.

## Playing

- Tap the water between two islands: one bridge, two, none again. Or tap an island, then another
  in line with it.
- A full island gets a second ring; one with too many bridges is crossed.
- **Undo**, **Restart**, **Next**; **More**: Easy, Medium and Hard, the previous puzzle, How to
  play. The side buttons step through the bank. Your place in each level and the bridges of the
  puzzle on screen are kept.

## Banks

| bank | grid | puzzles | islands |
|---|---|---|---|
| `7x7-easy` | 7 x 7 | 200 | about 12 |
| `9x9-medium` | 9 x 9 | 200 | about 19 |
| `11x11-hard` | 11 x 11 | 200 | about 27 |

Made by `make_bank.py` (our own generator, no third-party puzzles): islands are grown one bridge
at a time, and a puzzle is kept when it has exactly one solution and reasoning finishes it, no
guessing. Easy needs only the counting of bridges an island can still take; medium also needs
the rule that a finished group of islands may not be closed off from the rest; hard needs one
step of trial. No island touches another side by side.

## Build

```bash
python -I apps/hashi/make_bank.py        # data/, 200 puzzles a bank
python -I apps/hashi/bundle.py           # tools/gamekit + src/main.lua -> index.lua
python -I apps/hashi/test_hashi.py       # offline
python xtpack.py apps/hashi
```
