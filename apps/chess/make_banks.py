"""Pick the Chess app's puzzle banks from the Lichess puzzle database (CC0):
https://database.lichess.org/lichess_db_puzzle.csv.zst

  python -I apps/chess/make_banks.py lichess_db_puzzle.csv.zst [--per-bank 400]

Needs `pip install zstandard`. Keeps well-tried puzzles only (rating deviation at most 80,
popularity at least 90 %, played at least 1000 times, at most 10 half-moves), spread evenly over
each bank's rating range and sorted from easiest to hardest. Writes data/<bank>.txt, one puzzle
per line: "rating|FEN|moves|themes". The FEN is the position before the opponent's move; the
moves (UCI) start with that move, then the solver's and the replies in turn.
"""
import argparse, csv, io, os, random, sys

HERE = os.path.dirname(os.path.abspath(__file__))
BANKS = [  # file, label, rating range, needed theme
    ('mate1.txt', 'Mate in 1', (600, 1500), 'mateIn1'),
    ('mate2.txt', 'Mate in 2', (800, 1900), 'mateIn2'),
    ('easy.txt', 'Easy', (800, 1200), None),
    ('medium.txt', 'Medium', (1200, 1600), None),
    ('hard.txt', 'Hard', (1600, 2000), None),
    ('expert.txt', 'Expert', (2000, 2400), None),
]
DROP = {'short', 'long', 'veryLong', 'oneMove', 'crushing', 'advantage', 'equality', 'middlegame', 'endgame',
        'opening', 'master', 'masterVsMaster', 'superGM', 'player', 'mate'}
BUCKETS = 40


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('db')
    ap.add_argument('--per-bank', type=int, default=400)
    a = ap.parse_args()
    import zstandard
    rng = random.Random(20261027)
    pools = {b[0]: [[] for _ in range(BUCKETS)] for b in BANKS}
    seen = [0] * len(BANKS)
    with open(a.db, 'rb') as f:
        text = io.TextIOWrapper(zstandard.ZstdDecompressor().stream_reader(f), encoding='utf-8', newline='')
        for row in csv.DictReader(text):
            try:
                rating, dev, pop, plays = int(row['Rating']), int(row['RatingDeviation']), int(row['Popularity']), int(row['NbPlays'])
            except ValueError:
                continue
            moves = row['Moves'].split()
            if dev > 80 or pop < 90 or plays < 1000 or len(moves) > 10 or len(moves) % 2:
                continue
            themes = row['Themes'].split()
            for k, (fname, _label, (lo, hi), need) in enumerate(BANKS):
                if not lo <= rating < hi or (need and need not in themes):
                    continue
                if not need and ('mateIn1' in themes):
                    continue                      # plain banks: no one-move mates (they have their bank)
                b = (rating - lo) * BUCKETS // (hi - lo)
                pool = pools[fname][b]
                seen[k] += 1
                item = (rating, row['FEN'], row['Moves'], ' '.join(t for t in themes if t not in DROP))
                cap = a.per_bank // BUCKETS * 3
                if len(pool) < cap:
                    pool.append(item)
                else:
                    j = rng.randrange(seen[k])
                    if j < cap:
                        pool[j % cap] = item
                break                             # a puzzle goes to one bank only
    ddir = os.path.join(HERE, 'data')
    os.makedirs(ddir, exist_ok=True)
    for fname, label, (lo, hi), _need in BANKS:
        picked = []
        per = a.per_bank // BUCKETS
        for pool in pools[fname]:
            rng.shuffle(pool)
            picked += pool[:per]
        picked.sort(key=lambda p: p[0])
        with open(os.path.join(ddir, fname), 'w', encoding='utf-8', newline='\n') as f:
            for r, fen, mv, th in picked:
                f.write(f'{r}|{fen}|{mv}|{th}\n')
        print(f'{label:10} {fname:11} {len(picked)} puzzles, ratings {picked[0][0]}..{picked[-1][0]}')


if __name__ == '__main__':
    main()
