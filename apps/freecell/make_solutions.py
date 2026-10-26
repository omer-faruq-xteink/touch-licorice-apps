"""Solve Microsoft FreeCell deals 1..N with the game's own rules (src/rules.lua, run under lupa)
and write the solutions the Hint button follows: data/sol00.txt ... (100 deals a file), one line
per deal, "deal<SPACE>move move ...". Each solution is replayed and checked before it is written.

  python -I apps/freecell/make_solutions.py [--deals 1000] [--budget 80000] [--from 1]

A move is "c3c5x2" (column 3 to column 5, two cards), "c1f" (to a free cell), "f2h" / "c4h" (to
its foundation); the cards that go home by themselves after a move (autoplay) are not listed.
A deal not solved within four times the budget gets the line "deal -" (no hint for it).
"""
import argparse, os, sys, time
from lupa import lua54

HERE = os.path.dirname(os.path.abspath(__file__))
PER_FILE = 100

CHECK = '''
function(R, d, line)
  local p = R.deal(d)
  R.autoplay(p)
  for s in line:gmatch('%S+') do
    local m = R.move_parse(p, s)
    if not m or not R.legal(p, m) then return false end
    R.apply(p, m)
    R.autoplay(p)
  end
  return R.won(p)
end
'''


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--deals', type=int, default=1000)
    ap.add_argument('--budget', type=int, default=80000)
    ap.add_argument('--from', dest='first', type=int, default=1, help='start at this deal (a multiple of 100, plus 1)')
    a = ap.parse_args()
    L = lua54.LuaRuntime(unpack_returned_tuples=True)
    R = L.execute(open(os.path.join(HERE, 'src', 'rules.lua'), encoding='utf-8').read())
    solve = L.eval('function(R, d, b) local p = R.solve(R.deal(d), b); if not p then return nil end '
                   'local t = {} for i, m in ipairs(p) do t[i] = R.move_str(m) end return table.concat(t, " ") end')
    check = L.eval(CHECK)
    ddir = os.path.join(HERE, 'data')
    os.makedirs(ddir, exist_ok=True)
    t0, lines = time.time(), []
    for d in range(a.first, a.deals + 1):
        line = solve(R, d, a.budget) or solve(R, d, a.budget * 4)
        if line is None:
            print(f'deal {d}: no solution within {a.budget * 4} positions; no hint for it', flush=True)
            lines.append(f'{d} -')
        else:
            if not check(R, d, line):
                raise SystemExit(f'deal {d}: the solution does not replay')
            lines.append(f'{d} {line}')
        if d % PER_FILE == 0 or d == a.deals:
            k = (d - 1) // PER_FILE
            with open(os.path.join(ddir, f'sol{k:02d}.txt'), 'w', encoding='utf-8', newline='\n') as f:
                f.write('\n'.join(lines) + '\n')
            print(f'deals {k * PER_FILE + 1}..{d}: {time.time() - t0:.0f} s', flush=True)
            lines = []


if __name__ == '__main__':
    main()
